// we do these things not because they are easy, but because we thought they were going to be easy
const std = @import("std");
const String = []const u8;
// LLVM-implicating targets (qtarcan, gamescope, llama-cli, and Phase 3+
// afsrv_bun) live in build_llvm/ as a standalone Zig project — invoked
// via `cd build_llvm && zig build <target>`. They are intentionally NOT
// reachable from this top-level build script and their deps are NOT in
// this top-level build.zig.zon, so a self-host-only toolchain checking
// out arcan never sees them. See build_llvm/build.zig{,.zon}.
const build_xarcan = @import("build_xarcan.zig");
const build_helpers = @import("build_helpers.zig");
const build_external = @import("build_external.zig");

const a12_version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };
const shmif_version = std.SemanticVersion{ .major = 0, .minor = 18, .patch = 0 };

const Opts = struct {
    platform_header: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    static: bool,
    strip: ?bool,
    pic: ?bool,
    build_shmif_server: bool,
    build_shmif: bool,
    build_tui: bool,
    build_a12: bool,
    build_arcan_db: bool,
    build_arcan_frameserver: bool,
    build_afsrv_terminal: bool,
    build_afsrv_decode: bool,
    build_afsrv_encode: bool,
    build_afsrv_net: bool,
    build_arcan_net: bool,
    build_arcan_net_session: bool,
    build_afsrv_remoting: bool,
    build_afsrv_game: bool,
    build_afsrv_avfeed: bool,
    build_afsrv_bun: bool,
    build_afsrv_probe: bool,
    build_arcan_vk: bool,
    build_shmif_ext: bool,
    build_aclip: bool,
    build_shmmon: bool,
    build_acfgfs: bool,
    build_xarcan: bool,
    build_ghostty_tests: bool = false,
    prebuilt_musl: bool = false,
    libc_file: ?std.Build.LazyPath = null,
    static_deps: bool = false,
    ext: build_external.ExternalDeps = .{},
};

// Shared include path constants
const shmif_include_paths: []const String = &.{
    "src/shmif", "src/shmif/tui", "src/shmif/tui/lua", "src/shmif/tui/widgets",
    "src/shmif/platform", "src/engine", "src/platform",
};
const shmif_tui_include_paths: []const String = &.{
    "src/frameserver", "src/engine", "src/engine/external", "src/shmif",
};
const a12_include_paths: []const String = &.{
    "src/a12", "src/a12/external/blake3", "src/a12/external/zstd",
    "src/a12/external/zstd/common", "src/a12/external/mono",
    "src/a12/external/mono/optional", "src/a12/external", "src/engine", "src/shmif",
};
const compositor_include_paths: []const String = &.{
    "src/engine", "src/engine/external", "src/platform", "src/shmif",
    "src/shmif/tui", "src/frameserver", "external",
};
const fsrv_a12_include_paths: []const String = &.{
    "src/frameserver/util", "src/a12", "src/a12/external", "src/a12/external/blake3",
    "src/a12/external/mono", "src/a12/external/mono/optional", "src/engine", "src/frameserver",
};

// Helper functions
fn createExe(b: *std.Build, name: []const u8, opts: Opts) *std.Build.Step.Compile {
    // src/zig_panic_root.zig installs `pub const panic = std.debug.simple_panic`,
    // bypassing the default DWARF-walking panic handler that recursively crashes
    // on our compressed .zdebug_* sections. See the file for full rationale.
    const exe = b.addExecutable(.{ .use_llvm = use_llvm_default, .name = name, .root_module = b.createModule(.{
        .root_source_file = b.path("src/zig_panic_root.zig"),
        .target = opts.target, .optimize = opts.optimize,
    }) });
    addLibC(exe, opts);
    addPlatformDefinitions(exe, opts);
    exe.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
    addDarwinLibcBridge(exe, b, opts);
    return exe;
}

// On macOS every exe needs the glibc↔Darwin libc bridges (stdio globals,
// __errno_location, __assert_fail, __sigsetjmp, mremap/setfs*). One object
// per exe — no cross-object symbol collisions.
fn addDarwinLibcBridge(exe: *std.Build.Step.Compile, b: *std.Build, opts: Opts) void {
    switch (opts.target.result.os.tag) {
        .ios, .macos, .watchos, .tvos => {},
        else => return,
    }
    // LLVM backend: the stdio __mod_init_func constructor uses an @export
    // with an explicit mach-o section, which the self-hosted backend does
    // not yet implement (ExportOptions.section).
    const obj = b.addObject(.{ .use_llvm = true, .name = "libc_darwin", .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/darwin/libc_darwin.zig"),
        .target = opts.target, .optimize = opts.optimize,
    }) });
    addLibC(obj, opts);
    exe.addObject(obj);
}

fn createLibrary(b: *std.Build, name: []const u8, version: std.SemanticVersion, opts: Opts) *std.Build.Step.Compile {
    return b.addLibrary(.{
        .linkage = if (opts.static) .static else .dynamic,
        .name = name, .version = version,
        .use_llvm = use_llvm_default,
        .root_module = b.createModule(.{
            .target = opts.target, .optimize = opts.optimize, .pic = opts.pic, .strip = opts.strip,
        }),
    });
}

fn addIncludes(step: *std.Build.Step.Compile, b: *std.Build, paths: []const []const u8) void {
    for (paths) |p| step.addIncludePath(b.path(p));
}

// SH backend is the default for everything in this build.zig.
// LLVM-required builds (ghostty bridge variants, Qt/gamescope/llama
// integrations) live under build_llvm/ and have their own entry points.
// Kept as a function (rather than inlining `false`) so future per-file
// overrides have a single chokepoint to extend.
fn useLlvmForSource(b: *std.Build, zig_path: []const u8) ?bool {
    _ = b;
    _ = zig_path;
    return use_llvm_default;
}

// Backend selection: self-hosted for the native linux/bsd builds, LLVM when
// targeting darwin — the SH-backend Mach-O objects trip relocation overflows
// in the self-hosted linker. Set once at the top of build().
var use_llvm_default: bool = false;

fn debugPrefixFlag(b: *std.Build) []const u8 {
    return b.fmt("-fdebug-prefix-map={s}/=", .{b.build_root.path orelse "."});
}

fn cSourceFlags(b: *std.Build, extra: []const []const u8) []const []const u8 {
    // `&.{debugPrefixFlag(b)}` with a runtime value produces a stack-local
    // 1-element array; returning a pointer to it is a dangling slice.
    // LLVM often hides this by not reusing the stack; the self-hosted
    // aarch64 backend overwrites it aggressively, so allocate on b.allocator
    // unconditionally.
    const flags = b.allocator.alloc([]const u8, extra.len + 1) catch @panic("OOM");
    @memcpy(flags[0..extra.len], extra);
    flags[extra.len] = debugPrefixFlag(b);
    return flags;
}

fn addCSources(step: *std.Build.Step.Compile, b: *std.Build, paths: []const []const u8) void {
    const dbg = &.{debugPrefixFlag(b)};
    for (paths) |p| step.addCSourceFile(.{ .file = b.path(p), .flags = dbg });
}

// Call step.linkLibC() and, when -Dlibc_file is given, also point the step
// at that Zig libc file so Zig's own musl-from-source compile is skipped in
// favour of the prebuilt artifacts it describes. Replaces all direct
// step.linkLibC() calls so the flag is honoured uniformly.
fn addLibC(step: *std.Build.Step.Compile, opts: Opts) void {
    step.linkLibC();
    if (opts.libc_file) |p| step.setLibCFile(p);
}

fn linkFsrvStdlib(exe: *std.Build.Step.Compile) void {
    // On Darwin, m/rt/dl/pthread/atomic/util all live in libSystem (linked via
    // libc); there are no standalone .dylibs to name, so requesting them fails
    // the link. Only Linux/BSD split them into separate libraries.
    switch (exe.rootModuleTarget().os.tag) {
        .ios, .macos, .watchos, .tvos => {},
        // windows: m/atomic come from compiler-rt, dl/pthread/rt from the win
        // substrate; none exist as standalone import libs. (windows port)
        .windows => {},
        else => for ([_][]const u8{ "m", "rt", "dl", "pthread", "atomic" }) |lib| exe.linkSystemLibrary(lib),
    }
}

fn linkUtil(exe: *std.Build.Step.Compile) void {
    switch (exe.rootModuleTarget().os.tag) {
        .ios, .macos, .watchos, .tvos => {}, // forkpty/openpty are in libSystem
        .windows => {}, // no forkpty on windows (windows port)
        else => exe.linkSystemLibrary("util"),
    }
}

fn createMod(b: *std.Build, path: []const u8, opts: Opts) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(path),
        .target = opts.target, .optimize = opts.optimize,
    });
}

// a12_types re-exports shmif-layer types from shmif_types (arcan_event,
// arcan_shmif_cont, shmifsrv_client, arg_arr) so a12 consumers and shmif
// consumers agree on the underlying Zig type through the dispatch-struct
// pattern. Use this helper rather than createMod when a12_types is
// constructed locally.
fn createA12TypesMod(b: *std.Build, opts: Opts, shmif_mod: *std.Build.Module) *std.Build.Module {
    const m = createMod(b, "src/a12/a12_types.zig", opts);
    m.addImport("shmif_types", shmif_mod);
    return m;
}

// anet_types re-exports concrete extern-struct types from shmif_types,
// a12_types, and posix_libc (struct_arcan_shmif_cont, struct_arcan_event,
// struct_a12_state, pthread_mutex_t, ...) so its own module graph must see
// those siblings. Use this helper rather than createMod when the anet_types
// module is constructed locally.
fn createAnetTypesMod(
    b: *std.Build,
    opts: Opts,
    shmif_mod: *std.Build.Module,
    a12_mod: *std.Build.Module,
    libc_mod: *std.Build.Module,
) *std.Build.Module {
    const m = createMod(b, "src/a12/net/anet_types.zig", opts);
    m.addImport("shmif_types", shmif_mod);
    m.addImport("a12_types", a12_mod);
    m.addImport("posix", libc_mod);
    return m;
}

// The four hand-written replacement modules the T46 @cImport→@import sweep
// rewrites consumers against. Any Zig compile step that might end up
// containing (directly or through future rewrites) a call site spelled
// `@import("posix_libc")` / `@import("shmif_types")` / `@import("a12_types")`
// / `@import("anet_types")` needs these four modules available as named
// imports. Module graphs are lazy, so adding them to a compile step that
// doesn't actually use them is free.
const CoreMods = struct {
    posix_libc: *std.Build.Module,
    shmif_types: *std.Build.Module,
    a12_types: *std.Build.Module,
    anet_types: *std.Build.Module,
    lua54_api: *std.Build.Module,
};

fn coreMods(b: *std.Build, opts: Opts) CoreMods {
    const shmif_types = createMod(b, "src/shmif/shmif_types.zig", opts);
    const a12_types = createA12TypesMod(b, opts, shmif_types);
    const posix_libc = createMod(b, "src/platform/posix/libc.zig", opts);
    return .{
        .posix_libc = posix_libc,
        .shmif_types = shmif_types,
        .a12_types = a12_types,
        .anet_types = createAnetTypesMod(b, opts, shmif_types, a12_types, posix_libc),
        .lua54_api = createMod(b, "src/lua54/api.zig", opts),
    };
}

fn coreImports(mods: CoreMods) [5]std.Build.Module.Import {
    return .{
        .{ .name = "posix", .module = mods.posix_libc },
        .{ .name = "shmif_types", .module = mods.shmif_types },
        .{ .name = "a12_types", .module = mods.a12_types },
        .{ .name = "anet_types", .module = mods.anet_types },
        .{ .name = "lua_api", .module = mods.lua54_api },
    };
}

const NamePath = struct { name: String, path: String };

fn addZigObjects(
    exe: *std.Build.Step.Compile, b: *std.Build, opts: Opts,
    sources: []const NamePath, imports: []const std.Build.Module.Import,
    // Pointer-to-slice (1 reg slot) rather than slice-by-value (2 reg slots).
    // The 6-param signature's 9th register slot (the 2nd slice's .len) was
    // landing on the stack, and the aarch64 self-hosted backend was not
    // writing that stack slot — so the callee's `includes.len` came through
    // as 0xaaaa... (undef) and `addIncludes`/`Build.path` crashed reading
    // garbage. Pointer-to-slice keeps us at 8 register slots.
    includes: *const []const []const u8,
) void {
    for (sources) |src| {
        const obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = src.name, .root_module = b.createModule(.{
            .root_source_file = b.path(src.path), .target = opts.target,
            .optimize = opts.optimize, .imports = imports,
        }) });
        addLibC(obj, opts);
        addIncludes(obj, b, includes.*);
        exe.addObject(obj);
    }
}

// Compile src/lua54/lua_all_embed.zig as a shared Zig object providing the
// Lua 5.4 runtime (pure-Zig port) for userspace binaries. This is a slim
// variant of lua_all.zig that excludes seL4/boot-environment modules (lrepl,
// lunix, serialize, visitor, llock, lnotice, ltests, and the luaencode*/
// luaparse*/luapush*/etc helpers). The full lua_all.zig is reserved for the
// freestanding boot build. Call once per binary — each call produces a
// distinct Object so Zig's linker can dedupe symbols per-binary.
fn addLua54AllObject(b: *std.Build, exe: *std.Build.Step.Compile, opts: Opts) void {
    const lua54_all_obj = b.addObject(.{ .use_llvm = use_llvm_default,
        .name = "lua54_all",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lua54/lua_all_embed.zig"),
            .target = opts.target, .optimize = opts.optimize, .pic = opts.pic,
        }),
    });
    addLibC(lua54_all_obj, opts);
    exe.addObject(lua54_all_obj);
}

