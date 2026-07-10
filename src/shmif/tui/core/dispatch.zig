// Pure Zig port of tui/core/dispatch.c — zero C helpers.
// TUI event dispatch: target events, poll loop, inject.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const arcan = @import("arcan");

// Use @cImport only for TARGET_COMMAND_* enum values and SEGID_* — these
// are C enum integers and must match exactly. We avoid pulling in full
// C type definitions (those come from arcan_zig_types.zig instead).
const c = @import("shmif_types");

// Segment IDs (from arcan_shmif_event.h)
const SEGID_UNKNOWN = c.SEGID_UNKNOWN;
const SEGID_POPUP = c.SEGID_POPUP;
const SEGID_ACCESSIBILITY = c.SEGID_ACCESSIBILITY;
const SEGID_CLIPBOARD = c.SEGID_CLIPBOARD;
const SEGID_CLIPBOARD_PASTE = c.SEGID_CLIPBOARD_PASTE;
const SEGID_TUI = c.SEGID_TUI;
const SEGID_HANDOVER = c.SEGID_HANDOVER;
const SEGID_DEBUG = c.SEGID_DEBUG;

// Target commands (from arcan_shmif_event.h)
const CMD_EXIT = c.TARGET_COMMAND_EXIT;
const CMD_STEPFRAME = c.TARGET_COMMAND_STEPFRAME;
const CMD_STORE = c.TARGET_COMMAND_STORE;
const CMD_RESTORE = c.TARGET_COMMAND_RESTORE;
const CMD_BCHUNK_IN = c.TARGET_COMMAND_BCHUNK_IN;
const CMD_BCHUNK_OUT = c.TARGET_COMMAND_BCHUNK_OUT;
const CMD_RESET = c.TARGET_COMMAND_RESET;
const CMD_PAUSE = c.TARGET_COMMAND_PAUSE;
const CMD_UNPAUSE = c.TARGET_COMMAND_UNPAUSE;
const CMD_SEEKCONTENT = c.TARGET_COMMAND_SEEKCONTENT;
const CMD_NEWSEGMENT = c.TARGET_COMMAND_NEWSEGMENT;
const CMD_REQFAIL = c.TARGET_COMMAND_REQFAIL;
const CMD_GRAPHMODE = c.TARGET_COMMAND_GRAPHMODE;
const CMD_MESSAGE = c.TARGET_COMMAND_MESSAGE;
const CMD_FONTHINT = c.TARGET_COMMAND_FONTHINT;
const CMD_GEOHINT = c.TARGET_COMMAND_GEOHINT;
const CMD_DISPLAYHINT = c.TARGET_COMMAND_DISPLAYHINT;

// SHMIF primary type
const SHMIF_ACCESSIBILITY = c.SHMIF_ACCESSIBILITY;

// TUI window types (from arcan_tuisym.h)
const TUI_WND_TUI: u8 = 23;
const TUI_WND_POPUP: u8 = 16;
const TUI_WND_ACCESSIBILITY: u8 = 19;
const TUI_WND_DEBUG: u8 = 255;
const TUI_WND_HANDOVER: u8 = 26;

// Dirty state flags (from tui_int.h enum dirty_state)
const DIRTY_CURSOR: c_int = 1;
const DIRTY_FULL: c_int = 4;

// TUI color table limits (from arcan_tui.h)
const TUI_COL_LIMIT: usize = 36;
const TUI_COL_TBASE: usize = 16;

// tui_context field offsets
// Verified with compute_offsets on aarch64-linux (same target as build).
// struct tui_context sizeof = 4104.
const OFF_INACTIVE: usize = 84;
const OFF_DEFOCUS: usize = 211;
const OFF_INACT_TIMER: usize = 88;
const OFF_DIRTY: usize = 128;
const OFF_MODIFIERS: usize = 428;
const OFF_CURSOR_PERIOD: usize = 688;
const OFF_CURSOR_OFF: usize = 684;
const OFF_SBOFS: usize = 240; // c_long
const OFF_PPCM: usize = 124;
const OFF_CELL_W: usize = 404;
const OFF_CELL_H: usize = 408;
const OFF_CELL_AUTH: usize = 400;
const OFF_ALPHA: usize = 736;
const OFF_COLORS: usize = 432;
const OFF_ROWS: usize = 228;
const OFF_COLS: usize = 232;
const OFF_FRONT: usize = 32; // *tui_cell pointer
const OFF_TPACK_RECDST: usize = 216; // FILE* (void*)
const OFF_ACON: usize = 2808;
const OFF_CLIP_IN: usize = 3000;
const OFF_CLIP_OUT: usize = 3192;
const OFF_CHILDREN: usize = 760; // [256]*tui_context (pointer array)
const OFF_VIEWPORT_PROXY: usize = 3388;
const OFF_HANDLERS: usize = 3880;
const OFF_HOOKS_RESET: usize = 3840; // hooks.reset fn ptr
const OFF_GOT_PENDING: usize = 3688;
const OFF_PENDING_WND: usize = 3696;
const OFF_PENDING_HANDOVER: usize = 3384;

// arcan_shmif_cont internal layout
const SHMIF_CONT_SIZE: usize = 192;
const SHMIF_OFF_VIDP: usize = 8; // vidp pointer at offset 8
const SHMIF_OFF_W: usize = 80; // uint32_t w
const SHMIF_OFF_H: usize = 88; // uint32_t h

