/// shmif event serialization and queue semantics tests
///
/// Tier 2: Tests that exercise the C event pack/unpack functions and verify
/// event queue ring-buffer behavior. These link against the C shmif library.
///
/// The arcan_event struct in @cImport has nested anonymous unions/structs:
///   ev.category().*       (uint8 category)
///   ev.io()   (arcan_ioevent)
///   ev.tgt()  (arcan_tgtevent)
///   ev.ext()  (arcan_extevent)
const std = @import("std");
const testing = std.testing;

const c = @import("shmif_types");

// Accessor shortcuts

const Event = c.arcan_event;

/// Access the inner struct (contains unnamed_0 union + category)
inline fn inner(ev: *Event) *@TypeOf(ev.unnamed_0.unnamed_0) {
    return &ev.unnamed_0.unnamed_0;
}

/// Access the event variant union (io/tgt/ext/...)
inline fn variants(ev: *Event) *@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0) {
    return &ev.unnamed_0.unnamed_0.unnamed_0;
}

// Helper: subp_checksum in pure Zig

fn subpChecksum(buf: []const u8) u16 {
    // Must match the C implementation in arcan_shmif_sub.h exactly.
    // The C code uses uint16_t for res; the `res |= 0x10000` is a
    // no-op in C because the result is truncated back to uint16_t
    // on assignment.  We replicate by masking to 16 bits each iteration.
    var res: u16 = 0;
    for (buf) |byte| {
        // In C, `if (res & 1) res |= 0x10000;` is a no-op on uint16_t.
        // The effective computation is just: res = ((res >> 1) + byte) & 0xffff
        res = @truncate((@as(u32, res) >> 1) + byte);
    }
    return res;
}

// Helper: create a zeroed event with a given category

fn makeEvent(category: u8) Event {
    var ev: Event = std.mem.zeroes(Event);
    inner(&ev).category = category;
    return ev;
}

// 2a. Pack/unpack round-trip

test "IO event (keyboard) round-trips through pack/unpack" {
    var ev = makeEvent(c.EVENT_IO);
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.devkind = c.EVENT_IDEVKIND_KEYBOARD;
    io.datatype = c.EVENT_IDATATYPE_TRANSLATED;
    io.input.translated.scancode = 42;
    io.input.translated.keysym = 0x61; // 'a'
    io.input.translated.active = 1;

    var buf: [256]u8 = undefined;
    const pack_sz = c.arcan_shmif_eventpack(&ev, &buf, buf.len);
    try testing.expect(pack_sz > 0);
    try testing.expectEqual(@as(isize, 130), pack_sz); // 128 + 2 byte checksum

    var out: Event = undefined;
    const unpack_sz = c.arcan_shmif_eventunpack(&buf, @intCast(pack_sz), &out);
    try testing.expectEqual(pack_sz, unpack_sz);

    // Verify fields survived the round-trip
    try testing.expectEqual(inner(&ev).category, inner(&out).category);
    try testing.expectEqual(
        variants(&ev).io.input.translated.scancode,
        variants(&out).io.input.translated.scancode,
    );
    try testing.expectEqual(
        variants(&ev).io.input.translated.keysym,
        variants(&out).io.input.translated.keysym,
    );
    try testing.expectEqual(
        variants(&ev).io.input.translated.active,
        variants(&out).io.input.translated.active,
    );
}

test "TARGET event (DISPLAYHINT) round-trips through pack/unpack" {
    var ev = makeEvent(c.EVENT_TARGET);
    const tgt = &variants(&ev).tgt;
    tgt.kind = c.TARGET_COMMAND_DISPLAYHINT;
    tgt.ioevs[0].iv = 1920;
    tgt.ioevs[1].iv = 1080;

    var buf: [256]u8 = undefined;
    const pack_sz = c.arcan_shmif_eventpack(&ev, &buf, buf.len);
    try testing.expect(pack_sz > 0);

    var out: Event = undefined;
    const unpack_sz = c.arcan_shmif_eventunpack(&buf, @intCast(pack_sz), &out);
    try testing.expectEqual(pack_sz, unpack_sz);

    try testing.expectEqual(inner(&ev).category, inner(&out).category);
    try testing.expectEqual(
        variants(&ev).tgt.ioevs[0].iv,
        variants(&out).tgt.ioevs[0].iv,
    );
    try testing.expectEqual(
        variants(&ev).tgt.ioevs[1].iv,
        variants(&out).tgt.ioevs[1].iv,
    );
}

