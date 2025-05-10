const std = @import("std");

const String = []const u8;

const a12_version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};
const shmif_version = std.SemanticVersion{
    .major = 0,
    .minor = 17,
    .patch = 0,
};

pub fn build(b: *std.Build) void {
    const platform_header_path = b.path("./src/platform/platform.h").getPath(b);

    const opts = .{
        .platform_header = b.fmt("\"{s}\"", .{platform_header_path}),

        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),

        .static = b.option(bool, "static", "Statically linked build (default: true)") orelse true,
        .strip = b.option(bool, "strip", "Omit debug information"),
        .pic = b.option(bool, "pic", "Produce Position Independent Code"),

        .build_shmif_server = b.option(bool, "build_shmif_server", "Build arcan_shmif_server library (default: true)") orelse true,
        .build_shmif = b.option(bool, "build_shmif", "Build arcan_shmif library (default: true)") orelse true,
        .build_tui = b.option(bool, "build_tui", "Build arcan_tui library (default: true)") orelse true,
        .build_a12 = b.option(bool, "build_a12", "Build arcan_a12 library (default: true)") orelse true,

        .with_debugif = b.option(bool, "with_debugif", "Build with shmif debugif (default: true)") orelse true,
        .with_ffmpeg = b.option(bool, "with_ffmpeg", "Build with h264 encode/decode support using ffmpeg (default: true)") orelse true,

        .use_system_ffmpeg = b.systemIntegrationOption("ffmpeg", .{ .default = false }),
    };

    switch (opts.target.result.os.tag) {
        .linux,
        .ios,
        .macos,
        .watchos,
        .tvos,
        .freebsd,
        .dragonfly,
        .kfreebsd,
        .openbsd,
        .netbsd,
        => {},
        .windows => {
            if (opts.build_shmif) @panic("Arcan shmif build is unsupported on Windows");
        },
        else => |t| std.debug.panic("Unsupported platform: {s}", .{@tagName(t)}),
    }

    const arcan_api = createArcanApi(b, opts);
    _ = arcan_api.addModule("arcan");

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
    if (opts.build_shmif) {
        arcan_a12.linkLibrary(arcan_shmif);
        arcan_a12.linkLibrary(arcan_shmif_server);
    }
    if (opts.build_a12) b.installArtifact(arcan_a12);
}

const shmif_include_paths: []const String = &.{
    "src/shmif",
    "src/shmif/tui",
    "src/shmif/tui/lua",
    "src/shmif/tui/widgets",
    "src/shmif/platform",
    "src/engine",
    "src/platform",
};

const shmif_tui_include_paths: []const String = &.{
    "src/frameserver",
    "src/engine",
    "src/engine/external",
    "src/shmif",
};

const a12_include_paths: []const String = &.{
    "src/a12",
    "src/a12/external/blake3",
    "src/a12/external/zstd",
    "src/a12/external/zstd/common",
    "src/a12/external",
    "src/engine",
    "src/shmif",
};

fn createArcanApi(b: *std.Build, opts: anytype) *std.Build.Step.TranslateC {
    const step = b.addTranslateC(.{
        .root_source_file = b.path("src/arcan.h"),
        .target = opts.target,
        .optimize = opts.optimize,
    });

    step.defineCMacroRaw(b.fmt("PLATFORM_HEADER={s}", .{opts.platform_header}));
    if (opts.build_shmif) step.defineCMacroRaw("BUILD_SHMIF");
    if (opts.build_tui) step.defineCMacroRaw("BUILD_TUI");
    if (opts.build_a12) step.defineCMacroRaw("BUILD_A12");

    for (shmif_include_paths) |dir| {
        step.addIncludeDir(b.path(dir).getPath(b));
    }

    for (a12_include_paths) |dir| {
        step.addIncludeDir(b.path(dir).getPath(b));
    }

    for (shmif_tui_include_paths) |dir| {
        step.addIncludeDir(b.path(dir).getPath(b));
    }

    return step;
}

