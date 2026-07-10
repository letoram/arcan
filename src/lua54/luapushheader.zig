// LuaPushHeader - push a single HTTP header value onto Lua stack
// Cleaned from translate-c output of cosmopolitan libc Lua 5.4 helpers

const std = @import("std");

// --- Lua 5.4 types ---
pub const struct_lua_State = opaque {};
pub const lua_State = struct_lua_State;

// --- HTTP types ---
pub const struct_HttpSlice = extern struct {
    a: c_short = std.mem.zeroes(c_short),
    b: c_short = std.mem.zeroes(c_short),
};

pub const struct_HttpHeader = extern struct {
    k: struct_HttpSlice = std.mem.zeroes(struct_HttpSlice),
    v: struct_HttpSlice = std.mem.zeroes(struct_HttpSlice),
};

pub const struct_HttpHeaders = extern struct {
    n: c_uint = std.mem.zeroes(c_uint),
    c: c_uint = std.mem.zeroes(c_uint),
    p: [*c]struct_HttpHeader = std.mem.zeroes([*c]struct_HttpHeader),
};

pub const struct_HttpMessage = extern struct {
    i: c_int = std.mem.zeroes(c_int),
    a: c_int = std.mem.zeroes(c_int),
    status: c_int = std.mem.zeroes(c_int),
    t: u8 = std.mem.zeroes(u8),
    type: u8 = std.mem.zeroes(u8),
    version: u8 = std.mem.zeroes(u8),
    method: u64 = std.mem.zeroes(u64),
    k: struct_HttpSlice = std.mem.zeroes(struct_HttpSlice),
    uri: struct_HttpSlice = std.mem.zeroes(struct_HttpSlice),
    scratch: struct_HttpSlice = std.mem.zeroes(struct_HttpSlice),
    message: struct_HttpSlice = std.mem.zeroes(struct_HttpSlice),
    headers: [93]struct_HttpSlice = std.mem.zeroes([93]struct_HttpSlice),
    xheaders: struct_HttpHeaders = std.mem.zeroes(struct_HttpHeaders),
};

// --- C library externs ---
pub extern fn free(?*anyopaque) void;

// --- HTTP externs ---
pub extern const kHttpRepeatable: [93]u8;
pub extern fn FoldHeader([*c]struct_HttpMessage, [*c]const u8, c_int, [*c]usize) [*c]u8;

// --- Peer function externs ---
pub extern fn LuaPushLatin1(?*lua_State, [*c]const u8, usize) void;

// --- Exported function ---
pub export fn LuaPushHeader(L: ?*lua_State, m: [*c]struct_HttpMessage, b: [*c]const u8, h: c_int) c_int {
    const h_idx: c_uint = @intCast(h);
    if (kHttpRepeatable[h_idx] == 0) {
        // Non-repeatable header: push directly from buffer slice
        const header_a: c_int = m.*.headers[h_idx].a;
        const header_b: c_int = m.*.headers[h_idx].b;
        const offset: usize = @intCast(header_a);
        const length: usize = @intCast(header_b - header_a);
        LuaPushLatin1(L, b + offset, length);
    } else {
        // Repeatable header: fold all values together
        var vallen: usize = undefined;
        const val: [*c]u8 = FoldHeader(m, b, h, &vallen);
        LuaPushLatin1(L, val, vallen);
        free(@ptrCast(val));
    }
    return 1;
}