test "EXTERNAL event (REGISTER) round-trips through pack/unpack" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_REGISTER;

    // Fill title with a known pattern
    const title = "test-client";
    for (title, 0..) |ch, i| {
        variants(&ev).ext.unnamed_0.registr.title[i] = ch;
    }

    var buf: [256]u8 = undefined;
    const pack_sz = c.arcan_shmif_eventpack(&ev, &buf, buf.len);
    try testing.expect(pack_sz > 0);

    var out: Event = undefined;
    const unpack_sz = c.arcan_shmif_eventunpack(&buf, @intCast(pack_sz), &out);
    try testing.expectEqual(pack_sz, unpack_sz);

    try testing.expectEqual(inner(&ev).category, inner(&out).category);

    // Verify title survived
    const out_title: *const [title.len]u8 = @ptrCast(variants(&out).ext.unnamed_0.registr.title[0..title.len]);
    try testing.expectEqualSlices(u8, title, out_title);
}

test "packed size is always 130 bytes (128 event + 2 checksum)" {
    var buf: [256]u8 = undefined;

    var ev1 = makeEvent(c.EVENT_IO);
    try testing.expectEqual(@as(isize, 130), c.arcan_shmif_eventpack(&ev1, &buf, buf.len));

    var ev2 = makeEvent(c.EVENT_TARGET);
    try testing.expectEqual(@as(isize, 130), c.arcan_shmif_eventpack(&ev2, &buf, buf.len));

    var ev3 = makeEvent(c.EVENT_EXTERNAL);
    try testing.expectEqual(@as(isize, 130), c.arcan_shmif_eventpack(&ev3, &buf, buf.len));

    var ev4 = std.mem.zeroes(Event);
    try testing.expectEqual(@as(isize, 130), c.arcan_shmif_eventpack(&ev4, &buf, buf.len));
}

test "pack fails with insufficient buffer" {
    var ev = makeEvent(c.EVENT_IO);
    var small_buf: [64]u8 = undefined;
    const result = c.arcan_shmif_eventpack(&ev, &small_buf, small_buf.len);
    try testing.expectEqual(@as(isize, -1), result);
}

test "unpack fails with corrupted checksum" {
    var ev = makeEvent(c.EVENT_IO);
    var buf: [256]u8 = undefined;
    const pack_sz = c.arcan_shmif_eventpack(&ev, &buf, buf.len);
    try testing.expect(pack_sz > 0);

    // Corrupt the checksum (first 2 bytes)
    buf[0] ^= 0xff;

    var out: Event = undefined;
    const result = c.arcan_shmif_eventunpack(&buf, @intCast(pack_sz), &out);
    try testing.expectEqual(@as(isize, -1), result);
}

// 2b. Checksum verification

test "Zig subpChecksum matches C packing checksum" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_MESSAGE;

    var buf: [256]u8 = undefined;
    const pack_sz = c.arcan_shmif_eventpack(&ev, &buf, buf.len);
    try testing.expect(pack_sz > 0);

    // Extract checksum that the C function wrote
    const c_checksum = std.mem.readInt(u16, buf[0..2], .little);

    // Compute in Zig: checksum of the event bytes XOR'd with version tag
    const ev_bytes: *const [128]u8 = @ptrCast(&ev);
    const zig_raw = subpChecksum(ev_bytes);
    const version_tag: u16 = @intCast((@as(u32, c.ASHMIF_VERSION_MAJOR) << 2) | @as(u32, c.ASHMIF_VERSION_MINOR));
    const zig_checksum = zig_raw ^ version_tag;

    try testing.expectEqual(c_checksum, zig_checksum);
}

