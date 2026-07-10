
pub fn __init() void {
    math.sign = struct { fn anon(val: i64) V {
        return ((val < 0) and -1) or 1;
    } }.anon;

    math.clamp = struct { fn anon(val: i64, low: i64, high: i64) i64 {
        if (low and (val < low)) {
            return low;
        }
        if (high and (val > high)) {
            return high;
        }
        return val;
    } }.anon;

    strict_fname_valid = struct { fn anon(val: anytype) bool {
        for (string.gmatch(val, "%W")) |__may_pair| {
            const i = __may_pair[0];
            if (i != "_") {
                return false;
            }
        }
        return true;
    } }.anon;
    table.remove_vmatch = struct { fn anon(tbl: anytype, match: anytype) V {
        if (tbl == null) {
            return;
        }
        for (pairs(tbl)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            if (v == match) {
                tbl[k] = null;
                return v;
            }
        }
        return null;
    } }.anon;

    const suppl_delete_image_if = struct { pub fn suppl_delete_image_if(vid: anytype) void {
        if (valid_vid(vid)) {
            delete_image(vid);
        }
    } }.suppl_delete_image_if;

    const suppl_strcol_fmt = struct { pub fn suppl_strcol_fmt(str: anytype, sel: anytype) V {
        var sum = 0;
        for (1..(@intCast(str.len)) + 1) |i| {
            var ch = string.byte(string.sub(str, i, i));
            sum = sum + ch;
        }
        return HC_PALETTE[(sum % @intCast(HC_PALETTE.len)) + 1];
    } }.suppl_strcol_fmt;

    const suppl_hc_popup = struct { pub fn suppl_hc_popup(set: anytype) V {
        var @"fn" = __may_method(active_display().font_resfn);
        var str = .{ @"fn" };
        var hw = suppl_display_ui_pad();
        for (set, 0..) |v, i| {
            table.insert(str, v);
            table.insert(str, "\\n\\r" ++ suppl_strcol_fmt(v));
        }
        var text = render_text(str);
        var props = image_surface_properties(text);
        var sw = props.width + hw + hw;
        var sh = props.height + hw + hw;
        var ssurf = color_surface(sw, sh, 32, 32, 32);
        var shid = shader_setup(ssurf, "ui", "rounded", "active");
        link_image(ssurf, active_display().order_anchor);
        image_inherit_order(ssurf, true);
        order_image(ssurf, 10);
        link_image(text, ssurf);
        move_image(text, hw, hw);
        image_inherit_order(text, true);
        show_image(text);
        order_image(text, 2);
        return __may_mv(ssurf, sw, sh);
    } }.suppl_hc_popup;

    const suppl_region_stop = struct { pub fn suppl_region_stop(trig: anytype) void {
        iostatem_restore();
        durian_input_sethandler();
        dispatch_symbol_unlock(true);
        mouse_select_end(trig);
    } }.suppl_region_stop;

    const share_input = struct { fn share_input(wnd: Obj, allow_input: anytype, source: anytype, status: anytype, iotbl: anytype) void {
        if (status.kind == "terminated") {
            if (@intCast(status.last_words.len) > 0) {
                notification_add(wnd.title, wnd.icon, "Sharing Died", status.last_words, 2);
            }
            delete_image(source);
            wnd.share_sessions[source] = null;
        } else if ((status.kind == "input") and allow_input) {
            wnd.input_table(iotbl);
        }
    } }.share_input;

    const suppl_build_recargs = struct { pub fn suppl_build_recargs(streaming: anytype, argstr: anytype) V {
        var vcodec = gconfig_get("enc_vcodec");
        var fps = gconfig_get("enc_fps");
        var vbr = gconfig_get("enc_vbr");
        var vqual = gconfig_get("enc_vqual");
        var container = (streaming and "stream") or gconfig_get("enc_container");
        var srate = gconfig_get("enc_srate");

        argstr = string.format("vcodec=%s:fps=%.3f:container=%s%s", vcodec, fps, container, ((vqual > 0) and (":vpreset=" ++ tostring(vqual))) or (":vbitrate=" ++ tostring(vbr)));
        return __may_mv(argstr, srate);
    } }.suppl_build_recargs;

    const suppl_setup_sharing = struct { pub fn suppl_setup_sharing(wnd: anytype, argstr: anytype, srate: anytype, nosound: anytype, destination: anytype, allow_input: anytype, name: anytype) V {
        var props = image_storage_properties(wnd.canvas);

        if (!wnd.ignore_crop and wnd.crop_values) {
            props.width = (wnd.crop_values[4] - wnd.crop_values[2]);
            props.height = (wnd.crop_values[3] - wnd.crop_values[1]);
        }
        var storew = (((props.width % 2) != 0) and (props.width + 1)) or props.width;
        var storeh = (((props.height % 2) != 0) and (props.height + 1)) or props.height;

        var surf = alloc_surface(storew, storeh);
        if (!valid_vid(surf)) {
            return;
        }
        var nsrf = null_surface(props.width, props.height);
        if (!valid_vid(nsrf)) {
            delete_image(surf);
            return;
        }
        image_sharestorage(wnd.canvas, nsrf);
        show_image(nsrf);
        link_image(surf, wnd.anchor);
        var sset = .{};
        if (nosound or !wnd.source_audio) {
            argstr = argstr ++ ":nosound";
        } else {
            sset[1] = wnd.source_audio;
        }
        define_recordtarget(surf, destination, argstr, .{ nsrf }, sset, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, srate, struct { fn anon(va: anytype) void {
            share_input(wnd, allow_input, va);
        } }.anon);
        target_flags(surf, TARGET_BLOCKADOPT);
        if (!wnd.share_sessions) {
            wnd.share_sessions = .{};
        }
        wnd.share_sessions[surf] = name;
        return __may_mv(wnd, surf);
    } }.suppl_setup_sharing;

    const suppl_region_shadow = struct { pub fn suppl_region_shadow(ctx: anytype, w: i64, h: i64, opts: anytype) void {
        opts = (opts and opts) or .{};
        opts.method = (opts.method and opts.method) or gconfig_get("shadow_style");
        if (opts.method == "none") {
            if (valid_vid(ctx.shadow)) {
                delete_image(ctx.shadow);
                ctx.shadow = null;
            }
            return;
        }
        var shname = (opts.shader and opts.shader) or "dropshadow";

        var time = (opts.time and opts.time) or 0;
        var t = (opts.t and opts.t) or gconfig_get("shadow_t");
        var l = (opts.l and opts.l) or gconfig_get("shadow_l");
        var d = (opts.d and opts.d) or gconfig_get("shadow_d");
        var r = (opts.r and opts.r) or gconfig_get("shadow_r");
        var interp = (opts.interp and opts.interp) or INTERP_SMOOTHSTEP;
        var cr = undefined;
        var cg = undefined;
        var cb = undefined;

        if (opts.color) {
            cr, cg, cb = unpack(opts.color);
        } else {
            cr, cg, cb = unpack(gconfig_get("shadow_color"));
        }
        if (!valid_vid(ctx.shadow)) {
            ctx.shadow = color_surface(w + l + r, h + t + d, cr, cg, cb);
            if (!valid_vid(ctx.shadow)) {
                return;
            }
            if (opts.reference and (opts.method == "textured")) {
                image_sharestorage(opts.reference, ctx.shadow);
            }
            blend_image(ctx.shadow, 1.0, time);
            link_image(ctx.shadow, ctx.anchor, ANCHOR_UL);
            image_inherit_order(ctx.shadow, true);
            order_image(ctx.shadow, -1);
            image_mask_set(ctx.shadow, MASK_UNPICKABLE);
            var shid = shader_ui_lookup(ctx.shadow, "ui", shname, "active");
            if (shid) {
                shader_uniform(shid, "color", "fff", cr, cg, cb);
            }
        } else {
            reset_image_transform(ctx.shadow);
            show_image(ctx.shadow, time, interp);
        }
        image_color(ctx.shadow, cr, cg, cb);
        resize_image(ctx.shadow, w + l + r, h + t + d, time, interp);
        move_image(ctx.shadow, -l, -t);
    } }.suppl_region_shadow;

    const suppl_region_select = struct { pub fn suppl_region_select(r: anytype, g: anytype, b: anytype, handler: anytype) void {
        var col = fill_surface(1, 1, r, g, b);
        blend_image(col, 0.2);
        iostatem_save();
        mouse_select_begin(col);
        dispatch_meta_reset();
        shader_setup(col, "ui", "regsel", "active");
        dispatch_symbol_lock();
        durian_input_sethandler(durian_regionsel_input, "region-select");
        DURDEN_REGIONSEL_TRIGGER = handler;
    } }.suppl_region_select;

    var ffmts = .{
        __may_kv("jpg", "image"),
        __may_kv("jpeg", "image"),
        __may_kv("png", "image"),
        __may_kv("bmp", "image"),
        __may_kv("ogg", "audio"),
        __may_kv("m4a", "audio"),
        __may_kv("flac", "audio"),
        __may_kv("mp3", "audio"),
        __may_kv("mp4", "video"),
        __may_kv("wmv", "video"),
        __may_kv("mkv", "video"),
        __may_kv("avi", "video"),
        __may_kv("flv", "video"),
        __may_kv("mpg", "video"),
        __may_kv("mpeg", "video"),
        __may_kv("mov", "video"),
        __may_kv("pdf", "pdf"),
        __may_kv("ps", "pdf"),
        __may_kv("webm", "video"),
        __may_kv("*", "file"),
    };

    const match_ext = struct { fn match_ext(v: anytype, tbl: anytype) V {
        if (tbl == null) {
            return;
        }
        var ext = string.match(v, "^.+(%..+)$");
        ext = ((ext != null) and string.sub(ext, 2)) or ext;
        if ((ext == null) or (string.len(ext) == 0)) {
            return __may_mv(tbl["*"], ext);
        }
        var ent = tbl[string.lower(ext)];
        if (ent) {
            return __may_mv(ent, ext);
        } else {
            return __may_mv(tbl["*"], ext);
        }
    } }.match_ext;

    const suppl_track_table = struct { pub fn suppl_track_table(v: anytype) V {
        var proxy = .{};
        setmetatable(proxy, .{
            .__index = struct { fn anon(t: anytype, k: anytype) V {
                return v[k];
            } }.anon,
            .__newindex = struct { fn anon(t: anytype, k: anytype, val: anytype) void {
                print("table:set", t, k, val);
                v[k] = val;
            } }.anon,
        });
        return proxy;
    } }.suppl_track_table;

    const suppl_ext_type = struct { pub fn suppl_ext_type(@"fn": anytype) V {
        const tbl, const ext = match_ext(@"fn", ffmts);
        return __may_mv(tbl, ext);
    } }.suppl_ext_type;

    const defer_spawn = struct { fn defer_spawn(wnd: anytype, new: anytype, t: anytype, l: anytype, d: anytype, r: anytype, w: anytype, h: anytype, closure: anytype) void {
        if (!wnd.add_handler) {
            delete_image(new);
            return;
        }
        show_image(new);
        var cwin: Obj = __may_method(active_display().add_window, new, .{ .scalemode = "stretch" });
        if (!cwin) {
            delete_image(new);
            return;
        }
        const recrop = struct { fn recrop() void {
            var sprops = image_storage_properties(wnd.canvas);
            cwin.origo_ll = wnd.origo_ll;
            __may_method(cwin.set_crop, t * sprops.height, l * sprops.width, d * sprops.height, r * sprops.width, false, true);
        } }.recrop;

        cwin.add_handler("destroy", struct { fn anon() void {
            if (wnd.drop_handler) {
                __may_method(wnd.drop_handler, "resize", recrop);
            }
        } }.anon);
        recrop();
        cwin.set_title("Slice");
        cwin.source_name = wnd.name;
        cwin.name = cwin.name ++ "_crop";
        if (closure) {
            closure(cwin, t, l, d, r, w, h);
        }
    } }.defer_spawn;

    const slice_handler = struct { fn slice_handler(wnd: anytype, x1: anytype, y1: anytype, x2: anytype, y2: anytype, closure: anytype) void {
        var props = image_surface_resolve(wnd.canvas);
        var px2 = props.x + props.width;
        var py2 = props.y + props.height;

        x1 = ((x1 < props.x) and props.x) or x1;
        y1 = ((y1 < props.y) and props.y) or y1;
        x2 = ((x2 > px2) and px2) or x2;
        y2 = ((y2 > py2) and py2) or y2;
        if (((x2 - x1) <= 0) or ((y2 - y1) <= 0)) {
            return;
        }
        var new = null_surface(x2 - x1, y2 - y1);
        image_sharestorage(wnd.canvas, new);
        var t = (y1 - props.y) / props.height;
        var l = (x1 - props.x) / props.width;
        var d = (py2 - y2) / props.height;
        var r = (px2 - x2) / props.width;
        var w = (x2 - x1);
        var h = (y2 - y1);

        timer_add_periodic("wndspawn", 1, true, struct { fn anon() void {
            defer_spawn(wnd, new, t, l, d, r, w, h, closure);
        } }.anon);
    } }.slice_handler;

    const suppl_wnd_slice = struct { pub fn suppl_wnd_slice(wnd: anytype, closure: anytype) void {
        var wnd = active_display().selected;
        var props = image_surface_resolve(wnd.canvas);

        suppl_region_select(255, 0, 255, struct { fn anon(x1: anytype, y1: anytype, x2: anytype, y2: anytype) void {
            if (valid_vid(wnd.canvas)) {
                slice_handler(wnd, x1, y1, x2, y2, closure);
            }
        } }.anon);
    } }.suppl_wnd_slice;

    const suppl_build_rt_reg = struct { pub fn suppl_build_rt_reg(drt: anytype, x1: anytype, y1: anytype, x2: i64, y2: i64, srate: anytype, shid: anytype) V {
        var w = x2 - x1;
        var h = y2 - y1;

        if ((w <= 0) or (h <= 0)) {
            return;
        }
        var props = image_surface_resolve_properties(drt);
        x1 = x1 - props.x;
        y1 = y1 - props.y;
        var dst = alloc_surface(w, h);
        if (!valid_vid(dst)) {
            warning("build_rt: failed to create intermediate");
            return;
        }
        var cont = null_surface(w, h);
        if (!valid_vid(cont)) {
            delete_image(dst);
            return;
        }
        image_sharestorage(drt, cont);
        var s1 = x1 / props.width;
        var t1 = y1 / props.height;
        var s2 = (x1 + w) / props.width;
        var t2 = (y1 + h) / props.height;

        var txcos = .{
            s1,
            t1,
            s2,
            t1,
            s2,
            t2,
            s1,
            t2,
        };
        image_set_txcos(cont, txcos);
        show_image(.{
            cont,
            dst,
        });
        if (!shid) {
            shid = image_shader(drt);
        }
        if (shid) {
            image_shader(cont, shid);
        }
        return __may_mv(dst, .{ cont });
    } }.suppl_build_rt_reg;

    var color_labels = .{
        .{
            2,
            "primary",
            "Primary",
        },
        .{
            3,
            "secondary",
            "Secondary",
        },
        .{
            4,
            "background",
            "Background",
        },
        .{
            5,
            "text",
            "Text",
        },
        .{
            256 + 5,
            "text_bg",
            "Text-Background",
        },
        .{
            6,
            "cursor",
            "Cursor",
        },
        .{
            7,
            "altcursor",
            "Alternate-Cursor",
        },
        .{
            8,
            "highlight",
            "Text Highlight",
        },
        .{
            256 + 8,
            "highlight_bg",
            "Text Highlight Background",
        },
        .{
            9,
            "label",
            "Label",
            "Group/Content Descriptions",
        },
        .{
            256 + 9,
            "label",
            "Label Background",
            "Group/Content Descriptions",
        },
        .{
            10,
            "warning",
            "Warning",
            "Indicators of recoverable errors",
        },
        .{
            256 + 10,
            "warning_bg",
            "Warning Background",
            "Indicators of recoverable errors",
        },
        .{
            11,
            "error",
            "Error",
        },
        .{
            256 + 11,
            "error",
            "Error Background",
        },
        .{
            12,
            "alert",
            "Alert",
            "Catch user attention",
        },
        .{
            256 + 12,
            "alert",
            "Alert Background",
            "Catch user attention",
        },
        .{
            13,
            "inactive",
            "Inactive",
            "Labels where the related content is currently inaccessible",
        },
        .{
            256 + 13,
            "inactive",
            "Inactive Background",
            "Labels where the related content is currently inaccessible",
        },
        .{
            14,
            "reference",
            "Reference",
            "Actions that reference external contents or trigger navigation",
        },
        .{
            256 + 14,
            "reference",
            "Reference Background",
            "Actions that reference external contents or trigger navigation",
        },
        .{
            15,
            "ui",
            "UI",
            "User Interface Elements",
        },
        .{
            256 + 15,
            "ui",
            "UI Background",
            "User Interface Elements",
        },
        .{
            16,
            "black",
            "Terminal-Black",
        },
        .{
            17,
            "red",
            "Terminal-Red",
        },
        .{
            18,
            "green",
            "Terminal-Green",
        },
        .{
            19,
            "yellow",
            "Terminal-Yellow",
        },
        .{
            20,
            "blue",
            "Terminal-Blue",
        },
        .{
            21,
            "magenta",
            "Terminal-Magenta",
        },
        .{
            22,
            "cyan",
            "Terminal-Cyan",
        },
        .{
            23,
            "light_grey",
            "Terminal-Light-Grey",
        },
        .{
            24,
            "dark_grey",
            "Terminal-Dark-Grey",
        },
        .{
            25,
            "light_red",
            "Terminal-Light-Red",
        },
        .{
            26,
            "light_green",
            "Terminal-Light-Green",
        },
        .{
            27,
            "light_yellow",
            "Terminal-Light-Yellow",
        },
        .{
            28,
            "light_blue",
            "Terminal-Light-Blue",
        },
        .{
            29,
            "light_magenta",
            "Terminal-Light-Magenta",
        },
        .{
            30,
            "light_cyan",
            "Terminal-Light-Cyan",
        },
        .{
            31,
            "white",
            "Terminal-White",
        },
        .{
            32,
            "fg",
            "Terminal-Foreground",
        },
        .{
            33,
            "bg",
            "Terminal-Background",
        },
    };

    const glob_scheme_menu = struct { fn glob_scheme_menu(dst: anytype) V {
        var list = glob_resource("devmaps/colorschemes/*.lua", APPL_RESOURCE);
        var res = .{};
        list = (list and list) or .{};
        for (list, 0..) |v, i| {
            var name = string.sub(v, 1, -5);
            if (@intCast(name.len) > 0) {
                table.insert(res, .{
                    .name = "colorscheme_" ++ tostring(i),
                    .label = name,
                    .description = "Apply colorscheme " ++ name,
                    .kind = "action",
                    .handler = struct { fn anon() void {
                        var tbl = suppl_script_load("devmaps/colorschemes/" ++ v, false);
                        if ((type(tbl) == "table") and valid_vid(dst, type_frameserver)) {
                            suppl_tgt_color(dst, tbl);
                        }
                    } }.anon,
                });
            }
        }
        return res;
    } }.glob_scheme_menu;

    const suppl_colorschemes = struct { pub fn suppl_colorschemes() V {
        var list = glob_resource("devmaps/colorschemes/*.lua", APPL_RESOURCE);
        var res = .{};
        list = (list and list) or .{};
        for (list, 0..) |v, i| {
            var name = string.sub(v, 1, -5);
            if (@intCast(name.len) > 0) {
                table.insert(res, name);
            }
        }
        return res;
    } }.suppl_colorschemes;

    const suppl_color_menu = struct { pub fn suppl_color_menu(vid: anytype) V {
        var res = .{
            .{
                .name = "scheme",
                .label = "Scheme",
                .kind = "action",
                .description = "Apply a static color scheme from (devmaps/colorschemes)",
                .submenu = true,
                .handler = struct { fn anon() V {
                    return glob_scheme_menu(vid);
                } }.anon,
            },
            .{
                .name = "opacity",
                .label = "Opacity",
                .description = "Change background layer opacity (alpha channel)",
                .kind = "value",
                .hint = "(0..1)",
                .validator = gen_valid_float(0, 1),
                .handler = struct { fn anon(ctx: anytype, val: anytype) void {
                    if (!valid_vid(vid, TYPE_FRAMESERVER)) {
                        return;
                    }
                    target_graphmode(vid, 1, tonumber(val) * 255);
                    target_graphmode(vid, 0);
                } }.anon,
            },
        };
        for (color_labels, 0..) |v, k| {
            table.insert(res, .{
                .name = v[2],
                .label = v[3],
                .kind = "value",
                .hint = "(fr fg fb [br bg bb])(0..255)",
                .widget = "special:colorpick_r8g8b8",
                .description = v[4],
                .validator = suppl_valid_typestr("fff", 0, 255, 0),
                .handler = struct { fn anon(ctx: anytype, val: anytype) void {
                    var col = suppl_unpack_typestr("fff", val, 0, 255);
                    if (!valid_vid(vid, TYPE_FRAMESERVERR) or !col) {
                        return;
                    }
                    target_graphmode(vid, v[1], unpack(col));
                    target_graphmode(vid, 0, unpack(col));
                } }.anon,
            });
        }
        return res;
    } }.suppl_color_menu;

    var bdelim = ((tonumber("1,01") == null) and ".") or ",";
    var rdelim = ((bdelim == ".") and ",") or ".";

    const suppl_unpack_typestr = struct { pub fn suppl_unpack_typestr(typestr: anytype, val: anytype, lowv: i64, highv: i64) V {
        string.gsub(val, rdelim, bdelim);
        var rtbl = string.split(val, " ");
        for (1..(@intCast(rtbl.len)) + 1) |i| {
            rtbl[i] = tonumber(rtbl[i]);
            if (!rtbl[i]) {
                return;
            }
            if (lowv and (rtbl[i] < lowv)) {
                return;
            }
            if (highv and (rtbl[i] > highv)) {
                return;
            }
        }
        return rtbl;
    } }.suppl_unpack_typestr;

    const suppl_valid_name = struct { pub fn suppl_valid_name(val: anytype) bool {
        if (!string or (@intCast(val.len) == 0) or string.match(val, "%W")) {
            return false;
        }
        return true;
    } }.suppl_valid_name;

    const suppl_valid_vsymbol = struct { pub fn suppl_valid_vsymbol(val: anytype, base: anytype) V {
        if (!val) {
            return false;
        }
        if (string.len(val) == 0) {
            return false;
        }
        if (string.sub(val, 1, 3) == "0x_") {
            if (!val or !string.to_u8(string.sub(val, 4))) {
                return false;
            }
            val = string.to_u8(string.sub(val, 4));
        }
        if (string.sub(val, 1, 5) == "icon_") {
            val = string.sub(val, 6);
            if (icon_known(val)) {
                return __may_mv(true, struct { fn anon(w: anytype) V {
                    var vid = icon_lookup(val, w);
                    var props = image_surface_properties(vid);
                    var new = null_surface(props.width, props.height);
                    image_sharestorage(vid, new);
                    return new;
                } }.anon);
            }
            return false;
        }
        if (string.find(val, ":")) {
            return false;
        }
        return __may_mv(true, val);
    } }.suppl_valid_vsymbol;

    const append_color_menu = struct { fn append_color_menu(r: anytype, g: anytype, b: anytype, tbl: anytype, update_fun: anytype) void {
        tbl.kind = "value";
        tbl.widget = "special:colorpick_r8g8b8";
        tbl.hint = "(r g b)(0..255)";
        tbl.initial = string.format("%.0f %.0f %.0f", r, g, b);
        tbl.validator = suppl_valid_typestr("fff", 0, 255, 0);
        tbl.handler = struct { fn anon(ctx: anytype, val: anytype) void {
            var tbl = suppl_unpack_typestr("fff", val, 0, 255);
            if (!tbl) {
                return;
            }
            update_fun(string.format("\\#%02x%02x%02x", tbl[1], tbl[2], tbl[3]), tbl[1], tbl[2], tbl[3]);
        } }.anon;
    } }.append_color_menu;

    const suppl_hexstr_to_rgb = struct { pub fn suppl_hexstr_to_rgb(str: anytype) V {
        var base = undefined;

        if (!type(str) == "string") {
            str = "";
        }
        if (string.sub(str, 1, 1) == "#") {
            base = 2;
        } else if (string.sub(str, 2, 2) == "#") {
            base = 3;
        } else {
            base = 1;
        }
        var r = tonumber(string.sub(str, base + 0, base + 1), 16);
        var g = tonumber(string.sub(str, base + 2, base + 3), 16);
        var b = tonumber(string.sub(str, base + 4, base + 5), 16);

        r = (r and r) or 255;
        g = (g and g) or 255;
        b = (b and b) or 255;
        return __may_mv(r, g, b);
    } }.suppl_hexstr_to_rgb;

    const suppl_append_color_menu = struct { pub fn suppl_append_color_menu(v: anytype, tbl: anytype, update_fun: anytype) void {
        if (type(v) == "table") {
            append_color_menu(v[1], v[2], v[3], tbl, update_fun);
        } else {
            const r, const g, const b = suppl_hexstr_to_rgb(v);
            append_color_menu(r, g, b, tbl, update_fun);
        }
    } }.suppl_append_color_menu;

    const suppl_button_default_mh = struct { pub fn suppl_button_default_mh(wnd: anytype, cmd: anytype, altcmd: anytype) V {
        var res = .{
            .click = struct { fn anon(btn: anytype) void {
                dispatch_symbol_wnd(wnd, cmd);
            } }.anon,
            .over = struct { fn anon(btn: Obj) void {
                btn.switch_state("alert");
            } }.anon,
            .out = struct { fn anon(btn: Obj) void {
                btn.switch_state(((wnd.wm.selected == wnd) and "active") or "inactive");
            } }.anon,
        };
        if (altcmd) {
            res.rclick = struct { fn anon() void {
                dispatch_symbol_wnd(altcmd);
            } }.anon;
        }
        return res;
    } }.suppl_button_default_mh;

    const suppl_valid_typestr = struct { pub fn suppl_valid_typestr(utype: anytype, lowv: anytype, highv: anytype, defaultv: anytype) V {
        return struct { fn anon(val: anytype) bool {
            var tbl = suppl_unpack_typestr(utype, val, lowv, highv);
            if (tbl == null) {
                return false;
            }
            var vlen = string.sub(utype, -1) == "*";
            if (vlen) {
                return @intCast(tbl.len) >= string.len(utype - 1);
            } else {
                return @intCast(tbl.len) == string.len(utype);
            }
        } }.anon;
    } }.suppl_valid_typestr;

    const suppl_region_setup = struct { pub fn suppl_region_setup(x1: i64, y1: i64, x2: i64, y2: i64, nodef: anytype, static: anytype, title: anytype) V {
        var w = x2 - x1;
        var h = y2 - y1;

        var drt = active_display(true);
        var tiler = active_display();

        var i1 = pick_items(x1, y1, 1, true, drt);
        var i2 = pick_items(x2, y1, 1, true, drt);
        var i3 = pick_items(x1, y2, 1, true, drt);
        var i4 = pick_items(x2, y2, 1, true, drt);
        var img = drt;
        var in_float = (tiler.spaces[tiler.space_ind].mode == "float");

        if (in_float or (@intCast(i1.len) == 0) or (@intCast(i2.len) == 0) or (@intCast(i3.len) == 0) or (@intCast(i4.len) == 0) or (i1[1] != i2[1]) or (i1[1] != i3[1]) or (i1[1] != i4[1])) {
            rendertarget_forceupdate(drt);
        } else {
            img = i1[1];
        }
        const dvid, const grp = suppl_build_rt_reg(img, x1, y1, x2, y2);
        if (!valid_vid(dvid)) {
            return;
        }
        if (nodef) {
            return __may_mv(dvid, grp);
        }
        define_rendertarget(dvid, grp, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, (static and 0) or -1);
        if (static) {
            rendertarget_forceupdate(dvid);
            var dsrf = null_surface(w, h);
            image_sharestorage(dvid, dsrf);
            delete_image(dvid);
            show_image(dsrf);
            dvid = dsrf;
        }
        return __may_mv(dvid, grp, .{});
    } }.suppl_region_setup;

    var ptn_lut = .{
        .p = "prefix",
        .t = "title",
        .i = "ident",
        .a = "atype",
    };

    const get_ptn_str = struct { fn get_ptn_str(cb: anytype, wnd: anytype) V {
        if (string.len(cb) == 0) {
            return;
        }
        var field = ptn_lut[string.sub(cb, 1, 1)];
        if (!field or !wnd[field] or !(string.len(wnd[field]) > 0)) {
            return;
        }
        var len = tonumber(string.sub(cb, 2));
        return string.sub(wnd[field], 1, tonumber(string.sub(cb, 2)));
    } }.get_ptn_str;

    const suppl_ptn_expand = struct { pub fn suppl_ptn_expand(tbl: anytype, ptn: anytype, wnd: anytype) void {
        var set = string.split(ptn, " ");
        var prefix = "";
        for (set, 0..) |v, _| {
            if (string.sub(v, 1, 1) == "%") {
                var msg = get_ptn_str(string.sub(v, 2, 2), wnd);
                if (msg) {
                    table.insert(tbl, prefix ++ msg);
                    table.insert(tbl, "");
                }
                prefix = "";
            } else {
                prefix = prefix ++ v;
            }
        }
    } }.suppl_ptn_expand;

    const drop_keys = struct { pub fn drop_keys(matchstr: anytype) void {
        var rst = .{};
        for (match_keys(matchstr), 0..) |v, i| {
            const pos, const stop = string.find(v, "=", 1);
            var key = string.sub(v, 1, pos - 1);
            rst[key] = "";
        }
        store_key(rst);
    } }.drop_keys;

    string.utf8valid = struct { fn anon(str: anytype) V {
        const i, const len = .{ 1, @intCast(str.len) };
        var find = string.find;
        while (i <= len) {
            if (i == find(str, "[%z\x01-\x7f]", i)) {
                i = i + 1;
            } else if (i == find(str, "[Â-ß][{-¿]", i)) {
                i = i + 2;
            } else if ((i == find(str, "à[ -¿][€-¿]", i)) or (i == find(str, "[á-ì][€-¿][€-¿]", i)) or (i == find(str, "í[€-Ÿ][€-¿]", i)) or (i == find(str, "[î-ï][€-¿][€-¿]", i))) {
                i = i + 3;
            } else if ((i == find(str, "ð[-¿][€-¿][€-¿]", i)) or (i == find(str, "[ñ-ó][€-¿][€-¿][€-¿]", i)) or (i == find(str, "ô[€-][€-¿][€-¿]", i))) {
                i = i + 4;
            } else {
                return __may_mv(false, i);
            }
        }
        return true;
    } }.anon;

    const suppl_bind_u8 = struct { pub fn suppl_bind_u8(hook: anytype) void {
        var bwt = gconfig_get("bind_waittime");
        var tbhook = struct { fn anon(sym: anytype, done: bool, sym2: anytype, iotbl: anytype) void {
            if (!done) {
                return;
            }
            var bar = __may_method(active_display().lbar, struct { fn anon(ctx: anytype, instr: anytype, done: bool, lastv: anytype) V {
                if (!done) {
                    return instr and (string.len(instr) > 0) and (string.to_u8(instr) != null);
                }
                instr = string.to_u8(instr);
                if (instr and string.utf8valid(instr)) {
                    hook(sym, instr, sym2, iotbl);
                } else {
                    __may_method(active_display().message, "invalid utf-8 sequence specified");
                }
            } }.anon, ctx, .{ .label = "specify byte-sequence (like f0 9f 92 a9):" });
            suppl_widget_path(bar, bar.text_anchor, "special:u8");
        } }.anon;

        tiler_bbar(active_display(), string.format(LBL_BIND_COMBINATION, SYSTEM_KEYS["cancel"]), "keyorcombo", bwt, null, SYSTEM_KEYS["cancel"], tbhook);
    } }.suppl_bind_u8;

    const suppl_binding_helper = struct { pub fn suppl_binding_helper(prefix: anytype, suffix: anytype, bind_fn: anytype) V {
        var bwt = gconfig_get("bind_waittime");

        var on_input = struct { fn anon(sym: []const u8, done: bool) void {
            if (!done) {
                return;
            }
            var symname = prefix ++ (sym ++ suffix);
            dispatch_user_message("Pick a path or value to bind to " ++ symname);
            dispatch_symbol_bind(struct { fn anon(path: bool) void {
                dispatch_user_message("");
                if (!path) {
                    return;
                }
                bind_fn(symname, path);
            } }.anon);
        } }.anon;
        var bind_msg = string.format(LBL_BIND_COMBINATION_REP, SYSTEM_KEYS["cancel"]);

        var ctx = tiler_bbar(active_display(), bind_msg, false, gconfig_get("bind_waittime"), null, SYSTEM_KEYS["cancel"], on_input, gconfig_get("bind_repeat"));

        var lbsz = 2 * active_display().scalef * gconfig_get("lbar_sz");

        suppl_widget_path(ctx, ctx.bar, "special:custom", lbsz);
        return ctx;
    } }.suppl_binding_helper;

    var binding_queue = .{};
    const suppl_binding_queue = struct { pub fn suppl_binding_queue(arg: anytype) void {
        if (type(arg) == "function") {
            table.insert(binding_queue, arg);
        } else if (arg) {
            binding_queue = .{};
        } else {
            var ent = table.remove(binding_queue, 1);
            if (ent) {
                ent();
            }
        }
    } }.suppl_binding_queue;

    const text_input_table = struct { fn text_input_table(ctx: Obj, io: anytype, sym: anytype) V {
        if (!io.active) {
            return;
        }
        if (sym and ctx.bindings[sym]) {
            ctx.bindings[sym](ctx);
            return;
        }
        var keych = io.utf8;
        if (keych == null) {
            return ctx;
        }
        ctx.oldmsg = ctx.msg;
        ctx.oldpos = ctx.caretpos;
        ctx.msg, nch = string.insert(ctx.msg, keych, ctx.caretpos, ctx.nchars);
        ctx.caretpos = ctx.caretpos + nch;
        ctx.update_caret();
    } }.text_input_table;

    const text_input_view = struct { fn text_input_view(ctx: anytype) V {
        var rofs = math.floor(string.utf8ralign(ctx.msg, ctx.chofs + ctx.ulim));
        var lofs = math.floor(string.utf8ralign(ctx.msg, ctx.chofs));
        var str = string.sub(ctx.msg, lofs, rofs - 1);
        return str;
    } }.text_input_view;

    const text_input_caret_str = struct { fn text_input_caret_str(ctx: anytype) V {
        return string.sub(ctx.msg, math.floor(ctx.chofs), math.floor(ctx.caretpos) - 1);
    } }.text_input_caret_str;

    const text_input_undo = struct { fn text_input_undo(ctx: anytype) void {
        if (ctx.oldmsg) {
            ctx.msg = ctx.oldmsg;
            ctx.caretpos = ctx.oldpos;
        }
    } }.text_input_undo;

    const text_input_set = struct { fn text_input_set(ctx: Obj, str: anytype) void {
        ctx.msg = ((str and (@intCast(str.len) > 0)) and str) or "";
        ctx.caretpos = string.len(ctx.msg) + 1;
        ctx.chofs = ctx.caretpos - ctx.ulim;
        ctx.chofs = ((ctx.chofs < 1) and 1) or ctx.chofs;
        ctx.chofs = string.utf8lalign(ctx.msg, ctx.chofs);
        ctx.update_caret();
    } }.text_input_set;

    const text_input_caretalign = struct { fn text_input_caretalign(ctx: Obj) void {
        if ((ctx.caretpos - ctx.chofs + 1) > ctx.ulim) {
            ctx.chofs = string.utf8lalign(ctx.msg, ctx.caretpos - ctx.ulim);
        }
        ctx.draw();
    } }.text_input_caretalign;

    const text_input_chome = struct { fn text_input_chome(ctx: Obj) void {
        ctx.caretpos = 1;
        ctx.chofs = 1;
        ctx.update_caret();
    } }.text_input_chome;

    const text_input_cend = struct { fn text_input_cend(ctx: Obj) void {
        ctx.caretpos = string.len(ctx.msg) + 1;
        ctx.chofs = ctx.caretpos - ctx.ulim;
        ctx.chofs = ((ctx.chofs < 1) and 1) or ctx.chofs;
        ctx.chofs = string.utf8lalign(ctx.msg, ctx.chofs);
        ctx.update_caret();
    } }.text_input_cend;

    const text_input_cleft = struct { fn text_input_cleft(ctx: Obj) void {
        ctx.caretpos = string.utf8back(ctx.msg, ctx.caretpos);
        if (ctx.caretpos < ctx.chofs) {
            ctx.chofs = ctx.chofs - ctx.ulim;
            ctx.chofs = ((ctx.chofs < 1) and 1) or ctx.chofs;
            ctx.chofs = string.utf8lalign(ctx.msg, ctx.chofs);
        }
        ctx.update_caret();
    } }.text_input_cleft;

    const text_input_cright = struct { fn text_input_cright(ctx: Obj) void {
        ctx.caretpos = string.utf8forward(ctx.msg, ctx.caretpos);
        if ((ctx.chofs + ctx.ulim) <= ctx.caretpos) {
            ctx.chofs = ctx.chofs + 1;
        }
        ctx.update_caret();
    } }.text_input_cright;

    const text_input_cdel = struct { fn text_input_cdel(ctx: Obj) void {
        ctx.msg = string.delete_at(ctx.msg, ctx.caretpos);
        ctx.update_caret();
    } }.text_input_cdel;

    const text_input_cerase = struct { fn text_input_cerase(ctx: Obj) void {
        if (ctx.caretpos < 1) {
            return;
        }
        ctx.caretpos = string.utf8back(ctx.msg, ctx.caretpos);
        if (ctx.caretpos <= ctx.chofs) {
            ctx.chofs = ctx.caretpos - ctx.ulim;
            ctx.chofs = ((ctx.chofs < 0) and 1) or ctx.chofs;
        }
        ctx.msg = string.delete_at(ctx.msg, ctx.caretpos);
        ctx.update_caret();
    } }.text_input_cerase;

    const text_input_clear = struct { fn text_input_clear(ctx: Obj) void {
        ctx.caretpos = 1;
        ctx.msg = "";
        ctx.update_caret();
    } }.text_input_clear;

    const suppl_text_input = struct { pub fn suppl_text_input(ctx: Obj, iotbl: anytype, sym: anytype, redraw: anytype, opts: anytype) V {
        ctx = ((ctx == null) and .{
            .caretpos = 1,
            .limit = -1,
            .chofs = 1,
            .ulim = VRESW / gconfig_get("font_sz"),
            .msg = "",
            .draw = (redraw and redraw) or struct { fn anon() void {
            } }.anon,
            .view_str = text_input_view,
            .caret_str = text_input_caret_str,
            .set_str = text_input_set,
            .update_caret = text_input_caretalign,
            .caret_home = text_input_chome,
            .caret_end = text_input_cend,
            .caret_left = text_input_cleft,
            .caret_right = text_input_cright,
            .erase = text_input_cerase,
            .delete = text_input_cdel,
            .clear = text_input_clear,
            .undo = text_input_undo,
            .input = text_input_table,
        }) or ctx;
        var bindings = .{
            .k_left = "LEFT",
            .k_right = "RIGHT",
            .k_home = "HOME",
            .k_end = "END",
            .k_delete = "DELETE",
            .k_erase = "ERASE",
            .k_context = "TAB",
        };

        var flut = .{
            .k_left = text_input_cleft,
            .k_right = text_input_cright,
            .k_home = text_input_chome,
            .k_end = text_input_cend,
            .k_delete = text_input_cdel,
            .k_erase = text_input_cerase,
            .k_context = struct { fn anon() void {
            } }.anon,
        };

        if (opts.bindings) {
            for (pairs(opts.bindings)) |__may_pair| {
                const k = __may_pair[0];
                const v = __may_pair[1];
                if (bindings[k]) {
                    bindings[k] = v;
                }
            }
        }
        ctx.bindings = .{};
        for (pairs(bindings)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            ctx.bindings[v] = flut[k];
        }
        ctx.input(iotbl, sym);
        return ctx;
    } }.suppl_text_input;

    const gen_valid_float = struct { pub fn gen_valid_float(lb: anytype, ub: anytype) V {
        return gen_valid_num(lb, ub);
    } }.gen_valid_float;

    const merge_dispatch = struct { pub fn merge_dispatch(m1: anytype, m2: anytype) V {
        var kt = .{};
        var res = .{};
        if (m1 == null) {
            return m2;
        }
        if (m2 == null) {
            return m1;
        }
        for (pairs(m1)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            res[k] = v;
        }
        for (pairs(m2)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            res[k] = v;
        }
        return res;
    } }.merge_dispatch;

    const shared_valid_str = struct { pub fn shared_valid_str(inv: anytype) bool {
        return (type(inv) == "string") and (@intCast(inv.len) > 0);
    } }.shared_valid_str;

    const shared_valid01_float = struct { pub fn shared_valid01_float(inv: anytype) V {
        if (string.len(inv) == 0) {
            return true;
        }
        var val = tonumber(inv);
        return (val and ((val >= 0.0) and (val <= 1.0))) or false;
    } }.shared_valid01_float;

    const gen_valid_num = struct { pub fn gen_valid_num(lb: i64, ub: i64, step: anytype) V {
        var range = ub - lb;
        var step_sz = ((step != null) and step) or (range * 0.01);

        return struct { fn anon(val: bool) V {
            if (!val) {
                warning("validator activated with missing val");
                return __may_mv(false, lb, ub, step_sz);
            }
            if (string.len(val) == 0) {
                return __may_mv(false, lb, ub, step_sz);
            }
            var num = tonumber(val);
            if (num == null) {
                return __may_mv(false, lb, ub, step_sz);
            }
            return __may_mv(!((num < lb) or (num > ub)), lb, ub, step_sz);
        } }.anon;
    } }.gen_valid_num;

    var widgets = .{};

    const suppl_flip_handler = struct { pub fn suppl_flip_handler(key: anytype, chain: anytype) V {
        return struct { fn anon(ctx: anytype, val: anytype) void {
            if (val == LBL_FLIP) {
                gconfig_set(key, !gconfig_get(key));
            } else {
                gconfig_set(key, val == LBL_YES);
            }
            if (chain) {
                chain(gconfig_get(key) == LBL_YES);
            }
        } }.anon;
    } }.suppl_flip_handler;

    const suppl_script_load = struct { pub fn suppl_script_load(@"fn": anytype, logfn: anytype) V {
        var res = system_load(@"fn", false);
        logfn = (logfn and logfn) or warning;
        if (!res) {
            logfn(string.format("couldn't parse/load script: %s", @"fn"));
        } else {
            const okstate, const msg = pcall(res);
            if (!okstate) {
                logfn(string.format("script (%s) error: %s", @"fn", msg));
            } else {
                return msg;
            }
        }
    } }.suppl_script_load;

    var tool_closures = .{};
    const suppl_tools_register_closure = struct { pub fn suppl_tools_register_closure(handler: anytype) void {
        if (type(handler) == "function") {
            table.insert(tool_closures, handler);
        }
    } }.suppl_tools_register_closure;

    const suppl_scan_tools = struct { pub fn suppl_scan_tools() void {
        for (tool_closures, 0..) |v, _| {
            pcall(v);
        }
        tool_closures = .{};
        var list = glob_resource("tools/*.lua", APPL_RESOURCE);
        for (list, 0..) |v, k| {
            suppl_script_load("tools/" ++ v, warning);
        }
    } }.suppl_scan_tools;

    const suppl_chain_callback = struct { pub fn suppl_chain_callback(tbl: anytype, field: anytype, new: anytype) void {
        var old = tbl[field];
        tbl[field] = struct { fn anon(va: anytype) void {
            if (new) {
                new(va);
            }
            if (old) {
                tbl[field] = old;
                old(va);
            }
        } }.anon;
    } }.suppl_chain_callback;

    const suppl_scan_widgets = struct { pub fn suppl_scan_widgets() void {
        var res = glob_resource("widgets/*.lua", APPL_RESOURCE);
        for (res, 0..) |v, k| {
            var res = system_load("widgets/" ++ v, false);
            if (res) {
                const ok, const wtbl = pcall(res);

                if (ok and wtbl and wtbl.name and (type(wtbl.name) == "string") and (string.len(wtbl.name) > 0) and wtbl.paths and (type(wtbl.paths) == "table")) {
                    widgets[wtbl.name] = wtbl;
                } else {
                    warning("widget " ++ (v ++ " failed to load"));
                }
            } else {
                warning("widget " ++ (v ++ "f failed to parse"));
            }
        }
    } }.suppl_scan_widgets;

    var widget_destr = .{};
    const suppl_widget_path = struct { pub fn suppl_widget_path(ctx: anytype, anchor: anytype, ident: anytype, barh: bool) void {
        var match = .{};
        var fi = 0;

        for (pairs(widget_destr)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            __may_method(k.destroy);
        }
        widget_destr = .{};
        var props = image_surface_resolve_properties(anchor);
        var y1 = props.y;
        var y2 = props.y + props.height;
        var ad = active_display();
        var th = math.ceil(gconfig_get("lbar_sz") * active_display().scalef);
        var rh = y1 - th;

        for (pairs(widgets)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            for (v.paths, 0..) |j, i| {
                var ident_tag = undefined;
                if (type(j) == "function") {
                    ident_tag = j(v, ident);
                }
                if (((type(j) == "string") and (j == ident)) or ident_tag) {
                    var nc = (v.probe and __may_method(v.probe, rh, ident_tag)) or 1;

                    if (nc > 0) {
                        widget_destr[v] = true;
                        for (1..nc + 1) |n| {
                            table.insert(match, .{
                                v,
                                n,
                            });
                        }
                    }
                }
            }
        }
        var nm = @intCast(match.len);
        if (nm == 0) {
            return;
        }
        var pad = 0;

        var start = fi + 1;
        var ctr = 0;

        if ((nm - fi) > 0) {
            var ndiv = (@intCast(match.len) - fi) / 2;
            var cellw = ((ndiv > 1) and ((ad.width - pad - pad) / ndiv)) or ad.width;
            var cx = pad;
            while (start <= nm) {
                ctr = ctr + 1;
                var anch = null_surface(cellw, rh);
                link_image(anch, anchor);
                var dy = 0;

                if (gconfig_get("menu_helper") and !barh and ((ctr % 2) == 1)) {
                    dy = th;
                }
                show_image(anch);
                image_inherit_order(anch, true);
                image_mask_set(anch, MASK_UNPICKABLE);
                const w, const h = __may_method(match[start][1].show, anch, match[start][2], rh);
                start = start + 1;
                if (w and h) {
                    if ((ctr % 2) == 1) {
                        move_image(anch, cx, -h - dy);
                    } else {
                        move_image(anch, cx, props.height + dy + th);
                        cx = cx + cellw;
                    }
                } else {
                    delete_image(anch);
                }
            }
        }
    } }.suppl_widget_path;

    var prefixes = .{};
    const suppl_add_logfn = struct { pub fn suppl_add_logfn(prefix: anytype) V {
        if (prefixes[prefix]) {
            return __may_mv(prefixes[prefix][1], prefixes[prefix][2]);
        }
        var logscope = struct { fn anon() void {
            var queue = .{};
            var handler = null;

            prefixes[prefix] = .{
                struct { fn anon(msg: []const u8) void {
                    var exp_msg = CLOCK ++ (":" ++ (msg ++ "\n"));
                    if (handler) {
                        handler(exp_msg);
                    } else {
                        table.insert(queue, exp_msg);
                        if (@intCast(queue.len) > 200) {
                            table.remove(queue, 1);
                        }
                    }
                } }.anon,
                string.format,
            };
            _G[prefix ++ "_debug_listener"] = struct { fn anon(newh: anytype) void {
                if (newh and (type(newh) == "function")) {
                    handler = newh;
                    for (queue, 0..) |v, i| {
                        newh(v);
                    }
                } else {
                    handler = null;
                }
                queue = .{};
            } }.anon;
        } }.anon;
        logscope();
        return __may_mv(prefixes[prefix][1], prefixes[prefix][2]);
    } }.suppl_add_logfn;

    var color_cache = .{};
    const suppl_tgt_loadcolor = struct { pub fn suppl_tgt_loadcolor(cmap: []const u8) V {
        var tbl = .{};
        if (type(cmap) == "string") {
            if (!color_cache[cmap]) {
                tbl = suppl_script_load("devmaps/colorschemes/" ++ (cmap ++ ".lua"), false);
                if (type(tbl) == "table") {
                    color_cache[cmap] = tbl;
                } else {
                    tbl = null;
                }
            }
            tbl = color_cache[cmap];
        } else {
            tbl = cmap;
        }
        return tbl;
    } }.suppl_tgt_loadcolor;

    const suppl_tgt_color = struct { pub fn suppl_tgt_color(vid: anytype, cmap: anytype) void {
        assert(valid_vid(vid), "invalid vid to suppl_color");
        tbl = suppl_tgt_loadcolor(cmap);
        if (!tbl) {
            return;
        }
        for (1..36 + 1) |i| {
            var v = tbl[i];
            if (v and (@intCast(v.len) > 0)) {
                target_graphmode(vid, i + 1, v[1], v[2], v[3]);
                if (@intCast(v.len) == 6) {
                    target_graphmode(vid, bit.bor(i + 1, 256), v[4], v[5], v[6]);
                }
            }
        }
        target_graphmode(vid, 0);
    } }.suppl_tgt_color;

    var logtbl = .{};
    const suppl_log_intercept = struct { pub fn suppl_log_intercept(name: anytype) void {
        logtbl[name] = _G[name];
        _G[name] = struct { fn anon(va: anytype) void {
            print(debug.traceback());
            logtbl[name](va);
        } }.anon;
    } }.suppl_log_intercept;

    const suppl_display_ui_pad = struct { pub fn suppl_display_ui_pad() V {
        var disp = active_display(false, true);
        var hw = math.ceil(gconfig_get("font_sz") * 0.352778 * disp.ppcm / 20);
        return hw;
    } }.suppl_display_ui_pad;

    const fuzzy_dist = struct { fn fuzzy_dist(instr: anytype, val: bool) V {
        if (!val) {
            return math.huge;
        }
        var dist = 0;
        var last_pos = 0;
        var i = string.utf8forward(instr, 0);
        while (i <= @intCast(instr.len)) {
            var next_i = string.utf8forward(instr, i);
            var ch = string.lower(string.sub(instr, i, next_i - 1));
            const ok, const msg = pcall(string.find, string.lower(val), ch, last_pos + 1);
            if (!ok or !pos) {
                break;
            }
            dist = dist + (pos - last_pos);
            last_pos = pos;
            i = next_i;
        }
        return dist;
    } }.fuzzy_dist;

    const suppl_sort_az_nat = struct { pub fn suppl_sort_az_nat(a: anytype, b: anytype) bool {
        a = ((type(a) == "table") and a[3]) or a;
        b = ((type(b) == "table") and b[3]) or b;
        const s_a, const e_a = string.find(a, "%d+");
        const s_b, const e_b = string.find(b, "%d+");

        if ((s_a != null) and (s_b != null) and (s_a == s_b)) {
            var p_a = string.sub(a, 1, s_a - 1);
            var p_b = string.sub(b, 1, s_b - 1);

            if (p_a == p_b) {
                return tonumber(string.sub(a, s_a, e_a)) < tonumber(string.sub(b, s_b, e_b));
            }
        }
        return string.lower(a) < string.lower(b);
    } }.suppl_sort_az_nat;

    const suppl_sort_fuzzy = struct { pub fn suppl_sort_fuzzy(instr: anytype) V {
        return struct { fn anon(a: anytype, b: anytype) bool {
            return fuzzy_dist(instr, ((type(a) == "table") and a[3]) or a) < fuzzy_dist(instr, ((type(b) == "table") and b[3]) or b);
        } }.anon;
    } }.suppl_sort_fuzzy;

    const suppl_terminal_build_argenv = struct { pub fn suppl_terminal_build_argenv(group: anytype) V {
        var bc = gconfig_get("term_bgcol");
        var fc = gconfig_get("term_fgcol");
        var cp = (group and group) or gconfig_get("extcon_path");
        var palette = gconfig_get("term_palette");
        var cursor = gconfig_get("term_cursor");
        var blink = gconfig_get("term_blink");
        var interp = gconfig_get("term_interp");

        var lstr = string.format("%scursor=%s:interp=%s:blink=%s:bgalpha=%d:bgr=%d:bgg=%d:bgb=%d:fgr=%d:fgg=%d:fgb=%d:%s%s%s", (gconfig_get("term_tpack") and "tpack:") or "", cursor, interp, blink, gconfig_get("term_opa") * 255.0, bc[1], bc[2], bc[3], fc[1], fc[2], fc[3], ((cp and (string.len(cp) > 0)) and ("env=ARCAN_CONNPATH=" ++ cp)) or "", ((string.len(palette) > 0) and (":palette=" ++ palette)) or "", gconfig_get("term_append_arg"));

        if (gconfig_get("term_bitmap")) {
            lstr = lstr ++ (":" ++ "force_bitmap");
        }
        return lstr;
    } }.suppl_terminal_build_argenv;
}
