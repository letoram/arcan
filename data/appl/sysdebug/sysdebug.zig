
var render = undefined;
var nav = undefined;
var catalogue = .{
    .{
        .kind = "front",
        .slug = "preface",
        .path = "parts/00_foundations/preface.lua",
        .title = "Preface",
    },
    .{
        .kind = "front",
        .slug = "glossary",
        .path = "parts/00_foundations/glossary.lua",
        .title = "Glossary",
    },
    .{
        .kind = "front",
        .slug = "howto",
        .path = "parts/00_foundations/howto.lua",
        .title = "How to read this appl",
    },
    .{
        .kind = "chapter",
        .slug = "00_foundations/ch0_architecture",
        .path = "parts/00_foundations/ch0_architecture.lua",
        .title = "Part I · Ch 0 · Architecture",
    },
    .{
        .kind = "chapter",
        .slug = "00_foundations/ch1_introduction",
        .path = "parts/00_foundations/ch1_introduction.lua",
        .title = "Part I · Ch 1 · Introduction",
    },
    .{
        .kind = "chapter",
        .slug = "00_foundations/ch2_software_demystified",
        .path = "parts/00_foundations/ch2_software_demystified.lua",
        .title = "Part I · Ch 2 · Software Demystified",
    },
    .{
        .kind = "chapter",
        .slug = "00_foundations/ch3_principal_debugging",
        .path = "parts/00_foundations/ch3_principal_debugging.lua",
        .title = "Part I · Ch 3 · Principal Debugging",
    },
    .{
        .kind = "chapter",
        .slug = "00_foundations/ch4_tools_of_the_trade",
        .path = "parts/00_foundations/ch4_tools_of_the_trade.lua",
        .title = "Part I · Ch 4 · Tools of the Trade",
    },
    .{
        .kind = "chapter",
        .slug = "02_zig_fork/ch1_introduction",
        .path = "parts/02_zig_fork/ch1_introduction.lua",
        .title = "Part II · Ch 1 · Introduction (sh-zig)",
    },
    .{
        .kind = "chapter",
        .slug = "02_zig_fork/ch2_software_demystified",
        .path = "parts/02_zig_fork/ch2_software_demystified.lua",
        .title = "Part II · Ch 2 · Software Demystified (sh-zig)",
    },
    .{
        .kind = "chapter",
        .slug = "02_zig_fork/ch3_principal_debugging",
        .path = "parts/02_zig_fork/ch3_principal_debugging.lua",
        .title = "Part II · Ch 3 · Principal Debugging (sh-zig)",
    },
    .{
        .kind = "chapter",
        .slug = "02_zig_fork/ch4_tools_of_the_trade",
        .path = "parts/02_zig_fork/ch4_tools_of_the_trade.lua",
        .title = "Part II · Ch 4 · Tools of the Trade (sh-zig)",
    },
    .{
        .kind = "chapter",
        .slug = "03_zig_arcan/ch1_introduction",
        .path = "parts/03_zig_arcan/ch1_introduction.lua",
        .title = "Part III · Ch 1 · Introduction (zig-arcan)",
    },
    .{
        .kind = "chapter",
        .slug = "03_zig_arcan/ch2_software_demystified",
        .path = "parts/03_zig_arcan/ch2_software_demystified.lua",
        .title = "Part III · Ch 2 · Software Demystified (zig-arcan)",
    },
    .{
        .kind = "chapter",
        .slug = "03_zig_arcan/ch3_principal_debugging",
        .path = "parts/03_zig_arcan/ch3_principal_debugging.lua",
        .title = "Part III · Ch 3 · Principal Debugging (zig-arcan)",
    },
    .{
        .kind = "chapter",
        .slug = "03_zig_arcan/ch4_tools_of_the_trade",
        .path = "parts/03_zig_arcan/ch4_tools_of_the_trade.lua",
        .title = "Part III · Ch 4 · Tools of the Trade (zig-arcan)",
    },
    .{
        .kind = "chapter",
        .slug = "04_sel4_zig/ch1_introduction",
        .path = "parts/04_sel4_zig/ch1_introduction.lua",
        .title = "Part IV · Ch 1 · Introduction (seL4-zig)",
    },
    .{
        .kind = "chapter",
        .slug = "04_sel4_zig/ch2_software_demystified",
        .path = "parts/04_sel4_zig/ch2_software_demystified.lua",
        .title = "Part IV · Ch 2 · Software Demystified (seL4-zig)",
    },
    .{
        .kind = "chapter",
        .slug = "04_sel4_zig/ch3_principal_debugging",
        .path = "parts/04_sel4_zig/ch3_principal_debugging.lua",
        .title = "Part IV · Ch 3 · Principal Debugging (seL4-zig)",
    },
    .{
        .kind = "chapter",
        .slug = "04_sel4_zig/ch4_tools_of_the_trade",
        .path = "parts/04_sel4_zig/ch4_tools_of_the_trade.lua",
        .title = "Part IV · Ch 4 · Tools of the Trade (seL4-zig)",
    },
    .{
        .kind = "chapter",
        .slug = "05_a12_tailscale/ch1_introduction",
        .path = "parts/05_a12_tailscale/ch1_introduction.lua",
        .title = "Part V · Ch 1 · Introduction (a12)",
    },
    .{
        .kind = "chapter",
        .slug = "05_a12_tailscale/ch2_software_demystified",
        .path = "parts/05_a12_tailscale/ch2_software_demystified.lua",
        .title = "Part V · Ch 2 · Software Demystified (a12)",
    },
    .{
        .kind = "chapter",
        .slug = "05_a12_tailscale/ch3_principal_debugging",
        .path = "parts/05_a12_tailscale/ch3_principal_debugging.lua",
        .title = "Part V · Ch 3 · Principal Debugging (a12)",
    },
    .{
        .kind = "chapter",
        .slug = "05_a12_tailscale/ch4_tools_of_the_trade",
        .path = "parts/05_a12_tailscale/ch4_tools_of_the_trade.lua",
        .title = "Part V · Ch 4 · Tools of the Trade (a12)",
    },
    .{
        .kind = "article",
        .slug = "visibility_rule",
        .path = "articles/visibility_rule.lua",
        .title = "Article · The visibility rule, why",
        .date = "2026-05-01",
    },
    .{
        .kind = "back",
        .slug = "refs",
        .path = "parts/00_foundations/refs.lua",
        .title = "References",
    },
    .{
        .kind = "back",
        .slug = "tickets",
        .path = "parts/00_foundations/tickets.lua",
        .title = "Tickets",
    },
    .{
        .kind = "back",
        .slug = "verbs",
        .path = "parts/00_foundations/verbs.lua",
        .title = "Verbs",
    },
    .{
        .kind = "back",
        .slug = "xref",
        .path = "parts/00_foundations/xref.lua",
        .title = "Cross-reference",
    },
};
var state = .{
    .cur = 1,
    .vid = null,
    .scroll = 0,
    .h = 0,
    .verbboxes = .{},
};
fn clamp(x: i64, lo: i64, hi: i64) i64 {
    if (x < lo) {
        return lo;
    }
    if (x > hi) {
        return hi;
    }
    return x;
}

