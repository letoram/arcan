// arcan_boot_compat.zig — Pure Zig replacement for @cImport on freestanding boot target.
// Provides all symbols that arcan_lua.zig accesses via `c.*`.
// On POSIX, arcan_lua.zig uses @cImport instead (this file is not used).

const std = @import("std");
const builtin = @import("builtin");
const is_darwin = builtin.os.tag.isDarwin();
const arcan = @import("arcan"); // arcan_zig_types.zig

// ══════════════════════════════════════════════════════════════════════════════
// Section 1: Re-exports from arcan_zig_types.zig
// ══════════════════════════════════════════════════════════════════════════════

// Types
pub const arcan_vobj_id = arcan.arcan_vobj_id;
pub const arcan_aobj_id = arcan.arcan_aobj_id;
pub const arcan_errc = arcan.arcan_errc;
pub const shmif_pixel = arcan.shmif_pixel;
pub const shmif_asample = arcan.shmif_asample;
pub const av_pixel = arcan.av_pixel;
pub const arcan_tickv = arcan.arcan_tickv;
pub const agp_shader_id = arcan.agp_shader_id;
pub const ffunc_ind = arcan.ffunc_ind;
pub const sem_handle = arcan.sem_handle;
pub const arcan_interp_1d_function = arcan.arcan_interp_1d_function;
// Override interp function types to use boot_compat vector/quat
pub const arcan_interp_3d_function = ?*const fn (vector, vector, f32) callconv(.c) vector;
pub const arcan_interp_4d_function = ?*const fn (quat, quat, f32) callconv(.c) quat;
// Override vector/point/scalefactor to match @cImport's unnamed_0 structure
// This avoids 300+ unnamed_0 access changes in arcan_lua.zig
pub const vector = extern struct {
    unnamed_0: extern union {
        unnamed_0: extern struct { x: f32, y: f32, z: f32 },
        xyz: [3]f32,
    },
    pub fn init(x: f32, y: f32, z: f32) vector {
        return .{ .unnamed_0 = .{ .unnamed_0 = .{ .x = x, .y = y, .z = z } } };
    }
};
pub const quat = extern struct {
    unnamed_0: extern union {
        unnamed_0: extern struct { x: f32, y: f32, z: f32, w: f32 },
        xyzw: [4]f32,
    },
};
pub const point = vector;
pub const scalefactor = vector;
pub const surface_orientation = extern struct {
    yaw: f32 = 0,
    pitch: f32 = 0,
    roll: f32 = 0,
    quaternion: quat = std.mem.zeroes(quat),
};
pub const surface_properties = extern struct {
    position: point = std.mem.zeroes(point),
    scale: scalefactor = std.mem.zeroes(scalefactor),
    opa: f32 = 0,
    rotation: surface_orientation = .{},
};
pub const drm_hdr_meta = extern struct {
    eotf: c_int = 0,
    rx: f32 = 0, ry: f32 = 0, gx: f32 = 0, gy: f32 = 0, bx: f32 = 0, by: f32 = 0,
    wpx: f32 = 0, wpy: f32 = 0,
    master_min: f32 = 0, master_max: f32 = 0,
    cll: f32 = 0, fll: f32 = 0,
};
pub const img_cons = arcan.img_cons;
pub const vfunc_state = arcan.vfunc_state;
pub const arcan_blendfunc = arcan.arcan_blendfunc;
pub const arcan_clipmode = arcan.arcan_clipmode;
pub const arcan_vfilter_mode = arcan.arcan_vfilter_mode;
pub const arcan_vimage_mode = arcan.arcan_vimage_mode;
pub const arcan_imageproc_mode = arcan.arcan_imageproc_mode;
pub const arcan_slicetype = arcan.arcan_slicetype;
pub const arcan_vobj_tags = arcan.arcan_vobj_tags;
pub const arcan_order3d = arcan.arcan_order3d;
pub const enum_parent_anchor = arcan.enum_parent_anchor;
pub const enum_parent_scale = arcan.enum_parent_scale;
pub const enum_rendertarget_mode = arcan.enum_rendertarget_mode;
pub const enum_blitting_hint = arcan.enum_blitting_hint;
pub const enum_tag_transform_methods = arcan.enum_tag_transform_methods;
// Override arcan_ioevent with unnamed_0 for anonymous union wrapping devid/subid
pub const arcan_ioevent = extern struct {
    kind: c_uint = 0,
    devkind: c_uint = 0,
    datatype: c_uint = 0,
    label: [16]u8 = std.mem.zeroes([16]u8),
    flags: u8 = 0,
    _pad_flags: [1]u8 = .{0},
    unnamed_0: extern union {
        unnamed_0: extern struct { devid: u16 = 0, subid: u16 = 0 },
        id: [2]u16,
    } = .{ .id = .{ 0, 0 } },
    dst: u32 = 0,
    pts: u64 = 0,
    input: arcan.arcan_ioevent_data = std.mem.zeroes(arcan.arcan_ioevent_data),
};
// Override arcan_tgtevent with unnamed_0 for message union
pub const tgt_ioev = extern union { uiv: u32, iv: i32, fv: f32, cv: [4]u8 };
pub const arcan_tgtevent = extern struct {
    kind: c_uint = 0,
    ioevs: [8]tgt_ioev = std.mem.zeroes([8]tgt_ioev),
    code: c_int = 0,
    unnamed_0: extern union {
        message: [78]u8,
        bmessage: [78]u8,
        timestamp: u64,
    } = .{ .message = std.mem.zeroes([78]u8) },
};
// Override arcan_extevent to match @cImport unnamed_0 structure
pub const arcan_extevent = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    source: i64 = 0,
    unnamed_0: extern union {
        message: extern struct { data: [78]u8 = std.mem.zeroes([78]u8), multipart: u8 = 0 },
        labelhint: extern struct { label: [16]u8 = std.mem.zeroes([16]u8), initial: u16 = 0, descr: [53]u8 = std.mem.zeroes([53]u8), vsym: [5]u8 = std.mem.zeroes([5]u8), subv: u16 = 0, idatatype: u8 = 0, modifiers: u16 = 0 },
        segreq: extern struct { id: u32 = 0, width: u16 = 0, height: u16 = 0, xofs: i16 = 0, yofs: i16 = 0, dir: u8 = 0, hints: u8 = 0, kind: c_uint = 0 },
        viewport: extern struct { x: i32 = 0, y: i32 = 0, w: u32 = 0, h: u32 = 0, parent: u32 = 0, border: [4]u8 = std.mem.zeroes([4]u8), edge: u8 = 0, order: i8 = 0, embedded: u8 = 0, invisible: u8 = 0, focus: u8 = 0, anchor_edge: u8 = 0, anchor_pos: u8 = 0, ext_id: u32 = 0 },
        clock: extern struct { rate: u32 = 0, dynamic: u8 = 0, once: u8 = 0, id: u32 = 0 },
        registr: extern struct { title: [64]u8 = std.mem.zeroes([64]u8), kind: c_uint = 0, guid: [2]u64 = .{ 0, 0 } },
        bchunk: extern struct { unnamed_0: extern union { size: u64, ns: i64 } = .{ .size = 0 }, input: u8 = 0, hint: u8 = 0, stream: u8 = 0, extensions: [68]u8 = std.mem.zeroes([68]u8), identifier: u32 = 0 },
        stateinf: extern struct { size: u32 = 0, @"type": u32 = 0 },
        streamstat: extern struct { timestr: [9]u8 = std.mem.zeroes([9]u8), timelim: [9]u8 = std.mem.zeroes([9]u8), completion: f32 = 0, streaming: u8 = 0, frameno: u32 = 0, identifier: u32 = 0 },
        framestatus: extern struct { framenumber: u32 = 0, pts: u64 = 0, acquired: u64 = 0, fhint: f32 = 0 },
        content: extern struct { x_pos: f32 = 0, x_sz: f32 = 0, y_pos: f32 = 0, y_sz: f32 = 0, min_w: u32 = 0, min_h: u32 = 0, max_w: u32 = 0, max_h: u32 = 0, cell_w: u8 = 0, cell_h: u8 = 0, width: f32 = 0, height: f32 = 0 },
        coreopt: extern struct { index: u8 = 0, @"type": u8 = 0, data: [77]u8 = std.mem.zeroes([77]u8) },
        privdrop: extern struct { external: u8 = 0, sandboxed: u8 = 0, networked: u8 = 0 },
        inputmask: extern struct { device: u32 = 0, types: u32 = 0 },
        netstate: extern struct { unnamed_0: extern union { name: [66]u8, unnamed_0: extern struct { petname: [16]u8, pubk: [32]u8 } } = .{ .name = std.mem.zeroes([66]u8) }, space: u8 = 0, state: u8 = 0, @"type": u8 = 0, port: u16 = 0, ns: u16 = 0 },
        streaminf: extern struct { streamid: u8 = 0, datakind: u8 = 0, langid: [4]u8 = std.mem.zeroes([4]u8) },
    } = .{ .message = .{} },
    frame_id: u64 = 0,
};
// arcan_sevent (system event)
pub const arcan_sevent = extern struct {
    kind: c_uint = 0,
    errcode: c_int = 0,
    unnamed_0: extern union {
        tagv: extern struct { hitag: u32 = 0, lotag: u32 = 0 },
        mesg: extern struct { dyneval_msg: ?[*:0]u8 = null },
        data: extern struct { fd: c_int = 0, _pad: [4]u8 = .{ 0, 0, 0, 0 }, otag: isize = 0 },
        message: [64]u8,
    } = .{ .message = std.mem.zeroes([64]u8) },
};
// arcan_vevent (video event) — internal engine only
pub const arcan_vevent = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    source: i64 = 0,
    unnamed_0: extern union {
        unnamed_0: extern struct {
            width: i16 = 0,
            height: i16 = 0,
            flags: c_int = 0,
            vppcm: f32 = 0,
            displayid: c_int = 0,
            ledctrl: c_int = 0,
            ledid: c_int = 0,
            cardid: c_int = 0,
        },
        slot: c_int,
    } = .{ .slot = 0 },
    data: isize = 0,
};
// arcan_aevent (audio event) — internal engine only
pub const arcan_aevent = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    source: i32 = 0,
    _pad_source: [4]u8 = .{ 0, 0, 0, 0 },
    unnamed_0: extern union {
        otag: isize,
        data: [*c]usize,
    } = .{ .otag = 0 },
};
// Override arcan_event to match @cImport's 3-level unnamed_0 structure
// ev.unnamed_0.unnamed_0.category and ev.unnamed_0.unnamed_0.unnamed_0.tgt
pub const arcan_event = extern union {
    unnamed_0: extern struct {
        unnamed_0: extern struct {
            unnamed_0: extern union {
                io: arcan_ioevent,
                vid: arcan_vevent,
                aud: arcan_aevent,
                sys: arcan_sevent,
                tgt: arcan_tgtevent,
                ext: arcan_extevent,
                fsrv: arcan_fsrvevent_full,
            },
            category: u8,
        },
    },
    pad: [128]u8,

    pub fn zeroes() arcan_event {
        return .{ .pad = std.mem.zeroes([128]u8) };
    }
};
// Override opaque arcan_shmif_cont — partial struct with fields accessed by engine code
// Layout: addr(8) + vidp(8) + audp(8) + oflow_cookie(2) + abuf*(8) + abuf_cnt(1) +
//         padding(1) + epipe(4) + shmh(4) + shmsize(8) + unused(24) = 76 bytes → w at 80
pub const arcan_shmif_cont = extern struct {
    addr: ?*anyopaque = null, // struct arcan_shmif_page*
    unnamed_0: extern union { vidp: ?*anyopaque, floatp: ?*f32, vidb: [*c]u8 } = .{ .vidp = null },
    unnamed_1: extern union { audp: ?*anyopaque, audb: [*c]u8 } = .{ .audp = null },
    oflow_cookie: i16 = 0,
    abufused: u16 = 0,
    abufpos: u16 = 0,
    abufsize: u16 = 0,
    abufcount: u16 = 0,
    abuf_cnt: u8 = 0,
    _pad0: [3]u8 = .{ 0, 0, 0 },
    epipe: c_int = 0,
    shmh: c_int = 0,
    shmsize: usize = 0,
    unused: [3]usize align(8) = .{ 0, 0, 0 },
    w: usize = 0,
    h: usize = 0,
    stride: usize = 0,
    pitch: usize = 0,
    adata: u32 = 0,
    _pad1: [4]u8 = .{ 0, 0, 0, 0 },
    samplerate: usize = 0,
    hints: u8 = 0,
    _pad2: [7]u8 = std.mem.zeroes([7]u8),
    dirty: arcan_shmif_region = std.mem.zeroes(arcan_shmif_region),
    cookie: u64 = 0,
    user: ?*anyopaque = null,
    priv: ?*anyopaque = null, // struct shmif_hidden*
    privext: ?*anyopaque = null, // struct shmif_ext_hidden*
    segment_token: u32 = 0,
    _pad3: [4]u8 = .{ 0, 0, 0, 0 },
    vbufsize: usize = 0,
};
pub const arcan_shmif_region = arcan.arcan_shmif_region;
// Override arcan_strarr to match @cImport's unnamed_0 structure
pub const arcan_strarr = extern struct {
    count: usize = 0,
    limit: usize = 0,
    unnamed_0: extern union {
        data: [*c][*c]u8,
        cdata: [*c]?*anyopaque,
    } = .{ .data = null },
};
// Override tui_screen_attr with unnamed_0/unnamed_1/unnamed_2 for anonymous unions
pub const tui_screen_attr = extern struct {
    unnamed_0: extern union {
        fc: [3]u8,
        unnamed_0: extern struct { fr: u8 = 0, fg: u8 = 0, fb: u8 = 0 },
    } = .{ .fc = .{ 0, 0, 0 } },
    unnamed_1: extern union {
        bc: [3]u8,
        unnamed_0: extern struct { br: u8 = 0, bg: u8 = 0, bb: u8 = 0 },
    } = .{ .bc = .{ 0, 0, 0 } },
    unnamed_2: extern union {
        aflags: u16,
        aflags_u8: [2]u8,
    } = .{ .aflags = 0 },
    custom_id: u8 = 0,
};
pub const tui_cell = arcan.tui_cell;
pub const tui_constraints = arcan.tui_constraints;
pub const tui_labelent = arcan.tui_labelent;
pub const tui_cbcfg = arcan.tui_cbcfg;
pub const tui_context = arcan.tui_context;
pub const cfg_lookup_fun = arcan.cfg_lookup_fun;
pub const data_source = arcan.data_source;
// Override map_region to match @cImport's unnamed_0 structure
pub const map_region = extern struct {
    unnamed_0: extern struct {
        ptr: [*c]u8 = null,
    } = .{},
    zbyte: u8 = 0,
    _pad0: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
    sz: usize = 0,
    mmap: bool = false,
};
pub const pthread_t = arcan.pthread_t;
// arcan_frameserver_meta (desc) sub-struct — 480 bytes total
pub const arcan_frameserver_meta = extern struct {
    width: u16 = 0, // offset 0
    height: u16 = 0, // offset 2
    _pad0: [4]u8 = std.mem.zeroes([4]u8), // offset 4
    rows: usize = 0, // offset 8
    cols: usize = 0, // offset 16
    bpp: i8 = 0, // offset 24
    _pad1: [3]u8 = std.mem.zeroes([3]u8), // offset 25
    hints: c_int = 0, // offset 28
    pending_hints: c_int = 0, // offset 32
    rz_flag: bool = false, // offset 36
    _pad2: [1]u8 = .{0}, // offset 37
    region: arcan_shmif_region = std.mem.zeroes(arcan_shmif_region), // offset 38, 8 bytes
    region_valid: bool = false, // offset 46
    _pad3: [1]u8 = .{0}, // offset 47 → text starts at 48
    text: extern struct { // offset 48
        group: ?*anyopaque = null, // offset 48 (8 bytes)
        hint: c_int = 0, // offset 56
        szmm: f32 = 0, // offset 60
        cellw: usize = 0, // offset 64
        cellh: usize = 0, // offset 72
    } = .{}, // 32 bytes, offset 48..80
    hint: extern struct { // offset 80
        last: arcan_event = arcan_event.zeroes(), // offset 80, 128 bytes
        width: usize = 0, // offset 208
        height: usize = 0, // offset 216
        ppcm: f32 = 0, // offset 224
        _pad: [4]u8 = std.mem.zeroes([4]u8), // offset 228
    } = .{}, // 152 bytes, offset 80..232
    _gap_hint: [440 - 232]u8 = std.mem.zeroes([440 - 232]u8), // offset 232..440
    callback_framestate: bool = false, // offset 440
    _rest: [480 - 441]u8 = std.mem.zeroes([480 - 441]u8), // offset 441..480
};
// arcan_frameserver struct with fields at known offsets
pub const struct_arcan_frameserver = extern struct {
    desc: arcan_frameserver_meta = .{}, // offset 0, 480 bytes
    _gap1a: [676 - 480]u8 = std.mem.zeroes([676 - 480]u8), // offset 480..676
    queue_mask: c_int = 0, // offset 676
    source: ?[*:0]u8 = null, // offset 680
    dpipe: c_int = 0, // offset 688
    child: pid_t = 0, // offset 692
    max_w: usize = 0, // offset 696
    max_h: usize = 0, // offset 704
    sockmode: c_uint = 0, // offset 712 (mode_t)
    _pad_sockmode: [4]u8 = std.mem.zeroes([4]u8), // offset 716
    sockaddr: ?[*:0]u8 = null, // offset 720
    sockkey: ?[*:0]u8 = null, // offset 728
    metamask: c_uint = 0, // offset 736
    devicemask: c_uint = 0, // offset 740
    datamask: c_uint = 0, // offset 744
    xfer_sat: f32 = 0, // offset 748
    fused: bool = false, // offset 752
    fuse_blown: bool = false, // offset 753
    audio_flush_pending: bool = false, // offset 754
    _pad_fused: [1]u8 = .{0}, // offset 755 → align to flags at 756
    flags: extern struct { // offset 756, 8 bytes
        _bitfield: u32 = 0,
        activated: c_int = 0,
    } = .{}, // 8 bytes
    _gap3a: [800 - 764]u8 = std.mem.zeroes([800 - 764]u8), // offset 764..800
    alocks: ?[*]arcan_aobj_id = null, // offset 800 (pointer, 8 bytes)
    aid: arcan_aobj_id = 0, // offset 808 (i32)
    _pad_aid: [4]u8 = std.mem.zeroes([4]u8), // offset 812
    vid: arcan_vobj_id = 0, // offset 816 (i64)
    parent: extern struct { // offset 824 (16 bytes)
        ptr: ?*anyopaque = null,
        vid: arcan_vobj_id = 0,
    } = .{},
    _gap4: [892 - 840]u8 = std.mem.zeroes([892 - 840]u8), // offset 840..892
    cookie: u32 = 0, // offset 892
    cookie_fail: bool = false, // offset 896
    _pad_cookie: [7]u8 = std.mem.zeroes([7]u8), // pad to 8-byte alignment
    vstream: extern struct { // vstream sub-struct
        dead: bool = false,
        _pad: [255]u8 = std.mem.zeroes([255]u8), // rest of vstream
    } = .{},
    _gap5: [2000 - 896 - 8 - 256]u8 = std.mem.zeroes([2000 - 896 - 8 - 256]u8),
    segid: c_int = 0, // offset 2000
    _pad_segid: [4]u8 = std.mem.zeroes([4]u8), // offset 2004
    guid: [2]u64 = .{ 0, 0 }, // offset 2008
    tag: isize = 0, // offset 2024
    _gap6: [2088 - 2032]u8 = std.mem.zeroes([2088 - 2032]u8), // offset 2032..2088
    rz_known: c_int = 0, // offset 2088
    _tail: [2280 - 2089]u8 = std.mem.zeroes([2280 - 2089]u8), // offset 2089..2280
};
pub const struct_arcan_img_meta = arcan.struct_arcan_img_meta;
// Override arcan_rstrarg with unnamed_0 for payload union
pub const struct_arcan_rstrarg = extern struct {
    multiple: bool = false,
    _pad0: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
    unnamed_0: extern union {
        message: [*c]u8,
        array: [*c][*c]u8,
    } = .{ .message = null },
};
pub const struct_renderline_meta = arcan.struct_renderline_meta;
// Override agp_vstore: full struct with fields arcan_lua.zig accesses
pub const struct_agp_vstore = extern struct {
    refcount: usize = 0, update_ts: u32 = 0, _pad0: [4]u8 = .{ 0, 0, 0, 0 },
    vinf: extern union {
        text: extern struct {
            glid: c_uint = 0, _p0: [4]u8 = .{0} ** 4, glid_proxy: ?*c_uint = null,
            rid: c_uint = 0, wid: c_uint = 0,
            s_raw: u32 = 0, _p1: [4]u8 = .{0} ** 4, raw: ?[*]av_pixel = null,
            s_fmt: u64 = 0, d_fmt: u64 = 0, s_type: c_uint = 0, _p2: [4]u8 = .{0} ** 4,
            vpts: u64 = 0, hppcm: f32 = 0, vppcm: f32 = 0,
            kind: c_uint = 0, _p3: [4]u8 = .{0} ** 4,
            unnamed_0: extern union {
                source: [*c]u8, source_arr: [*c][*c]u8,
                tpack: extern struct { buf_sz: usize = 0, buf: ?[*]u8 = null, group: ?*anyopaque = null, tui: ?*anyopaque = null },
            } = .{ .source = null },
            format: c_int = 0, _p4: [4]u8 = .{0} ** 4, stride: usize = 0, handle: i64 = 0, tag: usize = 0,
        },
        col: extern struct { r: f32 = 0, g: f32 = 0, b: f32 = 0 },
    } = .{ .col = .{} },
    dst_copy: ?*struct_agp_vstore = null,
    w: usize = 0, h: usize = 0,
    bpp: u8 = 0, txmapped: u8 = 0, txu: u8 = 0, txv: u8 = 0,
    scale: u8 = 0, imageproc: u8 = 0, filtermode: u8 = 0,
    _pad_hdr: [1]u8 = .{0},
    hdr: extern struct {
        model: c_int = 0,
        drm: drm_hdr_meta = std.mem.zeroes(drm_hdr_meta),
    } = .{},
};

