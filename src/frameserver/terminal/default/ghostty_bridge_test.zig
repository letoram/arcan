// Tests for the ghostty bridge — the VT parser integration that connects
// ghostty's terminal emulator to arcan's TUI rendering pipeline.
//
// These tests exercise the ACTUAL path that `cat` output takes through
// afsrv_terminal: bytes → ghostty VT parser → terminal screen → TUI front buffer.
//
// No tolerance, no stubs. Feed real VT sequences, read real cell state.

const std = @import("std");
const testing = std.testing;
const GhosttyBridge = @import("ghostty_bridge").GhosttyBridge;

const test_alloc = testing.allocator;

// Fake TUI buffer
// syncToFrontBuffer writes into a raw byte buffer using hardcoded offsets.
// We create a fake TUI context in memory with the same layout.
const OFF_TUI_FRONT: usize = 32;
const OFF_TUI_FSTAMP: usize = 58;
const OFF_TUI_DIRTY: usize = 128;
const OFF_TUI_ROWS: usize = 228;
const OFF_TUI_COLS: usize = 232;
const TUI_CELL_SZ: usize = 28;
const CELL_OFF_CH: usize = 12;
const CELL_OFF_DRAW_CH: usize = 16;
const CELL_OFF_FC: usize = 0;
const CELL_OFF_BC: usize = 3;
const CELL_OFF_AFF: usize = 6;
const CELL_OFF_FSTAMP: usize = 25;

const TUI_ATTR_BOLD: u16 = 1;
const TUI_ATTR_UNDERLINE: u16 = 2;
const TUI_ATTR_ITALIC: u16 = 8;
const TUI_ATTR_INVERSE: u16 = 16;
const TUI_ATTR_STRIKETHROUGH: u16 = 128;

const FakeTui = struct {
    buf: []align(8) u8,
    front: []u8,
    rows: usize,
    cols: usize,

    fn init(allocator: std.mem.Allocator, cols: usize, rows: usize) !FakeTui {
        // Allocate the TUI context buffer (needs to be big enough for all offsets)
        const tui_size = 256; // enough for all offsets we access
        const front_size = rows * cols * TUI_CELL_SZ;
        const buf = try allocator.alignedAlloc(u8, .@"8", tui_size);
        @memset(buf, 0);
        const front = try allocator.alloc(u8, front_size);
        @memset(front, 0);

        // Set up the struct fields at the correct offsets
        const base: [*]u8 = buf.ptr;

        // front pointer
        @as(*align(1) usize, @ptrCast(base + OFF_TUI_FRONT)).* = @intFromPtr(front.ptr);

        // fstamp
        base[OFF_TUI_FSTAMP] = 1;

        // rows and cols (as c_int = i32)
        @as(*align(1) c_int, @ptrCast(base + OFF_TUI_ROWS)).* = @intCast(rows);
        @as(*align(1) c_int, @ptrCast(base + OFF_TUI_COLS)).* = @intCast(cols);

        return .{ .buf = buf, .front = front, .rows = rows, .cols = cols };
    }

    fn deinit(self: *FakeTui, allocator: std.mem.Allocator) void {
        allocator.free(self.front);
        allocator.free(self.buf);
    }

    fn tuiPtr(self: *FakeTui) *anyopaque {
        return @ptrCast(self.buf.ptr);
    }

    fn cellAt(self: *const FakeTui, row: usize, col: usize) []const u8 {
        const offset = (row * self.cols + col) * TUI_CELL_SZ;
        return self.front[offset..][0..TUI_CELL_SZ];
    }

    fn chAt(self: *const FakeTui, row: usize, col: usize) u32 {
        const cell = self.cellAt(row, col);
        return @as(*align(1) const u32, @ptrCast(cell.ptr + CELL_OFF_CH)).*;
    }

    fn drawChAt(self: *const FakeTui, row: usize, col: usize) u32 {
        const cell = self.cellAt(row, col);
        return @as(*align(1) const u32, @ptrCast(cell.ptr + CELL_OFF_DRAW_CH)).*;
    }

    fn fgAt(self: *const FakeTui, row: usize, col: usize) [3]u8 {
        const cell = self.cellAt(row, col);
        return .{ cell[CELL_OFF_FC], cell[CELL_OFF_FC + 1], cell[CELL_OFF_FC + 2] };
    }

    fn bgAt(self: *const FakeTui, row: usize, col: usize) [3]u8 {
        const cell = self.cellAt(row, col);
        return .{ cell[CELL_OFF_BC], cell[CELL_OFF_BC + 1], cell[CELL_OFF_BC + 2] };
    }

    fn aflagsAt(self: *const FakeTui, row: usize, col: usize) u16 {
        const cell = self.cellAt(row, col);
        return @as(*align(1) const u16, @ptrCast(cell.ptr + CELL_OFF_AFF)).*;
    }

    fn fstampAt(self: *const FakeTui, row: usize, col: usize) u8 {
        const cell = self.cellAt(row, col);
        return cell[CELL_OFF_FSTAMP];
    }

    fn dirtyState(self: *const FakeTui) u32 {
        return @as(*align(1) const u32, @ptrCast(self.buf.ptr + OFF_TUI_DIRTY)).*;
    }
};

