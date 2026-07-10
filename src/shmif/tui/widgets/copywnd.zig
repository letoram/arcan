// Zig port of tui/widgets/copywnd.c
// Copy window widget for arcan TUI — spawns a background thread.

const std = @import("std");

const c = @import("shmif_types");

// struct_tui_context is opaque in Zig. The original C copywnd accesses
// internal fields directly; here we use the public API instead.

// flag_cursor: force a cursor redraw.  The C version touches dirty flags;
// we approximate via arcan_tui_refresh (returns -1/EINVAL on closed ctx).
fn flag_cursor(ctx: ?*c.struct_tui_context) void {
    _ = c.arcan_tui_refresh(ctx);
}

fn tui_dims(ctx: ?*c.struct_tui_context) struct { cols: usize, rows: usize } {
    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(ctx, &rows, &cols);
    return .{ .cols = cols, .rows = rows };
}

const color_palette = [_][3]u8{
    .{ 0, 0, 0 }, // black
    .{ 205, 0, 0 }, // red
    .{ 0, 205, 0 }, // green
    .{ 205, 205, 0 }, // yellow
    .{ 0, 0, 238 }, // blue
    .{ 205, 0, 205 }, // magenta
    .{ 0, 205, 205 }, // cyan
    .{ 229, 229, 229 }, // light grey
    .{ 127, 127, 127 }, // dark grey
    .{ 255, 0, 0 }, // light red
    .{ 0, 255, 0 }, // light green
    .{ 255, 255, 0 }, // light yellow
    .{ 92, 92, 255 }, // light blue
    .{ 255, 0, 255 }, // light magenta
    .{ 0, 255, 255 }, // light cyan
    .{ 255, 255, 255 }, // white
    .{ 229, 229, 229 }, // light grey
    .{ 0, 0, 0 }, // black
};

const copywnd_context = struct {
    tui: ?*c.struct_tui_context,
    acon: ?*c.struct_arcan_shmif_cont,
    parent: ?*c.struct_tui_context,
    done: std.atomic.Value(c_int),

    invalidated: bool,
    edit_mode: bool,
    bgc: [3]u8,
    color_index: u8,

    base_buffer_sz: usize,
    base_buffer: ?[*]u8,

    edit_buffer_sz: usize,
    edit_buffer: ?[*]u8,

    in_select: c_int,
    last_x: c_int,
    last_y: c_int,
    last_mx: c_int,
    last_my: c_int,
};

fn copywnd_resized(ctx: ?*c.struct_tui_context, neww: usize, newh: usize, col: usize, row: usize, t: ?*anyopaque) callconv(.c) void {
    _ = neww;
    _ = newh;
    _ = col;
    _ = row;
    const cctx: *copywnd_context = @ptrCast(@alignCast(t orelse return));
    const tui = cctx.tui orelse return;
    const dims = tui_dims(tui);

    c.arcan_tui_erase_screen(ctx, false);

    if (cctx.base_buffer) |bb| {
        _ = c.arcan_tui_tunpack(tui,
            bb, cctx.base_buffer_sz,
            0, 0, dims.cols, dims.rows);
    }

    if (cctx.edit_buffer) |eb| {
        _ = c.arcan_tui_tunpack(tui,
            eb, cctx.edit_buffer_sz,
            0, 0, dims.cols, dims.rows);
    }
}

fn copywnd_set_labels(ctx: ?*c.struct_tui_context, t: *copywnd_context) void {
    _ = t;
    var ev = c.struct_arcan_event.zeroes();
    ev.category().* = c.EVENT_EXTERNAL;
    ev.ext().kind = c.EVENT_EXTERNAL_LABELHINT;
    ev.ext().labelhint().idatatype = c.EVENT_IDATATYPE_DIGITAL;
    copyStrFixed(&ev.ext().labelhint().label, "EDIT_TOGGLE");
    copyStrFixed(&ev.ext().labelhint().descr, "Toggle highlight/edit mode");
    ev.ext().labelhint().initial = c.TUIK_ESCAPE;
    ev.ext().labelhint().modifiers = c.TUIM_LMETA;
    // U+270E vsym
    ev.ext().labelhint().vsym[0] = 0xe2;
    ev.ext().labelhint().vsym[1] = 0x9c;
    ev.ext().labelhint().vsym[2] = 0x8e;
    if (c.arcan_tui_get_conn(ctx)) |conn|
        _ = c.arcan_shmif_enqueue(conn, &ev);
}