// Comptime verify agp_vstore field offsets match C (from platform_types.h)
comptime {
    const V = struct_agp_vstore;
    // C: offsetof(dst_copy)=168, offsetof(w)=176, offsetof(h)=184, offsetof(txmapped)=193
    if (@offsetOf(V, "dst_copy") != 168) @compileError("agp_vstore.dst_copy offset mismatch");
    if (@offsetOf(V, "w") != 176) @compileError("agp_vstore.w offset mismatch");
    if (@offsetOf(V, "h") != 184) @compileError("agp_vstore.h offset mismatch");
    if (@offsetOf(V, "txmapped") != 193) @compileError("agp_vstore.txmapped offset mismatch");
    if (@sizeOf(V) != 256) @compileError("agp_vstore size mismatch");
}

// Override: sized blobs so [*c] pointers work
pub const struct_agp_rendertarget = extern struct { _data: [256]u8 = std.mem.zeroes([256]u8) };
pub const struct_agp_mesh_store = extern struct {
    shared_buffer: [*c]u8 = null,
    shared_buffer_sz: usize = 0,
    verts: [*c]f32 = null,
    txcos: [*c]f32 = null,
    txcos2: [*c]f32 = null,
    normals: [*c]f32 = null,
    colors: [*c]f32 = null,
    tangents: [*c]f32 = null,
    bitangents: [*c]f32 = null,
    weights: [*c]f32 = null,
    joints: [*c]u16 = null,
    indices: [*c]c_uint = null,
    vertex_size: usize = 0,
    n_vertices: usize = 0,
    n_indices: usize = 0,
    @"type": c_uint = 0,
    depth_func: c_uint = 0,
    @"opaque": usize = 0,
    dirty: bool = false,
    nodepth: bool = false,
    validated: bool = false,
};
// Override transform structs to use boot_compat's vector/quat/surface_orientation
pub const struct_transf_move = extern struct {
    interp: u8 = 0,
    _pad0: [3]u8 = .{ 0, 0, 0 },
    startt: arcan_tickv = 0,
    endt: arcan_tickv = 0,
    startp: point = std.mem.zeroes(point),
    endp: point = std.mem.zeroes(point),
    tag: isize = 0,
};
pub const struct_transf_scale = extern struct {
    interp: u8 = 0,
    _pad0: [3]u8 = .{ 0, 0, 0 },
    startt: arcan_tickv = 0,
    endt: arcan_tickv = 0,
    startd: scalefactor = std.mem.zeroes(scalefactor),
    endd: scalefactor = std.mem.zeroes(scalefactor),
    tag: isize = 0,
};
pub const struct_transf_blend = extern struct {
    interp: u8 = 0,
    _pad0: [3]u8 = .{ 0, 0, 0 },
    startt: arcan_tickv = 0,
    endt: arcan_tickv = 0,
    startopa: f32 = 0,
    endopa: f32 = 0,
    tag: isize = 0,
};
pub const struct_transf_rotate = extern struct {
    interp: arcan_interp_4d_function = null,
    startt: arcan_tickv = 0,
    endt: arcan_tickv = 0,
    starto: surface_orientation = .{},
    endo: surface_orientation = .{},
    tag: isize = 0,
};
pub const struct_surface_transform = extern struct {
    move: struct_transf_move = .{},
    scale: struct_transf_scale = .{},
    blend: struct_transf_blend = .{},
    rotate: struct_transf_rotate = .{},
    next: ?*struct_surface_transform = null,
};
// Override frameset types to use [*c] pointers for indexing support
pub const struct_frameset_store = extern struct {
    frame: [*c]struct_agp_vstore = null,
    txcos: [8]f32 = std.mem.zeroes([8]f32),
};
pub const struct_vobject_frameset = extern struct {
    frames: [*c]struct_frameset_store = null,
    n_frames: usize = 0,
    index: usize = 0,
    ctr: c_int = 0,
    mctr: c_int = 0,
    mode: c_uint = 0,
};
pub const vobject_frameset = struct_vobject_frameset;
// Override with [*c] pointers for .* dereference compat
pub const struct_arcan_vobject_litem = extern struct {
    elem: [*c]arcan_vobject = @ptrFromInt(0),
    next: [*c]struct_arcan_vobject_litem = @ptrFromInt(0),
    previous: [*c]struct_arcan_vobject_litem = @ptrFromInt(0),
};
// Override rendertarget: [*c] pointers for .* dereference compat
pub const struct_rendertarget = extern struct {
    base: [16]f32 align(16) = std.mem.zeroes([16]f32),
    projection: [16]f32 align(16) = std.mem.zeroes([16]f32),
    shid: agp_shader_id = 0, _p0: [4]u8 = .{0} ** 4,
    frame_cookie: u64 = 0, msc: u64 = 0,
    force_shid: bool = false, inv_y: bool = false, _p1: [2]u8 = .{0} ** 2,
    id: c_int = 0,
    color: [*c]arcan_vobject = @ptrFromInt(0),
    first: [*c]struct_arcan_vobject_litem = @ptrFromInt(0),
    link: [*c]struct_rendertarget = @ptrFromInt(0),
    art: [*c]struct_agp_rendertarget = @ptrFromInt(0),
    mode: c_uint = 0, flags: c_uint = 0, order3d: c_uint = 0, _p2: [4]u8 = .{0} ** 4,
    readback: c_int = 0, readcnt: c_int = 0,
    hwreadback: bool = false, _p3: [3]u8 = .{0} ** 3,
    refresh: c_int = 0, refreshcnt: c_int = 0,
    transfc: usize = 0, uploadc: usize = 0, dirtyc: usize = 0,
    hppcm: f32 = 0, vppcm: f32 = 0,
    camtag: arcan_vobj_id = 0, min_order: usize = 0, max_order: usize = 0,
};
// Override opaque types from arcan module with minimal structs (for [*c] compat)
pub const struct_arcan_video_display = extern struct {
    suspended: bool = false,
    fullscreen: bool = false,
    conservative: bool = false,
    in_video: bool = false,
    no_stdout: bool = false,
    _pad0: [3]u8 = std.mem.zeroes([3]u8),
    cookie: u64 = 0,
    dirty: c_int = 0,
    _pad1: [4]u8 = std.mem.zeroes([4]u8),
    ignore_dirty: usize = 0,
    order3d: arcan_order3d = 0,
    _pad2: [4]u8 = std.mem.zeroes([4]u8),
    cursor: extern struct {
        vstore: [*c]struct_agp_vstore = null,
        x: c_int = 0,
        ox: c_int = 0,
        y: c_int = 0,
        oy: c_int = 0,
        w: usize = 0,
        h: usize = 0,
        active: bool = false,
    } = .{},
    default_vitemlim: c_uint = 0,
    _pad3: [4]u8 = std.mem.zeroes([4]u8),
    default_projection: [16]f32 = std.mem.zeroes([16]f32),
    window_projection: [16]f32 = std.mem.zeroes([16]f32),
    default_txcos: [8]f32 = std.mem.zeroes([8]f32),
    cursor_txcos: [8]f32 = std.mem.zeroes([8]f32),
    mirror_txcos: [8]f32 = std.mem.zeroes([8]f32),
    scalemode: arcan_vimage_mode = 0,
    imageproc: arcan_imageproc_mode = 0,
    filtermode: arcan_vfilter_mode = 0,
    blendmode: arcan_blendfunc = 0,
    deftxs: c_uint = 0,
    deftxt: c_uint = 0,
    mipmap: bool = false,
    _pad4: [3]u8 = std.mem.zeroes([3]u8),
    c_ticks: arcan_tickv = 0,
    c_lerp: f32 = 0,
    msasamples: u8 = 0,
    _pad5: [7]u8 = std.mem.zeroes([7]u8),
    txdump: ?[*:0]u8 = null,
};
pub const struct_arcan_video_context = extern struct {
    vitem_ofs: c_uint = 0,
    vitem_limit: c_uint = 0,
    nalive: c_long = 0,
    last_tickstamp: arcan_tickv = 0,
    _pad0: [4]u8 = std.mem.zeroes([4]u8),
    world: arcan_vobject = .{},
    vitems_pool: [*c]arcan_vobject = null,
    rtargets: [RENDERTARGET_LIMIT]struct_rendertarget = std.mem.zeroes([RENDERTARGET_LIMIT]struct_rendertarget),
    attachment: ?*struct_rendertarget = null,
    n_rtargets: isize = 0,
    stdoutp: struct_rendertarget = std.mem.zeroes(struct_rendertarget),
};
pub const struct_arcan_evctx = extern struct {
    front: ?*arcan_event = null,
    back: ?*arcan_event = null,
    eventbuf_sz: usize = 0,
    eventbuf: [*c]arcan_event = null,
    _data: [224]u8 = std.mem.zeroes([224]u8),
};
pub const struct_monitor_mode = arcan.struct_monitor_mode;
pub const struct_asynch_readback_meta = arcan.struct_asynch_readback_meta;

// Struct aliases (C-style names)
pub const arcan_vobject_litem = struct_arcan_vobject_litem;
pub const struct_arcan_shmif_cont = arcan_shmif_cont;
pub const struct_arg_arr = arcan_strarr;
// Shmif types for freestanding
pub const struct_shmif_resize_ext = extern struct {
    abuf_sz: isize = 0,
    abuf_cnt: i8 = 0,
    _pad0: [3]u8 = .{ 0, 0, 0 },
    samplerate: i32 = 0,
    adata: u32 = 0,
    vbuf_cnt: i8 = 0,
    _pad1: [3]u8 = .{ 0, 0, 0 },
    meta: c_int = 0,
    rows: usize = 0,
    cols: usize = 0,
    _pad2: [12]u8 = std.mem.zeroes([12]u8),
};
pub const shmif_trigger_hook_fptr = ?*const fn ([*c]arcan_shmif_cont) callconv(.c) c_uint;
pub const shmif_reset_hook_fptr = ?*const fn (c_int, ?*anyopaque) callconv(.c) void;
pub const SHMIF_INPUT = @as(c_uint, 1);
pub const SHMIF_OUTPUT = @as(c_uint, 2);
pub const SHMIF_SIGVID = @as(c_uint, 1);
pub const SHMIF_SIGAUD = @as(c_uint, 2);
// Shmif constants for freestanding
pub const pthread_mutex_t = extern struct { _data: [48]u8 = std.mem.zeroes([48]u8) };
pub const struct_arcan_shmif_initial = extern struct { _data: [256]u8 = std.mem.zeroes([256]u8) };
pub const struct_shmif_open_ext = extern struct {
    @"type": c_uint = 0,
    _pad0: [4]u8 = .{ 0, 0, 0, 0 },
    title: [*c]const u8 = null,
    ident: [*c]const u8 = null,
    guid: [2]u64 = .{ 0, 0 },
};
pub const SYNC_EVENT = @as(c_uint, 0);
pub const ARCAN_SHMPAGE_START_SZ: usize = 2 * 1024 * 1024;
pub const ASHMIF_VERSION_MAJOR = @as(c_uint, 0);
pub const PP_SHMPAGE_MAXW: usize = 8192;
pub const PP_SHMPAGE_MAXH: usize = 8192;
pub const SHMIF_ACQUIRE_FATALFAIL: c_uint = @bitCast(@as(c_int, -1));
pub const SHMIF_ACCESSIBILITY = @as(c_uint, 0x40);
pub const SHMIF_RHINT_SUBREGION = @as(u8, 4);
pub const SUPPORT_EVENT_EXIT = @as(c_uint, 1);
pub const SYNC_AUDIO = @as(c_uint, 2);
pub const ASHMIF_VERSION_MINOR = @as(c_uint, 18);
pub const struct_shmif_connection = extern struct {
    @"error": ?[*:0]const u8 = null,
    flags: c_uint = 0,
    _pad0: [4]u8 = .{ 0, 0, 0, 0 },
    keyfile: ?[*:0]const u8 = null,
    socket: c_int = -1,
    _pad1: [4]u8 = .{ 0, 0, 0, 0 },
    args: ?[*:0]const u8 = null,
    alternate_cp: ?[*:0]const u8 = null,
    networked: bool = false,
    _pad: [15]u8 = std.mem.zeroes([15]u8),
};
pub const AL_SOURCE_STATE = @as(c_int, 0x1010);
pub const AL_BUFFERS_PROCESSED = @as(c_int, 0x1016);
pub inline fn alSourceUnqueueBuffers(_: c_uint, _: c_int, _: [*c]c_uint) void {}
pub inline fn alSourceQueueBuffers(_: c_uint, _: c_int, _: [*c]c_uint) void {}
pub inline fn alGetError() c_int { return 0; }
pub const AL_NO_ERROR = @as(c_int, 0);
pub const ARCAN_ERRC_NOTREADY = @as(c_int, -10);
pub const SHMIF_NOREGISTER = @as(c_uint, 0x80);
pub const SHMIF_RESET_NOCHG = @as(c_int, 0);
pub const AL_PLAYING = @as(c_int, 0x1012);
pub const struct_arcan_event = arcan_event;
pub const ARCAN_SHMIF_SAMPLERATE = @as(usize, 48000);
pub inline fn alSourcePlay(_: c_uint) void {}
pub const SHMIF_DISABLE_GUARD = @as(c_uint, 0x100);
pub const ARCAN_SHMIF_VBUFC_LIM = @as(usize, 3);
pub const struct_watchdog_config = extern struct { parent_pid: c_int = 0, parent_fd: c_int = -1, exitf: ?*const fn (c_int) callconv(.c) void = null, relval: c_int = 0 };
pub const SHMIF_RESET_REMAP = @as(c_int, 2);
pub const SHMIF_SOCKET_PINGEVENT = @as(c_uint, 0x200);
pub const SHMIF_NOACTIVATE = @as(c_uint, 0x400);
pub const SHMIF_NOACTIVATE_RESIZE = @as(c_uint, 0x800);
pub const ARCAN_SHMIF_ABUFC_LIM = @as(usize, 12);
pub const enum_shmif_migrate_status = c_uint;
// Shmif types/constants for freestanding (added for shmif module imports)
pub const struct_debugint_ext_resolver = opaque {};
pub const struct_stat = extern struct { _data: [144]u8 = std.mem.zeroes([144]u8) };
pub const struct_cmsghdr = extern struct { cmsg_len: usize = 0, cmsg_level: c_int = 0, cmsg_type: c_int = 0 };
pub const tui_font = extern struct { _data: [8]u8 = std.mem.zeroes([8]u8) };
pub const STDIN_FILENO: c_int = 0;
pub const EINTR: c_int = 4;
pub const SUPPORT_EVENT_POLL: c_uint = 1;
pub const SHMIF_BGCOPY_KEEPIN: c_int = 1;
pub const SHMIF_BGCOPY_PROGRESS: c_int = 4;
pub const SHMIF_MIGRATE_NOCON: c_int = -2;
// EVENT_EXTERNAL_*, MBTN_*_IND: not needed here — shmif export fns
// have freestanding early returns, so the shmif-side enum values
// (which differ from engine-side values) are dead code on freestanding.
pub const struct_shmif_ext_hidden = extern struct {
    cleanup: ?*const fn (?*arcan_shmif_cont) callconv(.c) void = null,
    active_fd: c_int = -1,
    pending_fd: c_int = -1,
    state_fl: c_int = 0,
    _data: [44]u8 = std.mem.zeroes([44]u8),
};
pub const SHMIF_MIGRATE_OK = @as(c_uint, 0);
pub const STATE_NOACCEL = @as(c_int, 0);
pub const SYNC_VIDEO = @as(c_uint, 1);
pub const SHMIF_FATALFAIL_FUNC = @as(c_uint, 0);
pub const SHMIF_RESET_LOST = @as(c_int, 3);
// OpenAL type stubs for freestanding
pub const AL_NONE = @as(c_int, 0);
pub inline fn alGetSourcei(_: c_uint, _: c_int, _: *c_int) void {}
pub const ALuint = c_uint;
pub const ALint = c_int;
pub const ALenum = c_int;
pub const ALfloat = f32;
pub const ALsizei = c_int;
pub const ALCdevice = anyopaque;
pub const ALCcontext = anyopaque;
pub const surface_transform = struct_surface_transform;
pub const arcan_evctx = struct_arcan_evctx;
pub const arcan_frameserver = struct_arcan_frameserver;
pub const monitor_mode = struct_monitor_mode;
pub const struct_arcan_extevent = arcan.arcan_extevent;
pub const struct_arcan_strarr = arcan_strarr;
pub const struct_tui_context = arcan.tui_context;
pub const struct_tui_cbcfg = arcan.tui_cbcfg;
pub const struct_tui_constraints = arcan.tui_constraints;
pub const struct_tui_screen_attr = tui_screen_attr;
pub const agp_mesh_store = struct_agp_mesh_store;

// Error codes
pub const ARCAN_OK = arcan.ARCAN_OK;
pub const ARCAN_ERRC_NO_SUCH_OBJECT = arcan.ARCAN_ERRC_NO_SUCH_OBJECT;
pub const ARCAN_ERRC_BAD_ARGUMENT = arcan.ARCAN_ERRC_BAD_ARGUMENT;
pub const ARCAN_ERRC_NOAUDIO = arcan.ARCAN_ERRC_NOAUDIO;
pub const ARCAN_ERRC_CLONE_NOT_PERMITTED = arcan.ARCAN_ERRC_CLONE_NOT_PERMITTED;
pub const ARCAN_ERRC_UNACCEPTED_STATE = arcan.ARCAN_ERRC_UNACCEPTED_STATE;
pub const ARCAN_ERRC_OUT_OF_SPACE = arcan.ARCAN_ERRC_OUT_OF_SPACE;
pub const ARCAN_ERRC_BAD_RESOURCE = arcan.ARCAN_ERRC_BAD_RESOURCE;
pub const ARCAN_ERRC_BADVMODE = arcan.ARCAN_ERRC_BADVMODE;

// Resource namespace constants
pub const RESOURCE_APPL_TEMP = arcan.RESOURCE_APPL_TEMP;
pub const RESOURCE_APPL = arcan.RESOURCE_APPL;
pub const RESOURCE_APPL_SHARED = arcan.RESOURCE_APPL_SHARED;
pub const RESOURCE_APPL_STATE = arcan.RESOURCE_APPL_STATE;
pub const RESOURCE_SYS_APPLBASE = arcan.RESOURCE_SYS_APPLBASE;
pub const RESOURCE_SYS_APPLSTORE = arcan.RESOURCE_SYS_APPLSTORE;
pub const RESOURCE_SYS_APPLSTATE = arcan.RESOURCE_SYS_APPLSTATE;
pub const RESOURCE_SYS_FONT = arcan.RESOURCE_SYS_FONT;
pub const RESOURCE_SYS_BINS = arcan.RESOURCE_SYS_BINS;
pub const RESOURCE_SYS_LIBS = arcan.RESOURCE_SYS_LIBS;
pub const RESOURCE_SYS_DEBUG = arcan.RESOURCE_SYS_DEBUG;
pub const RESOURCE_SYS_SCRIPTS = arcan.RESOURCE_SYS_SCRIPTS;
pub const RESOURCE_NS_USER = arcan.RESOURCE_NS_USER;
pub const RESOURCE_SYS_ENDM = arcan.RESOURCE_SYS_ENDM;

// Event categories
// Override event categories as c_int (matching @cImport, not u8)
pub const EVENT_SYSTEM: c_int = 1;
pub const EVENT_IO: c_int = 2;
pub const EVENT_VIDEO: c_int = 4;
pub const EVENT_AUDIO: c_int = 8;
pub const EVENT_TARGET: c_int = 16;
pub const EVENT_FSRV: c_int = 32;
pub const EVENT_EXTERNAL: c_int = 64;

// Segment IDs / TARGET_COMMAND_* / EVENT_EXTERNAL_*
// These are defined in a single authoritative block further down in this
// file (search for "Source of truth: src/shmif/arcan_shmif_event.h").
pub const EVENT_EXTERNAL_SEGREQ: c_int = 10;

// IO device/data
// Override IO event constants as c_int (matching @cImport)
pub const EVENT_IDEVKIND_KEYBOARD: c_int = 1;
pub const EVENT_IDEVKIND_MOUSE: c_int = 2;
pub const EVENT_IDEVKIND_GAMEDEV: c_int = 4;
pub const EVENT_IDATATYPE_ANALOG: c_int = 1;
pub const EVENT_IDATATYPE_DIGITAL: c_int = 2;
pub const EVENT_IDATATYPE_TRANSLATED: c_int = 4;
pub const EVENT_IDATATYPE_TOUCH: c_int = 8;
pub const EVENT_IDATATYPE_EYES: c_int = 16;
pub const ARCAN_IOFL_GESTURE: c_int = 1;

// Key modifiers
pub const ARKMOD_NONE = arcan.ARKMOD_NONE;
pub const ARKMOD_LSHIFT = arcan.ARKMOD_LSHIFT;
pub const ARKMOD_RSHIFT = arcan.ARKMOD_RSHIFT;
pub const ARKMOD_LCTRL = arcan.ARKMOD_LCTRL;
pub const ARKMOD_RCTRL = arcan.ARKMOD_RCTRL;
pub const ARKMOD_LALT = arcan.ARKMOD_LALT;
pub const ARKMOD_RALT = arcan.ARKMOD_RALT;
pub const ARKMOD_LMETA = arcan.ARKMOD_LMETA;
pub const ARKMOD_RMETA = arcan.ARKMOD_RMETA;

