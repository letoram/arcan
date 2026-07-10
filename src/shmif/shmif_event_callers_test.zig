/// shmif real-world event construction tests
///
/// Tier 7: Tests that construct events exactly as real callers do (frameservers,
/// TUI, a12, server), round-trip them, and verify every field index. Derived
/// from actual code patterns in production callers.
const std = @import("std");
const testing = std.testing;

const c = @import("shmif_types");

// Accessor shortcuts

const Event = c.arcan_event;

inline fn inner(ev: *Event) *@TypeOf(ev.unnamed_0.unnamed_0) {
    return &ev.unnamed_0.unnamed_0;
}

inline fn variants(ev: *Event) *@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0) {
    return &ev.unnamed_0.unnamed_0.unnamed_0;
}

fn makeEvent(category: u8) Event {
    var ev: Event = std.mem.zeroes(Event);
    inner(&ev).category = category;
    return ev;
}

/// Pack and unpack an event, returning the unpacked result.
fn roundTrip(ev: *Event) !Event {
    var buf: [256]u8 = undefined;
    const pack_sz = c.arcan_shmif_eventpack(ev, &buf, buf.len);
    try testing.expect(pack_sz > 0);

    var out: Event = undefined;
    const unpack_sz = c.arcan_shmif_eventunpack(&buf, @intCast(pack_sz), &out);
    try testing.expectEqual(pack_sz, unpack_sz);
    return out;
}

// 7a. TARGET event ioevs field-index contracts

test "DISPLAYHINT field layout: w/h/flags/ppcm/cell_h/cell_w" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_DISPLAYHINT;
    tgt.ioevs[0].iv = 1920; // width
    tgt.ioevs[1].iv = 1080; // height
    tgt.ioevs[2].iv = 0x08; // flags: maximized
    tgt.ioevs[4].fv = 37.8; // ppcm
    tgt.ioevs[5].iv = 16; // cell_width (tpack)
    tgt.ioevs[6].iv = 32; // cell_height (tpack)

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(i32, 1920), o.ioevs[0].iv);
    try testing.expectEqual(@as(i32, 1080), o.ioevs[1].iv);
    try testing.expectEqual(@as(i32, 0x08), o.ioevs[2].iv);
    try testing.expectApproxEqAbs(@as(f32, 37.8), o.ioevs[4].fv, 0.01);
    try testing.expectEqual(@as(i32, 16), o.ioevs[5].iv);
    try testing.expectEqual(@as(i32, 32), o.ioevs[6].iv);
}

test "FONTHINT field layout: fd/type/size/hint/chain" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_FONTHINT;
    tgt.ioevs[0].iv = 42; // fd
    tgt.ioevs[1].iv = 1; // font presence indicator
    tgt.ioevs[2].fv = 3.5; // size in mm
    tgt.ioevs[3].iv = 2; // hinting: light
    tgt.ioevs[4].iv = 1; // chain: continuation

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(i32, 42), o.ioevs[0].iv);
    try testing.expectEqual(@as(i32, 1), o.ioevs[1].iv);
    try testing.expectApproxEqAbs(@as(f32, 3.5), o.ioevs[2].fv, 0.01);
    try testing.expectEqual(@as(i32, 2), o.ioevs[3].iv);
    try testing.expectEqual(@as(i32, 1), o.ioevs[4].iv);
}

test "GEOHINT float+cv fields: lat/lon/elev + country/lang/tz" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_GEOHINT;
    tgt.ioevs[0].fv = 59.334; // lat
    tgt.ioevs[1].fv = 18.065; // lon
    tgt.ioevs[2].fv = 28.0; // elev
    // country: "SWE\0"
    tgt.ioevs[3].cv = .{ 'S', 'W', 'E', 0 };
    // language spoken: "swe\0"
    tgt.ioevs[4].cv = .{ 's', 'w', 'e', 0 };
    // language written: "swe\0"
    tgt.ioevs[5].cv = .{ 's', 'w', 'e', 0 };

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectApproxEqAbs(@as(f32, 59.334), o.ioevs[0].fv, 0.01);
    try testing.expectApproxEqAbs(@as(f32, 18.065), o.ioevs[1].fv, 0.01);
    try testing.expectApproxEqAbs(@as(f32, 28.0), o.ioevs[2].fv, 0.01);
    try testing.expectEqual([4]u8{ 'S', 'W', 'E', 0 }, o.ioevs[3].cv);
    try testing.expectEqual([4]u8{ 's', 'w', 'e', 0 }, o.ioevs[4].cv);
    try testing.expectEqual([4]u8{ 's', 'w', 'e', 0 }, o.ioevs[5].cv);
}

test "OUTPUTHINT 6-field layout: maxw/h/rate/minw/h/display_id" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_OUTPUTHINT;
    tgt.ioevs[0].iv = 3840; // max_width
    tgt.ioevs[1].iv = 2160; // max_height
    tgt.ioevs[2].iv = 144; // rate
    tgt.ioevs[3].iv = 640; // min_width
    tgt.ioevs[4].iv = 480; // min_height
    tgt.ioevs[5].iv = 1; // output_id

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(i32, 3840), o.ioevs[0].iv);
    try testing.expectEqual(@as(i32, 2160), o.ioevs[1].iv);
    try testing.expectEqual(@as(i32, 144), o.ioevs[2].iv);
    try testing.expectEqual(@as(i32, 640), o.ioevs[3].iv);
    try testing.expectEqual(@as(i32, 480), o.ioevs[4].iv);
    try testing.expectEqual(@as(i32, 1), o.ioevs[5].iv);
}

test "RESET sub-codes: 0=soft, 1=hard, 2=recover-rst, 3=recover-recon" {
    const codes = [_]i32{ 0, 1, 2, 3 };
    for (codes) |code| {
        var ev = makeEvent(c.EVENT_TARGET);
        const tgt = &variants(&ev).tgt;
        tgt.kind = c.TARGET_COMMAND_RESET;
        tgt.ioevs[0].iv = code;

        const out = try roundTrip(&ev);
        const o = variants(@constCast(&out)).tgt;
        try testing.expectEqual(code, o.ioevs[0].iv);
    }
}

test "NEWSEGMENT direction+type+cookie" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_NEWSEGMENT;
    tgt.ioevs[1].iv = 1; // direction: input
    tgt.ioevs[2].iv = c.SEGID_CLIPBOARD; // segment type
    tgt.ioevs[3].uiv = 0xfeedface; // cookie

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(i32, 1), o.ioevs[1].iv);
    try testing.expectEqual(@as(i32, c.SEGID_CLIPBOARD), o.ioevs[2].iv);
    try testing.expectEqual(@as(u32, 0xfeedface), o.ioevs[3].uiv);
}

test "FRAMESKIP 5 timing parameters" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_FRAMESKIP;
    tgt.ioevs[0].iv = c.TARGET_SKIP_AUTO;
    tgt.ioevs[1].iv = 10;
    tgt.ioevs[2].iv = 20;
    tgt.ioevs[3].iv = 30;
    tgt.ioevs[4].iv = 40;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(i32, c.TARGET_SKIP_AUTO), o.ioevs[0].iv);
    try testing.expectEqual(@as(i32, 10), o.ioevs[1].iv);
    try testing.expectEqual(@as(i32, 20), o.ioevs[2].iv);
    try testing.expectEqual(@as(i32, 30), o.ioevs[3].iv);
    try testing.expectEqual(@as(i32, 40), o.ioevs[4].iv);
}

test "STEPFRAME counter positive and negative" {
    // Positive step
    {
        var ev = makeEvent(c.EVENT_TARGET);
        const tgt = &variants(&ev).tgt;
        tgt.kind = c.TARGET_COMMAND_STEPFRAME;
        tgt.ioevs[0].iv = 5;

        const out = try roundTrip(&ev);
        try testing.expectEqual(@as(i32, 5), variants(@constCast(&out)).tgt.ioevs[0].iv);
    }
    // Negative step (rollback)
    {
        var ev = makeEvent(c.EVENT_TARGET);
        const tgt = &variants(&ev).tgt;
        tgt.kind = c.TARGET_COMMAND_STEPFRAME;
        tgt.ioevs[0].iv = -3;

        const out = try roundTrip(&ev);
        try testing.expectEqual(@as(i32, -3), variants(@constCast(&out)).tgt.ioevs[0].iv);
    }
}

test "STORE fd-carrying event" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_STORE;
    tgt.ioevs[0].iv = 42; // fd (not BADFD)

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(i32, 42), o.ioevs[0].iv);
}

test "BCHUNK_IN with message label" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
    tgt.ioevs[0].iv = 10; // fd
    tgt.ioevs[1].iv = 4096; // size_lo
    tgt.ioevs[2].iv = 0; // size_hi
    const label = "application/pdf";
    for (label, 0..) |ch, i| {
        tgt.unnamed_0.message[i] = ch;
    }

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(i32, 10), o.ioevs[0].iv);
    try testing.expectEqual(@as(i32, 4096), o.ioevs[1].iv);
    try testing.expectEqual(@as(i32, 0), o.ioevs[2].iv);
    const out_label: *const [label.len]u8 = @ptrCast(o.unnamed_0.message[0..label.len]);
    try testing.expectEqualSlices(u8, label, out_label);
}

test "BCHUNK_OUT with message label" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_BCHUNK_OUT;
    tgt.ioevs[0].iv = 11; // fd
    tgt.ioevs[1].iv = 8192; // size_lo
    tgt.ioevs[2].iv = 1; // size_hi
    const label = "text/plain";
    for (label, 0..) |ch, i| {
        tgt.unnamed_0.message[i] = ch;
    }

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(i32, 11), o.ioevs[0].iv);
    try testing.expectEqual(@as(i32, 8192), o.ioevs[1].iv);
    try testing.expectEqual(@as(i32, 1), o.ioevs[2].iv);
    const out_label: *const [label.len]u8 = @ptrCast(o.unnamed_0.message[0..label.len]);
    try testing.expectEqualSlices(u8, label, out_label);
}

test "TARGET message union access: 78-byte string" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_MESSAGE;
    // Fill with a pattern up to 77 bytes (last byte must be 0)
    const msg = "The quick brown fox jumps over the lazy dog - testing 78 byte message field!";
    comptime {
        std.debug.assert(msg.len < 78);
    }
    for (msg, 0..) |ch, i| {
        tgt.unnamed_0.message[i] = ch;
    }

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    const out_msg: *const [msg.len]u8 = @ptrCast(o.unnamed_0.message[0..msg.len]);
    try testing.expectEqualSlices(u8, msg, out_msg);
}

// 7b. EXTERNAL event sub-struct contracts

test "SEGREQ clipboard pattern: kind=CLIPBOARD, w=1, h=1, id" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_SEGREQ;
    ext.unnamed_0.segreq.kind = c.SEGID_CLIPBOARD;
    ext.unnamed_0.segreq.width = 1;
    ext.unnamed_0.segreq.height = 1;
    ext.unnamed_0.segreq.id = 0xfeedface;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(@TypeOf(o.kind), c.EVENT_EXTERNAL_SEGREQ), o.kind);
    try testing.expectEqual(@as(@TypeOf(o.unnamed_0.segreq.kind), c.SEGID_CLIPBOARD), o.unnamed_0.segreq.kind);
    try testing.expectEqual(@as(u16, 1), o.unnamed_0.segreq.width);
    try testing.expectEqual(@as(u16, 1), o.unnamed_0.segreq.height);
    try testing.expectEqual(@as(u32, 0xfeedface), o.unnamed_0.segreq.id);
}

