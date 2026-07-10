/// shmif extended event coverage tests
///
/// Tier 5: Additional event variant round-trips, descrevent fd-carrying
/// event classifier, and expanded eventstr coverage.
const std = @import("std");
const testing = std.testing;

const c = @import("shmif_types");

// Accessor shortcuts (same as shmif_event_test.zig)

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

// 5a. IO event variants

test "IO analog event round-trip" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_AXIS_MOVE;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.datatype = c.EVENT_IDATATYPE_ANALOG;
    io.input.analog.nvalues = 2;
    io.input.analog.gotrel = 0;
    io.input.analog.axisval[0] = 100;

    const out = try roundTrip(&ev);
    const out_io = variants(@constCast(&out)).io;
    try testing.expectEqual(io.kind, out_io.kind);
    try testing.expectEqual(io.devkind, out_io.devkind);
    try testing.expectEqual(io.datatype, out_io.datatype);
    try testing.expectEqual(io.input.analog.nvalues, out_io.input.analog.nvalues);
    try testing.expectEqual(io.input.analog.axisval[0], out_io.input.analog.axisval[0]);
}

test "IO digital event round-trip" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.datatype = c.EVENT_IDATATYPE_DIGITAL;
    io.input.digital.active = 1;

    const out = try roundTrip(&ev);
    const out_io = variants(@constCast(&out)).io;
    try testing.expectEqual(io.kind, out_io.kind);
    try testing.expectEqual(io.datatype, out_io.datatype);
    try testing.expectEqual(io.input.digital.active, out_io.input.digital.active);
}

test "IO touch event round-trip" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.devkind = c.EVENT_IDEVKIND_TOUCHDISP;
    io.datatype = c.EVENT_IDATATYPE_DIGITAL;
    io.input.digital.active = 1;

    const out = try roundTrip(&ev);
    const out_io = variants(@constCast(&out)).io;
    try testing.expectEqual(io.devkind, out_io.devkind);
}

test "IO eyes event round-trip" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_AXIS_MOVE;
    io.devkind = c.EVENT_IDEVKIND_EYETRACKER;
    io.datatype = c.EVENT_IDATATYPE_ANALOG;

    const out = try roundTrip(&ev);
    const out_io = variants(@constCast(&out)).io;
    try testing.expectEqual(io.devkind, out_io.devkind);
}

test "IO event devid/subid fields preserved" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.unnamed_0.unnamed_0.devid = 42;
    io.unnamed_0.unnamed_0.subid = 7;

    const out = try roundTrip(&ev);
    const out_io = variants(@constCast(&out)).io;
    try testing.expectEqual(@as(u16, 42), out_io.unnamed_0.unnamed_0.devid);
    try testing.expectEqual(@as(u16, 7), out_io.unnamed_0.unnamed_0.subid);
}

// 5b. TARGET event variants

test "TARGET GEOHINT round-trip" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_GEOHINT;
    // Latitude/longitude stored as floats in ioevs
    tgt.ioevs[0].fv = 59.33; // latitude
    tgt.ioevs[1].fv = 18.07; // longitude

    const out = try roundTrip(&ev);
    const out_tgt = variants(@constCast(&out)).tgt;
    try testing.expectEqual(tgt.kind, out_tgt.kind);
    try testing.expectApproxEqAbs(tgt.ioevs[0].fv, out_tgt.ioevs[0].fv, 0.001);
    try testing.expectApproxEqAbs(tgt.ioevs[1].fv, out_tgt.ioevs[1].fv, 0.001);
}

test "TARGET MESSAGE round-trip" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_MESSAGE;
    const msg = "hello";
    for (msg, 0..) |ch, i| {
        tgt.unnamed_0.message[i] = ch;
    }

    const out = try roundTrip(&ev);
    const out_tgt = variants(@constCast(&out)).tgt;
    try testing.expectEqual(tgt.kind, out_tgt.kind);
    const out_msg: *const [msg.len]u8 = @ptrCast(out_tgt.unnamed_0.message[0..msg.len]);
    try testing.expectEqualSlices(u8, msg, out_msg);
}