// Helper: create bridge, no PTY needed for input tests
fn createBridge(cols: u16, rows: u16) !*GhosttyBridge {
    return GhosttyBridge.init(test_alloc, cols, rows, -1, null);
}

// ════════════════════════════════════════════════════════════════════
// VT Parser: Plain Text
// ════════════════════════════════════════════════════════════════════

test "ghostty: plain ASCII text appears in terminal cells" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("Hello");

    // Read directly from ghostty's screen
    const screen = bridge.terminal.screens.active;
    const pin = screen.pages.pin(.{ .active = .{} }) orelse return error.TestUnexpectedResult;
    const rac = pin.rowAndCell();
    const cells = pin.node.data.getCells(rac.row);

    try testing.expectEqual(@as(u21, 'H'), cells[0].codepoint());
    try testing.expectEqual(@as(u21, 'e'), cells[1].codepoint());
    try testing.expectEqual(@as(u21, 'l'), cells[2].codepoint());
    try testing.expectEqual(@as(u21, 'l'), cells[3].codepoint());
    try testing.expectEqual(@as(u21, 'o'), cells[4].codepoint());
}

test "ghostty: cursor advances after text" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("ABCDE");
    const pos = bridge.getCursorPos();
    try testing.expectEqual(@as(u16, 5), pos.x);
    try testing.expectEqual(@as(u16, 0), pos.y);
}

test "ghostty: newline moves cursor to next row" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("Line1\r\nLine2");
    const pos = bridge.getCursorPos();
    try testing.expectEqual(@as(u16, 5), pos.x);
    try testing.expectEqual(@as(u16, 1), pos.y);
}

test "ghostty: long line wraps at column boundary" {
    var bridge = try createBridge(10, 24);
    defer bridge.deinit();

    bridge.feedInput("ABCDEFGHIJKLMNO"); // 15 chars in 10-col terminal
    const pos = bridge.getCursorPos();
    // After 15 chars in 10 cols: cursor at col 5, row 1
    try testing.expectEqual(@as(u16, 5), pos.x);
    try testing.expectEqual(@as(u16, 1), pos.y);
}

// ════════════════════════════════════════════════════════════════════
// VT Parser: ANSI Escape Sequences
// ════════════════════════════════════════════════════════════════════

test "ghostty: SGR bold attribute" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("\x1b[1mBold\x1b[0m");

    const screen = bridge.terminal.screens.active;
    const pin = screen.pages.pin(.{ .active = .{} }) orelse return error.TestUnexpectedResult;
    const rac = pin.rowAndCell();
    const cells = pin.node.data.getCells(rac.row);

    // 'B' should have bold flag
    const style = pin.style(&cells[0]);
    try testing.expect(style.flags.bold);
}

