// AGP Vulkan 1.4 Backend — Core Module
// Provides VkEnv (instance, device, queues, sync, descriptors, pipeline layout)
// and exports all AGP init/env/ident functions.
// Phase 2: adds texture management, pipelines, vertex buffers, and bridge functions.

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const zig_dlopen = @import("dlopen");
const build_options = @import("build_options");

// Local cross-platform getenv (vk.zig has no shmif_types import). std.posix.getenv
// is a @compileError on windows; libc getenv works with ASCII names everywhere.
fn envSpan(name: [*:0]const u8) ?[:0]const u8 {
    const p = std.c.getenv(name) orelse return null;
    return std.mem.span(p);
}

fn rcdbg(comptime tag: []const u8) void {
    std.fs.File.stderr().writeAll("RCDBG:" ++ tag ++ "\n") catch {};
}

pub const std_options: std.Options = .{ .log_level = .warn };
// MAY-299: when the Vulkan ICD is statically linked into may
// (-Dstatic-vulkan), vkGetInstanceProcAddr is a same-binary defined symbol —
// no dlopen, and so the glibc-TLS foreign-call shim is unneeded.
const static_vulkan = build_options.static_vulkan;
const use_zig_dlopen = !static_vulkan and (builtin.link_mode == .static and (builtin.abi == .musl or !builtin.link_libc));
extern fn agp_shaderc_preload(handle: ?*anyopaque) callconv(.c) bool;
extern fn zig_foreign_begin() callconv(.c) void;
extern fn zig_foreign_end() callconv(.c) void;
extern fn vk_shared_get_screen_glid() u32;

// @cImport unavailable in the no-LLVM fork. Only three names from the
// original header soup were referenced in this file — see vk_cabi.zig.
const c = @import("vk_cabi.zig");

// Push Constants Layout
// NOTE: GLSL std430 aligns vec2 to 8 bytes, inserting padding before sz_input.
// The standard shaders (basic_2d, color_2d) were compiled with this padding,
// putting sz_output at offset 224. The slug shaders also use offset 224.
// We keep 248 bytes for the Zig struct (no padding) because the standard
// pipeline only reads up to opacity (offset 192) — the vec2 fields are only
// used by the slug pipeline which sets its own push constants.
pub const PushConstants = extern struct {
    modelview: [16]f32 = std.mem.zeroes([16]f32), // 64B, offset 0
    projection: [16]f32 = std.mem.zeroes([16]f32), // 64B, offset 64
    texturem: [16]f32 = std.mem.zeroes([16]f32), // 64B, offset 128
    opacity: f32 = 1.0, // offset 192
    trans_blend: f32 = 0.0, // offset 196
    trans_move: f32 = 0.0, // offset 200
    trans_rotate: f32 = 0.0, // offset 204
    trans_scale: f32 = 1.0, // offset 208
    sz_input: [2]f32 = .{ 0, 0 }, // offset 212
    sz_output: [2]f32 = .{ 0, 0 }, // offset 220
    sz_storage: [2]f32 = .{ 0, 0 }, // offset 228
    rtgt_id: i32 = 0, // offset 236
    fract_timestamp: f32 = 0.0, // offset 240
    timestamp: i32 = 0, // offset 244 (total: 248)
};

comptime {
    if (@sizeOf(PushConstants) != 248)
        @compileError("PushConstants must be exactly 248 bytes");
}

// Keep DynLib handle alive for glibc path
var stored_vk_lib: ?std.DynLib = null;

// Phase 2 Constants
const MAX_TEXTURES = 256;
const VERTEX_BUFFER_SIZE = 4 * 1024 * 1024; // 4MB — large enough to never wrap in one frame
const STAGING_BUFFER_SIZE = 64 * 1024 * 1024; // 64MB — covers 4K RGBA textures (3840x2400x4 = 37MB)

// Texture Slot
const TextureSlot = struct {
    image: vk.Image = .null_handle,
    view: vk.ImageView = .null_handle,
    memory: vk.DeviceMemory = .null_handle,
    descriptor_set: vk.DescriptorSet = .null_handle,
    width: u32 = 0,
    height: u32 = 0,
    in_use: bool = false,
    imported_dmabuf: bool = false,
    dmabuf_ino: u64 = 0, // inode of imported DMA-BUF fd (for same-buffer detection)
    rt_initialized: bool = false, // true after first use as render target (cleared on first pass)
};

// DMA-BUF resource cache entry (for triple-buffer reuse)
const DMABUF_CACHE_SIZE = 8;
const DmaBufCacheEntry = struct {
    ino: u64 = 0, // DMA-BUF inode (unique per buffer)
    slot_id: u32 = 0, // which TextureSlot this belongs to
    image: vk.Image = .null_handle,
    view: vk.ImageView = .null_handle,
    memory: vk.DeviceMemory = .null_handle,
    w: u32 = 0,
    h: u32 = 0,
};

// Deferred resource destruction — queued during rendering, flushed after frame fence.
const DeferredDestroy = struct {
    image: vk.Image = .null_handle,
    view: vk.ImageView = .null_handle,
    memory: vk.DeviceMemory = .null_handle,
    descriptor_set: vk.DescriptorSet = .null_handle,
};

// Vulkan Environment
// Uses the vulkan-zig Wrapper types which provide convenient method dispatch.
pub const VkEnv = struct {
    vkb: vk.BaseWrapper,
    vki: vk.InstanceWrapper,
    vkd: vk.DeviceWrapper,

    instance: vk.Instance,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    graphics_queue: vk.Queue,
    queue_family: u32,

    command_pool: vk.CommandPool,
    cmd: vk.CommandBuffer,

    image_available: vk.Semaphore,
    render_finished: vk.Semaphore,
    frame_fence: vk.Fence,

    pipeline_layout: vk.PipelineLayout,
    descriptor_set_layout: vk.DescriptorSetLayout,

    // EDS3 color-blend features present (missing on MoltenVK/KosmicKrisp —
    // there the pipeline bakes standard alpha blending statically and the
    // dynamic blend/write-mask calls are skipped)
    has_eds3_blend: bool = false,

    push_constants: PushConstants = .{},

    // Phase 2 resources
    basic_2d_pipeline: vk.Pipeline = .null_handle,
    color_2d_pipeline: vk.Pipeline = .null_handle,
    // Phase 4: UNORM pipeline variants for offscreen RT rendering
    basic_2d_pipeline_unorm: vk.Pipeline = .null_handle,
    color_2d_pipeline_unorm: vk.Pipeline = .null_handle,

    vert_shader_basic: vk.ShaderModule = .null_handle,
    frag_shader_basic: vk.ShaderModule = .null_handle,
    vert_shader_color: vk.ShaderModule = .null_handle,
    frag_shader_color: vk.ShaderModule = .null_handle,

    sampler_linear: vk.Sampler = .null_handle,
    sampler_nearest: vk.Sampler = .null_handle,

    descriptor_pool: vk.DescriptorPool = .null_handle,

    // Per-frame descriptor pool for custom shader draws.
    // Allocates a fresh descriptor set per draw to avoid updating a shared set
    // during command buffer recording (spec violation on tile-based GPUs: all
    // deferred draws in a render pass would see only the last texture written).
    frame_desc_pool: vk.DescriptorPool = .null_handle,

    vertex_buffer: vk.Buffer = .null_handle,
    vertex_memory: vk.DeviceMemory = .null_handle,
    vertex_mapped: ?[*]u8 = null,

    staging_buffer: vk.Buffer = .null_handle,
    staging_memory: vk.DeviceMemory = .null_handle,
    staging_mapped: ?[*]u8 = null,

    upload_cmd: vk.CommandBuffer = .null_handle,
    upload_fence: vk.Fence = .null_handle,

    // Async readback double-buffered staging
    readback_staging: [2]vk.Buffer = .{ .null_handle, .null_handle },
    readback_memory: [2]vk.DeviceMemory = .{ .null_handle, .null_handle },
    readback_mapped: [2]?[*]u8 = .{ null, null },
    readback_cmd: [2]vk.CommandBuffer = .{ .null_handle, .null_handle },
    readback_fence: [2]vk.Fence = .{ .null_handle, .null_handle },
    readback_pending: [2]bool = .{ false, false },
    readback_w: [2]u32 = .{ 0, 0 },
    readback_h: [2]u32 = .{ 0, 0 },
    readback_idx: u32 = 0, // current slot (ping-pong)

    // Dummy UBO for unused binding 1 in texture-only descriptor sets
    dummy_ubo_buffer: vk.Buffer = .null_handle,
    dummy_ubo_memory: vk.DeviceMemory = .null_handle,

    // Phase 4: rendertarget pass resources
    rt_fence: vk.Fence = .null_handle,
    rt_rendering: bool = false,
    rt_width: u32 = 0,
    rt_height: u32 = 0,
    rt_active_tex: u32 = 0,
    rt_viewport: [4]i32 = .{ 0, 0, 0, 0 }, // per-RT viewport/scissor: [x, y, w, h]

    // Per-RT alpha blend factors (GL glshared.c:1058-1075)
    // Default: GL_ONE / GL_ONE (additive alpha, !RENDERTARGET_RETAIN_ALPHA)
    blend_src_alpha: vk.BlendFactor = .one,
    blend_dst_alpha: vk.BlendFactor = .one,

    // Stencil resources (S8_UINT)
    stencil_image: vk.Image = .null_handle,
    stencil_view: vk.ImageView = .null_handle,
    stencil_memory: vk.DeviceMemory = .null_handle,
    stencil_active: bool = false,
    stencil_mode: enum { off, prepare, activated } = .off,

    // Depth resources (D32_SFLOAT) — for 3D pipeline
    depth_image: vk.Image = .null_handle,
    depth_view: vk.ImageView = .null_handle,
    depth_memory: vk.DeviceMemory = .null_handle,
    depth_active: bool = false, // true when PIPELINE_3D

    textures: [MAX_TEXTURES]TextureSlot = [_]TextureSlot{.{}} ** MAX_TEXTURES,
    next_texture_id: u32 = 1, // 0 = default white texture

    // DMA-BUF resource cache: avoids per-frame create+destroy for triple-buffered streams.
    // Gamescope cycles 3 DMA-BUF fds; we keep all 3 VkImage/view/memory alive and swap.
    dmabuf_cache: [DMABUF_CACHE_SIZE]DmaBufCacheEntry = [_]DmaBufCacheEntry{.{}} ** DMABUF_CACHE_SIZE,

    active_texture: u32 = 0,
    active_pipeline: u32 = 0,
    blend_mode: u32 = 0,
    color_write_enabled: bool = true,
    rendering_active: bool = false,
    cmd_recording: bool = false, // true when env.cmd is in recording state
    vertex_offset: u32 = 0,

    // Deferred destruction queue — flushed at start of next frame after fence
    deferred: [32]DeferredDestroy = [_]DeferredDestroy{.{}} ** 32,
    deferred_count: u32 = 0,

    // Deferred custom shader bind: params saved at agp_shader_activate,
    // actual descriptor set allocation + bind happens at draw time so that
    // env.active_texture reflects the correct vstore (set after activate).
    pending_custom_pipeline: u64 = 0,
    pending_custom_ubo_buf: u64 = 0,
    pending_custom_ubo_stride: u32 = 0,
    pending_custom_dyn_offset: u32 = 0,
    pending_custom_valid: bool = false,
    swapchain_format: vk.Format = .b8g8r8a8_unorm,
    swapchain_extent_w: u32 = 0,
    swapchain_extent_h: u32 = 0,
    // Set by WSI endFrame — enables agp_save_output to readback from swapchain
    last_presented_image: vk.Image = .null_handle,
    // Layout the last-presented image is left in. WSI leaves it .present_src_khr
    // (default); the GBM/KMS render-only path leaves it .general. agp_save_ppm /
    // agp_save_output read this so the readback barrier uses the correct old_layout.
    last_presented_layout: vk.ImageLayout = .present_src_khr,

    mem_props: vk.PhysicalDeviceMemoryProperties = undefined,

    // Keep DynLib alive so symbols remain resolved (glibc path only)
    _vk_lib: ?std.DynLib = null,

    fn deferDestroy(self: *VkEnv, img: vk.Image, view: vk.ImageView, mem: vk.DeviceMemory, desc: vk.DescriptorSet) void {
        if (self.deferred_count < self.deferred.len) {
            self.deferred[self.deferred_count] = .{ .image = img, .view = view, .memory = mem, .descriptor_set = desc };
            self.deferred_count += 1;
        } else {
            self.vkd.deviceWaitIdle(self.device) catch {};
            if (desc != .null_handle) self.vkd.freeDescriptorSets(self.device, self.descriptor_pool, 1, @ptrCast(&desc)) catch {};
            if (view != .null_handle) self.vkd.destroyImageView(self.device, view, null);
            if (img != .null_handle) self.vkd.destroyImage(self.device, img, null);
            if (mem != .null_handle) self.vkd.freeMemory(self.device, mem, null);
        }
    }

    fn flushDeferred(self: *VkEnv) void {
        for (self.deferred[0..self.deferred_count]) |dd| {
            if (dd.descriptor_set != .null_handle) self.vkd.freeDescriptorSets(self.device, self.descriptor_pool, 1, @ptrCast(&dd.descriptor_set)) catch {};
            if (dd.view != .null_handle) self.vkd.destroyImageView(self.device, dd.view, null);
            if (dd.image != .null_handle) self.vkd.destroyImage(self.device, dd.image, null);
            if (dd.memory != .null_handle) self.vkd.freeMemory(self.device, dd.memory, null);
        }
        self.deferred_count = 0;
    }

    pub fn deinit(self: *VkEnv) void {
        self.vkd.deviceWaitIdle(self.device) catch {};

        // Phase 2 cleanup
        // Flush DMA-BUF resource cache first (before destroying texture slots)
        for (&self.dmabuf_cache) |*entry| {
            if (entry.ino != 0) {
                if (entry.view != .null_handle) self.vkd.destroyImageView(self.device, entry.view, null);
                if (entry.image != .null_handle) self.vkd.destroyImage(self.device, entry.image, null);
                if (entry.memory != .null_handle) self.vkd.freeMemory(self.device, entry.memory, null);
                entry.* = .{};
            }
        }
        for (&self.textures) |*slot| {
            if (slot.in_use) {
                if (slot.view != .null_handle) self.vkd.destroyImageView(self.device, slot.view, null);
                if (slot.image != .null_handle) self.vkd.destroyImage(self.device, slot.image, null);
                if (slot.memory != .null_handle) self.vkd.freeMemory(self.device, slot.memory, null);
            }
        }
        if (self.basic_2d_pipeline != .null_handle) self.vkd.destroyPipeline(self.device, self.basic_2d_pipeline, null);
        if (self.color_2d_pipeline != .null_handle) self.vkd.destroyPipeline(self.device, self.color_2d_pipeline, null);
        if (self.basic_2d_pipeline_unorm != .null_handle) self.vkd.destroyPipeline(self.device, self.basic_2d_pipeline_unorm, null);
        if (self.color_2d_pipeline_unorm != .null_handle) self.vkd.destroyPipeline(self.device, self.color_2d_pipeline_unorm, null);
        if (self.rt_fence != .null_handle) self.vkd.destroyFence(self.device, self.rt_fence, null);
        if (self.stencil_view != .null_handle) self.vkd.destroyImageView(self.device, self.stencil_view, null);
        if (self.stencil_image != .null_handle) self.vkd.destroyImage(self.device, self.stencil_image, null);
        if (self.stencil_memory != .null_handle) self.vkd.freeMemory(self.device, self.stencil_memory, null);
        if (self.depth_view != .null_handle) self.vkd.destroyImageView(self.device, self.depth_view, null);
        if (self.depth_image != .null_handle) self.vkd.destroyImage(self.device, self.depth_image, null);
        if (self.depth_memory != .null_handle) self.vkd.freeMemory(self.device, self.depth_memory, null);
        if (self.vert_shader_basic != .null_handle) self.vkd.destroyShaderModule(self.device, self.vert_shader_basic, null);
        if (self.frag_shader_basic != .null_handle) self.vkd.destroyShaderModule(self.device, self.frag_shader_basic, null);
        if (self.vert_shader_color != .null_handle) self.vkd.destroyShaderModule(self.device, self.vert_shader_color, null);
        if (self.frag_shader_color != .null_handle) self.vkd.destroyShaderModule(self.device, self.frag_shader_color, null);
        if (self.sampler_linear != .null_handle) self.vkd.destroySampler(self.device, self.sampler_linear, null);
        if (self.sampler_nearest != .null_handle) self.vkd.destroySampler(self.device, self.sampler_nearest, null);
        if (self.frame_desc_pool != .null_handle) self.vkd.destroyDescriptorPool(self.device, self.frame_desc_pool, null);
        if (self.descriptor_pool != .null_handle) self.vkd.destroyDescriptorPool(self.device, self.descriptor_pool, null);
        if (self.vertex_buffer != .null_handle) self.vkd.destroyBuffer(self.device, self.vertex_buffer, null);
        if (self.vertex_memory != .null_handle) self.vkd.freeMemory(self.device, self.vertex_memory, null);
        if (self.staging_buffer != .null_handle) self.vkd.destroyBuffer(self.device, self.staging_buffer, null);
        if (self.staging_memory != .null_handle) self.vkd.freeMemory(self.device, self.staging_memory, null);
        if (self.dummy_ubo_buffer != .null_handle) self.vkd.destroyBuffer(self.device, self.dummy_ubo_buffer, null);
        if (self.dummy_ubo_memory != .null_handle) self.vkd.freeMemory(self.device, self.dummy_ubo_memory, null);
        if (self.upload_fence != .null_handle) self.vkd.destroyFence(self.device, self.upload_fence, null);
        for (0..2) |i| {
            if (self.readback_staging[i] != .null_handle) self.vkd.destroyBuffer(self.device, self.readback_staging[i], null);
            if (self.readback_memory[i] != .null_handle) self.vkd.freeMemory(self.device, self.readback_memory[i], null);
            if (self.readback_fence[i] != .null_handle) self.vkd.destroyFence(self.device, self.readback_fence[i], null);
        }

        // Phase 1 cleanup
        self.vkd.destroyFence(self.device, self.frame_fence, null);
        self.vkd.destroySemaphore(self.device, self.render_finished, null);
        self.vkd.destroySemaphore(self.device, self.image_available, null);
        self.vkd.destroyCommandPool(self.device, self.command_pool, null);
        self.vkd.destroyPipelineLayout(self.device, self.pipeline_layout, null);
        self.vkd.destroyDescriptorSetLayout(self.device, self.descriptor_set_layout, null);
        self.vkd.destroyDevice(self.device, null);
        self.vki.destroyInstance(self.instance, null);
    }
};

var global_env: ?*VkEnv = null;
var env_storage: VkEnv = undefined;

// Helper: find memory type index
extern "c" var stderr: *anyopaque;
extern "c" fn fprintf(s: *anyopaque, fmt: [*:0]const u8, ...) c_int;

fn findMemoryType(env: *VkEnv, type_filter: u32, properties: vk.MemoryPropertyFlags) ?u32 {
    for (0..env.mem_props.memory_type_count) |i| {
        const idx: u5 = @intCast(i);
        if ((type_filter & (@as(u32, 1) << idx)) != 0) {
            // Access via pointer into the array slot rather than
            // `env.mem_props.memory_types[i].property_flags` (implicit copy).
            // The SH aarch64 backend miscompiles the 8-byte extern-struct
            // copy from an indexed array element: the resulting local has
            // property_flags zeroed even though the underlying bytes were
            // populated correctly by the ICD. Reading via `*const MemoryType`
            // bypasses the broken copy. Mirrored in every other site that
            // dereferences `env.mem_props.memory_types[…]`.
            const mt_ptr: *const vk.MemoryType = &env.mem_props.memory_types[i];
            const req: u32 = @bitCast(properties);
            const has: u32 = @bitCast(mt_ptr.property_flags);
            if ((has & req) == req) {
                return @intCast(i);
            }
        }
    }
    return null;
}

// Helper: create buffer + allocate memory
fn createBuffer(
    env: *VkEnv,
    size: vk.DeviceSize,
    usage: vk.BufferUsageFlags,
    properties: vk.MemoryPropertyFlags,
) !struct { buffer: vk.Buffer, memory: vk.DeviceMemory } {
    const buffer = env.vkd.createBuffer(env.device, &.{
        .size = size,
        .usage = usage,
        .sharing_mode = .exclusive,
    }, null) catch return error.BufferCreateFailed;

    const mem_req = env.vkd.getBufferMemoryRequirements(env.device, buffer);
    const mem_type = findMemoryType(env, mem_req.memory_type_bits, properties) orelse
        return error.NoSuitableMemory;

    const memory = env.vkd.allocateMemory(env.device, &.{
        .allocation_size = mem_req.size,
        .memory_type_index = mem_type,
    }, null) catch return error.MemoryAllocFailed;

    env.vkd.bindBufferMemory(env.device, buffer, memory, 0) catch return error.BindMemoryFailed;

    return .{ .buffer = buffer, .memory = memory };
}

