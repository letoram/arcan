// Lua 5.4 UTF-8 library — utf8.len, utf8.offset, utf8.codepoint, etc.
// Cleaned from translate-c output of lutf8lib.c.

const std = @import("std");
const lua_State = opaque {};
const lua_Number = f64;
const lua_Integer = c_longlong;
const lua_Unsigned = c_ulonglong;
const lua_CFunction = ?*const fn (?*lua_State) callconv(.c) c_int;

// `name` must be nullable — see linit.zig. Zig safe mode fills `undefined`
// with 0xAA so a sentinel `.name = undefined` strings becomes garbage
// that Lua's strcmp dereferences during luaL_setfuncs iteration.
const luaL_Reg = extern struct {
    name: ?[*:0]const u8 = null,
    func: lua_CFunction = null,
};

const luaL_Buffer = extern struct {
    b: [*c]u8 = null,
    size: usize = 0,
    n: usize = 0,
    L: ?*lua_State = null,
    init: extern union {
        n: lua_Number,
        u: f64,
        s: ?*anyopaque,
        i: lua_Integer,
        l: c_long,
        b: [1024]u8,
    } = undefined,
};

// Lua C API externs
extern fn luaL_checkversion_(L: ?*lua_State, ver: lua_Number, sz: usize) void;
extern fn lua_createtable(L: ?*lua_State, narr: c_int, nrec: c_int) void;
extern fn luaL_setfuncs(L: ?*lua_State, l: [*]const luaL_Reg, nup: c_int) void;
extern fn lua_pushlstring(L: ?*lua_State, s: [*]const u8, len: usize) [*]const u8;
extern fn lua_setfield(L: ?*lua_State, idx: c_int, k: [*:0]const u8) void;
extern fn luaL_checklstring(L: ?*lua_State, arg: c_int, l: ?*usize) [*]const u8;
extern fn luaL_optinteger(L: ?*lua_State, arg: c_int, def: lua_Integer) lua_Integer;
extern fn luaL_argerror(L: ?*lua_State, arg: c_int, extramsg: [*:0]const u8) c_int;
extern fn lua_pushnil(L: ?*lua_State) void;
extern fn lua_pushinteger(L: ?*lua_State, n: lua_Integer) void;
extern fn lua_toboolean(L: ?*lua_State, idx: c_int) c_int;
extern fn luaL_checkinteger(L: ?*lua_State, arg: c_int) lua_Integer;
extern fn lua_pushfstring(L: ?*lua_State, fmt: [*:0]const u8, ...) [*]const u8;
extern fn lua_gettop(L: ?*lua_State) c_int;
extern fn luaL_buffinit(L: ?*lua_State, B: *luaL_Buffer) void;
extern fn luaL_addvalue(B: *luaL_Buffer) void;
extern fn luaL_pushresult(B: *luaL_Buffer) void;
extern fn luaL_checkstack(L: ?*lua_State, sz: c_int, msg: [*:0]const u8) void;
extern fn luaL_error(L: ?*lua_State, fmt: [*:0]const u8, ...) c_int;
extern fn lua_tointegerx(L: ?*lua_State, idx: c_int, isnum: ?*c_int) lua_Integer;
extern fn lua_pushcclosure(L: ?*lua_State, f: lua_CFunction, n: c_int) void;
extern fn lua_pushvalue(L: ?*lua_State, idx: c_int) void;
extern fn lua_settop(L: ?*lua_State, idx: c_int) void;

const utfint = c_uint;
const MAXUNICODE: utfint = 0x7FFFFFFF;
const MAXUTF: utfint = 0x10FFFF;

pub export fn luaopen_utf8(L: ?*lua_State) callconv(.c) c_int {
    luaL_checkversion_(L, @floatFromInt(@as(c_int, 504)), (@sizeOf(lua_Integer) * 16) + @sizeOf(lua_Number));
    lua_createtable(L, 0, @intCast(funcs.len - 1));
    luaL_setfuncs(L, &funcs, 0);
    _ = lua_pushlstring(L, "[\x00-\x7f\xc2-\xfd][\x80-\xbf]*", 14);
    lua_setfield(L, -2, "charpattern");
    return 1;
}

comptime {
    // asm (".section .yoink\n\tb\t\"lua_notice\"\n\t.previous");
}

