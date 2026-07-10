// Cosmopolitan-style host linker delegation for static musl binaries.
// Instead of reimplementing the dynamic linker (relocations, TLS, symbol resolution),
// we inject the host's ld-linux.so into the process and delegate to glibc's real
// dlopen/dlsym. This gives us proper GNU hash tables, NEON-optimized strcmp, and
// correct TLS — eliminating the 250K+ slow strcmp calls that made the old approach hang.
//
// Flow: first zig_dlopen call → compile tiny helper → mmap helper + ld-linux →
//       build synthetic stack → jump to ld-linux → helper passes glibc dl* pointers
//       back via callback + longjmp → all subsequent calls use real glibc dlopen/dlsym.
const std = @import("std");
const elf = std.elf;
const posix = std.posix;
const mem = std.mem;
const log = std.log.scoped(.zig_dlopen);

pub const std_options: std.Options = .{ .log_level = .warn };

var last_error: ?[*:0]const u8 = null;
var interp_buf: [256]u8 = undefined; // static buffer for PT_INTERP path

// Linux kernel sigprocmask flags (not exposed by Zig's std for non-libc targets)
const SIG_BLOCK: u32 = 0;
const SIG_SETMASK: u32 = 2;

/// Read auxiliary vector value from /proc/self/auxv (Zig's getauxval returns 0 on static musl).
fn readAuxval(at_type: usize) usize {
    const fd = posix.open("/proc/self/auxv", .{}, 0) catch return 0;
    defer posix.close(fd);
    var buf: [512]u8 = undefined;
    const n = posix.read(fd, &buf) catch return 0;
    const entries = @as([*]const [2]usize, @ptrCast(@alignCast(&buf)))[0 .. n / (2 * @sizeOf(usize))];
    for (entries) |entry| {
        if (entry[0] == std.elf.AT_NULL) break;
        if (entry[0] == at_type) return entry[1];
    }
    return 0;
}

// Public C API

pub export fn zig_dlopen(path_or_null: ?[*:0]const u8, flags: c_int) callconv(.c) ?*anyopaque {
    const path = path_or_null orelse {
        last_error = "dlopen(NULL) not supported";
        return null;
    };
    const name = mem.sliceTo(path, 0);

    if (isIgnoredIcd(name)) {
        log.info("zig_dlopen(\"{s}\") -- ignored (blacklisted ICD)", .{name});
        last_error = "zig_dlopen: ICD blacklisted";
        return null;
    }

    if (!foreign.ready) {
        if (!foreignInit()) {
            last_error = "zig_dlopen: host linker init failed";
            return null;
        }
    }

    log.info("zig_dlopen(\"{s}\")", .{name});
    const result = callForeign(FnDlopen, foreign.dlopen.?, .{ path, flags });
    if (result == null) {
        const err = callForeign(FnDlerror, foreign.dlerror.?, .{});
        if (err) |e| log.err("dlopen error: {s}", .{e});
        last_error = "zig_dlopen: dlopen failed";
    }
    return result;
}

pub export fn zig_dlsym(handle: ?*anyopaque, name_c: [*:0]const u8) callconv(.c) ?*anyopaque {
    if (!foreign.ready) return null;
    return callForeign(FnDlsym, foreign.dlsym.?, .{ handle, name_c });
}

pub export fn zig_dlclose(handle: ?*anyopaque) callconv(.c) c_int {
    if (!foreign.ready) return 0;
    return callForeign(FnDlclose, foreign.dlclose.?, .{handle});
}

pub fn zig_dlerror() callconv(.c) ?[*:0]const u8 {
    defer last_error = null;
    if (last_error) |e| return e;
    if (!foreign.ready) return null;
    return callForeign(FnDlerror, foreign.dlerror.?, .{});
}

// ICD filter (kept from old implementation)

fn isIgnoredIcd(name: []const u8) bool {
    const basename = std.fs.path.basename(name);
    if (mem.startsWith(u8, basename, "libvulkan_")) {
        const allowed = [_][]const u8{
            "libvulkan_asahi.so",
        };
        for (allowed) |a| {
            if (mem.startsWith(u8, basename, a)) return false;
        }
        return true;
    }
    if (mem.startsWith(u8, basename, "libLLVM")) return true;
    return false;
}

// Function pointer types for glibc dl* functions