fn createArcanShmifServer(b: *std.Build, opts: anytype) *std.Build.Step.Compile {
    const lib_opts = .{
        .name = "arcan_shmif_server",
        .version = shmif_version,
        .target = opts.target,
        .optimize = opts.optimize,
        .pic = opts.pic,
        .strip = opts.strip,
    };
    const step = if (opts.static)
        b.addStaticLibrary(lib_opts)
    else
        b.addSharedLibrary(lib_opts);

    step.linkLibC();
    addShmifHeaders(b, step);
    addShmifPlatformSources(b, step, opts);
    addPlatformDefinitions(step, opts);
    step.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);

    const shmif_server_sources: []const String = &.{
        "src/shmif/arcan_shmif_server.c",
        "src/platform/posix/frameserver.c",
        "src/shmif/arcan_shmif_control.c",
        "src/platform/posix/fsrv_guard.c",
        "src/platform/posix/mem.c",
        "src/shmif/arcan_shmif_evpack.c",
        "src/shmif/platform/exec.c",
    };
    for (shmif_server_sources) |source| {
        step.addCSourceFile(.{ .file = b.path(source) });
    }

    for (shmif_include_paths) |dir| {
        step.addIncludePath(b.path(dir));
    }

    return step;
}

fn createArcanShmif(b: *std.Build, opts: anytype) *std.Build.Step.Compile {
    const lib_opts = .{
        .name = "arcan_shmif",
        .version = shmif_version,
        .target = opts.target,
        .optimize = opts.optimize,
        .pic = opts.pic,
        .strip = opts.strip,
    };
    const step = if (opts.static)
        b.addStaticLibrary(lib_opts)
    else
        b.addSharedLibrary(lib_opts);

    step.linkLibC();
    addShmifHeaders(b, step);
    addShmifPlatformSources(b, step, opts);
    addPlatformDefinitions(step, opts);
    step.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);

    const shmif_sources: []const String = &.{
        "src/shmif/arcan_shmif_control.c",
        "src/shmif/arcan_shmif_sub.c",
        "src/shmif/arcan_shmif_evpack.c",
        "src/shmif/arcan_shmif_a11y.c",
	"src/shmif/arcan_shmif_migrate.c",
	"src/shmif/arcan_shmif_mousestate.c",
	"src/shmif/arcan_shmif_filehelper.c",
	"src/shmif/arcan_shmif_avtransfer.c",
	"src/shmif/arcan_shmif_argparse.c",
	"src/shmif/arcan_shmif_preroll.c",
	"src/shmif/arcan_shmif_eventhandler.c",
	"src/shmif/arcan_shmif_privsep.c",
	"src/shmif/arcan_shmif_evhelper.c",
        "src/shmif/platform/synch.c",
        "src/engine/arcan_trace.c",
        "src/shmif/platform/exec.c",
	"src/shmif/platform/fdpassing.c",
	"src/shmif/platform/eventqueue.c",
	"src/shmif/platform/watchdog.c",
	"src/shmif/platform/migrate.c",
	"src/shmif/platform/net.c",
	"src/shmif/platform/connection.c",
    };
    for (shmif_sources) |source| {
        step.addCSourceFile(.{ .file = b.path(source) });
    }

    // TODO Add LWA_PLATFORM_STR logic
    step.addCSourceFile(.{ .file = b.path("src/shmif/stub/stub.c") });

    for (shmif_include_paths) |dir| {
        step.addIncludePath(b.path(dir));
    }

    if (opts.with_debugif) {
        step.addCSourceFile(.{ .file = b.path("src/shmif/arcan_shmif_debugif.c") });
        step.root_module.addCMacro("SHMIF_DEBUG_IF", "");
    }

    return step;
}

