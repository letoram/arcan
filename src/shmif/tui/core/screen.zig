// Pure Zig port of tui/core/screen.c
// Manages TUI screen buffering, tpack serialization/deserialization, and refresh.
//
// tui_context is opaque (contains bitfields/_Atomic fields), accessed via
// verified byte offsets from gcc offsetof on Linux aarch64.
//
// tui_raster_header and tui_raster_line are __attribute__((packed)) C structs;
// we model them as byte arrays since Zig packed structs round to power-of-2 sizes.
//
// Varargs/errno/struct-by-value wrappers formerly in screen_shim.c are now inlined.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const arcan = @import("arcan");

// raster wire format constants (raster/raster_const.h)
const raster_cell_sz: usize = 12;
const raster_hdr_sz:  usize = 16;
const raster_line_sz: usize = 9;

// dirty-state bitmask (tui_int.h)
const DIRTY_NONE:    u32 = 0;
const DIRTY_CURSOR:  u32 = 1;
const DIRTY_PARTIAL: u32 = 2;
const DIRTY_FULL:    u32 = 4;

// raster flags (enum raster_flags)
const RPACK_IFRAME: u16 = 1;
const RPACK_DFRAME: u16 = 2;

// cursor states (enum cursor_states)
const CURSOR_NONE:     u8 = 0;
const CURSOR_INACTIVE: u8 = 1;
const CURSOR_ACTIVE:   u8 = 2;
const CURSOR_EXTHDRv1: u8 = 8;
const CURSOR_BLOCK:    u8 = 16;
const CURSOR_BAR:      u8 = 32;
const CURSOR_UNDER:    u8 = 64;
const CURSOR_HOLLOW:   u8 = 128;

// cell attribute bits (enum cell_attr)
const CATTR_BOLD:          u8 = 1;
const CATTR_UNDERLINE:     u8 = 2;
const CATTR_UNDERLINE_ALT: u8 = 4;
const CATTR_ITALIC:        u8 = 8;
const CATTR_STRIKETHROUGH: u8 = 16;
const CATTR_CURSOR:        u8 = 32;
const CATTR_SHAPEBREAK:    u8 = 64;

// cell extended attribute bits (enum cell_extr_attr)
const CEATTR_GLYPH_IND:  u8 = 1;
const CEATTR_AGLYPH_IND: u8 = 2;
const CEATTR_BORDER_R:   u8 = 4;
const CEATTR_BORDER_D:   u8 = 8;
const CEATTR_BORDER_L:   u8 = 16;
const CEATTR_BORDER_T:   u8 = 32;

// TUI cell attribute flags (arcan_tui.h TUI_ATTR_*)
const TUI_ATTR_BOLD:           u16 = 1;
const TUI_ATTR_UNDERLINE:      u16 = 2;
const TUI_ATTR_UNDERLINE_ALT:  u16 = 4;
const TUI_ATTR_ITALIC:         u16 = 8;
const TUI_ATTR_INVERSE:        u16 = 16;
const TUI_ATTR_STRIKETHROUGH:  u16 = 128;
const TUI_ATTR_SHAPE_BREAK:    u16 = 256;
const TUI_ATTR_COLOR_INDEXED:  u16 = 512;
const TUI_ATTR_GLYPH_INDEXED:  u16 = 1024;
const TUI_ATTR_AGLYPH_INDEXED: u16 = 2048;
const TUI_ATTR_BORDER_RIGHT:   u16 = 4096;
const TUI_ATTR_BORDER_DOWN:    u16 = 8192;
const TUI_ATTR_BORDER_LEFT:    u16 = 16384;
const TUI_ATTR_BORDER_TOP:     u16 = 32768;

// TUI color group indices
const TUI_COL_BG:     c_int  = 4;
const TUI_COL_CURSOR: usize  = 6;
const TUI_COL_LIMIT:  usize  = 36;

// SHMIF signal flags
const SHMIF_SIGVID:      c_int = 1;
const SHMIF_SIGBLK_NONE: c_int = 4;

// tui_raster_header byte layout (16 bytes, C __attribute__((packed)))
//   [0..3]  u32 data_sz
//   [4..5]  u16 lines
//   [6..7]  u16 cells
//   [8]     u8  direction
//   [9..10] u16 flags
//   [11..14] u8 bgc[4]
//   [15]    u8  cursor_state
const HDR_SZ:               usize = 16;
const HDR_OFF_DATA_SZ:      usize = 0;
const HDR_OFF_LINES:        usize = 4;
const HDR_OFF_CELLS:        usize = 6;
const HDR_OFF_FLAGS:        usize = 9;
const HDR_OFF_BGC:          usize = 11;
const HDR_OFF_CURSOR_STATE: usize = 15;

// tui_raster_line byte layout (9 bytes, C __attribute__((packed)))
//   [0..1] u16 start_line
//   [2..3] u16 ncells
//   [4..5] u16 offset
//   [6]    u8  content_dir
//   [7]    u8  scroll_dir
//   [8]    u8  line_state
const LINE_SZ:             usize = 9;
const LINE_OFF_START_LINE: usize = 0;
const LINE_OFF_NCELLS:     usize = 2;
const LINE_OFF_OFFSET:     usize = 4;

// Little-endian byte helpers

fn readU16LE(buf: [*]const u8, off: usize) u16 {
    return @as(u16, buf[off]) | (@as(u16, buf[off + 1]) << 8);
}
fn writeU16LE(buf: [*]u8, off: usize, v: u16) void {
    buf[off]     = @truncate(v);
    buf[off + 1] = @truncate(v >> 8);
}
fn readU32LE(buf: [*]const u8, off: usize) u32 {
    return @as(u32, buf[off]) |
           (@as(u32, buf[off + 1]) << 8) |
           (@as(u32, buf[off + 2]) << 16) |
           (@as(u32, buf[off + 3]) << 24);
}
fn writeU32LE(buf: [*]u8, off: usize, v: u32) void {
    buf[off]     = @truncate(v);
    buf[off + 1] = @truncate(v >> 8);
    buf[off + 2] = @truncate(v >> 16);
    buf[off + 3] = @truncate(v >> 24);
}

// tpack_gen_opts: must match C struct layout
// C: struct tpack_gen_opts { bool full; bool synch; bool back; }
const TpackGenOpts = extern struct {
    full:  bool,
    synch: bool,
    back:  bool,
};

// tui_context field byte offsets (gcc offsetof on Linux aarch64)
const O_BASE:    usize = 24;   // struct tui_cell* base
const O_FRONT:   usize = 32;   // struct tui_cell* front
const O_BACK:    usize = 40;   // struct tui_cell* back
const O_ROWS:    usize = 228;  // int rows
const O_COLS:    usize = 232;  // int cols
const O_DIRTY:   usize = 128;  // enum dirty_state dirty  (int-sized)
const O_CELL_W:  usize = 404;  // int cell_w
const O_CELL_H:  usize = 408;  // int cell_h
const O_PAD_W:   usize = 412;  // int pad_w
const O_PAD_H:   usize = 416;  // int pad_h
const O_CX:      usize = 420;  // int cx
const O_CY:      usize = 424;  // int cy
const O_SBOFS:   usize = 240;  // long sbofs
const O_DEFOCUS: usize = 211;  // bool defocus

