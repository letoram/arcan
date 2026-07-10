// Zig port of tui/widgets/listwnd.c
// List window widget for arcan TUI.

const std = @import("std");

const c = @import("shmif_types");

const LISTWND_MAGIC: u32 = 0xfadef00e;

// Callback function types for old_handlers forwarding (struct_tui_cbcfg stores ?*anyopaque)
const ResizedFn = *const fn (?*c.struct_tui_context, usize, usize, usize, usize, ?*anyopaque) callconv(.c) void;
const ResizeFn = *const fn (?*c.struct_tui_context, usize, usize, usize, usize, ?*anyopaque) callconv(.c) void;
const SubwindowFn = *const fn (?*c.struct_tui_context, ?*c.struct_arcan_shmif_cont, u32, u8, ?*anyopaque) callconv(.c) bool;
const TickFn = *const fn (?*c.struct_tui_context, ?*anyopaque) callconv(.c) void;
const GeohintFn = *const fn (?*c.struct_tui_context, f32, f32, f32, [*c]const u8, [*c]const u8, ?*anyopaque) callconv(.c) void;
const BchunkFn = *const fn (?*c.struct_tui_context, bool, u64, c_int, [*c]const u8, ?*anyopaque) callconv(.c) void;

fn castHandler(comptime T: type, ptr: *anyopaque) T {
    return @ptrCast(@alignCast(ptr));
}

const INACTIVE_ITEM: u16 = c.LIST_SEPARATOR | c.LIST_LABEL | c.LIST_PASSIVE | c.LIST_HIDE;
const HIDDEN_ITEM: u16 = c.LIST_HIDE;

const listwnd_meta = struct {
    magic: u32,
    list: [*c]c.struct_tui_list_entry,
    list_sz: usize,
    list_pos: usize,
    list_row: usize,
    list_ofs: usize,
    entry_state: c_int,
    entry_pos: usize,
    check_ch: u32,
    sub_ch: u32,
    old_handlers: c.struct_tui_cbcfg,
    old_flags: c_int,
    orig_w: usize,
    orig_h: usize,
};

// Helper: build a tui_screen_attr using color-indexed style.
// fc_col goes into fc[0], bc_col into bc[0], extra aflags OR'd in.
fn makeAttr(fc_col: u8, bc_col: u8, extra_flags: u16) c.struct_tui_screen_attr {
    var a = std.mem.zeroes(c.struct_tui_screen_attr);
    a.unnamed_2.aflags = @intCast(c.TUI_ATTR_COLOR_INDEXED | @as(c_int, extra_flags));
    a.unnamed_0.fc[0] = fc_col;
    a.unnamed_1.bc[0] = bc_col;
    return a;
}

fn validate(T: ?*c.struct_tui_context, M: ?*?*listwnd_meta) bool {
    if (T == null) return false;

    var handlers: c.struct_tui_cbcfg = std.mem.zeroes(c.struct_tui_cbcfg);
    _ = c.arcan_tui_update_handlers(T, null, &handlers, @sizeOf(c.struct_tui_cbcfg));

    const ch: ?*listwnd_meta = @ptrCast(@alignCast(handlers.tag));
    if (ch == null or ch.?.magic != LISTWND_MAGIC)
        return false;

    if (M) |m|
        m.* = ch;

    return true;
}

fn get_visible_offset(M: *listwnd_meta) usize {
    var ofs: usize = 0;
    var i: usize = M.list_ofs;
    while (i < M.list_pos) : (i += 1) {
        if (M.list[i].attributes & HIDDEN_ITEM != 0)
            continue;
        ofs += 1;
    }
    return ofs;
}

export fn arcan_tui_listwnd_tell(T: ?*c.struct_tui_context) isize {
    var M: ?*listwnd_meta = null;
    if (!validate(T, &M))
        return -1;
    return @intCast(M.?.list_pos);
}