fn createArcanA12(b: *std.Build, opts: anytype) *std.Build.Step.Compile {
    const lib_opts = .{
        .name = "arcan_a12",
        .version = a12_version,
        .target = opts.target,
        .optimize = opts.optimize,
        .pic = opts.pic,
        .strip = opts.strip,
    };
    const step = if (opts.static)
        b.addStaticLibrary(lib_opts)
    else
        b.addSharedLibrary(lib_opts);

    step.linkLibC();
    step.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);
    addPlatformDefinitions(step, opts);

    if (opts.target.result.os.tag == .windows) {
        step.linkSystemLibrary("winmm");
    }

    if (opts.with_ffmpeg) {
        if (opts.use_system_ffmpeg) {
            step.linkSystemLibrary("ffmpeg");
        } else {
            const lazy_ffmpeg = b.lazyDependency("ffmpeg", .{
                .target = opts.target,
                .optimize = opts.optimize,
            });
            if (lazy_ffmpeg) |ffmpeg| step.linkLibrary(ffmpeg.artifact("ffmpeg"));
        }
        step.root_module.addCMacro("WANT_H264_DEC", "");
        step.root_module.addCMacro("WANT_H264_ENC", "");
    }

    const a12_sources: []const String = &.{
        "src/a12/a12.c",
        "src/a12/a12_decode.c",
        "src/a12/a12_encode.c",
        "src/shmif/arcan_shmif_evpack.c",
    };
    for (a12_sources) |source| {
        step.addCSourceFile(.{ .file = b.path(source) });
    }

    if (!opts.build_shmif) {
        step.addCSourceFile(.{
            .file = b.path("src/a12/platform/shmif-stub.c"),
        });
    }

    const target_os = opts.target.result.os.tag;
    const platform_sources: []const String = switch (target_os) {
        .windows => &.{
            "src/a12/platform/windows.c",
            "src/platform/windows/mem.c",
            "src/platform/windows/time.c",
            "src/platform/windows/random.c",
        },
        else => &.{
            "src/a12/platform/posix.c",
            "src/platform/posix/mem.c",
            "src/platform/posix/time.c",
            "src/platform/posix/random.c",
        },
    };
    for (platform_sources) |source| {
        step.addCSourceFile(.{ .file = b.path(source) });
    }

    const a12_external_sources: []const String = &.{
        "src/a12/external/blake3/blake3.c",
        "src/a12/external/blake3/blake3_dispatch.c",
        "src/a12/external/blake3/blake3_portable.c",
        "src/a12/external/x25519.c",

        "src/a12/external/zstd/common/debug.c",
        "src/a12/external/zstd/common/entropy_common.c",
        "src/a12/external/zstd/common/error_private.c",
        "src/a12/external/zstd/common/fse_decompress.c",
        "src/a12/external/zstd/common/pool.c",
        "src/a12/external/zstd/common/threading.c",
        "src/a12/external/zstd/common/xxhash.c",
        "src/a12/external/zstd/common/zstd_common.c",
        "src/a12/external/zstd/compress/fse_compress.c",
        "src/a12/external/zstd/compress/hist.c",
        "src/a12/external/zstd/compress/huf_compress.c",
        "src/a12/external/zstd/compress/zstd_compress.c",
        "src/a12/external/zstd/compress/zstd_compress_literals.c",
        "src/a12/external/zstd/compress/zstd_compress_sequences.c",
        "src/a12/external/zstd/compress/zstd_compress_superblock.c",
        "src/a12/external/zstd/compress/zstd_double_fast.c",
        "src/a12/external/zstd/compress/zstd_fast.c",
        "src/a12/external/zstd/compress/zstd_lazy.c",
        "src/a12/external/zstd/compress/zstd_ldm.c",
        "src/a12/external/zstd/compress/zstd_opt.c",
        "src/a12/external/zstd/compress/zstdmt_compress.c",
        "src/a12/external/zstd/decompress/huf_decompress.c",
        "src/a12/external/zstd/decompress/zstd_ddict.c",
        "src/a12/external/zstd/decompress/zstd_decompress.c",
        "src/a12/external/zstd/decompress/zstd_decompress_block.c",
    };
    for (a12_external_sources) |source| {
        step.addCSourceFile(.{ .file = b.path(source) });
    }

    for (a12_include_paths) |path| {
        step.addIncludePath(b.path(path));
    }

    const a12_headers: []const String = &.{
        "a12.h",
        "pack.h",
        "a12_decode.h",
        "a12_encode.h",
    };
    for (a12_headers) |header| {
        step.installHeader(
            b.path(b.pathJoin(&.{"src/a12", header})),
            header,
        );
    }

    const a12_definitions: []const [2]String = &.{
        .{ "BLAKE3_NO_AVX2", "" },
        .{ "BLAKE3_NO_AVX512", "" },
        .{ "BLAKE3_NO_SSE41", "" },
        .{ "ZSTD_MULTITHREAD", "" },
        .{ "ZSTD_DISABLE_ASM", "" },
    };
    for (a12_definitions) |definition| {
        step.root_module.addCMacro(definition[0], definition[1]);
    }

    return step;
}

