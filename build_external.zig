const std = @import("std");
const build_helpers = @import("build_helpers.zig");
const String = []const u8;

pub const ExternalDeps = struct {
    openal: ?*std.Build.Step.Compile = null,
    libdrm: ?*std.Build.Step.Compile = null,
    xcb: ?*std.Build.Step.Compile = null,
};

pub fn resolveAll(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    shmif_inc_paths: []const String,
) ExternalDeps {
    _ = b;
    _ = shmif_inc_paths;
    _ = target;
    _ = optimize;
    return .{
        // All three loaded at runtime via zig_dlopen (same pattern as XCB).
        // Static builds of these via the allyourcodebase ZON deps require
        // compiling C objects, which the no-LLVM self-hosted fork can't do
        // (aro doesn't support C codegen). Headers come from system
        // /usr/include via pkg-config cflags; symbol resolution happens at
        // runtime through the dl_* shim modules (src/platform/dl/).
        .openal = null,
        .libdrm = null,
        .xcb = null,
    };
}

/// If a static lib was built, link it + add its include path.
/// Otherwise fall back to pkg-config.
pub fn linkOrPkgConfig(
    step: *std.Build.Step.Compile,
    maybe_lib: ?*std.Build.Step.Compile,
    pkg_name: []const u8,
) void {
    if (maybe_lib) |lib| {
        step.linkLibrary(lib);
    } else {
        build_helpers.linkPkgConfig(step, pkg_name);
    }
}

/// Same as linkOrPkgConfig but only adds include paths (cflags), no link flags.
pub fn includeOrPkgConfigCflags(
    step: *std.Build.Step.Compile,
    maybe_lib: ?*std.Build.Step.Compile,
    pkg_name: []const u8,
) void {
    if (maybe_lib) |lib| {
        step.addIncludePath(lib.getEmittedIncludeTree());
    } else {
        build_helpers.addPkgConfigCflags(step, pkg_name);
    }
}

