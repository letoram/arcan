// Zig reimplementation of arcan_shmif_evpack.c
// Drop-in C-ABI-compatible replacement for evpack functions.
//
// Exports: arcan_shmif_eventpack, arcan_shmif_eventunpack, arcan_shmif_eventstr
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const c = @import("shmif_types");

const Event = c.arcan_event;
const event_size = @sizeOf(Event);

// Version XOR tag: (ASHMIF_VERSION_MAJOR << 2) | ASHMIF_VERSION_MINOR
const version_xor: u16 = blk: {
    const maj: u32 = @intCast(c.ASHMIF_VERSION_MAJOR);
    const min: u32 = @intCast(c.ASHMIF_VERSION_MINOR);
    break :blk @intCast((maj << 2) | min);
};

/// Replicate subp_checksum from arcan_shmif_sub.h.
/// C uses uint16_t accumulator — the |= 0x10000 is a no-op (bit 16 truncated).
fn subpChecksum(buf: [*]const u8, len: usize) u16 {
    var res: u16 = 0;
    for (0..len) |i| {
        res = @intCast(((@as(u32, res) >> 1) + buf[i]) & 0xffff);
    }
    return res;
}

// Pack / Unpack

export fn arcan_shmif_eventpack(
    aev: *const Event,
    dbuf: [*]u8,
    dbuf_sz: usize,
) isize {
    if (is_freestanding) return -1;
    if (dbuf_sz < event_size + 2) return -1;

    const event_bytes: [*]const u8 = @ptrCast(aev);
    var checksum = subpChecksum(event_bytes, event_size) ^ version_xor;

    @memcpy(dbuf[0..2], std.mem.asBytes(&checksum));
    @memcpy(dbuf[2..][0..event_size], event_bytes[0..event_size]);

    return @intCast(event_size + 2);
}

export fn arcan_shmif_eventunpack(
    buf: [*]const u8,
    buf_sz: usize,
    out: *Event,
) isize {
    if (is_freestanding) return -1;
    if (buf_sz < event_size + 2) return -1;

    var chksum_in: u16 = undefined;
    @memcpy(std.mem.asBytes(&chksum_in), buf[0..2]);

    const out_bytes: [*]u8 = @ptrCast(out);
    @memcpy(out_bytes[0..event_size], buf[2..][0..event_size]);

    const chksum = subpChecksum(out_bytes, event_size) ^ version_xor;
    if (chksum_in != chksum) return -1;

    return @intCast(event_size + 2);
}

// eventstr helpers

extern fn snprintf(noalias buf: [*c]u8, size: usize, noalias fmt: [*c]const u8, ...) c_int;

var evbuf: [256]u8 = undefined;

fn msubToLbl(ind: c_int) [*c]const u8 {
    return switch (ind) {
        c.MBTN_LEFT_IND => "left",
        c.MBTN_RIGHT_IND => "right",
        c.MBTN_MIDDLE_IND => "middle",
        c.MBTN_WHEEL_UP_IND => "wheel-up",
        c.MBTN_WHEEL_DOWN_IND => "wheel-down",
        else => "unknown",
    };
}

/// Cast a fixed-size array pointer to a C string pointer.
inline fn arr(ptr: anytype) [*c]const u8 {
    return @ptrCast(ptr);
}

// eventstr: EXTERNAL events