const O_CURSOR:                usize = 728;  // enum tui_cursors cursor (int-sized)
const O_CURSOR_OFF:            usize = 684;  // bool cursor_off
const O_CURSOR_HARD_OFF:       usize = 685;  // bool cursor_hard_off
const O_CURSOR_COLOR_OVERRIDE: usize = 732;  // bool cursor_color_override
const O_CURSOR_COLOR:          usize = 733;  // uint8_t cursor_color[3]
const O_ALPHA:                 usize = 736;  // uint8_t alpha

// colors[TUI_COL_LIMIT]: sizeof(struct color) = 7 (rgb[3] at 0, bg[3] at 3, bgset at 6)
const O_COLORS:  usize = 432;
const COLOR_SZ:  usize = 7;
const COLOR_RGB: usize = 0;
const COLOR_BG:  usize = 3;

// last_cursor substruct
const O_LAST_CURSOR_ACTIVE: usize = 696;  // bool active
const O_LAST_CURSOR_ROW:    usize = 704;  // size_t row
const O_LAST_CURSOR_COL:    usize = 712;  // size_t col

// hooks substruct fn ptrs
const O_HOOKS_REFRESH:       usize = 3864;
const O_HOOKS_RESIZE:        usize = 3856;
const O_HOOKS_CURSOR_LOOKUP: usize = 3872;

// handlers (tui_cbcfg): base = O_HANDLERS, cbcfg.tag at offset 0
const O_HANDLERS:         usize = 3880;
const O_HANDLERS_TAG:     usize = 3880 + 0;
const O_HANDLERS_RESIZE:  usize = 3880 + 168;
const O_HANDLERS_RESIZED: usize = 3880 + 120;

// arcan_shmif_cont embedded at O_ACON
const O_ACON:             usize = 2808;
const SHMIF_OFF_ADDR:     usize = 0;    // arcan_shmif_page* addr
const SHMIF_OFF_VIDB:     usize = 8;    // uint8_t* vidb
const SHMIF_OFF_W:        usize = 80;   // size_t w
const SHMIF_OFF_H:        usize = 88;   // size_t h
const SHMIF_OFF_VBUFSIZE: usize = 184;  // size_t vbufsize

// parent / children[256]
const O_PARENT:   usize = 752;
const O_CHILDREN: usize = 760;

// tpack recording
const O_TPACK_RECDST: usize = 216;  // FILE*

// last_constraints (anch_row at 0, anch_col at 4 within struct)
const O_LAST_CONSTRAINTS:       usize = 3648;
const CONSTRAINTS_OFF_ANCH_ROW: usize = 0;
const CONSTRAINTS_OFF_ANCH_COL: usize = 4;

// viewport_proxy (uint32_t)
const O_VIEWPORT_PROXY: usize = 3388;

// tui_cell layout
// sizeof(struct tui_cell) = 28
// tui_screen_attr at 0 (10 bytes): fc[3] at 0, bc[3] at 3, aflags u16 at 6,
//                                   custom_id u8 at 8, pad u8 at 9
// ch  (u32) at 12
// draw_ch, real_x, cell_w, fstamp at 16, 20, 24, 25 (not used by screen.c)
const TUI_CELL_SZ: usize = 28;
const CELL_OFF_FC:  usize = 0;   // attr.fc[3]
const CELL_OFF_BC:  usize = 3;   // attr.bc[3]
const CELL_OFF_AFF: usize = 6;   // attr.aflags (u16 LE)
const CELL_OFF_CH:  usize = 12;  // ch (u32 LE)

// Extern function declarations

extern fn arcan_shmif_signalstatus(ctx: ?*arcan.arcan_shmif_cont) c_int;
extern fn arcan_shmif_signal(ctx: ?*arcan.arcan_shmif_cont, mask: c_int) c_uint;

extern fn arcan_tui_get_color(tui: ?*arcan.tui_context, group: c_int, rgb: [*]u8) void;
extern fn arcan_tui_eraseattr_region(
    tui: ?*arcan.tui_context,
    x1: usize, y1: usize, x2: usize, y2: usize,
    force: bool,
    attr: arcan.tui_screen_attr,
) void;
extern fn arcan_tui_defcattr(tui: ?*arcan.tui_context, group: c_int) arcan.tui_screen_attr;

extern fn arcan_timemillis() c_ulonglong;

extern fn fwrite(ptr: *const anyopaque, sz: usize, n: usize, stream: *anyopaque) usize;
extern fn fflush(stream: *anyopaque) c_int;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

// Inline replacements for screen_shim.c

const EAGAIN: c_int = 11;

fn setErrnoEagain() void {
    std.c._errno().* = EAGAIN;
}

fn recordCsv(
    dst: *anyopaque,
    sid: c_int, ax: c_int, ay: c_int,
    cols_val: c_int, rows_val: c_int,
    rv: usize, ts: c_ulonglong,
) void {
    var buf: [128]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d};{d};{d};{d};{d};{d};{d}\n", .{
        sid, ax, ay, cols_val, rows_val, rv, @as(usize, @intCast(ts)),
    }) catch return;
    _ = fwrite(s.ptr, 1, s.len, dst);
}

const ShmifResizeExt = extern struct {
    meta: u32 = 0,
    abuf_sz: usize = 0,
    abuf_cnt: isize,
    samplerate: isize = 0,
    vbuf_cnt: isize,
    rows: usize,
    cols: usize,
    nops: usize = 0,
    op_fm: usize = 0,
};

extern fn arcan_shmif_resize_ext(ctx: *anyopaque, width: c_uint, height: c_uint, req: ShmifResizeExt) bool;

fn resizeExt(
    acon: *arcan.arcan_shmif_cont,
    px_w: usize, px_h: usize,
    vbuf_cnt: isize, abuf_cnt: isize,
    rows_val: usize, cols_val: usize,
) bool {
    return arcan_shmif_resize_ext(
        @ptrCast(acon), @intCast(px_w), @intCast(px_h),
        ShmifResizeExt{
            .vbuf_cnt = vbuf_cnt,
            .abuf_cnt = abuf_cnt,
            .rows = rows_val,
            .cols = cols_val,
        },
    );
}

// Generic byte-offset helpers

fn ctxB(tui: *arcan.tui_context) [*]u8 {
    return @ptrCast(tui);
}
fn ctxBC(tui: *const arcan.tui_context) [*]const u8 {
    return @ptrCast(tui);
}

