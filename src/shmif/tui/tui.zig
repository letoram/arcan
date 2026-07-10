// Pure Zig port of tui/tui.c — main arcan_tui entrypoints.
//
// Maps/translates to internal functions (screen.c, dispatch.c, clipboard.c,
// input.c, fontmgmt.c). All exported symbols match C names exactly.
//
// Field access uses verified byte offsets (gcc offsetof, aarch64-linux).
// See compute_offsets.c for how the offsets were derived.

const std = @import("std");
const arcan = @import("arcan");

// Opaque type re-exports
const tui_context = arcan.tui_context;
const arcan_event = arcan.arcan_event;
const arcan_extevent = arcan.arcan_extevent;
const tui_screen_attr = arcan.tui_screen_attr;
const tui_cell = arcan.tui_cell;
const tui_constraints = arcan.tui_constraints;
const tui_cbcfg = arcan.tui_cbcfg;
const arcan_shmif_cont = arcan.arcan_shmif_cont;

// Verified byte offsets (aarch64-linux, gcc offsetof)
const OFF_SCREEN: usize = 0;
const OFF_FRONT: usize = 32;
const OFF_BACK: usize = 40;
const OFF_DEFATTR: usize = 48;
const OFF_FSTAMP: usize = 58;
const OFF_FLAGS: usize = 80;
const OFF_DIRTY: usize = 128;
const OFF_INACT_TIMER: usize = 88;
const OFF_MOUSE_FORWARD: usize = 208;
const OFF_ROWS: usize = 228;
const OFF_COLS: usize = 232;
const OFF_SBSTAT: usize = 248;
const OFF_SBSTAT_HINT: usize = 264; // sbstat.hint is an arcan_event (128 bytes) at this offset
const OFF_SBSTAT_DIRTY: usize = 392;
const OFF_CELL_W: usize = 404;
const OFF_CELL_H: usize = 408;
const OFF_CX: usize = 420;
const OFF_CY: usize = 424;
const OFF_COLORS: usize = 432; // struct color[TUI_COL_LIMIT], each 7 bytes
const OFF_CURSOR_HARD_OFF: usize = 685;
const OFF_CURSOR: usize = 728;
const OFF_CURSOR_COLOR_OVERRIDE: usize = 732;
const OFF_CURSOR_COLOR: usize = 733;
const OFF_ACON: usize = 2808;
const OFF_CLIP_IN: usize = 3000;
const OFF_LAST_IDENT: usize = 3392;
const OFF_LAST_STATE_SZ: usize = 3520;
const OFF_VIEWPORT_PROXY: usize = 3388;
const OFF_LAST_CONSTRAINTS: usize = 3648;
const OFF_PENDING_WND: usize = 3696;
const OFF_HOOKS_CURSOR_UPDATE: usize = 3824;
const OFF_HOOKS_RESET: usize = 3840;
const OFF_HANDLERS: usize = 3880;

// arcan_shmif_cont sub-field offsets
const SHMIF_OFF_ADDR: usize = 0;
const SHMIF_OFF_VIDP: usize = 8;
const SHMIF_OFF_W: usize = 80;
const SHMIF_OFF_H: usize = 88;
const SHMIF_OFF_EPIPE: usize = 36;
const SHMIF_OFF_SEGMENT_TOKEN: usize = 176;

// struct color field offsets (within a single color entry)
const COLOR_OFF_RGB: usize = 0;
const COLOR_OFF_BG: usize = 3;
const COLOR_OFF_BGSET: usize = 6;
const COLOR_SIZEOF: usize = 7;

// tui_screen_attr size (10 bytes: 3 fc + 3 bc + 2 aflags + 1 custom_id + 1 pad)
const SIZEOF_ATTR: usize = 10;
const SIZEOF_CELL: usize = 28;
const SIZEOF_ARCAN_EVENT: usize = 128;
const SIZEOF_SHMIF_CONT: usize = 192;
const SIZEOF_CBCFG: usize = 224;
const SIZEOF_CONSTRAINTS: usize = 32;

// dirty state bitmask values (from tui_int.h)
const DIRTY_CURSOR: u32 = 1;
const DIRTY_PARTIAL: u32 = 2;
const DIRTY_FULL: u32 = 4;

// tui_screen_attr aflags (from arcan_tuisym.h)
const TUI_ATTR_PROTECT: u16 = 32;
const TUI_ATTR_COLOR_INDEXED: u16 = 512;
const TUI_ATTR_BORDER_RIGHT: u16 = 4096;
const TUI_ATTR_BORDER_DOWN: u16 = 8192;
const TUI_ATTR_BORDER_LEFT: u16 = 16384;
const TUI_ATTR_BORDER_TOP: u16 = 32768;

// tui_context_flags (from arcan_tuisym.h)
const TUI_INSERT_MODE: u32 = 1;
const TUI_AUTO_WRAP: u32 = 2;
const TUI_REL_ORIGIN: u32 = 4;
const TUI_INVERSE: u32 = 8;
const TUI_HIDE_CURSOR: u32 = 16;
const TUI_FIXED_POS: u32 = 32;
const TUI_ALTERNATE: u32 = 64;
const TUI_MOUSE: u32 = 128;
const TUI_MOUSE_FULL: u32 = 256;

// tui_color_group (from arcan_tuisym.h)
const TUI_COL_PRIMARY: c_int = 2;
const TUI_COL_SECONDARY: c_int = 3;
const TUI_COL_BG: c_int = 4;
const TUI_COL_TEXT: c_int = 5;
const TUI_COL_CURSOR: c_int = 6;
const TUI_COL_ALTCURSOR: c_int = 7;
const TUI_COL_HIGHLIGHT: c_int = 8;
const TUI_COL_LABEL: c_int = 9;
const TUI_COL_WARNING: c_int = 10;
const TUI_COL_ERROR: c_int = 11;
const TUI_COL_ALERT: c_int = 12;
const TUI_COL_REFERENCE: c_int = 13;
const TUI_COL_INACTIVE: c_int = 14;
const TUI_COL_UI: c_int = 15;
const TUI_COL_TBASE: c_int = 16;
const TUI_COL_LIMIT: c_int = 36;

// tui_border_flags
const TUI_BORDER_USEATTR: c_int = 0;
const TUI_BORDER_APPEND: c_int = 1;

// tui_message_slots
const TUI_MESSAGE_PROMPT: c_int = 0;
const TUI_MESSAGE_ALERT: c_int = 1;
const TUI_MESSAGE_NOTIFICATION: c_int = 2;
const TUI_MESSAGE_FAILURE: c_int = 3;
const TUI_MESSAGE_LOCAL: c_int = 4;
const TUI_MESSAGE_GENERIC: c_int = 5;

// tui_progress_type
const TUI_PROGRESS_INTERNAL: c_int = 0;
const TUI_PROGRESS_BCHUNK_IN: c_int = 1;
const TUI_PROGRESS_BCHUNK_OUT: c_int = 2;
const TUI_PROGRESS_STATE_IN: c_int = 3;
const TUI_PROGRESS_STATE_OUT: c_int = 4;

// tui_subwnd_type
const TUI_WND_TUI: u32 = 23;
const TUI_WND_POPUP: u32 = 16;
const TUI_WND_DEBUG: u32 = 255;
const TUI_WND_HANDOVER: u32 = 26;
const TUI_WND_ACCESSIBILITY: u32 = 19;

// tui_process_errc
const TUI_ERRC_OK: c_int = 0;
const TUI_ERRC_BAD_ARG: c_int = -1;
const TUI_ERRC_BAD_FD: c_int = -2;
const TUI_ERRC_BAD_CTX: c_int = -3;

// SEGID values
const SEGID_TUI: c_int = 24;
const SEGID_POPUP: c_int = 16;
const SEGID_DEBUG: c_int = 255;
const SEGID_HANDOVER: c_int = 28;
const SEGID_ACCESSIBILITY: c_int = 20;

// External event kinds
const EVENT_EXTERNAL_MESSAGE: c_int = 0;
const EVENT_EXTERNAL_IDENT: c_int = 2;
const EVENT_EXTERNAL_FAILURE: c_int = 3;
const EVENT_EXTERNAL_SEGREQ: c_int = 10;
const EVENT_EXTERNAL_VIEWPORT: c_int = 13;
const EVENT_EXTERNAL_CONTENT: c_int = 14;
const EVENT_EXTERNAL_LABELHINT: c_int = 15;
const EVENT_EXTERNAL_ALERT: c_int = 17;
const EVENT_EXTERNAL_BCHUNKSTATE: c_int = 19;
const EVENT_EXTERNAL_STATESIZE: c_int = 8;
const EVENT_EXTERNAL_STREAMSTATUS: c_int = 7;

// IO event
const EVENT_IO_BUTTON: c_int = 2;
const EVENT_IDEVKIND_KEYBOARD: c_int = 1;
const EVENT_IDATATYPE_TRANSLATED: c_int = 4;

// Event categories
const EVENT_EXTERNAL: u8 = 64;
const EVENT_TARGET: u8 = 16;
const EVENT_IO: u8 = 2;

// POLLIN etc. from poll.h
const POLLIN: i16 = 0x001;
const POLLERR: i16 = 0x008;
const POLLHUP: i16 = 0x010;
const POLLNVAL: i16 = 0x020;

// External function declarations

// Internal TUI functions (from other TUI .c / .zig files)
extern fn tui_clipboard_push(tui: ?*tui_context, sel: [*c]const u8, len: usize) callconv(.c) bool;
extern fn tui_clipboard_check(tui: ?*tui_context) callconv(.c) void;
extern fn tui_event_poll(tui: ?*tui_context) callconv(.c) void;
extern fn tui_screen_refresh(tui: ?*tui_context) callconv(.c) c_int;
extern fn tui_screen_resized(tui: ?*tui_context) callconv(.c) void;
extern fn tui_screen_tpack_sz(tui: ?*tui_context) callconv(.c) usize;
extern fn tui_screen_tpack(tui: ?*tui_context, opts: tpack_gen_opts, rbuf: [*c]u8, rbuf_sz: usize) callconv(.c) usize;
extern fn tui_tpack_unpack(tui: ?*tui_context, buf: [*c]u8, buf_sz: usize, x: usize, y: usize, w: usize, h: usize) callconv(.c) c_int;
extern fn tui_expose_labels(tui: ?*tui_context) callconv(.c) void;
extern fn tui_input_event(tui: ?*tui_context, ioev: ?*anyopaque, label: [*c]const u8) callconv(.c) void;
extern fn tui_fontmgmt_hasglyph(tui: ?*tui_context, cp: u32) callconv(.c) bool;