// ════════════════════════════════════════════════════════════════════
// OpenAL-Soft (letoram fork with arcan shmif backend)
// ════════════════════════════════════════════════════════════════════
fn createOpenAL(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    shmif_inc_paths: []const String,
) ?*std.Build.Step.Compile {
    const dep = b.lazyDependency("openal_soft", .{}) orelse return null;
    const root = dep.path(".");

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "openal",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.linkLibC();

    // Generate config.h
    const config_h = b.addWriteFiles();
    _ = config_h.add("config.h", generateOpenALConfig(b, target));
    lib.addIncludePath(config_h.getDirectory());

    // Include paths within the OpenAL source tree
    const openal_includes: []const String = &.{ "include", "OpenAL32/Include", "common", ".", "Alc" };
    for (openal_includes) |p| lib.addIncludePath(root.path(b, p));

    // arcan shmif includes (needed by backends/arcan.c)
    for (shmif_inc_paths) |p| lib.addIncludePath(b.path(p));

    // Generate version.h
    _ = config_h.add("version.h",
        \\#define ALSOFT_VERSION "1.19.1"
        \\#define ALSOFT_GIT_BRANCH "master"
        \\#define ALSOFT_GIT_COMMIT_HASH "letoram"
        \\
    );

    // Compiler flags
    lib.root_module.addCMacro("AL_LIBTYPE_STATIC", "");
    lib.root_module.addCMacro("AL_ALEXT_PROTOTYPES", "");
    lib.root_module.addCMacro("HAVE_ARCAN", "");
    lib.root_module.addCMacro("restrict", "__restrict");
    lib.root_module.addCMacro("_GNU_SOURCE", "");

    // Core Alc sources (14)
    const alc_sources: []const String = &.{
        "Alc/ALc.c",       "Alc/ALu.c",        "Alc/alcConfig.c",
        "Alc/alcRing.c",   "Alc/ambdec.c",     "Alc/bformatdec.c",
        "Alc/bs2b.c",      "Alc/bsinc.c",      "Alc/helpers.c",
        "Alc/hrtf.c",      "Alc/mixer.c",      "Alc/mixer_c.c",
        "Alc/panning.c",   "Alc/uhjfilter.c",
    };

    // Backends (4: base + null + loopback + arcan)
    const backend_sources: []const String = &.{
        "Alc/backends/base.c",     "Alc/backends/null.c",
        "Alc/backends/loopback.c", "Alc/backends/arcan.c",
    };

    // Effects (10)
    const effect_sources: []const String = &.{
        "Alc/effects/chorus.c",    "Alc/effects/compressor.c",
        "Alc/effects/dedicated.c", "Alc/effects/distortion.c",
        "Alc/effects/echo.c",      "Alc/effects/equalizer.c",
        "Alc/effects/flanger.c",   "Alc/effects/modulator.c",
        "Alc/effects/null.c",      "Alc/effects/reverb.c",
    };

    // OpenAL32 API (11)
    const api_sources: []const String = &.{
        "OpenAL32/alAuxEffectSlot.c", "OpenAL32/alBuffer.c",
        "OpenAL32/alEffect.c",        "OpenAL32/alError.c",
        "OpenAL32/alExtension.c",     "OpenAL32/alFilter.c",
        "OpenAL32/alListener.c",      "OpenAL32/alSource.c",
        "OpenAL32/alState.c",         "OpenAL32/alThunk.c",
        "OpenAL32/sample_cvt.c",
    };

    // Common (5)
    const common_sources: []const String = &.{
        "common/almalloc.c", "common/atomic.c",
        "common/rwlock.c",   "common/threads.c",
        "common/uintmap.c",
    };

    const all_groups = [_][]const String{
        alc_sources, backend_sources, effect_sources, api_sources, common_sources,
    };
    // OpenAL 1.19 uses forward references and implicit declarations
    const openal_cflags: []const String = &.{
        "-std=gnu11",
        "-Wno-implicit-function-declaration",
    };
    for (all_groups) |group| {
        for (group) |src| {
            lib.addCSourceFile(.{ .file = root.path(b, src), .flags = openal_cflags });
        }
    }

    // Install public headers so consumers get include path
    lib.installHeadersDirectory(root.path(b, "include/AL"), "AL", .{});

    return lib;
}

fn generateOpenALConfig(b: *std.Build, target: std.Build.ResolvedTarget) []const u8 {
    const gcc_cpuid: []const u8 = if (target.result.cpu.arch == .x86_64)
        "#define HAVE_GCC_GET_CPUID"
    else
        "#undef HAVE_GCC_GET_CPUID";

    return b.fmt(
        \\/* OpenAL config — generated by build_external.zig */
        \\
        \\/* API declaration export attribute */
        \\#define AL_API
        \\#define ALC_API
        \\
        \\/* Alignment */
        \\#define ALIGN(x) __attribute__((aligned(x)))
        \\#define ASSUME_ALIGNED(x, y) __builtin_assume_aligned((x), (y))
        \\
        \\/* Visibility */
        \\#define HIDDEN_DECL __attribute__((visibility("hidden")))
        \\
        \\/* Platform features */
        \\#define HAVE_POSIX_MEMALIGN
        \\#define HAVE_STAT
        \\#define HAVE_LRINTF
        \\#define HAVE_MODFF
        \\#define HAVE_STRTOF
        \\#define HAVE_STRNLEN
        \\#define SIZEOF_LONG 8
        \\#define HAVE_C11_THREAD_LOCAL
        \\{s}
        \\
        \\/* Threading */
        \\#define HAVE_PTHREAD_SETNAME_NP
        \\#define HAVE_PTHREAD_SETSCHEDPARAM
        \\#define HAVE_PTHREAD_MUTEXATTR_SETPROTOCOL
        \\#define HAVE_PTHREAD_MUTEX_TIMEDLOCK
        \\
        \\/* Language support */
        \\#define HAVE_C99_VLA
        \\#define HAVE_C99_BOOL
        \\#define HAVE_STDINT_H
        \\#define HAVE_STDBOOL_H
        \\#define HAVE_DLFCN_H
        \\#define HAVE_FENV_H
        \\#define HAVE_MALLOC_H
        \\#define HAVE_STRINGS_H
        \\#define HAVE_DIRENT_H
        \\#define RESTRICT __restrict
        \\#define HAVE_C_INLINE 1
        \\#define HAVE_GCC_DESTRUCTOR
        \\#define HAVE_GCC_FORMAT
        \\
        \\#define ALSOFT_INSTALL_DATADIR "/usr/local/share/openal"
        \\
        \\/* Backends — arcan + null + loopback */
        \\#define HAVE_ARCAN
        \\#undef HAVE_ALSA
        \\#undef HAVE_OSS
        \\#undef HAVE_SOLARIS
        \\#undef HAVE_SNDIO
        \\#undef HAVE_QSA
        \\#undef HAVE_MMDEVAPI
        \\#undef HAVE_DSOUND
        \\#undef HAVE_WINMM
        \\#undef HAVE_PORTAUDIO
        \\#undef HAVE_PULSEAUDIO
        \\#undef HAVE_JACK
        \\#undef HAVE_COREAUDIO
        \\#undef HAVE_OPENSL
        \\#undef HAVE_WAVE
        \\
        \\/* SIMD — disabled for portability */
        \\#undef HAVE_SSE
        \\#undef HAVE_SSE2
        \\#undef HAVE_SSE3
        \\#undef HAVE_SSE4_1
        \\#undef HAVE_NEON
        \\
        \\/* Version */
        \\#define ALSOFT_VERSION "1.19.1"
        \\
    , .{gcc_cpuid});
}

