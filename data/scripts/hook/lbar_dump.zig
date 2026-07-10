
var _old_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
var _phase = "wait_init";
var _check_tick = null;
var _lines = .{};
fn log(msg: anytype) void {
    table.insert(_lines, msg);
}

fn dump_vid(label: []const u8, vid: anytype) void {
    if (!valid_vid(vid)) {
        log(label ++ ":INVALID");
        return;
    }
    var p = image_surface_properties(vid);
    var st = image_storage_properties(vid);
    var tag = image_tracetag(vid) or "?";
    log(string.format("%s vid=%d tag='%s' xy=(%.0f,%.0f) wh=(%.0f,%.0f) opa=%.3f ord=%d st=%dx%d", label, vid, tag, p.x, p.y, p.width, p.height, p.opacity, p.order or -1, st.width, st.height));
}

fn dump_tree(label: []const u8, vid: anytype, depth: anytype) void {
    if (!valid_vid(vid)) {
        return;
    }
    depth = depth or 0;
    dump_vid(string.rep("..", depth) ++ label, vid);
    var ch = image_children(vid);
    if (ch) {
        for (ch, 0..) |c, i| {
            dump_tree("ch" ++ i, c, depth + 1);
        }
    }
}

pub fn __init() void {
    _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) V {
        if (_old_clock) {
            _old_clock(va);
        }
        _tick = _tick + 1;
        if ((_phase == "wait_init") and (_tick == 5)) {
            dispatch_symbol("/global");
            _check_tick = _tick + (gconfig_get("transition") or 10) + 15;
            _phase = "wait_anim";
        }
        if ((_phase == "wait_anim") and (_tick >= _check_tick)) {
            _phase = "done";
            var ref = tiler_lbar_isactive(true);
            if (!ref) {
                return shutdown("FAIL:no_lbar");
            }
            log("=KEYS=");
            for (pairs(ref)) |__may_pair| {
                const k = __may_pair[0];
                const v = __may_pair[1];
                if ((type(v) != "table") and (type(v) != "function")) {
                    log(k ++ ("=" ++ tostring(v)));
                }
            }
            if (valid_vid(ref.text_anchor)) {
                log("=TEXT_ANCHOR_TREE=");
                dump_tree("ta", ref.text_anchor);
            }
            if (valid_vid(ref.anchor)) {
                log("=ANCHOR_TREE=");
                dump_tree("anc", ref.anchor);
            }
            return shutdown(table.concat(_lines, "\n"));
        }
    } }.anon;
}
