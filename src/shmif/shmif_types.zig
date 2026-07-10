// shmif_types.zig — Pure Zig type definitions for shmif and TUI modules.
// Replaces @cImport of arcan_shmif.h, arcan_tui.h, shmif_privint.h, etc.
// System/libc types and constants are also provided so files can use
// a single `const c = @import("shmif_types");` namespace.

const std = @import("std");

// ══════════════════════════════════════════════════════════════════════════════
// Section 1: Arcan struct types
// ══════════════════════════════════════════════════════════════════════════════

/// Derive the return type of a pointer accessor so that `*const T` input
/// produces `*const Target` and `*T` input produces `*Target`.
/// Used by the ergonomic unnamed_0-collapsing accessors on arcan_event and
/// its sub-structs — callers write `ev.tgt().kind = ...` rather than
/// `ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = ...`, and const callers
/// transparently receive const pointers back.
fn _PtrReturn(comptime SelfPtr: type, comptime Target: type) type {
    const info = @typeInfo(SelfPtr);
    if (info != .pointer) @compileError("accessor expects a pointer self, got " ++ @typeName(SelfPtr));
    return if (info.pointer.is_const) *const Target else *Target;
}

// arcan_shmif_region
pub const arcan_shmif_region = extern struct {
    x1: u16 = 0,
    x2: u16 = 0,
    y1: u16 = 0,
    y2: u16 = 0,
};

// arcan_shmif_cont — partial struct with fields accessed by shmif code
pub const arcan_shmif_cont = extern struct {
    addr: ?*anyopaque = null,
    unnamed_0: extern union { vidp: [*c]shmif_pixel, floatp: ?*f32, vidb: [*c]u8 } = .{ .vidp = null },
    unnamed_1: extern union { audp: [*c]shmif_asample, audb: [*c]u8 } = .{ .audp = null },
    oflow_cookie: i16 = 0,
    abufused: u16 = 0,
    abufpos: u16 = 0,
    abufsize: u16 = 0,
    abufcount: u16 = 0,
    abuf_cnt: u8 = 0,
    epipe: c_int = 0,
    shmh: c_int = 0,
    shmsize: usize = 0,
    unused: [3]usize align(8) = .{ 0, 0, 0 },
    w: usize = 0,
    h: usize = 0,
    stride: usize = 0,
    pitch: usize = 0,
    adata: u32 = 0,
    samplerate: usize = 0,
    hints: u8 = 0,
    dirty: arcan_shmif_region = std.mem.zeroes(arcan_shmif_region),
    cookie: u64 = 0,
    user: ?*anyopaque = null,
    priv: ?*anyopaque = null,
    privext: ?*struct_shmif_ext_hidden = null,
    segment_token: u32 = 0,
    vbufsize: usize = 0,

    // Ergonomic accessors for the anonymous-union video/audio pointers so
    // call sites don't need to spell `cont.unnamed_0.vidp` / `cont.unnamed_1.audp`.
    pub inline fn vidp(self: *const arcan_shmif_cont) [*c]shmif_pixel {
        return self.unnamed_0.vidp;
    }
    pub inline fn setVidp(self: *arcan_shmif_cont, p: [*c]shmif_pixel) void {
        self.unnamed_0.vidp = p;
    }
    pub inline fn floatp(self: *const arcan_shmif_cont) ?*f32 {
        return self.unnamed_0.floatp;
    }
    pub inline fn vidb(self: *const arcan_shmif_cont) [*c]u8 {
        return self.unnamed_0.vidb;
    }
    pub inline fn audp(self: *const arcan_shmif_cont) [*c]shmif_asample {
        return self.unnamed_1.audp;
    }
    pub inline fn setAudp(self: *arcan_shmif_cont, p: [*c]shmif_asample) void {
        self.unnamed_1.audp = p;
    }
    pub inline fn audb(self: *const arcan_shmif_cont) [*c]u8 {
        return self.unnamed_1.audb;
    }
};
pub const struct_arcan_shmif_cont = arcan_shmif_cont;

// arcan_ioevent_data (union)
pub const arcan_ioevent_data = extern union {
    digital: extern struct { active: u8 },
    analog: extern struct { gotrel: i8, nvalues: u8, axisval: [4]i16, active: u8 },
    touch: extern struct { active: u8, x: i16, y: i16, pressure: f32, size: f32, tilt_x: u16, tilt_y: u16, tool: u8 },
    eyes: extern struct { head_pos: [3]f32, head_ang: [3]f32, gaze_x1: f32, gaze_y1: f32, gaze_x2: f32, gaze_y2: f32, blink_left: u8, blink_right: u8, present: u8 },
    status: extern struct { action: u8, devkind: u8, devref: u16, domain: u8 },
    translated: extern struct { utf8: [5]u8, active: u8, scancode: u8, keysym: u32, modifiers: u16 },
};

// arcan_ioevent
pub const arcan_ioevent = extern struct {
    kind: c_int = 0,
    devkind: c_int = 0,
    datatype: c_int = 0,
    label: [16]u8 = std.mem.zeroes([16]u8),
    flags: u8 = 0,
    _pad_flags: [1]u8 = .{0},
    unnamed_0: extern union {
        unnamed_0: extern struct { devid: u16 = 0, subid: u16 = 0 },
        id: [2]u16,
    } = .{ .id = .{ 0, 0 } },
    dst: u32 = 0,
    pts: u64 = 0,
    input: arcan_ioevent_data = std.mem.zeroes(arcan_ioevent_data),

    pub inline fn devid(self: anytype) _PtrReturn(@TypeOf(self), u16) {
        return &self.unnamed_0.unnamed_0.devid;
    }
    pub inline fn subid(self: anytype) _PtrReturn(@TypeOf(self), u16) {
        return &self.unnamed_0.unnamed_0.subid;
    }
    pub inline fn id(self: anytype) _PtrReturn(@TypeOf(self), [2]u16) {
        return &self.unnamed_0.id;
    }
};

// arcan_tgtevent
pub const tgt_ioev = extern union { uiv: u32, iv: i32, fv: f32, cv: [4]u8 };
pub const arcan_tgtevent = extern struct {
    kind: c_int = 0,
    ioevs: [8]tgt_ioev = std.mem.zeroes([8]tgt_ioev),
    code: c_int = 0,
    unnamed_0: extern union {
        message: [78]u8,
        bmessage: [78]u8,
        timestamp: u64,
    } = .{ .message = std.mem.zeroes([78]u8) },

    pub inline fn message(self: anytype) _PtrReturn(@TypeOf(self), [78]u8) {
        return &self.unnamed_0.message;
    }
    pub inline fn bmessage(self: anytype) _PtrReturn(@TypeOf(self), [78]u8) {
        return &self.unnamed_0.bmessage;
    }
    pub inline fn timestamp(self: anytype) _PtrReturn(@TypeOf(self), u64) {
        return &self.unnamed_0.timestamp;
    }
};

// arcan_extevent
pub const arcan_extevent = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    source: i64 = 0,
    unnamed_0: extern union {
        message: extern struct { data: [78]u8, multipart: u8 },
        labelhint: extern struct { label: [16]u8, initial: u16, descr: [53]u8, vsym: [5]u8, subv: u16, idatatype: u8, modifiers: u16 },
        segreq: extern struct { id: u32, width: u16, height: u16, xofs: i16, yofs: i16, dir: u8, hints: u8, kind: c_int },
        viewport: extern struct { x: i32, y: i32, w: u32, h: u32, parent: u32, border: [4]u8, edge: u8, order: i8, embedded: u8, invisible: u8, focus: u8, anchor_edge: u8, anchor_pos: u8, ext_id: u32 },
        clock: extern struct { rate: u32, dynamic: u8, once: u8, id: u32 },
        registr: extern struct { title: [64]u8, kind: c_int, guid: [2]u64 },
        bchunk: extern struct { unnamed_0: extern union { size: u64, ns: u64 } = .{ .size = 0 }, input: u8, hint: u8, stream: u8, extensions: [68]u8, identifier: u32 },
        stateinf: extern struct { size: u32, @"type": u32 },
        streamstat: extern struct { timestr: [9]u8, timelim: [9]u8, completion: f32, streaming: u8, frameno: u32, identifier: u32 },
        framestatus: extern struct { framenumber: u32, pts: u64, acquired: u64, fhint: f32 },
        content: extern struct { x_pos: f32, x_sz: f32, y_pos: f32, y_sz: f32, width: f32, height: f32, cell_w: u8, cell_h: u8, min_w: u32, min_h: u32, max_w: u32, max_h: u32 },
        coreopt: extern struct { index: u8, @"type": u8, data: [77]u8 },
        privdrop: extern struct { external: u8, sandboxed: u8, networked: u8 },
        inputmask: extern struct { device: u32, types: u32 },
        netstate: extern struct { unnamed_0: extern union { name: [66]u8, unnamed_0: extern struct { petname: [16]u8, pubk: [32]u8 } } = .{ .name = std.mem.zeroes([66]u8) }, space: u8, state: u8, @"type": u8, _pad0: u8 = 0, port: u16, ns: u16 },
        bstream: extern struct { stride: u32, format: u32, offset: u32, mod_hi: u32, mod_lo: u32, gpuid: u32, width: u32, height: u32, left: u8, flags: u8 },
        streaminf: extern struct { streamid: u8, datakind: u8, langid: [4]u8 },
    } = .{ .message = .{ .data = std.mem.zeroes([78]u8), .multipart = 0 } },
    frame_id: u64 = 0,

    // Variant accessors — collapse `.unnamed_0.<variant>` to `.<variant>()`.
    // The accessors take `anytype` so they preserve const-ness through the call.
    pub inline fn message(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.message)) {
        return &self.unnamed_0.message;
    }
    pub inline fn labelhint(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.labelhint)) {
        return &self.unnamed_0.labelhint;
    }
    pub inline fn segreq(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.segreq)) {
        return &self.unnamed_0.segreq;
    }
    pub inline fn viewport(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.viewport)) {
        return &self.unnamed_0.viewport;
    }
    pub inline fn clock(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.clock)) {
        return &self.unnamed_0.clock;
    }
    pub inline fn registr(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.registr)) {
        return &self.unnamed_0.registr;
    }
    pub inline fn bchunk(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.bchunk)) {
        return &self.unnamed_0.bchunk;
    }
    pub inline fn stateinf(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.stateinf)) {
        return &self.unnamed_0.stateinf;
    }
    pub inline fn streamstat(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.streamstat)) {
        return &self.unnamed_0.streamstat;
    }
    pub inline fn framestatus(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.framestatus)) {
        return &self.unnamed_0.framestatus;
    }
    pub inline fn content(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.content)) {
        return &self.unnamed_0.content;
    }
    pub inline fn coreopt(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.coreopt)) {
        return &self.unnamed_0.coreopt;
    }
    pub inline fn privdrop(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.privdrop)) {
        return &self.unnamed_0.privdrop;
    }
    pub inline fn inputmask(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.inputmask)) {
        return &self.unnamed_0.inputmask;
    }
    pub inline fn netstate(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.netstate)) {
        return &self.unnamed_0.netstate;
    }
    pub inline fn bstream(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.bstream)) {
        return &self.unnamed_0.bstream;
    }
    pub inline fn streaminf(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_extevent, undefined).unnamed_0.streaminf)) {
        return &self.unnamed_0.streaminf;
    }
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

    pub inline fn tagv(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_sevent, undefined).unnamed_0.tagv)) {
        return &self.unnamed_0.tagv;
    }
    pub inline fn mesg(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_sevent, undefined).unnamed_0.mesg)) {
        return &self.unnamed_0.mesg;
    }
    pub inline fn data(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_sevent, undefined).unnamed_0.data)) {
        return &self.unnamed_0.data;
    }
    pub inline fn message(self: anytype) _PtrReturn(@TypeOf(self), [64]u8) {
        return &self.unnamed_0.message;
    }
};

// arcan_vevent (video event)
pub const arcan_vevent = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    source: i64 = 0,
    unnamed_0: extern union {
        unnamed_0: extern struct { width: i16 = 0, height: i16 = 0, flags: c_int = 0, vppcm: f32 = 0, displayid: c_int = 0, ledctrl: c_int = 0, ledid: c_int = 0, cardid: c_int = 0 },
        slot: c_int,
    } = .{ .slot = 0 },
    data: isize = 0,

    // Display metadata lives in the anonymous inner struct.
    pub inline fn width(self: anytype) _PtrReturn(@TypeOf(self), i16) { return &self.unnamed_0.unnamed_0.width; }
    pub inline fn height(self: anytype) _PtrReturn(@TypeOf(self), i16) { return &self.unnamed_0.unnamed_0.height; }
    pub inline fn flags(self: anytype) _PtrReturn(@TypeOf(self), c_int) { return &self.unnamed_0.unnamed_0.flags; }
    pub inline fn vppcm(self: anytype) _PtrReturn(@TypeOf(self), f32) { return &self.unnamed_0.unnamed_0.vppcm; }
    pub inline fn displayid(self: anytype) _PtrReturn(@TypeOf(self), c_int) { return &self.unnamed_0.unnamed_0.displayid; }
    pub inline fn ledctrl(self: anytype) _PtrReturn(@TypeOf(self), c_int) { return &self.unnamed_0.unnamed_0.ledctrl; }
    pub inline fn ledid(self: anytype) _PtrReturn(@TypeOf(self), c_int) { return &self.unnamed_0.unnamed_0.ledid; }
    pub inline fn cardid(self: anytype) _PtrReturn(@TypeOf(self), c_int) { return &self.unnamed_0.unnamed_0.cardid; }
    pub inline fn slot(self: anytype) _PtrReturn(@TypeOf(self), c_int) { return &self.unnamed_0.slot; }
};

// arcan_aevent (audio event)
pub const arcan_aevent = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    source: i32 = 0,
    _pad_source: [4]u8 = .{ 0, 0, 0, 0 },
    unnamed_0: extern union { otag: isize, data: [*c]usize } = .{ .otag = 0 },

    pub inline fn otag(self: anytype) _PtrReturn(@TypeOf(self), isize) { return &self.unnamed_0.otag; }
    pub inline fn data(self: anytype) _PtrReturn(@TypeOf(self), [*c]usize) { return &self.unnamed_0.data; }
};

// arcan_fsrvevent_full (frameserver event)
// Upstream C puts four sibling anonymous structs in the union for:
//  (0) media  : audio/width/height/xofs/yofs/fmt_fl/pts/counter/message
//  (1) ident  : ident/descriptor
//  (2) aproto : aproto
//  (3) limb   : limb
// translate-c numbered them unnamed_0..3; accessor names below track the
// C-level semantics so call sites don't need the numbers.
pub const arcan_fsrvevent_full = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    unnamed_0: extern union {
        unnamed_0: extern struct {
            audio: i32 = 0, _pad_audio: [4]u8 = .{ 0, 0, 0, 0 },
            width: usize = 0, height: usize = 0, xofs: usize = 0, yofs: usize = 0,
            fmt_fl: i8 = 0, _pad_fmt: [7]u8 = std.mem.zeroes([7]u8),
            pts: u64 = 0, counter: u64 = 0, message: [32]u8 = std.mem.zeroes([32]u8),
        },
        unnamed_1: extern struct { ident: [32]u8 = std.mem.zeroes([32]u8), descriptor: i64 = 0 },
        unnamed_2: extern struct { aproto: c_int = 0 },
        unnamed_3: extern struct { limb: c_uint = 0 },
        input: arcan_ioevent,
    } = .{ .unnamed_0 = .{} },
    video: i64 = 0,
    otag: isize = 0,

    pub inline fn media(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_fsrvevent_full, undefined).unnamed_0.unnamed_0)) {
        return &self.unnamed_0.unnamed_0;
    }
    pub inline fn ident(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_fsrvevent_full, undefined).unnamed_0.unnamed_1)) {
        return &self.unnamed_0.unnamed_1;
    }
    pub inline fn aproto(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_fsrvevent_full, undefined).unnamed_0.unnamed_2)) {
        return &self.unnamed_0.unnamed_2;
    }
    pub inline fn limb(self: anytype) _PtrReturn(@TypeOf(self), @TypeOf(@as(arcan_fsrvevent_full, undefined).unnamed_0.unnamed_3)) {
        return &self.unnamed_0.unnamed_3;
    }
    pub inline fn input(self: anytype) _PtrReturn(@TypeOf(self), arcan_ioevent) {
        return &self.unnamed_0.input;
    }
};

