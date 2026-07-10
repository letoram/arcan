// AGP Vulkan 1.4 Backend — Shared Rendering
// Provides all rendertarget, vstore, draw, streaming, mesh, stencil, blend functions.
// Phase 2: texture management, draw calls, rendertarget stubs.

const std = @import("std");

fn rcdbg(comptime tag: []const u8) void {
    std.fs.File.stderr().writeAll("RCDBG:" ++ tag ++ "\n") catch {};
}

// Arcan C types defined inline (no C headers in this pure-Zig codebase)
// Layouts match upstream arcan's platform_types.h / agp_platform.h on aarch64.
const c = struct {
    // av_pixel
    pub const av_pixel = u32;

    // storage_source enum
    pub const STORAGE_IMAGE_URI: c_uint = 0;
    pub const STORAGE_TEXT: c_uint = 1;
    pub const STORAGE_TEXTARRAY: c_uint = 2;
    pub const STORAGE_TPACK: c_uint = 3;

    // txstate enum
    pub const TXSTATE_OFF: c_uint = 0;
    pub const TXSTATE_TEX2D: c_uint = 1;

    // stream_type enum
    pub const STREAM_RAW: c_uint = 0;
    pub const STREAM_RAW_DIRECT: c_uint = 1;
    pub const STREAM_RAW_DIRECT_COPY: c_uint = 2;
    pub const STREAM_RAW_DIRECT_SYNCHRONOUS: c_uint = 3;
    pub const STREAM_EXT_RESYNCH: c_uint = 4;
    pub const STREAM_HANDLE: c_uint = 5;

    // agp_mesh_type enum
    pub const AGP_MESH_TRISOUP: c_uint = 0;

    // arcan_alloc_mem constants
    pub const ARCAN_MEM_VBUFFER: c_uint = 1;
    pub const ARCAN_MEM_VSTRUCT: c_uint = 2;
    pub const ARCAN_MEM_BZERO: c_uint = 1;
    pub const ARCAN_MEMALIGN_NATURAL: c_uint = 0;
    pub const ARCAN_MEMALIGN_PAGE: c_uint = 1;

    // drm_hdr_meta
    pub const struct_drm_hdr_meta = extern struct {
        eotf: c_int = 0,
        rx: f32 = 0, ry: f32 = 0,
        gx: f32 = 0, gy: f32 = 0,
        bx: f32 = 0, by: f32 = 0,
        wpx: f32 = 0, wpy: f32 = 0,
        master_min: f32 = 0, master_max: f32 = 0,
        cll: f32 = 0,
        fll: f32 = 0,
    };

    // agp_vstore (matches upstream platform_types.h on aarch64)
    pub const struct_agp_vstore = extern struct {
        refcount: usize = 0, // 0
        update_ts: u32 = 0, // 8
        _pad0: [4]u8 = .{ 0, 0, 0, 0 }, // 12 (align vinf to 8)
        vinf: extern union { // 16
            text: extern struct {
                glid: c_uint = 0, // +0 (abs 16)
                _pad_glid: [4]u8 = .{ 0, 0, 0, 0 }, // +4 (align glid_proxy ptr)
                glid_proxy: ?*c_uint = null, // +8 (abs 24)
                rid: c_uint = 0, // +16 (abs 32)
                wid: c_uint = 0, // +20 (abs 36)
                s_raw: u32 = 0, // +24 (abs 40)
                _pad_raw: [4]u8 = .{ 0, 0, 0, 0 }, // +28 (align raw ptr)
                raw: ?[*]av_pixel = null, // +32 (abs 48)
                s_fmt: u64 = 0, // +40 (abs 56)
                d_fmt: u64 = 0, // +48 (abs 64)
                s_type: c_uint = 0, // +56 (abs 72)
                _pad_vpts: [4]u8 = .{ 0, 0, 0, 0 }, // +60 (align vpts)
                vpts: u64 = 0, // +64 (abs 80)
                hppcm: f32 = 0, // +72 (abs 88)
                vppcm: f32 = 0, // +76 (abs 92)
                kind: c_uint = 0, // +80 (abs 96) — storage_source enum
                _pad_src: [4]u8 = .{ 0, 0, 0, 0 }, // +84 (align source ptr)
                unnamed_0: extern union { // +88 (abs 104)
                    source: ?[*:0]u8, // char*
                    source_arr: ?[*]?[*:0]u8, // char**
                    tpack: extern struct {
                        buf_sz: usize = 0,
                        buf: ?[*]u8 = null,
                        group: ?*anyopaque = null,
                        tui: ?*anyopaque = null,
                    },
                } = .{ .source = null },
                format: c_int = 0, // +120 (abs 136)
                _pad_stride: [4]u8 = .{ 0, 0, 0, 0 }, // +124 (align stride)
                stride: usize = 0, // +128 (abs 144)
                handle: i64 = 0, // +136 (abs 152)
                tag: usize = 0, // +144 (abs 160)
            },
            col: extern struct {
                r: f32 = 0,
                g: f32 = 0,
                b: f32 = 0,
            },
        } = .{ .text = .{} }, // vinf size = sizeof(text) = 152 bytes
        dst_copy: ?*struct_agp_vstore = null, // 168
        w: usize = 0, // 176
        h: usize = 0, // 184
        bpp: u8 = 0, // 192
        txmapped: u8 = 0, // 193
        txu: u8 = 0,
        txv: u8 = 0,
        scale: u8 = 0,
        imageproc: u8 = 0,
        filtermode: u8 = 0,
        _pad_hdr: u8 = 0, // 199 (padding before hdr which has int)
        hdr: extern struct {
            model: c_int = 0, // 200
            drm: struct_drm_hdr_meta = .{}, // 204
        } = .{},
    };

    // agp_rendertarget (opaque — we cast to/from VkRendertarget)
    pub const struct_agp_rendertarget = anyopaque;

    // agp_region
    pub const struct_agp_region = extern struct {
        x1: usize = 0,
        y1: usize = 0,
        x2: usize = 0,
        y2: usize = 0,
    };

    // agp_buffer_plane
    pub const struct_agp_buffer_plane = extern struct {
        fd: c_int = 0,
        fence: c_int = 0,
        w: usize = 0,
        h: usize = 0,
        unnamed_0: extern union {
            gbm: extern struct {
                format: u32 = 0,
                _pad0: [4]u8 = .{ 0, 0, 0, 0 },
                stride: u64 = 0,
                offset: u64 = 0,
                mod_hi: u32 = 0,
                mod_lo: u32 = 0,
            },
        } = .{ .gbm = .{} },
    };

    // stream_meta
    pub const struct_stream_meta = extern struct {
        unnamed_0: extern union {
            unnamed_0: extern struct { // buf/dirty/x1/y1/w/h/stride
                buf: ?[*]av_pixel = null,
                dirty: bool = false,
                _pad0: [3]u8 = .{ 0, 0, 0 },
                x1: c_uint = 0,
                y1: c_uint = 0,
                w: c_uint = 0,
                h: c_uint = 0,
                stride: c_uint = 0,
            },
            unnamed_1: extern struct { // planes/used
                planes: [4]struct_agp_buffer_plane = .{ .{}, .{}, .{}, .{} },
                used: usize = 0,
            },
        } = .{ .unnamed_0 = .{} },
        @"type": c_uint = 0,
        state: bool = false,
    };

    // asynch_readback_meta
    pub const struct_asynch_readback_meta = extern struct {
        ptr: ?[*]av_pixel = null,
        buf_sz: usize = 0,
        w: usize = 0,
        h: usize = 0,
        stride: usize = 0,
        release: ?*const fn (?*anyopaque) callconv(.c) void = null,
        tag: ?*anyopaque = null,
    };

    // agp_mesh_store
    pub const struct_agp_mesh_store = extern struct {
        shared_buffer: ?[*]u8 = null,
        shared_buffer_sz: usize = 0,
        verts: ?[*]f32 = null,
        txcos: ?[*]f32 = null,
        txcos2: ?[*]f32 = null,
        normals: ?[*]f32 = null,
        colors: ?[*]f32 = null,
        tangents: ?[*]f32 = null,
        bitangents: ?[*]f32 = null,
        weights: ?[*]f32 = null,
        joints: ?[*]u16 = null,
        _pad_joints: [6]u8 = .{ 0, 0, 0, 0, 0, 0 }, // align indices ptr
        indices: ?[*]c_uint = null,
        vertex_size: usize = 0,
        n_vertices: usize = 0,
        n_indices: usize = 0,
        @"type": c_uint = 0, // agp_mesh_type
        depth_func: c_uint = 0, // agp_depth_func
        @"opaque": usize = 0,
        dirty: bool = false,
        nodepth: bool = false,
        validated: bool = false,
    };

    // Engine functions
    pub extern fn arcan_alloc_mem(sz: usize, memtype: c_uint, hint: c_uint, alignment: c_uint) ?*anyopaque;
    pub extern fn arcan_mem_free(ptr: ?*anyopaque) void;
    pub extern fn arcan_timemillis() c_longlong;
};

// Bridge functions in vk.zig (linked at link time)
extern fn vk_env_create_texture(w: u32, h: u32, pixels: ?[*]const u8) u32;
extern fn vk_env_update_texture(id: u32, w: u32, h: u32, pixels: ?[*]const u8) void;
extern fn vk_env_destroy_texture(id: u32) void;
extern fn vk_env_bind_texture(id: u32) void;
extern fn vk_env_bind_secondary_texture(id: u32) void;
extern fn vk_env_import_dmabuf_texture(fd: c_int, w: u32, h: u32, stride: u64, offset: u64, drm_format: u32, modifier: u64) u32;
extern fn vk_env_update_dmabuf_texture(id: u32, fd: c_int, w: u32, h: u32, stride: u64, offset: u64, drm_format: u32, modifier: u64) bool;
extern fn vk_env_draw_quad(verts: ?[*]const f32, n_floats: u32) void;
extern fn vk_env_set_blend_mode(mode: u32) void;
extern fn vk_env_set_rt_viewport(x: i32, y: i32, w: i32, h: i32) void;
extern fn vk_env_set_blend_alpha(retain_alpha: bool) void;
extern fn vk_env_is_rendering() bool;
extern fn vk_env_get_active_texture() u32;

