// Zig port of tui/widgets/bufferwnd.c
// Text/hex buffer window widget for arcan TUI.

const std = @import("std");

const c = @import("shmif_types");

const BUFFERWND_MAGIC: u32 = 0xfadef00f;

// Callback function types for old_handlers forwarding (struct_tui_cbcfg stores ?*anyopaque)
const InputLabelFn = *const fn (?*c.struct_tui_context, [*c]const u8, bool, ?*anyopaque) callconv(.c) bool;
const QueryLabelFn = *const fn (?*c.struct_tui_context, usize, [*c]const u8, [*c]const u8, [*c]c.struct_tui_labelent, ?*anyopaque) callconv(.c) bool;
const SubwindowFn = *const fn (?*c.struct_tui_context, ?*c.struct_arcan_shmif_cont, u32, u8, ?*anyopaque) callconv(.c) bool;

fn castHandler(comptime T: type, ptr: *anyopaque) T {
    return @ptrCast(@alignCast(ptr));
}
const min_meta_rows: usize = 7;

const attr_lookup_fn = ?*const fn (T: ?*c.struct_tui_context, tag: ?*anyopaque, bytev: u8, pos: usize, dch: *u32, attr: *c.struct_tui_screen_attr) callconv(.c) void;

const bufferwnd_meta = struct {
    magic: u32,
    old_handlers: c.struct_tui_cbcfg,
    exit_status: c_int,
    old_flags: c_int,
    row: usize,
    col: usize,
    invalidated: bool,
    row_bytelen: usize,
    buffer: [*c]u8,
    buffer_sz: usize,
    buffer_pos: usize,
    buffer_ofs: usize,
    buffer_lend: usize,
    cursor_x: usize,
    cursor_y: usize,
    cursor_ofs_col: usize,
    cursor_ofs_row: usize,
    cursor_ofs_row_end: usize,
    cursor_halfb: bool,
    orig_w: usize,
    orig_h: usize,
    opts: c.struct_tui_bufferwnd_opts,
};

// Thread-local storage for coordinate resolution callbacks
threadlocal var resolve_temp = struct {
    x: usize = 0,
    y: usize = 0,
    ofs: usize = 0,
}{};

fn set_pos(T: ?*c.struct_tui_context, x: usize, y: usize) void {
    _ = T;
    resolve_temp.x = x;
    resolve_temp.y = y;
}

fn set_ofs(T: ?*c.struct_tui_context, ofs: usize) void {
    _ = T;
    resolve_temp.ofs = ofs;
}

fn validate_context(T: ?*c.struct_tui_context, M: ?*?*bufferwnd_meta) bool {
    if (T == null) return false;

    var handlers: c.struct_tui_cbcfg = std.mem.zeroes(c.struct_tui_cbcfg);
    _ = c.arcan_tui_update_handlers(T, null, &handlers, @sizeOf(c.struct_tui_cbcfg));

    const ch: ?*bufferwnd_meta = @ptrCast(@alignCast(handlers.tag));
    if (ch == null or ch.?.magic != BUFFERWND_MAGIC)
        return false;

    if (M) |m| m.* = ch;
    return true;
}

export fn arcan_tui_bufferwnd_release(T: ?*c.struct_tui_context) void {
    var meta: ?*bufferwnd_meta = null;
    if (!validate_context(T, &meta)) return;

    const m = meta.?;
    _ = c.arcan_tui_set_flags(T, m.old_flags);
    _ = c.arcan_tui_update_handlers(T, &m.old_handlers, null, @sizeOf(c.struct_tui_cbcfg));
    c.arcan_tui_reset_labels(T);

    const orig_w = m.orig_w;
    const orig_h = m.orig_h;

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

    m.magic = 0xdeadbeef;
    std.c.free(m);
}

export fn arcan_tui_bufferwnd_tell(T: ?*c.struct_tui_context, O: ?*c.struct_tui_bufferwnd_opts) usize {
    var M: ?*bufferwnd_meta = null;
    if (!validate_context(T, &M)) return 0;

    const m = M.?;
    if (O) |o| o.* = m.opts;
    return m.buffer_ofs;
}

fn has_cursor(M: *bufferwnd_meta) bool {
    return !M.opts.read_only or M.opts.view_mode == c.BUFFERWND_VIEW_HEX_DETAIL;
}

fn draw_hex_ch(T: ?*c.struct_tui_context, attr: *c.struct_tui_screen_attr, x: usize, y: usize, ch: u8) void {
    const hlut = "0123456789abcdef";
    const out = [2]u8{ hlut[(ch >> 4) & 0xf], hlut[(ch >> 0) & 0xf] };
    c.arcan_tui_move_to(T, x, y);
    _ = c.arcan_tui_writeu8(T, &out, 2, attr);
}

fn write_mask(T: ?*c.struct_tui_context, buf_1: [*c]const u8, buf_1_attr: *c.struct_tui_screen_attr, buf_2: [*c]const u8, buf_2_attr: *c.struct_tui_screen_attr, n: usize) void {
    var i: usize = 0;
    while (buf_1[i] != 0 and buf_2[i] != 0 and i < n) : (i += 1) {
        if (buf_1[i] != 0 and buf_1[i] != ' ') {
            _ = c.arcan_tui_writeu8(T, @ptrCast(&buf_1[i]), 1, buf_1_attr);
        } else {
            _ = c.arcan_tui_writeu8(T, @ptrCast(&buf_2[i]), 1, buf_2_attr);
        }
    }
}

fn draw_header(T: ?*c.struct_tui_context, M: *bufferwnd_meta, row: usize, cols: usize) void {
    var attr = c.arcan_tui_defcattr(T, c.TUI_COL_UI);
    if (cols <= 1) return;

    var buf: [256]u8 = undefined;
    @memset(&buf, ' ');

    const n = std.fmt.bufPrint(&buf, "{x}({x}+{x})", .{
        M.opts.offset + M.buffer_pos + M.buffer_ofs,
        M.opts.offset + M.buffer_pos,
        M.buffer_ofs,
    }) catch return;

    // Replace terminating NUL with space (drop the \0)
    if (n.len < buf.len)
        buf[n.len] = ' ';

    c.arcan_tui_move_to(T, row, 0);
    _ = c.arcan_tui_writeu8(T, &buf, cols, &attr);
}

