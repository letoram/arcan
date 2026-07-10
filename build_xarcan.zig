const std = @import("std");
const h = @import("build_helpers.zig");
const String = h.String;

pub fn createXarcan(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    arcan_shmif: *std.Build.Step.Compile,
) ?*std.Build.Step.Compile {
    const xa_dep = b.lazyDependency("xarcan", .{}) orelse return null;
    const root = xa_dep.path("");

    const exe = b.addExecutable(.{ .name = "Xarcan", .root_module = b.createModule(.{
        .target = target, .optimize = optimize, .link_libc = true,
    }) });

    // dix-config.h generation
    const config = b.addWriteFiles();
    _ = config.add("dix-config.h", genDixConfig());
    _ = config.add("version-config.h", genVersionConfig());
    _ = config.add("xkb-config.h", genXkbConfig());
    _ = config.add("xwayland-config.h", genXwaylandConfig());

    // include paths
    const xserver_inc_paths: []const String = &.{
        ".", "Xext", "Xi", "composite", "damageext", "exa", "fb", "glamor",
        "mi", "miext/damage", "miext/shadow", "miext/sync", "dbe", "dix",
        "dri3", "include", "present", "randr", "render", "xfixes",
        "glx", "hw/kdrive/src", "hw/kdrive/arcan", "os",
    };
    for (xserver_inc_paths) |p| exe.addIncludePath(root.path(b, p));
    exe.addIncludePath(config.getDirectory());

    // pkg-config system deps
    const pkgs: []const String = &.{
        "pixman-1", "xproto", "randrproto", "renderproto", "xextproto",
        "inputproto", "kbproto", "fontsproto", "fixesproto", "damageproto",
        "xcmiscproto", "bigreqsproto", "videoproto", "compositeproto",
        "recordproto", "scrnsaverproto", "resourceproto", "dri2proto",
        "dri3proto", "xineramaproto", "xf86vidmodeproto", "presentproto",
        "xkbfile", "xfont2", "xtrans", "xau",
        "epoxy", "gbm", "libdrm", "gl", "glproto", "dri",
        "xcb", "xcb-icccm", "xcb-xfixes", "xcb-util", "xcb-shm",
        "xshmfence",
    };
    for (pkgs) |pkg| h.linkPkgConfig(exe, pkg);

    // link our arcan shmif libs
    exe.linkLibrary(arcan_shmif);
    h.linkPkgConfig(exe, "egl");

    // system libs
    for ([_]String{ "m", "dl", "pthread", "rt", "nettle" }) |lib|
        exe.root_module.linkSystemLibrary(lib, .{});

    // common C flags
    const common_flags: []const String = &.{
        "-DHAVE_DIX_CONFIG_H",
        "-fno-strict-aliasing",
        "-fvisibility=hidden",
        "-Wno-unused-parameter",
        "-Wno-sign-compare",
        "-Wno-missing-field-initializers",
        "-Wno-unused-function",
        "-Wno-pointer-arith",
        "-Wno-cast-qual",
        "-Wno-redundant-decls",
        "-Wno-missing-prototypes",
        "-Wno-old-style-definition",
        "-Wno-nested-externs",
        "-Wno-implicit-fallthrough",
        "-Wno-shadow",
        "-Wno-bad-function-cast",
        "-Wno-strict-prototypes",
        "-Wno-missing-declarations",
        "-Wno-typedef-redefinition",
    };

    const glx_flags = common_flags ++ &[_]String{"-D__GLX_ALIGN64"};

    // dix (36 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "dix/atom.c", "dix/colormap.c", "dix/color.c", "dix/cursor.c",
        "dix/devices.c", "dix/dispatch.c", "dix/dixfonts.c", "dix/main.c",
        "dix/dixutils.c", "dix/enterleave.c", "dix/events.c", "dix/eventconvert.c",
        "dix/extension.c", "dix/gc.c", "dix/gestures.c", "dix/getevents.c",
        "dix/globals.c", "dix/glyphcurs.c", "dix/grabs.c", "dix/initatoms.c",
        "dix/inpututils.c", "dix/pixmap.c", "dix/privates.c", "dix/property.c",
        "dix/ptrveloc.c", "dix/region.c", "dix/registry.c", "dix/resource.c",
        "dix/selection.c", "dix/swaprep.c", "dix/swapreq.c", "dix/tables.c",
        "dix/touch.c", "dix/window.c",
    } });
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{"dix/stubmain.c"} });

    // os (21+ files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "os/WaitFor.c", "os/access.c", "os/alloc.c", "os/auth.c",
        "os/backtrace.c", "os/client.c", "os/connection.c", "os/fmt.c",
        "os/inputthread.c", "os/io.c", "os/mitauth.c", "os/osinit.c",
        "os/ospoll.c", "os/serverlock.c", "os/string.c", "os/utils.c",
        "os/xdmauth.c", "os/xsha1.c", "os/xstrans.c", "os/xprintf.c",
        "os/log.c", "os/busfault.c", "os/timingsafe_memcmp.c",
    } });

    // mi (28 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "mi/miarc.c", "mi/mibitblt.c", "mi/micmap.c", "mi/micopy.c",
        "mi/midash.c", "mi/midispcur.c", "mi/mieq.c", "mi/miexpose.c",
        "mi/mifillarc.c", "mi/migc.c", "mi/miglblt.c", "mi/mioverlay.c",
        "mi/mipointer.c", "mi/mipoly.c", "mi/mipolypnt.c", "mi/mipolyrect.c",
        "mi/mipolyseg.c", "mi/mipolytext.c", "mi/mipushpxl.c", "mi/miscrinit.c",
        "mi/misprite.c", "mi/mivaltree.c", "mi/miwideline.c", "mi/miwindow.c",
        "mi/mizerarc.c", "mi/mizerclip.c", "mi/mizerline.c",
    } });

    // fb (30 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "fb/fballpriv.c", "fb/fbarc.c", "fb/fbbits.c", "fb/fbblt.c",
        "fb/fbbltone.c", "fb/fbcmap_mi.c", "fb/fbcopy.c", "fb/fbfill.c",
        "fb/fbfillrect.c", "fb/fbfillsp.c", "fb/fbgc.c", "fb/fbgetsp.c",
        "fb/fbglyph.c", "fb/fbimage.c", "fb/fbline.c", "fb/fboverlay.c",
        "fb/fbpict.c", "fb/fbpixmap.c", "fb/fbpoint.c", "fb/fbpush.c",
        "fb/fbscreen.c", "fb/fbseg.c", "fb/fbsetsp.c", "fb/fbsolid.c",
        "fb/fbtile.c", "fb/fbtrap.c", "fb/fbutil.c", "fb/fbwindow.c",
    } });

    // composite (5 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "composite/compalloc.c", "composite/compext.c", "composite/compinit.c",
        "composite/compoverlay.c", "composite/compwindow.c",
    } });

    // damageext (1 file)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{"damageext/damageext.c"} });

    // dbe (2 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{ "dbe/dbe.c", "dbe/midbe.c" } });

    // randr (16 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "randr/randr.c", "randr/rrcrtc.c", "randr/rrdispatch.c", "randr/rrinfo.c",
        "randr/rrlease.c", "randr/rrmode.c", "randr/rrmonitor.c", "randr/rroutput.c",
        "randr/rrpointer.c", "randr/rrproperty.c", "randr/rrprovider.c",
        "randr/rrproviderproperty.c", "randr/rrscreen.c", "randr/rrsdispatch.c",
        "randr/rrtransform.c", "randr/rrxinerama.c",
    } });

    // render (11 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "render/animcur.c", "render/filter.c", "render/glyph.c", "render/matrix.c",
        "render/miindex.c", "render/mipict.c", "render/mirect.c", "render/mitrap.c",
        "render/mitri.c", "render/picture.c", "render/render.c",
    } });

    // present (10 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "present/present.c", "present/present_event.c", "present/present_execute.c",
        "present/present_fake.c", "present/present_fence.c", "present/present_notify.c",
        "present/present_request.c", "present/present_scmd.c", "present/present_screen.c",
        "present/present_vblank.c",
    } });

    // Xext (base + conditional)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "Xext/bigreq.c", "Xext/geext.c", "Xext/shape.c", "Xext/sleepuntil.c",
        "Xext/sync.c", "Xext/xcmisc.c", "Xext/xtest.c", "Xext/vidmode.c",
        "Xext/dpms.c", "Xext/shm.c", "Xext/hashtable.c", "Xext/xres.c",
        "Xext/saver.c", "Xext/xace.c",
        "Xext/panoramiX.c", "Xext/panoramiXprocs.c", "Xext/panoramiXSwap.c",
        "Xext/xvmain.c", "Xext/xvdisp.c", "Xext/xvmc.c",
    } });

    // xfixes (6 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "xfixes/cursor.c", "xfixes/disconnect.c", "xfixes/region.c",
        "xfixes/saveset.c", "xfixes/select.c", "xfixes/xfixes.c",
    } });

    // Xi (53 files + stubs)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "Xi/allowev.c", "Xi/chgdctl.c", "Xi/chgfctl.c", "Xi/chgkbd.c",
        "Xi/chgkmap.c", "Xi/chgprop.c", "Xi/chgptr.c", "Xi/closedev.c",
        "Xi/devbell.c", "Xi/exevents.c", "Xi/extinit.c", "Xi/getbmap.c",
        "Xi/getdctl.c", "Xi/getfctl.c", "Xi/getfocus.c", "Xi/getkmap.c",
        "Xi/getmmap.c", "Xi/getprop.c", "Xi/getselev.c", "Xi/getvers.c",
        "Xi/grabdev.c", "Xi/grabdevb.c", "Xi/grabdevk.c", "Xi/gtmotion.c",
        "Xi/listdev.c", "Xi/opendev.c", "Xi/queryst.c", "Xi/selectev.c",
        "Xi/sendexev.c", "Xi/setbmap.c", "Xi/setdval.c", "Xi/setfocus.c",
        "Xi/setmmap.c", "Xi/setmode.c", "Xi/ungrdev.c", "Xi/ungrdevb.c",
        "Xi/ungrdevk.c", "Xi/xiallowev.c", "Xi/xibarriers.c",
        "Xi/xichangecursor.c", "Xi/xichangehierarchy.c", "Xi/xigetclientpointer.c",
        "Xi/xigrabdev.c", "Xi/xipassivegrab.c", "Xi/xiproperty.c",
        "Xi/xiquerydevice.c", "Xi/xiquerypointer.c", "Xi/xiqueryversion.c",
        "Xi/xiselectev.c", "Xi/xisetclientpointer.c", "Xi/xisetdevfocus.c",
        "Xi/xiwarppointer.c",
    } });

    // xkb (23 files + stubs)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "xkb/ddxBeep.c", "xkb/ddxCtrls.c", "xkb/ddxLEDs.c", "xkb/ddxLoad.c",
        "xkb/maprules.c", "xkb/xkmread.c", "xkb/xkbtext.c", "xkb/xkbfmisc.c",
        "xkb/xkbout.c", "xkb/xkb.c", "xkb/xkbUtils.c", "xkb/xkbEvents.c",
        "xkb/xkbAccessX.c", "xkb/xkbSwap.c", "xkb/xkbLEDs.c", "xkb/xkbInit.c",
        "xkb/xkbActions.c", "xkb/xkbPrKeyEv.c",
        "xkb/XKBMisc.c", "xkb/XKBAlloc.c", "xkb/XKBGAlloc.c", "xkb/XKBMAlloc.c",
        "xkb/ddxKillSrv.c", "xkb/ddxPrivate.c", "xkb/ddxVT.c",
    } });

    // record (2 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{ "record/record.c", "record/set.c" } });

    // miext/damage (1 file)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{"miext/damage/damage.c"} });

    // miext/shadow (25 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "miext/shadow/shadow.c", "miext/shadow/sh3224.c",
        "miext/shadow/shafb4.c", "miext/shadow/shafb8.c",
        "miext/shadow/shiplan2p4.c", "miext/shadow/shiplan2p8.c",
        "miext/shadow/shpacked.c", "miext/shadow/shplanar8.c",
        "miext/shadow/shplanar.c", "miext/shadow/shrot16pack.c",
        "miext/shadow/shrot16pack_180.c", "miext/shadow/shrot16pack_270.c",
        "miext/shadow/shrot16pack_270YX.c", "miext/shadow/shrot16pack_90.c",
        "miext/shadow/shrot16pack_90YX.c", "miext/shadow/shrot32pack.c",
        "miext/shadow/shrot32pack_180.c", "miext/shadow/shrot32pack_270.c",
        "miext/shadow/shrot32pack_90.c", "miext/shadow/shrot8pack.c",
        "miext/shadow/shrot8pack_180.c", "miext/shadow/shrot8pack_270.c",
        "miext/shadow/shrot8pack_90.c", "miext/shadow/shrotate.c",
    } });

    // miext/sync (3 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "miext/sync/misync.c", "miext/sync/misyncfd.c", "miext/sync/misyncshm.c",
    } });

    // glamor (34 files + conditional)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "glamor/glamor.c", "glamor/glamor_copy.c", "glamor/glamor_core.c",
        "glamor/glamor_dash.c", "glamor/glamor_font.c",
        "glamor/glamor_composite_glyphs.c", "glamor/glamor_image.c",
        "glamor/glamor_lines.c", "glamor/glamor_segs.c", "glamor/glamor_render.c",
        "glamor/glamor_gradient.c", "glamor/glamor_prepare.c",
        "glamor/glamor_program.c", "glamor/glamor_rects.c", "glamor/glamor_spans.c",
        "glamor/glamor_text.c", "glamor/glamor_transfer.c",
        "glamor/glamor_transform.c", "glamor/glamor_trapezoid.c",
        "glamor/glamor_triangles.c", "glamor/glamor_addtraps.c",
        "glamor/glamor_glyphblt.c", "glamor/glamor_points.c",
        "glamor/glamor_pixmap.c", "glamor/glamor_largepixmap.c",
        "glamor/glamor_picture.c", "glamor/glamor_vbo.c",
        "glamor/glamor_window.c", "glamor/glamor_fbo.c",
        "glamor/glamor_compositerects.c", "glamor/glamor_utils.c",
        "glamor/glamor_sync.c",
        "glamor/glamor_glx_provider.c", "glamor/glamor_xv.c",
    } });

    // glx (31 files + glxvnd 4 files + dri2)
    exe.addCSourceFiles(.{ .root = root, .flags = glx_flags, .files = &.{
        "glx/indirect_dispatch.c", "glx/indirect_dispatch_swap.c",
        "glx/indirect_reqsize.c", "glx/indirect_size_get.c",
        "glx/indirect_table.c", "glx/clientinfo.c", "glx/createcontext.c",
        "glx/extension_string.c", "glx/indirect_util.c", "glx/indirect_program.c",
        "glx/indirect_texture_compression.c", "glx/glxcmds.c",
        "glx/glxcmdsswap.c", "glx/glxext.c", "glx/glxdriswrast.c",
        "glx/glxdricommon.c", "glx/glxscreens.c", "glx/render2.c",
        "glx/render2swap.c", "glx/renderpix.c", "glx/renderpixswap.c",
        "glx/rensize.c", "glx/single2.c", "glx/single2swap.c",
        "glx/singlepix.c", "glx/singlepixswap.c", "glx/singlesize.c",
        "glx/swap_interval.c", "glx/xfont.c",
        "glx/vndcmds.c", "glx/vndext.c", "glx/vndservermapping.c", "glx/vndservervendor.c",
    } });

    // dri3 (3 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "dri3/dri3.c", "dri3/dri3_request.c", "dri3/dri3_screen.c",
    } });

    // config (1 file)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{"config/config.c"} });

    // kdrive (6 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "hw/kdrive/src/kcmap.c", "hw/kdrive/src/kdrive.c",
        "hw/kdrive/src/kinfo.c", "hw/kdrive/src/kinput.c",
        "hw/kdrive/src/kshadow.c", "hw/kdrive/src/kxv.c",
        "mi/miinitext.c",
    } });

    // arcan backend (7 files)
    exe.addCSourceFiles(.{ .root = root, .flags = common_flags, .files = &.{
        "hw/kdrive/arcan/core.c", "hw/kdrive/arcan/init.c",
        "hw/kdrive/arcan/cvt.c", "hw/kdrive/arcan/proxywnd.c",
        "hw/kdrive/arcan/clipboard.c", "hw/kdrive/arcan/cursor.c",
        "hw/kdrive/arcan/present.c",
    } });

    for ([_]String{ "src/shmif", "src/engine" }) |p| exe.addIncludePath(b.path(p));

    // GL AGP layer removed — Xarcan needs rework to use Vulkan AGP or vendor its own GL

    return exe;
}

