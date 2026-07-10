// Zig port of tui/widgets/readline.c
// Readline/linenoise replacement for arcan TUI.

const std = @import("std");

const c = @import("shmif_types");

const READLINE_MAGIC: u32 = 0xfefef00d;

// Callback function types for old_handlers forwarding (struct_tui_cbcfg stores ?*anyopaque)
const RecolorFn = *const fn (?*c.struct_tui_context, ?*anyopaque) callconv(.c) void;
const Utf8PasteFn = *const fn (?*c.struct_tui_context, [*c]const u8, usize, bool, ?*anyopaque) callconv(.c) void;
const InputKeyFn = *const fn (?*c.struct_tui_context, u32, u8, u16, u16, ?*anyopaque) callconv(.c) void;
const InputMouseMotionFn = *const fn (?*c.struct_tui_context, bool, c_int, c_int, c_int, ?*anyopaque) callconv(.c) void;
const InputMouseButtonFn = *const fn (?*c.struct_tui_context, c_int, c_int, c_int, bool, c_int, ?*anyopaque) callconv(.c) void;
const StateFn = *const fn (?*c.struct_tui_context, bool, c_int, ?*anyopaque) callconv(.c) void;
const GeohintFn = *const fn (?*c.struct_tui_context, f32, f32, f32, [*c]const u8, [*c]const u8, ?*anyopaque) callconv(.c) void;
const ResizedFn = *const fn (?*c.struct_tui_context, usize, usize, usize, usize, ?*anyopaque) callconv(.c) void;
const InputLabelFn = *const fn (?*c.struct_tui_context, [*c]const u8, bool, ?*anyopaque) callconv(.c) bool;
const SubwindowFn = *const fn (?*c.struct_tui_context, ?*c.struct_arcan_shmif_cont, u32, u8, ?*anyopaque) callconv(.c) bool;
const QueryLabelFn = *const fn (?*c.struct_tui_context, usize, [*c]const u8, [*c]const u8, [*c]c.struct_tui_labelent, ?*anyopaque) callconv(.c) bool;
const ResetFn = *const fn (?*c.struct_tui_context, c_int, ?*anyopaque) callconv(.c) void;

fn castHandler(comptime T: type, ptr: *anyopaque) T {
    return @ptrCast(@alignCast(ptr));
}

// Shared between all readline instances (interactive toggle for completion hints)
var draw_completion_hint: bool = false;

const readline_meta = struct {
    magic: u32,
    opts: c.struct_tui_readline_opts,
    in_refresh: bool,

    // re-built on resize
    start_col: usize,
    stop_col: usize,
    start_row: usize,
    stop_row: usize,

    work: ?[*]u8, // UTF-8
    work_ofs: usize, // in bytes, code-point boundary aligned
    work_len: usize, // in code-points
    work_sz: usize, // in bytes
    cursor: usize, // offset in bytes from start to cursor

    // -1 as ok, modified by verify callback
    broken_offset: isize,

    // suggestion && tab completion feature (externally managed)
    current_suggestion: ?[*:0]const u8,
    show_completion: bool,
    completion: ?[*][*:0]const u8,
    suggest_prefix: ?[*]u8,
    suggest_prefix_sz: usize,
    suggest_suffix: ?[*]u8,
    suggest_suffix_sz: usize,
    completion_sz: usize,
    completion_mode: usize,
    completion_pos: usize,
    completion_hint: c_int,

    // line formatting
    line_format: ?[*]c.struct_tui_screen_attr,
    line_format_ofs: ?[*]usize,
    line_format_sz: usize,

    // prompt
    prompt: ?[*]const c.struct_tui_cell,
    prompt_len: usize,
    finished: c_int,

    // history feature (externally managed)
    history: ?[*][*:0]const u8,
    in_history: ?[*:0]u8,
    history_sz: usize,
    history_pos: usize,

    // restore on release
    old_handlers: c.struct_tui_cbcfg,
    old_flags: c_int,
};

fn validate_context(T: ?*c.struct_tui_context, M: ?*?*readline_meta) bool {
    if (T == null) return false;

    var handlers: c.struct_tui_cbcfg = std.mem.zeroes(c.struct_tui_cbcfg);
    _ = c.arcan_tui_update_handlers(T, null, &handlers, @sizeOf(c.struct_tui_cbcfg));

    const ch: ?*readline_meta = @ptrCast(@alignCast(handlers.tag));
    if (ch == null or ch.?.magic != READLINE_MAGIC)
        return false;

    if (M) |m| m.* = ch;
    return true;
}

fn release_line_format(M: *readline_meta) void {
    if (M.line_format == null) return;
    std.c.free(M.line_format);
    std.c.free(M.line_format_ofs);
    M.line_format = null;
    M.line_format_ofs = null;
    M.line_format_sz = 0;
}

fn utf8len(end: usize, msg: [*]const u8) usize {
    var pos: usize = 0;
    var len: usize = 0;
    while (pos < end) {
        if ((msg[pos] & 0xc0) != 0x80) len += 1;
        pos += 1;
    }
    return len;
}

fn utf8fwd(pos: usize, msg: [*]const u8, max: usize) usize {
    if (pos == max) return max;
    var p = pos + 1;
    while (msg[p] != 0 and (msg[p] & 0xc0) == 0x80) {
        p += 1;
    }
    return p;
}

fn utf8back(pos: usize, msg: [*]const u8) usize {
    if (pos == 0) return pos;
    var p = pos - 1;
    while (p > 0 and (msg[p] & 0xc0) == 0x80) {
        p -= 1;
    }
    return p;
}

fn reset_meta(M: *readline_meta) void {
    M.finished = 0;
    if (M.work) |w| w[0] = 0;
    M.work_ofs = 0;
    M.work_len = 0;
    M.cursor = 0;
    M.history = null;
    M.history_sz = 0;
    M.in_history = null;
}

fn verify(T: ?*c.struct_tui_context, M: *readline_meta) void {
    _ = T;
    const verify_fn = M.opts.verify orelse return;
    const work_ptr: [*c]const u8 = if (M.work) |w| w else null;
    M.broken_offset = verify_fn(work_ptr, M.cursor, M.show_completion, M.old_handlers.tag);
}

