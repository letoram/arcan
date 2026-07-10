const std = @import("std");
const builtin = @import("builtin");

const c = if (builtin.os.tag == .freestanding)
    @import("arcan_boot_compat")
else
    @import("arcan");

extern var stderr: *anyopaque;
extern fn fputs(s: [*:0]const u8, fp: *anyopaque) c_int;
fn trace_stderr(msg: [*:0]const u8) void {
    _ = fputs(msg, stderr);
}

// Clean math types (bypass @cImport anonymous union nesting)
// These have identical ABI to the C types, but expose x/y/z/w directly.
const Vec3 = extern struct { x: f32 = 0, y: f32 = 0, z: f32 = 0 };
const Quat = extern struct { x: f32 = 0, y: f32 = 0, z: f32 = 0, w: f32 = 0 };

const SurfOri = extern struct {
    yaw: f32 = 0,
    pitch: f32 = 0,
    roll: f32 = 0,
    quaternion: Quat = .{},
};

const SurfProps = extern struct {
    position: Vec3 = .{},
    scale: Vec3 = .{},
    opa: f32 = 0,
    rotation: SurfOri = .{},
};

/// Reinterpret c.surface_properties ↔ SurfProps (identical ABI)
inline fn sp(p: *c.surface_properties) *SurfProps {
    return @ptrCast(p);
}
inline fn spConst(p: *const c.surface_properties) *const SurfProps {
    return @ptrCast(p);
}
inline fn toCSP(p: SurfProps) c.surface_properties {
    return @bitCast(p);
}
inline fn fromCSP(p: c.surface_properties) SurfProps {
    return @bitCast(p);
}

// Type aliases
const arcan_vobj_id = c.arcan_vobj_id;
const arcan_errc = c.arcan_errc;
const arcan_vobject = c.arcan_vobject;
const arcan_vobject_litem = c.struct_arcan_vobject_litem;
const rendertarget = c.struct_rendertarget;
const surface_properties = c.surface_properties;
const surface_transform = c.struct_surface_transform;
const agp_vstore = c.struct_agp_vstore;
const agp_shader_id = c.agp_shader_id;
const img_cons = c.img_cons;
const vfunc_state = c.vfunc_state;
const av_pixel = c.av_pixel;

// Extern functions not available through @cImport (opaque struct params)
extern fn arcan_frameserver_flush(?*c.struct_arcan_frameserver) callconv(.c) void;
extern fn arcan_frameserver_free(?*c.struct_arcan_frameserver) callconv(.c) void;
extern fn arcan_frameserver_resume(?*c.struct_arcan_frameserver) callconv(.c) void;
extern fn fsrv_helper_get_aid(*c.struct_arcan_frameserver) callconv(.c) c.arcan_aobj_id;
extern fn fsrv_helper_set_no_dms_free(*c.struct_arcan_frameserver, bool) callconv(.c) void;
extern fn fsrv_helper_get_no_adopt(*c.struct_arcan_frameserver) callconv(.c) bool;

// Constants
const ARCAN_EID = c.ARCAN_EID;
const ARCAN_VIDEO_WORLDID = c.ARCAN_VIDEO_WORLDID;
const ARCAN_OK = c.ARCAN_OK;
const CONTEXT_STACK_LIMIT = c.CONTEXT_STACK_LIMIT;
const RENDERTARGET_LIMIT = c.RENDERTARGET_LIMIT;
const VITEM_CONTEXT_LIMIT = c.VITEM_CONTEXT_LIMIT;
const EPSILON: f32 = 0.000001;
const ASYNCH_CONCURRENT_THREADS = 12;

// Interpolation LUTs (match arcan_vinterp enum)
const lut_interp_3d = [_]c.arcan_interp_3d_function{
    c.interp_3d_linear,
    c.interp_3d_sine,
    c.interp_3d_expin,
    c.interp_3d_expout,
    c.interp_3d_expinout,
    c.interp_3d_smoothstep,
};

const lut_interp_1d = [_]c.arcan_interp_1d_function{
    c.interp_1d_linear,
    c.interp_1d_sine,
    c.interp_1d_expin,
    c.interp_1d_expout,
    c.interp_1d_expinout,
    c.interp_1d_smoothstep,
};

// ============================================================
// Globals
// ============================================================

export var arcan_video_display: c.struct_arcan_video_display = blk: {
    var d: c.struct_arcan_video_display = std.mem.zeroes(c.struct_arcan_video_display);
    d.conservative = false;
    d.deftxs = c.ARCAN_VTEX_CLAMP;
    d.deftxt = c.ARCAN_VTEX_CLAMP;
    d.scalemode = c.ARCAN_VIMAGE_NOPOW2;
    d.filtermode = c.ARCAN_VFILTER_BILINEAR;
    d.blendmode = c.BLEND_FORCE;
    d.order3d = c.ORDER3D_FIRST;
    d.suspended = false;
    d.msasamples = 4;
    d.c_ticks = 1;
    d.default_vitemlim = 1024;
    d.imageproc = c.IMAGEPROC_NORMAL;
    d.mipmap = false;
    d.dirty = 0;
    d.cursor.w = 24;
    d.cursor.h = 16;
    break :blk d;
};

export var vcontext_stack: [CONTEXT_STACK_LIMIT]c.struct_arcan_video_context = blk: {
    var stk: [CONTEXT_STACK_LIMIT]c.struct_arcan_video_context =
        std.mem.zeroes([CONTEXT_STACK_LIMIT]c.struct_arcan_video_context);
    stk[0].n_rtargets = 0;
    stk[0].vitem_ofs = 1;
    stk[0].nalive = 0;
    stk[0].world.tracetag = @constCast(@ptrCast("(world)"));
    stk[0].world.current.opa = 1.0;
    sp(&stk[0].world.current).rotation.quaternion.w = 1.0;
    break :blk stk;
};

export var vcontext_ind: c_uint = 0;

var current_context: *c.struct_arcan_video_context = &vcontext_stack[0];
// Must be null-initialized, not `undefined`. Zig safe mode fills `undefined`
// with 0xAA, and arcan_sem_init checks `sem.* == null` to decide whether to
// malloc a fresh sem_t — 0xAA… isn't null so the check skips the malloc and
// the subsequent sem_init() dereferences the garbage pointer. A zero-init
// sentinel is the contract arcan_sem_init expects.
var asynchsynch: c.sem_handle = null;
threadlocal var _current_rendertarget: ?*rendertarget = null;

// ============================================================
// Helper functions
// ============================================================

fn flagDirty(vobj: ?*arcan_vobject) void {
    if (vobj) |v| {
        if (v.owner != null) {
            @as(*rendertarget, @ptrCast(v.owner)).transfc += 1;
        }
    }
    arcan_video_display.dirty += 1;
}

inline fn flTest(obj: *const arcan_vobject, fl: c_uint) bool {
    return (@as(c_uint, @bitCast(obj.flags)) & fl) > 0;
}

inline fn flSet(obj: *arcan_vobject, fl: c_uint) void {
    obj.flags = @bitCast(@as(c_uint, @bitCast(obj.flags)) | fl);
}

inline fn flClear(obj: *arcan_vobject, fl: c_uint) void {
    obj.flags = @bitCast(@as(c_uint, @bitCast(obj.flags)) & ~fl);
}

fn trace(msg: [*c]const u8) void {
    _ = msg;
    // trace is a no-op unless TRACE_ENABLE is set
}

fn video_tracetag(src: ?*arcan_vobject) [*c]const u8 {
    if (src) |s| {
        if (s.tracetag) |tag| return tag;
    }
    return "(unknown)";
}

fn empty_surface() SurfProps {
    return .{ .rotation = .{ .quaternion = .{ .w = 1.0 } } };
}

// ============================================================
// Chunk 1: Simple queries & defaults
// ============================================================

export fn arcan_video_nfreecontexts() c_uint {
    return @intCast(CONTEXT_STACK_LIMIT - 1 - @as(c_int, @intCast(vcontext_ind)));
}

export fn arcan_video_default_texfilter(mode: c.arcan_vfilter_mode) void {
    arcan_video_display.filtermode = mode;
}

export fn arcan_video_default_imageprocmode(mode: c.arcan_imageproc_mode) void {
    arcan_video_display.imageproc = mode;
}

export fn arcan_video_default_scalemode(newmode: c.arcan_vimage_mode) void {
    arcan_video_display.scalemode = newmode;
}

export fn arcan_video_default_blendmode(newmode: c.arcan_blendfunc) void {
    arcan_video_display.blendmode = newmode;
}

export fn arcan_video_default_texmode(modes: c_uint, modet: c_uint) void {
    arcan_video_display.deftxs = modes;
    arcan_video_display.deftxt = modet;
}

export fn arcan_vint_defaultmapping(dst: [*c]f32, st: f32, tt: f32) void {
    dst[0] = 0.0;
    dst[1] = 0.0;
    dst[2] = st;
    dst[3] = 0.0;
    dst[4] = st;
    dst[5] = tt;
    dst[6] = 0.0;
    dst[7] = tt;
}

export fn arcan_vint_mirrormapping(dst: [*c]f32, st: f32, tt: f32) void {
    dst[6] = 0.0;
    dst[7] = 0.0;
    dst[4] = st;
    dst[5] = 0.0;
    dst[2] = st;
    dst[3] = tt;
    dst[0] = 0.0;
    dst[1] = tt;
}

export fn arcan_video_getmask(vid: arcan_vobj_id) c_uint {
    const vobj = arcan_video_getobject(vid);
    if (vobj == null) return 0;
    return @bitCast(vobj.?.mask);
}

export fn arcan_video_readtag(vid: arcan_vobj_id, tag: ?*[*c]const u8, alt: ?*[*c]const u8) arcan_errc {
    const vobj = arcan_video_getobject(vid);
    if (vobj == null) {
        if (tag) |t| t.* = null;
        if (alt) |a| a.* = null;
    } else {
        if (tag) |t| t.* = vobj.?.tracetag;
        if (alt) |a| a.* = vobj.?.alttext;
    }
    return ARCAN_OK;
}

export fn arcan_video_transformmask(vid: arcan_vobj_id, mask: c_uint) arcan_errc {
    const vobj = arcan_video_getobject(vid);
    if (vobj == null) return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    vobj.?.mask = @bitCast(mask);
    return ARCAN_OK;
}

export fn arcan_video_visible(vid: arcan_vobj_id, ov: bool) arcan_errc {
    const vobj = arcan_video_getobject(vid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const newopa: f32 = if (ov) 1.0 else 0.0;
    vobj.current.opa = newopa;
    flagDirty(vobj);
    return ARCAN_OK;
}

export fn arcan_video_getzv(vid: arcan_vobj_id) c_int {
    const vobj = arcan_video_getobject(vid) orelse return -1;
    return vobj.order;
}

export fn arcan_video_maxorder(rt: arcan_vobj_id, ov: *u16) arcan_errc {
    const vobj = arcan_video_getobject(rt);
    if (vobj == null) return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const tgt = arcan_vint_findrt(vobj.?) orelse return c.ARCAN_ERRC_UNACCEPTED_STATE;
    _ = tgt;
    var current_litem: ?*arcan_vobject_litem = @ptrCast(current_context.stdoutp.first);
    var order: u16 = 0;
    while (current_litem) |cl| {
        if (cl.elem) |elem_raw| {
            const elem: *arcan_vobject = @ptrCast(elem_raw);
            if (elem.order > 0 and @as(u16, @intCast(@as(c_uint, @bitCast(elem.order)) & 0xFFFF)) > order and elem.order < 65531)
                order = @intCast(@as(c_uint, @bitCast(elem.order)) & 0xFFFF);
        }
        current_litem = @ptrCast(cl.next);
    }
    ov.* = order;
    return ARCAN_OK;
}

export fn arcan_video_storage_properties(vid: arcan_vobj_id) img_cons {
    var res: img_cons = std.mem.zeroes(img_cons);
    const vobj = arcan_video_getobject(vid);
    if (vobj) |v| {
        const vs_opt: ?*agp_vstore = @ptrCast(v.vstore);
        if (vs_opt) |vs| {
            res.w = @intCast(vs.w);
            res.h = @intCast(vs.h);
            res.bpp = @intCast(vs.bpp);
        }
    }
    return res;
}

export fn arcan_video_initial_properties(vid: arcan_vobj_id) surface_properties {
    var res = empty_surface();
    const vobj = arcan_video_getobject(vid);
    if (vobj) |v| {
        if (vid > 0) {
            res.scale.x = @floatFromInt(v.origw);
            res.scale.y = @floatFromInt(v.origh);
        }
    }
    return toCSP(res);
}

export fn arcan_video_current_properties(vid: arcan_vobj_id) surface_properties {
    var rv = empty_surface();
    const vobj = arcan_video_getobject(vid);
    if (vobj) |v| {
        rv = fromCSP(v.current);
        rv.scale.x *= @floatFromInt(v.origw);
        rv.scale.y *= @floatFromInt(v.origh);
    }
    return toCSP(rv);
}

export fn arcan_video_resolve_properties(vid: arcan_vobj_id) surface_properties {
    var res = empty_surface();
    const vobj = arcan_video_getobject(vid);
    if (vobj) |v| {
        if (vid > 0) {
            arcan_resolve_vidprop(v, 0.0, @ptrCast(&res));
            res.scale.x *= @floatFromInt(v.origw);
            res.scale.y *= @floatFromInt(v.origh);
        }
    }
    return toCSP(res);
}

// ============================================================
// Chunk 2: Object allocation & lifecycle
// ============================================================

fn populate_vstore(vs: *?*agp_vstore) void {
    vs.* = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @sizeOf(agp_vstore),
        c.ARCAN_MEM_VSTRUCT,
        c.ARCAN_MEM_BZERO,
        c.ARCAN_MEMALIGN_NATURAL,
    )));
    const s = vs.* orelse return;
    s.txmapped = c.TXSTATE_TEX2D;
    s.txu = @intCast(arcan_video_display.deftxs);
    s.txv = @intCast(arcan_video_display.deftxt);
    s.scale = @intCast(arcan_video_display.scalemode);
    s.imageproc = @intCast(arcan_video_display.imageproc);
    s.filtermode = @intCast(arcan_video_display.filtermode);
    if (arcan_video_display.mipmap)
        s.filtermode |= @intCast(c.ARCAN_VFILTER_MIPMAP);
    s.refcount = 1;
}

fn video_allocid(status: *bool, ctx: *c.struct_arcan_video_context, write: bool) arcan_vobj_id {
    var i = ctx.vitem_ofs;
    var cnt: c_uint = ctx.vitem_limit;
    status.* = false;

    while (cnt > 0) : (cnt -= 1) {
        if (i == 0) i = 1;

        if (!flTest(@ptrCast(&ctx.vitems_pool[i]), c.FL_INUSE)) {
            status.* = true;
            if (!write) return @intCast(i);

            ctx.vitems_pool[i] = std.mem.zeroes(arcan_vobject);
            ctx.nalive += 1;
            flSet(@ptrCast(&ctx.vitems_pool[i]), c.FL_INUSE);
            ctx.vitem_ofs = if ((ctx.vitem_ofs + 1) >= ctx.vitem_limit) 1 else i + 1;
            return @intCast(i);
        }

        i = (i + 1) % (ctx.vitem_limit - 1);
    }

    return ARCAN_EID;
}

fn new_vobject(id: ?*arcan_vobj_id, dctx: *c.struct_arcan_video_context) ?*arcan_vobject {
    var status: bool = undefined;
    const fid = video_allocid(&status, dctx, true);

    if (!status) return null;

    const rv = &dctx.vitems_pool[@intCast(fid)];
    populate_vstore(&rv.vstore);

    rv.feed.ffunc = c.FFUNC_FATAL;
    rv.blendmode = arcan_video_display.blendmode;
    rv.clip = c.ARCAN_CLIP_OFF;

    sp(&rv.current).scale.x = 1.0;
    sp(&rv.current).scale.y = 1.0;
    sp(&rv.current).scale.z = 1.0;
    sp(&rv.current).position.x = 0;
    sp(&rv.current).position.y = 0;
    sp(&rv.current).position.z = 0;
    rv.current.rotation.quaternion = c.default_quat;

    rv.cellid = fid;
    rv.parent = &current_context.world;
    rv.mask = @bitCast(@as(c_uint, c.MASK_ORIENTATION | c.MASK_OPACITY | c.MASK_POSITION | c.MASK_FRAMESET | c.MASK_LIVING));

    if (id) |idp| idp.* = fid;

    return rv;
}

export fn arcan_video_newvobject(id: ?*arcan_vobj_id) ?*arcan_vobject {
    return new_vobject(id, current_context);
}

export fn arcan_video_getobject(id: arcan_vobj_id) ?*arcan_vobject {
    if (id > 0 and id < current_context.vitem_limit and
        flTest(@ptrCast(&current_context.vitems_pool[@intCast(id)]), c.FL_INUSE))
    {
        return &current_context.vitems_pool[@intCast(id)];
    } else if (id == ARCAN_VIDEO_WORLDID) {
        return &current_context.world;
    }
    return null;
}

export fn arcan_vint_nextfree() arcan_vobj_id {
    var status: bool = undefined;
    const id = video_allocid(&status, current_context, false);
    return if (status) id else ARCAN_EID;
}

export fn arcan_video_findstate(tag: c.arcan_vobj_tags, ptr: ?*anyopaque) arcan_vobj_id {
    var i: usize = 1;
    while (i < current_context.vitem_limit) : (i += 1) {
        if (flTest(@ptrCast(&current_context.vitems_pool[i]), c.FL_INUSE)) {
            const vobj: *arcan_vobject = @ptrCast(&current_context.vitems_pool[i]);
            if (vobj.feed.state.tag == tag and vobj.feed.state.ptr == ptr)
                return @intCast(i);
        }
    }
    return ARCAN_EID;
}

fn addchild(parent: *arcan_vobject, child_obj: *arcan_vobject) void {
    var slot: ?*?*arcan_vobject = null;
    var i: usize = 0;
    while (i < parent.childslots) : (i += 1) {
        if (parent.children[i] == null) {
            slot = &parent.children[i];
            break;
        }
    }

    if (slot == null) {
        const news: [*c]?*arcan_vobject = @ptrCast(@alignCast(c.arcan_alloc_mem(
            (parent.childslots + 8) * @sizeOf(?*arcan_vobject),
            c.ARCAN_MEM_VSTRUCT,
            0,
            c.ARCAN_MEMALIGN_NATURAL,
        )));

        if (parent.children != null) {
            const dst: [*]u8 = @ptrCast(news);
            const src_ptr: [*]const u8 = @ptrCast(parent.children);
            @memcpy(dst[0 .. parent.childslots * @sizeOf(?*arcan_vobject)], src_ptr[0 .. parent.childslots * @sizeOf(?*arcan_vobject)]);
            c.arcan_mem_free(@ptrCast(parent.children));
        }

        parent.children = news;
        var j: usize = 0;
        while (j < 8) : (j += 1) {
            parent.children[parent.childslots + j] = null;
        }

        slot = &parent.children[parent.childslots];
        parent.childslots += 8;
    }

    parent.extrefc.links += 1;
    child_obj.parent = parent;
    slot.?.* = child_obj;
}

fn invalidate_cache(vobj: *arcan_vobject) void {
    flagDirty(vobj);
    vobj.valid_cache = false;

    var i: usize = 0;
    while (i < vobj.childslots) : (i += 1) {
        if (vobj.children[i]) |ch| {
            invalidate_cache(ch);
        }
    }
}

fn dropchild(parent: *arcan_vobject, child_obj: *arcan_vobject) void {
    var i: usize = 0;
    while (i < parent.childslots) : (i += 1) {
        if (parent.children[i] == child_obj) {
            parent.children[i] = null;
            parent.extrefc.links -= 1;
            child_obj.parent = &current_context.world;
            break;
        }
    }
}

export fn arcan_vint_drop_vstore(s: ?*agp_vstore) void {
    const st = s orelse return;
    st.refcount -= 1;

    if (st.refcount == 0) {
        if (st.txmapped != c.TXSTATE_OFF and st.vinf.text.glid != 0) {
            if (st.vinf.text.raw) |raw| {
                c.arcan_mem_free(@ptrCast(raw));
                st.vinf.text.raw = null;
            }

            if (st.vinf.text.unnamed_0.tpack.group) |grp| {
                c.arcan_renderfun_release_fontgroup(@ptrCast(grp));
            }

            c.agp_drop_vstore(st);

            if (st.vinf.text.unnamed_0.source) |src| {
                c.arcan_mem_free(@ptrCast(src));
            }

            const ptr: [*]u8 = @ptrCast(st);
            @memset(ptr[0..@sizeOf(agp_vstore)], 0);
        }

        c.arcan_mem_free(@ptrCast(st));
    }
}

fn step_active_frame(vobj: *arcan_vobject) void {
    const fs: *c.struct_vobject_frameset = @ptrCast(vobj.frameset orelse return);
    const sz = fs.n_frames;
    fs.index = (fs.index + 1) % sz;
    if (vobj.owner != null) {
        @as(*rendertarget, @ptrCast(vobj.owner)).transfc += 1;
    }
    flagDirty(vobj);
}

export fn arcan_video_inheritorder(vid: arcan_vobj_id, newv: bool) arcan_errc {
    const vobj = arcan_video_getobject(vid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (vid == c.ARCAN_VIDEO_WORLDID or vobj.order < 0) return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (newv) {
        flSet(vobj, c.FL_ORDOFS);
    } else {
        flClear(vobj, c.FL_ORDOFS);
    }
    _ = update_zv(vobj, @as(*arcan_vobject, @ptrCast(vobj.parent)).order);
    return ARCAN_OK;
}

// ============================================================
// Chunk 3: Rendertarget management
// ============================================================

export fn arcan_vint_findrt(vobj: ?*arcan_vobject) ?*rendertarget {
    const v = vobj orelse return null;
    var i: usize = 0;
    while (i < @as(usize, @intCast(current_context.n_rtargets))) : (i += 1) {
        if (current_context.rtargets[i].color == v)
            return &current_context.rtargets[i];
    }
    if (v == &current_context.world)
        return &current_context.stdoutp;
    return null;
}

// Return the backing vstore of the RT that uses vobj as its color attachment.
export fn arcan_vint_findrt_color_store(vobj: ?*arcan_vobject) ?*agp_vstore {
    const rt = arcan_vint_findrt(vobj) orelse return null;
    const col = rt.color orelse return null;
    const vo: *arcan_vobject = @ptrCast(col);
    return vo.vstore;
}

export fn arcan_vint_findrt_vstore(st: ?*agp_vstore) ?*rendertarget {
    const s = st orelse return null;
    var i: usize = 0;
    while (i < @as(usize, @intCast(current_context.n_rtargets))) : (i += 1) {
        if (current_context.rtargets[i].color) |col_raw| {
            const col: *arcan_vobject = @ptrCast(col_raw);
            if (col.vstore == s)
                return &current_context.rtargets[i];
        }
    }
    if (current_context.stdoutp.color) |col_raw| {
        const col: *arcan_vobject = @ptrCast(col_raw);
        if (s == col.vstore)
            return &current_context.stdoutp;
    }
    return null;
}

fn detach_fromtarget(dst: ?*rendertarget, src: *arcan_vobject) bool {
    const d = dst orelse return false;
    rt_list_generation +%= 1;
    if (d.camtag == src.cellid)
        d.camtag = ARCAN_EID;
    if (d.first == null) return false;

    // find the element
    var torem: ?*arcan_vobject_litem = d.first;
    while (torem) |t| {
        if (t.elem == src) break;
        torem = t.next;
    } else return false;

    const t = torem.?;

    // remove from linked list
    if (d.first == t) {
        d.first = t.next;
        if (d.first) |f_raw| @as(*arcan_vobject_litem, @ptrCast(f_raw)).previous = null;
    } else if (t.next == null) {
        if (t.previous != null) @as(*arcan_vobject_litem, @ptrCast(t.previous)).next = null;
    } else {
        if (t.next != null) @as(*arcan_vobject_litem, @ptrCast(t.next)).previous = t.previous;
        if (t.previous != null) @as(*arcan_vobject_litem, @ptrCast(t.previous)).next = t.next;
    }

    var poison_elem: [*c]arcan_vobject = undefined;
    @as(*usize, @ptrCast(&poison_elem)).* = 0xfeedface;
    t.elem = poison_elem;
    c.arcan_mem_free(@ptrCast(t));

    if (src.owner == d) src.owner = null;

    if (d.color != null and d != &current_context.stdoutp) {
        @as(*arcan_vobject, @ptrCast(d.color)).extrefc.attachments -= 1;
        src.extrefc.attachments -= 1;
    } else {
        src.extrefc.attachments -= 1;
    }

    flagDirty(null);
    return true;
}

fn attach_object(dst: *rendertarget, src: *arcan_vobject) void {
    rt_list_generation +%= 1;
    const new_litem: *arcan_vobject_litem = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @sizeOf(arcan_vobject_litem),
        c.ARCAN_MEM_VSTRUCT,
        0,
        c.ARCAN_MEMALIGN_NATURAL,
    )));

    new_litem.next = null;
    new_litem.previous = null;
    new_litem.elem = src;

    if (src.owner == null) src.owner = dst;

    if (dst.first == null) {
        dst.first = new_litem;
    } else {
        const first_opt: ?*arcan_vobject_litem = @ptrCast(dst.first);
        const first_elem_opt: ?*arcan_vobject = @ptrCast(first_opt.?.elem);
        if (first_elem_opt.?.order > src.order) {
            new_litem.next = dst.first;
            dst.first = new_litem;
            if (new_litem.next != null)
                @as(*arcan_vobject_litem, @ptrCast(new_litem.next)).previous = new_litem;
        } else {
            var ipoint: ?*arcan_vobject_litem = @ptrCast(dst.first);
            var last = false;
            while (ipoint) |ip| {
                if (ip.next == null) {
                    last = true;
                    break;
                }
                const ip_next: *arcan_vobject_litem = @ptrCast(ip.next);
                const ip_next_elem: *arcan_vobject = @ptrCast(ip_next.elem);
                if (ip_next_elem.order > src.order)
                    break;
                ipoint = @ptrCast(ip.next);
            }

            if (ipoint) |ip| {
                if (last) {
                    ip.next = new_litem;
                    new_litem.previous = ip;
                } else {
                    new_litem.next = ip.next;
                    new_litem.previous = ip;
                    if (ip.next != null)
                        @as(*arcan_vobject_litem, @ptrCast(ip.next)).previous = new_litem;
                    ip.next = new_litem;
                }
            }
        }
    }

    // density reraster
    if (dst.hppcm > EPSILON or dst.vppcm > EPSILON) {
        arcan_vint_reraster(src, dst);
    }

    if (dst.color != null and dst != &current_context.stdoutp) {
        src.extrefc.attachments += 1;
        @as(*arcan_vobject, @ptrCast(dst.color)).extrefc.attachments += 1;
    } else {
        src.extrefc.attachments += 1;
    }

    flagDirty(null);
}

export fn arcan_vint_attachobject(id: arcan_vobj_id) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (vobj.owner != null) {
        _ = detach_fromtarget(vobj.owner, vobj);
    }
    attach_object(current_context.attachment orelse &current_context.stdoutp, vobj);
    return ARCAN_OK;
}


export fn arcan_video_currentattachment(vid: arcan_vobj_id) ?*rendertarget {
    const vobj = arcan_video_getobject(vid) orelse return null;
    return vobj.owner;
}

export fn arcan_vint_dirty_all() void {
    var ind: usize = 0;
    while (ind < @as(usize, @intCast(current_context.n_rtargets))) : (ind += 1) {
        current_context.rtargets[ind].dirtyc += 1;
    }
    arcan_video_display.dirty += 1;
}

export fn arcan_vint_reraster(src: *arcan_vobject, rtgt: *rendertarget) void {
    const vs: *agp_vstore = @ptrCast(src.vstore orelse return);

    if (!(vs.txmapped != c.TXSTATE_OFF and
        (vs.vinf.text.kind == c.STORAGE_TEXT or vs.vinf.text.kind == c.STORAGE_TEXTARRAY) and
        (@abs(vs.vinf.text.vppcm - rtgt.vppcm) > EPSILON or
        @abs(vs.vinf.text.hppcm - rtgt.hppcm) > EPSILON)))
        return;

    var dw: usize = 0;
    var dh: usize = 0;
    var maxw: usize = 0;
    var maxh: usize = 0;
    var dsz: u32 = 0;
    var n_lines_dummy: c_uint = 0;
    var lineheights_dummy: [*c]c.struct_renderline_meta = null;

    if (vs.vinf.text.kind == c.STORAGE_TEXT) {
        _ = c.arcan_renderfun_renderfmtstr(
            vs.vinf.text.unnamed_0.source,
            src.cellid,
            false,
            &n_lines_dummy,
            &lineheights_dummy,
            &dw,
            &dh,
            &dsz,
            &maxw,
            &maxh,
            false,
        );
    } else {
        _ = c.arcan_renderfun_renderfmtstr_extended(
            @ptrCast(vs.vinf.text.unnamed_0.source_arr),
            src.cellid,
            false,
            &n_lines_dummy,
            &lineheights_dummy,
            &dw,
            &dh,
            &dsz,
            &maxw,
            &maxh,
            false,
        );
    }
}

