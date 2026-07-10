
var bridges = .{};
var x11_lut = .{
    __may_kv("type", struct { fn anon(ctx: Obj, source: anytype, typename: anytype) void {
        ctx.states.typed = typename;
        if (!ctx.states.mapped) {
            ctx.apply_type();
        }
    } }.anon),
    __may_kv("pair", struct { fn anon(ctx: anytype, source: anytype, wl_id: []const u8, x11_id: []const u8) void {
        var wl_id = (wl_id and wl_id) or "missing";
        var x11_id = (x11_id and x11_id) or "missing";
        ctx.idstr = wl_id ++ ("-> " ++ x11_id);
        ctx.wm.log("wl_x11", ctx.wm.fmt("paired:wl=%s:x11=%s", wl_id, x11_id));
    } }.anon),
    __may_kv("fullscreen", struct { fn anon(ctx: anytype, source: anytype, on: anytype) void {
        ctx.wm.state_change(ctx, "fullscreen");
    } }.anon),
};
var wl_top_lut = .{
    __may_kv("move", struct { fn anon(ctx: anytype) void {
        ctx.states.moving = true;
    } }.anon),
    __may_kv("maximize", struct { fn anon(ctx: anytype) void {
        ctx.wm.state_change(ctx, "maximize");
    } }.anon),
    __may_kv("demaximize", struct { fn anon(ctx: anytype) void {
        ctx.wm.state_change(ctx, "demaximize");
    } }.anon),
    __may_kv("menu", struct { fn anon(ctx: anytype) void {
        ctx.wm.context_menu(ctx);
    } }.anon),
    __may_kv("fullscreen", struct { fn anon(ctx: anytype, source: anytype, on: anytype) void {
        ctx.wm.state_change(ctx, "fullscreen");
    } }.anon),
    __may_kv("resize", struct { fn anon(ctx: anytype, source: anytype, dx: anytype, dy: anytype) void {
        if (!dx or !dy) {
            return;
        }
        dx = tonumber(dx);
        dy = tonumber(dy);
        if (!dx or !dy) {
            ctx.states.resizing = false;
            return;
        }
        var mx = 0;
        var my = 0;
        if (dx < 0) {
            mx = 1;
        }
        if (dy < 0) {
            my = 1;
        }
        ctx.states.resizing = .{
            dx,
            dy,
            mx,
            my,
        };
    } }.anon),
    __may_kv("shell", struct { fn anon(ctx: anytype, shell_type: anytype) void {
    } }.anon),
    __may_kv("scale", struct { fn anon(ctx: anytype, sf: anytype) void {
    } }.anon),
    __may_kv("geom", struct { fn anon(ctx: anytype, x: anytype, y: anytype, w: anytype, h: anytype) void {
        ctx.wm.log("toplevel", ctx.wm.fmt("anchor_geom:x=%f:y=%f:w=%f:h=%f", x, y, w, h));
        ctx.anchor_offset = .{
            x,
            y,
        };
    } }.anon),
};
fn wnd_input_table(wnd: anytype, iotbl: anytype) void {
    if (!wnd.states.focused) {
        return;
    }
    target_input(wnd.vid, iotbl);
}

fn wnd_mouse_over(wnd: anytype) void {
    if (wnd.wm.cfg.mouse_focus and !wnd.states.focused) {
        wnd.wm.focus(wnd);
    }
}

fn wnd_mouse_out(wnd: anytype) void {
    if (wnd.wm.cfg.mouse_focus and wnd.states.focused) {
        wnd.wm.focus();
    }
}

fn wnd_mouse_btn(wnd: Obj, vid: anytype, button: anytype, active: bool, x: anytype, y: anytype) void {
    if (!active) {
        wnd.states.moving = false;
        wnd.states.resizing = false;
    } else if (!wnd.states.focused) {
        wnd.wm.focus(wnd);
    }
    if (wnd.dismiss_chain) {
        if (active) {
            wnd.block_release = button;
            wnd.dismiss_chain();
        }
        return;
    }
    if (!wnd.states.focused) {
        return;
    }
    if ((wnd.block_release == button) and !active) {
        wnd.block_release = null;
        return;
    }
    target_input(wnd.vid, .{
        .kind = "digital",
        .mouse = true,
        .devid = 0,
        .subid = button,
        .active = active,
    });
}

fn wnd_mouse_drop(wnd: Obj) void {
    wnd.drag_resize();
}

fn wnd_mouse_motion(wnd: anytype, vid: anytype, x: i64, y: i64, rx: anytype, ry: anytype) void {
    var tx = x - wnd.x;
    var ty = y - wnd.y;
    target_input(wnd.vid, .{
        .kind = "analog",
        .mouse = true,
        .devid = 0,
        .subid = 0,
        .samples = .{
            tx,
            rx,
        },
    });
    target_input(wnd.vid, .{
        .kind = "analog",
        .mouse = true,
        .devid = 0,
        .subid = 1,
        .samples = .{
            ty,
            ry,
        },
    });
}