fn draw_footer(T: ?*c.struct_tui_context, M: *bufferwnd_meta, row_ptr: *usize, col_ptr: *usize, rows_ptr: *usize, cols_ptr: *usize, mask_write: bool) void {
    const n_reserved: usize = 5;
    if (rows_ptr.* - row_ptr.* < n_reserved) return;

    if (mask_write) {
        rows_ptr.* -= n_reserved;
        return;
    }

    const rows = rows_ptr.*;
    const cols = cols_ptr.*;

    var reset_def = c.arcan_tui_defattr(T, null);
    var def = blk: {
        var a = std.mem.zeroes(c.struct_tui_screen_attr);
        a.unnamed_2.aflags = c.TUI_ATTR_COLOR_INDEXED;
        a.unnamed_0.fc[0] = c.TUI_COL_UI;
        a.unnamed_1.bc[0] = c.TUI_COL_UI;
        break :blk a;
    };
    var def_text = blk: {
        var a = std.mem.zeroes(c.struct_tui_screen_attr);
        a.unnamed_2.aflags = c.TUI_ATTR_COLOR_INDEXED;
        a.unnamed_0.fc[0] = c.TUI_COL_TEXT;
        a.unnamed_1.bc[0] = c.TUI_COL_TEXT;
        break :blk a;
    };

    var c_row = rows - n_reserved;
    _ = c.arcan_tui_defattr(T, &def);
    c.arcan_tui_erase_region(T, 0, c_row, cols, rows, false);
    _ = c.arcan_tui_defattr(T, &reset_def);

    // Build value union from buffer
    const buf_sz = M.buffer_sz - M.buffer_pos;
    var vbuf: [8]u8 = .{0} ** 8;
    const copy_n = @min(buf_sz, 8);
    @memcpy(vbuf[0..copy_n], M.buffer[M.buffer_pos + M.buffer_ofs .. M.buffer_pos + M.buffer_ofs + copy_n]);

    const l8: u8 = vbuf[0];
    const l16: u16 = @as(u16, vbuf[0]) | (@as(u16, vbuf[1]) << 8);
    const l32: u32 = @as(u32, vbuf[0]) | (@as(u32, vbuf[1]) << 8) | (@as(u32, vbuf[2]) << 16) | (@as(u32, vbuf[3]) << 24);
    const l64: u64 = @as(u64, l32) | (@as(u64, @as(u32, vbuf[4]) | (@as(u32, vbuf[5]) << 8) | (@as(u32, vbuf[6]) << 16) | (@as(u32, vbuf[7]) << 24)) << 32);
    const s8: i8 = @bitCast(l8);
    const s16: i16 = @bitCast(l16);
    const s32: i32 = @bitCast(l32);
    const s64: i64 = @bitCast(l64);
    const f: f32 = @bitCast(l32);
    const lf: f64 = @bitCast(l64);

    const w = cols - col_ptr.*;
    var work: [512]u8 = undefined;

    const row1_label = "x8:     x16:       x32:            x64:                                ";
    const row2_label = "u8:     u16:       u32:            u64:                                ";
    const row3_label = "s8:     s16:       s32:            s64:                               ";
    const row4_label = "Float:                  Double:              ASCII:";

    // Row 1: hex values
    const row1_data = std.fmt.bufPrint(&work, "   {x:0>2}       {x:0>4}       {x:0>8}       {x:0>16}", .{ l8, l16, l32, l64 }) catch "";
    c.arcan_tui_move_to(T, 0, c_row);
    write_mask(T, row1_label, &def, @ptrCast(row1_data.ptr), &def_text, w);
    c_row += 1;

    // Row 2: unsigned decimal
    const row2_data = std.fmt.bufPrint(&work, "   {d:0>3}      {d:0>5}    {d:0>12}      {d:0>20}", .{ l8, l16, l32, l64 }) catch "";
    c.arcan_tui_move_to(T, 0, c_row);
    write_mask(T, row2_label, &def, @ptrCast(row2_data.ptr), &def_text, w);
    c_row += 1;

    // Row 3: signed decimal
    const row3_data = std.fmt.bufPrint(&work, "   {d:0>4}     {d:0>6}     {d:0>11}     {d:0>21}", .{ s8, s16, s32, s64 }) catch "";
    c.arcan_tui_move_to(T, 0, c_row);
    write_mask(T, row3_label, &def, @ptrCast(row3_data.ptr), &def_text, w);
    c_row += 1;

    // Row 4: float/double
    const row4_data = std.fmt.bufPrint(&work, "      {d:.6}             {d:.6}                      ", .{ f, lf }) catch "";
    c.arcan_tui_move_to(T, 0, c_row);
    write_mask(T, row4_label, &def, @ptrCast(row4_data.ptr), &def_text, w);

    // ASCII column at the end of row 4
    const pos = row4_label.len;
    c.arcan_tui_move_to(T, pos, c_row);
    var bi: usize = 0;
    while (bi < cols - pos and bi < M.row_bytelen) : (bi += 1) {
        var ch: u8 = M.buffer[M.buffer_pos + M.buffer_ofs + bi];
        if (!std.ascii.isPrint(ch)) ch = '_';
        _ = c.arcan_tui_writeu8(T, &ch, 1, &def_text);
    }
    c_row += 1;

    c.arcan_tui_move_to(T, 0, c_row);
    _ = c.arcan_tui_writeu8(T, "Binary:", 7, &def);

    // Binary display
    var bit: u6 = 0;
    while (bit < 64) : (bit += 1) {
        const i: u6 = @intCast(bit);
        const ch: u8 = if ((l64 & (@as(u64, 1) << i)) != 0) '1' else '0';
        _ = c.arcan_tui_writeu8(T, &ch, 1, &def_text);
        if ((bit + 1) % 8 == 0) {
            // Dim the color
            if (def_text.unnamed_0.fc[0] > 40) def_text.unnamed_0.fc[0] -= 20;
            if (def_text.unnamed_0.fc[1] > 40) def_text.unnamed_0.fc[1] -= 20;
            if (def_text.unnamed_0.fc[2] > 40) def_text.unnamed_0.fc[2] -= 20;
            _ = c.arcan_tui_writeu8(T, " ", 1, &def_text);
        }
        if (bit == 63) break; // prevent overflow
    }

    rows_ptr.* -= n_reserved;
}