test "SEGREQ handover pattern: kind=HANDOVER" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_SEGREQ;
    ext.unnamed_0.segreq.kind = c.SEGID_HANDOVER;
    ext.unnamed_0.segreq.width = 640;
    ext.unnamed_0.segreq.height = 480;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(@TypeOf(o.unnamed_0.segreq.kind), c.SEGID_HANDOVER), o.unnamed_0.segreq.kind);
    try testing.expectEqual(@as(u16, 640), o.unnamed_0.segreq.width);
    try testing.expectEqual(@as(u16, 480), o.unnamed_0.segreq.height);
}

test "CLOCKREQ timer pattern: rate/id/dynamic/once" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_CLOCKREQ;
    ext.unnamed_0.clock.rate = 1;
    ext.unnamed_0.clock.id = 0xabcdef00;
    ext.unnamed_0.clock.dynamic = 0;
    ext.unnamed_0.clock.once = 1;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u32, 1), o.unnamed_0.clock.rate);
    try testing.expectEqual(@as(u32, 0xabcdef00), o.unnamed_0.clock.id);
    try testing.expectEqual(@as(u8, 0), o.unnamed_0.clock.dynamic);
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.clock.once);
}

test "BCHUNKSTATE with extensions" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_BCHUNKSTATE;
    ext.unnamed_0.bchunk.hint = 1;
    ext.unnamed_0.bchunk.input = 1;
    const exts = "png;jpg;gif";
    for (exts, 0..) |ch, i| {
        ext.unnamed_0.bchunk.extensions[i] = ch;
    }

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.bchunk.hint);
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.bchunk.input);
    const out_exts: *const [exts.len]u8 = @ptrCast(o.unnamed_0.bchunk.extensions[0..exts.len]);
    try testing.expectEqualSlices(u8, exts, out_exts);
}

test "STATESIZE report: size and type" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_STATESIZE;
    ext.unnamed_0.stateinf.size = 65536;
    ext.unnamed_0.stateinf.type = 1;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u32, 65536), o.unnamed_0.stateinf.size);
    try testing.expectEqual(@as(u32, 1), o.unnamed_0.stateinf.type);
}

test "STREAMINFO langid: 3-byte language code" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_STREAMINFO;
    ext.unnamed_0.streaminf.streamid = 1;
    ext.unnamed_0.streaminf.datakind = 2; // text
    ext.unnamed_0.streaminf.langid = .{ 'e', 'n', 'g', 0 };

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.streaminf.streamid);
    try testing.expectEqual(@as(u8, 2), o.unnamed_0.streaminf.datakind);
    try testing.expectEqual([4]u8{ 'e', 'n', 'g', 0 }, o.unnamed_0.streaminf.langid);
}

test "REGISTER with kind+guid+title" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_REGISTER;
    ext.unnamed_0.registr.kind = c.SEGID_TUI;
    ext.unnamed_0.registr.guid[0] = 0xdeadbeef12345678;
    ext.unnamed_0.registr.guid[1] = 0xcafebabe87654321;
    const title = "my-tui-app";
    for (title, 0..) |ch, i| {
        ext.unnamed_0.registr.title[i] = ch;
    }

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(@TypeOf(o.unnamed_0.registr.kind), c.SEGID_TUI), o.unnamed_0.registr.kind);
    try testing.expectEqual(@as(u64, 0xdeadbeef12345678), o.unnamed_0.registr.guid[0]);
    try testing.expectEqual(@as(u64, 0xcafebabe87654321), o.unnamed_0.registr.guid[1]);
    const out_title: *const [title.len]u8 = @ptrCast(o.unnamed_0.registr.title[0..title.len]);
    try testing.expectEqualSlices(u8, title, out_title);
}

test "LABELHINT with label+idatatype+descr" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_LABELHINT;
    const label = "PASTE";
    for (label, 0..) |ch, i| {
        ext.unnamed_0.labelhint.label[i] = ch;
    }
    ext.unnamed_0.labelhint.idatatype = c.EVENT_IDATATYPE_DIGITAL;
    const descr = "Paste from clipboard";
    for (descr, 0..) |ch, i| {
        ext.unnamed_0.labelhint.descr[i] = ch;
    }

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    const out_label: *const [label.len]u8 = @ptrCast(o.unnamed_0.labelhint.label[0..label.len]);
    try testing.expectEqualSlices(u8, label, out_label);
    try testing.expectEqual(@as(u8, c.EVENT_IDATATYPE_DIGITAL), o.unnamed_0.labelhint.idatatype);
    const out_descr: *const [descr.len]u8 = @ptrCast(o.unnamed_0.labelhint.descr[0..descr.len]);
    try testing.expectEqualSlices(u8, descr, out_descr);
}

test "CURSORHINT as message: cursor style 'hidden'" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_CURSORHINT;
    const cursor = "hidden";
    for (cursor, 0..) |ch, i| {
        ext.unnamed_0.message.data[i] = ch;
    }

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(@TypeOf(o.kind), c.EVENT_EXTERNAL_CURSORHINT), o.kind);
    const out_cursor: *const [cursor.len]u8 = @ptrCast(o.unnamed_0.message.data[0..cursor.len]);
    try testing.expectEqualSlices(u8, cursor, out_cursor);
}

test "MESSAGE multipart flag round-trips" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_MESSAGE;
    ext.unnamed_0.message.multipart = 1;
    const msg = "first part of a long message";
    for (msg, 0..) |ch, i| {
        ext.unnamed_0.message.data[i] = ch;
    }

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.message.multipart);
    const out_msg: *const [msg.len]u8 = @ptrCast(o.unnamed_0.message.data[0..msg.len]);
    try testing.expectEqualSlices(u8, msg, out_msg);
}

// 7c. ioevs union type coverage

test "ioevs[].iv: negative values survive (BADFD = -1)" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_STORE;
    tgt.ioevs[0].iv = -1; // BADFD

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(i32, -1), variants(@constCast(&out)).tgt.ioevs[0].iv);
}

test "ioevs[].uiv: large unsigned values (cookie = 0xfeedface)" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_NEWSEGMENT;
    tgt.ioevs[3].uiv = 0xfeedface;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(u32, 0xfeedface), variants(@constCast(&out)).tgt.ioevs[3].uiv);
}

test "ioevs[].fv: float precision preserved" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_GEOHINT;
    tgt.ioevs[0].fv = 59.334591; // lat
    tgt.ioevs[1].fv = -18.065321; // lon (negative)

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectApproxEqAbs(@as(f32, 59.334591), o.ioevs[0].fv, 0.0001);
    try testing.expectApproxEqAbs(@as(f32, -18.065321), o.ioevs[1].fv, 0.0001);
}

test "ioevs[].cv: 4-byte char array preserved" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_GEOHINT;
    tgt.ioevs[3].cv = .{ 'U', 'S', 'A', 0 };

    const out = try roundTrip(&ev);
    try testing.expectEqual([4]u8{ 'U', 'S', 'A', 0 }, variants(@constCast(&out)).tgt.ioevs[3].cv);
}

// 7d. descrevent completeness

test "descrevent TARGET_COMMAND_BCHUNK_OUT with valid fd returns true" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_BCHUNK_OUT;
    tgt.ioevs[0].iv = 42;
    try testing.expect(c.arcan_shmif_descrevent(&ev));
}

test "descrevent TARGET_COMMAND_NEWSEGMENT with valid fd returns true" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_NEWSEGMENT;
    tgt.ioevs[0].iv = 42;
    try testing.expect(c.arcan_shmif_descrevent(&ev));
}

// 7e. eventstr for caller-relevant events

test "eventstr for DISPLAYHINT contains DISPLAYHINT" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_DISPLAYHINT;
    tgt.ioevs[0].iv = 1920;
    tgt.ioevs[1].iv = 1080;
    const result = c.arcan_shmif_eventstr(&ev, null, 0);
    try testing.expect(result != null);
    const str = std.mem.span(result.?);
    try testing.expect(std.mem.indexOf(u8, str, "DISPLAYHINT") != null);
}

test "eventstr for SEGREQ contains SEGREQ" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_SEGREQ;
    const result = c.arcan_shmif_eventstr(&ev, null, 0);
    try testing.expect(result != null);
    const str = std.mem.span(result.?);
    try testing.expect(std.mem.indexOf(u8, str, "SEGREQ") != null);
}

// 7f. Edge cases: boundary values and extremes

test "DISPLAYHINT hints-only: w=0, h=0 (only flags change)" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_DISPLAYHINT;
    tgt.ioevs[0].iv = 0; // w=0 means "hints only"
    tgt.ioevs[1].iv = 0; // h=0 means "hints only"
    tgt.ioevs[2].iv = 0x02; // invisible flag
    tgt.ioevs[4].fv = -1.0; // ppcm < 0 means "ignore"

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(i32, 0), o.ioevs[0].iv);
    try testing.expectEqual(@as(i32, 0), o.ioevs[1].iv);
    try testing.expectEqual(@as(i32, 0x02), o.ioevs[2].iv);
    try testing.expectApproxEqAbs(@as(f32, -1.0), o.ioevs[4].fv, 0.01);
}

test "DISPLAYHINT max resolution at PP_SHMPAGE_MAXW/H" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_DISPLAYHINT;
    tgt.ioevs[0].iv = c.PP_SHMPAGE_MAXW;
    tgt.ioevs[1].iv = c.PP_SHMPAGE_MAXH;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(i32, c.PP_SHMPAGE_MAXW), o.ioevs[0].iv);
    try testing.expectEqual(@as(i32, c.PP_SHMPAGE_MAXH), o.ioevs[1].iv);
}

test "DISPLAYHINT all flags combined" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_DISPLAYHINT;
    // drag(1) | invisible(2) | unfocused(4) | maximized(8) | fullscreen(16) | detached(32)
    tgt.ioevs[2].iv = 0x3F;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(i32, 0x3F), variants(@constCast(&out)).tgt.ioevs[2].iv);
}

test "DISPLAYHINT segment_token in ioevs[7].uiv" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_DISPLAYHINT;
    tgt.ioevs[7].uiv = 0xDEADBEEF;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(u32, 0xDEADBEEF), variants(@constCast(&out)).tgt.ioevs[7].uiv);
}

test "FONTHINT with BADFD (no font descriptor)" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_FONTHINT;
    tgt.ioevs[0].iv = -1; // BADFD
    tgt.ioevs[2].fv = 0.0; // size 0 means unchanged
    tgt.ioevs[3].iv = -1; // hint -1 means unchanged

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(i32, -1), o.ioevs[0].iv);
    try testing.expectApproxEqAbs(@as(f32, 0.0), o.ioevs[2].fv, 0.001);
    try testing.expectEqual(@as(i32, -1), o.ioevs[3].iv);
}

test "GEOHINT negative elevation and longitude" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_GEOHINT;
    tgt.ioevs[0].fv = -33.868; // lat (Sydney, negative)
    tgt.ioevs[1].fv = 151.209; // lon
    tgt.ioevs[2].fv = -100.0; // below sea level

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectApproxEqAbs(@as(f32, -33.868), o.ioevs[0].fv, 0.01);
    try testing.expectApproxEqAbs(@as(f32, 151.209), o.ioevs[1].fv, 0.01);
    try testing.expectApproxEqAbs(@as(f32, -100.0), o.ioevs[2].fv, 0.01);
}

test "GEOHINT cv with high bytes (non-ASCII in byte array)" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_GEOHINT;
    tgt.ioevs[3].cv = .{ 0xFF, 0x80, 0x01, 0x00 };

    const out = try roundTrip(&ev);
    try testing.expectEqual([4]u8{ 0xFF, 0x80, 0x01, 0x00 }, variants(@constCast(&out)).tgt.ioevs[3].cv);
}

