// LuaPushHeaders - push all HTTP headers as a Lua table
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

// --- Lua API externs ---
pub extern fn lua_createtable(L: ?*lua_State, narr: c_int, nrec: c_int) void;
pub extern fn lua_setfield(L: ?*lua_State, idx: c_int, k: [*c]const u8) void;

// --- HTTP externs ---
pub extern fn GetHttpHeaderName(c_int) [*c]const u8;
pub extern fn GetHttpHeader([*c]const u8, usize) c_int;

// --- Peer function externs ---
pub extern fn LuaPushHeader(?*lua_State, [*c]struct_HttpMessage, [*c]const u8, c_int) c_int;
pub extern fn LuaPushLatin1(?*lua_State, [*c]const u8, usize) void;
pub extern fn DecodeLatin1([*c]const u8, usize, [*c]usize) [*c]u8;

/// Helper: convert HttpSlice short offset to usize for pointer arithmetic
inline fn sliceOffset(val: c_short) usize {
    return @intCast(@as(c_int, val));
}

/// Helper: compute HttpSlice length (b - a) as usize
inline fn sliceLen(a: c_short, b: c_short) usize {
    return @intCast(@as(c_int, b) - @as(c_int, a));
}

// --- Exported function ---
pub export fn LuaPushHeaders(L: ?*lua_State, m: [*c]struct_HttpMessage, b: [*c]const u8) c_int {
    lua_createtable(L, 0, 0);

    // Push standard headers (indices 0..92)
    var h: usize = 0;
    while (h < 93) : (h += 1) {
        if (m.*.headers[h].a != 0) {
            _ = LuaPushHeader(L, m, b, @as(c_int, @intCast(h)));
            lua_setfield(L, -2, GetHttpHeaderName(@as(c_int, @intCast(h))));
        }
    }

    // Push extension headers (custom/non-standard)
    var i: usize = 0;
    while (i < @as(usize, m.*.xheaders.n)) : (i += 1) {
        const x: [*c]struct_HttpHeader = m.*.xheaders.p + i;
        const v_off = sliceOffset(x.*.v.a);
        const v_len = sliceLen(x.*.v.a, x.*.v.b);
        const k_off = sliceOffset(x.*.k.a);
        const k_len = sliceLen(x.*.k.a, x.*.k.b);

        // Check if this extension header matches a known standard header
        const hdr_idx = GetHttpHeader(b + v_off, v_len);
        if (hdr_idx == -1) {
            // Unknown header: push value, decode key name from Latin-1
            LuaPushLatin1(L, b + v_off, v_len);
            const s: [*c]u8 = DecodeLatin1(b + k_off, k_len, null);
            lua_setfield(L, -2, s);
            free(@ptrCast(s));
        }
    }

    return 1;
}

