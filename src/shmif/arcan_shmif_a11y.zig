// Zig reimplementation of arcan_shmif_a11y.c
// Drop-in C-ABI-compatible replacement for accessibility support.
//
// Exports: arcan_shmif_a11yint_spawn
//
// Note: This file interfaces with arcan_tui (dynamically loaded at runtime
// via dlsym, matching the C ARCAN_TUI_DYNAMIC pattern) and arcan_shmif_server
// for oracle OCR support.
//
const std = @import("std");
const off = @import("shmif_offsets");
const builtin = @import("builtin");
const c = @import("shmif_types");

// Extern C declarations

extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn dlopen(filename: ?[*:0]const u8, flags: c_int) ?*anyopaque;
extern "c" fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;
extern "c" fn arcan_timesleep(ms: c_ulong) void;

extern "c" fn shmifsrv_free(client: ?*c.struct_shmifsrv_client, mode: c_int) void;
extern "c" fn shmifsrv_spawn_client(
    env: c.struct_shmifsrv_envp,
    clsocket: *c_int,
    statuscode: ?*c_int,
    idtok: u32,
) ?*c.struct_shmifsrv_client;
extern "c" fn shmifsrv_poll(client: *c.struct_shmifsrv_client) c_int;
extern "c" fn shmifsrv_dequeue_events(
    client: *c.struct_shmifsrv_client,
    newev: *c.arcan_event,
    limit: usize,
) usize;
extern "c" fn shmifsrv_put_video(
    client: ?*anyopaque,
    vbuf: ?*anyopaque,
) c_int;

fn put_video_simple(
    client: *c.struct_shmifsrv_client,
    w: usize,
    h: usize,
    pitch: usize,
    stride: usize,
    buffer: *anyopaque,
) c_int {
    var vbuf_mem: [off.VBuf.sizeof_vbuf]u8 align(8) = undefined;
    off.VBuf.initSimple(&vbuf_mem, w, h, pitch, stride, buffer);
    return shmifsrv_put_video(@ptrCast(client), @ptrCast(&vbuf_mem));
}
extern "c" fn shmifsrv_merge_multipart_message(
    P: *c.struct_shmifsrv_client,
    ev: *c.arcan_event,
    out: *[*c]u8,
    bad: *bool,
) bool;

// struct_shmif_hidden accessors (opaque due to bitfields)
const support_hook_fn = *const fn (*c.struct_arcan_shmif_cont, c_int) callconv(.c) void;

const RTLD_LAZY = 1;
const SHMIFSRV_FREE_NO_DMS = c.SHMIFSRV_FREE_NO_DMS;

// Dynamic TUI function pointers
// These mirror the ARCAN_TUI_DYNAMIC pattern from arcan_tui.h:
// function names become static function pointers resolved via dlsym.

const TuiSetupFn = *const fn (
    ?*c.struct_arcan_shmif_cont,
    ?*anyopaque,
    ?*const anyopaque,
    usize,
) callconv(.c) ?*anyopaque;

const TuiDynloadFn = *const fn (
    *const fn (?*anyopaque, [*:0]const u8) callconv(.c) ?*anyopaque,
    ?*anyopaque,
) callconv(.c) bool;

const TuiDestroyFn = *const fn (?*anyopaque, ?[*:0]const u8) callconv(.c) void;
const TuiMoveToFn = *const fn (?*anyopaque, usize, usize) callconv(.c) void;
const TuiRefreshFn = *const fn (?*anyopaque) callconv(.c) c_int;
const TuiWndhintFn = *const fn (?*anyopaque, ?*anyopaque, ?*const anyopaque) callconv(.c) void;
const TuiProcessFn = *const fn (?*?*anyopaque, c_int, ?*anyopaque, usize, c_int) callconv(.c) c_int;
const TuiPrintfFn = *const fn (?*anyopaque, ?*const anyopaque, [*c]const u8, ...) callconv(.c) void;

// Global function pointer state (mirrors the static scope in C with ARCAN_TUI_DYNAMIC)
var tui_setup_fn: ?TuiSetupFn = null;
var tui_destroy_fn: ?TuiDestroyFn = null;
var tui_move_to_fn: ?TuiMoveToFn = null;
var tui_refresh_fn: ?TuiRefreshFn = null;
var tui_wndhint_fn: ?TuiWndhintFn = null;
var tui_process_fn: ?TuiProcessFn = null;
var tui_printf_fn: ?TuiPrintfFn = null;