// shmif functions
extern fn arcan_shmif_enqueue(ctx: ?*arcan_shmif_cont, ev: *const arcan_event) callconv(.c) c_int;
extern fn arcan_shmif_signalstatus(ctx: ?*arcan_shmif_cont) callconv(.c) c_int;
extern fn arcan_timemillis() callconv(.c) c_ulonglong;
extern fn arcan_shmif_pushutf8(ctx: ?*arcan_shmif_cont, ev: *arcan_event, msg: [*c]const u8, len: usize) callconv(.c) bool;
extern fn arcan_shmif_bchunk_resolve(ctx: ?*arcan_shmif_cont, ev: *const arcan_event) callconv(.c) [*c]u8;
extern fn arcan_shmif_bgcopy(ctx: ?*arcan_shmif_cont, fdin: c_int, fdout: c_int, sigfd: c_int, fl: c_int) callconv(.c) void;
extern fn arcan_shmif_handover_exec(ctx: ?*arcan_shmif_cont, ev: arcan_event, path: [*c]const u8, argv: [*c][*c]u8, env: [*c][*c]u8, flags: c_int) callconv(.c) c_int;
extern fn arcan_shmif_handover_exec_pipe(ctx: ?*arcan_shmif_cont, ev: arcan_event, path: [*c]const u8, argv: [*c][*c]u8, env: [*c][*c]u8, flags: c_int, fds: [*c][*c]c_int, fds_sz: usize) callconv(.c) c_int;

// libc
extern fn poll(fds: [*]pollfd, nfds: u32, timeout: c_int) callconv(.c) c_int;
extern fn memcmp(a: ?*const anyopaque, b: ?*const anyopaque, n: usize) callconv(.c) c_int;
extern fn memcpy(dst: ?*anyopaque, src: ?*const anyopaque, n: usize) callconv(.c) ?*anyopaque;
extern fn memset(dst: ?*anyopaque, c: c_int, n: usize) callconv(.c) ?*anyopaque;
extern fn malloc(n: usize) callconv(.c) ?*anyopaque;
extern fn free(p: ?*anyopaque) callconv(.c) void;

// errno — must use __errno_location() on Linux (errno is thread-local)
extern fn __errno_location() *c_int;
fn setErrno(val: c_int) void {
    __errno_location().* = val;
}
const EINVAL: c_int = 22;

// pid_t type
const pid_t = c_int;

// pollfd struct
const pollfd = extern struct {
    fd: c_int,
    events: i16,
    revents: i16,
};

// tpack_gen_opts (from tui_int.h)
const tpack_gen_opts = extern struct {
    full: bool,
    synch: bool,
    back: bool,
};

// tui_subwnd_req
const tui_subwnd_req = extern struct {
    hint: c_int,
    rows: usize,
    cols: usize,
};

// tui_process_res
const tui_process_res = extern struct {
    ok: u32,
    bad: u32,
    errc: c_int,
};

// tui_region
const tui_region = extern struct {
    dx: c_int,
    dy: c_int,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
};

// arcan_tui_conn — same as arcan_shmif_cont
const arcan_tui_conn = arcan_shmif_cont;

// Low-level byte-offset field accessors
// These replicate the approach used in arcan_zig_types.zig

inline fn ptrAt(ctx: *tui_context, comptime T: type, offset: usize) *T {
    const base: [*]u8 = @ptrCast(ctx);
    return @ptrCast(@alignCast(base + offset));
}

inline fn ptrAtConst(ctx: *const tui_context, comptime T: type, offset: usize) *const T {
    const base: [*]const u8 = @ptrCast(ctx);
    return @ptrCast(@alignCast(base + offset));
}

// Get the 'screen' pointer (tsm_screen*) — non-null means legacy tsm mode
fn getScreen(c: *tui_context) ?*anyopaque {
    return ptrAt(c, ?*anyopaque, OFF_SCREEN).*;
}

// Get front/back cell buffers (may be null before screen init)
fn getFront(c: *tui_context) ?[*]tui_cell {
    return ptrAt(c, ?[*]tui_cell, OFF_FRONT).*;
}

fn getBack(c: *tui_context) ?[*]tui_cell {
    return ptrAt(c, ?[*]tui_cell, OFF_BACK).*;
}

fn getDefattr(c: *tui_context) *tui_screen_attr {
    return ptrAt(c, tui_screen_attr, OFF_DEFATTR);
}

fn getDefattrConst(c: *const tui_context) *const tui_screen_attr {
    return ptrAtConst(c, tui_screen_attr, OFF_DEFATTR);
}

fn getFstamp(c: *tui_context) *u8 {
    return ptrAt(c, u8, OFF_FSTAMP);
}

fn getFlags(c: *tui_context) *u32 {
    return ptrAt(c, u32, OFF_FLAGS);
}

fn getFlagsConst(c: *const tui_context) *const u32 {
    return ptrAtConst(c, u32, OFF_FLAGS);
}

fn getDirty(c: *tui_context) *u32 {
    return ptrAt(c, u32, OFF_DIRTY);
}

fn getInactTimer(c: *tui_context) *c_int {
    return ptrAt(c, c_int, OFF_INACT_TIMER);
}

fn getMouseForward(c: *tui_context) *bool {
    return ptrAt(c, bool, OFF_MOUSE_FORWARD);
}

fn getRows(c: *const tui_context) c_int {
    return ptrAtConst(c, c_int, OFF_ROWS).*;
}

fn getCols(c: *const tui_context) c_int {
    return ptrAtConst(c, c_int, OFF_COLS).*;
}

fn getCx(c: *tui_context) *c_int {
    return ptrAt(c, c_int, OFF_CX);
}

fn getCy(c: *tui_context) *c_int {
    return ptrAt(c, c_int, OFF_CY);
}

fn getCellW(c: *const tui_context) c_int {
    return ptrAtConst(c, c_int, OFF_CELL_W).*;
}

fn getCellH(c: *const tui_context) c_int {
    return ptrAtConst(c, c_int, OFF_CELL_H).*;
}

fn getCursorHardOff(c: *tui_context) *bool {
    return ptrAt(c, bool, OFF_CURSOR_HARD_OFF);
}

fn getCursor(c: *tui_context) *c_int {
    return ptrAt(c, c_int, OFF_CURSOR);
}

fn getCursorColorOverride(c: *tui_context) *bool {
    return ptrAt(c, bool, OFF_CURSOR_COLOR_OVERRIDE);
}

fn getCursorColor(c: *tui_context) [*]u8 {
    const base: [*]u8 = @ptrCast(c);
    return base + OFF_CURSOR_COLOR;
}

// sbstat access: sbstat is a struct { long ofs; unsigned len; arcan_event hint; bool dirty; }
// hint is at OFF_SBSTAT_HINT (= OFF_SBSTAT + 16, since long=8 + unsigned=4 + pad=4)
fn getSbstatHint(c: *tui_context) *arcan_event {
    return ptrAt(c, arcan_event, OFF_SBSTAT_HINT);
}

fn getSbstatDirty(c: *tui_context) *bool {
    return ptrAt(c, bool, OFF_SBSTAT_DIRTY);
}

// colors: struct color[TUI_COL_LIMIT], each COLOR_SIZEOF bytes
fn getColorRgb(c: *tui_context, group: c_int) [*]u8 {
    const base: [*]u8 = @ptrCast(c);
    const offset = OFF_COLORS + @as(usize, @intCast(group)) * COLOR_SIZEOF + COLOR_OFF_RGB;
    return base + offset;
}

fn getColorBg(c: *tui_context, group: c_int) [*]u8 {
    const base: [*]u8 = @ptrCast(c);
    const offset = OFF_COLORS + @as(usize, @intCast(group)) * COLOR_SIZEOF + COLOR_OFF_BG;
    return base + offset;
}

fn getColorBgset(c: *tui_context, group: c_int) *bool {
    return ptrAt(c, bool, OFF_COLORS + @as(usize, @intCast(group)) * COLOR_SIZEOF + COLOR_OFF_BGSET);
}

// acon access
fn getAcon(c: *tui_context) *arcan_shmif_cont {
    return @ptrCast(ptrAt(c, u8, OFF_ACON));
}

fn getAconConst(c: *const tui_context) *const arcan_shmif_cont {
    return @ptrCast(ptrAtConst(c, u8, OFF_ACON));
}

fn getClipIn(c: *tui_context) *arcan_shmif_cont {
    return @ptrCast(ptrAt(c, u8, OFF_CLIP_IN));
}

// Check if acon.addr is non-null (connection alive)
fn aconHasAddr(c: *const tui_context) bool {
    const base: [*]const u8 = @ptrCast(c);
    const addr_ptr: *const ?*anyopaque = @ptrCast(@alignCast(base + OFF_ACON + SHMIF_OFF_ADDR));
    return addr_ptr.* != null;
}

// Get acon.w and acon.h
fn getAconW(c: *const tui_context) u32 {
    const base: [*]const u8 = @ptrCast(c);
    const w_ptr: *const u32 = @ptrCast(@alignCast(base + OFF_ACON + SHMIF_OFF_W));
    return w_ptr.*;
}

fn getAconH(c: *const tui_context) u32 {
    const base: [*]const u8 = @ptrCast(c);
    const h_ptr: *const u32 = @ptrCast(@alignCast(base + OFF_ACON + SHMIF_OFF_H));
    return h_ptr.*;
}

fn setAconW(c: *tui_context, val: u32) void {
    const base: [*]u8 = @ptrCast(c);
    const w_ptr: *u32 = @ptrCast(@alignCast(base + OFF_ACON + SHMIF_OFF_W));
    w_ptr.* = val;
}