fn drop_completion(T: ?*c.struct_tui_context, M: *readline_meta, run: bool) void {
    if (!M.show_completion) return;
    if (M.completion == null) return;
    if (!run) return;

    const msg: [*:0]const u8 = M.completion.?[M.completion_pos];

    switch (M.completion_mode) {
        c.READLINE_SUGGEST_WORD => {
            const work = M.work orelse return;
            const cur = M.cursor;
            const ofs = M.work_ofs;
            // Check if we are on a word
            const on_word = (work[cur] != 0 and !std.ascii.isWhitespace(work[cur])) or
                (work[cur] == 0 and cur > 0 and !std.ascii.isWhitespace(work[cur - 1]));
            if (on_word) {
                delete_last_word(T, M);
                if (M.cursor > 0)
                    add_input(T, M, " ", 1, true);
            }
            _ = ofs;
        },
        c.READLINE_SUGGEST_IGNORE => return,
        c.READLINE_SUGGEST_INSERT => {},
        c.READLINE_SUGGEST_SUBSTITUTE => {
            if (M.work) |w| w[0] = 0;
            M.work_ofs = 0;
            M.work_len = 0;
            M.cursor = 0;
        },
        else => {},
    }

    if (M.suggest_prefix) |pfx|
        add_input(T, M, pfx, M.suggest_prefix_sz, true);

    var p: usize = 0;
    while (msg[p] != 0) {
        var ch: u32 = 0;
        const step = c.arcan_tui_utf8ucs4(@ptrCast(&msg[p]), &ch);
        if (step <= 0) break;
        add_input(T, M, @ptrCast(&msg[p]), @intCast(step), true);
        p += @intCast(step);
    }

    if (M.suggest_suffix) |sfx|
        add_input(T, M, sfx, M.suggest_suffix_sz, true);
}

fn get_attr_for_ofs(M: *readline_meta, ofs: usize) ?*c.struct_tui_screen_attr {
    if (M.line_format == null) return null;

    const fmt_ofs = M.line_format_ofs.?;
    const fmt_arr = M.line_format.?;

    var ch: usize = 0;
    var fmt_i: usize = 0;
    var fmt: ?*c.struct_tui_screen_attr = null;

    if (fmt_ofs[0] == 0)
        fmt = &fmt_arr[0];

    const work = M.work orelse return null;
    var i: usize = 0;
    while (i < M.work_sz and i <= ofs) {
        while (fmt_i < M.line_format_sz and fmt_ofs[fmt_i] <= ch) {
            fmt_i += 1;
            if (fmt_i >= M.line_format_sz) break;
            fmt = &fmt_arr[fmt_i];
        }
        ch += 1;
        i = utf8fwd(i, work, M.work_sz);
    }
    return fmt;
}

fn u8len(buf: [*c]const u8) usize {
    var len: usize = 0;
    var p: usize = 0;
    while (buf[p] != 0) {
        var ucs4: u32 = 0;
        const step = c.arcan_tui_utf8ucs4(@ptrCast(&buf[p]), &ucs4);
        len += 1;
        if (step <= 0) {
            p += 1;
        } else {
            p += @intCast(step);
        }
    }
    return len;
}

fn draw_completion(T: ?*c.struct_tui_context, M: *readline_meta, P: ?*c.struct_tui_context) void {
    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(T, &rows, &cols);
    if (rows < 2) return;
    var completion_rows = rows - 1;

    var cx: usize = 0;
    var cy: usize = 0;
    c.arcan_tui_cursorpos(T, &cx, &cy);
    var title_attr: c_int = c.TUI_ATTR_BORDER_DOWN;

    if ((M.completion_hint & c.READLINE_SUGGEST_TITLE_HINT) != 0) {
        if (M.completion_pos == 0 and M.completion_sz > 1)
            M.completion_pos = 1;
    }

    var step: isize = 1;
    if (rows - cy < (rows >> 1)) {
        step = -1;
        title_attr = c.TUI_ATTR_BORDER_TOP;
        completion_rows = cy - 1;
    }

    var start_ofs: usize = 0;
    if (completion_rows < M.completion_sz and M.completion_pos + 1 > completion_rows) {
        start_ofs = M.completion_pos - 1;
    }

    var attr = c.arcan_tui_defcattr(T, c.TUI_COL_UI);

    var maxw: usize = 0;
    var maxww: usize = 0;
    var maxhw: usize = 0;

    var i: isize = @intCast(start_ofs);
    var j: isize = @intCast(cy);
    j += step;
    while (!M.opts.completion_compact and i < @as(isize, @intCast(M.completion_sz)) and j >= 0 and j < @as(isize, @intCast(rows))) : ({
        i += 1;
        j += step;
    }) {
        const len: usize = u8len(M.completion.?[@intCast(i)]);

        if (draw_completion_hint and (M.completion_hint & c.READLINE_SUGGEST_HINT) != 0) {
            const hint_str: [*c]const u8 = M.completion.?[@intCast(i)];
            const hint_len = cstrlen(hint_str);
            const hw: usize = u8len(&hint_str[hint_len + 1]);
            if (maxhw < hw) maxhw = hw;
        }

        if (len > maxw) maxw = len;
    }

    maxww = maxw;

    if (maxhw > 0 and draw_completion_hint and (M.completion_hint & c.READLINE_SUGGEST_HINT) != 0) {
        maxw += maxhw + 2;
    }

    // Slide left if overshooting window
    if (cx + maxw >= cols) {
        if (maxw + 1 > cols)
            cx = 0
        else
            cx = cols - maxw - 1;
    }

    maxw += cx + 1;

    var lasty: usize = 0;
    i = @intCast(start_ofs);
    j = @intCast(cy);
    j += step;
    while (i < @as(isize, @intCast(M.completion_sz)) and j >= 0 and j < @as(isize, @intCast(rows))) : ({
        i += 1;
        j += step;
    }) {
        c.arcan_tui_move_to(T, cx, @intCast(j));
        lasty = @intCast(j);

        if (i == 0 and (M.completion_hint & c.READLINE_SUGGEST_TITLE_HINT) != 0) {
            attr.unnamed_2.aflags |= @intCast(title_attr);
        }

        if (i == 1) attr.unnamed_2.aflags &= ~@as(u16, @intCast(title_attr));

        const entry_str: [*c]const u8 = M.completion.?[@intCast(i)];

        if (@as(usize, @intCast(i)) == M.completion_pos) {
            attr.unnamed_2.aflags |= c.TUI_ATTR_INVERSE;
            _ = c.arcan_tui_writestr(T, entry_str, &attr);
            attr.unnamed_2.aflags &= ~@as(u16, c.TUI_ATTR_INVERSE);
            if (M.opts.suggest_item) |suggest_fn| {
                const entry_len = cstrlen(entry_str);
                suggest_fn(entry_str, &entry_str[entry_len + 1], M.old_handlers.tag);
            }
        } else {
            _ = c.arcan_tui_writestr(T, entry_str, &attr);
        }

        // Hint column
        if (maxhw > 0 and draw_completion_hint and (M.completion_hint & c.READLINE_SUGGEST_HINT) != 0) {
            var hattr = attr;
            hattr.unnamed_2.aflags |= c.TUI_ATTR_ITALIC;

            const entry_len = cstrlen(entry_str);
            const hint_str = &entry_str[entry_len + 1];

            var hx: usize = 0;
            var hy: usize = 0;
            c.arcan_tui_cursorpos(T, &hx, &hy);

            if (!M.opts.completion_compact) {
                while (hx < cx + maxww + 1) : (hx += 1) {
                    c.arcan_tui_write(T, ' ', &hattr);
                }
            }

            c.arcan_tui_write(T, ' ', &hattr);
            _ = c.arcan_tui_writestr(T, hint_str, &hattr);
        }

        // Pad to widest entry in non-compact mode
        if (!M.opts.completion_compact) {
            var tx: usize = 0;
            var ty: usize = 0;
            c.arcan_tui_cursorpos(T, &tx, &ty);
            while (tx < maxw) : (tx += 1) {
                c.arcan_tui_write(T, ' ', &attr);
            }
        }
    }

    // Draw border
    if (!M.opts.completion_compact) {
        const x1 = cx;
        const x2 = maxw - 1;
        var y1 = cy + 1;
        var y2 = lasty;
        if (lasty < cy + 1) {
            y1 = lasty;
            y2 = cy + 1;
        }
        if (step < 0) {
            y1 = lasty;
            y2 = if (cy > 0) cy - 1 else 0;
        }
        c.arcan_tui_write_border(T, attr, x1, y1, x2, y2, c.TUI_BORDER_APPEND);
    }
    _ = P;
}