test "TARGET OUTPUTHINT round-trip" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_OUTPUTHINT;
    tgt.ioevs[0].iv = 1920;
    tgt.ioevs[1].iv = 1080;

    const out = try roundTrip(&ev);
    const out_tgt = variants(@constCast(&out)).tgt;
    try testing.expectEqual(tgt.kind, out_tgt.kind);
    try testing.expectEqual(tgt.ioevs[0].iv, out_tgt.ioevs[0].iv);
    try testing.expectEqual(tgt.ioevs[1].iv, out_tgt.ioevs[1].iv);
}

test "TARGET FONTHINT round-trip" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_FONTHINT;
    tgt.ioevs[0].iv = 42; // fd placeholder
    tgt.ioevs[1].iv = 12; // font size

    const out = try roundTrip(&ev);
    const out_tgt = variants(@constCast(&out)).tgt;
    try testing.expectEqual(tgt.kind, out_tgt.kind);
    try testing.expectEqual(tgt.ioevs[0].iv, out_tgt.ioevs[0].iv);
    try testing.expectEqual(tgt.ioevs[1].iv, out_tgt.ioevs[1].iv);
}

test "TARGET DEVICE_NODE round-trip" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_DEVICE_NODE;
    tgt.ioevs[0].iv = 10; // fd placeholder

    const out = try roundTrip(&ev);
    const out_tgt = variants(@constCast(&out)).tgt;
    try testing.expectEqual(tgt.kind, out_tgt.kind);
    try testing.expectEqual(tgt.ioevs[0].iv, out_tgt.ioevs[0].iv);
}

// 5c. EXTERNAL event variants

test "EXTERNAL VIEWPORT round-trip" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_VIEWPORT;

    const out = try roundTrip(&ev);
    try testing.expectEqual(ext.kind, variants(@constCast(&out)).ext.kind);
}

test "EXTERNAL LABELHINT round-trip" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_LABELHINT;
    ext.unnamed_0.labelhint.idatatype = c.EVENT_IDATATYPE_DIGITAL;
    const label = "test_label";
    for (label, 0..) |ch, i| {
        ext.unnamed_0.labelhint.label[i] = ch;
    }

    const out = try roundTrip(&ev);
    const out_ext = variants(@constCast(&out)).ext;
    try testing.expectEqual(ext.kind, out_ext.kind);
    try testing.expectEqual(
        ext.unnamed_0.labelhint.idatatype,
        out_ext.unnamed_0.labelhint.idatatype,
    );
    const out_label: *const [label.len]u8 = @ptrCast(out_ext.unnamed_0.labelhint.label[0..label.len]);
    try testing.expectEqualSlices(u8, label, out_label);
}

test "EXTERNAL BCHUNKSTATE round-trip" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_BCHUNKSTATE;

    const out = try roundTrip(&ev);
    try testing.expectEqual(ext.kind, variants(@constCast(&out)).ext.kind);
}

test "EXTERNAL CLOCKREQ round-trip" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_CLOCKREQ;
    ext.unnamed_0.clock.rate = 60;
    ext.unnamed_0.clock.dynamic = 1;
    ext.unnamed_0.clock.once = 0;

    const out = try roundTrip(&ev);
    const out_ext = variants(@constCast(&out)).ext;
    try testing.expectEqual(ext.kind, out_ext.kind);
    try testing.expectEqual(ext.unnamed_0.clock.rate, out_ext.unnamed_0.clock.rate);
    try testing.expectEqual(ext.unnamed_0.clock.dynamic, out_ext.unnamed_0.clock.dynamic);
    try testing.expectEqual(ext.unnamed_0.clock.once, out_ext.unnamed_0.clock.once);
}