// struct color: rgb[3] + bg[3] + bgset(bool=1 byte) = 7 bytes per entry
const COLOR_SIZE: usize = 7;
const COLOR_OFF_RGB: usize = 0;
const COLOR_OFF_BG: usize = 3;
const COLOR_OFF_BGSET: usize = 6;

// tui_cell size = 28 bytes; ch (u32) at offset 8 within tui_cell
// (after tui_screen_attr: fc[3]+bc[3]+aflags(u16)+custom_id(u8) = 9 bytes, padded to 8)
const TUI_CELL_SIZE: usize = 28;
const TUI_CELL_CH_OFF: usize = 8;

// Number of children slots
const CHILDREN_COUNT: usize = 256;

// arcan_shmif_cont value-return wrapper
// arcan_shmif_cont is opaque in arcan_zig_types.zig (contains _Atomic fields).
// To receive it by value from arcan_shmif_acquire, we use a byte-compatible
// extern struct of the correct size and alignment.
const ShmifContVal = extern struct {
    data: [SHMIF_CONT_SIZE]u8 align(8),
};

comptime {
    if (@sizeOf(ShmifContVal) != SHMIF_CONT_SIZE)
        @compileError("ShmifContVal size mismatch");
}

// shmif_resize_ext struct
const shmif_resize_ext = extern struct {
    meta: u32 = 0,
    abuf_sz: usize = 0,
    abuf_cnt: isize = -1,
    samplerate: isize = 0,
    vbuf_cnt: isize = -1,
    rows: usize,
    cols: usize,
    nops: usize = 0,
    op_fm: usize = 0,
};

// External function declarations

// Returns arcan_shmif_cont by value (192 bytes on this platform).
// key is const char* (may be NULL — use null passed as [*c] type).
extern fn arcan_shmif_acquire(
    parent: ?*arcan.arcan_shmif_cont,
    key: [*c]const u8,
    segid: c_int,
    flags: c_int,
) callconv(.c) ShmifContVal;

extern fn arcan_shmif_defimpl(
    cont: ?*arcan.arcan_shmif_cont,
    segid: c_int,
    priv: ?*anyopaque,
) callconv(.c) void;

extern fn arcan_shmif_dupfd(fd: c_int, dstnum: c_int, nonblocking: bool) callconv(.c) c_int;

extern fn arcan_shmif_resize_ext(
    ctx: ?*arcan.arcan_shmif_cont,
    width: c_uint,
    height: c_uint,
    ext: shmif_resize_ext,
) callconv(.c) bool;

extern fn arcan_shmif_setprimary(segtype: c_int, ctx: ?*arcan.arcan_shmif_cont) callconv(.c) void;
extern fn arcan_shmif_poll(ctx: ?*arcan.arcan_shmif_cont, ev: *arcan.arcan_event) callconv(.c) c_int;
extern fn arcan_shmif_drop(ctx: ?*arcan.arcan_shmif_cont) callconv(.c) void;

// TUI internal functions (provided by other TUI C/Zig compilation units)
extern fn tui_screen_resized(tui: ?*arcan.tui_context) callconv(.c) void;
extern fn tui_fontmgmt_fonthint(tui: ?*arcan.tui_context, ev: *const arcan.arcan_tgtevent) callconv(.c) void;
extern fn tui_fontmgmt_invalidate(tui: ?*arcan.tui_context) callconv(.c) void;
extern fn tui_queue_requests(tui: ?*arcan.tui_context, clipboard: bool, ident: bool) callconv(.c) void;
extern fn tui_copywnd(src: ?*arcan.tui_context, conn: ?*arcan.arcan_shmif_cont) callconv(.c) void;
extern fn tui_input_event(tui: ?*arcan.tui_context, ioev: ?*anyopaque, label: [*c]const u8) callconv(.c) void;
extern fn arcan_tui_ucs4utf8(cp: u32, dst: [*c]u8) callconv(.c) usize;

// libc
extern fn malloc(size: usize) callconv(.c) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) callconv(.c) void;
extern fn fwrite(ptr: ?*const anyopaque, size: usize, count: usize, stream: ?*anyopaque) callconv(.c) usize;
extern fn fclose(stream: ?*anyopaque) callconv(.c) c_int;
extern fn fdopen(fd: c_int, mode: [*c]const u8) callconv(.c) ?*anyopaque;
extern fn close(fd: c_int) callconv(.c) c_int;
extern fn fputs(s: [*c]const u8, stream: ?*anyopaque) callconv(.c) c_int;
extern fn strcmp(a: [*c]const u8, b: [*c]const u8) callconv(.c) c_int;
extern fn memcpy(dst: ?*anyopaque, src: ?*const anyopaque, n: usize) callconv(.c) ?*anyopaque;
extern fn fabs(x: f64) callconv(.c) f64;
extern fn ceilf(x: f32) callconv(.c) f32;

// pthreads — pthread_t and pthread_attr_t are opaque; use fixed-size buffers.
// On linux/aarch64: sizeof(pthread_t)=8, sizeof(pthread_attr_t)=64
extern fn pthread_create(
    thread: *usize,
    attr: ?*const anyopaque,
    start: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    arg: ?*anyopaque,
) callconv(.c) c_int;
extern fn pthread_attr_init(attr: *anyopaque) callconv(.c) c_int;
extern fn pthread_attr_setdetachstate(attr: *anyopaque, state: c_int) callconv(.c) c_int;

const PTHREAD_CREATE_DETACHED: c_int = 1;

// Raw field accessors for tui_context (opaque type)

