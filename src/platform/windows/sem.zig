// Win32 semaphore shims — same C-ABI surface as platform/{posix,darwin}/sem.zig.
//
// sem_handle is sem_t* on POSIX; here it holds a Win32 HANDLE (pointer-sized).
// These are process-local semaphores (CreateSemaphore with no name). Arcan's
// cross-process sync goes through the futex words in the shared page
// (platform/synch.zig → WaitOnAddress on Windows), so the sem_* API only needs
// to be correct within a process for the milestone; a named/duplicated-handle
// variant lands with the multi-process frameserver work.

const std = @import("std");

const HANDLE = ?*anyopaque;
const BOOL = c_int;
const DWORD = u32;
const WAIT_OBJECT_0: DWORD = 0;
const WAIT_TIMEOUT: DWORD = 0x102;
const INFINITE: DWORD = 0xFFFFFFFF;

extern "kernel32" fn CreateSemaphoreW(attr: ?*anyopaque, initial: c_long, maximum: c_long, name: ?[*:0]const u16) callconv(.winapi) HANDLE;
extern "kernel32" fn ReleaseSemaphore(sem: HANDLE, count: c_long, prev: ?*c_long) callconv(.winapi) BOOL;
extern "kernel32" fn WaitForSingleObject(h: HANDLE, ms: DWORD) callconv(.winapi) DWORD;
extern "kernel32" fn CloseHandle(h: HANDLE) callconv(.winapi) BOOL;

const sem_handle = HANDLE;
const SEM_MAX: c_long = 0x7fffffff;

export fn arcan_sem_post(sem: sem_handle) c_int {
    return if (ReleaseSemaphore(sem, 1, null) != 0) 0 else -1;
}

export fn arcan_sem_unlink(_: sem_handle, _: [*:0]u8) c_int {
    // no named-semaphore filesystem entry to unlink for process-local sems
    return 0;
}

export fn arcan_sem_trywait(sem: sem_handle) c_int {
    return if (WaitForSingleObject(sem, 0) == WAIT_OBJECT_0) 0 else -1;
}

export fn arcan_sem_wait(sem: sem_handle) c_int {
    return if (WaitForSingleObject(sem, INFINITE) == WAIT_OBJECT_0) 0 else -1;
}

export fn arcan_sem_init(sem: *sem_handle, val: c_uint) c_int {
    const h = CreateSemaphoreW(null, @intCast(val), SEM_MAX, null);
    if (h == null) return -1;
    sem.* = h;
    return 0;
}

export fn arcan_sem_destroy(sem: sem_handle) c_int {
    if (sem == null) return -1;
    return if (CloseHandle(sem) != 0) 0 else -1;
}
