
var _orig_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
var lash_vid = null;
var capture_armed = false;

pub fn __init() void {
    if (type(durian_launch) == "function") {
        var _orig_dl = durian_launch;
        durian_launch = struct { fn anon(vid: anytype, prefix: anytype, title: []const u8, wnd: anytype, wargs: anytype) V {
            if (capture_armed and !lash_vid and ((title == "terminal") or (title == "lash"))) {
                lash_vid = vid;
            }
            return _orig_dl(vid, prefix, title, wnd, wargs);
        } }.anon;
    }
    const tag = struct { fn tag(s: []const u8) void {
        if (type(shmifmon) == "function") {
            shmifmon("hem_caveat:c2:" ++ s);
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
        "read /tmp/eq_c2.txt",
        "builtin dev",
        "read /tmp/eq_c2.txt",
    };
    var SLOT_BASE = 60;
    var SLOT_GAP = 30;
    var fired = .{};
    _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) void {
        if (_orig_clock) {
            _orig_clock(va);
        }
        _tick = _tick + 1;
        if ((_tick == 60) and !fired.spawn) {
            fired.spawn = true;
            capture_armed = true;
            tag("spawn");
            if (type(dispatch_symbol) == "function") {
                dispatch_symbol("/global/open/lash");
            }
        }
        var START = SLOT_BASE + 120;
        for (cmds, 0..) |cmd, i| {
            var at = START + (i - 1) * SLOT_GAP;
            if ((_tick == at) and !fired["s" ++ i]) {
                fired["s" ++ i] = true;
                if (lash_vid and valid_vid(lash_vid)) {
                    tag(string.format("slot=%d:%s", i, cmd));
                    send_line(lash_vid, cmd);
                }
            }
        }
        var END_TICK = START + @intCast(cmds.len) * SLOT_GAP + 100;
        if ((_tick == END_TICK) and !fired.eof) {
            fired.eof = true;
            if (lash_vid and valid_vid(lash_vid)) {
                delete_image(lash_vid);
            }
        }
        if ((_tick == (END_TICK + 100)) and !fired.done) {
            fired.done = true;
            if (type(shutdown) == "function") {
                shutdown("c2:done");
            }
        }
    } }.anon;
}