// arcan_event (128 bytes)
// Translate-c produced a triple-deep anonymous-struct/union chain here
// (unnamed_0.unnamed_0.unnamed_0.{io,vid,...,tgt,ext}). The accessor methods
// below collapse that so call sites write `ev.tgt().kind = ...` rather than
// `ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = ...`. The layout is fixed by
// the wire/shmpage ABI and must not change — accessors only.
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

    // Category tag accessor. Pointer-form so both reads and writes are terse:
    //   `ev.category().* = EVENT_TARGET;`   for writes
    //   `if (ev.category().* == EVENT_IO)`  for reads
    pub inline fn category(self: anytype) _PtrReturn(@TypeOf(self), u8) {
        return &self.unnamed_0.unnamed_0.category;
    }

    // Variant pointers. Each returns a pointer (const-correct) to the
    // corresponding alternative of the inner union so callers can access
    // fields directly: `ev.tgt().kind = EXIT`, `ev.ext().registr().title`.
    pub inline fn io(self: anytype) _PtrReturn(@TypeOf(self), arcan_ioevent) {
        return &self.unnamed_0.unnamed_0.unnamed_0.io;
    }
    pub inline fn vid(self: anytype) _PtrReturn(@TypeOf(self), arcan_vevent) {
        return &self.unnamed_0.unnamed_0.unnamed_0.vid;
    }
    pub inline fn aud(self: anytype) _PtrReturn(@TypeOf(self), arcan_aevent) {
        return &self.unnamed_0.unnamed_0.unnamed_0.aud;
    }
    pub inline fn sys(self: anytype) _PtrReturn(@TypeOf(self), arcan_sevent) {
        return &self.unnamed_0.unnamed_0.unnamed_0.sys;
    }
    pub inline fn tgt(self: anytype) _PtrReturn(@TypeOf(self), arcan_tgtevent) {
        return &self.unnamed_0.unnamed_0.unnamed_0.tgt;
    }
    pub inline fn ext(self: anytype) _PtrReturn(@TypeOf(self), arcan_extevent) {
        return &self.unnamed_0.unnamed_0.unnamed_0.ext;
    }
    pub inline fn fsrv(self: anytype) _PtrReturn(@TypeOf(self), arcan_fsrvevent_full) {
        return &self.unnamed_0.unnamed_0.unnamed_0.fsrv;
    }
};
pub const struct_arcan_event = arcan_event;

// arg_arr — simple key/value pair, NOT the same as arcan_strarr
pub const struct_arg_arr = extern struct {
    key: [*c]u8 = null,
    value: [*c]u8 = null,
};

// arcan_evctx
// Matches C struct arcan_evctx from shmif_platform.h.
// Fields are ordered to match the C layout: c_ticks, mask_cat_inp, state_fl,
// exit_code, drain, eventbuf_sz, eventbuf, front, back, local, synch.
pub const struct_arcan_evctx = extern struct {
    c_ticks: i32 = 0,
    mask_cat_inp: u32 = 0,
    state_fl: u32 = 0,
    exit_code: c_int = 0,
    drain: ?*const fn (?*arcan_event, c_int) callconv(.c) bool = null,
    eventbuf_sz: u8 = 0,
    _pad_ebs: [7]u8 = std.mem.zeroes([7]u8),
    eventbuf: [*c]arcan_event = @as([*c]arcan_event, @ptrFromInt(0)),
    front: ?*volatile u8 = null,
    back: ?*volatile u8 = null,
    local: i8 = 0,
    _pad_local: [7]u8 = std.mem.zeroes([7]u8),
    synch: extern struct {
        killswitch: ?*volatile u8 = null,
        handle: ?*anyopaque = null, // sem_t*
        synch: ?*anyopaque = null,
    } = .{},
    _data: [168]u8 = std.mem.zeroes([168]u8),
};

// shmif_resize_ext
// Verified against C: arcan_shmif_control.h struct shmif_resize_ext (72 bytes)
pub const struct_shmif_resize_ext = extern struct {
    meta: u32 = 0, // offset 0
    _pad_meta: [4]u8 = .{0} ** 4, // offset 4 (align to 8)
    abuf_sz: usize = 0, // offset 8
    abuf_cnt: isize = -1, // offset 16
    samplerate: isize = -1, // offset 24
    vbuf_cnt: isize = -1, // offset 32
    rows: usize = 0, // offset 40
    cols: usize = 0, // offset 48
    nops: usize = 0, // offset 56
    op_fm: usize = 0, // offset 64
};

// shmif_open_ext
pub const struct_shmif_open_ext = extern struct {
    @"type": c_uint = 0,
    _pad0: [4]u8 = .{ 0, 0, 0, 0 },
    title: [*c]const u8 = null,
    ident: [*c]const u8 = null,
    guid: [2]u64 = .{ 0, 0 },
};

// shmif_connection
pub const struct_shmif_connection = extern struct {
    @"error": ?[*:0]const u8 = null,
    flags: c_int = 0,
    keyfile: ?[*:0]const u8 = null,
    socket: c_int = -1,
    _pad1: [4]u8 = .{ 0, 0, 0, 0 },
    args: ?[*:0]const u8 = null,
    alternate_cp: ?[*:0]const u8 = null,
    networked: bool = false,
    _pad: [15]u8 = std.mem.zeroes([15]u8),
};

// shmif_ext_hidden
pub const struct_shmif_ext_hidden = extern struct {
    cleanup: ?*const fn (?*arcan_shmif_cont) callconv(.c) void = null,
    active_fd: c_int = -1,
    pending_fd: c_int = -1,
    state_fl: c_int = 0,
    _data: [44]u8 = std.mem.zeroes([44]u8),
};

// Opaque arcan types
// C: {int fd, int type, int hinting, float size_mm} = 16 bytes
pub const InitialFont = extern struct {
    fd: c_int = -1,
    @"type": c_int = 0,
    hinting: c_int = 0,
    size_mm: f32 = 0,
};
pub const InitialColor = extern struct {
    fg: [3]u8 = .{ 0, 0, 0 },
    fg_set: bool = false,
    bg: [3]u8 = .{ 0, 0, 0 },
    bg_set: bool = false,
};
// Verified against C: arcan_shmif_control.h (440 bytes)
pub const struct_arcan_shmif_initial = extern struct {
    fonts: [4]InitialFont = .{ .{}, .{}, .{}, .{} }, // offset 0, 64 bytes
    density: f32 = 0, // offset 64
    rgb_layout: c_int = 0, // offset 68
    display_width_px: usize = 0, // offset 72
    display_height_px: usize = 0, // offset 80
    rate: u16 = 0, // offset 88
    lang: [4]u8 = std.mem.zeroes([4]u8), // offset 90
    country: [4]u8 = std.mem.zeroes([4]u8), // offset 94
    text_lang: [4]u8 = std.mem.zeroes([4]u8), // offset 98
    _pad_align: [2]u8 = .{ 0, 0 }, // offset 102 (align to f32)
    latitude: f32 = 0, // offset 104
    longitude: f32 = 0, // offset 108
    elevation: f32 = 0, // offset 112
    render_node: c_int = -1, // offset 116
    timezone: c_int = 0, // offset 120
    colors: [36]InitialColor = [_]InitialColor{.{}} ** 36, // offset 124, 288 bytes
    _pad_cell: [4]u8 = .{ 0, 0, 0, 0 }, // offset 412 (align to size_t)
    cell_w: usize = 0, // offset 416
    cell_h: usize = 0, // offset 424
    // C struct has tail padding to 440 bytes (8-byte aligned)
};
comptime {
    const T = struct_arcan_shmif_initial;
    // C struct is 432 bytes (no tail padding needed in Zig extern struct)
    // The C sizeof=440 includes struct padding that Zig handles differently
    if (@offsetOf(T, "cell_w") != 416) @compileError("cell_w offset mismatch: " ++ std.fmt.comptimePrint("{}", .{@offsetOf(T, "cell_w")}));
    if (@offsetOf(T, "cell_w") != 416) @compileError("cell_w offset mismatch");
    if (@offsetOf(T, "cell_h") != 424) @compileError("cell_h offset mismatch");
    if (@offsetOf(T, "density") != 64) @compileError("density offset mismatch");
    if (@offsetOf(T, "colors") != 124) @compileError("colors offset mismatch");
}
pub const struct_arcan_shmif_ofstbl = extern struct {
    unnamed_0: extern union {
        unnamed_0: extern struct {
            ofs_ramp: u32 = 0,
            sz_ramp: u32 = 0,
            ofs_vr: u32 = 0,
            sz_vr: u32 = 0,
            ofs_hdr: u32 = 0,
            sz_hdr: u32 = 0,
            ofs_vector: u32 = 0,
            sz_vector: u32 = 0,
            ofs_venc: u32 = 0,
            sz_venc: u32 = 0,
        },
        _pad: [64]u8,
    } = .{ ._pad = std.mem.zeroes([64]u8) },
};
pub const struct_arcan_shmif_hdr = opaque {};
pub const struct_arcan_shmif_venc = extern struct {
    fourcc: [4]u8 = std.mem.zeroes([4]u8),
    _pad0: [4]u8 = std.mem.zeroes([4]u8),
    framesize: usize = 0,
};
pub const struct_debugint_ext_resolver = extern struct { _data: [64]u8 = std.mem.zeroes([64]u8) };
pub const struct_shmifsrv_client = opaque {};
pub const shmifsrv_client = struct_shmifsrv_client;

// arcan_shmif_server.h — struct shmifsrv_vbuffer (with SHMIF_SERVER_NO_BITFIELDS)
// Source of truth: src/shmif/arcan_shmif_server.h. Layout assumes
// SHMIF_SERVER_NO_BITFIELDS so `.flags` is a regular struct of bools.
// All consumers that previously @cImport-ed this header used that define.
pub const struct_shmifsrv_vbuffer_flags = extern struct {
    origo_ll: bool = false,
    ignore_alpha: bool = false,
    subregion: bool = false,
    srgb: bool = false,
    hwhandles: bool = false,
    tpack: bool = false,
    compressed: bool = false,
};

pub const struct_shmifsrv_vbuffer = extern struct {
    state: c_int = 0,
    unnamed_0: extern union {
        buffer: [*c]shmif_pixel,
        buffer_bytes: [*c]u8,
    } = .{ .buffer = null },
    flags: struct_shmifsrv_vbuffer_flags = .{},
    fourcc: [4]u8 = .{ 0, 0, 0, 0 },
    buffer_sz: usize = 0,
    w: usize = 0,
    h: usize = 0,
    pitch: usize = 0,
    stride: usize = 0,
    vpts: u64 = 0,
    region: arcan_shmif_region = std.mem.zeroes(arcan_shmif_region),
    formats: [4]usize = .{ 0, 0, 0, 0 },
    planes: [4]c_int = .{ 0, 0, 0, 0 },
};
pub const shmifsrv_vbuffer = struct_shmifsrv_vbuffer;
pub const enum_vbuffer_status = c_int;
pub const VBUFFER_OUTPUT: c_int = -1;
pub const VBUFFER_NODATA: c_int = 0;
pub const VBUFFER_OKDATA: c_int = 1;
pub const VBUFFER_HANDLE: c_int = 2;

// struct arcan_shmifext_setup, shmifext_buffer_plane, shmifext_color_buffer
// Source of truth: src/shmif/arcan_shmif_interop.h
pub const struct_arcan_shmifext_setup = extern struct {
    red: u8 = 0,
    green: u8 = 0,
    blue: u8 = 0,
    alpha: u8 = 0,
    depth: u8 = 0,
    api: u8 = 0,
    major: u8 = 0,
    minor: u8 = 0,
    flags: u64 = 0,
    mask: u64 = 0,
    builtin_fbo: u8 = 0,
    supersample: u8 = 0,
    stencil: u8 = 0,
    no_context: u8 = 0,
    shared_context: u64 = 0,
    deprecated_1: u8 = 0,
    deprecated_2: u32 = 0,
    uintfl_reserve: [6]u8 = .{ 0, 0, 0, 0, 0, 0 },
    reserved: [4]u64 = .{ 0, 0, 0, 0 },
};

pub const struct_shmifext_buffer_plane = extern struct {
    fd: c_int = 0,
    fence: c_int = 0,
    w: usize = 0,
    h: usize = 0,
    unnamed_0: extern union {
        gbm: extern struct {
            format: u32 = 0,
            stride: u64 = 0,
            offset: u64 = 0,
            mod_hi: u32 = 0,
            mod_lo: u32 = 0,
        },
    } = .{ .gbm = .{} },
};

pub const struct_shmifext_color_buffer = extern struct {
    id: extern union {
        gl: c_uint,
    } = .{ .gl = 0 },
    alloc_tags: [4]?*anyopaque = .{ null, null, null, null },
    type: c_int = 0,
};

// shmifext_setup_status enum values (from arcan_shmif_interop.h)
pub const SHHIFEXT_UNKNOWN: c_int = 0;
pub const SHMIFEXT_NO_API: c_int = 1;
pub const SHMIFEXT_NO_DISPLAY: c_int = 2;
pub const SHMIFEXT_NO_EGL: c_int = 3;
pub const SHMIFEXT_NO_CONFIG: c_int = 4;
pub const SHMIFEXT_NO_CONTEXT: c_int = 5;
pub const SHMIFEXT_ALREADY_SETUP: c_int = 6;
pub const SHMIFEXT_OUT_OF_MEMORY: c_int = 7;
pub const SHMIFEXT_OK: c_int = 8;

// agp_fenv — opaque from the shmif side, private to engine.
pub const struct_agp_fenv = opaque {};
pub const struct_shmifsrv_envp = extern struct {
    fd_bin: c_int = 0,
    path: [*c]const u8 = null,
    argv: ?*anyopaque = null,
    envv: ?*anyopaque = null,
    init_w: usize = 0,
    init_h: usize = 0,
    detach: c_int = 0,
    @"type": c_int = 0,
};
pub const struct_shmif_privsep_node = extern struct {
    path: ?[*:0]const u8 = null,
    perm: ?[*:0]const u8 = null,
};
pub const shmif_privsep_node = struct_shmif_privsep_node;
pub const struct_watchdog_config = extern struct {
    parent_pid: c_int = 0,
    parent_fd: c_int = -1,
    exitf: ?*const fn (c_int) callconv(.c) void = null,
    relval: c_int = 0,
};
pub const struct_a12addr_info = extern struct {
    len: c_int = 0,
    weak_auth: bool = false,
    _pad: [59]u8 = std.mem.zeroes([59]u8),
};