inline fn tuiPtr(tui: *arcan.tui_context, comptime T: type, offset: usize) *T {
    const base: [*]u8 = @ptrCast(tui);
    return @ptrCast(@alignCast(base + offset));
}

inline fn tuiPtrConst(tui: *const arcan.tui_context, comptime T: type, offset: usize) *const T {
    const base: [*]const u8 = @ptrCast(tui);
    return @ptrCast(@alignCast(base + offset));
}

fn getInactive(tui: *arcan.tui_context) *bool {
    return tuiPtr(tui, bool, OFF_INACTIVE);
}

fn getDefocus(tui: *arcan.tui_context) *bool {
    return tuiPtr(tui, bool, OFF_DEFOCUS);
}

fn getInactTimer(tui: *arcan.tui_context) *c_int {
    return tuiPtr(tui, c_int, OFF_INACT_TIMER);
}

fn getDirty(tui: *arcan.tui_context) *c_int {
    return tuiPtr(tui, c_int, OFF_DIRTY);
}

fn getModifiers(tui: *arcan.tui_context) *c_int {
    return tuiPtr(tui, c_int, OFF_MODIFIERS);
}

fn getCursorPeriod(tui: *const arcan.tui_context) c_int {
    return tuiPtrConst(tui, c_int, OFF_CURSOR_PERIOD).*;
}

fn getCursorOff(tui: *arcan.tui_context) *bool {
    return tuiPtr(tui, bool, OFF_CURSOR_OFF);
}

fn getSbofs(tui: *const arcan.tui_context) c_long {
    return tuiPtrConst(tui, c_long, OFF_SBOFS).*;
}

fn setSbofs(tui: *arcan.tui_context, val: c_long) void {
    tuiPtr(tui, c_long, OFF_SBOFS).* = val;
}

fn getPpcm(tui: *arcan.tui_context) *f32 {
    return tuiPtr(tui, f32, OFF_PPCM);
}

fn getCellW(tui: *arcan.tui_context) *c_int {
    return tuiPtr(tui, c_int, OFF_CELL_W);
}

fn getCellH(tui: *arcan.tui_context) *c_int {
    return tuiPtr(tui, c_int, OFF_CELL_H);
}

fn getCellAuth(tui: *arcan.tui_context) *bool {
    return tuiPtr(tui, bool, OFF_CELL_AUTH);
}

fn getAlpha(tui: *arcan.tui_context) *u8 {
    return tuiPtr(tui, u8, OFF_ALPHA);
}

fn getRows(tui: *const arcan.tui_context) c_int {
    return tuiPtrConst(tui, c_int, OFF_ROWS).*;
}

fn getCols(tui: *const arcan.tui_context) c_int {
    return tuiPtrConst(tui, c_int, OFF_COLS).*;
}

// front is *tui_cell — stored as a pointer value at OFF_FRONT
fn getFrontPtr(tui: *const arcan.tui_context) usize {
    return tuiPtrConst(tui, usize, OFF_FRONT).*;
}

// tpack_recdst is FILE* — stored as a nullable pointer at OFF_TPACK_RECDST
fn getTpackRecdst(tui: *arcan.tui_context) **anyopaque {
    // We treat FILE* as *anyopaque; the slot holds a nullable pointer.
    // Using **anyopaque so we can read/write the slot.
    return tuiPtr(tui, *anyopaque, OFF_TPACK_RECDST);
}

fn getTpackRecdstNullable(tui: *arcan.tui_context) *?*anyopaque {
    return tuiPtr(tui, ?*anyopaque, OFF_TPACK_RECDST);
}

fn getAcon(tui: *arcan.tui_context) *arcan.arcan_shmif_cont {
    return @ptrCast(tuiPtr(tui, u8, OFF_ACON));
}

fn getAconW(tui: *const arcan.tui_context) u32 {
    // arcan_shmif_cont.w is uint32_t at offset SHMIF_OFF_W within cont
    const base: [*]const u8 = @ptrCast(tuiPtrConst(tui, u8, OFF_ACON));
    return @as(*const u32, @ptrCast(@alignCast(base + SHMIF_OFF_W))).*;
}

fn getAconH(tui: *const arcan.tui_context) u32 {
    const base: [*]const u8 = @ptrCast(tuiPtrConst(tui, u8, OFF_ACON));
    return @as(*const u32, @ptrCast(@alignCast(base + SHMIF_OFF_H))).*;
}

fn getClipIn(tui: *arcan.tui_context) *arcan.arcan_shmif_cont {
    return @ptrCast(tuiPtr(tui, u8, OFF_CLIP_IN));
}

fn clipInHasVidp(tui: *const arcan.tui_context) bool {
    const base: [*]const u8 = @ptrCast(tuiPtrConst(tui, u8, OFF_CLIP_IN));
    const vidp: *const ?*anyopaque = @ptrCast(@alignCast(base + SHMIF_OFF_VIDP));
    return vidp.* != null;
}

fn getClipOut(tui: *arcan.tui_context) *arcan.arcan_shmif_cont {
    return @ptrCast(tuiPtr(tui, u8, OFF_CLIP_OUT));
}

fn clipOutHasVidp(tui: *const arcan.tui_context) bool {
    const base: [*]const u8 = @ptrCast(tuiPtrConst(tui, u8, OFF_CLIP_OUT));
    const vidp: *const ?*anyopaque = @ptrCast(@alignCast(base + SHMIF_OFF_VIDP));
    return vidp.* != null;
}

