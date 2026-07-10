
var left = 500;

pub fn __init() void {
    if (appl_arguments) {
        for (appl_arguments(), 0..) |v, i| {
            if (string.sub(v, 1, 9) == "shutdown=") {
                var rem = string.sub(v, 10);
                var num = tonumber(rem);
                if (num and (num > 0)) {
                    left = num;
                }
            }
        }
    }
    warning("shutdown in " ++ (tostring(left) ++ " ticks"));
    var old_tick = _G[APPLID ++ "_clock_pulse"];
    _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) V {
        if (left > 0) {
            left = left - 1;
        } else if (left == 0) {
            return shutdown("autoshutdown.lua finished", EXIT_SUCCESS);
        } else if (old_tick) {
            old_tick(va);
        }
    } }.anon;
}
