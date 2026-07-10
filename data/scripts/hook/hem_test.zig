
var _orig_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
var lash_vid = null;
var capture_armed = false;

pub fn __init() void {
    if (type(durian_launch) == "function") {
        var _orig_dl = durian_launch;
        durian_launch = struct { fn anon(vid: anytype, prefix: anytype, title: []const u8, wnd: anytype, wargs: anytype) V {
            if (type(shmifmon) == "function") {
                shmifmon("cat9_test:hook:durian_launch:armed=" ++ (tostring(capture_armed) ++ (":vid=" ++ (tostring(vid) ++ (":title=" ++ tostring(title))))));
            }
            if (capture_armed and !lash_vid and ((title == "terminal") or (title == "lash") or (title and string.find(title, "lash", 1, true)))) {
                lash_vid = vid;
                if (type(shmifmon) == "function") {
                    shmifmon("cat9_test:hook:captured_lash_vid=" ++ tostring(vid));
                }
            }
            return _orig_dl(vid, prefix, title, wnd, wargs);
        } }.anon;
    }
    const tag = struct { fn tag(s: []const u8) void {
        if (type(shmifmon) == "function") {
            shmifmon("cat9_test:hook:" ++ s);
        }
    } }.tag;

    var KSYM_RETURN = 13;
    const send_char = struct { fn send_char(vid: anytype, ch: anytype, sym: anytype) bool {
        if (!(vid and valid_vid(vid))) {
            return false;
        }
        sym = sym or 0;
        target_input(vid, .{
            .kind = "digital",
            .translated = true,
            .active = true,
            .devid = 0,
            .subid = sym,
            .number = sym,
            .keysym = sym,
            .modifiers = 0,
            .utf8 = ch,
        });
        target_input(vid, .{
            .kind = "digital",
            .translated = true,
            .active = false,
            .devid = 0,
            .subid = sym,
            .number = sym,
            .keysym = sym,
            .modifiers = 0,
            .utf8 = "",
        });
        return true;
    } }.send_char;

    const send_line = struct { fn send_line(vid: anytype, line: anytype) void {
        for (1..(@intCast(line.len)) + 1) |i| {
            var ch = string.sub(line, i, i);
            send_char(vid, ch, string.byte(ch));
        }
        send_char(vid, "\r", KSYM_RETURN);
    } }.send_line;

    var SLOT_BASE = 60;
    var SLOT_GAP = 25;
    var SHUTDOWN_GAP = 250;
    var cmds = .{
        "find /etc/hostname",
        "find /etc/passwd",
        "find /etc/issue",
        "ls /etc",
        "ls -la /tmp",
        "ls /var",
        "!!seq 1 5",
        "!!echo hello world",
        "!!true",
        "!!sleep 0.05",
        "cd /tmp",
        "cd /etc",
        "cd /var",
        "cd /",
        "cd -",
        "env CAT9_TEST harness",
        "env LASH_RUN_ID 42",
        "env =alias myfind find -name",
        "env =alias myls ls -la",
        "env COVERAGE 100",
        "view #0",
        "view #0 expand",
        "view #0 collapse",
        "view #0 toggle",
        "view #1 expand",
        "view #1 scroll 2",
        "view #1 mark 1",
        "view #1 linenumber on",
        "view #1 linenumber off",
        "view #last toggle",
        "copy #0 clipboard:",
        "copy #1 clipboard:",
        "copy #2 clipboard:",
        "copy #3 clipboard:",
        "copy #4 clipboard:",
        "copy #5 clipboard:",
        "copy #6 clipboard:",
        "copy #7 clipboard:",
        "copy #-1 clipboard:",
        "copy #-2 clipboard:",
        "view #-1",
        "view #-2",
        "view #last",
        "copy #4(1-2) clipboard:",
        "copy #5(1) clipboard:",
        "copy #2(1-3) clipboard:",
        "copy #3(1,2) clipboard:",
        "copy #-1(1) clipboard:",
        "forget #-1",
        "forget #-2",
        "find /etc/hosts",
        "forget #last",
        "find /etc/group",
        "forget #last hup",
        "!!sleep 0.06",
        "forget #last kill",
        "!!sleep 0.07",
        "forget #last quit",
        "forget all-bad",
        "forget all-passive",
        "!!seq 2 4",
        "repeat #last",
        "trigger #last ok flush",
        "trigger #last fail alert test_failure",
        "each #last !! echo each-iter",
        "each (merge) #last !! echo merge-iter",
        "each (sequential) #last !! echo seq-iter",
        "contain new",
        "contain add #last",
        "explain",
        "list",
        "list /tmp",
        "list /etc",
        "list /var",
        "list /",
        "config",
        "stash",
        "stash add /etc/hostname",
        "stash verify",
        "stash add /etc/passwd",
        "!!seq 3 6",
        "signal hup #last",
        "!!sleep 0.08",
        "signal kill #last",
        "!!sleep 0.09",
        "signal user1 #last",
        "view #2 expand",
        "view #3 expand",
        "view #4 collapse",
        "cd #4",
        "find /etc/services",
        "find /etc/hosts.allow",
        "cd /nonexistent_dir",
        "forget #999",
        "signal badsignal #0",
        "!!echo final-marker",
        "!!echo finished",
        "cd /home",
        "env DONE 1",
        "!!echo 100slots-done",
    };
    var total = @intCast(cmds.len);
    var fired = .{};
    _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) void {
        if (_orig_clock) {
            _orig_clock(va);
        }
        _tick = _tick + 1;
        if ((_tick == 60) and !fired.spawn) {
            fired.spawn = true;
            capture_armed = true;
            tag("tick=60:spawn_lash:armed_capture");
            if (type(dispatch_symbol) == "function") {
                dispatch_symbol("/global/open/lash");
            }
        }
        var START = SLOT_BASE + 120;
        for (cmds, 0..) |cmd, i| {
            var at = START + (i - 1) * SLOT_GAP;
            var key = "s" ++ i;
            if ((_tick == at) and !fired[key]) {
                fired[key] = true;
                if (!lash_vid or !valid_vid(lash_vid)) {
                    tag(string.format("slot=%d:no_lash_vid", i));
                } else {
                    tag(string.format("slot=%d:start", i));
                    send_line(lash_vid, cmd);
                }
            }
        }
        var SHUTDOWN_TICK = START + total * SLOT_GAP + SHUTDOWN_GAP;
        if ((_tick == SHUTDOWN_TICK) and !fired.eof) {
            fired.eof = true;
            tag(string.format("tick=%d:delete_lash_vid", SHUTDOWN_TICK));
            if (lash_vid and valid_vid(lash_vid)) {
                delete_image(lash_vid);
            }
        }
        var FINAL_TICK = SHUTDOWN_TICK + SHUTDOWN_GAP;
        if ((_tick == FINAL_TICK) and !fired.done) {
            fired.done = true;
            tag(string.format("tick=%d:shutdown", FINAL_TICK));
            if (type(shutdown) == "function") {
                shutdown("cat9_test:done");
            }
        }
    } }.anon;
}