// Phase 4: RT pass bridge functions
extern fn vk_env_begin_rt_pass(tex_id: u32, w: u32, h: u32) bool;
extern fn vk_env_end_rt_pass() void;
extern fn vk_env_rt_clear(r: f32, g: f32, b: f32, a: f32) void;
extern fn vk_env_readback_texture(tex_id: u32, dst: [*]u8, dst_sz: u32) bool;

// Stencil/color write bridge functions in vk.zig
extern fn vk_env_set_color_write(enabled: bool) void;
extern fn vk_env_stencil_begin(w: u32, h: u32) void;
extern fn vk_env_stencil_activate() void;
extern fn vk_env_stencil_end() void;

// Depth/pipeline/mesh bridge functions in vk.zig
extern fn vk_env_set_depth_active(active: bool) void;
extern fn vk_env_draw_mesh_verts(verts: [*]const u8, byte_size: u32, n_verts: u32) void;

// Platform bridge (vk-display/video.zig)
extern fn vk_platform_update_canvas(w: u32, h: u32) void;

// Async readback bridge functions in vk.zig
extern fn vk_env_readback_async_submit(tex_id: u32) void;
extern fn vk_env_readback_async_poll(out_w: *u32, out_h: *u32) ?[*]u8;

// Bridge functions in vk_shdrmgmt.zig
extern fn agp_shader_envv(slot: c_uint, value: ?*anyopaque, size: usize) c_int;

// Identity matrix for when modelview is NULL
const ident = [16]f32{
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
};

// Bridge functions in vk.zig for sub-region texture upload
extern fn vk_env_update_texture_sub(id: u32, x: u32, y: u32, w: u32, h: u32, stride: u32, pixels: [*]const u8) void;

// Bridge function in video.zig for updating clear color
extern fn vk_platform_set_clear_color(r: f32, g: f32, b: f32, a: f32) void;

// Rendertarget Backing Store
// struct agp_rendertarget is opaque (forward-declared in agp_platform.h).
// We allocate VkRendertarget and cast the pointer.
const VkRendertarget = struct {
    clearcol: [4]f32 = .{ 0.05, 0.05, 0.05, 1.0 },
    viewport: [4]i32 = .{ 0, 0, 0, 0 },
    store: ?*c.struct_agp_vstore = null,
    mode: c_uint = 0,
    // Dirty tracking (matches GL glshared.c:122 — dirty_region/dirty_region_decay)
    dirty_region: usize = 0,
    dirty_region_decay: usize = 0,
    dirty_flip: usize = 4, // MAX_BUFFERS from GL (marks as needing initial draws)
};

var active_rt: ?*VkRendertarget = null;
var world_rt: ?*VkRendertarget = null;
var rt_dbg_count: u32 = 0;
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;

// Screen Composite (GL FBO 0 equivalent)
// In no_stdout mode (durian deletes WORLDID), the engine draws the world
// scene graph (statusbar + workspace textures) via agp_activate_rendertarget(NULL).
// In GL this goes to FBO 0 (the screen). We provide a screen-sized texture
// as a render target and composite it to the swapchain afterward.
var screen_store: c.struct_agp_vstore = std.mem.zeroes(c.struct_agp_vstore);
var screen_rt: VkRendertarget = .{ .store = null, .mode = 0 };
var screen_has_content: bool = false;
var frame_active: bool = false; // true while cmd buffer is recording (begin_frame → end_frame)

/// Called from video.zig after swapchain creation / resize to allocate
/// the screen composite texture (our "FBO 0").
export fn vk_shared_set_screen_size(w: u32, h: u32) void {
    // Skip recreation if size hasn't changed (avoids losing content on
    // same-size XCB CONFIGURE_NOTIFY events, e.g. initial window map).
    if (screen_store.w == w and screen_store.h == h and screen_store.vinf.text.glid != 0) return;
    if (screen_store.vinf.text.glid != 0) {
        vk_env_destroy_texture(screen_store.vinf.text.glid);
    }
    screen_store.w = w;
    screen_store.h = h;
    screen_store.bpp = @sizeOf(c.av_pixel);
    screen_store.vinf.text.glid = vk_env_create_texture(w, h, null);
    screen_rt.store = &screen_store;
    screen_has_content = false;
}

/// Called from video.zig at the start of each frame, before arcan_vint_refresh.
export fn vk_shared_begin_frame() void {
    // NOTE: Do NOT reset screen_has_content here. The screen composite texture
    // retains content from previous frames via load_op=.load. Once the first
    // dirty frame renders into it, screen_has_content stays true so that
    // subsequent clean frames (where process_rendertarget returns early without
    // drawing) still composite the preserved screen content. The flag is only
    // reset when the screen texture is destroyed/recreated in set_screen_size.
    frame_active = true;
    world_rt = null; // Reset so largest RT is picked fresh each frame
}

/// Returns the screen composite store if it has been rendered into (ever).
/// Used by video.zig to get the composited scene in no_stdout mode.
/// The store retains content across frames (load_op=.load), so once set,
/// screen_has_content stays true until the texture is recreated.
export fn vk_screen_composite_vstore() ?*c.struct_agp_vstore {
    return if (screen_has_content and screen_store.vinf.text.glid != 0) &screen_store else null;
}

/// Get the screen composite texture glid for readback verification.
export fn vk_shared_get_screen_glid() u32 {
    return screen_store.vinf.text.glid;
}

/// End any active render pass (screen or sub-RT) without starting a new one.
/// Called from video.zig after arcan_vint_refresh to prepare for swapchain composite.
export fn vk_shared_end_all_passes() void {
    if (active_rt != null) {
        if (vk_env_is_rendering()) {
            vk_env_end_rt_pass();
        }
        active_rt = null;
    }
    frame_active = false;
}

/// Mark the currently active rendertarget as dirty (matches GL: agp_rendertarget_dirty call after draw)
fn markActiveDirty() void {
    if (active_rt) |rt| {
        rt.dirty_region += 1;
        rt.dirty_region_decay += 1;
        if (rt == &screen_rt) screen_has_content = true;
    }
}

/// Get the backing vstore of an agp_rendertarget (for platform compositing).
export fn agp_rendertarget_vstore(tgt: ?*c.struct_agp_rendertarget) ?*c.struct_agp_vstore {
    const rt: *VkRendertarget = if (tgt) |t| @ptrCast(@alignCast(t)) else return null;
    return rt.store;
}

/// Return the vstore from the last RT that had draws (tracked as world_rt).
/// This is used by the platform composite when the engine's world RT wasn't
/// reprocessed but content was rendered into a child workspace RT.
export fn vk_last_rendered_vstore() ?*c.struct_agp_vstore {
    if (world_rt) |rt| return rt.store;
    return null;
}



// Rendertarget Management

export fn agp_setup_rendertarget(
    vstore: ?*c.struct_agp_vstore,
    mode: c_uint,
) ?*c.struct_agp_rendertarget {
    const mem = c.arcan_alloc_mem(
        @sizeOf(VkRendertarget),
        c.ARCAN_MEM_VSTRUCT,
        c.ARCAN_MEM_BZERO,
        c.ARCAN_MEMALIGN_NATURAL,
    ) orelse return null;
    const rt: *VkRendertarget = @ptrCast(@alignCast(mem));
    rt.* = .{
        .store = vstore,
        .mode = mode,
        // Initialize viewport to vstore dimensions (matches GL glshared.c:865-868)
        .viewport = if (vstore) |vs| .{
            0, 0, @intCast(vs.w), @intCast(vs.h),
        } else .{ 0, 0, 0, 0 },
    };
    // Track as world RT (will be updated in agp_activate_rendertarget)
    if (world_rt == null) {
        world_rt = rt;
    }
    return @ptrCast(rt);
}


export fn agp_activate_rendertarget(tgt: ?*c.struct_agp_rendertarget) void {
    if (tgt) |t| {
        const rt: *VkRendertarget = @ptrCast(@alignCast(t));

        // End any previous RT pass that's still active
        if (vk_env_is_rendering() and active_rt != null and active_rt != rt) {
            vk_env_end_rt_pass();
        }

        active_rt = rt;
        // Track the LARGEST activated RT during the frame
        const rt_s: *c.struct_agp_vstore = @ptrCast(rt.store);
        rt_dbg_count += 1;
        if (rt_dbg_count < 50) {
        }
        if (world_rt == null) {
            world_rt = rt;
        } else {
            const old_s: *c.struct_agp_vstore = @ptrCast(world_rt.?.store);
            if (rt_s.w * rt_s.h >= old_s.w * old_s.h) world_rt = rt;
        }

        // Per-RT blend mode + alpha factors (matches GL glshared.c:1058-1075)
        // GL: if !(mode & RETAIN_ALPHA) → blend_src_alpha=ONE, dst_alpha=ONE (additive)
        //     else → blend_src_alpha=SRC_ALPHA, dst_alpha=ONE_MINUS_SRC_ALPHA
        const RENDERTARGET_RETAIN_ALPHA = 16;
        vk_env_set_blend_mode(1); // BLEND_NORMAL
        vk_env_set_blend_alpha((rt.mode & RENDERTARGET_RETAIN_ALPHA) != 0);

        // Per-RT viewport/scissor (matches GL glshared.c:1113-1115)
        // GL: env->scissor(vp[0], vp[1], vp[2], vp[3]) + env->viewport(same)
        vk_env_set_rt_viewport(rt.viewport[0], rt.viewport[1], rt.viewport[2], rt.viewport[3]);

        // Begin a new RT pass if the backing store has a valid GPU texture
        if (rt.store) |store| {
            if (store.vinf.text.glid != 0 and store.w > 0 and store.h > 0) {
                _ = vk_env_begin_rt_pass(
                    store.vinf.text.glid,
                    @intCast(store.w),
                    @intCast(store.h),
                );
            }
        }
    } else {
        // NULL tgt = "activate screen" (GL's FBO 0 equivalent).
        // In no_stdout mode, the engine draws the world scene graph
        // (statusbar + workspace textures) here. Route to screen composite.
        // NOTE: GL does NOT change blend state when binding FBO 0 — it inherits
        // BLEND_NORMAL from the previous RT activation. Match that behavior.
        // Previously forced BLEND_NONE which caused draws to overwrite instead
        // of blending, making text disappear after the first render.
        //
        // GL: scissor(0, 0, w, h) + viewport(0, 0, w, h) for screen (glshared.c:1087-1088)
        vk_env_set_rt_viewport(0, 0, @intCast(screen_store.w), @intCast(screen_store.h));
        if (frame_active) {
            // End previous RT pass if it wasn't the screen
            if (active_rt != null and active_rt != &screen_rt) {
                if (vk_env_is_rendering()) vk_env_end_rt_pass();
            }
            // Begin screen composite pass (our FBO 0)
            if (active_rt != &screen_rt and screen_store.vinf.text.glid != 0) {
                const ok = vk_env_begin_rt_pass(
                    screen_store.vinf.text.glid,
                    @intCast(screen_store.w),
                    @intCast(screen_store.h),
                );
                if (ok) {
                    active_rt = &screen_rt;
                }
            } else if (active_rt == &screen_rt) {
                // Screen pass already active, no-op
            }
        } else {
            if (active_rt != null) {
                if (vk_env_is_rendering()) vk_env_end_rt_pass();
                active_rt = null;
            }
        }
    }
}

