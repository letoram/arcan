
fn GetInfo(StackLvl: anytype, WithLineNum: anytype) V {
    StackLvl = StackLvl + 1;
    var Ret = undefined;
    var Info = debug.getinfo(StackLvl, "nlS");
    if (Info) {
        const Name, const What, const LineNum, const ShortSrc = .{ Info.name, Info.what, Info.currentline, Info.short_src };
        if (What == "tail") {
            Ret = "overwritten stack frame";
        } else {
            if (!Name) {
                if (What == "main") {
                    Name = "chunk";
                } else {
                    Name = What ++ "function";
                }
            }
            if (Name == "C function") {
                Ret = Name;
            } else {
                LineNum = (LineNum >= 1) and LineNum;
                if (WithLineNum and LineNum) {
                    Ret = Name ++ (" (" ++ (ShortSrc ++ (", line " ++ (LineNum ++ ")"))));
                } else {
                    Ret = Name ++ (" (" ++ (ShortSrc ++ ")"));
                }
            }
        }
    } else {
        Ret = "nowhere";
    }
    return Ret;
}

fn Indent(N: anytype) V {
    return string.rep(" ", N);
}

fn Hook(tracer: anytype, Event: []const u8) void {
    var Running = GetInfo(2);
    var Caller = GetInfo(3, true);
    if (!string.find(Running ++ Caller, "modules")) {
        if (Event == "call") {
            Depth = Depth + 1;
            tracer(string.format("%s %s <- %s\n", Indent(Depth), Running, Caller));
        } else {
            var RetType = undefined;
            if (Event == "return") {
                RetType = "returning from ";
            } else if (Event == "tail return") {
                RetType = "tail-returning from ";
            }
            Depth = Depth - 1;
        }
    }
}

pub fn Trace(scope: anytype, reportfn: anytype) void {
    tracer = (reportfn and reportfn) or print;
    if (type(scope) == "function") {
        Trace(null, reportfn);
        scope();
        Untrace();
        return;
    }
    if (!Depth) {
        Depth = 1;
        for (struct { fn anon() V {
            return debug.getinfo(Depth, "n");
        } }.anon) |__may_pair| {
            const Info = __may_pair[0];
            Depth = Depth + 1;
        }
        Depth = Depth - 2;
        debug.sethook(struct { fn anon(va: anytype) V {
            return Hook(tracer, va);
        } }.anon, "cr");
    } else {
    }
}

pub fn Untrace() void {
    debug.sethook();
    Depth = null;
}

fn calc_avg(frames: anytype) V {
    var val = 0;
    var min = frames[1];
    var max = frames[1];

    for (1..(@intCast(frames.len)) + 1) |i| {
        val = val + frames[i];
        min = ((frames[i] < min) and frames[i]) or min;
        max = ((frames[i] > max) and frames[i]) or max;
    }
    var avg = val / @intCast(frames.len);
    val = 0;
    for (1..(@intCast(frames.len)) + 1) |i| {
        var dist = frames[i] - avg;
        val = val + (dist * dist);
    }
    var stddev = math.sqrt(val / @intCast(frames.len));

    return __may_mv(avg, min, max, stddev);
}

fn bench_tick(tbl: anytype) bool {
    const tckcnt, const ticks, const framecnt, const frames, const costcnt, const cost = benchmark_data();

    if (framecnt > tbl.min) {
        const avg, const min, const max, const stddev = calc_avg(frames);
        avg = 1000.0 / avg;
        if (avg > tbl.thresh) {
            tbl.rep(tbl.count, min, max, avg, stddev);
            tbl.last_avg = avg;
            tbl.count = tbl.count + 1;
            if (tbl.rebench) {
                benchmark_enable(true);
            }
            const tot, const free = current_context_usage();
            if ((tot - free) <= 1) {
                __may_method(tbl.warning);
                return false;
            } else {
                __may_method(tbl.incr);
            }
            return true;
        } else {
            return false;
        }
    } else {
        return true;
    }
}

fn default_rep(count: anytype, min: anytype, max: anytype, avg: anytype, stddev: anytype) void {
    print(string.format("%d;%d;%d;%d;%d", count, min, max, avg, stddev));
}

fn bench_destr(tbl: anytype) void {
    for (1..(@intCast(tbl.list.len)) + 1) |i| {
        if (valid_vid(tbl.list[i])) {
            delete_image(tbl.list[i]);
        }
    }
    tbl.list = .{};
    tbl.tick = empty_fun;
    tbl.rep = empty_fun;
    tbl.incr = empty_fun;
    tbl.destroy = empty_fun;
    benchmark_enable(false);
}

pub fn benchmark_setup(arguments: anytype) void {
    system_context_size(65535);
    pop_video_context();
    if (arguments == null) {
        return;
    }
}

fn empty_warn(tbl: anytype) void {
    warning("limit reached during testing, values inconclusive.\n");
}

pub fn benchmark_create(min_samples: anytype, threshold: anytype, ramp: anytype, increment_function: anytype) V {
    var res = .{
        .tick = bench_tick,
        .rep = default_rep,
        .incr = incr,
        .min = min_samples,
        .thresh = threshold,
        .destroy = bench_destr,
        .incr = increment_function,
        .rebench = false,
        .warning = empty_warn,
        .count = 0,
        .list = .{},
    };

    for (0..ramp + 1) |i| {
        __may_step(1);
        res.count = res.count + 1;
        var img = increment_function();
        if (valid_vid(img)) {
            table.insert(res.list, img);
        }
    }
    benchmark_enable(true);
    return res;
}