fn ctxRead(comptime T: type, tui: *const arcan.tui_context, off: usize) T {
    const p: *align(1) const T = @ptrCast(ctxBC(tui) + off);
    return p.*;
}
fn ctxWrite(comptime T: type, tui: *arcan.tui_context, off: usize, v: T) void {
    const p: *align(1) T = @ptrCast(ctxB(tui) + off);
    p.* = v;
}
fn ctxOr32(tui: *arcan.tui_context, off: usize, bits: u32) void {
    const p: *align(1) u32 = @ptrCast(ctxB(tui) + off);
    p.* |= bits;
}

// tui_context field accessors

fn getBase(t: *const arcan.tui_context) ?[*]u8  { return ctxRead(?[*]u8, t, O_BASE); }
fn setBase(t: *arcan.tui_context, v: ?[*]u8) void { ctxWrite(?[*]u8, t, O_BASE, v); }

fn getFront(t: *const arcan.tui_context) ?[*]u8 { return ctxRead(?[*]u8, t, O_FRONT); }
fn setFront(t: *arcan.tui_context, v: ?[*]u8) void { ctxWrite(?[*]u8, t, O_FRONT, v); }

fn getBack(t: *const arcan.tui_context) ?[*]u8  { return ctxRead(?[*]u8, t, O_BACK); }
fn setBack(t: *arcan.tui_context, v: ?[*]u8) void { ctxWrite(?[*]u8, t, O_BACK, v); }

fn getRows(t: *const arcan.tui_context) c_int  { return ctxRead(c_int, t, O_ROWS); }
fn setRows(t: *arcan.tui_context, v: c_int) void { ctxWrite(c_int, t, O_ROWS, v); }

fn getCols(t: *const arcan.tui_context) c_int  { return ctxRead(c_int, t, O_COLS); }
fn setCols(t: *arcan.tui_context, v: c_int) void { ctxWrite(c_int, t, O_COLS, v); }

fn getDirty(t: *const arcan.tui_context) u32   { return ctxRead(u32, t, O_DIRTY); }
fn setDirty(t: *arcan.tui_context, v: u32) void { ctxWrite(u32, t, O_DIRTY, v); }
fn orDirty(t: *arcan.tui_context, bits: u32) void { ctxOr32(t, O_DIRTY, bits); }

fn getCellW(t: *const arcan.tui_context) c_int { return ctxRead(c_int, t, O_CELL_W); }
fn getCellH(t: *const arcan.tui_context) c_int { return ctxRead(c_int, t, O_CELL_H); }
fn setPadW(t: *arcan.tui_context, v: c_int) void { ctxWrite(c_int, t, O_PAD_W, v); }
fn setPadH(t: *arcan.tui_context, v: c_int) void { ctxWrite(c_int, t, O_PAD_H, v); }

fn getCx(t: *const arcan.tui_context) c_int   { return ctxRead(c_int, t, O_CX); }
fn setCx(t: *arcan.tui_context, v: c_int) void { ctxWrite(c_int, t, O_CX, v); }
fn getCy(t: *const arcan.tui_context) c_int   { return ctxRead(c_int, t, O_CY); }
fn setCy(t: *arcan.tui_context, v: c_int) void { ctxWrite(c_int, t, O_CY, v); }

fn getSbofs(t: *const arcan.tui_context) c_long { return ctxRead(c_long, t, O_SBOFS); }

fn getDefocus(t: *const arcan.tui_context) bool { return ctxBC(t)[O_DEFOCUS] != 0; }

fn getCursor(t: *const arcan.tui_context) u32  { return ctxRead(u32, t, O_CURSOR); }

fn getCursorOff(t: *const arcan.tui_context) bool {
    return ctxBC(t)[O_CURSOR_OFF] != 0;
}
fn getCursorHardOff(t: *const arcan.tui_context) bool {
    return ctxBC(t)[O_CURSOR_HARD_OFF] != 0;
}
fn getCursorColorOverride(t: *const arcan.tui_context) bool {
    return ctxBC(t)[O_CURSOR_COLOR_OVERRIDE] != 0;
}
fn getCursorColor(t: *const arcan.tui_context) *const [3]u8 {
    return @ptrCast(ctxBC(t) + O_CURSOR_COLOR);
}
fn getAlpha(t: *const arcan.tui_context) u8 { return ctxBC(t)[O_ALPHA]; }

// colors[idx]: rgb at COLOR_RGB, bg at COLOR_BG within each 7-byte entry
fn getColorRgb(t: *const arcan.tui_context, idx: usize) *const [3]u8 {
    return @ptrCast(ctxBC(t) + O_COLORS + idx * COLOR_SZ + COLOR_RGB);
}
fn getColorBg(t: *const arcan.tui_context, idx: usize) *const [3]u8 {
    return @ptrCast(ctxBC(t) + O_COLORS + idx * COLOR_SZ + COLOR_BG);
}

// last_cursor substruct
fn getLastCursorActive(t: *const arcan.tui_context) bool {
    return ctxBC(t)[O_LAST_CURSOR_ACTIVE] != 0;
}
fn setLastCursorActive(t: *arcan.tui_context, v: bool) void {
    ctxB(t)[O_LAST_CURSOR_ACTIVE] = if (v) 1 else 0;
}
fn getLastCursorRow(t: *const arcan.tui_context) usize {
    return ctxRead(usize, t, O_LAST_CURSOR_ROW);
}
fn setLastCursorRow(t: *arcan.tui_context, v: usize) void {
    ctxWrite(usize, t, O_LAST_CURSOR_ROW, v);
}
fn getLastCursorCol(t: *const arcan.tui_context) usize {
    return ctxRead(usize, t, O_LAST_CURSOR_COL);
}
fn setLastCursorCol(t: *arcan.tui_context, v: usize) void {
    ctxWrite(usize, t, O_LAST_CURSOR_COL, v);
}

// hooks fn ptr types
const hooks_refresh_fn       = ?*const fn (*arcan.tui_context) callconv(.c) void;
const hooks_resize_fn        = ?*const fn (*arcan.tui_context) callconv(.c) void;
const hooks_cursor_lookup_fn = ?*const fn (*arcan.tui_context, *usize, *usize) callconv(.c) void;

fn getHooksRefresh(t: *arcan.tui_context) hooks_refresh_fn {
    return ctxRead(hooks_refresh_fn, t, O_HOOKS_REFRESH);
}
fn getHooksResize(t: *arcan.tui_context) hooks_resize_fn {
    return ctxRead(hooks_resize_fn, t, O_HOOKS_RESIZE);
}
fn getHooksCursorLookup(t: *arcan.tui_context) hooks_cursor_lookup_fn {
    return ctxRead(hooks_cursor_lookup_fn, t, O_HOOKS_CURSOR_LOOKUP);
}