fn fmtExternal(ev: *Event, work: [*c]u8, sz: usize) void {
    const ext = ev.ext();
    const kind = ext.kind;

    if (kind == c.EVENT_EXTERNAL_MESSAGE) {
        _ = snprintf(work, sz, "EXT:MESSAGE(%s):%d", arr(&ext.unnamed_0.message.data), @as(c_int, ext.unnamed_0.message.multipart));
    } else if (kind == c.EVENT_EXTERNAL_COREOPT) {
        _ = snprintf(work, sz, "EXT:COREOPT(%s)", arr(&ext.unnamed_0.message.data));
    } else if (kind == c.EVENT_EXTERNAL_IDENT) {
        _ = snprintf(work, sz, "EXT:IDENT(%s)", arr(&ext.unnamed_0.message.data));
    } else if (kind == c.EVENT_EXTERNAL_FAILURE) {
        _ = snprintf(work, sz, "EXT:FAILURE()");
    } else if (kind == c.EVENT_EXTERNAL_BUFFERSTREAM) {
        const bs = &ext.unnamed_0.bstream;
        _ = snprintf(work, sz, "EXT:BUFFERSTREAM(%zu, w*h: %zu*%zu, fmt: %d, " ++
            "stride: %zu, offset: %zu, mod(lo,hi): %u,%u)", @as(usize, bs.left), @as(usize, bs.width), @as(usize, bs.height), @as(c_int, @as(i32, @bitCast(bs.format))), @as(usize, bs.stride), @as(usize, bs.offset), bs.mod_lo, bs.mod_hi);
    } else if (kind == c.EVENT_EXTERNAL_FRAMESTATUS) {
        _ = snprintf(work, sz, "EXT:FRAMESTATUS(DEPRECATED)");
    } else if (kind == c.EVENT_EXTERNAL_STREAMINFO) {
        const si = &ext.unnamed_0.streaminf;
        _ = snprintf(work, sz, "EXT:STREAMINFO(id: %d, kind: %d, lang: %c%c%c%c", @as(c_int, si.streamid), @as(c_int, si.datakind), @as(c_int, si.langid[0]), @as(c_int, si.langid[1]), @as(c_int, si.langid[2]), @as(c_int, si.langid[3]));
    } else if (kind == c.EVENT_EXTERNAL_STATESIZE) {
        _ = snprintf(work, sz, "EXT:STATESIZE(size: %u, type: %u)", ext.unnamed_0.stateinf.size, ext.unnamed_0.stateinf.type);
    } else if (kind == c.EVENT_EXTERNAL_FLUSHAUD) {
        _ = snprintf(work, sz, "EXT:FLUSHAUD()");
    } else if (kind == c.EVENT_EXTERNAL_SEGREQ) {
        const sr = &ext.unnamed_0.segreq;
        _ = snprintf(work, sz, "EXT:SEGREQ(id: %u, dimensions: %u" ++
            "*%u+" ++ "%d,%d, kind: %d)", sr.id, @as(c_uint, sr.width), @as(c_uint, sr.height), @as(c_int, sr.xofs), @as(c_int, sr.yofs), @as(c_int, @bitCast(sr.kind)));
    } else if (kind == c.EVENT_EXTERNAL_CURSORHINT) {
        _ = snprintf(work, sz, "EXT:CURSORHINT(%s)", arr(&ext.unnamed_0.message.data));
    } else if (kind == c.EVENT_EXTERNAL_VIEWPORT) {
        fmtViewport(ext, work, sz);
    } else if (kind == c.EVENT_EXTERNAL_CONTENT) {
        const cn = &ext.unnamed_0.content;
        _ = snprintf(work, sz, "EXT:CONTENT(x: %f/%f, y: %f/%f, wh: %f/%f)", @as(f64, cn.x_pos), @as(f64, cn.x_sz), @as(f64, cn.y_pos), @as(f64, cn.y_sz), @as(f64, cn.width), @as(f64, cn.height));
    } else if (kind == c.EVENT_EXTERNAL_LABELHINT) {
        const lh = &ext.unnamed_0.labelhint;
        _ = snprintf(work, sz, "EXT:LABELHINT(label: %.16s, default: %d, descr: %.58s, " ++
            "i-alias: %d, i-type: %d)", arr(&lh.label), @as(c_int, lh.initial), arr(&lh.descr), @as(c_int, lh.subv), @as(c_int, lh.idatatype));
    } else if (kind == c.EVENT_EXTERNAL_REGISTER) {
        const rg = &ext.unnamed_0.registr;
        _ = snprintf(work, sz, "EXT:REGISTER(title: %.64s, kind: %d, %lx:%lx)", arr(&rg.title), @as(c_int, @bitCast(rg.kind)), @as(c_ulong, rg.guid[0]), @as(c_ulong, rg.guid[1]));
    } else if (kind == c.EVENT_EXTERNAL_ALERT) {
        _ = snprintf(work, sz, "EXT:ALERT(%s):%d", arr(&ext.unnamed_0.message.data), @as(c_int, ext.unnamed_0.message.multipart));
    } else if (kind == c.EVENT_EXTERNAL_CLOCKREQ) {
        const ck = &ext.unnamed_0.clock;
        _ = snprintf(work, sz, "EXT:CLOCKREQ(rate: %u, id: %u, dynamic: %u, once: %u)", ck.rate, ck.id, @as(c_uint, ck.dynamic), @as(c_uint, ck.once));
    } else if (kind == c.EVENT_EXTERNAL_BCHUNKSTATE) {
        const bc = &ext.unnamed_0.bchunk;
        _ = snprintf(work, sz, "EXT:BCHUNKSTATE(size: %lu, hint: %u, input: %u, stream: %u id: %u ext: %.68s)", @as(c_ulong, bc.unnamed_0.size), @as(c_uint, bc.hint), @as(c_uint, bc.input), @as(c_uint, bc.stream), bc.identifier, arr(&bc.extensions));
    } else if (kind == c.EVENT_EXTERNAL_STREAMSTATUS) {
        const ss = &ext.unnamed_0.streamstat;
        _ = snprintf(work, sz, "EXT:STREAMSTATUS(#%u %.9s / %.9s, comp: %f, " ++
            "streaming: %u, id: %u)", ss.frameno, arr(&ss.timestr), arr(&ss.timelim), @as(f64, ss.completion), @as(c_uint, ss.streaming), ss.identifier);
    } else if (kind == c.EVENT_EXTERNAL_NETSTATE) {
        const ns = &ext.unnamed_0.netstate;
        _ = snprintf(work, sz, "EXT:NETSTATE(space=%u:state=%u:type=%u:name=%s", @as(c_uint, ns.space), @as(c_uint, ns.state), @as(c_uint, ns.type), arr(&ns.unnamed_0.name));
    } else if (kind == c.EVENT_EXTERNAL_PRIVDROP) {
        // C code reads tgt.ioevs[0].iv even for EXTERNAL events (union overlap)
        const tgt = ev.tgt();
        _ = snprintf(work, sz, "EXT:PRIVDROP(level=%d)", tgt.ioevs[0].iv);
    } else {
        _ = snprintf(work, sz, "EXT:UNKNOWN(%d)", @as(c_int, @bitCast(kind)));
    }
}

