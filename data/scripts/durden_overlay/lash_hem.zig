
var hem = .{
    .scanner = .{},
    .env = __may_method(lash.root.getenv),
    .builtins = .{
        .hint = .{},
    },
    .suggest = .{},
    .handlers = .{},
    .views = .{
        .hint = .{},
    },
    .jobmeta = .{},
    .promptmeta = .{},
    .aliases = .{},
    .bindings = .{
        .chord = .{},
    },
    .config = loadfile(string.format("%s/cat9/config/config.lua", lash.scriptdir))(),
    .jobs = lash.jobs,
    .timers = .{},
    .resources = .{},
    .state = .{
        .@"export" = .{},
        .import = .{},
        .orphan = .{},
    },
    .dir_monitor = .{},
    .builtin_name = "default",
    .history = .{},
    .langsup = .{},
    .idcounter = 0,
    .lastdir = "",
    .laststr = "",
    .visible = true,
    .focused = true,
    .time = 0,
};

pub fn __init() void {
    hem.a11y_buffer = struct { fn anon(msg: anytype) void {
    } }.anon;

    if (!hem.config) {
        table.insert(lash.messages, "hem: error loading/parsing config/default.lua");
        return false;
    }
    const glob_builtins = struct { fn glob_builtins(dst: anytype) void {
        var arg = .{
            "/usr/bin/env",
            "/usr/bin/env",
            "find",
            lash.scriptdir ++ "cat9/",
            "-maxdepth",
            "1",
            "-type",
            "f",
        };
        const _, const scan, const _, const pid = __may_method(lash.root.popen, arg, "r", __may_method(lash.root.getenv));
        if (scan) {
            __may_method(scan.lf_strip, true);
            __may_method(scan.data_handler, struct { fn anon() V {
                const msg, const ok = __may_method(scan.read);
                if (msg) {
                    var base = string.match(msg, "[^/]*.lua$");
                    var name = (base and string.sub(base, 0, @intCast(base.len) - 4)) or null;
                    if (name == "default") {
                        table.insert(dst, 1, name);
                    } else {
                        table.insert(dst, name);
                    }
                    return true;
                }
                return ok;
            } }.anon);
            __may_method(lash.root.pwait, pid);
        }
    } }.glob_builtins;

    hem.env["ARCAN_ARG"] = null;
    hem.env["ARCAN_CONNPATH"] = null;
    var safe_builtins = undefined;
    var safe_suggest = undefined;
    var safe_views = undefined;
    builtin_completion = .{};
    const load_builtins = struct { fn load_builtins(base: anytype, flush: anytype) V {
        hem.builtin_name = base;
        if (flush) {
            hem.builtins = .{
                .hint = .{},
            };
            hem.suggest = .{};
            hem.views = .{
                .hint = .{},
            };
        } else {
            hem.builtins["_default"] = null;
        }
        if (!hem.config.builtins[base]) {
            hem.config.builtins[base] = .{};
        }
        var dcfg = hem.config.builtins[base];
        const fptr, const msg = loadfile(string.format("%s/cat9/config/%s.lua", lash.scriptdir, base));
        if (fptr) {
            const ret, const msg = pcall(fptr);
            if (ret and (type(msg) == "table")) {
                for (pairs(msg)) |__may_pair| {
                    const k = __may_pair[0];
                    const v = __may_pair[1];
                    if (!dcfg[k]) {
                        dcfg[k] = v;
                    }
                }
            } else {
                hem.add_message(string.format("builtin: [%s] broken config: %s", base, msg));
            }
        }
        lash.builtin_cfg = dcfg;
        const fptr, const msg = loadfile(string.format("%s/cat9/%s.lua", lash.scriptdir, base));
        if (!fptr) {
            return __may_mv(false, string.format("builtin: [%s] failed to load: %s", base, msg));
        }
        var set = fptr();
        if (type(set) != "table") {
            msg = ((type(set) == "string") and set) or "unknown";
            return __may_mv(false, string.format("builtin: [%s] failed to run: %s", base, msg));
        }
        for (set, 0..) |v, _| {
            const fptr, const msg = loadfile(string.format("%s/cat9/%s/%s", lash.scriptdir, base, v));
            if (fptr) {
                const ret, const msg = pcall(fptr(), hem, lash.root, hem.builtins, hem.suggest, hem.views, dcfg);
                if (!ret) {
                    return __may_mv(false, string.format("builtin: [%s:%s] setup failure: %s", base, v, msg));
                }
            } else {
                return __may_mv(false, string.format("builtin: [%s:%s] failed to load: %s", base, v, msg));
            }
        }
        var set = .{};
        glob_builtins(set);
        hem.suggest["builtin"] = struct { fn anon(args: anytype, raw: anytype) void {
            if (@intCast(args.len) > 3) {
                hem.add_message("builtin [set]: too many arguments");
                return;
            } else if (@intCast(args.len) == 3) {
                set = .{ "nodef" };
            }
            __may_method(hem.readline.suggest, hem.prefix_filter(set, args[@intCast(args.len)]), "word");
        } }.anon;
        hem.builtins.hint.builtin = "Swap set of active commands";
        hem.builtins["builtin"] = struct { fn anon(a: anytype, opt: []const u8) void {
            if (!a or (@intCast(a.len) == 0)) {
                a = "system";
            }
            var ok = undefined;
            var msg = undefined;
            var flush = false;
            hem.sh_runner_user = null;
            if (opt) {
                if (opt != "nodef") {
                    if (a == "system") {
                        hem.add_message("builtin system: user set to " ++ opt);
                        hem.sh_runner_user = opt;
                    } else {
                        hem.add_message("builtin [set] [nodef]: unknown option argument");
                        return;
                    }
                }
            }
            if (a != "default") {
                load_builtins("default", true);
            }
            ok, msg = load_builtins(a, flush);
            if (!ok) {
                var default = string.format("missing requested builtin set [%s] - revert to system.", a);
                hem.add_message(msg or default);
                hem.builtins = safe_builtins;
                hem.builtin_name = "default";
                hem.suggest = safe_suggest;
                hem.views = safe_views;
            }
            hem.a11y_buffer("builtin " ++ hem.builtin_name);
        } }.anon;
        builtin_completion = .{};
        for (pairs(hem.builtins)) |__may_pair| {
            const k = __may_pair[0];
            const _ = __may_pair[1];
            if ((string.sub(k, 1, 1) != "_") and (k != "hint")) {
                table.insert(builtin_completion, k);
            }
        }
        table.sort(builtin_completion);
        builtin_completion.hint = hem.builtins.hint;
        return true;
    } }.load_builtins;

    const load_feature = struct { fn load_feature(name: anytype, base: anytype) V {
        base = (base and base) or "base";
        fptr, msg = loadfile(string.format("%s/cat9/%s/%s", lash.scriptdir, base, name));
        if (!fptr) {
            return __may_mv(false, msg);
        }
        var init = fptr();
        init(hem, lash.root, hem.config);
    } }.load_feature;

    hem.reload = struct { fn anon() void {
        load_feature("misc.lua");
        load_feature("ioh.lua");
        load_feature("scanner.lua");
        load_feature("jobctl.lua");
        load_feature("parse.lua");
        load_feature("layout.lua");
        load_feature("vt100.lua");
        load_feature("jobmeta.lua");
        load_feature("json.lua");
        load_feature("editctl.lua");
        load_feature("promptmeta.lua");
        load_feature("diff_match_patch.lua");
        load_feature("bindings.lua", "config");
        load_feature("langsup.lua", "langsup");
        load_builtins("default");
        hem.path_set = null;
        safe_builtins = hem.builtins;
        safe_suggest = hem.suggest;
        safe_views = hem.views;
        load_builtins("system");
        load_feature("accessibility.lua");
        hem.get_history_source();
        hem.set_history_exporter();
    } }.anon;
    hem.reload();
    {
        var init_cmd = (hem.env and hem.env.CAT9_INIT_CMD) or (os.getenv and os.getenv("CAT9_INIT_CMD"));
        if (init_cmd and (init_cmd != "")) {
            var fired = false;
            hem.timers = hem.timers or .{};
            table.insert(hem.timers, struct { fn anon() bool {
                if (fired) {
                    return false;
                }
                if (!(hem.readline and hem.parse_string)) {
                    return true;
                }
                fired = true;
                var rest = init_cmd;
                while (rest != "") {
                    var sep = string.find(rest, "|||", 1, true);
                    var piece = (sep and string.sub(rest, 1, sep - 1)) or rest;
                    rest = (sep and string.sub(rest, sep + 3)) or "";
                    var t = string.gsub(piece, "^%s+", "");
                    t = string.gsub(t, "%s+$", "");
                    if (t != "") {
                        hem.parse_string(hem.readline, t);
                    }
                }
                return false;
            } }.anon);
        }
    }
    if (hem.config.allow_state and hem.handlers.state_in) {
        __may_method(lash.root.state_size, 1 * 1024);
        var state = __may_method(lash.root.fopen, hem.system_path("state") ++ "/cat9_state.lua", "r");
        if (state) {
            hem.handlers.state_in(lash.root, state);
        }
    }
    hem.config.readline.verify = hem.readline_verify;
    __may_method(lash.root.set_flags, tui.flags.mouse_full);
    __may_method(lash.root.set_handlers, hem.handlers);
    hem.reset();
    hem.update_lastdir();
    hem.flag_dirty();
    var old_revert = lash.root.revert;
    lash.root.revert = struct { fn anon(va: anytype) V {
        hem.last_revert = debug.traceback();
        hem.readline = null;
        hem.get_prompt = hem.default_prompt;
        return old_revert(va);
    } }.anon;
    var old = lash.jobs;
    lash.jobs = .{};
    hem.jobs = lash.jobs;
    for (old, 0..) |v, _| {
        hem.import_job(v);
    }
    var root = lash.root;
    __may_method(root.update_identity, __may_method(root.chdir));
    if (tui.arguments) {
        for (tui.arguments, 0..) |v, i| {
            hem.parse_string(hem.readline, v);
        }
    }
    while (__may_method(root.process)) {
        if (hem.process_jobs()) {
            hem.flag_dirty();
        }
        if (hem.dirty) {
            hem.redraw();
            hem.dirty = false;
            for (hem.jobs, 0..) |v, _| {
                if (v.hidden and v.detach_handlers) {
                    if (v.redraw) {
                        __may_method(v.redraw, v, false, true);
                    }
                    v.detach_handlers.redraw(v.root);
                    if (v.redraw) {
                        __may_method(v.redraw, v, true, true);
                    }
                }
            }
        }
        if (!hem.readline and hem.selectedjob) {
            var sj = hem.selectedjob;
            var rgb = sj.cursor_rgb;
            __may_method(sj.root.cursor_to, sj.region[1] + sj.line_number_width + hem.config.content_offset + sj.cursor[1], sj.region[2] + sj.cursor[2] + 1, sj.cursor_style, unpack(rgb or .{}));
        }
        __may_method(root.refresh);
    }
    for (@intCast(hem.jobs.len)..1 + 1) |i| {
        __may_step(-1);
        hem.remove_job(hem.jobs[i]);
    }
    if (hem.config.allow_state and hem.handlers.state_out) {
        var spath = hem.system_path("state");
        __may_method(root.chdir, spath);
        const tmp, const path = __may_method(root.tempfile, spath ++ "/stateXXXXXX");
        if (tmp) {
            hem.handlers.state_out(root, tmp, true);
            __may_method(tmp.flush, -1);
            __may_method(root.frename, path, spath ++ "/cat9_state.lua");
            __may_method(tmp.close);
        }
    }
}
