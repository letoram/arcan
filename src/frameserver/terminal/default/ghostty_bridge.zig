// ghostty_bridge.zig — Bridge between arcan's terminal frameserver and ghostty-vt.
//
// Replaces TSM with ghostty's SIMD-optimized VT parser, screen management,
// and input encoding.
//
// Architecture:
// - ArcanHandler wraps ghostty's ReadonlyHandler + adds DA/DSR/title/clipboard handling
// - Stream persists across feedInput calls (VT parser state maintained)
// - TUI context passed as opaque pointer (no @cImport needed)

const std = @import("std");
const ghostty = @import("ghostty-vt");

const Terminal = ghostty.Terminal;
const Screen = ghostty.Screen;
const ReadonlyHandler = ghostty.ReadonlyHandler;
const StreamAction = ghostty.StreamAction;

extern "c" fn write(fd: c_int, buf: ?*const anyopaque, count: usize) isize;
extern "c" fn arcan_tui_ident(tui: *anyopaque, ident: [*c]const u8) void;

// TUI context byte offsets (aarch64-linux, gcc offsetof)
const OFF_TUI_FRONT: usize = 32; // struct tui_cell* front
const OFF_TUI_FSTAMP: usize = 58; // uint8_t fstamp
const OFF_TUI_DIRTY: usize = 128; // enum dirty_state (u32)
const OFF_TUI_ROWS: usize = 228; // int rows
const OFF_TUI_COLS: usize = 232; // int cols

// tui_cell layout (28 bytes total)
const TUI_CELL_SZ: usize = 28;
const CELL_OFF_FC: usize = 0; // attr.fc[3] — foreground RGB
const CELL_OFF_BC: usize = 3; // attr.bc[3] — background RGB
const CELL_OFF_AFF: usize = 6; // attr.aflags (u16)
const CELL_OFF_CID: usize = 8; // attr.custom_id (u8)
const CELL_OFF_CH: usize = 12; // ch (u32)
const CELL_OFF_DRAW_CH: usize = 16; // draw_ch (u32)
const CELL_OFF_FSTAMP: usize = 25; // fstamp (u8)

const DIRTY_PARTIAL: u32 = 2;

// TUI attribute flags (from tui_int.h)
const TUI_ATTR_BOLD: u16 = 1;
const TUI_ATTR_UNDERLINE: u16 = 2;
const TUI_ATTR_ITALIC: u16 = 8;
const TUI_ATTR_INVERSE: u16 = 16;
const TUI_ATTR_BLINK: u16 = 64;
const TUI_ATTR_STRIKETHROUGH: u16 = 128;
const TUI_ATTR_COLOR_INDEXED: u16 = 512;

const TUI_COL_BG: u8 = 4;
const TUI_COL_TEXT: u8 = 5;

