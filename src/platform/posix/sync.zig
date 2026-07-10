// Zig port of posix/sync.c
// Futex-based wakeup signaling for frameserver sync slots.
// Opaque arcan_frameserver access + platform-specific syscalls in sync_helpers.zig

const SYNC_EVENT: c_int = 1;
const SYNC_AUDIO: c_int = 2;
const SYNC_VIDEO: c_int = 4;

const arcan_frameserver = opaque {};

extern fn platform_fsrv_signal_event(tgt: ?*arcan_frameserver) void;
extern fn platform_fsrv_signal_video(tgt: ?*arcan_frameserver) void;
extern fn platform_fsrv_signal_audio(tgt: ?*arcan_frameserver) void;

export fn platform_fsrv_signal(tgt: ?*arcan_frameserver, slot: c_int) c_int {
    if (slot & SYNC_EVENT != 0) {
        platform_fsrv_signal_event(tgt);
    }
    if (slot & SYNC_VIDEO != 0) {
        platform_fsrv_signal_video(tgt);
    }
    if (slot & SYNC_AUDIO != 0) {
        platform_fsrv_signal_audio(tgt);
    }
    return 1;
}