fn genDixConfig() []const u8 {
    return
        \\/* Generated by build.zig for Xarcan */
        \\#ifndef _DIX_CONFIG_H_
        \\#define _DIX_CONFIG_H_
        \\
        \\#define _GNU_SOURCE 1
        \\
        \\/* Server version: 21.1.99.1 → 1*10000000 + 21*100000 + 1*1000 + 99*1 = 12101099 */
        \\#define XORG_VERSION_CURRENT 12101099
        \\
        \\/* Byte order */
        \\#ifdef __BIG_ENDIAN__
        \\#define X_BYTE_ORDER X_BIG_ENDIAN
        \\#else
        \\#define X_BYTE_ORDER X_LITTLE_ENDIAN
        \\#endif
        \\
        \\/* 64-bit server */
        \\#if __SIZEOF_LONG__ == 8
        \\#define _XSERVER64 1
        \\#endif
        \\
        \\/* Clock */
        \\#define MONOTONIC_CLOCK 1
        \\
        \\/* Input thread */
        \\#define INPUTTHREAD 1
        \\#define HAVE_PTHREAD_SETNAME_NP_WITH_TID 1
        \\
        \\/* Don't let X dependencies typedef 'pointer' */
        \\#define _XTYPEDEF_POINTER 1
        \\#define _XITYPEDEF_POINTER 1
        \\
        \\/* Networking */
        \\#define TCPCONN 1
        \\#define UNIXCONN 1
        \\#define IPv6 1
        \\#define XTRANS_SEND_FDS 1
        \\#define LISTEN_TCP 0
        \\#define LISTEN_UNIX 1
        \\#define LISTEN_LOCAL 1
        \\
        \\/* Always-enabled extensions */
        \\#define BIGREQS 1
        \\#define COMPOSITE 1
        \\#define DAMAGE 1
        \\#define DBE 1
        \\#define PRESENT 1
        \\#define RANDR 1
        \\#define RENDER 1
        \\#define SHAPE 1
        \\#define XFIXES 1
        \\#define XINPUT 1
        \\#define XRECORD 1
        \\#define XSYNC 1
        \\#define XTEST 1
        \\#define XCMISC 1
        \\#define XF86VIDMODE 1
        \\
        \\/* Conditional extensions (enabled for xarcan) */
        \\#define DPMSExtension 1
        \\#define MITSHM 1
        \\#define PANORAMIX 1
        \\#define XINERAMA 1
        \\#define RES 1
        \\#define SCREENSAVER 1
        \\#define XACE 1
        \\#define XV 1
        \\#define XvExtension 1
        \\#define XvMCExtension 1
        \\#define X_REGISTRY_RESOURCE 1
        \\
        \\/* GLX / Glamor / DRI */
        \\#define GLXEXT 1
        \\#define GLAMOR 1
        \\#define GLAMOR_HAS_GBM 1
        \\#define GLAMOR_HAS_GBM_LINEAR 1
        \\#define GBM_BO_WITH_MODIFIERS 1
        \\#define GBM_BO_FD_FOR_PLANE 1
        \\#define GBM_BO_WITH_MODIFIERS2 1
        \\#define GLAMOR_HAS_EGL_QUERY_DMABUF 1
        \\#define GLAMOR_HAS_EGL_QUERY_DRIVER 1
        \\#define WITH_LIBDRM 1
        \\#define HAVE_XSHMFENCE 1
        \\#define DRI2 1
        \\#define DRI3 1
        \\
        \\/* SHA1 via nettle */
        \\#define HAVE_SHA1_IN_LIBNETTLE 1
        \\
        \\/* Lock server */
        \\#define LOCK_SERVER 1
        \\
        \\/* Paths */
        \\#define SERVER_MISC_CONFIG_PATH "/usr/local/lib/xorg"
        \\#define PROJECTROOT "/usr/local"
        \\#define SYSCONFDIR "/usr/local/etc"
        \\#define SUID_WRAPPER_DIR "/usr/local/libexec"
        \\#define COMPILEDDEFAULTFONTPATH "/usr/local/share/fonts/X11/misc,/usr/local/share/fonts/X11/TTF,/usr/local/share/fonts/X11/OTF,/usr/local/share/fonts/X11/Type1,/usr/local/share/fonts/X11/100dpi,/usr/local/share/fonts/X11/75dpi"
        \\#define DRI_DRIVER_PATH "/usr/lib64/dri"
        \\
        \\/* Vendor */
        \\#define XVENDORNAME "The X.Org Foundation"
        \\#define XVENDORNAMESHORT "X.Org"
        \\#define __VENDORDWEBSUPPORT__ "http://wiki.x.org"
        \\#define BUILDERADDR "xorg@lists.freedesktop.org"
        \\#define BUILDERSTRING ""
        \\
        \\/* XKB defaults */
        \\#define XKB_DFLT_RULES "evdev"
        \\
        \\/* System headers */
        \\#define HAVE_DLFCN_H 1
        \\#define HAVE_EXECINFO_H 1
        \\#define HAVE_FNMATCH_H 1
        \\#define HAVE_STRINGS_H 1
        \\#define HAVE_SYS_UN_H 1
        \\#define HAVE_SYS_UTSNAME_H 1
        \\#define HAVE_SYS_SYSMACROS_H 1
        \\
        \\/* System functions */
        \\#define HAVE_BACKTRACE 1
        \\#define HAVE_CBRT 1
        \\#define HAVE_EPOLL_CREATE1 1
        \\#define HAVE_GETUID 1
        \\#define HAVE_GETEUID 1
        \\#define HAVE_GETIFADDRS 1
        \\#define HAVE_MEMFD_CREATE 1
        \\#define HAVE_MKOSTEMP 1
        \\#define HAVE_MMAP 1
        \\#define HAVE_POLL 1
        \\#define HAVE_POSIX_FALLOCATE 1
        \\#define HAVE_REALLOCARRAY 1
        \\#define HAVE_SETEUID 1
        \\#define HAVE_SETITIMER 1
        \\#define HAVE_SIGACTION 1
        \\#define HAVE_SIGPROCMASK 1
        \\#define HAVE_STRCASECMP 1
        \\#define HAVE_STRCASESTR 1
        \\#define HAVE_STRLCAT 1
        \\#define HAVE_STRLCPY 1
        \\#define HAVE_STRNCASECMP 1
        \\#define HAVE_STRNDUP 1
        \\#define HAVE_VASPRINTF 1
        \\#define HAVE_VSNPRINTF 1
        \\
        \\/* Hashtable support (for GLX + xres) */
        \\#define XSERVER_LIBPCIACCESS 0
        \\
        \\/* Debug */
        \\#ifdef NDEBUG
        \\#else
        \\#define DEBUG 1
        \\#endif
        \\
        \\#endif /* _DIX_CONFIG_H_ */
        \\
    ;
}