const FnDlopen = *const fn (?[*:0]const u8, c_int) callconv(.c) ?*anyopaque;
const FnDlsym = *const fn (?*anyopaque, [*:0]const u8) callconv(.c) ?*anyopaque;
const FnDlclose = *const fn (?*anyopaque) callconv(.c) c_int;
const FnDlerror = *const fn () callconv(.c) ?[*:0]const u8;

fn ReturnType(comptime T: type) type {
    const info = @typeInfo(T);
    const ptr_info = info.pointer;
    const child_info = @typeInfo(ptr_info.child);
    return child_info.@"fn".return_type.?;
}

// Foreign (glibc) state

const Foreign = struct {
    dlopen: ?FnDlopen = null,
    dlsym: ?FnDlsym = null,
    dlclose: ?FnDlclose = null,
    dlerror: ?FnDlerror = null,
    musl_tp: usize = 0,
    glibc_tp: usize = 0,
    jmpbuf: c.jmp_buf = undefined,
    ready: bool = false,
};

var foreign: Foreign = .{};

const c = struct {
    // musl's _setjmp/_longjmp (don't save/restore signal mask)
    pub const jmp_buf = [22]usize; // aarch64: 22 doublewords
    pub extern fn _setjmp(buf: *jmp_buf) callconv(.c) c_int;
    pub extern fn _longjmp(buf: *jmp_buf, val: c_int) callconv(.c) noreturn;
};

// TLS management
// Both musl and glibc use tpidr_el0 for TLS on aarch64. We switch per-call:
// musl TLS stays active by default, glibc TLS only during foreign calls.
// Vulkan driver threads (spawned by glibc's pthread_create) naturally have
// glibc TLS — no special handling needed for them.

/// Saved musl TP for the current foreign call (main thread only).
var saved_musl_tp_for_call: usize = 0;

inline fn readTpidr() usize {
    return asm volatile ("mrs %[tp], tpidr_el0"
        : [tp] "=r" (-> usize)
    );
}

inline fn writeTpidr(tp: usize) void {
    asm volatile ("msr tpidr_el0, %[tp]"
        :
        : [tp] "r" (tp),
    );
}

/// Switch to glibc TLS. Call before entering Vulkan/XCB/shaderc code.
/// Must be paired with zig_foreign_end(). Triggers foreignInit if not yet done.
/// Supports nesting via a depth counter (only outermost pair switches TLS).
var foreign_depth: u32 = 0;

pub export fn zig_foreign_begin() callconv(.c) void {
    if (!foreign.ready) return;
    if (foreign_depth == 0) {
        saved_musl_tp_for_call = readTpidr();
        writeTpidr(foreign.glibc_tp);
    }
    foreign_depth += 1;
}

/// Restore musl TLS. Call after returning from Vulkan/XCB/shaderc code.
pub export fn zig_foreign_end() callconv(.c) void {
    if (foreign_depth == 0) return;
    foreign_depth -= 1;
    if (foreign_depth == 0) {
        writeTpidr(saved_musl_tp_for_call);
    }
}

fn callForeign(comptime FnT: type, func: FnT, args: anytype) ReturnType(FnT) {
    // Always switch TLS per-call: musl → glibc → call → glibc → musl
    const musl_tp = readTpidr();
    writeTpidr(foreign.glibc_tp);
    defer writeTpidr(musl_tp);
    return @call(.auto, func, args);
}

// Callback from helper (called by helper's main)
// Receives glibc's dl* function pointers, saves glibc TLS, restores musl TLS,
// and longjmps back to our setjmp site.

export fn foreign_callback(ptrs: [*]?*anyopaque) callconv(.c) c_int {
    foreign.dlopen = @ptrCast(@alignCast(ptrs[0]));
    foreign.dlsym = @ptrCast(@alignCast(ptrs[1]));
    foreign.dlclose = @ptrCast(@alignCast(ptrs[2]));
    foreign.dlerror = @ptrCast(@alignCast(ptrs[3]));
    // Save glibc's TLS pointer (ld-linux set it during init)
    foreign.glibc_tp = asm volatile ("mrs %[tp], tpidr_el0"
        : [tp] "=r" (-> usize)
    );
    // Restore musl's TLS pointer
    asm volatile ("msr tpidr_el0, %[tp]"
        :
        : [tp] "r" (foreign.musl_tp),
    );
    c._longjmp(&foreign.jmpbuf, 1);
}

// Helper source (compiled at runtime with host cc)

