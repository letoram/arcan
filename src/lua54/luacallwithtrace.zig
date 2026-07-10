// LuaCallWithTrace — call Lua code with full traceback on error.
// Cleaned from translate-c output of luacallwithtrace.c.

const std = @import("std");
const lua_State = opaque {};
const lua_Integer = c_longlong;
const lua_KContext = isize;
const lua_KFunction = ?*const fn (?*lua_State, c_int, lua_KContext) callconv(.c) c_int;

extern fn lua_newthread(L: ?*lua_State) ?*lua_State;
extern fn lua_gettop(L: ?*lua_State) c_int;
extern fn lua_settop(L: ?*lua_State, idx: c_int) void;
extern fn lua_pushvalue(L: ?*lua_State, idx: c_int) void;
extern fn lua_rotate(L: ?*lua_State, idx: c_int, n: c_int) void;
extern fn lua_checkstack(L: ?*lua_State, n: c_int) c_int;
extern fn lua_xmove(from: ?*lua_State, to: ?*lua_State, n: c_int) void;
extern fn lua_type(L: ?*lua_State, idx: c_int) c_int;
extern fn lua_typename(L: ?*lua_State, tp: c_int) [*:0]const u8;
extern fn lua_tolstring(L: ?*lua_State, idx: c_int, len: ?*usize) ?[*:0]const u8;
extern fn lua_pushnil(L: ?*lua_State) void;
extern fn lua_pushstring(L: ?*lua_State, s: [*:0]const u8) ?[*:0]const u8;
extern fn lua_pushfstring(L: ?*lua_State, fmt: [*:0]const u8, ...) ?[*:0]const u8;
extern fn lua_resume(L: ?*lua_State, from: ?*lua_State, narg: c_int, nres: *c_int) c_int;
extern fn luaL_callmeta(L: ?*lua_State, obj: c_int, e: [*:0]const u8) c_int;
extern fn luaL_traceback2(L: ?*lua_State, L1: ?*lua_State, msg: ?[*:0]const u8, level: c_int) void;

pub export fn LuaCallWithTrace(arg_L: ?*lua_State, arg_nargs: c_int, arg_nres: c_int, arg_C: ?*lua_State) c_int {
    const L = arg_L;
    const nargs = arg_nargs;
    const nres = arg_nres;
    var C = arg_C;
    var nresults: c_int = undefined;
    var status: c_int = undefined;
    const canyield: bool = C != null;
    if (C == null) {
        C = lua_newthread(L);
    }
    lua_rotate(L, 1, 1);
    if (lua_checkstack(C, 1 + nargs) == 0) {
        _ = lua_pushstring(L, "too many arguments to resume");
        return 2;
    }
    lua_xmove(L, C, 1 + nargs);
    status = lua_resume(C, L, nargs, &nresults);
    if (!canyield) {
        // pop the thread
        lua_rotate(L, 1, -1);
        lua_settop(L, -2);
    }
    if (status != 0 and status != 1) {
        lua_xmove(C, L, 1);
        expanderr(L);
        luaL_traceback2(L, C, lua_tolstring(L, -1, null), 0);
        // remove original error, keep traceback
        lua_rotate(L, -2, -1);
        lua_settop(L, -2);
    } else {
        if (lua_checkstack(L, if (nres < nresults) nresults else nres) == 0) {
            lua_settop(C, -nresults - 1);
            _ = lua_pushstring(L, "too many results to resume");
            return 2;
        }
        lua_xmove(C, L, nresults);
        while (nresults < nres) : (nresults += 1) {
            lua_pushnil(L);
        }
        if (!canyield) {
            status = 0;
        }
    }
    return status;
}

pub export fn expanderr(arg_L: ?*lua_State) void {
    const L = arg_L;
    if (lua_tolstring(L, -1, null) == null) {
        if (luaL_callmeta(L, -1, "__tostring") != 0) {
            if (lua_type(L, -1) != 4) { // LUA_TSTRING
                {
                    var fmtbuf: [512]u8 = undefined;
                    const result = std.fmt.bufPrintZ(&fmtbuf, "(error object returned a {s} value)", .{
                        std.mem.span(lua_typename(L, lua_type(L, -1))),
                    }) catch "(error object returned a ? value)";
                    _ = lua_pushstring(L, result);
                }
                // remove __tostring result
                lua_rotate(L, -2, -1);
                lua_settop(L, -2);
            }
        } else {
            var fmtbuf: [512]u8 = undefined;
            const result = std.fmt.bufPrintZ(&fmtbuf, "(error object is a {s} value)", .{
                std.mem.span(lua_typename(L, lua_type(L, -1))),
            }) catch "(error object is a ? value)";
            _ = lua_pushstring(L, result);
        }
        // remove original error object
        lua_rotate(L, -2, -1);
        lua_settop(L, -2);
    }
}