// ════════════════════════════════════════════════════════════════════
// build() — main entry point
// ════════════════════════════════════════════════════════════════════
pub fn build(b: *std.Build) void {
    // Ticket 0157 — refuse to run as root unless explicitly opted in.
    // Root-owned files in zig-out/ silently break subsequent user-level
    // installs (the directory copy doesn't surface EPERM). The opt-in
    // is for legitimate system-prefix installs ("zig build install
    // -p /opt/arcan-system" with ARCAN_ALLOW_ROOT_INSTALL=1).
    if (@import("builtin").os.tag == .linux) {
        if (std.os.linux.geteuid() == 0) {
            // std.posix.getenv walks the initial environ snapshot taken
            // at program start; for the build binary that snapshot DOES
            // include vars set in the parent shell environment before
            // `zig build` was invoked. Direct walk of std.os.environ is
            // identical and avoids a libc dep. Lookup must match key
            // exactly including the trailing '='.
            var ok: ?[]const u8 = null;
            for (std.os.environ) |raw| {
                const e = std.mem.span(raw);
                if (std.mem.startsWith(u8, e, "ARCAN_ALLOW_ROOT_INSTALL=")) {
                    ok = e["ARCAN_ALLOW_ROOT_INSTALL=".len..];
                    break;
                }
            }
            if (ok == null or !std.mem.eql(u8, ok.?, "1")) {
                std.debug.print(
                    \\
                    \\refusing to build as root (EUID 0).
                    \\
                    \\Root-owned files in zig-out/ break subsequent user-level
                    \\installs because the directory copy doesn't surface
                    \\EPERM as an error — the install silently skips affected
                    \\files and you end up running stale code.
                    \\
                    \\If you intend a system-prefix install, set
                    \\  ARCAN_ALLOW_ROOT_INSTALL=1
                    \\and use
                    \\  zig build install -p /opt/arcan-system
                    \\(or another non-zig-out/ prefix). Never sudo into
                    \\zig-out/. See CLAUDE.md "Don'ts" + ticket 0157.
                    \\
                , .{});
                std.process.exit(1);
            }
        }
    }

    const platform_header_path = b.path("./src/platform/platform.h").getPath(b);
    const build_all = b.option(bool, "build_all", "Build all targets (default: false)") orelse false;
    const pic: ?bool = b.option(bool, "pic", "Produce Position Independent Code");
    const want_static_deps = b.option(bool, "static_deps", "Build OpenAL/libdrm from source instead of using system pkg-config (default: true)") orelse true;
    const target = b.standardTargetOptions(.{ .default_target = .{
        .cpu_arch = .aarch64,
        .os_tag = .linux,
        .abi = .musl,
    } });
    use_llvm_default = switch (target.result.os.tag) {
        // darwin: SH Mach-O relocations overflow. windows: SH has no Win64
        // codegen for several constructs (var-args, some atomics) — LLVM is
        // the only working backend for the x86_64-windows target.
        .ios, .macos, .watchos, .tvos, .windows => true,
        else => false,
    };
    // Bug 0162: setting `preferred_optimize_mode = .Debug` here disables
    // user-selectable release modes — the fork's standardOptimizeOption
    // (lib/std/Build.zig:1348) returns the preferred mode whenever
    // `--release` or `release_mode != .off` is set, ignoring which mode
    // the user actually asked for. Without preferred_optimize_mode the
    // function falls through to its release_mode switch (Debug if .off,
    // ReleaseSafe / ReleaseFast / ReleaseSmall otherwise) which is what
    // most projects want and what `--release=safe` actually means.
    //
    // Practical effect: `zig build install --release=safe` now produces
    // a ReleaseSafe build instead of silently staying Debug. Workaround
    // for 0162's a12int_append_out 7.8 MB stack frame until the
    // codegen-side fix lands.
    const optimize = b.standardOptimizeOption(.{});
    const ext: build_external.ExternalDeps = if (want_static_deps)
        build_external.resolveAll(b, target, optimize, shmif_include_paths)
    else
        .{};
    // Optional: point the build at a pre-existing libc installation via a
    // standard Zig libc file (see `zig libc`) to skip Zig's internal musl
    // compile. Off unless a path is passed.
    const libc_file_path = b.option([]const u8, "libc_file", "Path to a Zig libc file describing a prebuilt libc to link instead of compiling musl from source");
    const libc_file: ?std.Build.LazyPath = if (libc_file_path) |p| .{ .cwd_relative = p } else null;
    const opts = Opts{
        .platform_header = b.fmt("\"{s}\"", .{platform_header_path}),
        .target = target,
        .optimize = optimize,
        .static = b.option(bool, "static", "Statically linked build (default: true)") orelse true,
        .strip = b.option(bool, "strip", "Omit debug information"),
        .pic = pic,
        .build_shmif_server = b.option(bool, "build_shmif_server", "Build arcan_shmif_server library (default: true)") orelse true,
        .build_shmif = b.option(bool, "build_shmif", "Build arcan_shmif library (default: true)") orelse true,
        .build_tui = b.option(bool, "build_tui", "Build arcan_tui library (default: true)") orelse true,
        // a12/net is deferred on windows (needs the posix fd/socket substrate);
        // the compositor path links without it. (windows port)
        .build_a12 = b.option(bool, "build_a12", "Build arcan_a12 library (default: true)") orelse (target.result.os.tag != .windows),
        .build_arcan_db = b.option(bool, "build_arcan_db", "Build arcan_db database tool (default: false)") orelse build_all,
        .build_arcan_frameserver = b.option(bool, "build_arcan_frameserver", "Build arcan_frameserver chainloader (default: true)") orelse true,
        .build_afsrv_terminal = b.option(bool, "build_afsrv_terminal", "Build afsrv_terminal frameserver (default: true)") orelse true,
        .build_afsrv_decode = b.option(bool, "build_afsrv_decode", "Build afsrv_decode frameserver (default: true)") orelse true,
        .build_afsrv_encode = b.option(bool, "build_afsrv_encode", "Build afsrv_encode frameserver (default: false, needs a12 fixes)") orelse build_all,
        .build_afsrv_net = b.option(bool, "build_afsrv_net", "Build afsrv_net frameserver (default: false, needs a12 fixes)") orelse build_all,
        .build_arcan_net = b.option(bool, "build_arcan_net", "Build arcan-net directory/bridge binary (pure Zig)") orelse (target.result.os.tag != .windows),
        .build_arcan_net_session = b.option(bool, "build_arcan_net_session", "Build arcan-net-session binary (pure Zig)") orelse (target.result.os.tag != .windows),
        .build_afsrv_remoting = b.option(bool, "build_afsrv_remoting", "Build afsrv_remoting frameserver (default: false, needs a12 fixes)") orelse build_all,
        .build_afsrv_game = b.option(bool, "build_afsrv_game", "Build afsrv_game frameserver (default: true)") orelse true,
        .build_afsrv_avfeed = b.option(bool, "build_afsrv_avfeed", "Build afsrv_avfeed frameserver (default: true)") orelse true,
        .build_afsrv_bun = b.option(bool, "build_afsrv_bun", "Build afsrv_bun frameserver — embedded Bun host for JS/TS shmif clients (default: false, see bugs/0036)") orelse false,
        .build_afsrv_probe = b.option(bool, "build_afsrv_probe", "Build afsrv_probe frameserver (drives a12 coverage probes)") orelse true,
        .build_arcan_vk = b.option(bool, "build_arcan_vk", "Build arcan Vulkan VK_KHR_display compositor (default: true)") orelse true,
        .build_shmif_ext = b.option(bool, "build_shmif_ext", "Build arcan_shmif_ext stub library (default: false)") orelse build_all,
        .build_aclip = b.option(bool, "build_aclip", "Build aclip clipboard tool (default: false)") orelse build_all,
        .build_shmmon = b.option(bool, "build_shmmon", "Build shmmon monitor tool (default: false)") orelse build_all,
        .build_acfgfs = b.option(bool, "build_acfgfs", "Build acfgfs FUSE config filesystem (default: false)") orelse build_all,
        .build_xarcan = b.option(bool, "build_xarcan", "Build Xarcan X server with arcan backend (default: false)") orelse build_all,
        .build_ghostty_tests = b.option(bool, "build_ghostty_tests", "Expose the test-ghostty step; pulls the ghostty dep into the build graph (default: false)") orelse false,
        .prebuilt_musl = libc_file != null,
        .libc_file = libc_file,
        .static_deps = want_static_deps,
        .ext = ext,
    };

    switch (opts.target.result.os.tag) {
        .linux, .ios, .macos, .watchos, .tvos, .freebsd, .dragonfly, .openbsd, .netbsd, .windows => {},
        else => |t| std.debug.panic("Unsupported platform: {s} — arcan targets Linux/BSD/macOS/Windows", .{@tagName(t)}),
    }

    // PIC: only forced when caller passes -Dpic=true. qtarcan (now in
    // build_llvm/) sets PIC on its own shared lib internally.

    // Core libraries
    // Public "arcan" API module for downstream package consumers. Pure-Zig
    // type mirror (same file the engine uses internally); replaces the old
    // translate-C of src/arcan.h.
    _ = b.addModule("arcan", .{
        .root_source_file = b.path("src/engine/arcan_zig_types.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });
    const arcan_shmif_server = createArcanShmifServer(b, opts);
    if (opts.build_shmif_server) b.installArtifact(arcan_shmif_server);
    if (opts.build_shmif and !opts.build_shmif_server) @panic("Can not build Arcan shmif library without shmif server");
    const arcan_shmif = createArcanShmif(b, opts);
    arcan_shmif.linkLibrary(arcan_shmif_server);
    if (opts.build_shmif) b.installArtifact(arcan_shmif);
    if (opts.build_tui and !opts.build_shmif) @panic("Can not build Arcan TUI library without shmif");
    const arcan_tui = createArcanTui(b, opts);
    arcan_tui.linkLibrary(arcan_shmif);
    if (opts.build_tui) b.installArtifact(arcan_tui);
    const arcan_a12 = createArcanA12(b, opts);
    if (opts.build_shmif) { arcan_a12.linkLibrary(arcan_shmif); arcan_a12.linkLibrary(arcan_shmif_server); }
    if (opts.build_a12) b.installArtifact(arcan_a12);
    const arcan_shmif_ext = createArcanShmifExt(b, opts);
    if (opts.build_shmif_ext) b.installArtifact(arcan_shmif_ext);

    // Install data directories
    const install_resources = b.addInstallDirectory(.{ .source_dir = b.path("data/resources"), .install_dir = .{ .custom = "share/arcan/resources" }, .install_subdir = "" });
    const install_scripts = b.addInstallDirectory(.{ .source_dir = b.path("data/scripts"), .install_dir = .{ .custom = "share/arcan/scripts" }, .install_subdir = "" });
    const install_appls = b.addInstallDirectory(.{ .source_dir = b.path("data/appl"), .install_dir = .{ .custom = "share/arcan/appl" }, .install_subdir = "" });

    // Install source tree for debug info
    const install_src = b.addInstallDirectory(.{ .source_dir = b.path("src"), .install_dir = .{ .custom = "src" }, .install_subdir = "" });

    // Bundled appls (durden, cat9)
    // Policy: install upstream durden as-is. Any fix or debug hook we need
    // goes in via a SMALL, NAMED overlay file placed next to this block —
    // not a wholesale fork of the tree. The prior monolithic overlay at
    // src/sel4-zig/durden_appl/ was deleted in favour of this approach so
    // we stay reviewable against upstream and so our "shmif-monitoring-style"
    // probes can land as isolated drop-ins rather than diffs against a
    // quietly-drifting fork.
    const install_durden = if (b.lazyDependency("durden", .{})) |dep| blk: {
        const dir_step = b.addInstallDirectory(.{ .source_dir = dep.path("durden"), .install_dir = .{ .custom = "share/arcan/appl/durden" }, .install_subdir = "" });
        // Engine builtin Lua files (debug/string/table/keyboard/mouse/json/…)
        // live in data/scripts/builtin and are NOT included with the durden
        // package. Durden expects them at appl/durden/builtin/ (top-level
        // system_load in durden.lua) AND at resources/builtin/ (shared with
        // welcome/console etc).
        const install_builtins_appl = b.addInstallDirectory(.{ .source_dir = b.path("data/scripts/builtin"), .install_dir = .{ .custom = "share/arcan/appl/durden/builtin" }, .install_subdir = "" });
        install_builtins_appl.step.dependOn(&dir_step.step);
        const install_builtins_shared = b.addInstallDirectory(.{ .source_dir = b.path("data/scripts/builtin"), .install_dir = .{ .custom = "share/arcan/resources/builtin" }, .install_subdir = "" });
        install_builtins_shared.step.dependOn(&install_builtins_appl.step);
        // JetBrains Mono Variable as the ONLY font (GPU Slug renderer
        // contract — we do not fall back to bitmap/TTF raster). Overwrites
        // every font file durden ships with the variable one so aliased
        // names keep resolving.
        const jb_font = b.path("data/resources/fonts/jetbrain_variable.font");
        const font_targets = [_][]const u8{ "default.ttf", "hack.ttf", "emoji.ttf", "hyperlegible.otf" };
        var last_step: *std.Build.Step = &install_builtins_shared.step;
        for (font_targets) |fname| {
            const step = b.addInstallFile(jb_font, b.fmt("share/arcan/appl/durden/fonts/{s}", .{fname}));
            step.step.dependOn(last_step);
            last_step = &step.step;
        }
        // Durden overlay: small, named drop-ins that land atop upstream
        // durden. Each file is one ~self-contained patch; this keeps our
        // changes reviewable against upstream and makes it obvious when
        // an "overlay" is a debug aid vs a legitimate fix.
        const install_overlay_autorun = b.addInstallFile(
            b.path("data/scripts/durden_overlay/autorun.lua"),
            "share/arcan/appl/durden/autorun.lua",
        );
        install_overlay_autorun.step.dependOn(last_step);
        // bug 0017: suppl.lua holds the bug 0006 math.floor coercion
        // around string.utf8ralign before passing to string.sub —
        // without this, the firstrun-wizard text input crashes Lua.
        const install_overlay_suppl = b.addInstallFile(
            b.path("data/scripts/durden_overlay/suppl.lua"),
            "share/arcan/appl/durden/suppl.lua",
        );
        install_overlay_suppl.step.dependOn(&install_overlay_autorun.step);
        // bug 0021: browse.lua's load_image_asynch callback expects
        // status as a TABLE; defensive `type(status) == "table"` guard
        // prevents an arcan-killing chain (lua runtime error → alt_call
        // → bug 0008 alignment panic) on previewable file selection.
        const install_overlay_browse = b.addInstallFile(
            b.path("data/scripts/durden_overlay/browse.lua"),
            "share/arcan/appl/durden/menus/browse.lua",
        );
        install_overlay_browse.step.dependOn(&install_overlay_suppl.step);
        break :blk &install_overlay_browse.step;
    } else null;
    const install_cat9 = if (b.lazyDependency("cat9", .{})) |dep| blk: {
        const cat9_dir = b.addInstallDirectory(.{ .source_dir = dep.path("."), .install_dir = .{ .custom = "share/arcan/appl/durden/lash" }, .install_subdir = "", .exclude_extensions = &.{ ".md", "LICENSE" } });
        const wrapper = b.addWriteFiles();
        _ = wrapper.add("default.lua",
            \\-- generated by build.zig: load cat9 as default lash shell
            \\local path = lash.scriptdir .. "cat9.lua"
            \\local fn, err = loadfile(path)
            \\if fn then return fn()
            \\else table.insert(lash.messages, "cat9 load error: " .. tostring(err)) end
            \\
        );
        // Override dev.lua descriptor: cat9.lua's load_builtins("dev")
        // ALWAYS pre-loads the default set first (line 207-209), so we
        // do NOT need to re-list ../default/* here — that caused dispatch
        // breakage on this build (shell-jobs stopped firing). Just system
        // bridges + the dev-specific files.
        _ = wrapper.add("cat9/dev.lua",
            \\return {
            \\  '../system/cd.lua',
            \\  '../system/term.lua',
            \\  'scm.lua',
            \\  'debug.lua',
            \\  'build.lua',
            \\  'graph.lua',
            \\  '_helpers.lua',
            \\  'read.lua',
            \\  'head.lua',
            \\  'tail.lua',
            \\  'wc.lua',
            \\  'write.lua',
            \\  'paste.lua',
            \\  'edit.lua',
            \\  'grep.lua',
            \\  'glob.lua',
            \\  'find.lua',
            \\  'run.lua',
            \\  'zigbuild.lua',
            \\  'compile.lua',
            \\  'git.lua',
            \\  'edits.lua',
            \\  'disasm.lua',
            \\  'sheet.lua',
            \\  'selfhost.lua',
            \\  'bugs.lua',
            \\  'metrics.lua',
            \\  'hilbert.lua',
            \\  'snippets.lua',
            \\  'dashboard.lua',
            \\  'dwarf.lua',
            \\  'dietree.lua',
            \\  'atlas.lua',
            \\  'memcloud.lua',
            \\  'diegraph.lua',
            \\  'time.lua',
            \\  'refactor.lua',
            \\  'status.lua',
            \\  'proc.lua',
            \\  'fs.lua',
            \\  'screenshot.lua',
            \\  'bun.lua',
            \\  'claude.lua',
            \\  'region.lua',
            \\  'fossil.lua',
            \\}
            \\
        );
        // Generate build.lua with embedded source/zig paths
        // Pipeworld-like: each build/run spawns a tied terminal window (handover
        // with join-r hint) so every stage is a visible cell in the tiler.
        _ = wrapper.add("cat9/dev/build.lua", b.fmt(
            \\return
            \\function(cat9, root, builtins, suggest, views, builtin_cfg)
            \\local srcdir = "{s}"
            \\local zigbin = "{s}"
            \\local outdir = srcdir .. "/zig-out"
            \\local lwa_bin = outdir .. "/bin/arcan"
            \\
            \\local function escape_cell(v)
            \\  local s = tostring(v)
            \\  s = string.gsub(s, '"', '\\"')
            \\  return string.format('"%s"', s)
            \\end
            \\
            \\local function make_spread(title, headers, rows)
            \\  local ob = cat9.builtin_name
            \\  cat9.builtins["builtin"]("spreadsheet")
            \\  cat9.parse_string(cat9.readline, "new")
            \\  local spread = cat9.latestjob
            \\  if not spread then
            \\    cat9.add_message("build: spreadsheet builtin not available")
            \\    cat9.builtins["builtin"](ob)
            \\    return
            \\  end
            \\  spread.short = title
            \\  local hdr_parts = {{}}
            \\  for _, h in ipairs(headers) do table.insert(hdr_parts, escape_cell(h)) end
            \\  cat9.parse_string(cat9.readline,
            \\    string.format("insert #%d 1 %s", spread.id, table.concat(hdr_parts, " ")))
            \\  for i, row in ipairs(rows) do
            \\    local parts = {{}}
            \\    for _, v in ipairs(row) do table.insert(parts, escape_cell(v)) end
            \\    cat9.parse_string(cat9.readline,
            \\      string.format("insert #%d %d %s", spread.id, i + 1, table.concat(parts, " ")))
            \\  end
            \\  cat9.builtins["builtin"](ob)
            \\  return spread
            \\end
            \\
            \\-- Run build inline in cat9 cell. Output appears in current cell.
            \\-- When on_done is provided, fires on success (exit code 0).
            \\local function do_build(targets, on_done, build_opts)
            \\  build_opts = build_opts or {{}}
            \\  local argv = {{zigbin, "zig", "build"}}
            \\  for _, v in ipairs(targets) do table.insert(argv, v) end
            \\  local env = cat9.table_copy_shallow(cat9.env)
            \\  local old_dir = root:chdir()
            \\  root:chdir(build_opts.dir or srcdir)
            \\  local job = cat9.setup_shell_job(argv, "re", env,
            \\    "zig build " .. table.concat(targets, " "), {{close = true}})
            \\  if job then
            \\    job.short = "build:" .. (targets[1] or "default")
            \\    if on_done then
            \\      table.insert(job.hooks.on_finish, on_done)
            \\      table.insert(job.hooks.on_fail, function()
            \\        cat9.add_message("build failed: " .. table.concat(targets, " "))
            \\      end)
            \\    end
            \\  end
            \\  root:chdir(old_dir)
            \\  return job
            \\end
            \\
            \\-- target name -> output path mapping (relative to zig-out)
            \\local target_outputs = {{
            \\  ["arcan_vk"]         = "bin/arcan_vk",
            \\  ["arcan_frameserver"]= "bin/arcan_frameserver",
            \\  ["afsrv_terminal"]   = "bin/afsrv_terminal",
            \\  ["arcan_db"]         = "bin/arcan_db",
            \\  ["afsrv_decode"]     = "bin/afsrv_decode",
            \\  ["afsrv_encode"]     = "bin/afsrv_encode",
            \\  ["afsrv_net"]        = "bin/afsrv_net",
            \\  ["afsrv_remoting"]   = "bin/afsrv_remoting",
            \\  ["afsrv_game"]       = "bin/afsrv_game",
            \\  ["afsrv_avfeed"]     = "bin/afsrv_avfeed",
            \\  ["afsrv_bun"]        = "bin/afsrv_bun",
            \\  ["aclip"]            = "bin/aclip",
            \\  ["shmmon"]           = "bin/shmmon",
            \\  ["acfgfs"]           = "bin/acfgfs",
            \\  ["arcan_shmif"]      = "lib/libarcan_shmif.a",
            \\  ["arcan_shmif_server"]="lib/libarcan_shmif_server.a",
            \\  ["arcan_tui"]        = "lib/libarcan_tui.a",
            \\  ["arcan_a12"]        = "lib/libarcan_a12.a",
            \\  ["arcan_shmif_ext"]  = "lib/libarcan_shmif_ext.a",
            \\  ["xarcan"]           = "bin/Xarcan",
            \\  ["init"]             = "bin/init",
            \\  ["callgraph"]        = "bin/callgraph",
            \\}}
            \\
            \\local function file_age(path)
            \\  local f = io.open(path, "r")
            \\  if not f then return nil end
            \\  f:close()
            \\  return true
            \\end
            \\
            \\local function parse_zig_help(lines)
            \\  local opts = {{}}
            \\  local integrations = {{}}
            \\  local targets = {{}}
            \\  local section = ""
            \\  for _, line in ipairs(lines) do
            \\    if line:match("^Steps:") then section = "steps"
            \\    elseif line:match("^Project%-Specific Options:") then section = "opts"
            \\    elseif line:match("^System Integration Options:") then section = "sysint"
            \\    elseif line:match("^Available System Integrations:") then section = "avail"
            \\    elseif line:match("^General Options:") then section = "general"
            \\    elseif line:match("^Advanced Options:") then section = "advanced"
            \\    elseif section == "steps" then
            \\      local name, desc = line:match("^%s+(%S+).-(%u.+)")
            \\      if name then table.insert(targets, {{name, desc}}) end
            \\    elseif section == "opts" then
            \\      local name, typ, desc = line:match("^%s+%-D(%S+)=%[(%a+)%]%s+(.*)")
            \\      if name then
            \\        local def = desc:match("%(default:%s*(.-)%)")
            \\        table.insert(opts, {{name, typ, def or "", desc:gsub("%s*%(default:.-%)",""):gsub("^%s+",""):gsub("%s+$","")}})
            \\      end
            \\    elseif section == "avail" then
            \\      local pkg, enabled = line:match("^%s+(%S+)%s+(yes.*)")
            \\      if not pkg then pkg, enabled = line:match("^%s+(%S+)%s+(no.*)") end
            \\      if pkg then table.insert(integrations, {{pkg, enabled}}) end
            \\    end
            \\  end
            \\  return targets, opts, integrations
            \\end
            \\
            \\local function do_config()
            \\  local argv = {{zigbin, "zig", "build", "--help"}}
            \\  local old_dir = root:chdir()
            \\  root:chdir(srcdir)
            \\  local _, outf, errf, pid = root:popen(argv, "re")
            \\  root:chdir(old_dir)
            \\  if not pid then
            \\    cat9.add_message("build config: could not run zig build --help")
            \\    return
            \\  end
            \\  local lines = {{}}
            \\  local job = cat9.add_background_job(outf, pid, {{lf_strip = true, err = errf}},
            \\    function(job, code)
            \\      if code ~= 0 then
            \\        cat9.add_message("build config: zig build --help exited " .. tostring(code))
            \\        return
            \\      end
            \\      local targets, opts, integrations = parse_zig_help(lines)
            \\
            \\      -- targets spreadsheet with built/not-built status
            \\      local trows = {{}}
            \\      for _, t in ipairs(targets) do
            \\        local opath = target_outputs[t[1]]
            \\        local status = ""
            \\        if opath then
            \\          local full = outdir .. "/" .. opath
            \\          status = file_age(full) and "built" or ""
            \\        end
            \\        table.insert(trows, {{t[1], status, opath or "", t[2]}})
            \\      end
            \\      make_spread("Build Targets",
            \\        {{"Target", "Status", "Output", "Description"}}, trows)
            \\
            \\      -- options spreadsheet
            \\      make_spread("Build Options",
            \\        {{"Option", "Type", "Default", "Description"}}, opts)
            \\
            \\      -- system integrations spreadsheet
            \\      if #integrations > 0 then
            \\        make_spread("System Integrations",
            \\          {{"Package", "Enabled"}}, integrations)
            \\      end
            \\    end)
            \\  table.insert(job.hooks.on_data, function(line)
            \\    if line then table.insert(lines, line) end
            \\  end)
            \\end
            \\
            \\local function lwa_env()
            \\  local env = cat9.table_copy_shallow(cat9.env)
            \\  env["ARCAN_APPLBASEPATH"] = outdir .. "/share/arcan/appl"
            \\  env["ARCAN_RESOURCEPATH"] = outdir .. "/share/arcan/resources"
            \\  env["ARCAN_SCRIPTPATH"]   = outdir .. "/share/arcan/scripts"
            \\  env["ARCAN_BINPATH"]      = outdir .. "/bin/arcan_frameserver"
            \\  env["ARCAN_LIBPATH"]      = outdir .. "/lib"
            \\  return env
            \\end
            \\
            \\local function parse_mode(args)
            \\  local cmode = "embed"
            \\  if type(args[1]) == "table" and args[1].parg then
            \\    local t = table.remove(args, 1)
            \\    for _, v in ipairs(t) do
            \\      if v == "v" then cmode = "join-d"
            \\      elseif v == "h" then cmode = "join-r"
            \\      elseif v == "tab" then cmode = "tab"
            \\      elseif v == "embed" then cmode = "embed"
            \\      end
            \\    end
            \\  end
            \\  return cmode
            \\end
            \\
            \\builtins.hint["build"] = "Build arcan inline (zig build [target...] | run | xarcan | config)"
            \\function builtins.build(...)
            \\  local args = {{...}}
            \\  local set = {{}}
            \\  local ok, msg = cat9.expand_arg(set, args)
            \\  if not ok then return false, msg end
            \\
            \\  local cmode = parse_mode(set)
            \\
            \\  if set[1] == "config" then return do_config() end
            \\
            \\  -- "build run [appl]": build inline, then launch LWA compositor embedded.
            \\  -- "build (h) run durden": tile LWA to the right instead of embed.
            \\  if set[1] == "run" then
            \\    local appl = set[2] or "durden"
            \\    return do_build({{}}, function()
            \\      cat9.shmif_handover(cmode, "e", lwa_bin, lwa_env(),
            \\        {{"arcan(lwa:" .. appl .. ")", appl}})
            \\    end)
            \\  end
            \\
            \\  -- "build xarcan [app]": build Xarcan then launch embedded.
            \\  if set[1] == "xarcan" then
            \\    local xapp = set[2] or "xterm"
            \\    return do_build({{"-Dbuild_xarcan=true", "xarcan"}}, function()
            \\      local env = cat9.table_copy_shallow(cat9.env)
            \\      cat9.shmif_handover(cmode, "e", outdir .. "/bin/Xarcan", env,
            \\        {{"Xarcan", "-ac", "-retro", xapp}})
            \\    end)
            \\  end
            \\
            \\  -- "build [target...]": build inline in cat9 cell
            \\  return do_build(set)
            \\end
            \\
            \\builtins.hint["game"] = "Launch app via gamescope (game [app...])"
            \\function builtins.game(...)
            \\  local args = {{...}}
            \\  local set = {{}}
            \\  local ok, msg = cat9.expand_arg(set, args)
            \\  if not ok then return false, msg end
            \\
            \\  local cmode = parse_mode(set)
            \\  local gs_args = {{}}
            \\  for _, v in ipairs(set) do table.insert(gs_args, v) end
            \\  if #gs_args == 0 then gs_args = {{"chromium-browser"}} end
            \\
            \\  -- gamescope is built from the build_llvm/ sub-tree (LLVM-only
            \\  -- target). Output lands in build_llvm/zig-out/bin/gamescope.
            \\  return do_build({{"gamescope"}}, function()
            \\    local env = cat9.table_copy_shallow(cat9.env)
            \\    local argv = {{"gamescope", "--backend", "arcan", "-W", "1920", "-H", "1080", "--"}}
            \\    for _, a in ipairs(gs_args) do table.insert(argv, a) end
            \\    cat9.shmif_handover(cmode, "e",
            \\      srcdir .. "/build_llvm/zig-out/bin/gamescope", env, argv)
            \\  end, {{dir = srcdir .. "/build_llvm"}})
            \\end
            \\
            \\function suggest.build(args, raw)
            \\  if #args == 2 then
            \\    local targets = {{
            \\      "config", "run", "xarcan", "test-shmif",
            \\      "arcan-db",
            \\      "afsrv-terminal", "afsrv-decode", "afsrv-encode", "afsrv-net",
            \\      "afsrv-game", "afsrv-avfeed", "afsrv-cat9-viz", "afsrv-remoting",
            \\      "aclip", "shmmon", "acfgfs",
            \\      hint = {{
            \\        "Show build options/targets/integrations as spreadsheets",
            \\        "Build + launch nested arcan embedded",
            \\        "Build + launch X11 server embedded",
            \\        "Run shmif test suite",
            \\        "Database tool",
            \\        "Terminal frameserver", "Decode frameserver", "Encode frameserver",
            \\        "Network frameserver", "Game frameserver", "A/V feed frameserver",
            \\        "Remoting frameserver",
            \\        "Clipboard tool", "Image viewer", "Shared memory monitor", "FUSE config FS",
            \\      }}
            \\    }}
            \\    cat9.readline:suggest(cat9.prefix_filter(targets, args[#args]), "word")
            \\  elseif #args == 3 and args[2] == "run" then
            \\    cat9.readline:suggest({{"durden", hint = {{"Durden desktop"}}}}, "word")
            \\  elseif #args == 3 and args[2] == "xarcan" then
            \\    cat9.readline:suggest({{"xterm", "xclock", "xeyes", hint = {{"Terminal emulator", "Clock widget", "Eyes widget"}}}}, "word")
            \\  end
            \\end
            \\
            \\function suggest.game(args, raw)
            \\  if #args == 2 then
            \\    cat9.readline:suggest({{"chromium-browser", "steam", "firefox",
            \\      hint = {{"Chromium browser", "Steam client", "Firefox browser"}}}}, "word")
            \\  end
            \\end
            \\
            \\end
            \\
        , .{ b.build_root.path orelse ".", b.graph.zig_exe }));
        // Generate graph.lua — callgraph → spreadsheet interactive traversal
        _ = wrapper.add("cat9/dev/graph.lua", b.fmt(
            \\return
            \\function(cat9, root, builtins, suggest, views, builtin_cfg)
            \\local srcdir = "{s}"
            \\local cfg = builtin_cfg.graph or {{}}
            \\local depth_limit = cfg.caller_depth or 4
            \\local nodes = {{}}
            \\local file_index = {{}}
            \\local name_index = {{}}
            \\local callers = {{}}
            \\local callees = {{}}
            \\local loaded = false
            \\local loading = false
            \\local current_file = nil
            \\
            \\local function parse_dot_line(line)
            \\  if not line or #line == 0 then return end
            \\  local id = line:match('^%s*"([^"]+)"%s*%[')
            \\  if id then
            \\    local name = id:match(':(.+)$') or id
            \\    local file = id:match('^(.+):') or current_file or ""
            \\    local is_export = line:match('fillcolor="#4a90d9"') ~= nil
            \\    local is_pub = line:match('fillcolor="#7ab648"') ~= nil
            \\    nodes[id] = {{id = id, name = name, file = file, export = is_export, pub = is_pub}}
            \\    if not file_index[file] then file_index[file] = {{}} end
            \\    table.insert(file_index[file], id)
            \\    if not name_index[name] then name_index[name] = {{}} end
            \\    table.insert(name_index[name], id)
            \\    return
            \\  end
            \\  local from, to = line:match('"([^"]+)"%s*%->%s*"([^"]+)"')
            \\  if from and to then
            \\    if not callees[from] then callees[from] = {{}} end
            \\    table.insert(callees[from], to)
            \\    if not callers[to] then callers[to] = {{}} end
            \\    table.insert(callers[to], from)
            \\    return
            \\  end
            \\  local file = line:match('^%s*label="([^"]+)"')
            \\  if file then current_file = file end
            \\end
            \\
            \\local function load_graph(then_cb)
            \\  if loading then return end
            \\  nodes = {{}}; file_index = {{}}; name_index = {{}}; callers = {{}}; callees = {{}}
            \\  current_file = nil; loaded = false; loading = true
            \\  local cmd = string.format("cd %s && zig-out/bin/callgraph --scan", srcdir)
            \\  local _, outf, errf, pid = root:popen({{"/bin/sh", "/bin/sh", "-c", cmd}}, "re")
            \\  if not pid then
            \\    cat9.add_message("graph: could not spawn callgraph (build callgraph first)")
            \\    loading = false
            \\    return
            \\  end
            \\  local job = cat9.add_background_job(outf, pid, {{lf_strip = true, err = errf}},
            \\    function(job, code)
            \\      loading = false
            \\      if code ~= 0 then
            \\        cat9.add_message("graph: callgraph exited with code " .. tostring(code))
            \\        return
            \\      end
            \\      loaded = true
            \\      local nc, ec, fc = 0, 0, 0
            \\      for _ in pairs(nodes) do nc = nc + 1 end
            \\      for _, v in pairs(callees) do ec = ec + #v end
            \\      for _ in pairs(file_index) do fc = fc + 1 end
            \\      cat9.add_message(string.format("graph: %d functions, %d edges, %d files", nc, ec, fc))
            \\      if then_cb then then_cb() end
            \\    end)
            \\  table.insert(job.hooks.on_data, function(line) if line then parse_dot_line(line) end end)
            \\end
            \\
            \\local function escape_cell(v)
            \\  local s = tostring(v)
            \\  s = string.gsub(s, '"', '\\"')
            \\  return string.format('"%s"', s)
            \\end
            \\
            \\local function make_spread(title, headers, rows)
            \\  local ob = cat9.builtin_name
            \\  cat9.builtins["builtin"]("spreadsheet")
            \\  cat9.parse_string(cat9.readline, "new")
            \\  local spread = cat9.latestjob
            \\  if not spread then
            \\    cat9.add_message("graph: spreadsheet builtin not available")
            \\    cat9.builtins["builtin"](ob)
            \\    return
            \\  end
            \\  spread.short = title
            \\  local hdr_parts = {{}}
            \\  for _, h in ipairs(headers) do table.insert(hdr_parts, escape_cell(h)) end
            \\  cat9.parse_string(cat9.readline,
            \\    string.format("insert #%d 1 %s", spread.id, table.concat(hdr_parts, " ")))
            \\  for i, row in ipairs(rows) do
            \\    local parts = {{}}
            \\    for _, v in ipairs(row) do table.insert(parts, escape_cell(v)) end
            \\    cat9.parse_string(cat9.readline,
            \\      string.format("insert #%d %d %s", spread.id, i + 1, table.concat(parts, " ")))
            \\  end
            \\  cat9.builtins["builtin"](ob)
            \\  return spread
            \\end
            \\
            \\local function bfs_traverse(start_id, index)
            \\  local visited = {{[start_id] = true}}
            \\  local queue = {{{{id = start_id, depth = 0}}}}
            \\  local results = {{{{0, nodes[start_id].name, nodes[start_id].file, "-"}}}}
            \\  local qi = 1
            \\  while qi <= #queue do
            \\    local cur = queue[qi]; qi = qi + 1
            \\    if cur.depth < depth_limit then
            \\      for _, nid in ipairs(index[cur.id] or {{}}) do
            \\        if not visited[nid] then
            \\          visited[nid] = true
            \\          table.insert(queue, {{id = nid, depth = cur.depth + 1}})
            \\          local n = nodes[nid]
            \\          local via = nodes[cur.id] and nodes[cur.id].name or cur.id
            \\          if n then table.insert(results, {{cur.depth + 1, n.name, n.file, via}})
            \\          else table.insert(results, {{cur.depth + 1, nid, "?", via}}) end
            \\        end
            \\      end
            \\    end
            \\  end
            \\  return results
            \\end
            \\
            \\local function resolve_ids(name)
            \\  if name:find(":") then
            \\    if nodes[name] then return {{name}} end
            \\    return nil
            \\  end
            \\  return name_index[name]
            \\end
            \\
            \\local cmds = {{}}
            \\
            \\function cmds.overview()
            \\  local function show()
            \\    local files = {{}}
            \\    for path, ids in pairs(file_index) do
            \\      local exp = 0; local in_e, out_e = 0, 0
            \\      for _, id in ipairs(ids) do
            \\        if nodes[id] and nodes[id].export then exp = exp + 1 end
            \\        in_e = in_e + #(callers[id] or {{}})
            \\        out_e = out_e + #(callees[id] or {{}})
            \\      end
            \\      table.insert(files, {{path, #ids, exp, in_e, out_e}})
            \\    end
            \\    table.sort(files, function(a, b) return a[4] > b[4] end)
            \\    make_spread("Call Graph: Files",
            \\      {{"File", "Funcs", "Exported", "In-Edges", "Out-Edges"}}, files)
            \\  end
            \\  if loaded then show() else load_graph(show) end
            \\end
            \\
            \\function cmds.file(pattern)
            \\  if not loaded then return load_graph(function() cmds.file(pattern) end) end
            \\  local rows = {{}}
            \\  for path, ids in pairs(file_index) do
            \\    if path:find(pattern) then
            \\      for _, id in ipairs(ids) do
            \\        local n = nodes[id]
            \\        if n then
            \\          table.insert(rows, {{n.name, n.file,
            \\            n.export and "exp" or (n.pub and "pub" or ""),
            \\            #(callers[id] or {{}}), #(callees[id] or {{}})}})
            \\        end
            \\      end
            \\    end
            \\  end
            \\  table.sort(rows, function(a, b) return a[4] > b[4] end)
            \\  make_spread("Functions: " .. pattern,
            \\    {{"Function", "File", "Vis", "Callers", "Callees"}}, rows)
            \\end
            \\
            \\function cmds.callers(name)
            \\  if not loaded then return load_graph(function() cmds.callers(name) end) end
            \\  local ids = resolve_ids(name)
            \\  if not ids or #ids == 0 then
            \\    cat9.add_message("graph: not found: " .. name); return
            \\  end
            \\  if #ids > 1 then
            \\    local rows = {{}}
            \\    for _, id in ipairs(ids) do
            \\      local n = nodes[id]
            \\      if n then table.insert(rows, {{n.name, n.file, n.id}}) end
            \\    end
            \\    make_spread("Ambiguous: " .. name, {{"Function", "File", "ID"}}, rows)
            \\    cat9.add_message("Multiple matches — use qualified id: graph callers file:func")
            \\    return
            \\  end
            \\  make_spread("Callers of " .. name,
            \\    {{"Depth", "Function", "File", "Via"}}, bfs_traverse(ids[1], callers))
            \\end
            \\
            \\function cmds.callees(name)
            \\  if not loaded then return load_graph(function() cmds.callees(name) end) end
            \\  local ids = resolve_ids(name)
            \\  if not ids or #ids == 0 then
            \\    cat9.add_message("graph: not found: " .. name); return
            \\  end
            \\  if #ids > 1 then
            \\    local rows = {{}}
            \\    for _, id in ipairs(ids) do
            \\      local n = nodes[id]
            \\      if n then table.insert(rows, {{n.name, n.file, n.id}}) end
            \\    end
            \\    make_spread("Ambiguous: " .. name, {{"Function", "File", "ID"}}, rows)
            \\    cat9.add_message("Multiple matches — use qualified id: graph callees file:func")
            \\    return
            \\  end
            \\  make_spread("Callees of " .. name,
            \\    {{"Depth", "Function", "File", "Via"}}, bfs_traverse(ids[1], callees))
            \\end
            \\
            \\function cmds.search(pattern)
            \\  if not loaded then return load_graph(function() cmds.search(pattern) end) end
            \\  local rows = {{}}
            \\  for name, ids in pairs(name_index) do
            \\    if name:find(pattern) then
            \\      for _, id in ipairs(ids) do
            \\        local n = nodes[id]
            \\        if n then
            \\          table.insert(rows, {{n.name, n.file,
            \\            n.export and "exp" or (n.pub and "pub" or ""),
            \\            #(callers[id] or {{}}), #(callees[id] or {{}})}})
            \\        end
            \\      end
            \\    end
            \\  end
            \\  table.sort(rows, function(a, b) return a[4] > b[4] end)
            \\  make_spread("Search: " .. pattern,
            \\    {{"Function", "File", "Vis", "Callers", "Callees"}}, rows)
            \\end
            \\
            \\function cmds.reload()
            \\  loaded = false
            \\  load_graph(function() cat9.add_message("graph: reloaded") end)
            \\end
            \\
            \\suggest.graph = function(args, raw)
            \\  if #args == 2 then
            \\    local set = {{"callers", "callees", "search", "reload"}}
            \\    if loaded then
            \\      for path in pairs(file_index) do table.insert(set, path) end
            \\    end
            \\    cat9.readline:suggest(cat9.prefix_filter(set, args[2]), "word")
            \\  elseif #args == 3 and (args[2] == "callers" or args[2] == "callees" or args[2] == "search") then
            \\    if loaded then
            \\      local names = {{}}
            \\      for name in pairs(name_index) do table.insert(names, name) end
            \\      table.sort(names)
            \\      cat9.readline:suggest(cat9.prefix_filter(names, args[3]), "word")
            \\    end
            \\  end
            \\end
            \\
            \\builtins.hint.graph = "Callgraph explorer: functions, callers, callees"
            \\function builtins.graph(cmd, ...)
            \\  if not cmd then return cmds.overview() end
            \\  if cmd == "callers" then
            \\    local a = {{...}}; if not a[1] then cat9.add_message("graph callers <func>"); return end
            \\    return cmds.callers(a[1])
            \\  end
            \\  if cmd == "callees" then
            \\    local a = {{...}}; if not a[1] then cat9.add_message("graph callees <func>"); return end
            \\    return cmds.callees(a[1])
            \\  end
            \\  if cmd == "search" then
            \\    local a = {{...}}; if not a[1] then cat9.add_message("graph search <pattern>"); return end
            \\    return cmds.search(a[1])
            \\  end
            \\  if cmd == "reload" then return cmds.reload() end
            \\  return cmds.file(cmd)
            \\end
            \\
            \\end
            \\
        , .{b.build_root.path orelse "."}));
        // Override config/dev.lua to add graph config section
        _ = wrapper.add("cat9/config/dev.lua",
            \\return {
            \\  graph = { caller_depth = 4 },
            \\  scm = {
            \\    heading = {bc = tui.colors.text, fc= tui.colors.ref_yellow, border_down = true},
            \\    passive_heading = {bc = tui.colors.text, fc= tui.colors.ref_yellow},
            \\    error_heading = {bc = tui.colors.alert, fc = tui.colors.alert},
            \\    action = {bc = tui.colors.text, fc = tui.colors.ref_green},
            \\    strong_action = {bc = tui.colors.ref_red, fc = tui.colors.text},
            \\    data = {bc = tui.colors.text, fc = tui.colors.text},
            \\    time_format = "%y-%m-%d %H:%M",
            \\    timeline_cap = 100,
            \\    ticket_filters = {
            \\      Open = "status == 'Open'", Fixed = "status == 'Fixed'", Closed = "status == 'Closed'"
            \\    },
            \\    ticket_status = {"Open","Verify","Review","Deferred","Fixed","Tested","Closed"},
            \\    ticket_type = {"Code_Defect","Build_Problem","Documentation","Feature_Request","Incident"},
            \\    ticket_priority = {"Immediate","High","Medium","Low","Zero"},
            \\    ticket_severity = {"Critical","Severe","Important","Minor","Cosmetic"},
            \\    ticket_resolution = {
            \\      "Open","Fixed","Rejected","Workaround","Unable_To_Reproduce",
            \\      "Works_As_Designed","External_Bug","Not_A_Bug","Duplicate",
            \\      "Overcome_By_Events","Drive_By_Patch","Misconfiguration"
            \\    },
            \\    ticket_new_fields = {"version","title","type","subsystem","comment","severity"},
            \\    exclude = { EXTRA = {"^build"} },
            \\    edit_action = "s!(nokeep) vim",
            \\    commit_action = "s!(nokeep) fossil commit",
            \\    ticket_columns = {"date","title","severity","type"},
            \\    ticket_heading = {bc = tui.colors.text, fc = tui.colors.ref_yellow}
            \\  },
            \\  debug = {
            \\    arcan_default_mode = "split-r",
            \\    dap_default = {"gdb","gdb","-i","dap","-q"},
            \\    dap_create = {},
            \\    log_in = "/tmp/arcan.log",
            \\    dap_id = {"gdb"},
            \\    default_views = {"stderr","stdout","threads","errors"},
            \\    hide_while_runnning = false,
            \\    thread = {bc = tui.colors.text, fc = tui.colors.text},
            \\    thread_expanded = {bc = tui.colors.text, fc = tui.colors.text},
            \\    thread_selected = {bc = tui.colors.alert, fc = tui.colors.text, border_down = true},
            \\    source_line = {bc = tui.colors.text, fc = tui.colors.text},
            \\    breakpoint_line = {bc = tui.colors.ref_red, fc = tui.colors.text},
            \\    disassembly = {bc = tui.colors.text, fc = tui.colors.text},
            \\    disassembly_selected = {bc = tui.colors.alert, fc = tui.colors.text, border_down = true},
            \\    file = {bc = tui.colors.text, fc = tui.colors.text},
            \\    file_selected = {bc = tui.colors.alert, fc = tui.colors.text, border_down = true},
            \\    register = {fc = tui.colors.ref_green, bc = tui.colors.text},
            \\    register_value = {fc = tui.colors.ref_red, bc = tui.colors.text},
            \\    variable = {bc = tui.colors.text, fc = tui.colors.text},
            \\    reggroups = {
            \\      general = {
            \\        "rax","rbx","rcx","rdx","rsi","rrdi","rbp","rsp",
            \\        "r8","r9","r10","r11","r12","r13","r14","r15","rip","eflags"
            \\      },
            \\      segment = {"cs","ss","ds","es","fs","gs","fs_base","gs_base"},
            \\      floating_point = {
            \\        "st0","st1","st2","st3","st4","st5","st6","st7",
            \\        "fctrl","fstat","ftag","fiseg","fioff","foseg","fooff","fop","mxcsr"
            \\      },
            \\      vector = {"ymm%d+"}
            \\    },
            \\    options = {
            \\      "set disassembly-flavor intel",
            \\      "set debug dap-log-file /tmp/dap.log"
            \\    }
            \\  }
            \\}
            \\
        );
        const install_wrapper = b.addInstallDirectory(.{ .source_dir = wrapper.getDirectory(), .install_dir = .{ .custom = "share/arcan/appl/durden/lash" }, .install_subdir = "" });
        install_wrapper.step.dependOn(&cat9_dir.step);

        // bug 0017: cat9 overlays — durable in-tree home for two patches
        // that previously lived only in zig-out and got clobbered by every
        // clean rebuild because cat9 is a lazyDependency.
        //   lash_hem.lua: CAT9_INIT_CMD `|||`-delim splitter (bug 0013)
        //   lash_misc.lua: hist.meta OOB guard (bug 0012)
        const install_overlay_lash_hem = b.addInstallFile(
            b.path("data/scripts/durden_overlay/lash_hem.lua"),
            "share/arcan/appl/durden/lash/cat9.lua",
        );
        install_overlay_lash_hem.step.dependOn(&cat9_dir.step);
        install_wrapper.step.dependOn(&install_overlay_lash_hem.step);

        const install_overlay_lash_misc = b.addInstallFile(
            b.path("data/scripts/durden_overlay/lash_misc.lua"),
            "share/arcan/appl/durden/lash/cat9/base/misc.lua",
        );
        install_overlay_lash_misc.step.dependOn(&cat9_dir.step);
        install_wrapper.step.dependOn(&install_overlay_lash_misc.step);

        // Sibling test-instrumentation lash ruleset. Activated via
        // LASH_SHELL=cat9_test; loads stock cat9.lua and patches it to
        // emit native TUI MESSAGE events on each meaningful state
        // change. See data/scripts/hook/hem_test.lua for the hook
        // that drives a full functional test against this.
        const install_cat9_test = b.addInstallFile(
            b.path("data/lash/hem_test.lua"),
            "share/arcan/appl/durden/lash/cat9_test.lua",
        );
        // Pull cat9_test into the cat9 install pipeline so the
        // default-step → install_cat9 hookup at line ~1160 brings it in.
        install_wrapper.step.dependOn(&install_cat9_test.step);

        // Pure-Lua dev/ builtins from data/lash_builtins/cat9_dev/.
        // Each installs as cat9/dev/<name>.lua over the dep tree;
        // the dev.lua descriptor wrapper-add above lists them.
        const dev_builtins = [_][]const u8{
            "_helpers", "read",     "head",     "tail",  "wc",
            "write",    "paste",    "edit",     "grep",  "glob",  "find",
            "run",      "zigbuild", "compile",  "git",
            "edits",    "disasm",   "sheet",    "selfhost", "bugs",
            "metrics",  "hilbert",  "snippets", "dashboard",
            "dwarf",    "dietree",  "atlas",    "memcloud",
            "diegraph", "time",     "refactor",
            "status",   "proc",     "fs",       "screenshot",
            "bun",      "claude",
        };
        inline for (dev_builtins) |name| {
            const inst = b.addInstallFile(
                b.path(b.fmt("data/lash_builtins/cat9_dev/{s}.lua", .{name})),
                b.fmt("share/arcan/appl/durden/lash/cat9/dev/{s}.lua", .{name}),
            );
            install_wrapper.step.dependOn(&inst.step);
        }

        break :blk install_wrapper;
    } else null;

    // Compositor-side targets (arcan VK, frameservers, data dirs). Gated on
    // build_arcan_vk so `-Dbuild_arcan_vk=false` yields just the core libs
    // (shmif/shmif_server/tui/a12) — useful for bring-up on a new platform
    // before the compositor/frameserver substrate is ready.
    if (opts.build_arcan_vk) {
        const arcan_fs = createArcanFrameserver(b, opts);
        const install_fs = b.addInstallArtifact(arcan_fs, .{});
        const afsrv_term = createAfsrvTerminal(b, opts, arcan_shmif, arcan_shmif_server, arcan_tui);
        const install_term = b.addInstallArtifact(afsrv_term, .{});
        const afsrv_dec = createAfsrvDecode(b, opts, arcan_shmif, arcan_shmif_server, arcan_tui);
        const install_dec = b.addInstallArtifact(afsrv_dec, .{});

        const arcan_vk_exe = createArcanVk(b, opts, arcan_shmif, arcan_shmif_server);
        const install_exe = b.addInstallArtifact(arcan_vk_exe, .{});
        const default_step = b.getInstallStep();
        for ([_]*std.Build.Step{
            &install_exe.step, &install_fs.step, &install_term.step, &install_dec.step,
            &install_resources.step, &install_scripts.step, &install_appls.step, &install_src.step,
        }) |s| default_step.dependOn(s);
        if (install_durden) |s| default_step.dependOn(s);
        if (install_cat9) |s| default_step.dependOn(&s.step);

        // Run step: `zig build run -- [args]`
        const run_cmd = b.addRunArtifact(arcan_vk_exe);
        run_cmd.step.dependOn(b.getInstallStep());
        run_cmd.setCwd(.{ .cwd_relative = "zig-out" });
        if (b.args) |args| {
            run_cmd.addArgs(args);
        } else {
            run_cmd.addArgs(&.{ "-w", "2000", "-h", "1200", "durden" });
        }
        const run_step = b.step("run", "Run arcan Vulkan compositor (default: durden 2000x1200)");
        run_step.dependOn(&run_cmd.step);
    }

    // Ticket 0158 — surface silent install skips. addInstallDirectory
    // doesn't propagate EPERM when the destination is unwritable
    // (e.g. root-owned files from a prior sudo install — see ticket
    // 0157), so the install completes "successfully" but the appl /
    // resources / scripts trees diverge from data/. This step diffs
    // them after install and complains loudly.
    {
        // zig swallows BOTH stdout and stderr when an addSystemCommand
        // exits non-zero. Workaround: always tee the report to a stable
        // logfile (zig-out/check-install.log) so the user can read it
        // post-failure regardless of zig's output capture. The script's
        // own stdout (which DOES surface on exit 0) names the logfile.
        const check = b.addSystemCommand(&.{
            "sh", "-c",
            \\set -eu
            \\LOG="zig-out/check-install.log"
            \\mkdir -p zig-out
            \\: > "$LOG"
            \\drift=0
            \\for pair in 'data/appl share/arcan/appl' 'data/scripts share/arcan/scripts' 'data/resources share/arcan/resources'; do
            \\  src=$(echo $pair | awk '{print $1}')
            \\  dst="zig-out/$(echo $pair | awk '{print $2}')"
            \\  out=$(diff -rq "$src" "$dst" 2>&1 | grep -v '^Only in' || true)
            \\  if [ -n "$out" ]; then
            \\    echo "=== drift: $src vs $dst ===" >> "$LOG"
            \\    echo "$out" >> "$LOG"
            \\    echo "" >> "$LOG"
            \\    drift=$((drift + 1))
            \\  fi
            \\done
            \\if [ "$drift" -gt 0 ]; then
            \\  echo "check-install: $drift tree(s) drifted. Report at $LOG" >> "$LOG"
            \\  echo "" >> "$LOG"
            \\  echo "Likely cause: root-owned files in zig-out/ silently" >> "$LOG"
            \\  echo "skipped on user-level install (ticket 0157). For each" >> "$LOG"
            \\  echo "drifted file, run 'ls -la <path>' — if owner is root," >> "$LOG"
            \\  echo "chown to user and rerun 'zig build install'." >> "$LOG"
            \\  cat "$LOG" >&2 || true
            \\  echo "" >&2
            \\  echo "check-install FAILED. Full report: $LOG" >&2
            \\  exit 1
            \\fi
            \\echo "check-install: no drift, install tree mirrors source"
            ,
        });
        // Intentionally NOT dependOn(getInstallStep) — the diff is
        // useful even when install fails (e.g. transitive frameserver
        // compile errors blocking the install step entirely). Run it
        // standalone after a separate `zig build install`, or any time
        // you want to know if your source edits ever made it across.
        const check_step = b.step("check-install", "Diff source trees vs zig-out/share/arcan/ to catch silent install skips (ticket 0158)");
        check_step.dependOn(&check.step);
    }

    // GPU glyph test: `zig build test-gpu`
    // Runs the GPU Slug test suite via shell script (needs to kill arcan after readback).
    {
        const test_gpu = b.addSystemCommand(&.{
            "bash", "tests/render_pipeline/run_gpu_test.sh",
        });
        test_gpu.step.dependOn(b.getInstallStep());
        const test_gpu_step = b.step("test-gpu", "Run GPU Slug glyph comparison (variable fonts, full Vulkan pipeline)");
        test_gpu_step.dependOn(&test_gpu.step);
    }

    // Optional targets with simple step wiring
    const StepInfo = struct { flag: bool, name: []const u8, desc: []const u8, with_data: bool };
    const optional_targets = [_]StepInfo{
        .{ .flag = opts.build_arcan_db, .name = "arcan-db", .desc = "Build arcan_db database tool", .with_data = false },
        .{ .flag = opts.build_afsrv_decode, .name = "afsrv-decode", .desc = "Build afsrv_decode frameserver", .with_data = false },
        .{ .flag = opts.build_afsrv_terminal, .name = "afsrv-terminal", .desc = "Build afsrv_terminal frameserver", .with_data = false },
        .{ .flag = opts.build_afsrv_encode, .name = "afsrv-encode", .desc = "Build afsrv_encode frameserver", .with_data = false },
        .{ .flag = opts.build_afsrv_net, .name = "afsrv-net", .desc = "Build afsrv_net frameserver", .with_data = false },
        .{ .flag = opts.build_arcan_net, .name = "arcan-net", .desc = "Build arcan-net directory/bridge binary", .with_data = false },
        .{ .flag = opts.build_arcan_net_session, .name = "arcan-net-session", .desc = "Build arcan-net-session binary", .with_data = false },
        .{ .flag = opts.build_afsrv_remoting, .name = "afsrv-remoting", .desc = "Build afsrv_remoting frameserver", .with_data = false },
        .{ .flag = opts.build_afsrv_game, .name = "afsrv-game", .desc = "Build afsrv_game frameserver", .with_data = false },
        .{ .flag = opts.build_afsrv_avfeed, .name = "afsrv-avfeed", .desc = "Build afsrv_avfeed frameserver", .with_data = false },
        .{ .flag = opts.build_afsrv_bun, .name = "afsrv-bun", .desc = "Build afsrv_bun frameserver — embedded Bun host (Phase 2 skeleton; see bugs/0036)", .with_data = false },
        .{ .flag = opts.build_afsrv_probe, .name = "afsrv-probe", .desc = "Build afsrv_probe a12-coverage test frameserver", .with_data = false },
        .{ .flag = opts.build_aclip, .name = "aclip", .desc = "Build aclip clipboard tool", .with_data = false },
        .{ .flag = opts.build_shmmon, .name = "shmmon", .desc = "Build shmmon shared memory monitor", .with_data = false },
        .{ .flag = opts.build_acfgfs, .name = "acfgfs", .desc = "Build acfgfs FUSE config filesystem", .with_data = false },
    };
    const default_step = b.getInstallStep();
    for (optional_targets) |t| {
        if (!t.flag) continue;
        const exe = buildOptionalTarget(b, opts, t.name, arcan_shmif, arcan_shmif_server, arcan_tui, arcan_a12);
        const install = b.addInstallArtifact(exe, .{});
        const step = b.step(t.name, t.desc);
        step.dependOn(&install.step);
        if (t.with_data) {
            step.dependOn(&install_resources.step);
            step.dependOn(&install_scripts.step);
            step.dependOn(&install_appls.step);
        }
        default_step.dependOn(&install.step);
    }

    // The AGP vstore unit test (test-agp-vstore) went away with its C
    // harness (vk_shared_test.c had already been dropped from the tree).

    // arcan-wayland / xwm are gone and not coming back — X11 clients go
    // through Xarcan (below), everything else speaks shmif or a12.

    // qtarcan, gamescope, llama-cli targets and the Phase 3+ afsrv_bun
    // bun-link path live in build_llvm/. Build them with:
    //   cd build_llvm && zig build <target>
    // Top-level intentionally has no wiring or flags for those — see
    // build_llvm/build.zig{,.zon}.

    // xarcan
    if (opts.build_xarcan) {
        if (build_xarcan.createXarcan(b, opts.target, opts.optimize, arcan_shmif)) |exe| {
            const install = b.addInstallArtifact(exe, .{});
            const step = b.step("xarcan", "Build Xarcan X server with arcan backend");
            step.dependOn(&install.step);
            if (build_all) default_step.dependOn(&install.step);
        }
    }

    // Desktop integration shell profile
    {
        const install_profile = b.addInstallFile(
            b.path("data/share/arcan/arcan-desktop.sh"),
            "share/arcan/arcan-desktop.sh",
        );
        default_step.dependOn(&install_profile.step);
    }

    // callgraph tool
    {
        const callgraph_exe = b.addExecutable(.{ .use_llvm = use_llvm_default,
            .name = "callgraph",
            .root_module = b.createModule(.{
                .root_source_file = b.path("scripts/callgraph.zig"),
                .target = opts.target,
                .optimize = opts.optimize,
            }),
        });
        const install = b.addInstallArtifact(callgraph_exe, .{});
        const callgraph_step = b.step("callgraph", "Build call graph analyzer (outputs DOT/JSON)");
        callgraph_step.dependOn(&install.step);
        b.getInstallStep().dependOn(&install.step);
    }

    // Tests
    {
        if (opts.build_shmif) buildShmifTests(b, opts, arcan_shmif, arcan_shmif_server);
        buildTtfTests(b, opts);
        if (opts.build_ghostty_tests) buildGhosttyBridgeTests(b, opts);
        buildSlugTests(b, opts);
    }
}

/// Dispatch table for optional targets that need custom create functions.
fn buildOptionalTarget(
    b: *std.Build, opts: Opts, name: []const u8,
    arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile,
    arcan_tui: *std.Build.Step.Compile, arcan_a12: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const S = struct {
        fn eql(a: []const u8, comptime expected: []const u8) bool {
            return std.mem.eql(u8, a, expected);
        }
    };
    if (S.eql(name, "arcan-db")) return createArcanDb(b, opts);
    if (S.eql(name, "afsrv-decode")) return createAfsrvDecode(b, opts, arcan_shmif, arcan_shmif_server, arcan_tui);
    if (S.eql(name, "afsrv-terminal")) return createAfsrvTerminal(b, opts, arcan_shmif, arcan_shmif_server, arcan_tui);
    if (S.eql(name, "afsrv-encode")) return createAfsrvEncode(b, opts, arcan_shmif, arcan_shmif_server, arcan_a12);
    if (S.eql(name, "afsrv-net")) return createAfsrvNet(b, opts, arcan_shmif, arcan_shmif_server, arcan_a12, arcan_tui);
    if (S.eql(name, "arcan-net")) return createArcanNet(b, opts, arcan_shmif, arcan_shmif_server, arcan_a12, arcan_tui);
    if (S.eql(name, "arcan-net-session")) return createArcanNetSession(b, opts, arcan_shmif, arcan_shmif_server, arcan_a12, arcan_tui);
    if (S.eql(name, "afsrv-remoting")) return createSimpleFsrv(b, opts, "afsrv_remoting", "REMOTING", arcan_shmif, arcan_shmif_server, arcan_a12);
    if (S.eql(name, "afsrv-game")) return createAfsrvGame(b, opts, arcan_shmif, arcan_shmif_server);
    if (S.eql(name, "afsrv-avfeed")) return createSimpleFsrv(b, opts, "afsrv_avfeed", "AVFEED", arcan_shmif, arcan_shmif_server, null);
    if (S.eql(name, "afsrv-bun")) return createSimpleFsrv(b, opts, "afsrv_bun", "BUN", arcan_shmif, arcan_shmif_server, null);
    if (S.eql(name, "afsrv-probe")) return createSimpleFsrv(b, opts, "afsrv_probe", "PROBE", arcan_shmif, arcan_shmif_server, null);
if (S.eql(name, "aclip")) return createAclip(b, opts, arcan_shmif, arcan_shmif_server);
    if (S.eql(name, "shmmon")) return createShmmon(b, opts, arcan_shmif, arcan_shmif_server);
    if (S.eql(name, "acfgfs")) return createAcfgfs(b, opts, arcan_shmif, arcan_shmif_server);
    unreachable;
}

// ════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════
fn buildShmifTests(b: *std.Build, opts: Opts, arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile) void {
    const test_step = b.step("test-shmif", "Run shmif ABI compatibility tests");
    const tests_with_helpers = [_][]const u8{ "shmif_layout_test", "shmif_sub_layout_test", "shmif_mousestate_test" };
    const tests_no_helpers = [_][]const u8{ "shmif_event_test", "shmif_argparse_test", "shmif_event_extended_test", "shmif_event_callers_test", "shmif_util_test", "shmif_constants_test" };
    const helpers_c = "src/shmif/shmif_test_helpers.c";
    const have_helpers_c = blk: {
        std.fs.cwd().access(helpers_c, .{}) catch break :blk false;
        break :blk true;
    };
    inline for (.{ tests_with_helpers, tests_no_helpers }) |test_list| {
        for (test_list) |name| {
            const test_mod = b.createModule(.{
                .root_source_file = b.path(b.fmt("src/shmif/{s}.zig", .{name})),
                .target = opts.target, .optimize = opts.optimize,
            });
            const cm_test = coreMods(b, opts);
            test_mod.addImport("shmif_types", cm_test.shmif_types);
            test_mod.addImport("posix", cm_test.posix_libc);
            test_mod.addImport("a12_types", cm_test.a12_types);
            test_mod.addImport("anet_types", cm_test.anet_types);
            const t = b.addTest(.{ .use_llvm = use_llvm_default, .root_module = test_mod });
            t.linkLibrary(arcan_shmif);
            t.linkLibrary(arcan_shmif_server);
            addLibC(t, opts);
            var needs_helpers = false;
            for (tests_with_helpers) |h| {
                if (std.mem.eql(u8, name, h)) {
                    needs_helpers = true;
                    break;
                }
            }
            if (needs_helpers) {
                if (!have_helpers_c) continue;
                t.addCSourceFile(.{ .file = b.path(helpers_c) });
            }
            addIncludes(t, b, shmif_include_paths);
            test_step.dependOn(&b.addRunArtifact(t).step);
        }
    }
    // Integration and live-client harnesses are optional: only wire them if
    // the C side has been authored.
    if (std.fs.cwd().access("tests/shmif/shmif_integration.c", .{})) |_| {
        const integ_step = b.step("test-shmif-integration", "Run shmif server↔client integration test");
        const integ_exe = createExe(b, "shmif_integration_test", opts);
        integ_exe.addCSourceFile(.{ .file = b.path("tests/shmif/shmif_integration.c") });
        integ_exe.linkLibrary(arcan_shmif);
        integ_exe.linkLibrary(arcan_shmif_server);
        addIncludes(integ_exe, b, shmif_include_paths);
        const run_integ = b.addRunArtifact(integ_exe);
        integ_step.dependOn(&run_integ.step);
        test_step.dependOn(&run_integ.step);
    } else |_| {}
    if (std.fs.cwd().access("tests/shmif/shmif_live_client.c", .{})) |_| {
        const live_step = b.step("test-shmif-live", "Build shmif live test client (run manually against arcan)");
        const live_exe = createExe(b, "shmif_live_client", opts);
        live_exe.addCSourceFile(.{ .file = b.path("tests/shmif/shmif_live_client.c") });
        live_exe.linkLibrary(arcan_shmif);
        addIncludes(live_exe, b, shmif_include_paths);
        live_step.dependOn(&b.addInstallArtifact(live_exe, .{}).step);
    } else |_| {}
}

fn buildTtfTests(b: *std.Build, opts: Opts) void {
    const truetype_dep = b.lazyDependency("TrueType", .{
        .target = opts.target,
        .optimize = opts.optimize,
    }) orelse return; // TrueType not fetched yet — skip tests

    const truetype_mod = truetype_dep.module("TrueType");

    const test_step = b.step("test-ttf", "Run TrueType font renderer tests");
    const t = b.addTest(.{ .use_llvm = use_llvm_default, .root_module = b.createModule(.{
        .root_source_file = b.path("src/engine/arcan_ttf_test.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    }) });
    t.root_module.addImport("TrueType", truetype_mod);
    {
        const cm = coreMods(b, opts);
        t.root_module.addImport("posix", cm.posix_libc);
        t.root_module.addImport("shmif_types", cm.shmif_types);
        t.root_module.addImport("a12_types", cm.a12_types);
        t.root_module.addImport("anet_types", cm.anet_types);
    }

    // Generate test_fonts module via WriteFiles: embeds the font + all 70
    // raw reference bitmaps generated by C stb_truetype (gen_reference.c).
    // Format: 4-byte LE width, 4-byte LE height, then width*height alpha bytes.
    const wf = b.addWriteFiles();
    const fonts_zig = wf.add("test_fonts.zig",
        \\pub const hack_ttf = @embedFile("hack.ttf");
        \\// 70 raw reference bitmaps from C stb_truetype: 14 glyphs x 5 sizes
        \\pub const ref_H_12px = @embedFile("H_12px.bin");
        \\pub const ref_H_16px = @embedFile("H_16px.bin");
        \\pub const ref_H_24px = @embedFile("H_24px.bin");
        \\pub const ref_H_32px = @embedFile("H_32px.bin");
        \\pub const ref_H_48px = @embedFile("H_48px.bin");
        \\pub const ref_e_12px = @embedFile("e_12px.bin");
        \\pub const ref_e_16px = @embedFile("e_16px.bin");
        \\pub const ref_e_24px = @embedFile("e_24px.bin");
        \\pub const ref_e_32px = @embedFile("e_32px.bin");
        \\pub const ref_e_48px = @embedFile("e_48px.bin");
        \\pub const ref_l_12px = @embedFile("l_12px.bin");
        \\pub const ref_l_16px = @embedFile("l_16px.bin");
        \\pub const ref_l_24px = @embedFile("l_24px.bin");
        \\pub const ref_l_32px = @embedFile("l_32px.bin");
        \\pub const ref_l_48px = @embedFile("l_48px.bin");
        \\pub const ref_o_12px = @embedFile("o_12px.bin");
        \\pub const ref_o_16px = @embedFile("o_16px.bin");
        \\pub const ref_o_24px = @embedFile("o_24px.bin");
        \\pub const ref_o_32px = @embedFile("o_32px.bin");
        \\pub const ref_o_48px = @embedFile("o_48px.bin");
        \\pub const ref_g_12px = @embedFile("g_12px.bin");
        \\pub const ref_g_16px = @embedFile("g_16px.bin");
        \\pub const ref_g_24px = @embedFile("g_24px.bin");
        \\pub const ref_g_32px = @embedFile("g_32px.bin");
        \\pub const ref_g_48px = @embedFile("g_48px.bin");
        \\pub const ref_W_12px = @embedFile("W_12px.bin");
        \\pub const ref_W_16px = @embedFile("W_16px.bin");
        \\pub const ref_W_24px = @embedFile("W_24px.bin");
        \\pub const ref_W_32px = @embedFile("W_32px.bin");
        \\pub const ref_W_48px = @embedFile("W_48px.bin");
        \\pub const ref_A_12px = @embedFile("A_12px.bin");
        \\pub const ref_A_16px = @embedFile("A_16px.bin");
        \\pub const ref_A_24px = @embedFile("A_24px.bin");
        \\pub const ref_A_32px = @embedFile("A_32px.bin");
        \\pub const ref_A_48px = @embedFile("A_48px.bin");
        \\pub const ref_M_12px = @embedFile("M_12px.bin");
        \\pub const ref_M_16px = @embedFile("M_16px.bin");
        \\pub const ref_M_24px = @embedFile("M_24px.bin");
        \\pub const ref_M_32px = @embedFile("M_32px.bin");
        \\pub const ref_M_48px = @embedFile("M_48px.bin");
        \\pub const ref_i_12px = @embedFile("i_12px.bin");
        \\pub const ref_i_16px = @embedFile("i_16px.bin");
        \\pub const ref_i_24px = @embedFile("i_24px.bin");
        \\pub const ref_i_32px = @embedFile("i_32px.bin");
        \\pub const ref_i_48px = @embedFile("i_48px.bin");
        \\pub const ref_zero_12px = @embedFile("zero_12px.bin");
        \\pub const ref_zero_16px = @embedFile("zero_16px.bin");
        \\pub const ref_zero_24px = @embedFile("zero_24px.bin");
        \\pub const ref_zero_32px = @embedFile("zero_32px.bin");
        \\pub const ref_zero_48px = @embedFile("zero_48px.bin");
        \\pub const ref_at_12px = @embedFile("at_12px.bin");
        \\pub const ref_at_16px = @embedFile("at_16px.bin");
        \\pub const ref_at_24px = @embedFile("at_24px.bin");
        \\pub const ref_at_32px = @embedFile("at_32px.bin");
        \\pub const ref_at_48px = @embedFile("at_48px.bin");
        \\pub const ref_pipe_12px = @embedFile("pipe_12px.bin");
        \\pub const ref_pipe_16px = @embedFile("pipe_16px.bin");
        \\pub const ref_pipe_24px = @embedFile("pipe_24px.bin");
        \\pub const ref_pipe_32px = @embedFile("pipe_32px.bin");
        \\pub const ref_pipe_48px = @embedFile("pipe_48px.bin");
        \\pub const ref_bang_12px = @embedFile("bang_12px.bin");
        \\pub const ref_bang_16px = @embedFile("bang_16px.bin");
        \\pub const ref_bang_24px = @embedFile("bang_24px.bin");
        \\pub const ref_bang_32px = @embedFile("bang_32px.bin");
        \\pub const ref_bang_48px = @embedFile("bang_48px.bin");
        \\pub const ref_underscore_12px = @embedFile("underscore_12px.bin");
        \\pub const ref_underscore_16px = @embedFile("underscore_16px.bin");
        \\pub const ref_underscore_24px = @embedFile("underscore_24px.bin");
        \\pub const ref_underscore_32px = @embedFile("underscore_32px.bin");
        \\pub const ref_underscore_48px = @embedFile("underscore_48px.bin");
        \\// FreeType ground truth (what arcan actually uses)
        \\pub const ft_H_12px = @embedFile("ft_H_12px.bin");
        \\pub const ft_H_16px = @embedFile("ft_H_16px.bin");
        \\pub const ft_H_24px = @embedFile("ft_H_24px.bin");
        \\pub const ft_H_32px = @embedFile("ft_H_32px.bin");
        \\pub const ft_H_48px = @embedFile("ft_H_48px.bin");
        \\pub const ft_e_12px = @embedFile("ft_e_12px.bin");
        \\pub const ft_e_16px = @embedFile("ft_e_16px.bin");
        \\pub const ft_e_24px = @embedFile("ft_e_24px.bin");
        \\pub const ft_e_32px = @embedFile("ft_e_32px.bin");
        \\pub const ft_e_48px = @embedFile("ft_e_48px.bin");
        \\pub const ft_W_12px = @embedFile("ft_W_12px.bin");
        \\pub const ft_W_16px = @embedFile("ft_W_16px.bin");
        \\pub const ft_W_24px = @embedFile("ft_W_24px.bin");
        \\pub const ft_W_32px = @embedFile("ft_W_32px.bin");
        \\pub const ft_W_48px = @embedFile("ft_W_48px.bin");
        \\pub const ft_A_12px = @embedFile("ft_A_12px.bin");
        \\pub const ft_A_16px = @embedFile("ft_A_16px.bin");
        \\pub const ft_A_24px = @embedFile("ft_A_24px.bin");
        \\pub const ft_A_32px = @embedFile("ft_A_32px.bin");
        \\pub const ft_A_48px = @embedFile("ft_A_48px.bin");
        \\pub const ft_M_12px = @embedFile("ft_M_12px.bin");
        \\pub const ft_M_16px = @embedFile("ft_M_16px.bin");
        \\pub const ft_M_24px = @embedFile("ft_M_24px.bin");
        \\pub const ft_M_32px = @embedFile("ft_M_32px.bin");
        \\pub const ft_M_48px = @embedFile("ft_M_48px.bin");
        \\
    );
    _ = wf.addCopyFile(b.path("data/resources/fonts/hack.ttf"), "hack.ttf");
    // Copy all reference binaries from both C stb_truetype and FreeType
    const ref_names = [_][]const u8{
        "H", "e", "l", "o", "g", "W", "A", "M", "i", "zero", "at", "pipe", "bang", "underscore",
    };
    const ref_sizes = [_][]const u8{ "12", "16", "24", "32", "48" };
    for (ref_names) |name| {
        for (ref_sizes) |sz| {
            const filename = b.fmt("{s}_{s}px.bin", .{ name, sz });
            _ = wf.addCopyFile(b.path(b.fmt("reference/stb_raw/{s}", .{filename})), filename);
            // FreeType references prefixed with ft_
            _ = wf.addCopyFile(b.path(b.fmt("reference/freetype_raw/{s}", .{filename})), b.fmt("ft_{s}", .{filename}));
        }
    }

    {
        const cm = coreMods(b, opts);
        t.root_module.addImport("test_fonts", b.createModule(.{
            .root_source_file = fonts_zig,
            .target = opts.target,
            .optimize = opts.optimize,
            .imports = &.{
                .{ .name = "posix", .module = cm.posix_libc },
                .{ .name = "shmif_types", .module = cm.shmif_types },
                .{ .name = "a12_types", .module = cm.a12_types },
                .{ .name = "anet_types", .module = cm.anet_types },
            },
        }));
    }
    test_step.dependOn(&b.addRunArtifact(t).step);
}

fn buildSlugTests(b: *std.Build, opts: Opts) void {
    const truetype_dep = b.lazyDependency("TrueType", .{
        .target = opts.target,
        .optimize = opts.optimize,
    }) orelse return;

    const truetype_mod = truetype_dep.module("TrueType");

    // Test slug_glyph.zig (curve extraction + band building)
    const test_step = b.step("test-slug", "Run Slug GPU glyph data tests");
    const cm = coreMods(b, opts);
    const t = b.addTest(.{ .use_llvm = use_llvm_default, .root_module = b.createModule(.{
        .root_source_file = b.path("src/engine/slug_glyph.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    }) });
    t.root_module.addImport("TrueType", truetype_mod);
    t.root_module.addImport("posix", cm.posix_libc);
    t.root_module.addImport("shmif_types", cm.shmif_types);
    t.root_module.addImport("a12_types", cm.a12_types);
    t.root_module.addImport("anet_types", cm.anet_types);
    test_step.dependOn(&b.addRunArtifact(t).step);

    // Test arcan_raster_gpu.zig (instance data structures — no GPU needed)
    const t2 = b.addTest(.{ .use_llvm = use_llvm_default, .root_module = b.createModule(.{
        .root_source_file = b.path("src/engine/arcan_raster_gpu.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    }) });
    t2.root_module.addImport("TrueType", truetype_mod);
    t2.root_module.addImport("posix", cm.posix_libc);
    t2.root_module.addImport("shmif_types", cm.shmif_types);
    t2.root_module.addImport("a12_types", cm.a12_types);
    t2.root_module.addImport("anet_types", cm.anet_types);
    test_step.dependOn(&b.addRunArtifact(t2).step);
}

fn buildGhosttyBridgeTests(b: *std.Build, opts: Opts) void {
    const ghostty_dep = b.lazyDependency("ghostty", .{
        .target = opts.target,
        .optimize = opts.optimize,
        // Fork sentinel — forces every Compile step in ghostty's build
        // graph (and transitively in uucode's) to ignore any
        // `.use_llvm = true` pin set by the dep. The upstream pins are
        // defensive against an x86 SH backend bug that doesn't apply
        // here; our no-LLVM fork can't honor them anyway.
        .__zig_use_llvm_override__ = @as(?bool, null),
    }) orelse return; // ghostty not fetched yet — skip

    const ghostty_vt = ghostty_dep.module("ghostty-vt");

    // Create bridge module for tests (same as production but standalone)
    const cm = coreMods(b, opts);
    const bridge_mod = b.createModule(.{
        .root_source_file = b.path("src/frameserver/terminal/default/ghostty_bridge.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "posix", .module = cm.posix_libc },
            .{ .name = "shmif_types", .module = cm.shmif_types },
            .{ .name = "a12_types", .module = cm.a12_types },
            .{ .name = "anet_types", .module = cm.anet_types },
        },
    });
    bridge_mod.addImport("ghostty-vt", ghostty_vt);

    const test_step = b.step("test-ghostty", "Run ghostty bridge tests");
    const t = b.addTest(.{ .use_llvm = use_llvm_default, .root_module = b.createModule(.{
        .root_source_file = b.path("src/frameserver/terminal/default/ghostty_bridge_test.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    }) });
    t.root_module.addImport("ghostty_bridge", bridge_mod);
    t.root_module.addImport("posix", cm.posix_libc);
    t.root_module.addImport("shmif_types", cm.shmif_types);
    t.root_module.addImport("a12_types", cm.a12_types);
    t.root_module.addImport("anet_types", cm.anet_types);
    // Stub for arcan_tui_ident (extern C in bridge, not available in test)
    const stubs = b.addWriteFiles();
    const stub_zig = stubs.add("tui_stubs.zig",
        \\export fn arcan_tui_ident(tui: ?*anyopaque, ident: [*c]const u8) void {
        \\    _ = tui;
        \\    _ = ident;
        \\}
        \\
    );
    const stub_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "tui_stubs", .root_module = b.createModule(.{
        .root_source_file = stub_zig,
        .target = opts.target,
        .optimize = opts.optimize,
    }) });
    t.addObject(stub_obj);
    addLibC(t, opts);
    test_step.dependOn(&b.addRunArtifact(t).step);
}

// ════════════════════════════════════════════════════════════════════
// Core libraries
// ════════════════════════════════════════════════════════════════════
fn createArcanShmifServer(b: *std.Build, opts: Opts) *std.Build.Step.Compile {
    const step = createLibrary(b, "arcan_shmif_server", shmif_version, opts);
    addLibC(step, opts);
    addShmifPlatformSources(b, step, opts);
    addPlatformDefinitions(step, opts);
    step.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
    for ([_]String{ "src/shmif/arcan_shmif_server.zig", "src/shmif/arcan_shmif_control.zig", "src/shmif/platform/exec.zig" }) |zig_src|
        addShmifZigSource(b, step, zig_src, opts);
    for ([_]String{ "src/platform/posix/frameserver.zig", "src/platform/posix/fsrv_guard.zig", "src/platform/posix/mem.zig" }) |zig_src|
        addShmifZigSource(b, step, zig_src, opts);
    addEvpackSource(b, step, opts);
    addIncludes(step, b, shmif_include_paths);
    return step;
}

fn createArcanShmif(b: *std.Build, opts: Opts) *std.Build.Step.Compile {
    const step = createLibrary(b, "arcan_shmif", shmif_version, opts);
    addLibC(step, opts);
    // NOTE: platform base sources (shmemop / fdscan / random / warning /
    // fdpassing_nonblock / time / sem), arcan_shmif_control, platform/exec,
    // and arcan_shmif_evpack all live in arcan_shmif_server — this lib
    // `linkLibrary`s shmif_server at line 383, so those object files are
    // available at link time without re-embedding them here. Re-embedding
    // caused every shmif_server/shmif pair to collide on ~67 strong
    // symbols when the compositor linked both archives.
    addPlatformDefinitions(step, opts);
    step.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
    const shmif_zig_sources = [_]String{
        "src/shmif/arcan_shmif_sub.zig",
        "src/shmif/arcan_shmif_a11y.zig", "src/shmif/arcan_shmif_migrate.zig",
        "src/shmif/arcan_shmif_mousestate.zig", "src/shmif/arcan_shmif_filehelper.zig",
        "src/shmif/arcan_shmif_avtransfer.zig", "src/shmif/arcan_shmif_argparse.zig",
        "src/shmif/arcan_shmif_preroll.zig", "src/shmif/arcan_shmif_eventhandler.zig",
        "src/shmif/arcan_shmif_privsep.zig", "src/shmif/arcan_shmif_evhelper.zig",
        "src/shmif/platform/synch.zig",
        "src/shmif/platform/fdpassing.zig", "src/shmif/platform/eventqueue.zig",
        "src/shmif/platform/watchdog.zig", "src/shmif/platform/migrate.zig",
        "src/shmif/platform/net.zig", "src/shmif/platform/connection.zig",
    };
    for (shmif_zig_sources) |zig_src| addShmifZigSource(b, step, zig_src, opts);
    addShmifZigSource(b, step, "src/engine/arcan_trace.zig", opts);
    // stub.c belongs in arcan_shmif_ext, not arcan_shmif — it provides platform_video_*
    // stubs that conflict with real video platform implementations when linking the compositor.
    addIncludes(step, b, shmif_include_paths);
    addShmifZigSource(b, step, "src/shmif/arcan_shmif_debugif.zig", opts);
    step.root_module.addCMacro("SHMIF_DEBUG_IF", "");
    return step;
}

fn createArcanA12(b: *std.Build, opts: Opts) *std.Build.Step.Compile {
    const step = createLibrary(b, "arcan_a12", a12_version, opts);
    addLibC(step, opts);
    step.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
    addPlatformDefinitions(step, opts);
    addA12ZigSource(b, step, "src/a12/a12.zig", opts);
    addA12ZigSource(b, step, "src/a12/a12_encode.zig", opts);
    addA12ZigSource(b, step, "src/a12/a12_decode.zig", opts);
    // H264 decoder: stub only — the ffmpeg-backed impl left with the C
    // tree/ffmpeg linkage. It exports the a12_h264_{setup,decode,free}
    // C-ABI symbols a12_decode.zig links against.
    addA12ZigSource(b, step, "src/a12/h264_decode_stub.zig", opts);
    addEvpackSource(b, step, opts);
    if (!opts.build_shmif) addShmifZigSourceNoLlvm(b, step, "src/a12/platform/shmif_stub.zig", opts);
    addA12ZigSource(b, step, "src/a12/platform/posix.zig", opts);
    addShmifZigSource(b, step, "src/platform/posix/time.zig", opts);
    addShmifZigSource(b, step, "src/platform/posix/mem.zig", opts);
    addShmifZigSource(b, step, "src/platform/posix/random.zig", opts);
    // Crypto primitives are provided by src/a12/crypto_shim.zig (std.crypto).
    // The vendored C implementations (blake3, x25519, monocypher, mlkem-native)
    // are no longer compiled; they live on disk under src/a12/external/ for
    // reference only. See crypto_shim.zig for the exported C-ABI symbols.
    addA12ZigSource(b, step, "src/a12/crypto_shim.zig", opts);
    // zstd: pure Zig, end-to-end. Decoder is `std.compress.zstd` wrapped by
    // `src/a12/zstd_shim.zig`. Encoder is our translate-c-refined port in
    // `src/a12/zstd_enc/` (slices 1-5+; see that directory's _test.zig for
    // the full module graph). No C zstd library is linked.
    addA12ZigSource(b, step, "src/a12/zstd_shim.zig", opts);
    // Single root object — compiling each zstd_enc/*.zig standalone would
    // produce duplicate C-ABI symbols (each `pub export fn` appears in every
    // object that imports the defining file). `zstd_enc/root.zig` pulls the
    // full module graph through one compilation unit.
    addA12ZigSource(b, step, "src/a12/zstd_enc/root.zig", opts);
    addIncludes(step, b, a12_include_paths);
    for ([_][2]String{
        .{ "BLAKE3_NO_AVX2", "" }, .{ "BLAKE3_NO_AVX512", "" }, .{ "BLAKE3_NO_SSE41", "" },
        .{ "MLK_CONFIG_PARAMETER_SET", "768" }, .{ "MLK_CONFIG_NAMESPACE_PREFIX", "mlkem" },
    }) |def| step.root_module.addCMacro(def[0], def[1]);
    return step;
}

fn createArcanTui(b: *std.Build, opts: Opts) *std.Build.Step.Compile {
    const step = createLibrary(b, "arcan_tui", shmif_version, opts);
    addLibC(step, opts);
    step.root_module.addCMacro("NO_ARCAN_AGP", "");
    step.root_module.addCMacro("SHMIF_TTF", "");
    step.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
    const types_mod = createMod(b, "src/engine/arcan_zig_types.zig", opts);
    const cm_tui = coreMods(b, opts);
    const shmif_types_mod = cm_tui.shmif_types;
    const tui_includes: []const String = shmif_tui_include_paths ++ &[_]String{ "src/shmif", "src/shmif/tui", "src/shmif/tui/widgets" };
    addZigObjects(step, b, opts, &.{
        .{ .name = "tui_raster", .path = "src/shmif/tui/raster/raster.zig" },
        .{ .name = "tui_main", .path = "src/shmif/tui/tui.zig" },
        .{ .name = "tui_clipboard", .path = "src/shmif/tui/core/clipboard.zig" },
        .{ .name = "tui_input", .path = "src/shmif/tui/core/input.zig" },
        .{ .name = "tui_setup", .path = "src/shmif/tui/core/setup.zig" },
        .{ .name = "tui_screen", .path = "src/shmif/tui/core/screen.zig" },
        .{ .name = "tui_dispatch", .path = "src/shmif/tui/core/dispatch.zig" },
        .{ .name = "tui_fontmgmt", .path = "src/shmif/tui/raster/fontmgmt.zig" },
        .{ .name = "tui_linewnd", .path = "src/shmif/tui/widgets/linewnd.zig" },
        .{ .name = "tui_bufferwnd", .path = "src/shmif/tui/widgets/bufferwnd.zig" },
        .{ .name = "tui_listwnd", .path = "src/shmif/tui/widgets/listwnd.zig" },
        .{ .name = "tui_readline", .path = "src/shmif/tui/widgets/readline.zig" },
        .{ .name = "tui_copywnd", .path = "src/shmif/tui/widgets/copywnd.zig" },
        .{ .name = "tui_pixelfont", .path = "src/shmif/tui/raster/pixelfont.zig" },
        .{ .name = "tui_font_data", .path = "src/shmif/tui/raster/font_data.zig" },
        .{ .name = "tui_ttfstub", .path = "src/shmif/tui/raster/ttfstub.zig" },
    }, &.{
        .{ .name = "arcan", .module = types_mod },
        .{ .name = "shmif_types", .module = shmif_types_mod },
        .{ .name = "posix", .module = cm_tui.posix_libc },
        .{ .name = "a12_types", .module = cm_tui.a12_types },
        .{ .name = "anet_types", .module = cm_tui.anet_types },
    }, &tui_includes);
    addIncludes(step, b, shmif_tui_include_paths);
    return step;
}

// ════════════════════════════════════════════════════════════════════
// Frameservers & tools
// ════════════════════════════════════════════════════════════════════
fn createArcanFrameserver(b: *std.Build, opts: Opts) *std.Build.Step.Compile {
    const exe = createExe(b, "arcan_frameserver", opts);
    // AFSRV_CHAINLOADER must use "1" (not "") so @hasDecl sees it in Zig's @cImport
    {
        const offsets_mod = createMod(b, "src/shmif/shmif_offsets.zig", opts);
        const a12_offsets_mod = createMod(b, "src/a12/a12_offsets.zig", opts);
        const shmif_types_mod_cl = createMod(b, "src/shmif/shmif_types.zig", opts);
        const posix_libc_mod = createMod(b, "src/platform/posix/libc.zig", opts);
        const a12_types_mod_cl = createA12TypesMod(b, opts, shmif_types_mod_cl);
        const anet_types_mod_cl = createAnetTypesMod(b, opts, shmif_types_mod_cl, a12_types_mod_cl, posix_libc_mod);
        const fsrv_opts_mod = makeFsrvOpts(b, null, true);
        const obj = b.addObject(.{ .use_llvm = use_llvm_default,
            .name = "frameserver",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/frameserver/frameserver.zig"),
                .target = opts.target, .optimize = opts.optimize, .pic = opts.pic,
                .imports = &.{
                    .{ .name = "shmif_offsets", .module = offsets_mod },
                    .{ .name = "a12_offsets", .module = a12_offsets_mod },
                    .{ .name = "shmif_types", .module = shmif_types_mod_cl },
                    .{ .name = "posix", .module = posix_libc_mod },
                    .{ .name = "a12_types", .module = a12_types_mod_cl },
                    .{ .name = "anet_types", .module = anet_types_mod_cl },
                    .{ .name = "fsrv_opts", .module = fsrv_opts_mod },
                },
            }),
        });
        addLibC(obj, opts);
        obj.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
        obj.root_module.addCMacro("AFSRV_CHAINLOADER", "1");
        addPlatformDefinitions(obj, opts);
        addIncludes(obj, b, shmif_include_paths);
        exe.addObject(obj);
        addFrameserverEntry(b, exe, opts);
    }
    addIncludes(exe, b, &.{ "src/shmif", "src/engine", "src/platform", "src/frameserver" });
    return exe;
}

fn createArcanDb(b: *std.Build, opts: Opts) *std.Build.Step.Compile {
    const exe = createExe(b, "arcan_db", opts);
    exe.root_module.addCMacro("ARCAN_DB_STANDALONE", "");
    addShmifZigSource(b, exe, "src/platform/posix/mem.zig", opts);
    addShmifZigSource(b, exe, "src/tools/db/dbtool.zig", opts);
    addShmifZigSource(b, exe, "src/platform/posix/dbpath.zig", opts);
    // arcan_db.zig needs xitdb module — use custom object instead of addShmifZigSource
    {
        const xitdb_mod = if (b.lazyDependency("xitdb", .{ .target = opts.target, .optimize = opts.optimize })) |dep|
            dep.module("xitdb")
        else
            null;
        const offsets_mod = createMod(b, "src/shmif/shmif_offsets.zig", opts);
        const a12_offsets_mod = createMod(b, "src/a12/a12_offsets.zig", opts);
        const posix_libc_mod = createMod(b, "src/platform/posix/libc.zig", opts);
        const shmif_types_mod_db = createMod(b, "src/shmif/shmif_types.zig", opts);
        const a12_types_mod_db = createA12TypesMod(b, opts, shmif_types_mod_db);
        const anet_types_mod_db = createAnetTypesMod(b, opts, shmif_types_mod_db, a12_types_mod_db, posix_libc_mod);
        const obj = b.addObject(.{ .use_llvm = use_llvm_default,
            .name = "arcan_db",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/engine/arcan_db.zig"),
                .target = opts.target, .optimize = opts.optimize, .pic = opts.pic,
                .imports = if (xitdb_mod) |m| &.{
                    .{ .name = "shmif_offsets", .module = offsets_mod },
                    .{ .name = "a12_offsets", .module = a12_offsets_mod },
                    .{ .name = "posix", .module = posix_libc_mod },
                    .{ .name = "shmif_types", .module = shmif_types_mod_db },
                    .{ .name = "a12_types", .module = a12_types_mod_db },
                    .{ .name = "anet_types", .module = anet_types_mod_db },
                    .{ .name = "xitdb", .module = m },
                } else &.{
                    .{ .name = "shmif_offsets", .module = offsets_mod },
                    .{ .name = "a12_offsets", .module = a12_offsets_mod },
                    .{ .name = "posix", .module = posix_libc_mod },
                    .{ .name = "shmif_types", .module = shmif_types_mod_db },
                    .{ .name = "a12_types", .module = a12_types_mod_db },
                    .{ .name = "anet_types", .module = anet_types_mod_db },
                },
            }),
        });
        addLibC(obj, opts);
        obj.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
        addPlatformDefinitions(obj, opts);
        addIncludes(obj, b, shmif_include_paths);
        exe.addObject(obj);
    }
    addShmifZigSourceNoLlvm(b, exe, "src/platform/posix/warning.zig", opts);
    addIncludes(exe, b, &.{ "src/engine", "src/platform", "src/frameserver" });
    if (exe.rootModuleTarget().os.tag != .windows) exe.linkSystemLibrary("pthread"); // win threads via substrate
    return exe;
}

/// Build a simple frameserver: frameserver.c + custom sources, standard libs.
fn createSimpleFsrv(
    b: *std.Build, opts: Opts, name: []const u8, mode_upper: []const u8,
    arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile,
    arcan_a12: ?*std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const exe = createExe(b, name, opts);
    const mode_lower =
        if (std.mem.eql(u8, mode_upper, "AVFEED")) "avfeed"
        else if (std.mem.eql(u8, mode_upper, "BUN")) "bun"
        else if (std.mem.eql(u8, mode_upper, "REMOTING")) "remoting"
        else if (std.mem.eql(u8, mode_upper, "PROBE")) "probe"
        else unreachable;
    addFrameserverZig(b, exe, opts, b.fmt("ENABLE_FSRV_{s}", .{mode_upper}), mode_lower);

    if (std.mem.eql(u8, mode_upper, "AVFEED")) {
        addShmifZigSource(b, exe, "src/frameserver/avfeed/default/avfeed.zig", opts);
        addIncludes(exe, b, &.{ "src/frameserver", "src/shmif", "src/engine", "src/platform" });
    } else if (std.mem.eql(u8, mode_upper, "BUN")) {
        addShmifZigSource(b, exe, "src/frameserver/bun/default/bun.zig", opts);
        addIncludes(exe, b, &.{ "src/frameserver", "src/shmif", "src/engine", "src/platform" });
        // Phase 2 only: skeleton afsrv_bun, no Bun runtime linked.
        // Phase 3+ Bun obj-link wiring lives in
        // build_llvm/build_afsrv_bun.zig and is invoked from build_llvm/'s
        // standalone build (see ../bugs/0036).
    } else if (std.mem.eql(u8, mode_upper, "PROBE")) {
        addShmifZigSource(b, exe, "src/frameserver/probe/default/probe.zig", opts);
        addIncludes(exe, b, &.{ "src/frameserver", "src/shmif", "src/engine", "src/platform" });
    } else if (std.mem.eql(u8, mode_upper, "REMOTING")) {
        exe.root_module.addCMacro("MLK_CONFIG_PARAMETER_SET", "768");
        exe.root_module.addCMacro("MLK_CONFIG_NAMESPACE_PREFIX", "mlkem");
        addShmifZigSource(b, exe, "src/frameserver/remoting/default/remoting.zig", opts);
        const remoting_includes = shmif_include_paths ++ a12_include_paths ++ &[_]String{ "src/a12/net", "src/frameserver/util" };
        for ([_]String{
            "src/frameserver/remoting/default/a12.zig",
            "src/a12/net/anet_helper.zig", "src/a12/net/anet_keystore_naive.zig",
        }) |zig_path| addShmifZigSourceInnerA12(b, exe, zig_path, opts, useLlvmForSource(b, zig_path), remoting_includes);
        addIncludes(exe, b, fsrv_a12_include_paths);
        exe.addIncludePath(b.path("src/shmif"));
    }
    exe.linkLibrary(arcan_shmif);
    exe.linkLibrary(arcan_shmif_server);
    if (arcan_a12) |a12| exe.linkLibrary(a12);
    linkFsrvStdlib(exe);
    return exe;
}

/// Build a simple shmif tool: sources + includes + link shmif + stdlib.
fn createSimpleTool(
    b: *std.Build, opts: Opts, name: []const u8, sources: []const []const u8,
    includes: []const []const u8,
    arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const exe = createExe(b, name, opts);
    addCSources(exe, b, sources);
    addIncludes(exe, b, includes);
    exe.linkLibrary(arcan_shmif);
    exe.linkLibrary(arcan_shmif_server);
    linkFsrvStdlib(exe);
    return exe;
}

fn createAfsrvGame(b: *std.Build, opts: Opts, arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile) *std.Build.Step.Compile {
    const exe = createExe(b, "afsrv_game", opts);
    addFrameserverZig(b, exe, opts, "ENABLE_FSRV_GAME", "game");
    addShmifZigSource(b, exe, "src/frameserver/game/default/libretro.zig", opts);
    addShmifZigSource(b, exe, "src/frameserver/game/default/ntsc/snes_ntsc.zig", opts);
    addShmifZigSource(b, exe, "src/frameserver/util/sync_plot.zig", opts);
    addShmifZigSource(b, exe, "src/platform/posix/map_resource.zig", opts);
    addShmifZigSource(b, exe, "src/platform/posix/resource_io.zig", opts);
    addIncludes(exe, b, &.{ "src/engine", "src/platform", "src/frameserver", "src/frameserver/util", "src/frameserver/game/default", "src/shmif" });
    exe.linkLibrary(arcan_shmif);
    exe.linkLibrary(arcan_shmif_server);
    linkFsrvStdlib(exe);
    return exe;
}

fn createAclip(b: *std.Build, opts: Opts, arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile) *std.Build.Step.Compile {
    // Pure-Zig port of aclip.c. Root module is aclip.zig; link against the
    // existing libarcan_shmif (no extra C sources).
    const cm = coreMods(b, opts);
    const shmif_api_mod = b.createModule(.{
        .root_source_file = b.path("src/shmif/shmif_api.zig"),
        .target = opts.target, .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "shmif_types", .module = cm.shmif_types },
            .{ .name = "posix", .module = cm.posix_libc },
            .{ .name = "a12_types", .module = cm.a12_types },
            .{ .name = "anet_types", .module = cm.anet_types },
        },
    });
    const exe = b.addExecutable(.{ .use_llvm = use_llvm_default, .name = "aclip", .root_module = b.createModule(.{
        .root_source_file = b.path("src/tools/aclip/aclip.zig"),
        .target = opts.target, .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "shmif_types", .module = cm.shmif_types },
            .{ .name = "shmif_api", .module = shmif_api_mod },
            .{ .name = "posix", .module = cm.posix_libc },
            .{ .name = "a12_types", .module = cm.a12_types },
            .{ .name = "anet_types", .module = cm.anet_types },
        },
    }) });
    addLibC(exe, opts);
    addPlatformDefinitions(exe, opts);
    exe.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
    addIncludes(exe, b, shmif_include_paths);
    exe.linkLibrary(arcan_shmif);
    exe.linkLibrary(arcan_shmif_server);
    linkFsrvStdlib(exe);
    return exe;
}

fn createShmmon(b: *std.Build, opts: Opts, arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile) *std.Build.Step.Compile {
    const exe = createExe(b, "shmmon", opts);
    // Pure-Zig port: shmmon.zig + parse-edid.zig (latter landed by a parallel agent).
    addShmifZigSource(b, exe, "src/tools/shmmon/shmmon.zig", opts);
    addShmifZigSource(b, exe, "src/tools/shmmon/parse-edid.zig", opts);
    addIncludes(exe, b, shmif_include_paths);
    exe.linkLibrary(arcan_shmif);
    exe.linkLibrary(arcan_shmif_server);
    linkFsrvStdlib(exe);
    return exe;
}

fn createAcfgfs(b: *std.Build, opts: Opts, arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile) *std.Build.Step.Compile {
    _ = arcan_shmif; _ = arcan_shmif_server;
    // Pure-Zig FUSE client — speaks the kernel /dev/fuse protocol directly
    // via the setuid fusermount3 helper. No libfuse3 link or dlopen, so
    // no pthread/rt/dl deps and no musl↔glibc ABI bridge to worry about.
    const cm = coreMods(b, opts);
    const fuse_types_mod = createMod(b, "src/tools/acfgfs/fuse_types.zig", opts);
    const exe = b.addExecutable(.{ .use_llvm = use_llvm_default, .name = "arcan_cfgfs", .root_module = b.createModule(.{
        .root_source_file = b.path("src/tools/acfgfs/acfgfs.zig"),
        .target = opts.target, .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "posix", .module = cm.posix_libc },
            .{ .name = "shmif_types", .module = cm.shmif_types },
            .{ .name = "a12_types", .module = cm.a12_types },
            .{ .name = "anet_types", .module = cm.anet_types },
            .{ .name = "fuse_types", .module = fuse_types_mod },
        },
    }) });
    addLibC(exe, opts);
    return exe;
}

fn createArcanShmifExt(b: *std.Build, opts: Opts) *std.Build.Step.Compile {
    const step = createLibrary(b, "arcan_shmif_ext", shmif_version, opts);
    addLibC(step, opts);
    addPlatformDefinitions(step, opts);
    step.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
    step.root_module.addCMacro("HEADLESS_NOARCAN", "");
    addShmifZigSource(b, step, "src/shmif/stub/stub.zig", opts);
    // arcan_shmifext_signal stub — pure Zig replacement for stub_signal.c so
    // build.zig makes no addCSourceFile call here (arcan-net builds don't
    // need C compilation pulled in just to expose this no-op export).
    addShmifZigSource(b, step, "src/shmif/stub/stub_signal.zig", opts);
    addIncludes(step, b, shmif_include_paths);
    step.addIncludePath(b.path("src/platform"));
    return step;
}

// ════════════════════════════════════════════════════════════════════
// Complex frameservers (terminal, decode, encode, net)
// ════════════════════════════════════════════════════════════════════
fn createAfsrvTerminal(
    b: *std.Build, opts: Opts,
    arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile,
    arcan_tui: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const exe = createExe(b, "afsrv_terminal", opts);
    const is_darwin = switch (opts.target.result.os.tag) {
        .ios, .macos, .watchos, .tvos => true, else => false,
    };
    if (!is_darwin) exe.root_module.addCMacro("SALLOW_ST", "");

    const term_include_paths: []const String = &.{
        "src/frameserver", "src/frameserver/terminal/default", "src/frameserver/terminal/default/tsm",
        "src/shmif/tui/lua", "src/engine", "src/engine/external", "src/shmif", "src/shmif/tui", "src/platform",
    };
    addIncludes(exe, b, term_include_paths);
    addFrameserverZig(b, exe, opts, "ENABLE_FSRV_TERMINAL", "terminal");
    // Zig ports of tui_lua, nbio, shl-pty, shl-ring, tui_lua_glob, tui_popen
    const shmif_types_mod_term = createMod(b, "src/shmif/shmif_types.zig", opts);
    const posix_libc_mod_term = createMod(b, "src/platform/posix/libc.zig", opts);
    const a12_types_mod_term = createA12TypesMod(b, opts, shmif_types_mod_term);
    const anet_types_mod_term = createAnetTypesMod(b, opts, shmif_types_mod_term, a12_types_mod_term, posix_libc_mod_term);
    const lua54_api_mod_term = createMod(b, "src/lua54/api.zig", opts);
    for ([_]String{
        "src/frameserver/terminal/default/tsm/shl_pty.zig", "src/frameserver/terminal/default/tsm/shl_ring.zig",
        "src/shmif/tui/lua/tui_lua.zig", "src/shmif/tui/lua/tui_lua_glob.zig",
        "src/shmif/tui/lua/nbio.zig", "src/shmif/tui/lua/tui_popen.zig",
    }) |zig_path| {
        const obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = std.fs.path.stem(zig_path), .root_module = b.createModule(.{
            .root_source_file = b.path(zig_path), .target = opts.target, .optimize = opts.optimize,
            .imports = &.{
                .{ .name = "shmif_types", .module = shmif_types_mod_term },
                .{ .name = "posix", .module = posix_libc_mod_term },
                .{ .name = "a12_types", .module = a12_types_mod_term },
                .{ .name = "anet_types", .module = anet_types_mod_term },
                .{ .name = "lua_api", .module = lua54_api_mod_term },
            },
        }) });
        addLibC(obj, opts);
        addIncludes(obj, b, term_include_paths);
        exe.addObject(obj);
    }
    {
        const bit_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "bit", .root_module = b.createModule(.{
            .root_source_file = b.path("src/engine/external/bit.zig"), .target = opts.target, .optimize = opts.optimize,
            .imports = &.{
                .{ .name = "posix", .module = posix_libc_mod_term },
                .{ .name = "shmif_types", .module = shmif_types_mod_term },
                .{ .name = "a12_types", .module = a12_types_mod_term },
                .{ .name = "anet_types", .module = anet_types_mod_term },
                .{ .name = "lua_api", .module = lua54_api_mod_term },
            },
        }) });
        addLibC(bit_obj, opts);
        addIncludes(bit_obj, b, term_include_paths);
        exe.addObject(bit_obj);
    }
    addShmifZigSource(b, exe, "src/frameserver/terminal/default/cli_builtin.zig", opts);

    // arcterm.zig — needs terminal-specific include paths, ghostty bridge, shmif offsets
    {
        const offsets_mod = createMod(b, "src/shmif/shmif_offsets.zig", opts);
        const bridge_mod = createMod(b, "src/frameserver/terminal/default/ghostty_bridge.zig", opts);
        const posix_libc_mod = createMod(b, "src/platform/posix/libc.zig", opts);
        const shmif_types_mod = createMod(b, "src/shmif/shmif_types.zig", opts);
        const a12_types_mod_at = createA12TypesMod(b, opts, shmif_types_mod);
        const anet_types_mod_at = createAnetTypesMod(b, opts, shmif_types_mod, a12_types_mod_at, posix_libc_mod);
        // Disable ghostty's SIMD path via -Dsimd=false. That drops all
        // three of its hand-written-C++ / external-C++ deps (highway,
        // simdutf, utfcpp) plus ghostty's own src/simd/*.cpp files.
        // The no-LLVM fork has no libclang and can't compile C/C++, so
        // the SIMD deps fail with `aro does not support compiling C
        // objects yet`. The remaining dep (uucode, grapheme tables) is
        // pure Zig. Args stays a 1-bool anon struct, well below the
        // ResolvedTarget-by-value SH pitfall that broke the xitdb/uucode
        // call paths earlier.
        if (b.lazyDependency("ghostty", .{
            .simd = false,
            // See buildGhosttyBridgeTests — same fork sentinel. Propagates
            // through ghostty into uucode, whose `uucode_build_tables` and
            // our downstream `props-unigen` / `symbols-unigen` otherwise
            // pin `.use_llvm = true` and abort the build.
            .__zig_use_llvm_override__ = @as(?bool, null),
        })) |dep|
            bridge_mod.addImport("ghostty-vt", dep.module("ghostty-vt"));
        const obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "arcterm", .root_module = b.createModule(.{
            .root_source_file = b.path("src/frameserver/terminal/default/arcterm.zig"),
            .target = opts.target, .optimize = opts.optimize,
            .imports = &.{
                .{ .name = "shmif_offsets", .module = offsets_mod },
                .{ .name = "ghostty_bridge", .module = bridge_mod },
                .{ .name = "posix", .module = posix_libc_mod },
                .{ .name = "shmif_types", .module = shmif_types_mod },
                .{ .name = "a12_types", .module = a12_types_mod_at },
                .{ .name = "anet_types", .module = anet_types_mod_at },
            },
        }) });
        addLibC(obj, opts);
        obj.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
        addPlatformDefinitions(obj, opts);
        addIncludes(obj, b, shmif_include_paths);
        addIncludes(obj, b, &.{ "src/frameserver/terminal/default", "src/frameserver/terminal/default/tsm", "src/frameserver", "src/shmif/tui" });
        exe.addObject(obj);
    }
    // cli_parse.zig, cli.zig, cli_lua.zig — all need shmif offsets + terminal includes
    {
        const offsets_mod = createMod(b, "src/shmif/shmif_offsets.zig", opts);
        const posix_libc_mod = createMod(b, "src/platform/posix/libc.zig", opts);
        const shmif_types_mod = createMod(b, "src/shmif/shmif_types.zig", opts);
        const a12_types_mod_cli = createA12TypesMod(b, opts, shmif_types_mod);
        const anet_types_mod_cli = createAnetTypesMod(b, opts, shmif_types_mod, a12_types_mod_cli, posix_libc_mod);
        const cli_zig_sources = [_]NamePath{
            .{ .name = "cli_parse", .path = "src/frameserver/terminal/default/cli_parse.zig" },
            .{ .name = "cli", .path = "src/frameserver/terminal/default/cli.zig" },
            .{ .name = "cli_lua", .path = "src/frameserver/terminal/default/cli_lua.zig" },
        };
        const lua54_api_mod_cli = createMod(b, "src/lua54/api.zig", opts);
        for (cli_zig_sources) |src| {
            const obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = src.name, .root_module = b.createModule(.{
                .root_source_file = b.path(src.path), .target = opts.target, .optimize = opts.optimize,
                .imports = &.{
                    .{ .name = "shmif_offsets", .module = offsets_mod },
                    .{ .name = "posix", .module = posix_libc_mod },
                    .{ .name = "shmif_types", .module = shmif_types_mod },
                    .{ .name = "a12_types", .module = a12_types_mod_cli },
                    .{ .name = "anet_types", .module = anet_types_mod_cli },
                    .{ .name = "lua_api", .module = lua54_api_mod_cli },
                },
            }) });
            addLibC(obj, opts);
            obj.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
            addPlatformDefinitions(obj, opts);
            addIncludes(obj, b, shmif_include_paths);
            addIncludes(obj, b, &.{ "src/frameserver/terminal/default", "src/frameserver" });
            exe.addObject(obj);
        }
    }
    // st/st.c and st/tui.c ported to Zig
    addArcanMathZig(b, exe, opts);
    addLua54AllObject(b, exe, opts);
    exe.linkLibrary(arcan_shmif);
    exe.linkLibrary(arcan_shmif_server);
    exe.linkLibrary(arcan_tui);
    linkUtil(exe);
    linkFsrvStdlib(exe);
    return exe;
}

fn createAfsrvDecode(
    b: *std.Build, opts: Opts,
    arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile,
    arcan_tui: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const exe = createExe(b, "afsrv_decode", opts);
    addFrameserverZig(b, exe, opts, "ENABLE_FSRV_DECODE", "decode");
    // decode_img.c + decode_3d_tinyobj.c ported to Zig
    addShmifZigSource(b, exe, "src/frameserver/decode/default/decode.zig", opts);
    addShmifZigSource(b, exe, "src/frameserver/decode/default/decode_text.zig", opts);
    addShmifZigSource(b, exe, "src/frameserver/decode/default/decode_3d.zig", opts);
    addShmifZigSource(b, exe, "src/platform/posix/map_resource.zig", opts);
    addShmifZigSource(b, exe, "src/platform/posix/resource_io.zig", opts);
    addArcanMathZig(b, exe, opts);
    addShmifZigSource(b, exe, "src/frameserver/decode/default/kiss_fft.zig", opts);
    addIncludes(exe, b, &.{ "src/engine/external", "src/platform", "src/frameserver", "src/engine", "src/shmif" });
    exe.linkLibrary(arcan_shmif);
    exe.linkLibrary(arcan_shmif_server);
    exe.linkLibrary(arcan_tui);
    linkFsrvStdlib(exe);
    return exe;
}

fn createAfsrvNet(
    b: *std.Build, opts: Opts,
    arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile,
    arcan_a12: *std.Build.Step.Compile, arcan_tui: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const exe = createExe(b, "afsrv_net", opts);
    addFrameserverZig(b, exe, opts, "ENABLE_FSRV_NET", "net");
    for ([_][2]String{
        .{ "BLAKE3_NO_AVX2", "" }, .{ "BLAKE3_NO_AVX512", "" }, .{ "BLAKE3_NO_SSE41", "" },
        .{ "WANT_KEYSTORE_HASHER", "" }, .{ "MLK_CONFIG_PARAMETER_SET", "768" }, .{ "MLK_CONFIG_NAMESPACE_PREFIX", "mlkem" },
    }) |def| exe.root_module.addCMacro(def[0], def[1]);
    // afsrv_net is pure Zig — no C sources.
    const net_includes = shmif_include_paths ++ a12_include_paths ++ &[_]String{ "src/a12/net", "src/frameserver/util", "src/frameserver" };
    for ([_]String{
        "src/a12/net/helper_framecache.zig", "src/a12/net/helper_cl.zig",
        "src/a12/net/helper_srv.zig", "src/a12/net/helper_discover.zig",
        "src/a12/net/dir_supp.zig", "src/a12/net/dir_cl.zig",
        "src/a12/net/fts.zig", "src/a12/net/afsrv_net_stubs.zig",
        "src/a12/net/anet_keystore_naive.zig",
        "src/a12/net/anet_helper.zig",
        "src/frameserver/net/default/net.zig",
    }) |zig_path| addShmifZigSourceInnerA12(b, exe, zig_path, opts, useLlvmForSource(b, zig_path), net_includes);
    addArcanMathZig(b, exe, opts);
    addIncludes(exe, b, fsrv_a12_include_paths);
    addIncludes(exe, b, &.{ "src/shmif", "src/a12/net" });
    exe.linkLibrary(arcan_shmif);
    exe.linkLibrary(arcan_shmif_server);
    exe.linkLibrary(arcan_a12);
    exe.linkLibrary(arcan_tui);
    linkFsrvStdlib(exe);
    return exe;
}

fn createArcanNetSession(
    b: *std.Build, opts: Opts,
    arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile,
    arcan_a12: *std.Build.Step.Compile, arcan_tui: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const exe = createExe(b, "arcan-net-session", opts);
    for ([_][2]String{
        .{ "BLAKE3_NO_AVX2", "" }, .{ "BLAKE3_NO_AVX512", "" }, .{ "BLAKE3_NO_SSE41", "" },
        .{ "WANT_KEYSTORE_HASHER", "" }, .{ "MLK_CONFIG_PARAMETER_SET", "768" }, .{ "MLK_CONFIG_NAMESPACE_PREFIX", "mlkem" },
        .{ "ARCAN_BUILDVERSION", "\"mayhem-2026-04-16\"" },
    }) |def| exe.root_module.addCMacro(def[0], def[1]);
    const net_includes = shmif_include_paths ++ a12_include_paths ++ &[_]String{ "src/a12/net", "src/frameserver/util", "src/frameserver" };
    for ([_]String{
        "src/a12/net/session.zig",
        "src/a12/net/helper_srv.zig",
        "src/a12/net/helper_framecache.zig",
        "src/a12/net/anet_helper.zig",
        "src/a12/net/anet_keystore_naive.zig",
    }) |zig_path| addShmifZigSourceInnerA12(b, exe, zig_path, opts, useLlvmForSource(b, zig_path), net_includes);
    // Pure-Zig port of sheredom/hashmap.h providing the same exported
    // hashmap_* C ABI that session.zig calls through extern decls in
    // anet_types.zig. Replaces hashmap_impl.c so the arcan-net-session
    // build graph has no first-party C sources.
    addShmifZigSourceInnerA12(b, exe, "src/a12/net/hashmap.zig", opts, useLlvmForSource(b, "src/a12/net/hashmap.zig"), net_includes);
    addIncludes(exe, b, &.{"src/a12/net"});
    addArcanMathZig(b, exe, opts);
    addIncludes(exe, b, fsrv_a12_include_paths);
    addIncludes(exe, b, &.{ "src/shmif", "src/a12/net" });
    exe.linkLibrary(arcan_shmif);
    exe.linkLibrary(arcan_shmif_server);
    exe.linkLibrary(arcan_a12);
    exe.linkLibrary(arcan_tui);
    linkFsrvStdlib(exe);
    return exe;
}

fn createArcanNet(
    b: *std.Build, opts: Opts,
    arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile,
    arcan_a12: *std.Build.Step.Compile, arcan_tui: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const exe = createExe(b, "arcan-net", opts);
    for ([_][2]String{
        .{ "BLAKE3_NO_AVX2", "" }, .{ "BLAKE3_NO_AVX512", "" }, .{ "BLAKE3_NO_SSE41", "" },
        .{ "WANT_KEYSTORE_HASHER", "" }, .{ "HAVE_DIRSRV", "" }, .{ "ARCAN_DB_STANDALONE", "" },
        .{ "MLK_CONFIG_PARAMETER_SET", "768" }, .{ "MLK_CONFIG_NAMESPACE_PREFIX", "mlkem" },
        .{ "ARCAN_BUILDVERSION", "\"mayhem-2026-04-16\"" },
    }) |def| exe.root_module.addCMacro(def[0], def[1]);
    const net_includes = shmif_include_paths ++ a12_include_paths ++ &[_]String{ "src/a12/net", "src/frameserver/util", "src/frameserver" };
    for ([_]String{
        "src/a12/net/helper_cl.zig",
        "src/a12/net/helper_srv.zig",
        "src/a12/net/helper_discover.zig",
        "src/a12/net/helper_framecache.zig",
        "src/a12/net/net.zig",
        "src/a12/net/nbio.zig",
        "src/a12/net/net_lua.zig",
        "src/a12/net/net_lua_cfg.zig",
        "src/a12/net/dir_lua_appl.zig",
        "src/a12/net/dir_lua_support.zig",
        "src/a12/net/dir_lua_cfg.zig",
        "src/a12/net/dir_lua.zig",
        "src/a12/net/dir_cl.zig",
        "src/a12/net/dir_srv.zig",
        "src/a12/net/dir_srv_worker.zig",
        "src/a12/net/dir_srv_link.zig",
        "src/a12/net/dir_srv_bchunk.zig",
        "src/a12/net/dir_supp.zig",
        "src/a12/net/warning.zig",
        "src/a12/net/dbpath.zig",
        "src/a12/net/resource_io.zig",
        "src/a12/net/map_resource.zig",
        "src/a12/net/mem.zig",
        "src/a12/net/anet_helper.zig",
        "src/a12/net/anet_keystore_naive.zig",
        "src/a12/net/fts.zig",
        // Phase-0 stubs/pure-Zig impls for the 14 symbols that unblock
        // standalone arcan-net linking. See plans/warm-jumping-grove.md.
        "src/a12/net/dir_srv_globals.zig",
        "src/a12/net/arcan_bootstrap_data.zig",
        "src/a12/net/arcan_resource_cabi.zig",
        "src/a12/net/utf8.zig",
        "src/a12/net/lua_tbl.zig",
        "src/a12/a12_trace_cabi.zig",
        // C `main` shim: net.zig exports `arcan_net_main`, standalone exe
        // needs the real symbol.
        "src/a12/net/arcan_net_entry.zig",
    }) |zig_path| addShmifZigSourceInnerA12NetLua(b, exe, zig_path, opts, useLlvmForSource(b, zig_path), net_includes);
    // arcan_db: pure-Zig xitdb-backed engine (src/engine/arcan_db.zig). No sqlite3.
    {
        // Pass an empty args struct to lazyDependency: the fork's SH backend
        // miscompiles `Build.userInputOptionsFromArgs` when fed non-trivial
        // anonymous-struct args like `.{ .target = ..., .optimize = ... }`
        // (SEGV in memcpySmall while processing ResolvedTarget fields).
        // xitdb is pure-Zig and has no build options of its own, so this is
        // equivalent to the explicit form.
        const xitdb_mod = if (b.lazyDependency("xitdb", .{})) |dep|
            dep.module("xitdb") else null;
        const posix_libc_mod_db = createMod(b, "src/platform/posix/libc.zig", opts);
        const shmif_types_mod_ndb = createMod(b, "src/shmif/shmif_types.zig", opts);
        const a12_types_mod_ndb = createA12TypesMod(b, opts, shmif_types_mod_ndb);
        const anet_types_mod_ndb = createAnetTypesMod(b, opts, shmif_types_mod_ndb, a12_types_mod_ndb, posix_libc_mod_db);
        const db_obj = b.addObject(.{ .use_llvm = use_llvm_default,
            .name = "arcan_db",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/engine/arcan_db.zig"),
                .target = opts.target, .optimize = opts.optimize, .pic = opts.pic,
                .imports = if (xitdb_mod) |m| &.{
                    .{ .name = "xitdb", .module = m },
                    .{ .name = "posix", .module = posix_libc_mod_db },
                    .{ .name = "shmif_types", .module = shmif_types_mod_ndb },
                    .{ .name = "a12_types", .module = a12_types_mod_ndb },
                    .{ .name = "anet_types", .module = anet_types_mod_ndb },
                } else &.{
                    .{ .name = "posix", .module = posix_libc_mod_db },
                    .{ .name = "shmif_types", .module = shmif_types_mod_ndb },
                    .{ .name = "a12_types", .module = a12_types_mod_ndb },
                    .{ .name = "anet_types", .module = anet_types_mod_ndb },
                },
            }),
        });
        addLibC(db_obj, opts);
        db_obj.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
        addPlatformDefinitions(db_obj, opts);
        addIncludes(db_obj, b, net_includes);
        exe.addObject(db_obj);
    }
    addArcanMathZig(b, exe, opts);
    addIncludes(exe, b, fsrv_a12_include_paths);
    addIncludes(exe, b, &.{ "src/shmif", "src/a12/net" });
    exe.linkLibrary(arcan_shmif);
    exe.linkLibrary(arcan_shmif_server);
    exe.linkLibrary(arcan_a12);
    exe.linkLibrary(arcan_tui);
    addLua54AllObject(b, exe, opts);
    linkFsrvStdlib(exe);
    return exe;
}

// Variant of addShmifZigSourceInnerA12 that also wires in the lua54_api module (for dir_lua*, net_lua* sources).
fn addShmifZigSourceInnerA12NetLua(
    b: *std.Build, step: *std.Build.Step.Compile, zig_path: []const u8, opts: Opts,
    use_llvm: ?bool, include_paths: []const String,
) void {
    const offsets_mod = createMod(b, "src/shmif/shmif_offsets.zig", opts);
    const a12_offsets_mod = createMod(b, "src/a12/a12_offsets.zig", opts);
    const shmif_monitor_mod = createMod(b, "src/engine/shmif_monitor.zig", opts);
    const posix_libc_mod = createMod(b, "src/platform/posix/libc.zig", opts);
    const shmif_types_mod = createMod(b, "src/shmif/shmif_types.zig", opts);
    const a12_types_mod = createA12TypesMod(b, opts, shmif_types_mod);
    const anet_types_mod = createAnetTypesMod(b, opts, shmif_types_mod, a12_types_mod, posix_libc_mod);
    const lua54_api_mod = createMod(b, "src/lua54/api.zig", opts);
    const obj = b.addObject(.{
        .name = std.fs.path.stem(zig_path),
        .root_module = b.createModule(.{
            .root_source_file = b.path(zig_path), .target = opts.target, .optimize = opts.optimize, .pic = opts.pic,
            .imports = &.{
                .{ .name = "shmif_offsets", .module = offsets_mod },
                .{ .name = "a12_offsets", .module = a12_offsets_mod },
                .{ .name = "shmif_monitor", .module = shmif_monitor_mod },
                .{ .name = "posix", .module = posix_libc_mod },
                .{ .name = "a12_types", .module = a12_types_mod },
                .{ .name = "anet_types", .module = anet_types_mod },
                .{ .name = "shmif_types", .module = shmif_types_mod },
                .{ .name = "lua_api", .module = lua54_api_mod },
            },
        }),
        .use_llvm = use_llvm,
    });
    addLibC(obj, opts);
    obj.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
    addPlatformDefinitions(obj, opts);
    addIncludes(obj, b, include_paths);
    for ([_][2]String{
        .{ "MLK_CONFIG_PARAMETER_SET", "768" }, .{ "MLK_CONFIG_NAMESPACE_PREFIX", "mlkem" },
        .{ "WANT_KEYSTORE_HASHER", "" }, .{ "HAVE_DIRSRV", "" },
    }) |def| obj.root_module.addCMacro(def[0], def[1]);
    step.addObject(obj);
}

fn createAfsrvEncode(
    b: *std.Build, opts: Opts,
    arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile,
    arcan_a12: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const exe = createExe(b, "afsrv_encode", opts);
    addFrameserverZig(b, exe, opts, "ENABLE_FSRV_ENCODE", "encode");
    exe.root_module.addCMacro("MLK_CONFIG_PARAMETER_SET", "768");
    exe.root_module.addCMacro("MLK_CONFIG_NAMESPACE_PREFIX", "mlkem");
    const encode_includes = shmif_include_paths ++ a12_include_paths ++ &[_]String{ "src/a12/net", "src/frameserver/util" };
    for ([_]String{
        "src/a12/net/anet_helper.zig", "src/a12/net/anet_keystore_naive.zig",
    }) |zig_path| addShmifZigSourceInnerA12(b, exe, zig_path, opts, useLlvmForSource(b, zig_path), encode_includes);
    addShmifZigSource(b, exe, "src/frameserver/encode/default/encode.zig", opts);
    addShmifZigSource(b, exe, "src/frameserver/encode/default/img.zig", opts);
    // a12_serv_run / ffmpeg_run report-unavailable stubs (png_stream_run is
    // the real impl in img.zig); the ffmpeg backend left with the C tree.
    addShmifZigSource(b, exe, "src/frameserver/stubs.zig", opts);
    addShmifZigSourceInner(b, exe, "src/engine/arcan_img.zig", opts, useLlvmForSource(b, "src/engine/arcan_img.zig"), shmif_include_paths ++ &[_]String{"src/engine/external"});
    // stb_image / stb_image_write impls: pure-Zig translate-c port that
    // `pub export`s the entry points arcan_img.zig's externs resolve to.
    {
        const stb_image_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "stb_image", .root_module = b.createModule(.{
            .root_source_file = b.path("src/engine/external/stb_image.zig"),
            .target = opts.target, .optimize = opts.optimize, .pic = opts.pic,
        }) });
        addLibC(stb_image_obj, opts);
        exe.addObject(stb_image_obj);
    }
    exe.addIncludePath(b.path("src/engine/external"));
    // v4l2 capture support was C-only; encode.zig comptime-gates it off.
    addIncludes(exe, b, fsrv_a12_include_paths);
    exe.addIncludePath(b.path("src/shmif"));
    exe.linkLibrary(arcan_shmif);
    exe.linkLibrary(arcan_shmif_server);
    exe.linkLibrary(arcan_a12);
    linkFsrvStdlib(exe);
    return exe;
}

// ════════════════════════════════════════════════════════════════════
// Compositors (shared setup + VK / VK-LWA)
// ════════════════════════════════════════════════════════════════════

/// Shared setup for all compositor executables. Adds engine sources, TUI sources,
/// arcan_lua.c, platform posix sources (without open.c/psep_open — caller adds),
/// audio, Zig package deps, system deps, and internal library deps.
fn addCompositorCommon(
    exe: *std.Build.Step.Compile, b: *std.Build, opts: Opts,
    arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile,
) void {
    addPlatformDefinitions(exe, opts);
    exe.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
    exe.root_module.addCMacro("AGP_VULKAN", "");
    exe.root_module.addCMacro("HAVE_XKBCOMMON", "");
    exe.root_module.addCMacro("FRAMESERVER_MODESTRING", "\"terminal game net decode encode remoting avfeed\"");
    exe.root_module.addCMacro("ARCAN_BUILDVERSION", "\"mayhem-2026-03-09\"");
    addIncludes(exe, b, compositor_include_paths);

    // Engine C sources (most ported to Zig below)
    // arcan_frameserver_helpers.c replaced by .zig below

    // Shared Zig types + offset modules
    const types_mod = createMod(b, "src/engine/arcan_zig_types.zig", opts);
    const engine_offsets_mod = createMod(b, "src/engine/engine_offsets.zig", opts);
    const shmif_offsets_mod = createMod(b, "src/shmif/shmif_offsets.zig", opts);
    const shmif_types_mod = createMod(b, "src/shmif/shmif_types.zig", opts);
    const bootstrap_embed_mod = createMod(b, "src/engine/arcan_bootstrap_embed.zig", opts);

    // Use local TrueType.zig (with fvar/gvar variable font support) instead of external dependency
    const truetype_mod: ?*std.Build.Module = b.createModule(.{
        .root_source_file = b.path("src/engine/TrueType.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });

    // Zig-ported engine sources
    const zig_engine_sources: []const NamePath = &.{
        .{ .name = "arcan_main", .path = "src/engine/arcan_main.zig" },
        .{ .name = "alt_types", .path = "src/engine/alt/types.zig" },
        .{ .name = "alt_support", .path = "src/engine/alt/support.zig" },
        .{ .name = "alt_trace", .path = "src/engine/alt/trace.zig" },
        .{ .name = "arcan_ffunc_lut", .path = "src/engine/arcan_ffunc_lut.zig" },
        .{ .name = "arcan_audio", .path = "src/engine/arcan_audio.zig" },
        .{ .name = "arcan_img", .path = "src/engine/arcan_img.zig" },
        .{ .name = "arcan_led", .path = "src/engine/arcan_led.zig" },
        .{ .name = "arcan_vr", .path = "src/engine/arcan_vr.zig" },
        .{ .name = "arcan_vr_helpers", .path = "src/engine/arcan_vr_helpers.zig" },
        .{ .name = "arcan_math", .path = "src/engine/arcan_math.zig" },
        .{ .name = "arcan_db", .path = "src/engine/arcan_db.zig" },
        .{ .name = "arcan_event", .path = "src/engine/arcan_event.zig" },
        .{ .name = "arcan_raster", .path = "src/engine/arcan_raster.zig" },
        .{ .name = "arcan_conductor", .path = "src/engine/arcan_conductor.zig" },
        .{ .name = "arcan_frameserver", .path = "src/engine/arcan_frameserver.zig" },
        .{ .name = "alt_nbio", .path = "src/engine/alt/nbio.zig" },
        .{ .name = "arcan_3dbase", .path = "src/engine/arcan_3dbase.zig" },
        .{ .name = "arcan_monitor", .path = "src/engine/arcan_monitor.zig" },
        .{ .name = "arcan_renderfun", .path = "src/engine/arcan_renderfun.zig" },
        .{ .name = "arcan_ttf", .path = "src/engine/arcan_ttf.zig" },
        .{ .name = "zig_image_resize", .path = "src/engine/zig_image_resize.zig" },
        .{ .name = "arcan_video", .path = "src/engine/arcan_video.zig" },
        .{ .name = "arcan_frameserver_helpers", .path = "src/engine/arcan_frameserver_helpers.zig" },
        // Standalone-exe only: C `main` shim (arcan_main is the exported
        // engine entry) + stubs for single-binary integration points
        // (frameserver_dispatch, cl_env_warmup, ds4/zcs surfaces).
        .{ .name = "arcan_main_entry", .path = "src/engine/arcan_main_entry.zig" },
        .{ .name = "standalone_stubs", .path = "src/engine/standalone_stubs.zig" },
    };
    // Resolve xitdb module for arcan_db.zig
    const xitdb_mod_compositor = if (b.lazyDependency("xitdb", .{ .target = opts.target, .optimize = opts.optimize })) |dep|
        dep.module("xitdb")
    else
        null;
    const boot_compat_mod = b.createModule(.{
        .root_source_file = b.path("src/engine/arcan_boot_compat.zig"),
        .target = opts.target, .optimize = opts.optimize,
        .imports = &.{.{ .name = "arcan", .module = types_mod }},
    });
    const shmif_monitor_mod_engine = createMod(b, "src/engine/shmif_monitor.zig", opts);
    // posix_libc / shmif_types / a12_types / anet_types: hand-written pure-Zig
    // replacements for @cImport(stdio.h, ...) / @cImport(arcan_shmif.h, ...) /
    // @cImport(a12.h, ...) / @cImport(a12_helper.h, anet_helper.h, ...). Wired
    // into every engine source so the T46 sweep (which rewrites @cImport call
    // sites to @import("posix_libc") / @import("shmif_types") / etc.)
    // resolves cleanly at every build path without per-call-site wiring.
    const posix_libc_mod_engine = createMod(b, "src/platform/posix/libc.zig", opts);
    const a12_types_mod_engine = createA12TypesMod(b, opts, shmif_types_mod);
    const anet_types_mod_engine = createAnetTypesMod(b, opts, shmif_types_mod, a12_types_mod_engine, posix_libc_mod_engine);
    const lua54_api_mod_engine = createMod(b, "src/lua54/api.zig", opts);
    const base_imports: []const std.Build.Module.Import = &.{
        .{ .name = "arcan", .module = types_mod }, .{ .name = "engine_offsets", .module = engine_offsets_mod },
        .{ .name = "shmif_offsets", .module = shmif_offsets_mod }, .{ .name = "bootstrap_embed", .module = bootstrap_embed_mod },
        .{ .name = "arcan_boot_compat", .module = boot_compat_mod },
        .{ .name = "shmif_monitor", .module = shmif_monitor_mod_engine },
        .{ .name = "posix", .module = posix_libc_mod_engine },
        .{ .name = "shmif_types", .module = shmif_types_mod },
        .{ .name = "a12_types", .module = a12_types_mod_engine },
        .{ .name = "anet_types", .module = anet_types_mod_engine },
        .{ .name = "lua_api", .module = lua54_api_mod_engine },
    };
    const db_imports: []const std.Build.Module.Import = if (xitdb_mod_compositor) |m| &.{
        .{ .name = "arcan", .module = types_mod }, .{ .name = "engine_offsets", .module = engine_offsets_mod },
        .{ .name = "shmif_offsets", .module = shmif_offsets_mod }, .{ .name = "bootstrap_embed", .module = bootstrap_embed_mod },
        .{ .name = "arcan_boot_compat", .module = boot_compat_mod },
        .{ .name = "shmif_monitor", .module = shmif_monitor_mod_engine },
        .{ .name = "posix", .module = posix_libc_mod_engine },
        .{ .name = "shmif_types", .module = shmif_types_mod },
        .{ .name = "a12_types", .module = a12_types_mod_engine },
        .{ .name = "anet_types", .module = anet_types_mod_engine },
        .{ .name = "lua_api", .module = lua54_api_mod_engine },
        .{ .name = "xitdb", .module = m },
    } else base_imports;
    const ttf_imports: []const std.Build.Module.Import = if (truetype_mod) |m| &.{
        .{ .name = "arcan", .module = types_mod }, .{ .name = "engine_offsets", .module = engine_offsets_mod },
        .{ .name = "shmif_offsets", .module = shmif_offsets_mod }, .{ .name = "bootstrap_embed", .module = bootstrap_embed_mod },
        .{ .name = "arcan_boot_compat", .module = boot_compat_mod },
        .{ .name = "shmif_monitor", .module = shmif_monitor_mod_engine },
        .{ .name = "posix", .module = posix_libc_mod_engine },
        .{ .name = "shmif_types", .module = shmif_types_mod },
        .{ .name = "a12_types", .module = a12_types_mod_engine },
        .{ .name = "anet_types", .module = anet_types_mod_engine },
        .{ .name = "lua_api", .module = lua54_api_mod_engine },
        .{ .name = "TrueType", .module = m },
    } else base_imports;
    for (zig_engine_sources) |src| {
        const imports = if (std.mem.eql(u8, src.name, "arcan_db")) db_imports else if (std.mem.eql(u8, src.name, "arcan_ttf")) ttf_imports else base_imports;
        const obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = src.name, .root_module = b.createModule(.{
            .root_source_file = b.path(src.path), .target = opts.target, .optimize = opts.optimize,
            .imports = imports,
        }) });
        addLibC(obj, opts);
        addIncludes(obj, b, compositor_include_paths);
        exe.addObject(obj);
    }

    // TUI sources compiled directly (not via arcan_tui library) — engine provides
    // arcan_raster.c + arcan_ttf.c superseding TUI's raster.c + ttfstub.c
    addZigObjects(exe, b, opts, &.{
        .{ .name = "tui_main", .path = "src/shmif/tui/tui.zig" },
        .{ .name = "tui_linewnd", .path = "src/shmif/tui/widgets/linewnd.zig" },
        .{ .name = "tui_bufferwnd", .path = "src/shmif/tui/widgets/bufferwnd.zig" },
        .{ .name = "tui_listwnd", .path = "src/shmif/tui/widgets/listwnd.zig" },
        .{ .name = "tui_readline", .path = "src/shmif/tui/widgets/readline.zig" },
        .{ .name = "tui_copywnd", .path = "src/shmif/tui/widgets/copywnd.zig" },
        .{ .name = "tui_clipboard", .path = "src/shmif/tui/core/clipboard.zig" },
        .{ .name = "tui_input", .path = "src/shmif/tui/core/input.zig" },
        .{ .name = "tui_screen", .path = "src/shmif/tui/core/screen.zig" },
        .{ .name = "tui_dispatch", .path = "src/shmif/tui/core/dispatch.zig" },
        .{ .name = "tui_setup", .path = "src/shmif/tui/core/setup.zig" },
        .{ .name = "tui_fontmgmt", .path = "src/shmif/tui/raster/fontmgmt.zig" },
        .{ .name = "tui_pixelfont", .path = "src/shmif/tui/raster/pixelfont.zig" },
        .{ .name = "tui_font_data", .path = "src/shmif/tui/raster/font_data.zig" },
    }, &.{
        .{ .name = "arcan", .module = types_mod },
        .{ .name = "shmif_types", .module = shmif_types_mod },
        .{ .name = "posix", .module = posix_libc_mod_engine },
        .{ .name = "a12_types", .module = a12_types_mod_engine },
        .{ .name = "anet_types", .module = anet_types_mod_engine },
    }, &compositor_include_paths);

    // arcan_lua.zig (Zig port of arcan_lua.c) — compiled as object with same deps as engine sources
    {
        const obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "arcan_lua", .root_module = b.createModule(.{
            .root_source_file = b.path("src/engine/arcan_lua.zig"), .target = opts.target, .optimize = opts.optimize,
            .imports = &.{
                .{ .name = "arcan", .module = types_mod }, .{ .name = "engine_offsets", .module = engine_offsets_mod },
                .{ .name = "shmif_offsets", .module = shmif_offsets_mod }, .{ .name = "bootstrap_embed", .module = bootstrap_embed_mod },
                .{ .name = "arcan_boot_compat", .module = boot_compat_mod },
                .{ .name = "shmif_monitor", .module = shmif_monitor_mod_engine },
                .{ .name = "posix", .module = posix_libc_mod_engine },
                .{ .name = "shmif_types", .module = shmif_types_mod },
                .{ .name = "a12_types", .module = a12_types_mod_engine },
                .{ .name = "anet_types", .module = anet_types_mod_engine },
                .{ .name = "lua_api", .module = lua54_api_mod_engine },
            },
        }) });
        addLibC(obj, opts);
        addIncludes(obj, b, compositor_include_paths);
        exe.addObject(obj);
    }

    // bit.zig (luaopen_bit) — Zig port; stb_perlin.c stays as C (@cImport wrapper doesn't export C ABI)
    {
        const bit_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "bit", .root_module = b.createModule(.{
            .root_source_file = b.path("src/engine/external/bit.zig"), .target = opts.target, .optimize = opts.optimize,
            .imports = &.{
                .{ .name = "posix", .module = posix_libc_mod_engine },
                .{ .name = "shmif_types", .module = shmif_types_mod },
                .{ .name = "a12_types", .module = a12_types_mod_engine },
                .{ .name = "anet_types", .module = anet_types_mod_engine },
                .{ .name = "lua_api", .module = lua54_api_mod_engine },
            },
        }) });
        addLibC(bit_obj, opts);
        addIncludes(bit_obj, b, compositor_include_paths);
        exe.addObject(bit_obj);
    }
    // stb_perlin / stb_image — pure-Zig ports generated once via
    // `zig translate-c -lc` from the respective .h (with IMPLEMENTATION
    // defines), then post-processed to promote the public entry points to
    // `pub export fn` / `pub export var` so arcan_lua.zig / arcan_img.zig's
    // externs resolve at link. Compiled as objects so they participate in
    // link without dragging C TUs through aro.
    const stb_perlin_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "stb_perlin", .root_module = b.createModule(.{
        .root_source_file = b.path("src/engine/external/stb_perlin.zig"),
        .target = opts.target, .optimize = opts.optimize, .pic = opts.pic,
    }) });
    addLibC(stb_perlin_obj, opts);
    exe.addObject(stb_perlin_obj);
    const stb_image_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "stb_image", .root_module = b.createModule(.{
        .root_source_file = b.path("src/engine/external/stb_image.zig"),
        .target = opts.target, .optimize = opts.optimize, .pic = opts.pic,
    }) });
    addLibC(stb_image_obj, opts);
    exe.addObject(stb_image_obj);
    exe.addIncludePath(b.path("src/engine/external"));

    // Zig-ported platform sources
    const zig_platform_sources: []const NamePath = &.{
        .{ .name = "stub_setproctitle", .path = "src/platform/stub/setproctitle.zig" },
        .{ .name = "posix_config", .path = "src/platform/posix/config.zig" },
        .{ .name = "posix_tempfile", .path = "src/platform/posix/tempfile.zig" },
        .{ .name = "posix_fmt_open", .path = "src/platform/posix/fmt_open.zig" },
        .{ .name = "posix_dbpath", .path = "src/platform/posix/dbpath.zig" },
        .{ .name = "posix_strip_traverse", .path = "src/platform/posix/strip_traverse.zig" },
        .{ .name = "posix_resource_io", .path = "src/platform/posix/resource_io.zig" },
        .{ .name = "posix_sync", .path = "src/platform/posix/sync.zig" },
        .{ .name = "posix_base64", .path = "src/platform/posix/base64.zig" },
        .{ .name = "posix_prodthrd", .path = "src/platform/posix/prodthrd.zig" },
        .{ .name = "posix_map_resource", .path = "src/platform/posix/map_resource.zig" },
        .{ .name = "posix_appl", .path = "src/platform/posix/appl.zig" },
        .{ .name = "posix_glob", .path = "src/platform/posix/glob.zig" },
        .{ .name = "posix_paths", .path = "src/platform/posix/paths.zig" },
        .{ .name = "posix_namespace", .path = "src/platform/posix/namespace.zig" },
        .{ .name = "posix_launch", .path = "src/platform/posix/launch.zig" },
        .{ .name = "posix_sync_helpers", .path = "src/platform/posix/sync_helpers.zig" },
    };
    const offsets_mod = createMod(b, "src/shmif/shmif_offsets.zig", opts);
    for (zig_platform_sources) |src| {
        const obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = src.name, .root_module = b.createModule(.{
            .root_source_file = b.path(src.path), .target = opts.target, .optimize = opts.optimize,
            .imports = &.{
                .{ .name = "arcan", .module = types_mod },
                .{ .name = "shmif_offsets", .module = offsets_mod },
                .{ .name = "posix", .module = posix_libc_mod_engine },
                .{ .name = "shmif_types", .module = shmif_types_mod },
                .{ .name = "a12_types", .module = a12_types_mod_engine },
                .{ .name = "anet_types", .module = anet_types_mod_engine },
            },
        }) });
        addLibC(obj, opts);
        addIncludes(obj, b, compositor_include_paths);
        exe.addObject(obj);
    }

    // Audio (ma_alsa) — pure-Zig replacement for the OpenAL platform layer.
    // Routes device IO through dl_alsa (libasound dlopen'd at runtime via
    // zig_dlopen, cosmo-style). All `platform_audio_*` symbols come from
    // src/platform/audio/ma_alsa/platform_audio.zig — same C-ABI surface
    // arcan_audio.zig used to consume from openal.zig.
    {
        const zig_dlopen_api_audio = b.createModule(.{
            .root_source_file = b.path("src/platform/zig_dlopen_api.zig"),
            .target = opts.target, .optimize = opts.optimize,
        });
        const audio_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "platform_audio", .root_module = b.createModule(.{
            .root_source_file = b.path("src/platform/audio/ma_alsa/platform_audio.zig"),
            .target = opts.target, .optimize = opts.optimize,
            .imports = &.{
                .{ .name = "dlopen", .module = zig_dlopen_api_audio },
            },
        }) });
        addLibC(audio_obj, opts);
        // No pkg-config flags needed — no @cImport, no OpenAL headers.
        // libasound is loaded at runtime via dl_alsa shim (see
        // addRuntimeDlShims below).
        exe.addObject(audio_obj);
    }

    // Zig package deps
    addLua54AllObject(b, exe, opts);
    // sqlite3 removed — arcan_db.zig now uses xitdb (compiled in as Zig module, no linkLibrary needed)
    // freetype removed — arcan_ttf.zig now uses TrueType (pure Zig, no C library needed)
    // xkbcommon: loaded at runtime via zig_dlopen (dl_xkb shim) — no build-time link.

    // Install XKB data from system into zig-out/share/X11/xkb (self-contained derivation)
    b.installDirectory(.{ .source_dir = .{ .cwd_relative = "/usr/share/X11/xkb" }, .install_dir = .{ .custom = "share/X11/xkb" }, .install_subdir = "" });

    // Runtime-loaded C libs: openal, xkbcommon, libdrm — shim objects below
    // provide their symbols; the actual .so files are resolved at process
    // startup via zig_dlopen. No static link, no dynamic link at build time.
    addRuntimeDlShims(exe, b, opts);
    if (exe.rootModuleTarget().os.tag != .windows) exe.linkSystemLibrary("dl"); // win dlopen via kernel32 (windows port)
    linkFsrvStdlib(exe);

    // arcan_tui is NOT linked as a library — its sources are compiled directly above
    exe.linkLibrary(arcan_shmif);
    exe.linkLibrary(arcan_shmif_server);
}