fn refresh(T: ?*c.struct_tui_context, M: *readline_meta) void {
    if (M.in_refresh) return;
    M.in_refresh = true;

    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(T, &rows, &cols);

    if (M.old_handlers.recolor) |f|
        castHandler(RecolorFn, f)(T, M.old_handlers.tag);

    const x1 = M.start_col;
    const x2 = M.stop_col;
    const y1 = M.start_row;
    const y2 = M.stop_row;

    if (x1 > x2 or y1 > y2) {
        M.in_refresh = false;
        return;
    }

    var cx: usize = 0;
    var cy: usize = 0;
    var limit: usize = (x2 - x1) + 1;

    if (limit < 3) {
        M.in_refresh = false;
        return;
    }

    c.arcan_tui_move_to(T, x1, y1);

    var alert = blk: {
        var a = std.mem.zeroes(c.struct_tui_screen_attr);
        a.unnamed_2.aflags = c.TUI_ATTR_COLOR_INDEXED;
        a.unnamed_0.fc[0] = c.TUI_COL_WARNING;
        a.unnamed_1.bc[0] = c.TUI_COL_WARNING;
        break :blk a;
    };
    var hint = alert;

    c.arcan_tui_erase_region(T, x1, y1, x2, y2, false);

    const prompt_len = M.prompt_len;

    if (M.work) |work| {
        if (prompt_len + M.work_len > limit - 3) {
            const ul = limit / 3;
            if (ul > 2) {
                var pi: usize = 0;
                while (pi < ul - 2 and pi < prompt_len and M.prompt != null) : (pi += 1) {
                    c.arcan_tui_write(T, M.prompt.?[pi].ch, @constCast(&M.prompt.?[pi].attr));
                    limit -= 1;
                }
            }
            c.arcan_tui_write(T, '.', null);
            c.arcan_tui_write(T, '.', null);
            limit -= 2;
        } else {
            if (M.prompt) |prompt| {
                var pi: usize = 0;
                while (pi < M.prompt_len) : (pi += 1) {
                    c.arcan_tui_write(T, prompt[pi].ch, @constCast(&prompt[pi].attr));
                }
            }
            limit -= prompt_len;
        }

        var pos: usize = 0;
        const pos_cp: usize = 0;

        if (M.work_len > limit) {
            pos = M.cursor;
            var tail = M.cursor;
            var count = limit;

            while (count > 0) {
                if (pos > 0) {
                    while (pos > 0 and (work[pos - 1] & 0xc0) == 0x80)
                        pos -= 1;
                    if (pos > 0) pos -= 1;
                    count -= 1;
                }

                if (count > 0 and tail < M.work_ofs) {
                    while (tail < M.work_ofs and (work[tail + 1] & 0xc0) == 0x80)
                        tail += 1;
                    if (tail < M.work_ofs) tail += 1;
                    count -= 1;
                }
            }
        }
        _ = pos_cp;

        var gi: usize = 0;
        while (gi < M.work_len and gi < limit) : (gi += 1) {
            var ch: u32 = 0;
            if (pos == M.cursor) {
                c.arcan_tui_cursorpos(T, &cx, &cy);
            }
            const step = c.arcan_tui_utf8ucs4(@ptrCast(&work[pos]), &ch);
            if (M.opts.mask_character != 0) ch = M.opts.mask_character;

            if (step > 0) pos += @intCast(step);

            const attr_ptr = get_attr_for_ofs(M, pos);
            if (M.broken_offset != -1 and pos >= @as(usize, @intCast(M.broken_offset))) {
                c.arcan_tui_write(T, ch, &alert);
            } else {
                c.arcan_tui_write(T, ch, attr_ptr);
            }
        }

        if (M.show_completion) {
            if (M.completion != null and M.completion_sz > 0) {
                var ocx: usize = 0;
                var ocy: usize = 0;
                c.arcan_tui_cursorpos(T, &ocx, &ocy);
                draw_completion(T, M, M.opts.popup);
                c.arcan_tui_move_to(T, ocx, ocy);
            }
        } else if (M.opts.popup) |popup| {
            // Hide popup
            c.arcan_tui_wndhint(popup, T, c.struct_tui_constraints{
                .hide = 1,
                .min_cols = 0,
                .min_rows = 0,
                .max_cols = 0,
                .max_rows = 0,
                .anch_row = 0,
                .anch_col = 0,
                .embed = 0,
            });
        }

        if (M.current_suggestion) |cs| {
            if (cx == 0)
                c.arcan_tui_cursorpos(T, &cx, &cy);

            var si: usize = 0;
            var ii: usize = M.work_len;
            while (cs[si] != 0 and ii < limit) {
                var ch: u32 = 0;
                const step = c.arcan_tui_utf8ucs4(@ptrCast(&cs[si]), &ch);
                if (step > 0) si += @intCast(step) else si += 1;
                c.arcan_tui_write(T, ch, &hint);
                ii += 1;
            }
        }

        if (cx != 0)
            c.arcan_tui_move_to(T, cx, cy);
    }

    M.in_refresh = false;
}