// Color lookup table decoded from hex_colors.h GIMP data
// We decode it at comptime to avoid needing the C include
const hex_color_tbl: [768]u8 = blk: {
    @setEvalBranchQuota(100000);
    const data = "!!!!SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`" ++
        "SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`" ++
        "E0]!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!" ++
        "``Q!``Q!``Q!``Q!``Q!``Q!``Q!``Q!``Q!``Q!`T!!`T!!`T!!`T!!`T!!`T!!" ++
        "`T!!!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM" ++
        "!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM`T!!`T!!`T!!`T!!`T!!" ++
        "`T!!!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G" ++
        "!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G`T!!`T!!`T!!`T!!`Q$3" ++
        "B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`" ++
        "B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`" ++
        "B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`" ++
        "B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`" ++
        "B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`" ++
        "B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`" ++
        "B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`" ++
        "B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`````";
    var result: [768]u8 = undefined;
    var di: usize = 0;
    var si: usize = 0;
    while (di < 256) : (di += 1) {
        const d0: u8 = data[si] - 33;
        const d1: u8 = data[si + 1] - 33;
        const d2: u8 = data[si + 2] - 33;
        const d3: u8 = data[si + 3] - 33;
        result[di * 3 + 0] = (d0 << 2) | (d1 >> 4);
        result[di * 3 + 1] = ((d1 & 0xF) << 4) | (d2 >> 2);
        result[di * 3 + 2] = ((d2 & 0x3) << 6) | d3;
        si += 4;
    }
    break :blk result;
};

fn monochrome(T: ?*c.struct_tui_context, tag: ?*anyopaque, bytev: u8, pos: usize, dch: *u32, attr: *c.struct_tui_screen_attr) callconv(.c) void {
    _ = T;
    _ = tag;
    _ = bytev;
    _ = pos;
    _ = dch;
    attr.unnamed_2.aflags |= c.TUI_ATTR_COLOR_INDEXED;
    attr.unnamed_0.fc[0] = c.TUI_COL_TEXT;
    attr.unnamed_1.bc[0] = c.TUI_COL_TEXT;
}

fn color_lut(T: ?*c.struct_tui_context, tag: ?*anyopaque, bytev: u8, pos: usize, dch: *u32, attr: *c.struct_tui_screen_attr) callconv(.c) void {
    _ = tag;
    _ = pos;
    _ = dch;
    attr.unnamed_0.fc[0] = hex_color_tbl[@as(usize, bytev) * 3 + 0];
    attr.unnamed_0.fc[1] = hex_color_tbl[@as(usize, bytev) * 3 + 1];
    attr.unnamed_0.fc[2] = hex_color_tbl[@as(usize, bytev) * 3 + 2];
    attr.unnamed_2.aflags &= ~@as(u16, c.TUI_ATTR_COLOR_INDEXED);
    c.arcan_tui_get_bgcolor(T, c.TUI_COL_TEXT, &attr.unnamed_1.bc);
}

fn flt_ascii(T: ?*c.struct_tui_context, wndbuf: [*c]u8, wndbuf_sz: usize, pos: usize) void {
    _ = T;
    _ = pos;
    var i: usize = 0;
    while (i < wndbuf_sz) : (i += 1) {
        if (!std.ascii.isAscii(wndbuf[i]))
            wndbuf[i] = ' ';
    }
}

fn flt_none(T: ?*c.struct_tui_context, wndbuf: [*c]u8, wndbuf_sz: usize, pos: usize) void {
    _ = T;
    _ = wndbuf;
    _ = wndbuf_sz;
    _ = pos;
}

fn step_col(T: ?*c.struct_tui_context, M: *bufferwnd_meta, rows: usize, cols: usize, start_row: usize, start_col: usize, new_row: *bool) bool {
    _ = start_col;
    _ = start_row;
    new_row.* = false;

    if (M.col + 1 >= cols) {
        if (M.row + 1 >= rows) {
            return false;
        } else {
            M.row += 1;
            new_row.* = true;
        }
        M.col = 0;
    } else {
        M.col += 1;
    }

    c.arcan_tui_move_to(T, M.col, M.row);
    return true;
}

fn redraw_text(
    T: ?*c.struct_tui_context,
    M: *bufferwnd_meta,
    rows: usize,
    cols: usize,
    start_row: usize,
    start_col: usize,
    color_lookup: attr_lookup_fn,
    text_filter: ?*const fn (T: ?*c.struct_tui_context, wndbuf: [*c]u8, wndbuf_sz: usize, pos: usize) void,
    mask_write: bool,
    on_offset: ?*const fn (T: ?*c.struct_tui_context, x: usize, y: usize) void,
    on_position: ?*const fn (T: ?*c.struct_tui_context, offset: usize) void,
) void {
    M.row = start_row;
    M.col = start_col;
    if (!mask_write) {
        M.row_bytelen = 0;
        M.cursor_ofs_row = start_row;
        M.cursor_ofs_row_end = rows - 1;
    }

    c.arcan_tui_move_to(T, M.row, M.col);
    const wndbuf_sz = rows * cols;

    const def = c.arcan_tui_defattr(T, null);

    var new_row: bool = false;
    var first_row: bool = true;
    var cursor_found: bool = false;

    var i: usize = 0;
    while (i < wndbuf_sz and i + M.buffer_pos < M.buffer_sz) : (i += 1) {
        var cattr = def;
        const ch: u8 = M.buffer[i + M.buffer_pos];

        if (new_row and first_row and !mask_write) {
            first_row = false;
            M.row_bytelen = i;
        }

        if (on_position != null and M.row == M.cursor_y and M.col == M.cursor_x) {
            on_position.?(T, i);
            break;
        }

        if (on_offset != null and i == M.buffer_ofs) {
            on_offset.?(T, M.col, M.row);
            break;
        }

        if (!mask_write) {
            var dch: u32 = 0;
            if (color_lookup) |clf| clf(T, M.opts.cbtag, ch, i + M.buffer_pos, &dch, &cattr);
        }

        if (M.opts.wrap_mode != c.BUFFERWND_WRAP_ALL) {
            if (ch == '\n') {
                M.col = cols;
                if (!step_col(T, M, rows, cols, start_row, start_col, &new_row))
                    break;
                continue;
            } else if (ch == '\r' and M.opts.wrap_mode == c.BUFFERWND_WRAP_ACCEPT_CR_LF) {
                if (i + M.buffer_pos + 1 < M.buffer_sz) {
                    if (M.buffer[i + M.buffer_pos + 1] != '\n') {
                        M.col = cols;
                        if (!step_col(T, M, rows, cols, start_row, start_col, &new_row))
                            break;
                    }
                    continue;
                }
            }
        }

        _ = text_filter;

        if (i == M.buffer_ofs and !mask_write) {
            M.cursor_x = M.col;
            M.cursor_y = M.row;
            cursor_found = true;
        }

        if (!mask_write) {
            _ = c.arcan_tui_writeu8(T, @ptrCast(&M.buffer[i + M.buffer_pos]), 1, &cattr);
        }

        if (!step_col(T, M, rows, cols, start_row, start_col, &new_row))
            break;
    }

    // Edge case: cursor outside visible window
    if (!cursor_found and !mask_write) {
        const cy = M.row;
        var cx = M.col;
        while (cx > 0) {
            const cur = c.arcan_tui_getxy(T, cx, cy, false);
            if (cur.ch != 0) break;
            cx -= 1;
        }
        M.cursor_x = cx;
        M.cursor_y = cy;
        M.buffer_ofs = screen_to_pos(T, M);
    }

    c.arcan_tui_move_to(T, M.cursor_x, M.cursor_y);
}

