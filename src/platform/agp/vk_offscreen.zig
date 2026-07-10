// AGP Vulkan — Offscreen Render Target (LWA WSI replacement)
// Manages a VkImage + staging buffer for GPU→CPU readback instead of a swapchain.
// Used by the VK LWA platform to render offscreen and copy pixels to shmif.

const std = @import("std");
const vk = @import("vulkan");
const agp_vk = @import("vk.zig");
const builtin = @import("builtin");
const use_zig_dlopen = (builtin.link_mode == .static and (builtin.abi == .musl or !builtin.link_libc));
extern fn zig_foreign_begin() callconv(.c) void;
extern fn zig_foreign_end() callconv(.c) void;
inline fn tlsBegin() void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
}
inline fn tlsEnd() void {
    if (comptime use_zig_dlopen) zig_foreign_end();
}

pub const OffscreenTarget = struct {
    image: vk.Image = .null_handle,
    view: vk.ImageView = .null_handle,
    memory: vk.DeviceMemory = .null_handle,
    extent: vk.Extent2D = .{ .width = 0, .height = 0 },
    format: vk.Format = .b8g8r8a8_unorm,

    // GPU→CPU readback staging
    staging: vk.Buffer = .null_handle,
    staging_memory: vk.DeviceMemory = .null_handle,
    staging_mapped: ?[*]u8 = null,
    staging_size: usize = 0,
};

pub fn createOffscreen(env: *agp_vk.VkEnv, w: u32, h: u32) !OffscreenTarget {
    const format: vk.Format = .b8g8r8a8_unorm;
    // Create offscreen image
    const image = env.vkd.createImage(env.device, &.{
        .image_type = .@"2d",
        .format = format,
        .extent = .{ .width = w, .height = h, .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = .{
            .color_attachment_bit = true,
            .transfer_src_bit = true, // for readback to staging buffer
        },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    }, null) catch return error.ImageCreateFailed;

    // Allocate device-local memory for image
    const mem_reqs = env.vkd.getImageMemoryRequirements(env.device, image);
    const mem_type = findMemoryType(env, mem_reqs.memory_type_bits, .{
        .device_local_bit = true,
    }) orelse return error.NoSuitableMemory;

    const img_memory = env.vkd.allocateMemory(env.device, &.{
        .allocation_size = mem_reqs.size,
        .memory_type_index = mem_type,
    }, null) catch return error.MemoryAllocFailed;

    env.vkd.bindImageMemory(env.device, image, img_memory, 0) catch
        return error.BindMemoryFailed;

    // Create image view
    const view = env.vkd.createImageView(env.device, &.{
        .image = image,
        .view_type = .@"2d",
        .format = format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null) catch return error.ImageViewCreateFailed;

    // Create host-visible staging buffer for readback
    const pixel_size: usize = @as(usize, w) * @as(usize, h) * 4;
    const staging_size = pixel_size;

    const buf_info = vk.BufferCreateInfo{
        .size = staging_size,
        .usage = .{ .transfer_dst_bit = true },
        .sharing_mode = .exclusive,
    };
    const staging = env.vkd.createBuffer(env.device, &buf_info, null) catch
        return error.BufferCreateFailed;

    const buf_reqs = env.vkd.getBufferMemoryRequirements(env.device, staging);
    const buf_mem_type = findMemoryType(env, buf_reqs.memory_type_bits, .{
        .host_visible_bit = true,
        .host_coherent_bit = true,
    }) orelse return error.NoSuitableMemory;

    const staging_memory = env.vkd.allocateMemory(env.device, &.{
        .allocation_size = buf_reqs.size,
        .memory_type_index = buf_mem_type,
    }, null) catch return error.MemoryAllocFailed;

    env.vkd.bindBufferMemory(env.device, staging, staging_memory, 0) catch
        return error.BindMemoryFailed;

    // Persistently map staging buffer
    const mapped_ptr = env.vkd.mapMemory(env.device, staging_memory, 0, staging_size, .{}) catch
        return error.MapMemoryFailed;

    return OffscreenTarget{
        .image = image,
        .view = view,
        .memory = img_memory,
        .extent = .{ .width = w, .height = h },
        .format = format,
        .staging = staging,
        .staging_memory = staging_memory,
        .staging_mapped = @ptrCast(mapped_ptr),
        .staging_size = staging_size,
    };
}

/// Begin rendering to the offscreen image. Transitions layout and starts a render pass.
/// Must be called after vk_env_begin_frame_cmd().
pub fn beginFrame(env: *agp_vk.VkEnv, target: *OffscreenTarget, clear_color: [4]f32) !void {
    tlsBegin();
    defer tlsEnd();
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
        .image = target.image,
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
        .image_view = target.view,
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
            .extent = target.extent,
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

/// End rendering and copy image to staging buffer for CPU readback.
/// Submits command buffer with fence, then waits for completion.
pub fn endFrame(env: *agp_vk.VkEnv, target: *OffscreenTarget) !void {
    tlsBegin();
    defer tlsEnd();
    // End rendering
    env.vkd.cmdEndRendering(env.cmd);

    // Transition to transfer source
    const to_transfer = [_]vk.ImageMemoryBarrier2{.{
        .src_stage_mask = .{ .color_attachment_output_bit = true },
        .src_access_mask = .{ .color_attachment_write_bit = true },
        .dst_stage_mask = .{ .all_transfer_bit = true },
        .dst_access_mask = .{ .transfer_read_bit = true },
        .old_layout = .color_attachment_optimal,
        .new_layout = .transfer_src_optimal,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = target.image,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }};
    env.vkd.cmdPipelineBarrier2(env.cmd, &.{
        .image_memory_barrier_count = to_transfer.len,
        .p_image_memory_barriers = &to_transfer,
    });

    // Copy image to staging buffer.
    // Build BufferImageCopy via field-by-field assignment because the SH
    // backend miscompiles the outer-`.{}`-with-nested-`.{}` literal —
    // leaves the middle 28 bytes (image_subresource + image_offset)
    // uninitialized. See agp_vk.fullImageCopyRegion() and
    // memory/sh_vk_buffer_image_copy_init_miscompile.md.
    var region: [1]vk.BufferImageCopy = undefined;
    region[0].buffer_offset = 0;
    region[0].buffer_row_length = 0;
    region[0].buffer_image_height = 0;
    region[0].image_subresource.aspect_mask = .{ .color_bit = true };
    region[0].image_subresource.mip_level = 0;
    region[0].image_subresource.base_array_layer = 0;
    region[0].image_subresource.layer_count = 1;
    region[0].image_offset.x = 0;
    region[0].image_offset.y = 0;
    region[0].image_offset.z = 0;
    region[0].image_extent.width = target.extent.width;
    region[0].image_extent.height = target.extent.height;
    region[0].image_extent.depth = 1;
    env.vkd.cmdCopyImageToBuffer(
        env.cmd,
        target.image,
        .transfer_src_optimal,
        target.staging,
        region.len,
        &region,
    );

    env.vkd.endCommandBuffer(env.cmd) catch return error.CmdEndFailed;

    // Submit with fence (no semaphore wait — no swapchain acquire)
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{
        .command_buffer = env.cmd,
        .device_mask = 0,
    }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = cmd_info.len,
        .p_command_buffer_infos = &cmd_info,
    }}, env.frame_fence) catch return error.SubmitFailed;
}