// Helper: create/destroy stencil image (S8_UINT)
fn createStencilImage(env: *VkEnv, w: u32, h: u32) !void {
    if (w == 0 or h == 0) return error.InvalidDimensions;

    const image = env.vkd.createImage(env.device, &.{
        .image_type = .@"2d",
        .format = .s8_uint,
        .extent = .{ .width = w, .height = h, .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = .{ .depth_stencil_attachment_bit = true },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    }, null) catch return error.ImageCreateFailed;

    const mem_req = env.vkd.getImageMemoryRequirements(env.device, image);
    const mem_type = findMemoryType(env, mem_req.memory_type_bits, .{ .device_local_bit = true }) orelse
        return error.NoSuitableMemory;
    const memory = env.vkd.allocateMemory(env.device, &.{
        .allocation_size = mem_req.size,
        .memory_type_index = mem_type,
    }, null) catch return error.MemoryAllocFailed;
    env.vkd.bindImageMemory(env.device, image, memory, 0) catch return error.BindMemoryFailed;

    const view = env.vkd.createImageView(env.device, &.{
        .image = image,
        .view_type = .@"2d",
        .format = .s8_uint,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = .{ .stencil_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null) catch return error.ImageViewCreateFailed;

    env.stencil_image = image;
    env.stencil_view = view;
    env.stencil_memory = memory;
}

fn destroyStencilImage(env: *VkEnv) void {
    if (env.stencil_view != .null_handle) env.vkd.destroyImageView(env.device, env.stencil_view, null);
    if (env.stencil_image != .null_handle) env.vkd.destroyImage(env.device, env.stencil_image, null);
    if (env.stencil_memory != .null_handle) env.vkd.freeMemory(env.device, env.stencil_memory, null);
    env.stencil_view = .null_handle;
    env.stencil_image = .null_handle;
    env.stencil_memory = .null_handle;
}

fn createDepthImage(env: *VkEnv, w: u32, h: u32) !void {
    if (w == 0 or h == 0) return error.InvalidDimensions;

    const image = env.vkd.createImage(env.device, &.{
        .image_type = .@"2d",
        .format = .d32_sfloat,
        .extent = .{ .width = w, .height = h, .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = .{ .depth_stencil_attachment_bit = true },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    }, null) catch return error.ImageCreateFailed;

    const mem_req = env.vkd.getImageMemoryRequirements(env.device, image);
    const mem_type = findMemoryType(env, mem_req.memory_type_bits, .{ .device_local_bit = true }) orelse
        return error.NoSuitableMemory;
    const memory = env.vkd.allocateMemory(env.device, &.{
        .allocation_size = mem_req.size,
        .memory_type_index = mem_type,
    }, null) catch return error.MemoryAllocFailed;
    env.vkd.bindImageMemory(env.device, image, memory, 0) catch return error.BindMemoryFailed;

    const view = env.vkd.createImageView(env.device, &.{
        .image = image,
        .view_type = .@"2d",
        .format = .d32_sfloat,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = .{ .depth_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null) catch return error.ImageViewCreateFailed;

    env.depth_image = image;
    env.depth_view = view;
    env.depth_memory = memory;
}

fn destroyDepthImage(env: *VkEnv) void {
    if (env.depth_view != .null_handle) env.vkd.destroyImageView(env.device, env.depth_view, null);
    if (env.depth_image != .null_handle) env.vkd.destroyImage(env.device, env.depth_image, null);
    if (env.depth_memory != .null_handle) env.vkd.freeMemory(env.device, env.depth_memory, null);
    env.depth_view = .null_handle;
    env.depth_image = .null_handle;
    env.depth_memory = .null_handle;
}

// Helper: create shader module from u32-aligned SPIR-V data
fn createShaderModule(env: *VkEnv, code: []align(@alignOf(u32)) const u8) !vk.ShaderModule {
    return env.vkd.createShaderModule(env.device, &.{
        .code_size = code.len,
        .p_code = @ptrCast(code.ptr),
    }, null) catch return error.ShaderModuleCreateFailed;
}

// Embedded SPIR-V shaders — align(4) ensures u32 alignment required by Vulkan
const basic_2d_vert_spv align(@alignOf(u32)) = @embedFile("shaders/basic_2d_vert.spv").*;
const basic_2d_frag_spv align(@alignOf(u32)) = @embedFile("shaders/basic_2d_frag.spv").*;
const color_2d_vert_spv align(@alignOf(u32)) = @embedFile("shaders/color_2d_vert.spv").*;
const color_2d_frag_spv align(@alignOf(u32)) = @embedFile("shaders/color_2d_frag.spv").*;

// Phase 2 Initialization
pub fn initPhase2(env: *VkEnv, swapchain_format: vk.Format) !void {
    env.swapchain_format = swapchain_format;
    _ = fprintf(stderr, "initPhase2: entry\n");
    // Call the dispatch pointer directly with a pointer to env.mem_props
    // rather than vk-zig's `var out = undefined; fn(&out); return out;`
    // wrapper. Return-by-value of a 528-byte struct is miscompiled by the
    // aarch64 SH backend (memory_types[] stay zeroed after the ICD wrote
    // them). Direct dispatch makes the ICD write into final storage.
    env.vki.dispatch.vkGetPhysicalDeviceMemoryProperties.?(env.physical_device, &env.mem_props);
    _ = fprintf(stderr, "initPhase2: got mem_props (count=%d)\n", @as(c_uint, env.mem_props.memory_type_count));

    // Create shader modules from embedded SPIR-V
    env.vert_shader_basic = try createShaderModule(env, &basic_2d_vert_spv);
    env.frag_shader_basic = try createShaderModule(env, &basic_2d_frag_spv);
    env.vert_shader_color = try createShaderModule(env, &color_2d_vert_spv);
    env.frag_shader_color = try createShaderModule(env, &color_2d_frag_spv);
    _ = fprintf(stderr, "initPhase2: shaders OK\n");

    // Create samplers
    env.sampler_linear = env.vkd.createSampler(env.device, &.{
        .mag_filter = .linear,
        .min_filter = .linear,
        .mipmap_mode = .linear,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
        .mip_lod_bias = 0,
        .anisotropy_enable = .false,
        .max_anisotropy = 1,
        .compare_enable = .false,
        .compare_op = .always,
        .min_lod = 0,
        .max_lod = 0,
        .border_color = .float_transparent_black,
        .unnormalized_coordinates = .false,
    }, null) catch return error.SamplerCreateFailed;

    env.sampler_nearest = env.vkd.createSampler(env.device, &.{
        .mag_filter = .nearest,
        .min_filter = .nearest,
        .mipmap_mode = .nearest,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
        .mip_lod_bias = 0,
        .anisotropy_enable = .false,
        .max_anisotropy = 1,
        .compare_enable = .false,
        .compare_op = .always,
        .min_lod = 0,
        .max_lod = 0,
        .border_color = .float_transparent_black,
        .unnormalized_coordinates = .false,
    }, null) catch return error.SamplerCreateFailed;

    // Create descriptor pool — sized for textures + custom shader UBOs
    // Each texture set uses all 4 bindings: sampler(0) + dummy UBO(1) + sampler(2) + SDF atlas(3).
    // Each custom shader set uses: sampler(0) + UBO(1) + optional sampler(2) + optional SDF(3).
    const MAX_CUSTOM_SHADERS = 256;
    const pool_sizes = [_]vk.DescriptorPoolSize{
        .{
            .type = .combined_image_sampler,
            .descriptor_count = MAX_TEXTURES * 3 + MAX_CUSTOM_SHADERS * 3,
        },
        .{
            .type = .uniform_buffer_dynamic,
            .descriptor_count = MAX_TEXTURES + MAX_CUSTOM_SHADERS,
        },
    };
    env.descriptor_pool = env.vkd.createDescriptorPool(env.device, &.{
        .max_sets = MAX_TEXTURES + MAX_CUSTOM_SHADERS,
        .pool_size_count = pool_sizes.len,
        .p_pool_sizes = &pool_sizes,
        .flags = .{ .free_descriptor_set_bit = true },
    }, null) catch return error.DescriptorPoolCreateFailed;

    // Per-frame descriptor pool: fresh set per custom shader draw per frame.
    // 512 sets handles worst-case (multiple RT passes × many custom shader draws).
    const FRAME_MAX_SETS = 512;
    const frame_pool_sizes = [_]vk.DescriptorPoolSize{
        .{ .type = .combined_image_sampler, .descriptor_count = FRAME_MAX_SETS * 3 },
        .{ .type = .uniform_buffer_dynamic, .descriptor_count = FRAME_MAX_SETS },
    };
    env.frame_desc_pool = env.vkd.createDescriptorPool(env.device, &.{
        .max_sets = FRAME_MAX_SETS,
        .pool_size_count = frame_pool_sizes.len,
        .p_pool_sizes = &frame_pool_sizes,
        .flags = .{}, // no FREE_DESCRIPTOR_SET_BIT — we reset the whole pool per frame
    }, null) catch return error.DescriptorPoolCreateFailed;
    _ = fprintf(stderr, "initPhase2: samplers + descriptor pools OK\n");

    // Create graphics pipelines (swapchain format — with depth/stencil)
    env.basic_2d_pipeline = try createGraphicsPipeline(
        env,
        env.vert_shader_basic,
        env.frag_shader_basic,
        swapchain_format,
        .d32_sfloat,
        .s8_uint,
    );
    env.color_2d_pipeline = try createGraphicsPipeline(
        env,
        env.vert_shader_color,
        env.frag_shader_color,
        swapchain_format,
        .d32_sfloat,
        .s8_uint,
    );

    // Phase 4: UNORM pipelines for offscreen RT rendering
    // R8G8B8A8 for RT rendering — pixel upload swizzles BGRA→RGBA in uploadTexturePixels
    // Fix: RT passes don't attach depth/stencil, so pipeline must declare .undefined
    // per Vulkan spec §8.3: "if pDepthAttachment is NULL ... depthAttachmentFormat must be UNDEFINED"
    env.basic_2d_pipeline_unorm = try createGraphicsPipeline(
        env,
        env.vert_shader_basic,
        env.frag_shader_basic,
        .r8g8b8a8_unorm,
        .undefined,
        .undefined,
    );
    env.color_2d_pipeline_unorm = try createGraphicsPipeline(
        env,
        env.vert_shader_color,
        env.frag_shader_color,
        .r8g8b8a8_unorm,
        .undefined,
        .undefined,
    );
    _ = fprintf(stderr, "initPhase2: pipelines OK\n");

    // Create vertex buffer (host-visible, persistently mapped)
    const vb = try createBuffer(env, VERTEX_BUFFER_SIZE, .{ .vertex_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
    env.vertex_buffer = vb.buffer;
    env.vertex_memory = vb.memory;
    env.vertex_mapped = @ptrCast(env.vkd.mapMemory(env.device, vb.memory, 0, VERTEX_BUFFER_SIZE, .{}) catch
        return error.MapMemoryFailed);

    // Create staging buffer (host-visible, for texture uploads)
    const sb = try createBuffer(env, STAGING_BUFFER_SIZE, .{ .transfer_src_bit = true, .transfer_dst_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
    env.staging_buffer = sb.buffer;
    env.staging_memory = sb.memory;
    env.staging_mapped = @ptrCast(env.vkd.mapMemory(env.device, sb.memory, 0, STAGING_BUFFER_SIZE, .{}) catch
        return error.MapMemoryFailed);

    // Create dummy UBO buffer (256 bytes, zeroed) for unused binding 1 in texture descriptor sets
    const dub = try createBuffer(env, 256, .{ .uniform_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
    env.dummy_ubo_buffer = dub.buffer;
    env.dummy_ubo_memory = dub.memory;

    // Allocate upload command buffer
    var upload_cmd_buf: [1]vk.CommandBuffer = undefined;
    env.vkd.allocateCommandBuffers(env.device, &.{
        .command_pool = env.command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, &upload_cmd_buf) catch return error.CmdBufferAllocFailed;
    env.upload_cmd = upload_cmd_buf[0];

    // Create upload fence
    env.upload_fence = env.vkd.createFence(env.device, &.{}, null) catch
        return error.FenceCreateFailed;

    // Phase 4: RT fence for offscreen rendertarget passes
    env.rt_fence = env.vkd.createFence(env.device, &.{}, null) catch
        return error.FenceCreateFailed;

    // Async readback double-buffered staging (2 x STAGING_BUFFER_SIZE)
    for (0..2) |i| {
        const rb = try createBuffer(env, STAGING_BUFFER_SIZE, .{ .transfer_dst_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
        env.readback_staging[i] = rb.buffer;
        env.readback_memory[i] = rb.memory;
        env.readback_mapped[i] = @ptrCast(env.vkd.mapMemory(env.device, rb.memory, 0, STAGING_BUFFER_SIZE, .{}) catch
            return error.MapMemoryFailed);
        env.readback_fence[i] = env.vkd.createFence(env.device, &.{ .flags = .{ .signaled_bit = true } }, null) catch
            return error.FenceCreateFailed;
    }
    var rb_cmds: [2]vk.CommandBuffer = undefined;
    env.vkd.allocateCommandBuffers(env.device, &.{
        .command_pool = env.command_pool,
        .level = .primary,
        .command_buffer_count = 2,
    }, &rb_cmds) catch return error.CmdBufferAllocFailed;
    env.readback_cmd[0] = rb_cmds[0];
    env.readback_cmd[1] = rb_cmds[1];

    _ = fprintf(stderr, "initPhase2: buffers/fences OK\n");
    // Create default 1x1 white texture (slot 0)
    const white_pixel = [4]u8{ 255, 255, 255, 255 };
    env.textures[0] = try createTextureInternal(env, 1, 1, &white_pixel);
    env.textures[0].in_use = true;
    _ = fprintf(stderr, "initPhase2: default texture OK (exiting)\n");
}

// Helper: create graphics pipeline
fn createGraphicsPipeline(
    env: *VkEnv,
    vert_module: vk.ShaderModule,
    frag_module: vk.ShaderModule,
    color_format: vk.Format,
    depth_format: vk.Format,
    stencil_format: vk.Format,
) !vk.Pipeline {
    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .stage = .{ .vertex_bit = true },
            .module = vert_module,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = frag_module,
            .p_name = "main",
        },
    };

    // Vertex input: pos2 + uv2 = 16 bytes per vertex
    const binding_desc = [_]vk.VertexInputBindingDescription{.{
        .binding = 0,
        .stride = 16,
        .input_rate = .vertex,
    }};
    const attr_descs = [_]vk.VertexInputAttributeDescription{
        .{ .location = 0, .binding = 0, .format = .r32g32_sfloat, .offset = 0 }, // pos
        .{ .location = 1, .binding = 0, .format = .r32g32_sfloat, .offset = 8 }, // uv
    };

    const vertex_input = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = binding_desc.len,
        .p_vertex_binding_descriptions = &binding_desc,
        .vertex_attribute_description_count = attr_descs.len,
        .p_vertex_attribute_descriptions = &attr_descs,
    };

    const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_strip,
        .primitive_restart_enable = .false,
    };

    // Dynamic state: viewport/scissor + EDS1 (VK 1.3 core) + EDS3. The EDS3
    // entries are last so devices without the blend features (MoltenVK /
    // KosmicKrisp) just truncate the list — blending then comes from the
    // pipeline's static standard-alpha attachment state below.
    const dynamic_states = [_]vk.DynamicState{
        .viewport,
        .scissor,
        // EDS1 (VK 1.3 core)
        .primitive_topology,
        .cull_mode,
        .front_face,
        .depth_test_enable,
        .depth_write_enable,
        .depth_compare_op,
        .stencil_test_enable,
        .stencil_op,
        // EDS3 (VK_EXT_extended_dynamic_state3)
        .color_blend_enable_ext,
        .color_blend_equation_ext,
        .color_write_mask_ext,
    };
    const dynamic_state = vk.PipelineDynamicStateCreateInfo{
        .dynamic_state_count = if (env.has_eds3_blend) dynamic_states.len else dynamic_states.len - 3,
        .p_dynamic_states = &dynamic_states,
    };

    const viewport_state = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .scissor_count = 1,
    };

    const rasterizer = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .true,
        .rasterizer_discard_enable = .false,
        .polygon_mode = .fill,
        .cull_mode = .{},
        .front_face = .counter_clockwise,
        .depth_bias_enable = .false,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1.0,
    };

    const multisampling = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = .false,
        .min_sample_shading = 1.0,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };

    // Alpha blending: src_alpha / one_minus_src_alpha
    const blend_attachment = [_]vk.PipelineColorBlendAttachmentState{.{
        .blend_enable = .true,
        .src_color_blend_factor = .src_alpha,
        .dst_color_blend_factor = .one_minus_src_alpha,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .one_minus_src_alpha,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    }};
    const color_blending = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = blend_attachment.len,
        .p_attachments = &blend_attachment,
        .blend_constants = .{ 0, 0, 0, 0 },
    };

    // Depth/stencil state — all dynamic, but struct must exist for validation
    const depth_stencil = vk.PipelineDepthStencilStateCreateInfo{
        .depth_test_enable = .false,
        .depth_write_enable = .false,
        .depth_compare_op = .always,
        .depth_bounds_test_enable = .false,
        .stencil_test_enable = .false,
        .front = std.mem.zeroes(vk.StencilOpState),
        .back = std.mem.zeroes(vk.StencilOpState),
        .min_depth_bounds = 0,
        .max_depth_bounds = 1,
    };

    // Dynamic rendering (Vulkan 1.3+) — no render pass needed
    const rendering_info = vk.PipelineRenderingCreateInfo{
        .color_attachment_count = 1,
        .p_color_attachment_formats = @ptrCast(&color_format),
        .depth_attachment_format = depth_format,
        .stencil_attachment_format = stencil_format,
        .view_mask = 0,
    };

    const pipeline_info = [_]vk.GraphicsPipelineCreateInfo{.{
        .p_next = @ptrCast(&rendering_info),
        .stage_count = shader_stages.len,
        .p_stages = &shader_stages,
        .p_vertex_input_state = &vertex_input,
        .p_input_assembly_state = &input_assembly,
        .p_viewport_state = &viewport_state,
        .p_rasterization_state = &rasterizer,
        .p_multisample_state = &multisampling,
        .p_depth_stencil_state = &depth_stencil,
        .p_color_blend_state = &color_blending,
        .p_dynamic_state = &dynamic_state,
        .layout = env.pipeline_layout,
        .render_pass = .null_handle,
        .subpass = 0,
        .base_pipeline_index = -1,
    }};

    var pipeline: [1]vk.Pipeline = undefined;
    _ = env.vkd.createGraphicsPipelines(
        env.device,
        .null_handle,
        pipeline_info.len,
        &pipeline_info,
        null,
        &pipeline,
    ) catch return error.PipelineCreateFailed;

    return pipeline[0];
}

// Internal: create texture VkImage + VkImageView + descriptor set
// Slug GPU glyph pipeline: 2 vertex bindings (unit quad + per-instance cell data).
fn createSlugPipeline(
    env: *VkEnv,
    vert_module: vk.ShaderModule,
    frag_module: vk.ShaderModule,
    color_format: vk.Format,
) !vk.Pipeline {
    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
        .{ .stage = .{ .vertex_bit = true }, .module = vert_module, .p_name = "main" },
        .{ .stage = .{ .fragment_bit = true }, .module = frag_module, .p_name = "main" },
    };

    // Two bindings:
    //   Binding 0: per-vertex unit quad (pos2 + uv2 = 16 bytes), input_rate = VERTEX
    //   Binding 1: per-instance cell data (GpuCellInstance = 96 bytes), input_rate = INSTANCE
    const binding_desc = [_]vk.VertexInputBindingDescription{
        .{ .binding = 0, .stride = 16, .input_rate = .vertex },
        .{ .binding = 1, .stride = 96, .input_rate = .instance },
    };
    // Vertex attributes:
    //   loc 0: pos (vec2)  — binding 0, offset 0
    //   loc 1: uv (vec2)   — binding 0, offset 8
    // Instance attributes (binding 1, GpuCellInstance layout):
    //   loc 2: cell_pos (vec2)        — offset 0
    //   loc 3: cell_size (vec2)       — offset 8
    //   loc 4: em_min (vec2)          — offset 16
    //   loc 5: em_max (vec2)          — offset 24
    //   loc 6: band_transform (vec4)  — offset 32
    //   loc 7: glyph_data (ivec4)     — offset 48
    //   loc 8: fg_color (vec4)        — offset 64
    //   loc 9: bg_color (vec4)        — offset 80
    const attr_descs = [_]vk.VertexInputAttributeDescription{
        // Binding 0: per-vertex quad
        .{ .location = 0, .binding = 0, .format = .r32g32_sfloat, .offset = 0 },  // pos
        .{ .location = 1, .binding = 0, .format = .r32g32_sfloat, .offset = 8 },  // uv
        // Binding 1: per-instance cell data
        .{ .location = 2, .binding = 1, .format = .r32g32_sfloat, .offset = 0 },  // cell_pos
        .{ .location = 3, .binding = 1, .format = .r32g32_sfloat, .offset = 8 },  // cell_size
        .{ .location = 4, .binding = 1, .format = .r32g32_sfloat, .offset = 16 }, // em_min
        .{ .location = 5, .binding = 1, .format = .r32g32_sfloat, .offset = 24 }, // em_max
        .{ .location = 6, .binding = 1, .format = .r32g32b32a32_sfloat, .offset = 32 }, // band_transform
        .{ .location = 7, .binding = 1, .format = .r32g32b32a32_sint, .offset = 48 },   // glyph_data
        .{ .location = 8, .binding = 1, .format = .r32g32b32a32_sfloat, .offset = 64 }, // fg_color
        .{ .location = 9, .binding = 1, .format = .r32g32b32a32_sfloat, .offset = 80 }, // bg_color
    };

    const vertex_input = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = binding_desc.len,
        .p_vertex_binding_descriptions = &binding_desc,
        .vertex_attribute_description_count = attr_descs.len,
        .p_vertex_attribute_descriptions = &attr_descs,
    };

    const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list, // 6 vertices = 2 triangles per quad
        .primitive_restart_enable = .false,
    };

    // Minimal dynamic state — only viewport + scissor.
    // No EDS1/EDS3 — use static state for everything else to maximize driver compat.
    const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };
    const dynamic_state = vk.PipelineDynamicStateCreateInfo{
        .dynamic_state_count = dynamic_states.len,
        .p_dynamic_states = &dynamic_states,
    };

    const viewport_state = vk.PipelineViewportStateCreateInfo{ .viewport_count = 1, .scissor_count = 1 };

    const rasterizer = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .false, .rasterizer_discard_enable = .false,
        .polygon_mode = .fill, .cull_mode = .{}, .front_face = .counter_clockwise,
        .depth_bias_enable = .false, .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0, .depth_bias_slope_factor = 0, .line_width = 1.0,
    };

    const multisampling = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true }, .sample_shading_enable = .false,
        .min_sample_shading = 1.0, .alpha_to_coverage_enable = .false, .alpha_to_one_enable = .false,
    };

    // Alpha over blending for text coverage
    const blend_attachment = [_]vk.PipelineColorBlendAttachmentState{.{
        .blend_enable = .true,
        .src_color_blend_factor = .src_alpha, .dst_color_blend_factor = .one_minus_src_alpha,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one, .dst_alpha_blend_factor = .one_minus_src_alpha,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    }};
    const color_blending = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = .false, .logic_op = .copy,
        .attachment_count = blend_attachment.len, .p_attachments = &blend_attachment,
        .blend_constants = .{ 0, 0, 0, 0 },
    };

    const depth_stencil = vk.PipelineDepthStencilStateCreateInfo{
        .depth_test_enable = .false, .depth_write_enable = .false, .depth_compare_op = .always,
        .depth_bounds_test_enable = .false, .stencil_test_enable = .false,
        .front = std.mem.zeroes(vk.StencilOpState), .back = std.mem.zeroes(vk.StencilOpState),
        .min_depth_bounds = 0, .max_depth_bounds = 1,
    };

    const rendering_info = vk.PipelineRenderingCreateInfo{
        .color_attachment_count = 1,
        .p_color_attachment_formats = @ptrCast(&color_format),
        .depth_attachment_format = .undefined,
        .stencil_attachment_format = .undefined,
        .view_mask = 0,
    };

    const pipeline_info = [_]vk.GraphicsPipelineCreateInfo{.{
        .p_next = @ptrCast(&rendering_info),
        .stage_count = shader_stages.len, .p_stages = &shader_stages,
        .p_vertex_input_state = &vertex_input,
        .p_input_assembly_state = &input_assembly,
        .p_viewport_state = &viewport_state,
        .p_rasterization_state = &rasterizer,
        .p_multisample_state = &multisampling,
        .p_depth_stencil_state = &depth_stencil,
        .p_color_blend_state = &color_blending,
        .p_dynamic_state = &dynamic_state,
        .layout = env.pipeline_layout,
        .render_pass = .null_handle,
        .subpass = 0,
        .base_pipeline_index = -1,
    }};

    var pipeline: [1]vk.Pipeline = undefined;
    _ = env.vkd.createGraphicsPipelines(env.device, .null_handle, pipeline_info.len, &pipeline_info, null, &pipeline) catch
        return error.PipelineCreateFailed;

    return pipeline[0];
}

export fn vk_env_create_slug_pipeline(vert_handle: u64, frag_handle: u64) u64 {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return 0;
    const vert_mod: vk.ShaderModule = @enumFromInt(vert_handle);
    const frag_mod: vk.ShaderModule = @enumFromInt(frag_handle);
    // Vstore textures are R8G8B8A8_UNORM — must match pipeline color attachment format
    const format = vk.Format.r8g8b8a8_unorm;
    const pipeline = createSlugPipeline(env, vert_mod, frag_mod, format) catch {
        return 0;
    };
    return @intFromEnum(pipeline);
}

/// Create Slug pipeline for SDF temporal accumulation into R16F atlas.
/// EMA blending: new = alpha * src + (1-alpha) * dst, alpha = blend_constants.
fn createSlugSdfAccumPipeline(
    env: *VkEnv,
    vert_module: vk.ShaderModule,
    frag_module: vk.ShaderModule,
    color_format: vk.Format,
) !vk.Pipeline {
    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
        .{ .stage = .{ .vertex_bit = true }, .module = vert_module, .p_name = "main" },
        .{ .stage = .{ .fragment_bit = true }, .module = frag_module, .p_name = "main" },
    };

    // Two bindings: same as createSlugPipeline
    const binding_desc = [_]vk.VertexInputBindingDescription{
        .{ .binding = 0, .stride = 16, .input_rate = .vertex },
        .{ .binding = 1, .stride = 96, .input_rate = .instance },
    };
    const attr_descs = [_]vk.VertexInputAttributeDescription{
        .{ .location = 0, .binding = 0, .format = .r32g32_sfloat, .offset = 0 },
        .{ .location = 1, .binding = 0, .format = .r32g32_sfloat, .offset = 8 },
        .{ .location = 2, .binding = 1, .format = .r32g32_sfloat, .offset = 0 },
        .{ .location = 3, .binding = 1, .format = .r32g32_sfloat, .offset = 8 },
        .{ .location = 4, .binding = 1, .format = .r32g32_sfloat, .offset = 16 },
        .{ .location = 5, .binding = 1, .format = .r32g32_sfloat, .offset = 24 },
        .{ .location = 6, .binding = 1, .format = .r32g32b32a32_sfloat, .offset = 32 },
        .{ .location = 7, .binding = 1, .format = .r32g32b32a32_sint, .offset = 48 },
        .{ .location = 8, .binding = 1, .format = .r32g32b32a32_sfloat, .offset = 64 },
        .{ .location = 9, .binding = 1, .format = .r32g32b32a32_sfloat, .offset = 80 },
    };

    const vertex_input = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = binding_desc.len,
        .p_vertex_binding_descriptions = &binding_desc,
        .vertex_attribute_description_count = attr_descs.len,
        .p_vertex_attribute_descriptions = &attr_descs,
    };

    const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list,
        .primitive_restart_enable = .false,
    };

    const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };
    const dynamic_state = vk.PipelineDynamicStateCreateInfo{
        .dynamic_state_count = dynamic_states.len,
        .p_dynamic_states = &dynamic_states,
    };

    const viewport_state = vk.PipelineViewportStateCreateInfo{ .viewport_count = 1, .scissor_count = 1 };

    const rasterizer = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .false, .rasterizer_discard_enable = .false,
        .polygon_mode = .fill, .cull_mode = .{}, .front_face = .counter_clockwise,
        .depth_bias_enable = .false, .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0, .depth_bias_slope_factor = 0, .line_width = 1.0,
    };

    const multisampling = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true }, .sample_shading_enable = .false,
        .min_sample_shading = 1.0, .alpha_to_coverage_enable = .false, .alpha_to_one_enable = .false,
    };

    // Direct overwrite — accumulation shader writes fresh coverage each frame.
    // No blending needed: SlugRenderMS already averages 4 jittered samples.
    const blend_attachment = [_]vk.PipelineColorBlendAttachmentState{.{
        .blend_enable = .false,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = false, .b_bit = false, .a_bit = false },
    }};
    const color_blending = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = .false, .logic_op = .copy,
        .attachment_count = blend_attachment.len, .p_attachments = &blend_attachment,
        .blend_constants = .{ 0, 0, 0, 0 },
    };

    const depth_stencil = vk.PipelineDepthStencilStateCreateInfo{
        .depth_test_enable = .false, .depth_write_enable = .false, .depth_compare_op = .always,
        .depth_bounds_test_enable = .false, .stencil_test_enable = .false,
        .front = std.mem.zeroes(vk.StencilOpState), .back = std.mem.zeroes(vk.StencilOpState),
        .min_depth_bounds = 0, .max_depth_bounds = 1,
    };

    const rendering_info = vk.PipelineRenderingCreateInfo{
        .color_attachment_count = 1,
        .p_color_attachment_formats = @ptrCast(&color_format),
        .depth_attachment_format = .undefined,
        .stencil_attachment_format = .undefined,
        .view_mask = 0,
    };

    const pipeline_info = [_]vk.GraphicsPipelineCreateInfo{.{
        .p_next = @ptrCast(&rendering_info),
        .stage_count = shader_stages.len, .p_stages = &shader_stages,
        .p_vertex_input_state = &vertex_input,
        .p_input_assembly_state = &input_assembly,
        .p_viewport_state = &viewport_state,
        .p_rasterization_state = &rasterizer,
        .p_multisample_state = &multisampling,
        .p_depth_stencil_state = &depth_stencil,
        .p_color_blend_state = &color_blending,
        .p_dynamic_state = &dynamic_state,
        .layout = env.pipeline_layout,
        .render_pass = .null_handle,
        .subpass = 0,
        .base_pipeline_index = -1,
    }};

    var pipeline: [1]vk.Pipeline = undefined;
    _ = env.vkd.createGraphicsPipelines(env.device, .null_handle, pipeline_info.len, &pipeline_info, null, &pipeline) catch
        return error.PipelineCreateFailed;

    return pipeline[0];
}

export fn vk_env_create_slug_sdf_pipeline(vert_handle: u64, frag_handle: u64) u64 {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return 0;
    const vert_mod: vk.ShaderModule = @enumFromInt(vert_handle);
    const frag_mod: vk.ShaderModule = @enumFromInt(frag_handle);
    const pipeline = createSlugSdfAccumPipeline(env, vert_mod, frag_mod, .r16_sfloat) catch return 0;
    return @intFromEnum(pipeline);
}

// Unit quad for Slug instanced rendering: 6 vertices (2 triangles), vec2 per vertex.
// Shared across all glyph draws. Created once, never destroyed.
var slug_quad_buf: vk.Buffer = .null_handle;
var slug_quad_mem: vk.DeviceMemory = .null_handle;

// GPU glyph dump flag (set from ARCAN_GPU_DUMP_GLYPHS env var)
var gpu_dump_enabled: bool = false;
var gpu_dump_checked: bool = false;

// Dedicated command buffer for slug draw — cannot share env.cmd because
// synchronous uploads (agp_stream_prepare) change image layouts between
// recording and submission, making env.cmd's recorded barriers invalid.
var slug_cmd: vk.CommandBuffer = .null_handle;

// Pixel readback: after GPU completes frame, read a patch from the slug target texture
var slug_readback_tex: u32 = 0;
var slug_readback_pending: bool = false;
var slug_readback_done: bool = false;
var slug_readback_count: u32 = 0;

export fn vk_env_create_slug_quad_buffer() bool {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return false;
    if (slug_quad_buf != .null_handle) return true; // already created

    // 6 vertices × 4 floats (pos.xy + uv.xy) × 4 bytes = 96 bytes
    // Standard arcan vertex layout: pos2 + uv2 = 16 bytes/vertex
    // Covers full NDC space: pos = [-1,1], uv = [0,1]
    const quad_data = [24]f32{
        // Triangle 1: TL, TR, BL
        -1, -1, 0, 0, // pos(-1,-1) uv(0,0)
         1, -1, 1, 0, // pos(1,-1) uv(1,0)
        -1,  1, 0, 1, // pos(-1,1) uv(0,1)
        // Triangle 2: TR, BR, BL
         1, -1, 1, 0, // pos(1,-1) uv(1,0)
         1,  1, 1, 1, // pos(1,1) uv(1,1)
        -1,  1, 0, 1, // pos(-1,1) uv(0,1)
    };

    const buf = env.vkd.createBuffer(env.device, &.{
        .size = @sizeOf(@TypeOf(quad_data)),
        .usage = .{ .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null) catch return false;

    const mem_req = env.vkd.getBufferMemoryRequirements(env.device, buf);
    const mem_type = findMemoryType(env, mem_req.memory_type_bits, .{
        .host_visible_bit = true, .host_coherent_bit = true,
    }) orelse return false;

    const mem = env.vkd.allocateMemory(env.device, &.{
        .allocation_size = mem_req.size,
        .memory_type_index = mem_type,
    }, null) catch return false;

    env.vkd.bindBufferMemory(env.device, buf, mem, 0) catch return false;

    // Map, write quad data, keep mapped (tiny buffer, no perf concern)
    const mapped: ?*anyopaque = env.vkd.mapMemory(env.device, mem, 0, @sizeOf(@TypeOf(quad_data)), .{}) catch return false;
    if (mapped) |ptr| {
        const dst: *[24]f32 = @ptrCast(@alignCast(ptr));
        dst.* = quad_data;
    }

    slug_quad_buf = buf;
    slug_quad_mem = mem;
    return true;
}

export fn vk_env_get_slug_quad_buffer() u64 {
    return @intFromEnum(slug_quad_buf);
}

// Instance buffer for Slug: host-coherent, 384KB (4096 instances × 96 bytes)
var slug_inst_buf: vk.Buffer = .null_handle;
var slug_inst_mem: vk.DeviceMemory = .null_handle;
var slug_inst_mapped: ?[*]u8 = null;
const SLUG_INST_BUF_SIZE: usize = 16384 * 96;

export fn vk_env_create_slug_instance_buffer() bool {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return false;
    if (slug_inst_buf != .null_handle) return true;

    const buf = env.vkd.createBuffer(env.device, &.{
        .size = SLUG_INST_BUF_SIZE,
        .usage = .{ .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null) catch return false;

    const mem_req = env.vkd.getBufferMemoryRequirements(env.device, buf);
    const mem_type = findMemoryType(env, mem_req.memory_type_bits, .{
        .host_visible_bit = true, .host_coherent_bit = true,
    }) orelse return false;

    const mem = env.vkd.allocateMemory(env.device, &.{
        .allocation_size = mem_req.size,
        .memory_type_index = mem_type,
    }, null) catch return false;

    env.vkd.bindBufferMemory(env.device, buf, mem, 0) catch return false;

    slug_inst_mapped = @ptrCast(env.vkd.mapMemory(env.device, mem, 0, SLUG_INST_BUF_SIZE, .{}) catch return false);
    slug_inst_buf = buf;
    slug_inst_mem = mem;

    // Create dedicated command buffer for slug draw
    if (slug_cmd == .null_handle) {
        var cmds: [1]vk.CommandBuffer = undefined;
        env.vkd.allocateCommandBuffers(env.device, &.{
            .command_pool = env.command_pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, &cmds) catch return false;
        slug_cmd = cmds[0];
    }

    return true;
}

export fn vk_env_upload_slug_instances(data: ?*const anyopaque, byte_count: u32) bool {
    if (slug_inst_mapped == null) return false;
    if (byte_count > SLUG_INST_BUF_SIZE) return false;
    if (data) |d| {
        const src: [*]const u8 = @ptrCast(d);
        @memcpy(slug_inst_mapped.?[0..byte_count], src[0..byte_count]);
        return true;
    }
    return false;
}

export fn vk_env_get_slug_instance_buffer() u64 {
    return @intFromEnum(slug_inst_buf);
}

/// Check if texture slot dimensions match expected w/h.
export fn vk_env_texture_matches_size(tex_id: u32, w: u32, h: u32) bool {
    const env = global_env orelse return false;
    if (tex_id == 0 or tex_id >= MAX_TEXTURES or !env.textures[tex_id].in_use) return false;
    return env.textures[tex_id].width == w and env.textures[tex_id].height == h;
}

/// Issue the Slug instanced draw into a vstore texture.
/// This renders GPU glyph instances over the existing CPU-rasterized background.
export fn vk_env_slug_draw(pipeline_handle: u64, tex_id: u32, instance_count: u32) bool {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return false;
    if (instance_count == 0) return true;
    if (tex_id >= MAX_TEXTURES or !env.textures[tex_id].in_use) return false;
    if (slug_quad_buf == .null_handle or slug_inst_buf == .null_handle) return false;

    const w = env.textures[tex_id].width;
    const h = env.textures[tex_id].height;
    if (w == 0 or h == 0) return false;

    // Begin rendering into the vstore texture (preserves CPU background)
    if (!vk_env_begin_rt_pass(tex_id, w, h)) {
        return false;
    }

    // Bind the Slug pipeline
    const pipeline: vk.Pipeline = @enumFromInt(pipeline_handle);
    env.vkd.cmdBindPipeline(env.cmd, .graphics, pipeline);

    // Set viewport (Y-flipped for Vulkan, matching RT rendering)
    const fw: f32 = @floatFromInt(w);
    const fh: f32 = @floatFromInt(h);
    env.vkd.cmdSetViewport(env.cmd, 0, 1, @ptrCast(&vk.Viewport{
        .x = 0, .y = 0, .width = fw, .height = fh, .min_depth = 0, .max_depth = 1,
    }));
    env.vkd.cmdSetScissor(env.cmd, 0, 1, @ptrCast(&vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = .{ .width = w, .height = h },
    }));

    // All rasterization/blend state is static in the Slug pipeline (no EDS).

    // Push constants: identity MVP, output size = texture size, opacity = 1
    var pc: PushConstants = .{};
    pc.sz_output = .{ fw, fh };
    pc.opacity = 1.0;
    env.vkd.cmdPushConstants(env.cmd, env.pipeline_layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, @sizeOf(PushConstants), @ptrCast(&pc));

    // Bind descriptor set (default white texture — Slug curve/band textures bound here when ready)
    // TODO(blocker5): Create and bind curve/band textures for real Slug rendering
    const desc = env.textures[0].descriptor_set; // texture 0 = default 1x1 white
    const zero_offset = [_]u32{0};
    env.vkd.cmdBindDescriptorSets(env.cmd, .graphics, env.pipeline_layout, 0, 1, @ptrCast(&desc), 1, &zero_offset);

    // Bind BOTH vertex buffers: binding 0 = unit quad, binding 1 = instance data
    const bufs = [_]vk.Buffer{ slug_quad_buf, slug_inst_buf };
    const offs = [_]vk.DeviceSize{ 0, 0 };
    env.vkd.cmdBindVertexBuffers(env.cmd, 0, 2, &bufs, &offs);


    // Instanced draw: 6 vertices (unit quad), N instances (one per glyph cell)
    env.vkd.cmdDraw(env.cmd, 6, instance_count, 0, 0);

    // End RT pass — transitions texture back to shader_read_only
    vk_env_end_rt_pass();

    return true;
}

/// Slug draw using upload_cmd — same command buffer as texture uploads.
/// Called immediately after agp_stream_prepare uploads CPU pixels (synchronous,
/// fence waited). The image is in SHADER_READ_ONLY. We record the slug draw
/// into upload_cmd and submit+wait, just like a texture upload. This keeps
/// all operations on the same image serialized on upload_fence, avoiding
/// layout hazards with env.cmd.
export fn vk_env_slug_draw_with_textures(
    pipeline_handle: u64,
    tex_id: u32,
    instance_count: u32,
    curve_tex_id: u32,
    band_tex_id: u32,
) bool {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return false;
    if (instance_count == 0) return true;
    if (tex_id >= MAX_TEXTURES or !env.textures[tex_id].in_use) return false;
    if (slug_quad_buf == .null_handle or slug_inst_buf == .null_handle) return false;

    const slot = &env.textures[tex_id];
    const w = slot.width;
    const h = slot.height;
    if (w == 0 or h == 0) return false;

    const have_slug_textures = (curve_tex_id > 0 and curve_tex_id < MAX_TEXTURES and
        env.textures[curve_tex_id].in_use and
        band_tex_id > 0 and band_tex_id < MAX_TEXTURES and
        env.textures[band_tex_id].in_use);

    // Use upload_cmd — same buffer as texture uploads, serialized on upload_fence
    const cmd = env.upload_cmd;
    env.vkd.resetCommandBuffer(cmd, .{}) catch return false;
    env.vkd.beginCommandBuffer(cmd, &.{ .flags = .{ .one_time_submit_bit = true } }) catch return false;

    // Barrier: SHADER_READ_ONLY → COLOR_ATTACHMENT (image was left in SRO by the upload)
    env.vkd.cmdPipelineBarrier2(cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .all_transfer_bit = true }, .src_access_mask = .{ .transfer_write_bit = true }, .dst_stage_mask = .{ .color_attachment_output_bit = true }, .dst_access_mask = .{ .color_attachment_write_bit = true, .color_attachment_read_bit = true }, .old_layout = .shader_read_only_optimal, .new_layout = .color_attachment_optimal, .image = slot.image, })},
    });

    // Begin rendering into the vstore texture
    env.vkd.cmdBeginRendering(cmd, &.{
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = w, .height = h } },
        .layer_count = 1,
        .color_attachment_count = 1,
        .p_color_attachments = &[_]vk.RenderingAttachmentInfo{.{
            .image_view = slot.view,
            .image_layout = .color_attachment_optimal,
            .resolve_mode = .{},
            .resolve_image_layout = .undefined,
            .load_op = .load,
            .store_op = .store,
            .clear_value = .{ .color = .{ .float_32 = .{ 0, 0, 0, 0 } } },
        }},
        .p_depth_attachment = null,
        .p_stencil_attachment = null,
        .view_mask = 0,
    });

    // Bind pipeline, viewport, scissor, push constants
    const pipeline: vk.Pipeline = @enumFromInt(pipeline_handle);
    env.vkd.cmdBindPipeline(cmd, .graphics, pipeline);

    const fw: f32 = @floatFromInt(w);
    const fh: f32 = @floatFromInt(h);
    env.vkd.cmdSetViewport(cmd, 0, 1, @ptrCast(&vk.Viewport{
        .x = 0, .y = 0, .width = fw, .height = fh, .min_depth = 0, .max_depth = 1,
    }));
    env.vkd.cmdSetScissor(cmd, 0, 1, @ptrCast(&vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = w, .height = h },
    }));

    // Slug shaders expect GLSL std430 layout (252 bytes, vec2 padding at offset 212).
    // Build a padded push constant buffer matching the SPIR-V layout.
    var pc_buf: [252]u8 = std.mem.zeroes([252]u8);
    // opacity at offset 192
    @as(*f32, @ptrCast(@alignCast(pc_buf[192..196].ptr))).* = 1.0;
    // trans_blend at offset 196 — Slug ramp width (ADMM-optimized or default 0.5)
    @as(*f32, @ptrCast(@alignCast(pc_buf[196..200].ptr))).* = 0.5;
    // trans_scale at offset 208
    @as(*f32, @ptrCast(@alignCast(pc_buf[208..212].ptr))).* = 1.0;
    // sz_output at offset 224 (GLSL vec2 aligned)
    @as(*f32, @ptrCast(@alignCast(pc_buf[224..228].ptr))).* = fw;
    @as(*f32, @ptrCast(@alignCast(pc_buf[228..232].ptr))).* = fh;
    // fract_timestamp at GLSL std430 offset 244 — frame counter for temporal AA sample rotation
    @as(*f32, @ptrCast(@alignCast(pc_buf[244..248].ptr))).* = @as(f32, @floatFromInt(frame_counter & 0xFFFF));
    env.vkd.cmdPushConstants(cmd, env.pipeline_layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, 248, @ptrCast(&pc_buf));

    // Bind descriptor sets with curve/band textures
    if (have_slug_textures) {
        const layouts = [_]vk.DescriptorSetLayout{env.descriptor_set_layout};
        var desc_sets: [1]vk.DescriptorSet = undefined;
        env.vkd.allocateDescriptorSets(env.device, &.{
            .descriptor_pool = env.frame_desc_pool,
            .descriptor_set_count = 1,
            .p_set_layouts = &layouts,
        }, &desc_sets) catch {
            env.vkd.cmdEndRendering(cmd);
            env.vkd.endCommandBuffer(cmd) catch {};
            return false;
        };

        env.vkd.updateDescriptorSets(env.device, 4, &[_]vk.WriteDescriptorSet{
            .{ .dst_set = desc_sets[0], .dst_binding = 0, .dst_array_element = 0, .descriptor_count = 1,
               .descriptor_type = .combined_image_sampler,
               .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = env.textures[curve_tex_id].view, .image_layout = .shader_read_only_optimal }},
               .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
            .{ .dst_set = desc_sets[0], .dst_binding = 1, .dst_array_element = 0, .descriptor_count = 1,
               .descriptor_type = .uniform_buffer_dynamic,
               .p_image_info = undefined,
               .p_buffer_info = &[_]vk.DescriptorBufferInfo{.{ .buffer = env.dummy_ubo_buffer, .offset = 0, .range = 256 }},
               .p_texel_buffer_view = undefined },
            .{ .dst_set = desc_sets[0], .dst_binding = 2, .dst_array_element = 0, .descriptor_count = 1,
               .descriptor_type = .combined_image_sampler,
               .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = env.textures[band_tex_id].view, .image_layout = .shader_read_only_optimal }},
               .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
            .{ .dst_set = desc_sets[0], .dst_binding = 3, .dst_array_element = 0, .descriptor_count = 1,
               .descriptor_type = .combined_image_sampler,
               .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = env.textures[0].view, .image_layout = .shader_read_only_optimal }},
               .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
        }, 0, null);

        const zero_offset = [_]u32{0};
        env.vkd.cmdBindDescriptorSets(cmd, .graphics, env.pipeline_layout, 0, 1, @ptrCast(&desc_sets[0]), 1, &zero_offset);
    } else {
        const zero_offset = [_]u32{0};
        env.vkd.cmdBindDescriptorSets(cmd, .graphics, env.pipeline_layout, 0, 1, @ptrCast(&env.textures[0].descriptor_set), 1, &zero_offset);
    }

    // Draw
    const bufs = [_]vk.Buffer{ slug_quad_buf, slug_inst_buf };
    const buf_offs = [_]vk.DeviceSize{ 0, 0 };
    env.vkd.cmdBindVertexBuffers(cmd, 0, 2, &bufs, &buf_offs);
    env.vkd.cmdDraw(cmd, 6, instance_count, 0, 0);

    // End rendering
    env.vkd.cmdEndRendering(cmd);

    // Barrier: COLOR_ATTACHMENT → SHADER_READ_ONLY (ready for composite sampling)
    env.vkd.cmdPipelineBarrier2(cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .color_attachment_output_bit = true }, .src_access_mask = .{ .color_attachment_write_bit = true }, .dst_stage_mask = .{ .fragment_shader_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .color_attachment_optimal, .new_layout = .shader_read_only_optimal, .image = slot.image, })},
    });

    // Submit and wait — serialized on upload_fence, same as texture uploads
    env.vkd.endCommandBuffer(cmd) catch return false;
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{ .command_buffer = cmd, .device_mask = 0 }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = 1, .p_command_buffer_infos = &cmd_info,
    }}, env.upload_fence) catch return false;
    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch {};
    _ = env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch {};

    // Per-glyph PPM dump — always enabled, writes to tests/render_pipeline/output/
    if (instance_count > 5) {
        // Write a marker to prove this code runs
        const marker = std.fs.cwd().createFile("/tmp/slug_dump_reached.txt", .{}) catch null;
        if (marker) |m| {
            defer m.close();
            var mb: [64]u8 = undefined;
            const ms = std.fmt.bufPrint(&mb, "count={d} tex={d}\n", .{ instance_count, tex_id }) catch "?\n";
            m.writeAll(ms) catch {};
        }
        dumpGlyphPPMs(env, slot, w, h, instance_count);
    }

    return true;
}