fn step_cursor_left(T: ?*c.struct_tui_context, M: *readline_meta) void {
    if (M.cursor == 0) return;
    const work = M.work orelse return;
    M.cursor = utf8back(M.cursor, work);
    refresh(T, M);
}

fn step_cursor_right(T: ?*c.struct_tui_context, M: *readline_meta) void {
    const work = M.work orelse return;
    if (M.cursor < M.work_ofs)
        M.cursor = utf8fwd(M.cursor, work, M.work_ofs);
    refresh(T, M);
}

fn delete_at_cursor(T: ?*c.struct_tui_context, M: *readline_meta) bool {
    const work = M.work orelse return true;
    if (M.cursor == M.work_ofs) return true;

    const c_cursor = utf8fwd(M.cursor, work, M.work_ofs);
    std.mem.copyForwards(u8, work[M.cursor..M.work_ofs], work[c_cursor..M.work_ofs]);
    work[M.work_ofs] = 0;
    M.work_ofs -= 1;
    M.work_len = utf8len(M.work_ofs, work);

    refresh(T, M);
    return true;
}

fn erase_at_cursor(T: ?*c.struct_tui_context, M: *readline_meta) bool {
    const work = M.work orelse return true;
    if (M.cursor == 0 or M.work_len == 0) return true;

    const c_cursor = utf8back(M.cursor, work);
    const len = M.cursor - c_cursor;

    if (M.cursor == M.work_ofs) {
        @memset(work[c_cursor..c_cursor + len], 0);
    } else {
        std.mem.copyForwards(u8, work[c_cursor..M.work_ofs - len], work[M.cursor..M.work_ofs]);
        @memset(work[M.work_ofs - len .. M.work_ofs], 0);
    }

    M.cursor = c_cursor;
    M.work_len -= 1;
    M.work_ofs -= len;

    verify(T, M);
    refresh(T, M);
    return true;
}

fn add_linefeed(T: ?*c.struct_tui_context, M: *readline_meta) bool {
    if (M.show_completion and M.completion_sz > 0) {
        drop_completion(T, M, M.opts.linefeed_expand);
        verify(T, M);
        refresh(T, M);
    }

    if (!M.opts.multiline) {
        if (M.broken_offset != -1) return true;
        M.finished = 1;
        M.history_pos = 0;
    }
    return true;
}

fn delete_last_word(T: ?*c.struct_tui_context, M: *readline_meta) void {
    const work = M.work orelse return;
    if (M.cursor == 0) return;

    var cursor = M.cursor;
    if (cursor == M.work_ofs) {
        if (cursor > 0) cursor -= 1;
    }

    while (cursor > 0 and std.ascii.isWhitespace(work[cursor])) {
        cursor = utf8back(cursor, work);
    }

    var beg = cursor;
    while (beg > 0 and !std.ascii.isWhitespace(work[beg])) {
        beg = utf8back(beg, work);
    }

    var end = cursor;
    while (end < M.work_ofs and !std.ascii.isWhitespace(work[end])) {
        end = utf8fwd(end, work, M.work_ofs);
    }
    if (end > M.work_ofs) end = M.work_ofs;

    M.cursor = beg;
    const ntr = end - beg;
    M.work_ofs -= ntr;
    std.mem.copyForwards(u8, work[beg..M.work_ofs], work[end..end + M.work_ofs - beg]);
    M.work_len = utf8len(M.work_ofs, work);

    refresh(T, M);
}

fn cut_to_eol(T: ?*c.struct_tui_context, M: *readline_meta) void {
    const work = M.work orelse return;
    _ = c.arcan_tui_copy(T, @ptrCast(&work[M.cursor]));
    work[M.cursor] = 0;
    M.work_ofs = M.cursor;
    M.work_len = utf8len(M.cursor, work);
    verify(T, M);
    refresh(T, M);
}

fn cut_to_sol(T: ?*c.struct_tui_context, M: *readline_meta) void {
    const work = M.work orelse return;
    std.mem.copyForwards(u8, work[0..M.work_ofs - M.cursor], work[M.cursor..M.work_ofs]);
    work[M.cursor] = 0;
    _ = c.arcan_tui_copy(T, @ptrCast(work));
    M.work_ofs = M.cursor;
    M.cursor = 0;
    M.work_len = utf8len(M.work_ofs, work);
    verify(T, M);
    refresh(T, M);
}

fn on_utf8_paste(T: ?*c.struct_tui_context, u8str: [*c]const u8, len: usize, cont: bool, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    const m = M.?;

    if (m.opts.paste_forward) {
        if (m.old_handlers.utf8) |f|
            return castHandler(Utf8PasteFn, f)(T, u8str, len, cont, m.old_handlers.tag);
    }

    const old_tc = m.opts.tab_completion;
    m.opts.tab_completion = false;

    if (m.opts.filter_character) |filter_fn| {
        var i: usize = 0;
        while (i < len) {
            var ch: u32 = 0;
            const step = c.arcan_tui_utf8ucs4(@ptrCast(&u8str[i]), &ch);
            const step_u: usize = if (step > 0) @intCast(step) else 1;
            if (filter_fn(ch, m.work_len + 1, m.old_handlers.tag))
                add_input(T, m, @ptrCast(&u8str[i]), step_u, false);
            i += step_u;
        }
    } else {
        add_input(T, m, @ptrCast(u8str), len, false);
    }
    m.opts.tab_completion = old_tc;

    verify(T, m);
    refresh(T, m);
}