// children[i] is a pointer-sized slot containing ?*tui_context
fn getChild(tui: *arcan.tui_context, i: usize) ?*arcan.tui_context {
    const base: [*]u8 = @ptrCast(tui);
    const slot: *const ?*arcan.tui_context =
        @ptrCast(@alignCast(base + OFF_CHILDREN + i * @sizeOf(*anyopaque)));
    return slot.*;
}

fn getViewportProxy(tui: *const arcan.tui_context) u32 {
    return tuiPtrConst(tui, u32, OFF_VIEWPORT_PROXY).*;
}

fn getHandlers(tui: *arcan.tui_context) *arcan.tui_cbcfg {
    return tuiPtr(tui, arcan.tui_cbcfg, OFF_HANDLERS);
}

// hooks.reset fn ptr type: void(*)(struct tui_context*)
const HooksResetFn = *const fn (*arcan.tui_context) callconv(.c) void;

fn getHooksReset(tui: *arcan.tui_context) ?HooksResetFn {
    return tuiPtr(tui, ?HooksResetFn, OFF_HOOKS_RESET).*;
}

fn getGotPending(tui: *arcan.tui_context) *bool {
    return tuiPtr(tui, bool, OFF_GOT_PENDING);
}

fn getPendingWnd(tui: *arcan.tui_context) *arcan.arcan_event {
    return tuiPtr(tui, arcan.arcan_event, OFF_PENDING_WND);
}

fn getPendingHandover(tui: *arcan.tui_context) *u32 {
    return tuiPtr(tui, u32, OFF_PENDING_HANDOVER);
}

// colors[slot].rgb / .bg / .bgset
// struct color: { uint8_t rgb[3]; uint8_t bg[3]; bool bgset; } = 7 bytes
fn getColorRgb(tui: *arcan.tui_context, slot: usize) *[3]u8 {
    const base: [*]u8 = @ptrCast(tui);
    return @ptrCast(base + OFF_COLORS + slot * COLOR_SIZE + COLOR_OFF_RGB);
}

fn getColorBg(tui: *arcan.tui_context, slot: usize) *[3]u8 {
    const base: [*]u8 = @ptrCast(tui);
    return @ptrCast(base + OFF_COLORS + slot * COLOR_SIZE + COLOR_OFF_BG);
}

fn getColorBgset(tui: *arcan.tui_context, slot: usize) *bool {
    const base: [*]u8 = @ptrCast(tui);
    return @ptrCast(base + OFF_COLORS + slot * COLOR_SIZE + COLOR_OFF_BGSET);
}

// Thread data for async screen dump

const DumpThreadData = struct {
    fpek: ?*anyopaque,
    outb: ?[*]u8,
    sz: usize,
};

fn copy_thread(in_arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const din: *DumpThreadData = @ptrCast(@alignCast(in_arg orelse return null));
    _ = fwrite(din.outb, din.sz, 1, din.fpek);
    _ = fclose(din.fpek);
    free(din.outb);
    free(din);
    return null;
}

// ev_to_col: write float ioevs[1,2,3] as u8 RGB into dst

fn ev_to_col(ev: *const arcan.arcan_tgtevent, dst: *[3]u8) void {
    dst[0] = @intFromFloat(ev.ioevs[1].fv);
    dst[1] = @intFromFloat(ev.ioevs[2].fv);
    dst[2] = @intFromFloat(ev.ioevs[3].fv);
}

// dump_to_fd: dump screen text content to an fd

fn dump_to_fd(tui: *arcan.tui_context, fd: c_int) void {
    if (fd == -1) return;

    const fpek = fdopen(fd, "w") orelse {
        _ = close(fd);
        return;
    };

    const rows: usize = @intCast(getRows(tui));
    const cols: usize = @intCast(getCols(tui));

    // Worst case: 4 UTF-8 bytes per cell + 1 newline per row
    const buf_sz = rows * cols * 4 + rows;
    const raw_buf = malloc(buf_sz) orelse {
        _ = fclose(fpek);
        return;
    };
    const outb: [*]u8 = @ptrCast(raw_buf);

    var ofs: usize = 0;
    const front_addr = getFrontPtr(tui);

    var row: usize = 0;
    while (row < rows) : (row += 1) {
        var col: usize = 0;
        while (col < cols) : (col += 1) {
            const cell_addr = front_addr + (row * cols + col) * TUI_CELL_SIZE;
            const ch: u32 = @as(*const u32, @ptrFromInt(cell_addr + TUI_CELL_CH_OFF)).*;
            var out: [4]u8 = .{ 0, 0, 0, 0 };
            const nb = arcan_tui_ucs4utf8(ch, &out);
            if (out[0] != 0) {
                @memcpy(outb[ofs .. ofs + nb], out[0..nb]);
                ofs += nb;
            } else {
                outb[ofs] = ' ';
                ofs += 1;
            }
        }
        outb[ofs] = '\n';
        ofs += 1;
    }

    // Try async write via detached thread
    const data_raw = malloc(@sizeOf(DumpThreadData));
    if (data_raw) |data_void| {
        const data: *DumpThreadData = @ptrCast(@alignCast(data_void));
        data.* = .{ .outb = outb, .fpek = fpek, .sz = ofs };

        var pth: usize = undefined;
        // pthread_attr_t: 64 bytes on linux/aarch64
        var pthattr: [64]u8 align(8) = std.mem.zeroes([64]u8);
        _ = pthread_attr_init(&pthattr);
        _ = pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);

        if (pthread_create(&pth, &pthattr, copy_thread, data) == 0) {
            return; // thread owns outb / fpek / data
        }
        // Thread creation failed — free data, fall through to sync write
        free(data);
    }

    // Synchronous fallback
    _ = fwrite(outb, ofs, 1, fpek);
    _ = fclose(fpek);
    free(outb);
}

