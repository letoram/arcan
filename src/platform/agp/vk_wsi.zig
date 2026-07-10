// AGP Vulkan 1.4 Backend — WSI Layer (VK_KHR_display)
// Handles display enumeration, surface creation, swapchain, frame acquire/present.
// No DRM/KMS/GBM needed — Vulkan driver handles modesetting internally.

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const agp_vk = @import("vk.zig");

pub const std_options: std.Options = .{ .log_level = .warn };

const use_zig_dlopen = (builtin.link_mode == .static and (builtin.abi == .musl or !builtin.link_libc));
extern fn zig_foreign_begin() callconv(.c) void;
extern fn zig_foreign_end() callconv(.c) void;

pub const DisplayInfo = struct {
    display: vk.DisplayKHR,
    name: [256]u8 = std.mem.zeroes([256]u8),
    name_len: usize = 0,
    physical_width: u32 = 0,
    physical_height: u32 = 0,
    modes: [32]vk.DisplayModePropertiesKHR = undefined,
    mode_count: u32 = 0,
    plane_index: u32 = 0,
};

pub const Swapchain = struct {
    handle: vk.SwapchainKHR = .null_handle,
    surface: vk.SurfaceKHR = .null_handle,
    format: vk.Format = .b8g8r8a8_unorm,
    extent: vk.Extent2D = .{ .width = 0, .height = 0 },
    images: [4]vk.Image = std.mem.zeroes([4]vk.Image),
    views: [4]vk.ImageView = std.mem.zeroes([4]vk.ImageView),
    image_count: u32 = 0,
    current_image: u32 = 0,
};

pub fn enumerateDisplays(
    vki: vk.InstanceWrapper,
    physical_device: vk.PhysicalDevice,
    out: []DisplayInfo,
) !u32 {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    var display_count: u32 = 0;
    _ = vki.getPhysicalDeviceDisplayPropertiesKHR(physical_device, &display_count, null) catch
        return error.DisplayEnumFailed;
    if (display_count == 0) return 0;

    var props: [8]vk.DisplayPropertiesKHR = undefined;
    if (display_count > 8) display_count = 8;
    _ = vki.getPhysicalDeviceDisplayPropertiesKHR(physical_device, &display_count, &props) catch
        return error.DisplayEnumFailed;

    // Get display plane properties to find a usable plane
    var plane_count: u32 = 0;
    _ = vki.getPhysicalDeviceDisplayPlanePropertiesKHR(physical_device, &plane_count, null) catch
        return error.DisplayEnumFailed;

    var result_count: u32 = 0;
    for (0..display_count) |i| {
        if (result_count >= out.len) break;
        var info = DisplayInfo{
            .display = props[i].display,
            .physical_width = props[i].physical_resolution.width,
            .physical_height = props[i].physical_resolution.height,
        };

        // Copy display name
        {
            const name = std.mem.span(props[i].display_name);
            const copy_len = @min(name.len, info.name.len - 1);
            @memcpy(info.name[0..copy_len], name[0..copy_len]);
            info.name_len = copy_len;
        }

        // Get modes for this display
        var mode_count: u32 = 0;
        _ = vki.getDisplayModePropertiesKHR(physical_device, props[i].display, &mode_count, null) catch continue;
        if (mode_count > 32) mode_count = 32;
        _ = vki.getDisplayModePropertiesKHR(physical_device, props[i].display, &mode_count, &info.modes) catch continue;
        info.mode_count = mode_count;

        // Assign a plane (simple: use plane i if available)
        info.plane_index = @intCast(@min(i, if (plane_count > 0) plane_count - 1 else 0));

        out[result_count] = info;
        result_count += 1;
    }

    return result_count;
}

pub const DrmDisplayResult = struct {
    count: u32,
    drm_fd: std.posix.fd_t,
};

