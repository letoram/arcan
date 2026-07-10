/// shmif mousestate API tests
///
/// Tier 6: Tests the mouse state machine functions (arcan_shmif_mousestate_setup,
/// arcan_shmif_mousestate, arcan_shmif_mousestate_ioev). Uses a mock
/// arcan_shmif_cont allocated via C helper to satisfy the non-null context
/// requirement.
const std = @import("std");
const testing = std.testing;

const c = @import("shmif_types");

// C helper externs

extern fn shmif_test_mock_context(w: usize, h: usize) ?*c.struct_arcan_shmif_cont;
extern fn shmif_test_mock_destroy(con: ?*c.struct_arcan_shmif_cont) void;

// Helper: create a mouse analog IO event

const Event = c.arcan_event;

inline fn inner(ev: *Event) *@TypeOf(ev.unnamed_0.unnamed_0) {
    return &ev.unnamed_0.unnamed_0;
}

inline fn variants(ev: *Event) *@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0) {
    return &ev.unnamed_0.unnamed_0.unnamed_0;
}

/// Create a mouse motion event (packed, subid=2) with absolute coords.
fn makeMouseMotion(x: i16, y: i16) Event {
    var ev: Event = std.mem.zeroes(Event);
    inner(&ev).category = c.EVENT_IO;
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_AXIS_MOVE;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.datatype = c.EVENT_IDATATYPE_ANALOG;
    io.unnamed_0.unnamed_0.subid = 2; // packed: both X and Y
    io.unnamed_0.unnamed_0.devid = 0;
    io.input.analog.gotrel = 0; // absolute
    io.input.analog.nvalues = 4;
    io.input.analog.axisval[0] = x;
    io.input.analog.axisval[2] = y;
    return ev;
}

/// Create a mouse motion event with relative coords.
fn makeMouseMotionRel(dx: i16, dy: i16) Event {
    var ev = makeMouseMotion(dx, dy);
    variants(&ev).io.input.analog.gotrel = 1;
    return ev;
}

/// Create a mouse button event.
fn makeMouseButton(active: bool) Event {
    var ev: Event = std.mem.zeroes(Event);
    inner(&ev).category = c.EVENT_IO;
    const io = &variants(&ev).io;
    io.kind = c.EVENT_IO_BUTTON;
    io.devkind = c.EVENT_IDEVKIND_MOUSE;
    io.datatype = c.EVENT_IDATATYPE_DIGITAL;
    io.input.digital.active = if (active) 1 else 0;
    return ev;
}

// Helper: RAII-style mock context

const MockCtx = struct {
    con: *c.struct_arcan_shmif_cont,

    fn init(w: usize, h: usize) ?MockCtx {
        const con = shmif_test_mock_context(w, h) orelse return null;
        return .{ .con = con };
    }

    fn deinit(self: MockCtx) void {
        shmif_test_mock_destroy(self.con);
    }
};

// 6a. Constants

test "ASHMIF_MSTATE_SZ is 32" {
    try testing.expectEqual(@as(c_int, 32), c.ASHMIF_MSTATE_SZ);
}

// 6b. mousestate_setup

test "mousestate_setup with mock context does not crash" {
    const ctx = MockCtx.init(640, 480) orelse return error.SkipZigTest;
    defer ctx.deinit();

    var state: [c.ASHMIF_MSTATE_SZ]u8 = undefined;
    c.arcan_shmif_mousestate_setup(ctx.con, c.ARCAN_MOUSESTATE_ABSOLUTE, &state);
    // If we reach here, it didn't crash
}

test "mousestate_setup with null context does not crash" {
    var state: [c.ASHMIF_MSTATE_SZ]u8 = undefined;
    // With null context, setup should return early (no-op)
    c.arcan_shmif_mousestate_setup(null, c.ARCAN_MOUSESTATE_ABSOLUTE, &state);
}

// 6c. Absolute mode

test "absolute mode: single motion event returns coordinates" {
    const ctx = MockCtx.init(640, 480) orelse return error.SkipZigTest;
    defer ctx.deinit();

    var state: [c.ASHMIF_MSTATE_SZ]u8 = [_]u8{0} ** c.ASHMIF_MSTATE_SZ;
    c.arcan_shmif_mousestate_setup(ctx.con, c.ARCAN_MOUSESTATE_ABSOLUTE, &state);

    var ev = makeMouseMotion(100, 200);
    var out_x: c_int = 0;
    var out_y: c_int = 0;
    const ok = c.arcan_shmif_mousestate(ctx.con, &state, &ev, &out_x, &out_y);
    try testing.expect(ok);
    try testing.expectEqual(@as(c_int, 100), out_x);
    try testing.expectEqual(@as(c_int, 200), out_y);
}

test "absolute mode: multiple motion events, last position wins" {
    const ctx = MockCtx.init(640, 480) orelse return error.SkipZigTest;
    defer ctx.deinit();

    var state: [c.ASHMIF_MSTATE_SZ]u8 = [_]u8{0} ** c.ASHMIF_MSTATE_SZ;
    c.arcan_shmif_mousestate_setup(ctx.con, c.ARCAN_MOUSESTATE_ABSOLUTE, &state);

    var ev1 = makeMouseMotion(100, 200);
    var ev2 = makeMouseMotion(300, 400);
    var out_x: c_int = 0;
    var out_y: c_int = 0;

    _ = c.arcan_shmif_mousestate(ctx.con, &state, &ev1, &out_x, &out_y);
    const ok = c.arcan_shmif_mousestate(ctx.con, &state, &ev2, &out_x, &out_y);
    try testing.expect(ok);
    try testing.expectEqual(@as(c_int, 300), out_x);
    try testing.expectEqual(@as(c_int, 400), out_y);
}