fn redraw(T: ?*c.struct_tui_context, M: *listwnd_meta) void {
    var c_row: usize = 0;
    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(T, &rows, &cols);

    if (rows == 0) return;

    // Safeguard: ensure we fit in the current screen
    while (true) {
        const ofs = get_visible_offset(M);
        if (ofs <= rows) break;
        M.list_ofs += 1;
    }

    const reset_def = makeAttr(c.TUI_COL_TEXT, c.TUI_COL_TEXT, 0);
    var def  = makeAttr(c.TUI_COL_LABEL, c.TUI_COL_LABEL, 0);
    var sel  = makeAttr(c.TUI_COL_HIGHLIGHT, c.TUI_COL_HIGHLIGHT, c.TUI_ATTR_BOLD);
    var inact = makeAttr(c.TUI_COL_INACTIVE, c.TUI_COL_INACTIVE, 0);

    var reset_def_var = reset_def;
    _ = c.arcan_tui_defattr(T, &reset_def_var);
    c.arcan_tui_erase_screen(T, false);

    c_row = 0;
    var remaining = rows;
    var i: usize = M.list_ofs;
    while (remaining > 0 and i < M.list_sz) : (i += 1) {
        const lattr: u16 = M.list[i].attributes;
        const label: [*c]const u8 = M.list[i].label;

        if (lattr & HIDDEN_ITEM != 0) continue;

        remaining -= 1;
        c.arcan_tui_move_to(T, 0, c_row);

        var cattr: *c.struct_tui_screen_attr = &def;
        if (i == M.list_pos) {
            cattr = &sel;
            M.list_row = c_row;
        }

        if (lattr & c.LIST_PASSIVE != 0) {
            cattr = &inact;
        }

        if (lattr & c.LIST_SEPARATOR != 0) {
            var tl = inact;
            tl.unnamed_2.aflags |= c.TUI_ATTR_BORDER_TOP;
            var col: usize = 0;
            while (col < cols) : (col += 1) {
                c.arcan_tui_write(T, 0, &tl);
            }
            c_row += 1;
            continue;
        }

        // Clear the target line with the attribute
        _ = c.arcan_tui_defattr(T, cattr);
        c.arcan_tui_erase_region(T, 0, c_row, cols, c_row, false);

        // Draw label
        c.arcan_tui_move_to(T, 1 + M.list[i].indent, c_row);
        var ofs: usize = 0;
        var vofs: usize = 0;
        while (vofs < cols - 2 and label[ofs] != 0) : (vofs += 1) {
            var end: usize = ofs + 1;
            while (label[end] != 0 and (label[end] & 0xc0) == 0x80) : (end += 1) {}
            _ = c.arcan_tui_writeu8(T, @ptrCast(&label[ofs]), end - ofs, cattr);
            ofs = end;
        }

        // Annotate with symbols
        if (lattr & c.LIST_CHECKED != 0) {
            c.arcan_tui_move_to(T, 0, c_row);
            c.arcan_tui_write(T, M.check_ch, cattr);
        }

        if (lattr & c.LIST_HAS_SUB != 0) {
            c.arcan_tui_move_to(T, cols - 1, c_row);
            c.arcan_tui_write(T, M.sub_ch, cattr);
        }

        c_row += 1;
    }

    var reset_def_var2 = reset_def;
    _ = c.arcan_tui_defattr(T, &reset_def_var2);
}

export fn arcan_tui_listwnd_setpos(T: ?*c.struct_tui_context, n: usize) void {
    var M: ?*listwnd_meta = null;
    if (!validate(T, &M)) return;

    const m = M.?;
    if (n < m.list_sz)
        m.list_pos = n;

    redraw(T, m);
}

fn select_current(T: ?*c.struct_tui_context, M: *listwnd_meta) void {
    _ = T;
    const flags: u16 = M.list[M.list_pos].attributes;
    if (flags & INACTIVE_ITEM != 0) return;
    M.entry_state = 1;
    M.entry_pos = M.list_pos;
}

fn cancel(T: ?*c.struct_tui_context, M: *listwnd_meta) void {
    _ = T;
    M.entry_state = -1;
}