fn redraw_hex(
    T: ?*c.struct_tui_context,
    M: *bufferwnd_meta,
    rows_in: usize,
    cols: usize,
    start_row_in: usize,
    start_col: usize,
    detail: bool,
    color_lookup: attr_lookup_fn,
    mask_write: bool,
    on_offset: ?*const fn (T: ?*c.struct_tui_context, x: usize, y: usize) void,
    on_position: ?*const fn (T: ?*c.struct_tui_context, offset: usize) void,
) void {
    const def = c.arcan_tui_defattr(T, null);
    var rows = rows_in;
    var start_row = start_row_in;

    if (detail) {
        if (!mask_write)
            draw_header(T, M, start_row, cols);
        start_row += 1;

        draw_footer(T, M, &start_row, @constCast(&start_col), &rows, @constCast(&cols), mask_write);
    }

    if (!mask_write) {
        M.row_bytelen = 0;
        M.cursor_ofs_row = start_row;
        M.cursor_ofs_row_end = rows - 1;
    }

    var draw_cols = cols;
    if (M.opts.hex_mode > c.BUFFERWND_HEX_BASIC) {
        draw_cols = draw_cols - (draw_cols / 3);
    }

    if (draw_cols == 0) return;

    var i: usize = 0;
    var row = start_row;
    outer: while (row < rows and i < M.buffer_sz) : (row += 1) {
        const start_i = i;
        var col = start_col;

        while (col < draw_cols - 1 and i < M.buffer_sz) {
            if (i + M.buffer_pos >= M.buffer_sz) break :outer;

            if (on_position != null and row == M.cursor_y and col == M.cursor_x) {
                on_position.?(T, i);
                break :outer;
            }

            if (on_offset != null and i == M.buffer_ofs) {
                on_offset.?(T, col, row);
                break :outer;
            }

            if (!mask_write and i == M.buffer_ofs) {
                M.cursor_x = col + (if (M.cursor_halfb) @as(usize, 1) else @as(usize, 0));
                M.cursor_y = row;
            }

            const ch: u8 = M.buffer[i + M.buffer_pos];
            var cattr = def;

            if (!mask_write) {
                var dch: u32 = 0;
                if (color_lookup) |clf| clf(T, M.opts.cbtag, ch, i, &dch, &cattr);
                draw_hex_ch(T, &cattr, col, row, ch);
            }

            col += 3;
            i += 1;
        }

        // ASCII/annotation column
        if (draw_cols != cols) {
            var col2 = draw_cols + 1;
            var si = start_i;
            while (col2 < cols and si < i and !mask_write) : ({
                col2 += 1;
                si += 1;
            }) {
                const ch: u8 = M.buffer[si + M.buffer_pos];
                var dch: u32 = ch;
                var cattr = def;
                if (color_lookup) |clf| clf(T, M.opts.cbtag, ch, si + M.buffer_pos, &dch, &cattr);

                if (si == M.buffer_ofs) {
                    _ = c.arcan_tui_get_color(T, c.TUI_COL_CURSOR, &cattr.unnamed_1.bc);
                }

                c.arcan_tui_move_to(T, col2, row);
                c.arcan_tui_write(T, dch, &cattr);
            }
        }

        if (!mask_write) {
            if (row == start_row) {
                M.row_bytelen = i;
            }
            M.buffer_lend = i + M.buffer_pos;
        }
    }

    if (!mask_write)
        c.arcan_tui_move_to(T, M.cursor_x, M.cursor_y);
}

fn get_color_function(M: *bufferwnd_meta) attr_lookup_fn {
    switch (M.opts.color_mode) {
        c.BUFFERWND_COLOR_PALETTE => {
            return if (M.opts.view_mode < c.BUFFERWND_VIEW_HEX) monochrome else color_lut;
        },
        c.BUFFERWND_COLOR_CUSTOM => {
            if (M.opts.custom_attr) |f| return f;
            // fallthrough to NONE
        },
        else => {},
    }
    return monochrome;
}

fn screen_to_pos(T: ?*c.struct_tui_context, M: *bufferwnd_meta) usize {
    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(T, &rows, &cols);

    switch (M.opts.view_mode) {
        c.BUFFERWND_VIEW_ASCII => {
            redraw_text(T, M, rows, cols, 0, 0, null, flt_ascii, true, null, set_ofs);
        },
        c.BUFFERWND_VIEW_UTF8 => {
            redraw_text(T, M, rows, cols, 0, 0, null, flt_none, true, null, set_ofs);
        },
        c.BUFFERWND_VIEW_HEX, c.BUFFERWND_VIEW_HEX_DETAIL => {
            redraw_hex(T, M, rows, cols, 0, 0, M.opts.view_mode == c.BUFFERWND_VIEW_HEX_DETAIL, null, true, null, set_ofs);
        },
        else => {},
    }
    return resolve_temp.ofs;
}

fn pos_to_screen(T: ?*c.struct_tui_context, M: *bufferwnd_meta, x: *usize, y: *usize) void {
    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(T, &rows, &cols);

    switch (M.opts.view_mode) {
        c.BUFFERWND_VIEW_ASCII => {
            redraw_text(T, M, rows, cols, 0, 0, null, flt_ascii, true, set_pos, null);
        },
        c.BUFFERWND_VIEW_UTF8 => {
            redraw_text(T, M, rows, cols, 0, 0, null, flt_none, true, set_pos, null);
        },
        c.BUFFERWND_VIEW_HEX, c.BUFFERWND_VIEW_HEX_DETAIL => {
            redraw_hex(T, M, rows, cols, 0, 0, M.opts.view_mode == c.BUFFERWND_VIEW_HEX_DETAIL, null, true, set_pos, null);
        },
        else => {},
    }
    x.* = resolve_temp.x;
    y.* = resolve_temp.y;
}