// segid_to_tuiid

fn segid_to_tuiid(segid: c_int) c_int {
    if (segid == SEGID_TUI) return TUI_WND_TUI;
    if (segid == SEGID_POPUP) return TUI_WND_POPUP;
    if (segid == SEGID_DEBUG) return TUI_WND_DEBUG;
    if (segid == SEGID_HANDOVER) return TUI_WND_HANDOVER;
    return SEGID_UNKNOWN;
}

// tick_cursor

fn tick_cursor(tui: *arcan.tui_context) void {
    if (getCursorPeriod(tui) == 0)
        return;

    if (!getDefocus(tui).*) {
        getInactTimer(tui).* += 1;
        if (getSbofs(tui) != 0) {
            getCursorOff(tui).* = true;
        } else {
            const t = getInactTimer(tui).*;
            getCursorOff(tui).* = if (t > 1) !getCursorOff(tui).* else false;
        }
    }

    getDirty(tui).* |= DIRTY_CURSOR;
}

// display_hint

fn display_hint(tui: *arcan.tui_context, ev: *const arcan.arcan_tgtevent) void {
    // Proxy event for a child window?
    if (ev.ioevs[7].uiv != 0) {
        var i: usize = 0;
        while (i < CHILDREN_COUNT) : (i += 1) {
            const tgt = getChild(tui, i) orelse continue;
            if (getViewportProxy(tgt) != ev.ioevs[7].uiv)
                continue;

            const w: usize = @intCast(ev.ioevs[0].uiv);
            const h: usize = @intCast(ev.ioevs[1].uiv);
            const cell_w: c_int = getCellW(tui).*;
            const cell_h: c_int = getCellH(tui).*;

            var cols: usize = 0;
            var rows: usize = 0;

            if (w != 0 and cell_w != 0)
                cols = @intFromFloat(ceilf(@as(f32, @floatFromInt(w)) /
                    @as(f32, @floatFromInt(cell_w))));

            if (h != 0 and cell_h != 0)
                rows = @intFromFloat(ceilf(@as(f32, @floatFromInt(h)) /
                    @as(f32, @floatFromInt(cell_h))));

            getDefocus(tgt).* = (ev.ioevs[2].iv & 4) != 0;
            getInactive(tgt).* = (ev.ioevs[2].iv & 32) != 0;

            const handlers = getHandlers(tgt);
            if (handlers.resized) |resized_fn| {
                if (w != 0 and h != 0)
                    resized_fn(@ptrCast(tgt), w, h, cols, rows, handlers.tag);
            }

            if (handlers.visibility) |vis_fn| {
                vis_fn(@ptrCast(tgt),
                    !getInactive(tgt).*,
                    getDefocus(tgt).*,
                    handlers.tag);
            }
            break;
        }
        return;
    }

    // Regular display hint for this context
    const acon_w: i32 = @intCast(getAconW(tui));
    const acon_h: i32 = @intCast(getAconH(tui));
    const w: i32 = if (ev.ioevs[0].iv != 0) ev.ioevs[0].iv else acon_w;
    const h: i32 = if (ev.ioevs[1].iv != 0) ev.ioevs[1].iv else acon_h;

    // Server-side cell dimension hint
    const hcw = ev.ioevs[5].iv;
    const hch = ev.ioevs[6].iv;
    if (hcw != 0) getCellW(tui).* = hcw;
    if (hch != 0) getCellH(tui).* = hch;
    if (hcw != 0 and hch != 0) getCellAuth(tui).* = true;

    const cell_w: i32 = getCellW(tui).*;
    const cell_h: i32 = getCellH(tui).*;

    if (@abs(w - acon_w) > 0 or @abs(h - acon_h) > 0) {
        // Realign against grid and clamp to minimum 1
        var rows: usize = @intCast(@divTrunc(h, cell_h));
        var cols: usize = @intCast(@divTrunc(w, cell_w));
        if (rows == 0) rows = 1;
        if (cols == 0) cols = 1;

        // Communicate cell dimensions back + resolved size
        if (arcan_shmif_resize_ext(
            getAcon(tui),
            @intCast(cols * @as(usize, @intCast(cell_w))),
            @intCast(rows * @as(usize, @intCast(cell_h))),
            .{ .rows = rows, .cols = cols },
        )) {
            tui_screen_resized(@ptrCast(tui));
        }
    }

    // Visibility / focus state changes
    var update = false;

    // inactive bit is bit 1 of ioevs[2].iv
    const inactive_flag: i32 = ev.ioevs[2].iv & 2;
    const cur_inactive: i32 = if (getInactive(tui).*) 2 else 0;
    if ((inactive_flag ^ cur_inactive) != 0) {
        getInactive(tui).* = inactive_flag != 0;
        getDirty(tui).* |= DIRTY_CURSOR;
        update = true;
    }

    // defocus bit is bit 2 of ioevs[2].iv
    const defocus_flag: i32 = ev.ioevs[2].iv & 4;
    const cur_defocus: i32 = if (getDefocus(tui).*) 4 else 0;
    if ((defocus_flag ^ cur_defocus) != 0) {
        getDefocus(tui).* = defocus_flag != 0;
        getDirty(tui).* |= DIRTY_CURSOR;
        getModifiers(tui).* = 0;
        update = true;
    }

    if (update) {
        const handlers = getHandlers(tui);
        if (handlers.visibility) |vis_fn| {
            vis_fn(@ptrCast(tui),
                !getInactive(tui).*,
                !getDefocus(tui).*,
                handlers.tag);
        }
    }

    // Screen density change → font invalidation
    const new_ppcm = ev.ioevs[4].fv;
    if (new_ppcm > 0.0 and fabs(@floatCast(new_ppcm - getPpcm(tui).*)) > 0.01) {
        getPpcm(tui).* = new_ppcm;
        tui_fontmgmt_invalidate(@ptrCast(tui));
    }
}

