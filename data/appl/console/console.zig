
var workspaces = .{};
var ws_index = 1;
var hotkey_modifier = "lalt";
var syskey_modifier = "lalt_lctrl";
var clipboard_last = "";
var connection_point = "console";
var ws_limit = 100;
var wayland_connection = undefined;
var wayland_client = undefined;
var wayland_config = undefined;
pub fn console(args: anytype) void {
    KEYBOARD = @import("builtin/keyboard.zig").__init();
    @import("builtin/mouse.zig").__init();
    @import("builtin/debug.zig").__init();
    @import("builtin/string.zig").__init();
    @import("builtin/table.zig").__init();
    wayland_client, wayland_connection = @import("builtin/wayland.zig").__init();
    @import("console_osdkbd.zig").__init();
    wayland_config = @import("wayland_client.zig").__init();
    mouse_setup(load_image("cursor.png"), .{
        .layer = 65535,
        .pickdepth = 1,
    });
    mouse_state().autohide = true;
    workspaces.anchor = null_surface(VRESW, VRESH);
    show_image(workspaces.anchor);
    mouse_addlistener(.{
        .own = struct { fn anon(ctx: anytype, vid: anytype) bool {
            return vid == workspaces.anchor;
        } }.anon,
        .tap = struct { fn anon(ctx: anytype) bool {
            if (console_osdkbd_active()) {
                console_osdkbd_destroy(10);
            }
            return true;
        } }.anon,
        .name = "wm_anchor",
    }, .{ "tap" });
    __may_method(KEYBOARD.kbd_repeat);
    __may_method(KEYBOARD.load_keymap);
    switch_workspace(ws_index);
    connection_point = get_key("connection_point") or connection_point;
    target_alloc(connection_point, client_event_handler);
}

pub fn console_input(input: anytype) void {
    if (input.translated) {
        __may_method(KEYBOARD.patch, input);
        console_osdkbd_destroy(10);
        if (valid_hotkey(input)) {
            return;
        }
    } else if (input.mouse) {
        if (input.digital and (input.subid == MOUSE_MBUTTON)) {
            if (input.active) {
                clipboard_paste(clipboard_last);
            }
        } else {
            mouse_iotbl_input(input);
            return;
        }
    }
    var target: Obj = workspaces[ws_index];
    if (!target) {
        return;
    }
    if (input.touch and console_osdkbd_input(workspaces, target, input)) {
        return;
    }
    if (!input.kind) {
        print(debug.traceback());
    }
    target.input(input);
}

pub fn console_adopt(vid: anytype, kind: anytype, title: anytype, have_parent: anytype, last: anytype) V {
    const ok, const opts = whitelisted(kind, vid);
    if (!ok or have_parent or !find_free_space()) {
        return false;
    }
    var ret = new_client(vid, opts);
    if (last) {
        switch_workspace(1);
    }
    return ret;
}

fn add_client_mouse(ctx: anytype, vid: anytype) void {
    ctx.own = struct { fn anon(ctx: anytype, tgt: anytype) bool {
        return vid == tgt;
    } }.anon;
    ctx.name = "ws_mh";
    ctx.button = struct { fn anon(ctx: anytype, vid: anytype, ind: anytype, pressed: anytype, x: anytype, y: anytype) void {
        target_input(vid, .{
            .devid = 0,
            .subid = ind,
            .mouse = true,
            .kind = "digital",
            .active = pressed,
        });
    } }.anon;
    ctx.motion = struct { fn anon(ctx: anytype, vid: anytype, x: anytype, y: anytype, rx: anytype, ry: anytype) void {
        target_input(vid, .{
            .devid = 0,
            .subid = 0,
            .kind = "analog",
            .mouse = true,
            .samples = .{
                x,
                rx,
            },
        });
        target_input(vid, .{
            .devid = 0,
            .subid = 1,
            .kind = "analog",
            .mouse = true,
            .samples = .{
                y,
                ry,
            },
        });
    } }.anon;
    ctx.tap = struct { fn anon(ctx: anytype) bool {
        if (console_osdkbd_active()) {
            console_osdkbd_destroy(10);
        }
        return true;
    } }.anon;
    ctx.mouse = true;
    mouse_addlistener(ctx, .{
        "motion",
        "button",
        "tap",
    });
}

