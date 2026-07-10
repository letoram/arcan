// may/arcan Vulkan → a real window on macOS (VK_EXT_metal_surface / MoltenVK),
// now drawing through the ENGINE's own pipeline: initPhase2 builds the engine's
// shaders/pipelines, and each frame we bind basic_2d + the default-white-texture
// descriptor and issue vk_env_draw_quad (the engine's quad draw) into the
// swapchain image via dynamic rendering. A white quad on a pulsing background =
// arcan's render pipeline producing window content (not a manual clear).

const std = @import("std");
const agpvk = @import("agpvk");
const vk = @import("vulkan");

export fn slug_atlas_iter_sdf() callconv(.c) void {} // unused debug-font path

extern fn soma_window_create(w: c_int, h: c_int, title: [*:0]const u8) ?*anyopaque;
extern fn soma_window_poll() bool;

// The engine's quad draw (export fn in vk.zig); records into env.cmd, assuming a
// pipeline + descriptor are bound and a render pass is active.
extern fn vk_env_draw_quad(verts: ?[*]const f32, n_floats: u32) void;

// macOS libc spells the stderr global `__stderrp`; vk.zig's debug fprintf uses `stderr`.
extern "c" var __stderrp: *anyopaque;
export var stderr: *anyopaque = undefined;

const ident16 = [16]f32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 };
// 6 verts (triangle list), 4 floats each: pos.xy (NDC) + uv.xy
const quad = [24]f32{
    -0.5, -0.5, 0, 0,  0.5, -0.5, 1, 0,  -0.5, 0.5, 0, 1,
    0.5,  -0.5, 1, 0,  0.5, 0.5,  1, 1,  -0.5, 0.5, 0, 1,
};