export fn agp_drop_rendertarget(tgt: ?*c.struct_agp_rendertarget) void {
    const rt: ?*VkRendertarget = if (tgt) |t| @ptrCast(@alignCast(t)) else null;
    if (rt) |r| {
        if (world_rt == r) world_rt = null;
        if (active_rt == r) active_rt = null;
        c.arcan_mem_free(@ptrCast(r));
    }
}

export fn agp_resize_rendertarget(
    tgt: ?*c.struct_agp_rendertarget,
    neww: usize,
    newh: usize,
) void {
    const rt: ?*VkRendertarget = if (tgt) |t| @ptrCast(@alignCast(t)) else null;
    if (rt) |r| {
        // Update store dimensions + resize GPU texture (matches GL glshared.c:1253-1296)
        if (r.store) |store| {
            if (store.w == neww and store.h == newh) return;
            store.w = neww;
            store.h = newh;
            // Destroy old GPU texture and create new one at new size
            if (store.vinf.text.glid != 0) {
                vk_env_destroy_texture(store.vinf.text.glid);
                store.vinf.text.glid = 0;
            }
            agp_empty_vstore(r.store, neww, newh);
        }
        // Reset viewport to new dimensions (matches GL glshared.c:1255-1258)
        r.viewport = .{ 0, 0, @intCast(neww), @intCast(newh) };
    }
}

export fn agp_rendertarget_viewport(
    tgt: ?*c.struct_agp_rendertarget,
    x1: isize,
    y1: isize,
    x2: isize,
    y2: isize,
) void {
    const rt: ?*VkRendertarget = if (tgt) |t| @ptrCast(@alignCast(t)) else null;
    if (rt) |r| {
        r.viewport = .{
            @intCast(x1),
            @intCast(y1),
            @intCast(x2),
            @intCast(y2),
        };
    }
}

export fn agp_rendertarget_clear() void {
    if (active_rt) |rt| {
        if (vk_env_is_rendering()) {
            vk_env_rt_clear(rt.clearcol[0], rt.clearcol[1], rt.clearcol[2], rt.clearcol[3]);
        }
    }
}

export fn agp_rendertarget_clearcolor(
    tgt: ?*c.struct_agp_rendertarget,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
) void {
    const rt: ?*VkRendertarget = if (tgt) |t| @ptrCast(@alignCast(t)) else null;
    if (rt) |rtgt| {
        rtgt.clearcol = .{ r, g, b, a };
        // If this is the world rendertarget, update the swapchain clear color
        if (rtgt == world_rt) {
            vk_platform_set_clear_color(r, g, b, a);
        }
    }
}

export fn agp_rendertarget_allocator(
    tgt: ?*c.struct_agp_rendertarget,
    handler: ?*const fn (?*c.struct_agp_rendertarget, ?*c.struct_agp_vstore, c_int, ?*anyopaque) callconv(.c) bool,
    tag: ?*anyopaque,
) void {
    _ = tgt;
    _ = handler;
    _ = tag;
}

export fn agp_rendertarget_ids(
    tgt: ?*c.struct_agp_rendertarget,
    tgt_id: ?*usize,
    col: ?*usize,
    depth: ?*usize,
) void {
    _ = tgt;
    if (tgt_id) |p| p.* = 0;
    if (col) |p| p.* = 0;
    if (depth) |p| p.* = 0;
}

export fn agp_rendertarget_swapstore(
    tgt: ?*c.struct_agp_rendertarget,
    vstore: ?*c.struct_agp_vstore,
) bool {
    const rt: *VkRendertarget = if (tgt) |t| @ptrCast(@alignCast(t)) else return false;
    const new_store = vstore orelse return false;

    // Only swap if the store actually changed
    if (rt.store == new_store) return false;

    rt.store = new_store;
    return true;
}

export fn agp_rendertarget_proxy(
    tgt: ?*c.struct_agp_rendertarget,
    proxy_state: ?*const fn (?*c.struct_agp_rendertarget, usize) callconv(.c) bool,
    tag: usize,
) void {
    _ = tgt;
    _ = proxy_state;
    _ = tag;
}

export fn agp_rendertarget_swap(
    dst: ?*c.struct_agp_rendertarget,
    swap: ?*bool,
) ?*c.struct_agp_vstore {
    _ = dst;
    if (swap) |s| s.* = false;
    return null;
}

export fn agp_rendertarget_dropswap(tgt: ?*c.struct_agp_rendertarget) void {
    _ = tgt;
}

export fn agp_rendertarget_dirty(
    dst: ?*c.struct_agp_rendertarget,
    dirty: ?*c.struct_agp_region,
) usize {
    const rt: ?*VkRendertarget = if (dst) |d| @ptrCast(@alignCast(d)) else null;
    const r = rt orelse return 0;

    // If dirty region pointer provided, mark as dirty (GL: glshared.c:297-300)
    if (dirty != null) {
        r.dirty_region += 1;
        r.dirty_region_decay += 1;
    }

    return r.dirty_region_decay;
}

export fn agp_rendertarget_dirty_reset(
    src: ?*c.struct_agp_rendertarget,
    dst: ?*c.struct_agp_region,
) void {
    _ = dst;
    const rt: ?*VkRendertarget = if (src) |s| @ptrCast(@alignCast(s)) else null;
    const r = rt orelse return;

    // GL: glshared.c:1140-1141 — decay snapshots region, region resets to 0
    r.dirty_region_decay = r.dirty_region;
    r.dirty_region = 0;
}

// Vstore (Texture Backing Store)

export fn agp_activate_vstore(backing: ?*c.struct_agp_vstore) void {
    const s = backing orelse return;
    if (s.txmapped == c.TXSTATE_OFF) return;
    vk_env_bind_texture(s.vinf.text.glid);
}

export fn agp_deactivate_vstore() void {
    // Bind the default white texture (slot 0)
    vk_env_bind_texture(0);
}

export fn agp_null_vstore(backing: ?*c.struct_agp_vstore) void {
    const s = backing orelse return;
    if (s.vinf.text.glid != 0) {
        vk_env_destroy_texture(s.vinf.text.glid);
        s.vinf.text.glid = 0;
    }
}

export fn agp_empty_vstore(backing: ?*c.struct_agp_vstore, w: usize, h: usize) void {
    const s = backing orelse return;

    const sz: u32 = @intCast(w * h * @sizeOf(c.av_pixel));
    if (s.vinf.text.s_raw == 0) {
        s.vinf.text.s_raw = sz;
    }

    // Allocate raw pixel buffer
    s.vinf.text.raw = @ptrCast(@alignCast(c.arcan_alloc_mem(
        s.vinf.text.s_raw,
        c.ARCAN_MEM_VBUFFER,
        c.ARCAN_MEM_BZERO,
        c.ARCAN_MEMALIGN_PAGE,
    )));
    s.w = w;
    s.h = h;
    s.bpp = @sizeOf(c.av_pixel);
    s.txmapped = c.TXSTATE_TEX2D;

    // Create GPU texture and upload zeroed pixels
    rcdbg("EV-preupdate");
    agp_update_vstore(backing, true);
    rcdbg("EV-postupdate");

    // Free host-side buffer (like GL backend)
    c.arcan_mem_free(@ptrCast(s.vinf.text.raw));
    s.vinf.text.raw = null;
    s.vinf.text.s_raw = 0;
}

export fn agp_empty_vstoreext(
    backing: ?*c.struct_agp_vstore,
    w: usize,
    h: usize,
    hint: c_uint,
) void {
    _ = hint;
    agp_empty_vstore(backing, w, h);
}

/// Resize a vstore: update dimensions and re-upload to GPU.
/// Matches GL backend (gl21.c:363 alloc_buffer + gl21.c:499 agp_resize_vstore):
/// - If buffer size matches new dimensions, keep existing raw (preserves text
///   rendered by process_chain before this call)
/// - If buffer size differs (actual resize), free old and allocate new
/// - If raw is null, allocate new
export fn agp_resize_vstore(backing: ?*c.struct_agp_vstore, w: usize, h: usize) void {
    const s = backing orelse return;

    s.w = w;
    s.h = h;
    s.bpp = @sizeOf(c.av_pixel);

    // Match GL's alloc_buffer: realloc only if size changed
    const needed: u32 = @intCast(w * h * @sizeOf(c.av_pixel));
    if (s.vinf.text.s_raw != needed) {
        if (s.vinf.text.raw != null) {
            c.arcan_mem_free(@ptrCast(s.vinf.text.raw));
            s.vinf.text.raw = null;
        }
    }
    if (s.vinf.text.raw == null) {
        s.vinf.text.s_raw = needed;
        s.vinf.text.raw = @ptrCast(@alignCast(c.arcan_alloc_mem(
            needed,
            c.ARCAN_MEM_VBUFFER,
            c.ARCAN_MEM_BZERO,
            c.ARCAN_MEMALIGN_PAGE,
        )));
    }
    s.txmapped = c.TXSTATE_TEX2D;

    // Upload pixel data to GPU (create or update texture)
    agp_update_vstore(backing, true);
}