// handlers (tui_cbcfg)
const handlers_resize_fn  = ?*const fn (?*arcan.tui_context, usize, usize, usize, usize, ?*anyopaque) callconv(.c) void;
const handlers_resized_fn = ?*const fn (?*arcan.tui_context, usize, usize, usize, usize, ?*anyopaque) callconv(.c) void;

fn getHandlersTag(t: *arcan.tui_context) ?*anyopaque {
    return ctxRead(?*anyopaque, t, O_HANDLERS_TAG);
}
fn getHandlersResize(t: *arcan.tui_context) handlers_resize_fn {
    return ctxRead(handlers_resize_fn, t, O_HANDLERS_RESIZE);
}
fn getHandlersResized(t: *arcan.tui_context) handlers_resized_fn {
    return ctxRead(handlers_resized_fn, t, O_HANDLERS_RESIZED);
}

// arcan_shmif_cont accessors
fn getAconPtr(t: *arcan.tui_context) *arcan.arcan_shmif_cont {
    return @ptrCast(ctxB(t) + O_ACON);
}
fn getAconAddr(t: *const arcan.tui_context) ?*anyopaque {
    return ctxRead(?*anyopaque, t, O_ACON + SHMIF_OFF_ADDR);
}
fn getAconW(t: *const arcan.tui_context) usize {
    return ctxRead(usize, t, O_ACON + SHMIF_OFF_W);
}
fn getAconH(t: *const arcan.tui_context) usize {
    return ctxRead(usize, t, O_ACON + SHMIF_OFF_H);
}
fn setAconW(t: *arcan.tui_context, v: usize) void {
    ctxWrite(usize, t, O_ACON + SHMIF_OFF_W, v);
}
fn setAconH(t: *arcan.tui_context, v: usize) void {
    ctxWrite(usize, t, O_ACON + SHMIF_OFF_H, v);
}
fn getAconVidb(t: *const arcan.tui_context) ?[*]u8 {
    return ctxRead(?[*]u8, t, O_ACON + SHMIF_OFF_VIDB);
}
fn getAconVbufsize(t: *const arcan.tui_context) usize {
    return ctxRead(usize, t, O_ACON + SHMIF_OFF_VBUFSIZE);
}

// parent / children
fn getParent(t: *const arcan.tui_context) ?*arcan.tui_context {
    return ctxRead(?*arcan.tui_context, t, O_PARENT);
}
// Get parent->children[i]: walk into the parent's children array
fn getParentChild(parent: *arcan.tui_context, i: usize) ?*arcan.tui_context {
    const base: [*]const u8 = @ptrCast(parent);
    const p: *align(1) const ?*arcan.tui_context =
        @ptrCast(base + O_CHILDREN + i * @sizeOf(*anyopaque));
    return p.*;
}

fn getTpackRecdst(t: *const arcan.tui_context) ?*anyopaque {
    return ctxRead(?*anyopaque, t, O_TPACK_RECDST);
}

fn getViewportProxy(t: *const arcan.tui_context) u32 {
    return ctxRead(u32, t, O_VIEWPORT_PROXY);
}

fn getLastConstraintsAnchRow(t: *const arcan.tui_context) c_int {
    return ctxRead(c_int, t, O_LAST_CONSTRAINTS + CONSTRAINTS_OFF_ANCH_ROW);
}
fn getLastConstraintsAnchCol(t: *const arcan.tui_context) c_int {
    return ctxRead(c_int, t, O_LAST_CONSTRAINTS + CONSTRAINTS_OFF_ANCH_COL);
}

// tui_cell buffer helpers

fn cellAt(buf: [*]u8, idx: usize) [*]u8 {
    return buf + idx * TUI_CELL_SZ;
}
fn cellAtC(buf: [*]const u8, idx: usize) [*]const u8 {
    return buf + idx * TUI_CELL_SZ;
}
fn cellAflags(cell: [*]const u8) u16 {
    return readU16LE(cell, CELL_OFF_AFF);
}
fn cellCh(cell: [*]const u8) u32 {
    return readU32LE(cell, CELL_OFF_CH);
}
fn copyCell(dst: [*]u8, src: [*]const u8) void {
    @memcpy(dst[0..TUI_CELL_SZ], src[0..TUI_CELL_SZ]);
}

// tui_attr_equal
// Compare first 10 bytes (the tui_screen_attr portion) of two cells.
// All semantic fields are in bytes 0-8; byte 9 is pad (always zero after calloc).
fn attrEqual(a: [*]const u8, b: [*]const u8) bool {
    return std.mem.eql(u8, a[0..10], b[0..10]);
}

// boolToU8
fn b2u(cond: bool) u8 { return if (cond) 1 else 0; }

// pack_u32 / unpack_u32
fn pack_u32(src: u32, outb: [*]u8) void { writeU32LE(outb, 0, src); }
fn unpack_u32(inb: [*]const u8) u32 { return readU32LE(inb, 0); }

// find_row_ofs
// Returns first column >= start_ofs where front != back, or -1.
fn find_row_ofs(t: *arcan.tui_context, row: usize, start_ofs: usize) isize {
    const cols: usize = @intCast(getCols(t));
    const front = getFront(t) orelse return -1;
    const back  = getBack(t)  orelse return -1;
    const base  = row * cols;

    var pos = start_ofs;
    while (pos < cols) : (pos += 1) {
        const f = cellAtC(front, base + pos);
        const bk = cellAtC(back,  base + pos);
        if (!attrEqual(f, bk) or cellCh(f) != cellCh(bk))
            return @intCast(pos);
    }
    return -1;
}

