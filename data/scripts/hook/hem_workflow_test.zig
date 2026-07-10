
var _orig_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
var lash_vid = null;
var capture_armed = false;

pub fn __init() void {
    if (type(durian_launch) == "function") {
        var _orig_dl = durian_launch;
        durian_launch = struct { fn anon(vid: anytype, prefix: anytype, title: []const u8, wnd: anytype, wargs: anytype) V {
            if (type(shmifmon) == "function") {
                shmifmon("hem_wf:hook:durian_launch:armed=" ++ (tostring(capture_armed) ++ (":vid=" ++ (tostring(vid) ++ (":title=" ++ tostring(title))))));
            }
            if (capture_armed and !lash_vid and ((title == "terminal") or (title == "lash") or (title and string.find(title, "lash", 1, true)))) {
                lash_vid = vid;
                if (type(shmifmon) == "function") {
                    shmifmon("hem_wf:hook:captured_lash_vid=" ++ tostring(vid));
                }
            }
            return _orig_dl(vid, prefix, title, wnd, wargs);
        } }.anon;
    }
    const tag = struct { fn tag(s: []const u8) void {
        if (type(shmifmon) == "function") {
            shmifmon("hem_wf:hook:" ++ s);
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

    var cmds = .{
        .{
            .tool = "BuiltinSwitch",
            .cmd = "builtin dev",
        },
        .{
            .tool = "Dashboard",
            .cmd = "dashboard",
        },
        .{
            .tool = "Selfhost",
            .cmd = "selfhost",
        },
        .{
            .tool = "Final",
            .cmd = "!!echo wf-done",
        },
    };
    var SLOT_BASE = 60;
    var SLOT_GAP = 50;
    var SHUTDOWN_GAP = 4500;
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
        for (cmds, 0..) |slot, i| {
            var at = START + (i - 1) * SLOT_GAP;
            var key = "s" ++ i;
            if ((_tick == at) and !fired[key]) {
                fired[key] = true;
                if (!lash_vid or !valid_vid(lash_vid)) {
                    tag(string.format("slot=%d:tool=%s:no_lash_vid", i, slot.tool));
                } else {
                    tag(string.format("slot=%d:tool=%s:start", i, slot.tool));
                    send_line(lash_vid, slot.cmd);
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
                shutdown("hem_wf:done");
            }
        }
    } }.anon;
}