fn step_page_s(T: ?*c.struct_tui_context, M: *listwnd_meta) void {
    var rows: usize = 0;
    var _cols: usize = 0;
    c.arcan_tui_dimensions(T, &rows, &_cols);

    rows = (rows >> 1) + 1;
    var c_row: usize = M.list_ofs;
    while (c_row < M.list_sz and rows > 0) : (c_row += 1) {
        if (M.list[c_row].attributes & INACTIVE_ITEM != 0)
            continue;
        rows -= 1;
    }

    if (c_row == M.list_sz or M.list_pos == M.list_sz - 1) {
        M.list_ofs = 0;
        M.list_pos = 0;
    } else {
        M.list_ofs = c_row;
        M.list_pos += 1;
    }

    // Step cursor to next sane
    var next: usize = M.list_pos;
    while (next < M.list_sz) : (next += 1) {
        if (M.list[next].attributes & INACTIVE_ITEM == 0) {
            M.list_pos = next;
            break;
        }
    }

    redraw(T, M);
}

fn step_page_n(T: ?*c.struct_tui_context, M: *listwnd_meta) void {
    _ = T;
    _ = M;
    // Not implemented in original either
}

fn step_cursor_n(T: ?*c.struct_tui_context, M: *listwnd_meta) void {
    var current = M.list_pos;
    var vis_step: usize = 0;
    while (true) {
        current = if (current > 0) current - 1 else M.list_sz - 1;
        if (M.list[current].attributes & HIDDEN_ITEM == 0)
            vis_step += 1;

        if (M.list[current].attributes & INACTIVE_ITEM == 0)
            break;

        if (current == M.list_pos) break;
    }

    if (M.list_row < vis_step) {
        step_page_n(T, M);
        return;
    }

    M.list_pos = current;
    redraw(T, M);
}

fn step_cursor_s(T: ?*c.struct_tui_context, M: *listwnd_meta) void {
    var rows: usize = 0;
    var _cols: usize = 0;
    c.arcan_tui_dimensions(T, &rows, &_cols);

    var current = M.list_pos;
    var vis_step: usize = 0;
    var prev_vis: usize = current;
    var new_page: bool = false;

    while (true) {
        current = (current + 1) % M.list_sz;
        if (M.list[current].attributes & HIDDEN_ITEM == 0) {
            vis_step += 1;
            if (vis_step + M.list_row >= rows and !new_page) {
                new_page = true;
                prev_vis = current;
            }
        }

        if (M.list[current].attributes & INACTIVE_ITEM == 0)
            break;

        if (current == M.list_pos) break;
    }

    if (new_page) {
        M.list_ofs = prev_vis;
    } else if (current < M.list_pos) {
        if (prev_vis < rows)
            prev_vis = 0;
        M.list_ofs = prev_vis;
    }

    M.list_pos = current;
    redraw(T, M);
}

export fn arcan_tui_listwnd_dirty(T: ?*c.struct_tui_context) void {
    var M: ?*listwnd_meta = null;
    if (!validate(T, &M)) return;
    redraw(T, M.?);
}

fn u8_input(T: ?*c.struct_tui_context, u8str: [*c]const u8, len: usize, tag: ?*anyopaque) callconv(.c) bool {
    // Terminate the string
    var cp: [256]u8 = undefined;
    const copy_len = if (len < 255) len else 255;
    @memcpy(cp[0..copy_len], u8str[0..copy_len]);
    cp[copy_len] = 0;

    const M: *listwnd_meta = @ptrCast(@alignCast(tag orelse return false));
    var i: usize = 0;
    while (i < M.list_sz) : (i += 1) {
        const sc = M.list[i].shortcut;
        if (sc != null and cstreql(sc, &cp)) {
            if (M.list[i].attributes & ~(INACTIVE_ITEM) != 0) {
                M.list_pos = i;
                redraw(T, M);
            }
            return true;
        }
    }
    return false;
}

export fn arcan_tui_listwnd_status(T: ?*c.struct_tui_context, out: ?*?*c.struct_tui_list_entry) bool {
    var M: ?*listwnd_meta = null;
    if (!validate(T, &M)) return false;

    const m = M.?;
    if (m.entry_state == 0) return false;

    if (m.entry_state == -1) {
        if (out) |o| o.* = null;
    } else if (m.entry_state == 1) {
        if (out) |o| o.* = &m.list[m.entry_pos];
    }

    m.entry_state = 0;
    return true;
}

// Label handlers table
const LabelEnt = struct {
    handler: *const fn (T: ?*c.struct_tui_context, M: *listwnd_meta) void,
    label: []const u8,
    descr: []const u8,
    initial: u16,
    alt: u32,
};

