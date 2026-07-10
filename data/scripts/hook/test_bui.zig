
var _old_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
fn send_str(vid: anytype, str: anytype) void {
    for (1..(@intCast(str.len)) + 1) |i| {
        var ch = string.sub(str, i, i);
        target_input(vid, .{
            .kind = "digital",
            .translated = true,
            .active = true,
            .utf8 = ch,
            .keysym = 0,
            .modifiers = 0,
            .subid = 0,
        });
        target_input(vid, .{
            .kind = "digital",
            .translated = true,
            .active = false,
            .utf8 = "",
            .keysym = 0,
            .modifiers = 0,
            .subid = 0,
        });
    }
}

pub fn __init() void {
    _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) V {
        if (_old_clock) {
            _old_clock(va);
        }
        _tick = _tick + 1;
        if (_tick == 80) {
            var wnd = active_display().selected;
            if (wnd and valid_vid(wnd.external)) {
                send_str(wnd.external, "bui");
            }
        }
        if (_tick == 120) {
            save_ppm();
        }
        if (_tick == 125) {
            return shutdown("done");
        }
    } }.anon;
}
