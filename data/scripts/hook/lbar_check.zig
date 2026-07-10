
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
        if (_tick == 30) {
            var lines = .{};
            var ref = (tiler_lbar_isactive and tiler_lbar_isactive(true)) or null;
            if (!ref) {
                table.insert(lines, "LBAR:NOT_ACTIVE");
            } else {
                table.insert(lines, "LBAR:ACTIVE");
                if (ref.inp) {
                    table.insert(lines, "inp.msg='" ++ (tostring(ref.inp.msg) ++ "'"));
                    table.insert(lines, "inp.csel=" ++ tostring(ref.inp.csel));
                    if (ref.inp.set) {
                        table.insert(lines, "set_len=" ++ tostring(@intCast(ref.inp.set.len)));
                        for (1..math.min(5, @intCast(ref.inp.set.len)) + 1) |i| {
                            table.insert(lines, "  set[" ++ (i ++ ("]=" ++ tostring(((type(ref.inp.set[i]) == "table") and ref.inp.set[i][3]) or ref.inp.set[i]))));
                        }
                    } else {
                        table.insert(lines, "set=NIL");
                    }
                } else {
                    table.insert(lines, "inp=NIL");
                }
                if (ref.canchor) {
                    table.insert(lines, "canchor=" ++ (tostring(ref.canchor) ++ (" valid=" ++ tostring(valid_vid(ref.canchor)))));
                } else {
                    table.insert(lines, "canchor=NIL");
                }
                if (ref.text) {
                    table.insert(lines, "text=" ++ (tostring(ref.text) ++ (" valid=" ++ tostring(valid_vid(ref.text)))));
                } else {
                    table.insert(lines, "text=NIL");
                }
            }
            var tv = render_text(.{
                "\\#ff0000 ",
                "TestRed",
            });
            if (valid_vid(tv)) {
                var p = image_surface_properties(tv);
                table.insert(lines, "test_render:OK vid=" ++ (tostring(tv) ++ (" w=" ++ (tostring(p.width) ++ (" h=" ++ tostring(p.height))))));
                delete_image(tv);
            } else {
                table.insert(lines, "test_render:FAIL");
            }
            return shutdown(table.concat(lines, "\n"));
        }
    } }.anon;
}
