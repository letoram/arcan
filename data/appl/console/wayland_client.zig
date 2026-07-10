
var tbar_sz = 12;
var focus_color = .{
    127,
    127,
    127,
    255,
};
var unfocus_color = .{
    64,
    64,
    64,
    255,
};
var decor_config = .{
    .border = .{
        2,
        2,
        2,
        2,
    },
    .pad = .{
        tbar_sz,
        0,
        0,
        0,
    },
};
var size_top = decor_config.border[1] + decor_config.pad[1];
var decorator = @import("builtin/decorator.zig").__init()(decor_config);

pub fn __init() void {
    decor_config.select = struct { fn anon(decor: anytype, active: anytype, source: anytype) void {
        if (active) {
            decor.self.wm.focus(decor.self);
        }
    } }.anon;

    decor_config.drag_rz = struct { fn anon(decor: anytype, cont: bool, dx: anytype, dy: anytype, mx: i64, my: i64) void {
        if (!cont) {
            __may_method(decor.self.drag_resize);
        } else {
            __may_method(decor.self.drag_resize, dx, dy, -mx, -my);
        }
    } }.anon;

    const focus = struct { fn focus(ws: anytype, wnd: Obj) void {
        if (ws.focus) {
            if (ws.focus.decorator) {
                var decor: Obj = ws.focus.decorator;
                decor.border_color(unpack(unfocus_color));
                image_color(decor.titlebar, unpack(unfocus_color));
            }
            __may_method(ws.focus.unfocus);
        }
        ws.focus = wnd;
        if (!wnd) {
            return;
        }
        wnd.focus();
        if (wnd.decorator) {
            __may_method(wnd.decorator.border_color, unpack(focus_color));
            image_color(wnd.decorator.titlebar, unpack(focus_color));
        }
    } }.focus;

    const destroy = struct { fn destroy(ws: anytype, wnd: anytype) void {
        if (ws.focus == wnd) {
            ws.focus = null;
        }
        if (!wnd.wm) {
            delete_workspace(ws.workspace_index);
        }
    } }.destroy;

    const mapped = struct { fn mapped(ws: anytype, wnd: anytype) void {
        if (!focus) {
            wnd.wm.focus(wnd);
        }
    } }.mapped;

    const state_change = struct { fn state_change(ws: anytype, wnd: Obj, state: anytype) void {
        if (!state) {
            wnd.revert();
        }
        if (wnd != ws.focus) {
            return;
        }
        if (state == "maximize") {
            wnd.maximize();
        } else if (state == "fullscreen") {
            wnd.fullscreen();
        }
    } }.state_change;

    const move = struct { fn move(ws: anytype, wnd: anytype, x: anytype, y: anytype, dx: anytype, dy: anytype) V {
        if (wnd.decorator) {
            if (y < size_top) {
                y = size_top;
            }
        }
        return __may_mv(x, y);
    } }.move;

    const decorate = struct { fn decorate(ws: anytype, wnd: anytype, vid: anytype, w: anytype, h: anytype, anim_dt: anytype, anim_interp: anytype) V {
        if (!wnd.decorator) {
            var msg = undefined;
            wnd.decorator, msg = decorator(vid);
            if (!wnd.decorator) {
                return;
            }
            wnd.decorator.self = wnd;
            __may_method(wnd.decorator.border_color, 32, 255, 32, 1);
            var tb = color_surface(32, 32, 64, 127, 32);
            link_image(tb, wnd.decorator.vids.l, ANCHOR_UR);
            image_inherit_order(tb, true);
            order_image(tb, 1);
            show_image(tb);
            wnd.decorator.titlebar = tb;
            var mh = .{
                .name = "tbar_mh",
                .own = struct { fn anon(ctx: anytype, vid: anytype) bool {
                    return vid == tb;
                } }.anon,
                .drag = struct { fn anon(ctx: anytype, vid: anytype, dx: anytype, dy: anytype) void {
                    __may_method(wnd.nudge, dx, dy);
                } }.anon,
            };
            table.insert(wnd.decorator.mhs, mh);
            mouse_addlistener(mh, .{ "drag" });
        }
        __may_method(wnd.decorator.update, w, h, anim_dt, anim_interp);
        resize_image(wnd.decorator.titlebar, w, decor_config.pad[1]);
        return __may_mv(decor_config.pad[1] + decor_config.border[1], decor_config.pad[2] + decor_config.border[2], decor_config.pad[3] + decor_config.border[3], decor_config.pad[4] + decor_config.border[4]);
    } }.decorate;

    const configure = struct { fn configure(ws: anytype, wnd: anytype, typestr: []const u8) V {
        if (typestr == "toplevel") {
            return __may_mv(VRESW - decor_config.border[2] - decor_config.border[4], VRESH - tbar_sz - decor_config.border[3], 10, 10);
        }
    } }.configure;

    const wrap = struct { fn wrap(ws: anytype, func: anytype) V {
        return struct { fn anon(va: anytype) V {
            return func(ws, va);
        } }.anon;
    } }.wrap;

    const input_table = struct { fn input_table(ws: anytype, table: anytype) void {
        if (!ws.focus) {
            return;
        }
        __may_method(ws.focus.input_table, table);
    } }.input_table;

    return struct { fn anon(ws: anytype) V {
        ws.input = input_table;
        var cfg = .{
            .focus = wrap(ws, focus),
            .destroy = wrap(ws, destroy),
            .mapped = wrap(ws, mapped),
            .state_change = wrap(ws, state_change),
            .move = wrap(ws, move),
            .configure = wrap(ws, configure),
            .decorate = wrap(ws, decorate),
            .mouse_focus = true,
        };
        if (DEBUGLEVEL < 1) {
            cfg.log = struct { fn anon() void {
            } }.anon;
            cfg.fmt = struct { fn anon() void {
            } }.anon;
        }
        return cfg;
    } }.anon;
}