// ════════════════════════════════════════════════════════════════════
// libdrm
// ════════════════════════════════════════════════════════════════════
fn createLibdrm(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) ?*std.Build.Step.Compile {
    const dep = b.lazyDependency("libdrm", .{}) orelse return null;
    const root = dep.path(".");

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "drm",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.linkLibC();

    // Defines
    lib.root_module.addCMacro("HAVE_VISIBILITY", "1");
    lib.root_module.addCMacro("HAVE_LIBDRM_ATOMIC_PRIMITIVES", "1");
    lib.root_module.addCMacro("_GNU_SOURCE", "1");

    // Include paths
    lib.addIncludePath(root);
    lib.addIncludePath(root.path(b, "include/drm"));

    // Generate the fourcc table header at build time
    const fourcc_h = b.addWriteFiles();
    _ = fourcc_h.add("generated_static_table_fourcc.h", fourcc_table_content);
    lib.addIncludePath(fourcc_h.getDirectory());

    // glibc 2.28+ removed major/minor/makedev from sys/types.h.
    // On musl, they're inline functions in sys/sysmacros.h (no gnu_dev_* symbols).
    // Only alias to gnu_dev_* on glibc.
    if (target.result.abi != .musl and target.result.abi != .musleabi and target.result.abi != .musleabihf) {
        lib.root_module.addCMacro("major", "gnu_dev_major");
        lib.root_module.addCMacro("minor", "gnu_dev_minor");
        lib.root_module.addCMacro("makedev", "gnu_dev_makedev");
    }
    lib.root_module.addCMacro("HAVE_SYS_SYSMACROS_H", "1");
    lib.root_module.addCMacro("MAJOR_IN_SYSMACROS", "1");

    // Source files (4)
    const sources: []const String = &.{
        "xf86drm.c", "xf86drmHash.c", "xf86drmRandom.c", "xf86drmMode.c",
    };
    const drm_cflags: []const String = &.{
        "-Wno-implicit-function-declaration",
    };
    for (sources) |src| {
        lib.addCSourceFile(.{ .file = root.path(b, src), .flags = drm_cflags });
    }

    // Install public headers — xf86drm.h does #include <drm.h> (no prefix),
    // so DRM UAPI headers must be at the root of the include tree
    lib.installHeader(root.path(b, "xf86drm.h"), "xf86drm.h");
    lib.installHeader(root.path(b, "xf86drmMode.h"), "xf86drmMode.h");
    lib.installHeader(root.path(b, "libdrm_macros.h"), "libdrm_macros.h");
    lib.installHeader(root.path(b, "libdrm_lists.h"), "libdrm_lists.h");
    lib.installHeadersDirectory(root.path(b, "include/drm"), "", .{});
    // Also install under libdrm/ prefix for code that includes <libdrm/drm.h>
    lib.installHeadersDirectory(root.path(b, "include/drm"), "libdrm", .{});

    return lib;
}

