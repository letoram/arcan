
var _orig_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
var _fired = .{};

pub fn __init() void {
    _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) void {
        if (_orig_clock) {
            _orig_clock(va);
        }
        _tick = _tick + 1;
        for (.{
            50,
            90,
            130,
        }, 0..) |t, _| {
            if ((_tick == t) and !_fired[t]) {
                _fired[t] = true;
                if (type(dispatch_symbol) == "function") {
                    dispatch_symbol("/global/open/lash");
                }
            }
        }
    } }.anon;
}
