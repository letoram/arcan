
var _old_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
var _my_func = undefined;
fn my_clock(va: anytype) V {
    if (_old_clock) {
        _old_clock(va);
    }
    _tick = _tick + 1;
    if (_tick == 50) {
        dispatch_symbol("/global");
    }
    if (_tick == 200) {
        return shutdown("hook_done_tick200");
    }
}

pub fn __init() void {
    _my_func = my_clock;
    _G[APPLID ++ "_clock_pulse"] = my_clock;
}