export fn arcan_vint_worldrt() ?*c.struct_agp_rendertarget {
    return current_context.stdoutp.art;
}

export fn arcan_vint_world() ?*agp_vstore {
    return current_context.world.vstore;
}

export fn arcan_vint_current_rt() ?*rendertarget {
    return _current_rendertarget;
}

export fn arcan_video_rendertargetid(tgt: ?*rendertarget, newid: *c_int, oldid: *c_int) void {
    const t = tgt orelse return;
    oldid.* = t.id;
    if (newid.* >= 0) t.id = newid.*;
}

// ============================================================
// Chunk 4: Transform chain helpers, linking, init, canvas,
//          image loading, rendertarget setup, feed objects
// ============================================================

// Rendertarget FL helpers (rendertarget has its own flags field of type c_uint)
inline fn rtFlTest(rt: anytype, fl: c_uint) bool {
    return (rt.flags & fl) > 0;
}

inline fn rtFlSet(rt: anytype, fl: c_uint) void {
    rt.flags = rt.flags | fl;
}

inline fn rtFlClear(rt: anytype, fl: c_uint) void {
    rt.flags = rt.flags & ~fl;
}

/// run through the chain and zero all occurrences at ofs
fn swipe_chain(base_in: ?*surface_transform, ofs: usize, size: usize) void {
    var base = base_in;
    while (base) |b| {
        const ptr: [*]u8 = @ptrCast(b);
        @memset(ptr[ofs .. ofs + size], 0);
        base = b.next;
    }
}

/// copy a transform chain, compacting into freshly allocated nodes
fn dup_chain(base_in: ?*surface_transform) ?*surface_transform {
    const first = base_in orelse return null;

    const res: *surface_transform = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @sizeOf(surface_transform),
        c.ARCAN_MEM_VSTRUCT,
        0,
        c.ARCAN_MEMALIGN_NATURAL,
    )));

    var current: *surface_transform = res;
    var base: ?*surface_transform = first;

    while (base) |b| {
        const dst_ptr: [*]u8 = @ptrCast(current);
        const src_ptr: [*]const u8 = @ptrCast(b);
        @memcpy(dst_ptr[0..@sizeOf(surface_transform)], src_ptr[0..@sizeOf(surface_transform)]);

        if (b.next != null) {
            current.next = @ptrCast(@alignCast(c.arcan_alloc_mem(
                @sizeOf(surface_transform),
                c.ARCAN_MEM_VSTRUCT,
                0,
                c.ARCAN_MEMALIGN_NATURAL,
            )));
        } else {
            current.next = null;
        }

        if (current.next) |n| {
            current = n;
        }
        base = b.next;
    }

    return res;
}

export fn arcan_video_linkobjs(
    srcid: arcan_vobj_id,
    parentid: arcan_vobj_id,
    mask: c_uint,
    anchorp: c.enum_parent_anchor,
    scalem: c.enum_parent_scale,
) arcan_errc {
    const src = arcan_video_getobject(srcid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    var dst = arcan_video_getobject(parentid);

    // link to self always means link to world
    if (srcid == parentid or parentid == 0)
        dst = &current_context.world;

    const d = dst orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    // traverse destination and make sure we don't create cycles
    var cur: ?*arcan_vobject = d;
    while (cur) |cu| {
        if (cu.parent == src)
            return c.ARCAN_ERRC_CLONE_NOT_PERMITTED;
        cur = cu.parent;
    }

    // update anchor, mask and scale
    src.p_anchor = anchorp;
    src.mask = @bitCast(mask);
    src.p_scale = scalem;
    src.valid_cache = false;

    // already linked to dst? do nothing
    if (src.parent == d)
        return ARCAN_OK;

    // otherwise, first decrement parent counter
    if (src.parent != &current_context.world)
        dropchild(src.parent.?, src);

    // create link connection
    if (d != &current_context.world) {
        addchild(d, src);
    }

    if (flTest(src, c.FL_ORDOFS))
        _ = update_zv(src, @as(*arcan_vobject, @ptrCast(src.parent)).order);

    // reset all transformations except blend
    swipe_chain(src.transform, @offsetOf(c.struct_surface_transform, "move"), @sizeOf(c.struct_transf_move));
    swipe_chain(src.transform, @offsetOf(c.struct_surface_transform, "scale"), @sizeOf(c.struct_transf_scale));
    swipe_chain(src.transform, @offsetOf(c.struct_surface_transform, "rotate"), @sizeOf(c.struct_transf_rotate));

    invalidate_cache(d);
    flagDirty(null);

    return ARCAN_OK;
}

export fn arcan_video_init(
    width: u16,
    height: u16,
    bpp: u8,
    fs: bool,
    frames: bool,
    conservative: bool,
    caption: [*c]const u8,
) arcan_errc {
    const S = struct {
        var firstinit: bool = true;
    };

    if (S.firstinit) {
        if (c.arcan_sem_init(&asynchsynch, ASYNCH_CONCURRENT_THREADS) == -1) {
            c.arcan_warning("video_init couldn't create synchronization handle\n");
        }

        arcan_vint_defaultmapping(&arcan_video_display.default_txcos, 1.0, 1.0);
        arcan_vint_defaultmapping(&arcan_video_display.cursor_txcos, 1.0, 1.0);
        arcan_vint_mirrormapping(&arcan_video_display.mirror_txcos, 1.0, 1.0);
        c.arcan_video_reset_fontcache();
        S.firstinit = false;

        var tag: usize = 0;
        const get_config = c.platform_config_lookup(&tag);
        if (get_config) |gcfn| {
            var _outbuf: [*c]u8 = null;
            if (gcfn("video_ignore_dirty", 0, &_outbuf, tag)) {
                arcan_video_display.ignore_dirty = std.math.maxInt(usize) >> 1;
            }
        }
    }

    if (!c.platform_video_init(width, height, bpp, fs, frames, caption)) {
        c.arcan_warning("platform_video_init() failed.\n");
        return c.ARCAN_ERRC_BADVMODE;
    }
    _ = trace_stderr("video_init: platform OK, calling agp_init\n");

    c.agp_init();
    _ = trace_stderr("video_init: agp_init OK\n");

    arcan_video_display.in_video = true;
    arcan_video_display.conservative = conservative;

    sp(&current_context.world.current).scale.x = 1.0;
    sp(&current_context.world.current).scale.y = 1.0;
    current_context.vitem_limit = arcan_video_display.default_vitemlim;
    current_context.vitems_pool = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @sizeOf(arcan_vobject) * current_context.vitem_limit,
        c.ARCAN_MEM_VSTRUCT,
        c.ARCAN_MEM_BZERO,
        c.ARCAN_MEMALIGN_NATURAL,
    )));

    const mode = c.platform_video_dimensions();
    if (mode.width == 0 or mode.height == 0) {
        c.arcan_fatal("(video) platform error, invalid default mode\n");
    }
    _ = trace_stderr("video_init: dimensions OK, resize_canvas\n");
    _ = arcan_video_resize_canvas(mode.width, mode.height);
    _ = trace_stderr("video_init: resize_canvas OK\n");

    c.identity_matrix(&current_context.stdoutp.base);
    current_context.stdoutp.order3d = arcan_video_display.order3d;
    current_context.stdoutp.refreshcnt = 1;
    current_context.stdoutp.refresh = -1;
    current_context.stdoutp.max_order = 65536;
    current_context.stdoutp.shid = c.agp_default_shader(c.BASIC_2D);
    current_context.stdoutp.vppcm = current_context.stdoutp.hppcm;

    c.arcan_renderfun_outputdensity(
        current_context.stdoutp.hppcm,
        current_context.stdoutp.vppcm,
    );

    flagDirty(null);
    return ARCAN_OK;
}

export fn arcan_video_resize_canvas(neww: usize, newh: usize) arcan_errc {
    const mode = c.platform_video_dimensions();

    trace_stderr("resize_canvas: entry\n");
    if (!arcan_video_display.no_stdout) {
        if (current_context.world.vstore == null or current_context.stdoutp.art == null) {
            populate_vstore(&current_context.world.vstore);
            trace_stderr("resize_canvas: vstore populated\n");
            @as(*agp_vstore, @ptrCast(current_context.world.vstore)).filtermode &= @truncate(~@as(c_uint, c.ARCAN_VFILTER_MIPMAP));
            c.agp_empty_vstore(current_context.world.vstore, neww, newh);
            trace_stderr("resize_canvas: empty_vstore OK\n");
            current_context.stdoutp.color = &current_context.world;
            current_context.stdoutp.mode = c.RENDERTARGET_COLOR_DEPTH_STENCIL;
            current_context.stdoutp.art = c.agp_setup_rendertarget(
                current_context.world.vstore,
                current_context.stdoutp.mode,
            );
            trace_stderr("resize_canvas: setup_rendertarget OK\n");
        } else {
            c.agp_resize_rendertarget(current_context.stdoutp.art, neww, newh);
        }
    }

    c.build_orthographic_matrix(
        &arcan_video_display.window_projection,
        0,
        @floatFromInt(mode.width),
        @floatFromInt(mode.height),
        0,
        0,
        1,
    );

    c.build_orthographic_matrix(
        &arcan_video_display.default_projection,
        0,
        @floatFromInt(mode.width),
        @floatFromInt(mode.height),
        0,
        0,
        1,
    );

    const proj_src: [*]const u8 = @ptrCast(&arcan_video_display.default_projection);
    const proj_dst: [*]u8 = @ptrCast(&current_context.stdoutp.projection);
    @memcpy(proj_dst[0 .. @sizeOf(f32) * 16], proj_src[0 .. @sizeOf(f32) * 16]);

    current_context.world.origw = @intCast(neww);
    current_context.world.origh = @intCast(newh);

    flagDirty(null);
    _ = c.arcan_video_forceupdate(ARCAN_VIDEO_WORLDID, true);

    return ARCAN_OK;
}

fn nexthigher(k_in: u16) u16 {
    var k = k_in -% 1;
    var i: u5 = 1;
    while (i < 16) : (i *= 2) {
        k = k | (k >> @as(u4, @truncate(i)));
    }
    return k +% 1;
}

export fn arcan_vint_getimage(
    fname: [*c]const u8,
    dst: *arcan_vobject,
    forced_in: img_cons,
    asynchsrc: bool,
) arcan_errc {
    _ = c.arcan_sem_wait(asynchsynch);

    var inw: usize = 0;
    var inh: usize = 0;

    // try-open
    var inres = c.arcan_open_resource(fname);
    if (inres.fd == c.BADFD) {
        _ = c.arcan_sem_post(asynchsynch);
        return c.ARCAN_ERRC_BAD_RESOURCE;
    }

    // mmap or buffer
    const inmem = c.arcan_map_resource(&inres, false);
    if (inmem.unnamed_0.ptr == null) {
        _ = c.arcan_sem_post(asynchsynch);
        c.arcan_release_resource(&inres);
        return c.ARCAN_ERRC_BAD_RESOURCE;
    }

    var meta: c.struct_arcan_img_meta = std.mem.zeroes(c.struct_arcan_img_meta);
    var ch_imgbuf: [*c]u32 = null;

    var rv = c.arcan_img_decode(
        fname,
        inmem.unnamed_0.ptr,
        inmem.sz,
        &ch_imgbuf,
        &inw,
        &inh,
        &meta,
        @as(*agp_vstore, @ptrCast(dst.vstore)).imageproc == c.IMAGEPROC_FLIPH,
    );

    _ = c.arcan_release_map(inmem);
    c.arcan_release_resource(&inres);

    done: {
        push_comp: {
            if (rv != ARCAN_OK)
                break :done;

            const imgbuf_raw = c.arcan_img_repack(ch_imgbuf, inw, inh);
            if (imgbuf_raw == null) {
                rv = c.ARCAN_ERRC_OUT_OF_SPACE;
                break :done;
            }
            const imgbuf: [*c]av_pixel = @ptrCast(imgbuf_raw);

            var neww: u16 = @intCast(inw);
            var newh: u16 = @intCast(inh);

            dst.origw = @intCast(inw);
            dst.origh = @intCast(inh);

            if (!asynchsrc)
                dst.feed.state.tag = c.ARCAN_TAG_IMAGE;

            const dstframe: *agp_vstore = @ptrCast(dst.vstore);
            dstframe.vinf.text.unnamed_0.source = c.strdup(fname);

            var forced = forced_in;
            const desm = @as(*agp_vstore, @ptrCast(dst.vstore)).scale;

            if (meta.compressed)
                break :push_comp;

            if (desm == c.ARCAN_VIMAGE_SCALEPOW2) {
                forced.w = if (nexthigher(neww) == neww) 0 else nexthigher(neww);
                forced.h = if (nexthigher(newh) == newh) 0 else nexthigher(newh);
            }

            if (forced.h > 0 and forced.w > 0) {
                neww = if (desm == c.ARCAN_VIMAGE_SCALEPOW2) nexthigher(@intCast(forced.w)) else @intCast(forced.w);
                newh = if (desm == c.ARCAN_VIMAGE_SCALEPOW2) nexthigher(@intCast(forced.h)) else @intCast(forced.h);
                dst.origw = @intCast(forced.w);
                dst.origh = @intCast(forced.h);

                dstframe.vinf.text.s_raw = @as(u32, @intCast(neww)) * @as(u32, @intCast(newh)) * @sizeOf(av_pixel);
                dstframe.vinf.text.raw = @ptrCast(@alignCast(c.arcan_alloc_mem(
                    dstframe.vinf.text.s_raw,
                    c.ARCAN_MEM_VBUFFER,
                    0,
                    c.ARCAN_MEMALIGN_PAGE,
                )));

                _ = c.arcan_renderfun_stretchblit(
                    @ptrCast(imgbuf),
                    @intCast(inw),
                    @intCast(inh),
                    @ptrCast(dstframe.vinf.text.raw),
                    neww,
                    newh,
                    @intFromBool(@as(*agp_vstore, @ptrCast(dst.vstore)).imageproc == c.IMAGEPROC_FLIPH),
                );
                c.arcan_mem_free(@ptrCast(imgbuf));
            } else {
                neww = @intCast(inw);
                newh = @intCast(inh);
                dstframe.vinf.text.raw = @ptrCast(imgbuf);
                dstframe.vinf.text.s_raw = @intCast(inw * inh * @sizeOf(av_pixel));
            }

            @as(*agp_vstore, @ptrCast(dst.vstore)).w = neww;
            @as(*agp_vstore, @ptrCast(dst.vstore)).h = newh;
        }
        // push_comp fallthrough
        if (!asynchsrc and @as(*agp_vstore, @ptrCast(dst.vstore)).txmapped != c.TXSTATE_OFF)
            c.agp_update_vstore(dst.vstore, true);
    }
    // done
    _ = c.arcan_sem_post(asynchsynch);
    return rv;
}

export fn arcan_video_3dorder(order: c.arcan_order3d, rt: arcan_vobj_id) arcan_errc {
    if (rt != ARCAN_EID) {
        const vobj = arcan_video_getobject(rt) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
        const rtgt = arcan_vint_findrt(vobj) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
        rtgt.order3d = order;
    } else {
        arcan_video_display.order3d = order;
    }
    return ARCAN_OK;
}

fn rescale_origwh(dst: *arcan_vobject, fx: f32, fy: f32) void {
    var current: ?*surface_transform = @ptrCast(dst.transform);
    while (current) |cur| {
        cur.scale.startd.unnamed_0.unnamed_0.x *= fx;
        cur.scale.startd.unnamed_0.unnamed_0.y *= fy;
        cur.scale.endd.unnamed_0.unnamed_0.x *= fx;
        cur.scale.endd.unnamed_0.unnamed_0.y *= fy;
        current = @ptrCast(cur.next);
    }
}

export fn arcan_video_framecyclemode(id: arcan_vobj_id, mode: c_int) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (vobj.frameset == null) return c.ARCAN_ERRC_UNACCEPTED_STATE;
    const fs: *c.vobject_frameset = @ptrCast(vobj.frameset);
    const abs_mode = if (mode < 0) -mode else mode;
    fs.ctr = @intCast(abs_mode);
    fs.mctr = @intCast(abs_mode);
    return ARCAN_OK;
}

export fn arcan_video_cursorpos(newx: c_int, newy: c_int, absolute: bool) void {
    if (absolute) {
        arcan_video_display.cursor.x = newx;
        arcan_video_display.cursor.y = newy;
    } else {
        arcan_video_display.cursor.x += newx;
        arcan_video_display.cursor.y += newy;
    }
}

export fn arcan_video_cursorsize(w: usize, h: usize) void {
    arcan_video_display.cursor.w = w;
    arcan_video_display.cursor.h = h;
}

export fn arcan_video_cursorstore(src: arcan_vobj_id) void {
    if (arcan_video_display.cursor.vstore != null) {
        arcan_vint_drop_vstore(arcan_video_display.cursor.vstore);
        arcan_video_display.cursor.vstore = null;
    }

    const vobj = arcan_video_getobject(src) orelse return;
    if (src == ARCAN_VIDEO_WORLDID or @as(*agp_vstore, @ptrCast(vobj.vstore)).txmapped != c.TXSTATE_TEX2D)
        return;

    arcan_video_display.cursor.vstore = vobj.vstore;
    @as(*agp_vstore, @ptrCast(vobj.vstore)).refcount += 1;
}

export fn arcan_video_shareglstore(sid: arcan_vobj_id, did: arcan_vobj_id) arcan_errc {
    const src = arcan_video_getobject(sid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const dst = arcan_video_getobject(did) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (src == dst) return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    // remove the original target store
    arcan_vint_drop_vstore(dst.vstore);

    const rtgt = arcan_vint_findrt(dst);

    // if the source is broken, convert dst to null store
    if (@as(*agp_vstore, @ptrCast(src.vstore)).txmapped == c.TXSTATE_OFF or
        flTest(src, c.FL_PRSIST) or
        flTest(dst, c.FL_PRSIST))
    {
        // but leave rendertarget vstore alone
        if (rtgt != null)
            return ARCAN_OK;

        populate_vstore(&dst.vstore);
        const store: *agp_vstore = @ptrCast(dst.vstore);
        store.txmapped = c.TXSTATE_OFF;
        store.vinf.col = @as(*agp_vstore, @ptrCast(src.vstore)).vinf.col;
        dst.program = src.program;

        flagDirty(dst);
        return ARCAN_OK;
    }

    dst.vstore = src.vstore;
    @as(*agp_vstore, @ptrCast(dst.vstore)).refcount += 1;

    // customized texture coordinates
    if (src.txcos != null) {
        if (dst.txcos == null) {
            dst.txcos = @ptrCast(@alignCast(c.arcan_alloc_mem(
                8 * @sizeOf(f32),
                c.ARCAN_MEM_VSTRUCT,
                0,
                c.ARCAN_MEMALIGN_SIMD,
            )));
        }
        const dst_sl: [*]u8 = @ptrCast(dst.txcos);
        const src_sl: [*]const u8 = @ptrCast(src.txcos);
        @memcpy(dst_sl[0 .. @sizeOf(f32) * 8], src_sl[0 .. @sizeOf(f32) * 8]);
    } else if (dst.txcos != null) {
        c.arcan_mem_free(@ptrCast(dst.txcos));
        dst.txcos = null;
    }

    // for rendertarget, rebuild with new store
    if (rtgt) |rt| {
        c.agp_drop_rendertarget(rt.art);
        rt.art = c.agp_setup_rendertarget(@as(*arcan_vobject, @ptrCast(rt.color)).vstore, rt.mode);
        _ = c.arcan_video_forceupdate(did, true);
    }

    flagDirty(dst);
    return ARCAN_OK;
}

export fn arcan_video_solidcolor(
    origw: f32,
    origh: f32,
    r: u8,
    g_val: u8,
    b: u8,
    zv: c_ushort,
) arcan_vobj_id {
    var rv: arcan_vobj_id = ARCAN_EID;
    const newvobj = arcan_video_newvobject(&rv) orelse return rv;

    @as(*agp_vstore, @ptrCast(newvobj.vstore)).txmapped = c.TXSTATE_OFF;
    @as(*agp_vstore, @ptrCast(newvobj.vstore)).vinf.col.r = @as(f32, @floatFromInt(r)) / 255.0;
    @as(*agp_vstore, @ptrCast(newvobj.vstore)).vinf.col.g = @as(f32, @floatFromInt(g_val)) / 255.0;
    @as(*agp_vstore, @ptrCast(newvobj.vstore)).vinf.col.b = @as(f32, @floatFromInt(b)) / 255.0;

    newvobj.program = c.agp_default_shader(c.COLOR_2D);

    newvobj.origw = @intFromFloat(origw);
    newvobj.origh = @intFromFloat(origh);
    newvobj.order = @intCast(zv);

    _ = arcan_vint_attachobject(rv);

    return rv;
}

export fn arcan_video_nullobject(origw: f32, origh: f32, zv: c_ushort) arcan_vobj_id {
    const rv = arcan_video_solidcolor(origw, origh, 0, 0, 0, zv);
    if (arcan_video_getobject(rv)) |vobj| {
        vobj.program = 0;
    }
    return rv;
}

export fn arcan_video_rawobject(
    buf: [*c]av_pixel,
    cons: img_cons,
    origw: f32,
    origh: f32,
    zv: c_ushort,
) arcan_vobj_id {
    var rv: arcan_vobj_id = ARCAN_EID;
    const bufs = cons.w * cons.h * cons.bpp;

    if (cons.bpp != @sizeOf(av_pixel))
        return ARCAN_EID;

    const newvobj = arcan_video_newvobject(&rv) orelse return ARCAN_EID;
    const ds: *agp_vstore = @ptrCast(newvobj.vstore);

    if (buf == null) {
        ds.vinf.text.s_raw = @intCast(cons.w * cons.h * @sizeOf(av_pixel));
        ds.vinf.text.raw = @ptrCast(@alignCast(c.arcan_alloc_mem(
            ds.vinf.text.s_raw,
            c.ARCAN_MEM_VBUFFER,
            c.ARCAN_MEM_BZERO,
            c.ARCAN_MEMALIGN_PAGE,
        )));
    } else {
        ds.vinf.text.s_raw = @intCast(bufs);
        ds.vinf.text.raw = @ptrCast(buf);
    }

    ds.w = @intCast(cons.w);
    ds.h = @intCast(cons.h);
    ds.bpp = @intCast(cons.bpp);
    ds.txmapped = c.TXSTATE_TEX2D;

    newvobj.origw = @intFromFloat(origw);
    newvobj.origh = @intFromFloat(origh);
    newvobj.order = @intCast(zv);

    c.agp_update_vstore(newvobj.vstore, true);
    _ = arcan_vint_attachobject(rv);

    return rv;
}

export fn arcan_video_rendertargetdensity(
    src: arcan_vobj_id,
    vppcm_in: f32,
    hppcm_in: f32,
    reraster: bool,
    rescale: bool,
) arcan_errc {
    const srcobj = arcan_video_getobject(src) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const rtgt = arcan_vint_findrt(srcobj) orelse return c.ARCAN_ERRC_UNACCEPTED_STATE;

    var vppcm = vppcm_in;
    var hppcm = hppcm_in;

    if (vppcm < EPSILON) vppcm = rtgt.vppcm;
    if (hppcm < EPSILON) hppcm = rtgt.hppcm;

    if (rtgt.vppcm == vppcm and rtgt.hppcm == hppcm)
        return ARCAN_OK;

    // reflect the new changes
    const sfx = hppcm / rtgt.hppcm;
    const sfy = vppcm / rtgt.vppcm;
    c.arcan_renderfun_outputdensity(rtgt.hppcm, rtgt.vppcm);

    rtgt.vppcm = vppcm;
    rtgt.hppcm = hppcm;

    var cent: ?*arcan_vobject_litem = @ptrCast(rtgt.first);
    while (cent) |ce| {
        if (ce.elem == null) { cent = @ptrCast(ce.next); continue; }
        const vobj: *arcan_vobject = @ptrCast(ce.elem);
        if (vobj.owner != rtgt) {
            cent = @ptrCast(ce.next);
            continue;
        }

        if (reraster)
            arcan_vint_reraster(vobj, rtgt);

        if (rescale) {
            _ = @as(f32, @floatFromInt(vobj.origw)) * sp(&vobj.current).scale.x;
            _ = @as(f32, @floatFromInt(vobj.origh)) * sp(&vobj.current).scale.y;
            rescale_origwh(
                vobj,
                sfx / sp(&vobj.current).scale.x,
                sfy / sp(&vobj.current).scale.y,
            );
            invalidate_cache(vobj);
        }
        cent = @ptrCast(ce.next);
    }

    flagDirty(srcobj);
    return ARCAN_OK;
}

export fn arcan_video_detachfromrendertarget(did: arcan_vobj_id, src: arcan_vobj_id) arcan_errc {
    const srcobj = arcan_video_getobject(src) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    _ = arcan_video_getobject(did) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const dstobj = arcan_video_getobject(did).?;

    if (&current_context.stdoutp == srcobj.owner) {
        _ = detach_fromtarget(&current_context.stdoutp, srcobj);
        return ARCAN_OK;
    }

    var ind: usize = 0;
    while (ind < @as(usize, @intCast(current_context.n_rtargets))) : (ind += 1) {
        if (current_context.rtargets[ind].color == dstobj and
            srcobj.owner != &current_context.rtargets[ind])
        {
            _ = detach_fromtarget(&current_context.rtargets[ind], srcobj);
        }
    }

    return ARCAN_OK;
}

export fn arcan_video_attachtorendertarget(
    did: arcan_vobj_id,
    src: arcan_vobj_id,
    detach: bool,
) arcan_errc {
    if (src == ARCAN_VIDEO_WORLDID) {
        c.arcan_warning("arcan_video_attachtorendertarget(), WORLDID attach" ++
            " not directly supported, use a null-surface with " ++
            "shared storage instead.");
        return c.ARCAN_ERRC_UNACCEPTED_STATE;
    }

    const dstobj = arcan_video_getobject(did) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const srcobj = arcan_video_getobject(src) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (dstobj == srcobj) return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (flTest(dstobj, c.FL_PRSIST) or flTest(srcobj, c.FL_PRSIST))
        return c.ARCAN_ERRC_UNACCEPTED_STATE;

    if (current_context.stdoutp.color == dstobj) {
        if (srcobj.owner != null and detach)
            _ = detach_fromtarget(srcobj.owner, srcobj);

        _ = detach_fromtarget(&current_context.stdoutp, srcobj);
        attach_object(&current_context.stdoutp, srcobj);
        return ARCAN_OK;
    }

    // linear search for rendertarget matching the destination id
    var ind: usize = 0;
    while (ind < @as(usize, @intCast(current_context.n_rtargets))) : (ind += 1) {
        if (current_context.rtargets[ind].color == dstobj) {
            if (srcobj.owner != null and detach)
                _ = detach_fromtarget(srcobj.owner, srcobj);

            _ = detach_fromtarget(&current_context.rtargets[ind], srcobj);
            attach_object(&current_context.rtargets[ind], srcobj);
            return ARCAN_OK;
        }
    }

    return c.ARCAN_ERRC_BAD_ARGUMENT;
}

export fn arcan_video_defaultattachment(src: arcan_vobj_id) arcan_errc {
    if (src == ARCAN_EID)
        return c.ARCAN_ERRC_BAD_ARGUMENT;

    const vobj = arcan_video_getobject(src) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const rtgt = arcan_vint_findrt(vobj) orelse return c.ARCAN_ERRC_UNACCEPTED_STATE;

    current_context.attachment = rtgt;
    return ARCAN_OK;
}

export fn arcan_video_alterreadback(did: arcan_vobj_id, readback: c_int) arcan_errc {
    if (did == ARCAN_VIDEO_WORLDID) {
        current_context.stdoutp.readback = readback;
        return ARCAN_OK;
    }

    const vobj = arcan_video_getobject(did) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const rtgt = arcan_vint_findrt(vobj) orelse return c.ARCAN_ERRC_UNACCEPTED_STATE;

    rtgt.readback = readback;
    rtgt.readcnt = if (readback < 0) -readback else readback;
    return ARCAN_OK;
}

export fn arcan_video_rendertarget_range(
    did: arcan_vobj_id,
    min_in: isize,
    max_in: isize,
) arcan_errc {
    var rtgt: ?*rendertarget = null;

    if (did == ARCAN_VIDEO_WORLDID) {
        rtgt = &current_context.stdoutp;
    } else {
        const vobj = arcan_video_getobject(did) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
        rtgt = arcan_vint_findrt(vobj);
    }

    const rt = rtgt orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    var min_val = min_in;
    var max_val = max_in;
    if (min_val < 0 or max_val < min_val) {
        min_val = 0;
        max_val = 65536;
    }

    rt.min_order = @intCast(min_val);
    rt.max_order = @intCast(max_val);

    return ARCAN_OK;
}

export fn arcan_video_rendertarget_setnoclear(did: arcan_vobj_id, value: bool) arcan_errc {
    var rtgt: ?*rendertarget = null;

    if (did == ARCAN_VIDEO_WORLDID) {
        rtgt = &current_context.stdoutp;
    } else {
        const vobj = arcan_video_getobject(did) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
        rtgt = arcan_vint_findrt(vobj);
    }

    const rt = rtgt orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (value)
        rtFlSet(rt, c.TGTFL_NOCLEAR)
    else
        rtFlClear(rt, c.TGTFL_NOCLEAR);

    return ARCAN_OK;
}

export fn arcan_video_linkrendertarget(
    did: arcan_vobj_id,
    tgt_id: arcan_vobj_id,
    refresh: c_int,
    scale: bool,
    format: c.enum_rendertarget_mode,
) arcan_errc {
    var vobj = arcan_video_getobject(tgt_id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const tgt = arcan_vint_findrt(vobj) orelse return c.ARCAN_ERRC_BAD_ARGUMENT;

    // this can be used to update the link state of an existing rendertarget
    // or to define a new one based on the pipeline of an existing one
    vobj = arcan_video_getobject(did) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    var newtgt = arcan_vint_findrt(vobj);
    if (newtgt == null) {
        const rv = arcan_video_setuprendertarget(did, 0, refresh, scale, format);
        if (rv != ARCAN_OK)
            return rv;

        newtgt = arcan_vint_findrt(vobj);
    }

    const nt = newtgt orelse return c.ARCAN_ERRC_BAD_ARGUMENT;
    if (nt == tgt) return c.ARCAN_ERRC_BAD_ARGUMENT;

    nt.link = tgt;
    return ARCAN_OK;
}

export fn arcan_video_setuprendertarget(
    did: arcan_vobj_id,
    readback: c_int,
    refresh: c_int,
    scale: bool,
    format: c.enum_rendertarget_mode,
) arcan_errc {
    const vobj = arcan_video_getobject(did) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (arcan_vint_findrt(vobj) != null) {
        c.arcan_warning("arcan_video_setuprendertarget() source vid" ++
            " already is a rendertarget\n");
        return c.ARCAN_ERRC_BAD_ARGUMENT;
    }

    if (current_context.n_rtargets >= RENDERTARGET_LIMIT)
        return c.ARCAN_ERRC_OUT_OF_SPACE;

    const ind: usize = @intCast(current_context.n_rtargets);
    current_context.n_rtargets += 1;
    const dst = &current_context.rtargets[ind];
    dst.* = std.mem.zeroes(rendertarget);

    flSet(vobj, c.FL_RTGT);
    rtFlSet(dst, c.TGTFL_ALIVE);
    dst.color = vobj;
    dst.camtag = ARCAN_EID;
    dst.readback = readback;
    dst.readcnt = if (readback < 0) -readback else readback;
    dst.refresh = refresh;
    dst.refreshcnt = if (refresh < 0) -refresh else refresh;
    dst.art = c.agp_setup_rendertarget(vobj.vstore, format);
    dst.shid = c.agp_default_shader(c.BASIC_2D);
    dst.mode = format;
    dst.order3d = arcan_video_display.order3d;
    dst.vppcm = 28.346456692913385;
    dst.hppcm = 28.346456692913385;
    dst.min_order = 0;
    dst.max_order = 65536;

    const S = struct {
        var id: c_int = 0;
    };
    S.id = @rem(S.id + 1, std.math.maxInt(c_int) - 1);
    dst.id = S.id;

    vobj.extrefc.attachments += 1;

    // alter projection so the GL texture gets stored correctly
    c.build_orthographic_matrix(
        &dst.projection,
        0,
        @floatFromInt(vobj.origw),
        0,
        @floatFromInt(vobj.origh),
        0,
        1,
    );
    c.identity_matrix(&dst.base);

    const mode = c.platform_video_dimensions();
    if (scale) {
        const xs = @as(f32, @floatFromInt(@as(*agp_vstore, @ptrCast(vobj.vstore)).w)) / @as(f32, @floatFromInt(mode.width));
        const ys = @as(f32, @floatFromInt(@as(*agp_vstore, @ptrCast(vobj.vstore)).h)) / @as(f32, @floatFromInt(mode.height));
        c.scale_matrix(&dst.base, xs, ys, 1.0);
    }

    return ARCAN_OK;
}

export fn arcan_video_setactiveframe(dst: arcan_vobj_id, fid: c_uint) arcan_errc {
    const dstvobj = arcan_video_getobject(dst) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (dstvobj.frameset == null) return c.ARCAN_ERRC_UNACCEPTED_STATE;
    const fs: *c.vobject_frameset = @ptrCast(dstvobj.frameset);

    fs.index = if (fid < fs.n_frames) @intCast(fid) else 0;

    flagDirty(dstvobj);
    return ARCAN_OK;
}

export fn arcan_video_setasframe(
    dst: arcan_vobj_id,
    src: arcan_vobj_id,
    fid: usize,
) arcan_errc {
    const dstvobj = arcan_video_getobject(dst) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const srcvobj = arcan_video_getobject(src) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (dstvobj.frameset == null or @as(*agp_vstore, @ptrCast(srcvobj.vstore)).txmapped != c.TXSTATE_TEX2D)
        return c.ARCAN_ERRC_UNACCEPTED_STATE;

    const fs: *c.vobject_frameset = @ptrCast(dstvobj.frameset);
    if (fid >= fs.n_frames)
        return c.ARCAN_ERRC_BAD_ARGUMENT;

    const store = &fs.frames[fid];
    if (store.frame != srcvobj.vstore) {
        arcan_vint_drop_vstore(store.frame);
        store.frame = srcvobj.vstore;
    }

    if (srcvobj.txcos != null) {
        const dst_sl: [*]u8 = @ptrCast(&store.txcos);
        const src_sl: [*]const u8 = @ptrCast(srcvobj.txcos);
        @memcpy(dst_sl[0 .. @sizeOf(f32) * 8], src_sl[0 .. @sizeOf(f32) * 8]);
    } else {
        arcan_vint_defaultmapping(&store.txcos, 1.0, 1.0);
    }

    @as(*agp_vstore, @ptrCast(store.frame)).refcount += 1;

    return ARCAN_OK;
}

const thread_loader_args = extern struct {
    dst: ?*arcan_vobject,
    self: c.pthread_t,
    dstid: arcan_vobj_id,
    fname: [*c]u8,
    tag: isize,
    constraints: img_cons,
    rc: arcan_errc,
};

fn thread_loader(in: ?*anyopaque) callconv(.c) ?*anyopaque {
    const largs: *thread_loader_args = @ptrCast(@alignCast(in));
    const dst = largs.dst.?;
    largs.rc = arcan_vint_getimage(largs.fname, dst, largs.constraints, true);
    dst.feed.state.tag = c.ARCAN_TAG_ASYNCIMGRD;
    return null;
}

export fn arcan_vint_joinasynch(img: *arcan_vobject, emit: bool, force: bool) void {
    if (!force and img.feed.state.tag != c.ARCAN_TAG_ASYNCIMGRD) {
        return;
    }

    if (img.feed.state.ptr == null) return;
    const args: *thread_loader_args = @ptrCast(@alignCast(img.feed.state.ptr));

    _ = c.pthread_join(args.self, null);

    var loadev: c.arcan_event = c.arcan_event.zeroes();
    loadev.unnamed_0.unnamed_0.category = c.EVENT_VIDEO;
    loadev.unnamed_0.unnamed_0.unnamed_0.vid.data = args.tag;
    loadev.unnamed_0.unnamed_0.unnamed_0.vid.source = args.dstid;

    if (args.rc == ARCAN_OK) {
        loadev.unnamed_0.unnamed_0.unnamed_0.vid.kind = c.EVENT_VIDEO_ASYNCHIMAGE_LOADED;
        loadev.unnamed_0.unnamed_0.unnamed_0.vid.unnamed_0.unnamed_0.width = @intCast(img.origw);
        loadev.unnamed_0.unnamed_0.unnamed_0.vid.unnamed_0.unnamed_0.height = @intCast(img.origh);
    } else {
        // copy broken placeholder
        img.origw = 32;
        img.origh = 32;
        @as(*agp_vstore, @ptrCast(img.vstore)).vinf.text.s_raw = 32 * 32 * @sizeOf(av_pixel);
        @as(*agp_vstore, @ptrCast(img.vstore)).vinf.text.raw = @ptrCast(@alignCast(c.arcan_alloc_mem(
            @as(*agp_vstore, @ptrCast(img.vstore)).vinf.text.s_raw,
            c.ARCAN_MEM_VBUFFER,
            c.ARCAN_MEM_BZERO,
            c.ARCAN_MEMALIGN_PAGE,
        )));

        @as(*agp_vstore, @ptrCast(img.vstore)).w = 32;
        @as(*agp_vstore, @ptrCast(img.vstore)).h = 32;
        @as(*agp_vstore, @ptrCast(img.vstore)).vinf.text.unnamed_0.source = c.strdup(args.fname);
        @as(*agp_vstore, @ptrCast(img.vstore)).filtermode = @intCast(c.ARCAN_VFILTER_NONE);

        loadev.unnamed_0.unnamed_0.unnamed_0.vid.unnamed_0.unnamed_0.width = 32;
        loadev.unnamed_0.unnamed_0.unnamed_0.vid.unnamed_0.unnamed_0.height = 32;
        loadev.unnamed_0.unnamed_0.unnamed_0.vid.kind = c.EVENT_VIDEO_ASYNCHIMAGE_FAILED;
    }

    c.agp_update_vstore(img.vstore, true);

    if (emit)
        _ = c.arcan_event_enqueue(c.arcan_event_defaultctx(), &loadev);

    c.arcan_mem_free(@ptrCast(args.fname));
    c.arcan_mem_free(@ptrCast(args));
    img.feed.state.ptr = null;
    img.feed.state.tag = c.ARCAN_TAG_IMAGE;
}

fn loadimage_asynch(fname: [*c]const u8, constraints: img_cons, tag: isize) arcan_vobj_id {
    var rv: arcan_vobj_id = ARCAN_EID;
    const dstobj = arcan_video_newvobject(&rv) orelse return rv;

    const args: *thread_loader_args = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @sizeOf(thread_loader_args),
        c.ARCAN_MEM_THREADCTX,
        0,
        c.ARCAN_MEMALIGN_NATURAL,
    )));

    args.dstid = rv;
    args.dst = dstobj;
    args.fname = c.strdup(fname);
    args.tag = tag;
    args.constraints = constraints;

    dstobj.feed.state.tag = c.ARCAN_TAG_ASYNCIMGLD;
    dstobj.feed.state.ptr = @ptrCast(args);

    _ = c.pthread_create(&args.self, null, &thread_loader, @ptrCast(args));

    return rv;
}