pub fn u_posrelat(pos: lua_Integer, len: usize) callconv(.c) lua_Integer {
    if (pos >= 0) return pos;
    const neg: usize = @intCast(-pos);
    if (neg > len) return 0;
    return @as(lua_Integer, @intCast(len)) + pos + 1;
}

pub fn utf8_decode(s_arg: [*]const u8, val: ?*utfint, strict: c_int) callconv(.c) ?[*]const u8 {
    const limits = [6]utfint{ ~@as(utfint, 0), 128, 2048, 65536, 2097152, 67108864 };
    var s = s_arg;
    var c: c_uint = s[0];
    var res: utfint = 0;

    if (c < 128) {
        res = c;
    } else {
        var count: usize = 0;
        while ((c & 64) != 0) : (c <<= 1) {
            count += 1;
            const cc: c_uint = s[count];
            if ((cc & 192) != 128) return null;
            res = (res << 6) | (cc & 63);
        }
        res |= @as(utfint, c & 127) << @intCast(count * 5);
        if ((count > 5) or (res > MAXUNICODE) or (res < limits[count])) return null;
        s += count;
    }
    if (strict != 0) {
        if ((res > MAXUTF) or ((55296 <= res) and (res <= 57343))) return null;
    }
    if (val) |v| {
        v.* = res;
    }
    return s + 1;
}

fn utflen(L: ?*lua_State) callconv(.c) c_int {
    var n: lua_Integer = 0;
    var len: usize = undefined;
    const s = luaL_checklstring(L, 1, &len);
    var posi = u_posrelat(luaL_optinteger(L, 2, 1), len);
    var posj = u_posrelat(luaL_optinteger(L, 3, -1), len);
    const lax = lua_toboolean(L, 4);

    _ = (1 <= posi and blk: {
        posi -= 1;
        break :blk posi <= @as(lua_Integer, @intCast(len));
    }) or (luaL_argerror(L, 2, "initial position out of bounds") != 0);
    _ = (blk: {
        posj -= 1;
        break :blk posj < @as(lua_Integer, @intCast(len));
    }) or (luaL_argerror(L, 3, "final position out of bounds") != 0);

    while (posi <= posj) {
        const s1 = utf8_decode(s + @as(usize, @intCast(posi)), null, @intFromBool(lax == 0));
        if (s1 == null) {
            lua_pushnil(L);
            lua_pushinteger(L, posi + 1);
            return 2;
        }
        posi = @intCast(@intFromPtr(s1.?) - @intFromPtr(s));
        n += 1;
    }
    lua_pushinteger(L, n);
    return 1;
}

fn codepoint(L: ?*lua_State) callconv(.c) c_int {
    var len: usize = undefined;
    const s = luaL_checklstring(L, 1, &len);
    const posi = u_posrelat(luaL_optinteger(L, 2, 1), len);
    const pose = u_posrelat(luaL_optinteger(L, 3, posi), len);
    const lax = lua_toboolean(L, 4);

    _ = (posi >= 1) or (luaL_argerror(L, 2, "out of bounds") != 0);
    _ = (pose <= @as(lua_Integer, @intCast(len))) or (luaL_argerror(L, 3, "out of bounds") != 0);
    if (posi > pose) return 0;
    if ((pose - posi) >= 0x7FFFFFFF) return luaL_error(L, "string slice too long");

    var n: c_int = @intCast(pose - posi + 1);
    luaL_checkstack(L, n, "string slice too long");
    n = 0;
    const se = s + @as(usize, @intCast(pose));
    var sp = s + @as(usize, @intCast(posi - 1));
    while (@intFromPtr(sp) < @intFromPtr(se)) {
        var code: utfint = undefined;
        const next = utf8_decode(sp, &code, @intFromBool(lax == 0));
        if (next == null) return luaL_error(L, "invalid UTF-8 code");
        sp = next.?;
        lua_pushinteger(L, @intCast(code));
        n += 1;
    }
    return n;
}

fn pushutfchar(L: ?*lua_State, arg: c_int) callconv(.c) void {
    const code: lua_Unsigned = @bitCast(luaL_checkinteger(L, arg));
    _ = (code <= MAXUNICODE) or (luaL_argerror(L, arg, "value out of range") != 0);
    var buf: [8]u8 = undefined;
    const cp: u21 = @intCast(@as(u32, @truncate(code)));
    const len = std.unicode.utf8Encode(cp, &buf) catch 0;
    if (len > 0) {
        _ = lua_pushlstring(L, &buf, len);
    } else {
        _ = lua_pushlstring(L, &buf, 0);
    }
}

