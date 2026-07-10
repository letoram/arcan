// AGP Vulkan Backend — GBM+KMS direct-to-display (no VK_KHR_display)
//
// For Apple Silicon / Asahi and other split-GPU/display setups where the
// Mesa ICD does NOT implement VK_KHR_display (Honeykrisp's physical device
// fails vkGetPhysicalDeviceDisplayPropertiesKHR outright, and
// vkGetDrmDisplayEXT returns VK_ERROR_UNKNOWN for both the GPU's and the
// apple-drm display card's fd).
//
// Approach — classic GBM+KMS pattern from upstream arcan's egl-dri backend:
//
//   1. Open /dev/dri/card2 (apple-drm, the display-only card) through
//      platform_device_open() so psep_open.zig's drmSetMaster fires and
//      arcan actually owns the CRTC.
//   2. Enumerate connectors, pick the first connected one, pick its
//      preferred mode, pick a free CRTC+encoder combo.
//   3. Allocate N (≥2) VkImages on card1 (asahi) with
//      VK_EXT_image_drm_format_modifier, export each as a DMA-BUF via
//      VK_KHR_external_memory_fd. Wrap each fd with
//      drmModeAddFB2WithModifiers on card2 to get a KMS framebuffer ID.
//   4. Render to image[i], wait for the fence, drmModePageFlip image[i]
//      onto the CRTC with DRM_MODE_PAGE_FLIP_EVENT, block on vblank via
//      drmHandleEvent, advance i.
//   5. On teardown, restore the saved CRTC state and drop master.
//
// Modifier negotiation: Honeykrisp advertises APPLE_GPU_TILED for its
// render target, apple-drm expects LINEAR (or maybe a subset of Apple
// tile layouts). We try each Vulkan-supported modifier against
// drmModeAddFB2WithModifiers; if all fail, fall back to GBM_BO_USE_LINEAR
// (slower but guaranteed to scan out).
//
// This module deliberately mirrors the shape of vk_wsi.zig (Swapchain,
// beginFrame/endFrame, DisplayInfo) so the call sites in
// platform/vk-display/video.zig don't need per-mode branching beyond the
// init/destroy boundary.

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const agp_vk = @import("vk.zig");

pub const std_options: std.Options = .{ .log_level = .info };

// On static-musl builds, the Vulkan/XCB ICDs are dlopened glibc libs that
// store TLS via tpidr_el0. musl's static binary uses tpidr_el0 too, with a
// different layout — when glibc-side malloc reads errno (TLS), it scribbles
// over musl's tcache header and the next CAS faults. The whole platform
// guards every ICD entry with zig_foreign_begin / zig_foreign_end (defined
// in zig_dlopen.zig) which swap the TLS register for the call's duration.
// vk_wsi.zig and vk_xcb.zig follow the same pattern; missing it produces
// the exact "SIGSEGV inside hk_CreateImage → malloc → __aarch64_cas4_acq"
// shape we hit during step 3 bring-up.
const use_zig_dlopen = (builtin.link_mode == .static and (builtin.abi == .musl or !builtin.link_libc));
extern fn zig_foreign_begin() callconv(.c) void;
extern fn zig_foreign_end() callconv(.c) void;

// @cImport unavailable in the no-LLVM self-hosted fork. Use the
// hand-written drm_cabi namespace; symbols resolve against dl_drm.zig
// at link time, which dlopens libdrm.so.2 at runtime.
const c = @import("drm_cabi.zig");

// platform_device_open is provided by src/platform/posix/psep_open.zig and
// runs the open in the privilege-separated parent so drmSetMaster fires on
// the returned fd. acquireDrmDisplay's bug was opening the cards directly
// via std.posix.openZ, which never made arcan a master.
extern fn platform_device_open(name: [*c]const u8, flags: c_int) c_int;

// Probe types

const MAX_CARDS = 4;

pub const CardInfo = struct {
    fd: c_int = -1,
    has_kms: bool = false,        // drmModeGetResources returned a connector with DRM_MODE_CONNECTED
    has_render_node: bool = false, // /sys/class/drm/cardN/device matches a renderD*/device
};

pub const FALLBACK_MODE_CAP: usize = 16;

pub const ConnectorPick = struct {
    connector_id: u32,
    encoder_id: u32,
    crtc_id: u32,
    mode: c.drmModeModeInfo,
    mm_width: u32,
    mm_height: u32,
    // Fallback chain: modes to try in order if `drmModeSetCrtc` rejects
    // the chosen primary. [0] == `mode`. The remainder is the connector's
    // EDID list (sorted descending bandwidth by the kernel). When the
    // panel reports a high-bandwidth preferred mode (e.g. 4K@144 needing
    // FRL+DSC) and the driver can't drive it, we walk down to a mode
    // that actually accepts. `n_fallback_modes` is the live count.
    fallback_modes: [FALLBACK_MODE_CAP]c.drmModeModeInfo,
    n_fallback_modes: u8,
};

// Module state (set by acquireDisplay, read by later steps)

pub const Acquired = struct {
    disp_fd: c_int = -1,        // card with the connected connector (apple-drm on Asahi)
    draw_fd: c_int = -1,        // card with the GPU render node (asahi on Asahi); equals disp_fd on unified hardware
    pick: ConnectorPick = std.mem.zeroes(ConnectorPick),
};

// Swapchain analog (shape mirrors vk_wsi.Swapchain)

pub const Swapchain = struct {
    images: [4]vk.Image = std.mem.zeroes([4]vk.Image),
    views: [4]vk.ImageView = std.mem.zeroes([4]vk.ImageView),
    memory: [4]vk.DeviceMemory = std.mem.zeroes([4]vk.DeviceMemory),
    dmabuf_fds: [4]std.posix.fd_t = .{ -1, -1, -1, -1 },
    kms_fb_ids: [4]u32 = .{ 0, 0, 0, 0 },

    image_count: u32 = 0,
    current_image: u32 = 0,

    extent: vk.Extent2D = .{ .width = 0, .height = 0 },
    format: vk.Format = .a2r10g10b10_unorm_pack32,

    drm_fd: std.posix.fd_t = -1,
    connector_id: u32 = 0,
    crtc_id: u32 = 0,
    saved_crtc: ?*c.drmModeCrtc = null, // restored on destroy

    // Dedicated present fence — endFrame submits with this and waits it
    // before drmModePageFlip so KMS doesn't scan a half-rendered buffer.
    // We can't reuse env.frame_fence here because vk_env_begin_frame_cmd
    // also waits on env.frame_fence next iteration; if we wait+reset it
    // synchronously inside endFrame, the next begin_frame_cmd blocks
    // forever on a fence nobody will signal.
    present_fence: vk.Fence = .null_handle,
};

pub const DisplayInfo = struct {
    name: [256]u8 = std.mem.zeroes([256]u8),
    name_len: usize = 0,
    physical_width_mm: u32 = 0,
    physical_height_mm: u32 = 0,
    mode_width: u32 = 0,
    mode_height: u32 = 0,
    refresh_mhz: u32 = 0,
};

// Helpers

/// Check if /sys/class/drm/cardN/device matches any renderD{128..131}/device.
/// True only for cards backed by a real render-capable GPU. apple-drm has
/// connectors but no render node, so it returns false.
fn cardHasRenderNode(card_idx: u8) bool {
    var card_link_buf: [256]u8 = undefined;
    var card_path_buf: [64]u8 = undefined;
    const card_path = std.fmt.bufPrintZ(&card_path_buf, "/sys/class/drm/card{d}/device", .{card_idx}) catch return false;
    const card_link = std.posix.readlinkZ(card_path, &card_link_buf) catch return false;

    var r: u8 = 128;
    while (r < 132) : (r += 1) {
        var render_link_buf: [256]u8 = undefined;
        var render_path_buf: [64]u8 = undefined;
        const render_path = std.fmt.bufPrintZ(&render_path_buf, "/sys/class/drm/renderD{d}/device", .{r}) catch continue;
        const render_link = std.posix.readlinkZ(render_path, &render_link_buf) catch continue;
        if (std.mem.eql(u8, card_link, render_link)) return true;
    }
    return false;
}