// Video constants
pub const ARCAN_VIDEO_WORLDID = arcan.ARCAN_VIDEO_WORLDID;
pub const ARCAN_EID = arcan.ARCAN_EID;
pub const CONTEXT_STACK_LIMIT = arcan.CONTEXT_STACK_LIMIT;
pub const VITEM_CONTEXT_LIMIT = arcan.VITEM_CONTEXT_LIMIT;
pub const RENDERTARGET_LIMIT = arcan.RENDERTARGET_LIMIT;
pub const BADFD = arcan.BADFD;
pub const ARCAN_VINTER_LINEAR = arcan.ARCAN_VINTER_LINEAR;
pub const ARCAN_VTEX_REPEAT = arcan.ARCAN_VTEX_REPEAT;
pub const ARCAN_VTEX_CLAMP = arcan.ARCAN_VTEX_CLAMP;

// Blend/Clip/Filter/Image/Proc
pub const BLEND_NONE = arcan.BLEND_NONE;
pub const BLEND_NORMAL = arcan.BLEND_NORMAL;
pub const BLEND_ADD = arcan.BLEND_ADD;
pub const BLEND_MULTIPLY = arcan.BLEND_MULTIPLY;
pub const BLEND_SUB = arcan.BLEND_SUB;
pub const BLEND_PREMUL = arcan.BLEND_PREMUL;
pub const BLEND_FORCE = arcan.BLEND_FORCE;
pub const ARCAN_CLIP_OFF = arcan.ARCAN_CLIP_OFF;
pub const ARCAN_CLIP_ON = arcan.ARCAN_CLIP_ON;
pub const ARCAN_CLIP_SHALLOW = arcan.ARCAN_CLIP_SHALLOW;
pub const ARCAN_VFILTER_NONE = arcan.ARCAN_VFILTER_NONE;
pub const ARCAN_VFILTER_LINEAR = arcan.ARCAN_VFILTER_LINEAR;
pub const ARCAN_VFILTER_BILINEAR = arcan.ARCAN_VFILTER_BILINEAR;
pub const ARCAN_VFILTER_TRILINEAR = arcan.ARCAN_VFILTER_TRILINEAR;
pub const ARCAN_VFILTER_MIPMAP = arcan.ARCAN_VFILTER_MIPMAP;
pub const ARCAN_VIMAGE_NOPOW2 = arcan.ARCAN_VIMAGE_NOPOW2;
pub const ARCAN_VIMAGE_SCALEPOW2 = arcan.ARCAN_VIMAGE_SCALEPOW2;
pub const IMAGEPROC_NORMAL = arcan.IMAGEPROC_NORMAL;
pub const IMAGEPROC_FLIPH = arcan.IMAGEPROC_FLIPH;
pub const ARCAN_CUBEMAP = arcan.ARCAN_CUBEMAP;
pub const ARCAN_3DTEXTURE = arcan.ARCAN_3DTEXTURE;

// Tags
pub const ARCAN_TAG_NONE = arcan.ARCAN_TAG_NONE;
pub const ARCAN_TAG_IMAGE = arcan.ARCAN_TAG_IMAGE;
pub const ARCAN_TAG_TEXT = arcan.ARCAN_TAG_TEXT;
pub const ARCAN_TAG_FRAMESERV = arcan.ARCAN_TAG_FRAMESERV;
pub const ARCAN_TAG_ASYNCIMGLD = arcan.ARCAN_TAG_ASYNCIMGLD;
pub const ARCAN_TAG_ASYNCIMGRD = arcan.ARCAN_TAG_ASYNCIMGRD;
pub const ARCAN_TAG_3DOBJ = arcan.ARCAN_TAG_3DOBJ;
pub const ARCAN_TAG_3DCAMERA = arcan.ARCAN_TAG_3DCAMERA;
pub const ARCAN_TAG_CUSTOMPROC = arcan.ARCAN_TAG_CUSTOMPROC;
pub const ARCAN_TAG_LWA = arcan.ARCAN_TAG_LWA;
pub const ARCAN_TAG_VR = arcan.ARCAN_TAG_VR;

// Masks
pub const MASK_NONE = arcan.MASK_NONE;
pub const MASK_POSITION = arcan.MASK_POSITION;
pub const MASK_SCALE = arcan.MASK_SCALE;
pub const MASK_OPACITY = arcan.MASK_OPACITY;
pub const MASK_LIVING = arcan.MASK_LIVING;
pub const MASK_ORIENTATION = arcan.MASK_ORIENTATION;
pub const MASK_UNPICKABLE = arcan.MASK_UNPICKABLE;
pub const MASK_FRAMESET = arcan.MASK_FRAMESET;
pub const MASK_MAPPING = arcan.MASK_MAPPING;
pub const MASK_TRANSFORMS = arcan.MASK_TRANSFORMS;

// Anchors/Scale
pub const ANCHORP_UL = arcan.ANCHORP_UL;
pub const ANCHORP_UC = arcan.ANCHORP_UC;
pub const ANCHORP_UR = arcan.ANCHORP_UR;
pub const ANCHORP_CL = arcan.ANCHORP_CL;
pub const ANCHORP_C = arcan.ANCHORP_C;
pub const ANCHORP_CR = arcan.ANCHORP_CR;
pub const ANCHORP_LL = arcan.ANCHORP_LL;
pub const ANCHORP_LC = arcan.ANCHORP_LC;
pub const ANCHORP_LR = arcan.ANCHORP_LR;
pub const SCALEM_NONE = arcan.SCALEM_NONE;
pub const SCALEM_WIDTH = arcan.SCALEM_WIDTH;
pub const SCALEM_HEIGHT = arcan.SCALEM_HEIGHT;
pub const SCALEM_WIDTH_HEIGHT = arcan.SCALEM_WIDTH_HEIGHT;
pub const SCALEM_DEPTH = arcan.SCALEM_DEPTH;

// Order/Frameset/Rendertarget
pub const ORDER3D_NONE = arcan.ORDER3D_NONE;
pub const ORDER3D_FIRST = arcan.ORDER3D_FIRST;
pub const ORDER3D_LAST = arcan.ORDER3D_LAST;
pub const ARCAN_FRAMESET_SPLIT = arcan.ARCAN_FRAMESET_SPLIT;
pub const ARCAN_FRAMESET_MULTITEXTURE = arcan.ARCAN_FRAMESET_MULTITEXTURE;
pub const RENDERTARGET_DEPTH = arcan.RENDERTARGET_DEPTH;
pub const RENDERTARGET_COLOR = arcan.RENDERTARGET_COLOR;
pub const RENDERTARGET_COLOR_DEPTH_STENCIL = arcan.RENDERTARGET_COLOR_DEPTH_STENCIL;
pub const RENDERTARGET_RETAIN_ALPHA = arcan.RENDERTARGET_RETAIN_ALPHA;
pub const TGTFL_READING = arcan.TGTFL_READING;
pub const TGTFL_ALIVE = arcan.TGTFL_ALIVE;
pub const TGTFL_NOCLEAR = arcan.TGTFL_NOCLEAR;

// Vobj flags
pub const FL_INUSE = arcan.FL_INUSE;
pub const FL_NASYNC = arcan.FL_NASYNC;
pub const FL_TCYCLE = arcan.FL_TCYCLE;
pub const FL_ROTOFS = arcan.FL_ROTOFS;
pub const FL_ORDOFS = arcan.FL_ORDOFS;
pub const FL_PRSIST = arcan.FL_PRSIST;
pub const FL_FULL3D = arcan.FL_FULL3D;
pub const FL_RTGT = arcan.FL_RTGT;

// Feed functions
// Override FFUNC_ constants as c_int to match @cImport's enum mapping
pub const FFUNC_FATAL: c_int = 0;
pub const FFUNC_NULL: c_int = 1;
pub const FFUNC_AVFEED: c_int = 2;
pub const FFUNC_NULLFEED: c_int = 3;
pub const FFUNC_FEEDCOPY: c_int = 4;
pub const FFUNC_VFRAME: c_int = 5;
pub const FFUNC_NULLFRAME: c_int = 6;
pub const FFUNC_WRAPPED: c_int = 7;
pub const FFUNC_LUA_PROC: c_int = 8;
pub const FFUNC_3DOBJ: c_int = 9;
pub const FFUNC_LWA: c_int = 10;
pub const FFUNC_VR: c_int = 11;
pub const FFUNC_SOCKVER: c_int = 12;
pub const FFUNC_SOCKPOLL: c_int = 13;
pub const FFUNC_POLL: c_int = 0;
pub const FFUNC_RENDER: c_int = 1;
pub const FFUNC_TICK: c_int = 2;
pub const FFUNC_DESTROY: c_int = 3;
pub const FFUNC_READBACK: c_int = 4;
pub const FFUNC_READBACK_HANDLE: c_int = 5;
pub const FFUNC_ADOPT: c_int = 6;
pub const FRV_NOFRAME = arcan.FRV_NOFRAME;
pub const FRV_GOTFRAME = arcan.FRV_GOTFRAME;
pub const FRV_COPIED = arcan.FRV_COPIED;
pub const FRV_NOUPLOAD = arcan.FRV_NOUPLOAD;

// Shader env
pub const MODELVIEW_MATR = arcan.MODELVIEW_MATR;
pub const PROJECTION_MATR = arcan.PROJECTION_MATR;
pub const TEXTURE_MATR = arcan.TEXTURE_MATR;
pub const OBJ_OPACITY = arcan.OBJ_OPACITY;
pub const TRANS_BLEND = arcan.TRANS_BLEND;
pub const TRANS_MOVE = arcan.TRANS_MOVE;
pub const TRANS_ROTATE = arcan.TRANS_ROTATE;
pub const TRANS_SCALE = arcan.TRANS_SCALE;
pub const SIZE_INPUT = arcan.SIZE_INPUT;
pub const SIZE_OUTPUT = arcan.SIZE_OUTPUT;
pub const SIZE_STORAGE = arcan.SIZE_STORAGE;
pub const RTGT_ID = arcan.RTGT_ID;
pub const FRACT_TIMESTAMP_F = arcan.FRACT_TIMESTAMP_F;
pub const TIMESTAMP_D = arcan.TIMESTAMP_D;
pub const shdrbool = arcan.shdrbool;
pub const shdrint = arcan.shdrint;
pub const shdrfloat = arcan.shdrfloat;
pub const shdrvec2 = arcan.shdrvec2;
pub const shdrvec3 = arcan.shdrvec3;
pub const shdrvec4 = arcan.shdrvec4;
pub const shdrmat4x4 = arcan.shdrmat4x4;
pub const BASIC_2D = arcan.BASIC_2D;
pub const COLOR_2D = arcan.COLOR_2D;
pub const BASIC_3D = arcan.BASIC_3D;
pub const TXSTATE_OFF = arcan.TXSTATE_OFF;
pub const TXSTATE_TEX2D = arcan.TXSTATE_TEX2D;
pub const TXSTATE_DEPTH = arcan.TXSTATE_DEPTH;
pub const TXSTATE_TEX3D = arcan.TXSTATE_TEX3D;
pub const TXSTATE_CUBE = arcan.TXSTATE_CUBE;
pub const TXSTATE_TPACK = arcan.TXSTATE_TPACK;
pub const STORAGE_IMAGE_URI = arcan.STORAGE_IMAGE_URI;
pub const STORAGE_TEXT = arcan.STORAGE_TEXT;
pub const STORAGE_TEXTARRAY = arcan.STORAGE_TEXTARRAY;
pub const STORAGE_TPACK = arcan.STORAGE_TPACK;
pub const PIPELINE_2D = arcan.PIPELINE_2D;
pub const PIPELINE_3D = arcan.PIPELINE_3D;
pub const AGP_MESH_TRISOUP = arcan.AGP_MESH_TRISOUP;
pub const AGP_MESH_POINTCLOUD = arcan.AGP_MESH_POINTCLOUD;
pub const AGP_DEPTH_LESS = arcan.AGP_DEPTH_LESS;
pub const AGP_DEPTH_LESSEQUAL = arcan.AGP_DEPTH_LESSEQUAL;
pub const AGP_DEPTH_GREATER = arcan.AGP_DEPTH_GREATER;
pub const AGP_DEPTH_GREATEREQUAL = arcan.AGP_DEPTH_GREATEREQUAL;
pub const AGP_DEPTH_EQUAL = arcan.AGP_DEPTH_EQUAL;
pub const AGP_DEPTH_NOTEQUAL = arcan.AGP_DEPTH_NOTEQUAL;
pub const AGP_DEPTH_ALWAYS = arcan.AGP_DEPTH_ALWAYS;
pub const MESH_FACING_FRONT = arcan.MESH_FACING_FRONT;
pub const MESH_FACING_BACK = arcan.MESH_FACING_BACK;
pub const MESH_FACING_BOTH = arcan.MESH_FACING_BOTH;
pub const MESH_FACING_NODEPTH = arcan.MESH_FACING_NODEPTH;
pub const MESH_DEBUG_GEOMETRY = arcan.MESH_DEBUG_GEOMETRY;
pub const MESH_FILL_LINE = arcan.MESH_FILL_LINE;
pub const HINT_NONE = arcan.HINT_NONE;
pub const HINT_FL_PRIMARY = arcan.HINT_FL_PRIMARY;
pub const HINT_FIT = arcan.HINT_FIT;
pub const HINT_CROP = arcan.HINT_CROP;
pub const HINT_YFLIP = arcan.HINT_YFLIP;
pub const HINT_ROTATE_CW_90 = arcan.HINT_ROTATE_CW_90;
pub const HINT_ROTATE_CCW_90 = arcan.HINT_ROTATE_CCW_90;
pub const HINT_ROTATE_180 = arcan.HINT_ROTATE_180;
pub const HINT_CURSOR = arcan.HINT_CURSOR;
pub const HINT_DIRECT = arcan.HINT_DIRECT;
pub const TAG_TRANSFORM_SKIP = arcan.TAG_TRANSFORM_SKIP;
pub const TAG_TRANSFORM_LAST = arcan.TAG_TRANSFORM_LAST;
pub const TAG_TRANSFORM_ALL = arcan.TAG_TRANSFORM_ALL;

// Video events
pub const EVENT_VIDEO_EXPIRE = arcan.EVENT_VIDEO_EXPIRE;
pub const EVENT_VIDEO_CHAIN_OVER = arcan.EVENT_VIDEO_CHAIN_OVER;
pub const EVENT_VIDEO_DISPLAY_RESET = arcan.EVENT_VIDEO_DISPLAY_RESET;
pub const EVENT_VIDEO_DISPLAY_ADDED = arcan.EVENT_VIDEO_DISPLAY_ADDED;
pub const EVENT_VIDEO_DISPLAY_REMOVED = arcan.EVENT_VIDEO_DISPLAY_REMOVED;
pub const EVENT_VIDEO_DISPLAY_CHANGED = arcan.EVENT_VIDEO_DISPLAY_CHANGED;
pub const EVENT_VIDEO_ASYNCHIMAGE_LOADED = arcan.EVENT_VIDEO_ASYNCHIMAGE_LOADED;
pub const EVENT_VIDEO_ASYNCHIMAGE_FAILED = arcan.EVENT_VIDEO_ASYNCHIMAGE_FAILED;

// Memory
pub const ARCAN_MEM_VBUFFER = arcan.ARCAN_MEM_VBUFFER;
pub const ARCAN_MEM_VSTRUCT = arcan.ARCAN_MEM_VSTRUCT;
pub const ARCAN_MEM_EXTSTRUCT = arcan.ARCAN_MEM_EXTSTRUCT;
pub const ARCAN_MEM_ABUFFER = arcan.ARCAN_MEM_ABUFFER;
pub const ARCAN_MEM_STRINGBUF = arcan.ARCAN_MEM_STRINGBUF;
pub const ARCAN_MEM_SHARED = arcan.ARCAN_MEM_SHARED;
pub const ARCAN_MEM_VTAG = arcan.ARCAN_MEM_VTAG;
pub const ARCAN_MEM_ATAG = arcan.ARCAN_MEM_ATAG;
pub const ARCAN_MEM_BINDING = arcan.ARCAN_MEM_BINDING;
pub const ARCAN_MEM_MODELDATA = arcan.ARCAN_MEM_MODELDATA;
pub const ARCAN_MEM_THREADCTX = arcan.ARCAN_MEM_THREADCTX;
pub const ARCAN_MEM_BZERO = arcan.ARCAN_MEM_BZERO;
pub const ARCAN_MEM_TEMPORARY = arcan.ARCAN_MEM_TEMPORARY;
pub const ARCAN_MEM_EXEC = arcan.ARCAN_MEM_EXEC;
pub const ARCAN_MEM_NONFATAL = arcan.ARCAN_MEM_NONFATAL;
pub const ARCAN_MEM_READONLY = arcan.ARCAN_MEM_READONLY;
pub const ARCAN_MEM_SENSITIVE = arcan.ARCAN_MEM_SENSITIVE;
pub const ARCAN_MEMALIGN_NATURAL = arcan.ARCAN_MEMALIGN_NATURAL;
pub const ARCAN_MEMALIGN_PAGE = arcan.ARCAN_MEMALIGN_PAGE;
pub const ARCAN_MEMALIGN_SIMD = arcan.ARCAN_MEMALIGN_SIMD;

