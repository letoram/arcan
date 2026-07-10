// Lua table cycle-detection visitor — tracks visited pointers.
// Cleaned from translate-c output of visitor.c.

extern fn realloc(?*anyopaque, usize) ?*anyopaque;

pub const LuaVisited = extern struct {
    i: c_int = 0,
    n: c_int = 0,
    p: [*]?*const anyopaque = undefined,
};

pub export fn LuaPushVisit(v: *LuaVisited, p: ?*const anyopaque) c_int {
    if (IsVisited(v, p)) return 1;
    return Visit(v, p);
}

pub export fn LuaPopVisit(v: *LuaVisited) void {
    v.i -= 1;
}

pub fn IsVisited(v: *LuaVisited, p: ?*const anyopaque) callconv(.c) bool {
    var i: c_int = 0;
    while (i < v.i) : (i += 1) {
        const idx: usize = @intCast(i);
        if (v.p[idx] == p) {
            return true;
        }
    }
    return false;
}

pub fn Visit(v: *LuaVisited, p: ?*const anyopaque) callconv(.c) c_int {
    if (v.i == v.n) {
        var n2: c_int = v.n;
        if (n2 == 0) {
            n2 = 2;
        }
        n2 += n2 >> @intCast(1);
        const byte_count: usize = @as(usize, @intCast(n2)) * @sizeOf(?*const anyopaque);
        const raw: ?*anyopaque = realloc(@ptrCast(v.p), byte_count);
        if (raw) |valid| {
            v.p = @ptrCast(@alignCast(valid));
            v.n = n2;
        } else {
            return -1;
        }
    }
    const idx: usize = @intCast(v.i);
    v.p[idx] = p;
    v.i += 1;
    return 0;
}