// 2c. Event string conversion

test "eventstr produces non-null for IO event" {
    var ev = makeEvent(c.EVENT_IO);
    variants(&ev).io.datatype = c.EVENT_IDATATYPE_DIGITAL;
    const result = c.arcan_shmif_eventstr(&ev, null, 0);
    try testing.expect(result != null);
}

test "eventstr produces non-null for TARGET event" {
    var ev = makeEvent(c.EVENT_TARGET);
    variants(&ev).tgt.kind = c.TARGET_COMMAND_EXIT;
    const result = c.arcan_shmif_eventstr(&ev, null, 0);
    try testing.expect(result != null);
    // Should contain "EXIT"
    const str = std.mem.span(result.?);
    try testing.expect(std.mem.indexOf(u8, str, "EXIT") != null);
}

test "eventstr produces non-null for EXTERNAL event" {
    var ev = makeEvent(c.EVENT_EXTERNAL);
    variants(&ev).ext.kind = c.EVENT_EXTERNAL_REGISTER;
    const result = c.arcan_shmif_eventstr(&ev, null, 0);
    try testing.expect(result != null);
    const str = std.mem.span(result.?);
    try testing.expect(std.mem.indexOf(u8, str, "REGISTER") != null);
}

test "eventstr returns empty string for null event" {
    const result = c.arcan_shmif_eventstr(null, null, 0);
    try testing.expect(result != null);
    try testing.expectEqual(@as(u8, 0), result.?[0]);
}

// 2d. Event queue ring buffer semantics
//
// struct arcan_shmif_page is opaque to Zig, so we can't instantiate the
// embedded event queues directly. Instead we test the ring buffer index
// arithmetic using PP_QUEUE_SZ, which IS accessible.

const QUEUE_SZ: u8 = @intCast(c.PP_QUEUE_SZ);

test "queue index arithmetic: back advances on enqueue" {
    const front: u8 = 0;
    var back: u8 = 0;

    // Simulate enqueue
    back = (back +% 1) % QUEUE_SZ;

    try testing.expectEqual(@as(u8, 0), front);
    try testing.expectEqual(@as(u8, 1), back);
}

test "queue can hold PP_QUEUE_SZ - 1 events before full" {
    const front: u8 = 0;
    var back: u8 = 0;

    // Fill queue to capacity (one slot always empty as sentinel)
    var i: u8 = 0;
    while (i < QUEUE_SZ - 1) : (i += 1) {
        back = (back +% 1) % QUEUE_SZ;
    }

    // Queue is now full: (back + 1) % SZ == front
    try testing.expectEqual(front, (back +% 1) % QUEUE_SZ);
}

test "queue dequeue advances front" {
    var front: u8 = 0;
    var back: u8 = 0;

    // Enqueue 3
    var i: u8 = 0;
    while (i < 3) : (i += 1) {
        back = (back +% 1) % QUEUE_SZ;
    }

    // Dequeue 1
    front = (front +% 1) % QUEUE_SZ;

    try testing.expectEqual(@as(u8, 1), front);
    try testing.expectEqual(@as(u8, 3), back);
}

test "queue indices wrap around within [0, PP_QUEUE_SZ)" {
    const front: u8 = QUEUE_SZ - 2;
    var back: u8 = QUEUE_SZ - 2;

    // Enqueue 4 events (should wrap)
    var i: u8 = 0;
    while (i < 4) : (i += 1) {
        back = (back +% 1) % QUEUE_SZ;
    }

    _ = front;
    try testing.expect(back < QUEUE_SZ);
    try testing.expectEqual(@as(u8, 2), back); // (127-2+4) % 127 = 2
}