// target_event

fn target_event(tui: *arcan.tui_context, aev: *arcan.arcan_event) void {
    {
        const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
        const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
        const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
        if (sc_open("/tmp/clip_xbridge.log", "a")) |f| {
            _ = sc_fprintf(f, "term: target_event kind=%d\n", @as(c_int, aev.asTgt().kind));
            _ = sc_fclose(f);
        }
    }
    const ev = aev.asTgt();
    const kind = ev.kind;

    if (kind == CMD_GRAPHMODE) {
        // GRAPHMODE: buffered color table update
        const bg = (ev.ioevs[0].iv & 256) > 0;
        const slot_raw = ev.ioevs[0].iv & (~@as(i32, 256));
        const slot: usize = @intCast(slot_raw);

        // Always mark color[1].bgset and dirty
        getColorBgset(tui, 1).* = true;
        getColorBg(tui, 1)[0] = 255;
        getDirty(tui).* = DIRTY_FULL;

        if (slot == 0) {
            // Commit: notify recolor handler
            const handlers = getHandlers(tui);
            if (handlers.recolor) |recolor_fn|
                recolor_fn(@ptrCast(tui), handlers.tag);
            return;
        }

        if (slot == 1) {
            // Special alpha slot
            getAlpha(tui).* = @intFromFloat(ev.ioevs[1].fv);
            return;
        }

        if (slot >= TUI_COL_LIMIT) return;

        if (slot >= TUI_COL_TBASE) {
            // Reserved slots: fg = bg
            ev_to_col(ev, getColorRgb(tui, slot));
            ev_to_col(ev, getColorBg(tui, slot));
        } else {
            if (bg)
                ev_to_col(ev, getColorBg(tui, slot))
            else
                ev_to_col(ev, getColorRgb(tui, slot));
        }
    } else if (kind == CMD_PAUSE) {
        const handlers = getHandlers(tui);
        if (handlers.exec_state) |fn_|
            fn_(@ptrCast(tui), 1, handlers.tag);
    } else if (kind == CMD_UNPAUSE) {
        const handlers = getHandlers(tui);
        if (handlers.exec_state) |fn_|
            fn_(@ptrCast(tui), 0, handlers.tag);
    } else if (kind == CMD_RESET) {
        getModifiers(tui).* = 0;
        if (getHooksReset(tui)) |reset_fn|
            reset_fn(tui);
        setSbofs(tui, 0);

        const iv = ev.ioevs[0].iv;
        if (iv == 0 or iv == 1) {
            const handlers = getHandlers(tui);
            if (handlers.reset) |fn_|
                fn_(@ptrCast(tui), iv, handlers.tag);
        } else if (iv == 2 or iv == 3) {
            const handlers = getHandlers(tui);
            if (handlers.reset) |fn_|
                fn_(@ptrCast(tui), iv, handlers.tag);
            arcan_shmif_drop(getClipIn(tui));
            arcan_shmif_drop(getClipOut(tui));
            tui_queue_requests(@ptrCast(tui), true, true);
        }
        getDirty(tui).* = DIRTY_FULL;
    } else if (kind == CMD_BCHUNK_IN) {
        if (strcmp(&ev.message.message, "stdin") == 0) {
            _ = arcan_shmif_dupfd(ev.ioevs[0].iv, std.posix.STDIN_FILENO, false);
            return;
        }
        const handlers = getHandlers(tui);
        if (handlers.bchunk) |bchunk_fn| {
            const fd = arcan_shmif_dupfd(ev.ioevs[0].iv, -1, false);
            if (fd != -1) {
                const sz = bchunk_size(ev);
                bchunk_fn(@ptrCast(tui), true, sz, fd, &ev.message.message, handlers.tag);
            }
        }
    } else if (kind == CMD_BCHUNK_OUT) {
        if (strcmp(&ev.message.message, "tuiraw") == 0) {
            dump_to_fd(tui, arcan_shmif_dupfd(ev.ioevs[0].iv, -1, false));
            return;
        }
        if (strcmp(&ev.message.message, "tuiani") == 0) {
            const recdst = getTpackRecdstNullable(tui);
            if (recdst.*) |old_fp| _ = fclose(old_fp);
            const fd = arcan_shmif_dupfd(ev.ioevs[0].iv, -1, false);
            recdst.* = fdopen(fd, "w");
            if (recdst.*) |fp| _ = fputs("tpk1\n", fp);
            return;
        }
        if (strcmp(&ev.message.message, "stdout") == 0) {
            _ = arcan_shmif_dupfd(ev.ioevs[0].iv, std.posix.STDOUT_FILENO, false);
            return;
        }
        if (strcmp(&ev.message.message, "stderr") == 0) {
            _ = arcan_shmif_dupfd(ev.ioevs[0].iv, std.posix.STDERR_FILENO, false);
            return;
        }
        const handlers = getHandlers(tui);
        if (handlers.bchunk) |bchunk_fn| {
            const fd = arcan_shmif_dupfd(ev.ioevs[0].iv, -1, false);
            if (fd != -1) {
                const sz = bchunk_size(ev);
                bchunk_fn(@ptrCast(tui), false, sz, fd, &ev.message.message, handlers.tag);
            }
        }
    } else if (kind == CMD_SEEKCONTENT) {
        const handlers = getHandlers(tui);
        if (ev.ioevs[0].iv != 0) {
            if (handlers.seek_relative) |fn_|
                fn_(@ptrCast(tui), @intCast(ev.ioevs[1].iv), @intCast(ev.ioevs[2].iv), handlers.tag);
        } else {
            if (handlers.seek_absolute) |fn_| {
                const v = ev.ioevs[1].fv;
                if (v >= 0.0 and v <= 1.0)
                    fn_(@ptrCast(tui), v, handlers.tag);
            }
        }
    } else if (kind == CMD_FONTHINT) {
        tui_fontmgmt_fonthint(@ptrCast(tui), ev);
    } else if (kind == CMD_DISPLAYHINT) {
        display_hint(tui, ev);
    } else if (kind == CMD_REQFAIL) {
        // High bit set → external request failure, forward to subwindow handler
        if ((@as(u32, @bitCast(ev.ioevs[0].iv)) & (@as(u32, 1) << 31)) != 0) {
            const handlers = getHandlers(tui);
            if (handlers.subwindow) |sw_fn| {
                const id = @as(u32, @bitCast(ev.ioevs[0].iv)) & 0xffff;
                _ = sw_fn(@ptrCast(tui), null, id, TUI_WND_TUI, handlers.tag);
            }
        }
    } else if (kind == CMD_NEWSEGMENT) {
        handle_newsegment(tui, aev, ev);
    } else if (kind == CMD_STEPFRAME) {
        // Magic tick value from the server
        if (ev.ioevs[1].uiv == 0xabcdef00) {
            tick_cursor(tui);
            const handlers = getHandlers(tui);
            if (handlers.tick) |fn_|
                fn_(@ptrCast(tui), handlers.tag);
        }
    } else if (kind == CMD_GEOHINT) {
        const handlers = getHandlers(tui);
        if (handlers.geohint) |fn_| {
            fn_(@ptrCast(tui),
                ev.ioevs[0].fv,
                ev.ioevs[1].fv,
                ev.ioevs[2].fv,
                // cv is [4]u8, cast to [*c]const u8 (null-terminated char*)
                @ptrCast(&ev.ioevs[3].cv),
                @ptrCast(&ev.ioevs[4].cv),
                handlers.tag);
        }
    } else if (kind == CMD_STORE or kind == CMD_RESTORE) {
        const handlers = getHandlers(tui);
        if (handlers.state) |fn_|
            fn_(@ptrCast(tui), kind == CMD_RESTORE, ev.ioevs[0].iv, handlers.tag);
    } else if (kind == CMD_MESSAGE) {
        const handlers = getHandlers(tui);
        {
            const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
            const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
            const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
            if (sc_open("/tmp/clip_xbridge.log", "a")) |f| {
                _ = sc_fprintf(f, "dispatch: CMD_MESSAGE main_seg msg_cb=%s first='%c%c%c%c'\n",
                    if (handlers.message == null) @as([*c]const u8, "nil") else @as([*c]const u8, "set"),
                    @as(c_int, ev.message.message[0]),
                    @as(c_int, ev.message.message[1]),
                    @as(c_int, ev.message.message[2]),
                    @as(c_int, ev.message.message[3]));
                _ = sc_fclose(f);
            }
        }
        if (handlers.message) |fn_|
            fn_(@ptrCast(tui), &ev.message.bmessage, ev.ioevs[0].iv != 0, handlers.tag);
    } else if (kind == CMD_EXIT) {
        const handlers = getHandlers(tui);
        if (handlers.exec_state) |fn_|
            fn_(@ptrCast(tui), 2, handlers.tag);
        arcan_shmif_drop(getAcon(tui));
    }
    // All other commands: ignore (C default: break)
}