/// Acquire displays from a separate DRM device via VK_EXT_acquire_drm_display.
/// Used on Apple Silicon where GPU (card1/asahi) and display controller (card2/apple-drm)
/// are separate DRM devices. Returns the count of acquired displays and the DRM fd
/// (caller must keep fd open for the lifetime of the display surface).
pub fn acquireDrmDisplay(
    vki: vk.InstanceWrapper,
    physical_device: vk.PhysicalDevice,
    out: []DisplayInfo,
) !DrmDisplayResult {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    // Find the DRM card that has display connectors (not the GPU render card).
    // On Apple Silicon: card1=asahi (GPU), card2=apple-drm (display).
    var drm_fd: std.posix.fd_t = -1;
    var connector_ids: [8]u32 = undefined;
    var connector_count: u32 = 0;
    var display_card_idx: u8 = 0;

    var card_idx: u8 = 0;
    while (card_idx < 8) : (card_idx += 1) {
        // Check if this card has any connected connectors
        var found_connected = false;
        var local_ids: [8]u32 = undefined;
        var local_count: u32 = 0;

        var conn_scan: u8 = 0;
        while (conn_scan < 8) : (conn_scan += 1) {
            // Try common connector type names
            const connector_types = [_][]const u8{
                "HDMI-A-", "DP-", "eDP-", "VGA-", "DVI-D-", "DVI-I-",
            };
            for (connector_types) |ctype| {
                var status_buf: [128]u8 = undefined;
                const status_path = std.fmt.bufPrintZ(
                    &status_buf,
                    "/sys/class/drm/card{d}-{s}{d}/status",
                    .{ card_idx, ctype, conn_scan + 1 },
                ) catch continue;

                const status_file = std.fs.cwd().openFileZ(status_path, .{}) catch continue;
                defer status_file.close();
                var rbuf: [32]u8 = undefined;
                const n = status_file.read(&rbuf) catch continue;
                const status_str = std.mem.trimRight(u8, rbuf[0..n], "\n\r ");

                if (std.mem.eql(u8, status_str, "connected")) {
                    found_connected = true;
                    // Read connector_id
                    var id_path_buf: [128]u8 = undefined;
                    const id_path = std.fmt.bufPrintZ(
                        &id_path_buf,
                        "/sys/class/drm/card{d}-{s}{d}/connector_id",
                        .{ card_idx, ctype, conn_scan + 1 },
                    ) catch continue;

                    const id_file = std.fs.cwd().openFileZ(id_path, .{}) catch continue;
                    defer id_file.close();
                    var id_buf: [16]u8 = undefined;
                    const id_n = id_file.read(&id_buf) catch continue;
                    const id_str = std.mem.trimRight(u8, id_buf[0..id_n], "\n\r ");
                    const cid = std.fmt.parseInt(u32, id_str, 10) catch continue;

                    if (local_count < local_ids.len) {
                        local_ids[local_count] = cid;
                        local_count += 1;
                    }
                }
            }
        }

        if (found_connected and local_count > 0) {
            // Verify this is NOT the GPU render-only card by checking for a display driver
            var driver_buf: [128]u8 = undefined;
            const driver_path = std.fmt.bufPrintZ(
                &driver_buf,
                "/sys/class/drm/card{d}/device/driver",
                .{card_idx},
            ) catch continue;
            var link_buf: [128]u8 = undefined;
            const link = std.posix.readlinkZ(driver_path, &link_buf) catch continue;
            const driver_name = std.fs.path.basename(link);

            // Skip cards driven by the GPU compute driver (they have renderD* but no real display)
            if (std.mem.eql(u8, driver_name, "asahi") or
                std.mem.eql(u8, driver_name, "amdgpu") or
                std.mem.eql(u8, driver_name, "i915") or
                std.mem.eql(u8, driver_name, "xe") or
                std.mem.eql(u8, driver_name, "nouveau"))
            {
                // This is the GPU card — has connectors but they belong to the GPU driver.
                // On unified architectures this IS the display card. On split arch (Apple),
                // the display is on a separate card. Try to open it anyway as fallback below.
                continue;
            }

            // This card has connected display outputs and is NOT the GPU render card.
            var dev_path_buf: [32]u8 = undefined;
            const dev_path = std.fmt.bufPrintZ(&dev_path_buf, "/dev/dri/card{d}", .{card_idx}) catch continue;
            drm_fd = std.posix.openZ(dev_path, .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0) catch continue;
            @memcpy(connector_ids[0..local_count], local_ids[0..local_count]);
            connector_count = local_count;
            display_card_idx = card_idx;
            break;
        }
    }

    if (drm_fd < 0 or connector_count == 0) {
        std.log.err("vk: no DRM display card found with connected outputs", .{});
        return error.NoDrmDisplay;
    }

    std.log.info("vk: found display card /dev/dri/card{d} with {d} connected connector(s)", .{ display_card_idx, connector_count });

    // Also open the GPU render card — some drivers need the GPU's own DRM fd
    // for getDrmDisplayEXT rather than the display card's fd.
    var gpu_fd: std.posix.fd_t = -1;
    {
        var gi: u8 = 0;
        while (gi < 8) : (gi += 1) {
            if (gi == display_card_idx) continue;
            var gpath_buf: [32]u8 = undefined;
            const gpath = std.fmt.bufPrintZ(&gpath_buf, "/dev/dri/card{d}", .{gi}) catch continue;
            gpu_fd = std.posix.openZ(gpath, .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0) catch continue;
            std.log.info("vk: opened GPU card /dev/dri/card{d} (fd={d})", .{ gi, gpu_fd });
            break;
        }
    }

    // Use VK_EXT_acquire_drm_display to get VkDisplayKHR handles from connector IDs.
    // Try display card fd first, then GPU card fd — different drivers need different fds.
    var result_count: u32 = 0;
    for (0..connector_count) |i| {
        if (result_count >= out.len) break;
        const cid = connector_ids[i];

        // Try display card fd first, then GPU card fd
        const fds_to_try = [_]std.posix.fd_t{ drm_fd, gpu_fd };
        var acquired = false;

        for (fds_to_try) |try_fd| {
            if (try_fd < 0) continue;

            // Call vkGetDrmDisplayEXT directly to get the raw result code
            var out_display: vk.DisplayKHR = .null_handle;
            const raw_result: i32 = @intFromEnum(vki.dispatch.vkGetDrmDisplayEXT.?(
                physical_device,
                try_fd,
                cid,
                &out_display,
            ));
            if (raw_result != 0) {
                std.log.info("vk: vkGetDrmDisplayEXT(fd={d}, connector_id={d}) returned VkResult={d}", .{ try_fd, cid, raw_result });
                continue;
            }
            const display = out_display;

            vki.acquireDrmDisplayEXT(physical_device, try_fd, display) catch |e| {
                std.log.warn("vk: acquireDrmDisplayEXT(fd={d}, connector_id={d}) failed: {s}", .{ try_fd, cid, @errorName(e) });
                continue;
            };

            std.log.info("vk: acquired DRM display connector_id={d} via fd={d}", .{ cid, try_fd });
            acquired = true;

            var info = DisplayInfo{ .display = display };

            // Get modes for this display
            var mode_count: u32 = 0;
            _ = vki.getDisplayModePropertiesKHR(physical_device, display, &mode_count, null) catch {
                continue;
            };
            if (mode_count == 0) continue;
            if (mode_count > 32) mode_count = 32;
            _ = vki.getDisplayModePropertiesKHR(physical_device, display, &mode_count, &info.modes) catch continue;
            info.mode_count = mode_count;

            const name = std.fmt.bufPrint(&info.name, "DRM-connector-{d}", .{cid}) catch "DRM";
            info.name_len = name.len;

            var plane_count: u32 = 0;
            _ = vki.getPhysicalDeviceDisplayPlanePropertiesKHR(physical_device, &plane_count, null) catch {};
            info.plane_index = @intCast(@min(result_count, if (plane_count > 0) plane_count - 1 else 0));

            out[result_count] = info;
            result_count += 1;
            break;
        }

        if (!acquired) {
            std.log.err("vk: could not acquire display for connector_id={d} via any DRM fd", .{cid});
        }
    }

    if (result_count == 0) {
        std.posix.close(drm_fd);
        if (gpu_fd >= 0) std.posix.close(gpu_fd);
        std.log.err("vk: no displays acquired via VK_EXT_acquire_drm_display", .{});
        return error.NoDrmDisplayModes;
    }

    // Keep both fds open — Vulkan needs them for the display surface lifetime.
    // Return the display card fd; gpu_fd leaked intentionally (closed at shutdown).
    return .{ .count = result_count, .drm_fd = drm_fd };
}

