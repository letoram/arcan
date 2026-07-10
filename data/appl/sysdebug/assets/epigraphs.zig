
pub fn __init() void {
    return struct { fn anon() V {
        return .{};
    } }.anon;
}
