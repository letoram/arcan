
var glob_cache = .{};

var last_path = "/browse/shared";
pub fn browse_get_last() V {
    return last_path;
}

fn open_image(wnd: anytype, name: anytype, @"fn": anytype) void {
    if (wnd.load_pending) {
        delete_image(wnd.load_pending);
    }
    load_image_asynch(@"fn", struct { fn anon(src: anytype, stat: anytype) void {
        if (stat.kind == "loaded") {
            __may_method(wnd.set_title, name);
            image_sharestorage(src, wnd.canvas);
            delete_image(src);
            __may_method(wnd.resize_effective, stat.width, stat.height);
        }
    } }.anon);
}

pub fn browse_load_decode(arg: anytype, in_file_tag: anytype, in_file: anytype) V {
    return struct { fn anon(wnd: anytype, name: anytype, @"fn": anytype) void {
        var aid = undefined;
        wnd.pending_vid, aid = launch_decode(@"fn", arg, struct { fn anon(source: anytype, status: anytype) void {
            if (status.kind == "terminated") {
                delete_image(source);
                if (wnd.pending_vid == source) {
                    wnd.pending_vid = null;
                }
            } else if (status.kind == "bchunkstate") {
                open_nonblock(source, false, in_file_tag, in_file);
            } else if (status.kind == "preroll") {
                target_displayhint(source, wnd.width, wnd.height, wnd.dispmask, __may_method(wnd.displaytable, wnd, wnd.wm.disptbl));
            } else if (status.kind == "resized") {
                if (valid_vid(wnd.external)) {
                    delete_image(wnd.external);
                }
                wnd.external = source;
                image_sharestorage(source, wnd.canvas);
                audio_gain(aid, gconfig_get("global_gain") * wnd.gain);
                target_updatehandler(source, extevh_default);
                extevh_default(source, status);
            }
        } }.anon);
    } }.anon;
}

fn get_related_menu(wnd: anytype, set: anytype, loader: anytype) V {
    var res = .{};
    if (!wnd.destroy) {
        return res;
    }
    const get_name = struct { fn get_name(v: anytype) V {
        v = string.split(v, "/");
        return v[@intCast(v.len)];
    } }.get_name;

    var step_menu = .{
        .{
            .name = "first",
            .label = "First",
            .description = "Switch to the first item in the list",
            .kind = "action",
            .handler = struct { fn anon() void {
                loader(wnd, get_name(set[1].file), set[1].file);
            } }.anon,
        },
        .{
            .name = "last",
            .label = "Last",
            .description = "Switch to the last item in the list",
            .kind = "action",
            .handler = struct { fn anon() void {
                loader(wnd, get_name(set[@intCast(set.len)].file), set[@intCast(set.len)].file);
            } }.anon,
        },
        .{
            .name = "next",
            .label = "Next",
            .description = "Switch to the next item in the list",
            .kind = "action",
            .handler = struct { fn anon() void {
                wnd.list_index = wnd.list_index + 1;
                if (wnd.list_index > @intCast(wnd.file_set.len)) {
                    wnd.list_index = 1;
                }
                loader(wnd, get_name(set[wnd.list_index].file), set[wnd.list_index].file);
            } }.anon,
        },
        .{
            .name = "previous",
            .label = "Previous",
            .description = "Switch to the previous item in the list",
            .kind = "action",
            .handler = struct { fn anon() void {
                wnd.list_index = wnd.list_index - 1;
                if (wnd.list_index <= 0) {
                    wnd.list_index = @intCast(wnd.file_set.len);
                }
                loader(wnd, get_name(set[wnd.list_index].file), set[wnd.list_index].file);
            } }.anon,
        },
        .{
            .name = "random",
            .label = "Random",
            .description = "Switch to a random item in the list",
            .kind = "action",
            .handler = struct { fn anon() void {
                var start = math.random(1, @intCast(set.len));
                var current = start;
                while (true) {
                    if (!set[current].visited) {
                        break;
                    }
                    current = current + 1;
                    if (current > @intCast(set.len)) {
                        current = 1;
                    }
                    if (current == start) break;
                }

                if (current == start) {
                    for (1..(@intCast(set.len)) + 1) |i| {
                        set[i].visited = null;
                    }
                }
                set[current].visited = true;
                wnd.list_index = current;
                loader(wnd, get_name(set[wnd.list_index].file), set[wnd.list_index].file);
            } }.anon,
        },
    };
    table.insert(res, .{
        .name = "step",
        .kind = "action",
        .label = "Step",
        .description = "Controls for stepping the playlist",
        .submenu = true,
        .handler = step_menu,
    });
    for (set, 0..) |v, i| {
        var name = get_name(v.name);
        table.insert(res, .{
            .name = tostring(i),
            .label = name,
            .kind = "action",
            .handler = struct { fn anon() void {
                loader(wnd, name, v);
            } }.anon,
        });
    }
    return res;
}