// ════════════════════════════════════════════════════════════════════
// libxcb + libXau + xcb-util + xcb-util-wm (unified static library)
// ════════════════════════════════════════════════════════════════════
fn createXcb(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) ?*std.Build.Step.Compile {
    const xcb_dep = b.lazyDependency("libxcb", .{}) orelse return null;
    const xau_dep = b.lazyDependency("libXau", .{}) orelse return null;
    const util_dep = b.lazyDependency("xcb_util", .{}) orelse return null;
    const wm_dep = b.lazyDependency("xcb_util_wm", .{}) orelse return null;

    const xcb_root = xcb_dep.path(".");
    const xau_root = xau_dep.path(".");
    const util_root = util_dep.path(".");
    const wm_root = wm_dep.path(".");

    // Pre-generated protocol files live in src/external/xcb-generated/
    const gen_path = b.path("src/external/xcb-generated");

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "xcb",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.linkLibC();

    // config.h for libxcb
    const config_wf = b.addWriteFiles();
    _ = config_wf.add("config.h", generateXcbConfig());
    lib.addIncludePath(config_wf.getDirectory());

    // Include paths
    // libxcb core headers (xcb.h, xcbext.h, xcbint.h) from generated dir
    lib.addIncludePath(gen_path);
    // libxcb src dir (for xcb_windefs.h and other internal headers)
    lib.addIncludePath(xcb_root.path(b, "src"));
    // libXau headers
    lib.addIncludePath(xau_root.path(b, "include"));
    // xorgproto: xcb.h includes <X11/Xproto.h> — use system xorgproto
    lib.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });

    // Compiler flags
    lib.root_module.addCMacro("HAVE_CONFIG_H", "");
    lib.root_module.addCMacro("_GNU_SOURCE", "");

    const xcb_cflags: []const String = &.{
        "-Wno-implicit-function-declaration",
        "-Wno-sign-compare",
    };

    // libxcb core sources (8 files from upstream repo)
    const xcb_core_sources: []const String = &.{
        "src/xcb_auth.c",  "src/xcb_conn.c", "src/xcb_ext.c",
        "src/xcb_in.c",    "src/xcb_list.c", "src/xcb_out.c",
        "src/xcb_util.c",  "src/xcb_xid.c",
    };
    for (xcb_core_sources) |src| {
        lib.addCSourceFile(.{ .file = xcb_root.path(b, src), .flags = xcb_cflags });
    }

    // Generated protocol sources (from src/external/xcb-generated/)
    const xcb_proto_sources: []const String = &.{
        "xproto.c",    "xkb.c",       "composite.c", "xfixes.c",
        "bigreq.c",    "xc_misc.c",   "shm.c",       "ge.c",
        "damage.c",    "render.c",    "shape.c",     "sync.c",
        "dri2.c",      "dri3.c",      "present.c",   "randr.c",
        "xinput.c",
    };
    for (xcb_proto_sources) |src| {
        lib.addCSourceFile(.{ .file = gen_path.path(b, src), .flags = xcb_cflags });
    }

    // libXau sources (8 files)
    const xau_sources: []const String = &.{
        "AuDispose.c", "AuFileName.c", "AuGetAddr.c", "AuGetBest.c",
        "AuLock.c",    "AuRead.c",     "AuUnlock.c",  "AuWrite.c",
    };
    for (xau_sources) |src| {
        lib.addCSourceFile(.{ .file = xau_root.path(b, src), .flags = xcb_cflags });
    }

    // xcb-util sources (3 files)
    // xcb-util needs <xcb/xcb.h> — install path is xcb/ prefix
    lib.addIncludePath(util_root.path(b, "src"));
    const xcb_util_sources: []const String = &.{
        "src/atoms.c", "src/event.c", "src/xcb_aux.c",
    };
    for (xcb_util_sources) |src| {
        lib.addCSourceFile(.{ .file = util_root.path(b, src), .flags = xcb_cflags });
    }

    // xcb-util-wm/icccm source (1 file)
    lib.addIncludePath(wm_root.path(b, "icccm"));
    lib.addCSourceFile(.{ .file = wm_root.path(b, "icccm/icccm.c"), .flags = xcb_cflags });

    // xkbcommon-x11 sources (6 files from upstream xkbcommon)
    // The allyourcodebase xkbcommon builds xkbcommon-x11 with linkSystemLibrary("xcb")
    // which embeds the system .so. Instead, compile x11 sources here against our static xcb.
    // These files need xkbcommon's config.h defines — provide them as cflags.
    if (b.lazyDependency("xkbcommon_src", .{})) |xkb_src_dep| {
        const xkb_root = xkb_src_dep.path(".");
        lib.addIncludePath(xkb_root.path(b, "include"));
        lib.addIncludePath(xkb_root.path(b, "src"));
        const xkb_x11_cflags: []const String = &.{
            "-Wno-implicit-function-declaration",
            "-Wno-sign-compare",
            "-DHAVE_STRNDUP=1",
            "-DHAVE_ASPRINTF=1",
            "-DHAVE_UNISTD_H=1",
            "-DHAVE_MMAP=1",
            "-DHAVE_MKOSTEMP=1",
            "-DHAVE_POSIX_FALLOCATE=1",
            "-DHAVE_EACCESS=1",
            "-DHAVE___BUILTIN_EXPECT=1",
            "-D_GNU_SOURCE=1",
            "-DDEFAULT_XKB_RULES=\"evdev\"",
            "-DDEFAULT_XKB_MODEL=\"pc105\"",
            "-DDEFAULT_XKB_LAYOUT=\"us\"",
            "-DDEFAULT_XKB_VARIANT=NULL",
            "-DDEFAULT_XKB_OPTIONS=NULL",
            "-DDFLT_XKB_CONFIG_ROOT=\"/usr/share/X11/xkb\"",
            "-DDFLT_XKB_CONFIG_EXTRA_PATH=\"/etc/xkb\"",
            "-DXLOCALEDIR=\"/usr/share/X11/locale\"",
        };
        const xkb_x11_sources: []const String = &.{
            "src/x11/keymap.c", "src/x11/state.c", "src/x11/util.c",
            "src/context-priv.c", "src/keymap-priv.c", "src/atom.c",
        };
        for (xkb_x11_sources) |src| {
            lib.addCSourceFile(.{ .file = xkb_root.path(b, src), .flags = xkb_x11_cflags });
        }
        lib.installHeader(xkb_root.path(b, "include/xkbcommon/xkbcommon-x11.h"), "xkbcommon/xkbcommon-x11.h");
    }

    // Install public headers
    // xcb/ prefix: core headers + generated protocol headers
    lib.installHeader(gen_path.path(b, "xcb.h"), "xcb/xcb.h");
    lib.installHeader(gen_path.path(b, "xcbext.h"), "xcb/xcbext.h");
    // Generated protocol headers
    const proto_headers: []const String = &.{
        "xproto.h",    "xkb.h",       "composite.h", "xfixes.h",
        "bigreq.h",    "xc_misc.h",   "shm.h",       "ge.h",
        "damage.h",    "render.h",    "shape.h",     "sync.h",
        "dri2.h",      "dri3.h",      "present.h",   "randr.h",
        "xinput.h",
    };
    for (proto_headers) |hdr| {
        lib.installHeader(gen_path.path(b, hdr), b.fmt("xcb/{s}", .{hdr}));
    }
    // xcb-util headers
    lib.installHeader(util_root.path(b, "src/xcb_atom.h"), "xcb/xcb_atom.h");
    lib.installHeader(util_root.path(b, "src/xcb_aux.h"), "xcb/xcb_aux.h");
    lib.installHeader(util_root.path(b, "src/xcb_event.h"), "xcb/xcb_event.h");
    lib.installHeader(util_root.path(b, "src/xcb_util.h"), "xcb/xcb_util.h");
    // xcb-util-wm/icccm header
    lib.installHeader(wm_root.path(b, "icccm/xcb_icccm.h"), "xcb/xcb_icccm.h");
    // libXau header
    lib.installHeader(xau_root.path(b, "include/X11/Xauth.h"), "X11/Xauth.h");

    return lib;
}

