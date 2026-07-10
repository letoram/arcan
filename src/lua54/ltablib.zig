// Lua 5.4 table library — table.insert, table.remove, table.sort, etc.
// Cleaned from translate-c output of ltablib.c.

const std = @import("std");

const lua_State = opaque {};
const lua_Number = f64;
const lua_Integer = c_longlong;
const lua_Unsigned = c_ulonglong;
const lua_KContext = isize;
const lua_KFunction = ?*const fn (?*lua_State, c_int, lua_KContext) callconv(.c) c_int;
const lua_CFunction = ?*const fn (?*lua_State) callconv(.c) c_int;

const clock_t = i64;
const time_t = i64;

const luaL_Reg = extern struct {
    name: ?[*:0]const u8 = null,
    func: lua_CFunction = null,
};

// luaL_Buffer — must match struct layout from lauxlib.h so we can stack-allocate it.
const luaL_Buffer_initb = extern union {
    n: lua_Number,
    u: f64,
    s: ?*anyopaque,
    i: lua_Integer,
    l: c_long,
    b: [1024]u8,
};
const luaL_Buffer = extern struct {
    b: [*c]u8 = std.mem.zeroes([*c]u8),
    size: usize = std.mem.zeroes(usize),
    n: usize = std.mem.zeroes(usize),
    L: ?*lua_State = std.mem.zeroes(?*lua_State),
    init: luaL_Buffer_initb = std.mem.zeroes(luaL_Buffer_initb),
};

// Lua API
extern fn lua_gettop(L: ?*lua_State) c_int;
extern fn lua_settop(L: ?*lua_State, idx: c_int) void;
extern fn lua_pushvalue(L: ?*lua_State, idx: c_int) void;
extern fn lua_rotate(L: ?*lua_State, idx: c_int, n: c_int) void;
extern fn lua_checkstack(L: ?*lua_State, n: c_int) c_int;
extern fn lua_type(L: ?*lua_State, idx: c_int) c_int;
extern fn lua_typename(L: ?*lua_State, tp: c_int) [*:0]const u8;
extern fn lua_toboolean(L: ?*lua_State, idx: c_int) c_int;
extern fn lua_isstring(L: ?*lua_State, idx: c_int) c_int;
extern fn lua_compare(L: ?*lua_State, idx1: c_int, idx2: c_int, op: c_int) c_int;
extern fn lua_pushnil(L: ?*lua_State) void;
extern fn lua_pushinteger(L: ?*lua_State, n: lua_Integer) void;
extern fn lua_pushstring(L: ?*lua_State, s: [*:0]const u8) ?[*:0]const u8;
extern fn lua_pushlstring(L: ?*lua_State, s: [*]const u8, len: usize) ?[*:0]const u8;
extern fn lua_createtable(L: ?*lua_State, narr: c_int, nrec: c_int) void;
extern fn lua_getmetatable(L: ?*lua_State, objindex: c_int) c_int;
extern fn lua_rawget(L: ?*lua_State, idx: c_int) c_int;
extern fn lua_setfield(L: ?*lua_State, idx: c_int, k: [*:0]const u8) void;
extern fn lua_seti(L: ?*lua_State, idx: c_int, n: lua_Integer) void;
extern fn lua_geti(L: ?*lua_State, idx: c_int, n: lua_Integer) c_int;
extern fn lua_callk(L: ?*lua_State, nargs: c_int, nresults: c_int, ctx: lua_KContext, k: lua_KFunction) void;
extern fn clock() clock_t;
extern fn time(tloc: ?*time_t) time_t;
extern fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;

// Auxiliary library
extern fn luaL_checkversion_(L: ?*lua_State, ver: lua_Number, sz: usize) void;
extern fn luaL_argerror(L: ?*lua_State, arg: c_int, extramsg: [*:0]const u8) c_int;
extern fn luaL_error(L: ?*lua_State, fmt: [*:0]const u8, ...) c_int;
extern fn luaL_checkinteger(L: ?*lua_State, arg: c_int) lua_Integer;
extern fn luaL_optinteger(L: ?*lua_State, arg: c_int, def: lua_Integer) lua_Integer;
extern fn luaL_optlstring(L: ?*lua_State, arg: c_int, def: ?[*:0]const u8, l: ?*usize) ?[*:0]const u8;
extern fn luaL_checktype(L: ?*lua_State, arg: c_int, t: c_int) void;
extern fn luaL_len(L: ?*lua_State, idx: c_int) lua_Integer;
extern fn luaL_setfuncs(L: ?*lua_State, l: [*]const luaL_Reg, nup: c_int) void;
extern fn luaL_buffinit(L: ?*lua_State, B: *luaL_Buffer) void;
extern fn luaL_addlstring(B: *luaL_Buffer, s: [*]const u8, l: usize) void;
extern fn luaL_addvalue(B: *luaL_Buffer) void;
extern fn luaL_pushresult(B: *luaL_Buffer) void;