fn make_playlist(wnd: anytype, @"fn": anytype, tracker: anytype, loader: anytype) void {
    var name = string.split(@"fn", "/");
    name = name[@intCast(name.len)];
    wnd.full_path = @"fn";
    wnd.file_set = tracker;
    table.sort(tracker, struct { fn anon(a: anytype, b: anytype) V {
        return suppl_sort_az_nat(a.file, b.file);
    } }.anon);
    wnd.list_index = table.find_i(tracker, @"fn") or 1;
    wnd.actions = .{
        .{
            .name = "playlist",
            .kind = "action",
            .description = "Select or step related media",
            .submenu = true,
            .label = "Playlist",
            .eval = struct { fn anon() bool {
                return @intCast(tracker.len) > 1;
            } }.anon,
            .handler = struct { fn anon() V {
                return get_related_menu(wnd, tracker, loader);
            } }.anon,
        },
    };
}

fn imgwnd(@"fn": anytype, pctx: anytype, tracker: anytype) void {
    load_image_asynch(@"fn", struct { fn anon(src: anytype, stat: anytype) void {
        if (stat.kind == "loaded") {
            wnd = __may_method(active_display().add_window, src, .{ .scalemode = "aspect" });
            extevh_apply_atype(wnd, "multimedia", src, .{});
            make_playlist(wnd, @"fn", tracker, open_image);
            __may_method(wnd.set_title, "image:" ++ @"fn");
        } else if (valid_vid(src)) {
            delete_image(src);
            __may_method(active_display().message, "couldn't load " ++ @"fn");
        }
    } }.anon);
}

fn pdfwnd(@"fn": anytype, path: anytype, tracker: anytype) void {
    lastpath = path;
    var vid = launch_decode(@"fn", "protocol=pdf", struct { fn anon(s: anytype, st: anytype) void {
    } }.anon);

    if (valid_vid(vid)) {
        var wnd = durian_launch(vid, "", @"fn");
        make_playlist(wnd, @"fn", tracker, browse_load_decode("protocol=pdf"));
        durian_devicehint(vid);
    } else {
        __may_method(active_display().message, "decode- frameserver broken or out-of-resources");
    }
}

fn decwnd(@"fn": anytype, path: anytype, tracker: anytype) void {
    lastpath = path;
    var vid = launch_decode(@"fn", struct { fn anon(s: anytype, st: anytype) void {
    } }.anon);

    if (valid_vid(vid)) {
        var wnd = durian_launch(vid, "", @"fn");
        make_playlist(wnd, @"fn", tracker, browse_load_decode(""));
        durian_devicehint(vid);
    } else {
        __may_method(active_display().message, "decode- frameserver broken or out-of-resources");
    }
}

fn setup_preview(state: anytype, dst: anytype) void {
    var w = state.last_w;
    var ofs = state.last_ofs;
    var sel = state.selected;
    var old_vid = state.vid;

    if (!valid_vid(old_vid)) {
        delete_image(dst);
        return;
    }
    state.vid = dst;
    const parent, const attachment = image_parent(old_vid);
    if (valid_vid(parent)) {
        link_image(dst, parent);
    }
    image_inherit_order(dst, true);
    delete_image(old_vid);
    var opa = (sel and 1.0) or 0.3;
    var time = gconfig_get("animation");
    if (!valid_vid(dst)) {
        return;
    }
    resize_image(dst, w, 0);
    var props = image_surface_properties(dst);
    resize_image(dst, 8, 8);
    move_image(dst, ofs + w * 0.5, 0);
    resize_image(dst, w, 0, time);
    blend_image(dst, opa, time);
    nudge_image(dst, -w * 0.5, -props.height, time);
}

