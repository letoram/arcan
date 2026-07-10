
pub fn __init() void {
    @import("builtin/osdkbd.zig").__init();
    var active = null;
    var in_tap = undefined;
    var page_alnum = .{
        "1234567890|",
        "qwertyuiop/",
        "asdfghjkl;\\",
        "zxcvbnm$.:,",
    };
    var page_ALNUM = .{
        "!@#$%^*()[]",
        "QWERTYUIOP_",
        "ASDFGHJKL{}",
        "ZXCVBNM\"'`~",
    };
    var page_numpad = .{
        "123+/=@",
        "456-<>",
        "789&*%^#!",
    };
    const set_order_mask = struct { fn set_order_mask(anchor: anytype, vid: anytype) void {
        image_mask_set(vid, MASK_UNPICKABLE);
        image_clip_on(vid, CLIP_SHALLOW);
        link_image(vid, anchor, ANCHOR_C);
        image_inherit_order(vid, true);
        show_image(vid);
        order_image(vid, 2);
    } }.set_order_mask;

    const prepare_label = struct { fn prepare_label(bg: anytype, fmt: anytype, label: anytype, base_w: anytype) V {
        var width = undefined;
        var height = undefined;
        var lineh = undefined;
        if (type(label) == "string") {
            label, lineh, width, height, _ = render_text(.{
                fmt,
                label,
            });
        } else {
            var props = image_surface_properties(label);
            width = props.width;
            height = props.height;
        }
        if (!valid_vid(label)) {
            return __may_mv(0, 0);
        }
        set_order_mask(bg, label);
        nudge_image(label, -0.5 * width, -0.5 * height);
        return __may_mv(width, height);
    } }.prepare_label;

    const render_factory = struct { fn render_factory(canvas: anytype, sym: anytype) V {
        return struct { fn anon(btn: anytype, kbd: anytype, base_w: f64, base_h: f64) V {
            var txtcol = "\\#ffffff";
            var bgcol = .{
                40,
                40,
                40,
            };
            var lsym = sym;
            var icon = null;
            if (type(lsym) == "function") {
                lsym, icon = lsym(kbd);
            }
            var bg = color_surface(base_w, base_h, unpack(bgcol));
            link_image(bg, canvas);
            image_inherit_order(bg, true);
            order_image(bg, 1);
            var lw = 0;
            var lh = 0;
            if (lsym and (@intCast(lsym.len) > 0)) {
                lw, lh = prepare_label(bg, txtcol, lsym, base_w);
            }
            show_image(bg);
            if (valid_vid(icon)) {
                if (lw > 0) {
                    var quad_w = 0.5 * base_w - (0.5 * lw) - 4;
                    var quad_h = 0.5 * base_h - (0.5 * lh) - 4;
                    if ((quad_w > 0) and (quad_h > 0)) {
                        resize_image(icon, quad_w, quad_h);
                        link_image(icon, bg, ANCHOR_UR);
                        image_inherit_order(icon, true);
                        show_image(icon);
                        order_image(icon, 2);
                        move_image(icon, -quad_w, 0);
                    } else {
                        image_sharestorage(icon, bg);
                        delete_image(icon);
                    }
                } else {
                    prepare_label(bg, txtcol, icon, base_w);
                }
            }
            var mh = .{
                .over = struct { fn anon() void {
                    image_color(bg, 150, 40, 0);
                } }.anon,
                .out = struct { fn anon() void {
                    image_color(bg, bgcol[1], bgcol[2], bgcol[3]);
                } }.anon,
                .activate = struct { fn anon() void {
                    var flash = color_surface(base_w, base_h, 255, 255, 255);
                    link_image(flash, bg);
                    image_inherit_order(flash, true);
                    order_image(flash, 1);
                    blend_image(flash, 1.0, 2);
                    blend_image(flash, 0.0, 3);
                    expire_image(flash, 5);
                } }.anon,
                .latch = struct { fn anon(on: anytype) void {
                    if (on) {
                        image_color(bg, 150, 40, 0);
                    } else {
                        image_color(bg, 40, 40, 40);
                    }
                } }.anon,
            };
            return __may_mv(bg, mh);
        } }.anon;
    } }.render_factory;

    const buttons_for_strtbl = struct { fn buttons_for_strtbl(tbl: anytype) V {
        var res = .{};
        for (tbl, 0..) |v, _| {
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
    } }.buttons_for_strtbl;

    const buttons_for_wm = struct { fn buttons_for_wm(tbl: anytype) V {
        var res = .{};
        var ctrl_row = .{};
        for (1..10 + 1) |i| {
            if (tbl[i] and valid_vid(tbl[i].vid)) {
                table.insert(res, .{
                    .sym = struct { fn anon() V {
                        var icon = null_surface(64, 64);
                        image_sharestorage(tbl[i].vid, icon);
                        return __may_mv(tostring(i), icon);
                    } }.anon,
                    .handler = struct { fn anon() void {
                        switch_workspace(i);
                    } }.anon,
                });
                table.insert(ctrl_row, .{
                    .sym = "X",
                    .handler = struct { fn anon() void {
                        delete_workspace(i);
                    } }.anon,
                });
                table.insert(ctrl_row, .{
                    .sym = "Aud",
                    .handler = struct { fn anon() void {
                        if (tbl[i].aid) {
                            var current = audio_gain(tbl[i].aid, null);
                            audio_gain(tbl[i].aid, 1.0 - current);
                        }
                    } }.anon,
                });
            } else {
                table.insert(res, .{
                    .sym = tostring(i),
                    .handler = struct { fn anon() void {
                        switch_workspace(i);
                    } }.anon,
                });
                table.insert(ctrl_row, .{
                    .sym = "",
                    .handler = struct { fn anon() void {
                    } }.anon,
                });
                table.insert(ctrl_row, .{
                    .sym = "",
                    .handler = struct { fn anon() void {
                    } }.anon,
                });
            }
        }
        var cmd_row = .{};
        table.insert(cmd_row, .{
            .sym = "Paste",
            .handler = struct { fn anon() void {
                clipboard_paste();
            } }.anon,
        });
        table.insert(cmd_row, .{
            .sym = "Exit",
            .handler = struct { fn anon() void {
                __may_method(active.set_page, 5);
            } }.anon,
        });
        return .{
            res,
            ctrl_row,
            cmd_row,
        };
    } }.buttons_for_wm;

    const confirm_shutdown = struct { fn confirm_shutdown() V {
        return .{
            .{
                .{
                    .sym = "Yes",
                    .handler = struct { fn anon() V {
                        return shutdown();
                    } }.anon,
                },
                .{
                    .sym = "No",
                    .handler = struct { fn anon() void {
                        __may_method(active.set_page, 1);
                    } }.anon,
                },
            },
        };
    } }.confirm_shutdown;

    const u8fwd = struct { fn u8fwd(src: anytype, ofs: anytype) V {
        if (ofs <= string.len(src)) {
            while (true) {
                ofs = ofs + 1;
                if ((ofs > string.len(src)) or (utf8kind(string.byte(src, ofs)) < 2)) break;
            }
        }
        return ofs;
    } }.u8fwd;

    var symtable = @import("builtin/keyboard.zig").__init();
    const find_sym = struct { fn find_sym(ch: anytype) V {
        var num = symtable[ch];
        if (num) {
            return __may_mv(num, num, num);
        }
        return __may_mv(0, 0, 0);
    } }.find_sym;

    const send_press_release = struct { fn send_press_release(dst: anytype, u8: anytype, mods: anytype, sym: anytype, label: anytype) void {
        var ktbl = .{
            .kind = "digital",
            .translated = true,
            .active = true,
            .utf8 = u8,
            .devid = 0,
            .subid = sym,
            .label = label,
            .number = sym,
            .modifiers = mods,
            .keysym = sym,
        };
        target_input(dst, ktbl);
        ktbl.active = false;
        ktbl.utf8 = null;
        target_input(dst, ktbl);
    } }.send_press_release;

    const buttons_for_dst = struct { fn buttons_for_dst(tbl: anytype, rows: anytype) V {
        var res = .{};
        if (tbl.input_labels) {
            for (tbl.input_labels, 0..) |v, _| {
                if (v.datatype == "digital") {
                    table.insert(res, .{
                        .sym = ((@intCast(v.vsym.len) > 0) and v.vsym) or v.labelhint,
                        .handler = struct { fn anon() void {
                            send_press_release(tbl.vid, null, 0, 0, v.labelhint);
                        } }.anon,
                    });
                }
            }
        }
        if (tbl.segkind == "terminal") {
            table.insert(res, .{
                .sym = "^C",
                .handler = struct { fn anon() void {
                    send_press_release(tbl.vid, string.char(0x03), 0, 0);
                } }.anon,
            });
        }
        if (@intCast(res.len) < rows) {
            return .{ res };
        } else {
            var rowtbl = .{};
            var npr = math.floor(@intCast(res.len) / rows);
            assert(rows > 1);
            for (1..(rows - 1) + 1) |row| {
                var crow = .{};
                for (1..npr + 1) |i| {
                    table.insert(crow, table.remove(res, 1));
                }
                table.insert(rowtbl, crow);
            }
            if (@intCast(res.len) > 0) {
                table.insert(rowtbl, res);
            }
            return rowtbl;
        }
    } }.buttons_for_dst;

    const send_string = struct { fn send_string(dst: anytype, str: bool, label: anytype) void {
        if (!valid_vid(dst, TYPE_FRAMESERVER) or !str or (@intCast(str.len) == 0)) {
            return;
        }
        var ofs = 1;
        var lofs = 1;
        while (true) {
            ofs = lofs;
            lofs = u8fwd(str, ofs);
            var ch = string.sub(str, ofs, lofs);
            const sub, const number, const keysym = find_sym(lofs);
            send_press_release(dst, ch, 0, keysym);
            if (lofs == ofs) break;
        }
    } }.send_string;

    var current_dst = null;
    const spawn_keyboard = struct { fn spawn_keyboard(wm: anytype, dst: anytype, x: anytype, y: anytype, speed: anytype) void {
        var pages = .{
            buttons_for_strtbl(page_alnum),
            buttons_for_strtbl(page_ALNUM),
            buttons_for_strtbl(page_numpad),
            buttons_for_wm(wm),
            confirm_shutdown(),
        };
        table.insert(pages[3][1], .{
            .sym = string.char(0xE2) ++ (string.char(0x86) ++ string.char(0x91)),
            .handler = struct { fn anon() void {
                send_press_release(dst.vid, null, 0, symtable["UP"]);
            } }.anon,
        });
        table.insert(pages[3][1], .{
            .sym = "TAB",
            .handler = struct { fn anon() void {
                send_press_release(dst.vid, null, 0, symtable["TAB"]);
            } }.anon,
        });
        table.insert(pages[3][2], .{
            .sym = string.char(0xE2) ++ (string.char(0x86) ++ string.char(0x90)),
            .handler = struct { fn anon() void {
                send_press_release(dst.vid, null, 0, symtable["LEFT"]);
            } }.anon,
        });
        table.insert(pages[3][2], .{
            .sym = string.char(0xE2) ++ (string.char(0x86) ++ string.char(0x93)),
            .handler = struct { fn anon() void {
                send_press_release(dst.vid, null, 0, symtable["DOWN"]);
            } }.anon,
        });
        table.insert(pages[3][2], .{
            .sym = string.char(0xE2) ++ (string.char(0x86) ++ string.char(0x92)),
            .handler = struct { fn anon() void {
                send_press_release(dst.vid, null, 0, symtable["RIGHT"]);
            } }.anon,
        });
        var fkeys = .{};
        for (1..10 + 1) |i| {
            var fk = "F" ++ tostring(i);
            table.insert(fkeys, .{
                .sym = fk,
                .handler = struct { fn anon() void {
                    send_press_release(dst.vid, null, 0, symtable[fk]);
                } }.anon,
            });
        }
        table.insert(pages[3], 1, fkeys);
        var bottom = .{
            .{
                .sym = "ESC",
                .handler = struct { fn anon() void {
                    send_press_release(dst.vid, "\n", 0, symtable["ESCAPE"]);
                } }.anon,
            },
            .{
                .sym = "123",
                .handler = 3,
            },
            .{
                .sym = "ABC",
                .handler = 2,
            },
            .{
                .sym = " ",
                .handler = " ",
                .fill = true,
            },
            .{
                .sym = "WM",
                .handler = 4,
            },
            .{
                .sym = string.char(0xc2) ++ (string.char(0xac) ++ string.char(0x85)),
                .handler = struct { fn anon() void {
                    send_press_release(dst.vid, "\n", 0, symtable["ENTER"]);
                } }.anon,
            },
        };
        current_dst = dst;
        var buttons = buttons_for_dst(dst, 4);
        if (buttons) {
            table.insert(pages, buttons);
            table.insert(bottom, .{
                .sym = struct { fn anon() V {
                    var icon = null_surface(64, 64);
                    image_sharestorage(dst.vid, icon);
                    return __may_mv("App", icon);
                } }.anon,
                .handler = @intCast(pages.len),
            });
        }
        table.insert(bottom, .{
            .sym = "Bksp",
            .handler = struct { fn anon() void {
                send_press_release(dst.vid, null, 0, symtable["BACKSPACE"]);
            } }.anon,
        });
        bottom[4].width_factor = @intCast((pages[1][1]).len) - @intCast(bottom.len) + 1;
        const rt, const dw, const dh, const vresw, const vresh = wm_active_display();
        var height = math.floor(dh * 0.3);
        var canvas = fill_surface(dw, height, 32, 32, 32);
        show_image(canvas);
        order_image(canvas, 10);
        instant_image_transform(dst.vid);
        var cache = .{
            wm.anchor,
            image_surface_properties(wm.anchor),
        };
        var opts = .{
            .bottom = bottom,
            .input_string = struct { fn anon(str: anytype) void {
                send_string(dst.vid, str);
            } }.anon,
        };
        active = osdkbd_build(canvas, struct { fn anon(sym: anytype) V {
            return render_factory(canvas, sym);
        } }.anon, pages, opts);
        active.target_cache = cache;
        __may_method(active.show);
        console_osdkbd_reanchor(wm.anchor, speed);
    } }.spawn_keyboard;

    const console_osdkbd_destroy = struct { pub fn console_osdkbd_destroy(speed: anytype) void {
        if (active) {
            var cache = active.target_cache;
            if (valid_vid(cache[1])) {
                move_image(cache[1], 0, 0, speed);
            }
            __may_method(active.destroy);
            active = null;
            in_tap = false;
        }
    } }.console_osdkbd_destroy;

    const console_osdkbd_active = struct { pub fn console_osdkbd_active() V {
        return active;
    } }.console_osdkbd_active;

    var last_io = .{
        .x = 0,
        .y = 0,
        .subid = 0,
    };
    const console_osdkbd_reanchor = struct { pub fn console_osdkbd_reanchor(vid: anytype, speed: anytype) void {
        if (!active) {
            return;
        }
        const _, const _, const dh, const _, const _ = wm_active_display();
        var height = math.floor(dh * 0.3);
        var canvas = active.canvas;
        if (last_io.y < (0.5 * dh)) {
            link_image(canvas, vid, ANCHOR_UL);
            move_image(canvas, 0, -height);
            move_image(vid, 0, height, speed);
        } else {
            link_image(canvas, vid, ANCHOR_LL);
            move_image(vid, 0, -height, speed);
        }
    } }.console_osdkbd_reanchor;

    var old_clock = struct { fn anon() void {
    } }.anon;
    const clock = struct { fn clock() V {
        return old_clock();
    } }.clock;

    if (console_clock_pulse) {
        old_clock = console_clock_pulse;
    }
    console_clock_pulse = clock;
    const console_osdkbd_invalidate = struct { pub fn console_osdkbd_invalidate(wm: anytype, dst: anytype) void {
        console_osdkbd_destroy(0);
        if (!active) {
            return;
        }
        var page = active.page_index;
        spawn_keyboard(wm, dst, last_io.x, last_io.y, 0);
        __may_method(active.set_page, page);
    } }.console_osdkbd_invalidate;

    const console_osdkbd_input = struct { pub fn console_osdkbd_input(wm: anytype, dst: anytype, io: anytype) V {
        var speed = 10;
        if (!io) {
            io = last_io;
        }
        if (io.active) {
            if (active and in_tap and ((CLOCK - in_tap) > 1)) {
                in_tap = false;
            }
            return;
        }
        if (!io.touch) {
            return;
        }
        wm_touch_normalize(io);
        last_io = io;
        if (!in_tap) {
            in_tap = CLOCK;
        } else {
            return;
        }
        if (!active) {
            spawn_keyboard(wm, dst, io.x, io.y, speed);
            return true;
        } else {
            return mouse_touch_at(io.x, io.y, io.subid, "tap");
        }
    } }.console_osdkbd_input;
}