fn wnd_mouse_drag(wnd: Obj, vid: anytype, dx: i64, dy: i64) void {
    if (wnd.states.moving) {
        const x, const y = wnd.wm.move(wnd, wnd.x + dx, wnd.y + dy);
        wnd.x = x;
        wnd.y = y;
        if (wnd.send_position) {
            var msg = string.format("kind=move:x=%d:y=%d", wnd.x, wnd.y);
            wnd.wm.log("wl_x11", msg);
            target_input(vid, msg);
        }
        move_image(wnd.vid, wnd.x, wnd.y);
        return;
    } else if (wnd.states.resizing) {
        wnd.drag_resize(dx, dy);
        if (wnd.in_resize[1] < 32) {
            wnd.in_resize[1] = 32;
        }
        if (wnd.in_resize[2] < 32) {
            wnd.in_resize[2] = 32;
        }
        target_displayhint(wnd.vid, wnd.in_resize[1], wnd.in_resize[2]);
    } else {
        const mx, const my = mouse_xy();
        wnd_mouse_motion(wnd, vid, mx, my);
    }
}

fn wnd_hint_state(wnd: anytype) V {
    var mask = 0;
    if (!wnd.states.focused) {
        mask = bit.bor(mask, TD_HINT_UNFOCUSED);
    }
    if (!wnd.states.visible) {
        mask = bit.bor(mask, TD_HINT_INVISIBLE);
    }
    if (wnd.states.maximized) {
        mask = bit.bor(mask, TD_HINT_MAXIMIZED);
    }
    if (wnd.states.fullscreen) {
        mask = bit.bor(mask, TD_HINT_FULLSCREEN);
    }
    return mask;
}

fn wnd_unfocus(wnd: anytype) void {
    wnd.wm.log(wnd.name, wnd.wm.fmt("focus=off:idstr=%s", (wnd.idstr and wnd.idstr) or wnd.name));
    wnd.states.focused = false;
    target_displayhint(wnd.vid, 0, 0, wnd_hint_state(wnd));
    wnd.wm.custom_cursor = false;
    mouse_switch_cursor("default");
}

fn wnd_focus(wnd: anytype) void {
    wnd.wm.log(wnd.name, wnd.wm.fmt("focus=on:idstr=%s", (wnd.idstr and wnd.idstr) or wnd.name));
    wnd.states.focused = true;
    target_displayhint(wnd.vid, 0, 0, wnd_hint_state(wnd));
    wnd.wm.custom_cursor = wnd;
    table.remove_match(wnd.wm.window_stack, wnd);
    table.insert(wnd.wm.window_stack, wnd);
    __may_method(wnd.wm.restack);
}

fn wnd_destroy(wnd: anytype) void {
    wnd.wm.log(wnd.name, "destroy");
    mouse_droplistener(wnd);
    wnd.wm.windows[wnd.cookie] = null;
    table.remove_match(wnd.wm.window_stack, wnd);
    __may_method(wnd.wm.restack);
    if (wnd.wm.custom_cursor == wnd) {
        mouse_switch_cursor("default");
    }
    if (wnd.wm.cfg.destroy) {
        wnd.wm.cfg.destroy(wnd);
    }
    if (valid_vid(wnd.vid)) {
        wnd.wm.known_surfaces[wnd.vid] = null;
        delete_image(wnd.vid);
    }
}

fn wnd_fullscreen(wnd: anytype) void {
    if (wnd.states.fullscreen) {
        return;
    }
    wnd.states.fullscreen = .{
        wnd.w,
        wnd.h,
        wnd.x,
        wnd.y,
    };
    wnd.defer_move = .{
        0,
        0,
    };
    target_displayhint(wnd.vid, wnd.wm.disptbl.width, wnd.wm.disptbl.height, wnd_hint_state(wnd));
}

fn wnd_maximize(wnd: Obj) void {
    if (wnd.states.maximized) {
        return;
    }
    if (wnd.states.fullscreen) {
        wnd.revert(.{ .no_hint = true });
    }
    wnd.states.maximized = .{
        wnd.w,
        wnd.h,
        wnd.x,
        wnd.y,
    };
    wnd.defer_move = .{
        0,
        0,
    };
    target_displayhint(wnd.vid, wnd.wm.disptbl.width, wnd.wm.disptbl.height, wnd_hint_state(wnd));
}

fn wnd_revert(wnd: anytype, opts: bool) void {
    var tbl = undefined;
    if (wnd.states.fullscreen) {
        tbl = wnd.states.fullscreen;
        wnd.states.fullscreen = false;
    } else if (wnd.states.maximized) {
        tbl = wnd.states.maximized;
        wnd.states.maximized = false;
    } else {
        return;
    }
    if (!opts or !opts.no_hint) {
        target_displayhint(wnd.vid, tbl[1], tbl[2], wnd_hint_state(wnd));
        wnd.defer_move = .{
            tbl[3],
            tbl[4],
        };
    }
    wnd_hint_state(wnd);
}