fn fmtViewport(ext: anytype, work: [*c]u8, sz: usize) void {
    const vp = &ext.unnamed_0.viewport;
    _ = snprintf(work, sz, "EXT:VIEWPORT(frame: %lu, " ++
        "id: %u parent: %u " ++
        "@x,y+w,h: +%d,%d+%u,%u" ++
        ", border: %d,%d,%d,%d embed: %d focus: %d, invisible: %d, " ++
        "anchor-edge: %d, anchor-pos: %d, edge: %d, z: %d)", @as(c_ulong, ext.frame_id), vp.ext_id, vp.parent, @as(c_int, vp.x), @as(c_int, vp.y), @as(c_uint, @as(u16, @truncate(vp.w))), @as(c_uint, @as(u16, @truncate(vp.h))), @as(c_int, vp.border[0]), @as(c_int, vp.border[1]), @as(c_int, vp.border[2]), @as(c_int, vp.border[3]), @as(c_int, vp.embedded), @as(c_int, vp.focus), @as(c_int, vp.invisible), @as(c_int, vp.anchor_edge), @as(c_int, vp.anchor_pos), @as(c_int, vp.edge), @as(c_int, vp.order));
}

// eventstr: TARGET events

fn fmtTarget(ev: *Event, work: [*c]u8, sz: usize) void {
    const tgt = ev.tgt();
    const kind = tgt.kind;

    if (kind == c.TARGET_COMMAND_EXIT) {
        _ = snprintf(work, sz, "TGT:EXIT");
    } else if (kind == c.TARGET_COMMAND_FRAMESKIP) {
        _ = snprintf(work, sz, "TGT:FRAMESKIP(%d)", tgt.ioevs[0].iv);
    } else if (kind == c.TARGET_COMMAND_STEPFRAME) {
        _ = snprintf(work, sz, "TGT:STEPFRAME(#%d, ID: %d, sec: %u, frac: %u)", tgt.ioevs[0].iv, tgt.ioevs[1].iv, tgt.ioevs[2].uiv, tgt.ioevs[3].uiv);
    } else if (kind == c.TARGET_COMMAND_COREOPT) {
        _ = snprintf(work, sz, "TGT:COREOPT(%d=%s)", @as(c_int, tgt.code), arr(&tgt.unnamed_0.message));
    } else if (kind == c.TARGET_COMMAND_STORE) {
        _ = snprintf(work, sz, "TGT:STORE(fd)");
    } else if (kind == c.TARGET_COMMAND_RESTORE) {
        _ = snprintf(work, sz, "TGT:RESTORE(fd)");
    } else if (kind == c.TARGET_COMMAND_BCHUNK_IN) {
        const bsz = @as(c_ulong, @as(u64, @bitCast(@as(i64, tgt.ioevs[1].iv)))) | (@as(c_ulong, @as(u64, @bitCast(@as(i64, tgt.ioevs[2].iv)))) << 32);
        _ = snprintf(work, sz, "TGT:BCHUNK-IN(%lub:msg=%s)", bsz, arr(&tgt.unnamed_0.message));
    } else if (kind == c.TARGET_COMMAND_BCHUNK_OUT) {
        const bsz = @as(c_ulong, @as(u64, @bitCast(@as(i64, tgt.ioevs[1].iv)))) | (@as(c_ulong, @as(u64, @bitCast(@as(i64, tgt.ioevs[2].iv)))) << 32);
        _ = snprintf(work, sz, "TGT:BCHUNK-OUT(%lub:msg=%s)", bsz, arr(&tgt.unnamed_0.message));
    } else if (kind == c.TARGET_COMMAND_RESET) {
        const rst: [*c]const u8 = if (tgt.ioevs[0].iv == 0)
            "soft"
        else if (tgt.ioevs[0].iv == 1)
            "hard"
        else if (tgt.ioevs[0].iv == 2)
            "recover-rst"
        else if (tgt.ioevs[0].iv == 3)
            "recover-recon"
        else
            "bad-value";
        _ = snprintf(work, sz, "TGT:RESET(%s)", rst);
    } else if (kind == c.TARGET_COMMAND_PAUSE) {
        _ = snprintf(work, sz, "TGT:PAUSE()");
    } else if (kind == c.TARGET_COMMAND_UNPAUSE) {
        _ = snprintf(work, sz, "TGT:UNPAUSE()");
    } else if (kind == c.TARGET_COMMAND_SEEKCONTENT) {
        if (tgt.ioevs[0].iv == 0) {
            _ = snprintf(work, sz, "TGT:SEEKCONTENT(relative: x(+%d), y(+%d))", tgt.ioevs[1].iv, tgt.ioevs[2].iv);
        } else if (tgt.ioevs[0].iv == 1) {
            _ = snprintf(work, sz, "TGT:SEEKCONTENT(absolute: x(%f), y(%f)", @as(f64, tgt.ioevs[1].fv), @as(f64, tgt.ioevs[2].fv));
        } else {
            _ = snprintf(work, sz, "TGT:SEEKCONTENT(BROKEN)");
        }
    } else if (kind == c.TARGET_COMMAND_SEEKTIME) {
        const mode: [*c]const u8 = if (tgt.ioevs[0].iv != 1) "relative" else "absolute";
        _ = snprintf(work, sz, "TGT:SEEKTIME(%s: %f)", mode, @as(f64, tgt.ioevs[1].fv));
    } else if (kind == c.TARGET_COMMAND_DISPLAYHINT) {
        fmtDisplayhint(tgt, work, sz);
    } else if (kind == c.TARGET_COMMAND_ANCHORHINT) {
        _ = snprintf(work, sz, "TGT:ANCHORHINT(relxyz=%d,%d,%d:sref=%u:dref=%u", tgt.ioevs[0].iv, tgt.ioevs[1].iv, tgt.ioevs[2].iv, tgt.ioevs[3].uiv, tgt.ioevs[4].uiv);
    } else if (kind == c.TARGET_COMMAND_SETIODEV) {
        _ = snprintf(work, sz, "TGT:IODEV(DEPRECATED)");
    } else if (kind == c.TARGET_COMMAND_STREAMSET) {
        _ = snprintf(work, sz, "TGT:STREAMSET(%d)", tgt.ioevs[0].iv);
    } else if (kind == c.TARGET_COMMAND_ATTENUATE) {
        _ = snprintf(work, sz, "TGT:ATTENUATE(%f)", @as(f64, tgt.ioevs[0].fv));
    } else if (kind == c.TARGET_COMMAND_AUDDELAY) {
        _ = snprintf(work, sz, "TGT:AUDDELAY(aud +%d ms, vid +%d ms)", tgt.ioevs[0].iv, tgt.ioevs[1].iv);
    } else if (kind == c.TARGET_COMMAND_NEWSEGMENT) {
        const dir: [*c]const u8 = if (tgt.ioevs[1].iv != 0) "read" else "write";
        _ = snprintf(work, sz, "TGT:NEWSEGMENT(cookie:%u, direction: %s, type: %d)", tgt.ioevs[3].uiv, dir, tgt.ioevs[2].iv);
    } else if (kind == c.TARGET_COMMAND_REQFAIL) {
        _ = snprintf(work, sz, "TGT:REQFAIL(cookie:%d)", tgt.ioevs[0].iv);
    } else if (kind == c.TARGET_COMMAND_BUFFER_FAIL) {
        _ = snprintf(work, sz, "TGT:BUFFER_FAIL()");
    } else if (kind == c.TARGET_COMMAND_DEVICE_NODE) {
        fmtDeviceNode(tgt, work, sz);
    } else if (kind == c.TARGET_COMMAND_GRAPHMODE) {
        _ = snprintf(work, sz, "TGT:GRAPHMODE(group: %d, value: %.0f, %.0f, %.0f)", tgt.ioevs[0].iv, @as(f64, tgt.ioevs[1].fv), @as(f64, tgt.ioevs[2].fv), @as(f64, tgt.ioevs[3].fv));
    } else if (kind == c.TARGET_COMMAND_MESSAGE) {
        _ = snprintf(work, sz, "TGT:MESSAGE(continued: %d, message: %s)", tgt.ioevs[0].iv, arr(&tgt.unnamed_0.message));
    } else if (kind == c.TARGET_COMMAND_FONTHINT) {
        _ = snprintf(work, sz, "TGT:FONTHINT(" ++
            "type: %d, size: %f mm, hint: %d, chain: %d)", tgt.ioevs[1].iv, @as(f64, tgt.ioevs[2].fv), tgt.ioevs[3].iv, tgt.ioevs[4].iv);
    } else if (kind == c.TARGET_COMMAND_GEOHINT) {
        _ = snprintf(work, sz, "TGT:GEOHINT(" ++
            "lat: %f, long: %f, elev: %f, country/lang: %s/%s/%s, ts: %d)", @as(f64, tgt.ioevs[0].fv), @as(f64, tgt.ioevs[1].fv), @as(f64, tgt.ioevs[2].fv), arr(&tgt.ioevs[3].cv), arr(&tgt.ioevs[4].cv), arr(&tgt.ioevs[5].cv), tgt.ioevs[6].iv);
    } else if (kind == c.TARGET_COMMAND_OUTPUTHINT) {
        _ = snprintf(work, sz, "OUTPUTHINT(" ++
            "maxw/h: %d/%d, rate: %d, minw/h: %d/%d, id: %d", tgt.ioevs[0].iv, tgt.ioevs[1].iv, tgt.ioevs[2].iv, tgt.ioevs[3].iv, tgt.ioevs[4].iv, tgt.ioevs[5].iv);
    } else if (kind == c.TARGET_COMMAND_ACTIVATE) {
        _ = snprintf(work, sz, "TGT:ACTIVATE()");
    } else {
        _ = snprintf(work, sz, "TGT:UNKNOWN(!)");
    }
}