// 6d. Relative mode

test "relative mode: reports relative deltas directly" {
    const ctx = MockCtx.init(640, 480) orelse return error.SkipZigTest;
    defer ctx.deinit();

    var state: [c.ASHMIF_MSTATE_SZ]u8 = [_]u8{0} ** c.ASHMIF_MSTATE_SZ;
    c.arcan_shmif_mousestate_setup(ctx.con, c.ARCAN_MOUSESTATE_RELATIVE, &state);

    var ev = makeMouseMotionRel(5, -3);
    var out_x: c_int = 0;
    var out_y: c_int = 0;
    const ok = c.arcan_shmif_mousestate(ctx.con, &state, &ev, &out_x, &out_y);
    try testing.expect(ok);
    try testing.expectEqual(@as(c_int, 5), out_x);
    try testing.expectEqual(@as(c_int, -3), out_y);
}

// 6e. mousestate_ioev mirrors mousestate

test "mousestate_ioev produces same results as mousestate" {
    const ctx = MockCtx.init(640, 480) orelse return error.SkipZigTest;
    defer ctx.deinit();

    // Test with mousestate
    var state1: [c.ASHMIF_MSTATE_SZ]u8 = [_]u8{0} ** c.ASHMIF_MSTATE_SZ;
    c.arcan_shmif_mousestate_setup(ctx.con, c.ARCAN_MOUSESTATE_ABSOLUTE, &state1);

    var ev = makeMouseMotion(150, 250);
    var x1: c_int = 0;
    var y1: c_int = 0;
    _ = c.arcan_shmif_mousestate(ctx.con, &state1, &ev, &x1, &y1);

    // Test same with mousestate_ioev
    var state2: [c.ASHMIF_MSTATE_SZ]u8 = [_]u8{0} ** c.ASHMIF_MSTATE_SZ;
    c.arcan_shmif_mousestate_setup(ctx.con, c.ARCAN_MOUSESTATE_ABSOLUTE, &state2);

    var ioev = variants(&ev).io;
    var x2: c_int = 0;
    var y2: c_int = 0;
    _ = c.arcan_shmif_mousestate_ioev(ctx.con, &state2, &ioev, &x2, &y2);

    try testing.expectEqual(x1, x2);
    try testing.expectEqual(y1, y2);
}

// 6f. Button events are not mouse motion

test "button events return false (not mouse motion)" {
    const ctx = MockCtx.init(640, 480) orelse return error.SkipZigTest;
    defer ctx.deinit();

    var state: [c.ASHMIF_MSTATE_SZ]u8 = [_]u8{0} ** c.ASHMIF_MSTATE_SZ;
    c.arcan_shmif_mousestate_setup(ctx.con, c.ARCAN_MOUSESTATE_ABSOLUTE, &state);

    var ev = makeMouseButton(true);
    var out_x: c_int = 0;
    var out_y: c_int = 0;
    const ok = c.arcan_shmif_mousestate(ctx.con, &state, &ev, &out_x, &out_y);
    try testing.expect(!ok);
}

// 6g. Null state uses internal mstate

test "null state pointer uses context internal state" {
    const ctx = MockCtx.init(640, 480) orelse return error.SkipZigTest;
    defer ctx.deinit();

    // Setup with null state (uses con->priv->mstate)
    c.arcan_shmif_mousestate_setup(ctx.con, c.ARCAN_MOUSESTATE_ABSOLUTE, null);

    var ev = makeMouseMotion(50, 60);
    var out_x: c_int = 0;
    var out_y: c_int = 0;
    const ok = c.arcan_shmif_mousestate(ctx.con, null, &ev, &out_x, &out_y);
    try testing.expect(ok);
    try testing.expectEqual(@as(c_int, 50), out_x);
    try testing.expectEqual(@as(c_int, 60), out_y);
}

// 6h. Null context returns false

test "mousestate with null context returns false" {
    var state: [c.ASHMIF_MSTATE_SZ]u8 = [_]u8{0} ** c.ASHMIF_MSTATE_SZ;
    var ev = makeMouseMotion(10, 20);
    var out_x: c_int = 0;
    var out_y: c_int = 0;
    const ok = c.arcan_shmif_mousestate(null, &state, &ev, &out_x, &out_y);
    try testing.expect(!ok);
}

// 6i. Absolute mode clamps to context dimensions

test "absolute mode: coordinates clamped to context w/h" {
    const ctx = MockCtx.init(100, 100) orelse return error.SkipZigTest;
    defer ctx.deinit();

    var state: [c.ASHMIF_MSTATE_SZ]u8 = [_]u8{0} ** c.ASHMIF_MSTATE_SZ;
    c.arcan_shmif_mousestate_setup(ctx.con, c.ARCAN_MOUSESTATE_ABSOLUTE, &state);

    // Send coordinates beyond the context dimensions
    var ev = makeMouseMotion(500, 500);
    var out_x: c_int = 0;
    var out_y: c_int = 0;
    _ = c.arcan_shmif_mousestate(ctx.con, &state, &ev, &out_x, &out_y);

    // Should be clamped to w/h (100)
    try testing.expect(out_x <= 100);
    try testing.expect(out_y <= 100);
}