fn tl_wnd_resized(wnd: anytype, source: anytype, status: anytype) void {
    if (!wnd.states.mapped) {
        wnd.states.mapped = true;
        show_image(wnd.vid);
        wnd.wm.mapped(wnd);
    }
    var rzmask = wnd.states.resizing;
    if (rzmask) {
        var dw = (wnd.w - status.width);
        var dh = (wnd.h - status.height);
        var dx = dw * rzmask[3];
        var dy = dh * rzmask[4];
        const x, const y = wnd.wm.move(wnd, wnd.x + dx, wnd.y + dy);
        wnd.x = x;
        wnd.y = y;
        move_image(wnd.vid, wnd.x, wnd.y);
        wnd.defer_move = null;
    }
    wnd.w = status.width;
    wnd.h = status.height;
    resize_image(wnd.vid, status.width, status.height);
    if (wnd.use_decor) {
        wnd.wm.decorate(wnd, wnd.vid, wnd.w, wnd.h);
    }
    if (wnd.defer_move) {
        const x, const y = wnd.wm.move(wnd, wnd.defer_move[1], wnd.defer_move[2]);
        move_image(wnd.vid, x, y);
        wnd.x = x;
        wnd.y = y;
        wnd.defer_move = null;
    }
}

fn self_own(self: anytype, vid: anytype) V {
    return (self.vid == vid) or (self.mouse_proxy and (vid == self.mouse_proxy));
}

fn x11_wnd_realize(wnd: anytype, popup: anytype, grab: anytype) void {
    if (wnd.realized) {
        return;
    }
    if (!wnd.states.mapped or !wnd.states.typed) {
        hide_image(wnd.vid);
        return;
    }
    show_image(wnd.vid);
    target_displayhint(wnd.vid, wnd.w, wnd.h);
    mouse_addlistener(wnd, .{
        "motion",
        "drag",
        "drop",
        "button",
        "over",
        "out",
    });
    table.insert(wnd.wm.window_stack, 1, wnd);
    wnd.wm.state_change(wnd, "realized", popup, grab);
    wnd.realized = true;
}

fn x11_wnd_type(wnd: Obj) void {
    var popup_type = (wnd.states.typed == "menu") or (wnd.states.typed == "popup") or (wnd.states.typed == "tooltip") or (wnd.states.typed == "dropdown");
    if (popup_type) {
        wnd.use_decor = false;
        wnd.wm.decorate(wnd);
        image_inherit_order(wnd.vid, false);
        order_image(wnd.vid, 65531);
    } else {
        image_inherit_order(wnd.vid, true);
        wnd.use_decor = true;
        order_image(wnd.vid, 1);
    }
    wnd.realize();
}

fn x11_nudge(wnd: anytype, dx: i64, dy: i64) void {
    const x, const y = wnd.wm.move(wnd, wnd.x + dx, wnd.y + dy, dx, dy);
    move_image(wnd.vid, x, y);
    wnd.x = x;
    wnd.y = y;
    var msg = string.format("kind=move:x=%d:y=%d", x, y);

    wnd.wm.log("wl_x11", msg);
    target_input(wnd.vid, msg);
}

fn wnd_nudge(wnd: anytype, dx: i64, dy: i64) void {
    const x, const y = wnd.wm.move(wnd, wnd.x + dx, wnd.y + dy, dx, dy);
    move_image(wnd.vid, x, y);
    wnd.x = x;
    wnd.y = y;
    wnd.wm.log("wnd", wnd.wm.fmt("source=%d:x=%d:y=%d", wnd.vid, x, y));
}

fn wnd_drag_rz(wnd: anytype, dx: anytype, dy: i64, mx: anytype, my: anytype) void {
    if (!dx) {
        wnd.states.resizing = false;
        wnd.in_resize = null;
        return;
    }
    if (!wnd.in_resize) {
        wnd.in_resize = .{
            wnd.w,
            wnd.h,
        };
        if (mx and my) {
            wnd.states.resizing = .{
                1,
                1,
                mx,
                my,
            };
        }
    }
    var tw = wnd.in_resize[1] + (dx * wnd.states.resizing[1]);
    var th = wnd.in_resize[2] + (dy * wnd.states.resizing[2]);
    if (tw < wnd.min_w) {
        tw = wnd.min_w;
    }
    if (th < wnd.min_h) {
        th = wnd.min_h;
    }
    if ((wnd.max_w > 0) and (tw > wnd.max_w)) {
        tw = wnd.max_w;
    }
    if ((wnd.max_h > 0) and (tw > wnd.max_h)) {
        tw = wnd.max_h;
    }
    wnd.in_resize = .{
        tw,
        th,
    };
    target_displayhint(wnd.vid, wnd.in_resize[1], wnd.in_resize[2]);
    wnd.wm.log("wnd", wnd.wm.fmt("source=%d:drag_rz=%d:%d", wnd.vid, wnd.in_resize[1], wnd.in_resize[2]));
}

