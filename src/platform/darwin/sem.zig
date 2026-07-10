// Zig port of platform/darwin/sem.c — semaphore shim for macOS.
// Darwin only implements *named* POSIX semaphores (sem_init on an unnamed
// sem_t always fails with ENOSYS), so arcan_sem_init simulates an unnamed
// semaphore by sem_open'ing a randomly-named one and immediately
// sem_unlink'ing it — the handle stays valid, the name is reclaimed.
// Copyright: Björn Ståhl (original C), 3-Clause BSD (see COPYING).

const std = @import("std");

// sem_t is opaque on Darwin; the handle is sem_t* (SEM_FAILED == (sem_t*)-1).
const sem_handle = ?*anyopaque;
const SEM_FAILED: sem_handle = @ptrFromInt(std.math.maxInt(usize));

const O_CREAT: c_int = 0x0200; // Darwin <fcntl.h>
const O_EXCL: c_int = 0x0800;

extern "c" fn sem_post(sem: sem_handle) c_int;
extern "c" fn sem_wait(sem: sem_handle) c_int;
extern "c" fn sem_trywait(sem: sem_handle) c_int;
extern "c" fn sem_close(sem: sem_handle) c_int;
extern "c" fn sem_unlink(name: [*:0]const u8) c_int;
extern "c" fn sem_open(name: [*:0]const u8, oflag: c_int, ...) sem_handle;

export fn arcan_sem_post(sem: sem_handle) c_int {
    return sem_post(sem);
}

export fn arcan_sem_unlink(_: sem_handle, key: [*:0]u8) c_int {
    return sem_unlink(key);
}

export fn arcan_sem_trywait(sem: sem_handle) c_int {
    return sem_trywait(sem);
}

export fn arcan_sem_wait(sem: sem_handle) c_int {
    return sem_wait(sem);
}

export fn arcan_sem_init(sem: *sem_handle, val: c_uint) c_int {
    var retryc: usize = 10;
    var seed: u32 = @truncate(@as(u64, @bitCast(std.time.milliTimestamp())));
    while (retryc > 0) : (retryc -= 1) {
        // xorshift so repeated failures try distinct names without needing
        // libc rand() state.
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;
        var buf: [32]u8 = undefined;
        const name = std.fmt.bufPrintZ(&buf, "/arc_dwn_sem_{d}", .{seed}) catch continue;
        const s = sem_open(name.ptr, O_CREAT | O_EXCL, @as(c_uint, 0o700), val);
        // sem_unlink is distinct from sem_close: reclaim the name, keep the fd.
        _ = sem_unlink(name.ptr);
        if (s != SEM_FAILED) {
            sem.* = s;
            return 0;
        }
    }
    return -1;
}

export fn arcan_sem_destroy(sem: sem_handle) c_int {
    if (sem == null) return -1;
    return sem_close(sem);
}
