// Pure Zig port of tui/core/input.c — zero C helpers.
// TUI input event handling: keyboard, mouse, labels.

const std = @import("std");
const arcan = @import("arcan");

fn cstrlen(s: [*c]const u8) usize {
    if (s == null) return 0;
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

fn cstreql(a: [*c]const u8, b: [*c]const u8) bool {
    if (a == null or b == null) return a == b;
    var i: usize = 0;
    while (a[i] != 0 and b[i] != 0) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return a[i] == b[i];
}

fn snprintfLabel(dst: []u8, src: [*c]const u8) void {
    const len = cstrlen(src);
    const copy_len = if (len >= dst.len) dst.len - 1 else len;
    for (0..copy_len) |i| {
        dst[i] = src[i];
    }
    dst[copy_len] = 0;
}

export fn tui_expose_labels(tui: ?*arcan.tui_context) void {
    const t = tui orelse return;
    const handlers = t.getHandlers();

    // Send empty LABELHINT first (resets label list)
    var ev = arcan.arcan_event.zeroes();
    ev.setCategory(arcan.EVENT_EXTERNAL);
    ev.asExt().kind = arcan.EVENT_EXTERNAL_LABELHINT;
    ev.asExt().payload.labelhint.idatatype = @intCast(arcan.EVENT_IDATATYPE_DIGITAL);
    _ = arcan.arcan_shmif_enqueue(t.getAcon(), &ev);

    // Send COPY_WINDOW label
    snprintfLabel(&ev.asExt().payload.labelhint.label, "COPY_WINDOW");
    ev.asExt().payload.labelhint.idatatype = @intCast(arcan.EVENT_IDATATYPE_DIGITAL);
    ev.asExt().payload.labelhint.modifiers = arcan.TUIM_LSHIFT;
    ev.asExt().payload.labelhint.initial = arcan.TUIK_PRINT;
    _ = arcan.arcan_shmif_enqueue(t.getAcon(), &ev);

    // Query additional labels from handler
    if (handlers.query_label) |query_fn| {
        var ind: usize = 0;
        while (true) {
            var dstlbl = std.mem.zeroes(arcan.tui_labelent);
            if (!query_fn(tui, ind, "ENG", "ENG", &dstlbl, handlers.tag))
                break;
            ind += 1;

            snprintfLabel(&ev.asExt().payload.labelhint.label, &dstlbl.label);
            snprintfLabel(&ev.asExt().payload.labelhint.descr, &dstlbl.descr);
            ev.asExt().payload.labelhint.subv = dstlbl.subv;
            ev.asExt().payload.labelhint.idatatype = if (dstlbl.idatatype != 0)
                dstlbl.idatatype
            else
                @intCast(arcan.EVENT_IDATATYPE_DIGITAL);
            ev.asExt().payload.labelhint.modifiers = dstlbl.modifiers;
            ev.asExt().payload.labelhint.initial = dstlbl.initial;
            snprintfLabel(&ev.asExt().payload.labelhint.vsym, &dstlbl.vsym);
            _ = arcan.arcan_shmif_enqueue(t.getAcon(), &ev);
        }
    }
}

fn update_mods(mods: c_int, sym: c_int, pressed: bool) c_int {
    if (pressed) {
        return switch (sym) {
            @as(c_int, arcan.TUIK_LSHIFT) => mods | arcan.ARKMOD_LSHIFT,
            @as(c_int, arcan.TUIK_RSHIFT) => mods | arcan.ARKMOD_RSHIFT,
            @as(c_int, arcan.TUIK_LCTRL) => mods | arcan.ARKMOD_LCTRL,
            @as(c_int, arcan.TUIK_RCTRL) => mods | arcan.ARKMOD_RCTRL,
            @as(c_int, arcan.TUIK_COMPOSE), @as(c_int, arcan.TUIK_LMETA) => mods | arcan.ARKMOD_LMETA,
            @as(c_int, arcan.TUIK_RMETA) => mods | arcan.ARKMOD_RMETA,
            else => mods,
        };
    } else {
        return switch (sym) {
            @as(c_int, arcan.TUIK_LSHIFT) => mods & ~arcan.ARKMOD_LSHIFT,
            @as(c_int, arcan.TUIK_RSHIFT) => mods & ~arcan.ARKMOD_RSHIFT,
            @as(c_int, arcan.TUIK_LCTRL) => mods & ~arcan.ARKMOD_LCTRL,
            @as(c_int, arcan.TUIK_RCTRL) => mods & ~arcan.ARKMOD_RCTRL,
            @as(c_int, arcan.TUIK_COMPOSE), @as(c_int, arcan.TUIK_LMETA) => mods & ~arcan.ARKMOD_LMETA,
            @as(c_int, arcan.TUIK_RMETA) => mods & ~arcan.ARKMOD_RMETA,
            else => mods,
        };
    }
}

fn consume_label(
    tui: ?*arcan.tui_context,
    t: *arcan.tui_context,
    ioev: *const arcan.arcan_ioevent,
    label: [*c]const u8,
) bool {
    _ = ioev;
    if (cstreql(label, "COPY_WINDOW")) {
        var ev = arcan.arcan_event.zeroes();
        ev.setCategory(arcan.EVENT_EXTERNAL);
        const ext = ev.asExt();
        ext.kind = arcan.EVENT_EXTERNAL_SEGREQ;
        ext.payload.segreq.kind = arcan.SEGID_TUI;
        ext.payload.segreq.id = 0x2c0c0;
        ext.payload.segreq.width = @intCast(t.getAconW());
        ext.payload.segreq.height = @intCast(t.getAconH());
        _ = arcan.arcan_shmif_enqueue(t.getAcon(), &ev);
        return true;
    }

    const handlers = t.getHandlers();
    if (handlers.input_label) |input_label_fn| {
        const res = input_label_fn(tui, label, true, handlers.tag);
        if (res) {
            _ = input_label_fn(tui, label, false, handlers.tag);
        }
        return res;
    }

    return false;
}

export fn tui_input_event(
    tui: ?*arcan.tui_context,
    ioev_opaque: ?*anyopaque,
    label: [*c]const u8,
) void {
    const t = tui orelse return;
    const ioev: *const arcan.arcan_ioevent = @ptrCast(@alignCast(ioev_opaque orelse return));

    // Check hooks.input first
    if (t.getHooksInput()) |hooks_input| {
        hooks_input(t, ioev, label);
        return;
    }

    if (ioev.datatype == arcan.EVENT_IDATATYPE_TRANSLATED) {
        const pressed = ioev.input.translated.active != 0;
        const sym: c_int = @intCast(ioev.input.translated.keysym);
        const mods_ptr = t.getModifiers();
        mods_ptr.* = update_mods(mods_ptr.*, sym, pressed);

        if (!pressed)
            return;

        t.getInactTimer().* = -4;
        if (label[0] != 0 and consume_label(tui, t, ioev, label))
            return;

        // Function keys 300-314 are consumed silently
        if (sym >= 300 and sym <= 314)
            return;

        // UTF-8 decode validation
        var len: usize = 0;
        var valid = true;
        var codepoint: u32 = 0;
        var state: u32 = 0;
        while (len < 5 and ioev.input.translated.utf8[len] != 0) {
            if (arcan.UTF8_REJECT == arcan.utf8_decode(&state, &codepoint, ioev.input.translated.utf8[len])) {
                valid = false;
                break;
            }
            len += 1;
        }

        // Private use area check
        if (codepoint >= 0xe000 and codepoint <= 0xf8ff)
            valid = false;

        const handlers = t.getHandlers();
        // Take the utf8 dispatch path only when no significant modifier is
        // held. Otherwise we'd lose modifier info — e.g. shift+tab would
        // be written to the PTY as raw 0x09 (just tab), so claude's
        // shift+tab binding never fires. Modifier-bearing keys must reach
        // input_key so the encoder can produce the proper kitty/CSI-u
        // sequence (e.g. shift+tab → `\x1b[9;2u`, ctrl+enter → `\x1b[13;5u`).
        //
        // Read the modifier mask from the EVENT itself, not from the
        // tracked tui state. The tracked state (mods_ptr) drifts when a
        // modifier release event is delivered to a different window
        // (focus switch under a held modifier), leaving stale bits set
        // forever — observed: ctrl bits sticky after one focus change,
        // breaking every subsequent shift+tab / shift+letter dispatch.
        // `ioev.input.translated.modifiers` is the per-event mask from
        // the platform layer (xcb/evdev), authoritative.
        const ev_mods: u16 = @intCast(ioev.input.translated.modifiers);
        const ctrl_held = (ev_mods & (arcan.ARKMOD_LCTRL | arcan.ARKMOD_RCTRL)) != 0;
        const alt_held = (ev_mods & (arcan.ARKMOD_LALT | arcan.ARKMOD_RALT)) != 0;
        const shift_held = (ev_mods & (arcan.ARKMOD_LSHIFT | arcan.ARKMOD_RSHIFT)) != 0;
        // Shift alone matters only for control characters (codepoint < 0x20)
        // and DEL (0x7f). Plain printable characters with shift (e.g. shift+a
        // → 'A') already have the shift baked into the utf8 byte and should
        // still take the utf8 path.
        const first_byte = ioev.input.translated.utf8[0];
        const shift_significant = shift_held and (first_byte < 0x20 or first_byte == 0x7f);
        const skip_utf8 = ctrl_held or alt_held or shift_significant;
        if (valid and first_byte != 0 and handlers.input_utf8 != null and !skip_utf8) {
            if (handlers.input_utf8) |input_utf8_fn| {
                if (input_utf8_fn(tui, &ioev.input.translated.utf8, len, handlers.tag))
                    return;
            }
        }

        if (handlers.input_key) |input_key_fn| {
            input_key_fn(
                tui,
                ioev.input.translated.keysym,
                ioev.input.translated.scancode,
                ioev.input.translated.modifiers,
                ioev.subid,
                handlers.tag,
            );
        }
    } else if (ioev.devkind == arcan.EVENT_IDEVKIND_MOUSE) {
        if (ioev.datatype == arcan.EVENT_IDATATYPE_ANALOG) {
            var x: c_int = 0;
            var y: c_int = 0;
            if (!arcan.arcan_shmif_mousestate_ioev(t.getAcon(), t.getMouseState(), ioev, &x, &y))
                return;

            const cell_w = t.getCellW();
            const cell_h = t.getCellH();
            t.getMouseX().* = if (cell_w > 0) @divTrunc(x, cell_w) else 0;
            t.getMouseY().* = if (cell_h > 0) @divTrunc(y, cell_h) else 0;

            const rows = t.getRows();
            const cols = t.getCols();
            if (t.getMouseY().* >= rows)
                t.getMouseY().* = rows - 1;
            if (t.getMouseX().* >= cols)
                t.getMouseX().* = cols - 1;

            const handlers = t.getHandlers();
            if (handlers.input_mouse_motion) |motion_fn| {
                motion_fn(tui, false, t.getMouseX().*, t.getMouseY().*, t.getModifiers().*, handlers.tag);
            }
            return;
        } else if (ioev.datatype == arcan.EVENT_IDATATYPE_DIGITAL) {
            if (ioev.subid != 0) {
                const bit = @as(u32, 1) << @intCast(ioev.subid - 1);
                if (ioev.input.digital.active != 0)
                    t.getMouseBtnmask().* |= bit
                else
                    t.getMouseBtnmask().* &= ~bit;
            }

            const handlers = t.getHandlers();
            if (handlers.input_mouse_button) |button_fn| {
                button_fn(
                    tui,
                    t.getMouseX().*,
                    t.getMouseY().*,
                    @intCast(ioev.subid),
                    ioev.input.digital.active != 0,
                    t.getModifiers().*,
                    handlers.tag,
                );
                return;
            }

            if ((ioev.flags & arcan.ARCAN_IOFL_GESTURE) != 0) {
                // gesture handling: dblclick, click — currently no-op
                return;
            }

            if (ioev.subid == arcan.TUIBTN_WHEEL_UP) {
                if (ioev.input.digital.active != 0) {
                    if (handlers.input_key) |key_fn| {
                        const mods = t.getModifiers().*;
                        const sym: u32 = if ((mods & (arcan.ARKMOD_LSHIFT | arcan.ARKMOD_RSHIFT)) != 0)
                            arcan.TUIK_PAGEUP
                        else
                            arcan.TUIK_UP;
                        key_fn(tui, sym, ioev.input.translated.scancode, 0, ioev.subid, handlers.tag);
                    }
                }
            } else if (ioev.subid == arcan.TUIBTN_WHEEL_DOWN) {
                if (ioev.input.digital.active != 0) {
                    if (handlers.input_key) |key_fn| {
                        const mods = t.getModifiers().*;
                        const sym: u32 = if ((mods & (arcan.ARKMOD_LSHIFT | arcan.ARKMOD_RSHIFT)) != 0)
                            arcan.TUIK_PAGEDOWN
                        else
                            arcan.TUIK_DOWN;
                        key_fn(tui, sym, ioev.input.translated.scancode, 0, ioev.subid, handlers.tag);
                    }
                }
            }
        } else {
            const handlers = t.getHandlers();
            if (handlers.input_misc) |misc_fn| {
                misc_fn(tui, ioev, handlers.tag);
            }
        }
    }
}