fn load_tui_symbols(handle: ?*anyopaque) bool {
    tui_setup_fn = @ptrCast(@alignCast(dlsym(handle, "arcan_tui_setup") orelse return false));
    tui_destroy_fn = @ptrCast(@alignCast(dlsym(handle, "arcan_tui_destroy") orelse return false));
    tui_move_to_fn = @ptrCast(@alignCast(dlsym(handle, "arcan_tui_move_to") orelse return false));
    tui_refresh_fn = @ptrCast(@alignCast(dlsym(handle, "arcan_tui_refresh") orelse return false));
    tui_wndhint_fn = @ptrCast(@alignCast(dlsym(handle, "arcan_tui_wndhint") orelse return false));
    tui_process_fn = @ptrCast(@alignCast(dlsym(handle, "arcan_tui_process") orelse return false));
    tui_printf_fn = @ptrCast(@alignCast(dlsym(handle, "arcan_tui_printf") orelse return false));
    return true;
}

// a11y_meta structure

const A11yMeta = struct {
    tui: ?*anyopaque,
    oracle: ?*c.struct_shmifsrv_client,
    w: usize,
    h: usize,
    last_message: [*c]u8,
    oracle_fail: bool,
};

// synch_oracle

fn synch_oracle(M: *A11yMeta, P: *c.struct_arcan_shmif_cont) void {
    if (M.oracle_fail)
        return;

    var ev: c.arcan_event = undefined;
    var pv: c_int = undefined;

    // if w/h differ, respawn the oracle
    if (M.oracle != null and (M.w != P.w or M.h != P.h)) {
        shmifsrv_free(M.oracle, 0);
        M.oracle = null;
    }

    if (M.oracle == null) {
        // C code: char envarg[1024] = "ARCAN_ARG=proto=ocr";
        //         char* envv[] = {envarg, NULL};
        var envarg = std.mem.zeroes([1024]u8);
        const env_str = "ARCAN_ARG=proto=ocr";
        @memcpy(envarg[0..env_str.len], env_str);
        var envv = [2][*c]u8{ @ptrCast(&envarg), null };
        var env = std.mem.zeroes(c.struct_shmifsrv_envp);
        env.path = @constCast(@ptrCast("/usr/bin/afsrv_encode"));
        env.envv = @ptrCast(&envv);
        env.detach = 2 | 4 | 8;
        env.init_w = P.w;
        env.init_h = P.h;
        env.type = c.SEGID_ENCODER;

        var clsock: c_int = -1;
        M.oracle = shmifsrv_spawn_client(env, &clsock, null, 0);
        if (M.oracle == null) {
            M.oracle_fail = true;
            return;
        }

        // ensure we send ACTIVATE or _encode will consume the STEPFRAME
        pv = shmifsrv_poll(M.oracle.?);
        while (pv >= 0) {
            while (shmifsrv_dequeue_events(M.oracle.?, &ev, 1) == 1) {}
            if (pv == 1) break;
            pv = shmifsrv_poll(M.oracle.?);
        }

        M.w = P.w;
        M.h = P.h;
    }

    // this goes away when we can have a futex to kqueue on
    while (put_video_simple(
        M.oracle.?,
        @as(usize, @intCast(P.w)),
        @as(usize, @intCast(P.h)),
        @as(usize, @intCast(P.pitch)),
        @as(usize, @intCast(P.stride)),
        @ptrCast(P.unnamed_0.vidp),
    ) == 0) {
        arcan_timesleep(1);
    }

    // this is OUTPUT so VFRAME ready doesn't really help
    pv = shmifsrv_poll(M.oracle.?);
    while (pv >= 0) {
        while (shmifsrv_dequeue_events(M.oracle.?, &ev, 1) == 1) {
            if (ev.category().* == c.EVENT_EXTERNAL and
                ev.ext().kind == c.EVENT_EXTERNAL_MESSAGE)
            {
                var bad: bool = undefined;
                var out: [*c]u8 = undefined;
                if (shmifsrv_merge_multipart_message(M.oracle.?, &ev, &out, &bad)) {
                    if (bad)
                        continue;

                    if (tui_move_to_fn) |move_to| move_to(M.tui, 0, 0);
                    if (tui_printf_fn) |printf_fn| printf_fn(M.tui, null, "%s", out);
                }
            }
        }
        if (pv == 1) break;
        pv = shmifsrv_poll(M.oracle.?);
    }

    if (pv == -1) {
        shmifsrv_free(M.oracle, 0);
        M.oracle = null;
        M.oracle_fail = true;
    }
}

// on_state callback

fn on_state(p: *c.struct_arcan_shmif_cont, state: c_int) callconv(.c) void {
    const priv: *anyopaque = @ptrCast(@alignCast(p.priv));
    const M: *A11yMeta = @ptrCast(@alignCast(off.Hidden.getSupportWindowHookData(priv)));

    if (state == c.SUPPORT_EVENT_VSIGNAL) {
        if ((p.hints & c.SHMIF_RHINT_TPACK) != 0)
            return;
        synch_oracle(M, p);
    } else if (state == c.SUPPORT_EVENT_POLL) {
        if (tui_process_fn) |process_fn| {
            var tui_ptr = M.tui;
            _ = process_fn(&tui_ptr, 1, null, 0, 0);
        }
    } else if (state == c.SUPPORT_EVENT_EXIT) {
        if (M.oracle != null) {
            shmifsrv_free(M.oracle, SHMIFSRV_FREE_NO_DMS);
        }
        off.Hidden.setSupportWindowHook(priv, null);
        if (tui_destroy_fn) |destroy_fn| destroy_fn(M.tui, null);
        free(@as(?*anyopaque, @ptrCast(M)));
    }
}