const labels = [_]LabelEnt{
    .{
        .handler = select_current,
        .label = "SELECT",
        .descr = "Activate/Toggle the currently selected item",
        .initial = c.TUIK_RETURN,
        .alt = c.TUIK_RIGHT,
    },
    .{
        .handler = step_cursor_s,
        .label = "NEXT",
        .descr = "Move the cursor to the next valid entry",
        .initial = c.TUIK_DOWN,
        .alt = 0,
    },
    .{
        .handler = step_cursor_n,
        .label = "PREV",
        .descr = "Move the cursor to the previous valid entry",
        .initial = c.TUIK_UP,
        .alt = 0,
    },
    .{
        .handler = step_page_s,
        .label = "NEXT_PAGE",
        .descr = "Step the list to the next page",
        .initial = c.TUIK_PAGEDOWN,
        .alt = 0,
    },
    .{
        .handler = step_page_n,
        .label = "PREV_PAGE",
        .descr = "Step the list to the previous page",
        .initial = c.TUIK_PAGEUP,
        .alt = 0,
    },
    .{
        .handler = cancel,
        .label = "CANCEL",
        .descr = "Exit the list view state",
        .initial = c.TUIK_ESCAPE,
        .alt = c.TUIK_LEFT,
    },
};

fn on_label_input(T: ?*c.struct_tui_context, label: [*c]const u8, active: bool, tag: ?*anyopaque) callconv(.c) bool {
    if (!active) return true;

    const M: *listwnd_meta = @ptrCast(@alignCast(tag orelse return false));

    for (&labels) |*entry| {
        if (cstreql_lit(label, entry.label)) {
            entry.handler(T, M);
            return true;
        }
    }
    return false;
}

fn key_input(T: ?*c.struct_tui_context, keysym: u32, scancode: u8, mods: u16, subid: u16, tag: ?*anyopaque) callconv(.c) void {
    _ = scancode;
    _ = mods;
    _ = subid;
    const M: *listwnd_meta = @ptrCast(@alignCast(tag orelse return));

    for (&labels) |*entry| {
        if ((keysym != 0 and keysym == entry.alt) or keysym == entry.initial) {
            entry.handler(T, M);
            return;
        }
    }
}

export fn arcan_tui_listwnd_release(T: ?*c.struct_tui_context) void {
    var M: ?*listwnd_meta = null;
    if (!validate(T, &M)) return;

    const m = M.?;
    _ = c.arcan_tui_set_flags(T, m.old_flags);
    _ = c.arcan_tui_update_handlers(T, &m.old_handlers, null, @sizeOf(c.struct_tui_cbcfg));
    c.arcan_tui_reset_labels(T);

    const orig_w = m.orig_w;
    const orig_h = m.orig_h;

    m.magic = 0xdeadbeef;

    c.arcan_tui_wndhint(T, null, c.struct_tui_constraints{
        .min_cols = -1,
        .min_rows = -1,
        .max_cols = @intCast(orig_w),
        .max_rows = @intCast(orig_h),
        .anch_row = -1,
        .anch_col = -1,
        .hide = 0,
        .embed = 0,
    });

    std.c.free(m);
}

fn on_resized(T: ?*c.struct_tui_context, neww: usize, newh: usize, col: usize, row: usize, t: ?*anyopaque) callconv(.c) void {
    const M: *listwnd_meta = @ptrCast(@alignCast(t orelse return));
    redraw(T, M);
    if (M.old_handlers.resized) |f|
        castHandler(ResizedFn, f)(T, neww, newh, col, row, M.old_handlers.tag);
}

fn on_subwindow(T: ?*c.struct_tui_context, conn: ?*c.struct_arcan_shmif_cont, id: u32, @"type": u8, t: ?*anyopaque) callconv(.c) bool {
    const M: *listwnd_meta = @ptrCast(@alignCast(t orelse return false));
    if (M.old_handlers.subwindow) |f|
        return castHandler(SubwindowFn, f)(T, conn, id, @"type", M.old_handlers.tag);
    return false;
}

fn on_resize(T: ?*c.struct_tui_context, neww: usize, newh: usize, col: usize, row: usize, t: ?*anyopaque) callconv(.c) void {
    const M: *listwnd_meta = @ptrCast(@alignCast(t orelse return));
    if (M.old_handlers.resize) |f|
        castHandler(ResizeFn, f)(T, neww, newh, col, row, M.old_handlers.tag);
}

