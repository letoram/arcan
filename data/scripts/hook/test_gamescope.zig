
var _old_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
fn my_clock(va: anytype) V {
    if (_old_clock) {
        _old_clock(va);
    }
    _tick = _tick + 1;
    if (_tick == 100) {
        var gs_bin = "/home/x/test/arcan/zig-out/bin/gamescope";
        var cmd = "env XDG_RUNTIME_DIR=/run/user/" ++ (tostring(1000) ++ (" HOME=/home/x " ++ (gs_bin ++ (" --backend arcan" ++ (" -w 1280 -h 720" ++ (" -W 1280 -H 720" ++ (" -- /usr/bin/glxgears" ++ " 2>/tmp/gamescope.log")))))));
        warning("test_gamescope: launching at tick " ++ tostring(_tick));
        launch_avfeed("exec=" ++ cmd, "terminal", struct { fn anon(source: anytype, status: anytype) void {
            if (status.kind == "preroll") {
                warning("test_gamescope: preroll OK (vid=" ++ (tostring(source) ++ ")"));
                var wnd = durian_launch(source, "", "terminal");
                if (wnd) {
                    wnd.scalemode = "stretch";
                    extevh_default(source, .{
                        .kind = "registered",
                        .segkind = "terminal",
                        .title = "gamescope",
                    });
                    target_displayhint(source, 1280, 720, 0);
                }
            } else if (status.kind == "terminated") {
                warning("test_gamescope: terminated");
            }
        } }.anon);
    }
    if (_tick == 2000) {
        warning("test_gamescope: screenshot");
        save_ppm();
    }
    if (_tick == 2010) {
        return shutdown("test_gamescope done");
    }
}

pub fn __init() void {
    _G[APPLID ++ "_clock_pulse"] = my_clock;
}