fn createArcanTui(b: *std.Build, opts: anytype) *std.Build.Step.Compile {
    const lib_opts = .{
        .name = "arcan_tui",
        .version = shmif_version,
        .target = opts.target,
        .optimize = opts.optimize,
        .pic = opts.pic,
        .strip = opts.strip,
    };
    const step = if (opts.static)
        b.addStaticLibrary(lib_opts)
    else
        b.addSharedLibrary(lib_opts);

    step.linkLibC();
    step.root_module.addCMacro("NO_ARCAN_AGP", "");
    step.root_module.addCMacro("SHMIF_TTF", "");
    step.root_module.addCMacro("PLATFORM_HEADER", opts.platform_header);

    const shmif_tui_sources: []const String = &.{
        "src/shmif/tui/tui.c",
        "src/shmif/tui/core/clipboard.c",
        "src/shmif/tui/core/input.c",
        "src/shmif/tui/core/setup.c",
        "src/shmif/tui/core/screen.c",
        "src/shmif/tui/core/dispatch.c",
        "src/shmif/tui/raster/pixelfont.c",
        "src/shmif/tui/raster/raster.c",
        "src/shmif/tui/raster/fontmgmt.c",
        "src/shmif/tui/widgets/bufferwnd.c",
        "src/shmif/tui/widgets/listwnd.c",
        "src/shmif/tui/widgets/linewnd.c",
        "src/shmif/tui/widgets/readline.c",
        "src/shmif/tui/widgets/copywnd.c",
    };
    for (shmif_tui_sources) |source| {
        step.addCSourceFile(.{
            .file = b.path(source),
            .flags = &.{"-latomic"},
        });
    }

    // Only support TUI_RASTER_NO_TTF for now
    step.addCSourceFile(.{
        .file = b.path("src/shmif/tui/raster/ttfstub.c"),
        .flags = &.{"-latomic"},
    });

    const shmif_tui_headers: []const String = &.{
        "arcan_tui.h",
        "arcan_tuidefs.h",
        "arcan_tuisym.h",
        "arcan_tui_bufferwnd.h",
        "arcan_tui_listwnd.h",
        "arcan_tui_linewnd.h",
        "arcan_tui_readline.h",
    };
    for (shmif_tui_headers) |header| {
        step.installHeader(
            b.path(b.pathJoin(&.{"src/shmif/", header})),
            header,
        );
    }

    for (shmif_tui_include_paths) |path| {
        step.addIncludePath(b.path(path));
    }

    return step;
}

fn addShmifHeaders(b: *std.Build, lib: *std.Build.Step.Compile) void {
    const shmif_headers: []const String = &.{
        "arcan_shmif_control.h",
        "arcan_shmif_interop.h",
        "arcan_shmif_event.h",
        "arcan_shmif_server.h",
        "arcan_shmif_sub.h",
        "arcan_shmif_defs.h",
        "arcan_shmif.h",
    };
    for (shmif_headers) |header| {
        lib.installHeader(
            b.path(b.pathJoin(&.{"src/shmif", header})),
            header
        );
    }
}

