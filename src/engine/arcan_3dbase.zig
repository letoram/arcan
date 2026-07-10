// Pure Zig port of engine/arcan_3dbase.c — 3D model management, camera, rendering.
// All functions are exported with `export fn` for C linkage, static helpers use `fn`.
//
// NOTE: arcan_3d_camtag uses @cVaStart (C variadic). On aarch64 this requires
// use_llvm=false in build.zig when compiling this file.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

// Arcan C headers removed — they don't exist in this pure-Zig codebase.
// Types imported from arcan_zig_types.zig via @import("arcan").
const arcan = @import("arcan");

// Math types (match arcan_math.zig layout, NOT @cImport anonymous unions)
// These simple extern structs have identical ABI to the C originals (which use
// anonymous unions for x/y/z/w vs xyz[]/xyzw[] overlay, but same memory layout).
const vector = extern struct { x: f32 = 0, y: f32 = 0, z: f32 = 0 };
const point = vector;
const quat = extern struct { x: f32 = 0, y: f32 = 0, z: f32 = 0, w: f32 = 0 };

const surface_orientation = extern struct {
    yaw: f32,
    pitch: f32,
    roll: f32,
    quaternion: quat,
};

const surface_properties = extern struct {
    position: point,
    scale: vector,
    opa: f32,
    rotation: surface_orientation,
};

// Type aliases
const arcan_vobj_id = arcan.arcan_vobj_id;
const arcan_errc = arcan.arcan_errc;
const agp_shader_id = arcan.agp_shader_id;
const vfunc_state = arcan.vfunc_state;
const img_cons = arcan.img_cons;
const arcan_vobject = arcan.arcan_vobject;
const arcan_vobject_litem = arcan.struct_arcan_vobject_litem;
const agp_mesh_store = arcan.struct_agp_mesh_store;
const agp_vstore = arcan.struct_agp_vstore;
const rendertarget = arcan.struct_rendertarget;
const arcan_vr_ctx = anyopaque;
const AgpRenderOptions = extern struct { line_width: c_int = 0 };
const data_source = extern struct { fd: c_int = -1, start: i64 = 0, len: i64 = 0, source: [*c]u8 = null };
const av_pixel = arcan.av_pixel;

// Type conversions
// arcan_vobject uses @cImport types (with anonymous unions), while we use simple
// extern structs for surface_properties/vector/quat. These have identical ABI layouts,
// so @bitCast is safe for conversion.
const c_surface_properties = arcan.surface_properties;
const c_vector = arcan.vector;

inline fn surfPropsFromC(p: c_surface_properties) surface_properties {
    return @bitCast(p);
}

inline fn vectorFromC(v: c_vector) vector {
    return @bitCast(v);
}

// Constants
const ARCAN_EID = arcan.ARCAN_EID;
const ARCAN_OK = arcan.ARCAN_OK;
const ARCAN_ERRC_NO_SUCH_OBJECT = arcan.ARCAN_ERRC_NO_SUCH_OBJECT;
const ARCAN_ERRC_UNACCEPTED_STATE = arcan.ARCAN_ERRC_UNACCEPTED_STATE;
const ARCAN_ERRC_BAD_ARGUMENT = arcan.ARCAN_ERRC_BAD_ARGUMENT;
const ARCAN_ERRC_OUT_OF_SPACE = arcan.ARCAN_ERRC_OUT_OF_SPACE;
const ARCAN_TAG_3DOBJ = arcan.ARCAN_TAG_3DOBJ;
const ARCAN_TAG_3DCAMERA = arcan.ARCAN_TAG_3DCAMERA;
const ffunc_ind = arcan.ffunc_ind;
const FFUNC_3DOBJ = arcan.FFUNC_3DOBJ;
const FFUNC_TICK: c_uint = arcan.FFUNC_TICK;
const FFUNC_DESTROY: c_uint = arcan.FFUNC_DESTROY;
const ARCAN_MEM_VTAG: c_int = @intCast(arcan.ARCAN_MEM_VTAG);
const ARCAN_MEM_MODELDATA: c_int = @intCast(arcan.ARCAN_MEM_MODELDATA);
const ARCAN_MEM_BZERO: c_int = @intCast(arcan.ARCAN_MEM_BZERO);
const ARCAN_MEMALIGN_NATURAL: c_int = @intCast(arcan.ARCAN_MEMALIGN_NATURAL);
const ARCAN_MEMALIGN_PAGE: c_int = @intCast(arcan.ARCAN_MEMALIGN_PAGE);
const ARCAN_MEMALIGN_SIMD: c_int = @intCast(arcan.ARCAN_MEMALIGN_SIMD);
const ARCAN_FRAMESET_SPLIT: c_int = @intCast(arcan.ARCAN_FRAMESET_SPLIT);
const AGP_MESH_TRISOUP: c_int = @intCast(arcan.AGP_MESH_TRISOUP);
const AGP_MESH_POINTCLOUD: c_int = @intCast(arcan.AGP_MESH_POINTCLOUD);
const MESH_FACING_NODEPTH: c_int = @intCast(arcan.MESH_FACING_NODEPTH);
const MESH_FILL_LINE: c_int = @intCast(arcan.MESH_FILL_LINE);
const FL_FULL3D: c_int = @intCast(arcan.FL_FULL3D);
const EPSILON: f32 = 0.0001;
const PIPELINE_3D: c_int = @intCast(arcan.PIPELINE_3D);
const BASIC_3D: c_int = @intCast(arcan.BASIC_3D);
const MODELVIEW_MATR: c_int = @intCast(arcan.MODELVIEW_MATR);
const PROJECTION_MATR: c_int = @intCast(arcan.PROJECTION_MATR);
const OBJ_OPACITY: c_int = @intCast(arcan.OBJ_OPACITY);
const CYLINDER_FILL_HALF: c_int = 0;
const CYLINDER_FILL_HALF_CAPS: c_int = 1;

// Extern C functions
extern fn arcan_alloc_mem(sz: usize, memtype: c_int, hint: c_int, alignment: c_int) ?*anyopaque;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn arcan_video_getobject(id: arcan_vobj_id) ?*arcan_vobject;
extern fn arcan_video_addfobject(feed: ffunc_ind, state: vfunc_state, constraints: img_cons, zv: c_ushort) arcan_vobj_id;
extern fn arcan_video_alterfeed(id: arcan_vobj_id, feed: ffunc_ind, state: vfunc_state) arcan_errc;
extern fn arcan_video_allocframes(id: arcan_vobj_id, count: c_uint, mode: c_int) arcan_errc;
extern fn arcan_resolve_vidprop(vobj: *arcan_vobject, lerp: f32, props: *surface_properties) void;
extern fn arcan_vint_current_rt() ?*rendertarget;
extern fn arcan_vint_findrt(vobj: ?*arcan_vobject) ?*rendertarget;
extern fn arcan_vr_release(vrref: ?*arcan_vr_ctx, id: arcan_vobj_id) arcan_errc;
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;

extern fn agp_pipeline_hint(mode: c_int) void;
extern fn agp_render_options(opts: AgpRenderOptions) void;
extern fn agp_shader_activate(shid: agp_shader_id) c_int;
extern fn agp_default_shader(shtype: c_int) agp_shader_id;
extern fn agp_shader_envv(slot: c_int, value: ?*anyopaque, size: usize) c_int;
extern fn agp_blendstate(mode: c_int) void;
extern fn agp_activate_vstore(backing: ?*agp_vstore) void;
extern fn agp_activate_vstore_multi(backing: [*]?*agp_vstore, n: usize) void;
extern fn agp_submit_mesh(store: *agp_mesh_store, flags: c_int) void;
extern fn agp_drop_mesh(store: *agp_mesh_store) void;