fn redraw_bufferwnd(T: ?*c.struct_tui_context, M: *bufferwnd_meta) void {
    c.arcan_tui_erase_screen(T, false);
    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(T, &rows, &cols);
    _ = c.arcan_tui_set_flags(T, if (has_cursor(M)) 0 else c.TUI_HIDE_CURSOR);

    switch (M.opts.view_mode) {
        c.BUFFERWND_VIEW_ASCII => {
            redraw_text(T, M, rows, cols, 0, 0, get_color_function(M), flt_ascii, false, null, null);
        },
        c.BUFFERWND_VIEW_UTF8 => {
            redraw_text(T, M, rows, cols, 0, 0, get_color_function(M), flt_none, false, null, null);
        },
        c.BUFFERWND_VIEW_HEX => {
            redraw_hex(T, M, rows, cols, 0, 0, false, monochrome, false, null, null);
        },
        c.BUFFERWND_VIEW_HEX_DETAIL => {
            redraw_hex(T, M, rows, cols, 0, 0, rows > min_meta_rows, get_color_function(M), false, null, null);
        },
        else => {},
    }
}

fn on_resized(T: ?*c.struct_tui_context, neww: usize, newh: usize, col: usize, row: usize, t: ?*anyopaque) callconv(.c) void {
    _ = neww;
    _ = newh;
    _ = col;
    _ = row;
    const M: *bufferwnd_meta = @ptrCast(@alignCast(t orelse return));
    redraw_bufferwnd(T, M);
}

fn on_recolor(T: ?*c.struct_tui_context, t: ?*anyopaque) callconv(.c) void {
    const M: *bufferwnd_meta = @ptrCast(@alignCast(t orelse return));
    redraw_bufferwnd(T, M);
}

fn label_wrap_cycle(T: ?*c.struct_tui_context, M: *bufferwnd_meta) bool {
    switch (M.opts.wrap_mode) {
        c.BUFFERWND_WRAP_ACCEPT_CR_LF => M.opts.wrap_mode = c.BUFFERWND_WRAP_ALL,
        c.BUFFERWND_WRAP_ACCEPT_LF => M.opts.wrap_mode = c.BUFFERWND_WRAP_ACCEPT_CR_LF,
        c.BUFFERWND_WRAP_ALL => M.opts.wrap_mode = c.BUFFERWND_WRAP_ACCEPT_LF,
        else => {},
    }
    redraw_bufferwnd(T, M);
    return true;
}

fn label_color_cycle(T: ?*c.struct_tui_context, M: *bufferwnd_meta) bool {
    if (M.opts.color_mode == c.BUFFERWND_COLOR_NONE) {
        M.opts.color_mode = c.BUFFERWND_COLOR_PALETTE;
    } else if (M.opts.color_mode == c.BUFFERWND_COLOR_PALETTE) {
        if (M.opts.custom_attr != null) {
            M.opts.color_mode = c.BUFFERWND_COLOR_CUSTOM;
        } else {
            M.opts.color_mode = c.BUFFERWND_COLOR_NONE;
        }
    }
    redraw_bufferwnd(T, M);
    return true;
}

fn label_hex_cycle(T: ?*c.struct_tui_context, M: *bufferwnd_meta) bool {
    M.opts.view_mode = c.BUFFERWND_VIEW_HEX;

    if (M.opts.hex_mode == c.BUFFERWND_HEX_BASIC) {
        M.opts.hex_mode = c.BUFFERWND_HEX_ASCII;
    } else if (M.opts.hex_mode == c.BUFFERWND_HEX_ASCII) {
        M.opts.hex_mode = c.BUFFERWND_HEX_BASIC;
    }
    // BUFFERWND_HEX_ANNOTATE and BUFFERWND_HEX_META are incomplete in the original

    if (M.opts.view_mode >= c.BUFFERWND_VIEW_HEX) {
        redraw_bufferwnd(T, M);
    }
    return true;
}

fn label_view_cycle(T: ?*c.struct_tui_context, M: *bufferwnd_meta) bool {
    M.cursor_halfb = false;
    switch (M.opts.view_mode) {
        c.BUFFERWND_VIEW_ASCII => M.opts.view_mode = c.BUFFERWND_VIEW_UTF8,
        c.BUFFERWND_VIEW_UTF8 => M.opts.view_mode = c.BUFFERWND_VIEW_HEX,
        c.BUFFERWND_VIEW_HEX => M.opts.view_mode = c.BUFFERWND_VIEW_HEX_DETAIL,
        c.BUFFERWND_VIEW_HEX_DETAIL => M.opts.view_mode = c.BUFFERWND_VIEW_ASCII,
        else => {},
    }
    redraw_bufferwnd(T, M);
    return true;
}

const LabelEnt = struct {
    handler: *const fn (T: ?*c.struct_tui_context, M: *bufferwnd_meta) bool,
    label: []const u8,
    descr: []const u8,
    initial: u16,
};

const labels = [_]LabelEnt{
    .{ .handler = label_wrap_cycle, .label = "WRAP", .descr = "Cycle wrapping modes", .initial = c.TUIK_F3 },
    .{ .handler = label_view_cycle, .label = "VIEW", .descr = "Cycle presentation modes (ASCII/UTF8/...)", .initial = c.TUIK_F4 },
    .{ .handler = label_color_cycle, .label = "COLOR", .descr = "Cycle coloring modes (byte value, type, ...)", .initial = c.TUIK_F5 },
    .{ .handler = label_hex_cycle, .label = "HEX_MODE", .descr = "Cycle hex modes (ascii column, annotations, ...)", .initial = c.TUIK_F6 },
};

fn on_label_input(T: ?*c.struct_tui_context, label: [*c]const u8, active: bool, tag: ?*anyopaque) callconv(.c) bool {
    if (!active) return true;

    const M: *bufferwnd_meta = @ptrCast(@alignCast(tag orelse return false));

    for (&labels) |*entry| {
        if (cstreql_lit(label, entry.label)) {
            return entry.handler(T, M);
        }
    }

    // Chain onwards
    if (M.old_handlers.input_label) |f|
        return castHandler(InputLabelFn, f)(T, label, active, M.old_handlers.tag);

    return false;
}