export fn arcan_video_pushasynch(source: arcan_vobj_id) arcan_errc {
    const vobj = arcan_video_getobject(source) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.feed.state.tag == c.ARCAN_TAG_ASYNCIMGLD or
        vobj.feed.state.tag == c.ARCAN_TAG_ASYNCIMGRD)
    {
        arcan_vint_joinasynch(vobj, false, true);
    } else {
        return c.ARCAN_ERRC_UNACCEPTED_STATE;
    }

    return ARCAN_OK;
}

fn loadimage(fname: [*c]const u8, constraints: img_cons, errcode: ?*arcan_errc) arcan_vobj_id {
    var rv: arcan_vobj_id = 0;

    const newvobj = arcan_video_newvobject(&rv) orelse return ARCAN_EID;

    const rc = arcan_vint_getimage(fname, newvobj, constraints, false);

    if (rc != ARCAN_OK)
        _ = c.arcan_video_deleteobject(rv);

    if (errcode) |ec|
        ec.* = rc;

    return rv;
}

export fn arcan_video_feedstate(id: arcan_vobj_id) ?*vfunc_state {
    const vobj = arcan_video_getobject(id) orelse return null;
    if (id <= 0) return null;
    return &vobj.feed.state;
}

export fn arcan_video_alterfeed(id: arcan_vobj_id, cb: c.ffunc_ind, state: vfunc_state) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    vobj.feed.state = state;
    vobj.feed.ffunc = cb;
    return ARCAN_OK;
}

fn arcan_video_setupfeed(ffunc: c.ffunc_ind, cons: img_cons, ntus: u8, ncpt: u8) arcan_vobj_id {
    _ = ntus;
    if (ffunc == 0) return 0;

    var rv: arcan_vobj_id = 0;
    const newvobj = arcan_video_newvobject(&rv) orelse return ARCAN_EID;

    const vstor: *agp_vstore = @ptrCast(newvobj.vstore);
    newvobj.origw = @intCast(cons.w);
    newvobj.origh = @intCast(cons.h);
    vstor.bpp = if (ncpt == 0) @intCast(@sizeOf(av_pixel)) else ncpt;
    vstor.filtermode &= @truncate(~@as(c_uint, c.ARCAN_VFILTER_MIPMAP));

    if (vstor.scale == c.ARCAN_VIMAGE_NOPOW2) {
        vstor.w = @intCast(cons.w);
        vstor.h = @intCast(cons.h);
    } else {
        vstor.w = nexthigher(@intCast(cons.w));
        vstor.h = nexthigher(@intCast(cons.h));
        const hx = @as(f32, @floatFromInt(cons.w)) / @as(f32, @floatFromInt(vstor.w));
        const hy = @as(f32, @floatFromInt(cons.h)) / @as(f32, @floatFromInt(vstor.h));
        if (newvobj.txcos != null)
            arcan_vint_defaultmapping(newvobj.txcos, hx, hy);
    }

    // allocate
    vstor.vinf.text.s_raw = @intCast(@as(usize, @intCast(vstor.w)) *
        @as(usize, @intCast(vstor.h)) * @as(usize, @intCast(vstor.bpp)));
    vstor.vinf.text.raw = @ptrCast(@alignCast(c.arcan_alloc_mem(
        vstor.vinf.text.s_raw,
        c.ARCAN_MEM_VBUFFER,
        c.ARCAN_MEM_BZERO,
        c.ARCAN_MEMALIGN_PAGE,
    )));

    newvobj.feed.ffunc = ffunc;
    c.agp_update_vstore(newvobj.vstore, true);

    return rv;
}

export fn arcan_video_resizefeed(id: arcan_vobj_id, w: usize, h: usize) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.feed.state.tag == c.ARCAN_TAG_ASYNCIMGLD or
        vobj.feed.state.tag == c.ARCAN_TAG_ASYNCIMGRD)
    {
        _ = arcan_video_pushasynch(id);
    }

    // rescale transformation chain
    const ox = @as(f32, @floatFromInt(vobj.origw)) * sp(&vobj.current).scale.x;
    const oy = @as(f32, @floatFromInt(vobj.origh)) * sp(&vobj.current).scale.y;
    const sfx = ox / @as(f32, @floatFromInt(w));
    const sfy = oy / @as(f32, @floatFromInt(h));
    if (sp(&vobj.current).scale.x > 0 and sp(&vobj.current).scale.y > 0) {
        rescale_origwh(
            vobj,
            sfx / sp(&vobj.current).scale.x,
            sfy / sp(&vobj.current).scale.y,
        );
    }

    vobj.origw = @intCast(w);
    vobj.origh = @intCast(h);

    sp(&vobj.current).scale.x = sfx;
    sp(&vobj.current).scale.y = sfy;
    invalidate_cache(vobj);
    c.agp_resize_vstore(vobj.vstore, w, h);

    flagDirty(vobj);
    return ARCAN_OK;
}

export fn arcan_video_loadimageasynch(
    rloc: [*c]const u8,
    constraints: img_cons,
    tag: isize,
) arcan_vobj_id {
    const rv = loadimage_asynch(rloc, constraints, tag);

    if (rv > 0) {
        if (arcan_video_getobject(rv)) |vobj| {
            vobj.current.rotation.quaternion = c.default_quat;
            _ = arcan_vint_attachobject(rv);
        }
    }

    return rv;
}

export fn arcan_video_loadimage(
    rloc: [*c]const u8,
    constraints: img_cons,
    zv: c_ushort,
) arcan_vobj_id {
    const rv = loadimage(rloc, constraints, null);

    if (rv > 0) {
        if (arcan_video_getobject(rv)) |vobj| {
            vobj.order = @intCast(zv);
            vobj.current.rotation.quaternion = c.default_quat;
            _ = arcan_vint_attachobject(rv);
        }
    }

    return rv;
}

export fn arcan_video_addfobject(
    feed: c.ffunc_ind,
    state: vfunc_state,
    cons: img_cons,
    zv: c_ushort,
) arcan_vobj_id {
    var rv: arcan_vobj_id = undefined;
    const feed_ntus: u8 = 1;

    rv = arcan_video_setupfeed(feed, cons, feed_ntus, @intCast(cons.bpp));
    if (rv > 0) {
        const vobj = arcan_video_getobject(rv).?;
        vobj.order = @intCast(zv);
        vobj.feed.state = state;

        if (state.tag == c.ARCAN_TAG_3DOBJ) {
            flSet(vobj, c.FL_FULL3D);
            vobj.order *= -1;
        }

        _ = arcan_vint_attachobject(rv);
    }

    return rv;
}

export fn arcan_video_scaletxcos(id: arcan_vobj_id, sfs: f32, sft: f32) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.txcos == null) {
        vobj.txcos = @ptrCast(@alignCast(c.arcan_alloc_mem(
            8 * @sizeOf(f32),
            c.ARCAN_MEM_VSTRUCT,
            0,
            c.ARCAN_MEMALIGN_SIMD,
        )));
        if (vobj.txcos == null)
            return c.ARCAN_ERRC_OUT_OF_SPACE;

        arcan_vint_defaultmapping(vobj.txcos, 1.0, 1.0);
    }

    vobj.txcos[0] *= sfs;
    vobj.txcos[1] *= sft;
    vobj.txcos[2] *= sfs;
    vobj.txcos[3] *= sft;
    vobj.txcos[4] *= sfs;
    vobj.txcos[5] *= sft;
    vobj.txcos[6] *= sfs;
    vobj.txcos[7] *= sft;

    flagDirty(vobj);
    return ARCAN_OK;
}

// ============================================================
// Chunk: Transforms, animation, texture/frameset/shader
// ============================================================

// 1. arcan_video_forceblend
export fn arcan_video_forceblend(id: arcan_vobj_id, mode: c.arcan_blendfunc) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (id <= 0) return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    vobj.blendmode = mode;
    flagDirty(vobj);
    return ARCAN_OK;
}

// 2. update_zv (static, recursive)
fn update_zv(vobj: *arcan_vobject, newzv_in: c_int) arcan_errc {
    const owner = vobj.owner orelse return c.ARCAN_ERRC_UNACCEPTED_STATE;

    const newzv = std.math.clamp(newzv_in, 0, 65535);
    const oldv = vobj.order;

    _ = detach_fromtarget(owner, vobj);
    vobj.order = newzv;

    if (vobj.feed.state.tag == c.ARCAN_TAG_3DOBJ)
        vobj.order *= -1;

    attach_object(owner, vobj);

    var i: usize = 0;
    while (i < vobj.childslots) : (i += 1) {
        if (vobj.children[i] != null) {
            const child: *arcan_vobject = @ptrCast(vobj.children[i]);
            if (flTest(child, c.FL_ORDOFS)) {
                const distance = child.order - oldv;
                _ = update_zv(child, newzv + distance);
            }
        }
    }

    return ARCAN_OK;
}

// 3. arcan_video_setzv
export fn arcan_video_setzv(id: arcan_vobj_id, newzv_in: c_int) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    var newzv = newzv_in;
    if (flTest(vobj, c.FL_ORDOFS))
        newzv = newzv + @as(*arcan_vobject, @ptrCast(vobj.parent)).order;

    _ = update_zv(vobj, newzv);
    return ARCAN_OK;
}

// 4. arcan_video_setlife
export fn arcan_video_setlife(id: arcan_vobj_id, lifetime: c_uint) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (id <= 0) return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (lifetime == 0) {
        vobj.lifetime = -1;
    } else {
        vobj.mask |= @bitCast(@as(c_uint, c.MASK_LIVING));
    }

    vobj.lifetime = @intCast(lifetime);
    return ARCAN_OK;
}

// 5. emit_transform_event (static)
fn emit_transform_event(src: arcan_vobj_id, slot: c_uint, tag: isize) void {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_VIDEO;
    ev.unnamed_0.unnamed_0.unnamed_0.vid.kind = c.EVENT_VIDEO_CHAIN_OVER;
    ev.unnamed_0.unnamed_0.unnamed_0.vid.data = tag;
    ev.unnamed_0.unnamed_0.unnamed_0.vid.source = src;
    ev.unnamed_0.unnamed_0.unnamed_0.vid.unnamed_0.slot = @intCast(slot);
    _ = c.arcan_event_enqueue(c.arcan_event_defaultctx(), &ev);
}

// 6. arcan_video_zaptransform
export fn arcan_video_zaptransform(id: arcan_vobj_id, mask_in: c_int, left: [*c]c_uint) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    var current: ?*surface_transform = vobj.transform;
    var last: *?*surface_transform = &vobj.transform;

    const ct = arcan_video_display.c_ticks;

    // only set if the data is actually needed
    if (left != null) {
        if (current) |cur| {
            left[0] = if (ct > cur.blend.endt) 0 else cur.blend.endt - ct;
            left[1] = if (ct > cur.move.endt) 0 else cur.move.endt - ct;
            left[2] = if (ct > cur.rotate.endt) 0 else cur.rotate.endt - ct;
            left[3] = if (ct > cur.scale.endt) 0 else cur.scale.endt - ct;
        } else {
            left[0] = 4;
            left[1] = 4;
            left[2] = 4;
            left[3] = 4;
        }
    }

    // if mask is 0, zap entire chain (~0 = all bits set)
    const mask: c_uint = if (mask_in == 0) ~@as(c_uint, 0) else @as(c_uint, @intCast(mask_in));

    while (current) |cur| {
        // !!!x in C means: if (mask & MASK_X) then zero the field
        if (mask & c.MASK_OPACITY != 0) {
            cur.blend.endt = 0;
            cur.blend.startt = 0;
        }
        if (mask & c.MASK_POSITION != 0) {
            cur.move.endt = 0;
            cur.move.startt = 0;
        }
        if (mask & c.MASK_ORIENTATION != 0) {
            cur.rotate.endt = 0;
            cur.rotate.startt = 0;
        }
        if (mask & c.MASK_SCALE != 0) {
            cur.scale.endt = 0;
            cur.scale.startt = 0;
        }

        // any transform alive? then don't free the transform
        const used = (cur.blend.endt | cur.move.endt |
            cur.rotate.endt | cur.scale.endt) != 0;

        if (!used) {
            if (last.* == cur)
                last.* = cur.next;

            const next = cur.next;
            c.arcan_mem_free(@ptrCast(cur));
            current = next;
        } else {
            last = &cur.next;
            current = cur.next;
        }
    }

    invalidate_cache(vobj);
    return ARCAN_OK;
}

// 7. arcan_video_tagtransform
export fn arcan_video_tagtransform(id: arcan_vobj_id, tag: isize, mask_in: c_uint) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.transform == null)
        return c.ARCAN_ERRC_UNACCEPTED_STATE;

    if ((mask_in & ~@as(c_uint, c.MASK_TRANSFORMS)) > 0)
        return c.ARCAN_ERRC_BAD_ARGUMENT;

    var mask = mask_in;
    var current: ?*surface_transform = vobj.transform;

    while (current != null and mask > 0) {
        const cur = current.?;

        if ((mask & c.MASK_POSITION) > 0) {
            if (cur.move.startt != 0 and
                (cur.next == null or @as(*surface_transform, @ptrCast(cur.next)).move.startt == 0))
            {
                mask &= ~@as(c_uint, c.MASK_POSITION);
                cur.move.tag = tag;
            }
        }

        if ((mask & c.MASK_SCALE) > 0) {
            if (cur.scale.startt != 0 and
                (cur.next == null or @as(*surface_transform, @ptrCast(cur.next)).scale.startt == 0))
            {
                mask &= ~@as(c_uint, c.MASK_SCALE);
                cur.scale.tag = tag;
            }
        }

        if ((mask & c.MASK_ORIENTATION) > 0) {
            if (cur.rotate.startt != 0 and
                (cur.next == null or @as(*surface_transform, @ptrCast(cur.next)).rotate.startt == 0))
            {
                mask &= ~@as(c_uint, c.MASK_ORIENTATION);
                cur.rotate.tag = tag;
            }
        }

        if ((mask & c.MASK_OPACITY) > 0) {
            if (cur.blend.startt != 0 and
                (cur.next == null or @as(*surface_transform, @ptrCast(cur.next)).blend.startt == 0))
            {
                mask &= ~@as(c_uint, c.MASK_OPACITY);
                cur.blend.tag = tag;
            }
        }

        current = @ptrCast(cur.next);
    }

    return ARCAN_OK;
}

// 8. arcan_video_instanttransform
export fn arcan_video_instanttransform(id: arcan_vobj_id, mask_in: c_int, method: c.enum_tag_transform_methods) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.transform == null)
        return ARCAN_OK;

    var current: ?*surface_transform = vobj.transform;
    const mask: c_uint = if (mask_in == 0) ~@as(c_uint, 0) else @as(c_uint, @intCast(mask_in));

    var at_last: bool = undefined;
    var last: *?*surface_transform = &vobj.transform;

    while (current) |cur| {
        if (cur.move.startt != 0 and (mask & c.MASK_POSITION) != 0) {
            vobj.current.position = cur.move.endp;
            cur.move.startt = 0;

            at_last = (method == c.TAG_TRANSFORM_LAST) and
                !(cur.next != null and @as(*surface_transform, @ptrCast(cur.next)).move.startt != 0);

            if (cur.move.tag != 0 and (method == c.TAG_TRANSFORM_ALL or at_last))
                emit_transform_event(vobj.cellid, c.MASK_POSITION, cur.move.tag);
        }

        if (cur.blend.startt != 0 and (mask & c.MASK_OPACITY) != 0) {
            vobj.current.opa = cur.blend.endopa;
            cur.blend.startt = 0;

            at_last = (method == c.TAG_TRANSFORM_LAST) and
                !(cur.next != null and @as(*surface_transform, @ptrCast(cur.next)).blend.startt != 0);

            if (cur.blend.tag != 0 and (method == c.TAG_TRANSFORM_ALL or at_last))
                emit_transform_event(vobj.cellid, c.MASK_OPACITY, cur.blend.tag);
        }

        if (cur.rotate.startt != 0 and (mask & c.MASK_ORIENTATION) != 0) {
            vobj.current.rotation = cur.rotate.endo;
            cur.rotate.startt = 0;

            at_last = (method == c.TAG_TRANSFORM_LAST) and
                !(cur.next != null and @as(*surface_transform, @ptrCast(cur.next)).rotate.startt != 0);

            if (cur.rotate.tag != 0 and (method == c.TAG_TRANSFORM_LAST or at_last))
                emit_transform_event(vobj.cellid, c.MASK_ORIENTATION, cur.rotate.tag);
        }

        if (cur.scale.startt != 0 and (mask & c.MASK_SCALE) != 0) {
            vobj.current.scale = cur.scale.endd;
            cur.scale.startt = 0;

            at_last = (method == c.TAG_TRANSFORM_LAST) and
                !(cur.next != null and @as(*surface_transform, @ptrCast(cur.next)).scale.startt != 0);

            if (cur.scale.tag != 0 and (method == c.TAG_TRANSFORM_LAST or at_last))
                emit_transform_event(vobj.cellid, c.MASK_SCALE, cur.scale.tag);
        }

        // see also: zaptransform
        const used = (cur.blend.startt | cur.move.startt |
            cur.rotate.startt | cur.scale.startt) != 0;

        if (!used) {
            if (last.* == cur)
                last.* = cur.next;

            if (vobj.transform == cur)
                vobj.transform = cur.next;

            const tokill = cur;
            current = cur.next;
            c.arcan_mem_free(@ptrCast(tokill));
        } else {
            last = &cur.next;
            current = cur.next;
        }
    }

    invalidate_cache(vobj);
    return ARCAN_OK;
}