fn setAconH(c: *tui_context, val: u32) void {
    const base: [*]u8 = @ptrCast(c);
    const h_ptr: *u32 = @ptrCast(@alignCast(base + OFF_ACON + SHMIF_OFF_H));
    h_ptr.* = val;
}

// Get acon.epipe
fn getAconEpipe(c: *const tui_context) c_int {
    const base: [*]const u8 = @ptrCast(c);
    const ep_ptr: *const c_int = @ptrCast(@alignCast(base + OFF_ACON + SHMIF_OFF_EPIPE));
    return ep_ptr.*;
}

// Get acon.segment_token
fn getAconSegmentToken(c: *const tui_context) u32 {
    const base: [*]const u8 = @ptrCast(c);
    const st_ptr: *const u32 = @ptrCast(@alignCast(base + OFF_ACON + SHMIF_OFF_SEGMENT_TOKEN));
    return st_ptr.*;
}

// Get clip_in.epipe
fn getClipInEpipe(c: *const tui_context) c_int {
    const base: [*]const u8 = @ptrCast(c);
    const ep_ptr: *const c_int = @ptrCast(@alignCast(base + OFF_CLIP_IN + SHMIF_OFF_EPIPE));
    return ep_ptr.*;
}

// Get clip_in.addr (to check if clipboard is active)
fn clipInHasAddr(c: *const tui_context) bool {
    const base: [*]const u8 = @ptrCast(c);
    const addr_ptr: *const ?*anyopaque = @ptrCast(@alignCast(base + OFF_CLIP_IN + SHMIF_OFF_ADDR));
    return addr_ptr.* != null;
}

// last_ident and last_state_sz
fn getLastIdent(c: *tui_context) *arcan_event {
    return ptrAt(c, arcan_event, OFF_LAST_IDENT);
}

fn getLastStateSz(c: *tui_context) *arcan_event {
    return ptrAt(c, arcan_event, OFF_LAST_STATE_SZ);
}

// last_constraints
fn getLastConstraints(c: *tui_context) *tui_constraints {
    return ptrAt(c, tui_constraints, OFF_LAST_CONSTRAINTS);
}

// pending_wnd
fn getPendingWnd(c: *tui_context) arcan_event {
    return ptrAt(c, arcan_event, OFF_PENDING_WND).*;
}

// viewport_proxy
fn getViewportProxy(c: *const tui_context) u32 {
    return ptrAtConst(c, u32, OFF_VIEWPORT_PROXY).*;
}

// hooks
const hooks_cursor_update_fn = ?*const fn (*tui_context) callconv(.c) void;
const hooks_reset_fn = ?*const fn (*tui_context) callconv(.c) void;

fn getHooksCursorUpdate(c: *tui_context) hooks_cursor_update_fn {
    return ptrAt(c, hooks_cursor_update_fn, OFF_HOOKS_CURSOR_UPDATE).*;
}

fn getHooksReset(c: *tui_context) hooks_reset_fn {
    return ptrAt(c, hooks_reset_fn, OFF_HOOKS_RESET).*;
}

// handlers
fn getHandlers(c: *tui_context) *tui_cbcfg {
    return ptrAt(c, tui_cbcfg, OFF_HANDLERS);
}