export fn agp_drop_vstore(backing: ?*c.struct_agp_vstore) void {
    const s = backing orelse return;
    if (s.vinf.text.glid != 0) {
        vk_env_destroy_texture(s.vinf.text.glid);
        s.vinf.text.glid = 0;
    }
}

export fn agp_activate_vstore_multi(backing: ?*?*c.struct_agp_vstore, n: usize) void {
    const stores = backing orelse return;
    if (n == 0) return;

    // Bind primary texture (index 0)
    const s0: *?*c.struct_agp_vstore = @ptrCast(stores);
    if (s0.*) |store0| {
        if (store0.txmapped != c.TXSTATE_OFF) {
            vk_env_bind_texture(store0.vinf.text.glid);
        }
    }

    // Bind secondary texture (index 1) to descriptor binding 2
    if (n >= 2) {
        const arr: [*]?*c.struct_agp_vstore = @ptrCast(stores);
        if (arr[1]) |store1| {
            if (store1.txmapped != c.TXSTATE_OFF) {
                vk_env_bind_secondary_texture(store1.vinf.text.glid);
            }
        }
    }

    // n > 2: additional texture units not yet supported
}

export fn agp_slice_vstore(
    backing: ?*c.struct_agp_vstore,
    n_slices: usize,
    base_size: usize,
    txstate: c_uint,
) bool {
    _ = backing;
    _ = n_slices;
    _ = base_size;
    _ = txstate;
    return false;
}

export fn agp_slice_synch(
    backing: ?*c.struct_agp_vstore,
    n_slices: usize,
    slices: ?*?*c.struct_agp_vstore,
) bool {
    _ = backing;
    _ = n_slices;
    _ = slices;
    return false;
}

export fn agp_resolve_texid(vs: ?*c.struct_agp_vstore) c_uint {
    const s = vs orelse return 0;
    return s.vinf.text.glid;
}

export fn agp_vstore_copyreg(
    src: ?*c.struct_agp_vstore,
    dst: ?*c.struct_agp_vstore,
    x1: usize,
    y1: usize,
    x2: usize,
    y2: usize,
) void {
    _ = src;
    _ = dst;
    _ = x1;
    _ = y1;
    _ = x2;
    _ = y2;
}

export fn agp_update_vstore(s: ?*c.struct_agp_vstore, copy: bool) void {
    const vs = s orelse return;

    if (vs.txmapped == c.TXSTATE_OFF) {
        if (copy and vs.vinf.text.raw != null and vs.w > 0 and vs.h > 0) {
            vs.txmapped = c.TXSTATE_TEX2D;
        } else {
            return;
        }
    }

    if (copy) {
        if (vs.vinf.text.glid == 0) {
            // Create new GPU texture
            rcdbg("UV-precreate");
            vs.vinf.text.glid = vk_env_create_texture(
                @intCast(vs.w),
                @intCast(vs.h),
                @ptrCast(vs.vinf.text.raw),
            );
            rcdbg("UV-postcreate");
        } else {
            // Update existing texture
            vk_env_update_texture(
                vs.vinf.text.glid,
                @intCast(vs.w),
                @intCast(vs.h),
                @ptrCast(vs.vinf.text.raw),
            );
        }
        if (vs.refcount == 0) vs.refcount = 1;
        vs.update_ts = @truncate(@as(u64, @bitCast(c.arcan_timemillis())));
    }
}

// Streaming

// Access stream_meta fields through the anonymous union/struct chain
inline fn smBuf(meta: *const c.struct_stream_meta) ?[*]c.av_pixel {
    return meta.unnamed_0.unnamed_0.buf;
}

inline fn smDirty(meta: *const c.struct_stream_meta) bool {
    return meta.unnamed_0.unnamed_0.dirty;
}

inline fn smX1(meta: *const c.struct_stream_meta) c_uint {
    return meta.unnamed_0.unnamed_0.x1;
}

inline fn smY1(meta: *const c.struct_stream_meta) c_uint {
    return meta.unnamed_0.unnamed_0.y1;
}

inline fn smW(meta: *const c.struct_stream_meta) c_uint {
    return meta.unnamed_0.unnamed_0.w;
}

inline fn smH(meta: *const c.struct_stream_meta) c_uint {
    return meta.unnamed_0.unnamed_0.h;
}

inline fn smStride(meta: *const c.struct_stream_meta) c_uint {
    return meta.unnamed_0.unnamed_0.stride;
}

fn alloc_buffer(s: *c.struct_agp_vstore) void {
    if (s.vinf.text.raw != null) return;
    const sz: u32 = @intCast(@as(usize, s.w) * @as(usize, s.h) * @sizeOf(c.av_pixel));
    s.vinf.text.s_raw = sz;
    s.vinf.text.raw = @ptrCast(@alignCast(c.arcan_alloc_mem(
        sz,
        c.ARCAN_MEM_VBUFFER,
        c.ARCAN_MEM_BZERO,
        c.ARCAN_MEMALIGN_PAGE,
    )));
}

export fn agp_stream_prepare(
    store: ?*c.struct_agp_vstore,
    base: c.struct_stream_meta,
    stream_type: c_uint,
) c.struct_stream_meta {
    const s = store orelse return base;

    var res = base;
    res.state = true;
    res.@"type" = stream_type;

    if (stream_type == c.STREAM_RAW) {
        // Allocate buffer for caller to fill; upload happens on agp_stream_release
        alloc_buffer(s);
        res.unnamed_0.unnamed_0.buf = s.vinf.text.raw;
        res.state = (s.vinf.text.raw != null);
    } else if (stream_type == c.STREAM_RAW_DIRECT or
        stream_type == c.STREAM_RAW_DIRECT_COPY or
        stream_type == c.STREAM_RAW_DIRECT_SYNCHRONOUS)
    {
        const buf = smBuf(&base);
        if (buf) |px| {
            // Upload CPU-rasterized background (cell backgrounds, cursor, borders).
            // For Slug targets, the cached glyph draw is replayed after upload
            // (see below) so text persists even when only backgrounds are refreshed.
            if (smDirty(&base)) {
                // Sub-region upload
                const mx = smX1(&base);
                const my = smY1(&base);
                const mw = smW(&base);
                const mh = smH(&base);
                const mstride = smStride(&base);
                if (s.vinf.text.glid != 0 and mw > 0 and mh > 0) {
                    vk_env_update_texture_sub(
                        s.vinf.text.glid,
                        mx,
                        my,
                        mw,
                        mh,
                        mstride,
                        @ptrCast(px),
                    );
                } else if (s.vinf.text.glid == 0) {
                    s.vinf.text.glid = vk_env_create_texture(
                        @intCast(s.w),
                        @intCast(s.h),
                        @ptrCast(px),
                    );
                    if (s.refcount == 0) s.refcount = 1;
                }
            } else {
                // Full texture upload
                if (s.vinf.text.glid != 0) {
                    vk_env_update_texture(
                        s.vinf.text.glid,
                        @intCast(s.w),
                        @intCast(s.h),
                        @ptrCast(px),
                    );
                } else {
                    s.vinf.text.glid = vk_env_create_texture(
                        @intCast(s.w),
                        @intCast(s.h),
                        @ptrCast(px),
                    );
                    if (s.refcount == 0) s.refcount = 1;
                }
            }

        }
    } else if (stream_type == c.STREAM_EXT_RESYNCH) {
        // Invalidate and rebuild texture
        agp_null_vstore(store);
        agp_update_vstore(store, true);
    } else if (stream_type == c.STREAM_HANDLE) {
        // DMA-BUF import via VK_EXT_external_memory_dma_buf
        const planes = &base.unnamed_0.unnamed_1.planes;
        const used = base.unnamed_0.unnamed_1.used;
        if (used > 0) {
            const plane = &planes[0];
            const plane_fd = plane.fd;
            const plane_w: u32 = @intCast(plane.w);
            const plane_h: u32 = @intCast(plane.h);
            const plane_stride = plane.unnamed_0.gbm.stride;
            const plane_offset = plane.unnamed_0.gbm.offset;
            const plane_format = plane.unnamed_0.gbm.format;
            const plane_modifier: u64 = (@as(u64, plane.unnamed_0.gbm.mod_hi) << 32) | @as(u64, plane.unnamed_0.gbm.mod_lo);

            const eff_w = if (plane_w > 0) plane_w else @as(u32, @intCast(s.w));
            const eff_h = if (plane_h > 0) plane_h else @as(u32, @intCast(s.h));

            if (s.vinf.text.glid != 0) {
                // In-place update: reuse slot + descriptor set, swap Vulkan resources
                if (vk_env_update_dmabuf_texture(s.vinf.text.glid, plane_fd, eff_w, eff_h, plane_stride, plane_offset, plane_format, plane_modifier)) {
                    if (plane_w > 0) s.w = @intCast(plane_w);
                    if (plane_h > 0) s.h = @intCast(plane_h);
                    res.state = true;
                } else {
                    // Fallback: destroy + reimport
                    vk_env_destroy_texture(s.vinf.text.glid);
                    s.vinf.text.glid = 0;
                    const glid = vk_env_import_dmabuf_texture(plane_fd, eff_w, eff_h, plane_stride, plane_offset, plane_format, plane_modifier);
                    if (glid != 0) {
                        s.vinf.text.glid = glid;
                        s.vinf.text.s_raw = 0;
                        if (plane_w > 0) s.w = @intCast(plane_w);
                        if (plane_h > 0) s.h = @intCast(plane_h);
                        s.bpp = @sizeOf(c.av_pixel);
                        s.txmapped = c.TXSTATE_TEX2D;
                        if (s.refcount == 0) s.refcount = 1;
                        res.state = true;
                    } else {
                        res.state = false;
                    }
                }
            } else {
                // First frame: allocate new slot
                const glid = vk_env_import_dmabuf_texture(plane_fd, eff_w, eff_h, plane_stride, plane_offset, plane_format, plane_modifier);
                if (glid != 0) {
                    s.vinf.text.glid = glid;
                    s.vinf.text.s_raw = 0;
                    if (plane_w > 0) s.w = @intCast(plane_w);
                    if (plane_h > 0) s.h = @intCast(plane_h);
                    s.bpp = @sizeOf(c.av_pixel);
                    s.txmapped = c.TXSTATE_TEX2D;
                    if (s.refcount == 0) s.refcount = 1;
                    res.state = true;
                } else {
                    res.state = false;
                }
            }
        } else {
            res.state = false;
        }
    }

    return res;
}