pub fn new_client(vid: anytype, opts: anytype) V {
    if (!valid_vid(vid)) {
        return;
    }
    var new_ws = find_free_space();
    if (!new_ws) {
        delete_image(vid);
        return;
    }
    var ctx = .{
        .index = new_ws,
        .vid = vid,
        .scale = opts.scaling,
        .clipboard_temp = "",
    };
    if (!opts.input) {
        ctx.input = struct { fn anon(ctx: anytype, tbl: anytype) void {
            target_input(vid, tbl);
        } }.anon;
    } else {
        ctx.input = opts.input;
    }
    order_image(vid, 2);
    link_image(vid, workspaces.anchor);
    if (!opts.block_mouse) {
        add_client_mouse(ctx, vid);
    }
    workspaces[new_ws] = ctx;
    switch_workspace(new_ws);
    return __may_mv(true, ctx);
}

pub fn spawn_terminal() V {
    var term_arg = (get_key("terminal") or "palette=solarized") ++ (":env=ARCAN_CONNPATH=" ++ connection_point);
    var inarg = appl_arguments();
    for (inarg, 0..) |v, _| {
        if (v == "lash") {
            term_arg = "cli=lua:" ++ term_arg;
        }
    }
    return launch_avfeed(term_arg, "terminal", struct { fn anon(source: anytype, status: anytype) V {
        return client_event_handler(source, status);
    } }.anon);
}

fn scale_client(ws: anytype, w: f64, h: f64) V {
    if (ws.scale) {
        var ar = w / h;
        var wr = w / VRESW;
        var hr = h / VRESH;
        return __may_mv((((hr > wr) and math.floor(VRESH * ar)) or VRESW), (((hr < wr) and math.floor(VRESW / ar)) or VRESH));
    } else {
        return __may_mv(w, h);
    }
}

pub fn client_event_handler(source: anytype, status: anytype) void {
    if (status.kind == "terminated") {
        delete_image(source);
        const _, const index = find_client(source);
        if (index) {
            delete_workspace(index);
        }
    } else if (status.kind == "resized") {
        const ws, const index = find_client(source);
        if (ws) {
            const w, const h = scale_client(ws, status.width, status.height);
            resize_image(source, w, h);
            center_image(source, workspaces.anchor);
            image_set_txcos_default(source, status.origo_ll);
            ws.aid = status.source_audio;
        } else {
            delete_image(source);
        }
    } else if (status.kind == "connected") {
        if (find_free_space() == null) {
            delete_image(source);
        }
        target_alloc(connection_point, client_event_handler);
    } else if (status.kind == "registered") {
        const ok, const opts = whitelisted(status.segkind, source);
        if (!ok) {
            delete_image(source);
            return;
        }
        if (status.segkind == "bridge-wayland") {
            wayland_connection(source, struct { fn anon(source: anytype, status: anytype) void {
                const _, const wl_cl = new_client(source, .{ .block_mouse = true });
                var cfg = wayland_config(wl_cl);
                var cl = wayland_client(source, status, cfg);
                wl_cl.bridge = cl;
            } }.anon);
            return;
        }
        var client_ws = find_client(source);
        if (!client_ws) {
            _, client_ws = new_client(source, opts);
            if (!client_ws) {
                delete_image(source);
                return;
            }
            client_ws.segkind = status.segkind;
            client_ws.input_labels = .{};
        }
    } else if (status.kind == "input_label") {
        var client_ws = find_client(source);
        if (@intCast(status.labelhint.len) == 0) {
            client_ws.input_labels.input_labels = .{};
        } else {
            table.insert(client_ws.input_labels, status);
        }
    } else if (status.kind == "preroll") {
        target_displayhint(source, VRESW, VRESH, TD_HINT_IGNORE, .{ .ppcm = VPPCM });
        var font = get_key("terminal_font");
        var font_sz = get_key("font_size");
        if (font and ((status.segkind == "tui") or (status.segkind == "terminal"))) {
            target_fonthint(source, font, (tonumber(font_sz) or 12) * FONT_PT_SZ, 2);
        } else {
            target_fonthint(source, (tonumber(font_sz) or 12) * FONT_PT_SZ, 2);
        }
    } else if (status.kind == "segment_request") {
        if (status.segkind == "clipboard") {
            var vid = accept_target(clipboard_handler);
            if (!valid_vid(vid)) {
                return;
            }
            link_image(vid, source);
        } else if (status.segkind == "handover") {
            var vid = accept_target(client_event_handler);
        }
    }
}

