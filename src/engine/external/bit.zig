///
/// Lua BitOp -- a bit operations library for Lua 5.1/5.2.
/// http://bitop.luajit.org/
///
/// Copyright (C) 2008-2012 Mike Pall. All rights reserved.
///
/// Permission is hereby granted, free of charge, to any person obtaining
/// a copy of this software and associated documentation files (the
/// "Software"), to deal in the Software without restriction, including
/// without limitation the rights to use, copy, modify, merge, publish,
/// distribute, sublicense, and/or sell copies of the Software, and to
/// permit persons to whom the Software is furnished to do so, subject to
/// the following conditions:
///
/// The above copyright notice and this permission notice shall be
/// included in all copies or substantial portions of the Software.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
/// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
/// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
/// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
/// CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
/// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
/// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
///
/// [ MIT license: http://www.opensource.org/licenses/mit-license.php ]
///
/// Zig port of bit.c for the arcan project.
///

const std = @import("std");

const lua = @import("lua_api");

const SBits = i32;
const UBits = u32;

/// Union for converting lua_Number (double) to bit representation.
/// Uses the standard 2^52+2^51 trick to round a double to an integer
/// and then extract the low 32 bits.
const BitNum = extern union {
    n: lua.lua_Number,
    b: u64,
};

/// Convert a Lua argument at stack index `idx` to a UBits (u32).
fn barg(L: ?*lua.lua_State, idx: c_int) UBits {
    var bn: BitNum = undefined;
    bn.n = lua.lua_tonumber(L, idx);

    // lua_Number is double: add magic constant 2^52+2^51 to snap to integer,
    // then extract the low 32 bits from the IEEE 754 representation.
    bn.n += 6755399441055744.0; // 2^52 + 2^51
    const b: UBits = @truncate(bn.b);

    // Lua 5.1: if result is 0 and arg wasn't a number, raise type error
    if (b == 0 and lua.lua_isnumber(L, idx) == 0) {
        _ = lua.luaL_typerror(L, idx, "number");
    }
    return b;
}

/// Push result: cast UBits to SBits (signed), then to lua_Number.
inline fn bret(L: ?*lua.lua_State, b: UBits) c_int {
    lua.lua_pushnumber(L, @as(lua.lua_Number, @floatFromInt(@as(SBits, @bitCast(b)))));
    return 1;
}

// --- Bit operations ---

fn bit_tobit(L: ?*lua.lua_State) callconv(.c) c_int {
    return bret(L, barg(L, 1));
}

fn bit_bnot(L: ?*lua.lua_State) callconv(.c) c_int {
    return bret(L, ~barg(L, 1));
}

/// Variadic AND: fold all arguments with &
fn bit_band(L: ?*lua.lua_State) callconv(.c) c_int {
    var b = barg(L, 1);
    var i = lua.lua_gettop(L);
    while (i > 1) : (i -= 1) {
        b &= barg(L, i);
    }
    return bret(L, b);
}

/// Variadic OR: fold all arguments with |
fn bit_bor(L: ?*lua.lua_State) callconv(.c) c_int {
    var b = barg(L, 1);
    var i = lua.lua_gettop(L);
    while (i > 1) : (i -= 1) {
        b |= barg(L, i);
    }
    return bret(L, b);
}

/// Variadic XOR: fold all arguments with ^
fn bit_bxor(L: ?*lua.lua_State) callconv(.c) c_int {
    var b = barg(L, 1);
    var i = lua.lua_gettop(L);
    while (i > 1) : (i -= 1) {
        b ^= barg(L, i);
    }
    return bret(L, b);
}

/// Logical left shift
fn bit_lshift(L: ?*lua.lua_State) callconv(.c) c_int {
    const b = barg(L, 1);
    const n: u5 = @truncate(barg(L, 2) & 31);
    return bret(L, b << n);
}

/// Logical right shift
fn bit_rshift(L: ?*lua.lua_State) callconv(.c) c_int {
    const b = barg(L, 1);
    const n: u5 = @truncate(barg(L, 2) & 31);
    return bret(L, b >> n);
}