// 9. arcan_video_objecttexmode
export fn arcan_video_objecttexmode(id: arcan_vobj_id, modes: c_uint, modet: c_uint) arcan_errc {
    const src = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    @as(*agp_vstore, @ptrCast(src.vstore)).txu = @intCast(modes);
    @as(*agp_vstore, @ptrCast(src.vstore)).txv = @intCast(modet);
    c.agp_update_vstore(src.vstore, false);
    flagDirty(src);
    return ARCAN_OK;
}

// 10. arcan_video_objectfilter
export fn arcan_video_objectfilter(id: arcan_vobj_id, mode: c_uint) arcan_errc {
    const src = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    @as(*agp_vstore, @ptrCast(src.vstore)).filtermode = @intCast(mode);
    c.agp_update_vstore(src.vstore, false);
    return ARCAN_OK;
}

// 11. arcan_video_transformcycle
export fn arcan_video_transformcycle(sid: arcan_vobj_id, flag: bool) arcan_errc {
    const src = arcan_video_getobject(sid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (flag)
        flSet(src, c.FL_TCYCLE)
    else
        flClear(src, c.FL_TCYCLE);
    return ARCAN_OK;
}

// 12. arcan_video_copyprops
export fn arcan_video_copyprops(sid: arcan_vobj_id, did: arcan_vobj_id) arcan_errc {
    if (sid == did)
        return ARCAN_OK;

    const src = arcan_video_getobject(sid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const dst = arcan_video_getobject(did) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    var newprop: surface_properties = undefined;
    c.arcan_resolve_vidprop(src, 0.0, &newprop);

    dst.current = newprop;
    // translate scale
    if (sp(&newprop).scale.x > 0 and sp(&newprop).scale.y > 0) {
        const dstw: f32 = sp(&newprop).scale.x * @as(f32, @floatFromInt(src.origw));
        const dsth: f32 = sp(&newprop).scale.y * @as(f32, @floatFromInt(src.origh));
        sp(&dst.current).scale.x = dstw / @as(f32, @floatFromInt(dst.origw));
        sp(&dst.current).scale.y = dsth / @as(f32, @floatFromInt(dst.origh));
    }

    return ARCAN_OK;
}

// 13. arcan_video_copytransform
export fn arcan_video_copytransform(sid: arcan_vobj_id, did: arcan_vobj_id) arcan_errc {
    const src = arcan_video_getobject(sid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const dst = arcan_video_getobject(did) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (src == dst) return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    // memcpy current properties
    const dst_bytes: [*]u8 = @ptrCast(&dst.current);
    const src_bytes: [*]const u8 = @ptrCast(&src.current);
    @memcpy(dst_bytes[0..@sizeOf(surface_properties)], src_bytes[0..@sizeOf(surface_properties)]);

    _ = arcan_video_zaptransform(did, 0, null);
    dst.transform = dup_chain(src.transform);
    _ = update_zv(dst, src.order);

    invalidate_cache(dst);

    dst.origw = src.origw;
    dst.origh = src.origh;

    return ARCAN_OK;
}

// 14. arcan_video_transfertransform
export fn arcan_video_transfertransform(sid: arcan_vobj_id, did: arcan_vobj_id) arcan_errc {
    const rv = arcan_video_copytransform(sid, did);

    if (rv == ARCAN_OK) {
        const src = arcan_video_getobject(sid).?;
        _ = arcan_video_zaptransform(sid, 0, null);
        src.transform = null;
    }

    return rv;
}

// 15. drop_rtarget (static)
fn drop_rtarget(vobj: *arcan_vobject) void {
    // linear search for the vobj among rendertargets
    var dst: ?*rendertarget = null;
    var dstind: c_uint = 0;

    while (dstind < current_context.n_rtargets) : (dstind += 1) {
        if (current_context.rtargets[dstind].color == vobj) {
            dst = &current_context.rtargets[dstind];
            break;
        }
    }

    const dst_rt = dst orelse return;

    // drop references from any linktarget
    {
        var i: usize = 0;
        while (i < current_context.n_rtargets) : (i += 1) {
            if (i == dstind) continue;
            if (current_context.rtargets[i].link == dst_rt)
                current_context.rtargets[i].link = null;
        }
    }

    if (current_context.attachment == dst_rt)
        current_context.attachment = null;

    // disassociate with the context
    current_context.n_rtargets -= 1;
    if (current_context.n_rtargets < 0) {
        c.arcan_warning("[bug] rtgt count (%d) < 0\n", current_context.n_rtargets);
    }

    if (vobj.tracetag != null)
        c.arcan_warning("(arcan_video_deleteobject(reference-pass) -- remove rendertarget (%s)\n", vobj.tracetag);

    // kill GPU resources
    if (dst_rt.art != null)
        c.agp_drop_rendertarget(dst_rt.art);
    dst_rt.art = null;

    // create a temporary copy of all the elements in the rendertarget
    var cascade_c: usize = 0;
    var cur_item: ?*arcan_vobject_litem = dst_rt.first;
    const attach_count: usize = @intCast(vobj.extrefc.attachments);
    const pool_sz = attach_count * @sizeOf(?*arcan_vobject);
    const pool: [*c]?*arcan_vobject = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @intCast(pool_sz),
        c.ARCAN_MEM_VSTRUCT,
        c.ARCAN_MEM_TEMPORARY,
        c.ARCAN_MEMALIGN_NATURAL,
    )));

    // note the contents of the rendertarget as "detached" from the source vobj
    while (cur_item) |item| {
        const base = item.elem;
        pool[cascade_c] = base;
        cascade_c += 1;

        // rtarget has one less attachment, and base is attached to one less
        vobj.extrefc.attachments -= 1;
        if (base != null) {
            const b: *arcan_vobject = @ptrCast(base);
            b.extrefc.attachments -= 1;

            trace("(deleteobject::drop_rtarget) remove attached from rendertarget\n");

            if (b.extrefc.attachments < 0) {
                c.arcan_warning("[bug] obj-attach-refc (%d) < 0\n", b.extrefc.attachments);
            }
        }

        if (vobj.extrefc.attachments < 0) {
            c.arcan_warning("[bug] rtgt-ext-refc (%d) < 0\n", vobj.extrefc.attachments);
        }

        // cleanup and unlink before moving on
        const last_item = item;
        var poison_elem: [*c]arcan_vobject = undefined;
        @as(*usize, @ptrCast(&poison_elem)).* = 0xfacefeed;
        last_item.elem = poison_elem;
        cur_item = item.next;
        var poison_next: [*c]arcan_vobject_litem = undefined;
        @as(*usize, @ptrCast(&poison_next)).* = 0xdeadbeef;
        last_item.next = poison_next;
        c.arcan_mem_free(@ptrCast(last_item));
    }
    dst_rt.first = null;

    // compact the context array of rendertargets (overlapping — must use memmove)
    if (dstind + 1 < RENDERTARGET_LIMIT) {
        const dst_ptr: [*]u8 = @ptrCast(&current_context.rtargets[dstind]);
        const src_ptr: [*]const u8 = @ptrCast(&current_context.rtargets[dstind + 1]);
        const count: usize = @intCast(@sizeOf(rendertarget) * (RENDERTARGET_LIMIT - 1 - @as(c_int, @intCast(dstind))));
        _ = c.memmove(dst_ptr, src_ptr, count);
    }

    // always kill the last element
    {
        const ptr: [*]u8 = @ptrCast(&current_context.rtargets[RENDERTARGET_LIMIT - 1]);
        @memset(ptr[0..@sizeOf(rendertarget)], 0);
    }

    // self-reference gone
    vobj.extrefc.attachments -= 1;
    trace("(deleteobject::drop_rtarget) remove self reference from rendertarget\n");
    if (vobj.extrefc.attachments != 0) {
        c.arcan_warning("[bug] vobj refc (%d) != 0\n", vobj.extrefc.attachments);
    }

    // sweep the list of rendertarget children
    {
        var i: usize = 0;
        while (i < cascade_c) : (i += 1) {
            if (pool[i]) |pi| {
                if (flTest(pi, c.FL_INUSE) and
                    (pi.owner == dst_rt or (pi.owner != null and !rtFlTest(@as(*rendertarget, @ptrCast(pi.owner)), c.TGTFL_ALIVE))))
                {
                    pi.owner = null;

                    if ((@as(c_uint, @bitCast(pi.mask)) & c.MASK_LIVING) > 0)
                        _ = arcan_video_deleteobject(pi.cellid)
                    else
                        attach_object(&current_context.stdoutp, pi);
                }
            }
        }
    }

    // remove dangling references/links
    {
        var i: c_uint = 0;
        while (i < current_context.n_rtargets) : (i += 1) {
            if (current_context.rtargets[i].link == dst_rt) {
                current_context.rtargets[i].link = null;
            }
        }
    }

    c.arcan_mem_free(@ptrCast(pool));
}

// 16. drop_frameset (static)
fn drop_frameset(vobj: *arcan_vobject) void {
    if (vobj.frameset == null) return;
    const fs: *c.vobject_frameset = @ptrCast(vobj.frameset);

    var i: usize = 0;
    while (i < fs.n_frames) : (i += 1) {
        arcan_vint_drop_vstore(fs.frames[i].frame);
    }

    c.arcan_mem_free(@ptrCast(fs.frames));
    fs.frames = null;

    c.arcan_mem_free(@ptrCast(fs));
    vobj.frameset = null;
}

// 17. arcan_video_deleteobject
export fn arcan_video_deleteobject(id: arcan_vobj_id) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (id == ARCAN_VIDEO_WORLDID or id == ARCAN_EID)
        return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    // when a persist is defined in a lower layer
    if (flTest(vobj, c.FL_PRSIST) and
        (vcontext_ind > 0 and flTest(
        @as(*const arcan_vobject, @ptrCast(&vcontext_stack[vcontext_ind - 1].vitems_pool[@intCast(vobj.cellid)])), c.FL_PRSIST)))
    {
        return c.ARCAN_ERRC_UNACCEPTED_STATE;
    }

    // step one, disassociate from ALL rendertargets
    _ = detach_fromtarget(&current_context.stdoutp, vobj);
    {
        var i: c_uint = 0;
        while (i < current_context.n_rtargets and vobj.extrefc.attachments != 0) : (i += 1) {
            _ = detach_fromtarget(&current_context.rtargets[i], vobj);
        }
    }

    // step two, disconnect from parent
    if (vobj.parent != null and vobj.parent != &current_context.world)
        dropchild(vobj.parent.?, vobj);

    // vobj might be a rendertarget itself
    drop_rtarget(vobj);
    drop_frameset(vobj);

    // populate a pool of cascade deletions
    const sum: usize = @intCast(vobj.extrefc.links);
    const pool_sz = (sum + 1) * @sizeOf(?*arcan_vobject);
    const pool: [*c]?*arcan_vobject = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @intCast(pool_sz),
        c.ARCAN_MEM_VSTRUCT,
        c.ARCAN_MEM_TEMPORARY,
        c.ARCAN_MEMALIGN_NATURAL,
    )));
    var cascade_c: usize = 0;

    if (sum > 0) {
        const pslice: [*]u8 = @ptrCast(pool);
        @memset(pslice[0..pool_sz], 0);
    }

    // drop all children, add those that should be deleted to the pool
    {
        var i: usize = 0;
        while (i < vobj.childslots) : (i += 1) {
            if (vobj.children[i] == null) continue;
            const cur: *arcan_vobject = @ptrCast(vobj.children[i]);

            if ((@as(c_uint, @bitCast(cur.mask)) & c.MASK_LIVING) > 0 and cascade_c < sum + 1)
                pool[cascade_c] = cur;
            cascade_c += 1;

            dropchild(vobj, cur);
        }
    }

    c.arcan_mem_free(@ptrCast(vobj.children));
    vobj.childslots = 0;

    current_context.nalive -= 1;

    // time to drop all associated resources
    _ = arcan_video_zaptransform(id, 0, null);
    c.arcan_mem_free(@ptrCast(vobj.txcos));

    // full-object specific clean-up
    if (vobj.feed.ffunc != c.FFUNC_FATAL) {
        _ = c.arcan_ffunc_lookup(@intCast(vobj.feed.ffunc)).?(
            c.FFUNC_DESTROY,
            null,
            0,
            0,
            0,
            0,
            vobj.feed.state,
            vobj.cellid,
        );
        vobj.feed.state.ptr = null;
        vobj.feed.ffunc = c.FFUNC_FATAL;
        vobj.feed.state.tag = c.ARCAN_TAG_NONE;
    }

    if (vobj.feed.state.tag == c.ARCAN_TAG_ASYNCIMGLD)
        _ = arcan_video_pushasynch(id);

    // video storage
    arcan_vint_drop_vstore(vobj.vstore);
    vobj.vstore = null;

    if ((vobj.extrefc.attachments | vobj.extrefc.links) != 0) {
        c.arcan_warning("[BUG] Broken reference counters for expiring objects, %d, %d\n",
            vobj.extrefc.attachments, vobj.extrefc.links);
    }

    c.arcan_mem_free(@ptrCast(vobj.tracetag));
    c.arcan_mem_free(@ptrCast(vobj.alttext));
    _ = arcan_vint_dropshape(vobj);

    // reset entire object
    vobj.* = std.mem.zeroes(arcan_vobject);

    // cascade delete
    {
        var i: usize = 0;
        while (i < cascade_c) : (i += 1) {
            if (pool[i]) |pi| {
                trace("(deleteobject) cascade pool entry\n");
                if (flTest(pi, c.FL_INUSE))
                    _ = arcan_video_deleteobject(pi.cellid);
            }
        }
    }

    c.arcan_mem_free(@ptrCast(pool));
    return ARCAN_OK;
}

// 18. arcan_video_override_mapping
export fn arcan_video_override_mapping(id: arcan_vobj_id, newmapping: [*c]f32) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (id <= 0) return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.txcos != null)
        c.arcan_mem_free(@ptrCast(vobj.txcos));

    vobj.txcos = @ptrCast(@alignCast(c.arcan_alloc_fillmem(
        @ptrCast(newmapping),
        @sizeOf(f32) * 8,
        c.ARCAN_MEM_VSTRUCT,
        0,
        c.ARCAN_MEMALIGN_SIMD,
    )));

    flagDirty(vobj);
    return ARCAN_OK;
}

// 19. arcan_video_retrieve_mapping
export fn arcan_video_retrieve_mapping(id: arcan_vobj_id, dst_map: [*c]f32) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (dst_map == null or id <= 0) return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    const sptr: [*]const f32 = if (vobj.txcos != null)
        vobj.txcos
    else
        &arcan_video_display.default_txcos;

    const dst_bytes: [*]u8 = @ptrCast(dst_map);
    const src_bytes: [*]const u8 = @ptrCast(sptr);
    @memcpy(dst_bytes[0 .. @sizeOf(f32) * 8], src_bytes[0 .. @sizeOf(f32) * 8]);

    return ARCAN_OK;
}

// 20. arcan_video_findparent
export fn arcan_video_findparent(id: arcan_vobj_id, ref: arcan_vobj_id) arcan_vobj_id {
    var vobj: ?*arcan_vobject = arcan_video_getobject(id);
    if (vobj == null) return ARCAN_EID;

    if (vobj.?.parent == null or (vobj.?.parent != null and @as(*arcan_vobject, @ptrCast(vobj.?.parent)).owner == null))
        return ARCAN_EID;

    if (ref != ARCAN_EID) {
        while (vobj != null and vobj.?.parent != null) {
            vobj = vobj.?.parent;
            if (ref == vobj.?.cellid) {
                return vobj.?.cellid;
            }
        }
        return ARCAN_EID;
    }

    return @as(*arcan_vobject, @ptrCast(vobj.?.parent)).cellid;
}

// 21. arcan_video_findchild
export fn arcan_video_findchild(parentid: arcan_vobj_id, ofs_in: c_uint) arcan_vobj_id {
    const vobj = arcan_video_getobject(parentid) orelse return ARCAN_EID;

    var ofs = ofs_in;
    var i: usize = 0;
    while (i < vobj.childslots) : (i += 1) {
        if (vobj.children[i] != null) {
            if (ofs > 0) {
                ofs -= 1;
            } else {
                return @as(*arcan_vobject, @ptrCast(vobj.children[i])).cellid;
            }
        }
    }

    return ARCAN_EID;
}

// 22. recsweep (static recursive)
fn recsweep(base: ?*arcan_vobject, match: *arcan_vobject, limit_in: c_int) bool {
    const b = base orelse return false;
    if (limit_in != -1 and limit_in <= 0) return false;

    if (b == match) return true;

    const next_limit: c_int = if (limit_in != -1) limit_in - 1 else -1;
    var i: usize = 0;
    while (i < b.childslots) : (i += 1) {
        if (recsweep(b.children[i], match, next_limit))
            return true;
    }

    return false;
}

// 23. arcan_video_isdescendant
export fn arcan_video_isdescendant(vid: arcan_vobj_id, parent: arcan_vobj_id, limit: c_int) bool {
    const base = arcan_video_getobject(parent) orelse return false;
    const match = arcan_video_getobject(vid) orelse return false;
    return recsweep(base, match, limit);
}

// 24. arcan_video_objectrotate (wrapper)
export fn arcan_video_objectrotate(id: arcan_vobj_id, ang: f32, time: c_uint) arcan_errc {
    return arcan_video_objectrotate3d(id, ang, 0.0, 0.0, time);
}

// 25. arcan_video_objectrotate3d
export fn arcan_video_objectrotate3d(id: arcan_vobj_id, roll: f32, pitch: f32, yaw: f32, tv: c_uint) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    invalidate_cache(vobj);

    // clear chains for rotate if immediate
    if (tv == 0) {
        swipe_chain(vobj.transform, @offsetOf(surface_transform, "rotate"), @sizeOf(c.struct_transf_rotate));
        vobj.current.rotation.roll = roll;
        vobj.current.rotation.pitch = pitch;
        vobj.current.rotation.yaw = yaw;
        vobj.current.rotation.quaternion = c.build_quat_taitbryan(roll, pitch, yaw);
        return ARCAN_OK;
    }

    var bv: c.surface_orientation = vobj.current.rotation;
    var base: ?*surface_transform = vobj.transform;
    var last: ?*surface_transform = base;

    // figure out the starting angle
    while (base != null and base.?.rotate.startt != 0) {
        bv = base.?.rotate.endo;
        last = base;
        base = base.?.next;
    }

    if (base == null) {
        if (last) |l| {
            l.next = @ptrCast(@alignCast(c.arcan_alloc_mem(
                @sizeOf(surface_transform),
                c.ARCAN_MEM_VSTRUCT,
                c.ARCAN_MEM_BZERO,
                c.ARCAN_MEMALIGN_NATURAL,
            )));
            base = l.next;
        } else {
            base = @ptrCast(@alignCast(c.arcan_alloc_mem(
                @sizeOf(surface_transform),
                c.ARCAN_MEM_VSTRUCT,
                c.ARCAN_MEM_BZERO,
                c.ARCAN_MEMALIGN_NATURAL,
            )));
            last = base;
        }
    }

    if (vobj.transform == null)
        vobj.transform = base;

    const b = base.?;
    const l = last.?;
    b.rotate.startt = if (l.rotate.endt < arcan_video_display.c_ticks)
        arcan_video_display.c_ticks
    else
        l.rotate.endt;
    b.rotate.endt = b.rotate.startt + tv;
    b.rotate.starto = bv;

    b.rotate.endo.roll = roll;
    b.rotate.endo.pitch = pitch;
    b.rotate.endo.yaw = yaw;
    b.rotate.endo.quaternion = c.build_quat_taitbryan(roll, pitch, yaw);

    if (vobj.owner != null)
        @as(*rendertarget, @ptrCast(vobj.owner)).transfc += 1;

    b.rotate.interp = if (@abs(bv.roll - roll) > 180.0 or
        @abs(bv.pitch - pitch) > 180.0 or @abs(bv.yaw - yaw) > 180.0)
        c.nlerp_quat180
    else
        c.nlerp_quat360;

    return ARCAN_OK;
}

// 26. arcan_video_allocframes
export fn arcan_video_allocframes(id: arcan_vobj_id, capacity: u8, mode: c_uint) arcan_errc {
    const target = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    // similar restrictions as with sharestore
    if (@as(*agp_vstore, @ptrCast(target.vstore)).txmapped != c.TXSTATE_TEX2D)
        return c.ARCAN_ERRC_UNACCEPTED_STATE;

    if (flTest(target, c.FL_PRSIST))
        return c.ARCAN_ERRC_CLONE_NOT_PERMITTED;

    // special case, de-allocate
    if (capacity <= 1) {
        drop_frameset(target);
        return ARCAN_OK;
    }

    // only permit framesets to grow
    if (@as(?*c.struct_vobject_frameset, @ptrCast(target.frameset))) |fs| {
        if (fs.n_frames > capacity)
            return c.ARCAN_ERRC_UNACCEPTED_STATE;
    } else {
        target.frameset = @ptrCast(@alignCast(c.arcan_alloc_mem(
            @sizeOf(c.struct_vobject_frameset),
            c.ARCAN_MEM_VSTRUCT,
            c.ARCAN_MEM_BZERO,
            c.ARCAN_MEMALIGN_NATURAL,
        )));
    }

    const fs: *c.struct_vobject_frameset = @ptrCast(target.frameset);
    fs.n_frames = capacity;
    fs.frames = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @sizeOf(c.struct_frameset_store) * @as(usize, capacity),
        c.ARCAN_MEM_VSTRUCT,
        c.ARCAN_MEM_BZERO,
        c.ARCAN_MEMALIGN_NATURAL,
    )));

    var i: usize = 0;
    while (i < capacity) : (i += 1) {
        fs.frames[i].frame = target.vstore;
        arcan_vint_defaultmapping(&fs.frames[i].txcos, 1.0, 1.0);
        @as(*agp_vstore, @ptrCast(target.vstore)).refcount += 1;
    }

    fs.mode = mode;
    return ARCAN_OK;
}

// 27. arcan_video_origoshift
export fn arcan_video_origoshift(id: arcan_vobj_id, sx: f32, sy: f32, sz: f32, anchor_shift: c.enum_parent_anchor) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    invalidate_cache(vobj);
    flSet(vobj, c.FL_ORDOFS);
    vobj.origo_ofs.unnamed_0.unnamed_0.x = sx;
    vobj.origo_ofs.unnamed_0.unnamed_0.y = sy;
    vobj.origo_ofs.unnamed_0.unnamed_0.z = sz;
    vobj.p_anchor_shift = anchor_shift;

    return ARCAN_OK;
}

// 28. arcan_video_objectopacity
export fn arcan_video_objectopacity(id: arcan_vobj_id, opa_in: f32, tv: c_uint) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const opa = std.math.clamp(opa_in, 0.0, 1.0);

    invalidate_cache(vobj);

    // clear chains for blend if immediate
    if (tv == 0) {
        swipe_chain(vobj.transform, @offsetOf(surface_transform, "blend"), @sizeOf(c.struct_transf_blend));
        vobj.current.opa = opa;
    } else {
        // find endpoint to attach at
        var bv: f32 = vobj.current.opa;

        var base: ?*surface_transform = vobj.transform;
        var last: ?*surface_transform = base;

        while (base != null and base.?.blend.startt != 0) {
            bv = base.?.blend.endopa;
            last = base;
            base = base.?.next;
        }

        if (base == null) {
            if (last) |l| {
                l.next = @ptrCast(@alignCast(c.arcan_alloc_mem(
                    @sizeOf(surface_transform),
                    c.ARCAN_MEM_VSTRUCT,
                    c.ARCAN_MEM_BZERO,
                    c.ARCAN_MEMALIGN_NATURAL,
                )));
                base = l.next;
            } else {
                base = @ptrCast(@alignCast(c.arcan_alloc_mem(
                    @sizeOf(surface_transform),
                    c.ARCAN_MEM_VSTRUCT,
                    c.ARCAN_MEM_BZERO,
                    c.ARCAN_MEMALIGN_NATURAL,
                )));
                last = base;
            }
        }

        if (vobj.transform == null)
            vobj.transform = base;

        if (vobj.owner != null)
            @as(*rendertarget, @ptrCast(vobj.owner)).transfc += 1;

        const b = base.?;
        const l = last.?;
        b.blend.startt = if (l.blend.endt < arcan_video_display.c_ticks)
            arcan_video_display.c_ticks
        else
            l.blend.endt;
        b.blend.endt = b.blend.startt + tv;
        b.blend.startopa = bv;
        b.blend.endopa = opa + EPSILON;
        b.blend.interp = c.ARCAN_VINTER_LINEAR;
    }

    return ARCAN_OK;
}

// 29. arcan_video_blendinterp
export fn arcan_video_blendinterp(id: arcan_vobj_id, inter: c_uint) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.transform == null)
        return c.ARCAN_ERRC_UNACCEPTED_STATE;

    var base: ?*surface_transform = @ptrCast(vobj.transform);
    while (base != null and base.?.blend.startt != 0 and
        @as(?*surface_transform, @ptrCast(base.?.next)) != null and @as(*surface_transform, @ptrCast(base.?.next)).blend.startt != 0)
    {
        base = @ptrCast(base.?.next);
    }

    base.?.blend.interp = @intCast(inter);
    return ARCAN_OK;
}

// 30. arcan_video_scaleinterp
export fn arcan_video_scaleinterp(id: arcan_vobj_id, inter: c_uint) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.transform == null)
        return c.ARCAN_ERRC_UNACCEPTED_STATE;

    var base: ?*surface_transform = @ptrCast(vobj.transform);
    while (base != null and base.?.scale.startt != 0 and
        @as(?*surface_transform, @ptrCast(base.?.next)) != null and @as(*surface_transform, @ptrCast(base.?.next)).scale.startt != 0)
    {
        base = @ptrCast(base.?.next);
    }

    base.?.scale.interp = @intCast(inter);
    return ARCAN_OK;
}

// 31. arcan_video_moveinterp
export fn arcan_video_moveinterp(id: arcan_vobj_id, inter: c_uint) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (vobj.transform == null)
        return c.ARCAN_ERRC_UNACCEPTED_STATE;

    var base: ?*surface_transform = @ptrCast(vobj.transform);
    while (base != null and base.?.move.startt != 0 and
        @as(?*surface_transform, @ptrCast(base.?.next)) != null and @as(*surface_transform, @ptrCast(base.?.next)).move.startt != 0)
    {
        base = @ptrCast(base.?.next);
    }

    base.?.move.interp = @intCast(inter);
    return ARCAN_OK;
}

// 32. arcan_video_objectmove
export fn arcan_video_objectmove(id: arcan_vobj_id, newx: f32, newy: f32, newz: f32, tv: c_uint) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    invalidate_cache(vobj);

    // clear chains if immediate
    if (tv == 0) {
        swipe_chain(vobj.transform, @offsetOf(surface_transform, "move"), @sizeOf(c.struct_transf_move));
        sp(&vobj.current).position.x = newx;
        sp(&vobj.current).position.y = newy;
        sp(&vobj.current).position.z = newz;
        return ARCAN_OK;
    }

    // find endpoint to attach at
    var base: ?*surface_transform = vobj.transform;
    var last: ?*surface_transform = base;
    var bwp: c.point = vobj.current.position;

    while (base != null and base.?.move.startt != 0) {
        bwp = base.?.move.endp;
        last = base;
        base = base.?.next;
    }

    if (base == null) {
        if (last) |l| {
            l.next = @ptrCast(@alignCast(c.arcan_alloc_mem(
                @sizeOf(surface_transform),
                c.ARCAN_MEM_VSTRUCT,
                c.ARCAN_MEM_BZERO,
                c.ARCAN_MEMALIGN_NATURAL,
            )));
            base = l.next;
        } else {
            base = @ptrCast(@alignCast(c.arcan_alloc_mem(
                @sizeOf(surface_transform),
                c.ARCAN_MEM_VSTRUCT,
                c.ARCAN_MEM_BZERO,
                c.ARCAN_MEMALIGN_NATURAL,
            )));
            last = base;
        }
    }

    var newp: c.point = undefined;
    newp.unnamed_0.unnamed_0.x = newx;
    newp.unnamed_0.unnamed_0.y = newy;
    newp.unnamed_0.unnamed_0.z = newz;

    if (vobj.transform == null)
        vobj.transform = base;

    const b = base.?;
    const l = last.?;
    b.move.startt = if (l.move.endt < arcan_video_display.c_ticks)
        arcan_video_display.c_ticks
    else
        l.move.endt;
    b.move.endt = b.move.startt + tv;
    b.move.interp = c.ARCAN_VINTER_LINEAR;
    b.move.startp = bwp;
    b.move.endp = newp;

    if (@as(?*rendertarget, @ptrCast(vobj.owner))) |owner|
        owner.transfc += 1;

    return ARCAN_OK;
}