var last_index = 1;
pub fn switch_workspace(index: anytype) V {
    if (!index) {
        if (workspaces[last_index]) {
            return switch_workspace(last_index);
        } else {
            for (1..10 + 1) |i| {
                if (workspaces[i]) {
                    return switch_workspace(i);
                }
            }
        }
        index = 1;
    }
    if (workspaces[ws_index]) {
        hide_image(workspaces[ws_index].vid);
        move_image(workspaces[ws_index].vid, 0, 0);
    }
    if (ws_index != index) {
        last_index = ws_index;
        ws_index = index;
    }
    if (!workspaces[ws_index]) {
        spawn_terminal();
    }
    var new_space = workspaces[ws_index];
    if (new_space and valid_vid(new_space.vid)) {
        show_image(new_space.vid);
        console_osdkbd_invalidate(workspaces, new_space);
    }
}

pub fn find_free_space() V {
    if (!workspaces[ws_index]) {
        return ws_index;
    }
    for (1..10 + 1) |i| {
        if (!workspaces[i]) {
            return i;
        }
    }
}

pub fn find_client(vid: anytype) V {
    for (1..10 + 1) |i| {
        if (workspaces[i] and (workspaces[i].vid == vid)) {
            return __may_mv(workspaces[i], i);
        }
    }
}

pub fn valid_hotkey(input: anytype) V {
    var mods = decode_modifiers(input.modifiers, "_");
    if (!input.active or ((mods != hotkey_modifier) and (mods != syskey_modifier))) {
        return false;
    }
    if (mods == syskey_modifier) {
        if (input.keysym == KEYBOARD.tokeysym("SYSREQ")) {
            system_collapse();
        } else if (input.keysym == KEYBOARD.tokeysym("BACKSPACE")) {
            return shutdown();
        }
        return true;
    }
    if (input.keysym == KEYBOARD.tokeysym("v")) {
        clipboard_paste(clipboard_last);
    } else if (input.keysym == KEYBOARD.tokeysym("DELETE")) {
        if (workspaces[ws_index] and workspaces[ws_index].vid) {
            delete_workspace(ws_index);
        }
    } else if (input.keysym == KEYBOARD.tokeysym("m")) {
        if (workspaces[ws_index] and workspaces[ws_index].aid) {
            var current = audio_gain(workspaces[ws_index].aid, null);
            audio_gain(workspaces[ws_index].aid, 1.0 - current);
        }
    } else if (input.keysym == KEYBOARD.tokeysym("l")) {
        next_workspace();
    } else if (input.keysym == KEYBOARD.tokeysym("h")) {
        previous_workspace();
    } else if ((input.keysym >= KEYBOARD.tokeysym("F1")) and (input.keysym <= KEYBOARD.tokeysym("F10"))) {
        switch_workspace(input.keysym - KEYBOARD.tokeysym("F1") + 1);
    }
    return true;
}

var clipboard_temp = "";
pub fn clipboard_handler(source: anytype, status: anytype) void {
    if (status.kind == "terminated") {
        delete_image(source);
    } else if (status.kind == "message") {
        tbl, _ = find_client(image_parent(source));
        tbl.clipboard_temp = tbl.clipboard_temp ++ status.message;
        if (!status.multipart) {
            clipboard_last = tbl.clipboard_temp;
            tbl.clipboard_temp = "";
        }
    }
}

