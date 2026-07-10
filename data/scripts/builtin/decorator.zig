
pub fn __init() void {
    if (!table.copy) {
        @import("builtin/table.zig").__init();
    }
    const decor_destroy = struct { fn decor_destroy(ctx: anytype) void {
        for (pairs(ctx.vids)) |__may_pair| {
            const _ = __may_pair[0];
            const v = __may_pair[1];
            if (valid_vid(v)) {
                delete_image(v);
            }
        }
        for (ctx.mhs, 0..) |v, _| {
            mouse_droplistener(v);
        }
    } }.decor_destroy;

    const border_color = struct { fn border_color(ctx: anytype, r: anytype, g: anytype, b: anytype, a: anytype) void {
        for (.{
            "t",
            "l",
            "d",
            "r",
        }, 0..) |v, _| {
            var vid = ctx.vids[v];
            if (vid) {
                image_color(vid, r, g, b);
                blend_image(vid, a, 1);
            }
        }
    } }.border_color;

    const switch_rt = struct { fn switch_rt(ctx: anytype, rt: anytype) void {
        for (pairs(ctx.vids)) |__may_pair| {
            const _ = __may_pair[0];
            const v = __may_pair[1];
            rendertarget_attach(rt, v, RENDERTARGET_DETACH);
        }
    } }.switch_rt;

    const self_own = struct { fn self_own(ctx: anytype, vid: anytype) bool {
        return vid == ctx.self;
    } }.self_own;

    const border_click = struct { fn border_click(ctx: anytype, vid: anytype) void {
    } }.border_click;

    const surface_state = struct { fn surface_state(tbl: anytype, delta: anytype, width: i64) i64 {
        var pct = delta / (width + 1);
        if (delta < 16) {
            return 0;
        } else if ((width - delta) < 16) {
            return 2;
        }
        return 1;
    } }.surface_state;

    var dirtbl = .{
        .{
            "rz_diag_l",
            -1,
            -1,
            -1,
            -1,
        },
        .{
            "rz_up",
            0,
            -1,
            0,
            -1,
        },
        .{
            "rz_diag_r",
            1,
            -1,
            0,
            -1,
        },
        .{
            "rz_right",
            1,
            0,
            0,
            0,
        },
        .{
            "rz_diag_r",
            1,
            1,
            0,
            0,
        },
        .{
            "rz_down",
            0,
            1,
            0,
            0,
        },
        .{
            "rz_diag_l",
            -1,
            1,
            -1,
            0,
        },
        .{
            "rz_left",
            -1,
            0,
            -1,
            0,
        },
    };

    const sl_to_dir_mask = struct { fn sl_to_dir_mask(props: anytype, x: i64, y: i64, h: anytype, near: anytype) V {
        if (h) {
            var edge = surface_state(props, x - props.x, props.width);
            if (edge == 0) {
                return (near and dirtbl[1]) or dirtbl[7];
            } else if (edge == 1) {
                return (near and dirtbl[2]) or dirtbl[6];
            } else {
                return (near and dirtbl[3]) or dirtbl[5];
            }
        } else {
            var edge = surface_state(props, y - props.y, props.height);
            if (edge == 0) {
                return (near and dirtbl[1]) or dirtbl[3];
            } else if (edge == 1) {
                return (near and dirtbl[8]) or dirtbl[4];
            } else {
                return (near and dirtbl[7]) or dirtbl[5];
            }
        }
    } }.sl_to_dir_mask;

    const add_mouse = struct { fn add_mouse(tbl: anytype, vid: anytype, mx: anytype, my: anytype, horiz: anytype, near: anytype, name: anytype) void {
        table.insert(tbl.mhs, .{
            .name = name,
            .self = vid,
            .pcache = .{
                image_surface_resolve(vid),
                CLOCK,
            },
            .own = self_own,
            .click = struct { fn anon(ctx: anytype) void {
                if (tbl.select) {
                    tbl.select(tbl, true, ctx.last_cursor);
                }
            } }.anon,
            .drag = struct { fn anon(ctx: anytype, vid: anytype, dx: i64, dy: i64) void {
                if (!tbl.drag_rz) {
                    return;
                }
                tbl.drag_rz(tbl, true, dx * ctx.drag_mask[1], dy * ctx.drag_mask[2], ctx.move_mask[1], ctx.move_mask[2]);
            } }.anon,
            .drop = struct { fn anon(ctx: anytype, vid: anytype) void {
                if (tbl.drag_rz) {
                    tbl.drag_rz(tbl, false, 0, 0, 0, 0);
                }
                if (tbl.select) {
                    tbl.select(tbl, true, ctx.last_cursor);
                }
            } }.anon,
            .motion = struct { fn anon(ctx: anytype, vid: anytype, x: anytype, y: anytype, rx: anytype, ry: anytype) void {
                if ((CLOCK - ctx.pcache[2]) > 10) {
                    ctx.pcache[1] = image_surface_resolve(vid);
                }
                var mask = sl_to_dir_mask(ctx.pcache[1], x, y, horiz, near);
                ctx.drag_mask = .{
                    mask[2],
                    mask[3],
                };
                ctx.move_mask = .{
                    mask[4],
                    mask[5],
                };
                if (tbl.select and (ctx.current_cursor != ctx.last_cursor)) {
                    ctx.current_cursor = mask[1];
                    tbl.select(tbl, false, mask[1]);
                }
                ctx.last_cursor = mask[1];
            } }.anon,
            .out = struct { fn anon(ctx: anytype) void {
                if (tbl.select) {
                    ctx.current_cursor = null;
                    tbl.select(tbl, false);
                }
            } }.anon,
        });
        mouse_addlistener(tbl.mhs[@intCast(tbl.mhs.len)], .{
            "drag",
            "drop",
            "motion",
            "out",
        });
    } }.add_mouse;

    const get_fb = struct { fn get_fb(tbl: anytype, ind: anytype, fb: anytype) V {
        return (tbl[ind] and tbl[ind]) or fb;
    } }.get_fb;

    const build_decor = struct { pub fn build_decor(vid: anytype, cfg: anytype) V {
        var res = .{
            .update = struct { fn anon() void {
            } }.anon,
            .switch_rt = switch_rt,
            .destroy = decor_destroy,
            .border_color = border_color,
            .drag_rz = cfg.drag_rz,
            .select = cfg.select,
            .vids = .{},
            .mhs = .{},
        };
        if (!valid_vid(vid)) {
            return __may_mv(false, "attempt to decorate a non-existing video object");
        }
        var use_mouse = (cfg.drag_rz != null) or (cfg.select != null);
        if (!cfg.border or (@intCast(cfg.border.len) != 4)) {
            return __may_mv(false, "missing border / invalid size (t,l,d,r) expected");
        }
        res.border = table.copy(cfg.border);
        var wpad = .{
            0,
            0,
            0,
            0,
        };
        if (cfg.pad) {
            wpad = cfg.pad;
        }
        if (cfg.border[1] > 0) {
            var pad = cfg.border[2] + cfg.border[4] + wpad[2] + wpad[4];
            res.vids.t = color_surface(pad + 1, cfg.border[1], 1, 32, 32, 32);
            link_image(res.vids.t, vid, ANCHOR_UL, ANCHOR_SCALE_W);
            move_image(res.vids.t, -cfg.border[2] - wpad[2], -cfg.border[1] - wpad[1]);
            if (!cfg.force_order) {
                image_inherit_order(res.vids.t, true);
                order_image(res.vids.t, 1);
            } else {
                order_image(res.vids.t, cfg.force_order);
            }
            if (use_mouse) {
                add_mouse(res, res.vids.t, -1, 0, true, true, "top");
            }
        }
        if (cfg.border[2] > 0) {
            var pad = wpad[1] + wpad[3];
            res.vids.l = color_surface(cfg.border[2], pad + 1, 32, 32, 32);
            link_image(res.vids.l, vid, ANCHOR_UL, ANCHOR_SCALE_H);
            move_image(res.vids.l, -cfg.border[2] - wpad[2], -wpad[1]);
            image_inherit_order(res.vids.l, true);
            if (!cfg.force_order) {
                image_inherit_order(res.vids.l, true);
                order_image(res.vids.l, 1);
            } else {
                order_image(res.vids.l, cfg.force_order);
            }
            if (use_mouse) {
                add_mouse(res, res.vids.l, -1, 0, false, true, "left");
            }
        }
        if (cfg.border[3] > 0) {
            var pad = cfg.border[2] + cfg.border[4] + wpad[2] + wpad[4];
            res.vids.d = color_surface(pad + 1, cfg.border[3], 1, 32, 32, 32);
            link_image(res.vids.d, vid, ANCHOR_LL, ANCHOR_SCALE_W);
            image_inherit_order(res.vids.d, true);
            if (!cfg.force_order) {
                image_inherit_order(res.vids.d, true);
                order_image(res.vids.d, 1);
            } else {
                order_image(res.vids.d, cfg.force_order);
            }
            move_image(res.vids.d, -cfg.border[2] - wpad[2], wpad[3]);
            if (use_mouse) {
                add_mouse(res, res.vids.d, 0, 1, true, false, "down");
            }
        }
        if (cfg.border[4] > 0) {
            var pad = wpad[1] + wpad[3];
            res.vids.r = color_surface(cfg.border[4], pad + 1, 32, 32, 32);
            link_image(res.vids.r, vid, ANCHOR_UR, ANCHOR_SCALE_H);
            image_inherit_order(res.vids.r, true);
            if (!cfg.force_order) {
                image_inherit_order(res.vids.r, true);
                order_image(res.vids.r, 1);
            } else {
                order_image(res.vids.r, cfg.force_order);
            }
            move_image(res.vids.r, wpad[4], -wpad[1]);
            if (use_mouse) {
                add_mouse(res, res.vids.r, 0, 1, false, false, "right");
            }
        }
        return res;
    } }.build_decor;

    return struct { fn anon(cfg: anytype) V {
        return struct { fn anon(vid: anytype) V {
            return build_decor(vid, cfg);
        } }.anon;
    } }.anon;
}