extern fn identity_matrix(m: *[16]f32) void;
extern fn scale_matrix(m: *[16]f32, sx: f32, sy: f32, sz: f32) void;
extern fn translate_matrix(m: *[16]f32, tx: f32, ty: f32, tz: f32) void;
extern fn multiply_matrix(dst: *[16]f32, a: *const [16]f32, b: *const [16]f32) void;
extern fn matr_quatf(q: quat, dst: *[16]f32) *f32;
extern fn norm_quat(q: quat) quat;
extern fn build_quat_taitbryan(roll: f32, pitch: f32, yaw: f32) quat;
extern fn mult_matrix_vecf(matr: *const [16]f32, inv: *const [4]f32, outv: *[4]f32) void;
extern fn build_projection_matrix(m: *[16]f32, near: f32, far: f32, aspect: f32, fov: f32) void;
extern fn dev_coord(out_x: *f32, out_y: *f32, out_z: *f32, x: c_int, y: c_int, w: c_int, h: c_int, near: f32, far: f32) void;
extern fn unproject_matrix(dev_x: f32, dev_y: f32, dev_z: f32, view: *const [16]f32, proj: *const [16]f32) vector;
extern fn norm_vector(v: vector) vector;
extern fn sub_vector(a: vector, b: vector) vector;
extern fn mul_vectorf(a: vector, f: f32) vector;
extern fn ray_sphere(ray_pos: *const vector, ray_dir: *const vector, sphere_pos: *const vector, sphere_rad: f32, d1: *f32, d2: *f32) bool;
// struct_monitor_mode: used as return type of extern fn; use [64]u8 as freestanding stub
const struct_monitor_mode = arcan.struct_monitor_mode;
extern fn platform_video_dimensions() struct_monitor_mode;

extern fn sqrtf(x: f32) f32;
extern fn cosf(x: f32) f32;
extern fn sinf(x: f32) f32;
extern fn rand() c_int;

// pthread types and functions
// pthread_mutex_t: glibc=40 bytes on aarch64, musl=48 bytes; use 48 for freestanding
const pthread_mutex_t = [48]u8;
const pthread_t = usize;
extern fn pthread_mutex_init(mutex: *pthread_mutex_t, attr: ?*const anyopaque) c_int;
extern fn pthread_mutex_lock(mutex: *pthread_mutex_t) c_int;
extern fn pthread_mutex_unlock(mutex: *pthread_mutex_t) c_int;
extern fn pthread_mutex_destroy(mutex: *pthread_mutex_t) c_int;
extern fn pthread_join(thread: pthread_t, retval: ?*?*anyopaque) c_int;

// Extern global
const struct_arcan_video_display = arcan.struct_arcan_video_display;
extern var arcan_video_display: struct_arcan_video_display;

// M_PI constants
const M_PI: f32 = 3.14159265358979323846;
const M_PI_2: f32 = 1.57079632679489661923;

// RAND_MAX
const RAND_MAX: f32 = 2147483647.0;

// Internal struct definitions

const camtag_data = extern struct {
    projection: [16]f32 align(16),
    mvm: [16]f32 align(16),
    wpos: vector align(16),
    near: f32,
    far: f32,
    line_width: f32,
    flags: c_int,
    vrref: ?*arcan_vr_ctx,
};

const geometry = extern struct {
    nmaps: usize,
    program: agp_shader_id,

    store: agp_mesh_store,

    complete: bool,
    threaded: bool,

    worker: pthread_t,
    next: ?*geometry,
};

const arcan_3dmodel = extern struct {
    lock: pthread_mutex_t,
    work_count: c_int,

    geom: ?*geometry,

    // AA-BB
    bbmin: vector,
    bbmax: vector,
    radius: f32,

    flags: extern struct {
        debug: bool,
        complete: bool,
        infinite: bool,
    },

    deferred: extern struct {
        scale: bool,
        swizzle: bool,
        orient: bool,
        orientf: vector,
    },

    vrref: ?*arcan_vr_ctx,
    parent: ?*arcan_vobject,
};

// Static helper functions

fn build_plane(
    min: point,
    max: point,
    step: point,
    verts_out: *?[*]f32,
    indices_out: *?[*]c_uint,
    txcos_out: *?[*]f32,
    nverts: *usize,
    nindices: *usize,
    vertical: bool,
) void {
    const delta = point{
        .x = max.x - min.x,
        .y = max.y,
        .z = max.z - min.z,
    };

    const nx: usize = @intFromFloat(@ceil(delta.x / step.x));
    const nz: usize = @intFromFloat(@ceil(delta.z / step.z));

    nverts.* = nx * nz;
    const verts: [*]f32 = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(f32) * nverts.* * 3,
        ARCAN_MEM_MODELDATA,
        0,
        ARCAN_MEMALIGN_PAGE,
    )));
    verts_out.* = verts;

    const txcos: [*]f32 = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(f32) * nverts.* * 2,
        ARCAN_MEM_MODELDATA,
        0,
        ARCAN_MEMALIGN_PAGE,
    )));
    txcos_out.* = txcos;

    var vofs: usize = 0;
    var tofs: usize = 0;
    for (0..nx) |x| {
        for (0..nz) |z| {
            verts[vofs] = min.x + @as(f32, @floatFromInt(x)) * step.x;
            vofs += 1;
            if (vertical) {
                verts[vofs] = min.z + @as(f32, @floatFromInt(z)) * step.z;
                vofs += 1;
                verts[vofs] = min.y;
                vofs += 1;
            } else {
                verts[vofs] = min.y;
                vofs += 1;
                verts[vofs] = min.z + @as(f32, @floatFromInt(z)) * step.z;
                vofs += 1;
            }
            txcos[tofs] = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(nx - 1));
            tofs += 1;
            txcos[tofs] = @as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(nz - 1));
            tofs += 1;
        }
    }

    vofs = 0;
    const idx: [*]c_uint = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(c_uint) * (nx - 1) * (nz - 1) * 6,
        ARCAN_MEM_MODELDATA,
        0,
        ARCAN_MEMALIGN_PAGE,
    )));
    indices_out.* = idx;

    for (0..nx - 1) |x| {
        for (0..nz - 1) |z| {
            idx[vofs] = @intCast((x + 1) * nz + (z + 1));
            vofs += 1;
            idx[vofs] = @intCast(x * nz + (z + 1));
            vofs += 1;
            idx[vofs] = @intCast(x * nz + z);
            vofs += 1;

            idx[vofs] = @intCast((x + 1) * nz + z);
            vofs += 1;
            idx[vofs] = @intCast((x + 1) * nz + (z + 1));
            vofs += 1;
            idx[vofs] = @intCast(x * nz + z);
            vofs += 1;
        }
    }

    nindices.* = vofs;
}

fn freemodel(src_opt: ?*arcan_3dmodel) void {
    const src = src_opt orelse return;

    if (src.vrref) |vrref| {
        const cellid = if (src.parent) |p| p.cellid else ARCAN_EID;
        _ = arcan_vr_release(vrref, cellid);
        src.vrref = null;
    }

    // always make sure the model is loaded before freeing
    var geom = src.geom;
    while (geom) |g| {
        if (g.threaded) {
            _ = pthread_join(g.worker, null);
            g.threaded = false;
        }
        geom = g.next;
    }

    geom = src.geom;

    // special case: shared buffer between main and sub-geom
    const first_geom = geom orelse return;
    const base: usize = if (first_geom.store.shared_buffer) |sb|
        @intFromPtr(sb)
    else if (first_geom.store.verts) |v|
        @intFromPtr(v)
    else
        0;

    // save the base geometry slot for last
    geom = first_geom.next;
    while (geom) |g| {
        const base2: usize = if (g.store.shared_buffer) |sb|
            @intFromPtr(sb)
        else if (g.store.verts) |v|
            @intFromPtr(v)
        else
            0;

        // subgeom is its own geometry
        if (base2 != base)
            agp_drop_mesh(&g.store);

        // delink from list and free
        const last = g;
        geom = g.next;
        last.next = null;
        arcan_mem_free(@ptrCast(last));
    }

    agp_drop_mesh(&first_geom.store);
    arcan_mem_free(@ptrCast(src.geom));
    _ = pthread_mutex_destroy(&src.lock);
    arcan_mem_free(@ptrCast(src));
}

fn push_deferred(model: *arcan_3dmodel) void {
    if (model.work_count > 0)
        return;

    if (!model.flags.complete)
        return;

    if (model.deferred.scale) {
        _ = arcan_3d_scalevertices(model.parent.?.cellid);
        model.deferred.scale = false;
    }

    if (model.deferred.swizzle) {
        _ = arcan_3d_swizzlemodel(model.parent.?.cellid);
        model.deferred.swizzle = false;
    }

    if (model.deferred.orient) {
        _ = arcan_3d_baseorient(
            model.parent.?.cellid,
            model.deferred.orientf.x,
            model.deferred.orientf.y,
            model.deferred.orientf.z,
        );
        model.deferred.orient = false;
    }
}