const IdxT = c_uint;

// TAB_R=1, TAB_W=2, TAB_L=4, TAB_RW=3, TAB_RWL=7
const TAB_R = 1;
const TAB_W = 2;
const TAB_L = 4;

pub export fn luaopen_table(L: ?*lua_State) callconv(.c) c_int {
    luaL_checkversion_(L, @floatFromInt(@as(c_int, 504)), @sizeOf(lua_Integer) *% 16 +% @sizeOf(lua_Number));
    lua_createtable(L, 0, @as(c_int, @intCast(tab_funcs.len - 1)));
    luaL_setfuncs(L, &tab_funcs, 0);
    return 1;
}

comptime {
    // asm (".section .yoink\n\tb\t\"lua_notice\"\n\t.previous");
}

fn checkfield(L: ?*lua_State, key: [*:0]const u8, n: c_int) c_int {
    _ = lua_pushstring(L, key);
    return @intFromBool(lua_rawget(L, -n) != 0);
}

fn checktab(L: ?*lua_State, arg: c_int, what: c_int) void {
    if (lua_type(L, arg) != 5) { // LUA_TTABLE
        var n: c_int = 1;
        if (lua_getmetatable(L, arg) != 0 and
            ((what & TAB_R) == 0 or checkfield(L, "__index", blk: {
            n += 1;
            break :blk n;
        }) != 0) and
            ((what & TAB_W) == 0 or checkfield(L, "__newindex", blk: {
            n += 1;
            break :blk n;
        }) != 0) and
            ((what & TAB_L) == 0 or checkfield(L, "__len", blk: {
            n += 1;
            break :blk n;
        }) != 0))
        {
            lua_settop(L, -n - 1);
        } else {
            luaL_checktype(L, arg, 5); // LUA_TTABLE
        }
    }
}

fn tinsert(L: ?*lua_State) callconv(.c) c_int {
    var pos: lua_Integer = undefined;
    var e: lua_Integer = blk: {
        checktab(L, 1, TAB_R | TAB_W | TAB_L);
        break :blk luaL_len(L, 1);
    };
    e +%= 1;
    switch (lua_gettop(L)) {
        2 => {
            pos = e;
        },
        3 => {
            pos = luaL_checkinteger(L, 2);
            _ = (@as(lua_Unsigned, @bitCast(pos)) -% 1 < @as(lua_Unsigned, @bitCast(e))) or
                (luaL_argerror(L, 2, "position out of bounds") != 0);
            var i: lua_Integer = e;
            while (i > pos) : (i -= 1) {
                _ = lua_geti(L, 1, i - 1);
                lua_seti(L, 1, i);
            }
        },
        else => {
            return luaL_error(L, "wrong number of arguments to 'insert'");
        },
    }
    lua_seti(L, 1, pos);
    return 0;
}

fn tremove(L: ?*lua_State) callconv(.c) c_int {
    const size: lua_Integer = blk: {
        checktab(L, 1, TAB_R | TAB_W | TAB_L);
        break :blk luaL_len(L, 1);
    };
    var pos: lua_Integer = luaL_optinteger(L, 2, size);
    if (pos != size) {
        _ = (@as(lua_Unsigned, @bitCast(pos)) -% 1 <= @as(lua_Unsigned, @bitCast(size))) or
            (luaL_argerror(L, 2, "position out of bounds") != 0);
    }
    _ = lua_geti(L, 1, pos);
    while (pos < size) : (pos += 1) {
        _ = lua_geti(L, 1, pos + 1);
        lua_seti(L, 1, pos);
    }
    lua_pushnil(L);
    lua_seti(L, 1, pos);
    return 1;
}

fn tmove(L: ?*lua_State) callconv(.c) c_int {
    const f: lua_Integer = luaL_checkinteger(L, 2);
    const e: lua_Integer = luaL_checkinteger(L, 3);
    const t: lua_Integer = luaL_checkinteger(L, 4);
    const tt: c_int = if (lua_type(L, 5) > 0) 5 else 1;
    checktab(L, 1, TAB_R);
    checktab(L, tt, TAB_W);
    if (e >= f) {
        var n: lua_Integer = undefined;
        _ = (f > 0 or e < (std.math.maxInt(i64) + f)) or
            (luaL_argerror(L, 3, "too many elements to move") != 0);
        n = (e - f) + 1;
        _ = (t <= (std.math.maxInt(i64) - n + 1)) or
            (luaL_argerror(L, 4, "destination wrap around") != 0);
        if ((t > e) or (t <= f) or (tt != 1 and lua_compare(L, 1, tt, 0) == 0)) {
            var i: lua_Integer = 0;
            while (i < n) : (i += 1) {
                _ = lua_geti(L, 1, f + i);
                lua_seti(L, tt, t + i);
            }
        } else {
            var i: lua_Integer = n - 1;
            while (i >= 0) : (i -= 1) {
                _ = lua_geti(L, 1, f + i);
                lua_seti(L, tt, t + i);
            }
        }
    }
    lua_pushvalue(L, tt);
    return 1;
}