pub fn createDisplaySurface(
    vki: vk.InstanceWrapper,
    instance: vk.Instance,
    mode: vk.DisplayModeKHR,
    extent: vk.Extent2D,
    plane_index: u32,
) !vk.SurfaceKHR {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const create_info = vk.DisplaySurfaceCreateInfoKHR{
        .display_mode = mode,
        .plane_index = plane_index,
        .plane_stack_index = 0,
        .transform = .{ .identity_bit_khr = true },
        .global_alpha = 1.0,
        .alpha_mode = .{ .opaque_bit_khr = true },
        .image_extent = extent,
    };

    return vki.createDisplayPlaneSurfaceKHR(instance, &create_info, null) catch
        return error.SurfaceCreateFailed;
}

pub fn createSwapchain(
    env: *agp_vk.VkEnv,
    surface: vk.SurfaceKHR,
    w: u32,
    h: u32,
) !Swapchain {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    // Query surface capabilities
    const caps = env.vki.getPhysicalDeviceSurfaceCapabilitiesKHR(
        env.physical_device,
        surface,
    ) catch return error.SurfaceCapsQueryFailed;

    // Pick format: prefer BGRA8 UNORM (avoids double gamma — GL uses UNORM everywhere)
    var format_count: u32 = 0;
    _ = env.vki.getPhysicalDeviceSurfaceFormatsKHR(
        env.physical_device,
        surface,
        &format_count,
        null,
    ) catch return error.SurfaceFormatQueryFailed;

    var formats: [16]vk.SurfaceFormatKHR = undefined;
    if (format_count > 16) format_count = 16;
    _ = env.vki.getPhysicalDeviceSurfaceFormatsKHR(
        env.physical_device,
        surface,
        &format_count,
        &formats,
    ) catch return error.SurfaceFormatQueryFailed;

    var chosen_format = vk.SurfaceFormatKHR{
        .format = .b8g8r8a8_unorm,
        .color_space = .srgb_nonlinear_khr,
    };
    for (formats[0..format_count]) |fmt| {
        if (fmt.format == .b8g8r8a8_unorm and fmt.color_space == .srgb_nonlinear_khr) {
            chosen_format = fmt;
            break;
        }
    }

    // Determine extent
    const extent = if (caps.current_extent.width != 0xFFFFFFFF)
        caps.current_extent
    else
        vk.Extent2D{
            .width = std.math.clamp(w, caps.min_image_extent.width, caps.max_image_extent.width),
            .height = std.math.clamp(h, caps.min_image_extent.height, caps.max_image_extent.height),
        };

    // Image count: prefer triple buffering
    var image_count = caps.min_image_count + 1;
    if (caps.max_image_count > 0 and image_count > caps.max_image_count) {
        image_count = caps.max_image_count;
    }
    if (image_count > 4) image_count = 4;

    const swapchain = env.vkd.createSwapchainKHR(env.device, &.{
        .surface = surface,
        .min_image_count = image_count,
        .image_format = chosen_format.format,
        .image_color_space = chosen_format.color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .image_sharing_mode = .exclusive,
        .pre_transform = caps.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = .fifo_khr,
        .clipped = .true,
    }, null) catch return error.SwapchainCreateFailed;

    // Get swapchain images
    var sc = Swapchain{
        .handle = swapchain,
        .surface = surface,
        .format = chosen_format.format,
        .extent = extent,
    };

    var actual_count: u32 = 0;
    _ = env.vkd.getSwapchainImagesKHR(env.device, swapchain, &actual_count, null) catch
        return error.SwapchainImagesFailed;
    if (actual_count > 4) actual_count = 4;
    _ = env.vkd.getSwapchainImagesKHR(env.device, swapchain, &actual_count, &sc.images) catch
        return error.SwapchainImagesFailed;
    sc.image_count = actual_count;

    // Create image views
    for (0..actual_count) |i| {
        sc.views[i] = env.vkd.createImageView(env.device, &.{
            .image = sc.images[i],
            .view_type = .@"2d",
            .format = chosen_format.format,
            .components = .{
                .r = .identity,
                .g = .identity,
                .b = .identity,
                .a = .identity,
            },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null) catch return error.ImageViewCreateFailed;
    }

    return sc;
}

pub fn destroySwapchain(env: *agp_vk.VkEnv, sc: *Swapchain) void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    env.vkd.deviceWaitIdle(env.device) catch {};

    for (0..sc.image_count) |i| {
        if (sc.views[i] != .null_handle)
            env.vkd.destroyImageView(env.device, sc.views[i], null);
    }
    if (sc.handle != .null_handle)
        env.vkd.destroySwapchainKHR(env.device, sc.handle, null);
    if (sc.surface != .null_handle)
        env.vki.destroySurfaceKHR(env.instance, sc.surface, null);
    sc.* = .{};
}