// redraw

fn redraw(T: ?*anyopaque, a11y: *A11yMeta) void {
    if (tui_move_to_fn) |move_to| move_to(T, 0, 0);

    if (a11y.oracle_fail) {
        if (tui_printf_fn) |printf_fn| printf_fn(T, null, "image interpreter failed");
    } else {
        if (tui_printf_fn) |printf_fn| printf_fn(T, null, "no accesibility information available");
    }

    if (tui_refresh_fn) |refresh_fn| _ = refresh_fn(T);
}

// resized callback

fn resized(
    T: ?*anyopaque,
    _: usize,
    _: usize,
    _: usize,
    _: usize,
    tag: ?*anyopaque,
) callconv(.c) void {
    const p: *c.struct_arcan_shmif_cont = @ptrCast(@alignCast(tag));
    const priv: *anyopaque = @ptrCast(@alignCast(p.priv));
    const a11y: *A11yMeta = @ptrCast(@alignCast(off.Hidden.getSupportWindowHookData(priv)));

    redraw(T, a11y);
}

// execstate callback

fn execstate(
    _: ?*anyopaque,
    state: c_int,
    tag: ?*anyopaque,
) callconv(.c) void {
    const p: *c.struct_arcan_shmif_cont = @ptrCast(@alignCast(tag));
    const priv: *anyopaque = @ptrCast(@alignCast(p.priv));
    const a11y: *A11yMeta = @ptrCast(@alignCast(off.Hidden.getSupportWindowHookData(priv)));

    if (state == 2) {
        if (a11y.oracle != null) {
            shmifsrv_free(a11y.oracle, 0);
            a11y.oracle = null;
            a11y.oracle_fail = true;
        }
    }
}

// arcan_shmif_a11yint_spawn

export fn arcan_shmif_a11yint_spawn(
    ctx: ?*c.struct_arcan_shmif_cont,
    p: ?*c.struct_arcan_shmif_cont,
) bool {
    const parent = p orelse return false;
    const child = ctx orelse return false;
    const priv: *anyopaque = @ptrCast(@alignCast(parent.priv));

    // only one active per parent
    if (off.Hidden.getSupportWindowHook(priv) != null)
        return false;

    // regular thing to handle dynamic injection / loading
    if (tui_setup_fn == null) {
        const lib_name: [*:0]const u8 = if (comptime builtin.os.tag == .macos)
            "libarcan_tui.dylib"
        else
            "libarcan_tui.so";

        const openh = dlopen(lib_name, RTLD_LAZY);
        if (!load_tui_symbols(openh))
            return false;
    }

    const raw = malloc(@sizeOf(A11yMeta)) orelse return false;
    const a11y: *A11yMeta = @ptrCast(@alignCast(raw));
    a11y.* = std.mem.zeroes(A11yMeta);

    off.Hidden.setSupportWindowHook(priv, @constCast(@ptrCast(&on_state)));
    off.Hidden.setSupportWindowHookData(priv, @ptrCast(a11y));

    // Set up TUI callback config struct using zeroed memory with
    // just the callbacks we need, matching the C struct tui_cbcfg layout
    const cbcfg_sz = @sizeOf(c.struct_tui_cbcfg);
    var cbcfg_buf: [cbcfg_sz]u8 align(@alignOf(c.struct_tui_cbcfg)) = std.mem.zeroes([cbcfg_sz]u8);
    const cbcfg: *c.struct_tui_cbcfg = @ptrCast(&cbcfg_buf);
    cbcfg.resized = @constCast(@ptrCast(&resized));
    cbcfg.exec_state = @constCast(@ptrCast(&execstate));
    cbcfg.tag = @ptrCast(parent);

    const setup_fn = tui_setup_fn orelse return false;
    a11y.tui = setup_fn(child, null, @ptrCast(cbcfg), cbcfg_sz);

    if (a11y.tui == null) {
        free(raw);
        return false;
    }

    // set some basic window hints
    var cons = std.mem.zeroes(c.struct_tui_constraints);
    cons.min_rows = 2;
    cons.max_rows = 20;
    cons.min_cols = 64;
    cons.max_cols = 240;
    if (tui_wndhint_fn) |wndhint_fn| wndhint_fn(a11y.tui, null, @ptrCast(&cons));

    return true;
}