fn addShmifPlatformSources(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    opts: anytype,
) void {
    const shmif_platform_sources: []const String = &.{
        "src/platform/posix/shmemop.c",
        "src/platform/posix/warning.c",
        "src/platform/posix/fdpassing.c",
        "src/platform/posix/random.c",
        "src/platform/posix/fdscan.c",
    };
    for (shmif_platform_sources) |source| {
        lib.addCSourceFile(.{
            .file = b.path(source),
            .flags = &.{"-latomic"},
        });
    }
    lib.addCSourceFile(.{
        .file = b.path("src/platform/posix/fdpassing.c"),
        .flags = &.{ "-w", "-DNONBLOCK_RECV" },
    });

    switch (opts.target.result.os.tag) {
        .linux, .freebsd, .openbsd, .dragonfly, .kfreebsd, .netbsd => {
            const shmif_platform_posix_sources: []const String = &.{
                "src/platform/posix/time.c",
                "src/platform/posix/sem.c",
            };
            for (shmif_platform_posix_sources) |source| {
                lib.addCSourceFile(.{
                    .file = b.path(source),
                    .flags = &.{"-latomic"},
                });
            }
        },
        .ios, .macos, .watchos, .tvos => {
            const shmif_platform_darwin_sources: []const String = &.{
                "src/platform/darwin/time.c",
                "src/platform/darwin/sem.c",
            };
            for (shmif_platform_darwin_sources) |source| {
                lib.addCSourceFile(.{
                    .file = b.path(source),
                    .flags = &.{"-latomic"},
                });
            }
        },
        else => {},
    }
}

fn addPlatformDefinitions(step: *std.Build.Step.Compile, opts: anytype) void {
    const linux_platform_definitions: []const [2]String = &.{
        .{ "__UNIX", "" },
        .{ "__LINUX", "" },
        .{ "POSIX_C_SOURCE", "" },
        .{ "_GNU_SOURCE", "" },
    };
    const darwin_platform_definitions: []const [2]String = &.{
        .{ "__UNIX", "" },
        .{ "POSIX_C_SOURCE", "" },
        .{ "__APPLE__", "" },
        .{ "ARCAN_SHMIF_OVERCOMMIT", "" },
        .{ "_WITH_DPRINTF", "" },
        .{ "_GNU_SOURCE", "" },
    };
    const windows_platform_definitions: []const [2]String = &.{
        .{ "__WINDOWS", "" },
    };

    const bsd_platform_definitions = [_][2]String{
        .{ "_WITH_GETLINE", "" },
        .{ "__UNIX", "" },
        .{ "__BSD", "" },
        .{ "LIBUSB_BSD", "" },
    };

    const platform_definitions = switch (opts.target.result.os.tag) {
        .linux => linux_platform_definitions,
        .ios, .macos, .watchos, .tvos => darwin_platform_definitions,
        .windows => windows_platform_definitions,
        .freebsd => &(bsd_platform_definitions ++ .{.{ "__FreeBSD__", "" }}),
        .dragonfly => &(bsd_platform_definitions ++ .{.{ "__DragonFly__", "" }}),
        .kfreebsd => &(bsd_platform_definitions ++ .{.{ "__kFreeBSD__", "" }}),
        .openbsd => &(bsd_platform_definitions ++ .{
            .{ "__OpenBSD__", "" },
            .{ "CLOCK_MONOTONIC_RAW", "CLOCK_MONOTONIC" },
        }),
        .netbsd => &(bsd_platform_definitions ++ .{
            .{ "__NetBSD__", "" },
            .{ "CLOCK_MONOTONIC_RAW", "CLOCK_MONOTONIC" },
        }),
        else => &(.{}),
    };

    for (platform_definitions) |def| {
        step.root_module.addCMacro(def[0], def[1]);
    }
}
