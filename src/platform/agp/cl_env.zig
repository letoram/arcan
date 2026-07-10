//! cl_env.zig — OpenCL/Rusticl mirror of src/platform/agp/vk.zig:VkEnv.
//!
//! MAY-247 Phase 2 skeleton. Owns the Rusticl context + command queue,
//! loads the durian compute kernels (one per former graphics shader) at
//! init, and presents enough of the VkEnv-shaped surface that later
//! phases (cl_gbm_kms.zig in Phase 3, then the agp callers) can be
//! ported with minimal callsite churn.
//!
//! What's here today (Phase 2):
//!   - init / deinit
//!   - color_2d_compute program + kernel loaded from
//!     durian_cl_kernels.color_2d_compute (SPV embedded via
//!     buildDurianClKernels in build.zig)
//!
//! Deferred (Phase 3+):
//!   - GBM / DMA-BUF / cl_khr_image2d_from_buffer wiring
//!   - Sampler cache
//!   - The remaining 4 compute kernels (basic_2d, slug_glyph,
//!     slug_sdf_accum, slug_debug_frag)
//!   - The full per-frame state struct (push_constants equivalent,
//!     rt-target tracking, readback ping-pong, etc.) — only added as
//!     callers actually need them.

const std = @import("std");
const cl = @import("cl");
const cl_kernels = @import("durian_cl_kernels");

pub const Error = cl.Error || error{
    OutOfMemory,
    ProgramBuildFailed,
};

/// Mirror of vk.zig:VkEnv. Fields here intentionally PARALLEL the
/// VkEnv layout where the concept survives the Vulkan→OpenCL move:
///
///   vk.instance         → cl_env.platform
///   vk.physical_device  → cl_env.device
///   vk.device           → cl_env.ctx.handle  (cl_context)
///   vk.graphics_queue   → cl_env.ctx.queue   (cl_command_queue)
///   vk.color_2d_pipeline → cl_env.color_2d_kernel
///
/// Concepts that disappear in the port (no equivalent needed):
///   vk.command_pool / cmd / pipeline_layout / descriptor_set_layout
///   / descriptor_pool / vertex_buffer / vert_shader_* / frag_shader_*
pub const ClEnv = struct {
    alloc: std.mem.Allocator,
    loader: cl.Loader,
    ctx: cl.Context,
    platform: cl.cl_platform_id,
    device: cl.cl_device_id,

    /// Compute kernels — one per former vk.zig graphics pipeline.
    /// All hot at init time so first-frame latency doesn't pay the
    /// build cost. Phase 3 will add the remaining 4 shaders.
    color_2d_program: cl.Program,
    color_2d_kernel: cl.Kernel,

    /// Lazy singleton — vk.zig has `getEnv()`. Mirror.
    var instance: ?*ClEnv = null;

    pub fn init(alloc: std.mem.Allocator) Error!*ClEnv {
        var loader = cl.Loader.open() catch |err| return err;
        errdefer loader.close();
        const platform = try loader.firstPlatform();
        const device = try loader.firstGpu(platform);

        var ctx = try cl.Context.create(&loader, device);
        errdefer ctx.deinit();

        // color_2d_compute — the only kernel Phase 2 wires up. The SPV
        // bytes come from buildDurianClKernels in build.zig.
        var color_2d_program = try cl.Program.buildSpv(&ctx, cl_kernels.color_2d_compute, null);
        errdefer color_2d_program.deinit();
        var color_2d_kernel = try color_2d_program.kernel("color_2d_compute");
        errdefer color_2d_kernel.deinit();

        const env = try alloc.create(ClEnv);
        env.* = .{
            .alloc = alloc,
            .loader = loader,
            .ctx = ctx,
            .platform = platform,
            .device = device,
            .color_2d_program = color_2d_program,
            .color_2d_kernel = color_2d_kernel,
        };
        instance = env;
        return env;
    }

    pub fn deinit(self: *ClEnv) void {
        self.color_2d_kernel.deinit();
        self.color_2d_program.deinit();
        self.ctx.deinit();
        self.loader.close();
        if (instance == self) instance = null;
        self.alloc.destroy(self);
    }

    /// Mirror of vk.zig:getEnv() — returns the singleton if init.
    pub fn getEnv() ?*ClEnv {
        return instance;
    }

    /// Convenience: device name as printed by deviceName().
    /// Buffer must outlive the returned slice.
    pub fn deviceName(self: *const ClEnv, buf: []u8) Error![]const u8 {
        return self.loader.deviceName(self.device, buf);
    }
};