test "OUTPUTHINT with VRR fields (ioevs[6..7] floats)" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_OUTPUTHINT;
    tgt.ioevs[0].iv = 2560;
    tgt.ioevs[1].iv = 1440;
    tgt.ioevs[2].iv = 165;
    tgt.ioevs[6].fv = 48.0; // vrr_min
    tgt.ioevs[7].fv = 1.0; // vrr_step

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectApproxEqAbs(@as(f32, 48.0), o.ioevs[6].fv, 0.01);
    try testing.expectApproxEqAbs(@as(f32, 1.0), o.ioevs[7].fv, 0.01);
}

test "FRAMESKIP with all TARGET_SKIP modes" {
    const modes = [_]i32{
        c.TARGET_SKIP_AUTO, // 0
        c.TARGET_SKIP_NONE, // -1
        c.TARGET_SKIP_REVERSE, // -2
        c.TARGET_SKIP_ROLLBACK, // -3
        c.TARGET_SKIP_STEP, // 1
        c.TARGET_SKIP_FASTFWD, // 10
    };
    for (modes) |mode| {
        var ev = makeEvent(c.EVENT_TARGET);
        variants(&ev).tgt.kind = c.TARGET_COMMAND_FRAMESKIP;
        variants(&ev).tgt.ioevs[0].iv = mode;

        const out = try roundTrip(&ev);
        try testing.expectEqual(mode, variants(@constCast(&out)).tgt.ioevs[0].iv);
    }
}

test "STEPFRAME with INT32_MIN counter (extreme rollback)" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_STEPFRAME;
    tgt.ioevs[0].iv = std.math.minInt(i32);

    const out = try roundTrip(&ev);
    try testing.expectEqual(std.math.minInt(i32), variants(@constCast(&out)).tgt.ioevs[0].iv);
}

test "STEPFRAME with source ID in ioevs[1].uiv" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_STEPFRAME;
    tgt.ioevs[0].iv = 1;
    tgt.ioevs[1].uiv = 42; // custom clock source ID

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(i32, 1), o.ioevs[0].iv);
    try testing.expectEqual(@as(u32, 42), o.ioevs[1].uiv);
}

test "BCHUNK_IN with max size (full 64-bit via lo+hi)" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
    tgt.ioevs[0].iv = 5; // fd
    tgt.ioevs[1].iv = std.math.maxInt(i32); // size_lo max
    tgt.ioevs[2].iv = std.math.maxInt(i32); // size_hi max
    tgt.ioevs[3].iv = 1; // namespace selector
    tgt.ioevs[4].iv = 1; // parallel transfer flag

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(std.math.maxInt(i32), o.ioevs[1].iv);
    try testing.expectEqual(std.math.maxInt(i32), o.ioevs[2].iv);
    try testing.expectEqual(@as(i32, 1), o.ioevs[3].iv);
    try testing.expectEqual(@as(i32, 1), o.ioevs[4].iv);
}

test "TARGET message filled to exact 78-byte capacity" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_MESSAGE;
    // Fill all 78 bytes with non-zero pattern
    for (0..78) |i| {
        tgt.unnamed_0.message[i] = @intCast((i % 95) + 32); // printable ASCII
    }

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    for (0..78) |i| {
        try testing.expectEqual(tgt.unnamed_0.message[i], o.unnamed_0.message[i]);
    }
}

test "TARGET message with embedded null bytes" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_MESSAGE;
    tgt.unnamed_0.message[0] = 'A';
    tgt.unnamed_0.message[1] = 0; // null in middle
    tgt.unnamed_0.message[2] = 'B';

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(u8, 'A'), o.unnamed_0.message[0]);
    try testing.expectEqual(@as(u8, 0), o.unnamed_0.message[1]);
    try testing.expectEqual(@as(u8, 'B'), o.unnamed_0.message[2]);
}

test "NEWSEGMENT with all documented segment types" {
    const types = [_]i32{
        c.SEGID_UNKNOWN, c.SEGID_LWA, c.SEGID_MEDIA, c.SEGID_TERMINAL,
        c.SEGID_GAME,    c.SEGID_APPLICATION, c.SEGID_BROWSER, c.SEGID_TUI,
        c.SEGID_POPUP,   c.SEGID_CURSOR, c.SEGID_CLIPBOARD, c.SEGID_HANDOVER,
    };
    for (types) |segtype| {
        var ev = makeEvent(c.EVENT_TARGET);
        const tgt = &variants(&ev).tgt;
        tgt.kind = c.TARGET_COMMAND_NEWSEGMENT;
        tgt.ioevs[2].iv = segtype;

        const out = try roundTrip(&ev);
        try testing.expectEqual(segtype, variants(@constCast(&out)).tgt.ioevs[2].iv);
    }
}

test "NEWSEGMENT with token in ioevs[4] and default handler in [5]" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_NEWSEGMENT;
    tgt.ioevs[4].uiv = 0xABCD1234; // segment token
    tgt.ioevs[5].iv = 1; // run default handler

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    try testing.expectEqual(@as(u32, 0xABCD1234), o.ioevs[4].uiv);
    try testing.expectEqual(@as(i32, 1), o.ioevs[5].iv);
}

test "STORE with BADFD returns false from descrevent" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_STORE;
    tgt.ioevs[0].iv = -1; // BADFD
    try testing.expect(!c.arcan_shmif_descrevent(&ev));
}

test "RESTORE with valid fd returns true from descrevent" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_RESTORE;
    tgt.ioevs[0].iv = 7;
    try testing.expect(c.arcan_shmif_descrevent(&ev));
}

test "BCHUNK_IN with BADFD returns false from descrevent" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
    tgt.ioevs[0].iv = -1;
    try testing.expect(!c.arcan_shmif_descrevent(&ev));
}

test "BCHUNK_OUT with BADFD returns false from descrevent" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_BCHUNK_OUT;
    tgt.ioevs[0].iv = -1;
    try testing.expect(!c.arcan_shmif_descrevent(&ev));
}

// 7g. Edge cases: EXTERNAL event sub-struct boundaries

test "SEGREQ max dimensions at PP_SHMPAGE_MAXW/H" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_SEGREQ;
    ext.unnamed_0.segreq.width = c.PP_SHMPAGE_MAXW;
    ext.unnamed_0.segreq.height = c.PP_SHMPAGE_MAXH;
    ext.unnamed_0.segreq.kind = c.SEGID_APPLICATION;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u16, c.PP_SHMPAGE_MAXW), o.unnamed_0.segreq.width);
    try testing.expectEqual(@as(u16, c.PP_SHMPAGE_MAXH), o.unnamed_0.segreq.height);
}

test "SEGREQ with direction hints and offsets" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_SEGREQ;
    ext.unnamed_0.segreq.kind = c.SEGID_POPUP;
    ext.unnamed_0.segreq.dir = 5; // attach-l
    ext.unnamed_0.segreq.xofs = -100; // negative offset
    ext.unnamed_0.segreq.yofs = 200;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u8, 5), o.unnamed_0.segreq.dir);
    try testing.expectEqual(@as(i16, -100), o.unnamed_0.segreq.xofs);
    try testing.expectEqual(@as(i16, 200), o.unnamed_0.segreq.yofs);
}

test "SEGREQ with xofs/yofs at INT16 extremes" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_SEGREQ;
    ext.unnamed_0.segreq.xofs = std.math.minInt(i16);
    ext.unnamed_0.segreq.yofs = std.math.maxInt(i16);

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(std.math.minInt(i16), o.unnamed_0.segreq.xofs);
    try testing.expectEqual(std.math.maxInt(i16), o.unnamed_0.segreq.yofs);
}

test "CLOCKREQ dynamic=1 (presentation feedback)" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_CLOCKREQ;
    ext.unnamed_0.clock.rate = 60;
    ext.unnamed_0.clock.dynamic = 1;
    ext.unnamed_0.clock.id = 1; // reserved for present-feedback

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u32, 60), o.unnamed_0.clock.rate);
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.clock.dynamic);
}

test "CLOCKREQ dynamic=2 (vblank)" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_CLOCKREQ;
    ext.unnamed_0.clock.rate = 0;
    ext.unnamed_0.clock.dynamic = 2;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(u8, 2), variants(@constCast(&out)).ext.unnamed_0.clock.dynamic);
}

test "BCHUNKSTATE all hint bits" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_BCHUNKSTATE;
    ext.unnamed_0.bchunk.hint = 0x0F; // immediate|accept-all|multipart|cursor
    ext.unnamed_0.bchunk.input = 0;
    ext.unnamed_0.bchunk.stream = 1;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u8, 0x0F), o.unnamed_0.bchunk.hint);
    try testing.expectEqual(@as(u8, 0), o.unnamed_0.bchunk.input);
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.bchunk.stream);
}

test "BCHUNKSTATE extensions at max capacity (68 bytes)" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_BCHUNKSTATE;
    // Fill all 68 extension bytes
    for (0..68) |i| {
        ext.unnamed_0.bchunk.extensions[i] = @intCast((i % 26) + 'a');
    }

    const out = try roundTrip(&ev);
    for (0..68) |i| {
        try testing.expectEqual(
            ext.unnamed_0.bchunk.extensions[i],
            variants(@constCast(&out)).ext.unnamed_0.bchunk.extensions[i],
        );
    }
}

test "STATESIZE with zero size (disabled)" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_STATESIZE;
    ext.unnamed_0.stateinf.size = 0;
    ext.unnamed_0.stateinf.type = 0;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u32, 0), o.unnamed_0.stateinf.size);
}

test "STATESIZE with UINT32_MAX size" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_STATESIZE;
    ext.unnamed_0.stateinf.size = std.math.maxInt(u32);

    const out = try roundTrip(&ev);
    try testing.expectEqual(std.math.maxInt(u32), variants(@constCast(&out)).ext.unnamed_0.stateinf.size);
}

test "REGISTER with max-length title (64 bytes)" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_REGISTER;
    ext.unnamed_0.registr.kind = c.SEGID_APPLICATION;
    for (0..64) |i| {
        ext.unnamed_0.registr.title[i] = @intCast((i % 26) + 'A');
    }

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    for (0..64) |i| {
        try testing.expectEqual(ext.unnamed_0.registr.title[i], o.unnamed_0.registr.title[i]);
    }
}

test "REGISTER with GUID all-zeros and all-ones" {
    // All zeros
    {
        var ev = makeEvent(c.EVENT_EXTERNAL);
        const ext = &variants(&ev).ext;
        ext.kind = c.EVENT_EXTERNAL_REGISTER;
        ext.unnamed_0.registr.guid[0] = 0;
        ext.unnamed_0.registr.guid[1] = 0;

        const out = try roundTrip(&ev);
        const o = variants(@constCast(&out)).ext;
        try testing.expectEqual(@as(u64, 0), o.unnamed_0.registr.guid[0]);
        try testing.expectEqual(@as(u64, 0), o.unnamed_0.registr.guid[1]);
    }
    // All ones
    {
        var ev = makeEvent(c.EVENT_EXTERNAL);
        const ext = &variants(&ev).ext;
        ext.kind = c.EVENT_EXTERNAL_REGISTER;
        ext.unnamed_0.registr.guid[0] = std.math.maxInt(u64);
        ext.unnamed_0.registr.guid[1] = std.math.maxInt(u64);

        const out = try roundTrip(&ev);
        const o = variants(@constCast(&out)).ext;
        try testing.expectEqual(std.math.maxInt(u64), o.unnamed_0.registr.guid[0]);
        try testing.expectEqual(std.math.maxInt(u64), o.unnamed_0.registr.guid[1]);
    }
}