// Extern fn from arcan_zig_types
pub const arcan_warning = arcan.arcan_warning;
pub const arcan_mem_free = arcan.arcan_mem_free;
pub const arcan_fatal = arcan.arcan_fatal;
// Re-declare with ?*anyopaque return type
pub extern fn arcan_alloc_mem(sz: usize, memtype: c_uint, hint: c_uint, alignment: c_uint) ?*anyopaque;
pub extern fn arcan_alloc_fillmem(src: ?*const anyopaque, sz: usize, memtype: c_uint, hint: c_uint, alignment: c_uint) ?*anyopaque;
pub const arcan_random = arcan.arcan_random;
pub extern fn arcan_timemillis() c_ulonglong;
pub const arcan_frametime = arcan.arcan_frametime;
// Re-declare with boot_compat's sized struct_arcan_evctx (not arcan's anyopaque)
pub extern fn arcan_event_defaultctx() ?*struct_arcan_evctx;
pub extern fn arcan_event_init(ctx: ?*struct_arcan_evctx) void;
pub extern fn arcan_event_deinit(ctx: ?*struct_arcan_evctx, flush: bool) void;
pub extern fn arcan_event_enqueue(ctx: ?*struct_arcan_evctx, ev: *const arcan_event) c_int;
pub const arcan_event_purge = arcan.arcan_event_purge;
pub const arcan_sem_init = arcan.arcan_sem_init;
pub const arcan_sem_post = arcan.arcan_sem_post;
pub const arcan_sem_wait = arcan.arcan_sem_wait;
pub const arcan_audio_play = arcan.arcan_audio_play;
pub const arcan_audio_purge = arcan.arcan_audio_purge;
pub const arcan_open_resource = arcan.arcan_open_resource;
pub const arcan_release_resource = arcan.arcan_release_resource;
// Override: return boot_compat's map_region (with unnamed_0) not arcan's
pub extern fn arcan_map_resource(ds: *data_source, wr: bool) map_region;
pub extern fn arcan_release_map(region: map_region) bool;
pub const arcan_img_decode = arcan.arcan_img_decode;
pub const arcan_img_repack = arcan.arcan_img_repack;
pub const arcan_renderfun_outputdensity = arcan.arcan_renderfun_outputdensity;
pub const arcan_renderfun_release_fontgroup = arcan.arcan_renderfun_release_fontgroup;
pub extern fn arcan_renderfun_renderfmtstr(message: [*c]const u8, dst: arcan_vobj_id, pot: bool, n_lines: ?*c_uint, lineheights: ?*[*c]struct_renderline_meta, dw: *usize, dh: *usize, d_sz: *u32, maxw: *usize, maxh: *usize, norender: bool) [*c]av_pixel;
pub extern fn arcan_renderfun_renderfmtstr_extended(message: [*c]const [*c]const u8, dst: arcan_vobj_id, pot: bool, n_lines: ?*c_uint, lineheights: ?*[*c]struct_renderline_meta, dw: *usize, dh: *usize, d_sz: *u32, maxw: *usize, maxh: *usize, norender: bool) [*c]av_pixel;
pub const arcan_renderfun_stretchblit = arcan.arcan_renderfun_stretchblit;
pub extern fn arcan_resolve_vidprop(vobj: ?*arcan_vobject, lerp: f32, props: *surface_properties) void;
pub const arcan_ffunc_lookup = arcan.arcan_ffunc_lookup;
pub const arcan_video_deleteobject = arcan.arcan_video_deleteobject;
pub const arcan_video_forceupdate = arcan.arcan_video_forceupdate;
pub const arcan_video_reset_fontcache = arcan.arcan_video_reset_fontcache;
// Override to use boot_compat's struct_arcan_vobject_litem type
pub extern fn arcan_3d_refresh(camtag: arcan_vobj_id, cell: ?*struct_arcan_vobject_litem, frag: f32) ?*struct_arcan_vobject_litem;
pub const arcan_3d_obj_bb_intersect = arcan.arcan_3d_obj_bb_intersect;
pub const platform_video_init = arcan.platform_video_init;
pub const platform_video_shutdown = arcan.platform_video_shutdown;
pub const platform_video_prepare_external = arcan.platform_video_prepare_external;
pub const platform_video_restore_external = arcan.platform_video_restore_external;
pub const platform_video_decay = arcan.platform_video_decay;
pub const platform_video_dimensions = arcan.platform_video_dimensions;
pub const platform_video_query_displays = arcan.platform_video_query_displays;
pub const TTF_Quit = arcan.TTF_Quit;
pub const memmove = arcan.memmove;
pub const strdup = arcan.strdup;
pub const pthread_create = arcan.pthread_create;
pub const pthread_join = arcan.pthread_join;
pub const DEG2RAD = arcan.DEG2RAD;
pub const interp_1d_linear = arcan.interp_1d_linear;
pub const interp_1d_sine = arcan.interp_1d_sine;
pub const interp_1d_expout = arcan.interp_1d_expout;
pub const interp_1d_expin = arcan.interp_1d_expin;
pub const interp_1d_expinout = arcan.interp_1d_expinout;
pub const interp_1d_smoothstep = arcan.interp_1d_smoothstep;
// Override interp_3d/quat functions to use boot_compat vector/quat types
pub extern fn interp_3d_linear(startv: vector, stopv: vector, fract: f32) vector;
pub extern fn interp_3d_sine(startv: vector, endv: vector, fract: f32) vector;
pub extern fn interp_3d_expout(startv: vector, endv: vector, fract: f32) vector;
pub extern fn interp_3d_expin(startv: vector, endv: vector, fract: f32) vector;
pub extern fn interp_3d_expinout(startv: vector, endv: vector, fract: f32) vector;
pub extern fn interp_3d_smoothstep(startv: vector, endv: vector, fract: f32) vector;
pub extern fn nlerp_quat180(a: quat, b: quat, f: f32) quat;
pub extern fn nlerp_quat360(a: quat, b: quat, f: f32) quat;
pub const identity_matrix = arcan.identity_matrix;
pub const scale_matrix = arcan.scale_matrix;
pub const translate_matrix = arcan.translate_matrix;
pub const multiply_matrix = arcan.multiply_matrix;
pub const build_orthographic_matrix = arcan.build_orthographic_matrix;
pub extern fn build_quat_taitbryan(roll: f32, pitch: f32, yaw: f32) quat;
pub extern fn matr_quatf(a: quat, dmatr: [*c]f32) [*c]f32;
pub const matr_rotatef = arcan.matr_rotatef;
pub extern fn angle_quat(a: quat) vector;
pub extern fn norm_quat(src: quat) quat;
pub extern fn mul_quat(a: quat, b: quat) quat;
pub const agp_init = arcan.agp_init;
// Override AGP functions that use struct_agp_rendertarget/vstore/mesh_store
// (arcan_zig_types has these as anyopaque, boot_compat has real structs)
pub extern fn agp_activate_rendertarget(tgt: ?*struct_agp_rendertarget) void;
pub const agp_activate_stencil = arcan.agp_activate_stencil;
pub extern fn agp_activate_vstore(backing: ?*struct_agp_vstore) void;
pub extern fn agp_activate_vstore_multi(backing: [*c]?*struct_agp_vstore, n: usize) void;
pub const agp_blendstate = arcan.agp_blendstate;
pub extern fn agp_deactivate_vstore() void;
pub const agp_default_shader = arcan.agp_default_shader;
pub const agp_disable_stencil = arcan.agp_disable_stencil;
pub const agp_draw_vobj = arcan.agp_draw_vobj;
pub extern fn agp_drop_mesh(s: ?*struct_agp_mesh_store) void;
pub extern fn agp_drop_rendertarget(tgt: ?*struct_agp_rendertarget) void;
pub extern fn agp_drop_vstore(backing: ?*struct_agp_vstore) void;
pub extern fn agp_empty_vstore(backing: ?*struct_agp_vstore, w: usize, h: usize) void;
pub extern fn agp_null_vstore(backing: ?*struct_agp_vstore) void;
pub const agp_pipeline_hint = arcan.agp_pipeline_hint;
pub extern fn agp_poll_readback(vs: ?*struct_agp_vstore) struct_asynch_readback_meta;
pub const agp_prepare_stencil = arcan.agp_prepare_stencil;
pub extern fn agp_readback_synchronous(dst: ?*struct_agp_vstore) void;
pub const agp_rendertarget_clear = arcan.agp_rendertarget_clear;
pub extern fn agp_rendertarget_clearcolor(tgt: ?*struct_agp_rendertarget, r: f32, g: f32, b: f32, a: f32) void;
pub extern fn agp_rendertarget_proxy(tgt: ?*struct_agp_rendertarget, proxy_state: ?*const fn (?*struct_agp_rendertarget, usize) callconv(.c) bool, tag: usize) void;
pub extern fn agp_rendertarget_swapstore(tgt: ?*struct_agp_rendertarget, vstore: ?*struct_agp_vstore) bool;
pub extern fn agp_request_readback(vs: ?*struct_agp_vstore) void;
pub extern fn agp_resize_rendertarget(tgt: ?*struct_agp_rendertarget, neww: usize, newh: usize) void;
pub extern fn agp_resize_vstore(backing: ?*struct_agp_vstore, w: usize, h: usize) void;
pub const agp_save_output = arcan.agp_save_output;
pub extern fn agp_setup_rendertarget(vs: ?*struct_agp_vstore, mode: c_uint) [*c]struct_agp_rendertarget;
pub const agp_shader_activate = arcan.agp_shader_activate;
pub const agp_shader_envv = arcan.agp_shader_envv;
pub const agp_shader_flush = arcan.agp_shader_flush;
pub const agp_shader_forceunif = arcan.agp_shader_forceunif;
pub const agp_shader_rebuild_all = arcan.agp_shader_rebuild_all;
pub const agp_shader_valid = arcan.agp_shader_valid;
pub extern fn agp_slice_synch(backing: ?*struct_agp_vstore, n_slices: usize, slices: [*c]?*struct_agp_vstore) bool;
pub extern fn agp_slice_vstore(backing: ?*struct_agp_vstore, n_slices: usize, base_size: usize, state: c_uint) bool;
pub extern fn agp_submit_mesh(mesh: ?*struct_agp_mesh_store, flags: c_uint) void;
pub extern fn agp_update_vstore(backing: ?*struct_agp_vstore, copy: bool) void;
pub const arcan_expand_resource = arcan.arcan_expand_resource;
pub const arcan_override_namespace = arcan.arcan_override_namespace;
pub const arcan_softoverride_namespace = arcan.arcan_softoverride_namespace;
pub const arcan_pin_namespace = arcan.arcan_pin_namespace;
pub const arcan_fetch_namespace = arcan.arcan_fetch_namespace;
pub const arcan_lookup_namespace = arcan.arcan_lookup_namespace;
pub const arcan_isfile = arcan.arcan_isfile;
pub const arcan_isdir = arcan.arcan_isdir;
pub const platform_config_lookup = arcan.platform_config_lookup;
pub const arcan_shmif_enqueue = arcan.arcan_shmif_enqueue;
pub const arcan_shmif_poll = arcan.arcan_shmif_poll;
// Own extern fn declaration — accepts boot_compat's [*c]arcan_shmif_cont
pub extern fn arcan_shmif_drop(ctx: [*c]arcan_shmif_cont) void;
pub const arcan_shmif_pushutf8 = arcan.arcan_shmif_pushutf8;
pub const arcan_shmif_mousestate_ioev = arcan.arcan_shmif_mousestate_ioev;

pub extern var default_quat: quat;

// ══════════════════════════════════════════════════════════════════════════════
// Section 2: Lua C API
// ══════════════════════════════════════════════════════════════════════════════

pub const lua_State = opaque {};
pub const lua_Number = f64;
pub const lua_Integer = c_longlong;
pub const lua_CFunction = ?*const fn (?*lua_State) callconv(.c) c_int;
pub const lua_Debug = extern struct {
    event: c_int = 0,
    name: [*c]const u8 = null,
    namewhat: [*c]const u8 = null,
    what: [*c]const u8 = null,
    source: [*c]const u8 = null,
    srclen: usize = 0,
    currentline: c_int = 0,
    linedefined: c_int = 0,
    lastlinedefined: c_int = 0,
    nups: u8 = 0,
    nparams: u8 = 0,
    isvararg: u8 = 0,
    istailcall: u8 = 0,
    ftransfer: c_ushort = 0,
    ntransfer: c_ushort = 0,
    short_src: [60]u8 = std.mem.zeroes([60]u8),
    i_ci: ?*anyopaque = null,
};
pub const luaL_Reg = extern struct { name: ?[*:0]const u8 = null, func: lua_CFunction = null };

pub const LUA_TNIL: c_int = 0;
pub const LUA_TBOOLEAN: c_int = 1;
pub const LUA_TLIGHTUSERDATA: c_int = 2;
pub const LUA_TNUMBER: c_int = 3;
pub const LUA_TSTRING: c_int = 4;
pub const LUA_TTABLE: c_int = 5;
pub const LUA_TFUNCTION: c_int = 6;
pub const LUA_TUSERDATA: c_int = 7;
pub const LUA_TTHREAD: c_int = 8;
// Both freestanding and userspace builds link the in-tree Lua 5.4 port,
// which uses -LUAI_MAXSTACK - 1000 = -1001000. The previous -10000 was
// the Lua 5.1 / LuaJIT value and silently caused every call going through
// `c.LUA_REGISTRYINDEX` (luaL_getmetatable, lua_rawgeti, etc.) to land on
// a relative-top index that lua_type then reported as TNONE → durian's
// open_nonblock("=ipc/control") tripped luaV_finishget's "attempt to index
// a nil value" inside alt_nbio_open's setmetatable path.
pub const LUA_REGISTRYINDEX: c_int = -1001000;
// Note: Lua 5.4 removed LUA_GLOBALSINDEX. Use lua_setglobal/lua_getglobal/lua_pushglobaltable instead.
pub const LUA_NOREF: c_int = -2;
pub const LUA_MULTRET: c_int = -1;
pub const LUA_OK: c_int = 0;
pub const LUA_MASKCOUNT: c_int = 4;
pub const LUA_VERSION_NUM: c_int = 504;
pub const LUAAPI_VERSION_MAJOR: c_int = 0;
pub const LUAAPI_VERSION_MINOR: c_int = 14;