/// Return pointer to the staging buffer's mapped memory (pixels ready after fence wait).
pub fn readPixels(target: *OffscreenTarget) ?[*]u8 {
    return target.staging_mapped;
}

/// Destroy and recreate with new dimensions.
pub fn resize(env: *agp_vk.VkEnv, target: *OffscreenTarget, w: u32, h: u32) !void {
    tlsBegin();
    defer tlsEnd();
    destroyOffscreen(env, target);
    target.* = try createOffscreen(env, w, h);
}

pub fn destroyOffscreen(env: *agp_vk.VkEnv, target: *OffscreenTarget) void {
    tlsBegin();
    defer tlsEnd();
    env.vkd.deviceWaitIdle(env.device) catch {};

    if (target.staging_mapped != null) {
        env.vkd.unmapMemory(env.device, target.staging_memory);
        target.staging_mapped = null;
    }
    if (target.staging != .null_handle) env.vkd.destroyBuffer(env.device, target.staging, null);
    if (target.staging_memory != .null_handle) env.vkd.freeMemory(env.device, target.staging_memory, null);
    if (target.view != .null_handle) env.vkd.destroyImageView(env.device, target.view, null);
    if (target.image != .null_handle) env.vkd.destroyImage(env.device, target.image, null);
    if (target.memory != .null_handle) env.vkd.freeMemory(env.device, target.memory, null);
    target.* = .{};
}

// Helpers

fn findMemoryType(env: *agp_vk.VkEnv, type_filter: u32, properties: vk.MemoryPropertyFlags) ?u32 {
    for (0..env.mem_props.memory_type_count) |i| {
        const idx: u5 = @intCast(i);
        if ((type_filter & (@as(u32, 1) << idx)) != 0) {
            const flags = env.mem_props.memory_types[i].property_flags;
            if ((@as(u32, @bitCast(flags)) & @as(u32, @bitCast(properties))) == @as(u32, @bitCast(properties))) {
                return @intCast(i);
            }
        }
    }
    return null;
}