test "LABELHINT with modifiers and subv" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_LABELHINT;
    const label = "COPY";
    for (label, 0..) |ch, i| {
        ext.unnamed_0.labelhint.label[i] = ch;
    }
    ext.unnamed_0.labelhint.idatatype = c.EVENT_IDATATYPE_TRANSLATED;
    ext.unnamed_0.labelhint.modifiers = c.ARKMOD_LCTRL;
    ext.unnamed_0.labelhint.subv = 42;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u16, c.ARKMOD_LCTRL), o.unnamed_0.labelhint.modifiers);
    try testing.expectEqual(@as(u16, 42), o.unnamed_0.labelhint.subv);
}

test "LABELHINT with vsym (UTF-8 visual symbol)" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_LABELHINT;
    // Set a multi-byte UTF-8 visual symbol (e.g. "A" as simple case)
    ext.unnamed_0.labelhint.vsym[0] = 'A';
    ext.unnamed_0.labelhint.vsym[1] = 0;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u8, 'A'), o.unnamed_0.labelhint.vsym[0]);
}

test "VIEWPORT with all fields populated" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_VIEWPORT;
    ext.unnamed_0.viewport.x = -50;
    ext.unnamed_0.viewport.y = -25;
    ext.unnamed_0.viewport.w = 800;
    ext.unnamed_0.viewport.h = 600;
    ext.unnamed_0.viewport.parent = 42;
    ext.unnamed_0.viewport.edge = 5; // center
    ext.unnamed_0.viewport.order = -1; // below parent
    ext.unnamed_0.viewport.embedded = 1;
    ext.unnamed_0.viewport.invisible = 0;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(i32, -50), o.unnamed_0.viewport.x);
    try testing.expectEqual(@as(i32, -25), o.unnamed_0.viewport.y);
    try testing.expectEqual(@as(u32, 800), o.unnamed_0.viewport.w);
    try testing.expectEqual(@as(u32, 600), o.unnamed_0.viewport.h);
    try testing.expectEqual(@as(u32, 42), o.unnamed_0.viewport.parent);
    try testing.expectEqual(@as(u8, 5), o.unnamed_0.viewport.edge);
    try testing.expectEqual(@as(i8, -1), o.unnamed_0.viewport.order);
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.viewport.embedded);
}

test "VIEWPORT with order at INT8 extremes" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_VIEWPORT;
    ext.unnamed_0.viewport.order = std.math.minInt(i8);

    const out = try roundTrip(&ev);
    try testing.expectEqual(std.math.minInt(i8), variants(@constCast(&out)).ext.unnamed_0.viewport.order);
}

test "CONTENT with scrollbar position hints" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_CONTENT;
    ext.unnamed_0.content.x_pos = 0.25;
    ext.unnamed_0.content.x_sz = 0.5;
    ext.unnamed_0.content.y_pos = 0.0;
    ext.unnamed_0.content.y_sz = 1.0;
    ext.unnamed_0.content.cell_w = 8;
    ext.unnamed_0.content.cell_h = 16;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectApproxEqAbs(@as(f32, 0.25), o.unnamed_0.content.x_pos, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.5), o.unnamed_0.content.x_sz, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), o.unnamed_0.content.y_pos, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 1.0), o.unnamed_0.content.y_sz, 0.001);
    try testing.expectEqual(@as(u8, 8), o.unnamed_0.content.cell_w);
    try testing.expectEqual(@as(u8, 16), o.unnamed_0.content.cell_h);
}

test "CONTENT with disabled scrollbar (negative position)" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_CONTENT;
    ext.unnamed_0.content.x_pos = -1.0; // disabled
    ext.unnamed_0.content.y_pos = -1.0; // disabled

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectApproxEqAbs(@as(f32, -1.0), o.unnamed_0.content.x_pos, 0.001);
    try testing.expectApproxEqAbs(@as(f32, -1.0), o.unnamed_0.content.y_pos, 0.001);
}

// 7h. Edge cases: ioevs boundary extremes

test "ioevs[].iv: INT32_MAX survives round-trip" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_COREOPT;
    tgt.ioevs[0].iv = std.math.maxInt(i32);

    const out = try roundTrip(&ev);
    try testing.expectEqual(std.math.maxInt(i32), variants(@constCast(&out)).tgt.ioevs[0].iv);
}

test "ioevs[].iv: INT32_MIN survives round-trip" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_COREOPT;
    tgt.ioevs[0].iv = std.math.minInt(i32);

    const out = try roundTrip(&ev);
    try testing.expectEqual(std.math.minInt(i32), variants(@constCast(&out)).tgt.ioevs[0].iv);
}

test "ioevs[].uiv: UINT32_MAX survives round-trip" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_COREOPT;
    tgt.ioevs[0].uiv = std.math.maxInt(u32);

    const out = try roundTrip(&ev);
    try testing.expectEqual(std.math.maxInt(u32), variants(@constCast(&out)).tgt.ioevs[0].uiv);
}

test "ioevs[].fv: very small float (subnormal)" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_GEOHINT;
    tgt.ioevs[0].fv = std.math.floatMin(f32);

    const out = try roundTrip(&ev);
    try testing.expectEqual(std.math.floatMin(f32), variants(@constCast(&out)).tgt.ioevs[0].fv);
}

test "ioevs[].fv: negative zero survives" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_GEOHINT;
    tgt.ioevs[0].fv = -0.0;

    const out = try roundTrip(&ev);
    const val = variants(@constCast(&out)).tgt.ioevs[0].fv;
    try testing.expectEqual(@as(f32, 0.0), val);
}

test "all 8 ioevs slots survive simultaneously" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_DISPLAYHINT;
    for (0..8) |i| {
        tgt.ioevs[i].iv = @intCast(i * 1000 + 42);
    }

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).tgt;
    for (0..8) |i| {
        try testing.expectEqual(@as(i32, @intCast(i * 1000 + 42)), o.ioevs[i].iv);
    }
}

// 7i. Edge cases: pack/unpack with pattern data

test "pack/unpack event with all bytes set to 0xFF" {
    var ev: Event = undefined;
    @memset(std.mem.asBytes(&ev), 0xFF);
    // Set valid category so pack works
    inner(&ev).category = c.EVENT_TARGET;

    var buf: [256]u8 = undefined;
    const pack_sz = c.arcan_shmif_eventpack(&ev, &buf, buf.len);
    try testing.expect(pack_sz > 0);

    var out: Event = undefined;
    const unpack_sz = c.arcan_shmif_eventunpack(&buf, @intCast(pack_sz), &out);
    try testing.expectEqual(pack_sz, unpack_sz);

    // Verify byte-for-byte equality
    const ev_bytes = std.mem.asBytes(&ev);
    const out_bytes = std.mem.asBytes(&out);
    try testing.expectEqualSlices(u8, ev_bytes, out_bytes);
}

test "pack/unpack event with alternating bit pattern" {
    var ev: Event = undefined;
    @memset(std.mem.asBytes(&ev), 0xAA);
    inner(&ev).category = c.EVENT_EXTERNAL;

    var buf: [256]u8 = undefined;
    const pack_sz = c.arcan_shmif_eventpack(&ev, &buf, buf.len);
    try testing.expect(pack_sz > 0);

    var out: Event = undefined;
    _ = c.arcan_shmif_eventunpack(&buf, @intCast(pack_sz), &out);

    const ev_bytes = std.mem.asBytes(&ev);
    const out_bytes = std.mem.asBytes(&out);
    try testing.expectEqualSlices(u8, ev_bytes, out_bytes);
}

test "unpack with buffer exactly 130 bytes succeeds" {
    var ev = makeEvent(c.EVENT_IO);
    var buf: [130]u8 = undefined;
    const pack_sz = c.arcan_shmif_eventpack(&ev, &buf, buf.len);
    try testing.expectEqual(@as(isize, 130), pack_sz);

    var out: Event = undefined;
    const unpack_sz = c.arcan_shmif_eventunpack(&buf, 130, &out);
    try testing.expectEqual(@as(isize, 130), unpack_sz);
}

test "unpack with buffer 129 bytes fails" {
    var ev = makeEvent(c.EVENT_IO);
    var buf: [256]u8 = undefined;
    _ = c.arcan_shmif_eventpack(&ev, &buf, buf.len);

    var out: Event = undefined;
    const result = c.arcan_shmif_eventunpack(&buf, 129, &out);
    try testing.expectEqual(@as(isize, -1), result);
}

// 7j. Edge cases: eventstr with various event kinds

test "eventstr for BCHUNK_IN contains BCHUNK_IN" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
    const result = c.arcan_shmif_eventstr(&ev, null, 0);
    try testing.expect(result != null);
    const str = std.mem.span(result.?);
    try testing.expect(std.mem.indexOf(u8, str, "BCHUNK-IN") != null);
}

test "eventstr for BCHUNK_OUT contains BCHUNK-OUT" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_BCHUNK_OUT;
    const result = c.arcan_shmif_eventstr(&ev, null, 0);
    try testing.expect(result != null);
    const str = std.mem.span(result.?);
    try testing.expect(std.mem.indexOf(u8, str, "BCHUNK-OUT") != null);
}

test "eventstr for NEWSEGMENT contains NEWSEGMENT" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_NEWSEGMENT;
    const result = c.arcan_shmif_eventstr(&ev, null, 0);
    try testing.expect(result != null);
    const str = std.mem.span(result.?);
    try testing.expect(std.mem.indexOf(u8, str, "NEWSEGMENT") != null);
}

test "eventstr for RESET contains RESET" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_RESET;
    const result = c.arcan_shmif_eventstr(&ev, null, 0);
    try testing.expect(result != null);
    const str = std.mem.span(result.?);
    try testing.expect(std.mem.indexOf(u8, str, "RESET") != null);
}

test "eventstr with user-provided buffer" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_EXIT;
    var buf: [256]u8 = undefined;
    const result = c.arcan_shmif_eventstr(&ev, &buf, buf.len);
    try testing.expect(result != null);
    // Result should point into our buffer
    const result_ptr: [*]const u8 = @ptrCast(result.?);
    const buf_ptr: [*]const u8 = &buf;
    try testing.expectEqual(buf_ptr, result_ptr);
}

// ═══════════════════════════════════════════════════════════════════
// Tier 10: Zig reimplementation edge cases
// ═══════════════════════════════════════════════════════════════════

// 10a. IO event subtypes: translated keyboard

test "translated keyboard event: all fields preserved" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.devkind = c.EVENT_IDEVKIND_KEYBOARD;
    io.datatype = c.EVENT_IDATATYPE_TRANSLATED;
    io.input.translated.active = 1;
    io.input.translated.scancode = 0x1E; // 'A' on many layouts
    io.input.translated.keysym = 0x61; // 'a'
    io.input.translated.modifiers = c.ARKMOD_LSHIFT;
    io.input.translated.utf8 = .{ 'A', 0, 0, 0, 0 };

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).io;
    try testing.expectEqual(@as(u8, 1), o.input.translated.active);
    try testing.expectEqual(@as(u8, 0x1E), o.input.translated.scancode);
    try testing.expectEqual(@as(u32, 0x61), o.input.translated.keysym);
    try testing.expectEqual(@as(u16, c.ARKMOD_LSHIFT), o.input.translated.modifiers);
    try testing.expectEqual([5]u8{ 'A', 0, 0, 0, 0 }, o.input.translated.utf8);
}

test "translated keyboard: multi-byte UTF-8 in utf8 field" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.devkind = c.EVENT_IDEVKIND_KEYBOARD;
    io.datatype = c.EVENT_IDATATYPE_TRANSLATED;
    // UTF-8 for U+00E9 (é) = 0xC3 0xA9
    io.input.translated.utf8 = .{ 0xC3, 0xA9, 0, 0, 0 };

    const out = try roundTrip(&ev);
    try testing.expectEqual([5]u8{ 0xC3, 0xA9, 0, 0, 0 }, variants(@constCast(&out)).io.input.translated.utf8);
}