export fn agp_stream_commit(s: ?*c.struct_agp_vstore, meta: c.struct_stream_meta) void {
    _ = s;
    _ = meta;
}

export fn agp_stream_release(s: ?*c.struct_agp_vstore, meta: c.struct_stream_meta) void {
    const vs = s orelse return;
    const stream_type: c_uint = meta.@"type";

    if (stream_type == c.STREAM_RAW) {
        // The caller filled vs.vinf.text.raw — now upload it
        if (vs.vinf.text.raw) |raw| {
            if (vs.vinf.text.glid != 0) {
                vk_env_update_texture(
                    vs.vinf.text.glid,
                    @intCast(vs.w),
                    @intCast(vs.h),
                    @ptrCast(raw),
                );
            } else {
                vs.vinf.text.glid = vk_env_create_texture(
                    @intCast(vs.w),
                    @intCast(vs.h),
                    @ptrCast(raw),
                );
                if (vs.refcount == 0) vs.refcount = 1;
            }
            vs.update_ts = @truncate(@as(u64, @bitCast(c.arcan_timemillis())));
        }
    }
    // Other modes: no-op on release (upload already happened in prepare)
}

// Drawing

var pipeline_mode: c_uint = 0;

export fn agp_pipeline_hint(mode: c_uint) void {
    pipeline_mode = mode;
    // PIPELINE_2D=0, PIPELINE_3D=1 (from agp_platform.h:264-266)
    vk_env_set_depth_active(mode == 1);
}

export fn agp_blendstate(mode: c_uint) void {
    vk_env_set_blend_mode(mode);
}

export fn agp_draw_vobj(
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    txcos: ?[*]const f32,
    modelview: ?[*]const f32,
) void {
    // Set modelview matrix via shader envv
    const MODELVIEW_MATR = 0;
    if (modelview) |mv| {
        _ = agp_shader_envv(MODELVIEW_MATR, @ptrCast(@constCast(mv)), @sizeOf(f32) * 16);
        // BUG-5: check for flipped coords
        // Debug draw logging removed
    } else {
        _ = agp_shader_envv(MODELVIEW_MATR, @ptrCast(@constCast(&ident)), @sizeOf(f32) * 16);
    }

    // Default texture coordinates if not provided
    const default_txcos = [8]f32{ 0, 0, 1, 0, 1, 1, 0, 1 };
    const tc = txcos orelse &default_txcos;

    // Build 6 vertices as triangle list (two explicit triangles).
    // txcos: [0,1]=TL, [2,3]=TR, [4,5]=BR, [6,7]=BL
    var verts: [24]f32 = undefined;
    // Triangle 1: TL, TR, BL
    verts[0] = x1;  verts[1] = y1;  verts[2] = tc[0]; verts[3] = tc[1];  // TL
    verts[4] = x2;  verts[5] = y1;  verts[6] = tc[2]; verts[7] = tc[3];  // TR
    verts[8] = x1;  verts[9] = y2;  verts[10] = tc[6]; verts[11] = tc[7]; // BL
    // Triangle 2: TR, BR, BL
    verts[12] = x2; verts[13] = y1; verts[14] = tc[2]; verts[15] = tc[3]; // TR
    verts[16] = x2; verts[17] = y2; verts[18] = tc[4]; verts[19] = tc[5]; // BR
    verts[20] = x1; verts[21] = y2; verts[22] = tc[6]; verts[23] = tc[7]; // BL

    vk_env_draw_quad(&verts, 24);

    // TRACE: count draws and log active texture
    {
        const SD = struct { var count: u32 = 0; };
        SD.count += 1;
        if (SD.count <= 20) {
        }
    }

    // Mark active rendertarget as dirty (GL: glshared.c:1578)
    markActiveDirty();
}

// GPU Glyph Rendering (Slug Algorithm)
//
// Called from arcan_renderfun.zig after tui_raster_renderagp uploads the
// CPU-rasterized background. Overdraw glyph instances using Slug shader.

var slug_initialized: bool = false;
var slug_last_tex_id: u32 = 0; // glid of the last vstore Slug drew into
var slug_pipeline_handle: u64 = 0;
var slug_vert_mod: u64 = 0;
var slug_frag_mod: u64 = 0;

// Slug atlas texture IDs (Vulkan texture slots)
var slug_curve_tex_id: u32 = 0;
var slug_band_tex_id: u32 = 0;
var slug_textures_created: bool = false;

// No replay/tracking needed — GPU renders all cell content (bg + text + decorations)
// in a single instanced draw per terminal. The tpack/tuisynch handlers call
// agp_slug_draw_instances after CPU upload, which is the only draw site.

// SDF atlas: persistent R16F texture for temporal coverage accumulation
var sdf_atlas_tex_id: u32 = 0;
var sdf_atlas_created: bool = false;
var sdf_accum_pipeline_handle: u64 = 0;
var sdf_accum_vert_mod: u64 = 0;
var sdf_accum_frag_mod: u64 = 0;

// Vulkan bridge functions from vk.zig
extern fn vk_env_create_shader_module(spv_ptr: [*]const u8, spv_len: u32) u64;
extern fn vk_env_create_slug_pipeline(vert_handle: u64, frag_handle: u64) u64;
extern fn vk_env_create_slug_quad_buffer() bool;
extern fn vk_env_create_slug_instance_buffer() bool;
extern fn vk_env_upload_slug_instances(data: ?*const anyopaque, byte_count: u32) bool;
extern fn vk_env_get_slug_quad_buffer() u64;
extern fn vk_env_get_slug_instance_buffer() u64;
extern fn vk_env_slug_draw(pipeline: u64, tex_id: u32, instance_count: u32) bool;
extern fn vk_env_create_texture_f16(w: u32, h: u32, pixels: ?[*]const u8) u32;
extern fn vk_env_create_texture_u16(w: u32, h: u32, pixels: ?[*]const u8) u32;
extern fn vk_env_create_texture_f32(w: u32, h: u32, pixels: ?[*]const u8) u32;
extern fn vk_env_slug_draw_with_textures(pipeline: u64, tex_id: u32, instance_count: u32, curve_tex: u32, band_tex: u32) bool;
extern fn vk_env_create_sdf_atlas(w: u32, h: u32) u32;
extern fn vk_env_create_slug_sdf_pipeline(vert_handle: u64, frag_handle: u64) u64;
extern fn vk_env_slug_sdf_accumulate(pipeline: u64, sdf_atlas_tex_id: u32, instance_count: u32, curve_tex: u32, band_tex: u32) bool;
extern fn vk_env_slug_draw_with_sdf(pipeline: u64, tex_id: u32, instance_count: u32, curve_tex: u32, band_tex: u32, sdf_atlas_tex_id: u32) bool;
extern fn slug_atlas_increment_sample_counts() void;
extern fn vk_env_dump_sdf_atlas(sdf_atlas_tex_id: u32, instance_count: u32) void;

// SDF stats (from arcan_ttf.zig)
const SdfStats = extern struct {
    total_glyphs: u32,
    converged: u32,
    max_sample_count: u16,
    min_sample_count: u16,
    sdf_alloc_x: u16,
    sdf_alloc_y: u16,
};
extern fn slug_atlas_get_sdf_stats(out: *SdfStats) void;

// SDF diagnostic frame counter
var sdf_diag_frame: u32 = 0;

// STB reference atlas (on-disk, loaded at runtime for GPU comparison)
var stb_ref_tex_id: u32 = 0;
var stb_ref_loaded: bool = false;
extern fn slug_atlas_load_stb_ref(ptsize: u32) bool;
extern fn slug_atlas_get_stb_ref(out_w: *u32, out_h: *u32) ?[*]const u8;
extern fn slug_atlas_stb_loaded() bool;
extern fn vk_env_create_texture_r8(w: u32, h: u32, pixels: ?[*]const u8) u32;

// Compute grading infrastructure
extern fn vk_env_create_ssbo(size_bytes: u32) bool;
extern fn vk_env_get_ssbo_ptr() ?[*]u8;
extern fn vk_env_create_region_ssbo(size_bytes: u32) bool;
extern fn vk_env_get_region_ssbo_ptr() ?[*]u8;
extern fn vk_env_create_grade_compute(comp_handle: u64) bool;
extern fn vk_env_dispatch_grade(sdf_tex: u32, stb_tex: u32, num_glyphs: u32) bool;

// ADMM infrastructure
extern fn vk_env_create_admm_ssbo(size_bytes: u32) bool;
extern fn vk_env_get_admm_ssbo_ptr() ?[*]u8;
extern fn vk_env_create_cov_perturbed(w: u32, h: u32) bool;
extern fn vk_env_get_cov_plus_tex() u32;
extern fn vk_env_get_cov_minus_tex() u32;
extern fn vk_env_slug_sdf_accum_perturbed(pipeline: u64, target_tex: u32, instance_count: u32, curve_tex: u32, band_tex: u32, ramp: f32) bool;
extern fn vk_env_set_slug_ramp(ramp: f32) void;
extern fn vk_env_set_slug_params(ramp: f32, alpha: f32, beta: f32) void;
extern fn vk_env_set_sdf_dump_ptsize(ptsize: u32) void;
extern fn vk_env_reset_sdf_atlas(sdf_tex_id: u32) void;
extern fn vk_env_update_texture_r8(id: u32, w: u32, h: u32, pixels: ?[*]const u8) void;

