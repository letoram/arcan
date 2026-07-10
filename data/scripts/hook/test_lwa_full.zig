
var _old_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
fn my_clock(va: anytype) void {
    if (_old_clock) {
        _old_clock(va);
    }
    _tick = _tick + 1;
    if (_tick == 100) {
        warning("test_lwa_full: launching child arcan (LWA) at tick " ++ tostring(_tick));
        var arcan_bin = "/home/x/test/arcan/zig-out/bin/arcan";
        var child_log = "/tmp/arcan_lwa_child.log";
        var cmd = arcan_bin ++ (" -w 640 -h 480" ++ (" -H hook/test_lwa_child.lua" ++ (" durian 2>" ++ (child_log ++ (" ; echo EXIT_CODE=$? >> " ++ child_log)))));
        launch_avfeed("exec=" ++ cmd, "terminal", struct { fn anon(source: anytype, status: anytype) void {
            if (status.kind == "preroll") {
                warning("test_lwa_full: child terminal preroll OK");
                var wnd = durian_launch(source, "", "terminal");
                if (wnd) {
                    wnd.scalemode = "stretch";
                    extevh_default(source, .{
                        .kind = "registered",
                        .segkind = "terminal",
                        .title = "lwa-child",
                    });
                    target_displayhint(source, 640, 480, 0);
                }
            } else if (status.kind == "terminated") {
                warning("test_lwa_full: child terminated");
            }
        } }.anon);
    }
}

pub fn __init() void {
    _G[APPLID ++ "_clock_pulse"] = my_clock;
}