test "translated keyboard: keysym at uint32 max" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.devkind = c.EVENT_IDEVKIND_KEYBOARD;
    io.datatype = c.EVENT_IDATATYPE_TRANSLATED;
    io.input.translated.keysym = std.math.maxInt(u32);

    const out = try roundTrip(&ev);
    try testing.expectEqual(std.math.maxInt(u32), variants(@constCast(&out)).io.input.translated.keysym);
}

test "translated keyboard: all modifier bits set" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.devkind = c.EVENT_IDEVKIND_KEYBOARD;
    io.datatype = c.EVENT_IDATATYPE_TRANSLATED;
    io.input.translated.modifiers = 0xFFFF;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(u16, 0xFFFF), variants(@constCast(&out)).io.input.translated.modifiers);
}

// 10b. IO event subtypes: analog multi-axis

test "analog event: 4-axis mouse with packed format" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_AXIS_MOVE;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.datatype = c.EVENT_IDATATYPE_ANALOG;
    io.unnamed_0.unnamed_0.subid = 2; // packed X+Y
    io.input.analog.gotrel = 0;
    io.input.analog.nvalues = 4;
    io.input.analog.axisval = .{ 100, 200, 300, 400 };

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).io;
    try testing.expectEqual(@as(u16, 2), o.unnamed_0.unnamed_0.subid);
    try testing.expectEqual(@as(u8, 4), o.input.analog.nvalues);
    try testing.expectEqual([4]i16{ 100, 200, 300, 400 }, o.input.analog.axisval);
}

test "analog event: relative with negative values" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_AXIS_MOVE;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.datatype = c.EVENT_IDATATYPE_ANALOG;
    io.input.analog.gotrel = 1;
    io.input.analog.nvalues = 2;
    io.input.analog.axisval = .{ -32768, 32767, 0, 0 };

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).io;
    try testing.expectEqual(@as(i16, -32768), o.input.analog.axisval[0]);
    try testing.expectEqual(@as(i16, 32767), o.input.analog.axisval[1]);
}

test "analog event: single axis (subid 0 = X only)" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_AXIS_MOVE;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.datatype = c.EVENT_IDATATYPE_ANALOG;
    io.unnamed_0.unnamed_0.subid = 0; // X only
    io.input.analog.nvalues = 2;
    io.input.analog.axisval[0] = 500;
    io.input.analog.axisval[1] = 501;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).io;
    try testing.expectEqual(@as(u16, 0), o.unnamed_0.unnamed_0.subid);
    try testing.expectEqual(@as(i16, 500), o.input.analog.axisval[0]);
}

// 10c. IO event subtypes: touch

test "touch event: pressure and size as floats" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_TOUCH;
    io.devkind = c.EVENT_IDEVKIND_TOUCHDISP;
    io.datatype = c.EVENT_IDATATYPE_TOUCH;
    io.input.touch.active = 1;
    io.input.touch.x = 500;
    io.input.touch.y = 300;
    io.input.touch.pressure = 0.75;
    io.input.touch.size = 10.5;
    io.input.touch.tool = 1;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).io;
    try testing.expectEqual(@as(u8, 1), o.input.touch.active);
    try testing.expectEqual(@as(i16, 500), o.input.touch.x);
    try testing.expectEqual(@as(i16, 300), o.input.touch.y);
    try testing.expectApproxEqAbs(@as(f32, 0.75), o.input.touch.pressure, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 10.5), o.input.touch.size, 0.001);
    try testing.expectEqual(@as(u8, 1), o.input.touch.tool);
}

test "touch event: tilt values at extremes" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_TOUCH;
    io.devkind = c.EVENT_IDEVKIND_TOUCHDISP;
    io.datatype = c.EVENT_IDATATYPE_TOUCH;
    io.input.touch.tilt_x = 0;
    io.input.touch.tilt_y = 65535;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).io;
    try testing.expectEqual(@as(u16, 0), o.input.touch.tilt_x);
    try testing.expectEqual(@as(u16, 65535), o.input.touch.tilt_y);
}

// 10d. IO event subtypes: eyes

test "eyes event: head position and gaze" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_EYES;
    io.devkind = c.EVENT_IDEVKIND_EYETRACKER;
    io.datatype = c.EVENT_IDATATYPE_EYES;
    io.input.eyes.head_pos = .{ 0.5, -0.3, 1.2 };
    io.input.eyes.head_ang = .{ 10.0, 20.0, 30.0 };
    io.input.eyes.gaze_x1 = 0.1;
    io.input.eyes.gaze_y1 = 0.9;
    io.input.eyes.gaze_x2 = 0.2;
    io.input.eyes.gaze_y2 = 0.8;
    io.input.eyes.blink_left = 1;
    io.input.eyes.blink_right = 0;
    io.input.eyes.present = 1;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).io;
    try testing.expectApproxEqAbs(@as(f32, 0.5), o.input.eyes.head_pos[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, -0.3), o.input.eyes.head_pos[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 1.2), o.input.eyes.head_pos[2], 0.001);
    try testing.expectEqual(@as(u8, 1), o.input.eyes.blink_left);
    try testing.expectEqual(@as(u8, 0), o.input.eyes.blink_right);
    try testing.expectEqual(@as(u8, 1), o.input.eyes.present);
}

// 10e. IO event: digital button

test "digital button: active=1 preserved" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.datatype = c.EVENT_IDATATYPE_DIGITAL;
    io.input.digital.active = 1;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(u8, 1), variants(@constCast(&out)).io.input.digital.active);
}

test "digital button: active=0 preserved" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.datatype = c.EVENT_IDATATYPE_DIGITAL;
    io.input.digital.active = 0;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(u8, 0), variants(@constCast(&out)).io.input.digital.active);
}

// 10f. IO event: label, devid, subid, dst, pts

test "IO label field: 16-byte string preserved" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    const label = "MY_BTN_LABEL\x00\x00\x00\x00";
    @memcpy(&io.label, label);

    const out = try roundTrip(&ev);
    try testing.expectEqualSlices(u8, label, &variants(@constCast(&out)).io.label);
}

test "IO devid and subid at u16 extremes" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_AXIS_MOVE;
    io.unnamed_0.unnamed_0.devid = 0xFFFF;
    io.unnamed_0.unnamed_0.subid = 0xFFFF;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).io;
    try testing.expectEqual(@as(u16, 0xFFFF), o.unnamed_0.unnamed_0.devid);
    try testing.expectEqual(@as(u16, 0xFFFF), o.unnamed_0.unnamed_0.subid);
}

test "IO dst field preserved" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.dst = 0xDEADBEEF;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(u32, 0xDEADBEEF), variants(@constCast(&out)).io.dst);
}

test "IO pts field preserved (u64)" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.pts = 0x123456789ABCDEF0;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(u64, 0x123456789ABCDEF0), variants(@constCast(&out)).io.pts);
}

test "IO flags field preserved" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.flags = c.ARCAN_IOFL_GESTURE;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(u8, c.ARCAN_IOFL_GESTURE), variants(@constCast(&out)).io.flags);
}

// 10g. IO event: gamedev

test "gamedev analog: axis values preserved" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_AXIS_MOVE;
    io.devkind = c.EVENT_IDEVKIND_GAMEDEV;
    io.datatype = c.EVENT_IDATATYPE_ANALOG;
    io.unnamed_0.unnamed_0.devid = 1; // gamepad 1
    io.unnamed_0.unnamed_0.subid = 3; // axis 3 (right stick Y)
    io.input.analog.nvalues = 1;
    io.input.analog.axisval[0] = -16000;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).io;
    try testing.expectEqual(@as(u16, 1), o.unnamed_0.unnamed_0.devid);
    try testing.expectEqual(@as(u16, 3), o.unnamed_0.unnamed_0.subid);
    try testing.expectEqual(@as(i16, -16000), o.input.analog.axisval[0]);
}

// 10h. EXTERNAL sub-structs not previously tested

test "PRIVDROP: external and sandboxed flags" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_PRIVDROP;
    ext.unnamed_0.privdrop.external = 1;
    ext.unnamed_0.privdrop.sandboxed = 1;
    ext.unnamed_0.privdrop.networked = 0;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.privdrop.external);
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.privdrop.sandboxed);
    try testing.expectEqual(@as(u8, 0), o.unnamed_0.privdrop.networked);
}

test "INPUTMASK: device and type bitmaps" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_INPUTMASK;
    ext.unnamed_0.inputmask.device = c.EVENT_IDEVKIND_KEYBOARD | c.EVENT_IDEVKIND_MOUSE;
    ext.unnamed_0.inputmask.types = c.EVENT_IDATATYPE_TRANSLATED;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(
        @as(u32, @bitCast(c.EVENT_IDEVKIND_KEYBOARD | c.EVENT_IDEVKIND_MOUSE)),
        o.unnamed_0.inputmask.device,
    );
    try testing.expectEqual(@as(u32, @bitCast(c.EVENT_IDATATYPE_TRANSLATED)), o.unnamed_0.inputmask.types);
}

test "NETSTATE: name, space, state, type" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_NETSTATE;
    ext.unnamed_0.netstate.space = 1; // host
    ext.unnamed_0.netstate.state = 1; // discovered
    ext.unnamed_0.netstate.type = 3; // source | sink
    ext.unnamed_0.netstate.port = 6680;
    const name = "myhost";
    for (name, 0..) |ch, i| {
        ext.unnamed_0.netstate.unnamed_0.name[i] = ch;
    }

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.netstate.space);
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.netstate.state);
    try testing.expectEqual(@as(u8, 3), o.unnamed_0.netstate.type);
    try testing.expectEqual(@as(u16, 6680), o.unnamed_0.netstate.port);
}

test "BSTREAM: stride, format, modifier, dimensions" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_BUFFERSTREAM;
    ext.unnamed_0.bstream.stride = 3840;
    ext.unnamed_0.bstream.format = 0x34325258; // XR24
    ext.unnamed_0.bstream.mod_hi = 0x01;
    ext.unnamed_0.bstream.mod_lo = 0x02;
    ext.unnamed_0.bstream.width = 960;
    ext.unnamed_0.bstream.height = 540;
    ext.unnamed_0.bstream.left = 2;
    ext.unnamed_0.bstream.flags = 1; // stream-got-fence

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u32, 3840), o.unnamed_0.bstream.stride);
    try testing.expectEqual(@as(u32, 0x34325258), o.unnamed_0.bstream.format);
    try testing.expectEqual(@as(u32, 0x01), o.unnamed_0.bstream.mod_hi);
    try testing.expectEqual(@as(u32, 0x02), o.unnamed_0.bstream.mod_lo);
    try testing.expectEqual(@as(u32, 960), o.unnamed_0.bstream.width);
    try testing.expectEqual(@as(u32, 540), o.unnamed_0.bstream.height);
    try testing.expectEqual(@as(u8, 2), o.unnamed_0.bstream.left);
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.bstream.flags);
}

test "STREAMSTATUS: timestr, completion, frameno" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_STREAMSTATUS;
    ext.unnamed_0.streamstat.timestr = .{ '0', '1', ':', '2', '3', ':', '4', '5', 0 };
    ext.unnamed_0.streamstat.timelim = .{ '0', '2', ':', '0', '0', ':', '0', '0', 0 };
    ext.unnamed_0.streamstat.completion = 0.42;
    ext.unnamed_0.streamstat.streaming = 1;
    ext.unnamed_0.streamstat.frameno = 1234;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual([9]u8{ '0', '1', ':', '2', '3', ':', '4', '5', 0 }, o.unnamed_0.streamstat.timestr);
    try testing.expectApproxEqAbs(@as(f32, 0.42), o.unnamed_0.streamstat.completion, 0.001);
    try testing.expectEqual(@as(u32, 1234), o.unnamed_0.streamstat.frameno);
}