/// Custom stream handler: delegates terminal state to ReadonlyHandler,
/// adds interactive responses (DA, DSR) and external actions (title, clipboard).
pub const ArcanHandler = struct {
    readonly: ReadonlyHandler,
    pty_fd: i32,
    tui: ?*anyopaque,
    clipboard_cb: ?*const fn ([*c]const u8, usize) void = null,

    pub fn init(terminal: *Terminal, pty_fd: i32, tui: ?*anyopaque) ArcanHandler {
        return .{
            .readonly = ReadonlyHandler.init(terminal),
            .pty_fd = pty_fd,
            .tui = tui,
        };
    }

    pub fn deinit(self: *ArcanHandler) void {
        self.readonly.deinit();
    }

    pub fn vt(
        self: *ArcanHandler,
        comptime action: StreamAction.Tag,
        value: StreamAction.Value(action),
    ) !void {
        // ReadonlyHandler processes all terminal-state-modifying actions (no-ops for queries)
        try self.readonly.vt(action, value);

        // Additionally handle the actions ReadonlyHandler ignores
        switch (action) {
            .device_attributes => self.handleDA(value),
            .device_status => self.handleDSR(value),
            .window_title => self.handleTitle(value),
            .clipboard_contents => self.handleClipboard(value),
            else => {},
        }
    }

    fn handleDA(self: *ArcanHandler, value: StreamAction.Value(.device_attributes)) void {
        // DA1/DA2/DA3 — respond like xterm/VT220
        const response: []const u8 = if (value == .primary)
            "\x1b[?62;22c"
        else if (value == .secondary)
            "\x1b[>0;10;1c"
        else if (value == .tertiary)
            "\x1bP!|00000000\x1b\\"
        else
            return;
        _ = write(self.pty_fd, response.ptr, response.len);
    }

    fn handleDSR(self: *ArcanHandler, value: StreamAction.Value(.device_status)) void {
        const req = value.request;
        if (req == .operating_status) {
            const response = "\x1b[0n";
            _ = write(self.pty_fd, response.ptr, response.len);
        } else if (req == .cursor_position) {
            const cursor = self.readonly.terminal.screens.active.cursor;
            var buf: [32]u8 = undefined;
            const response = std.fmt.bufPrint(&buf, "\x1b[{d};{d}R", .{
                @as(u32, cursor.y) + 1,
                @as(u32, cursor.x) + 1,
            }) catch return;
            _ = write(self.pty_fd, response.ptr, response.len);
        }
        // color_scheme and others: ignore for now
    }

    fn handleTitle(self: *ArcanHandler, value: StreamAction.Value(.window_title)) void {
        if (self.tui) |tui| {
            // title is a []const u8 slice — need to null-terminate for C
            var buf: [256]u8 = undefined;
            const title = value.title;
            const len = @min(title.len, buf.len - 1);
            @memcpy(buf[0..len], title[0..len]);
            buf[len] = 0;
            arcan_tui_ident(tui, &buf);
        }
    }

    fn handleClipboard(self: *ArcanHandler, value: StreamAction.Value(.clipboard_contents)) void {
        if (self.clipboard_cb) |cb| {
            // data is []const u8 — base64-encoded clipboard content
            var buf: [8192]u8 = undefined;
            const data = value.data;
            const len = @min(data.len, buf.len - 1);
            @memcpy(buf[0..len], data[0..len]);
            buf[len] = 0;
            cb(&buf, len);
        }
    }
};

pub const ArcanStream = ghostty.Stream(ArcanHandler);