fn destroy_current() void {
    if (state.vid and valid_vid(state.vid)) {
        delete_image(state.vid);
    }
    state.vid = null;
    state.scroll = 0;
    state.h = 0;
}

fn show_index() void {
    destroy_current();
    state.cur = 0;
    var txt = render.render_index(catalogue);
    state.vid = render_text(txt);
    if (!valid_vid(state.vid)) {
        return;
    }
    show_image(state.vid);
    move_image(state.vid, 24, 24);
    var props = image_surface_properties(state.vid);
    state.h = props.height;
}

fn show_at(idx: anytype) void {
    idx = clamp(idx, 1, @intCast(catalogue.len));
    destroy_current();
    state.cur = idx;
    var entry = catalogue[idx];
    var mod = system_load(entry.path);
    if (!mod) {
        state.vid = render_text("\\f,14\\bsysdebug: failed to load\\!b\\n\\r" ++ entry.path);
        if (valid_vid(state.vid)) {
            show_image(state.vid);
            move_image(state.vid, 24, 24);
        }
        return;
    }
    var view = mod();
    var txt = render.render_view(view, entry, idx, @intCast(catalogue.len));
    state.vid = render_text(txt);
    if (!valid_vid(state.vid)) {
        return;
    }
    show_image(state.vid);
    move_image(state.vid, 24, 24);
    var props = image_surface_properties(state.vid);
    state.h = props.height;
    state.verbboxes = .{};
    for (view.body or .{}, 0..) |b, _| {
        if ((b.kind == "verbbox") and (type(b.chain) == "string")) {
            table.insert(state.verbboxes, b.chain);
        }
    }
    if (view.bus_publish) {
        var bp = view.bus_publish;
        var pl = bp.payload or .{};
        var pstr = "";
        for (pairs(pl)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            pstr = pstr ++ (" " ++ (tostring(k) ++ ("=" ++ tostring(v))));
        }
        if (warning) {
            warning(string.format("[sysdebug.bus] sensor=%s key=%s%s", tostring(bp.sensor or "unknown"), tostring(entry.slug or idx), pstr));
        }
    }
}