/// Walk a card's connectors. Sets card.has_kms if any connector reports
/// DRM_MODE_CONNECTED. Doesn't pick one — that happens in selectConnector.
fn probeKms(card: *CardInfo) void {
    const res = c.drmModeGetResources(card.fd) orelse return;
    defer c.drmModeFreeResources(res);

    var i: c_int = 0;
    while (i < res.*.count_connectors) : (i += 1) {
        const cid = res.*.connectors[@intCast(i)];
        const conn = c.drmModeGetConnector(card.fd, cid) orelse continue;
        defer c.drmModeFreeConnector(conn);
        if (conn.*.connection == c.DRM_MODE_CONNECTED) {
            card.has_kms = true;
            return;
        }
    }
}

/// Pick the first connected connector on disp_fd, choose a mode, find an
/// encoder it can drive, and from that encoder pick a CRTC. Mirrors
/// egl-dri's setup_kms() shape.
///
/// Mode selection: default is highest refresh rate among all listed modes.
/// Env `ARCAN_VIDEO_MODE=WxH` caps resolution (e.g. "3840x2160" to get 4K
/// modes instead of the panel's native 3840x2400). Env `ARCAN_VIDEO_MODE=WxH@R`
/// pins to that exact resolution+refresh if available, else falls back to the
/// highest-refresh variant at WxH, else to the previous default.
fn selectConnector(disp_fd: c_int) ?ConnectorPick {
    const res = c.drmModeGetResources(disp_fd) orelse return null;
    defer c.drmModeFreeResources(res);

    // Parse the env override once; applies to whichever connector matches.
    // Use std.c.getenv (not std.posix.getenv) — the latter walks the initial
    // environ table snapshot captured at program start before main(), which
    // misses values set by wrappers/systemd on our child after fork/exec
    // reshuffles. std.c.getenv goes through libc's live environ table.
    const env_mode_raw = std.c.getenv("ARCAN_VIDEO_MODE");
    var want_w: u32 = 0;
    var want_h: u32 = 0;
    var want_refresh: u32 = 0; // 0 = any
    if (env_mode_raw) |cstr| {
        const s = std.mem.span(cstr);
        std.log.err("vk_gbm_kms: ARCAN_VIDEO_MODE=\"{s}\" (raw)", .{s});
        const x_idx = std.mem.indexOfScalar(u8, s, 'x');
        const at_idx = std.mem.indexOfScalar(u8, s, '@');
        if (x_idx) |xi| {
            want_w = std.fmt.parseInt(u32, s[0..xi], 10) catch 0;
            const end = at_idx orelse s.len;
            want_h = std.fmt.parseInt(u32, s[xi + 1 .. end], 10) catch 0;
            if (at_idx) |ai| {
                want_refresh = std.fmt.parseInt(u32, s[ai + 1 ..], 10) catch 0;
            }
        }
        std.log.err("vk_gbm_kms: env parsed want={d}x{d}@{d}", .{ want_w, want_h, want_refresh });
    } else {
        std.log.err("vk_gbm_kms: ARCAN_VIDEO_MODE unset (default to preferred)", .{});
    }

    // Connector loop
    var ci: c_int = 0;
    while (ci < res.*.count_connectors) : (ci += 1) {
        const cid = res.*.connectors[@intCast(ci)];
        const conn = c.drmModeGetConnector(disp_fd, cid) orelse continue;
        defer c.drmModeFreeConnector(conn);
        if (conn.*.connection != c.DRM_MODE_CONNECTED) continue;
        if (conn.*.count_modes == 0) continue;

        // Enumerate modes for diagnostics — useful at bring-up time and when
        // users wonder why we didn't pick the highest-refresh variant.
        std.log.err("vk_gbm_kms: connector_id={d} has {d} mode(s):", .{ cid, conn.*.count_modes });
        var mi: c_int = 0;
        while (mi < conn.*.count_modes) : (mi += 1) {
            const mm = conn.*.modes[@intCast(mi)];
            const preferred = (mm.type & c.DRM_MODE_TYPE_PREFERRED) != 0;
            std.log.err("  [{d}] {d}x{d}@{d}Hz clock={d}kHz{s}", .{
                mi, mm.hdisplay, mm.vdisplay, mm.vrefresh, mm.clock,
                if (preferred) " (preferred)" else "",
            });
        }

        // Selection. Priority:
        //   1. Exact env match (WxH@R).
        //   2. Highest refresh rate at env-capped resolution (WxH, any refresh).
        //   3. DRM_MODE_TYPE_PREFERRED's resolution, highest refresh at that size.
        //      This is what the EDID advertises as the panel's native mode;
        //      plain "highest vrefresh overall" picks 1280x1024@75 over
        //      3840x2400@60 on a 4K panel, which is terrible.
        //   4. Fallback to mode 0 (kernel sorted it to the top).
        var preferred_w: u32 = 0;
        var preferred_h: u32 = 0;
        {
            var pm: c_int = 0;
            while (pm < conn.*.count_modes) : (pm += 1) {
                const mm = conn.*.modes[@intCast(pm)];
                if ((mm.type & c.DRM_MODE_TYPE_PREFERRED) != 0) {
                    preferred_w = mm.hdisplay;
                    preferred_h = mm.vdisplay;
                    break;
                }
            }
        }
        // Lock the "target resolution" for highest-refresh selection. If env
        // specified WxH, use that; else use the preferred (native) resolution;
        // else fall through to "any".
        const lock_w: u32 = if (want_w != 0) want_w else preferred_w;
        const lock_h: u32 = if (want_h != 0) want_h else preferred_h;

        var mode_idx: usize = 0;
        var best_rate: u32 = 0;
        var found: bool = false;
        var m: c_int = 0;
        while (m < conn.*.count_modes) : (m += 1) {
            const mm = conn.*.modes[@intCast(m)];
            if (lock_w != 0 and lock_h != 0) {
                if (mm.hdisplay != lock_w or mm.vdisplay != lock_h) continue;
                if (want_w != 0 and want_refresh != 0 and mm.vrefresh == want_refresh) {
                    mode_idx = @intCast(m);
                    found = true;
                    break;
                }
                if (mm.vrefresh > best_rate) {
                    best_rate = mm.vrefresh;
                    mode_idx = @intCast(m);
                    found = true;
                }
            } else if (!found) {
                // No preferred flag + no env; fall back to highest-refresh
                // overall only when no other signal exists.
                if (mm.vrefresh > best_rate) {
                    best_rate = mm.vrefresh;
                    mode_idx = @intCast(m);
                }
            }
        }
        const mode = conn.*.modes[mode_idx];

        // Encoder + CRTC: try the connector's currently-bound encoder first
        // (that's what fbcon/simpledrm left set up; reusing it minimizes
        // disruption to the console handoff). If that doesn't yield a CRTC,
        // walk the encoder list and pick the first encoder with a possible
        // CRTC bit set in the resource list.
        var crtc_id: u32 = 0;
        var encoder_id: u32 = 0;

        if (conn.*.encoder_id != 0) {
            const enc = c.drmModeGetEncoder(disp_fd, conn.*.encoder_id);
            if (enc) |e| {
                defer c.drmModeFreeEncoder(e);
                if (e.*.crtc_id != 0) {
                    crtc_id = e.*.crtc_id;
                    encoder_id = conn.*.encoder_id;
                }
            }
        }

        if (crtc_id == 0) {
            var ei: c_int = 0;
            outer: while (ei < conn.*.count_encoders) : (ei += 1) {
                const eid = conn.*.encoders[@intCast(ei)];
                const enc = c.drmModeGetEncoder(disp_fd, eid) orelse continue;
                defer c.drmModeFreeEncoder(enc);
                var bit: u5 = 0;
                while (bit < res.*.count_crtcs) : (bit += 1) {
                    if ((enc.*.possible_crtcs & (@as(u32, 1) << bit)) != 0) {
                        crtc_id = res.*.crtcs[bit];
                        encoder_id = eid;
                        break :outer;
                    }
                    if (bit == 31) break;
                }
            }
        }

        if (crtc_id == 0) continue;

        // Build fallback chain: chosen mode at [0], then every other mode
        // in EDID order (sorted descending bandwidth by the kernel). Cap
        // at FALLBACK_MODE_CAP. If `drmModeSetCrtc` later rejects the
        // primary (HDMI 2.1 FRL/DSC unsupported, plane bandwidth budget
        // exceeded, etc.), the modeset retry walks this list.
        var pick: ConnectorPick = .{
            .connector_id = cid,
            .encoder_id = encoder_id,
            .crtc_id = crtc_id,
            .mode = mode,
            .mm_width = conn.*.mmWidth,
            .mm_height = conn.*.mmHeight,
            .fallback_modes = undefined,
            .n_fallback_modes = 1,
        };
        pick.fallback_modes[0] = mode;
        {
            var fi: c_int = 0;
            while (fi < conn.*.count_modes and pick.n_fallback_modes < FALLBACK_MODE_CAP) : (fi += 1) {
                if (@as(usize, @intCast(fi)) == mode_idx) continue;
                pick.fallback_modes[pick.n_fallback_modes] = conn.*.modes[@intCast(fi)];
                pick.n_fallback_modes += 1;
            }
        }
        return pick;
    }

    return null;
}