fn on_utf8_input(T: ?*c.struct_tui_context, u8str: [*c]const u8, len: usize, tag: ?*anyopaque) callconv(.c) bool {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return true;
    const m = M.?;

    if (m.in_history) |ih| {
        std.c.free(ih);
        m.in_history = null;
    }

    if (u8str[0] == '\x1b') return false;
    if (u8str[0] == '\n' or u8str[0] == '\r') return add_linefeed(T, m);

    if (u8str[0] == '\t' and m.opts.tab_completion) {
        synch_completion(T, m);
        return true;
    }

    if (u8str[0] == ' ' and m.opts.whitespace_expand) {
        if (m.show_completion and m.completion != null) {
            drop_completion(T, m, true);
            verify(T, m);
            refresh(T, m);
            return true;
        }
    } else if (u8str[0] == 0x08 or u8str[0] == 0x7f) {
        return erase_at_cursor(T, m);
    }

    if (m.opts.filter_character) |filter_fn| {
        var ch: u32 = 0;
        _ = c.arcan_tui_utf8ucs4(u8str, &ch);
        if (!filter_fn(ch, m.work_len + 1, m.old_handlers.tag)) {
            return true;
        }
    }

    add_input(T, m, @ptrCast(u8str), len, false);
    refresh(T, m);
    return true;
}

fn step_history(T: ?*c.struct_tui_context, M: *readline_meta, step: isize) void {
    if (M.history == null or M.history_sz == 0) return;

    if (M.in_history == null) {
        if (step < 0) return;

        const work: [*c]const u8 = if (M.work) |w| w else "";
        M.in_history = c.strdup(work);
        if (M.in_history == null) return;

        const hist_entry = M.history.?[M.history_pos];
        const hist_len = cstrlen(hist_entry);
        replace_str(T, M, hist_entry, hist_len);
        return;
    }

    if (M.history_pos == 0 and step < 0) {
        const ih = M.in_history.?;
        const ih_len = cstrlen(ih);
        replace_str(T, M, ih, ih_len);
        std.c.free(M.in_history);
        M.in_history = null;
        return;
    }

    if (step > 0) {
        M.history_pos += 1;
        if (M.history_pos >= M.history_sz)
            M.history_pos = M.history_sz - 1;
    } else {
        if (M.history_pos > 0) M.history_pos -= 1;
    }

    const hist_entry = M.history.?[M.history_pos];
    const hist_len = cstrlen(hist_entry);
    replace_str(T, M, hist_entry, hist_len);
}

fn synch_completion(T: ?*c.struct_tui_context, M: *readline_meta) void {
    const verify_fn = M.opts.verify orelse return;
    const work_ptr: [*c]const u8 = if (M.work) |w| w else null;
    M.broken_offset = verify_fn(work_ptr, M.cursor, true, M.old_handlers.tag);

    M.show_completion = true;
    if (M.completion != null)
        refresh(T, M);
}

fn on_key_input(T: ?*c.struct_tui_context, keysym: u32, scancode: u8, mods: u16, subid: u16, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    const m = M.?;

    if (m.opts.block_builtin_bindings) {
        if (m.old_handlers.input_key) |f|
            castHandler(InputKeyFn, f)(T, keysym, scancode, mods, subid, m.old_handlers.tag);
        return;
    }

    if (keysym == c.TUIK_F1) {
        draw_completion_hint = !draw_completion_hint;
        refresh(T, m);
        return;
    }

    const meta_held = (mods & (c.TUIM_LCTRL | c.TUIM_RCTRL)) != 0;
    if (meta_held) {
        if (keysym == c.TUIK_RETURN or keysym == c.TUIK_M) {
            m.finished = 1;
        } else if (keysym == c.TUIK_L) {
            arcan_tui_readline_reset(T);
        } else if (keysym == c.TUIK_D) {
            if (m.work_ofs == 0) {
                if (m.opts.allow_exit) {
                    arcan_tui_readline_reset(T);
                    m.finished = -1;
                    return;
                }
            } else {
                _ = delete_at_cursor(T, m);
            }
        } else if (keysym == c.TUIK_T) {
            // MISSING: swap with previous
        } else if (keysym == c.TUIK_B) {
            step_cursor_left(T, m);
            refresh(T, m);
        } else if (keysym == c.TUIK_F) {
            step_cursor_right(T, m);
            refresh(T, m);
        } else if (keysym == c.TUIK_K) {
            cut_to_eol(T, m);
        } else if (keysym == c.TUIK_U) {
            cut_to_sol(T, m);
        } else if (keysym == c.TUIK_P) {
            step_history(T, m, 1);
        } else if (keysym == c.TUIK_N) {
            step_history(T, m, -1);
        } else if (keysym == c.TUIK_A) {
            m.cursor = 0;
            refresh(T, m);
        } else if (keysym == c.TUIK_E) {
            m.cursor = m.work_ofs;
            refresh(T, m);
        } else if (keysym == c.TUIK_W) {
            delete_last_word(T, m);
        } else if (keysym == c.TUIK_TAB) {
            synch_completion(T, m);
        }

        if (m.old_handlers.input_key) |f|
            castHandler(InputKeyFn, f)(T, keysym, scancode, mods, subid, m.old_handlers.tag);
        return;
    }

    if (keysym == c.TUIK_LEFT) {
        drop_completion(T, m, false);
        step_cursor_left(T, m);
        verify(T, m);
        refresh(T, m);
    } else if (keysym == c.TUIK_RIGHT) {
        drop_completion(T, m, m.cursor == m.work_ofs);
        verify(T, m);
        refresh(T, m);
        step_cursor_right(T, m);
    } else if (keysym == c.TUIK_UP) {
        if (m.show_completion and m.completion_sz > 0) {
            if (m.completion_pos == 0)
                m.completion_pos = m.completion_sz - 1
            else
                m.completion_pos -= 1;
            refresh(T, m);
        } else {
            step_history(T, m, 1);
        }
    } else if (keysym == c.TUIK_DOWN) {
        if (m.show_completion and m.completion_sz > 0) {
            m.completion_pos = (m.completion_pos + 1) % m.completion_sz;
            refresh(T, m);
        } else {
            step_history(T, m, -1);
        }
    } else if (keysym == c.TUIK_ESCAPE) {
        if (m.show_completion and m.completion != null) {
            m.show_completion = false;
            drop_completion(T, m, false);
            refresh(T, m);
        } else if (m.opts.allow_exit) {
            arcan_tui_readline_reset(T);
            m.finished = -1;
        }
    } else if (keysym == c.TUIK_BACKSPACE) {
        _ = erase_at_cursor(T, m);
    } else if (keysym == c.TUIK_DELETE) {
        _ = delete_at_cursor(T, m);
    } else if (keysym == c.TUIK_TAB and m.opts.tab_completion) {
        synch_completion(T, m);
    } else if (keysym == c.TUIK_RETURN) {
        _ = add_linefeed(T, m);
    } else {
        if (m.old_handlers.input_key) |f|
            castHandler(InputKeyFn, f)(T, keysym, scancode, mods, subid, m.old_handlers.tag);
    }
}