// 33. arcan_video_objectscale
export fn arcan_video_objectscale(id: arcan_vobj_id, wf: f32, hf: f32, df: f32, tv: c_uint) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    invalidate_cache(vobj);

    if (tv == 0) {
        swipe_chain(vobj.transform, @offsetOf(surface_transform, "scale"), @sizeOf(c.struct_transf_scale));
        sp(&vobj.current).scale.x = wf;
        sp(&vobj.current).scale.y = hf;
        sp(&vobj.current).scale.z = df;
    } else {
        var base: ?*surface_transform = vobj.transform;
        var last: ?*surface_transform = base;
        var bs: c.scalefactor = vobj.current.scale;

        while (base != null and base.?.scale.startt != 0) {
            bs = base.?.scale.endd;
            last = base;
            base = base.?.next;
        }

        if (base == null) {
            if (last) |l| {
                l.next = @ptrCast(@alignCast(c.arcan_alloc_mem(
                    @sizeOf(surface_transform),
                    c.ARCAN_MEM_VSTRUCT,
                    c.ARCAN_MEM_BZERO,
                    c.ARCAN_MEMALIGN_NATURAL,
                )));
                base = l.next;
            } else {
                base = @ptrCast(@alignCast(c.arcan_alloc_mem(
                    @sizeOf(surface_transform),
                    c.ARCAN_MEM_VSTRUCT,
                    c.ARCAN_MEM_BZERO,
                    c.ARCAN_MEMALIGN_NATURAL,
                )));
                last = base;
            }
        }

        if (vobj.transform == null)
            vobj.transform = base;

        const b = base.?;
        const l = last.?;
        b.scale.startt = if (l.scale.endt < arcan_video_display.c_ticks)
            arcan_video_display.c_ticks
        else
            l.scale.endt;
        b.scale.endt = b.scale.startt + tv;
        b.scale.interp = c.ARCAN_VINTER_LINEAR;
        b.scale.startd = bs;
        b.scale.endd.unnamed_0.unnamed_0.x = wf;
        b.scale.endd.unnamed_0.unnamed_0.y = hf;
        b.scale.endd.unnamed_0.unnamed_0.z = df;

        if (@as(?*rendertarget, @ptrCast(vobj.owner))) |owner|
            owner.transfc += 1;
    }

    return ARCAN_OK;
}

// 34. tesselate_2d (static)
fn tesselate_2d(n_s: usize, n_t: usize) c.struct_agp_mesh_store {
    var res: c.struct_agp_mesh_store = std.mem.zeroes(c.struct_agp_mesh_store);
    res.depth_func = c.AGP_DEPTH_LESS;

    const step_s: f32 = 2.0 / @as(f32, @floatFromInt(n_s - 1));
    const step_t: f32 = 2.0 / @as(f32, @floatFromInt(n_t - 1));

    // use same buffer for both vertices and txcos
    res.shared_buffer_sz = @intCast(@sizeOf(f32) * n_s * n_t * 4);
    const sbuf: ?*anyopaque = @ptrCast(c.arcan_alloc_mem(
        @intCast(@sizeOf(f32) * n_s * n_t * 4),
        c.ARCAN_MEM_MODELDATA,
        c.ARCAN_MEM_NONFATAL,
        c.ARCAN_MEMALIGN_PAGE,
    ));
    res.shared_buffer = @ptrCast(sbuf);

    const vertices: [*c]f32 = @ptrCast(@alignCast(sbuf));
    if (vertices == null)
        return res;

    const txcos: [*c]f32 = vertices + n_s * n_t * 2;

    const indices: [*c]c_uint = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @intCast(@sizeOf(c_uint) * (n_s - 1) * (n_t - 1) * 6),
        c.ARCAN_MEM_MODELDATA,
        c.ARCAN_MEM_NONFATAL,
        c.ARCAN_MEMALIGN_PAGE,
    )));

    if (indices == null) {
        c.arcan_mem_free(@ptrCast(vertices));
        return res;
    }

    // populate txco/vertices
    {
        var y: usize = 0;
        while (y < n_t) : (y += 1) {
            var x: usize = 0;
            while (x < n_s) : (x += 1) {
                const ofs = (y * n_s + x) * 2;
                vertices[ofs + 0] = @as(f32, @floatFromInt(x)) * step_s - 1.0;
                vertices[ofs + 1] = @as(f32, @floatFromInt(y)) * step_t - 1.0;
                txcos[ofs + 0] = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(n_s));
                txcos[ofs + 1] = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(n_t));
            }
        }
    }

    // get the indices
    {
        var ofs: usize = 0;
        var y: usize = 0;
        while (y < n_t - 1) : (y += 1) {
            var x: usize = 0;
            while (x < n_s - 1) : (x += 1) {
                indices[ofs] = @intCast(x * n_s + y);
                ofs += 1;
                indices[ofs] = @intCast(x * n_s + (y + 1));
                ofs += 1;
                indices[ofs] = @intCast((x + 1) * n_s + (y + 1));
                ofs += 1;
                indices[ofs] = @intCast(x * n_s + y);
                ofs += 1;
                indices[ofs] = @intCast((x + 1) * n_s + (y + 1));
                ofs += 1;
                indices[ofs] = @intCast((x + 1) * n_s + y);
                ofs += 1;
            }
        }
    }

    res.verts = vertices;
    res.txcos = txcos;
    res.indices = indices;
    res.n_vertices = @intCast(n_s * n_t);
    res.vertex_size = 2;
    res.n_indices = @intCast((n_s - 1) * (n_t - 1) * 6);
    res.type = c.AGP_MESH_TRISOUP;

    return res;
}

// 35. arcan_video_defineshape
export fn arcan_video_defineshape(
    dst: arcan_vobj_id,
    n_s: usize,
    n_t: usize,
    store: [*c]?*c.struct_agp_mesh_store,
    depth: bool,
) arcan_errc {
    const vobj = arcan_video_getobject(dst) orelse {
        if (store != null) store[0] = null;
        return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    };

    if (n_s == 0 or n_t == 0) {
        if (store != null) store[0] = vobj.shape;
        return ARCAN_OK;
    }

    if (vobj.shape != null or n_s == 1 or n_t == 1) {
        c.agp_drop_mesh(vobj.shape);
        if (n_s == 1 or n_t == 1) {
            vobj.shape = null;
            if (store != null) store[0] = vobj.shape;
            return ARCAN_OK;
        }
    } else {
        vobj.shape = @ptrCast(@alignCast(c.arcan_alloc_mem(
            @sizeOf(c.struct_agp_mesh_store),
            c.ARCAN_MEM_MODELDATA,
            c.ARCAN_MEM_BZERO | c.ARCAN_MEM_NONFATAL,
            c.ARCAN_MEMALIGN_NATURAL,
        )));
    }

    if (vobj.shape == null) {
        if (store != null) store[0] = null;
        return c.ARCAN_ERRC_OUT_OF_SPACE;
    }

    // we now KNOW that s > 1 and t > 1, that shape is valid
    const ns = tesselate_2d(n_s, n_t);
    if (ns.verts == null) {
        if (vobj.shape != null) {
            _ = arcan_vint_dropshape(vobj);
        }
        if (store != null) store[0] = null;
        return c.ARCAN_ERRC_OUT_OF_SPACE;
    }

    @as(*c.struct_agp_mesh_store, @ptrCast(vobj.shape)).* = ns;
    @as(*c.struct_agp_mesh_store, @ptrCast(vobj.shape)).nodepth = depth;

    if (store != null) store[0] = vobj.shape;
    return ARCAN_OK;
}

// 36. compact_transformation (static)
fn compact_transformation(base: ?*arcan_vobject, ofs: c_uint, count: c_uint) void {
    const b = base orelse return;
    if (b.transform == null) return;

    var last: ?*surface_transform = null;
    var work: ?*surface_transform = b.transform;

    // copy the next transformation
    while (work != null and work.?.next != null) {
        const w = work.?;
        const wn = w.next.?;

        const dst_ptr: [*]u8 = @ptrCast(w);
        const src_ptr: [*]const u8 = @ptrCast(wn);
        @memcpy(dst_ptr[ofs .. ofs + count], src_ptr[ofs .. ofs + count]);

        last = work;
        work = w.next;
    }

    // reset the last one
    {
        const w = work.?;
        const ptr: [*]u8 = @ptrCast(w);
        @memset(ptr[ofs .. ofs + count], 0);

        // if it is now empty, free and delink
        if ((w.blend.startt | w.scale.startt | w.move.startt | w.rotate.startt) == 0) {
            c.arcan_mem_free(@ptrCast(w));
            if (last) |l| {
                l.next = null;
            } else {
                b.transform = null;
            }
            // H3 FIX TEMPORARILY DISABLED FOR RED/GREEN TEST
            // b.valid_cache = false;
            // flagDirty(b);
        }
    }
}

// 37. arcan_video_setprogram
export fn arcan_video_setprogram(id: arcan_vobj_id, shid: agp_shader_id) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    if (c.agp_shader_valid(shid)) {
        flagDirty(vobj);
        vobj.program = shid;
        return ARCAN_OK;
    }

    return c.ARCAN_ERRC_NO_SUCH_OBJECT;
}

// ============================================================
// Chunk 6: Tick, resolve, render pipeline
// ============================================================

inline fn lerp_fract(startt: f32, endt: f32, ts: f32) f32 {
    var rv = (EPSILON + (ts - startt)) / (endt - startt);
    if (rv > 1.0) rv = 1.0;
    return rv;
}

fn update_object(ci: *arcan_vobject, stamp: c_ulonglong) c_int {
    var upd: c_int = 0;

    // Guard against freed/recycled objects with stale rendertarget references
    if (!flTest(ci, c.FL_INUSE))
        return 0;

    if (ci.last_updated < stamp) {
        const parent_ptr = ci.parent;
        if (parent_ptr != null) {
            const parent: *arcan_vobject = @ptrCast(parent_ptr);
            if (parent != &current_context.world and parent.last_updated != stamp) {
                upd += update_object(parent, stamp);
            }
        }
    }

    ci.last_updated = @intCast(stamp);

    if (ci.transform == null)
        return upd;

    if (@as(?*surface_transform, @ptrCast(ci.transform))) |tf| {
        if (tf.blend.startt != 0) {
            upd += 1;
            const fract = lerp_fract(
                @floatFromInt(tf.blend.startt),
                @floatFromInt(tf.blend.endt),
                @floatFromInt(stamp),
            );

            ci.current.opa = lut_interp_1d[@intCast(tf.blend.interp)].?(
                tf.blend.startopa, tf.blend.endopa, fract,
            );

            if (fract > 1.0 - EPSILON) {
                ci.current.opa = tf.blend.endopa;

                if (flTest(ci, c.FL_TCYCLE)) {
                    _ = arcan_video_objectopacity(ci.cellid, tf.blend.endopa,
                        tf.blend.endt - tf.blend.startt);
                    if (tf.blend.interp > 0)
                        _ = arcan_video_blendinterp(ci.cellid, @intCast(tf.blend.interp));
                }

                if (tf.blend.tag != 0)
                    emit_transform_event(ci.cellid, c.MASK_OPACITY, tf.blend.tag);

                compact_transformation(ci,
                    @offsetOf(c.struct_surface_transform, "blend"),
                    @sizeOf(c.struct_transf_blend));
            }
        }
    }

    if (@as(?*surface_transform, @ptrCast(ci.transform))) |tf| {
        if (tf.move.startt != 0) {
            upd += 1;
            const fract = lerp_fract(
                @floatFromInt(tf.move.startt),
                @floatFromInt(tf.move.endt),
                @floatFromInt(stamp),
            );

            ci.current.position = lut_interp_3d[@intCast(tf.move.interp)].?(
                tf.move.startp, tf.move.endp, fract,
            );

            if (fract > 1.0 - EPSILON) {
                ci.current.position = tf.move.endp;

                if (flTest(ci, c.FL_TCYCLE)) {
                    _ = arcan_video_objectmove(ci.cellid,
                        tf.move.endp.unnamed_0.unnamed_0.x, tf.move.endp.unnamed_0.unnamed_0.y, tf.move.endp.unnamed_0.unnamed_0.z,
                        tf.move.endt - tf.move.startt);

                    if (tf.move.interp > 0)
                        _ = arcan_video_moveinterp(ci.cellid, @intCast(tf.move.interp));
                }

                if (tf.move.tag != 0)
                    emit_transform_event(ci.cellid, c.MASK_POSITION, tf.move.tag);

                compact_transformation(ci,
                    @offsetOf(c.struct_surface_transform, "move"),
                    @sizeOf(c.struct_transf_move));
            }
        }
    }

    if (@as(?*surface_transform, @ptrCast(ci.transform))) |tf| {
        if (tf.scale.startt != 0) {
            upd += 1;
            const fract = lerp_fract(
                @floatFromInt(tf.scale.startt),
                @floatFromInt(tf.scale.endt),
                @floatFromInt(stamp),
            );
            ci.current.scale = lut_interp_3d[@intCast(tf.scale.interp)].?(
                tf.scale.startd, tf.scale.endd, fract,
            );

            if (fract > 1.0 - EPSILON) {
                ci.current.scale = tf.scale.endd;

                if (flTest(ci, c.FL_TCYCLE)) {
                    _ = arcan_video_objectscale(ci.cellid,
                        tf.scale.endd.unnamed_0.unnamed_0.x, tf.scale.endd.unnamed_0.unnamed_0.y, tf.scale.endd.unnamed_0.unnamed_0.z,
                        tf.scale.endt - tf.scale.startt);

                    if (tf.scale.interp > 0)
                        _ = arcan_video_scaleinterp(ci.cellid, @intCast(tf.scale.interp));
                }

                if (tf.scale.tag != 0)
                    emit_transform_event(ci.cellid, c.MASK_SCALE, tf.scale.tag);

                compact_transformation(ci,
                    @offsetOf(c.struct_surface_transform, "scale"),
                    @sizeOf(c.struct_transf_scale));
            }
        }
    }

    if (@as(?*surface_transform, @ptrCast(ci.transform))) |tf| {
        if (tf.rotate.startt != 0) {
            upd += 1;
            const fract = lerp_fract(
                @floatFromInt(tf.rotate.startt),
                @floatFromInt(tf.rotate.endt),
                @floatFromInt(stamp),
            );

            if (fract > 1.0 - EPSILON) {
                ci.current.rotation = tf.rotate.endo;
                if (flTest(ci, c.FL_TCYCLE))
                    _ = arcan_video_objectrotate3d(ci.cellid,
                        tf.rotate.endo.roll, tf.rotate.endo.pitch, tf.rotate.endo.yaw,
                        tf.rotate.endt - tf.rotate.startt);

                if (tf.rotate.tag != 0)
                    emit_transform_event(ci.cellid, c.MASK_ORIENTATION, tf.rotate.tag);

                compact_transformation(ci,
                    @offsetOf(c.struct_surface_transform, "rotate"),
                    @sizeOf(c.struct_transf_rotate));
            } else {
                ci.current.rotation.quaternion = tf.rotate.interp.?(
                    tf.rotate.starto.quaternion, tf.rotate.endo.quaternion, fract,
                );
            }
        }
    }

    return upd;
}

fn expire_object(obj: *arcan_vobject) void {
    if (obj.lifetime != 0) {
        obj.lifetime -= 1;
        if (obj.lifetime == 0) {
            var dobjev: c.arcan_event = c.arcan_event.zeroes();
            dobjev.unnamed_0.unnamed_0.category = c.EVENT_VIDEO;
            dobjev.unnamed_0.unnamed_0.unnamed_0.vid.kind = c.EVENT_VIDEO_EXPIRE;
            dobjev.unnamed_0.unnamed_0.unnamed_0.vid.source = obj.cellid;
            _ = c.arcan_event_enqueue(c.arcan_event_defaultctx(), &dobjev);
        }
    }
}

inline fn process_counter(tgt: *rendertarget, field: *c_int, base: c_int, fract: f32) bool {
    _ = tgt;
    _ = fract;
    if (base == 0) return false;
    field.* -= 1;
    if (field.* <= 0) {
        field.* = if (base < 0) -base else base;
        return true;
    }
    return false;
}

inline fn process_readback(tgt: *rendertarget, fract: f32) void {
    if (!rtFlTest(tgt, c.TGTFL_READING) and
        process_counter(tgt, &tgt.readcnt, tgt.readback, fract))
    {
        if (tgt.hwreadback) {
            const vobj: *arcan_vobject = tgt.color orelse return;
            if (vobj.feed.ffunc != 0) {
                if (c.arcan_ffunc_lookup(@intCast(vobj.feed.ffunc))) |ff| {
                    if (ff(c.FFUNC_READBACK_HANDLE, null, 0, 0, 0, 0,
                        vobj.feed.state, vobj.cellid) == c.FRV_GOTFRAME) return;
                }
            }
        }
        if (!tgt.hwreadback) {
            c.agp_request_readback(@as(*arcan_vobject, @ptrCast(tgt.color)).vstore);
            rtFlSet(tgt, c.TGTFL_READING);
        }
    }
}

// Generation counter: incremented every time any rendertarget list is modified.
// tick_rendertarget checks this after callbacks to detect list mutation.
var rt_list_generation: u64 = 0;

fn tick_rendertarget(tgt: *rendertarget) c_int {
    tgt.transfc = 0;
    var current = tgt.first;

    while (@as(?*arcan_vobject_litem, @ptrCast(current))) |cur| {
        const gen_before = rt_list_generation;
        const next = cur.next;

        // Skip poisoned/null/out-of-pool/freed entries
        if (@intFromPtr(cur.elem) == 0xfeedface or cur.elem == null) {
            current = next;
            continue;
        }
        const elem: *arcan_vobject = @ptrCast(cur.elem);

        const pool_base = @intFromPtr(current_context.vitems_pool);
        const pool_end = pool_base + @as(usize, @intCast(current_context.vitem_limit)) * @sizeOf(arcan_vobject);
        const elem_addr = @intFromPtr(elem);
        if (elem_addr < pool_base or elem_addr >= pool_end or
            (elem_addr - pool_base) % @sizeOf(arcan_vobject) != 0 or
            !flTest(elem, c.FL_INUSE))
        {
            current = next;
            continue;
        }

        arcan_vint_joinasynch(elem, true, false);

        if (elem.last_updated != arcan_video_display.c_ticks)
            tgt.transfc += @intCast(update_object(elem, arcan_video_display.c_ticks));

        if (elem.feed.ffunc != 0) {
            const ffunc_val = elem.feed.ffunc;
            if (ffunc_val <= std.math.maxInt(u8)) {
                if (c.arcan_ffunc_lookup(@intCast(ffunc_val))) |ff| {
                    _ = ff(c.FFUNC_TICK, null, 0, 0, 0, 0, elem.feed.state, elem.cellid);
                }
            }
        }

        // If a callback modified any rendertarget list, the saved `next` pointer
        // may be freed. Restart iteration from tgt.first to be safe.
        if (rt_list_generation != gen_before) {
            current = tgt.first;
            continue;
        }

        if (@as(?*c.struct_vobject_frameset, @ptrCast(elem.frameset))) |fs| {
            if (fs.mctr != 0) {
                fs.ctr -= 1;
                if (fs.ctr == 0) {
                    step_active_frame(elem);
                    fs.ctr = if (fs.mctr < 0) -fs.mctr else fs.mctr;
                }
            }
        }

        if ((@as(c_uint, @bitCast(elem.mask)) & c.MASK_LIVING) > 0)
            expire_object(elem);

        current = next;
    }

    if (tgt.refresh > 0 and process_counter(tgt, &tgt.refreshcnt, tgt.refresh, 0.0)) {
        tgt.transfc += @intCast(process_rendertarget(tgt, 0.0, false));
        tgt.dirtyc = 0;
    }

    if (tgt.readback < 0)
        process_readback(tgt, 0.0);

    return @intCast(tgt.transfc);
}

export fn arcan_video_tick(steps_in: c_uint, njobs: ?*c_uint) c_uint {
    if (steps_in == 0) return 0;

    var steps = steps_in;
    const now = c.arcan_frametime();
    var tsd: u32 = @intCast(arcan_video_display.c_ticks);
    c.arcan_random(@ptrCast(&arcan_video_display.cookie), 8);

    while (true) {
        arcan_video_display.dirty +=
            @intCast(update_object(&current_context.world, arcan_video_display.c_ticks));

        arcan_video_display.dirty +=
            @intCast(c.agp_shader_envv(c.TIMESTAMP_D, &tsd, @sizeOf(u32)));

        // Iterate in reverse — if a callback triggers drop_rtarget, the memmove
        // compaction shifts higher indices down. Reverse order means we've already
        // visited those slots, so no slot is skipped or visited twice.
        {
            var i: usize = @intCast(current_context.n_rtargets);
            while (i > 0) {
                i -= 1;
                // Re-check bounds: n_rtargets may have changed during callback
                if (i < @as(usize, @intCast(current_context.n_rtargets)))
                    arcan_video_display.dirty += tick_rendertarget(&current_context.rtargets[i]);
            }
        }

        arcan_video_display.dirty += tick_rendertarget(&current_context.stdoutp);

        arcan_video_display.c_ticks =
            @intCast(@rem((@as(i64, arcan_video_display.c_ticks) + 1), (@as(i64, std.math.maxInt(i32)) / 3)));

        steps -= 1;
        if (steps == 0) break;
    }

    if (njobs) |nj| nj.* = @intCast(arcan_video_display.dirty);
    return @intCast(c.arcan_frametime() - now);
}

export fn arcan_video_clipto(id: arcan_vobj_id, clip_tgt: arcan_vobj_id) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    vobj.clip_src = clip_tgt;
    return ARCAN_OK;
}

export fn arcan_video_setclip(id: arcan_vobj_id, mode: c.arcan_clipmode) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    vobj.clip = mode;
    return ARCAN_OK;
}

export fn arcan_video_persistobject(id: arcan_vobj_id) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (vobj.frameset == null and @as(*agp_vstore, @ptrCast(vobj.vstore)).refcount == 1 and
        vobj.parent == @as([*c]arcan_vobject, @ptrCast(&current_context.world)))
    {
        flSet(vobj, c.FL_PRSIST);
        return ARCAN_OK;
    }
    return c.ARCAN_ERRC_UNACCEPTED_STATE;
}

fn apply(vobj: *arcan_vobject, dprops: *surface_properties, sprops: ?*surface_properties, lerp: f32, force: bool) void {
    dprops.* = vobj.current;

    if (@as(?*surface_transform, @ptrCast(vobj.transform))) |tf| {
        const ct: f32 = @floatFromInt(arcan_video_display.c_ticks);

        if (tf.move.startt != 0)
            dprops.position = lut_interp_3d[@intCast(tf.move.interp)].?(
                tf.move.startp, tf.move.endp,
                lerp_fract(@floatFromInt(tf.move.startt), @floatFromInt(tf.move.endt), ct + lerp));

        if (tf.scale.startt != 0)
            dprops.scale = lut_interp_3d[@intCast(tf.scale.interp)].?(
                tf.scale.startd, tf.scale.endd,
                lerp_fract(@floatFromInt(tf.scale.startt), @floatFromInt(tf.scale.endt), ct + lerp));

        if (tf.blend.startt != 0)
            dprops.opa = lut_interp_1d[@intCast(tf.blend.interp)].?(
                tf.blend.startopa, tf.blend.endopa,
                lerp_fract(@floatFromInt(tf.blend.startt), @floatFromInt(tf.blend.endt), ct + lerp));

        if (tf.rotate.startt != 0) {
            dprops.rotation.quaternion = tf.rotate.interp.?(
                tf.rotate.starto.quaternion, tf.rotate.endo.quaternion,
                lerp_fract(@floatFromInt(tf.rotate.startt), @floatFromInt(tf.rotate.endt), ct + lerp));
            const ang = c.angle_quat(dprops.rotation.quaternion);
            dprops.rotation.roll = ang.unnamed_0.unnamed_0.x;
            dprops.rotation.pitch = ang.unnamed_0.unnamed_0.y;
            dprops.rotation.yaw = ang.unnamed_0.unnamed_0.z;
        }

        if (sprops == null) return;
    }

    const sparent = sprops orelse return;

    if (force or (@as(c_uint, @bitCast(vobj.mask)) & c.MASK_POSITION) > 0) {
        const dp = sp(dprops);
        const pp = spConst(sparent);
        dp.position.x += pp.position.x;
        dp.position.y += pp.position.y;
        dp.position.z += pp.position.z;
    }

    if (force or (@as(c_uint, @bitCast(vobj.mask)) & c.MASK_ORIENTATION) > 0) {
        dprops.rotation.yaw += sparent.rotation.yaw;
        dprops.rotation.pitch += sparent.rotation.pitch;
        dprops.rotation.roll += sparent.rotation.roll;
        if (flTest(vobj, c.FL_FULL3D))
            dprops.rotation.quaternion = c.mul_quat(sparent.rotation.quaternion, dprops.rotation.quaternion);
    }

    if (force or (@as(c_uint, @bitCast(vobj.mask)) & c.MASK_OPACITY) > 0)
        dprops.opa *= sparent.opa;
}

fn sub_anchor_shift(ref: *arcan_vobject, props: *surface_properties, dprop: *surface_properties, rule: c_int) void {
    const ow: f32 = @floatFromInt(ref.origw);
    const oh: f32 = @floatFromInt(ref.origh);
    const p = sp(props);
    const d = sp(dprop);
    switch (rule) {
        c.ANCHORP_UR => { p.position.x -= ow * d.scale.x; },
        c.ANCHORP_LR => { p.position.y -= oh * d.scale.y; p.position.x -= ow * d.scale.x; },
        c.ANCHORP_LL => { p.position.y -= oh * d.scale.y; },
        c.ANCHORP_CR => { p.position.y -= oh * d.scale.y * 0.5; p.position.x -= ow * d.scale.x; },
        c.ANCHORP_C, c.ANCHORP_UC, c.ANCHORP_CL, c.ANCHORP_LC => {
            const mid_y = (oh * d.scale.y) * 0.5;
            const mid_x = (ow * d.scale.x) * 0.5;
            if (rule == c.ANCHORP_UC or rule == c.ANCHORP_LC or rule == c.ANCHORP_C) p.position.x -= mid_x;
            if (rule == c.ANCHORP_CL or rule == c.ANCHORP_C) p.position.y -= mid_y;
            if (rule == c.ANCHORP_LC) p.position.y -= oh * d.scale.y;
        },
        else => {},
    }
}

fn add_anchor_shift(ref: *arcan_vobject, props: *surface_properties, dprop: *surface_properties, rule: c_int) void {
    const ow: f32 = @floatFromInt(ref.origw);
    const oh: f32 = @floatFromInt(ref.origh);
    const p = sp(props);
    const d = sp(dprop);
    switch (rule) {
        c.ANCHORP_UR => { p.position.x += ow * d.scale.x; },
        c.ANCHORP_LR => { p.position.y += oh * d.scale.y; p.position.x += ow * d.scale.x; },
        c.ANCHORP_LL => { p.position.y += oh * d.scale.y; },
        c.ANCHORP_CR => { p.position.y += oh * d.scale.y * 0.5; p.position.x += ow * d.scale.x; },
        c.ANCHORP_C, c.ANCHORP_UC, c.ANCHORP_CL, c.ANCHORP_LC => {
            const mid_y = (oh * d.scale.y) * 0.5;
            const mid_x = (ow * d.scale.x) * 0.5;
            if (rule == c.ANCHORP_UC or rule == c.ANCHORP_LC or rule == c.ANCHORP_C) p.position.x += mid_x;
            if (rule == c.ANCHORP_CL or rule == c.ANCHORP_C) p.position.y += mid_y;
            if (rule == c.ANCHORP_LC) p.position.y += oh * d.scale.y;
        },
        else => {},
    }
}

