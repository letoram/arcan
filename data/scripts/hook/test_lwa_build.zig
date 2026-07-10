
var _old_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
fn my_clock(va: anytype) void {
    if (_old_clock) {
        _old_clock(va);
    }
    _tick = _tick + 1;
    if (_tick == 100) {
        var log = "/tmp/arcan_lwa_build.log";
        var cmd = "cd /home/x/test/arcan && /usr/local/bin/zig build run -- -w 640 -h 480 durian 2>" ++ (log ++ (" ; echo EXIT_CODE=$? >> " ++ log));
        warning("test_lwa_build: launching 'zig build run' at tick " ++ tostring(_tick));
        launch_avfeed("exec=" ++ cmd, "terminal", struct { fn anon(source: anytype, status: anytype) void {
            if (status.kind == "preroll") {
                var wnd = durian_launch(source, "", "terminal");
                if (wnd) {
                    wnd.scalemode = "stretch";
                    extevh_default(source, .{
                        .kind = "registered",
                        .segkind = "terminal",
                        .title = "lwa-build-test",
                    });
                    target_displayhint(source, 640, 480, 0);
                }
            }
        } }.anon);
    }
}

pub fn __init() void {
    _G[APPLID ++ "_clock_pulse"] = my_clock;
}