fn ensure_size(T: ?*c.struct_tui_context, M: *readline_meta, sz: usize) bool {
    if (sz <= M.work_sz) return true;

    const new_sz = sz + 1024;
    const new_buf: ?[*]u8 = @ptrCast(std.c.malloc(new_sz));
    if (new_buf == null) return false;

    @memset(new_buf.?[0..new_sz], 0);
    if (M.work) |old| {
        if (M.work_ofs > 0)
            @memcpy(new_buf.?[0..M.work_ofs], old[0..M.work_ofs]);
        std.c.free(old);
    }
    M.work = new_buf;
    M.work_sz = new_sz;

    _ = T;
    return true;
}

fn replace_str(T: ?*c.struct_tui_context, M: *readline_meta, str: [*c]const u8, len: usize) void {
    if (!ensure_size(T, M, len + 1)) return;

    const work = M.work.?;
    @memcpy(work[0..len], str[0..len]);
    work[len] = 0;
    M.work_ofs = len;
    M.cursor = len;
    M.work_len = utf8len(len, str);

    refresh(T, M);
}

fn add_input(T: ?*c.struct_tui_context, M: *readline_meta, u8str: [*c]const u8, len: usize, noverify: bool) void {
    if (!ensure_size(T, M, M.work_ofs + len + 1)) return;

    const work = M.work.?;

    if (M.cursor == M.work_ofs) {
        M.cursor += len;
        @memcpy(work[M.work_ofs..M.work_ofs + len], u8str[0..len]);
        work[M.cursor] = 0;
    } else {
        // Slide buffer right for mid-insertion
        std.mem.copyBackwards(u8, work[M.cursor + len .. M.work_ofs + len], work[M.cursor..M.work_ofs]);
        @memcpy(work[M.cursor..M.cursor + len], u8str[0..len]);
        M.cursor += len;
    }

    if (!noverify) verify(T, M);

    var pos: usize = 0;
    var count: usize = 0;
    while (pos < len) : (pos += 1) {
        if ((u8str[pos] & 0xc0) != 0x80) count += 1;
    }

    M.work_ofs += len;
    M.work_len += count;
}

fn on_visibility(T: ?*c.struct_tui_context, visible: bool, focus: bool, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M) or M.?.old_handlers.visibility == null) return;
    const cb: *const fn (?*c.struct_tui_context, bool, bool, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(M.?.old_handlers.visibility.?));
    cb(T, visible, focus, M.?.old_handlers.tag);
}

fn on_exec_state(T: ?*c.struct_tui_context, state: c_int, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M) or M.?.old_handlers.exec_state == null) return;
    const cb: *const fn (?*c.struct_tui_context, c_int, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(M.?.old_handlers.exec_state.?));
    cb(T, state, M.?.old_handlers.tag);
}

fn on_tick(T: ?*c.struct_tui_context, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M) or M.?.old_handlers.tick == null) return;
    const cb: *const fn (?*c.struct_tui_context, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(M.?.old_handlers.tick.?));
    cb(T, M.?.old_handlers.tag);
}

fn on_bchunk(T: ?*c.struct_tui_context, input: bool, size: u64, fd: c_int, @"type": [*c]const u8, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M) or M.?.old_handlers.bchunk == null) return;
    const cb: *const fn (?*c.struct_tui_context, bool, u64, c_int, [*c]const u8, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(M.?.old_handlers.bchunk.?));
    cb(T, input, size, fd, @"type", M.?.old_handlers.tag);
}

fn on_mouse_motion(T: ?*c.struct_tui_context, relative: bool, x: c_int, y: c_int, modifiers: c_int, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    const m = M.?;

    if (m.opts.mouse_forward) {
        if (m.old_handlers.input_mouse_button) |_| {
            if (m.old_handlers.input_mouse_motion) |f|
                castHandler(InputMouseMotionFn, f)(T, relative, x, y, modifiers, m.old_handlers.tag);
        }
    }
}

fn on_mouse_button_input(T: ?*c.struct_tui_context, x: c_int, y: c_int, button: c_int, active: bool, modifiers: c_int, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    const m = M.?;

    const in_region = (x >= @as(c_int, @intCast(m.start_col)) and
        x <= @as(c_int, @intCast(m.stop_col)) and
        y >= @as(c_int, @intCast(m.start_row)) and
        y <= @as(c_int, @intCast(m.stop_row)));

    if (!in_region) {
        if (m.opts.mouse_forward) {
            if (m.old_handlers.input_mouse_button) |f|
                castHandler(InputMouseButtonFn, f)(T, x, y, button, active, modifiers, m.old_handlers.tag);
        } else if (m.opts.allow_exit) {
            m.finished = -1;
        }
        return;
    }

    if (!active) return;

    var cx: usize = 0;
    var cy: usize = 0;
    c.arcan_tui_cursorpos(T, &cx, &cy);

    const w = m.stop_col - m.start_col;
    const c_ofs = (cx - m.start_col) + (cy - m.start_row) * w;
    const mx: usize = @intCast(x);
    const my: usize = @intCast(y);
    const m_ofs = (mx - m.start_col) + (my - m.start_row) * w;

    if (m_ofs == c_ofs) return;

    if (m_ofs > c_ofs) {
        var i: usize = 0;
        while (i < m_ofs - c_ofs) : (i += 1)
            step_cursor_right(T, m);
    } else {
        var i: usize = 0;
        while (i < c_ofs - m_ofs) : (i += 1)
            step_cursor_left(T, m);
    }
    refresh(T, m);
}

export fn arcan_tui_readline_region(T: ?*c.struct_tui_context, x1: usize, y1: usize, x2: usize, y2: usize) void {
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    const m = M.?;
    m.start_col = x1;
    m.stop_col = x2;
    m.start_row = y1;
    m.stop_row = y2;
}

fn on_recolor(T: ?*c.struct_tui_context, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    const m = M.?;
    if (m.old_handlers.recolor) |f|
        castHandler(RecolorFn, f)(T, m.old_handlers.tag);
    refresh(T, m);
}

export fn arcan_tui_readline_autocomplete(T: ?*c.struct_tui_context, suffix: [*c]const u8) void {
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M) or M.?.work == null) return;
    M.?.current_suggestion = if (suffix != null) @ptrCast(suffix) else null;
}