test "ghostty: SGR color 256-palette" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    // Set foreground to palette color 1 (red)
    bridge.feedInput("\x1b[38;5;1mR");

    const screen = bridge.terminal.screens.active;
    const pin = screen.pages.pin(.{ .active = .{} }) orelse return error.TestUnexpectedResult;
    const rac = pin.rowAndCell();
    const cells = pin.node.data.getCells(rac.row);

    try testing.expectEqual(@as(u21, 'R'), cells[0].codepoint());

    const style = pin.style(&cells[0]);
    // Should be palette color 1
    switch (style.fg_color) {
        .palette => |idx| try testing.expectEqual(@as(u8, 1), idx),
        else => return error.TestUnexpectedResult,
    }
}

test "ghostty: SGR RGB true color" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    // Set foreground to RGB(255, 128, 0)
    bridge.feedInput("\x1b[38;2;255;128;0mX");

    const screen = bridge.terminal.screens.active;
    const pin = screen.pages.pin(.{ .active = .{} }) orelse return error.TestUnexpectedResult;
    const rac = pin.rowAndCell();
    const cells = pin.node.data.getCells(rac.row);

    const style = pin.style(&cells[0]);
    switch (style.fg_color) {
        .rgb => |rgb| {
            try testing.expectEqual(@as(u8, 255), rgb.r);
            try testing.expectEqual(@as(u8, 128), rgb.g);
            try testing.expectEqual(@as(u8, 0), rgb.b);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "ghostty: cursor movement CSI sequences" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    // Move cursor to row 5, col 10 (1-indexed in VT)
    bridge.feedInput("\x1b[5;10H");
    const pos = bridge.getCursorPos();
    try testing.expectEqual(@as(u16, 9), pos.x); // 0-indexed
    try testing.expectEqual(@as(u16, 4), pos.y);
}

test "ghostty: erase in display (ED)" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("AAAA\x1b[H\x1b[2J"); // write, home, clear screen
    const pos = bridge.getCursorPos();
    try testing.expectEqual(@as(u16, 0), pos.x);
    try testing.expectEqual(@as(u16, 0), pos.y);

    // Cell at 0,0 should be empty after clear
    const screen = bridge.terminal.screens.active;
    const pin = screen.pages.pin(.{ .active = .{} }) orelse return error.TestUnexpectedResult;
    const rac = pin.rowAndCell();
    const cells = pin.node.data.getCells(rac.row);
    try testing.expectEqual(@as(u21, 0), cells[0].codepoint());
}

test "ghostty: erase in line (EL)" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("ABCDEFGH\x1b[5G\x1b[K"); // write 8 chars, go to col 5, erase to EOL
    const screen = bridge.terminal.screens.active;
    const pin = screen.pages.pin(.{ .active = .{} }) orelse return error.TestUnexpectedResult;
    const rac = pin.rowAndCell();
    const cells = pin.node.data.getCells(rac.row);

    // Cols 0-3 should have A,B,C,D
    try testing.expectEqual(@as(u21, 'A'), cells[0].codepoint());
    try testing.expectEqual(@as(u21, 'D'), cells[3].codepoint());
    // Col 4 onwards should be empty
    try testing.expectEqual(@as(u21, 0), cells[4].codepoint());
    try testing.expectEqual(@as(u21, 0), cells[5].codepoint());
}

// ════════════════════════════════════════════════════════════════════
// syncToFrontBuffer: ghostty screen → TUI cell buffer
// ════════════════════════════════════════════════════════════════════

test "ghostty: syncToFrontBuffer writes codepoints" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("Hi!");

    var tui = try FakeTui.init(test_alloc, 80, 24);
    defer tui.deinit(test_alloc);

    bridge.syncToFrontBuffer(tui.tuiPtr());

    try testing.expectEqual(@as(u32, 'H'), tui.chAt(0, 0));
    try testing.expectEqual(@as(u32, 'i'), tui.chAt(0, 1));
    try testing.expectEqual(@as(u32, '!'), tui.chAt(0, 2));
    // draw_ch should match ch
    try testing.expectEqual(@as(u32, 'H'), tui.drawChAt(0, 0));
}

test "ghostty: syncToFrontBuffer writes empty cells as zero" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("AB");

    var tui = try FakeTui.init(test_alloc, 80, 24);
    defer tui.deinit(test_alloc);

    bridge.syncToFrontBuffer(tui.tuiPtr());

    try testing.expectEqual(@as(u32, 'A'), tui.chAt(0, 0));
    try testing.expectEqual(@as(u32, 'B'), tui.chAt(0, 1));
    try testing.expectEqual(@as(u32, 0), tui.chAt(0, 2)); // empty
    try testing.expectEqual(@as(u32, 0), tui.chAt(1, 0)); // next row empty
}