fn utfchar(L: ?*lua_State) callconv(.c) c_int {
    const n = lua_gettop(L);
    if (n == 1) {
        pushutfchar(L, 1);
    } else {
        var b: luaL_Buffer = undefined;
        luaL_buffinit(L, &b);
        var i: c_int = 1;
        while (i <= n) : (i += 1) {
            pushutfchar(L, i);
            luaL_addvalue(&b);
        }
        luaL_pushresult(&b);
    }
    return 1;
}

fn byteoffset(L: ?*lua_State) callconv(.c) c_int {
    var len: usize = undefined;
    const s = luaL_checklstring(L, 1, &len);
    var n = luaL_checkinteger(L, 2);
    var posi: lua_Integer = @intCast(if (n >= 0) @as(usize, 1) else len + 1);
    posi = u_posrelat(luaL_optinteger(L, 3, posi), len);

    _ = (1 <= posi and blk: {
        posi -= 1;
        break :blk posi <= @as(lua_Integer, @intCast(len));
    }) or (luaL_argerror(L, 3, "position out of bounds") != 0);

    if (n == 0) {
        // find beginning of current byte sequence
        while ((posi > 0) and ((@as(c_int, s[@intCast(posi)]) & 192) == 128)) {
            posi -= 1;
        }
    } else {
        if ((@as(c_int, s[@intCast(posi)]) & 192) == 128)
            return luaL_error(L, "initial position is a continuation byte");
        if (n < 0) {
            while ((n < 0) and (posi > 0)) {
                while (true) {
                    posi -= 1;
                    if (!((posi > 0) and ((@as(c_int, s[@intCast(posi)]) & 192) == 128))) break;
                }
                n += 1;
            }
        } else {
            n -= 1;
            while ((n > 0) and (posi < @as(lua_Integer, @intCast(len)))) {
                while (true) {
                    posi += 1;
                    if (!((@as(c_int, s[@intCast(posi)]) & 192) == 128)) break;
                }
                n -= 1;
            }
        }
    }
    if (n == 0) {
        lua_pushinteger(L, posi + 1);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

fn iter_aux(L: ?*lua_State, strict: c_int) callconv(.c) c_int {
    var len: usize = undefined;
    const s = luaL_checklstring(L, 1, &len);
    var n: lua_Unsigned = @bitCast(lua_tointegerx(L, 2, null));

    if (n < len) {
        // skip continuation bytes
        while ((@as(c_int, s[@intCast(n)]) & 192) == 128) {
            n +%= 1;
        }
    }
    if (n >= len) return 0;

    var code: utfint = undefined;
    const next = utf8_decode(s + @as(usize, @intCast(n)), &code, strict);
    if ((next == null) or ((@as(c_int, next.?[0]) & 192) == 128))
        return luaL_error(L, "invalid UTF-8 code");
    lua_pushinteger(L, @bitCast(n +% 1));
    lua_pushinteger(L, @intCast(code));
    return 2;
}

fn iter_auxstrict(L: ?*lua_State) callconv(.c) c_int {
    return iter_aux(L, 1);
}

fn iter_auxlax(L: ?*lua_State) callconv(.c) c_int {
    return iter_aux(L, 0);
}

fn iter_codes(L: ?*lua_State) callconv(.c) c_int {
    const lax = lua_toboolean(L, 2);
    const s = luaL_checklstring(L, 1, null);
    _ = (!((@as(c_int, s[0]) & 192) == 128)) or (luaL_argerror(L, 1, "invalid UTF-8 code") != 0);
    lua_pushcclosure(L, if (lax != 0) &iter_auxlax else &iter_auxstrict, 0);
    lua_pushvalue(L, 1);
    lua_pushinteger(L, 0);
    return 3;
}

const funcs = [_]luaL_Reg{
    .{ .name = "offset", .func = &byteoffset },
    .{ .name = "codepoint", .func = &codepoint },
    .{ .name = "char", .func = &utfchar },
    .{ .name = "len", .func = &utflen },
    .{ .name = "codes", .func = &iter_codes },
    .{ .name = "charpattern", .func = null },
    // Sentinel — luaL_setfuncs iterates until name == NULL. Must be
    // explicit `null`, NOT `undefined` (Zig safe mode fills undefined
    // with 0xAA; strcmp then dereferences the garbage pointer).
    .{ .name = null, .func = null },
};
