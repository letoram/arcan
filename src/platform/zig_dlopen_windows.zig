// Windows backend for the zig_dlopen C-ABI surface.
//
// Design mirrors the macOS backend: the base OS library (here kernel32, the
// Windows analog of libSystem — always mapped, provides the loader itself) is
// the ONE thing referenced directly; every *subsystem* library (ws2_32 for
// sockets, user32/gdi32 for the window, vulkan-1.dll for the ICD) is reached
// through this shim at runtime via LoadLibrary/GetProcAddress, never linked.
// That keeps the "dlopen everything" contract identical across Linux/macOS/
// Windows so the dl_*.zig shims, vk.zig and friends reuse the same code.
//
// dlopen(name, flags) -> LoadLibraryA(name)      (flags ignored; Win has no
//                                                 RTLD_* — resolution is eager)
// dlopen(NULL, ...)   -> GetModuleHandleA(NULL)  (the main module, mirrors the
//                                                 "search already-loaded" case)
// dlsym(h, name)      -> GetProcAddress(h, name)
// dlclose(h)          -> FreeLibrary(h)
//
// No musl<->glibc TLS split exists here, so the foreign-call bracket is a
// no-op, exactly like macOS.

const HMODULE = ?*anyopaque;
const FARPROC = ?*anyopaque;
const BOOL = c_int;
const DWORD = u32;

extern "kernel32" fn LoadLibraryA(name: ?[*:0]const u8) callconv(.winapi) HMODULE;
extern "kernel32" fn GetModuleHandleA(name: ?[*:0]const u8) callconv(.winapi) HMODULE;
extern "kernel32" fn GetProcAddress(module: HMODULE, name: [*:0]const u8) callconv(.winapi) FARPROC;
extern "kernel32" fn FreeLibrary(module: HMODULE) callconv(.winapi) BOOL;
extern "kernel32" fn GetLastError() callconv(.winapi) DWORD;

pub export fn zig_dlopen(path_or_null: ?[*:0]const u8, flags: c_int) callconv(.c) ?*anyopaque {
    _ = flags;
    if (path_or_null) |p| return LoadLibraryA(p);
    return GetModuleHandleA(null);
}

pub export fn zig_dlsym(handle: ?*anyopaque, name_c: [*:0]const u8) callconv(.c) ?*anyopaque {
    // A null handle means "the process default": search the main module, then
    // the common base DLLs. GetProcAddress needs a concrete module.
    const h = handle orelse GetModuleHandleA(null);
    return GetProcAddress(h, name_c);
}

pub export fn zig_dlclose(handle: ?*anyopaque) callconv(.c) c_int {
    return if (FreeLibrary(handle) != 0) 0 else -1;
}

var err_buf: [64]u8 = undefined;
pub fn zig_dlerror() callconv(.c) ?[*:0]const u8 {
    const code = GetLastError();
    if (code == 0) return null;
    // Minimal, allocation-free: report the numeric Win32 error code.
    const s = std.fmt.bufPrintZ(&err_buf, "Win32 error {d}", .{code}) catch return null;
    return s.ptr;
}

// No TLS split on Windows — no-ops so every foreign-call bracket compiles.
pub export fn zig_foreign_begin() callconv(.c) void {}
pub export fn zig_foreign_end() callconv(.c) void {}

const std = @import("std");