var grade_compute_ready: bool = false;
var grade_dispatched: bool = false;
var admm_ready: bool = false;
var admm_converged_count: u32 = 0;
var admm_current_ramp: f32 = 0.5; // global optimized ramp

// SDF entry info (matches arcan_ttf.zig + vk.zig definition)
const SdfEntryInfo = extern struct {
    codepoint: u32,
    sdf_x: u16,
    sdf_y: u16,
    sdf_w: u16,
    sdf_h: u16,
    sample_count: u16,
};
extern fn slug_atlas_iter_sdf(out: [*]SdfEntryInfo, max_entries: u32) u32;

// Multi-size STB + font pointer caching
extern fn slug_atlas_load_all_stb_refs() bool;
extern fn slug_atlas_blit_stb_for_size(ptsize: u32) bool;
extern fn slug_atlas_get_stb_cell_size(ptsize: u32, out_w: *u16, out_h: *u16) bool;
extern fn slug_atlas_reset_sdf() void;
extern fn slug_atlas_set_cell_override(w: u16, h: u16) void;
extern fn slug_atlas_set_scale_override(scale: f32) void;
extern fn slug_atlas_compute_scale(font_ptr: ?*anyopaque, ptsize: u32) f32;
extern fn slug_atlas_lookup(font_ptr: ?*anyopaque, codepoint: u32, out: *GlyphInstanceLookup) void;

var cached_font_ptr: ?*anyopaque = null;

/// Called from arcan_raster.zig to cache the font pointer for ADMM calibration.
export fn slug_cache_font_ptr(font_ptr: ?*anyopaque) void {
    if (cached_font_ptr == null and font_ptr != null) {
        cached_font_ptr = font_ptr;
    }
}

// GlyphInstanceLookup — matches arcan_ttf.zig's GlyphInstanceData
const GlyphInstanceLookup = extern struct {
    em_min: [2]f32,
    em_max: [2]f32,
    band_transform: [4]f32,
    glyph_data: [4]i32,
    valid: bool,
    sdf_atlas_x: u16 = 0,
    sdf_atlas_y: u16 = 0,
    sdf_atlas_w: u16 = 0,
    sdf_atlas_h: u16 = 0,
    sdf_sample_count: u16 = 0,
};

// GpuCellInstance — 96 bytes, matches arcan_raster.zig
const GpuCellInstance = extern struct {
    cell_pos: [2]f32,
    cell_size: [2]f32,
    em_min: [2]f32,
    em_max: [2]f32,
    band_transform: [4]f32,
    glyph_data: [4]i32,
    fg_color: [4]f32,
    bg_color: [4]f32,
};

// Codepoint ranges matching STB atlas generator
const cp_ranges = [_][2]u32{
    .{ 0x0020, 0x007E }, // ASCII printable
    .{ 0x00A0, 0x00FF }, // Latin-1 supplement
    .{ 0x0100, 0x017F }, // Latin Extended-A
    .{ 0x2000, 0x206F }, // General punctuation
    .{ 0x2190, 0x21FF }, // Arrows
    .{ 0x2500, 0x257F }, // Box drawing
    .{ 0x2580, 0x259F }, // Block elements
    .{ 0x25A0, 0x25FF }, // Geometric shapes
    .{ 0x2700, 0x27BF }, // Dingbats
};

/// Force-populate atlas with all codepoints in the STB range.
/// Builds GpuCellInstance array, uploads to instance buffer. Returns instance count.
fn populateAllGlyphs(font_ptr: *anyopaque, cell_w: u16, cell_h: u16) u32 {
    var instances: [4096]GpuCellInstance = undefined;
    var count: u32 = 0;
    const cw: f32 = @floatFromInt(cell_w);
    const ch: f32 = @floatFromInt(cell_h);
    // Grid layout: 80 columns
    const cols: u32 = 80;

    for (cp_ranges) |r| {
        var cp: u32 = r[0];
        while (cp <= r[1] and count < 4096) : (cp += 1) {
            var lookup = GlyphInstanceLookup{
                .em_min = .{ 0, 0 },
                .em_max = .{ 1, 1 },
                .band_transform = .{ 1, 1, 0, 0 },
                .glyph_data = .{ 0, 0, 0, 0 },
                .valid = false,
            };
            slug_atlas_lookup(font_ptr, cp, &lookup);
            if (!lookup.valid) continue;

            // Pack SDF atlas coords into glyph_data
            var gd = lookup.glyph_data;
            gd[2] = (gd[2] & 0xFF) | (@as(i32, @intCast(lookup.sdf_atlas_x)) << 8);
            gd[2] = gd[2] | (@as(i32, @intCast(@min(lookup.sdf_sample_count, 255))) << 20);
            gd[3] = (gd[3] & 0xFFF) | (@as(i32, @intCast(lookup.sdf_atlas_y)) << 12);

            const col = count % cols;
            const row = count / cols;
            instances[count] = .{
                .cell_pos = .{ @as(f32, @floatFromInt(col)) * cw, @as(f32, @floatFromInt(row)) * ch },
                .cell_size = .{ cw, ch },
                .em_min = lookup.em_min,
                .em_max = lookup.em_max,
                .band_transform = lookup.band_transform,
                .glyph_data = gd,
                .fg_color = .{ 1.0, 1.0, 1.0, 1.0 },
                .bg_color = .{ 0.0, 0.0, 0.0, 1.0 },
            };
            count += 1;
        }
    }

    if (count > 0) {
        _ = vk_env_upload_slug_instances(@ptrCast(&instances), count * 96);
    }
    return count;
}

// vk_env_begin_rt_pass / vk_env_end_rt_pass already declared earlier in this file

// Glyph atlas bridge (from arcan_ttf.zig)
extern fn slug_atlas_is_dirty() bool;
extern fn slug_atlas_mark_clean() void;
extern fn slug_atlas_get_curve_data(out_texels: *u32, out_width: *u32) ?[*]const f32;
extern fn slug_atlas_get_band_data(out_texels: *u32, out_width: *u32) ?[*]const u16;

// Shaderc bridge (from vk_shdrmgmt.zig)
extern fn agp_shader_build(
    tag: ?[*:0]const u8,
    geom: ?[*:0]const u8,
    vert: ?[*:0]const u8,
    frag: ?[*:0]const u8,
) u32;

// ADMM Parameter Serialization
// Binary format: "SLUG" magic (4B) + version (4B) + num_entries (4B) + global_ramp (4B)
//                + per-entry: codepoint (4B) + ramp (4B) + flags (4B)

const SlugParamHeader = extern struct {
    magic: u32 = 0x534C5547, // "SLUG"
    version: u32 = 1,
    num_entries: u32 = 0,
    global_ramp: f32 = 0.5,
};

const SlugParamEntry = extern struct {
    codepoint: u32,
    ramp: f32,
    flags: u32, // 0=default, 1=custom ramp
};

fn serializeAdmmParams(quality_ptr: [*]const u8, num_glyphs: u32, entries: *const [1024]SdfEntryInfo) !void {
    const quality: [*]const f32 = @ptrCast(@alignCast(quality_ptr));

    // Build list of non-default entries
    var param_entries: [512]SlugParamEntry = undefined;
    var n_custom: u32 = 0;
    var ramp_sum: f32 = 0.0;

    for (0..num_glyphs) |i| {
        const ramp_val = quality[i * 4 + 2]; // GlyphQuality.ramp
        ramp_sum += ramp_val;

        // Only store entries that differ from default by > 1e-4
        if (@abs(ramp_val - 0.5) > 1e-4) {
            param_entries[n_custom] = .{
                .codepoint = entries.*[i].codepoint,
                .ramp = ramp_val,
                .flags = 1,
            };
            n_custom += 1;
        }
    }

    const global_ramp = if (num_glyphs > 0) ramp_sum / @as(f32, @floatFromInt(num_glyphs)) else 0.5;

    // Write to ~/.arcan/slug_params/
    const home = @import("shmif_types").getenvSpan("HOME") orelse "/tmp";
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.arcan/slug_params", .{home}) catch return error.PathTooLong;

    // Create directory
    std.fs.cwd().makePath(path) catch {};

    var file_buf: [512]u8 = undefined;
    const file_path = std.fmt.bufPrint(&file_buf, "{s}/default_all.bin", .{path}) catch return error.PathTooLong;

    var file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        return err;
    };
    defer file.close();

    // Write header
    const header = SlugParamHeader{
        .num_entries = n_custom,
        .global_ramp = global_ramp,
    };
    file.writeAll(std.mem.asBytes(&header)) catch |err| return err;

    // Write entries
    for (0..n_custom) |i| {
        file.writeAll(std.mem.asBytes(&param_entries[i])) catch |err| return err;
    }

}

/// Load previously serialized ADMM parameters. Returns global ramp or null if no file.
fn loadAdmmParams() ?f32 {
    const home = @import("shmif_types").getenvSpan("HOME") orelse return null;
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.arcan/slug_params/default_all.bin", .{home}) catch return null;

    var file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();

    var header: SlugParamHeader = undefined;
    const bytes_read = file.read(std.mem.asBytes(&header)) catch return null;
    if (bytes_read < @sizeOf(SlugParamHeader)) return null;
    if (header.magic != 0x534C5547 or header.version != 1) return null;

    return header.global_ramp;
}