/// Arithmetic right shift (sign-extending)
fn bit_arshift(L: ?*lua.lua_State) callconv(.c) c_int {
    const b = barg(L, 1);
    const n: u5 = @truncate(barg(L, 2) & 31);
    const sb: SBits = @bitCast(b);
    const result: UBits = @bitCast(sb >> n);
    return bret(L, result);
}

/// Rotate left
fn bit_rol(L: ?*lua.lua_State) callconv(.c) c_int {
    const b = barg(L, 1);
    const n: u5 = @truncate(barg(L, 2) & 31);
    return bret(L, std.math.rotl(UBits, b, n));
}

/// Rotate right
fn bit_ror(L: ?*lua.lua_State) callconv(.c) c_int {
    const b = barg(L, 1);
    const n: u5 = @truncate(barg(L, 2) & 31);
    return bret(L, std.math.rotr(UBits, b, n));
}

/// Byte swap (reverse endianness)
fn bit_bswap(L: ?*lua.lua_State) callconv(.c) c_int {
    const b = barg(L, 1);
    return bret(L, @byteSwap(b));
}

/// Convert to hex string. Optional second arg is number of hex digits (negative = uppercase).
fn bit_tohex(L: ?*lua.lua_State) callconv(.c) c_int {
    var b = barg(L, 1);
    var n: SBits = if (lua.lua_type(L, 2) == lua.LUA_TNONE) 8 else @bitCast(barg(L, 2));
    const hexdigits: [*]const u8 = if (n < 0) "0123456789ABCDEF" else "0123456789abcdef";
    if (n < 0) n = -n;
    if (n > 8) n = 8;
    var buf: [8]u8 = undefined;
    const len: usize = @intCast(n);
    var i: usize = len;
    while (i > 0) {
        i -= 1;
        buf[i] = hexdigits[@as(usize, b & 15)];
        b >>= 4;
    }
    _ = lua.lua_pushlstring(L, &buf, len);
    return 1;
}

// --- Function registration table ---

const bit_funcs = [_]lua.luaL_Reg{
    .{ .name = "tobit", .func = bit_tobit },
    .{ .name = "bnot", .func = bit_bnot },
    .{ .name = "band", .func = bit_band },
    .{ .name = "bor", .func = bit_bor },
    .{ .name = "bxor", .func = bit_bxor },
    .{ .name = "lshift", .func = bit_lshift },
    .{ .name = "rshift", .func = bit_rshift },
    .{ .name = "arshift", .func = bit_arshift },
    .{ .name = "rol", .func = bit_rol },
    .{ .name = "ror", .func = bit_ror },
    .{ .name = "bswap", .func = bit_bswap },
    .{ .name = "tohex", .func = bit_tohex },
    .{ .name = null, .func = null },
};

// --- Entry point ---

/// Library open function. Exported as arcan_luaopen_bit to avoid symbol
/// conflict with LuaJIT's built-in luaopen_bit.
export fn arcan_luaopen_bit(L: ?*lua.lua_State) callconv(.c) c_int {
    // Self-test: push a known number, convert via barg, verify round-trip.
    lua.lua_pushnumber(L, @as(lua.lua_Number, 1437217655.0));
    const b = barg(L, -1);

    // Arithmetic right shift sanity check: (-8) >> 2 must be -2
    const bad_sar = (@as(SBits, -8) >> 2) != @as(SBits, -2);

    if (b != 1437217655 or bad_sar) {
        var msg: [*c]const u8 = "compiled with incompatible luaconf.h";
        if (b == 1127743488) {
            msg = "not compiled with SWAPPED_DOUBLE";
        }
        if (bad_sar) {
            msg = "arithmetic right-shift broken";
        }
        _ = lua.luaL_error(L, "bit library self-test failed (%s)", msg);
    }
    lua.lua_settop(L, -1 - 1); // lua_pop(L, 1)

    // Lua 5.1: luaL_register creates/populates the "bit" global table
    lua.luaL_register(L, "bit", &bit_funcs);
    return 1;
}