const helper_source =
    \\#include <dlfcn.h>
    \\#include <stdlib.h>
    \\int main(int argc, char **argv) {
    \\    if (argc != 2) return 1;
    \\    char *ep;
    \\    unsigned long addr = strtoul(argv[1], &ep, 10);
    \\    if (*ep) return 2;
    \\    void *ptrs[] = { dlopen, dlsym, dlclose, dlerror };
    \\    return ((int (*)(void *))addr)(ptrs);
    \\}
;

// Minimal ELF mapper
// Maps PT_LOAD segments and extracts PT_INTERP. No relocations, no symbol
// resolution — that's the host linker's job.

const ElfMapping = struct {
    base: usize,
    size: usize,
    entry: usize, // entry point (base-adjusted)
    interp: ?[]const u8, // PT_INTERP path
    phdr_addr: usize, // address of program headers in mapped memory
    phnum: u16,
};

fn elfMap(path: [*:0]const u8) !ElfMapping {
    const fd = try posix.openZ(path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    defer posix.close(fd);
    const file: std.fs.File = .{ .handle = fd };
    const stat = try file.stat();
    const size = std.math.cast(usize, stat.size) orelse return error.FileTooBig;
    const page_size = std.heap.pageSize();

    // Map entire file for reading headers
    const file_bytes = try posix.mmap(null, mem.alignForward(usize, size, page_size), posix.PROT.READ, .{ .TYPE = .PRIVATE }, fd, 0);
    defer posix.munmap(file_bytes);

    const eh: *const elf.Ehdr = @ptrCast(file_bytes.ptr);
    if (!mem.eql(u8, eh.e_ident[0..4], elf.MAGIC)) return error.NotElfFile;

    const elf_addr = @intFromPtr(file_bytes.ptr);

    // First pass: find total virtual address span
    var virt_min: usize = std.math.maxInt(usize);
    var virt_max: usize = 0;
    var interp_offset: usize = 0;
    var interp_len: usize = 0;
    {
        var ph_addr: usize = elf_addr + eh.e_phoff;
        for (0..eh.e_phnum) |_| {
            const ph: *const elf.Phdr = @ptrFromInt(ph_addr);
            switch (ph.p_type) {
                elf.PT_LOAD => {
                    virt_min = @min(virt_min, ph.p_vaddr & ~(@as(usize, page_size) - 1));
                    virt_max = @max(virt_max, mem.alignForward(usize, ph.p_vaddr + ph.p_memsz, page_size));
                },
                elf.PT_INTERP => {
                    interp_offset = ph.p_offset;
                    interp_len = ph.p_filesz - 1; // exclude null terminator
                },
                else => {},
            }
            ph_addr += eh.e_phentsize;
        }
    }
    if (virt_max == 0) return error.NoLoadSegments;

    const total_size = virt_max - virt_min;

    // Reserve address space
    const all_mem = try posix.mmap(null, total_size, posix.PROT.NONE, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
    errdefer posix.munmap(all_mem);
    const base = @intFromPtr(all_mem.ptr) -% virt_min;

    // Second pass: map PT_LOAD segments
    {
        var ph_addr: usize = elf_addr + eh.e_phoff;
        for (0..eh.e_phnum) |_| {
            const ph: *const elf.Phdr = @ptrFromInt(ph_addr);
            defer ph_addr += eh.e_phentsize;
            if (ph.p_type != elf.PT_LOAD) continue;

            const seg_start = (base + ph.p_vaddr) & ~(@as(usize, page_size) - 1);
            const seg_end = mem.alignForward(usize, base + ph.p_vaddr + ph.p_memsz, page_size);
            const seg_len = seg_end - seg_start;
            const ptr: [*]align(std.heap.page_size_min) u8 = @ptrFromInt(seg_start);

            // Map writable first, then copy file content, then set proper perms
            var prot: u32 = posix.PROT.READ | posix.PROT.WRITE;
            if ((ph.p_flags & elf.PF_X) != 0) prot |= posix.PROT.EXEC;

            _ = try posix.mmap(ptr, seg_len, prot, .{ .TYPE = .PRIVATE, .FIXED = true, .ANONYMOUS = true }, -1, 0);

            if (ph.p_filesz > 0) {
                const dest_start = base + ph.p_vaddr;
                const dest: [*]u8 = @ptrFromInt(dest_start);
                @memcpy(dest[0..ph.p_filesz], file_bytes[ph.p_offset..][0..ph.p_filesz]);
            }

            // Set final permissions (remove write if not originally writable)
            if ((ph.p_flags & elf.PF_W) == 0) {
                var final_prot: u32 = posix.PROT.NONE;
                if ((ph.p_flags & elf.PF_R) != 0) final_prot |= posix.PROT.READ;
                if ((ph.p_flags & elf.PF_X) != 0) final_prot |= posix.PROT.EXEC;
                posix.mprotect(ptr[0..seg_len], final_prot) catch {};
            }
        }
    }

    // Copy PT_INTERP path into static buffer (file_bytes is about to be unmapped)
    var interp: ?[]const u8 = null;
    if (interp_len > 0 and interp_len < interp_buf.len) {
        @memcpy(interp_buf[0..interp_len], file_bytes[interp_offset..][0..interp_len]);
        interp_buf[interp_len] = 0;
        interp = interp_buf[0..interp_len];
    }

    return .{
        .base = base,
        .size = total_size,
        .entry = base + eh.e_entry,
        .interp = interp,
        .phdr_addr = base + eh.e_phoff,
        .phnum = eh.e_phnum,
    };
}

// Foreign init: compile helper, map ELFs, build stack, jump

fn foreignInit() bool {
    log.info("foreignInit: injecting host linker (cosmopolitan-style)", .{});

    // Save musl's TLS pointer
    foreign.musl_tp = asm volatile ("mrs %[tp], tpidr_el0"
        : [tp] "=r" (-> usize)
    );

    // Step 1: Compile the helper (cached)
    const helper_path = getHelperPath() catch |e| {
        log.err("foreignInit: failed to get helper path: {s}", .{@errorName(e)});
        return false;
    };

    // Step 2: Map the helper ELF
    const helper = elfMap(helper_path) catch |e| {
        log.err("foreignInit: failed to map helper: {s}", .{@errorName(e)});
        return false;
    };
    log.info("foreignInit: helper mapped at base 0x{x}, entry 0x{x}", .{ helper.base, helper.entry });

    // Step 3: Get PT_INTERP from helper (path to ld-linux)
    const interp_path = helper.interp orelse {
        log.err("foreignInit: helper has no PT_INTERP", .{});
        return false;
    };

    log.info("foreignInit: PT_INTERP = {s}", .{interp_path});

    // interp_path is already null-terminated in interp_buf (from elfMap)
    // Step 4: Map ld-linux
    const interp = elfMap(@ptrCast(interp_path.ptr)) catch |e| {
        log.err("foreignInit: failed to map ld-linux: {s}", .{@errorName(e)});
        return false;
    };
    log.info("foreignInit: ld-linux mapped at base 0x{x}, entry 0x{x}", .{ interp.base, interp.entry });

    // Step 5: setjmp — we'll longjmp back here from the callback
    if (c._setjmp(&foreign.jmpbuf) != 0) {
        // Returned from longjmp in foreign_callback — glibc dl* pointers are set.
        // musl TLS is already restored (foreign_callback did it before longjmp).
        foreign.ready = true;
        log.info("foreignInit: host linker ready (dlopen=0x{x})", .{@intFromPtr(foreign.dlopen)});

        // Force glibc's malloc to use mmap instead of sbrk for all allocations.
        // Both musl and glibc share the process brk — without this, glibc's
        // malloc arena 0 extends via sbrk into musl's heap.
        // Also set M_ARENA_MAX=1 to prevent multi-arena issues with our TLS switching,
        // and M_TRIM_THRESHOLD=-1 to prevent arena trimming.
        const mallopt_sym = callForeign(FnDlsym, foreign.dlsym.?, .{ null, "mallopt" });
        if (mallopt_sym) |sym| {
            const mallopt_fn: *const fn (c_int, c_int) callconv(.c) c_int = @ptrCast(@alignCast(sym));
            const M_MMAP_THRESHOLD: c_int = -3;
            const M_ARENA_MAX: c_int = -8;
            _ = callForeign(@TypeOf(mallopt_fn), mallopt_fn, .{ M_MMAP_THRESHOLD, 0 });
            _ = callForeign(@TypeOf(mallopt_fn), mallopt_fn, .{ M_ARENA_MAX, 1 });
            log.info("foreignInit: mallopt configured (mmap_threshold=0, arena_max=1)", .{});
        }

        // Pre-warm glibc's malloc tcache on the main thread by doing a
        // malloc+free cycle. This ensures tcache is initialized before any
        // Vulkan driver threads are created.
        const glibc_malloc_sym = callForeign(FnDlsym, foreign.dlsym.?, .{ null, "malloc" });
        const glibc_free_sym = callForeign(FnDlsym, foreign.dlsym.?, .{ null, "free" });
        if (glibc_malloc_sym) |msym| {
            if (glibc_free_sym) |fsym| {
                const glibc_malloc: *const fn (usize) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(msym));
                const glibc_free: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(fsym));
                // Warm up different size classes
                inline for ([_]usize{ 16, 32, 64, 128, 256, 512 }) |sz| {
                    const p = callForeign(@TypeOf(glibc_malloc), glibc_malloc, .{sz});
                    if (p) |ptr| callForeign(@TypeOf(glibc_free), glibc_free, .{ptr});
                }
                log.info("foreignInit: glibc malloc tcache pre-warmed", .{});
            }
        }

        return true;
    }

    // Step 6: Build synthetic stack and jump to ld-linux
    const page_size = std.heap.pageSize();

    // Format callback address as decimal string
    var addr_buf: [24]u8 = undefined;
    const cb_addr = @intFromPtr(&foreign_callback);
    const addr_str = std.fmt.bufPrintZ(&addr_buf, "{d}", .{cb_addr}) catch {
        log.err("foreignInit: failed to format callback address", .{});
        return false;
    };

    // Allocate stack (16KB should be plenty for ld-linux + helper init)
    const stack_size = 4 * page_size;
    const stack_mem = posix.mmap(null, stack_size, posix.PROT.READ | posix.PROT.WRITE, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0) catch {
        log.err("foreignInit: failed to allocate stack", .{});
        return false;
    };

    // Build stack from high address downward (aarch64 stack grows down)
    // Layout matches what the Linux kernel provides to ld-linux:
    //   argc, argv[0], argv[1], NULL, envp..., NULL, auxv...
    var sp = @intFromPtr(stack_mem.ptr) + stack_size;

    // Helper strings: argv[0] and argv[1]
    const argv0 = "dlopen-helper";

    // Build auxv entries first (we need to know where they go)
    // CRITICAL: AT_HWCAP/AT_HWCAP2 must be passed so glibc detects CPU features
    // (LSE atomics, etc.). Without them, glibc uses slow fallback paths and may
    // misconfigure malloc's arena locking.
    const AuxvEntry = [2]usize;
    const hwcap = readAuxval(std.elf.AT_HWCAP);
    const hwcap2 = readAuxval(std.elf.AT_HWCAP2);
    log.info("foreignInit: AT_HWCAP=0x{x}, AT_HWCAP2=0x{x}", .{ hwcap, hwcap2 });
    const auxv = [_]AuxvEntry{
        .{ std.elf.AT_PHDR, helper.phdr_addr },
        .{ std.elf.AT_PHENT, @sizeOf(elf.Phdr) },
        .{ std.elf.AT_PHNUM, helper.phnum },
        .{ std.elf.AT_PAGESZ, page_size },
        .{ std.elf.AT_BASE, interp.base },
        .{ std.elf.AT_ENTRY, helper.entry },
        .{ std.elf.AT_FLAGS, 0 },
        .{ std.elf.AT_HWCAP, hwcap },
        .{ std.elf.AT_HWCAP2, hwcap2 },
        .{ std.elf.AT_UID, 0 },
        .{ std.elf.AT_EUID, 0 },
        .{ std.elf.AT_GID, 0 },
        .{ std.elf.AT_EGID, 0 },
        .{ std.elf.AT_SECURE, 0 },
        .{ std.elf.AT_RANDOM, @intFromPtr(stack_mem.ptr) }, // 16 random bytes (stack memory is fine)
        .{ std.elf.AT_NULL, 0 },
    };

    // Count envp from current process
    var envp_count: usize = 0;
    if (getEnviron()) |envp| {
        while (envp[envp_count] != null) envp_count += 1;
    }

    // Total number of usize slots needed:
    // argc(1) + argv[0] + argv[1] + NULL + envp[0..n] + NULL + auxv
    const total_slots = 1 + 2 + 1 + envp_count + 1 + auxv.len * 2;
    sp -= total_slots * @sizeOf(usize);
    sp &= ~@as(usize, 15); // 16-byte align

    const slots: [*]usize = @ptrFromInt(sp);
    var idx: usize = 0;

    // argc = 2
    slots[idx] = 2;
    idx += 1;

    // argv[0] = "dlopen-helper"
    slots[idx] = @intFromPtr(argv0.ptr);
    idx += 1;

    // argv[1] = callback address string
    slots[idx] = @intFromPtr(addr_str.ptr);
    idx += 1;

    // argv terminator
    slots[idx] = 0;
    idx += 1;

    // envp
    if (getEnviron()) |envp| {
        for (0..envp_count) |i| {
            slots[idx] = @intFromPtr(envp[i]);
            idx += 1;
        }
    }

    // envp terminator
    slots[idx] = 0;
    idx += 1;

    // auxv
    for (auxv) |entry| {
        slots[idx] = entry[0];
        idx += 1;
        slots[idx] = entry[1];
        idx += 1;
    }

    log.info("foreignInit: jumping to ld-linux entry 0x{x}, sp=0x{x}", .{ interp.entry, sp });

    // Jump to ld-linux's entry point with our synthetic stack
    asm volatile (
        \\mov sp, %[sp]
        \\br %[entry]
        :
        : [sp] "r" (sp),
          [entry] "r" (interp.entry),
    );

    unreachable;
}

