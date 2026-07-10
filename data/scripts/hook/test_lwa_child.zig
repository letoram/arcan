
var _old_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
var _launched = false;
fn my_clock(va: anytype) void {
    if (_old_clock) {
        _old_clock(va);
    }
    _tick = _tick + 1;
    if ((_tick == 150) and !_launched) {
        _launched = true;
        warning("test_lwa_child: opening lash at tick " ++ tostring(_tick));
        dispatch_symbol("/global/open/lash");
    }
}

pub fn __init() void {
    _G[APPLID ++ "_clock_pulse"] = my_clock;
}