fn asynch_decode(state: anytype, self: anytype, append: anytype) void {
    if (!valid_vid(state.vid)) {
        return;
    }
    var cmd = append;
    if (!cmd) {
        cmd = string.format("pos=%f:noaudio:loop", gconfig_get("browser_position") * 0.01);
        cmd = string.gsub(cmd, ",", ".");
    }
    var vid = launch_decode(self.preview_path, cmd, struct { fn anon(source: anytype, status: anytype) void {
        if ((status.kind == "resized") and state.in_asynch) {
            setup_preview(state, source);
            state.in_asynch = false;
        } else if (status.kind == "terminated") {
            delete_image(source);
        }
    } }.anon);

    if (valid_vid(vid)) {
        link_image(vid, state.vid);
    }
}

fn asynch_pdf(state: anytype, self: anytype) V {
    return asynch_decode(state, self, "proto=pdf");
}

fn open_image(state: anytype, self: anytype) void {
    load_image_asynch(self.preview_path, struct { fn anon(source: anytype, status: anytype) void {
        if ((type(status) == "table") and (status.kind == "loaded")) {
            setup_preview(state, source);
            state.in_asynch = false;
            self.last_state = state;
        } else if ((type(status) == "table") and (status.kind == "load_failed")) {
            delete_image(source);
        }
    } }.anon);
}

fn update_preview(state: anytype, active: bool, xofs: anytype, width: anytype, index: anytype) void {
    if (active == null) {
        if (valid_vid(state.vid)) {
            delete_image(state.vid);
        }
        return;
    }
    if (valid_vid(state.vid)) {
        instant_image_transform(state.vid);
        move_image(state.vid, xofs, -image_surface_properties(state.vid).height);
    }
    if (active == false) {
        if (valid_vid(state.vid) and !state.in_asynch) {
            blend_image(state.vid, 0.3, gconfig_get("animation"));
        }
        state.selected = false;
        return;
    }
    if (valid_vid(state.vid) and !state.in_asynch) {
        blend_image(state.vid, 1.0, gconfig_get("animation"));
    }
    state.selected = true;
    state.last_w = width;
    state.last_ofs = xofs;
    state.last_index = index;
}

fn prepare_preview(callback: anytype, self: anytype, anchor: anytype, ofs: anytype, width: anytype, index: anytype) V {
    var state = .{
        .in_asynch = true,
        .last_ofs = ofs,
        .last_w = width,
        .selected = true,
        .menu = self,
        .last_index = index,
        .vid = null_surface(1, 1),
    };

    if (!valid_vid(state.vid)) {
        return .{
            .update = struct { fn anon() void {
            } }.anon,
        };
    }
    link_image(state.vid, anchor);
    image_inherit_order(state.vid, true);
    var mh = .{
        .own = struct { fn anon(ctx: anytype, vid: anytype) bool {
            return vid == state.vid;
        } }.anon,
        .over = struct { fn anon(ctx: anytype, vid: anytype) void {
        } }.anon,
    };
    mouse_addlistener(mh);
    __may_method(tiler_lbar_isactive(true).append_mh, mh);
    var cnt = gconfig_get("browser_timer");
    if (cnt > 0) {
        timer_add_periodic("_preview_" ++ tostring(ofs), cnt, true, struct { fn anon() void {
            callback(state, self);
        } }.anon, true);
    } else {
        callback(state, self);
    }
    state.update = update_preview;
    return state;
}

