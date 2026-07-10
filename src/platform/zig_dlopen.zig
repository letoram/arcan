// Entry point for the zig_dlopen C-ABI surface (the "dlopen" module),
// used across the tree (the dl_*.zig shims, vk.zig, vk_offscreen.zig).
//
// zig_dlopen_linux.zig — static-musl host-linker injection (Cosmopolitan /
// jart-style: map ld-linux, delegate to glibc dlopen/dlsym, switch
// musl<->glibc TLS per call). Required because a static-musl binary
// otherwise cannot reach glibc-only .so's (the Vulkan driver, shaderc,
// libasound).
//
// The aliases below keep both call styles working — Zig callers use
// `dl.zig_dlopen(...)`, while C / `extern fn` callers (e.g.
// vk_offscreen.zig) link the `export fn` symbols emitted by the impl.

const builtin = @import("builtin");

pub const impl = switch (builtin.os.tag) {
    .macos, .ios, .watchos, .tvos => @import("zig_dlopen_macos.zig"),
    else => @import("zig_dlopen_linux.zig"),
};

pub const zig_dlopen = impl.zig_dlopen;
pub const zig_dlsym = impl.zig_dlsym;
pub const zig_dlclose = impl.zig_dlclose;
pub const zig_dlerror = impl.zig_dlerror;
pub const zig_foreign_begin = impl.zig_foreign_begin;
pub const zig_foreign_end = impl.zig_foreign_end;

// Force the selected impl file to load so its `export fn` symbols are
// emitted even when this file is an object's root module — plain pub
// aliases are not analysis roots under stock zig.
comptime {
    _ = impl;
}
