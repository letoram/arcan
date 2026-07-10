// macOS backend for the zig_dlopen C-ABI surface.
//
// On Linux we run as a static-musl binary and must inject the host ld-linux +
// switch musl<->glibc TLS (tpidr_el0) to reach glibc-only .so files — see
// zig_dlopen_linux.zig. None of that exists on macOS: there is a single system
// libc (libSystem) that exports dlopen/dlsym/dlclose/dlerror, and a Mach-O
// binary links it directly. So this backend is a thin forward to the native
// dynamic linker, and the foreign-TLS bracket is a no-op.
//
// The point: callers (the dl_*.zig shims, vk.zig, a miniaudio loader) use the
// SAME symbols with the SAME semantics on both platforms, so the Linux Vulkan/
// AGP code is reused on macOS unchanged. What differs is only the library
// *names* (.dylib vs .so.1), switched at the call sites by target os.
//
// Requires a Vulkan runtime to be installed: the macOS Vulkan SDK now ships
// LunarG KosmicKrisp (a Khronos-conformant Vulkan 1.3 driver over Metal on
// Apple Silicon) alongside MoltenVK. Load "libvulkan.1.dylib"; prefer the
// KosmicKrisp ICD. Cap the requested instance apiVersion to 1.3 on macOS.

// libSystem dynamic linker. dlopen(NULL, ...) is valid on macOS (returns a
// handle that searches images already loaded into the process), so the path
// is optional to mirror the Linux signature.
extern "c" fn dlopen(path: ?[*:0]const u8, mode: c_int) ?*anyopaque;
extern "c" fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;
extern "c" fn dlclose(handle: ?*anyopaque) c_int;
extern "c" fn dlerror() ?[*:0]const u8;

// RTLD_* flags share values with the callers' Linux usage for the common case
// (RTLD_LAZY == 1 on both), so flags are forwarded verbatim.
pub export fn zig_dlopen(path_or_null: ?[*:0]const u8, flags: c_int) callconv(.c) ?*anyopaque {
    return dlopen(path_or_null, flags);
}

pub export fn zig_dlsym(handle: ?*anyopaque, name_c: [*:0]const u8) callconv(.c) ?*anyopaque {
    return dlsym(handle, name_c);
}

pub export fn zig_dlclose(handle: ?*anyopaque) callconv(.c) c_int {
    return dlclose(handle);
}

pub fn zig_dlerror() callconv(.c) ?[*:0]const u8 {
    return dlerror();
}

// No musl/glibc TLS split on macOS — these are intentionally no-ops so every
// Linux call site that brackets a foreign call (dl_alsa.zig's fc/fcv,
// vk_offscreen.zig's tlsBegin/tlsEnd, etc.) compiles and runs unchanged.
pub export fn zig_foreign_begin() callconv(.c) void {}
pub export fn zig_foreign_end() callconv(.c) void {}