test "EXTERNAL MESSAGE round-trip with multipart" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    const ext = &variants(&ev).ext;
    ext.kind = c.EVENT_EXTERNAL_MESSAGE;
    ext.unnamed_0.message.multipart = 1;
    const msg = "part1";
    for (msg, 0..) |ch, i| {
        ext.unnamed_0.message.data[i] = ch;
    }

    const out = try roundTrip(&ev);
    const out_ext = variants(@constCast(&out)).ext;
    try testing.expectEqual(ext.kind, out_ext.kind);
    try testing.expectEqual(
        ext.unnamed_0.message.multipart,
        out_ext.unnamed_0.message.multipart,
    );
    const out_data: *const [msg.len]u8 = @ptrCast(out_ext.unnamed_0.message.data[0..msg.len]);
    try testing.expectEqualSlices(u8, msg, out_data);
}

// 5d. descrevent

const BADFD: i32 = -1;

test "descrevent with null returns false" {
    try testing.expect(!c.arcan_shmif_descrevent(null));
}

test "descrevent with non-TARGET event returns false" {
    var ev = makeEvent(c.EVENT_IO);
    try testing.expect(!c.arcan_shmif_descrevent(&ev));
}

test "descrevent TARGET_COMMAND_STORE with valid fd returns true" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_STORE;
    tgt.ioevs[0].iv = 42; // valid fd (not BADFD)
    try testing.expect(c.arcan_shmif_descrevent(&ev));
}

test "descrevent TARGET_COMMAND_RESTORE with valid fd returns true" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_RESTORE;
    tgt.ioevs[0].iv = 42;
    try testing.expect(c.arcan_shmif_descrevent(&ev));
}

test "descrevent TARGET_COMMAND_DEVICE_NODE with valid fd returns true" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_DEVICE_NODE;
    tgt.ioevs[0].iv = 42;
    try testing.expect(c.arcan_shmif_descrevent(&ev));
}

test "descrevent TARGET_COMMAND_FONTHINT with valid fd returns true" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_FONTHINT;
    tgt.ioevs[0].iv = 42;
    try testing.expect(c.arcan_shmif_descrevent(&ev));
}

test "descrevent TARGET_COMMAND_BCHUNK_IN with BADFD returns false" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
    tgt.ioevs[0].iv = BADFD;
    try testing.expect(!c.arcan_shmif_descrevent(&ev));
}

test "descrevent TARGET_COMMAND_EXIT (not in list) returns false" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_EXIT;
    tgt.ioevs[0].iv = 42; // even with valid fd, EXIT is not in the desc list
    try testing.expect(!c.arcan_shmif_descrevent(&ev));
}

// 5e. eventstr expanded

test "eventstr for IO analog contains ANALOG" {
    var ev = makeEvent(c.EVENT_IO);
    variants(&ev).io.datatype = c.EVENT_IDATATYPE_ANALOG;
    const result = c.arcan_shmif_eventstr(&ev, null, 0);
    try testing.expect(result != null);
    const str = std.mem.span(result.?);
    try testing.expect(std.mem.indexOf(u8, str, "analog") != null or
        std.mem.indexOf(u8, str, "ANALOG") != null or
        std.mem.indexOf(u8, str, "Analog") != null);
}

test "eventstr for TARGET FONTHINT contains FONTHINT" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_FONTHINT;
    const result = c.arcan_shmif_eventstr(&ev, null, 0);
    try testing.expect(result != null);
    const str = std.mem.span(result.?);
    try testing.expect(std.mem.indexOf(u8, str, "FONTHINT") != null);
}

test "eventstr for EXTERNAL CLOCKREQ contains CLOCKREQ" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_CLOCKREQ;
    const result = c.arcan_shmif_eventstr(&ev, null, 0);
    try testing.expect(result != null);
    const str = std.mem.span(result.?);
    try testing.expect(std.mem.indexOf(u8, str, "CLOCKREQ") != null);
}
