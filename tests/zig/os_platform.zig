const std = @import("std");
const os_platform = @import("os_platform");

test "all os_platform symbols are implemented" {
    @setEvalBranchQuota(10_000);

    // Automatically check existance of all arcan_ functions
    const declarations = @typeInfo(os_platform).Struct.decls;
    inline for (declarations) |decl| {
        comptime if (!std.mem.startsWith(u8, decl.name, "arcan_")) continue;
        const field = @field(os_platform, decl.name);
        const meta = @typeInfo(@TypeOf(field));
        comptime if (meta != .Fn) continue;

        try externFnCheck(field);
    }
}

fn externFnCheck(f: anytype) !void {
    try std.testing.expect(@intFromPtr(&f) > 0);
}