// Helper: strlen for C strings
fn cstrlen(s: [*c]const u8) usize {
    if (s == null) return 0;
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

// flag_cursor (static inline in C)
fn flag_cursor(c: *tui_context) void {
    getDirty(c).* |= DIRTY_CURSOR;
    getInactTimer(c).* = -4;

    if (getHooksCursorUpdate(c)) |cursor_update_fn| {
        cursor_update_fn(c);
    }
}

// write_front_checked (static in C)
fn write_front_checked(
    c: *tui_context,
    x: usize,
    y: usize,
    uc: u32,
    attr: ?*const tui_screen_attr,
) void {
    _ = x;
    _ = y;
    const cols: usize = @intCast(getCols(c));
    const rows: usize = @intCast(getRows(c));
    const cx: usize = @intCast(getCx(c).*);
    const cy: usize = @intCast(getCy(c).*);
    const ofs = cy * cols + cx;
    if (ofs >= cols * rows)
        return;

    const front = getFront(c) orelse return;
    const data = &front[ofs];
    data.fstamp = getFstamp(c).*;
    data.draw_ch = uc;
    data.ch = uc;
    if (attr) |a| {
        data.attr = a.*;
    }
    getDirty(c).* |= DIRTY_PARTIAL;
}

// ═══════════════════════════════════════════════════════════════
// Exported functions (match C ABI symbol names exactly)
// ═══════════════════════════════════════════════════════════════

export fn arcan_tui_copy(tui: ?*tui_context, utf8_msg: [*c]const u8) callconv(.c) bool {
    const t = tui orelse return false;
    return tui_clipboard_push(t, utf8_msg, cstrlen(utf8_msg));
}

export fn arcan_tui_getxy(
    tui: ?*tui_context,
    x: usize,
    y: usize,
    fl: bool,
) callconv(.c) tui_cell {
    const t = tui orelse return std.mem.zeroes(tui_cell);
    const rows: usize = @intCast(getRows(t));
    const cols: usize = @intCast(getCols(t));

    if (y >= rows or x >= cols)
        return std.mem.zeroes(tui_cell);

    const buf = (if (fl) getFront(t) else getBack(t)) orelse return std.mem.zeroes(tui_cell);
    return buf[y * cols + x];
}

export fn arcan_tui_request_subwnd(
    tui: ?*tui_context,
    @"type": u32,
    id: u16,
) callconv(.c) void {
    arcan_tui_request_subwnd_ext(
        tui,
        @"type",
        id,
        std.mem.zeroes(tui_subwnd_req),
        @sizeOf(tui_subwnd_req),
    );
}

export fn arcan_tui_request_subwnd_ext(
    tui: ?*tui_context,
    seg_type: u32,
    id: u16,
    req: tui_subwnd_req,
    req_sz: usize,
) callconv(.c) void {
    const T = tui orelse return;
    if (!aconHasAddr(T))
        return;

    // Map TUI_WND_* to SEGID_*
    const mapped_type: c_int = switch (seg_type) {
        TUI_WND_TUI => SEGID_TUI,
        TUI_WND_POPUP => SEGID_POPUP,
        TUI_WND_DEBUG => SEGID_DEBUG,
        TUI_WND_HANDOVER => SEGID_HANDOVER,
        TUI_WND_ACCESSIBILITY => SEGID_ACCESSIBILITY,
        else => return,
    };

    var ev = arcan_event.zeroes();
    ev.setCategory(EVENT_EXTERNAL);
    const ext = ev.asExt();
    ext.kind = EVENT_EXTERNAL_SEGREQ;
    ext.payload.segreq.kind = mapped_type;
    ext.payload.segreq.id = @as(u32, id) | (1 << 31);
    ext.payload.segreq.width = @intCast(getAconW(T));
    ext.payload.segreq.height = @intCast(getAconH(T));

    if (req_sz == @sizeOf(tui_subwnd_req)) {
        if (req.cols != 0)
            ext.payload.segreq.width = @intCast(@as(usize, @intCast(getCellW(T))) * req.cols);
        if (req.rows != 0)
            ext.payload.segreq.height = @intCast(@as(usize, @intCast(getCellH(T))) * req.rows);
        ext.payload.segreq.dir = @intCast(req.hint);
    }

    _ = arcan_shmif_enqueue(getAcon(T), &ev);
}

export fn arcan_tui_get_handles(
    contexts: [*c]?*tui_context,
    n_contexts: usize,
    fddst: [*c]c_int,
    fddst_lim: usize,
) callconv(.c) usize {
    var ret: usize = 0;
    if (fddst == null or contexts == null)
        return 0;

    var i: usize = 0;
    while (i < n_contexts and ret < fddst_lim) : (i += 1) {
        const ctx = contexts[i] orelse continue;
        if (!aconHasAddr(ctx))
            continue;

        fddst[ret] = getAconEpipe(ctx);
        ret += 1;

        if (clipInHasAddr(ctx) and ret < fddst_lim) {
            fddst[ret] = getClipInEpipe(ctx);
            ret += 1;
        }
    }

    return ret;
}

export fn arcan_tui_ucs4utf8(cp: u32, dst: [*c]u8) callconv(.c) usize {
    // Reject invalid codepoints
    if ((cp >= 0xd800 and cp <= 0xdfff) or
        (cp >= 0xfdd0 and cp <= 0xfdef) or
        (cp > 0x10ffff) or
        ((cp & 0xffff) == 0xffff) or
        ((cp & 0xffff) == 0xfffe))
        return 0;

    // ASCII range
    if (cp < (1 << 7)) {
        dst[0] = @intCast(cp & 0x7f);
        return 1;
    }

    if (cp < (1 << 11)) {
        dst[0] = @intCast(0xc0 | ((cp >> 6) & 0x1f));
        dst[1] = @intCast(0x80 | ((cp) & 0x3f));
        return 2;
    }

    if (cp < (1 << 16)) {
        dst[0] = @intCast(0xe0 | ((cp >> 12) & 0x0f));
        dst[1] = @intCast(0x80 | ((cp >> 6) & 0x3f));
        dst[2] = @intCast(0x80 | ((cp) & 0x3f));
        return 3;
    }

    if (cp < (1 << 21)) {
        dst[0] = @intCast(0xf0 | ((cp >> 18) & 0x07));
        dst[1] = @intCast(0x80 | ((cp >> 12) & 0x3f));
        dst[2] = @intCast(0x80 | ((cp >> 6) & 0x3f));
        dst[3] = @intCast(0x80 | ((cp) & 0x3f));
        return 4;
    }

    return 0;
}

export fn arcan_tui_ucs4utf8_s(cp: u32, dst: [*c]u8) callconv(.c) usize {
    const nc = arcan_tui_ucs4utf8(cp, dst);
    dst[nc] = '\x00';
    return nc;
}

export fn arcan_tui_utf8ucs4(src: [*c]const u8, dst: *u32) callconv(.c) isize {
    const c: u8 = src[0];

    // Out of range ASCII
    if (c == 0xC0 or c == 0xC1)
        return -1;

    // Single byte
    if ((c & 0x80) == 0) {
        dst.* = c;
        return 1;
    }

    // Started at middle of sequence
    if ((c & 0xC0) == 0x80)
        return -2;

    var left: u8 = undefined;
    var used: u8 = undefined;

    if ((c & 0xE0) == 0xC0) {
        dst.* = @as(u32, c & 0x1F) << 6;
        left = 1;
        used = 2;
    } else if ((c & 0xF0) == 0xE0) {
        dst.* = @as(u32, c & 0x0F) << 12;
        left = 2;
        used = 3;
    } else if ((c & 0xF8) == 0xF0) {
        dst.* = @as(u32, c & 0x07) << 18;
        left = 3;
        used = 4;
    } else {
        return -1;
    }

    while (left > 0) {
        const bc: u8 = src[used - left];
        if ((bc & 0xC0) != 0x80)
            return -1;

        if (left == 3) {
            dst.* |= @as(u32, bc & 0x3F) << 12;
            left -= 1;
        } else if (left == 2) {
            dst.* |= @as(u32, bc & 0x3F) << 6;
            left -= 1;
        } else if (left == 1) {
            dst.* |= @as(u32, bc & 0x3F);
            left -= 1;
        }
    }

    return @as(isize, used);
}

export fn arcan_tui_process(
    contexts: [*c]?*tui_context,
    n_contexts: usize,
    fdset: [*c]c_int,
    fdset_sz: usize,
    timeout: c_int,
) callconv(.c) tui_process_res {
    var res = std.mem.zeroes(tui_process_res);

    if (fdset_sz + n_contexts == 0) {
        res.errc = TUI_ERRC_BAD_ARG;
        return res;
    }

    if ((n_contexts > 0 and contexts == null) or (fdset_sz > 0 and fdset == null)) {
        res.errc = TUI_ERRC_BAD_ARG;
        return res;
    }

    if (n_contexts > 32 or fdset_sz > 32) {
        res.errc = TUI_ERRC_BAD_ARG;
        return res;
    }

    var cur_timeout = timeout;

    // Diagnostic counters (observe-only, does not change behavior).
    const Diag = struct {
        var calls: u64 = 0;
        var fast_poll: u64 = 0;     // cur_timeout forced to 0 (dirty)
        var fast_poll_signalled: u64 = 0; // fast-poll while SIGVID outstanding
        var last_report_ms: c_ulonglong = 0;
    };
    Diag.calls += 1;

    var saw_dirty_ctx: bool = false;
    var saw_pending_sig: bool = false;
    _ = &saw_pending_sig;

    // Check for bad/dirty contexts
    {
        var i: usize = 0;
        while (i < n_contexts) : (i += 1) {
            const ctx = contexts[i] orelse {
                res.bad |= @as(u32, 1) << @intCast(i);
                continue;
            };
            if (!aconHasAddr(ctx)) {
                res.bad |= @as(u32, 1) << @intCast(i);
            } else if (getDirty(ctx).* != 0) {
                saw_dirty_ctx = true;
                if (arcan_shmif_signalstatus(getAcon(ctx)) != 0)
                    saw_pending_sig = true;
                cur_timeout = 0;
            }
        }
    }

    if (saw_dirty_ctx) {
        Diag.fast_poll += 1;
        if (saw_pending_sig) Diag.fast_poll_signalled += 1;
    }

    // Rate-limited report: one line per ~500ms of activity.
    const now_ms = arcan_timemillis();
    if (now_ms - Diag.last_report_ms > 500) {
        Diag.last_report_ms = now_ms;
        var dbuf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&dbuf,
            "[DIAG tui_process] calls={d} fast_poll={d} fast_poll_signalled={d} cur_timeout={d} dirty={} sig_pending={}\n",
            .{ Diag.calls, Diag.fast_poll, Diag.fast_poll_signalled,
               cur_timeout, saw_dirty_ctx, saw_pending_sig }) catch "[DIAG tui_process] bufPrint failed\n";
        if (comptime @import("builtin").os.tag != .freestanding) {
            std.fs.File.stderr().writeAll(msg) catch {};
        }
    }

    if (res.bad != 0) {
        res.errc = TUI_ERRC_BAD_CTX;
        return res;
    }

    // Build pollfd array: n_contexts*2 (clip_in, acon) + fdset_sz
    const max_fds = n_contexts * 2 + fdset_sz;
    // Use a stack-allocated array large enough (32*2 + 32 = 96)
    var fds: [96]pollfd = std.mem.zeroes([96]pollfd);
    const pollev: i16 = POLLIN | POLLERR | POLLNVAL | POLLHUP;

    var ofs: usize = 0;
    {
        var i: usize = 0;
        while (i < n_contexts) : (i += 1) {
            const ctx = contexts[i].?;
            const clip_epipe = if (clipInHasAddr(ctx)) getClipInEpipe(ctx) else -1;
            fds[ofs] = .{
                .fd = clip_epipe,
                .events = pollev,
                .revents = 0,
            };
            ofs += 1;
            fds[ofs] = .{
                .fd = getAconEpipe(ctx),
                .events = pollev,
                .revents = 0,
            };
            ofs += 1;
        }
    }

    const fdset_ofs = ofs;
    {
        var i: usize = 0;
        while (i < fdset_sz) : (i += 1) {
            fds[ofs] = .{
                .fd = fdset[i],
                .events = pollev,
                .revents = 0,
            };
            ofs += 1;
        }
    }

    var sv = poll(&fds, @intCast(ofs), cur_timeout);

    // Diagnostic: when poll returns quickly but nothing draining, log which
    // fd is holding its revents (usually POLLHUP on a peer-closed pipe).
    // Rate-limited so 1M+ spinning iterations don't flood.
    {
        const DiagRe = struct { var last_ms: c_ulonglong = 0; };
        const nowms = arcan_timemillis();
        if (sv > 0 and nowms - DiagRe.last_ms > 500) {
            DiagRe.last_ms = nowms;
            var buf: [256]u8 = undefined;
            var off_b: usize = 0;
            var wi: usize = 0;
            while (wi < ofs and off_b < buf.len - 32) : (wi += 1) {
                const slot_kind: []const u8 = blk: {
                    if (wi < n_contexts * 2) {
                        break :blk if (wi % 2 == 0) "clip" else "acon";
                    }
                    break :blk "user";
                };
                const s = std.fmt.bufPrint(buf[off_b..],
                    " [{s}:fd={d} re=0x{x}]", .{ slot_kind, fds[wi].fd, @as(u16, @bitCast(fds[wi].revents)) }) catch break;
                off_b += s.len;
            }
            var outbuf: [384]u8 = undefined;
            const line = std.fmt.bufPrint(&outbuf,
                "[DIAG tui_poll_revents] sv={d} cur_timeout={d}{s}\n",
                .{ sv, cur_timeout, buf[0..off_b] }) catch "[DIAG tui_poll_revents] bufPrint failed\n";
            if (comptime @import("builtin").os.tag != .freestanding) {
                std.fs.File.stderr().writeAll(line) catch {};
            }
        }
    }

    // Process context events
    {
        var ci: usize = 0;
        while (ci < n_contexts and sv > 0) : (ci += 1) {
            if (fds[ci * 2].revents != 0) {
                tui_clipboard_check(contexts[ci]);
                sv -= 1;
            }
            if (fds[ci * 2 + 1].revents != 0) {
                tui_event_poll(contexts[ci]);
                sv -= 1;
            }
        }
    }

    // Process caller-supplied fds
    {
        var i: usize = fdset_ofs;
        while (i < ofs and sv > 0) : (i += 1) {
            if (fds[i].revents != 0) {
                sv -= 1;
                if (fds[i].revents == POLLIN) {
                    res.ok |= @as(u32, 1) << @intCast(i - fdset_ofs);
                } else {
                    res.bad |= @as(u32, 1) << @intCast(i - fdset_ofs);
                }
            }
        }
    }

    if (res.bad != 0)
        res.errc = TUI_ERRC_BAD_FD;

    _ = max_fds;
    return res;
}

export fn arcan_tuiint_dirty(tui: ?*tui_context) callconv(.c) c_int {
    const t = tui orelse return 0;
    return @intCast(getDirty(t).*);
}

export fn arcan_tui_refresh(tui: ?*tui_context) callconv(.c) c_int {
    const t = tui orelse {
        setErrno(EINVAL);
        return -1;
    };

    if (!aconHasAddr(t)) {
        setErrno(EINVAL);
        return -1;
    }

    if (getSbstatDirty(t).*) {
        _ = arcan_shmif_enqueue(getAcon(t), getSbstatHint(t));
        getSbstatDirty(t).* = false;
    }

    if (getDirty(t).* != 0) {
        return tui_screen_refresh(t);
    }

    return 0;
}