/// Render glyph instances into SDF atlas for temporal accumulation.
/// Uses upload_cmd, same pattern as vk_env_slug_draw_with_textures.
export fn vk_env_slug_sdf_accumulate(
    pipeline_handle: u64,
    sdf_atlas_tex_id: u32,
    instance_count: u32,
    curve_tex_id: u32,
    band_tex_id: u32,
) bool {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return false;
    if (instance_count == 0) return true;
    if (sdf_atlas_tex_id >= MAX_TEXTURES or !env.textures[sdf_atlas_tex_id].in_use) return false;
    if (slug_quad_buf == .null_handle or slug_inst_buf == .null_handle) return false;

    const slot = &env.textures[sdf_atlas_tex_id];
    const w = slot.width;
    const h = slot.height;
    if (w == 0 or h == 0) return false;

    const have_slug_textures = (curve_tex_id > 0 and curve_tex_id < MAX_TEXTURES and
        env.textures[curve_tex_id].in_use and
        band_tex_id > 0 and band_tex_id < MAX_TEXTURES and
        env.textures[band_tex_id].in_use);
    if (!have_slug_textures) return false;

    const cmd = env.upload_cmd;
    env.vkd.resetCommandBuffer(cmd, .{}) catch return false;
    env.vkd.beginCommandBuffer(cmd, &.{ .flags = .{ .one_time_submit_bit = true } }) catch return false;

    // Barrier: SHADER_READ_ONLY -> COLOR_ATTACHMENT
    env.vkd.cmdPipelineBarrier2(cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .fragment_shader_bit = true }, .src_access_mask = .{ .shader_read_bit = true }, .dst_stage_mask = .{ .color_attachment_output_bit = true }, .dst_access_mask = .{ .color_attachment_write_bit = true, .color_attachment_read_bit = true }, .old_layout = .shader_read_only_optimal, .new_layout = .color_attachment_optimal, .image = slot.image, })},
    });

    // First use: clear. Subsequent: load (EMA accumulates over previous).
    const first_use = !slot.rt_initialized;
    if (first_use) slot.rt_initialized = true;

    env.vkd.cmdBeginRendering(cmd, &.{
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = w, .height = h } },
        .layer_count = 1,
        .color_attachment_count = 1,
        .p_color_attachments = &[_]vk.RenderingAttachmentInfo{.{
            .image_view = slot.view,
            .image_layout = .color_attachment_optimal,
            .resolve_mode = .{},
            .resolve_image_layout = .undefined,
            .load_op = if (first_use) .clear else .load,
            .store_op = .store,
            .clear_value = .{ .color = .{ .float_32 = .{ 0, 0, 0, 0 } } },
        }},
        .p_depth_attachment = null,
        .p_stencil_attachment = null,
        .view_mask = 0,
    });

    const pipeline: vk.Pipeline = @enumFromInt(pipeline_handle);
    env.vkd.cmdBindPipeline(cmd, .graphics, pipeline);

    const fw: f32 = @floatFromInt(w);
    const fh: f32 = @floatFromInt(h);
    env.vkd.cmdSetViewport(cmd, 0, 1, @ptrCast(&vk.Viewport{
        .x = 0, .y = 0, .width = fw, .height = fh, .min_depth = 0, .max_depth = 1,
    }));
    env.vkd.cmdSetScissor(cmd, 0, 1, @ptrCast(&vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = w, .height = h },
    }));

    // Push constants: sz_output = atlas dimensions
    var pc_buf: [252]u8 = std.mem.zeroes([252]u8);
    @as(*f32, @ptrCast(@alignCast(pc_buf[192..196].ptr))).* = 1.0; // opacity
    @as(*f32, @ptrCast(@alignCast(pc_buf[196..200].ptr))).* = slug_ramp_override; // trans_blend = ramp
    @as(*f32, @ptrCast(@alignCast(pc_buf[200..204].ptr))).* = slug_gamma_override; // trans_move = coverage gamma
    @as(*f32, @ptrCast(@alignCast(pc_buf[204..208].ptr))).* = slug_dropout_override; // trans_rotate = dropout blend
    @as(*f32, @ptrCast(@alignCast(pc_buf[208..212].ptr))).* = 1.0; // trans_scale
    @as(*f32, @ptrCast(@alignCast(pc_buf[224..228].ptr))).* = fw; // sz_output.x
    @as(*f32, @ptrCast(@alignCast(pc_buf[228..232].ptr))).* = fh; // sz_output.y
    @as(*f32, @ptrCast(@alignCast(pc_buf[244..248].ptr))).* = @as(f32, @floatFromInt(frame_counter & 0xFFFF));
    env.vkd.cmdPushConstants(cmd, env.pipeline_layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, 248, @ptrCast(&pc_buf));

    // Bind descriptor sets with curve/band textures
    const layouts = [_]vk.DescriptorSetLayout{env.descriptor_set_layout};
    var desc_sets: [1]vk.DescriptorSet = undefined;
    env.vkd.allocateDescriptorSets(env.device, &.{
        .descriptor_pool = env.frame_desc_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = &layouts,
    }, &desc_sets) catch {
        env.vkd.cmdEndRendering(cmd);
        env.vkd.endCommandBuffer(cmd) catch {};
        return false;
    };

    // Write curve (binding 0), dummy UBO (binding 1), band (binding 2), dummy SDF (binding 3)
    env.vkd.updateDescriptorSets(env.device, 4, &[_]vk.WriteDescriptorSet{
        .{ .dst_set = desc_sets[0], .dst_binding = 0, .dst_array_element = 0, .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = env.textures[curve_tex_id].view, .image_layout = .shader_read_only_optimal }},
            .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
        .{ .dst_set = desc_sets[0], .dst_binding = 1, .dst_array_element = 0, .descriptor_count = 1,
            .descriptor_type = .uniform_buffer_dynamic,
            .p_image_info = undefined,
            .p_buffer_info = &[_]vk.DescriptorBufferInfo{.{ .buffer = env.dummy_ubo_buffer, .offset = 0, .range = 256 }},
            .p_texel_buffer_view = undefined },
        .{ .dst_set = desc_sets[0], .dst_binding = 2, .dst_array_element = 0, .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = env.textures[band_tex_id].view, .image_layout = .shader_read_only_optimal }},
            .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
        .{ .dst_set = desc_sets[0], .dst_binding = 3, .dst_array_element = 0, .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = env.textures[0].view, .image_layout = .shader_read_only_optimal }},
            .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
    }, 0, null);

    const zero_offset = [_]u32{0};
    env.vkd.cmdBindDescriptorSets(cmd, .graphics, env.pipeline_layout, 0, 1, @ptrCast(&desc_sets[0]), 1, &zero_offset);

    // Draw
    const bufs = [_]vk.Buffer{ slug_quad_buf, slug_inst_buf };
    const buf_offs = [_]vk.DeviceSize{ 0, 0 };
    env.vkd.cmdBindVertexBuffers(cmd, 0, 2, &bufs, &buf_offs);
    env.vkd.cmdDraw(cmd, 6, instance_count, 0, 0);

    env.vkd.cmdEndRendering(cmd);

    // Barrier: COLOR_ATTACHMENT -> SHADER_READ_ONLY
    env.vkd.cmdPipelineBarrier2(cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .color_attachment_output_bit = true }, .src_access_mask = .{ .color_attachment_write_bit = true }, .dst_stage_mask = .{ .fragment_shader_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .color_attachment_optimal, .new_layout = .shader_read_only_optimal, .image = slot.image, })},
    });

    env.vkd.endCommandBuffer(cmd) catch return false;
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{ .command_buffer = cmd, .device_mask = 0 }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = 1, .p_command_buffer_infos = &cmd_info,
    }}, env.upload_fence) catch return false;
    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch {};
    _ = env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch {};

    return true;
}

/// Single-frame SDF accumulation with a specific ramp value, always clears the target.
/// Used for ADMM Jacobian computation: render coverage at ramp±h into covPlus/covMinus textures.
export fn vk_env_slug_sdf_accum_perturbed(
    pipeline_handle: u64,
    target_tex_id: u32,
    instance_count: u32,
    curve_tex_id: u32,
    band_tex_id: u32,
    ramp_value: f32,
) bool {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return false;
    if (instance_count == 0) return true;
    if (target_tex_id >= MAX_TEXTURES or !env.textures[target_tex_id].in_use) return false;
    if (slug_quad_buf == .null_handle or slug_inst_buf == .null_handle) return false;

    const slot = &env.textures[target_tex_id];
    const w = slot.width;
    const h = slot.height;
    if (w == 0 or h == 0) return false;

    const have_slug_textures = (curve_tex_id > 0 and curve_tex_id < MAX_TEXTURES and
        env.textures[curve_tex_id].in_use and
        band_tex_id > 0 and band_tex_id < MAX_TEXTURES and
        env.textures[band_tex_id].in_use);
    if (!have_slug_textures) return false;

    const cmd = env.upload_cmd;
    env.vkd.resetCommandBuffer(cmd, .{}) catch return false;
    env.vkd.beginCommandBuffer(cmd, &.{ .flags = .{ .one_time_submit_bit = true } }) catch return false;

    // Barrier: SHADER_READ_ONLY -> COLOR_ATTACHMENT
    env.vkd.cmdPipelineBarrier2(cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .fragment_shader_bit = true }, .src_access_mask = .{ .shader_read_bit = true }, .dst_stage_mask = .{ .color_attachment_output_bit = true }, .dst_access_mask = .{ .color_attachment_write_bit = true, .color_attachment_read_bit = true }, .old_layout = .shader_read_only_optimal, .new_layout = .color_attachment_optimal, .image = slot.image, })},
    });

    // Always clear — single-frame snapshot for Jacobian, not temporal EMA
    env.vkd.cmdBeginRendering(cmd, &.{
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = w, .height = h } },
        .layer_count = 1,
        .color_attachment_count = 1,
        .p_color_attachments = &[_]vk.RenderingAttachmentInfo{.{
            .image_view = slot.view,
            .image_layout = .color_attachment_optimal,
            .resolve_mode = .{},
            .resolve_image_layout = .undefined,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .color = .{ .float_32 = .{ 0, 0, 0, 0 } } },
        }},
        .p_depth_attachment = null,
        .p_stencil_attachment = null,
        .view_mask = 0,
    });

    const pipeline: vk.Pipeline = @enumFromInt(pipeline_handle);
    env.vkd.cmdBindPipeline(cmd, .graphics, pipeline);

    const fw: f32 = @floatFromInt(w);
    const fh: f32 = @floatFromInt(h);
    env.vkd.cmdSetViewport(cmd, 0, 1, @ptrCast(&vk.Viewport{
        .x = 0, .y = 0, .width = fw, .height = fh, .min_depth = 0, .max_depth = 1,
    }));
    env.vkd.cmdSetScissor(cmd, 0, 1, @ptrCast(&vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = w, .height = h },
    }));

    // Push constants with perturbed values (ramp from arg, alpha/beta from globals)
    var pc_buf: [252]u8 = std.mem.zeroes([252]u8);
    @as(*f32, @ptrCast(@alignCast(pc_buf[192..196].ptr))).* = 1.0; // opacity
    @as(*f32, @ptrCast(@alignCast(pc_buf[196..200].ptr))).* = ramp_value; // trans_blend = ramp
    @as(*f32, @ptrCast(@alignCast(pc_buf[200..204].ptr))).* = slug_gamma_override; // trans_move = coverage gamma
    @as(*f32, @ptrCast(@alignCast(pc_buf[204..208].ptr))).* = slug_dropout_override; // trans_rotate = dropout blend
    @as(*f32, @ptrCast(@alignCast(pc_buf[208..212].ptr))).* = 1.0; // trans_scale
    @as(*f32, @ptrCast(@alignCast(pc_buf[224..228].ptr))).* = fw; // sz_output.x
    @as(*f32, @ptrCast(@alignCast(pc_buf[228..232].ptr))).* = fh; // sz_output.y
    @as(*f32, @ptrCast(@alignCast(pc_buf[244..248].ptr))).* = @as(f32, @floatFromInt(frame_counter & 0xFFFF));
    env.vkd.cmdPushConstants(cmd, env.pipeline_layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, 248, @ptrCast(&pc_buf));

    // Bind descriptor sets
    const layouts = [_]vk.DescriptorSetLayout{env.descriptor_set_layout};
    var desc_sets: [1]vk.DescriptorSet = undefined;
    env.vkd.allocateDescriptorSets(env.device, &.{
        .descriptor_pool = env.frame_desc_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = &layouts,
    }, &desc_sets) catch {
        env.vkd.cmdEndRendering(cmd);
        env.vkd.endCommandBuffer(cmd) catch {};
        return false;
    };

    env.vkd.updateDescriptorSets(env.device, 4, &[_]vk.WriteDescriptorSet{
        .{ .dst_set = desc_sets[0], .dst_binding = 0, .dst_array_element = 0, .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = env.textures[curve_tex_id].view, .image_layout = .shader_read_only_optimal }},
            .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
        .{ .dst_set = desc_sets[0], .dst_binding = 1, .dst_array_element = 0, .descriptor_count = 1,
            .descriptor_type = .uniform_buffer_dynamic,
            .p_image_info = undefined,
            .p_buffer_info = &[_]vk.DescriptorBufferInfo{.{ .buffer = env.dummy_ubo_buffer, .offset = 0, .range = 256 }},
            .p_texel_buffer_view = undefined },
        .{ .dst_set = desc_sets[0], .dst_binding = 2, .dst_array_element = 0, .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = env.textures[band_tex_id].view, .image_layout = .shader_read_only_optimal }},
            .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
        .{ .dst_set = desc_sets[0], .dst_binding = 3, .dst_array_element = 0, .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = env.textures[0].view, .image_layout = .shader_read_only_optimal }},
            .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
    }, 0, null);

    const zero_offset = [_]u32{0};
    env.vkd.cmdBindDescriptorSets(cmd, .graphics, env.pipeline_layout, 0, 1, @ptrCast(&desc_sets[0]), 1, &zero_offset);

    const bufs = [_]vk.Buffer{ slug_quad_buf, slug_inst_buf };
    const buf_offs = [_]vk.DeviceSize{ 0, 0 };
    env.vkd.cmdBindVertexBuffers(cmd, 0, 2, &bufs, &buf_offs);
    env.vkd.cmdDraw(cmd, 6, instance_count, 0, 0);

    env.vkd.cmdEndRendering(cmd);

    // Barrier: COLOR_ATTACHMENT -> SHADER_READ_ONLY
    env.vkd.cmdPipelineBarrier2(cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .color_attachment_output_bit = true }, .src_access_mask = .{ .color_attachment_write_bit = true }, .dst_stage_mask = .{ .fragment_shader_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .color_attachment_optimal, .new_layout = .shader_read_only_optimal, .image = slot.image, })},
    });

    env.vkd.endCommandBuffer(cmd) catch return false;
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{ .command_buffer = cmd, .device_mask = 0 }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = 1, .p_command_buffer_infos = &cmd_info,
    }}, env.upload_fence) catch return false;
    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch {};
    _ = env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch {};

    return true;
}

/// Read back the SDF atlas R16F texture and dump per-glyph coverage as grayscale PPMs.
/// Each glyph's atlas region is extracted and written to sdf_U{codepoint}_{size}px.ppm.
/// Called from vk_shared.zig after accumulation reaches convergence threshold.
/// SDF entry info from arcan_ttf.zig atlas cache
const SdfEntryInfo = extern struct {
    codepoint: u32,
    sdf_x: u16,
    sdf_y: u16,
    sdf_w: u16,
    sdf_h: u16,
    sample_count: u16,
};
extern fn slug_atlas_iter_sdf(out: [*]SdfEntryInfo, max_entries: u32) u32;

export fn vk_env_dump_sdf_atlas(sdf_atlas_tex_id: u32, _: u32) void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return;
    if (sdf_atlas_tex_id >= MAX_TEXTURES or !env.textures[sdf_atlas_tex_id].in_use) return;

    const slot = &env.textures[sdf_atlas_tex_id];
    const atlas_w = slot.width;
    const atlas_h = slot.height;
    if (atlas_w == 0 or atlas_h == 0) return;

    // R16F = 2 bytes per pixel
    const atlas_bytes: usize = @as(usize, atlas_w) * @as(usize, atlas_h) * 2;
    if (atlas_bytes > STAGING_BUFFER_SIZE) return;

    // Read back atlas texture to staging buffer
    env.vkd.resetCommandBuffer(env.upload_cmd, .{}) catch return;
    env.vkd.beginCommandBuffer(env.upload_cmd, &.{ .flags = .{ .one_time_submit_bit = true } }) catch return;
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .fragment_shader_bit = true }, .src_access_mask = .{ .shader_read_bit = true }, .dst_stage_mask = .{ .all_transfer_bit = true }, .dst_access_mask = .{ .transfer_read_bit = true }, .old_layout = .shader_read_only_optimal, .new_layout = .transfer_src_optimal, .image = slot.image, })},
    });
    env.vkd.cmdCopyImageToBuffer(env.upload_cmd, slot.image, .transfer_src_optimal, env.staging_buffer, 1, &[_]vk.BufferImageCopy{
        fullImageCopyRegion(atlas_w, atlas_h, atlas_w, atlas_h),
    });
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .all_transfer_bit = true }, .src_access_mask = .{ .transfer_read_bit = true }, .dst_stage_mask = .{ .fragment_shader_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .transfer_src_optimal, .new_layout = .shader_read_only_optimal, .image = slot.image, })},
    });
    env.vkd.endCommandBuffer(env.upload_cmd) catch return;
    const ci = [_]vk.CommandBufferSubmitInfo{.{ .command_buffer = env.upload_cmd, .device_mask = 0 }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = 1, .p_command_buffer_infos = &ci,
    }}, env.upload_fence) catch return;
    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch {};
    _ = env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch {};

    const staging: [*]const u8 = @ptrCast(env.staging_mapped orelse return);

    // Get atlas entries with codepoints from arcan_ttf.zig
    var entries: [1024]SdfEntryInfo = undefined;
    const n_entries = slug_atlas_iter_sdf(&entries, 1024);
    var n_written: u32 = 0;

    for (0..n_entries) |i| {
        const e = entries[i];
        const sdf_x: u32 = e.sdf_x;
        const sdf_y: u32 = e.sdf_y;
        const cw: u32 = e.sdf_w;
        const ch: u32 = e.sdf_h;
        if (cw == 0 or ch == 0) continue;
        if (sdf_x + cw > atlas_w or sdf_y + ch > atlas_h) continue;

        var fname_buf: [128]u8 = undefined;
        const sz_label = if (sdf_dump_ptsize > 0) sdf_dump_ptsize else ch;
        const fname = std.fmt.bufPrint(&fname_buf, "tests/render_pipeline/output/sdf_U{X:0>4}_{d}px.ppm", .{ e.codepoint, sz_label }) catch continue;
        const file = std.fs.cwd().createFile(fname, .{}) catch continue;
        defer file.close();

        var hdr_buf: [32]u8 = undefined;
        const hdr = std.fmt.bufPrint(&hdr_buf, "P6\n{d} {d}\n255\n", .{ cw, ch }) catch continue;
        file.writeAll(hdr) catch continue;

        for (0..ch) |row| {
            for (0..cw) |col| {
                const px_off = ((sdf_y + @as(u32, @intCast(row))) * atlas_w + sdf_x + @as(u32, @intCast(col))) * 2;
                const half_bits: u16 = @as(*align(1) const u16, @ptrCast(staging + px_off)).*;
                const coverage = halfToFloat(half_bits);
                const gray: u8 = @intFromFloat(@min(@max(coverage * 255.0, 0.0), 255.0));
                file.writeAll(&[3]u8{ gray, gray, gray }) catch {};
            }
        }
        n_written += 1;
    }
}

/// Convert IEEE 754 half-precision float (16-bit) to single-precision float (32-bit).
fn halfToFloat(h: u16) f32 {
    const sign: u32 = @as(u32, h >> 15) << 31;
    const exp: u32 = (h >> 10) & 0x1F;
    const mant: u32 = h & 0x3FF;
    if (exp == 0) {
        if (mant == 0) return @bitCast(sign); // +/- zero
        // Denormalized: 2^-14 * (mant/1024)
        const f: f32 = @as(f32, @floatFromInt(mant)) / 1024.0;
        return if (sign != 0) -f * (1.0 / 16384.0) else f * (1.0 / 16384.0);
    }
    if (exp == 31) {
        if (mant == 0) return @bitCast(sign | 0x7F800000); // +/- infinity
        return @bitCast(sign | 0x7FC00000); // NaN
    }
    // Normalized: rebase exponent from bias-15 to bias-127
    const f32_bits: u32 = sign | ((@as(u32, exp) + 112) << 23) | (@as(u32, mant) << 13);
    return @bitCast(f32_bits);
}

/// Slug draw with SDF atlas bound at binding 3 (same as vk_env_slug_draw_with_textures
/// but writes 4 descriptor bindings instead of 3).
export fn vk_env_slug_draw_with_sdf(
    pipeline_handle: u64,
    tex_id: u32,
    instance_count: u32,
    curve_tex_id: u32,
    band_tex_id: u32,
    sdf_atlas_tex_id: u32,
) bool {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return false;
    if (instance_count == 0) return true;
    if (tex_id >= MAX_TEXTURES or !env.textures[tex_id].in_use) return false;
    if (slug_quad_buf == .null_handle or slug_inst_buf == .null_handle) return false;

    const slot = &env.textures[tex_id];
    const w = slot.width;
    const h = slot.height;
    if (w == 0 or h == 0) return false;

    const have_slug_textures = (curve_tex_id > 0 and curve_tex_id < MAX_TEXTURES and
        env.textures[curve_tex_id].in_use and
        band_tex_id > 0 and band_tex_id < MAX_TEXTURES and
        env.textures[band_tex_id].in_use);

    const have_sdf = (sdf_atlas_tex_id > 0 and sdf_atlas_tex_id < MAX_TEXTURES and
        env.textures[sdf_atlas_tex_id].in_use);

    // Use upload_cmd — same buffer as texture uploads, serialized on upload_fence
    const cmd = env.upload_cmd;
    env.vkd.resetCommandBuffer(cmd, .{}) catch return false;
    env.vkd.beginCommandBuffer(cmd, &.{ .flags = .{ .one_time_submit_bit = true } }) catch return false;

    // Barrier: SHADER_READ_ONLY -> COLOR_ATTACHMENT (image was left in SRO by the upload)
    env.vkd.cmdPipelineBarrier2(cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .all_transfer_bit = true }, .src_access_mask = .{ .transfer_write_bit = true }, .dst_stage_mask = .{ .color_attachment_output_bit = true }, .dst_access_mask = .{ .color_attachment_write_bit = true, .color_attachment_read_bit = true }, .old_layout = .shader_read_only_optimal, .new_layout = .color_attachment_optimal, .image = slot.image, })},
    });

    // Begin rendering into the vstore texture
    env.vkd.cmdBeginRendering(cmd, &.{
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = w, .height = h } },
        .layer_count = 1,
        .color_attachment_count = 1,
        .p_color_attachments = &[_]vk.RenderingAttachmentInfo{.{
            .image_view = slot.view,
            .image_layout = .color_attachment_optimal,
            .resolve_mode = .{},
            .resolve_image_layout = .undefined,
            .load_op = .load,
            .store_op = .store,
            .clear_value = .{ .color = .{ .float_32 = .{ 0, 0, 0, 0 } } },
        }},
        .p_depth_attachment = null,
        .p_stencil_attachment = null,
        .view_mask = 0,
    });

    // Bind pipeline, viewport, scissor, push constants
    const pipeline: vk.Pipeline = @enumFromInt(pipeline_handle);
    env.vkd.cmdBindPipeline(cmd, .graphics, pipeline);

    const fw: f32 = @floatFromInt(w);
    const fh: f32 = @floatFromInt(h);
    env.vkd.cmdSetViewport(cmd, 0, 1, @ptrCast(&vk.Viewport{
        .x = 0, .y = 0, .width = fw, .height = fh, .min_depth = 0, .max_depth = 1,
    }));
    env.vkd.cmdSetScissor(cmd, 0, 1, @ptrCast(&vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = w, .height = h },
    }));

    // Slug shaders expect GLSL std430 layout (252 bytes, vec2 padding at offset 212).
    var pc_buf: [252]u8 = std.mem.zeroes([252]u8);
    @as(*f32, @ptrCast(@alignCast(pc_buf[192..196].ptr))).* = 1.0; // opacity
    @as(*f32, @ptrCast(@alignCast(pc_buf[196..200].ptr))).* = slug_ramp_override; // trans_blend = ramp
    @as(*f32, @ptrCast(@alignCast(pc_buf[200..204].ptr))).* = slug_gamma_override; // trans_move = coverage gamma
    @as(*f32, @ptrCast(@alignCast(pc_buf[204..208].ptr))).* = slug_dropout_override; // trans_rotate = dropout blend
    @as(*f32, @ptrCast(@alignCast(pc_buf[208..212].ptr))).* = 1.0; // trans_scale
    @as(*f32, @ptrCast(@alignCast(pc_buf[224..228].ptr))).* = fw; // sz_output.x
    @as(*f32, @ptrCast(@alignCast(pc_buf[228..232].ptr))).* = fh; // sz_output.y
    @as(*f32, @ptrCast(@alignCast(pc_buf[244..248].ptr))).* = @as(f32, @floatFromInt(frame_counter & 0xFFFF));
    env.vkd.cmdPushConstants(cmd, env.pipeline_layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, 248, @ptrCast(&pc_buf));

    // Bind descriptor sets with curve/band textures + SDF atlas
    if (have_slug_textures) {
        const layouts = [_]vk.DescriptorSetLayout{env.descriptor_set_layout};
        var desc_sets: [1]vk.DescriptorSet = undefined;
        env.vkd.allocateDescriptorSets(env.device, &.{
            .descriptor_pool = env.frame_desc_pool,
            .descriptor_set_count = 1,
            .p_set_layouts = &layouts,
        }, &desc_sets) catch {
            env.vkd.cmdEndRendering(cmd);
            env.vkd.endCommandBuffer(cmd) catch {};
            return false;
        };

        // SDF atlas view: use actual atlas if available, otherwise dummy texture 0
        const sdf_view = if (have_sdf) env.textures[sdf_atlas_tex_id].view else env.textures[0].view;

        env.vkd.updateDescriptorSets(env.device, 4, &[_]vk.WriteDescriptorSet{
            .{ .dst_set = desc_sets[0], .dst_binding = 0, .dst_array_element = 0, .descriptor_count = 1,
                .descriptor_type = .combined_image_sampler,
                .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = env.textures[curve_tex_id].view, .image_layout = .shader_read_only_optimal }},
                .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
            .{ .dst_set = desc_sets[0], .dst_binding = 1, .dst_array_element = 0, .descriptor_count = 1,
                .descriptor_type = .uniform_buffer_dynamic,
                .p_image_info = undefined,
                .p_buffer_info = &[_]vk.DescriptorBufferInfo{.{ .buffer = env.dummy_ubo_buffer, .offset = 0, .range = 256 }},
                .p_texel_buffer_view = undefined },
            .{ .dst_set = desc_sets[0], .dst_binding = 2, .dst_array_element = 0, .descriptor_count = 1,
                .descriptor_type = .combined_image_sampler,
                .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = env.textures[band_tex_id].view, .image_layout = .shader_read_only_optimal }},
                .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
            .{ .dst_set = desc_sets[0], .dst_binding = 3, .dst_array_element = 0, .descriptor_count = 1,
                .descriptor_type = .combined_image_sampler,
                .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = sdf_view, .image_layout = .shader_read_only_optimal }},
                .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
        }, 0, null);

        const zero_offset = [_]u32{0};
        env.vkd.cmdBindDescriptorSets(cmd, .graphics, env.pipeline_layout, 0, 1, @ptrCast(&desc_sets[0]), 1, &zero_offset);
    } else {
        const zero_offset = [_]u32{0};
        env.vkd.cmdBindDescriptorSets(cmd, .graphics, env.pipeline_layout, 0, 1, @ptrCast(&env.textures[0].descriptor_set), 1, &zero_offset);
    }

    // Draw
    const bufs = [_]vk.Buffer{ slug_quad_buf, slug_inst_buf };
    const buf_offs = [_]vk.DeviceSize{ 0, 0 };
    env.vkd.cmdBindVertexBuffers(cmd, 0, 2, &bufs, &buf_offs);
    env.vkd.cmdDraw(cmd, 6, instance_count, 0, 0);

    // End rendering
    env.vkd.cmdEndRendering(cmd);

    // Barrier: COLOR_ATTACHMENT -> SHADER_READ_ONLY (ready for composite sampling)
    env.vkd.cmdPipelineBarrier2(cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .color_attachment_output_bit = true }, .src_access_mask = .{ .color_attachment_write_bit = true }, .dst_stage_mask = .{ .fragment_shader_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .color_attachment_optimal, .new_layout = .shader_read_only_optimal, .image = slot.image, })},
    });

    // Submit and wait — serialized on upload_fence, same as texture uploads
    env.vkd.endCommandBuffer(cmd) catch return false;
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{ .command_buffer = cmd, .device_mask = 0 }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = 1, .p_command_buffer_infos = &cmd_info,
    }}, env.upload_fence) catch return false;
    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch {};
    _ = env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch {};

    return true;
}

