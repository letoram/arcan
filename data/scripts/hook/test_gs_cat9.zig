
var _old_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
var _term_vid = null;
var _phase = 0;
fn type_into(vid: anytype, str: Obj) void {
    for (1..(@intCast(str.len)) + 1) |i| {
        var ch = str.sub(i, i);
        target_input(vid, .{
            .kind = "digital",
            .translated = true,
            .active = true,
            .utf8 = ch,
            .keysym = 0,
            .modifiers = 0,
            .devid = 0,
            .subid = 0,
            .number = 0,
        });
        target_input(vid, .{
            .kind = "digital",
            .translated = true,
            .active = false,
            .utf8 = "",
            .keysym = 0,
            .modifiers = 0,
            .devid = 0,
            .subid = 0,
            .number = 0,
        });
    }
}

fn press_enter(vid: anytype) void {
    target_input(vid, .{
        .kind = "digital",
        .translated = true,
        .active = true,
        .utf8 = "\r",
        .keysym = 13,
        .modifiers = 0,
        .devid = 0,
        .subid = 0,
        .number = 13,
    });
    target_input(vid, .{
        .kind = "digital",
        .translated = true,
        .active = false,
        .utf8 = "",
        .keysym = 13,
        .modifiers = 0,
        .devid = 0,
        .subid = 0,
        .number = 13,
    });
}

fn my_clock(va: anytype) V {
    if (_old_clock) {
        _old_clock(va);
    }
    _tick = _tick + 1;
    if ((_tick == 100) and (_phase == 0)) {
        var wm = active_display();
        if (wm and wm.selected and wm.selected.external) {
            _term_vid = wm.selected.external;
            _phase = 1;
        }
    }
    if ((_tick == 200) and (_phase == 1)) {
        type_into(_term_vid, "builtin gamescope");
        press_enter(_term_vid);
        _phase = 2;
    }
    if ((_tick == 400) and (_phase == 2)) {
        type_into(_term_vid, "chromium");
        press_enter(_term_vid);
        _phase = 3;
    }
    if (_tick == 3000) {
        save_ppm();
    }
    if (_tick == 3010) {
        return shutdown("test_gs_hem phase=" ++ (tostring(_phase) ++ (" vid=" ++ tostring(_term_vid))));
    }
}

pub fn __init() void {
    _G[APPLID ++ "_clock_pulse"] = my_clock;
}