// resize_cellbuffer
fn resize_cellbuffer(t: *arcan.tui_context) void {
    if (getBase(t)) |old| free(old);
    setBase(t, null);

    const rows: usize = @intCast(getRows(t));
    const cols: usize = @intCast(getCols(t));
    const buf_sz = 2 * rows * cols * TUI_CELL_SZ;
    const rbuf_sz = tui_screen_tpack_sz(t);

    const raw = malloc(buf_sz) orelse {
        // LOG equivalent — write to stderr
        const msg = "couldn't allocate screen buffers\n";
        std.fs.File.stderr().writeAll(msg) catch {};
        return;
    };

    @memset(@as([*]u8, @ptrCast(raw))[0..buf_sz], 0);

    // Fill every cell with COLOR_INDEXED + TUI_COL_BG so any cell that the
    // application never writes still renders with arcan's terminal-bg
    // colour instead of zero-RGB black. Without this, regions outside what
    // the app paints (e.g. hem's job view past content, htop past last
    // process line) show as solid black on top of an otherwise correct
    // dark-grey terminal background.
    {
        const TUI_COL_BG_IDX: u8 = 4;
        const TUI_COL_TEXT_IDX: u8 = 5;
        const total_cells = 2 * rows * cols;
        var ci: usize = 0;
        const cells_base: [*]u8 = @ptrCast(raw);
        while (ci < total_cells) : (ci += 1) {
            const cell = cells_base + ci * TUI_CELL_SZ;
            cell[CELL_OFF_FC] = TUI_COL_TEXT_IDX;
            cell[CELL_OFF_BC] = TUI_COL_BG_IDX;
            @as(*align(1) u16, @ptrCast(cell + CELL_OFF_AFF)).* = TUI_ATTR_COLOR_INDEXED;
        }
    }

    // Root-cause fix for bug #30: shrinking the font (cell_w/cell_h go
    // down) grows rows*cols without resizing the underlying shmif page,
    // so tpack-format rbuf_sz can exceed the actual vidp allocation
    // (`vbuf_sz`). The old code memset rbuf_sz bytes unconditionally →
    // SIGSEGV whenever rbuf_sz > vbuf_sz. Clamp to the real allocation
    // and log the clamp so we can find the code path that should've
    // called arcan_shmif_resize_ext first (tui_fontmgmt_fonthint is a
    // known offender — it skips the resize that tui_fontmgmt_invalidate
    // performs for DPI changes).
    if (getAconVidb(t)) |vidb| {
        const vbuf_sz = getAconVbufsize(t);
        const memset_sz = if (rbuf_sz <= vbuf_sz) rbuf_sz else vbuf_sz;
        if (rbuf_sz > vbuf_sz) {
            const sc_fopen = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
            const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
            const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
            if (sc_fopen("/tmp/arcan_shmif_trace.log", "a")) |f| {
                _ = sc_fprintf(
                    f,
                    "resize_cellbuffer: rbuf_sz=%zu > vbuf_sz=%zu (rows=%zu cols=%zu cell=%dx%d) — clamped\n",
                    rbuf_sz,
                    vbuf_sz,
                    rows,
                    cols,
                    @as(c_int, getCellW(t)),
                    @as(c_int, getCellH(t)),
                );
                _ = sc_fclose(f);
            }
        }
        @memset(vidb[0..memset_sz], 0);
    }

    setBase(t, @ptrCast(raw));
    setFront(t, @ptrCast(raw));
    const back_ptr: [*]u8 = @as([*]u8, @ptrCast(raw)) + rows * cols * TUI_CELL_SZ;
    setBack(t, back_ptr);
    orDirty(t, DIRTY_FULL);
}

// cell_to_rcell
// Serialize one tui_cell into 12-byte raster wire format. Returns 12.
fn cell_to_rcell(t: *arcan.tui_context, cell: [*]const u8, out: [*]u8, has_cursor: u8) usize {
    const aflags = cellAflags(cell);

    var fc: [*]const u8 = cell + CELL_OFF_FC;
    var bc: [*]const u8 = cell + CELL_OFF_BC;
    var fc_s: [3]u8 = undefined;
    var bc_s: [3]u8 = undefined;

    if ((aflags & TUI_ATTR_COLOR_INDEXED) != 0) {
        fc_s = getColorRgb(t, fc[0] % TUI_COL_LIMIT).*;
        bc_s = getColorBg(t,  bc[0] % TUI_COL_LIMIT).*;
        fc = &fc_s;
        bc = &bc_s;
    }

    if ((aflags & TUI_ATTR_INVERSE) != 0) {
        const intens: f32 =
            (0.299 * @as(f32, @floatFromInt(fc[0])) +
             0.587 * @as(f32, @floatFromInt(fc[1])) +
             0.114 * @as(f32, @floatFromInt(fc[2]))) / 255.0;
        if (intens < 0.5) {
            out[0] = 0xff; out[1] = 0xff; out[2] = 0xff;
        } else {
            out[0] = 0x00; out[1] = 0x00; out[2] = 0x00;
        }
        out[3] = fc[0]; out[4] = fc[1]; out[5] = fc[2];
    } else {
        out[0] = fc[0]; out[1] = fc[1]; out[2] = fc[2];
        out[3] = bc[0]; out[4] = bc[1]; out[5] = bc[2];
    }

    out[6] = (
        CATTR_BOLD          * b2u((aflags & TUI_ATTR_BOLD)          != 0) |
        CATTR_UNDERLINE     * b2u((aflags & TUI_ATTR_UNDERLINE)     != 0) |
        CATTR_UNDERLINE_ALT * b2u((aflags & TUI_ATTR_UNDERLINE_ALT) != 0) |
        CATTR_ITALIC        * b2u((aflags & TUI_ATTR_ITALIC)        != 0) |
        CATTR_STRIKETHROUGH * b2u((aflags & TUI_ATTR_STRIKETHROUGH) != 0) |
        CATTR_SHAPEBREAK    * b2u((aflags & TUI_ATTR_SHAPE_BREAK)   != 0) |
        CATTR_CURSOR        * has_cursor
    );
    out[7] = (
        CEATTR_GLYPH_IND  * b2u((aflags & TUI_ATTR_GLYPH_INDEXED)  != 0) |
        CEATTR_AGLYPH_IND * b2u((aflags & TUI_ATTR_AGLYPH_INDEXED) != 0) |
        CEATTR_BORDER_R   * b2u((aflags & TUI_ATTR_BORDER_RIGHT)   != 0) |
        CEATTR_BORDER_D   * b2u((aflags & TUI_ATTR_BORDER_DOWN)    != 0) |
        CEATTR_BORDER_L   * b2u((aflags & TUI_ATTR_BORDER_LEFT)    != 0) |
        CEATTR_BORDER_T   * b2u((aflags & TUI_ATTR_BORDER_TOP)     != 0)
    );

    pack_u32(cellCh(cell), out + 8);
    return raster_cell_sz;
}

// rcell_to_cell
// Deserialize a 12-byte raster cell into a tui_cell buffer. Tracks cursor.
fn rcell_to_cell(
    C: *arcan.tui_context,
    x: usize, y: usize,
    src: [*]const u8,
    dst: [*]u8,
    got_cursor: *bool,
) void {
    @memset(dst[0..TUI_CELL_SZ], 0);

    // fc[3], bc[3]
    dst[CELL_OFF_FC + 0] = src[0];
    dst[CELL_OFF_FC + 1] = src[1];
    dst[CELL_OFF_FC + 2] = src[2];
    dst[CELL_OFF_BC + 0] = src[3];
    dst[CELL_OFF_BC + 1] = src[4];
    dst[CELL_OFF_BC + 2] = src[5];

    // aflags — strip cursor bit if found
    var aflags: u16 = @as(u16, src[6]) | (@as(u16, src[7]) << 8);
    if ((aflags & @as(u16, CATTR_CURSOR)) != 0) {
        aflags &= ~@as(u16, CATTR_CURSOR);  // strip cursor attr
        if (!got_cursor.*) {
            setCx(C, @intCast(x));
            setCy(C, @intCast(y));
            got_cursor.* = true;
        }
    }
    writeU16LE(dst, CELL_OFF_AFF, aflags);

    // codepoint
    writeU32LE(dst, CELL_OFF_CH, unpack_u32(src + 8));
}