fn copywnd_set_ident(ctx: ?*c.struct_tui_context, tag: *copywnd_context) void {
    var buf: [20]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "Copy{s}", .{if (tag.edit_mode) ":Edit" else ""}) catch return;
    c.arcan_tui_ident(ctx, s.ptr);
}

fn copywnd_utf8(ctx: ?*c.struct_tui_context, u8str: [*c]const u8, len: usize, t: ?*anyopaque) callconv(.c) bool {
    const cctx: *copywnd_context = @ptrCast(@alignCast(t orelse return false));
    if (cctx.tui == null or !cctx.edit_mode) return false;

    // Ignore backspace, CR, LF — let symbol input dominate
    if (u8str[0] == 8 or u8str[0] == '\r' or u8str[0] == '\n') return false;

    if (u8str[0] != 0) {
        if (c.arcan_tui_writeu8(ctx, @ptrCast(u8str), len, null) > 0) {
            return true;
        }
    }
    return false;
}

fn get_cursor_cell(ctx: ?*c.struct_tui_context) c.struct_tui_cell {
    var cx: usize = 0;
    var cy: usize = 0;
    c.arcan_tui_cursorpos(ctx, &cx, &cy);
    return c.arcan_tui_getxy(ctx, cx, cy, true);
}

fn copywnd_mark_cell(ctx: ?*c.struct_tui_context, tag: *copywnd_context) void {
    const cell = get_cursor_cell(ctx);
    var attr = cell.attr;

    // Remove the indexed state
    if ((attr.unnamed_2.aflags & c.TUI_ATTR_COLOR_INDEXED) != 0) {
        c.arcan_tui_get_color(ctx, @intCast(attr.unnamed_1.bc[0]), &attr.unnamed_1.bc);
        c.arcan_tui_get_color(ctx, @intCast(attr.unnamed_0.fc[0]), &attr.unnamed_0.fc);
        attr.unnamed_2.aflags &= ~@as(u16, c.TUI_ATTR_COLOR_INDEXED);
    }

    attr.unnamed_1.bc[0] = color_palette[tag.color_index][0];
    attr.unnamed_1.bc[1] = color_palette[tag.color_index][1];
    attr.unnamed_1.bc[2] = color_palette[tag.color_index][2];

    if (cell.ch == 0) {
        _ = c.arcan_tui_writeu8(ctx, &[_]u8{' '}, 1, &attr);
    } else {
        c.arcan_tui_write(ctx, cell.ch, &attr);
    }
    tag.invalidated = true;
}

fn copywnd_color(ctx: ?*c.struct_tui_context, cctx: *copywnd_context) void {
    cctx.bgc[0] = color_palette[cctx.color_index][0];
    cctx.bgc[1] = color_palette[cctx.color_index][1];
    cctx.bgc[2] = color_palette[cctx.color_index][2];
    c.arcan_tui_set_color(ctx, c.TUI_COL_CURSOR, &cctx.bgc);
    flag_cursor(ctx);
}

fn copywnd_step_mouse(ctx: ?*c.struct_tui_context, tag: *copywnd_context) void {
    switch (tag.in_select) {
        1 => copywnd_mark_cell(ctx, tag),
        2 => tag.invalidated = true,
        3 => {},
        else => return,
    }
}