pub const GhosttyBridge = struct {
    /// Viewport-relative selection range. Row/col indices refer to the
    /// currently visible viewport (same coord space as mouse events arrive
    /// in). `active` is true while the user is still dragging.
    pub const Selection = struct {
        start_row: u16,
        start_col: u16,
        end_row: u16,
        end_col: u16,
        active: bool,
    };

    terminal: Terminal,
    stream: ArcanStream,
    alloc: std.mem.Allocator,
    pty_fd: i32,
    /// null when there's nothing to copy or render. Renderer (syncToFrontBuffer)
    /// reads this; mouse handlers in arcterm write via selectionStart/Update/End.
    selection: ?Selection = null,

    pub fn init(alloc: std.mem.Allocator, cols: u16, rows: u16, pty_fd: i32, tui: ?*anyopaque) !*GhosttyBridge {
        const self = try alloc.create(GhosttyBridge);
        self.terminal = try Terminal.init(alloc, .{
            .cols = cols,
            .rows = rows,
        });

        // Default the kitty keyboard protocol (KKB) ON. With KKB off, ghostty's
        // encoder falls back to the fixterms CSI-u path, which neither bash
        // nor kitty-aware programs (claude, helix, …) speak — chord input is
        // emitted as literal `^[[…u` text. Seeding `disambiguate=true` on the
        // primary screen flips the encoder onto the kitty path so KKB-aware
        // programs see well-formed sequences from the first byte. The
        // alternate screen (lazy-init in switchScreen) inherits the default
        // disabled state; programs that switch to alt-screen typically push
        // their own KKB state via `CSI > {flags} u`, which our seed never
        // gets in the way of.
        const kkb_default: ghostty.kitty.KeyFlags = .{ .disambiguate = true };
        self.terminal.screens.active.kitty_keyboard.set(.set, kkb_default);

        self.alloc = alloc;
        self.pty_fd = pty_fd;
        self.selection = null;
        // Stream stores handler by value; handler.readonly.terminal points to &self.terminal
        self.stream = ArcanStream.initAlloc(alloc, ArcanHandler.init(&self.terminal, pty_fd, tui));
        return self;
    }

    pub fn deinit(self: *GhosttyBridge) void {
        self.stream.deinit();
        self.terminal.deinit(self.alloc);
        const alloc = self.alloc;
        alloc.destroy(self);
    }

    /// Feed PTY output bytes through the VT parser. Stream state persists.
    pub fn feedInput(self: *GhosttyBridge, data: []const u8) void {
        self.stream.nextSlice(data) catch {};
    }

    /// Resize the terminal.
    pub fn resize(self: *GhosttyBridge, cols: u16, rows: u16) void {
        self.terminal.resize(self.alloc, cols, rows) catch {};
    }

    /// Hard reset.
    pub fn fullReset(self: *GhosttyBridge) void {
        self.terminal.fullReset();
    }

    /// Get cursor position.
    pub fn getCursorPos(self: *GhosttyBridge) struct { x: u16, y: u16 } {
        const cursor = self.terminal.screens.active.cursor;
        return .{ .x = cursor.x, .y = cursor.y };
    }

    /// Set TUI context (may change after reset).
    pub fn setTui(self: *GhosttyBridge, tui: ?*anyopaque) void {
        self.stream.handler.tui = tui;
    }

    /// Set a palette color (idx 0-255).
    pub fn setColor(self: *GhosttyBridge, idx: u8, r: u8, g: u8, b: u8) void {
        self.terminal.colors.palette.current[idx] = .{ .r = r, .g = g, .b = b };
    }

    /// Get a palette color (idx 0-255).
    pub fn getColor(self: *GhosttyBridge, idx: u8) struct { r: u8, g: u8, b: u8 } {
        const rgb = self.terminal.colors.palette.current[idx];
        return .{ .r = rgb.r, .g = rgb.g, .b = rgb.b };
    }

    /// Set clipboard callback for OSC 52.
    pub fn setClipboardCb(self: *GhosttyBridge, cb: ?*const fn ([*c]const u8, usize) void) void {
        self.stream.handler.clipboard_cb = cb;
    }

    // Selection (mouse-drag text range for copy)

    pub fn selectionStart(self: *GhosttyBridge, row: u16, col: u16) void {
        self.selection = .{
            .start_row = row,
            .start_col = col,
            .end_row = row,
            .end_col = col,
            .active = true,
        };
    }

    pub fn selectionUpdate(self: *GhosttyBridge, row: u16, col: u16) void {
        if (self.selection) |*sel| {
            if (!sel.active) return;
            sel.end_row = row;
            sel.end_col = col;
        }
    }

    /// Finalise the drag. Zero-length selections (plain click) clear the
    /// selection so we don't leave a single highlighted cell hanging.
    pub fn selectionEnd(self: *GhosttyBridge) void {
        if (self.selection) |*sel| {
            sel.active = false;
            if (sel.start_row == sel.end_row and sel.start_col == sel.end_col) {
                self.selection = null;
            }
        }
    }

    pub fn selectionClear(self: *GhosttyBridge) void {
        self.selection = null;
    }

    /// Does (row, col) fall inside the current selection? Uses text-flow
    /// ordering (first-row right-of-start, middle rows full, last-row
    /// left-of-end) after normalising the range so start is top-left.
    pub fn selectionIsSelected(self: *const GhosttyBridge, row: u16, col: u16) bool {
        const sel = self.selection orelse return false;
        const norm = normaliseRange(sel);
        if (row < norm.top_row or row > norm.bot_row) return false;
        if (norm.top_row == norm.bot_row) {
            return col >= norm.top_col and col <= norm.bot_col;
        }
        if (row == norm.top_row) return col >= norm.top_col;
        if (row == norm.bot_row) return col <= norm.bot_col;
        return true; // full row in the middle of a multi-row selection
    }

    const NormalisedRange = struct {
        top_row: u16,
        top_col: u16,
        bot_row: u16,
        bot_col: u16,
    };

    fn normaliseRange(sel: Selection) NormalisedRange {
        const sr = sel.start_row;
        const sc = sel.start_col;
        const er = sel.end_row;
        const ec = sel.end_col;
        if (sr < er or (sr == er and sc <= ec)) {
            return .{ .top_row = sr, .top_col = sc, .bot_row = er, .bot_col = ec };
        }
        return .{ .top_row = er, .top_col = ec, .bot_row = sr, .bot_col = sc };
    }

    /// Extract the currently-selected text as an owned UTF-8 buffer.
    /// Iterates the viewport-pinned rows in the same order syncToFrontBuffer
    /// does, so row indices match. Joins rows with '\n', trims trailing
    /// whitespace per row, skips wide-cell spacer halves, null-terminates
    /// the payload so arcan_tui_copy can pass a C string.
    pub fn selectionText(self: *GhosttyBridge, alloc: std.mem.Allocator) !?[]u8 {
        const sel = self.selection orelse return null;
        const norm = normaliseRange(sel);

        var out: std.ArrayListUnmanaged(u8) = .{};
        errdefer out.deinit(alloc);

        const screen = self.terminal.screens.active;
        const pin = screen.pages.pin(.{ .viewport = .{} }) orelse return null;
        var row_it = pin.rowIterator(.right_down, null);

        var row_idx: u16 = 0;
        while (row_it.next()) |row_pin| : (row_idx += 1) {
            if (row_idx > norm.bot_row) break;
            if (row_idx < norm.top_row) continue;

            const rac = row_pin.rowAndCell();
            const all_cells = row_pin.node.data.getCells(rac.row);

            const col_lo: usize = if (row_idx == norm.top_row) norm.top_col else 0;
            const col_hi_excl: usize = if (row_idx == norm.bot_row)
                @min(@as(usize, norm.bot_col) + 1, all_cells.len)
            else
                all_cells.len;

            // Per-row buffer so we can trim trailing whitespace.
            var row_buf: std.ArrayListUnmanaged(u8) = .{};
            defer row_buf.deinit(alloc);

            var c: usize = col_lo;
            while (c < col_hi_excl) : (c += 1) {
                const cell = &all_cells[c];
                if (cell.wide == .spacer_tail or cell.wide == .spacer_head) continue;
                const cp: u21 = @intCast(cell.codepoint());
                if (cp == 0) {
                    try row_buf.append(alloc, ' ');
                    continue;
                }
                var ebuf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(cp, &ebuf) catch {
                    try row_buf.append(alloc, '?');
                    continue;
                };
                try row_buf.appendSlice(alloc, ebuf[0..n]);
            }

            // trim trailing spaces on the row
            var end: usize = row_buf.items.len;
            while (end > 0 and row_buf.items[end - 1] == ' ') : (end -= 1) {}
            try out.appendSlice(alloc, row_buf.items[0..end]);

            // Only emit a newline when this row is a hard break. Ghostty
            // marks soft-wrapped lines (where a logical line overflows into
            // the next row) with `row.wrap = true`; the continuation row is
            // part of the same logical line, so gluing the two row-buffers
            // together reconstructs the original text exactly. Without this
            // check, pasting a copied wrapped command line would insert
            // spurious `\n`s that chop it into pieces.
            const row_ptr = rac.row;
            const is_soft_wrap = row_ptr.wrap;
            if (row_idx < norm.bot_row and !is_soft_wrap) {
                try out.append(alloc, '\n');
            }
        }

        try out.append(alloc, 0); // NUL terminator for C consumers (arcan_tui_copy)
        return try out.toOwnedSlice(alloc);
    }

    /// Sync ghostty screen state to TUI front buffer.
    /// Called from the refresh hook — iterates active screen cells and writes
    /// codepoints + styled attributes into tui->front[].
    pub fn syncToFrontBuffer(self: *GhosttyBridge, tui: *anyopaque) void {
        const base: [*]u8 = @ptrCast(tui);

        // Read TUI context fields via offsets
        const front: [*]u8 = @as(*align(1) ?[*]u8, @ptrCast(base + OFF_TUI_FRONT)).* orelse return;
        const fstamp: u8 = base[OFF_TUI_FSTAMP];
        const rows: usize = @intCast(@as(*align(1) c_int, @ptrCast(base + OFF_TUI_ROWS)).*);
        const cols: usize = @intCast(@as(*align(1) c_int, @ptrCast(base + OFF_TUI_COLS)).*);

        // Get active screen and iterate rows. Render from the viewport pin
        // (not .active) so wheel-driven scrollback through ghostty's history
        // pages actually shows up in the front buffer. When the viewport is
        // parked on the live area, this is identical to `.active`.
        const screen = self.terminal.screens.active;
        const pin = screen.pages.pin(.{ .viewport = .{} }) orelse return;
        var row_it = pin.rowIterator(.right_down, null);

        var row_idx: usize = 0;
        while (row_it.next()) |row_pin| {
            if (row_idx >= rows) break;

            const rac = row_pin.rowAndCell();
            const all_cells = row_pin.node.data.getCells(rac.row);
            const ncols = @min(all_cells.len, cols);

            for (0..ncols) |col_idx| {
                const cell = &all_cells[col_idx];
                const cell_base = front + (row_idx * cols + col_idx) * TUI_CELL_SZ;

                // Get codepoint
                const cp: u32 = cell.codepoint();

                // Skip spacer cells (part of wide character)
                if (cell.wide == .spacer_tail or cell.wide == .spacer_head) {
                    @as(*align(1) u32, @ptrCast(cell_base + CELL_OFF_CH)).* = 0;
                    @as(*align(1) u32, @ptrCast(cell_base + CELL_OFF_DRAW_CH)).* = 0;
                    cell_base[CELL_OFF_FSTAMP] = fstamp;
                    continue;
                }

                // Write codepoint to both ch and draw_ch
                @as(*align(1) u32, @ptrCast(cell_base + CELL_OFF_CH)).* = cp;
                @as(*align(1) u32, @ptrCast(cell_base + CELL_OFF_DRAW_CH)).* = cp;

                // Get style and map colors + attributes
                const style = row_pin.style(cell);

                const fg = self.resolveColor(style.fg_color, true);
                const bg = self.resolveColor(style.bg_color, false);

                cell_base[CELL_OFF_FC + 0] = fg[0];
                cell_base[CELL_OFF_FC + 1] = fg[1];
                cell_base[CELL_OFF_FC + 2] = fg[2];
                cell_base[CELL_OFF_BC + 0] = bg[0];
                cell_base[CELL_OFF_BC + 1] = bg[1];
                cell_base[CELL_OFF_BC + 2] = bg[2];

                // Map ghostty style flags → TUI attribute flags
                var aflags: u16 = 0;
                if (style.flags.bold) aflags |= TUI_ATTR_BOLD;
                if (style.flags.italic) aflags |= TUI_ATTR_ITALIC;
                if (style.flags.underline != .none) aflags |= TUI_ATTR_UNDERLINE;
                if (style.flags.inverse) aflags |= TUI_ATTR_INVERSE;
                if (style.flags.blink) aflags |= TUI_ATTR_BLINK;
                if (style.flags.strikethrough) aflags |= TUI_ATTR_STRIKETHROUGH;

                // Flip inverse-video for cells inside a drag-selection so the
                // user can see what's about to be copied.
                if (self.selectionIsSelected(@intCast(row_idx), @intCast(col_idx))) {
                    aflags ^= TUI_ATTR_INVERSE;
                }

                @as(*align(1) u16, @ptrCast(cell_base + CELL_OFF_AFF)).* = aflags;

                // Clear custom_id
                cell_base[CELL_OFF_CID] = 0;

                // Write fstamp
                cell_base[CELL_OFF_FSTAMP] = fstamp;
            }

            // Clear remaining columns in this row. Use COLOR_INDEXED + TUI_COL_BG
            // so the renderer picks the proper terminal-bg from arcan's palette
            // (typically a dark grey, not pure black). Writing literal RGB from
            // ghostty's palette[0] yields actual black, which is what produced
            // the staircase shape — htop cells with explicit bg vs. our cleared
            // cells using ghostty's default bg.
            for (ncols..cols) |col_idx| {
                const cell_base = front + (row_idx * cols + col_idx) * TUI_CELL_SZ;
                @as(*align(1) u32, @ptrCast(cell_base + CELL_OFF_CH)).* = 0;
                @as(*align(1) u32, @ptrCast(cell_base + CELL_OFF_DRAW_CH)).* = 0;
                @as(*align(1) u16, @ptrCast(cell_base + CELL_OFF_AFF)).* = TUI_ATTR_COLOR_INDEXED;
                cell_base[CELL_OFF_FC + 0] = TUI_COL_TEXT;
                cell_base[CELL_OFF_BC + 0] = TUI_COL_BG;
                cell_base[CELL_OFF_FSTAMP] = fstamp;
            }

            row_idx += 1;
        }

        // Clear rows past ghostty's last yielded row.
        while (row_idx < rows) : (row_idx += 1) {
            for (0..cols) |col_idx| {
                const cell_base = front + (row_idx * cols + col_idx) * TUI_CELL_SZ;
                @as(*align(1) u32, @ptrCast(cell_base + CELL_OFF_CH)).* = 0;
                @as(*align(1) u32, @ptrCast(cell_base + CELL_OFF_DRAW_CH)).* = 0;
                @as(*align(1) u16, @ptrCast(cell_base + CELL_OFF_AFF)).* = TUI_ATTR_COLOR_INDEXED;
                cell_base[CELL_OFF_FC + 0] = TUI_COL_TEXT;
                cell_base[CELL_OFF_BC + 0] = TUI_COL_BG;
                cell_base[CELL_OFF_FSTAMP] = fstamp;
            }
        }

        // Mark TUI dirty
        const dirty_ptr: *align(1) u32 = @ptrCast(base + OFF_TUI_DIRTY);
        dirty_ptr.* |= DIRTY_PARTIAL;
    }

    /// Resolve a ghostty Color to RGB bytes, using the terminal palette for
    /// .none (default) and .palette colors.
    fn resolveColor(self: *const GhosttyBridge, color: anytype, is_fg: bool) [3]u8 {
        return switch (color) {
            .none => blk: {
                // Default: palette index 7 (white) for fg, 0 (black) for bg
                const idx: u8 = if (is_fg) 7 else 0;
                const rgb = self.terminal.colors.palette.current[idx];
                break :blk .{ rgb.r, rgb.g, rgb.b };
            },
            .palette => |idx| blk: {
                const rgb = self.terminal.colors.palette.current[idx];
                break :blk .{ rgb.r, rgb.g, rgb.b };
            },
            .rgb => |rgb| .{ rgb.r, rgb.g, rgb.b },
        };
    }

    /// Get scrollback line count (for content size hints).
    /// TODO Phase 5: iterate page list to count total rows accurately.
    pub fn getScrollbackCount(self: *GhosttyBridge) usize {
        _ = self;
        return 0;
    }

    // Phase 4: Input encoding

    /// Encode a key event via ghostty and write to PTY.
    /// keysym: TUIK keysym (SDL1.2 convention)
    /// mods: TUIM modifier bitmask
    /// unicode: unicode codepoint from subid (0 if not printable)
    pub fn encodeAndWriteKey(self: *GhosttyBridge, keysym: u32, mods: u16, unicode: u16) void {
        const gkey = tuikToGhosttyKey(keysym) orelse {
            // Unknown key — if we have a unicode codepoint, write it as UTF-8
            if (unicode > 0 and unicode < 128) {
                var ch: u8 = @intCast(unicode);
                // Apply ctrl modifier for ASCII letters
                if (mods & TUIM_CTRL != 0 and ch >= 'a' and ch <= 'z')
                    ch = ch - 'a' + 1;
                const buf: [1]u8 = .{ch};
                _ = write(self.pty_fd, &buf, 1);
            }
            return;
        };

        // Build UTF-8 text for the unicode codepoint
        var utf8_buf: [4]u8 = undefined;
        var utf8_slice: []const u8 = "";
        if (unicode > 0) {
            const len = std.unicode.utf8Encode(@intCast(unicode), &utf8_buf) catch 0;
            if (len > 0) utf8_slice = utf8_buf[0..len];
        }

        const event = ghostty.input.KeyEvent{
            .action = if (mods & TUIM_REPEAT != 0) .repeat else .press,
            .key = gkey,
            .mods = tuiModsToGhosttyMods(mods),
            .utf8 = utf8_slice,
            .unshifted_codepoint = if (gkey.codepoint()) |cp| cp else 0,
        };

        const opts = ghostty.input.KeyEncodeOptions.fromTerminal(&self.terminal);

        var buf: [128]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buf);
        ghostty.input.encodeKey(&writer, event, opts) catch return;
        const encoded = writer.buffered();
        if (encoded.len > 0) {
            _ = write(self.pty_fd, encoded.ptr, encoded.len);
        }
    }

    /// Encode paste data with optional bracketed paste mode.
    pub fn encodeAndWritePaste(self: *GhosttyBridge, data: [*c]const u8, len: usize) void {
        if (len == 0) return;
        const slice = data[0..len];
        const bracketed = self.terminal.modes.get(.bracketed_paste);

        if (bracketed) {
            const prefix = "\x1b[200~";
            const suffix = "\x1b[201~";
            _ = write(self.pty_fd, prefix.ptr, prefix.len);
            _ = write(self.pty_fd, slice.ptr, slice.len);
            _ = write(self.pty_fd, suffix.ptr, suffix.len);
        } else {
            // In non-bracketed mode, replace \n with \r
            for (slice) |ch| {
                const byte: [1]u8 = .{if (ch == '\n') '\r' else ch};
                _ = write(self.pty_fd, &byte, 1);
            }
        }
    }

    /// Encode mouse button event and write to PTY.
    pub fn encodeMouseButton(self: *GhosttyBridge, x: c_int, y: c_int, button: c_int, active: bool, mods: u16) void {
        if (!self.hasMouseTracking()) return;
        const fmt = self.getMouseFormat();
        const cb = mouseButtonCode(button, mods);
        self.writeMouseEvent(cb, x, y, active, fmt);
    }

    /// Encode mouse motion event and write to PTY.
    pub fn encodeMouseMotion(self: *GhosttyBridge, x: c_int, y: c_int, mods: u16) void {
        // Only report motion if button-event or any-event tracking is enabled
        const any = self.terminal.modes.get(.mouse_event_any);
        const btn = self.terminal.modes.get(.mouse_event_button);
        if (!any and !btn) return;

        const fmt = self.getMouseFormat();
        // Motion events use button code 32 + modifier bits
        const cb: u8 = 32 | mouseModBits(mods);
        self.writeMouseEvent(cb, x, y, true, fmt);
    }

    fn hasMouseTracking(self: *const GhosttyBridge) bool {
        return self.terminal.modes.get(.mouse_event_x10) or
            self.terminal.modes.get(.mouse_event_normal) or
            self.terminal.modes.get(.mouse_event_button) or
            self.terminal.modes.get(.mouse_event_any);
    }

    const MouseFormat = enum { x10, sgr };

    fn getMouseFormat(self: *const GhosttyBridge) MouseFormat {
        if (self.terminal.modes.get(.mouse_format_sgr) or
            self.terminal.modes.get(.mouse_format_sgr_pixels))
            return .sgr;
        return .x10;
    }

    fn mouseButtonCode(button: c_int, mods: u16) u8 {
        // Standard mouse protocol button encoding
        const base: u8 = switch (button) {
            1 => 0, // left
            2 => 1, // middle
            3 => 2, // right
            4 => 64, // scroll up
            5 => 65, // scroll down
            else => 0,
        };
        return base | mouseModBits(mods);
    }

    fn mouseModBits(mods: u16) u8 {
        var bits: u8 = 0;
        if (mods & TUIM_SHIFT != 0) bits |= 4;
        if (mods & TUIM_ALT != 0) bits |= 8;
        if (mods & TUIM_CTRL != 0) bits |= 16;
        return bits;
    }

    fn writeMouseEvent(self: *GhosttyBridge, cb: u8, x: c_int, y: c_int, press: bool, fmt: MouseFormat) void {
        var buf: [64]u8 = undefined;
        switch (fmt) {
            .sgr => {
                // SGR format: \x1b[<cb;x+1;y+1M (press) or m (release)
                const end_ch: u8 = if (press) 'M' else 'm';
                const result = std.fmt.bufPrint(&buf, "\x1b[<{d};{d};{d}{c}", .{
                    cb,
                    @as(u32, @intCast(@max(x, 0))) + 1,
                    @as(u32, @intCast(@max(y, 0))) + 1,
                    end_ch,
                }) catch return;
                _ = write(self.pty_fd, result.ptr, result.len);
            },
            .x10 => {
                // X10 format: \x1b[M<cb+32><x+33><y+33>
                if (x < 0 or y < 0 or x > 222 or y > 222) return;
                const seq = [6]u8{
                    0x1b, '[', 'M',
                    cb + 32,
                    @intCast(@as(u32, @intCast(x)) + 33),
                    @intCast(@as(u32, @intCast(y)) + 33),
                };
                _ = write(self.pty_fd, &seq, 6);
            },
        }
    }

    // TUIK → ghostty Key mapping

    // TUIM modifier bitmask values
    const TUIM_SHIFT: u16 = 0x0003;
    const TUIM_CTRL: u16 = 0x00c0;
    const TUIM_ALT: u16 = 0x0300;
    const TUIM_META: u16 = 0x0c00;
    const TUIM_REPEAT: u16 = 0x8000;

    fn tuiModsToGhosttyMods(mods: u16) ghostty.input.KeyMods {
        return .{
            .shift = (mods & TUIM_SHIFT) != 0,
            .ctrl = (mods & TUIM_CTRL) != 0,
            .alt = (mods & TUIM_ALT) != 0,
            .super = (mods & TUIM_META) != 0,
        };
    }

    fn tuikToGhosttyKey(keysym: u32) ?ghostty.input.Key {
        return switch (keysym) {
            // ASCII range — use fromASCII for printable chars
            8 => .backspace,
            9 => .tab,
            13 => .enter,
            27 => .escape,
            32 => .space,
            127 => .delete,

            // Digits 0-9 (ASCII 48-57)
            48 => .digit_0, 49 => .digit_1, 50 => .digit_2,
            51 => .digit_3, 52 => .digit_4, 53 => .digit_5,
            54 => .digit_6, 55 => .digit_7, 56 => .digit_8,
            57 => .digit_9,

            // Letters a-z (ASCII 97-122)
            97 => .key_a, 98 => .key_b, 99 => .key_c,
            100 => .key_d, 101 => .key_e, 102 => .key_f,
            103 => .key_g, 104 => .key_h, 105 => .key_i,
            106 => .key_j, 107 => .key_k, 108 => .key_l,
            109 => .key_m, 110 => .key_n, 111 => .key_o,
            112 => .key_p, 113 => .key_q, 114 => .key_r,
            115 => .key_s, 116 => .key_t, 117 => .key_u,
            118 => .key_v, 119 => .key_w, 120 => .key_x,
            121 => .key_y, 122 => .key_z,

            // Punctuation
            44 => .comma, // TUIK_COMMA
            46 => .period, // TUIK_PERIOD
            61 => .slash, // TUIK_SLASH (SDL1.2 mapping)
            92 => .backslash, // TUIK_BACKSLASH
            20 => .minus, // TUIK_MINUS
            21 => .equal, // TUIK_EQUALS

            // Arrow keys
            273 => .arrow_up,
            274 => .arrow_down,
            275 => .arrow_right,
            276 => .arrow_left,

            // Navigation
            277 => .insert,
            278 => .home,
            279 => .end,
            280 => .page_up,
            281 => .page_down,

            // Function keys F1-F12
            282 => .f1, 283 => .f2, 284 => .f3, 285 => .f4,
            286 => .f5, 287 => .f6, 288 => .f7, 289 => .f8,
            290 => .f9, 291 => .f10, 292 => .f11, 293 => .f12,

            // Keypad
            256 => .numpad_0, 257 => .numpad_1, 258 => .numpad_2,
            259 => .numpad_3, 260 => .numpad_4, 261 => .numpad_5,
            262 => .numpad_6, 263 => .numpad_7, 264 => .numpad_8,
            265 => .numpad_9,
            266 => .numpad_decimal,
            267 => .numpad_divide,
            268 => .numpad_multiply,
            269 => .numpad_subtract,
            270 => .numpad_add,

            // Miscellaneous
            19 => .pause, // TUIK_PAUSE
            300 => .num_lock, // TUIK_NUMLOCKCLEAR
            301 => .caps_lock, // TUIK_CAPSLOCK
            302 => .scroll_lock, // TUIK_SCROLLLOCK
            316 => .print_screen, // TUIK_PRINT

            else => null,
        };
    }
};