var handlers = .{
    __may_kv("image", .{
        .run = imgwnd,
        .col = HC_PALETTE[1],
        .selcol = HC_PALETTE[1],
        .preview = struct { fn anon(va: anytype) V {
            if (gconfig_get("browser_preview") == "none") {
                return;
            }
            return prepare_preview(open_image, va);
        } }.anon,
    }),
    __may_kv("audio", .{
        .run = decwnd,
        .col = HC_PALETTE[2],
        .selcol = HC_PALETTE[2],
    }),
    __may_kv("pdf", .{
        .run = pdfwnd,
        .col = HC_PALETTE[4],
        .selcol = HC_PALETTE[4],
        .preview = struct { fn anon(va: anytype) V {
            if (gconfig_get("browser_preview") == "none") {
                return;
            }
            return prepare_preview(asynch_pdf, va);
        } }.anon,
    }),
    __may_kv("video", .{
        .run = decwnd,
        .col = HC_PALETTE[3],
        .selcol = HC_PALETTE[3],
        .preview = struct { fn anon(va: anytype) V {
            if (gconfig_get("browser_preview") == "none") {
                return;
            }
            return prepare_preview(asynch_decode, va);
        } }.anon,
    }),
};

var alth = null;
pub fn browse_override_ext(v: anytype) void {
    var fake_entry = .{
        .run = struct { fn anon() void {
        } }.anon,
        .col = HC_PALETTE[4],
        .selcol = HC_PALETTE[4],
    };
    if (!v) {
        alth = null;
    } else if (v == "*") {
        alth = struct { fn anon(simple: anytype, ext: anytype) V {
            if (handlers[simple]) {
                return handlers[simple];
            } else {
                return fake_entry;
            }
        } }.anon;
    } else {
        alth = struct { fn anon(simple: anytype, ext: anytype) V {
            if (ext == v) {
                if (handlers[simple]) {
                    return handlers[simple];
                } else {
                    return fake_entry;
                }
            }
        } }.anon;
    }
}

fn cursortag(@"fn": anytype) void {
    var ms = mouse_state();
    var ct = ms.cursortag;
    if (ct) {
        if (ct.ref != "browser") {
            __may_method(active_display().cancellation);
            ct = null;
        }
    }
    const fontstr, const _ = __may_method(active_display().font_resfn);
    if (!ct) {
        var tag = render_text(.{
            fontstr,
            "Placeholder",
        });
        show_image(tag);
        mouse_cursortag("browser", .{}, struct { fn anon(dst: anytype, accept: bool, src: anytype) V {
            if (accept == null) {
                return dst and valid_vid(dst.external, TYPE_FRAMESERVER);
            } else if (accept == false) {
                for (src, 0..) |v, _| {
                    __may_method(v.nbio.close);
                }
            } else {
                for (src, 0..) |v, _| {
                    var nbio = open_nonblock(v.path, false);
                    var id = string.split(v.path, "/");
                    id = string.sub(id[@intCast(id.len)], -76);
                    if (nbio) {
                        open_nonblock(dst.external, false, id, nbio);
                    } else {
                        warning("browse: couldn't open " ++ v.path);
                    }
                }
            }
        } }.anon, tag);
        ct = ms.cursortag;
    }
    if (!table.find_key_i(ct.src, "path", @"fn")) {
        table.insert(ct.src, .{ .path = @"fn" });
        var suffix = ((@intCast(ct.src.len) > 1) and " Files") or " File";
        render_text(ct.vid, .{
            fontstr,
            tostring(@intCast(ct.src.len)) ++ suffix,
        });
    }
}