// Public API

/// Probe /dev/dri/card0..3, classify each as KMS-capable / render-capable,
/// then pick a (disp_fd, draw_fd) pair: prefer same-device, fall back to
/// split-device (Apple Silicon: disp=apple-drm, draw=asahi). On the chosen
/// disp_fd, pick a connected connector + preferred mode + CRTC.
///
/// On success, populates `out` with the chosen card pair and connector
/// selection. On failure, all opened fds are closed and an error is returned.
/// The fds in `out` must be closed by the caller (or by destroySwapchain
/// once a swapchain is built on top of them).
pub fn acquireDisplay(out: *Acquired, info: *DisplayInfo) !void {
    var cards: [MAX_CARDS]CardInfo = .{ .{}, .{}, .{}, .{} };
    var probed: u8 = 0;

    // First pass: open + classify each card.
    var i: u8 = 0;
    while (i < MAX_CARDS) : (i += 1) {
        var path_buf: [32]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, "/dev/dri/card{d}", .{i}) catch continue;

        // platform_device_open routes through psep_open.zig which calls
        // drmSetMaster on the returned fd — essential for KMS modeset.
        const O_RDWR: c_int = 2;
        const O_CLOEXEC: c_int = 0o2000000;
        const fd = platform_device_open(path.ptr, O_RDWR | O_CLOEXEC);
        if (fd < 0) continue;

        cards[i].fd = fd;
        probed += 1;
        probeKms(&cards[i]);
        cards[i].has_render_node = cardHasRenderNode(i);
        // Step 2 diag: keep at .err for the duration of bring-up so the probe
        // results are visible without depending on a runtime log filter that
        // the engine may override. Lower to .info once the backend is stable.
        std.log.err("vk_gbm_kms: card{d} fd={d} has_kms={} has_render={}", .{ i, fd, cards[i].has_kms, cards[i].has_render_node });
    }

    if (probed == 0) {
        std.log.err("vk_gbm_kms: no /dev/dri/card* could be opened via platform_device_open", .{});
        return error.NoCardsOpenable;
    }

    // Second pass: pick (disp, draw). Prefer same-device.
    var disp_idx: i8 = -1;
    var draw_idx: i8 = -1;

    for (0..MAX_CARDS) |idx| {
        if (cards[idx].has_kms and cards[idx].has_render_node) {
            disp_idx = @intCast(idx);
            draw_idx = @intCast(idx);
            break;
        }
    }

    if (disp_idx == -1) {
        // Split-device fallback (Apple Silicon shape).
        for (0..MAX_CARDS) |di| {
            if (!cards[di].has_kms) continue;
            for (0..MAX_CARDS) |dr| {
                if (di == dr) continue;
                if (!cards[dr].has_render_node) continue;
                disp_idx = @intCast(di);
                draw_idx = @intCast(dr);
                break;
            }
            if (disp_idx != -1) break;
        }
    }

    if (disp_idx == -1) {
        // No KMS-capable card. Fall back to render-only — find any card with a
        // render node and run with no scanout / no connector.  The engine can
        // still render to its rendertargets; clients connect via shmif and
        // draw normally; only the actual display hand-off is skipped. When a
        // connector becomes available later (netlink hotplug in
        // src/platform/posix/psep_open.zig:check_netlink), the platform layer
        // calls this function again and promotes to a real KMS swapchain.
        // No "headless" platform — same code path, just one branch missing
        // its outputs because the environment doesn't have any.
        for (0..MAX_CARDS) |idx| {
            if (cards[idx].has_render_node) {
                draw_idx = @intCast(idx);
                break;
            }
        }
        if (draw_idx == -1) {
            std.log.err("vk_gbm_kms: no render-capable card found — cannot proceed without at least a render node", .{});
            for (0..MAX_CARDS) |idx| {
                if (cards[idx].fd >= 0) std.posix.close(cards[idx].fd);
            }
            return error.NoUsableCardPair;
        }
        std.log.warn("vk_gbm_kms: no KMS connector available; coming up render-only on card{d}, awaiting hotplug", .{draw_idx});
    }

    const has_display = (disp_idx != -1);
    const disp_fd: c_int = if (has_display) cards[@intCast(disp_idx)].fd else -1;
    const draw_fd: c_int = cards[@intCast(draw_idx)].fd;
    if (has_display) {
        std.log.err("vk_gbm_kms: chose disp=card{d}(fd={d}) draw=card{d}(fd={d})", .{ disp_idx, disp_fd, draw_idx, draw_fd });
    } else {
        std.log.warn("vk_gbm_kms: render-only on card{d}(fd={d}), no scanout", .{ draw_idx, draw_fd });
    }

    // Close every fd we don't need anymore.
    for (0..MAX_CARDS) |idx| {
        if (cards[idx].fd >= 0 and cards[idx].fd != disp_fd and cards[idx].fd != draw_fd) {
            std.posix.close(cards[idx].fd);
        }
    }

    // Connector + mode + CRTC selection on disp_fd. Only attempted when KMS is
    // available; render-only mode synthesises a default mode so downstream
    // sizing (rendertarget extent, swapchain images) still has concrete
    // dimensions to use.
    var pick: ConnectorPick = std.mem.zeroes(ConnectorPick);
    if (has_display) {
        pick = selectConnector(disp_fd) orelse {
            std.log.err("vk_gbm_kms: card has KMS but no connector+mode+CRTC combination produced a valid pick", .{});
            if (disp_fd != draw_fd) std.posix.close(draw_fd);
            std.posix.close(disp_fd);
            return error.NoUsableConnector;
        };
        std.log.err(
            "vk_gbm_kms: picked connector_id={d} encoder_id={d} crtc_id={d} mode={d}x{d}@{d}Hz ({d}x{d}mm)",
            .{ pick.connector_id, pick.encoder_id, pick.crtc_id, pick.mode.hdisplay, pick.mode.vdisplay, pick.mode.vrefresh, pick.mm_width, pick.mm_height },
        );
    } else {
        // Render-only default. 1280x720 @ 60Hz is a safe placeholder; the
        // actual size doesn't matter because nothing scans out — but the
        // engine wires width/height through to rendertargets, so it has to
        // be concrete.
        pick.mode.hdisplay = 1280;
        pick.mode.vdisplay = 720;
        pick.mode.vrefresh = 60;
        const placeholder = "render-only";
        @memcpy(pick.mode.name[0..placeholder.len], placeholder);
    }

    out.* = .{
        .disp_fd = disp_fd,
        .draw_fd = draw_fd,
        .pick = pick,
    };

    // Surface mode info to caller via DisplayInfo for downstream sizing.
    info.* = .{
        .physical_width_mm = pick.mm_width,
        .physical_height_mm = pick.mm_height,
        .mode_width = pick.mode.hdisplay,
        .mode_height = pick.mode.vdisplay,
        .refresh_mhz = @as(u32, pick.mode.vrefresh) * 1000,
    };
    const name_bytes = std.mem.span(@as([*:0]const u8, @ptrCast(&pick.mode.name)));
    const copy_len = @min(name_bytes.len, info.name.len - 1);
    @memcpy(info.name[0..copy_len], name_bytes[0..copy_len]);
    info.name_len = copy_len;
}

// Step 3: swapchain allocation (Vulkan VkImage → DMA-BUF → KMS FB)

const N_BUFFERS: u32 = 2;