fn rendermodel(
    vobj: *arcan_vobject,
    src: *arcan_3dmodel,
    baseprog: agp_shader_id,
    props: surface_properties,
    view: *[16]f32,
    flags: c_int,
) void {
    if (props.opa < EPSILON or !src.flags.complete or src.work_count > 0)
        return;

    // transform order: scale
    var scale_m align(16) = [16]f32{
        props.scale.x, 0.0, 0.0, 0.0,
        0.0,           props.scale.y, 0.0, 0.0,
        0.0,           0.0, props.scale.z, 0.0,
        0.0,           0.0, 0.0,           1.0,
    };

    const origo = vectorFromC(vobj.origo_ofs);
    const ox = origo.x;
    const oy = origo.y;
    const oz = origo.z;

    // point-translation to origo_ofs
    translate_matrix(&scale_m, ox, oy, oz);

    // rotate
    var orient: [16]f32 align(16) = undefined;
    _ = matr_quatf(props.rotation.quaternion, &orient);
    var model_m: [16]f32 align(16) = undefined;
    multiply_matrix(&model_m, &orient, &scale_m);

    // object translation
    translate_matrix(&model_m, props.position.x - ox, props.position.y - oy, props.position.z - oz);

    var out: [16]f32 align(16) = undefined;
    multiply_matrix(&out, view, &model_m);

    _ = agp_shader_envv(MODELVIEW_MATR, @ptrCast(&out), @sizeOf(f32) * 16);
    var opa = props.opa;
    _ = agp_shader_envv(OBJ_OPACITY, @ptrCast(&opa), @sizeOf(f32));

    var base_geom = src.geom;

    agp_blendstate(@intCast(vobj.blendmode));
    var fset_ofs: usize = if (vobj.frameset) |fs| fs.index else 0;

    while (base_geom) |bg| {
        _ = agp_shader_activate(if (bg.program > 0) bg.program else baseprog);

        if (vobj.frameset == null) {
            agp_activate_vstore(vobj.vstore);
        } else {
            const frameset = vobj.frameset.?;
            if (bg.nmaps == 1) {
                agp_activate_vstore(frameset.frames[fset_ofs].frame);
                fset_ofs = (fset_ofs + 1) % frameset.n_frames;
            } else if (bg.nmaps > 1) {
                // VLA: use a stack buffer up to reasonable limit
                var backing_buf: [64]?*agp_vstore = undefined;
                const nmaps = @min(bg.nmaps, 64);
                for (0..nmaps) |i| {
                    backing_buf[i] = frameset.frames[fset_ofs].frame;
                    fset_ofs = (fset_ofs + 1) % frameset.n_frames;
                }
                agp_activate_vstore_multi(&backing_buf, nmaps);
            }
            // else nmaps == 0: do nothing
        }

        _ = agp_shader_envv(MODELVIEW_MATR, @ptrCast(&out), @sizeOf(f32) * 16);
        agp_submit_mesh(&bg.store, flags);
        base_geom = bg.next;
    }
}

// arcan_ffunc_3dobj

export fn arcan_ffunc_3dobj(
    cmd: c_int,
    buf: [*c]av_pixel,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: arcan_vobj_id,
) c_int {
    if (is_freestanding) return 0;
    _ = buf;
    _ = buf_sz;
    _ = width;
    _ = height;
    _ = mode;

    if ((state.tag == ARCAN_TAG_3DOBJ or state.tag == ARCAN_TAG_3DCAMERA) and state.ptr != null) {
        switch (cmd) {
            FFUNC_TICK => {},
            FFUNC_DESTROY => {
                if (state.tag == ARCAN_TAG_3DOBJ) {
                    freemodel(@ptrCast(@alignCast(state.ptr)));
                } else {
                    const camobj = arcan_video_getobject(srcid);
                    const camera: *camtag_data = @ptrCast(@alignCast(state.ptr));
                    if (camera.vrref) |vrref| {
                        _ = arcan_vr_release(vrref, camobj.?.cellid);
                        camera.vrref = null;
                    }
                    arcan_mem_free(state.ptr);
                    if (camobj) |co| {
                        co.feed.state.ptr = null;
                    }
                }
            },
            else => {},
        }
    }

    return 0;
}

// process_scene_infinite (static)

fn process_scene_infinite(
    cell: ?*arcan_vobject_litem,
    lerp: f32,
    view: *[16]f32,
    flags: c_int,
) ?*arcan_vobject_litem {
    var current = cell;
    const rtgt = arcan_vint_current_rt();
    var min_order: isize = 0;
    var max_order: isize = 65536;
    if (rtgt) |rt| {
        min_order = @intCast(rt.min_order);
        max_order = @intCast(rt.max_order);
    }

    while (current) |cur| {
        const cvo = cur.elem;
        const obj3d: *arcan_3dmodel = @ptrCast(@alignCast(cvo.*.feed.state.ptr));

        if (cvo.*.order >= 0 or obj3d.flags.infinite == false)
            break;

        const abs_o: isize = cvo.*.order * -1;
        if (abs_o < min_order) {
            current = cur.next;
            continue;
        }

        if (abs_o > max_order)
            break;

        var dprops: surface_properties = undefined;
        arcan_resolve_vidprop(cvo, lerp, &dprops);
        rendermodel(cvo, obj3d, cvo.*.program, dprops, view, flags | MESH_FACING_NODEPTH);

        current = cur.next;
    }

    return current;
}

fn process_scene_normal(
    cell: ?*arcan_vobject_litem,
    lerp: f32,
    modelview: *[16]f32,
    flags: c_int,
) void {
    var current = cell;
    const rtgt = arcan_vint_current_rt();
    var min_order: isize = 0;
    var max_order: isize = 65536;
    if (rtgt) |rt| {
        min_order = @intCast(rt.min_order);
        max_order = @intCast(rt.max_order);
    }

    while (current) |cur| {
        const cvo = cur.elem;

        // non-negative => 2D part of the pipeline
        if (cvo.*.order >= 0)
            break;

        const abs_o: isize = cvo.*.order * -1;
        if (abs_o < min_order) {
            current = cur.next;
            continue;
        }

        if (abs_o > max_order)
            break;

        var dprops: surface_properties = undefined;
        const model: *arcan_3dmodel = @ptrCast(@alignCast(cvo.*.feed.state.ptr));
        if (model.vrref != null) {
            dprops = @bitCast(cvo.*.current);
        } else {
            arcan_resolve_vidprop(cvo, lerp, &dprops);
        }
        rendermodel(cvo, model, cvo.*.program, dprops, modelview, flags);

        current = cur.next;
    }
}

// Exported functions

export fn arcan_3d_bindvr(id: arcan_vobj_id, vrref: ?*arcan_vr_ctx) arcan_errc {
    if (is_freestanding) return ARCAN_ERRC_NO_SUCH_OBJECT;
    const model = arcan_video_getobject(id) orelse return ARCAN_ERRC_NO_SUCH_OBJECT;

    if (model.feed.state.tag == ARCAN_TAG_3DOBJ) {
        const m3d: *arcan_3dmodel = @ptrCast(@alignCast(model.feed.state.ptr));
        m3d.vrref = vrref;
        return ARCAN_OK;
    } else if (model.feed.state.tag == ARCAN_TAG_3DCAMERA) {
        const camera: *camtag_data = @ptrCast(@alignCast(model.feed.state.ptr));
        camera.vrref = vrref;
        return ARCAN_OK;
    } else {
        return ARCAN_ERRC_UNACCEPTED_STATE;
    }
}

export fn arcan_3d_viewray(
    camtag: arcan_vobj_id,
    x: c_int,
    y: c_int,
    fract: f32,
    pos: *vector,
    ang: *vector,
) void {
    if (is_freestanding) return;
    _ = fract;
    const camobj = arcan_video_getobject(camtag) orelse return;
    if (camobj.feed.state.tag != ARCAN_TAG_3DCAMERA)
        return;
    const camera: *camtag_data = @ptrCast(@alignCast(camobj.feed.state.ptr));
    const mode = platform_video_dimensions();

    var z: f32 = undefined;
    dev_coord(&pos.x, &pos.y, &z, x, y, @intCast(mode.width), @intCast(mode.height), camera.near, camera.far);

    var p1 = unproject_matrix(pos.x, pos.y, 0.0, &camera.mvm, &camera.projection);
    var p2 = unproject_matrix(pos.x, pos.y, 1.0, &camera.mvm, &camera.projection);

    p1.z = camera.wpos.z + camera.near;
    p2.z = camera.wpos.z + camera.far;

    pos.* = p1;
    ang.* = norm_vector(sub_vector(p2, p1));
}