/// Read back the vstore after GPU slug draw and write per-glyph PPMs.
/// Each glyph cell gets its own file: gpu_U{codepoint}_{fontsize}px.ppm
fn dumpGlyphPPMs(env: *VkEnv, slot: *const TextureSlot, w: u32, h: u32, instance_count: u32) void {
    // Read back the full vstore via upload_cmd
    env.vkd.resetCommandBuffer(env.upload_cmd, .{}) catch return;
    env.vkd.beginCommandBuffer(env.upload_cmd, &.{ .flags = .{ .one_time_submit_bit = true } }) catch return;
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .fragment_shader_bit = true }, .src_access_mask = .{ .shader_read_bit = true }, .dst_stage_mask = .{ .all_transfer_bit = true }, .dst_access_mask = .{ .transfer_read_bit = true }, .old_layout = .shader_read_only_optimal, .new_layout = .transfer_src_optimal, .image = slot.image, })},
    });
    env.vkd.cmdCopyImageToBuffer(env.upload_cmd, slot.image, .transfer_src_optimal, env.staging_buffer, 1, &[_]vk.BufferImageCopy{
        fullImageCopyRegion(w, h, w, h),
    });
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .all_transfer_bit = true }, .src_access_mask = .{ .transfer_read_bit = true }, .dst_stage_mask = .{ .fragment_shader_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .transfer_src_optimal, .new_layout = .shader_read_only_optimal, .image = slot.image, })},
    });
    env.vkd.endCommandBuffer(env.upload_cmd) catch return;
    const ci = [_]vk.CommandBufferSubmitInfo{.{ .command_buffer = env.upload_cmd, .device_mask = 0 }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = 1, .p_command_buffer_infos = &ci,
    }}, env.upload_fence) catch return;
    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch {};
    _ = env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch {};

    const staging = env.staging_mapped orelse return;

    // Get font size from env
    // Iterate instance buffer and extract per-glyph cells
    const inst_data: [*]const u8 = @ptrCast(slug_inst_mapped orelse return);
    var n_written: u32 = 0;

    for (0..instance_count) |i| {
        const inst_off = i * 96;
        // Read cell_pos (offset 0, [2]f32), cell_size (offset 8, [2]f32), glyph_data[3] (offset 60, i32)
        const cx: i32 = @intFromFloat(@as(*const f32, @ptrCast(@alignCast(inst_data + inst_off + 0))).*);
        const cy: i32 = @intFromFloat(@as(*const f32, @ptrCast(@alignCast(inst_data + inst_off + 4))).*);
        const cw_f: f32 = @as(*const f32, @ptrCast(@alignCast(inst_data + inst_off + 8))).*;
        const ch_f: f32 = @as(*const f32, @ptrCast(@alignCast(inst_data + inst_off + 12))).*;
        const gd3: i32 = @as(*const i32, @ptrCast(@alignCast(inst_data + inst_off + 60))).*;
        const codepoint: u32 = @intCast((gd3 >> 16) & 0xFFFF);

        if (codepoint == 0 or cw_f <= 0 or ch_f <= 0) continue;

        const cw: u32 = @intFromFloat(cw_f);
        const ch: u32 = @intFromFloat(ch_f);
        if (cx < 0 or cy < 0) continue;
        const ux: u32 = @intCast(cx);
        const uy: u32 = @intCast(cy);
        if (ux + cw > w or uy + ch > h) continue;

        // Write PPM
        var fname_buf: [128]u8 = undefined;
        const fname = std.fmt.bufPrint(&fname_buf, "tests/render_pipeline/output/gpu_U{X:0>4}_{d}px.ppm", .{ codepoint, ch }) catch continue;

        const file = std.fs.cwd().createFile(fname, .{}) catch continue;
        defer file.close();

        var hdr_buf: [32]u8 = undefined;
        const hdr = std.fmt.bufPrint(&hdr_buf, "P6\n{d} {d}\n255\n", .{ cw, ch }) catch continue;
        file.writeAll(hdr) catch continue;

        for (0..ch) |row| {
            for (0..cw) |col| {
                const px_off = ((uy + @as(u32, @intCast(row))) * w + ux + @as(u32, @intCast(col))) * 4;
                const r = staging[px_off];
                const g = staging[px_off + 1];
                const b = staging[px_off + 2];
                file.writeAll(&[3]u8{ r, g, b }) catch {};
            }
        }
        n_written += 1;
    }
}

fn createTextureInternal(
    env: *VkEnv,
    w: u32,
    h: u32,
    pixels: ?[*]const u8,
) !TextureSlot {
    return createTextureInternalFmt(env, w, h, pixels, .r8g8b8a8_unorm, 4, true);
}

fn createTextureInternalFmt(
    env: *VkEnv,
    w: u32,
    h: u32,
    pixels: ?[*]const u8,
    format: vk.Format,
    bytes_per_pixel: u32,
    swizzle_bgra: bool,
) !TextureSlot {
    rcdbg("CTI-entry");
    const image = env.vkd.createImage(env.device, &.{
        .image_type = .@"2d",
        .format = format,
        .extent = .{ .width = w, .height = h, .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = .{ .transfer_dst_bit = true, .sampled_bit = true, .color_attachment_bit = true, .transfer_src_bit = true },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    }, null) catch return error.ImageCreateFailed;

    rcdbg("CTI-img");
    // Allocate device-local memory.
    // vk-zig's wrapper does `var out = undefined; fn(&out); return out;` —
    // the SH backend miscompiles the 24B extern-struct return-by-value
    // (same class of bug as `getPhysicalDeviceMemoryProperties` at
    // initPhase2 entry). Call the dispatch pointer directly so the ICD
    // writes straight into `mem_req`.
    var mem_req: vk.MemoryRequirements = undefined;
    env.vkd.dispatch.vkGetImageMemoryRequirements.?(env.device, image, &mem_req);
    const mem_type = findMemoryType(env, mem_req.memory_type_bits, .{ .device_local_bit = true }) orelse
        return error.NoSuitableMemory;
    const memory = env.vkd.allocateMemory(env.device, &.{
        .allocation_size = mem_req.size,
        .memory_type_index = mem_type,
    }, null) catch return error.MemoryAllocFailed;
    env.vkd.bindImageMemory(env.device, image, memory, 0) catch return error.BindMemoryFailed;

    rcdbg("CTI-bind");
    // Create image view — must match image format
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

    // Allocate descriptor set
    const layouts = [_]vk.DescriptorSetLayout{env.descriptor_set_layout};
    var desc_sets: [1]vk.DescriptorSet = undefined;
    env.vkd.allocateDescriptorSets(env.device, &.{
        .descriptor_pool = env.descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = &layouts,
    }, &desc_sets) catch return error.DescriptorAllocFailed;

    rcdbg("CTI-descalloc");
    // Update descriptor set — must write ALL 4 bindings so the driver doesn't
    // access uninitialized descriptors (causes crash on Asahi AGX).
    // Use nearest sampling for data textures (f16/u16), linear for visual.
    const sampler = if (format == .r8g8b8a8_unorm) env.sampler_linear else env.sampler_nearest;
    const image_info = [_]vk.DescriptorImageInfo{.{
        .sampler = sampler,
        .image_view = view,
        .image_layout = .shader_read_only_optimal,
    }};
    const dummy_ubo_info = [_]vk.DescriptorBufferInfo{.{
        .buffer = env.dummy_ubo_buffer,
        .offset = 0,
        .range = 256,
    }};
    env.vkd.updateDescriptorSets(env.device, 4, &[_]vk.WriteDescriptorSet{
        .{
            .dst_set = desc_sets[0],
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &image_info,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = desc_sets[0],
            .dst_binding = 1,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .uniform_buffer_dynamic,
            .p_image_info = undefined,
            .p_buffer_info = &dummy_ubo_info,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = desc_sets[0],
            .dst_binding = 2,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &image_info, // same texture for binding 2
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = desc_sets[0],
            .dst_binding = 3,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &image_info, // same texture for binding 3 (SDF atlas placeholder)
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
    }, 0, null);

    rcdbg("CTI-descset");
    // Upload initial pixels if provided
    if (pixels) |px| {
        rcdbg("CTI-preupload");
        try uploadTexturePixelsFmt(env, image, w, h, px, bytes_per_pixel, swizzle_bgra);
        rcdbg("CTI-postupload");
    } else {
        // Transition to shader_read_only even without data
        try transitionImageLayout(env, image, .undefined, .shader_read_only_optimal);
    }

    rcdbg("CTI-return");
    return TextureSlot{
        .image = image,
        .view = view,
        .memory = memory,
        .descriptor_set = desc_sets[0],
        .width = w,
        .height = h,
        .in_use = true,
    };
}

// DRM Format → VkFormat mapping
fn drmFormatToVk(drm_format: u32) ?vk.Format {
    return switch (drm_format) {
        0x34325241 => .b8g8r8a8_unorm, // DRM_FORMAT_ARGB8888
        0x34325258 => .b8g8r8a8_unorm, // DRM_FORMAT_XRGB8888
        0x34324241 => .r8g8b8a8_unorm, // DRM_FORMAT_ABGR8888
        0x34324258 => .r8g8b8a8_unorm, // DRM_FORMAT_XBGR8888
        0x30334241 => .a2b10g10r10_unorm_pack32, // DRM_FORMAT_ABGR2101010 (AB30)
        0x30334258 => .a2b10g10r10_unorm_pack32, // DRM_FORMAT_XBGR2101010 (XB30)
        0x30335241 => .a2r10g10b10_unorm_pack32, // DRM_FORMAT_ARGB2101010 (AR30)
        0x30335258 => .a2r10g10b10_unorm_pack32, // DRM_FORMAT_XRGB2101010 (XR30)
        else => null,
    };
}

// DMA-BUF Import
// Import a DMA-BUF file descriptor as a Vulkan texture using
// VK_KHR_external_memory_fd + VK_EXT_external_memory_dma_buf +
// VK_EXT_image_drm_format_modifier.
//
// Uses the "list" approach: query all modifiers the driver supports for this
// format and let the driver pick the one that matches the imported memory.
// This is zero-copy and works even when the exporter reports DRM_FORMAT_MOD_INVALID
// (same GPU / same driver on both sides).

const DmaBufResources = struct {
    image: vk.Image,
    view: vk.ImageView,
    memory: vk.DeviceMemory,
};

/// Create VkImage + VkDeviceMemory + VkImageView from a DMA-BUF fd.
/// Does NOT allocate descriptor sets or transition layout.
fn createDmaBufResources(
    env: *VkEnv,
    fd: c_int,
    w: u32,
    h: u32,
    stride: u64,
    offset: u64,
    drm_format: u32,
    modifier: u64,
) !DmaBufResources {
    const vk_format = drmFormatToVk(drm_format) orelse return error.UnsupportedFormat;

    // Query which memory types can import this fd
    var fd_props = vk.MemoryFdPropertiesKHR{
        .memory_type_bits = 0,
    };
    env.vkd.getMemoryFdPropertiesKHR(
        env.device,
        .{ .dma_buf_bit_ext = true },
        fd,
        &fd_props,
    ) catch return error.FdPropsQueryFailed;

    if (fd_props.memory_type_bits == 0) return error.NoCompatibleMemoryType;

    // Query supported DRM format modifiers for this Vulkan format.
    // The driver returns all modifier+feature combos it supports.
    var mod_list = vk.DrmFormatModifierPropertiesListEXT{};
    var fmt_props2 = vk.FormatProperties2{
        .p_next = @ptrCast(&mod_list),
        .format_properties = undefined,
    };
    env.vki.getPhysicalDeviceFormatProperties2(env.physical_device, vk_format, &fmt_props2);

    const mod_count = mod_list.drm_format_modifier_count;
    if (mod_count == 0) return error.UnsupportedFormat;

    // Second call: get the actual modifier properties
    var mod_props_buf: [16]vk.DrmFormatModifierPropertiesEXT = undefined;
    if (mod_count > mod_props_buf.len) return error.UnsupportedFormat;
    mod_list.p_drm_format_modifier_properties = &mod_props_buf;
    env.vki.getPhysicalDeviceFormatProperties2(env.physical_device, vk_format, &fmt_props2);

    // Build list of modifier values that support SAMPLED_BIT
    var mod_values: [16]u64 = undefined;
    var usable_count: u32 = 0;
    for (mod_props_buf[0..mod_count]) |prop| {
        if (prop.drm_format_modifier_tiling_features.sampled_image_bit) {
            mod_values[usable_count] = prop.drm_format_modifier;
            usable_count += 1;
        }
    }
    if (usable_count == 0) return error.UnsupportedFormat;

    // Determine if caller provided a valid (non-INVALID) DRM format modifier.
    // When the exporter (e.g. gamescope) creates images with VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT,
    // the exported DMA-BUF carries the real modifier (e.g. APPLE_GPU_TILED on Asahi).
    // We use the EXPLICIT create info to import with the exact modifier + stride/offset.
    const drm_format_mod_invalid: u64 = (1 << 56) - 1;
    const has_explicit_modifier = modifier != drm_format_mod_invalid and modifier != 0xffffffffffffffff;

    // Validate that the explicit modifier is supported for sampling on this device
    var use_explicit = has_explicit_modifier;
    if (use_explicit) {
        var supported = false;
        for (mod_props_buf[0..mod_count]) |prop| {
            if (prop.drm_format_modifier == modifier) {
                supported = prop.drm_format_modifier_tiling_features.sampled_image_bit;
                break;
            }
        }
        if (!supported) {
            use_explicit = false;
        }
    }

    // Explicit path: import with the exact modifier + stride/offset from exporter.
    // This is correct for DMA-BUF import — the exporter allocated with a specific
    // modifier and the importer must match it exactly.
    var plane_layout = [_]vk.SubresourceLayout{.{
        .offset = offset,
        .size = 0, // ignored for DRM modifier images per Vulkan spec
        .row_pitch = stride,
        .array_pitch = 0,
        .depth_pitch = 0,
    }};
    var drm_mod_explicit = vk.ImageDrmFormatModifierExplicitCreateInfoEXT{
        .drm_format_modifier = modifier,
        .drm_format_modifier_plane_count = 1,
        .p_plane_layouts = &plane_layout,
    };

    // List fallback: let driver pick from supported modifiers (for INVALID modifier).
    // Put caller's modifier first in the list if it's in the supported set.
    if (!use_explicit) {
        if (has_explicit_modifier) {
            for (0..usable_count) |i| {
                if (mod_values[i] == modifier) {
                    mod_values[i] = mod_values[0];
                    mod_values[0] = modifier;
                    break;
                }
            }
        }
    }
    var drm_mod_list = vk.ImageDrmFormatModifierListCreateInfoEXT{
        .drm_format_modifier_count = usable_count,
        .p_drm_format_modifiers = &mod_values,
    };

    const drm_pnext: *const anyopaque = if (use_explicit) @ptrCast(&drm_mod_explicit) else @ptrCast(&drm_mod_list);
    const ext_mem_info = vk.ExternalMemoryImageCreateInfo{
        .p_next = drm_pnext,
        .handle_types = .{ .dma_buf_bit_ext = true },
    };

    const image = env.vkd.createImage(env.device, &.{
        .p_next = &ext_mem_info,
        .image_type = .@"2d",
        .format = vk_format,
        .extent = .{ .width = w, .height = h, .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .drm_format_modifier_ext,
        .usage = .{ .sampled_bit = true },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    }, null) catch return error.ImageCreateFailed;
    errdefer env.vkd.destroyImage(env.device, image, null);

    // Get memory requirements and intersect with fd-compatible types
    const mem_req = env.vkd.getImageMemoryRequirements(env.device, image);
    const compatible_bits = mem_req.memory_type_bits & fd_props.memory_type_bits;
    if (compatible_bits == 0) return error.NoCompatibleMemoryType;

    // Find a memory type from the compatible set (prefer device-local)
    const mem_type = findMemoryType(env, compatible_bits, .{ .device_local_bit = true }) orelse
        findMemoryType(env, compatible_bits, .{}) orelse
        return error.NoSuitableMemory;

    // Import the fd — Vulkan takes ownership on success
    const import_fd_info = vk.ImportMemoryFdInfoKHR{
        .handle_type = .{ .dma_buf_bit_ext = true },
        .fd = fd,
    };
    const memory = env.vkd.allocateMemory(env.device, &.{
        .p_next = &import_fd_info,
        .allocation_size = mem_req.size,
        .memory_type_index = mem_type,
    }, null) catch return error.MemoryAllocFailed;
    // After this point, fd is owned by Vulkan — don't close it on error
    errdefer env.vkd.freeMemory(env.device, memory, null);

    env.vkd.bindImageMemory(env.device, image, memory, 0) catch return error.BindMemoryFailed;

    // Create image view
    const view = env.vkd.createImageView(env.device, &.{
        .image = image,
        .view_type = .@"2d",
        .format = vk_format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null) catch return error.ImageViewCreateFailed;

    return DmaBufResources{
        .image = image,
        .view = view,
        .memory = memory,
    };
}

fn importTextureFromDmaBuf(
    env: *VkEnv,
    fd: c_int,
    w: u32,
    h: u32,
    stride: u64,
    offset: u64,
    drm_format: u32,
    modifier: u64,
) !TextureSlot {
    const res = try createDmaBufResources(env, fd, w, h, stride, offset, drm_format, modifier);
    // On error below, clean up the resources we just created
    errdefer {
        env.vkd.destroyImageView(env.device, res.view, null);
        env.vkd.destroyImage(env.device, res.image, null);
        env.vkd.freeMemory(env.device, res.memory, null);
    }

    // Allocate and update descriptor set (all 3 bindings for Asahi)
    const layouts = [_]vk.DescriptorSetLayout{env.descriptor_set_layout};
    var desc_sets: [1]vk.DescriptorSet = undefined;
    env.vkd.allocateDescriptorSets(env.device, &.{
        .descriptor_pool = env.descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = &layouts,
    }, &desc_sets) catch return error.DescriptorAllocFailed;

    updateDescriptorSetForTexture(env, desc_sets[0], res.view);

    // Transition to shader_read_only_optimal (UNDEFINED is required for DRM modifier tiling)
    try transitionImageLayout(env, res.image, .undefined, .shader_read_only_optimal);

    // Host→shader barrier: the client already wrote pixels via mmap before the import.
    // The layout transition alone doesn't make host writes visible to the shader.
    if (env.cmd_recording) {
        const mem_barrier = [_]vk.MemoryBarrier2{.{
            .src_stage_mask = .{ .host_bit = true },
            .src_access_mask = .{ .host_write_bit = true },
            .dst_stage_mask = .{ .fragment_shader_bit = true },
            .dst_access_mask = .{ .shader_read_bit = true },
        }};
        env.vkd.cmdPipelineBarrier2(env.cmd, &.{
            .memory_barrier_count = mem_barrier.len,
            .p_memory_barriers = &mem_barrier,
        });
    }

    return TextureSlot{
        .image = res.image,
        .view = res.view,
        .memory = res.memory,
        .descriptor_set = desc_sets[0],
        .width = w,
        .height = h,
        .in_use = true,
        .imported_dmabuf = true,
    };
}

/// Write all 4 descriptor bindings (sampler at 0+2+3, UBO at 1) for a texture view.
fn updateDescriptorSetForTexture(env: *VkEnv, desc_set: vk.DescriptorSet, view: vk.ImageView) void {
    const image_info = [_]vk.DescriptorImageInfo{.{
        .sampler = env.sampler_linear,
        .image_view = view,
        .image_layout = .shader_read_only_optimal,
    }};
    const dummy_ubo_info = [_]vk.DescriptorBufferInfo{.{
        .buffer = env.dummy_ubo_buffer,
        .offset = 0,
        .range = 256,
    }};
    env.vkd.updateDescriptorSets(env.device, 4, &[_]vk.WriteDescriptorSet{
        .{
            .dst_set = desc_set,
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &image_info,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = desc_set,
            .dst_binding = 1,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .uniform_buffer_dynamic,
            .p_image_info = undefined,
            .p_buffer_info = &dummy_ubo_info,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = desc_set,
            .dst_binding = 2,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &image_info,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = desc_set,
            .dst_binding = 3,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &image_info,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
    }, 0, null);
}

// Helper: transition image layout
fn transitionImageLayout(
    env: *VkEnv,
    image: vk.Image,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
) !void {
    env.vkd.resetCommandBuffer(env.upload_cmd, .{}) catch return error.CmdResetFailed;
    env.vkd.beginCommandBuffer(env.upload_cmd, &.{
        .flags = .{ .one_time_submit_bit = true },
    }) catch return error.CmdBeginFailed;

    var src_stage: vk.PipelineStageFlags2 = .{ .top_of_pipe_bit = true };
    var src_access: vk.AccessFlags2 = .{};
    var dst_stage: vk.PipelineStageFlags2 = .{ .fragment_shader_bit = true };
    var dst_access: vk.AccessFlags2 = .{ .shader_read_bit = true };

    if (old_layout == .transfer_dst_optimal) {
        src_stage = .{ .all_transfer_bit = true };
        src_access = .{ .transfer_write_bit = true };
    }
    if (new_layout == .transfer_dst_optimal) {
        dst_stage = .{ .all_transfer_bit = true };
        dst_access = .{ .transfer_write_bit = true };
    }

    const barrier = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = src_stage, .src_access_mask = src_access, .dst_stage_mask = dst_stage, .dst_access_mask = dst_access, .old_layout = old_layout, .new_layout = new_layout, .image = image, })};
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = barrier.len,
        .p_image_memory_barriers = &barrier,
    });

    env.vkd.endCommandBuffer(env.upload_cmd) catch return error.CmdEndFailed;

    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{
        .command_buffer = env.upload_cmd,
        .device_mask = 0,
    }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = cmd_info.len,
        .p_command_buffer_infos = &cmd_info,
    }}, env.upload_fence) catch return error.SubmitFailed;

    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch
        return error.FenceWaitFailed;
    _ = env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch
        return error.FenceResetFailed;
}

// Helper: upload pixels to texture via staging buffer
fn uploadTexturePixels(
    env: *VkEnv,
    image: vk.Image,
    w: u32,
    h: u32,
    pixels: [*]const u8,
) !void {
    return uploadTexturePixelsFmt(env, image, w, h, pixels, 4, true);
}

// SH backend leaves nested-struct fields of vk.zig struct literals
// uninitialized when an outer `.{ ... }` literal assigns nested `.{ ... }`
// initializers to those fields. Concretely, for `vk.BufferImageCopy{.{ ... }}`
// the middle 28 bytes (image_subresource + image_offset) are garbage; for
// `vk.ImageMemoryBarrier2{.{ ... }}` the first 16 bytes of subresource_range
// are garbage. Mesa derefs the garbage subresource and either crashes
// (cmdCopyBufferToImage) or transitions the wrong aspect/level (the barrier
// path silently breaks layout transitions, which is why text stopped
// rendering after the buffer-copy crash was fixed).
//
// Workaround: build the struct via field-by-field assignment on a `var`
// declared `undefined`. The backend handles per-field stores correctly
// even though it miscompiles the literal-init path for these particular
// vk.zig types (likely tied to FlagsMixin comptime decls inside
// ImageAspectFlags / PipelineStageFlags2 / etc.).
fn fullColorSubresourceRange() vk.ImageSubresourceRange {
    var sr: vk.ImageSubresourceRange = undefined;
    sr.aspect_mask = .{ .color_bit = true };
    sr.base_mip_level = 0;
    sr.level_count = 1;
    sr.base_array_layer = 0;
    sr.layer_count = 1;
    return sr;
}

fn fullColorSubresourceLayers() vk.ImageSubresourceLayers {
    var sl: vk.ImageSubresourceLayers = undefined;
    sl.aspect_mask = .{ .color_bit = true };
    sl.mip_level = 0;
    sl.base_array_layer = 0;
    sl.layer_count = 1;
    return sl;
}

fn fullImageCopyRegion(buffer_row_length: u32, buffer_image_height: u32, w: u32, h: u32) vk.BufferImageCopy {
    var r: vk.BufferImageCopy = undefined;
    r.buffer_offset = 0;
    r.buffer_row_length = buffer_row_length;
    r.buffer_image_height = buffer_image_height;
    r.image_subresource = fullColorSubresourceLayers();
    r.image_offset.x = 0;
    r.image_offset.y = 0;
    r.image_offset.z = 0;
    r.image_extent.width = w;
    r.image_extent.height = h;
    r.image_extent.depth = 1;
    return r;
}

// Convenience: build a full-color, single-layer image-memory barrier with
// the subresource_range fully populated (the literal form leaves it as
// stack garbage on the SH backend — see fullColorSubresourceRange's note).
const ImageBarrierArgs = struct {
    src_stage_mask: vk.PipelineStageFlags2 = .{},
    src_access_mask: vk.AccessFlags2 = .{},
    dst_stage_mask: vk.PipelineStageFlags2 = .{},
    dst_access_mask: vk.AccessFlags2 = .{},
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
    image: vk.Image,
};

fn fullColorImageBarrier(args: ImageBarrierArgs) vk.ImageMemoryBarrier2 {
    var b: vk.ImageMemoryBarrier2 = undefined;
    b.s_type = .image_memory_barrier_2;
    b.p_next = null;
    b.src_stage_mask = args.src_stage_mask;
    b.src_access_mask = args.src_access_mask;
    b.dst_stage_mask = args.dst_stage_mask;
    b.dst_access_mask = args.dst_access_mask;
    b.old_layout = args.old_layout;
    b.new_layout = args.new_layout;
    b.src_queue_family_index = vk.QUEUE_FAMILY_IGNORED;
    b.dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED;
    b.image = args.image;
    b.subresource_range = fullColorSubresourceRange();
    return b;
}

fn uploadTexturePixelsFmt(
    env: *VkEnv,
    image: vk.Image,
    w: u32,
    h: u32,
    pixels: [*]const u8,
    bytes_per_pixel: u32,
    swizzle_bgra: bool,
) !void {
    const size: usize = @as(usize, w) * @as(usize, h) * @as(usize, bytes_per_pixel);
    if (size > STAGING_BUFFER_SIZE) return error.TextureTooLarge;

    const staging = env.staging_mapped orelse return error.StagingNotMapped;
    rcdbg("UPL-staging");

    if (swizzle_bgra and bytes_per_pixel == 4) {
        // BGRA→RGBA swizzle for arcan's shmif_pixel format
        const n_pixels = @as(usize, w) * @as(usize, h);
        var i: usize = 0;
        while (i < n_pixels) : (i += 1) {
            const off = i * 4;
            staging[off + 0] = pixels[off + 2]; // R ← byte 2
            staging[off + 1] = pixels[off + 1]; // G ← byte 1
            staging[off + 2] = pixels[off + 0]; // B ← byte 0
            staging[off + 3] = pixels[off + 3]; // A ← byte 3
        }
    } else {
        // Direct copy — f16/u16 data or pre-swizzled RGBA
        @memcpy(staging[0..size], pixels[0..size]);
    }

    rcdbg("UPL-copied");
    // Record upload commands
    env.vkd.resetCommandBuffer(env.upload_cmd, .{}) catch return error.CmdResetFailed;
    env.vkd.beginCommandBuffer(env.upload_cmd, &.{
        .flags = .{ .one_time_submit_bit = true },
    }) catch return error.CmdBeginFailed;
    rcdbg("UPL-cmdbegin");

    // Barrier: undefined -> transfer_dst
    const to_transfer = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .top_of_pipe_bit = true }, .src_access_mask = .{}, .dst_stage_mask = .{ .all_transfer_bit = true }, .dst_access_mask = .{ .transfer_write_bit = true }, .old_layout = .undefined, .new_layout = .transfer_dst_optimal, .image = image, })};
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = to_transfer.len,
        .p_image_memory_barriers = &to_transfer,
    });

    rcdbg("UPL-barrier1");
    // Copy buffer to image. See fullImageCopyRegion's comment — SH backend
    // miscompiles the struct-literal form here.
    const region = [_]vk.BufferImageCopy{fullImageCopyRegion(0, 0, w, h)};
    env.vkd.cmdCopyBufferToImage(
        env.upload_cmd,
        env.staging_buffer,
        image,
        .transfer_dst_optimal,
        region.len,
        &region,
    );

    // Barrier: transfer_dst -> shader_read_only
    const to_shader = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .all_transfer_bit = true }, .src_access_mask = .{ .transfer_write_bit = true }, .dst_stage_mask = .{ .fragment_shader_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .transfer_dst_optimal, .new_layout = .shader_read_only_optimal, .image = image, })};
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = to_shader.len,
        .p_image_memory_barriers = &to_shader,
    });

    rcdbg("UPL-barrier2");
    env.vkd.endCommandBuffer(env.upload_cmd) catch return error.CmdEndFailed;
    rcdbg("UPL-cmdend");

    // Submit and wait
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{
        .command_buffer = env.upload_cmd,
        .device_mask = 0,
    }};
    rcdbg("UPL-presubmit");
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = cmd_info.len,
        .p_command_buffer_infos = &cmd_info,
    }}, env.upload_fence) catch return error.SubmitFailed;
    rcdbg("UPL-submitdone");

    rcdbg("UPL-prefence");
    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch
        return error.FenceWaitFailed;
    rcdbg("UPL-postfence");
    _ = env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch
        return error.FenceResetFailed;
    rcdbg("UPL-done");
}