// DRM fourcc / modifier constants (from drm_fourcc.h, hardcoded to avoid
// pulling another @cInclude). XR24 = X8R8G8B8 little-endian = memory layout
// B,G,R,X — the same byte order as VK_FORMAT_B8G8R8A8_UNORM with alpha
// treated as don't-care, which is what KMS scanout planes expect.
const DRM_FORMAT_XRGB8888: u32 = 0x34325258;
const DRM_FORMAT_XRGB2101010: u32 = 0x30335258; // 'XR30'
const DRM_FORMAT_MOD_LINEAR: u64 = 0;
const DRM_FORMAT_MOD_INVALID: u64 = (1 << 56) - 1;
const DRM_MODE_FB_MODIFIERS: u32 = 1 << 1;

fn findMemoryTypeLocal(env: *agp_vk.VkEnv, type_filter: u32, properties: vk.MemoryPropertyFlags) ?u32 {
    for (0..env.mem_props.memory_type_count) |i| {
        const idx: u5 = @intCast(i);
        if ((type_filter & (@as(u32, 1) << idx)) != 0) {
            const flags = env.mem_props.memory_types[i].property_flags;
            const req: u32 = @bitCast(properties);
            const has: u32 = @bitCast(flags);
            if ((has & req) == req) return @intCast(i);
        }
    }
    return null;
}

/// Allocate N color buffers as Vulkan VkImages with VK_EXT_image_drm_format_modifier
/// (LINEAR for now — guaranteed compatible with apple-drm scanout), export each
/// as a DMA-BUF fd via VK_KHR_external_memory_fd, then register each fd with
/// disp_fd's KMS via drmModeAddFB2WithModifiers (or drmModeAddFB2 on fallback).
///
/// Modifier strategy: LINEAR is the lowest-common-denominator that any KMS
/// driver accepts. APPLE_GPU_TILED is what Honeykrisp natively wants for its
/// render targets, but apple-drm may not understand it. We start with LINEAR
/// to prove the pipeline; modifier negotiation lands later (step 4 polish) if
/// the perf hit is real.
pub fn createSwapchain(env: *agp_vk.VkEnv, acquired: *const Acquired, width: u32, height: u32) !Swapchain {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    var sc: Swapchain = .{
        .extent = .{ .width = width, .height = height },
        .format = .a2r10g10b10_unorm_pack32,
        .drm_fd = acquired.disp_fd,
        .connector_id = acquired.pick.connector_id,
        .crtc_id = acquired.pick.crtc_id,
    };

    // Reverse-engineering aid: emit each step's status at .err so failures are
    // visible without depending on a runtime log filter.
    std.log.err("vk_gbm_kms: createSwapchain {d}x{d} (N={d}, modifier=LINEAR)", .{ width, height, N_BUFFERS });

    sc.present_fence = env.vkd.createFence(env.device, &.{ .flags = .{ .signaled_bit = true } }, null) catch |e| {
        std.log.err("vk_gbm_kms: present_fence createFence failed: {s}", .{@errorName(e)});
        return error.FenceCreateFailed;
    };

    var i: u32 = 0;
    errdefer destroySwapchain(env, &sc);

    while (i < N_BUFFERS) : (i += 1) {
        // 1. Build VkImage with explicit LINEAR modifier + external memory
        const modifier: u64 = DRM_FORMAT_MOD_LINEAR;
        // List form (lets Vulkan pick stride for us); switch to explicit only
        // if we need to match a foreign exporter's exact layout.
        const mod_values: [1]u64 = .{modifier};
        var drm_mod_list = vk.ImageDrmFormatModifierListCreateInfoEXT{
            .drm_format_modifier_count = 1,
            .p_drm_format_modifiers = &mod_values,
        };
        const ext_mem_info = vk.ExternalMemoryImageCreateInfo{
            .p_next = @ptrCast(&drm_mod_list),
            .handle_types = .{ .dma_buf_bit_ext = true },
        };

        const image = env.vkd.createImage(env.device, &.{
            .p_next = &ext_mem_info,
            .image_type = .@"2d",
            .format = sc.format,
            .extent = .{ .width = width, .height = height, .depth = 1 },
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = .drm_format_modifier_ext,
            .usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
            .sharing_mode = .exclusive,
            .initial_layout = .undefined,
        }, null) catch |e| {
            std.log.err("vk_gbm_kms: createImage[{d}] failed: {s}", .{ i, @errorName(e) });
            return error.ImageCreateFailed;
        };
        sc.images[i] = image;

        // 2. Allocate device-local memory with EXPORT capability
        const mem_req = env.vkd.getImageMemoryRequirements(env.device, image);
        const mem_type = findMemoryTypeLocal(env, mem_req.memory_type_bits, .{ .device_local_bit = true }) orelse
            findMemoryTypeLocal(env, mem_req.memory_type_bits, .{}) orelse {
            std.log.err("vk_gbm_kms: no compatible memory type for image[{d}]", .{i});
            return error.NoCompatibleMemory;
        };
        const export_info = vk.ExportMemoryAllocateInfo{
            .handle_types = .{ .dma_buf_bit_ext = true },
        };
        const memory = env.vkd.allocateMemory(env.device, &.{
            .p_next = &export_info,
            .allocation_size = mem_req.size,
            .memory_type_index = mem_type,
        }, null) catch |e| {
            std.log.err("vk_gbm_kms: allocateMemory[{d}] failed: {s}", .{ i, @errorName(e) });
            return error.MemoryAllocFailed;
        };
        sc.memory[i] = memory;
        env.vkd.bindImageMemory(env.device, image, memory, 0) catch |e| {
            std.log.err("vk_gbm_kms: bindImageMemory[{d}] failed: {s}", .{ i, @errorName(e) });
            return error.BindMemoryFailed;
        };

        // 3. Export memory as DMA-BUF fd
        const fd = env.vkd.getMemoryFdKHR(env.device, &.{
            .memory = memory,
            .handle_type = .{ .dma_buf_bit_ext = true },
        }) catch |e| {
            std.log.err("vk_gbm_kms: getMemoryFdKHR[{d}] failed: {s}", .{ i, @errorName(e) });
            return error.ExportFdFailed;
        };
        sc.dmabuf_fds[i] = fd;

        // 4. Get plane layout (stride/offset) for KMS FB registration
        const sub = vk.ImageSubresource{
            .aspect_mask = .{ .memory_plane_0_bit_ext = true },
            .mip_level = 0,
            .array_layer = 0,
        };
        const layout = env.vkd.getImageSubresourceLayout(env.device, image, &sub);
        const stride: u32 = @intCast(layout.row_pitch);
        const offset_b: u32 = @intCast(layout.offset);

        // 5. Create image view (color attachment for our render pass)
        const view = env.vkd.createImageView(env.device, &.{
            .image = image,
            .view_type = .@"2d",
            .format = sc.format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null) catch |e| {
            std.log.err("vk_gbm_kms: createImageView[{d}] failed: {s}", .{ i, @errorName(e) });
            return error.ImageViewFailed;
        };
        sc.views[i] = view;

        // 6. + 7. DMA-BUF fd → DRM handle (PRIME) → KMS framebuffer registration.
        // Both steps need a KMS-capable disp_fd. In render-only mode (no
        // connector, no scanout) acquired.disp_fd is -1 and we skip both —
        // the VkImage is still valid as a render target, it just never
        // becomes a KMS fb. kms_fb_ids[i] stays 0 as a sentinel for endFrame.
        if (acquired.disp_fd < 0) {
            std.log.warn("vk_gbm_kms: buf[{d}] image=ok mem=ok fd={d} stride={d} (render-only, skip KMS FB)", .{ i, fd, stride });
            continue;
        }

        var drm_handle: u32 = 0;
        const prime_ret = c.drmPrimeFDToHandle(acquired.disp_fd, fd, &drm_handle);
        if (prime_ret != 0) {
            std.log.err("vk_gbm_kms: drmPrimeFDToHandle[{d}] failed: ret={d} errno={d}", .{ i, prime_ret, std.c._errno().* });
            return error.PrimeFDToHandleFailed;
        }

        var handles: [4]u32 = .{ drm_handle, 0, 0, 0 };
        var pitches: [4]u32 = .{ stride, 0, 0, 0 };
        var offsets: [4]u32 = .{ offset_b, 0, 0, 0 };
        var modifiers: [4]u64 = .{ modifier, 0, 0, 0 };
        var fb_id: u32 = 0;
        const flags: u32 = if (modifier == DRM_FORMAT_MOD_LINEAR) 0 else DRM_MODE_FB_MODIFIERS;
        const addfb_ret = c.drmModeAddFB2WithModifiers(
            acquired.disp_fd,
            width,
            height,
            DRM_FORMAT_XRGB2101010,
            &handles,
            &pitches,
            &offsets,
            &modifiers,
            &fb_id,
            flags,
        );
        if (addfb_ret != 0 or fb_id == 0) {
            // Fall back to non-modifier AddFB2 (LINEAR doesn't strictly need modifier flag)
            const addfb2_ret = c.drmModeAddFB2(
                acquired.disp_fd,
                width,
                height,
                DRM_FORMAT_XRGB2101010,
                &handles,
                &pitches,
                &offsets,
                &fb_id,
                0,
            );
            if (addfb2_ret != 0 or fb_id == 0) {
                std.log.err("vk_gbm_kms: drmModeAddFB2[{d}] failed: withMod={d} fallback={d} errno={d}", .{ i, addfb_ret, addfb2_ret, std.c._errno().* });
                return error.AddFBFailed;
            }
        }
        sc.kms_fb_ids[i] = fb_id;
        std.log.err("vk_gbm_kms: buf[{d}] image=ok mem=ok fd={d} handle={d} stride={d} fb_id={d}", .{ i, fd, drm_handle, stride, fb_id });
    }

    sc.image_count = N_BUFFERS;
    return sc;
}

// Step 4: render loop (beginFrame / endFrame + page-flip)

// Module-private modeset state. drmModeSetCrtc is called once on the first
// frame to bind the CRTC to fb_ids[0]; subsequent frames use drmModePageFlip.
// saved_crtc captures the pre-modeset state for restoration in step 5.
var modeset_done: bool = false;
var pending_flip: bool = false;
var initial_mode: c.drmModeModeInfo = undefined;

// Fallback chain mirrored from ConnectorPick. Used by endFrame's modeset
// retry to walk down to a mode the kernel actually accepts.
var fallback_modes: [FALLBACK_MODE_CAP]c.drmModeModeInfo = undefined;
var n_fallback_modes: u8 = 0;
var initial_connector_id: u32 = 0;

fn pageFlipHandler(_: c_int, _: c_uint, _: c_uint, _: c_uint, user_data: ?*anyopaque) callconv(.c) void {
    const flag: *bool = @ptrCast(@alignCast(user_data orelse return));
    flag.* = false;
}

var drm_event_ctx: c.drmEventContext = .{
    .version = 2,
    .vblank_handler = null,
    .page_flip_handler = pageFlipHandler,
    .page_flip_handler2 = null,
    .sequence_handler = null,
};

pub fn beginFrame(env: *agp_vk.VkEnv, sc: *Swapchain, clear_color: [4]f32) !void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const idx = sc.current_image;
    if (idx >= sc.image_count) return error.InvalidImageIndex;

    // Transition image to color attachment for our render pass.
    const to_color = [_]vk.ImageMemoryBarrier2{.{
        .src_stage_mask = .{ .top_of_pipe_bit = true },
        .src_access_mask = .{},
        .dst_stage_mask = .{ .color_attachment_output_bit = true },
        .dst_access_mask = .{ .color_attachment_write_bit = true },
        .old_layout = .undefined,
        .new_layout = .color_attachment_optimal,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = sc.images[idx],
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }};
    env.vkd.cmdPipelineBarrier2(env.cmd, &.{
        .image_memory_barrier_count = to_color.len,
        .p_image_memory_barriers = &to_color,
    });

    const color_attachment = [_]vk.RenderingAttachmentInfo{.{
        .image_view = sc.views[idx],
        .image_layout = .color_attachment_optimal,
        .resolve_mode = .{},
        .resolve_image_layout = .undefined,
        .load_op = .clear,
        .store_op = .store,
        .clear_value = .{ .color = .{ .float_32 = clear_color } },
    }};
    env.vkd.cmdBeginRendering(env.cmd, &.{
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = sc.extent },
        .layer_count = 1,
        .view_mask = 0,
        .color_attachment_count = color_attachment.len,
        .p_color_attachments = &color_attachment,
        .p_depth_attachment = if (env.depth_active and env.depth_view != .null_handle)
            &vk.RenderingAttachmentInfo{
                .image_view = env.depth_view,
                .image_layout = .depth_stencil_attachment_optimal,
                .resolve_mode = .{},
                .resolve_image_layout = .undefined,
                .load_op = .clear,
                .store_op = .dont_care,
                .clear_value = .{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
            }
        else
            null,
        .p_stencil_attachment = if (env.stencil_active and env.stencil_view != .null_handle)
            &vk.RenderingAttachmentInfo{
                .image_view = env.stencil_view,
                .image_layout = .depth_stencil_attachment_optimal,
                .resolve_mode = .{},
                .resolve_image_layout = .undefined,
                .load_op = .clear,
                .store_op = .dont_care,
                .clear_value = .{ .depth_stencil = .{ .depth = 0, .stencil = 0 } },
            }
        else
            null,
    });
}