export fn arcan_3d_obj_bb_intersect(
    cam: arcan_vobj_id,
    obj: arcan_vobj_id,
    x: c_int,
    y: c_int,
) bool {
    if (is_freestanding) return false;
    const model = arcan_video_getobject(obj) orelse return false;
    if (model.feed.state.tag != ARCAN_TAG_3DOBJ)
        return false;

    var ray_pos: vector = undefined;
    var ray_dir: vector = undefined;

    const rad = (@as(*arcan_3dmodel, @ptrCast(@alignCast(model.feed.state.ptr)))).radius;
    arcan_3d_viewray(cam, x, y, arcan_video_display.c_lerp, &ray_pos, &ray_dir);

    var d1: f32 = undefined;
    var d2: f32 = undefined;

    var cur_pos = vectorFromC(model.current.position);
    return ray_sphere(&ray_pos, &ray_dir, &cur_pos, rad, &d1, &d2);
}

export fn arcan_3d_refresh(
    camtag: arcan_vobj_id,
    cell: ?*arcan_vobject_litem,
    fract: f32,
) ?*arcan_vobject_litem {
    if (is_freestanding) return null;
    const camobj = arcan_video_getobject(camtag) orelse return cell;

    if (camobj.feed.state.tag != ARCAN_TAG_3DCAMERA)
        return cell;

    const camera: *camtag_data = @ptrCast(@alignCast(camobj.feed.state.ptr));
    var matr: [16]f32 align(16) = undefined;
    var dmatr: [16]f32 align(16) = undefined;
    var omatr: [16]f32 align(16) = undefined;

    agp_pipeline_hint(PIPELINE_3D);
    agp_render_options(.{ .line_width = @intFromFloat(camera.line_width) });

    var dprop: surface_properties = undefined;
    arcan_resolve_vidprop(camobj, fract, &dprop);
    if (camera.vrref != null) {
        dprop.rotation = @bitCast(camobj.current.rotation);
    }

    _ = agp_shader_activate(agp_default_shader(BASIC_3D));
    _ = agp_shader_envv(PROJECTION_MATR, @ptrCast(&camera.projection), @sizeOf(f32) * 16);

    // scale
    identity_matrix(&matr);
    scale_matrix(&matr, dprop.scale.x, dprop.scale.y, dprop.scale.z);

    // rotate
    _ = matr_quatf(norm_quat(dprop.rotation.quaternion), &omatr);
    multiply_matrix(&dmatr, &matr, &omatr);

    var result_cell = cell;

    if (cell) |c_cell| {
        const obj3d: *arcan_3dmodel = @ptrCast(@alignCast(c_cell.elem.*.feed.state.ptr));

        // "infinite geometry" (skybox)
        if (obj3d.flags.infinite)
            result_cell = process_scene_infinite(cell, fract, &dmatr, camera.flags);
    }

    // object translate
    const cdata: *camtag_data = @ptrCast(@alignCast(camobj.feed.state.ptr));
    cdata.wpos = dprop.position;
    translate_matrix(&dmatr, dprop.position.x, dprop.position.y, dprop.position.z);
    @memcpy(&cdata.mvm, &dmatr);

    process_scene_normal(result_cell, fract, &dmatr, camera.flags);

    return result_cell;
}

fn minmax_verts(minp: *vector, maxp: *vector, verts: [*]const f32, nverts: usize) void {
    var i: usize = 0;
    while (i < nverts * 3) : (i += 3) {
        const ax = verts[i];
        const ay = verts[i + 1];
        const az = verts[i + 2];
        if (ax < minp.x) minp.x = ax;
        if (ay < minp.y) minp.y = ay;
        if (az < minp.z) minp.z = az;
        if (ax > maxp.x) maxp.x = ax;
        if (ay > maxp.y) maxp.y = ay;
        if (az > maxp.z) maxp.z = az;
    }
}

export fn arcan_3d_swizzlemodel(dst: arcan_vobj_id) arcan_errc {
    if (is_freestanding) return ARCAN_ERRC_NO_SUCH_OBJECT;
    const vobj = arcan_video_getobject(dst) orelse return ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.feed.state.tag != ARCAN_TAG_3DOBJ)
        return ARCAN_ERRC_UNACCEPTED_STATE;

    const model: *arcan_3dmodel = @ptrCast(@alignCast(vobj.feed.state.ptr));
    _ = pthread_mutex_lock(&model.lock);
    if (model.work_count != 0 or !model.flags.complete) {
        model.deferred.swizzle = true;
        _ = pthread_mutex_unlock(&model.lock);
        return ARCAN_OK;
    }

    var curr = model.geom;
    while (curr) |g| {
        if (g.store.indices != null) {
            const indices_ptr = g.store.indices.?;
            var i: usize = 0;
            while (i < g.store.n_indices) : (i += 3) {
                const iv = indices_ptr[i];
                indices_ptr[i] = indices_ptr[i + 2];
                indices_ptr[i + 2] = iv;
            }
        } else {
            const verts_ptr = g.store.verts.?;
            var i: usize = 0;
            while (i < g.store.n_vertices * 9) : (i += 9) {
                const v1x = verts_ptr[i];
                const v1y = verts_ptr[i + 1];
                const v1z = verts_ptr[i + 2];
                const v3x = verts_ptr[i + 6];
                const v3y = verts_ptr[i + 7];
                const v3z = verts_ptr[i + 8];
                verts_ptr[i] = v3x;
                verts_ptr[i + 1] = v3y;
                verts_ptr[i + 2] = v3z;
                verts_ptr[i + 6] = v1x;
                verts_ptr[i + 7] = v1y;
                verts_ptr[i + 8] = v1z;
            }
        }

        curr = g.next;
    }

    _ = pthread_mutex_unlock(&model.lock);
    return ARCAN_ERRC_NO_SUCH_OBJECT; // C code returns rv which was initialized to NO_SUCH_OBJECT
}

export fn arcan_3d_pointcloud(count_arg: usize, nmaps: usize) arcan_vobj_id {
    if (is_freestanding) return ARCAN_EID;
    if (count_arg == 0)
        return ARCAN_EID;

    var state = vfunc_state{ .tag = ARCAN_TAG_3DOBJ, .ptr = null };
    const empty = std.mem.zeroes(img_cons);
    const rv = arcan_video_addfobject(FFUNC_3DOBJ, state, empty, 1);

    if (rv == ARCAN_EID)
        return ARCAN_EID;

    const newmodel: *arcan_3dmodel = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(arcan_3dmodel),
        ARCAN_MEM_VTAG,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    )));
    state.ptr = @ptrCast(newmodel);
    _ = arcan_video_alterfeed(rv, FFUNC_3DOBJ, state);
    _ = pthread_mutex_init(&newmodel.lock, null);

    newmodel.geom = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(geometry),
        ARCAN_MEM_VTAG,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    )));
    const geom = newmodel.geom.?;
    geom.store.n_vertices = count_arg;
    geom.store.vertex_size = 3;
    geom.nmaps = nmaps;
    geom.store.verts = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(f32) * count_arg * 3,
        ARCAN_MEM_MODELDATA,
        0,
        ARCAN_MEMALIGN_PAGE,
    )));
    geom.store.txcos = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(f32) * count_arg * 2,
        ARCAN_MEM_MODELDATA,
        0,
        ARCAN_MEMALIGN_PAGE,
    )));

    const step = 2.0 / sqrtf(@floatFromInt(count_arg));

    var cz: f32 = -1;
    var cx: f32 = -1;
    const dbuf = geom.store.verts.?;
    const tbuf = geom.store.txcos.?;

    var count = count_arg;
    var di: usize = 0;
    var ti: usize = 0;

    // evenly distribute texture coordinates, randomly distribute vertices
    while (count > 0) : (count -= 1) {
        cx = cx + step;
        if (cx > 1) {
            cx = -1;
            cz = cz + step;
        }

        const rx: f32 = 1.0 - @as(f32, @floatFromInt(rand())) / (RAND_MAX / 2.0);
        const ry: f32 = 1.0 - @as(f32, @floatFromInt(rand())) / (RAND_MAX / 2.0);
        const rz: f32 = 1.0 - @as(f32, @floatFromInt(rand())) / (RAND_MAX / 2.0);

        dbuf[di] = rx;
        di += 1;
        dbuf[di] = ry;
        di += 1;
        dbuf[di] = rz;
        di += 1;
        tbuf[ti] = (cx + 1.0) / 2.0;
        ti += 1;
        tbuf[ti] = (cz + 1.0) / 2.0;
        ti += 1;
    }

    newmodel.radius = 1.0;

    newmodel.bbmin = vector{ .x = -1, .y = -1, .z = -1 };
    newmodel.bbmax = vector{ .x = 1, .y = 1, .z = 1 };
    newmodel.flags.complete = true;
    newmodel.flags.debug = true;
    geom.nmaps = nmaps;
    geom.store.type = AGP_MESH_POINTCLOUD;

    return rv;
}

