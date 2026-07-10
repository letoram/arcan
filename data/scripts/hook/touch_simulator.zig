
var ep = _G[APPLID ++ "_input"];

pub fn __init() void {
    if (!ep) {
        return;
    }
    var acc_x = 0;
    var acc_y = 0;
    var cursor = fill_surface(8, 8, 0, 127, 0);
    image_mask_set(cursor, MASK_UNPICKABLE);
    show_image(cursor);
    order_image(cursor, 65535);
    _G[APPLID ++ "_input"] = struct { fn anon(iotbl: anytype, va: anytype) V {
        if (!iotbl.mouse) {
            return ep(iotbl, va);
        }
        if (iotbl.digital) {
            ep(.{
                .kind = "touch",
                .touch = true,
                .devid = 0,
                .active = iotbl.active,
                .subid = 127 + iotbl.subid,
                .size = 1,
                .pressure = 1,
                .x = acc_x,
                .y = acc_y,
            }, va);
            return;
        }
        var vid = set_context_attachment(BADID);
        var aw = undefined;
        var ah = undefined;
        if (vid == WORLDID) {
            aw = VRESW;
            ah = VRESH;
        } else {
            var props = image_storage_properties(vid);
            aw = props.width;
            ah = props.height;
        }
        if (iotbl.relative) {
            if (iotbl.subid == 0) {
                acc_x = acc_x + iotbl.samples[1];
            } else {
                acc_y = acc_y + iotbl.samples[1];
            }
        } else {
            if (iotbl.subid == 0) {
                acc_x = iotbl.samples[1];
            } else {
                acc_y = iotbl.samples[1];
            }
        }
        acc_x = ((acc_x < 0) and 0) or acc_x;
        acc_y = ((acc_y < 0) and 0) or acc_y;
        acc_x = ((acc_x > aw) and aw) or acc_x;
        acc_y = ((acc_y > ah) and ah) or acc_y;
        move_image(cursor, acc_x, acc_y);
        assert(acc_x != null);
        assert(acc_y != null);
    } }.anon;
}
