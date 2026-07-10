
pub fn __init() void {
    if (!(lash and lash.root and lash.root.message)) {
        if (lash and lash.messages) {
            table.insert(lash.messages, "cat9_test: lash.root:message unavailable");
        }
        return false;
    }
    const emit = struct { fn emit(tag: anytype) void {
        pcall(struct { fn anon() void {
            __may_method(lash.root.message, tag);
            __may_method(lash.root.refresh);
        } }.anon);
    } }.emit;

    emit("test:bootstrap:shell=cat9_test");
    var orig_readline = lash.root.readline;
    if (type(orig_readline) == "function") {
        lash.root.readline = struct { fn anon(self: anytype, cb: anytype, cfg: anytype) V {
            var wrapped_cb = undefined;
            if (type(cb) == "function") {
                wrapped_cb = struct { fn anon(rlself: anytype, line: anytype, va: anytype) V {
                    if (line and (@intCast(line.len) > 0)) {
                        var m = __may_method(tostring(line).gsub, "[\r\n]", " ");
                        emit("test:input:" ++ m);
                    }
                    return cb(rlself, line, va);
                } }.anon;
            }
            return orig_readline(self, wrapped_cb or cb, cfg);
        } }.anon;
        emit("test:bootstrap:readline_wrapped");
    } else {
        emit("test:bootstrap:readline_wrap_skipped");
    }
    var orig_set_handlers = lash.root.set_handlers;
    var installed = false;
    lash.root.set_handlers = struct { fn anon(self: anytype, handlers: anytype) V {
        if (!installed) {
            installed = true;
            emit("test:bootstrap:set_handlers_intercepted");
            var hem_ref = undefined;
            for (pairs(handlers)) |__may_pair| {
                const k = __may_pair[0];
                const v = __may_pair[1];
                if (type(v) == "function") {
                    var i = 1;
                    while (true) {
                        const n, const val = debug.getupvalue(v, i);
                        if (!n) {
                            break;
                        }
                        if ((n == "hem") and (type(val) == "table") and val.add_message and val.builtins) {
                            hem_ref = val;
                            break;
                        }
                        i = i + 1;
                    }
                    if (hem_ref) {
                        break;
                    }
                }
            }
            if (hem_ref) {
                var _orig_addmsg = hem_ref.add_message;
                hem_ref.add_message = struct { fn anon(s: anytype) V {
                    emit("test:msg:" ++ __may_method(tostring(s).gsub, "[\r\n]", " "));
                    return _orig_addmsg(s);
                } }.anon;
                var _orig_set = hem_ref.builtins["builtin"];
                if (_orig_set) {
                    hem_ref.builtins["builtin"] = struct { fn anon(a: anytype, opt: anytype) V {
                        emit("test:builtin_switch:to=" ++ tostring(a));
                        var r = _orig_set(a, opt);
                        emit("test:builtin_switch:after=" ++ (tostring(hem_ref.builtin_name) ++ (":has_read=" ++ (tostring(hem_ref.builtins.read != null) ++ (":has_write=" ++ tostring(hem_ref.builtins.write != null))))));
                        return r;
                    } }.anon;
                }
            }
            var orig_bo = handlers.bchunk_out;
            if (orig_bo) {
                handlers.bchunk_out = struct { fn anon(self: anytype, blob: anytype, id: anytype, va: anytype) V {
                    emit("test:bchunk_out:id=" ++ tostring(id));
                    return orig_bo(self, blob, id, va);
                } }.anon;
            }
            var orig_bi = handlers.bchunk_in;
            if (orig_bi) {
                handlers.bchunk_in = struct { fn anon(self: anytype, blob: anytype, id: anytype, lref: anytype, va: anytype) V {
                    emit("test:bchunk_in:id=" ++ tostring(id));
                    return orig_bi(self, blob, id, lref, va);
                } }.anon;
            }
            var orig_tick = handlers.tick;
            var prev = .{};
            var prev_exit = .{};
            handlers.tick = struct { fn anon(va: anytype) V {
                var jobs = lash.jobs;
                if (jobs) {
                    var seen = .{};
                    for (jobs, 0..) |job, _| {
                        var id = job.id;
                        if (id) {
                            seen[id] = true;
                            if (!prev[id]) {
                                prev[id] = job.short or job.raw or "?";
                                var short = __may_method(tostring(prev[id]).gsub, "[\r\n]", " ");
                                emit("test:job_in:id=" ++ (tostring(id) ++ (":short=" ++ short)));
                            }
                            if ((job.exit != null) and (prev_exit[id] == null)) {
                                prev_exit[id] = job.exit;
                                emit("test:job_done:id=" ++ (tostring(id) ++ (":exit=" ++ tostring(job.exit))));
                            }
                        }
                    }
                    for (pairs(prev)) |__may_pair| {
                        const id = __may_pair[0];
                        const _ = __may_pair[1];
                        if (!seen[id]) {
                            emit("test:job_out:id=" ++ tostring(id));
                            prev[id] = null;
                            prev_exit[id] = null;
                        }
                    }
                }
                if (orig_tick) {
                    return orig_tick(va);
                }
            } }.anon;
            emit("test:bootstrap:wraps=installed");
        }
        return orig_set_handlers(self, handlers);
    } }.anon;

    emit("test:bootstrap:loading_hem");
    var hem_path = lash.scriptdir ++ "cat9.lua";
    const @"fn", const err = loadfile(hem_path);
    if (!@"fn") {
        emit("test:bootstrap:err=loadfile:" ++ tostring(err));
        return false;
    }
    emit("test:bootstrap:cat9_loaded:about_to_run");
    const ok, const run_err = pcall(@"fn");
    emit("test:teardown:cat9_returned:ok=" ++ (tostring(ok) ++ (":err=" ++ tostring(run_err))));
    pcall(struct { fn anon() void {
        var f: Obj = io.open("/tmp/cat9_test_teardown.txt", "w");
        if (f) {
            f.write(string.format("ok=%s\nerr=%s\n", tostring(ok), tostring(run_err)));
            f.close();
        }
    } }.anon);
    return ok;
}