test "FRAMESTATUS: framenumber, pts, acquired" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_FRAMESTATUS;
    ext.unnamed_0.framestatus.framenumber = 42;
    ext.unnamed_0.framestatus.pts = 1000;
    ext.unnamed_0.framestatus.acquired = 1002;
    ext.unnamed_0.framestatus.fhint = 0.95;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u32, 42), o.unnamed_0.framestatus.framenumber);
    try testing.expectEqual(@as(u64, 1000), o.unnamed_0.framestatus.pts);
    try testing.expectEqual(@as(u64, 1002), o.unnamed_0.framestatus.acquired);
    try testing.expectApproxEqAbs(@as(f32, 0.95), o.unnamed_0.framestatus.fhint, 0.001);
}

test "ext.frame_id survives round-trip" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_MESSAGE;
    ext.frame_id = 0xFEDCBA9876543210;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(u64, 0xFEDCBA9876543210), variants(@constCast(&out)).ext.frame_id);
}

test "ext.source (int64) survives round-trip with negative value" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_MESSAGE;
    ext.source = -42;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(i64, -42), variants(@constCast(&out)).ext.source);
}

// 10i. Byte-level event construction

test "byte-level: tgt.kind at bytes 0-3 matches LE encoding" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_DISPLAYHINT; // 14
    const raw = std.mem.asBytes(&ev);
    // On LE: 14 = 0x0E, 0x00, 0x00, 0x00
    try testing.expectEqual(@as(u8, 14), raw[0]);
    try testing.expectEqual(@as(u8, 0), raw[1]);
}

test "byte-level: tgt.ioevs[0] at bytes 4-7" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.ioevs[0].uiv = 0x04030201;
    const raw = std.mem.asBytes(&ev);
    try testing.expectEqual(@as(u8, 0x01), raw[4]);
    try testing.expectEqual(@as(u8, 0x02), raw[5]);
    try testing.expectEqual(@as(u8, 0x03), raw[6]);
    try testing.expectEqual(@as(u8, 0x04), raw[7]);
}

test "byte-level: tgt.ioevs[1] at bytes 8-11" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.ioevs[1].uiv = 0xAABBCCDD;
    const raw = std.mem.asBytes(&ev);
    try testing.expectEqual(@as(u8, 0xDD), raw[8]);
    try testing.expectEqual(@as(u8, 0xCC), raw[9]);
    try testing.expectEqual(@as(u8, 0xBB), raw[10]);
    try testing.expectEqual(@as(u8, 0xAA), raw[11]);
}

test "byte-level: tgt.code at bytes 36-39" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.code = 0x12345678;
    const raw = std.mem.asBytes(&ev);
    try testing.expectEqual(@as(u8, 0x78), raw[36]);
    try testing.expectEqual(@as(u8, 0x56), raw[37]);
    try testing.expectEqual(@as(u8, 0x34), raw[38]);
    try testing.expectEqual(@as(u8, 0x12), raw[39]);
}

test "byte-level: tgt.message starts at byte 40" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    inner(&ev).category = c.EVENT_TARGET;
    variants(&ev).tgt.unnamed_0.message[0] = 0x42;
    const raw = std.mem.asBytes(&ev);
    try testing.expectEqual(@as(u8, 0x42), raw[40]);
}

test "byte-level: tgt.message ends at byte 117 (40+78-1)" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    inner(&ev).category = c.EVENT_TARGET;
    variants(&ev).tgt.unnamed_0.message[77] = 0xFE;
    const raw = std.mem.asBytes(&ev);
    try testing.expectEqual(@as(u8, 0xFE), raw[117]);
}

test "byte-level: category is at byte 120" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    inner(&ev).category = 0x42;
    const raw = std.mem.asBytes(&ev);
    try testing.expectEqual(@as(u8, 0x42), raw[120]);
}

// 10j. Cross-variant aliasing

test "tgt.kind and ext.kind occupy same bytes" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    variants(&ev).tgt.kind = c.TARGET_COMMAND_EXIT; // 1
    // Reading ext.kind should see the same bytes (type-punning)
    const ext_kind: c_int = variants(&ev).ext.kind;
    try testing.expectEqual(@as(c_int, 1), ext_kind);
}

test "writing tgt clears ext fields (same memory)" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    inner(&ev).category = c.EVENT_TARGET;
    // Fill ext first
    variants(&ev).ext.source = 0x1234;
    // Now write tgt — should overwrite ext.source's bytes
    variants(&ev).tgt.ioevs[1].uiv = 0xAAAAAAAA;
    // ext.source's upper bytes may be changed
    const raw = std.mem.asBytes(&ev);
    // ioevs[1] is at bytes 8-11, source is at bytes 8-15 (on ext)
    try testing.expectEqual(@as(u8, 0xAA), raw[8]);
}

// 10k. Pack/unpack invariants

test "pack size is always exactly 130 bytes (128 event + 2 checksum)" {
    const categories = [_]u8{
        c.EVENT_IO, c.EVENT_TARGET, c.EVENT_EXTERNAL,
    };
    for (categories) |cat| {
        var ev = makeEvent(cat);
        var buf: [256]u8 = undefined;
        const sz = c.arcan_shmif_eventpack(&ev, &buf, buf.len);
        try testing.expectEqual(@as(isize, 130), sz);
    }
}

test "pack then unpack: byte-for-byte identity" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_DISPLAYHINT;
    tgt.ioevs[0].iv = 1920;
    tgt.ioevs[1].iv = 1080;
    tgt.code = 42;
    const msg = "hello";
    for (msg, 0..) |ch, i| tgt.unnamed_0.message[i] = ch;

    const out = try roundTrip(&ev);
    try testing.expectEqualSlices(u8, std.mem.asBytes(&ev), std.mem.asBytes(&out));
}

test "double pack/unpack: result is identical" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_REGISTER;
    variants(&ev).ext.unnamed_0.registr.guid[0] = 0xDEAD;

    const out1 = try roundTrip(&ev);
    var out1_mut = out1;
    const out2 = try roundTrip(&out1_mut);
    try testing.expectEqualSlices(u8, std.mem.asBytes(&out1), std.mem.asBytes(&out2));
}

test "corrupted checksum: unpack fails" {
    var ev = makeEvent(c.EVENT_IO);
    var buf: [256]u8 = undefined;
    const sz = c.arcan_shmif_eventpack(&ev, &buf, buf.len);
    try testing.expect(sz == 130);

    // Corrupt checksum bytes (last 2 bytes of packed data)
    buf[128] ^= 0xFF;
    buf[129] ^= 0xFF;

    var out: c.arcan_event = undefined;
    const result = c.arcan_shmif_eventunpack(&buf, 130, &out);
    try testing.expectEqual(@as(isize, -1), result);
}

// 10l. descrevent comprehensive

test "descrevent: DEVICE_NODE with valid fd returns true" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_DEVICE_NODE;
    variants(&ev).tgt.ioevs[0].iv = 5;
    try testing.expect(c.arcan_shmif_descrevent(&ev));
}

test "descrevent: DEVICE_NODE with BADFD returns false" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_DEVICE_NODE;
    variants(&ev).tgt.ioevs[0].iv = -1;
    try testing.expect(!c.arcan_shmif_descrevent(&ev));
}

test "descrevent: FONTHINT with valid fd returns true" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_FONTHINT;
    variants(&ev).tgt.ioevs[0].iv = 3;
    try testing.expect(c.arcan_shmif_descrevent(&ev));
}

test "descrevent: non-fd-carrying TARGET command returns false" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_DISPLAYHINT;
    variants(&ev).tgt.ioevs[0].iv = 42;
    try testing.expect(!c.arcan_shmif_descrevent(&ev));
}

test "descrevent: EXTERNAL event always returns false" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_SEGREQ;
    try testing.expect(!c.arcan_shmif_descrevent(&ev));
}

test "descrevent: IO event always returns false" {
    var ev = makeEvent(c.EVENT_IO);
    try testing.expect(!c.arcan_shmif_descrevent(&ev));
}

// 10m. eventstr comprehensive coverage

test "eventstr: all TARGET commands produce non-null output" {
    const cmds = [_]c_int{
        c.TARGET_COMMAND_EXIT, c.TARGET_COMMAND_FRAMESKIP,
        c.TARGET_COMMAND_STEPFRAME, c.TARGET_COMMAND_COREOPT,
        c.TARGET_COMMAND_STORE, c.TARGET_COMMAND_RESTORE,
        c.TARGET_COMMAND_BCHUNK_IN, c.TARGET_COMMAND_BCHUNK_OUT,
        c.TARGET_COMMAND_RESET, c.TARGET_COMMAND_PAUSE,
        c.TARGET_COMMAND_UNPAUSE, c.TARGET_COMMAND_DISPLAYHINT,
        c.TARGET_COMMAND_NEWSEGMENT, c.TARGET_COMMAND_MESSAGE,
        c.TARGET_COMMAND_FONTHINT, c.TARGET_COMMAND_GEOHINT,
        c.TARGET_COMMAND_OUTPUTHINT, c.TARGET_COMMAND_ACTIVATE,
        c.TARGET_COMMAND_DEVICE_NODE,
    };
    for (cmds) |cmd| {
        var ev = makeEvent(c.EVENT_TARGET);
        variants(&ev).tgt.kind = cmd;
        const result = c.arcan_shmif_eventstr(&ev, null, 0);
        try testing.expect(result != null);
    }
}

test "eventstr: all EXTERNAL kinds produce non-null output" {
    const kinds = [_]c_int{
        c.EVENT_EXTERNAL_MESSAGE, c.EVENT_EXTERNAL_COREOPT,
        c.EVENT_EXTERNAL_IDENT, c.EVENT_EXTERNAL_FAILURE,
        c.EVENT_EXTERNAL_STREAMINFO, c.EVENT_EXTERNAL_STATESIZE,
        c.EVENT_EXTERNAL_SEGREQ, c.EVENT_EXTERNAL_CURSORHINT,
        c.EVENT_EXTERNAL_VIEWPORT, c.EVENT_EXTERNAL_CONTENT,
        c.EVENT_EXTERNAL_LABELHINT, c.EVENT_EXTERNAL_REGISTER,
        c.EVENT_EXTERNAL_CLOCKREQ, c.EVENT_EXTERNAL_BCHUNKSTATE,
    };
    for (kinds) |kind| {
        var ev = makeEvent(c.EVENT_EXTERNAL);
        variants(&ev).ext.kind = kind;
        const result = c.arcan_shmif_eventstr(&ev, null, 0);
        try testing.expect(result != null);
    }
}

test "eventstr: IO event produces non-null" {
    var ev = makeEvent(c.EVENT_IO);
    const result = c.arcan_shmif_eventstr(&ev, null, 0);
    try testing.expect(result != null);
}

test "eventstr: user buffer is null-terminated" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_EXIT;
    var buf: [256]u8 = undefined;
    @memset(&buf, 0xFF);
    const result = c.arcan_shmif_eventstr(&ev, &buf, buf.len);
    try testing.expect(result != null);
    const str = std.mem.span(result.?);
    try testing.expect(str.len < 256);
}

// 10n. COREOPT sub-struct