// Vulkan compositor helpers
const VkModules = struct { vk_mod: *std.Build.Module, vulkan_mod: *std.Build.Module, zig_dlopen_mod: *std.Build.Module };

/// Shared Vulkan AGP setup: vulkan bindings module, vk_mod, vk_shared + vk_shdrmgmt objects.
fn addVulkanAgp(exe: *std.Build.Step.Compile, b: *std.Build, opts: Opts, name_suffix: []const u8) VkModules {
    // Pre-generated vulkan-zig bindings, committed at
    // src/platform/agp/generated/vk.zig. No generator binary to build/run
    // (which also unbreaks cross-compilation) and no host registry needed.
    const vulkan_mod = createMod(b, "src/platform/agp/generated/vk.zig", opts);
    const vk_mod = createMod(b, "src/platform/agp/vk.zig", opts);
    vk_mod.addImport("vulkan", vulkan_mod);
    // static_vulkan=true statically links a Vulkan ICD into the binary
    // (single-binary builds); the standalone build always loads the system
    // loader/ICD at runtime.
    const vk_build_opts = b.addOptions();
    vk_build_opts.addOption(bool, "static_vulkan", false);
    vk_mod.addImport("build_options", vk_build_opts.createModule());
    // zig_dlopen_api.zig — extern-only surface, shared by every module that
    // calls the dl shim. The strong `pub export fn` definitions live in
    // src/platform/zig_dlopen.zig and get compiled into exactly one object
    // (addRuntimeDlShims below). Using an extern-only module here prevents
    // every importer from exporting its own strong zig_dlopen/zig_dlsym
    // copy — without this, dl_openal.o / dl_xkb.o / dl_drm.o /
    // platform_vk_video.o each shipped identical strong definitions and
    // the fork's ELF linker couldn't dedup.
    const zig_dlopen_mod = b.createModule(.{
        .root_source_file = b.path("src/platform/zig_dlopen_api.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });
    vk_mod.addImport("dlopen", zig_dlopen_mod);
    for (compositor_include_paths) |dir| vk_mod.addIncludePath(b.path(dir));

    // Compile Slug GLSL shaders to SPIR-V before building vk_shared (which @embedFile's them)
    const shader_dir = "src/platform/agp/shaders";
    const slug_shaders = [_]struct { src: []const u8, out: []const u8, stage: []const u8 }{
        .{ .src = "slug_glyph.vert", .out = "slug_glyph_vert.spv", .stage = "-fshader-stage=vert" },
        .{ .src = "slug_glyph.frag", .out = "slug_glyph_frag.spv", .stage = "-fshader-stage=frag" },
        .{ .src = "slug_debug_frag.frag", .out = "slug_debug_frag.spv", .stage = "-fshader-stage=frag" },
        .{ .src = "slug_sdf_accum.vert", .out = "slug_sdf_accum_vert.spv", .stage = "-fshader-stage=vert" },
        .{ .src = "slug_sdf_accum.frag", .out = "slug_sdf_accum_frag.spv", .stage = "-fshader-stage=frag" },
        .{ .src = "slug_sdf_grade.comp", .out = "slug_sdf_grade.spv", .stage = "-fshader-stage=comp" },
    };
    var last_shader_step: ?*std.Build.Step = null;
    for (slug_shaders) |s| {
        const compile_shader = b.addSystemCommand(&.{
            "glslc", s.stage, b.pathJoin(&.{ shader_dir, s.src }), "-o", b.pathJoin(&.{ shader_dir, s.out }),
        });
        if (last_shader_step) |prev| compile_shader.step.dependOn(prev);
        last_shader_step = &compile_shader.step;
    }

    const cm_vk = coreMods(b, opts);
    const shared_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = b.fmt("agp_vk_shared{s}", .{name_suffix}), .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/agp/vk_shared.zig"), .target = opts.target, .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "posix", .module = cm_vk.posix_libc },
            .{ .name = "shmif_types", .module = cm_vk.shmif_types },
            .{ .name = "a12_types", .module = cm_vk.a12_types },
            .{ .name = "anet_types", .module = cm_vk.anet_types },
        },
    }) });
    if (last_shader_step) |shader_step| shared_obj.step.dependOn(shader_step);
    addLibC(shared_obj, opts);
    addIncludes(shared_obj, b, compositor_include_paths);
    exe.addObject(shared_obj);

    const shdrmgmt_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = b.fmt("agp_vk_shdrmgmt{s}", .{name_suffix}), .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/agp/vk_shdrmgmt.zig"), .target = opts.target, .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "posix", .module = cm_vk.posix_libc },
            .{ .name = "shmif_types", .module = cm_vk.shmif_types },
            .{ .name = "a12_types", .module = cm_vk.a12_types },
            .{ .name = "anet_types", .module = cm_vk.anet_types },
        },
    }) });
    addLibC(shdrmgmt_obj, opts);
    addIncludes(shdrmgmt_obj, b, compositor_include_paths);
    exe.addObject(shdrmgmt_obj);

    return .{ .vk_mod = vk_mod, .vulkan_mod = vulkan_mod, .zig_dlopen_mod = zig_dlopen_mod };
}