// Vulkan Initialization

pub fn init(extra_extensions: []const [*:0]const u8) !*VkEnv {
    // MAY-299: static-Vulkan path — the pure-Zig ICD (src/vulkan_soft) is
    // linked into may, so vkGetInstanceProcAddr is a defined symbol in THIS
    // binary. Acquire it directly via @extern; no dlopen / loader / .so.
    const get_instance_proc_addr: vk.PfnGetInstanceProcAddr = if (comptime static_vulkan)
        @extern(vk.PfnGetInstanceProcAddr, .{ .name = "vkGetInstanceProcAddr" })
    else if (comptime builtin.link_mode == .static and
        // Load Vulkan dynamically — use our Zig ELF loader on static musl,
        // std.DynLib on glibc (which has a real dlopen)
        (builtin.abi == .musl or !builtin.link_libc))
    blk: {
        const handle = zig_dlopen.zig_dlopen("libvulkan.so.1", 1) orelse
            return error.VulkanLoadFailed;
        // Preload shaderc and resolve all symbols now while single-threaded.
        // glibc's _dlerror_run crashes after Vulkan spawns presentation threads,
        // so all dlopen/dlsym must happen before vkCreateInstance.
        if (zig_dlopen.zig_dlopen("libshaderc_shared.so.1", 1)) |sc_handle| {
            _ = agp_shaderc_preload(sc_handle);
        }
        break :blk @ptrCast(@alignCast(
            zig_dlopen.zig_dlsym(handle, "vkGetInstanceProcAddr") orelse
                return error.VulkanSymbolMissing,
        ));
    } else blk: {
        // Darwin: try the LunarG loader first (SDK / homebrew), then
        // MoltenVK directly — it exports vkGetInstanceProcAddr and
        // implements VK_EXT_metal_surface itself, no loader needed.
        const candidates: []const []const u8 = if (comptime builtin.os.tag.isDarwin()) &.{
            "libvulkan.1.dylib",
            "libvulkan.dylib",
            "/opt/homebrew/lib/libvulkan.1.dylib",
            "/usr/local/lib/libvulkan.1.dylib",
            "libMoltenVK.dylib",
            "/opt/homebrew/lib/libMoltenVK.dylib",
            "/usr/local/lib/libMoltenVK.dylib",
        } else if (comptime builtin.os.tag == .windows) &.{
            // The loader ships as vulkan-1.dll; for a software-only guest
            // (QEMU, no GPU) drop a lavapipe ICD + its vulkan-1.dll alongside
            // or on PATH. DynLib.open goes through LoadLibrary (dlopen).
            "vulkan-1.dll",
        } else &.{"libvulkan.so.1"};
        var lib: std.DynLib = for (candidates) |cand| {
            if (std.DynLib.open(cand)) |l| {
                std.log.info("vk.init: loaded {s}", .{cand});
                break l;
            } else |_| {}
        } else return error.VulkanLoadFailed;
        stored_vk_lib = lib;
        break :blk @ptrCast(@alignCast(
            lib.lookup(*const anyopaque, "vkGetInstanceProcAddr") orelse
                return error.VulkanSymbolMissing,
        ));
    };

    // Switch to glibc TLS for all Vulkan calls. Must happen AFTER zig_dlopen
    // (which triggers foreignInit on first call). Nesting-safe via depth counter.
    if (comptime use_zig_dlopen) zig_foreign_begin();

    std.log.info("vk.init: got vkGetInstanceProcAddr, loading base wrapper...", .{});
    const vkb = vk.BaseWrapper.load(get_instance_proc_addr);
    std.log.info("vk.init: base wrapper loaded, creating instance...", .{});

    // Create instance
    const app_info = vk.ApplicationInfo{
        .api_version = @bitCast(vk.makeApiVersion(0, 1, 4, 0)),
        .application_version = 0,
        .engine_version = 0,
        .p_application_name = "arcan",
        .p_engine_name = "arcan-agp-vk",
    };

    // Build extensions array
    var extensions: [16][*:0]const u8 = undefined;
    var ext_count: u32 = 0;
    for (extra_extensions) |ext| {
        if (ext_count < extensions.len) {
            extensions[ext_count] = ext;
            ext_count += 1;
        }
    }
    // Darwin: portability (non-conformant) implementations — MoltenVK — are
    // hidden by the loader unless the instance opts in via
    // VK_KHR_portability_enumeration + the enumerate-portability flag.
    if (comptime builtin.os.tag.isDarwin()) {
        if (ext_count < extensions.len) {
            extensions[ext_count] = "VK_KHR_portability_enumeration";
            ext_count += 1;
        }
    }

    // Optional: validation layers
    var layer_count: u32 = 0;
    var layers: [1][*:0]const u8 = undefined;
    if (envSpan("VK_INSTANCE_LAYERS")) |_| {
        layers[0] = "VK_LAYER_KHRONOS_validation";
        layer_count = 1;
    }

    std.log.info("vk.init: calling vkCreateInstance with {d} extensions, {d} layers...", .{ ext_count, layer_count });
    const instance = vkb.createInstance(&.{
        .flags = if (comptime builtin.os.tag.isDarwin()) .{ .enumerate_portability_bit_khr = true } else .{},
        .p_application_info = &app_info,
        .enabled_extension_count = ext_count,
        .pp_enabled_extension_names = if (ext_count > 0) @ptrCast(&extensions) else null,
        .enabled_layer_count = layer_count,
        .pp_enabled_layer_names = if (layer_count > 0) @ptrCast(&layers) else null,
    }, null) catch |e| {
        std.log.err("vk.init: vkCreateInstance failed: {s}", .{@errorName(e)});
        return error.InstanceCreateFailed;
    };
    std.log.info("vk.init: instance created, loading instance wrapper...", .{});
    const vki = vk.InstanceWrapper.load(instance, get_instance_proc_addr);
    std.log.info("vk.init: instance wrapper loaded, enumerating physical devices...", .{});

    // Select physical device
    var pdev_count: u32 = 0;
    _ = vki.enumeratePhysicalDevices(instance, &pdev_count, null) catch
        return error.DeviceEnumFailed;
    std.log.info("vk.init: found {d} physical devices", .{pdev_count});
    if (pdev_count == 0) return error.NoDevices;

    var pdevs: [8]vk.PhysicalDevice = undefined;
    if (pdev_count > 8) pdev_count = 8;
    _ = vki.enumeratePhysicalDevices(instance, &pdev_count, &pdevs) catch
        return error.DeviceEnumFailed;

    // Pick first discrete GPU, or first device
    var chosen: u32 = 0;
    for (0..pdev_count) |i| {
        const props = vki.getPhysicalDeviceProperties(pdevs[i]);
        if (props.device_type == .discrete_gpu) {
            chosen = @intCast(i);
            break;
        }
    }
    const physical_device = pdevs[chosen];

    // Find graphics queue family
    var qf_count: u32 = 0;
    vki.getPhysicalDeviceQueueFamilyProperties(physical_device, &qf_count, null);
    var qf_props: [16]vk.QueueFamilyProperties = undefined;
    if (qf_count > 16) qf_count = 16;
    vki.getPhysicalDeviceQueueFamilyProperties(physical_device, &qf_count, &qf_props);

    var queue_family: u32 = 0;
    var found_queue = false;
    for (0..qf_count) |i| {
        if (qf_props[i].queue_flags.graphics_bit) {
            queue_family = @intCast(i);
            found_queue = true;
            break;
        }
    }
    if (!found_queue) return error.NoGraphicsQueue;

    // Create logical device
    const queue_priority: f32 = 1.0;
    const queue_create_info = [_]vk.DeviceQueueCreateInfo{.{
        .queue_family_index = queue_family,
        .queue_count = 1,
        .p_queue_priorities = @ptrCast(&queue_priority),
    }};

    // Only request VK_KHR_swapchain when surface extensions were requested
    // (headless/LWA mode passes no instance extensions → no swapchain needed)
    const needs_swapchain = extra_extensions.len > 0;
    const device_ext_wanted = [_][*:0]const u8{
        "VK_KHR_swapchain",
        "VK_EXT_extended_dynamic_state3",
        "VK_KHR_external_memory_fd",
        "VK_EXT_external_memory_dma_buf",
        "VK_EXT_image_drm_format_modifier",
        // "VK_KHR_pipeline_executable_properties", // Shift 10: TODO — causes crash, needs investigation
        // Spec-mandatory to request when the implementation advertises it
        // (portability implementations: MoltenVK / KosmicKrisp on Metal).
        "VK_KHR_portability_subset",
    };
    // Intersect wanted with what the device actually offers — the external
    // memory / dma-buf / drm-modifier trio only exists on Linux drivers and
    // requesting an absent extension fails vkCreateDevice outright (seen on
    // MoltenVK/KosmicKrisp).
    var device_ext_buf: [device_ext_wanted.len][*:0]const u8 = undefined;
    var device_ext_count: usize = 0;
    {
        var avail_count: u32 = 0;
        _ = vki.enumerateDeviceExtensionProperties(physical_device, null, &avail_count, null) catch return error.DeviceCreateFailed;
        const avail = std.heap.c_allocator.alloc(vk.ExtensionProperties, avail_count) catch return error.DeviceCreateFailed;
        defer std.heap.c_allocator.free(avail);
        _ = vki.enumerateDeviceExtensionProperties(physical_device, null, &avail_count, avail.ptr) catch return error.DeviceCreateFailed;
        for (device_ext_wanted) |want| {
            if (!needs_swapchain and std.mem.eql(u8, std.mem.span(want), "VK_KHR_swapchain"))
                continue;
            const found = for (avail[0..avail_count]) |*prop| {
                const name = std.mem.sliceTo(&prop.extension_name, 0);
                if (std.mem.eql(u8, name, std.mem.span(want))) break true;
            } else false;
            if (found) {
                device_ext_buf[device_ext_count] = want;
                device_ext_count += 1;
            } else {
                std.log.warn("vk.init: device extension {s} unavailable, continuing without", .{want});
            }
        }
    }
    const device_extensions: []const [*:0]const u8 = device_ext_buf[0..device_ext_count];
    var has_eds3 = false;
    for (device_extensions) |e| {
        if (std.mem.eql(u8, std.mem.span(e), "VK_EXT_extended_dynamic_state3")) has_eds3 = true;
    }

    // EDS3 features — dynamic blend, color write mask, polygon mode
    // Query which EDS3 features the device really has (MoltenVK exposes the
    // extension without the color-blend trio) and request only those.
    var eds3_features = vk.PhysicalDeviceExtendedDynamicState3FeaturesEXT{};
    var has_eds3_blend = false;
    if (has_eds3) {
        var query_eds3 = vk.PhysicalDeviceExtendedDynamicState3FeaturesEXT{};
        var feats2 = vk.PhysicalDeviceFeatures2{ .p_next = @ptrCast(&query_eds3), .features = .{} };
        vki.getPhysicalDeviceFeatures2(physical_device, &feats2);
        eds3_features.extended_dynamic_state_3_color_blend_enable = query_eds3.extended_dynamic_state_3_color_blend_enable;
        eds3_features.extended_dynamic_state_3_color_blend_equation = query_eds3.extended_dynamic_state_3_color_blend_equation;
        eds3_features.extended_dynamic_state_3_color_write_mask = query_eds3.extended_dynamic_state_3_color_write_mask;
        eds3_features.extended_dynamic_state_3_polygon_mode = query_eds3.extended_dynamic_state_3_polygon_mode;
        has_eds3_blend = query_eds3.extended_dynamic_state_3_color_blend_enable == .true and
            query_eds3.extended_dynamic_state_3_color_blend_equation == .true and
            query_eds3.extended_dynamic_state_3_color_write_mask == .true;
        if (!has_eds3_blend)
            std.log.warn("vk.init: EDS3 blend features unavailable — static alpha-blend fallback", .{});
    }

    // Vulkan 1.3 features — dynamic rendering + synchronization2. Only chain
    // the EDS3 feature struct when the extension was actually requested.
    const vk13_features = vk.PhysicalDeviceVulkan13Features{
        .p_next = if (has_eds3) @ptrCast(@constCast(&eds3_features)) else null,
        .dynamic_rendering = .true,
        .synchronization_2 = .true,
    };

    // Enable depth clamping — the engine uses GL-style projection matrices with
    // depth range [-1, 1], but Vulkan clips primitives to z in [0, w]. Without
    // depth clamping, ALL 2D geometry (z_clip = -1) gets clipped away.
    const enabled_features = vk.PhysicalDeviceFeatures{
        .depth_clamp = .true,
    };

    const device = vki.createDevice(physical_device, &.{
        .p_next = @ptrCast(&vk13_features),
        .queue_create_info_count = queue_create_info.len,
        .p_queue_create_infos = &queue_create_info,
        .enabled_extension_count = @intCast(device_extensions.len),
        .pp_enabled_extension_names = device_extensions.ptr,
        .p_enabled_features = &enabled_features,
    }, null) catch return error.DeviceCreateFailed;

    std.log.info("vk.init: device created, loading device wrapper...", .{});
    const vkd = vk.DeviceWrapper.load(device, vki.dispatch.vkGetDeviceProcAddr.?);
    std.log.info("vk.init: device wrapper loaded", .{});

    const graphics_queue = vkd.getDeviceQueue(device, queue_family, 0);

    // Command pool + buffer
    const command_pool = vkd.createCommandPool(device, &.{
        .queue_family_index = queue_family,
        .flags = .{ .reset_command_buffer_bit = true },
    }, null) catch return error.CmdPoolCreateFailed;

    var cmd_buf: [1]vk.CommandBuffer = undefined;
    vkd.allocateCommandBuffers(device, &.{
        .command_pool = command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, &cmd_buf) catch return error.CmdBufferAllocFailed;

    // Sync objects
    const image_available = vkd.createSemaphore(device, &.{}, null) catch
        return error.SyncCreateFailed;
    const render_finished = vkd.createSemaphore(device, &.{}, null) catch
        return error.SyncCreateFailed;
    const frame_fence = vkd.createFence(device, &.{
        .flags = .{ .signaled_bit = true },
    }, null) catch return error.SyncCreateFailed;

    // Descriptor set layout:
    //   binding 0: combined_image_sampler (map_tu0 / map_diffuse)
    //   binding 1: uniform_buffer_dynamic (custom shader UBO)
    //   binding 2: combined_image_sampler (map_tu1, optional)
    //   binding 3: combined_image_sampler (SDF atlas, optional)
    // Built-in shaders only use binding 0; custom shaders may use all four.
    // Vulkan ignores unused bindings, so one layout works for everything.
    const binding = [_]vk.DescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
        },
        .{
            .binding = 1,
            .descriptor_type = .uniform_buffer_dynamic,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
        },
        .{
            .binding = 2,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
        },
        .{
            .binding = 3,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
        },
    };
    const descriptor_set_layout = vkd.createDescriptorSetLayout(device, &.{
        .binding_count = binding.len,
        .p_bindings = &binding,
    }, null) catch return error.DescriptorLayoutFailed;

    // Pipeline layout with push constants
    const push_constant_range = [_]vk.PushConstantRange{.{
        .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
        .offset = 0,
        .size = @sizeOf(PushConstants),
    }};
    const pipeline_layout = vkd.createPipelineLayout(device, &.{
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast(&descriptor_set_layout),
        .push_constant_range_count = push_constant_range.len,
        .p_push_constant_ranges = &push_constant_range,
    }, null) catch return error.PipelineLayoutFailed;

    env_storage = VkEnv{
        .vkb = vkb,
        .vki = vki,
        .vkd = vkd,
        .instance = instance,
        .physical_device = physical_device,
        .device = device,
        .graphics_queue = graphics_queue,
        .queue_family = queue_family,
        .command_pool = command_pool,
        .cmd = cmd_buf[0],
        .image_available = image_available,
        .render_finished = render_finished,
        .frame_fence = frame_fence,
        .pipeline_layout = pipeline_layout,
        .descriptor_set_layout = descriptor_set_layout,
        .has_eds3_blend = has_eds3_blend,
        ._vk_lib = stored_vk_lib,
    };
    // Populate memory properties early — needed by createOffscreen (LWA) before initPhase2
    env_storage.mem_props = vki.getPhysicalDeviceMemoryProperties(physical_device);
    global_env = &env_storage;
    if (comptime use_zig_dlopen) zig_foreign_end();
    return &env_storage;
}

pub fn getEnv() ?*VkEnv {
    return global_env;
}

// Bridge Export Functions (called from vk_shared.zig / vk_shdrmgmt.zig)

fn findFreeTextureSlot(env: *VkEnv) ?u32 {
    // First try the fast path: next sequential ID (only if slot is actually free)
    if (env.next_texture_id < MAX_TEXTURES and !env.textures[env.next_texture_id].in_use) {
        const id = env.next_texture_id;
        env.next_texture_id = id + 1;
        return id;
    }
    // Slow path: scan for a freed slot (skip 0 = default white)
    for (1..MAX_TEXTURES) |i| {
        if (!env.textures[i].in_use) return @intCast(i);
    }
    _ = c.printf("[vk_tex] ERROR: all %u texture slots exhausted!\n", @as(c_uint, MAX_TEXTURES));
    return null;
}

export fn vk_env_create_texture(w: u32, h: u32, pixels: ?[*]const u8) u32 {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return 0;
    const id = findFreeTextureSlot(env) orelse {
        std.log.err("vk_env_create_texture({d}x{d}): all texture slots exhausted", .{ w, h });
        return 0;
    };


    rcdbg("VEC-precreate");
    env.textures[id] = createTextureInternal(env, w, h, pixels) catch |e| {
        std.log.err("vk_env_create_texture({d}x{d}): {s}", .{ w, h, @errorName(e) });
        return 0;
    };

    rcdbg("VEC-created");
    return id;
}

// Slug GPU glyph textures: float16 (curves) and uint16 (bands)
export fn vk_env_create_texture_f16(w: u32, h: u32, pixels: ?[*]const u8) u32 {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return 0;
    const id = findFreeTextureSlot(env) orelse return 0;
    env.textures[id] = createTextureInternalFmt(env, w, h, pixels, .r16g16b16a16_sfloat, 8, false) catch return 0;
    return id;
}

export fn vk_env_create_texture_u16(w: u32, h: u32, pixels: ?[*]const u8) u32 {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return 0;
    const id = findFreeTextureSlot(env) orelse return 0;
    env.textures[id] = createTextureInternalFmt(env, w, h, pixels, .r16g16b16a16_uint, 8, false) catch return 0;
    return id;
}

/// Create RGBA float32 texture (16 bytes per texel) — for Slug curve data.
export fn vk_env_create_texture_f32(w: u32, h: u32, pixels: ?[*]const u8) u32 {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return 0;
    const id = findFreeTextureSlot(env) orelse return 0;
    env.textures[id] = createTextureInternalFmt(env, w, h, pixels, .r32g32b32a32_sfloat, 16, false) catch return 0;
    return id;
}

/// Create R16F SDF atlas texture (2 bytes per texel) — for temporal coverage accumulation.
export fn vk_env_create_sdf_atlas(w: u32, h: u32) u32 {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return 0;
    const id = findFreeTextureSlot(env) orelse return 0;
    env.textures[id] = createTextureInternalFmt(env, w, h, null, .r16_sfloat, 2, false) catch return 0;
    return id;
}

// Compute pipeline + SSBO infrastructure for ADMM glyph grading

/// Create a host-visible storage buffer (SSBO). Returns buffer handle or 0.
/// The buffer is host-visible + coherent for CPU readback of quality metrics.
var compute_ssbo_buf: vk.Buffer = .null_handle;
var compute_ssbo_mem: vk.DeviceMemory = .null_handle;
var compute_ssbo_mapped: ?[*]u8 = null;
var compute_ssbo_size: u32 = 0;

export fn vk_env_create_ssbo(size_bytes: u32) bool {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return false;
    if (compute_ssbo_buf != .null_handle) return true; // already created

    const result = createBuffer(env, size_bytes, .{ .storage_buffer_bit = true, .transfer_src_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true }) catch return false;
    compute_ssbo_buf = result.buffer;
    compute_ssbo_mem = result.memory;
    compute_ssbo_size = size_bytes;

    // Map permanently
    compute_ssbo_mapped = @ptrCast(env.vkd.mapMemory(env.device, compute_ssbo_mem, 0, size_bytes, .{}) catch return false);
    @memset(compute_ssbo_mapped.?[0..size_bytes], 0);
    return true;
}

/// Get mapped SSBO pointer for CPU read/write.
export fn vk_env_get_ssbo_ptr() ?[*]u8 {
    return compute_ssbo_mapped;
}

/// Second SSBO for glyph region info (read-only from compute shader).
var compute_region_buf: vk.Buffer = .null_handle;
var compute_region_mem: vk.DeviceMemory = .null_handle;
var compute_region_mapped: ?[*]u8 = null;
var compute_region_size: u32 = 0;

export fn vk_env_create_region_ssbo(size_bytes: u32) bool {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return false;
    if (compute_region_buf != .null_handle) return true;

    const result = createBuffer(env, size_bytes, .{ .storage_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true }) catch return false;
    compute_region_buf = result.buffer;
    compute_region_mem = result.memory;
    compute_region_size = size_bytes;

    compute_region_mapped = @ptrCast(env.vkd.mapMemory(env.device, compute_region_mem, 0, size_bytes, .{}) catch return false);
    @memset(compute_region_mapped.?[0..size_bytes], 0);
    return true;
}

export fn vk_env_get_region_ssbo_ptr() ?[*]u8 {
    return compute_region_mapped;
}

// ADMM state SSBO (per-glyph optimization state)

/// AdmmState: 32 bytes per glyph (theta, z, u, mu, prev_theta, prev_z, admm_iter, converged)
var compute_admm_buf: vk.Buffer = .null_handle;
var compute_admm_mem: vk.DeviceMemory = .null_handle;
var compute_admm_mapped: ?[*]u8 = null;
var compute_admm_size: u32 = 0;

export fn vk_env_create_admm_ssbo(size_bytes: u32) bool {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return false;
    if (compute_admm_buf != .null_handle) return true;

    const result = createBuffer(env, size_bytes, .{ .storage_buffer_bit = true, .transfer_src_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true }) catch return false;
    compute_admm_buf = result.buffer;
    compute_admm_mem = result.memory;
    compute_admm_size = size_bytes;

    compute_admm_mapped = @ptrCast(env.vkd.mapMemory(env.device, compute_admm_mem, 0, size_bytes, .{}) catch return false);
    // Initialize 3-param AdmmState: 96 bytes (24 floats) per glyph
    // theta=(0.5,1.0,1.0), z=(0,0,0), u=(0,0,0), mu=1.0, JtJ=0, Jtr=0, accum_n=0, conv=0
    const num_glyphs = size_bytes / 96;
    const floats: [*]f32 = @ptrCast(@alignCast(compute_admm_mapped.?));
    @memset(compute_admm_mapped.?[0..size_bytes], 0);
    for (0..num_glyphs) |i| {
        const base = i * 24; // 96 bytes / 4 = 24 floats per entry
        floats[base + 0] = 0.5; // theta0 (ramp)
        floats[base + 1] = 0.0; // theta1 (dropout blend)
        floats[base + 2] = 0.0; // theta2 (unused)
        // z0..z2, u0..u2 = 0 (already zeroed)
        floats[base + 9] = 1.0; // mu
        // JtJ, Jtr, accum_n, converged, pad = 0 (already zeroed)
    }
    return true;
}

export fn vk_env_get_admm_ssbo_ptr() ?[*]u8 {
    return compute_admm_mapped;
}

// covPlus / covMinus textures for Jacobian finite differences

var cov_plus_tex_id: u32 = 0;
var cov_minus_tex_id: u32 = 0;

/// Create the two R16F textures for perturbed coverage (Jacobian computation).
/// Same dimensions as SDF atlas.
export fn vk_env_create_cov_perturbed(w: u32, h: u32) bool {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return false;
    if (cov_plus_tex_id > 0) return true; // already created

    const plus_id = findFreeTextureSlot(env) orelse return false;
    env.textures[plus_id] = createTextureInternalFmt(env, w, h, null, .r16_sfloat, 2, false) catch return false;
    cov_plus_tex_id = plus_id;

    const minus_id = findFreeTextureSlot(env) orelse return false;
    env.textures[minus_id] = createTextureInternalFmt(env, w, h, null, .r16_sfloat, 2, false) catch return false;
    cov_minus_tex_id = minus_id;

    return true;
}

export fn vk_env_get_cov_plus_tex() u32 {
    return cov_plus_tex_id;
}

export fn vk_env_get_cov_minus_tex() u32 {
    return cov_minus_tex_id;
}

/// Set the global Slug parameters (called from vk_shared.zig when ADMM updates).
export fn vk_env_set_slug_ramp(ramp: f32) void {
    slug_ramp_override = ramp;
}

export fn vk_env_set_sdf_dump_ptsize(ptsize: u32) void {
    sdf_dump_ptsize = ptsize;
}

export fn vk_env_set_slug_params(ramp: f32, gamma: f32, dropout: f32) void {
    slug_ramp_override = ramp;
    slug_gamma_override = gamma;
    slug_dropout_override = dropout;
}

/// Reset the SDF atlas texture so next accumulation pass uses .clear load_op.
/// Called between sizes during multi-size calibration.
export fn vk_env_reset_sdf_atlas(sdf_tex_id: u32) void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return;
    if (sdf_tex_id >= MAX_TEXTURES or !env.textures[sdf_tex_id].in_use) return;
    env.textures[sdf_tex_id].rt_initialized = false;
}

/// Update an existing R8 texture with new pixel data (same dimensions).
/// Used to swap STB reference content without creating a new texture.
export fn vk_env_update_texture_r8(id: u32, w: u32, h: u32, pixels: ?[*]const u8) void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return;
    if (id >= MAX_TEXTURES or !env.textures[id].in_use) return;
    const px = pixels orelse return;
    uploadTexturePixels(env, env.textures[id].image, w, h, px) catch {};
}

/// Create compute pipeline for glyph grading.
var compute_pipeline: vk.Pipeline = .null_handle;
var compute_pipeline_layout: vk.PipelineLayout = .null_handle;
var compute_desc_layout: vk.DescriptorSetLayout = .null_handle;
var compute_desc_pool: vk.DescriptorPool = .null_handle;

export fn vk_env_create_grade_compute(comp_handle: u64) bool {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return false;
    const comp_mod: vk.ShaderModule = @enumFromInt(comp_handle);

    // Compute descriptor layout:
    //   binding 0: sampler (SDF atlas R16F)
    //   binding 1: sampler (stb ref R8)
    //   binding 2: storage buffer (quality SSBO, read-write)
    //   binding 3: storage buffer (region info, read-only)
    //   binding 4: storage buffer (ADMM state, read-write)
    //   binding 5: sampler (covPlus R16F — coverage at ramp+h)
    //   binding 6: sampler (covMinus R16F — coverage at ramp-h)
    const bindings = [_]vk.DescriptorSetLayoutBinding{
        .{ .binding = 0, .descriptor_type = .combined_image_sampler, .descriptor_count = 1, .stage_flags = .{ .compute_bit = true } },
        .{ .binding = 1, .descriptor_type = .combined_image_sampler, .descriptor_count = 1, .stage_flags = .{ .compute_bit = true } },
        .{ .binding = 2, .descriptor_type = .storage_buffer, .descriptor_count = 1, .stage_flags = .{ .compute_bit = true } },
        .{ .binding = 3, .descriptor_type = .storage_buffer, .descriptor_count = 1, .stage_flags = .{ .compute_bit = true } },
        .{ .binding = 4, .descriptor_type = .storage_buffer, .descriptor_count = 1, .stage_flags = .{ .compute_bit = true } },
        .{ .binding = 5, .descriptor_type = .combined_image_sampler, .descriptor_count = 1, .stage_flags = .{ .compute_bit = true } },
        .{ .binding = 6, .descriptor_type = .combined_image_sampler, .descriptor_count = 1, .stage_flags = .{ .compute_bit = true } },
    };
    compute_desc_layout = env.vkd.createDescriptorSetLayout(env.device, &.{
        .binding_count = bindings.len,
        .p_bindings = &bindings,
    }, null) catch return false;

    // Compute pipeline layout (no push constants needed)
    compute_pipeline_layout = env.vkd.createPipelineLayout(env.device, &.{
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast(&compute_desc_layout),
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null) catch return false;

    // Compute pipeline
    var pipeline: [1]vk.Pipeline = undefined;
    _ = env.vkd.createComputePipelines(env.device, .null_handle, 1, &[_]vk.ComputePipelineCreateInfo{.{
        .stage = .{ .stage = .{ .compute_bit = true }, .module = comp_mod, .p_name = "main" },
        .layout = compute_pipeline_layout,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    }}, null, &pipeline) catch return false;
    compute_pipeline = pipeline[0];

    // Descriptor pool for compute (4 samplers + 3 storage buffers)
    const pool_sizes = [_]vk.DescriptorPoolSize{
        .{ .type = .combined_image_sampler, .descriptor_count = 4 },
        .{ .type = .storage_buffer, .descriptor_count = 3 },
    };
    compute_desc_pool = env.vkd.createDescriptorPool(env.device, &.{
        .max_sets = 1,
        .pool_size_count = pool_sizes.len,
        .p_pool_sizes = &pool_sizes,
        .flags = .{ .free_descriptor_set_bit = true },
    }, null) catch return false;

    return true;
}

/// Dispatch the grading compute shader.
/// Reads SDF atlas + stb ref, writes quality SSBO, dispatches num_glyphs workgroups.
export fn vk_env_dispatch_grade(sdf_tex: u32, stb_tex: u32, num_glyphs: u32) bool {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return false;
    if (compute_pipeline == .null_handle) return false;
    if (num_glyphs == 0) return true;
    if (sdf_tex >= MAX_TEXTURES or stb_tex >= MAX_TEXTURES) return false;
    if (!env.textures[sdf_tex].in_use or !env.textures[stb_tex].in_use) return false;
    if (compute_ssbo_buf == .null_handle or compute_region_buf == .null_handle) return false;

    const cmd = env.upload_cmd;
    env.vkd.resetCommandBuffer(cmd, .{}) catch return false;
    env.vkd.beginCommandBuffer(cmd, &.{ .flags = .{ .one_time_submit_bit = true } }) catch return false;

    // Allocate and write descriptor set
    const layouts = [_]vk.DescriptorSetLayout{compute_desc_layout};
    var desc_sets: [1]vk.DescriptorSet = undefined;
    env.vkd.allocateDescriptorSets(env.device, &.{
        .descriptor_pool = compute_desc_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = &layouts,
    }, &desc_sets) catch return false;

    // Use covPlus/covMinus if available, otherwise use SDF atlas as dummy
    const plus_view = if (cov_plus_tex_id > 0 and cov_plus_tex_id < MAX_TEXTURES and env.textures[cov_plus_tex_id].in_use)
        env.textures[cov_plus_tex_id].view
    else
        env.textures[sdf_tex].view;
    const minus_view = if (cov_minus_tex_id > 0 and cov_minus_tex_id < MAX_TEXTURES and env.textures[cov_minus_tex_id].in_use)
        env.textures[cov_minus_tex_id].view
    else
        env.textures[sdf_tex].view;

    // Use ADMM SSBO if available, otherwise use quality SSBO as placeholder
    const admm_buf = if (compute_admm_buf != .null_handle) compute_admm_buf else compute_ssbo_buf;
    const admm_range = if (compute_admm_buf != .null_handle) compute_admm_size else compute_ssbo_size;

    env.vkd.updateDescriptorSets(env.device, 7, &[_]vk.WriteDescriptorSet{
        .{ .dst_set = desc_sets[0], .dst_binding = 0, .dst_array_element = 0, .descriptor_count = 1,
           .descriptor_type = .combined_image_sampler,
           .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = env.textures[sdf_tex].view, .image_layout = .shader_read_only_optimal }},
           .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
        .{ .dst_set = desc_sets[0], .dst_binding = 1, .dst_array_element = 0, .descriptor_count = 1,
           .descriptor_type = .combined_image_sampler,
           .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = env.textures[stb_tex].view, .image_layout = .shader_read_only_optimal }},
           .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
        .{ .dst_set = desc_sets[0], .dst_binding = 2, .dst_array_element = 0, .descriptor_count = 1,
           .descriptor_type = .storage_buffer,
           .p_image_info = undefined,
           .p_buffer_info = &[_]vk.DescriptorBufferInfo{.{ .buffer = compute_ssbo_buf, .offset = 0, .range = compute_ssbo_size }},
           .p_texel_buffer_view = undefined },
        .{ .dst_set = desc_sets[0], .dst_binding = 3, .dst_array_element = 0, .descriptor_count = 1,
           .descriptor_type = .storage_buffer,
           .p_image_info = undefined,
           .p_buffer_info = &[_]vk.DescriptorBufferInfo{.{ .buffer = compute_region_buf, .offset = 0, .range = compute_region_size }},
           .p_texel_buffer_view = undefined },
        .{ .dst_set = desc_sets[0], .dst_binding = 4, .dst_array_element = 0, .descriptor_count = 1,
           .descriptor_type = .storage_buffer,
           .p_image_info = undefined,
           .p_buffer_info = &[_]vk.DescriptorBufferInfo{.{ .buffer = admm_buf, .offset = 0, .range = admm_range }},
           .p_texel_buffer_view = undefined },
        .{ .dst_set = desc_sets[0], .dst_binding = 5, .dst_array_element = 0, .descriptor_count = 1,
           .descriptor_type = .combined_image_sampler,
           .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = plus_view, .image_layout = .shader_read_only_optimal }},
           .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
        .{ .dst_set = desc_sets[0], .dst_binding = 6, .dst_array_element = 0, .descriptor_count = 1,
           .descriptor_type = .combined_image_sampler,
           .p_image_info = &[_]vk.DescriptorImageInfo{.{ .sampler = env.sampler_nearest, .image_view = minus_view, .image_layout = .shader_read_only_optimal }},
           .p_buffer_info = undefined, .p_texel_buffer_view = undefined },
    }, 0, null);

    env.vkd.cmdBindPipeline(cmd, .compute, compute_pipeline);
    env.vkd.cmdBindDescriptorSets(cmd, .compute, compute_pipeline_layout, 0, 1, @ptrCast(&desc_sets[0]), 0, undefined);
    env.vkd.cmdDispatch(cmd, num_glyphs, 1, 1);

    env.vkd.endCommandBuffer(cmd) catch return false;
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{ .command_buffer = cmd, .device_mask = 0 }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = 1, .p_command_buffer_infos = &cmd_info,
    }}, env.upload_fence) catch return false;
    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch {};
    _ = env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch {};

    // Free descriptor set for reuse
    env.vkd.freeDescriptorSets(env.device, compute_desc_pool, 1, @ptrCast(&desc_sets[0])) catch {};

    return true;
}