export fn arcan_tui_wndhint(
    tui: ?*tui_context,
    par: ?*tui_context,
    cons: tui_constraints,
) callconv(.c) void {
    const C = tui orelse return;

    const max_cols = cons.max_cols;
    const max_rows = cons.max_rows;
    const min_cols = cons.min_cols;
    const min_rows = cons.min_rows;

    var cols = if (max_cols != 0) max_cols else min_cols;
    var rows = if (max_rows != 0) max_rows else min_rows;

    // Special case: detached window — inject as displayhint
    if (!aconHasAddr(C) and (cols > 0 or rows > 0)) {
        getLastConstraints(C).* = cons;

        if (cols <= 0) cols = getCols(C);
        if (rows <= 0) rows = getRows(C);

        if (cols > 0) {
            setAconW(C, @intCast(getCellW(C) * cols));
        }
        if (rows > 0) {
            setAconH(C, @intCast(getCellH(C) * rows));
        }

        tui_screen_resized(C);
    }

    // Send sizing constraints
    if (cols > 0 or rows > 0) {
        var content = arcan_event.zeroes();
        content.setCategory(EVENT_EXTERNAL);
        const ext = content.asExt();
        ext.kind = EVENT_EXTERNAL_CONTENT;
        ext.payload.content.min_w = @intCast(cons.min_cols * getCellW(C));
        ext.payload.content.min_h = @intCast(cons.min_rows * getCellH(C));
        ext.payload.content.max_w = @intCast(cons.max_cols * getCellW(C));
        ext.payload.content.max_h = @intCast(cons.max_rows * getCellH(C));
        ext.payload.content.cell_w = @intCast(getCellW(C));
        ext.payload.content.cell_h = @intCast(getCellH(C));

        if (aconHasAddr(C))
            _ = arcan_shmif_enqueue(getAcon(C), &content);
    }

    // Send viewport/anchoring if parent provided
    if (par) |P| {
        var viewport = arcan_event.zeroes();
        viewport.setCategory(EVENT_EXTERNAL);
        const ext = viewport.asExt();
        ext.kind = EVENT_EXTERNAL_VIEWPORT;
        ext.payload.viewport.parent = getAconSegmentToken(P);
        ext.payload.viewport.x = cons.anch_col * getCellW(P);
        ext.payload.viewport.y = cons.anch_row * getCellH(P);
        ext.payload.viewport.w = @intCast(cons.max_cols * getCellW(P));
        ext.payload.viewport.h = @intCast(cons.max_rows * getCellH(P));
        ext.payload.viewport.invisible = @intCast(cons.hide);

        const vp = getViewportProxy(C);
        if (vp != 0) {
            ext.payload.viewport.embedded = @intCast(cons.embed);
            ext.payload.viewport.parent = vp;
            ext.payload.viewport.order = -1;

            if (aconHasAddr(P))
                _ = arcan_shmif_enqueue(getAcon(P), &viewport);
        } else if (aconHasAddr(C)) {
            _ = arcan_shmif_enqueue(getAcon(C), &viewport);
        }
    }

    getLastConstraints(C).* = cons;
}

export fn arcan_tui_fdresolve(tui: ?*tui_context, fd: c_int) callconv(.c) [*c]u8 {
    const t = tui orelse return null;

    var aev = arcan_event.zeroes();
    aev.setCategory(EVENT_TARGET);
    const tgt = aev.asTgtMut();
    // TARGET_COMMAND_BCHUNK_IN = 14
    tgt.kind = 14;
    tgt.ioevs[0].iv = fd;

    return arcan_shmif_bchunk_resolve(getAcon(t), &aev);
}

export fn arcan_tui_bgcopy(
    tui: ?*tui_context,
    fdin: c_int,
    fdout: c_int,
    sigfd: c_int,
    fl: c_int,
) callconv(.c) void {
    const t = tui orelse return;
    arcan_shmif_bgcopy(getAcon(t), fdin, fdout, sigfd, fl);
}

export fn arcan_tui_get_color(
    tui: ?*tui_context,
    group: c_int,
    rgb: [*c]u8,
) callconv(.c) void {
    const t = tui orelse return;
    if (group < TUI_COL_LIMIT and group >= TUI_COL_PRIMARY) {
        const src = getColorRgb(t, group);
        rgb[0] = src[0];
        rgb[1] = src[1];
        rgb[2] = src[2];
    }
}

export fn arcan_tui_get_bgcolor(
    tui: ?*tui_context,
    group: c_int,
    rgb: [*c]u8,
) callconv(.c) void {
    const t = tui orelse return;

    switch (group) {
        1,
        TUI_COL_TEXT,
        TUI_COL_HIGHLIGHT,
        TUI_COL_LABEL,
        TUI_COL_WARNING,
        TUI_COL_ERROR,
        TUI_COL_ALERT,
        TUI_COL_REFERENCE,
        TUI_COL_INACTIVE,
        TUI_COL_UI,
        => {
            // Use bg if explicitly set, otherwise fall back to TUI_COL_BG.rgb
            const src = if (getColorBgset(t, group).*) getColorBg(t, group) else getColorRgb(t, TUI_COL_BG);
            rgb[0] = src[0];
            rgb[1] = src[1];
            rgb[2] = src[2];
        },
        // For reference groups and all others, always use BG as BG color
        else => {
            const src = getColorRgb(t, TUI_COL_BG);
            rgb[0] = src[0];
            rgb[1] = src[1];
            rgb[2] = src[2];
        },
    }
}

export fn arcan_tui_set_bgcolor(
    tui: ?*tui_context,
    group: c_int,
    rgb: [*c]u8,
) callconv(.c) void {
    const t = tui orelse return;

    switch (group) {
        // These are no-ops for bgcolor
        TUI_COL_PRIMARY,
        TUI_COL_SECONDARY,
        TUI_COL_ALTCURSOR,
        TUI_COL_CURSOR,
        => {},

        TUI_COL_BG,
        TUI_COL_TEXT,
        TUI_COL_HIGHLIGHT,
        TUI_COL_LABEL,
        TUI_COL_WARNING,
        TUI_COL_ERROR,
        TUI_COL_ALERT,
        TUI_COL_REFERENCE,
        TUI_COL_INACTIVE,
        TUI_COL_UI,
        => {
            const dst = getColorBg(t, group);
            dst[0] = rgb[0];
            dst[1] = rgb[1];
            dst[2] = rgb[2];
            getColorBgset(t, group).* = true;
        },
        else => {},
    }
}

export fn arcan_tui_acon(ctx: ?*tui_context) callconv(.c) ?*arcan_shmif_cont {
    const t = ctx orelse return null;
    return getAcon(t);
}

export fn arcan_tui_get_conn(ctx: ?*tui_context) callconv(.c) ?*arcan_shmif_cont {
    return arcan_tui_acon(ctx);
}

export fn arcan_tui_set_color(
    tui: ?*tui_context,
    group: c_int,
    rgb: [*c]u8,
) callconv(.c) void {
    const t = tui orelse return;

    if (group < TUI_COL_LIMIT and group >= TUI_COL_PRIMARY) {
        const dst = getColorRgb(t, group);
        dst[0] = rgb[0];
        dst[1] = rgb[1];
        dst[2] = rgb[2];

        if (group >= TUI_COL_TBASE) {
            // Also set bg for terminal-base colors
            const bgdst = getColorBg(t, group);
            bgdst[0] = rgb[0];
            bgdst[1] = rgb[1];
            bgdst[2] = rgb[2];
        }
    }
}

export fn arcan_tui_update_handlers(
    tui: ?*tui_context,
    cbs: ?*const tui_cbcfg,
    out: ?*tui_cbcfg,
    cbs_sz: usize,
) callconv(.c) bool {
    const t = tui orelse return false;
    if (cbs_sz > @sizeOf(tui_cbcfg))
        return false;

    if (out) |o| {
        _ = memcpy(@ptrCast(o), @ptrCast(getHandlers(t)), cbs_sz);
    }

    if (cbs) |c| {
        _ = memcpy(@ptrCast(getHandlers(t)), @ptrCast(c), cbs_sz);
    }

    return true;
}

export fn arcan_tui_statesize(c: ?*tui_context, sz: usize) callconv(.c) void {
    const t = c orelse return;

    var ev = arcan_event.zeroes();
    ev.setCategory(EVENT_EXTERNAL);
    const ext = ev.asExt();
    ext.kind = EVENT_EXTERNAL_STATESIZE;
    ext.payload.stateinf.size = @intCast(sz);

    getLastStateSz(t).* = ev;
    _ = arcan_shmif_enqueue(getAcon(t), &ev);
}

// add_to_event (static helper)
fn add_to_event(
    c: *tui_context,
    more: bool,
    ev: *arcan_event,
    ofs: *usize,
    msg: [*c]const u8,
    nb: usize,
) void {
    // extensions is 68 bytes (in arcan_zig_types.zig bchunk.extensions: [68]u8)
    const lim: usize = 68;
    const ext = ev.asExt();

    // If not enough room, enable multipart and flush
    if (nb + ofs.* > lim - 1) {
        if (more) {
            ext.payload.bchunk.hint |= 4;
        } else {
            ext.payload.bchunk.hint &= ~@as(u8, 4);
        }
        // Remove separator
        if (ofs.* > 0)
            ext.payload.bchunk.extensions[ofs.* - 1] = '\x00';
        _ = arcan_shmif_enqueue(getAcon(c), ev);
        _ = memset(@ptrCast(&ext.payload.bchunk.extensions[0]), 0, lim);
        ofs.* = 0;
    }

    // Append and continue
    _ = memcpy(@ptrCast(&ext.payload.bchunk.extensions[ofs.*]), @ptrCast(msg), nb);
    ofs.* += nb;

    if (!more) {
        _ = arcan_shmif_enqueue(getAcon(c), ev);
        ext.payload.bchunk.hint &= ~@as(u8, 4);
        _ = memset(@ptrCast(&ext.payload.bchunk.extensions[0]), 0, lim);
    }
}

// send_list (static helper)
fn send_list(
    c: *tui_context,
    ev_in: arcan_event,
    suffix: [*c]const u8,
    list: [*c]const u8,
) void {
    var ev = ev_in;
    var start: usize = 0;
    var end: usize = 0;
    var ofs: usize = 0;
    const ext = ev.asExt();

    while (list[end] != 0) {
        if (list[end] == '*') {
            ext.payload.bchunk.hint |= 2;
            end += 1;
            start = end;
            continue;
        }

        // ';' is the delimiter
        if (list[end] != ';') {
            end += 1;
            continue;
        }

        // Ignore empty
        if (end == start) {
            end += 1;
            start = end;
            continue;
        }

        // Include the delimiter in nb
        const nb = end - start + 1;

        // If entry exceeds permitted length, skip it
        if (nb > 64) {
            start = end;
            continue;
        }

        // more = (there is a next char after ';') or suffix is non-null
        const next_char = list[end + 1];
        const more = (next_char != 0) or (suffix != null and suffix[0] != 0);
        add_to_event(c, more, &ev, &ofs, list + start, nb);
        end += 1;
        start = end;
    }

    // Leftover (no trailing ';')
    if (start != end) {
        const has_suffix = (suffix != null and suffix[0] != 0);
        add_to_event(c, has_suffix, &ev, &ofs, list + start, end - start);
    }

    if (suffix != null and suffix[0] != 0) {
        add_to_event(c, false, &ev, &ofs, suffix, cstrlen(suffix));
    }

    // Multipart terminator
    if ((ev.asExt().payload.bchunk.hint & 4) != 0) {
        ev.asExt().payload.bchunk.hint &= ~@as(u8, 4);
        _ = arcan_shmif_enqueue(getAcon(c), &ev);
    }
}