export fn arcan_resolve_vidprop(vobj: *arcan_vobject, lerp: f32, props: *surface_properties) void {
    if (vobj.valid_cache) {
        props.* = vobj.prop_cache;
    } else if (vobj.parent != null and vobj.parent != @as([*c]arcan_vobject, @ptrCast(&current_context.world))) {
        var dprop = empty_surface();
        arcan_resolve_vidprop(@ptrCast(vobj.parent), lerp, @ptrCast(&dprop));
        apply(vobj, props, @ptrCast(&dprop), lerp, false);

        if (vobj.p_scale != 0) {
            if (@as(c_uint, @intCast(vobj.p_scale)) & c.SCALEM_WIDTH != 0) {
                const pw_base = @as(f32, @floatFromInt(@as(*arcan_vobject, @ptrCast(vobj.parent)).origw)) * dprop.scale.x;
                const mw_d = @as(f32, @floatFromInt(vobj.origw)) +
                    ((@as(f32, @floatFromInt(vobj.origw)) * sp(props).scale.x) - @as(f32, @floatFromInt(vobj.origw)));
                sp(props).scale.x = (pw_base + mw_d - 1.0) / @as(f32, @floatFromInt(vobj.origw));
            }
            if (@as(c_uint, @intCast(vobj.p_scale)) & c.SCALEM_HEIGHT != 0) {
                const ph_base = @as(f32, @floatFromInt(@as(*arcan_vobject, @ptrCast(vobj.parent)).origh)) * dprop.scale.y;
                const mh_d = @as(f32, @floatFromInt(vobj.origh)) +
                    ((@as(f32, @floatFromInt(vobj.origh)) * sp(props).scale.y) - @as(f32, @floatFromInt(vobj.origh)));
                sp(props).scale.y = (ph_base + mh_d - 1.0) / @as(f32, @floatFromInt(vobj.origh));
            }
        }

        add_anchor_shift(@ptrCast(vobj.parent), props, @ptrCast(&dprop), @intCast(vobj.p_anchor));
        sub_anchor_shift(vobj, props, @ptrCast(&dprop), @intCast(vobj.p_anchor_shift));
    } else {
        apply(vobj, props, &current_context.world.current, lerp, true);
    }

    var cur: ?*arcan_vobject = vobj;
    var can_cache = true;
    while (cur) |obj| {
        if (obj.transform != null) { can_cache = false; break; }
        cur = obj.parent;
    }

    if (can_cache and vobj.owner != null and !vobj.valid_cache) {
        vobj.prop_cache = props.*;
        vobj.valid_cache = true;
        var dprop = props.*;
        build_modelview(&vobj.prop_matr, &@as(*rendertarget, @ptrCast(vobj.owner)).base, &dprop, vobj);
    }
}

inline fn build_modelview(dmatr: [*]f32, imatr: [*]f32, prop: *surface_properties, src: *arcan_vobject) void {
    var omatr: [16]f32 align(16) = undefined;
    var tmatr: [16]f32 align(16) = undefined;

    const p = sp(prop);
    p.scale.x *= @as(f32, @floatFromInt(src.origw)) * 0.5;
    p.scale.y *= @as(f32, @floatFromInt(src.origh)) * 0.5;
    p.position.x += p.scale.x;
    p.position.y += p.scale.y;

    src.rotate_state =
        @abs(prop.rotation.roll) > EPSILON or
        @abs(prop.rotation.pitch) > EPSILON or
        @abs(prop.rotation.yaw) > EPSILON;

    @memcpy(tmatr[0..16], imatr[0..16]);

    if (src.rotate_state) {
        if (flTest(src, c.FL_FULL3D))
            _ = c.matr_quatf(c.norm_quat(prop.rotation.quaternion), &omatr)
        else
            _ = c.matr_rotatef(@floatCast(c.DEG2RAD(prop.rotation.roll)), &omatr);
    }

    const oofs = src.origo_ofs.unnamed_0.unnamed_0;
    if (oofs.x > EPSILON or oofs.y > EPSILON) {
        c.translate_matrix(&tmatr, p.position.x + oofs.x, p.position.y + oofs.y, 0.0);
        c.multiply_matrix(dmatr, &tmatr, &omatr);
        c.translate_matrix(dmatr, -oofs.x, -oofs.y, 0.0);
    } else {
        c.translate_matrix(&tmatr, p.position.x, p.position.y, 0.0);
    }

    if (src.rotate_state)
        c.multiply_matrix(dmatr, &tmatr, &omatr)
    else
        @memcpy(dmatr[0..16], tmatr[0..16]);
}

inline fn time_ratio(start: c.arcan_tickv, stop: c.arcan_tickv) f32 {
    if (start > 0) {
        const num: f32 = @floatFromInt(@as(i64, @intCast(arcan_video_display.c_ticks)) - @as(i64, start));
        const den: f32 = @floatFromInt(@as(i64, @intCast(stop)) - @as(i64, start));
        return num / den;
    }
    return 1.0;
}

fn update_shenv(src: *arcan_vobject, prop: *surface_properties) void {
    _ = c.agp_shader_envv(c.OBJ_OPACITY, &prop.opa, @sizeOf(f32));

    var sz_i = [2]f32{ @floatFromInt(src.origw), @floatFromInt(src.origh) };
    _ = c.agp_shader_envv(c.SIZE_INPUT, &sz_i, @sizeOf(f32) * 2);

    var sz_o = [2]f32{ sp(prop).scale.x * 2.0, sp(prop).scale.y * 2.0 };
    _ = c.agp_shader_envv(c.SIZE_OUTPUT, &sz_o, @sizeOf(f32) * 2);

    var active_vstore: *agp_vstore = src.vstore.?;
    if (@as(?*c.struct_vobject_frameset, @ptrCast(src.frameset))) |fs| {
        if (fs.mode == c.ARCAN_FRAMESET_SPLIT)
            active_vstore = fs.frames[fs.index].frame;
    }

    var sz_s = [2]f32{ @floatFromInt(active_vstore.w), @floatFromInt(active_vstore.h) };
    _ = c.agp_shader_envv(c.SIZE_STORAGE, &sz_s, @sizeOf(f32) * 2);

    if (@as(?*surface_transform, @ptrCast(src.transform))) |trans| {
        var ev = time_ratio(trans.move.startt, trans.move.endt);
        _ = c.agp_shader_envv(c.TRANS_MOVE, &ev, @sizeOf(f32));
        ev = time_ratio(trans.rotate.startt, trans.rotate.endt);
        _ = c.agp_shader_envv(c.TRANS_ROTATE, &ev, @sizeOf(f32));
        ev = time_ratio(trans.scale.startt, trans.scale.endt);
        _ = c.agp_shader_envv(c.TRANS_SCALE, &ev, @sizeOf(f32));
        ev = time_ratio(trans.blend.startt, trans.blend.endt);
        _ = c.agp_shader_envv(c.TRANS_BLEND, &ev, @sizeOf(f32));
    } else {
        var ev: f32 = 1.0;
        _ = c.agp_shader_envv(c.TRANS_MOVE, &ev, @sizeOf(f32));
        _ = c.agp_shader_envv(c.TRANS_ROTATE, &ev, @sizeOf(f32));
        _ = c.agp_shader_envv(c.TRANS_SCALE, &ev, @sizeOf(f32));
        _ = c.agp_shader_envv(c.TRANS_BLEND, &ev, @sizeOf(f32));
    }
}

fn setup_surf(dst: *rendertarget, prop: *surface_properties, src: *arcan_vobject, mv: *[*]f32) void {
    const S = struct { var dmatr: [16]f32 align(16) = undefined; };
    if (src.feed.state.tag == c.ARCAN_TAG_ASYNCIMGLD) return;

    if (src.valid_cache and dst == src.owner) {
        const p = sp(prop);
        p.scale.x *= @as(f32, @floatFromInt(src.origw)) * 0.5;
        p.scale.y *= @as(f32, @floatFromInt(src.origh)) * 0.5;
        p.position.x += p.scale.x;
        p.position.y += p.scale.y;
        mv.* = &src.prop_matr;
    } else {
        build_modelview(&S.dmatr, &dst.base, prop, src);
        mv.* = &S.dmatr;
    }
    update_shenv(src, prop);
}

fn setup_shape_surf(dst: *rendertarget, prop: *surface_properties, src: *arcan_vobject, mv: *[*]f32) void {
    const S = struct { var dmatr: [16]f32 align(16) = undefined; };
    if (src.feed.state.tag == c.ARCAN_TAG_ASYNCIMGLD) return;
    build_modelview(&S.dmatr, &dst.base, prop, src);
    mv.* = &S.dmatr;
    c.scale_matrix(mv.*, sp(prop).scale.x, sp(prop).scale.y, 1.0);
    update_shenv(src, prop);
}

fn draw_colorsurf(dst: *rendertarget, prop: surface_properties, src: *arcan_vobject, r: f32, g: f32, b: f32, txcos: [*c]f32) void {
    var cval = [3]f32{ r, g, b };
    var mvm: [*]f32 = undefined;
    var mprop = prop;
    setup_surf(dst, &mprop, src, &mvm);
    c.agp_shader_forceunif("obj_col", c.shdrvec3, @ptrCast(&cval));
    const mp = sp(&mprop);
    c.agp_draw_vobj(-mp.scale.x, -mp.scale.y, mp.scale.x, mp.scale.y, txcos, mvm);
}

fn draw_texsurf(dst: *rendertarget, prop: surface_properties, src: *arcan_vobject, txcos: [*c]f32) void {
    var mvm: [*]f32 = undefined;
    var mprop = prop;
    if (@as(?*c.struct_agp_mesh_store, @ptrCast(src.shape))) |shape| {
        if (!shape.nodepth) c.agp_pipeline_hint(c.PIPELINE_3D);
        setup_shape_surf(dst, &mprop, src, &mvm);
        _ = c.agp_shader_envv(c.MODELVIEW_MATR, mvm, @sizeOf(f32) * 16);
        c.agp_submit_mesh(shape, c.MESH_FACING_BOTH);
        if (!shape.nodepth) c.agp_pipeline_hint(c.PIPELINE_2D);
    } else {
        setup_surf(dst, &mprop, src, &mvm);
        const mp2 = sp(&mprop);
        c.agp_draw_vobj(-mp2.scale.x, -mp2.scale.y, mp2.scale.x, mp2.scale.y, txcos, mvm);
    }
}

fn ffunc_process(dst: *arcan_vobject, step: bool) void {
    if (dst.feed.ffunc == 0) return;
    const ffunc = c.arcan_ffunc_lookup(@as(u8, @intCast(dst.feed.ffunc))) orelse return;
    const frame_status = ffunc(c.FFUNC_POLL, null, 0, 0, 0, 0, dst.feed.state, dst.cellid);

    // DIAG: log pollfeed — only first 5 for each vid to avoid flood
    // Also print vobj address and raw vstore pointer value
    // pollfeed debug block removed

    if (frame_status == c.FRV_GOTFRAME) {
        if (!step) return;
        flagDirty(dst);
        // The pcookie de-dup gate from the original ported C — `if pcookie ==
        // arcan_video_display.cookie return;` — silently skipped FFUNC_RENDER
        // for subsegment vobjs. Without RENDER, vready in the kid's shmpage
        // never gets cleared, the kid spins in tui_screen_refresh forever
        // ("SIGVID still outstanding" diagnostic), and lash terminals never
        // become visible in durian even though shmif registration succeeds.
        //
        // Removing the gate: every GOTFRAME now drives a RENDER. The pcookie
        // field is still updated so any downstream code that reads it sees
        // the latest cycle. Verified live: 3 lash subsegments rendering
        // continuously, kid logs growing instead of stalling at the 2348-byte
        // post-preroll size.
        dst.feed.pcookie = arcan_video_display.cookie;

        if (@as(?*c.struct_vobject_frameset, @ptrCast(dst.frameset))) |fs| {
            if (fs.mctr != 0) {
                fs.ctr -= 1;
                if (fs.ctr == 0) {
                    fs.ctr = if (fs.mctr < 0) -fs.mctr else fs.mctr;
                    step_active_frame(dst);
                }
            }
        }

        const vs: *agp_vstore = @ptrCast(dst.vstore);
        _ = ffunc(c.FFUNC_RENDER,
            vs.vinf.text.raw, vs.vinf.text.s_raw,
            @intCast(vs.w), @intCast(vs.h), vs.vinf.text.glid,
            dst.feed.state, dst.cellid);

        arcan_video_display.dirty += 1;
        if (@as(?*rendertarget, @ptrCast(dst.owner))) |owner| { owner.uploadc += 1; owner.transfc += 1; }
    }
}

export fn arcan_vint_pollfeed(vid: arcan_vobj_id, step: bool) arcan_errc {
    const vobj = arcan_video_getobject(vid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    ffunc_process(vobj, step);
    return ARCAN_OK;
}

fn poll_list(first_in: ?*arcan_vobject_litem) void {
    // ffunc_process can cascade into arcan_video_deleteobject →
    // detach_fromtarget → arcan_mem_free(litem). If we cached `cur.next`
    // before the callback and the callback freed it, the next iteration
    // would walk into a reused allocation (we observed cur.elem = ASCII
    // "uiprim_b…" — a uiprim tag string that the allocator had reused
    // that slot for). This produced an arcan SIGSEGV at `celem.feed.ffunc`
    // whenever a networked frameserver torn down fast (arcan-net bridge
    // disconnects). Mirror the guard that tick_rendertarget already uses:
    // check rt_list_generation around each callback, restart from `first`
    // on mutation, and validate that cur.elem points to a live vitems_pool
    // entry before dereferencing.
    var current = first_in;
    while (@as(?*arcan_vobject_litem, @ptrCast(current))) |cur| {
        const gen_before = rt_list_generation;
        const next: ?*arcan_vobject_litem = @ptrCast(cur.next);

        if (@intFromPtr(cur.elem) == 0xfeedface or cur.elem == null) {
            current = next;
            continue;
        }
        const elem: *arcan_vobject = @ptrCast(cur.elem);

        const pool_base = @intFromPtr(current_context.vitems_pool);
        const pool_end = pool_base + @as(usize, @intCast(current_context.vitem_limit)) * @sizeOf(arcan_vobject);
        const elem_addr = @intFromPtr(elem);
        if (elem_addr < pool_base or elem_addr >= pool_end or
            (elem_addr - pool_base) % @sizeOf(arcan_vobject) != 0 or
            !flTest(elem, c.FL_INUSE))
        {
            current = next;
            continue;
        }

        if (elem.feed.ffunc != 0) ffunc_process(elem, true);

        if (rt_list_generation != gen_before) {
            // callback freed something; restart walk to avoid stale next
            current = first_in;
            continue;
        }
        current = next;
    }
}

// DIAG: direct-file-IO logger bypassing arcan_warning. Writes to fixed
export fn arcan_video_pollfeed() void {
    var ind: usize = 0;
    while (ind < @as(usize, @intCast(current_context.n_rtargets))) : (ind += 1)
        arcan_vint_pollreadback(&current_context.rtargets[ind]);
    arcan_vint_pollreadback(&current_context.stdoutp);

    var i: usize = 0;
    while (i < @as(usize, @intCast(current_context.n_rtargets))) : (i += 1)
        poll_list(current_context.rtargets[i].first);
    poll_list(current_context.stdoutp.first);
}

fn get_clip_source(vobj: *arcan_vobject) ?*arcan_vobject {
    var res: ?*arcan_vobject = vobj.parent;
    if (vobj.clip_src != 0 and vobj.clip_src != ARCAN_VIDEO_WORLDID) {
        if (arcan_video_getobject(vobj.clip_src)) |clipref| return clipref;
    }
    if (vobj.parent == &current_context.world) res = null;
    return res;
}

fn populate_stencil(tgt: *rendertarget, celem_in: *arcan_vobject, fract: f32) void {
    c.agp_prepare_stencil();
    _ = c.agp_shader_activate(tgt.shid);

    if (celem_in.clip == c.ARCAN_CLIP_SHALLOW) {
        if (get_clip_source(celem_in)) |cs| {
            var pprops = empty_surface();
            arcan_resolve_vidprop(cs, fract, @ptrCast(&pprops));
            draw_colorsurf(tgt, toCSP(pprops), cs, 1.0, 1.0, 1.0, null);
        }
    } else {
        var celem: *arcan_vobject = celem_in;
        while (celem.parent != null and celem.parent != &current_context.world) {
            const parent: *arcan_vobject = @ptrCast(celem.parent);
            var pprops = empty_surface();
            arcan_resolve_vidprop(parent, fract, @ptrCast(&pprops));
            if (parent.clip == c.ARCAN_CLIP_OFF)
                draw_colorsurf(tgt, toCSP(pprops), parent, 1.0, 1.0, 1.0, null)
            else if (parent.clip == c.ARCAN_CLIP_SHALLOW) {
                draw_colorsurf(tgt, toCSP(pprops), parent, 1.0, 1.0, 1.0, null);
                break;
            }
            celem = parent;
        }
    }
    c.agp_activate_stencil();
}

export fn arcan_vint_bindmulti(elem: *arcan_vobject, ind_in: usize) void {
    const set: *c.struct_vobject_frameset = @ptrCast(elem.frameset orelse return);
    const sz = set.n_frames;
    var elems_buf: [64]?*agp_vstore = undefined;
    var ind = ind_in;
    const count = @min(sz, 64);
    for (0..count) |i_| {
        elems_buf[i_] = set.frames[ind].frame;
        ind = if (ind > 0) ind - 1 else sz - 1;
    }
    c.agp_activate_vstore_multi(@ptrCast(&elems_buf), count);
}

fn draw_vobj(tgt: *rendertarget, vobj: *arcan_vobject, dprops: *surface_properties, txcos: [*c]f32) c_int {
    if (vobj.blendmode == c.BLEND_NORMAL and dprops.opa > 1.0 - EPSILON)
        c.agp_blendstate(c.BLEND_NONE)
    else
        c.agp_blendstate(vobj.blendmode);

    const vstore: *agp_vstore = vobj.vstore.?;
    if (vstore.txmapped == c.TXSTATE_OFF and vobj.program != 0) {
        draw_colorsurf(tgt, dprops.*, vobj, vstore.vinf.col.r, vstore.vinf.col.g, vstore.vinf.col.b, txcos);
        return 1;
    }
    if (vstore.txmapped == c.TXSTATE_TEX2D) {
        draw_texsurf(tgt, dprops.*, vobj, txcos);
        return 1;
    }
    return 0;
}

fn setup_shallow_texclip(elem: *arcan_vobject, clip_src: *arcan_vobject, dstcos: *[*c]f32, dprops: *surface_properties, fract: f32) bool {
    const S = struct { var cliptxbuf: [8]f32 = undefined; };
    var pprops = empty_surface();
    arcan_resolve_vidprop(clip_src, fract, @ptrCast(&pprops));

    const p_x = pprops.position.x;
    const p_y = pprops.position.y;
    const p_w = pprops.scale.x * @as(f32, @floatFromInt(clip_src.origw));
    const p_h = pprops.scale.y * @as(f32, @floatFromInt(clip_src.origh));
    const p_xw = p_x + p_w;
    const p_yh = p_y + p_h;

    const dp = sp(dprops);
    var cp_x = dp.position.x;
    var cp_y = dp.position.y;
    var cp_w = dp.scale.x * @as(f32, @floatFromInt(elem.origw));
    var cp_h = dp.scale.y * @as(f32, @floatFromInt(elem.origh));
    const cp_xw = cp_x + cp_w;
    const cp_yh = cp_y + cp_h;

    if (cp_xw < p_x or cp_yh < p_y or cp_x > p_xw or cp_y > p_yh) {
        return false;
    }
    if (cp_x >= p_x and cp_xw <= p_xw and cp_y >= p_y and cp_yh <= p_yh) return true;

    const src_txcos: [*]f32 = dstcos.*;
    @memcpy(&S.cliptxbuf, src_txcos[0..8]);
    const xrange = S.cliptxbuf[2] - S.cliptxbuf[0];
    const yrange = S.cliptxbuf[7] - S.cliptxbuf[1];
    const origw_f: f32 = @floatFromInt(elem.origw);
    const origh_f: f32 = @floatFromInt(elem.origh);

    if (cp_x < p_x) {
        const sl = ((p_x - cp_x) / origw_f) * xrange;
        cp_w -= p_x - cp_x; S.cliptxbuf[0] += sl; S.cliptxbuf[6] += sl; cp_x = p_x;
    }
    if (cp_y < p_y) {
        const su = ((p_y - cp_y) / origh_f) * yrange;
        cp_h -= p_y - cp_y; S.cliptxbuf[1] += su; S.cliptxbuf[3] += su; cp_y = p_y;
    }
    if (cp_x + cp_w > p_xw) {
        const sr = ((cp_x + cp_w) - p_xw) / origw_f * xrange;
        cp_w -= (cp_x + cp_w) - p_xw; S.cliptxbuf[2] -= sr; S.cliptxbuf[4] -= sr;
    }
    if (cp_y + cp_h > p_yh) {
        const sd = ((cp_y + cp_h) - p_yh) / origh_f * yrange;
        cp_h -= (cp_y + cp_h) - p_yh; S.cliptxbuf[5] -= sd; S.cliptxbuf[7] -= sd;
    }

    dp.position.x = cp_x;
    dp.position.y = cp_y;
    dp.scale.x = cp_w / origw_f;
    dp.scale.y = cp_h / origh_f;
    elem.valid_cache = false;
    dstcos.* = &S.cliptxbuf;
    return true;
}

fn process_rendertarget(tgt: *rendertarget, fract: f32, nest_in: bool) usize {
    var pc: usize = if (arcan_video_display.ignore_dirty != 0) 1 else 0;
    var nest = nest_in;

    if (@as(?*rendertarget, @ptrCast(tgt.link))) |link_tgt| {
        const tmp_cur = tgt.first;
        tgt.first = link_tgt.first;
        tgt.link = null;
        const old_msc = tgt.msc;
        pc += process_rendertarget(tgt, fract, false);
        nest = pc > 0;
        tgt.first = tmp_cur;
        tgt.link = @ptrCast(link_tgt);
        tgt.dirtyc += link_tgt.dirtyc;
        tgt.transfc += link_tgt.transfc;
        tgt.msc = old_msc;
    }

    var current: ?*arcan_vobject_litem = tgt.first;

    if (arcan_video_display.dirty == 0 and arcan_video_display.ignore_dirty == 0 and
        tgt.dirtyc == 0 and tgt.transfc == 0) return 0;

    tgt.uploadc = 0;
    tgt.msc += 1;

    if (tgt.color != null and !nest)
        _ = c.agp_rendertarget_swapstore(tgt.art, @as(*arcan_vobject, @ptrCast(tgt.color)).vstore);

    _current_rendertarget = tgt;
    c.agp_activate_rendertarget(tgt.art);
    _ = c.agp_shader_envv(c.RTGT_ID, &tgt.id, @sizeOf(c_int));
    var unit_opa: f32 = 1.0;
    _ = c.agp_shader_envv(c.OBJ_OPACITY, &unit_opa, @sizeOf(f32));

    if (!rtFlTest(tgt, c.TGTFL_NOCLEAR) and !nest)
        c.agp_rendertarget_clear();

    // 3D first pass
    if (tgt.order3d == c.ORDER3D_FIRST) {
        if (current) |cur| {
            if (@intFromPtr(cur.elem) != 0xfeedface and cur.elem != null and
                @as(*arcan_vobject, @ptrCast(cur.elem)).order < 0)
            {
                current = c.arcan_3d_refresh(tgt.camtag, current, fract);
                pc += 1;
            }
        }
    }

    // skip 3d pipeline
    while (current) |cur| {
        if (@intFromPtr(cur.elem) == 0xfeedface)
        { current = cur.next; continue; } // poisoned — skip
        if (cur.elem == null or @as(*arcan_vobject, @ptrCast(cur.elem)).order >= 0) break;
        current = cur.next;
    }

    // 2D processing
    if (current != null) {
        c.agp_pipeline_hint(c.PIPELINE_2D);
        _ = c.agp_shader_activate(c.agp_default_shader(c.BASIC_2D));
        _ = c.agp_shader_envv(c.PROJECTION_MATR, &tgt.projection, @sizeOf(f32) * 16);

        while (current) |cur| {
            if (@intFromPtr(cur.elem) == 0xfeedface)
            { current = cur.next; continue; } // poisoned — skip
            const elem: *arcan_vobject = cur.elem orelse { current = cur.next; continue; };
            if (elem.order < 0) { current = cur.next; continue; }
            if (elem.order < @as(c_int, @intCast(tgt.min_order))) { current = cur.next; continue; }
            if (elem.order > @as(c_int, @intCast(tgt.max_order))) break;

            var dprops = empty_surface();
            arcan_resolve_vidprop(elem, fract, @ptrCast(&dprops));

            if (dprops.opa <= EPSILON or elem == tgt.color) {
                current = cur.next; continue;
            }

            var txcos: [*c]f32 = elem.txcos;
            if ((@as(c_uint, @bitCast(elem.mask)) & c.MASK_MAPPING) > 0)
                txcos = if (elem.parent != &current_context.world) @as(*arcan_vobject, @ptrCast(elem.parent)).txcos else elem.txcos;
            if (txcos == null) txcos = &arcan_video_display.default_txcos;

            var shid: agp_shader_id = tgt.shid;
            if (!tgt.force_shid and elem.program != 0) shid = elem.program;
            _ = c.agp_shader_activate(shid);

            if (@as(?*c.struct_vobject_frameset, @ptrCast(elem.frameset))) |fs| {
                if (fs.mode == c.ARCAN_FRAMESET_MULTITEXTURE) {
                    arcan_vint_bindmulti(elem, fs.index);
                } else {
                    const ds = &fs.frames[fs.index];
                    txcos = &ds.txcos;
                    c.agp_activate_vstore(ds.frame);
                }
            } else {
                c.agp_activate_vstore(elem.vstore);
            }

            current = cur.next;

            const clip_src = get_clip_source(elem);
            if (elem.clip == c.ARCAN_CLIP_OFF or clip_src == null) {
                pc += @intCast(draw_vobj(tgt, elem, @ptrCast(&dprops), txcos));
                continue;
            }

            if (elem.clip == c.ARCAN_CLIP_SHALLOW and !elem.rotate_state and !clip_src.?.rotate_state) {
                const clip_ok = setup_shallow_texclip(elem, @as(*arcan_vobject, @ptrCast(clip_src)), &txcos, @ptrCast(&dprops), fract);
                if (!clip_ok) continue;
                pc += @intCast(draw_vobj(tgt, elem, @ptrCast(&dprops), txcos));
                continue;
            }

            populate_stencil(tgt, elem, fract);
            pc += @intCast(draw_vobj(tgt, elem, @ptrCast(&dprops), txcos));
            c.agp_disable_stencil();
        }
    }

    // end3d
    current = tgt.first;
    if (current) |cur| {
        if (@intFromPtr(cur.elem) != 0xfeedface and cur.elem != null and
            @as(*arcan_vobject, @ptrCast(cur.elem)).order < 0 and tgt.order3d == c.ORDER3D_LAST)
        {
            _ = c.agp_shader_activate(c.agp_default_shader(c.BASIC_2D));
            const new_current = c.arcan_3d_refresh(tgt.camtag, current, fract);
            if (new_current != tgt.first) pc += 1;
        }
    }

    if (pc > 0) tgt.frame_cookie = arcan_video_display.cookie;
    return pc;
}

// ============================================================
// Chunk 8: Context management, drawing helpers, misc
// ============================================================

fn rebase_transform(current_xf: ?*surface_transform, ofs: i64) void {
    var xf = current_xf orelse return;
    const ofs32: u32 = @truncate(@as(u64, @bitCast(ofs)));
    if (xf.move.startt != 0) {
        xf.move.startt +%= ofs32;
        xf.move.endt +%= ofs32;
    }
    if (xf.rotate.startt != 0) {
        xf.rotate.startt +%= ofs32;
        xf.rotate.endt +%= ofs32;
    }
    if (xf.scale.startt != 0) {
        xf.scale.startt +%= ofs32;
        xf.scale.endt +%= ofs32;
    }
    rebase_transform(@ptrCast(xf.next), ofs);
}

fn deallocate_gl_context(context: *c.struct_arcan_video_context, del: bool, safe_store: ?*agp_vstore) void {
    var i: usize = 1;
    while (i < context.vitem_limit) : (i += 1) {
        if (flTest(@as(*const arcan_vobject, @ptrCast(&context.vitems_pool[i])), c.FL_INUSE)) {
            const cur: *arcan_vobject = @ptrCast(&context.vitems_pool[i]);
            if (cur.feed.state.tag == c.ARCAN_TAG_ASYNCIMGLD or
                cur.feed.state.tag == c.ARCAN_TAG_ASYNCIMGRD)
                _ = arcan_video_pushasynch(@intCast(i));

            if (del) {
                _ = arcan_video_deleteobject(@intCast(i));
            } else if (!flTest(cur, c.FL_PRSIST) and !flTest(cur, c.FL_RTGT) and
                cur.vstore != safe_store)
            {
                c.agp_null_vstore(cur.vstore);
            }
        }
    }
    if (del) {
        c.arcan_mem_free(@ptrCast(context.vitems_pool));
        context.vitems_pool = null;
    }
}

fn reallocate_gl_context(context: *c.struct_arcan_video_context) void {
    const cticks = arcan_video_display.c_ticks;
    if (context.vitems_pool == null) {
        context.vitem_limit = arcan_video_display.default_vitemlim;
        context.vitem_ofs = 1;
        context.vitems_pool = @ptrCast(@alignCast(c.arcan_alloc_mem(
            @sizeOf(arcan_vobject) * context.vitem_limit,
            c.ARCAN_MEM_VSTRUCT,
            c.ARCAN_MEM_BZERO,
            c.ARCAN_MEMALIGN_NATURAL,
        )));
    } else {
        var i: usize = 1;
        while (i < context.vitem_limit) : (i += 1) {
            if (!flTest(@as(*const arcan_vobject, @ptrCast(&context.vitems_pool[i])), c.FL_INUSE)) continue;
            const cur: *arcan_vobject = @ptrCast(&context.vitems_pool[i]);
            if (flTest(cur, c.FL_PRSIST)) continue;

            const ctrans = cur.transform;
            if (ctrans != null and cticks > context.last_tickstamp) {
                rebase_transform(ctrans, @as(i64, @intCast(cticks)) - @as(i64, @intCast(context.last_tickstamp)));
            }

            if (arcan_video_display.conservative and
                cur.feed.state.tag == c.ARCAN_TAG_IMAGE)
            {
                const src_ptr: [*c]u8 = @as(*agp_vstore, @ptrCast(cur.vstore)).vinf.text.unnamed_0.source;
                const fname: [*c]u8 = c.strdup(src_ptr);
                c.arcan_mem_free(@ptrCast(@as(*agp_vstore, @ptrCast(cur.vstore)).vinf.text.unnamed_0.source));
                _ = arcan_vint_getimage(fname, cur, .{ .w = cur.origw, .h = cur.origh, .bpp = 0 }, false);
                c.arcan_mem_free(@ptrCast(fname));
            } else if (@as(*agp_vstore, @ptrCast(cur.vstore)).txmapped != c.TXSTATE_OFF) {
                c.agp_update_vstore(cur.vstore, true);
            }

            const fsrv: ?*c.struct_arcan_frameserver = @ptrCast(@alignCast(cur.feed.state.ptr));
            if (cur.feed.state.tag == c.ARCAN_TAG_FRAMESERV and fsrv != null) {
                arcan_frameserver_flush(fsrv);
                arcan_frameserver_resume(fsrv);
                _ = c.arcan_audio_play(fsrv_helper_get_aid(fsrv.?), false, 0.0, -2);
            }
        }
    }
}

fn push_transfer_persists(src: *c.struct_arcan_video_context, dst: *c.struct_arcan_video_context) void {
    var i: usize = 1;
    while (i < src.vitem_limit -| 1) : (i += 1) {
        const srcobj: *arcan_vobject = @ptrCast(&src.vitems_pool[i]);
        const dstobj: *arcan_vobject = @ptrCast(&dst.vitems_pool[i]);
        if (!flTest(srcobj, c.FL_INUSE) or !flTest(srcobj, c.FL_PRSIST)) continue;

        _ = detach_fromtarget(srcobj.owner, srcobj);
        const src_bytes = @as([*]u8, @ptrCast(srcobj));
        const dst_bytes = @as([*]u8, @ptrCast(dstobj));
        @memcpy(dst_bytes[0..@sizeOf(arcan_vobject)], src_bytes[0..@sizeOf(arcan_vobject)]);
        dst.nalive += 1;
        dstobj.parent = &dst.world;
        attach_object(&dst.stdoutp, dstobj);
    }
}

fn pop_transfer_persists(src: *c.struct_arcan_video_context, dst: *c.struct_arcan_video_context) void {
    var i: usize = 1;
    while (i < src.vitem_limit -| 1) : (i += 1) {
        const srcobj: *arcan_vobject = @ptrCast(&src.vitems_pool[i]);
        const dstobj: *arcan_vobject = @ptrCast(&dst.vitems_pool[i]);
        if (!flTest(srcobj, c.FL_INUSE) or !flTest(srcobj, c.FL_PRSIST)) continue;

        const parent = dstobj.parent;
        _ = detach_fromtarget(srcobj.owner, srcobj);
        src.nalive -= 1;

        const src_bytes = @as([*]u8, @ptrCast(srcobj));
        const dst_bytes = @as([*]u8, @ptrCast(dstobj));
        @memcpy(dst_bytes[0..@sizeOf(arcan_vobject)], src_bytes[0..@sizeOf(arcan_vobject)]);
        attach_object(&dst.stdoutp, dstobj);
        dstobj.parent = parent;
        @memset(src_bytes[0..@sizeOf(arcan_vobject)], 0);
    }
}

export fn arcan_video_pushcontext() c_int {
    var empty_vobj: arcan_vobject = std.mem.zeroes(arcan_vobject);
    empty_vobj.current.opa = 1.0;
    sp(&empty_vobj.current).scale.x = 1.0;
    sp(&empty_vobj.current).scale.y = 1.0;
    sp(&empty_vobj.current).scale.z = 1.0;
    empty_vobj.current.rotation.quaternion = c.default_quat;
    empty_vobj.vstore = current_context.world.vstore;

    if (vcontext_ind + 1 == CONTEXT_STACK_LIMIT)
        return -1;

    current_context.last_tickstamp = arcan_video_display.c_ticks;

    const src_bytes = @as([*]const u8, @ptrCast(current_context));
    const dst_bytes = @as([*]u8, @ptrCast(&vcontext_stack[vcontext_ind + 1]));
    @memcpy(dst_bytes[0..@sizeOf(c.struct_arcan_video_context)], src_bytes[0..@sizeOf(c.struct_arcan_video_context)]);

    deallocate_gl_context(current_context, false, empty_vobj.vstore);

    if (@as(?*agp_vstore, @ptrCast(current_context.world.vstore))) |ws| {
        empty_vobj.origw = @intCast(ws.w);
        empty_vobj.origh = @intCast(ws.h);
    }

    vcontext_ind += 1;
    current_context = &vcontext_stack[vcontext_ind];
    current_context.stdoutp.first = null;
    current_context.vitem_ofs = 1;
    current_context.nalive = 0;
    current_context.world = empty_vobj;
    current_context.stdoutp.refreshcnt = 1;
    current_context.stdoutp.refresh = 1;
    current_context.stdoutp.vppcm = 28;
    current_context.stdoutp.hppcm = 28;
    current_context.stdoutp.color = &current_context.world;
    current_context.stdoutp.max_order = 65536;
    current_context.vitem_limit = arcan_video_display.default_vitemlim;
    current_context.vitems_pool = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @sizeOf(arcan_vobject) * current_context.vitem_limit,
        c.ARCAN_MEM_VSTRUCT,
        c.ARCAN_MEM_BZERO,
        c.ARCAN_MEMALIGN_NATURAL,
    )));
    current_context.rtargets[0].first = null;

    push_transfer_persists(&vcontext_stack[vcontext_ind - 1], current_context);
    flagDirty(null);

    return @intCast(arcan_video_nfreecontexts());
}