fn on_tick(T: ?*c.struct_tui_context, t: ?*anyopaque) callconv(.c) void {
    const M: *listwnd_meta = @ptrCast(@alignCast(t orelse return));
    if (M.old_handlers.tick) |f|
        castHandler(TickFn, f)(T, M.old_handlers.tag);
}

fn on_geohint(T: ?*c.struct_tui_context, lat: f32, longit: f32, elev: f32, cnt: [*c]const u8, lang: [*c]const u8, t: ?*anyopaque) callconv(.c) void {
    const M: *listwnd_meta = @ptrCast(@alignCast(t orelse return));
    if (M.old_handlers.geohint) |f|
        castHandler(GeohintFn, f)(T, lat, longit, elev, cnt, lang, M.old_handlers.tag);
}

fn on_bchunk(T: ?*c.struct_tui_context, input: bool, size: u64, fd: c_int, msg: [*c]const u8, tag: ?*anyopaque) callconv(.c) void {
    const M: *listwnd_meta = @ptrCast(@alignCast(tag orelse return));
    if (M.old_handlers.bchunk) |f|
        castHandler(BchunkFn, f)(T, input, size, fd, msg, M.old_handlers.tag);
}

fn on_mouse_motion(T: ?*c.struct_tui_context, relative: bool, mouse_x: c_int, mouse_y: c_int, modifiers: c_int, tag: ?*anyopaque) callconv(.c) void {
    const M: *listwnd_meta = @ptrCast(@alignCast(tag orelse return));

    if (relative) {
        if (mouse_y == 0) return;
        if (mouse_y < 0) {
            var i: c_int = mouse_y;
            while (i != 0) : (i += 1)
                step_cursor_n(T, M);
        } else {
            var i: c_int = mouse_y;
            while (i != 0) : (i -= 1)
                step_cursor_s(T, M);
        }
        return;
    }
    _ = mouse_x;
    _ = modifiers;

    var idx: usize = M.list_ofs;
    var yp: usize = 0;
    while (idx < M.list_sz) : (idx += 1) {
        if (M.list[idx].attributes & HIDDEN_ITEM != 0) continue;

        if (yp == @as(usize, @intCast(mouse_y))) {
            if (M.list_pos != idx) {
                M.list_pos = idx;
                redraw(T, M);
            }
            break;
        }
        yp += 1;
    }
}

fn on_mouse_button(T: ?*c.struct_tui_context, last_x: c_int, last_y: c_int, button: c_int, active: bool, modifiers: c_int, tag: ?*anyopaque) callconv(.c) void {
    _ = last_x;
    _ = last_y;
    _ = modifiers;
    const M: *listwnd_meta = @ptrCast(@alignCast(tag orelse return));
    if (!active) return;

    if (button == c.TUIBTN_LEFT) {
        select_current(T, M);
    } else if (button == c.TUIBTN_RIGHT) {
        cancel(T, M);
    } else if (button == c.TUIBTN_MIDDLE) {
        step_page_s(T, M);
    } else if (button == c.TUIBTN_WHEEL_UP) {
        step_cursor_n(T, M);
    } else if (button == c.TUIBTN_WHEEL_DOWN) {
        step_cursor_s(T, M);
    }
}

fn on_recolor(T: ?*c.struct_tui_context, t: ?*anyopaque) callconv(.c) void {
    const M: *listwnd_meta = @ptrCast(@alignCast(t orelse return));
    redraw(T, M);
}

fn on_label_query(T: ?*c.struct_tui_context, index: usize, country: [*c]const u8, lang: [*c]const u8, dstlbl: [*c]c.struct_tui_labelent, t: ?*anyopaque) callconv(.c) bool {
    _ = T;
    _ = country;
    _ = lang;
    _ = t;

    if (labels.len < index + 1) return false;

    const entry = &labels[index];
    const dst = &dstlbl[0];
    dst.* = std.mem.zeroes(c.struct_tui_labelent);
    copyStr(&dst.label, entry.label);
    copyStr(&dst.descr, entry.descr);
    dst.initial = entry.initial;
    return true;
}