fn createArcanVk(b: *std.Build, opts: Opts, arcan_shmif: *std.Build.Step.Compile, arcan_shmif_server: *std.Build.Step.Compile) *std.Build.Step.Compile {
    const exe = createExe(b, "arcan", opts);
    addCompositorCommon(exe, b, opts, arcan_shmif, arcan_shmif_server);
    const vk = addVulkanAgp(exe, b, opts, "");

    // WSI module (swapchain)
    const vk_wsi_mod = createMod(b, "src/platform/agp/vk_wsi.zig", opts);
    vk_wsi_mod.addImport("vulkan", vk.vulkan_mod);
    vk_wsi_mod.addImport("vk.zig", vk.vk_mod);
    for (compositor_include_paths) |dir| vk_wsi_mod.addIncludePath(b.path(dir));

    // XCB window module
    const vk_xcb_mod = createMod(b, "src/platform/agp/vk_xcb.zig", opts);
    vk_xcb_mod.addImport("vulkan", vk.vulkan_mod);
    for (compositor_include_paths) |dir| vk_xcb_mod.addIncludePath(b.path(dir));
    // XCB headers for @cImport type definitions (loaded at runtime on musl via zig_dlopen)
    if (opts.ext.xcb) |xcb_lib| {
        vk_xcb_mod.addIncludePath(xcb_lib.getEmittedIncludeTree());
    } else {
        // pkg-config --cflags xcb returns empty on standard installs (/usr/include).
        // Musl sysroot doesn't include /usr/include, so add it explicitly.
        vk_xcb_mod.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
    }
    // zig_dlopen import for runtime XCB loading on static musl (shared with vk.zig)
    vk_xcb_mod.addImport("dlopen", vk.zig_dlopen_mod);
    // xkbcommon headers: from system /usr/include (symbols loaded at runtime via dl_xkb shim)
    vk_xcb_mod.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });

    // Offscreen module (for LWA mode)
    const vk_offscreen_mod = createMod(b, "src/platform/agp/vk_offscreen.zig", opts);
    vk_offscreen_mod.addImport("vulkan", vk.vulkan_mod);
    vk_offscreen_mod.addImport("vk.zig", vk.vk_mod);
    for (compositor_include_paths) |dir| vk_offscreen_mod.addIncludePath(b.path(dir));

    // GBM+KMS direct-to-display module (for Asahi/split-DRM hardware where
    // the Vulkan ICD doesn't implement VK_KHR_display; see vk_gbm_kms.zig).
    const vk_gbm_kms_mod = createMod(b, "src/platform/agp/vk_gbm_kms.zig", opts);
    vk_gbm_kms_mod.addImport("vulkan", vk.vulkan_mod);
    vk_gbm_kms_mod.addImport("vk.zig", vk.vk_mod);
    for (compositor_include_paths) |dir| vk_gbm_kms_mod.addIncludePath(b.path(dir));
    // libdrm headers (xf86drm.h, xf86drmMode.h) for @cImport — from system.
    // Symbols are resolved at runtime via dl_drm shim linked into the exe.
    vk_gbm_kms_mod.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
    vk_gbm_kms_mod.addSystemIncludePath(.{ .cwd_relative = "/usr/include/libdrm" });

    // Platform video.zig (unified: XCB + KHR_display + GBM_KMS + LWA + Metal)
    // Metal WSI module (macOS only; comptime-dead elsewhere but the import
    // name must still resolve under stock zig)
    const vk_metal_mod = createMod(b, "src/platform/agp/macos/vk_metal.zig", opts);
    vk_metal_mod.addImport("vulkan", vk.vulkan_mod);

    // Win32 WSI module (windows only; comptime-dead elsewhere but the import
    // name must still resolve).
    const vk_win32_mod = createMod(b, "src/platform/agp/win32/vk_win32.zig", opts);
    vk_win32_mod.addImport("vulkan", vk.vulkan_mod);

    // Native window implementation per target: macOS Cocoa/CAMetalLayer or
    // Windows Win32/HWND. Each exports the soma_window_* surface the WSI
    // module externs, and resolves its OS libraries (AppKit/Metal, or
    // user32/gdi32) via dlopen at runtime — the cross-link from Linux needs
    // nothing beyond the target's base libSystem/kernel32.
    switch (opts.target.result.os.tag) {
        .ios, .macos, .watchos, .tvos => {
            const cocoa_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "cocoa_window", .root_module = b.createModule(.{
                .root_source_file = b.path("src/platform/agp/macos/cocoa_window.zig"),
                .target = opts.target, .optimize = opts.optimize,
            }) });
            addLibC(cocoa_obj, opts);
            exe.addObject(cocoa_obj);
        },
        .windows => {
            const win32_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "win32_window", .root_module = b.createModule(.{
                .root_source_file = b.path("src/platform/agp/win32/win32_window.zig"),
                .target = opts.target, .optimize = opts.optimize,
            }) });
            addLibC(win32_obj, opts);
            exe.addObject(win32_obj);
        },
        else => {},
    }

    const cm_video = coreMods(b, opts);
    const video_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "platform_vk_video", .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/vk-display/video.zig"), .target = opts.target, .optimize = opts.optimize,
    }) });
    addLibC(video_obj, opts);
    video_obj.root_module.addImport("vulkan", vk.vulkan_mod);
    video_obj.root_module.addImport("vk.zig", vk.vk_mod);
    video_obj.root_module.addImport("vk_wsi.zig", vk_wsi_mod);
    video_obj.root_module.addImport("vk_xcb.zig", vk_xcb_mod);
    video_obj.root_module.addImport("vk_offscreen.zig", vk_offscreen_mod);
    video_obj.root_module.addImport("vk_gbm_kms.zig", vk_gbm_kms_mod);
    video_obj.root_module.addImport("vk_metal.zig", vk_metal_mod);
    video_obj.root_module.addImport("vk_win32.zig", vk_win32_mod);
    video_obj.root_module.addImport("posix", cm_video.posix_libc);
    video_obj.root_module.addImport("shmif_types", cm_video.shmif_types);
    video_obj.root_module.addImport("a12_types", cm_video.a12_types);
    video_obj.root_module.addImport("anet_types", cm_video.anet_types);
    addIncludes(video_obj, b, compositor_include_paths);
    exe.addObject(video_obj);

    // Platform evdev event handling (Zig port)
    const cm_evdev = coreMods(b, opts);
    const event_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "platform_evdev_event", .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/evdev/event.zig"), .target = opts.target, .optimize = opts.optimize,
    }) });
    event_obj.root_module.addImport("arcan", createMod(b, "src/engine/arcan_zig_types.zig", opts));
    event_obj.root_module.addImport("posix", cm_evdev.posix_libc);
    event_obj.root_module.addImport("shmif_types", cm_evdev.shmif_types);
    event_obj.root_module.addImport("a12_types", cm_evdev.a12_types);
    event_obj.root_module.addImport("anet_types", cm_evdev.anet_types);
    event_obj.root_module.addImport("evdev_types", createMod(b, "src/platform/evdev/evdev_types.zig", opts));
    addLibC(event_obj, opts);
    addIncludes(event_obj, b, compositor_include_paths);
    event_obj.root_module.addIncludePath(b.path("src/platform/evdev"));
    // xkbcommon + xcb headers from system /usr/include (symbols loaded at
    // runtime via dl_xkb shim and the existing zig_dlopen XCB path).
    build_helpers.addPkgConfigCflags(event_obj, "xkbcommon");
    build_helpers.addPkgConfigCflags(event_obj, "xcb");
    exe.addObject(event_obj);
    // Keyboard lookup table (replaces deleted C keycode_xlate.h)
    const cm_keymap = coreMods(b, opts);
    const keymap_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "evdev_keymap", .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/evdev/keymap.zig"), .target = opts.target, .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "posix", .module = cm_keymap.posix_libc },
            .{ .name = "shmif_types", .module = cm_keymap.shmif_types },
            .{ .name = "a12_types", .module = cm_keymap.a12_types },
            .{ .name = "anet_types", .module = cm_keymap.anet_types },
        },
    }) });
    exe.addObject(keymap_obj);
    addPsepOpen(exe, b, opts);
    // libdrm / xkbcommon / xcb: all loaded at runtime via zig_dlopen shims.
    // addRuntimeDlShims (called above) added the shim objects; nothing more
    // to link here.
    if (opts.target.result.abi != .musl and opts.target.result.os.tag != .windows) {
        exe.linkSystemLibrary("dl");
    }
    return exe;
}


