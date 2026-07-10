
pub fn __init() void {
    if (!wm_input_selected) {
        wm_input_selected = struct { fn anon(iotbl: anytype) void {
        } }.anon;
    }
    var grab_key = undefined;
    if (!wm_input_grab) {
        wm_input_grab = struct { fn anon(key: anytype) V {
            if (key and !grab_key) {
                grab_key = key;
            }
            return grab_key;
        } }.anon;
    }
    if (!wm_input_release_grab) {
        wm_input_release_grab = struct { fn anon(key: anytype) bool {
            assert(key);
            assert(grab_key != null);
            if (key == grab_key) {
                grab_key = null;
                return true;
            }
            return false;
        } }.anon;
    }
    if (!wm_active_display) {
        wm_active_display = struct { fn anon() V {
            return __may_mv(WORLDID, VRESW, VRESH, HPPCM, VPPCM);
        } }.anon;
    }
    var active_display_listeners = .{};
    if (!wm_active_display_rebuild) {
        wm_active_display_rebuild = struct { fn anon() void {
            const rt, const w, const h, const hppcm, const vppcm = wm_active_display();
            for (active_display_listeners, 0..) |v, _| {
                v(rt, w, h, hppcm, vppcm);
            }
        } }.anon;
    }
    if (!wm_active_display_listen) {
        wm_active_display_listen = struct { fn anon(hnd: anytype) void {
            assert(hnd);
            assert(type(hnd) == "function");
            for (active_display_listeners, 0..) |v, _| {
                if (v == hnd) {
                    return;
                }
            }
            table.insert(active_display_listeners, hnd);
        } }.anon;
    }
    if (!wm_get_keyboard_translation) {
        var symtable = @import("builtin/keyboard.zig").__init();
        __may_method(symtable.load_keymap, "default.lua");
        wm_get_keyboard_translation = struct { fn anon() V {
            return symtable;
        } }.anon;
    }
    if (!wm_touch_normalize) {
        var rangetbl = .{};
        wm_touch_normalize = struct { fn anon(io: anytype) void {
            const rt, const w, const h, const _, const _ = wm_active_display();
            var range = rangetbl[io.devid];
            if (!range) {
                var x_axis = inputanalog_query(io.devid, 0);
                var y_axis = inputanalog_query(io.devid, 1);

                if (x_axis and y_axis) {
                    range = .{
                        x_axis.upper_bound,
                        y_axis.upper_bound,
                    };
                } else {
                    range = .{
                        w,
                        h,
                    };
                }
                rangetbl[io.devid] = range;
            }
            if (io.x > range[1]) {
                range[1] = io.x;
            }
            if (io.y > range[2]) {
                range[2] = io.y;
            }
            io.x = io.x / range[1] * w;
            io.y = io.y / range[2] * h;
        } }.anon;
    }
}