pub fn main() !void {
    stderr = __stderrp;
    const W: u32 = 800;
    const H: u32 = 600;
    std.debug.print("== may/arcan ENGINE-DRAW window on macOS (MoltenVK) ==\n", .{});

    const env = try agpvk.init(&.{ "VK_KHR_surface", "VK_EXT_metal_surface" });
    const layer = soma_window_create(@intCast(W), @intCast(H), "may/arcan - engine draw") orelse return error.WindowFailed;
    const surface = try env.vki.createMetalSurfaceEXT(env.instance, &.{ .p_layer = @ptrCast(layer) }, null);

    const caps = try env.vki.getPhysicalDeviceSurfaceCapabilitiesKHR(env.physical_device, surface);
    var min_images: u32 = caps.min_image_count + 1;
    if (caps.max_image_count > 0 and min_images > caps.max_image_count) min_images = caps.max_image_count;

    const swapchain = try env.vkd.createSwapchainKHR(env.device, &.{
        .surface = surface,
        .min_image_count = min_images,
        .image_format = .b8g8r8a8_unorm,
        .image_color_space = .srgb_nonlinear_khr,
        .image_extent = .{ .width = W, .height = H },
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .image_sharing_mode = .exclusive,
        .pre_transform = caps.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = .fifo_khr,
        .clipped = .true,
    }, null);

    var n: u32 = 0;
    _ = try env.vkd.getSwapchainImagesKHR(env.device, swapchain, &n, null);
    var images: [8]vk.Image = undefined;
    if (n > images.len) n = images.len;
    _ = try env.vkd.getSwapchainImagesKHR(env.device, swapchain, &n, &images);

    var views: [8]vk.ImageView = undefined;
    {
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            views[i] = try env.vkd.createImageView(env.device, &.{
                .image = images[i],
                .view_type = .@"2d",
                .format = .b8g8r8a8_unorm,
                .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
                .subresource_range = .{ .aspect_mask = .{ .color_bit = true }, .base_mip_level = 0, .level_count = 1, .base_array_layer = 0, .layer_count = 1 },
            }, null);
        }
    }
    std.debug.print("surface + swapchain ({d} imgs) OK\n", .{n});

    agpvk.initPhase2(env, .b8g8r8a8_unorm) catch |e| {
        std.debug.print("initPhase2 FAILED: {s}\n", .{@errorName(e)});
        return e;
    };
    std.debug.print("initPhase2 OK -- drawing via engine pipeline\n", .{});

    // Engine draw state (read by vk_env_draw_quad)
    env.push_constants = .{ .projection = ident16, .modelview = ident16, .texturem = ident16, .opacity = 1.0 };
    env.swapchain_extent_w = W;
    env.swapchain_extent_h = H;
    env.rt_rendering = false;
    env.rt_viewport = .{ 0, 0, 0, 0 };
    env.color_write_enabled = true;
    env.blend_mode = 1;
    env.rendering_active = true;

    const range = vk.ImageSubresourceRange{ .aspect_mask = .{ .color_bit = true }, .base_mip_level = 0, .level_count = 1, .base_array_layer = 0, .layer_count = 1 };

    var frame: u32 = 0;
    while (soma_window_poll()) {
        const acq = env.vkd.acquireNextImageKHR(env.device, swapchain, std.math.maxInt(u64), env.image_available, .null_handle) catch break;
        const idx = acq.image_index;

        try env.vkd.beginCommandBuffer(env.cmd, &.{ .flags = .{ .one_time_submit_bit = true } });

        const to_color = vk.ImageMemoryBarrier{
            .src_access_mask = .{},
            .dst_access_mask = .{ .color_attachment_write_bit = true },
            .old_layout = .undefined,
            .new_layout = .color_attachment_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = images[idx],
            .subresource_range = range,
        };
        env.vkd.cmdPipelineBarrier(env.cmd, .{ .top_of_pipe_bit = true }, .{ .color_attachment_output_bit = true }, .{}, 0, null, 0, null, 1, @ptrCast(&to_color));

        const ph: f32 = @as(f32, @floatFromInt(frame % 240)) / 240.0;
        const s = 0.25 + 0.2 * @sin(ph * 6.2831853);
        env.vkd.cmdBeginRendering(env.cmd, &.{
            .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = W, .height = H } },
            .layer_count = 1,
            .view_mask = 0,
            .color_attachment_count = 1,
            .p_color_attachments = &[_]vk.RenderingAttachmentInfo{.{
                .image_view = views[idx],
                .image_layout = .color_attachment_optimal,
                .resolve_mode = .{},
                .resolve_image_layout = .undefined,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .color = .{ .float_32 = .{ 0.1, s, 0.3, 1.0 } } },
            }},
        });

        // Bind the engine's textured pipeline + the default white texture, then draw.
        env.vkd.cmdBindPipeline(env.cmd, .graphics, env.basic_2d_pipeline);
        const zoff = [_]u32{0};
        env.vkd.cmdBindDescriptorSets(env.cmd, .graphics, env.pipeline_layout, 0, 1, @ptrCast(&env.textures[0].descriptor_set), 1, &zoff);

        env.vertex_offset = 0;
        vk_env_draw_quad(&quad, 24);

        env.vkd.cmdEndRendering(env.cmd);

        const to_present = vk.ImageMemoryBarrier{
            .src_access_mask = .{ .color_attachment_write_bit = true },
            .dst_access_mask = .{},
            .old_layout = .color_attachment_optimal,
            .new_layout = .present_src_khr,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = images[idx],
            .subresource_range = range,
        };
        env.vkd.cmdPipelineBarrier(env.cmd, .{ .color_attachment_output_bit = true }, .{ .bottom_of_pipe_bit = true }, .{}, 0, null, 0, null, 1, @ptrCast(&to_present));

        try env.vkd.endCommandBuffer(env.cmd);

        const wait_stage = vk.PipelineStageFlags{ .color_attachment_output_bit = true };
        const submit = vk.SubmitInfo{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&env.image_available),
            .p_wait_dst_stage_mask = @ptrCast(&wait_stage),
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&env.cmd),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(&env.render_finished),
        };
        try env.vkd.queueSubmit(env.graphics_queue, 1, @ptrCast(&submit), env.frame_fence);

        _ = env.vkd.queuePresentKHR(env.graphics_queue, &.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&env.render_finished),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&swapchain),
            .p_image_indices = @ptrCast(&idx),
        }) catch {};

        _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.frame_fence), .true, std.math.maxInt(u64)) catch {};
        try env.vkd.resetFences(env.device, 1, @ptrCast(&env.frame_fence));
        try env.vkd.resetCommandBuffer(env.cmd, .{});

        frame += 1;
        if (frame >= 900) break;
    }
    _ = env.vkd.deviceWaitIdle(env.device) catch {};
    std.debug.print("window closed after {d} frames\n", .{frame});
}
