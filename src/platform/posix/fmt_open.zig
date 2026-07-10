// Pure Zig port of posix/fmt_open.c — replaces both fmt_open.c and fmt_open_shim.c.
//
// Exports:
//   fmt_open(flags, mode, fmt, ...)  — variadic, printf-style path open
//   fmt_open_path(flags, mode, path) — non-variadic, pre-formatted path open
//
// Zig 0.15.2 disables @cVaStart on aarch64 (and x86_64/windows) due to
// miscompilations. We work around this with a naked function that manually
// constructs the C va_list struct from the saved register state, then
// delegates to fmt_open_inner which uses vsnprintf to format the path.
//
// aarch64 on the no-LLVM self-hosted fork: the built-in assembler rejects
// FP/SIMD register operands (`q*`/`d*`/`s*`), `.arch_extension fp`, asm
// comments (`//`, `/* */`), and `mov wN, #-imm` — which makes a proper
// variadic trampoline impossible to express inline. No callers of
// fmt_open() exist in the arcan tree (it's declared in os_platform.h
// purely for ABI completeness), so on aarch64 we export a non-variadic
// stub returning -1. `fmt_open_path` is fully functional everywhere.

const std = @import("std");
const builtin = @import("builtin");

const c = @import("posix");

/// AArch64 va_list layout (AAPCS64).
const VaListAarch64 = extern struct {
    __stack: ?*anyopaque,
    __gr_top: ?*anyopaque,
    __vr_top: ?*anyopaque,
    __gr_offs: c_int,
    __vr_offs: c_int,
};

/// x86_64 SysV va_list layout.
const VaListX86_64 = extern struct {
    gp_offset: c_uint,
    fp_offset: c_uint,
    overflow_arg_area: ?*anyopaque,
    reg_save_area: ?*anyopaque,
};

extern "c" fn vsnprintf(
    buf: ?[*]u8,
    size: usize,
    fmt: [*:0]const u8,
    ap: *anyopaque,
) c_int;

/// Open a pre-formatted path with close-on-exec.
export fn fmt_open_path(flags: c_int, mode: c.mode_t, path: [*c]const u8) c_int {
    const rv = c.open(path, flags, mode);

    // Set close-on-exec so spawned children don't inherit this fd
    if (rv != -1) {
        _ = c.fcntl(rv, c.F_SETFD, c.FD_CLOEXEC);
    }

    return rv;
}

/// Inner implementation called by the naked fmt_open trampoline.
/// Receives a pointer to the platform va_list struct set up by the trampoline.
export fn fmt_open_inner(flags: c_int, mode: c.mode_t, fmt: [*:0]const u8, ap: *anyopaque) c_int {
    // First pass: measure the formatted length (use a copy so ap is preserved).
    const VaList = switch (builtin.cpu.arch) {
        .aarch64, .aarch64_be => VaListAarch64,
        .x86_64 => VaListX86_64,
        else => @compileError("fmt_open variadic trampoline: unsupported architecture"),
    };
    const ap_typed: *VaList = @ptrCast(@alignCast(ap));
    var ap_copy = ap_typed.*;
    const cc = vsnprintf(null, 0, fmt, @ptrCast(&ap_copy));
    if (cc <= 0) return -1;

    const size: usize = @intCast(cc + 1);
    const dbuf: ?*anyopaque = std.c.malloc(size);
    if (dbuf == null) return -1;

    // Second pass: format into the allocated buffer (consumes original ap).
    _ = vsnprintf(@ptrCast(dbuf), size, fmt, ap);

    const rv = fmt_open_path(flags, mode, @ptrCast(dbuf));
    std.c.free(dbuf);
    return rv;
}

// Select the platform entry point at comptime: non-variadic stub on
// aarch64, naked variadic trampoline everywhere else.

const use_aarch64_stub = builtin.cpu.arch == .aarch64 or builtin.cpu.arch == .aarch64_be;

fn fmtOpenAarch64Stub(flags: c_int, mode: c.mode_t, fmt: [*:0]const u8) callconv(.c) c_int {
    _ = flags;
    _ = mode;
    _ = fmt;
    return -1;
}