pub extern fn luaL_newstate() ?*lua_State;
pub extern fn luaL_openlibs(L: ?*lua_State) void;
pub extern fn luaL_loadbufferx(L: ?*lua_State, buff: [*c]const u8, sz: usize, name: [*c]const u8, mode: [*c]const u8) c_int;
pub inline fn luaL_loadbuffer(L: ?*lua_State, buff: [*c]const u8, sz: usize, name: [*c]const u8) c_int {
    return luaL_loadbufferx(L, buff, sz, name, null);
}
pub extern fn luaL_loadfilex(L: ?*lua_State, filename: [*c]const u8, mode: [*c]const u8) c_int;
pub inline fn luaL_loadfile(L: ?*lua_State, filename: [*c]const u8) c_int {
    return luaL_loadfilex(L, filename, null);
}
pub extern fn luaL_loadstring(L: ?*lua_State, s: [*c]const u8) c_int;
pub extern fn luaL_checkinteger(L: ?*lua_State, arg: c_int) lua_Integer;
pub extern fn luaL_checknumber(L: ?*lua_State, arg: c_int) lua_Number;
pub extern fn luaL_checklstring(L: ?*lua_State, arg: c_int, l: ?*usize) [*c]const u8;
pub extern fn luaL_checktype(L: ?*lua_State, arg: c_int, t: c_int) void;
pub extern fn luaL_checkudata(L: ?*lua_State, arg: c_int, tname: [*c]const u8) ?*anyopaque;
pub extern fn luaL_optinteger(L: ?*lua_State, arg: c_int, def: lua_Integer) lua_Integer;
pub extern fn luaL_optnumber(L: ?*lua_State, arg: c_int, def: lua_Number) lua_Number;
pub extern fn luaL_optlstring(L: ?*lua_State, arg: c_int, def: [*c]const u8, l: ?*usize) [*c]const u8;
pub extern fn luaL_error(L: ?*lua_State, fmt: [*c]const u8, ...) c_int;
pub extern fn luaL_argerror(L: ?*lua_State, arg: c_int, extramsg: [*c]const u8) c_int;
pub extern fn luaL_ref(L: ?*lua_State, t: c_int) c_int;
pub extern fn luaL_unref(L: ?*lua_State, t: c_int, ref: c_int) void;
pub extern fn luaL_newmetatable(L: ?*lua_State, tname: [*c]const u8) c_int;
pub inline fn luaL_getmetatable(L: ?*lua_State, tname: [*c]const u8) void {
    _ = lua_getfield(L, LUA_REGISTRYINDEX, tname);
}
pub extern fn luaL_setfuncs(L: ?*lua_State, l: [*]const luaL_Reg, nup: c_int) void;
pub extern fn luaL_typeerror(L: ?*lua_State, arg: c_int, tname: [*c]const u8) c_int;
pub extern fn lua_pcall(L: ?*lua_State, nargs: c_int, nresults: c_int, msgh: c_int) c_int;
pub extern fn lua_pcallk(L: ?*lua_State, nargs: c_int, nresults: c_int, errfunc: c_int, ctx: isize, k: ?*anyopaque) c_int;
pub extern fn lua_callk(L: ?*lua_State, nargs: c_int, nresults: c_int, ctx: isize, k: ?*anyopaque) void;
pub inline fn lua_call(L: ?*lua_State, nargs: c_int, nresults: c_int) void {
    lua_callk(L, nargs, nresults, 0, null);
}
pub extern fn lua_close(L: ?*lua_State) void;
pub extern fn lua_gettop(L: ?*lua_State) c_int;
pub extern fn lua_settop(L: ?*lua_State, idx: c_int) void;
pub extern fn lua_type(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_pushnil(L: ?*lua_State) void;
pub extern fn lua_pushinteger(L: ?*lua_State, n: lua_Integer) void;
pub extern fn lua_pushnumber(L: ?*lua_State, n: lua_Number) void;
pub extern fn lua_pushstring(L: ?*lua_State, s: [*c]const u8) void;
pub extern fn lua_pushlstring(L: ?*lua_State, s: [*c]const u8, len: usize) void;
pub extern fn lua_pushboolean(L: ?*lua_State, b: c_int) void;
pub extern fn lua_pushvalue(L: ?*lua_State, idx: c_int) void;
pub extern fn lua_pushcclosure(L: ?*lua_State, f: lua_CFunction, n: c_int) void;
pub extern fn lua_createtable(L: ?*lua_State, narr: c_int, nrec: c_int) void;
pub extern fn lua_newuserdatauv(L: ?*lua_State, size: usize, nuvalue: c_int) ?*anyopaque;
pub inline fn lua_newuserdata(L: ?*lua_State, size: usize) ?*anyopaque {
    return lua_newuserdatauv(L, size, 1);
}
pub extern fn lua_toboolean(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_tointegerx(L: ?*lua_State, idx: c_int, pisnum: ?*c_int) lua_Integer;
pub inline fn lua_tointeger(L: ?*lua_State, idx: c_int) lua_Integer {
    return lua_tointegerx(L, idx, null);
}
pub extern fn lua_tonumberx(L: ?*lua_State, idx: c_int, pisnum: ?*c_int) lua_Number;
pub inline fn lua_tonumber(L: ?*lua_State, idx: c_int) lua_Number {
    return lua_tonumberx(L, idx, null);
}
pub extern fn lua_tolstring(L: ?*lua_State, idx: c_int, len: ?*usize) [*c]const u8;
pub extern fn lua_isnumber(L: ?*lua_State, idx: c_int) c_int;
pub inline fn lua_isboolean(L: ?*lua_State, idx: c_int) bool {
    return lua_type(L, idx) == LUA_TBOOLEAN;
}
pub inline fn lua_isfunction(L: ?*lua_State, idx: c_int) bool {
    return lua_type(L, idx) == LUA_TFUNCTION;
}
pub extern fn lua_iscfunction(L: ?*lua_State, idx: c_int) c_int;
// Lua 5.4: these functions return c_int (the type of the pushed value).
pub extern fn lua_getfield(L: ?*lua_State, idx: c_int, k: [*c]const u8) c_int;
pub extern fn lua_setfield(L: ?*lua_State, idx: c_int, k: [*c]const u8) void;
pub extern fn lua_gettable(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_geti(L: ?*lua_State, idx: c_int, n: lua_Integer) c_int;
pub extern fn lua_rawget(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_rawgetp(L: ?*lua_State, idx: c_int, p: ?*const anyopaque) c_int;
pub extern fn lua_getiuservalue(L: ?*lua_State, idx: c_int, n: c_int) c_int;
// Lua 5.4 lua_rawgeti: n is lua_Integer (c_longlong). Existing call sites pass
// c_int via @intCast; expose via an inline wrapper that accepts c_int and widens.
pub inline fn lua_rawgeti(L: ?*lua_State, idx: c_int, n: c_int) c_int {
    const impl = @extern(*const fn (?*lua_State, c_int, lua_Integer) callconv(.c) c_int, .{ .name = "lua_rawgeti" });
    return impl(L, idx, @as(lua_Integer, n));
}
pub extern fn lua_rawset(L: ?*lua_State, idx: c_int) void;
pub extern fn lua_setmetatable(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_next(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_rotate(L: ?*lua_State, idx: c_int, n: c_int) void;
pub extern fn lua_rawlen(L: ?*lua_State, idx: c_int) c_ulonglong;
// Lua 5.4 global table access (replaces LUA_GLOBALSINDEX).
pub extern fn lua_setglobal(L: ?*lua_State, name: [*c]const u8) void;
pub extern fn lua_getglobal(L: ?*lua_State, name: [*c]const u8) c_int;
pub extern fn lua_pushglobaltable(L: ?*lua_State) void;
pub inline fn lua_insert(L: ?*lua_State, idx: c_int) void {
    lua_rotate(L, idx, 1);
}
pub inline fn lua_remove(L: ?*lua_State, idx: c_int) void {
    lua_rotate(L, idx, -1);
    lua_settop(L, -1 - 1);
}
pub inline fn lua_replace(L: ?*lua_State, idx: c_int) void {
    lua_rotate(L, idx, 1); // Lua 5.4: lua_copy(L, -1, idx); lua_pop(L, 1)
    lua_settop(L, -1 - 1);
}
pub inline fn lua_objlen(L: ?*lua_State, idx: c_int) usize {
    return @intCast(lua_rawlen(L, idx));
}
pub extern fn lua_sethook(L: ?*lua_State, f: ?*const fn (?*lua_State, ?*lua_Debug) callconv(.c) void, mask: c_int, count: c_int) c_int;
pub extern fn lua_getinfo(L: ?*lua_State, what: [*c]const u8, ar: ?*lua_Debug) c_int;
pub extern fn lua_getstack(L: ?*lua_State, level: c_int, ar: ?*lua_Debug) c_int;
pub inline fn luaopen_bit(_: ?*lua_State) c_int {
    return 0; // Lua 5.4 has native bitwise ops, no separate bit library
}

pub inline fn lua_newtable(L: ?*lua_State) void { lua_createtable(L, 0, 0); }
pub inline fn lua_pushcfunction(L: ?*lua_State, f: lua_CFunction) void { lua_pushcclosure(L, f, 0); }
pub inline fn lua_pushliteral(L: ?*lua_State, s: [*c]const u8) void { lua_pushstring(L, s); }

// Lua compat trampolines
// Two directions:
// - Freestanding (Lua 5.4): export 5.1 names → forward to 5.4 functions (provided by lua54 module)
// - Hosted (LuaJIT 5.1): export 5.4 names → forward to 5.1 functions (provided by LuaJIT)
const is_freestanding_lua = @import("builtin").os.tag == .freestanding;

comptime {
    if (@import("builtin").os.tag.isDarwin()) {
        // macOS arcan_vk links lua54 + compat51.zig in the same compilation —
        // both the 5.4 and 5.1 names are real exports; no trampolines needed.
    } else if (is_freestanding_lua) {
        // Freestanding: Lua 5.4 is linked. Provide 5.1 compat names → 5.4 implementations.
        @export(&lua_call_54, .{ .name = "lua_call", .linkage = .weak });
        @export(&lua_insert_54, .{ .name = "lua_insert", .linkage = .weak });
        @export(&lua_remove_54, .{ .name = "lua_remove", .linkage = .weak });
        @export(&lua_replace_54, .{ .name = "lua_replace", .linkage = .weak });
        @export(&lua_tonumber_54, .{ .name = "lua_tonumber", .linkage = .weak });
        @export(&lua_tointeger_54, .{ .name = "lua_tointeger", .linkage = .weak });
        @export(&lua_objlen_54, .{ .name = "lua_objlen", .linkage = .weak });
        @export(&lua_newuserdata_54, .{ .name = "lua_newuserdata", .linkage = .weak });
        @export(&luaL_loadbuffer_54, .{ .name = "luaL_loadbuffer", .linkage = .weak });
        @export(&luaL_loadfile_54, .{ .name = "luaL_loadfile", .linkage = .weak });
        @export(&luaL_getmetatable_54, .{ .name = "luaL_getmetatable", .linkage = .weak });
        @export(&lua_isboolean_54, .{ .name = "lua_isboolean", .linkage = .weak });
        @export(&luaopen_bit_stub, .{ .name = "luaopen_bit", .linkage = .weak });
    } else {
        // Hosted: LuaJIT (5.1) is linked. Provide 5.4 names → 5.1 implementations.
        @export(&lua_callk_51, .{ .name = "lua_callk", .linkage = .weak });
        @export(&lua_rotate_51, .{ .name = "lua_rotate", .linkage = .weak });
        @export(&lua_rawlen_51, .{ .name = "lua_rawlen", .linkage = .weak });
        @export(&lua_newuserdatauv_51, .{ .name = "lua_newuserdatauv", .linkage = .weak });
    }
}

// Freestanding trampolines: 5.1 name → 5.4 implementation (extern from lua54 module)
fn lua_call_54(L: ?*lua_State, nargs: c_int, nresults: c_int) callconv(.c) void { lua_callk(L, nargs, nresults, 0, null); }
fn lua_insert_54(L: ?*lua_State, idx: c_int) callconv(.c) void { lua_rotate(L, idx, 1); }
fn lua_remove_54(L: ?*lua_State, idx: c_int) callconv(.c) void { lua_rotate(L, idx, -1); lua_settop(L, -1 - 1); }
fn lua_replace_54(L: ?*lua_State, idx: c_int) callconv(.c) void { lua_rotate(L, idx, 1); lua_settop(L, -1 - 1); }
fn lua_tonumber_54(L: ?*lua_State, idx: c_int) callconv(.c) lua_Number { return lua_tonumberx(L, idx, null); }
fn lua_tointeger_54(L: ?*lua_State, idx: c_int) callconv(.c) lua_Integer { return lua_tointegerx(L, idx, null); }
fn lua_objlen_54(L: ?*lua_State, idx: c_int) callconv(.c) usize { return @intCast(lua_rawlen(L, idx)); }
fn lua_newuserdata_54(L: ?*lua_State, size: usize) callconv(.c) ?*anyopaque { return lua_newuserdatauv(L, size, 1); }
fn luaL_loadbuffer_54(L: ?*lua_State, buff: [*c]const u8, sz: usize, name: [*c]const u8) callconv(.c) c_int { return luaL_loadbufferx(L, buff, sz, name, null); }
fn luaL_loadfile_54(L: ?*lua_State, filename: [*c]const u8) callconv(.c) c_int { return luaL_loadfilex(L, filename, null); }
fn luaL_getmetatable_54(L: ?*lua_State, tname: [*c]const u8) callconv(.c) void { _ = lua_getfield(L, LUA_REGISTRYINDEX, tname); }
fn lua_isboolean_54(L: ?*lua_State, idx: c_int) callconv(.c) bool { return lua_type(L, idx) == LUA_TBOOLEAN; }
fn luaopen_bit_stub(_: ?*lua_State) callconv(.c) c_int { return 0; }

// Hosted (LuaJIT) trampolines: provide Lua 5.4 API names using LuaJIT 5.1 functions.
// Use @extern to reference LuaJIT symbols without conflicting with our weak exports above.
fn lua_callk_51(L: ?*lua_State, nargs: c_int, nresults: c_int, _: isize, _: ?*anyopaque) callconv(.c) void {
    _ = lua_pcall(L, nargs, nresults, 0);
}
fn lua_rotate_51(L: ?*lua_State, idx_raw: c_int, n_raw: c_int) callconv(.c) void {
    // lua_rotate(L, idx, n): rotate elements between idx and top by n positions.
    // LuaJIT provides lua_insert (top→idx) and lua_remove (idx→gone).
    const jit_insert = @extern(*const fn (?*lua_State, c_int) callconv(.c) void, .{ .name = "lua_insert" });
    const top = lua_gettop(L);
    if (top == 0) return;
    var idx = idx_raw;
    if (idx < 0) idx = top + 1 + idx;
    if (idx < 1 or idx > top) return;
    const elems: c_int = top - idx + 1;
    if (elems <= 1) return;
    var n = @mod(n_raw, elems);
    if (n < 0) n += elems;
    if (n == 0) return;
    if (n > 0) {
        // n>0: move top n elements down to idx position.
        // Equivalent to n repeated lua_insert(L, idx).
        var i: c_int = 0;
        while (i < n) : (i += 1) {
            jit_insert(L, idx);
        }
    }
}
fn lua_rawlen_51(L: ?*lua_State, idx: c_int) callconv(.c) c_ulonglong {
    const jit_objlen = @extern(*const fn (?*lua_State, c_int) callconv(.c) usize, .{ .name = "lua_objlen" });
    return @intCast(jit_objlen(L, idx));
}
fn lua_newuserdatauv_51(L: ?*lua_State, size: usize, _: c_int) callconv(.c) ?*anyopaque {
    const jit_newuserdata = @extern(*const fn (?*lua_State, usize) callconv(.c) ?*anyopaque, .{ .name = "lua_newuserdata" });
    return jit_newuserdata(L, size);
}

// ══════════════════════════════════════════════════════════════════════════════
// Section 3: arcan_vobject (full struct for freestanding)
// ══════════════════════════════════════════════════════════════════════════════

pub const arcan_vobject = extern struct {
    parent: ?*arcan_vobject = null,
    children: [*c]?*arcan_vobject = @ptrFromInt(0),
    frameset: ?*struct_vobject_frameset = null,
    vstore: [*c]struct_agp_vstore = null,
    flags: c_uint = 0,
    origw: u16 = 0,
    origh: u16 = 0,
    program: agp_shader_id = 0,
    _pad_shape: [4]u8 = .{ 0, 0, 0, 0 },
    shape: ?*struct_agp_mesh_store = null,
    feed: extern struct {
        ffunc: c_uint = 0,
        _pad0: [4]u8 = .{ 0, 0, 0, 0 },
        state: vfunc_state = .{},
        pcookie: u64 = 0,
    } = .{},
    txcos: [*c]f32 = null,
    blendmode: arcan_blendfunc = 0,
    order: c_int = 0,
    current: surface_properties = std.mem.zeroes(surface_properties),
    origo_ofs: point = std.mem.zeroes(point),
    _pad_align: [4]u8 = .{ 0, 0, 0, 0 },
    transform: ?*struct_surface_transform = null,
    mask: c_int = 0,
    clip: arcan_clipmode = 0,
    clip_src: arcan_vobj_id = 0,
    valid_cache: bool = false,
    rotate_state: bool = false,
    _pad_vc: [6]u8 = .{ 0, 0, 0, 0, 0, 0 },
    prop_cache: surface_properties = std.mem.zeroes(surface_properties),
    prop_matr: [16]f32 align(16) = std.mem.zeroes([16]f32),
    last_updated: c_ulong = 0,
    lifetime: c_long = 0,
    p_anchor: enum_parent_anchor = 0,
    p_scale: enum_parent_scale = 0,
    p_anchor_shift: enum_parent_anchor = 0,
    childslots: c_uint = 0,
    owner: [*c]struct_rendertarget = null,
    cellid: arcan_vobj_id = 0,
    extrefc: extern struct { attachments: c_int = 0, links: c_int = 0 } = .{},
    tracetag: ?[*:0]u8 = null,
    alttext: ?[*:0]u8 = null,
};

pub const arcan_video_context = struct_arcan_video_context;

// ══════════════════════════════════════════════════════════════════════════════
// Section 4: Missing constants (not in arcan_zig_types.zig)
// ══════════════════════════════════════════════════════════════════════════════

pub const ADPMS_OFF: c_int = 0;
pub const ADPMS_ON: c_int = 1;
pub const ADPMS_STANDBY: c_int = 2;
pub const ADPMS_SUSPEND: c_int = 3;
pub const AOBJ_STREAM: c_int = 1;
pub const AOBJ_CAPTUREFEED: c_int = 2;
// Canonical values from src/platform/platform_types.h:enum resource_type.
// Earlier 4/8 here disagreed with the callee (posix/namespace.zig: 256/512),
// so every system_load() / findresource(... ARES_RDONLY ...) call ended up
// opening files O_RDWR — failing EACCES on read-only system files like
// share/arcan/scripts/builtin/mouse.lua. That single mismatch was the root
// cause of the "mouse.lua not found" boot abort even when isfile=1.
pub const ARES_FILE: c_int = 1;
pub const ARES_FOLDER: c_int = 2;
pub const ARES_SOCKET: c_int = 3;
pub const ARES_CREATE: c_int = 256;
pub const ARES_RDONLY: c_int = 512;
pub const ARKMOD_CAPS: c_int = 0x2000;
pub const ARKMOD_NUM: c_int = 0x1000;
pub const ARKMOD_MODE: c_int = 0x4000;
pub const ANCHORP_ENDM: c_int = 10;
pub const SCALEM_ENDM: c_int = 5;
pub const BFRM_SHELL: c_int = 0;
pub const BFRM_BIN: c_int = 1;
pub const BFRM_LWA: c_int = 2;
pub const BFRM_GAME: c_int = 3;
pub const BFRM_EXTERN: c_int = 4;
pub const CB_SOURCE_NONE: c_int = 0;
pub const CB_SOURCE_FRAMESERVER: c_int = 1;
pub const CB_SOURCE_IMAGE: c_int = 2;
pub const CB_SOURCE_TRANSFORM: c_int = 3;
pub const CB_SOURCE_PREROLL: c_int = 4;
pub const CURSOR_BLOCK: c_int = 0;
pub const CURSOR_BAR: c_int = 1;
pub const CURSOR_UNDER: c_int = 2;
pub const CURSOR_HOLLOW: c_int = 3;
pub const CYLINDER_FILL_FULL: c_int = 0;
pub const CYLINDER_FILL_HALF: c_int = 1;
pub const CYLINDER_FILL_FULL_CAPS: c_int = 2;
pub const CYLINDER_FILL_HALF_CAPS: c_int = 3;
pub const DB_KVTARGET = c_int;
pub const DVT_APPL: c_int = 0;
pub const DVT_TARGET: c_int = 1;
pub const DVT_CONFIG: c_int = 3;
pub const DVT_ENDM: c_int = 4;
pub const BAD_CONFIG: c_int = -1;
pub const BAD_TARGET: c_int = -1;
pub const EP_TRIGGER_CLOCK: c_int = 1 << 0;
pub const EP_TRIGGER_INPUT: c_int = 1 << 1;
pub const EP_TRIGGER_INPUT_RAW: c_int = 1 << 2;
pub const EP_TRIGGER_INPUT_END: c_int = 1 << 3;
pub const EP_TRIGGER_ADOPT: c_int = 1 << 6;
pub const EP_TRIGGER_AUTORES: c_int = 1 << 7;
pub const EP_TRIGGER_AUTOFONT: c_int = 1 << 8;
pub const EP_TRIGGER_DISPLAYSTATE: c_int = 1 << 9;
pub const EP_TRIGGER_DISPLAYRESET: c_int = 1 << 10;
pub const EP_TRIGGER_FRAMESERVER: c_int = 1 << 11;
pub const EP_TRIGGER_MESH: c_int = 1 << 12;
pub const EP_TRIGGER_LWA: c_int = 1 << 14;
pub const EP_TRIGGER_IMAGE: c_int = 1 << 15;
pub const EP_TRIGGER_AUDIO: c_int = 1 << 16;
pub const EP_TRIGGER_MAIN: c_int = 1 << 17;
pub const EP_TRIGGER_NBIO_RD: c_int = 1 << 19;
pub const EP_TRIGGER_NBIO_WR: c_int = 1 << 20;
pub const EP_TRIGGER_NBIO_DATA: c_int = 1 << 21;
pub const ARCAN_VINTER_SINE: c_int = 1;
pub const ARCAN_VINTER_EXPOUT: c_int = 2;
pub const ARCAN_VINTER_EXPIN: c_int = 3;
pub const ARCAN_VINTER_EXPINOUT: c_int = 4;
pub const ARCAN_VINTER_SMOOTHSTEP: c_int = 5;
pub const ARCAN_VINTER_ENDMARKER: c_int = 6;
pub const EVENT_IO_BUTTON: c_int = 0;
pub const EVENT_IO_AXIS_MOVE: c_int = 1;
pub const EVENT_IO_TOUCH: c_int = 2;
pub const EVENT_IO_STATUS: c_int = 3;
pub const EVENT_IO_EYES: c_int = 4;
pub const EVENT_IDEV_ADDED: c_int = 0;
pub const EVENT_IDEV_REMOVED: c_int = 1;
pub const EVENT_IDEVKIND_TOUCHDISP: c_int = 3;
pub const EVENT_IDEVKIND_EYETRACKER: c_int = 5;
pub const EVENT_IDEVKIND_LEDCTRL: c_int = 6;
pub const EVENT_SYSTEM_EXIT: c_int = 0;
pub const EVENT_SYSTEM_DATA_IN: c_int = 1;
pub const EVENT_SYSTEM_DATA_OUT: c_int = 2;
pub const EVENT_AUDIO_PLAYBACK_FINISHED: c_int = 0;
pub const EVENT_TRANSLATION_SET: c_int = 0;
pub const EVENT_TRANSLATION_CLEAR: c_int = 1;
pub const EVENT_TRANSLATION_REMAP: c_int = 2;
pub const EVENT_FSRV_EXTCONN: c_int = 0;
pub const EVENT_FSRV_RESIZED: c_int = 1;
pub const EVENT_FSRV_TERMINATED: c_int = 2;
pub const EVENT_FSRV_DROPPEDFRAME: c_int = 3;
pub const EVENT_FSRV_DELIVEREDFRAME: c_int = 4;
pub const EVENT_FSRV_PREROLL: c_int = 5;
pub const EVENT_FSRV_APROTO: c_int = 6;
pub const EVENT_FSRV_GAMMARAMP: c_int = 7;
pub const EVENT_FSRV_IONESTED: c_int = 8;
pub const EVENT_FSRV_ADDVRLIMB: c_int = 9;
// EVENT_EXTERNAL_* / TARGET_COMMAND_* / SEGID_*
// Source of truth: src/shmif/arcan_shmif_event.h. The comment at the top of
// this file used to claim that arcan_lua.zig only pulled from here on
// freestanding, but in fact arcan_lua.zig (and several other engine modules)
// `@import("arcan_boot_compat")` on every target, so these values MUST match
// the canonical C header — otherwise the engine writes old/scrambled enum
// values into the shmpage event queue and clients (which use the correct
// ABI from src/shmif/shmif_types.zig) misinterpret them. That drift caused
// durian→client DISPLAYHINT (should be 14) to arrive as 11 (= UNPAUSE, so
// ignored) and DEVICE_NODE (should be 22) to arrive as 20 (= REQFAIL, so
// clients bailed out of preroll instead of activating).
pub const EVENT_EXTERNAL_MESSAGE: c_int = 0;
pub const EVENT_EXTERNAL_COREOPT: c_int = 1;
pub const EVENT_EXTERNAL_IDENT: c_int = 2;
pub const EVENT_EXTERNAL_FAILURE: c_int = 3;
pub const EVENT_EXTERNAL_BUFFERSTREAM: c_int = 4;
pub const EVENT_EXTERNAL_FRAMESTATUS: c_int = 5;
pub const EVENT_EXTERNAL_STREAMINFO: c_int = 6;
pub const EVENT_EXTERNAL_STREAMSTATUS: c_int = 7;
pub const EVENT_EXTERNAL_STATESIZE: c_int = 8;
pub const EVENT_EXTERNAL_FLUSHAUD: c_int = 9;
// EVENT_EXTERNAL_SEGREQ = 10 is defined elsewhere in this file.
pub const EVENT_EXTERNAL_CURSORHINT: c_int = 12;
pub const EVENT_EXTERNAL_VIEWPORT: c_int = 13;
pub const EVENT_EXTERNAL_CONTENT: c_int = 14;
pub const EVENT_EXTERNAL_LABELHINT: c_int = 15;
pub const EVENT_EXTERNAL_REGISTER: c_int = 16;
pub const EVENT_EXTERNAL_ALERT: c_int = 17;
pub const EVENT_EXTERNAL_CLOCKREQ: c_int = 18;
pub const EVENT_EXTERNAL_BCHUNKSTATE: c_int = 19;
pub const EVENT_EXTERNAL_PRIVDROP: c_int = 20;
pub const EVENT_EXTERNAL_INPUTMASK: c_int = 21;
pub const EVENT_EXTERNAL_NETSTATE: c_int = 22;
pub const EVENT_EXTERNAL_ULIM: c_int = 23;

pub const TARGET_COMMAND_EXIT: c_int = 1;
pub const TARGET_COMMAND_FRAMESKIP: c_int = 2;
pub const TARGET_COMMAND_STEPFRAME: c_int = 3;
pub const TARGET_COMMAND_COREOPT: c_int = 4;
pub const TARGET_COMMAND_STORE: c_int = 5;
pub const TARGET_COMMAND_RESTORE: c_int = 6;
pub const TARGET_COMMAND_BCHUNK_IN: c_int = 7;
pub const TARGET_COMMAND_BCHUNK_OUT: c_int = 8;
pub const TARGET_COMMAND_RESET: c_int = 9;
pub const TARGET_COMMAND_PAUSE: c_int = 10;
pub const TARGET_COMMAND_UNPAUSE: c_int = 11;
pub const TARGET_COMMAND_SEEKTIME: c_int = 12;
pub const TARGET_COMMAND_SEEKCONTENT: c_int = 13;
pub const TARGET_COMMAND_DISPLAYHINT: c_int = 14;
pub const TARGET_COMMAND_SETIODEV: c_int = 15;
pub const TARGET_COMMAND_STREAMSET: c_int = 16;
pub const TARGET_COMMAND_ATTENUATE: c_int = 17;
pub const TARGET_COMMAND_AUDDELAY: c_int = 18;
pub const TARGET_COMMAND_NEWSEGMENT: c_int = 19;
pub const TARGET_COMMAND_REQFAIL: c_int = 20;
pub const TARGET_COMMAND_BUFFER_FAIL: c_int = 21;
pub const TARGET_COMMAND_DEVICE_NODE: c_int = 22;
pub const TARGET_COMMAND_GRAPHMODE: c_int = 23;
pub const TARGET_COMMAND_MESSAGE: c_int = 24;
pub const TARGET_COMMAND_FONTHINT: c_int = 25;
pub const TARGET_COMMAND_GEOHINT: c_int = 26;
pub const TARGET_COMMAND_OUTPUTHINT: c_int = 27;
pub const TARGET_COMMAND_ACTIVATE: c_int = 28;
pub const TARGET_COMMAND_DEVICESTATE: c_int = 29;
pub const TARGET_COMMAND_ANCHORHINT: c_int = 30;
pub const TARGET_COMMAND_LIMIT: c_int = 2147483647; // INT_MAX

pub const SEGID_UNKNOWN: c_int = 0;
pub const SEGID_LWA: c_int = 1;
pub const SEGID_NETWORK_SERVER: c_int = 2;
pub const SEGID_NETWORK_CLIENT: c_int = 3;
pub const SEGID_MEDIA: c_int = 4;
pub const SEGID_TERMINAL: c_int = 5;
pub const SEGID_REMOTING: c_int = 6;
pub const SEGID_ENCODER: c_int = 7;
pub const SEGID_SENSOR: c_int = 8;
pub const SEGID_GAME: c_int = 9;
pub const SEGID_APPLICATION: c_int = 10;
pub const SEGID_BROWSER: c_int = 11;
pub const SEGID_VM: c_int = 12;
pub const SEGID_HMD_SBS: c_int = 13;
pub const SEGID_HMD_L: c_int = 14;
pub const SEGID_HMD_R: c_int = 15;
pub const SEGID_POPUP: c_int = 16;
pub const SEGID_ICON: c_int = 17;
pub const SEGID_TITLEBAR: c_int = 18;
pub const SEGID_CURSOR: c_int = 19;
pub const SEGID_ACCESSIBILITY: c_int = 20;
pub const SEGID_CLIPBOARD: c_int = 21;
pub const SEGID_CLIPBOARD_PASTE: c_int = 22;
pub const SEGID_WIDGET: c_int = 23;
pub const SEGID_TUI: c_int = 24;
pub const SEGID_SERVICE: c_int = 25;
pub const SEGID_BRIDGE_X11: c_int = 26;
pub const SEGID_BRIDGE_WAYLAND: c_int = 27;
pub const SEGID_HANDOVER: c_int = 28;
pub const SEGID_AUDIO: c_int = 29;
pub const SEGID_BRIDGE_ALLOCATOR: c_int = 30;
pub const SEGID_MONITOR: c_int = 254;
pub const SEGID_DEBUG: c_int = 255;
pub const SEGID_LIM: c_int = 256;
pub const ARCAN_SHMPAGE_MAXW: c_int = 8192;
pub const ARCAN_SHMPAGE_MAXH: c_int = 8192;
pub const ARCAN_SHMPAGE_VCHANNELS: c_int = 4;
pub const ARCAN_SHMIF_ACHANNELS: c_int = 2;
pub const ARCAN_SHM_UMASK: c_int = 0o077;
pub const SHMIF_RHINT_ORIGO_LL: c_int = 1;
pub const SHMIF_RHINT_TPACK: c_int = 64;
pub const SHMIF_META_CM: c_int = 1;
pub const SHMIF_META_HDR: c_int = 2;
pub const SHMIF_META_VR: c_int = 4;
pub const SHMIF_CMRAMP_PLIM: c_int = 256;
pub const SHMIF_CMRAMP_UPLIM: c_int = 2048;
pub const ARCAN_ANALOGFILTER_NONE: c_int = 0;
pub const ARCAN_ANALOGFILTER_PASS: c_int = 1;
pub const ARCAN_ANALOGFILTER_AVG: c_int = 2;
pub const ARCAN_ANALOGFILTER_ALAST: c_int = 3;
pub const ARCAN_ANALOGFILTER_FORGET: c_int = 4;
pub const TRACE_SYS_DEFAULT: c_int = 0;
pub const TRACE_SYS_SLOW: c_int = 1;
pub const TRACE_SYS_FAST: c_int = 2;
pub const TRACE_SYS_WARN: c_int = 3;
pub const TRACE_SYS_ERROR: c_int = 4;
pub const ARCAN_TIMER_TICK: c_int = 25;
pub const TUI_ATTR_BOLD: c_int = 1;
pub const TUI_ATTR_UNDERLINE: c_int = 2;
pub const TUI_ATTR_UNDERLINE_ALT: c_int = 4;
pub const TUI_ATTR_ITALIC: c_int = 8;
pub const TUI_ATTR_INVERSE: c_int = 16;
pub const TUI_ATTR_PROTECT: c_int = 32;
pub const TUI_ATTR_BLINK: c_int = 64;
pub const TUI_ATTR_STRIKETHROUGH: c_int = 128;
pub const TUI_ATTR_SHAPE_BREAK: c_int = 256;
pub const TUI_ATTR_BORDER_RIGHT: c_int = 512;
pub const TUI_ATTR_BORDER_DOWN: c_int = 1024;
pub const TUI_ATTR_BORDER_LEFT: c_int = 2048;
pub const TUI_ATTR_BORDER_TOP: c_int = 4096;
pub const TUI_ATTR_COLOR_INDEXED: c_int = 8192;
pub const TUI_HIDE_CURSOR: c_int = 1;
pub const VSTORE_HINT_NORMAL: c_int = 0;
pub const VSTORE_HINT_LODEF: c_int = 2;
pub const VSTORE_HINT_HIDEF: c_int = 4;
pub const VSTORE_HINT_F16: c_int = 6;
pub const VSTORE_HINT_F32: c_int = 8;
pub const RENDERTARGET_MSAA: c_int = 5;
pub const BROKEN_SHADER: c_uint = 0xffffffff;
pub const ARCAN_LUA_SWITCH_APPL: c_int = 1;
pub const ARCAN_LUA_SWITCH_APPL_NOADOPT: c_int = 2;
// Computed from RESOURCE_* bits to match src/engine/alt/support.h's
// canonical definitions. The previous numeric literals (63/31/127/255)
// did not include RESOURCE_SYS_SCRIPTS (2048) in CAREFUL_USERMASK and
// did not include RESOURCE_NS_USER (4096) in DEFAULT_USERMASK, so
// system_load("builtin/...") never searched the system-scripts namespace
// and user-namespace prefixes (ns:/...) were silently ignored.
pub const DEFAULT_USERMASK: c_int =
    RESOURCE_APPL | RESOURCE_APPL_SHARED | RESOURCE_APPL_TEMP | RESOURCE_NS_USER;
pub const CREATE_USERMASK: c_int =
    RESOURCE_APPL_TEMP | RESOURCE_APPL_SHARED | RESOURCE_NS_USER;
pub const CAREFUL_USERMASK: c_int =
    RESOURCE_APPL | RESOURCE_APPL_SHARED | RESOURCE_APPL_TEMP | RESOURCE_SYS_SCRIPTS;
pub const MODULE_USERMASK: c_int = RESOURCE_SYS_LIBS;
pub const MASK_ALL: c_int =
    RESOURCE_APPL | RESOURCE_APPL_TEMP | RESOURCE_APPL_SHARED |
    RESOURCE_APPL_STATE | RESOURCE_SYS_APPLBASE | RESOURCE_SYS_APPLSTORE |
    RESOURCE_SYS_APPLSTATE | RESOURCE_SYS_FONT | RESOURCE_SYS_BINS |
    RESOURCE_SYS_LIBS | RESOURCE_SYS_DEBUG | RESOURCE_SYS_SCRIPTS;
pub const EPSILON: f32 = 0.0001;
pub const MM_PER_PT: f32 = 0.352778;

// VR limbs
pub const NECK: c_int = 0;
pub const L_EYE: c_int = 1;
pub const R_EYE: c_int = 2;
pub const L_SHOULDER: c_int = 3;
pub const R_SHOULDER: c_int = 4;
pub const L_ELBOW: c_int = 5;
pub const R_ELBOW: c_int = 6;
pub const L_WRIST: c_int = 7;
pub const R_WRIST: c_int = 8;
pub const L_TOOL: c_int = 9;
pub const R_TOOL: c_int = 10;
pub const L_THUMB_PROXIMAL: c_int = 11;
pub const L_THUMB_MIDDLE: c_int = 12;
pub const L_THUMB_DISTAL: c_int = 13;
pub const L_POINTER_PROXIMAL: c_int = 14;
pub const L_POINTER_MIDDLE: c_int = 15;
pub const L_POINTER_DISTAL: c_int = 16;
pub const L_MIDDLE_PROXIMAL: c_int = 17;
pub const L_MIDDLE_MIDDLE: c_int = 18;
pub const L_MIDDLE_DISTAL: c_int = 19;
pub const L_RING_PROXIMAL: c_int = 20;
pub const L_RING_MIDDLE: c_int = 21;
pub const L_RING_DISTAL: c_int = 22;
pub const L_PINKY_PROXIMAL: c_int = 23;
pub const L_PINKY_MIDDLE: c_int = 24;
pub const L_PINKY_DISTAL: c_int = 25;
pub const R_THUMB_PROXIMAL: c_int = 26;
pub const R_THUMB_MIDDLE: c_int = 27;
pub const R_THUMB_DISTAL: c_int = 28;
pub const R_POINTER_PROXIMAL: c_int = 29;
pub const R_POINTER_MIDDLE: c_int = 30;
pub const R_POINTER_DISTAL: c_int = 31;
pub const R_MIDDLE_PROXIMAL: c_int = 32;
pub const R_MIDDLE_MIDDLE: c_int = 33;
pub const R_MIDDLE_DISTAL: c_int = 34;
pub const R_RING_PROXIMAL: c_int = 35;
pub const R_RING_MIDDLE: c_int = 36;
pub const R_RING_DISTAL: c_int = 37;
pub const R_PINKY_PROXIMAL: c_int = 38;
pub const R_PINKY_MIDDLE: c_int = 39;
pub const R_PINKY_DISTAL: c_int = 40;
pub const L_HIP: c_int = 41;
pub const R_HIP: c_int = 42;
pub const L_KNEE: c_int = 43;
pub const R_KNEE: c_int = 44;
pub const L_ANKLE: c_int = 45;
pub const R_ANKLE: c_int = 46;
pub const PERSON: c_int = 47;

// POSIX constants
pub const PATH_MAX: c_int = 4096;
pub const RTLD_NOW: c_int = 2;
pub const O_RDONLY: c_int = 0;
pub const O_WRONLY: c_int = 1;
pub const O_RDWR: c_int = 2;
pub const O_CREAT: c_int = if (is_darwin) 0x0200 else 64;
pub const O_TRUNC: c_int = if (is_darwin) 0x0400 else 512;
pub const O_CLOEXEC: c_int = if (is_darwin) 0x1000000 else 524288;
pub const O_DIRECTORY: c_int = if (is_darwin) 0x100000 else 65536;
pub const S_IRUSR: c_int = 256;
pub const S_IWUSR: c_int = 128;
pub const EXIT_SUCCESS: c_int = 0;
pub const EXIT_FAILURE: c_int = 1;
pub const SIGUSR1: c_int = if (is_darwin) 30 else 10;
pub const SA_SIGINFO: c_int = if (is_darwin) 0x0040 else 4;
pub const POLLIN: c_int = 1;
pub const POLLOUT: c_int = 4;
pub const POLLERR: c_int = 8;
pub const POLLHUP: c_int = 16;
pub const POLLNVAL: c_int = 32;
pub const EAGAIN: c_int = if (is_darwin) 35 else 11;
pub const EPROTOTYPE: c_int = if (is_darwin) 41 else 91;
pub const ECHILD: c_int = 10;
pub const O_NONBLOCK: c_int = if (is_darwin) 0x4 else 2048;
pub const AF_UNIX: c_int = 1;
pub const SOCK_STREAM: c_int = 1;
pub const SOCK_DGRAM: c_int = 2;
pub const F_GETFL: c_int = 3;
pub const F_SETFL: c_int = 4;
pub const F_GETFD: c_int = 1;
pub const F_SETFD: c_int = 2;
pub const FD_CLOEXEC: c_int = 1;
pub const S_IRWXU: c_int = 0o700;
pub const SEEK_SET: c_int = 0;
pub const SEEK_CUR: c_int = 1;
pub const SEEK_END: c_int = 2;
pub const PTHREAD_CREATE_DETACHED: c_int = if (is_darwin) 2 else 1;

// ══════════════════════════════════════════════════════════════════════════════
// Section 5: Missing types
// ══════════════════════════════════════════════════════════════════════════════

pub const FILE = opaque {};
// Darwin arm64 sigjmp_buf is 49 longs (392 bytes; _JBLEN=48 + sigmask slot) —
// the Linux 32-usize buffer overflows and corrupts the stack on sigsetjmp.
pub const jmp_buf = if (is_darwin) [49]usize else [32]usize;
pub const mode_t = c_uint;
pub const pid_t = c_int;
pub const sigaction_handler_fn = ?*const fn (c_int, [*c]siginfo_t, ?*anyopaque) callconv(.c) void;
pub const struct_sigaction = if (is_darwin) extern struct {
    __sa_handler: extern union {
        sa_handler: ?*const fn (c_int) callconv(.c) void,
        sa_sigaction: sigaction_handler_fn,
    } = .{ .sa_handler = null },
    sa_mask: c_uint = 0,
    sa_flags: c_int = 0,
} else extern struct {
    __sa_handler: extern union {
        sa_handler: ?*const fn (c_int) callconv(.c) void,
        sa_sigaction: sigaction_handler_fn,
    } = .{ .sa_handler = null },
    sa_mask: [16]c_ulong = std.mem.zeroes([16]c_ulong),
    sa_flags: c_int = 0,
    _pad0: [4]u8 = std.mem.zeroes([4]u8),
    sa_restorer: ?*const fn () callconv(.c) void = null,
};
pub const siginfo_t = extern struct { _data: [16]usize };
pub const pthread_attr_t = extern struct { _data: [8]usize };
pub const struct_pollfd = extern struct { fd: c_int, events: c_short, revents: c_short };
pub const struct_sockaddr_un = if (is_darwin) extern struct {
    sun_len: u8 = 0,
    sun_family: u8 = 0,
    sun_path: [104]u8 = std.mem.zeroes([104]u8),
} else extern struct {
    sun_family: c_ushort = 0,
    sun_path: [108]u8 = std.mem.zeroes([108]u8),
};
pub const off_t = c_long;
pub const sockaddr = anyopaque;
pub const socklen_t = c_uint;
pub extern fn socket(domain: c_int, sock_type: c_int, protocol: c_int) c_int;
pub extern fn bind(fd: c_int, addr: *const anyopaque, addrlen: socklen_t) c_int;
pub extern fn connect(fd: c_int, addr: *const anyopaque, addrlen: socklen_t) c_int;
pub extern fn listen(fd: c_int, backlog: c_int) c_int;
pub extern fn accept(fd: c_int, addr: ?*anyopaque, addrlen: ?*socklen_t) c_int;
pub extern fn lseek(fd: c_int, offset: off_t, whence: c_int) off_t;
pub extern fn random() c_long;
pub const file_handle = c_int;
pub const platform_display_id = c_uint;
pub const platform_mode_id = c_uint;
pub const nonblock_io = extern struct {
    eofm: bool = false,
    lfstrip: bool = false,
    _pad0: [6]u8 = std.mem.zeroes([6]u8),
    ofs: c_long = 0,
    lfch: u8 = 0,
    _pad1: [3]u8 = std.mem.zeroes([3]u8),
    fd: c_int = 0,
    out_queued: usize = 0,
    out_count: usize = 0,
    out_queue: ?*anyopaque = null,
    out_queue_tail: ?*anyopaque = null,
    mode: mode_t = 0,
    _pad2: [4]u8 = std.mem.zeroes([4]u8),
    unlink_fn: ?[*:0]u8 = null,
    pending: ?[*:0]u8 = null,
    data_rearmed: bool = false,
    _pad3: [7]u8 = std.mem.zeroes([7]u8),
    data_handler: isize = 0,
    write_handler: isize = 0,
    buf: [4096]u8 = std.mem.zeroes([4096]u8),
};
pub const struct_nonblock_io = nonblock_io;
pub const display_layer_cfg = extern struct {
    x: isize = 0,
    y: isize = 0,
    hint: enum_blitting_hint = 0,
    opacity: f32 = 0,
};
// drm_hdr_meta already defined above (line 57)
pub const vr_meta = extern struct {
    hres: c_uint = 0,
    vres: c_uint = 0,
    h_size: f32 = 0,
    v_size: f32 = 0,
    h_center: f32 = 0,
    eye_display: f32 = 0,
    lens_distance: f32 = 0,
    ipd: f32 = 0,
    left_fov: f32 = 0,
    right_fov: f32 = 0,
    left_ar: f32 = 0,
    right_ar: f32 = 0,
    hsep: f32 = 0,
    vpos: f32 = 0,
    distortion: [4]f32 = std.mem.zeroes([4]f32),
    abberation: [4]f32 = std.mem.zeroes([4]f32),
    projection_left: [16]f32 = std.mem.zeroes([16]f32),
    projection_right: [16]f32 = std.mem.zeroes([16]f32),
};
pub const region = extern struct { x1: c_int = 0, y1: c_int = 0, x2: c_int = 0, y2: c_int = 0 };
pub extern fn arcan_appl_id() [*c]const u8;
pub const arcan_benchdata = extern struct {
    bench_enabled: bool = false,
    _pad0: [3]u8 = std.mem.zeroes([3]u8),
    ticktime: [32]c_uint = std.mem.zeroes([32]c_uint),
    tickcount: c_uint = 0,
    tickofs: u8 = 0,
    _pad1: [3]u8 = std.mem.zeroes([3]u8),
    frametime: [64]c_uint = std.mem.zeroes([64]c_uint),
    framecount: c_uint = 0,
    frameofs: u8 = 0,
    _pad2: [3]u8 = std.mem.zeroes([3]u8),
    framecost: [64]c_uint = std.mem.zeroes([64]c_uint),
    costcount: c_uint = 0,
    costofs: u8 = 0,
};
pub const arcan_dbh = anyopaque;
pub const arcan_dbtrans_id = extern union {
    cid: c_long,
    tid: c_long,
    applname: [*c]const u8,
};
// fsrv event matching @cImport's unnamed_0 layout
pub const arcan_fsrvevent_full = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    unnamed_0: extern union {
        unnamed_0: extern struct {
            audio: i32 = 0,
            _pad_audio: [4]u8 = .{ 0, 0, 0, 0 },
            width: usize = 0,
            height: usize = 0,
            xofs: usize = 0,
            yofs: usize = 0,
            fmt_fl: i8 = 0,
            _pad_fmt: [7]u8 = std.mem.zeroes([7]u8),
            pts: u64 = 0,
            counter: u64 = 0,
            message: [32]u8 = std.mem.zeroes([32]u8),
        },
        unnamed_1: extern struct {
            ident: [32]u8 = std.mem.zeroes([32]u8),
            descriptor: i64 = 0,
        },
        unnamed_2: extern struct {
            aproto: c_int = 0,
        },
        unnamed_3: extern struct {
            limb: c_uint = 0,
        },
        input: arcan_ioevent,
    } = .{ .unnamed_0 = .{} },
    video: i64 = 0,
    otag: isize = 0,
};
pub const arcan_fsrvevent = extern struct {
    kind: c_uint = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    unnamed_0: extern union {
        unnamed_0: extern struct {
            audio: i32 = 0,
            _pad: [4]u8 = .{ 0, 0, 0, 0 },
            width: usize = 0,
            height: usize = 0,
            xofs: usize = 0,
            yofs: usize = 0,
            fmt_fl: i8 = 0,
        },
    } = .{ .unnamed_0 = .{} },
    video: i64 = 0,
    otag: isize = 0,
};
pub const arcan_vr_ctx = anyopaque;
pub const struct_arcan_vr_ctx = arcan_vr_ctx;
pub const struct_arcan_userns = extern struct {
    read: bool = false,
    write: bool = false,
    ipc: bool = false,
    _pad0: [1]u8 = .{0},
    dirfd: c_int = 0,
    label: [64]u8 = std.mem.zeroes([64]u8),
    name: [32]u8 = std.mem.zeroes([32]u8),
    path: [256]u8 = std.mem.zeroes([256]u8),
};
pub const subseg_output = c_int;
pub const enum_DB_BFORMAT = c_int;
pub const module_init_prototype = ?*const fn (c_int, c_int, c_int) callconv(.c) [*c]const luaL_Reg;
pub const cbfun = ?*const fn (?*lua_State) callconv(.c) c_int;
pub const frameserver_envp = extern struct {
    use_builtin: bool = false,
    _pad0: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
    custom_feed: c_longlong = 0,
    preserve_env: bool = false,
    _pad1: [3]u8 = .{ 0, 0, 0 },
    init_w: c_int = 0,
    init_h: c_int = 0,
    _pad2: [4]u8 = .{ 0, 0, 0, 0 },
    prequeue_sz: usize = 0,
    prequeue_events: ?*?*arcan_event = null,
    metamask: c_int = 0,
    _pad3: [4]u8 = .{ 0, 0, 0, 0 },
    args: extern struct {
        builtin: extern struct {
            resource: [*c]const u8 = null,
            mode: [*c]const u8 = null,
        } = .{},
    } = .{},
};
pub const struct_frameserver_envp = frameserver_envp;
pub const platform_mode_opts = extern struct {
    depth: c_int = 0,
    vrr: f32 = 0,
};
pub const arcan_afunc_cb = ?*const fn (arcan_aobj_id, ?*anyopaque, [*c]i16, usize) callconv(.c) arcan_errc;

// Helpers
pub inline fn RGBA(r: u8, g: u8, b: u8, a: u8) av_pixel {
    return @as(av_pixel, a) << 24 | @as(av_pixel, r) << 16 | @as(av_pixel, g) << 8 | @as(av_pixel, b);
}
pub inline fn RGBA_DECOMP(val: av_pixel, r: *u8, g: *u8, b: *u8, a: *u8) void {
    a.* = @truncate(val >> 24);
    r.* = @truncate(val >> 16);
    g.* = @truncate(val >> 8);
    b.* = @truncate(val);
}
pub inline fn build_vect(x: f32, y: f32, z: f32) vector {
    return .{ .unnamed_0 = .{ .unnamed_0 = .{ .x = x, .y = y, .z = z } } };
}

// ══════════════════════════════════════════════════════════════════════════════
// Section 6: Missing engine extern fn
// ══════════════════════════════════════════════════════════════════════════════

// Video
pub extern fn arcan_video_3dorder(order: arcan_order3d, rt: arcan_vobj_id) arcan_errc;
pub extern fn arcan_video_addfobject(feed: c_uint, state: vfunc_state, cons: img_cons, zv: c_int) arcan_vobj_id;
pub extern fn arcan_video_allocframes(id: arcan_vobj_id, n: c_uint, mode: c_uint) arcan_errc;
pub extern fn arcan_video_alterfeed(id: arcan_vobj_id, mode: c_uint, state: vfunc_state) arcan_errc;
pub extern fn arcan_video_attachtorendertarget(did: arcan_vobj_id, src: arcan_vobj_id, detach: bool) arcan_errc;
pub extern fn arcan_video_blendinterp(id: arcan_vobj_id, mode: c_uint) arcan_errc;
pub extern fn arcan_video_clipto(id: arcan_vobj_id, cid: arcan_vobj_id) arcan_errc;
pub extern fn arcan_video_contextsize(newlim: c_uint) bool;
pub extern fn arcan_video_contextusage(used: ?*c_uint) c_uint;
pub extern fn arcan_video_copyprops(src: arcan_vobj_id, dst: arcan_vobj_id) void;
pub extern fn arcan_video_copytransform(src: arcan_vobj_id, dst: arcan_vobj_id) arcan_errc;
pub extern fn arcan_video_currentattachment() arcan_vobj_id;
pub extern fn arcan_video_current_properties(id: arcan_vobj_id) surface_properties;
pub extern fn arcan_video_cursorpos(x: c_int, y: c_int, absolute: bool) void;
pub extern fn arcan_video_cursorsize(w: usize, h: usize) void;
pub extern fn arcan_video_cursorstore(id: arcan_vobj_id) void;
pub extern fn arcan_video_defaultattachment(id: arcan_vobj_id) arcan_vobj_id;
pub extern fn arcan_video_default_blendmode(mode: arcan_blendfunc) void;
pub extern fn arcan_video_defaultfont(ident: [*c]const u8, fd: c_int, sz: c_int, hintflag: c_int, append: bool) bool;
pub extern fn arcan_video_default_imageprocmode(mode: arcan_imageproc_mode) void;
pub extern fn arcan_video_default_scalemode(mode: arcan_vimage_mode) void;
pub extern fn arcan_video_default_texfilter(mode: arcan_vfilter_mode) void;
pub extern fn arcan_video_default_texmode(modes: c_uint, modet: c_uint) void;
pub extern fn arcan_video_defineshape(dst: arcan_vobj_id, n_s: usize, n_t: usize, store: *?*struct_agp_mesh_store, depth: bool) arcan_errc;
pub extern fn arcan_video_detachfromrendertarget(did: arcan_vobj_id, src: arcan_vobj_id) arcan_errc;
pub extern fn arcan_video_disable_worldid() void;
pub extern var arcan_video_display: struct_arcan_video_display;
pub extern fn arcan_video_extpopcontext(saved: *arcan_vobj_id) c_uint;
pub extern fn arcan_video_extpushcontext(saved: *arcan_vobj_id) c_int;
pub extern fn arcan_video_feedstate(id: arcan_vobj_id) [*c]vfunc_state;
pub extern fn arcan_video_findchild(id: arcan_vobj_id, ofs: c_uint) arcan_vobj_id;
pub extern fn arcan_video_findparent(id: arcan_vobj_id, ref: arcan_vobj_id) arcan_vobj_id;
pub extern fn arcan_video_fontdefaults(fd: ?*c_int, fdsz: ?*c_int, hint: ?*c_int) void;
pub extern fn arcan_video_forceblend(id: arcan_vobj_id, mode: arcan_blendfunc) arcan_errc;
pub extern fn arcan_video_forceread(sid: arcan_vobj_id, local: bool, dptr: *[*c]av_pixel, dstsz: *usize) arcan_errc;
pub extern fn arcan_video_framecyclemode(id: arcan_vobj_id, val: c_int) arcan_errc;
pub extern fn arcan_video_getmask(id: arcan_vobj_id) c_uint;
pub extern fn arcan_video_getobject(id: arcan_vobj_id) [*c]arcan_vobject;
pub extern fn arcan_video_getzv(id: arcan_vobj_id) c_ushort;
pub extern fn arcan_video_hittest(id: arcan_vobj_id, x: c_int, y: c_int) bool;
pub extern fn arcan_video_inheritorder(id: arcan_vobj_id, on: bool) arcan_errc;
pub extern fn arcan_video_initial_properties(id: arcan_vobj_id) surface_properties;
pub extern fn arcan_video_instanttransform(id: arcan_vobj_id, mask: c_int, method: enum_tag_transform_methods) arcan_errc;
pub extern fn arcan_video_isdescendant(id: arcan_vobj_id, parent: arcan_vobj_id, limit: c_int) bool;
pub extern fn arcan_video_linkobjs(src: arcan_vobj_id, parent: arcan_vobj_id, mask: c_uint, anchor: enum_parent_anchor, scale: enum_parent_scale) arcan_errc;
pub extern fn arcan_video_linkrendertarget(did: arcan_vobj_id, src: arcan_vobj_id, refresh: c_int, scale: bool, fmt: enum_rendertarget_mode) arcan_errc;
pub extern fn arcan_video_loadimage(fname: [*c]const u8, cons: img_cons, desm: arcan_vimage_mode) arcan_vobj_id;
pub extern fn arcan_video_loadimageasynch(fname: [*c]const u8, cons: img_cons, tag: isize) arcan_vobj_id;
pub extern fn arcan_video_maxorder(rt: arcan_vobj_id, ov: ?*u16) arcan_errc;
pub extern fn arcan_video_mipmapset(id: arcan_vobj_id, enable: bool) arcan_errc;
pub extern fn arcan_video_moveinterp(id: arcan_vobj_id, mode: c_uint) arcan_errc;
pub extern fn arcan_video_newvobject(id: ?*arcan_vobj_id) [*c]arcan_vobject;
pub extern fn arcan_video_nfreecontexts() c_int;
pub extern fn arcan_video_nullobject(w: f32, h: f32, order: c_uint) arcan_vobj_id;
pub extern fn arcan_video_objectfilter(id: arcan_vobj_id, mode: arcan_vfilter_mode) arcan_errc;
pub extern fn arcan_video_objectmove(id: arcan_vobj_id, x: f32, y: f32, z: f32, time: c_uint) arcan_errc;
pub extern fn arcan_video_objectopacity(id: arcan_vobj_id, opa: f32, time: c_uint) arcan_errc;
pub extern fn arcan_video_objectrotate(id: arcan_vobj_id, ang: f32, time: arcan_tickv) arcan_errc;
pub extern fn arcan_video_objectrotate3d(id: arcan_vobj_id, roll: f32, pitch: f32, yaw: f32, time: c_uint) arcan_errc;
pub extern fn arcan_video_objectscale(id: arcan_vobj_id, sx: f32, sy: f32, sz: f32, time: c_uint) arcan_errc;
pub extern fn arcan_video_objecttexmode(id: arcan_vobj_id, modes: c_uint, modet: c_uint) arcan_errc;
pub extern fn arcan_video_origoshift(id: arcan_vobj_id, sx: f32, sy: f32, sz: f32, anchor: enum_parent_anchor) arcan_errc;
pub extern fn arcan_video_override_mapping(id: arcan_vobj_id, txcos: [*c]const f32) arcan_errc;
pub extern fn arcan_video_persistobject(id: arcan_vobj_id) arcan_errc;
pub extern fn arcan_video_pick(rt: arcan_vobj_id, dst: [*c]arcan_vobj_id, count: usize, x: c_int, y: c_int) usize;
pub extern fn arcan_video_popcontext() c_uint;
pub extern fn arcan_video_prepare_external(keep_events: bool) bool;
pub extern fn arcan_video_properties_at(id: arcan_vobj_id, ticks: c_uint) surface_properties;
pub extern fn arcan_video_pushasynch(id: arcan_vobj_id) arcan_errc;
pub extern fn arcan_video_pushcontext() c_uint;
pub extern fn arcan_video_rawobject(buf: [*c]av_pixel, cons: img_cons, w: f32, h: f32, order: c_uint) arcan_vobj_id;
pub extern fn arcan_video_readtag(id: arcan_vobj_id, tag: *[*c]const u8, alt: *[*c]const u8) arcan_errc;
pub extern fn arcan_video_renderstring(id: arcan_vobj_id, arg: struct_arcan_rstrarg, lines: *c_uint, lineheights: *[*c]struct_renderline_meta, errc: *arcan_errc) arcan_vobj_id;
pub extern fn arcan_video_rendertargetdensity(did: arcan_vobj_id, vppcm: f32, hppcm: f32, reraster: bool, rescale: bool) arcan_errc;
pub extern fn arcan_video_rendertargetid(did: arcan_vobj_id, id: ?*c_int, mirror: ?*c_int) arcan_errc;
pub extern fn arcan_video_rendertarget_range(did: arcan_vobj_id, min: isize, max: isize) arcan_errc;
pub extern fn arcan_video_rendertarget_setnoclear(did: arcan_vobj_id, noclear: bool) arcan_errc;
pub extern fn arcan_video_resampleobject(id: arcan_vobj_id, did: arcan_vobj_id, neww: usize, newh: usize, prg: agp_shader_id, nocopy: bool) arcan_errc;
pub extern fn arcan_video_resize_canvas(w: usize, h: usize) arcan_errc;
pub extern fn arcan_video_resizefeed(id: arcan_vobj_id, w: usize, h: usize) arcan_errc;
pub extern fn arcan_video_resolve_properties(id: arcan_vobj_id) surface_properties;
pub extern fn arcan_video_restore_external(reset: bool) void;
pub extern fn arcan_video_retrieve_mapping(id: arcan_vobj_id, dst: [*c]f32) arcan_errc;
pub extern fn arcan_video_rpick(rt: arcan_vobj_id, dst: [*c]arcan_vobj_id, count: usize, x: c_int, y: c_int) usize;
pub extern fn arcan_video_scaleinterp(id: arcan_vobj_id, mode: c_uint) arcan_errc;
pub extern fn arcan_video_scaletxcos(id: arcan_vobj_id, s: f32, t: f32) arcan_errc;
pub extern fn arcan_video_screencoords(id: arcan_vobj_id, dst: [*c]vector) arcan_errc;
pub extern fn arcan_video_screenshot(dptr: *[*c]u32, dsize: *usize) arcan_errc;
pub extern fn arcan_video_setactiveframe(id: arcan_vobj_id, frame: c_uint) arcan_errc;
pub extern fn arcan_video_setasframe(dst: arcan_vobj_id, src: arcan_vobj_id, slot: usize) arcan_errc;
pub extern fn arcan_video_setclip(id: arcan_vobj_id, mode: arcan_clipmode) arcan_errc;
pub extern fn arcan_video_setlife(id: arcan_vobj_id, lifetime: c_uint) arcan_errc;
pub extern fn arcan_video_setprogram(id: arcan_vobj_id, shid: agp_shader_id) arcan_errc;
pub extern fn arcan_video_setuprendertarget(did: arcan_vobj_id, readback: c_int, refresh: c_int, scale: bool, fmt: enum_rendertarget_mode) arcan_errc;
pub extern fn arcan_video_setzv(id: arcan_vobj_id, zv: c_int) arcan_errc;
pub extern fn arcan_video_shareglstore(sid: arcan_vobj_id, did: arcan_vobj_id) arcan_errc;
pub extern fn arcan_video_sliceobject(id: arcan_vobj_id, stype: arcan_slicetype, base: usize, n_slices: usize) arcan_errc;
pub extern fn arcan_video_solidcolor(w: f32, h: f32, r: u8, g: u8, b: u8, zv: c_ushort) arcan_vobj_id;
pub extern fn arcan_video_storage_properties(id: arcan_vobj_id) img_cons;
pub extern fn arcan_video_tagtransform(id: arcan_vobj_id, tag: isize, mask: enum_tag_transform_methods) arcan_errc;
pub extern fn arcan_video_tracetag(id: arcan_vobj_id, message: [*c]const u8, alt: [*c]const u8) arcan_errc;
pub extern fn arcan_video_transfertransform(src: arcan_vobj_id, dst: arcan_vobj_id) arcan_errc;
pub extern fn arcan_video_transformcycle(id: arcan_vobj_id, cycle: bool) arcan_errc;
pub extern fn arcan_video_transformmask(id: arcan_vobj_id, mask: c_uint) arcan_errc;
pub extern fn arcan_video_tuisynch(id: arcan_vobj_id) void;
pub extern fn arcan_video_updateslices(id: arcan_vobj_id, n_slices: usize, slices: [*c]arcan_vobj_id) arcan_errc;
pub extern fn arcan_video_zaptransform(id: arcan_vobj_id, mask: c_int, left: [*c]c_uint) arcan_errc;

// 3D
pub extern fn arcan_3d_addmesh(dst: arcan_vobj_id, resource: data_source, nmaps: c_uint) arcan_errc;
pub extern fn arcan_3d_addraw(dst: arcan_vobj_id, verts: [*c]f32, nv: usize, indices: [*c]c_uint, ni: usize, txcos: [*c]f32, txcos2: [*c]f32, normals: [*c]f32, tangents: [*c]f32, colors: [*c]f32, bones: [*c]u16, weights: [*c]f32, nmaps: c_uint) arcan_errc;
pub extern fn arcan_3d_baseorient(id: arcan_vobj_id, roll: f32, pitch: f32, yaw: f32) arcan_errc;
pub extern fn arcan_3d_buildbox(w: f32, h: f32, d: f32, nmaps: c_uint, fill: bool) arcan_vobj_id;
pub extern fn arcan_3d_buildcylinder(r: f32, halfh: f32, steps: usize, nmaps: usize, fill_mode: c_int) arcan_vobj_id;
pub extern fn arcan_3d_buildplane(mins: f32, mint: f32, maxs: f32, maxt: f32, base: f32, sdens: f32, tdens: f32, nmaps: usize, vert: bool) arcan_vobj_id;
pub extern fn arcan_3d_buildsphere(r: f32, l: c_uint, m: c_uint, hemi: bool, nmaps: usize) arcan_vobj_id;
pub extern fn arcan_3d_camproj(vid: arcan_vobj_id, proj: [*c]f32) arcan_errc;
pub extern fn arcan_3d_camtag(tgt: arcan_vobj_id, vid: arcan_vobj_id, near: f32, far: f32, ar: f32, fov: f32, flags: c_int, line_width: f64) arcan_errc;
pub extern fn arcan_3d_emptymodel() arcan_vobj_id;
pub extern fn arcan_3d_finalizemodel(id: arcan_vobj_id) arcan_errc;
pub extern fn arcan_3d_infinitemodel(id: arcan_vobj_id, state: bool) arcan_errc;
pub extern fn arcan_3d_meshshader(id: arcan_vobj_id, shid: agp_shader_id, slot: c_uint) arcan_errc;
pub extern fn arcan_3d_pointcloud(count: usize, nmaps: c_uint) arcan_vobj_id;
pub extern fn arcan_3d_scalevertices(id: arcan_vobj_id) arcan_errc;
pub extern fn arcan_3d_swizzlemodel(id: arcan_vobj_id) arcan_errc;

// Audio
pub extern fn arcan_audio_capturefeed(dev: [*c]const u8) arcan_aobj_id;
pub extern fn arcan_audio_capturelist() [*c][*c]u8;
pub const arcan_audio_cfg = extern struct {
    hrtf: bool = false,
    _pad: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
    out: ?[*:0]const u8 = null,
};
pub extern fn arcan_audio_reconfigure(cfg: arcan_audio_cfg) c_int;
pub extern fn arcan_audio_feed(feed: arcan_afunc_cb, tag: ?*anyopaque, errc: *arcan_errc) arcan_aobj_id;
pub extern fn arcan_audio_getgain(id: arcan_aobj_id, gain: *f32) arcan_errc;
pub const arcan_monafunc_cb = ?*const fn (arcan_aobj_id, [*c]u8, usize, c_uint, c_uint, ?*anyopaque) callconv(.c) void;
pub extern fn arcan_audio_hookfeed(id: arcan_aobj_id, tag: ?*anyopaque, cb: arcan_monafunc_cb, oldtag: ?*?*anyopaque) arcan_errc;
pub extern fn arcan_audio_kind(id: arcan_aobj_id) c_int;
pub extern fn arcan_audio_listener(pos: [*c]f32) void;
pub extern fn arcan_audio_load_sample(fname: [*c]const u8, gain: f32, errc: ?*arcan_errc) arcan_aobj_id;
pub extern fn arcan_audio_position(id: arcan_aobj_id, vid: arcan_vobj_id) void;
pub extern fn arcan_audio_sample_buffer(buf: [*c]f32, elems: usize, channels: c_int, samplerate: c_int, fmt: [*c]const u8) arcan_aobj_id;
pub extern fn arcan_audio_scan_devices() [*c]const u8;
pub extern fn arcan_audio_setgain(id: arcan_aobj_id, gain: f32, time: u16) arcan_errc;
pub extern fn arcan_audio_stop(id: arcan_aobj_id) arcan_errc;

// Database
pub extern fn arcan_db_add_kvpair(dbh: ?*arcan_dbh, key: [*c]const u8, val: [*c]const u8) void;
pub extern fn arcan_db_applkeys(dbh: ?*arcan_dbh, appl: [*c]const u8, pattern: [*c]const u8) arcan_strarr;
pub extern fn arcan_db_appl_val(dbh: ?*arcan_dbh, appl: [*c]const u8, key: [*c]const u8) [*c]u8;
pub extern fn arcan_db_begin_transaction(dbh: ?*arcan_dbh, target: DB_KVTARGET, id: arcan_dbtrans_id) void;
pub extern fn arcan_db_configid(dbh: ?*arcan_dbh, target: c_long, config: [*c]const u8) c_long;
pub extern fn arcan_db_configs(dbh: ?*arcan_dbh, target: c_long) arcan_strarr;
pub extern fn arcan_db_end_transaction(dbh: ?*arcan_dbh) void;
pub extern fn arcan_db_getkeys(dbh: ?*arcan_dbh, domain: DB_KVTARGET, id: arcan_dbtrans_id) arcan_strarr;
pub extern fn arcan_db_get_shared(appl: ?*[*c]const u8) ?*arcan_dbh;
pub extern fn arcan_db_getvalue(dbh: ?*arcan_dbh, domain: c_int, id: c_long, key: [*c]const u8) [*c]u8;
pub extern fn arcan_db_launch_status(dbh: ?*arcan_dbh, id: c_long, ok: bool) void;
pub extern fn arcan_db_matchkey(dbh: ?*arcan_dbh, domain: c_int, pattern: [*c]const u8) arcan_strarr;
pub extern fn arcan_db_targetexec(dbh: ?*arcan_dbh, configid: c_long, bfmt: *enum_DB_BFORMAT, argv: *arcan_strarr, env: *arcan_strarr, libs: *arcan_strarr) [*c]u8;
pub extern fn arcan_db_targetid(dbh: ?*arcan_dbh, target: [*c]const u8, tag: [*c]u8) c_long;
pub extern fn arcan_db_targets(dbh: ?*arcan_dbh, tag: [*c]const u8) arcan_strarr;
pub extern fn arcan_db_targettag(dbh: ?*arcan_dbh, id: c_long) [*c]u8;
pub extern fn arcan_db_target_tags(dbh: ?*arcan_dbh) arcan_strarr;

// Frameserver
pub extern fn arcan_frameserver_flush(fsrv: [*c]struct_arcan_frameserver) void;
pub extern fn arcan_frameserver_free(fsrv: [*c]struct_arcan_frameserver) void;
pub extern fn arcan_frameserver_pause(fsrv: [*c]struct_arcan_frameserver) void;
pub extern fn arcan_frameserver_resume(fsrv: [*c]struct_arcan_frameserver) void;
pub extern fn arcan_frameserver_atypes() [*c]const u8;
pub extern fn arcan_frameserver_audioframe_direct(fsrv: ?*anyopaque, id: arcan_aobj_id, buf: [*c]i16, nsamples: usize, channels: c_uint) arcan_errc;
pub extern fn arcan_frameserver_avfeed_mixer(fsrv: [*c]struct_arcan_frameserver, n: c_int, sources: [*c]arcan_aobj_id) void;
pub extern fn arcan_frameserver_avfeedmon(src: arcan_aobj_id, buf: [*c]u8, buf_sz: usize, channels: c_uint, frequency: c_uint, tag: ?*anyopaque) void;
pub extern fn arcan_frameserver_displayhint(fsrv: [*c]struct_arcan_frameserver, w: usize, h: usize, ppcm: f32) void;
pub extern fn arcan_frameserver_getramps(fsrv: [*c]struct_arcan_frameserver, index: usize, table: [*c]f32, table_sz: usize, ch_sz: [*c]usize) bool;
pub extern fn arcan_frameserver_setfont(fsrv: [*c]struct_arcan_frameserver, fd: c_int, sz: f32, hint: c_int, slot: c_int) bool;
pub extern fn arcan_frameserver_setramps(fsrv: [*c]struct_arcan_frameserver, index: usize, table: [*c]f32, table_sz: usize, ch_sz: [*c]usize, edid: [*c]u8, edid_sz: usize) bool;
pub extern fn arcan_frameserver_update_mixweight(fsrv: [*c]struct_arcan_frameserver, source: arcan_aobj_id, leftch: f32, rightch: f32) void;

// Conductor
pub extern fn arcan_conductor_focus(fsrv: ?*struct_arcan_frameserver) void;
pub extern fn arcan_conductor_gpus_locked() usize;
pub extern fn arcan_conductor_register_frameserver(fsrv: [*c]struct_arcan_frameserver) void;
pub extern fn arcan_conductor_reset_count(step: bool) c_int;
pub extern fn arcan_conductor_setsynch(key: [*c]const u8) void;
pub extern fn arcan_conductor_synchopts() [*c][*c]const u8;

// LED
pub const led_capabilities = extern struct {
    nleds: c_int = 0,
    variable_brightness: bool = false,
    rgb: bool = false,
};
pub extern fn arcan_led_capabilities(devid: u8) led_capabilities;
pub extern fn arcan_led_controllers() u64;
pub extern fn arcan_led_intensity(devid: u8, ledid: i16, intensity: u8) c_int;
pub extern fn arcan_led_rgb(devid: u8, ledid: i16, r: u8, g: u8, b: u8, mflag: bool) c_int;

// Monitor
pub extern fn arcan_monitor_fsrvvid(cp: [*c]const u8, fsrv: ?*struct_arcan_frameserver) bool;
pub extern fn arcan_monitor_watchdog(ctx: ?*lua_State, ar: ?*lua_Debug) void;
pub extern fn arcan_monitor_watchdog_listen(ctx: ?*lua_State, name: [*c]const u8) void;

// Trace
pub extern fn arcan_trace_mark(sys: [*c]const u8, subsys: [*c]const u8, trigger: u8, tracelevel: u8, ident: u64, quant: u32, msg: [*c]const u8, file_name: [*c]const u8, func_name: [*c]const u8, line: c_uint) void;
pub extern fn arcan_trace_setbuffer(buf: ?*anyopaque, sz: usize, finish_flag: ?*bool) void;
pub extern fn arcan_trace_threadname(name: [*c]const u8) void;

// Platform events
pub extern fn platform_event_analogall(on: bool, mouse: bool) void;
pub extern fn platform_event_analogfilter(devid: c_int, axis: c_int, lb: c_int, ub: c_int, dz: c_int, bsz: c_int, mode: c_uint) void;
pub extern fn platform_event_analogstate(devid: c_int, axis: c_int, lb: *c_int, ub: *c_int, dz: *c_int, kbsz: *c_int, mode: *c_uint) arcan_errc;
pub extern fn platform_event_capabilities(dst: *[*c]const u8) c_uint;
pub extern fn platform_event_devlabel(devid: c_int) [*c]const u8;
pub extern fn platform_event_keyrepeat(ctx: ?*struct_arcan_evctx, period: *c_int, delay: *c_int) void;
pub extern fn platform_event_rescan_idev(ctx: ?*struct_arcan_evctx) void;
pub extern fn platform_event_samplebase(devid: c_int, xyz: [*c]f32) void;
pub extern fn platform_event_translation(devid: c_int, action: c_int, names: [*c][*c]const u8, errmsg: [*c][*c]const u8) c_int;

// Platform video
pub extern fn platform_video_capstr() [*c]const u8;
pub extern fn platform_video_cardhandle(cardn: c_int, buffer_method: *c_int, metadata_sz: *usize, metadata: *[*c]u8) c_int;
pub extern fn platform_video_display_edid(did: platform_display_id, buf: *[*c]u8, sz: *usize) bool;
pub extern fn platform_video_dpms(did: platform_display_id, mode: c_int) c_int;
pub extern fn platform_video_get_display_gamma(did: platform_display_id, sz: *usize, outb: *[*c]u16) bool;
pub extern fn platform_video_map_display_layer(id: arcan_vobj_id, did: platform_display_id, layer_id: usize, cfg: display_layer_cfg) isize;
pub extern fn platform_video_query_modes(did: platform_display_id, count: *usize) [*c]struct_monitor_mode;
pub extern fn platform_video_reset(id: c_int, swap: c_int) void;
pub extern fn platform_video_set_display_gamma(did: platform_display_id, sz: usize, r: [*c]const u16, g: [*c]const u16, b: [*c]const u16) bool;
pub extern fn platform_video_set_mode(did: platform_display_id, mid: platform_mode_id, opts: platform_mode_opts) bool;
pub extern fn platform_video_specify_mode(did: platform_display_id, mode: struct_monitor_mode) bool;

// Platform frameserver
pub extern fn platform_fsrv_default_abufsize(new_sz: usize) usize;
pub extern fn platform_fsrv_enter(fsrv: [*c]struct_arcan_frameserver, ctx: [*c]jmp_buf) void;
pub extern fn platform_fsrv_leave() void;
pub extern fn platform_fsrv_pushevent(fsrv: [*c]struct_arcan_frameserver, ev: *const arcan_event) c_int;
pub extern fn platform_fsrv_pushfd(fsrv: ?*struct_arcan_frameserver, ev: *arcan_event, fd: c_int) c_int;
pub extern fn platform_fsrv_spawn_subsegment(parent: [*c]struct_arcan_frameserver, segid: c_int, hints: c_int, w: usize, h: usize, tag: usize, reqid: u32) [*c]struct_arcan_frameserver;
pub extern fn platform_fsrv_wrapcl(C: [*c]arcan_shmif_cont, tag: usize) [*c]struct_arcan_frameserver;

// Platform misc
pub extern fn platform_is_lwa_mode() bool;
pub extern fn platform_launch_fork(env: *frameserver_envp, tag: usize) ?*struct_arcan_frameserver;
pub extern fn platform_launch_internal(fname: [*c]const u8, argv: *arcan_strarr, envv: *arcan_strarr, libs: *arcan_strarr, tag: usize) ?*struct_arcan_frameserver;
pub extern fn platform_launch_listen_external(key: [*c]const u8, pw: [*c]const u8, fd: c_int, mode: mode_t, w: usize, h: usize, tag: usize) [*c]struct_arcan_frameserver;
pub extern fn platform_lwa_allocbind_feed(ctx: ?*anyopaque, rtgt: arcan_vobj_id, seg_type: c_uint, cbtag: usize) bool;
pub extern fn platform_lwa_targetevent(fsrv: ?*anyopaque, ev: *const arcan_event) bool;

// Alt subsystem
pub extern fn alt_apply_ban(ctx: ?*lua_State) void;
pub extern fn alt_call(ctx: ?*lua_State, kind: c_int, maskv: u64, kind_tag: usize, args: c_int, retc: c_int, src: [*c]const u8) void;
pub extern fn alt_loadfile(ctx: ?*lua_State, fname: [*c]const u8) c_int;
pub extern fn alt_lookup_entry(ctx: ?*lua_State, name: [*c]const u8, len: usize) bool;
pub extern fn alt_nbio_data_in(ctx: ?*lua_State, tag: isize) void;
pub extern fn alt_nbio_data_out(ctx: ?*lua_State, tag: isize) void;
pub extern fn alt_nbio_import(ctx: ?*lua_State, fd: c_int, mode: mode_t, dst: *[*c]nonblock_io, unlink_fn: ?*?[*:0]u8) bool;
pub extern fn alt_nbio_process_read(ctx: ?*lua_State, nb: *nonblock_io, nonbuf: bool) c_int;
pub extern fn alt_nbio_register(ctx: ?*lua_State, add_fn: ?*const fn (c_int, mode_t, isize) callconv(.c) bool, remove_fn: ?*const fn (c_int, mode_t, *isize) callconv(.c) bool, error_fn: ?*const fn (?*lua_State, c_int, isize, [*c]const u8) callconv(.c) void) void;
pub extern fn alt_nbio_release() void;
pub extern fn alt_setup_context(ctx: ?*lua_State, appl: [*c]const u8) void;
pub extern fn alt_trace_crash_source() [*c]const u8;
pub extern fn alt_trace_finish(ctx: ?*lua_State) void;
pub extern fn alt_trace_log(ctx: ?*lua_State) callconv(.c) c_int;
pub extern fn alt_trace_set_crash_source(msg: [*c]const u8) void;
pub extern fn alt_fatal(msg: [*c]const u8) void;
pub extern fn arcan_shmif_bgcopy(ctx: ?*anyopaque, src: c_int, dst: c_int, sigfd: c_int, flags: c_int) void;
pub extern fn alt_trace_start(ctx: ?*lua_State, cb: isize, sz: usize) bool;

// Misc engine
pub extern fn arcan_lua_pushglobalconsts(ctx: ?*lua_State) void;
pub extern fn arcan_lua_setglobalnum(ctx: ?*lua_State, key: [*c]const u8, val: f64) void;
pub extern fn arcan_lua_setglobalstr(ctx: ?*lua_State, key: [*c]const u8, val: [*c]const u8) void;
pub extern fn arcan_lua_statesnap(dst: ?*FILE, tag: [*c]const u8, delim: bool) void;
pub extern fn arcan_base64_decode(instr: [*c]const u8, outsz: *usize, hint: c_int) [*c]u8;
pub extern fn arcan_base64_encode(data: [*c]const u8, inl: usize, outl: *usize, hint: c_int) [*c]u8;
pub extern fn arcan_device_lock(devid: c_int, lockstate: bool) void;
pub extern fn arcan_event_add_source(ctx: ?*struct_arcan_evctx, fd: c_int, mode: mode_t, otag: isize, mask: bool) bool;
pub extern fn arcan_event_clearmask(ctx: ?*struct_arcan_evctx) void;
pub extern fn arcan_event_del_source(ctx: ?*struct_arcan_evctx, fd: c_int, mode: mode_t, out: *isize) bool;
pub extern fn arcan_event_maskall(ctx: ?*struct_arcan_evctx) void;
pub extern fn arcan_event_repl(ctx: ?*struct_arcan_evctx, cat: c_int, r_ofs: usize, r_b: usize, cmpbuf: ?*anyopaque, w_ofs: usize, w_b: usize, w_buf: ?*anyopaque) void;
pub extern fn arcan_expand_namespaces(inargs: [*c][*c]u8) [*c][*c]u8;
pub extern fn arcan_find_resource(label: [*c]const u8, ns: c_uint, mode: c_uint, dfd: ?*c_int) [*c]u8;
pub extern fn arcan_glob(basename: [*c]u8, ns: c_uint, cb: ?*const fn ([*c]u8, ?*anyopaque) callconv(.c) void, asynch: ?*c_int, tag: ?*anyopaque) c_uint;
pub extern fn arcan_glob_userns(basename: [*c]u8, userns: [*c]const u8, cb: ?*const fn ([*c]u8, ?*anyopaque) callconv(.c) void, asynch: ?*c_int, tag: ?*anyopaque) c_uint;
pub extern fn arcan_img_outpng(dst: ?*FILE, buf: [*c]u32, w: usize, h: usize, vflip: bool) bool;
pub extern fn arcan_mem_freearr(arr: *arcan_strarr) void;
pub extern fn arcan_process_title(newtitle: [*c]const u8) void;
pub extern fn arcan_pt_to_mm(pt: usize) f32;
pub extern fn arcan_renderfun_fontgroup(fds: [*c]c_int, n_fonts: usize) ?*anyopaque;
pub extern fn arcan_renderfun_fontgroup_size(group: ?*anyopaque, size_mm: f32, ppcm: f32, w: *usize, h: *usize) void;
pub extern fn arcan_shmif_dupfd(fd: c_int, dstnum: c_int, blocking: bool) c_int;
pub extern fn arcan_shmif_resolve_connpath(key: [*c]const u8, dst: [*c]u8, dsz: usize) c_int;
pub extern fn arcan_target_launch_external(fname: [*c]const u8, argv: *arcan_strarr, env: *arcan_strarr, libs: *arcan_strarr, exitc: *c_int) c_ulong;
pub extern fn arcan_timemicros() c_longlong;
pub extern fn arcan_user_namespaces() arcan_strarr;
pub extern fn arcan_verifyload_appl(appl: [*c]const u8, out: *[*c]const u8) bool;
pub extern fn arcan_verify_namespaces(report: bool) bool;
pub extern fn arcan_vint_attachobject(id: arcan_vobj_id) arcan_errc;
pub extern fn arcan_vint_defaultmapping(dst: [*c]f32, st: f32, tt: f32) void;
pub extern fn arcan_vint_findrt(vobj: [*c]arcan_vobject) [*c]struct_rendertarget;
pub extern fn arcan_vint_mirrormapping(dst: [*c]f32, st: f32, tt: f32) void;
pub extern fn arcan_vint_pollfeed(vid: arcan_vobj_id, step: bool) arcan_errc;
pub extern fn arcan_vint_pollreadback(rtgt: ?*struct_rendertarget) void;
pub extern fn arcan_vr_displaydata(ctx: ?*arcan_vr_ctx, dst: *vr_meta) arcan_errc;
pub extern fn arcan_vr_maplimb(ctx: ?*arcan_vr_ctx, limb: c_uint, vid: arcan_vobj_id, phy: bool, @"async": bool) arcan_errc;
pub extern fn arcan_vr_setref(ctx: ?*arcan_vr_ctx) arcan_errc;
pub extern fn arcan_vr_setup(bridge_arg: [*c]const u8, evctx: ?*struct_arcan_evctx, tag: usize) ?*arcan_vr_ctx;
pub extern fn callback_framestate(state: vfunc_state, mode: c_int) void;
pub extern fn region_valid(r: *const region) bool;

// AGP extras
pub extern fn agp_empty_vstoreext(backing: ?*struct_agp_vstore, w: usize, h: usize, mode: c_int) void;
pub extern fn agp_ident() [*c]const u8;
pub extern fn agp_rendertarget_viewport(tgt: ?*struct_agp_rendertarget, x1: isize, y1: isize, x2: isize, y2: isize) void;
pub extern fn agp_shader_addgroup(shid: agp_shader_id) agp_shader_id;
pub extern fn agp_shader_build(tag: [*c]const u8, geom: [*c]const u8, vert: [*c]const u8, frag: [*c]const u8) agp_shader_id;
pub extern fn agp_shader_destroy(shid: agp_shader_id) bool;
pub extern fn agp_shader_language() [*c]const u8;
pub extern fn agp_shader_lookup(tag: [*c]const u8) agp_shader_id;

// TUI
pub extern fn arcan_tui_cursorpos(ctx: ?*tui_context, x: *usize, y: *usize) void;
pub extern fn arcan_tui_cursor_style(ctx: ?*tui_context, fl: c_int, col: ?*const u8) c_int;
pub extern fn arcan_tui_defattr(ctx: ?*tui_context, attr: ?*tui_screen_attr) tui_screen_attr;
pub extern fn arcan_tui_dimensions(ctx: ?*tui_context, rows: *usize, cols: *usize) void;
pub extern fn arcan_tui_erase_region(ctx: ?*tui_context, x1: usize, y1: usize, x2: usize, y2: usize, prot: bool) void;
pub extern fn arcan_tui_getxy(ctx: ?*tui_context, x: usize, y: usize, resolve: bool) tui_cell;
pub extern fn arcan_tui_move_to(ctx: ?*tui_context, x: usize, y: usize) void;
pub extern fn arcan_tui_set_flags(ctx: ?*tui_context, flags: c_int) void;
pub extern fn arcan_tui_setup(conn: ?*arcan_shmif_cont, parent: ?*tui_context, cbs: *const tui_cbcfg, sz: usize) ?*tui_context;
pub extern fn arcan_tui_ucs4utf8(cp: u32, dst: [*c]u8) usize;
pub extern fn arcan_tui_wndhint(ctx: ?*tui_context, parent: ?*tui_context, cons: tui_constraints) void;
pub extern fn arcan_tui_writeu8(ctx: ?*tui_context, data: [*c]const u8, len: usize, attr: *const tui_screen_attr) bool;

// Math helpers
pub extern fn add_vector(a: vector, b: vector) vector;
pub extern fn crossp_vector(a: vector, b: vector) vector;
pub extern fn mul_vectorf(a: vector, f: f32) vector;
pub extern fn norm_vector(v: vector) vector;
pub extern fn taitbryan_forwardv(roll: f32, pitch: f32, yaw: f32) vector;

// Vid helper
pub extern fn luavid_tovid(val: lua_Number) arcan_vobj_id;

// ══════════════════════════════════════════════════════════════════════════════
// Section 7: Libc functions (extern fn — stubs needed on freestanding)
// ══════════════════════════════════════════════════════════════════════════════

pub extern fn malloc(size: usize) ?*anyopaque;
pub extern fn free(ptr: ?*anyopaque) void;
pub extern fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
pub extern fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;
pub extern fn memset(s: ?*anyopaque, c_val: c_int, n: usize) ?*anyopaque;
pub extern fn strlen(s: [*c]const u8) usize;
pub extern fn strcmp(s1: [*c]const u8, s2: [*c]const u8) c_int;
pub extern fn strncmp(s1: [*c]const u8, s2: [*c]const u8, n: usize) c_int;
pub extern fn strcat(dest: [*c]u8, src: [*c]const u8) [*c]u8;
pub extern fn strrchr(s: [*c]const u8, c_val: c_int) [*c]u8;
pub extern fn strstr(haystack: [*c]const u8, needle: [*c]const u8) [*c]u8;
pub extern fn strerror(errnum: c_int) [*c]u8;
pub extern fn snprintf(buf: [*c]u8, size: usize, fmt: [*c]const u8, ...) c_int;
pub extern fn sprintf(buf: [*c]u8, fmt: [*c]const u8, ...) c_int;
pub extern fn asprintf(strp: *[*c]u8, fmt: [*c]const u8, ...) c_int;
pub extern fn fprintf(stream: ?*FILE, fmt: [*c]const u8, ...) c_int;
pub extern fn fopen(path: [*c]const u8, mode: [*c]const u8) ?*FILE;
pub extern fn fclose(stream: ?*FILE) c_int;
pub extern fn fdopen(fd: c_int, mode: [*c]const u8) ?*FILE;
pub extern fn fflush(stream: ?*FILE) c_int;
pub extern fn fwrite(ptr: ?*const anyopaque, size: usize, nmemb: usize, stream: ?*FILE) usize;
pub extern fn fputc(c_val: c_int, stream: ?*FILE) c_int;
pub extern fn fputs(s: [*c]const u8, stream: ?*FILE) c_int;
pub extern fn open(path: [*c]const u8, flags: c_int, ...) c_int;
pub extern fn close(fd: c_int) c_int;
pub extern fn dup(fd: c_int) c_int;
pub extern fn read(fd: c_int, buf: ?*anyopaque, count: usize) isize;
pub extern fn write(fd: c_int, buf: ?*const anyopaque, count: usize) isize;
pub extern fn unlink(path: [*c]const u8) c_int;
pub extern fn pipe(fds: [*c]c_int) c_int;
pub extern fn poll(fds: [*c]struct_pollfd, nfds: c_ulong, timeout: c_int) c_int;
pub extern fn isalnum(c_val: c_int) c_int;
pub extern fn isspace(c_val: c_int) c_int;
pub extern fn modff(val: f32, iptr: *f32) f32;
pub extern fn time(t: ?*c_long) c_long;
pub extern fn localtime(timer: *const c_long) ?*anyopaque;
pub extern fn strftime(s: [*c]u8, max: usize, fmt: [*c]const u8, tm: ?*const anyopaque) usize;
pub extern fn setenv(name: [*c]const u8, value: [*c]const u8, overwrite: c_int) c_int;
pub extern fn unsetenv(name: [*c]const u8) c_int;
pub extern fn atexit(func: ?*const fn () callconv(.c) void) c_int;
pub extern fn dlopen(filename: [*c]const u8, flags: c_int) ?*anyopaque;
pub extern fn dlsym(handle: ?*anyopaque, symbol: [*c]const u8) ?*anyopaque;
pub extern fn dlclose(handle: ?*anyopaque) c_int;
pub extern fn dlerror() [*c]u8;
pub extern fn waitpid(pid: pid_t, status: ?*c_int, options: c_int) pid_t;
// windows: route to the substrate's consistent asm setjmp/longjmp pair so the
// lua-recovery longjmp (monitor/support/arcan_lua call these via `c.`) matches
// arcan_main's arcan_setjmp. libc's setjmp/longjmp are SEH/incompatible. (windows port)
extern fn arcan_setjmp(env: [*c]jmp_buf) c_int;
extern fn arcan_longjmp(env: [*c]jmp_buf, val: c_int) noreturn;
extern fn _setjmp_libc(env: [*c]jmp_buf) c_int;
extern fn longjmp_libc(env: [*c]jmp_buf, val: c_int) void;
pub const _setjmp = if (builtin.os.tag == .windows) arcan_setjmp else struct {
    extern fn _setjmp(env: [*c]jmp_buf) c_int;
}._setjmp;
pub const longjmp = if (builtin.os.tag == .windows) arcan_longjmp else struct {
    extern fn longjmp(env: [*c]jmp_buf, val: c_int) void;
}.longjmp;
pub extern fn pthread_attr_init(attr: *pthread_attr_t) c_int;
pub extern fn pthread_attr_setdetachstate(attr: *pthread_attr_t, state: c_int) c_int;
pub extern fn _errno() *c_int;
pub extern fn __errno_location() *c_int;

pub extern fn sigaction(sig: c_int, act: ?*const struct_sigaction, oact: ?*struct_sigaction) c_int;

pub fn WIFEXITED(status: c_int) bool {
    return (@as(c_uint, @bitCast(status)) & 0x7f) == 0;
}

// ══════════════════════════════════════════════════════════════════════════════
// Section 8: Additional Lua API, libc, engine functions
// (needed by alt/support.zig, alt/trace.zig, arcan_monitor.zig)
// ══════════════════════════════════════════════════════════════════════════════

// Additional Lua API
pub extern fn lua_pushfstring(L: ?*lua_State, fmt: [*c]const u8, ...) [*c]const u8;
pub extern fn lua_pushliteral_helper(L: ?*lua_State, s: [*c]const u8, len: usize) void;
pub extern fn lua_atpanic(L: ?*lua_State, f: lua_CFunction) lua_CFunction;
// Lua 5.4 signature (5 args); our pure-Zig lua54 port declares the same.
// The arcan C tree historically used the 5.1 4-arg form, so this decl
// now mirrors 5.4 and callers must pass a `mode` argument. Pass `null`
// for the default "bt" (both text and binary). The 4-arg call left the
// mode as uninitialized stack/register garbage, tripping `checkmode`
// with `attempt to load a text chunk (mode is '')`.
pub extern fn lua_load(L: ?*lua_State, reader: ?*const fn (?*lua_State, ?*anyopaque, *usize) callconv(.c) [*c]const u8, dt: ?*anyopaque, chunkname: [*c]const u8, mode: [*c]const u8) c_int;
pub extern fn lua_typename(L: ?*lua_State, tp: c_int) [*c]const u8;
pub extern fn lua_rawequal(L: ?*lua_State, idx1: c_int, idx2: c_int) c_int;
pub extern fn lua_getlocal(L: ?*lua_State, ar: ?*anyopaque, n: c_int) [*c]const u8;
pub extern fn lua_getmetatable(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_isstring(L: ?*lua_State, idx: c_int) c_int;
pub extern fn lua_gc(L: ?*lua_State, what: c_int, data: c_int) c_int;

// Additional arcan engine functions
pub extern fn arcan_state_dump(tag: [*c]const u8, msg: [*c]const u8, src: [*c]const u8) void;
pub extern fn arcan_monitor_watchdog_error(L: ?*lua_State, mode: c_int, enter: bool) ?*FILE;
pub extern fn arcan_monitor_masktrigger(L: ?*lua_State) void;
pub extern fn vid_toluavid(innum: arcan_vobj_id) lua_Number;
pub extern fn arcan_conductor_toggle_watchdog() void;
pub extern fn arcan_trace_log(msg: [*c]const u8, len: usize) void;
pub extern fn arcan_lua_crash_source(ctx: ?*anyopaque) [*c]const u8;
pub extern fn arcan_lua_default_errorhook(L: ?*lua_State) void;
pub extern fn arcan_conductor_frameserver_known(fsrv: ?*anyopaque) bool;
pub extern fn arcan_monitor_external(cmd: [*c]u8, fifo_path: [*c]u8, input: *?*FILE) bool;
pub extern fn arcan_monitor_configure(srate: c_int, dst: [*c]const u8, ctrl: ?*FILE) bool;

// Additional alt/trace functions
pub extern fn alt_trace_callstack_raw(L: ?*lua_State, D: ?*anyopaque, levels: c_int, out: ?*FILE) void;
pub extern fn alt_trace_dumpstack_raw(L: ?*lua_State, out: ?*FILE) void;
pub extern fn alt_trace_callstack(L: ?*lua_State, out: ?*FILE) void;
pub extern fn alt_trace_dumptable_raw(L: ?*lua_State, ofs: c_int, cap: c_int, out: ?*FILE) void;
pub extern fn alt_trace_print_type(L: ?*lua_State, i: c_int, suffix: [*c]const u8, out: ?*FILE) void;
pub extern fn alt_trace_strtoep(ep: [*c]const u8) u64;
pub extern fn alt_trace_hookmask(mask: u64, bkpt: bool) void;
pub extern fn alt_trace_cbstate(kind: *u64, luavid: *i64, vid: *i64) void;

// Additional libc functions
pub extern fn vfprintf(stream: ?*FILE, fmt: [*c]const u8, args: *anyopaque) c_int;
pub extern fn open_memstream(bufp: *[*c]u8, sizep: *usize) ?*FILE;
pub extern fn getc(stream: ?*FILE) c_int;
pub extern fn ungetc(ch: c_int, stream: ?*FILE) c_int;
pub extern fn feof(stream: ?*FILE) c_int;
pub extern fn fread(ptr: [*c]u8, size: usize, nmemb: usize, stream: ?*FILE) usize;
pub extern fn ferror(stream: ?*FILE) c_int;
pub extern fn fgets(buf: [*c]u8, size: c_int, stream: ?*FILE) [*c]u8;
pub extern fn setlinebuf(stream: ?*FILE) void;
pub extern fn fileno(stream: ?*FILE) c_int;
pub extern fn getpid() c_int;
pub extern fn exit(status: c_int) noreturn;
pub extern fn mkfifo(pathname: [*c]const u8, mode: c_uint) c_int;
pub extern fn strcasecmp(s1: [*c]const u8, s2: [*c]const u8) c_int;
pub extern fn strtoul(nptr: [*c]const u8, endptr: ?*[*c]u8, base: c_int) c_ulong;
pub extern fn strtol(nptr: [*c]const u8, endptr: ?*[*c]u8, base: c_int) c_long;
pub extern fn strtok_r(str: [*c]u8, delim: [*c]const u8, saveptr: *[*c]u8) [*c]u8;
pub extern fn fcntl(fd: c_int, cmd: c_int, ...) c_int;

// Extern variables
pub extern var stderr: ?*FILE;
pub extern var stdin: ?*FILE;
pub extern var stdout: ?*FILE;
pub extern var arcanmain_recover_state: anyopaque;
pub extern var main_lua_context: ?*anyopaque;
pub extern var main_lua_signalled: c_int;
pub extern var arcan_trace_enabled: bool;