fn generateXcbConfig() []const u8 {
    return
        \\/* libxcb config — generated by build_external.zig */
        \\#define HAVE_ABSTRACT_SOCKETS 1
        \\#define HAVE_SENDMSG 1
        \\#define USE_POLL 1
        \\#define HAVE_UNISTD_H 1
        \\#define XCB_QUEUE_BUFFER_SIZE 16384
        \\/* No XDMCP auth */
        \\/* #undef HASXDMAUTH */
        \\/* #undef HAVE_SOCKADDR_SUN_LEN */
        \\/* #undef HAVE_TSOL_LABEL_H */
        \\
    ;
}

const fourcc_table_content =
    \\/* AUTOMATICALLY GENERATED by gen_table_fourcc.py. You should modify
    \\   that script instead of adding here entries manually! */
    \\static const struct drmFormatModifierInfo drm_format_modifier_table[] = {
    \\    { DRM_MODIFIER_INVALID(NONE, INVALID) },
    \\    { DRM_MODIFIER_LINEAR(NONE, LINEAR) },
    \\    { DRM_MODIFIER_INTEL(X_TILED, X_TILED) },
    \\    { DRM_MODIFIER_INTEL(Y_TILED, Y_TILED) },
    \\    { DRM_MODIFIER_INTEL(Yf_TILED, Yf_TILED) },
    \\    { DRM_MODIFIER_INTEL(Y_TILED_CCS, Y_TILED_CCS) },
    \\    { DRM_MODIFIER_INTEL(Yf_TILED_CCS, Yf_TILED_CCS) },
    \\    { DRM_MODIFIER_INTEL(Y_TILED_GEN12_RC_CCS, Y_TILED_GEN12_RC_CCS) },
    \\    { DRM_MODIFIER_INTEL(Y_TILED_GEN12_MC_CCS, Y_TILED_GEN12_MC_CCS) },
    \\    { DRM_MODIFIER_INTEL(Y_TILED_GEN12_RC_CCS_CC, Y_TILED_GEN12_RC_CCS_CC) },
    \\    { DRM_MODIFIER_INTEL(4_TILED, 4_TILED) },
    \\    { DRM_MODIFIER_INTEL(4_TILED_DG2_RC_CCS, 4_TILED_DG2_RC_CCS) },
    \\    { DRM_MODIFIER_INTEL(4_TILED_DG2_MC_CCS, 4_TILED_DG2_MC_CCS) },
    \\    { DRM_MODIFIER_INTEL(4_TILED_DG2_RC_CCS_CC, 4_TILED_DG2_RC_CCS_CC) },
    \\    { DRM_MODIFIER_INTEL(4_TILED_MTL_RC_CCS, 4_TILED_MTL_RC_CCS) },
    \\    { DRM_MODIFIER_INTEL(4_TILED_MTL_MC_CCS, 4_TILED_MTL_MC_CCS) },
    \\    { DRM_MODIFIER_INTEL(4_TILED_MTL_RC_CCS_CC, 4_TILED_MTL_RC_CCS_CC) },
    \\    { DRM_MODIFIER(SAMSUNG, 64_32_TILE, 64_32_TILE) },
    \\    { DRM_MODIFIER(SAMSUNG, 16_16_TILE, 16_16_TILE) },
    \\    { DRM_MODIFIER(QCOM, COMPRESSED, COMPRESSED) },
    \\    { DRM_MODIFIER(QCOM, TILED3, TILED3) },
    \\    { DRM_MODIFIER(QCOM, TILED2, TILED2) },
    \\    { DRM_MODIFIER(VIVANTE, TILED, TILED) },
    \\    { DRM_MODIFIER(VIVANTE, SUPER_TILED, SUPER_TILED) },
    \\    { DRM_MODIFIER(VIVANTE, SPLIT_TILED, SPLIT_TILED) },
    \\    { DRM_MODIFIER(VIVANTE, SPLIT_SUPER_TILED, SPLIT_SUPER_TILED) },
    \\    { DRM_MODIFIER(NVIDIA, TEGRA_TILED, TEGRA_TILED) },
    \\    { DRM_MODIFIER(NVIDIA, 16BX2_BLOCK_ONE_GOB, 16BX2_BLOCK_ONE_GOB) },
    \\    { DRM_MODIFIER(NVIDIA, 16BX2_BLOCK_TWO_GOB, 16BX2_BLOCK_TWO_GOB) },
    \\    { DRM_MODIFIER(NVIDIA, 16BX2_BLOCK_FOUR_GOB, 16BX2_BLOCK_FOUR_GOB) },
    \\    { DRM_MODIFIER(NVIDIA, 16BX2_BLOCK_EIGHT_GOB, 16BX2_BLOCK_EIGHT_GOB) },
    \\    { DRM_MODIFIER(NVIDIA, 16BX2_BLOCK_SIXTEEN_GOB, 16BX2_BLOCK_SIXTEEN_GOB) },
    \\    { DRM_MODIFIER(NVIDIA, 16BX2_BLOCK_THIRTYTWO_GOB, 16BX2_BLOCK_THIRTYTWO_GOB) },
    \\    { DRM_MODIFIER(BROADCOM, VC4_T_TILED, VC4_T_TILED) },
    \\    { DRM_MODIFIER(BROADCOM, SAND32, SAND32) },
    \\    { DRM_MODIFIER(BROADCOM, SAND64, SAND64) },
    \\    { DRM_MODIFIER(BROADCOM, SAND128, SAND128) },
    \\    { DRM_MODIFIER(BROADCOM, SAND256, SAND256) },
    \\    { DRM_MODIFIER(BROADCOM, UIF, UIF) },
    \\    { DRM_MODIFIER(ARM, 16X16_BLOCK_U_INTERLEAVED, 16X16_BLOCK_U_INTERLEAVED) },
    \\    { DRM_MODIFIER(ALLWINNER, TILED, TILED) },
    \\};
    \\static const struct drmFormatModifierVendorInfo drm_format_modifier_vendor_table[] = {
    \\    { DRM_FORMAT_MOD_VENDOR_NONE, "NONE" },
    \\    { DRM_FORMAT_MOD_VENDOR_INTEL, "INTEL" },
    \\    { DRM_FORMAT_MOD_VENDOR_AMD, "AMD" },
    \\    { DRM_FORMAT_MOD_VENDOR_NVIDIA, "NVIDIA" },
    \\    { DRM_FORMAT_MOD_VENDOR_SAMSUNG, "SAMSUNG" },
    \\    { DRM_FORMAT_MOD_VENDOR_QCOM, "QCOM" },
    \\    { DRM_FORMAT_MOD_VENDOR_VIVANTE, "VIVANTE" },
    \\    { DRM_FORMAT_MOD_VENDOR_BROADCOM, "BROADCOM" },
    \\    { DRM_FORMAT_MOD_VENDOR_ARM, "ARM" },
    \\    { DRM_FORMAT_MOD_VENDOR_ALLWINNER, "ALLWINNER" },
    \\    { DRM_FORMAT_MOD_VENDOR_AMLOGIC, "AMLOGIC" },
    \\};
    \\
;