test "ghostty: syncToFrontBuffer maps SGR bold to TUI_ATTR_BOLD" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("\x1b[1mB\x1b[0mN");

    var tui = try FakeTui.init(test_alloc, 80, 24);
    defer tui.deinit(test_alloc);

    bridge.syncToFrontBuffer(tui.tuiPtr());

    // 'B' should have bold, 'N' should not
    try testing.expect((tui.aflagsAt(0, 0) & TUI_ATTR_BOLD) != 0);
    try testing.expectEqual(@as(u16, 0), tui.aflagsAt(0, 1) & TUI_ATTR_BOLD);
}

test "ghostty: syncToFrontBuffer maps italic and underline" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("\x1b[3mI\x1b[0m\x1b[4mU\x1b[0mN");

    var tui = try FakeTui.init(test_alloc, 80, 24);
    defer tui.deinit(test_alloc);

    bridge.syncToFrontBuffer(tui.tuiPtr());

    try testing.expect((tui.aflagsAt(0, 0) & TUI_ATTR_ITALIC) != 0);
    try testing.expect((tui.aflagsAt(0, 1) & TUI_ATTR_UNDERLINE) != 0);
    try testing.expectEqual(@as(u16, 0), tui.aflagsAt(0, 2) & (TUI_ATTR_ITALIC | TUI_ATTR_UNDERLINE));
}

test "ghostty: syncToFrontBuffer maps RGB colors" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    // FG red, BG blue
    bridge.feedInput("\x1b[38;2;255;0;0m\x1b[48;2;0;0;255mX\x1b[0m");

    var tui = try FakeTui.init(test_alloc, 80, 24);
    defer tui.deinit(test_alloc);

    bridge.syncToFrontBuffer(tui.tuiPtr());

    const fg = tui.fgAt(0, 0);
    const bg = tui.bgAt(0, 0);
    try testing.expectEqual(@as(u8, 255), fg[0]); // R
    try testing.expectEqual(@as(u8, 0), fg[1]);   // G
    try testing.expectEqual(@as(u8, 0), fg[2]);   // B
    try testing.expectEqual(@as(u8, 0), bg[0]);   // R
    try testing.expectEqual(@as(u8, 0), bg[1]);   // G
    try testing.expectEqual(@as(u8, 255), bg[2]); // B
}

test "ghostty: syncToFrontBuffer sets fstamp on all cells" {
    var bridge = try createBridge(10, 2);
    defer bridge.deinit();

    bridge.feedInput("Hi");

    var tui = try FakeTui.init(test_alloc, 10, 2);
    defer tui.deinit(test_alloc);

    bridge.syncToFrontBuffer(tui.tuiPtr());

    // All cells in synced rows should have fstamp = 1
    for (0..2) |row| {
        for (0..10) |col| {
            try testing.expectEqual(@as(u8, 1), tui.fstampAt(row, col));
        }
    }
}

test "ghostty: syncToFrontBuffer marks dirty" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("X");

    var tui = try FakeTui.init(test_alloc, 80, 24);
    defer tui.deinit(test_alloc);

    bridge.syncToFrontBuffer(tui.tuiPtr());
    try testing.expect((tui.dirtyState() & 2) != 0); // DIRTY_PARTIAL
}

test "ghostty: syncToFrontBuffer multiline" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("Row0\r\nRow1\r\nRow2");

    var tui = try FakeTui.init(test_alloc, 80, 24);
    defer tui.deinit(test_alloc);

    bridge.syncToFrontBuffer(tui.tuiPtr());

    try testing.expectEqual(@as(u32, 'R'), tui.chAt(0, 0));
    try testing.expectEqual(@as(u32, '0'), tui.chAt(0, 3));
    try testing.expectEqual(@as(u32, 'R'), tui.chAt(1, 0));
    try testing.expectEqual(@as(u32, '1'), tui.chAt(1, 3));
    try testing.expectEqual(@as(u32, 'R'), tui.chAt(2, 0));
    try testing.expectEqual(@as(u32, '2'), tui.chAt(2, 3));
}

