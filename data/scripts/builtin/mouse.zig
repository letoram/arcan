
var mouse_handlers = .{
    .click = .{},
    .over = .{},
    .out = .{},
    .drag = .{},
    .press = .{},
    .button = .{},
    .release = .{},
    .drop = .{},
    .hover = .{},
    .motion = .{},
    .dblclick = .{},
    .rclick = .{},
    .tap = .{},
};

pub fn __init() void {
    MOUSE_LABELLUT = .{
        "left",
        "right",
        "middle",
        "wheel y+",
        "wheel y-",
        "wheel x+",
        "wheel -",
    };
    MOUSE_LBUTTON = 1;
    MOUSE_RBUTTON = 2;
    MOUSE_MBUTTON = 3;
    MOUSE_WHEELPY = 4;
    MOUSE_WHEELNY = 5;
    MOUSE_WHEELPX = 6;
    MOUSE_WHEELNX = 7;
    MOUSE_AUXBTN = 8;
    var mstate = .{
        .handlers = mouse_handlers,
        .blocked = false,
        .btns = .{},
        .btns_clock = .{},
        .btns_bounce = .{},
        .btns_remap = .{},
        .cur_over = .{},
        .hover_track = .{},
        .active_list = .{},
        .fastmap = .{},
        .autohide = false,
        .hide_base = 40,
        .hide_count = 40,
        .hidden = true,
        .accel_x = 1,
        .accel_y = 1,
        .dblclickstep = 12,
        .drag_delta = 4,
        .hover_ticks = 30,
        .hover_thresh = 12,
        .click_timeout = 14,
        .animation_speed = 20,
        .long_press = "rclick",
        .click_cnt = 0,
        .counter = 0,
        .hover_count = 0,
        .x_ofs = 0,
        .y_ofs = 0,
        .last_hover = 0,
        .dev = 0,
        .x = 0,
        .y = 0,
        .rel_x = 0,
        .rel_y = 0,
        .min_x = 0,
        .min_y = 0,
        .inertia_x = 0,
        .inertia_y = 0,
        .inertia_acc_x = 0,
        .inertia_acc_y = 0,
        .max_x = VRESW,
        .max_y = VRESH,
        .hotspot_x = 0,
        .hotspot_y = 0,
        .scale_w = 1,
        .scale_h = 1,
        .scale_i = true,
    };

    var cursors = .{};

    var linear_find_vid = undefined;
    for (1..255 + 1) |i| {
        mstate.btns_remap[i] = i;
        mstate.btns[i] = false;
        mstate.btns_clock[i] = CLOCK;
        mstate.btns_bounce[i] = 0;
    }
    mstate.btns_remap[256] = MOUSE_WHEELPY;
    mstate.btns_remap[257] = MOUSE_WHEELNY;
    mstate.btns_remap[258] = MOUSE_WHEELPX;
    mstate.btns_remap[259] = MOUSE_WHEELNX;
    const mouse_inertia = struct { pub fn mouse_inertia(x: anytype, y: anytype) void {
        mstate.inertia_x = x;
        mstate.inertia_y = y;
        mstate.inertia_acc_x = 0;
        mstate.inertia_acc_y = 0;
    } }.mouse_inertia;

    const mouse_cursor_draw = struct { fn mouse_cursor_draw(nofwd: bool) void {
        const x, const y = mouse_hotxy();
        move_image(mstate.cursor, x + mstate.x_ofs, y + mstate.y_ofs);
        if (!nofwd and mstate.cursor_hook) {
            for (mstate.cursor_hook, 0..) |v, k| {
                v(mstate.cursor, x + mstate.x_ofs, y + mstate.y_ofs, mstate.active_label);
            }
        }
    } }.mouse_cursor_draw;

    const mouse_cursorhook = struct { pub fn mouse_cursorhook(newhook: anytype) void {
        if (!mstate.cursor_hook) {
            mstate.cursor_hook = .{};
        }
        if (table.remove_match(mstate.cursor_hook, newhook)) {
            if (@intCast(mstate.cursor_hook.len) == 0) {
                mstate.cursor_hook = null;
            }
            return;
        }
        table.insert(mstate.cursor_hook, newhook);
    } }.mouse_cursorhook;

    const lock_constrain = struct { fn lock_constrain() V {
        if (!valid_vid(mstate.lockvid)) {
            return;
        }
        var props = image_surface_resolve_properties(mstate.lockvid);
        var ul_x = props.x;
        var ul_y = props.y;
        var lr_x = props.x + props.width;
        var lr_y = props.y + props.height;

        if (mstate.warp) {
            var cpx = math.floor(props.x + 0.5 * props.width);
            var cpy = math.floor(props.y + 0.5 * props.height);
            input_samplebase(mstate.dev, cpx, cpy);
            mstate.x = cpx;
            mstate.y = cpy;
        } else {
            mstate.x = ((mstate.x < ul_x) and ul_x) or mstate.x;
            mstate.y = ((mstate.y < ul_y) and ul_y) or mstate.y;
            mstate.x = ((mstate.x > lr_x) and lr_x) or mstate.x;
            mstate.y = ((mstate.y > lr_y) and lr_y) or mstate.y;
        }
        var nx = mstate.x;
        var ny = mstate.y;
        mstate.rel_x = (((mstate.rel_x + mstate.x) < ul_x) and (mstate.x - ul_x)) or mstate.rel_x;
        mstate.rel_x = (((mstate.rel_x + mstate.x) > lr_x) and (lr_x - mstate.x)) or mstate.rel_x;
        mstate.rel_y = (((mstate.rel_y + mstate.y) < ul_y) and (mstate.y - ul_y)) or mstate.rel_y;
        mstate.rel_y = (((mstate.rel_y + mstate.y) > lr_y) and (lr_y - mstate.y)) or mstate.rel_y;
        return __may_mv(ul_x, ul_y, lr_x, lr_y);
    } }.lock_constrain;

    const mouse_cursorupd = struct { fn mouse_cursorupd(x: anytype, y: anytype) V {
        x = x * mstate.accel_x;
        y = y * mstate.accel_y;
        lmx = mstate.x;
        lmy = mstate.y;
        mstate.x = mstate.x + x;
        mstate.y = mstate.y + y;
        mstate.x = ((mstate.x < 0) and 0) or mstate.x;
        mstate.y = ((mstate.y < 0) and 0) or mstate.y;
        mstate.x = ((mstate.x > mstate.max_x) and (mstate.max_x - 1)) or mstate.x;
        mstate.y = ((mstate.y > mstate.max_y) and (mstate.max_y - 1)) or mstate.y;
        mstate.hide_count = mstate.hide_base;
        var relx = mstate.x - lmx;
        var rely = mstate.y - lmy;

        lock_constrain();
        mouse_cursor_draw();
        return __may_mv(relx, rely);
    } }.mouse_cursorupd;

    mstate.lmb_global_press = struct { fn anon() void {
        mstate.y_ofs = 2;
        mstate.x_ofs = 2;
        mouse_cursorupd(0, 0);
        mstate.lmb_pressed = true;
    } }.anon;
    mstate.lmb_global_release = struct { fn anon() void {
        mstate.x_ofs = 0;
        mstate.y_ofs = 0;
        mouse_cursorupd(0, 0);
        mstate.lmb_pressed = false;
        var pr = mstate.pending_release;
        if (pr) {
            mstate.pending_release = null;
            var res: Obj = linear_find_vid(mstate.handlers.release, pr, "release");
            if (res) {
                res.release(pr, mstate.x, mstate.y);
            }
        }
    } }.anon;
    mouse_pickfun = pick_items;
    const def_reveal = struct { fn def_reveal() void {
        for (1..20 + 1) |i| {
            var surf = color_surface(16, 16, 0, 255, 0);
            show_image(surf);
            var seed = math.random(80) - 40;
            order_image(surf, 65534);
            var intime = math.random(50);
            move_image(surf, mstate.x, mstate.y);
            nudge_image(surf, math.random(150) - 75, math.random(150) - 75, intime);
            expire_image(surf, intime);
            blend_image(surf, 0.0, intime);
        }
    } }.def_reveal;

    const linear_find = struct { fn linear_find(table: anytype, label: anytype) V {
        for (pairs(table)) |__may_pair| {
            const a = __may_pair[0];
            const b = __may_pair[1];
            if (b == label) {
                return a;
            }
        }
        return null;
    } }.linear_find;

    const insert_unique = struct { fn insert_unique(tbl: anytype, key: anytype) void {
        for (tbl, 0..) |val, key| {
            if (val == key) {
                tbl[key] = val;
                return;
            }
        }
        table.insert(tbl, key);
    } }.insert_unique;

    const linear_ifind = struct { fn linear_ifind(table: anytype, val: anytype) bool {
        for (1..(@intCast(table.len)) + 1) |i| {
            if (table[i] == val) {
                return true;
            }
        }
        return false;
    } }.linear_ifind;

    linear_find_vid = struct { fn anon(table: anytype, vid: anytype, state: anytype) V {
        if (!valid_vid(vid)) {
            return;
        }
        var fast = mstate.fastmap[vid];
        if (fast) {
            return (fast[state] and fast) or null;
        }
        for (table, 0..) |b, a| {
            if (type(b.own) == "function") {
                if (__may_method(b.own, vid, state)) {
                    return b;
                }
            } else if (b.own == vid) {
                return b;
            }
        }
    } }.anon;
    const select_regupd = struct { fn select_regupd() V {
        const x, const y = mouse_xy();
        var x2 = mstate.in_select.x;
        var y2 = mstate.in_select.y;

        if (x > x2) {
            var tx = x;
            x = x2;
            x2 = tx;
        }
        if (y > y2) {
            var ty = y;
            y = y2;
            y2 = ty;
        }
        return __may_mv(x, y, x2, y2);
    } }.select_regupd;

    const cached_pick = struct { fn cached_pick(xpos: anytype, ypos: anytype, depth: anytype, reverse: anytype) V {
        if ((mouse_lastpick == null) or (CLOCK > mouse_lastpick.tick) or (xpos != mouse_lastpick.x) or (ypos != mouse_lastpick.y)) {
            var res = pick_items(xpos, ypos, depth, reverse, mstate.rt);

            mouse_lastpick = .{
                .tick = CLOCK,
                .x = xpos,
                .y = ypos,
                .count = nitems,
                .val = res,
            };
            return res;
        } else {
            return mouse_lastpick.val;
        }
    } }.cached_pick;

    const mouse_cursor = struct { pub fn mouse_cursor() V {
        return mstate.cursor;
    } }.mouse_cursor;

    const mouse_state = struct { pub fn mouse_state() V {
        return mstate;
    } }.mouse_state;

    const mouse_destroy = struct { pub fn mouse_destroy() void {
        mouse_handlers = .{
            .click = .{},
            .drag = .{},
            .drop = .{},
            .over = .{},
            .out = .{},
            .motion = .{},
            .dblclick = .{},
            .rclick = .{},
            .tap = .{},
        };
        mstate.handlers = mouse_handlers;
        mstate.btns = .{
            false,
            false,
            false,
            false,
            false,
        };
        mstate.cur_over = .{};
        mstate.hover_track = .{};
        mstate.autohide = false;
        mstate.hide_base = 40;
        mstate.hide_count = 40;
        mstate.hidden = true;
        mstate.accel_x = 1;
        mstate.accel_y = 1;
        mstate.dblclickstep = 6;
        mstate.drag_delta = 4;
        mstate.hover_ticks = 30;
        mstate.hover_thresh = 12;
        mstate.counter = 0;
        mstate.hover_count = 0;
        mstate.x_ofs = 0;
        mstate.y_ofs = 0;
        mstate.last_hover = 0;
        toggle_mouse_grab(MOUSE_GRABOFF);
        for (pairs(cursors)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            delete_image(v.vid);
        }
        cursors = .{};
        if (valid_vid(mstate.cursor)) {
            delete_image(mstate.cursor);
            mstate.cursor = BADID;
        }
    } }.mouse_destroy;

    const mouse_load_theme = struct { pub fn mouse_load_theme(path: anytype, name: []const u8) void {
        var load_cursor = undefined;
        load_cursor = struct { fn anon(set: anytype, name: anytype, fname: anytype, hot_x: anytype, hot_y: anytype) V {
            var @"fn" = string.format("%s/%s/%s", path, set, fname);
            var vid = load_image(@"fn");

            if (!valid_vid(vid)) {
                warning("cursor set broken, couldn't load " ++ @"fn");
                vid = fill_surface(8, 8, 0, 255, 0);
                hot_x = 0;
                hot_y = 0;
            }
            mouse_add_cursor(name, vid, hot_x, hot_y);
            return vid;
        } }.anon;
        var @"fn" = string.format("%s/%s/%s.lua", path, name, name);
        var set = system_load(@"fn", false);

        if (type(set) == "function") {
            const ok, const ret = pcall(set);
            if (ok and (type(ret) == "table")) {
                for (pairs(ret)) |__may_pair| {
                    const k = __may_pair[0];
                    const v = __may_pair[1];
                    load_cursor(name, k, v[1], v[2], v[3]);
                }
            } else {
                warning("bad cursor-set definition: " ++ @"fn");
            }
        } else {
            warning("couldn't load cursor-set: " ++ name);
        }
    } }.mouse_load_theme;

    const mouse_setup = struct { pub fn mouse_setup(cvid: anytype, va: anytype) void {
        var a = .{ va };
        var opts = .{
            .pickdepth = 1,
            .layer = 65535,
            .cachepick = true,
            .hidden = false,
        };
        if (type(a[1]) == "table") {
            for (pairs(a[1])) |__may_pair| {
                const k = __may_pair[0];
                const v = __may_pair[1];
                if (type(opts[k]) == type(v)) {
                    opts[k] = v;
                } else {
                    warning("mouse_setup:unknown/mismatched key:" ++ k);
                }
            }
        } else {
            opts.layer = ((type(a[2]) == "number") and a[2]) or opts.layer;
            opts.pickdepth = ((type(a[3]) == "number") and a[3]) or opts.pickdepth;
            opts.cachepick = ((type(a[4]) == "boolean") and a[4]) or opts.cachepick;
            opts.hidden = ((type(a[5]) == "boolean") and a[5]) or opts.hidden;
        }
        mstate.hidden = opts.hidden;
        mstate.x = math.floor(mstate.max_x * 0.5);
        mstate.y = math.floor(mstate.max_y * 0.5);
        mstate.cursor = null_surface(1, 1);
        image_mask_set(mstate.cursor, MASK_UNPICKABLE);
        if (!valid_vid(cvid)) {
            cvid = fill_surface(32, 32, 0, 127, 0);
        }
        mouse_add_cursor("default", cvid, 0, 0);
        var props = image_surface_properties(cvid);
        mstate.size = .{
            props.width,
            props.height,
        };
        mstate.rt = rt;
        mouse_switch_cursor();
        if (!hidden) {
            show_image(mstate.cursor);
        }
        mouse_cursor_draw();
        mstate.pickdepth = opts.pickdepth;
        order_image(mstate.cursor, opts.layer);
        image_mask_set(mstate.cursor, MASK_UNPICKABLE);
        if (opts.cachepick) {
            mouse_pickfun = cached_pick;
        } else {
            mouse_pickfun = pick_items;
        }
        mouse_cursorupd(0, 0);
        var set = .{
            "accel_x",
            "accel_y",
            "dblclickstep",
            "drag_delta",
            "hover_ticks",
            "hover_thresh",
            "click_timeout",
            "animation_speed",
            "long_press",
        };
        for (set, 0..) |v, _| {
            var key = get_key("mouse_" ++ v);
            if (key) {
                var okt = type(mstate[v]);
                if (okt == "number") {
                    var val = tonumber(okt);
                    if (val) {
                        mstate[v] = val;
                    }
                } else if (okt == "string") {
                    mstate[v] = key;
                }
            }
        }
    } }.mouse_setup;

    const mouse_absinput_masked = struct { pub fn mouse_absinput_masked(x: anytype, y: anytype, nofwd: anytype) void {
        mouse_hidemask(true);
        mouse_absinput(x, y, nofwd);
        mouse_hidemask(false);
    } }.mouse_absinput_masked;

    const mouse_warp = struct { pub fn mouse_warp(x: anytype, y: anytype, nofwd: anytype) void {
        mstate.x = x;
        mstate.y = y;
        mstate.press_x = x;
        mstate.press_y = y;
        mouse_cursor_draw(nofwd);
    } }.mouse_warp;

    const mouse_absinput = struct { pub fn mouse_absinput(x: i64, y: i64, nofwd: bool) void {
        var rx = x - mstate.x;
        var ry = y - mstate.y;
        var arx = mstate.accel_x * rx;
        var ary = mstate.accel_y * ry;

        mstate.rel_x = arx;
        mstate.rel_y = ary;
        mstate.x = x + (arx - rx);
        mstate.y = y + (ary - ry);
        lock_constrain();
        mouse_cursor_draw(nofwd);
        if (!nofwd) {
            mouse_input(mstate.x, mstate.y, null, true);
        }
    } }.mouse_absinput;

    const mouse_lockto = struct { pub fn mouse_lockto(vid: anytype, fun: anytype, warp: anytype, state: anytype) V {
        var olv = mstate.lockvid;
        var olf = mstate.lockfun;
        var olw = mstate.warp;
        var ols = mstate.lockstate;

        if (valid_vid(vid)) {
            mstate.lockvid = vid;
            mstate.lockfun = fun;
            mstate.lockstate = state;
            mstate.warp = ((warp != null) and warp) or false;
        } else {
            mstate.lockvid = null;
            mstate.lockfun = null;
            mstate.lockstate = null;
            mstate.warp = false;
        }
        return __may_mv(olv, olf, olw, ols);
    } }.mouse_lockto;

    const mouse_hotxy = struct { pub fn mouse_hotxy() V {
        return __may_mv((mstate.x - mstate.hotspot_x * mstate.scale_w), (mstate.y - mstate.hotspot_y * mstate.scale_h));
    } }.mouse_hotxy;

    const mouse_xy = struct { pub fn mouse_xy() V {
        return __may_mv(mstate.x, mstate.y);
    } }.mouse_xy;

    const mouse_cursortag_drop = struct { pub fn mouse_cursortag_drop(accept: anytype, state: anytype) void {
        if (mstate.cursortag) {
            mstate.cursortag.handler(mstate.cursortag.ref, accept, state);
            if (valid_vid(mstate.cursortag.vid)) {
                expire_image(mstate.cursortag.vid, mstate.animation_speed);
                const lb, const _, const _ = reset_image_transform(mstate.cursortag.vid);
                blend_image(mstate.cursortag.vid, 0.0, mstate.animation_speed - lb, INTERP_EXPOUT);
                delete_image(mstate.cursortag.vid);
            }
            mstate.cursortag = null;
        }
    } }.mouse_cursortag_drop;

    const mouse_cursortag = struct { pub fn mouse_cursortag(ref: anytype, src: anytype, handler: anytype, vid: anytype) void {
        if (type(handler) != "function") {
            return;
        }
        mouse_cursortag_drop();
        if (!valid_vid(vid)) {
            return;
        }
        image_mask_set(vid, MASK_UNPICKABLE);
        link_image(vid, mstate.cursor, ANCHOR_LR);
        image_inherit_order(vid, true);
        order_image(vid, -1);
        var props = image_surface_properties(vid);

        mstate.cursortag = .{
            .src = src,
            .vid = vid,
            .ref = ref,
            .handler = handler,
        };
    } }.mouse_cursortag;

    const mouse_cursortag_state = struct { pub fn mouse_cursortag_state(accept: anytype) void {
        if (!mstate.cursortag) {
            return;
        }
        if (valid_vid(mstate.cursortag.vid)) {
            const lb, const _, const _ = reset_image_transform(mstate.cursortag.vid);
            blend_image(mstate.cursortag.vid, (accept and 0.5) or 1.0, mstate.animation_speed - lb);
        }
        mstate.cursortag.accept = accept;
    } }.mouse_cursortag_state;

    const mouse_drag = struct { fn mouse_drag(x: anytype, y: anytype) V {
        var hitc = 0;
        for (pairs(mstate.drag.list)) |__may_pair| {
            const key = __may_pair[0];
            const val = __may_pair[1];
            var res: Obj = linear_find_vid(mstate.handlers.drag, val, "drag");
            if (res) {
                res.drag(val, x, y, mstate.drag.id);
                hitc = hitc + 1;
            }
        }
        return hitc;
    } }.mouse_drag;

    const bhandler = struct { fn bhandler(hists: anytype, press: anytype, id: anytype) void {
        if (press) {
            if ((id != MOUSE_RBUTTON) or mstate.rdrag) {
                mstate.press_x = mstate.x;
                mstate.press_y = mstate.y;
                mstate.predrag = .{
                    .list = hists,
                    .count = mstate.drag_delta,
                    .id = id,
                };
            }
            mstate.click_cnt = mstate.click_timeout;
            mstate.lmb_global_press();
            for (hists, 0..) |val, key| {
                var res = linear_find_vid(mstate.handlers.press, val, "press");
                if (res) {
                    mstate.pending_release = val;
                    if (__may_method(res.press, val, mstate.x, mstate.y)) {
                        break;
                    }
                }
            }
        } else {
            if (val == mstate.pending_release) {
                mstate.pending_release = null;
            }
            mstate.lmb_global_release();
            for (hists, 0..) |val, key| {
                var res = linear_find_vid(mstate.handlers.release, val, "release");
                if (res) {
                    if (__may_method(res.release, val, mstate.x, mstate.y)) {
                        break;
                    }
                }
            }
            if (mstate.drag) {
                for (pairs(mstate.drag.list)) |__may_pair| {
                    const key = __may_pair[0];
                    const val = __may_pair[1];
                    var res = linear_find_vid(mstate.handlers.drop, val, "drop");
                    if (res) {
                        if (__may_method(res.drop, val, mstate.x, mstate.y, mstate.cursor_tag)) {
                            return;
                        }
                    }
                }
            } else {
                if (mstate.click_cnt > 0) {
                    for (hists, 0..) |val, key| {
                        var sym = ((id == MOUSE_RBUTTON) and "rclick") or "click";
                        var res = linear_find_vid(mstate.handlers.click, val, sym);
                        if (res) {
                            if (res[sym](val, mstate.x, mstate.y)) {
                                break;
                            }
                        }
                    }
                }
                if ((mstate.counter > 0) and (mstate.counter <= mstate.dblclickstep)) {
                    for (hists, 0..) |val, key| {
                        var res = linear_find_vid(mstate.handlers.dblclick, val, "dblclick");
                        if (res) {
                            if (__may_method(res.dblclick, val, mstate.x, mstate.y, id)) {
                                break;
                            }
                        }
                    }
                }
            }
            mstate.counter = 0;
            mstate.predrag = null;
            mstate.drag = null;
        }
    } }.bhandler;

    const mouse_lockh = struct { fn mouse_lockh(relx: anytype, rely: anytype) void {
        if (!valid_vid(mstate.lockvid)) {
            mouse_lockto();
        } else if (mstate.lockfun) {
            const x, const y = mouse_xy();
            mstate.lockfun(relx, rely, x, y, mstate.lockstate);
        }
    } }.mouse_lockh;

    const mouse_btnlock = struct { fn mouse_btnlock(ind: anytype, active: anytype) void {
        const x, const y = mouse_xy();
        if (!valid_vid(mstate.lockvid)) {
            mouse_lockto(null, null);
        } else if (mstate.lockfun) {
            mstate.lockfun(0, 0, x, y, mstate.lockstate, ind, active);
        }
    } }.mouse_btnlock;

    const mouse_button_input = struct { pub fn mouse_button_input(ind: anytype, active: bool) V {
        ind = mstate.btns_remap[ind];
        if (!ind or (mstate.btns[ind] == active)) {
            return;
        }
        if (active and (mstate.btns_bounce[ind] > 0) and ((CLOCK - mstate.btns_clock[ind]) < mstate.btns_bounce[ind])) {
            return;
        }
        if (mstate.btns[ind] == active) {
            return;
        }
        mstate.hide_count = mstate.hide_base;
        if (mstate.lockvid) {
            mstate.btns[ind] = active;
            mstate.btns_clock[ind] = CLOCK;
            return mouse_btnlock(ind, active);
        }
        var hists = mouse_pickfun(mstate.x, mstate.y, mstate.pickdepth, 1, mstate.rt);

        if (DEBUGLEVEL > 2) {
            var res = .{};
            print("button matches:");
            for (hists, 0..) |v, i| {
                print("\t" ++ (tostring(v) ++ (":" ++ (((image_tracetag(v) != null) and image_tracetag(v)) or "unknown"))));
            }
            print("\n");
        }
        if (@intCast(mstate.handlers.button.len) > 0) {
            for (hists, 0..) |val, key| {
                var res = linear_find_vid(mstate.handlers.button, val, "button");
                if (res) {
                    if (active) {
                        if (!mstate.active_list[ind]) {
                            mstate.active_list[ind] = .{};
                        }
                        table.insert(mstate.active_list[ind], .{
                            res,
                            val,
                        });
                    } else if (mstate.active_list[ind]) {
                        for (mstate.active_list[ind], 0..) |v, i| {
                            if (v[2] == val) {
                                table.remove(mstate.active_list[ind], i);
                                break;
                            }
                        }
                    }
                    __may_method(res.button, val, ind, active, mstate.x, mstate.y);
                }
            }
            if (!active) {
                if (mstate.active_list[ind]) {
                    for (mstate.active_list[ind], 0..) |v, i| {
                        if (v[1].button) {
                            __may_method(v[1].button, v[2], ind, false, mstate.x, mstate.y);
                        }
                    }
                    mstate.active_list[ind] = .{};
                }
            }
        }
        mstate.in_handler = true;
        if ((ind == MOUSE_LBUTTON) and (active != mstate.btns[MOUSE_LBUTTON])) {
            bhandler(hists, active, MOUSE_LBUTTON);
        }
        if ((ind == MOUSE_RBUTTON) and (active != mstate.btns[MOUSE_RBUTTON])) {
            bhandler(hists, active, MOUSE_RBUTTON);
        }
        mstate.btns[ind] = active;
        mstate.btns_clock[ind] = CLOCK;
        mstate.in_handler = false;
    } }.mouse_button_input;

    const mbh = struct { fn mbh(hists: anytype, state: anytype) void {
        if (state[MOUSE_LBUTTON] != mstate.btns[MOUSE_LBUTTON]) {
            bhandler(hists, state[MOUSE_LBUTTON], MOUSE_LBUTTON);
        } else if (state[MOUSE_RBUTTON] != mstate.btns[MOUSE_RBUTTON]) {
            bhandler(hists, state[MOUSE_RBUTTON], MOUSE_RBUTTON);
        }
        mstate.btns[MOUSE_LBUTTON] = state[MOUSE_LBUTTON];
        mstate.btns[MOUSE_MBUTTON] = state[MOUSE_MBUTTON];
        mstate.btns[MOUSE_RBUTTON] = state[MOUSE_RBUTTON];
    } }.mbh;

    const mouse_reveal_hook = struct { pub fn mouse_reveal_hook(state: anytype) void {
        if (type(state) == "function") {
            mstate.reveal_hook = state;
        } else if (state) {
            mstate.reveal_hook = def_reveal;
        } else {
            mstate.reveal_hook = null;
        }
    } }.mouse_reveal_hook;

    const mouse_over = struct { pub fn mouse_over(vid: anytype) bool {
        for (mstate.cur_over, 0..) |v, i| {
            if (v == vid) {
                return true;
            }
        }
    } }.mouse_over;

    var mid_c = 0;
    var mid_v = .{
        0,
        0,
    };

    const mouse_iotbl_input = struct { pub fn mouse_iotbl_input(iotbl: anytype) bool {
        if (!iotbl.mouse) {
            return false;
        }
        if (iotbl.digital) {
            mouse_button_input(iotbl.subid, iotbl.active);
            return true;
        }
        if (iotbl.relative) {
            if (iotbl.subid == 0) {
                mouse_input(iotbl.samples[1], 0);
            } else if (iotbl.subid == 1) {
                mouse_input(0, iotbl.samples[1]);
            } else if (iotbl.subid == 2) {
                mouse_input(iotbl.samples[1], iotbl.samples[3]);
            }
        } else {
            if (iotbl.subid == 2) {
                mouse_absinput(iotbl.samples[1], iotbl.samples[3]);
            } else {
                mid_v[iotbl.subid + 1] = iotbl.samples[1];
                mid_c = mid_c + 1;
                if (mid_c == 2) {
                    mouse_absinput(mid_v[1], mid_v[2]);
                    mid_c = 0;
                }
            }
        }
        return true;
    } }.mouse_iotbl_input;

    if ((API_VERSION_MAJOR == 0) and (API_VERSION_MINOR < 11)) {
        mouse_iotbl_input = struct { fn anon(iotbl: anytype) void {
            if (iotbl.digital) {
                mouse_button_input(iotbl.subid, iotbl.active);
                return;
            }
            if (iotbl.relative) {
                if (iotbl.subid == 0) {
                    mouse_input(iotbl.samples[2], 0);
                } else {
                    mouse_input(0, iotbl.samples[1]);
                }
            } else {
                mid_v[iotbl.subid + 1] = iotbl.samples[1];
                mid_c = mid_c + 1;
                if (mid_c == 2) {
                    mouse_absinput(mid_v[1], mid_v[2]);
                    mid_c = 0;
                }
            }
        } }.anon;
    }
    const mouse_input = struct { pub fn mouse_input(x: anytype, y: anytype, state: anytype, noinp: bool) V {
        if (type(x) == "table") {
            return mouse_iotbl_input(x);
        }
        if ((x != 0) or (y != 0)) {
            if ((mstate.inertia_x > 0) or (mstate.inertia_y > 0)) {
                mstate.inertia_acc_x = mstate.inertia_acc_x + x;
                mstate.inertia_acc_y = mstate.inertia_acc_y + y;
                if ((math.abs(mstate.inertia_acc_x) > mstate.inertia_x) and (math.abs(mstate.inertia_acc_y) > mstate.inertia_y)) {
                    mstate.inertia_acc_x = 0;
                    mstate.inertia_acc_y = 0;
                } else {
                    return __may_mv(0, 0);
                }
            }
            if (!mstate.revmask and mstate.hidden) {
                instant_image_transform(mstate.cursor);
                blend_image(mstate.cursor, 1.0, 10);
                mstate.hidden = false;
                if (mstate.reveal_hook) {
                    mstate.reveal_hook();
                }
            } else if (mstate.hidden) {
                return __may_mv(0, 0);
            }
        }
        if ((noinp == null) or (noinp == false)) {
            x, y = mouse_cursorupd(x, y);
        } else {
            x = mstate.rel_x;
            y = mstate.rel_y;
        }
        if (mstate.lockvid or mstate.lockfun) {
            return mouse_lockh(x, y);
        }
        mstate.in_handler = true;
        mstate.hover_count = 0;
        if (!mstate.hover_ign and (@intCast(mstate.hover_track.len) > 0)) {
            var dx = math.abs(mstate.hover_x - mstate.x);
            var dy = math.abs(mstate.hover_y - mstate.y);

            if ((dx + dy) > mstate.hover_thresh) {
                for (mstate.hover_track, 0..) |v, i| {
                    if (v.state.hover and __may_method(v.state.hover, v.vid, mstate.x, mstate.y, false)) {
                        break;
                    }
                }
                mstate.hover_track = .{};
                mstate.hover_x = null;
                mstate.last_hover = CLOCK;
            }
        }
        var hists = mouse_pickfun(mstate.x, mstate.y, mstate.pickdepth, 1);

        if (mstate.drag) {
            var hitc = mouse_drag(x, y);
            if (state != null) {
                mbh(hists, state);
            }
            mstate.in_handler = false;
            if (hitc > 0) {
                return;
            }
        }
        for (@intCast(mstate.cur_over.len)..1 + 1) |i| {
            __may_step(-1);
            if (!linear_ifind(hists, mstate.cur_over[i])) {
                var res = linear_find_vid(mstate.handlers.out, mstate.cur_over[i], "out");
                if (res) {
                    __may_method(res.out, mstate.cur_over[i], mstate.x, mstate.y);
                }
                table.remove(mstate.cur_over, i);
            } else {
                var res = linear_find_vid(mstate.handlers.motion, mstate.cur_over[i], "motion");
                if (res) {
                    __may_method(res.motion, mstate.cur_over[i], mstate.x, mstate.y);
                }
            }
        }
        for (1..(@intCast(hists.len)) + 1) |i| {
            if (linear_find(mstate.cur_over, hists[i]) == null) {
                table.insert(mstate.cur_over, hists[i]);
                var res = linear_find_vid(mstate.handlers.over, hists[i], "over");
                if (res) {
                    __may_method(res.over, hists[i], mstate.x, mstate.y, mstate.cursortag);
                }
            }
        }
        if (mstate.predrag) {
            x, y = mouse_xy();
            var dx = math.abs(mstate.press_x - x);
            var dy = math.abs(mstate.press_y - y);
            var dist = math.sqrt(dx * dx + dy * dy);

            if (dist >= mstate.predrag.count) {
                mstate.drag = mstate.predrag;
                mstate.predrag = null;
                mstate.pending_release = null;
                mouse_drag(x - mstate.press_x, y - mstate.press_y);
            }
        }
        if (state == null) {
            mstate.in_handler = false;
            return;
        }
        mbh(hists, state);
        mstate.in_handler = false;
    } }.mouse_input;

    var mouse_input_ref = mouse_input;
    const mouse_block = struct { pub fn mouse_block() void {
        mouse_input = struct { fn anon() void {
        } }.anon;
        mstate.blocked = true;
        mouse_hide();
    } }.mouse_block;

    const mouse_unblock = struct { pub fn mouse_unblock() void {
        mouse_input = mouse_input_ref;
        mstate.blocked = false;
        mouse_show();
    } }.mouse_unblock;

    const mouse_addlistener = struct { pub fn mouse_addlistener(tbl: anytype, events: anytype) void {
        if (tbl == null) {
            warning("mouse_addlistener(), refusing to add empty table.\n");
            warning(debug.traceback());
            return;
        }
        if ((tbl.own == null) and !tbl.own_vid) {
            warning("mouse_addlistener(), missing own function in argument.\n");
            return;
        }
        if (tbl.own_vid) {
            var mvid = tbl.own_vid;
            tbl.own = struct { fn anon(ctx: anytype, vid: anytype) bool {
                return vid == mvid;
            } }.anon;
            mstate.fastmap[mvid] = tbl;
        }
        if (tbl.name == null) {
            warning(" -- mouse listener missing identifier -- ");
            warning(debug.traceback());
            tbl.name = "__missing__";
        } else if (type(tbl.name) != "string") {
            warning(" -- mouse listener invalid field name type : " ++ type(tbl.name));
            warning(debug.traceback());
            tbl.name = "__broken__";
        }
        if (DEBUGLEVEL > 2) {
            warning(string.format("handler count: %d ", mouse_handlercount()));
        }
        if (!events) {
            events = .{};
            for (pairs(mouse_handlers)) |__may_pair| {
                const k = __may_pair[0];
                const _ = __may_pair[1];
                if (tbl[k]) {
                    table.insert(events, k);
                }
            }
        }
        for (events, 0..) |val, ind| {
            if ((mstate.handlers[val] != null) and (linear_find(mstate.handlers[val], tbl) == null) and (tbl[val] != null)) {
                insert_unique(mstate.handlers[val], tbl);
            }
        }
    } }.mouse_addlistener;

    const mouse_handlercount = struct { pub fn mouse_handlercount() V {
        var cnt = 0;
        for (pairs(mstate.handlers)) |__may_pair| {
            const ind = __may_pair[0];
            const val = __may_pair[1];
            cnt = cnt + @intCast(val.len);
        }
        return cnt;
    } }.mouse_handlercount;

    const mouse_dumphandlers = struct { pub fn mouse_dumphandlers() void {
        warning("mouse_dumphandlers()");
        for (pairs(mstate.handlers)) |__may_pair| {
            const ind = __may_pair[0];
            const val = __may_pair[1];
            warning("\t" ++ (ind ++ ":"));
            for (val, 0..) |vtbl, key| {
                warning("\t\t" ++ ((vtbl.name and vtbl.name) or tostring(vtbl)));
            }
        }
        warning("/mouse_dumphandlers()");
    } }.mouse_dumphandlers;

    const drop_match = struct { fn drop_match(intbl: anytype, match: anytype) void {
        for (intbl, 0..) |val, ind| {
            if (val == match) {
                table.remove(intbl, ind);
                break;
            }
        }
    } }.drop_match;

    const mouse_droplistener = struct { pub fn mouse_droplistener(tbl: anytype) void {
        for (pairs(mstate.handlers)) |__may_pair| {
            const key = __may_pair[0];
            const val = __may_pair[1];
            drop_match(val, tbl);
        }
        for (pairs(mstate.active_list)) |__may_pair| {
            const i = __may_pair[0];
            const v = __may_pair[1];
            drop_match(v, tbl);
        }
        if (tbl.own_vid) {
            mstate.fastmap[tbl.own_vid] = null;
        }
    } }.mouse_droplistener;

    const mouse_add_cursor = struct { pub fn mouse_add_cursor(label: anytype, img: anytype, hs_x: anytype, hs_y: anytype, opts: anytype) V {
        if ((label == null) or (type(label) != "string")) {
            if (valid_vid(img)) {
                delete_image(img);
            }
            return warning("mouse_add_cursor(), missing label or wrong type");
        }
        if (cursors[label] != null) {
            delete_image(cursors[label].vid);
        }
        if (!valid_vid(img)) {
            return warning(string.format("mouse_add_cursor(%s), missing image", label));
        }
        opts = (opts and opts) or .{};
        var props = image_storage_properties(img);
        cursors[label] = .{
            .vid = img,
            .hotspot_x = hs_x,
            .hotspot_y = hs_y,
            .width = (opts.width and opts.width) or props.width,
            .height = (opts.height and opts.height) or props.height,
            .shader = opts.shader,
        };
    } }.mouse_add_cursor;

    const mouse_scale = struct { pub fn mouse_scale(factor: i64) void {
        if (!mouse.prescale) {
            mouse.prescale = .{};
        }
        cursor.accel_x = mouse.prescale.ax * factor;
        cursor.accel_y = mouse.prescale.ay * factor;
    } }.mouse_scale;

    const mouse_touch_at = struct { pub fn mouse_touch_at(x: anytype, y: anytype, kind: anytype) V {
        var forward = true;
        kind = (kind and kind) or "tap";
        var hists = mouse_pickfun(x, y, mstate.pickdepth, 1);
        var taph = mstate.handlers.tap;
        for (1..(@intCast(hists.len)) + 1) |i| {
            var res: Obj = linear_find_vid(taph, hists[i], "tap");
            if (res) {
                forward = res.tap(x, y, kind);
            }
        }
        return forward;
    } }.mouse_touch_at;

    const mouse_cursor_sf = struct { pub fn mouse_cursor_sf(fx: anytype, fy: anytype) void {
        mstate.scale_w = (fx and fx) or 1.0;
        mstate.scale_h = (fy and fy) or 1.0;
        if (mstate.scale_i) {
            const i, const f = math.modf(mstate.scale_w);
            mstate.scale_w = ((f > 0.5) and math.ceil(mstate.scale_w)) or math.floor(mstate.scale_w);
            i, f = math.modf(mstate.scale_h);
            mstate.scale_h = ((f > 0.5) and math.ceil(mstate.scale_h)) or math.floor(mstate.scale_h);
            i, f = math.modf(mstate.scale_h);
        }
        var new_w = math.ceil(mstate.size[1] * mstate.scale_w);
        var new_h = math.ceil(mstate.size[2] * mstate.scale_h);

        if (valid_vid(mstate.cursor)) {
            resize_image(mstate.cursor, new_w, new_h);
        }
    } }.mouse_cursor_sf;

    const mouse_custom_cursor = struct { pub fn mouse_custom_cursor(ct: anytype) void {
        image_sharestorage(ct.vid, mstate.cursor);
        mstate.size = .{
            ct.width,
            ct.height,
        };
        mouse_cursor_sf(mstate.scale_w, mstate.scale_h);
        if (ct.shader) {
            image_shader(mstate.cursor, ct.shader);
        } else {
            image_shader(mstate.cursor, "DEFAULT");
        }
        mstate.hotspot_x = ct.hotspot_x;
        mstate.hotspot_y = ct.hotspot_y;
        mstate.active_label = "";
        mstate.custom_cursor = ct;
        mouse_cursor_draw();
    } }.mouse_custom_cursor;

    const mouse_switch_cursor = struct { pub fn mouse_switch_cursor(label: anytype, force: bool) void {
        if (label == null) {
            label = "default";
        }
        if ((label == mstate.active_label) and !force) {
            return;
        }
        if (cursors[label] == null) {
            hide_image(mstate.cursor);
            return;
        }
        var ct = cursors[label];
        mouse_custom_cursor(ct);
        mstate.active_label = label;
    } }.mouse_switch_cursor;

    const mouse_cursors = struct { pub fn mouse_cursors() V {
        return cursors;
    } }.mouse_cursors;

    const mouse_hide = struct { pub fn mouse_hide() void {
        instant_image_transform(mstate.cursor);
        blend_image(mstate.cursor, 0.0, (mstate.revmask and 0) or 20, INTERP_EXPOUT);
    } }.mouse_hide;

    const mouse_autohide = struct { pub fn mouse_autohide(state: anytype) V {
        mstate.autohide = ((state and state) or !mstate.autohide);
        return mstate.autohide;
    } }.mouse_autohide;

    const mouse_hidemask = struct { pub fn mouse_hidemask(st: anytype) void {
        mstate.revmask = st;
    } }.mouse_hidemask;

    const mouse_blocked = struct { pub fn mouse_blocked() V {
        return mstate.blocked;
    } }.mouse_blocked;

    const mouse_show = struct { pub fn mouse_show() void {
        if (mstate.blocked) {
            return;
        }
        instant_image_transform(mstate.cursor);
        blend_image(mstate.cursor, 1.0, 20, INTERP_EXPOUT);
    } }.mouse_show;

    @import("builtin/debug.zig").__init();
    const mouse_tick = struct { pub fn mouse_tick(val: i64) void {
        mstate.counter = mstate.counter + val;
        mstate.hover_count = mstate.hover_count + 1;
        if (mstate.click_cnt > 0) {
            mstate.click_cnt = mstate.click_cnt - 1;
            if ((mstate.click_cnt == 0) and mstate.lmb_pressed and !mstate.drag) {
                var lpa = mstate.long_press;
                if ((lpa == "rclick") or (lpa == "dblclick")) {
                    var hists = mouse_pickfun(mstate.x, mstate.y, mstate.pickdepth, 1, mstate.rt);
                    mstate.predrag = null;
                    for (hists, 0..) |val, _| {
                        var res = linear_find_vid(mstate.handlers[lpa], val, lpa);
                        if (res and res[lpa](res, val, mstate.x, mstate.y)) {
                            break;
                        }
                    }
                }
            }
        }
        if (!mstate.drag and mstate.autohide and (mstate.hidden == false)) {
            mstate.hide_count = mstate.hide_count - val;
            if (mstate.hide_count <= 0) {
                mstate.hidden = true;
                instant_image_transform(mstate.cursor);
                mstate.hide_count = mstate.hide_base;
                blend_image(mstate.cursor, 0.0, mstate.animation_speed, INTERP_EXPOUT);
                return;
            }
        }
        mstate.in_handler = true;
        var hval = mstate.hover_ticks;

        if (mstate.hover_count > hval) {
            if (hover_reset) {
                var hists = mouse_pickfun(mstate.x, mstate.y, mstate.pickdepth, 1);
                for (1..(@intCast(hists.len)) + 1) |i| {
                    var res = linear_find_vid(mstate.handlers.hover, hists[i], "hover");
                    if (res) {
                        if (mstate.hover_x == null) {
                            mstate.hover_x = mstate.x;
                            mstate.hover_y = mstate.y;
                        }
                        __may_method(res.hover, hists[i], mstate.x, mstate.y, true);
                        table.insert(mstate.hover_track, .{
                            .state = res,
                            .vid = hists[i],
                        });
                    }
                }
            }
            hover_reset = false;
        } else {
            hover_reset = true;
        }
        mstate.in_handler = false;
    } }.mouse_tick;

    const mouse_dblclickrate = struct { pub fn mouse_dblclickrate(newr: anytype) V {
        if (newr == null) {
            return mstate.dblclickstep;
        } else {
            mstate.dblclickstep = newr;
        }
    } }.mouse_dblclickrate;

    const mouse_querytarget = struct { pub fn mouse_querytarget(rt: anytype) void {
        if (rt == null) {
            rt = WORLDID;
        }
        var props = image_surface_properties(rt);
        rendertarget_attach(rt, mstate.cursor, RENDERTARGET_DETACH);
        if (mstate.cursortag and mstate.cursortag.vid) {
            rendertarget_attach(rt, mstate.cursortag.vid, RENDERTARGET_DETACH);
        }
        mstate.max_x = props.width;
        mstate.max_y = props.height;
        if (mstate.rt != rt) {
            mstate.rt = rt;
            mouse_select_end();
        }
    } }.mouse_querytarget;

    const mouse_state_save = struct { pub fn mouse_state_save() void {
        mstate.save = .{
            .label = mstate.active_label,
            .lockvid = mstate.lockvid,
            .lockfun = mstate.lockfun,
            .lockwarp = mstate.warp,
            .lockstate = mstate.lockstate,
            .active_label = mstate.active_label,
            .custom_cursor = mstate.custom_cursor,
        };
        mstate.save.x, mstate.save.y = mouse_xy();
        mouse_lockto();
        mstate.active_label = null;
        mouse_switch_cursor("default");
    } }.mouse_state_save;

    const mouse_state_restore = struct { pub fn mouse_state_restore(warp: anytype) void {
        if (!mstate.save) {
            return;
        }
        var save = mstate.save;
        mstate.save = null;
        if (valid_vid(save.lockvid)) {
            mouse_lockto(save.lockvid, save.lockfun, save.lockwarp, save.lockstate);
        }
        if (warp) {
            mouse_absinput_masked(save.x, save.y, true);
        }
        if (save.custom_cursor) {
            mouse_custom_cursor(save.custom_cursor);
        }
    } }.mouse_state_restore;

    const mouse_select_begin = struct { pub fn mouse_select_begin(vid: anytype, constrain: anytype) bool {
        if (!valid_vid(vid)) {
            return false;
        }
        if (mstate.in_select) {
            mouse_select_end();
        }
        mstate.in_select = .{
            .x = mstate.x,
            .y = mstate.y,
            .vid = vid,
            .hidden = mstate.hidden,
            .autodelete = .{},
            .autohide = mstate.autohide,
            .lockvid = mstate.lockvid,
            .lockfun = mstate.lockfun,
        };
        mstate.autohide = false;
        mouse_show();
        if (constrain) {
            assert((constrain[4] - constrain[2]) > 0);
            assert((constrain[3] - constrain[1]) > 0);
            assert((constrain[1] >= 0) and (constrain[2] >= 0));
            assert((constrain[3] <= mstate.max_x) and (constrain[4] <= mstate.max_y));
            var newlock = null_surface(constrain[3] - constrain[1], constrain[4] - constrain[2]);
            mstate.lockvid = newlock;
            move_image(newlock, constrain[1], constrain[2]);
            table.insert(mstate.in_select.autodelete, lockvid);
        }
        link_image(vid, mstate.cursor);
        image_mask_clear(vid, MASK_POSITION);
        image_mask_set(vid, MASK_UNPICKABLE);
        image_inherit_order(vid, true);
        order_image(vid, -1);
        resize_image(vid, 1, 1);
        move_image(vid, mstate.x, mstate.y);
        table.insert(mstate.in_select.autodelete, vid);
        mstate.lockvid = null_surface(MAX_SURFACEW, MAX_SURFACEH);
        mstate.lockfun = struct { fn anon() void {
            const x1, const y1, const x2, const y2 = select_regupd();
            var w = x2 - x1;
            var h = y2 - y1;
            if ((w <= 0) or (h <= 0)) {
                return;
            }
            move_image(vid, x1, y1);
            resize_image(vid, w, h);
        } }.anon;
        return true;
    } }.mouse_select_begin;

    const mouse_select_set = struct { pub fn mouse_select_set(vid: anytype) void {
        if (!mstate.lockfun or !mstate.in_select) {
            return;
        }
        if (valid_vid(vid)) {
            var props = image_surface_resolve_properties(vid);
            mstate.x = props.x + props.width;
            mstate.y = props.y + props.height;
            mstate.in_select.x = props.x;
            mstate.in_select.y = props.y;
            mouse_cursorupd(0, 0);
            mstate.lockfun();
        } else {
            mstate.in_select.x = mstate.x;
            mstate.in_select.y = mstate.y;
            mouse_cursorupd(0, 0);
            mstate.lockfun();
        }
    } }.mouse_select_set;

    const mouse_select_end = struct { pub fn mouse_select_end(handler: anytype) void {
        if (!mstate.in_select) {
            return;
        }
        if (mstate.hidden) {
            mouse_hide();
        }
        if (valid_vid(mstate.lockvid)) {
            delete_image(mstate.lockvid);
        }
        mstate.lockfun = mstate.in_select.lockfun;
        mstate.lockvid = mstate.in_select.lockvid;
        mstate.autohide = mstate.in_select.autohide;
        for (mstate.in_select.autodelete, 0..) |v, i| {
            if (valid_vid(v)) {
                delete_image(v);
            }
        }
        if (handler) {
            handler(select_regupd());
        }
        mstate.in_select = null;
    } }.mouse_select_end;

    const mouse_acceleration = struct { pub fn mouse_acceleration(newvx: anytype, newvy: anytype) V {
        if (newvx == null) {
            return __may_mv(mstate.accel_x, mstate.accel_y);
        } else if (newvy == null) {
            mstate.accel_x = math.abs(newvx);
            mstate.accel_y = math.abs(newvx);
        } else {
            mstate.accel_x = math.abs(newvx);
            mstate.accel_y = math.abs(newvy);
        }
    } }.mouse_acceleration;
}