// ════════════════════════════════════════════════════════════════════
// Utility functions (platform defs, shmif sources, pkg-config, etc.)
// ════════════════════════════════════════════════════════════════════
fn addPlatformDefinitions(step: *std.Build.Step.Compile, opts: Opts) void {
    const bsd_platform_definitions = [_][2]String{ .{ "_WITH_GETLINE", "" }, .{ "__UNIX", "" }, .{ "__BSD", "" }, .{ "LIBUSB_BSD", "" } };
    const platform_definitions: []const [2]String = switch (opts.target.result.os.tag) {
        .linux => &.{ .{ "__UNIX", "" }, .{ "__LINUX", "" }, .{ "POSIX_C_SOURCE", "" }, .{ "_GNU_SOURCE", "" } },
        .ios, .macos, .watchos, .tvos => &.{ .{ "__UNIX", "" }, .{ "POSIX_C_SOURCE", "" }, .{ "__APPLE__", "" }, .{ "ARCAN_SHMIF_OVERCOMMIT", "" }, .{ "_WITH_DPRINTF", "" }, .{ "_GNU_SOURCE", "" } },
        .freebsd => &(bsd_platform_definitions ++ .{.{ "__FreeBSD__", "" }}),
        .dragonfly => &(bsd_platform_definitions ++ .{.{ "__DragonFly__", "" }}),
        .openbsd => &(bsd_platform_definitions ++ .{ .{ "__OpenBSD__", "" }, .{ "CLOCK_MONOTONIC_RAW", "CLOCK_MONOTONIC" } }),
        .netbsd => &(bsd_platform_definitions ++ .{ .{ "__NetBSD__", "" }, .{ "CLOCK_MONOTONIC_RAW", "CLOCK_MONOTONIC" } }),
        else => &(.{}),
    };
    for (platform_definitions) |def| step.root_module.addCMacro(def[0], def[1]);
}