/// Compile GLSL shader source to SPIR-V, create shader module.
/// Returns module handle or 0 on failure.
fn compileSlugShader(src: []const u8, is_vertex: bool) u64 {
    _ = is_vertex;
    // agp_shader_build compiles GLSL→SPIR-V internally, but we need
    // raw SPIR-V modules for the custom Slug pipeline.
    // Use the embedded pre-compiled SPIR-V instead.
    const spv = if (src.ptr == @embedFile("shaders/slug_glyph.vert").ptr)
        @embedFile("shaders/slug_glyph_vert.spv")
    else
        @embedFile("shaders/slug_glyph_frag.spv");
    return vk_env_create_shader_module(spv.ptr, @intCast(spv.len));
}

// Multi-size burst calibration: 101 sizes × 596 glyphs × 5 ADMM rounds
const ACCUM_FRAMES: u32 = 20;
const ADMM_MAX_ROUNDS: u32 = 100;
const ADMM_FD_H: f32 = 0.01;
const SIZE_MIN: u32 = 8;
const SIZE_MAX: u32 = 38;

fn fwrite(file: anytype, comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch buf[0..buf.len];
    file.writeAll(s) catch {};
}

fn runCalibrationBurst(_: u32) !void {
    const font_ptr = cached_font_ptr orelse return error.NoFontPtr;


    // Load all STB references into CPU RAM
    if (!slug_atlas_load_all_stb_refs()) return error.NoStbRefs;

    var file = std.fs.cwd().createFile("/tmp/admm_calibration.txt", .{}) catch return error.FileCreate;
    defer file.close();

    var sizes_done: u32 = 0;

    for (SIZE_MIN..SIZE_MAX + 1) |ptsize| {
        var cell_w: u16 = 0;
        var cell_h: u16 = 0;
        if (!slug_atlas_get_stb_cell_size(@intCast(ptsize), &cell_w, &cell_h)) continue;

        slug_atlas_reset_sdf();
        slug_atlas_set_cell_override(cell_w, cell_h);
        const computed_scale = slug_atlas_compute_scale(font_ptr, @intCast(ptsize));
        if (computed_scale == 0) @panic("slug_atlas_compute_scale returned 0");
        slug_atlas_set_scale_override(computed_scale);
        if (ptsize % 20 == 0) {
        }
        vk_env_reset_sdf_atlas(sdf_atlas_tex_id);

        const inst_n = populateAllGlyphs(font_ptr, cell_w, cell_h);
        if (inst_n == 0) continue;

        // Rebuild curve/band textures
        if (slug_atlas_is_dirty()) {
            var ct: u32 = 0;
            var cw: u32 = 0;
            var bt: u32 = 0;
            var bw: u32 = 0;
            const cp = slug_atlas_get_curve_data(&ct, &cw);
            const bp = slug_atlas_get_band_data(&bt, &bw);
            if (cp != null and bp != null and ct > 0 and bt > 0) {
                vk_env_destroy_texture(slug_curve_tex_id);
                vk_env_destroy_texture(slug_band_tex_id);
                const ch2 = (ct + cw - 1) / cw;
                const bh2 = (bt + bw - 1) / bw;
                slug_curve_tex_id = vk_env_create_texture_f32(cw, if (ch2 > 0) ch2 else 1, @ptrCast(cp));
                slug_band_tex_id = vk_env_create_texture_u16(bw, if (bh2 > 0) bh2 else 1, @ptrCast(bp));
            }
            slug_atlas_mark_clean();
        }

        // Accumulate Slug coverage (reference algorithm)
        for (0..ACCUM_FRAMES) |_| {
            _ = vk_env_slug_sdf_accumulate(sdf_accum_pipeline_handle, sdf_atlas_tex_id, inst_n, slug_curve_tex_id, slug_band_tex_id);
            slug_atlas_increment_sample_counts();
        }

        // Dump SDF PPMs at this size (use ptsize in filename, not cell_h)
        vk_env_set_sdf_dump_ptsize(@intCast(ptsize));
        vk_env_dump_sdf_atlas(sdf_atlas_tex_id, inst_n);

        sizes_done += 1;
        if (sizes_done % 10 == 0) {
        }
    }

    fwrite(file, "# Slug vs STB comparison: {d} sizes x 596 glyphs\n", .{sizes_done});
    fwrite(file, "# CalcCoverage: exact Slug reference (Lengyel 2026 public domain)\n", .{});
    fwrite(file, "# No ADMM — pure algorithm comparison\n", .{});

    // Dump visual proof at 48px: render with ADMM params, dump SDF atlas PPMs
    {
        var cw48: u16 = 0;
        var ch48: u16 = 0;
        if (slug_atlas_get_stb_cell_size(48, &cw48, &ch48)) {
            slug_atlas_reset_sdf();
            slug_atlas_set_cell_override(cw48, ch48);
            slug_atlas_set_scale_override(slug_atlas_compute_scale(font_ptr, 48));
            vk_env_reset_sdf_atlas(sdf_atlas_tex_id);
            const n48 = populateAllGlyphs(font_ptr, cw48, ch48);
            if (slug_atlas_is_dirty()) {
                var ct2: u32 = 0;
                var cw2: u32 = 0;
                var bt2: u32 = 0;
                var bw2: u32 = 0;
                const cp2 = slug_atlas_get_curve_data(&ct2, &cw2);
                const bp2 = slug_atlas_get_band_data(&bt2, &bw2);
                if (cp2 != null and bp2 != null and ct2 > 0 and bt2 > 0) {
                    vk_env_destroy_texture(slug_curve_tex_id);
                    vk_env_destroy_texture(slug_band_tex_id);
                    slug_curve_tex_id = vk_env_create_texture_f32(cw2, @max((ct2 + cw2 - 1) / cw2, 1), @ptrCast(cp2));
                    slug_band_tex_id = vk_env_create_texture_u16(bw2, @max((bt2 + bw2 - 1) / bw2, 1), @ptrCast(bp2));
                }
                slug_atlas_mark_clean();
            }
            // Accumulate with ADMM-optimized params
            for (0..ACCUM_FRAMES) |_| {
                _ = vk_env_slug_sdf_accumulate(sdf_accum_pipeline_handle, sdf_atlas_tex_id, n48, slug_curve_tex_id, slug_band_tex_id);
                slug_atlas_increment_sample_counts();
            }
            // Dump per-glyph PPMs (writes to tests/render_pipeline/output/)
            vk_env_dump_sdf_atlas(sdf_atlas_tex_id, n48);

            // Also dump STB reference for 48px
            _ = slug_atlas_blit_stb_for_size(48);
        }
    }

    slug_atlas_set_cell_override(0, 0);
    slug_atlas_set_scale_override(0); // restore default behavior
}

/// Draw GPU-rendered glyphs over the vstore texture.
/// Called from arcan_renderfun.zig after CPU background upload.
export fn agp_slug_draw_instances(instances: ?*const anyopaque, count: u32, tex_id: u32) void {
    // Slug GPU glyph rendering entry point
    slug_last_tex_id = tex_id; // track which vstore Slug draws into
    if (count == 0 or instances == null) return;

    // Lazy init: create Slug pipeline + buffers on first call
    if (!slug_initialized) {
        slug_initialized = true;

        // Create shader modules from pre-compiled SPIR-V.
        // SPIR-V must be u32-aligned; @embedFile may not be, so use aligned copies.
        const vert_spv = @embedFile("shaders/slug_glyph_vert.spv");
        // Slug curve evaluation fragment shader (compiled from slug_glyph.frag by build.zig)
        const frag_spv = @embedFile("shaders/slug_glyph_frag.spv");
        var vert_aligned: [vert_spv.len]u8 align(4) = vert_spv.*;
        var frag_aligned: [frag_spv.len]u8 align(4) = frag_spv.*;
        slug_vert_mod = vk_env_create_shader_module(&vert_aligned, @intCast(vert_spv.len));
        slug_frag_mod = vk_env_create_shader_module(&frag_aligned, @intCast(frag_spv.len));

        if (slug_vert_mod == 0 or slug_frag_mod == 0) {
            arcan_warning("[slug_gpu] shader module creation failed\n");
            return;
        }

        // Create instanced pipeline
        slug_pipeline_handle = vk_env_create_slug_pipeline(slug_vert_mod, slug_frag_mod);
        if (slug_pipeline_handle == 0) {
            arcan_warning("[slug_gpu] pipeline creation failed\n");
            return;
        }

        // Create static quad buffer + instance buffer
        if (!vk_env_create_slug_quad_buffer()) {
            arcan_warning("[slug_gpu] quad buffer creation failed\n");
            slug_pipeline_handle = 0;
            return;
        }
        if (!vk_env_create_slug_instance_buffer()) {
            arcan_warning("[slug_gpu] instance buffer creation failed\n");
            slug_pipeline_handle = 0;
            return;
        }

        // ADMM parameter loading removed — using reference Slug defaults.
    }

    if (slug_pipeline_handle == 0) return;

    // Upload instance data to GPU buffer (96 bytes per GpuCellInstance)
    const byte_count = count * 96;
    if (!vk_env_upload_slug_instances(instances, byte_count)) {
        arcan_warning("[slug_gpu] instance upload failed\n");
        return;
    }

    // Check if glyph atlas has new curve/band data to upload
    if (slug_atlas_is_dirty() or !slug_textures_created) {
        var curve_texels: u32 = 0;
        var curve_width: u32 = 0;
        var band_texels: u32 = 0;
        var band_width: u32 = 0;
        const curve_ptr = slug_atlas_get_curve_data(&curve_texels, &curve_width);
        const band_ptr = slug_atlas_get_band_data(&band_texels, &band_width);

        if (curve_ptr != null and band_ptr != null and curve_texels > 0 and band_texels > 0) {
            // Compute texture dimensions: width = TEX_WIDTH, height = ceil(texels / width)
            const curve_h = (curve_texels + curve_width - 1) / curve_width;
            const band_h = (band_texels + band_width - 1) / band_width;

            if (slug_textures_created) {
                // Atlas grew — destroy old textures and recreate with new dimensions.
                // vk_env_update_texture only handles RGBA8; our textures are f32/u16,
                // so destroy + recreate is the correct path.
                vk_env_destroy_texture(slug_curve_tex_id);
                vk_env_destroy_texture(slug_band_tex_id);
                slug_curve_tex_id = 0;
                slug_band_tex_id = 0;
                slug_textures_created = false;
            }

            // Create textures (first time or after atlas growth recreate)
            // Curve texture: RGBA float32, 16 bytes/texel
            slug_curve_tex_id = vk_env_create_texture_f32(
                curve_width,
                if (curve_h > 0) curve_h else 1,
                @ptrCast(curve_ptr),
            );
            // Band texture: RGBA uint16, 8 bytes/texel
            slug_band_tex_id = vk_env_create_texture_u16(
                band_width,
                if (band_h > 0) band_h else 1,
                @ptrCast(band_ptr),
            );
            if (slug_curve_tex_id > 0 and slug_band_tex_id > 0) {
                slug_textures_created = true;
            }
            slug_atlas_mark_clean();
        }
    }

    // SDF atlas removed — single-pass Slug rendering is sufficient.
    // The accumulation pipeline is only used during ARCAN_SLUG_CALIBRATE testing.

    // Single-pass Slug rendering directly to vstore.
    // No SDF atlas, no temporal accumulation — pure per-frame curve evaluation.
    // If curve/band textures aren't ready yet (first frame after resize, atlas
    // rebuild, etc.), skip the draw entirely rather than invoking the
    // placeholder path that fills cells with solid fg-color rectangles — that
    // flashed as red-block + cursor across all visible terminals on every
    // resize.
    if (!slug_textures_created) return;
    const draw_ok: bool = vk_env_slug_draw_with_textures(
        slug_pipeline_handle, tex_id, count,
        slug_curve_tex_id, slug_band_tex_id,
    );

    if (draw_ok) {
        // Track this texture so any future CPU upload automatically replays Slug glyphs.
    } else {
        const S = struct { var logged: u32 = 0; };
        if (S.logged < 10) {
            arcan_warning("[slug_gpu] vk_env_slug_draw FAILED (tex=%u count=%u)\n", tex_id, count);
            S.logged += 1;
        }
    }

}