fn on_label_query(T: ?*c.struct_tui_context, index: usize, country: [*c]const u8, lang: [*c]const u8, dstlbl: [*c]c.struct_tui_labelent, t: ?*anyopaque) callconv(.c) bool {
    _ = T;
    const M: *bufferwnd_meta = @ptrCast(@alignCast(t orelse return false));

    if (labels.len < index + 1) {
        if (M.old_handlers.query_label) |f|
            return castHandler(QueryLabelFn, f)(null, index - labels.len - 1, country, lang, dstlbl, M.old_handlers.tag);
        return false;
    }

    const entry = &labels[index];
    const dst = &dstlbl[0];
    dst.* = std.mem.zeroes(c.struct_tui_labelent);
    copyStr(&dst.label, entry.label);
    copyStr(&dst.descr, entry.descr);
    dst.initial = entry.initial;
    return true;
}

fn on_subwindow(T: ?*c.struct_tui_context, conn: ?*c.struct_arcan_shmif_cont, id: u32, _: u8, _: ?*anyopaque) callconv(.c) bool {
    var M: ?*bufferwnd_meta = null;
    if (!validate_context(T, &M)) return false;

    if (M.?.old_handlers.subwindow) |f|
        return castHandler(SubwindowFn, f)(T, conn, id, 0, M.?.old_handlers.tag);

    return false;
}

fn on_u8(T: ?*c.struct_tui_context, u8str: [*c]const u8, len: usize, tag: ?*anyopaque) callconv(.c) bool {
    const M: *bufferwnd_meta = @ptrCast(@alignCast(tag orelse return false));
    if (M.opts.read_only) return false;

    switch (M.opts.view_mode) {
        c.BUFFERWND_VIEW_ASCII => {
            if (len != 1) return false;
            if (M.opts.commit) |commit_fn| {
                if (!commit_fn(T, M.opts.cbtag, @ptrCast(u8str), len, M.buffer_pos + M.buffer_ofs))
                    return true;
            }
            M.buffer[M.buffer_pos + M.buffer_ofs] = u8str[0];
            step_cursor_e(T, M);
            redraw_bufferwnd(T, M);
        },
        c.BUFFERWND_VIEW_UTF8 => {
            // Not implemented in original
        },
        c.BUFFERWND_VIEW_HEX, c.BUFFERWND_VIEW_HEX_DETAIL => {
            if (!std.ascii.isHex(u8str[0])) return false;

            if (M.opts.commit) |commit_fn| {
                if (!commit_fn(T, M.opts.cbtag, @ptrCast(u8str), len, M.buffer_pos + M.buffer_ofs))
                    return true;
            }

            var nibble: u8 = u8str[0];
            const inb: u8 = M.buffer[M.buffer_pos + M.buffer_ofs];

            if (nibble >= '0' and nibble <= '9') {
                nibble = nibble - '0';
            } else {
                nibble = 10 + (std.ascii.toLower(nibble) - 'a');
            }

            if (!M.cursor_halfb) {
                nibble = nibble * 16 + (inb & 15);
            } else {
                nibble = nibble + (inb & 0xf0);
            }

            M.buffer[M.buffer_pos + M.buffer_ofs] = nibble;
            step_cursor_e(T, M);
            redraw_bufferwnd(T, M);
            return true;
        },
        else => {},
    }
    return false;
}

fn scroll_page_down(T: ?*c.struct_tui_context, M: *bufferwnd_meta) void {
    switch (M.opts.view_mode) {
        c.BUFFERWND_VIEW_UTF8, c.BUFFERWND_VIEW_ASCII => {
            // Need to sweep the buffer — not fully implemented
        },
        c.BUFFERWND_VIEW_HEX, c.BUFFERWND_VIEW_HEX_DETAIL => {
            const step = M.row_bytelen * (M.cursor_ofs_row_end - M.cursor_ofs_row);
            M.buffer_pos += M.row_bytelen * (M.cursor_ofs_row_end - M.cursor_ofs_row);
            if (M.buffer_pos + M.row_bytelen > M.buffer_sz)
                M.buffer_pos = M.buffer_sz - step;
        },
        else => {},
    }
    redraw_bufferwnd(T, M);
}

fn scroll_page_up(T: ?*c.struct_tui_context, M: *bufferwnd_meta) void {
    switch (M.opts.view_mode) {
        c.BUFFERWND_VIEW_UTF8, c.BUFFERWND_VIEW_ASCII => {},
        c.BUFFERWND_VIEW_HEX, c.BUFFERWND_VIEW_HEX_DETAIL => {
            const step = M.row_bytelen * (M.cursor_ofs_row_end - M.cursor_ofs_row);
            if (M.buffer_pos > step)
                M.buffer_pos -= step
            else
                M.buffer_pos = 0;
        },
        else => {},
    }
    redraw_bufferwnd(T, M);
}

fn scroll_row_down(T: ?*c.struct_tui_context, M: *bufferwnd_meta) void {
    switch (M.opts.view_mode) {
        c.BUFFERWND_VIEW_UTF8, c.BUFFERWND_VIEW_ASCII => {
            M.cursor_x = 0;
            M.cursor_y = 1;
            const pos = screen_to_pos(T, M);
            if (M.buffer_pos + pos < M.buffer_sz) {
                M.buffer_pos += pos;
            }
        },
        c.BUFFERWND_VIEW_HEX, c.BUFFERWND_VIEW_HEX_DETAIL => {
            if (M.buffer_pos + M.row_bytelen < M.buffer_sz)
                M.buffer_pos += M.row_bytelen;
        },
        else => {},
    }
    redraw_bufferwnd(T, M);
}

fn scroll_row_up(T: ?*c.struct_tui_context, M: *bufferwnd_meta) void {
    switch (M.opts.view_mode) {
        c.BUFFERWND_VIEW_UTF8, c.BUFFERWND_VIEW_ASCII => {
            var cofs: usize = 1;
            var cols: usize = 0;
            var in_linefeed: bool = false;
            {
                var _r: usize = 0;
                c.arcan_tui_dimensions(T, &_r, &cols);
            }

            while (cofs < M.buffer_pos and cols > 0) {
                const ch: u8 = M.buffer[M.buffer_pos - cofs];
                if (ch == '\n' or ch == '\r') {
                    if (M.opts.wrap_mode != c.BUFFERWND_WRAP_ALL) {
                        if (in_linefeed) {
                            if (cofs > 0) cofs -= 1;
                            break;
                        }
                        in_linefeed = true;
                    }
                }
                cols -= 1;
                if (cols > 0) cofs += 1;
            }
            M.buffer_pos -= if (M.buffer_pos > cofs) cofs else M.buffer_pos;
        },
        c.BUFFERWND_VIEW_HEX, c.BUFFERWND_VIEW_HEX_DETAIL => {
            M.buffer_pos -= if (M.buffer_pos > M.row_bytelen) M.row_bytelen else M.buffer_pos;
        },
        else => {},
    }
    redraw_bufferwnd(T, M);
}