pub fn endFrame(env: *agp_vk.VkEnv, sc: *Swapchain, acquired: *Acquired) !void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const idx = sc.current_image;

    env.vkd.cmdEndRendering(env.cmd);

    // Transition for KMS scanout. GENERAL is the lowest-common-denominator
    // layout that any future op (including external scanout) accepts. Once
    // step-4 is verified, switch to a queueFamilyForeign release for
    // explicit cross-API synchronization.
    const to_scanout = [_]vk.ImageMemoryBarrier2{.{
        .src_stage_mask = .{ .color_attachment_output_bit = true },
        .src_access_mask = .{ .color_attachment_write_bit = true },
        .dst_stage_mask = .{ .bottom_of_pipe_bit = true },
        .dst_access_mask = .{},
        .old_layout = .color_attachment_optimal,
        .new_layout = .general,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = sc.images[idx],
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }};
    env.vkd.cmdPipelineBarrier2(env.cmd, &.{
        .image_memory_barrier_count = to_scanout.len,
        .p_image_memory_barriers = &to_scanout,
    });

    env.cmd_recording = false;
    env.vkd.endCommandBuffer(env.cmd) catch return error.CmdEndFailed;

    // No swapchain semaphores — we own the images. Submit with the frame
    // fence so vk_env_begin_frame_cmd can wait it on the next iteration.
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{
        .command_buffer = env.cmd,
        .device_mask = 0,
    }};
    // Submit on present_fence (NOT env.frame_fence — see comment on the
    // fence field). queueSubmit also signals env.frame_fence semantically
    // by using Vulkan's normal sync; we don't need to. The present_fence
    // gates only the page-flip wait below.
    _ = env.vkd.resetFences(env.device, 1, @ptrCast(&sc.present_fence)) catch {};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = cmd_info.len,
        .p_command_buffer_infos = &cmd_info,
    }}, sc.present_fence) catch return error.SubmitFailed;

    // Also signal env.frame_fence so vk_env_begin_frame_cmd's wait next
    // iteration completes promptly — submit a no-op (empty submit) to do it.
    env.vkd.queueSubmit2(env.graphics_queue, 0, null, env.frame_fence) catch {};

    // Block on the GPU before handing the buffer to KMS. A future revision
    // can use a sync_file FD passed via DRM_MODE_PAGE_FLIP_TARGET so KMS
    // does the wait, but this is the simplest correct sequencing.
    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&sc.present_fence), .true, std.math.maxInt(u64)) catch {};

    // Render-only mode: no KMS to hand the frame to. The GPU has already
    // rendered into sc.images[idx]; advance the round-robin and we're done.
    // When a connector hotplug fires, the platform layer rebuilds the
    // swapchain with KMS fbs and modeset_done resets to false.
    if (sc.drm_fd < 0) {
        // Expose the just-rendered image for offscreen readback (save_ppm /
        // agp_save_output / frame capture). It is left in .general by the
        // to_scanout barrier above; record that so the readback uses the
        // right old_layout. This is the only "present" the headless path has.
        env.last_presented_image = sc.images[idx];
        env.last_presented_layout = .general;
        agp_vk.frameCaptureCheck(env);
        sc.current_image = (sc.current_image + 1) % sc.image_count;
        return;
    }

    // Modeset on the very first frame (binds CRTC to fb_id), page-flip from
    // then on. Save the original CRTC state so step 5 can restore it.
    //
    // Mode-fallback chain: drmModeSetCrtc returns -ENOSPC (-28) when the
    // kernel can't drive the requested mode (e.g. the EDID-preferred
    // 4K@144 needs HDMI 2.1 FRL/DSC which the apple-drm DCP path doesn't
    // implement on every variant). Walk the fallback list — populated
    // from the connector's full EDID list in selectConnector() and
    // mirrored here by primeForModeset / tryPromoteToHeadful — until one
    // accepts. Without this we'd panic; the previous behaviour was to
    // surface the error up to the engine which then null-derefed in a
    // downstream display-state lookup.
    if (!modeset_done) {
        sc.saved_crtc = c.drmModeGetCrtc(sc.drm_fd, sc.crtc_id);
        var connector_arr: [1]u32 = .{sc.connector_id};

        const limit: u8 = if (n_fallback_modes > 0) n_fallback_modes else 1;
        var attempt: u8 = 0;
        var setret: c_int = -1;
        while (attempt < limit) : (attempt += 1) {
            // primeForModeset / tryPromoteToHeadful seed fallback_modes[0]
            // == initial_mode. If n_fallback_modes == 0 (very early call,
            // shouldn't happen) we still try initial_mode once.
            const try_mode: c.drmModeModeInfo =
                if (n_fallback_modes > 0) fallback_modes[attempt] else initial_mode;
            setret = c.drmModeSetCrtc(
                sc.drm_fd,
                sc.crtc_id,
                sc.kms_fb_ids[idx],
                0, 0,
                &connector_arr[0],
                1,
                @constCast(&try_mode),
            );
            if (setret == 0) {
                initial_mode = try_mode;
                break;
            }
            std.log.err(
                "vk_gbm_kms: drmModeSetCrtc[{d}/{d}] {d}x{d}@{d}Hz clock={d}kHz failed ret={d} errno={d}",
                .{ attempt + 1, limit,
                   try_mode.hdisplay, try_mode.vdisplay, try_mode.vrefresh, try_mode.clock,
                   setret, std.c._errno().* });
        }
        if (setret != 0) {
            // MAY-200: all 16 fallback modes rejected. Pre-patch behaviour
            // returned error.ModesetFailed every frame, which kept this
            // loop firing 16 setCrtc syscalls per frame indefinitely
            // (337k+ failure lines / minute on the DCP-wedge path) and
            // left acquired.disp_fd dangling so the outer hotplug guard
            // in synchDisplay (state.gbm_acquired.disp_fd < 0) couldn't
            // re-arm tryPromoteToHeadful on a subsequent clean event.
            // Bail to render-only: clear sc.drm_fd, hand back the
            // disp_fd, leave acquired.disp_fd = -1 so the very next
            // DISPLAY_CONNECTOR_STATE event re-enters tryPromoteToHeadful
            // with fresh state. Silent on all subsequent frames.
            std.log.err(
                "vk_gbm_kms: all {d} fallback modes rejected; bailing to render-only — DCP likely wedged (MAY-200). " ++
                    "Next hotplug event will retry tryPromoteToHeadful.",
                .{limit});
            if (acquired.disp_fd >= 0) {
                std.posix.close(acquired.disp_fd);
                acquired.disp_fd = -1;
            }
            sc.drm_fd = -1;
            sc.connector_id = 0;
            sc.crtc_id = 0;
            modeset_done = false;
            pending_flip = false;
            // Advance round-robin and return cleanly — engine treats this
            // frame as rendered into a non-scannable target. Subsequent
            // endFrame calls take the render-only branch at line 915.
            sc.current_image = (sc.current_image + 1) % sc.image_count;
            return;
        }
        modeset_done = true;
        std.log.err(
            "vk_gbm_kms: drmModeSetCrtc OK on fb_id={d} mode={d}x{d}@{d}Hz (mode {d}/{d})",
            .{ sc.kms_fb_ids[idx],
               initial_mode.hdisplay, initial_mode.vdisplay, initial_mode.vrefresh,
               attempt + 1, limit });
    } else {
        // If a prior page-flip is still in flight, wait it out before queueing
        // another (drmModePageFlip would otherwise return EBUSY).
        while (pending_flip) {
            const r = c.drmHandleEvent(sc.drm_fd, &drm_event_ctx);
            if (r != 0) {
                std.log.err("vk_gbm_kms: drmHandleEvent (drain) ret={d} errno={d}", .{ r, std.c._errno().* });
                pending_flip = false;
                break;
            }
        }

        // Page-flip can return EBUSY for a few reasons on fairydust:
        //   - the previous modeset's first vblank hasn't landed yet;
        //   - the kernel still has a prior flip pending;
        //   - DCP has wedged at ControllerPowerState=0 after a disconnect
        //     cycle — see the comment at drivers/gpu/drm/apple/dcp.c:376.
        //     dcp_dptx_connect() resets the DPTX link but doesn't call
        //     dcp_poweron(), so the firmware refuses swap submissions
        //     until something drives drm_atomic_commit(active=1) — i.e.
        //     a real modeset — which re-enters apple_crtc_atomic_enable
        //     and calls dcp_poweron().
        //
        // Strategy: poll+retry a few times for the transient cases, and
        // if page-flip still won't take, fall back to drmModeSetCrtc
        // which DOES trip atomic_enable and kicks DCP back awake. That's
        // heavier than a page-flip (a full modeset ~tens of ms, may
        // cause a one-frame blank) but it's self-healing. Cap the retry
        // budget so we don't starve the event pump; after ~100 ms we'd
        // rather take the modeset hit and keep input flowing.
        const PAGEFLIP_RETRIES: u8 = 3;
        var flip_attempt: u8 = 0;
        var flipret: c_int = -1;
        while (flip_attempt < PAGEFLIP_RETRIES) : (flip_attempt += 1) {
            pending_flip = true;
            flipret = c.drmModePageFlip(
                sc.drm_fd,
                sc.crtc_id,
                sc.kms_fb_ids[idx],
                c.DRM_MODE_PAGE_FLIP_EVENT,
                @ptrCast(&pending_flip),
            );
            if (flipret == 0) break;
            pending_flip = false;
            const err = std.c._errno().*;
            // MAY-192: the dl_drm drmModePageFlip wrapper returns -errno as
            // its return value and leaves C errno at 0 (observed in the
            // wild: ret=-16 errno=0). EBUSY (16) is the DCP-wedge /
            // flip-pending transient that the retry + setCrtc-rearm below
            // is built to absorb — classify it from flipret too, not only
            // errno, or every EBUSY is misread as fatal and the DCP is
            // never re-armed (was producing 60+k spurious 'non-EBUSY error'
            // lines per minute under the wedge cycle).
            const is_ebusy = err == 16 or flipret == -16 or flipret == 16;
            if (!is_ebusy) { // genuinely fatal — skip retry and skip fallback
                std.log.err("vk_gbm_kms: drmModePageFlip non-EBUSY error: ret={d} errno={d}", .{ flipret, err });
                return error.PageFlipFailed;
            }
            var pfd = [_]std.posix.pollfd{.{ .fd = sc.drm_fd, .events = std.posix.POLL.IN, .revents = 0 }};
            _ = std.posix.poll(&pfd, 33) catch {};
            if ((pfd[0].revents & std.posix.POLL.IN) != 0) {
                _ = c.drmHandleEvent(sc.drm_fd, &drm_event_ctx);
            }
        }

        if (flipret != 0) {
            // EBUSY wedged. Force a setCrtc to re-power DCP and put the
            // new fb into scan-out atomically. Logs at .err because it's
            // rare and worth seeing if it fires frequently (suggests a
            // DCP path we haven't fixed).
            var con_arr: [1]u32 = .{sc.connector_id};
            const setret = c.drmModeSetCrtc(
                sc.drm_fd,
                sc.crtc_id,
                sc.kms_fb_ids[idx],
                0, 0,
                &con_arr[0],
                1,
                &initial_mode,
            );
            if (setret != 0) {
                std.log.err("vk_gbm_kms: EBUSY→setCrtc fallback failed: ret={d} errno={d}", .{ setret, std.c._errno().* });
                return error.PageFlipExhausted;
            }
            std.log.err("vk_gbm_kms: EBUSY→setCrtc fallback OK on fb_id={d} (DCP re-armed)", .{sc.kms_fb_ids[idx]});
            pending_flip = false;
            // fall through to current_image advance
        } else {
            // Page-flip accepted — block for vblank so we pace at the
            // display's refresh rate and the kernel's per-CRTC "one
            // flip pending" doesn't EBUSY us on the NEXT frame. The
            // pageFlipHandler clears `pending_flip` when the event fires.
            while (pending_flip) {
                const r = c.drmHandleEvent(sc.drm_fd, &drm_event_ctx);
                if (r != 0) {
                    std.log.err("vk_gbm_kms: drmHandleEvent (wait) ret={d} errno={d}", .{ r, std.c._errno().* });
                    pending_flip = false;
                    break;
                }
            }
        }
    }

    // Round-robin to the next image for the upcoming frame.
    sc.current_image = (sc.current_image + 1) % sc.image_count;
}