var gen_menu_for_path = undefined;
fn gen_menu_for_resource(path: []const u8, v: []const u8, descr: []const u8, prefix: anytype, ns: []const u8, tracker: anytype) V {
    var fqn = path ++ ((((path == "/") and "") or "/") ++ v);
    var nsfqn = fqn;

    if (type(ns) == "string") {
        nsfqn = ns ++ (":/" ++ fqn);
    }
    if (descr == "directory") {
        return .{
            .label = v,
            .name = v,
            .kind = "action",
            .description = v,
            .submenu = true,
            .handler = struct { fn anon() V {
                return gen_menu_for_path(fqn, prefix, ns, tracker);
            } }.anon,
        };
    } else if (descr == "file") {
        const simple, const ext = suppl_ext_type(v);

        if (!ext or (@intCast(ext.len) == 0)) {
        }
        var exth = (alth and alth(simple, ext)) or handlers[simple];

        if (!exth) {
            return;
        }
        if (!tracker[simple]) {
            tracker[simple] = .{};
        }
        table.insert(tracker[simple], .{ .file = nsfqn });
        var res = .{
            .label = v,
            .name = v,
            .description = v,
            .format = exth.col,
            .select_format = exth.selcol,
            .kind = "action",
            .preview = exth.preview,
            .preview_path = nsfqn,
        };

        res.alt_handler = struct { fn anon(ctx: anytype) V {
            const x, const y = mouse_xy();
            var menu = .{
                .{
                    .name = "window",
                    .kind = "action",
                    .label = "Open as Window",
                    .handler = struct { fn anon() void {
                        exth.run(nsfqn, res.last_state, tracker[simple]);
                    } }.anon,
                },
                .{
                    .name = "tag",
                    .kind = "action",
                    .label = "Add to Cursortag",
                    .handler = struct { fn anon() void {
                        cursortag(nsfqn);
                    } }.anon,
                },
            };
            return menu;
        } }.anon;
        res.handler = struct { fn anon(ctx: anytype) void {
            exth.run(nsfqn, res.last_state, tracker[simple]);
        } }.anon;
        return res;
    } else {
    }
}

pub fn __init() void {
    gen_menu_for_path = struct { fn anon(path: []const u8, prefix: []const u8, ns: []const u8) V {
        var files = glob_resource(path, ns);
        var tracker = .{};

        var res = .{};

        for (files, 0..) |v, i| {
            if ((v != ".") and (v != "..")) {
                var descr = undefined;
                if (type(ns) == "string") {
                    _, descr = resource(ns ++ (":/" ++ (path ++ ("/" ++ v))));
                } else {
                    _, descr = resource(path ++ ("/" ++ v), ns);
                }
                if (descr) {
                    var menu = gen_menu_for_resource(path, v, descr, prefix, ns, tracker);
                    if (menu) {
                        table.insert(res, menu);
                    }
                }
            }
        }
        table.insert(res, .{
            .label = ".",
            .name = "refresh",
            .kind = "action",
            .alias = prefix ++ path,
            .interactive = true,
            .handler = struct { fn anon() void {
                glob_cache[path] = null;
            } }.anon,
        });
        res.alt_handler = struct { fn anon() V {
            var res = .{
                .{
                    .name = "media",
                    .label = "Media",
                    .kind = "action",
                    .handler = struct { fn anon() void {
                        print("set filter to media");
                    } }.anon,
                },
                .{
                    .name = "all_files",
                    .label = "All Files",
                    .kind = "action",
                    .handler = struct { fn anon() void {
                        print("set filter to all files");
                    } }.anon,
                },
            };
            return res;
        } }.anon;
        last_path = prefix ++ path;
        return res;
    } }.anon;
    return struct { fn anon() V {
        var res = .{
            .{
                .name = "shared",
                .label = "Shared",
                .kind = "action",
                .submenu = true,
                .description = "The shared resources namespace",
                .handler = struct { fn anon() V {
                    return gen_menu_for_path("", "/browse/shared", SHARED_RESOURCE);
                } }.anon,
            },
            .{
                .name = "durian",
                .label = "Durian",
                .kind = "action",
                .description = "Durian generated output",
                .submenu = true,
                .handler = struct { fn anon() V {
                    return gen_menu_for_path("output", "/browse/durian", APPL_TEMP_RESOURCE);
                } }.anon,
            },
            .{
                .label = "Last",
                .name = "last",
                .description = "Return to the last visited browse/ path",
                .kind = "action",
                .alias = struct { fn anon() V {
                    return last_path;
                } }.anon,
                .handler = struct { fn anon() void {
                } }.anon,
            },
        };

        if (list_namespaces) {
            for (list_namespaces(), 0..) |v, _| {
                table.insert(res, .{
                    .label = v.label,
                    .name = v.name,
                    .kind = "action",
                    .submenu = true,
                    .handler = struct { fn anon() V {
                        return gen_menu_for_path("", "/browse/" ++ v.name, v.name);
                    } }.anon,
                });
            }
        }
        return res;
    } }.anon;
}