// tui_screen_tpack_sz

export fn tui_screen_tpack_sz(tui: ?*arcan.tui_context) usize {
    if (is_freestanding) return 0;
    const t = tui orelse return 0;
    const rows: usize = @intCast(getRows(t));
    const cols: usize = @intCast(getCols(t));
    return HDR_SZ +
        ((rows * cols + 2) * raster_cell_sz) +
        ((rows + 2) * raster_line_sz);
}

// tui_screen_tpack

export fn tui_screen_tpack(
    tui: ?*arcan.tui_context,
    opts: TpackGenOpts,
    rbuf: ?[*]u8,
    rbuf_sz: usize,
) usize {
    if (is_freestanding) return 0;
    _ = rbuf_sz;
    const t   = tui  orelse return 0;
    const out = rbuf orelse return 0;

    if (!opts.full and getDirty(t) == DIRTY_NONE)
        return 0;

    // Work area for the 16-byte header (written at end)
    var hdr = std.mem.zeroes([HDR_SZ]u8);
    var bgc: [3]u8 = .{ 0, 0, 0 };
    arcan_tui_get_color(tui, TUI_COL_BG, &bgc);
    hdr[HDR_OFF_BGC + 0] = bgc[0];
    hdr[HDR_OFF_BGC + 1] = bgc[1];
    hdr[HDR_OFF_BGC + 2] = bgc[2];
    hdr[HDR_OFF_BGC + 3] = getAlpha(t);

    // Output offset starts after header + 3-byte CURSOR_EXTHDRv1 colour extension
    var outsz: usize = HDR_SZ + 3;

    var apts = opts;  // mutable copy
    if (opts.back) { apts.full = true; apts.synch = false; }

    const rows: usize = @intCast(getRows(t));
    const cols: usize = @intCast(getCols(t));
    const dirty = getDirty(t);

    var hdr_lines: u16 = 0;
    var hdr_cells: u16 = 0;
    var hdr_flags: u16 = 0;
    var hdr_cursor_state: u8 = 0;

    // I-frame
    if (apts.full or (dirty & DIRTY_FULL) != 0) {
        var fp = (if (apts.back) getBack(t) else getFront(t)) orelse return 0;
        var bk = getBack(t) orelse return 0;

        setLastCursorActive(t, false);

        hdr_flags |= RPACK_IFRAME;
        // Cap to u16 range — if cell dimensions are too small (server sent wrong
        // DISPLAYHINT), truncate rather than crash. The terminal will be garbled
        // but arcan stays alive for the user to fix font settings.
        const total = rows * cols;
        if (total > 65535) {
            hdr_lines = @intCast(@min(rows, 65535));
            hdr_cells = 65535;
            // Only pack what fits
            const max_rows = @min(rows, 65535 / @max(cols, 1));
            hdr_lines = @intCast(max_rows);
            hdr_cells = @intCast(max_rows * cols);
        } else {
            hdr_lines = @intCast(rows);
            hdr_cells = @intCast(total);
        }

        for (0..rows) |row| {
            // Write line header: start_line=row, ncells=cols, offset=0
            writeU16LE(out, outsz + LINE_OFF_START_LINE, @intCast(row));
            writeU16LE(out, outsz + LINE_OFF_NCELLS,     @intCast(cols));
            writeU16LE(out, outsz + LINE_OFF_OFFSET,     0);
            out[outsz + 6] = 0; out[outsz + 7] = 0; out[outsz + 8] = 0;
            outsz += LINE_SZ;

            for (0..cols) |_| {
                if (apts.synch) copyCell(bk, fp);
                outsz += cell_to_rcell(t, fp, out + outsz, 0);
                bk += TUI_CELL_SZ;
                fp += TUI_CELL_SZ;
            }
        }

    // D-frame
    } else if ((dirty & DIRTY_PARTIAL) != 0) {
        const fp = getFront(t) orelse return 0;
        const bk = getBack(t)  orelse return 0;

        for (0..rows) |row| {
            // Find first dirty column in this row
            const first_ofs = find_row_ofs(t, row, 0);
            if (first_ofs == -1) continue;

            const row_base = row * cols;

            if (getLastCursorActive(t) and
                getLastCursorRow(t) == row and
                getLastCursorCol(t) == @as(usize, @intCast(first_ofs)))
            {
                setLastCursorActive(t, false);
            }

            // Reserve space for line header; fill after iterating cells
            const line_dst = outsz;
            outsz += LINE_SZ;

            var line_ncells: u16 = 0;
            var ofs: isize = first_ofs;

            while (ofs != -1 and ofs < @as(isize, @intCast(cols))) {
                const col: usize = @intCast(ofs);
                const cell = cellAt(fp, row_base + col);

                if (apts.synch)
                    copyCell(cellAt(bk, row_base + col), cell);

                line_ncells +|= 1;   // saturate: u16 caps at 65535
                outsz += cell_to_rcell(t, cell, out + outsz, 0);

                const last_ofs = ofs;
                ofs = find_row_ofs(t, row, col + 1);
                if (ofs == -1) break;

                // Skip (gap fill) between changed columns
                var skip = last_ofs + 1;
                while (skip != ofs) : (skip += 1) {
                    @memset(out[outsz..][0..raster_cell_sz], 0);
                    out[outsz + 6] = 128;
                    out[outsz + 7] = 0;
                    outsz += raster_cell_sz;
                    line_ncells +|= 1;
                }
            }

            // Write line header back into its reserved position
            const first_col_u: u16 = if (first_ofs >= 0) @intCast(first_ofs) else 0;
            writeU16LE(out, line_dst + LINE_OFF_START_LINE, @intCast(row));
            writeU16LE(out, line_dst + LINE_OFF_NCELLS,     line_ncells);
            writeU16LE(out, line_dst + LINE_OFF_OFFSET,     first_col_u);
            out[line_dst + 6] = 0;
            out[line_dst + 7] = 0;
            out[line_dst + 8] = 0;

            // Saturating add — wire format caps at u16 (65535).  Beyond
            // that the receiver gets a possibly-truncated frame but the
            // compositor stays alive (raw `+=` would panic in Debug).
            hdr_cells +|= line_ncells;
            hdr_lines +|= 1;
        }

        hdr_flags |= RPACK_DFRAME;
    }

    // Cursor update
    if ((dirty & DIRTY_CURSOR) != 0) {
        if (dirty == DIRTY_CURSOR)
            hdr_flags |= RPACK_DFRAME;

        const cols_sz: usize = @intCast(getCols(t));
        const last_active = getLastCursorActive(t);
        const last_row    = getLastCursorRow(t);
        const last_col    = getLastCursorCol(t);
        const cx: usize   = @intCast(getCx(t));
        const cy: usize   = @intCast(getCy(t));

        // 1. Restore old cursor position (emit without cursor attr)
        if (last_active and (last_col != cx or last_row != cy)) {
            hdr_lines +|= 1;
            hdr_cells +|= 1;

            writeU16LE(out, outsz + LINE_OFF_START_LINE, @intCast(last_row));
            writeU16LE(out, outsz + LINE_OFF_NCELLS,     1);
            writeU16LE(out, outsz + LINE_OFF_OFFSET,     @intCast(last_col));
            out[outsz + 6] = 0; out[outsz + 7] = 0; out[outsz + 8] = 0;
            outsz += LINE_SZ;

            const fp = getFront(t) orelse return 0;
            outsz += cell_to_rcell(t, cellAt(fp, last_row * cols_sz + last_col), out + outsz, 0);
        }

        // 2. Send new cursor
        hdr_lines +|= 1;
        hdr_cells +|= 1;

        var new_x = cx;
        var new_y = cy;
        if (getHooksCursorLookup(t)) |fn_| fn_(t, &new_x, &new_y);

        setLastCursorRow(t, new_y);
        setLastCursorCol(t, new_x);

        writeU16LE(out, outsz + LINE_OFF_START_LINE, @intCast(new_y));
        writeU16LE(out, outsz + LINE_OFF_NCELLS,     1);
        writeU16LE(out, outsz + LINE_OFF_OFFSET,     @intCast(new_x));
        out[outsz + 6] = 0; out[outsz + 7] = 0; out[outsz + 8] = 0;
        outsz += LINE_SZ;

        const fp = getFront(t) orelse return 0;
        outsz += cell_to_rcell(t, cellAt(fp, new_y * cols_sz + new_x), out + outsz, 1);

        // Cursor visibility
        if (getCursorOff(t) or getCursorHardOff(t) or getSbofs(t) != 0) {
            hdr_cursor_state = CURSOR_NONE;
        } else {
            hdr_cursor_state = if (getDefocus(t)) CURSOR_INACTIVE else CURSOR_ACTIVE;
        }

        setLastCursorActive(t, true);
    }

    // Finalize header
    const data_sz: u32 = @intCast(
        @as(usize, hdr_lines) * raster_line_sz +
        @as(usize, hdr_cells) * raster_cell_sz +
        raster_hdr_sz + 3
    );
    writeU32LE(&hdr, HDR_OFF_DATA_SZ, data_sz);
    writeU16LE(&hdr, HDR_OFF_LINES,   hdr_lines);
    writeU16LE(&hdr, HDR_OFF_CELLS,   hdr_cells);
    writeU16LE(&hdr, HDR_OFF_FLAGS,   hdr_flags);

    hdr_cursor_state |= CURSOR_EXTHDRv1;
    const cursor_shape = getCursor(t);
    if (cursor_shape == 0) {
        hdr_cursor_state |= CURSOR_BLOCK;
    } else {
        hdr_cursor_state |= @as(u8, @truncate(cursor_shape)) &
            (CURSOR_BLOCK | CURSOR_BAR | CURSOR_UNDER | CURSOR_HOLLOW);
    }
    hdr[HDR_OFF_CURSOR_STATE] = hdr_cursor_state;

    // Write header at buffer start
    @memcpy(out[0..HDR_SZ], &hdr);

    // Write cursor color extension (3 bytes immediately after header)
    if (getCursorColorOverride(t)) {
        const cc = getCursorColor(t);
        out[HDR_SZ + 0] = cc[0];
        out[HDR_SZ + 1] = cc[1];
        out[HDR_SZ + 2] = cc[2];
    } else {
        const cc = getColorRgb(t, TUI_COL_CURSOR);
        out[HDR_SZ + 0] = cc[0];
        out[HDR_SZ + 1] = cc[1];
        out[HDR_SZ + 2] = cc[2];
    }

    return outsz;
}