export fn arcan_tui_send_message(
    src: ?*tui_context,
    local: bool,
    msg: [*c]const u8,
) callconv(.c) void {
    // Intentionally empty (as in C original)
    _ = src;
    _ = local;
    _ = msg;
}

export fn arcan_tui_announce_cursor_io(
    c: ?*tui_context,
    descr: [*c]const u8,
) callconv(.c) void {
    const t = c orelse return;

    var ev = arcan_event.zeroes();
    ev.setCategory(EVENT_EXTERNAL);
    const ext = ev.asExt();
    ext.kind = EVENT_EXTERNAL_BCHUNKSTATE;
    ext.payload.bchunk.input = 0; // false
    ext.payload.bchunk.hint = 8;

    send_list(t, ev, @as([*c]const u8, ""), descr);
}

export fn arcan_tui_announce_io(
    c: ?*tui_context,
    immediately: bool,
    input_descr: [*c]const u8,
    output_descr: [*c]const u8,
) callconv(.c) void {
    const t = c orelse return;

    var ev = arcan_event.zeroes();
    ev.setCategory(EVENT_EXTERNAL);
    const ext = ev.asExt();
    ext.kind = EVENT_EXTERNAL_BCHUNKSTATE;
    ext.payload.bchunk.input = 1; // true
    ext.payload.bchunk.hint = if (immediately) 1 else 0;
    // Set extensions to "*\0" (wildcard hint)
    ext.payload.bchunk.extensions[0] = '*';
    ext.payload.bchunk.extensions[1] = 0;

    if (immediately) {
        if (input_descr != null) {
            if (cstrlen(input_descr) == 0) {
                ext.payload.bchunk.hint |= 2; // wildcard
                _ = arcan_shmif_enqueue(getAcon(t), &ev);
            } else {
                send_list(t, ev, @as([*c]const u8, ""), input_descr);
            }
        }

        if (output_descr != null) {
            ext.payload.bchunk.hint = 0;
            ext.payload.bchunk.input = 0;
            if (cstrlen(output_descr) == 0) {
                ext.payload.bchunk.hint |= 2;
                _ = arcan_shmif_enqueue(getAcon(t), &ev);
            } else {
                send_list(t, ev, @as([*c]const u8, ""), output_descr);
            }
        }

        return;
    }

    if (input_descr != null) {
        const suffix: [*c]const u8 = if (cstrlen(input_descr) == 0) "stdin" else ";stdin";
        send_list(t, ev, suffix, input_descr);
    }

    if (output_descr != null) {
        ext.payload.bchunk.input = 0;
        const suffix: [*c]const u8 = if (cstrlen(output_descr) == 0)
            "tuiraw;stdout;stderr"
        else
            ";tuiraw;stdout;stderr";
        send_list(t, ev, suffix, output_descr);
    }
}

export fn arcan_tui_erase_screen(c: ?*tui_context, protect: bool) callconv(.c) void {
    const t = c orelse return;
    const def = arcan_tui_defattr(t, null);
    arcan_tui_eraseattr_screen(t, protect, def);
}

export fn arcan_tui_eraseattr_screen(
    c: ?*tui_context,
    protect: bool,
    attr: tui_screen_attr,
) callconv(.c) void {
    const t = c orelse return;
    arcan_tui_eraseattr_region(t, 0, 0, @intCast(getCols(t)), @intCast(getRows(t)), protect, attr);
}

export fn arcan_tui_eraseattr_region(
    c: ?*tui_context,
    x1: usize,
    y1: usize,
    x2: usize,
    y2: usize,
    protect: bool,
    attr: tui_screen_attr,
) callconv(.c) void {
    const t = c orelse return;

    const rows: usize = @intCast(getRows(t));
    const cols: usize = @intCast(getCols(t));
    const front = getFront(t) orelse return;
    const fstamp = getFstamp(t).*;

    var y: usize = y1;
    while (y < rows and y <= y2) : (y += 1) {
        var x: usize = x1;
        while (x < cols and x <= x2) : (x += 1) {
            const data = &front[y * cols + x];
            if (!protect or (data.attr.aflags & TUI_ATTR_PROTECT) == 0) {
                data.ch = 0;
                data.draw_ch = 0;
                data.attr = attr;
                data.fstamp = fstamp;
            }
        }
    }
    getDirty(t).* |= DIRTY_PARTIAL;
}

export fn arcan_tui_erase_region(
    c: ?*tui_context,
    x1: usize,
    y1: usize,
    x2: usize,
    y2: usize,
    protect: bool,
) callconv(.c) void {
    const t = c orelse return;
    const def = arcan_tui_defattr(t, null);
    arcan_tui_eraseattr_region(t, x1, y1, x2, y2, protect, def);
}

export fn arcan_tui_scrollhint(
    c: ?*tui_context,
    n_regions: usize,
    regions: ?*tui_region,
) callconv(.c) void {
    // FIXME: immature / incorrect (as in C original)
    _ = c;
    _ = n_regions;
    _ = regions;
}

export fn arcan_tui_defcattr(c: ?*tui_context, group: c_int) callconv(.c) tui_screen_attr {
    const t = c orelse return std.mem.zeroes(tui_screen_attr);

    var out = getDefattr(t).*;
    // Copy foreground color from group
    var rgb_buf: [3]u8 = [3]u8{ 0, 0, 0 };
    arcan_tui_get_color(t, group, &rgb_buf);
    out.fc = rgb_buf;
    arcan_tui_get_bgcolor(t, group, &rgb_buf);
    out.bc = rgb_buf;
    out.aflags &= ~TUI_ATTR_COLOR_INDEXED;

    return out;
}

export fn arcan_tui_defattr(
    c: ?*tui_context,
    attr: ?*const tui_screen_attr,
) callconv(.c) tui_screen_attr {
    const t = c orelse return std.mem.zeroes(tui_screen_attr);

    const out = getDefattr(t).*;
    if (attr) |a| {
        getDefattr(t).* = a.*;
    }
    return out;
}

export fn arcan_tui_write(
    c: ?*tui_context,
    ucode: u32,
    attr: ?*const tui_screen_attr,
) callconv(.c) void {
    const t = c orelse return;

    // Write + advance
    const use_attr = if (attr) |a| a else getDefattr(t);
    write_front_checked(t, @intCast(getCx(t).*), @intCast(getCy(t).*), ucode, use_attr);

    // Advance and wrap or clamp
    getCx(t).* += 1;
    if (getCx(t).* > getCols(t) - 1) {
        if ((getFlags(t).* & TUI_AUTO_WRAP) != 0) {
            getCx(t).* = 0;
            if (getCy(t).* < getRows(t) - 1)
                getCy(t).* += 1;
        } else {
            getCx(t).* = getCols(t) - 1;
        }
    }

    flag_cursor(t);
}

export fn arcan_tui_writeattr_at(
    c: ?*tui_context,
    attr: ?*const tui_screen_attr,
    x: usize,
    y: usize,
) callconv(.c) void {
    const t = c orelse return;
    const a = attr orelse return;

    // assert(c->screen == NULL) — only works in non-tsm mode
    const cols: usize = @intCast(getCols(t));
    const rows: usize = @intCast(getRows(t));
    if (x < cols and y < rows) {
        if (getFront(t)) |front| front[y * cols + x].attr = a.*;
    }

    flag_cursor(t);
}

export fn arcan_tui_ident(c: ?*tui_context, ident: [*c]const u8) callconv(.c) void {
    const t = c orelse return;

    var nev = arcan_event.zeroes();
    nev.setCategory(EVENT_EXTERNAL);
    const ext = nev.asExt();
    ext.kind = EVENT_EXTERNAL_IDENT;

    // Copy ident string into ext.payload.message.data (78 bytes), like snprintf(buf, lim, "%s", ident)
    const lim: usize = 78;
    if (ident != null) {
        const src_len = cstrlen(ident);
        const copy_len = if (src_len >= lim) lim - 1 else src_len;
        var i: usize = 0;
        while (i < copy_len) : (i += 1) {
            ext.payload.message.data[i] = ident[i];
        }
        ext.payload.message.data[copy_len] = 0;
    }

    if (memcmp(getLastIdent(t), &nev, SIZEOF_ARCAN_EVENT) != 0)
        _ = arcan_shmif_enqueue(getAcon(t), &nev);
    getLastIdent(t).* = nev;
}

export fn arcan_tui_writeu8(
    c: ?*tui_context,
    u8_data: [*c]const u8,
    len: usize,
    attr: ?*tui_screen_attr,
) callconv(.c) bool {
    const t = c orelse return false;
    if (u8_data == null or len == 0)
        return false;

    var pos: usize = 0;
    while (pos < len) {
        var ucs4: u32 = 0;
        const step = arcan_tui_utf8ucs4(u8_data + pos, &ucs4);
        if (step <= 0) {
            pos += 1;
        } else {
            pos += @intCast(step);
        }
        arcan_tui_write(t, ucs4, attr);
    }

    return true;
}

export fn arcan_tui_hasglyph(c: ?*tui_context, cp: u32) callconv(.c) bool {
    return tui_fontmgmt_hasglyph(c, cp);
}

export fn arcan_tui_writestr(
    c: ?*tui_context,
    str: [*c]const u8,
    attr: ?*tui_screen_attr,
) callconv(.c) bool {
    const t = c orelse return false;
    const len = cstrlen(str);
    return arcan_tui_writeu8(t, str, len, attr);
}

export fn arcan_tui_cursorpos(c: ?*tui_context, x: ?*usize, y: ?*usize) callconv(.c) void {
    const t = c orelse return;
    // assert(c->screen == NULL)
    if (x) |px| px.* = @intCast(getCx(t).*);
    if (y) |py| py.* = @intCast(getCy(t).*);
}

export fn arcan_tui_reset_labels(c: ?*tui_context) callconv(.c) void {
    const t = c orelse return;
    tui_expose_labels(t);
}