export fn arcan_video_popcontext() c_uint {
    if (vcontext_ind > 0)
        pop_transfer_persists(current_context, &vcontext_stack[vcontext_ind - 1]);

    deallocate_gl_context(current_context, true, current_context.world.vstore);

    if (vcontext_ind > 0) {
        vcontext_ind -= 1;
        current_context = &vcontext_stack[vcontext_ind];
    }

    reallocate_gl_context(current_context);
    flagDirty(null);

    return @intCast(@as(usize, @intCast(CONTEXT_STACK_LIMIT)) - 1 - vcontext_ind);
}

export fn arcan_video_recoverexternal(pop: bool, saved: *c_int, truncated: *c_int, adopt: ?*const fn (arcan_vobj_id, ?*anyopaque) callconv(.c) void, tag: ?*anyopaque) void {
    saved.* = 0;
    truncated.* = 0;
    var n_ext: usize = 0;

    // pass 1: count frameservers and disable rtgt proxies
    var ctx_i: usize = 0;
    while (ctx_i <= vcontext_ind) : (ctx_i += 1) {
        const ctx = &vcontext_stack[ctx_i];
        var j: usize = 1;
        while (j < ctx.vitem_limit) : (j += 1) {
            if (flTest(@ptrCast(&ctx.vitems_pool[j]), c.FL_INUSE)) {
                if (ctx.vitems_pool[j].feed.state.tag == c.ARCAN_TAG_FRAMESERV)
                    n_ext += 1;
            }
        }
        var k: usize = 0;
        while (k < @as(usize, @intCast(ctx.n_rtargets))) : (k += 1) {
            c.agp_rendertarget_proxy(ctx.rtargets[k].art, null, 0);
        }
    }

    // use heap-allocated arrays instead of VLA
    const AlimEntry = struct {
        gl_store: ?*agp_vstore,
        tracetag: [*c]u8,
        ffunc: c.ffunc_ind,
        state: vfunc_state,
        origw: c_int,
        origh: c_int,
        zv: c_int,
    };

    if (n_ext == 0) {
        if (pop) {
            var lastctxc = arcan_video_popcontext();
            while (true) {
                const lastctxa = arcan_video_popcontext();
                if (lastctxc == lastctxa) break;
                lastctxc = lastctxa;
            }
        }
        return;
    }

    if (n_ext >= VITEM_CONTEXT_LIMIT - 1)
        n_ext = VITEM_CONTEXT_LIMIT - 1;
    if (n_ext > arcan_video_display.default_vitemlim)
        arcan_video_display.default_vitemlim = @intCast(n_ext + 1);

    const alim: [*]AlimEntry = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @sizeOf(AlimEntry) * (n_ext + 1),
        c.ARCAN_MEM_VSTRUCT,
        c.ARCAN_MEM_BZERO,
        c.ARCAN_MEMALIGN_NATURAL,
    )));
    defer c.arcan_mem_free(@ptrCast(alim));

    const audbuf: [*]c.arcan_aobj_id = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @sizeOf(c.arcan_aobj_id) * (n_ext + 1),
        c.ARCAN_MEM_VSTRUCT,
        c.ARCAN_MEM_BZERO,
        c.ARCAN_MEMALIGN_NATURAL,
    )));
    defer c.arcan_mem_free(@ptrCast(audbuf));

    var s_ofs: usize = 0;
    ctx_i = 0;
    while (ctx_i <= vcontext_ind) : (ctx_i += 1) {
        const ctx = &vcontext_stack[ctx_i];
        var j: usize = 1;
        while (j < ctx.vitem_limit) : (j += 1) {
            if (!flTest(@ptrCast(&ctx.vitems_pool[j]), c.FL_INUSE) or
                ctx.vitems_pool[j].feed.state.tag != c.ARCAN_TAG_FRAMESERV) continue;

            const cobj = &ctx.vitems_pool[j];
            if (cobj.feed.ffunc == c.FFUNC_SOCKVER or cobj.feed.ffunc == c.FFUNC_SOCKPOLL)
                continue;

            const fsrv: *c.struct_arcan_frameserver = @ptrCast(@alignCast(cobj.feed.state.ptr));
            if (fsrv_helper_get_no_adopt(fsrv)) continue;

            if (s_ofs < n_ext) {
                alim[s_ofs] = .{
                    .state = cobj.feed.state,
                    .ffunc = @intCast(cobj.feed.ffunc),
                    .gl_store = cobj.vstore,
                    .origw = @intCast(cobj.origw),
                    .origh = @intCast(cobj.origh),
                    .zv = @intCast(ctx_i + 1),
                    .tracetag = if (cobj.tracetag != null) c.strdup(cobj.tracetag) else null,
                };
                audbuf[s_ofs] = fsrv_helper_get_aid(fsrv);
                @as(*agp_vstore, @ptrCast(cobj.vstore)).refcount += 1;
                cobj.feed.state.tag = c.ARCAN_TAG_NONE;
                cobj.feed.ffunc = c.FFUNC_FATAL;
                cobj.feed.state.ptr = null;
                s_ofs += 1;
            } else {
                truncated.* += 1;
            }
        }
    }

    if (pop) {
        var lastctxc = arcan_video_popcontext();
        while (true) {
            const lastctxa = arcan_video_popcontext();
            if (lastctxc == lastctxa) break;
            lastctxc = lastctxa;
        }
    }

    // pass 3: setup new world
    var i: usize = 0;
    while (i < s_ofs) : (i += 1) {
        var did: arcan_vobj_id = undefined;
        const vobj = new_vobject(&did, current_context) orelse continue;
        vobj.vstore = alim[i].gl_store;
        vobj.feed.state = alim[i].state;
        vobj.feed.ffunc = alim[i].ffunc;
        vobj.origw = @intCast(alim[i].origw);
        vobj.origh = @intCast(alim[i].origh);
        vobj.tracetag = alim[i].tracetag;

        _ = arcan_vint_attachobject(did);
        _ = c.arcan_ffunc_lookup(@intCast(vobj.feed.ffunc)).?(
            c.FFUNC_ADOPT, null, 0, 0, 0, 0, vobj.feed.state, vobj.cellid,
        );
        saved.* += 1;
        if (adopt) |afn| afn(did, tag);
    }

    c.arcan_audio_purge(audbuf, s_ofs);
    c.arcan_event_purge();
}

export fn arcan_video_extpopcontext(dst: *arcan_vobj_id) c_uint {
    var dstbuf: [*c]av_pixel = undefined;
    var dsz: usize = undefined;

    flagDirty(null);
    _ = arcan_vint_refresh(0.0, &dsz);
    const ss = arcan_video_screenshot(@ptrCast(&dstbuf), &dsz) == ARCAN_OK;
    const rv = arcan_video_popcontext();

    if (ss) {
        const mode = c.platform_video_dimensions();
        const w: usize = @intCast(mode.width);
        const h: usize = @intCast(mode.height);
        const cons: img_cons = .{ .w = @intCast(w), .h = @intCast(h), .bpp = @sizeOf(av_pixel) };
        dst.* = arcan_video_rawobject(dstbuf, cons, @floatFromInt(w), @floatFromInt(h), 1);
        if (dst.* == ARCAN_EID) {
            c.arcan_mem_free(@ptrCast(dstbuf));
        } else {
            const vobj = arcan_video_getobject(dst.*).?;
            vobj.txcos = @ptrCast(@alignCast(c.arcan_alloc_mem(
                @sizeOf(f32) * 8, c.ARCAN_MEM_VSTRUCT, 0, c.ARCAN_MEMALIGN_SIMD,
            )));
            arcan_vint_mirrormapping(vobj.txcos, 1.0, 1.0);
        }
    }
    return rv;
}

export fn arcan_video_extpushcontext(dst: *arcan_vobj_id) c_int {
    var dstbuf: [*c]av_pixel = undefined;
    var dsz: usize = undefined;

    flagDirty(null);
    _ = arcan_vint_refresh(0.0, &dsz);
    const ss = arcan_video_screenshot(@ptrCast(&dstbuf), &dsz) == ARCAN_OK;
    const rv = arcan_video_pushcontext();

    if (ss) {
        const mode = c.platform_video_dimensions();
        const w: usize = @intCast(mode.width);
        const h: usize = @intCast(mode.height);
        const cons: img_cons = .{ .w = @intCast(w), .h = @intCast(h), .bpp = @sizeOf(av_pixel) };
        dst.* = arcan_video_rawobject(dstbuf, cons, @floatFromInt(w), @floatFromInt(h), 1);
        if (dst.* == ARCAN_EID) {
            c.arcan_mem_free(@ptrCast(dstbuf));
        } else {
            const vobj = arcan_video_getobject(dst.*).?;
            vobj.txcos = @ptrCast(@alignCast(c.arcan_alloc_mem(
                @sizeOf(f32) * 8, c.ARCAN_MEM_VSTRUCT, 0, c.ARCAN_MEMALIGN_SIMD,
            )));
            arcan_vint_mirrormapping(vobj.txcos, 1.0, 1.0);
        }
    }
    return rv;
}

export fn arcan_vint_drawrt(vs: ?*agp_vstore, x: c_int, y: c_int, w: c_int, h: c_int) void {
    var imatr: [16]f32 align(16) = undefined;
    c.identity_matrix(&imatr);
    _ = c.agp_shader_activate(c.agp_default_shader(c.BASIC_2D));
    if (vs == null) return;

    c.agp_activate_vstore(vs);
    _ = c.agp_shader_envv(c.MODELVIEW_MATR, &imatr, @sizeOf(f32) * 16);
    _ = c.agp_shader_envv(c.PROJECTION_MATR, &arcan_video_display.window_projection, @sizeOf(f32) * 16);
    c.agp_blendstate(c.BLEND_NONE);
    c.agp_draw_vobj(0, 0, @floatFromInt(x + w), @floatFromInt(y + h), &arcan_video_display.mirror_txcos, null);
    c.agp_deactivate_vstore();
}

export fn arcan_vint_applyhint(
    src: ?*arcan_vobject,
    hint: c.enum_blitting_hint,
    txin: [*c]f32,
    txout: [*c]f32,
    outx: *usize,
    outy: *usize,
    outw: *usize,
    outh: *usize,
    blackframes: *usize,
) void {
    @memcpy(txout[0..8], txin[0..8]);
    const h: c_uint = @bitCast(hint);

    if (h & c.HINT_ROTATE_CW_90 != 0) {
        txout[0] = txin[2]; txout[1] = txin[3];
        txout[2] = txin[4]; txout[3] = txin[5];
        txout[4] = txin[6]; txout[5] = txin[7];
        txout[6] = txin[0]; txout[7] = txin[1];
    } else if (h & c.HINT_ROTATE_CCW_90 != 0) {
        txout[0] = txin[6]; txout[1] = txin[7];
        txout[2] = txin[0]; txout[3] = txin[1];
        txout[4] = txin[2]; txout[5] = txin[3];
        txout[6] = txin[4]; txout[7] = txin[5];
    } else if (h & c.HINT_ROTATE_180 != 0) {
        txout[0] = txin[4]; txout[1] = txin[5];
        txout[2] = txin[6]; txout[3] = txin[7];
        txout[4] = txin[0]; txout[5] = txin[1];
        txout[6] = txin[2]; txout[7] = txin[3];
    }

    if (h & c.HINT_YFLIP != 0) {
        var flipb: [8]f32 = undefined;
        @memcpy(&flipb, txout[0..8]);
        txout[0] = flipb[6]; txout[1] = flipb[7];
        txout[2] = flipb[4]; txout[3] = flipb[5];
        txout[4] = flipb[2]; txout[5] = flipb[3];
        txout[6] = flipb[0]; txout[7] = flipb[1];
    }

    if (h & c.HINT_CROP != 0) {
        const sw: isize = @intCast(@as(*agp_vstore, @ptrCast(src.?.vstore)).w);
        const sh: isize = @intCast(@as(*agp_vstore, @ptrCast(src.?.vstore)).h);
        const diffw: isize = @as(isize, @intCast(outw.*)) - sw;
        const diffh: isize = @as(isize, @intCast(outh.*)) - sh;
        if (diffw < 0) {
            outx.* = @intCast(-diffw);
        } else {
            outw.* = @intCast(sw);
            outx.* = @intCast(@divTrunc(diffw, 2));
        }
        if (diffh < 0) {
            outy.* = @intCast(-diffh);
        } else {
            outh.* = @intCast(sh);
            outy.* = @intCast(@divTrunc(diffh, 2));
        }
    } else {
        outx.* = 0;
        outy.* = 0;
    }
    blackframes.* = 3;
}

export fn arcan_vint_drawcursor(erase: bool) void {
    if (arcan_video_display.cursor.vstore == null) return;

    var txmatr: [8]f32 = undefined;
    var txcos: [*c]f32 = &arcan_video_display.cursor_txcos;

    if (!erase) {
        arcan_video_display.cursor.ox = arcan_video_display.cursor.x;
        arcan_video_display.cursor.oy = arcan_video_display.cursor.y;
    }

    const x1 = arcan_video_display.cursor.ox;
    const y1 = arcan_video_display.cursor.oy;
    const x2 = x1 + @as(c_int, @intCast(arcan_video_display.cursor.w));
    const y2 = y1 + @as(c_int, @intCast(arcan_video_display.cursor.h));
    const mode = c.platform_video_dimensions();

    if (erase) {
        const s1: f32 = @as(f32, @floatFromInt(x1)) / @as(f32, @floatFromInt(mode.width));
        const s2: f32 = @as(f32, @floatFromInt(x2)) / @as(f32, @floatFromInt(mode.width));
        const t1: f32 = 1.0 - (@as(f32, @floatFromInt(y1)) / @as(f32, @floatFromInt(mode.height)));
        const t2: f32 = 1.0 - (@as(f32, @floatFromInt(y2)) / @as(f32, @floatFromInt(mode.height)));
        txmatr[0] = s1; txmatr[1] = t1;
        txmatr[2] = s2; txmatr[3] = t1;
        txmatr[4] = s2; txmatr[5] = t2;
        txmatr[6] = s1; txmatr[7] = t2;
        txcos = &txmatr;

        c.agp_blendstate(c.BLEND_NONE);
        c.agp_activate_vstore(current_context.world.vstore);
    } else {
        c.agp_blendstate(c.BLEND_FORCE);
        c.agp_activate_vstore(arcan_video_display.cursor.vstore);
    }

    var opa: f32 = 1.0;
    _ = c.agp_shader_activate(c.agp_default_shader(c.BASIC_2D));
    _ = c.agp_shader_envv(c.OBJ_OPACITY, &opa, @sizeOf(f32));
    c.agp_draw_vobj(@floatFromInt(x1), @floatFromInt(y1), @floatFromInt(x2), @floatFromInt(y2), txcos, null);
    c.agp_deactivate_vstore();
}

export fn arcan_vint_dropshape(vobj: ?*arcan_vobject) arcan_errc {
    if (vobj == null) return ARCAN_OK;
    if (vobj.?.shape == null) return ARCAN_OK;
    c.agp_drop_mesh(vobj.?.shape);
    return ARCAN_OK;
}