export fn arcan_tui_readline_suggest(T: ?*c.struct_tui_context, mode: c_int, set: [*c][*c]const u8, sz: usize) void {
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M) or M.?.work == null) return;
    const m = M.?;

    const mask = c.READLINE_SUGGEST_HINT | c.READLINE_SUGGEST_TITLE_HINT;
    m.completion = @ptrCast(set);
    m.completion_sz = sz;
    m.completion_mode = @intCast(mode & ~(mask));
    m.completion_hint = mode & mask;
    m.completion_pos = 0;

    if (m.show_completion) refresh(T, m);
}

export fn arcan_tui_readline_reset(T: ?*c.struct_tui_context) void {
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M) or M.?.work == null) return;
    reset_meta(M.?);
    verify(T, M.?);
    refresh(T, M.?);
}

export fn arcan_tui_readline_set(T: ?*c.struct_tui_context, msg: [*c]const u8) void {
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M) or M.?.work == null) return;
    const m = M.?;

    reset_meta(m);

    if (msg == null) return;

    var p: usize = 0;
    while (msg[p] != 0) {
        var ch: u32 = 0;
        const step = c.arcan_tui_utf8ucs4(@ptrCast(&msg[p]), &ch);
        if (step > 0) {
            add_input(T, m, @ptrCast(&msg[p]), @intCast(step), true);
            p += @intCast(step);
        } else break;
    }

    refresh(T, m);
}

export fn arcan_tui_readline_prompt(T: ?*c.struct_tui_context, prompt: [*c]const c.struct_tui_cell) void {
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    const m = M.?;

    if (prompt == null and m.prompt != null) {
        m.prompt = null;
        m.prompt_len = 0;
        refresh(T, m);
        return;
    }

    var len: usize = 0;
    if (prompt != null) {
        while (prompt[len].ch != 0) len += 1;
    }

    m.prompt = if (prompt != null) @ptrCast(prompt) else null;
    m.prompt_len = len;
    refresh(T, m);
}

fn reset_boundaries(T: ?*c.struct_tui_context, M: *readline_meta, cols: usize, rows: usize) void {
    // Degenerate surface (e.g. the pre-DISPLAYHINT placeholder segment is
    // smaller than one glyph cell): C upstream wraps and draws nothing; do
    // the same without trapping — the resize handler recomputes real bounds.
    if (rows == 0 or cols == 0) {
        M.start_row = 0;
        M.stop_row = 0;
        M.start_col = 0;
        M.stop_col = 0;
        _ = T;
        return;
    }
    if (M.opts.anchor_row < 0 and M.opts.n_rows < rows) {
        M.start_row = 0;
        M.stop_row = 0;

        const pad: usize = @intCast(-(M.opts.anchor_row) + @as(isize, @intCast(M.opts.n_rows)));

        if (rows > pad) {
            M.start_row = rows - pad;
            M.stop_row = M.start_row + M.opts.n_rows - 1;
        }
    } else if (M.opts.anchor_row > 0) {
        M.start_row = @intCast(M.opts.anchor_row - 1);
        M.stop_row = M.start_row + M.opts.n_rows - 1;
    } else {
        M.start_row = 0;
        M.stop_row = rows - 1;
    }

    if (M.opts.margin_left > 0)
        M.start_col = M.opts.margin_left - 1
    else
        M.start_col = 0;

    if (M.opts.margin_right > 0 and cols > M.opts.margin_right)
        M.stop_col = cols - M.opts.margin_right - 1
    else
        M.stop_col = cols - 1;

    if (M.stop_row >= rows) M.stop_row = rows - 1;
    if (M.stop_col >= cols) M.stop_col = cols - 1;

    _ = T;
}

fn on_state(T: ?*c.struct_tui_context, input: bool, fd: c_int, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    if (M.?.old_handlers.state) |f|
        castHandler(StateFn, f)(T, input, fd, M.?.old_handlers.tag);
}

fn on_geohint(T: ?*c.struct_tui_context, lat: f32, lng: f32, elev: f32, a3_c: [*c]const u8, a3_lang: [*c]const u8, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    if (M.?.old_handlers.geohint) |f|
        castHandler(GeohintFn, f)(T, lat, lng, elev, a3_c, a3_lang, M.?.old_handlers.tag);
}

fn on_resized(T: ?*c.struct_tui_context, neww: usize, newh: usize, cols: usize, rows: usize, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    const m = M.?;

    if (m.old_handlers.resized) |f|
        castHandler(ResizedFn, f)(T, neww, newh, cols, rows, m.old_handlers.tag);

    reset_boundaries(T, m, cols, rows);
    refresh(T, m);
}

fn on_label_input(T: ?*c.struct_tui_context, label: [*c]const u8, active: bool, tag: ?*anyopaque) callconv(.c) bool {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return false;
    const m = M.?;

    if (m.old_handlers.input_label) |f|
        return castHandler(InputLabelFn, f)(T, label, active, m.old_handlers.tag);

    return false;
}

fn on_subwindow(T: ?*c.struct_tui_context, connection: ?*c.struct_arcan_shmif_cont, id: u32, @"type": u8, tag: ?*anyopaque) callconv(.c) bool {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return false;
    if (M.?.old_handlers.subwindow) |f|
        return castHandler(SubwindowFn, f)(T, connection, id, @"type", M.?.old_handlers.tag);
    return false;
}

fn on_label_query(T: ?*c.struct_tui_context, index: usize, country: [*c]const u8, lang: [*c]const u8, dstlbl: [*c]c.struct_tui_labelent, t: ?*anyopaque) callconv(.c) bool {
    _ = t;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return false;
    const m = M.?;

    if (m.old_handlers.query_label) |f|
        return castHandler(QueryLabelFn, f)(T, index - 1, country, lang, dstlbl, m.old_handlers.tag);

    return false;
}

fn on_reset(T: ?*c.struct_tui_context, level: c_int, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    arcan_tui_readline_reset(T);
    if (M.?.old_handlers.reset) |f|
        castHandler(ResetFn, f)(T, level, M.?.old_handlers.tag);
}

export fn arcan_tui_readline_autosuggest(T: ?*c.struct_tui_context, vl: bool) void {
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    M.?.show_completion = vl;
    refresh(T, M.?);
}