/// Stash the picked mode + connector_id for the modeset on first endFrame.
/// Called from initGbmKms after createSwapchain, before the first synchDisplay.
pub fn primeForModeset(acquired: *const Acquired) void {
    initial_mode = acquired.pick.mode;
    initial_connector_id = acquired.pick.connector_id;
    n_fallback_modes = acquired.pick.n_fallback_modes;
    var i: usize = 0;
    while (i < n_fallback_modes) : (i += 1) {
        fallback_modes[i] = acquired.pick.fallback_modes[i];
    }
    modeset_done = false;
    pending_flip = false;
}

/// Hotplug → headful promotion. Called from synchDisplay when
/// platform_device_poll() reports DISPLAY_CONNECTOR_STATE and the current
/// swapchain is render-only (sc.drm_fd < 0). Re-runs the card probe; if a
/// connector is now available, takes DRM master on its card, registers
/// every existing VkImage's DMA-BUF as a KMS framebuffer (the steps that
/// were skipped at boot in render-only mode), and seeds modeset_done=false
/// so the next endFrame does the first drmModeSetCrtc.
///
/// Returns true on successful promotion; caller should then emit
/// EVENT_VIDEO_DISPLAY_RESET so the engine relays out.
///
/// Notes:
///   * Best-effort — if the new mode differs from the current swapchain
///     extent (placeholder 1280x720 vs whatever the connector advertises),
///     the engine will letterbox until something else triggers a full
///     swapchain rebuild. Acceptable trade for not having to re-allocate
///     all the rendertargets here.
///   * No "headless" platform involved — same vk_gbm_kms code path,
///     branches that were "off because environment had no connector" now
///     turn on.
pub fn tryPromoteToHeadful(env: *agp_vk.VkEnv, acquired: *Acquired, sc: *Swapchain) bool {
    if (acquired.disp_fd >= 0) return false; // already headful

    var cards: [MAX_CARDS]CardInfo = .{ .{}, .{}, .{}, .{} };
    var i: u8 = 0;
    while (i < MAX_CARDS) : (i += 1) {
        var path_buf: [32]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, "/dev/dri/card{d}", .{i}) catch continue;
        const O_RDWR: c_int = 2;
        const O_CLOEXEC: c_int = 0o2000000;
        const fd = platform_device_open(path.ptr, O_RDWR | O_CLOEXEC);
        if (fd < 0) continue;
        cards[i].fd = fd;
        probeKms(&cards[i]);
        cards[i].has_render_node = cardHasRenderNode(i);
    }

    // Pick a card with KMS for display. Prefer one that's also our render
    // card (acquired.draw_fd points to the existing render-only card).
    var disp_idx: i8 = -1;
    for (0..MAX_CARDS) |idx| {
        if (cards[idx].has_kms) {
            disp_idx = @intCast(idx);
            break;
        }
    }
    if (disp_idx == -1) {
        // No KMS yet — close everything and stay render-only.
        for (0..MAX_CARDS) |idx| {
            if (cards[idx].fd >= 0) std.posix.close(cards[idx].fd);
        }
        return false;
    }

    const new_disp_fd = cards[@intCast(disp_idx)].fd;

    // Close the cards we don't need (every fd that isn't the new disp).
    for (0..MAX_CARDS) |idx| {
        if (cards[idx].fd >= 0 and cards[idx].fd != new_disp_fd) {
            std.posix.close(cards[idx].fd);
        }
    }

    const pick = selectConnector(new_disp_fd) orelse {
        std.log.warn("vk_gbm_kms: tryPromoteToHeadful — connector probe failed; staying render-only", .{});
        std.posix.close(new_disp_fd);
        return false;
    };

    std.log.warn(
        "vk_gbm_kms: HOTPLUG promote — connector_id={d} crtc_id={d} mode={d}x{d}@{d}Hz",
        .{ pick.connector_id, pick.crtc_id, pick.mode.hdisplay, pick.mode.vdisplay, pick.mode.vrefresh },
    );

    // MAY-200: DCP rejects drmModeSetCrtc with -ENOSPC when the bound FB's
    // dimensions don't match the connector's mode. If the render-only
    // placeholder (1280x720) doesn't match the picked headful mode (e.g.
    // 4096x2160), tear down sc and rebuild at the connector dimensions
    // so createSwapchain's step 6+7 registers KMS FBs at the right size.
    const need_resize = pick.mode.hdisplay != sc.extent.width or pick.mode.vdisplay != sc.extent.height;

    if (need_resize) {
        // Wire acquired.disp_fd BEFORE createSwapchain so the new
        // swapchain self-registers KMS FBs (createSwapchain checks
        // acquired.disp_fd >= 0 internally; see lines 709-739).
        acquired.disp_fd = new_disp_fd;
        acquired.pick = pick;

        destroySwapchain(env, sc);

        sc.* = createSwapchain(env, acquired, pick.mode.hdisplay, pick.mode.vdisplay) catch |err| {
            std.log.err(
                "vk_gbm_kms: tryPromoteToHeadful — createSwapchain at {d}x{d} failed: {s}; staying render-only",
                .{ pick.mode.hdisplay, pick.mode.vdisplay, @errorName(err) },
            );
            std.posix.close(new_disp_fd);
            acquired.disp_fd = -1;
            return false;
        };

        initial_mode = pick.mode;
        initial_connector_id = pick.connector_id;
        n_fallback_modes = pick.n_fallback_modes;
        var fmi: usize = 0;
        while (fmi < n_fallback_modes) : (fmi += 1) {
            fallback_modes[fmi] = pick.fallback_modes[fmi];
        }
        modeset_done = false;
        pending_flip = false;
        return true;
    }

    // dims-match fast path: register each existing VkImage's exported
    // DMA-BUF fd as a KMS framebuffer on the new disp_fd. Mirrors
    // createSwapchain's step 6 + 7.
    var idx: u32 = 0;
    while (idx < sc.image_count) : (idx += 1) {
        const fd = sc.dmabuf_fds[idx];
        if (fd < 0) continue;

        var drm_handle: u32 = 0;
        const prime_ret = c.drmPrimeFDToHandle(new_disp_fd, fd, &drm_handle);
        if (prime_ret != 0) {
            std.log.err("vk_gbm_kms: tryPromoteToHeadful drmPrimeFDToHandle[{d}] ret={d} errno={d}", .{ idx, prime_ret, std.c._errno().* });
            std.posix.close(new_disp_fd);
            return false;
        }

        // Pitch / offset come from the VkImage subresource layout. We don't
        // re-query them here — we trust the original createSwapchain values
        // since the underlying VkImage didn't change. drmModeAddFB2 with
        // pitch=extent.width*4 (LINEAR XRGB8888) is correct for our format.
        const pitch: u32 = sc.extent.width * 4;
        var handles: [4]u32 = .{ drm_handle, 0, 0, 0 };
        var pitches: [4]u32 = .{ pitch, 0, 0, 0 };
        var offsets: [4]u32 = .{ 0, 0, 0, 0 };
        var fb_id: u32 = 0;
        const addfb_ret = c.drmModeAddFB2(
            new_disp_fd,
            sc.extent.width,
            sc.extent.height,
            DRM_FORMAT_XRGB2101010,
            &handles,
            &pitches,
            &offsets,
            &fb_id,
            0,
        );
        if (addfb_ret != 0 or fb_id == 0) {
            std.log.err("vk_gbm_kms: tryPromoteToHeadful drmModeAddFB2[{d}] ret={d} errno={d}", .{ idx, addfb_ret, std.c._errno().* });
            std.posix.close(new_disp_fd);
            return false;
        }
        sc.kms_fb_ids[idx] = fb_id;
    }

    // Wire the new state. modeset_done=false so endFrame's first call does
    // drmModeSetCrtc (and saves the prior CRTC for restore on shutdown).
    acquired.disp_fd = new_disp_fd;
    acquired.pick = pick;
    sc.drm_fd = new_disp_fd;
    sc.connector_id = pick.connector_id;
    sc.crtc_id = pick.crtc_id;
    initial_mode = pick.mode;
    initial_connector_id = pick.connector_id;
    n_fallback_modes = pick.n_fallback_modes;
    {
        var fmi: usize = 0;
        while (fmi < n_fallback_modes) : (fmi += 1) {
            fallback_modes[fmi] = pick.fallback_modes[fmi];
        }
    }
    modeset_done = false;
    pending_flip = false;
    return true;
}