/// Create R8_UNORM texture (1 byte per texel) — for stb reference atlas.
export fn vk_env_create_texture_r8(w: u32, h: u32, pixels: ?[*]const u8) u32 {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return 0;
    const id = findFreeTextureSlot(env) orelse return 0;
    env.textures[id] = createTextureInternalFmt(env, w, h, pixels, .r8_unorm, 1, false) catch return 0;
    return id;
}

export fn vk_env_update_texture(id: u32, w: u32, h: u32, pixels: ?[*]const u8) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (id >= MAX_TEXTURES or !env.textures[id].in_use) return;
    const px = pixels orelse return;

    const slot = &env.textures[id];

    // If dimensions changed, recreate the texture
    if (slot.width != w or slot.height != h) {
        if (env.rendering_active or env.cmd_recording) {
            // Mid-frame: defer old resource destruction, create new via upload_cmd.
            // Don't touch env.cmd — render pass stays active.
            env.deferDestroy(slot.image, slot.view, slot.memory, slot.descriptor_set);
        } else {
            // Between frames: synchronous destroy is safe
            env.vkd.deviceWaitIdle(env.device) catch return;
            if (slot.view != .null_handle) env.vkd.destroyImageView(env.device, slot.view, null);
            if (slot.image != .null_handle) env.vkd.destroyImage(env.device, slot.image, null);
            if (slot.memory != .null_handle) env.vkd.freeMemory(env.device, slot.memory, null);
            if (slot.descriptor_set != .null_handle) {
                env.vkd.freeDescriptorSets(env.device, env.descriptor_pool, 1, @ptrCast(&slot.descriptor_set)) catch {};
            }
        }
        slot.* = createTextureInternal(env, w, h, px) catch return;
        return;
    }

    // Same dimensions — just re-upload
    uploadTexturePixels(env, slot.image, w, h, px) catch return;
}

export fn vk_env_update_texture_sub(id: u32, x: u32, y: u32, w: u32, h: u32, stride: u32, pixels: [*]const u8) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (id >= MAX_TEXTURES or !env.textures[id].in_use) return;

    const slot = &env.textures[id];
    const staging = env.staging_mapped orelse return;

    // Clamp sub-region to texture dimensions — dirty regions from shmif can
    // exceed the actual texture size (e.g. stale region from a prior resize).
    const cw = if (x + w > slot.width) slot.width -| x else w;
    const ch = if (y + h > slot.height) slot.height -| y else h;
    if (cw == 0 or ch == 0) return;

    // Copy pixel data to staging buffer, handling stride.
    // The source buffer is the FULL framebuffer (like GL's GL_UNPACK_ROW_LENGTH).
    // We must offset by (y * src_stride + x * 4) to reach the sub-region,
    // matching GL's GL_UNPACK_SKIP_ROWS/GL_UNPACK_SKIP_PIXELS behavior.
    const row_bytes: usize = @as(usize, cw) * 4;
    const src_stride: usize = if (stride > 0) @as(usize, stride) else @as(usize, slot.width) * 4;
    const total_size: usize = row_bytes * @as(usize, ch);
    if (total_size > STAGING_BUFFER_SIZE) return;

    // Offset into the full framebuffer to reach (x, y)
    const src_start: usize = @as(usize, y) * src_stride + @as(usize, x) * 4;

    // Copy with BGRA→RGBA swizzle (arcan's shmif_pixel is BGRA in memory on LE)
    const n_rows: usize = @intCast(ch);
    for (0..n_rows) |row| {
        const dst_row = row * row_bytes;
        const src_row = src_start + row * src_stride;
        const n_px: usize = @intCast(cw);
        for (0..n_px) |px| {
            const doff = dst_row + px * 4;
            const soff = src_row + px * 4;
            staging[doff + 0] = pixels[soff + 2]; // R ← byte 2
            staging[doff + 1] = pixels[soff + 1]; // G
            staging[doff + 2] = pixels[soff + 0]; // B ← byte 0
            staging[doff + 3] = pixels[soff + 3]; // A
        }
    }

    // Record upload commands
    env.vkd.resetCommandBuffer(env.upload_cmd, .{}) catch return;
    env.vkd.beginCommandBuffer(env.upload_cmd, &.{
        .flags = .{ .one_time_submit_bit = true },
    }) catch return;

    // Barrier: shader_read_only -> transfer_dst
    const to_transfer = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .fragment_shader_bit = true }, .src_access_mask = .{ .shader_read_bit = true }, .dst_stage_mask = .{ .all_transfer_bit = true }, .dst_access_mask = .{ .transfer_write_bit = true }, .old_layout = .shader_read_only_optimal, .new_layout = .transfer_dst_optimal, .image = slot.image, })};
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = to_transfer.len,
        .p_image_memory_barriers = &to_transfer,
    });

    // Copy buffer to sub-region of image. Same SH-backend literal-init
    // miscompile workaround as fullImageCopyRegion — but with sub-region
    // image_offset, so we need a custom build.
    var region: [1]vk.BufferImageCopy = undefined;
    region[0].buffer_offset = 0;
    region[0].buffer_row_length = cw;
    region[0].buffer_image_height = ch;
    region[0].image_subresource = fullColorSubresourceLayers();
    region[0].image_offset.x = @intCast(x);
    region[0].image_offset.y = @intCast(y);
    region[0].image_offset.z = 0;
    region[0].image_extent.width = cw;
    region[0].image_extent.height = ch;
    region[0].image_extent.depth = 1;
    env.vkd.cmdCopyBufferToImage(
        env.upload_cmd,
        env.staging_buffer,
        slot.image,
        .transfer_dst_optimal,
        region.len,
        &region,
    );

    // Barrier: transfer_dst -> shader_read_only
    const to_shader = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .all_transfer_bit = true }, .src_access_mask = .{ .transfer_write_bit = true }, .dst_stage_mask = .{ .fragment_shader_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .transfer_dst_optimal, .new_layout = .shader_read_only_optimal, .image = slot.image, })};
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = to_shader.len,
        .p_image_memory_barriers = &to_shader,
    });

    env.vkd.endCommandBuffer(env.upload_cmd) catch return;

    // Submit and wait
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{
        .command_buffer = env.upload_cmd,
        .device_mask = 0,
    }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = cmd_info.len,
        .p_command_buffer_infos = &cmd_info,
    }}, env.upload_fence) catch return;

    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch return;
    _ = env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch return;
}

export fn vk_env_destroy_texture(id: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (id >= MAX_TEXTURES or !env.textures[id].in_use) return;
    if (id == 0) return; // Don't destroy default white texture

    const slot = &env.textures[id];

    if (env.rendering_active or env.cmd_recording) {
        // Mid-frame: defer destruction, don't kill the render pass
        env.deferDestroy(slot.image, slot.view, slot.memory, slot.descriptor_set);
    } else {
        // Between frames: synchronous destroy
        if (slot.view != .null_handle) env.vkd.destroyImageView(env.device, slot.view, null);
        if (slot.image != .null_handle) env.vkd.destroyImage(env.device, slot.image, null);
        if (slot.memory != .null_handle) env.vkd.freeMemory(env.device, slot.memory, null);
        if (slot.descriptor_set != .null_handle) {
            env.vkd.freeDescriptorSets(env.device, env.descriptor_pool, 1, @ptrCast(&slot.descriptor_set)) catch {};
        }
    }
    slot.* = .{};
    // Flush any DMA-BUF cache entries belonging to this slot
    for (&env.dmabuf_cache) |*entry| {
        if (entry.ino != 0 and entry.slot_id == id) {
            if (entry.view != .null_handle) env.vkd.destroyImageView(env.device, entry.view, null);
            if (entry.image != .null_handle) env.vkd.destroyImage(env.device, entry.image, null);
            if (entry.memory != .null_handle) env.vkd.freeMemory(env.device, entry.memory, null);
            entry.* = .{};
        }
    }
    // Let findFreeTextureSlot's fast path reuse this freed slot immediately
    // instead of climbing monotonically to MAX_TEXTURES.
    if (id < env.next_texture_id) env.next_texture_id = id;
}

/// Import a DMA-BUF fd as a Vulkan texture. Returns slot index (glid) or 0 on failure.
export fn vk_env_import_dmabuf_texture(
    fd: c_int,
    w: u32,
    h: u32,
    stride: u64,
    offset: u64,
    drm_format: u32,
    modifier: u64,
) u32 {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return 0;
    const id = findFreeTextureSlot(env) orelse {
        _ = c.printf("[vk] DMA-BUF import failed: texture slots full\n");
        return 0;
    };

    // Record the DMA-BUF inode before Vulkan takes ownership of the fd
    const dmabuf_ino = if (builtin.os.tag == .windows) @as(u64, 0) else blk: {
        const stat = std.posix.fstat(fd) catch break :blk @as(u64, 0);
        break :blk stat.ino;
    };

    env.textures[id] = importTextureFromDmaBuf(env, fd, w, h, stride, offset, drm_format, modifier) catch |err| {
        _ = c.printf("[vk] DMA-BUF import failed: %s (fd=%d %ux%u fmt=0x%x stride=%lu mod=0x%lx)\n", @errorName(err).ptr, fd, w, h, drm_format, stride, modifier);
        return 0;
    };
    env.textures[id].dmabuf_ino = dmabuf_ino;
    return id;
}

/// Update an existing DMA-BUF texture slot in-place: swap VkImage/VkImageView/VkDeviceMemory
/// from a new fd, reuse the existing descriptor set and slot ID. No deviceWaitIdle, no slot
/// allocation, no descriptor pool alloc/free. Returns true on success.
export fn vk_env_update_dmabuf_texture(
    id: u32,
    fd: c_int,
    w: u32,
    h: u32,
    stride: u64,
    offset: u64,
    drm_format: u32,
    modifier: u64,
) bool {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return false;
    if (id >= MAX_TEXTURES or !env.textures[id].in_use) return false;
    const slot = &env.textures[id];

    // Identify the incoming DMA-BUF by its inode (unique per buffer).
    const new_ino = if (builtin.os.tag == .windows) @as(u64, 0) else blk: {
        const stat = std.posix.fstat(fd) catch break :blk @as(u64, 0);
        break :blk stat.ino;
    };

    // === Cache path: check if we've seen this DMA-BUF before (triple-buffer reuse) ===
    if (new_ino != 0) {
        for (&env.dmabuf_cache) |*entry| {
            if (entry.ino == new_ino and entry.slot_id == id and entry.w == w and entry.h == h) {
                // Cache hit! Swap current slot resources with cached entry.
                _ = std.c.close(fd);

                // Stash current slot resources into this cache entry
                const old_image = slot.image;
                const old_view = slot.view;
                const old_memory = slot.memory;
                const old_ino = slot.dmabuf_ino;

                // Move cached resources into the active slot
                slot.image = entry.image;
                slot.view = entry.view;
                slot.memory = entry.memory;
                slot.width = w;
                slot.height = h;
                slot.dmabuf_ino = new_ino;

                // Put old resources into cache (for reuse when this buffer cycles back)
                entry.image = old_image;
                entry.view = old_view;
                entry.memory = old_memory;
                entry.ino = old_ino;
                // entry.slot_id, w, h stay the same (same slot, same dimensions)

                // Update descriptor set to the cached view (already transitioned)
                updateDescriptorSetForTexture(env, slot.descriptor_set, slot.view);

                // Memory barrier: ensure previous frame's writes are visible
                if (env.cmd_recording) {
                    const mem_barrier = [_]vk.MemoryBarrier2{.{
                        .src_stage_mask = .{ .host_bit = true },
                        .src_access_mask = .{ .host_write_bit = true },
                        .dst_stage_mask = .{ .fragment_shader_bit = true },
                        .dst_access_mask = .{ .shader_read_bit = true },
                    }};
                    env.vkd.cmdPipelineBarrier2(env.cmd, &.{
                        .memory_barrier_count = mem_barrier.len,
                        .p_memory_barriers = &mem_barrier,
                    });
                }
                return true;
            }
        }
    }

    // === Cold path: new DMA-BUF, must create Vulkan resources ===
    const res = createDmaBufResources(env, fd, w, h, stride, offset, drm_format, modifier) catch |err| {
        _ = c.printf("[vk_dmabuf] update failed: %s (slot %u fd=%d %ux%u)\n", @errorName(err).ptr, id, fd, w, h);
        return false;
    };

    // Cache current slot's resources for reuse (if they exist)
    if (slot.image != .null_handle and slot.dmabuf_ino != 0) {
        // Find a free cache entry, or evict the oldest
        var cache_idx: ?usize = null;
        for (env.dmabuf_cache, 0..) |entry, i| {
            if (entry.ino == 0) {
                cache_idx = i;
                break;
            }
        }
        if (cache_idx == null) {
            // Cache full — evict entry 0 (destroy its resources)
            const evict = &env.dmabuf_cache[0];
            if (evict.view != .null_handle) env.vkd.destroyImageView(env.device, evict.view, null);
            if (evict.image != .null_handle) env.vkd.destroyImage(env.device, evict.image, null);
            if (evict.memory != .null_handle) env.vkd.freeMemory(env.device, evict.memory, null);
            cache_idx = 0;
        }
        env.dmabuf_cache[cache_idx.?] = .{
            .ino = slot.dmabuf_ino,
            .slot_id = id,
            .image = slot.image,
            .view = slot.view,
            .memory = slot.memory,
            .w = slot.width,
            .h = slot.height,
        };
    } else {
        // No previous resources to cache — just destroy them
        if (slot.view != .null_handle) env.vkd.destroyImageView(env.device, slot.view, null);
        if (slot.image != .null_handle) env.vkd.destroyImage(env.device, slot.image, null);
        if (slot.memory != .null_handle) env.vkd.freeMemory(env.device, slot.memory, null);
    }

    // Install new resources into the slot
    slot.image = res.image;
    slot.view = res.view;
    slot.memory = res.memory;
    slot.width = w;
    slot.height = h;
    slot.dmabuf_ino = new_ino;

    updateDescriptorSetForTexture(env, slot.descriptor_set, res.view);

    // Transition new image: UNDEFINED → SHADER_READ_ONLY_OPTIMAL
    if (env.cmd_recording) {
        const was_rt = env.rt_rendering;
        if (was_rt) {
            env.vkd.cmdEndRendering(env.cmd);
            env.rt_rendering = false;
            env.rendering_active = false;
        }

        const barrier = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .top_of_pipe_bit = true }, .src_access_mask = .{}, .dst_stage_mask = .{ .fragment_shader_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .undefined, .new_layout = .shader_read_only_optimal, .image = res.image, })};
        env.vkd.cmdPipelineBarrier2(env.cmd, &.{
            .image_memory_barrier_count = barrier.len,
            .p_image_memory_barriers = &barrier,
        });

        if (was_rt) {
            const rt_tex = env.rt_active_tex;
            if (rt_tex < MAX_TEXTURES and env.textures[rt_tex].in_use) {
                const rt_slot = &env.textures[rt_tex];
                const color_att = [_]vk.RenderingAttachmentInfo{.{
                    .image_view = rt_slot.view,
                    .image_layout = .color_attachment_optimal,
                    .resolve_mode = .{},
                    .resolve_image_layout = .undefined,
                    .load_op = .load,
                    .store_op = .store,
                    .clear_value = .{ .color = .{ .float_32 = .{ 0, 0, 0, 0 } } },
                }};
                const has_depth = env.depth_active and env.depth_view != .null_handle;
                const depth_att = vk.RenderingAttachmentInfo{
                    .image_view = env.depth_view,
                    .image_layout = .depth_stencil_attachment_optimal,
                    .resolve_mode = .{},
                    .resolve_image_layout = .undefined,
                    .load_op = .load,
                    .store_op = .dont_care,
                    .clear_value = .{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
                };
                const has_stencil = env.stencil_active and env.stencil_view != .null_handle;
                const stencil_att = vk.RenderingAttachmentInfo{
                    .image_view = env.stencil_view,
                    .image_layout = .depth_stencil_attachment_optimal,
                    .resolve_mode = .{},
                    .resolve_image_layout = .undefined,
                    .load_op = .load,
                    .store_op = .dont_care,
                    .clear_value = .{ .depth_stencil = .{ .depth = 0, .stencil = 0 } },
                };
                env.vkd.cmdBeginRendering(env.cmd, &.{
                    .render_area = .{
                        .offset = .{ .x = 0, .y = 0 },
                        .extent = .{ .width = env.rt_width, .height = env.rt_height },
                    },
                    .layer_count = 1,
                    .view_mask = 0,
                    .color_attachment_count = color_att.len,
                    .p_color_attachments = &color_att,
                    .p_depth_attachment = if (has_depth) &depth_att else null,
                    .p_stencil_attachment = if (has_stencil) &stencil_att else null,
                });
                env.rendering_active = true;
                env.rt_rendering = true;
            }
        }
    } else {
        transitionImageLayout(env, res.image, .undefined, .shader_read_only_optimal) catch {
            _ = c.printf("[vk_dmabuf] update: layout transition failed for slot %u\n", id);
            return false;
        };
    }

    return true;
}

/// Lightweight barrier for zero-copy vidp DMA-BUF textures: the client wrote
/// new pixels via mmap, insert a host→shader memory barrier so the GPU sees
/// them. Called from push_buffer's fast path (vidp_glid != 0) instead of
/// re-importing the texture.
export fn vk_env_dmabuf_host_barrier() void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (!env.cmd_recording) return;

    const mem_barrier = [_]vk.MemoryBarrier2{.{
        .src_stage_mask = .{ .host_bit = true },
        .src_access_mask = .{ .host_write_bit = true },
        .dst_stage_mask = .{ .fragment_shader_bit = true },
        .dst_access_mask = .{ .shader_read_bit = true },
    }};
    env.vkd.cmdPipelineBarrier2(env.cmd, &.{
        .memory_barrier_count = mem_barrier.len,
        .p_memory_barriers = &mem_barrier,
    });
}

// GBM DMA-BUF Allocation
// Compositor-side GBM for allocating DMA-BUF backed vidp buffers.
// Loaded at runtime via zig_dlopen (same mechanism as Vulkan/XCB).
// Called from frameserver resize path to provide zero-copy vidp.

const GbmDevice = opaque {};
const GbmBo = opaque {};

const GbmFns = struct {
    create_device: *const fn (c_int) callconv(.c) ?*GbmDevice = undefined,
    device_destroy: *const fn (*GbmDevice) callconv(.c) void = undefined,
    bo_create: *const fn (*GbmDevice, u32, u32, u32, u32) callconv(.c) ?*GbmBo = undefined,
    bo_destroy: *const fn (*GbmBo) callconv(.c) void = undefined,
    bo_map: *const fn (*GbmBo, u32, u32, u32, u32, u32, *u32, *?*anyopaque) callconv(.c) ?*anyopaque = undefined,
    bo_unmap: *const fn (*GbmBo, ?*anyopaque) callconv(.c) void = undefined,
    bo_get_fd: *const fn (*GbmBo) callconv(.c) c_int = undefined,
    bo_get_modifier: *const fn (*GbmBo) callconv(.c) u64 = undefined,
    handle: ?*anyopaque = null,
    dev: ?*GbmDevice = null,
    render_fd: c_int = -1,
};

var gbm: GbmFns = .{};

const GBM_BO_USE_LINEAR: u32 = 1 << 4;
const GBM_BO_USE_WRITE: u32 = 1 << 3;
const DRM_FORMAT_ARGB8888: u32 = 0x34325241;

fn gbmLoad() bool {
    if (gbm.handle != null) return true;

    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const handle = zig_dlopen.zig_dlopen("libgbm.so.1", 1) orelse
        zig_dlopen.zig_dlopen("libgbm.so", 1) orelse
        return false;

    inline for (.{
        .{ "gbm_create_device", "create_device" },
        .{ "gbm_device_destroy", "device_destroy" },
        .{ "gbm_bo_create", "bo_create" },
        .{ "gbm_bo_destroy", "bo_destroy" },
        .{ "gbm_bo_map", "bo_map" },
        .{ "gbm_bo_unmap", "bo_unmap" },
        .{ "gbm_bo_get_fd", "bo_get_fd" },
        .{ "gbm_bo_get_modifier", "bo_get_modifier" },
    }) |entry| {
        const sym = zig_dlopen.zig_dlsym(handle, entry[0]) orelse {
            _ = c.printf("[vk_gbm] missing symbol: %s\n", entry[0].ptr);
            return false;
        };
        @field(gbm, entry[1]) = @ptrCast(@alignCast(sym));
    }

    gbm.handle = handle;
    return true;
}

fn gbmInitDevice() bool {
    if (gbm.dev != null) return true;
    if (!gbmLoad()) return false;

    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const fd = if (builtin.os.tag == .windows) @as(c_int, -1) else std.c.open("/dev/dri/renderD128", .{ .ACCMODE = .RDWR }, @as(c_uint, 0));
    if (fd < 0) {
        _ = c.printf("[vk_gbm] failed to open /dev/dri/renderD128\n");
        return false;
    }

    const dev = gbm.create_device(fd) orelse {
        _ = std.c.close(fd);
        _ = c.printf("[vk_gbm] gbm_create_device failed\n");
        return false;
    };

    gbm.dev = dev;
    gbm.render_fd = fd;
    return true;
}

/// Result of a GBM DMA-BUF allocation — returned to compositor for tracking.
const GbmAllocResult = extern struct {
    fd: c_int,
    map_ptr: ?*anyopaque,
    map_data: ?*anyopaque,
    bo: ?*anyopaque, // opaque GbmBo pointer
    stride: u32,
    modifier_lo: u32,
    modifier_hi: u32,
};

/// Allocate a CPU-mappable DMA-BUF via GBM. Returns fd + mmap pointer.
/// The compositor calls this during resize to provide DMA-BUF backed vidp.
/// Caller must call vk_gbm_free() to release resources.
export fn vk_gbm_alloc(w: u32, h: u32, result: *GbmAllocResult) callconv(.c) bool {
    if (!gbmInitDevice()) {
        _ = c.printf("[vk_gbm] gbmInitDevice() failed\n");
        return false;
    }
    const dev = gbm.dev orelse {
        _ = c.printf("[vk_gbm] gbm.dev is null after init\n");
        return false;
    };

    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const bo = gbm.bo_create(dev, w, h, DRM_FORMAT_ARGB8888,
        GBM_BO_USE_LINEAR) orelse {
        _ = c.printf("[vk_gbm] bo_create failed (%ux%u)\n", w, h);
        return false;
    };

    var map_data: ?*anyopaque = null;
    var stride: u32 = 0;
    const map_ptr = gbm.bo_map(bo, 0, 0, w, h, 3, &stride, &map_data); // 3 = READ_WRITE
    if (map_ptr == null or @intFromPtr(map_ptr) == ~@as(usize, 0)) {
        _ = c.printf("[vk_gbm] bo_map failed (%ux%u)\n", w, h);
        gbm.bo_destroy(bo);
        return false;
    }

    const fd = gbm.bo_get_fd(bo);
    if (fd < 0) {
        gbm.bo_unmap(bo, map_data);
        gbm.bo_destroy(bo);
        return false;
    }

    const modifier = gbm.bo_get_modifier(bo);

    result.* = .{
        .fd = fd,
        .map_ptr = map_ptr,
        .map_data = map_data,
        .bo = @ptrCast(bo),
        .stride = stride,
        .modifier_lo = @truncate(modifier),
        .modifier_hi = @truncate(modifier >> 32),
    };

    return true;
}

/// Free a GBM DMA-BUF allocation.
export fn vk_gbm_free(bo_opaque: ?*anyopaque, map_data: ?*anyopaque) callconv(.c) void {
    const bo: *GbmBo = @ptrCast(@alignCast(bo_opaque orelse return));

    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    if (map_data) |md| gbm.bo_unmap(bo, md);
    gbm.bo_destroy(bo);
}

export fn vk_env_get_active_texture() u32 {
    const env = global_env orelse return 0;
    return env.active_texture;
}

export fn vk_env_bind_texture(id: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (id < MAX_TEXTURES and env.textures[id].in_use) {
        env.active_texture = id;
    }
}


/// Bind a secondary texture to descriptor binding 2 of the primary texture's descriptor set.
/// Used by agp_activate_vstore_multi for 2-texture effects.
export fn vk_env_bind_secondary_texture(tex_id: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (tex_id >= MAX_TEXTURES or !env.textures[tex_id].in_use) return;

    const primary_id = env.active_texture;
    if (primary_id >= MAX_TEXTURES or !env.textures[primary_id].in_use) return;
    if (env.textures[primary_id].descriptor_set == .null_handle) return;

    // Update binding 2 of the primary texture's descriptor set with the secondary texture
    const image_info = [_]vk.DescriptorImageInfo{.{
        .sampler = env.sampler_linear,
        .image_view = env.textures[tex_id].view,
        .image_layout = .shader_read_only_optimal,
    }};
    env.vkd.updateDescriptorSets(env.device, 1, &[_]vk.WriteDescriptorSet{.{
        .dst_set = env.textures[primary_id].descriptor_set,
        .dst_binding = 2,
        .dst_array_element = 0,
        .descriptor_count = 1,
        .descriptor_type = .combined_image_sampler,
        .p_image_info = &image_info,
        .p_buffer_info = undefined,
        .p_texel_buffer_view = undefined,
    }}, 0, null);
}

// Blend Equation Table (matches GL glshared.c:1476-1535)
/// Get blend equation for the given mode. Alpha blend factors come from env
/// (set per-RT by vk_env_set_blend_alpha), matching GL's blend_func_separate
/// which uses env->blend_src_alpha / env->blend_dst_alpha (glshared.c:1487-1535).
fn getBlendEquation(mode: u32, env: *VkEnv) vk.ColorBlendEquationEXT {
    return switch (mode) {
        1, 128 => .{ // BLEND_NORMAL, BLEND_FORCE
            .src_color_blend_factor = .src_alpha,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .color_blend_op = .add,
            .src_alpha_blend_factor = env.blend_src_alpha,
            .dst_alpha_blend_factor = env.blend_dst_alpha,
            .alpha_blend_op = .add,
        },
        2 => .{ // BLEND_ADD
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .one,
            .color_blend_op = .add,
            .src_alpha_blend_factor = env.blend_src_alpha,
            .dst_alpha_blend_factor = env.blend_dst_alpha,
            .alpha_blend_op = .add,
        },
        3 => .{ // BLEND_MULTIPLY
            .src_color_blend_factor = .dst_color,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .color_blend_op = .add,
            .src_alpha_blend_factor = env.blend_src_alpha,
            .dst_alpha_blend_factor = env.blend_dst_alpha,
            .alpha_blend_op = .add,
        },
        4 => .{ // BLEND_SUB
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .color_blend_op = .reverse_subtract,
            .src_alpha_blend_factor = env.blend_src_alpha,
            .dst_alpha_blend_factor = env.blend_dst_alpha,
            .alpha_blend_op = .add,
        },
        5 => .{ // BLEND_PREMUL
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .color_blend_op = .add,
            .src_alpha_blend_factor = env.blend_src_alpha,
            .dst_alpha_blend_factor = env.blend_dst_alpha,
            .alpha_blend_op = .add,
        },
        else => .{ // BLEND_NONE — equation doesn't matter when blend disabled
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
        },
    };
}