export fn arcan_tui_reset(c: ?*tui_context) callconv(.c) void {
    const t = c orelse return;

    if (getHooksReset(t)) |reset_fn| {
        reset_fn(t);
        return;
    }

    getFlags(t).* = TUI_ALTERNATE;
    // In C: .fc = TUI_COL_TEXT sets fc[0] = 5 (color index), fc[1..2] = 0
    getDefattr(t).* = tui_screen_attr{
        .fc = [3]u8{ @intCast(TUI_COL_TEXT), 0, 0 },
        .bc = [3]u8{ @intCast(TUI_COL_TEXT), 0, 0 },
        .aflags = TUI_ATTR_COLOR_INDEXED,
        .custom_id = 0,
    };

    arcan_tui_eraseattr_screen(t, false, getDefattr(t).*);
    flag_cursor(t);
}

export fn arcan_tui_dimensions(c: ?*tui_context, rows: ?*usize, cols: ?*usize) callconv(.c) void {
    const t = c orelse return;
    if (rows) |r| r.* = @intCast(getRows(t));
    if (cols) |cl| cl.* = @intCast(getCols(t));
}

export fn arcan_tui_progress(c: ?*tui_context, ptype: c_int, status_in: f32) callconv(.c) void {
    const t = c orelse return;
    if (ptype < TUI_PROGRESS_INTERNAL or ptype > TUI_PROGRESS_STATE_OUT)
        return;

    var status = status_in;
    if (status > 1.0) status = 1.0;
    if (status < 0.0001) status = 0.0001;

    var ev = arcan_event.zeroes();
    ev.setCategory(EVENT_EXTERNAL);
    const ext = ev.asExt();
    ext.kind = EVENT_EXTERNAL_STREAMSTATUS;
    ext.payload.streamstat.completion = status;
    ext.payload.streamstat.streaming = @intCast(ptype);

    _ = arcan_shmif_enqueue(getAcon(t), &ev);
}

export fn arcan_tui_set_flags(c: ?*tui_context, flags: c_int) callconv(.c) c_int {
    const t = c orelse return -1;

    const old_flags: c_int = @intCast(getFlags(t).*);
    getFlags(t).* = @intCast(flags);
    getCursorHardOff(t).* = (flags & @as(c_int, TUI_HIDE_CURSOR)) != 0;

    if (old_flags != flags)
        flag_cursor(t);

    if ((flags & @as(c_int, TUI_MOUSE | TUI_MOUSE_FULL)) != 0)
        getMouseForward(t).* = true;

    return old_flags;
}

export fn arcan_tui_move_to(c: ?*tui_context, x_in: usize, y_in: usize) callconv(.c) void {
    const t = c orelse return;

    var x = x_in;
    var y = y_in;

    const cols: usize = @intCast(getCols(t));
    const rows: usize = @intCast(getRows(t));

    if (x != 0 and x >= cols) x = cols - 1;
    if (y != 0 and y >= rows) y = rows - 1;

    if (x != @as(usize, @intCast(getCx(t).*)) or y != @as(usize, @intCast(getCy(t).*))) {
        getCx(t).* = @intCast(x);
        getCy(t).* = @intCast(y);
        flag_cursor(t);
    }
}

export fn arcan_tui_newline(c: ?*tui_context) callconv(.c) void {
    const t = c orelse return;
    const rows: usize = @intCast(getRows(t));
    getCx(t).* = 0;
    const cy = getCy(t);
    if (@as(usize, @intCast(cy.*)) + 1 >= rows) {
        scroll_front_up(t, 1);
    } else {
        cy.* += 1;
    }
    flag_cursor(t);
}

export fn arcan_tui_move_down(c: ?*tui_context, num: usize, scroll: bool) callconv(.c) void {
    const t = c orelse return;
    const rows: usize = @intCast(getRows(t));
    const cy = getCy(t);
    const cur: usize = @intCast(cy.*);
    if (cur + num >= rows) {
        if (scroll) {
            const overshoot = cur + num - (rows - 1);
            scroll_front_up(t, overshoot);
        }
        cy.* = @intCast(rows - 1);
    } else {
        cy.* += @intCast(num);
    }
    flag_cursor(t);
}

export fn arcan_tui_move_line_home(c: ?*tui_context) callconv(.c) void {
    const t = c orelse return;
    if (getCx(t).* != 0) {
        getCx(t).* = 0;
        flag_cursor(t);
    }
}

export fn arcan_tui_scroll_up(c: ?*tui_context, n: usize) callconv(.c) void {
    const t = c orelse return;
    scroll_front_up(t, n);
}

export fn arcan_tui_scroll_down(c: ?*tui_context, n: usize) callconv(.c) void {
    const t = c orelse return;
    const front = getFront(t) orelse return;
    const cols: usize = @intCast(getCols(t));
    const rows: usize = @intCast(getRows(t));
    const total = rows * cols;
    if (n >= rows) {
        for (0..total) |i| front[i] = std.mem.zeroes(tui_cell);
    } else {
        const shift = n * cols;
        const copy_cells = total - shift;
        std.mem.copyBackwards(tui_cell, front[shift..total], front[0..copy_cells]);
        for (0..shift) |i| front[i] = std.mem.zeroes(tui_cell);
    }
    getDirty(t).* |= DIRTY_FULL;
}

fn scroll_front_up(t: *tui_context, n: usize) void {
    const front = getFront(t) orelse return;
    const cols: usize = @intCast(getCols(t));
    const rows: usize = @intCast(getRows(t));
    const total = rows * cols;
    if (n >= rows) {
        for (0..total) |i| front[i] = std.mem.zeroes(tui_cell);
    } else {
        const shift = n * cols;
        const copy_cells = total - shift;
        std.mem.copyForwards(tui_cell, front[0..copy_cells], front[shift..total]);
        for (copy_cells..total) |i| front[i] = std.mem.zeroes(tui_cell);
    }
    getDirty(t).* |= DIRTY_FULL;
}

// arcan_tui_printf — variadic C function, not exported from Zig.
// Callers should use arcan_tui_writeu8 directly instead.
// The a11y code loads it via dlsym at runtime (optional).

export fn arcan_tui_message(
    c: ?*tui_context,
    target: c_int,
    msg: [*c]const u8,
) callconv(.c) void {
    const t = c orelse return;

    var outev = arcan_event.zeroes();
    outev.setCategory(EVENT_EXTERNAL);
    outev.asExt().kind = EVENT_EXTERNAL_MESSAGE;

    const len = cstrlen(msg);

    if (target == TUI_MESSAGE_PROMPT) {
        // fall through to arcan_shmif_pushutf8 below
    } else if (target == TUI_MESSAGE_ALERT) {
        outev.asExt().kind = EVENT_EXTERNAL_ALERT;
    } else if (target == TUI_MESSAGE_FAILURE) {
        outev.asExt().kind = EVENT_EXTERNAL_FAILURE;
    } else if (target == TUI_MESSAGE_NOTIFICATION) {
        const workstr: ?*u8 = @ptrCast(malloc(len + 2));
        if (workstr == null) return;
        const ws: [*]u8 = @ptrCast(workstr.?);
        ws[0] = '>';
        _ = memcpy(@ptrCast(ws + 1), @ptrCast(msg), len);
        ws[len + 1] = 0;
        _ = arcan_shmif_pushutf8(getAcon(t), &outev, msg, len);
        free(workstr);
        return;
    } else if (target == TUI_MESSAGE_LOCAL) {
        const handlers = getHandlers(t);
        if (handlers.message) |message_fn| {
            message_fn(c, msg, false, handlers.tag);
        }
        return;
    } else if (target == TUI_MESSAGE_GENERIC) {
        // fall through
    } else {
        return;
    }

    _ = arcan_shmif_pushutf8(getAcon(t), &outev, msg, len);
}

export fn arcan_tui_handover(
    c: ?*tui_context,
    conn: ?*arcan_tui_conn,
    path: [*c]const u8,
    argv: [*c][*c]u8,
    env: [*c][*c]u8,
    flags: c_int,
) callconv(.c) pid_t {
    const t = c orelse return -1;
    _ = conn;
    return arcan_shmif_handover_exec(
        getAcon(t),
        getPendingWnd(t),
        path,
        argv,
        env,
        flags,
    );
}

export fn arcan_tui_handover_pipe(
    c: ?*tui_context,
    conn: ?*arcan_tui_conn,
    path: [*c]const u8,
    argv: [*c][*c]u8,
    env: [*c][*c]u8,
    fds: [*c][*c]c_int,
    fds_sz: usize,
) callconv(.c) pid_t {
    const t = c orelse return -1;
    _ = conn;
    return arcan_shmif_handover_exec_pipe(
        getAcon(t),
        getPendingWnd(t),
        path,
        argv,
        env,
        0,
        fds,
        fds_sz,
    );
}

export fn arcan_tui_content_size(
    c: ?*tui_context,
    row_ofs: usize,
    row_tot: usize,
    col_ofs: usize,
    col_tot: usize,
) callconv(.c) void {
    const t = c orelse return;

    var ev = arcan_event.zeroes();
    ev.setCategory(EVENT_EXTERNAL);
    const ext = ev.asExt();
    ext.kind = EVENT_EXTERNAL_CONTENT;
    ext.payload.content.x_sz = 1.0;
    ext.payload.content.y_sz = 1.0;

    const cols: usize = @intCast(getCols(t));
    const rows: usize = @intCast(getRows(t));

    if (col_tot > cols and col_ofs < col_tot) {
        ext.payload.content.x_sz = @as(f32, @floatFromInt(cols)) / @as(f32, @floatFromInt(col_tot));
        ext.payload.content.x_pos = @as(f32, @floatFromInt(col_ofs)) / @as(f32, @floatFromInt(col_tot));
        ext.payload.content.width = 1.0 / @as(f32, @floatFromInt(col_tot - cols));
    }

    if (row_tot > rows and row_ofs < row_tot) {
        ext.payload.content.y_sz = @as(f32, @floatFromInt(rows)) / @as(f32, @floatFromInt(row_tot));
        ext.payload.content.y_pos = @as(f32, @floatFromInt(row_ofs)) / @as(f32, @floatFromInt(row_tot));
        ext.payload.content.height = 1.0 / @as(f32, @floatFromInt(row_tot - rows));
    }

    getSbstatDirty(t).* = true;
    getSbstatHint(t).* = ev;
}