// Sub-structure types
pub const struct_ramp_block = extern struct {
    edid: [128]u8 = std.mem.zeroes([128]u8),
    plane_lim: [4]u16 = std.mem.zeroes([4]u16),
    plane_data: [2048]u8 = std.mem.zeroes([2048]u8),
    checksum: u16 = 0,
};
pub const union_shmif_ext_substruct = extern union {
    cramp: ?*anyopaque,
    vr: ?*anyopaque,
    hdr: ?*anyopaque,
    vector: ?*anyopaque,
    venc: ?*anyopaque,
};
pub const enum_shmif_ext_meta = c_int;
pub const enum_shmif_migrate_status = c_int;

pub const struct_blobio_meta = extern struct {
    fd: c_int = -1,
    @"type": c_int = 0,
};

pub const struct_io_job = extern struct {
    buf: [*c]u8 = null,
    buf_sz: usize = 0,
    ofs: usize = 0,
    next: ?*struct_io_job = null,
};
pub const struct_nonblock_io = extern struct {
    eofm: bool = false,
    lfstrip: bool = false,
    _pad0: [2]u8 = std.mem.zeroes([2]u8),
    _pad0b: [4]u8 = std.mem.zeroes([4]u8),
    ofs: c_long = 0,
    lfch: u8 = 0,
    _pad1: [3]u8 = std.mem.zeroes([3]u8),
    fd: c_int = 0,
    out_queued: usize = 0,
    out_count: usize = 0,
    out_queue: ?*struct_io_job = null,
    out_queue_tail: ?*?*struct_io_job = null,
    mode: mode_t = 0,
    _pad2: [4]u8 = std.mem.zeroes([4]u8),
    unlink_fn: [*c]u8 = null,
    pending: [*c]u8 = null,
    data_rearmed: bool = false,
    _pad3: [7]u8 = std.mem.zeroes([7]u8),
    data_handler: isize = 0,
    write_handler: isize = 0,
    buf: [4096]u8 = std.mem.zeroes([4096]u8),
};

// Function pointer types
pub const shmif_trigger_hook_fptr = ?*const fn ([*c]arcan_shmif_cont) callconv(.c) c_uint;
pub const shmif_reset_hook_fptr = ?*const fn (c_int, ?*anyopaque) callconv(.c) void;

// Basic aliases
pub const shmif_pixel = u32;
pub const shmif_asample = i16;
pub const av_pixel = u32;