export fn arcan_tui_listwnd_setup(T: ?*c.struct_tui_context, L: [*c]c.struct_tui_list_entry, n_entries: usize) bool {
    if (T == null or L == null or n_entries == 0) return false;

    const meta: *listwnd_meta = @ptrCast(@alignCast(std.c.malloc(@sizeOf(listwnd_meta)) orelse return false));
    meta.* = std.mem.zeroes(listwnd_meta);
    meta.magic = LISTWND_MAGIC;
    meta.list_sz = n_entries;
    meta.list = L;
    meta.list_pos = 0;
    meta.list_row = 0;
    meta.list_ofs = 0;
    meta.entry_state = 0;

    meta.old_flags = c.arcan_tui_set_flags(T, c.TUI_ALTERNATE | c.TUI_HIDE_CURSOR | c.TUI_MOUSE);

    var cbcfg = std.mem.zeroes(c.struct_tui_cbcfg);
    cbcfg.tag = @ptrCast(meta);
    cbcfg.resize = @ptrCast(@constCast(&on_resize));
    cbcfg.resized = @ptrCast(@constCast(&on_resized));
    cbcfg.recolor = @ptrCast(@constCast(&on_recolor));
    cbcfg.tick = @ptrCast(@constCast(&on_tick));
    cbcfg.geohint = @ptrCast(@constCast(&on_geohint));
    cbcfg.query_label = @ptrCast(@constCast(&on_label_query));
    cbcfg.input_label = @ptrCast(@constCast(&on_label_input));
    cbcfg.input_key = @ptrCast(@constCast(&key_input));
    cbcfg.input_mouse_motion = @ptrCast(@constCast(&on_mouse_motion));
    cbcfg.input_mouse_button = @ptrCast(@constCast(&on_mouse_button));
    cbcfg.input_utf8 = @ptrCast(@constCast(&u8_input));
    cbcfg.subwindow = @ptrCast(@constCast(&on_subwindow));
    cbcfg.bchunk = @ptrCast(@constCast(&on_bchunk));

    // MODIFIER LETTER RIGHT ARROWHEAD U+02c3
    meta.sub_ch = if (c.arcan_tui_hasglyph(T, 0x02c3)) 0x02c3 else '>';

    _ = c.arcan_tui_update_handlers(T, &cbcfg, &meta.old_handlers, @sizeOf(c.struct_tui_cbcfg));

    // Compute max width from labels
    var max_w: usize = 0;
    var ei: usize = 0;
    while (ei < n_entries) : (ei += 1) {
        var j: usize = 0;
        var w: usize = 0;
        while (L[ei].label[j] != 0) {
            if ((L[ei].label[j] & 0xc0) != 0x80)
                w += 1;
            j += 1;
        }
        if (w > max_w) max_w = w;
    }

    var orig_h: usize = 0;
    var orig_w: usize = 0;
    c.arcan_tui_dimensions(T, &orig_h, &orig_w);
    meta.orig_h = orig_h;
    meta.orig_w = orig_w;

    c.arcan_tui_wndhint(T, null, c.struct_tui_constraints{
        .min_cols = -1,
        .min_rows = -1,
        .max_cols = @intCast(max_w + 4),
        .max_rows = @intCast(n_entries + 1),
        .anch_row = -1,
        .anch_col = -1,
        .hide = 0,
        .embed = 0,
    });

    c.arcan_tui_reset_labels(T);
    redraw(T, meta);

    return true;
}

// Helper: compare C string to a Zig string literal
fn cstreql_lit(a: [*c]const u8, b: []const u8) bool {
    if (a == null) return false;
    var i: usize = 0;
    while (i < b.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return a[i] == 0;
}

fn cstreql(a: [*c]const u8, b: [*c]const u8) bool {
    if (a == null or b == null) return a == b;
    var i: usize = 0;
    while (a[i] != 0 and b[i] != 0) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return a[i] == b[i];
}

fn copyStr(dst: anytype, src: []const u8) void {
    const dst_slice: []u8 = dst;
    const copy_len = @min(src.len, dst_slice.len - 1);
    @memcpy(dst_slice[0..copy_len], src[0..copy_len]);
    dst_slice[copy_len] = 0;
}
