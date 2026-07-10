
pub fn __init() void {
    return struct { fn anon() V {
        var M = .{};
        M.annotations = struct { fn anon(slug: anytype) V {
            return .{};
        } }.anon;

        M.search = struct { fn anon(query: anytype) V {
            return .{};
        } }.anon;

        M.serve_index = struct { fn anon(req: anytype) V {
            return .{
                .kind = (req and req.kind) or "list",
                .entries = .{},
            };
        } }.anon;

        return M;
    } }.anon;
}