fn x11_vtable() V {
    return .{
        .name = "x11_bridge",
        .own = self_own,
        .x = 0,
        .y = 0,
        .w = 32,
        .h = 32,
        .pad_x = 0,
        .pad_y = 0,
        .min_w = 32,
        .min_h = 32,
        .max_w = 0,
        .max_h = 0,
        .send_position = true,
        .use_decor = true,
        .states = .{
            .mapped = false,
            .typed = false,
            .fullscreen = false,
            .maximized = false,
            .visible = false,
            .moving = false,
            .resizing = false,
        },
        .destroy = wnd_destroy,
        .input_table = wnd_input_table,
        .over = wnd_mouse_over,
        .out = wnd_mouse_out,
        .button = wnd_mouse_btn,
        .drag = x11_mouse_drag,
        .motion = wnd_mouse_motion,
        .drop = wnd_mouse_drop,
        .focus = wnd_focus,
        .unfocus = wnd_unfocus,
        .revert = wnd_revert,
        .fullscreen = wnd_fullscreen,
        .maximize = wnd_maximize,
        .drag_resize = wnd_drag_rz,
        .nudge = x11_nudge,
        .apply_type = x11_wnd_type,
        .realize = x11_wnd_realize,
    };
}

fn wnd_dnd_source(wnd: anytype, x: anytype, y: anytype, types: anytype) void {
}

fn wnd_copy_paste(wnd: anytype, src: anytype, dst: anytype) void {
    var nc = @intCast(src.states.copy_set.len);
    if (!dst.wm or !valid_vid(dst.wm.control) or (nc == 0)) {
        return;
    }
    var control = dst.wm.control;
    target_input(control, "offer");
    var lim = ((nc < 32) and nc) or 32;
    for (1..lim + 1) |i| {
        target_input(control, v);
    }
    target_input(control, "/offer");
    dst.wm.offer_src = src;
}

fn tl_vtable(wm: anytype) V {
    return .{
        .name = "wl_toplevel",
        .wm = wm,
        .states = .{
            .mapped = false,
            .focused = false,
            .fullscreen = false,
            .maximized = false,
            .visible = false,
            .moving = false,
            .resizing = false,
            .copy_set = .{},
        },
        .focus = wnd_focus,
        .unfocus = wnd_unfocus,
        .maximize = wnd_maximize,
        .fullscreen = wnd_fullscreen,
        .revert = wnd_revert,
        .nudge = wnd_nudge,
        .drag_resize = wnd_drag_rz,
        .dnd_source = wnd_dnd_source,
        .copy_paste = wnd_paste_opts,
        .x = 0,
        .y = 0,
        .w = 0,
        .h = 0,
        .min_w = 32,
        .min_h = 32,
        .max_w = 0,
        .max_h = 0,
        .input_table = wnd_input_table,
        .over = wnd_mouse_over,
        .out = wnd_mouse_out,
        .drag = wnd_mouse_drag,
        .drop = wnd_mouse_drop,
        .button = wnd_mouse_btn,
        .motion = wnd_mouse_motion,
        .destroy = wnd_destroy,
        .own = self_own,
    };
}

fn popup_click(popup: anytype, vid: anytype, x: anytype, y: anytype) void {
    var tbl = target_input(vid, .{
        .kind = "digital",
        .mouse = true,
        .devid = 0,
        .subid = 1,
        .active = true,
    });
    target_input(vid, .{
        .kind = "digital",
        .mouse = true,
        .devid = 0,
        .subid = 1,
        .active = false,
    });
}

fn setup_grab_surface(popup: anytype) V {
    var vid = null_surface(popup.wm.disptbl.width, popup.wm.disptbl.height);
    rendertarget_attach(popup.wm.disptbl.rt, vid, RENDERTARGET_DETACH);
    show_image(vid);
    order_image(vid, 65530);
    image_tracetag(vid, "popup_grab");
    var done = false;
    var tbl = .{
        .name = "popup_grab_mh",
        .own = struct { fn anon(ctx: anytype, tgt: anytype) bool {
            return vid == tgt;
        } }.anon,
        .button = struct { fn anon() void {
            if (!done) {
                done = true;
                __may_method(popup.destroy);
            }
        } }.anon,
    };
    mouse_addlistener(tbl, .{ "button" });
    popup.wm.log("popup", popup.wm.fmt("grab_on"));
    return struct { fn anon() void {
        popup.wm.log("popup", popup.wm.fmt("grab_free"));
        mouse_droplistener(tbl);
        delete_image(vid);
        done = true;
    } }.anon;
}

fn popup_destroy(popup: anytype) void {
    if (popup.grab) {
        popup.grab = popup.grab();
    }
    mouse_switch_cursor("default");
    if (valid_vid(popup.vid)) {
        delete_image(popup.vid);
        popup.wm.known_surfaces[popup.vid] = null;
    }
    mouse_droplistener(popup);
    popup.wm.windows[popup.cookie] = null;
}

fn popup_over(popup: anytype) void {
    if (popup.wm.cursor) {
        mouse_custom_cursor(popup.wm.cursor);
    } else {
        mouse_switch_cursor("default");
    }
}

fn popup_vtable() V {
    return .{
        .name = "popup_mh",
        .own = self_own,
        .motion = wnd_mouse_motion,
        .click = popup_click,
        .destroy = popup_destroy,
        .over = popup_over,
        .out = popup_out,
        .states = .{},
        .x = 0,
        .y = 0,
    };
}