pub fn destroySwapchain(env: *agp_vk.VkEnv, sc: *Swapchain) void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    // Step 5: clean CRTC teardown
    //
    // Disable the CRTC BEFORE we tear down the KMS framebuffers it's
    // currently scanning. drmModeSetCrtc with fb_id=0 triggers
    // apple_crtc_atomic_disable() → dcp_poweroff() which drives DCP's
    // ControllerPowerState back to 0 through the firmware's proper
    // shutdown path. Skipping it leaves DCP half-alive: RmFB releases
    // the scanout buffer out from under an active scanout, and the next
    // arcan session reconnects into a DCP that refuses swap submissions
    // with "swap_submit_dcp: swallowed swap … as fControllerPowerState
    // is 0" and "flip_done timed out" errors. See the fairydust
    // comment at drivers/gpu/drm/apple/dcp.c:376 — dcp_dptx_connect
    // resets the DPTX link on reconnect but does not re-call
    // dcp_poweron(), so after a wedge only a fresh atomic_enable (i.e.
    // a real modeset) recovers. Avoid the wedge in the first place by
    // shutting the CRTC down cleanly on exit.
    if (sc.drm_fd >= 0 and sc.crtc_id != 0 and modeset_done) {
        const disret = c.drmModeSetCrtc(sc.drm_fd, sc.crtc_id, 0, 0, 0, null, 0, null);
        if (disret != 0) {
            std.log.err("vk_gbm_kms: CRTC disable ret={d} errno={d} (non-fatal)", .{ disret, std.c._errno().* });
        } else {
            std.log.err("vk_gbm_kms: CRTC {d} disabled", .{sc.crtc_id});
        }
        modeset_done = false;
        pending_flip = false;
    }

    // Restore the pre-modeset CRTC state if one was captured on the very
    // first endFrame. For a fresh-boot arcan session the "prior" state
    // is typically iBoot's framebuffer; if nothing was captured (e.g.
    // we crashed before the first endFrame), skip.
    if (sc.saved_crtc) |saved_opaque| {
        const saved: *c.drmModeCrtc = @ptrCast(@alignCast(saved_opaque));
        if (saved.*.mode_valid != 0 and saved.*.buffer_id != 0) {
            var con_arr: [1]u32 = .{sc.connector_id};
            const rret = c.drmModeSetCrtc(
                sc.drm_fd,
                saved.*.crtc_id,
                saved.*.buffer_id,
                saved.*.x,
                saved.*.y,
                &con_arr[0],
                1,
                &saved.*.mode,
            );
            if (rret != 0) {
                std.log.err("vk_gbm_kms: saved-CRTC restore ret={d} errno={d}", .{ rret, std.c._errno().* });
            }
        }
        c.drmModeFreeCrtc(saved);
        sc.saved_crtc = null;
    }

    var i: u32 = 0;
    while (i < N_BUFFERS) : (i += 1) {
        if (sc.kms_fb_ids[i] != 0 and sc.drm_fd >= 0) {
            _ = c.drmModeRmFB(sc.drm_fd, sc.kms_fb_ids[i]);
            sc.kms_fb_ids[i] = 0;
        }
        if (sc.views[i] != .null_handle) {
            env.vkd.destroyImageView(env.device, sc.views[i], null);
            sc.views[i] = .null_handle;
        }
        if (sc.images[i] != .null_handle) {
            env.vkd.destroyImage(env.device, sc.images[i], null);
            sc.images[i] = .null_handle;
        }
        if (sc.memory[i] != .null_handle) {
            env.vkd.freeMemory(env.device, sc.memory[i], null);
            sc.memory[i] = .null_handle;
        }
        // dmabuf fd is owned by Vulkan (passed via getMemoryFdKHR — caller-owned
        // per spec). Close defensively only if vk import never claimed it.
        // For now we never explicitly close — Vulkan freeMemory above releases.
        sc.dmabuf_fds[i] = -1;
    }
    sc.image_count = 0;

    if (sc.present_fence != .null_handle) {
        env.vkd.destroyFence(env.device, sc.present_fence, null);
        sc.present_fence = .null_handle;
    }

    // Release DRM master explicitly. close() would do it implicitly but
    // an explicit drop gives a legible dmesg trail.
    if (sc.drm_fd >= 0) {
        _ = c.drmDropMaster(sc.drm_fd);
        std.log.err("vk_gbm_kms: destroySwapchain — CRTC disabled, master dropped", .{});
    }
}