pub fn clipboard_paste(msg: anytype) V {
    msg = (msg and msg) or clipboard_last;
    var dst_ws = workspaces[ws_index];
    if (!dst_ws or !valid_vid(dst_ws.vid, TYPE_FRAMESERVER) or (@intCast(clipboard_last.len) == 0)) {
        return false;
    }
    if (!valid_vid(dst_ws.clipboard)) {
        dst_ws.clipboard = define_nulltarget(dst_ws.vid, "clipboard", struct { fn anon(source: anytype, status: anytype) void {
            if (status.kind == "terminated") {
                delete_image(source);
            }
        } }.anon);
        if (!valid_vid(dst_ws.clipboard)) {
            return;
        }
        link_image(dst_ws.clipboard, dst_ws.vid);
    }
    target_input(dst_ws.clipboard, msg);
}

pub fn previous_workspace() void {
    for (ws_index + 1..1 + 1) |i| {
        __may_step(-1);
        if (workspaces[i] != null) {
            switch_workspace(i);
            return;
        }
    }
    for (ws_limit..ws_index + 1) |i| {
        __may_step(-1);
        if (workspaces[i] != null) {
            switch_workspace(i);
            return;
        }
    }
}

pub fn next_workspace() void {
    for (ws_index + 1..ws_limit + 1) |i| {
        if (workspaces[i] != null) {
            switch_workspace(i);
            return;
        }
    }
    for (1..ws_index + 1) |i| {
        if (workspaces[i] != null) {
            switch_workspace(i);
            return;
        }
    }
}

pub fn resize_workspace(i: anytype, w: anytype, h: anytype) void {
    if (!workspaces[i]) {
        return;
    }
    target_displayhint(workspaces[i].vid, w, h, TD_HINT_IGNORE);
}

pub fn delete_workspace(i: anytype) void {
    if (workspaces[i] and valid_vid(workspaces[i].vid)) {
        delete_image(workspaces[i].vid);
    }
    if (workspaces[i].destroy) {
        __may_method(workspaces[i].destroy);
    }
    if (workspaces[i].mouse) {
        mouse_droplistener(workspaces[i]);
    }
    workspaces[i] = null;
    if (i == ws_index) {
        switch_workspace();
    }
}

pub fn whitelisted(kind: anytype, vid: anytype) V {
    var set = .{
        __may_kv("vm", .{
            client_event_handler,
            .{},
        }),
        __may_kv("lightweight arcan", .{
            client_event_handler,
            .{},
        }),
        __may_kv("multimedia", .{
            client_event_handler,
            .{ .scale = true },
        }),
        __may_kv("tui", .{
            client_event_handler,
            .{},
        }),
        __may_kv("game", .{
            client_event_handler,
            .{ .scale = true },
        }),
        __may_kv("application", .{
            client_event_handler,
            .{},
        }),
        __may_kv("browser", .{
            client_event_handler,
            .{},
        }),
        __may_kv("terminal", .{
            client_event_handler,
            .{},
        }),
        __may_kv("bridge-x11", .{
            client_event_handler,
            .{},
        }),
        __may_kv("bridge-wayland", .{
            client_event_handler,
            .{},
        }),
    };
    if (set[kind]) {
        if (vid) {
            target_updatehandler(vid, set[kind][1]);
        }
        return __may_mv(true, set[kind][2]);
    }
}

pub fn console_clock_pulse() void {
    mouse_tick(1);
    __may_method(KEYBOARD.tick);
}

pub fn console_display_state(status: anytype) void {
    resize_video_canvas(VRESW, VRESH);
    resize_image(workspaces.anchor, VRESW, VRESH);
    mouse_querytarget(WORLDID);
    for (pairs(workspaces)) |__may_pair| {
        const i = __may_pair[0];
        const v = __may_pair[1];
        if (type(v) == "table") {
            if (v.bridge) {
                __may_method(v.bridge.resize, VRESW, VRESH);
            } else if (valid_vid(v.vid, TYPE_FRAMESERVER)) {
                target_displayhint(v.vid, VRESW, VRESH, TD_HINT_IGNORE, WORLDID);
            }
        }
    }
    var target = workspaces[ws_index];
    if (!target) {
        console_osdkbd_destroy(0);
        return;
    }
    console_osdkbd_invalidate(workspaces, target);
}