fn addEvpackSource(b: *std.Build, step: *std.Build.Step.Compile, opts: Opts) void {
    const cm = coreMods(b, opts);
    const obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "arcan_shmif_evpack", .root_module = b.createModule(.{
        .root_source_file = b.path("src/shmif/arcan_shmif_evpack.zig"), .target = opts.target, .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "shmif_types", .module = cm.shmif_types },
            .{ .name = "posix", .module = cm.posix_libc },
            .{ .name = "a12_types", .module = cm.a12_types },
            .{ .name = "anet_types", .module = cm.anet_types },
        },
    }) });
    addLibC(obj, opts);
    addIncludes(obj, b, shmif_include_paths);
    step.addObject(obj);
}

fn addArcanMathZig(b: *std.Build, exe: *std.Build.Step.Compile, opts: Opts) void {
    const cm = coreMods(b, opts);
    const obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "arcan_math", .root_module = b.createModule(.{
        .root_source_file = b.path("src/engine/arcan_math.zig"), .target = opts.target, .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "posix", .module = cm.posix_libc },
            .{ .name = "shmif_types", .module = cm.shmif_types },
            .{ .name = "a12_types", .module = cm.a12_types },
            .{ .name = "anet_types", .module = cm.anet_types },
        },
    }) });
    addLibC(obj, opts);
    exe.addObject(obj);
}