fn realign_update(T: ?*c.struct_tui_context, M: *bufferwnd_meta, cx_in: usize, cy: usize) void {
    var cx = cx_in;
    var align_cursor = true;

    if (M.opts.view_mode == c.BUFFERWND_VIEW_UTF8 or M.opts.view_mode == c.BUFFERWND_VIEW_ASCII) {
        if (M.opts.wrap_mode == c.BUFFERWND_WRAP_ALL)
            align_cursor = false;
    }

    while (align_cursor and cx > 0) {
        const cur = c.arcan_tui_getxy(T, cx, cy, false);
        if (cur.ch != 0) break;
        cx -= 1;
    }

    M.cursor_x = cx;
    M.cursor_y = cy;
    M.buffer_ofs = screen_to_pos(T, M);

    c.arcan_tui_move_to(T, M.cursor_x, M.cursor_y);
}

fn step_cursor_s(T: ?*c.struct_tui_context, M: *bufferwnd_meta) void {
    const cx = M.cursor_x;
    var cy = M.cursor_y;
    const vm = M.opts.view_mode;

    if (cy + 1 > M.cursor_ofs_row_end) {
        scroll_row_down(T, M);
        return;
    } else {
        cy = cy + 1;
    }

    if (M.cursor_halfb) {
        const cx2 = if (cx > 0) cx - 1 else 0;
        realign_update(T, M, cx2, cy);
        M.cursor_x += 1;
        c.arcan_tui_move_to(T, M.cursor_x, M.cursor_y);
    } else {
        realign_update(T, M, cx, cy);
    }

    if (vm == c.BUFFERWND_VIEW_HEX_DETAIL)
        redraw_bufferwnd(T, M);
}

fn step_cursor_n(T: ?*c.struct_tui_context, M: *bufferwnd_meta) void {
    const cx = M.cursor_x;
    var cy = M.cursor_y;
    const vm = M.opts.view_mode;

    if (cy == M.cursor_ofs_row) {
        scroll_row_up(T, M);
        return;
    } else {
        cy = cy - 1;
    }

    if (M.cursor_halfb) {
        const cx2 = if (cx > 0) cx - 1 else 0;
        realign_update(T, M, cx2, cy);
        M.cursor_x += 1;
        c.arcan_tui_move_to(T, M.cursor_x, M.cursor_y);
    } else {
        realign_update(T, M, cx, cy);
    }

    if (vm == c.BUFFERWND_VIEW_HEX_DETAIL)
        redraw_bufferwnd(T, M);
}

fn step_cursor_w(T: ?*c.struct_tui_context, M: *bufferwnd_meta) void {
    const vm = M.opts.view_mode;
    var cofs: isize = 0;

    if ((vm == c.BUFFERWND_VIEW_HEX or vm == c.BUFFERWND_VIEW_HEX_DETAIL) and !M.opts.read_only) {
        if (M.cursor_halfb) {
            M.cursor_halfb = false;
            if (M.cursor_x > 0) M.cursor_x -= 1;
            c.arcan_tui_move_to(T, M.cursor_x, M.cursor_y);
            return;
        } else {
            M.cursor_halfb = true;
            cofs = 1;
        }
    }

    if (M.buffer_ofs == 0) {
        if (M.buffer_pos > 0) {
            M.buffer_ofs = M.row_bytelen - 1;
            scroll_row_up(T, M);
        }
    } else {
        M.buffer_ofs -= 1;
        pos_to_screen(T, M, &M.cursor_x, &M.cursor_y);
        if (cofs > 0) M.cursor_x += @intCast(cofs);
        c.arcan_tui_move_to(T, M.cursor_x, M.cursor_y);
    }

    if (vm == c.BUFFERWND_VIEW_HEX_DETAIL)
        redraw_bufferwnd(T, M);
}

fn step_cursor_e(T: ?*c.struct_tui_context, M: *bufferwnd_meta) void {
    const vm = M.opts.view_mode;

    if ((vm == c.BUFFERWND_VIEW_HEX or vm == c.BUFFERWND_VIEW_HEX_DETAIL) and !M.opts.read_only) {
        if (!M.cursor_halfb) {
            M.cursor_halfb = true;
            M.cursor_x += 1;
            c.arcan_tui_move_to(T, M.cursor_x, M.cursor_y);
            return;
        } else {
            M.cursor_halfb = false;
        }
    }

    if (M.buffer_ofs == M.buffer_lend - 1) {
        M.buffer_ofs -= M.row_bytelen - 1;
        step_cursor_s(T, M);
    } else {
        M.buffer_ofs += 1;
        pos_to_screen(T, M, &M.cursor_x, &M.cursor_y);
        c.arcan_tui_move_to(T, M.cursor_x, M.cursor_y);
    }

    if (vm == c.BUFFERWND_VIEW_HEX_DETAIL) {
        redraw_bufferwnd(T, M);
    }
}

fn on_key_input(T: ?*c.struct_tui_context, keysym: u32, scancode: u8, mods: u16, subid: u16, tag: ?*anyopaque) callconv(.c) void {
    _ = scancode;
    _ = subid;
    const M: *bufferwnd_meta = @ptrCast(@alignCast(tag orelse return));

    if (keysym == c.TUIK_DOWN or keysym == c.TUIK_J) {
        if (has_cursor(M))
            step_cursor_s(T, M)
        else
            scroll_row_down(T, M);
    } else if (keysym == c.TUIK_UP or keysym == c.TUIK_K) {
        if (has_cursor(M))
            step_cursor_n(T, M)
        else
            scroll_row_up(T, M);
    } else if (keysym == c.TUIK_LEFT or keysym == c.TUIK_H) {
        if (has_cursor(M))
            step_cursor_w(T, M)
        else
            scroll_row_up(T, M);
    } else if (keysym == c.TUIK_RIGHT or keysym == c.TUIK_L) {
        if (has_cursor(M))
            step_cursor_e(T, M)
        else
            scroll_row_down(T, M);
    } else if (keysym == c.TUIK_PAGEDOWN) {
        scroll_page_down(T, M);
    } else if (keysym == c.TUIK_PAGEUP) {
        scroll_page_up(T, M);
    } else if (keysym == c.TUIK_ESCAPE or
        (keysym == c.TUIK_RETURN and (mods & (c.TUIM_LSHIFT | c.TUIM_RSHIFT)) != 0))
    {
        if (!M.opts.allow_exit) return;
        M.exit_status = if (keysym == c.TUIK_RETURN) 0 else -1;
    }
}

