// Lua REPL lock/unlock — thread safety for the Lua REPL.
// Cleaned from translate-c output of llock.c.

const std = @import("std");

// On freestanding targets std.c.pthread_mutex_t resolves to void, which
// is not a valid type for an extern variable.  Use an opaque type so
// the lock object is always pointer-sized regardless of the target.
const LockObj = opaque {};

extern fn pthread_mutex_lock(mutex: *LockObj) c_int;
extern fn pthread_mutex_unlock(mutex: *LockObj) c_int;

extern var lua_repl_lock_obj: LockObj;

pub fn lua_repl_lock() void {
    _ = pthread_mutex_lock(&lua_repl_lock_obj);
}

pub fn lua_repl_unlock() void {
    _ = pthread_mutex_unlock(&lua_repl_lock_obj);
}