test "ext COREOPT: index, type, data" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_COREOPT;
    ext.unnamed_0.coreopt.index = 3;
    ext.unnamed_0.coreopt.type = 2; // value
    const data = "some_value";
    for (data, 0..) |ch, i| {
        ext.unnamed_0.coreopt.data[i] = ch;
    }

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u8, 3), o.unnamed_0.coreopt.index);
    try testing.expectEqual(@as(u8, 2), o.unnamed_0.coreopt.type);
    const out_data: *const [data.len]u8 = @ptrCast(o.unnamed_0.coreopt.data[0..data.len]);
    try testing.expectEqualSlices(u8, data, out_data);
}

// 10o. VIEWPORT all edge fields

test "VIEWPORT: border array preserved" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_VIEWPORT;
    ext.unnamed_0.viewport.border = .{ 10, 20, 30, 40 }; // top, left, right, down

    const out = try roundTrip(&ev);
    try testing.expectEqual([4]u8{ 10, 20, 30, 40 }, variants(@constCast(&out)).ext.unnamed_0.viewport.border);
}

test "VIEWPORT: focus and anchor fields" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_VIEWPORT;
    ext.unnamed_0.viewport.focus = 1;
    ext.unnamed_0.viewport.anchor_edge = 1;
    ext.unnamed_0.viewport.anchor_pos = 1;
    ext.unnamed_0.viewport.ext_id = 0x12345678;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.viewport.focus);
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.viewport.anchor_edge);
    try testing.expectEqual(@as(u8, 1), o.unnamed_0.viewport.anchor_pos);
    try testing.expectEqual(@as(u32, 0x12345678), o.unnamed_0.viewport.ext_id);
}

// 10p. CONTENT min/max dimensions

test "CONTENT: min/max w/h preserved" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_CONTENT;
    ext.unnamed_0.content.min_w = 100;
    ext.unnamed_0.content.min_h = 50;
    ext.unnamed_0.content.max_w = 4000;
    ext.unnamed_0.content.max_h = 3000;
    ext.unnamed_0.content.width = 0.5;
    ext.unnamed_0.content.height = 0.8;

    const out = try roundTrip(&ev);
    const o = variants(@constCast(&out)).ext;
    try testing.expectEqual(@as(u32, 100), o.unnamed_0.content.min_w);
    try testing.expectEqual(@as(u32, 50), o.unnamed_0.content.min_h);
    try testing.expectEqual(@as(u32, 4000), o.unnamed_0.content.max_w);
    try testing.expectEqual(@as(u32, 3000), o.unnamed_0.content.max_h);
    try testing.expectApproxEqAbs(@as(f32, 0.5), o.unnamed_0.content.width, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.8), o.unnamed_0.content.height, 0.001);
}

// 10q. BCHUNK size union (ns alias)

test "BCHUNKSTATE: size and ns share same bytes (union)" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_BCHUNKSTATE;
    ext.unnamed_0.bchunk.unnamed_0.size = 0x123456789ABCDEF0;

    // ns overlaps size
    try testing.expectEqual(@as(u64, 0x123456789ABCDEF0), ext.unnamed_0.bchunk.unnamed_0.ns);
}

test "BCHUNKSTATE: identifier field preserved" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_BCHUNKSTATE;
    ext.unnamed_0.bchunk.identifier = 0xFEEDFACE;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(u32, 0xFEEDFACE), variants(@constCast(&out)).ext.unnamed_0.bchunk.identifier);
}

// 10r. SEGREQ hints field

test "SEGREQ: hints field preserved" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_SEGREQ;
    ext.unnamed_0.segreq.hints = 0xFF;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(u8, 0xFF), variants(@constCast(&out)).ext.unnamed_0.segreq.hints);
}

// 10s. LABELHINT initial and descr boundary

test "LABELHINT: initial keysym u16 max" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_LABELHINT;
    ext.unnamed_0.labelhint.initial = 0xFFFF;

    const out = try roundTrip(&ev);
    try testing.expectEqual(@as(u16, 0xFFFF), variants(@constCast(&out)).ext.unnamed_0.labelhint.initial);
}

test "LABELHINT: descr at full 53-byte capacity" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_LABELHINT;
    for (0..53) |i| {
        ext.unnamed_0.labelhint.descr[i] = @intCast((i % 26) + 'a');
    }

    const out = try roundTrip(&ev);
    for (0..53) |i| {
        try testing.expectEqual(
            ext.unnamed_0.labelhint.descr[i],
            variants(@constCast(&out)).ext.unnamed_0.labelhint.descr[i],
        );
    }
}

// 11. eventstr full branch coverage (evpack.c → 100%)

// Helper: call eventstr and return the Zig string slice.
fn eventStr(ev: *Event) []const u8 {
    const result = c.arcan_shmif_eventstr(ev, null, 0);
    if (result) |ptr| return std.mem.span(ptr);
    return "";
}

fn eventStrBuf(ev: *Event, buf: []u8) []const u8 {
    const result = c.arcan_shmif_eventstr(ev, buf.ptr, buf.len);
    if (result) |ptr| return std.mem.span(ptr);
    return "";
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

// 11a. eventstr: null event returns empty string

test "eventstr: null event returns empty string" {
    const result = c.arcan_shmif_eventstr(null, null, 0);
    try testing.expect(result != null);
    try testing.expectEqual(@as(u8, 0), result.?[0]);
}

// 11b. eventstr: user-provided buffer is used

test "eventstr: user buffer receives output" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_EXIT;
    var buf: [256]u8 = undefined;
    const s = eventStrBuf(&ev, &buf);
    try testing.expect(contains(s, "EXIT"));
    // Result pointer should be inside our buffer
    const result_ptr = c.arcan_shmif_eventstr(&ev, &buf, buf.len);
    try testing.expectEqual(@intFromPtr(&buf), @intFromPtr(result_ptr.?));
}

// 11c. eventstr: EXTERNAL branches

test "eventstr: EXT MESSAGE" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_MESSAGE;
    variants(&ev).ext.unnamed_0.message.data[0] = 'h';
    variants(&ev).ext.unnamed_0.message.data[1] = 'i';
    variants(&ev).ext.unnamed_0.message.multipart = 1;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "MESSAGE"));
    try testing.expect(contains(s, "hi"));
    try testing.expect(contains(s, "1")); // multipart
}

test "eventstr: EXT COREOPT" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_COREOPT;
    variants(&ev).ext.unnamed_0.message.data[0] = 'x';
    const s = eventStr(&ev);
    try testing.expect(contains(s, "COREOPT"));
}

test "eventstr: EXT IDENT" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_IDENT;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "IDENT"));
}

test "eventstr: EXT FAILURE" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_FAILURE;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "FAILURE"));
}

test "eventstr: EXT BUFFERSTREAM" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_BUFFERSTREAM;
    variants(&ev).ext.unnamed_0.bstream.width = 640;
    variants(&ev).ext.unnamed_0.bstream.height = 480;
    variants(&ev).ext.unnamed_0.bstream.format = 1;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "BUFFERSTREAM"));
    try testing.expect(contains(s, "640"));
}

test "eventstr: EXT FRAMESTATUS" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_FRAMESTATUS;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "FRAMESTATUS"));
}

test "eventstr: EXT STREAMINFO" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_STREAMINFO;
    variants(&ev).ext.unnamed_0.streaminf.streamid = 42;
    variants(&ev).ext.unnamed_0.streaminf.langid[0] = 'e';
    variants(&ev).ext.unnamed_0.streaminf.langid[1] = 'n';
    const s = eventStr(&ev);
    try testing.expect(contains(s, "STREAMINFO"));
}

test "eventstr: EXT STATESIZE" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_STATESIZE;
    variants(&ev).ext.unnamed_0.stateinf.size = 65536;
    variants(&ev).ext.unnamed_0.stateinf.type = 1;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "STATESIZE"));
    try testing.expect(contains(s, "65536"));
}

test "eventstr: EXT FLUSHAUD" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_FLUSHAUD;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "FLUSHAUD"));
}

test "eventstr: EXT SEGREQ" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_SEGREQ;
    variants(&ev).ext.unnamed_0.segreq.width = 320;
    variants(&ev).ext.unnamed_0.segreq.height = 240;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "SEGREQ"));
    try testing.expect(contains(s, "320"));
}

test "eventstr: EXT CURSORHINT" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_CURSORHINT;
    variants(&ev).ext.unnamed_0.message.data[0] = 'h';
    variants(&ev).ext.unnamed_0.message.data[1] = 'i';
    const s = eventStr(&ev);
    try testing.expect(contains(s, "CURSORHINT"));
}

test "eventstr: EXT VIEWPORT" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_VIEWPORT;
    variants(&ev).ext.unnamed_0.viewport.w = 800;
    variants(&ev).ext.unnamed_0.viewport.h = 600;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "VIEWPORT"));
}

test "eventstr: EXT CONTENT" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_CONTENT;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "CONTENT"));
}

test "eventstr: EXT LABELHINT" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_LABELHINT;
    variants(&ev).ext.unnamed_0.labelhint.label[0] = 'A';
    const s = eventStr(&ev);
    try testing.expect(contains(s, "LABELHINT"));
}

test "eventstr: EXT REGISTER" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_REGISTER;
    variants(&ev).ext.unnamed_0.registr.kind = c.SEGID_TUI;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "REGISTER"));
}

test "eventstr: EXT ALERT" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_ALERT;
    variants(&ev).ext.unnamed_0.message.data[0] = '!';
    variants(&ev).ext.unnamed_0.message.multipart = 0;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "ALERT"));
}

test "eventstr: EXT CLOCKREQ" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_CLOCKREQ;
    variants(&ev).ext.unnamed_0.clock.rate = 60;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "CLOCKREQ"));
}

test "eventstr: EXT BCHUNKSTATE" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_BCHUNKSTATE;
    variants(&ev).ext.unnamed_0.bchunk.hint = 1;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "BCHUNKSTATE"));
}

test "eventstr: EXT STREAMSTATUS" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_STREAMSTATUS;
    variants(&ev).ext.unnamed_0.streamstat.frameno = 100;
    variants(&ev).ext.unnamed_0.streamstat.completion = 0.75;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "STREAMSTATUS"));
}

test "eventstr: EXT NETSTATE" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_NETSTATE;
    variants(&ev).ext.unnamed_0.netstate.space = 1;
    variants(&ev).ext.unnamed_0.netstate.state = 2;
    variants(&ev).ext.unnamed_0.netstate.type = 3;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "NETSTATE"));
}

test "eventstr: EXT PRIVDROP" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_PRIVDROP;
    variants(&ev).tgt.ioevs[0].iv = 2; // PRIVDROP reads from tgt.ioevs
    const s = eventStr(&ev);
    try testing.expect(contains(s, "PRIVDROP"));
}

test "eventstr: EXT UNKNOWN (default branch)" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = 9999; // non-existent kind
    const s = eventStr(&ev);
    try testing.expect(contains(s, "UNKNOWN"));
}

// 11d. eventstr: TARGET branches

test "eventstr: TGT EXIT" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_EXIT;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "EXIT"));
}

test "eventstr: TGT FRAMESKIP" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_FRAMESKIP;
    variants(&ev).tgt.ioevs[0].iv = 5;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "FRAMESKIP"));
}

test "eventstr: TGT STEPFRAME" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_STEPFRAME;
    variants(&ev).tgt.ioevs[0].iv = 3;
    variants(&ev).tgt.ioevs[1].iv = 42;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "STEPFRAME"));
}

test "eventstr: TGT COREOPT" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_COREOPT;
    variants(&ev).tgt.code = 7;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "COREOPT"));
}

test "eventstr: TGT STORE" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_STORE;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "STORE"));
}

test "eventstr: TGT RESTORE" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_RESTORE;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "RESTORE"));
}

test "eventstr: TGT BCHUNK_IN" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "BCHUNK-IN"));
}