// ════════════════════════════════════════════════════════════════════
// Full Pipeline: VT → ghostty → TUI buffer (what `cat` actually does)
// ════════════════════════════════════════════════════════════════════

test "ghostty: cat output pipeline - plain text" {
    // Simulates: echo "Hello, World!" | cat in afsrv_terminal
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("Hello, World!\r\n$ ");

    var tui = try FakeTui.init(test_alloc, 80, 24);
    defer tui.deinit(test_alloc);

    bridge.syncToFrontBuffer(tui.tuiPtr());

    // Row 0: "Hello, World!"
    const expected = "Hello, World!";
    for (expected, 0..) |ch, i| {
        try testing.expectEqual(@as(u32, ch), tui.chAt(0, i));
    }
    // Row 1: "$ "
    try testing.expectEqual(@as(u32, '$'), tui.chAt(1, 0));
    try testing.expectEqual(@as(u32, ' '), tui.chAt(1, 1));
}

test "ghostty: cat output pipeline - ANSI colored text" {
    // Simulates: printf '\033[31mRED\033[32mGREEN\033[0m\n'
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("\x1b[31mRED\x1b[32mGREEN\x1b[0m\r\n");

    var tui = try FakeTui.init(test_alloc, 80, 24);
    defer tui.deinit(test_alloc);

    bridge.syncToFrontBuffer(tui.tuiPtr());

    // "RED" at cols 0-2, "GREEN" at cols 3-7
    try testing.expectEqual(@as(u32, 'R'), tui.chAt(0, 0));
    try testing.expectEqual(@as(u32, 'E'), tui.chAt(0, 1));
    try testing.expectEqual(@as(u32, 'D'), tui.chAt(0, 2));
    try testing.expectEqual(@as(u32, 'G'), tui.chAt(0, 3));

    // "RED" should have palette color 1 (red) foreground
    // After syncToFrontBuffer, fg RGB comes from palette[1]
    const red_fg = tui.fgAt(0, 0);
    const green_fg = tui.fgAt(0, 3);
    // Red and green should be different colors
    try testing.expect(red_fg[0] != green_fg[0] or red_fg[1] != green_fg[1]);
}

test "ghostty: cat output pipeline - box drawing characters" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    // UTF-8 for ┌─┐
    bridge.feedInput("\xe2\x94\x8c\xe2\x94\x80\xe2\x94\x90");

    var tui = try FakeTui.init(test_alloc, 80, 24);
    defer tui.deinit(test_alloc);

    bridge.syncToFrontBuffer(tui.tuiPtr());

    try testing.expectEqual(@as(u32, 0x250C), tui.chAt(0, 0)); // ┌
    try testing.expectEqual(@as(u32, 0x2500), tui.chAt(0, 1)); // ─
    try testing.expectEqual(@as(u32, 0x2510), tui.chAt(0, 2)); // ┐
}

// ════════════════════════════════════════════════════════════════════
// Bridge API
// ════════════════════════════════════════════════════════════════════

test "ghostty: resize changes terminal dimensions" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.resize(40, 12);

    // Cursor should be within new bounds
    const pos = bridge.getCursorPos();
    try testing.expect(pos.x < 40);
    try testing.expect(pos.y < 12);
}

test "ghostty: fullReset clears screen" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.feedInput("Some text here");
    bridge.fullReset();

    const pos = bridge.getCursorPos();
    try testing.expectEqual(@as(u16, 0), pos.x);
    try testing.expectEqual(@as(u16, 0), pos.y);
}

test "ghostty: palette color set/get roundtrips" {
    var bridge = try createBridge(80, 24);
    defer bridge.deinit();

    bridge.setColor(42, 0xAA, 0xBB, 0xCC);
    const c = bridge.getColor(42);
    try testing.expectEqual(@as(u8, 0xAA), c.r);
    try testing.expectEqual(@as(u8, 0xBB), c.g);
    try testing.expectEqual(@as(u8, 0xCC), c.b);
}
