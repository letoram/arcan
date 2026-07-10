
var _lbt_old_clock = _G[APPLID ++ "_clock_pulse"];
var _lbt_tick = 0;
var _lbt_phase = "wait_init";
var _lbt_check_tick = null;
var _lbt_msgs = .{};
fn _lbt_log(msg: anytype) void {
    table.insert(_lbt_msgs, msg);
}

pub fn __init() void {
    _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) V {
        if (_lbt_old_clock) {
            _lbt_old_clock(va);
        }
        _lbt_tick = _lbt_tick + 1;
        if ((_lbt_phase == "wait_init") and (_lbt_tick == 5)) {
            var ttime = gconfig_get("transition");
            _lbt_log("transition=" ++ tostring(ttime));
            dispatch_symbol("/global");
            _lbt_check_tick = _lbt_tick + ttime + 10;
            _lbt_phase = "wait_anim";
        }
        if ((_lbt_phase == "wait_anim") and (_lbt_tick >= _lbt_check_tick)) {
            _lbt_phase = "done";
            var ref = tiler_lbar_isactive(true);
            if (!ref) {
                return shutdown("FAIL lbar not active");
            }
            var pass = true;
            if (valid_vid(ref.text_anchor)) {
                var p = image_surface_properties(ref.text_anchor);
                _lbt_log("bar opa=" ++ string.format("%.4f", p.opacity));
                if (p.opacity < 0.9) {
                    _lbt_log("FAIL bar opacity");
                    pass = false;
                }
            } else {
                _lbt_log("FAIL bar vid invalid");
                pass = false;
            }
            if (valid_vid(ref.anchor)) {
                var p = image_surface_properties(ref.anchor);
                _lbt_log("bg opa=" ++ string.format("%.4f", p.opacity));
                if (p.opacity < 0.3) {
                    _lbt_log("FAIL bg opacity");
                    pass = false;
                }
            } else {
                _lbt_log("FAIL bg vid invalid");
                pass = false;
            }
            if (ref.ccursor and valid_vid(ref.ccursor)) {
                var p = image_surface_properties(ref.ccursor);
                _lbt_log("ccursor opa=" ++ string.format("%.4f", p.opacity));
            }
            if (valid_vid(ref.caret)) {
                var p = image_surface_properties(ref.caret);
                _lbt_log("caret opa=" ++ string.format("%.4f", p.opacity));
            }
            _lbt_log("bar order=" ++ tostring(image_surface_properties(ref.text_anchor).order));
            _lbt_log("bg order=" ++ tostring(image_surface_properties(ref.anchor).order));
            var result = (pass and "ALL PASS") or "TEST FAILED";
            return shutdown(result ++ (" " ++ table.concat(_lbt_msgs, " / ")));
        }
    } }.anon;
}