/// Destroy swapchain + views but keep the surface alive (for resize).
pub fn destroySwapchainOnly(env: *agp_vk.VkEnv, sc: *Swapchain) void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    env.vkd.deviceWaitIdle(env.device) catch {};

    for (0..sc.image_count) |i| {
        if (sc.views[i] != .null_handle)
            env.vkd.destroyImageView(env.device, sc.views[i], null);
    }
    if (sc.handle != .null_handle)
        env.vkd.destroySwapchainKHR(env.device, sc.handle, null);

    // Preserve surface — zero everything else
    const saved_surface = sc.surface;
    sc.* = .{};
    sc.surface = saved_surface;
}

pub fn beginFrame(env: *agp_vk.VkEnv, sc: *Swapchain, clear_color: [4]f32) !void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    // Fence wait + cmd buffer recording already started by vk_env_begin_frame_cmd().
    // Just acquire the swapchain image and begin the swapchain rendering pass.

    // Acquire next image
    const result = env.vkd.acquireNextImageKHR(
        env.device,
        sc.handle,
        std.math.maxInt(u64),
        env.image_available,
        .null_handle,
    ) catch return error.AcquireFailed;
    sc.current_image = result.image_index;

    // Transition image to color attachment
    const to_color = [_]vk.ImageMemoryBarrier2{.{
        .src_stage_mask = .{ .top_of_pipe_bit = true },
        .src_access_mask = .{},
        .dst_stage_mask = .{ .color_attachment_output_bit = true },
        .dst_access_mask = .{ .color_attachment_write_bit = true },
        .old_layout = .undefined,
        .new_layout = .color_attachment_optimal,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = sc.images[sc.current_image],
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

    // Begin dynamic rendering with clear
    const color_attachment = [_]vk.RenderingAttachmentInfo{.{
        .image_view = sc.views[sc.current_image],
        .image_layout = .color_attachment_optimal,
        .resolve_mode = .{},
        .resolve_image_layout = .undefined,
        .load_op = .clear,
        .store_op = .store,
        .clear_value = .{ .color = .{ .float_32 = clear_color } },
    }};
    env.vkd.cmdBeginRendering(env.cmd, &.{
        .render_area = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = sc.extent,
        },
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

pub fn endFrame(env: *agp_vk.VkEnv, sc: *Swapchain) !void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    // End rendering
    env.vkd.cmdEndRendering(env.cmd);

    // Transition to present
    const to_present = [_]vk.ImageMemoryBarrier2{.{
        .src_stage_mask = .{ .color_attachment_output_bit = true },
        .src_access_mask = .{ .color_attachment_write_bit = true },
        .dst_stage_mask = .{ .bottom_of_pipe_bit = true },
        .dst_access_mask = .{},
        .old_layout = .color_attachment_optimal,
        .new_layout = .present_src_khr,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = sc.images[sc.current_image],
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }};
    env.vkd.cmdPipelineBarrier2(env.cmd, &.{
        .image_memory_barrier_count = to_present.len,
        .p_image_memory_barriers = &to_present,
    });

    env.cmd_recording = false;
    env.vkd.endCommandBuffer(env.cmd) catch return error.CmdEndFailed;

    // Submit with synchronization2
    const wait_sem = [_]vk.SemaphoreSubmitInfo{.{
        .semaphore = env.image_available,
        .value = 0,
        .stage_mask = .{ .color_attachment_output_bit = true },
        .device_index = 0,
    }};
    const signal_sem = [_]vk.SemaphoreSubmitInfo{.{
        .semaphore = env.render_finished,
        .value = 0,
        .stage_mask = .{ .all_graphics_bit = true },
        .device_index = 0,
    }};
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{
        .command_buffer = env.cmd,
        .device_mask = 0,
    }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .wait_semaphore_info_count = wait_sem.len,
        .p_wait_semaphore_infos = &wait_sem,
        .command_buffer_info_count = cmd_info.len,
        .p_command_buffer_infos = &cmd_info,
        .signal_semaphore_info_count = signal_sem.len,
        .p_signal_semaphore_infos = &signal_sem,
    }}, env.frame_fence) catch return error.SubmitFailed;

    // Present
    _ = env.vkd.queuePresentKHR(env.graphics_queue, &.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&env.render_finished),
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&sc.handle),
        .p_image_indices = @ptrCast(&sc.current_image),
    }) catch return error.PresentFailed;

    // Track for agp_save_output readback
    env.last_presented_image = sc.images[sc.current_image];

    // Shift 10: check if GPU frame capture should trigger
    agp_vk.frameCaptureCheck(env);
}