/// Build the fsrv_opts options module that frameserver.zig consumes for
/// dispatch (replaces former `@hasDecl(c, "ENABLE_FSRV_*")` / "AFSRV_CHAINLOADER"
/// gates — those silently broke once the @cImport block was replaced with a
/// hand-written struct, since C macros don't bleed into Zig structs).
fn makeFsrvOpts(b: *std.Build, mode_str: ?[]const u8, is_chainloader: bool) *std.Build.Module {
    const opts_step = b.addOptions();
    opts_step.addOption(bool, "is_chainloader", is_chainloader);
    opts_step.addOption(?[]const u8, "default_mode", mode_str);
    const eq = std.mem.eql;
    opts_step.addOption(bool, "enable_decode",   if (mode_str) |m| eq(u8, m, "decode")   else false);
    opts_step.addOption(bool, "enable_terminal", if (mode_str) |m| eq(u8, m, "terminal") else false);
    opts_step.addOption(bool, "enable_encode",   if (mode_str) |m| eq(u8, m, "encode")   else false);
    opts_step.addOption(bool, "enable_remoting", if (mode_str) |m| eq(u8, m, "remoting") else false);
    opts_step.addOption(bool, "enable_game",     if (mode_str) |m| eq(u8, m, "game")     else false);
    opts_step.addOption(bool, "enable_avfeed",   if (mode_str) |m| eq(u8, m, "avfeed")   else false);
    opts_step.addOption(bool, "enable_bun",      if (mode_str) |m| eq(u8, m, "bun")      else false);
    opts_step.addOption(bool, "enable_probe",    if (mode_str) |m| eq(u8, m, "probe")    else false);
    opts_step.addOption(bool, "enable_net",      if (mode_str) |m| eq(u8, m, "net")      else false);
    return opts_step.createModule();
}