// tui_screen_resized

export fn tui_screen_resized(tui: ?*arcan.tui_context) void {
    if (is_freestanding) return;
    const t = tui orelse return;

    const acon_w: c_int = @intCast(getAconW(t));
    const acon_h: c_int = @intCast(getAconH(t));
    const cell_w = getCellW(t);
    const cell_h = getCellH(t);

    const cols: c_int = if (cell_w > 0) @divTrunc(acon_w, cell_w) else 0;
    const rows: c_int = if (cell_h > 0) @divTrunc(acon_h, cell_h) else 0;

    setPadW(t, acon_w - cols * cell_w);
    setPadH(t, acon_h - rows * cell_h);

    if (cols != getCols(t) or rows != getRows(t)) {
        // LOG("update screensize (%d * %d), (%d * %d)\n", ...) — omitted (varargs)

        if (getHandlersResize(t)) |fn_|
            fn_(tui, @intCast(acon_w), @intCast(acon_h),
                     @intCast(cols),   @intCast(rows),
                     getHandlersTag(t));

        setCols(t, cols);
        setRows(t, rows);

        if (getViewportProxy(t) == 0)
            resize_cellbuffer(t);

        if (getHooksResize(t)) |fn_| fn_(t);

        if (getHandlersResized(t)) |fn_|
            fn_(tui, @intCast(acon_w), @intCast(acon_h),
                     @intCast(cols),   @intCast(rows),
                     getHandlersTag(t));
    }

    orDirty(t, DIRTY_FULL);
}

// tui_tpack_unpack

