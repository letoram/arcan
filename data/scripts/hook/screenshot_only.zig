
var _old_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;

pub fn __init() void {
    _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) V {
        if (_old_clock) {
            _old_clock(va);
        }
        _tick = _tick + 1;
        if (_tick == 120) {
            save_ppm();
        }
        if (_tick == 125) {
            return shutdown("screenshot done");
        }
    } }.anon;
}
