// Pure Zig port of tui/core/clipboard.c — zero C helpers.
// Clipboard check (poll clip_in) and push (write to clip_out).

const arcan = @import("arcan");

export fn tui_clipboard_check(tui: ?*arcan.tui_context) void {
    const t = tui orelse return;
    var ev = arcan.arcan_event.zeroes();

    const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
    const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
    const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });

    while (arcan.arcan_shmif_poll(t.getClipIn(), &ev) > 0) {
        if (sc_open("/tmp/clip_xbridge.log", "a")) |f| {
            _ = sc_fprintf(f, "term: clipboard_check got ev cat=%d\n", @as(c_int, ev.getCategory()));
            _ = sc_fclose(f);
        }
        if (ev.getCategory() != arcan.EVENT_TARGET)
            continue;

        const tev = ev.asTgt();
        if (sc_open("/tmp/clip_xbridge.log", "a")) |f| {
            _ = sc_fprintf(f, "term: clipboard_check kind=%d\n", @as(c_int, tev.kind));
            _ = sc_fclose(f);
        }
        switch (tev.kind) {
            arcan.TARGET_COMMAND_MESSAGE => {
                const handlers = t.getHandlers();
                if (handlers.utf8) |utf8_fn| {
                    const msg: [*c]const u8 = &tev.message.message;
                    const len = cstrlen(msg);
                    utf8_fn(tui, msg, len, tev.ioevs[0].iv != 0, handlers.tag);
                }
            },
            arcan.TARGET_COMMAND_EXIT => {
                arcan.arcan_shmif_drop(t.getClipIn());
                return;
            },
            else => {},
        }
    }
}

export fn tui_clipboard_push(
    tui: ?*arcan.tui_context,
    sel: [*c]const u8,
    len: usize,
) bool {
    const t = tui orelse return false;

    if (!t.clipOutHasVidp() or sel == null or len == 0)
        return false;

    var msgev = arcan.arcan_event.zeroes();
    msgev.setCategory(arcan.EVENT_EXTERNAL);
    msgev.asExt().kind = arcan.EVENT_EXTERNAL_MESSAGE;

    return arcan.arcan_shmif_pushutf8(t.getClipOut(), &msgev, sel, len);
}

fn cstrlen(s: [*c]const u8) usize {
    if (s == null) return 0;
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

/// Push a clipboard-out payload on the MAIN shmif segment as a MESSAGE
/// event stream with prefix "CLIP_OUT:". Used as a fallback for
/// arcan_tui_copy when the clip_out subsegment never established (our
/// tree loses the NEWSEGMENT reply somewhere between engine and tui
/// dispatcher). Paired with durian atypes/terminal.lua's message handler
/// which detects the prefix and forwards the assembled text to
/// CLIPBOARD:set_global. Total on-wire payload: len(sel) + 9 bytes for
/// the prefix; arcan_shmif_pushutf8 handles UTF-8 boundary chunking.
export fn tui_clipboard_push_main(
    tui: ?*arcan.tui_context,
    sel: [*c]const u8,
    len: usize,
) bool {
    const t = tui orelse return false;
    if (sel == null or len == 0) return false;

    const sc_malloc = @extern(*const fn (usize) callconv(.c) ?*anyopaque, .{ .name = "malloc" });
    const sc_free = @extern(*const fn (?*anyopaque) callconv(.c) void, .{ .name = "free" });

    const total = len + 9; // "CLIP_OUT:" prefix
    const buf_raw = sc_malloc(total + 1) orelse return false;
    defer sc_free(buf_raw);
    const buf: [*]u8 = @ptrCast(buf_raw);
    @memcpy(buf[0..9], "CLIP_OUT:");
    @memcpy(buf[9 .. 9 + len], sel[0..len]);
    buf[total] = 0;

    var msgev = arcan.arcan_event.zeroes();
    msgev.setCategory(arcan.EVENT_EXTERNAL);
    msgev.asExt().kind = arcan.EVENT_EXTERNAL_MESSAGE;

    // Reach the embedded main shmif_cont at offset 2808 (matches
    // shmif/tui/core/dispatch.zig OFF_ACON). tui_context is opaque from
    // here so go through byte-pointer arithmetic.
    const tui_base: [*]u8 = @ptrCast(t);
    const acon: *arcan.arcan_shmif_cont = @ptrCast(@alignCast(tui_base + 2808));
    return arcan.arcan_shmif_pushutf8(acon, &msgev, @ptrCast(buf), total);
}
