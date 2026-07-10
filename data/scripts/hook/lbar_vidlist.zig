
var _old_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;

pub fn __init() void {
    _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) V {
        if (_old_clock) {
            _old_clock(va);
        }
        _tick = _tick + 1;
        if (_tick == 5) {
            dispatch_symbol("/global");
        }
        if (_tick == 60) {
            var lines = .{};
            for (0..4095 + 1) |i| {
                if (valid_vid(i)) {
                    var p = image_surface_properties(i);
                    var st = image_storage_properties(i);
                    var tag = image_tracetag(i) or "?";
                    var ord = p.order or -1;
                    if (ord >= 100) {
                        table.insert(lines, string.format("vid=%d tag='%s' xy=(%.0f,%.0f) wh=(%.0f,%.0f) opa=%.3f ord=%d st=%dx%d", i, tag, p.x, p.y, p.width, p.height, p.opacity, ord, st.width, st.height));
                    }
                }
            }
            return shutdown(table.concat(lines, "\n"));
        }
    } }.anon;
}