fn fmtOpenNaked() callconv(.naked) void {
    switch (builtin.cpu.arch) {
        .x86_64 => {
            // x86_64 SysV: named args in rdi, rsi, rdx. Variadic GP in
            // rcx, r8, r9 (3 remaining of 6 GP slots). FP in xmm0-xmm7.
            // AL (lower byte of rax) holds the count of vector (xmm) args.
            //
            // Stack layout (304 bytes, 16-byte aligned):
            //   [rsp+ 0]   return addr save area  (8 bytes)
            //   [rsp+ 8]   rbp save               (8 bytes)
            //   [rsp+16]   VaList                  (16 bytes)
            //   [rsp+32]   register save area      (48 GP + 128 FP = 176 bytes)
            //     GP: rcx(+32), r8(+40), r9(+48), rdi(+56)*, rsi(+64)*, rdx(+72)*
            //       * = named args, saved for completeness per ABI
            //     FP: xmm0-xmm7 at [rsp+80] (128 bytes)
            //   total = 208, round to 208 (already 16-byte aligned after push rbp)
            //
            // VaList fields:
            //   gp_offset = 24       (3 named args * 8 = skip first 3 GP slots)
            //   fp_offset = 48       (6 GP slots * 8 = 48, FP starts here)
            //   overflow_arg_area    (points to stack args above our frame)
            //   reg_save_area        (points to saved registers)
            asm volatile (
                \\ push    %%rbp
                \\ mov     %%rsp, %%rbp
                \\ sub     $208, %%rsp
                \\
                \\ // Save GP registers to register save area at rsp+32
                \\ mov     %%rdi, 32(%%rsp)      // slot 0: rdi (flags)
                \\ mov     %%rsi, 40(%%rsp)      // slot 1: rsi (mode)
                \\ mov     %%rdx, 48(%%rsp)      // slot 2: rdx (fmt)
                \\ mov     %%rcx, 56(%%rsp)      // slot 3: rcx (1st vararg)
                \\ mov     %%r8,  64(%%rsp)      // slot 4: r8  (2nd vararg)
                \\ mov     %%r9,  72(%%rsp)      // slot 5: r9  (3rd vararg)
                \\
                \\ // Save FP registers xmm0-xmm7 at rsp+80
                \\ movaps  %%xmm0,  80(%%rsp)
                \\ movaps  %%xmm1,  96(%%rsp)
                \\ movaps  %%xmm2, 112(%%rsp)
                \\ movaps  %%xmm3, 128(%%rsp)
                \\ movaps  %%xmm4, 144(%%rsp)
                \\ movaps  %%xmm5, 160(%%rsp)
                \\ movaps  %%xmm6, 176(%%rsp)
                \\ movaps  %%xmm7, 192(%%rsp)
                \\
                \\ // Build VaList at rsp+16
                \\ movl    $24,  16(%%rsp)       // gp_offset (skip 3 named GP args)
                \\ movl    $48,  20(%%rsp)       // fp_offset (FP area starts after 6 GP slots)
                \\ lea     16(%%rbp), %%rax      // overflow_arg_area (stack args)
                \\ mov     %%rax, 24(%%rsp)
                \\ lea     32(%%rsp), %%rax      // reg_save_area
                \\ mov     %%rax, 32(%%rsp)
                \\
                \\ // Call fmt_open_inner(rdi=flags, rsi=mode, rdx=fmt, rcx=&VaList)
                \\ // rdi, rsi, rdx already hold the right values
                \\ lea     16(%%rsp), %%rcx
                \\ call    fmt_open_inner
                \\
                \\ add     $208, %%rsp
                \\ pop     %%rbp
                \\ ret
            );
        },
        else => @compileError("fmt_open variadic trampoline: unsupported architecture"),
    }
}

comptime {
    if (use_aarch64_stub) {
        @export(&fmtOpenAarch64Stub, .{ .name = "fmt_open" });
    } else {
        @export(&fmtOpenNaked, .{ .name = "fmt_open" });
    }
}