fn getEnviron() ?[*]const ?[*:0]const u8 {
    // musl's environ
    const environ_ptr = @extern(?*[*]const ?[*:0]const u8, .{ .name = "environ" });
    if (environ_ptr) |p| return p.*;
    return null;
}

// Helper compilation and caching

fn getHelperPath() ![*:0]const u8 {
    // Cache in XDG_CACHE_HOME or ~/.cache
    const cache_base = posix.getenvZ("XDG_CACHE_HOME") orelse blk: {
        const home = posix.getenvZ("HOME") orelse "/tmp";
        break :blk home;
    };

    var dir_buf: [256]u8 = undefined;
    const is_xdg = posix.getenvZ("XDG_CACHE_HOME") != null;
    const dir_path = if (is_xdg)
        std.fmt.bufPrintZ(&dir_buf, "{s}/arcan", .{cache_base}) catch return error.PathTooLong
    else
        std.fmt.bufPrintZ(&dir_buf, "{s}/.cache/arcan", .{cache_base}) catch return error.PathTooLong;

    // Create cache directory
    std.fs.cwd().makePath(dir_path[0..dir_path.len]) catch {};

    var helper_buf: [300]u8 = undefined;
    const helper_path = std.fmt.bufPrintZ(&helper_buf, "{s}/dlopen-helper", .{dir_path}) catch return error.PathTooLong;

    // Check if helper already exists
    if (posix.access(helper_path, posix.F_OK)) |_| {
        // Already compiled
        return helper_path;
    } else |_| {
        // Need to compile
    }

    // Write helper source to temp file
    var src_buf: [300]u8 = undefined;
    const src_path = std.fmt.bufPrintZ(&src_buf, "{s}/dlopen-helper.c", .{dir_path}) catch return error.PathTooLong;

    {
        const fd = try posix.open(src_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, 0o644);
        defer posix.close(fd);
        var written: usize = 0;
        while (written < helper_source.len) {
            written += posix.write(fd, helper_source[written..]) catch return error.WriteFailed;
        }
    }

    // Compile with host cc
    log.info("compiling dlopen helper: {s}", .{helper_path});
    const argv = [_:null]?[*:0]const u8{
        "cc",
        "-pie",
        "-fPIC",
        "-O2",
        "-o",
        helper_path,
        src_path,
        "-ldl",
        null,
    };

    const pid = try posix.fork();
    if (pid == 0) {
        // Child: exec cc
        const envp = getEnviron() orelse @as([*]const ?[*:0]const u8, &[_:null]?[*:0]const u8{});
        posix.execvpeZ("cc", &argv, @ptrCast(envp)) catch {};
        std.posix.exit(127);
    }

    // Parent: wait for cc
    const result = posix.waitpid(pid, 0);
    const W = std.os.linux.W;
    if (W.IFSIGNALED(result.status)) {
        log.err("cc killed by signal {d}", .{W.TERMSIG(result.status)});
        return error.CompileFailed;
    }
    if (W.IFEXITED(result.status)) {
        const code = W.EXITSTATUS(result.status);
        if (code != 0) {
            log.err("cc exited with status {d}", .{code});
            return error.CompileFailed;
        }
    }

    log.info("dlopen helper compiled successfully", .{});
    return helper_path;
}

// Retained from old implementation (needed by shims.c)
extern var __stack_chk_guard_value: usize;
