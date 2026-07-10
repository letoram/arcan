
pub fn __init() void {
    if (type(gconfig_set) == "function") {
        var orig_gset = gconfig_set;
        gconfig_set = struct { fn anon(key: anytype, val: anytype, force: anytype) void {
            orig_gset(key, val, force);
            if ((type(val) != "function") and (type(val) != "table")) {
                store_key(key, tostring(val));
            }
        } }.anon;
    }
    if (type(dispatch_set) == "function") {
        var _old_clock = _G[APPLID ++ "_clock_pulse"];
        _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) void {
            if (_old_clock) {
                _old_clock(va);
            }
            if (!_G.__lash_bind_done) {
                _G.__lash_bind_done = true;
                dispatch_set("m1_m2_RETURN", "/global/open/lash");
                dispatch_set("m1_m2_b", "/global/open/lash");
                if (type(gconfig_set) == "function") {
                    gconfig_set("meta_lock", "none");
                }
                if (type(shmifmon) == "function") {
                    shmifmon("durian:launch:bugs_open=see_fossil");
                }
            }
        } }.anon;
    }
    if ((type(menus_register) == "function") and !_G.__sysdebug_menu_registered) {
        _G.__sysdebug_menu_registered = true;
        menus_register("global", "open", .{
            .name = "sysdebug",
            .label = "Sysdebug",
            .description = "Companion to Mellstrand & Stahl's Systemic " ++ "Software Debugging, applied to this stack (LWA appl)",
            .kind = "action",
            .handler = struct { fn anon(ctx: anytype) void {
                if (type(spawn_terminal) != "function") {
                    warning("sysdebug menu: spawn_terminal not defined");
                    return;
                }
                spawn_terminal("exec=/home/x/next/arcan/zig-out/bin/arcan sysdebug");
            } }.anon,
        });
    }
    if (type(shmifmon) != "function") {
        return;
    }
    shmifmon("autorun:loaded");
    var watched = .{
        "preroll",
        "registered",
        "resized",
        "terminated",
        "segment_request",
        "viewport",
        "ident",
        "message",
        "bchunkstate",
        "alert",
    };
    if (type(extevh_default) == "function") {
        var orig = extevh_default;
        extevh_default = struct { fn anon(source: anytype, stat: anytype) void {
            var kind = (stat and stat.kind) or "?";
            var watch = false;
            for (watched, 0..) |w, _| {
                if (w == kind) {
                    watch = true;
                    break;
                }
            }
            if (watch) {
                var extra = "";
                if ((kind == "message") and stat and stat.message) {
                    var m: Obj = tostring(stat.message);
                    var chain: Obj = m.match("^%[sysdebug%.spawn%-cell%] entry=%d+ verbbox=%d+ chain=(.+)$");
                    if (chain and (type(spawn_terminal) == "function")) {
                        var lash_base = "/home/x/next/arcan/zig-out/share/arcan/appl/durian/lash";
                        var cmd = "cli=lua:env=LASH_SHELL=cat9:env=LASH_BASE=" ++ (lash_base ++ (":env=CAT9_INIT_CMD=" ++ chain));
                        const ok, const err = pcall(spawn_terminal, cmd);
                        shmifmon(string.format("sysdebug:spawn-cell:dispatched:ok=%s:chain=%s", tostring(ok), chain.sub(1, 80)));
                        if (!ok) {
                            warning("sysdebug spawn-cell failed: " ++ tostring(err));
                        }
                    }
                    m = m.gsub("[\r\n]", " ");
                    extra = ":message=" ++ m;
                } else if ((kind == "segment_request") and stat) {
                    extra = string.format(":segkind=%s:hint=%s:reqid=%s", tostring(stat.segkind), tostring(stat.split_dir or stat.position or stat.hint), tostring(stat.reqid));
                } else if ((kind == "bchunkstate") and stat) {
                    extra = string.format(":input=%s:disable=%s:size=%s", tostring(stat.input), tostring(stat.disable), tostring(stat.size));
                }
                shmifmon(string.format("extevh_default:enter:kind=%s:source=%s%s", kind, tostring(source), extra));
            }
            const ok, const err = pcall(orig, source, stat);
            if (watch) {
                shmifmon(string.format("extevh_default:exit:kind=%s:ok=%s:err=%s", kind, tostring(ok), tostring(err)));
            }
            if (!ok) {
                warning("extevh_default raised: " ++ tostring(err));
            }
        } }.anon;
        shmifmon("autorun:extevh_default:wrapped");
    } else {
        shmifmon("autorun:extevh_default:missing");
    }
    if (type(durian_launch) == "function") {
        var orig_dl = durian_launch;
        durian_launch = struct { fn anon(vid: anytype, prefix: anytype, title: anytype, wnd: anytype, wargs: anytype) V {
            shmifmon(string.format("durian_launch:enter:vid=%s:title=%s", tostring(vid), tostring(title)));
            const ok, const out = pcall(orig_dl, vid, prefix, title, wnd, wargs);
            shmifmon(string.format("durian_launch:exit:vid=%s:ok=%s:out=%s", tostring(vid), tostring(ok), tostring(out)));
            if (!ok) {
                warning("durian_launch raised: " ++ tostring(out));
                return null;
            }
            return out;
        } }.anon;
        shmifmon("autorun:durian_launch:wrapped");
    }
}