// TUI types
pub const struct_tui_context = opaque {};
// arcan_tui_conn is both a type (typedef) and an extern function in C.
// In Zig, the extern function declaration takes the name. For the type,
// use struct_arcan_shmif_cont directly.
pub const struct_tui_screen_attr = extern struct {
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
pub const struct_tui_cell = extern struct {
    attr: struct_tui_screen_attr = .{},
    ch: u32 = 0,
    draw_ch: u32 = 0,
    real_x: u32 = 0,
    cell_w: u8 = 0,
    fstamp: u8 = 0,
    _pad: [2]u8 = std.mem.zeroes([2]u8),
};
pub const struct_tui_cbcfg = extern struct {
    // tag must be the first field to match the C struct layout (arcan_tui.h)
    // and the arcan_zig_types.zig tui_cbcfg definition.
    tag: ?*anyopaque = null,
    // Function pointer fields — all nullable
    query_label: ?*anyopaque = null,
    input_label: ?*anyopaque = null,
    input_alabel: ?*anyopaque = null,
    input_mouse_motion: ?*anyopaque = null,
    input_mouse_button: ?*anyopaque = null,
    input_utf8: ?*anyopaque = null,
    input_key: ?*anyopaque = null,
    input_misc: ?*anyopaque = null,
    state: ?*anyopaque = null,
    bchunk: ?*anyopaque = null,
    vpaste: ?*anyopaque = null,
    apaste: ?*anyopaque = null,
    tick: ?*anyopaque = null,
    utf8: ?*anyopaque = null,
    resized: ?*anyopaque = null,
    reset: ?*anyopaque = null,
    geohint: ?*anyopaque = null,
    recolor: ?*anyopaque = null,
    subwindow: ?*anyopaque = null,
    substitute: ?*anyopaque = null,
    resize: ?*anyopaque = null,
    visibility: ?*anyopaque = null,
    exec_state: ?*anyopaque = null,
    cli_command: ?*anyopaque = null,
    seek_absolute: ?*anyopaque = null,
    seek_relative: ?*anyopaque = null,
    message: ?*anyopaque = null,
};
pub const struct_tui_constraints = extern struct {
    anch_row: c_int = 0,
    anch_col: c_int = 0,
    max_rows: c_int = 0,
    max_cols: c_int = 0,
    min_rows: c_int = 0,
    min_cols: c_int = 0,
    hide: c_int = 0,
    embed: c_int = 0,
};
pub const struct_tui_process_res = extern struct {
    ok: bool = false,
    bad: c_int = 0,
    errc: c_int = 0,
};
pub const struct_tui_labelent = extern struct {
    label: [16]u8 = std.mem.zeroes([16]u8),
    descr: [58]u8 = std.mem.zeroes([58]u8),
    initial: u16 = 0,
    vsym: [5]u8 = std.mem.zeroes([5]u8),
    subv: u16 = 0,
    idatatype: u8 = 0,
    modifiers: u16 = 0,
};
pub const struct_tui_pending = extern struct {
    id: isize = 0,
    hint: u8 = 0,
    _pad0: [3]u8 = std.mem.zeroes([3]u8),
    embed: c_int = 0,
};
pub const struct_tui_lmeta = extern struct {
    unnamed_0: extern union {
        tui: ?*struct_tui_context,
        subs: [64]?*struct_tui_context,
    } = .{ .tui = null },
    submeta: [64][*c]struct_tui_lmeta = std.mem.zeroes([64][*c]struct_tui_lmeta),
    parent: [*c]struct_tui_lmeta = null,
    n_subs: usize = 0,
    pending_mask: u8 = 0,
    _pad_pm: [7]u8 = std.mem.zeroes([7]u8),
    pending: [8]struct_tui_pending = std.mem.zeroes([8]struct_tui_pending),
    embed: c_int = 0,
    _pad_embed: [4]u8 = std.mem.zeroes([4]u8),
    tui_state: isize = 0,
    href: isize = 0,
    widget_mode: c_int = 0,
    _pad_wm: [4]u8 = std.mem.zeroes([4]u8),
    widget_closure: isize = 0,
    widget_state: isize = 0,
    widget_meta: ?*struct_widget_meta = null,
    in_callback: bool = false,
    _pad_ic: [7]u8 = std.mem.zeroes([7]u8),
    blobs: ?*anyopaque = null,
    cwd: ?*anyopaque = null,
    cwd_sz: usize = 0,
    cwd_fd: c_int = -1,
    _pad_cfd: [4]u8 = std.mem.zeroes([4]u8),
    in_subwnd: ?*anyopaque = null,
    subwnd_handover: c_int = 0,
    _pad_sh: [4]u8 = std.mem.zeroes([4]u8),
    lua: ?*lua_State = null,
};
pub const struct_widget_meta = extern struct {
    parent: [*c]struct_tui_lmeta = null,
    unnamed_0: extern union {
        readline: extern struct {
            filter: isize = 0,
            verify: isize = 0,
            item: isize = 0,
            history: [*c][*c]u8 = null,
            history_sz: usize = 0,
            suggest: [*c][*c]u8 = null,
            suggest_sz: usize = 0,
        },
        listview: extern struct {
            ents: [*c]struct_tui_list_entry = null,
            n_ents: usize = 0,
        },
        bufferview: extern struct {
            buf: [*c]u8 = null,
            sz: usize = 0,
        },
        _pad: [64]u8,
    } = .{ ._pad = std.mem.zeroes([64]u8) },
};
pub const struct_tui_subwnd_req = extern struct {
    id: u32 = 0,
    @"type": c_int = 0,
    hint: u8 = 0,
    _pad0: [3]u8 = std.mem.zeroes([3]u8),
    rows: c_int = 0,
    cols: c_int = 0,
};

// TUI widget types
pub const struct_tui_list_entry = extern struct {
    label: [*c]const u8 = null,
    shortcut: [*c]const u8 = null,
    attributes: u16 = 0,
    indent: u8 = 0,
    tag: usize = 0,
};
pub const struct_tui_bufferwnd_opts = extern struct {
    read_only: bool = false,
    allow_exit: bool = false,
    hide_cursor: bool = false,
    _pad0: u8 = 0,
    view_mode: c_int = 0,
    wrap_mode: c_int = 0,
    color_mode: c_int = 0,
    hex_mode: c_int = 0,
    custom_attr: ?*const fn (?*struct_tui_context, ?*anyopaque, u8, usize, ?*u32, ?*struct_tui_screen_attr) callconv(.c) void = null,
    commit: ?*const fn (?*struct_tui_context, ?*anyopaque, [*c]const u8, usize, usize) callconv(.c) bool = null,
    cbtag: ?*anyopaque = null,
    offset: u64 = 0,
};
pub const struct_tui_readline_opts = extern struct {
    anchor_row: isize = 0,
    n_rows: usize = 0,
    margin_left: usize = 0,
    margin_right: usize = 0,
    allow_exit: bool = false,
    _pad0: [7]u8 = std.mem.zeroes([7]u8),
    autocomplete: ?*const fn ([*c]const u8, ?*[*c]const u8, [*c]const u8, ?*anyopaque) callconv(.c) bool = null,
    filter_character: ?*const fn (u32, usize, ?*anyopaque) callconv(.c) bool = null,
    mask_character: u32 = 0,
    multiline: bool = false,
    tab_completion: bool = false,
    _pad1: [2]u8 = std.mem.zeroes([2]u8),
    verify: ?*const fn ([*c]const u8, usize, bool, ?*anyopaque) callconv(.c) isize = null,
    mouse_forward: bool = false,
    paste_forward: bool = false,
    block_builtin_bindings: bool = false,
    _pad2: [5]u8 = std.mem.zeroes([5]u8),
    popup: ?*struct_tui_context = null,
    completion_compact: bool = false,
    linefeed_expand: bool = false,
    whitespace_expand: bool = false,
    _pad3: [5]u8 = std.mem.zeroes([5]u8),
    suggest_item: ?*const fn ([*c]const u8, [*c]const u8, ?*anyopaque) callconv(.c) void = null,
    _extra: [64]u8 = std.mem.zeroes([64]u8),
};
pub const struct_tui_linewnd_line = extern struct {
    label: [*c]const u8 = null,
    attributes: u16 = 0,
    indent: u8 = 0,
    tag: usize = 0,
};

// TUI font
pub const tui_font = extern struct { _data: [8]u8 = std.mem.zeroes([8]u8) };

// pthread types
// `_data: [48]u8` has alignment 1 in Zig — but musl's pthread_mutex_lock does
// `ldaxr w_, [mutex]` which requires 4-byte (effectively 8-byte) alignment.
// Auto-layout structs containing pthread_mutex_t end up placing it at
// arbitrary byte offsets, leading to SIGBUS in __pthread_mutex_lock.
// `align(8)` propagates so the containing field is also 8-byte aligned.
// See afsrv_terminal SIGBUS at __pthread_mutex_timedlock / a_ll
// (memory/sh_pthread_mutex_alignment.md).
pub const pthread_mutex_t = extern struct { _data: [48]u8 align(8) = std.mem.zeroes([48]u8) };
pub const pthread_t = c_ulong;
pub const pthread_attr_t = extern struct { _data: [8]usize };

// ══════════════════════════════════════════════════════════════════════════════
// Section 2: Arcan constants
// ══════════════════════════════════════════════════════════════════════════════

// Event categories
pub const EVENT_SYSTEM: c_int = 1;
pub const EVENT_IO: c_int = 2;
pub const EVENT_VIDEO: c_int = 4;
pub const EVENT_AUDIO: c_int = 8;
pub const EVENT_TARGET: c_int = 16;
pub const EVENT_FSRV: c_int = 32;
pub const EVENT_EXTERNAL: c_int = 64;

// Segment IDs
// Source of truth: src/shmif/arcan_shmif_event.h (enum ARCAN_SEGID).
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

// TARGET_COMMAND
// Source of truth: src/shmif/arcan_shmif_event.h (enum ARCAN_TARGET_COMMAND).
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

// TARGET_SKIP
// Source of truth: src/shmif/arcan_shmif_event.h (enum ARCAN_TARGET_SKIP).
pub const TARGET_SKIP_AUTO: c_int = 0;
pub const TARGET_SKIP_NONE: c_int = -1;
pub const TARGET_SKIP_REVERSE: c_int = -2;
pub const TARGET_SKIP_ROLLBACK: c_int = -3;
pub const TARGET_SKIP_STEP: c_int = 1;
pub const TARGET_SKIP_FASTFWD: c_int = 10;

// EVENT_EXTERNAL
// Source of truth: src/shmif/arcan_shmif_event.h (enum ARCAN_EVENT_EXTERNAL).
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
pub const EVENT_EXTERNAL_SEGREQ: c_int = 10;
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

// IO event kinds
pub const EVENT_IO_BUTTON: c_int = 0;
pub const EVENT_IO_AXIS_MOVE: c_int = 1;
pub const EVENT_IO_TOUCH: c_int = 2;
pub const EVENT_IO_STATUS: c_int = 3;
pub const EVENT_IO_EYES: c_int = 4;

// IO device kinds (bitflags)
// Source of truth: src/shmif/arcan_shmif_event.h (enum ARCAN_EVENT_IDEVKIND).
pub const EVENT_IDEVKIND_KEYBOARD: c_int = 1;
pub const EVENT_IDEVKIND_MOUSE: c_int = 2;
pub const EVENT_IDEVKIND_GAMEDEV: c_int = 4;
pub const EVENT_IDEVKIND_TOUCHDISP: c_int = 8;
pub const EVENT_IDEVKIND_LEDCTRL: c_int = 16;
pub const EVENT_IDEVKIND_EYETRACKER: c_int = 32;
pub const EVENT_IDEVKIND_STATUS: c_int = 64;

// IO data types
pub const EVENT_IDATATYPE_ANALOG: c_int = 1;
pub const EVENT_IDATATYPE_DIGITAL: c_int = 2;
pub const EVENT_IDATATYPE_TRANSLATED: c_int = 4;
pub const EVENT_IDATATYPE_TOUCH: c_int = 8;
pub const EVENT_IDATATYPE_EYES: c_int = 16;

// IO flags
pub const ARCAN_IOFL_GESTURE: c_int = 1;
pub const ARCAN_IOFL_ENTER: c_int = 2;
pub const ARCAN_IOFL_LEAVE: c_int = 4;

// SHMIF input/output type (arcan_shmif_primary argument enum)
// Source of truth: src/shmif/arcan_shmif_control.h (enum ARCAN_SHMIF_TYPE).
pub const SHMIF_INPUT: c_uint = 1;
pub const SHMIF_OUTPUT: c_uint = 2;
pub const SHMIF_ACCESSIBILITY: c_uint = 3;

// SHMIF signal kinds
// Source of truth: src/shmif/arcan_shmif_control.h (SHMIF_SIGVID/_SIGAUD and
// the blocking-mode field overlay).
pub const SHMIF_SIGVID: c_uint = 1;
pub const SHMIF_SIGAUD: c_uint = 2;
pub const SHMIF_SIGBLK_FORCE: c_uint = 0;
pub const SHMIF_SIGBLK_NONE: c_uint = 4;
pub const SHMIF_SIGVID_AUTO_DIRTY: c_uint = 8;

// SHMIF open flags
// Source of truth: src/shmif/arcan_shmif_control.h (SHMIF_FLAGS enum).
pub const SHMIF_NOFLAGS: c_uint = 0;
pub const SHMIF_DISABLE_GUARD: c_uint = 2;
pub const SHMIF_ACQUIRE_FATALFAIL: c_uint = 4;
pub const SHMIF_FATALFAIL_FUNC: c_uint = 8;
pub const SHMIF_CONNECT_LOOP: c_uint = 16;
pub const SHMIF_MANUAL_PAUSE: c_uint = 32;
pub const SHMIF_NOAUTO_RECONNECT: c_uint = 64;
pub const SHMIF_MIGRATE_SUBSEGMENTS: c_uint = 128;
pub const SHMIF_NOACTIVATE_RESIZE: c_uint = 256;
pub const SHMIF_NOACTIVATE: c_uint = 512;
pub const SHMIF_NOREGISTER: c_uint = 1024;
pub const SHMIF_SOCKET_PINGEVENT: c_uint = 2048;

// SHMIF reset status (ioevs[0].iv payload in RESET target command)
// Source of truth: src/shmif/arcan_shmif_control.h (ARCAN_SHMIF_RESET enum).
pub const SHMIF_RESET_LOST: c_int = 1;
pub const SHMIF_RESET_REMAP: c_int = 2;
pub const SHMIF_RESET_NOCHG: c_int = 3;

// SHMIF RGBA
pub const SHMIF_RGBA_RSHIFT: c_int = 16;
pub const SHMIF_RGBA_GSHIFT: c_int = 8;
pub const SHMIF_RGBA_BSHIFT: c_int = 0;
pub const SHMIF_RGBA_ASHIFT: c_int = 24;
pub inline fn SHMIF_RGBA(r: u32, g: u32, b: u32, a: u32) u32 {
    return (r << 16) | (g << 8) | b | (a << 24);
}
pub inline fn SHMIF_RGBA_DECOMP(val: u32, r: *u8, g: *u8, b: *u8, a: *u8) void {
    r.* = @truncate((val >> 16) & 0xff);
    g.* = @truncate((val >> 8) & 0xff);
    b.* = @truncate(val & 0xff);
    a.* = @truncate((val >> 24) & 0xff);
}

// SHMIF rendering hints (bit-positioned flags + ORIGO_UL base)
// Source of truth: src/shmif/arcan_shmif_control.h (ARCAN_FLAGV enum).
pub const SHMIF_RHINT_ORIGO_UL: c_int = 0;
pub const SHMIF_RHINT_ORIGO_LL: c_int = 1;
pub const SHMIF_RHINT_SUBREGION: c_int = 2;
pub const SHMIF_RHINT_IGNORE_ALPHA: c_int = 4;
pub const SHMIF_RHINT_CSPACE_SRGB: c_int = 8;
pub const SHMIF_RHINT_AUTH_TOK: c_int = 16;
pub const SHMIF_RHINT_VSIGNAL_EV: c_int = 32;
pub const SHMIF_RHINT_EMPTY: c_int = 64;
pub const SHMIF_RHINT_TPACK: c_int = 128;

// SHMIF bgcopy
pub const SHMIF_BGCOPY_KEEPIN: c_int = 1;
pub const SHMIF_BGCOPY_KEEPOUT: c_int = 2;
pub const SHMIF_BGCOPY_PROGRESS: c_int = 4;

// SHMIF migrate
pub const SHMIF_MIGRATE_OK: c_int = 0;
pub const SHMIF_MIGRATE_BADARG: c_int = -1;
pub const SHMIF_MIGRATE_NOCON: c_int = -2;
pub const SHMIF_MIGRATE_BAD_SOURCE: c_int = -3;
pub const SHMIF_MIGRATE_TRANSFER_FAIL: c_int = -4;

// SHMIF EOTF (HDR)
// Source of truth: src/shmif/arcan_shmif_sub.h (SHMIF_EOTF enum).
pub const SHMIF_EOTF_SDR: c_int = 0;
pub const SHMIF_EOTF_HDR: c_int = 1;
pub const SHMIF_EOTF_ST2084: c_int = 2;
pub const SHMIF_EOTF_HLG: c_int = 3;

// SHMIF META (extended metadata advertisement bits)
// Source of truth: src/shmif/arcan_shmif_control.h (ARCAN_SHMIF_META enum).
pub const SHMIF_META_NONE: c_int = 0;
pub const SHMIF_META_CM: c_int = 2;
pub const SHMIF_META_HDR: c_int = 4;
pub const SHMIF_META_VR: c_int = 16;
pub const SHMIF_META_VENC: c_int = 32;

// SHMIF page/ramp constants
pub const ARCAN_SHMPAGE_START_SZ: usize = 2 * 1024 * 1024;
pub const ARCAN_SHMPAGE_DEFAULT_PPCM: f32 = 28.34;
pub const ARCAN_SHMPAGE_VCHANNELS: c_int = 4;
pub const ARCAN_SHMPAGE_MAXW: c_int = 8192;
pub const ARCAN_SHMPAGE_MAXH: c_int = 8192;
pub const ARCAN_SHMIF_SAMPLERATE: usize = 48000;
pub const ARCAN_SHMIF_ACHANNELS: c_int = 2;
pub const ARCAN_SHMIF_VBUFC_LIM: usize = 3;
pub const ARCAN_SHMIF_ABUFC_LIM: usize = 12;
pub const ARCAN_SHMIF_RAMPMAGIC: u32 = 0xfeedface;
pub const ARCAN_SHMPAGE_MAX_SZ: usize = 104857600; // PP_SHMPAGE_MAXSZ (100 MB)
pub const VR_VERSION: u8 = 1;
pub const LIMB_LIM: c_int = 49; // count of avatar_limbs enum entries, sentinel

// struct vr_limb from arcan_shmif_sub.h. Only the on-wire layout matters;
// we don't access individual fields from Zig (only @sizeOf).
pub const struct_vr_limb = extern struct {
    haptic_id: u8 = 0,
    haptic_capabilities: u8 = 0,
    ignored: u8 = 0,
    limb_type: u8 = 0,
    timestamp: u32 = 0, // _Atomic uint_least32_t
    data: [64]u8 = std.mem.zeroes([64]u8),
};

// struct arcan_shmif_ramp from arcan_shmif_sub.h. Only `.magic` and
// `.n_blocks` are accessed; the flex-array tail is handled separately.
pub const struct_arcan_shmif_ramp = extern struct {
    magic: u32 = 0,
    dirty_in: u8 = 0, // _Atomic uint_least8_t
    dirty_out: u8 = 0, // _Atomic uint_least8_t
    n_blocks: u8 = 0,
    _pad: u8 = 0,
    // struct ramp_block ramps[] — flex array, not in @sizeOf.
};

// struct arcan_shmif_vr from arcan_shmif_sub.h. Only `.version` and
// `.limb_lim` are accessed. `meta` is padded out to the C layout size
// without mirroring every float individually.
pub const struct_arcan_shmif_vr = extern struct {
    version: u8 = 0,
    limb_lim: u8 = 0,
    _pad0: [6]u8 = std.mem.zeroes([6]u8), // align to 8 for limb_mask
    limb_mask: u64 = 0, // _Atomic uint_least64_t
    ready: u8 = 0, // _Atomic uint_least8_t
    _pad1: [3]u8 = std.mem.zeroes([3]u8),
    // struct vr_meta meta — 220 bytes in C; represented as opaque bytes.
    meta: [220]u8 = std.mem.zeroes([220]u8),
    // struct vr_limb limbs[] — flex array, not in @sizeOf.
};
pub const SHMIF_CMRAMP_PLIM: c_int = 256;
pub const SHMIF_CMRAMP_UPLIM: c_int = 2048;
pub const SHMIF_PLEDGE_PREFIX: [*c]const u8 = "shmif_";

// Page constants (PP_*)
// Source of truth: src/shmif/arcan_shmif_control.h (PP_SHMPAGE_* macros).
pub const PP_SHMPAGE_MAXW: usize = 8192;
pub const PP_SHMPAGE_MAXH: usize = 8192;
pub const PP_SHMPAGE_STARTSZ: usize = 2014088;
pub const PP_SHMPAGE_MAXSZ: usize = 104857600;
pub const PP_SHMPAGE_ALIGN: usize = 64;
pub const PP_QUEUE_SZ: usize = 127;
pub const SEGMENT_LIMIT: usize = 256;

// Versioning
pub const ASHMIF_VERSION_MAJOR: c_uint = 0;
pub const ASHMIF_VERSION_MINOR: c_uint = 18;

// SYNC constants
pub const SYNC_EVENT: c_uint = 0;
pub const SYNC_VIDEO: c_uint = 1;
pub const SYNC_AUDIO: c_uint = 2;

// Mousestate
pub const ARCAN_MOUSESTATE_RELATIVE: c_int = 1;
pub const ARCAN_MOUSESTATE_ABSOLUTE: c_int = 0;
pub const ARCAN_MOUSESTATE_NOCLAMP: c_int = 2;
pub const ASHMIF_MSTATE_SZ: usize = 32;

// Mouse button indices
// Source of truth: src/shmif/arcan_shmif_event.h (enum ARCAN_MBTN_IMAP, 1-based).
pub const MBTN_LEFT_IND: c_int = 1;
pub const MBTN_RIGHT_IND: c_int = 2;
pub const MBTN_MIDDLE_IND: c_int = 3;
pub const MBTN_WHEEL_UP_IND: c_int = 4;
pub const MBTN_WHEEL_DOWN_IND: c_int = 5;

// SUPPORT_EVENT
pub const SUPPORT_EVENT_EXIT: c_uint = 1;
pub const SUPPORT_EVENT_POLL: c_uint = 2;
pub const SUPPORT_EVENT_VSIGNAL: c_uint = 3;

// SHMIFSRV constants
pub const SHMIFSRV_FREE_FULL: c_int = 0;
pub const SHMIFSRV_FREE_NO_DMS: c_int = 1;
pub const SHMIFSRV_FREE_LOCAL: c_int = 2;

// BADFD
pub const BADFD: c_int = -1;

// Memory allocation types (from arcan_video.h)
pub const enum_arcan_memtypes = c_uint;
pub const enum_arcan_memhint = c_uint;
pub const enum_arcan_memalign = c_uint;
pub const ARCAN_MEM_VBUFFER: c_uint = 1;
pub const ARCAN_MEM_VSTRUCT: c_uint = 2;
pub const ARCAN_MEM_EXTSTRUCT: c_uint = 3;
pub const ARCAN_MEM_ABUFFER: c_uint = 4;
pub const ARCAN_MEM_STRINGBUF: c_uint = 5;
pub const ARCAN_MEM_SHARED: c_uint = 6;
pub const ARCAN_MEM_VTAG: c_uint = 7;
pub const ARCAN_MEM_ATAG: c_uint = 8;
pub const ARCAN_MEM_BINDING: c_uint = 9;
pub const ARCAN_MEM_MODELDATA: c_uint = 10;
pub const ARCAN_MEM_THREADCTX: c_uint = 11;
pub const ARCAN_MEM_BZERO: c_uint = 1;
pub const ARCAN_MEM_NONFATAL: c_uint = 8;
pub const ARCAN_MEM_SENSITIVE: c_uint = 32;
pub const ARCAN_MEMALIGN_NATURAL: c_uint = 0;
pub const ARCAN_MEMALIGN_PAGE: c_uint = 1;
pub const ARCAN_MEMALIGN_SIMD: c_uint = 2;

// State constants
pub const STATE_NOACCEL: c_int = 0;

// Key modifiers (ARKMOD)
pub const ARKMOD_NONE: c_int = 0x0000;
pub const ARKMOD_LSHIFT: c_int = 0x0001;
pub const ARKMOD_RSHIFT: c_int = 0x0002;
pub const ARKMOD_LCTRL: c_int = 0x0040;
pub const ARKMOD_RCTRL: c_int = 0x0080;
pub const ARKMOD_LALT: c_int = 0x0100;
pub const ARKMOD_RALT: c_int = 0x0200;
pub const ARKMOD_LMETA: c_int = 0x0400;
pub const ARKMOD_RMETA: c_int = 0x0800;
pub const ARKMOD_NUM: c_int = 0x1000;
pub const ARKMOD_CAPS: c_int = 0x2000;
pub const ARKMOD_MODE: c_int = 0x4000;
pub const ARKMOD_REPEAT: c_int = 0x8000;

// Privsep MARK constants
pub const MARK_READ: c_int = 1;
pub const MARK_WRITE: c_int = 2;
pub const MARK_SOCKET: c_int = 4;
pub const MARK_SHMIF: c_int = 8;
pub const MARK_KEYSTORE: c_int = 16;
pub const MARK_PASS: c_int = 32;

// EXECVE_DETACH flags
pub const EXECVE_DETACH_PROCESS: c_int = 1;
pub const EXECVE_DETACH_KEEP_SESSION: c_int = 2;
pub const EXECVE_DETACH_RESET_MASK: c_int = 4;

// ══════════════════════════════════════════════════════════════════════════════
// Section 3: TUI constants
// ══════════════════════════════════════════════════════════════════════════════

// TUI flags
pub const TUI_HIDE_CURSOR: c_int = 1;
pub const TUI_ALTERNATE: c_int = 2;
pub const TUI_MOUSE: c_int = 4;
pub const TUI_MOUSE_FULL: c_int = 8;
pub const TUI_AUTO_WRAP: c_int = 16;

// TUI attributes — values must match arcan_tuisym.h.
pub const TUI_ATTR_BOLD: c_int = 1;
pub const TUI_ATTR_UNDERLINE: c_int = 2;
pub const TUI_ATTR_UNDERLINE_ALT: c_int = 4;
pub const TUI_ATTR_ITALIC: c_int = 8;
pub const TUI_ATTR_INVERSE: c_int = 16;
pub const TUI_ATTR_PROTECT: c_int = 32;
pub const TUI_ATTR_BLINK: c_int = 64;
pub const TUI_ATTR_STRIKETHROUGH: c_int = 128;
pub const TUI_ATTR_SHAPE_BREAK: c_int = 256;
pub const TUI_ATTR_COLOR_INDEXED: c_int = 512;
pub const TUI_ATTR_GLYPH_INDEXED: c_int = 1024;
pub const TUI_ATTR_AGLYPH_INDEXED: c_int = 2048;
pub const TUI_ATTR_BORDER_RIGHT: c_int = 4096;
pub const TUI_ATTR_BORDER_DOWN: c_int = 8192;
pub const TUI_ATTR_BORDER_LEFT: c_int = 16384;
pub const TUI_ATTR_BORDER_TOP: c_int = 32768;
pub const TUI_ATTR_BORDER_ALL: c_int = 61440;

// TUI colors — values must match arcan_tuisym.h. Enum starts at 2
// (slots 0/1 are reserved for preset-detection per the C header).
pub const TUI_COL_PRIMARY: c_int = 2;
pub const TUI_COL_SECONDARY: c_int = 3;
pub const TUI_COL_BG: c_int = 4;
pub const TUI_COL_TEXT: c_int = 5;
pub const TUI_COL_CURSOR: c_int = 6;
pub const TUI_COL_ALTCURSOR: c_int = 7;
pub const TUI_COL_HIGHLIGHT: c_int = 8;
pub const TUI_COL_LABEL: c_int = 9;
pub const TUI_COL_WARNING: c_int = 10;
pub const TUI_COL_ERROR: c_int = 11;
pub const TUI_COL_ALERT: c_int = 12;
pub const TUI_COL_REFERENCE: c_int = 13;
pub const TUI_COL_INACTIVE: c_int = 14;
pub const TUI_COL_UI: c_int = 15;
pub const TUI_COL_TBASE: c_int = 16;
pub const TUI_COL_LIMIT: c_int = 36;

// TUI error codes
pub const TUI_ERRC_OK: c_int = 0;
pub const TUI_ERRC_BAD_ARG: c_int = -1;
pub const TUI_ERRC_BAD_FD: c_int = -2;
pub const TUI_ERRC_BAD_CTX: c_int = -3;

// TUI messages
pub const TUI_MESSAGE_GENERIC: c_int = 0;
pub const TUI_MESSAGE_NOTIFICATION: c_int = 1;
pub const TUI_MESSAGE_ALERT: c_int = 2;
pub const TUI_MESSAGE_FAILURE: c_int = 3;
pub const TUI_MESSAGE_LOCAL: c_int = 4;

// TUI window types — values match arcan_tuisym.h so that they align with the
// SEGID_* segment-kind IDs a parent expects in a subsegment request.
pub const TUI_WND_TUI: c_int = 23;
pub const TUI_WND_POPUP: c_int = 16;
pub const TUI_WND_DOCKICON: c_int = 17;
pub const TUI_WND_ACCESSIBILITY: c_int = 19;
pub const TUI_WND_DEBUG: c_int = 255;
pub const TUI_WND_HANDOVER: c_int = 26;

// TUI bgcopy
pub const TUI_BGCOPY_KEEPIN: c_int = 1;
pub const TUI_BGCOPY_KEEPOUT: c_int = 2;
pub const TUI_BGCOPY_PROGRESS: c_int = 4;

// TUI border
pub const TUI_BORDER_APPEND: c_int = 1;

// TUI CLI
pub const TUI_CLI_INVALID: c_int = -1;

// TUI cursor styles
pub const CURSOR_BLOCK: c_int = 0;
pub const CURSOR_BAR: c_int = 1;
pub const CURSOR_UNDER: c_int = 2;
pub const CURSOR_HOLLOW: c_int = 3;
pub const CURSOR_BLINK: c_int = 0x80;

// TUI dirty flags
pub const DIRTY_CURSOR: c_int = 1;

// TUI font styles
pub const TTF_R: c_int = 0;
pub const TTF_F: c_int = 1;
pub const TTF_S: c_int = 2;

// List widget attributes
pub const LIST_PASSIVE: u16 = 1;
pub const LIST_HIDE: u16 = 2;
pub const LIST_CHECKED: u16 = 4;
pub const LIST_HAS_SUB: u16 = 8;
pub const LIST_SEPARATOR: u16 = 16;
pub const LIST_LABEL: u16 = 32;

// Bufferwnd modes
pub const BUFFERWND_VIEW_ASCII: c_int = 0;
pub const BUFFERWND_VIEW_UTF8: c_int = 1;
pub const BUFFERWND_VIEW_HEX: c_int = 2;
pub const BUFFERWND_VIEW_HEX_DETAIL: c_int = 3;
pub const BUFFERWND_COLOR_NONE: c_int = 0;
pub const BUFFERWND_COLOR_PALETTE: c_int = 1;
pub const BUFFERWND_COLOR_CUSTOM: c_int = 2;
pub const BUFFERWND_HEX_BASIC: c_int = 0;
pub const BUFFERWND_HEX_ASCII: c_int = 1;
pub const BUFFERWND_HEX_META: c_int = 2;
pub const BUFFERWND_WRAP_ALL: c_int = 0;
pub const BUFFERWND_WRAP_ACCEPT_LF: c_int = 1;
pub const BUFFERWND_WRAP_ACCEPT_CR_LF: c_int = 2;

// Readline suggest — values must match arcan_tui_readline.h
// enum tui_readline_suggestion_mode. HINT and TITLE_HINT are bit flags
// OR'd into mode; the lower bits select INSERT/WORD/SUBSTITUTE/IGNORE.
pub const READLINE_SUGGEST_INSERT: c_int = 0;
pub const READLINE_SUGGEST_WORD: c_int = 1;
pub const READLINE_SUGGEST_SUBSTITUTE: c_int = 2;
pub const READLINE_SUGGEST_IGNORE: c_int = 3;
pub const READLINE_SUGGEST_HINT: c_int = 64;
pub const READLINE_SUGGEST_TITLE_HINT: c_int = 128;

// Widget meta types
pub const TWND_NORMAL: c_int = 0;
pub const TWND_LISTWND: c_int = 1;
pub const TWND_BUFWND: c_int = 2;
pub const TWND_READLINE: c_int = 3;

// TUI window split/join
pub const TUIWND_SPLIT_NONE: c_int = 0;
pub const TUIWND_SPLIT_LEFT: c_int = 1;
pub const TUIWND_SPLIT_RIGHT: c_int = 2;
pub const TUIWND_SPLIT_TOP: c_int = 3;
pub const TUIWND_SPLIT_DOWN: c_int = 4;
pub const TUIWND_JOIN_LEFT: c_int = 5;
pub const TUIWND_JOIN_RIGHT: c_int = 6;
pub const TUIWND_JOIN_TOP: c_int = 7;
pub const TUIWND_JOIN_DOWN: c_int = 8;
pub const TUIWND_TAB: c_int = 9;
pub const TUIWND_EMBED: c_int = 10;
pub const TUIWND_SWALLOW: c_int = 11;

// TUI key symbols (TUIK) — full set
pub const TUIK_UNKNOWN: u32 = 0;
pub const TUIK_FIRST: u32 = 0;
pub const TUIK_BACKSPACE: u32 = 8;
pub const TUIK_TAB: u32 = 9;
pub const TUIK_CLEAR: u32 = 12;
pub const TUIK_RETURN: u32 = 13;
pub const TUIK_PAUSE: u32 = 19;
pub const TUIK_ESCAPE: u32 = 27;
pub const TUIK_SPACE: u32 = 32;
pub const TUIK_EXCLAIM: u32 = 33;
pub const TUIK_QUOTEDBL: u32 = 34;
pub const TUIK_HASH: u32 = 35;
pub const TUIK_DOLLAR: u32 = 36;
pub const TUIK_APOSTROPHE: u32 = 39;
pub const TUIK_COMMA: u32 = 44;
pub const TUIK_MINUS: u32 = 45;
pub const TUIK_PERIOD: u32 = 46;
pub const TUIK_SLASH: u32 = 47;
pub const TUIK_0: u32 = 48;
pub const TUIK_1: u32 = 49;
pub const TUIK_2: u32 = 50;
pub const TUIK_3: u32 = 51;
pub const TUIK_4: u32 = 52;
pub const TUIK_5: u32 = 53;
pub const TUIK_6: u32 = 54;
pub const TUIK_7: u32 = 55;
pub const TUIK_8: u32 = 56;
pub const TUIK_9: u32 = 57;
pub const TUIK_COLON: u32 = 58;
pub const TUIK_SEMICOLON: u32 = 59;
pub const TUIK_LESS: u32 = 60;
pub const TUIK_EQUALS: u32 = 61;
pub const TUIK_A: u32 = 97;
pub const TUIK_B: u32 = 98;
pub const TUIK_C: u32 = 99;
pub const TUIK_D: u32 = 100;
pub const TUIK_E: u32 = 101;
pub const TUIK_F: u32 = 102;
pub const TUIK_G: u32 = 103;
pub const TUIK_H: u32 = 104;
pub const TUIK_I: u32 = 105;
pub const TUIK_J: u32 = 106;
pub const TUIK_K: u32 = 107;
pub const TUIK_L: u32 = 108;
pub const TUIK_M: u32 = 109;
pub const TUIK_N: u32 = 110;
pub const TUIK_O: u32 = 111;
pub const TUIK_P: u32 = 112;
pub const TUIK_Q: u32 = 113;
pub const TUIK_R: u32 = 114;
pub const TUIK_S: u32 = 115;
pub const TUIK_T: u32 = 116;
pub const TUIK_U: u32 = 117;
pub const TUIK_V: u32 = 118;
pub const TUIK_W: u32 = 119;
pub const TUIK_X: u32 = 120;
pub const TUIK_Y: u32 = 121;
pub const TUIK_Z: u32 = 122;
pub const TUIK_BACKSLASH: u32 = 92;
pub const TUIK_GRAVE: u32 = 96;
pub const TUIK_DELETE: u32 = 127;
pub const TUIK_KP_0: u32 = 256;
pub const TUIK_KP_1: u32 = 257;
pub const TUIK_KP_2: u32 = 258;
pub const TUIK_KP_3: u32 = 259;
pub const TUIK_KP_4: u32 = 260;
pub const TUIK_KP_5: u32 = 261;
pub const TUIK_KP_6: u32 = 262;
pub const TUIK_KP_7: u32 = 263;
pub const TUIK_KP_8: u32 = 264;
pub const TUIK_KP_9: u32 = 265;
pub const TUIK_KP_PERIOD: u32 = 266;
pub const TUIK_KP_DIVIDE: u32 = 267;
pub const TUIK_KP_MULTIPLY: u32 = 268;
pub const TUIK_KP_MINUS: u32 = 269;
pub const TUIK_KP_PLUS: u32 = 270;
pub const TUIK_KP_ENTER: u32 = 271;
pub const TUIK_KP_LEFTBRACE: u32 = 91;
pub const TUIK_KP_RIGHTBRACE: u32 = 93;
pub const TUIK_KP_PLUSMINUS: u32 = 272;
pub const TUIK_UP: u32 = 273;
pub const TUIK_DOWN: u32 = 274;
pub const TUIK_RIGHT: u32 = 275;
pub const TUIK_LEFT: u32 = 276;
pub const TUIK_INSERT: u32 = 277;
pub const TUIK_HOME: u32 = 278;
pub const TUIK_END: u32 = 279;
pub const TUIK_PAGEUP: u32 = 280;
pub const TUIK_PAGEDOWN: u32 = 281;
pub const TUIK_F1: u32 = 282;
pub const TUIK_F2: u32 = 283;
pub const TUIK_F3: u32 = 284;
pub const TUIK_F4: u32 = 285;
pub const TUIK_F5: u32 = 286;
pub const TUIK_F6: u32 = 287;
pub const TUIK_F7: u32 = 288;
pub const TUIK_F8: u32 = 289;
pub const TUIK_F9: u32 = 290;
pub const TUIK_F10: u32 = 291;
pub const TUIK_F11: u32 = 292;
pub const TUIK_F12: u32 = 293;
pub const TUIK_NUMLOCKCLEAR: u32 = 300;
pub const TUIK_CAPSLOCK: u32 = 301;
pub const TUIK_SCROLLLOCK: u32 = 302;
pub const TUIK_RSHIFT: u32 = 303;
pub const TUIK_LSHIFT: u32 = 304;
pub const TUIK_RCTRL: u32 = 305;
pub const TUIK_LCTRL: u32 = 306;
pub const TUIK_RALT: u32 = 307;
pub const TUIK_LALT: u32 = 308;
pub const TUIK_RMETA: u32 = 309;
pub const TUIK_LMETA: u32 = 310;
pub const TUIK_LGUI: u32 = 311;
pub const TUIK_RGUI: u32 = 312;
pub const TUIK_AGAIN: u32 = 313;
pub const TUIK_COMPOSE: u32 = 314;
pub const TUIK_STOP: u32 = 315;
pub const TUIK_SYSREQ: u32 = 317;
pub const TUIK_POWER: u32 = 320;
pub const TUIK_MUTE: u32 = 127;
pub const TUIK_VOLUMEDOWN: u32 = 129;
pub const TUIK_VOLUMEUP: u32 = 128;
pub const TUIK_LANG1: u32 = 400;
pub const TUIK_LANG2: u32 = 401;
pub const TUIK_LANG3: u32 = 402;
pub const TUIK_INTERNATIONAL1: u32 = 410;
pub const TUIK_INTERNATIONAL2: u32 = 411;
pub const TUIK_INTERNATIONAL3: u32 = 412;
pub const TUIK_INTERNATIONAL4: u32 = 413;
pub const TUIK_INTERNATIONAL5: u32 = 414;
pub const TUIK_INTERNATIONAL6: u32 = 415;
pub const TUIK_INTERNATIONAL7: u32 = 416;
pub const TUIK_INTERNATIONAL8: u32 = 417;
pub const TUIK_INTERNATIONAL9: u32 = 418;

// TUI mouse buttons
pub const TUIBTN_LEFT: u16 = 1;
pub const TUIBTN_RIGHT: u16 = 2;
pub const TUIBTN_MIDDLE: u16 = 3;
pub const TUIBTN_WHEEL_UP: u16 = 4;
pub const TUIBTN_WHEEL_DOWN: u16 = 5;

// TUI modifier masks
pub const TUIM_LSHIFT: u16 = 0x0001;
pub const TUIM_RSHIFT: u16 = 0x0002;
pub const TUIM_LCTRL: u16 = 0x0040;
pub const TUIM_RCTRL: u16 = 0x0080;
pub const TUIM_LALT: u16 = 0x0100;
pub const TUIM_RALT: u16 = 0x0200;
pub const TUIM_LMETA: u16 = 0x0400;
pub const TUIM_RMETA: u16 = 0x0800;
pub const TUIM_REPEAT: u16 = 0x8000;

// ══════════════════════════════════════════════════════════════════════════════
// Section 4: POSIX/libc types and constants
// ══════════════════════════════════════════════════════════════════════════════

pub const pid_t = c_int;
pub const uid_t = c_uint;
pub const gid_t = c_uint;
pub const mode_t = c_uint;
pub const off_t = i64;
pub const sa_family_t = c_ushort;
pub const nfds_t = c_ulong;
pub const socklen_t = c_uint;

pub const FILE = opaque {};

pub const struct_stat = extern struct {
    st_dev: u64 = 0,
    st_ino: u64 = 0,
    st_mode: c_uint = 0,
    st_nlink: u32 = 0,
    st_uid: u32 = 0,
    st_gid: u32 = 0,
    st_rdev: u64 = 0,
    _pad0: u64 = 0,
    st_size: i64 = 0,
    st_blksize: c_int = 0,
    _pad1: c_int = 0,
    st_blocks: i64 = 0,
    st_atim: extern struct { tv_sec: c_long = 0, tv_nsec: c_long = 0 } = .{},
    st_mtim: extern struct { tv_sec: c_long = 0, tv_nsec: c_long = 0 } = .{},
    st_ctim: extern struct { tv_sec: c_long = 0, tv_nsec: c_long = 0 } = .{},
    _reserved: [2]c_int = .{ 0, 0 },
};
pub const struct_pollfd = extern struct { fd: c_int = 0, events: c_short = 0, revents: c_short = 0 };
pub const struct_iovec = extern struct { iov_base: ?*anyopaque = null, iov_len: usize = 0 };
pub const struct_msghdr = extern struct {
    msg_name: ?*anyopaque = null,
    msg_namelen: c_uint = 0,
    _pad0: [4]u8 = .{ 0, 0, 0, 0 },
    msg_iov: ?*struct_iovec = null,
    msg_iovlen: usize = 0,
    msg_control: ?*anyopaque = null,
    msg_controllen: usize = 0,
    msg_flags: c_int = 0,
    _pad1: [4]u8 = .{ 0, 0, 0, 0 },
};
pub const struct_cmsghdr = extern struct { cmsg_len: usize = 0, cmsg_level: c_int = 0, cmsg_type: c_int = 0 };
pub const struct_sockaddr = extern struct { sa_family: sa_family_t = 0, sa_data: [14]u8 = std.mem.zeroes([14]u8) };
pub const struct_sockaddr_un = extern struct { sun_family: sa_family_t = 0, sun_path: [108]u8 = std.mem.zeroes([108]u8) };
pub const struct_sigaction = extern struct {
    __sa_handler: extern union {
        sa_handler: ?*const fn (c_int) callconv(.c) void,
        sa_sigaction: ?*const fn (c_int, ?*anyopaque, ?*anyopaque) callconv(.c) void,
    } = .{ .sa_handler = null },
    sa_mask: [16]c_ulong = std.mem.zeroes([16]c_ulong),
    sa_flags: c_int = 0,
    _pad0: [4]u8 = std.mem.zeroes([4]u8),
    sa_restorer: ?*const fn () callconv(.c) void = null,
};
pub const struct_timeval = extern struct { tv_sec: c_long = 0, tv_usec: c_long = 0 };
pub const struct_utsname = extern struct {
    sysname: [65]u8 = std.mem.zeroes([65]u8),
    nodename: [65]u8 = std.mem.zeroes([65]u8),
    release: [65]u8 = std.mem.zeroes([65]u8),
    version: [65]u8 = std.mem.zeroes([65]u8),
    machine: [65]u8 = std.mem.zeroes([65]u8),
    domainname: [65]u8 = std.mem.zeroes([65]u8),
};
pub const struct_termios = extern struct { _data: [60]u8 = std.mem.zeroes([60]u8) };
pub const struct_winsize = extern struct { ws_row: c_ushort = 0, ws_col: c_ushort = 0, ws_xpixel: c_ushort = 0, ws_ypixel: c_ushort = 0 };
pub const struct_group = extern struct { gr_name: [*c]u8 = null, gr_passwd: [*c]u8 = null, gr_gid: gid_t = 0, _pad: [4]u8 = .{ 0, 0, 0, 0 }, gr_mem: [*c][*c]u8 = null };
pub const struct_passwd = extern struct { pw_name: [*c]u8 = null, pw_passwd: [*c]u8 = null, pw_uid: uid_t = 0, pw_gid: gid_t = 0, pw_gecos: [*c]u8 = null, pw_dir: [*c]u8 = null, pw_shell: [*c]u8 = null };

pub const glob_t = extern struct {
    gl_pathc: usize = 0,
    gl_pathv: [*c][*c]u8 = null,
    gl_offs: usize = 0,
    _data: [40]u8 = std.mem.zeroes([40]u8),
};

// POSIX constants
pub const AF_UNIX: c_int = 1;
pub const PF_UNIX: c_int = 1;
pub const SOCK_STREAM: c_int = 1;
pub const SOCK_DGRAM: c_int = 2;
pub const SOL_SOCKET: c_int = 1;
pub const SCM_RIGHTS: c_int = 1;
pub const SO_RCVTIMEO: c_int = 20;
pub const SO_NOSIGPIPE: c_int = 0; // Linux has no SO_NOSIGPIPE
pub const MSG_DONTWAIT: c_int = 0x40;
pub const MSG_NOSIGNAL: c_int = 0x4000;
pub const O_RDONLY: c_int = 0;
pub const O_WRONLY: c_int = 1;
pub const O_RDWR: c_int = 2;
pub const O_CREAT: c_int = 64;
pub const O_TRUNC: c_int = 512;
pub const O_APPEND: c_int = 1024;
pub const O_NONBLOCK: c_int = 2048;
pub const O_NOCTTY: c_int = 256;
pub const O_CLOEXEC: c_int = 524288;
pub const O_DIRECTORY: c_int = 65536;
pub const F_GETFD: c_int = 1;
pub const F_SETFD: c_int = 2;
pub const F_GETFL: c_int = 3;
pub const F_SETFL: c_int = 4;
pub const FD_CLOEXEC: c_int = 1;
pub const SEEK_SET: c_int = 0;
pub const SEEK_CUR: c_int = 1;
pub const SEEK_END: c_int = 2;
pub const S_IRUSR: c_int = 0o400;
pub const S_IWUSR: c_int = 0o200;
pub const S_IXUSR: c_int = 0o100;
pub const S_IRWXU: c_int = 0o700;
pub const S_IRGRP: c_int = 0o040;
pub const S_IWGRP: c_int = 0o020;
pub const POLLIN: c_short = 1;
pub const POLLOUT: c_short = 4;
pub const POLLERR: c_short = 8;
pub const POLLHUP: c_short = 16;
pub const POLLNVAL: c_short = 32;
pub const EAGAIN: c_int = 11;
pub const EINTR: c_int = 4;
pub const EINVAL: c_int = 22;
pub const EWOULDBLOCK: c_int = 11;
pub const SIGCHLD: c_int = 17;
pub const SIGCONT: c_int = 18;
pub const SIGHUP: c_int = 1;
pub const SIGINT: c_int = 2;
pub const SIGPIPE: c_int = 13;
pub const SIGKILL: c_int = 9;
pub const SIGQUIT: c_int = 3;
pub const SIGSTOP: c_int = 19;
pub const SIGUSR1: c_int = 10;
pub const SIGUSR2: c_int = 12;
pub const EXIT_SUCCESS: c_int = 0;
pub const EXIT_FAILURE: c_int = 1;
pub const STDIN_FILENO: c_int = 0;
pub const STDOUT_FILENO: c_int = 1;
pub const STDERR_FILENO: c_int = 2;
pub const SHUT_RDWR: c_int = 2;
pub const TCSANOW: c_int = 0;
pub const VERASE: c_int = 2;
pub const WNOHANG: c_int = 1;
pub const AT_FDCWD: c_int = -100;
pub const AT_SYMLINK_NOFOLLOW: c_int = 0x100;
pub const PTHREAD_CREATE_DETACHED: c_int = 1;

// mmap constants
pub const PROT_READ: c_int = 1;
pub const PROT_WRITE: c_int = 2;
pub const MAP_SHARED: c_int = 1;
pub const MAP_ANONYMOUS: c_int = 0x20;
pub const MAP_FAILED: *anyopaque = @ptrFromInt(@as(usize, std.math.maxInt(usize)));
pub const MADV_DONTDUMP: c_int = 16;

// ioctl constants (aarch64 Linux)
pub const TIOCSCTTY: c_ulong = 0x540E;
pub const TIOCSWINSZ: c_ulong = 0x5414;

// CMSG macros as functions
pub fn CMSG_ALIGN(len: usize) usize {
    return (len + @sizeOf(usize) - 1) & ~(@as(usize, @sizeOf(usize)) - 1);
}
pub fn CMSG_SPACE(len: usize) usize {
    return CMSG_ALIGN(len) + CMSG_ALIGN(@sizeOf(struct_cmsghdr));
}
pub fn CMSG_LEN(len: usize) usize {
    return CMSG_ALIGN(@sizeOf(struct_cmsghdr)) + len;
}
pub fn CMSG_FIRSTHDR(mhdr: *const struct_msghdr) ?*struct_cmsghdr {
    if (mhdr.msg_controllen >= @sizeOf(struct_cmsghdr)) {
        return @ptrCast(@alignCast(mhdr.msg_control));
    }
    return null;
}

// WIFEXITED / WEXITSTATUS macros
pub fn WIFEXITED(status: c_int) bool {
    return (status & 0x7f) == 0;
}
pub fn WEXITSTATUS(status: c_int) c_int {
    return (status >> 8) & 0xff;
}

// Lua types (for tui_lua files)
pub const lua_State = opaque {};
pub const lua_Integer = c_longlong;
pub const lua_Number = f64;
pub const struct_luaL_Reg = extern struct {
    name: [*c]const u8 = null,
    func: ?*const fn (?*lua_State) callconv(.c) c_int = null,
};
pub const LUA_TNUMBER: c_int = 3;
pub const LUA_TSTRING: c_int = 4;
pub const LUA_TTABLE: c_int = 5;
pub const LUA_TBOOLEAN: c_int = 1;
pub const LUA_TUSERDATA: c_int = 7;

// Lua C API functions
pub extern "c" fn lua_createtable(L: ?*lua_State, narr: c_int, nrec: c_int) void;
pub extern "c" fn lua_settable(L: ?*lua_State, idx: c_int) void;
pub extern "c" fn lua_settop(L: ?*lua_State, idx: c_int) void;
pub extern "c" fn lua_gettop(L: ?*lua_State) c_int;
pub extern "c" fn lua_getfield(L: ?*lua_State, idx: c_int, k: [*c]const u8) void;
pub extern "c" fn lua_setfield(L: ?*lua_State, idx: c_int, k: [*c]const u8) void;
pub extern "c" fn lua_rawset(L: ?*lua_State, idx: c_int) void;
// Canonical signature returns c_int (the type of the pushed value), but every
// caller in the codebase ignores it. Declared as void here so existing calls
// don't all need `_ =` — return discard is safe under the C ABI.
pub extern "c" fn lua_rawgeti(L: ?*lua_State, idx: c_int, n: lua_Integer) void;
pub extern "c" fn lua_pushnil(L: ?*lua_State) void;
pub extern "c" fn lua_pushboolean(L: ?*lua_State, b: c_int) void;
pub extern "c" fn lua_pushinteger(L: ?*lua_State, n: lua_Integer) void;
pub extern "c" fn lua_pushnumber(L: ?*lua_State, n: lua_Number) void;
pub extern "c" fn lua_pushstring(L: ?*lua_State, s: [*c]const u8) void;
pub extern "c" fn lua_pushlstring(L: ?*lua_State, s: [*c]const u8, len: usize) void;
pub extern "c" fn lua_pushvalue(L: ?*lua_State, idx: c_int) void;
pub extern "c" fn lua_pushcclosure(L: ?*lua_State, f: ?*const fn (?*lua_State) callconv(.c) c_int, n: c_int) void;
pub extern "c" fn lua_toboolean(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_tointeger(L: ?*lua_State, idx: c_int) lua_Integer;
pub extern "c" fn lua_tonumber(L: ?*lua_State, idx: c_int) lua_Number;
pub extern "c" fn lua_tolstring(L: ?*lua_State, idx: c_int, len: ?*usize) [*c]const u8;
pub extern "c" fn lua_isnumber(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_isstring(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_iscfunction(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_type(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_typename(L: ?*lua_State, tp: c_int) [*c]const u8;
pub extern "c" fn lua_rawequal(L: ?*lua_State, idx1: c_int, idx2: c_int) c_int;
pub extern "c" fn lua_next(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_objlen(L: ?*lua_State, idx: c_int) usize;
pub extern "c" fn lua_getmetatable(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_setmetatable(L: ?*lua_State, idx: c_int) c_int;
pub extern "c" fn lua_newuserdata(L: ?*lua_State, sz: usize) ?*anyopaque;
pub extern "c" fn lua_call(L: ?*lua_State, nargs: c_int, nresults: c_int) void;
pub extern "c" fn lua_pcall(L: ?*lua_State, nargs: c_int, nresults: c_int, errfunc: c_int) c_int;
pub extern "c" fn lua_error(L: ?*lua_State) c_int;
pub extern "c" fn luaL_argerror(L: ?*lua_State, arg: c_int, extramsg: [*c]const u8) c_int;
pub extern "c" fn luaL_checkinteger(L: ?*lua_State, arg: c_int) lua_Integer;
pub extern "c" fn luaL_checknumber(L: ?*lua_State, arg: c_int) lua_Number;
pub extern "c" fn luaL_checklstring(L: ?*lua_State, arg: c_int, len: ?*usize) [*c]const u8;
pub extern "c" fn luaL_checkudata(L: ?*lua_State, arg: c_int, tname: [*c]const u8) ?*anyopaque;
pub extern "c" fn luaL_error(L: ?*lua_State, fmt: [*c]const u8, ...) c_int;
pub extern "c" fn luaL_newmetatable(L: ?*lua_State, tname: [*c]const u8) c_int;
pub extern "c" fn luaL_optinteger(L: ?*lua_State, arg: c_int, def: lua_Integer) lua_Integer;
pub extern "c" fn luaL_optlstring(L: ?*lua_State, arg: c_int, def: [*c]const u8, len: ?*usize) [*c]const u8;
pub extern "c" fn luaL_optnumber(L: ?*lua_State, arg: c_int, def: lua_Number) lua_Number;
pub extern "c" fn luaL_ref(L: ?*lua_State, t: c_int) c_int;
pub extern "c" fn luaL_unref(L: ?*lua_State, t: c_int, ref: c_int) void;

// Raster font data (extern symbols)
pub extern const Lat15_Terminus12x6_psf: [*]const u8;
pub extern const Lat15_Terminus12x6_psf_len: usize;
pub extern const Lat15_Terminus22x11_psf: [*]const u8;
pub extern const Lat15_Terminus22x11_psf_len: usize;
pub extern const Lat15_Terminus32x16_psf: [*]const u8;
pub extern const Lat15_Terminus32x16_psf_len: usize;

// TTF types
pub const TTF_Font = opaque {};

// cli_builtin.h types (used by terminal frameserver cli_parse.zig / cli.zig)
// Source of truth: src/frameserver/terminal/default/cli_builtin.h
pub const struct_group_ent = extern struct {
    enter: i8 = 0,
    leave: i8 = 0,
    leave_eol: bool = false,
    expand: ?*const fn (*struct_group_ent, [*c]const u8) callconv(.c) [*c]u8 = null,
};
pub const group_ent = struct_group_ent;

pub const struct_argv_parse_opt = extern struct {
    prepad: usize = 0,
    groups: [*c]struct_group_ent = null,
    sep: i8 = 0,
};
pub const argv_parse_opt = struct_argv_parse_opt;

// cli_builtin.h: enum launch_mode values (src/frameserver/terminal/default/cli_builtin.h)
pub const LAUNCH_UNSET: c_uint = 0;
pub const LAUNCH_VT100: c_uint = 1;
pub const LAUNCH_TUI: c_uint = 2;
pub const LAUNCH_WL: c_uint = 3;
pub const LAUNCH_X11: c_uint = 4;
pub const LAUNCH_SHMIF: c_uint = 5;

// cli_builtin.h: struct ext_cmd — descriptor for a pending launch
pub const struct_ext_cmd = extern struct {
    id: u32 = 0,
    flags: c_int = 0,
    argv: [*c][*c]u8 = null,
    env: [*c][*c]u8 = null,
    wd: [*c]u8 = null,
    mode: c_uint = LAUNCH_UNSET, // enum launch_mode in C
    stall: bool = false,
    closure: ?*const fn (usize) callconv(.c) void = null,
    closure_tag: usize = 0,
};

// cli_builtin.h: struct cli_state — shared state for the CLI frameserver
pub const struct_cli_state = extern struct {
    env: [*c][*c]u8 = null,
    cwd: [*c]u8 = null,
    mode: c_uint = LAUNCH_UNSET,
    alive: bool = false,
    bgalpha: u8 = 0,
    die_on_finish: bool = false,
    id_counter: u32 = 0,
    pending: [4]struct_ext_cmd = [_]struct_ext_cmd{.{}} ** 4,
    blocked: bool = false,
    in_debug: [*c]u8 = null,
    prompt: [*c]struct_tui_cell = null,
    prompt_sz: usize = 0,
};

// cli_builtin.h: struct cli_command — executable CLI builtin
pub const struct_cli_command = extern struct {
    name: [*c]const u8 = null,
    exec: ?*const fn (
        state: *struct_cli_state,
        argv: [*c][*c]u8,
        ofs: *isize,
        err: *[*c]u8,
    ) callconv(.c) [*c]struct_ext_cmd = null,
    cli_command: ?*const fn (
        state: *struct_cli_state,
        argv: [*c]const [*c]const u8,
        n_elem: usize,
        command: c_int,
        feedback: [*c]const [*c]const u8,
        n_results: *usize,
    ) callconv(.c) c_int = null,
};

// cli_builtin.h — exported by cli_builtin.zig
pub extern "c" fn cli_get_builtin(cmd: [*c]const u8) [*c]struct_cli_command;
// cli_parse.zig — extract_argv
pub extern "c" fn extract_argv(
    message: [*c]const u8,
    opts: struct_argv_parse_opt,
    err_ofs: *isize,
) [*c][*c]u8;

// arcan_tui_readline.h: enum — readline result status
pub const READLINE_STATUS_TERMINATE: c_int = -2;
pub const READLINE_STATUS_CANCELLED: c_int = -1;
pub const READLINE_STATUS_EDITED: c_int = 0;
pub const READLINE_STATUS_DONE: c_int = 1;

// Aliases needed by various files
pub const struct_arcan_shmif_region = arcan_shmif_region;
pub const arg_arr = struct_arg_arr;
// arcan_tui_conn is used as both a type alias and a function name in C.
// In Zig, the type alias takes priority since tui_lua.zig uses [*c]arcan_tui_conn.
pub const arcan_tui_conn = struct_arcan_shmif_cont;
// RGBA alias used by mem.zig and others
pub const RGBA = SHMIF_RGBA;
// MAP_PRIVATE constant
pub const MAP_PRIVATE: c_int = 2;

// arcan_strarr (complex string array with count/limit)
pub const struct_arcan_strarr = extern struct {
    count: usize = 0,
    limit: usize = 0,
    unnamed_0: extern union {
        data: [*c][*c]u8,
        cdata: [*c]?*anyopaque,
    } = .{ .data = null },
};

// ══════════════════════════════════════════════════════════════════════════════
// Section 5: Libc function declarations
// ══════════════════════════════════════════════════════════════════════════════
// Used by shmif files that previously got these from @cImport of system headers.

pub extern "c" fn malloc(size: usize) ?*anyopaque;
pub extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
pub extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
pub extern "c" fn free(ptr: ?*anyopaque) void;
pub extern "c" fn memcpy(noalias dst: ?*anyopaque, noalias src: ?*const anyopaque, n: usize) ?*anyopaque;
pub extern "c" fn memmove(dst: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;
pub extern "c" fn memset(dst: ?*anyopaque, ch: c_int, n: usize) ?*anyopaque;
pub extern "c" fn strdup(s: [*c]const u8) [*c]u8;
pub extern "c" fn strcmp(a: [*c]const u8, b: [*c]const u8) c_int;
pub extern "c" fn strncmp(a: [*c]const u8, b: [*c]const u8, n: usize) c_int;
pub extern "c" fn strcasecmp(a: [*c]const u8, b: [*c]const u8) c_int;
pub extern "c" fn strlen(s: [*c]const u8) usize;
pub extern "c" fn strchr(s: [*c]const u8, ch: c_int) [*c]u8;
pub extern "c" fn strrchr(s: [*c]const u8, ch: c_int) [*c]u8;
pub extern "c" fn strerror(errnum: c_int) [*c]const u8;
pub extern "c" fn read(fd: c_int, buf: ?*anyopaque, count: usize) isize;
pub extern "c" fn write(fd: c_int, buf: ?*const anyopaque, count: usize) isize;
pub extern "c" fn open(path: [*c]const u8, flags: c_int, ...) c_int;
pub extern "c" fn openat(dirfd: c_int, path: [*c]const u8, flags: c_int, ...) c_int;
pub extern "c" fn close(fd: c_int) c_int;
pub extern "c" fn dup(fd: c_int) c_int;
pub extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
pub extern "c" fn pipe(pipefd: *[2]c_int) c_int;
pub extern "c" fn fork() pid_t;
pub extern "c" fn execl(path: [*c]const u8, arg0: [*c]const u8, ...) c_int;
pub extern "c" fn execlp(file: [*c]const u8, arg0: [*c]const u8, ...) c_int;
pub extern "c" fn execve(path: [*c]const u8, argv: [*c]const [*c]const u8, envp: [*c]const [*c]const u8) c_int;
pub extern "c" fn execvp(file: [*c]const u8, argv: [*c]const [*c]const u8) c_int;
pub extern "c" fn exit(status: c_int) noreturn;
pub extern "c" fn abort() noreturn;
pub extern "c" fn kill(pid: pid_t, sig: c_int) c_int;
pub extern "c" fn signal(sig: c_int, handler: ?*const fn (c_int) callconv(.c) void) ?*const fn (c_int) callconv(.c) void;
pub extern "c" fn waitpid(pid: pid_t, status: ?*c_int, options: c_int) pid_t;
pub extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
pub extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
pub extern "c" fn poll(fds: [*c]struct_pollfd, nfds: nfds_t, timeout: c_int) c_int;
pub extern "c" fn socket(domain: c_int, @"type": c_int, protocol: c_int) c_int;
pub extern "c" fn bind(sockfd: c_int, addr: *const struct_sockaddr, addrlen: socklen_t) c_int;
pub extern "c" fn listen(sockfd: c_int, backlog: c_int) c_int;
pub extern "c" fn accept(sockfd: c_int, addr: ?*struct_sockaddr, addrlen: ?*socklen_t) c_int;
pub extern "c" fn connect(sockfd: c_int, addr: *const struct_sockaddr, addrlen: socklen_t) c_int;
pub extern "c" fn setsockopt(sockfd: c_int, level: c_int, optname: c_int, optval: ?*const anyopaque, optlen: socklen_t) c_int;
pub extern "c" fn sendmsg(sockfd: c_int, msg: *const struct_msghdr, flags: c_int) isize;
pub extern "c" fn recvmsg(sockfd: c_int, msg: *struct_msghdr, flags: c_int) isize;
pub extern "c" fn chdir(path: [*c]const u8) c_int;
pub extern "c" fn fchdir(fd: c_int) c_int;
pub extern "c" fn getcwd(buf: [*c]u8, size: usize) [*c]u8;
pub extern "c" fn fstat(fd: c_int, buf: *struct_stat) c_int;
pub extern "c" fn fstatat(dirfd: c_int, path: [*c]const u8, buf: *struct_stat, flags: c_int) c_int;
pub extern "c" fn stat(path: [*c]const u8, buf: *struct_stat) c_int;
pub extern "c" fn fchmod(fd: c_int, mode: mode_t) c_int;
pub extern "c" fn fchmodat(dirfd: c_int, path: [*c]const u8, mode: mode_t, flags: c_int) c_int;
pub extern "c" fn fchownat(dirfd: c_int, path: [*c]const u8, owner: uid_t, group: gid_t, flags: c_int) c_int;
pub extern "c" fn mkdirat(dirfd: c_int, path: [*c]const u8, mode: mode_t) c_int;
pub extern "c" fn mkfifo(path: [*c]const u8, mode: mode_t) c_int;
pub extern "c" fn mkstemp(template: [*c]u8) c_int;
pub extern "c" fn unlink(path: [*c]const u8) c_int;
pub extern "c" fn unlinkat(dirfd: c_int, path: [*c]const u8, flags: c_int) c_int;
pub extern "c" fn renameat(olddirfd: c_int, oldpath: [*c]const u8, newdirfd: c_int, newpath: [*c]const u8) c_int;
pub extern "c" fn readlinkat(dirfd: c_int, path: [*c]const u8, buf: [*c]u8, bufsiz: usize) isize;
pub extern "c" fn lseek(fd: c_int, offset: off_t, whence: c_int) off_t;
pub extern "c" fn realpath(path: [*c]const u8, resolved: [*c]u8) [*c]u8;
pub extern "c" fn setsid() pid_t;
pub extern "c" fn tcgetattr(fd: c_int, termios_p: *struct_termios) c_int;
pub extern "c" fn tcsetattr(fd: c_int, actions: c_int, termios_p: *const struct_termios) c_int;
pub extern "c" fn getenv(name: [*c]const u8) [*c]u8;
pub extern "c" fn getpwnam(name: [*c]const u8) ?*struct_passwd;
pub extern "c" fn getpwuid(uid: uid_t) ?*struct_passwd;
pub extern "c" fn getgrgid(gid: gid_t) ?*struct_group;
pub extern "c" fn getgrnam(name: [*c]const u8) ?*struct_group;
pub extern "c" fn grantpt(fd: c_int) c_int;
pub extern "c" fn unlockpt(fd: c_int) c_int;
pub extern "c" fn ptsname(fd: c_int) [*c]u8;
pub extern "c" fn posix_openpt(flags: c_int) c_int;
pub extern "c" fn perror(s: [*c]const u8) void;
pub extern "c" fn isalnum(ch: c_int) c_int;
pub extern "c" fn abs(n: c_int) c_int;
pub extern "c" fn random() c_long;
pub extern "c" fn ffs(i: c_int) c_int;
pub extern "c" fn mmap(addr: ?*anyopaque, length: usize, prot: c_int, flags: c_int, fd: c_int, offset: off_t) ?*anyopaque;
pub extern "c" fn munmap(addr: ?*anyopaque, length: usize) c_int;
pub extern "c" fn madvise(addr: ?*anyopaque, length: usize, advice: c_int) c_int;
pub extern "c" fn mprotect(addr: ?*anyopaque, length: usize, prot: c_int) c_int;
pub extern "c" fn posix_memalign(memptr: *?*anyopaque, alignment: usize, size: usize) c_int;
pub extern "c" fn uname(buf: *struct_utsname) c_int;
pub extern "c" fn sigaction(sig: c_int, act: ?*const struct_sigaction, oact: ?*struct_sigaction) c_int;

pub const DIR = opaque {};
pub extern "c" fn opendir(name: [*c]const u8) ?*DIR;
pub extern "c" fn readdir(dirp: *DIR) ?*anyopaque;
pub extern "c" fn closedir(dirp: *DIR) c_int;

pub extern "c" fn glob(pattern: [*c]const u8, flags: c_int, errfunc: ?*const fn ([*c]const u8, c_int) callconv(.c) c_int, pglob: *glob_t) c_int;
pub extern "c" fn globfree(pglob: *glob_t) void;

pub extern "c" fn pthread_create(thread: *pthread_t, attr: ?*const pthread_attr_t, start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) c_int;
pub extern "c" fn pthread_attr_init(attr: *pthread_attr_t) c_int;
pub extern "c" fn pthread_attr_destroy(attr: *pthread_attr_t) c_int;
pub extern "c" fn pthread_attr_setdetachstate(attr: *pthread_attr_t, detachstate: c_int) c_int;

pub extern "c" var stderr: *anyopaque;
pub extern "c" fn fprintf(stream: *anyopaque, fmt: [*c]const u8, ...) c_int;
pub extern "c" fn snprintf(noalias buf: [*c]u8, size: usize, noalias fmt: [*c]const u8, ...) c_int;

// errno
pub extern "c" fn __errno_location() *c_int;

// ══════════════════════════════════════════════════════════════════════════════
// Section 6: TUI extern function declarations
// ══════════════════════════════════════════════════════════════════════════════

pub extern "c" fn arcan_tui_setup(con: ?*struct_arcan_shmif_cont, parent: ?*struct_tui_context, cbs: ?*const struct_tui_cbcfg, cb_sz: usize) ?*struct_tui_context;
pub extern "c" fn arcan_tui_destroy(ctx: ?*struct_tui_context, msg: ?[*:0]const u8) void;
pub extern "c" fn arcan_tui_process(contexts: ?*?*struct_tui_context, n_contexts: c_int, fdset: ?*c_int, fdset_sz: usize, timeout: c_int) struct_tui_process_res;
pub extern "c" fn arcan_tui_refresh(ctx: ?*struct_tui_context) c_int;
pub extern "c" fn arcan_tui_update_handlers(ctx: ?*struct_tui_context, new_handlers: ?*const struct_tui_cbcfg, old: ?*struct_tui_cbcfg, cb_sz: usize) bool;
pub extern "c" fn arcan_tui_dimensions(ctx: ?*struct_tui_context, rows: ?*usize, cols: ?*usize) void;
pub extern "c" fn arcan_tui_move_to(ctx: ?*struct_tui_context, x: usize, y: usize) void;
pub extern "c" fn arcan_tui_write(ctx: ?*struct_tui_context, ucode: u32, attr: ?*const struct_tui_screen_attr) void;
pub extern "c" fn arcan_tui_writeu8(ctx: ?*struct_tui_context, u8_msg: [*c]const u8, len: usize, attr: ?*const struct_tui_screen_attr) usize;
pub extern "c" fn arcan_tui_writestr(ctx: ?*struct_tui_context, str: [*c]const u8, attr: ?*const struct_tui_screen_attr) bool;
pub extern "c" fn arcan_tui_writeattr_at(ctx: ?*struct_tui_context, attr: ?*const struct_tui_screen_attr, x: usize, y: usize) void;
pub extern "c" fn arcan_tui_write_border(ctx: ?*struct_tui_context, attr: struct_tui_screen_attr, x1: usize, y1: usize, x2: usize, y2: usize, flags: c_int) void;
pub extern "c" fn arcan_tui_erase_screen(ctx: ?*struct_tui_context, protect: bool) void;
pub extern "c" fn arcan_tui_erase_region(ctx: ?*struct_tui_context, x1: usize, y1: usize, x2: usize, y2: usize, protect: bool) void;
pub extern "c" fn arcan_tui_cursorpos(ctx: ?*struct_tui_context, x: ?*usize, y: ?*usize) void;
pub extern "c" fn arcan_tui_getxy(ctx: ?*struct_tui_context, x: usize, y: usize, resolve: bool) struct_tui_cell;
pub extern "c" fn arcan_tui_defattr(ctx: ?*struct_tui_context, attr: ?*const struct_tui_screen_attr) struct_tui_screen_attr;
pub extern "c" fn arcan_tui_defcattr(ctx: ?*struct_tui_context, group: c_int) struct_tui_screen_attr;
pub extern "c" fn arcan_tui_set_color(ctx: ?*struct_tui_context, group: c_int, rgb: [*c]const u8) void;
pub extern "c" fn arcan_tui_get_color(ctx: ?*struct_tui_context, group: c_int, rgb: [*c]u8) void;
pub extern "c" fn arcan_tui_get_bgcolor(ctx: ?*struct_tui_context, group: c_int, rgb: [*c]u8) void;
pub extern "c" fn arcan_tui_set_flags(ctx: ?*struct_tui_context, flags: c_int) c_int;
pub extern "c" fn arcan_tui_reset(ctx: ?*struct_tui_context) void;
pub extern "c" fn arcan_tui_reset_labels(ctx: ?*struct_tui_context) void;
pub extern "c" fn arcan_tui_ident(ctx: ?*struct_tui_context, ident: [*c]const u8) void;
pub extern "c" fn arcan_tui_statesize(ctx: ?*struct_tui_context, sz: usize) void;
pub extern "c" fn arcan_tui_wndhint(ctx: ?*struct_tui_context, parent: ?*struct_tui_context, cons: struct_tui_constraints) void;
pub extern "c" fn arcan_tui_content_size(ctx: ?*struct_tui_context, w: usize, h: usize, cell_w: usize, cell_h: usize) void;
pub extern "c" fn arcan_tui_copy(ctx: ?*struct_tui_context, msg: [*c]const u8) bool;
pub extern "c" fn arcan_tui_message(ctx: ?*struct_tui_context, @"type": c_int, msg: [*c]const u8) bool;
pub extern "c" fn arcan_tui_announce_io(ctx: ?*struct_tui_context, input: bool, input_descr: [*c]const u8, output_descr: [*c]const u8) void;
pub extern "c" fn arcan_tui_announce_cursor_io(ctx: ?*struct_tui_context, descr: [*c]const u8) void;
// arcan_tui_cursor_style — signature matches arcan_tui.h (3-arg, int return).
// When fl==0 and col==null, returns the currently-set cursor style.
pub extern "c" fn arcan_tui_cursor_style(ctx: ?*struct_tui_context, fl: c_int, col: ?[*]const u8) c_int;
pub extern "c" fn arcan_tui_hasglyph(ctx: ?*struct_tui_context, cp: u32) bool;
pub extern "c" fn arcan_tui_ucs4utf8(cp: u32, dst: [*c]u8) usize;
pub extern "c" fn arcan_tui_utf8ucs4(src: [*c]const u8, dst: *u32) usize;
pub extern "c" fn arcan_tui_tpack(ctx: ?*struct_tui_context, rbuf: *[*c]u8, rbuf_sz: *usize) bool;
pub extern "c" fn arcan_tui_tunpack(ctx: ?*struct_tui_context, buf: [*c]const u8, buf_sz: usize, x: usize, y: usize, unpack_w: usize, unpack_h: usize) bool;
pub extern "c" fn arcan_tui_screencopy(src: ?*struct_tui_context, dst: ?*struct_tui_context, s_x1: usize, s_y1: usize, s_x2: usize, s_y2: usize, x: usize, y: usize) void;
pub extern "c" fn arcan_tui_request_subwnd_ext(ctx: ?*struct_tui_context, @"type": c_int, hint: u8, id: u32, dir: c_int) void;
pub extern "c" fn arcan_tui_send_key(ctx: ?*struct_tui_context, utf8: [*c]u8, label: [*c]const u8, sym: u32, scode: u8, mods: u16, subid: u16) void;
pub extern "c" fn arcan_tui_open_display(title: [*c]const u8, ident: [*c]const u8) ?*struct_arcan_shmif_cont;
pub extern "c" fn arcan_tui_bgcopy(ctx: ?*struct_tui_context, fdin: c_int, fdout: c_int, sigfd: c_int, flags: c_int) void;
pub extern "c" fn arcan_tui_handover(ctx: ?*struct_tui_context, conn: ?*struct_arcan_shmif_cont, path: [*c]const u8, argv: [*c]const [*c]u8, env: [*c]const [*c]u8, flags: c_int) pid_t;
pub extern "c" fn arcan_tui_handover_pipe(ctx: ?*struct_tui_context, conn: ?*struct_arcan_shmif_cont, path: [*c]const u8, argv: [*c]const [*c]u8, env: [*c]const [*c]u8, fds: [*c]const [*c]c_int, fds_sz: usize) pid_t;
// arcan_tui_request_subwnd — request a subwindow allocation (tui subtype + id token).
pub extern "c" fn arcan_tui_request_subwnd(ctx: ?*struct_tui_context, @"type": c_uint, id: u16) void;
pub extern "c" fn arcan_tui_fdresolve(ctx: ?*struct_tui_context, fd: c_int) [*c]u8;
pub extern "c" fn arcan_tui_get_conn(ctx: ?*struct_tui_context) ?*struct_arcan_shmif_cont;

// TUI cursor / scrolling / progress helpers.
// Signatures mirror arcan_tui.h:
//   void arcan_tui_newline(struct tui_context*);
//   void arcan_tui_progress(struct tui_context*, int type, float status);
//   void arcan_tui_scroll_up(struct tui_context*, size_t);
//   void arcan_tui_scroll_down(struct tui_context*, size_t);
pub extern "c" fn arcan_tui_newline(ctx: ?*struct_tui_context) void;
pub extern "c" fn arcan_tui_progress(ctx: ?*struct_tui_context, @"type": c_int, status: f32) void;
pub extern "c" fn arcan_tui_scroll_up(ctx: ?*struct_tui_context, n: usize) void;
pub extern "c" fn arcan_tui_scroll_down(ctx: ?*struct_tui_context, n: usize) void;

// TUI widget functions
pub extern "c" fn arcan_tui_listwnd_setup(ctx: ?*struct_tui_context, entries: [*c]struct_tui_list_entry, n_entries: usize) bool;
pub extern "c" fn arcan_tui_listwnd_setpos(ctx: ?*struct_tui_context, n: usize) void;
pub extern "c" fn arcan_tui_listwnd_tell(ctx: ?*struct_tui_context) usize;
pub extern "c" fn arcan_tui_listwnd_status(ctx: ?*struct_tui_context) c_int;
pub extern "c" fn arcan_tui_listwnd_release(ctx: ?*struct_tui_context) bool;
pub extern "c" fn arcan_tui_listwnd_dirty(ctx: ?*struct_tui_context) void;

pub extern "c" fn arcan_tui_bufferwnd_setup(ctx: ?*struct_tui_context, buf: [*c]u8, buf_sz: usize, opts: ?*const struct_tui_bufferwnd_opts, sz: usize) void;
pub extern "c" fn arcan_tui_bufferwnd_seek(ctx: ?*struct_tui_context, ofs: usize) void;
pub extern "c" fn arcan_tui_bufferwnd_tell(ctx: ?*struct_tui_context) usize;
pub extern "c" fn arcan_tui_bufferwnd_status(ctx: ?*struct_tui_context) c_int;
pub extern "c" fn arcan_tui_bufferwnd_release(ctx: ?*struct_tui_context) void;

pub extern "c" fn arcan_tui_readline_setup(ctx: ?*struct_tui_context, opts: ?*const struct_tui_readline_opts, sz: usize) void;
// arcan_tui_readline_reset — clears the in-flight readline buffer.
pub extern "c" fn arcan_tui_readline_reset(ctx: ?*struct_tui_context) void;
// arcan_tui_readline_finished — returns READLINE_STATUS_* (int), not bool.
pub extern "c" fn arcan_tui_readline_finished(ctx: ?*struct_tui_context, buffer: *[*c]u8) c_int;
pub extern "c" fn arcan_tui_readline_release(ctx: ?*struct_tui_context) void;
pub extern "c" fn arcan_tui_readline_set(ctx: ?*struct_tui_context, msg: [*c]const u8) void;
pub extern "c" fn arcan_tui_readline_region(ctx: ?*struct_tui_context, x1: usize, y1: usize, x2: usize, y2: usize) void;
pub extern "c" fn arcan_tui_readline_prompt(ctx: ?*struct_tui_context, prompt: ?*const struct_tui_cell) void;
pub extern "c" fn arcan_tui_readline_history(ctx: ?*struct_tui_context, buf: [*c]const [*c]const u8, count: usize) void;
pub extern "c" fn arcan_tui_readline_autocomplete(ctx: ?*struct_tui_context, suffix: [*c]const u8) void;
pub extern "c" fn arcan_tui_readline_autosuggest(ctx: ?*struct_tui_context, enabled: bool) void;
pub extern "c" fn arcan_tui_readline_suggest(ctx: ?*struct_tui_context, mode: c_int, set: [*c]const [*c]const u8, set_sz: usize) void;
pub extern "c" fn arcan_tui_readline_suggest_fix(ctx: ?*struct_tui_context, prefix: [*c]const u8, suffix: [*c]const u8) void;
pub extern "c" fn arcan_tui_readline_format(ctx: ?*struct_tui_context, ofs: [*c]usize, attr: [*c]struct_tui_screen_attr, n: usize) void;
pub extern "c" fn arcan_tui_printf(ctx: ?*struct_tui_context, attr: ?*const struct_tui_screen_attr, fmt: [*c]const u8, ...) void;

// Pixelfont extern
pub extern "c" fn tui_pixelfont_draw(font: ?*anyopaque, buf: [*c]u32, pitch: usize, max_w: usize, max_h: usize, x: usize, y: usize, ch: u32, fg: u32, bg: u32, dsw: *usize, dsh: *usize, flags: c_int) bool;

// Shmif extern functions used by shmif module files
pub extern "c" fn arcan_shmif_cookie() u64;
/// arcan_shmif_open — primary entry point. The third arg is `struct arg_arr**`
/// in the C header; spelt as `?*?*struct_arg_arr` here.
pub extern "c" fn arcan_shmif_open(
    type_: c_int,
    flags: c_uint,
    args: ?*?*struct_arg_arr,
) struct_arcan_shmif_cont;
/// arcan_shmif_acquire — sub-segment activation from an existing parent
/// context. Variadic because different segment kinds consume additional
/// arguments (size, hint flags). Callers typically don't use the varargs.
pub extern "c" fn arcan_shmif_acquire(
    parent: ?*struct_arcan_shmif_cont,
    shmkey: [*c]const u8,
    typ: c_int,
    flags: c_int,
    ...,
) struct_arcan_shmif_cont;
pub extern "c" fn arcan_shmif_enqueue(ctx: ?*struct_arcan_shmif_cont, ev: ?*const arcan_event) c_int;
pub extern "c" fn arcan_shmif_wait(ctx: ?*struct_arcan_shmif_cont, ev: ?*arcan_event) c_int;
pub extern "c" fn arcan_shmif_signal(ctx: ?*struct_arcan_shmif_cont, mask: c_uint) c_uint;
pub extern "c" fn arcan_shmif_drop(ctx: ?*struct_arcan_shmif_cont) void;
pub extern "c" fn arcan_shmif_poll(ctx: ?*struct_arcan_shmif_cont, ev: ?*arcan_event) c_int;
pub extern "c" fn arcan_shmif_lock(ctx: ?*struct_arcan_shmif_cont) ?*anyopaque;
pub extern "c" fn arcan_shmif_dupfd(fd: c_int, newfd: c_int, closing: bool) c_int;
pub extern "c" fn arcan_shmif_dirty(ctx: ?*struct_arcan_shmif_cont, x1: usize, y1: usize, x2: usize, y2: usize, fl: c_int) void;
pub extern "c" fn arcan_shmif_vbufsz(meta: c_int, hints: u8, w: usize, h: usize, rows: usize, cols: usize) usize;
pub extern "c" fn arcan_shmif_mousestate(ctx: ?*struct_arcan_shmif_cont, state: ?[*]u8, inev: ?*arcan_event, out_x: ?*c_int, out_y: ?*c_int) bool;
pub extern "c" fn arcan_shmif_mousestate_ioev(ctx: ?*struct_arcan_shmif_cont, state: ?[*]u8, inev: ?*arcan_ioevent, out_x: ?*c_int, out_y: ?*c_int) bool;
pub extern "c" fn arcan_shmif_mousestate_setup(ctx: ?*struct_arcan_shmif_cont, flags: c_int, state: ?[*]u8) void;
pub extern "c" fn arcan_shmif_descrevent(ev: ?*const arcan_event) bool;
pub extern "c" fn arcan_shmif_eventstr(ev: ?*const arcan_event, buf: [*c]u8, buf_sz: usize) [*c]const u8;
pub extern "c" fn arcan_shmif_eventpack(aev: *const arcan_event, dbuf: [*]u8, dbuf_sz: usize) isize;
pub extern "c" fn arcan_shmif_eventunpack(sbuf: [*]const u8, sbuf_sz: usize, outev: *arcan_event) isize;

// argparse functions (from arcan_shmif_argparse.zig, re-exported for consumers)
pub extern "c" fn arg_unpack(resource: [*c]const u8) [*c]struct_arg_arr;
pub extern "c" fn arg_cleanup(arr: [*c]struct_arg_arr) void;
pub extern "c" fn arg_remove(arr: [*c]struct_arg_arr, key: [*c]const u8) void;
pub extern "c" fn arg_add(ctx: ?*struct_arcan_shmif_cont, darg: ?*[*c]struct_arg_arr, key: [*c]const u8, val: [*c]const u8, replace: bool) bool;
pub extern "c" fn arg_lookup(arr: [*c]struct_arg_arr, val: [*c]const u8, ind: c_ushort, found: ?*[*c]const u8) bool;
pub extern "c" fn arg_serialize(arr: [*c]struct_arg_arr) [*c]u8;
pub extern "c" fn arcan_shmif_last_words(ctx: ?*struct_arcan_shmif_cont, msg: [*c]const u8) void;
pub extern "c" fn arcan_shmif_privsep(ctx: ?*struct_arcan_shmif_cont, priv: [*c]const u8, paths: ?*const anyopaque, opts: c_int) void;
pub extern "c" fn arcan_shmif_defer_register(ctx: ?*struct_arcan_shmif_cont, ev: arcan_event) bool;

// arcan_shmif_primary / setprimary — SHMIF_INPUT / SHMIF_OUTPUT slot access.
pub extern "c" fn arcan_shmif_primary(@"type": c_int) ?*struct_arcan_shmif_cont;
pub extern "c" fn arcan_shmif_setprimary(@"type": c_int, ctx: ?*struct_arcan_shmif_cont) void;

// arcan_shmif_acquireloop — accept event pump used while waiting for a subseg.
pub extern "c" fn arcan_shmif_acquireloop(
    ctx: ?*struct_arcan_shmif_cont,
    acq_ev: *arcan_event,
    evpool: *[*c]arcan_event,
    evpool_sz: *isize,
) bool;

// arcan_shmif_handover_exec_pipe — handover-segment exec helper.
pub extern "c" fn arcan_shmif_handover_exec_pipe(
    ctx: ?*struct_arcan_shmif_cont,
    ev: arcan_event,
    path: [*c]const u8,
    argv: [*c][*c]u8,
    env: [*c][*c]u8,
    flags: c_int,
    fds: [*c][*c]c_int,
    fds_sz: usize,
) pid_t;

// shmifsrv extern fns — arcan_shmif_server.h. Signatures track the header.
// The `env` arg is by-value struct; `clsocket`/`statuscode` are out-params.
pub extern "c" fn shmifsrv_spawn_client(
    env: struct_shmifsrv_envp,
    clsocket: ?*c_int,
    statuscode: ?*c_int,
    idtok: u32,
) ?*struct_shmifsrv_client;
pub extern "c" fn shmifsrv_inherit_connection(
    sockin: c_int,
    memin: c_int,
    sc: ?*c_int,
) ?*struct_shmifsrv_client;
pub extern "c" fn shmifsrv_client_handle(cl: ?*struct_shmifsrv_client, pid: ?*c_int) c_int;
pub extern "c" fn shmifsrv_client_memory_handle(cl: ?*struct_shmifsrv_client) c_int;
pub extern "c" fn shmifsrv_poll(cl: ?*struct_shmifsrv_client) c_int;
pub extern "c" fn shmifsrv_free(cl: ?*struct_shmifsrv_client, mode: c_int) void;
pub extern "c" fn shmifsrv_enqueue_event(
    cl: ?*struct_shmifsrv_client,
    ev: ?*const struct_arcan_event,
    fd: c_int,
) bool;
pub extern "c" fn shmifsrv_dequeue_events(
    cl: ?*struct_shmifsrv_client,
    newev: ?*struct_arcan_event,
    limit: usize,
) usize;

// alt_nbio functions (from engine/alt/nbio.c or equivalent)
pub extern "c" fn alt_nbio_close(L: ?*lua_State, ibb: ?*?*struct_nonblock_io) c_int;
pub extern "c" fn alt_nbio_import(L: ?*lua_State, fd: c_int, m: mode_t, dst: ?*?*struct_nonblock_io, uf: ?*[*c]u8) bool;

// TTF rendering (used by raster.zig)
pub extern "c" fn TTF_RenderUNICODEglyph(font: ?*TTF_Font, ch: u32, fg: u32, bg: u32, usebg: bool, dst: [*c]u32, pitch: usize, max_w: usize, max_h: usize, dw: *usize, dh: *usize) bool;
pub extern "c" fn TTF_SetFontStyle(font: ?*TTF_Font, style: c_int) void;
