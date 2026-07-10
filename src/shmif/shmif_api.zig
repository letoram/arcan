//! Shared Zig bindings for the C-ABI arcan_shmif_* entry points.
//!
//! The shmif library lives in our own `src/shmif/` tree as Zig sources but
//! is linked into clients (the engine, frameservers, the standalone tools)
//! through a libc-compatible C ABI. Tools used to redeclare the same
//! `extern fn arcan_shmif_*` lines per-file. This module collects them in
//! one place so a tool just `@import`s `shmif_api` and gets the lot.
//!
//! Add new entries here as tools/clients need them, not in the consumer.
//! Keep declarations 1:1 with the C signatures in `arcan_shmif_control.h`
//! (and the corresponding zig exports in `src/shmif/arcan_shmif_*.zig`).

const std = @import("std");
const types = @import("shmif_types");

pub const shmif_cont = types.struct_arcan_shmif_cont;
pub const arcan_event = types.arcan_event;
pub const shmif_open_ext = types.struct_shmif_open_ext;
pub const arg_arr = types.struct_arg_arr;

// lifecycle

/// Open a SHMIF segment via the rich `shmif_open_ext` parameter block.
/// Args: `flags` (SHMIF_DISABLE_GUARD, SHMIF_ACQUIRE_FATALFAIL, …),
/// `outargs` (out-param string for ARCAN_ARG ack), `ext`/`ext_sz`
/// (parameter block + sizeof). Returns a populated `shmif_cont`.
pub extern fn arcan_shmif_open_ext(
    flags: c_int,
    outargs: ?*[*c]arg_arr,
    ext: shmif_open_ext,
    ext_sz: usize,
) shmif_cont;

/// Drop a SHMIF segment cleanly: tears down the watchdog, unmaps shm,
/// closes the socket. Caller must not touch `*ctx` after return.
pub extern fn arcan_shmif_drop(ctx: *shmif_cont) void;

// synchronization

/// Push pending audio/video frames to the parent. `mask` is a bitmap of
/// `SHMIF_SIGVID | SHMIF_SIGAUD | SHMIF_SIGBLK`. Returns elapsed ms.
pub extern fn arcan_shmif_signal(ctx: ?*shmif_cont, mask: c_int) c_uint;

/// Block until an event is available (or the segment dies). Pulls the
/// next event into `*dst`. Returns 1 on event, 0 on dead/timeout.
pub extern fn arcan_shmif_wait(ctx: ?*shmif_cont, dst: ?*arcan_event) c_int;

// event helpers

/// Push a UTF-8 chunk as one or more MESSAGE events on `ctx`'s outqueue.
/// Used by clipboard tools to paste long strings split across the
/// 78-byte MESSAGE limit. `ev` is a template event used to seed each
/// chunk's metadata; `msg` + `len` is the payload.
pub extern fn arcan_shmif_pushutf8(
    ctx: ?*shmif_cont,
    ev: *const arcan_event,
    msg: [*c]const u8,
    len: usize,
) bool;

/// Get a printable representation of an event into `buf`. If `buf` is
/// null/`buf_sz==0` the function uses a static internal buffer (safe for
/// printf-style debug logs). Returns a pointer to the rendered string.
pub extern fn arcan_shmif_eventstr(
    ev: *const arcan_event,
    buf: [*c]u8,
    buf_sz: usize,
) [*c]const u8;

/// 64-bit cookie identifying ABI compat between client and server. The
/// client compares `arcan_shmif_cookie()` against `shmpage->cookie`; if
/// they differ, the page was produced by a different shmif version.
pub extern fn arcan_shmif_cookie() u64;