export fn arcan_tui_tpack(
    tui: ?*tui_context,
    rbuf: [*c][*c]u8,
    rbuf_sz: [*c]usize,
) callconv(.c) bool {
    if (rbuf == null or rbuf_sz == null)
        return false;

    const cap = tui_screen_tpack_sz(tui);
    const raw: ?*anyopaque = malloc(cap);
    if (raw == null)
        return false;

    const buf: [*c]u8 = @ptrCast(raw.?);
    rbuf[0] = buf;
    rbuf_sz[0] = tui_screen_tpack(
        tui,
        tpack_gen_opts{ .full = true, .synch = false, .back = false },
        buf,
        cap,
    );

    return true;
}

export fn arcan_tui_tunpack(
    tui: ?*tui_context,
    buf: [*c]u8,
    buf_sz: usize,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
) callconv(.c) bool {
    return tui_tpack_unpack(tui, buf, buf_sz, x, y, w, h) >= 0;
}

export fn arcan_tui_cursor_style(
    tui: ?*tui_context,
    fl: c_int,
    col: ?[*]const u8,
) callconv(.c) c_int {
    const t = tui orelse return 0;

    if (col == null)
        getCursorColorOverride(t).* = false;

    if (fl == 0 and col == null) {
        return getCursor(t).*;
    }

    if (fl != 0)
        getCursor(t).* = fl;

    if (col) |c| {
        const cursor_col = getCursorColor(t);
        cursor_col[0] = c[0];
        cursor_col[1] = c[1];
        cursor_col[2] = c[2];
        getCursorColorOverride(t).* = true;
    }

    return 0;
}

export fn arcan_tui_screencopy(
    src: ?*tui_context,
    dst: ?*tui_context,
    s_x1: usize,
    s_y1: usize,
    s_x2_in: usize,
    s_y2_in: usize,
    d_x1: usize,
    d_y1: usize,
) callconv(.c) void {
    const S = src orelse return;
    const D = dst orelse return;

    if (s_x1 > s_x2_in or s_y1 > s_y2_in)
        return;

    var s_x2 = s_x2_in;
    var s_y2 = s_y2_in;
    const d_x2: usize = @intCast(getCols(D));
    const d_y2: usize = @intCast(getRows(D));
    const src_cols: usize = @intCast(getCols(S));
    const dst_cols: usize = @intCast(getCols(D));

    if (s_x2 > @as(usize, @intCast(getCols(S)))) s_x2 = @intCast(getCols(S));
    if (s_y2 > @as(usize, @intCast(getRows(S)))) s_y2 = @intCast(getRows(S));

    const src_front = getFront(S) orelse return;
    const dst_front = getFront(D) orelse return;

    var cy = s_y1;
    var dy = d_y1;
    while (cy < s_y2 and dy < d_y2) : ({ cy += 1; dy += 1; }) {
        var cx = s_x1;
        var dx = d_x1;
        while (cx < s_x2 and dx < d_x2) : ({ cx += 1; dx += 1; }) {
            dst_front[dy * dst_cols + dx] = src_front[cy * src_cols + cx];
        }
    }

    getDirty(D).* = DIRTY_FULL;
}

export fn arcan_tui_write_border(
    T: ?*tui_context,
    attr_in: tui_screen_attr,
    x1: usize,
    y1: usize,
    x2: usize,
    y2: usize,
    fl: c_int,
) callconv(.c) void {
    const t = T orelse return;
    if (x1 > x2 or y1 > y2) return;

    var attr = attr_in;
    var cattr: tui_screen_attr = undefined;

    if (fl == TUI_BORDER_APPEND)
        attr.aflags = 0;

    // Top-left corner
    attr.aflags = TUI_ATTR_BORDER_TOP | TUI_ATTR_BORDER_LEFT;
    if (y2 - y1 == 0) attr.aflags |= TUI_ATTR_BORDER_DOWN;
    if (x2 - x1 == 0) attr.aflags |= TUI_ATTR_BORDER_RIGHT;

    if (fl == TUI_BORDER_APPEND) {
        cattr = arcan_tui_getxy(t, x1, y1, true).attr;
        cattr.aflags |= attr.aflags;
        arcan_tui_writeattr_at(t, &cattr, x1, y1);
    } else {
        arcan_tui_writeattr_at(t, &attr, x1, y1);
    }

    // Top row
    attr.aflags = TUI_ATTR_BORDER_TOP;
    if (y2 - y1 == 0) attr.aflags |= TUI_ATTR_BORDER_DOWN;

    var i: usize = x1 + 1;
    while (i < x2) : (i += 1) {
        if (fl == TUI_BORDER_APPEND) {
            cattr = arcan_tui_getxy(t, i, y1, true).attr;
            cattr.aflags |= attr.aflags;
            arcan_tui_writeattr_at(t, &cattr, i, y1);
        } else {
            arcan_tui_writeattr_at(t, &attr, i, y1);
        }
    }

    // Top-right corner
    if (x2 - x1 > 0) {
        attr.aflags = TUI_ATTR_BORDER_TOP | TUI_ATTR_BORDER_RIGHT;
        if (y2 - y1 == 0) attr.aflags |= TUI_ATTR_BORDER_DOWN;
        if (fl == TUI_BORDER_APPEND) {
            cattr = arcan_tui_getxy(t, x2, y2, true).attr;
            cattr.aflags |= attr.aflags;
            arcan_tui_writeattr_at(t, &cattr, x2, y1);
        } else {
            arcan_tui_writeattr_at(t, &attr, x2, y1);
        }
    }

    // Left column
    attr.aflags = TUI_ATTR_BORDER_LEFT;
    if (x2 - x1 == 0) attr.aflags |= TUI_ATTR_BORDER_RIGHT;
    i = y1 + 1;
    while (i < y2) : (i += 1) {
        if (fl == TUI_BORDER_APPEND) {
            cattr = arcan_tui_getxy(t, x1, i, true).attr;
            cattr.aflags |= attr.aflags;
            arcan_tui_writeattr_at(t, &cattr, x1, i);
        } else {
            arcan_tui_writeattr_at(t, &attr, x1, i);
        }
    }

    // Right column
    if (x2 - x1 > 0) {
        attr.aflags = TUI_ATTR_BORDER_RIGHT;
        i = y1 + 1;
        while (i < y2) : (i += 1) {
            if (fl == TUI_BORDER_APPEND) {
                cattr = arcan_tui_getxy(t, x2, i, true).attr;
                cattr.aflags |= attr.aflags;
                arcan_tui_writeattr_at(t, &cattr, x2, i);
            } else {
                arcan_tui_writeattr_at(t, &attr, x2, i);
            }
        }
    }

    if (y2 - y1 == 0) return;

    // Bottom-left corner
    attr.aflags = TUI_ATTR_BORDER_DOWN | TUI_ATTR_BORDER_LEFT;
    if (fl == TUI_BORDER_APPEND) {
        cattr = arcan_tui_getxy(t, x1, y2, true).attr;
        cattr.aflags |= attr.aflags;
        arcan_tui_writeattr_at(t, &cattr, x1, y2);
    } else {
        arcan_tui_writeattr_at(t, &attr, x1, y2);
    }

    // Bottom row
    attr.aflags = TUI_ATTR_BORDER_DOWN;
    i = x1 + 1;
    while (i < x2) : (i += 1) {
        if (fl == TUI_BORDER_APPEND) {
            cattr = arcan_tui_getxy(t, i, y2, true).attr;
            cattr.aflags |= attr.aflags;
            arcan_tui_writeattr_at(t, &cattr, i, y2);
        } else {
            arcan_tui_writeattr_at(t, &attr, i, y2);
        }
    }

    // Bottom-right corner
    attr.aflags = TUI_ATTR_BORDER_DOWN | TUI_ATTR_BORDER_RIGHT;
    if (fl == TUI_BORDER_APPEND) {
        cattr = arcan_tui_getxy(t, x2, y2, true).attr;
        cattr.aflags |= attr.aflags;
        arcan_tui_writeattr_at(t, &cattr, x2, y2);
    } else {
        arcan_tui_writeattr_at(t, &attr, x2, y2);
    }
}

export fn arcan_tui_send_key(
    C: ?*tui_context,
    utf8: [*c]const u8,
    lbl: [*c]const u8,
    keysym: u32,
    scancode: u8,
    mods: u16,
    subid: u16,
) callconv(.c) void {
    const t = C orelse return;

    var ev = arcan_event.zeroes();
    ev.setCategory(EVENT_IO);
    const io = ev.asIoMut();
    io.datatype = EVENT_IDATATYPE_TRANSLATED;
    io.devkind = EVENT_IDEVKIND_KEYBOARD;
    io.kind = EVENT_IO_BUTTON;
    io.subid = subid;
    io.input.translated.active = 1;
    io.input.translated.keysym = keysym;
    io.input.translated.scancode = scancode;
    io.input.translated.modifiers = mods;

    if (lbl != null) {
        // Copy label into io.label[16], like snprintf(dst, 16, "%s", lbl)
        const lbl_len = cstrlen(lbl);
        const copy_len = if (lbl_len >= 16) 15 else lbl_len;
        var li: usize = 0;
        while (li < copy_len) : (li += 1) {
            io.label[li] = lbl[li];
        }
        io.label[copy_len] = 0;
    }

    // Copy utf8[4]
    if (utf8 != null) {
        io.input.translated.utf8[0] = utf8[0];
        io.input.translated.utf8[1] = utf8[1];
        io.input.translated.utf8[2] = utf8[2];
        io.input.translated.utf8[3] = utf8[3];
    }

    const vp = getViewportProxy(t);
    if (vp != 0) {
        io.dst = vp;
        if (aconHasAddr(t)) {
            _ = arcan_shmif_enqueue(getAcon(t), &ev);
            ev.asIoMut().input.translated.active = 0;
            _ = arcan_shmif_enqueue(getAcon(t), &ev);
        }
        return;
    }

    // Deliver locally
    tui_input_event(t, @ptrCast(io), lbl);
    ev.asIoMut().input.translated.active = 0;
    tui_input_event(t, @ptrCast(ev.asIoMut()), lbl);
}