fn scroll_by(dy: i64) void {
    if (!state.vid or !valid_vid(state.vid)) {
        return;
    }
    var viewport = VRESH - 48;
    var max_scroll = math.max(0, state.h - viewport);
    state.scroll = clamp(state.scroll + dy, 0, max_scroll);
    move_image(state.vid, 24, 24 - state.scroll);
}

pub fn sysdebug(args: anytype) void {
    KEYBOARD = @import("builtin/keyboard.zig").__init();
    render = @import("views/render.zig").__init()();
    nav = .{
        .show_index = show_index,
        .show_at = show_at,
        .scroll_by = scroll_by,
        .catalogue = catalogue,
    };
    var bg = fill_surface(VRESW, VRESH, 12, 12, 16);
    show_image(bg);
    order_image(bg, 0);
    show_index();
}

pub fn sysdebug_input(iotbl: anytype) V {
    if (!iotbl.translated or !iotbl.active) {
        return;
    }
    var key = null;
    if (KEYBOARD) {
        if ((type(KEYBOARD) == "table") and KEYBOARD[iotbl.keysym]) {
            key = KEYBOARD[iotbl.keysym];
        } else if (type(KEYBOARD.tolabel) == "function") {
            const ok, const lbl = pcall(KEYBOARD.tolabel, KEYBOARD, iotbl);
            if (ok) {
                key = lbl;
            }
        } else if (type(KEYBOARD.patch) == "function") {
            pcall(KEYBOARD.patch, KEYBOARD, iotbl);
            key = iotbl.label;
        }
    }
    key = key or iotbl.label or iotbl.utf8 or tostring(iotbl.keysym or "");
    if ((key == "ESCAPE") or (key == "Escape")) {
        return shutdown();
    }
    if (state.cur == 0) {
        var n = tonumber(key);
        if (n and (n >= 1) and (n <= @intCast(catalogue.len))) {
            show_at(n);
            return;
        }
        if ((key == "RETURN") or (key == "Return")) {
            show_at(1);
            return;
        }
        return;
    }
    {
        var n = tonumber(key);
        if (n and (n >= 1) and (n <= 9) and state.verbboxes[n]) {
            var chain = state.verbboxes[n];
            if (type(set_clipboard) == "function") {
                pcall(set_clipboard, chain);
            }
            var msg = string.format("[sysdebug.spawn-cell] entry=%d verbbox=%d chain=%s", state.cur, n, chain);
            if ((type(target_message) == "function") and WORLDID) {
                pcall(target_message, WORLDID, msg);
            }
            if (type(warning) == "function") {
                warning(msg);
            }
            return;
        }
    }
    if ((key == "h") or (key == "H") or (key == "HOME") or (key == "Home")) {
        show_index();
        return;
    } else if ((key == "RIGHT") or (key == "Right") or (key == "n") or (key == "N")) {
        show_at(state.cur + 1);
        return;
    } else if ((key == "LEFT") or (key == "Left") or (key == "p") or (key == "P")) {
        show_at(state.cur - 1);
        return;
    } else if ((key == "DOWN") or (key == "Down") or (key == "j")) {
        scroll_by(40);
        return;
    } else if ((key == "UP") or (key == "Up") or (key == "k")) {
        scroll_by(-40);
        return;
    } else if ((key == "PAGEDOWN") or (key == "PageDown") or (key == " ") or (key == "SPACE")) {
        scroll_by(VRESH - 80);
        return;
    } else if ((key == "PAGEUP") or (key == "PageUp")) {
        scroll_by(-(VRESH - 80));
        return;
    }
}

pub fn sysdebug_display_state(state_str: anytype, va: anytype) void {
    if (state and state.cur and (state.cur > 0)) {
        show_at(state.cur);
    } else if (state and (state.cur == 0)) {
        show_index();
    }
}