fn addfield(L: ?*lua_State, b: *luaL_Buffer, i: lua_Integer) void {
    _ = lua_geti(L, 1, i);
    if (lua_isstring(L, -1) == 0) {
        _ = luaL_error(L, "invalid value (%s) at index %I in table for 'concat'", lua_typename(L, lua_type(L, -1)), @as(c_longlong, @bitCast(i)));
    }
    luaL_addvalue(b);
}

fn tconcat(L: ?*lua_State) callconv(.c) c_int {
    var b: luaL_Buffer = undefined;
    var last: lua_Integer = blk: {
        checktab(L, 1, TAB_R | TAB_L);
        break :blk luaL_len(L, 1);
    };
    var lsep: usize = undefined;
    const sep = luaL_optlstring(L, 2, "", &lsep);
    var i: lua_Integer = luaL_optinteger(L, 3, 1);
    last = luaL_optinteger(L, 4, last);
    luaL_buffinit(L, &b);
    while (i < last) : (i += 1) {
        addfield(L, &b, i);
        if (sep) |s| {
            luaL_addlstring(&b, s, lsep);
        }
    }
    if (i == last) {
        addfield(L, &b, i);
    }
    luaL_pushresult(&b);
    return 1;
}

fn tpack(L: ?*lua_State) callconv(.c) c_int {
    var i: c_int = undefined;
    const n: c_int = lua_gettop(L);
    lua_createtable(L, n, 1);
    lua_rotate(L, 1, 1);
    i = n;
    while (i >= 1) : (i -= 1) {
        lua_seti(L, 1, @intCast(i));
    }
    lua_pushinteger(L, @intCast(n));
    lua_setfield(L, 1, "n");
    return 1;
}

fn tunpack(L: ?*lua_State) callconv(.c) c_int {
    var n: lua_Unsigned = undefined;
    var i: lua_Integer = luaL_optinteger(L, 2, 1);
    const e: lua_Integer = if (lua_type(L, 3) > 0) luaL_checkinteger(L, 3) else luaL_len(L, 1);
    if (i > e) return 0;
    n = @as(lua_Unsigned, @bitCast(e)) -% @as(lua_Unsigned, @bitCast(i));
    if (n >= @as(lua_Unsigned, @intCast(@as(u32, 2147483647))) or lua_checkstack(L, @intCast(@as(c_uint, @truncate(blk: {
        n +%= 1;
        break :blk n;
    })))) == 0) return luaL_error(L, "too many results to unpack");
    while (i < e) : (i += 1) {
        _ = lua_geti(L, 1, i);
    }
    _ = lua_geti(L, 1, e);
    return @intCast(@as(c_uint, @truncate(n)));
}

fn l_randomizePivot() c_uint {
    const c = clock();
    const t = time(null);
    var buff: [4]c_uint = undefined;
    var rnd: c_uint = 0;
    _ = memcpy(@ptrCast(&buff), @ptrCast(&c), (@sizeOf(clock_t) / @sizeOf(c_uint)) * @sizeOf(c_uint));
    _ = memcpy(@ptrCast(@as([*]c_uint, @ptrCast(&buff)) + (@sizeOf(clock_t) / @sizeOf(c_uint))), @ptrCast(&t), (@sizeOf(time_t) / @sizeOf(c_uint)) * @sizeOf(c_uint));
    var i: c_uint = 0;
    while (i < @sizeOf([4]c_uint) / @sizeOf(c_uint)) : (i +%= 1) {
        rnd +%= buff[i];
    }
    return rnd;
}

fn set2(L: ?*lua_State, i: IdxT, j: IdxT) void {
    lua_seti(L, 1, @bitCast(@as(c_ulonglong, i)));
    lua_seti(L, 1, @bitCast(@as(c_ulonglong, j)));
}

fn sort_comp(L: ?*lua_State, a: c_int, b: c_int) c_int {
    if (lua_type(L, 2) == 0) { // LUA_TNIL — no comparison function
        return lua_compare(L, a, b, 1); // LUA_OPLT
    } else {
        lua_pushvalue(L, 2);
        lua_pushvalue(L, a - 1);
        lua_pushvalue(L, b - 2);
        lua_callk(L, 2, 1, 0, null);
        const res = lua_toboolean(L, -1);
        lua_settop(L, -2); // pop result
        return res;
    }
}