fn fmtDisplayhint(tgt: anytype, work: [*c]u8, sz: usize) void {
    const f2 = tgt.ioevs[2].iv;
    _ = snprintf(work, sz, "TGT:DISPLAYHINT(%d*%d, ppcm: %f, flags: %s%s%s%s%s%s, cell: %d, %d, tgt: %u", tgt.ioevs[0].iv, tgt.ioevs[1].iv, @as(f64, tgt.ioevs[4].fv), @as([*c]const u8, if (f2 & 1 != 0) "drag-sz " else ""), @as([*c]const u8, if (f2 & 2 != 0) "invis " else ""), @as([*c]const u8, if (f2 & 4 != 0) "unfocus " else ""), @as([*c]const u8, if (f2 & 8 != 0) "maximized " else ""), @as([*c]const u8, if (f2 & 16 != 0) "minimized " else ""), @as([*c]const u8, if (f2 & 32 != 0) "detached " else ""), tgt.ioevs[5].iv, tgt.ioevs[6].iv, tgt.ioevs[7].uiv);
}

fn fmtDeviceNode(tgt: anytype, work: [*c]u8, sz: usize) void {
    if (tgt.ioevs[1].iv == 1) {
        _ = snprintf(work, sz, "TGT:DEVICE_NODE(render-node)");
    } else if (tgt.ioevs[1].iv == 2) {
        _ = snprintf(work, sz, "TGT:DEVICE_NODE(connpath: %s:%d)", arr(&tgt.unnamed_0.message), tgt.ioevs[0].iv);
    } else if (tgt.ioevs[1].iv == 3) {
        _ = snprintf(work, sz, "TGT:DEVICE_NODE(remote: %s:%d)", arr(&tgt.unnamed_0.message), tgt.ioevs[0].iv);
    } else if (tgt.ioevs[1].iv == 4) {
        _ = snprintf(work, sz, "TGT:DEVICE_NODE(alt: %s:%d)", arr(&tgt.unnamed_0.message), tgt.ioevs[0].iv);
    } else if (tgt.ioevs[1].iv == 5) {
        _ = snprintf(work, sz, "TGT:DEVICE_NODE(auth-cookie)");
    }
}