export fn arcan_3d_buildcylinder(
    r: f32,
    hh: f32,
    steps: usize,
    nmaps: usize,
    fill_mode: c_int,
) arcan_vobj_id {
    if (is_freestanding) return ARCAN_EID;
    var state = vfunc_state{ .tag = ARCAN_TAG_3DOBJ, .ptr = null };
    const empty = std.mem.zeroes(img_cons);

    if (hh < EPSILON or steps < 1)
        return ARCAN_EID;

    const rv = arcan_video_addfobject(FFUNC_3DOBJ, state, empty, 1);
    if (rv == ARCAN_EID)
        return rv;

    // control structure
    const newmodel: *arcan_3dmodel = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(arcan_3dmodel),
        ARCAN_MEM_VTAG,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    )));
    state.ptr = @ptrCast(newmodel);
    _ = arcan_video_alterfeed(rv, FFUNC_3DOBJ, state);
    _ = pthread_mutex_init(&newmodel.lock, null);
    _ = arcan_video_allocframes(rv, 1, ARCAN_FRAMESET_SPLIT);

    // metadata / geometry source
    newmodel.geom = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(geometry),
        ARCAN_MEM_VTAG,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    )));
    const geom = newmodel.geom.?;

    // total number of verts, normals, textures and indices
    const caps: usize = if (fill_mode > CYLINDER_FILL_HALF) @as(usize, 1) else 0;
    const n_verts = 3 * (steps * 3 + caps * steps * 2);
    const n_txcos = 3 * (steps * 2 + caps * steps * 2);
    const n_normals = 3 * (steps * 3 + caps * steps * 2);
    const n_indices = 1 * (steps * 6 + caps * steps * 6);
    const buf_sz = @sizeOf(f32) * (n_verts + n_normals + n_txcos) + n_indices * @sizeOf(c_uint);

    // build our storage buffers
    const dbuf: [*]f32 = @ptrCast(@alignCast(arcan_alloc_mem(buf_sz, ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_SIMD)));
    var vp_i: usize = 0;
    const np_base: usize = n_verts;
    var np_i: usize = 0;
    const tp_base: usize = n_txcos + n_verts;
    var tp_i: usize = 0;
    const ip_base: usize = n_verts + n_txcos + n_normals;
    var ip_i: usize = 0;

    // map it all into our model
    geom.store.vertex_size = 3;
    geom.store.type = AGP_MESH_TRISOUP;
    geom.store.shared_buffer_sz = buf_sz;
    geom.store.shared_buffer = @ptrCast(dbuf);
    geom.store.verts = dbuf;
    geom.store.txcos = dbuf + tp_base;
    geom.store.normals = dbuf + np_base;
    const ip_as_float: [*]f32 = dbuf + ip_base;
    geom.store.indices = @ptrCast(@alignCast(ip_as_float));
    geom.store.n_indices = n_indices;
    geom.store.n_vertices = n_verts / 3;
    geom.nmaps = nmaps;
    geom.complete = true;
    newmodel.radius = if (r > (2.0 * hh)) r else 2.0 * hh;
    newmodel.bbmin = vector{ .x = -r, .y = -hh, .z = -r };
    newmodel.bbmax = vector{ .x = r, .y = hh, .z = r };
    newmodel.flags.complete = true;

    // pass one, base data
    var step_sz: f32 = 2.0 * M_PI / @as(f32, @floatFromInt(steps));
    var txf: f32 = 2.0 * M_PI;

    if (fill_mode == CYLINDER_FILL_HALF or fill_mode == CYLINDER_FILL_HALF_CAPS) {
        step_sz = M_PI / @as(f32, @floatFromInt(steps));
        txf = M_PI;
    }

    for (0..steps + 1) |i| {
        const p = @as(f32, @floatFromInt(i)) * step_sz;
        const x = cosf(p);
        const z = sinf(p);

        // top
        dbuf[vp_i] = r * x;
        vp_i += 1;
        dbuf[vp_i] = hh;
        vp_i += 1;
        dbuf[vp_i] = r * z;
        vp_i += 1;
        dbuf[tp_base + tp_i] = p / txf;
        tp_i += 1;
        dbuf[tp_base + tp_i] = 0;
        tp_i += 1;
        dbuf[np_base + np_i] = x;
        np_i += 1;
        dbuf[np_base + np_i] = 0;
        np_i += 1;
        dbuf[np_base + np_i] = z;
        np_i += 1;

        // bottom
        dbuf[vp_i] = r * x;
        vp_i += 1;
        dbuf[vp_i] = -hh;
        vp_i += 1;
        dbuf[vp_i] = r * z;
        vp_i += 1;
        dbuf[tp_base + tp_i] = p / txf;
        tp_i += 1;
        dbuf[tp_base + tp_i] = 1;
        tp_i += 1;
        dbuf[np_base + np_i] = x;
        np_i += 1;
        dbuf[np_base + np_i] = 0;
        np_i += 1;
        dbuf[np_base + np_i] = z;
        np_i += 1;
    }

    // pass two, index buffer
    const ip_ptr: [*]c_uint = @ptrCast(@alignCast(ip_as_float));
    var ic: usize = 0;
    var ofs: isize = 0;

    if (fill_mode == CYLINDER_FILL_HALF or fill_mode == CYLINDER_FILL_HALF_CAPS)
        ofs = -1;

    const loop_end: usize = if (ofs < 0) steps - 1 else steps;
    for (0..loop_end) |i| {
        const idx2: c_uint = @intCast(i * 2 + 1);
        const idx3: c_uint = @intCast(i * 2 + 2);
        const idx1: c_uint = @intCast(i * 2 + 0);
        const idx4: c_uint = @intCast(i * 2 + 3);
        ic += 6;
        ip_ptr[ip_i] = idx2;
        ip_i += 1;
        ip_ptr[ip_i] = idx3;
        ip_i += 1;
        ip_ptr[ip_i] = idx1;
        ip_i += 1;
        ip_ptr[ip_i] = idx4;
        ip_i += 1;
        ip_ptr[ip_i] = idx3;
        ip_i += 1;
        ip_ptr[ip_i] = idx2;
        ip_i += 1;
    }

    geom.store.n_indices = ic;

    // pass three, endcaps
    if (caps > 0) {
        dbuf[vp_i] = 0;
        vp_i += 1;
        dbuf[vp_i] = hh;
        vp_i += 1;
        dbuf[vp_i] = 0;
        vp_i += 1;
        dbuf[tp_base + tp_i] = 0;
        tp_i += 1;
        dbuf[tp_base + tp_i] = 0;
        tp_i += 1;
        dbuf[np_base + np_i] = 0;
        np_i += 1;
        dbuf[np_base + np_i] = 1;
        np_i += 1;
        dbuf[np_base + np_i] = 0;
        np_i += 1;
        dbuf[vp_i] = 0;
        vp_i += 1;
        dbuf[vp_i] = -hh;
        vp_i += 1;
        dbuf[vp_i] = 0;
        dbuf[tp_base + tp_i] = 0;
        tp_i += 1;
        dbuf[tp_base + tp_i] = 0;
        dbuf[np_base + np_i] = 0;
        np_i += 1;
        dbuf[np_base + np_i] = 1;
        np_i += 1;
        dbuf[np_base + np_i] = 0;
    }

    return rv;
}