fn partition(L: ?*lua_State, lo_arg: IdxT, up: IdxT) IdxT {
    var i: IdxT = lo_arg;
    var j: IdxT = up -% 1;
    while (true) {
        // move i forward while a[i] < pivot
        while (blk: {
            i +%= 1;
            _ = lua_geti(L, 1, @bitCast(@as(c_ulonglong, i)));
            break :blk sort_comp(L, -1, -2) != 0;
        }) {
            if (i == up -% 1) {
                _ = luaL_error(L, "invalid order function for sorting");
            }
            lua_settop(L, -2); // pop a[i]
        }
        // move j backward while pivot < a[j]
        while (blk: {
            j -%= 1;
            _ = lua_geti(L, 1, @bitCast(@as(c_ulonglong, j)));
            break :blk sort_comp(L, -3, -1) != 0;
        }) {
            if (j < i) {
                _ = luaL_error(L, "invalid order function for sorting");
            }
            lua_settop(L, -2); // pop a[j]
        }
        if (j < i) {
            lua_settop(L, -2); // pop a[j]
            set2(L, up -% 1, i);
            return i;
        }
        set2(L, i, j);
    }
    return 0; // unreachable
}

fn choosePivot(lo: IdxT, up: IdxT, rnd: c_uint) IdxT {
    const r4: IdxT = (up -% lo) / 4;
    return (rnd % (r4 *% 2)) +% (lo +% r4);
}

fn auxsort(L: ?*lua_State, lo_arg: IdxT, up_arg: IdxT, rnd_arg: c_uint) void {
    var lo = lo_arg;
    var up = up_arg;
    var rnd = rnd_arg;
    while (lo < up) {
        var p: IdxT = undefined;
        var n: IdxT = undefined;
        _ = lua_geti(L, 1, @bitCast(@as(c_ulonglong, lo)));
        _ = lua_geti(L, 1, @bitCast(@as(c_ulonglong, up)));
        if (sort_comp(L, -1, -2) != 0) {
            set2(L, lo, up);
        } else {
            lua_settop(L, -3); // pop both
        }
        if (up -% lo == 1) return;
        if (up -% lo < 100 or rnd == 0) {
            p = (lo +% up) / 2;
        } else {
            p = choosePivot(lo, up, rnd);
        }
        _ = lua_geti(L, 1, @bitCast(@as(c_ulonglong, p)));
        _ = lua_geti(L, 1, @bitCast(@as(c_ulonglong, lo)));
        if (sort_comp(L, -2, -1) != 0) {
            set2(L, p, lo);
        } else {
            lua_settop(L, -2); // pop a[lo]
            _ = lua_geti(L, 1, @bitCast(@as(c_ulonglong, up)));
            if (sort_comp(L, -1, -2) != 0) {
                set2(L, p, up);
            } else {
                lua_settop(L, -3); // pop both
            }
        }
        if (up -% lo == 2) return;
        _ = lua_geti(L, 1, @bitCast(@as(c_ulonglong, p)));
        lua_pushvalue(L, -1);
        _ = lua_geti(L, 1, @bitCast(@as(c_ulonglong, up -% 1)));
        set2(L, p, up -% 1);
        p = partition(L, lo, up);
        if (p -% lo < up -% p) {
            auxsort(L, lo, p -% 1, rnd);
            n = p -% lo;
            lo = p +% 1;
        } else {
            auxsort(L, p +% 1, up, rnd);
            n = up -% p;
            up = p -% 1;
        }
        if ((up -% lo) / 128 > n) {
            rnd = l_randomizePivot();
        }
    }
}

fn sort(L: ?*lua_State) callconv(.c) c_int {
    checktab(L, 1, TAB_R | TAB_W | TAB_L);
    const n: lua_Integer = luaL_len(L, 1);
    if (n > 1) {
        _ = (n < 2147483647) or (luaL_argerror(L, 1, "array too big") != 0);
        if (lua_type(L, 2) > 0) { // comparison function given
            luaL_checktype(L, 2, 6); // LUA_TFUNCTION
        }
        lua_settop(L, 2);
        auxsort(L, 1, @intCast(@as(c_uint, @truncate(@as(c_ulonglong, @bitCast(n))))), 0);
    }
    return 0;
}

const tab_funcs = [_]luaL_Reg{
    .{ .name = "concat", .func = &tconcat },
    .{ .name = "insert", .func = &tinsert },
    .{ .name = "pack", .func = &tpack },
    .{ .name = "unpack", .func = &tunpack },
    .{ .name = "remove", .func = &tremove },
    .{ .name = "move", .func = &tmove },
    .{ .name = "sort", .func = &sort },
    .{ .name = null, .func = null }, // sentinel
};