// eventstr: IO events

fn fmtIo(ev: *Event, work: [*c]u8, sz: usize) void {
    const io = ev.io();
    const dt = io.datatype;

    if (dt == c.EVENT_IDATATYPE_TRANSLATED) {
        const tr = &io.input.translated;
        _ = snprintf(work, sz, "IO:(%s)[kbd(%d):%s] %d:mask=%d,sym:%d,code:%d,utf8:%s", arr(&io.label), @as(c_int, io.unnamed_0.unnamed_0.devid), @as([*c]const u8, if (tr.active != 0) "pressed" else "released"), @as(c_int, io.unnamed_0.unnamed_0.subid), @as(c_int, tr.modifiers), @as(c_int, @bitCast(tr.keysym)), @as(c_int, tr.scancode), arr(&tr.utf8));
    } else if (dt == c.EVENT_IDATATYPE_ANALOG) {
        const an = &io.input.analog;
        const devstr: [*c]const u8 = if (io.devkind == c.EVENT_IDEVKIND_MOUSE) "mouse" else "analog";
        _ = snprintf(work, sz, "IO:(%s)[%s(%d):%d] act: %s, rel: %s, v(%d){%d, %d, %d, %d}", arr(&io.label), devstr, @as(c_int, io.unnamed_0.unnamed_0.devid), @as(c_int, io.unnamed_0.unnamed_0.subid), @as([*c]const u8, if (an.active != 0) "yes" else "no"), @as([*c]const u8, if (an.gotrel != 0) "yes" else "no"), @as(c_int, an.nvalues), @as(c_int, an.axisval[0]), @as(c_int, an.axisval[1]), @as(c_int, an.axisval[2]), @as(c_int, an.axisval[3]));
    } else if (dt == c.EVENT_IDATATYPE_EYES) {
        const ey = &io.input.eyes;
        _ = snprintf(work, sz, "EYE:(%s)[eye(%d)] %d: head:%f,%f,%f ang: %f,%f,%f" ++
            "gaze_1: %f,%f gaze_2: %f,%f", arr(&io.label), @as(c_int, io.unnamed_0.unnamed_0.devid), @as(c_int, io.unnamed_0.unnamed_0.subid), @as(f64, ey.head_pos[0]), @as(f64, ey.head_pos[1]), @as(f64, ey.head_pos[2]), @as(f64, ey.head_ang[0]), @as(f64, ey.head_ang[1]), @as(f64, ey.head_ang[2]), @as(f64, ey.gaze_x1), @as(f64, ey.gaze_y1), @as(f64, ey.gaze_x2), @as(f64, ey.gaze_y2));
    } else if (dt == c.EVENT_IDATATYPE_TOUCH) {
        const tc = &io.input.touch;
        _ = snprintf(work, sz, "IO:(%s)[touch(%d)] %d: @%d,%d pressure: %f, size: %f", arr(&io.label), @as(c_int, io.unnamed_0.unnamed_0.devid), @as(c_int, io.unnamed_0.unnamed_0.subid), @as(c_int, tc.x), @as(c_int, tc.y), @as(f64, tc.pressure), @as(f64, tc.size));
    } else if (dt == c.EVENT_IDATATYPE_DIGITAL) {
        if (io.devkind == c.EVENT_IDEVKIND_MOUSE) {
            _ = snprintf(work, sz, "IO:[mouse(%d):%d], %s:%s", @as(c_int, io.unnamed_0.unnamed_0.devid), @as(c_int, io.unnamed_0.unnamed_0.subid), msubToLbl(@intCast(io.unnamed_0.unnamed_0.subid)), @as([*c]const u8, if (io.input.digital.active != 0) "pressed" else "released"));
        } else {
            _ = snprintf(work, sz, "IO:[digital(%d):%d], %s", @as(c_int, io.unnamed_0.unnamed_0.devid), @as(c_int, io.unnamed_0.unnamed_0.subid), @as([*c]const u8, if (io.input.digital.active != 0) "pressed" else "released"));
        }
    } else {
        _ = snprintf(work, sz, "IO:[unhandled(%d)]", @as(c_int, @bitCast(dt)));
    }
}

// eventstr entry point

export fn arcan_shmif_eventstr(
    aev: ?*Event,
    dbuf: ?[*]u8,
    dsz: usize,
) [*c]const u8 {
    if (is_freestanding) return "";
    const empty: [*c]const u8 = "";
    if (aev == null) return empty;

    var ev: Event = aev.?.*;

    var work: [*c]u8 = undefined;
    var sz: usize = undefined;
    if (dbuf) |buf| {
        work = buf;
        sz = dsz;
    } else {
        work = @ptrCast(&evbuf);
        sz = evbuf.len;
    }

    const cat: c_int = @intCast(ev.category().*);

    if (cat == c.EVENT_EXTERNAL) {
        fmtExternal(&ev, work, sz);
    } else if (cat == c.EVENT_TARGET) {
        fmtTarget(&ev, work, sz);
    } else if (cat == c.EVENT_IO) {
        fmtIo(&ev, work, sz);
    }

    return @ptrCast(work);
}
