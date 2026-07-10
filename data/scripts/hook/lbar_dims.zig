
var _old_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;

pub fn __init() void {
    _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) V {
        if (_old_clock) {
            _old_clock(va);
        }
        _tick = _tick + 1;
        if (_tick == 3) {
            var wm = active_display();
            if (wm) {
                print(string.format("[HOOK] wm.width=%d wm.height=%d VRESW=%d VRESH=%d", wm.width, wm.height, VRESW, VRESH));
            } else {
                print("[HOOK] active_display() returned nil");
            }
        }
        if (_tick == 5) {
            dispatch_symbol("/global");
        }
        if (_tick == 60) {
            return shutdown("hook_done_tick60");
        }
    } }.anon;
}