// MAY-201: set the DPMS connector property. dpms_value follows the
// kernel/X11 convention (0=on, 1=standby, 2=suspend, 3=off); the
// caller (platform_video_dpms) maps arcan's ADPMS_* constants onto
// the same range. Returns true on success.
//
// DPMS is a connector property, not a CRTC one — we look it up by
// name on the swapchain's connector and write the new value via
// drmModeConnectorSetProperty. Most TVs honor DPMS_ON to mean
// "don't sleep on signal-stays-active heuristic"; cheap TVs ignore
// it once they've decided to standby. Combine with the TV's own
// auto-off menu.
pub fn setDpms(sc: *const Swapchain, dpms_value: u32) bool {
    if (sc.drm_fd < 0 or sc.connector_id == 0) return false;

    const props = c.drmModeObjectGetProperties(
        sc.drm_fd,
        sc.connector_id,
        c.DRM_MODE_OBJECT_CONNECTOR,
    ) orelse {
        std.log.err("vk_gbm_kms: setDpms — drmModeObjectGetProperties failed errno={d}", .{std.c._errno().*});
        return false;
    };
    defer c.drmModeFreeObjectProperties(props);

    var i: u32 = 0;
    while (i < props.*.count_props) : (i += 1) {
        const prop = c.drmModeGetProperty(sc.drm_fd, props.*.props[i]) orelse continue;
        defer c.drmModeFreeProperty(prop);

        // prop.*.name is a fixed-size [32]u8 — match exactly "DPMS\0".
        const name = &prop.*.name;
        if (name[0] != 'D' or name[1] != 'P' or name[2] != 'M' or name[3] != 'S' or name[4] != 0) continue;

        const setret = c.drmModeConnectorSetProperty(
            sc.drm_fd,
            sc.connector_id,
            prop.*.prop_id,
            @intCast(dpms_value),
        );
        if (setret != 0) {
            std.log.err(
                "vk_gbm_kms: setDpms — drmModeConnectorSetProperty(conn={d}, prop={d}, val={d}) ret={d} errno={d}",
                .{ sc.connector_id, prop.*.prop_id, dpms_value, setret, std.c._errno().* },
            );
            return false;
        }
        std.log.err("vk_gbm_kms: DPMS set to {d} on connector {d}", .{ dpms_value, sc.connector_id });
        return true;
    }

    std.log.err("vk_gbm_kms: setDpms — DPMS property not found on connector {d}", .{sc.connector_id});
    return false;
}
