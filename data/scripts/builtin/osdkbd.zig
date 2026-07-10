
pub fn __init() void {
    var set_defaults = undefined;
    var row_to_buttons = undefined;
    var kbd_destroy = undefined;
    var kbd_reset = undefined;
    var kbd_show = undefined;
    var kbd_hide = undefined;
    var set_page = undefined;
    @import("builtin/wmsupport.zig").__init();
    const osdkbd_build = struct { pub fn osdkbd_build(canvas: anytype, icon_lookup: anytype, pages: anytype, opts: anytype) V {
        var res = .{
            .canvas = canvas,
            .pages = .{},
            .orig_pages = pages,
            .opts = (opts and opts) or .{},
            .icon_lookup = icon_lookup,
            .destroy = kbd_destroy,
            .reset = kbd_reset,
            .hide = kbd_hide,
            .show = kbd_show,
            .set_page = kbd_set_page,
        };
        set_defaults(res.opts);
        for (pages, 0..) |v, i| {
            var rows = .{};
            res.pages[i] = rows;
            for (v, 0..) |row, n| {
                table.insert(rows, row_to_buttons(res, i, row, icon_lookup));
            }
        }
        if (opts.bottom) {
            res.bottom = row_to_buttons(res, 0, opts.bottom, icon_lookup);
        }
        return res;
    } }.osdkbd_build;

    kbd_destroy = struct { fn anon(kbd: anytype) void {
        var buttons = .{};
        for (kbd.pages, 0..) |page, _| {
            for (page, 0..) |row, _| {
                for (row, 0..) |btn, _| {
                    table.insert(buttons, btn);
                }
            }
        }
        if (kbd.top) {
            for (kbd.top, 0..) |btn, _| {
                table.insert(buttons, btn);
            }
        }
        if (kbd.bottom) {
            for (kbd.bottom, 0..) |btn, _| {
                table.insert(buttons, btn);
            }
        }
        for (buttons, 0..) |btn, _| {
            if (valid_vid(btn.vid)) {
                expire_image(btn.vid, kbd.opts.animation_speed);
                btn.vid = null;
            }
            if (btn.handlers) {
                mouse_droplistener(btn.handlers);
            }
        }
        expire_image(kbd.canvas, kbd.opts.animation_speed);
        var kl = .{};
        for (pairs(kbd)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            table.insert(kl, k);
        }
        for (kl, 0..) |k, _| {
            kbd[k] = null;
        }
    } }.anon;
    kbd_show = struct { fn anon(kbd: Obj) void {
        blend_image(kbd.canvas, 1.0, kbd.opts.animation_speed, kbd.opts.animation_fn);
        kbd.set_page(1);
    } }.anon;
    const layout_row = struct { fn layout_row(kbd: anytype, row: anytype, x_ofs: anytype, y_ofs: anytype, fair_h: anytype, max_w: i64, opts: anytype) V {
        var dw_count = 0;

        for (row, 0..) |btn, _| {
            dw_count = dw_count + btn.width_factor;
            if (!btn.mouse) {
                mouse_addlistener(btn, btn.handlers);
                btn.mouse = true;
            }
        }
        var fair_w = (max_w - (dw_count - 1) * opts.hpad) / dw_count;

        var btn_render = struct { fn anon(btn: Obj, ind: anytype, w: anytype, x_ofs: i64) void {
            w = math.floor(w * btn.width_factor);
            if (ind == @intCast(row.len)) {
                w = max_w - x_ofs;
            }
            btn.vid, handlers = btn.sym(kbd, w, fair_h);
            for (pairs(handlers)) |__may_pair| {
                const k = __may_pair[0];
                const v = __may_pair[1];
                btn[k] = v;
            }
            image_tracetag(btn.vid, "osd_button");
            link_image(btn.vid, kbd.canvas);
        } }.anon;
        for (row, 0..) |btn, ind| {
            if (!valid_vid(btn.vid)) {
                btn_render(btn, ind, fair_w, x_ofs);
            }
            if (valid_vid(btn.vid)) {
                move_image(btn.vid, x_ofs, y_ofs);
                x_ofs = x_ofs + image_surface_resolve(btn.vid).width + opts.hpad;
                show_image(btn.vid);
            }
        }
        return fair_h;
    } }.layout_row;

    kbd_set_page = struct { fn anon(kbd: anytype, ind: anytype, flush: anytype) void {
        if (flush and kbd.pages[ind]) {
            for (kbd.pages[ind], 0..) |row, _| {
                for (row, 0..) |btn, _| {
                    if (valid_vid(btn.vid)) {
                        delete_image(btn.vid);
                    }
                    if (btn.mouse) {
                        mouse_droplistener(btn.handlers);
                    }
                }
            }
            kbd.pages[ind] = null;
        }
        if (!kbd.pages[ind]) {
            if (kbd.orig_pages[ind]) {
                kbd.pages[ind] = .{};
                for (kbd.orig_pages[ind], 0..) |row, _| {
                    table.insert(kbd.pages[ind], row_to_buttons(kbd, ind, row, kbd.icon_lookup));
                }
            } else {
                return;
            }
        }
        var old_index = (kbd.page_index and kbd.page_index) or 1;
        if (kbd.page_index and (kbd.page_index != ind)) {
            for (kbd.pages[kbd.page_index], 0..) |row, _| {
                for (row, 0..) |btn, _| {
                    if (valid_vid(btn.vid)) {
                        hide_image(btn.vid);
                    }
                }
            }
        }
        kbd.page_index = ind;
        var props = image_surface_resolve(kbd.canvas);
        var n_rows = @intCast(kbd.pages[ind].len);
        var row_ofs = 0;
        var opts = kbd.opts;

        if (opts.completion) {
            row_ofs = row_ofs + 1;
            n_rows = n_rows + 1;
        }
        if (kbd.opts.buffer) {
            row_ofs = row_ofs + 1;
            n_rows = n_rows + 1;
        }
        if (kbd.bottom) {
            n_rows = n_rows + 1;
        }
        var half_hpad = math.ceil(opts.hpad * 0.5);
        var half_vpad = math.ceil(opts.vpad * 0.5);

        n_rows = n_rows + row_ofs;
        props.height = props.height - half_vpad;
        props.width = props.width - half_hpad;
        var fair_h = math.floor(((props.height - ((n_rows - 1) * opts.hpad))) / n_rows);
        var row_y = math.floor(opts.vpad);
        var x_ofs = half_hpad;

        if (kbd.opts.buffer) {
        }
        for (kbd.pages[ind], 0..) |v, i| {
            if ((i == @intCast(kbd.pages.len)) and !kbd.bottom) {
                fair_h = props.height - row_y;
            }
            row_y = row_y + opts.vpad + layout_row(kbd, v, x_ofs, row_y, fair_h, props.width, opts);
        }
        if (kbd.bottom) {
            for (kbd.bottom, 0..) |v, k| {
                if (valid_vid(v.vid)) {
                    delete_image(v.vid);
                }
            }
            row_y = row_y + opts.vpad + layout_row(kbd, kbd.bottom, x_ofs, row_y, props.height - row_y, props.width, opts);
            for (kbd.bottom, 0..) |v, i| {
                if (v.latch and (type(v.original_handler) == "number")) {
                    v.latch(v.original_handler == ind);
                }
            }
        }
    } }.anon;
    kbd_hide = struct { fn anon(kbd: anytype) void {
        blend_image(kbd.canvas, 0.0, kbd.opts.animation_speed, kbd.opts.animation_fn);
    } }.anon;
    kbd_reset = struct { fn anon(kbd: anytype) void {
    } }.anon;
    const gen_press = struct { fn gen_press(btn: anytype, ch: anytype) V {
        return .{
            .{
                .kind = "translated",
                .devid = 1,
                .subid = 1,
                .utf8 = ch,
                .translated = true,
                .active = true,
                .keysym = 1,
                .number = 1,
                .modifiers = 0,
            },
            .{
                .kind = "translated",
                .devid = 1,
                .subid = 1,
                .translated = true,
                .active = false,
                .modifiers = 0,
            },
        };
    } }.gen_press;

    set_defaults = struct { fn anon(opts: anytype) void {
        if (!opts.hpad) {
            opts.hpad = 1;
        }
        if (!opts.vpad) {
            opts.vpad = 1;
        }
        if (!opts.pt_sz) {
            opts.pt_sz = 10;
        }
        if (!opts.animation_speed) {
            opts.animation_speed = 10;
        }
        if (!opts.animation_fn) {
            opts.animation_fn = INTERP_EXPIN;
        }
        if (!opts.input_string) {
            opts.input_string = struct { fn anon(str: anytype) void {
                print("input_string", str);
            } }.anon;
        }
    } }.anon;
    const handler_for_button = struct { fn handler_for_button(kbd: anytype, ctx: anytype, btn: anytype) V {
        if (type(btn.handler) == "string") {
            return struct { fn anon() void {
                if (ctx.activate) {
                    __may_method(ctx.activate);
                }
                kbd.opts.input_string(btn.handler);
            } }.anon;
        } else if (type(btn.handler) == "function") {
            return struct { fn anon() void {
                if (ctx.activate) {
                    __may_method(ctx.activate);
                }
                btn.handler();
            } }.anon;
        } else if (type(btn.handler) == "number") {
            return struct { fn anon() void {
                if (kbd.page_btn and kbd.page_btn.latch) {
                    kbd.page_btn.latch(false);
                    kbd.page_btn = null;
                }
                if (btn.handler == kbd.page_index) {
                    __may_method(kbd.set_page, 1);
                    return;
                }
                __may_method(kbd.set_page, btn.handler);
            } }.anon;
        }
    } }.handler_for_button;

    row_to_buttons = struct { fn anon(kbd: anytype, page: anytype, row: anytype, icon_lookup: anytype) V {
        var res = .{};
        for (row, 0..) |btn, n| {
            var hnd = struct { fn anon() void {
            } }.anon;
            var new_btn = .{
                .sym = icon_lookup(btn.sym),
                .width_factor = (btn.width_factor and btn.width_factor) or 1,
                .own = struct { fn anon(ctx: anytype, vid: anytype) bool {
                    return vid == ctx.vid;
                } }.anon,
                .over = struct { fn anon() void {
                } }.anon,
                .out = struct { fn anon() void {
                } }.anon,
                .name = string.format("%d_row_button_%d", page, n, @intCast(res.len)),
            };

            new_btn.handlers = .{
                "click",
                "tap",
                "rclick",
                "over",
                "out",
            };
            new_btn.handler = handler_for_button(kbd, new_btn, btn);
            new_btn.original_handler = btn.handler;
            new_btn.click = new_btn.handler;
            new_btn.tap = new_btn.handler;
            new_btn.rclick = new_btn.handler;
            if (btn.over) {
                new_btn.over = btn.over;
            }
            if (btn.out) {
                new_btn.out = btn.out;
            }
            new_btn.latch = btn.latch;
            new_btn.activate = btn.activate;
            table.insert(res, new_btn);
        }
        return res;
    } }.anon;
    if (APPLID == "osdkbd") {
        const generate_buttons = struct { fn generate_buttons(tbl: anytype) V {
            var res = .{};

            for (pairs(tbl)) |__may_pair| {
                const _ = __may_pair[0];
                const v = __may_pair[1];
                var row = .{};
                for (1..(@intCast(v.len)) + 1) |i| {
                    table.insert(row, .{
                        .sym = __may_method(v.sub, i, i),
                        .handler = __may_method(v.sub, i, i),
                    });
                }
                table.insert(res, row);
            }
            return res;
        } }.generate_buttons;

        const osdkbd = struct { pub fn osdkbd() void {
            var hh = math.floor(VRESH * 0.5);
            var canvas = fill_surface(VRESW, VRESH * 0.5, 127, 127, 127);
            move_image(canvas, 0, VRESH - hh);
            @import("builtin/mouse.zig").__init();
            mouse_setup(fill_surface(8, 8, 0, 255, 0), 65535, 1, true, false);
            var page_1 = .{
                "qwertyuiop",
                "asdfghjkl-",
                "zxcvbnm`|,.",
            };

            var page_2 = .{
                "QWERTYUIOP:",
                "ASDFGHJKL$;",
                "ZXCVBNM\";.,",
            };

            var page_3 = .{
                "123+=@[]",
                "456-/|\\!{}",
                "789*%^()",
            };

            var button_all = .{
                .{
                    .sym = "123",
                    .handler = 3,
                },
                .{
                    .sym = "ABC",
                    .handler = struct { fn anon(kbd: anytype) void {
                    } }.anon,
                },
                .{
                    .sym = " ",
                    .handler = " ",
                    .fill = true,
                },
                .{
                    .sym = "x",
                    .handler = struct { fn anon(buf: anytype) void {
                    } }.anon,
                },
                .{
                    .sym = "->",
                    .handler = struct { fn anon(buf: anytype) void {
                    } }.anon,
                },
            };

            var render = struct { fn anon(msg: anytype) void {
                var vid = render_text(msg);
                if (valid_vid(vid)) {
                    show_image(vid);
                    expire_image(vid, 50);
                }
            } }.anon;
            var opts = .{
                .bottom = button_all,
                .input_string = struct { fn anon(msg: anytype) void {
                    render(msg);
                } }.anon,
            };

            var kbd: Obj = osdkbd_build(canvas, struct { fn anon(sym: anytype) V {
                return struct { fn anon(btn: anytype, kbd: anytype, base_w: anytype, base_h: anytype) V {
                    var txtcol = "\\#ffffff";
                    var bgcol = .{
                        40,
                        40,
                        40,
                    };

                    var lsym = sym;
                    if (type(lsym) == "function") {
                        lsym = lsym(kbd);
                    }
                    var bg = color_surface(base_w, base_h, unpack(bgcol));
                    const label, const lineh, const width, const height, const _ = render_text(.{
                        txtcol,
                        lsym,
                    });
                    link_image(bg, canvas);
                    image_inherit_order(bg, true);
                    order_image(bg, 1);
                    if (valid_vid(label)) {
                        image_mask_set(label, MASK_UNPICKABLE);
                        link_image(label, bg, ANCHOR_C);
                        show_image(label);
                        image_inherit_order(label, true);
                        order_image(label, 1);
                        nudge_image(label, -0.5 * width, -0.5 * height);
                    }
                    return __may_mv(bg, .{
                        .over = struct { fn anon() void {
                            image_color(bg, 150, 40, 0);
                        } }.anon,
                        .out = struct { fn anon() void {
                            image_color(bg, bgcol[1], bgcol[2], bgcol[3]);
                        } }.anon,
                        .select = struct { fn anon() void {
                        } }.anon,
                        .deselect = struct { fn anon() void {
                        } }.anon,
                        .latch = struct { fn anon(on: anytype) void {
                            if (on) {
                                image_color(bg, 40, 0, 150);
                            } else {
                                image_color(bg, 40, 40, 40);
                            }
                        } }.anon,
                    });
                } }.anon;
            } }.anon, .{
                generate_buttons(page_1),
                generate_buttons(page_2),
                generate_buttons(page_3),
            }, opts);

            kbd.show();
        } }.osdkbd;

        const osdkbd_input = struct { pub fn osdkbd_input(iotbl: anytype) void {
            mouse_iotbl_input(iotbl);
        } }.osdkbd_input;
    }
}