fn copywnd_key(ctx: ?*c.struct_tui_context, keysym: u32, scancode: u8, mods: u16, subid: u16, tag: ?*anyopaque) callconv(.c) void {
    _ = scancode;
    _ = subid;
    const cctx: *copywnd_context = @ptrCast(@alignCast(tag orelse return));
    _ = ctx orelse return;

    var cx: usize = 0;
    var cy: usize = 0;
    c.arcan_tui_cursorpos(ctx, &cx, &cy);

    if (keysym == c.TUIK_UP) {
        if ((mods & (c.TUIM_LSHIFT | c.TUIM_RSHIFT)) != 0) {
            copywnd_mark_cell(ctx, cctx);
        } else {
            c.arcan_tui_move_to(ctx, cx, if (cy > 0) cy - 1 else 0);
        }
    } else if (keysym == c.TUIK_DOWN) {
        if ((mods & (c.TUIM_LSHIFT | c.TUIM_RSHIFT)) != 0) {
            copywnd_mark_cell(ctx, cctx);
        } else {
            c.arcan_tui_move_to(ctx, cx, cy + 1);
        }
    } else if (keysym == c.TUIK_LEFT) {
        if ((mods & (c.TUIM_LSHIFT | c.TUIM_RSHIFT)) != 0) {
            copywnd_mark_cell(ctx, cctx);
        } else {
            c.arcan_tui_move_to(ctx, if (cx > 0) cx - 1 else 0, cy);
        }
    } else if (keysym == c.TUIK_RIGHT) {
        if ((mods & (c.TUIM_LSHIFT | c.TUIM_RSHIFT)) != 0) {
            copywnd_mark_cell(ctx, cctx);
        } else {
            c.arcan_tui_move_to(ctx, cx + 1, cy);
        }
    } else if (keysym == c.TUIK_RETURN) {
        cctx.last_my += 1;
        c.arcan_tui_move_to(ctx, @intCast(cctx.last_mx), @intCast(cctx.last_my));
        flag_cursor(ctx);
    } else if (keysym == c.TUIK_BACKSPACE or keysym == c.TUIK_CLEAR) {
        const def = c.arcan_tui_defattr(ctx, null);
        _ = c.arcan_tui_writeu8(ctx, &[_]u8{' '}, 1, &def);
        cctx.invalidated = true;
    } else if (keysym == c.TUIK_ESCAPE) {
        const cell = get_cursor_cell(ctx);
        cctx.bgc[0] = cell.attr.unnamed_1.bc[0];
        cctx.bgc[1] = cell.attr.unnamed_1.bc[1];
        cctx.bgc[2] = cell.attr.unnamed_1.bc[2];
        c.arcan_tui_set_color(ctx, c.TUI_COL_CURSOR, &cctx.bgc);
        flag_cursor(ctx);
    } else if (keysym >= c.TUIK_F1 and keysym <= c.TUIK_F10) {
        cctx.color_index = @intCast(keysym - c.TUIK_F1);
        copywnd_color(ctx, cctx);
    }
}

fn copywnd_mouse_motion(ctx: ?*c.struct_tui_context, relative: bool, x: c_int, y: c_int, modifiers: c_int, t: ?*anyopaque) callconv(.c) void {
    _ = relative;
    _ = modifiers;
    const cctx: *copywnd_context = @ptrCast(@alignCast(t orelse return));
    if (cctx.tui == null or !cctx.edit_mode) return;

    const dx = x - cctx.last_x;
    const dy = y - cctx.last_y;

    if (cctx.in_select > 0 and (dx != 0 or dy != 0)) {
        if (dx > 1) {
            var d = dx;
            while (d > 0) : (d -= 1) {
                c.arcan_tui_move_to(ctx, @intCast(x - d), @intCast(y));
                copywnd_step_mouse(ctx, cctx);
            }
        }
        if (dx < -1) {
            var d = dx;
            while (d < 0) : (d += 1) {
                c.arcan_tui_move_to(ctx, @intCast(x + d), @intCast(y));
                copywnd_step_mouse(ctx, cctx);
            }
        }
        if (dy > 1) {
            var d = dy;
            while (d > 0) : (d -= 1) {
                c.arcan_tui_move_to(ctx, @intCast(x), @intCast(y - d));
                copywnd_step_mouse(ctx, cctx);
            }
        }
        if (dy < -1) {
            var d = dy;
            while (d < 0) : (d += 1) {
                c.arcan_tui_move_to(ctx, @intCast(x), @intCast(y + d));
                copywnd_step_mouse(ctx, cctx);
            }
        }

        cctx.last_x = x;
        cctx.last_y = y;

        c.arcan_tui_move_to(ctx, @intCast(x), @intCast(y));
        copywnd_step_mouse(ctx, cctx);
    }
    c.arcan_tui_move_to(ctx, @intCast(x), @intCast(y));
    cctx.last_mx = x;
    cctx.last_my = y;
}