export fn arcan_tui_readline_set_cursor(T: ?*c.struct_tui_context, pos: isize, relative: bool) void {
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    const m = M.?;
    const work = m.work orelse return;

    if (!relative) m.cursor = 0;

    const abs_pos: usize = @intCast(if (pos < 0) -pos else pos);
    var i: usize = 0;
    while (i < abs_pos) : (i += 1) {
        if (pos < 0) {
            m.cursor = utf8back(m.cursor, work);
            if (m.cursor == 0) break;
        } else {
            if (m.cursor >= m.work_ofs) break;
            m.cursor = utf8fwd(m.cursor, work, m.work_ofs);
        }
    }
}

export fn arcan_tui_readline_format(T: ?*c.struct_tui_context, ofs: [*c]usize, attr: [*c]c.struct_tui_screen_attr, n: usize) void {
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    const m = M.?;

    release_line_format(m);
    m.line_format = @ptrCast(attr);
    m.line_format_ofs = @ptrCast(ofs);
    m.line_format_sz = n;
    refresh(T, m);
}

export fn arcan_tui_readline_setup(T: ?*c.struct_tui_context, opts: ?*c.struct_tui_readline_opts, opt_sz: usize) void {
    if (T == null or opts == null) return;

    const meta: *readline_meta = @ptrCast(@alignCast(std.c.malloc(@sizeOf(readline_meta)) orelse return));
    meta.* = std.mem.zeroes(readline_meta);
    meta.magic = READLINE_MAGIC;
    meta.broken_offset = -1;

    if (opt_sz > @sizeOf(readline_meta)) return;

    const copy_sz = @min(opt_sz, @sizeOf(c.struct_tui_readline_opts));
    @memcpy(
        @as([*]u8, @ptrCast(&meta.opts))[0..copy_sz],
        @as([*]const u8, @ptrCast(opts.?))[0..copy_sz],
    );

    if (meta.opts.n_rows == 0) meta.opts.n_rows = 1;

    var cbcfg = std.mem.zeroes(c.struct_tui_cbcfg);
    cbcfg.input_key = @ptrCast(@constCast(&on_key_input));
    cbcfg.input_mouse_button = @ptrCast(@constCast(&on_mouse_button_input));
    cbcfg.recolor = @ptrCast(@constCast(&on_recolor));
    cbcfg.input_utf8 = @ptrCast(@constCast(&on_utf8_input));
    cbcfg.utf8 = @ptrCast(@constCast(&on_utf8_paste));
    cbcfg.resized = @ptrCast(@constCast(&on_resized));
    cbcfg.input_label = @ptrCast(@constCast(&on_label_input));
    cbcfg.subwindow = @ptrCast(@constCast(&on_subwindow));
    cbcfg.query_label = @ptrCast(@constCast(&on_label_query));
    cbcfg.reset = @ptrCast(@constCast(&on_reset));
    cbcfg.input_mouse_motion = @ptrCast(@constCast(&on_mouse_motion));
    cbcfg.bchunk = @ptrCast(@constCast(&on_bchunk));
    cbcfg.tick = @ptrCast(@constCast(&on_tick));
    cbcfg.visibility = @ptrCast(@constCast(&on_visibility));
    cbcfg.exec_state = @ptrCast(@constCast(&on_exec_state));
    cbcfg.state = @ptrCast(@constCast(&on_state));
    cbcfg.geohint = @ptrCast(@constCast(&on_geohint));
    cbcfg.tag = @ptrCast(meta);

    _ = c.arcan_tui_update_handlers(T, &cbcfg, &meta.old_handlers, @sizeOf(c.struct_tui_cbcfg));

    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(T, &rows, &cols);
    reset_boundaries(T, meta, cols, rows);
    _ = ensure_size(T, meta, 32);
    refresh(T, meta);
}

export fn arcan_tui_readline_release(T: ?*c.struct_tui_context) void {
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    const m = M.?;

    if (m.suggest_prefix) |pfx| {
        std.c.free(pfx);
        m.suggest_prefix = null;
        m.suggest_prefix_sz = 0;
    }

    if (m.suggest_suffix) |sfx| {
        std.c.free(sfx);
        m.suggest_suffix = null;
        m.suggest_suffix_sz = 0;
    }

    release_line_format(m);

    m.magic = 0xdeadbeef;
    if (m.work) |w| std.c.free(w);

    _ = c.arcan_tui_update_handlers(T, &m.old_handlers, null, @sizeOf(c.struct_tui_cbcfg));
    std.c.free(m);
}

export fn arcan_tui_readline_finished(T: ?*c.struct_tui_context, buffer: ?*?[*:0]u8) c_int {
    if (buffer) |b| b.* = null;

    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return 0; // false

    const m = M.?;
    if (buffer) |b| b.* = if (m.work) |w| @ptrCast(w) else null;
    return m.finished;
}

export fn arcan_tui_readline_history(T: ?*c.struct_tui_context, buf: [*c][*c]const u8, count: usize) void {
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    const m = M.?;
    m.history = @ptrCast(buf);
    m.history_sz = count;
    m.history_pos = 0;
}

export fn arcan_tui_readline_suggest_fix(T: ?*c.struct_tui_context, pre: [*c]const u8, suf: [*c]const u8) void {
    var M: ?*readline_meta = null;
    if (!validate_context(T, &M)) return;
    const m = M.?;

    if (m.suggest_prefix) |pfx| {
        std.c.free(pfx);
        m.suggest_prefix = null;
        m.suggest_prefix_sz = 0;
    }

    if (m.suggest_suffix) |sfx| {
        std.c.free(sfx);
        m.suggest_suffix = null;
        m.suggest_suffix_sz = 0;
    }

    if (pre != null) {
        const nb = cstrlen(pre);
        const copy: ?[*]u8 = @ptrCast(std.c.malloc(nb + 1));
        if (copy == null) return;
        @memcpy(copy.?[0..nb], pre[0..nb]);
        copy.?[nb] = 0;
        m.suggest_prefix = copy;
        m.suggest_prefix_sz = nb;
    }

    if (suf != null) {
        const nb = cstrlen(suf);
        const copy: ?[*]u8 = @ptrCast(std.c.malloc(nb + 1));
        if (copy == null) return;
        @memcpy(copy.?[0..nb], suf[0..nb]);
        copy.?[nb] = 0;
        m.suggest_suffix = copy;
        m.suggest_suffix_sz = nb;
    }
}

// Helpers
fn cstrlen(s: [*c]const u8) usize {
    if (s == null) return 0;
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}
