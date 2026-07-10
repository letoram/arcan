// C-ABI extern surface of zig_dlopen for importers.
// The strong definitions live in src/platform/zig_dlopen.zig and are
// compiled into a single object (linked into the exe that needs runtime
// dlopen support). Every other module that wants to call the dl shim
// imports THIS file via `@import("dlopen")` (build.zig registers this
// path under the "zig_dlopen" module name). That way each importer just
// gets extern declarations — no duplicated strong `pub export fn` in every
// object that uses dlopen.

pub extern fn zig_dlopen(path_or_null: ?[*:0]const u8, flags: c_int) callconv(.c) ?*anyopaque;
pub extern fn zig_dlsym(handle: ?*anyopaque, name: [*:0]const u8) callconv(.c) ?*anyopaque;
pub extern fn zig_dlclose(handle: ?*anyopaque) callconv(.c) c_int;
pub extern fn zig_foreign_begin() callconv(.c) void;
pub extern fn zig_foreign_end() callconv(.c) void;