export fn arcan_video_resampleobject(
    vid: arcan_vobj_id,
    did: arcan_vobj_id,
    neww: usize,
    newh: usize,
    shid: agp_shader_id,
    nocopy: bool,
) arcan_errc {
    const vobj = arcan_video_getobject(vid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (neww == 0 or newh == 0) return c.ARCAN_ERRC_OUT_OF_SPACE;
    if (@as(*agp_vstore, @ptrCast(vobj.vstore)).txmapped != c.TXSTATE_TEX2D) return c.ARCAN_ERRC_UNACCEPTED_STATE;

    const xfer = arcan_video_nullobject(@floatFromInt(neww), @floatFromInt(newh), 0);
    if (xfer == ARCAN_EID) return c.ARCAN_ERRC_OUT_OF_SPACE;

    _ = arcan_video_shareglstore(vid, xfer);
    _ = arcan_video_setprogram(xfer, shid);
    _ = arcan_video_forceblend(xfer, c.BLEND_FORCE);

    var dst: arcan_vobj_id = undefined;

    if (did != ARCAN_EID) {
        const dvobj = arcan_video_getobject(did) orelse {
            _ = arcan_video_deleteobject(xfer);
            return c.ARCAN_ERRC_OUT_OF_SPACE;
        };
        if (@as(*agp_vstore, @ptrCast(dvobj.vstore)).txmapped != c.TXSTATE_TEX2D) {
            _ = arcan_video_deleteobject(xfer);
            return c.ARCAN_ERRC_UNACCEPTED_STATE;
        }
        const rtgt_id = arcan_video_nullobject(@floatFromInt(neww), @floatFromInt(newh), 0);
        if (rtgt_id == ARCAN_EID) {
            _ = arcan_video_deleteobject(xfer);
            return c.ARCAN_ERRC_OUT_OF_SPACE;
        }
        if (@as(*agp_vstore, @ptrCast(dvobj.vstore)).w != @as(c_uint, @intCast(neww)) or @as(*agp_vstore, @ptrCast(dvobj.vstore)).h != @as(c_uint, @intCast(newh))) {
            c.agp_resize_vstore(dvobj.vstore, @intCast(neww), @intCast(newh));
        }
        _ = arcan_video_shareglstore(did, rtgt_id);
        dst = rtgt_id;
    } else {
        const new_sz = neww * newh * @sizeOf(av_pixel);
        const raw_ptr = c.arcan_alloc_mem(
            new_sz, c.ARCAN_MEM_VBUFFER, c.ARCAN_MEM_NONFATAL, c.ARCAN_MEMALIGN_PAGE,
        );
        if (raw_ptr == null) {
            _ = arcan_video_deleteobject(xfer);
            return c.ARCAN_ERRC_OUT_OF_SPACE;
        }
        const dstbuf: [*c]av_pixel = @ptrCast(@alignCast(raw_ptr));
        const cons: img_cons = .{ .w = @intCast(neww), .h = @intCast(newh), .bpp = @sizeOf(av_pixel) };
        dst = arcan_video_rawobject(dstbuf, cons, @floatFromInt(neww), @floatFromInt(newh), 1);
        if (dst == ARCAN_EID) {
            c.arcan_mem_free(@ptrCast(dstbuf));
            _ = arcan_video_deleteobject(xfer);
            return c.ARCAN_ERRC_OUT_OF_SPACE;
        }
    }

    const rts = arcan_video_setuprendertarget(dst, 0, -1, false, c.RENDERTARGET_COLOR | c.RENDERTARGET_RETAIN_ALPHA);
    if (rts != ARCAN_OK) {
        _ = arcan_video_deleteobject(dst);
        _ = arcan_video_deleteobject(xfer);
        return rts;
    }

    _ = arcan_video_attachtorendertarget(dst, xfer, true);
    const dst_rtgt = arcan_vint_findrt(arcan_video_getobject(dst).?);
    if (dst_rtgt) |rt| c.agp_rendertarget_clearcolor(rt.art, 0.0, 0.0, 0.0, 0.0);
    _ = arcan_video_objectopacity(xfer, 1.0, 0);
    _ = arcan_video_forceupdate(dst, true);

    if (did == ARCAN_EID) {
        vobj.origw = @intCast(neww);
        vobj.origh = @intCast(newh);
        _ = arcan_video_shareglstore(dst, vid);
        _ = arcan_video_objectscale(vid, 1.0, 1.0, 1.0, 0);
    }
    _ = arcan_video_deleteobject(dst);

    if (!nocopy) {
        c.agp_readback_synchronous(vobj.vstore);
    }
    return ARCAN_OK;
}

export fn arcan_video_mipmapset(vid: arcan_vobj_id, enable: bool) arcan_errc {
    const vobj = arcan_video_getobject(vid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const vs: *agp_vstore = @ptrCast(vobj.vstore);
    if (vs.txmapped != c.TXSTATE_TEX2D or vs.vinf.text.raw == null)
        return c.ARCAN_ERRC_UNACCEPTED_STATE;

    const newbuf = c.arcan_alloc_fillmem(
        vs.vinf.text.raw,
        vs.vinf.text.s_raw,
        c.ARCAN_MEM_VBUFFER,
        c.ARCAN_MEM_NONFATAL,
        c.ARCAN_MEMALIGN_PAGE,
    );
    if (newbuf == null) return c.ARCAN_ERRC_OUT_OF_SPACE;

    arcan_vint_drop_vstore(vs);
    if (enable)
        vs.filtermode |= @intCast(c.ARCAN_VFILTER_MIPMAP)
    else
        vs.filtermode &= @truncate(~@as(c_uint, c.ARCAN_VFILTER_MIPMAP));

    vs.vinf.text.raw = @ptrCast(@alignCast(newbuf));
    c.agp_update_vstore(vobj.vstore, true);
    return ARCAN_OK;
}

export fn arcan_video_forceread(sid: arcan_vobj_id, local: bool, dptr: *[*c]av_pixel, dsize: *usize) arcan_errc {
    const vobj = arcan_video_getobject(sid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (vobj.vstore == null) return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const dstore: *agp_vstore = @ptrCast(vobj.vstore);
    if (dstore.txmapped != c.TXSTATE_TEX2D) return c.ARCAN_ERRC_UNACCEPTED_STATE;

    dsize.* = @sizeOf(av_pixel) * @as(usize, dstore.w) * @as(usize, dstore.h);
    dptr.* = @ptrCast(@alignCast(c.arcan_alloc_mem(
        dsize.*, c.ARCAN_MEM_VBUFFER,
        c.ARCAN_MEM_TEMPORARY | c.ARCAN_MEM_NONFATAL, c.ARCAN_MEMALIGN_PAGE,
    )));

    if (local and dstore.vinf.text.raw != null and dstore.vinf.text.s_raw > 0) {
        @memcpy(@as([*]u8, @ptrCast(dptr.*))[0..dsize.*], @as([*]const u8, @ptrCast(dstore.vinf.text.raw))[0..dsize.*]);
    } else {
        const temp = dstore.vinf.text.raw;
        dstore.vinf.text.raw = @ptrCast(@alignCast(dptr.*));
        c.agp_readback_synchronous(dstore);
        dstore.vinf.text.raw = temp;
    }
    return ARCAN_OK;
}

export fn arcan_video_disable_worldid() void {
    if (current_context.stdoutp.art) |art| {
        c.agp_drop_rendertarget(art);
        current_context.stdoutp.art = null;
    }
    arcan_video_display.no_stdout = true;
}

export fn arcan_video_forceupdate(vid: arcan_vobj_id, forcedirty: bool) arcan_errc {
    const vobj = arcan_video_getobject(vid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const tgt = arcan_vint_findrt(vobj) orelse return c.ARCAN_ERRC_UNACCEPTED_STATE;

    const id = arcan_video_display.ignore_dirty;
    if (forcedirty) {
        flagDirty(vobj);
        arcan_video_display.ignore_dirty = 1;
    } else {
        arcan_video_display.ignore_dirty = 0;
    }

    _ = process_rendertarget(tgt, arcan_video_display.c_lerp, false);
    tgt.dirtyc = 0;
    arcan_video_display.ignore_dirty = id;
    _current_rendertarget = null;
    c.agp_activate_rendertarget(null);

    if (tgt.readback != 0) {
        process_readback(tgt, arcan_video_display.c_lerp);
        arcan_vint_pollreadback(tgt);
    }
    return ARCAN_OK;
}

export fn arcan_video_screenshot(dptr: *[*c]av_pixel, dsize: *usize) arcan_errc {
    const mode = c.platform_video_dimensions();
    dsize.* = @as(usize, @intCast(mode.width)) * @as(usize, @intCast(mode.height)) * @sizeOf(av_pixel);

    dptr.* = @ptrCast(@alignCast(c.arcan_alloc_mem(
        dsize.*, c.ARCAN_MEM_VBUFFER,
        c.ARCAN_MEM_TEMPORARY | c.ARCAN_MEM_NONFATAL, c.ARCAN_MEMALIGN_PAGE,
    )));
    if (dptr.* == null) {
        dsize.* = 0;
        return c.ARCAN_ERRC_OUT_OF_SPACE;
    }
    c.agp_save_output(@intCast(mode.width), @intCast(mode.height), dptr.*, dsize.*);
    return ARCAN_OK;
}

export fn arcan_vint_pollreadback(tgt: *rendertarget) void {
    if (!rtFlTest(tgt, c.TGTFL_READING)) return;

    if (tgt.color == null) return;
    const vobj: *arcan_vobject = @ptrCast(tgt.color);
    if (vobj.feed.ffunc != 0) {
        const ffunc = c.arcan_ffunc_lookup(@intCast(vobj.feed.ffunc));
        if (ffunc) |ff| {
            if (ff(c.FFUNC_POLL, null, 0, 0, 0, 0, vobj.feed.state, vobj.cellid) == c.FRV_GOTFRAME)
                return;
        }
    }

    const rbb = c.agp_poll_readback(vobj.vstore);
    if (rbb.ptr == null) return;

    if (vobj.feed.ffunc == 0) {
        tgt.readback = 0;
    } else {
        _ = c.arcan_ffunc_lookup(@intCast(vobj.feed.ffunc)).?(
            c.FFUNC_READBACK, rbb.ptr,
            @intCast(@as(usize, @intCast(rbb.w)) * @as(usize, @intCast(rbb.h)) * @sizeOf(av_pixel)),
            @intCast(rbb.w), @intCast(rbb.h), 0, vobj.feed.state, vobj.cellid,
        );
    }
    rbb.release.?(rbb.tag);
    rtFlClear(tgt, c.TGTFL_READING);
}

fn steptgt(fract: f32, tgt: *rendertarget) usize {
    const dst_obj = tgt.color;
    if (dst_obj != null) {
        const dst: *arcan_vobject = @ptrCast(dst_obj);
        if (dst.current.opa < EPSILON and @as(*agp_vstore, @ptrCast(dst.vstore)).refcount == 1 and
            dst.feed.state.tag == c.ARCAN_TAG_FRAMESERV)
        {
            const ff = c.arcan_ffunc_lookup(@as(u8, @intCast(dst.feed.ffunc))) orelse return 0;
            if (ff(c.FFUNC_POLL, null, 0, 0, 0, 0, dst.feed.state, dst.cellid) == c.FRV_GOTFRAME)
                return 1;
        }
    }

    var transfc: usize = 0;
    if (tgt.refresh < 0 and process_counter(tgt, &tgt.refreshcnt, tgt.refresh, fract)) {
        transfc += process_rendertarget(tgt, fract, false);
        tgt.dirtyc = 0;
        process_readback(tgt, fract);
    }
    return transfc;
}

export fn arcan_vint_refresh(fract: f32, ndirty: *usize) c_uint {
    const pre = c.arcan_timemillis();
    var transfc: usize = 0;
    arcan_video_display.c_lerp = fract;
    c.arcan_random(@ptrCast(&arcan_video_display.cookie), 8);

    if (arcan_video_display.ignore_dirty > 0) {
        transfc += 1;
        arcan_video_display.ignore_dirty -= 1;
    }

    var ind: usize = 0;
    while (ind < @as(usize, @intCast(current_context.n_rtargets))) : (ind += 1) {
        const tgt = &current_context.rtargets[ind];
        transfc += steptgt(fract, tgt);
    }

    _current_rendertarget = null;
    c.agp_activate_rendertarget(null);

    transfc += steptgt(fract, &current_context.stdoutp);
    ndirty.* = transfc + @as(usize, @intCast(arcan_video_display.dirty));
    arcan_video_display.dirty = 0;

    if (ndirty.* > 0 and arcan_video_display.ignore_dirty == 0) {
        arcan_video_display.ignore_dirty = c.platform_video_decay();
    }

    const post = c.arcan_timemillis();
    return @intCast(post - pre);
}

export fn arcan_video_screencoords(id: arcan_vobj_id, res: [*c]c.vector) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (vobj.feed.state.tag == c.ARCAN_TAG_3DOBJ) return c.ARCAN_ERRC_UNACCEPTED_STATE;

    var prop: surface_properties = undefined;
    if (vobj.valid_cache) {
        prop = vobj.prop_cache;
    } else {
        prop = toCSP(empty_surface());
        arcan_resolve_vidprop(vobj, arcan_video_display.c_lerp, &prop);
    }

    const w: f32 = @as(f32, @floatFromInt(vobj.origw)) * sp(&prop).scale.x;
    const h: f32 = @as(f32, @floatFromInt(vobj.origh)) * sp(&prop).scale.y;

    res[0].unnamed_0.unnamed_0.x = sp(&prop).position.x;
    res[0].unnamed_0.unnamed_0.y = sp(&prop).position.y;
    res[1].unnamed_0.unnamed_0.x = res[0].unnamed_0.unnamed_0.x + w;
    res[1].unnamed_0.unnamed_0.y = res[0].unnamed_0.unnamed_0.y;
    res[2].unnamed_0.unnamed_0.x = res[1].unnamed_0.unnamed_0.x;
    res[2].unnamed_0.unnamed_0.y = res[1].unnamed_0.unnamed_0.y + h;
    res[3].unnamed_0.unnamed_0.x = res[0].unnamed_0.unnamed_0.x;
    res[3].unnamed_0.unnamed_0.y = res[2].unnamed_0.unnamed_0.y;

    if (@abs(sp(&prop).rotation.roll) > EPSILON) {
        const ang: f32 = @floatCast(c.DEG2RAD(sp(&prop).rotation.roll));
        const sinv = @sin(ang);
        const cosv = @cos(ang);
        const cpx = res[0].unnamed_0.unnamed_0.x + 0.5 * w;
        const cpy = res[0].unnamed_0.unnamed_0.y + 0.5 * h;

        var i: usize = 0;
        while (i < 4) : (i += 1) {
            const rx = cosv * (res[i].unnamed_0.unnamed_0.x - cpx) - sinv * (res[i].unnamed_0.unnamed_0.y - cpy) + cpx;
            const ry = sinv * (res[i].unnamed_0.unnamed_0.x - cpx) + cosv * (res[i].unnamed_0.unnamed_0.y - cpy) + cpy;
            res[i].unnamed_0.unnamed_0.x = rx;
            res[i].unnamed_0.unnamed_0.y = ry;
        }
    }
    return ARCAN_OK;
}

fn isign(p1_x: c_int, p1_y: c_int, p2_x: c_int, p2_y: c_int, p3_x: c_int, p3_y: c_int) c_int {
    return (p1_x - p3_x) * (p2_y - p3_y) - (p2_x - p3_x) * (p1_y - p3_y);
}

fn itri(x: c_int, y: c_int, t: [6]c_int) bool {
    const b1 = isign(x, y, t[0], t[1], t[2], t[3]) < 0;
    const b2 = isign(x, y, t[2], t[3], t[4], t[5]) < 0;
    const b3 = isign(x, y, t[4], t[5], t[0], t[1]) < 0;
    return (b1 == b2) and (b2 == b3);
}

export fn arcan_video_hittest(id: arcan_vobj_id, x: c_int, y: c_int) bool {
    var projv: [4]c.vector = undefined;
    const vobj = arcan_video_getobject(id);

    if (arcan_video_screencoords(id, &projv) != ARCAN_OK) {
        if (vobj != null and vobj.?.feed.state.tag == c.ARCAN_TAG_3DOBJ) {
            return c.arcan_3d_obj_bb_intersect(current_context.stdoutp.camtag, id, x, y);
        }
        return false;
    }

    if (vobj.?.rotate_state) {
        const t1 = [6]c_int{
            @intFromFloat(projv[0].unnamed_0.unnamed_0.x), @intFromFloat(projv[0].unnamed_0.unnamed_0.y),
            @intFromFloat(projv[1].unnamed_0.unnamed_0.x), @intFromFloat(projv[1].unnamed_0.unnamed_0.y),
            @intFromFloat(projv[2].unnamed_0.unnamed_0.x), @intFromFloat(projv[2].unnamed_0.unnamed_0.y),
        };
        const t2 = [6]c_int{
            @intFromFloat(projv[2].unnamed_0.unnamed_0.x), @intFromFloat(projv[2].unnamed_0.unnamed_0.y),
            @intFromFloat(projv[3].unnamed_0.unnamed_0.x), @intFromFloat(projv[3].unnamed_0.unnamed_0.y),
            @intFromFloat(projv[0].unnamed_0.unnamed_0.x), @intFromFloat(projv[0].unnamed_0.unnamed_0.y),
        };
        return itri(x, y, t1) or itri(x, y, t2);
    } else {
        return (x >= @as(c_int, @intFromFloat(projv[0].unnamed_0.unnamed_0.x)) and
            y >= @as(c_int, @intFromFloat(projv[0].unnamed_0.unnamed_0.y)) and
            x <= @as(c_int, @intFromFloat(projv[2].unnamed_0.unnamed_0.x)) and
            y <= @as(c_int, @intFromFloat(projv[2].unnamed_0.unnamed_0.y)));
    }
}

export fn arcan_video_sliceobject(sid: arcan_vobj_id, slice_type: c.arcan_slicetype, base: usize, n_slices: usize) arcan_errc {
    const src = arcan_video_getobject(sid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    const txstate: c_uint = if (slice_type == c.ARCAN_CUBEMAP) c.TXSTATE_CUBE else c.TXSTATE_TEX3D;
    return if (c.agp_slice_vstore(src.vstore, n_slices, base, txstate)) ARCAN_OK else c.ARCAN_ERRC_UNACCEPTED_STATE;
}

export fn arcan_video_updateslices(sid: arcan_vobj_id, n_slices: usize, slices: [*c]arcan_vobj_id) arcan_errc {
    const src = arcan_video_getobject(sid) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    if (n_slices > 4096) return c.ARCAN_ERRC_NO_SUCH_OBJECT;

    var vstores_buf: [4096]?*agp_vstore = undefined;
    var i: usize = 0;
    while (i < n_slices) : (i += 1) {
        const slot = arcan_video_getobject(slices[i]);
        vstores_buf[i] = if (slot) |s| s.vstore else null;
    }

    return if (c.agp_slice_synch(src.vstore, n_slices, &vstores_buf))
        ARCAN_OK
    else
        c.ARCAN_ERRC_UNACCEPTED_STATE;
}

fn obj_visible(vobj_in: *arcan_vobject) bool {
    var vobj = vobj_in;
    var visible = vobj.current.opa > EPSILON;
    while (visible and vobj.parent != null and (@as(c_uint, @bitCast(vobj.mask)) & c.MASK_OPACITY) > 0) {
        visible = vobj.current.opa > EPSILON;
        vobj = vobj.parent.?;
    }
    return visible;
}

export fn arcan_video_rpick(rt: arcan_vobj_id, dst: [*c]arcan_vobj_id, lim: usize, x: c_int, y: c_int) usize {
    var count: usize = 0;
    const vobj = arcan_video_getobject(rt) orelse return 0;
    const tgt = arcan_vint_findrt(vobj) orelse return 0;
    if (lim == 0 or tgt.first == null) return 0;

    var current_litem: ?*arcan_vobject_litem = tgt.first;
    while (current_litem) |cl| {
        if (cl.next == null) break;
        current_litem = cl.next;
    }

    while (current_litem) |cl| {
        if (count >= lim) break;
        if (@intFromPtr(cl.elem) == 0xfeedface)
        { current_litem = @ptrCast(cl.previous); continue; } // poisoned
        if (cl.elem != null) {
            const elem: *arcan_vobject = @ptrCast(cl.elem);
            if ((@as(c_uint, @bitCast(elem.mask)) & c.MASK_UNPICKABLE) == 0 and
                obj_visible(elem) and arcan_video_hittest(elem.cellid, x, y))
            {
                dst[count] = elem.cellid;
                count += 1;
            }
        }
        current_litem = @ptrCast(cl.previous);
    }
    return count;
}

export fn arcan_video_pick(rt: arcan_vobj_id, dst: [*c]arcan_vobj_id, lim: usize, x: c_int, y: c_int) usize {
    var count: usize = 0;
    const vobj = arcan_video_getobject(rt) orelse return 0;
    const tgt = arcan_vint_findrt(vobj) orelse return 0;
    if (lim == 0 or tgt.first == null) return 0;

    var current_litem: ?*arcan_vobject_litem = @ptrCast(tgt.first);
    while (current_litem) |cl| {
        if (count >= lim) break;
        if (@intFromPtr(cl.elem) == 0xfeedface)
        { current_litem = @ptrCast(cl.next); continue; } // poisoned
        if (cl.elem != null) {
            const elem: *arcan_vobject = @ptrCast(cl.elem);
            if (elem.cellid != 0 and
                (@as(c_uint, @bitCast(elem.mask)) & c.MASK_UNPICKABLE) == 0 and
                obj_visible(elem) and arcan_video_hittest(elem.cellid, x, y))
            {
                dst[count] = elem.cellid;
                count += 1;
            }
        }
        current_litem = @ptrCast(cl.next);
    }
    return count;
}

export fn arcan_video_properties_at(id: arcan_vobj_id, ticks: c_uint) surface_properties {
    if (ticks == 0) return arcan_video_current_properties(id);
    const fullprocess = ticks == @as(c_uint, @bitCast(@as(c_int, -1)));

    var rv = toCSP(empty_surface());
    const vobj = arcan_video_getobject(id) orelse return rv;

    rv = vobj.current;
    if (@as(?*surface_transform, @ptrCast(vobj.transform))) |base_xf| {
        var abs_ticks: c.arcan_tickv = ticks;
        if (!fullprocess) abs_ticks += arcan_video_display.c_ticks;

        // move
        var cur = base_xf;
        if (cur.move.startt != 0) {
            while ((cur.move.endt < abs_ticks or fullprocess) and @as(?*surface_transform, @ptrCast(cur.next)) != null) {
                if (@as(*surface_transform, @ptrCast(cur.next)).move.startt != 0) cur = @ptrCast(cur.next) else break;
            }
            if (cur.move.endt <= abs_ticks) {
                rv.position = cur.move.endp;
            } else if (cur.move.startt == abs_ticks) {
                rv.position = cur.move.startp;
            } else {
                const fract = lerp_fract(@floatFromInt(cur.move.startt), @floatFromInt(cur.move.endt), @floatFromInt(abs_ticks));
                rv.position = lut_interp_3d[cur.move.interp].?(cur.move.startp, cur.move.endp, fract);
            }
        }

        // scale
        cur = base_xf;
        if (cur.scale.startt != 0) {
            while ((cur.scale.endt < abs_ticks or fullprocess) and @as(?*surface_transform, @ptrCast(cur.next)) != null) {
                if (@as(*surface_transform, @ptrCast(cur.next)).scale.startt != 0) cur = @ptrCast(cur.next) else break;
            }
            if (cur.scale.endt <= abs_ticks) {
                rv.scale = cur.scale.endd;
            } else if (cur.scale.startt == abs_ticks) {
                rv.scale = cur.scale.startd;
            } else {
                const fract = lerp_fract(@floatFromInt(cur.scale.startt), @floatFromInt(cur.scale.endt), @floatFromInt(abs_ticks));
                rv.scale = lut_interp_3d[cur.scale.interp].?(cur.scale.startd, cur.scale.endd, fract);
            }
        }

        // blend
        cur = base_xf;
        if (cur.blend.startt != 0) {
            while ((cur.blend.endt < abs_ticks or fullprocess) and @as(?*surface_transform, @ptrCast(cur.next)) != null) {
                if (@as(*surface_transform, @ptrCast(cur.next)).blend.startt != 0) cur = @ptrCast(cur.next) else break;
            }
            if (cur.blend.endt <= abs_ticks) {
                rv.opa = cur.blend.endopa;
            } else if (cur.blend.startt == abs_ticks) {
                rv.opa = cur.blend.startopa;
            } else {
                const fract = lerp_fract(@floatFromInt(cur.blend.startt), @floatFromInt(cur.blend.endt), @floatFromInt(abs_ticks));
                rv.opa = lut_interp_1d[cur.blend.interp].?(cur.blend.startopa, cur.blend.endopa, fract);
            }
        }

        // rotate
        cur = base_xf;
        if (cur.rotate.startt != 0) {
            while ((cur.rotate.endt < abs_ticks or fullprocess) and @as(?*surface_transform, @ptrCast(cur.next)) != null) {
                if (@as(*surface_transform, @ptrCast(cur.next)).rotate.startt != 0) cur = @ptrCast(cur.next) else break;
            }
            if (cur.rotate.endt <= abs_ticks) {
                rv.rotation = cur.rotate.endo;
            } else if (cur.rotate.startt == abs_ticks) {
                rv.rotation = cur.rotate.starto;
            } else {
                const fract = lerp_fract(@floatFromInt(cur.rotate.startt), @floatFromInt(cur.rotate.endt), @floatFromInt(abs_ticks));
                rv.rotation.quaternion = cur.rotate.interp.?(cur.rotate.starto.quaternion, cur.rotate.endo.quaternion, fract);
            }
        }
    }

    sp(&rv).scale.x *= @floatFromInt(vobj.origw);
    sp(&rv).scale.y *= @floatFromInt(vobj.origh);
    return rv;
}

export fn arcan_video_prepare_external(keep_events: bool) bool {
    if (arcan_video_pushcontext() == -1) return false;
    if (!keep_events) c.arcan_event_deinit(c.arcan_event_defaultctx(), false);
    c.platform_video_prepare_external();
    return true;
}

fn invalidate_rendertargets() void {
    var i: usize = 0;
    while (i < @as(usize, @intCast(current_context.n_rtargets))) : (i += 1) {
        const tgt = &current_context.rtargets[i];
        if (tgt.art == null) continue;
        c.arcan_mem_free(@ptrCast(tgt.art));
        tgt.art = null;
        if (tgt.color == null) continue;
        tgt.art = c.agp_setup_rendertarget(@as(*arcan_vobject, @ptrCast(tgt.color)).vstore, tgt.mode);
    }

    var j: isize = @as(isize, @intCast(current_context.n_rtargets)) - 1;
    while (j >= 0) : (j -= 1) {
        const tgt = &current_context.rtargets[@intCast(j)];
        if (tgt.color == null) continue;
        _ = arcan_video_forceupdate(@as(*arcan_vobject, @ptrCast(tgt.color)).cellid, true);
    }
}

export fn arcan_video_contextusage(used: ?*c_uint) c_uint {
    if (used) |u| {
        u.* = 0;
        var i: usize = 1;
        while (i < current_context.vitem_limit -| 1) : (i += 1) {
            if (flTest(@as(*const arcan_vobject, @ptrCast(&current_context.vitems_pool[i])), c.FL_INUSE))
                u.* += 1;
        }
    }
    return @intCast(current_context.vitem_limit -| 1);
}

export fn arcan_video_contextsize(newlim: c_uint) bool {
    if (newlim <= 1 or newlim >= VITEM_CONTEXT_LIMIT) return false;
    if (newlim < arcan_video_display.default_vitemlim) {
        var i: usize = 1;
        while (i < current_context.vitem_limit -| 1) : (i += 1) {
            if (flTest(@as(*const arcan_vobject, @ptrCast(&current_context.vitems_pool[i])), c.FL_INUSE | c.FL_PRSIST))
                return false;
        }
    }
    arcan_video_display.default_vitemlim = newlim;
    return true;
}

export fn arcan_video_restore_external(keep_events: bool) void {
    if (!keep_events) c.arcan_event_init(c.arcan_event_defaultctx());

    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_VIDEO;
    ev.unnamed_0.unnamed_0.unnamed_0.vid.kind = c.EVENT_VIDEO_DISPLAY_RESET;
    _ = c.arcan_event_enqueue(c.arcan_event_defaultctx(), &ev);
    c.platform_video_restore_external();
    c.platform_video_query_displays();
    c.agp_shader_rebuild_all();
    _ = arcan_video_popcontext();
    invalidate_rendertargets();
}

fn flag_ctxfsrv_dms(ctx: ?*c.struct_arcan_video_context) void {
    const context = ctx orelse return;
    var i: usize = 1;
    while (i < context.vitem_limit) : (i += 1) {
        if (!flTest(@as(*const arcan_vobject, @ptrCast(&context.vitems_pool[i])), c.FL_INUSE)) continue;
        const cur: *arcan_vobject = @ptrCast(&context.vitems_pool[i]);
        if (cur.feed.state.tag == c.ARCAN_TAG_FRAMESERV and cur.feed.state.ptr != null) {
            const fsrv: *c.struct_arcan_frameserver = @ptrCast(@alignCast(cur.feed.state.ptr));
            fsrv_helper_set_no_dms_free(fsrv, true);
        }
    }
}

export fn arcan_video_shutdown(release_fsrv: bool) void {
    if (!arcan_video_display.in_video) return;
    arcan_video_display.in_video = false;

    if (!release_fsrv) flag_ctxfsrv_dms(current_context);

    var lastctxc = arcan_video_popcontext();
    if (!release_fsrv) flag_ctxfsrv_dms(current_context);

    while (true) {
        const lastctxa = arcan_video_popcontext();
        if (lastctxc == lastctxa) break;
        lastctxc = lastctxa;
        if (!release_fsrv) flag_ctxfsrv_dms(current_context);
    }

    c.agp_shader_flush();
    deallocate_gl_context(current_context, true, null);
    c.arcan_video_reset_fontcache();
    c.TTF_Quit();
    c.platform_video_shutdown();
}

export fn arcan_video_tracetag(id: arcan_vobj_id, message: [*c]const u8, alt: [*c]const u8) arcan_errc {
    const vobj = arcan_video_getobject(id) orelse return c.ARCAN_ERRC_NO_SUCH_OBJECT;
    c.arcan_mem_free(@ptrCast(vobj.tracetag));
    c.arcan_mem_free(@ptrCast(vobj.alttext));
    vobj.tracetag = if (message != null) c.strdup(message) else null;
    vobj.alttext = if (alt != null) c.strdup(alt) else null;
    return ARCAN_OK;
}

fn update_sourcedescr(ds: *agp_vstore, data: *c.struct_arcan_rstrarg) void {
    if (ds.vinf.text.kind == c.STORAGE_TEXT) {
        c.arcan_mem_free(@ptrCast(ds.vinf.text.unnamed_0.source));
    } else if (ds.vinf.text.kind == c.STORAGE_TEXTARRAY) {
        var work: [*c][*c]u8 = @ptrCast(ds.vinf.text.unnamed_0.source_arr);
        while (work[0] != null) {
            c.arcan_mem_free(@ptrCast(work[0]));
            work += 1;
        }
        c.arcan_mem_free(@ptrCast(ds.vinf.text.unnamed_0.source_arr));
    }

    if (data.multiple) {
        ds.vinf.text.kind = c.STORAGE_TEXTARRAY;
        ds.vinf.text.unnamed_0.source_arr = data.unnamed_0.array;
    } else {
        ds.vinf.text.kind = c.STORAGE_TEXT;
        ds.vinf.text.unnamed_0.source = data.unnamed_0.message;
    }
}

export fn arcan_video_renderstring(
    src: arcan_vobj_id,
    data: c.struct_arcan_rstrarg,
    n_lines: *c_uint,
    lineheights: *?*c.struct_renderline_meta,
    errc: ?*arcan_errc,
) arcan_vobj_id {
    var rv = src;

    if (src == ARCAN_VIDEO_WORLDID) {
        if (errc) |e| e.* = c.ARCAN_ERRC_UNACCEPTED_STATE;
        return ARCAN_EID;
    }

    var maxw: usize = undefined;
    var maxh: usize = undefined;
    var w: usize = undefined;
    var h: usize = undefined;
    var dsz: u32 = undefined;

    const dst_rt: *rendertarget = if (current_context.attachment != null) @ptrCast(current_context.attachment) else &current_context.stdoutp;
    c.arcan_renderfun_outputdensity(dst_rt.hppcm, dst_rt.vppcm);

    if (src == ARCAN_EID) {
        const vobj = arcan_video_newvobject(&rv) orelse {
            if (errc) |e| e.* = c.ARCAN_ERRC_OUT_OF_SPACE;
            return ARCAN_EID;
        };
        const ds: *agp_vstore = @ptrCast(vobj.vstore);
        vobj.feed.state.tag = c.ARCAN_TAG_TEXT;
        vobj.blendmode = c.BLEND_FORCE;

        ds.vinf.text.raw = if (data.multiple)
            @ptrCast(c.arcan_renderfun_renderfmtstr_extended(
                @ptrCast(data.unnamed_0.array),
                src, false, n_lines, lineheights, &w, &h, &dsz, &maxw, &maxh, false,
            ))
        else
            @ptrCast(c.arcan_renderfun_renderfmtstr(
                data.unnamed_0.message,
                src, false, n_lines, lineheights, &w, &h, &dsz, &maxw, &maxh, false,
            ));

        if (ds.vinf.text.raw == null) {
            _ = arcan_video_deleteobject(rv);
            if (errc) |e| e.* = c.ARCAN_ERRC_BAD_ARGUMENT;
            return ARCAN_EID;
        }

        ds.vinf.text.vppcm = dst_rt.vppcm;
        ds.vinf.text.hppcm = dst_rt.hppcm;
        ds.vinf.text.kind = c.STORAGE_TEXT;
        ds.vinf.text.s_raw = dsz;
        ds.w = @intCast(w);
        ds.h = @intCast(h);
        ds.txmapped = c.TXSTATE_TEX2D;
        c.agp_update_vstore(ds, true);
        _ = arcan_vint_attachobject(rv);

        vobj.origw = @intCast(maxw);
        vobj.origh = @intCast(maxh);
        var mut_data = data;
        update_sourcedescr(ds, &mut_data);
    } else {
        const vobj = arcan_video_getobject(src) orelse {
            if (errc) |e| e.* = c.ARCAN_ERRC_NO_SUCH_OBJECT;
            return ARCAN_EID;
        };
        if (vobj.feed.state.tag != c.ARCAN_TAG_TEXT) {
            if (errc) |e| e.* = c.ARCAN_ERRC_UNACCEPTED_STATE;
            return ARCAN_EID;
        }
        const ds: *agp_vstore = @ptrCast(vobj.vstore);
        const new_raw: ?[*]av_pixel = if (data.multiple)
            @ptrCast(c.arcan_renderfun_renderfmtstr_extended(
                @ptrCast(data.unnamed_0.array),
                src, false, n_lines, lineheights, &w, &h, &dsz, &maxw, &maxh, false,
            ))
        else
            @ptrCast(c.arcan_renderfun_renderfmtstr(
                data.unnamed_0.message,
                src, false, n_lines, lineheights, &w, &h, &dsz, &maxw, &maxh, false,
            ));

        if (new_raw) |raw| {
            if (ds.vinf.text.raw != null)
                c.arcan_mem_free(@ptrCast(ds.vinf.text.raw));
            ds.vinf.text.raw = @ptrCast(raw);
            ds.vinf.text.s_raw = dsz;
            ds.w = @intCast(w);
            ds.h = @intCast(h);
            ds.txmapped = c.TXSTATE_TEX2D;
            c.agp_resize_vstore(vobj.vstore, w, h);
            ds.vinf.text.hppcm = dst_rt.hppcm;
            ds.vinf.text.vppcm = dst_rt.vppcm;
        }

        invalidate_cache(vobj);
        _ = arcan_video_objectscale(vobj.cellid, 1.0, 1.0, 1.0, 0);

        vobj.origw = @intCast(maxw);
        vobj.origh = @intCast(maxh);
        var mut_data = data;
        update_sourcedescr(ds, &mut_data);
    }
    return rv;
}