fn on_popup(popup: anytype, source: anytype, status: anytype) void {
    if (status.kind == "create") {
        var wnd = popup;
        if (wnd.pending_popup and valid_vid(wnd.pending_popup.vid)) {
            __may_method(wnd.pending_popup.destroy);
        }
        var popup = popup_vtable();
        const vid, const aid, const cookie = accept_target(struct { fn anon(va: anytype) V {
            return on_popup(popup, va);
        } }.anon);
        image_tracetag(vid, "wl_popup");
        rendertarget_attach(wnd.disptbl.rt, vid, RENDERTARGET_DETACH);
        wnd.known_surfaces[vid] = true;
        wnd.pending_popup = popup;
        link_image(vid, wnd.anchor);
        popup.wm = wnd;
        popup.cookie = cookie;
        popup.vid = vid;
        mouse_addlistener(popup, .{
            "motion",
            "click",
            "over",
            "out",
        });
    } else if (status.kind == "terminated") {
        __may_method(popup.destroy);
    } else if (status.kind == "resized") {
        if (!popup.states.mapped) {
            popup.states.mapped = true;
            if (popup.got_parent) {
                show_image(popup.vid);
            }
        }
        resize_image(popup.vid, status.width, status.height);
    } else if (status.kind == "viewport") {
        var pwnd = popup.wm.windows[status.parent];
        if (!pwnd) {
            popup.wm.log("popup", popup.wm.fmt("bad_parent=%d", status.parent));
            popup.got_parent = false;
            hide_image(popup.vid);
            return;
        }
        pwnd.popup = popup;
        popup.parent = pwnd;
        popup.got_parent = true;
        link_image(popup.vid, pwnd.vid);
        move_image(popup.vid, status.rel_x, status.rel_y);
        if (status.focus) {
            order_image(popup.vid, 65531);
            if (!popup.grab) {
                popup.grab = setup_grab_surface(popup);
            }
            image_mask_clear(popup.vid, MASK_UNPICKABLE);
        } else {
            if (popup.grab) {
                popup.grab = popup.grab();
            }
            order_image(popup.vid, 1);
            image_mask_set(popup.vid, MASK_UNPICKABLE);
        }
        var props = image_surface_resolve(popup.vid);
        popup.x = props.x;
        popup.y = props.y;
        if (popup.states.mapped) {
            show_image(popup.vid);
        }
        if (popup.wm.pending_popup == popup) {
            popup.wm.pending_popup = null;
        }
    }
}

fn on_toplevel(wnd: anytype, source: anytype, status: anytype) V {
    if (status.kind == "create") {
        var new = tl_vtable();
        new.wm = wnd;
        const w, const h, const x, const y = wnd.configure(new, "toplevel");
        const vid, const aid, const cookie = accept_target(w, h, struct { fn anon(va: anytype) V {
            return on_toplevel(new, va);
        } }.anon);
        rendertarget_attach(wnd.disptbl.rt, vid, RENDERTARGET_DETACH);
        new.vid = vid;
        new.cookie = cookie;
        wnd.known_surfaces[vid] = true;
        new.x = x;
        new.y = y;
        table.insert(wnd.window_stack, new);
        image_tracetag(vid, "wl_toplevel");
        new.vid = vid;
        image_inherit_order(vid, true);
        link_image(vid, wnd.anchor);
        mouse_addlistener(new, .{
            "over",
            "out",
            "drag",
            "button",
            "motion",
            "drop",
        });
        return __may_mv(new, cookie);
    } else if (status.kind == "terminated") {
        __may_method(wnd.destroy);
    } else if (status.kind == "resized") {
        tl_wnd_resized(wnd, source, status);
    } else if (status.kind == "viewport") {
        var parent = wnd.wm.windows[status.parent];
        if (parent) {
            wnd.wm.log("wl_toplevel", wnd.wm.fmt("reparent=%d", status.parent));
            wnd.wm.state_change(wnd, "toplevel", parent);
        } else {
            wnd.wm.log("wl_toplevel", wnd.wm.fmt("viewport:unknown_parent:%d", status.parent));
        }
    } else if (status.kind == "message") {
        wnd.wm.log("wl_toplevel", wnd.wm.fmt("message=%s", status.message));
        var opts = string.split(status.message, ":");
        if (!opts or !opts[1]) {
            return;
        }
        if ((opts[1] == "shell") and (opts[2] == "xdg_top") and opts[3] and wl_top_lut[opts[3]]) {
            wl_top_lut[opts[3]](wnd, source, unpack(opts, 4));
        }
    }
}

