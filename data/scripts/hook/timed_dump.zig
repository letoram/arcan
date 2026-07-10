
var left = 500;
var reset = 0;
var seqn = 0;
var prefix = "timed";

pub fn __init() void {
    if (appl_arguments) {
        for (appl_arguments(), 0..) |v, i| {
            if (string.sub(v, 1, 11) == "dump_timer=") {
                var rem = string.sub(v, 12);
                var num = tonumber(rem);
                if (num and (num > 0)) {
                    left = num;
                }
            } else if (string.sub(v, 1, 12) == "dump_period=") {
                var rem = string.sub(v, 13);
                var num = tonumber(rem);
                if (num and (num > 0)) {
                    reset = num;
                }
            } else if (string.sub(v, 1, 12) == "dump_prefix=") {
                var rem = string.sub(v, 13);
                if (rem and (@intCast(rem.len) > 0)) {
                    prefix = rem;
                }
            }
        }
    }
    var old_tick = _G[APPLID ++ "_clock_pulse"];
    if (!old_tick) {
        old_tick = struct { fn anon() void {
        } }.anon;
    }
    _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) void {
        if (left > 0) {
            left = left - 1;
            if (left == 0) {
                var fname = string.format("%s%s.lua", prefix, ((seqn > 0) and ("_" ++ tostring(seqn))) or "");
                zap_resource(fname);
                system_snapshot(fname);
                left = reset;
            }
        }
        old_tick(va);
    } }.anon;
}