// Compute the bchunk size from ioevs[1] | (ioevs[2] << 31)
// This matches the C: ev->ioevs[1].iv | (ev->ioevs[2].iv << 31)
fn bchunk_size(ev: *const arcan.arcan_tgtevent) u64 {
    const lo: u64 = @intCast(@as(u32, @bitCast(ev.ioevs[1].iv)));
    const hi: u64 = @intCast(@as(u32, @bitCast(ev.ioevs[2].iv)));
    return lo | (hi << 31);
}

// handle_newsegment

fn handle_newsegment(tui: *arcan.tui_context, aev: *arcan.arcan_event, ev: *const arcan.arcan_tgtevent) void {
    const segtype = ev.ioevs[2].iv;
    {
        const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
        const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
        const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
        if (sc_open("/tmp/clip_xbridge.log", "a")) |f| {
            _ = sc_fprintf(f, "term: handle_newsegment segtype=%d ioevs[1]=%d ioevs[3].uiv=0x%x\n",
                @as(c_int, segtype), @as(c_int, ev.ioevs[1].iv), @as(c_uint, ev.ioevs[3].uiv));
            _ = sc_fclose(f);
        }
    }

    // Filter: only accept known segment types
    if (segtype != SEGID_TUI and
        segtype != SEGID_POPUP and
        segtype != SEGID_HANDOVER and
        segtype != SEGID_DEBUG and
        segtype != SEGID_ACCESSIBILITY and
        segtype != SEGID_CLIPBOARD_PASTE and
        segtype != SEGID_CLIPBOARD)
    {
        return; // C: LOG + return
    }

    // Clipboard paste segment
    if (segtype == SEGID_CLIPBOARD_PASTE) {
        if (!clipInHasVidp(tui)) {
            const result = arcan_shmif_acquire(getAcon(tui), null, SEGID_CLIPBOARD_PASTE, 0);
            _ = memcpy(tuiPtr(tui, u8, OFF_CLIP_IN), &result.data, SHMIF_CONT_SIZE);
        }
        return;
    }

    // The requested clipboard (copy-out) has arrived
    if (ev.ioevs[1].iv == 0 and ev.ioevs[3].uiv == 0xfeedface) {
        if (!clipOutHasVidp(tui)) {
            const result = arcan_shmif_acquire(getAcon(tui), null, SEGID_CLIPBOARD, 0);
            _ = memcpy(tuiPtr(tui, u8, OFF_CLIP_OUT), &result.data, SHMIF_CONT_SIZE);
        }
        return;
    }

    // COPY_WINDOW: heap-allocate a new shmif_cont and hand to tui_copywnd
    if (segtype == SEGID_TUI and ev.ioevs[3].uiv == 0x2c0c0) {
        const buf = malloc(SHMIF_CONT_SIZE) orelse return;
        const buf_bytes: [*]u8 = @ptrCast(buf);
        @memset(buf_bytes[0..SHMIF_CONT_SIZE], 0);
        const result = arcan_shmif_acquire(getAcon(tui), null, SEGID_TUI, 0);
        _ = memcpy(buf, &result.data, SHMIF_CONT_SIZE);
        tui_copywnd(@ptrCast(tui), @ptrCast(buf));
        return;
    }

    // General subwindow request
    const can_push = (segtype == SEGID_DEBUG) or (segtype == SEGID_ACCESSIBILITY);
    const user_defined = (@as(u32, @bitCast(ev.ioevs[3].iv)) & (@as(u32, 1) << 31)) != 0;

    const handlers = getHandlers(tui);
    if ((can_push or user_defined) and handlers.subwindow != null) {
        const id: u32 = @as(u32, @bitCast(ev.ioevs[3].iv)) & 0xffff;
        const kind = segid_to_tuiid(segtype);

        if (segtype == SEGID_HANDOVER) {
            getGotPending(tui).* = true;
            getPendingHandover(tui).* = ev.ioevs[4].uiv;
            getPendingWnd(tui).* = aev.*;

            if (handlers.subwindow) |sw_fn| {
                // Pass (void*)(uintptr_t)-1 as the 'acon' arg to signal handover
                const sentinel: *arcan.arcan_shmif_cont =
                    @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
                _ = sw_fn(@ptrCast(tui), sentinel, id, @intCast(kind), handlers.tag);
            }

            getPendingHandover(tui).* = 0;
            getGotPending(tui).* = false;

            if (kind == @as(c_int, TUI_WND_ACCESSIBILITY)) {
                arcan_shmif_setprimary(SHMIF_ACCESSIBILITY, getAcon(tui));
            }
            return;
        }

        // Acquire on stack, pass pointer to subwindow handler
        var acon_buf: [SHMIF_CONT_SIZE]u8 align(8) = std.mem.zeroes([SHMIF_CONT_SIZE]u8);
        const result = arcan_shmif_acquire(getAcon(tui), null, segtype, 0);
        @memcpy(&acon_buf, &result.data);
        const acon_ptr: *arcan.arcan_shmif_cont = @ptrCast(&acon_buf);

        if (handlers.subwindow) |sw_fn| {
            if (!sw_fn(@ptrCast(tui), acon_ptr, id, @intCast(kind), handlers.tag)) {
                // Client ignored the subwindow — apply default impl
                arcan_shmif_defimpl(acon_ptr, segtype, @ptrCast(tui));
            }
        }
    }
}