fn on_cursor(ctx: anytype, source: anytype, status: anytype) void {
    if (status.kind == "create") {
        var cursor = accept_target(struct { fn anon(va: anytype) V {
            return on_cursor(ctx, va);
        } }.anon);
        ctx.cursor.vid = cursor;
        link_image(ctx.bridge, cursor);
        ctx.known_surfaces[cursor] = true;
        image_tracetag(cursor, "wl_cursor");
        rendertarget_attach(ctx.disptbl.rt, cursor, RENDERTARGET_DETACH);
    } else if (status.kind == "resized") {
        ctx.cursor.width = status.width;
        ctx.cursor.height = status.height;
        resize_image(ctx.cursor.vid, status.width, status.height);
        if (ctx.custom_cursor) {
            mouse_custom_cursor(ctx.cursor);
        }
    } else if (status.kind == "message") {
        if (ctx.custom_cursor) {
            mouse_custom_cursor(ctx.cursor);
        }
    } else if (status.kind == "terminated") {
        delete_image(source);
        ctx.known_surfaces[source] = null;
    }
}

fn on_subsurface(ctx: anytype, source: anytype, status: anytype) V {
    if (status.kind == "create") {
        var subwnd = .{ .name = "tl_subsurface" };
        const vid, const aid, const cookie = accept_target(struct { fn anon(va: anytype) V {
            return on_subsurface(subwnd, va);
        } }.anon);
        subwnd.vid = vid;
        subwnd.wm = ctx;
        subwnd.cookie = cookie;
        ctx.wm.known_surfaces[vid] = true;
        rendertarget_attach(ctx.wm.disptbl.rt, vid, RENDERTARGET_DETACH);
        image_tracetag(vid, "wl_subsurface");
        return __may_mv(subwnd, cookie);
    } else if (status.kind == "resized") {
    } else if (status.kind == "viewport") {
        link_image(source, parent.vid);
    } else if (status.kind == "terminated") {
        delete_image(source);
        ctx.wm.windows[ctx.cookie] = null;
        ctx.wm.known_surfaces[source] = null;
    }
}

fn x11_viewport(wnd: anytype, source: anytype, status: anytype) void {
    var anchor = wnd.wm.anchor;
    if (status.parent != 0) {
        var pwnd = wnd.wm.windows[status.parent];
        if (pwnd) {
            anchor = pwnd.vid;
        }
    }
    if (wnd.in_resize) {
        return;
    }
    link_image(wnd.vid, anchor);
    move_image(wnd.vid, status.rel_x, status.rel_y);
    var props = image_surface_resolve(wnd.vid);
    const x, const y = wnd.wm.move(wnd, props.x, props.y);
    wnd.x = x;
    wnd.y = y;
    wnd.wm.log("wl_x11", wnd.wm.fmt("viewport:parent=%d:hx=%d:hy=%d:x=%d:y=%d", status.parent, status.rel_x, status.rel_y, x, y));
}

fn on_x11(wnd: anytype, source: anytype, status: anytype) V {
    if (status.kind == "create") {
        var x11 = x11_vtable();
        x11.wm = wnd;
        const w, const h, const x, const y = wnd.configure(x11, "x11");
        const vid, const aid, const cookie = accept_target(w, h, struct { fn anon(va: anytype) V {
            return on_x11(x11, va);
        } }.anon);
        rendertarget_attach(wnd.disptbl.rt, vid, RENDERTARGET_DETACH);
        x11.x = x;
        x11.y = y;
        move_image(vid, x, y);
        wnd.known_surfaces[vid] = true;
        x11.vid = vid;
        x11.cookie = cookie;
        image_tracetag(vid, "x11_unknown_type");
        image_inherit_order(vid, true);
        link_image(vid, wnd.anchor);
        return __may_mv(x11, cookie);
    } else if (status.kind == "resized") {
        tl_wnd_resized(wnd, source, status);
        __may_method(wnd.realize);
        if (wnd.realized and wnd.use_decor) {
            const t, const l, const d, const r = wnd.wm.decorate(wnd, wnd.vid, wnd.w, wnd.h);
            wnd.pad_x = t;
            wnd.pad_y = l;
        }
    } else if (status.kind == "message") {
        var opts = string.split(status.message, ":");
        if (!opts or !opts[1] or !x11_lut[opts[1]]) {
            wnd.wm.log("wl_x11", wnd.wm.fmt("unhandled_message=%s", status.message));
            return;
        }
        wnd.wm.log("wl_x11", wnd.wm.fmt("message=%s", status.message));
        return x11_lut[opts[1]](wnd, source, unpack(opts, 2));
    } else if (status.kind == "registered") {
        wnd.guid = status.guid;
    } else if (status.kind == "viewport") {
        x11_viewport(wnd, source, status);
    } else if (status.kind == "terminated") {
        __may_method(wnd.destroy);
    }
}

fn bridge_handler(ctx: anytype, source: anytype, status: anytype) void {
    if (status.kind == "terminated") {
        __may_method(ctx.destroy);
        return;
    } else if (status.kind == "message") {
        const cmd, const data = string.split_first(status.message, ":");
        ctx.log("bridge", ctx.fmt("message:kind=%s", cmd));
        if (cmd == "offer") {
            if (table.find_i(ctx.offer, data)) {
                return;
            }
            table.insert(ctx.offer, data);
        } else if (cmd == "offer-reset") {
            ctx.offer = .{};
        }
        return;
    } else if (status.kind != "segment_request") {
        return;
    }
    var permitted = .{
        __may_kv("cursor", on_cursor),
        __may_kv("application", on_toplevel),
        __may_kv("popup", on_popup),
        __may_kv("multimedia", on_subsurface),
        __may_kv("bridge-x11", on_x11),
    };
    var handler = permitted[status.segkind];
    if (!handler) {
        warning("unhandled segment type: " ++ status.segkind);
        return;
    }
    const wnd, const cookie = handler(ctx, source, .{ .kind = "create" });
    if (wnd) {
        ctx.windows[cookie] = wnd;
    }
}

