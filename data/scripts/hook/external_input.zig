
var connpoint_handler = undefined;
fn open_connpoint(prefix: []const u8, ind: anytype) void {
    if (!ind) {
        ind = _G["_external_input_index"];
        _G["_external_input_index"] = _G["_external_input_index"] + 1;
    }
    var key = prefix ++ ("_" ++ tonumber(ind));
    var vid = target_alloc(key, struct { fn anon(source: anytype, status: anytype, iotbl: anytype) void {
        if (status.kind == "terminated") {
            delete_image(source);
            open_connpoint(prefix, ind);
        } else if (status.kind == "input") {
            var fun = _G[APPLID ++ "_input"];
            if (fun) {
                fun(iotbl);
            }
        }
    } }.anon);
    if (!valid_vid(vid)) {
        warning("builtin/external_input: could not open '" ++ (key ++ "'"));
    }
}

pub fn __init() void {
    if (!_G["_external_input_index"]) {
        _G["_external_input_index"] = 1;
    }
    var prefix = get_key("ext_io");
    if (!prefix) {
        prefix = "extio";
    }
    open_connpoint(prefix);
}