// Exported API

/// Process an event as if it originated from the display server connection.
export fn tui_event_inject(tui: ?*arcan.tui_context, ev: ?*arcan.arcan_event) void {
    if (is_freestanding) return;
    const t = tui orelse return;
    const aev = ev orelse return;

    switch (aev.getCategory()) {
        arcan.EVENT_IO => {
            const ioev = aev.asIo();
            tui_input_event(@ptrCast(t), @ptrCast(@constCast(ioev)), &ioev.label);
        },
        arcan.EVENT_TARGET => {
            target_event(t, aev);
        },
        else => {},
    }
}

/// Poll the incoming event queue on the tui segment and dispatch all events.
export fn tui_event_poll(tui: ?*arcan.tui_context) void {
    if (is_freestanding) return;
    const t = tui orelse return;
    var ev = arcan.arcan_event.zeroes();

    while (true) {
        const pv = arcan_shmif_poll(getAcon(t), &ev);
        if (pv <= 0) {
            if (pv == -1)
                arcan_shmif_drop(getAcon(t));
            return;
        }

        switch (ev.getCategory()) {
            arcan.EVENT_IO => {
                const ioev = ev.asIo();
                tui_input_event(@ptrCast(t), @ptrCast(@constCast(ioev)), &ioev.label);
            },
            arcan.EVENT_TARGET => {
                target_event(t, &ev);
            },
            else => {},
        }
    }
}