fn set_rate(ctx: anytype, period: anytype, delay: anytype) void {
    message_target(ctx.bridge, string.format("seat:rate:%d,%d", period, delay));
}

fn set_bridge(ctx: anytype, source: anytype) void {
    var w = ctx.disptbl.width;
    var h = ctx.disptbl.height;
    target_displayhint(source, w, h, 0, ctx.disptbl);
    if (!ctx.cfg.block_gpu) {
        target_flags(source, TARGET_ALLOWGPU);
    }
    target_updatehandler(source, struct { fn anon(va: anytype) V {
        return bridge_handler(ctx, va);
    } }.anon);
    ctx.bridge = source;
    ctx.anchor = null_surface(w, h);
    image_tracetag(ctx.anchor, "wl_bridge_anchor");
    image_mask_set(ctx.anchor, MASK_UNPICKABLE);
    show_image(ctx.anchor);
    ctx.mh = .{
        .name = "wl_bg",
        .own = self_own,
        .vid = ctx.anchor,
        .click = struct { fn anon() void {
            ctx.focus();
        } }.anon,
    };
    mouse_addlistener(ctx.mh, .{ "click" });
}

fn resize_output(ctx: anytype, neww: anytype, newh: anytype, density: anytype, refresh: anytype) void {
    if (density) {
        ctx.disptbl.vppcm = density;
        ctx.disptbl.hppcm = density;
    }
    if (neww) {
        ctx.disptbl.width = neww;
    } else {
        neww = ctx.disptbl.width;
    }
    if (newh) {
        ctx.disptbl.height = newh;
    } else {
        newh = ctx.disptbl.height;
    }
    if (refresh) {
        ctx.disptbl.refresh = refresh;
    }
    if (!valid_vid(ctx.bridge)) {
        return;
    }
    ctx.log("bridge", ctx.fmt("output_resize=%d:%d", ctx.disptbl.width, ctx.disptbl.height));
    target_displayhint(ctx.bridge, neww, newh, 0, ctx.disptbl);
    for (pairs(ctx.windows)) |__may_pair| {
        const _ = __may_pair[0];
        const v = __may_pair[1];
        if (v.reconfigure) {
            if (v.states.fullscreen or v.states.maximized) {
                __may_method(v.reconfigure, neww, newh);
            } else {
                __may_method(v.reconfigure, v.w, v.h);
            }
        }
    }
}

fn reparent_rt(ctx: anytype, rt: anytype) void {
    ctx.disptbl.rt = rt;
    for (pairs(ctx.known_surfaces)) |__may_pair| {
        const k = __may_pair[0];
        const v = __may_pair[1];
        rendertarget_attach(ctx.disptbl.rt, k, RENDERTARGET_DETACH);
    }
    if (valid_vid(ctx.anchor)) {
        rendertarget_attach(ctx.disptbl.rt, ctx.anchor, RENDERTARGET_DETACH);
    }
}

var window_stack = .{};
fn restack(ctx: anytype) void {
    var cnt = 0;
    for (pairs(ctx.windows)) |__may_pair| {
        const _ = __may_pair[0];
        const v = __may_pair[1];
        cnt = cnt + 1;
    }
    for (ctx.window_stack, 0..) |v, i| {
        order_image(v.vid, i * 10);
    }
}