export fn arcan_3d_buildsphere(
    r: f32,
    l_arg: c_uint,
    m_arg: c_uint,
    hemi: bool,
    nmaps: usize,
) arcan_vobj_id {
    if (is_freestanding) return ARCAN_EID;
    var state = vfunc_state{ .tag = ARCAN_TAG_3DOBJ, .ptr = null };
    const empty = std.mem.zeroes(img_cons);

    const l: usize = @intCast(l_arg);
    const m: usize = @intCast(m_arg);

    if (l <= 1 or m <= 1)
        return ARCAN_EID;

    const rv = arcan_video_addfobject(FFUNC_3DOBJ, state, empty, 1);
    if (rv == ARCAN_EID)
        return rv;

    const newmodel: *arcan_3dmodel = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(arcan_3dmodel),
        ARCAN_MEM_VTAG,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    )));
    state.ptr = @ptrCast(newmodel);
    _ = arcan_video_alterfeed(rv, FFUNC_3DOBJ, state);
    _ = pthread_mutex_init(&newmodel.lock, null);
    _ = arcan_video_allocframes(rv, 1, ARCAN_FRAMESET_SPLIT);

    // total number of verts, normals, textures and indices
    const nv = l * m * 3;
    const nn = l * m * 3;
    const nt = l * m * 2;
    const ni = (l - 1) * (m - 1) * 6;
    const buf_sz = (nv + nn + nt) * @sizeOf(f32) + ni * @sizeOf(c_uint);

    // build our storage buffers
    const dbuf: [*]f32 = @ptrCast(@alignCast(arcan_alloc_mem(buf_sz, ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_SIMD)));

    // map it all into our model
    newmodel.geom = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(geometry),
        ARCAN_MEM_VTAG,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    )));
    const geom = newmodel.geom.?;
    geom.store.vertex_size = 3;
    geom.store.type = AGP_MESH_TRISOUP;
    geom.store.shared_buffer_sz = buf_sz;
    geom.store.shared_buffer = @ptrCast(dbuf);
    geom.store.verts = dbuf;
    geom.store.normals = dbuf + nv;
    geom.store.txcos = dbuf + nv + nn;
    const ip_as_float: [*]f32 = dbuf + nv + nn + nt;
    geom.store.indices = @ptrCast(@alignCast(ip_as_float));
    geom.store.n_indices = ni;
    geom.store.n_vertices = nv / 3;
    geom.complete = true;
    newmodel.radius = r;
    geom.nmaps = nmaps;
    newmodel.flags.complete = true;

    // pass one, base data
    const step_l: f32 = 1.0 / @as(f32, @floatFromInt(l - 1));
    const step_m: f32 = 1.0 / @as(f32, @floatFromInt(m - 1));
    var hcons: f32 = undefined;
    var yofs: f32 = undefined;
    if (hemi) {
        hcons = 0;
        yofs = -0.5 * r;
    } else {
        hcons = -M_PI_2;
        yofs = 0.0;
    }

    var vi: usize = 0;
    var nni: usize = nv; // normals offset
    var ti: usize = nv + nn; // txcos offset

    for (0..l) |L| {
        for (0..m) |M| {
            const Lf: f32 = @floatFromInt(L);
            const Mf: f32 = @floatFromInt(M);
            const y_val = sinf(hcons + M_PI * Lf * step_l) + yofs;
            const x_val = cosf(2.0 * M_PI * Mf * step_m) * sinf(M_PI * Lf * step_l);
            const z_val = sinf(2.0 * M_PI * Mf * step_m) * sinf(M_PI * Lf * step_l);
            dbuf[ti] = Mf * step_m;
            ti += 1;
            dbuf[ti] = 1.0 - Lf * step_l;
            ti += 1;
            dbuf[vi] = x_val * r;
            vi += 1;
            dbuf[vi] = y_val * r;
            vi += 1;
            dbuf[vi] = z_val * r;
            vi += 1;
            dbuf[nni] = x_val;
            nni += 1;
            dbuf[nni] = y_val;
            nni += 1;
            dbuf[nni] = z_val;
            nni += 1;
        }
    }

    // pass two, indexing primitives
    const ip_ptr: [*]c_uint = @ptrCast(@alignCast(ip_as_float));
    var ii: usize = 0;

    for (0..l - 1) |L| {
        for (0..m - 1) |M| {
            const idx1: c_uint = @intCast(L * m + M);
            const idx2: c_uint = @intCast(L * m + M + 1);
            const idx3: c_uint = @intCast((L + 1) * m + M + 1);
            const idx4: c_uint = @intCast((L + 1) * m + M);
            ip_ptr[ii] = idx1;
            ii += 1;
            ip_ptr[ii] = idx2;
            ii += 1;
            ip_ptr[ii] = idx3;
            ii += 1;
            ip_ptr[ii] = idx1;
            ii += 1;
            ip_ptr[ii] = idx3;
            ii += 1;
            ip_ptr[ii] = idx4;
            ii += 1;
        }
    }

    return rv;
}

export fn arcan_3d_buildbox(
    w: f32,
    h: f32,
    d: f32,
    nmaps: usize,
    s: bool,
) arcan_vobj_id {
    if (is_freestanding) return ARCAN_EID;
    var state = vfunc_state{ .tag = ARCAN_TAG_3DOBJ, .ptr = null };
    const empty = std.mem.zeroes(img_cons);
    const rv = arcan_video_addfobject(FFUNC_3DOBJ, state, empty, 1);

    if (rv == ARCAN_EID)
        return rv;

    // wait with setting the full model until we know we have a fobject
    const newmodel: *arcan_3dmodel = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(arcan_3dmodel),
        ARCAN_MEM_VTAG,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    )));
    state.ptr = @ptrCast(newmodel);
    _ = arcan_video_alterfeed(rv, FFUNC_3DOBJ, state);
    _ = pthread_mutex_init(&newmodel.lock, null);
    _ = arcan_video_allocframes(rv, 1, ARCAN_FRAMESET_SPLIT);

    // winding order: clockwise
    const verts = [_]f32{
        -w, h, -d, // TOP
        -w, h, d,
        w,  h, d,
        w,  h, -d,
        -w, h, d, // LEFT
        -w, -h, d,
        -w, -h, -d,
        -w, h, -d,
        w, h, d, // RIGHT
        w, -h, d,
        w, -h, -d,
        w, h, -d,
        w, h, d, // FRONT
        w, -h, d,
        -w, -h, d,
        -w, h, d,
        w, h, -d, // BACK
        w, -h, -d,
        -w, -h, -d,
        -w, h, -d,
        -w, -h, -d, // BOTTOM
        -w, -h, d,
        w, -h, d,
        w, -h, -d,
    };

    const txcos = [_]f32{
        0, 1, // TOP
        0, 0,
        1, 0,
        1, 1,
        0, 0, // LEFT
        0, 1,
        1, 1,
        1, 0,
        1, 0, // RIGHT
        1, 1,
        0, 1,
        0, 0,
        0, 0, // FRONT
        0, 1,
        1, 1,
        1, 0,
        1, 0, // BACK
        1, 1,
        0, 1,
        0, 0,
        0, 0, // BOTTOM
        0, 1,
        1, 1,
        1, 0,
    };

    const normals = [_]f32{
        0,  1,  0, // TOP
        0,  1,  0,
        0,  1,  0,
        0,  1,  0,
        -1, 0,  0, // LEFT
        -1, 0,  0,
        -1, 0,  0,
        -1, 0,  0,
        1,  0,  0, // RIGHT
        1,  0,  0,
        1,  0,  0,
        1,  0,  0,
        0,  0,  -1, // FRONT
        0,  0,  -1,
        0,  0,  -1,
        0,  0,  -1,
        0,  0,  1, // BACK
        0,  0,  1,
        0,  0,  1,
        0,  0,  1,
        0,  -1, 0, // BOTTOM
        0,  -1, 0,
        0,  -1, 0,
        0,  -1, 0,
    };

    const indices = [_]c_uint{
        10, 9, 8, // right
        11, 10, 8,
        6, 4, 5, // left
        7, 4, 6,
        2, 1, 0, // top
        3, 2, 0,
        22, 20, 21, // bottom
        23, 20, 22,
        18, 17, 16, // back
        19, 18, 16,
        14, 12, 13, // front
        12, 14, 15,
    };

    const bbmin = vector{ .x = -w, .y = -h, .z = -d };
    const bbmax = vector{ .x = w, .y = h, .z = d };

    // one big allocation for everything
    const buf_sz = @sizeOf(f32) * (verts.len + txcos.len + normals.len) + @sizeOf(c_uint) * indices.len;

    const dbuf: [*]f32 = @ptrCast(@alignCast(arcan_alloc_mem(buf_sz, ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_SIMD)));
    const nofs: usize = verts.len;
    const tofs: usize = nofs + normals.len;
    const iofs: usize = tofs + txcos.len;

    @memcpy(dbuf[0..verts.len], &verts);
    @memcpy(dbuf[nofs..][0..normals.len], &normals);
    @memcpy(dbuf[tofs..][0..txcos.len], &txcos);
    const iofs_as_uint: [*]c_uint = @ptrCast(@alignCast(dbuf + iofs));
    @memcpy(iofs_as_uint[0..indices.len], &indices);

    if (s) {
        const geom_ptr: ?*?*geometry = &newmodel.geom;
        _ = geom_ptr;
        var prev_geom: ?*geometry = null;

        for (0..6) |i| {
            const g: *geometry = @ptrCast(@alignCast(arcan_alloc_mem(
                @sizeOf(geometry),
                ARCAN_MEM_MODELDATA,
                ARCAN_MEM_BZERO,
                0,
            )));
            g.store.shared_buffer = @ptrCast(dbuf);
            g.store.shared_buffer_sz = buf_sz;
            g.store.verts = dbuf;
            g.store.txcos = dbuf + tofs;
            g.store.normals = dbuf + nofs;
            g.store.indices = iofs_as_uint + i * 6;
            g.store.n_indices = 6;
            g.store.vertex_size = 3;
            g.store.n_vertices = verts.len;
            g.nmaps = nmaps;
            g.complete = true;
            g.next = null;

            if (prev_geom) |pg| {
                pg.next = g;
            } else {
                newmodel.geom = g;
            }
            prev_geom = g;
        }
    } else {
        newmodel.geom = @ptrCast(@alignCast(arcan_alloc_mem(
            @sizeOf(geometry),
            ARCAN_MEM_VTAG,
            ARCAN_MEM_BZERO,
            ARCAN_MEMALIGN_NATURAL,
        )));
        const geom = newmodel.geom.?;
        geom.nmaps = nmaps;
        geom.store.vertex_size = 3;
        geom.store.type = AGP_MESH_TRISOUP;
        geom.store.shared_buffer_sz = buf_sz;
        geom.store.verts = dbuf;
        geom.store.txcos = dbuf + tofs;
        geom.store.normals = dbuf + nofs;
        geom.store.indices = iofs_as_uint;
        geom.store.n_indices = indices.len;
        geom.store.n_vertices = verts.len;
        geom.store.shared_buffer = @ptrCast(dbuf);
        geom.complete = true;
    }

    newmodel.radius = d;
    newmodel.bbmin = bbmin;
    newmodel.bbmax = bbmax;
    newmodel.flags.complete = true;

    return rv;
}