fn genVersionConfig() []const u8 {
    return
        \\/* Generated by build.zig for Xarcan */
        \\#define VENDOR_RELEASE 12101099
        \\#define VENDOR_NAME "The X.Org Foundation"
        \\#define VENDOR_NAME_SHORT "X.Org"
        \\#define VENDOR_WEB "http://wiki.x.org"
        \\#define VENDOR_MAN_VERSION "Version 21.1.99"
        \\
    ;
}

fn genXkbConfig() []const u8 {
    return
        \\/* Generated by build.zig for Xarcan */
        \\#define XKB_BIN_DIRECTORY "/usr/bin"
        \\#define XKB_BASE_DIRECTORY "/usr/share/X11/xkb"
        \\#define XKB_DFLT_RULES "evdev"
        \\#define XKB_DFLT_MODEL "pc105"
        \\#define XKB_DFLT_LAYOUT "us"
        \\#define XKB_DFLT_VARIANT ""
        \\#define XKB_DFLT_OPTIONS ""
        \\#define XKM_OUTPUT_DIR "/usr/share/X11/xkb/compiled/"
        \\
    ;
}

fn genXwaylandConfig() []const u8 {
    return
        \\/* Generated by build.zig for Xarcan — stub, xwayland features disabled */
        \\
    ;
}