fn bridge_table(cfg: anytype) V {
    var res = .{
        .control = BADID,
        .window_stack = window_stack,
        .windows = .{},
        .known_surfaces = .{},
        .cursor = .{
            .vid = BADID,
            .hotspot_x = 0,
            .hotspot_y = 0,
            .width = 1,
            .height = 1,
        },
        .offer = .{},
        .cfg = cfg,
        .disptbl = .{
            .rt = WORLDID,
            .width = VRESW,
            .height = VRESH,
            .ppcm = VPPCM,
        },
        .resize = resize_output,
        .repeat_rate = set_rate,
        .restack = restack,
        .set_rt = reparent_rt,
        .log = print,
        .fmt = string.format,
    };
    if (cfg.width) {
        res.disptbl.width = cfg.width;
    }
    if (cfg.height) {
        res.disptbl.height = cfg.height;
    }
    if (cfg.fmt) {
        res.fmt = cfg.fmt;
    }
    if (cfg.log) {
        res.log = cfg.log;
    }
    if (type(cfg.window_stack) == "table") {
        res.window_stack = cfg.window_stack;
    }
    if (type(cfg.move) == "function") {
        res.log("wlwm", "override_handler=move");
        res.move = cfg.move;
    } else {
        res.log("wlwm", "default_handler=move");
        res.move = struct { fn anon(wnd: anytype, x: anytype, y: anytype, dx: anytype, dy: anytype) V {
            return __may_mv(x, y);
        } }.anon;
    }
    if (type(cfg.context_menu) == "function") {
        res.log("wlwm", "override_handler=context_menu");
        res.context_menu = cfg.context_menu;
    } else {
        res.context_menu = struct { fn anon() void {
        } }.anon;
    }
    res.configure = struct { fn anon(va: anytype) V {
        var w = undefined;
        var h = undefined;
        var x = undefined;
        var y = undefined;
        if (cfg.configure) {
            w, h, x, y = cfg.configure(va);
        }
        w = (w and w) or (res.disptbl.width * 0.5);
        h = (h and h) or (res.disptbl.height * 0.3);
        if (!x or !y) {
            x, y = mouse_xy();
        }
        return __may_mv(w, h, x, y);
    } }.anon;
    if (type(cfg.focus) == "function") {
        res.log("wlwm", "override_handler=focus");
        res.focus = cfg.focus;
    } else {
        res.log("wlwm", "default_handler=focus");
        res.focus = struct { fn anon() bool {
            return true;
        } }.anon;
    }
    if (type(cfg.decorate) == "function") {
        res.log("wlwm", "override_handler=decorate");
        res.decorate = cfg.decorate;
    } else {
        res.log("wlwm", "default_handler=decorate");
        res.decorate = struct { fn anon() void {
        } }.anon;
    }
    if (type(cfg.mapped) == "function") {
        res.log("wlwm", "override_handler=mapped");
        res.mapped = cfg.mapped;
    } else {
        res.log("wlwm", "default_handler=mapped");
        res.mapped = struct { fn anon() void {
        } }.anon;
    }
    if (type(cfg.state_change) == "function") {
        res.log("wlwm", "override_handler=state_change");
        res.state_change = cfg.state_change;
    } else {
        res.state_change = struct { fn anon(wnd: Obj, state: bool) void {
            if (!state) {
                wnd.revert();
            }
        } }.anon;
    }
    if ((cfg.resize_request) == "function") {
        res.log("wlwm", "override_handler=resize_request");
        res.resize_request = cfg.resize_request;
    } else {
        res.log("wlwm", "default_handler=resize_request");
        res.resize_request = struct { fn anon(wnd: anytype, new_w: anytype, new_h: anytype) V {
            if (new_w > ctx.disptbl.width) {
                new_w = ctx.disptbl.width;
            }
            if (new_h > ctx.disptbl.height) {
                new_h = ctx.disptbl.height;
            }
            return __may_mv(new_w, new_h);
        } }.anon;
    }
    res.destroy = struct { fn anon() void {
        var rmlist = .{};
        for (pairs(res.windows)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            table.insert(rmlist, v);
        }
        for (rmlist, 0..) |v, i| {
            if (v.destroy) {
                __may_method(v.destroy);
                if (cfg.destroy) {
                    cfg.destroy(v);
                }
            }
        }
        if (cfg.destroy) {
            cfg.destroy(res);
        }
        if (valid_vid(res.bridge)) {
            delete_image(res.bridge);
        }
        if (valid_vid(res.anchor)) {
            delete_image(res.anchor);
        }
        mouse_droplistener(res);
        var keys = .{};
        for (pairs(res)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            table.insert(keys, v);
        }
        for (keys, 0..) |k, _| {
            res[k] = null;
        }
    } }.anon;
    return res;
}

fn client_handler(nested: anytype, trigger: anytype, source: anytype, status: anytype) V {
    if (!bridges[source]) {
        bridges[source] = .{};
    }
    if (status.kind == "registered") {
        if (status.segkind != "bridge-wayland") {
            delete_image(source);
            return;
        }
    } else if (status.kind == "segment_request") {
        if (status.segkind == "bridge-wayland") {
            if (nested) {
                return false;
            }
            var vid = accept_target(32, 32, struct { fn anon(va: anytype) V {
                return client_handler(true, trigger, va);
            } }.anon);
        } else {
            var bridge = trigger(source, status);
            if (bridge) {
                table.insert(bridges[source], bridge);
                rendertarget_attach(bridge.disptbl.rt, vid, RENDERTARGET_DETACH);
            }
        }
    } else if (status.kind == "terminated") {
        for (bridges[source], 0..) |v, k| {
            __may_method(v.destroy);
        }
        delete_image(source);
        bridges[source] = null;
    }
}

fn connection_mgmt(source: anytype, trigger: anytype) void {
    target_updatehandler(source, struct { fn anon(source: anytype, status: anytype) void {
        client_handler(false, trigger, source, status);
    } }.anon);
}

pub fn __init() void {
    return __may_mv(struct { fn anon(vid: anytype, segreq: anytype, cfg: anytype) V {
        var ctx = bridge_table(cfg);
        set_bridge(ctx, vid);
        bridge_handler(ctx, vid, segreq);
        return ctx;
    } }.anon, connection_mgmt);
}