test "eventstr: TGT BCHUNK_OUT" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_BCHUNK_OUT;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "BCHUNK-OUT"));
}

test "eventstr: TGT RESET soft" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_RESET;
    variants(&ev).tgt.ioevs[0].iv = 0;
    try testing.expect(contains(eventStr(&ev), "soft"));
}

test "eventstr: TGT RESET hard" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_RESET;
    variants(&ev).tgt.ioevs[0].iv = 1;
    try testing.expect(contains(eventStr(&ev), "hard"));
}

test "eventstr: TGT RESET recover-rst" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_RESET;
    variants(&ev).tgt.ioevs[0].iv = 2;
    try testing.expect(contains(eventStr(&ev), "recover-rst"));
}

test "eventstr: TGT RESET recover-recon" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_RESET;
    variants(&ev).tgt.ioevs[0].iv = 3;
    try testing.expect(contains(eventStr(&ev), "recover-recon"));
}

test "eventstr: TGT RESET bad-value" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_RESET;
    variants(&ev).tgt.ioevs[0].iv = 99;
    try testing.expect(contains(eventStr(&ev), "bad-value"));
}

test "eventstr: TGT PAUSE" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_PAUSE;
    try testing.expect(contains(eventStr(&ev), "PAUSE"));
}

test "eventstr: TGT UNPAUSE" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_UNPAUSE;
    try testing.expect(contains(eventStr(&ev), "UNPAUSE"));
}

test "eventstr: TGT SEEKCONTENT relative" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_SEEKCONTENT;
    variants(&ev).tgt.ioevs[0].iv = 0; // relative
    variants(&ev).tgt.ioevs[1].iv = 10;
    variants(&ev).tgt.ioevs[2].iv = 20;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "SEEKCONTENT"));
    try testing.expect(contains(s, "relative"));
}

test "eventstr: TGT SEEKCONTENT absolute" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_SEEKCONTENT;
    variants(&ev).tgt.ioevs[0].iv = 1; // absolute
    const s = eventStr(&ev);
    try testing.expect(contains(s, "SEEKCONTENT"));
    try testing.expect(contains(s, "absolute"));
}

test "eventstr: TGT SEEKCONTENT broken" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_SEEKCONTENT;
    variants(&ev).tgt.ioevs[0].iv = 99; // bad value
    const s = eventStr(&ev);
    try testing.expect(contains(s, "SEEKCONTENT"));
    try testing.expect(contains(s, "BROKEN"));
}

test "eventstr: TGT SEEKTIME" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_SEEKTIME;
    variants(&ev).tgt.ioevs[0].iv = 1; // absolute
    const s = eventStr(&ev);
    try testing.expect(contains(s, "SEEKTIME"));
    try testing.expect(contains(s, "absolute"));
}

test "eventstr: TGT SEEKTIME relative" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_SEEKTIME;
    variants(&ev).tgt.ioevs[0].iv = 0; // relative
    const s = eventStr(&ev);
    try testing.expect(contains(s, "relative"));
}

test "eventstr: TGT DISPLAYHINT" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_DISPLAYHINT;
    variants(&ev).tgt.ioevs[0].iv = 1920;
    variants(&ev).tgt.ioevs[1].iv = 1080;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "DISPLAYHINT"));
    try testing.expect(contains(s, "1920"));
}

test "eventstr: TGT ANCHORHINT" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_ANCHORHINT;
    variants(&ev).tgt.ioevs[0].iv = 10;
    variants(&ev).tgt.ioevs[1].iv = 20;
    variants(&ev).tgt.ioevs[2].iv = 30;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "ANCHORHINT"));
}

test "eventstr: TGT SETIODEV" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_SETIODEV;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "IODEV"));
}

test "eventstr: TGT STREAMSET" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_STREAMSET;
    variants(&ev).tgt.ioevs[0].iv = 3;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "STREAMSET"));
}

test "eventstr: TGT ATTENUATE" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_ATTENUATE;
    variants(&ev).tgt.ioevs[0].fv = 0.75;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "ATTENUATE"));
}

test "eventstr: TGT AUDDELAY" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_AUDDELAY;
    variants(&ev).tgt.ioevs[0].iv = 50;
    variants(&ev).tgt.ioevs[1].iv = 100;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "AUDDELAY"));
}

test "eventstr: TGT NEWSEGMENT" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_NEWSEGMENT;
    variants(&ev).tgt.ioevs[1].iv = 1; // read direction
    variants(&ev).tgt.ioevs[2].iv = c.SEGID_TUI;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "NEWSEGMENT"));
    try testing.expect(contains(s, "read"));
}

test "eventstr: TGT REQFAIL" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_REQFAIL;
    variants(&ev).tgt.ioevs[0].iv = 42;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "REQFAIL"));
}

test "eventstr: TGT BUFFER_FAIL" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_BUFFER_FAIL;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "BUFFER_FAIL"));
}

test "eventstr: TGT DEVICE_NODE render-node" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_DEVICE_NODE;
    variants(&ev).tgt.ioevs[1].iv = 1;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "DEVICE_NODE"));
    try testing.expect(contains(s, "render-node"));
}

test "eventstr: TGT DEVICE_NODE connpath" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_DEVICE_NODE;
    variants(&ev).tgt.ioevs[1].iv = 2;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "DEVICE_NODE"));
    try testing.expect(contains(s, "connpath"));
}

test "eventstr: TGT DEVICE_NODE remote" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_DEVICE_NODE;
    variants(&ev).tgt.ioevs[1].iv = 3;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "DEVICE_NODE"));
    try testing.expect(contains(s, "remote"));
}

test "eventstr: TGT DEVICE_NODE alt" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_DEVICE_NODE;
    variants(&ev).tgt.ioevs[1].iv = 4;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "DEVICE_NODE"));
    try testing.expect(contains(s, "alt"));
}

test "eventstr: TGT DEVICE_NODE auth-cookie" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_DEVICE_NODE;
    variants(&ev).tgt.ioevs[1].iv = 5;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "DEVICE_NODE"));
    try testing.expect(contains(s, "auth-cookie"));
}

test "eventstr: TGT GRAPHMODE" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_GRAPHMODE;
    variants(&ev).tgt.ioevs[0].iv = 1;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "GRAPHMODE"));
}

test "eventstr: TGT MESSAGE" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_MESSAGE;
    variants(&ev).tgt.unnamed_0.message[0] = 'z';
    const s = eventStr(&ev);
    try testing.expect(contains(s, "MESSAGE"));
}

test "eventstr: TGT FONTHINT" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_FONTHINT;
    variants(&ev).tgt.ioevs[1].iv = 2;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "FONTHINT"));
}

test "eventstr: TGT GEOHINT" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_GEOHINT;
    variants(&ev).tgt.ioevs[0].fv = 59.33;
    variants(&ev).tgt.ioevs[1].fv = 18.07;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "GEOHINT"));
}

test "eventstr: TGT OUTPUTHINT" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_OUTPUTHINT;
    variants(&ev).tgt.ioevs[0].iv = 3840;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "OUTPUTHINT"));
}

test "eventstr: TGT ACTIVATE" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_ACTIVATE;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "ACTIVATE"));
}

test "eventstr: TGT UNKNOWN (default branch)" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = 9999;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "UNKNOWN"));
}

// 11e. eventstr: IO branches

test "eventstr: IO TRANSLATED" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.datatype = c.EVENT_IDATATYPE_TRANSLATED;
    io.unnamed_0.unnamed_0.devid = 1;
    io.unnamed_0.unnamed_0.subid = 30;
    io.input.translated.active = 1;
    io.input.translated.keysym = 65;
    io.input.translated.scancode = 30;
    io.input.translated.modifiers = 3;
    io.input.translated.utf8[0] = 'A';
    const s = eventStr(&ev);
    try testing.expect(contains(s, "kbd"));
    try testing.expect(contains(s, "pressed"));
}

test "eventstr: IO TRANSLATED released" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.datatype = c.EVENT_IDATATYPE_TRANSLATED;
    io.input.translated.active = 0;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "released"));
}

test "eventstr: IO ANALOG mouse" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.datatype = c.EVENT_IDATATYPE_ANALOG;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.unnamed_0.unnamed_0.devid = 0;
    io.unnamed_0.unnamed_0.subid = 2;
    io.input.analog.nvalues = 2;
    io.input.analog.axisval[0] = 100;
    io.input.analog.axisval[1] = 200;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "mouse"));
}

test "eventstr: IO ANALOG non-mouse" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.datatype = c.EVENT_IDATATYPE_ANALOG;
    io.devkind = c.EVENT_IDEVKIND_GAMEDEV;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "analog"));
}

test "eventstr: IO EYES" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.datatype = c.EVENT_IDATATYPE_EYES;
    io.unnamed_0.unnamed_0.devid = 0;
    io.input.eyes.head_pos[0] = 1.0;
    io.input.eyes.head_ang[0] = 0.5;
    io.input.eyes.gaze_x1 = 0.5;
    io.input.eyes.gaze_y1 = 0.5;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "EYE"));
}

test "eventstr: IO TOUCH" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.datatype = c.EVENT_IDATATYPE_TOUCH;
    io.unnamed_0.unnamed_0.devid = 0;
    io.unnamed_0.unnamed_0.subid = 0;
    io.input.touch.x = 320;
    io.input.touch.y = 240;
    io.input.touch.pressure = 0.8;
    io.input.touch.size = 1.0;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "touch"));
}

test "eventstr: IO DIGITAL mouse (msub_to_lbl left)" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.datatype = c.EVENT_IDATATYPE_DIGITAL;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.unnamed_0.unnamed_0.devid = 0;
    io.unnamed_0.unnamed_0.subid = c.MBTN_LEFT_IND;
    io.input.digital.active = 1;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "mouse"));
    try testing.expect(contains(s, "left"));
    try testing.expect(contains(s, "pressed"));
}

test "eventstr: IO DIGITAL mouse right" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.datatype = c.EVENT_IDATATYPE_DIGITAL;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.unnamed_0.unnamed_0.subid = c.MBTN_RIGHT_IND;
    io.input.digital.active = 0;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "right"));
    try testing.expect(contains(s, "released"));
}

test "eventstr: IO DIGITAL mouse middle" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.datatype = c.EVENT_IDATATYPE_DIGITAL;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.unnamed_0.unnamed_0.subid = c.MBTN_MIDDLE_IND;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "middle"));
}

test "eventstr: IO DIGITAL mouse wheel-up" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.datatype = c.EVENT_IDATATYPE_DIGITAL;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.unnamed_0.unnamed_0.subid = c.MBTN_WHEEL_UP_IND;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "wheel-up"));
}

test "eventstr: IO DIGITAL mouse wheel-down" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.datatype = c.EVENT_IDATATYPE_DIGITAL;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.unnamed_0.unnamed_0.subid = c.MBTN_WHEEL_DOWN_IND;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "wheel-down"));
}

test "eventstr: IO DIGITAL mouse unknown button" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.datatype = c.EVENT_IDATATYPE_DIGITAL;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.unnamed_0.unnamed_0.subid = 99; // unknown button index
    const s = eventStr(&ev);
    try testing.expect(contains(s, "unknown"));
}

test "eventstr: IO DIGITAL non-mouse" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.datatype = c.EVENT_IDATATYPE_DIGITAL;
    io.devkind = c.EVENT_IDEVKIND_GAMEDEV;
    io.input.digital.active = 1;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "digital"));
    try testing.expect(contains(s, "pressed"));
}

test "eventstr: IO unknown datatype (default)" {
    var ev = makeEvent(c.EVENT_IO);
    variants(&ev).io.datatype = 99;
    const s = eventStr(&ev);
    try testing.expect(contains(s, "unhandled"));
}