fn copywnd_mouse_button(ctx: ?*c.struct_tui_context, last_x: c_int, last_y: c_int, button: c_int, active: bool, modifiers: c_int, t: ?*anyopaque) callconv(.c) void {
    _ = modifiers;
    const cctx: *copywnd_context = @ptrCast(@alignCast(t orelse return));
    if (cctx.tui == null or !cctx.edit_mode) return;

    if (cctx.in_select == button) {
        if (active) return; // contact bounce or repeat
        cctx.in_select = -1;
        return;
    }

    if (!active) return;

    if (button <= 3) {
        cctx.in_select = button;
        cctx.last_x = last_x;
        cctx.last_y = last_y;
        copywnd_step_mouse(ctx, cctx);
    } else {
        // Wheel mapped to color
        if (button == 4) {
            cctx.color_index = if (cctx.color_index > 0)
                cctx.color_index - 1
            else
                @intCast(color_palette.len - 1);
            if (ctx) |tctx| copywnd_color(tctx, cctx);
        } else if (button == 5) {
            cctx.color_index = if (cctx.color_index > 0)
                cctx.color_index - 1
            else
                @intCast(color_palette.len - 1);
            if (ctx) |tctx| copywnd_color(tctx, cctx);
        }
    }
}

fn copywnd_label(ctx: ?*c.struct_tui_context, label: [*c]const u8, active: bool, t: ?*anyopaque) callconv(.c) bool {
    const cctx: *copywnd_context = @ptrCast(@alignCast(t orelse return false));
    if (cctx.tui == null) return false;
    _ = ctx orelse return false;

    if (cstreql_lit(label, "EDIT_TOGGLE")) {
        if (!active) return true;

        if (cctx.edit_mode) {
            // mouse_forward is internal; toggle mouse via flags instead
            cctx.edit_mode = false;
            _ = c.arcan_tui_set_flags(ctx, c.TUI_HIDE_CURSOR);
        } else {
            cctx.edit_mode = true;
            _ = c.arcan_tui_set_flags(ctx, c.TUI_MOUSE);
        }
        copywnd_set_ident(ctx, cctx);
        return true;
    }
    return false;
}

fn copywnd_reset(ctx: ?*c.struct_tui_context, level: c_int, tag: ?*anyopaque) callconv(.c) void {
    _ = level;
    const cctx: *copywnd_context = @ptrCast(@alignCast(tag orelse return));
    if (ctx == null) return;
    copywnd_set_labels(ctx, cctx);
    copywnd_set_ident(ctx, cctx);
}

fn copywnd_resize(ctx: ?*c.struct_tui_context, neww: usize, newh: usize, col: usize, row: usize, t: ?*anyopaque) callconv(.c) void {
    _ = neww;
    _ = newh;
    _ = col;
    _ = row;
    const cctx: *copywnd_context = @ptrCast(@alignCast(t orelse return));
    if (cctx.tui == null) return;

    if (cctx.edit_buffer) |eb| {
        std.c.free(eb);
        cctx.edit_buffer = null;
    }

    _ = c.arcan_tui_tpack(ctx, @ptrCast(&cctx.edit_buffer), &cctx.edit_buffer_sz);
}