export fn arcan_3d_buildplane(
    mins: f32,
    mint: f32,
    maxs: f32,
    maxt: f32,
    base: f32,
    wdens: f32,
    ddens: f32,
    nmaps: usize,
    vert: bool,
) arcan_vobj_id {
    if (is_freestanding) return ARCAN_EID;
    var state = vfunc_state{ .tag = ARCAN_TAG_3DOBJ, .ptr = null };
    const empty = std.mem.zeroes(img_cons);

    // fail on unsolvable dimension constraints
    if ((maxs < mins or wdens <= 0 or wdens >= maxs - mins) or
        (maxt < mint or ddens <= 0 or ddens >= maxt - mint))
        return @intCast(ARCAN_ERRC_BAD_ARGUMENT);

    const rv = arcan_video_addfobject(FFUNC_3DOBJ, state, empty, 1);

    if (rv == ARCAN_EID)
        return rv;

    // if [vert] we flip y and z axis when setting vertices
    const minp = point{ .x = mins, .y = base, .z = mint };
    const maxp = point{ .x = maxs, .y = base, .z = maxt };
    const step = point{ .x = wdens, .y = 0, .z = ddens };

    const newmodel: *arcan_3dmodel = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(arcan_3dmodel),
        ARCAN_MEM_VTAG,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_PAGE,
    )));

    _ = pthread_mutex_init(&newmodel.lock, null);

    state.ptr = @ptrCast(newmodel);
    _ = arcan_video_alterfeed(rv, FFUNC_3DOBJ, state);

    // find next slot (always first for fresh model)
    newmodel.geom = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(geometry),
        ARCAN_MEM_VTAG,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_PAGE,
    )));

    const geom = newmodel.geom.?;
    geom.nmaps = nmaps;
    geom.store.type = AGP_MESH_TRISOUP;
    geom.store.vertex_size = 3;

    build_plane(minp, maxp, step, &geom.store.verts, &geom.store.indices, &geom.store.txcos, &geom.store.n_vertices, &geom.store.n_indices, vert);

    _ = arcan_video_allocframes(rv, 1, ARCAN_FRAMESET_SPLIT);

    minmax_verts(&newmodel.bbmin, &newmodel.bbmax, geom.store.verts orelse return ARCAN_EID, geom.store.n_vertices);
    geom.complete = true;
    newmodel.flags.complete = true;

    return rv;
}

export fn arcan_3d_meshshader(
    dst: arcan_vobj_id,
    shid: agp_shader_id,
    slot_arg: c_uint,
) arcan_errc {
    if (is_freestanding) return ARCAN_ERRC_NO_SUCH_OBJECT;
    const vobj = arcan_video_getobject(dst) orelse return ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.feed.state.tag != ARCAN_TAG_3DOBJ)
        return ARCAN_ERRC_UNACCEPTED_STATE;

    var cur = (@as(*arcan_3dmodel, @ptrCast(@alignCast(vobj.feed.state.ptr)))).geom;
    var slot: c_uint = slot_arg;
    while (cur != null and slot > 0) {
        cur = cur.?.next;
        slot -= 1;
    }

    if (cur != null and slot == 0) {
        cur.?.program = shid;
    } else {
        return ARCAN_ERRC_BAD_ARGUMENT;
    }

    return ARCAN_OK;
}

export fn arcan_3d_addraw(
    dst: arcan_vobj_id,
    vertices: ?[*]f32,
    n_vertices: usize,
    indices_arg: ?[*]c_uint,
    n_indices: usize,
    txcos_arg: ?[*]f32,
    txcos2: ?[*]f32,
    normals_arg: ?[*]f32,
    tangents: ?[*]f32,
    colors: ?[*]f32,
    bones: ?[*]u16,
    weights: ?[*]f32,
    nmaps: c_uint,
) arcan_errc {
    if (is_freestanding) return ARCAN_ERRC_NO_SUCH_OBJECT;
    const vobj = arcan_video_getobject(dst) orelse return ARCAN_ERRC_NO_SUCH_OBJECT;

    const model: *arcan_3dmodel = @ptrCast(@alignCast(vobj.feed.state.ptr));

    if (vobj.feed.state.tag != ARCAN_TAG_3DOBJ or
        model.flags.complete == true)
        return ARCAN_ERRC_UNACCEPTED_STATE;

    // find last elem and add
    var nextslot: *?*geometry = &model.geom;
    while (nextslot.* != null) {
        nextslot = &nextslot.*.?.next;
    }

    nextslot.* = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(geometry),
        ARCAN_MEM_VTAG,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    )));
    const dg = nextslot.* orelse return ARCAN_ERRC_OUT_OF_SPACE;

    dg.nmaps = nmaps;
    dg.store.type = AGP_MESH_TRISOUP;
    dg.store.verts = vertices;
    dg.store.indices = indices_arg;
    dg.store.normals = normals_arg;
    dg.store.tangents = tangents;
    dg.store.txcos = txcos_arg;
    dg.store.txcos2 = txcos2;
    dg.store.colors = colors;
    dg.store.joints = bones;
    dg.store.weights = weights;
    dg.store.n_vertices = n_vertices;
    dg.store.vertex_size = 3;
    dg.store.n_indices = n_indices;

    return ARCAN_OK;
}

export fn arcan_3d_addmesh(
    dst: arcan_vobj_id,
    resource: data_source,
    nmaps: c_uint,
) arcan_errc {
    if (is_freestanding) return ARCAN_ERRC_NO_SUCH_OBJECT;
    _ = resource;
    _ = nmaps;
    const vobj = arcan_video_getobject(dst) orelse return ARCAN_ERRC_NO_SUCH_OBJECT;

    const model: *arcan_3dmodel = @ptrCast(@alignCast(vobj.feed.state.ptr));

    // Always returns UNACCEPTED_STATE (commented out code in C)
    if (true or
        vobj.feed.state.tag != ARCAN_TAG_3DOBJ or
        model.flags.complete == true)
        return ARCAN_ERRC_UNACCEPTED_STATE;

    return ARCAN_OK;
}