// Mesh

export fn agp_submit_mesh(base: ?*c.struct_agp_mesh_store, fl: c_uint) void {
    const mesh = base orelse return;
    _ = fl;

    if (mesh.@"type" != c.AGP_MESH_TRISOUP) return;
    if (mesh.verts == null or mesh.n_vertices == 0) return;

    const verts: [*]const f32 = @ptrCast(mesh.verts orelse return);
    const txcos: ?[*]const f32 = if (mesh.txcos) |t| @ptrCast(t) else null;
    const vertex_size: usize = @intCast(mesh.vertex_size); // floats per position vertex
    const n: usize = @intCast(mesh.n_vertices);

    // Pack into our 2D vertex format: pos.xy + uv.xy (16 bytes per vertex)
    // Skip Z component and normals for Phase A
    var buf: [4096]f32 = undefined; // 1024 vertices max
    const max_verts = buf.len / 4;
    const count = @min(n, max_verts);

    for (0..count) |i| {
        const vi = i * vertex_size;
        buf[i * 4 + 0] = verts[vi]; // x
        buf[i * 4 + 1] = verts[vi + 1]; // y
        if (txcos) |tc| {
            buf[i * 4 + 2] = tc[i * 2]; // u
            buf[i * 4 + 3] = tc[i * 2 + 1]; // v
        } else {
            buf[i * 4 + 2] = 0;
            buf[i * 4 + 3] = 0;
        }
    }

    // Set modelview via shader envv
    const MODELVIEW_MATR = 0;
    _ = agp_shader_envv(MODELVIEW_MATR, @ptrCast(@constCast(&ident)), @sizeOf(f32) * 16);

    const byte_size: u32 = @intCast(count * 4 * @sizeOf(f32));
    vk_env_draw_mesh_verts(@ptrCast(&buf), byte_size, @intCast(count));

    markActiveDirty();
}

export fn agp_invalidate_mesh(base: ?*c.struct_agp_mesh_store) void {
    _ = base;
}

export fn agp_drop_mesh(s: ?*c.struct_agp_mesh_store) void {
    _ = s;
}

// Stencil

// Readback

export fn agp_readback_synchronous(dst: ?*c.struct_agp_vstore) void {
    const vs = dst orelse return;
    if (vs.txmapped != c.TXSTATE_TEX2D) return;
    if (vs.vinf.text.glid == 0) return;

    const bufsz: u32 = @intCast(@as(usize, vs.w) * @as(usize, vs.h) * @sizeOf(c.av_pixel));

    // Allocate or resize the raw buffer if needed
    if (vs.vinf.text.raw == null or
        (vs.vinf.text.s_raw != 0 and vs.vinf.text.s_raw < bufsz))
    {
        if (vs.vinf.text.raw != null) {
            c.arcan_mem_free(@ptrCast(vs.vinf.text.raw));
        }
        vs.vinf.text.s_raw = bufsz;
        vs.vinf.text.raw = @ptrCast(@alignCast(c.arcan_alloc_mem(
            bufsz,
            c.ARCAN_MEM_VBUFFER,
            c.ARCAN_MEM_BZERO,
            c.ARCAN_MEMALIGN_PAGE,
        )));
    }

    if (vs.vinf.text.raw) |raw| {
        _ = vk_env_readback_texture(vs.vinf.text.glid, @ptrCast(raw), bufsz);
    }
}

export fn agp_request_readback(store: ?*c.struct_agp_vstore) void {
    const vs = store orelse return;
    if (vs.txmapped != c.TXSTATE_TEX2D) return;
    if (vs.vinf.text.glid == 0) return;

    // Submit async readback (double-buffered, returns immediately)
    vk_env_readback_async_submit(vs.vinf.text.glid);
}

export fn agp_poll_readback(store: ?*c.struct_agp_vstore) c.struct_asynch_readback_meta {
    var res: c.struct_asynch_readback_meta = std.mem.zeroes(c.struct_asynch_readback_meta);
    const vs = store orelse return res;
    if (vs.txmapped != c.TXSTATE_TEX2D) return res;

    // Poll async readback (previous frame's result)
    var out_w: u32 = 0;
    var out_h: u32 = 0;
    if (vk_env_readback_async_poll(&out_w, &out_h)) |data| {
        const sz = @as(usize, out_w) * @as(usize, out_h) * @sizeOf(c.av_pixel);
        // Copy to vstore raw buffer so caller owns the data
        const bufsz: u32 = @intCast(sz);
        if (vs.vinf.text.raw == null or
            (vs.vinf.text.s_raw != 0 and vs.vinf.text.s_raw < bufsz))
        {
            if (vs.vinf.text.raw != null) {
                c.arcan_mem_free(@ptrCast(vs.vinf.text.raw));
            }
            vs.vinf.text.s_raw = bufsz;
            vs.vinf.text.raw = @ptrCast(@alignCast(c.arcan_alloc_mem(
                bufsz,
                c.ARCAN_MEM_VBUFFER,
                c.ARCAN_MEM_BZERO,
                c.ARCAN_MEMALIGN_PAGE,
            )));
        }
        if (vs.vinf.text.raw) |raw| {
            const dst: [*]u8 = @ptrCast(raw);
            @memcpy(dst[0..sz], data[0..sz]);
        }
        res.ptr = vs.vinf.text.raw;
        res.buf_sz = sz;
        res.w = @intCast(out_w);
        res.h = @intCast(out_h);
        res.stride = @as(usize, out_w) * @sizeOf(c.av_pixel);
    } else if (vs.vinf.text.raw) |raw| {
        // Return cached data if available (previous successful poll)
        res.ptr = raw;
        res.buf_sz = @as(usize, vs.w) * @as(usize, vs.h) * @sizeOf(c.av_pixel);
        res.w = vs.w;
        res.h = vs.h;
        res.stride = @as(usize, vs.w) * @sizeOf(c.av_pixel);
    }
    return res;
}

// Stencil (matches GL glshared.c:1441-1467)
// Flow: prepare → draw_stencil (writes to stencil buffer) → activate → draw content → disable

export fn agp_prepare_stencil() void {
    // Enable stencil test, disable color writes, func=ALWAYS, op=REPLACE
    // Stencil image is created lazily on first use
    const sw: u32 = 2048; // max expected size, resized as needed
    const sh: u32 = 2048;
    vk_env_stencil_begin(sw, sh);
    vk_env_set_blend_mode(0); // disable blend during stencil fill
    vk_env_set_color_write(false); // disable color writes
}

export fn agp_draw_stencil(x1: f32, y1: f32, x2: f32, y2: f32) void {
    // Draw the clipping geometry into the stencil buffer
    // The stencil write happens via dynamic state in vk_env_draw_quad
    // (stencil_active=true, func=ALWAYS, op=REPLACE writes 1 to stencil)
    const default_txcos = [8]f32{ 0, 0, 1, 0, 1, 1, 0, 1 };
    const MODELVIEW_MATR = 0;
    _ = agp_shader_envv(MODELVIEW_MATR, @ptrCast(@constCast(&ident)), @sizeOf(f32) * 16);

    // Build strip: TL, TR, BL, BR
    var verts: [16]f32 = undefined;
    verts[0] = x1;
    verts[1] = y1;
    verts[2] = default_txcos[0];
    verts[3] = default_txcos[1];
    verts[4] = x2;
    verts[5] = y1;
    verts[6] = default_txcos[2];
    verts[7] = default_txcos[3];
    verts[8] = x1;
    verts[9] = y2;
    verts[10] = default_txcos[6];
    verts[11] = default_txcos[7];
    verts[12] = x2;
    verts[13] = y2;
    verts[14] = default_txcos[4];
    verts[15] = default_txcos[5];

    vk_env_draw_quad(&verts, 16);
}

export fn agp_activate_stencil() void {
    // Re-enable color writes, switch stencil to EQUAL/KEEP mode
    vk_env_stencil_activate();
}

export fn agp_disable_stencil() void {
    // Turn off stencil test entirely
    vk_env_stencil_end();
}