export fn tui_tpack_unpack(
    C: ?*arcan.tui_context,
    buf_arg: ?[*]u8,
    buf_sz_arg: usize,
    x: usize,
    y: usize,
    x2_arg: usize,
    y2_arg: usize,
) c_int {
    if (is_freestanding) return -1;
    const tui   = C       orelse return -1;
    var buf     = buf_arg orelse return -1;
    var buf_sz  = buf_sz_arg;

    if (buf_sz < HDR_SZ) return -1;

    // Parse header
    var hdr: [HDR_SZ]u8 = undefined;
    @memcpy(&hdr, buf[0..HDR_SZ]);
    const data_sz   = readU32LE(&hdr, HDR_OFF_DATA_SZ);
    const hdr_lines = readU16LE(&hdr, HDR_OFF_LINES);
    const hdr_cells = readU16LE(&hdr, HDR_OFF_CELLS);
    const hdr_flags = readU16LE(&hdr, HDR_OFF_FLAGS);
    const cursor_st = hdr[HDR_OFF_CURSOR_STATE];

    // Validate
    var hdr_ver_sz: usize =
        @as(usize, hdr_lines) * raster_line_sz +
        @as(usize, hdr_cells) * raster_cell_sz +
        raster_hdr_sz;
    if ((cursor_st & CURSOR_EXTHDRv1) != 0) hdr_ver_sz += 3;

    if (data_sz > buf_sz or data_sz != hdr_ver_sz) return -1;

    buf    += HDR_SZ;
    buf_sz -= HDR_SZ;

    if ((cursor_st & CURSOR_EXTHDRv1) != 0) {
        buf    += 3;
        buf_sz -= 3;
    }

    var got_cursor = false;
    var x2 = x2_arg;
    var y2 = y2_arg;

    // Non-delta frame: optionally resize context and erase region
    if ((hdr_flags & RPACK_DFRAME) == 0) {
        const ncols: usize = if (hdr_lines > 0) hdr_cells / hdr_lines else 0;

        if ((x2 == 0 or y2 == 0) and
            (@as(usize, @intCast(getRows(tui))) != hdr_lines or
             @as(usize, @intCast(getCols(tui))) != ncols))
        {
            const px_w = @as(usize, @intCast(getCellW(tui))) * ncols;
            const px_h = @as(usize, @intCast(getCellH(tui))) * hdr_lines;
            x2 = ncols;
            y2 = hdr_lines;

            var resized = false;

            if (getAconAddr(tui) == null) {
                setAconW(tui, px_w);
                setAconH(tui, px_h);
                tui_screen_resized(C);
                resized = true;
            } else {
                resized = resizeExt(
                    getAconPtr(tui), px_w, px_h,
                    -1, -1,
                    @intCast(hdr_lines), ncols,
                );
            }

            if (resized) tui_screen_resized(C);
        }

        const empty = arcan_tui_defcattr(C, TUI_COL_BG);
        arcan_tui_eraseattr_region(C, x, y, x2, y2, false, empty);
    }

    // Clamp clip region
    const ctx_cols: usize = @intCast(getCols(tui));
    const ctx_rows: usize = @intCast(getRows(tui));
    if (x2 == 0 or x2 > ctx_cols) x2 = ctx_cols;
    if (y2 == 0 or y2 > ctx_rows) y2 = ctx_rows;

    const front = getFront(tui) orelse return -1;

    for (0..hdr_lines) |_| {
        if (buf_sz < LINE_SZ) return -1;

        var line: [LINE_SZ]u8 = undefined;
        @memcpy(&line, buf[0..LINE_SZ]);
        buf    += LINE_SZ;
        buf_sz -= LINE_SZ;

        const start_line: usize  = readU16LE(&line, LINE_OFF_START_LINE);
        const ncells_line: usize = readU16LE(&line, LINE_OFF_NCELLS);
        const line_offset: usize = readU16LE(&line, LINE_OFF_OFFSET);

        var col  = line_offset;
        var left = ncells_line;
        while (left > 0 and buf_sz >= raster_cell_sz) {
            left -= 1;

            var cell_bytes = std.mem.zeroes([TUI_CELL_SZ]u8);
            rcell_to_cell(tui, col, start_line, buf, &cell_bytes, &got_cursor);
            buf    += raster_cell_sz;
            buf_sz -= raster_cell_sz;

            if (start_line < y2 and col < x2) {
                const idx = start_line * ctx_cols + col;
                copyCell(cellAt(front, idx), &cell_bytes);
            }
            col += 1;
        }
    }

    setDirty(tui, DIRTY_FULL);
    return 1;
}

// Diagnostic: track first render
var diag_refresh_count: u32 = 0;

// tui_screen_refresh

export fn tui_screen_refresh(tui: ?*arcan.tui_context) c_int {
    if (is_freestanding) return -1;
    const t = tui orelse return -1;

    if (getHooksRefresh(t)) |fn_| fn_(t);

    // Diagnostic: count EAGAIN bails vs successful refreshes to understand
    // whether the caller's main loop is busy-spinning on a dirty-but-blocked
    // state. Rate-limited to once every 500ms to avoid flooding.
    const Diag = struct {
        var eagain_skips: u64 = 0;
        var delivered: u64 = 0;
        var last_report_ms: c_ulonglong = 0;
    };

    if (arcan_shmif_signalstatus(getAconPtr(t)) != 0) {
        Diag.eagain_skips += 1;
        const now_ms = arcan_timemillis();
        if (now_ms - Diag.last_report_ms > 500) {
            Diag.last_report_ms = now_ms;
            var dbuf: [192]u8 = undefined;
            const msg = std.fmt.bufPrint(&dbuf,
                "[DIAG screen_refresh] eagain_skips={d} delivered={d} dirty={d} (SIGVID still outstanding, dirty stays set)\n",
                .{ Diag.eagain_skips, Diag.delivered, getDirty(t) })
                    catch "[DIAG screen_refresh] bufPrint failed\n";
            std.fs.File.stderr().writeAll(msg) catch {};
        }
        setErrnoEagain();  // errno = EAGAIN
        return -1;
    }
    Diag.delivered += 1;

    const vidb     = getAconVidb(t)     orelse return 0;
    const vbufsize = getAconVbufsize(t);

    const rv = tui_screen_tpack(
        tui,
        TpackGenOpts{ .full = false, .synch = true, .back = false },
        vidb,
        vbufsize,
    );
    setDirty(t, DIRTY_NONE);

    if (rv == 0) return 0;

    // DIAGNOSTIC: log first render stats
    if (diag_refresh_count < 3) {
        diag_refresh_count += 1;
        var dbuf: [256]u8 = undefined;
        // Count non-zero bytes in the vidb tpack buffer
        var nonzero: usize = 0;
        for (0..@min(rv, vbufsize)) |bi| {
            if (vidb[bi] != 0) nonzero += 1;
        }
        const w = getAconW(t);
        const h = getAconH(t);
        const msg = std.fmt.bufPrint(&dbuf, "[DIAG tui_screen_refresh #{d}] tpack_bytes={d}, nonzero_bytes={d}, vidb=0x{x}, w={d}, h={d}, vbufsize={d}\n", .{
            diag_refresh_count, rv, nonzero, @intFromPtr(vidb), w, h, vbufsize,
        }) catch "DIAG: bufPrint failed\n";
        std.fs.File.stderr().writeAll(msg) catch {};
    }

    // Optional tpack recording
    if (getTpackRecdst(t)) |dst| {
        var sid: c_int      = 0;
        var anchor_x: c_int = 0;
        var anchor_y: c_int = 0;

        if (getParent(t)) |parent| {
            sid = -1;
            for (0..256) |i| {
                if (getParentChild(parent, i)) |child| {
                    if (child == t) {
                        sid      = @intCast(i);
                        anchor_x = getLastConstraintsAnchCol(t);
                        anchor_y = getLastConstraintsAnchRow(t);
                        break;
                    }
                }
            }
        }

        if (sid != -1) {
            recordCsv(
                dst, sid, anchor_x, anchor_y,
                getCols(t), getRows(t),
                rv, arcan_timemillis(),
            );
            _ = fwrite(vidb, rv, 1, dst);
        }
    }

    _ = arcan_shmif_signal(getAconPtr(t), SHMIF_SIGVID | SHMIF_SIGBLK_NONE);

    if (getTpackRecdst(t)) |dst|
        _ = fflush(dst);

    return 0;
}