export fn vk_env_draw_quad(verts: ?[*]const f32, n_floats: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (!env.rendering_active) return;
    const v = verts orelse return;

    const byte_size = n_floats * @sizeOf(f32);
    const n_verts = n_floats / 4; // 4 floats per vertex (pos2 + uv2)

    // Check vertex buffer space
    if (env.vertex_offset + byte_size > VERTEX_BUFFER_SIZE) {
        env.vertex_offset = 0;
    }

    // Copy vertices to mapped vertex buffer
    const dst = env.vertex_mapped orelse return;
    const src_bytes: [*]const u8 = @ptrCast(v);
    @memcpy(dst[env.vertex_offset .. env.vertex_offset + byte_size], src_bytes[0..byte_size]);

    // Set viewport and scissor — use per-RT viewport (from agp_rendertarget_viewport)
    // when rendering offscreen, or full swapchain extent for screen composite.
    // RT passes: negative viewport height flips Y to match GL clip space.
    // Swapchain composite: standard viewport — RT content stored with GL convention.
    //
    // rt_viewport is set by agp_activate_rendertarget from the RT's viewport[] field.
    // GL: glScissor(vp[0], vp[1], vp[2], vp[3]) + glViewport(same).
    // Values come from arcan_lua.c:1407: agp_rendertarget_viewport(art, x, y, x+view_w, y+view_h)
    // so vp[2] is width and vp[3] is height (when x=0, which is typical).
    const vp = env.rt_viewport;
    const has_vp = (vp[2] > 0 and vp[3] > 0);
    const vp_x: u32 = if (has_vp) @intCast(@max(0, vp[0])) else 0;
    const vp_y: u32 = if (has_vp) @intCast(@max(0, vp[1])) else 0;
    const vp_w: u32 = if (has_vp) @intCast(vp[2]) else if (env.rt_rendering) env.rt_width else env.swapchain_extent_w;
    const vp_h: u32 = if (has_vp) @intCast(vp[3]) else if (env.rt_rendering) env.rt_height else env.swapchain_extent_h;
    const fw: f32 = @floatFromInt(vp_w);
    const fh: f32 = @floatFromInt(vp_h);
    const fx: f32 = @floatFromInt(vp_x);
    const fy: f32 = @floatFromInt(vp_y);
    // Viewport Y strategy depends on the projection matrix convention:
    // - RT pass: engine sends ortho with m[5]>0 (Vulkan-native, Y down) → positive viewport
    // - Composite/swapchain: video.zig sends ortho with m[5]<0 (GL convention, Y up) → negative viewport
    if (env.rt_rendering) {
        env.vkd.cmdSetViewport(env.cmd, 0, 1, @ptrCast(&vk.Viewport{
            .x = fx,
            .y = fy,
            .width = fw,
            .height = fh,
            .min_depth = 0,
            .max_depth = 1,
        }));
    } else {
        env.vkd.cmdSetViewport(env.cmd, 0, 1, @ptrCast(&vk.Viewport{
            .x = fx,
            .y = fy + fh,
            .width = fw,
            .height = -fh,
            .min_depth = 0,
            .max_depth = 1,
        }));
    }
    env.vkd.cmdSetScissor(env.cmd, 0, 1, @ptrCast(&vk.Rect2D{
        .offset = .{ .x = @intCast(vp_x), .y = @intCast(vp_y) },
        .extent = .{ .width = vp_w, .height = vp_h },
    }));

    // Dynamic state — EDS1 (VK 1.3 core) + EDS3
    // Use triangle_list for 6-vertex quads (two explicit triangles), strip for 3/4 verts
    env.vkd.cmdSetPrimitiveTopology(env.cmd, if (n_verts == 6) .triangle_list else .triangle_strip);
    env.vkd.cmdSetCullMode(env.cmd, .{});
    env.vkd.cmdSetFrontFace(env.cmd, .counter_clockwise);
    // Depth state: enabled in PIPELINE_3D, disabled in PIPELINE_2D
    env.vkd.cmdSetDepthTestEnable(env.cmd, if (env.depth_active) .true else .false);
    env.vkd.cmdSetDepthWriteEnable(env.cmd, if (env.depth_active) .true else .false);
    env.vkd.cmdSetDepthCompareOp(env.cmd, if (env.depth_active) .less else .always);
    env.vkd.cmdSetStencilTestEnable(env.cmd, if (env.stencil_active) .true else .false);
    switch (env.stencil_mode) {
        .prepare => {
            // Write to stencil: func=ALWAYS, op=REPLACE, ref=1
            env.vkd.cmdSetStencilOp(env.cmd, .{ .front_bit = true, .back_bit = true }, .replace, .replace, .replace, .always);
            env.vkd.cmdSetStencilCompareMask(env.cmd, .{ .front_bit = true, .back_bit = true }, 0xFF);
            env.vkd.cmdSetStencilWriteMask(env.cmd, .{ .front_bit = true, .back_bit = true }, 0xFF);
            env.vkd.cmdSetStencilReference(env.cmd, .{ .front_bit = true, .back_bit = true }, 1);
        },
        .activated => {
            // Read from stencil: func=EQUAL, op=KEEP, ref=1
            env.vkd.cmdSetStencilOp(env.cmd, .{ .front_bit = true, .back_bit = true }, .keep, .keep, .keep, .equal);
            env.vkd.cmdSetStencilCompareMask(env.cmd, .{ .front_bit = true, .back_bit = true }, 0xFF);
            env.vkd.cmdSetStencilWriteMask(env.cmd, .{ .front_bit = true, .back_bit = true }, 0);
            env.vkd.cmdSetStencilReference(env.cmd, .{ .front_bit = true, .back_bit = true }, 1);
        },
        .off => {
            env.vkd.cmdSetStencilOp(env.cmd, .{ .front_bit = true, .back_bit = true }, .keep, .keep, .keep, .always);
        },
    }

    if (env.active_pipeline < 2) {
        // Built-in shaders (0=basic_2d, 1=color_2d): bind pipeline + descriptor
        const pipeline = if (env.rt_rendering)
            (if (env.active_pipeline == 1) env.color_2d_pipeline_unorm else env.basic_2d_pipeline_unorm)
        else
            (if (env.active_pipeline == 1) env.color_2d_pipeline else env.basic_2d_pipeline);
        env.vkd.cmdBindPipeline(env.cmd, .graphics, pipeline);

        // Bind descriptor set for active texture
        const tex_id = if (env.active_texture < MAX_TEXTURES and env.textures[env.active_texture].in_use)
            env.active_texture
        else
            0; // fallback to default white
        const desc = env.textures[tex_id].descriptor_set;
        if (@intFromEnum(desc) == 0) return; // skip draw if no descriptor set

        const zero_offset = [_]u32{0};
        env.vkd.cmdBindDescriptorSets(env.cmd, .graphics, env.pipeline_layout, 0, 1, @ptrCast(&desc), 1, &zero_offset);
    } else {
        // Custom shaders (active_pipeline >= 2): bind pipeline + descriptor set NOW
        // at draw time, so env.active_texture is correct (engine sets it after
        // agp_shader_activate but before agp_draw_vobj).
        bindCustomShaderNow(env);

    }

    // Blend mode (EDS3) — set AFTER pipeline bind to ensure dynamic state
    // isn't reset by cmdBindPipeline (MoltenVK may reset EDS3 state on bind)
    if (env.has_eds3_blend) {
        const blend_en: u32 = if (env.blend_mode != 0) 1 else 0;
        env.vkd.cmdSetColorBlendEnableEXT(env.cmd, 0, 1, @ptrCast(&blend_en));
        const equation = [_]vk.ColorBlendEquationEXT{getBlendEquation(env.blend_mode, env)};
        env.vkd.cmdSetColorBlendEquationEXT(env.cmd, 0, 1, &equation);

        // Color write mask (disabled during stencil prepare)
        const write_mask = [_]vk.ColorComponentFlags{
            if (env.color_write_enabled)
                .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true }
            else
                .{},
        };
        env.vkd.cmdSetColorWriteMaskEXT(env.cmd, 0, 1, &write_mask);
    }

    // Push constants for ALL draws (engine matrices + opacity used by both built-in
    // and custom vertex/fragment shaders via layout(push_constant))
    env.vkd.cmdPushConstants(env.cmd, env.pipeline_layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, @sizeOf(PushConstants), @ptrCast(&env.push_constants));

    // Bind vertex buffer
    const offsets = [_]vk.DeviceSize{env.vertex_offset};
    env.vkd.cmdBindVertexBuffers(env.cmd, 0, 1, @ptrCast(&env.vertex_buffer), &offsets);

    // Draw
    env.vkd.cmdDraw(env.cmd, n_verts, 1, 0, 0);

    env.vertex_offset += byte_size;
}

export fn vk_env_set_rt_viewport(x: i32, y: i32, w: i32, h: i32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    env.rt_viewport = .{ x, y, w, h };
}

/// Set per-RT alpha blend factors (called from agp_activate_rendertarget).
/// Matches GL glshared.c:1068-1074 — blend_func_separate's alpha src/dst params.
/// retain_alpha=false: src=ONE, dst=ONE (additive alpha blending)
/// retain_alpha=true:  src=SRC_ALPHA, dst=ONE_MINUS_SRC_ALPHA
export fn vk_env_set_blend_alpha(retain_alpha: bool) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (retain_alpha) {
        env.blend_src_alpha = .src_alpha;
        env.blend_dst_alpha = .one_minus_src_alpha;
    } else {
        env.blend_src_alpha = .one;
        env.blend_dst_alpha = .one;
    }
}

export fn vk_env_set_blend_mode(mode: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    env.blend_mode = mode;
}

export fn vk_env_set_color_write(enabled: bool) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    env.color_write_enabled = enabled;
}

export fn vk_env_stencil_begin(w: u32, h: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (env.stencil_image == .null_handle) {
        createStencilImage(env, w, h) catch return;
    }
    env.stencil_active = true;
    env.stencil_mode = .prepare;
}

export fn vk_env_stencil_activate() void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    env.stencil_mode = .activated;
    env.color_write_enabled = true;
}

export fn vk_env_stencil_end() void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    env.stencil_active = false;
    env.stencil_mode = .off;
    env.color_write_enabled = true;
}

export fn vk_env_resize_stencil(w: u32, h: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    destroyStencilImage(env);
    createStencilImage(env, w, h) catch {};
}

/// Set depth testing mode (called from agp_pipeline_hint)
export fn vk_env_set_depth_active(active: bool) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    env.depth_active = active;
    // Lazily create depth image on first 3D use
    if (active and env.depth_image == .null_handle) {
        const w = if (env.swapchain_extent_w > 0) env.swapchain_extent_w else 2048;
        const h = if (env.swapchain_extent_h > 0) env.swapchain_extent_h else 2048;
        createDepthImage(env, w, h) catch {};
    }
}

export fn vk_env_resize_depth(w: u32, h: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    destroyDepthImage(env);
    createDepthImage(env, w, h) catch {};
}

/// Draw vertices with triangle list topology (for mesh rendering).
/// Expects interleaved position(3f) + texcoord(2f) = 20 bytes/vertex.
export fn vk_env_draw_mesh_verts(verts: [*]const u8, byte_size: u32, n_verts: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (!env.rendering_active) return;
    if (byte_size == 0 or n_verts == 0) return;

    // Check vertex buffer space
    if (env.vertex_offset + byte_size > VERTEX_BUFFER_SIZE) {
        env.vertex_offset = 0;
    }

    // Copy to mapped vertex buffer
    const dst = env.vertex_mapped orelse return;
    @memcpy(dst[env.vertex_offset .. env.vertex_offset + byte_size], verts[0..byte_size]);

    // Bind vertex buffer
    const offsets = [_]vk.DeviceSize{@as(vk.DeviceSize, env.vertex_offset)};
    env.vkd.cmdBindVertexBuffers(env.cmd, 0, 1, @ptrCast(&env.vertex_buffer), &offsets);

    // Set viewport and scissor — always negative viewport height for GL Y-flip
    const vp_w = if (env.rt_rendering) env.rt_width else env.swapchain_extent_w;
    const vp_h = if (env.rt_rendering) env.rt_height else env.swapchain_extent_h;
    const fh2: f32 = @floatFromInt(vp_h);
    env.vkd.cmdSetViewport(env.cmd, 0, 1, @ptrCast(&vk.Viewport{
        .x = 0,
        .y = fh2,
        .width = @floatFromInt(vp_w),
        .height = -fh2,
        .min_depth = 0,
        .max_depth = 1,
    }));
    env.vkd.cmdSetScissor(env.cmd, 0, 1, @ptrCast(&vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = .{ .width = vp_w, .height = vp_h },
    }));

    // Dynamic state
    env.vkd.cmdSetCullMode(env.cmd, .{});
    env.vkd.cmdSetFrontFace(env.cmd, .counter_clockwise);
    env.vkd.cmdSetDepthTestEnable(env.cmd, if (env.depth_active) .true else .false);
    env.vkd.cmdSetDepthWriteEnable(env.cmd, if (env.depth_active) .true else .false);
    env.vkd.cmdSetDepthCompareOp(env.cmd, if (env.depth_active) .less else .always);
    env.vkd.cmdSetStencilTestEnable(env.cmd, .false);
    const both: vk.StencilFaceFlags = .{ .front_bit = true, .back_bit = true };
    env.vkd.cmdSetStencilOp(env.cmd, both, .keep, .keep, .keep, .always);

    // Blend
    if (env.has_eds3_blend) {
        const blend_en: u32 = if (env.blend_mode != 0) 1 else 0;
        env.vkd.cmdSetColorBlendEnableEXT(env.cmd, 0, 1, @ptrCast(&blend_en));
        const equation = [_]vk.ColorBlendEquationEXT{getBlendEquation(env.blend_mode, env)};
        env.vkd.cmdSetColorBlendEquationEXT(env.cmd, 0, 1, &equation);
        const write_mask = [_]vk.ColorComponentFlags{
            .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        };
        env.vkd.cmdSetColorWriteMaskEXT(env.cmd, 0, 1, &write_mask);
    }

    // Bind pipeline + descriptors (use basic_2d for now — mesh needs its own pipeline eventually)
    const pipeline = if (env.rt_rendering) env.basic_2d_pipeline_unorm else env.basic_2d_pipeline;
    env.vkd.cmdBindPipeline(env.cmd, .graphics, pipeline);

    const tex_id = if (env.active_texture < MAX_TEXTURES and env.textures[env.active_texture].in_use)
        env.active_texture
    else
        0;
    env.vkd.cmdBindDescriptorSets(
        env.cmd,
        .graphics,
        env.pipeline_layout,
        0,
        1,
        @ptrCast(&env.textures[tex_id].descriptor_set),
        0,
        null,
    );
    env.vkd.cmdPushConstants(env.cmd, env.pipeline_layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, @sizeOf(PushConstants), @ptrCast(&env.push_constants));

    // Draw as triangle list using cmdDraw
    env.vkd.cmdDraw(env.cmd, n_verts, 1, 0, 0);

    env.vertex_offset += byte_size;
}

export fn vk_env_get_push_constants() ?*const PushConstants {
    const env = global_env orelse return null;
    return &env.push_constants;
}

export fn vk_env_bind_pipeline(shid: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    env.active_pipeline = shid;
}

export fn vk_env_push_constants(data: ?[*]const u8, size: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (size != @sizeOf(PushConstants)) return;
    const d = data orelse return;
    const dst: [*]u8 = @ptrCast(&env.push_constants);
    @memcpy(dst[0..size], d[0..size]);
}

export fn vk_env_is_rendering() bool {
    const env = global_env orelse return false;
    return env.rendering_active;
}

export fn vk_env_is_rt_rendering() bool {
    const env = global_env orelse return false;
    return env.rt_rendering;
}

// Bridge Functions for Custom Shaders (called from vk_shdrmgmt.zig)

export fn vk_env_create_shader_module(spv_ptr: [*]const u8, spv_len: u32) u64 {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return 0;
    const len: usize = spv_len;

    // SPIR-V must be u32-aligned for Vulkan. The caller may pass unaligned
    // data (e.g. @embedFile across C ABI erases alignment metadata).
    // Check actual pointer alignment; copy to heap if needed.
    const aligned_ptr: [*]align(4) const u8 = if (@intFromPtr(spv_ptr) % 4 == 0)
        @alignCast(spv_ptr)
    else blk: {
        const buf = std.heap.c_allocator.alignedAlloc(u8, .@"4", len) catch return 0;
        @memcpy(buf, spv_ptr[0..len]);
        break :blk buf.ptr;
    };

    const module = env.vkd.createShaderModule(env.device, &.{
        .code_size = spv_len,
        .p_code = @ptrCast(aligned_ptr),
    }, null) catch return 0;
    return @bitCast(@intFromEnum(module));
}

export fn vk_env_destroy_shader_module(handle: u64) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (handle == 0) return;
    const module: vk.ShaderModule = @enumFromInt(@as(u64, @bitCast(handle)));
    env.vkd.destroyShaderModule(env.device, module, null);
}

export fn vk_env_create_custom_pipeline(
    vert_handle: u64,
    frag_handle: u64,
    format_val: u32,
) u64 {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return 0;
    const vert_mod: vk.ShaderModule = @enumFromInt(@as(u64, @bitCast(vert_handle)));
    const frag_mod: vk.ShaderModule = @enumFromInt(@as(u64, @bitCast(frag_handle)));
    const color_format: vk.Format = @enumFromInt(format_val);
    const pipeline = createGraphicsPipeline(env, vert_mod, frag_mod, color_format, .undefined, .undefined) catch return 0;
    return @bitCast(@intFromEnum(pipeline));
}

export fn vk_env_destroy_pipeline(handle: u64) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (handle == 0) return;
    const pipeline: vk.Pipeline = @enumFromInt(@as(u64, @bitCast(handle)));
    env.vkd.destroyPipeline(env.device, pipeline, null);
}

export fn vk_env_create_ubo(size: u32, stride: u32, out_mapped: *?[*]u8, out_desc_set: *u64) u64 {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return 0;

    // Create host-visible, coherent buffer for UBO
    const buf_result = createBuffer(
        env,
        size,
        .{ .uniform_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    ) catch return 0;

    // Map the buffer
    const mapped: [*]u8 = @ptrCast(env.vkd.mapMemory(
        env.device,
        buf_result.memory,
        0,
        size,
        .{},
    ) catch {
        env.vkd.destroyBuffer(env.device, buf_result.buffer, null);
        env.vkd.freeMemory(env.device, buf_result.memory, null);
        return 0;
    });
    out_mapped.* = mapped;

    // Allocate descriptor set
    const layouts = [_]vk.DescriptorSetLayout{env.descriptor_set_layout};
    var desc_sets: [1]vk.DescriptorSet = undefined;
    env.vkd.allocateDescriptorSets(env.device, &.{
        .descriptor_pool = env.descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = &layouts,
    }, &desc_sets) catch {
        env.vkd.unmapMemory(env.device, buf_result.memory);
        env.vkd.destroyBuffer(env.device, buf_result.buffer, null);
        env.vkd.freeMemory(env.device, buf_result.memory, null);
        return 0;
    };
    out_desc_set.* = @bitCast(@intFromEnum(desc_sets[0]));

    // Write the UBO descriptor at binding 1
    // We also need to write a dummy sampler at binding 0 so the set is valid.
    const ubo_info = [_]vk.DescriptorBufferInfo{.{
        .buffer = buf_result.buffer,
        .offset = 0,
        .range = if (stride > 0) stride else size, // per-group stride; dynamic offset selects the group
    }};
    const dummy_image_info = [_]vk.DescriptorImageInfo{.{
        .sampler = env.sampler_linear,
        .image_view = env.textures[0].view, // default white texture
        .image_layout = .shader_read_only_optimal,
    }};
    env.vkd.updateDescriptorSets(env.device, 4, &[_]vk.WriteDescriptorSet{
        .{
            .dst_set = desc_sets[0],
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &dummy_image_info,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = desc_sets[0],
            .dst_binding = 1,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .uniform_buffer_dynamic,
            .p_image_info = undefined,
            .p_buffer_info = &ubo_info,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = desc_sets[0],
            .dst_binding = 2,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &dummy_image_info, // same dummy sampler for binding 2
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = desc_sets[0],
            .dst_binding = 3,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &dummy_image_info, // dummy sampler for SDF atlas binding 3
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
    }, 0, null);

    // Return buffer handle; memory handle is stored by caller via the pair
    // We pack buffer + memory into a single return by storing memory handle in a global
    // Actually, let's return a packed struct via two out params.
    // For simplicity: return buffer as u64, store memory as second return via another export.
    // Better: store the memory handle so we can free it later.
    // The caller will track both handles. We return buffer_handle here.
    // We'll use a separate bridge to destroy.
    // Store memory alongside — we'll encode both handles.
    // Simplest: return buffer, let caller also call vk_env_get_ubo_memory to get memory handle.
    last_ubo_memory = @bitCast(@intFromEnum(buf_result.memory));
    return @bitCast(@intFromEnum(buf_result.buffer));
}

var last_ubo_memory: u64 = 0;

export fn vk_env_get_last_ubo_memory() u64 {
    return last_ubo_memory;
}

export fn vk_env_destroy_ubo(buf_handle: u64, mem_handle: u64, desc_handle: u64) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (mem_handle != 0) {
        const memory: vk.DeviceMemory = @enumFromInt(@as(u64, @bitCast(mem_handle)));
        env.vkd.unmapMemory(env.device, memory);
        env.vkd.freeMemory(env.device, memory, null);
    }
    if (buf_handle != 0) {
        const buffer: vk.Buffer = @enumFromInt(@as(u64, @bitCast(buf_handle)));
        env.vkd.destroyBuffer(env.device, buffer, null);
    }
    if (desc_handle != 0) {
        const desc_set: vk.DescriptorSet = @enumFromInt(@as(u64, @bitCast(desc_handle)));
        env.vkd.freeDescriptorSets(env.device, env.descriptor_pool, 1, @ptrCast(&desc_set)) catch {};
    }
}

export fn vk_env_get_ubo_alignment() u32 {
    const env = global_env orelse return 256;
    const props = env.vki.getPhysicalDeviceProperties(env.physical_device);
    const align_val = props.limits.min_uniform_buffer_offset_alignment;
    return if (align_val > 0) @intCast(align_val) else 256;
}

export fn vk_env_get_swapchain_format() u32 {
    const env = global_env orelse return @bitCast(@as(i32, @intFromEnum(vk.Format.b8g8r8a8_unorm)));
    return @bitCast(@as(i32, @intFromEnum(env.swapchain_format)));
}

/// Save custom shader bind parameters for deferred binding at draw time.
/// The actual descriptor set allocation + pipeline/descriptor bind happens in
/// vk_env_draw_quad, so that env.active_texture is correct (engine sets it
/// between agp_shader_activate and agp_draw_vobj).
export fn vk_env_bind_custom_shader(pipeline_handle: u64, ubo_buf_handle: u64, ubo_stride: u32, dynamic_offset: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    env.pending_custom_pipeline = pipeline_handle;
    env.pending_custom_ubo_buf = ubo_buf_handle;
    env.pending_custom_ubo_stride = ubo_stride;
    env.pending_custom_dyn_offset = dynamic_offset;
    env.pending_custom_valid = true;
}

/// Actually bind the custom shader pipeline + descriptor set with the current
/// active texture. Called from vk_env_draw_quad at draw time.
fn bindCustomShaderNow(env: *VkEnv) void {
    if (!env.pending_custom_valid) return;

    const pipeline: vk.Pipeline = @enumFromInt(@as(u64, @bitCast(env.pending_custom_pipeline)));
    env.vkd.cmdBindPipeline(env.cmd, .graphics, pipeline);

    // Allocate a FRESH descriptor set from the per-frame pool for this draw.
    // On tile-based deferred renderers (Asahi AGX), all draws in a render pass
    // are deferred, so they'd all see the LAST texture written to a shared set.
    const layouts = [_]vk.DescriptorSetLayout{env.descriptor_set_layout};
    var desc_sets: [1]vk.DescriptorSet = undefined;
    env.vkd.allocateDescriptorSets(env.device, &.{
        .descriptor_pool = env.frame_desc_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = &layouts,
    }, &desc_sets) catch {
        // Pool exhausted — fall back to texture's own descriptor set (no UBO)
        const tex_id = if (env.active_texture < MAX_TEXTURES and env.textures[env.active_texture].in_use)
            env.active_texture
        else
            0;
        const fallback_desc = env.textures[tex_id].descriptor_set;
        const zero_off = [_]u32{0};
        env.vkd.cmdBindDescriptorSets(env.cmd, .graphics, env.pipeline_layout, 0, 1, @ptrCast(&fallback_desc), 1, &zero_off);
        env.vkd.cmdPushConstants(env.cmd, env.pipeline_layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, @sizeOf(PushConstants), @ptrCast(&env.push_constants));
        return;
    };
    const frame_desc = desc_sets[0];

    // Write all 4 bindings into the fresh set:
    //   binding 0: active texture (sampler)
    //   binding 1: shader UBO (dynamic offset selects uniform group)
    //   binding 2: active texture (secondary sampler, mirrors primary)
    //   binding 3: dummy SDF atlas sampler
    const tex_id = if (env.active_texture < MAX_TEXTURES and env.textures[env.active_texture].in_use)
        env.active_texture
    else
        0;
    const image_info = [_]vk.DescriptorImageInfo{.{
        .sampler = env.sampler_linear,
        .image_view = env.textures[tex_id].view,
        .image_layout = .shader_read_only_optimal,
    }};

    const ubo_buffer: vk.Buffer = @enumFromInt(@as(u64, @bitCast(env.pending_custom_ubo_buf)));
    const ubo_info = [_]vk.DescriptorBufferInfo{.{
        .buffer = ubo_buffer,
        .offset = 0,
        .range = if (env.pending_custom_ubo_stride > 0) env.pending_custom_ubo_stride else 256,
    }};

    env.vkd.updateDescriptorSets(env.device, 4, &[_]vk.WriteDescriptorSet{
        .{
            .dst_set = frame_desc,
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &image_info,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = frame_desc,
            .dst_binding = 1,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .uniform_buffer_dynamic,
            .p_image_info = undefined,
            .p_buffer_info = &ubo_info,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = frame_desc,
            .dst_binding = 2,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &image_info,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .dst_set = frame_desc,
            .dst_binding = 3,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &image_info, // dummy sampler for SDF atlas binding 3
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        },
    }, 0, null);

    // DIAGNOSTIC: log custom shader bind state
    // Bind the fresh set with the UBO dynamic offset
    const offsets = [_]u32{env.pending_custom_dyn_offset};
    env.vkd.cmdBindDescriptorSets(env.cmd, .graphics, env.pipeline_layout, 0, 1, @ptrCast(&frame_desc), 1, &offsets);

    // Push constants for engine uniforms (modelview/projection via vertex shader)
    env.vkd.cmdPushConstants(env.cmd, env.pipeline_layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, @sizeOf(PushConstants), @ptrCast(&env.push_constants));
}

export fn vk_env_update_ubo_texture(desc_handle: u64, tex_id: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (tex_id >= MAX_TEXTURES or !env.textures[tex_id].in_use) return;

    const desc_set: vk.DescriptorSet = @enumFromInt(@as(u64, @bitCast(desc_handle)));
    const image_info = [_]vk.DescriptorImageInfo{.{
        .sampler = env.sampler_linear,
        .image_view = env.textures[tex_id].view,
        .image_layout = .shader_read_only_optimal,
    }};
    env.vkd.updateDescriptorSets(env.device, 1, &[_]vk.WriteDescriptorSet{.{
        .dst_set = desc_set,
        .dst_binding = 0,
        .dst_array_element = 0,
        .descriptor_count = 1,
        .descriptor_type = .combined_image_sampler,
        .p_image_info = &image_info,
        .p_buffer_info = undefined,
        .p_texel_buffer_view = undefined,
    }}, 0, null);
}

// Phase 4: Rendertarget Pass Functions

/// Start recording the main command buffer for a new frame.
/// Called by video.zig before arcan_vint_refresh() so all RT passes share one cmd buffer.
export fn vk_env_begin_frame_cmd() void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;

    // Wait for previous frame's cmd buffer to complete
    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.frame_fence), .true, std.math.maxInt(u64)) catch {};
    _ = env.vkd.resetFences(env.device, 1, @ptrCast(&env.frame_fence)) catch {};

    // Destroy textures deferred from last frame (GPU finished, safe now)
    env.flushDeferred();

    // Reset per-frame descriptor pool (previous frame completed, safe to reset)
    if (env.frame_desc_pool != .null_handle) {
        env.vkd.resetDescriptorPool(env.device, env.frame_desc_pool, .{}) catch {};
    }

    env.vkd.resetCommandBuffer(env.cmd, .{}) catch return;
    env.vkd.beginCommandBuffer(env.cmd, &.{
        .flags = .{ .one_time_submit_bit = true },
    }) catch return;

    env.cmd_recording = true;
    env.vertex_offset = 0;
}

/// Submit the current command buffer with only a fence (no semaphores/presentation).
/// Used when skipping a frame so the fence is signaled for the next begin_frame_cmd.
export fn vk_env_submit_empty_frame() void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;

    env.cmd_recording = false;
    env.vkd.endCommandBuffer(env.cmd) catch return;

    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{
        .command_buffer = env.cmd,
        .device_mask = 0,
    }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = cmd_info.len,
        .p_command_buffer_infos = &cmd_info,
    }}, env.frame_fence) catch {};
}

export fn vk_env_begin_rt_pass(tex_id: u32, w: u32, h: u32) bool {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return false;
    if (tex_id >= MAX_TEXTURES or !env.textures[tex_id].in_use) return false;

    // Out-of-frame RT pass (e.g. resample_image during Lua init):
    // Start recording the main cmd buffer so draw commands aren't lost.
    if (!env.cmd_recording) {
        env.vkd.deviceWaitIdle(env.device) catch {};
        env.vkd.resetCommandBuffer(env.cmd, .{}) catch return false;
        env.vkd.beginCommandBuffer(env.cmd, &.{
            .flags = .{ .one_time_submit_bit = true },
        }) catch return false;
        env.cmd_recording = true;
        env.vertex_offset = 0;
    }

    const slot = &env.textures[tex_id];


    // Barrier: SHADER_READ_ONLY → COLOR_ATTACHMENT_OPTIMAL
    const to_color = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .fragment_shader_bit = true }, .src_access_mask = .{ .shader_read_bit = true }, .dst_stage_mask = .{ .color_attachment_output_bit = true }, .dst_access_mask = .{ .color_attachment_write_bit = true, .color_attachment_read_bit = true }, .old_layout = .shader_read_only_optimal, .new_layout = .color_attachment_optimal, .image = slot.image, })};
    env.vkd.cmdPipelineBarrier2(env.cmd, &.{
        .image_memory_barrier_count = to_color.len,
        .p_image_memory_barriers = &to_color,
    });

    // Begin dynamic rendering into this texture
    // First use of a texture as RT must clear (Vulkan images start undefined).
    // Subsequent uses load existing content (NOCLEAR RTs, icon caches, etc.).
    const first_use = !slot.rt_initialized;
    if (first_use) {
        slot.rt_initialized = true;
    }
    const color_attachment = [_]vk.RenderingAttachmentInfo{.{
        .image_view = slot.view,
        .image_layout = .color_attachment_optimal,
        .resolve_mode = .{},
        .resolve_image_layout = .undefined,
        .load_op = if (first_use) .clear else .load,
        .store_op = .store,
        .clear_value = .{ .color = .{ .float_32 = .{ 0, 0, 0, 0 } } },
    }};
    // Optional depth attachment
    const depth_att = vk.RenderingAttachmentInfo{
        .image_view = env.depth_view,
        .image_layout = .depth_stencil_attachment_optimal,
        .resolve_mode = .{},
        .resolve_image_layout = .undefined,
        .load_op = .clear,
        .store_op = .dont_care,
        .clear_value = .{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
    };
    const has_depth = env.depth_active and env.depth_view != .null_handle;

    // Optional stencil attachment
    const stencil_att = vk.RenderingAttachmentInfo{
        .image_view = env.stencil_view,
        .image_layout = .depth_stencil_attachment_optimal,
        .resolve_mode = .{},
        .resolve_image_layout = .undefined,
        .load_op = .clear,
        .store_op = .dont_care,
        .clear_value = .{ .depth_stencil = .{ .depth = 0, .stencil = 0 } },
    };
    const has_stencil = env.stencil_active and env.stencil_view != .null_handle;

    env.vkd.cmdBeginRendering(env.cmd, &.{
        .render_area = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = w, .height = h },
        },
        .layer_count = 1,
        .view_mask = 0,
        .color_attachment_count = color_attachment.len,
        .p_color_attachments = &color_attachment,
        .p_depth_attachment = if (has_depth) &depth_att else null,
        .p_stencil_attachment = if (has_stencil) &stencil_att else null,
    });

    // Set RT state
    env.rendering_active = true;
    env.rt_rendering = true;
    env.rt_width = w;
    env.rt_height = h;
    env.rt_active_tex = tex_id;

    return true;
}

export fn vk_env_end_rt_pass() void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (!env.rt_rendering) return;

    const tex_id = env.rt_active_tex;
    if (tex_id >= MAX_TEXTURES or !env.textures[tex_id].in_use) return;

    // End rendering
    env.vkd.cmdEndRendering(env.cmd);

    // Barrier: COLOR_ATTACHMENT_OPTIMAL → SHADER_READ_ONLY_OPTIMAL
    const to_shader = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .color_attachment_output_bit = true }, .src_access_mask = .{ .color_attachment_write_bit = true }, .dst_stage_mask = .{ .fragment_shader_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .color_attachment_optimal, .new_layout = .shader_read_only_optimal, .image = env.textures[tex_id].image, })};
    env.vkd.cmdPipelineBarrier2(env.cmd, &.{
        .image_memory_barrier_count = to_shader.len,
        .p_image_memory_barriers = &to_shader,
    });

    // Clear RT state (cmd buffer stays recording for next RT or swapchain pass)
    env.rendering_active = false;
    env.rt_rendering = false;
}