export fn arcan_tui_bufferwnd_synch(T: ?*c.struct_tui_context, buf: [*c]u8, buf_sz: usize, prefix_ofs: usize) void {
    var M: ?*bufferwnd_meta = null;
    if (buf == null or buf_sz == 0 or !validate_context(T, &M)) return;

    const m = M.?;
    m.buffer = buf;
    m.buffer_sz = buf_sz;
    m.buffer_ofs = 0;
    m.buffer_pos = 0;
    m.exit_status = 1;
    m.cursor_x = 0;
    m.cursor_y = 0;
    m.cursor_halfb = false;
    m.cursor_ofs_col = 0;
    m.cursor_ofs_row = 0;
    m.cursor_ofs_row_end = 0;
    m.opts.offset = prefix_ofs;

    redraw_bufferwnd(T, m);
}

export fn arcan_tui_bufferwnd_seek(T: ?*c.struct_tui_context, buf_pos: usize) void {
    var M: ?*bufferwnd_meta = null;
    if (!validate_context(T, &M)) return;

    const m = M.?;
    var pos = buf_pos;
    if (pos >= m.buffer_sz)
        pos = m.buffer_sz - 1;

    const n_rows = m.cursor_ofs_row_end - m.cursor_ofs_row;
    const bpp = n_rows * m.row_bytelen;

    if (pos < bpp) {
        m.buffer_pos = 0;
        m.buffer_ofs = pos;
    } else {
        m.buffer_pos = (pos / bpp) * bpp;
        m.buffer_ofs = pos - m.buffer_pos;
    }

    redraw_bufferwnd(T, m);
}

fn mouse_button(T: ?*c.struct_tui_context, last_x: c_int, last_y: c_int, button: c_int, active: bool, modifiers: c_int, tag: ?*anyopaque) callconv(.c) void {
    _ = modifiers;
    const M: *bufferwnd_meta = @ptrCast(@alignCast(tag orelse return));
    if (!active) return;

    if (button == c.TUIBTN_WHEEL_UP) {
        step_cursor_n(T, M);
        return;
    } else if (button == c.TUIBTN_WHEEL_DOWN) {
        step_cursor_s(T, M);
        return;
    }

    M.cursor_x = @intCast(last_x);
    M.cursor_y = @intCast(last_y);

    if (M.opts.view_mode == c.BUFFERWND_VIEW_HEX_DETAIL or M.opts.view_mode == c.BUFFERWND_VIEW_HEX) {
        if (M.cursor_x != 0 and M.cursor_x % 3 != 0)
            M.cursor_x -= M.cursor_x % 3;
    }

    const old_pos = M.buffer_ofs;
    M.buffer_ofs = screen_to_pos(T, M);

    if (old_pos == M.buffer_ofs) return;

    var x: usize = 0;
    var y: usize = 0;
    pos_to_screen(T, M, &x, &y);
    M.cursor_x = x;
    M.cursor_y = y;

    redraw_bufferwnd(T, M);
}

export fn arcan_tui_bufferwnd_setup(T: ?*c.struct_tui_context, buf: [*c]u8, buf_sz: usize, opts: ?*c.struct_tui_bufferwnd_opts, opt_sz: usize) void {
    _ = opt_sz;

    const meta: *bufferwnd_meta = @ptrCast(@alignCast(std.c.malloc(@sizeOf(bufferwnd_meta)) orelse return));
    meta.* = std.mem.zeroes(bufferwnd_meta);
    meta.magic = BUFFERWND_MAGIC;
    meta.buffer = buf;
    meta.buffer_sz = buf_sz;
    meta.exit_status = 1;

    var orig_h: usize = 0;
    var orig_w: usize = 0;
    c.arcan_tui_dimensions(T, &orig_h, &orig_w);
    meta.orig_h = orig_h;
    meta.orig_w = orig_w;

    if (orig_w < 80 or orig_h < 24) {
        c.arcan_tui_wndhint(T, null, c.struct_tui_constraints{
            .min_cols = -1,
            .min_rows = -1,
            .max_cols = 80,
            .max_rows = 24,
            .anch_row = -1,
            .anch_col = -1,
            .hide = 0,
            .embed = 0,
        });
    }

    if (opts) |o| meta.opts = o.*;

    var cbcfg = std.mem.zeroes(c.struct_tui_cbcfg);
    cbcfg.tag = @ptrCast(meta);
    cbcfg.resized = @ptrCast(@constCast(&on_resized));
    cbcfg.query_label = @ptrCast(@constCast(&on_label_query));
    cbcfg.input_label = @ptrCast(@constCast(&on_label_input));
    cbcfg.input_key = @ptrCast(@constCast(&on_key_input));
    cbcfg.input_mouse_button = @ptrCast(@constCast(&mouse_button));
    cbcfg.input_utf8 = @ptrCast(@constCast(&on_u8));
    cbcfg.subwindow = @ptrCast(@constCast(&on_subwindow));
    cbcfg.recolor = @ptrCast(@constCast(&on_recolor));

    meta.old_flags = c.arcan_tui_set_flags(T, c.TUI_ALTERNATE | c.TUI_MOUSE);

    _ = c.arcan_tui_update_handlers(T, &cbcfg, &meta.old_handlers, @sizeOf(c.struct_tui_cbcfg));

    c.arcan_tui_reset_labels(T);
    redraw_bufferwnd(T, meta);
}

export fn arcan_tui_bufferwnd_status(T: ?*c.struct_tui_context) c_int {
    var meta: ?*bufferwnd_meta = null;
    if (!validate_context(T, &meta)) return -1;
    return meta.?.exit_status;
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

fn copyStr(dst: anytype, src: []const u8) void {
    const dst_slice: []u8 = dst;
    const copy_len = @min(src.len, dst_slice.len - 1);
    @memcpy(dst_slice[0..copy_len], src[0..copy_len]);
    dst_slice[copy_len] = 0;
}
