
var _old_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
var _phase = "wait_init";

pub fn __init() void {
    _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) V {
        if (_old_clock) {
            _old_clock(va);
        }
        _tick = _tick + 1;
        if ((_phase == "wait_init") and (_tick == 50)) {
            dispatch_symbol("/global");
            _phase = "wait_anim";
        }
        if ((_phase == "wait_anim") and (_tick == 120)) {
            _phase = "done";
            save_screenshot("/tmp/lbar_screen.png");
        }
        if ((_phase == "done") and (_tick == 130)) {
            return shutdown("screenshot saved");
        }
    } }.anon;
}