fn copywnd_thread_proc(in: ?*anyopaque) callconv(.c) ?*anyopaque {
    const cctx: *copywnd_context = @ptrCast(@alignCast(in orelse return null));

    var cbs = std.mem.zeroes(c.struct_tui_cbcfg);
    cbs.tag = @ptrCast(cctx);
    cbs.resize = @ptrCast(@constCast(&copywnd_resize));
    cbs.resized = @ptrCast(@constCast(&copywnd_resized));
    cbs.input_label = @ptrCast(@constCast(&copywnd_label));
    cbs.input_mouse_motion = @ptrCast(@constCast(&copywnd_mouse_motion));
    cbs.input_mouse_button = @ptrCast(@constCast(&copywnd_mouse_button));
    cbs.input_utf8 = @ptrCast(@constCast(&copywnd_utf8));
    cbs.input_key = @ptrCast(@constCast(&copywnd_key));
    cbs.reset = @ptrCast(@constCast(&copywnd_reset));

    cctx.tui = c.arcan_tui_setup(
        @ptrCast(cctx.acon),
        cctx.parent,
        &cbs,
        @sizeOf(c.struct_tui_cbcfg),
    );

    cctx.done.store(1, .release);

    if (cctx.tui) |tui| {
        copywnd_reset(tui, 1, @ptrCast(cctx));
        // Hide cursor (cursor_hard_off is internal; use flags)
        _ = c.arcan_tui_set_flags(tui, c.TUI_HIDE_CURSOR);

        if (cctx.base_buffer) |bb| {
            const dims = tui_dims(tui);
            _ = c.arcan_tui_tunpack(tui,
                bb, cctx.base_buffer_sz,
                0, 0, dims.cols, dims.rows);
        }

        while (true) {
            var tui_ptr = tui;
            const res = c.arcan_tui_process(@ptrCast(&tui_ptr), 1, null, 0, -1);

            if (res.errc < c.TUI_ERRC_OK or res.bad != 0) break;

            if (-1 == c.arcan_tui_refresh(tui) and std.c._errno().* == c.EINVAL) break;
        }

        c.arcan_tui_destroy(tui, null);
    }

    std.c.free(cctx);
    return null;
}

export fn tui_copywnd(src: ?*c.struct_tui_context, acon: ?*c.struct_arcan_shmif_cont) void {
    if (acon == null or src == null) return;

    const cctx: *copywnd_context = @ptrCast(@alignCast(std.c.malloc(@sizeOf(copywnd_context)) orelse return));
    cctx.* = std.mem.zeroes(copywnd_context);
    cctx.parent = src;
    cctx.acon = acon;
    cctx.done = std.atomic.Value(c_int).init(0);

    _ = c.arcan_tui_tpack(src, @ptrCast(&cctx.base_buffer), &cctx.base_buffer_sz);

    // Make erase color match the cursor — use API function instead of direct struct access
    c.arcan_tui_get_color(src, c.TUI_COL_CURSOR, &cctx.bgc);

    var bgattr: c.pthread_attr_t = undefined;
    _ = c.pthread_attr_init(&bgattr);
    _ = c.pthread_attr_setdetachstate(&bgattr, c.PTHREAD_CREATE_DETACHED);

    var bgthr: c.pthread_t = undefined;

    // Lock source context so copywnd can see a consistent state
    // Note: struct_tui_context is opaque, cannot access .acon directly
    // Use arcan_tui_conn to get the shmif_cont if needed
    if (c.arcan_tui_get_conn(src)) |conn| {
        _ = c.arcan_shmif_lock(conn);
    }

    if (0 != c.pthread_create(&bgthr, &bgattr, copywnd_thread_proc, cctx)) {
        std.c.free(cctx);
        return;
    }

    // Spinlock until the thread has set done = 1 (past setup)
    while (cctx.done.load(.acquire) == 0) {
        std.atomic.spinLoopHint();
    }
}

// Helpers
fn cstreql_lit(a: [*c]const u8, b: []const u8) bool {
    if (a == null) return false;
    var i: usize = 0;
    while (i < b.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return a[i] == 0;
}

fn copyStrFixed(dst: anytype, src: []const u8) void {
    const sz = @sizeOf(@TypeOf(dst.*));
    const copy_len = @min(src.len, sz - 1);
    @memcpy(dst[0..copy_len], src[0..copy_len]);
    dst[copy_len] = 0;
}
