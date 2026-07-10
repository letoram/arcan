
pub fn __init() void {
    return struct { fn anon(hem: anytype, root: anytype, config: anytype) void {
        var lastmsg = undefined;
        hem.url_ptn = struct { fn anon() []const u8 {
            return "https?://(([%w_.~!*:@&+$/?%%#-]-)(%w[-.%w]*%.)(%w%w%w?%w?)(:?)(%d*)(/?)([%w_.~!*:@&+$/?%%#=-]*))";
        } }.anon;

        hem.each_ch = struct { fn anon(str: anytype, cb: anytype, err: anytype, pos: anytype, dir: anytype) V {
            var u8_step = root.utf8_step;
            var dir = dir or 1;
            err = err or struct { fn anon() void {
            } }.anon;
            if (pos) {
                pos = u8_step(str, pos);
                if (pos == -1) {
                    err(str, pos);
                    return;
                }
            } else {
                pos = 1;
            }
            while (true) {
                const nextch, const ch = u8_step(str, dir, pos);
                if (nextch == -1) {
                    if (nextch < @intCast(str.len)) {
                        err(str, pos);
                    }
                    return;
                }
                if (nextch < pos) {
                    if (cb(string.sub(str, nextch, pos - 1), nextch)) {
                        break;
                    }
                } else {
                    if (cb(string.sub(str, pos, nextch - 1), pos)) {
                        break;
                    }
                }
                pos = nextch;
            }
            return pos;
        } }.anon;

        hem.remove_match = struct { fn anon(tbl: anytype, ent: anytype) V {
            for (tbl, 0..) |v, i| {
                if (v == ent) {
                    table.remove(tbl, i);
                    return __may_mv(true, i);
                }
            }
        } }.anon;

        table.find_key_i = struct { fn anon(table: anytype, field: anytype, r: anytype) V {
            for (table, 0..) |v, k| {
                if (v[field] == r) {
                    return __may_mv(k, v);
                }
            }
        } }.anon;

        table.find_i = struct { fn anon(table: anytype, r: anytype) V {
            for (table, 0..) |v, k| {
                if (v == r) {
                    return __may_mv(k, table[k]);
                }
            }
        } }.anon;

        table.copy_recursive = struct { fn anon(tbl: anytype) V {
            var res = .{};
            for (pairs(tbl)) |__may_pair| {
                const k = __may_pair[0];
                const v = __may_pair[1];
                if (type(v) == "table") {
                    res[k] = table.copy_recursive(v);
                } else {
                    res[k] = v;
                }
            }
            return res;
        } }.anon;

        table.equal = struct { fn anon(tbl1: bool, tbl2: bool) bool {
            if (!tbl1 or !tbl2) {
                return false;
            }
            if (@intCast(tbl1.len) != @intCast(tbl2.len)) {
                return false;
            }
            for (tbl1, 0..) |v, i| {
                if (v != tbl2[i]) {
                    return false;
                }
            }
            return true;
        } }.anon;

        string.fit_to_length = struct { fn anon(str: anytype, cap: i64, lpad: anytype, ofs: anytype) V {
            var left = cap;
            var out = "";
            ofs = ofs or 0;
            if (cap == 0) {
                return str;
            }
            hem.each_ch(str, struct { fn anon(ch: []const u8) bool {
                if (ofs > 0) {
                    ofs = ofs - 1;
                } else {
                    out = out ++ ch;
                    left = left - 1;
                }
                return left == 0;
            } }.anon, struct { fn anon() void {
            } }.anon);
            if (left > 0) {
                if (lpad) {
                    return string.rep(" ", left) ++ out;
                } else {
                    return out ++ string.rep(" ", left);
                }
            }
            return out;
        } }.anon;

        if (!string.unpack_shmif_argstr) {
            string.unpack_shmif_argstr = struct { fn anon(a1: anytype, a2: anytype) V {
                var arg = undefined;
                var res = undefined;
                if (type(a1) == "table") {
                    res = a1;
                    arg = a2;
                } else {
                    arg = a1;
                    res = .{};
                }
                if ((type(arg) != "string") or (@intCast(arg.len) == 0)) {
                    return res;
                }
                var entries = string.split(arg, ":");
                for (entries, 0..) |v, _| {
                    var elem = string.split(v, "=");
                    if (elem and elem[1] and (@intCast(elem[1].len) > 0)) {
                        if (@intCast(elem.len) == 1) {
                            res[elem[1]] = true;
                        } else if (@intCast(elem.len) == 2) {
                            res[elem[1]] = string.gsub(elem[2], "\t", ":");
                        }
                    }
                }
                return res;
            } }.anon;
        }
        if (!string.split_first) {
            string.split_first = struct { fn anon(instr: bool, delim: anytype) V {
                if (!instr) {
                    return;
                }
                const delim_pos, const delim_stp = string.find(instr, delim, 1);
                if (delim_pos) {
                    var first = string.sub(instr, 1, delim_pos - 1);
                    var rest = string.sub(instr, delim_stp + 1);
                    first = (first and first) or "";
                    rest = (rest and rest) or "";
                    return __may_mv(first, rest);
                } else {
                    return __may_mv("", instr);
                }
            } }.anon;
        }
        if (!string.lpad) {
            string.lpad = struct { fn anon(instr: []const u8, digits: i64) []const u8 {
                if (@intCast(instr.len) < digits) {
                    return string.rep(" ", digits - @intCast(instr.len)) ++ instr;
                }
                return instr;
            } }.anon;
        }
        hem.compact_path = struct { fn anon(str: anytype, lastcap: anytype) V {
            var set = string.split(str, "/");
            var compact = .{};
            for (1..(@intCast(set.len)) + 1) |i| {
                if (i < @intCast(set.len)) {
                    var next = root.utf8_step(set[i], 1, 1);
                    table.insert(compact, ((next == -1) and set[i]) or string.sub(set[i], 1, next));
                } else {
                    table.insert(compact, set[i]);
                }
            }
            return table.concat(compact, "/");
        } }.anon;

        math.clamp = struct { fn anon(num: i64, low: i64, high: i64) i64 {
            if (low and (num < low)) {
                return low;
            } else if (high and (num > high)) {
                return high;
            } else {
                return num;
            }
        } }.anon;

        hem.modifier_string = struct { fn anon(mod: anytype) V {
            var str = "";
            if (bit.band(mod, tui.modifiers.SHIFT) > 0) {
                str = str ++ "shift_";
            }
            if (bit.band(mod, tui.modifiers.CTRL) > 0) {
                str = str ++ "ctrl_";
            }
            if (bit.band(mod, tui.modifiers.ALT) > 0) {
                str = str ++ "alt_";
            }
            if (bit.band(mod, tui.modifiers.META) > 0) {
                str = str ++ "meta_";
            }
            return str;
        } }.anon;

        hem.system_path = struct { fn anon(ns: anytype) V {
            var base = lash.scriptdir ++ "/state";
            if (hem.env["XDG_STATE_HOME"]) {
                base = hem.env["XDG_STATE_HOME"];
            }
            return base;
        } }.anon;

        hem.run_in_dir = struct { fn anon(root: Obj, dir: anytype, cb: anytype) void {
            var old = root.chdir();
            root.chdir(dir);
            cb();
            root.chdir(old);
        } }.anon;

        hem.chdir = struct { fn anon(step: anytype) void {
            hem.prevdir = __may_method(root.chdir);
            __may_method(root.chdir, step);
            if (step) {
                var new = __may_method(root.chdir);
                if (new != hem.prevdir) {
                    for (pairs(hem.dir_monitor)) |__may_pair| {
                        const k = __may_pair[0];
                        const v = __may_pair[1];
                        v(new, hem.prevdir);
                    }
                    __may_method(root.update_identity, new);
                }
            }
            hem.scanner_path = null;
            hem.update_lastdir();
        } }.anon;

        hem.update_lastdir = struct { fn anon() void {
            var wd = __may_method(root.chdir);
            var dirs = string.split(wd, "/");
            var dir = "/";
            if (@intCast(dirs.len)) {
                hem.lastdir = dirs[@intCast(dirs.len)];
            }
        } }.anon;

        hem.build_tmpjob_files = struct { fn anon(args: anytype, dispatch: anytype, fail: anytype) V {
            var files = .{};
            var names = .{};
            const closure = struct { fn closure() void {
                for (names, 0..) |v, _| {
                    __may_method(root.funlink, v);
                }
                for (files, 0..) |v, _| {
                    __may_method(v.close);
                }
            } }.closure;

            for (args, 0..) |v, _| {
                if ((type(v) == "table") and v.slice) {
                    const tpath, const file = __may_method(root.tempfile);
                    if (file) {
                        table.insert(files, file);
                        table.insert(names, tpath);
                    } else {
                        hem.add_message("build tmp-job: couldn't create temporary storage");
                        return closure();
                    }
                }
            }
            if (@intCast(files.len) == 0) {
                return;
            }
            var pending = 0;
            var failed = 0;
            var ok = 0;
            var writeh = struct { fn anon(oob: anytype, finish_ok: anytype) void {
                if (finish_ok) {
                    ok = ok + 1;
                } else {
                    failed = failed + 1;
                }
                if ((failed + ok) == pending) {
                    if (failed > 0) {
                        fail();
                    } else {
                        dispatch();
                    }
                }
            } }.anon;
            for (args, 0..) |v, i| {
                if ((type(v) == "table") and v.slice) {
                    pending = pending + 1;
                    __may_method(files[pos].write, __may_method(v.slice), writeh);
                }
            }
            return closure;
        } }.anon;

        hem.add_message = struct { fn anon(msg: Obj) void {
            if (!msg) {
                lastmsg = "";
            } else if (type(msg) != "string") {
                print("add_message(" ++ (type(msg) ++ (")" ++ debug.traceback())));
            } else {
                lastmsg = msg;
                if (@intCast(lastmsg.len) > 0) {
                    hem.a11y_buffer(msg);
                }
            }
            if (msg and (type(msg) == "string") and lash and lash.root) {
                var s: Obj = msg.gsub("[\r\n]", " ");
                if (@intCast(s.len) > 200) {
                    s = s.sub(1, 200);
                }
                pcall(struct { fn anon() void {
                    __may_method(lash.root.message, "hem:msg:" ++ s);
                } }.anon);
            }
        } }.anon;

        hem.get_message = struct { fn anon(dequeue: anytype) V {
            var old = lastmsg;
            if (dequeue) {
                lastmsg = null;
            }
            return old;
        } }.anon;

        hem.opt_number = struct { fn anon(set: anytype, ind: anytype, default: anytype) V {
            var num = set[ind] and tonumber(set[ind]);
            return (num and num) or default;
        } }.anon;

        hem.run_lut = struct { fn anon(cmd: anytype, tgt: anytype, lut: anytype, set: anytype) void {
            var i = 1;
            while (i and (i <= @intCast(set.len))) {
                var opt = set[i];
                if (type(opt) != "string") {
                    lastmsg = string.format("%s >...< %d argument invalid", cmd, i);
                    return;
                }
                if (!lut[opt]) {
                    i = i + 1;
                } else {
                    i = lut[opt](set, i, tgt);
                }
            }
        } }.anon;

        var maptype = .{
            .s = tostring,
            .n = tonumber,
            .b = struct { fn anon(v: bool) bool {
                return v == true;
            } }.anon,
        };
        hem.stableb64 = struct { fn anon(tbl: anytype) V {
            var res = .{};
            var typemap = .{
                __may_kv("string", "s"),
                __may_kv("boolean", "b"),
                __may_kv("number", "n"),
            };
            for (pairs(tbl)) |__may_pair| {
                const k = __may_pair[0];
                const v = __may_pair[1];
                var kt = typemap[type(k)];
                var vt = typemap[type(v)];
                if (kt and vt) {
                    table.insert(res, hem.to_b64(kt ++ (vt ++ tostring(k))));
                    table.insert(res, hem.to_b64(tostring(v)));
                }
            }
            return table.concat(res, ":");
        } }.anon;

        hem.b64stable = struct { fn anon(str: anytype) V {
            var sub = string.split(str, ":");
            var deq = table.remove;
            var res = .{};
            while (@intCast(sub.len) > 0) {
                var key = hem.from_b64(deq(sub, 1));
                var val = hem.from_b64(deq(sub, 1));
                if (key) {
                    var kt = string.sub(key, 1, 1);
                    var vt = string.sub(key, 2, 2);
                    key = string.sub(key, 3);
                    if (key and val and maptype[kt] and maptype[vt]) {
                        res[maptype[kt](key)] = maptype[vt](val);
                    }
                }
            }
            return res;
        } }.anon;

        const extract = struct { fn extract(v: anytype, from: anytype, width: anytype) V {
            return bit.band(bit.rshift(v, from), bit.lshift(1, width) - 1);
        } }.extract;

        var b64enc = .{};
        var b64dec = .{};
        for (pairs(.{
            __may_kv(0, "A"),
            "B",
            "C",
            "D",
            "E",
            "F",
            "G",
            "H",
            "I",
            "J",
            "K",
            "L",
            "M",
            "N",
            "O",
            "P",
            "Q",
            "R",
            "S",
            "T",
            "U",
            "V",
            "W",
            "X",
            "Y",
            "Z",
            "a",
            "b",
            "c",
            "d",
            "e",
            "f",
            "g",
            "h",
            "i",
            "j",
            "k",
            "l",
            "m",
            "n",
            "o",
            "p",
            "q",
            "r",
            "s",
            "t",
            "u",
            "v",
            "w",
            "x",
            "y",
            "z",
            "0",
            "1",
            "2",
            "3",
            "4",
            "5",
            "6",
            "7",
            "8",
            "9",
            "+",
            "/",
            "=",
        })) |__may_pair| {
            const b64 = __may_pair[0];
            const ch = __may_pair[1];
            b64enc[b64] = __may_method(ch.byte);
        }
        for (pairs(b64enc)) |__may_pair| {
            const b64 = __may_pair[0];
            const char = __may_pair[1];
            b64dec[char] = b64;
        }
        hem.to_b64 = struct { fn anon(str: Obj) V {
            const char, const concat = .{ string.char, table.concat };
            var encoder = b64enc;
            const t, const k, const n = .{ .{}, 1, @intCast(str.len) };
            var lastn = n % 3;
            for (1..(n - lastn) + 1) |i| {
                __may_step(3);
                const a, const b, const c = str.byte(i, i + 2);
                var v = a * 0x10000 + b * 0x100 + c;
                var s = undefined;
                s = char(encoder[extract(v, 18, 6)], encoder[extract(v, 12, 6)], encoder[extract(v, 6, 6)], encoder[extract(v, 0, 6)]);
                t[k] = s;
                k = k + 1;
            }
            if (lastn == 2) {
                const a, const b = str.byte(n - 1, n);
                var v = a * 0x10000 + b * 0x100;
                t[k] = char(encoder[extract(v, 18, 6)], encoder[extract(v, 12, 6)], encoder[extract(v, 6, 6)], encoder[64]);
            } else if (lastn == 1) {
                var v = str.byte(n) * 0x10000;
                t[k] = char(encoder[extract(v, 18, 6)], encoder[extract(v, 12, 6)], encoder[64], encoder[64]);
            }
            return concat(t);
        } }.anon;

        hem.from_b64 = struct { fn anon(b64: Obj) V {
            const char, const concat = .{ string.char, table.concat };
            var decoder = b64dec;
            var pattern = "[^%w%+%/%=]";
            b64 = b64.gsub(pattern, "");
            const t, const k = .{ .{}, 1 };
            var n = @intCast(b64.len);
            var padding = ((b64.sub(-2) == "==") and 2) or ((b64.sub(-1) == "=") and 1) or 0;
            for (1..(((padding > 0) and (n - 4)) or n) + 1) |i| {
                __may_step(4);
                const a, const b, const c, const d = b64.byte(i, i + 3);
                var s = undefined;
                var v = decoder[a] * 0x40000 + decoder[b] * 0x1000 + decoder[c] * 0x40 + decoder[d];
                s = char(extract(v, 16, 8), extract(v, 8, 8), extract(v, 0, 8));
                t[k] = s;
                k = k + 1;
            }
            if (padding == 1) {
                const a, const b, const c = b64.byte(n - 3, n - 1);
                var v = decoder[a] * 0x40000 + decoder[b] * 0x1000 + decoder[c] * 0x40;
                t[k] = char(extract(v, 16, 8), extract(v, 8, 8));
            } else if (padding == 2) {
                const a, const b = b64.byte(n - 3, n - 2);
                var v = decoder[a] * 0x40000 + decoder[b] * 0x1000;
                t[k] = char(extract(v, 16, 8));
            }
            return concat(t);
        } }.anon;

        hem.reader_factory = struct { fn anon(io: anytype, tick: anytype, cb: anytype) void {
            var cd = tick;
            var buf = .{};
            table.insert(hem.timers, struct { fn anon() V {
                var oc = @intCast(buf.len);
                const _, const ok = __may_method(io.read, buf);
                if (!ok) {
                    cb(buf, true);
                    buf = .{};
                    return false;
                }
                if ((@intCast(buf.len) == oc) and (@intCast(buf.len) > 0)) {
                    cd = cd - 1;
                    if (cd <= 0) {
                        cd = tick;
                    }
                    var ob = buf;
                    buf = .{};
                    return cb(ob, false);
                }
                return true;
            } }.anon);
        } }.anon;

        hem.add_job_suggestions = struct { fn anon(set: anytype, allow_hidden: anytype, filter: anytype) void {
            var filter = filter or struct { fn anon(job: anytype) V {
                return __may_mv(true, job.short);
            } }.anon;
            if (!set.hint) {
                set.hint = .{};
            }
            if (hem.selectedjob) {
                const ok, const hint = filter(hem.selectedjob);
                if (ok) {
                    table.insert(set, "#csel");
                    table.insert(set.hint, hint or "");
                }
            }
            if (hem.latestjob) {
                const ok, const hint = filter(hem.latestjob);
                if (ok) {
                    table.insert(set, "#last");
                    table.insert(set.hint, hint or "");
                }
            }
            for (lash.jobs, 0..) |v, _| {
                const ok, const hint = filter(v);
                if (ok and (!v.hidden or allow_hidden)) {
                    table.insert(set, "#" ++ tostring(v.id));
                    table.insert(set.hint, hint or "");
                    if (v.alias) {
                        table.insert(set, "#" ++ v.alias);
                        table.insert(set.hint, hint or "");
                    }
                }
            }
        } }.anon;

        const expand_helpers = struct { fn expand_helpers(helpers: anytype, v: anytype, va: anytype) V {
            const a, const b, const c = string.find(v, "$([%w_]+)");
            if (!c) {
                return v;
            }
            var res = "";
            if (a > 1) {
                res = string.sub(v, 1, a - 1);
            }
            if (helpers[c]) {
                var expanded = helpers[c](va);
                if (expanded) {
                    if (@intCast(expanded.len) == 0) {
                        return null;
                    }
                    res = res ++ expanded;
                }
            }
            var suf = string.sub(v, b + 1);
            if (string.sub(suf, 1, 1) == " ") {
                suf = string.sub(suf, 2);
            }
            res = res ++ suf;
            return expand_helpers(helpers, res);
        } }.expand_helpers;

        const apply_queue = struct { fn apply_queue(dst: anytype, queue: bool, template: anytype) void {
            if (!queue or (@intCast(queue.len) == 0)) {
                return;
            }
            if (template.prefix and (type(template.prefix) == "table")) {
                for (template.prefix, 0..) |v, _| {
                    table.insert(dst, v);
                }
            }
            for (queue, 0..) |v, _| {
                table.insert(dst, v);
            }
            if (template.suffix and (type(template.suffix) == "table")) {
                for (template.suffix, 0..) |v, _| {
                    table.insert(dst, v);
                }
            }
        } }.apply_queue;

        hem.template_to_str = struct { fn anon(template: anytype, helpers: anytype, job: anytype) V {
            var res = .{};
            var queue = undefined;
            for (template, 0..) |v, _| {
                if (type(v) == "table") {
                    table.insert(res, v);
                } else if (type(v) == "string") {
                    if ((v == "$begin") or (v == "$end")) {
                        apply_queue(res, queue, template);
                        if (v == "$begin") {
                            queue = .{};
                        } else {
                            queue = null;
                        }
                    } else {
                        table.insert(queue or res, expand_helpers(helpers, v, job));
                    }
                } else if (type(v) == "function") {
                    var fret = v(hem, job);
                    if (fret and string.find(fret, "%S")) {
                        table.insert(queue or res, fret);
                    }
                } else {
                    hem.add_message("bad member in prompt");
                }
            }
            apply_queue(res, queue, template);
            return res;
        } }.anon;

        hem.always_active = struct { fn anon() bool {
            return true;
        } }.anon;

        hem.table_copy_shallow = struct { fn anon(intbl: anytype) V {
            var outtbl = .{};
            for (pairs(intbl)) |__may_pair| {
                const k = __may_pair[0];
                const v = __may_pair[1];
                outtbl[k] = v;
            }
            return outtbl;
        } }.anon;

        const escape = struct { fn escape(line: anytype, expand: bool) V {
            if (!expand) {
                return line;
            }
            if (string.find(line, " ") or string.find(line, "\"")) {
                return "\"" ++ (string.trim(string.gsub(line, "\"", "\\\"")) ++ "\"");
            }
            return line;
        } }.escape;

        hem.expand_string_table = struct { fn anon(intbl: anytype, cap: anytype, expand: anytype) V {
            var out = .{};
            var count = 0;
            while (@intCast(intbl.len) > 0) {
                var item: Obj = table.remove(intbl, 1);
                var as_string = escape(tostring(item), expand);
                if ((type(item) != "table") and as_string) {
                    table.insert(out, as_string);
                    count = count + @intCast(as_string.len);
                } else if ((type(item) == "table") and item.slice) {
                    var arg = null;
                    if ((type(intbl[1]) == "table") and intbl[1].parg) {
                        arg = table.remove(intbl, 1);
                    }
                    var set = item.slice(arg);
                    if (set) {
                        for (set, 0..) |v, _| {
                            v = escape(tostring(v), expand);
                            count = count + @intCast(v.len);
                            table.insert(out, v);
                        }
                    }
                } else {
                    return __may_mv(null, "unexpected type in arguments");
                }
            }
            return out;
        } }.anon;

        hem.switch_env = struct { fn anon(job: bool, force_prompt: anytype) void {
            if (hem.job_stash and !job) {
                hem.chdir(hem.job_stash.dir);
                hem.env = hem.job_stash.env;
                hem.get_prompt = hem.job_stash.get_prompt;
                hem.builtins = hem.job_stash.builtins;
                hem.views = hem.job_stash.views;
                hem.suggest = hem.job_stash.suggest;
                hem.builtin_name = hem.job_stash.builtin_name;
                hem.job_stash = null;
            }
            if (!job) {
                return;
            }
            hem.job_stash = .{
                .dir = __may_method(root.chdir),
                .env = hem.table_copy_shallow(hem.env),
                .get_prompt = hem.get_prompt,
                .views = hem.views,
                .builtins = hem.builtins,
                .builtin_name = hem.builtin_name,
                .suggest = job.suggest,
            };
            hem.builtins = job.builtins;
            hem.builtin_name = job.builtin_name;
            if (force_prompt) {
                hem.get_prompt = struct { fn anon() V {
                    if (type(force_prompt) == "string") {
                        return .{ force_prompt };
                    } else if (type(force_prompt) == "table") {
                        return force_prompt;
                    } else {
                        return .{ "" };
                    }
                } }.anon;
                if (hem.readline) {
                    __may_method(hem.readline.set, job.raw);
                }
            }
            hem.chdir(job.dir);
            hem.env = job.env;
        } }.anon;

        hem.hide_readline = struct { fn anon(root: Obj) void {
            if (!hem.readline) {
                return;
            }
            hem.laststr = __may_method(hem.readline.get);
            root.revert();
            hem.flag_dirty();
        } }.anon;

        hem.set_readline = struct { fn anon(rl: anytype, src: anytype) void {
            hem.readline = rl;
            hem.readline_src = src;
        } }.anon;

        hem.block_readline = struct { fn anon(root: anytype, on: anytype, hide: anytype) void {
            hem.readline_block = on;
            hem.readline_block_hide = hide;
        } }.anon;

        var KiB = 1024;
        var MiB = 1024 * 1024;
        var GiB = 1024 * 1024 * 1024;
        var TiB = 1024 * 1024 * 1024 * 1024;
        hem.sz_to_human = struct { fn anon(sz: anytype) V {
            if (sz < KiB) {
                return __may_mv("B", sz);
            } else if (sz < MiB) {
                return __may_mv("K", sz / KiB);
            } else if (sz < GiB) {
                return __may_mv("M", sz / MiB);
            } else if (sz < TiB) {
                return __may_mv("G", sz / GiB);
            } else {
                return __may_mv("T", sz / TiB);
            }
        } }.anon;

        hem.list_processes = struct { fn anon(closure: anytype) void {
            var env = .{};
            const _, const out, const _, const pid = __may_method(root.popen, "ps ax", "r", env);
            hem.add_background_job(out, pid, .{ .lf_strip = true }, struct { fn anon(job: anytype, code: i64) void {
                if (code == 0) {
                    var set = .{};
                    for (job.data, 0..) |v, i| {
                        var elem = string.split(string.trim(v), "%s+");
                        var pid = tonumber(elem[1]);
                        table.insert(set, .{
                            .pid = tonumber(elem[1]),
                            .tty = elem[2],
                            .state = elem[3],
                            .time = elem[4],
                            .name = table.concat(elem, " ", 5),
                        });
                    }
                    table.remove(set, 1);
                    closure(set);
                } else {
                    closure(.{});
                }
            } }.anon);
        } }.anon;

        hem.get_history_source = struct { fn anon() V {
            var builtin = (hem.config.history.builtin_bin and hem.builtin_name) or "default";
            if (!hem.history[builtin]) {
                hem.history[builtin] = .{
                    .bytecount = 0,
                    .linecount = 0,
                    .meta = .{},
                };
            }
            return hem.history[builtin];
        } }.anon;

        var histflt = .{
            "^cd%s",
            "^builtin%s",
        };
        hem.append_history = struct { fn anon(line: anytype, job: anytype) void {
            var hist = hem.get_history_source(hem.history[builtin]);
            if (!hist[line]) {
                hist[line] = true;
            } else if (config.history.filter_duplicate) {
                for (@intCast(hist.len)..1 + 1) |i| {
                    __may_step(-1);
                    if (hist[i] == line) {
                        table.remove(hist, i);
                        if (hist.meta and (i <= @intCast(hist.meta.len))) {
                            table.remove(hist.meta, i);
                        }
                        hist.linecount = hist.linecount - 1;
                        hist.bytecount = hist.bytecount - @intCast(line.len);
                        break;
                    }
                }
            }
            if ((type(job) == "table") and job.pid) {
                var @"defer" = undefined;
                @"defer" = struct { fn anon() void {
                    hem.append_history(line);
                    hem.remove_match(job.hooks.on_finish, @"defer");
                } }.anon;
                table.insert(job.hooks.on_finish, @"defer");
                return;
            }
            table.insert(hist, 1, line);
            hist.linecount = hist.linecount + 1;
            hist.bytecount = hist.bytecount + @intCast(line.len);
        } }.anon;

        hem.setup_readline = struct { fn anon(root: Obj) void {
            if (hem.readline_block) {
                if (!hem.readline_block_hide) {
                    hem.hide_readline(root);
                }
                return;
            }
            const cx, const cy = root.cursor_pos();
            root.cursor_to(cx, cy, config.readline.cursor, unpack(config.readline.cursor_rgb or .{}));
            var rl: Obj = root.readline(struct { fn anon(self: anytype, line: bool) void {
                hem.set_readline(null, "readline_cb");
                if (!line or (@intCast(line.len) == 0)) {
                    var on_cancel = hem.on_cancel;
                    if (on_cancel) {
                        hem.on_cancel = null;
                        on_cancel();
                        hem.reset();
                        return;
                    }
                }
                hem.on_cancel = null;
                var on_line = hem.on_line;
                if (on_line) {
                    hem.on_line = null;
                    if (on_line()) {
                        hem.reset();
                        return;
                    }
                }
                var jobret = hem.parse_string(self, line);
                hem.append_history(line, jobret);
                if (!hem.readline_block) {
                    hem.reset();
                }
            } }.anon, config.readline);
            hem.set_readline(rl, "setup_readline");
            rl.set(hem.laststr);
            rl.set_prompt(hem.get_prompt());
            rl.set_history(hem.get_history_source());
            rl.suggest(config.autosuggest);
        } }.anon;

        hem.custom_readline = struct { fn anon(wnd: anytype, prompt: anytype, initial: anytype, handler: anytype) void {
            var oprompt = hem.get_prompt;
            var got_readline = hem.readline;
            hem.block_readline(wnd.root, false, false);
            hem.reset();
            hem.set_readline(__may_method(wnd.root.readline, struct { fn anon(self: anytype, line: anytype) void {
                hem.get_prompt = oprompt;
                hem.block_readline(wnd.root, false, false);
                hem.reset();
                wnd.in_query = false;
                if (!got_readline) {
                    hem.hide_readline(wnd.root);
                }
                handler(line);
            } }.anon, .{
                .cancellable = true,
                .forward_meta = false,
                .forward_paste = false,
                .forward_mouse = true,
            }), identity);
            wnd.in_query = true;
            hem.block_readline(lash.root, true, true);
            __may_method(hem.readline.set, initial);
            hem.get_prompt = prompt;
        } }.anon;

        hem.misc_resolve_mode = struct { fn anon(arg: anytype, cmode: anytype) V {
            if (type(arg[1]) != "table") {
                return __may_mv("", cmode);
            }
            var open_mode = "";
            var t = table.remove(arg, 1);
            if (!t.parg) {
                hem.add_message("spurious #job argument in subshell command");
                return;
            }
            for (t, 0..) |v, _| {
                if (v == "err") {
                    open_mode = "e";
                } else if (v == "nokeep") {
                    open_mode = open_mode ++ "!";
                } else if (v == "embed") {
                    cmode = "embed";
                } else if (v == "v") {
                    cmode = "join-d";
                } else if (v == "tab") {
                    cmode = "tab";
                }
            }
            return __may_mv(open_mode, cmode);
        } }.anon;

        hem.expand_arg_dst = struct { fn anon(cmd: []const u8, va: anytype) V {
            var base = .{ va };
            var dst = undefined;
            if (type(base[1]) == "table") {
                dst = table.remove(base, 1);
            } else {
                dst = hem.selectedjob;
            }
            if (!dst) {
                return __may_mv(false, cmd ++ " >job< : job specifier missing");
            }
            var set = .{};
            const ok, const msg = hem.expand_arg(set, base);
            if (!ok) {
                return __may_mv(false, msg);
            }
            return __may_mv(dst, set);
        } }.anon;

        hem.get_active_root = struct { fn anon() V {
            if (hem.selectedjob) {
                return hem.selectedjob.root;
            } else {
                return lash.root;
            }
        } }.anon;

        hem.set_history_exporter = struct { fn anon() void {
            if (!hem.config.history.persist) {
                hem.state.@"export".history = null;
                hem.state.import.history = null;
                return;
            }
            hem.state.@"export"["history"] = struct { fn anon() V {
                var set = .{};
                for (pairs(hem.history)) |__may_pair| {
                    const k = __may_pair[0];
                    const v = __may_pair[1];
                    for (v, 0..) |v, i| {
                        set[k ++ ("_" ++ tostring(i))] = v;
                    }
                }
                return set;
            } }.anon;
            hem.state.import["history"] = struct { fn anon(lines: anytype) void {
                var oldb = hem.builtin_name;
                var cur = oldb;
                for (pairs(lines)) |__may_pair| {
                    const k = __may_pair[0];
                    const v = __may_pair[1];
                    const group, const _ = unpack(string.split(k, "_"));
                    if (cur != group) {
                        cur = group;
                        hem.builtin_name = cur;
                    }
                    v = string.trim(v);
                    if (@intCast(v.len) > 0) {
                        hem.append_history(v);
                    }
                }
                hem.builtin_name = oldb;
            } }.anon;
        } }.anon;
    } }.anon;
}