/// Compile frameserver.zig with the correct ENABLE_FSRV_* and DEFAULT_FSRV_MODE macros.
/// Empty C defines don't become Zig declarations visible to @hasDecl, so we use "1".
/// C `main` shim for standalone frameserver exes — frameserver.zig only
/// exports `frameserver_entry` (see frameserver_main_entry.zig).
fn addFrameserverEntry(b: *std.Build, exe: *std.Build.Step.Compile, opts: Opts) void {
    const obj = b.addObject(.{ .use_llvm = use_llvm_default,
        .name = "frameserver_entry",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/frameserver/frameserver_main_entry.zig"),
            .target = opts.target, .optimize = opts.optimize, .pic = opts.pic,
        }),
    });
    addLibC(obj, opts);
    exe.addObject(obj);
}

fn addFrameserverZig(b: *std.Build, exe: *std.Build.Step.Compile, opts: Opts, enable_macro: []const u8, mode_str: []const u8) void {
    const offsets_mod = createMod(b, "src/shmif/shmif_offsets.zig", opts);
    const a12_offsets_mod = createMod(b, "src/a12/a12_offsets.zig", opts);
    const shmif_types_mod_fs = createMod(b, "src/shmif/shmif_types.zig", opts);
    const posix_libc_mod = createMod(b, "src/platform/posix/libc.zig", opts);
    const a12_types_mod_fs = createA12TypesMod(b, opts, shmif_types_mod_fs);
    const anet_types_mod_fs = createAnetTypesMod(b, opts, shmif_types_mod_fs, a12_types_mod_fs, posix_libc_mod);
    const fsrv_opts_mod = makeFsrvOpts(b, mode_str, false);
    const obj = b.addObject(.{ .use_llvm = use_llvm_default,
        .name = "frameserver",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/frameserver/frameserver.zig"),
            .target = opts.target, .optimize = opts.optimize, .pic = opts.pic,
            .imports = &.{
                .{ .name = "shmif_offsets", .module = offsets_mod },
                .{ .name = "a12_offsets", .module = a12_offsets_mod },
                .{ .name = "shmif_types", .module = shmif_types_mod_fs },
                .{ .name = "posix", .module = posix_libc_mod },
                .{ .name = "a12_types", .module = a12_types_mod_fs },
                .{ .name = "anet_types", .module = anet_types_mod_fs },
                .{ .name = "fsrv_opts", .module = fsrv_opts_mod },
            },
        }),
    });
    addLibC(obj, opts);
    obj.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
    obj.root_module.addCMacro(enable_macro, "1");
    obj.root_module.addCMacro("DEFAULT_FSRV_MODE", b.fmt("\"{s}\"", .{mode_str}));
    addPlatformDefinitions(obj, opts);
    addIncludes(obj, b, shmif_include_paths);
    exe.addObject(obj);
    addFrameserverEntry(b, exe, opts);
}

fn addShmifZigSource(b: *std.Build, step: *std.Build.Step.Compile, zig_path: []const u8, opts: Opts) void {
    addShmifZigSourceInner(b, step, zig_path, opts, useLlvmForSource(b, zig_path), shmif_include_paths);
}

fn addShmifZigSourceNoLlvm(b: *std.Build, step: *std.Build.Step.Compile, zig_path: []const u8, opts: Opts) void {
    addShmifZigSourceInner(b, step, zig_path, opts, false, shmif_include_paths);
}

fn addShmifZigSourceForceLlvm(b: *std.Build, step: *std.Build.Step.Compile, zig_path: []const u8, opts: Opts) void {
    addShmifZigSourceInner(b, step, zig_path, opts, true, shmif_include_paths);
}

fn addA12ZigSource(b: *std.Build, step: *std.Build.Step.Compile, zig_path: []const u8, opts: Opts) void {
    addShmifZigSourceInnerA12(b, step, zig_path, opts, useLlvmForSource(b, zig_path), shmif_include_paths ++ a12_include_paths);
}

fn addShmifZigSourceInnerA12(b: *std.Build, step: *std.Build.Step.Compile, zig_path: []const u8, opts: Opts, use_llvm: ?bool, include_paths: []const String) void {
    const offsets_mod = createMod(b, "src/shmif/shmif_offsets.zig", opts);
    const a12_offsets_mod = createMod(b, "src/a12/a12_offsets.zig", opts);
    const shmif_monitor_mod = createMod(b, "src/engine/shmif_monitor.zig", opts);
    const posix_libc_mod = createMod(b, "src/platform/posix/libc.zig", opts);
    const shmif_types_mod = createMod(b, "src/shmif/shmif_types.zig", opts);
    const a12_types_mod = createA12TypesMod(b, opts, shmif_types_mod);
    const anet_types_mod = createAnetTypesMod(b, opts, shmif_types_mod, a12_types_mod, posix_libc_mod);
    const obj = b.addObject(.{
        .name = std.fs.path.stem(zig_path),
        .root_module = b.createModule(.{
            .root_source_file = b.path(zig_path), .target = opts.target, .optimize = opts.optimize, .pic = opts.pic,
            .imports = &.{
                .{ .name = "shmif_offsets", .module = offsets_mod },
                .{ .name = "a12_offsets", .module = a12_offsets_mod },
                .{ .name = "shmif_monitor", .module = shmif_monitor_mod },
                .{ .name = "posix", .module = posix_libc_mod },
                .{ .name = "a12_types", .module = a12_types_mod },
                .{ .name = "anet_types", .module = anet_types_mod },
                .{ .name = "shmif_types", .module = shmif_types_mod },
            },
        }),
        .use_llvm = use_llvm,
    });
    addLibC(obj, opts);
    obj.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
    addPlatformDefinitions(obj, opts);
    addIncludes(obj, b, include_paths);
    // a12 Zig objects need MLK_CONFIG defines for mlkem headers
    for ([_][2]String{
        .{ "MLK_CONFIG_PARAMETER_SET", "768" }, .{ "MLK_CONFIG_NAMESPACE_PREFIX", "mlkem" },
    }) |def| obj.root_module.addCMacro(def[0], def[1]);
    step.addObject(obj);
}

fn addShmifZigSourceInner(b: *std.Build, step: *std.Build.Step.Compile, zig_path: []const u8, opts: Opts, use_llvm: ?bool, include_paths: []const String) void {
    const offsets_mod = createMod(b, "src/shmif/shmif_offsets.zig", opts);
    const a12_offsets_mod = createMod(b, "src/a12/a12_offsets.zig", opts);
    const shmif_types_mod = createMod(b, "src/shmif/shmif_types.zig", opts);
    const shmif_api_mod = b.createModule(.{
        .root_source_file = b.path("src/shmif/shmif_api.zig"),
        .target = opts.target, .optimize = opts.optimize,
        .imports = &.{.{ .name = "shmif_types", .module = shmif_types_mod }},
    });
    const posix_libc_mod = createMod(b, "src/platform/posix/libc.zig", opts);
    const a12_types_mod = createA12TypesMod(b, opts, shmif_types_mod);
    const anet_types_mod = createAnetTypesMod(b, opts, shmif_types_mod, a12_types_mod, posix_libc_mod);
    const shmif_monitor_mod = createMod(b, "src/engine/shmif_monitor.zig", opts);
    const obj = b.addObject(.{
        .name = std.fs.path.stem(zig_path),
        .root_module = b.createModule(.{
            .root_source_file = b.path(zig_path), .target = opts.target, .optimize = opts.optimize, .pic = opts.pic,
            .imports = &.{
                .{ .name = "shmif_offsets", .module = offsets_mod },
                .{ .name = "a12_offsets", .module = a12_offsets_mod },
                .{ .name = "shmif_types", .module = shmif_types_mod },
                .{ .name = "shmif_api", .module = shmif_api_mod },
                .{ .name = "posix", .module = posix_libc_mod },
                .{ .name = "a12_types", .module = a12_types_mod },
                .{ .name = "anet_types", .module = anet_types_mod },
                .{ .name = "shmif_monitor", .module = shmif_monitor_mod },
            },
        }),
        .use_llvm = use_llvm,
    });
    addLibC(obj, opts);
    obj.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
    addPlatformDefinitions(obj, opts);
    addIncludes(obj, b, include_paths);
    step.addObject(obj);
}

fn addShmifPlatformSources(b: *std.Build, lib: *std.Build.Step.Compile, opts: Opts) void {
    // shmif_libc_helpers.c removed — functionality ported to Zig
    for ([_]String{ "src/platform/posix/shmemop.zig", "src/platform/posix/fdscan.zig", "src/platform/posix/random.zig" }) |zig_src|
        addShmifZigSource(b, lib, zig_src, opts);
    // warning.zig's arcan_warning/arcan_fatal are variadic. The aarch64 SH
    // backend can emit @cVaStart bodies, so on linux/bsd/macOS warning.zig
    // is compiled with the SH backend and defines them in pure Zig. On
    // x86_64-windows neither backend can (LLVM disables it, SH has no Win64
    // var-arg codegen) — there warning.zig compiles under LLVM with
    // va_in_zig=false (so it does NOT emit the bodies) and warning_va.c
    // supplies them, compiled by the bundled clang.
    if (opts.target.result.os.tag == .windows) {
        addShmifZigSource(b, lib, "src/platform/posix/warning.zig", opts); // LLVM (use_llvm_default)
        addCSources(lib, b, &.{"src/platform/posix/warning_va.c"});
    } else {
        addShmifZigSourceNoLlvm(b, lib, "src/platform/posix/warning.zig", opts);
    }
    addShmifZigSource(b, lib, "src/platform/posix/fdpassing_nonblock.zig", opts);
    switch (opts.target.result.os.tag) {
        .linux, .freebsd, .openbsd, .dragonfly, .netbsd => {
            for ([_]String{ "src/platform/posix/time.zig", "src/platform/posix/sem.zig" }) |zig_src|
                addShmifZigSource(b, lib, zig_src, opts);
        },
        .ios, .macos, .watchos, .tvos => {
            // Darwin needs the mach clock + named-semaphore shims (pure Zig
            // ports of the old darwin/{time,sem}.c).
            for ([_]String{ "src/platform/darwin/time.zig", "src/platform/darwin/sem.zig" }) |zig_src|
                addShmifZigSource(b, lib, zig_src, opts);
        },
        .windows => {
            // Win32 substrate: clock (QueryPerformanceCounter), semaphores
            // (CreateSemaphore), and the broader posix shim layer.
            for ([_]String{ "src/platform/windows/time.zig", "src/platform/windows/sem.zig" }) |zig_src|
                addShmifZigSource(b, lib, zig_src, opts);
        },
        else => {},
    }
}

// Adds the three runtime-dlopen shim objects (openal, xkbcommon, libdrm)
// to the exe. Each shim exports C-ABI wrapper functions with the same
// names as the real library symbols; the wrappers forward to function
// pointers resolved at first use via zig_dlopen/zig_dlsym. This lets the
// static musl exe link without the real .so files and load them at
// startup from the host (glibc) system.
fn addRuntimeDlShims(exe: *std.Build.Step.Compile, b: *std.Build, opts: Opts) void {
    // Single implementing object for zig_dlopen's strong symbols. Every
    // consumer imports zig_dlopen_api (declared via createModule under name
    // "zig_dlopen") which provides `extern fn` decls only. Without this
    // split, dl_openal / dl_xkb / dl_drm / platform_vk_video each re-emit
    // `pub export fn zig_dlopen/zig_dlsym/...` and the linker gets 4-way
    // strong-symbol collisions.
    const zig_dlopen_api_mod = b.createModule(.{
        .root_source_file = b.path("src/platform/zig_dlopen_api.zig"),
        .target = opts.target, .optimize = opts.optimize,
    });
    const zig_dlopen_impl_obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "dlopen", .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/zig_dlopen.zig"),
        .target = opts.target, .optimize = opts.optimize,
    }) });
    addLibC(zig_dlopen_impl_obj, opts);
    exe.addObject(zig_dlopen_impl_obj);

    const shims: []const struct { name: []const u8, path: []const u8 } = &.{
        .{ .name = "dl_openal", .path = "src/platform/dl/dl_openal.zig" },
        .{ .name = "dl_xkb", .path = "src/platform/dl/dl_xkb.zig" },
        .{ .name = "dl_drm", .path = "src/platform/dl/dl_drm.zig" },
        .{ .name = "dl_alsa", .path = "src/platform/dl/dl_alsa.zig" },
    };
    for (shims) |s| {
        const obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = s.name, .root_module = b.createModule(.{
            .root_source_file = b.path(s.path),
            .target = opts.target, .optimize = opts.optimize,
            .imports = &.{.{ .name = "dlopen", .module = zig_dlopen_api_mod }},
        }) });
        addLibC(obj, opts);
        exe.addObject(obj);
    }
}

fn addPsepOpen(exe: *std.Build.Step.Compile, b: *std.Build, opts: Opts) void {
    const cm = coreMods(b, opts);
    const obj = b.addObject(.{ .use_llvm = use_llvm_default, .name = "posix_psep_open", .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/posix/psep_open.zig"), .target = opts.target, .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "posix", .module = cm.posix_libc },
            .{ .name = "shmif_types", .module = cm.shmif_types },
            .{ .name = "a12_types", .module = cm.a12_types },
            .{ .name = "anet_types", .module = cm.anet_types },
        },
    }) });
    addLibC(obj, opts);
    addIncludes(obj, b, compositor_include_paths);
    // libdrm headers only; symbols come from dl_drm shim on the exe.
    build_helpers.addPkgConfigCflags(obj, "libdrm");
    exe.addObject(obj);
}

const linkPkgConfig = build_helpers.linkPkgConfig;
const addPkgConfigCflags = build_helpers.addPkgConfigCflags;
const getPkgConfigVariable = build_helpers.getPkgConfigVariable;


// LLVM-implicating integrations (qtarcan, gamescope, llama-cli, afsrv_bun)
// live in the build_llvm/ sub-package — see build_llvm/build.zig and
// build_llvm/build.zig.zon. Self-host-friendly external integrations
// (xarcan) stay top-level in build_xarcan.zig.
