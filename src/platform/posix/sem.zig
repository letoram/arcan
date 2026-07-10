// Zig port of posix/sem.c
// Thin wrappers around POSIX semaphore functions.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

const c = if (is_freestanding) void else std.c;

/// sem_handle is sem_t* in C (nullable).
const sem_handle = if (is_freestanding) ?*anyopaque else ?*c.sem_t;

/// sem_unlink is not in Zig's std.c bindings, declare it directly.
extern "c" fn sem_unlink(name: [*:0]const u8) c_int;

export fn arcan_sem_post(sem: sem_handle) c_int {
    if (is_freestanding) return -1;
    return c.sem_post(sem.?);
}

export fn arcan_sem_unlink(_: sem_handle, key: [*:0]u8) c_int {
    if (is_freestanding) return -1;
    return sem_unlink(key);
}

export fn arcan_sem_trywait(sem: sem_handle) c_int {
    if (is_freestanding) return -1;
    return c.sem_trywait(sem.?);
}

export fn arcan_sem_wait(sem: sem_handle) c_int {
    if (is_freestanding) return -1;
    return c.sem_wait(sem.?);
}

export fn arcan_sem_init(sem: *sem_handle, val: c_uint) c_int {
    if (is_freestanding) return -1;
    if (sem.* == null) {
        const ptr = c.malloc(@sizeOf(c.sem_t));
        if (ptr == null) return -1;
        sem.* = @ptrCast(@alignCast(ptr));
    }
    return c.sem_init(sem.*.?, 0, val);
}

export fn arcan_sem_destroy(sem: sem_handle) c_int {
    if (is_freestanding) return -1;
    return c.sem_destroy(sem.?);
}