export fn arcan_3d_scalevertices(vid: arcan_vobj_id) arcan_errc {
    if (is_freestanding) return ARCAN_ERRC_NO_SUCH_OBJECT;
    const vobj = arcan_video_getobject(vid) orelse return ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.feed.state.tag != ARCAN_TAG_3DOBJ)
        return ARCAN_ERRC_UNACCEPTED_STATE;

    const model: *arcan_3dmodel = @ptrCast(@alignCast(vobj.feed.state.ptr));

    _ = pthread_mutex_lock(&model.lock);
    if (model.work_count != 0 or !model.flags.complete) {
        model.deferred.scale = true;
        _ = pthread_mutex_unlock(&model.lock);
        return ARCAN_OK;
    }
    var geom = model.geom;

    while (geom) |g| {
        minmax_verts(&model.bbmin, &model.bbmax, g.store.verts.?, g.store.n_vertices);
        geom = g.next;
    }

    geom = model.geom;

    const dx = model.bbmax.x - model.bbmin.x;
    const dy = model.bbmax.y - model.bbmin.y;
    const dz = model.bbmax.z - model.bbmin.z;

    var sf: f32 = undefined;
    if (dz > dy and dz > dx) {
        sf = 2.0 / dz;
    } else if (dy > dz and dy > dx) {
        sf = 2.0 / dy;
    } else {
        sf = 2.0 / dx;
    }

    model.bbmax = mul_vectorf(model.bbmax, sf);
    model.bbmin = mul_vectorf(model.bbmin, sf);

    const tx = (0.0 - model.bbmin.x) - (model.bbmax.x - model.bbmin.x) * 0.5;
    const ty = (0.0 - model.bbmin.y) - (model.bbmax.y - model.bbmin.y) * 0.5;
    const tz = (0.0 - model.bbmin.z) - (model.bbmax.z - model.bbmin.z) * 0.5;

    model.bbmax.x += tx;
    model.bbmin.x += tx;
    model.bbmax.y += ty;
    model.bbmin.y += ty;
    model.bbmax.z += tz;
    model.bbmin.z += tz;

    while (geom) |g| {
        const verts_ptr = g.store.verts.?;
        var i: usize = 0;
        while (i < g.store.n_vertices * 3) : (i += 3) {
            verts_ptr[i] = tx + verts_ptr[i] * sf;
            verts_ptr[i + 1] = ty + verts_ptr[i + 1] * sf;
            verts_ptr[i + 2] = tz + verts_ptr[i + 2] * sf;
        }

        geom = g.next;
    }

    _ = pthread_mutex_unlock(&model.lock);
    return ARCAN_OK;
}

export fn arcan_3d_infinitemodel(id: arcan_vobj_id, state: bool) arcan_errc {
    if (is_freestanding) return ARCAN_ERRC_NO_SUCH_OBJECT;
    const vobj = arcan_video_getobject(id) orelse return ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.feed.state.tag != ARCAN_TAG_3DOBJ)
        return ARCAN_ERRC_UNACCEPTED_STATE;

    const dstobj: *arcan_3dmodel = @ptrCast(@alignCast(vobj.feed.state.ptr));
    dstobj.flags.infinite = state;

    return ARCAN_OK;
}

export fn arcan_3d_finalizemodel(id: arcan_vobj_id) arcan_errc {
    if (is_freestanding) return ARCAN_ERRC_NO_SUCH_OBJECT;
    const vobj = arcan_video_getobject(id) orelse return ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.feed.state.tag != ARCAN_TAG_3DOBJ)
        return ARCAN_ERRC_UNACCEPTED_STATE;

    const dstobj: *arcan_3dmodel = @ptrCast(@alignCast(vobj.feed.state.ptr));

    if (dstobj.flags.complete == false) {
        dstobj.flags.complete = true;
        push_deferred(dstobj);
    }

    return ARCAN_OK;
}

export fn arcan_3d_emptymodel() arcan_vobj_id {
    if (is_freestanding) return ARCAN_EID;
    const econs = std.mem.zeroes(img_cons);
    const newmodel: *arcan_3dmodel = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(arcan_3dmodel),
        ARCAN_MEM_VTAG,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    )));
    const state = vfunc_state{ .tag = ARCAN_TAG_3DOBJ, .ptr = @ptrCast(newmodel) };

    const rv = arcan_video_addfobject(FFUNC_3DOBJ, state, econs, 1);

    if (rv != ARCAN_EID) {
        newmodel.parent = arcan_video_getobject(rv);
        _ = pthread_mutex_init(&newmodel.lock, null);
    } else {
        arcan_mem_free(@ptrCast(newmodel));
    }

    return rv;
}

export fn arcan_3d_baseorient(
    dst: arcan_vobj_id,
    roll: f32,
    pitch: f32,
    yaw: f32,
) arcan_errc {
    if (is_freestanding) return ARCAN_ERRC_NO_SUCH_OBJECT;
    const vobj = arcan_video_getobject(dst) orelse return ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.feed.state.tag != ARCAN_TAG_3DOBJ)
        return ARCAN_ERRC_UNACCEPTED_STATE;

    const model: *arcan_3dmodel = @ptrCast(@alignCast(vobj.feed.state.ptr));
    _ = pthread_mutex_lock(&model.lock);

    if (model.work_count != 0 or !model.flags.complete) {
        model.deferred.orient = true;
        model.deferred.orientf.x = roll;
        model.deferred.orientf.y = pitch;
        model.deferred.orientf.z = yaw;
        _ = pthread_mutex_unlock(&model.lock);
        return ARCAN_OK;
    }

    var geom = model.geom;

    // 1. create the rotation matrix by mapping to a quaternion
    const repr = build_quat_taitbryan(roll, pitch, yaw);
    var matr: [16]f32 align(16) = undefined;
    _ = matr_quatf(repr, &matr);

    // 2. iterate all geometries connected to the model
    while (geom) |g| {
        const verts_ptr = g.store.verts.?;

        // 3. sweep through all the vertexes in the model
        var i: usize = 0;
        while (i < g.store.n_vertices * 3) : (i += 3) {
            var xyz align(16) = [4]f32{ verts_ptr[i], verts_ptr[i + 1], verts_ptr[i + 2], 1.0 };
            var out_v: [4]f32 align(16) = undefined;

            // 4. transform the current vertex
            mult_matrix_vecf(&matr, &xyz, &out_v);
            verts_ptr[i] = out_v[0];
            verts_ptr[i + 1] = out_v[1];
            verts_ptr[i + 2] = out_v[2];
        }

        geom = g.next;
    }

    _ = pthread_mutex_unlock(&model.lock);
    return ARCAN_OK;
}

export fn arcan_3d_camproj(vid: arcan_vobj_id, proj: *[16]f32) arcan_errc {
    if (is_freestanding) return ARCAN_ERRC_NO_SUCH_OBJECT;
    const vobj = arcan_video_getobject(vid) orelse return ARCAN_ERRC_NO_SUCH_OBJECT;

    const camera: *camtag_data = @ptrCast(@alignCast(vobj.feed.state.ptr));
    if (vobj.feed.state.tag != ARCAN_TAG_3DCAMERA)
        return ARCAN_ERRC_UNACCEPTED_STATE;

    @memcpy(&camera.projection, proj);
    return ARCAN_OK;
}

// arcan_3d_camtag — the caller in arcan_lua.c passes line_width directly.
export fn arcan_3d_camtag(
    tgtid: arcan_vobj_id,
    vid: arcan_vobj_id,
    near: f32,
    far: f32,
    ar: f32,
    fov: f32,
    flags: c_int,
    line_width: f64,
) callconv(.c) arcan_errc {
    if (is_freestanding) return ARCAN_ERRC_NO_SUCH_OBJECT;
    const vobj = arcan_video_getobject(vid) orelse return ARCAN_ERRC_NO_SUCH_OBJECT;
    var tgt: ?*rendertarget = null;

    if (tgtid != ARCAN_EID) {
        const tgtobj = arcan_video_getobject(tgtid);
        tgt = arcan_vint_findrt(tgtobj);
    }

    var camobj: ?*camtag_data = null;

    if (vobj.feed.state.ptr != null) {
        if (vobj.feed.state.tag != ARCAN_TAG_3DCAMERA)
            return ARCAN_ERRC_UNACCEPTED_STATE;
        camobj = @ptrCast(@alignCast(vobj.feed.state.ptr));
    }

    if (tgt) |rt| {
        rt.camtag = vobj.cellid;
    } else {
        vobj.owner.*.camtag = vobj.cellid;
    }

    if (camobj == null) {
        camobj = @ptrCast(@alignCast(arcan_alloc_mem(
            @sizeOf(camtag_data),
            ARCAN_MEM_VTAG,
            ARCAN_MEM_BZERO,
            ARCAN_MEMALIGN_SIMD,
        )));
    }

    const cam = camobj.?;
    cam.near = near;
    cam.far = far;
    cam.flags = flags;
    if ((flags & MESH_FILL_LINE) != 0) {
        cam.line_width = @floatCast(line_width);
    } else {
        cam.line_width = 1.0;
    }

    build_projection_matrix(&cam.projection, near, far, ar, fov);

    const new_state = vfunc_state{ .tag = ARCAN_TAG_3DCAMERA, .ptr = @ptrCast(cam) };
    _ = arcan_video_alterfeed(vid, FFUNC_3DOBJ, new_state);

    vobj.flags |= @as(c_uint, @intCast(FL_FULL3D));

    return ARCAN_OK;
}