export fn vk_env_rt_clear(r: f32, g: f32, b: f32, a: f32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (!env.rendering_active) return;

    const clear_attachment = [_]vk.ClearAttachment{.{
        .aspect_mask = .{ .color_bit = true },
        .color_attachment = 0,
        .clear_value = .{ .color = .{ .float_32 = .{ r, g, b, a } } },
    }};

    const vp_w = if (env.rt_rendering) env.rt_width else env.swapchain_extent_w;
    const vp_h = if (env.rt_rendering) env.rt_height else env.swapchain_extent_h;
    const clear_rect = [_]vk.ClearRect{.{
        .rect = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = vp_w, .height = vp_h },
        },
        .base_array_layer = 0,
        .layer_count = 1,
    }};
    env.vkd.cmdClearAttachments(env.cmd, clear_attachment.len, &clear_attachment, clear_rect.len, &clear_rect);
}

export fn vk_env_readback_texture(tex_id: u32, dst: [*]u8, dst_sz: u32) bool {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return false;
    if (tex_id >= MAX_TEXTURES or !env.textures[tex_id].in_use) return false;

    const slot = &env.textures[tex_id];
    const size: usize = @as(usize, slot.width) * @as(usize, slot.height) * 4;
    if (size > STAGING_BUFFER_SIZE) return false;

    // If the main cmd buffer has pending draws (out-of-frame resample),
    // submit it now so the GPU actually renders before we readback.
    if (env.cmd_recording) {
        // End any active RT pass first
        if (env.rt_rendering) {
            env.vkd.cmdEndRendering(env.cmd);
            // Barrier: COLOR_ATTACHMENT → SHADER_READ_ONLY
            const flush_barrier = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .color_attachment_output_bit = true }, .src_access_mask = .{ .color_attachment_write_bit = true }, .dst_stage_mask = .{ .fragment_shader_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .color_attachment_optimal, .new_layout = .shader_read_only_optimal, .image = env.textures[env.rt_active_tex].image, })};
            env.vkd.cmdPipelineBarrier2(env.cmd, &.{
                .image_memory_barrier_count = flush_barrier.len,
                .p_image_memory_barriers = &flush_barrier,
            });
            env.rendering_active = false;
            env.rt_rendering = false;
        }
        env.cmd_recording = false;
        env.vkd.endCommandBuffer(env.cmd) catch return false;
        const flush_cmd = [_]vk.CommandBufferSubmitInfo{.{
            .command_buffer = env.cmd,
            .device_mask = 0,
        }};
        // Use upload_fence (not frame_fence) to avoid deadlock with begin_frame_cmd
        env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
            .command_buffer_info_count = flush_cmd.len,
            .p_command_buffer_infos = &flush_cmd,
        }}, env.upload_fence) catch return false;
        _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch return false;
        _ = env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch return false;
    }

    // Use upload_cmd for readback (separate from RT cmd)
    env.vkd.resetCommandBuffer(env.upload_cmd, .{}) catch return false;
    env.vkd.beginCommandBuffer(env.upload_cmd, &.{
        .flags = .{ .one_time_submit_bit = true },
    }) catch return false;

    // Barrier: SHADER_READ_ONLY → TRANSFER_SRC
    const to_transfer = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .fragment_shader_bit = true }, .src_access_mask = .{ .shader_read_bit = true }, .dst_stage_mask = .{ .all_transfer_bit = true }, .dst_access_mask = .{ .transfer_read_bit = true }, .old_layout = .shader_read_only_optimal, .new_layout = .transfer_src_optimal, .image = slot.image, })};
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = to_transfer.len,
        .p_image_memory_barriers = &to_transfer,
    });

    // Copy image to staging buffer
    // SH backend miscompiles nested-literal vk.BufferImageCopy — use the
    // field-by-field helper. See sh_vk_buffer_image_copy_init_miscompile.md.
    const region = [_]vk.BufferImageCopy{fullImageCopyRegion(0, 0, slot.width, slot.height)};
    env.vkd.cmdCopyImageToBuffer(
        env.upload_cmd,
        slot.image,
        .transfer_src_optimal,
        env.staging_buffer,
        region.len,
        &region,
    );

    // Barrier: TRANSFER_SRC → SHADER_READ_ONLY
    const to_shader = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .all_transfer_bit = true }, .src_access_mask = .{ .transfer_read_bit = true }, .dst_stage_mask = .{ .fragment_shader_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .transfer_src_optimal, .new_layout = .shader_read_only_optimal, .image = slot.image, })};
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = to_shader.len,
        .p_image_memory_barriers = &to_shader,
    });

    env.vkd.endCommandBuffer(env.upload_cmd) catch return false;

    // Submit and wait
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{
        .command_buffer = env.upload_cmd,
        .device_mask = 0,
    }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = cmd_info.len,
        .p_command_buffer_infos = &cmd_info,
    }}, env.upload_fence) catch return false;

    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch return false;
    _ = env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch return false;

    // Copy from staging to destination
    const staging = env.staging_mapped orelse return false;
    const copy_sz = @min(size, @as(usize, dst_sz));

    @memcpy(dst[0..copy_sz], staging[0..copy_sz]);

    return true;
}

/// Submit async readback of a texture — copies to staging[idx] and advances ping-pong.
/// Returns immediately; poll with vk_env_readback_async_poll to get data.
export fn vk_env_readback_async_submit(tex_id: u32) void {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return;
    if (tex_id >= MAX_TEXTURES or !env.textures[tex_id].in_use) return;

    const slot = &env.textures[tex_id];
    const size: usize = @as(usize, slot.width) * @as(usize, slot.height) * 4;
    if (size > STAGING_BUFFER_SIZE) return;

    const idx: usize = env.readback_idx;

    // Wait for this slot's previous readback to finish (if any)
    if (env.readback_pending[idx]) {
        _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.readback_fence[idx]), .true, std.math.maxInt(u64)) catch return;
        env.readback_pending[idx] = false;
    }
    env.vkd.resetFences(env.device, 1, @ptrCast(&env.readback_fence[idx])) catch return;

    // Record copy command
    env.vkd.resetCommandBuffer(env.readback_cmd[idx], .{}) catch return;
    env.vkd.beginCommandBuffer(env.readback_cmd[idx], &.{
        .flags = .{ .one_time_submit_bit = true },
    }) catch return;

    // Barrier: SHADER_READ_ONLY → TRANSFER_SRC
    const to_transfer = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .fragment_shader_bit = true }, .src_access_mask = .{ .shader_read_bit = true }, .dst_stage_mask = .{ .all_transfer_bit = true }, .dst_access_mask = .{ .transfer_read_bit = true }, .old_layout = .shader_read_only_optimal, .new_layout = .transfer_src_optimal, .image = slot.image, })};
    env.vkd.cmdPipelineBarrier2(env.readback_cmd[idx], &.{
        .image_memory_barrier_count = to_transfer.len,
        .p_image_memory_barriers = &to_transfer,
    });

    // Copy image to readback staging buffer
    // SH backend nested-literal miscompile workaround — see fullImageCopyRegion.
    const region = [_]vk.BufferImageCopy{fullImageCopyRegion(0, 0, slot.width, slot.height)};
    env.vkd.cmdCopyImageToBuffer(
        env.readback_cmd[idx],
        slot.image,
        .transfer_src_optimal,
        env.readback_staging[idx],
        region.len,
        &region,
    );

    // Barrier: TRANSFER_SRC → SHADER_READ_ONLY
    const to_shader = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .all_transfer_bit = true }, .src_access_mask = .{ .transfer_read_bit = true }, .dst_stage_mask = .{ .fragment_shader_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .transfer_src_optimal, .new_layout = .shader_read_only_optimal, .image = slot.image, })};
    env.vkd.cmdPipelineBarrier2(env.readback_cmd[idx], &.{
        .image_memory_barrier_count = to_shader.len,
        .p_image_memory_barriers = &to_shader,
    });

    env.vkd.endCommandBuffer(env.readback_cmd[idx]) catch return;

    // Submit — signal fence but don't wait
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{
        .command_buffer = env.readback_cmd[idx],
        .device_mask = 0,
    }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = cmd_info.len,
        .p_command_buffer_infos = &cmd_info,
    }}, env.readback_fence[idx]) catch return;

    env.readback_pending[idx] = true;
    env.readback_w[idx] = slot.width;
    env.readback_h[idx] = slot.height;

    // Advance ping-pong
    env.readback_idx = 1 - env.readback_idx;
}

/// Poll the OTHER slot (previous frame's readback). Returns pointer + dimensions if ready.
export fn vk_env_readback_async_poll(out_w: *u32, out_h: *u32) ?[*]u8 {
    // TLS switch: may be called from Lua (musl TLS) outside synchDisplay's wrapping
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const env = global_env orelse return null;

    // Poll the slot that was submitted BEFORE the current one
    const poll_idx: usize = 1 - env.readback_idx;
    if (!env.readback_pending[poll_idx]) return null;

    // Non-blocking fence check (timeout=0)
    const result = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.readback_fence[poll_idx]), .true, 0) catch return null;
    if (result != .success) return null; // not ready yet

    env.readback_pending[poll_idx] = false;
    out_w.* = env.readback_w[poll_idx];
    out_h.* = env.readback_h[poll_idx];
    return env.readback_mapped[poll_idx];
}

export fn vk_env_set_rendering_active(active: bool) void {
    const env = global_env orelse return;
    env.rendering_active = active;
}

export fn vk_env_set_swapchain_extent(w: u32, h: u32) void {
    const env = global_env orelse return;
    env.swapchain_extent_w = w;
    env.swapchain_extent_h = h;
}

// Exported AGP Functions (C ABI)

export fn agp_init() void {
    // No-op: Vulkan init happens via agp_vk_init() called from platform video
}

export fn agp_ident() [*:0]const u8 {
    return "VULKAN14";
}

export fn agp_backend_ident() [*:0]const u8 {
    return "VULKAN14";
}

export fn agp_shader_language() [*:0]const u8 {
    return "GLSL120";
}

const envopts_list = [_:null]?[*:0]const u8{
    "ARCAN_VIDEO_VK_VALIDATION=1",
    "enable Vulkan validation layers",
    null,
};

export fn agp_envopts() [*]const ?[*:0]const u8 {
    return &envopts_list;
}

export fn agp_accelerated() bool {
    return true;
}

export fn agp_status_ok(msg: ?*[*:0]const u8) bool {
    if (msg) |m| m.* = "Vulkan AGP OK";
    return global_env != null;
}

export fn agp_alloc_fenv(
    lookup: ?*anyopaque,
    tag: ?*anyopaque,
) ?*c.struct_agp_fenv {
    _ = lookup;
    _ = tag;
    return null;
}

export fn agp_env() ?*c.struct_agp_fenv {
    return null;
}

export fn agp_setenv(fenv: ?*c.struct_agp_fenv) void {
    _ = fenv;
}

export fn agp_dropenv(fenv: ?*c.struct_agp_fenv) void {
    _ = fenv;
}

/// Read pixels from the last-presented swapchain image (matches GL glReadPixels).
export fn agp_save_output(w: usize, h: usize, dst: ?[*]u32, dsz: usize) void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return;
    const out = dst orelse return;
    if (w == 0 or h == 0) return;

    const size: usize = w * h * @sizeOf(u32);
    if (dsz < size) return;
    if (env.last_presented_image == .null_handle) return;
    if (size > STAGING_BUFFER_SIZE) return;

    // Use upload_cmd for readback (separate from main cmd)
    env.vkd.resetCommandBuffer(env.upload_cmd, .{}) catch return;
    env.vkd.beginCommandBuffer(env.upload_cmd, &.{
        .flags = .{ .one_time_submit_bit = true },
    }) catch return;

    // Barrier: PRESENT_SRC → TRANSFER_SRC
    const to_transfer = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .bottom_of_pipe_bit = true }, .src_access_mask = .{}, .dst_stage_mask = .{ .all_transfer_bit = true }, .dst_access_mask = .{ .transfer_read_bit = true }, .old_layout = .present_src_khr, .new_layout = .transfer_src_optimal, .image = env.last_presented_image, })};
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = to_transfer.len,
        .p_image_memory_barriers = &to_transfer,
    });

    // Copy image to staging buffer (nested-literal miscompile workaround).
    const region = [_]vk.BufferImageCopy{fullImageCopyRegion(0, 0, @intCast(w), @intCast(h))};
    env.vkd.cmdCopyImageToBuffer(
        env.upload_cmd,
        env.last_presented_image,
        .transfer_src_optimal,
        env.staging_buffer,
        region.len,
        &region,
    );

    // Barrier: TRANSFER_SRC → PRESENT_SRC (restore for next present)
    const to_present = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .all_transfer_bit = true }, .src_access_mask = .{ .transfer_read_bit = true }, .dst_stage_mask = .{ .top_of_pipe_bit = true }, .dst_access_mask = .{}, .old_layout = .transfer_src_optimal, .new_layout = .present_src_khr, .image = env.last_presented_image, })};
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = to_present.len,
        .p_image_memory_barriers = &to_present,
    });

    env.vkd.endCommandBuffer(env.upload_cmd) catch return;

    // Submit and wait
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{
        .command_buffer = env.upload_cmd,
        .device_mask = 0,
    }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = cmd_info.len,
        .p_command_buffer_infos = &cmd_info,
    }}, env.upload_fence) catch return;
    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch return;
    env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch return;

    // Copy from staging to destination
    if (env.staging_mapped) |mapped| {
        @memcpy(@as([*]u8, @ptrCast(out))[0..size], mapped[0..size]);
    }
}

/// Dump current swapchain frame as PPM to /tmp/arcan_screen.ppm
export fn agp_save_ppm() void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    const env = global_env orelse return;
    if (env.last_presented_image == .null_handle) return;

    const w = env.swapchain_extent_w;
    const h = env.swapchain_extent_h;
    if (w == 0 or h == 0) return;
    const size: usize = @as(usize, w) * @as(usize, h) * 4;
    if (size > STAGING_BUFFER_SIZE) return;

    // Readback via upload_cmd
    env.vkd.resetCommandBuffer(env.upload_cmd, .{}) catch return;
    env.vkd.beginCommandBuffer(env.upload_cmd, &.{ .flags = .{ .one_time_submit_bit = true } }) catch return;
    const present_layout = env.last_presented_layout;
    const to_xfer = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .bottom_of_pipe_bit = true }, .src_access_mask = .{}, .dst_stage_mask = .{ .all_transfer_bit = true }, .dst_access_mask = .{ .transfer_read_bit = true }, .old_layout = present_layout, .new_layout = .transfer_src_optimal, .image = env.last_presented_image, })};
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{ .image_memory_barrier_count = 1, .p_image_memory_barriers = &to_xfer });
    const region = [_]vk.BufferImageCopy{fullImageCopyRegion(0, 0, w, h)};
    env.vkd.cmdCopyImageToBuffer(env.upload_cmd, env.last_presented_image, .transfer_src_optimal, env.staging_buffer, 1, &region);
    const to_present = [_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .all_transfer_bit = true }, .src_access_mask = .{ .transfer_read_bit = true }, .dst_stage_mask = .{ .top_of_pipe_bit = true }, .dst_access_mask = .{}, .old_layout = .transfer_src_optimal, .new_layout = present_layout, .image = env.last_presented_image, })};
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{ .image_memory_barrier_count = 1, .p_image_memory_barriers = &to_present });
    env.vkd.endCommandBuffer(env.upload_cmd) catch return;
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{ .command_buffer = env.upload_cmd, .device_mask = 0 }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = 1, .p_command_buffer_infos = &cmd_info,
    }}, env.upload_fence) catch return;
    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch return;
    env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch return;

    const mapped = env.staging_mapped orelse return;

    // Write PPM (P6)
    const f = std.c.fopen("/tmp/arcan_screen.ppm", "wb") orelse return;
    defer _ = std.c.fclose(f);
    var hdr: [64]u8 = undefined;
    const hlen = std.fmt.bufPrint(&hdr, "P6\n{d} {d}\n255\n", .{ w, h }) catch return;
    _ = std.c.fwrite(hlen.ptr, 1, hlen.len, f);
    // Convert BGRA -> RGB
    for (0..@as(usize, h)) |y| {
        for (0..@as(usize, w)) |x| {
            const off = (y * @as(usize, w) + x) * 4;
            const rgb = [3]u8{ mapped[off + 2], mapped[off + 1], mapped[off] };
            _ = std.c.fwrite(&rgb, 1, 3, f);
        }
    }
}

export fn agp_render_options(opts: c.struct_agp_render_options) void {
    _ = opts;
}

// agp_readback_synchronous, agp_request_readback, agp_poll_readback
// are implemented in vk_shared.zig (Phase 4)

// ============================================================================
// GPU Frame Capture — Shift 10: capture arcan+durian+hem for Mac Studio replay
// ============================================================================
// Triggered by: ARCAN_FRAME_CAPTURE=<dir> + SIGUSR1 (or auto at frame N via ARCAN_CAPTURE_FRAME=N)
// Outputs:
//   <dir>/framebuffer.bin  — raw BGRA8 pixels of composited frame
//   <dir>/tex_<id>.bin     — raw BGRA8 pixels of each active texture
//   <dir>/basic_2d_vert.spv, basic_2d_frag.spv, etc. — SPIR-V shaders
//   <dir>/metadata.json    — dimensions, texture info, render state
//
// On Mac Studio (m1n1 proxy): load framebuffer.bin → memset → fb_blit → pixels on display
// For GPU render: load textures + SPIR-V → recompile → render same scene

var capture_dir_buf: [512]u8 = undefined;
var capture_dir: ?[]const u8 = null;
var capture_frame_target: i32 = -1;
var capture_pending: bool = false;
var frame_counter: u32 = 0;
var sdf_accum_frame: u32 = 0; // SDF accumulation frame counter for running-mean alpha
var slug_ramp_override: f32 = 0.5; // ADMM-optimized ramp (set by vk_shared.zig)
var sdf_dump_ptsize: u32 = 0; // when > 0, use ptsize instead of cell_h in PPM filenames
var slug_gamma_override: f32 = 1.0; // fixed at 1.0 (optical weight via sqrt instead)
var slug_dropout_override: f32 = 0.0; // CalcCoverage now matches reference exactly

fn initFrameCapture() void {
    // Read config from environment
    if (envSpan("ARCAN_FRAME_CAPTURE")) |dir| {
        @memcpy(capture_dir_buf[0..dir.len], dir);
        capture_dir = capture_dir_buf[0..dir.len];
    }
    if (envSpan("ARCAN_CAPTURE_FRAME")) |val| {
        capture_frame_target = std.fmt.parseInt(i32, val, 10) catch -1;
    }
}

/// Called from endFrame (vk_wsi.zig) after each present — checks if capture should trigger.
pub fn frameCaptureCheck(env: *VkEnv) void {
    // Lazy init on first call
    if (frame_counter == 0) initFrameCapture();

    frame_counter += 1;

    if (capture_frame_target >= 0 and frame_counter == @as(u32, @intCast(capture_frame_target))) {
        capture_pending = true;
    }

    if (!capture_pending or capture_dir == null) return;
    capture_pending = false;

    doFrameCapture(env);
}

/// Trigger capture on next frame (callable from signal handler via extern)
export fn agp_frame_capture_trigger() void {
    capture_pending = true;
}

fn doFrameCapture(env: *VkEnv) void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    const dir = capture_dir orelse return;

    // Ensure GPU is idle so all textures are ready
    env.vkd.deviceWaitIdle(env.device) catch return;

    // Create output directory (best effort)
    var dir_z: [513]u8 = undefined;
    @memcpy(dir_z[0..dir.len], dir);
    dir_z[dir.len] = 0;
    _ = std.c.mkdir(@ptrCast(&dir_z), 0o755);

    // 1. Capture framebuffer
    captureFramebuffer(env, dir);

    // 2. Capture all active textures
    captureTextures(env, dir);

    // 3. Save SPIR-V shaders
    saveSpirvShaders(dir);

    // 4. Capture compiled AGX shader binaries via VK_KHR_pipeline_executable_properties
    captureShaderBinaries(env, dir);

    // 5. Save metadata
    saveMetadata(env, dir);

}

fn writeFile(dir: []const u8, name: [*:0]const u8, data: []const u8) void {
    var path_buf: [600]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "{s}/{s}", .{ dir, name }) catch return;
    const f = std.c.fopen(path.ptr, "wb") orelse return;
    defer _ = std.c.fclose(f);
    _ = std.c.fwrite(data.ptr, 1, data.len, f);
}

fn captureFramebuffer(env: *VkEnv, dir: []const u8) void {
    const w = env.swapchain_extent_w;
    const h = env.swapchain_extent_h;
    if (w == 0 or h == 0) return;
    if (env.last_presented_image == .null_handle) return;
    const size: usize = @as(usize, w) * @as(usize, h) * 4;
    if (size > STAGING_BUFFER_SIZE) return;

    // Readback via upload_cmd (same pattern as agp_save_ppm)
    env.vkd.resetCommandBuffer(env.upload_cmd, .{}) catch return;
    env.vkd.beginCommandBuffer(env.upload_cmd, &.{ .flags = .{ .one_time_submit_bit = true } }) catch return;

    // PRESENT_SRC → TRANSFER_SRC
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .bottom_of_pipe_bit = true }, .src_access_mask = .{}, .dst_stage_mask = .{ .all_transfer_bit = true }, .dst_access_mask = .{ .transfer_read_bit = true }, .old_layout = .present_src_khr, .new_layout = .transfer_src_optimal, .image = env.last_presented_image, })},
    });

    env.vkd.cmdCopyImageToBuffer(env.upload_cmd, env.last_presented_image, .transfer_src_optimal, env.staging_buffer, 1, &[_]vk.BufferImageCopy{fullImageCopyRegion(0, 0, w, h)});

    // TRANSFER_SRC → PRESENT_SRC (restore)
    env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .all_transfer_bit = true }, .src_access_mask = .{ .transfer_read_bit = true }, .dst_stage_mask = .{ .top_of_pipe_bit = true }, .dst_access_mask = .{}, .old_layout = .transfer_src_optimal, .new_layout = .present_src_khr, .image = env.last_presented_image, })},
    });

    env.vkd.endCommandBuffer(env.upload_cmd) catch return;
    const cmd_info = [_]vk.CommandBufferSubmitInfo{.{ .command_buffer = env.upload_cmd, .device_mask = 0 }};
    env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = 1,
        .p_command_buffer_infos = &cmd_info,
    }}, env.upload_fence) catch return;
    _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch return;
    env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch return;

    if (env.staging_mapped) |mapped| {
        writeFile(dir, "framebuffer.bin", mapped[0..size]);
    }
}

fn captureTextures(env: *VkEnv, dir: []const u8) void {
    var tex_count: u32 = 0;

    for (0..MAX_TEXTURES) |i| {
        const slot = &env.textures[i];
        if (!slot.in_use or slot.image == .null_handle) continue;
        if (slot.width == 0 or slot.height == 0) continue;

        const size: usize = @as(usize, slot.width) * @as(usize, slot.height) * 4;
        if (size > STAGING_BUFFER_SIZE) continue;

        // Readback this texture
        env.vkd.resetCommandBuffer(env.upload_cmd, .{}) catch continue;
        env.vkd.beginCommandBuffer(env.upload_cmd, &.{ .flags = .{ .one_time_submit_bit = true } }) catch continue;

        // SHADER_READ_ONLY → TRANSFER_SRC
        env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
            .image_memory_barrier_count = 1,
            .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .all_commands_bit = true }, .src_access_mask = .{ .shader_read_bit = true }, .dst_stage_mask = .{ .all_transfer_bit = true }, .dst_access_mask = .{ .transfer_read_bit = true }, .old_layout = .shader_read_only_optimal, .new_layout = .transfer_src_optimal, .image = slot.image, })},
        });

        env.vkd.cmdCopyImageToBuffer(env.upload_cmd, slot.image, .transfer_src_optimal, env.staging_buffer, 1, &[_]vk.BufferImageCopy{fullImageCopyRegion(0, 0, slot.width, slot.height)});

        // TRANSFER_SRC → SHADER_READ_ONLY (restore)
        env.vkd.cmdPipelineBarrier2(env.upload_cmd, &.{
            .image_memory_barrier_count = 1,
            .p_image_memory_barriers = &[_]vk.ImageMemoryBarrier2{fullColorImageBarrier(.{ .src_stage_mask = .{ .all_transfer_bit = true }, .src_access_mask = .{ .transfer_read_bit = true }, .dst_stage_mask = .{ .all_commands_bit = true }, .dst_access_mask = .{ .shader_read_bit = true }, .old_layout = .transfer_src_optimal, .new_layout = .shader_read_only_optimal, .image = slot.image, })},
        });

        env.vkd.endCommandBuffer(env.upload_cmd) catch continue;
        const cmd_info = [_]vk.CommandBufferSubmitInfo{.{ .command_buffer = env.upload_cmd, .device_mask = 0 }};
        env.vkd.queueSubmit2(env.graphics_queue, 1, &[_]vk.SubmitInfo2{.{
            .command_buffer_info_count = 1,
            .p_command_buffer_infos = &cmd_info,
        }}, env.upload_fence) catch continue;
        _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.upload_fence), .true, std.math.maxInt(u64)) catch continue;
        env.vkd.resetFences(env.device, 1, @ptrCast(&env.upload_fence)) catch continue;

        if (env.staging_mapped) |mapped| {
            var name_buf: [64]u8 = undefined;
            const name = std.fmt.bufPrintZ(&name_buf, "tex_{d}_{d}x{d}.bin", .{ i, slot.width, slot.height }) catch continue;
            writeFile(dir, name.ptr, mapped[0..size]);
            tex_count += 1;
        }
    }

}

fn captureShaderBinaries(env: *VkEnv, dir: []const u8) void {
    // Check if the extension function is loaded
    if (env.vkd.dispatch.vkGetPipelineExecutablePropertiesKHR == null) {
        return;
    }

    // Query compiled AGX binaries from each pipeline via VK_KHR_pipeline_executable_properties
    const pipelines = [_]struct { pipeline: vk.Pipeline, name: [*:0]const u8 }{
        .{ .pipeline = env.basic_2d_pipeline, .name = "basic_2d" },
        .{ .pipeline = env.color_2d_pipeline, .name = "color_2d" },
        .{ .pipeline = env.basic_2d_pipeline_unorm, .name = "basic_2d_unorm" },
        .{ .pipeline = env.color_2d_pipeline_unorm, .name = "color_2d_unorm" },
    };


    for (pipelines) |p| {
        if (p.pipeline == .null_handle) continue;

        // Step 1: Get executable properties (vertex, fragment stages)
        var exec_count: u32 = 0;
        _ = env.vkd.getPipelineExecutablePropertiesKHR(
            env.device,
            &.{ .pipeline = p.pipeline },
            &exec_count,
            null,
        ) catch {
            _ = c.printf("[frame_capture] getPipelineExecutablePropertiesKHR failed for %s\n", p.name);
            continue;
        };

        if (exec_count == 0) continue;

        // Limit to reasonable count
        const max_execs = 8;
        if (exec_count > max_execs) exec_count = max_execs;
        var exec_props: [max_execs]vk.PipelineExecutablePropertiesKHR = undefined;
        for (0..max_execs) |i| exec_props[i] = .{
            .stages = .{},
            .name = [_]u8{0} ** vk.MAX_DESCRIPTION_SIZE,
            .description = [_]u8{0} ** vk.MAX_DESCRIPTION_SIZE,
            .subgroup_size = 0,
        };
        _ = env.vkd.getPipelineExecutablePropertiesKHR(
            env.device,
            &.{ .pipeline = p.pipeline },
            &exec_count,
            &exec_props,
        ) catch continue;

        // Step 2: For each executable, get internal representations (AGX binary)
        for (0..exec_count) |ei| {
            var repr_count: u32 = 0;
            _ = env.vkd.getPipelineExecutableInternalRepresentationsKHR(
                env.device,
                &.{ .pipeline = p.pipeline, .executable_index = @intCast(ei) },
                &repr_count,
                null,
            ) catch continue;

            if (repr_count == 0) continue;

            const max_reprs = 8;
            if (repr_count > max_reprs) repr_count = max_reprs;
            var reprs: [max_reprs]vk.PipelineExecutableInternalRepresentationKHR = undefined;

            // First pass: get sizes
            for (0..max_reprs) |i| reprs[i] = .{
                .name = [_]u8{0} ** vk.MAX_DESCRIPTION_SIZE,
                .description = [_]u8{0} ** vk.MAX_DESCRIPTION_SIZE,
                .is_text = .false,
                .data_size = 0,
                .p_data = null,
            };
            _ = env.vkd.getPipelineExecutableInternalRepresentationsKHR(
                env.device,
                &.{ .pipeline = p.pipeline, .executable_index = @intCast(ei) },
                &repr_count,
                &reprs,
            ) catch continue;

            // Second pass: allocate and fetch data
            for (0..repr_count) |ri| {
                const data_size = reprs[ri].data_size;
                if (data_size == 0 or data_size > 16 * 1024 * 1024) continue;

                // Use staging buffer for the data (it's already mapped)
                if (data_size > STAGING_BUFFER_SIZE) continue;
                reprs[ri].p_data = @ptrCast(env.staging_mapped);
            }

            var repr_count2 = repr_count;
            _ = env.vkd.getPipelineExecutableInternalRepresentationsKHR(
                env.device,
                &.{ .pipeline = p.pipeline, .executable_index = @intCast(ei) },
                &repr_count2,
                &reprs,
            ) catch continue;

            // Save each representation
            for (0..repr_count) |ri| {
                const repr = &reprs[ri];
                if (repr.data_size == 0 or repr.p_data == null) continue;

                // Determine stage name from exec props
                const stage_name: [*:0]const u8 = if (exec_props[ei].stages.vertex_bit)
                    "vert"
                else if (exec_props[ei].stages.fragment_bit)
                    "frag"
                else if (exec_props[ei].stages.compute_bit)
                    "comp"
                else
                    "unknown";

                // repr.name contains e.g. "AGX Assembly" (text) or "AGX Binary" (binary)
                const is_binary = repr.is_text == .false;
                const ext: [*:0]const u8 = if (is_binary) ".bin" else ".txt";

                var name_buf: [128]u8 = undefined;
                const name = std.fmt.bufPrintZ(&name_buf, "agx_{s}_{s}_{d}{s}", .{
                    p.name, stage_name, ri, ext,
                }) catch continue;

                const data: [*]const u8 = @ptrCast(repr.p_data);
                writeFile(dir, name.ptr, data[0..repr.data_size]);
            }
        }
    }
}

fn saveSpirvShaders(dir: []const u8) void {
    writeFile(dir, "basic_2d_vert.spv", &basic_2d_vert_spv);
    writeFile(dir, "basic_2d_frag.spv", &basic_2d_frag_spv);
    writeFile(dir, "color_2d_vert.spv", &color_2d_vert_spv);
    writeFile(dir, "color_2d_frag.spv", &color_2d_frag_spv);
}

fn saveMetadata(env: *VkEnv, dir: []const u8) void {
    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const w = stream.writer();

    w.print("{{\n", .{}) catch return;
    w.print("  \"width\": {d},\n", .{env.swapchain_extent_w}) catch return;
    w.print("  \"height\": {d},\n", .{env.swapchain_extent_h}) catch return;
    w.print("  \"format\": \"{s}\",\n", .{@tagName(env.swapchain_format)}) catch return;
    w.print("  \"frame\": {d},\n", .{frame_counter}) catch return;

    // Active textures
    w.print("  \"textures\": [\n", .{}) catch return;
    var first = true;
    for (0..MAX_TEXTURES) |i| {
        const slot = &env.textures[i];
        if (!slot.in_use or slot.width == 0 or slot.height == 0) continue;
        if (!first) { w.print(",\n", .{}) catch return; }
        w.print("    {{\"id\": {d}, \"w\": {d}, \"h\": {d}, \"dmabuf\": {s}}}", .{
            i, slot.width, slot.height, if (slot.imported_dmabuf) "true" else "false",
        }) catch return;
        first = false;
    }
    w.print("\n  ]\n}}\n", .{}) catch return;

    const written = stream.getWritten();
    writeFile(dir, "metadata.json", written);
}
