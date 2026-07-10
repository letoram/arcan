// Zig port of engine/arcan_lua.c — Lua scripting bindings for the arcan compositor.
// ~280 Lua binding functions exposing the engine API to Lua scripts.
//
// Ported from C using zig translate-c as reference, with manual cleanup.
// All platforms use arcan_boot_compat module for types, constants, and extern fn
// declarations (pure Zig, no @cImport of arcan C headers). Lua and libc functions
// are declared as extern fn in boot_compat and link to real libraries on POSIX.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = builtin.os.tag == .freestanding;

// All types, constants, and function declarations — pure Zig, no @cImport of arcan C headers.
// arcan_boot_compat provides: arcan types/constants/extern fns, Lua API (extern fn + inline wrappers),
// and system libc functions (extern fn). On freestanding, Lua stubs return 0/null; on POSIX,
// extern fn declarations link to the real LuaJIT and libc at link time.
pub const c = @import("arcan_boot_compat");

// Type aliases for brevity
const lua_State = c.lua_State;
const luaL_Reg = c.luaL_Reg;
const arcan_vobj_id = c.arcan_vobj_id;
const arcan_aobj_id = c.arcan_aobj_id;
const arcan_event = c.arcan_event;
const lua_Number = c.lua_Number;

// External symbols from other engine modules
extern var lua_vid_base: c_uint;
extern var lua_debug_level: c_uint;
extern var vcontext_ind: c_uint;
// vcontext_stack is exported in arcan_video.zig as
// `[CONTEXT_STACK_LIMIT]c.struct_arcan_video_context` (a static array).
// Declaring it here as `[*c]…` (pointer-to-context) was wrong — every
// `vcontext_stack[i]` reading 8 bytes from the first struct field as a
// pointer base, then indexing — producing garbage like 0x400000000ab and
// SIGSEGVing the state-dump and cbdrop walkers (bug 0007).
extern var vcontext_stack: [c.CONTEXT_STACK_LIMIT]c.arcan_video_context;

extern fn _n_strdup(instr: [*c]const u8, alt: [*c]const u8) [*c]u8;

// STB Perlin noise — on POSIX: resolved at link time against the C stub
// src/engine/external/stb_perlin_impl.c (STB_PERLIN_IMPLEMENTATION); on
// freestanding: inline stub returning 0.
const stb_perlin = if (is_freestanding) struct {
    pub fn stb_perlin_fbm_noise3(_: f32, _: f32, _: f32, _: f32, _: f32, _: c_int) f32 {
        return 0;
    }
} else struct {
    pub extern fn stb_perlin_fbm_noise3(
        x: f32, y: f32, z: f32,
        lacunarity: f32, gain: f32,
        octaves: c_int,
    ) f32;
};
fn stb_perlin_fbm_noise3(x: f32, y: f32, z: f32, lacunarity: f32, gain_val: f32, octaves: c_int) f32 {
    return stb_perlin.stb_perlin_fbm_noise3(x, y, z, lacunarity, gain_val, octaves);
}

// Module-level state
var fsrv_ok: c_int = 1;

const MOUSE_GRAB_ON: c_int = 20;
const MOUSE_GRAB_OFF: c_int = 21;

const MAX_SURFACEH: c_int = 4096;
const MAX_SURFACEW: c_int = 8192;

const FRAMESET_NODETACH: c_int = 11;
const FRAMESET_DETACH: c_int = 10;

const RENDERTARGET_DETACH: c_int = 20;
const RENDERTARGET_NODETACH: c_int = 21;
const RENDERTARGET_SCALE: c_int = 30;
const RENDERTARGET_NOSCALE: c_int = 31;

const RENDERFMT_COLOR: c_int = c.RENDERTARGET_COLOR;
const RENDERFMT_DEPTH: c_int = c.RENDERTARGET_DEPTH;
const RENDERFMT_FULL: c_int = c.RENDERTARGET_COLOR_DEPTH_STENCIL;
const RENDERFMT_MSAA: c_int = c.RENDERTARGET_MSAA;
const RENDERFMT_RETAIN_ALPHA: c_int = c.RENDERTARGET_RETAIN_ALPHA;

const DEVICE_INDIRECT: c_int = 1;
const DEVICE_DIRECT: c_int = 2;
const DEVICE_LOST: c_int = 3;

const ANCHORHINT_SEGMENT: c_int = 10;
const ANCHORHINT_EXTERNAL: c_int = 11;
const ANCHORHINT_PROXY: c_int = 12;
const ANCHORHINT_PROXY_EXTERNAL: c_int = 13;

const FATAL_MSG_FRAMESERV = "specified destination is not a frameserver.\n";

const luactx_state = struct {
    rawres: c.nonblock_io = std.mem.zeroes(c.nonblock_io),
    grab: u8 = 0,
    prefix_buf: [*c]u8 = null,
    prefix_ofs: usize = 0,
    pending_segpush: [*c]c.arcan_shmif_cont = null,
    last_segreq: [*c]c.arcan_extevent = null,
    pending_socket_label: [*c]u8 = null,
    pending_socket_descr: c_int = 0,
    last_argv: [*c][*c]const u8 = null,
    last_ctx: ?*lua_State = null,
    error_hook: ?*const fn (?*lua_State, [*c]c.lua_Debug) callconv(.c) void = null,
    worldid_tag: isize = 0,
    last_clock: usize = 0,
};

var luactx: luactx_state = .{};

// Vector/point field access helpers
// vector/point/scalefactor in C is struct{union{struct{x,y,z};xyz[3]}}
// Zig's @cImport maps this to .unnamed_0.unnamed_0.{x,y,z}
// boot_compat matches this structure for compat
inline fn vecx(v: c.vector) f32 { return v.unnamed_0.unnamed_0.x; }
inline fn vecy(v: c.vector) f32 { return v.unnamed_0.unnamed_0.y; }
inline fn vecz(v: c.vector) f32 { return v.unnamed_0.unnamed_0.z; }
inline fn vecxp(v: *c.vector) *f32 { return &v.unnamed_0.unnamed_0.x; }
inline fn vecyp(v: *c.vector) *f32 { return &v.unnamed_0.unnamed_0.y; }
inline fn veczp(v: *c.vector) *f32 { return &v.unnamed_0.unnamed_0.z; }

// Inline Lua helpers (macros in C)
inline fn DBHANDLE() ?*c.arcan_dbh {
    return c.arcan_db_get_shared(null);
}

fn lua_pushvid(ctx: ?*lua_State, id: arcan_vobj_id) void {
    var vid = id;
    if (vid != c.ARCAN_EID and vid != c.ARCAN_VIDEO_WORLDID)
        vid += @as(arcan_vobj_id, @intCast(lua_vid_base));
    c.lua_pushnumber(ctx, @floatFromInt(vid));
}

fn lua_pushaid(ctx: ?*lua_State, id: arcan_aobj_id) void {
    c.lua_pushnumber(ctx, @floatFromInt(id));
}

fn luaL_checkaid(ctx: ?*lua_State, num: c_int) arcan_vobj_id {
    return @intFromFloat(c.luaL_checknumber(ctx, num));
}

fn luaL_checkvid(ctx: ?*lua_State, num: c_int, dst: ?*[*c]c.arcan_vobject) arcan_vobj_id {
    const lnum: arcan_vobj_id = @intFromFloat(c.luaL_checknumber(ctx, num));
    const id = c.luavid_tovid(@floatFromInt(lnum));
    if (dst) |d| {
        d.* = c.arcan_video_getobject(id);
        if (d.* == null)
            c.arcan_fatal("luaL_checkvid() failed, invalid vid (%lld)\n", @as(c_longlong, id));
    }
    return id;
}

fn luaL_checkbnumber(ctx: ?*lua_State, ind: c_int) bool {
    return c.lua_toboolean(ctx, ind) != 0;
}

fn luaL_optbnumber(ctx: ?*lua_State, ind: c_int, dfl: bool) bool {
    if (c.lua_isnumber(ctx, ind) != 0)
        return c.lua_tonumber(ctx, ind) != 0
    else if (c.lua_isboolean(ctx, ind))
        return c.lua_toboolean(ctx, ind) != 0
    else
        return dfl;
}

fn luaL_optnumber_alt(ctx: ?*lua_State, ind: c_int, dfl: f64) f64 {
    if (c.lua_type(ctx, ind) == c.LUA_TNUMBER)
        return c.lua_tonumber(ctx, ind);
    return dfl;
}

fn luaL_checkint(ctx: ?*lua_State, ind: c_int) c_int {
    return @intFromFloat(c.luaL_checknumber(ctx, ind));
}

fn luaL_optint(ctx: ?*lua_State, ind: c_int, dfl: c_int) c_int {
    if (c.lua_type(ctx, ind) == c.LUA_TNUMBER) {
        const n = c.lua_tonumber(ctx, ind);
        if (n != n or n > 2147483647.0 or n < -2147483648.0) return dfl; // NaN/overflow
        return @intFromFloat(n);
    }
    return dfl;
}

// intbl helpers — read fields from Lua tables
fn intblstr(ctx: ?*lua_State, ind: c_int, field: [*c]const u8) [*c]const u8 {
    _ = c.lua_getfield(ctx, ind, field);
    const rv = c.lua_tolstring(ctx, -1, null);
    c.lua_settop(ctx, -(1) - 1);
    return rv;
}

fn intblfloat(ctx: ?*lua_State, ind: c_int, field: [*c]const u8) f32 {
    _ = c.lua_getfield(ctx, ind, field);
    const rv: f32 = @floatCast(c.lua_tonumber(ctx, -1));
    c.lua_settop(ctx, -(1) - 1);
    return rv;
}

fn intblint(ctx: ?*lua_State, ind: c_int, field: [*c]const u8) c_int {
    _ = c.lua_getfield(ctx, ind, field);
    const rv: c_int = @intFromFloat(c.lua_tonumber(ctx, -1));
    c.lua_settop(ctx, -(1) - 1);
    return rv;
}

fn intblint_checked(ctx: ?*lua_State, ind: c_int, field: [*c]const u8, ok: *bool) c_int {
    _ = c.lua_getfield(ctx, ind, field);
    ok.* = c.lua_type(ctx, -1) == c.LUA_TNUMBER;
    const rv: c_int = @intFromFloat(c.lua_tonumber(ctx, -1));
    c.lua_settop(ctx, -(1) - 1);
    return rv;
}

fn intblbool(ctx: ?*lua_State, ind: c_int, field: [*c]const u8) bool {
    _ = c.lua_getfield(ctx, ind, field);
    const rv = c.lua_toboolean(ctx, -1) != 0;
    c.lua_settop(ctx, -(1) - 1);
    return rv;
}

// set_tbl helpers — set fields on Lua tables
fn set_tblstr(ctx: ?*lua_State, key: [*c]const u8, val: [*c]const u8, top: c_int) void {
    c.lua_pushstring(ctx, key);
    c.lua_pushstring(ctx, val);
    c.lua_rawset(ctx, top);
}

fn set_tbldynstr(ctx: ?*lua_State, key: [*c]const u8, val: [*c]const u8, top: c_int) void {
    c.lua_pushstring(ctx, key);
    c.lua_pushstring(ctx, val);
    c.lua_rawset(ctx, top);
}

fn set_tblnum(ctx: ?*lua_State, key: [*c]const u8, val: f64, top: c_int) void {
    c.lua_pushstring(ctx, key);
    c.lua_pushnumber(ctx, val);
    c.lua_rawset(ctx, top);
}

fn set_tblbool(ctx: ?*lua_State, key: [*c]const u8, val: bool, top: c_int) void {
    c.lua_pushstring(ctx, key);
    c.lua_pushboolean(ctx, @intFromBool(val));
    c.lua_rawset(ctx, top);
}

fn set_tblint(ctx: ?*lua_State, key: [*c]const u8, val: c_int, top: c_int) void {
    c.lua_pushstring(ctx, key);
    c.lua_pushnumber(ctx, @floatFromInt(val));
    c.lua_rawset(ctx, top);
}


// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part1.zig
// ══════════════════════════════════════════════════════════════════════

// === Section 0: Helpers ===
//
// Helper functions from arcan_lua.c lines ~295-995 and scattered utility
// functions used throughout the Lua bindings.
//
// Assumes the caller provides:
//   type aliases: lua_State, arcan_vobj_id, arcan_aobj_id, arcan_event
//   extern var lua_vid_base: c_uint;
//   extern var lua_debug_level: c_uint;


// ---------------------------------------------------------------------------
// 1. colon_escape (C:303-311) — replace ':' with '\t' in-place
// ---------------------------------------------------------------------------
fn colon_escape(in: [*c]u8) [*c]u8 {
    var instr = in;
    while (instr[0] != 0) {
        if (instr[0] == ':')
            instr[0] = '\t';
        instr += 1;
    }
    return in;
}

// ---------------------------------------------------------------------------
// 2. find_lua_callback (C:315-327) — scan stack for first Lua function
// ---------------------------------------------------------------------------
fn find_lua_callback(ctx: ?*lua_State) isize {
    const nargs = c.lua_gettop(ctx);

    var i: usize = 1;
    while (i <= @as(usize, @intCast(nargs))) : (i += 1) {
        const idx = @as(c_int, @intCast(i));
        if (c.lua_type(ctx, idx) == c.LUA_TFUNCTION and c.lua_iscfunction(ctx, idx) == 0) {
            c.lua_pushvalue(ctx, idx);
            const ref: isize = @intCast(c.luaL_ref(ctx, c.LUA_REGISTRYINDEX));
            return ref;
        }
    }

    return @as(isize, c.LUA_NOREF);
}

// ---------------------------------------------------------------------------
// 3. find_lua_type (C:329-341) — scan stack for nth value of given type
// ---------------------------------------------------------------------------
fn find_lua_type(ctx: ?*lua_State, typ: c_int, ofs_arg: c_int) c_int {
    const nargs = c.lua_gettop(ctx);
    var ofs = ofs_arg;

    var i: usize = 1;
    while (i <= @as(usize, @intCast(nargs))) : (i += 1) {
        const idx = @as(c_int, @intCast(i));
        const ltype = c.lua_type(ctx, idx);
        if (ltype == typ) {
            if (ofs == 0)
                return idx;
            ofs -= 1;
        }
    }

    return 0;
}

// ---------------------------------------------------------------------------
// 4. luaL_lastcaller (C:343-354) — debug info, uses file-scope static buffer
// ---------------------------------------------------------------------------
var lastcaller_msg: [1024]u8 = std.mem.zeroes([1024]u8);

fn luaL_lastcaller(ctx: ?*lua_State) [*c]const u8 {
    lastcaller_msg[1023] = 0;

    var dbg: c.lua_Debug = undefined;
    _ = c.lua_getstack(ctx, 1, &dbg);
    _ = c.lua_getinfo(ctx, "nlS", &dbg);
    _ = c.snprintf(
        @as([*c]u8, @ptrCast(&lastcaller_msg)),
        1023,
        "%s:%d",
        @as([*c]u8, @ptrCast(&dbg.short_src)),
        dbg.currentline,
    );

    return @as([*c]const u8, @ptrCast(&lastcaller_msg));
}

// ---------------------------------------------------------------------------
// 5. trace_allocation (C:356-361) — conditional warning on alloc
// ---------------------------------------------------------------------------
fn trace_allocation(ctx: ?*lua_State, sym: [*c]const u8, id: arcan_vobj_id) void {
    if (lua_debug_level > 2) {
        c.arcan_warning(
            @as([*c]const u8, "\x1b[1m %s: alloc(%s) => %lld)\x1b[39m\x1b[0m\n"),
            luaL_lastcaller(ctx),
            sym,
            @as(c_longlong, id + @as(arcan_vobj_id, @intCast(lua_vid_base))),
        );
    }
}

// ---------------------------------------------------------------------------
// 6. trace_coverage (C:363-424) — coverage tracing to file, static FILE* state
// ---------------------------------------------------------------------------
var trace_coverage_outf: ?*c.FILE = null;
var trace_coverage_init: bool = false;

fn trace_coverage(fsym: [*c]const u8, ctx: ?*lua_State) void {
    // retry loop replaces goto retry
    while (true) {
        if (trace_coverage_outf == null and trace_coverage_init)
            return;

        if (trace_coverage_outf == null) {
            trace_coverage_init = true;
            const fname = c.arcan_expand_resource(
                @as([*c]const u8, "arcan.coverage"),
                @as(c_uint, @bitCast(c.RESOURCE_SYS_DEBUG)),
            );

            if (fname == null)
                return;

            trace_coverage_outf = c.fopen(fname, "w+");
            c.arcan_mem_free(@as(?*anyopaque, @ptrCast(fname)));
            continue; // retry
        }

        break;
    }

    const outf = trace_coverage_outf.?;
    _ = c.fprintf(outf, "%llu;%s;", c.arcan_timemillis(), fsym);

    const top = c.lua_gettop(ctx);
    var i: usize = 1;
    while (i <= @as(usize, @intCast(top))) : (i += 1) {
        const idx = @as(c_int, @intCast(i));
        const t = c.lua_type(ctx, idx);
        switch (t) {
            c.LUA_TBOOLEAN => _ = c.fputs("bool;", outf),
            c.LUA_TNIL => _ = c.fputs("nil;", outf),
            c.LUA_TLIGHTUSERDATA => _ = c.fputs("lightud;", outf),
            c.LUA_TTABLE => _ = c.fputs("table;", outf),
            c.LUA_TUSERDATA => _ = c.fputs("ud;", outf),
            c.LUA_TTHREAD => _ = c.fputs("thread;", outf),
            c.LUA_TSTRING => _ = c.fputs("str;", outf),
            c.LUA_TNUMBER => _ = c.fputs("num;", outf),
            c.LUA_TFUNCTION => _ = c.fputs("fptr;", outf),
            else => _ = c.fputs("unt;", outf),
        }
    }

    _ = c.fputc(@as(c_int, '\n'), outf);
}

// ---------------------------------------------------------------------------
// 7. findresource (C:557-574) — wraps arcan_find_resource with debug logging
// ---------------------------------------------------------------------------
fn findresource(
    arg: [*c]const u8,
    space: c_uint,
    typ: c_uint,
    fd: [*c]c_int,
) [*c]u8 {
    const res = c.arcan_find_resource(arg, space, typ, fd);

    if (lua_debug_level != 0) {
        c.arcan_warning(
            @as([*c]const u8, "find_resource:ns=%d:type=%d:%s=%s\n"),
            @as(c_int, @bitCast(space)),
            @as(c_int, @bitCast(typ)),
            arg,
            if (res != null) res else @as([*c]const u8, "[null]"),
        );
    }

    return res;
}

// ---------------------------------------------------------------------------
// 8. alua_doresolve (C:576-596) — load and execute a Lua buffer from resource
// ---------------------------------------------------------------------------
fn alua_doresolve(ctx: ?*lua_State, inp: [*c]const u8) c_int {
    var source = c.arcan_open_resource(inp);
    if (source.fd == c.BADFD)
        return -1;

    const map = c.arcan_map_resource(&source, false);
    if (map.unnamed_0.ptr == null) {
        c.arcan_release_resource(&source);
        return -1;
    }

    var rv = c.luaL_loadbuffer(ctx, map.unnamed_0.ptr, map.sz, inp);
    if (0 == rv)
        rv = c.lua_pcall(ctx, 0, c.LUA_MULTRET, 0);

    _ = c.arcan_release_map(map);
    c.arcan_release_resource(&source);

    return rv;
}

// ---------------------------------------------------------------------------
// 9. validblendmode (C:826-832) — check blend enum value
// ---------------------------------------------------------------------------
fn validblendmode(m: c_int) bool {
    return m == c.BLEND_NONE or
        m == c.BLEND_ADD or
        m == c.BLEND_SUB or
        m == c.BLEND_MULTIPLY or
        m == c.BLEND_NORMAL or
        m == c.BLEND_FORCE or
        m == c.BLEND_PREMUL;
}

// ---------------------------------------------------------------------------
// 10. fsrvtos (C:13605-13644) — SEGID enum to human-readable string
// ---------------------------------------------------------------------------
fn fsrvtos(ink: c_uint) [*c]const u8 {
    const v: c_int = @bitCast(ink);
    return switch (v) {
        c.SEGID_LWA => "lightweight arcan",
        c.SEGID_MEDIA => "multimedia",
        c.SEGID_NETWORK_SERVER => "network-server",
        c.SEGID_NETWORK_CLIENT => "network-client",
        c.SEGID_CURSOR => "cursor",
        c.SEGID_TERMINAL => "terminal",
        c.SEGID_TUI => "tui",
        c.SEGID_POPUP => "popup",
        c.SEGID_ICON => "icon",
        c.SEGID_REMOTING => "remoting",
        c.SEGID_GAME => "game",
        c.SEGID_HMD_L => "hmd-l",
        c.SEGID_HMD_R => "hmd-r",
        c.SEGID_HMD_SBS => "hmd-sbs-lr",
        c.SEGID_VM => "vm",
        c.SEGID_APPLICATION => "application",
        c.SEGID_CLIPBOARD => "clipboard",
        c.SEGID_BROWSER => "browser",
        c.SEGID_ENCODER => "encoder",
        c.SEGID_TITLEBAR => "titlebar",
        c.SEGID_SENSOR => "sensor",
        c.SEGID_SERVICE => "service",
        c.SEGID_BRIDGE_X11 => "bridge-x11",
        c.SEGID_BRIDGE_WAYLAND => "bridge-wayland",
        c.SEGID_BRIDGE_ALLOCATOR => "bridge-allocator",
        c.SEGID_DEBUG => "debug",
        c.SEGID_WIDGET => "widget",
        c.SEGID_ACCESSIBILITY => "accessibility",
        c.SEGID_CLIPBOARD_PASTE => "clipboard-paste",
        c.SEGID_AUDIO => "audio",
        c.SEGID_HANDOVER => "handover",
        c.SEGID_UNKNOWN => "unknown",
        else => "",
    };
}

// ---------------------------------------------------------------------------
// 11. tgtevent (C:4168-4183) — push event to frameserver
// ---------------------------------------------------------------------------
fn tgtevent(dst: arcan_vobj_id, ev_arg: arcan_event) bool {
    var ev = ev_arg;
    const state = c.arcan_video_feedstate(dst);

    if (state != null and state.*.tag == c.ARCAN_TAG_FRAMESERV and state.*.ptr != null) {
        const fsrv: ?*c.arcan_frameserver = @ptrCast(@alignCast(state.*.ptr));
        return c.platform_fsrv_pushevent(fsrv, &ev) == c.ARCAN_OK;
    } else if (state != null and state.*.tag == c.ARCAN_TAG_LWA and state.*.ptr != null) {
        return c.platform_lwa_targetevent(@ptrCast(@alignCast(state.*.ptr)), &ev);
    }

    return false;
}

// ---------------------------------------------------------------------------
// 12. chop (C:890-904) — trim leading/trailing whitespace
// ---------------------------------------------------------------------------
fn chop(str_arg: [*c]u8) [*c]u8 {
    var str = str_arg;
    var endptr: [*c]u8 = str + c.strlen(str) - 1;

    // skip leading whitespace
    while (c.isspace(@as(c_int, str[0])) != 0)
        str += 1;

    if (str[0] == 0)
        return str;

    // skip trailing whitespace
    while (@intFromPtr(endptr) > @intFromPtr(str) and c.isspace(@as(c_int, endptr[0])) != 0)
        endptr -= 1;

    (endptr + 1)[0] = 0;

    return str;
}

// ---------------------------------------------------------------------------
// 13. funtable (C:906-915) — create lua table with a "kind" field
// ---------------------------------------------------------------------------
fn funtable(ctx: ?*lua_State, kind: u32) c_int {
    c.lua_createtable(ctx, 0, 0);
    const top = c.lua_gettop(ctx);
    c.lua_pushstring(ctx, "kind");
    c.lua_pushnumber(ctx, @as(c.lua_Number, @floatFromInt(kind)));
    c.lua_rawset(ctx, top);
    return top;
}

// ---------------------------------------------------------------------------
// 14. streamtype (C:986-995) — number to stream type string
// ---------------------------------------------------------------------------
fn streamtype(num: c_int) [*c]const u8 {
    return switch (num) {
        0 => "audio",
        1 => "video",
        2 => "text",
        3 => "overlay",
        else => "broken",
    };
}

// ---------------------------------------------------------------------------
// 15. Filter constants (C:917-925) — character filter sets
// ---------------------------------------------------------------------------
const flt_alpha = "abcdefghijklmnopqrstuvwxyz-_";
const flt_chunkfn = "abcdefghijklmnopqrstuvwxyz1234567890;*";
const flt_alphanum = "abcdefghijklmnopqrstuvxwyz-0123456789-_";
const flt_Alphanum = "abcdefghijklmnopqrstuvxwyz-0123456789-_" ++
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const flt_Alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZ-_" ++
    "abcdefghijklmnopqrstuvwxyz";
const flt_num = "0123456789_-";
const flt_chint = "abcdefhijklmnopqrstuvwyz:1234567890";

// ---------------------------------------------------------------------------
// 16. fltpush (C:927-960) — filter and copy a string
// ---------------------------------------------------------------------------
fn fltpush(
    dst: [*c]u8,
    ulim_arg: u8,
    inmsg_arg: [*c]u8,
    fltch: [*c]const u8,
    replch: u8,
) void {
    var out = dst;
    var ulim = ulim_arg;
    var inmsg = inmsg_arg;

    while (inmsg[0] != 0 and ulim > 0) {
        ulim -= 1;
        var pos = fltch;
        var found = false;

        while (pos[0] != 0) {
            if (pos[0] == inmsg[0]) {
                found = true;
                break;
            }
            pos += 1;
        }

        if (!found) {
            if (replch != 0) {
                out[0] = replch;
                out += 1;
            }
        } else {
            out[0] = inmsg[0];
            out += 1;
        }
        inmsg += 1;
    }

    out[0] = 0;
}

// ---------------------------------------------------------------------------
// 17. utf8_decode + slim_utf8_push (C:960-984)
//     utf8_decode from src/frameserver/util/utf8.c (Hoehrmann decoder)
// ---------------------------------------------------------------------------
const UTF8_ACCEPT: u32 = 0;
const UTF8_REJECT: u32 = 1;

const utf8d = [_]u8{
    // 00..1f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 20..3f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 40..5f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 60..7f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 80..9f
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
    // a0..bf
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    // c0..df
    8, 8, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    // e0..ef
    0xa, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x4, 0x3, 0x3,
    // f0..ff
    0xb, 0x6, 0x6, 0x6, 0x5, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8,
    // s0..s0
    0x0, 0x1, 0x2, 0x3, 0x5, 0x8, 0x7, 0x1, 0x1, 0x1, 0x4, 0x6, 0x1, 0x1, 0x1, 0x1,
    // s1..s2
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1,
    // s3..s4
    1, 2, 1, 1, 1, 1, 1, 2, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1,
    // s5..s6
    1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 1, 3, 1, 1, 1, 1, 1, 1,
    // s7..s8
    1, 3, 1, 1, 1, 1, 1, 3, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
};

inline fn utf8_decode(state: *u32, codep: *u32, byte: u32) u32 {
    const typ: u32 = utf8d[@as(usize, @intCast(byte))];

    codep.* = if (state.* != UTF8_ACCEPT)
        (byte & 0x3f) | (codep.* << 6)
    else
        (@as(u32, 0xff) >> @as(u5, @intCast(typ))) & byte;

    state.* = utf8d[256 + state.* * 16 + typ];
    return state.*;
}

fn slim_utf8_push(dst: [*c]u8, ulim: c_int, inmsg: [*c]u8) void {
    var state: u32 = 0;
    var codepoint: u32 = 0;
    var i: usize = 0;

    const limit: usize = @intCast(ulim);

    while (inmsg[i] != 0 and i < limit) : (i += 1) {
        dst[i] = inmsg[i];

        if (utf8_decode(&state, &codepoint, @as(u32, inmsg[i])) == UTF8_REJECT) {
            // broken state — clear
            dst[0] = 0;
            return;
        }
    }

    if (state == UTF8_ACCEPT) {
        dst[i] = 0;
        return;
    }

    // incomplete sequence — clear
    dst[0] = 0;
}

// ---------------------------------------------------------------------------
// 18. stack_to_uiarray (C:5737-5758) — extract unsigned int array from lua stack
// ---------------------------------------------------------------------------
fn stack_to_uiarray(
    ctx: ?*lua_State,
    memtype: c_int,
    dst: [*c][*c]c_uint,
    n: [*c]usize,
    count: usize,
) bool {
    _ = n;
    const nval: usize = c.lua_objlen(ctx, -1);
    if (nval == 0 or (count != 0 and nval != count))
        return false;

    dst.* = @ptrCast(@alignCast(c.arcan_alloc_mem(
        nval * @sizeOf(c_uint),
        @as(c_uint, @bitCast(memtype)),
        @as(c_uint, @bitCast(c.ARCAN_MEM_NONFATAL)),
        @as(c_uint, @bitCast(c.ARCAN_MEMALIGN_NATURAL)),
    )));

    if (dst.* == null)
        return false;

    const out: [*c]c_uint = dst.*;
    var i: usize = 0;
    while (i < nval) : (i += 1) {
        _ = c.lua_rawgeti(ctx, -1, @as(c_int, @intCast(i + 1)));
        out[i] = @as(c_uint, @bitCast(@as(c_int, @truncate(c.lua_tointeger(ctx, -1)))));
        c.lua_settop(ctx, -1 - 1);
    }

    return true;
}

// ---------------------------------------------------------------------------
// 19. stack_to_farray (C:5760-5781) — extract float array from lua stack
// ---------------------------------------------------------------------------
fn stack_to_farray(
    ctx: ?*lua_State,
    memtype: c_int,
    dst: [*c][*c]f32,
    n: [*c]usize,
    count: usize,
) bool {
    const nval: usize = c.lua_objlen(ctx, -1);
    if (nval == 0 or (count != 0 and nval != count))
        return false;

    dst.* = @ptrCast(@alignCast(c.arcan_alloc_mem(
        nval * @sizeOf(f32),
        @as(c_uint, @bitCast(memtype)),
        @as(c_uint, @bitCast(c.ARCAN_MEM_NONFATAL)),
        @as(c_uint, @bitCast(c.ARCAN_MEMALIGN_NATURAL)),
    )));

    if (dst.* == null)
        return false;

    var i: usize = 0;
    while (i < nval) : (i += 1) {
        _ = c.lua_rawgeti(ctx, -1, @as(c_int, @intCast(i + 1)));
        dst.*[n.*] = @as(f32, @floatCast(c.luaL_checknumber(ctx, -1)));
        n.* += 1;
        c.lua_settop(ctx, -1 - 1);
    }

    return (count == 0 or n.* == count);
}

// ---------------------------------------------------------------------------
// 20. filter_text (C:7400-7452) — sanitize text: allow alnum, whitespace,
//     selected punctuation; replace rest with space; strip leading/trailing
// ---------------------------------------------------------------------------
fn filter_text(in: [*c]u8, out_sz: *usize) [*c]u8 {
    // Step 1: sanitize characters in-place
    var work = in;
    while (work[0] != 0) {
        if (c.isalnum(@as(c_int, work[0])) != 0 or c.isspace(@as(c_int, work[0])) != 0) {
            // allowed — pass through
        } else {
            switch (work[0]) {
                ',', '.', '!', '/', '\n', '\t', ';', ':', '(', '\'', '<', '>', ')' => {},
                else => {
                    work[0] = ' ';
                },
            }
        }
        work += 1;
    }

    // Step 2: strip leading whitespace
    var start = in;
    while (start[0] != 0 and c.isspace(@as(c_int, start[0])) != 0)
        start += 1;

    out_sz.* = c.strlen(start);

    if (out_sz.* == 0)
        return start;

    // Step 3: strip trailing whitespace
    work = start + out_sz.*;
    while ((work[0] == 0 or c.isspace(@as(c_int, work[0])) != 0) and out_sz.* > 0) {
        work -= 1;
        out_sz.* -= 1;
    }

    if (work[0] != 0)
        (work + 1)[0] = 0;

    return start;
}

// ---------------------------------------------------------------------------
// 21. get_utf8 (C:3563-3572) — extract up to 4 bytes of utf8 char into dst[5]
// ---------------------------------------------------------------------------
fn get_utf8(instr: [*c]const u8, dst: [*c]u8) void {
    if (instr == null) {
        dst[0] = 0;
        dst[1] = 0;
        dst[2] = 0;
        dst[3] = 0;
        dst[4] = 0;
        return;
    }

    const len = c.strlen(instr);
    const copy_len = if (len <= 4) len else 4;
    _ = c.memcpy(
        @as(?*anyopaque, @ptrCast(dst)),
        @as(?*const anyopaque, @ptrCast(instr)),
        copy_len,
    );
}

// ---------------------------------------------------------------------------
// 22. is_special_res (C:3170-3175) — check for special resource string prefixes
// ---------------------------------------------------------------------------
fn is_special_res(msg: [*c]const u8) bool {
    return c.strncmp(msg, "device", 6) == 0 or
        c.strncmp(msg, "stream", 6) == 0 or
        c.strncmp(msg, "capture", 7) == 0;
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part2.zig
// ══════════════════════════════════════════════════════════════════════

// === Section 1: Public API + Section 2: Resource I/O ===
//
// Ported from src/engine/arcan_lua.c (C source lines 598-1091, plus
// scattered public API functions) to Zig, using translate-c as reference.
//
// Requires a C helper file providing accessor functions for opaque
// arcan_frameserver fields (fsrv_get_vid, fsrv_get_tag, etc.)
// and the remaining static helpers (lua_pushvid, findresource, etc.)
// that are defined in the unported portion of arcan_lua.c.



// Type aliases

// Errno constants
const EAGAIN: c_int = 11;
const EINTR: c_int = 4;

// External variables from other engine modules
extern var benchdata: c.arcan_benchdata;

// Functions implemented here (were extern fn, now actual implementations)

// dump_vobject, dump_rtgt, fput_luasafe_str — provided by arcan_frameserver_helpers.c
extern fn dump_vobject(dst: ?*c.FILE, src: [*c]c.arcan_vobject) void;
extern fn dump_rtgt(dst: ?*c.FILE, rtgt: [*c]c.struct_rendertarget) void;
extern fn fput_luasafe_str(dst: ?*c.FILE, str: [*c]const u8) void;

fn vid_toluavid(id: arcan_vobj_id) f64 {
    var vid = id;
    if (vid != c.ARCAN_EID and vid != c.ARCAN_VIDEO_WORLDID)
        vid += @as(arcan_vobj_id, @intCast(lua_vid_base));
    return @floatFromInt(vid);
}

fn sig_watchdog(_: c_int, info: [*c]c.siginfo_t, _: ?*anyopaque) callconv(.c) void {
    // siginfo_t layout varies across platforms/cImport — always set the hook
    // (the original C code checked si_pid == getppid() but the watchdog signal
    //  only fires from the parent process anyway)
    _ = info;
    _ = c.lua_sethook(luactx.last_ctx, luactx.error_hook, c.LUA_MASKCOUNT, 1);
}

fn luaB_loadstring(ctx: ?*lua_State) callconv(.c) c_int {
    var l: usize = 0;
    const s = c.luaL_checklstring(ctx, 1, &l);
    const chunkname = c.luaL_optlstring(ctx, 2, s, null);
    if (c.luaL_loadbuffer(ctx, s, l, chunkname) == 0)
        return 1;
    c.lua_pushnil(ctx);
    c.lua_insert(ctx, -2);
    return 2;
}

fn add_source(fd: c_int, mode: c.mode_t, otag: isize) callconv(.c) bool {
    return c.arcan_event_add_source(c.arcan_event_defaultctx(), fd, mode, otag, false);
}

fn del_source(fd: c_int, mode: c.mode_t, out: [*c]isize) callconv(.c) bool {
    return c.arcan_event_del_source(c.arcan_event_defaultctx(), fd, mode, out);
}

fn error_nbio(_: ?*lua_State, _: c_int, _: isize, _: [*c]const u8) callconv(.c) void {}

fn alua_exposefuncs(ctx: ?*lua_State, debugfuncs: u8) c_int {
    if (ctx == null) return c.ARCAN_ERRC_UNACCEPTED_STATE;
    lua_debug_level = debugfuncs;

    register_tbl(ctx, &resfuns);
    register_tbl(ctx, &tgtfuns);
    register_tbl(ctx, &dbfuns);
    register_tbl(ctx, &custfuns);
    register_tbl(ctx, &audfuns);
    register_tbl(ctx, &imgfuns);
    register_tbl(ctx, &threedfuns);
    register_tbl(ctx, &sysfuns);
    register_tbl(ctx, &iofuns);
    register_tbl(ctx, &vidsysfuns);
    register_tbl(ctx, &netfuns);

    // Override print for tracer integration
    c.lua_pushcfunction(ctx, c.alt_trace_log);
    c.lua_setglobal(ctx, "print");

    // calcImage metatable
    _ = c.luaL_newmetatable(ctx, "calcImage");
    c.lua_pushvalue(ctx, -1);
    c.lua_setfield(ctx, -2, "__index");
    c.lua_pushcfunction(ctx, &procimage_get);
    c.lua_setfield(ctx, -2, "get");
    c.lua_pushcfunction(ctx, &procimage_read);
    c.lua_setfield(ctx, -2, "read");
    c.lua_pushcfunction(ctx, &procimage_cursor);
    c.lua_setfield(ctx, -2, "cursor");
    c.lua_pushcfunction(ctx, &procimage_histo);
    c.lua_setfield(ctx, -2, "histogram_impose");
    c.lua_pushcfunction(ctx, &procimage_lookup);
    c.lua_setfield(ctx, -2, "frequency");
    c.lua_pushcfunction(ctx, &procimage_translate);
    c.lua_setfield(ctx, -2, "translate");
    c.lua_pushcfunction(ctx, &procimage_cursor_to);
    c.lua_setfield(ctx, -2, "cursor_to");
    c.lua_pushcfunction(ctx, &procimage_cursor_style);
    c.lua_setfield(ctx, -2, "cursor_style");
    c.lua_settop(ctx, c.lua_gettop(ctx) - 1);

    // meshAccess metatable
    _ = c.luaL_newmetatable(ctx, "meshAccess");
    c.lua_pushvalue(ctx, -1);
    c.lua_setfield(ctx, -2, "__index");
    c.lua_pushcfunction(ctx, &meshaccess_verts);
    c.lua_setfield(ctx, -2, "vertices");
    c.lua_pushcfunction(ctx, &meshaccess_indices);
    c.lua_setfield(ctx, -2, "indices");
    c.lua_pushcfunction(ctx, &meshaccess_texcos);
    c.lua_setfield(ctx, -2, "texcos");
    c.lua_pushcfunction(ctx, &meshaccess_texcos);
    c.lua_setfield(ctx, -2, "texture_coordinates");
    c.lua_pushcfunction(ctx, &meshaccess_colors);
    c.lua_setfield(ctx, -2, "colors");
    c.lua_pushcfunction(ctx, &meshaccess_type);
    c.lua_setfield(ctx, -2, "primitive_type");
    c.lua_settop(ctx, c.lua_gettop(ctx) - 1);

    // ZCS-Live Phase 5: zcsDeep metatable — methods on an opened deep view
    // (`ud:name(tid,idx)`, `ud:summary()`, `ud:close()`) + __gc that unmaps the
    // arena and releases the bridge view.
    _ = c.luaL_newmetatable(ctx, "zcsDeep");
    c.lua_pushvalue(ctx, -1);
    c.lua_setfield(ctx, -2, "__index");
    c.lua_pushcfunction(ctx, &zcs_deep_name_lua);
    c.lua_setfield(ctx, -2, "name");
    c.lua_pushcfunction(ctx, &zcs_deep_summary_lua);
    c.lua_setfield(ctx, -2, "summary");
    c.lua_pushcfunction(ctx, &zcs_deep_close_lua);
    c.lua_setfield(ctx, -2, "close");
    c.lua_pushcfunction(ctx, &zcs_deep_gc);
    c.lua_setfield(ctx, -2, "__gc");
    c.lua_settop(ctx, c.lua_gettop(ctx) - 1);

    const top = c.lua_gettop(ctx);
    extend_baseapi(ctx);
    extend_ds4api(ctx);
    _ = c.luaopen_bit(ctx);
    c.lua_settop(ctx, top);

    _ = c.atexit(arcan_lua_cleanup);
    return c.ARCAN_OK;
}

export fn arcan_lua_cbdrop() void {
    var i: usize = 0;
    while (i <= vcontext_ind) : (i += 1) {
        const ctx = &vcontext_stack[i];
        var j: usize = 0;
        while (j < @as(usize, @intCast(ctx.*.vitem_limit))) : (j += 1) {
            if ((ctx.*.vitems_pool[j].flags & @as(c_uint, c.FL_INUSE)) != 0 and
                ctx.*.vitems_pool[j].feed.state.tag == c.ARCAN_TAG_FRAMESERV)
            {
                const fsrv_ptr = ctx.*.vitems_pool[j].feed.state.ptr;
                if (fsrv_ptr != null)
                    fsrv_helper_set_tag(fsrv_ptr, c.LUA_NOREF);
            }
        }
    }
}

export fn arcan_lua_crash_source(_: ?*lua_State) [*c]const u8 {
    return c.alt_trace_crash_source();
}

export fn arcan_state_dump(key: [*c]const u8, msg: [*c]const u8, src: [*c]const u8) void {
    const logtime = c.time(null);
    const ltime = c.localtime(&logtime);
    if (ltime == null) {
        c.arcan_warning("arcan_state_dump() failed, couldn't get localtime.\n");
        return;
    }

    var date_str: [32]u8 = undefined;
    _ = c.strftime(&date_str, date_str.len, "%m%d_%H%M%S", ltime);

    var state_fn: [256]u8 = undefined;
    _ = c.snprintf(&state_fn, state_fn.len, "%s_%s.lua", key, &date_str);

    const fname = c.arcan_expand_resource(&state_fn, c.RESOURCE_SYS_DEBUG);
    if (fname == null) return;
    defer c.arcan_mem_free(@as(?*anyopaque, @ptrCast(fname)));

    const tmpout = c.fopen(fname, "w+");
    if (tmpout != null) {
        var dbuf: [512]u8 = undefined;
        _ = c.snprintf(&dbuf, dbuf.len, "%s, %s\n",
            if (msg != null) msg else @as([*c]const u8, ""),
            if (src != null) src else @as([*c]const u8, ""));
        arcan_lua_statesnap(tmpout, &dbuf, false);
        _ = c.fclose(tmpout);
    } else {
        c.arcan_warning("crashdump requested but file is not accessible.\n");
    }
}

// C accessor helpers for opaque arcan_frameserver
// arcan_frameserver is demoted to opaque by @cImport due to bitfields.
// ZCS-Live Phase 5 — deep-introspection bridge. These resolve at link time to
// the compiler-side `export fn` in src/InternPool/deep_view.zig (the same
// extern-decl + link-resolve pattern as `arcan_shmif_*` / `arcan_main`; the
// engine module cannot `@import` the InternPool). On a `may` built without
// `-Dinternpool-shared-arena` the exports still exist (gate-off they return
// the "unavailable" sentinels), so the link refs always resolve.
//   zcs_deep_open(base, meta) -> opaque view handle (or null)
//   zcs_deep_nav_name(view, tid, idx, buf, buflen) -> name byte length (or -1)
//   zcs_deep_summary(view, out, meta) -> bool (fills DeepSummary)
//   zcs_deep_close(view)
extern fn zcs_deep_open(base: usize, meta: ?*const anyopaque) ?*anyopaque;
extern fn zcs_deep_nav_name(view: ?*anyopaque, tid: u32, idx: u32, buf: ?[*]u8, buflen: usize) c_long;
extern fn zcs_deep_summary(view: ?*anyopaque, out: ?*DeepSummary, meta: ?*const anyopaque) bool;
extern fn zcs_deep_close(view: ?*anyopaque) void;
// Fetch a passed descriptor off a frameserver's event/data pipe (SCM_RIGHTS).
// Used to retrieve the live IP-arena memfd the may.zcs publisher pushes ahead
// of its `may.iparena` BCHUNKSTATE event. Impl: platform/posix/fdpassing_nonblock.zig.
extern fn arcan_fetchhandle(sockin_fd: c_int, block: bool) c_int;
// Mirror of deep_view.zig's `Summary` extern struct (pointer-free, C-ABI).
const DeepSummary = extern struct {
    thread_count: u32 = 0,
    nav_total: u32 = 0,
    nav_unresolved: u32 = 0,
    nav_type_resolved: u32 = 0,
    nav_fully_resolved: u32 = 0,
    nav_unreadable: u32 = 0,
    dep_entries_len: u32 = 0,
    first_dependency_len: u32 = 0,
    committed_bytes: u64 = 0,
    build_match: u32 = 0,
    _pad: u32 = 0,
};

// True iff the bchunk `extensions` field is the ZCS-Live live-arena tag
// ("may.iparena", NUL-terminated). Only that tag triggers the descriptor fetch.
fn is_iparena_ext(extensions: [*]const u8) bool {
    const tag = "may.iparena";
    var i: usize = 0;
    while (i < tag.len) : (i += 1) {
        if (extensions[i] != tag[i]) return false;
    }
    return extensions[tag.len] == 0;
}

// Stash the latest live may.zcs arena fd into the global Lua table `_zcs_arena`
// ({fd=, size=, source=}). Read by the zcs_probe hook / zcs.zig deep path,
// decoupling the fd capture from the debug window's adoption timing.
fn zcs_stash_arena_fd(ctx: ?*lua_State, source: f64, fd: f64, size: f64) void {
    c.lua_createtable(ctx, 0, 3);
    const t = c.lua_gettop(ctx);
    set_tblnum(ctx, "fd", fd, t);
    set_tblnum(ctx, "size", size, t);
    set_tblnum(ctx, "source", source, t);
    c.lua_setglobal(ctx, "_zcs_arena");
}

// These thin C wrappers provide field access.
// C accessor helpers for arcan_frameserver (opaque bitfield struct)
// Defined in arcan_frameserver_helpers.c with fsrv_helper_* prefix
extern fn fsrv_helper_get_vid(fsrv: ?*anyopaque) arcan_vobj_id;
extern fn fsrv_helper_get_aid(fsrv: ?*anyopaque) c.arcan_aobj_id;
extern fn fsrv_helper_get_tag(fsrv: ?*anyopaque) isize;
extern fn fsrv_helper_set_tag(fsrv: ?*anyopaque, val: isize) void;
extern fn fsrv_helper_get_segid(fsrv: ?*anyopaque) c_int;
extern fn fsrv_helper_set_segid(fsrv: ?*anyopaque, val: c_int) void;
extern fn fsrv_helper_get_cookie(fsrv: ?*anyopaque) u32;
extern fn fsrv_helper_get_desc_width(fsrv: ?*anyopaque) u16;
extern fn fsrv_helper_get_desc_height(fsrv: ?*anyopaque) u16;
extern fn fsrv_helper_get_desc_hints(fsrv: ?*anyopaque) c_int;
extern fn fsrv_helper_get_desc_region_valid(fsrv: ?*anyopaque) bool;
extern fn fsrv_helper_get_desc_region(fsrv: ?*anyopaque, x1: *i16, y1: *i16, x2: *i16, y2: *i16) void;
extern fn fsrv_helper_get_desc_text_cellw(fsrv: ?*anyopaque) usize;
extern fn fsrv_helper_get_desc_text_cellh(fsrv: ?*anyopaque) usize;
extern fn fsrv_helper_get_desc_aext_hdr(fsrv: ?*anyopaque) ?*anyopaque;
extern fn fsrv_helper_get_title_buf(fsrv: ?*anyopaque) [*c]u8;
extern fn fsrv_helper_get_title_buf_len(fsrv: ?*anyopaque) usize;
extern fn fsrv_helper_get_activated(fsrv: ?*anyopaque) c_int;
extern fn fsrv_helper_set_activated(fsrv: ?*anyopaque, val: c_int) void;
extern fn fsrv_helper_get_shmptr(fsrv: ?*anyopaque) ?*anyopaque;
extern fn fsrv_helper_page_get_dms(page: ?*anyopaque) i8;
extern fn fsrv_helper_get_title(fsrv: ?*anyopaque) [*c]const u8;  // returns f->title (read-only)
extern fn fsrv_helper_get_guid(fsrv: ?*anyopaque, idx: c_int) u64;
extern fn fsrv_helper_get_parent_vid(fsrv: ?*anyopaque) arcan_vobj_id;
extern fn fsrv_helper_get_desc_recovery_tick(fsrv: ?*anyopaque) c_uint;

// Bitfield flag accessors — C bitfields are opaque in Zig @cImport
extern fn fsrv_helper_get_flag_alive(fsrv: ?*anyopaque) bool;
extern fn fsrv_helper_get_flag_explicit(fsrv: ?*anyopaque) bool;
extern fn fsrv_helper_get_flag_local_copy(fsrv: ?*anyopaque) bool;
extern fn fsrv_helper_get_flag_no_alpha_copy(fsrv: ?*anyopaque) bool;
extern fn fsrv_helper_get_flag_autoclock(fsrv: ?*anyopaque) bool;
extern fn fsrv_helper_get_flag_gpu_auth(fsrv: ?*anyopaque) bool;
extern fn fsrv_helper_get_flag_rz_ack(fsrv: ?*anyopaque) bool;
extern fn fsrv_helper_get_flag_no_adopt(fsrv: ?*anyopaque) bool;
extern fn fsrv_helper_get_flag_block_hdr_meta(fsrv: ?*anyopaque) bool;
extern fn fsrv_helper_set_flag_explicit(fsrv: ?*anyopaque, v: bool) void;
extern fn fsrv_helper_set_flag_local_copy(fsrv: ?*anyopaque, v: bool) void;
extern fn fsrv_helper_set_flag_no_alpha_copy(fsrv: ?*anyopaque, v: bool) void;
extern fn fsrv_helper_set_flag_autoclock(fsrv: ?*anyopaque, v: bool) void;
extern fn fsrv_helper_set_flag_gpu_auth(fsrv: ?*anyopaque, v: bool) void;
extern fn fsrv_helper_set_flag_rz_ack(fsrv: ?*anyopaque, v: bool) void;
extern fn fsrv_helper_set_flag_no_adopt(fsrv: ?*anyopaque, v: bool) void;
extern fn fsrv_helper_set_flag_block_hdr_meta(fsrv: ?*anyopaque, v: bool) void;

// luactx (module-level static state)
// Defined in the main arcan_lua module; declared extern here.
const LuaCtx = extern struct {
    rawres: c.struct_nonblock_io,
    grab: u8,
    prefix_buf: [*c]u8,
    prefix_ofs: usize,
    pending_segpush: [*c]c.arcan_shmif_cont,
    last_segreq: [*c]c.struct_arcan_extevent,
    pending_socket_label: [*c]u8,
    pending_socket_descr: c_int,
    last_argv: [*c][*c]const u8,
    last_ctx: ?*lua_State,
    error_hook: ?*const fn (?*lua_State, [*c]c.lua_Debug) callconv(.c) void,
    worldid_tag: isize,
    last_clock: usize,
};

// ==========================================================================
// Section 1: Public API (export fn)
// ==========================================================================

// --------------------------------------------------------------------------
// 1. arcan_lua_tick (C:598-632)
// --------------------------------------------------------------------------
export fn arcan_lua_tick(ctx: ?*lua_State, nticks_arg: usize, global: usize) void {
    var nticks = nticks_arg;
    if (nticks == 0) return;

    arcan_lua_setglobalnum(ctx, "CLOCK", @as(f64, @floatFromInt(global)));
    luactx.last_clock = global;

    // Prefer batched clock_pulse if available
    if (c.alt_lookup_entry(ctx, "clock_pulse_batch", 17)) {
        c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(global)));
        c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(nticks)));
        c.alt_call(ctx, c.CB_SOURCE_NONE, @as(u64, @bitCast(@as(c_long, c.EP_TRIGGER_CLOCK))), 0, 2, 0, @as([*c]const u8, "arcan_lua.zig:clock_pulse_batch"));
        return;
    }

    // Otherwise emit one tick at a time
    while (nticks != 0) {
        nticks -= 1;
        if (!c.alt_lookup_entry(ctx, "clock_pulse", 11))
            break;
        c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(global)));
        c.lua_pushnumber(ctx, @as(lua_Number, 1.0));
        c.alt_call(ctx, c.CB_SOURCE_NONE, @as(u64, @bitCast(@as(c_long, c.EP_TRIGGER_CLOCK))), 0, 2, 0, @as([*c]const u8, "arcan_lua.zig:clock_pulse"));
    }

    c.alt_trace_finish(ctx);
}

// --------------------------------------------------------------------------
// 2. arcan_lua_main (C:634-651)
// --------------------------------------------------------------------------
export fn arcan_lua_main(ctx: ?*lua_State, inp: [*c]const u8, file: bool) [*c]u8 {
    // NOTE: Do NOT wrap with zig_foreign_begin/end here. The Lua VM must run
    // under musl TLS — musl's __errno_location, malloc, etc. use tpidr_el0.
    // Running the entire VM under glibc TLS corrupts glibc's heap metadata.
    // Vulkan/XCB/shaderc calls are wrapped at their own boundaries (agp, video).
    var fail: bool = false;

    if (file) {
        fail = alua_doresolve(ctx, inp) != 0;
    } else {
        fail = (c.luaL_loadfile(ctx, inp) != 0) or
            (c.lua_pcall(ctx, 0, c.LUA_MULTRET, 0) != 0);
    }

    if (fail) {
        const msg = c.lua_tolstring(ctx, -1, null);
        if (msg != null) return c.strdup(msg);
    }

    return null;
}

// --------------------------------------------------------------------------
// 3. arcan_lua_launch_cp (C:656-694)
// --------------------------------------------------------------------------
export fn arcan_lua_launch_cp(ctx: ?*lua_State, cp_arg: [*c]const u8, key: [*c]const u8) bool {
    if (cp_arg == null or ctx == null) return false;

    if (!c.alt_lookup_entry(ctx, "adopt", 5)) {
        c.arcan_warning(@as([*c]const u8, "target appl lacks an _adopt handler\n"));
        return false;
    }

    const res = c.platform_launch_listen_external(
        cp_arg,
        key,
        -1,
        c.ARCAN_SHM_UMASK,
        32,
        32,
        @as(usize, @bitCast(@as(isize, c.LUA_NOREF))),
    );

    if (res == null) {
        c.arcan_warning(@as([*c]const u8, "couldn't listen on connection point (%s)\n"), cp_arg);
        return false;
    }

    // res is ?*anyopaque because arcan_frameserver is opaque
    const vid = fsrv_helper_get_vid(res);
    lua_pushvid(ctx, vid);
    c.lua_pushlstring(ctx, "_stdin", 6);
    c.lua_pushlstring(ctx, "", 0);
    lua_pushvid(ctx, c.ARCAN_EID);
    c.lua_pushboolean(ctx, 1);

    c.alt_call(ctx, c.CB_SOURCE_NONE, @as(u64, @bitCast(@as(c_long, c.EP_TRIGGER_ADOPT))), 0, 5, 1, @as([*c]const u8, "arcan_lua.zig:adopt"));

    if (c.lua_type(ctx, -1) == c.LUA_TBOOLEAN and c.lua_toboolean(ctx, -1) != 0) {
        c.lua_settop(ctx, -2);
        return true;
    } else {
        c.arcan_warning(@as([*c]const u8, "target appl rejected _stdin on adopt\n"));
        c.lua_settop(ctx, -2);
        _ = c.arcan_video_deleteobject(vid);
        return false;
    }
}

// --------------------------------------------------------------------------
// 4. arcan_lua_adopt (C:696-824)
//    Uses VLA in C — we use a fixed-size buffer (max 256 frameservers).
//    arcan_frameserver is opaque — uses C accessor helpers.
// --------------------------------------------------------------------------
const MAX_ADOPT_FSRV = 256;

export fn arcan_lua_adopt(ctx: ?*lua_State) void {
    const first = vcontext_stack[0].stdoutp.first;
    var current = first;

    // Count frameservers
    var n_fsrv: usize = 0;
    while (current != null) {
        const elem_ptr: *c.arcan_vobject = @ptrCast(current.*.elem);
        if (elem_ptr.feed.state.tag == c.ARCAN_TAG_FRAMESERV)
            n_fsrv += 1;
        current = current.*.next;
    }

    if (n_fsrv == 0) return;

    // Collect IDs — primary segments first, secondary segments at the end
    var ids: [MAX_ADOPT_FSRV]arcan_vobj_id = undefined;
    const effective = if (n_fsrv > MAX_ADOPT_FSRV) MAX_ADOPT_FSRV else n_fsrv;
    var count: usize = 0;
    var lcount: usize = effective - 1;
    current = first;
    while (count < effective and current != null) {
        const elem_ptr: *c.arcan_vobject = @ptrCast(current.*.elem);
        if (elem_ptr.feed.state.tag == c.ARCAN_TAG_FRAMESERV) {
            const fsrv_ptr = elem_ptr.feed.state.ptr;
            if (fsrv_helper_get_parent_vid(fsrv_ptr) != c.ARCAN_EID) {
                ids[lcount] = elem_ptr.cellid;
                if (lcount > 0) lcount -= 1;
            } else {
                ids[count] = elem_ptr.cellid;
                count += 1;
            }
        }
        current = current.*.next;
    }

    var delids: [MAX_ADOPT_FSRV]arcan_vobj_id = undefined;
    var delcount: usize = 0;
    const tc = c.arcan_conductor_reset_count(false);

    // Forward to adopt function (or delete)
    var idx: usize = 0;
    while (idx < effective) : (idx += 1) {
        const vobj = c.arcan_video_getobject(ids[idx]);
        if (vobj == null) continue;
        const vobj_ptr: *c.arcan_vobject = @ptrCast(vobj);
        if (vobj_ptr.feed.state.tag != c.ARCAN_TAG_FRAMESERV) continue;

        const fsrv_ptr = vobj_ptr.feed.state.ptr;
        fsrv_helper_set_tag(fsrv_ptr, @as(isize, c.LUA_NOREF));

        var do_delete: bool = true;

        // Skip frameservers created during this recovery tick
        if (fsrv_helper_get_desc_recovery_tick(fsrv_ptr) == tc) continue;

        if (c.alt_lookup_entry(ctx, "adopt", 5) and
            c.arcan_video_getobject(ids[idx]) != null)
        {
            lua_pushvid(ctx, vobj_ptr.cellid);
            c.lua_pushstring(ctx, fsrvtos(@bitCast(fsrv_helper_get_segid(fsrv_ptr))));
            c.lua_pushstring(ctx, fsrv_helper_get_title(fsrv_ptr));
            lua_pushvid(ctx, fsrv_helper_get_parent_vid(fsrv_ptr));
            c.lua_pushboolean(ctx, @intFromBool(idx == effective - 1));

            c.alt_call(ctx, c.CB_SOURCE_NONE, @as(u64, @bitCast(@as(c_long, c.EP_TRIGGER_ADOPT))), 0, 5, 1, @as([*c]const u8, "arcan_lua.zig:adopt"));

            // If we get explicit accept, don't delete
            if (c.lua_type(ctx, -1) == c.LUA_TBOOLEAN and c.lua_toboolean(ctx, -1) != 0) {
                do_delete = false;

                // Send register event so adoption handler can map to archetype
                var reg_ev = c.arcan_event.zeroes();
                reg_ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_EXTERNAL))));
                reg_ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_REGISTER;
                reg_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.registr.kind = @bitCast(fsrv_helper_get_segid(fsrv_ptr));
                reg_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.registr.guid[0] = fsrv_helper_get_guid(fsrv_ptr, 0);
                reg_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.registr.guid[1] = fsrv_helper_get_guid(fsrv_ptr, 1);
                _ = c.arcan_event_enqueue(c.arcan_event_defaultctx(), &reg_ev);

                // Fake a resize event for the last negotiated state
                var rsz_ev = c.arcan_event.zeroes();
                rsz_ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_FSRV))));
                rsz_ev.unnamed_0.unnamed_0.unnamed_0.fsrv.kind = c.EVENT_FSRV_RESIZED;
                rsz_ev.unnamed_0.unnamed_0.unnamed_0.fsrv.unnamed_0.unnamed_0.width = fsrv_helper_get_desc_width(fsrv_ptr);
                rsz_ev.unnamed_0.unnamed_0.unnamed_0.fsrv.unnamed_0.unnamed_0.height = fsrv_helper_get_desc_height(fsrv_ptr);
                rsz_ev.unnamed_0.unnamed_0.unnamed_0.fsrv.video = fsrv_helper_get_vid(fsrv_ptr);
                rsz_ev.unnamed_0.unnamed_0.unnamed_0.fsrv.unnamed_0.unnamed_0.audio = fsrv_helper_get_aid(fsrv_ptr);
                rsz_ev.unnamed_0.unnamed_0.unnamed_0.fsrv.otag = fsrv_helper_get_tag(fsrv_ptr);
                const hints = fsrv_helper_get_desc_hints(fsrv_ptr);
                rsz_ev.unnamed_0.unnamed_0.unnamed_0.fsrv.unnamed_0.unnamed_0.fmt_fl = @as(i8, @truncate(@as(c_int, @bitCast(
                    (@as(c_uint, @bitCast(hints)) & c.SHMIF_RHINT_ORIGO_LL) |
                        (@as(c_uint, @bitCast(hints)) & c.SHMIF_RHINT_TPACK),
                ))));
                _ = c.arcan_event_enqueue(c.arcan_event_defaultctx(), &rsz_ev);

                // Send RESET to the frameserver
                var rst_ev = c.arcan_event.zeroes();
                rst_ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
                rst_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_RESET;
                rst_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = 2;
                _ = c.platform_fsrv_pushevent(@as(?*c.arcan_frameserver, @ptrCast(@alignCast(fsrv_ptr))), &rst_ev);
            }

            c.lua_settop(ctx, -2);
        }

        if (do_delete) {
            delids[delcount] = ids[idx];
            delcount += 1;
        }
    }

    // Purge non-external events, reset otags on external events
    c.arcan_event_purge();

    // Mask events during delete, then delete rejected frameservers
    c.arcan_event_maskall(c.arcan_event_defaultctx());
    var di: usize = 0;
    while (di < delcount) : (di += 1) {
        _ = c.arcan_video_deleteobject(delids[di]);
    }
    c.arcan_event_clearmask(c.arcan_event_defaultctx());
}

// Lua 5.1 globals dropped in 5.2+. Called from arcan_lua_alloc right
// after luaL_openlibs. durian / other ported appls still call these
// by their 5.1 names; our runtime is 5.4.
fn alua_install_lua51_compat(L: ?*lua_State) void {
    // unpack = table.unpack — durian calls this on almost every frame
    // via gconfig getter chains.
    _ = c.lua_getglobal(L, "table");
    _ = c.lua_getfield(L, -1, "unpack");
    c.lua_setglobal(L, "unpack");
    c.lua_settop(L, -2); // pop table

    // loadstring = load — in 5.4, `load(s)` accepts a string source and
    // returns the compiled chunk, matching 5.1 `loadstring` semantics
    // exactly. durian's debug menu + the hem djot-reader view call
    // loadstring directly. The pre-existing debug-mode-gated
    // pushcclosure of luaB_loadstring in arcan_lua_mapfunctions is
    // redundant with this shim (which is always on) but harmless.
    _ = c.lua_getglobal(L, "load");
    c.lua_setglobal(L, "loadstring");

    // getfenv / setfenv: 5.1 exposed function-environment manipulation
    // as top-level globals; 5.4 hides environments behind each
    // function's `_ENV` upvalue. No 1:1 replacement exists — what we
    // can shim is the SHAPES of getfenv/setfenv that durian actually
    // uses:
    //   - `(debug or getfenv()).getmetatable(value)` — getfenv() as a
    //     fallback globals-table reference. Returning `_G` covers this.
    //   - setfenv appears only in commented-out hem tableview code.
    //     Provide a no-op returning arg 1 so a future uncomment doesn't
    //     crash.
    // Correct behavior for `getfenv(f)` where f is a specific function
    // would require `debug.getupvalue(f, <_ENV index>)` — not done here.
    c.lua_pushcclosure(L, &luaB_getfenv_compat, 0);
    c.lua_setglobal(L, "getfenv");
    c.lua_pushcclosure(L, &luaB_setfenv_compat, 0);
    c.lua_setglobal(L, "setfenv");

    // `module` is NOT shimmed. It's absent from durian's sources; if a
    // future appl needs it we'll handle then. A correct shim would
    // require emulating 5.1 module-table installation which has no
    // clean 5.4 analogue.

    // `bit` library: LuaJIT/5.1 ships a bitwise-ops module; Lua 5.4 has
    // built-in operators (&/|/~/<</>>) but no `bit` table. durian uses
    // bit.band/bor/bxor/bnot/lshift/rshift across dispatch + display +
    // tools. Provide a shim built from the native operators.
    c.lua_createtable(L, 0, 6);
    c.lua_pushcclosure(L, &luaB_bit_band, 0);
    c.lua_setfield(L, -2, "band");
    c.lua_pushcclosure(L, &luaB_bit_bor, 0);
    c.lua_setfield(L, -2, "bor");
    c.lua_pushcclosure(L, &luaB_bit_bxor, 0);
    c.lua_setfield(L, -2, "bxor");
    c.lua_pushcclosure(L, &luaB_bit_bnot, 0);
    c.lua_setfield(L, -2, "bnot");
    c.lua_pushcclosure(L, &luaB_bit_lshift, 0);
    c.lua_setfield(L, -2, "lshift");
    c.lua_pushcclosure(L, &luaB_bit_rshift, 0);
    c.lua_setfield(L, -2, "rshift");
    c.lua_setglobal(L, "bit");
}

// LuaJIT/Lua 5.1 `bit.*` shims. Use 32-bit semantics (mask to u32) like
// LuaJIT, so bit.bnot(0) == 0xffffffff and bit.bor with negative values
// behaves predictably for durian's HINT_* flag manipulation.
fn bit_arg_u32(L: ?*lua_State, idx: c_int) u32 {
    const v: i64 = @intFromFloat(c.luaL_checknumber(L, idx));
    return @truncate(@as(u64, @bitCast(v)));
}

fn luaB_bit_band(L: ?*lua_State) callconv(.c) c_int {
    const n = c.lua_gettop(L);
    var r: u32 = 0xffffffff;
    var i: c_int = 1;
    while (i <= n) : (i += 1) r &= bit_arg_u32(L, i);
    c.lua_pushinteger(L, @intCast(@as(u64, r)));
    return 1;
}

fn luaB_bit_bor(L: ?*lua_State) callconv(.c) c_int {
    const n = c.lua_gettop(L);
    var r: u32 = 0;
    var i: c_int = 1;
    while (i <= n) : (i += 1) r |= bit_arg_u32(L, i);
    c.lua_pushinteger(L, @intCast(@as(u64, r)));
    return 1;
}

fn luaB_bit_bxor(L: ?*lua_State) callconv(.c) c_int {
    const n = c.lua_gettop(L);
    var r: u32 = 0;
    var i: c_int = 1;
    while (i <= n) : (i += 1) r ^= bit_arg_u32(L, i);
    c.lua_pushinteger(L, @intCast(@as(u64, r)));
    return 1;
}

fn luaB_bit_bnot(L: ?*lua_State) callconv(.c) c_int {
    const v = bit_arg_u32(L, 1);
    c.lua_pushinteger(L, @intCast(@as(u64, ~v)));
    return 1;
}

fn luaB_bit_lshift(L: ?*lua_State) callconv(.c) c_int {
    const v = bit_arg_u32(L, 1);
    const s: u5 = @intCast(@as(i64, @intFromFloat(c.luaL_checknumber(L, 2))) & 31);
    c.lua_pushinteger(L, @intCast(@as(u64, v << s)));
    return 1;
}

fn luaB_bit_rshift(L: ?*lua_State) callconv(.c) c_int {
    const v = bit_arg_u32(L, 1);
    const s: u5 = @intCast(@as(i64, @intFromFloat(c.luaL_checknumber(L, 2))) & 31);
    c.lua_pushinteger(L, @intCast(@as(u64, v >> s)));
    return 1;
}

fn luaB_getfenv_compat(L: ?*lua_State) callconv(.c) c_int {
    // Shape-compatible with durian's `getfenv()` (no-arg) call site.
    // Does NOT honor a function argument — see alua_install_lua51_compat.
    c.lua_pushglobaltable(L);
    return 1;
}

fn luaB_setfenv_compat(L: ?*lua_State) callconv(.c) c_int {
    // No-op. Returns arg 1 (the function/level) so call-site chains
    // like `local f = setfenv(fn, env)` keep the function reference.
    c.lua_settop(L, 1);
    return 1;
}

// --------------------------------------------------------------------------
// 5. arcan_lua_alloc (C:7528-7541)
// --------------------------------------------------------------------------
export fn arcan_lua_alloc(watchdog: ?*const fn (?*lua_State, [*c]c.lua_Debug) callconv(.c) void) ?*lua_State {
    const res: ?*lua_State = c.luaL_newstate();
    luactx.worldid_tag = @as(isize, c.LUA_NOREF);

    if (res != null) {
        c.luaL_openlibs(res);
        alua_install_lua51_compat(res);
    }

    luactx.error_hook = watchdog;
    luactx.last_ctx = res;
    arcan_lua_default_errorhook(res);

    return res;
}

// --------------------------------------------------------------------------
// 6. arcan_lua_mapfunctions (C:7574-7590)
// --------------------------------------------------------------------------
export fn arcan_lua_mapfunctions(ctx: ?*lua_State, debuglevel: c_int) void {
    c.alt_setup_context(ctx, c.arcan_appl_id());
    c.alt_apply_ban(ctx);
    _ = alua_exposefuncs(ctx, @as(u8, @bitCast(@as(i8, @truncate(debuglevel)))));
    c.arcan_lua_pushglobalconsts(ctx);
    c.alt_nbio_register(ctx, &add_source, &del_source, &error_nbio);

    // Only allow eval() style operation in explicit debug modes
    if (lua_debug_level != 0) {
        c.lua_pushlstring(ctx, "loadstring", 10);
        c.lua_pushcclosure(ctx, &luaB_loadstring, 1);
        c.lua_setglobal(ctx, "loadstring");
    }
}

// --------------------------------------------------------------------------
// 7. arcan_lua_dostring (C:7499-7503)
// --------------------------------------------------------------------------
export fn arcan_lua_dostring(ctx: ?*lua_State, code: [*c]const u8, name: [*c]const u8) void {
    if (c.luaL_loadbuffer(ctx, code, c.strlen(code), name) != 0) {
        c.arcan_warning("arcan_lua_dostring(%s): load error: %s\n", name, c.lua_tolstring(ctx, -1, null));
        c.lua_settop(ctx, -2);
        return;
    }
    if (c.lua_pcall(ctx, 0, c.LUA_MULTRET, 0) != 0) {
        c.arcan_warning("arcan_lua_dostring(%s): pcall error: %s\n", name, c.lua_tolstring(ctx, -1, null));
        c.lua_settop(ctx, -2);
        return;
    }
}

// --------------------------------------------------------------------------
// 8. arcan_lua_shutdown (C:7475-7497)
// --------------------------------------------------------------------------
export fn arcan_lua_shutdown(ctx: ?*lua_State) void {
    c.arcan_trace_setbuffer(null, 0, null);
    c.alt_trace_finish(ctx);
    c.alt_nbio_release();

    // Close the open_rawresource fd if still open
    if (luactx.rawres.fd > 0) {
        _ = c.close(luactx.rawres.fd);
        luactx.rawres.fd = -1;
    }

    // Reset state -- some properties carry over between system_collapse calls
    luactx.rawres = std.mem.zeroes(c.struct_nonblock_io);
    luactx.last_segreq = null;
    luactx.pending_socket_label = null;
    luactx.pending_socket_descr = 0;

    c.lua_close(ctx);
}

// --------------------------------------------------------------------------
// 9. arcan_lua_setglobalnum (C:1030-1034)
// --------------------------------------------------------------------------
export fn arcan_lua_setglobalnum(ctx: ?*lua_State, key: [*c]const u8, val: f64) void {
    c.lua_pushnumber(ctx, val);
    c.lua_setglobal(ctx, key);
}

// --------------------------------------------------------------------------
// 10. arcan_lua_setglobalstr (C:1023-1028)
// --------------------------------------------------------------------------
export fn arcan_lua_setglobalstr(ctx: ?*lua_State, key: [*c]const u8, val: [*c]const u8) void {
    c.lua_pushstring(ctx, val);
    c.lua_setglobal(ctx, key);
}

// --------------------------------------------------------------------------
// 11. arcan_lua_callvoidfun (C:7784-7810)
// --------------------------------------------------------------------------
export fn arcan_lua_callvoidfun(
    ctx: ?*lua_State,
    fun: [*c]const u8,
    masksrc: u64,
    warn: bool,
    argv: [*c][*c]const u8,
) bool {
    _ = masksrc;
    // NOTE: Do NOT wrap with zig_foreign_begin/end here. The Lua VM must run
    // under musl TLS. Vulkan calls are wrapped at the agp/video boundary.

    // Track argv for later
    if (argv != null) {
        luactx.last_argv = argv;
    }

    if (c.alt_lookup_entry(ctx, fun, c.strlen(fun))) {
        var argc: c_int = 0;
        c.lua_createtable(ctx, 0, 0);
        const top = c.lua_gettop(ctx);

        while (argv != null and argv[@as(usize, @intCast(argc))] != null) {
            c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(argc + 1)));
            c.lua_pushstring(ctx, argv[@as(usize, @intCast(argc))]);
            argc += 1;
            c.lua_rawset(ctx, top);
        }

        c.alt_call(ctx, c.CB_SOURCE_NONE, @as(u64, @bitCast(@as(c_long, c.EP_TRIGGER_MAIN))), 0, 1, 0, fun);
        return true;
    } else if (warn) {
        c.arcan_warning(@as([*c]const u8, "missing expected symbol ( %s )\n"), fun);
    }

    return false;
}

// --------------------------------------------------------------------------
// 12. arcan_lua_statesnap (C:13889-14006)
// --------------------------------------------------------------------------
export fn arcan_lua_statesnap(dst: ?*c.FILE, tag: [*c]const u8, delim: bool) void {
    const disp: [*c]c.struct_arcan_video_display = &c.arcan_video_display;
    const mmode: c.struct_monitor_mode = c.platform_video_dimensions();

    if (delim) {
        _ = c.fputs(@as([*c]const u8, "#BEGINSTATE\n"), dst);
    }

    _ = c.fprintf(
        dst,
        @as([*c]const u8,
            " do \nlocal nan = 0/0;\nlocal inf = math.huge;\nlocal vobj = {};\n" ++
                "local props = {};\nlocal restbl = {\n\tversion = [[%s]],\n\tdisplay = {\n" ++
                "\t\twidth = %d,\n\t\theight = %d,\n\t\tconservative = %d,\n" ++
                "\t\tticks = %lld,\n\t\tdefault_vitemlim = %d,\n\t\timageproc = %d,\n" ++
                "\t\tscalemode = %d,\n\t\tfiltermode = %d,\n\t},\n\tvcontexts = {}};\n"),
        @as([*c]const u8, "zig-port"),
        @as(c_int, @bitCast(@as(c_uint, @truncate(mmode.width)))),
        @as(c_int, @bitCast(@as(c_uint, @truncate(mmode.height)))),
        @as(c_int, if (disp.*.conservative) 1 else 0),
        @as(c_longlong, @bitCast(@as(c_ulonglong, disp.*.c_ticks))),
        @as(c_int, @bitCast(disp.*.default_vitemlim)),
        @as(c_int, @bitCast(disp.*.imageproc)),
        @as(c_int, @bitCast(disp.*.scalemode)),
        @as(c_int, @bitCast(disp.*.filtermode)),
    );

    _ = c.fprintf(dst, @as([*c]const u8, "restbl.message = "));
    fput_luasafe_str(dst, if (tag != null) tag else @as([*c]const u8, ""));
    _ = c.fprintf(dst, @as([*c]const u8, ";\n"));

    var cctx: c_int = @as(c_int, @bitCast(vcontext_ind));
    while (cctx >= 0) {
        _ = c.fprintf(dst, @as([*c]const u8,
            "local ctx = {\n\tvobjs = {},\n\trtargets = {}\n};"));

        const vctx: [*c]c.struct_arcan_video_context =
            &vcontext_stack[@as(c_uint, @intCast(cctx))];
        _ = c.fprintf(
            dst,
            @as([*c]const u8,
                "ctx.ind = %d;\nctx.alive = %d;\nctx.limit = %d;\nctx.tickstamp = %lld;\n"),
            cctx,
            @as(c_int, @bitCast(@as(c_int, @truncate(vctx.*.nalive)))),
            @as(c_int, @bitCast(vctx.*.vitem_limit)),
            @as(c_longlong, @bitCast(@as(c_ulonglong, vctx.*.last_tickstamp))),
        );

        // Dump each in-use vobject
        {
            var i: usize = 0;
            while (i < @as(usize, @intCast(vctx.*.vitem_limit))) : (i += 1) {
                if ((vctx.*.vitems_pool[i].flags & @as(c_uint, c.FL_INUSE)) == 0) continue;
                dump_vobject(dst, vctx.*.vitems_pool + i);
                _ = c.fprintf(
                    dst,
                    @as([*c]const u8,
                        "vobj.cellid_translated = %ld;\nctx.vobjs[vobj.cellid] = vobj;\n"),
                    @as(c_long, @intFromFloat(vid_toluavid(
                        @as(arcan_vobj_id, @bitCast(@as(c_ulonglong, i))),
                    ))),
                );
            }
        }

        dump_rtgt(dst, &vctx.*.stdoutp);
        {
            var i: usize = 0;
            while (i < @as(usize, @bitCast(vctx.*.n_rtargets))) : (i += 1) {
                dump_rtgt(dst, &vctx.*.rtargets[i]);
            }
        }

        _ = c.fprintf(dst, @as([*c]const u8, "table.insert(restbl.vcontexts, ctx);"));
        cctx -= 1;
    }

    // Benchmark data
    if (benchdata.bench_enabled) {
        const bsz: usize = @sizeOf(@TypeOf(benchdata.ticktime)) / @sizeOf(c_uint);
        const fsz: usize = @sizeOf(@TypeOf(benchdata.frametime)) / @sizeOf(c_uint);
        const csz: usize = @sizeOf(@TypeOf(benchdata.framecost)) / @sizeOf(c_uint);

        var i_u: usize = (@as(usize, @intCast(@as(c_uint, @bitCast(@as(c_int, benchdata.tickofs))))) + 1) % bsz;
        _ = c.fprintf(dst, @as([*c]const u8, "\nrestbl.benchmark = {};\nrestbl.benchmark.ticks = {"));
        while (i_u != @as(usize, @intCast(@as(c_uint, @bitCast(@as(c_int, benchdata.tickofs)))))) {
            _ = c.fprintf(dst, @as([*c]const u8, "%d,"), benchdata.ticktime[i_u]);
            i_u = (i_u + 1) % bsz;
        }

        _ = c.fprintf(dst, @as([*c]const u8, "};\nrestbl.benchmark.frames = {"));
        i_u = (@as(usize, @intCast(@as(c_uint, @bitCast(@as(c_int, benchdata.frameofs))))) + 1) % fsz;
        while (i_u != @as(usize, @intCast(@as(c_uint, @bitCast(@as(c_int, benchdata.frameofs)))))) {
            _ = c.fprintf(dst, @as([*c]const u8, "%d,"), benchdata.frametime[i_u]);
            i_u = (i_u + 1) % fsz;
        }

        _ = c.fprintf(dst, @as([*c]const u8, "};\nrestbl.benchmark.framecost = {"));
        i_u = (@as(usize, @intCast(@as(c_uint, @bitCast(@as(c_int, benchdata.costofs))))) + 1) % csz;
        while (i_u != @as(usize, @intCast(@as(c_uint, @bitCast(@as(c_int, benchdata.costofs)))))) {
            _ = c.fprintf(dst, @as([*c]const u8, "%d,"), benchdata.framecost[i_u]);
            i_u = (i_u + 1) % csz;
        }
        _ = c.fprintf(dst, @as([*c]const u8, "};\n"));

        _ = c.memset(@as(?*anyopaque, @ptrCast(&benchdata.ticktime)), 0, @sizeOf(@TypeOf(benchdata.ticktime)));
        _ = c.memset(@as(?*anyopaque, @ptrCast(&benchdata.frametime)), 0, @sizeOf(@TypeOf(benchdata.frametime)));
        _ = c.memset(@as(?*anyopaque, @ptrCast(&benchdata.framecost)), 0, @sizeOf(@TypeOf(benchdata.framecost)));
        benchdata.tickofs = 0;
        benchdata.frameofs = 0;
        benchdata.costofs = 0;
    }

    _ = c.fprintf(
        dst,
        @as([*c]const u8, "return restbl;\nend\n%s"),
        if (delim) @as([*c]const u8, "#ENDSTATE\n") else @as([*c]const u8, ""),
    );
    _ = c.fflush(dst);
}

// --------------------------------------------------------------------------
// 13. arcan_lua_stategrab (C:14012-14086)
//     Uses static locals in C -- we use Zig file-level vars.
// --------------------------------------------------------------------------
var stategrab_buf: [*c]u8 = null;
var stategrab_sz: usize = 0;
var stategrab_ofs: usize = 0;
var stategrab_poll: c.struct_pollfd = std.mem.zeroes(c.struct_pollfd);

export fn arcan_lua_stategrab(ctx: ?*lua_State, dstfun: [*c]u8, src: c_int) void {
    _ = dstfun;

    // Initial setup
    if (stategrab_buf == null) {
        stategrab_sz = 1024;
        stategrab_buf = @as([*c]u8, @ptrCast(@alignCast(c.arcan_alloc_mem(
            stategrab_sz,
            c.ARCAN_MEM_STRINGBUF,
            c.ARCAN_MEM_TEMPORARY | c.ARCAN_MEM_BZERO,
            c.ARCAN_MEMALIGN_NATURAL,
        ))));
        stategrab_poll.fd = src;
        stategrab_poll.events = c.POLLIN;
    }

    // Flush read into buffer, parse for \n#ENDBLOCK\n
    if (c.poll(&stategrab_poll, 1, 0) > 0) {
        const ntr: usize = (stategrab_sz - 1) - stategrab_ofs;
        const nr: isize = c.read(src, @as(?*anyopaque, @ptrCast(stategrab_buf + stategrab_ofs)), ntr);

        if (nr > 0) {
            stategrab_ofs += @as(usize, @intCast(nr));
            const substrp_raw: [*c]u8 = c.strstr(stategrab_buf, "\n#ENDBLOCK\n");

            if (substrp_raw != null) {
                // Terminate at the \n before #ENDBLOCK
                substrp_raw[1] = 0;

                _ = c.lua_getglobal(ctx, "sample");
                if (c.lua_type(ctx, -1) != c.LUA_TFUNCTION) {
                    c.lua_settop(ctx, -2);
                    c.arcan_warning(@as([*c]const u8, "stategrab(), couldn't find function 'sample' in debugscript. Sample ignored.\n"));
                } else {
                    const top = c.lua_gettop(ctx);
                    _ = c.luaL_loadstring(ctx, stategrab_buf);
                    c.lua_call(ctx, 0, c.LUA_MULTRET);
                    const narg = c.lua_gettop(ctx) - top;
                    c.lua_call(ctx, narg, 0);
                }

                // Advance past \n#ENDBLOCK\n (11 bytes)
                const substrp_end = substrp_raw + 11;
                const dist = @intFromPtr(substrp_end) - @intFromPtr(stategrab_buf);
                if (stategrab_ofs > dist) {
                    const ntm = stategrab_ofs - dist;
                    _ = c.memmove(
                        @as(?*anyopaque, @ptrCast(stategrab_buf)),
                        @as(?*const anyopaque, @ptrCast(substrp_end)),
                        ntm,
                    );
                    stategrab_ofs = ntm;
                } else {
                    stategrab_ofs = 0;
                }
                _ = c.memset(
                    @as(?*anyopaque, @ptrCast(stategrab_buf + stategrab_ofs)),
                    0,
                    stategrab_sz - stategrab_ofs,
                );
            }
        }

        // Grow buffer if full
        if (stategrab_ofs == stategrab_sz - 1) {
            stategrab_sz <<= 1;
            const newp: [*c]u8 = @as([*c]u8, @ptrCast(@alignCast(c.realloc(
                @as(?*anyopaque, @ptrCast(stategrab_buf)),
                stategrab_sz,
            ))));
            if (newp != null) {
                stategrab_buf = newp;
            } else {
                stategrab_sz >>= 1;
            }
        }
    }
}

// --------------------------------------------------------------------------
// 14. arcan_lua_default_errorhook (C:7520-7526)
// --------------------------------------------------------------------------
export fn arcan_lua_default_errorhook(L: ?*lua_State) void {
    _ = L;
    var sa: c.struct_sigaction = std.mem.zeroes(c.struct_sigaction);
    if (@hasField(c.struct_sigaction, "__sigaction_handler")) {
        // glibc: __sigaction_handler is a union with sa_handler/sa_sigaction
        sa.__sigaction_handler = .{ .sa_sigaction = &sig_watchdog };
    } else {
        // musl: __sa_handler is a union with sa_handler/sa_sigaction
        sa.__sa_handler = .{ .sa_sigaction = &sig_watchdog };
    }
    sa.sa_flags = c.SA_SIGINFO;
    _ = c.sigaction(c.SIGUSR1, &sa, null);
}

// --------------------------------------------------------------------------
// 15. arcan_lua_cleanup (C:12625-12627)
// --------------------------------------------------------------------------
export fn arcan_lua_cleanup() void {}

// ==========================================================================
// Section 2: Resource I/O (Lua bindings -- NOT export fn)
// ==========================================================================

// --------------------------------------------------------------------------
// 1. zapresource (C:834-850)
// --------------------------------------------------------------------------
fn zapresource(ctx: ?*lua_State) callconv(.c) c_int {
    const srcpath = c.luaL_checklstring(ctx, 1, null);
    const path = findresource(
        srcpath,
        c.RESOURCE_APPL_TEMP | c.RESOURCE_NS_USER,
        c.ARES_FILE,
        null,
    );

    if (path != null and c.unlink(path) != -1) {
        c.lua_pushboolean(ctx, 1);
    } else {
        c.lua_pushboolean(ctx, 0);
    }

    c.arcan_mem_free(@as(?*anyopaque, @ptrCast(path)));
    return 1;
}

// --------------------------------------------------------------------------
// 2. rawresource (C:852-888)
// --------------------------------------------------------------------------
fn rawresource(ctx: ?*lua_State) callconv(.c) c_int {
    // Can't do more than this due to legacy
    if (luactx.rawres.fd > 0) {
        c.arcan_warning(@as([*c]const u8,
            "open_rawresource(), open requested while other resource " ++
                "still open, use close_rawresource first.\n"));
        _ = c.close(luactx.rawres.fd);
        luactx.rawres.fd = -1;
        luactx.rawres.ofs = 0;
        luactx.rawres.eofm = false;
    }

    const path = findresource(
        c.luaL_checklstring(ctx, 1, null),
        c.DEFAULT_USERMASK,
        c.ARES_FILE | c.ARES_RDONLY,
        null,
    );

    if (path == null) {
        const fname = c.arcan_expand_resource(
            c.luaL_checklstring(ctx, 1, null),
            c.RESOURCE_APPL_TEMP,
        );
        if (fname != null) {
            luactx.rawres.fd = c.open(
                fname,
                c.O_CREAT | c.O_CLOEXEC | c.O_RDWR,
                c.S_IRUSR | c.S_IWUSR,
            );
            c.arcan_mem_free(@as(?*anyopaque, @ptrCast(fname)));
        }
    } else {
        luactx.rawres.fd = c.open(path, c.O_RDONLY | c.O_CLOEXEC);
        c.arcan_mem_free(@as(?*anyopaque, @ptrCast(path)));
    }

    luactx.rawres.lfstrip = true;
    c.lua_pushboolean(ctx, @intFromBool(luactx.rawres.fd > 0));
    return 1;
}

// --------------------------------------------------------------------------
// 3. readrawresource (C:997-1021)
// --------------------------------------------------------------------------
fn readrawresource(ctx: ?*lua_State) callconv(.c) c_int {
    // Push nil first -- for -1 check to not trigger LuaJIT
    c.lua_pushnil(ctx);
    const pos = c.lua_gettop(ctx);

    if (luactx.rawres.eofm) {
        return 1;
    }

    if (luactx.rawres.fd <= 0) {
        return 1;
    }

    const n = c.alt_nbio_process_read(ctx, &luactx.rawres, false);
    if (n != 0) {
        c.lua_remove(ctx, pos);
    } else {
        c.lua_settop(ctx, -2);
    }

    return n;
}

// --------------------------------------------------------------------------
// 4. rawclose (C:1036-1051)
// --------------------------------------------------------------------------
fn rawclose(ctx: ?*lua_State) callconv(.c) c_int {
    const res: bool = false;

    if (luactx.rawres.fd > 0) {
        _ = c.close(luactx.rawres.fd);
        luactx.rawres.fd = -1;
        luactx.rawres.ofs = 0;
        luactx.rawres.eofm = false;
    }

    c.lua_pushboolean(ctx, @intFromBool(res));
    return 1;
}

// --------------------------------------------------------------------------
// 5. pushrawstr (C:1053-1076)
// --------------------------------------------------------------------------
fn pushrawstr(ctx: ?*lua_State) callconv(.c) c_int {
    const mesg = c.luaL_checklstring(ctx, 1, null);
    var ntw: usize = c.strlen(mesg);

    if (ntw > 0 and luactx.rawres.fd > 0) {
        var ofs: usize = 0;

        while (ntw > 0) {
            const nw = c.write(luactx.rawres.fd, @as(?*const anyopaque, @ptrCast(mesg + ofs)), ntw);
            if (nw != -1) {
                ofs += @as(usize, @intCast(nw));
                ntw -= @as(usize, @intCast(nw));
            } else {
                const err = if (is_freestanding) c._errno().* else std.c._errno().*;
                if (err != EAGAIN and err != EINTR) break;
            }
        }
    }

    c.lua_pushboolean(ctx, @intFromBool(ntw == 0));
    return 1;
}

// --------------------------------------------------------------------------
// 6. debugstall (C:1078-1091)
// --------------------------------------------------------------------------
fn debugstall(ctx: ?*lua_State) callconv(.c) c_int {
    const tn: c_int = @as(c_int, @intFromFloat(c.luaL_checknumber(ctx, 1)));
    if (tn <= 0) {
        _ = c.unsetenv("ARCAN_FRAMESERVER_DEBUGSTALL");
    } else {
        var buf: [5]u8 = undefined;
        _ = c.snprintf(&buf, 5, @as([*c]const u8, "%4d"), tn);
        _ = c.setenv("ARCAN_FRAMESERVER_DEBUGSTALL", &buf, 1);
    }

    return 0;
}

// --------------------------------------------------------------------------
// 7. globcb (C:7626-7633) -- callback for glob
// --------------------------------------------------------------------------
const Globs = extern struct {
    ctx: ?*lua_State = null,
    top: c_int = 0,
    index: c_int = 0,
};

fn globcb(arg: [*c]u8, tag: ?*anyopaque) callconv(.c) void {
    const bptr: *Globs = @ptrCast(@alignCast(tag));
    c.lua_pushnumber(bptr.ctx, @as(lua_Number, @floatFromInt(bptr.index)));
    bptr.index += 1;
    c.lua_pushstring(bptr.ctx, arg);
    c.lua_rawset(bptr.ctx, bptr.top);
}

// --------------------------------------------------------------------------
// 8. listns (C:7635-7677) -- list_namespaces binding
// --------------------------------------------------------------------------
fn listns(ctx: ?*lua_State) callconv(.c) c_int {
    var ns: c.struct_arcan_strarr = c.arcan_user_namespaces();
    c.lua_createtable(ctx, 0, 0);

    var count: c_int = 1;
    while (@as(usize, @intCast(count)) <= ns.count and ns.unnamed_0.cdata != null) {
        const cn: [*c]c.struct_arcan_userns = @ptrCast(@alignCast(
            ns.unnamed_0.cdata[@as(usize, @intCast(count - 1))],
        ));
        if (cn == null) break;

        c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(count)));
        c.lua_createtable(ctx, 0, 0);

        c.lua_pushlstring(ctx, "label", 5);
        c.lua_pushstring(ctx, @as([*c]u8, @ptrCast(&cn.*.label)));
        c.lua_rawset(ctx, -3);

        c.lua_pushlstring(ctx, "name", 4);
        c.lua_pushstring(ctx, @as([*c]u8, @ptrCast(&cn.*.name)));
        c.lua_rawset(ctx, -3);

        c.lua_pushlstring(ctx, "read", 4);
        c.lua_pushboolean(ctx, @intFromBool(cn.*.read));
        c.lua_rawset(ctx, -3);

        c.lua_pushlstring(ctx, "write", 5);
        c.lua_pushboolean(ctx, @intFromBool(cn.*.write));
        c.lua_rawset(ctx, -3);

        c.lua_pushlstring(ctx, "ipc", 3);
        c.lua_pushboolean(ctx, @intFromBool(cn.*.ipc));
        c.lua_rawset(ctx, -3);

        c.lua_rawset(ctx, -3);
        count += 1;
    }

    c.arcan_mem_freearr(&ns);
    return 1;
}

// --------------------------------------------------------------------------
// 9. globresource (C:7679-7734) -- glob_resource binding
// --------------------------------------------------------------------------
fn globresource(ctx: ?*lua_State) callconv(.c) c_int {
    var bptr: Globs = .{
        .ctx = ctx,
        .top = 0,
        .index = 1,
    };

    const label: [*c]u8 = c.strdup(c.luaL_checklstring(ctx, 1, null));
    var userns: [*c]const u8 = null;
    var mask: c_int = c.DEFAULT_USERMASK;

    if (c.lua_type(ctx, 2) == c.LUA_TSTRING) {
        userns = c.lua_tolstring(ctx, 2, null);
    } else if (c.lua_type(ctx, 2) == c.LUA_TNUMBER) {
        mask = @as(c_int, @intFromFloat(c.luaL_checknumber(ctx, 2)));
        mask &= (c.DEFAULT_USERMASK |
            c.RESOURCE_APPL_STATE |
            c.RESOURCE_SYS_APPLBASE |
            c.RESOURCE_SYS_FONT);
    }

    var asynch: bool = false;
    if (c.lua_type(ctx, 3) == c.LUA_TBOOLEAN) {
        asynch = c.lua_toboolean(ctx, 3) != 0;
    }

    if (asynch) {
        var fd: c_int = undefined;
        if (userns != null) {
            _ = c.arcan_glob_userns(label, userns, null, &fd, null);
        } else {
            _ = c.arcan_glob(label, @as(c_uint, @bitCast(mask)), null, &fd, null);
        }
        var dst: [*c]c.struct_nonblock_io = undefined;
        _ = c.alt_nbio_import(ctx, fd, 0, &dst, null);
    } else {
        c.lua_createtable(ctx, 0, 0);
        bptr.top = c.lua_gettop(ctx);

        if (userns != null) {
            _ = c.arcan_glob_userns(
                label,
                userns,
                &globcb,
                null,
                @as(?*anyopaque, @ptrCast(&bptr)),
            );
        } else {
            _ = c.arcan_glob(
                label,
                @as(c_uint, @bitCast(mask)),
                &globcb,
                null,
                @as(?*anyopaque, @ptrCast(&bptr)),
            );
        }
    }

    c.free(@as(?*anyopaque, @ptrCast(label)));
    return 1;
}

// --------------------------------------------------------------------------
// 10. resource (C:7736-7760) -- resource() binding
// --------------------------------------------------------------------------
fn resource(ctx: ?*lua_State) callconv(.c) c_int {
    const label = c.luaL_checklstring(ctx, 1, null);
    const mask: c_int = @as(c_int, @truncate(c.luaL_optinteger(
        ctx,
        2,
        @as(c.lua_Integer, @bitCast(@as(c_long, c.DEFAULT_USERMASK))),
    )));
    const res = c.arcan_find_resource(
        label,
        @as(c_uint, @bitCast(mask)),
        c.ARES_FILE | c.ARES_FOLDER,
        null,
    );

    if (res == null) {
        c.lua_pushstring(ctx, res);
        c.lua_pushlstring(ctx, "not found", 9);
    } else {
        c.lua_pushstring(ctx, res);
        if (c.arcan_isdir(res)) {
            c.lua_pushlstring(ctx, "directory", 9);
        } else {
            c.lua_pushlstring(ctx, "file", 4);
        }
        c.arcan_mem_free(@as(?*anyopaque, @ptrCast(res)));
    }

    return 2;
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part3.zig
// ══════════════════════════════════════════════════════════════════════

// === Section 3: Image Loading & Transforms + Section 4: Audio ===
//
// Ported from src/engine/arcan_lua.c lines 1093-1931.
// Uses helpers from arcan_lua_header.zig (lua_pushvid, luaL_checkvid, etc.)






// These are static functions in arcan_lua.c that will be made visible
// when the full file is ported. For now, declare as extern so we can
// link against the C object that still contains them.


// Section 3: Image Loading & Transforms

pub fn loadimage(ctx: ?*lua_State) callconv(.c) c_int {
    const srcstr = c.luaL_checklstring(ctx, 1, null);
    const path = findresource(
        srcstr,
        c.DEFAULT_USERMASK,
        c.ARES_FILE | c.ARES_RDONLY,
        null,
    );

    const prio: u8 = @intCast(@as(c_uint, @bitCast(luaL_optint(ctx, 2, 0))));
    const desw: c_uint = @bitCast(luaL_optint(ctx, 3, 0));
    const desh: c_uint = @bitCast(luaL_optint(ctx, 4, 0));

    var id: arcan_vobj_id = c.ARCAN_EID;
    if (path != null) {
        id = c.arcan_video_loadimage(path, c.img_cons{
            .w = desw,
            .h = desh,
            .bpp = 0,
        }, @intCast(prio));
        c.arcan_mem_free(@ptrCast(path));
    }

    lua_pushvid(ctx, id);
    trace_allocation(ctx, "load_image", id);
    return 1;
}

pub fn loadimageasynch(ctx: ?*lua_State) callconv(.c) c_int {
    var id: arcan_vobj_id = c.ARCAN_EID;
    var ref: isize = 0;

    const srcstr = c.luaL_checklstring(ctx, 1, null);
    const path = findresource(
        srcstr,
        c.DEFAULT_USERMASK,
        c.ARES_FILE | c.ARES_RDONLY,
        null,
    );

    if (c.lua_type(ctx, 2) == c.LUA_TFUNCTION and c.lua_iscfunction(ctx, 2) == 0) {
        c.lua_pushvalue(ctx, 2);
        ref = c.luaL_ref(ctx, c.LUA_REGISTRYINDEX);
    }

    if (path != null and c.strlen(path) > 0) {
        id = c.arcan_video_loadimageasynch(path, std.mem.zeroes(c.img_cons), ref);
    }
    c.arcan_mem_free(@ptrCast(path));

    lua_pushvid(ctx, id);
    trace_allocation(ctx, "load_image_asynch", id);
    return 1;
}

pub fn imageloaded(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 1, &vobj);

    c.lua_pushnumber(ctx, @floatFromInt(
        @intFromBool(vobj.*.feed.state.tag == c.ARCAN_TAG_IMAGE),
    ));
    return 1;
}

pub fn moveimage(ctx: ?*lua_State) callconv(.c) c_int {
    const newx: f32 = @floatCast(luaL_optnumber_alt(ctx, 2, 0));
    const newy: f32 = @floatCast(luaL_optnumber_alt(ctx, 3, 0));
    var time = luaL_optint(ctx, 4, 0);
    const interp = luaL_optint(ctx, 5, -1);

    if (time < 0) time = 0;

    const argtype = c.lua_type(ctx, 1);
    if (argtype == c.LUA_TNUMBER) {
        const id = luaL_checkvid(ctx, 1, null);
        _ = c.arcan_video_objectmove(id, newx, newy, 1.0, @bitCast(time));
        if (time > 0 and interp >= 0 and interp < c.ARCAN_VINTER_ENDMARKER)
            _ = c.arcan_video_moveinterp(id, @bitCast(interp));
    } else if (argtype == c.LUA_TTABLE) {
        const nelems: usize = @intCast(c.lua_objlen(ctx, 1));
        for (0..nelems) |i| {
            _ = c.lua_rawgeti(ctx, 1, @intCast(i + 1));
            const id = luaL_checkvid(ctx, -1, null);
            _ = c.arcan_video_objectmove(id, newx, newy, 1.0, @bitCast(time));
            if (time > 0 and interp >= 0 and interp < c.ARCAN_VINTER_ENDMARKER)
                _ = c.arcan_video_moveinterp(id, @bitCast(interp));
            c.lua_settop(ctx, -1 - 1);
        }
    } else {
        c.arcan_fatal("move_image(), invalid argument (1) " ++
            "expected VID or indexed table of VIDs\n");
    }

    return 0;
}

pub fn nudgeimage(ctx: ?*lua_State) callconv(.c) c_int {
    const newx: f32 = @floatCast(luaL_optnumber_alt(ctx, 2, 0));
    const newy: f32 = @floatCast(luaL_optnumber_alt(ctx, 3, 0));
    var time = luaL_optint(ctx, 4, 0);
    const interp = luaL_optint(ctx, 5, -1);

    if (time < 0) time = 0;
    const use_interp = time > 0 and interp >= 0 and interp < c.ARCAN_VINTER_ENDMARKER;

    const argtype = c.lua_type(ctx, 1);
    if (argtype == c.LUA_TNUMBER) {
        const id = luaL_checkvid(ctx, 1, null);
        const props = c.arcan_video_current_properties(id);
        _ = c.arcan_video_objectmove(
            id,
            props.position.unnamed_0.unnamed_0.x + newx,
            props.position.unnamed_0.unnamed_0.y + newy,
            1.0,
            @bitCast(time),
        );
        if (use_interp)
            _ = c.arcan_video_moveinterp(id, @bitCast(interp));
    } else if (argtype == c.LUA_TTABLE) {
        const nelems: usize = @intCast(c.lua_objlen(ctx, 1));
        for (0..nelems) |i| {
            _ = c.lua_rawgeti(ctx, 1, @intCast(i + 1));
            const id = luaL_checkvid(ctx, -1, null);
            const props = c.arcan_video_current_properties(id);
            _ = c.arcan_video_objectmove(
                id,
                props.position.unnamed_0.unnamed_0.x + newx,
                props.position.unnamed_0.unnamed_0.y + newy,
                1.0,
                @bitCast(time),
            );
            if (use_interp)
                _ = c.arcan_video_moveinterp(id, @bitCast(interp));
            c.lua_settop(ctx, -1 - 1);
        }
    } else {
        c.arcan_fatal("nudge_image(), invalid argument (1) " ++
            "expected VID or indexed table of VIDs\n");
    }

    return 0;
}

pub fn resettransform(ctx: ?*lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    var left: [4]c_uint = undefined;
    const mask: c_int = @intFromFloat(luaL_optnumber_alt(ctx, 2, 0));

    _ = c.arcan_video_zaptransform(id, mask, &left);
    c.lua_pushnumber(ctx, @floatFromInt(left[0]));
    c.lua_pushnumber(ctx, @floatFromInt(left[1]));
    c.lua_pushnumber(ctx, @floatFromInt(left[2]));
    c.lua_pushnumber(ctx, @floatFromInt(left[3]));
    return 4;
}

pub fn instanttransform(ctx: ?*lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);

    var mask: c_int = 0;
    var last: bool = false;
    var all: bool = false;

    if (c.lua_isnumber(ctx, 2) != 0) {
        mask = @intFromFloat(c.lua_tonumber(ctx, 2));
    } else if (c.lua_type(ctx, 2) == c.LUA_TBOOLEAN) {
        last = c.lua_toboolean(ctx, 2) != 0;
        all = luaL_optbnumber(ctx, 3, false);
    }

    var method: c_int = c.TAG_TRANSFORM_SKIP;
    if (last)
        method = c.TAG_TRANSFORM_LAST;
    if (all)
        method = c.TAG_TRANSFORM_ALL;

    _ = c.arcan_video_instanttransform(id, mask, @bitCast(method));
    return 0;
}

pub fn cycletransform(ctx: ?*lua_State) callconv(.c) c_int {
    const sid = luaL_checkvid(ctx, 1, null);
    const flag = luaL_checkbnumber(ctx, 2);
    _ = c.arcan_video_transformcycle(sid, flag);
    return 0;
}

pub fn copytransform(ctx: ?*lua_State) callconv(.c) c_int {
    const sid = luaL_checkvid(ctx, 1, null);
    const did = luaL_checkvid(ctx, 2, null);
    _ = c.arcan_video_copytransform(sid, did);
    return 0;
}

pub fn transfertransform(ctx: ?*lua_State) callconv(.c) c_int {
    const sid = luaL_checkvid(ctx, 1, null);
    const did = luaL_checkvid(ctx, 2, null);
    _ = c.arcan_video_transfertransform(sid, did);
    return 0;
}

pub fn rotateimage(ctx: ?*lua_State) callconv(.c) c_int {
    const ang: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    const time = luaL_optint(ctx, 3, 0);

    const argtype = c.lua_type(ctx, 1);
    if (argtype == c.LUA_TNUMBER) {
        const id = luaL_checkvid(ctx, 1, null);
        _ = c.arcan_video_objectrotate(id, ang, @bitCast(time));
    } else if (argtype == c.LUA_TTABLE) {
        const nelems: usize = @intCast(c.lua_objlen(ctx, 1));
        for (0..nelems) |i| {
            _ = c.lua_rawgeti(ctx, 1, @intCast(i + 1));
            const id = luaL_checkvid(ctx, -1, null);
            _ = c.arcan_video_objectrotate(id, ang, @bitCast(time));
            c.lua_settop(ctx, -1 - 1);
        }
    } else {
        c.arcan_fatal("rotate_image(), invalid argument (1) " ++
            "expected VID or indexed table of VIDs\n");
    }

    return 0;
}

pub fn resampleimage(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const sid = luaL_checkvid(ctx, 1, &vobj);

    const shid: c.agp_shader_id = if (c.lua_type(ctx, 2) == c.LUA_TSTRING)
        c.agp_shader_lookup(c.luaL_checklstring(ctx, 2, null))
    else
        @intFromFloat(c.luaL_checknumber(ctx, 2));

    const raw_w: c_int = @intFromFloat(c.luaL_checknumber(ctx, 3));
    const raw_h: c_int = @intFromFloat(c.luaL_checknumber(ctx, 4));
    const width: usize = @intCast(if (raw_w < 0) -raw_w else raw_w);
    const height: usize = @intCast(if (raw_h < 0) -raw_h else raw_h);
    var nosynch: bool = false;

    const did: arcan_vobj_id = if (c.lua_type(ctx, 5) == c.LUA_TNUMBER)
        luaL_checkvid(ctx, 5, null)
    else
        c.ARCAN_EID;

    if (c.lua_type(ctx, 5) == c.LUA_TBOOLEAN)
        nosynch = c.lua_toboolean(ctx, 5) != 0
    else if (c.lua_type(ctx, 6) == c.LUA_TBOOLEAN)
        nosynch = c.lua_toboolean(ctx, 6) != 0;

    if (width == 0 or width > @as(usize, @intCast(MAX_SURFACEW)) or
        height == 0 or height > @as(usize, @intCast(MAX_SURFACEH)))
    {
        c.arcan_fatal(
            "resample_image(), illegal dimensions" ++
                " requested (%d:%d x %d:%d)\n",
            width,
            MAX_SURFACEW,
            height,
            MAX_SURFACEH,
        );
    }

    const osh = vobj.*.program;
    if (c.ARCAN_OK != c.arcan_video_setprogram(sid, shid)) {
        c.arcan_warning(
            "arcan_video_setprogram(%d, %d) -- couldn't set shader," ++
                "invalid vobj or shader id specified.\n",
            sid,
            shid,
        );
    } else {
        _ = c.arcan_video_resampleobject(sid, did, width, height, shid, nosynch);
        vobj.*.program = osh;
    }

    return 0;
}

pub fn imageresizestorage(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const id = luaL_checkvid(ctx, 1, &vobj);

    const raw_w: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));
    const raw_h: c_int = @intFromFloat(c.luaL_checknumber(ctx, 3));
    // (debug removed — std.posix not available on freestanding)
    const w: usize = @intCast(if (raw_w < 0) -raw_w else raw_w);
    const h: usize = @intCast(if (raw_h < 0) -raw_h else raw_h);

    if (w == 0 or w > @as(usize, @intCast(MAX_SURFACEW)) or
        h == 0 or h > @as(usize, @intCast(MAX_SURFACEH)))
    {
        c.arcan_fatal(
            "image_resize_storage(), illegal dimensions" ++
                "\trequested (%d:%d x %d:%d)\n",
            w,
            MAX_SURFACEW,
            h,
            MAX_SURFACEH,
        );
    }

    vobj.*.origw = @truncate(w);
    vobj.*.origh = @truncate(h);

    const rtgt = c.arcan_vint_findrt(vobj);
    if (rtgt != null) {
        c.agp_resize_rendertarget(rtgt.*.art, w, h);

        const view_w: isize = @intFromFloat(luaL_optnumber_alt(ctx, 4, @floatFromInt(w)));
        const view_h: isize = @intFromFloat(luaL_optnumber_alt(ctx, 5, @floatFromInt(h)));
        const x: isize = @intFromFloat(luaL_optnumber_alt(ctx, 6, 0));
        const y: isize = @intFromFloat(luaL_optnumber_alt(ctx, 7, 0));

        if (!rtgt.*.inv_y)
            c.build_orthographic_matrix(
                @ptrCast(&rtgt.*.projection),
                @floatFromInt(x),
                @floatFromInt(w),
                @floatFromInt(y),
                @floatFromInt(h),
                0,
                1,
            )
        else
            c.build_orthographic_matrix(
                @ptrCast(&rtgt.*.projection),
                @floatFromInt(x),
                @floatFromInt(w),
                @floatFromInt(h),
                @floatFromInt(y),
                0,
                1,
            );

        c.agp_rendertarget_viewport(rtgt.*.art, x, y, x + view_w, y + view_h);
        _int_flag(vobj);
        c.arcan_video_display.dirty += 1;
    } else {
        _ = c.arcan_video_resizefeed(id, w, h);
    }
    return 0;
}

pub fn centerimage(ctx: ?*lua_State) callconv(.c) c_int {
    var sobj: [*c]c.arcan_vobject = undefined;
    const src = luaL_checkvid(ctx, 1, &sobj);
    const obj = luaL_checkvid(ctx, 2, null);
    const al: c_int = @intFromFloat(luaL_optnumber_alt(ctx, 3, @floatFromInt(c.ANCHORP_C)));
    const xofs: c_int = @intFromFloat(luaL_optnumber_alt(ctx, 4, 0));
    const yofs: c_int = @intFromFloat(luaL_optnumber_alt(ctx, 5, 0));

    const sprop = c.arcan_video_resolve_properties(src);
    const dprop = c.arcan_video_resolve_properties(obj);

    // center point of source
    const cp_sx: c_int = @intFromFloat(@as(f64, @floatCast(sprop.position.unnamed_0.unnamed_0.x)) +
        @as(f64, @floatCast(sprop.scale.unnamed_0.unnamed_0.x)) * 0.5);
    const cp_sy: c_int = @intFromFloat(@as(f64, @floatCast(sprop.position.unnamed_0.unnamed_0.y)) +
        @as(f64, @floatCast(sprop.scale.unnamed_0.unnamed_0.y)) * 0.5);

    // anchor point on destination
    var ap_x: c_int = @intFromFloat(dprop.position.unnamed_0.unnamed_0.x);
    var ap_y: c_int = @intFromFloat(dprop.position.unnamed_0.unnamed_0.y);

    switch (al) {
        c.ANCHORP_C => {
            ap_x += @intFromFloat(@as(f64, @floatCast(dprop.scale.unnamed_0.unnamed_0.x)) * 0.5);
            ap_y += @intFromFloat(@as(f64, @floatCast(dprop.scale.unnamed_0.unnamed_0.y)) * 0.5);
        },
        c.ANCHORP_UC => {
            ap_x += @intFromFloat(@as(f64, @floatCast(dprop.scale.unnamed_0.unnamed_0.x)) * 0.5);
        },
        c.ANCHORP_LC => {
            ap_x += @intFromFloat(@as(f64, @floatCast(dprop.scale.unnamed_0.unnamed_0.x)) * 0.5);
            ap_y += @intFromFloat(dprop.scale.unnamed_0.unnamed_0.y);
        },
        c.ANCHORP_CL => {
            ap_y += @intFromFloat(@as(f64, @floatCast(dprop.scale.unnamed_0.unnamed_0.y)) * 0.5);
        },
        c.ANCHORP_CR => {
            ap_x += @intFromFloat(dprop.scale.unnamed_0.unnamed_0.x);
            ap_y += @intFromFloat(@as(f64, @floatCast(dprop.scale.unnamed_0.unnamed_0.y)) * 0.5);
        },
        c.ANCHORP_UL => {},
        c.ANCHORP_UR => {
            ap_x += @intFromFloat(dprop.scale.unnamed_0.unnamed_0.x);
        },
        c.ANCHORP_LL => {
            ap_y += @intFromFloat(dprop.scale.unnamed_0.unnamed_0.y);
        },
        c.ANCHORP_LR => {
            ap_x += @intFromFloat(dprop.scale.unnamed_0.unnamed_0.x);
            ap_y += @intFromFloat(dprop.scale.unnamed_0.unnamed_0.y);
        },
        else => {
            c.arcan_fatal("center_image(), unknown anchor point (%d)\n", al);
        },
    }

    _ = c.arcan_video_objectmove(
        src,
        sobj.*.current.position.unnamed_0.unnamed_0.x + @as(f32, @floatFromInt(ap_x)) -
            @as(f32, @floatFromInt(cp_sx)) + @as(f32, @floatFromInt(xofs)),
        sobj.*.current.position.unnamed_0.unnamed_0.y + @as(f32, @floatFromInt(ap_y)) -
            @as(f32, @floatFromInt(cp_sy)) + @as(f32, @floatFromInt(yofs)),
        1.0,
        0,
    );

    return 0;
}

pub fn cropimage(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const id = luaL_checkvid(ctx, 1, &vobj);
    const w: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    const h: f32 = @floatCast(c.luaL_checknumber(ctx, 3));

    const prop = c.arcan_video_initial_properties(id);
    var ss: f32 = 1.0;
    var st: f32 = 1.0;
    var crop_st: bool = false;

    if (prop.scale.unnamed_0.unnamed_0.x > w) {
        ss = w / prop.scale.unnamed_0.unnamed_0.x;
        crop_st = true;
    }
    if (prop.scale.unnamed_0.unnamed_0.y > h) {
        st = h / prop.scale.unnamed_0.unnamed_0.y;
        crop_st = true;
    }

    _ = c.arcan_video_objectscale(id, ss, st, 1.0, 0);
    if (crop_st)
        _ = c.arcan_video_scaletxcos(id, ss, st);

    return 0;
}

// resize_image — absolute values, arcan_video_objectscale takes relative to initial
pub fn scaleimage2(ctx: ?*lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    var raw_w: f64 = c.luaL_checknumber(ctx, 2);
    var raw_h: f64 = c.luaL_checknumber(ctx, 3);
    if (!std.math.isFinite(raw_w)) raw_w = 0;
    if (!std.math.isFinite(raw_h)) raw_h = 0;
    var neww: f32 = @floatCast(raw_w);
    var newh: f32 = @floatCast(raw_h);

    var time = luaL_optint(ctx, 4, 0);
    const interp = luaL_optint(ctx, 5, -1);
    const use_interp = time > 0 and interp >= 0 and interp < c.ARCAN_VINTER_ENDMARKER;

    if (time < 0) time = 0;

    if (neww < c.EPSILON and newh < c.EPSILON) {
        return 0;
    }

    const prop = c.arcan_video_initial_properties(id);
    if (prop.scale.unnamed_0.unnamed_0.x < c.EPSILON and prop.scale.unnamed_0.unnamed_0.y < c.EPSILON) {
        c.lua_pushnumber(ctx, 0);
        c.lua_pushnumber(ctx, 0);
    } else {
        // retain aspect ratio in scale
        if (neww < c.EPSILON and newh > c.EPSILON)
            neww = newh * (prop.scale.unnamed_0.unnamed_0.x / prop.scale.unnamed_0.unnamed_0.y)
        else if (neww > c.EPSILON and newh < c.EPSILON)
            newh = neww * (prop.scale.unnamed_0.unnamed_0.y / prop.scale.unnamed_0.unnamed_0.x);

        neww = @ceil(neww);
        newh = @ceil(newh);
        _ = c.arcan_video_objectscale(
            id,
            neww / prop.scale.unnamed_0.unnamed_0.x,
            newh / prop.scale.unnamed_0.unnamed_0.y,
            1.0,
            @bitCast(time),
        );

        if (use_interp)
            _ = c.arcan_video_scaleinterp(id, @bitCast(interp));

        c.lua_pushnumber(ctx, @floatCast(neww));
        c.lua_pushnumber(ctx, @floatCast(newh));
    }

    return 2;
}

pub fn scaleimage(ctx: ?*lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);

    var desw: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    var desh: f32 = @floatCast(c.luaL_checknumber(ctx, 3));
    var time = luaL_optint(ctx, 4, 0);
    const interp = luaL_optint(ctx, 5, -1);
    if (time < 0) time = 0;
    const use_interp = time > 0 and interp >= 0 and interp < c.ARCAN_VINTER_ENDMARKER;

    const prop = c.arcan_video_initial_properties(id);

    // retain aspect ratio in scale
    if (desw < c.EPSILON and desh > c.EPSILON)
        desw = desh * (prop.scale.unnamed_0.unnamed_0.x / prop.scale.unnamed_0.unnamed_0.y)
    else if (desw > c.EPSILON and desh < c.EPSILON)
        desh = desw * (prop.scale.unnamed_0.unnamed_0.y / prop.scale.unnamed_0.unnamed_0.x);

    _ = c.arcan_video_objectscale(id, desw, desh, 1.0, @bitCast(time));
    if (use_interp)
        _ = c.arcan_video_scaleinterp(id, @bitCast(interp));

    c.lua_pushnumber(ctx, @floatCast(desw));
    c.lua_pushnumber(ctx, @floatCast(desh));

    return 2;
}

pub fn orderimage(ctx: ?*lua_State) callconv(.c) c_int {
    const zv: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));

    const argtype = c.lua_type(ctx, 1);
    if (argtype == c.LUA_TNUMBER) {
        const id = luaL_checkvid(ctx, 1, null);
        _ = c.arcan_video_setzv(id, zv);
    } else if (argtype == c.LUA_TTABLE) {
        const nelems: usize = @intCast(c.lua_objlen(ctx, 1));
        for (0..nelems) |i| {
            _ = c.lua_rawgeti(ctx, 1, @intCast(i + 1));
            const id = luaL_checkvid(ctx, -1, null);
            _ = c.arcan_video_setzv(id, zv);
            c.lua_settop(ctx, -1 - 1);
        }
    } else {
        c.arcan_fatal("order_image(), invalid argument (1) " ++
            "expected VID or indexed table of VIDs\n");
    }

    return 0;
}

pub fn maxorderimage(ctx: ?*lua_State) callconv(.c) c_int {
    var rtgt: arcan_vobj_id = @intFromFloat(
        luaL_optnumber_alt(ctx, 1, @floatFromInt(c.ARCAN_VIDEO_WORLDID)),
    );

    if (rtgt != c.ARCAN_EID and rtgt != c.ARCAN_VIDEO_WORLDID)
        rtgt -= @intCast(lua_vid_base);

    var rv: u16 = 0;
    _ = c.arcan_video_maxorder(rtgt, &rv);
    c.lua_pushnumber(ctx, @floatFromInt(rv));
    return 1;
}

// helper, not a Lua binding — called by imageopacity, showimage, hideimage
pub fn massopacity(ctx: ?*lua_State, val: f32, caller: [*c]const u8) void {
    const time = luaL_optint(ctx, 3, 0);
    const interp = luaL_optint(ctx, 4, -1);

    const use_interp = time > 0 and interp >= 0 and interp < c.ARCAN_VINTER_ENDMARKER;

    const argtype = c.lua_type(ctx, 1);
    if (argtype == c.LUA_TNUMBER) {
        const id = luaL_checkvid(ctx, 1, null);
        _ = c.arcan_video_objectopacity(id, val, @bitCast(time));
        if (use_interp)
            _ = c.arcan_video_blendinterp(id, @bitCast(interp));
    } else if (argtype == c.LUA_TTABLE) {
        const nelems: usize = @intCast(c.lua_objlen(ctx, 1));
        for (0..nelems) |i| {
            _ = c.lua_rawgeti(ctx, 1, @intCast(i + 1));
            const id = luaL_checkvid(ctx, -1, null);
            _ = c.arcan_video_objectopacity(id, val, @bitCast(time));
            if (use_interp)
                _ = c.arcan_video_blendinterp(id, @bitCast(interp));
            c.lua_settop(ctx, -1 - 1);
        }
    } else {
        c.arcan_fatal("%s(), invalid argument (1) " ++
            "expected VID or indexed table of VIDs\n", caller);
    }
}

pub fn imageopacity(ctx: ?*lua_State) callconv(.c) c_int {
    const val: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    massopacity(ctx, val, "blend_image");
    return 0;
}

pub fn showimage(ctx: ?*lua_State) callconv(.c) c_int {
    massopacity(ctx, 1.0, "show_image");
    return 0;
}

pub fn hideimage(ctx: ?*lua_State) callconv(.c) c_int {
    massopacity(ctx, 0.0, "hide_image");
    return 0;
}

pub fn forceblend(ctx: ?*lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const raw: c_int = @intFromFloat(luaL_optnumber_alt(ctx, 2, @floatFromInt(c.BLEND_FORCE)));
    const mode: c_uint = @bitCast(if (raw < 0) -raw else raw);
    _ = c.arcan_video_forceblend(id, mode);
    return 0;
}

pub fn imagepersist(ctx: ?*lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    c.lua_pushboolean(ctx, @intFromBool(c.arcan_video_persistobject(id) == c.ARCAN_OK));
    return 1;
}

// Section 4: Audio

pub fn dropaudio(ctx: ?*lua_State) callconv(.c) c_int {
    _ = c.arcan_audio_stop(@intCast(luaL_checkaid(ctx, 1)));
    return 0;
}

pub fn gain(ctx: ?*lua_State) callconv(.c) c_int {
    const id: arcan_aobj_id = @intCast(luaL_checkaid(ctx, 1));

    if (c.lua_type(ctx, 2) != c.LUA_TNIL) {
        const gval: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
        const time: u16 = @truncate(@as(c_uint, @bitCast(luaL_optint(ctx, 3, 0))));
        _ = c.arcan_audio_setgain(id, gval, time);
    }

    var dgain: f32 = undefined;
    if (c.ARCAN_OK == c.arcan_audio_getgain(id, &dgain)) {
        c.lua_pushnumber(ctx, @floatCast(dgain));
        return 1;
    }

    return 0;
}

pub fn audiopos(ctx: ?*lua_State) callconv(.c) c_int {
    const id: arcan_aobj_id = @intCast(luaL_checkaid(ctx, 1));
    const vid = luaL_checkvid(ctx, 2, null);
    c.arcan_audio_position(id, vid);
    return 0;
}

pub fn audioout(ctx: ?*lua_State) callconv(.c) c_int {
    c.lua_createtable(ctx, 0, 0);
    var outputs = c.arcan_audio_scan_devices();
    var count: usize = 1;

    while (outputs != null) {
        const len = c.strlen(outputs);
        if (len == 0) break;
        c.lua_pushnumber(ctx, @floatFromInt(count));
        count += 1;
        c.lua_pushlstring(ctx, outputs, len);
        c.lua_rawset(ctx, -3);
        outputs += len + 1;
    }

    return 1;
}

pub fn audioreconf(ctx: ?*lua_State) callconv(.c) c_int {
    var cfg = c.arcan_audio_cfg{
        .hrtf = false,
        .out = null,
    };

    if (c.lua_type(ctx, 1) == c.LUA_TTABLE) {
        cfg.hrtf = intblbool(ctx, 1, "hrtf");
        cfg.out = intblstr(ctx, 1, "output");
    }

    c.lua_pushnumber(ctx, @floatFromInt(c.arcan_audio_reconfigure(cfg)));
    return 0;
}

pub fn audiolisten(ctx: ?*lua_State) callconv(.c) c_int {
    const vid = luaL_checkvid(ctx, 1, null);
    c.arcan_audio_listener(vid);
    return 0;
}

pub fn abufsz(ctx: ?*lua_State) callconv(.c) c_int {
    var new_sz: usize = @intFromFloat(c.luaL_checknumber(ctx, 1));

    if (new_sz != 0 and new_sz < 1024) {
        c.arcan_warning("audio_buffer_size(), input size too small, forcing 1024\n");
        new_sz = 1024;
    } else if (new_sz > 32768) {
        c.arcan_warning("audio_buffer_size(), excessively large buffer, capping" ++
            "to 32k\n");
        new_sz = 32768;
    } else if (new_sz != 0 and (new_sz % (@sizeOf(c.shmif_asample) * @as(usize, @intCast(c.ARCAN_SHMIF_ACHANNELS)))) != 0) {
        c.arcan_warning("audio_buffer_size(%zu), useless size, " ++
            "growing to align with sample size\n");
        new_sz += new_sz % (@sizeOf(c.shmif_asample) * @as(usize, @intCast(c.ARCAN_SHMIF_ACHANNELS)));
    }

    c.lua_pushnumber(ctx, @floatFromInt(c.platform_fsrv_default_abufsize(new_sz)));
    return 1;
}

pub fn playaudio(ctx: ?*lua_State) callconv(.c) c_int {
    const id: arcan_aobj_id = @intCast(luaL_checkaid(ctx, 1));
    const ref: isize = find_lua_callback(ctx);

    if (c.lua_isnumber(ctx, 2) != 0)
        _ = c.arcan_audio_play(id, true, @floatCast(c.luaL_checknumber(ctx, 2)), ref)
    else
        _ = c.arcan_audio_play(id, false, 0.0, ref);

    return 0;
}

pub fn captureaudio(ctx: ?*lua_State) callconv(.c) c_int {
    var cptlist = c.arcan_audio_capturelist();
    const luach = c.luaL_checklstring(ctx, 1, null);

    var match: bool = false;
    while (cptlist.* != null and !match) {
        match = c.strcmp(cptlist.*, luach) == 0;
        cptlist += 1;
    }

    if (match) {
        lua_pushaid(ctx, c.arcan_audio_capturefeed(luach));
        return 1;
    }

    return 0;
}

pub fn capturelist(ctx: ?*lua_State) callconv(.c) c_int {
    var cptlist = c.arcan_audio_capturelist();
    var count: c_int = 1;

    c.lua_createtable(ctx, 0, 0);
    const top = c.lua_gettop(ctx);

    while (cptlist.* != null) {
        c.lua_pushnumber(ctx, @floatFromInt(count));
        count += 1;
        c.lua_pushstring(ctx, cptlist.*);
        c.lua_rawset(ctx, top);
        cptlist += 1;
    }

    return 1;
}

pub fn loadasample(ctx: ?*lua_State) callconv(.c) c_int {
    // table-to-buffer path
    if (c.lua_type(ctx, -1) == c.LUA_TTABLE) {
        var buf: [*c]f32 = undefined;
        var n_ch: c_int = 2;
        var ofs: c_int = 1;
        var fmt: [*c]const u8 = "stereo";
        var rate: c_int = 48000;

        if (c.lua_type(ctx, ofs) == c.LUA_TNUMBER) {
            n_ch = @intFromFloat(c.lua_tonumber(ctx, ofs));
            ofs += 1;
        }
        if (c.lua_type(ctx, ofs) == c.LUA_TNUMBER) {
            rate = @intFromFloat(c.lua_tonumber(ctx, ofs));
            ofs += 1;
        }
        if (c.lua_type(ctx, ofs) == c.LUA_TSTRING) {
            fmt = c.lua_tolstring(ctx, ofs, null);
            ofs += 1;
        }

        var n: usize = 0;
        if (!stack_to_farray(ctx, c.ARCAN_MEM_ABUFFER, &buf, &n, 0)) {
            lua_pushaid(ctx, c.ARCAN_EID);
        } else {
            lua_pushaid(ctx, c.arcan_audio_sample_buffer(buf, n, n_ch, rate, fmt));
        }

        return 1;
    }

    // file path
    const rname = c.luaL_checklstring(ctx, 1, null);
    const res_path = findresource(
        rname,
        c.DEFAULT_USERMASK,
        c.ARES_FILE | c.ARES_RDONLY,
        null,
    );
    const gval: f32 = @floatCast(luaL_optnumber_alt(ctx, 2, 1.0));
    const sid = c.arcan_audio_load_sample(res_path, gval, null);
    c.arcan_mem_free(@ptrCast(res_path));
    lua_pushaid(ctx, sid);

    return 1;
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part4.zig
// ══════════════════════════════════════════════════════════════════════

// === Section 5: Image Properties/Text/Shader + Section 6: System/Lifecycle ===
//
// Ported from arcan_lua.c lines 1933-3324 (sections 5+6).
// LUA_TRACE/LUA_ETRACE removed per porting rules.



// Type aliases

// External symbols

inline fn SHADER_INDEX(rv: c_int) u16 {
    return @as(u16, @truncate(@as(u32, @bitCast(rv)) & 0xffff));
}

// ============================================================================
// Section 5: Image Properties, Text, Shader, Cursor
// ============================================================================

// 1. buildshader (C:1933)
fn buildshader(ctx: ?*c.lua_State) callconv(.c) c_int {
    const vprog = c.luaL_optlstring(ctx, 1, null, null);
    const fprog = c.luaL_optlstring(ctx, 2, null, null);
    const label = c.luaL_checklstring(ctx, 3, null);

    const rv = c.agp_shader_build(label, null, vprog, fprog);
    c.lua_pushnumber(ctx, @as(f64, @floatFromInt(SHADER_INDEX(@as(c_int, @bitCast(rv))))));
    return 1;
}

// 2. deleteshader (C:1962)
fn deleteshader(ctx: ?*c.lua_State) callconv(.c) c_int {
    const sid: c_int = @intFromFloat(@abs(c.luaL_checknumber(ctx, 1)));
    c.lua_pushboolean(ctx, @intFromBool(c.agp_shader_destroy(@bitCast(sid))));
    return 1;
}

// 3. sharestorage (C:1970)
fn sharestorage(ctx: ?*c.lua_State) callconv(.c) c_int {
    const src = luaL_checkvid(ctx, 1, null);
    const dst = luaL_checkvid(ctx, 2, null);

    const rv = c.arcan_video_shareglstore(src, dst);
    c.lua_pushboolean(ctx, @intFromBool(rv == c.ARCAN_OK));
    return 1;
}

// 4. matchstorage (C:1983)
fn matchstorage(ctx: ?*c.lua_State) callconv(.c) c_int {
    var v1: [*c]c.arcan_vobject = undefined;
    var v2: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 1, &v1);
    _ = luaL_checkvid(ctx, 2, &v2);
    c.lua_pushboolean(ctx, @intFromBool(v1.*.vstore == v2.*.vstore));
    return 1;
}

// 5. cursorstorage (C:1995)
fn cursorstorage(ctx: ?*c.lua_State) callconv(.c) c_int {
    const src = luaL_checkvid(ctx, 1, null);

    if (c.lua_type(ctx, 2) == c.LUA_TTABLE) {
        if (c.lua_objlen(ctx, -1) != 8) {
            c.arcan_warning(@as([*c]const u8, "cursor_setstorage(), too few elements in txco tables(expected 8, got %i)\n"), @as(c_int, @intCast(c.lua_objlen(ctx, -1))));
            return 0;
        }

        var i: usize = 0;
        while (i < 8) : (i += 1) {
            _ = c.lua_rawgeti(ctx, -1, @as(c_int, @intCast(i + 1)));
            c.arcan_video_display.cursor_txcos[i] = @floatCast(c.lua_tonumber(ctx, -1));
            c.lua_settop(ctx, -1 - 1);
        }
    }

    c.arcan_video_cursorstore(src);
    return 0;
}

// 6. cursormove (C:2018)
fn cursormove(ctx: ?*c.lua_State) callconv(.c) c_int {
    var x: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1));
    var y: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));
    const clamp = luaL_optbnumber(ctx, 3, false);

    const mmode = c.platform_video_dimensions();

    if (clamp) {
        x = if (x > @as(c_int, @intCast(mmode.width))) @as(c_int, @intCast(mmode.width)) else x;
        y = if (y > @as(c_int, @intCast(mmode.height))) @as(c_int, @intCast(mmode.height)) else y;
        x = if (x < 0) 0 else x;
        y = if (y < 0) 0 else y;
    }

    c.arcan_video_cursorpos(x, y, true);
    return 0;
}

// 7. cursornudge (C:2038)
fn cursornudge(ctx: ?*c.lua_State) callconv(.c) c_int {
    var x: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1) + @as(f64, @floatFromInt(c.arcan_video_display.cursor.x)));
    var y: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2) + @as(f64, @floatFromInt(c.arcan_video_display.cursor.y)));
    const clamp = luaL_optbnumber(ctx, 3, false);

    const mmode = c.platform_video_dimensions();

    if (clamp) {
        x = if (x > @as(c_int, @intCast(mmode.width))) @as(c_int, @intCast(mmode.width)) else x;
        y = if (y > @as(c_int, @intCast(mmode.height))) @as(c_int, @intCast(mmode.height)) else y;
        x = if (x < 0) 0 else x;
        y = if (y < 0) 0 else y;
    }

    c.arcan_video_cursorpos(x, y, true);
    return 0;
}

// 8. cursorposition (C:2059)
fn cursorposition(ctx: ?*c.lua_State) callconv(.c) c_int {
    c.lua_pushnumber(ctx, @as(f64, @floatFromInt(c.arcan_video_display.cursor.x)));
    c.lua_pushnumber(ctx, @as(f64, @floatFromInt(c.arcan_video_display.cursor.y)));
    return 2;
}

// 9. cursorsize (C:2067)
fn cursorsize(ctx: ?*c.lua_State) callconv(.c) c_int {
    const w: usize = @intFromFloat(c.luaL_checknumber(ctx, 1));
    const h: usize = @intFromFloat(c.luaL_checknumber(ctx, 2));
    c.arcan_video_cursorsize(w, h);
    return 0;
}

// 10. imagestate (C:2076)
fn imagestate(ctx: ?*c.lua_State) callconv(.c) c_int {
    const vid = luaL_checkvid(ctx, 1, null);

    const state = c.arcan_video_feedstate(vid);
    if (state == null) {
        c.lua_pushstring(ctx, "static");
    } else {
        switch (state.*.tag) {
            c.ARCAN_TAG_FRAMESERV => c.lua_pushstring(ctx, "frameserver"),
            c.ARCAN_TAG_3DOBJ => c.lua_pushstring(ctx, "3d object"),
            c.ARCAN_TAG_ASYNCIMGLD, c.ARCAN_TAG_ASYNCIMGRD => c.lua_pushstring(ctx, "asynchronous state"),
            c.ARCAN_TAG_3DCAMERA => c.lua_pushstring(ctx, "3d camera"),
            else => c.lua_pushstring(ctx, "unknown"),
        }
    }
    return 1;
}

// 11. tagtransform (C:2110)
fn tagtransform(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    var mask: c_uint = @intFromFloat(c.luaL_checknumber(ctx, 2));

    const MASK_TRANSFORMS: c_uint = c.MASK_POSITION | c.MASK_SCALE | c.MASK_OPACITY | c.MASK_ORIENTATION;
    if ((mask & ~MASK_TRANSFORMS) != 0) {
        c.arcan_warning(@as([*c]const u8, "tag_image_transform(), unknown mask- bits filtered.\n"));
        mask &= MASK_TRANSFORMS;
    }

    const ref = find_lua_callback(ctx);
    _ = c.arcan_video_tagtransform(id, ref, mask);
    return 0;
}

// 12. setshader (C:2129)
fn setshader(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const id = luaL_checkvid(ctx, 1, &vobj);
    const oldshid = vobj.*.program;

    if (c.lua_gettop(ctx) == 1) {
        c.lua_pushnumber(ctx, @as(f64, @floatFromInt(oldshid)));
        return 1;
    }

    // identifier can be a number or shared name
    const shid: c.agp_shader_id = if (c.lua_type(ctx, 2) == c.LUA_TSTRING)
        c.agp_shader_lookup(c.luaL_checklstring(ctx, 2, null))
    else
        @intFromFloat(c.luaL_checknumber(ctx, 2));

    if (!c.agp_shader_valid(shid)) {
        c.lua_pushnumber(ctx, @as(f64, @floatFromInt(oldshid)));
        return 1;
    }

    if (c.lua_type(ctx, 3) != c.LUA_TNUMBER) {
        c.lua_pushnumber(ctx, @as(f64, @floatFromInt(oldshid)));
        _ = c.arcan_video_setprogram(id, shid);
        return 1;
    }

    // long form: modify rendertarget shader state
    const num = luaL_checkint(ctx, 3);
    const rtgt = c.arcan_vint_findrt(vobj);

    if (rtgt == null)
        c.arcan_fatal(@as([*c]const u8, "image_shader() -- vid does not refer to a rendertarget\n"));

    rtgt.*.force_shid = false;
    c.lua_pushnumber(ctx, @as(f64, @floatFromInt(rtgt.*.shid)));

    if (num == 1) {
        rtgt.*.shid = shid;
    } else if (num == 2) {
        rtgt.*.force_shid = true;
        rtgt.*.shid = shid;
    } else {
        return 1;
    }

    return 1;
}

// 13. setmeshshader (C:2187)
fn setmeshshader(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const shid: c.agp_shader_id = if (c.lua_type(ctx, 2) == c.LUA_TSTRING)
        c.agp_shader_lookup(c.luaL_checklstring(ctx, 2, null))
    else
        @intFromFloat(c.luaL_checknumber(ctx, 2));

    const slot: c_uint = @intCast(@abs(@as(c_int, @intFromFloat(c.luaL_checknumber(ctx, 3)))));
    _ = c.arcan_3d_meshshader(id, shid, slot);
    return 0;
}

// 14. textdimensions (C:2202) — manually ported (translate-c failed due to goto + VLA)
fn textdimensions(ctx: ?*c.lua_State) callconv(.c) c_int {
    var width: usize = 0;
    var height: usize = 0;
    var maxw: usize = 0;
    var maxh: usize = 0;
    var sz: u32 = undefined;

    const ltype = c.lua_type(ctx, 1);

    if (ltype == c.LUA_TSTRING) {
        const message = c.luaL_checklstring(ctx, 1, null);
        _ = c.arcan_renderfun_renderfmtstr(
            message,
            c.ARCAN_EID,
            false,
            null,
            null,
            &width,
            &height,
            &sz,
            &maxw,
            &maxh,
            true,
        );
    } else if (ltype == c.LUA_TTABLE) {
        const nelems: c_int = @intCast(c.lua_objlen(ctx, 1));

        if (nelems == 0) {
            // goto out equivalent
            c.lua_pushnumber(ctx, @floatFromInt(width));
            c.lua_pushnumber(ctx, @floatFromInt(height));
            return 2;
        }

        // Allocate message array
        const alloc_sz = @sizeOf([*c]u8) * @as(usize, @intCast(nelems + 1));
        const messages: [*c][*c]u8 = @ptrCast(@alignCast(c.arcan_alloc_mem(
            alloc_sz,
            c.ARCAN_MEM_VSTRUCT,
            0,
            c.ARCAN_MEMALIGN_NATURAL,
        )));

        var i: usize = 0;
        while (i < @as(usize, @intCast(nelems))) : (i += 1) {
            _ = c.lua_rawgeti(ctx, 1, @as(c_int, @intCast(i + 1)));
            messages[i] = c.strdup(c.luaL_checklstring(ctx, -1, null));
            c.lua_settop(ctx, -1 - 1);
        }
        messages[@as(usize, @intCast(nelems))] = null;

        // renderfmtstr_extended will free() the messages
        _ = c.arcan_renderfun_renderfmtstr_extended(
            @ptrCast(messages),
            c.ARCAN_EID,
            false,
            null,
            null,
            &width,
            &height,
            &sz,
            &maxw,
            &maxh,
            true,
        );
    } else {
        c.arcan_fatal(@as([*c]const u8, "text_dimensions(), invalid type for argument 1, accepted string or table\n"));
    }

    c.lua_pushnumber(ctx, @floatFromInt(width));
    c.lua_pushnumber(ctx, @floatFromInt(height));
    return 2;
}

// 15. apply_tuiattr_table (C:2251) — helper, not a Lua binding
fn apply_tuiattr_table(
    L: ?*c.lua_State,
    ind: c_int,
    attr: [*c]c.struct_tui_screen_attr,
) void {
    attr.*.unnamed_2.aflags = 0;
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_BOLD) * @as(c_uint, @intFromBool(intblbool(L, ind, "bold")))));
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_UNDERLINE) * @as(c_uint, @intFromBool(intblbool(L, ind, "underline")))));
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_ITALIC) * @as(c_uint, @intFromBool(intblbool(L, ind, "italic")))));
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_INVERSE) * @as(c_uint, @intFromBool(intblbool(L, ind, "inverse")))));
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_UNDERLINE) * @as(c_uint, @intFromBool(intblbool(L, ind, "underline")))));
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_UNDERLINE_ALT) * @as(c_uint, @intFromBool(intblbool(L, ind, "underline_alt")))));
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_PROTECT) * @as(c_uint, @intFromBool(intblbool(L, ind, "protect")))));
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_BLINK) * @as(c_uint, @intFromBool(intblbool(L, ind, "blink")))));
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_STRIKETHROUGH) * @as(c_uint, @intFromBool(intblbool(L, ind, "strikethrough")))));
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_SHAPE_BREAK) * @as(c_uint, @intFromBool(intblbool(L, ind, "break")))));
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_BORDER_LEFT) * @as(c_uint, @intFromBool(intblbool(L, ind, "border_left")))));
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_BORDER_RIGHT) * @as(c_uint, @intFromBool(intblbool(L, ind, "border_right")))));
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_BORDER_TOP) * @as(c_uint, @intFromBool(intblbool(L, ind, "border_top")))));
    attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_BORDER_DOWN) * @as(c_uint, @intFromBool(intblbool(L, ind, "border_down")))));

    var ok: bool = undefined;
    attr.*.custom_id = @as(u8, @truncate(@as(c_uint, @bitCast(intblint_checked(L, ind, "id", &ok)))));

    attr.*.unnamed_0.unnamed_0.fr = 0;
    attr.*.unnamed_0.unnamed_0.fg = 0;
    attr.*.unnamed_0.unnamed_0.fb = 0;
    attr.*.unnamed_1.unnamed_0.br = 0;
    attr.*.unnamed_1.unnamed_0.bg = 0;
    attr.*.unnamed_1.unnamed_0.bb = 0;

    const val = intblint_checked(L, ind, "fc", &ok);
    if (val != -1 and ok) {
        attr.*.unnamed_2.aflags |= @as(u16, @truncate(@as(c_uint, c.TUI_ATTR_COLOR_INDEXED)));
        attr.*.unnamed_0.fc[0] = @as(u8, @truncate(@as(c_uint, @bitCast(val))));
        attr.*.unnamed_1.bc[0] = @as(u8, @truncate(@as(c_uint, @bitCast(intblint_checked(L, ind, "bc", &ok)))));
    } else {
        _ = intblint_checked(L, ind, "fr", &ok);
        if (ok) {
            attr.*.unnamed_0.unnamed_0.fr = @as(u8, @truncate(@as(c_uint, @bitCast(intblint_checked(L, ind, "fr", &ok)))));
            attr.*.unnamed_0.unnamed_0.fg = @as(u8, @truncate(@as(c_uint, @bitCast(intblint_checked(L, ind, "fg", &ok)))));
            attr.*.unnamed_0.unnamed_0.fb = @as(u8, @truncate(@as(c_uint, @bitCast(intblint_checked(L, ind, "fb", &ok)))));
        } else {
            attr.*.unnamed_0.unnamed_0.fr = 196;
            attr.*.unnamed_0.unnamed_0.fg = 196;
            attr.*.unnamed_0.unnamed_0.fb = 196;
        }

        _ = intblint_checked(L, ind, "br", &ok);
        if (ok) {
            attr.*.unnamed_1.unnamed_0.br = @as(u8, @truncate(@as(c_uint, @bitCast(intblint_checked(L, ind, "br", &ok)))));
            attr.*.unnamed_1.unnamed_0.bg = @as(u8, @truncate(@as(c_uint, @bitCast(intblint_checked(L, ind, "bg", &ok)))));
            attr.*.unnamed_1.unnamed_0.bb = @as(u8, @truncate(@as(c_uint, @bitCast(intblint_checked(L, ind, "bb", &ok)))));
        }
    }
}

// 16. textsurface (C:2302)
fn textsurface(L: ?*c.lua_State) callconv(.c) c_int {
    const n_rows: usize = @intFromFloat(c.luaL_checknumber(L, 1));
    const n_cols: usize = @intFromFloat(c.luaL_checknumber(L, 2));
    var tblind: c_int = 3;
    var T: ?*c.struct_tui_context = undefined;
    var vid: arcan_vobj_id = undefined;

    if (c.lua_type(L, 3) == c.LUA_TNUMBER) {
        var vobj: [*c]c.arcan_vobject = undefined;
        vid = luaL_checkvid(L, 3, &vobj);

        lua_pushvid(L, vid);
        T = @ptrCast(vobj.*.vstore.*.vinf.text.unnamed_0.tpack.tui);

        if (vobj.*.feed.state.ptr != null) {
            c.arcan_fatal(@as([*c]const u8, "text_surface(r, c, >vid<) is not a pure text_surface"));
        }

        var crows: usize = undefined;
        var ccols: usize = undefined;
        c.arcan_tui_dimensions(T, &crows, &ccols);

        if (crows != n_rows or ccols != n_cols) {
            var cellw: usize = undefined;
            var cellh: usize = undefined;
            c.arcan_renderfun_fontgroup_size(
                @ptrCast(vobj.*.vstore.*.vinf.text.unnamed_0.tpack.group),
                0.0,
                vobj.*.owner.*.hppcm,
                &cellw,
                &cellh,
            );

            c.arcan_tui_wndhint(T, null, c.struct_tui_constraints{
                .anch_row = 0,
                .anch_col = 0,
                .max_rows = @as(c_int, @intCast(n_rows)),
                .max_cols = @as(c_int, @intCast(n_cols)),
                .min_rows = 0,
                .min_cols = 0,
                .hide = 0,
                .embed = 0,
            });

            const w = cellw * n_cols;
            const h = cellh * n_rows;
            _ = c.arcan_video_resizefeed(vid, w, h);
        }
        tblind += 1;
    } else {
        var vobj: [*c]c.arcan_vobject = undefined;

        var pt: c_int = undefined;
        var fd: [4]c.file_handle = .{ BADFD, BADFD, BADFD, BADFD };
        var hint: c_int = undefined;
        c.arcan_video_fontdefaults(&fd[0], &pt, &hint);
        // arcan_video_fontdefaults yields a BORROWED fd; arcan_renderfun_fontgroup
        // takes ownership of every fd it's handed (release path closes them).
        // dup so the cache slot survives this fontgroup's eventual release.
        if (fd[0] != BADFD) fd[0] = c.dup(fd[0]);

        var cellw: usize = undefined;
        var cellh: usize = undefined;
        const group = c.arcan_renderfun_fontgroup(&fd[0], 4);
        vid = c.arcan_video_currentattachment();
        vobj = c.arcan_video_getobject(vid);
        const tgt = c.arcan_vint_findrt(vobj);
        c.arcan_renderfun_fontgroup_size(
            group,
            c.arcan_pt_to_mm(@intCast(pt)),
            tgt.*.hppcm,
            &cellw,
            &cellh,
        );

        vid = c.arcan_video_rawobject(
            null,
            c.img_cons{
                .w = @intCast(cellw * n_cols),
                .h = @intCast(cellh * n_rows),
                .bpp = 4,
            },
            @floatFromInt(cellw * n_cols),
            @floatFromInt(cellh * n_rows),
            0,
        );
        vobj = c.arcan_video_getobject(vid);
        trace_allocation(L, "text_surface", vid);

        T = c.arcan_tui_setup(null, null, &std.mem.zeroes(c.struct_tui_cbcfg), @sizeOf(c.struct_tui_cbcfg));
        _ = c.arcan_tui_set_flags(T, c.TUI_HIDE_CURSOR);
        c.arcan_tui_wndhint(T, null, c.struct_tui_constraints{
            .anch_row = 0,
            .anch_col = 0,
            .max_rows = @as(c_int, @intCast(n_rows)),
            .max_cols = @as(c_int, @intCast(n_cols)),
            .min_rows = 0,
            .min_cols = 0,
            .hide = 0,
            .embed = 0,
        });

        vobj.*.vstore.*.vinf.text.unnamed_0.tpack.group = @ptrCast(group);
        vobj.*.vstore.*.vinf.text.unnamed_0.tpack.tui = @ptrCast(T);
        vobj.*.vstore.*.vinf.text.kind = @bitCast(@as(c_int, c.STORAGE_TPACK));

        lua_pushvid(L, vid);
    }

    if (c.lua_type(L, tblind) != c.LUA_TTABLE) {
        c.arcan_fatal(@as([*c]const u8, "text_surface(r, c, [vid], >table< argument expected"));
    }

    c.arcan_tui_move_to(T, 0, 0);
    const nval: usize = c.lua_objlen(L, tblind);
    var cy: usize = 0;

    // sweep each row
    var i: usize = 0;
    while (i < nval) : (i += 1) {
        _ = c.lua_rawgeti(L, tblind, @as(c_int, @intCast(i + 1)));
        if (c.lua_type(L, -1) != c.LUA_TTABLE)
            c.arcan_fatal(@as([*c]const u8, "text_surface(>table<) expected row table on index\n"));

        var ok: bool = undefined;
        const y = intblint_checked(L, -1, "y", &ok);
        if (ok and y >= 0) {
            cy = @intCast(y);
        }

        var x = intblint_checked(L, -1, "x", &ok);
        if (!ok) {
            x = 0;
            c.arcan_tui_erase_region(T, 0, cy, n_cols, cy, false);
        }

        const ncells: usize = c.lua_objlen(L, -1);
        c.arcan_tui_move_to(T, @intCast(x), cy);

        var cattr = c.arcan_tui_defattr(T, null);

        var rowind: usize = 0;
        while (rowind < ncells) : (rowind += 1) {
            _ = c.lua_rawgeti(L, -1, @as(c_int, @intCast(rowind + 1)));
            if (c.lua_type(L, -1) == c.LUA_TSTRING) {
                const str = c.lua_tolstring(L, -1, null);
                _ = c.arcan_tui_writeu8(T, @ptrCast(str), c.strlen(str), &cattr);
            } else if (c.lua_type(L, -1) == c.LUA_TTABLE) {
                apply_tuiattr_table(L, -1, &cattr);
            } else {
                c.arcan_fatal(@as([*c]const u8, "text_surface(>table<) unexpected type in row\n"));
            }
            c.lua_settop(L, -1 - 1);
        }

        cy += 1;
        c.lua_settop(L, -1 - 1);
    }

    c.arcan_video_tuisynch(vid);
    return 1;
}

// 17. rendertext (C:2458)
fn rendertext(ctx: ?*c.lua_State) callconv(.c) c_int {
    var id: arcan_vobj_id = c.ARCAN_EID;
    var argpos: c_int = 1;

    var ltype = c.lua_type(ctx, 1);
    if (ltype == c.LUA_TNUMBER) {
        id = luaL_checkvid(ctx, 1, null);
        argpos += 1;
    }

    ltype = c.lua_type(ctx, argpos);
    var nlines: c_uint = 0;
    var lineheights: [*c]c.struct_renderline_meta = null;
    var errc: c.arcan_errc = undefined;

    // old non-escaped string form
    if (ltype == c.LUA_TSTRING) {
        const message = c.strdup(c.luaL_checklstring(ctx, argpos, null));
        trace_allocation(ctx, "render_text", id);
        id = c.arcan_video_renderstring(id, c.struct_arcan_rstrarg{
            .multiple = false,
            .unnamed_0 = .{ .message = message },
        }, &nlines, &lineheights, &errc);
    } else if (ltype == c.LUA_TTABLE) {
        // table form: % 2 == 0 = format, % 2 == 1 = regular
        const nelems: c_int = @intCast(c.lua_objlen(ctx, argpos));
        if (nelems == 0) {
            c.arcan_warning(@as([*c]const u8, "render_text(), passed empty table"));
            return 0;
        }

        const messages: [*c][*c]u8 = @ptrCast(@alignCast(c.arcan_alloc_mem(
            @sizeOf([*c]u8) * @as(usize, @intCast(nelems + 1)),
            c.ARCAN_MEM_VSTRUCT,
            0,
            c.ARCAN_MEMALIGN_NATURAL,
        )));

        var i: usize = 0;
        while (i < @as(usize, @intCast(nelems))) : (i += 1) {
            _ = c.lua_rawgeti(ctx, argpos, @as(c_int, @intCast(i + 1)));
            messages[i] = c.strdup(c.luaL_checklstring(ctx, -1, null));
            c.lua_settop(ctx, -1 - 1);
        }
        messages[@as(usize, @intCast(nelems))] = null;

        id = c.arcan_video_renderstring(id, c.struct_arcan_rstrarg{
            .multiple = true,
            .unnamed_0 = .{ .array = messages },
        }, &nlines, &lineheights, &errc);
    } else {
        c.arcan_fatal(@as([*c]const u8, "render_text(), expected string or table\n"));
    }

    lua_pushvid(ctx, id);
    c.lua_createtable(ctx, @bitCast(nlines), 0);
    var asc: c_int = 0;
    var height: c_int = 0;
    const top = c.lua_gettop(ctx);

    var li: usize = 0;
    while (li < @as(usize, nlines)) : (li += 1) {
        c.lua_pushnumber(ctx, @floatFromInt(li + 1));
        c.lua_pushnumber(ctx, @floatFromInt(lineheights[li].ystart));
        if (asc == 0 and lineheights[li].ascent != 0) {
            asc = lineheights[li].ascent;
            height = lineheights[li].height;
        }
        c.lua_rawset(ctx, top);
    }

    if (lineheights != null) {
        c.arcan_mem_free(@ptrCast(lineheights));
    }

    const vobj = c.arcan_video_getobject(id);
    if (vobj != null) {
        c.lua_pushnumber(ctx, @floatFromInt(vobj.*.origw));
        c.lua_pushnumber(ctx, @floatFromInt(height));
        c.lua_pushnumber(ctx, @floatFromInt(asc));
        return 5;
    }

    return 2;
}

// 18. scaletxcos (C:2541)
fn scaletxcos(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const txs: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    const txt: f32 = @floatCast(c.luaL_checknumber(ctx, 3));
    _ = c.arcan_video_scaletxcos(id, txs, txt);
    return 0;
}

// 19. settxcos_default (C:2554)
fn settxcos_default(ctx: ?*c.lua_State) callconv(.c) c_int {
    var dst: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 1, &dst);
    const mirror = luaL_optbnumber(ctx, 2, false);

    if (dst.*.txcos == null) {
        dst.*.txcos = @ptrCast(@alignCast(c.arcan_alloc_mem(
            @sizeOf(f32) * 8,
            c.ARCAN_MEM_VSTRUCT,
            c.ARCAN_MEM_NONFATAL,
            c.ARCAN_MEMALIGN_SIMD,
        )));
    }

    if (dst.*.txcos != null) {
        if (mirror) {
            c.arcan_vint_mirrormapping(dst.*.txcos, 1.0, 1.0);
        } else {
            c.arcan_vint_defaultmapping(dst.*.txcos, 1.0, 1.0);
        }
    }
    return 0;
}

// 20. settxcos (C:2576)
fn settxcos(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    var txcos: [8]f32 = undefined;

    if (c.arcan_video_retrieve_mapping(id, &txcos) == c.ARCAN_OK) {
        c.luaL_checktype(ctx, 2, c.LUA_TTABLE);
        const ncords: c_int = @intCast(c.lua_objlen(ctx, -1));
        if (ncords < 8) {
            c.arcan_warning(@as([*c]const u8, "image_set_txcos(), Too few elements in txco tables(expected 8, got %i)\n"), ncords);
            return 0;
        }

        var i: usize = 0;
        while (i < 8) : (i += 1) {
            _ = c.lua_rawgeti(ctx, -1, @as(c_int, @intCast(i + 1)));
            txcos[i] = @floatCast(c.lua_tonumber(ctx, -1));
            c.lua_settop(ctx, -1 - 1);
        }

        _ = c.arcan_video_override_mapping(id, &txcos);
    }
    return 0;
}

// 21. gettxcos (C:2603)
fn gettxcos(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    var rv: c_int = 0;
    var txcos = [_]f32{ 0, 0, 0, 0, 0, 0, 0, 0 };

    if (c.arcan_video_retrieve_mapping(id, &txcos) == c.ARCAN_OK) {
        c.lua_createtable(ctx, 8, 0);
        const top = c.lua_gettop(ctx);

        var i: usize = 0;
        while (i < 8) : (i += 1) {
            c.lua_pushnumber(ctx, @floatFromInt(i + 1));
            c.lua_pushnumber(ctx, @as(f64, @floatCast(txcos[i])));
            c.lua_rawset(ctx, top);
        }
        rv = 1;
    }
    return rv;
}

// 22. togglemask (C:2627)
fn togglemask(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const val: c_int = @intFromFloat(@abs(c.luaL_checknumber(ctx, 2)));

    // C: (val & !(MASK_ALL)) == 0  — note: ! on int is logical not, 0 if MASK_ALL != 0
    if ((@as(c_uint, @bitCast(val)) & @as(c_uint, @intFromBool(c.MASK_ALL == 0))) == 0) {
        var mask = c.arcan_video_getmask(id);
        mask ^= @as(c_uint, @bitCast(~val));
        _ = c.arcan_video_transformmask(id, mask);
    }
    return 0;
}

// 23. clearall (C:2643)
fn clearall(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    if (id != 0)
        _ = c.arcan_video_transformmask(id, 0);
    return 0;
}

// 24. maskstr (C:2654) — helper, returns heap-allocated string
fn maskstr(mask: c_uint) [*c]u8 {
    var buf: [72]u8 = [_]u8{0} ** 72;
    var pos: usize = 0;

    const masks = [_]struct { m: c_uint, s: []const u8 }{
        .{ .m = c.MASK_POSITION, .s = "position " },
        .{ .m = c.MASK_SCALE, .s = "scale " },
        .{ .m = c.MASK_OPACITY, .s = "opacity " },
        .{ .m = c.MASK_LIVING, .s = "living " },
        .{ .m = c.MASK_ORIENTATION, .s = "orientation " },
        .{ .m = c.MASK_UNPICKABLE, .s = "unpickable " },
        .{ .m = c.MASK_FRAMESET, .s = "frameset " },
        .{ .m = c.MASK_MAPPING, .s = "mapping " },
    };

    for (masks) |entry| {
        if ((mask & entry.m) > 0) {
            for (entry.s) |ch| {
                if (pos < buf.len - 1) {
                    buf[pos] = ch;
                    pos += 1;
                }
            }
        }
    }
    buf[pos] = 0;
    return c.strdup(&buf);
}

// 25. clearmask (C:2685)
fn clearmask(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const val: c_int = @intFromFloat(@abs(c.luaL_checknumber(ctx, 2)));

    if ((@as(c_uint, @bitCast(val)) & @as(c_uint, @intFromBool(c.MASK_ALL == 0))) == 0) {
        var mask = c.arcan_video_getmask(id);
        mask &= @as(c_uint, @bitCast(~val));
        _ = c.arcan_video_transformmask(id, mask);
    }
    return 0;
}

// 26. setmask (C:2700)
fn setmask(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const val: c_uint = @intFromFloat(c.luaL_checknumber(ctx, 2));

    if ((val & @as(c_uint, @intFromBool(c.MASK_ALL == 0))) == 0) {
        var mask = c.arcan_video_getmask(id);
        mask |= val;
        _ = c.arcan_video_transformmask(id, mask);
        return 0;
    } else {
        c.arcan_warning(@as([*c]const u8, "Script Warning: image_mask_set(),\tbad mask specified (%i)\n"), @as(c_int, @bitCast(val)));
        return 0;
    }
}

// 27. clipon (C:2720)
fn clipon(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const clipm = luaL_optint(ctx, 2, c.ARCAN_CLIP_ON);

    if (clipm != c.ARCAN_CLIP_ON and clipm != c.ARCAN_CLIP_SHALLOW) {
        c.arcan_fatal(@as([*c]const u8, "image_clip_on() - invalid clipping mode (%d)\n"), clipm);
    }
    _ = c.arcan_video_setclip(id, @bitCast(clipm));

    if (c.lua_type(ctx, 3) == c.LUA_TNUMBER) {
        const did = luaL_checkvid(ctx, 3, null);
        _ = c.arcan_video_clipto(id, did);
    }
    return 0;
}

// 28. clipoff (C:2739)
fn clipoff(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    _ = c.arcan_video_setclip(id, @bitCast(@as(c_int, c.ARCAN_CLIP_OFF)));
    return 0;
}

// 29. pick (C:2747)
fn pick(ctx: ?*c.lua_State) callconv(.c) c_int {
    const x = luaL_checkint(ctx, 1);
    const y = luaL_checkint(ctx, 2);
    const reverse = luaL_optbnumber(ctx, 4, false);
    const limit: usize = @intCast(luaL_optint(ctx, 3, 8));
    var res: arcan_vobj_id = @intFromFloat(luaL_optnumber_alt(ctx, 5, @as(f64, @floatFromInt(c.ARCAN_VIDEO_WORLDID))));

    if (res != c.ARCAN_EID and res != c.ARCAN_VIDEO_WORLDID)
        res -= @as(arcan_vobj_id, @intCast(lua_vid_base));

    var pickbuf: [64]arcan_vobj_id = std.mem.zeroes([64]arcan_vobj_id);
    if (limit > 64)
        c.arcan_fatal(@as([*c]const u8, "pick_items(), unreasonable pick buffer size requested."));

    var count: usize = if (reverse)
        c.arcan_video_rpick(res, &pickbuf, limit, x, y)
    else
        c.arcan_video_pick(res, &pickbuf, limit, x, y);

    var ofs: usize = 1;
    c.lua_createtable(ctx, @intCast(count), 0);
    const top = c.lua_gettop(ctx);

    while (count > 0) : (count -= 1) {
        c.lua_pushnumber(ctx, @floatFromInt(ofs));
        lua_pushvid(ctx, pickbuf[ofs - 1]);
        c.lua_rawset(ctx, top);
        ofs += 1;
    }
    return 1;
}

// 30. hittest (C:2793)
fn hittest(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const x = luaL_checkint(ctx, 2);
    const y = luaL_checkint(ctx, 3);

    c.lua_pushboolean(ctx, @intFromBool(c.arcan_video_hittest(id, x, y)));
    return 1;
}

// 31. deleteimage (C:2806)
fn deleteimage(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const srcid = c.luaL_checknumber(ctx, 1);

    // In LWA mode, disabling WORLDID is not allowed (it's the shmif output)
    if (id == c.ARCAN_VIDEO_WORLDID and !c.platform_is_lwa_mode()) {
        c.arcan_video_disable_worldid();
        return 0;
    }

    const rv = c.arcan_video_deleteobject(id);
    if (rv != c.ARCAN_OK)
        c.arcan_fatal(@as([*c]const u8, "Tried to delete non-existing object (%.0lf=>%lld)"), srcid, @as(c_longlong, id));

    return 0;
}

// 32. setlife (C:2830)
fn setlife(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    var ttl = luaL_checkint(ctx, 2);

    if (ttl <= 0)
        ttl = 1;

    _ = c.arcan_video_setlife(id, @bitCast(ttl));
    return 0;
}

// ============================================================================
// Section 6: System/Lifecycle
// ============================================================================

// 1. systemcontextsize (C:2849)
fn systemcontextsize(ctx: ?*c.lua_State) callconv(.c) c_int {
    const newlim: c_uint = @intCast(luaL_checkint(ctx, 1));

    if (newlim > 1 and newlim <= c.VITEM_CONTEXT_LIMIT)
        _ = c.arcan_video_contextsize(newlim)
    else
        c.arcan_fatal(@as([*c]const u8, "system_context_size(), invalid context size specified (%d)\n"), @as(c_int, @bitCast(newlim)));

    return 0;
}

// 2. subsys_reset (C:2860)
fn subsys_reset(ctx: ?*c.lua_State) callconv(.c) c_int {
    const subsys = c.luaL_checklstring(ctx, 1, null);
    if (c.strcmp(subsys, "video") == 0) {
        const card: c_int = @intFromFloat(luaL_optnumber_alt(ctx, 2, -1.0));
        const swap: c_int = @intFromBool(luaL_optbnumber(ctx, 3, false));
        c.platform_video_reset(card, swap);
    } else {
        c.arcan_fatal(@as([*c]const u8, "unaccepted subsystem (%s), acceptable: video\n"), subsys);
    }
    return 0;
}

// 3. syscollapse (C:2878)
fn syscollapse(ctx: ?*c.lua_State) callconv(.c) c_int {
    var switch_appl: [*c]const u8 = c.luaL_optlstring(ctx, 1, null, null);

    if (switch_appl != null) {
        if (c.strlen(switch_appl) == 0)
            c.arcan_fatal(@as([*c]const u8, "system_collapse(), 0-length appl name not permitted.\n"));

        // validate: only alnum and '_'
        var work: [*c]const u8 = switch_appl;
        while (work[0] != 0) : (work += 1) {
            if (c.isalnum(@as(c_int, work[0])) == 0 and work[0] != '_')
                c.arcan_fatal(@as([*c]const u8, "system_collapse(), only aZ_ are permitted in names.\n"));
        }

        // lua will free when we destroy the context
        switch_appl = c.strdup(switch_appl);
        var errmsg: [*c]const u8 = undefined;

        if (!c.arcan_verifyload_appl(switch_appl, &errmsg)) {
            if (lua_debug_level != 0)
                _ = c.arcan_verify_namespaces(true);

            // Use real arcan_fatal (not alt_fatal) since we no longer have a context
            c.arcan_fatal(@as([*c]const u8, "system_collapse(), failed to load appl (%s), reason: %s\n"), switch_appl, errmsg);
        }
    }

    const ExternLocal = struct {
        extern var arcanmain_recover_state: c.jmp_buf;
    };

    c.longjmp(
        @ptrCast(@alignCast(&ExternLocal.arcanmain_recover_state)),
        if (luaL_optbnumber(ctx, 2, false))
            c.ARCAN_LUA_SWITCH_APPL_NOADOPT
        else
            c.ARCAN_LUA_SWITCH_APPL,
    );

    return 0;
}

// 4. syssnap (C:2915)
fn syssnap(ctx: ?*c.lua_State) callconv(.c) c_int {
    const instr = c.luaL_checklstring(ctx, 1, null);
    var fname: [*c]u8 = findresource(instr, c.RESOURCE_APPL_TEMP, c.O_WRONLY, null);
    var debugif: bool = false;

    if (c.lua_type(ctx, 2) == c.LUA_TBOOLEAN) {
        debugif = c.lua_toboolean(ctx, 2) != 0;
    }

    if (fname != null) {
        c.arcan_warning(@as([*c]const u8, "system_statesnap(), refuses to overwrite existing file (%s));\n"), fname);
        c.arcan_mem_free(@ptrCast(fname));
        c.lua_pushboolean(ctx, 0);
        c.lua_pushstring(ctx, "file exists");
        return 2;
    }

    fname = c.arcan_expand_resource(c.luaL_checklstring(ctx, 1, null), c.RESOURCE_APPL_TEMP);

    if (debugif and fname != null) {
        c.arcan_monitor_watchdog_listen(ctx, fname);
        c.lua_pushboolean(ctx, 1);
        return 1;
    }

    const outf: ?*c.FILE = if (fname != null) c.fopen(fname, "w+") else null;
    if (outf != null) {
        c.arcan_lua_statesnap(outf, "", false);
        _ = c.fclose(outf);
        c.lua_pushboolean(ctx, 1);
        return 1;
    } else {
        c.arcan_warning(@as([*c]const u8, "system_statesnap(), couldn't open (%s) for writing.\n"), instr);
        c.lua_pushboolean(ctx, 0);
        c.lua_pushstring(ctx, "couldn't create");
        return 2;
    }
}

// 5. targetsuspend (C:2960)
fn targetsuspend(ctx: ?*c.lua_State) callconv(.c) c_int {
    const vid = luaL_checkvid(ctx, 1, null);
    const rsusp = luaL_optbnumber(ctx, 2, false);

    const state = c.arcan_video_feedstate(vid);

    if (state == null or state.*.tag != c.ARCAN_TAG_FRAMESERV or state.*.ptr == null) {
        c.arcan_warning(@as([*c]const u8, "suspend_target(), referenced object is not connected to a frameserver.\n"));
        return 0;
    }

    const fsrv: ?*c.arcan_frameserver = @ptrCast(@alignCast(state.*.ptr));

    if (fsrv.?.*.flags.activated == 0) {
        fsrv.?.*.flags.activated = 2;
        return 0;
    }

    var ev = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @truncate(@as(c_uint, c.EVENT_TARGET));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @bitCast(@as(c_int, c.TARGET_COMMAND_PAUSE));

    if (!rsusp)
        _ = c.arcan_frameserver_pause(fsrv);

    _ = c.platform_fsrv_pushevent(fsrv, &ev);
    return 0;
}

// 6. targetresume (C:2996)
fn targetresume(ctx: ?*c.lua_State) callconv(.c) c_int {
    const vid = luaL_checkvid(ctx, 1, null);
    const rsusp = luaL_optbnumber(ctx, 2, false);

    const state = c.arcan_video_feedstate(vid);
    const fsrv: ?*c.arcan_frameserver = @ptrCast(@alignCast(state.*.ptr));

    if (state == null or state.*.tag != c.ARCAN_TAG_FRAMESERV or fsrv == null) {
        c.arcan_fatal(@as([*c]const u8, "suspend_target(), referenced object not connected to a frameserver.\n"));
    }

    var ev = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @truncate(@as(c_uint, c.EVENT_TARGET));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @bitCast(@as(c_int, c.TARGET_COMMAND_UNPAUSE));

    if (fsrv.?.*.flags.activated == 2) {
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @bitCast(@as(c_int, c.TARGET_COMMAND_ACTIVATE));
        fsrv.?.*.flags.activated = 1;
    } else if (!rsusp) {
        _ = c.arcan_frameserver_resume(fsrv);
    }

    _ = c.platform_fsrv_pushevent(fsrv, &ev);
    return 0;
}

// 7. systemload (C:2962) — manually ported (translate-c failed due to VLA + goto)
fn systemload(ctx: ?*c.lua_State) callconv(.c) c_int {
    const instr = c.luaL_checklstring(ctx, 1, null);
    const dieonfail = luaL_optbnumber(ctx, 2, true);

    const ext = c.strrchr(instr, '.');
    if (ext == null) {
        if (dieonfail)
            c.arcan_fatal(@as([*c]const u8, "system_load(), extension missing."))
        else
            c.arcan_warning(@as([*c]const u8, "system_load(), extension missing."));
        return 0;
    }

    const islua = c.strcmp(ext, ".lua") == 0;

    if (!islua and c.strcmp(ext, ".so") != 0) {
        if (dieonfail)
            c.arcan_fatal(@as([*c]const u8, "system_load(), unsupported extension: %s\n"), ext)
        else
            c.arcan_warning(@as([*c]const u8, "system_load(), unsupported extension: %s\n"), ext);
        return 0;
    }

    // native module loading (.so)
    if (!islua) {
        // strip the extension by writing NUL at the dot
        const ext_mut: [*c]u8 = @constCast(ext);
        ext_mut[0] = 0;

        // build workbuf: instr + ".so"
        const instr_len = c.strlen(instr);
        const ext_str = ".so";
        const ext_len = ext_str.len;
        const buflen = instr_len + ext_len + 1;

        var workbuf: [512]u8 = undefined;
        if (buflen > workbuf.len) {
            if (dieonfail)
                c.arcan_fatal(@as([*c]const u8, "system_load(), path too long\n"));
            return 0;
        }
        _ = c.snprintf(&workbuf, workbuf.len, "%s%s", instr, @as([*c]const u8, ".so"));

        const fname_mod = findresource(
            &workbuf,
            c.MODULE_USERMASK,
            c.ARES_FILE | c.ARES_RDONLY,
            null,
        );
        if (fname_mod == null) {
            if (dieonfail)
                c.arcan_fatal(@as([*c]const u8, "Couldn't find required module: (%s)\n"), instr)
            else
                c.arcan_warning(@as([*c]const u8, "Couldn't find required module: (%s)\n"), instr);
            return 0;
        }

        const dlh = c.dlopen(fname_mod, c.RTLD_NOW);
        if (dlh == null) {
            c.arcan_mem_free(@ptrCast(fname_mod));
            if (dieonfail)
                c.arcan_fatal(@as([*c]const u8, "Couldn't open module, error: (%s)\n"), c.dlerror())
            else
                c.arcan_warning(@as([*c]const u8, "Couldn't open module, error: (%s)\n"), c.dlerror());
            return 0;
        }
        c.arcan_mem_free(@ptrCast(fname_mod));

        const initfn: c.module_init_prototype = @ptrCast(@alignCast(c.dlsym(dlh, "arcan_module_init")));
        if (initfn == null) {
            if (dieonfail)
                c.arcan_fatal(@as([*c]const u8, "Couldn't load module (%s), missing arcan_module_init symbol"), instr)
            else
                c.arcan_warning(@as([*c]const u8, "Couldn't load module (%s), missing arcan_module_init symbol"), instr);
            _ = c.dlclose(dlh);
            return 0;
        }

        const resfuns_init = initfn.?(c.LUAAPI_VERSION_MAJOR, c.LUAAPI_VERSION_MINOR, c.LUA_VERSION_NUM);
        if (resfuns_init == null) {
            if (dieonfail)
                c.arcan_fatal(@as([*c]const u8, "Module initialization (%s) failed\n"), instr)
            else
                c.arcan_warning(@as([*c]const u8, "Module initialization (%s) failed\n"), instr);
            return 0;
        }

        c.lua_newtable(ctx);
        const top = c.lua_gettop(ctx);

        var resfuns_ptr = resfuns_init;
        while (resfuns_ptr.*.name != null) : (resfuns_ptr += 1) {
            c.lua_pushstring(ctx, resfuns_ptr.*.name);
            c.lua_pushcfunction(ctx, resfuns_ptr.*.func);
            c.lua_rawset(ctx, top);
        }
        return 1;
    }

    // Lua script loading
    var fd: c_int = -1;
    const fname = findresource(instr, c.CAREFUL_USERMASK, c.ARES_RDONLY | c.ARES_FILE, &fd);
    var res: c_int = 0;

    if (fname != null) {
        if (fd != -1)
            _ = c.close(fd);

        const rv = c.alt_loadfile(ctx, fname);
        if (rv == 0) {
            res = 1;
        } else if (dieonfail) {
            c.arcan_fatal(
                @as([*c]const u8, "Error parsing lua script (%s): %s\n"),
                instr,
                if (rv == 2) @as([*c]const u8, "bytecode forbidden") else c.lua_tolstring(ctx, -1, null),
            );
        }
    } else if (dieonfail) {
        c.arcan_fatal(@as([*c]const u8, "Invalid script specified for system_load(%s)\n"), instr);
    } else {
        c.arcan_warning(@as([*c]const u8, "Invalid script specified for system_load(%s)\n"), instr);
    }

    c.arcan_mem_free(@ptrCast(fname));
    return res;
}

// 8. launchdecode (C:3251) — manually ported (translate-c failed due to goto)
fn launchdecode(ctx: ?*c.lua_State) callconv(.c) c_int {
    var fname: [*c]u8 = null;
    var args = std.mem.zeroes(c.struct_frameserver_envp);
    args.use_builtin = true;
    args.args.builtin.mode = "decode";

    if (fsrv_ok == 0) {
        return 0;
    }

    const ref = find_lua_callback(ctx);

    // nil first argument is permitted (for proto=... options)
    if (c.lua_type(ctx, 1) == c.LUA_TNIL) {
        args.args.builtin.resource = c.luaL_checklstring(ctx, 2, null);
    } else {
        const res_str = c.luaL_checklstring(ctx, 1, null);
        var optarg: [*c]const u8 = "";
        if (c.lua_type(ctx, 2) == c.LUA_TSTRING) {
            optarg = c.lua_tolstring(ctx, 2, null);
        }

        if (is_special_res(res_str)) {
            fname = c.strdup(res_str);
        } else {
            fname = findresource(
                res_str,
                c.DEFAULT_USERMASK,
                c.ARES_FILE | c.ARES_RDONLY,
                null,
            );
            if (fname == null) {
                return 0;
            }

            // legacy: swap : to \t
            _ = colon_escape(fname);

            // prepend option string
            const flen = c.strlen(fname);
            const optlen = c.strlen(optarg);
            const maxlen = flen + optlen + 6 + 1;
            const ol: [*c]u8 = @ptrCast(@alignCast(c.arcan_alloc_mem(
                maxlen,
                c.ARCAN_MEM_STRINGBUF,
                0,
                c.ARCAN_MEMALIGN_NATURAL,
            )));
            _ = c.snprintf(
                ol,
                maxlen,
                "%s%sfile=%s",
                optarg,
                if (optlen > 0) @as([*c]const u8, ":") else @as([*c]const u8, ""),
                fname,
            );
            c.arcan_mem_free(@ptrCast(fname));
            fname = ol;
        }
        args.args.builtin.resource = fname;
    }

    // finish:
    const mvctx = c.platform_launch_fork(&args, @bitCast(ref));
    var vid: arcan_vobj_id = c.ARCAN_EID;
    var aid: arcan_aobj_id = c.ARCAN_EID;

    if (mvctx != null) {
        _ = c.arcan_video_objectopacity(mvctx.?.*.vid, 0.0, 0);
        vid = mvctx.?.*.vid;
        aid = mvctx.?.*.aid;
        trace_allocation(ctx, "launch_decode", mvctx.?.*.vid);
    }

    lua_pushvid(ctx, vid);
    lua_pushaid(ctx, aid);
    c.arcan_mem_free(@ptrCast(fname));
    return 2;
}

// 9. launchavfeed (C:3313)
fn launchavfeed(ctx: ?*c.lua_State) callconv(.c) c_int {
    // early out if fsrv support is disabled
    if (fsrv_ok == 0) {
        return 0;
    }

    const argstr = c.luaL_optlstring(ctx, 1, "", null);
    var modearg: [*c]const u8 = "avfeed";
    if (argstr != null)
        modearg = c.luaL_optlstring(ctx, 2, modearg, null);

    const modestr = c.arcan_frameserver_atypes();

    // expand namespaces in the argument string
    var expbuf = [2][*c]u8{ c.strdup(argstr), null };
    _ = c.arcan_expand_namespaces(&expbuf);

    // only permit build-time defined modes
    if (c.strstr(modestr, modearg) == null) {
        c.arcan_warning(@as([*c]const u8, "launch_avfeed(), requested mode (%s) missing from detected and allowed frameserver archetypes (%s), rejected.\n"), modearg, modestr);
        c.free(@ptrCast(expbuf[0]));
        lua_pushvid(ctx, c.ARCAN_EID);
        lua_pushaid(ctx, c.ARCAN_EID);
        return 2;
    }

    const ref = find_lua_callback(ctx);

    var args = std.mem.zeroes(c.struct_frameserver_envp);
    args.use_builtin = true;
    args.args.builtin.mode = modearg;
    args.args.builtin.resource = expbuf[0];

    if (c.strcmp(modearg, "terminal") == 0)
        args.preserve_env = true;

    const mvctx = c.platform_launch_fork(&args, @bitCast(ref));
    c.arcan_random(@ptrCast(&mvctx.?.*.guid), 16);
    c.free(@ptrCast(expbuf[1]));

    if (mvctx == null) {
        lua_pushvid(ctx, c.ARCAN_EID);
        lua_pushaid(ctx, c.ARCAN_EID);
        return 2;
    }

    trace_allocation(ctx, "launch_avfeed", mvctx.?.*.vid);
    _ = c.arcan_video_objectopacity(mvctx.?.*.vid, 0.0, 0);
    lua_pushvid(ctx, mvctx.?.*.vid);
    lua_pushaid(ctx, mvctx.?.*.aid);

    // push base64-encoded guid
    var dsz: usize = undefined;
    const b64: [*c]u8 = @ptrCast(@alignCast(c.arcan_base64_encode(
        @ptrCast(&mvctx.?.*.guid[0]),
        16,
        &dsz,
        0,
    )));
    c.lua_pushstring(ctx, b64);
    c.arcan_mem_free(@ptrCast(b64));

    c.lua_pushnumber(ctx, @floatFromInt(mvctx.?.*.cookie));
    return 4;
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part5a.zig
// ══════════════════════════════════════════════════════════════════════

// Zig port of engine/arcan_lua.c lines 3326-3625 — VR, LEDs, context management,
// UTF-8 helper, and LWA message.
//
// Ported from C using zig translate-c as reference, with manual cleanup.
// LUA_TRACE/LUA_ETRACE removed per porting rules.
//
// This file does NOT include the @cImport block or type aliases — those come
// from arcan_lua_header.zig and will be in scope when assembled.

// vr_setup (C:3326-3347)
pub fn vr_setup(ctx: ?*lua_State) callconv(.c) c_int {
    var opts: [*c]const u8 = null;

    if (c.lua_type(ctx, 1) == c.LUA_TSTRING) {
        opts = c.luaL_checklstring(ctx, 1, null);
    }

    const ref = find_lua_callback(ctx);
    if (ref == @as(isize, @intCast(c.LUA_NOREF))) {
        c.arcan_fatal("vr_setup(), no event callback handler provided\n");
    }

    c.lua_pushboolean(ctx, @intFromBool(
        c.arcan_vr_setup(opts, c.arcan_event_defaultctx(), @as(usize, @bitCast(ref))) != null,
    ));

    return 1;
}

// vr_maplimb (C:3349-3367)
pub fn vr_maplimb(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 1, &vobj);
    if (vobj == null or vobj.*.feed.state.tag != c.ARCAN_TAG_VR)
        return 0;

    const vid = luaL_checkvid(ctx, 2, null);

    const limb: c_uint = @intFromFloat(c.luaL_checknumber(ctx, 3));

    const pos = luaL_optbnumber(ctx, 4, true);
    const orient = luaL_optbnumber(ctx, 5, true);

    _ = c.arcan_vr_maplimb(
        @as(?*c.arcan_vr_ctx, @ptrCast(vobj.*.feed.state.ptr)),
        limb,
        vid,
        pos,
        orient,
    );

    return 0;
}

// vr_getmeta (C:3369-3439)
pub fn vr_getmeta(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 1, &vobj);
    if (vobj == null or vobj.*.feed.state.tag != c.ARCAN_TAG_VR)
        return 0;

    var md: c.vr_meta = undefined;
    if (c.ARCAN_OK != c.arcan_vr_displaydata(
        @as(?*c.arcan_vr_ctx, @ptrCast(vobj.*.feed.state.ptr)),
        &md,
    ))
        return 0;

    c.lua_createtable(ctx, 0, 0);
    const top = c.lua_gettop(ctx);
    set_tblnum(ctx, "width", @floatFromInt(md.hres), top);
    set_tblnum(ctx, "height", @floatFromInt(md.vres), top);
    set_tblnum(ctx, "center", @as(f64, @floatCast(md.h_center)), top);
    set_tblnum(ctx, "horizontal", @as(f64, @floatCast(md.h_size)), top);
    set_tblnum(ctx, "vertical", @as(f64, @floatCast(md.v_size)), top);
    set_tblnum(ctx, "left_fov", @as(f64, @floatCast(md.left_fov)), top);
    set_tblnum(ctx, "right_fov", @as(f64, @floatCast(md.right_fov)), top);
    set_tblnum(ctx, "left_ar", @as(f64, @floatCast(md.left_ar)), top);
    set_tblnum(ctx, "right_ar", @as(f64, @floatCast(md.right_ar)), top);
    set_tblnum(ctx, "hsep", @as(f64, @floatCast(md.hsep)), top);
    set_tblnum(ctx, "vpos", @as(f64, @floatCast(md.vpos)), top);
    set_tblnum(ctx, "lens_distance", @as(f64, @floatCast(md.lens_distance)), top);
    set_tblnum(ctx, "eye_display", @as(f64, @floatCast(md.eye_display)), top);
    set_tblnum(ctx, "ipd", @as(f64, @floatCast(md.ipd)), top);

    // distortion array
    c.lua_pushlstring(ctx, "distortion", "distortion".len);
    c.lua_createtable(ctx, 0, 4);
    var ttop = c.lua_gettop(ctx);
    for (0..4) |i| {
        c.lua_pushnumber(ctx, @floatFromInt(i + 1));
        c.lua_pushnumber(ctx, @as(f64, @floatCast(md.distortion[i])));
        c.lua_rawset(ctx, ttop);
    }
    c.lua_rawset(ctx, top);

    // abberation array
    c.lua_pushlstring(ctx, "abberation", "abberation".len);
    c.lua_createtable(ctx, 0, 4);
    ttop = c.lua_gettop(ctx);
    for (0..4) |i| {
        c.lua_pushnumber(ctx, @floatFromInt(i + 1));
        c.lua_pushnumber(ctx, @as(f64, @floatCast(md.abberation[i])));
        c.lua_rawset(ctx, ttop);
    }
    c.lua_rawset(ctx, top);

    // projection_left array
    c.lua_pushlstring(ctx, "projection_left", "projection_left".len);
    c.lua_createtable(ctx, 0, 16);
    ttop = c.lua_gettop(ctx);
    for (0..16) |i| {
        c.lua_pushnumber(ctx, @floatFromInt(i + 1));
        c.lua_pushnumber(ctx, @as(f64, @floatCast(md.projection_left[i])));
        c.lua_rawset(ctx, ttop);
    }
    c.lua_rawset(ctx, top);

    // projection_right array
    c.lua_pushlstring(ctx, "projection_right", "projection_right".len);
    c.lua_createtable(ctx, 0, 16);
    ttop = c.lua_gettop(ctx);
    for (0..16) |i| {
        c.lua_pushnumber(ctx, @floatFromInt(i + 1));
        c.lua_pushnumber(ctx, @as(f64, @floatCast(md.projection_right[i])));
        c.lua_rawset(ctx, ttop);
    }
    c.lua_rawset(ctx, top);

    return 1;
}

// n_leds (C:3441-3460)
pub fn n_leds(ctx: ?*lua_State) callconv(.c) c_int {
    const id = luaL_optint(ctx, 1, -1);
    if (id == -1) {
        const ccont = c.arcan_led_controllers();
        c.lua_pushnumber(ctx, @log2(@as(f64, @floatFromInt(ccont))));
        c.lua_pushnumber(ctx, @as(f64, @floatFromInt(ccont & 0x00000000ffffffff)));
        c.lua_pushnumber(ctx, @as(f64, @floatFromInt((ccont & 0xffffffff00000000) >> 32)));
        return 1;
    }

    const cap = c.arcan_led_capabilities(@as(u8, @bitCast(@as(i8, @truncate(id)))));

    c.lua_pushnumber(ctx, @as(f64, @floatFromInt(cap.nleds)));
    c.lua_pushboolean(ctx, @intFromBool(cap.variable_brightness));
    c.lua_pushboolean(ctx, @intFromBool(cap.rgb));
    return 3;
}

// led_intensity (C:3462-3474)
pub fn led_intensity(ctx: ?*lua_State) callconv(.c) c_int {
    const id: u8 = @as(u8, @bitCast(@as(i8, @truncate(luaL_checkint(ctx, 1)))));
    const led: i16 = @as(i16, @bitCast(@as(c_short, @truncate(luaL_checkint(ctx, 2)))));
    const intensity: u8 = @as(u8, @bitCast(@as(i8, @truncate(luaL_checkint(ctx, 3)))));

    c.lua_pushnumber(ctx, @as(f64, @floatFromInt(c.arcan_led_intensity(id, led, intensity))));
    return 1;
}

// led_rgb (C:3476-3489)
pub fn led_rgb(ctx: ?*lua_State) callconv(.c) c_int {
    const id: u8 = @as(u8, @bitCast(@as(i8, @truncate(luaL_checkint(ctx, 1)))));
    const led: i16 = @as(i16, @bitCast(@as(c_short, @truncate(luaL_checkint(ctx, 2)))));
    const r: u8 = @as(u8, @bitCast(@as(i8, @truncate(luaL_checkint(ctx, 3)))));
    const g: u8 = @as(u8, @bitCast(@as(i8, @truncate(luaL_checkint(ctx, 4)))));
    const b: u8 = @as(u8, @bitCast(@as(i8, @truncate(luaL_checkint(ctx, 5)))));
    const buf = luaL_optbnumber(ctx, 6, false);

    c.lua_pushnumber(ctx, @as(f64, @floatFromInt(c.arcan_led_rgb(id, led, r, g, b, buf))));
    return 1;
}

// setled (C:3491-3506)
pub fn setled(ctx: ?*lua_State) callconv(.c) c_int {
    const id = luaL_checkint(ctx, 1);
    const num = luaL_checkint(ctx, 2);
    const state: c_int = if (luaL_optbnumber(ctx, 3, true)) 255 else 0;

    c.lua_pushnumber(ctx, @as(f64, @floatFromInt(c.arcan_led_intensity(
        @as(u8, @bitCast(@as(i8, @truncate(id)))),
        @as(i16, @bitCast(@as(c_short, @truncate(num)))),
        @as(u8, @bitCast(@as(i8, @truncate(state)))),
    ))));
    return 1;
}

// pushcontext (C:3508-3519)
pub fn pushcontext(ctx: ?*lua_State) callconv(.c) c_int {
    if (c.arcan_video_nfreecontexts() > 1)
        c.lua_pushinteger(ctx, @as(c.lua_Integer, @intCast(c.arcan_video_pushcontext())))
    else
        c.lua_pushinteger(ctx, -1);

    return 1;
}

// popcontext_ext (C:3521-3531)
pub fn popcontext_ext(ctx: ?*lua_State) callconv(.c) c_int {
    var newid: arcan_vobj_id = c.ARCAN_EID;

    if (c.arcan_video_nfreecontexts() > 1) {
        c.lua_pushinteger(ctx, @as(c.lua_Integer, @intCast(c.arcan_video_extpopcontext(&newid))));
    } else {
        c.lua_pushinteger(ctx, -1);
    }
    lua_pushvid(ctx, newid);

    return 2;
}

// pushcontext_ext (C:3533-3543)
pub fn pushcontext_ext(ctx: ?*lua_State) callconv(.c) c_int {
    var newid: arcan_vobj_id = c.ARCAN_EID;

    if (c.arcan_video_nfreecontexts() > 1) {
        c.lua_pushinteger(ctx, @as(c.lua_Integer, @intCast(c.arcan_video_extpushcontext(&newid))));
    } else {
        c.lua_pushinteger(ctx, -1);
    }
    lua_pushvid(ctx, newid);

    return 2;
}

// popcontext (C:3545-3550)
pub fn popcontext(ctx: ?*lua_State) callconv(.c) c_int {
    c.lua_pushinteger(ctx, @as(c.lua_Integer, @intCast(c.arcan_video_popcontext())));
    return 1;
}

// contextusage (C:3552-3561)
pub fn contextusage(ctx: ?*lua_State) callconv(.c) c_int {
    var usecount: c_uint = undefined;
    c.lua_pushinteger(ctx, @as(c.lua_Integer, @intCast(c.arcan_video_contextusage(&usecount))));
    c.lua_pushinteger(ctx, @as(c.lua_Integer, @intCast(usecount)));
    return 2;
}

// lwamessage (C:3575-3625)
// Only used under ARCAN_LWA. Sends a UTF-8 message to an LWA subsegment,
// splitting at UTF-8 codepoint boundaries when the message exceeds the
// event message buffer size.
pub fn lwamessage(
    ctx: ?*lua_State,
    in_len: usize,
    msg: [*c]const u8,
    sseg: ?*c.subseg_output,
) c_int {
    _ = ctx;

    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_MESSAGE;

    var state: u32 = 0;
    var codepoint: u32 = 0;
    var outs = msg;
    var len = in_len;
    const maxlen = @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data)) - 1;

    // split at UTF-8 codepoint boundaries when message exceeds buffer
    while (len > maxlen) {
        var lastok: usize = 0;
        state = 0;
        var i: usize = 0;
        while (i <= maxlen - 1) : (i += 1) {
            if (UTF8_ACCEPT == utf8_decode(&state, &codepoint, @as(u32, outs[i])))
                lastok = i;

            if (i != lastok) {
                if (0 == i)
                    return 0;
            }
        }

        const copy_len = lastok + 1;
        @memcpy(
            ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data[0..copy_len],
            outs[0..copy_len],
        );
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data[copy_len] = 0;
        len -= copy_len;
        outs += copy_len;

        if (len != 0)
            ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.multipart = 1
        else
            ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.multipart = 0;

        _ = c.platform_lwa_targetevent(sseg, &ev);
    }

    // flush remaining
    if (len != 0) {
        _ = c.snprintf(
            @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data)),
            maxlen,
            "%s",
            outs,
        );
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.multipart = 0;
        _ = c.platform_lwa_targetevent(sseg, &ev);
    }
    return 0;
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part5b.zig
// ══════════════════════════════════════════════════════════════════════

// Port of arcan_lua.c lines 3626-3924
// Functions: targetmessage, targetinput, lookup_idatatype_str




// targetmessage (C:3626-3734)
// Forwards a message string to a frameserver, splitting into multipart
// chunks along utf8 codepoint boundaries when the message exceeds the
// event message buffer size.
pub fn targetmessage(ctx: ?*lua_State) callconv(.c) c_int {
    var vidind: c_int = undefined;
    var tblind: c_int = undefined;

    // same ordering issue as target_input — accept (vid, str) or (str, vid)
    if (c.lua_type(ctx, 1) == c.LUA_TNUMBER) {
        vidind = 1;
        tblind = 2;
    } else {
        tblind = 1;
        vidind = 2;
    }

    const vid = luaL_checkvid(ctx, vidind, null);
    const vstate: [*c]c.vfunc_state = c.arcan_video_feedstate(vid);
    var fsrv: ?*c.arcan_frameserver = null;

    var len: usize = 0;
    var msg: [*c]const u8 = c.luaL_checklstring(ctx, tblind, &len);

    // LWA path: use EVENT_EXTERNAL direction for parent/subsegment
    if (vid == c.ARCAN_VIDEO_WORLDID and c.platform_is_lwa_mode()) {
        return lwamessage(ctx, len, msg, null);
    } else if (vstate != null and vstate.*.tag == c.ARCAN_TAG_LWA) {
        return lwamessage(ctx, len, msg, @ptrCast(@alignCast(vstate.*.ptr)));
    }

    if (vstate != null and vstate.*.tag == c.ARCAN_TAG_FRAMESERV) {
        fsrv = @ptrCast(@alignCast(vstate.*.ptr));
    }

    if (fsrv == null) {
        c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(@as(c_int, -1))));
        return 1;
    }

    // "strlen" + validate the entire message as utf8
    var state: u32 = 0;
    var codepoint: u32 = 0;
    while (msg[len] != 0) {
        if (UTF8_REJECT == utf8_decode(&state, &codepoint, @as(u32, @intCast(msg[len])))) {
            c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(@as(c_int, -1))));
            return 1;
        }
        len += 1;
    }

    if (state != UTF8_ACCEPT) {
        c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(@as(c_int, -1))));
        return 1;
    }

    var ev: arcan_event = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @truncate(@as(c_uint, c.EVENT_TARGET));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @bitCast(@as(c_int, c.TARGET_COMMAND_MESSAGE));

    // message buffer size minus null terminator
    const msgsz: usize = @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)) - 1;

    // pack in multipart '\0' — split on utf8 codepoint boundaries
    while (len > msgsz) {
        var i: usize = 0;
        var lastok: usize = 0;
        state = 0;

        // search for the last complete codepoint offset within msgsz
        while (i < msgsz and i < len) : (i += 1) {
            if (@as(u32, UTF8_ACCEPT) == utf8_decode(&state, &codepoint, @as(u32, @intCast(msg[i])))) {
                lastok = i;
            }
        }

        // rewind if we split on the wrong point
        if (i != lastok) {
            i = lastok;
        }

        // copy into buffer and forward
        const copy_len: usize = lastok + 1;
        const dst_msg: [*c]u8 = @ptrCast(@alignCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message));
        @memcpy(dst_msg[0..copy_len], msg[0..copy_len]);
        dst_msg[copy_len] = 0;

        len -= copy_len;
        msg += copy_len;

        // mark multipart
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = if (len != 0) @as(i32, 1) else @as(i32, 0);

        if (c.ARCAN_OK != c.platform_fsrv_pushevent(fsrv, &ev)) {
            c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(len + copy_len)));
            return 1;
        }
    }

    // spill or message fits from the start
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = 0;
    if (len != 0) {
        const dst_msg: [*c]u8 = @ptrCast(@alignCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message));
        @memcpy(dst_msg[0..len], msg[0..len]);
        dst_msg[len] = 0;
        if (c.ARCAN_OK != c.platform_fsrv_pushevent(fsrv, &ev)) {
            c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(len)));
            return 1;
        }
    }

    c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(@as(c_int, 0))));
    return 1;
}

// targetinput (C:3740-3903)
// Sends an input event to a frameserver. Accepts (vid, iotbl) or (iotbl, vid).
// If the second argument is a string, delegates to targetmessage.
// Reads a Lua table with fields: kind, digital, translated, active, devid,
// subid, analog, touch, eyes, etc. and constructs an arcan_event.
pub fn targetinput(ctx: ?*lua_State) callconv(.c) c_int {
    var vidind: c_int = undefined;
    var tblind: c_int = undefined;

    // swizzle if necessary
    if (c.lua_type(ctx, 1) == c.LUA_TNUMBER) {
        vidind = 1;
        tblind = 2;
    } else {
        tblind = 1;
        vidind = 2;
    }

    if (c.lua_type(ctx, tblind) == c.LUA_TSTRING)
        return targetmessage(ctx);

    const vid = luaL_checkvid(ctx, vidind, null);
    const vstate: [*c]c.vfunc_state = c.arcan_video_feedstate(vid);
    if (vstate == null or vstate.*.tag != c.ARCAN_TAG_FRAMESERV) {
        c.lua_pushnumber(ctx, @as(lua_Number, 0));
        return 1;
    }

    const fsrv: ?*c.arcan_frameserver = @ptrCast(@alignCast(vstate.*.ptr));

    c.luaL_checktype(ctx, tblind, c.LUA_TTABLE);
    var ev: arcan_event = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @truncate(@as(c_uint, c.EVENT_IO));
    const io = &ev.unnamed_0.unnamed_0.unnamed_0.io;

    // NOTE: no validation that label matches earlier labelhints or gestures
    io.flags = @as(u8, @truncate((@as(u32, @intFromBool(intblbool(ctx, tblind, "gesture"))) *% 0xff) & @as(u32, c.ARCAN_IOFL_GESTURE)));

    const label = intblstr(ctx, tblind, "label");
    if (label != null) {
        var ul: c_int = @as(c_int, @intCast(@sizeOf(@TypeOf(io.label)))) - 1;
        var lbl_ptr = label;
        var dst_idx: usize = 0;
        while (lbl_ptr[0] != 0 and ul > 0) {
            io.label[dst_idx] = lbl_ptr[0];
            dst_idx += 1;
            lbl_ptr += 1;
            ul -= 1;
        }
        io.label[dst_idx] = 0;
    }
    io.pts = @as(u64, @bitCast(@as(i64, intblint(ctx, tblind, "pts"))));
    io.unnamed_0.unnamed_0.devid = @as(u16, @bitCast(@as(i16, @truncate(intblint(ctx, tblind, "devid")))));
    io.unnamed_0.unnamed_0.subid = @as(u16, @bitCast(@as(i16, @truncate(intblint(ctx, tblind, "subid")))));

    // Check boolean flags first, then fall back to string "kind" field.
    // The approach: grab universal fields, check boolean shortcuts, then
    // scan for kind string and FALLBACK to string-compare.
    const mouse = intblbool(ctx, tblind, "mouse");
    if (mouse)
        io.devkind = @bitCast(@as(c_int, c.EVENT_IDEVKIND_MOUSE));

    // Use a labeled block to emulate the goto-based dispatch in C
    const result = dispatch: {
        if (intblbool(ctx, tblind, "analog"))
            break :dispatch fillAnalog(ctx, tblind, io);

        if (intblbool(ctx, tblind, "touch"))
            break :dispatch fillTouch(ctx, tblind, io);

        if (intblbool(ctx, tblind, "digital"))
            break :dispatch fillDigital(ctx, tblind, io);

        if (intblbool(ctx, tblind, "eyes"))
            break :dispatch fillEyes(ctx, tblind, io);

        const kindlbl = intblstr(ctx, tblind, "kind");
        if (kindlbl == null) {
            // kinderr
            c.arcan_warning("Script Warning: target_input(), unknown \"kind\" field in table.\n");
            c.lua_pushnumber(ctx, @as(lua_Number, 0));
            return 1;
        }

        if (c.strcmp(kindlbl, "analog") == 0) {
            break :dispatch fillAnalog(ctx, tblind, io);
        } else if (c.strcmp(kindlbl, "touch") == 0) {
            break :dispatch fillTouch(ctx, tblind, io);
        } else if (c.strcmp(kindlbl, "eyes") == 0) {
            break :dispatch fillEyes(ctx, tblind, io);
        } else if (c.strcmp(kindlbl, "digital") == 0) {
            break :dispatch fillDigital(ctx, tblind, io);
        } else {
            // kinderr
            c.arcan_warning("Script Warning: target_input(), unknown \"kind\" field in table.\n");
            c.lua_pushnumber(ctx, @as(lua_Number, 0));
            return 1;
        }
    };

    if (!result) {
        // analog path returned early with warning (no samples table)
        return 1;
    }

    c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(@intFromBool(c.ARCAN_OK == c.platform_fsrv_pushevent(fsrv, &ev)))));
    return 1;
}

// Fill analog input fields on the io event. Returns false if samples table missing.
fn fillAnalog(ctx: ?*lua_State, tblind: c_int, io: *c.arcan_ioevent) bool {
    io.kind = @bitCast(@as(c_int, c.EVENT_IO_AXIS_MOVE));
    if (io.devkind != @as(@TypeOf(io.devkind), @bitCast(@as(c_int, c.EVENT_IDEVKIND_MOUSE))))
        io.devkind = @bitCast(@as(c_int, c.EVENT_IDEVKIND_GAMEDEV));
    io.input.analog.gotrel = @intFromBool(intblbool(ctx, tblind, "relative"));
    io.datatype = @bitCast(@as(c_int, c.EVENT_IDATATYPE_ANALOG));
    io.input.analog.active = @intFromBool(!intblbool(ctx, tblind, "leave"));
    _ = intblbool(ctx, tblind, "leave"); // second read matches C code

    // sweep the samples subtable
    _ = c.lua_getfield(ctx, tblind, "samples");
    if (c.lua_type(ctx, -1) != c.LUA_TTABLE) {
        c.arcan_warning("target_input(), no samples provided for target input\n");
        c.lua_pushnumber(ctx, @as(lua_Number, 0));
        return false;
    }

    const naxiss: usize = c.lua_objlen(ctx, -1);
    const max_axisval = @sizeOf(@TypeOf(io.input.analog.axisval)) / @sizeOf(i16);
    var i: usize = 0;
    while (i < naxiss and i < max_axisval) : (i += 1) {
        _ = c.lua_rawgeti(ctx, -1, @as(c_int, @intCast(i + 1)));
        // Read as a number and truncate, NOT lua_tointeger: Lua 5.4's
        // lua_tointeger returns 0 for a float without an exact integer
        // representation, and mouse sample coordinates from
        // convert_mouse_xy are fractional. The C original relied on
        // Lua 5.1 lua_tointeger semantics (plain double truncation);
        // replicate that. Without this, every axisval lands 0 and any
        // LWA/frameserver client's cursor pins to the top-left corner.
        const sv: f64 = c.lua_tonumber(ctx, -1);
        io.input.analog.axisval[i] = @as(i16, @truncate(@as(i64, @intFromFloat(@trunc(sv)))));
        c.lua_settop(ctx, -(1) - 1); // lua_pop(ctx, 1)
    }
    io.input.analog.nvalues = @as(u8, @truncate(naxiss));

    return true;
}

// Fill touch input fields on the io event.
fn fillTouch(ctx: ?*lua_State, tblind: c_int, io: *c.arcan_ioevent) bool {
    io.kind = @bitCast(@as(c_int, c.EVENT_IO_TOUCH));
    io.devkind = @bitCast(@as(c_int, c.EVENT_IDEVKIND_TOUCHDISP));
    io.datatype = @bitCast(@as(c_int, c.EVENT_IDATATYPE_TOUCH));
    io.input.touch.active = @as(u8, @truncate(@as(c_uint, @bitCast(intblint(ctx, tblind, "active")))));
    io.input.touch.x = @as(i16, @truncate(intblint(ctx, tblind, "x")));
    io.input.touch.y = @as(i16, @truncate(intblint(ctx, tblind, "y")));
    io.input.touch.pressure = intblfloat(ctx, tblind, "pressure");
    io.input.touch.size = intblfloat(ctx, tblind, "size");
    return true;
}

// Fill eyes input fields on the io event.
fn fillEyes(ctx: ?*lua_State, tblind: c_int, io: *c.arcan_ioevent) bool {
    io.kind = @bitCast(@as(c_int, c.EVENT_IO_EYES));
    io.devkind = @bitCast(@as(c_int, c.EVENT_IDEVKIND_EYETRACKER));
    io.datatype = @bitCast(@as(c_int, c.EVENT_IDATATYPE_EYES));
    io.input.eyes.head_pos[0] = intblfloat(ctx, tblind, "head_x");
    io.input.eyes.head_pos[1] = intblfloat(ctx, tblind, "head_y");
    io.input.eyes.head_pos[2] = intblfloat(ctx, tblind, "head_z");
    io.input.eyes.head_ang[0] = intblfloat(ctx, tblind, "head_rx");
    io.input.eyes.head_ang[1] = intblfloat(ctx, tblind, "head_ry");
    io.input.eyes.head_ang[2] = intblfloat(ctx, tblind, "head_rz");
    io.input.eyes.present = @intFromBool(intblbool(ctx, tblind, "present"));
    io.input.eyes.gaze_x1 = intblfloat(ctx, tblind, "x1");
    io.input.eyes.gaze_y1 = intblfloat(ctx, tblind, "y1");
    io.input.eyes.gaze_x2 = intblfloat(ctx, tblind, "x2");
    io.input.eyes.gaze_y2 = intblfloat(ctx, tblind, "y2");
    io.input.eyes.blink_left = @intFromBool(intblbool(ctx, tblind, "blink_left"));
    io.input.eyes.blink_right = @intFromBool(intblbool(ctx, tblind, "blink_right"));
    return true;
}

// Fill digital input fields on the io event (translated or raw).
fn fillDigital(ctx: ?*lua_State, tblind: c_int, io: *c.arcan_ioevent) bool {
    if (intblbool(ctx, tblind, "translated")) {
        io.kind = @bitCast(@as(c_int, c.EVENT_IO_BUTTON));
        io.devkind = @bitCast(@as(c_int, c.EVENT_IDEVKIND_KEYBOARD));
        io.datatype = @bitCast(@as(c_int, c.EVENT_IDATATYPE_TRANSLATED));
        io.input.translated.active = @intFromBool(intblbool(ctx, tblind, "active"));
        io.input.translated.scancode = @as(u8, @truncate(@as(c_uint, @bitCast(intblint(ctx, tblind, "number")))));
        io.input.translated.keysym = @as(u32, @bitCast(intblint(ctx, tblind, "keysym")));
        io.input.translated.modifiers = @as(u16, @bitCast(@as(i16, @truncate(intblint(ctx, tblind, "modifiers")))));
        get_utf8(intblstr(ctx, tblind, "utf8"), @as([*c]u8, @ptrCast(&io.input.translated.utf8)));
    } else {
        if (io.devkind != @as(@TypeOf(io.devkind), @bitCast(@as(c_int, c.EVENT_IDEVKIND_MOUSE))))
            io.devkind = @bitCast(@as(c_int, c.EVENT_IDEVKIND_GAMEDEV));
        io.datatype = @bitCast(@as(c_int, c.EVENT_IDATATYPE_DIGITAL));
        io.kind = @bitCast(@as(c_int, c.EVENT_IO_BUTTON));
        io.input.digital.active = @intFromBool(intblbool(ctx, tblind, "active"));
        // TRACE_MARK_ONESHOT omitted (uses __FILE__ which is untranslatable)
    }
    return true;
}

// lookup_idatatype_str (C:3905-3923)
// Maps a string datatype name to its EVENT_IDATATYPE_* constant.
pub fn lookup_idatatype_str(str: [*c]const u8) callconv(.c) isize {
    if (c.strcmp(str, "analog") == 0)
        return @as(isize, c.EVENT_IDATATYPE_ANALOG);

    if (c.strcmp(str, "digital") == 0)
        return @as(isize, c.EVENT_IDATATYPE_DIGITAL);

    if (c.strcmp(str, "translated") == 0)
        return @as(isize, c.EVENT_IDATATYPE_TRANSLATED);

    if (c.strcmp(str, "touch") == 0)
        return @as(isize, c.EVENT_IDATATYPE_TOUCH);

    if (c.strcmp(str, "eyes") == 0)
        return @as(isize, c.EVENT_IDATATYPE_EYES);

    return -1;
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part5c.zig
// ══════════════════════════════════════════════════════════════════════

// Zig port of engine/arcan_lua.c lines 3925-4531 -- display event handlers,
// input table builder, segment request, VR limb names, and preroll.
//
// Ported from C using zig translate-c as reference, with manual cleanup.



// -- Type aliases --

// -- External state --

// -- Aliases matching C macros tblstr/tblnum/tblbool/tbldynstr --
const tblstr = set_tblstr;
const tbldynstr = set_tbldynstr;
const tblnum = set_tblnum;
const tblbool = set_tblbool;
extern fn alt_call(ctx: ?*lua_State, kind: c_int, maskv: u64, kind_tag: usize, args: c_int, retc: c_int, src: [*c]const u8) void;
extern fn alt_lookup_entry(ctx: ?*lua_State, fun: [*c]const u8, len: usize) bool;

// -- Module-level state (luactx struct -- shared with other parts) --

// ---------------------------------------------------------------------------
// 1. lookup_idatatype (C:3925-3943)
// ---------------------------------------------------------------------------
fn lookup_idatatype(itype: c_int) ?[*c]const u8 {
    return switch (itype) {
        c.EVENT_IDATATYPE_ANALOG => "analog",
        c.EVENT_IDATATYPE_DIGITAL => "digital",
        c.EVENT_IDATATYPE_TRANSLATED => "translated",
        c.EVENT_IDATATYPE_TOUCH => "touch",
        c.EVENT_IDATATYPE_EYES => "eyes",
        else => null,
    };
}

// ---------------------------------------------------------------------------
// 2. push_displaymodes (C:3951-4015)
// ---------------------------------------------------------------------------
fn push_displaymodes(ctx: ?*lua_State, id: c.platform_display_id) void {
    const dtop = c.lua_gettop(ctx);
    var mcount: usize = 0;
    const modes = c.platform_video_query_modes(id, &mcount);
    if (modes == null)
        return;

    var j: usize = 0;
    while (j < mcount) : (j += 1) {
        c.lua_pushnumber(ctx, @floatFromInt(j + 1));
        c.lua_createtable(ctx, 0, 12);

        const jtop = c.lua_gettop(ctx);

        c.lua_pushlstring(ctx, "cardid", 6);
        c.lua_pushnumber(ctx, 0);
        c.lua_rawset(ctx, jtop);

        c.lua_pushlstring(ctx, "displayid", 9);
        c.lua_pushnumber(ctx, @floatFromInt(id));
        c.lua_rawset(ctx, jtop);

        c.lua_pushlstring(ctx, "phy_width_mm", 12);
        c.lua_pushnumber(ctx, @floatFromInt(modes[j].phy_width));
        c.lua_rawset(ctx, jtop);

        c.lua_pushlstring(ctx, "phy_height_mm", 13);
        c.lua_pushnumber(ctx, @floatFromInt(modes[j].phy_height));
        c.lua_rawset(ctx, jtop);

        c.lua_pushlstring(ctx, "subpixel_layout", 15);
        c.lua_pushstring(ctx, if (modes[j].subpixel != null) modes[j].subpixel else "unknown");
        c.lua_rawset(ctx, jtop);

        c.lua_pushlstring(ctx, "dynamic", 7);
        c.lua_pushboolean(ctx, @intFromBool(modes[j].dynamic));
        c.lua_rawset(ctx, jtop);

        c.lua_pushlstring(ctx, "primary", 7);
        c.lua_pushboolean(ctx, @intFromBool(modes[j].primary));
        c.lua_rawset(ctx, jtop);

        c.lua_pushlstring(ctx, "modeid", 6);
        c.lua_pushnumber(ctx, @floatFromInt(modes[j].id));
        c.lua_rawset(ctx, jtop);

        c.lua_pushlstring(ctx, "width", 5);
        c.lua_pushnumber(ctx, @floatFromInt(modes[j].width));
        c.lua_rawset(ctx, jtop);

        c.lua_pushlstring(ctx, "height", 6);
        c.lua_pushnumber(ctx, @floatFromInt(modes[j].height));
        c.lua_rawset(ctx, jtop);

        c.lua_pushlstring(ctx, "refresh", 7);
        c.lua_pushnumber(ctx, @floatFromInt(modes[j].refresh));
        c.lua_rawset(ctx, jtop);

        c.lua_pushlstring(ctx, "depth", 5);
        c.lua_pushnumber(ctx, @floatFromInt(modes[j].depth));
        c.lua_rawset(ctx, jtop);

        c.lua_rawset(ctx, dtop);
    }
}

// ---------------------------------------------------------------------------
// 3. display_reset (C:4017-4088)
// ---------------------------------------------------------------------------
fn display_reset(ctx: ?*lua_State, ev: [*c]arcan_event) void {
    const vid = &ev.*.unnamed_0.unnamed_0.unnamed_0.vid;

    if (vid.source == -1) {
        // minor protection against bad displays
        if (vid.unnamed_0.unnamed_0.vppcm > 18.0) {
            c.arcan_lua_setglobalnum(ctx, "VPPCM", vid.unnamed_0.unnamed_0.vppcm);
            c.arcan_lua_setglobalnum(ctx, "HPPCM", vid.unnamed_0.unnamed_0.vppcm);
        }

        // call VRES_AUTORES if defined (durian uses this for tiler resize)
        _ = c.lua_getglobal(ctx, "VRES_AUTORES");
        if (c.lua_isfunction(ctx, -1)) {
            c.lua_pushnumber(ctx, @floatFromInt(vid.unnamed_0.unnamed_0.width));
            c.lua_pushnumber(ctx, @floatFromInt(vid.unnamed_0.unnamed_0.height));
            c.lua_pushnumber(ctx, vid.unnamed_0.unnamed_0.vppcm);
            c.lua_pushnumber(ctx, @floatFromInt(vid.unnamed_0.unnamed_0.flags));
            c.lua_pushnumber(ctx, @floatFromInt(vid.unnamed_0.unnamed_0.displayid));
            alt_call(ctx, c.CB_SOURCE_NONE, c.EP_TRIGGER_AUTORES, 0, 5, 0, "display_reset:VRES_AUTORES");
        } else {
            c.lua_settop(ctx, -(1) - 1);
        }

        // always update platform and globals so windowed compositors get correct canvas dims
        if (vid.unnamed_0.unnamed_0.width != 0 and vid.unnamed_0.unnamed_0.height != 0) {
            var mode = std.mem.zeroes(c.struct_monitor_mode);
            mode.width = @intCast(vid.unnamed_0.unnamed_0.width);
            mode.height = @intCast(vid.unnamed_0.unnamed_0.height);
            if (c.platform_video_specify_mode(@intCast(vid.unnamed_0.unnamed_0.displayid), mode)) {
                c.arcan_lua_setglobalnum(ctx, "VRESW", @floatFromInt(mode.width));
                c.arcan_lua_setglobalnum(ctx, "VRESH", @floatFromInt(mode.height));
            }
        }
    } else if (vid.source == -2) {
        // LWA font reset via VRES_AUTOFONT
        _ = c.lua_getglobal(ctx, "VRES_AUTOFONT");
        if (c.lua_isfunction(ctx, -1)) {
            c.lua_pushnumber(ctx, vid.unnamed_0.unnamed_0.vppcm);
            c.lua_pushnumber(ctx, @floatFromInt(vid.unnamed_0.unnamed_0.width));
            c.lua_pushnumber(ctx, @floatFromInt(vid.unnamed_0.unnamed_0.displayid));
            alt_call(ctx, c.CB_SOURCE_NONE, c.EP_TRIGGER_AUTOFONT, 0, 3, 0, "display_reset:VRES_AUTOFONT");
        } else {
            c.lua_settop(ctx, -(1) - 1);
        }
    }

    if (!alt_lookup_entry(ctx, "display_state", "display_state".len))
        return;

    c.lua_pushlstring(ctx, "reset", 5);

    alt_call(ctx, c.CB_SOURCE_NONE, c.EP_TRIGGER_DISPLAYRESET, 0, 1, 0, "display_reset:display_state:reset");
}

// ---------------------------------------------------------------------------
// 4. display_added (C:4090-4112)
// ---------------------------------------------------------------------------
fn display_added(ctx: ?*lua_State, ev: [*c]arcan_event) void {
    if (!alt_lookup_entry(ctx, "display_state", "display_state".len))
        return;

    const vid = &ev.*.unnamed_0.unnamed_0.unnamed_0.vid;

    c.lua_pushlstring(ctx, "added", 5);
    c.lua_pushnumber(ctx, @floatFromInt(vid.unnamed_0.unnamed_0.displayid));

    c.lua_createtable(ctx, 0, 3);
    const top = c.lua_gettop(ctx);
    c.lua_pushlstring(ctx, "ledctrl", 7);
    c.lua_pushnumber(ctx, @floatFromInt(vid.unnamed_0.unnamed_0.ledctrl));
    c.lua_rawset(ctx, top);
    c.lua_pushlstring(ctx, "ledind", 6);
    c.lua_pushnumber(ctx, @floatFromInt(vid.unnamed_0.unnamed_0.ledid));
    c.lua_rawset(ctx, top);
    c.lua_pushlstring(ctx, "card", 4);
    c.lua_pushnumber(ctx, @floatFromInt(vid.unnamed_0.unnamed_0.cardid));
    c.lua_rawset(ctx, top);

    alt_call(ctx, c.CB_SOURCE_NONE, c.EP_TRIGGER_DISPLAYSTATE, 0, 3, 0, "display_added:display_state:added");
}

// ---------------------------------------------------------------------------
// 5. display_changed (C:4114-4122)
// ---------------------------------------------------------------------------
fn display_changed(ctx: ?*lua_State, ev: [*c]arcan_event) void {
    _ = ev;
    if (!alt_lookup_entry(ctx, "display_state", "display_state".len))
        return;

    c.lua_pushlstring(ctx, "changed", 7);
    alt_call(ctx, c.CB_SOURCE_NONE, c.EP_TRIGGER_DISPLAYSTATE, 0, 1, 0, "display_changed:display_state:changed");
}

// ---------------------------------------------------------------------------
// 6. display_removed (C:4124-4133)
// ---------------------------------------------------------------------------
fn display_removed(ctx: ?*lua_State, ev: [*c]arcan_event) void {
    if (!alt_lookup_entry(ctx, "display_state", "display_state".len))
        return;

    const vid = &ev.*.unnamed_0.unnamed_0.unnamed_0.vid;
    c.lua_pushlstring(ctx, "removed", 7);
    c.lua_pushnumber(ctx, @floatFromInt(vid.unnamed_0.unnamed_0.displayid));
    alt_call(ctx, c.CB_SOURCE_NONE, c.EP_TRIGGER_DISPLAYSTATE, 0, 2, 0, "display_removed:display_state:removed");
}

// ---------------------------------------------------------------------------
// 7. do_preroll (C:4135-4166)
// ---------------------------------------------------------------------------
fn do_preroll(ctx: ?*lua_State, ref: isize, vid: arcan_vobj_id, aid: arcan_aobj_id) void {
    {
        const f = c.fopen("/tmp/arcan_preroll_trace.log", "a");
        if (f != null) {
            _ = c.fprintf(f, "do_preroll: ENTRY vid=%lld ref=%lld aid=%lld\n",
                @as(c_longlong, @intCast(vid)), @as(c_longlong, @intCast(ref)),
                @as(c_longlong, @intCast(aid)));
            _ = c.fclose(f);
        }
    }
    const state = c.arcan_video_feedstate(vid);
    if (state == null or state.*.tag != c.ARCAN_TAG_FRAMESERV or state.*.ptr == null) {
        const f = c.fopen("/tmp/arcan_preroll_trace.log", "a");
        if (f != null) {
            _ = c.fprintf(f, "do_preroll: EARLY-RETURN bad feedstate vid=%lld\n",
                @as(c_longlong, @intCast(vid)));
            _ = c.fclose(f);
        }
        return;
    }
    const fsrv: ?*anyopaque = state.*.ptr;

    if (ref != @as(isize, c.LUA_NOREF)) {
        {
            const f = c.fopen("/tmp/arcan_preroll_trace.log", "a");
            if (f != null) {
                _ = c.fprintf(f, "do_preroll: pre alt_call vid=%lld\n", @as(c_longlong, @intCast(vid)));
                _ = c.fclose(f);
            }
        }
        _ = c.lua_rawgeti(ctx, c.LUA_REGISTRYINDEX, @as(c_int, @intCast(ref)));
        lua_pushvid(ctx, vid);
        c.lua_createtable(ctx, 0, 0);
        const top = c.lua_gettop(ctx);
        tblstr(ctx, "kind", "preroll", top);
        tbldynstr(ctx, "segkind", fsrvtos(@bitCast(fsrv_helper_get_segid(fsrv))), top);
        tblnum(ctx, "source_audio", @floatFromInt(aid), top);
        alt_call(ctx, c.CB_SOURCE_PREROLL, c.EP_TRIGGER_FRAMESERVER, @bitCast(vid), 2, 0, "do_preroll:frameserver:preroll");
        {
            const f = c.fopen("/tmp/arcan_preroll_trace.log", "a");
            if (f != null) {
                _ = c.fprintf(f, "do_preroll: post alt_call vid=%lld\n", @as(c_longlong, @intCast(vid)));
                _ = c.fclose(f);
            }
        }
    } else {
        const f = c.fopen("/tmp/arcan_preroll_trace.log", "a");
        if (f != null) {
            _ = c.fprintf(f, "do_preroll: SKIPPING alt_call (LUA_NOREF) vid=%lld\n", @as(c_longlong, @intCast(vid)));
            _ = c.fclose(f);
        }
    }

    // there is the possibility of 'deferred' activation so that the WM
    // can control the sequence in which multiple clients are unlocked
    // BUG-10: check dms before activate — if 0, terminal will die during preroll
    const dms_val = fsrv_helper_page_get_dms(fsrv_helper_get_shmptr(fsrv));
    if (dms_val == 0) {
        c.arcan_warning("BUG-10: dms=0 before ACTIVATE — terminal will die!\n");
    }

    const act = fsrv_helper_get_activated(fsrv);
    {
        const f = c.fopen("/tmp/arcan_preroll_trace.log", "a");
        if (f != null) {
            _ = c.fprintf(f, "do_preroll: vid=%lld act=%d dms=%d segid=%d\n",
                @as(c_longlong, @intCast(vid)), act, dms_val,
                @as(c_int, @intCast(fsrv_helper_get_segid(fsrv))));
            _ = c.fclose(f);
        }
    }
    if (act == 0) {
        fsrv_helper_set_activated(fsrv, 1);
        var ev = arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.category = @as(u8, @truncate(@as(c_uint, c.EVENT_TARGET)));
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @bitCast(@as(c_int, c.TARGET_COMMAND_ACTIVATE));
        const send_rc = tgtevent(vid, ev);
        const f = c.fopen("/tmp/arcan_preroll_trace.log", "a");
        if (f != null) {
            _ = c.fprintf(f, "do_preroll: sent ACTIVATE vid=%lld rc=%d\n",
                @as(c_longlong, @intCast(vid)), send_rc);
            _ = c.fclose(f);
        }
    } else {
        const f = c.fopen("/tmp/arcan_preroll_trace.log", "a");
        if (f != null) {
            _ = c.fprintf(f, "do_preroll: SKIPPED ACTIVATE (already act=%d) vid=%lld\n",
                act, @as(c_longlong, @intCast(vid)));
            _ = c.fclose(f);
        }
    }
}

// ---------------------------------------------------------------------------
// 9. push_view (C:4185-4223)
// ---------------------------------------------------------------------------
fn push_view(ctx: ?*lua_State, ev: [*c]c.arcan_extevent, fsrv: ?*anyopaque, top: c_int) void {
    _ = fsrv;
    const vp = &ev.*.unnamed_0.viewport;

    tblbool(ctx, "invisible", vp.invisible != 0, top);
    tblbool(ctx, "focus", vp.focus != 0, top);
    tblbool(ctx, "anchor_edge", vp.anchor_edge != 0, top);
    tblbool(ctx, "anchor_pos", vp.anchor_pos != 0, top);
    tblbool(ctx, "embedded", vp.embedded != 0, top);
    tblnum(ctx, "rel_order", @floatFromInt(vp.order), top);
    tblnum(ctx, "rel_x", @floatFromInt(vp.x), top);
    tblnum(ctx, "rel_y", @floatFromInt(vp.y), top);
    tblnum(ctx, "anchor_w", @floatFromInt(vp.w), top);
    tblnum(ctx, "anchor_h", @floatFromInt(vp.h), top);
    tblnum(ctx, "edge", @floatFromInt(vp.edge), top);
    tblnum(ctx, "ext_id", @floatFromInt(vp.ext_id), top);
    tblbool(ctx, "scaled", vp.embedded == 2, top);
    tblbool(ctx, "hintfwd", vp.embedded == 3, top);

    c.lua_pushlstring(ctx, "border", 6);
    c.lua_createtable(ctx, 4, 0);
    const top2 = c.lua_gettop(ctx);
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        c.lua_pushnumber(ctx, @floatFromInt(i + 1));
        c.lua_pushnumber(ctx, @floatFromInt(vp.border[i]));
        c.lua_rawset(ctx, top2);
    }
    c.lua_rawset(ctx, top);

    const pid: u32 = vp.parent;
    tblnum(ctx, "parent", @floatFromInt(pid), top);
}

// ---------------------------------------------------------------------------
// 10. emit_segreq (C:4225-4297)
// ---------------------------------------------------------------------------
fn emit_segreq(ctx: ?*lua_State, parent: ?*anyopaque, ev: [*c]c.arcan_extevent) void {
    luactx.last_segreq = @ptrCast(ev);
    const top = c.lua_gettop(ctx);

    // clamp invalid segreq kind
    if (ev.*.unnamed_0.segreq.kind > c.SEGID_DEBUG or
        ev.*.unnamed_0.segreq.kind == 0)
    {
        ev.*.unnamed_0.segreq.kind = c.SEGID_UNKNOWN;
    }

    tblstr(ctx, "kind", "segment_request", top);
    tblnum(ctx, "width", @floatFromInt(ev.*.unnamed_0.segreq.width), top);
    tblnum(ctx, "height", @floatFromInt(ev.*.unnamed_0.segreq.height), top);
    tblnum(ctx, "reqid", @floatFromInt(ev.*.unnamed_0.segreq.id), top);
    tblnum(ctx, "xofs", @floatFromInt(ev.*.unnamed_0.segreq.xofs), top);
    tblnum(ctx, "yofs", @floatFromInt(ev.*.unnamed_0.segreq.yofs), top);

    switch (ev.*.unnamed_0.segreq.dir) {
        1 => tblstr(ctx, "split", "left", top),
        2 => tblstr(ctx, "split", "right", top),
        3 => tblstr(ctx, "split", "top", top),
        4 => tblstr(ctx, "split", "bottom", top),
        5 => tblstr(ctx, "position", "left", top),
        6 => tblstr(ctx, "position", "right", top),
        7 => tblstr(ctx, "position", "top", top),
        8 => tblstr(ctx, "position", "bottom", top),
        9 => tblstr(ctx, "position", "tab", top),
        10 => tblstr(ctx, "position", "embed", top),
        11 => tblstr(ctx, "position", "swallow", top),
        else => {},
    }

    tblnum(ctx, "parent", @floatFromInt(fsrv_helper_get_cookie(parent)), top);
    tbldynstr(ctx, "segkind", fsrvtos(ev.*.unnamed_0.segreq.kind), top);

    alt_call(ctx, c.CB_SOURCE_FRAMESERVER, c.EP_TRIGGER_FRAMESERVER, @bitCast(ev.*.source), 2, 0, "emit_segreq:frameserver:segment_request");

    // call into callback, if we have been consumed, do nothing, otherwise reject
    if (luactx.last_segreq != null) {
        var rev = arcan_event.zeroes();
        rev.unnamed_0.unnamed_0.category = @as(u8, @truncate(@as(c_uint, c.EVENT_TARGET)));
        rev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @bitCast(@as(c_int, c.TARGET_COMMAND_REQFAIL));
        rev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = @bitCast(ev.*.unnamed_0.segreq.id);

        _ = tgtevent(ev.*.source, rev);
    }

    luactx.last_segreq = null;
}

// ---------------------------------------------------------------------------
// 11. limb_name (C:4299-4352)
// ---------------------------------------------------------------------------
fn limb_name(num: c_int) [*c]const u8 {
    return switch (num) {
        c.PERSON => "person",
        c.NECK => "neck",
        c.L_EYE => "eye-left",
        c.R_EYE => "eye-right",
        c.L_SHOULDER => "shoulder-left",
        c.R_SHOULDER => "shoulder-right",
        c.L_ELBOW => "elbow-left",
        c.R_ELBOW => "elbow-right",
        c.L_WRIST => "wrist-left",
        c.R_WRIST => "wrist-right",
        c.L_THUMB_PROXIMAL => "thumb-proximal-left",
        c.L_THUMB_MIDDLE => "thumb-middle-left",
        c.L_THUMB_DISTAL => "thumb-distal-left",
        c.L_POINTER_PROXIMAL => "pointer-proximal-left",
        c.L_POINTER_MIDDLE => "pointer-middle-left",
        c.L_POINTER_DISTAL => "pointer-distal-left",
        c.L_MIDDLE_PROXIMAL => "middle-proximal-left",
        c.L_MIDDLE_MIDDLE => "middle-middle-left",
        c.L_MIDDLE_DISTAL => "middle-distal-left",
        c.L_RING_PROXIMAL => "ring-proximal-left",
        c.L_RING_MIDDLE => "ring-middle-left",
        c.L_RING_DISTAL => "ring-distal-left",
        c.L_PINKY_PROXIMAL => "pinky-proximal-left",
        c.L_PINKY_MIDDLE => "pinky-middle-left",
        c.L_PINKY_DISTAL => "pinky-distal-left",
        c.R_THUMB_PROXIMAL => "thumb-proximal-right",
        c.R_THUMB_MIDDLE => "thumb-middle-right",
        c.R_THUMB_DISTAL => "thumb-distal-right",
        c.R_POINTER_PROXIMAL => "pointer-proximal-right",
        c.R_POINTER_MIDDLE => "pointer-middle-right",
        c.R_POINTER_DISTAL => "pointer-distal-right",
        c.R_MIDDLE_PROXIMAL => "middle-proximal-right",
        c.R_MIDDLE_MIDDLE => "middle-middle-right",
        c.R_MIDDLE_DISTAL => "middle-distal-right",
        c.R_RING_PROXIMAL => "ring-proximal-right",
        c.R_RING_MIDDLE => "ring-middle-right",
        c.R_RING_DISTAL => "ring-distal-right",
        c.R_PINKY_PROXIMAL => "pinky-proximal-right",
        c.R_PINKY_MIDDLE => "pinky-middle-right",
        c.R_PINKY_DISTAL => "pinky-distal-right",
        c.L_HIP => "hip-left",
        c.R_HIP => "hip-right",
        c.L_KNEE => "knee-left",
        c.R_KNEE => "knee-right",
        c.L_ANKLE => "ankle-left",
        c.R_ANKLE => "ankle-right",
        c.L_TOOL => "tool-left",
        c.R_TOOL => "tool-right",
        else => "broken",
    };
}

// ---------------------------------------------------------------------------
// 12. kindstr (C:4354-4366)
// ---------------------------------------------------------------------------
fn kindstr(num: c_int) [*c]const u8 {
    return switch (num) {
        c.EVENT_IDEVKIND_KEYBOARD => "keyboard",
        c.EVENT_IDEVKIND_MOUSE => "mouse",
        c.EVENT_IDEVKIND_GAMEDEV => "game",
        c.EVENT_IDEVKIND_TOUCHDISP => "touch",
        c.EVENT_IDEVKIND_EYETRACKER => "eyetracker",
        c.EVENT_IDEVKIND_LEDCTRL => "led",
        else => "broken",
    };
}

// ---------------------------------------------------------------------------
// 13. append_iotable (C:4382-4531)
// ---------------------------------------------------------------------------
fn append_iotable(ctx: ?*lua_State, ev: [*c]c.arcan_ioevent) void {
    const top = funtable(ctx, ev.*.kind);

    c.lua_pushlstring(ctx, "kind", 4);
    if (ev.*.label[0] != 0 and ev.*.kind != c.EVENT_IO_STATUS and
        ev.*.label[ev.*.label.len - 1] == 0)
    {
        tbldynstr(ctx, "label", @as([*c]const u8, @ptrCast(&ev.*.label)), top);
    }

    switch (ev.*.kind) {
        c.EVENT_IO_TOUCH => {
            c.lua_pushlstring(ctx, "touch", 5);
            c.lua_rawset(ctx, top);

            tblbool(ctx, "touch", true, top);
            tblnum(ctx, "devid", @floatFromInt(ev.*.unnamed_0.unnamed_0.devid), top);
            tblnum(ctx, "subid", @floatFromInt(ev.*.unnamed_0.unnamed_0.subid), top);
            tblnum(ctx, "pressure", ev.*.input.touch.pressure, top);
            tblbool(ctx, "active", ev.*.input.touch.active != 0, top);
            tblnum(ctx, "size", ev.*.input.touch.size, top);
            tblnum(ctx, "x", @floatFromInt(ev.*.input.touch.x), top);
            tblnum(ctx, "y", @floatFromInt(ev.*.input.touch.y), top);
        },

        c.EVENT_IO_EYES => {
            c.lua_pushlstring(ctx, "eyes", 4);
            c.lua_rawset(ctx, top);

            tblbool(ctx, "eyes", true, top);
            tblnum(ctx, "devid", @floatFromInt(ev.*.unnamed_0.unnamed_0.devid), top);
            tblnum(ctx, "subid", @floatFromInt(ev.*.unnamed_0.unnamed_0.subid), top);
            tblnum(ctx, "head_x", ev.*.input.eyes.head_pos[0], top);
            tblnum(ctx, "head_y", ev.*.input.eyes.head_pos[1], top);
            tblnum(ctx, "head_z", ev.*.input.eyes.head_pos[1], top); // note: C original uses [1] not [2]
            tblnum(ctx, "head_rx", ev.*.input.eyes.head_ang[0], top);
            tblnum(ctx, "head_ry", ev.*.input.eyes.head_ang[1], top);
            tblnum(ctx, "head_rz", ev.*.input.eyes.head_ang[2], top);
            tblnum(ctx, "x1", ev.*.input.eyes.gaze_x1, top);
            tblnum(ctx, "y1", ev.*.input.eyes.gaze_y1, top);
            tblnum(ctx, "x2", ev.*.input.eyes.gaze_x2, top);
            tblnum(ctx, "y2", ev.*.input.eyes.gaze_y2, top);
            tblbool(ctx, "present", ev.*.input.eyes.present != 0, top);
            tblbool(ctx, "blink_left", ev.*.input.eyes.blink_left != 0, top);
            tblbool(ctx, "blink_right", ev.*.input.eyes.blink_right != 0, top);
        },

        c.EVENT_IO_STATUS => {
            const lbl = c.platform_event_devlabel(@as(c_int, @intCast(ev.*.unnamed_0.unnamed_0.devid)));
            c.lua_pushlstring(ctx, "status", 6);
            c.lua_rawset(ctx, top);
            tblbool(ctx, "status", true, top);
            tblnum(ctx, "devid", @floatFromInt(ev.*.unnamed_0.unnamed_0.devid), top);
            tblnum(ctx, "subid", @floatFromInt(ev.*.unnamed_0.unnamed_0.subid), top);
            if (lbl != null)
                tbldynstr(ctx, "extlabel", lbl, top);

            tbldynstr(ctx, "devkind", kindstr(@as(c_int, @intCast(ev.*.input.status.devkind))), top);
            tbldynstr(ctx, "label", @as([*c]const u8, @ptrCast(&ev.*.label)), top);
            tblnum(ctx, "devref", @floatFromInt(ev.*.input.status.devref), top);

            switch (ev.*.input.status.domain) {
                0 => tblstr(ctx, "domain", "platform", top),
                1 => tblstr(ctx, "domain", "led", top),
                else => tblstr(ctx, "domain", "unknown-report", top),
            }

            switch (ev.*.input.status.action) {
                c.EVENT_IDEV_ADDED => tblstr(ctx, "action", "added", top),
                c.EVENT_IDEV_REMOVED => tblstr(ctx, "action", "removed", top),
                else => tblstr(ctx, "action", "blocked", top),
            }
        },

        c.EVENT_IO_AXIS_MOVE => {
            c.lua_pushlstring(ctx, "analog", 6);
            c.lua_rawset(ctx, top);
            if (ev.*.devkind == c.EVENT_IDEVKIND_MOUSE) {
                tblbool(ctx, "mouse", true, top);
                tblstr(ctx, "source", "mouse", top);
            } else {
                tblstr(ctx, "source", "joystick", top);
            }

            tblnum(ctx, "devid", @floatFromInt(ev.*.unnamed_0.unnamed_0.devid), top);
            tblnum(ctx, "subid", @floatFromInt(ev.*.unnamed_0.unnamed_0.subid), top);
            tblbool(ctx, "active", true, top);
            tblbool(ctx, "analog", true, top);
            tblbool(ctx, "relative", ev.*.input.analog.gotrel != 0, top);

            c.lua_pushlstring(ctx, "samples", 7);
            c.lua_createtable(ctx, @as(c_int, @intCast(ev.*.input.analog.nvalues)), 0);
            const top2 = c.lua_gettop(ctx);
            var i: usize = 0;
            while (i < @as(usize, @intCast(ev.*.input.analog.nvalues))) : (i += 1) {
                c.lua_pushnumber(ctx, @floatFromInt(i + 1));
                c.lua_pushnumber(ctx, @floatFromInt(ev.*.input.analog.axisval[i]));
                c.lua_rawset(ctx, top2);
            }
            c.lua_rawset(ctx, top);
        },

        c.EVENT_IO_BUTTON => {
            c.lua_pushlstring(ctx, "digital", 7);
            c.lua_rawset(ctx, top);
            tblbool(ctx, "digital", true, top);

            if (ev.*.devkind == c.EVENT_IDEVKIND_KEYBOARD) {
                tblbool(ctx, "translated", true, top);
                tblnum(ctx, "number", @floatFromInt(ev.*.input.translated.scancode), top);
                tblnum(ctx, "keysym", @floatFromInt(ev.*.input.translated.keysym), top);
                tblnum(ctx, "modifiers", @floatFromInt(ev.*.input.translated.modifiers), top);
                tblnum(ctx, "devid", @floatFromInt(ev.*.unnamed_0.unnamed_0.devid), top);
                tblnum(ctx, "subid", @floatFromInt(ev.*.unnamed_0.unnamed_0.subid), top);
                tbldynstr(ctx, "utf8", @as([*c]const u8, @ptrCast(&ev.*.input.translated.utf8)), top);
                tblbool(ctx, "active", ev.*.input.translated.active != 0, top);
                tblstr(ctx, "device", "translated", top);
                tblbool(ctx, "keyboard", true, top);
            } else if (ev.*.devkind == c.EVENT_IDEVKIND_MOUSE or
                ev.*.devkind == c.EVENT_IDEVKIND_GAMEDEV)
            {
                if (ev.*.devkind == c.EVENT_IDEVKIND_MOUSE) {
                    tblbool(ctx, "mouse", true, top);
                    tblstr(ctx, "source", "mouse", top);
                } else {
                    tblbool(ctx, "joystick", true, top);
                    tblstr(ctx, "source", "joystick", top);
                }
                tblbool(ctx, "translated", false, top);
                tblnum(ctx, "devid", @floatFromInt(ev.*.unnamed_0.unnamed_0.devid), top);
                tblnum(ctx, "subid", @floatFromInt(ev.*.unnamed_0.unnamed_0.subid), top);
                tblbool(ctx, "active", ev.*.input.digital.active != 0, top);
            }
        },

        else => {
            c.lua_pushlstring(ctx, "unknown", 7);
            c.lua_rawset(ctx, top);
            c.arcan_warning("Engine -> Script: ignoring IO event: %i\n", ev.*.kind);
        },
    }
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part5d.zig
// ══════════════════════════════════════════════════════════════════════



// slim_utf8_push (MSGBUF_UTF8 macro)
// Declared as extern since it is a static function defined in another
// translation unit of the arcan_lua.c port.

// append_iotable

// alt_call

// alt_nbio_import
extern fn alt_nbio_import(L: ?*lua_State, fd: c_int, mode: c.mode_t, dst: *?*c.nonblock_io, unlink_fn: ?*[*c]u8) bool;

// alt_nbio_open
extern fn alt_nbio_open(L: ?*lua_State) callconv(.c) c_int;

// import_btype (lines 4532-4547)
// Imports a buffer type from an event fd, setting table fields.
fn import_btype(
    L: ?*lua_State,
    top: c_int,
    reset: c_int,
    key: [*c]const u8,
    mode: c_int,
    fd_in: c_int,
) bool {
    var dst: ?*c.nonblock_io = null;

    set_tblstr(L, "kind", key, top);
    c.lua_pushstring(L, "io");
    const fd = c.arcan_shmif_dupfd(fd_in, -1, false);
    if (alt_nbio_import(L, fd, @intCast(@as(c_uint, @bitCast(mode))), &dst, null)) {
        c.lua_rawset(L, top);
        return true;
    }

    c.lua_settop(L, reset);
    return false;
}

// arcan_lwa_subseg_ev (lines 4549-4652)
// Handles LWA subsegment events; public, non-static.
export fn arcan_lwa_subseg_ev(
    ctx: ?*lua_State,
    source: arcan_vobj_id,
    cb_tag_in: usize,
    ev: [*c]arcan_event,
) callconv(.c) void {
    const reset = c.lua_gettop(ctx);
    var cb_tag = cb_tag_in;

    if (ev.*.unnamed_0.unnamed_0.category != c.EVENT_TARGET and
        ev.*.unnamed_0.unnamed_0.category != c.EVENT_IO)
        return;

    if (source == c.ARCAN_VIDEO_WORLDID)
        cb_tag = @bitCast(luactx.worldid_tag);

    if (cb_tag == @as(usize, @bitCast(@as(isize, c.LUA_NOREF)))) {
        // if we don't get a callback tag, it is added to the worldid as an 'arcan'
        // entrypoint for those that aren't covered elsewhere
        c.lua_settop(ctx, reset);
        return;
    } else {
        _ = c.lua_rawgeti(ctx, c.LUA_REGISTRYINDEX, @as(c_int, @intCast(@as(isize, @bitCast(cb_tag)))));
    }

    lua_pushvid(ctx, source);

    if (ev.*.unnamed_0.unnamed_0.category == c.EVENT_IO) {
        // re-use the same table mapping as normal
        append_iotable(ctx, &ev.*.unnamed_0.unnamed_0.unnamed_0.io);
        alt_call(
            ctx,
            c.CB_SOURCE_NONE,
            @as(u64, @bitCast(@as(c_long, c.EP_TRIGGER_LWA))),
            0,
            2,
            0,
            "arcan_lua.zig:event:lwa_io",
        );
        return;
    }

    c.lua_newtable(ctx);
    const top = c.lua_gettop(ctx);

    // msgbuf: COUNT_OF(ev->tgt.message) + 1 = 78 + 1 = 79
    var msgbuf: [79]u8 = undefined;

    const tgt = &ev.*.unnamed_0.unnamed_0.unnamed_0.tgt;

    switch (tgt.kind) {
        // unfinished — C fall-through: STORE -> RESTORE -> BCHUNK_IN
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_STORE))) => {
            if (!import_btype(ctx, top, reset, "store", c.O_WRONLY, tgt.ioevs[0].iv))
                return;
            // fall through to RESTORE
            if (!import_btype(ctx, top, reset, "restore", c.O_RDONLY, tgt.ioevs[0].iv))
                return;
            // fall through to BCHUNK_IN
            if (!import_btype(ctx, top, reset, "bchunk-in", c.O_RDONLY, tgt.ioevs[0].iv))
                return;
            slim_utf8_push(&msgbuf, 78, @constCast(@ptrCast(&tgt.unnamed_0.message)));
            set_tbldynstr(ctx, "id", &msgbuf, top);
        },
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_RESTORE))) => {
            if (!import_btype(ctx, top, reset, "restore", c.O_RDONLY, tgt.ioevs[0].iv))
                return;
            // fall through to BCHUNK_IN
            if (!import_btype(ctx, top, reset, "bchunk-in", c.O_RDONLY, tgt.ioevs[0].iv))
                return;
            slim_utf8_push(&msgbuf, 78, @constCast(@ptrCast(&tgt.unnamed_0.message)));
            set_tbldynstr(ctx, "id", &msgbuf, top);
        },
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_BCHUNK_IN))) => {
            if (!import_btype(ctx, top, reset, "bchunk-in", c.O_RDONLY, tgt.ioevs[0].iv))
                return;
            slim_utf8_push(&msgbuf, 78, @constCast(@ptrCast(&tgt.unnamed_0.message)));
            set_tbldynstr(ctx, "id", &msgbuf, top);
        },
        // BCHUNK_OUT falls through to the ignored group
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_BCHUNK_OUT))) => {
            if (!import_btype(ctx, top, reset, "bchunk-out", c.O_WRONLY, tgt.ioevs[0].iv))
                return;
            slim_utf8_push(&msgbuf, 78, @constCast(@ptrCast(&tgt.unnamed_0.message)));
            set_tbldynstr(ctx, "id", &msgbuf, top);
            // fall through to ignored group
            c.lua_settop(ctx, reset);
            return;
        },

        // Ignored group: these commands are not forwarded to Lua
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_FRAMESKIP))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_STEPFRAME))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_PAUSE))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_UNPAUSE))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_GRAPHMODE))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_ANCHORHINT))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_RESET))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_SEEKCONTENT))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_COREOPT))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_SEEKTIME))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_ATTENUATE))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_STREAMSET))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_SETIODEV))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_AUDDELAY))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_DEVICESTATE))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_GEOHINT))),
        => {
            c.lua_settop(ctx, reset);
            return;
        },

        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_MESSAGE))) => {
            set_tblstr(ctx, "kind", "message", top);
            set_tblbool(ctx, "multipart", tgt.ioevs[0].iv != 0, top);
            slim_utf8_push(&msgbuf, 78, @constCast(@ptrCast(&tgt.unnamed_0.message)));
            set_tbldynstr(ctx, "message", &msgbuf, top);
        },

        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_EXIT))) => {
            // map to 'terminated'
            set_tblstr(ctx, "kind", "terminated", top);
        },

        // Already handled internally
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_NEWSEGMENT))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_REQFAIL))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_OUTPUTHINT))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_ACTIVATE))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_DISPLAYHINT))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_FONTHINT))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_BUFFER_FAIL))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_DEVICE_NODE))),
        @as(c_uint, @bitCast(@as(c_int, c.TARGET_COMMAND_LIMIT))),
        => {
            c.lua_settop(ctx, reset);
            return;
        },

        else => {},
    }

    alt_call(
        ctx,
        c.CB_SOURCE_NONE,
        @as(u64, @bitCast(@as(c_long, c.EP_TRIGGER_LWA))),
        0,
        2,
        0,
        "arcan_lua.zig:event:lwa",
    );
}

// arcan_lwa_subseg_adopt (lines 4659-4684)
// Adopts an LWA subsegment; public, non-static.
export fn arcan_lwa_subseg_adopt(
    L: ?*lua_State,
    C: [*c]c.arcan_shmif_cont,
) callconv(.c) void {
    if (luactx.worldid_tag == @as(isize, c.LUA_NOREF)) {
        c.arcan_shmif_drop(C);
        return;
    }

    _ = c.lua_rawgeti(L, c.LUA_REGISTRYINDEX, @as(c_int, @truncate(luactx.worldid_tag)));
    luactx.pending_segpush = C;
    lua_pushvid(L, c.ARCAN_VIDEO_WORLDID);
    c.lua_newtable(L);
    const top = c.lua_gettop(L);

    set_tblstr(L, "kind", "segment_request", top);
    set_tblnum(L, "width", @floatFromInt(C.*.w), top);
    set_tblnum(L, "height", @floatFromInt(C.*.h), top);
    set_tblnum(L, "reqid", 0, top);
    set_tblnum(L, "xofs", 0, top);
    set_tblnum(L, "yofs", 0, top);

    alt_call(
        L,
        c.CB_SOURCE_NONE,
        @as(u64, @bitCast(@as(c_long, c.EP_TRIGGER_LWA))),
        0,
        2,
        0,
        "arcan_lua.zig:event:lwa",
    );

    if (luactx.pending_segpush != null) {
        luactx.pending_segpush = null;
        c.arcan_shmif_drop(C);
    }
}

// eotfstr (lines 4688-4698)
// Returns the EOTF string name for a given numeric EOTF value.
fn eotfstr(eotf: c_int) [*c]const u8 {
    return switch (eotf) {
        0 => "sdr",
        1 => "hdr",
        2 => "pq",
        3 => "hdg",
        else => "bad",
    };
}

// spacetostr (lines 4701-4726)
// Returns the colorspace string name for a given numeric space value.
// From shmif_event.h: struct netstate definition.
fn spacetostr(space: c_int) [*c]const u8 {
    return switch (space) {
        0 => "tag",
        1 => "basename",
        2 => "subname",
        3 => "ipv4",
        4 => "ipv6",
        5 => "a12pub",
        6 => "connectivity",
        else => "unknown",
    };
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part5e.zig
// ══════════════════════════════════════════════════════════════════════

// arcan_lua_pushevent — dispatch arcan events to Lua callbacks
// Ported from arcan_lua.c lines 4728-5323

// ---------------------------------------------------------------------------
// arcan_lua_pushevent (C:4728-5320) — dispatch arcan events to Lua callbacks
// ---------------------------------------------------------------------------
export fn arcan_lua_pushevent(ctx: ?*lua_State, ev: [*c]arcan_event) callconv(.c) bool {
    var adopt_check: bool = false;
    var msgbuf: [@sizeOf(arcan_event) + 1]u8 = undefined;

    if (ev == null) {
        if (c.alt_lookup_entry(ctx, "input_end", 9)) {
            c.alt_call(ctx, c.CB_SOURCE_NONE,
                @as(u64, @intCast(c.EP_TRIGGER_INPUT_END)), 0, 0, 0, "input_end");
        }
        return true;
    }

    const category = ev.*.unnamed_0.unnamed_0.category;

    if (category == c.EVENT_IO) {
        // try to deliver the raw out-of-loop input, but defer / reinject if the
        // script can't handle it or rejects it
        if (c.arcan_conductor_gpus_locked() != 0) {
            var consumed: bool = false;
            if (c.alt_lookup_entry(ctx, "input_raw", 9)) {
                append_iotable(ctx, &ev.*.unnamed_0.unnamed_0.unnamed_0.io);
                c.alt_call(ctx, c.CB_SOURCE_NONE,
                    @as(u64, @intCast(c.EP_TRIGGER_INPUT_RAW)), 0, 1, 1, "event:input_raw");

                if (c.lua_type(ctx, -1) == c.LUA_TBOOLEAN and c.lua_toboolean(ctx, -1) != 0) {
                    consumed = true;
                }
                c.lua_settop(ctx, -(1) - 1);
            }
            return consumed;
        }

        if (c.alt_lookup_entry(ctx, "input", 5)) {
            append_iotable(ctx, &ev.*.unnamed_0.unnamed_0.unnamed_0.io);
            c.alt_call(ctx, c.CB_SOURCE_NONE,
                @as(u64, @intCast(c.EP_TRIGGER_INPUT)), 0, 1, 0, "event:input");
        }
        return true;
    }

    if (category == c.EVENT_SYSTEM) {
        const sys = &ev.*.unnamed_0.unnamed_0.unnamed_0.sys;

        if (sys.kind == c.EVENT_SYSTEM_DATA_IN) {
            if (sys.unnamed_0.data.otag == c.LUA_NOREF)
                return true;
            c.alt_nbio_data_in(ctx, sys.unnamed_0.data.otag);
        } else if (sys.kind == c.EVENT_SYSTEM_DATA_OUT) {
            if (sys.unnamed_0.data.otag == c.LUA_NOREF)
                return true;
            c.alt_nbio_data_out(ctx, sys.unnamed_0.data.otag);
        }
        return true;
    }

    // all other events are prohibited while gpus are locked
    if (c.arcan_conductor_gpus_locked() != 0) {
        return false;
    }

    if (category == c.EVENT_EXTERNAL) {
        var preroll: bool = false;
        const ext = &ev.*.unnamed_0.unnamed_0.unnamed_0.ext;

        // need to jump through a few hoops to get hold of the possible callback
        const vobj = c.arcan_video_getobject(ext.source);
        if (vobj == null or vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV) {
            return true;
        }

        const reset = c.lua_gettop(ctx);
        const fsrv: ?*c.arcan_frameserver = @ptrCast(@alignCast(vobj.*.feed.state.ptr));
        if (fsrv_helper_get_tag(fsrv) == c.LUA_NOREF) {
            return true;
        }
        _ = c.lua_rawgeti(ctx, c.LUA_REGISTRYINDEX, @intCast(fsrv_helper_get_tag(fsrv)));
        lua_pushvid(ctx, ext.source);

        c.lua_createtable(ctx, 0, 0);
        const top = c.lua_gettop(ctx);
        set_tblnum(ctx, "frame", @floatFromInt(ext.frame_id), top);

        switch (ext.kind) {
            c.EVENT_EXTERNAL_IDENT => {
                set_tblstr(ctx, "kind", "ident", top);
                slim_utf8_push(&msgbuf, @intCast(ext.unnamed_0.message.data.len),
                    @ptrCast(@constCast(&ext.unnamed_0.message.data)));
                set_tblstr(ctx, "message", &msgbuf, top);
            },
            c.EVENT_EXTERNAL_COREOPT => {
                set_tblstr(ctx, "kind", "coreopt", top);
                set_tblnum(ctx, "slot", @floatFromInt(ext.unnamed_0.coreopt.index), top);
                slim_utf8_push(&msgbuf, @intCast(ext.unnamed_0.message.data.len),
                    @ptrCast(@constCast(&ext.unnamed_0.message.data)));
                set_tblstr(ctx, "argument", &msgbuf, top);
                if (ext.unnamed_0.coreopt.@"type" == 0)
                    set_tblstr(ctx, "type", "key", top)
                else if (ext.unnamed_0.coreopt.@"type" == 1)
                    set_tblstr(ctx, "type", "description", top)
                else if (ext.unnamed_0.coreopt.@"type" == 2)
                    set_tblstr(ctx, "type", "value", top)
                else if (ext.unnamed_0.coreopt.@"type" == 3)
                    set_tblstr(ctx, "type", "current", top)
                else {
                    c.lua_settop(ctx, reset);
                    return true;
                }
            },
            // this is handled / managed through _event.c, _conductor.c and _frameserver.c
            c.EVENT_EXTERNAL_CLOCKREQ => {
                c.lua_settop(ctx, reset);
                return true;
            },
            c.EVENT_EXTERNAL_CONTENT => {
                set_tblstr(ctx, "kind", "content_state", top);
                set_tblnum(ctx, "rel_x", @as(f64, @floatCast(ext.unnamed_0.content.x_pos)), top);
                set_tblnum(ctx, "rel_y", @as(f64, @floatCast(ext.unnamed_0.content.y_pos)), top);
                set_tblnum(ctx, "wnd_w", @as(f64, @floatCast(ext.unnamed_0.content.width)), top);
                set_tblnum(ctx, "wnd_h", @as(f64, @floatCast(ext.unnamed_0.content.height)), top);
                set_tblnum(ctx, "x_size", @as(f64, @floatCast(ext.unnamed_0.content.x_sz)), top);
                set_tblnum(ctx, "y_size", @as(f64, @floatCast(ext.unnamed_0.content.y_sz)), top);
                set_tblnum(ctx, "cell_w", @floatFromInt(ext.unnamed_0.content.cell_w), top);
                set_tblnum(ctx, "cell_h", @floatFromInt(ext.unnamed_0.content.cell_h), top);
                set_tblnum(ctx, "min_w", @floatFromInt(ext.unnamed_0.content.min_w), top);
                set_tblnum(ctx, "min_h", @floatFromInt(ext.unnamed_0.content.min_h), top);
                set_tblnum(ctx, "max_w", @floatFromInt(ext.unnamed_0.content.max_w), top);
                set_tblnum(ctx, "max_h", @floatFromInt(ext.unnamed_0.content.max_h), top);
            },
            // the actual mask state can be queried through input capabilities
            c.EVENT_EXTERNAL_INPUTMASK => {
                set_tblstr(ctx, "kind", "mask_input", top);
            },
            c.EVENT_EXTERNAL_VIEWPORT => {
                set_tblstr(ctx, "kind", "viewport", top);
                push_view(ctx, ext, fsrv, top);
            },
            c.EVENT_EXTERNAL_CURSORHINT => {
                fltpush(&msgbuf, @intCast(ext.unnamed_0.message.data.len - 1),
                    @ptrCast(@constCast(&ext.unnamed_0.message.data)),
                    flt_chint, '?');
                set_tblstr(ctx, "cursor", &msgbuf, top);
                set_tblstr(ctx, "kind", "cursorhint", top);
            },
            c.EVENT_EXTERNAL_ALERT, c.EVENT_EXTERNAL_MESSAGE => {
                // In C this uses the if(0) trick to share the tail between ALERT and MESSAGE.
                // ALERT sets kind="alert", MESSAGE sets kind="message", then both share the
                // MSGBUF_UTF8 + multipart + message tail.
                if (ext.kind == c.EVENT_EXTERNAL_ALERT)
                    set_tblstr(ctx, "kind", "alert", top)
                else
                    set_tblstr(ctx, "kind", "message", top);
                slim_utf8_push(&msgbuf, @intCast(ext.unnamed_0.message.data.len),
                    @ptrCast(@constCast(&ext.unnamed_0.message.data)));
                set_tblbool(ctx, "multipart", ext.unnamed_0.message.multipart != 0, top);
                set_tblstr(ctx, "message", &msgbuf, top);
            },
            c.EVENT_EXTERNAL_FAILURE => {
                set_tblstr(ctx, "kind", "failure", top);
                slim_utf8_push(&msgbuf, @intCast(ext.unnamed_0.message.data.len),
                    @ptrCast(@constCast(&ext.unnamed_0.message.data)));
                set_tblstr(ctx, "message", &msgbuf, top);
            },
            // DEPRECATED
            c.EVENT_EXTERNAL_FRAMESTATUS => {
                c.lua_settop(ctx, reset);
                return true;
            },
            c.EVENT_EXTERNAL_STREAMINFO => {
                fltpush(&msgbuf, @intCast(ext.unnamed_0.streaminf.langid.len - 1),
                    @ptrCast(@constCast(&ext.unnamed_0.streaminf.langid)),
                    flt_Alpha, '?');
                set_tblstr(ctx, "kind", "streaminfo", top);
                set_tblstr(ctx, "lang", &msgbuf, top);
                set_tblnum(ctx, "streamid", @floatFromInt(ext.unnamed_0.streaminf.streamid), top);
                set_tblstr(ctx, "type",
                    streamtype(@intCast(ext.unnamed_0.streaminf.datakind)), top);
            },
            c.EVENT_EXTERNAL_STREAMSTATUS => {
                set_tblstr(ctx, "kind", "streamstatus", top);
                fltpush(&msgbuf, @intCast(ext.unnamed_0.streamstat.timestr.len - 1),
                    @ptrCast(@constCast(&ext.unnamed_0.streamstat.timestr)),
                    flt_num, '?');
                set_tblstr(ctx, "ctime", &msgbuf, top);
                fltpush(&msgbuf, @intCast(ext.unnamed_0.streamstat.timelim.len - 1),
                    @ptrCast(@constCast(&ext.unnamed_0.streamstat.timelim)),
                    flt_num, '?');
                set_tblstr(ctx, "endtime", &msgbuf, top);
                set_tblnum(ctx, "completion",
                    @as(f64, @floatCast(ext.unnamed_0.streamstat.completion)), top);
                set_tblnum(ctx, "frameno",
                    @floatFromInt(ext.unnamed_0.streamstat.frameno), top);
                set_tblnum(ctx, "streaming",
                    @floatFromInt(@as(c_int, @intFromBool(ext.unnamed_0.streamstat.streaming != 0))), top);
            },
            // special semantics for segreq
            c.EVENT_EXTERNAL_SEGREQ => {
                emit_segreq(ctx, fsrv, ext);
                return true;
            },
            c.EVENT_EXTERNAL_LABELHINT => {
                const idt = lookup_idatatype(@intCast(ext.unnamed_0.labelhint.idatatype));
                if (idt == null) {
                    c.lua_settop(ctx, reset);
                    return true;
                }
                slim_utf8_push(&msgbuf, @intCast(ext.unnamed_0.labelhint.descr.len),
                    @ptrCast(@constCast(&ext.unnamed_0.labelhint.descr)));
                set_tblstr(ctx, "description", &msgbuf, top);
                set_tblstr(ctx, "kind", "input_label", top);
                fltpush(&msgbuf, @intCast(ext.unnamed_0.labelhint.label.len - 1),
                    @ptrCast(@constCast(&ext.unnamed_0.labelhint.label)),
                    flt_Alphanum, '?');
                set_tblstr(ctx, "labelhint", &msgbuf, top);
                set_tblnum(ctx, "initial", @floatFromInt(ext.unnamed_0.labelhint.initial), top);
                set_tblstr(ctx, "datatype", idt.?, top);
                set_tblnum(ctx, "modifiers", @floatFromInt(ext.unnamed_0.labelhint.modifiers), top);
                slim_utf8_push(&msgbuf, @intCast(ext.unnamed_0.labelhint.vsym.len),
                    @ptrCast(@constCast(&ext.unnamed_0.labelhint.vsym)));
                set_tblstr(ctx, "vsym", &msgbuf, top);
            },
            c.EVENT_EXTERNAL_BCHUNKSTATE => {
                set_tblstr(ctx, "kind", "bchunkstate", top);
                if ((ext.unnamed_0.bchunk.hint & 8) > 0) {
                    set_tblbool(ctx, "cursor", true, top);
                    set_tblbool(ctx, "hint", false, top);
                } else {
                    set_tblbool(ctx, "hint", !((ext.unnamed_0.bchunk.hint & 1) > 0), top);
                    set_tblbool(ctx, "cursor", false, top);
                }
                set_tblbool(ctx, "multipart", (ext.unnamed_0.bchunk.hint & 4) != 0, top);
                set_tblnum(ctx, "size", @floatFromInt(ext.unnamed_0.bchunk.unnamed_0.size), top);
                set_tblbool(ctx, "input", ext.unnamed_0.bchunk.input != 0, top);
                set_tblbool(ctx, "stream", ext.unnamed_0.bchunk.stream != 0, top);
                set_tblbool(ctx, "wildcard", (ext.unnamed_0.bchunk.hint & 2) != 0, top);
                set_tblbool(ctx, "disable", ext.unnamed_0.bchunk.extensions[0] == 0, top);
                if (ext.unnamed_0.bchunk.extensions[0] != 0) {
                    fltpush(&msgbuf, @intCast(ext.unnamed_0.bchunk.extensions.len - 1),
                        @ptrCast(@constCast(&ext.unnamed_0.bchunk.extensions)),
                        flt_chunkfn, '\x00');
                    set_tblstr(ctx, "extensions", &msgbuf, top);
                }
                // ZCS-Live Phase 5: the may.zcs publisher pushes the live
                // InternPool-arena memfd via SCM_RIGHTS immediately BEFORE this
                // BCHUNKSTATE event, tagged "may.iparena". The generic external
                // event path does NOT fetch a passed descriptor (unlike
                // BUFFERSTREAM), so we fetch it here — ONLY for that exact tag,
                // to avoid consuming descriptors on ordinary bchunk hints — and
                // expose it to the appl as `stat.fd` (a raw fd number) so the
                // deep-view builtins can mmap the arena. -1 when no fd arrived.
                if (is_iparena_ext(&ext.unnamed_0.bchunk.extensions)) {
                    const shmif_offsets = @import("shmif_offsets");
                    const dpipe = shmif_offsets.Fsrv.getDpipe(@ptrCast(fsrv));
                    const arena_fd = arcan_fetchhandle(dpipe, false);
                    const arena_size: f64 = @floatFromInt(ext.unnamed_0.bchunk.unnamed_0.size);
                    set_tblnum(ctx, "fd", @floatFromInt(arena_fd), top);
                    // The may.zcs debug window's appl-managed lifecycle surfaces
                    // it in `all_windows` only seconds after the fd arrives
                    // (during preroll), so the per-window `stat.fd` capture races
                    // window adoption. Also stash the LATEST live fd+size into a
                    // process-global Lua table `_zcs_arena` (source vid keyed),
                    // which the probe/builtins read regardless of window state.
                    if (arena_fd >= 0) zcs_stash_arena_fd(ctx, @floatFromInt(@as(i64, @bitCast(@as(u64, @intCast(ext.source))))), @floatFromInt(arena_fd), arena_size);
                }
            },
            // This event does not arrive raw, the tracking properties are
            // projected unto the event during queuetransfer
            c.EVENT_EXTERNAL_PRIVDROP => {
                set_tblstr(ctx, "kind", "privdrop", top);
                set_tblbool(ctx, "external", ext.unnamed_0.privdrop.external != 0, top);
                set_tblbool(ctx, "sandboxed", ext.unnamed_0.privdrop.external != 0, top);
                set_tblbool(ctx, "networked", ext.unnamed_0.privdrop.external != 0, top);
            },
            c.EVENT_EXTERNAL_STATESIZE => {
                set_tblstr(ctx, "kind", "state_size", top);
                set_tblnum(ctx, "state_size", @floatFromInt(ext.unnamed_0.stateinf.size), top);
                set_tblnum(ctx, "typeid", @floatFromInt(ext.unnamed_0.stateinf.@"type"), top);
            },
            c.EVENT_EXTERNAL_NETSTATE => {
                set_tblstr(ctx, "kind", "state", top);
                set_tblstr(ctx, "namespace", spacetostr(ext.unnamed_0.netstate.space), top);
                if (ext.unnamed_0.netstate.space == 5) {
                    slim_utf8_push(&msgbuf, @intCast(ext.unnamed_0.netstate.unnamed_0.name.len),
                        @ptrCast(@constCast(&ext.unnamed_0.netstate.unnamed_0.name)));
                    set_tblstr(ctx, "name", &msgbuf, top);
                    var dsz: usize = 0;
                    const b64 = c.arcan_base64_encode(
                        @ptrCast(&ext.unnamed_0.netstate.unnamed_0.unnamed_0.pubk),
                        32, &dsz, 0);
                    set_tbldynstr(ctx, "pubk", b64, top);
                } else {
                    slim_utf8_push(&msgbuf, @intCast(ext.unnamed_0.netstate.unnamed_0.name.len),
                        @ptrCast(@constCast(&ext.unnamed_0.netstate.unnamed_0.name)));
                    set_tblstr(ctx, "name", &msgbuf, top);
                }

                if ((ext.unnamed_0.netstate.state & (1 | 2 | 4)) != 0) {
                    if (ext.unnamed_0.netstate.space == 6) {
                        set_tblbool(ctx, "connected", true, top);
                    } else {
                        set_tblbool(ctx, "discovered", true, top);
                        set_tblbool(ctx, "multipart", ext.unnamed_0.netstate.state == 2, top);
                    }
                } else if (ext.unnamed_0.netstate.state == 0) {
                    set_tblbool(ctx, "lost", true, top);
                } else {
                    set_tblbool(ctx, "bad", true, top);
                }

                if (ext.unnamed_0.netstate.@"type" == 1)
                    set_tblbool(ctx, "source", true, top);
                if (ext.unnamed_0.netstate.@"type" == 2)
                    set_tblbool(ctx, "sink", true, top);
                if (ext.unnamed_0.netstate.@"type" == 4)
                    set_tblbool(ctx, "directory", true, top);
            },
            c.EVENT_EXTERNAL_REGISTER => {
                // DEBUG: confirm REGISTER reaches Lua dispatch for this fsrv
                const smon = @import("shmif_monitor");
                smon.emit("lua-REGISTER", @intCast(ext.source),
                    @intCast(c.EVENT_EXTERNAL), @intCast(ext.unnamed_0.registr.kind));
                // prevent switching types
                var id: c_uint = ext.unnamed_0.registr.kind;
                const segid: c_uint = @bitCast(fsrv_helper_get_segid(fsrv));
                if (segid != c.SEGID_UNKNOWN and
                    ext.unnamed_0.registr.kind != segid)
                {
                    id = segid;
                    // In C: ev->ext.registr.kind = fsrv->segid
                    // Modify the event through the original pointer
                    ev.*.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.registr.kind = segid;
                }
                // as well as registering protected types
                else if (fsrv_helper_get_segid(fsrv) == c.SEGID_UNKNOWN and
                    (id == c.SEGID_NETWORK_CLIENT or id == c.SEGID_NETWORK_SERVER))
                {
                    c.arcan_warning("client (%d) attempted to register a reserved (%d) " ++
                        "type which is not permitted.\n", @as(c_int, @intCast(fsrv_helper_get_segid(fsrv))), @as(c_int, @intCast(id)));
                    c.lua_settop(ctx, reset);
                    return true;
                }
                // update and mark for pre-roll unless protected
                if (fsrv_helper_get_segid(fsrv) == c.SEGID_UNKNOWN) {
                    fsrv_helper_set_segid(fsrv, @intCast(id));
                    preroll = true;
                }
                set_tblstr(ctx, "kind", "registered", top);
                set_tblstr(ctx, "segkind", fsrvtos(ext.unnamed_0.registr.kind), top);
                slim_utf8_push(&msgbuf, @intCast(ext.unnamed_0.registr.title.len),
                    @ptrCast(@constCast(&ext.unnamed_0.registr.title)));
                _ = c.snprintf(fsrv_helper_get_title_buf(fsrv), fsrv_helper_get_title_buf_len(fsrv), "%s", @as([*c]u8, &msgbuf));
                set_tblstr(ctx, "title", &msgbuf, top);

                var dsz: usize = 0;
                const b64 = c.arcan_base64_encode(
                    @ptrCast(&ext.unnamed_0.registr.guid[0]),
                    16, &dsz, 0);
                set_tbldynstr(ctx, "guid", b64, top);
            },
            else => {
                set_tblstr(ctx, "kind", "unknown", top);
                set_tblnum(ctx, "kind_num", @floatFromInt(ext.kind), top);
            },
        }

        c.alt_call(ctx, c.CB_SOURCE_FRAMESERVER, @as(u64, @intCast(c.EP_TRIGGER_FRAMESERVER)),
            @bitCast(ext.source), 2, 0, "frameserver:event");
        // special: external connection + connected->registered sequence finished
        if (preroll) {
            do_preroll(ctx, fsrv_helper_get_tag(fsrv), fsrv_helper_get_vid(fsrv), fsrv_helper_get_aid(fsrv));
        }
    } else if (category == c.EVENT_FSRV) {
        const fsrv_ev = &ev.*.unnamed_0.unnamed_0.unnamed_0.fsrv;
        const vobj = c.arcan_video_getobject(fsrv_ev.video);

        // this can happen if the frameserver has died and been enqueued but
        // delete_image was called in between, in that case, we still want to drop the
        // reference.
        if (vobj == null) {
            if (fsrv_ev.otag != c.LUA_NOREF) {
                // otag is intptr_t in the C event struct (holds either a
                // small luaL_ref return or a callback pointer). When used
                // as a Lua registry ref the real value fits in i32, but we
                // can't assert that here because the engine also writes
                // pointer-sized garbage into otag on some paths. Match C's
                // implicit cast semantics with @truncate rather than
                // @intCast, which panics on any 64→32 overflow.
                c.luaL_unref(ctx, c.LUA_REGISTRYINDEX, @truncate(fsrv_ev.otag));
            }
            return true;
        }

        // the backing frameserver is already free:d at this point, hence why we need
        // the reference to stay on the queue so that we can unref accordingly
        if (fsrv_ev.kind == c.EVENT_FSRV_TERMINATED) {
            if (fsrv_ev.otag == c.LUA_NOREF)
                return true;

            // function, source, status
            _ = c.lua_rawgeti(ctx, c.LUA_REGISTRYINDEX, @truncate(fsrv_ev.otag));
            lua_pushvid(ctx, fsrv_ev.video);
            c.lua_createtable(ctx, 0, 0);

            const top = c.lua_gettop(ctx);
            set_tblstr(ctx, "kind", "terminated", top);
            slim_utf8_push(&msgbuf, @intCast(fsrv_ev.unnamed_0.unnamed_0.message.len),
                @ptrCast(@constCast(&fsrv_ev.unnamed_0.unnamed_0.message)));
            set_tblstr(ctx, "last_words", &msgbuf, top);
            c.alt_call(ctx,
                c.CB_SOURCE_FRAMESERVER, @as(u64, @intCast(c.EP_TRIGGER_FRAMESERVER)),
                @bitCast(fsrv_ev.otag), 2, 0, "frameserver:event");
            c.luaL_unref(ctx, c.LUA_REGISTRYINDEX, @truncate(fsrv_ev.otag));
            return true;
        }

        // Special case, VR inherits some properties from frameserver,
        // but masks / shields a lot of the default eventloop
        if (vobj.*.feed.state.tag == c.ARCAN_TAG_VR) {
            if (fsrv_ev.otag == c.LUA_NOREF)
                return true;

            _ = c.lua_rawgeti(ctx, c.LUA_REGISTRYINDEX, @truncate(fsrv_ev.otag));
            lua_pushvid(ctx, fsrv_ev.video);
            c.lua_createtable(ctx, 0, 0);
            const top = c.lua_gettop(ctx);
            if (fsrv_ev.kind == c.EVENT_FSRV_ADDVRLIMB) {
                set_tblstr(ctx, "kind", "limb_added", top);
                set_tblnum(ctx, "id", @floatFromInt(fsrv_ev.unnamed_0.unnamed_3.limb), top);
                set_tblstr(ctx, "name", limb_name(@intCast(fsrv_ev.unnamed_0.unnamed_3.limb)), top);
            } else {
                set_tblstr(ctx, "kind", "limb_lost", top);
                set_tblnum(ctx, "id", @floatFromInt(fsrv_ev.unnamed_0.unnamed_3.limb), top);
                set_tblstr(ctx, "name", limb_name(@intCast(fsrv_ev.unnamed_0.unnamed_3.limb)), top);
            }
            c.alt_call(ctx, c.CB_SOURCE_FRAMESERVER,
                @as(u64, @intCast(c.EP_TRIGGER_FRAMESERVER)), @bitCast(fsrv_ev.otag), 2, 0, "frameserver:vr");
            return true;
        }

        if (vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV)
            return true;

        const fsrv: [*c]c.arcan_frameserver = @ptrCast(@alignCast(vobj.*.feed.state.ptr));
        if (c.LUA_NOREF == fsrv_helper_get_tag(fsrv))
            return true;

        if (fsrv_ev.kind == c.EVENT_FSRV_PREROLL) {
            do_preroll(ctx, fsrv_helper_get_tag(fsrv), fsrv_helper_get_vid(fsrv), fsrv_helper_get_aid(fsrv));
            return true;
        }

        // function, source, status
        _ = c.lua_rawgeti(ctx, c.LUA_REGISTRYINDEX, @truncate(fsrv_ev.otag));
        lua_pushvid(ctx, fsrv_ev.video);
        c.lua_createtable(ctx, 0, 0);

        var argc: c_int = 2;
        const top = c.lua_gettop(ctx);

        set_tblnum(ctx, "source_audio", @floatFromInt(fsrv_ev.unnamed_0.unnamed_0.audio), top);

        switch (fsrv_ev.kind) {
            c.EVENT_FSRV_TERMINATED, c.EVENT_FSRV_PREROLL => {},
            c.EVENT_FSRV_APROTO => {
                set_tblstr(ctx, "kind", "proto_change", top);
                set_tblbool(ctx, "cm", (fsrv_ev.unnamed_0.unnamed_2.aproto & c.SHMIF_META_CM) > 0, top);
                set_tblbool(ctx, "hdr", (fsrv_ev.unnamed_0.unnamed_2.aproto & c.SHMIF_META_HDR) > 0, top);
                set_tblbool(ctx, "vr", (fsrv_ev.unnamed_0.unnamed_2.aproto & c.SHMIF_META_VR) > 0, top);
            },
            c.EVENT_FSRV_GAMMARAMP => {
                set_tblstr(ctx, "kind", "ramp_update", top);
                set_tblnum(ctx, "index", @floatFromInt(fsrv_ev.unnamed_0.unnamed_0.counter), top);
            },
            c.EVENT_FSRV_DELIVEREDFRAME => {
                set_tblstr(ctx, "kind", "frame", top);
                set_tblnum(ctx, "pts", @floatFromInt(fsrv_ev.unnamed_0.unnamed_0.pts), top);
                set_tblnum(ctx, "number", @floatFromInt(fsrv_ev.unnamed_0.unnamed_0.counter), top);
                set_tblnum(ctx, "x", @floatFromInt(fsrv_ev.unnamed_0.unnamed_0.xofs), top);
                set_tblnum(ctx, "y", @floatFromInt(fsrv_ev.unnamed_0.unnamed_0.yofs), top);
                set_tblnum(ctx, "width", @floatFromInt(fsrv_ev.unnamed_0.unnamed_0.width), top);
                set_tblnum(ctx, "height", @floatFromInt(fsrv_ev.unnamed_0.unnamed_0.height), top);

                if (fsrv_helper_get_desc_region_valid(fsrv)) {
                    var rx1: i16 = 0;
                    var ry1: i16 = 0;
                    var rx2: i16 = 0;
                    var ry2: i16 = 0;
                    fsrv_helper_get_desc_region(fsrv, &rx1, &ry1, &rx2, &ry2);
                    if (fsrv_helper_get_desc_hints(fsrv) & c.SHMIF_RHINT_TPACK != 0) {
                        const dy = ry2 - ry1;
                        const dx = rx2 - rx1;
                        const cellw: i16 = @intCast(fsrv_helper_get_desc_text_cellw(fsrv));
                        const cellh: i16 = @intCast(fsrv_helper_get_desc_text_cellh(fsrv));
                        set_tblnum(ctx, "x", @floatFromInt(@divTrunc(rx1, cellw)), top);
                        set_tblnum(ctx, "y", @floatFromInt(@divTrunc(ry1, cellh)), top);
                        set_tblnum(ctx, "rows", @floatFromInt(@divTrunc(dy, cellh)), top);
                        set_tblnum(ctx, "cols", @floatFromInt(@divTrunc(dx, cellw)), top);
                    } else {
                        set_tblnum(ctx, "x1", @floatFromInt(rx1), top);
                        set_tblnum(ctx, "y1", @floatFromInt(ry1), top);
                        set_tblnum(ctx, "x2", @floatFromInt(rx2), top);
                        set_tblnum(ctx, "y2", @floatFromInt(ry2), top);
                    }
                }

                if (fsrv_helper_get_desc_aext_hdr(fsrv) != null) {
                    const m = vobj.*.vstore.*.hdr.drm;
                    set_tblnum(ctx, "fll", @as(f64, @floatCast(m.fll)), top);
                    set_tblnum(ctx, "cll", @as(f64, @floatCast(m.cll)), top);
                    set_tblnum(ctx, "master_min_nits", @as(f64, @floatCast(m.master_min)), top);
                    set_tblnum(ctx, "master_max_nits", @as(f64, @floatCast(m.master_max)), top);
                    set_tblnum(ctx, "whitepoint_x", @as(f64, @floatCast(m.wpx)), top);
                    set_tblnum(ctx, "whitepoint_y", @as(f64, @floatCast(m.wpy)), top);
                    set_tblnum(ctx, "red_x", @as(f64, @floatCast(m.rx)), top);
                    set_tblnum(ctx, "red_y", @as(f64, @floatCast(m.ry)), top);
                    set_tblnum(ctx, "green_x", @as(f64, @floatCast(m.gx)), top);
                    set_tblnum(ctx, "green_y", @as(f64, @floatCast(m.gy)), top);
                    set_tblnum(ctx, "blue_x", @as(f64, @floatCast(m.bx)), top);
                    set_tblnum(ctx, "blue_y", @as(f64, @floatCast(m.by)), top);
                    set_tblstr(ctx, "eotf", eotfstr(m.eotf), top);
                }
            },
            c.EVENT_FSRV_IONESTED => {
                set_tblstr(ctx, "kind", "input", top);
                set_tblnum(ctx, "tgtid", @floatFromInt(fsrv_ev.unnamed_0.input.dst), top);
                append_iotable(ctx, &fsrv_ev.unnamed_0.input);
                argc = 3;
            },
            c.EVENT_FSRV_DROPPEDFRAME => {
                set_tblstr(ctx, "kind", "dropped_frame", top);
                set_tblnum(ctx, "pts", @floatFromInt(fsrv_ev.unnamed_0.unnamed_0.pts), top);
                set_tblnum(ctx, "number", @floatFromInt(fsrv_ev.unnamed_0.unnamed_0.counter), top);
            },
            c.EVENT_FSRV_EXTCONN => {
                set_tblstr(ctx, "kind", "connected", top);
                slim_utf8_push(&msgbuf, @intCast(fsrv_ev.unnamed_0.unnamed_1.ident.len),
                    @ptrCast(@constCast(&fsrv_ev.unnamed_0.unnamed_1.ident)));
                set_tblstr(ctx, "key", &msgbuf, top);
                luactx.pending_socket_label = c.strdup(&msgbuf);
                luactx.pending_socket_descr = @intCast(fsrv_ev.unnamed_0.unnamed_1.descriptor);
                adopt_check = true;
            },
            c.EVENT_FSRV_RESIZED => {
                set_tblstr(ctx, "kind", "resized", top);
                set_tblnum(ctx, "width", @floatFromInt(fsrv_ev.unnamed_0.unnamed_0.width), top);
                set_tblnum(ctx, "height", @floatFromInt(fsrv_ev.unnamed_0.unnamed_0.height), top);

                // mirrored is incorrect but can't drop it for legacy reasons
                set_tblbool(ctx, "mirrored", (fsrv_ev.unnamed_0.unnamed_0.fmt_fl & @as(i8, @intCast(c.SHMIF_RHINT_ORIGO_LL))) != 0, top);
                set_tblbool(ctx, "origo_ll", (fsrv_ev.unnamed_0.unnamed_0.fmt_fl & @as(i8, @intCast(c.SHMIF_RHINT_ORIGO_LL))) != 0, top);
                set_tblbool(ctx, "tpack", (fsrv_ev.unnamed_0.unnamed_0.fmt_fl & @as(i8, @truncate(c.SHMIF_RHINT_TPACK))) != 0, top);
            },
            else => {},
        }

        c.alt_call(ctx, c.CB_SOURCE_FRAMESERVER, @as(u64, @intCast(c.EP_TRIGGER_FRAMESERVER)),
            @bitCast(fsrv_ev.video), argc, 0, "frameserver:event");
    } else if (category == c.EVENT_VIDEO) {
        const vid = &ev.*.unnamed_0.unnamed_0.unnamed_0.vid;

        if (vid.kind == c.EVENT_VIDEO_DISPLAY_ADDED) {
            display_added(ctx, ev);
            return true;
        } else if (vid.kind == c.EVENT_VIDEO_DISPLAY_RESET) {
            display_reset(ctx, ev);
            return true;
        } else if (vid.kind == c.EVENT_VIDEO_DISPLAY_REMOVED) {
            display_removed(ctx, ev);
            return true;
        } else if (vid.kind == c.EVENT_VIDEO_DISPLAY_CHANGED) {
            display_changed(ctx, ev);
            return true;
        }

        // terminating conditions: no callback or source vid broken
        const dst_cb = vid.data;
        const srcobj = c.arcan_video_getobject(vid.source);
        if (0 == dst_cb or srcobj == null)
            return true;

        var evmsg: [*c]const u8 = "video_event";

        // add placeholder, if we find an asynch recipient
        c.lua_pushnumber(ctx, 0);

        lua_pushvid(ctx, vid.source);
        c.lua_createtable(ctx, 0, 0);
        const top = c.lua_gettop(ctx);
        var source: c_int = c.CB_SOURCE_NONE;

        switch (vid.kind) {
            c.EVENT_VIDEO_EXPIRE => {
                // not even likely that these get forwarded here
            },
            c.EVENT_VIDEO_CHAIN_OVER => {
                evmsg = "video_event(chain_tag reached), callback";
                source = c.CB_SOURCE_TRANSFORM;
            },
            // In C, ASYNCHIMAGE_LOADED uses if(0) trick to fall through to FAILED's tail.
            // We handle both separately, duplicating the shared tail.
            c.EVENT_VIDEO_ASYNCHIMAGE_LOADED => {
                evmsg = "video_event(asynchimg_loaded), callback";
                source = c.CB_SOURCE_IMAGE;
                set_tblstr(ctx, "kind", "loaded", top);
                if (srcobj != null and srcobj.*.vstore.*.vinf.text.unnamed_0.source != null)
                    set_tblstr(ctx, "resource", srcobj.*.vstore.*.vinf.text.unnamed_0.source, top)
                else
                    set_tblstr(ctx, "resource", "unknown", top);
                set_tblnum(ctx, "width", @floatFromInt(vid.unnamed_0.unnamed_0.width), top);
                set_tblnum(ctx, "height", @floatFromInt(vid.unnamed_0.unnamed_0.height), top);
            },
            c.EVENT_VIDEO_ASYNCHIMAGE_FAILED => {
                source = c.CB_SOURCE_IMAGE;
                evmsg = "video_event(asynchimg_load_fail), callback";
                set_tblstr(ctx, "kind", "load_failed", top);
                if (srcobj != null and srcobj.*.vstore.*.vinf.text.unnamed_0.source != null)
                    set_tblstr(ctx, "resource", srcobj.*.vstore.*.vinf.text.unnamed_0.source, top)
                else
                    set_tblstr(ctx, "resource", "unknown", top);
                set_tblnum(ctx, "width", @floatFromInt(vid.unnamed_0.unnamed_0.width), top);
                set_tblnum(ctx, "height", @floatFromInt(vid.unnamed_0.unnamed_0.height), top);
            },
            else => {
                c.arcan_warning("Engine -> Script Warning: arcan_lua_pushevent()," ++
                    "\tunknown video event (%i)\n", @as(c_int, @intCast(vid.kind)));
            },
        }

        if (source != c.CB_SOURCE_NONE) {
            _ = c.lua_rawgeti(ctx, c.LUA_REGISTRYINDEX, @intCast(dst_cb));
            c.lua_replace(ctx, 1);
            c.alt_call(ctx, source,
                @as(u64, @intCast(c.EP_TRIGGER_IMAGE)), @bitCast(vid.source), 2, 0, evmsg);
        } else {
            c.lua_settop(ctx, 0);
        }

        if (adopt_check) {
            if (luactx.pending_socket_label != null) {
                c.arcan_mem_free(@ptrCast(luactx.pending_socket_label));
                _ = c.close(luactx.pending_socket_descr);
                luactx.pending_socket_descr = -1;
                luactx.pending_socket_label = null;
            }
        }
    } else if (category == c.EVENT_AUDIO) {
        const aud = &ev.*.unnamed_0.unnamed_0.unnamed_0.aud;
        if (aud.kind == c.EVENT_AUDIO_PLAYBACK_FINISHED and
            aud.unnamed_0.otag != c.LUA_NOREF)
        {
            _ = c.lua_rawgeti(ctx, c.LUA_REGISTRYINDEX, @truncate(aud.unnamed_0.otag));
            c.alt_call(ctx, c.CB_SOURCE_NONE,
                @as(u64, @intCast(c.EP_TRIGGER_AUDIO)), 0, 0, 0, "audio:finished");
            c.luaL_unref(ctx, c.LUA_REGISTRYINDEX, @truncate(aud.unnamed_0.otag));
        }
    }
    return true;
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part6.zig
// ══════════════════════════════════════════════════════════════════════

// === Part 6: Video helpers, frameset, link, 3D models, image props, DB keys ===
//
// Ported from arcan_lua.c lines 5324-6452.
// LUA_TRACE/LUA_ETRACE removed per porting rules.



// External symbols


const DEFAULT_USERMASK: c_uint = @bitCast(((c.RESOURCE_APPL | c.RESOURCE_APPL_SHARED) | c.RESOURCE_APPL_TEMP) | c.RESOURCE_NS_USER);

const EPSILON: f32 = 0.0000009999999974752427;

// Helper for accessing the unnamed position/scale fields
// surface_properties -> position (point/vector) -> unnamed_0 -> unnamed_0 -> x,y,z
// surface_properties -> scale    (scalefactor)  -> unnamed_0 -> unnamed_0 -> x,y,z

// ============================================================================
// image_parent (C:5324)
// ============================================================================
fn imageparent(ctx: ?*c.lua_State) callconv(.c) c_int {
    var srcobj: [*c]c.arcan_vobject = undefined;
    const id = luaL_checkvid(ctx, 1, &srcobj);
    const ref = c.luavid_tovid(c.luaL_optnumber(ctx, 2, @floatFromInt(c.ARCAN_EID)));
    const pid = c.arcan_video_findparent(id, ref);

    lua_pushvid(ctx, pid);
    lua_pushvid(ctx, if (srcobj.*.owner != null)
        srcobj.*.owner.*.color.*.cellid
    else
        c.ARCAN_VIDEO_WORLDID);
    return 2;
}

// ============================================================================
// video_synchronization (C:5338)
// ============================================================================
fn videosynch(ctx: ?*c.lua_State) callconv(.c) c_int {
    const newstrat = c.luaL_optlstring(ctx, 1, null, null);

    if (newstrat == null) {
        const opts = c.arcan_conductor_synchopts();
        c.lua_createtable(ctx, 0, 0);
        const top = c.lua_gettop(ctx);
        var count: usize = 0;

        // platform definition requires opts to be [k,d, ... ,NULL,NULL]
        while (opts[count * 2] != null) {
            c.lua_pushnumber(ctx, @floatFromInt(count + 1));
            c.lua_pushstring(ctx, opts[count * 2]);
            c.lua_rawset(ctx, top);
            c.lua_pushstring(ctx, opts[count * 2]);
            c.lua_pushstring(ctx, opts[count * 2 + 1]);
            c.lua_rawset(ctx, top);
            count += 1;
        }

        return 1;
    } else {
        c.arcan_conductor_setsynch(newstrat);
    }

    return 0;
}

// ============================================================================
// valid_vid (C:5369)
// ============================================================================
fn validvid(ctx: ?*c.lua_State) callconv(.c) c_int {
    var res: arcan_vobj_id = @intFromFloat(c.luaL_optnumber(ctx, 1, @floatFromInt(c.ARCAN_EID)));

    if (res != c.ARCAN_EID and res != c.ARCAN_VIDEO_WORLDID)
        res -= @as(arcan_vobj_id, @intCast(lua_vid_base));

    if (res < 0 and res != c.ARCAN_VIDEO_WORLDID)
        res = c.ARCAN_EID;

    const typ: c_int = @intFromFloat(c.luaL_optnumber(ctx, 2, -1.0));
    if (typ != -1) {
        const vobj = c.arcan_video_getobject(res);
        // In LWA mode, WORLDID with ARCAN_TAG_FRAMESERV type check returns true
        if (typ == c.ARCAN_TAG_FRAMESERV and res == c.ARCAN_VIDEO_WORLDID and c.platform_is_lwa_mode()) {
            c.lua_pushboolean(ctx, 1);
            return 1;
        }
        c.lua_pushboolean(ctx, @intFromBool(vobj != null and vobj.*.feed.state.tag == typ));
    } else {
        c.lua_pushboolean(ctx, @intFromBool(c.arcan_video_getobject(res) != null));
    }

    return 1;
}

// ============================================================================
// image_children (C:5397)
// ============================================================================
fn imagechildren(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const cid = c.luavid_tovid(c.luaL_optnumber(ctx, 2, @floatFromInt(c.ARCAN_EID)));

    if (cid != c.ARCAN_EID) {
        c.lua_pushboolean(ctx, @intFromBool(c.arcan_video_isdescendant(id, cid, -1)));
        return 1;
    }

    var child: arcan_vobj_id = undefined;
    var ofs: c_uint = 0;
    var count: c_uint = 1;

    c.lua_createtable(ctx, 0, 0);
    const top = c.lua_gettop(ctx);

    while (true) {
        child = c.arcan_video_findchild(id, ofs);
        ofs += 1;
        if (child == c.ARCAN_EID) break;
        c.lua_pushnumber(ctx, @floatFromInt(count));
        count += 1;
        lua_pushvid(ctx, child);
        c.lua_rawset(ctx, top);
    }

    return 1;
}

// ============================================================================
// image_framesetsize (C:5423)
// ============================================================================
fn framesetalloc(ctx: ?*c.lua_State) callconv(.c) c_int {
    const sid = luaL_checkvid(ctx, 1, null);
    const num: c_uint = @bitCast(luaL_checkint(ctx, 2));
    const mode: c_uint = @bitCast(luaL_optint(ctx, 3, c.ARCAN_FRAMESET_SPLIT));

    if (num < 256) {
        _ = c.arcan_video_allocframes(sid, @truncate(num), mode);
    } else {
        c.arcan_fatal("frameset_alloc() frameset limit (256) exceeded\n");
    }

    return 0;
}

// ============================================================================
// image_framecyclemode (C:5439)
// ============================================================================
fn framesetcycle(ctx: ?*c.lua_State) callconv(.c) c_int {
    const sid = luaL_checkvid(ctx, 1, null);
    const num: c_uint = @bitCast(luaL_optint(ctx, 2, 0));
    _ = c.arcan_video_framecyclemode(sid, @bitCast(num));
    return 0;
}

// ============================================================================
// image_pushasynch (C:5448)
// ============================================================================
fn pushasynch(ctx: ?*c.lua_State) callconv(.c) c_int {
    const sid = luaL_checkvid(ctx, 1, null);
    _ = c.arcan_video_pushasynch(sid);
    return 0;
}

// ============================================================================
// image_active_frame (C:5456)
// ============================================================================
fn activeframe(ctx: ?*c.lua_State) callconv(.c) c_int {
    const sid = luaL_checkvid(ctx, 1, null);
    const num: c_uint = @bitCast(luaL_checkint(ctx, 2));
    _ = c.arcan_video_setactiveframe(sid, num);
    return 0;
}

// ============================================================================
// image_origo_offset (C:5466)
// ============================================================================
fn origoofs(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const sid = luaL_checkvid(ctx, 1, &vobj);
    const xv: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    const yv: f32 = @floatCast(c.luaL_checknumber(ctx, 3));
    const zv: f32 = @floatCast(c.luaL_optnumber(ctx, 4, 0.0));
    const apoint: c_int = @intFromFloat(c.luaL_optnumber(ctx, 5, @as(f64, @floatFromInt(c.ANCHORP_UL))));

    _ = c.arcan_video_origoshift(sid, xv, yv, zv, @bitCast(apoint));
    return 0;
}

// ============================================================================
// mesh_ud struct (C:5481)
// ============================================================================
const mesh_ud = if (is_freestanding) extern struct {
    mesh: [*c]c.agp_mesh_store = @ptrFromInt(0),
    vobj: [*c]c.arcan_vobject = @ptrFromInt(0),
} else extern struct {
    mesh: [*c]c.agp_mesh_store = std.mem.zeroes([*c]c.agp_mesh_store),
    vobj: [*c]c.arcan_vobject = std.mem.zeroes([*c]c.arcan_vobject),
};

// ============================================================================
// image_tesselation (C:5486)
// ============================================================================
fn imagetess(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const sid = luaL_checkvid(ctx, 1, &vobj);
    const arg1 = c.lua_type(ctx, 2);
    var s: usize = 0;
    var t: usize = 0;
    var depth: bool = true;

    // either num, num, fun or fun - anything else is terminal
    if (arg1 == c.LUA_TNUMBER) {
        s = @intFromFloat(c.luaL_checknumber(ctx, 2));
        t = @intFromFloat(c.luaL_checknumber(ctx, 3));
        depth = luaL_optbnumber(ctx, 4, true);
        if (s > @as(usize, @intCast(MAX_SURFACEW)) or
            t > @as(usize, @intCast(MAX_SURFACEH)))
            c.arcan_fatal("image_tesselation(vid,s,t) illegal s or t value");
    } else if (arg1 != c.LUA_TFUNCTION) {
        c.arcan_fatal("image_tesselation(vid,num,num,*fun*) or (vid, *fun*)");
    } else if (c.lua_iscfunction(ctx, 2) != 0) {
        c.arcan_fatal("image_tesselation(fun), fun must be valid lua- function");
    }

    const ref = find_lua_callback(ctx);

    // user want access?
    var ms: [*c]c.agp_mesh_store = undefined;
    if (@as(isize, @intCast(c.LUA_NOREF)) == ref) {
        _ = c.arcan_video_defineshape(sid, s, t, &ms, depth);
        c.lua_pushboolean(ctx, @intFromBool((ms != null and ms.*.verts != null) or s == 1 or t == 1));
    } else {
        _ = c.arcan_video_defineshape(sid, s, t, &ms, depth);
        c.lua_pushboolean(ctx, @intFromBool((ms != null and ms.*.verts != null) or s == 1 or t == 1));
        // invoke callback for ms, when finished, empty the userdata store
        if (ms != null and ms.*.verts != null) {
            _ = c.lua_rawgeti(ctx, c.LUA_REGISTRYINDEX, @as(c_int, @truncate(ref)));
            const ud: *mesh_ud = @ptrCast(@alignCast(c.lua_newuserdata(ctx, @sizeOf(mesh_ud))));
            ud.* = std.mem.zeroes(mesh_ud);
            _ = c.lua_getfield(ctx, c.LUA_REGISTRYINDEX, "meshAccess");
            _ = c.lua_setmetatable(ctx, -2);
            c.lua_pushnumber(ctx, @floatFromInt(ms.*.n_vertices));
            c.lua_pushnumber(ctx, @floatFromInt(ms.*.vertex_size));
            ud.mesh = ms;
            ud.vobj = vobj;
            c.alt_call(ctx, c.CB_SOURCE_NONE, @as(u64, @intCast(c.EP_TRIGGER_MESH)), 0, 3, 0, "tesselate_image");
            ud.mesh = null;
        }
    }

    return 1;
}

// ============================================================================
// image_inherit_order (C:5540)
// ============================================================================
fn orderinherit(ctx: ?*c.lua_State) callconv(.c) c_int {
    const origo = c.lua_toboolean(ctx, 2) != 0;

    // array of VIDs or single VID
    const argtype = c.lua_type(ctx, 1);
    if (argtype == c.LUA_TNUMBER) {
        const id = luaL_checkvid(ctx, 1, null);
        _ = c.arcan_video_inheritorder(id, origo);
    } else if (argtype == c.LUA_TTABLE) {
        const nelems: c_int = @intCast(c.lua_objlen(ctx, 1));

        var i: usize = 0;
        while (i < @as(usize, @intCast(nelems))) : (i += 1) {
            _ = c.lua_rawgeti(ctx, 1, @as(c_int, @intCast(i + 1)));
            const id = luaL_checkvid(ctx, -1, null);
            _ = c.arcan_video_inheritorder(id, origo);
            c.lua_settop(ctx, -1 - 1);
        }
    }

    return 0;
}

// ============================================================================
// set_image_as_frame (C:5565)
// ============================================================================
fn imageasframe(ctx: ?*c.lua_State) callconv(.c) c_int {
    const sid = luaL_checkvid(ctx, 1, null);
    const did = luaL_checkvid(ctx, 2, null);
    const num: c_uint = @bitCast(luaL_checkint(ctx, 3));

    const code = c.arcan_video_setasframe(sid, did, @as(usize, num));
    if (code != @as(c.arcan_errc, @intCast(c.ARCAN_OK))) {
        switch (code) {
            @as(c.arcan_errc, @intCast(c.ARCAN_ERRC_UNACCEPTED_STATE)) => {
                c.arcan_warning("set_image_as_frame() failed, source not connected to textured backing store.\n");
            },
            @as(c.arcan_errc, @intCast(c.ARCAN_ERRC_NO_SUCH_OBJECT)) => {},
            @as(c.arcan_errc, @intCast(c.ARCAN_ERRC_BAD_ARGUMENT)) => {
                c.arcan_warning("set_image_as_frame() failed, dest doesn't have enough frames.\n");
            },
            else => {
                c.arcan_fatal("set_image_as_frame() failed, unknown code: %d\n", @as(c_int, code));
            },
        }
    }

    return 0;
}

// ============================================================================
// link_image (C:5593)
// ============================================================================
fn linkimage(ctx: ?*c.lua_State) callconv(.c) c_int {
    const sid = luaL_checkvid(ctx, 1, null);
    const did = luaL_checkvid(ctx, 2, null);
    const ap: c_int = @intFromFloat(c.luaL_optnumber(ctx, 3, @as(f64, @floatFromInt(c.ANCHORP_UL))));

    if (ap > c.ANCHORP_ENDM)
        c.arcan_fatal("link_image() -- invalid anchor point specified (%d)\n", ap);

    const sp: c_int = @intFromFloat(c.luaL_optnumber(ctx, 4, @as(f64, @floatFromInt(c.SCALEM_NONE))));
    if (sp > c.SCALEM_ENDM)
        c.arcan_fatal("link_image() -- invalid scale bias dimension (%d)\n", sp);

    var smask = c.arcan_video_getmask(sid);
    smask |= @as(c_uint, @bitCast(c.MASK_LIVING));

    const rv = c.arcan_video_linkobjs(sid, did, smask, @bitCast(ap), @bitCast(sp));
    c.lua_pushboolean(ctx, @intFromBool(rv == c.ARCAN_OK));
    return 1;
}

// ============================================================================
// relink_image (C:5615)
// ============================================================================
fn relinkimage(ctx: ?*c.lua_State) callconv(.c) c_int {
    const sid = luaL_checkvid(ctx, 1, null);
    const did = luaL_checkvid(ctx, 2, null);
    const ap: c_int = @intFromFloat(c.luaL_optnumber(ctx, 3, @as(f64, @floatFromInt(c.ANCHORP_UL))));

    if (ap > c.ANCHORP_ENDM)
        c.arcan_fatal("link_image() -- invalid anchor point specified (%d)\n", ap);

    const sp: c_int = @intFromFloat(c.luaL_optnumber(ctx, 4, @as(f64, @floatFromInt(c.SCALEM_NONE))));
    if (sp > c.SCALEM_ENDM)
        c.arcan_fatal("link_image() -- invalid scale bias dimension (%d)\n", sp);

    var smask = c.arcan_video_getmask(sid);
    smask |= @as(c_uint, @bitCast(c.MASK_LIVING));

    // resolve to world-space
    var pprop: c.surface_properties = std.mem.zeroes(c.surface_properties);
    if (did != c.ARCAN_EID and did != c.ARCAN_VIDEO_WORLDID) {
        pprop = c.arcan_video_resolve_properties(did);
    }
    const sprop = c.arcan_video_resolve_properties(sid);

    // will also reset transforms
    const rv = c.arcan_video_linkobjs(sid, did, smask, @bitCast(@as(c_int, c.ANCHORP_UL)), @bitCast(sp));

    // if the re-linking suceeded, we can apply the world-space delta
    if (rv == c.ARCAN_OK) {
        var new_x: f32 = sprop.position.unnamed_0.unnamed_0.x - pprop.position.unnamed_0.unnamed_0.x;
        var new_y: f32 = sprop.position.unnamed_0.unnamed_0.y - pprop.position.unnamed_0.unnamed_0.y;
        var new_z: f32 = sprop.position.unnamed_0.unnamed_0.z - pprop.position.unnamed_0.unnamed_0.z;

        // if the anchor point is different, resolve local anchor delta
        if (ap != c.ANCHORP_UL) {
            _ = c.arcan_video_objectmove(sid, 0, 0, 0, 0);
            const base = c.arcan_video_resolve_properties(sid);
            _ = c.arcan_video_linkobjs(sid, did, smask, @bitCast(ap), @bitCast(sp));
            const anchor = c.arcan_video_resolve_properties(sid);
            new_x -= anchor.position.unnamed_0.unnamed_0.x - base.position.unnamed_0.unnamed_0.x;
            new_y -= anchor.position.unnamed_0.unnamed_0.y - base.position.unnamed_0.unnamed_0.y;
            new_z -= anchor.position.unnamed_0.unnamed_0.z - base.position.unnamed_0.unnamed_0.z;
        }

        _ = c.arcan_video_objectmove(sid, new_x, new_y, new_z, 0);
    }

    c.lua_pushboolean(ctx, @intFromBool(rv == c.ARCAN_OK));
    return 1;
}

// ============================================================================
// pushprop helper (C:5669) — push surface_properties as Lua table
// ============================================================================
fn pushprop(ctx: ?*c.lua_State, prop: c.surface_properties, zv: c_ushort) c_int {
    c.lua_createtable(ctx, 0, 11);

    c.lua_pushliteral(ctx, "x");
    c.lua_pushnumber(ctx, @floatCast(prop.position.unnamed_0.unnamed_0.x));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "y");
    c.lua_pushnumber(ctx, @floatCast(prop.position.unnamed_0.unnamed_0.y));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "z");
    c.lua_pushnumber(ctx, @floatCast(prop.position.unnamed_0.unnamed_0.z));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "width");
    c.lua_pushnumber(ctx, @floatCast(prop.scale.unnamed_0.unnamed_0.x));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "height");
    c.lua_pushnumber(ctx, @floatCast(prop.scale.unnamed_0.unnamed_0.y));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "depth");
    c.lua_pushnumber(ctx, @floatCast(prop.scale.unnamed_0.unnamed_0.z));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "angle");
    c.lua_pushnumber(ctx, @floatCast(prop.rotation.roll));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "roll");
    c.lua_pushnumber(ctx, @floatCast(prop.rotation.roll));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "pitch");
    c.lua_pushnumber(ctx, @floatCast(prop.rotation.pitch));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "yaw");
    c.lua_pushnumber(ctx, @floatCast(prop.rotation.yaw));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "opacity");
    c.lua_pushnumber(ctx, @floatCast(prop.opa));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "order");
    c.lua_pushnumber(ctx, @floatFromInt(zv));
    c.lua_rawset(ctx, -3);

    return 1;
}

// ============================================================================
// scale_3dvertices (C:5725)
// ============================================================================
fn scale3dverts(ctx: ?*c.lua_State) callconv(.c) c_int {
    const vid = luaL_checkvid(ctx, 1, null);
    _ = c.arcan_3d_scalevertices(vid);
    return 0;
}

// ============================================================================
// rawmesh helper (C:5783) — called from loadmesh when arg2 is table
// ============================================================================
fn rawmesh(ctx: ?*c.lua_State, did: arcan_vobj_id, nmaps: c_int) c_int {
    const labels = [6][*c]const u8{
        "normals", "txcos", "txcos_2", "tangents", "colors", "weights",
    };
    const factors = [6]usize{ 3, 2, 2, 4, 4, 0 };
    var targets: [6][*c]f32 = .{ null, null, null, null, null, null };
    var sizes: [6]usize = .{ 0, 0, 0, 0, 0, 0 };
    var n_vertices: usize = 0;
    var n_indices: usize = 0;
    var vertices: [*c]f32 = null;
    var bones_u: [*c]c_uint = null;
    var indices: [*c]c_uint = null;

    const rv: c_int = blk: {
        // vertices
        _ = c.lua_getfield(ctx, 2, "vertices");
        if (c.lua_type(ctx, -1) != c.LUA_TTABLE)
            c.arcan_fatal("add_3dmesh(), required field 'vertices' missing");

        if (!stack_to_farray(ctx, c.ARCAN_MEM_MODELDATA, &vertices, &n_vertices, 0)) {
            c.lua_settop(ctx, -1 - 1);
            break :blk 0;
        }
        if (n_vertices == 0 or n_vertices % 3 != 0)
            c.arcan_fatal("add_3dmesh(), invalid number of elements (%%3=0) in vertices");

        n_vertices /= 3;

        // indices
        _ = c.lua_getfield(ctx, 2, "indices");
        if (c.lua_type(ctx, -1) == c.LUA_TTABLE) {
            if (!stack_to_uiarray(ctx, c.ARCAN_MEM_MODELDATA, &indices, &n_indices, 0)) {
                c.arcan_warning("add_3dmesh(), couldn't unpack indices");
                c.lua_settop(ctx, -1 - 1);
                break :blk 0;
            }
        }
        c.lua_settop(ctx, -1 - 1);

        // bones — hardcoded limit, repack
        _ = c.lua_getfield(ctx, 2, "bones");
        if (c.lua_type(ctx, -1) == c.LUA_TTABLE) {
            var n_bones: usize = 0;
            if (stack_to_uiarray(ctx, c.ARCAN_MEM_MODELDATA, &bones_u, &n_bones, n_vertices * 4)) {
                // repack first 4 into u16
                const bones_us: [*c]u16 = @ptrCast(@alignCast(bones_u));
                var tmp: [4]u16 = .{
                    @truncate(bones_u[0]),
                    @truncate(bones_u[1]),
                    @truncate(bones_u[2]),
                    @truncate(bones_u[3]),
                };
                _ = c.memcpy(@ptrCast(bones_us), @ptrCast(&tmp), @sizeOf(u16) * 4);
            }
        }

        // optional float arrays
        for (0..6) |i| {
            _ = c.lua_getfield(ctx, 2, labels[i]);
            if (c.lua_type(ctx, -1) == c.LUA_TTABLE) {
                if (!stack_to_farray(ctx, c.ARCAN_MEM_MODELDATA, &targets[i], &sizes[i], factors[i])) {
                    c.arcan_warning("add_3dmesh(), couldn't unpack field");
                    c.lua_settop(ctx, -1 - 1);
                    break :blk 0;
                }
            }
            c.lua_settop(ctx, -1 - 1);
        }

        const bones_us: [*c]u16 = @ptrCast(@alignCast(bones_u));
        if (c.ARCAN_OK == c.arcan_3d_addraw(
            did,
            vertices,
            n_vertices,
            indices,
            n_indices,
            targets[0],
            targets[1],
            targets[2],
            targets[3],
            targets[4],
            bones_us,
            targets[5],
            @bitCast(nmaps),
        )) {
            c.lua_pushboolean(ctx, 1);
            return 1;
        }

        break :blk 0;
    };

    if (rv == 0) {
        // fail path: free all allocated arrays
        for (0..6) |i| {
            c.arcan_mem_free(@ptrCast(targets[i]));
        }
        c.arcan_mem_free(@ptrCast(bones_u));
        c.arcan_mem_free(@ptrCast(indices));
        c.arcan_mem_free(@ptrCast(vertices));
        c.lua_pushboolean(ctx, 0);
    }
    return 1;
}

// ============================================================================
// add_3dmesh (C:5867)
// ============================================================================
fn loadmesh(ctx: ?*c.lua_State) callconv(.c) c_int {
    const did = luaL_checkvid(ctx, 1, null);
    const nmaps: c_int = @intCast(@abs(@as(i32, @intFromFloat(c.luaL_optnumber(ctx, 3, 1.0)))));

    if (c.lua_type(ctx, 2) == c.LUA_TTABLE)
        return rawmesh(ctx, did, nmaps);
    if (c.lua_type(ctx, 2) != c.LUA_TSTRING)
        c.arcan_fatal("add_3dmesh(), invalid resource type");

    const path = findresource(
        c.luaL_checklstring(ctx, 2, null),
        DEFAULT_USERMASK,
        @bitCast(c.ARES_FILE | c.ARES_RDONLY),
        null,
    );

    var indata = c.arcan_open_resource(path);
    if (indata.fd != c.BADFD) {
        const rv = c.arcan_3d_addmesh(did, indata, @bitCast(nmaps));
        if (rv != c.ARCAN_OK)
            c.arcan_warning("loadmesh() -- Couldn't add mesh\n");
        c.arcan_release_resource(&indata);
        c.lua_pushboolean(ctx, 0);
    } else {
        c.lua_pushboolean(ctx, 1);
    }
    c.arcan_mem_free(@ptrCast(path));

    return 1;
}

// ============================================================================
// attrtag_model (C:5897)
// ============================================================================
fn attrtag(ctx: ?*c.lua_State) callconv(.c) c_int {
    const did = luaL_checkvid(ctx, 1, null);
    const attr = c.luaL_checklstring(ctx, 2, null);
    const state = luaL_checkbnumber(ctx, 3);

    if (c.strcmp(attr, "infinite") == 0) {
        c.lua_pushboolean(ctx, @intFromBool(c.arcan_3d_infinitemodel(did, state) != c.ARCAN_OK));
    } else {
        c.lua_pushboolean(ctx, 0);
    }

    return 1;
}

// ============================================================================
// new_3dmodel (C:5914)
// ============================================================================
fn buildmodel(ctx: ?*c.lua_State) callconv(.c) c_int {
    var id: arcan_vobj_id = c.ARCAN_EID;
    id = c.arcan_3d_emptymodel();

    if (id != c.ARCAN_EID)
        _ = c.arcan_video_objectopacity(id, 0, 0);

    lua_pushvid(ctx, id);
    trace_allocation(ctx, "new_3dmodel", id);
    return 1;
}

// ============================================================================
// finalize_3dmodel (C:5929)
// ============================================================================
fn finalmodel(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const rv = c.arcan_3d_finalizemodel(id);
    if (rv == c.ARCAN_ERRC_UNACCEPTED_STATE) {
        c.arcan_fatal("new_3dmodel(), specified vid\tis not connected to a 3d model.\n");
    }
    return 0;
}

// ============================================================================
// build_3dplane (C:5943)
// ============================================================================
fn buildplane(ctx: ?*c.lua_State) callconv(.c) c_int {
    const minx: f32 = @floatCast(c.luaL_checknumber(ctx, 1));
    const mind: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    const endx: f32 = @floatCast(c.luaL_checknumber(ctx, 3));
    const endd: f32 = @floatCast(c.luaL_checknumber(ctx, 4));
    const starty: f32 = @floatCast(c.luaL_checknumber(ctx, 5));
    const hdens: f32 = @floatCast(c.luaL_checknumber(ctx, 6));
    const ddens: f32 = @floatCast(c.luaL_checknumber(ctx, 7));
    const nmaps: c_int = @intCast(@abs(@as(i32, @intFromFloat(c.luaL_optnumber(ctx, 8, 1.0)))));
    const vert = luaL_optbnumber(ctx, 9, false);

    const id = c.arcan_3d_buildplane(
        minx,
        mind,
        endx,
        endd,
        starty,
        hdens,
        ddens,
        @intCast(nmaps),
        vert,
    );

    lua_pushvid(ctx, id);
    trace_allocation(ctx, "build_3dplane", id);
    return 1;
}

// ============================================================================
// build_3dbox (C:5966)
// ============================================================================
fn buildbox(ctx: ?*c.lua_State) callconv(.c) c_int {
    const width: f32 = @floatCast(c.luaL_checknumber(ctx, 1));
    const height: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    const depth: f32 = @floatCast(c.luaL_checknumber(ctx, 3));
    const nmaps: c_int = @intCast(@abs(@as(i32, @intFromFloat(c.luaL_optnumber(ctx, 4, 1.0)))));
    const split = luaL_optbnumber(ctx, 5, false);

    const id = c.arcan_3d_buildbox(width, height, depth, @intCast(nmaps), split);
    lua_pushvid(ctx, id);
    trace_allocation(ctx, "build_3dbox", id);
    return 1;
}

// ============================================================================
// build_pointcloud (C:5983)
// ============================================================================
fn pointcloud(ctx: ?*c.lua_State) callconv(.c) c_int {
    const count: f32 = @floatCast(c.luaL_checknumber(ctx, 1));
    const nmaps: c_int = @intCast(@abs(@as(i32, @intFromFloat(c.luaL_optnumber(ctx, 2, 1.0)))));

    const id = c.arcan_3d_pointcloud(@intFromFloat(count), @intCast(nmaps));
    lua_pushvid(ctx, id);
    trace_allocation(ctx, "build_pointcloud", id);
    return 1;
}

// ============================================================================
// build_cylinder (C:5996)
// ============================================================================
fn buildcylinder(ctx: ?*c.lua_State) callconv(.c) c_int {
    const radius: f32 = @floatCast(c.luaL_checknumber(ctx, 1));
    const halfh: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    const steps: usize = @intFromFloat(c.luaL_checknumber(ctx, 3));
    const nmaps: c_int = @intCast(@abs(@as(i32, @intFromFloat(c.luaL_optnumber(ctx, 4, 1.0)))));
    const caps = c.luaL_optlstring(ctx, 5, null, null);

    var capv: c_int = c.CYLINDER_FILL_FULL;
    if (caps != null and c.strcmp(caps, "caps") == 0) {
        capv = c.CYLINDER_FILL_FULL_CAPS;
    } else if (caps != null and c.strcmp(caps, "half") == 0) {
        capv = c.CYLINDER_FILL_HALF;
    } else if (caps != null and c.strcmp(caps, "halfcaps") == 0) {
        capv = c.CYLINDER_FILL_HALF_CAPS;
    }

    const id = c.arcan_3d_buildcylinder(radius, halfh, steps, @intCast(nmaps), capv);
    lua_pushvid(ctx, id);
    trace_allocation(ctx, "build_cylinder", id);
    return 1;
}

// ============================================================================
// build_sphere (C:6019)
// ============================================================================
fn buildsphere(ctx: ?*c.lua_State) callconv(.c) c_int {
    const radius: f32 = @floatCast(c.luaL_checknumber(ctx, 1));
    const lng: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    const lat: f32 = @floatCast(c.luaL_checknumber(ctx, 3));
    const nmaps: c_int = @intCast(@abs(@as(i32, @intFromFloat(c.luaL_optnumber(ctx, 4, 1.0)))));
    const hemi = luaL_optbnumber(ctx, 5, false);

    const id = c.arcan_3d_buildsphere(radius, @intFromFloat(lng), @intFromFloat(lat), hemi, @intCast(nmaps));
    lua_pushvid(ctx, id);
    trace_allocation(ctx, "build_sphere", id);
    return 1;
}

// ============================================================================
// swizzle_model (C:6033)
// ============================================================================
fn swizzlemodel(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const rv = c.arcan_3d_swizzlemodel(id);
    c.lua_pushboolean(ctx, @intFromBool(rv == c.ARCAN_OK));
    return 1;
}

// ============================================================================
// camtag_model (C:6044)
// ============================================================================
fn camtag(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);

    // second form: update a camera with a different projection
    if (c.lua_type(ctx, 2) == c.LUA_TTABLE) {
        var proj: [16]f32 = undefined;
        const nvals: c_int = @intCast(c.lua_objlen(ctx, -1));
        if (nvals != 16) {
            c.lua_pushboolean(ctx, 0);
            return 1;
        } else {
            for (0..16) |i| {
                _ = c.lua_rawgeti(ctx, 2, @as(c_int, @intCast(i + 1)));
                proj[i] = @floatCast(c.lua_tonumber(ctx, -1));
                c.lua_settop(ctx, -1 - 1);
            }
            c.lua_pushboolean(ctx, @intFromBool(c.arcan_3d_camproj(id, &proj) == c.ARCAN_OK));
        }
        return 1;
    }

    const mode = c.platform_video_dimensions();
    const w: f32 = @floatFromInt(mode.width);
    const h: f32 = @floatFromInt(mode.height);

    var ar: f32 = if (w / h > 1.0) w / h else h / w;

    const nv: f32 = @floatCast(c.luaL_optnumber(ctx, 2, 0.1));
    const fv: f32 = @floatCast(c.luaL_optnumber(ctx, 3, 100.0));
    const fov: f32 = @floatCast(c.luaL_optnumber(ctx, 4, 45.0));
    ar = @floatCast(c.luaL_optnumber(ctx, 5, @as(f64, @floatCast(ar))));
    const front = luaL_optbnumber(ctx, 6, true);
    const back = luaL_optbnumber(ctx, 7, false);
    var linew: f32 = @floatCast(c.luaL_optnumber(ctx, 8, 0.0));

    var flags: c_uint = 0;
    if (linew > EPSILON) {
        flags |= @bitCast(c.MESH_FILL_LINE);
    } else {
        linew = 1.0;
    }

    var dst: arcan_vobj_id = c.ARCAN_EID;
    if (c.lua_type(ctx, 9) == c.LUA_TNUMBER) {
        var vobj: [*c]c.arcan_vobject = undefined;
        dst = luaL_checkvid(ctx, 9, &vobj);
        if (c.arcan_vint_findrt(vobj) == null)
            c.arcan_fatal("camtag_model(), referenced dst is not a rendertarget\n");
    }

    if (front)
        flags |= @bitCast(c.MESH_FACING_FRONT);
    if (back)
        flags |= @bitCast(c.MESH_FACING_BACK);

    const rv = c.arcan_3d_camtag(dst, id, nv, fv, ar, fov, @bitCast(flags), @as(f64, @floatCast(linew)));
    c.lua_pushboolean(ctx, @intFromBool(rv == c.ARCAN_OK));
    return 1;
}

// ============================================================================
// image_surface_properties (C:6110)
// ============================================================================
fn getimageprop(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    var dt: c_longlong = @intFromFloat(c.luaL_optnumber(ctx, 2, 0.0));

    if (dt < 0)
        dt = std.math.maxInt(c_long);

    const prop = if (dt > 0)
        c.arcan_video_properties_at(id, @intCast(@as(u64, @bitCast(dt))))
    else
        c.arcan_video_current_properties(id);

    return pushprop(ctx, prop, c.arcan_video_getzv(id));
}

// ============================================================================
// image_surface_resolve_properties (C:6128)
// ============================================================================
fn getimageresolveprop(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const prop = c.arcan_video_resolve_properties(id);
    return pushprop(ctx, prop, c.arcan_video_getzv(id));
}

// ============================================================================
// image_surface_initial_properties (C:6138)
// ============================================================================
fn getimageinitprop(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const prop = c.arcan_video_initial_properties(id);
    return pushprop(ctx, prop, c.arcan_video_getzv(id));
}

// ============================================================================
// image_storage_properties (C:6149)
// ============================================================================
fn getimagestorageprop(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const id = luaL_checkvid(ctx, 1, &vobj);
    const cons = c.arcan_video_storage_properties(id);
    c.lua_createtable(ctx, 0, 3);

    c.lua_pushliteral(ctx, "bpp");
    c.lua_pushnumber(ctx, @floatFromInt(cons.bpp));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "height");
    c.lua_pushnumber(ctx, @floatFromInt(cons.h));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "width");
    c.lua_pushnumber(ctx, @floatFromInt(cons.w));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "refc");
    c.lua_pushnumber(ctx, @floatFromInt(vobj.*.vstore.*.refcount));
    c.lua_rawset(ctx, -3);

    c.lua_pushliteral(ctx, "type");
    switch (@as(c_int, @intCast(vobj.*.vstore.*.txmapped))) {
        c.TXSTATE_OFF => c.lua_pushliteral(ctx, "color"),
        c.TXSTATE_TEX2D => c.lua_pushliteral(ctx, "2d"),
        c.TXSTATE_DEPTH => c.lua_pushliteral(ctx, "depth"),
        c.TXSTATE_TEX3D => c.lua_pushliteral(ctx, "3d"),
        c.TXSTATE_CUBE => c.lua_pushliteral(ctx, "cube"),
        c.TXSTATE_TPACK => c.lua_pushliteral(ctx, "tpack"),
        else => {},
    }
    c.lua_rawset(ctx, -3);

    return 1;
}

// ============================================================================
// image_storage_slice (C:6200)
// ============================================================================
fn slicestore(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const id = luaL_checkvid(ctx, 1, &vobj);
    const typ: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));

    if (typ != c.ARCAN_CUBEMAP and typ != c.ARCAN_3DTEXTURE)
        c.arcan_fatal("image_storage_slice(), unknown slice type");

    c.luaL_checktype(ctx, 3, c.LUA_TTABLE);
    const values: usize = c.lua_objlen(ctx, 3);

    if (vobj.*.vstore.*.txmapped != c.TXSTATE_TEX2D)
        c.arcan_fatal("image_storage_slice(), destination store is not textured");

    // Use a bounded stack buffer instead of VLA
    var slices_buf: [256]arcan_vobj_id = undefined;
    if (values > 256)
        c.arcan_fatal("image_storage_slice(), too many slices (max 256)");

    for (0..values) |i| {
        _ = c.lua_rawgeti(ctx, 3, @as(c_int, @intCast(i + 1)));
        const setvid = c.luavid_tovid(c.lua_tonumber(ctx, -1));
        const svobj = c.arcan_video_getobject(setvid);
        if (svobj == null or svobj.*.vstore == null or svobj.*.vstore.*.txmapped != c.TXSTATE_TEX2D)
            c.arcan_fatal("image_storage_slice(), invalid slice source at index %zu", i + 1);
        slices_buf[i] = setvid;
        c.lua_settop(ctx, -1 - 1);
    }

    if (@as(c.arcan_errc, @intCast(c.ARCAN_OK)) == c.arcan_video_sliceobject(id, @intCast(typ), vobj.*.vstore.*.w, values) and
        @as(c.arcan_errc, @intCast(c.ARCAN_OK)) == c.arcan_video_updateslices(id, values, &slices_buf))
    {
        c.lua_pushboolean(ctx, 1);
    } else {
        c.lua_pushboolean(ctx, 0);
    }

    return 1;
}

// ============================================================================
// copy_surface_properties (C:6237)
// ============================================================================
fn copyimageprop(ctx: ?*c.lua_State) callconv(.c) c_int {
    const sid = luaL_checkvid(ctx, 1, null);
    const did = luaL_checkvid(ctx, 2, null);
    _ = c.arcan_video_copyprops(sid, did);
    return 0;
}

// ============================================================================
// validate_key helper (C:6248)
// ============================================================================
fn validate_key(key: [*c]const u8) bool {
    var k = key;
    while (k.* != 0) {
        const ch = k.*;
        if (!std.ascii.isAlphanumeric(ch) and ch != '_' and ch != '+' and ch != '/' and ch != '=')
            return false;
        k += 1;
    }
    return true;
}

// ============================================================================
// setup_transaction helper (C:6261)
// ============================================================================
fn setup_transaction(ctx: ?*c.lua_State, kvtgt: *c.DB_KVTARGET, ind: c_int) c.arcan_dbtrans_id {
    var tid: c.arcan_dbtrans_id = undefined;
    tid.applname = c.arcan_appl_id();
    kvtgt.* = c.DVT_APPL;

    const tgt = c.luaL_optlstring(ctx, ind, null, null);
    if (tgt != null) {
        kvtgt.* = c.DVT_TARGET;
        tid.tid = c.arcan_db_targetid(DBHANDLE(), tgt, null);
        if (tid.tid == c.BAD_TARGET) {
            kvtgt.* = c.DVT_ENDM;
            return tid;
        }

        const cfg = c.luaL_optlstring(ctx, ind + 1, null, null);
        if (cfg != null) {
            tid.cid = c.arcan_db_configid(DBHANDLE(), tid.tid, cfg);
            kvtgt.* = if (tid.cid == c.BAD_CONFIG) c.DVT_ENDM else c.DVT_CONFIG;
        }
    }

    return tid;
}

// ============================================================================
// store_key (C:6287)
// ============================================================================
fn storekey(ctx: ?*c.lua_State) callconv(.c) c_int {
    var kvtgt: c.DB_KVTARGET = undefined;
    const tid = setup_transaction(ctx, &kvtgt, if (c.lua_type(ctx, 1) == c.LUA_TTABLE) @as(c_int, 2) else @as(c_int, 3));

    if (kvtgt == c.DVT_ENDM) {
        c.lua_pushboolean(ctx, 0);
        return 1;
    }

    if (c.lua_type(ctx, 1) == c.LUA_TTABLE) {
        c.lua_pushnil(ctx);
        c.arcan_db_begin_transaction(DBHANDLE(), kvtgt, tid);

        var counter: usize = 0;
        while (c.lua_next(ctx, 1) != 0) {
            counter += 1;
            const key = c.lua_tolstring(ctx, -2, null);
            if (!validate_key(key)) {
                c.arcan_warning("store_key, key rejected (restricted to [a-Z0-9_+/=])\n");
            } else {
                const val = c.lua_tolstring(ctx, -1, null);
                c.arcan_db_add_kvpair(DBHANDLE(), key, val);
            }

            c.lua_settop(ctx, -1 - 1);
        }

        c.arcan_db_end_transaction(DBHANDLE());
        c.lua_pushboolean(ctx, 1);
        return 1;
    }

    const keystr = c.luaL_checklstring(ctx, 1, null);
    const valstr = c.luaL_checklstring(ctx, 2, null);
    if (!validate_key(keystr)) {
        c.arcan_warning("store_key, key rejected (restricted to [a-Z0-9_])\n");
        c.lua_pushboolean(ctx, 0);
        return 1;
    }

    c.arcan_db_begin_transaction(DBHANDLE(), kvtgt, tid);
    c.arcan_db_add_kvpair(DBHANDLE(), keystr, valstr);
    c.arcan_db_end_transaction(DBHANDLE());

    c.lua_pushboolean(ctx, 1);
    return 1;
}

// ============================================================================
// push_stringres helper (C:6341)
// ============================================================================
fn push_stringres(ctx: ?*c.lua_State, res: *c.arcan_strarr) c_int {
    c.lua_createtable(ctx, 0, 0);

    if (res.unnamed_0.data != null) {
        var curr: [*c][*c]u8 = res.unnamed_0.data;
        var count: c_uint = 1;
        const top = c.lua_gettop(ctx);

        while (curr.* != null) {
            c.lua_pushnumber(ctx, @floatFromInt(count));
            count += 1;
            c.lua_pushstring(ctx, curr.*);
            curr += 1;
            c.lua_rawset(ctx, top);
        }
    }

    return 1; // always return a table (empty if no results)
}

// ============================================================================
// match_keys (C:6364)
// ============================================================================
fn matchkeys(ctx: ?*c.lua_State) callconv(.c) c_int {
    const pattern = c.luaL_checklstring(ctx, 1, null);
    const domain: c_int = @intFromFloat(c.luaL_optnumber(ctx, 2, @as(f64, @floatFromInt(c.DVT_APPL))));

    if (domain != c.DVT_TARGET and domain != c.DVT_CONFIG and domain != c.DVT_APPL)
        c.arcan_fatal("match keys(%d) invalid domain specified, domain must be KEY_TARGET or KEY_CONFIG\n");

    var res: c.arcan_strarr = undefined;
    if (domain == c.DVT_APPL) {
        res = c.arcan_db_applkeys(DBHANDLE(), c.arcan_appl_id(), pattern);
    } else {
        res = c.arcan_db_matchkey(DBHANDLE(), @bitCast(domain), pattern);
    }

    const rv = push_stringres(ctx, &res);
    c.arcan_mem_freearr(&res);
    return rv;
}

// ============================================================================
// get_keys (C:6386)
// ============================================================================
fn getkeys(ctx: ?*c.lua_State) callconv(.c) c_int {
    const tgt = c.luaL_checklstring(ctx, 1, null);
    const cfg = c.luaL_optlstring(ctx, 2, null, null);
    var tid: c.arcan_dbtrans_id = undefined;
    var cid_u: c.arcan_dbtrans_id = undefined;
    tid.tid = c.arcan_db_targetid(DBHANDLE(), tgt, null);

    var res: c.arcan_strarr = undefined;
    if (cfg == null) {
        res = c.arcan_db_getkeys(DBHANDLE(), c.DVT_TARGET, tid);
    } else {
        cid_u.cid = c.arcan_db_configid(DBHANDLE(), tid.tid, cfg);
        res = c.arcan_db_getkeys(DBHANDLE(), c.DVT_CONFIG, cid_u);
    }

    const rv = push_stringres(ctx, &res);
    c.arcan_mem_freearr(&res);
    return rv;
}

// ============================================================================
// get_key (C:6409)
// ============================================================================
fn getkey(ctx: ?*c.lua_State) callconv(.c) c_int {
    const key = c.luaL_checklstring(ctx, 1, null);
    if (!validate_key(key)) {
        c.arcan_warning("invalid key specified (restricted to [a-Z0-9_])\n");
        c.lua_pushnil(ctx);
        return 1;
    }

    const opt_target = c.luaL_optlstring(ctx, 2, null, null);

    if (opt_target != null) {
        const tid = c.arcan_db_targetid(DBHANDLE(), opt_target, null);

        const opt_config = c.luaL_optlstring(ctx, 3, null, null);
        if (opt_config != null) {
            const cid = c.arcan_db_configid(DBHANDLE(), tid, opt_config);
            const val = c.arcan_db_getvalue(DBHANDLE(), c.DVT_CONFIG, cid, key);
            if (val != null) {
                c.lua_pushstring(ctx, val);
            } else {
                c.lua_pushnil(ctx);
            }
            c.free(@ptrCast(val));
        } else {
            _ = c.arcan_db_getvalue(DBHANDLE(), c.DVT_TARGET, tid, key);
        }
    } else {
        const val = c.arcan_db_appl_val(DBHANDLE(), c.arcan_appl_id(), key);

        if (val != null) {
            c.lua_pushstring(ctx, val);
            c.free(@ptrCast(val));
        } else {
            c.lua_pushnil(ctx);
        }
    }

    return 1;
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part7.zig
// ══════════════════════════════════════════════════════════════════════

// Zig port of engine/arcan_lua.c lines 6453–7453
// Functions: kbdrepeat, v3dorder, videocanvasrsz, push_fsrv_ramp, pull_fsrv_ramp,
//   fsrv_gamma, videodispgamma, videodispdescr, videodisplay, videomapping,
//   dpms_to_str, videodpms, inputbase, inputremaptranslation, inputcap,
//   mousegrab, gettargets, gettags, getconfigs, allocsurface, fillsurface,
//   imagemipmap, imagecolor, colorsurface, nullsurface, rawsurface,
//   randomsurface, filter_text



// Type aliases

// External symbols



const ORDER3D_FIRST: c_int = 1;
const ORDER3D_LAST: c_int = 2;
const ORDER3D_NONE: c_int = 0;

const ADPMS_IGNORE: c_int = 0;
const ADPMS_OFF: c_int = 1;
const ADPMS_SUSPEND: c_int = 2;
const ADPMS_STANDBY: c_int = 3;
const ADPMS_ON: c_int = 4;

const ARCAN_TAG_FRAMESERV: c_int = 3;
const HINT_NONE: c_int = 0;
const TXSTATE_TEX2D: c_int = 1;
const ARCAN_VFILTER_NONE: c_int = 0;

const EVENT_TRANSLATION_CLEAR: c_int = 0;
const EVENT_TRANSLATION_SET: c_int = 1;
const EVENT_TRANSLATION_REMAP: c_int = 2;
const EVENT_TRANSLATION_SERIALIZE_CURRENT: c_int = 3;
const EVENT_TRANSLATION_SERIALIZE_SPEC: c_int = 4;

const EVENT_IDEVKIND_KEYBOARD: c_int = 1;
const EVENT_IDEVKIND_GAMEDEV: c_int = 4;
const EVENT_IDEVKIND_TOUCHDISP: c_int = 8;
const EVENT_IDEVKIND_LEDCTRL: c_int = 16;
const EVENT_IDEVKIND_EYETRACKER: c_int = 32;

const EVENT_IDATATYPE_ANALOG: c_int = 1;
const EVENT_IDATATYPE_DIGITAL: c_int = 2;
const EVENT_IDATATYPE_TRANSLATED: c_int = 4;
const EVENT_IDATATYPE_TOUCH: c_int = 8;
const EVENT_IDATATYPE_EYES: c_int = 16;

const ACAP_TRANSLATED: c_int = 1;
const ACAP_MOUSE: c_int = 2;
const ACAP_GAMING: c_int = 4;
const ACAP_TOUCH: c_int = 8;
const ACAP_POSITION: c_int = 16;
const ACAP_ORIENTATION: c_int = 32;
const ACAP_EYES: c_int = 64;

const CREATE_USERMASK: c_uint = c.RESOURCE_APPL | c.RESOURCE_APPL_TEMP | c.RESOURCE_APPL_SHARED | c.RESOURCE_NS_USER;

const ARCAN_OK: c_int = 0;



// Inline Lua helpers

inline fn RGBA(r: u8, g: u8, b: u8, a: u8) u32 {
    return (@as(u32, a) << 24) | (@as(u32, b) << 16) | (@as(u32, g) << 8) | @as(u32, r);
}

fn abs_int(v: c_int) c_int {
    return if (v < 0) -v else v;
}

fn abs_usize(v: c_int) usize {
    const a = abs_int(v);
    return @intCast(a);
}

fn abs_u8(v: c_int) u8 {
    return @truncate(@as(c_uint, @bitCast(abs_int(v))));
}

// Extern declarations for functions in other translation units
// Zig implementation of FLAG_DIRTY macro from arcan_videoint.h
fn flag_dirty(vobj: [*c]c.arcan_vobject) void {
    if (vobj != null) {
        if (vobj.*.owner) |owner| {
            owner.*.transfc += 1;
        }
    }
    c.arcan_video_display.dirty += 1;
}

// ══════════════════════════════════════════════════════════════════════
// Functions
// ══════════════════════════════════════════════════════════════════════

fn kbdrepeat(ctx: ?*c.lua_State) callconv(.c) c_int {
    var rperiod: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1));
    var rdelay: c_int = @intFromFloat(c.luaL_optnumber(ctx, 2, -1.0));

    c.platform_event_keyrepeat(c.arcan_event_defaultctx(), &rperiod, &rdelay);

    c.lua_pushnumber(ctx, @floatFromInt(rperiod));
    c.lua_pushnumber(ctx, @floatFromInt(rdelay));

    return 2;
}

fn v3dorder(ctx: ?*c.lua_State) callconv(.c) c_int {
    var rt: arcan_vobj_id = c.ARCAN_EID;
    const nargs = c.lua_gettop(ctx);
    var order: c_int = undefined;

    if (nargs == 2) {
        rt = luaL_checkvid(ctx, 1, null);
        order = @intFromFloat(c.luaL_checknumber(ctx, 2));
    } else {
        order = @intFromFloat(c.luaL_checknumber(ctx, 1));
    }

    if (order != ORDER3D_FIRST and order != ORDER3D_LAST and order != ORDER3D_NONE)
        c.arcan_fatal("3dorder(%d) invalid order specified (%d)," ++
            "\texpected ORDER_FIRST, ORDER_LAST or ORDER_NONE\n", order, order);

    _ = c.arcan_video_3dorder(@bitCast(order), rt);
    return 0;
}

fn videocanvasrsz(ctx: ?*c.lua_State) callconv(.c) c_int {
    const w: usize = abs_usize(@intFromFloat(c.luaL_checknumber(ctx, 1)));
    const h: usize = abs_usize(@intFromFloat(c.luaL_checknumber(ctx, 2)));

    if (w == 0 or h == 0) {
        return 0;
    }

    // In LWA mode, disable no_stdout and resize the shmif output surface
    if (c.platform_is_lwa_mode()) {
        c.arcan_video_display.no_stdout = false;
        var mode = std.mem.zeroes(c.struct_monitor_mode);
        mode.width = @intCast(w);
        mode.height = @intCast(h);
        if (!c.platform_video_specify_mode(0, mode))
            return 0;
    }

    if (@as(c.arcan_errc, @intCast(c.ARCAN_OK)) == c.arcan_video_resize_canvas(w, h)) {
        c.arcan_lua_setglobalnum(ctx, "VRESW", @floatFromInt(w));
        c.arcan_lua_setglobalnum(ctx, "VRESH", @floatFromInt(h));
    }

    return 0;
}

fn push_fsrv_ramp(dst: ?*c.arcan_frameserver, src: ?*c.lua_State, index: c_int, n: usize) bool {
    var ramps = [_]f32{0} ** c.SHMIF_CMRAMP_UPLIM;
    var ch_sz = [_]usize{0} ** c.SHMIF_CMRAMP_PLIM;

    var edid_sz: usize = 0;
    var edid_buf: [*c]u8 = null;
    var i: usize = 0;

    while (i < n and i < @as(usize, c.SHMIF_CMRAMP_UPLIM)) : (i += 1) {
        _ = c.lua_rawgeti(src, 2, @intCast(i + 1));
        ramps[i] = @floatCast(c.lua_tonumber(src, -1));
        c.lua_settop(src, -1 - 1);
    }

    _ = c.lua_getfield(src, 2, "edid");
    edid_buf = @ptrCast(@constCast(c.lua_tolstring(src, -1, &edid_sz)));
    c.lua_settop(src, -1 - 1);

    // setjmp/longjmp for SIGBUS guard around frameserver shmpage access
    var tramp: c.jmp_buf = undefined;
    if (c._setjmp(&tramp) != 0) {
        return false;
    }

    ch_sz[0] = i;
    c.platform_fsrv_enter(dst, &tramp);
    const rv = c.arcan_frameserver_setramps(
        dst,
        @bitCast(@as(c_long, @intCast(index))),
        &ramps,
        i,
        &ch_sz,
        edid_buf,
        edid_sz,
    );
    c.platform_fsrv_leave();
    return rv;
}

fn pull_fsrv_ramp(dst: ?*c.lua_State, src: ?*c.arcan_frameserver, ind: c_int) c_int {
    var tramp: c.jmp_buf = undefined;
    if (c._setjmp(&tramp) != 0) {
        return 0;
    }

    var ch_pos: [c.SHMIF_CMRAMP_PLIM]usize = undefined;
    var tblbuf: [c.SHMIF_CMRAMP_UPLIM]f32 = undefined;

    c.platform_fsrv_enter(src, &tramp);
    const rv = c.arcan_frameserver_getramps(
        src,
        @bitCast(@as(c_long, @intCast(ind))),
        &tblbuf,
        @sizeOf([c.SHMIF_CMRAMP_UPLIM]f32),
        &ch_pos,
    );
    c.platform_fsrv_leave();

    if (rv and ch_pos[0] != 0) {
        const nr: usize = if (ch_pos[0] > @as(usize, c.SHMIF_CMRAMP_UPLIM)) @as(usize, c.SHMIF_CMRAMP_UPLIM) else ch_pos[0];
        c.lua_createtable(dst, @intCast(nr), 0);
        const top = c.lua_gettop(dst);
        for (0..nr) |i| {
            c.lua_pushnumber(dst, @floatFromInt(i + 1));
            c.lua_pushnumber(dst, @as(lua_Number, @floatCast(tblbuf[i])));
            c.lua_rawset(dst, top);
        }
        return 1;
    }

    return 0;
}

fn fsrv_gamma(ctx: ?*c.lua_State, fsrv_dst: [*c]c.arcan_vobject) c_int {
    if (fsrv_dst.*.feed.state.tag != ARCAN_TAG_FRAMESERV)
        c.arcan_fatal("video_displaygamma(), tried to set gamma on a vobj with " ++
            "no valid frameserver backing");

    // fsrv-set?
    if (c.lua_type(ctx, 2) == c.LUA_TTABLE) {
        const values: c_int = @intCast(c.lua_objlen(ctx, 2));
        if (values <= 0 or @rem(values, 3) != 0) {
            c.arcan_fatal("video_displaygamma(), broken ramp table" ++
                "(%d should be > 0 and divisible by 3)\n", values);
        }

        c.lua_pushboolean(ctx, @intFromBool(push_fsrv_ramp(
            @ptrCast(@alignCast(fsrv_dst.*.feed.state.ptr)),
            ctx,
            luaL_optint(ctx, 3, 0),
            @intCast(values),
        )));
        return 1;
    }
    // fsrv get
    else {
        const rv = pull_fsrv_ramp(
            ctx,
            @ptrCast(@alignCast(fsrv_dst.*.feed.state.ptr)),
            luaL_optint(ctx, 2, 0),
        );
        return rv;
    }
}

fn videodispgamma(ctx: ?*c.lua_State) callconv(.c) c_int {
    var fsrv_dst: [*c]c.arcan_vobject = null;

    // separate "to frameserver instead of display?" path:
    const id: i64 = @intFromFloat(c.luaL_checknumber(ctx, 1));
    if (id != c.ARCAN_EID and id != c.ARCAN_VIDEO_WORLDID and id > @as(i64, @intCast(lua_vid_base))) {
        fsrv_dst = c.arcan_video_getobject(@intCast(id - @as(i64, @intCast(lua_vid_base))));
        if (fsrv_dst != null)
            return fsrv_gamma(ctx, fsrv_dst);
    }

    if (c.lua_gettop(ctx) > 1) {
        c.luaL_checktype(ctx, 2, c.LUA_TTABLE);
        var values: c_int = @intCast(c.lua_objlen(ctx, 2));
        if (values <= 0 or @rem(values, 3) != 0) {
            c.arcan_fatal("video_displaygamma(), broken ramp table" ++
                "(%d should be > 0 and divisible by 3)\n", values);
        }

        const ramps: [*c]u16 = @ptrCast(@alignCast(c.arcan_alloc_mem(
            @as(usize, @intCast(values)) * @sizeOf(u16),
            c.ARCAN_MEM_VSTRUCT,
            c.ARCAN_MEM_TEMPORARY | c.ARCAN_MEM_BZERO,
            c.ARCAN_MEMALIGN_NATURAL,
        )));

        for (0..@intCast(values)) |i| {
            _ = c.lua_rawgeti(ctx, 2, @intCast(i + 1));
            const num: f32 = @floatCast(c.lua_tonumber(ctx, -1));
            c.lua_settop(ctx, -1 - 1);
            const clamped: f64 = if (num < 0.0) 0.0 else if (num > 1.0) 1.0 else @as(f64, @floatCast(num));
            ramps[i] = @intFromFloat(clamped * 65535.0);
        }

        values = @divTrunc(values, 3);
        const uvalues: usize = @intCast(values);
        c.lua_pushboolean(ctx, @intFromBool(c.platform_video_set_display_gamma(
            @bitCast(@as(c_int, @truncate(id))),
            uvalues,
            ramps + 0 * uvalues,
            ramps + 1 * uvalues,
            ramps + 2 * uvalues,
        )));

        return 1;
    }
    // get
    else {
        var nramps: usize = undefined;
        var outb: [*c]u16 = undefined;

        if (!c.platform_video_get_display_gamma(
            @bitCast(@as(c_int, @truncate(id))),
            &nramps,
            &outb,
        ))
            return 0;

        // push as planar table of floats
        c.lua_createtable(ctx, @intCast(nramps * 3), 0);
        const top = c.lua_gettop(ctx);
        for (0..nramps * 3) |i| {
            c.lua_pushnumber(ctx, @floatFromInt(i + 1));
            c.lua_pushnumber(ctx, @as(lua_Number, @floatCast(@as(f32, @floatFromInt(outb[i])) / 65535.0)));
            c.lua_rawset(ctx, top);
        }

        return 1;
    }

    return 0;
}

fn videodispdescr(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id: c.platform_display_id = @intFromFloat(c.luaL_checknumber(ctx, 1));
    var buf: [*c]u8 = undefined;
    var buf_sz: usize = undefined;

    if (!c.platform_video_display_edid(id, &buf, &buf_sz)) {
        return 0;
    }

    var hash: c_ulong = 5381;
    c.lua_pushlstring(ctx, buf, buf_sz);
    for (0..buf_sz) |i| {
        hash = ((hash << 5) +% hash) +% @as(c_ulong, buf[i]);
    }

    c.lua_pushnumber(ctx, @floatFromInt(hash));

    // if we can provide parsing support, expose select fields as a table
    c.lua_newtable(ctx);
    // Note: ARCAN_EGL_DRI_DISPLAYINFO ifdef block omitted (display-info parsing)

    c.free(@ptrCast(buf));
    return 3;
}

fn videodisplay(ctx: ?*c.lua_State) callconv(.c) c_int {
    var id: c.platform_display_id = undefined;
    var opts = std.mem.zeroes(c.platform_mode_opts);

    switch (c.lua_gettop(ctx)) {
        0 => {
            // rescan
            c.platform_video_query_displays();
        },
        1 => {
            // probe modes
            id = @intFromFloat(c.luaL_checknumber(ctx, 1));
            c.lua_newtable(ctx);
            push_displaymodes(ctx, id);
            return 1;
        },
        2 => {
            // specify hardcoded mode
            id = @intFromFloat(c.luaL_checknumber(ctx, 1));
            const mode: c.platform_mode_id = @intFromFloat(c.luaL_checknumber(ctx, 2));
            c.lua_pushboolean(ctx, @intFromBool(c.platform_video_set_mode(id, mode, opts)));
            return 1;
        },
        3 => {
            // specify custom mode
            id = @intFromFloat(c.luaL_checknumber(ctx, 1));
            // add options
            if (c.lua_type(ctx, 3) == c.LUA_TTABLE) {
                const mode: c.platform_mode_id = @intFromFloat(c.luaL_checknumber(ctx, 2));
                opts.vrr = intblfloat(ctx, 3, "vrr");
                opts.depth = @intFromFloat(intblfloat(ctx, 3, "format"));
                c.lua_pushboolean(ctx, @intFromBool(c.platform_video_set_mode(id, mode, opts)));
            } else {
                const h: usize = @intFromFloat(c.luaL_checknumber(ctx, 3));
                const w: usize = @intFromFloat(c.luaL_checknumber(ctx, 2));
                var mmode = std.mem.zeroes(c.monitor_mode);
                mmode.width = w;
                mmode.height = h;
                c.lua_pushboolean(ctx, @intFromBool(c.platform_video_specify_mode(id, mmode)));
            }
            return 1;
        },
        else => {
            c.arcan_fatal("video_displaymodes(), invalid number of aguments (%d)\n",
                c.lua_gettop(ctx));
        },
    }

    return 0;
}

fn videomapping(ctx: ?*c.lua_State) callconv(.c) c_int {
    const vid: arcan_vobj_id = c.luavid_tovid(c.luaL_checknumber(ctx, 1));
    const id: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));
    if (id < 0)
        c.arcan_fatal("map_video_display(), invalid target display id (%d)\n", id);

    var layer = std.mem.zeroes(c.display_layer_cfg);
    layer.hint = @intFromFloat(c.luaL_optnumber(ctx, 3, @floatFromInt(HINT_NONE)));
    layer.opacity = 1.0;

    if (@as(c_int, @bitCast(layer.hint)) < HINT_NONE) {
        c.arcan_fatal("map_video_display(), invalid blitting " ++
            "hint specified (%d)\n", @as(c_int, @bitCast(layer.hint)));
    }

    if (vid != c.ARCAN_VIDEO_WORLDID and vid != c.ARCAN_EID) {
        const vobj = c.arcan_video_getobject(vid);
        if (vobj == null)
            c.arcan_fatal("map_video_display(), invalid vid " ++
                "requested %lld \n", @as(c_longlong, vid));

        if (vobj.*.vstore.*.txmapped != TXSTATE_TEX2D) {
            c.arcan_warning("map_video_display(), associated " ++
                "video object has an invalid backing store (font, color, ...)\n");
            return 0;
        }
    }

    const layer_ind: usize = @intFromFloat(c.luaL_optnumber(ctx, 4, 0));
    if (layer_ind > 0) {
        layer.x = @intFromFloat(c.luaL_optnumber(ctx, 5, 0));
        layer.y = @intFromFloat(c.luaL_optnumber(ctx, 6, 0));
    }

    const left: isize = c.platform_video_map_display_layer(vid, @bitCast(id), layer_ind, layer);
    c.lua_pushboolean(ctx, @intFromBool(left >= 0));
    c.lua_pushnumber(ctx, @floatFromInt(left));
    return 2;
}

fn dpms_to_str(dpms: c_int) [*c]const u8 {
    return switch (dpms) {
        ADPMS_OFF => "off",
        ADPMS_SUSPEND => "suspend",
        ADPMS_STANDBY => "standby",
        ADPMS_ON => "on",
        else => "bad-display",
    };
}

fn videodpms(ctx: ?*c.lua_State) callconv(.c) c_int {
    const n = c.lua_gettop(ctx);
    const did: c.platform_display_id = @intFromFloat(c.luaL_checknumber(ctx, 1));
    if (1 == n) {
        // query only
    } else if (2 == n) {
        const state: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));
        if (c.strcmp(dpms_to_str(state), "bad-display") == 0)
            c.arcan_fatal("video_display_state(), invalid DPMS value (valid: " ++
                "DISPLAY _ON, _OFF, _SUSPEND or _STANDBY) \n");
        _ = c.platform_video_dpms(did, @bitCast(state));
    } else {
        c.arcan_fatal("video_display_state(), 1 or 2 arguments expected, not %d\n", n);
    }

    c.lua_pushstring(ctx, dpms_to_str(@bitCast(c.platform_video_dpms(did, @bitCast(ADPMS_IGNORE)))));

    return 1;
}

fn inputbase(ctx: ?*c.lua_State) callconv(.c) c_int {
    const devid: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1));
    var xyz: [3]f32 = undefined;
    xyz[0] = @floatCast(c.luaL_optnumber(ctx, 2, 0));
    xyz[1] = @floatCast(c.luaL_optnumber(ctx, 3, 0));
    xyz[2] = @floatCast(c.luaL_optnumber(ctx, 4, 0));
    c.platform_event_samplebase(devid, &xyz);
    return 0;
}

fn inputremaptranslation(ctx: ?*c.lua_State) callconv(.c) c_int {
    const devid: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1));
    const act: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));
    var getmap: bool = false;
    var ofs: c_int = 2;

    // set if we want an iostream to the current (remap) or a desired one
    if (c.lua_type(ctx, 3) == c.LUA_TBOOLEAN or c.lua_type(ctx, 3) == c.LUA_TNUMBER) {
        getmap = luaL_checkbnumber(ctx, 3);
        ofs += 1;
    }

    if (act != EVENT_TRANSLATION_CLEAR and
        act != EVENT_TRANSLATION_SET and
        act != EVENT_TRANSLATION_REMAP)
    {
        c.arcan_fatal("input_remap_translation() - unknown op: %d\n", act);
    }

    const ttop = c.lua_gettop(ctx);

    // Use a fixed-size buffer for the string array (VLA replacement)
    var arr_buf: [64][*c]const u8 = undefined;
    const arr_count: usize = if (ttop - ofs > 0) @intCast(ttop - ofs) else 0;

    if (arr_count > 0) {
        for (0..arr_count) |i| {
            arr_buf[i] = c.luaL_checklstring(ctx, @intCast(@as(c_int, @intCast(i)) + ofs + 1), null);
        }
        arr_buf[arr_count] = null;
    }

    var err: [*c]const u8 = "";

    if (getmap) {
        var mode: c_int = EVENT_TRANSLATION_SERIALIZE_CURRENT;
        if (act == EVENT_TRANSLATION_SET)
            mode = EVENT_TRANSLATION_SERIALIZE_SPEC;

        const fd = c.platform_event_translation(devid, mode, &arr_buf, &err);
        var dst_ptr: [*c]c.nonblock_io = undefined;
        _ = c.alt_nbio_import(ctx, fd, @bitCast(mode), &dst_ptr, null);
        c.lua_pushstring(ctx, err);
        return 2;
    }

    const res = c.platform_event_translation(devid, act, &arr_buf, &err);
    c.lua_pushboolean(ctx, res);
    c.lua_pushstring(ctx, err);

    return 2;
}

fn inputcap(ctx: ?*c.lua_State) callconv(.c) c_int {
    var pident: [*c]const u8 = undefined;
    const pcap: c_uint = @bitCast(c.platform_event_capabilities(&pident));

    c.lua_newtable(ctx);
    const top = c.lua_gettop(ctx);
    if (c.lua_type(ctx, 1) == c.LUA_TNUMBER) {
        var vobj: [*c]c.arcan_vobject = undefined;
        _ = luaL_checkvid(ctx, 1, &vobj);

        if (vobj.*.feed.state.tag != ARCAN_TAG_FRAMESERV)
            c.arcan_fatal("input_capabilities(), specified " ++
                "vid (arg 1) not associated with a frameserver.");

        const tgt: *c.arcan_frameserver = @ptrCast(@alignCast(vobj.*.feed.state.ptr));

        set_tblbool(ctx, "keyboard", (tgt.devicemask & @as(c_uint, @bitCast(EVENT_IDEVKIND_KEYBOARD))) != 0, top);
        set_tblbool(ctx, "game", (tgt.devicemask & @as(c_uint, @bitCast(EVENT_IDEVKIND_GAMEDEV))) != 0, top);
        set_tblbool(ctx, "mouse", (tgt.devicemask & @as(c_uint, @bitCast(EVENT_IDEVKIND_GAMEDEV))) != 0, top);
        set_tblbool(ctx, "touch", (tgt.devicemask & @as(c_uint, @bitCast(EVENT_IDEVKIND_TOUCHDISP))) != 0, top);
        set_tblbool(ctx, "led", (tgt.devicemask & @as(c_uint, @bitCast(EVENT_IDEVKIND_LEDCTRL))) != 0, top);
        set_tblbool(ctx, "eyetracker", (tgt.devicemask & @as(c_uint, @bitCast(EVENT_IDEVKIND_EYETRACKER))) != 0, top);
        set_tblbool(ctx, "analog", (tgt.datamask & @as(c_uint, @bitCast(EVENT_IDATATYPE_ANALOG))) != 0, top);
        set_tblbool(ctx, "digital", (tgt.datamask & @as(c_uint, @bitCast(EVENT_IDATATYPE_DIGITAL))) != 0, top);
        set_tblbool(ctx, "translated", (tgt.datamask & @as(c_uint, @bitCast(EVENT_IDATATYPE_TRANSLATED))) != 0, top);
        set_tblbool(ctx, "touch", (tgt.datamask & @as(c_uint, @bitCast(EVENT_IDATATYPE_TOUCH))) != 0, top);
        set_tblbool(ctx, "eyes", (tgt.datamask & @as(c_uint, @bitCast(EVENT_IDATATYPE_EYES))) != 0, top);
    } else {
        set_tblbool(ctx, "keyboard", (pcap & @as(c_uint, @bitCast(ACAP_TRANSLATED))) > 0, top);
        set_tblbool(ctx, "mouse", (pcap & @as(c_uint, @bitCast(ACAP_MOUSE))) > 0, top);
        set_tblbool(ctx, "game", (pcap & @as(c_uint, @bitCast(ACAP_GAMING))) > 0, top);
        set_tblbool(ctx, "touch", (pcap & @as(c_uint, @bitCast(ACAP_TOUCH))) > 0, top);
        set_tblbool(ctx, "position", (pcap & @as(c_uint, @bitCast(ACAP_POSITION))) > 0, top);
        set_tblbool(ctx, "orientation", (pcap & @as(c_uint, @bitCast(ACAP_ORIENTATION))) > 0, top);
        set_tblbool(ctx, "eyetracker", (pcap & @as(c_uint, @bitCast(ACAP_EYES))) > 0, top);
    }
    c.lua_pushstring(ctx, pident);
    return 2;
}

fn mousegrab(ctx: ?*c.lua_State) callconv(.c) c_int {
    const mode = luaL_optint(ctx, 1, -1);

    if (mode == -1)
        luactx.grab = @intFromBool(luactx.grab == 0)
    else if (mode == MOUSE_GRAB_ON)
        luactx.grab = 1
    else if (mode == MOUSE_GRAB_OFF)
        luactx.grab = 0;

    c.arcan_device_lock(0, luactx.grab != 0);
    c.lua_pushboolean(ctx, @as(c_int, @bitCast(@as(c_uint, luactx.grab))));

    return 1;
}

fn gettargets(ctx: ?*c.lua_State) callconv(.c) c_int {
    var rv: c_int = 0;

    var res = c.arcan_db_targets(
        DBHANDLE(),
        c.luaL_optlstring(ctx, 1, null, null),
    );
    rv += push_stringres(ctx, &res);
    c.arcan_mem_freearr(&res);

    return rv;
}

fn gettags(ctx: ?*c.lua_State) callconv(.c) c_int {
    var res = c.arcan_db_target_tags(DBHANDLE());
    const rv = push_stringres(ctx, &res);
    return rv;
}

fn getconfigs(ctx: ?*c.lua_State) callconv(.c) c_int {
    const target = c.luaL_checklstring(ctx, 1, null);
    var rv: c_int = 0;

    const tid = c.arcan_db_targetid(DBHANDLE(), target, null);
    var res = c.arcan_db_configs(DBHANDLE(), tid);

    rv += push_stringres(ctx, &res);
    const tag = c.arcan_db_targettag(DBHANDLE(), tid);
    if (tag != null) {
        c.lua_pushstring(ctx, tag);
        c.arcan_mem_free(@ptrCast(tag));
        rv += 1;
    }

    c.arcan_mem_freearr(&res);

    return rv;
}

fn allocsurface(ctx: ?*c.lua_State) callconv(.c) c_int {
    const w: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1));
    const h: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));

    const noalpha = luaL_optbnumber(ctx, 3, false);
    var quality: c_int = @intFromFloat(c.luaL_optnumber(ctx, 4, 0));

    if (w > MAX_SURFACEW or h > MAX_SURFACEH)
        c.arcan_fatal("alloc_surface(%d, %d) failed, unacceptable " ++
            "surface dimensions. Compile time restriction (%d,%d)\n",
            w, h, MAX_SURFACEW, MAX_SURFACEH);

    var rv: arcan_vobj_id = undefined;
    const vobj = c.arcan_video_newvobject(&rv);
    if (vobj == null) {
        lua_pushvid(ctx, c.ARCAN_EID);
        return 1;
    }

    const ds = vobj.*.vstore;

    // the quality levels are defined to have the noalpha as + 1
    if (noalpha)
        quality += 1;

    c.agp_empty_vstoreext(ds, @intCast(w), @intCast(h), @bitCast(quality));

    vobj.*.origw = @truncate(@as(c_uint, @bitCast(w)));
    vobj.*.origh = @truncate(@as(c_uint, @bitCast(h)));
    vobj.*.order = 0;
    _ = c.arcan_vint_attachobject(rv);

    lua_pushvid(ctx, rv);
    trace_allocation(ctx, "alloc_surface", rv);

    return 1;
}

fn fillsurface(ctx: ?*c.lua_State) callconv(.c) c_int {
    var cons = c.img_cons{ .w = 32, .h = 32, .bpp = 4 };

    const desw: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1));
    const desh: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));

    const r: u8 = abs_u8(@intFromFloat(c.luaL_checknumber(ctx, 3)));
    const g: u8 = abs_u8(@intFromFloat(c.luaL_checknumber(ctx, 4)));
    const b: u8 = abs_u8(@intFromFloat(c.luaL_checknumber(ctx, 5)));

    cons.w = @bitCast(abs_int(@intFromFloat(c.luaL_optnumber(ctx, 6, 8))));
    cons.h = @bitCast(abs_int(@intFromFloat(c.luaL_optnumber(ctx, 7, 8))));

    if (@as(c_int, @bitCast(cons.w)) > 0 and @as(c_int, @bitCast(cons.w)) <= MAX_SURFACEW and
        @as(c_int, @bitCast(cons.h)) > 0 and @as(c_int, @bitCast(cons.h)) <= MAX_SURFACEH)
    {
        const buf: [*c]c.av_pixel = @ptrCast(@alignCast(c.arcan_alloc_mem(
            @as(usize, cons.w) * @as(usize, cons.h) * @sizeOf(c.av_pixel),
            c.ARCAN_MEM_VBUFFER,
            0,
            c.ARCAN_MEMALIGN_PAGE,
        )));

        if (buf == null) {
            // error path (goto error in C)
            return 0;
        }

        var cptr: [*c]c.av_pixel = buf;

        var y: usize = 0;
        while (y < cons.h) : (y += 1) {
            var x: usize = 0;
            while (x < cons.w) : (x += 1) {
                cptr.* = RGBA(r, g, b, 0xff);
                cptr += 1;
            }
        }

        const id = c.arcan_video_rawobject(
            buf,
            cons,
            @floatFromInt(desw),
            @floatFromInt(desh),
            0,
        );

        lua_pushvid(ctx, id);
        trace_allocation(ctx, "fill_surface", id);
        return 1;
    } else {
        c.arcan_fatal("fillsurface(%d, %d) failed, unacceptable " ++
            "surface dimensions. Compile time restriction (%d,%d)\n",
            desw, desh, MAX_SURFACEW, MAX_SURFACEH);
    }

    // error: couldn't allocate buffer
    return 0;
}

fn imagemipmap(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const state = luaL_checkbnumber(ctx, 1);
    _ = c.arcan_video_mipmapset(id, state);
    return 0;
}

fn imagecolor(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 1, &vobj);
    const cred: u8 = abs_u8(@intFromFloat(c.luaL_checknumber(ctx, 2)));
    const cgrn: u8 = abs_u8(@intFromFloat(c.luaL_checknumber(ctx, 3)));
    const cblu: u8 = abs_u8(@intFromFloat(c.luaL_checknumber(ctx, 4)));
    const alpha: u8 = abs_u8(@intFromFloat(c.luaL_optnumber(ctx, 5, 255)));

    if (vobj.*.vstore.*.txmapped != 0) {
        const rtgt = c.arcan_vint_findrt(vobj);
        if (rtgt != null) {
            c.agp_rendertarget_clearcolor(
                rtgt.*.art,
                @as(f32, @floatFromInt(cred)) / 255.0,
                @as(f32, @floatFromInt(cgrn)) / 255.0,
                @as(f32, @floatFromInt(cblu)) / 255.0,
                @as(f32, @floatFromInt(alpha)) / 255.0,
            );
            c.lua_pushboolean(ctx, 1);
            return 1;
        } else {
            c.lua_pushboolean(ctx, 0);
            return 1;
        }
    }

    vobj.*.vstore.*.vinf.col.r = @as(f32, @floatFromInt(cred)) / 255.0;
    vobj.*.vstore.*.vinf.col.g = @as(f32, @floatFromInt(cgrn)) / 255.0;
    vobj.*.vstore.*.vinf.col.b = @as(f32, @floatFromInt(cblu)) / 255.0;
    flag_dirty(vobj);

    c.lua_pushboolean(ctx, 1);
    return 1;
}

fn colorsurface(ctx: ?*c.lua_State) callconv(.c) c_int {
    const desw: usize = abs_usize(@intFromFloat(c.luaL_checknumber(ctx, 1)));
    const desh: usize = abs_usize(@intFromFloat(c.luaL_checknumber(ctx, 2)));
    const cred: u8 = abs_u8(@intFromFloat(c.luaL_checknumber(ctx, 3)));
    const cgrn: u8 = abs_u8(@intFromFloat(c.luaL_checknumber(ctx, 4)));
    const cblu: u8 = abs_u8(@intFromFloat(c.luaL_checknumber(ctx, 5)));
    const order: c_int = abs_int(@intFromFloat(c.luaL_optnumber(ctx, 6, 1)));

    const id = c.arcan_video_solidcolor(
        @floatFromInt(desw),
        @floatFromInt(desh),
        cred,
        cgrn,
        cblu,
        @truncate(@as(c_uint, @bitCast(order))),
    );
    lua_pushvid(ctx, id);
    trace_allocation(ctx, "color_surface", id);

    return 1;
}

fn nullsurface(ctx: ?*c.lua_State) callconv(.c) c_int {
    const desw: usize = abs_usize(@intFromFloat(c.luaL_checknumber(ctx, 1)));
    const desh: usize = abs_usize(@intFromFloat(c.luaL_checknumber(ctx, 2)));
    const order: c_int = abs_int(@intFromFloat(c.luaL_optnumber(ctx, 3, 1)));

    const id = c.arcan_video_nullobject(
        @floatFromInt(desw),
        @floatFromInt(desh),
        @truncate(@as(c_uint, @bitCast(order))),
    );
    lua_pushvid(ctx, id);

    trace_allocation(ctx, "null_surface", id);

    return 1;
}

fn rawsurface(ctx: ?*c.lua_State) callconv(.c) c_int {
    const desw: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1));
    const desh: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));
    const bpp: c_int = @intFromFloat(c.luaL_checknumber(ctx, 3));

    const dumpstr = c.luaL_optlstring(ctx, 5, null, null);

    if (bpp != 1 and bpp != 3 and bpp != 4)
        c.arcan_fatal("rawsurface(), invalid source channel count (%d)" ++
            "\taccepted values: 1, 2, 4\n", bpp);

    const cons = c.img_cons{
        .w = @bitCast(desw),
        .h = @bitCast(desh),
        .bpp = @truncate(@as(c_uint, @sizeOf(c.av_pixel))),
    };

    c.luaL_checktype(ctx, 4, c.LUA_TTABLE);
    const nsamples: c_int = @intCast(c.lua_objlen(ctx, 4));

    if (nsamples < desw * desh * bpp)
        c.arcan_fatal("rawsurface(), number of samples (%d) are less than" ++
            "\tthe expected length (%d).\n", nsamples, desw * desh * bpp);

    var ofs: c_uint = 1;

    if (desw < 0 or desh < 0 or desw > MAX_SURFACEW or desh > MAX_SURFACEH)
        c.arcan_fatal("rawsurface(), desired dimensions (%d x %d) " ++
            "exceed compile-time limits (%d x %d).\n",
            desw, desh, MAX_SURFACEW, MAX_SURFACEH);

    const buf: [*c]c.av_pixel = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @as(usize, @intCast(desw)) * @as(usize, @intCast(desh)) * @sizeOf(c.av_pixel),
        c.ARCAN_MEM_VBUFFER,
        0,
        c.ARCAN_MEMALIGN_PAGE,
    )));

    var cptr: [*c]c.av_pixel = buf;

    var y: usize = 0;
    while (y < @as(usize, cons.h)) : (y += 1) {
        var x: usize = 0;
        while (x < @as(usize, cons.w)) : (x += 1) {
            switch (bpp) {
                1 => {
                    _ = c.lua_rawgeti(ctx, 4, @bitCast(blk: {
                        const tmp = ofs;
                        ofs += 1;
                        break :blk tmp;
                    }));
                    const r: u8 = @intFromFloat(c.lua_tonumber(ctx, -1));
                    c.lua_settop(ctx, -1 - 1);
                    cptr.* = RGBA(r, r, r, 0xff);
                    cptr += 1;
                },
                3 => {
                    _ = c.lua_rawgeti(ctx, 4, @bitCast(blk: {
                        const tmp = ofs;
                        ofs += 1;
                        break :blk tmp;
                    }));
                    const r: u8 = @intFromFloat(c.lua_tonumber(ctx, -1));
                    _ = c.lua_rawgeti(ctx, 4, @bitCast(blk: {
                        const tmp = ofs;
                        ofs += 1;
                        break :blk tmp;
                    }));
                    const g: u8 = @intFromFloat(c.lua_tonumber(ctx, -1));
                    _ = c.lua_rawgeti(ctx, 4, @bitCast(blk: {
                        const tmp = ofs;
                        ofs += 1;
                        break :blk tmp;
                    }));
                    const b_val: u8 = @intFromFloat(c.lua_tonumber(ctx, -1));
                    c.lua_settop(ctx, -3 - 1);
                    cptr.* = RGBA(r, g, b_val, 0xff);
                    cptr += 1;
                },
                4 => {
                    _ = c.lua_rawgeti(ctx, 4, @bitCast(blk: {
                        const tmp = ofs;
                        ofs += 1;
                        break :blk tmp;
                    }));
                    const r: u8 = @intFromFloat(c.lua_tonumber(ctx, -1));
                    _ = c.lua_rawgeti(ctx, 4, @bitCast(blk: {
                        const tmp = ofs;
                        ofs += 1;
                        break :blk tmp;
                    }));
                    const g: u8 = @intFromFloat(c.lua_tonumber(ctx, -1));
                    _ = c.lua_rawgeti(ctx, 4, @bitCast(blk: {
                        const tmp = ofs;
                        ofs += 1;
                        break :blk tmp;
                    }));
                    const b_val: u8 = @intFromFloat(c.lua_tonumber(ctx, -1));
                    _ = c.lua_rawgeti(ctx, 4, @bitCast(blk: {
                        const tmp = ofs;
                        ofs += 1;
                        break :blk tmp;
                    }));
                    const a: u8 = @intFromFloat(c.lua_tonumber(ctx, -1));
                    c.lua_settop(ctx, -4 - 1);
                    cptr.* = RGBA(r, g, b_val, a);
                    cptr += 1;
                },
                else => {},
            }
        }
    }

    if (dumpstr != null) {
        var fd: c_int = undefined;
        const fname = c.arcan_find_resource(dumpstr, CREATE_USERMASK, c.ARES_FILE | c.ARES_CREATE, &fd);
        if (fname == null) {
            c.arcan_warning(
                "rawsurface() -- refusing to overwrite existing file (%s)\n",
                fname,
            );
        } else {
            const fpek = c.fdopen(fd, "wb");
            if (fpek == null) {
                c.arcan_warning("rawsurface() - - couldn't open (%s).\n", fname);
            } else {
                _ = c.arcan_img_outpng(fpek, buf, @intCast(desw), @intCast(desh), false);
            }
            _ = c.fclose(fpek);
            c.arcan_mem_free(@ptrCast(fname));
        }
    }

    const id = c.arcan_video_rawobject(buf, cons, @floatFromInt(desw), @floatFromInt(desh), 0);

    lua_pushvid(ctx, id);
    trace_allocation(ctx, "raw_surface", id);
    return 1;
}

fn randomsurface(ctx: ?*c.lua_State) callconv(.c) c_int {
    const desw: usize = abs_usize(@intFromFloat(c.luaL_checknumber(ctx, 1)));
    const desh: usize = abs_usize(@intFromFloat(c.luaL_checknumber(ctx, 2)));
    const cons = c.img_cons{
        .w = @truncate(desw),
        .h = @truncate(desh),
        .bpp = @truncate(@as(c_uint, @sizeOf(c.av_pixel))),
    };

    const method = c.luaL_optlstring(ctx, 3, "normal", null);

    const cptr: [*c]c.av_pixel = @ptrCast(@alignCast(c.arcan_alloc_mem(
        desw * desh * @sizeOf(c.av_pixel),
        c.ARCAN_MEM_VBUFFER,
        0,
        c.ARCAN_MEMALIGN_PAGE,
    )));

    if (c.strcmp(method, "uniform-3") == 0) {
        for (0..desh) |y| {
            for (0..desw) |x| {
                var rgb: [3]u8 = undefined;
                c.arcan_random(&rgb, 3);
                cptr[y * desw + x] = RGBA(rgb[0], rgb[1], rgb[2], 255);
            }
        }
    } else if (c.strcmp(method, "uniform-4") == 0) {
        // fill entire buffer with random bytes
        c.arcan_random(@ptrCast(cptr), desw * desh * @sizeOf(c.av_pixel));
    } else if (c.strcmp(method, "fbm") == 0) {
        const lacunarity: f32 = @floatCast(c.luaL_checknumber(ctx, 4));
        const gain_val: f32 = @floatCast(c.luaL_checknumber(ctx, 5));
        const octaves: f32 = @floatCast(c.luaL_checknumber(ctx, 6));
        _ = @as(f32, @floatCast(c.luaL_checknumber(ctx, 7))); // xstart (unused in loop)
        _ = @as(f32, @floatCast(c.luaL_checknumber(ctx, 8))); // ystart (unused in loop)
        const zv: f32 = @floatCast(c.luaL_checknumber(ctx, 9));

        const sx: f32 = 1.0 / @as(f32, @floatFromInt(desw));
        const sy: f32 = 1.0 / @as(f32, @floatFromInt(desh));

        for (0..desh) |y| {
            for (0..desw) |x| {
                // [-1, 1] -> [0, 1] -> 0..255
                const xv: f32 = @as(f32, @floatFromInt(x)) * sx;
                const yv: f32 = @as(f32, @floatFromInt(y)) * sy;
                const rv: f32 = @floatCast(1.0 + @as(f64, @floatCast(
                    stb_perlin_fbm_noise3(xv, yv, zv, lacunarity, gain_val, @intFromFloat(octaves)),
                )));
                const iv: u8 = @intFromFloat((rv / 2.0) * 255.0);
                cptr[y * desw + x] = RGBA(iv, iv, iv, 255);
            }
        }
    } else {
        for (0..desh) |y| {
            for (0..desw) |x| {
                var rv: u8 = undefined;
                c.arcan_random(&rv, 1);
                cptr[y * desw + x] = RGBA(rv, rv, rv, 255);
            }
        }
    }

    const id = c.arcan_video_rawobject(null, cons, @floatFromInt(desw), @floatFromInt(desh), 0);
    _ = c.arcan_video_objectfilter(id, @bitCast(ARCAN_VFILTER_NONE));
    lua_pushvid(ctx, id);

    trace_allocation(ctx, "random", id);
    return 1;
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part8.zig
// ══════════════════════════════════════════════════════════════════════

// === Part 8: System/Lifecycle + Target Hints ===
//
// Ported from arcan_lua.c lines 7454-8521.
// Functions: warning, arcan_lua_shutdown, arcan_lua_dostring, error_hook,
//   sig_watchdog, arcan_lua_default_errorhook, arcan_lua_alloc,
//   luaB_loadstring, add_source, del_source, error_nbio,
//   arcan_lua_mapfunctions, alua_shutdown, globcb, listns, globresource,
//   resource, screencoord, arcan_lua_callvoidfun, arcantargethint,
//   targethandler, targetpacify, targetportcfg, layout_tonum, targetgeohint,
//   targetfonthint, xlt_dev, pthr_waiter, targetdevhint, targetdisphint,
//   get_vid_token, targetanchor



// Type aliases

// External symbols from other engine modules

// luactx state — static in arcan_lua.c, declared extern for linking

// Extern fn from other parts of arcan_lua

// Constants
const BADFD: c_int = -1;
const BROKEN_PROCESS_HANDLE: c_int = -1;



// ---------------------------------------------------------------------------
// 1. warning (C:7454-7473)
// ---------------------------------------------------------------------------
/// `shmifmon(tag)` — Lua-callable tag-writer. Routes to the engine-wide
/// shmif_monitor log so Lua-side observations show up interleaved with
/// engine-side event traces. No-op when ARCAN_SHMIF_MONITOR is unset.
fn shmifmon_lua(ctx: ?*c.lua_State) callconv(.c) c_int {
    const smon = @import("shmif_monitor");
    const msg: [*c]const u8 = c.luaL_checklstring(ctx, 1, null);
    if (msg != null) {
        smon.emitLuaTag(@ptrCast(msg));
    }
    return 0;
}

fn warning(ctx: ?*c.lua_State) callconv(.c) c_int {
    var len: usize = 0;
    var msg: [*c]u8 = @as([*c]u8, @ptrCast(@constCast(c.luaL_checklstring(ctx, 1, null))));
    msg = filter_text(msg, &len);

    if (c.lua_type(ctx, 2) == c.LUA_TBOOLEAN and c.lua_toboolean(ctx, 2) != 0) {
        c.arcan_monitor_watchdog(ctx, null);
    }

    if (len == 0) {
        return 0;
    }

    c.arcan_warning("\n\x1b[1m(%s)\x1b[32m %s\x1b[0m\n", c.arcan_appl_id(), msg);
    return 0;
}

// ---------------------------------------------------------------------------
// 2. arcan_lua_shutdown (C:7475-7497)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 3. arcan_lua_dostring (C:7499-7503)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 4. error_hook (C:7505-7510)
// ---------------------------------------------------------------------------
fn error_hook(ctx: ?*c.lua_State, ar: [*c]c.lua_Debug) callconv(.c) void {
    _ = ar;
    _ = c.luaL_error(ctx, "ANR - Application Not Responding");
}

// ---------------------------------------------------------------------------
// 6. arcan_lua_default_errorhook (C:7520-7526)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 7. arcan_lua_alloc (C:7528-7541)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 12. arcan_lua_mapfunctions (C:7574-7590)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 13. alua_shutdown (C:7593-7618)
// ---------------------------------------------------------------------------
fn alua_shutdown(ctx: ?*c.lua_State) callconv(.c) c_int {
    var ev = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_SYSTEM))));
    ev.unnamed_0.unnamed_0.unnamed_0.sys.kind = @as(c_uint, @bitCast(c.EVENT_SYSTEM_EXIT));
    ev.unnamed_0.unnamed_0.unnamed_0.sys.errcode = @as(c_int, @intFromFloat(
        c.luaL_optnumber(ctx, 2, @as(lua_Number, @floatFromInt(c.EXIT_SUCCESS))),
    ));
    _ = c.arcan_event_enqueue(c.arcan_event_defaultctx(), &ev);

    var tlen: usize = 0;
    const str = filter_text(
        @as([*c]u8, @ptrCast(@constCast(c.luaL_optlstring(ctx, 1, "", null)))),
        &tlen,
    );
    if (tlen > 0) {
        c.arcan_warning("%s\n", str);
    }

    return 0;
}

// ---------------------------------------------------------------------------
// struct Globs — helper for globresource
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 18. screencoord (C:7762-7782)
// ---------------------------------------------------------------------------
fn screencoord(ctx: ?*c.lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);

    var cv: [4]c.vector = undefined;
    if (c.ARCAN_OK == c.arcan_video_screencoords(id, &cv)) {
        c.lua_pushnumber(ctx, @as(lua_Number, @floatCast(cv[0].unnamed_0.unnamed_0.x)));
        c.lua_pushnumber(ctx, @as(lua_Number, @floatCast(cv[0].unnamed_0.unnamed_0.y)));
        c.lua_pushnumber(ctx, @as(lua_Number, @floatCast(cv[1].unnamed_0.unnamed_0.x)));
        c.lua_pushnumber(ctx, @as(lua_Number, @floatCast(cv[1].unnamed_0.unnamed_0.y)));
        c.lua_pushnumber(ctx, @as(lua_Number, @floatCast(cv[2].unnamed_0.unnamed_0.x)));
        c.lua_pushnumber(ctx, @as(lua_Number, @floatCast(cv[2].unnamed_0.unnamed_0.y)));
        c.lua_pushnumber(ctx, @as(lua_Number, @floatCast(cv[3].unnamed_0.unnamed_0.x)));
        c.lua_pushnumber(ctx, @as(lua_Number, @floatCast(cv[3].unnamed_0.unnamed_0.y)));
        return 8;
    }

    return 0;
}

// ---------------------------------------------------------------------------
// 19. arcan_lua_callvoidfun (C:7784-7810)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 20. arcantargethint (C:7812-7922)
// In LWA mode, sends hint events to parent. Otherwise pushes false.
// ---------------------------------------------------------------------------
fn arcantargethint(ctx: ?*c.lua_State) callconv(.c) c_int {
    if (c.platform_is_lwa_mode()) {
        var tblind: c_int = 2;
        if (c.lua_type(ctx, 1) == c.LUA_TNUMBER) {
            tblind = 3;
        }

        const msg_str = c.luaL_checklstring(ctx, tblind - 1, null);
        if (c.lua_type(ctx, tblind) != c.LUA_TTABLE) {
            c.lua_pushboolean(ctx, 0);
            return 1;
        }

        if (c.strcmp(msg_str, "state_size") == 0) {
            var ev = c.arcan_event.zeroes();
            ev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
            ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_STATESIZE;
            var size = intblint(ctx, tblind, "state_size");
            var typeid = intblint(ctx, tblind, "typeid");
            if (size < 0) size = 0;
            if (typeid < 0) typeid = 0;
            ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.stateinf.size = @intCast(size);
            ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.stateinf.type = @intCast(typeid);
            c.lua_pushboolean(ctx, @intFromBool(c.platform_lwa_targetevent(null, &ev)));
        } else if (c.strcmp(msg_str, "cursor") == 0) {
            var ev = c.arcan_event.zeroes();
            ev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
            ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_CURSORHINT;
            const lbl = intblstr(ctx, tblind, "style");
            if (lbl == null) {
                c.lua_pushboolean(ctx, 0);
                return 1;
            }
            _ = c.snprintf(
                @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data)),
                @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data)),
                "%s",
                lbl,
            );
            c.lua_pushboolean(ctx, @intFromBool(c.platform_lwa_targetevent(null, &ev)));
        } else if (c.strcmp(msg_str, "input_label") == 0) {
            var ev = c.arcan_event.zeroes();
            ev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
            ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_LABELHINT;
            const lbl = intblstr(ctx, tblind, "labelhint");
            if (lbl == null) {
                c.lua_pushboolean(ctx, 0);
                return 1;
            }
            _ = c.snprintf(
                @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.labelhint.label)),
                @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.labelhint.label)),
                "%s",
                lbl,
            );

            const init = intblint(ctx, tblind, "initial");
            if (init != -1) {
                ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.labelhint.initial = @intCast(init);
            }

            const descr = intblstr(ctx, tblind, "description");
            if (descr != null) {
                _ = c.snprintf(
                    @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.labelhint.descr)),
                    @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.labelhint.descr)),
                    "%s",
                    descr,
                );
            }

            const vsym = intblstr(ctx, tblind, "vsym");
            if (vsym != null) {
                _ = c.snprintf(
                    @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.labelhint.vsym)),
                    5,
                    "%s",
                    vsym,
                );
            }

            const dt = lookup_idatatype_str(intblstr(ctx, tblind, "datatype"));
            if (dt != -1) {
                ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.labelhint.idatatype = @intCast(dt);
            }

            const mods = intblint(ctx, tblind, "modifiers");
            if (mods != -1) {
                ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.labelhint.modifiers = @intCast(mods);
            }

            c.lua_pushboolean(ctx, @intFromBool(c.platform_lwa_targetevent(null, &ev)));
        } else {
            c.lua_pushboolean(ctx, 0);
        }
        return 1;
    }
    c.lua_pushboolean(ctx, 0);
    return 1;
}

// ---------------------------------------------------------------------------
// 21. targethandler (C:7924-7979)
// ---------------------------------------------------------------------------
fn targethandler(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const id = luaL_checkvid(ctx, 1, &vobj);

    // unreference the old one so we don't leak
    if (vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV) {
        c.arcan_fatal("target_updatehandler(), specified vid (arg 1) not " ++
            "associated with a frameserver.");
    }

    const fsrv: *c.arcan_frameserver = @ptrCast(@alignCast(
        vobj.*.feed.state.ptr orelse {
            c.arcan_fatal("target_updatehandler(), specified vid (arg 1) is not" ++
                " associated with a frameserver.");
            unreachable;
        },
    ));

    if (fsrv.tag != @as(isize, @bitCast(@as(c_long, c.LUA_NOREF)))) {
        c.luaL_unref(ctx, c.LUA_REGISTRYINDEX, @as(c_int, @intCast(fsrv.tag)));
    }

    // takes care of the type checking or setting an empty ref
    const ref = find_lua_callback(ctx);
    @as(*isize, @ptrCast(@alignCast(@constCast(&fsrv.tag)))).* = ref;

    // for the already pending events referring to the specific frameserver,
    // rewrite the otag to match that of the new function
    var vid_val = id;
    var ref_val = ref;
    c.arcan_event_repl(
        c.arcan_event_defaultctx(),
        c.EVENT_FSRV,
        @offsetOf(c.arcan_fsrvevent, "video"),
        @sizeOf(arcan_vobj_id),
        @as(?*anyopaque, @ptrCast(&vid_val)),
        @offsetOf(c.arcan_fsrvevent, "otag"),
        @sizeOf(@TypeOf(@as(c.arcan_fsrvevent, undefined).otag)),
        @as(?*anyopaque, @ptrCast(&ref_val)),
    );

    return 0;
}

// ---------------------------------------------------------------------------
// 22. targetpacify (C:7982-8006)
// ---------------------------------------------------------------------------
fn targetpacify(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 1, &vobj);

    if (vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV or vobj.*.feed.state.ptr == null) {
        c.arcan_fatal("target_pacify(), specified vid (arg 1) not " ++
            "associated with a frameserver.");
    }

    const fsrv: *c.arcan_frameserver = @ptrCast(@alignCast(vobj.*.feed.state.ptr));
    const mask = luaL_optbnumber(ctx, 2, true);

    if (mask) {
        @as(*isize, @ptrCast(@alignCast(@constCast(&fsrv.tag)))).* = @as(isize, @bitCast(@as(c_long, c.LUA_NOREF)));

        _ = c.arcan_frameserver_free(fsrv);
        vobj.*.feed.ffunc = c.FFUNC_NULLFRAME;
        vobj.*.feed.state.ptr = null;
        vobj.*.feed.state.tag = c.ARCAN_TAG_IMAGE;
    } else {
        _ = c.arcan_frameserver_free(fsrv);
    }

    return 0;
}

// ---------------------------------------------------------------------------
// 23. targetportcfg (C:8008-8027)
// ---------------------------------------------------------------------------
fn targetportcfg(ctx: ?*c.lua_State) callconv(.c) c_int {
    const tgt = luaL_checkvid(ctx, 1, null);
    const tgtport: c_uint = @as(c_uint, @bitCast(@as(c_int, @truncate(c.luaL_checkinteger(ctx, 2)))));
    const tgtkind: c_uint = @as(c_uint, @bitCast(@as(c_int, @truncate(c.luaL_checkinteger(ctx, 3)))));

    var ev = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_SETIODEV));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = @as(i32, @bitCast(tgtport));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = @as(i32, @bitCast(tgtkind));

    _ = tgtevent(tgt, ev);
    return 0;
}

// ---------------------------------------------------------------------------
// 24. layout_tonum (C:8029-8040)
// ---------------------------------------------------------------------------
fn layout_tonum(layout: [*c]const u8) c_int {
    if (layout == null or c.strcmp(layout, "hRGB") == 0)
        return 0
    else if (c.strcmp(layout, "hBGR") == 0)
        return 1
    else if (c.strcmp(layout, "vRGB") == 0)
        return 2
    else if (c.strcmp(layout, "vBGR") == 0)
        return 3;
    return 0;
}

// ---------------------------------------------------------------------------
// 25. targetgeohint (C:8042-8085)
// ---------------------------------------------------------------------------
fn targetgeohint(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const tgt = luaL_checkvid(ctx, 1, &vobj);

    if (vobj.*.feed.state.ptr == null or vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV) {
        c.arcan_fatal("target_geohint() -- " ++ FATAL_MSG_FRAMESERV);
    }

    const country = c.luaL_checklstring(ctx, 4, null);
    const written = c.luaL_checklstring(ctx, 5, null);
    const spoken = c.luaL_checklstring(ctx, 6, null);

    if (c.strlen(country) != 3)
        c.arcan_fatal("target_geohint(country) - expected ISO-3166-1-alpha3");

    if (c.strlen(written) != 3)
        c.arcan_fatal("target_geohint(written language) - expected ISO-639-2-alpha 3");

    if (c.strlen(spoken) != 3)
        c.arcan_fatal("target_geohint(spoken language) - expected ISO-639-2-alpha 3");

    var outev = arcan_event.zeroes();
    outev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_GEOHINT));
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].fv = @as(f32, @floatCast(c.luaL_checknumber(ctx, 1)));
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].fv = @as(f32, @floatCast(c.luaL_checknumber(ctx, 2)));
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].fv = @as(f32, @floatCast(c.luaL_checknumber(ctx, 3)));
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].cv = .{ country[0], country[1], country[2], 0 };
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].cv = .{ spoken[0], spoken[1], spoken[2], 0 };
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[5].cv = .{ written[0], written[1], written[2], 0 };
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[6].iv = @as(c_int, @intFromFloat(c.luaL_checknumber(ctx, 7)));

    _ = tgtevent(tgt, outev);
    return 0;
}

// ---------------------------------------------------------------------------
// 26. targetfonthint (C:8087-8158)
// ---------------------------------------------------------------------------
fn targetfonthint(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const tgt = luaL_checkvid(ctx, 1, &vobj);
    {
        const f = c.fopen("/tmp/arcan_lua_trace.log", "a");
        if (f != null) {
            _ = c.fprintf(f, "target_fonthint called vid=%lld\n", @as(c_longlong, @intCast(tgt)));
            _ = c.fclose(f);
        }
    }

    if (vobj.*.feed.state.ptr == null or vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV) {
        c.arcan_fatal("target_fonthint() -- " ++ FATAL_MSG_FRAMESERV);
    }

    const fsrv: *c.arcan_frameserver = @ptrCast(@alignCast(vobj.*.feed.state.ptr));

    var numind: c_int = 2;
    var fd: c_int = BADFD;
    var fd_owned: bool = false;

    // some cases implies 'change current font size or hinting without
    // changing font', hence why we begin with an optional string arg.
    if (c.lua_type(ctx, numind) == c.LUA_TSTRING) {
        const instr = c.luaL_checklstring(ctx, numind, null);
        numind += 1;
        if (c.strcmp(instr, ".default") == 0) {
            // arcan_video_fontdefaults returns a BORROWED handle into
            // font_cache; do not close it later. Bug 0125: an unconditional
            // close at the end of this function was destroying the cache's
            // reference and the next set_font_slot would EBADF on a stale fd.
            c.arcan_video_fontdefaults(&fd, null, null);
        } else {
            fd = BADFD;
            const fname = findresource(
                instr,
                @as(c_uint, @bitCast(c.RESOURCE_SYS_FONT)),
                @as(c_uint, @bitCast(c.ARES_FILE | c.ARES_RDONLY)),
                &fd,
            );
            c.arcan_mem_free(@as(?*anyopaque, @ptrCast(fname)));
            if (BADFD == fd) {
                c.lua_pushboolean(ctx, 0);
                return 1;
            }
            fd_owned = true;
        }
    }

    const sz: f32 = @as(f32, @floatCast(c.luaL_checknumber(ctx, numind)));
    const hint: c_int = @as(c_int, @intFromFloat(c.luaL_checknumber(ctx, numind + 1)));
    const slot: c_int = @intFromBool(luaL_optbnumber(ctx, numind + 2, false));

    var outev = arcan_event.zeroes();
    outev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_FONTHINT));
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = if (fd != BADFD) @as(c_int, 1) else @as(c_int, 0);
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].fv = sz;
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = hint;
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv = slot;

    // update the font reference data inside the frameserver as well
    const send_dh = slot == 0 and sz != fsrv.desc.text.szmm and
        fsrv.desc.hint.last.unnamed_0.unnamed_0.unnamed_0.tgt.kind == @as(c_uint, @bitCast(c.TARGET_COMMAND_DISPLAYHINT));

    // this may duplicate the fd in order to save for later
    _ = c.arcan_frameserver_setfont(fsrv, fd, sz, hint, slot);

    if (send_dh)
        _ = c.platform_fsrv_pushevent(fsrv, &fsrv.desc.hint.last);

    if (fd != BADFD) {
        const pfd_rc = c.platform_fsrv_pushfd(fsrv, &outev, fd);
        // H9 partial mitigation: yield between pushfd and close so the kernel
        // has a chance to fully process the SCM_RIGHTS enqueue. Combined
        // with H19 (watchdog peek disabled on child side) gives ~45% success
        // vs ~4% baseline.
        {
            const sched_yield = @extern(*const fn () callconv(.c) c_int, .{ .name = "sched_yield" });
            _ = sched_yield();
        }
        {
            const ff = c.fopen("/tmp/arcan_lua_trace.log", "a");
            if (ff != null) {
                _ = c.fprintf(ff, "target_fonthint pushfd vid=%lld fd=%d rc=%d (ioevs[1]=%d)\n",
                    @as(c_longlong, @intCast(tgt)), fd, pfd_rc,
                    outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv);
                _ = c.fclose(ff);
            }
        }
        c.lua_pushboolean(ctx, pfd_rc);
        if (fd_owned) _ = c.close(fd);
    } else {
        {
            const ff = c.fopen("/tmp/arcan_lua_trace.log", "a");
            if (ff != null) {
                _ = c.fprintf(ff, "target_fonthint (no fd) vid=%lld (ioevs[1]=%d)\n",
                    @as(c_longlong, @intCast(tgt)),
                    outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv);
                _ = c.fclose(ff);
            }
        }
        c.lua_pushboolean(ctx, @intFromBool(c.ARCAN_OK == c.platform_fsrv_pushevent(fsrv, &outev)));
    }

    c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(fsrv.desc.text.cellw)));
    c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(fsrv.desc.text.cellh)));

    return 3;
}

// ---------------------------------------------------------------------------
// 27. xlt_dev (C:8161-8172)
// ---------------------------------------------------------------------------
fn xlt_dev(inv: c_int) c_int {
    return switch (inv) {
        DEVICE_DIRECT => 1,
        DEVICE_LOST => 2,
        else => 0,
    };
}

// ---------------------------------------------------------------------------
// 28. pthr_waiter (C:8174-8188)
// ---------------------------------------------------------------------------
fn pthr_waiter(src: ?*anyopaque) callconv(.c) ?*anyopaque {
    const pid: *c.pid_t = @ptrCast(@alignCast(src));
    while (true) {
        var status: c_int = 0;
        const rc = c.waitpid(pid.*, &status, 0);
        if (rc == -1 and (if (is_freestanding) c._errno().* else std.c._errno().*) == c.ECHILD)
            break;
        if (c.WIFEXITED(status))
            break;
    }
    c.free(@as(?*anyopaque, @ptrCast(pid)));
    return null;
}

// ---------------------------------------------------------------------------
// 29. targetdevhint (C:8190-8319)
// ---------------------------------------------------------------------------
fn targetdevhint(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 1, &vobj);
    if (vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV)
        c.arcan_fatal("target_devicehint(), vid not connected to a frameserver\n");

    const fsrv: *c.arcan_frameserver = @ptrCast(@alignCast(vobj.*.feed.state.ptr));

    const typ = c.lua_type(ctx, 2);

    // integer- type, switch physical device
    if (typ == c.LUA_TNUMBER) {
        const num: c_int = @as(c_int, @intFromFloat(c.luaL_checknumber(ctx, 2)));

        // negative number: just switch mode of operation
        if (num < 0) {
            var dev_ev = arcan_event.zeroes();
            dev_ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
            dev_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_DEVICE_NODE));
            dev_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = BADFD;
            dev_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = 1;
            dev_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].iv = xlt_dev(@as(c_int, @intFromFloat(
                c.luaL_optnumber(ctx, 3, @as(lua_Number, @floatFromInt(DEVICE_INDIRECT))),
            )));
            _ = c.platform_fsrv_pushevent(fsrv, &dev_ev);
        }
        // card- reference, extract device handle for the mode in question
        else {
            var method: c_int = 0;
            var buf_sz: usize = 0;
            var buf: [*c]u8 = undefined;
            const fd = c.platform_video_cardhandle(num, &method, &buf_sz, &buf);
            if (fd == -1) {
                c.arcan_warning("target_devicehint(), invalid card index specified\n");
                return 0;
            }

            if (buf_sz > @sizeOf(@TypeOf(@as(c.arcan_tgtevent, undefined).unnamed_0.message))) {
                c.arcan_warning("target_devicehint(). clamping modifier size (%zu)\n");
                buf_sz = @sizeOf(@TypeOf(@as(c.arcan_tgtevent, undefined).unnamed_0.message));
            }

            var ev = arcan_event.zeroes();
            ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_DEVICE_NODE));
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = 1;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].iv = xlt_dev(@as(c_int, @intFromFloat(
                c.luaL_optnumber(ctx, 3, @as(lua_Number, @floatFromInt(DEVICE_INDIRECT))),
            )));
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = method;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv = @as(i32, @bitCast(@as(c_uint, @truncate(buf_sz))));

            _ = c.memcpy(
                @as(?*anyopaque, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
                @as(?*const anyopaque, @ptrCast(buf)),
                buf_sz,
            );
            c.arcan_mem_free(@as(?*anyopaque, @ptrCast(buf)));
            _ = c.platform_fsrv_pushfd(fsrv, &ev, fd);
        }
    }
    // string reference, switch render-node
    else if (typ == c.LUA_TSTRING) {
        const cpath = c.luaL_checklstring(ctx, 2, null);
        const force = luaL_optbnumber(ctx, 3, false);

        var outev = arcan_event.zeroes();
        outev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
        outev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_DEVICE_NODE));
        outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = BADFD;
        outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = if (force) @as(c_int, 2) else @as(c_int, 4);
        outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].uiv = @as(u32, @truncate(fsrv.guid[0] & 0xffffffff));
        outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].uiv = @as(u32, @truncate(fsrv.guid[0] >> 32));
        outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].uiv = @as(u32, @truncate(fsrv.guid[1] & 0xffffffff));
        outev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[5].uiv = @as(u32, @truncate(fsrv.guid[1] >> 32));

        // we require a real string for the connection path if forced
        if (force) {
            if (c.strlen(cpath) == 0)
                c.arcan_fatal("target_devicehint(), forced migration connpath len == 0\n");

            // spawn a waitpid- thread to reap the child process after migration
            if (fsrv.child != BROKEN_PROCESS_HANDLE) {
                var jattr: c.pthread_attr_t = undefined;
                var pthr: c.pthread_t = undefined;
                _ = c.pthread_attr_init(&jattr);
                _ = c.pthread_attr_setdetachstate(&jattr, c.PTHREAD_CREATE_DETACHED);
                const pid_ptr: *c.pid_t = @ptrCast(@alignCast(c.malloc(@sizeOf(c.pid_t))));
                pid_ptr.* = fsrv.child;
                @as(*c.pid_t, @ptrCast(@alignCast(@constCast(&fsrv.child)))).* = BROKEN_PROCESS_HANDLE;
                _ = c.pthread_create(&pthr, null, &pthr_waiter, @as(?*anyopaque, @ptrCast(pid_ptr)));
            }
        }

        const msg_size = @sizeOf(@TypeOf(@as(c.arcan_tgtevent, undefined).unnamed_0.message)) /
            @sizeOf(u8);
        if (c.strlen(cpath) > msg_size) {
            c.arcan_warning("address length exceeds boundary, truncated");
        }
        _ = c.snprintf(
            @as([*c]u8, @ptrCast(&outev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
            msg_size,
            "%s",
            cpath,
        );

        // for networked connections to work the process needs access to the state store
        if (c.strncmp(cpath, "a12://", 6) == 0 or
            c.strncmp(cpath, "a12s://", 6) == 0 or
            c.strrchr(cpath, '@') != null)
        {
            const nsp = c.arcan_expand_resource("a12", @as(c_uint, @bitCast(c.RESOURCE_SYS_APPLSTATE)));
            const state_fd = c.open(nsp, c.O_RDONLY | c.O_DIRECTORY);

            var a12_ev = arcan_event.zeroes();
            a12_ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
            a12_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_DEVICE_NODE));
            a12_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = BADFD;
            a12_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = 1;
            a12_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = 3;

            _ = c.platform_fsrv_pushfd(fsrv, &a12_ev, state_fd);
            _ = c.close(state_fd);
        }

        _ = c.platform_fsrv_pushevent(fsrv, &outev);
    } else {
        c.arcan_fatal("target_devicehint(), argument misuse");
    }

    return 0;
}

// ---------------------------------------------------------------------------
// 30. targetdisphint (C:8322-8451)
// ---------------------------------------------------------------------------
fn targetdisphint(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const tgt = luaL_checkvid(ctx, 1, &vobj);
    {
        const f = c.fopen("/tmp/arcan_lua_trace.log", "a");
        if (f != null) {
            _ = c.fprintf(f, "target_displayhint called vid=%lld\n", @as(c_longlong, @intCast(tgt)));
            _ = c.fclose(f);
        }
    }

    // non fsrv vid — warn and ignore (handover lifecycle can leave overlay vids without fsrv tag)
    if (vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV or vobj.*.feed.state.ptr == null) {
        c.arcan_warning("target_displayhint() - vid is not a frameserver, ignoring\n");
        return 0;
    }
    const fsrv: *c.arcan_frameserver = @ptrCast(@alignCast(vobj.*.feed.state.ptr));

    var width: c_int = @as(c_int, @intFromFloat(c.luaL_checknumber(ctx, 2)));
    var height: c_int = @as(c_int, @intFromFloat(c.luaL_checknumber(ctx, 3)));
    const cont: c_int = @as(c_int, @intFromFloat(c.luaL_optnumber(ctx, 4, 128)));
    var cookie: u32 = 0;

    // clamp to not have client propagate illegal dimensions
    width = if (width > c.ARCAN_SHMPAGE_MAXW) c.ARCAN_SHMPAGE_MAXW else width;
    height = if (height > c.ARCAN_SHMPAGE_MAXH) c.ARCAN_SHMPAGE_MAXH else height;

    var phy_lay: c_int = 0;
    var ppcm: f32 = 0;

    const typ = c.lua_type(ctx, 5);

    if (typ == c.LUA_TNUMBER and @as(lua_Number, @floatFromInt(c.ARCAN_VIDEO_WORLDID)) == c.luaL_checknumber(ctx, 5)) {
        // WORLDID => use platform display dimensions
        const mmode = c.platform_video_dimensions();
        const lw: c_int = @as(c_int, @bitCast(@as(c_uint, @truncate(mmode.width))));
        var phy_w: c_int = @as(c_int, @bitCast(@as(c_uint, @truncate(mmode.phy_width))));
        if (lw != 0 and phy_w != 0) {
            ppcm = 10.0 * (@as(f32, @floatFromInt(lw)) / @as(f32, @floatFromInt(phy_w)));
        }
        phy_w = @as(c_int, @bitCast(@as(c_uint, @truncate(mmode.width))));
        phy_lay = layout_tonum(mmode.subpixel);

        var out_ev = arcan_event.zeroes();
        out_ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
        out_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_OUTPUTHINT));
        out_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = @as(i32, @bitCast(@as(c_uint, @truncate(mmode.width))));
        out_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = @as(i32, @bitCast(@as(c_uint, @truncate(mmode.height))));
        out_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].iv = @as(i32, @intCast(mmode.refresh));
        out_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = 32;
        out_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv = 32;
        _ = tgtevent(tgt, out_ev);
    } else if (typ == c.LUA_TNUMBER) {
        // vid reference => get cookie from frameserver
        var vobj2: [*c]c.arcan_vobject = undefined;
        _ = luaL_checkvid(ctx, 5, &vobj2);
        if (vobj2.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV) {
            c.arcan_warning(
                "target_displayhint() - vid reference not connected to frameserver",
            );
        } else {
            const fsrv2: *c.arcan_frameserver = @ptrCast(@alignCast(vobj2.*.feed.state.ptr));
            cookie = fsrv2.cookie;
        }
    } else if (typ == c.LUA_TTABLE) {
        const nv = intblfloat(ctx, 5, "ppcm");
        if (nv > 10) {
            ppcm = nv;
        } else if (nv > 0) {
            c.arcan_warning("target_displayhint(), display table provided " ++
                "but with broken / bad ppcm field (%.1f), ignoring\n", @as(f64, nv));
        }

        const tbl_width = intblint(ctx, 5, "width");
        const tbl_height = intblint(ctx, 5, "height");
        var refresh = intblint(ctx, 5, "refresh");
        var minw = intblint(ctx, 5, "min_width");
        var minh = intblint(ctx, 5, "min_height");

        if (refresh == -1) refresh = 60;
        if (minw == -1) minw = 32;
        if (minh == -1) minh = 32;

        if (tbl_width > 0 and tbl_height > 0) {
            var out_ev2 = arcan_event.zeroes();
            out_ev2.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
            out_ev2.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_OUTPUTHINT));
            out_ev2.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = tbl_width;
            out_ev2.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = tbl_height;
            out_ev2.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].iv = refresh;
            out_ev2.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = minw;
            out_ev2.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv = minh;
            _ = tgtevent(tgt, out_ev2);
        }

        phy_lay = layout_tonum(intblstr(ctx, 5, "subpixel_layout"));
    }

    if (width < 0 or height < 0)
        c.arcan_fatal("target_disphint(%d, %d), " ++
            "display dimensions must be >= 0", width, height);

    // forward the rendering relevant information to the frameserver
    c.arcan_frameserver_displayhint(
        fsrv,
        @as(usize, @bitCast(@as(c_long, width))),
        @as(usize, @bitCast(@as(c_long, height))),
        ppcm,
    );

    var ev = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_DISPLAYHINT));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = width;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = height;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].iv = cont;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = phy_lay;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].fv = ppcm;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[5].iv = @as(i32, @bitCast(@as(c_uint, @truncate(fsrv.desc.text.cellw))));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[6].iv = @as(i32, @bitCast(@as(c_uint, @truncate(fsrv.desc.text.cellh))));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[7].uiv = cookie;

    fsrv.desc.hint.last = ev;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.timestamp = @as(u64, @truncate(c.arcan_timemillis()));
    _ = tgtevent(tgt, ev);

    c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(fsrv.desc.text.cellw)));
    c.lua_pushnumber(ctx, @as(lua_Number, @floatFromInt(fsrv.desc.text.cellh)));

    return 2;
}

// ---------------------------------------------------------------------------
// 31. get_vid_token (C:8453-8467)
// ---------------------------------------------------------------------------
fn get_vid_token(ctx: ?*c.lua_State, ind: c_int) c_uint {
    var vobj: [*c]c.arcan_vobject = undefined;
    const parent = luaL_checkvid(ctx, ind, &vobj);

    if (parent == c.ARCAN_VIDEO_WORLDID)
        return 0;

    if (vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV) {
        c.arcan_fatal("target_anchorhint(vid, ANCHORHINT_SEGMENT, " ++
            ">parent<, ...) not connected to a frameserver");
    }
    const fsrv: *c.arcan_frameserver = @ptrCast(@alignCast(vobj.*.feed.state.ptr));
    return fsrv.cookie;
}

// ---------------------------------------------------------------------------
// 32. targetanchor (C:8469-8520)
// ---------------------------------------------------------------------------
fn targetanchor(ctx: ?*c.lua_State) callconv(.c) c_int {
    var ev = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_ANCHORHINT));

    var vobj: [*c]c.arcan_vobject = undefined;
    const vid = luaL_checkvid(ctx, 1, &vobj);

    if (vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV) {
        c.arcan_fatal("target_anchorhint(>vid<, ...) not connected to a frameserver");
    }

    const typ: c_int = @as(c_int, @intFromFloat(c.luaL_checknumber(ctx, 2)));
    var coord_ofs: c_int = 4;

    switch (typ) {
        ANCHORHINT_SEGMENT => {
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].uiv = get_vid_token(ctx, 3);
        },
        ANCHORHINT_PROXY => {
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].uiv = get_vid_token(ctx, 3);
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].uiv = get_vid_token(ctx, 4);
        },
        ANCHORHINT_EXTERNAL => {
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].uiv = @as(u32, @intFromFloat(c.luaL_checknumber(ctx, 3)));
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[5].iv = 1;
            coord_ofs = 5;
        },
        ANCHORHINT_PROXY_EXTERNAL => {
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].uiv = @as(u32, @intFromFloat(c.luaL_checknumber(ctx, 3)));
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].uiv = @as(u32, @intFromFloat(c.luaL_checknumber(ctx, 4)));
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[5].iv = 1;
            coord_ofs = 5;
        },
        else => {
            c.arcan_fatal("target_anchorhint(vid, >type<, ..) invalid type value");
        },
    }

    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].uiv = @as(u32, @intFromFloat(c.luaL_checknumber(ctx, coord_ofs + 0)));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].uiv = @as(u32, @intFromFloat(c.luaL_checknumber(ctx, coord_ofs + 1)));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].uiv = @as(u32, @intFromFloat(c.luaL_optnumber(ctx, coord_ofs + 2, 0)));

    _ = tgtevent(vid, ev);
    return 0;
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part9.zig
// ══════════════════════════════════════════════════════════════════════

// Zig port of engine/arcan_lua.c lines 8522-9516
// Functions: targetgraph, targetcoreopt, targetparent, targetseek,
//   updateflag, targetflags, targetsynchronous, targetverbose,
//   targetskipmodecfg, targetbond, targetrestore, targetstepframe,
//   targetsnapshot, targetreset, spawn_subsegment, targetaccept_lwa,
//   targetaccept, targetalloc, targetlaunch



// Type aliases

const LAUNCH_EXTERNAL: c_int = 0;
const LAUNCH_INTERNAL: c_int = 1;

// External symbols

// Declared in other parts

// luactx state — defined in another part, referenced here

// Inline Lua helpers

// target_flags enum
const TARGET_FLAG_SYNCHRONOUS: c_int = 1;
const TARGET_FLAG_NO_ALPHA_UPLOAD: c_int = 2;
const TARGET_FLAG_VERBOSE: c_int = 3;
const TARGET_FLAG_VSTORE_SYNCH: c_int = 4;
const TARGET_FLAG_AUTOCLOCK: c_int = 5;
const TARGET_FLAG_NO_BUFFERPASS: c_int = 6;
const TARGET_FLAG_ALLOW_CM: c_int = 7;
const TARGET_FLAG_ALLOW_HDR: c_int = 8;
const TARGET_FLAG_ALLOW_INPUT: c_int = 9;
const TARGET_FLAG_ALLOW_GPUAUTH: c_int = 10;
const TARGET_FLAG_LIMIT_SIZE: c_int = 11;
const TARGET_FLAG_SYNCH_SIZE: c_int = 12;
const TARGET_FLAG_NO_ADOPT: c_int = 13;
const TARGET_FLAG_DRAIN_QUEUE: c_int = 14;
const TARGET_FLAG_ENDM: c_int = 15;

// ---------------------------------------------------------------------------
// targetgraph (C:8522) — target_graphmode
// ---------------------------------------------------------------------------
fn targetgraph(ctx: ?*c.lua_State) callconv(.c) c_int {
    {
        const Count = struct { var n: u64 = 0; };
        Count.n += 1;
        // Only log first graphmode in a burst to avoid spam.
        if (Count.n % 70 == 1) {
            const tgt_peek: c_int = @as(c_int, @intFromFloat(c.luaL_checknumber(ctx, 1)));
            const f = c.fopen("/tmp/arcan_lua_trace.log", "a");
            if (f != null) {
                _ = c.fprintf(f, "target_graphmode called vid=%d seq=%llu (1st of batch)\n",
                    tgt_peek, Count.n);
                _ = c.fclose(f);
            }
        }
    }
    var ev = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_GRAPHMODE));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = @as(i32, @truncate(c.luaL_checkinteger(ctx, 2)));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].fv = @as(f32, @floatCast(c.luaL_optnumber(ctx, 3, 0.0)));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].fv = @as(f32, @floatCast(c.luaL_optnumber(ctx, 4, 0.0)));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].fv = @as(f32, @floatCast(c.luaL_optnumber(ctx, 5, 0.0)));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].fv = @as(f32, @floatCast(c.luaL_optnumber(ctx, 6, 0.0)));

    _ = tgtevent(luaL_checkvid(ctx, 1, null), ev);

    return 0;
}

// ---------------------------------------------------------------------------
// targetcoreopt (C:8541) — target_coreopt
// ---------------------------------------------------------------------------
fn targetcoreopt(ctx: ?*c.lua_State) callconv(.c) c_int {
    const tgt = luaL_checkvid(ctx, 1, null);
    var ev = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_COREOPT));

    ev.unnamed_0.unnamed_0.unnamed_0.tgt.code = @as(c_int, @intFromFloat(c.luaL_checknumber(ctx, 2)));
    const msg = c.luaL_checklstring(ctx, 3, null);

    _ = c.snprintf(
        @as([*c]u8, @ptrCast(@alignCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message))),
        @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
        "%s",
        msg,
    );
    _ = tgtevent(tgt, ev);

    return 0;
}

// ---------------------------------------------------------------------------
// targetparent (C:8560) — target_parent
// ---------------------------------------------------------------------------
fn targetparent(ctx: ?*c.lua_State) callconv(.c) c_int {
    const tgt = luaL_checkvid(ctx, 1, null);
    const state = c.arcan_video_feedstate(tgt);

    if (!(state != null and state.*.tag == c.ARCAN_TAG_FRAMESERV and state.*.ptr != null)) {
        lua_pushvid(ctx, c.ARCAN_EID);
    } else {
        const fsrv: *c.arcan_frameserver = @ptrCast(@alignCast(state.*.ptr));
        lua_pushvid(ctx, fsrv.parent.vid);
    }

    return 1;
}

// ---------------------------------------------------------------------------
// targetseek (C:8577) — target_seek
// ---------------------------------------------------------------------------
fn targetseek(ctx: ?*c.lua_State) callconv(.c) c_int {
    const tgt = luaL_checkvid(ctx, 1, null);
    const val: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    const relative = luaL_optbnumber(ctx, 3, true);
    const time_flag = luaL_optbnumber(ctx, 4, true);

    _ = c.arcan_video_feedstate(tgt);

    if (time_flag) {
        var ev = arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_SEEKTIME));

        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = @intFromBool(relative);
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].fv = val;
        _ = tgtevent(tgt, ev);
    } else {
        var ev = arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_SEEKCONTENT));

        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = @intFromBool(relative);
        if (relative) {
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = @as(i32, @intFromFloat(val));
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].iv = @as(i32, @intFromFloat(c.luaL_optnumber(ctx, 5, 0)));
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].fv = @as(f32, @floatCast(c.luaL_optnumber(ctx, 6, 0)));
        } else {
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].fv = val;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].fv = @as(f32, @floatCast(c.luaL_optnumber(ctx, 5, -1)));
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].fv = @as(f32, @floatCast(c.luaL_optnumber(ctx, 6, -1)));
        }
        _ = tgtevent(tgt, ev);
    }

    return 0;
}

// ---------------------------------------------------------------------------
// updateflag (C:8639) — helper for targetflags/targetsynchronous/targetverbose
// ---------------------------------------------------------------------------
fn updateflag(vid: arcan_vobj_id, flag: c_int, toggle: bool) void {
    const state = c.arcan_video_feedstate(vid);

    if (!(state != null and state.*.tag == c.ARCAN_TAG_FRAMESERV and state.*.ptr != null)) {
        c.arcan_warning("updateflag() vid(%lld) is not connected to a frameserver\n", @as(c_longlong, vid));
        return;
    }

    const fsrv: *c.arcan_frameserver = @ptrCast(@alignCast(state.*.ptr));

    const fptr: ?*anyopaque = @ptrCast(fsrv);
    switch (flag) {
        TARGET_FLAG_SYNCHRONOUS => {
            fsrv_helper_set_flag_explicit(fptr, toggle);
        },
        TARGET_FLAG_VERBOSE => {
            fsrv.desc.callback_framestate = toggle;
        },
        TARGET_FLAG_VSTORE_SYNCH => {
            fsrv_helper_set_flag_local_copy(fptr, toggle);
        },
        TARGET_FLAG_NO_ALPHA_UPLOAD => {
            fsrv_helper_set_flag_no_alpha_copy(fptr, toggle);
        },
        TARGET_FLAG_AUTOCLOCK => {
            fsrv_helper_set_flag_autoclock(fptr, toggle);
        },
        TARGET_FLAG_ALLOW_GPUAUTH => {
            fsrv_helper_set_flag_gpu_auth(fptr, toggle);
        },
        TARGET_FLAG_NO_BUFFERPASS => {
            fsrv.vstream.dead = toggle;
        },
        TARGET_FLAG_NO_ADOPT => {
            fsrv_helper_set_flag_no_adopt(fptr, toggle);
        },
        TARGET_FLAG_ALLOW_CM => {
            if (toggle) {
                fsrv.metamask |= @as(c_uint, @bitCast(c.SHMIF_META_CM));
            } else {
                fsrv.metamask &= @as(c_uint, @bitCast(~@as(c_int, c.SHMIF_META_CM)));
            }
        },
        TARGET_FLAG_ALLOW_HDR => {
            if (toggle) {
                fsrv.metamask |= @as(c_uint, @bitCast(c.SHMIF_META_HDR));
            } else {
                fsrv.metamask &= @as(c_uint, @bitCast(~@as(c_int, c.SHMIF_META_HDR)));
            }
        },
        TARGET_FLAG_ALLOW_INPUT => {
            const event_io_val: c_int = c.EVENT_IO;
            if (toggle) {
                fsrv.queue_mask |= event_io_val;
            } else {
                fsrv.queue_mask &= ~event_io_val;
            }
        },
        TARGET_FLAG_LIMIT_SIZE => {
            // handled in targetflags directly
        },
        TARGET_FLAG_SYNCH_SIZE => {
            fsrv_helper_set_flag_rz_ack(fptr, toggle);
        },
        TARGET_FLAG_DRAIN_QUEUE => {
            if (toggle) {
                fsrv.xfer_sat = @as(f32, @floatCast(-1.0));
            } else {
                fsrv.xfer_sat = @as(f32, @floatCast(0.5));
            }
        },
        TARGET_FLAG_ENDM => {},
        else => {},
    }
}

// ---------------------------------------------------------------------------
// targetflags (C:8726) — target_flags
// ---------------------------------------------------------------------------
fn targetflags(ctx: ?*c.lua_State) callconv(.c) c_int {
    const tgt = luaL_checkvid(ctx, 1, null);
    const flag: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));
    if (flag < TARGET_FLAG_SYNCHRONOUS or flag >= TARGET_FLAG_ENDM)
        c.arcan_fatal("target_flags() unknown flag value (%d)\n", flag);

    if (flag == TARGET_FLAG_LIMIT_SIZE) {
        const state = c.arcan_video_feedstate(tgt);
        const max_w: usize = @intFromFloat(c.luaL_checknumber(ctx, 3));
        const max_h: usize = @intFromFloat(c.luaL_checknumber(ctx, 4));
        if (!(state != null and state.*.tag == c.ARCAN_TAG_FRAMESERV and state.*.ptr != null)) {
            c.arcan_warning("updateflag() vid(%lld) is not connected to a frameserver\n", @as(c_longlong, tgt));
        } else {
            const s: *c.arcan_frameserver = @ptrCast(@alignCast(state.*.ptr));
            s.max_w = max_w;
            s.max_h = max_h;
        }
    } else {
        const toggle = luaL_optbnumber(ctx, 3, true);
        updateflag(tgt, flag, toggle);
    }
    return 0;
}

// ---------------------------------------------------------------------------
// targetsynchronous (C:8760) — target_synchronous
// ---------------------------------------------------------------------------
fn targetsynchronous(ctx: ?*c.lua_State) callconv(.c) c_int {
    const tgt = luaL_checkvid(ctx, 1, null);
    const toggle = luaL_optbnumber(ctx, 2, true);
    updateflag(tgt, TARGET_FLAG_SYNCHRONOUS, toggle);
    return 0;
}

// ---------------------------------------------------------------------------
// targetverbose (C:8769) — target_verbose
// ---------------------------------------------------------------------------
fn targetverbose(ctx: ?*c.lua_State) callconv(.c) c_int {
    const tgt = luaL_checkvid(ctx, 1, null);
    const toggle = luaL_optbnumber(ctx, 2, true);
    updateflag(tgt, TARGET_FLAG_VERBOSE, toggle);
    return 0;
}

// ---------------------------------------------------------------------------
// targetskipmodecfg (C:8778) — target_framemode
// ---------------------------------------------------------------------------
fn targetskipmodecfg(ctx: ?*c.lua_State) callconv(.c) c_int {
    const tgt = luaL_checkvid(ctx, 1, null);
    const skipval: c_int = @as(c_int, @truncate(c.luaL_checkinteger(ctx, 2)));
    const skiparg: c_int = @as(c_int, @truncate(c.luaL_optinteger(ctx, 3, 0)));
    const preaud: c_int = @as(c_int, @truncate(c.luaL_optinteger(ctx, 4, 0)));
    const skipdbg1: c_int = @as(c_int, @truncate(c.luaL_optinteger(ctx, 5, 0)));
    const skipdbg2: c_int = @as(c_int, @truncate(c.luaL_optinteger(ctx, 6, 0)));

    if (skipval < -1) {
        return 0;
    }

    var ev = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_FRAMESKIP));

    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = skipval;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = skiparg;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].iv = preaud;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = skipdbg1;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv = skipdbg2;

    _ = tgtevent(tgt, ev);

    return 0;
}

// ---------------------------------------------------------------------------
// targetbond (C:8809) — bond_target
// ---------------------------------------------------------------------------
fn targetbond(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj_a: [*c]c.arcan_vobject = undefined;
    var vobj_b: [*c]c.arcan_vobject = undefined;

    _ = luaL_checkvid(ctx, 1, &vobj_a);
    _ = luaL_checkvid(ctx, 2, &vobj_b);

    if (vobj_a.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV or
        vobj_b.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV)
        c.arcan_fatal("bond_target(), both arguments must be valid frameservers.\n");

    const val = luaL_optbnumber(ctx, 3, false);
    const descr_a = c.luaL_optlstring(ctx, 4, "*", null);
    const descr_b = c.luaL_optlstring(ctx, 5, descr_a, null);

    var pair: [2]c_int = undefined;
    if (c.pipe(@as([*c]c_int, @ptrCast(&pair))) == -1) {
        c.arcan_warning("bond_target(), pipe pair failed. Reason: %s\n", c.strerror(c.__errno_location().*));
        return 0;
    }

    const fsrv_a: ?*c.arcan_frameserver = @ptrCast(@alignCast(vobj_a.*.feed.state.ptr));
    const fsrv_b: ?*c.arcan_frameserver = @ptrCast(@alignCast(vobj_b.*.feed.state.ptr));

    var ev = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(
        if (val) c.TARGET_COMMAND_BCHUNK_OUT else c.TARGET_COMMAND_STORE,
    ));

    _ = c.snprintf(
        @as([*c]u8, @ptrCast(@alignCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message))),
        @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
        "%s",
        descr_a,
    );

    _ = c.platform_fsrv_pushfd(fsrv_a, &ev, pair[1]);

    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(
        if (val) c.TARGET_COMMAND_BCHUNK_IN else c.TARGET_COMMAND_RESTORE,
    ));
    _ = c.snprintf(
        @as([*c]u8, @ptrCast(@alignCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message))),
        @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
        "%s",
        descr_b,
    );

    _ = c.platform_fsrv_pushfd(fsrv_b, &ev, pair[0]);

    _ = c.close(pair[0]);
    _ = c.close(pair[1]);

    return 0;
}

// ---------------------------------------------------------------------------
// targetrestore (C:8856) — restore_target
// ---------------------------------------------------------------------------
fn targetrestore(ctx: ?*c.lua_State) callconv(.c) c_int {
    const tgt = luaL_checkvid(ctx, 1, null);
    const snapkey = c.luaL_checklstring(ctx, 2, null);
    const descr = c.luaL_optlstring(ctx, 4, "octet-stream", null);

    const ns: c_int = @intFromFloat(c.luaL_optnumber(ctx, 3, @floatFromInt(c.RESOURCE_APPL_STATE)));
    var command: c_int = c.TARGET_COMMAND_RESTORE;

    // verify it's a frameserver we are sending to
    const state = c.arcan_video_feedstate(tgt);
    if (state == null or state.*.tag != c.ARCAN_TAG_FRAMESERV or state.*.ptr == null) {
        c.lua_pushboolean(ctx, 0);
        return 1;
    }

    // verify namespace for reading
    if (ns != c.RESOURCE_APPL_STATE) {
        command = c.TARGET_COMMAND_BCHUNK_IN;
    }

    // resolve from requested namespace, only accept files
    var fd: c_int = BADFD;
    const fname = findresource(
        snapkey,
        @as(c_uint, @bitCast(ns)),
        @as(c_uint, @bitCast(c.ARES_FILE | c.ARES_RDONLY)),
        &fd,
    );
    c.free(@as(?*anyopaque, @ptrCast(fname)));

    if (BADFD == fd) {
        c.arcan_warning("couldn't load / resolve (%s)\n", snapkey);
        c.lua_pushboolean(ctx, 0);
        return 1;
    }

    // send to recipient, close local handle
    const fsrv: ?*c.arcan_frameserver = @ptrCast(@alignCast(state.*.ptr));
    var ev = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(command));

    _ = c.snprintf(
        @as([*c]u8, @ptrCast(@alignCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message))),
        @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
        "%s",
        descr,
    );

    c.lua_pushboolean(ctx, @intFromBool(c.ARCAN_OK == c.platform_fsrv_pushfd(fsrv, &ev, fd)));
    _ = c.close(fd);

    return 1;
}

// ---------------------------------------------------------------------------
// targetstepframe (C:8905) — stepframe_target
// ---------------------------------------------------------------------------
fn targetstepframe(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const tgt = luaL_checkvid(ctx, 1, &vobj);
    const state = c.arcan_video_feedstate(tgt);
    const rtgt = c.arcan_vint_findrt(vobj);
    const fsrv: ?*c.arcan_frameserver = if (state.*.tag == c.ARCAN_TAG_FRAMESERV)
        @ptrCast(@alignCast(state.*.ptr))
    else
        null;

    const force_synch = luaL_optbnumber(ctx, 3, false);
    const nframes: c_int = @intFromFloat(c.luaL_optnumber(ctx, 2, 1));

    // [control frame and resize pacing]
    if (fsrv != null and rtgt == null) {
        const fs = fsrv.?;
        if (fsrv_helper_get_flag_rz_ack(@ptrCast(fs)) and nframes == 0) {
            if (fs.rz_known == 0) {
                return 0;
            }

            // force update / upload
            fs.rz_known += 1;
            _ = c.arcan_vint_pollfeed(tgt, true);
            return 0;
        }

        var ev = arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_STEPFRAME));
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = nframes;
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = @as(i32, @intFromFloat(c.luaL_optnumber(ctx, 3, 0)));
        _ = tgtevent(tgt, ev);
        c.lua_pushboolean(ctx, 1);
        return 1;
    }

    // request readback into a recordtarget, query / update dirty
    var x: c_int = @intFromFloat(c.luaL_optnumber(ctx, 4, -1));
    if (fsrv != null and x > -1) {
        const fs = fsrv.?;
        fs.desc.region_valid = false;
        var y: c_int = @intFromFloat(c.luaL_optnumber(ctx, 5, -1));
        var w: c_int = @intFromFloat(c.luaL_optnumber(ctx, 6, -1));
        var h: c_int = @intFromFloat(c.luaL_optnumber(ctx, 7, -1));
        if (x > @as(c_int, @bitCast(@as(c_uint, fs.desc.width))))
            x = 0;
        if (y < 0 or y > @as(c_int, @bitCast(@as(c_uint, fs.desc.height))))
            y = 0;

        if (w <= 0 or (x + w) > @as(c_int, @bitCast(@as(c_uint, fs.desc.width))))
            w = @as(c_int, @bitCast(@as(c_uint, fs.desc.width))) - x;

        if (h <= 0 or (y + h) > @as(c_int, @bitCast(@as(c_uint, fs.desc.height))))
            h = @as(c_int, @bitCast(@as(c_uint, fs.desc.height))) - y;

        fs.desc.region = c.arcan_shmif_region{
            .x1 = @as(u16, @bitCast(@as(c_short, @truncate(x)))),
            .y1 = @as(u16, @bitCast(@as(c_short, @truncate(y)))),
            .x2 = @as(u16, @bitCast(@as(c_short, @truncate(x + w)))),
            .y2 = @as(u16, @bitCast(@as(c_short, @truncate(y + h)))),
        };
        fs.desc.region_valid = true;
    }

    // FL_TEST(rtgt, TGTFL_READING) => (rtgt.*.flags & TGTFL_READING) > 0
    if (!((rtgt.*.flags & @as(c_uint, @bitCast(c.TGTFL_READING))) > 0)) {
        c.agp_request_readback(rtgt.*.color.*.vstore);
        rtgt.*.flags |= @as(c_uint, @bitCast(c.TGTFL_READING));
        rtgt.*.transfc +%= 1;
        c.lua_pushboolean(ctx, 1);
    } else {
        // need to communicate that we are stuck
        c.lua_pushboolean(ctx, 0);
    }

    // synchronous readback spin
    if (force_synch) {
        const start = c.arcan_timemillis();
        while ((rtgt.*.flags & @as(c_uint, @bitCast(c.TGTFL_READING))) > 0) {
            if (c.arcan_timemillis() -% start > 1000) {
                c.arcan_warning("pollreadback(), synch-readback safety timeout exceed\n");
                break;
            }
            c.arcan_vint_pollreadback(rtgt);
        }
    }

    return 1;
}

// ---------------------------------------------------------------------------
// targetsnapshot (C:9008) — snapshot_target
// ---------------------------------------------------------------------------
fn targetsnapshot(ctx: ?*c.lua_State) callconv(.c) c_int {
    const tgt = luaL_checkvid(ctx, 1, null);
    const snapkey = c.luaL_checklstring(ctx, 2, null);
    const descr = c.luaL_optlstring(ctx, 4, "octet-stream", null);

    const ns: c_int = @intFromFloat(c.luaL_optnumber(ctx, 3, @floatFromInt(c.RESOURCE_APPL_STATE)));
    var command: c_int = c.TARGET_COMMAND_STORE;

    // verify namespace for writing
    if (ns != c.RESOURCE_APPL_STATE) {
        if ((ns & (c.RESOURCE_APPL_TEMP | c.RESOURCE_APPL_SHARED | c.RESOURCE_NS_USER)) != 0) {
            command = c.TARGET_COMMAND_BCHUNK_OUT;
        } else {
            c.lua_pushboolean(ctx, 0);
            return 1;
        }
    }

    // verify frameserver state
    const state = c.arcan_video_feedstate(tgt);
    if (state == null or state.*.tag != c.ARCAN_TAG_FRAMESERV or state.*.ptr == null) {
        c.lua_pushboolean(ctx, 0);
        return 1;
    }
    const fsrv: ?*c.arcan_frameserver = @ptrCast(@alignCast(state.*.ptr));

    // resolve and grab descriptor
    var fd: c_int = -1;
    const fname = findresource(
        snapkey,
        @as(c_uint, @bitCast(ns)),
        @as(c_uint, @bitCast(c.ARES_FILE | c.ARES_CREATE)),
        &fd,
    );
    c.arcan_mem_free(@as(?*anyopaque, @ptrCast(fname)));

    if (-1 == fd) {
        c.lua_pushboolean(ctx, 0);
        return 1;
    }

    var ev = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(command));

    _ = c.snprintf(
        @as([*c]u8, @ptrCast(@alignCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message))),
        @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
        "%s",
        descr,
    );
    c.lua_pushboolean(ctx, @intFromBool(c.platform_fsrv_pushfd(fsrv, &ev, fd) != 0));
    _ = c.close(fd);
    return 1;
}

// ---------------------------------------------------------------------------
// targetreset (C:9063) — reset_target
// ---------------------------------------------------------------------------
fn targetreset(ctx: ?*c.lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const vid = luaL_checkvid(ctx, 1, &vobj);
    const hard = luaL_optbnumber(ctx, 2, false);

    var ev = arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_TARGET))));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_RESET));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = if (hard) 1 else 0;

    if (vobj != null and vobj.*.feed.state.tag == c.ARCAN_TAG_VR) {
        _ = c.arcan_vr_setref(@as(?*c.arcan_vr_ctx, @ptrCast(vobj.*.feed.state.ptr)));
    } else {
        _ = tgtevent(vid, ev);
        if (vobj.*.feed.state.tag == c.ARCAN_TAG_FRAMESERV) {
            _ = c.arcan_frameserver_flush(@as(?*c.arcan_frameserver, @ptrCast(@alignCast(vobj.*.feed.state.ptr))));
        }
    }

    return 0;
}

// ---------------------------------------------------------------------------
// spawn_subsegment (C:9094) — allocate subsegment for frameserver
// ---------------------------------------------------------------------------
fn spawn_subsegment(
    parent: ?*c.arcan_frameserver,
    segid: c_uint,
    hints: u8,
    reqid: u32,
    w_arg: usize,
    h_arg: usize,
) ?*c.arcan_frameserver {
    // clip to limits
    var w = w_arg;
    var h = h_arg;
    if (w > @as(usize, @intCast(c.ARCAN_SHMPAGE_MAXW)))
        w = @as(usize, @intCast(c.ARCAN_SHMPAGE_MAXW));
    if (h > @as(usize, @intCast(c.ARCAN_SHMPAGE_MAXH)))
        h = @as(usize, @intCast(c.ARCAN_SHMPAGE_MAXH));

    // first allocate the vobj
    const cons = c.img_cons{
        .w = @as(c_uint, @truncate(w)),
        .h = @as(c_uint, @truncate(h)),
        .bpp = c.ARCAN_SHMPAGE_VCHANNELS,
    };
    var state = c.vfunc_state{
        .tag = c.ARCAN_TAG_FRAMESERV,
        .ptr = null,
    };
    const newvid = c.arcan_video_addfobject(
        @as(c.ffunc_ind, @bitCast(@as(i8, @truncate(c.FFUNC_VFRAME)))),
        state,
        cons,
        0,
    );
    if (newvid == c.ARCAN_EID) {
        return null;
    }

    const res = c.platform_fsrv_spawn_subsegment(
        parent,
        @as(c_int, @bitCast(segid)),
        @as(c_int, @bitCast(@as(c_uint, hints))),
        w,
        h,
        @as(usize, @bitCast(@as(c_long, @truncate(newvid)))),
        reqid,
    );

    if (res == null) {
        _ = c.arcan_video_deleteobject(newvid);
        return null;
    }

    // update fobject with new frameserver reference
    state.ptr = @as(?*anyopaque, @ptrCast(res));
    res.*.vid = newvid;
    _ = c.arcan_video_alterfeed(
        newvid,
        @as(c.ffunc_ind, @bitCast(@as(i8, @truncate(c.FFUNC_VFRAME)))),
        state,
    );

    // encoder doesn't need playback or audio control ID
    var errc: c.arcan_errc = undefined;
    if (segid != @as(c_uint, @bitCast(c.SEGID_ENCODER))) {
        res.*.aid = c.arcan_audio_feed(
            @as(c.arcan_afunc_cb, @ptrCast(&c.arcan_frameserver_audioframe_direct)),
            @as(?*anyopaque, @ptrCast(res)),
            &errc,
        );
    }

    c.arcan_conductor_register_frameserver(res);

    return res;
}

// ---------------------------------------------------------------------------
// targetaccept_lwa (C:9139) — accept_target LWA path (ARCAN_LWA ifdef)
// ---------------------------------------------------------------------------
fn targetaccept_lwa(ctx: ?*c.lua_State) c_int {
    const C: [*c]c.arcan_shmif_cont = @ptrCast(@alignCast(c.arcan_alloc_mem(
        @sizeOf(c.arcan_shmif_cont),
        @as(c_uint, @bitCast(c.ARCAN_MEM_VTAG)),
        @as(c_uint, @bitCast(c.ARCAN_MEM_BZERO)),
        @as(c_uint, @bitCast(c.ARCAN_MEMALIGN_NATURAL)),
    )));
    C.* = luactx.pending_segpush.*;

    // first allocate the vobj
    const cons = c.img_cons{
        .w = @intCast(C.*.w),
        .h = @intCast(C.*.h),
        .bpp = c.ARCAN_SHMPAGE_VCHANNELS,
    };
    const state = c.vfunc_state{
        .tag = c.ARCAN_TAG_FRAMESERV,
        .ptr = null,
    };
    const newvid = c.arcan_video_addfobject(
        @as(c.ffunc_ind, @bitCast(@as(i8, @truncate(c.FFUNC_WRAPPED)))),
        state,
        cons,
        0,
    );

    if (newvid == c.ARCAN_EID) {
        c.arcan_mem_free(@as(?*anyopaque, @ptrCast(C)));
        return 0;
    }

    const newref_opt = c.platform_fsrv_wrapcl(C, @as(usize, @bitCast(@as(c_long, @truncate(newvid)))));

    if (newref_opt == null) {
        lua_pushvid(ctx, c.ARCAN_EID);
        lua_pushaid(ctx, c.ARCAN_EID);
        c.lua_pushnumber(ctx, 0);
        return 3;
    }
    const newref = newref_opt.?;

    const fftag = c.vfunc_state{
        .tag = c.ARCAN_TAG_FRAMESERV,
        .ptr = @as(?*anyopaque, @ptrCast(newref_opt)),
    };

    const vobj = c.arcan_video_getobject(newvid);
    vobj.*.vstore.*.vinf.text.d_fmt = @as(c_uint, @bitCast(@as(c_int, 0x1907))); // GL_NOALPHA_PIXEL_FORMAT
    _ = c.arcan_video_alterfeed(
        newvid,
        @as(c.ffunc_ind, @bitCast(@as(i8, @truncate(c.FFUNC_WRAPPED)))),
        fftag,
    );
    _ = c.arcan_video_resizefeed(newvid, @as(usize, C.*.w), @as(usize, C.*.h));

    lua_pushvid(ctx, newref.*.vid);
    lua_pushaid(ctx, newref.*.aid);
    c.lua_pushnumber(ctx, @floatFromInt(newref.*.cookie));
    luactx.pending_segpush = null;
    trace_allocation(ctx, "subseg-push", newref.*.vid);

    return 3;
}

// ---------------------------------------------------------------------------
// targetaccept (C:9187) — accept_target
// ---------------------------------------------------------------------------
fn targetaccept(ctx: ?*c.lua_State) callconv(.c) c_int {
    // ARCAN_LWA path: if there is a pending segment push, use the LWA handler
    if (luactx.pending_segpush != null) {
        return targetaccept_lwa(ctx);
    }

    if (luactx.last_segreq == null)
        c.arcan_fatal("accept_target(), only permitted inside a segment_request.\n");

    var w: u16 = luactx.last_segreq.*.unnamed_0.segreq.width;
    var h: u16 = luactx.last_segreq.*.unnamed_0.segreq.height;

    if (c.lua_isnumber(ctx, 1) != 0)
        w = @as(u16, @intFromFloat(c.lua_tonumber(ctx, 1)));

    if (c.lua_isnumber(ctx, 2) != 0)
        h = @as(u16, @intFromFloat(c.lua_tonumber(ctx, 2)));

    const segid: c_uint = luactx.last_segreq.*.unnamed_0.segreq.kind;
    const prev_state = c.arcan_video_feedstate(
        @as(arcan_vobj_id, @bitCast(@as(c_longlong, luactx.last_segreq.*.source))),
    );
    const newref = spawn_subsegment(
        @ptrCast(@alignCast(prev_state.*.ptr)),
        segid,
        luactx.last_segreq.*.unnamed_0.segreq.hints,
        luactx.last_segreq.*.unnamed_0.segreq.id,
        @as(usize, w),
        @as(usize, h),
    );

    if (newref == null) {
        lua_pushvid(ctx, c.ARCAN_EID);
        lua_pushaid(ctx, c.ARCAN_EID);
        c.lua_pushnumber(ctx, 0);
        return 3;
    }

    const nr = newref.?;
    nr.tag = find_lua_callback(ctx);

    // special handling for SEGID_HANDOVER
    if (segid == @as(c_uint, @bitCast(c.SEGID_HANDOVER))) {
        nr.child = -1;
        _ = c.arcan_video_alterfeed(nr.vid, @as(c.ffunc_ind, @bitCast(@as(i8, @truncate(c.FFUNC_NULLFRAME)))), c.vfunc_state{
            .tag = c.ARCAN_TAG_FRAMESERV,
            .ptr = @as(?*anyopaque, @ptrCast(newref)),
        });
    }

    lua_pushvid(ctx, nr.vid);
    lua_pushaid(ctx, nr.aid);
    c.lua_pushnumber(ctx, @floatFromInt(nr.cookie));
    luactx.last_segreq = null;
    trace_allocation(ctx, "subseg", nr.vid);

    return 3;
}

// ---------------------------------------------------------------------------
// targetalloc (C:9250) — target_alloc
// ---------------------------------------------------------------------------
fn targetalloc(ctx: ?*c.lua_State) callconv(.c) c_int {
    var cb_ind: c_int = 2;
    const pw: [*c]u8 = null;

    // defunct password arg — skip if string at position 2
    if (c.lua_type(ctx, 2) == c.LUA_TSTRING) {
        cb_ind = 3;
    }

    // optional width/height before callback
    var init_w: usize = 32;
    var init_h: usize = 32;
    if (c.lua_type(ctx, cb_ind) == c.LUA_TNUMBER) {
        if (c.lua_type(ctx, cb_ind + 1) != c.LUA_TNUMBER) {
            c.arcan_fatal("target_alloc(), argument error, expected number (height)\n");
        }
        init_w = @intFromFloat(c.luaL_checknumber(ctx, cb_ind + 0));
        init_h = @intFromFloat(c.luaL_checknumber(ctx, cb_ind + 1));
        cb_ind += 2;
    }

    c.luaL_checktype(ctx, cb_ind, c.LUA_TFUNCTION);
    if (c.lua_iscfunction(ctx, cb_ind) != 0)
        c.arcan_fatal("target_alloc(), callback to C function forbidden.\n");

    c.lua_pushvalue(ctx, cb_ind);
    const ref: isize = @intCast(c.luaL_ref(ctx, c.LUA_REGISTRYINDEX));

    var tag: c_int = 0;
    var segid: c_int = c.SEGID_UNKNOWN;

    if (c.lua_type(ctx, cb_ind + 1) == c.LUA_TNUMBER) {
        tag = @intFromFloat(c.lua_tonumber(ctx, cb_ind + 1));
    } else if (c.lua_type(ctx, cb_ind + 1) == c.LUA_TSTRING) {
        const msg = c.lua_tolstring(ctx, cb_ind + 1, null);
        if (c.strcmp(msg, "debug") == 0) {
            segid = c.SEGID_DEBUG;
        } else if (c.strcmp(msg, "accessibility") == 0) {
            segid = c.SEGID_ACCESSIBILITY;
        } else {
            c.arcan_warning("target_alloc(), unaccepted segid type-string (%s), allowed: debug, accessibility\n", msg);
        }

        if (c.lua_type(ctx, cb_ind + 2) == c.LUA_TBOOLEAN and c.lua_toboolean(ctx, cb_ind + 2) != 0) {
            segid |= @as(c_int, @bitCast(@as(c_uint, 1) << @intCast(31)));
        }
    }

    var newref: ?*c.arcan_frameserver = null;

    // allocate new key or give to preexisting frameserver?
    if (c.lua_type(ctx, 1) == c.LUA_TSTRING) {
        const key = c.luaL_checklstring(ctx, 1, null);
        const keylen = c.strlen(key);
        if (0 == keylen or keylen > 30)
            c.arcan_fatal("target_alloc(), invalid listening key (%s), length (%d) should be , 0 < n < 31\n", keylen);

        // validate characters
        {
            var pos: [*c]const u8 = key;
            while (pos.* != 0) : (pos += 1) {
                if (!(c.isalnum(pos.*) != 0) and pos.* != '_' and pos.* != '-')
                    c.arcan_fatal("target_alloc(%s), only aZ_ are permitted in names.\n", key);
            }
        }

        if (luactx.pending_socket_label != null and
            c.strcmp(key, luactx.pending_socket_label) == 0)
        {
            newref = c.platform_launch_listen_external(
                key,
                pw,
                luactx.pending_socket_descr,
                c.ARCAN_SHM_UMASK,
                init_w,
                init_h,
                @as(usize, @bitCast(ref)),
            );
            c.arcan_mem_free(@as(?*anyopaque, @ptrCast(luactx.pending_socket_label)));
            luactx.pending_socket_label = null;
        } else {
            newref = c.platform_launch_listen_external(
                key,
                pw,
                -1,
                c.ARCAN_SHM_UMASK,
                init_w,
                init_h,
                @as(usize, @bitCast(ref)),
            );
        }

        if (newref == null) {
            return 0;
        }

        c.arcan_conductor_register_frameserver(newref);
    } else {
        const srcfsrv = luaL_checkvid(ctx, 1, null);
        const state = c.arcan_video_feedstate(srcfsrv);
        if (state != null and state.*.tag == c.ARCAN_TAG_FRAMESERV and state.*.ptr != null) {
            newref = spawn_subsegment(
                @ptrCast(@alignCast(state.*.ptr)),
                @as(c_uint, @bitCast(segid)),
                0,
                @as(u32, @bitCast(tag)),
                init_w,
                init_h,
            );
        } else {
            c.arcan_fatal("target_alloc() specified source ID doesn't contain a frameserver\n.");
        }
        newref.?.tag = ref;
    }

    if (newref == null) {
        lua_pushvid(ctx, c.ARCAN_EID);
        lua_pushaid(ctx, c.ARCAN_EID);
        return 2;
    }

    const nr = newref.?;
    lua_pushvid(ctx, nr.vid);
    lua_pushaid(ctx, nr.aid);
    c.lua_pushnumber(ctx, @floatFromInt(nr.cookie));

    trace_allocation(ctx, "target", nr.vid);
    return 3;
}

// ---------------------------------------------------------------------------
// targetlaunch (C:9372) — launch_target
// translate-c failed on this (goto statements) — manually ported from C
// ---------------------------------------------------------------------------
fn targetlaunch(ctx: ?*c.lua_State) callconv(.c) c_int {
    var rc: usize = 0;
    var ofs: c_int = 2;
    var lmode: c_int = LAUNCH_INTERNAL;

    const tname = c.luaL_checklstring(ctx, 1, null);
    var cfg: [*c]const u8 = "default";

    if (c.lua_type(ctx, 2) == c.LUA_TSTRING) {
        cfg = c.lua_tolstring(ctx, 2, null);
        ofs += 1;
    }

    const cid = c.arcan_db_configid(
        DBHANDLE(),
        c.arcan_db_targetid(DBHANDLE(), tname, null),
        cfg,
    );

    if (c.lua_type(ctx, ofs) == c.LUA_TNUMBER) {
        lmode = @intFromFloat(c.lua_tonumber(ctx, ofs));
        ofs += 1;
    }

    if (lmode != LAUNCH_EXTERNAL and lmode != LAUNCH_INTERNAL)
        c.arcan_fatal("launch_target(), invalid mode -- expected LAUNCH_INTERNAL or LAUNCH_EXTERNAL ");

    const ref = find_lua_callback(ctx);

    var argv: c.arcan_strarr = std.mem.zeroes(c.arcan_strarr);
    var env: c.arcan_strarr = std.mem.zeroes(c.arcan_strarr);
    var libs: c.arcan_strarr = std.mem.zeroes(c.arcan_strarr);
    var bfmt: c.enum_DB_BFORMAT = undefined;

    const exec = c.arcan_db_targetexec(DBHANDLE(), cid, &bfmt, &argv, &env, &libs);

    // means strarrs won't be populated, not fatal due to race potential
    if (exec == null) {
        c.arcan_warning("launch_target(), failed -- invalid configuration\n");
        return 0;
    }

    // Use labeled block for goto cleanup pattern
    rc = blk: {
        if (lmode == LAUNCH_EXTERNAL) {
            if (bfmt != c.BFRM_EXTERN) {
                c.arcan_warning("launch_target(), failed -- binary format not suitable for external launch.");
                break :blk 0;
            }

            var retc: c_int = 1; // EXIT_FAILURE
            if (c.arcan_video_prepare_external(false) == false) {
                c.arcan_warning("Warning, arcan_target_launch_external(), couldn't push current context, aborting launch.\n");
                break :blk 0;
            }

            const tv = c.arcan_target_launch_external(exec, &argv, &env, &libs, &retc);
            c.lua_pushnumber(ctx, @floatFromInt(retc));
            c.lua_pushnumber(ctx, @floatFromInt(tv));
            c.arcan_video_restore_external(false);

            break :blk 2;
        }

        var intarget: ?*c.arcan_frameserver = null;

        switch (bfmt) {
            c.BFRM_BIN, c.BFRM_SHELL => {
                intarget = c.platform_launch_internal(exec, &argv, &env, &libs, @as(usize, @bitCast(ref)));
            },
            c.BFRM_LWA => {
                c.arcan_warning("bfrm_lwa() not yet supported\n");
            },
            c.BFRM_GAME => {
                if (lmode != 1) {
                    c.arcan_warning("launch_target(), configuration specified game format which is only possible in internal- mode.");
                    break :blk 0;
                }

                var args = std.mem.zeroes(c.frameserver_envp);
                args.use_builtin = true;
                args.args.builtin.mode = "game";

                var expbuf: [4][*c]u8 = .{
                    colon_escape(c.strdup(exec)),
                    if (argv.count > 1) colon_escape(c.strdup(argv.unnamed_0.data[1])) else null,
                    if (argv.count > 2) colon_escape(c.strdup(argv.unnamed_0.data[2])) else null,
                    null,
                };
                _ = c.arcan_expand_namespaces(@as([*c][*c]u8, @ptrCast(&expbuf)));

                var argstr: [*c]u8 = null;
                if (c.asprintf(
                    &argstr,
                    "core=%s%s%s%s%s",
                    expbuf[0],
                    if (expbuf[1] != null) @as([*c]const u8, ":resource=") else @as([*c]const u8, ""),
                    if (expbuf[1] != null) expbuf[1] else @as([*c]u8, @constCast("")),
                    if (expbuf[1] != null) @as([*c]const u8, ":syspath=") else @as([*c]const u8, ""),
                    if (expbuf[2] != null) expbuf[2] else @as([*c]u8, @constCast("")),
                ) == -1) {
                    argstr = null;
                }

                args.args.builtin.resource = argstr;
                intarget = c.platform_launch_fork(&args, @as(usize, @bitCast(ref)));
                c.free(@as(?*anyopaque, @ptrCast(argstr)));
                c.free(@as(?*anyopaque, @ptrCast(expbuf[0])));
                c.free(@as(?*anyopaque, @ptrCast(expbuf[1])));
            },
            else => {
                c.arcan_fatal("launch_target(), database inconsistency, unknown binary format encountered.\n");
            },
        }

        // update accounting
        c.arcan_db_launch_status(DBHANDLE(), cid, intarget != null);

        if (intarget) |it| {
            _ = c.arcan_video_objectopacity(it.vid, 0.0, 0);
            lua_pushvid(ctx, it.vid);
            lua_pushaid(ctx, it.aid);
            c.lua_pushnumber(ctx, @floatFromInt(it.cookie));
            trace_allocation(ctx, "launch", it.vid);
            break :blk 3;
        }

        break :blk 0;
    };

    // cleanup (always runs)
    c.arcan_mem_freearr(&argv);
    c.arcan_mem_freearr(&env);
    c.arcan_mem_freearr(&libs);
    c.arcan_mem_free(@as(?*anyopaque, @ptrCast(exec)));

    return @as(c_int, @intCast(rc));
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part10.zig
// ══════════════════════════════════════════════════════════════════════

// Zig port of engine/arcan_lua.c lines 9518–10939 — rendertarget, calctarget,
// mesh access, image storage/metadata, recording, and 3D build functions.
//
// Ported from C using zig translate-c as reference, with manual cleanup.



// Type aliases

// External state from other compilation units

// Forward-declared externs from other parts of arcan_lua
extern fn luavid_tovid(innum: lua_Number) arcan_vobj_id;
// Zig implementation of _int_flag from arcan_videoint.h (static inline)
fn _int_flag(vobj: [*c]c.arcan_vobject) void {
    if (vobj != null) {
        if (vobj.*.owner) |owner| {
            owner.*.transfc += 1;
        }
    }
}
extern var arcan_video_display: extern struct {
    dirty: c_uint,
};

extern var system_page_size: c_int;

// Module-level state (luactx struct — shared with other parts)

// Constants

const NULFILE = "/dev/null";


fn lua_isnumber(ctx: ?*lua_State, ind: c_int) bool {
    return c.lua_type(ctx, ind) == c.LUA_TNUMBER;
}

// FLAG_DIRTY macro
fn FLAG_DIRTY(vobj: [*c]c.arcan_vobject) void {
    _int_flag(vobj);
    arcan_video_display.dirty += 1;
}

// Histogram packing
const HIST_DIRTY: c_uint = 0;
const HIST_SPLIT: c_uint = 1;
const HIST_MERGE: c_uint = 2;
const HIST_MERGE_NOALPHA: c_uint = 3;

// Structs
const transform_cs = struct {
    blend: usize = 0,
    move: usize = 0,
    rotate: usize = 0,
    scale: usize = 0,
};

const proctarget_src = extern struct {
    ctx: ?*lua_State = null,
    cbfun: usize = 0,
};

const rn_userdata = extern struct {
    bufptr: [*c]c.av_pixel = null,
    width: c_int = 0,
    height: c_int = 0,
    nelem: usize = 0,
    tui: ?*c.tui_context = null,
    bins: [1024]c_uint = std.mem.zeroes([1024]c_uint),
    nf: [4]f32 = std.mem.zeroes([4]f32),
    valid: bool = false,
    packing: c_uint = 0,
};


// ═══════════════════════════════════════════════════════════════════════════
// Helper: clock_transform
// ═══════════════════════════════════════════════════════════════════════════
fn clock_transform(vobj: [*c]c.arcan_vobject, dst: *transform_cs) void {
    var current: [*c]c.surface_transform = vobj.*.transform;
    while (current != null) {
        var tc: usize = if (current.*.blend.endt != 0)
            @as(usize, @bitCast(@as(c_ulong, current.*.blend.endt))) -% luactx.last_clock
        else
            0;
        if (tc > dst.blend) dst.blend = tc;

        tc = if (current.*.move.endt != 0)
            @as(usize, @bitCast(@as(c_ulong, current.*.move.endt))) -% luactx.last_clock
        else
            0;
        if (tc > dst.move) dst.move = tc;

        tc = if (current.*.rotate.endt != 0)
            @as(usize, @bitCast(@as(c_ulong, current.*.rotate.endt))) -% luactx.last_clock
        else
            0;
        if (tc > dst.rotate) dst.rotate = tc;

        tc = if (current.*.scale.endt != 0)
            @as(usize, @bitCast(@as(c_ulong, current.*.scale.endt))) -% luactx.last_clock
        else
            0;
        if (tc > dst.scale) dst.scale = tc;

        current = current.*.next;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper: packing_lut
// ═══════════════════════════════════════════════════════════════════════════
fn packing_lut(mode: c_uint, dst: *[4]c_int) void {
    const otbl_separate = [4]c_int{ 0, 256, 512, 768 };
    const otbl_mergeall = [4]c_int{ 0, 0, 0, 0 };
    const otbl_mergergb = [4]c_int{ 0, 0, 0, 768 };

    const otbl = switch (mode) {
        HIST_DIRTY, HIST_SPLIT => otbl_separate,
        HIST_MERGE => otbl_mergeall,
        else => otbl_mergergb,
    };
    dst.* = otbl;
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper: procimage_buildhisto
// ═══════════════════════════════════════════════════════════════════════════
fn procimage_buildhisto(ud: *rn_userdata, pack: c_uint) void {
    if (ud.packing == pack) return;

    const img = ud.bufptr;
    @memset(&ud.bins, 0);

    var otbl: [4]c_int = undefined;
    packing_lut(pack, &otbl);

    ud.packing = pack;

    // populate bins with frequency
    var row: usize = 0;
    while (row < @as(usize, @intCast(ud.height))) : (row += 1) {
        var col_idx: usize = 0;
        while (col_idx < @as(usize, @intCast(ud.width))) : (col_idx += 1) {
            const ofs = row * @as(usize, @intCast(ud.width)) + col_idx;
            var rgba: [4]u8 = undefined;
            c.RGBA_DECOMP(img[ofs], &rgba[0], &rgba[1], &rgba[2], &rgba[3]);
            ud.bins[@intCast(@as(c_int, otbl[0]) + @as(c_int, @intCast(rgba[0])))] += 1;
            ud.bins[@intCast(@as(c_int, otbl[1]) + @as(c_int, @intCast(rgba[1])))] += 1;
            ud.bins[@intCast(@as(c_int, otbl[2]) + @as(c_int, @intCast(rgba[2])))] += 1;
            ud.bins[@intCast(@as(c_int, otbl[3]) + @as(c_int, @intCast(rgba[3])))] += 1;
        }
    }

    // update limits for each bin
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const idx0 = @as(usize, @intCast(otbl[0])) + i;
        const idx1 = @as(usize, @intCast(otbl[1])) + i;
        const idx2 = @as(usize, @intCast(otbl[2])) + i;
        const idx3 = @as(usize, @intCast(otbl[3])) + i;
        if (ud.nf[0] < @as(f32, @floatFromInt(ud.bins[idx0]))) ud.nf[0] = @floatFromInt(ud.bins[idx0]);
        if (ud.nf[1] < @as(f32, @floatFromInt(ud.bins[idx1]))) ud.nf[1] = @floatFromInt(ud.bins[idx1]);
        if (ud.nf[2] < @as(f32, @floatFromInt(ud.bins[idx2]))) ud.nf[2] = @floatFromInt(ud.bins[idx2]);
        if (ud.nf[3] < @as(f32, @floatFromInt(ud.bins[idx3]))) ud.nf[3] = @floatFromInt(ud.bins[idx3]);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper: add_attr_tbl
// ═══════════════════════════════════════════════════════════════════════════
fn add_attr_tbl(L: ?*lua_State, attr: c.tui_screen_attr) void {
    c.lua_createtable(L, 0, 0);

    if ((attr.unnamed_2.aflags & c.TUI_ATTR_COLOR_INDEXED) != 0) {
        c.lua_pushstring(L, "fc");
        c.lua_pushnumber(L, @floatFromInt(attr.unnamed_0.fc[0]));
        c.lua_rawset(L, -3);

        c.lua_pushstring(L, "bc");
        c.lua_pushnumber(L, @floatFromInt(attr.unnamed_1.bc[0]));
        c.lua_rawset(L, -3);
    } else {
        c.lua_pushstring(L, "fr");
        c.lua_pushnumber(L, @floatFromInt(attr.unnamed_0.unnamed_0.fr));
        c.lua_rawset(L, -3);

        c.lua_pushstring(L, "fg");
        c.lua_pushnumber(L, @floatFromInt(attr.unnamed_0.unnamed_0.fg));
        c.lua_rawset(L, -3);

        c.lua_pushstring(L, "fb");
        c.lua_pushnumber(L, @floatFromInt(attr.unnamed_0.unnamed_0.fb));
        c.lua_rawset(L, -3);

        c.lua_pushstring(L, "br");
        c.lua_pushnumber(L, @floatFromInt(attr.unnamed_1.unnamed_0.br));
        c.lua_rawset(L, -3);

        c.lua_pushstring(L, "bg");
        c.lua_pushnumber(L, @floatFromInt(attr.unnamed_1.unnamed_0.bg));
        c.lua_rawset(L, -3);

        c.lua_pushstring(L, "bb");
        c.lua_pushnumber(L, @floatFromInt(attr.unnamed_1.unnamed_0.bb));
        c.lua_rawset(L, -3);
    }

    const aflags: c_int = @intCast(attr.unnamed_2.aflags);

    inline for (.{
        .{ "bold", c.TUI_ATTR_BOLD },
        .{ "italic", c.TUI_ATTR_ITALIC },
        .{ "inverse", c.TUI_ATTR_INVERSE },
        .{ "underline", c.TUI_ATTR_UNDERLINE },
        .{ "underline_alt", c.TUI_ATTR_UNDERLINE_ALT },
        .{ "protect", c.TUI_ATTR_PROTECT },
        .{ "blink", c.TUI_ATTR_BLINK },
        .{ "strikethrough", c.TUI_ATTR_STRIKETHROUGH },
        .{ "break", c.TUI_ATTR_SHAPE_BREAK },
        .{ "border_left", c.TUI_ATTR_BORDER_LEFT },
        .{ "border_right", c.TUI_ATTR_BORDER_RIGHT },
        .{ "border_down", c.TUI_ATTR_BORDER_DOWN },
        .{ "border_top", c.TUI_ATTR_BORDER_TOP },
    }) |entry| {
        c.lua_pushstring(L, entry[0]);
        c.lua_pushboolean(L, aflags & entry[1]);
        c.lua_rawset(L, -3);
    }

    c.lua_pushstring(L, "id");
    c.lua_pushnumber(L, @floatFromInt(attr.custom_id));
    c.lua_rawset(L, -3);
}

fn ensure_tui_procimage(ud: *rn_userdata, comptime prefix: []const u8) void {
    if (ud.valid == false)
        c.arcan_fatal(prefix ++ "calctarget object called out of scope\n");
    if (ud.tui == null)
        c.arcan_fatal(prefix ++ "calctarget object lacks text context\n");
}

// ═══════════════════════════════════════════════════════════════════════════
// rendertarget_forceupdate
// ═══════════════════════════════════════════════════════════════════════════
fn rendertargetforce(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const vid = luaL_checkvid(ctx, 1, &vobj);
    _ = luaL_optbnumber(ctx, 2, true);

    const rtgt = c.arcan_vint_findrt(vobj);
    if (rtgt == null)
        c.arcan_fatal("rendertarget_forceupdate(), specified vid does not reference a rendertarget");

    if (c.lua_type(ctx, 2) == c.LUA_TNUMBER) {
        rtgt.*.refresh = @intFromFloat(c.luaL_checknumber(ctx, 2));
        rtgt.*.refreshcnt = @intCast(if (rtgt.*.refresh < 0) -rtgt.*.refresh else rtgt.*.refresh);

        if (c.lua_type(ctx, 3) == c.LUA_TNUMBER) {
            rtgt.*.readback = @intFromFloat(c.luaL_checknumber(ctx, 3));
            rtgt.*.readcnt = @intCast(if (rtgt.*.readback < 0) -rtgt.*.readback else rtgt.*.readback);
        }

        if (luaL_optbnumber(ctx, 4, false)) {
            rtgt.*.hwreadback = true;
        }
    } else {
        var forcedirty: bool = true;
        if (c.lua_type(ctx, 2) == c.LUA_TBOOLEAN) {
            forcedirty = c.lua_toboolean(ctx, 2) != 0;
        }

        if (@as(c.arcan_errc, @intCast(c.ARCAN_OK)) != c.arcan_video_forceupdate(vid, forcedirty))
            c.arcan_fatal("rendertarget_forceupdate() failed on vid");
    }

    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// rendertarget_metrics
// ═══════════════════════════════════════════════════════════════════════════
fn rendertargetmetrics(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 1, &vobj);
    const rtgt = c.arcan_vint_findrt(vobj);

    if (rtgt == null)
        c.arcan_fatal("rendertarget_metrics(), specified vid does not reference a rendertarget");

    c.lua_createtable(ctx, 0, 0);

    c.lua_pushstring(ctx, "dirty");
    c.lua_pushnumber(ctx, @floatFromInt(rtgt.*.dirtyc));
    c.lua_rawset(ctx, -3);

    c.lua_pushstring(ctx, "transfers");
    c.lua_pushnumber(ctx, @floatFromInt(rtgt.*.uploadc));
    c.lua_rawset(ctx, -3);

    c.lua_pushstring(ctx, "updates");
    c.lua_pushnumber(ctx, @floatFromInt(rtgt.*.transfc));
    c.lua_rawset(ctx, -3);

    // get the clock horizon
    var current: [*c]c.arcan_vobject_litem = rtgt.*.first;
    var cs = transform_cs{};
    while (current != null) {
        clock_transform(current.*.elem, &cs);
        current = current.*.next;
    }

    c.lua_pushstring(ctx, "time_move");
    c.lua_pushnumber(ctx, @floatFromInt(cs.move));
    c.lua_rawset(ctx, -3);

    c.lua_pushstring(ctx, "time_blend");
    c.lua_pushnumber(ctx, @floatFromInt(cs.blend));
    c.lua_rawset(ctx, -3);

    c.lua_pushstring(ctx, "time_scale");
    c.lua_pushnumber(ctx, @floatFromInt(cs.scale));
    c.lua_rawset(ctx, -3);

    c.lua_pushstring(ctx, "time_rotate");
    c.lua_pushnumber(ctx, @floatFromInt(cs.rotate));
    c.lua_rawset(ctx, -3);

    return 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// rendertarget_vids
// ═══════════════════════════════════════════════════════════════════════════
fn rendertarget_vids(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 1, &vobj);
    const rtgt = c.arcan_vint_findrt(vobj);

    if (rtgt == null)
        c.arcan_fatal("rendertarget_vids(), specified vid does not reference a rendertarget");

    c.lua_createtable(ctx, 0, 0);

    var i: c_int = 1;
    const top = c.lua_gettop(ctx);
    var current: [*c]c.arcan_vobject_litem = rtgt.*.first;
    while (current != null) {
        c.lua_pushnumber(ctx, @floatFromInt(i));
        i += 1;
        lua_pushvid(ctx, current.*.elem.*.cellid);
        c.lua_rawset(ctx, top);
        current = current.*.next;
    }

    return 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// rendertarget_noclear
// ═══════════════════════════════════════════════════════════════════════════
fn rendernoclear(ctx: ?*lua_State) callconv(.c) c_int {
    const did = luaL_checkvid(ctx, 1, null);
    const clearfl = luaL_checkbnumber(ctx, 2);

    c.lua_pushboolean(ctx, @intFromBool(
        c.arcan_video_rendertarget_setnoclear(did, clearfl) == @as(c.arcan_errc, @intCast(c.ARCAN_OK)),
    ));

    return 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// rendertarget_reconfigure
// ═══════════════════════════════════════════════════════════════════════════
fn renderreconf(ctx: ?*lua_State) callconv(.c) c_int {
    const did = luaL_checkvid(ctx, 1, null);
    var hppcm: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    var vppcm: f32 = @floatCast(c.luaL_checknumber(ctx, 3));

    if (hppcm < 18.0) hppcm = 18.0;
    if (vppcm < 18.0) vppcm = 18.0;

    if (did == c.ARCAN_VIDEO_WORLDID) {
        c.arcan_lua_setglobalnum(ctx, "VPPCM", @floatCast(vppcm));
        c.arcan_lua_setglobalnum(ctx, "HPPCM", @floatCast(hppcm));
    }

    _ = c.arcan_video_rendertargetdensity(did, vppcm, hppcm, true, true);
    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// rendertarget_range
// ═══════════════════════════════════════════════════════════════════════════
fn rendertargetrange(ctx: ?*lua_State) callconv(.c) c_int {
    const did = luaL_checkvid(ctx, 1, null);
    const min_val: isize = @intFromFloat(c.luaL_optnumber(ctx, 2, -1.0));
    const max_val: isize = @intFromFloat(c.luaL_optnumber(ctx, 3, -1.0));
    _ = c.arcan_video_rendertarget_range(did, min_val, max_val);
    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// rendertarget_id
// ═══════════════════════════════════════════════════════════════════════════
fn rendertargetid(ctx: ?*lua_State) callconv(.c) c_int {
    const did = luaL_checkvid(ctx, 1, null);
    var id: c_int = undefined;

    // set or only get?
    if (c.lua_type(ctx, 2) == c.LUA_TNUMBER) {
        id = @intFromFloat(c.luaL_checknumber(ctx, 2));
        _ = c.arcan_video_rendertargetid(did, &id, null);
    }

    if (@as(c.arcan_errc, @intCast(c.ARCAN_OK)) != c.arcan_video_rendertargetid(did, null, &id))
        c.lua_pushnil(ctx)
    else
        c.lua_pushnumber(ctx, @floatFromInt(id));

    return 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// rendertarget_detach
// ═══════════════════════════════════════════════════════════════════════════
fn renderdetach(ctx: ?*lua_State) callconv(.c) c_int {
    const did = luaL_checkvid(ctx, 1, null);
    const sid = luaL_checkvid(ctx, 2, null);
    _ = c.arcan_video_detachfromrendertarget(did, sid);
    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// set_context_attachment
// ═══════════════════════════════════════════════════════════════════════════
fn setdefattach(ctx: ?*lua_State) callconv(.c) c_int {
    const did = luavid_tovid(c.luaL_optnumber(ctx, 1, @floatFromInt(@as(c_int, c.ARCAN_EID))));
    const cattach = c.arcan_video_currentattachment();

    if (did != c.ARCAN_EID)
        _ = c.arcan_video_defaultattachment(did);

    lua_pushvid(ctx, cattach);
    return 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// rendertarget_attach
// ═══════════════════════════════════════════════════════════════════════════
fn renderattach(ctx: ?*lua_State) callconv(.c) c_int {
    const did = luaL_checkvid(ctx, 1, null);
    const sid = luaL_checkvid(ctx, 2, null);
    const detach = luaL_checkint(ctx, 3);

    if (detach != RENDERTARGET_DETACH and detach != RENDERTARGET_NODETACH) {
        c.arcan_fatal("renderattach(%d) invalid arg 3, expected RENDERTARGET_DETACH or RENDERTARGET_NODETACH\n", detach);
    }

    _ = c.arcan_video_attachtorendertarget(did, sid, detach == RENDERTARGET_DETACH);
    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// define_linktarget
// ═══════════════════════════════════════════════════════════════════════════
fn linkset(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const did = luaL_checkvid(ctx, 1, null);
    const rtgt_id = luaL_checkvid(ctx, 2, &vobj);
    const rtgt = c.arcan_vint_findrt(vobj);
    if (rtgt == null)
        c.arcan_fatal("define_linktarget() - referenced vid is not a rendertarget\n");

    const scale = luaL_optint(ctx, 3, RENDERTARGET_NOSCALE);
    const rate = luaL_optint(ctx, 4, -1);
    const format = luaL_optint(ctx, 5, RENDERFMT_COLOR);

    if (scale != RENDERTARGET_SCALE and scale != RENDERTARGET_NOSCALE) {
        c.arcan_fatal("renderset(%d) invalid arg 3, expected RENDERTARGET_SCALE or RENDERTARGET_NOSCALE\n", scale);
    }

    const ok = c.arcan_video_linkrendertarget(
        did,
        rtgt_id,
        rate,
        scale == RENDERTARGET_SCALE,
        @bitCast(format),
    ) != 0;

    c.lua_pushboolean(ctx, @intFromBool(ok));
    return 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// define_rendertarget
// ═══════════════════════════════════════════════════════════════════════════
fn renderset(ctx: ?*lua_State) callconv(.c) c_int {
    const did = luaL_checkvid(ctx, 1, null);
    const nvids: c_int = @intCast(c.lua_objlen(ctx, 2));
    const detach = luaL_optint(ctx, 3, RENDERTARGET_DETACH);
    const scale = luaL_optint(ctx, 4, RENDERTARGET_NOSCALE);
    const rate = luaL_optint(ctx, 5, -1);
    const format = luaL_optint(ctx, 6, RENDERFMT_COLOR);

    if (detach != RENDERTARGET_DETACH and detach != RENDERTARGET_NODETACH) {
        c.arcan_fatal("renderset(%d) invalid arg 3, expected RENDERTARGET_DETACH or RENDERTARGET_NODETACH\n", detach);
    }

    if (scale != RENDERTARGET_SCALE and scale != RENDERTARGET_NOSCALE) {
        c.arcan_fatal("renderset(%d) invalid arg 4, expected RENDERTARGET_SCALE or RENDERTARGET_NOSCALE\n", scale);
    }

    // (RT debug removed — std.posix not available on freestanding)
    const ok = c.arcan_video_setuprendertarget(
        did,
        0,
        rate,
        scale == RENDERTARGET_SCALE,
        @bitCast(format),
    ) == @as(c.arcan_errc, @intCast(c.ARCAN_OK));

    if (c.lua_type(ctx, 7) == c.LUA_TNUMBER and c.lua_type(ctx, 8) == c.LUA_TNUMBER) {
        _ = c.arcan_video_rendertargetdensity(
            did,
            @floatCast(c.luaL_checknumber(ctx, 7)),
            @floatCast(c.luaL_checknumber(ctx, 8)),
            false,
            false,
        );
    }

    if (nvids > 0) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(nvids))) : (i += 1) {
            _ = c.lua_rawgeti(ctx, 2, @intCast(i + 1));
            const setvid = luavid_tovid(c.lua_tonumber(ctx, -1));
            c.lua_settop(ctx, -2);
            _ = c.arcan_video_attachtorendertarget(did, setvid, detach == RENDERTARGET_DETACH);
        }
    }

    c.lua_pushboolean(ctx, @intFromBool(ok));
    return 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// procimage:frequency
// ═══════════════════════════════════════════════════════════════════════════
fn procimage_lookup(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *rn_userdata = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "calcImage")));

    const bin: isize = @intFromFloat(c.luaL_checknumber(ctx, 2));
    if (bin < 0 or bin >= 256)
        c.arcan_fatal("calcImage:frequency, invalid bin %d specified (0..255).\n");

    const pack: c_uint = @intFromFloat(c.luaL_optnumber(ctx, 3, @floatFromInt(HIST_SPLIT)));
    const norm: bool = luaL_optbnumber(ctx, 4, true);

    if (ud.valid == false)
        c.arcan_fatal("calcImage:frequency, calctarget object called out of scope.\n");

    procimage_buildhisto(ud, pack);

    var ofs: [4]c_int = undefined;
    packing_lut(pack, &ofs);

    const ubin: usize = @intCast(bin);
    if (norm) {
        c.lua_pushnumber(ctx, @floatCast(@as(f32, @floatFromInt(ud.bins[@intCast(ofs[0])] + ubin)) / (ud.nf[0] + EPSILON)));
        c.lua_pushnumber(ctx, @floatCast(@as(f32, @floatFromInt(ud.bins[@intCast(ofs[1])] + ubin)) / (ud.nf[1] + EPSILON)));
        c.lua_pushnumber(ctx, @floatCast(@as(f32, @floatFromInt(ud.bins[@intCast(ofs[2])] + ubin)) / (ud.nf[2] + EPSILON)));
        c.lua_pushnumber(ctx, @floatCast(@as(f32, @floatFromInt(ud.bins[@intCast(ofs[3])] + ubin)) / (ud.nf[3] + EPSILON)));
    } else {
        c.lua_pushnumber(ctx, @floatCast(@as(f32, @floatFromInt(ud.bins[@as(usize, @intCast(ofs[0])) + ubin]))));
        c.lua_pushnumber(ctx, @floatCast(@as(f32, @floatFromInt(ud.bins[@as(usize, @intCast(ofs[1])) + ubin]))));
        c.lua_pushnumber(ctx, @floatCast(@as(f32, @floatFromInt(ud.bins[@as(usize, @intCast(ofs[2])) + ubin]))));
        c.lua_pushnumber(ctx, @floatCast(@as(f32, @floatFromInt(ud.bins[@as(usize, @intCast(ofs[3])) + ubin]))));
    }
    return 4;
}

// ═══════════════════════════════════════════════════════════════════════════
// procimage:histogram_impose
// ═══════════════════════════════════════════════════════════════════════════
fn procimage_histo(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *rn_userdata = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "calcImage")));

    if (ud.valid == false)
        c.arcan_fatal("calcImage:histogram_impose, calctarget object called out of scope\n");

    var vobj: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 2, &vobj);

    if (vobj.*.vstore == null or @as(c_int, vobj.*.vstore.*.txmapped) == c.TXSTATE_OFF or
        vobj.*.vstore.*.vinf.text.raw == null)
        c.arcan_fatal("calcImage:histogram_impose, destination vstore must have a valid textured backend.\n");

    if (vobj.*.vstore.*.w < 256)
        c.arcan_fatal("calcImage:histogram_impose, destination vstore width need to be >=256.\n");

    const packing: c_int = @intFromFloat(c.luaL_optnumber(ctx, 3, @floatFromInt(HIST_MERGE)));
    const dst_row: usize = @intFromFloat(c.luaL_optnumber(ctx, 4, 0.0));

    var base: [*c]c.av_pixel = vobj.*.vstore.*.vinf.text.raw;
    if (dst_row > vobj.*.vstore.*.h) {
        c.arcan_fatal("calcImage:histogram_impose, destination vstore row (%zu) need to fit in current height (%zu)\n", dst_row, vobj.*.vstore.*.h);
    }
    base += dst_row * vobj.*.vstore.*.w;

    var lut: [4]c_int = undefined;
    packing_lut(@bitCast(packing), &lut);

    var n: [4]f32 = undefined;
    procimage_buildhisto(ud, @bitCast(packing));

    if (luaL_optbnumber(ctx, 4, true)) {
        n[0] = ud.nf[0] + EPSILON;
        n[1] = ud.nf[1] + EPSILON;
        n[2] = ud.nf[2] + EPSILON;
        n[3] = ud.nf[3] + EPSILON;
    } else {
        const total: f32 = @floatFromInt(@as(c_int, ud.width) * @as(c_int, ud.height));
        n[0] = total;
        n[1] = total;
        n[2] = total;
        n[3] = total;
    }

    switch (packing) {
        @as(c_int, @intCast(HIST_SPLIT)) => {
            var j: usize = 0;
            while (j < 256) : (j += 1) {
                const r: f32 = @as(f32, @floatFromInt(ud.bins[j + @as(usize, @intCast(lut[0]))])) / n[0] * 255.0;
                const g: f32 = @as(f32, @floatFromInt(ud.bins[j + @as(usize, @intCast(lut[1]))])) / n[1] * 255.0;
                const b: f32 = @as(f32, @floatFromInt(ud.bins[j + @as(usize, @intCast(lut[2]))])) / n[2] * 255.0;
                const a: f32 = @as(f32, @floatFromInt(ud.bins[j + @as(usize, @intCast(lut[3]))])) / n[3] * 255.0;
                base[j] = c.RGBA(@as(u8, @intFromFloat(r)), @as(u8, @intFromFloat(g)), @as(u8, @intFromFloat(b)), @as(u8, @intFromFloat(a)));
            }
        },
        @as(c_int, @intCast(HIST_MERGE)), @as(c_int, @intCast(HIST_MERGE_NOALPHA)) => {
            var j: usize = 0;
            while (j < 256) : (j += 1) {
                const val: u8 = @intFromFloat(@as(f32, @floatFromInt(ud.bins[j])) / n[0] * 255.0);
                base[j] = c.RGBA(val, val, val, 0xff);
            }
        },
        else => {
            c.arcan_fatal("calcImage:histogram_impose, unknown packing mode. Allowed: HISTOGRAM_(SPLIT, MERGE, MERGE_NOALPHA)\n");
        },
    }

    c.agp_update_vstore(vobj.*.vstore, true);
    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// procimage:cursor_to
// ═══════════════════════════════════════════════════════════════════════════
fn procimage_cursor_to(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *rn_userdata = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "calcImage")));
    ensure_tui_procimage(ud, "calcImage:cursor_to, ");

    const x: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));
    const y: c_int = @intFromFloat(c.luaL_checknumber(ctx, 3));
    c.arcan_tui_move_to(ud.tui, @intCast(x), @intCast(y));

    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// procimage:cursor_style
// ═══════════════════════════════════════════════════════════════════════════
fn procimage_cursor_style(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *rn_userdata = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "calcImage")));
    ensure_tui_procimage(ud, "calcImage:cursor_style, ");

    const style = c.luaL_checklstring(ctx, 2, null);
    var fl: c_int = 0;

    if (c.strcmp(style, "block") == 0)
        fl = c.CURSOR_BLOCK
    else if (c.strcmp(style, "bar") == 0)
        fl = c.CURSOR_BAR
    else if (c.strcmp(style, "underline") == 0)
        fl = c.CURSOR_UNDER
    else if (c.strcmp(style, "frame") == 0)
        fl = c.CURSOR_HOLLOW;

    var col: [*c]u8 = null;
    var colv = [3]u8{ 0, 0, 0 };

    if (c.lua_type(ctx, 3) == c.LUA_TNUMBER and
        c.lua_type(ctx, 4) == c.LUA_TNUMBER and
        c.lua_type(ctx, 5) == c.LUA_TNUMBER)
    {
        colv[0] = @intFromFloat(c.lua_tonumber(ctx, 3));
        colv[1] = @intFromFloat(c.lua_tonumber(ctx, 4));
        colv[2] = @intFromFloat(c.lua_tonumber(ctx, 5));
        col = &colv;
    }

    _ = c.arcan_tui_cursor_style(ud.tui, fl, col);
    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// procimage:cursor
// ═══════════════════════════════════════════════════════════════════════════
fn procimage_cursor(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *rn_userdata = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "calcImage")));
    ensure_tui_procimage(ud, "calcImage:cursor, ");

    var cx: usize = undefined;
    var cy: usize = undefined;
    c.arcan_tui_cursorpos(ud.tui, &cx, &cy);

    c.lua_pushnumber(ctx, @floatFromInt(cx));
    c.lua_pushnumber(ctx, @floatFromInt(cy));

    return 2;
}

// ═══════════════════════════════════════════════════════════════════════════
// procimage:translate
// ═══════════════════════════════════════════════════════════════════════════
fn procimage_translate(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *rn_userdata = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "calcImage")));
    ensure_tui_procimage(ud, "calcImage:translate, ");

    const cx: usize = @intFromFloat(c.luaL_checknumber(ctx, 2));
    const cy: usize = @intFromFloat(c.luaL_checknumber(ctx, 3));
    var rows: usize = undefined;
    var cols: usize = undefined;
    c.arcan_tui_dimensions(ud.tui, &rows, &cols);
    const cell_w = @as(usize, @intCast(ud.width)) / cols;
    const cell_h = @as(usize, @intCast(ud.height)) / rows;

    c.lua_pushnumber(ctx, @floatFromInt(cx / cell_w));
    c.lua_pushnumber(ctx, @floatFromInt(cy / cell_h));

    return 2;
}

// ═══════════════════════════════════════════════════════════════════════════
// procimage:read
// ═══════════════════════════════════════════════════════════════════════════
fn procimage_read(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *rn_userdata = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "calcImage")));
    ensure_tui_procimage(ud, "calcImage:read, ");

    const col_val: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));
    const row_val: c_int = @intFromFloat(c.luaL_checknumber(ctx, 3));

    const cell = c.arcan_tui_getxy(ud.tui, @intCast(col_val), @intCast(row_val), true);
    var str: [4]u8 = undefined;
    const sz = c.arcan_tui_ucs4utf8(cell.ch, &str);
    c.lua_pushlstring(ctx, &str, if (sz != 0 and str[0] != 0) sz else 0);
    add_attr_tbl(ctx, @bitCast(cell.attr));
    return 2;
}

// ═══════════════════════════════════════════════════════════════════════════
// procimage:get
// ═══════════════════════════════════════════════════════════════════════════
fn procimage_get(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *rn_userdata = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "calcImage")));
    if (ud.valid == false)
        c.arcan_fatal("calcImage:get, calctarget object called out of scope\n");

    const x: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));
    const y: c_int = @intFromFloat(c.luaL_checknumber(ctx, 3));

    if (x >= ud.width or y >= ud.height) {
        c.arcan_fatal("calcImage:get, requested coordinates out of range, source: %d * %d, requested: %d, %d\n", ud.width, ud.height, x, y);
    }

    const img = ud.bufptr;
    var r: u8 = undefined;
    var g: u8 = undefined;
    var b: u8 = undefined;
    var a: u8 = undefined;
    c.RGBA_DECOMP(img[@intCast(y * ud.width + x)], &r, &g, &b, &a);

    const nch: c_int = @intFromFloat(c.luaL_optnumber(ctx, 4, 1.0));
    if (nch <= 0 or nch > 4)
        c.arcan_fatal("calcImage:get, invalid number of channels, requested: %d, valid(1..4)\n", nch);

    if (nch >= 1)
        c.lua_pushnumber(ctx, @floatFromInt(r));
    if (nch >= 2)
        c.lua_pushnumber(ctx, @floatFromInt(g));
    if (nch >= 3)
        c.lua_pushnumber(ctx, @floatFromInt(b));
    if (nch >= 4)
        c.lua_pushnumber(ctx, @floatFromInt(a));

    return nch;
}

// ═══════════════════════════════════════════════════════════════════════════
// meshAccess:indices
// ═══════════════════════════════════════════════════════════════════════════
fn meshaccess_indices(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *mesh_ud = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "meshAccess")));
    const ind: usize = @intCast(luaL_checkint(ctx, 2));

    if (ud.mesh == null or ud.mesh.*.indices == null)
        c.arcan_fatal("meshAccess:indices called outside of valid scope");
    if (ind > ud.mesh.*.n_indices - 1)
        c.arcan_fatal("meshAccess:indices called with OOB index %zu", ind);

    const nargs = c.lua_gettop(ctx);
    if (nargs == 2) {
        if (ud.mesh.*.vertex_size == 2) {
            var k: usize = 0;
            while (k < 6) : (k += 1) {
                c.lua_pushnumber(ctx, @floatFromInt(ud.mesh.*.indices[ind * 6 + k]));
            }
            return 6;
        } else if (ud.mesh.*.vertex_size == 3) {
            var k: usize = 0;
            while (k < 9) : (k += 1) {
                c.lua_pushnumber(ctx, @floatFromInt(ud.mesh.*.indices[ind * 9 + k]));
            }
            return 6; // NOTE: original C returns 6 even for vertex_size==3 (9 values pushed)
        }
    }
    var i: usize = 0;
    while (i < ud.mesh.*.vertex_size * 3) : (i += 1) {
        ud.mesh.*.indices[ind * ud.mesh.*.vertex_size * 3 + i] = @intFromFloat(c.luaL_checknumber(ctx, @intCast(3 + i)));
    }
    ud.mesh.*.dirty = true;
    FLAG_DIRTY(ud.vobj);
    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// meshAccess:vertices
// ═══════════════════════════════════════════════════════════════════════════
fn meshaccess_verts(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *mesh_ud = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "meshAccess")));
    const ind: usize = @intCast(luaL_checkint(ctx, 2));

    if (ud.mesh == null)
        c.arcan_fatal("meshAccess:vertices called outside of valid scope");
    if (ind > ud.mesh.*.n_vertices - 1)
        c.arcan_fatal("meshAccess:vertices called with OOB index %zu", ind);

    const nargs = c.lua_gettop(ctx);
    if (nargs == 2) {
        if (ud.mesh.*.vertex_size == 2) {
            c.lua_pushnumber(ctx, @floatCast(ud.mesh.*.verts[ind * 2 + 0]));
            c.lua_pushnumber(ctx, @floatCast(ud.mesh.*.verts[ind * 2 + 1]));
            return 2;
        } else if (ud.mesh.*.vertex_size == 3) {
            c.lua_pushnumber(ctx, @floatCast(ud.mesh.*.verts[ind * 3 + 0]));
            c.lua_pushnumber(ctx, @floatCast(ud.mesh.*.verts[ind * 3 + 1]));
            c.lua_pushnumber(ctx, @floatCast(ud.mesh.*.verts[ind * 3 + 2]));
            return 3;
        }
        return 0;
    }
    var i: usize = 0;
    while (i < ud.mesh.*.vertex_size) : (i += 1) {
        ud.mesh.*.verts[ind * ud.mesh.*.vertex_size + i] = @floatCast(c.luaL_checknumber(ctx, @intCast(3 + i)));
    }
    ud.mesh.*.dirty = true;
    FLAG_DIRTY(ud.vobj);
    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// meshAccess:texcos
// ═══════════════════════════════════════════════════════════════════════════
fn meshaccess_texcos(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *mesh_ud = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "meshAccess")));
    const ind: usize = @intCast(luaL_checkint(ctx, 2));
    const group: usize = @intCast(luaL_checkint(ctx, 3));

    if (group != 0 and group != 1)
        c.arcan_fatal("meshAccess:texcos only valid group is 0 or 1");

    if (ud.mesh == null)
        c.arcan_fatal("meshAccess:texcos called outside of valid scope");
    if (ind > ud.mesh.*.n_vertices - 1)
        c.arcan_fatal("meshAccess:texcos called with OOB index %zu", ind);

    var dst: [*c]f32 = null;

    if (group == 0) {
        if (ud.mesh.*.txcos == null) {
            ud.mesh.*.txcos = @ptrCast(@alignCast(c.arcan_alloc_mem(
                ud.mesh.*.n_vertices * @sizeOf(f32) * 2,
                c.ARCAN_MEM_MODELDATA,
                c.ARCAN_MEM_NONFATAL | c.ARCAN_MEM_BZERO,
                c.ARCAN_MEMALIGN_NATURAL,
            )));
            if (ud.mesh.*.txcos == null)
                return 0;
        }
        dst = ud.mesh.*.txcos;
    } else {
        if (ud.mesh.*.txcos2 == null) {
            ud.mesh.*.txcos2 = @ptrCast(@alignCast(c.arcan_alloc_mem(
                ud.mesh.*.n_vertices * @sizeOf(f32) * 2,
                c.ARCAN_MEM_MODELDATA,
                c.ARCAN_MEM_NONFATAL | c.ARCAN_MEM_BZERO,
                c.ARCAN_MEMALIGN_NATURAL,
            )));
            if (ud.mesh.*.txcos2 == null)
                return 0;
        }
        dst = ud.mesh.*.txcos2;
    }

    const nargs = c.lua_gettop(ctx);
    if (nargs == 3) {
        c.lua_pushnumber(ctx, @floatCast(dst[ind * 2 + 0]));
        c.lua_pushnumber(ctx, @floatCast(dst[ind * 2 + 1]));
        return 2;
    }

    dst[ind * 2 + 0] = @floatCast(c.luaL_checknumber(ctx, 4));
    dst[ind * 2 + 1] = @floatCast(c.luaL_checknumber(ctx, 5));
    ud.mesh.*.dirty = true;
    FLAG_DIRTY(ud.vobj);

    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// meshAccess:colors
// ═══════════════════════════════════════════════════════════════════════════
fn meshaccess_colors(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *mesh_ud = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "meshAccess")));
    const ind: usize = @intCast(luaL_checkint(ctx, 2));

    if (ud.mesh == null)
        c.arcan_fatal("meshAccess:colors called outside of valid scope");
    if (ind > ud.mesh.*.n_vertices - 1)
        c.arcan_fatal("meshAccess:colors called with OOB index %zu", ind);

    if (ud.mesh.*.colors == null) {
        ud.mesh.*.colors = @ptrCast(@alignCast(c.arcan_alloc_mem(
            ud.mesh.*.n_vertices * @sizeOf(f32) * 4,
            c.ARCAN_MEM_MODELDATA,
            c.ARCAN_MEM_NONFATAL | c.ARCAN_MEM_BZERO,
            c.ARCAN_MEMALIGN_NATURAL,
        )));
        if (ud.mesh.*.colors == null)
            return 0;
    }

    const nargs = c.lua_gettop(ctx);
    if (nargs == 2) {
        // NOTE: C original reads from verts (likely a bug), preserved faithfully
        c.lua_pushnumber(ctx, @floatCast(ud.mesh.*.verts[ind * 4 + 0]));
        c.lua_pushnumber(ctx, @floatCast(ud.mesh.*.verts[ind * 4 + 1]));
        c.lua_pushnumber(ctx, @floatCast(ud.mesh.*.verts[ind * 4 + 2]));
        c.lua_pushnumber(ctx, @floatCast(ud.mesh.*.verts[ind * 4 + 3]));
        return 4;
    }

    ud.mesh.*.colors[ind * 4 + 0] = @floatCast(c.luaL_checknumber(ctx, 3));
    ud.mesh.*.colors[ind * 4 + 1] = @floatCast(c.luaL_checknumber(ctx, 4));
    ud.mesh.*.colors[ind * 4 + 2] = @floatCast(c.luaL_checknumber(ctx, 5));
    ud.mesh.*.colors[ind * 4 + 3] = @floatCast(c.luaL_checknumber(ctx, 6));
    ud.mesh.*.dirty = true;
    FLAG_DIRTY(ud.vobj);
    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// meshAccess:primitive_type
// ═══════════════════════════════════════════════════════════════════════════
fn meshaccess_type(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *mesh_ud = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "meshAccess")));
    const mesh_type = luaL_checkint(ctx, 2);

    if (ud.mesh == null)
        c.arcan_fatal("meshAccess:vertex called outside of valid scope");

    if (mesh_type == 0)
        ud.mesh.*.@"type" = c.AGP_MESH_TRISOUP
    else if (mesh_type == 1)
        ud.mesh.*.@"type" = c.AGP_MESH_POINTCLOUD
    else
        ud.mesh.*.@"type" = c.AGP_MESH_TRISOUP;

    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// arcan_lua_proctarget (FFUNC callback for calctargets)
// ═══════════════════════════════════════════════════════════════════════════
pub export fn arcan_lua_proctarget(
    cmd: c_uint,
    buf: [*c]c.av_pixel,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: c.vfunc_state,
    srcid: arcan_vobj_id,
) c_uint {
    _ = mode;
    _ = srcid;

    if (cmd == @as(c_uint, @bitCast(@as(c_int, c.FFUNC_DESTROY)))) {
        c.free(state.ptr);
        return 0;
    }

    if (cmd != @as(c_uint, @bitCast(@as(c_int, c.FFUNC_READBACK))))
        return 0;

    // Static scrapbuf — persist across calls
    const S = struct {
        var scrapbuf: ?*anyopaque = null;
        var scrapbuf_sz: usize = 0;
    };

    if (S.scrapbuf == null or S.scrapbuf_sz < buf_sz) {
        c.arcan_mem_free(S.scrapbuf);
        S.scrapbuf = c.arcan_alloc_mem(
            buf_sz,
            c.ARCAN_MEM_BINDING,
            0,
            c.ARCAN_MEMALIGN_PAGE,
        );
        if (S.scrapbuf != null) {
            S.scrapbuf_sz = buf_sz;
        } else {
            return 0;
        }
    }

    if ((@intFromPtr(buf) % @as(usize, @intCast(system_page_size)) != 0) and
        (@intFromPtr(S.scrapbuf.?) % @as(usize, @intCast(system_page_size)) != 0))
    {
        const inbuf: [*]volatile u32 = @ptrCast(@alignCast(buf));
        const outbuf: [*]u32 = @ptrCast(@alignCast(S.scrapbuf.?));
        var i: usize = 0;
        while (i < @as(usize, width) * @as(usize, height)) : (i += 1) {
            outbuf[i] = inbuf[i];
        }
    } else {
        _ = c.memcpy(S.scrapbuf, @as(?*const anyopaque, @ptrCast(buf)), buf_sz);
    }

    const src: *proctarget_src = @ptrCast(@alignCast(state.ptr));
    _ = c.lua_rawgeti(src.ctx, c.LUA_REGISTRYINDEX, @intCast(src.cbfun));

    const ud: *rn_userdata = @ptrCast(@alignCast(c.lua_newuserdata(src.ctx, @sizeOf(rn_userdata))));
    _ = c.memset(@ptrCast(ud), 0, @sizeOf(rn_userdata));
    c.luaL_getmetatable(src.ctx, "calcImage");
    _ = c.lua_setmetatable(src.ctx, -2);

    ud.bufptr = @ptrCast(@alignCast(S.scrapbuf));
    ud.width = @intCast(width);
    ud.height = @intCast(height);
    ud.nelem = @as(usize, width) * @as(usize, height);
    ud.valid = true;
    ud.packing = HIST_DIRTY;

    c.lua_pushnumber(src.ctx, @floatFromInt(width));
    c.lua_pushnumber(src.ctx, @floatFromInt(height));
    alt_call(
        src.ctx,
        c.CB_SOURCE_IMAGE,
        @bitCast(@as(c_long, c.EP_TRIGGER_IMAGE)),
        0,
        3,
        0,
        "calc_target:callback",
    );
    ud.valid = false;

    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// image_metadata
// ═══════════════════════════════════════════════════════════════════════════
fn imagemetadata(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 1, &vobj);
    if (@as(c_int, vobj.*.vstore.*.txmapped) != c.TXSTATE_TEX2D) {
        c.lua_pushboolean(ctx, 0);
        return 1;
    }

    const model = c.luaL_checklstring(ctx, 2, null);
    if (c.strcmp(model, "drmv1") != 0) {
        c.lua_pushboolean(ctx, 0);
        return 1;
    }

    if (c.lua_type(ctx, 3) != c.LUA_TTABLE) {
        c.lua_pushboolean(ctx, 0);
        c.arcan_fatal("image_metadata(, , >tbl< ) expected table");
        return 1;
    }

    const ncords: c_int = @intCast(c.lua_objlen(ctx, 3));
    if (ncords < 8) {
        c.arcan_fatal("image_metadata(), wrong coordinate set");
        c.lua_pushboolean(ctx, 0);
        return 1;
    }

    var coords: [8]f32 = undefined;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        _ = c.lua_rawgeti(ctx, 3, @intCast(i + 1));
        coords[i] = @floatCast(c.lua_tonumber(ctx, -1));
        c.lua_settop(ctx, -2);
    }

    const clamp_val = struct {
        fn f(x: f32, lo: f32, hi: f32) f32 {
            return if (x > hi) hi else if (x < lo) lo else x;
        }
    }.f;

    var meta = std.mem.zeroes(c.drm_hdr_meta);
    meta.rx = clamp_val(coords[0], 0.0, 1.3107);
    meta.ry = clamp_val(coords[1], 0.0, 1.3107);
    meta.gx = clamp_val(coords[2], 0.0, 1.3107);
    meta.gy = clamp_val(coords[3], 0.0, 1.3107);
    meta.bx = clamp_val(coords[4], 0.0, 1.3107);
    meta.by = clamp_val(coords[5], 0.0, 1.3107);
    meta.wpx = clamp_val(coords[6], 0.0, 1.3107);
    meta.wpy = clamp_val(coords[7], 0.0, 1.3107);

    const eotf = c.luaL_checklstring(ctx, 8, null);
    if (c.strcmp(eotf, "sdr") == 0)
        meta.eotf = 0
    else if (c.strcmp(eotf, "hdr") == 0)
        meta.eotf = 1
    else if (c.strcmp(eotf, "pq") == 0)
        meta.eotf = 2
    else if (c.strcmp(eotf, "hlg") == 0)
        meta.eotf = 3;

    meta.master_min = @floatCast(c.luaL_checknumber(ctx, 4));
    meta.master_max = @floatCast(c.luaL_checknumber(ctx, 5));
    meta.cll = @floatCast(c.luaL_checknumber(ctx, 6));
    meta.fll = @floatCast(c.luaL_checknumber(ctx, 7));

    vobj.*.vstore.*.hdr.model = 1;
    vobj.*.vstore.*.hdr.drm = meta;

    const fsrv: ?*c.arcan_frameserver = @ptrCast(@alignCast(vobj.*.feed.state.ptr));

    if (fsrv != null and vobj.*.feed.state.tag == c.ARCAN_TAG_FRAMESERV) {
        fsrv_helper_set_flag_block_hdr_meta(@ptrCast(fsrv.?), true);
    }

    c.lua_pushboolean(ctx, 1);
    return 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// image_access_storage
// ═══════════════════════════════════════════════════════════════════════════
fn imagestorage(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 1, &vobj);

    if (@as(c_int, vobj.*.vstore.*.txmapped) != c.TXSTATE_TEX2D) {
        c.arcan_warning("image_access_storage(), referenced object must have a textured backing store.");
        c.lua_pushboolean(ctx, 0);
        return 1;
    }

    if (vobj.*.vstore.*.vinf.text.raw == null) {
        c.arcan_warning("image_access_storage(), referenced object does not have a valid backing store.");
        c.lua_pushboolean(ctx, 0);
        return 1;
    }

    // ZCS-Live / bug-0128: on the render-only (no-scanout) GPU path — e.g. a
    // gbm_kms display with no HDMI connector — a frameserver's frame lives on
    // the GPU texture while the CPU-side text.raw copy is never synced (no
    // readback ticks without scanout). Pull the current GPU contents back
    // into text.raw so the calctarget callback observes live pixels rather
    // than a cleared buffer. Pixel vstores only (skip TUI/tpack text stores,
    // which carry no GPU pixel texture). image_access_storage is an explicit,
    // infrequent op, so a synchronous readback here is acceptable.
    if (vobj.*.vstore.*.vinf.text.unnamed_0.tpack.tui == null)
        c.agp_readback_synchronous(vobj.*.vstore);

    if (c.lua_type(ctx, 2) == c.LUA_TFUNCTION and c.lua_iscfunction(ctx, 2) == 0)
        c.lua_pushvalue(ctx, 2)
    else
        c.arcan_fatal("image_access_storage(), must specify a valid lua function as second argument.");

    const ud: *rn_userdata = @ptrCast(@alignCast(c.lua_newuserdata(ctx, @sizeOf(rn_userdata))));
    _ = c.memset(@ptrCast(ud), 0, @sizeOf(rn_userdata));
    ud.bufptr = vobj.*.vstore.*.vinf.text.raw;
    ud.width = @intCast(vobj.*.vstore.*.w);
    ud.height = @intCast(vobj.*.vstore.*.h);
    ud.nelem = @as(usize, @intCast(ud.width)) * @as(usize, @intCast(ud.height));
    ud.valid = true;
    ud.tui = @ptrCast(vobj.*.vstore.*.vinf.text.unnamed_0.tpack.tui);
    ud.packing = HIST_DIRTY;
    c.luaL_getmetatable(ctx, "calcImage");
    _ = c.lua_setmetatable(ctx, -2);

    c.lua_pushnumber(ctx, @floatFromInt(ud.width));
    c.lua_pushnumber(ctx, @floatFromInt(ud.height));
    var narg: usize = 3;

    if (vobj.*.vstore.*.vinf.text.unnamed_0.tpack.tui != null) {
        var cols: usize = undefined;
        var rows: usize = undefined;
        c.arcan_tui_dimensions(
            @ptrCast(vobj.*.vstore.*.vinf.text.unnamed_0.tpack.tui),
            &rows,
            &cols,
        );
        c.lua_pushnumber(ctx, @floatFromInt(cols));
        c.lua_pushnumber(ctx, @floatFromInt(rows));
        narg += 2;
    }

    alt_call(ctx, c.CB_SOURCE_IMAGE, @bitCast(@as(c_long, c.EP_TRIGGER_IMAGE)), 0, @intCast(narg), 0, "calctarget:callback");

    c.lua_pushboolean(ctx, 1);
    return 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// ZCS-Live Phase 5 — deep-introspection Lua builtins (zcs_deep_*)
//
// Map the live InternPool-arena memfd a may.zcs publisher passed over BCHUNK
// (exposed as `stat.fd` by the BCHUNKSTATE handler above) read-only and run the
// compiler-side Observer over it through the `zcs_deep_*` C bridge — yielding
// REAL Nav fully-qualified names + a Nav/dep summary from the live compile, far
// beyond the 1024×37 telemetry frame. The `meta` argument is the raw bytes of
// the publisher's `ObserverShared.ArenaMeta` block (the appl reads it out of the
// telemetry frame at the known offset and passes it as a Lua string).
// ═══════════════════════════════════════════════════════════════════════════

const ZCS_PROT_READ: c_int = 1;
const ZCS_MAP_SHARED: c_int = 0x01;
extern fn mmap(addr: ?*anyopaque, length: usize, prot: c_int, flags: c_int, fd: c_int, offset: c_long) ?*anyopaque;
extern fn munmap(addr: ?*anyopaque, length: usize) c_int;

// Userdata backing an opened deep view: the bridge handle + the mmap region (so
// __gc can close + unmap) + an owned copy of the meta bytes (the bridge reads
// the meta pointer on summary calls, so it must outlive the open call).
const zcs_deep_ud = extern struct {
    handle: ?*anyopaque,
    map_ptr: ?*anyopaque,
    map_len: usize,
    meta_ptr: ?*anyopaque,
    meta_len: usize,
};

// zcs_deep_open(fd, size, meta_str) -> userdata | (nil, errmsg)
// fd: the arena memfd (from stat.fd). size: committed bytes to map.
// meta_str: raw ObserverShared.ArenaMeta bytes.
fn zcs_deep_open_lua(ctx: ?*lua_State) callconv(.c) c_int {
    const fd: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1));
    const size: usize = @intFromFloat(c.luaL_checknumber(ctx, 2));
    var meta_len: usize = 0;
    const meta_in = c.luaL_checklstring(ctx, 3, &meta_len);
    if (fd < 0 or size == 0 or meta_in == null or meta_len == 0) {
        c.lua_pushnil(ctx);
        c.lua_pushstring(ctx, "zcs_deep_open: bad fd/size/meta");
        return 2;
    }

    // Map the arena read-only, shared (it is a live memfd that keeps growing on
    // the publisher side; MAP_SHARED gives us a consistent window into it).
    const base = mmap(null, size, ZCS_PROT_READ, ZCS_MAP_SHARED, fd, 0);
    if (base == null or @intFromPtr(base) == @as(usize, @bitCast(@as(isize, -1)))) {
        c.lua_pushnil(ctx);
        c.lua_pushstring(ctx, "zcs_deep_open: mmap failed");
        return 2;
    }

    // Copy the meta bytes into a libc allocation owned by the userdata.
    const meta_copy = c.malloc(meta_len);
    if (meta_copy == null) {
        _ = munmap(base, size);
        c.lua_pushnil(ctx);
        c.lua_pushstring(ctx, "zcs_deep_open: oom");
        return 2;
    }
    _ = c.memcpy(meta_copy, @ptrCast(meta_in), meta_len);

    const handle = zcs_deep_open(@intFromPtr(base), meta_copy);
    if (handle == null) {
        c.free(meta_copy);
        _ = munmap(base, size);
        c.lua_pushnil(ctx);
        c.lua_pushstring(ctx, "zcs_deep_open: bridge rejected meta (gate off / empty / build mismatch)");
        return 2;
    }

    const ud: *zcs_deep_ud = @ptrCast(@alignCast(c.lua_newuserdata(ctx, @sizeOf(zcs_deep_ud))));
    ud.* = .{
        .handle = handle,
        .map_ptr = base,
        .map_len = size,
        .meta_ptr = meta_copy,
        .meta_len = meta_len,
    };
    c.luaL_getmetatable(ctx, "zcsDeep");
    _ = c.lua_setmetatable(ctx, -2);
    return 1;
}

// zcs_deep_name(ud, tid, idx) -> string | nil
fn zcs_deep_name_lua(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *zcs_deep_ud = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "zcsDeep")));
    const tid: u32 = @intFromFloat(c.luaL_checknumber(ctx, 2));
    const idx: u32 = @intFromFloat(c.luaL_checknumber(ctx, 3));
    if (ud.handle == null) {
        c.lua_pushnil(ctx);
        return 1;
    }
    var buf: [1024]u8 = undefined;
    const n = zcs_deep_nav_name(ud.handle, tid, idx, &buf, buf.len);
    if (n < 0) {
        c.lua_pushnil(ctx);
        return 1;
    }
    c.lua_pushlstring(ctx, &buf, @intCast(n));
    return 1;
}

// zcs_deep_summary(ud) -> table | nil
fn zcs_deep_summary_lua(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *zcs_deep_ud = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "zcsDeep")));
    if (ud.handle == null) {
        c.lua_pushnil(ctx);
        return 1;
    }
    var s: DeepSummary = .{};
    if (!zcs_deep_summary(ud.handle, &s, ud.meta_ptr)) {
        c.lua_pushnil(ctx);
        return 1;
    }
    c.lua_createtable(ctx, 0, 0);
    const top = c.lua_gettop(ctx);
    set_tblnum(ctx, "thread_count", @floatFromInt(s.thread_count), top);
    set_tblnum(ctx, "nav_total", @floatFromInt(s.nav_total), top);
    set_tblnum(ctx, "nav_unresolved", @floatFromInt(s.nav_unresolved), top);
    set_tblnum(ctx, "nav_type_resolved", @floatFromInt(s.nav_type_resolved), top);
    set_tblnum(ctx, "nav_fully_resolved", @floatFromInt(s.nav_fully_resolved), top);
    set_tblnum(ctx, "nav_unreadable", @floatFromInt(s.nav_unreadable), top);
    set_tblnum(ctx, "dep_entries", @floatFromInt(s.dep_entries_len), top);
    set_tblnum(ctx, "first_dependency", @floatFromInt(s.first_dependency_len), top);
    set_tblnum(ctx, "committed_bytes", @floatFromInt(s.committed_bytes), top);
    set_tblbool(ctx, "build_match", s.build_match != 0, top);
    return 1;
}

// __gc for the zcsDeep metatable: release the bridge view, unmap the arena,
// free the meta copy. Idempotent (nulls the handle).
fn zcs_deep_gc(ctx: ?*lua_State) callconv(.c) c_int {
    const ud: *zcs_deep_ud = @ptrCast(@alignCast(c.luaL_checkudata(ctx, 1, "zcsDeep")));
    if (ud.handle) |h| {
        zcs_deep_close(h);
        ud.handle = null;
    }
    if (ud.map_ptr) |p| {
        _ = munmap(p, ud.map_len);
        ud.map_ptr = null;
    }
    if (ud.meta_ptr) |m| {
        c.free(m);
        ud.meta_ptr = null;
    }
    return 0;
}

// zcs_deep_close(ud) -> explicit early release (also runs via __gc).
fn zcs_deep_close_lua(ctx: ?*lua_State) callconv(.c) c_int {
    return zcs_deep_gc(ctx);
}

// ═══════════════════════════════════════════════════════════════════════════
// spawn_recsubseg (helper)
// ═══════════════════════════════════════════════════════════════════════════
fn spawn_recsubseg(
    ctx: ?*lua_State,
    did: arcan_vobj_id,
    dfsrv: arcan_vobj_id,
    naids: c_int,
    aidlocks: [*c]arcan_aobj_id,
) c_int {
    const vobj = c.arcan_video_getobject(dfsrv);
    const dobj = c.arcan_video_getobject(did);

    const fsrv: ?*c.arcan_frameserver = @ptrCast(@alignCast(vobj.*.feed.state.ptr));

    if (fsrv == null or vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV) {
        c.arcan_fatal("spawn_recsubseg() -- " ++ FATAL_MSG_FRAMESERV);
    }

    const rv = c.platform_fsrv_spawn_subsegment(
        fsrv,
        c.SEGID_ENCODER,
        0,
        dobj.*.vstore.*.w,
        dobj.*.vstore.*.h,
        @intCast(did),
        0,
    );

    if (rv == null) {
        c.arcan_warning("spawn_recsubseg() -- operation failed, couldn't attach output segment.\n");
        return 0;
    }

    const fftag = c.vfunc_state{
        .tag = c.ARCAN_TAG_FRAMESERV,
        .ptr = @ptrCast(rv),
    };
    _ = c.arcan_video_alterfeed(did, c.FFUNC_AVFEED, fftag);

    // grab the requested callback
    if (c.lua_type(ctx, 9) == c.LUA_TFUNCTION and c.lua_iscfunction(ctx, 9) == 0) {
        c.lua_pushvalue(ctx, 9);
        rv.?.*.tag = c.luaL_ref(ctx, c.LUA_REGISTRYINDEX);
    }

    rv.?.*.alocks = aidlocks;
    var base: [*c]arcan_aobj_id = aidlocks;
    while (base != null and base.* != 0) {
        var hookfun: ?*anyopaque = undefined;
        _ = c.arcan_audio_hookfeed(blk: {
            const tmp = base.*;
            base += 1;
            break :blk tmp;
        }, @ptrCast(rv), &c.arcan_frameserver_avfeedmon, &hookfun);
    }

    if (naids > 1)
        c.arcan_frameserver_avfeed_mixer(rv, naids, aidlocks);
    c.arcan_conductor_register_frameserver(rv);

    lua_pushvid(ctx, rv.?.*.vid);
    trace_allocation(ctx, "encode", rv.?.*.vid);
    return 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// spawn_recfsrv (helper)
// ═══════════════════════════════════════════════════════════════════════════
fn spawn_recfsrv(
    ctx: ?*lua_State,
    did: arcan_vobj_id,
    dfsrv: arcan_vobj_id,
    naids: c_int,
    aidlocks: [*c]arcan_aobj_id,
    argl: [*c]const u8,
    resf: [*c]const u8,
) c_int {
    _ = dfsrv;
    if (fsrv_ok == 0)
        return 0;

    const dobj = c.arcan_video_getobject(did);

    var tag: isize = 0;
    if (c.lua_type(ctx, 9) == c.LUA_TFUNCTION and c.lua_iscfunction(ctx, 9) == 0) {
        c.lua_pushvalue(ctx, 9);
        tag = c.luaL_ref(ctx, c.LUA_REGISTRYINDEX);
    }

    var args = std.mem.zeroes(c.frameserver_envp);
    args.use_builtin = true;
    args.custom_feed = did;
    args.args.builtin.mode = "encode";
    args.args.builtin.resource = argl;
    args.init_w = @intCast(dobj.*.vstore.*.w);
    args.init_h = @intCast(dobj.*.vstore.*.h);

    const mvctx = c.platform_launch_fork(&args, @bitCast(tag));
    if (mvctx == null) {
        return 0;
    }

    const fftag = c.vfunc_state{
        .tag = c.ARCAN_TAG_FRAMESERV,
        .ptr = @ptrCast(mvctx),
    };
    _ = c.arcan_video_alterfeed(did, c.FFUNC_AVFEED, fftag);

    // pushing the file descriptor signals the frameserver to start receiving
    var fd: c_int = BADFD;

    if (c.strstr(args.args.builtin.resource, "container=stream") != null or c.strlen(resf) == 0) {
        fd = c.open(NULFILE, c.O_WRONLY | c.O_CLOEXEC);
    } else {
        const fname = findresource(
            resf,
            @bitCast(c.RESOURCE_APPL_TEMP | c.RESOURCE_APPL_SHARED | c.RESOURCE_NS_USER),
            @bitCast(c.ARES_FILE | c.ARES_CREATE),
            &fd,
        );

        if (fname == null) {
            c.arcan_warning("couldn't create output (%s), recorded data will be lost\n", fname);
            fd = c.open(NULFILE, c.O_WRONLY | c.O_CLOEXEC);
        }

        c.arcan_mem_free(@ptrCast(fname));
    }

    if (fd != BADFD) {
        var ev = arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.category = @as(u8, @truncate(@as(c_uint, @intCast(c.EVENT_TARGET))));
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @intCast(c.TARGET_COMMAND_STORE));
        c.lua_pushboolean(ctx, @intFromBool(c.platform_fsrv_pushfd(mvctx, &ev, fd) != 0));
        _ = c.close(fd);
    }

    mvctx.?.*.alocks = aidlocks;

    var base: [*c]arcan_aobj_id = mvctx.?.*.alocks;
    while (base != null and base.* != 0) {
        var hookfun: ?*anyopaque = undefined;
        _ = c.arcan_audio_hookfeed(blk: {
            const tmp = base.*;
            base += 1;
            break :blk tmp;
        }, @ptrCast(mvctx), &c.arcan_frameserver_avfeedmon, &hookfun);
    }

    if (naids > 1)
        c.arcan_frameserver_avfeed_mixer(mvctx, naids, aidlocks);

    mvctx.?.*.flags.activated = 1;
    var activate_ev = arcan_event.zeroes();
    activate_ev.unnamed_0.unnamed_0.category = @intCast(c.EVENT_TARGET);
    activate_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @bitCast(c.TARGET_COMMAND_ACTIVATE);
    _ = tgtevent(did, activate_ev);

    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// rendertarget_bind
// ═══════════════════════════════════════════════════════════════════════════
fn renderbind(ctx: ?*lua_State) callconv(.c) c_int {
    var rt_vobj: [*c]c.arcan_vobject = undefined;
    var fsrv_vobj: [*c]c.arcan_vobject = undefined;

    const rt = luaL_checkvid(ctx, 1, &rt_vobj);
    var fsrvid = luaL_checkvid(ctx, 2, &fsrv_vobj);

    const rtgt = c.arcan_vint_findrt(rt_vobj);
    if (rtgt == null)
        c.arcan_fatal("rendertarget_bind(), 1[src] vid is not a rendertarget\n");

    if (fsrv_vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV)
        c.arcan_fatal("rendertarget_bind(), 2[dst] vid is not a frameserver\n");

    const fsrv: *c.arcan_frameserver = @ptrCast(@alignCast(fsrv_vobj.*.feed.state.ptr));
    if (fsrv.segid != c.SEGID_ENCODER and fsrv.segid != c.SEGID_CLIPBOARD_PASTE)
        c.arcan_fatal("rendertarget_bind(), 2[dst] is not an encoder type\n");

    // synch src-size with dst size
    c.agp_resize_rendertarget(rtgt.*.art, fsrv.desc.width, fsrv.desc.height);
    rtgt.*.readback = rtgt.*.refresh;
    rtgt.*.readcnt = @intCast(if (rtgt.*.readcnt < 0) -rtgt.*.readcnt else rtgt.*.readcnt);
    fsrv.vid = rt;

    // bind new rendertarget as recipient
    _ = c.arcan_video_alterfeed(rt, c.FFUNC_AVFEED, c.vfunc_state{
        .tag = c.ARCAN_TAG_FRAMESERV,
        .ptr = @ptrCast(fsrv),
    });

    // pacify source video
    _ = c.arcan_video_alterfeed(fsrvid, c.FFUNC_NULLFRAME, c.vfunc_state{
        .tag = c.ARCAN_TAG_IMAGE,
        .ptr = null,
    });

    // rewrite pending events
    // ext is at offset 0 in the arcan_event union chain, so
    // offsetof(arcan_event, ext.source) == offsetof(arcan_extevent, source)
    const ext_source_off = @offsetOf(c.arcan_extevent, "source");
    const ext_source_sz = @sizeOf(@TypeOf(@as(c.arcan_extevent, undefined).source));
    c.arcan_event_repl(
        c.arcan_event_defaultctx(),
        c.EVENT_EXTERNAL,
        ext_source_off,
        ext_source_sz,
        @ptrCast(&fsrvid),
        ext_source_off,
        ext_source_sz,
        @constCast(@ptrCast(&rt)),
    );

    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// define_calctarget (procset — manually ported, translate-c failed due to goto)
// ═══════════════════════════════════════════════════════════════════════════
fn procset(ctx: ?*lua_State) callconv(.c) c_int {
    // similar in setup to renderset, but fewer arguments and takes a processing callback
    const did = luaL_checkvid(ctx, 1, null);
    c.luaL_checktype(ctx, 2, c.LUA_TTABLE);
    const nvids: c_int = @intCast(c.lua_objlen(ctx, 2));
    const detach = luaL_checkint(ctx, 3);
    const scale = luaL_checkint(ctx, 4);
    const pollrate = luaL_checkint(ctx, 5);

    const rv = blk: {
        if (nvids <= 0) {
            c.arcan_fatal("define_calctarget(), no source VIDs specified, second argument should be an indexed table with >= 1 valid VIDs.");
        }

        if (detach != RENDERTARGET_DETACH and detach != RENDERTARGET_NODETACH) {
            c.arcan_warning("define_calctarget(%d) invalid arg 3, expected RENDERTARGET_DETACH or RENDERTARGET_NODETACH\n", detach);
            break :blk;
        }

        if (scale != RENDERTARGET_SCALE and scale != RENDERTARGET_NOSCALE) {
            c.arcan_warning("define_calctarget(%d) invalid arg 4, expected RENDERTARGET_SCALE or RENDERTARGET_NOSCALE\n", scale);
            break :blk;
        }

        if (@as(c.arcan_errc, @intCast(c.ARCAN_OK)) != c.arcan_video_setuprendertarget(
            did,
            pollrate,
            pollrate,
            scale == RENDERTARGET_SCALE,
            c.RENDERTARGET_COLOR,
        ))
            c.arcan_fatal("define_calctarget() couldn't setup rendertarget");

        var i: usize = 0;
        while (i < @as(usize, @intCast(nvids))) : (i += 1) {
            _ = c.lua_rawgeti(ctx, 2, @intCast(i + 1));
            const setvid = luavid_tovid(@floatFromInt(c.lua_tointeger(ctx, -1)));
            c.lua_settop(ctx, -2);

            if (setvid == c.ARCAN_VIDEO_WORLDID)
                c.arcan_fatal("define_calctarget(), WORLDID is not a valid data source, use null_surface with image_sharestorage.\n");

            _ = c.arcan_video_attachtorendertarget(did, setvid, detach == RENDERTARGET_DETACH);
        }

        const cbsrc: *proctarget_src = @ptrCast(@alignCast(c.arcan_alloc_mem(
            @sizeOf(proctarget_src),
            c.ARCAN_MEM_VTAG,
            c.ARCAN_MEM_BZERO,
            c.ARCAN_MEMALIGN_NATURAL,
        )));

        cbsrc.ctx = ctx;
        cbsrc.cbfun = 0;

        if (c.lua_type(ctx, 6) == c.LUA_TFUNCTION and c.lua_iscfunction(ctx, 6) == 0) {
            c.lua_pushvalue(ctx, 6);
            cbsrc.cbfun = @intCast(c.luaL_ref(ctx, c.LUA_REGISTRYINDEX));
        }

        const fftag = c.vfunc_state{
            .tag = c.ARCAN_TAG_CUSTOMPROC,
            .ptr = @ptrCast(cbsrc),
        };
        _ = c.arcan_video_alterfeed(did, c.FFUNC_LUA_PROC, fftag);
        break :blk;
    };
    _ = rv;

    // cleanup label target
    return 0;
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part11.zig
// ══════════════════════════════════════════════════════════════════════

// === Part 11: Targets, Recording, Benchmarks, 3D Models, Shader Uniforms,
//              Texture/Blend/Scale Modes, Input Analog, Screenshot, Net,
//              Fonts, Utility (base64/hash/random), extend_baseapi ===
//
// Ported from arcan_lua.c lines 10941-12796.
// LUA_TRACE/LUA_ETRACE removed per porting rules.



// Type aliases

// External symbols
extern var arcan_trace_enabled: bool;

// External engine functions

// Constants
const CONST_ROTATE_RELATIVE: c_int = 10;
const CONST_ROTATE_ABSOLUTE: c_int = 5;
const CONST_DISCOVER_PASSIVE: usize = 1;
const CONST_DISCOVER_SWEEP: usize = 2;
const CONST_DISCOVER_BROADCAST: usize = 3;
const CONST_DISCOVER_DIRECTORY: usize = 4;
const CONST_DISCOVER_TEST: usize = 8;
const CONST_TRUST_KNOWN: usize = 11;
const CONST_TRUST_PERMIT_UNKNOWN: usize = 12;
const CONST_TRUST_TRANSITIVE: usize = 13;


// Module-level state (matches C static struct luactx)



const OUTFMT_PNG: c_int = 0;
const OUTFMT_PNG_FLIP: c_int = 1;
const OUTFMT_RAW8: c_int = 2;
const OUTFMT_RAW24: c_int = 3;
const OUTFMT_RAW32: c_int = 4;

// Modifier table for decode_modifiers
const ModEnt = struct {
    v: c_int,
    s: [*c]const u8,
};

const modtable = [_]ModEnt{
    .{ .v = c.ARKMOD_LSHIFT, .s = "lshift" },
    .{ .v = c.ARKMOD_RSHIFT, .s = "rshift" },
    .{ .v = c.ARKMOD_LALT, .s = "lalt" },
    .{ .v = c.ARKMOD_RALT, .s = "ralt" },
    .{ .v = c.ARKMOD_LCTRL, .s = "lctrl" },
    .{ .v = c.ARKMOD_RCTRL, .s = "rctrl" },
    .{ .v = c.ARKMOD_LMETA, .s = "lmeta" },
    .{ .v = c.ARKMOD_RMETA, .s = "rmeta" },
    .{ .v = c.ARKMOD_NUM, .s = "num" },
    .{ .v = c.ARKMOD_CAPS, .s = "caps" },
    .{ .v = c.ARKMOD_MODE, .s = "mode" },
};

// ============================================================================
// define_nulltarget
// ============================================================================
fn nulltarget(ctx: ?*lua_State) callconv(.c) c_int {
    var dobj: [*c]c.arcan_vobject = undefined;
    const did = luaL_checkvid(ctx, 1, &dobj);

    const state = c.arcan_video_feedstate(did);
    if (state.*.tag != c.ARCAN_TAG_FRAMESERV)
        c.arcan_fatal("define_nulltarget(), nulltarget (1) " ++ FATAL_MSG_FRAMESERV);

    var typ: [*c]const u8 = "clipboard";
    if (c.lua_type(ctx, 2) == c.LUA_TSTRING)
        typ = c.luaL_checklstring(ctx, 2, null);

    var encoder_type: c_uint = c.SEGID_ENCODER;
    if (c.strcmp(typ, "clipboard") == 0) {
        encoder_type = c.SEGID_CLIPBOARD_PASTE;
    } else {
        c.arcan_warning("define_nulltarget(), unknown subtype, assuming encoder.\n");
    }

    const rv = spawn_subsegment(
        @as(?*c.arcan_frameserver, @ptrCast(@alignCast(state.*.ptr))),
        encoder_type,
        0,
        0,
        1,
        1,
    );

    if (rv == null) {
        lua_pushvid(ctx, c.ARCAN_EID);
        return 1;
    }

    const fftag = c.vfunc_state{
        .tag = c.ARCAN_TAG_FRAMESERV,
        .ptr = @as(?*anyopaque, @ptrCast(rv)),
    };

    _ = c.arcan_video_alterfeed(rv.?.*.vid, c.FFUNC_NULLFRAME, fftag);
    rv.?.*.tag = find_lua_callback(ctx);

    lua_pushvid(ctx, rv.?.*.vid);
    return 1;
}

// ============================================================================
// define_feedtarget
// ============================================================================
fn feedtarget(ctx: ?*lua_State) callconv(.c) c_int {
    var dobj: [*c]c.arcan_vobject = undefined;
    var sobj: [*c]c.arcan_vobject = undefined;
    const did = luaL_checkvid(ctx, 1, &dobj);
    const sid = luaL_checkvid(ctx, 2, &sobj);

    const state = c.arcan_video_feedstate(did);
    if (state.*.tag != c.ARCAN_TAG_FRAMESERV)
        c.arcan_fatal("define_feedtarget() feedtarget (1) " ++ FATAL_MSG_FRAMESERV);

    const rv = spawn_subsegment(
        @as(?*c.arcan_frameserver, @ptrCast(@alignCast(state.*.ptr))),
        c.SEGID_ENCODER,
        0,
        0,
        sobj.*.vstore.*.w,
        sobj.*.vstore.*.h,
    );

    if (rv == null) {
        lua_pushvid(ctx, c.ARCAN_EID);
        return 1;
    }

    const fftag = c.vfunc_state{
        .tag = c.ARCAN_TAG_FRAMESERV,
        .ptr = @as(?*anyopaque, @ptrCast(rv)),
    };

    _ = c.arcan_video_shareglstore(sid, rv.?.*.vid);
    _ = c.arcan_video_alterfeed(rv.?.*.vid, c.FFUNC_FEEDCOPY, fftag);

    rv.?.*.tag = find_lua_callback(ctx);

    lua_pushvid(ctx, rv.?.*.vid);
    return 1;
}

// ============================================================================
// str_to_segid (ARCAN_LWA only — included for completeness)
// ============================================================================
const SegLutEntry = struct {
    msg: [*c]const u8,
    val: c_uint,
};

const seglut = [_]SegLutEntry{
    .{ .msg = "cursor", .val = c.SEGID_CURSOR },
    .{ .msg = "popup", .val = c.SEGID_POPUP },
    .{ .msg = "icon", .val = c.SEGID_ICON },
    .{ .msg = "clipboard", .val = c.SEGID_CLIPBOARD },
    .{ .msg = "titlebar", .val = c.SEGID_TITLEBAR },
    .{ .msg = "debug", .val = c.SEGID_DEBUG },
    .{ .msg = "widget", .val = c.SEGID_WIDGET },
    .{ .msg = "media", .val = c.SEGID_MEDIA },
    .{ .msg = "accessibility", .val = c.SEGID_ACCESSIBILITY },
    .{ .msg = "hmd-l", .val = c.SEGID_HMD_L },
    .{ .msg = "hmd-r", .val = c.SEGID_HMD_R },
};

fn str_to_segid(str: [*c]const u8) c_uint {
    for (seglut) |entry| {
        if (c.strcmp(entry.msg, str) == 0)
            return entry.val;
    }
    return c.SEGID_UNKNOWN;
}

// ============================================================================
// define_arcantarget (C:11047-11106)
// In LWA mode, sets up a rendertarget and binds it to a shmif subsegment.
// ============================================================================
fn arcanset(ctx: ?*lua_State) callconv(.c) c_int {
    if (!c.platform_is_lwa_mode()) {
        c.arcan_warning("define_arcantarget() is only valid in LWA mode");
        return 0;
    }

    var dvobj: [*c]c.arcan_vobject = undefined;
    const did = luaL_checkvid(ctx, 1, &dvobj);

    if (dvobj.*.vstore.*.txmapped != c.TXSTATE_TEX2D)
        c.arcan_fatal("define_arcantarget(), first argument " ++
            "must have a texture- based store.");

    const seg_type = str_to_segid(c.luaL_checklstring(ctx, 2, null));
    if (seg_type == c.SEGID_UNKNOWN)
        c.arcan_fatal("define_arcantarget(), second argument " ++
            "(segid) could not be matched.");

    c.luaL_checktype(ctx, 3, c.LUA_TTABLE);
    const nvids: c_int = @intCast(c.lua_objlen(ctx, 3));

    if (nvids <= 0)
        c.arcan_fatal("define_arcantarget(), sources must " ++
            "consist of a table with >= 1 valid vids.");

    const ref = find_lua_callback(ctx);
    if (ref == c.LUA_NOREF)
        c.arcan_fatal("define_arcantarget(), no event handler provided");

    if (c.ARCAN_OK !=
        c.arcan_video_setuprendertarget(did, -1, -1, false, c.RENDERTARGET_COLOR))
    {
        c.arcan_warning("define_arcantarget(), setup rendertarget failed.\n");
        c.lua_pushboolean(ctx, 0);
        return 1;
    }

    var i: c_int = 0;
    while (i < nvids) : (i += 1) {
        _ = c.lua_rawgeti(ctx, 3, i + 1);
        const setvid = c.luavid_tovid(c.lua_tonumber(ctx, -1));
        c.lua_settop(ctx, -(1) - 1);

        if (setvid == c.ARCAN_VIDEO_WORLDID)
            c.arcan_fatal("define_arcantarget(), using WORLDID as a direct source is " ++
                "not permitted, create a null_surface and use image_sharestorage. ");

        _ = c.arcan_video_attachtorendertarget(did, setvid, true);
    }

    c.lua_pushboolean(ctx, @intFromBool(c.platform_lwa_allocbind_feed(
        @ptrCast(ctx), did, seg_type, @as(usize, @intCast(ref)),
    )));
    return 1;
}

// ============================================================================
// define_recordtarget (manually ported — translate-c failed due to goto)
// ============================================================================
fn recordset(ctx: ?*lua_State) callconv(.c) c_int {
    var dvobj: [*c]c.arcan_vobject = undefined;
    var dfsrv_vobj: [*c]c.arcan_vobject = undefined;
    const did = luaL_checkvid(ctx, 1, &dvobj);

    if (dvobj.*.vstore.*.txmapped != c.TXSTATE_TEX2D)
        c.arcan_fatal("define_recordtarget(), recordtarget " ++
            "recipient must have a texture- based store.");

    var resf: [*c]const u8 = null;
    var argl: [*c]u8 = null;
    var dfsrv: arcan_vobj_id = c.ARCAN_EID;

    if (c.lua_type(ctx, 2) == c.LUA_TNUMBER) {
        dfsrv = luaL_checkvid(ctx, 2, &dfsrv_vobj);
    } else {
        resf = c.luaL_checklstring(ctx, 2, null);
        argl = c.strdup(c.luaL_checklstring(ctx, 3, null));
    }

    c.luaL_checktype(ctx, 4, c.LUA_TTABLE);
    var rc: c_int = 0;
    const nvids: c_int = @intCast(c.lua_objlen(ctx, 4));

    if (nvids <= 0)
        c.arcan_fatal("define_recordtarget(), sources must " ++
            "consist of a table with >= 1 valid vids.");

    const detach = luaL_checkint(ctx, 6);
    const scale = luaL_checkint(ctx, 7);
    const pollrate = luaL_checkint(ctx, 8);

    var naids: c_int = 0;
    const global_monitor: bool = false;

    if (c.lua_type(ctx, 5) == c.LUA_TTABLE) {
        naids = @intCast(c.lua_objlen(ctx, 5));
    } else if (c.lua_type(ctx, 5) == c.LUA_TNUMBER) {
        naids = 1;
        const did5 = luaL_checkvid(ctx, 5, null);
        if (did5 != c.ARCAN_VIDEO_WORLDID) {
            c.arcan_warning("recordset(%d) Unexpected value for audio, " ++
                "only a table of selected AID streams or single WORLDID " ++
                "(global monitor) allowed.\n");
            c.free(@as(?*anyopaque, @ptrCast(argl)));
            return rc;
        } else {
            c.arcan_warning("recordset() - global monitor support currently " ++
                "disabled pending refactor.\n");
            naids = 0;
        }
    }

    // Validate detach/scale using labeled block for goto cleanup replacement
    rc = cleanup_blk: {
        if (detach != RENDERTARGET_DETACH and detach != RENDERTARGET_NODETACH) {
            c.arcan_warning("recordset(%d) invalid arg 6, expected" ++
                "\tRENDERTARGET_DETACH or RENDERTARGET_NODETACH\n");
            break :cleanup_blk 0;
        }

        if (scale != RENDERTARGET_SCALE and scale != RENDERTARGET_NOSCALE) {
            c.arcan_warning("recordset(%d) invalid arg 7, " ++
                "expected RENDERTARGET_SCALE or RENDERTARGET_NOSCALE\n");
            break :cleanup_blk 0;
        }

        if (c.ARCAN_OK != c.arcan_video_setuprendertarget(
            did,
            pollrate,
            pollrate,
            scale == RENDERTARGET_SCALE,
            c.RENDERTARGET_COLOR,
        )) {
            c.arcan_warning("define_recordtarget(), setup rendertarget failed.\n");
            break :cleanup_blk 0;
        }

        {
            var i: usize = 0;
            while (i < @as(usize, @intCast(nvids))) : (i += 1) {
                _ = c.lua_rawgeti(ctx, 4, @as(c_int, @intCast(i + 1)));
                const setvid = c.luavid_tovid(@floatFromInt(c.lua_tointeger(ctx, -1)));
                c.lua_settop(ctx, -(1) - 1);

                if (setvid == c.ARCAN_VIDEO_WORLDID)
                    c.arcan_fatal("recordset(), using WORLDID as a direct source is " ++
                        "not permitted, create a null_surface and use image_sharestorage. ");

                _ = c.arcan_video_attachtorendertarget(
                    did,
                    setvid,
                    detach == RENDERTARGET_DETACH,
                );
            }
        }

        var aidlocks: [*c]arcan_aobj_id = null;
        var naids_local = naids;

        // build the set of audio sources
        if (naids_local > 0 and !global_monitor) {
            aidlocks = @as([*c]arcan_aobj_id, @ptrCast(@alignCast(c.arcan_alloc_mem(
                @as(usize, @intCast(naids_local)) * @sizeOf(arcan_aobj_id) + @sizeOf(arcan_aobj_id),
                c.ARCAN_MEM_ATAG,
                0,
                c.ARCAN_MEMALIGN_NATURAL,
            ))));

            aidlocks[@as(usize, @intCast(naids_local))] = 0; // terminate

            var i: usize = 0;
            while (i < @as(usize, @intCast(naids_local))) : (i += 1) {
                _ = c.lua_rawgeti(ctx, 5, @as(c_int, @intCast(i + 1)));
                const setaid: arcan_aobj_id = @intFromFloat(c.lua_tonumber(ctx, -1));
                c.lua_settop(ctx, -(1) - 1);

                if (c.arcan_audio_kind(setaid) != c.AOBJ_STREAM and
                    c.arcan_audio_kind(setaid) != c.AOBJ_CAPTUREFEED)
                {
                    c.arcan_warning("recordset(), unsupported AID source type," ++
                        " only STREAMs currently supported. Audio recording disabled.\n");
                    c.free(@as(?*anyopaque, @ptrCast(aidlocks)));
                    aidlocks = null;
                    naids_local = 0;

                    const argl_len = c.strlen(if (argl != null) argl else @as([*c]u8, @ptrCast(@constCast(""))));
                    const ol: [*c]u8 = @as([*c]u8, @ptrCast(@alignCast(c.arcan_alloc_mem(
                        argl_len + @sizeOf([14]u8),
                        c.ARCAN_MEM_STRINGBUF,
                        0,
                        c.ARCAN_MEMALIGN_NATURAL,
                    ))));
                    _ = c.sprintf(ol, "%s%s", if (argl != null) argl else @as([*c]u8, @ptrCast(@constCast(""))), ":noaudio=true");
                    c.free(@as(?*anyopaque, @ptrCast(argl)));
                    argl = ol;
                    break;
                }

                aidlocks[i] = setaid;
            }
        }

        // Append noaudio string if no audio sources
        if (naids_local == 0 and (argl == null or c.strstr(argl, "noaudio=true") == null)) {
            const argl_len = c.strlen(if (argl != null) argl else @as([*c]u8, @ptrCast(@constCast(""))));
            const ol: [*c]u8 = @as([*c]u8, @ptrCast(@alignCast(c.arcan_alloc_mem(
                argl_len + @sizeOf([14]u8),
                c.ARCAN_MEM_STRINGBUF,
                0,
                c.ARCAN_MEMALIGN_NATURAL,
            ))));
            _ = c.sprintf(ol, "%s%s", if (argl != null) argl else @as([*c]u8, @ptrCast(@constCast(""))), ":noaudio=true");
            c.free(@as(?*anyopaque, @ptrCast(argl)));
            argl = ol;
        }

        // Spawn into vid or create new encode frameserver
        if (dfsrv != c.ARCAN_EID) {
            break :cleanup_blk spawn_recsubseg(ctx, did, dfsrv, naids_local, aidlocks);
        } else {
            break :cleanup_blk spawn_recfsrv(ctx, did, dfsrv, naids_local, aidlocks, argl, resf);
        }
    };

    c.free(@as(?*anyopaque, @ptrCast(argl)));
    return rc;
}

// ============================================================================
// recordtarget_gain
// ============================================================================
fn recordgain(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    _ = luaL_checkvid(ctx, 1, &vobj);
    const fsrv: ?*c.arcan_frameserver = @ptrCast(@alignCast(vobj.*.feed.state.ptr));
    const aid = luaL_checkaid(ctx, 2);
    const left: f32 = @floatCast(c.luaL_checknumber(ctx, 3));
    const right: f32 = @floatCast(c.luaL_checknumber(ctx, 4));

    if (fsrv == null or vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV)
        c.arcan_fatal("recordtarget_gain(1), " ++ FATAL_MSG_FRAMESERV);

    c.arcan_frameserver_update_mixweight(fsrv, @intCast(aid), left, right);

    return 0;
}

// ============================================================================
// benchmark_tracedata
// ============================================================================
fn benchtracedata(ctx: ?*lua_State) callconv(.c) c_int {
    if (!arcan_trace_enabled)
        return 0;

    const subsys = c.luaL_checklstring(ctx, 1, null);
    const message = c.luaL_checklstring(ctx, 2, null);

    const ident: c_int = @intFromFloat(c.luaL_optnumber(ctx, 3, 0));
    const quant: c_int = @intFromFloat(c.luaL_optnumber(ctx, 4, 1));

    const trigger: c_int = @intFromFloat(c.luaL_optnumber(ctx, 5, 0));
    if (trigger < 0 or trigger > 2) {
        c.arcan_fatal("benchmark_tracedata, " ++
            "invalid trigger value (%d) >= 0 <= 2\n", trigger);
    }

    const level: c_int = @intFromFloat(c.luaL_optnumber(ctx, 6, @floatFromInt(c.TRACE_SYS_DEFAULT)));
    if (level < 0 or level > c.TRACE_SYS_ERROR) {
        c.arcan_fatal("benchmark_tracedata, invalid value, " ++
            "expecting: TRACE_PATH_DEFAULT, SLOW, FAST, WARN or ERROR\n");
    }

    var ar: c.lua_Debug = undefined;
    _ = c.lua_getstack(ctx, 2, &ar);
    _ = c.lua_getinfo(ctx, "nSl", &ar);

    c.arcan_trace_mark(
        "lua",
        subsys,
        @as(u8, @bitCast(@as(i8, @truncate(trigger)))),
        @as(u8, @bitCast(@as(i8, @truncate(level)))),
        @as(u64, @bitCast(@as(c_long, ident))),
        @as(u32, @bitCast(quant)),
        message,
        @as([*c]u8, @ptrCast(@alignCast(&ar.short_src))),
        ar.name,
        @as(u32, @bitCast(ar.currentline)),
    );

    return 0;
}

// ============================================================================
// benchmark_enable
// ============================================================================
fn togglebench(ctx: ?*lua_State) callconv(.c) c_int {
    // trigger existing
    c.arcan_trace_setbuffer(null, 0, null);
    c.alt_trace_finish(ctx);

    // callback form? allocate collection buffer and enable tracing
    const callback = find_lua_callback(ctx);
    if (c.lua_type(ctx, 1) == c.LUA_TNUMBER and callback != 0) {
        const buf_sz: usize = @intFromFloat(c.lua_tonumber(ctx, 1) * 1024.0);
        if (!c.alt_trace_start(ctx, callback, buf_sz)) {
            return 0;
        }
        return 0;
    }

    // simple form? normal benchmarking
    const nargs = c.lua_gettop(ctx);

    if (nargs != 0)
        benchdata.bench_enabled = c.lua_toboolean(ctx, 1) != 0
    else
        benchdata.bench_enabled = !benchdata.bench_enabled;

    c.arcan_video_display.ignore_dirty = @intFromBool(benchdata.bench_enabled);

    // always reset on data change
    @memset(std.mem.asBytes(&benchdata.ticktime), 0);
    @memset(std.mem.asBytes(&benchdata.frametime), 0);
    @memset(std.mem.asBytes(&benchdata.framecost), 0);
    benchdata.tickofs = 0;
    benchdata.frameofs = 0;
    benchdata.costofs = 0;
    benchdata.framecount = 0;
    benchdata.tickcount = 0;
    benchdata.costcount = 0;

    return 0;
}

// ============================================================================
// appl_arguments
// ============================================================================
fn getapplarguments(ctx: ?*lua_State) callconv(.c) c_int {
    const argv: [*c][*c]const u8 = luactx.last_argv;
    var argc: c_int = 0;
    c.lua_createtable(ctx, 0, 0);
    const top = c.lua_gettop(ctx);
    while (argv != null and argv[@as(usize, @intCast(argc))] != null) {
        c.lua_pushnumber(ctx, @floatFromInt(argc + 1));
        c.lua_pushstring(ctx, argv[@as(usize, @intCast(argc))]);
        c.lua_rawset(ctx, top);
        argc += 1;
    }

    return 1;
}

// ============================================================================
// benchmark_data
// ============================================================================
fn getbenchvals(ctx: ?*lua_State) callconv(.c) c_int {
    var bench_sz: usize = @sizeOf(@TypeOf(benchdata.ticktime)) / @sizeOf(c_uint);

    c.lua_pushnumber(ctx, @floatFromInt(benchdata.tickcount));
    c.lua_createtable(ctx, 0, 0);
    var top = c.lua_gettop(ctx);
    var i: c_int = @as(c_int, @bitCast(@as(c_uint, @truncate((@as(usize, @intCast(@as(c_uint, benchdata.tickofs))) + 1) % bench_sz))));
    var count: c_int = 0;

    while (i != @as(c_int, @bitCast(@as(c_uint, benchdata.tickofs)))) {
        c.lua_pushnumber(ctx, @floatFromInt(count));
        c.lua_pushnumber(ctx, @floatFromInt(benchdata.ticktime[@as(usize, @intCast(@as(c_uint, @bitCast(i))))]));
        c.lua_rawset(ctx, top);
        count += 1;
        i = @as(c_int, @bitCast(@as(c_uint, @truncate((@as(usize, @intCast(@as(c_uint, @bitCast(i)))) + 1) % bench_sz))));
    }

    bench_sz = @sizeOf(@TypeOf(benchdata.frametime)) / @sizeOf(c_uint);
    i = @as(c_int, @bitCast(@as(c_uint, @truncate((@as(usize, @intCast(@as(c_uint, benchdata.frameofs))) + 1) % bench_sz))));
    c.lua_pushnumber(ctx, @floatFromInt(benchdata.framecount));
    c.lua_createtable(ctx, 0, 0);
    top = c.lua_gettop(ctx);
    count = 0;

    while (i != @as(c_int, @bitCast(@as(c_uint, benchdata.frameofs)))) {
        c.lua_pushnumber(ctx, @floatFromInt(count));
        c.lua_pushnumber(ctx, @floatFromInt(benchdata.frametime[@as(usize, @intCast(@as(c_uint, @bitCast(i))))]));
        c.lua_rawset(ctx, top);
        count += 1;
        i = @as(c_int, @bitCast(@as(c_uint, @truncate((@as(usize, @intCast(@as(c_uint, @bitCast(i)))) + 1) % bench_sz))));
    }

    bench_sz = @sizeOf(@TypeOf(benchdata.framecost)) / @sizeOf(c_uint);
    i = @as(c_int, @bitCast(@as(c_uint, @truncate((@as(usize, @intCast(@as(c_uint, benchdata.costofs))) + 1) % bench_sz))));
    c.lua_pushnumber(ctx, @floatFromInt(benchdata.costcount));
    c.lua_createtable(ctx, 0, 0);
    top = c.lua_gettop(ctx);
    count = 0;

    while (i != @as(c_int, @bitCast(@as(c_uint, benchdata.costofs)))) {
        c.lua_pushnumber(ctx, @floatFromInt(count));
        c.lua_pushnumber(ctx, @floatFromInt(benchdata.framecost[@as(usize, @intCast(@as(c_uint, @bitCast(i))))]));
        c.lua_rawset(ctx, top);
        count += 1;
        i = @as(c_int, @bitCast(@as(c_uint, @truncate((@as(usize, @intCast(@as(c_uint, @bitCast(i)))) + 1) % bench_sz))));
    }

    return 6;
}

// ============================================================================
// benchmark_timestamp
// ============================================================================
fn timestamp(ctx: ?*lua_State) callconv(.c) c_int {
    const stratum: c_int = @intFromFloat(c.luaL_optnumber(ctx, 1, 0));
    switch (stratum) {
        0 => {
            c.lua_pushnumber(ctx, @floatFromInt(c.arcan_timemillis()));
        },
        1 => {
            c.lua_pushnumber(ctx, @floatFromInt(c.time(null)));
        },
        -1 => {
            c.lua_pushnumber(ctx, @floatFromInt(c.arcan_timemicros()));
        },
        else => {
            c.arcan_fatal("benchmark_timestamp(), unknown stratum (%d)\n", stratum);
        },
    }
    return 1;
}

// ============================================================================
// decode_modifiers
// ============================================================================
fn decodemod(ctx: ?*lua_State) callconv(.c) c_int {
    const modval = luaL_checkint(ctx, 1);

    if (c.lua_type(ctx, 2) == c.LUA_TSTRING) {
        var lim: [modtable.len * 9 + 1]u8 = undefined;
        var dst: usize = 0;
        var prepch: u8 = '_';
        const luastr = c.luaL_checklstring(ctx, 2, null);
        if (luastr[0] != 0)
            prepch = luastr[0];

        var prep: bool = false;
        for (modtable) |entry| {
            if (modval & entry.v != 0) {
                if (prep) {
                    lim[dst] = prepch;
                    dst += 1;
                }
                var lbl: [*c]const u8 = entry.s;
                while (lbl[0] != 0) {
                    lim[dst] = lbl[0];
                    dst += 1;
                    lbl += 1;
                }
                prep = true;
            }
        }

        lim[dst] = 0;
        c.lua_pushstring(ctx, @as([*c]const u8, @ptrCast(&lim)));
        return 1;
    }

    c.lua_createtable(ctx, 10, 0);
    const top = c.lua_gettop(ctx);
    var count: c_int = 1;
    for (modtable) |entry| {
        if (modval & entry.v != 0) {
            c.lua_pushnumber(ctx, @floatFromInt(count));
            c.lua_pushstring(ctx, entry.s);
            c.lua_rawset(ctx, top);
            count += 1;
        }
    }

    return 1;
}

// ============================================================================
// move3d_model
// ============================================================================
fn movemodel(ctx: ?*lua_State) callconv(.c) c_int {
    const vid = luaL_checkvid(ctx, 1, null);
    const x: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    const y: f32 = @floatCast(c.luaL_checknumber(ctx, 3));
    const z: f32 = @floatCast(c.luaL_checknumber(ctx, 4));
    const dt: c_uint = @bitCast(luaL_optint(ctx, 5, 0));
    const interp = luaL_optint(ctx, 6, c.ARCAN_VINTER_LINEAR);

    _ = c.arcan_video_objectmove(vid, x, y, z, dt);
    if (dt != 0 and interp < c.ARCAN_VINTER_ENDMARKER)
        _ = c.arcan_video_moveinterp(vid, @as(c_uint, @bitCast(interp)));

    return 0;
}

// ============================================================================
// forward3d_model
// ============================================================================
fn forwardmodel(ctx: ?*lua_State) callconv(.c) c_int {
    const vid = luaL_checkvid(ctx, 1, null);
    const mag: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    const dt: c_uint = @bitCast(luaL_optint(ctx, 3, 0));
    const axismask_x = luaL_optbnumber(ctx, 4, false);
    const axismask_y = luaL_optbnumber(ctx, 5, false);
    const axismask_z = luaL_optbnumber(ctx, 6, false);
    const interp = luaL_optint(ctx, 7, c.ARCAN_VINTER_LINEAR);

    const prop = c.arcan_video_current_properties(vid);

    var view = c.taitbryan_forwardv(prop.rotation.roll, prop.rotation.pitch, prop.rotation.yaw);
    view = c.mul_vectorf(view, mag);
    const newpos = c.add_vector(prop.position, view);

    _ = c.arcan_video_objectmove(
        vid,
        if (axismask_x) prop.position.unnamed_0.unnamed_0.x else newpos.unnamed_0.unnamed_0.x,
        if (axismask_y) prop.position.unnamed_0.unnamed_0.y else newpos.unnamed_0.unnamed_0.y,
        if (axismask_z) prop.position.unnamed_0.unnamed_0.z else newpos.unnamed_0.unnamed_0.z,
        dt,
    );

    if (dt != 0 and interp < c.ARCAN_VINTER_ENDMARKER and interp != c.ARCAN_VINTER_LINEAR)
        _ = c.arcan_video_moveinterp(vid, @as(c_uint, @bitCast(interp)));

    return 0;
}

// ============================================================================
// step3d_model
// ============================================================================
fn stepmodel(ctx: ?*lua_State) callconv(.c) c_int {
    const vid = luaL_checkvid(ctx, 1, null);

    const mag_fwd: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    var mag_side: f32 = @floatCast(c.luaL_checknumber(ctx, 3));
    const dt: c_uint = @bitCast(luaL_optint(ctx, 4, 0));
    const apply = luaL_optbnumber(ctx, 5, true);
    const axismask_x = luaL_optbnumber(ctx, 6, false);
    const axismask_y = luaL_optbnumber(ctx, 7, false);
    const axismask_z = luaL_optbnumber(ctx, 8, false);
    const interp: c_uint = @bitCast(luaL_optint(ctx, 9, c.ARCAN_VINTER_LINEAR));

    const prop = c.arcan_video_current_properties(vid);
    var view = c.taitbryan_forwardv(
        prop.rotation.roll,
        prop.rotation.pitch,
        prop.rotation.yaw,
    );
    const up = c.build_vect(0.0, 1.0, 0.0);

    // first strafe
    if (prop.rotation.pitch > 180.0 or prop.rotation.pitch < -180.0)
        mag_side *= -1.0;
    const strafeview = c.norm_vector(c.crossp_vector(view, up));

    var newpos: c.vector = undefined;
    newpos.unnamed_0.unnamed_0.x = prop.position.unnamed_0.unnamed_0.x + strafeview.unnamed_0.unnamed_0.x * mag_side;
    newpos.unnamed_0.unnamed_0.y = prop.position.unnamed_0.unnamed_0.y + strafeview.unnamed_0.unnamed_0.y * mag_side;
    newpos.unnamed_0.unnamed_0.z = prop.position.unnamed_0.unnamed_0.z + strafeview.unnamed_0.unnamed_0.z * mag_side;

    // then forward
    view = c.mul_vectorf(view, mag_fwd);
    newpos = c.add_vector(newpos, view);

    // only apply if requested
    if (apply) {
        _ = c.arcan_video_objectmove(
            vid,
            if (axismask_x) prop.position.unnamed_0.unnamed_0.x else newpos.unnamed_0.unnamed_0.x,
            if (axismask_y) prop.position.unnamed_0.unnamed_0.y else newpos.unnamed_0.unnamed_0.y,
            if (axismask_z) prop.position.unnamed_0.unnamed_0.z else newpos.unnamed_0.unnamed_0.z,
            dt,
        );

        if (dt != 0 and interp < @as(c_uint, @bitCast(c.ARCAN_VINTER_ENDMARKER)) and interp != @as(c_uint, @bitCast(c.ARCAN_VINTER_LINEAR)))
            _ = c.arcan_video_moveinterp(vid, interp);
    }

    // return the possible new position
    c.lua_pushnumber(ctx, @as(lua_Number, @floatCast(newpos.unnamed_0.unnamed_0.x)));
    c.lua_pushnumber(ctx, @as(lua_Number, @floatCast(newpos.unnamed_0.unnamed_0.y)));
    c.lua_pushnumber(ctx, @as(lua_Number, @floatCast(newpos.unnamed_0.unnamed_0.z)));

    return 3;
}

// ============================================================================
// strafe3d_model
// ============================================================================
fn strafemodel(ctx: ?*lua_State) callconv(.c) c_int {
    const vid = luaL_checkvid(ctx, 1, null);
    var mag: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    const dt: c_uint = @bitCast(luaL_optint(ctx, 3, 0));
    const axismask_x = luaL_optbnumber(ctx, 4, false);
    const axismask_y = luaL_optbnumber(ctx, 5, false);
    const axismask_z = luaL_optbnumber(ctx, 6, false);
    const interp: c_uint = @bitCast(luaL_optint(ctx, 7, c.ARCAN_VINTER_LINEAR));

    _ = axismask_x;
    _ = axismask_y;
    _ = axismask_z;

    var prop = c.arcan_video_current_properties(vid);
    var view = c.taitbryan_forwardv(
        prop.rotation.roll,
        prop.rotation.pitch,
        prop.rotation.yaw,
    );

    const up = c.build_vect(0.0, 1.0, 0.0);
    if (prop.rotation.pitch > 180.0 or prop.rotation.pitch < -180.0)
        mag *= -1.0;

    view = c.norm_vector(c.crossp_vector(view, up));

    prop.position.unnamed_0.unnamed_0.x += view.unnamed_0.unnamed_0.x * mag;
    prop.position.unnamed_0.unnamed_0.z += view.unnamed_0.unnamed_0.z * mag;

    _ = c.arcan_video_objectmove(
        vid,
        prop.position.unnamed_0.unnamed_0.x,
        prop.position.unnamed_0.unnamed_0.y,
        prop.position.unnamed_0.unnamed_0.z,
        dt,
    );

    if (dt != 0 and interp < @as(c_uint, @bitCast(c.ARCAN_VINTER_ENDMARKER)) and interp != @as(c_uint, @bitCast(c.ARCAN_VINTER_LINEAR)))
        _ = c.arcan_video_moveinterp(vid, interp);

    return 0;
}

// ============================================================================
// scale3d_model
// ============================================================================
fn scalemodel(ctx: ?*lua_State) callconv(.c) c_int {
    const vid = luaL_checkvid(ctx, 1, null);
    const sx: f32 = @floatCast(c.luaL_checknumber(ctx, 2));
    const sy: f32 = @floatCast(c.luaL_checknumber(ctx, 3));
    const sz: f32 = @floatCast(c.luaL_checknumber(ctx, 4));
    const dt: c_uint = @bitCast(luaL_optint(ctx, 5, 0));
    const interp: c_uint = @bitCast(luaL_optint(ctx, 6, c.ARCAN_VINTER_LINEAR));

    _ = c.arcan_video_objectscale(vid, sx, sy, sz, dt);

    if (dt != 0 and interp < @as(c_uint, @bitCast(c.ARCAN_VINTER_ENDMARKER)) and interp != @as(c_uint, @bitCast(c.ARCAN_VINTER_LINEAR)))
        _ = c.arcan_video_scaleinterp(vid, interp);

    return 0;
}

// ============================================================================
// orient3d_model
// ============================================================================
fn orientmodel(ctx: ?*lua_State) callconv(.c) c_int {
    const vid = luaL_checkvid(ctx, 1, null);
    const roll: f64 = c.luaL_checknumber(ctx, 2);
    const pitch: f64 = c.luaL_checknumber(ctx, 3);
    const yaw: f64 = c.luaL_checknumber(ctx, 4);
    _ = c.arcan_3d_baseorient(vid, @floatCast(roll), @floatCast(pitch), @floatCast(yaw));
    return 0;
}

// ============================================================================
// shader_ugroup
// ============================================================================
fn shader_ugroup(ctx: ?*lua_State) callconv(.c) c_int {
    const shid: c.agp_shader_id = @intFromFloat(if (c.lua_type(ctx, 1) == c.LUA_TSTRING)
        @as(lua_Number, @floatFromInt(c.agp_shader_lookup(c.luaL_checklstring(ctx, 1, null))))
    else
        c.luaL_checknumber(ctx, 1));

    const newgrp = c.agp_shader_addgroup(shid);
    if (newgrp == c.BROKEN_SHADER) {
        return 0;
    }
    c.lua_pushnumber(ctx, @floatFromInt(newgrp));
    return 1;
}

// ============================================================================
// shader_uniform
// ============================================================================
fn shader_uniform(ctx: ?*lua_State) callconv(.c) c_int {
    var fbuf: [16]f32 = undefined;

    const sid: c_int = @intFromFloat(@abs(c.luaL_checknumber(ctx, 1)));
    var label: [*c]const u8 = c.luaL_checklstring(ctx, 2, null);
    const fmtstr: [*c]const u8 = c.luaL_checklstring(ctx, 3, null);

    const fmtlen = c.strlen(fmtstr);
    const darg: isize = @as(isize, @intCast(c.lua_gettop(ctx))) - @as(isize, @intCast(fmtlen));
    if (darg != 3 and darg != 4)
        c.arcan_fatal("shader_uniform(), invalid number of arguments (%d) for " ++
            "format string: %s\n", c.lua_gettop(ctx), fmtstr);

    const abase: c_int = if (darg == 4) 5 else 4;

    if (c.agp_shader_activate(@as(c.agp_shader_id, @bitCast(sid))) != c.ARCAN_OK) {
        c.arcan_warning("shader_uniform(), shader (%d) failed" ++
            "\tto activate.\n", sid);
        return 0;
    }

    if (label == null)
        label = "unknown";

    if (fmtstr[0] == 'b') {
        var fmt: c_int = @intFromBool(luaL_checkbnumber(ctx, abase));
        c.agp_shader_forceunif(label, c.shdrbool, @as(?*anyopaque, @ptrCast(&fmt)));
    } else if (fmtstr[0] == 'i') {
        var fmt: c_int = @intFromFloat(c.luaL_checknumber(ctx, abase));
        c.agp_shader_forceunif(label, c.shdrint, @as(?*anyopaque, @ptrCast(&fmt)));
    } else {
        var fi: c_uint = 0;
        while (fmtstr[fi] == 'f') {
            fi += 1;
        }
        if (fi != 0) {
            switch (fi) {
                1 => {
                    fbuf[0] = @floatCast(c.luaL_checknumber(ctx, abase));
                    c.agp_shader_forceunif(label, c.shdrfloat, @as(?*anyopaque, @ptrCast(&fbuf)));
                },
                2 => {
                    fbuf[0] = @floatCast(c.luaL_checknumber(ctx, abase));
                    fbuf[1] = @floatCast(c.luaL_checknumber(ctx, abase + 1));
                    c.agp_shader_forceunif(label, c.shdrvec2, @as(?*anyopaque, @ptrCast(&fbuf)));
                },
                3 => {
                    fbuf[0] = @floatCast(c.luaL_checknumber(ctx, abase));
                    fbuf[1] = @floatCast(c.luaL_checknumber(ctx, abase + 1));
                    fbuf[2] = @floatCast(c.luaL_checknumber(ctx, abase + 2));
                    c.agp_shader_forceunif(label, c.shdrvec3, @as(?*anyopaque, @ptrCast(&fbuf)));
                },
                4 => {
                    fbuf[0] = @floatCast(c.luaL_checknumber(ctx, abase));
                    fbuf[1] = @floatCast(c.luaL_checknumber(ctx, abase + 1));
                    fbuf[2] = @floatCast(c.luaL_checknumber(ctx, abase + 2));
                    fbuf[3] = @floatCast(c.luaL_checknumber(ctx, abase + 3));
                    c.agp_shader_forceunif(label, c.shdrvec4, @as(?*anyopaque, @ptrCast(&fbuf)));
                },
                16 => {
                    var idx: c_uint = 16;
                    while (idx > 0) {
                        idx -= 1;
                        fbuf[idx] = @floatCast(c.luaL_checknumber(ctx, abase + @as(c_int, @bitCast(idx))));
                    }
                    c.agp_shader_forceunif(label, c.shdrmat4x4, @as(?*anyopaque, @ptrCast(&fbuf)));
                },
                else => {
                    c.arcan_warning("shader_uniform(%s), unsupported format " ++
                        "string accepted f counts are 1..4 and 16\n", label);
                },
            }
        } else {
            c.arcan_warning("shader_uniform(%s), unspported format " ++
                "\tstring (%s)\n", label, fmtstr);
        }
    }

    // FLAG_DIRTY(NULL)
    _int_flag(null);
    c.arcan_video_display.dirty += 1;

    return 0;
}

// ============================================================================
// rotate3d_model
// ============================================================================
fn rotatemodel(ctx: ?*lua_State) callconv(.c) c_int {
    const vid = luaL_checkvid(ctx, 1, null);
    const roll: f64 = c.luaL_checknumber(ctx, 2);
    const pitch: f64 = c.luaL_checknumber(ctx, 3);
    const yaw: f64 = c.luaL_checknumber(ctx, 4);
    const dt_raw: c_int = @intFromFloat(c.luaL_optnumber(ctx, 5, 0));
    const dt: c_uint = @bitCast(if (dt_raw < 0) -dt_raw else dt_raw);
    const rotate_rel: c_int = @intFromFloat(c.luaL_optnumber(ctx, 6, @floatFromInt(CONST_ROTATE_ABSOLUTE)));

    if (rotate_rel != CONST_ROTATE_RELATIVE and rotate_rel != CONST_ROTATE_ABSOLUTE)
        c.arcan_fatal("rotatemodel(%d), invalid rotation base defined, (%d)" ++
            "\tshould be ROTATE_ABSOLUTE or ROTATE_RELATIVE\n", rotate_rel);

    const prop = c.arcan_video_current_properties(vid);

    if (rotate_rel == CONST_ROTATE_RELATIVE) {
        _ = c.arcan_video_objectrotate3d(
            vid,
            @floatCast(@as(f64, @floatCast(prop.rotation.roll)) + roll),
            @floatCast(@as(f64, @floatCast(prop.rotation.pitch)) + pitch),
            @floatCast(@as(f64, @floatCast(prop.rotation.yaw)) + yaw),
            dt,
        );
    } else {
        _ = c.arcan_video_objectrotate3d(vid, @floatCast(roll), @floatCast(pitch), @floatCast(yaw), dt);
    }

    return 0;
}

// ============================================================================
// switch_default_imageproc
// ============================================================================
fn setimageproc(ctx: ?*lua_State) callconv(.c) c_int {
    const num: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1));

    if (num == c.IMAGEPROC_NORMAL or num == c.IMAGEPROC_FLIPH) {
        c.arcan_video_default_imageprocmode(@as(c_uint, @bitCast(num)));
    } else {
        c.arcan_fatal("setimageproc(%d), invalid image postprocess " ++
            "specified, expected IMAGEPROC_NORMAL or IMAGEPROC_FLIPH\n", num);
    }

    return 0;
}

// ============================================================================
// switch_default_blendmode
// ============================================================================
fn setblendmode(ctx: ?*lua_State) callconv(.c) c_int {
    const num: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1));

    if (!validblendmode(num)) {
        c.arcan_video_default_blendmode(@as(c_uint, @bitCast(num)));
    } else {
        c.arcan_fatal("setblendmode(%d): " ++
            "invalid blend mode specified, expected BLEND_NORMAL or BLEND_FORCE");
    }

    return 0;
}

// ============================================================================
// switch_default_texfilter
// ============================================================================
fn settexfilter(ctx: ?*lua_State) callconv(.c) c_int {
    const mode: c_uint = @intFromFloat(c.luaL_checknumber(ctx, 1));

    if (mode == @as(c_uint, @bitCast(c.ARCAN_VFILTER_TRILINEAR)) or
        mode == @as(c_uint, @bitCast(c.ARCAN_VFILTER_BILINEAR)) or
        mode == @as(c_uint, @bitCast(c.ARCAN_VFILTER_LINEAR)) or
        mode == @as(c_uint, @bitCast(c.ARCAN_VFILTER_NONE)))
    {
        c.arcan_video_default_texfilter(mode);
    }

    return 0;
}

// ============================================================================
// image_texfilter
// ============================================================================
fn changetexfilter(ctx: ?*lua_State) callconv(.c) c_int {
    const mode: c_uint = @intFromFloat(c.luaL_checknumber(ctx, 2));
    const vid = luaL_checkvid(ctx, 1, null);

    if (mode == @as(c_uint, @bitCast(c.ARCAN_VFILTER_TRILINEAR)) or
        mode == @as(c_uint, @bitCast(c.ARCAN_VFILTER_BILINEAR)) or
        mode == @as(c_uint, @bitCast(c.ARCAN_VFILTER_LINEAR)) or
        mode == @as(c_uint, @bitCast(c.ARCAN_VFILTER_NONE)))
    {
        _ = c.arcan_video_objectfilter(vid, mode);
    } else {
        c.arcan_fatal("image_texfilter(vid, s) -- unsupported mode (%d), expected:" ++
            " FILTER_LINEAR, FILTER_BILINEAR or FILTER_TRILINEAR\n", mode);
    }

    return 0;
}

// ============================================================================
// switch_default_texmode
// ============================================================================
fn settexmode(ctx: ?*lua_State) callconv(.c) c_int {
    const numa: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1));
    const numb: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));
    const tmpn: c_long = @intFromFloat(c.luaL_optnumber(ctx, 3, @floatFromInt(c.ARCAN_EID)));

    if ((numa == c.ARCAN_VTEX_CLAMP or numa == c.ARCAN_VTEX_REPEAT) and
        (numb == c.ARCAN_VTEX_CLAMP or numb == c.ARCAN_VTEX_REPEAT))
    {
        if (tmpn != @as(c_long, c.ARCAN_EID)) {
            const dvid = luaL_checkvid(ctx, 3, null);
            _ = c.arcan_video_objecttexmode(dvid, @as(c_uint, @bitCast(numa)), @as(c_uint, @bitCast(numb)));
        } else {
            c.arcan_video_default_texmode(@as(c_uint, @bitCast(numa)), @as(c_uint, @bitCast(numb)));
        }
    }

    return 0;
}

// ============================================================================
// image_tracetag
// ============================================================================
fn tracetag(ctx: ?*lua_State) callconv(.c) c_int {
    const id = luaL_checkvid(ctx, 1, null);
    const msg = c.luaL_optlstring(ctx, 2, null, null);
    const alt = c.luaL_optlstring(ctx, 3, null, null);
    var rc: c_int = 0;

    if (msg == null) {
        var curtag: [*c]const u8 = undefined;
        var curalt: [*c]const u8 = undefined;

        _ = c.arcan_video_readtag(id, &curtag, &curalt);
        c.lua_pushstring(ctx, if (curtag != null) curtag else "(no tag)");
        c.lua_pushstring(ctx, if (curalt != null) curalt else "");

        // allow updating only the alt-text part
        if (alt != null)
            _ = c.arcan_video_tracetag(id, msg, alt);

        rc = 2;
    } else {
        _ = c.arcan_video_tracetag(id, msg, alt);
    }

    return rc;
}

// ============================================================================
// switch_default_scalemode
// ============================================================================
fn setscalemode(ctx: ?*lua_State) callconv(.c) c_int {
    const num: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1));

    if (num == c.ARCAN_VIMAGE_NOPOW2 or num == c.ARCAN_VIMAGE_SCALEPOW2) {
        c.arcan_video_default_scalemode(@as(c_uint, @bitCast(num)));
    } else {
        c.arcan_fatal("setscalemode(%d), invalid scale-mode specified. Expecting:" ++
            "SCALE_NOPOW2, SCALE_POW2 \n", num);
    }

    return 0;
}

// ============================================================================
// utf8kind
// ============================================================================
fn utf8kind(ctx: ?*lua_State) callconv(.c) c_int {
    const num: u8 = @as(u8, @bitCast(@as(i8, @truncate(luaL_checkint(ctx, 1)))));

    if (num & (1 << 7) != 0) {
        c.lua_pushnumber(ctx, @floatFromInt(@as(c_int, if (num & (1 << 6) != 0) 1 else 2)));
    } else {
        c.lua_pushnumber(ctx, 0);
    }

    return 1;
}

// ============================================================================
// inputanalog_filter
// ============================================================================
fn inputfilteranalog(ctx: ?*lua_State) callconv(.c) c_int {
    const joyid: c_int = @intFromFloat(c.luaL_checknumber(ctx, 1));
    const axisid: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));
    const deadzone: c_int = @intFromFloat(c.luaL_checknumber(ctx, 3));
    const lb: c_int = @intFromFloat(c.luaL_checknumber(ctx, 4));
    const ub: c_int = @intFromFloat(c.luaL_checknumber(ctx, 5));
    const buffer_sz: c_int = @intFromFloat(c.luaL_checknumber(ctx, 6));

    const smode = c.luaL_checklstring(ctx, 7, null);
    var mode: c_uint = c.ARCAN_ANALOGFILTER_NONE;

    if (c.strcmp(smode, "drop") == 0) {
        // mode stays NONE
    } else if (c.strcmp(smode, "pass") == 0) {
        mode = c.ARCAN_ANALOGFILTER_PASS;
    } else if (c.strcmp(smode, "average") == 0) {
        mode = c.ARCAN_ANALOGFILTER_AVG;
    } else if (c.strcmp(smode, "latest") == 0) {
        mode = c.ARCAN_ANALOGFILTER_ALAST;
    } else if (c.strcmp(smode, "forget") == 0) {
        mode = c.ARCAN_ANALOGFILTER_FORGET;
    } else {
        c.arcan_warning("inputfilteranalog(), unsupported mode (%s)\n", smode);
    }

    c.platform_event_analogfilter(joyid, axisid, lb, ub, deadzone, buffer_sz, mode);

    return 0;
}

// ============================================================================
// tblanalogenum (helper)
// ============================================================================
fn tblanalogenum(ctx: ?*lua_State, ttop: c_int, mode: c_uint) void {
    switch (mode) {
        c.ARCAN_ANALOGFILTER_NONE => set_tblstr(ctx, "mode", "drop", ttop),
        c.ARCAN_ANALOGFILTER_PASS => set_tblstr(ctx, "mode", "pass", ttop),
        c.ARCAN_ANALOGFILTER_AVG => set_tblstr(ctx, "mode", "average", ttop),
        c.ARCAN_ANALOGFILTER_ALAST => set_tblstr(ctx, "mode", "latest", ttop),
        c.ARCAN_ANALOGFILTER_FORGET => set_tblstr(ctx, "mode", "forget", ttop),
        else => {},
    }
}

// ============================================================================
// singlequery (helper)
// ============================================================================
fn singlequery(ctx: ?*lua_State, devid: c_int, axid: c_int) c_int {
    var lbound: c_int = undefined;
    var ubound: c_int = undefined;
    var dz: c_int = undefined;
    var ksz: c_int = undefined;
    var mode: c_uint = undefined;

    const errc = c.platform_event_analogstate(devid, axid, &lbound, &ubound, &dz, &ksz, &mode);

    if (errc != @as(c.arcan_errc, @intCast(c.ARCAN_OK))) {
        const lbl = c.platform_event_devlabel(devid);
        if (lbl != null) {
            c.lua_createtable(ctx, 0, 0);
            const ttop = c.lua_gettop(ctx);
            set_tbldynstr(ctx, "label", c.platform_event_devlabel(devid), ttop);
            set_tblnum(ctx, "devid", @floatFromInt(devid), ttop);
            return 1;
        }
        return 0;
    }

    c.lua_createtable(ctx, 0, 0);
    const ttop = c.lua_gettop(ctx);
    set_tblnum(ctx, "devid", @floatFromInt(devid), ttop);
    set_tblnum(ctx, "subid", @floatFromInt(axid), ttop);
    set_tbldynstr(ctx, "label", c.platform_event_devlabel(devid), ttop);
    set_tblnum(ctx, "upper_bound", @floatFromInt(ubound), ttop);
    set_tblnum(ctx, "lower_bound", @floatFromInt(lbound), ttop);
    set_tblnum(ctx, "deadzone", @floatFromInt(dz), ttop);
    set_tblnum(ctx, "kernel_size", @floatFromInt(ksz), ttop);
    tblanalogenum(ctx, ttop, mode);

    return 1;
}

// ============================================================================
// focus_target
// ============================================================================
fn targetfocus(ctx: ?*lua_State) callconv(.c) c_int {
    var vobj: [*c]c.arcan_vobject = undefined;
    const checkv: arcan_vobj_id = @intFromFloat(c.luaL_optnumber(ctx, 1, @floatFromInt(c.ARCAN_VIDEO_WORLDID)));

    if (checkv == c.ARCAN_VIDEO_WORLDID) {
        c.arcan_conductor_focus(null);
    } else {
        _ = luaL_checkvid(ctx, 1, &vobj);
        if (vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV or vobj.*.feed.state.ptr == null)
            c.arcan_fatal("focus_target(fsrv) fsrv arg. not tied to a frameserver");

        const fsrv: ?*c.arcan_frameserver = @ptrCast(@alignCast(vobj.*.feed.state.ptr));
        c.arcan_conductor_focus(fsrv);
    }

    return 0;
}

// ============================================================================
// inputanalog_query
// ============================================================================
fn inputanalogquery(ctx: ?*lua_State) callconv(.c) c_int {
    var devid: c_int = 0;
    var resind: c_int = 1;
    const devnum: c_int = @intFromFloat(c.luaL_optnumber(ctx, 1, -1));
    const axnum_raw: c_int = @intFromFloat(c.luaL_optnumber(ctx, 2, 0));
    const axnum: c_int = if (axnum_raw < 0) -axnum_raw else axnum_raw;
    const rescan = luaL_optbnumber(ctx, 3, false);

    if (rescan)
        c.platform_event_rescan_idev(c.arcan_event_defaultctx());

    if (devnum != -1) {
        const n = singlequery(ctx, devnum, axnum);
        return n;
    }

    c.lua_createtable(ctx, 0, 0);
    var errc: c.arcan_errc = @intCast(c.ARCAN_OK);

    const max_devices = 256;
    while (errc != @as(c.arcan_errc, @intCast(c.ARCAN_ERRC_NO_SUCH_OBJECT))) {
        if (devid >= max_devices)
            break;

        var axid: c_int = 0;

        while (true) {
            var lbound: c_int = undefined;
            var ubound: c_int = undefined;
            var dz: c_int = undefined;
            var ksz: c_int = undefined;
            var mode: c_uint = undefined;

            errc = c.platform_event_analogstate(devid, axid, &lbound, &ubound, &dz, &ksz, &mode);

            if (errc != @as(c.arcan_errc, @intCast(c.ARCAN_OK)))
                break;

            const rawtop = c.lua_gettop(ctx);
            c.lua_pushnumber(ctx, @floatFromInt(resind));
            resind += 1;
            c.lua_createtable(ctx, 0, 0);
            const ttop = c.lua_gettop(ctx);

            set_tblnum(ctx, "devid", @floatFromInt(devid), ttop);
            set_tblnum(ctx, "subid", @floatFromInt(axid), ttop);
            set_tbldynstr(ctx, "label", c.platform_event_devlabel(devid), ttop);
            set_tblnum(ctx, "upper_bound", @floatFromInt(ubound), ttop);
            set_tblnum(ctx, "lower_bound", @floatFromInt(lbound), ttop);
            set_tblnum(ctx, "deadzone", @floatFromInt(dz), ttop);
            set_tblnum(ctx, "kernel_size", @floatFromInt(ksz), ttop);
            tblanalogenum(ctx, ttop, mode);

            c.lua_rawset(ctx, rawtop);
            axid += 1;
        }

        devid += 1;
    }

    return 1;
}

// ============================================================================
// inputanalog_toggle
// ============================================================================
fn inputanalogtoggle(ctx: ?*lua_State) callconv(.c) c_int {
    const val = luaL_checkbnumber(ctx, 1);
    const mouse = luaL_optbnumber(ctx, 2, false);

    c.platform_event_analogall(val, mouse);

    return 0;
}

// ============================================================================
// dump_raw (helper for screenshot)
// ============================================================================
fn dump_raw(dst: ?*c.FILE, buf: [*c]c.av_pixel, w: c_int, h: c_int, fmt: c_int) void {
    var sf: usize = 0;

    switch (fmt) {
        OUTFMT_RAW8 => sf = 1,
        OUTFMT_RAW24 => sf = 3,
        OUTFMT_RAW32 => sf = 4,
        else => return,
    }

    const total_size = @as(usize, @intCast(w)) * @as(usize, @intCast(h)) * sf;
    const interim: [*c]u8 = @ptrCast(@alignCast(c.arcan_alloc_mem(
        total_size,
        c.ARCAN_MEM_VBUFFER,
        c.ARCAN_MEM_TEMPORARY | c.ARCAN_MEM_NONFATAL,
        c.ARCAN_MEMALIGN_NATURAL,
    )));

    if (interim == null)
        return;

    var work: [*c]u8 = interim;

    var y: c_int = h - 1;
    while (y >= 0) : (y -= 1) {
        var x: c_int = 0;
        while (x < w) : (x += 1) {
            var rgba: [4]u8 = undefined;
            c.RGBA_DECOMP(
                buf[@as(usize, @intCast(y * w + x))],
                &rgba[0],
                &rgba[1],
                &rgba[2],
                &rgba[3],
            );
            switch (fmt) {
                OUTFMT_RAW8 => {
                    work[0] = @as(u8, @truncate((@as(c_uint, rgba[0]) + @as(c_uint, rgba[1]) + @as(c_uint, rgba[2])) / 3));
                    work += 1;
                },
                OUTFMT_RAW24 => {
                    work[0] = rgba[0];
                    work += 1;
                    work[0] = rgba[1];
                    work += 1;
                    work[0] = rgba[2];
                    work += 1;
                },
                OUTFMT_RAW32 => {
                    _ = c.memcpy(@as(?*anyopaque, @ptrCast(work)), @as(?*const anyopaque, @ptrCast(&rgba)), 4);
                    work += 4;
                },
                else => {},
            }
        }
    }

    _ = c.fwrite(@as(?*const anyopaque, @ptrCast(interim)), total_size, 1, dst);
    c.arcan_mem_free(@as(?*anyopaque, @ptrCast(interim)));
}

// ============================================================================
// pthr_imgwr struct + thread function (helper for screenshot)
// ============================================================================
const pthr_imgwr_t = extern struct {
    dst: ?*c.FILE = null,
    fmt: c_int = 0,
    dw: usize = 0,
    dh: usize = 0,
    databuf: [*c]c.av_pixel = null,
};

fn pthr_imgwr_fn(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const job: *pthr_imgwr_t = @ptrCast(@alignCast(arg));
    c.arcan_trace_threadname("lua_image_writer");

    switch (job.fmt) {
        OUTFMT_PNG => {
            _ = c.arcan_img_outpng(job.dst, job.databuf, job.dw, job.dh, false);
        },
        OUTFMT_PNG_FLIP => {
            _ = c.arcan_img_outpng(job.dst, job.databuf, job.dw, job.dh, true);
        },
        OUTFMT_RAW8, OUTFMT_RAW24, OUTFMT_RAW32 => {
            dump_raw(job.dst, job.databuf, @as(c_int, @intCast(job.dw)), @as(c_int, @intCast(job.dh)), job.fmt);
        },
        else => {},
    }

    _ = c.fclose(job.dst);
    c.arcan_mem_free(@as(?*anyopaque, @ptrCast(job.databuf)));
    c.arcan_mem_free(@as(?*anyopaque, @ptrCast(job)));

    return null;
}

// ============================================================================
// save_screenshot (manually ported — translate-c failed due to goto)
// ============================================================================
fn screenshot(ctx: ?*lua_State) callconv(.c) c_int {
    var databuf: [*c]c.av_pixel = null;
    var bufs: usize = undefined;

    const mode = c.platform_video_dimensions();
    var dw: c_int = @intCast(mode.width);
    var dh: c_int = @intCast(mode.height);

    const resstr: [*c]const u8 = c.luaL_checklstring(ctx, 1, null);
    var sid: arcan_vobj_id = c.ARCAN_EID;

    const fmt: c_int = @intFromFloat(c.luaL_optnumber(ctx, 2, @floatFromInt(OUTFMT_PNG)));
    if (fmt != OUTFMT_PNG and fmt != OUTFMT_PNG_FLIP and
        fmt != OUTFMT_RAW8 and fmt != OUTFMT_RAW24 and fmt != OUTFMT_RAW32)
        c.arcan_fatal("save_screenshot(), invalid/uknown format: %d\n", fmt);

    const local = luaL_optbnumber(ctx, 4, false);

    if (@as(c_int, @intFromFloat(c.luaL_optnumber(ctx, 3, @floatFromInt(c.ARCAN_EID)))) != c.ARCAN_EID) {
        sid = luaL_checkvid(ctx, 3, null);
        _ = c.arcan_video_forceread(sid, local, &databuf, &bufs);

        const com = c.arcan_video_storage_properties(sid);
        dw = @intCast(com.w);
        dh = @intCast(com.h);
    } else {
        _ = c.arcan_video_screenshot(&databuf, &bufs);
    }

    if (databuf == null) {
        c.arcan_warning("save_screenshot() -- insufficient free memory.\n");
        return 0;
    }

    // Use labeled block to handle goto cleanup pattern
    const success = blk: {
        var infd: c_int = -1;
        var fname = findresource(resstr, CREATE_USERMASK, c.ARES_FILE | c.ARES_CREATE, &infd);
        if (fname == null) {
            // if create failed, the file may already exist -- try to open for truncate
            fname = findresource(resstr, CREATE_USERMASK, c.ARES_FILE, null);
            if (fname == null) {
                break :blk false;
            }
            infd = c.open(fname, c.O_WRONLY | c.O_TRUNC);
            if (infd == -1) {
                c.arcan_mem_free(@as(?*anyopaque, @ptrCast(fname)));
                break :blk false;
            }
        }
        c.arcan_mem_free(@as(?*anyopaque, @ptrCast(fname)));

        const job: ?*pthr_imgwr_t = @ptrCast(@alignCast(c.arcan_alloc_mem(
            @sizeOf(pthr_imgwr_t),
            c.ARCAN_MEM_VSTRUCT,
            c.ARCAN_MEM_TEMPORARY | c.ARCAN_MEM_NONFATAL,
            c.ARCAN_MEMALIGN_NATURAL,
        )));

        if (job == null) {
            _ = c.close(infd);
            break :blk false;
        }

        // fdopen — if it fails, descriptor is still open
        job.?.dst = c.fdopen(infd, "wb");
        if (job.?.dst == null) {
            _ = c.close(infd);
            c.arcan_mem_free(@as(?*anyopaque, @ptrCast(job)));
            break :blk false;
        }
        job.?.dw = @intCast(dw);
        job.?.dh = @intCast(dh);
        job.?.fmt = fmt;
        job.?.databuf = databuf;

        // detach as we don't want to find / join later
        var jattr: c.pthread_attr_t = undefined;
        var pthr: c.pthread_t = undefined;
        _ = c.pthread_attr_init(&jattr);
        _ = c.pthread_attr_setdetachstate(&jattr, c.PTHREAD_CREATE_DETACHED);
        _ = c.pthread_create(&pthr, &jattr, pthr_imgwr_fn, @as(?*anyopaque, @ptrCast(job)));

        // thread owns databuf and job now — don't free them
        break :blk true;
    };

    if (!success) {
        // cleanup: thread did not take ownership
        c.arcan_mem_free(@as(?*anyopaque, @ptrCast(databuf)));
    }

    return 0;
}

// ============================================================================
// save_ppm — dump current swapchain frame to /tmp/arcan_screen.ppm
// ============================================================================
extern fn agp_save_ppm() void;
fn save_ppm_lua(ctx: ?*lua_State) callconv(.c) c_int {
    _ = ctx;
    agp_save_ppm();
    return 0;
}

// ============================================================================
// host X11 CLIPBOARD bridge (Piece 2 of copy/paste)
// ============================================================================
extern fn platform_video_set_clipboard(text: [*c]const u8, len: usize) void;
extern fn platform_video_request_clipboard_paste() c_int;
extern fn platform_video_pop_host_paste(out: [*c]u8, cap: usize) usize;

/// set_clipboard(string) → claim X CLIPBOARD ownership and serve `string`
/// to other X clients on subsequent paste requests.
fn set_clipboard_lua(ctx: ?*lua_State) callconv(.c) c_int {
    var slen: usize = 0;
    const sptr = c.lua_tolstring(ctx, 1, &slen);
    if (sptr == null) {
        platform_video_set_clipboard(null, 0);
    } else {
        platform_video_set_clipboard(sptr, slen);
    }
    return 0;
}

/// paste_from_host() → ask the host X server for the current CLIPBOARD
/// payload. Reply lands asynchronously and is forwarded by the platform
/// layer; durian routes via _input_clipboard event hook (target_input).
/// Returns true if the request was issued; false if no XCB backend or a
/// paste is already in flight.
fn paste_from_host_lua(ctx: ?*lua_State) callconv(.c) c_int {
    const ok = platform_video_request_clipboard_paste();
    c.lua_pushboolean(ctx, ok);
    return 1;
}

/// pop_host_paste() → returns the payload of the most recent
/// SelectionNotify reply (UTF-8 string) and clears the stash, or nil
/// if nothing's pending. Durian polls this on a short timer after
/// calling paste_from_host(), then forwards via target_input to the
/// focused window's clipboard segment.
fn pop_host_paste_lua(ctx: ?*lua_State) callconv(.c) c_int {
    var buf: [65536]u8 = undefined;
    const total = platform_video_pop_host_paste(&buf, buf.len);
    if (total == 0) {
        c.lua_pushnil(ctx);
        return 1;
    }
    const n = @min(total, buf.len);
    c.lua_pushlstring(ctx, &buf, n);
    return 1;
}

/// clip_log(str) → debug log to /tmp/clip_xbridge.log. Temporary, drop
/// once paste-from-host is verified end-to-end.
fn clip_log_lua(ctx: ?*lua_State) callconv(.c) c_int {
    var slen: usize = 0;
    const sptr = c.lua_tolstring(ctx, 1, &slen);
    if (sptr == null or slen == 0) return 0;
    const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
    const sc_fwrite = @extern(*const fn ([*c]const u8, usize, usize, ?*anyopaque) callconv(.c) usize, .{ .name = "fwrite" });
    const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
    if (sc_open("/tmp/clip_xbridge.log", "a")) |f| {
        _ = sc_fwrite(sptr, 1, slen, f);
        _ = sc_fwrite("\n", 1, 1, f);
        _ = sc_fclose(f);
    }
    return 0;
}

// ============================================================================
// lua_launch_fsrv (helper)
// ============================================================================
fn lua_launch_fsrv(
    ctx: ?*lua_State,
    args: *c.frameserver_envp,
    callback: isize,
    out: ?*?*c.arcan_frameserver,
) bool {
    if (fsrv_ok == 0) {
        lua_pushvid(ctx, c.ARCAN_EID);
        return false;
    }

    const ref = c.platform_launch_fork(args, @as(usize, @bitCast(callback)));
    if (ref == null) {
        lua_pushvid(ctx, c.ARCAN_EID);
        return false;
    }

    var ev = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_ACTIVATE;
    _ = tgtevent(ref.?.*.vid, ev);
    ref.?.*.flags.activated = 1;

    lua_pushvid(ctx, ref.?.*.vid);
    trace_allocation(ctx, "net", ref.?.*.vid);

    if (out) |o| {
        o.* = ref;
    }
    return true;
}

// ============================================================================
// net_listen
// ============================================================================
fn net_listen(ctx: ?*lua_State) callconv(.c) c_int {
    const ref = find_lua_callback(ctx);
    if (ref == @as(isize, @intCast(c.LUA_NOREF)))
        c.arcan_fatal("net_listen() no handler provided\n");

    const name = c.luaL_checklstring(ctx, 1, null);
    const iface = c.luaL_optlstring(ctx, 2, "", null);
    const port: usize = @intFromFloat(c.luaL_optnumber(ctx, 3, 0));
    const namelen = c.strlen(name);

    if (namelen == 0 or namelen > 30)
        c.arcan_fatal("net_listen(), invalid listening name (%s), " ++
            "length (%zu) should be , 0 < n < 31\n", namelen);

    {
        var key: [*c]const u8 = name;
        while (key[0] != 0) : (key += 1) {
            if (c.isalnum(@as(c_int, key[0])) == 0 and name[0] != '_' and key[0] != '-')
                c.arcan_fatal("net_listen(%s), invalid listening name (%s), " ++
                    " _-a-Z0-9 are permitted in names.\n", key);
        }
    }

    var buf: [256]u8 = undefined;
    _ = c.snprintf(@as([*c]u8, @ptrCast(&buf)), 256, "name=%s:port=%zu:host=%s", name, port, iface);

    var args = std.mem.zeroes(c.frameserver_envp);
    args.use_builtin = true;
    args.args.builtin.mode = "net-srv";
    args.args.builtin.resource = @as([*c]u8, @ptrCast(&buf));

    var out: ?*c.arcan_frameserver = null;
    _ = lua_launch_fsrv(ctx, &args, ref, &out);
    if (out) |o| {
        fsrv_helper_set_flag_no_adopt(@ptrCast(o), true);
    }

    return 1;
}

// ============================================================================
// net_discover
// ============================================================================
fn net_discover(ctx: ?*lua_State) callconv(.c) c_int {
    var ofs: c_int = 1;
    var mode: usize = CONST_DISCOVER_SWEEP;
    var trust: usize = CONST_TRUST_KNOWN;
    var trustm: [*c]const u8 = undefined;
    var discm: [*c]const u8 = undefined;

    if (c.lua_type(ctx, ofs) == c.LUA_TNUMBER) {
        mode = @intFromFloat(c.lua_tonumber(ctx, ofs));
        ofs += 1;
    }

    if (c.lua_type(ctx, ofs) == c.LUA_TNUMBER) {
        trust = @intFromFloat(c.lua_tonumber(ctx, ofs));
        ofs += 1;
    }

    switch (mode) {
        CONST_DISCOVER_SWEEP => discm = "sweep",
        CONST_DISCOVER_PASSIVE => discm = "passive",
        CONST_DISCOVER_BROADCAST => discm = "broadcast",
        CONST_DISCOVER_DIRECTORY => discm = "directory",
        CONST_DISCOVER_TEST => discm = "test",
        else => {
            discm = "bad";
            c.arcan_fatal("net_discover(): unknown discover mode: %zu", mode);
        },
    }

    switch (trust) {
        CONST_TRUST_KNOWN => trustm = "known",
        CONST_TRUST_PERMIT_UNKNOWN => trustm = "unknown",
        CONST_TRUST_TRANSITIVE => trustm = "transitive",
        else => {
            trustm = "bad";
            c.arcan_fatal("net_discover(): unknown trust model: %zu", trust);
        },
    }

    var descr: [*c]const u8 = "";
    if (c.lua_type(ctx, ofs) == c.LUA_TSTRING) {
        descr = c.lua_tolstring(ctx, ofs, null);
        ofs += 1;
    }

    var ref: isize = @as(isize, @intCast(c.LUA_NOREF));
    if (c.lua_type(ctx, ofs) == c.LUA_TFUNCTION and c.lua_iscfunction(ctx, ofs) == 0) {
        c.lua_pushvalue(ctx, ofs);
        ref = @as(isize, @intCast(c.luaL_ref(ctx, c.LUA_REGISTRYINDEX)));
    } else {
        c.arcan_fatal("net_discover(): argument error, expected event handler");
    }

    const len = @sizeOf([34]u8) + @sizeOf([10]u8) + @sizeOf([11]u8) + c.strlen(descr);

    const instr: [*c]u8 = @ptrCast(@alignCast(c.arcan_alloc_mem(
        len,
        c.ARCAN_MEM_STRINGBUF,
        c.ARCAN_MEM_TEMPORARY | c.ARCAN_MEM_NONFATAL,
        c.ARCAN_MEMALIGN_NATURAL,
    )));

    if (instr == null) {
        lua_pushvid(ctx, c.ARCAN_EID);
        return 1;
    }

    _ = c.snprintf(instr, len, "mode=client:discover=%s:trust=%s:opt=%s", discm, trustm, descr);

    var args = std.mem.zeroes(c.frameserver_envp);
    args.use_builtin = true;
    args.args.builtin.mode = "net-cl";
    args.args.builtin.resource = instr;

    _ = lua_launch_fsrv(ctx, &args, ref, null);
    c.arcan_mem_free(@as(?*anyopaque, @ptrCast(instr)));

    return 1;
}

// ============================================================================
// net_open
// ============================================================================
fn net_open(ctx: ?*lua_State) callconv(.c) c_int {
    const host: [*c]u8 = c.strdup(c.luaL_checklstring(ctx, 1, null));
    const ref = find_lua_callback(ctx);

    // @stdin path: generate a connection point for the outer monitor
    if (c.strncmp(host, "@stdin", 6) == 0) {
        var rnd: [6]u8 = undefined;
        var co: [13]u8 = undefined;
        c.arcan_random(@as([*c]u8, @ptrCast(&rnd)), 6);
        for (0..6) |i| {
            co[i * 2] = "0123456789abcdef"[rnd[i] >> 4];
            co[i * 2 + 1] = "0123456789abcdef"[rnd[i] & 0x0f];
        }
        co[12] = 0;

        const newref = c.platform_launch_listen_external(
            @as([*c]u8, @ptrCast(&co)),
            null,
            -1,
            c.ARCAN_SHM_UMASK,
            32,
            32,
            @as(usize, @bitCast(ref)),
        );
        if (newref == null) {
            c.arcan_warning("couldn't listen on connection point (%s)\n", @as([*c]u8, @ptrCast(&co)));
            lua_pushvid(ctx, c.ARCAN_EID);
            c.free(@as(?*anyopaque, @ptrCast(host)));
            return 1;
        }

        var path: [c.PATH_MAX]u8 = undefined;
        if (0 > c.arcan_shmif_resolve_connpath(
            @as([*c]u8, @ptrCast(&co)),
            @as([*c]u8, @ptrCast(&path)),
            c.PATH_MAX,
        )) {
            c.arcan_warning("couldn't resolve socket path");
            _ = c.arcan_frameserver_free(newref);
            lua_pushvid(ctx, c.ARCAN_EID);
            return 1;
        }

        c.free(@as(?*anyopaque, @ptrCast(host)));
        c.arcan_conductor_register_frameserver(newref);
        newref.?.*.segid = c.SEGID_NETWORK_CLIENT;

        if (!c.arcan_monitor_fsrvvid(@as([*c]u8, @ptrCast(&path)), newref)) {
            _ = c.arcan_frameserver_free(newref);
            lua_pushvid(ctx, c.ARCAN_EID);
            return 1;
        }

        trace_allocation(ctx, "net_listen", newref.?.*.vid);
        lua_pushvid(ctx, newref.?.*.vid);
        return 1;
    }

    var instr: [*c]u8 = undefined;
    _ = colon_escape(host);

    // do we have a tag or a probe request?
    if (host[0] == '@' or host[0] == '?') {
        const probe: [*c]const u8 = if (host[0] == '?') "probe:" else "";
        var work_sz: usize = c.strlen(host) + @sizeOf([29]u8);

        // do we have an explicit host specifier?
        if (c.lua_type(ctx, 2) == c.LUA_TSTRING) {
            const hoststr: [*c]u8 = c.strdup(c.luaL_checklstring(ctx, 2, null));
            _ = colon_escape(hoststr);
            work_sz += c.strlen(hoststr);
            instr = @ptrCast(@alignCast(c.arcan_alloc_mem(
                work_sz,
                c.ARCAN_MEM_STRINGBUF,
                c.ARCAN_MEM_TEMPORARY,
                c.ARCAN_MEMALIGN_NATURAL,
            )));
            _ = c.snprintf(instr, work_sz, "mode=client:%stag=%s:host=%s", probe, host + 1, hoststr);
            c.free(@as(?*anyopaque, @ptrCast(hoststr)));
        } else {
            instr = @ptrCast(@alignCast(c.arcan_alloc_mem(
                work_sz,
                c.ARCAN_MEM_STRINGBUF,
                c.ARCAN_MEM_TEMPORARY,
                c.ARCAN_MEMALIGN_NATURAL,
            )));
            _ = c.snprintf(instr, work_sz, "mode=client:%stag=%s", probe, host + 1);
        }
        c.free(@as(?*anyopaque, @ptrCast(host)));
    } else {
        // populate and escape, due to IPv6 addresses etc.
        const prefix = "mode=client:host=";
        const work_sz: usize = c.strlen(host) + prefix.len + 1;
        _ = colon_escape(host);

        instr = @ptrCast(@alignCast(c.arcan_alloc_mem(
            work_sz,
            c.ARCAN_MEM_STRINGBUF,
            c.ARCAN_MEM_TEMPORARY,
            c.ARCAN_MEMALIGN_NATURAL,
        )));

        _ = c.snprintf(instr, work_sz, "%s%s", @as([*c]const u8, prefix.ptr), host);
        c.free(@as(?*anyopaque, @ptrCast(host)));
    }

    var args = std.mem.zeroes(c.frameserver_envp);
    args.use_builtin = true;
    args.preserve_env = true;
    args.args.builtin.mode = "net-cl";
    args.args.builtin.resource = instr;

    _ = lua_launch_fsrv(ctx, &args, ref, null);

    c.free(@as(?*anyopaque, @ptrCast(instr)));

    return 1;
}

// ============================================================================
// arcan_lua_cleanup (public export)
// ============================================================================

// ============================================================================
// register_tbl (helper)
// ============================================================================
fn register_tbl(ctx: ?*lua_State, funtbl_init: [*c]const c.luaL_Reg) void {
    var funtbl = funtbl_init;
    while (funtbl.*.name != null) {
        c.lua_pushstring(ctx, funtbl.*.name);
        c.lua_pushcclosure(ctx, funtbl.*.func, 1);
        c.lua_setglobal(ctx, funtbl.*.name);
        funtbl += 1;
    }
}

// ============================================================================
// system_identstr
// ============================================================================
fn getidentstr(ctx: ?*lua_State) callconv(.c) c_int {
    c.lua_pushstring(ctx, c.platform_video_capstr());
    return 1;
}

// ============================================================================
// system_defaultfont
// ============================================================================
fn setdefaultfont(ctx: ?*lua_State) callconv(.c) c_int {
    const fontn = c.luaL_optlstring(ctx, 1, null, null);
    var fd: c_int = BADFD;

    const fn_res = findresource(fontn, c.RESOURCE_SYS_FONT, c.ARES_FILE | c.ARES_RDONLY, &fd);

    if (fn_res == null) {
        c.lua_pushboolean(ctx, 0);
        return 1;
    }

    c.free(@as(?*anyopaque, @ptrCast(fn_res)));
    if (BADFD == fd) {
        c.lua_pushboolean(ctx, 0);
        return 1;
    }

    const fontsz: c_int = @intFromFloat(c.luaL_checknumber(ctx, 2));
    const fonth: c_int = @intFromFloat(c.luaL_checknumber(ctx, 3));
    const append = luaL_optbnumber(ctx, 4, false);

    const res = c.arcan_video_defaultfont(fontn, fd, fontsz, fonth, append);

    c.lua_pushboolean(ctx, @intFromBool(res));
    return 1;
}

// ============================================================================
// engine_introspect — bug 0117 / 0118 phase 1.4
// ============================================================================
//
// Lua side of the gdb-attach replacement. Returns engine globals by
// name without requiring an external debugger / nm + symbol-address
// dance. The bug 0116 hunt needed exactly this readout:
//
//   atlas_curve_offset, atlas_band_offset, atlas_dirty, atlas_initialized,
//   sdf_next_x, sdf_next_y, sdf_row_height
//
// V1 surface: pass a name OR "atlas" / "*" / empty for the full
// dump as a Lua table. Numeric values come back as numbers; the
// catch-all dump returns a table.
//
// Extension path: each engine module exposes its introspectable
// state via an `*_get_state` extern (see slug_atlas_get_state in
// arcan_ttf.zig:2310). Adding a new module to the registry =
// import the extern here + dispatch its prefix.
const SlugAtlasState_introspect = extern struct {
    curve_offset: u32,
    band_offset: u32,
    max_curve_texels: u32,
    max_band_texels: u32,
    cache_size: u32,
    sdf_next_x: u16,
    sdf_next_y: u16,
    sdf_row_height: u16,
    dirty: u8,
    initialized: u8,
};

extern fn slug_atlas_get_state(out: *SlugAtlasState_introspect) void;

// Push a (string, number) pair into the table at top-of-stack.
fn pushI(ctx: ?*lua_State, k: [*:0]const u8, v: c_int) void {
    c.lua_pushstring(ctx, k);
    c.lua_pushnumber(ctx, @floatFromInt(v));
    c.lua_rawset(ctx, -3);
}
fn pushU(ctx: ?*lua_State, k: [*:0]const u8, v: u32) void {
    c.lua_pushstring(ctx, k);
    c.lua_pushnumber(ctx, @floatFromInt(v));
    c.lua_rawset(ctx, -3);
}
fn pushU16(ctx: ?*lua_State, k: [*:0]const u8, v: u16) void {
    c.lua_pushstring(ctx, k);
    c.lua_pushnumber(ctx, @floatFromInt(v));
    c.lua_rawset(ctx, -3);
}

fn fill_atlas_table(ctx: ?*lua_State) void {
    var st: SlugAtlasState_introspect = undefined;
    slug_atlas_get_state(&st);
    c.lua_newtable(ctx);
    pushU(ctx, "atlas_curve_offset", st.curve_offset);
    pushU(ctx, "atlas_band_offset", st.band_offset);
    pushU(ctx, "atlas_max_curve_texels", st.max_curve_texels);
    pushU(ctx, "atlas_max_band_texels", st.max_band_texels);
    pushU(ctx, "atlas_cache_size", st.cache_size);
    pushU16(ctx, "sdf_next_x", st.sdf_next_x);
    pushU16(ctx, "sdf_next_y", st.sdf_next_y);
    pushU16(ctx, "sdf_row_height", st.sdf_row_height);
    pushI(ctx, "atlas_dirty", st.dirty);
    pushI(ctx, "atlas_initialized", st.initialized);
}

fn streq(a: [*:0]const u8, b: []const u8) bool {
    var i: usize = 0;
    while (i < b.len) : (i += 1) {
        if (a[i] == 0 or a[i] != b[i]) return false;
    }
    return a[i] == 0;
}

fn engineintrospect(ctx: ?*lua_State) callconv(.c) c_int {
    const name_c = c.luaL_optlstring(ctx, 1, "*", null);
    if (name_c == null) {
        c.lua_pushnil(ctx);
        return 1;
    }
    const name: [*:0]const u8 = @ptrCast(name_c);

    // Full dump.
    if (streq(name, "*") or streq(name, "all") or streq(name, "atlas")) {
        fill_atlas_table(ctx);
        return 1;
    }

    // Single-key fast path. Switch on the suffix; supports both bare
    // ("atlas_curve_offset") and module-qualified ("arcan_ttf.atlas_curve_offset")
    // names so hem can use either.
    var st: SlugAtlasState_introspect = undefined;
    slug_atlas_get_state(&st);

    const Match = struct {
        keys: []const []const u8,
        fn matches(self: @This(), n: [*:0]const u8) bool {
            for (self.keys) |k| if (streq(n, k)) return true;
            return false;
        }
    };
    inline for (.{
        .{ &[_][]const u8{ "atlas_curve_offset", "arcan_ttf.atlas_curve_offset" }, st.curve_offset },
        .{ &[_][]const u8{ "atlas_band_offset", "arcan_ttf.atlas_band_offset" }, st.band_offset },
        .{ &[_][]const u8{ "atlas_max_curve_texels" }, st.max_curve_texels },
        .{ &[_][]const u8{ "atlas_max_band_texels" }, st.max_band_texels },
        .{ &[_][]const u8{ "atlas_cache_size" }, st.cache_size },
    }) |entry| {
        const keys: []const []const u8 = entry[0];
        const m = Match{ .keys = keys };
        if (m.matches(name)) {
            c.lua_pushnumber(ctx, @floatFromInt(entry[1]));
            return 1;
        }
    }
    inline for (.{
        .{ &[_][]const u8{ "sdf_next_x", "arcan_ttf.sdf_next_x" }, st.sdf_next_x },
        .{ &[_][]const u8{ "sdf_next_y", "arcan_ttf.sdf_next_y" }, st.sdf_next_y },
        .{ &[_][]const u8{ "sdf_row_height", "arcan_ttf.sdf_row_height" }, st.sdf_row_height },
    }) |entry| {
        const keys: []const []const u8 = entry[0];
        const m = Match{ .keys = keys };
        if (m.matches(name)) {
            c.lua_pushnumber(ctx, @floatFromInt(entry[1]));
            return 1;
        }
    }
    if (streq(name, "atlas_dirty") or streq(name, "arcan_ttf.atlas_dirty")) {
        c.lua_pushnumber(ctx, @floatFromInt(st.dirty));
        return 1;
    }
    if (streq(name, "atlas_initialized") or streq(name, "arcan_ttf.atlas_initialized")) {
        c.lua_pushnumber(ctx, @floatFromInt(st.initialized));
        return 1;
    }

    // Unknown name — return nil so the caller can decide.
    c.lua_pushnil(ctx);
    return 1;
}

// ============================================================================
// util:base64_encode
// ============================================================================
fn base64_encode(ctx: ?*lua_State) callconv(.c) c_int {
    var dsz: usize = undefined;
    var dsz2: usize = undefined;
    const instr: [*c]const u8 = c.luaL_checklstring(ctx, 1, &dsz);
    const outstr: [*c]u8 = @ptrCast(@alignCast(c.arcan_base64_encode(
        @as([*c]const u8, @ptrCast(instr)),
        dsz,
        &dsz2,
        0,
    )));

    c.lua_pushstring(ctx, outstr);
    c.arcan_mem_free(@as(?*anyopaque, @ptrCast(outstr)));

    return 1;
}

// ============================================================================
// util:base64_decode
// ============================================================================
fn base64_decode(ctx: ?*lua_State) callconv(.c) c_int {
    var dsz: usize = undefined;
    const instr: [*c]const u8 = c.luaL_checklstring(ctx, 1, null);
    const outstr: [*c]u8 = @ptrCast(@alignCast(c.arcan_base64_decode(
        @as([*c]const u8, @ptrCast(instr)),
        &dsz,
        0,
    )));
    c.lua_pushlstring(ctx, outstr, dsz);
    c.arcan_mem_free(@as(?*anyopaque, @ptrCast(outstr)));

    return 1;
}

// ============================================================================
// util:random_interval (manually ported — translate-c failed due to __builtin_clzll)
// ============================================================================
fn chacha_interval(ctx: ?*lua_State) callconv(.c) c_int {
    const low: i64 = @intFromFloat(c.luaL_checknumber(ctx, 1));
    const high: i64 = @intFromFloat(c.luaL_checknumber(ctx, 2));
    const len: u64 = @bitCast(high - low);

    const shift: u6 = @intCast(64 - @as(u7, @intCast(@clz(len))));

    var result: i64 = undefined;
    while (true) {
        var buf_bytes: [8]u8 = undefined;
        c.arcan_random(@as([*c]u8, @ptrCast(&buf_bytes)), 8);
        const raw: u64 = @bitCast(buf_bytes);
        const shifted: u64 = raw >> shift;
        if (shifted < len) {
            result = @bitCast(shifted);
            break;
        }
    }

    c.lua_pushnumber(ctx, @floatFromInt(result));
    return 1;
}

// ============================================================================
// util:random_bytes
// ============================================================================
fn chacha_random(ctx: ?*lua_State) callconv(.c) c_int {
    const count: usize = @intFromFloat(c.luaL_checknumber(ctx, 1));
    const buf: [*c]u8 = @ptrCast(@alignCast(c.arcan_alloc_mem(
        count,
        c.ARCAN_MEM_STRINGBUF,
        c.ARCAN_MEM_TEMPORARY | c.ARCAN_MEM_NONFATAL,
        c.ARCAN_MEMALIGN_NATURAL,
    )));
    if (buf != null) {
        c.arcan_random(buf, count);
        c.lua_pushlstring(ctx, buf, count);
        c.arcan_mem_free(@as(?*anyopaque, @ptrCast(buf)));
        return 1;
    }
    return 0;
}

// ============================================================================
// ds4.infer — native DS4-Flash inference entry point.
//
// The ds4 module is built into the may exe via `--dep ds4` in build.zig;
// `ds4_infer_c` is `pub export fn` over there. We declare it `extern`
// here so engine_lib compiles without seeing the ds4 graph and the
// final exe link resolves the symbol.
// ============================================================================
extern fn ds4_infer_c(prompt_ptr: [*]const u8, prompt_len: usize) c_int;

fn ds4_infer_lua(ctx: ?*lua_State) callconv(.c) c_int {
    var dsz: usize = undefined;
    const instr: [*c]const u8 = c.luaL_checklstring(ctx, 1, &dsz);
    const rc = ds4_infer_c(@as([*]const u8, @ptrCast(instr)), dsz);
    c.lua_pushnumber(ctx, @floatFromInt(rc));
    return 1;
}

// ============================================================================
// util:hash
// ============================================================================
fn hash_string(ctx: ?*lua_State) callconv(.c) c_int {
    var str: [*c]const u8 = c.luaL_checklstring(ctx, 1, null);
    const method = c.luaL_optlstring(ctx, 2, "djb", null);

    if (c.strcmp(method, "djb") == 0) {
        var hash: c_ulong = 5381;
        while (str[0] != 0) {
            hash = ((hash << 5) +% hash) +% @as(c_ulong, str[0]);
            str += 1;
        }
        c.lua_pushnumber(ctx, @floatFromInt(hash));
    } else {
        c.arcan_warning("util:hash(%s), unknown hash method" ++
            " supported: djb)\n", method);
        return 0;
    }

    return 1;
}

// ============================================================================
// extend_baseapi — registers util table with to_base64, from_base64, hash,
//                  random_interval, random_bytes
// ============================================================================
fn extend_baseapi(ctx: ?*lua_State) void {
    c.lua_createtable(ctx, 0, 0);
    const top = c.lua_gettop(ctx);

    c.lua_pushstring(ctx, "to_base64");
    c.lua_pushcfunction(ctx, base64_encode);
    c.lua_rawset(ctx, top);

    c.lua_pushstring(ctx, "from_base64");
    c.lua_pushcfunction(ctx, base64_decode);
    c.lua_rawset(ctx, top);

    c.lua_pushstring(ctx, "hash");
    c.lua_pushcfunction(ctx, hash_string);
    c.lua_rawset(ctx, top);

    c.lua_pushstring(ctx, "random_interval");
    c.lua_pushcfunction(ctx, chacha_interval);
    c.lua_rawset(ctx, top);

    c.lua_pushstring(ctx, "random_bytes");
    c.lua_pushcfunction(ctx, chacha_random);
    c.lua_rawset(ctx, top);

    c.lua_setglobal(ctx, "util");
}

// ============================================================================
// extend_ds4api — registers the `ds4` global table with `infer`.
//
// Wires the native DS4-Flash inference entry point (resolved at final-exe
// link time from src/Ds4/api.zig's `ds4_infer_c`) into the durian Lua VM
// as `ds4.infer(prompt)`. Phase-A behavior: prints to stderr and returns
// 0 on success.
// ============================================================================
fn extend_ds4api(ctx: ?*lua_State) void {
    c.lua_createtable(ctx, 0, 0);
    const top = c.lua_gettop(ctx);

    c.lua_pushstring(ctx, "infer");
    c.lua_pushcfunction(ctx, ds4_infer_lua);
    c.lua_rawset(ctx, top);

    c.lua_setglobal(ctx, "ds4");
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part12a.zig
// ══════════════════════════════════════════════════════════════════════

// === Part 12a: Registration tables + alua_exposefuncs + arcan_lua_pushglobalconsts ===
//
// Ported from arcan_lua.c lines 12800-13431.
// Contains the Lua function registration tables and the global constant push function.

// ============================================================================
// Registration Tables (luaL_Reg arrays)
// ============================================================================

const resfuns = [_]luaL_Reg{
    .{ .name = "resource", .func = resource },
    .{ .name = "glob_resource", .func = globresource },
    .{ .name = "list_namespaces", .func = listns },
    .{ .name = "zap_resource", .func = zapresource },
    .{ .name = "open_nonblock", .func = alt_nbio_open },
    .{ .name = "open_rawresource", .func = rawresource },
    .{ .name = "close_rawresource", .func = rawclose },
    .{ .name = "write_rawresource", .func = pushrawstr },
    .{ .name = "read_rawresource", .func = readrawresource },
    .{ .name = "save_screenshot", .func = screenshot },
    .{ .name = "save_ppm", .func = save_ppm_lua },
    .{ .name = "set_clipboard", .func = set_clipboard_lua },
    .{ .name = "paste_from_host", .func = paste_from_host_lua },
    .{ .name = "pop_host_paste", .func = pop_host_paste_lua },
    .{ .name = "clip_log", .func = clip_log_lua },
    .{ .name = null, .func = null },
};

const tgtfuns = [_]luaL_Reg{
    .{ .name = "launch_target", .func = targetlaunch },
    .{ .name = "target_alloc", .func = targetalloc },
    .{ .name = "target_input", .func = targetinput },
    .{ .name = "input_target", .func = targetinput },
    .{ .name = "suspend_target", .func = targetsuspend },
    .{ .name = "resume_target", .func = targetresume },
    .{ .name = "message_target", .func = targetmessage },
    .{ .name = "accept_target", .func = targetaccept },
    .{ .name = "pacify_target", .func = targetpacify },
    .{ .name = "stepframe_target", .func = targetstepframe },
    .{ .name = "snapshot_target", .func = targetsnapshot },
    .{ .name = "restore_target", .func = targetrestore },
    .{ .name = "bond_target", .func = targetbond },
    .{ .name = "reset_target", .func = targetreset },
    .{ .name = "focus_target", .func = targetfocus },
    .{ .name = "target_portconfig", .func = targetportcfg },
    .{ .name = "target_framemode", .func = targetskipmodecfg },
    .{ .name = "target_verbose", .func = targetverbose },
    .{ .name = "target_synchronous", .func = targetsynchronous },
    .{ .name = "target_flags", .func = targetflags },
    .{ .name = "target_graphmode", .func = targetgraph },
    .{ .name = "target_anchorhint", .func = targetanchor },
    .{ .name = "target_displayhint", .func = targetdisphint },
    .{ .name = "target_devicehint", .func = targetdevhint },
    .{ .name = "target_fonthint", .func = targetfonthint },
    .{ .name = "target_geohint", .func = targetgeohint },
    .{ .name = "target_seek", .func = targetseek },
    .{ .name = "target_parent", .func = targetparent },
    .{ .name = "target_coreopt", .func = targetcoreopt },
    .{ .name = "target_updatehandler", .func = targethandler },
    .{ .name = "arcantarget_hint", .func = arcantargethint },
    .{ .name = "define_rendertarget", .func = renderset },
    .{ .name = "define_linktarget", .func = linkset },
    .{ .name = "define_recordtarget", .func = recordset },
    .{ .name = "define_calctarget", .func = procset },
    .{ .name = "define_feedtarget", .func = feedtarget },
    .{ .name = "define_nulltarget", .func = nulltarget },
    .{ .name = "define_arcantarget", .func = arcanset },
    .{ .name = "rendertarget_forceupdate", .func = rendertargetforce },
    .{ .name = "rendertarget_vids", .func = rendertarget_vids },
    .{ .name = "recordtarget_gain", .func = recordgain },
    .{ .name = "rendertarget_detach", .func = renderdetach },
    .{ .name = "rendertarget_bind", .func = renderbind },
    .{ .name = "rendertarget_attach", .func = renderattach },
    .{ .name = "rendertarget_noclear", .func = rendernoclear },
    .{ .name = "rendertarget_id", .func = rendertargetid },
    .{ .name = "rendertarget_range", .func = rendertargetrange },
    .{ .name = "rendertarget_metrics", .func = rendertargetmetrics },
    .{ .name = "rendertarget_reconfigure", .func = renderreconf },
    .{ .name = "launch_decode", .func = launchdecode },
    .{ .name = "launch_avfeed", .func = launchavfeed },
    .{ .name = null, .func = null },
};

const dbfuns = [_]luaL_Reg{
    .{ .name = "store_key", .func = storekey },
    .{ .name = "get_key", .func = getkey },
    .{ .name = "get_keys", .func = getkeys },
    .{ .name = "match_keys", .func = matchkeys },
    .{ .name = "list_targets", .func = gettargets },
    .{ .name = "list_target_tags", .func = gettags },
    .{ .name = "target_configurations", .func = getconfigs },
    .{ .name = null, .func = null },
};

const custfuns = [_]luaL_Reg{
    .{ .name = null, .func = null },
};

const audfuns = [_]luaL_Reg{
    .{ .name = "play_audio", .func = playaudio },
    .{ .name = "delete_audio", .func = dropaudio },
    .{ .name = "load_asample", .func = loadasample },
    .{ .name = "audio_gain", .func = gain },
    .{ .name = "audio_buffer_size", .func = abufsz },
    .{ .name = "audio_position", .func = audiopos },
    .{ .name = "audio_outputs", .func = audioout },
    .{ .name = "audio_listener", .func = audiolisten },
    .{ .name = "audio_reconfigure", .func = audioreconf },
    .{ .name = "capture_audio", .func = captureaudio },
    .{ .name = "list_audio_inputs", .func = capturelist },
    .{ .name = null, .func = null },
};

const imgfuns = [_]luaL_Reg{
    .{ .name = "load_image", .func = loadimage },
    .{ .name = "load_image_asynch", .func = loadimageasynch },
    .{ .name = "image_loaded", .func = imageloaded },
    .{ .name = "delete_image", .func = deleteimage },
    .{ .name = "show_image", .func = showimage },
    .{ .name = "hide_image", .func = hideimage },
    .{ .name = "move_image", .func = moveimage },
    .{ .name = "nudge_image", .func = nudgeimage },
    .{ .name = "rotate_image", .func = rotateimage },
    .{ .name = "scale_image", .func = scaleimage },
    .{ .name = "resize_image", .func = scaleimage2 },
    .{ .name = "resample_image", .func = resampleimage },
    .{ .name = "blend_image", .func = imageopacity },
    .{ .name = "crop_image", .func = cropimage },
    .{ .name = "persist_image", .func = imagepersist },
    .{ .name = "image_parent", .func = imageparent },
    .{ .name = "center_image", .func = centerimage },
    .{ .name = "image_children", .func = imagechildren },
    .{ .name = "order_image", .func = orderimage },
    .{ .name = "max_current_image_order", .func = maxorderimage },
    .{ .name = "link_image", .func = linkimage },
    .{ .name = "relink_image", .func = relinkimage },
    .{ .name = "set_image_as_frame", .func = imageasframe },
    .{ .name = "image_framesetsize", .func = framesetalloc },
    .{ .name = "image_framecyclemode", .func = framesetcycle },
    .{ .name = "image_pushasynch", .func = pushasynch },
    .{ .name = "image_active_frame", .func = activeframe },
    .{ .name = "image_origo_offset", .func = origoofs },
    .{ .name = "image_inherit_order", .func = orderinherit },
    .{ .name = "image_tesselation", .func = imagetess },
    .{ .name = "expire_image", .func = setlife },
    .{ .name = "reset_image_transform", .func = resettransform },
    .{ .name = "instant_image_transform", .func = instanttransform },
    .{ .name = "tag_image_transform", .func = tagtransform },
    .{ .name = "image_transform_cycle", .func = cycletransform },
    .{ .name = "copy_image_transform", .func = copytransform },
    .{ .name = "transfer_image_transform", .func = transfertransform },
    .{ .name = "copy_surface_properties", .func = copyimageprop },
    .{ .name = "image_set_txcos", .func = settxcos },
    .{ .name = "image_get_txcos", .func = gettxcos },
    .{ .name = "image_set_txcos_default", .func = settxcos_default },
    .{ .name = "image_texfilter", .func = changetexfilter },
    .{ .name = "image_scale_txcos", .func = scaletxcos },
    .{ .name = "image_clip_on", .func = clipon },
    .{ .name = "image_clip_off", .func = clipoff },
    .{ .name = "image_mask_toggle", .func = togglemask },
    .{ .name = "image_mask_set", .func = setmask },
    .{ .name = "image_screen_coordinates", .func = screencoord },
    .{ .name = "image_mask_clear", .func = clearmask },
    .{ .name = "image_tracetag", .func = tracetag },
    .{ .name = "image_mask_clearall", .func = clearall },
    .{ .name = "image_shader", .func = setshader },
    .{ .name = "image_state", .func = imagestate },
    .{ .name = "image_access_storage", .func = imagestorage },
    .{ .name = "image_resize_storage", .func = imageresizestorage },
    .{ .name = "image_metadata", .func = imagemetadata },
    .{ .name = "image_sharestorage", .func = sharestorage },
    .{ .name = "image_matchstorage", .func = matchstorage },
    .{ .name = "cursor_setstorage", .func = cursorstorage },
    .{ .name = "cursor_position", .func = cursorposition },
    .{ .name = "move_cursor", .func = cursormove },
    .{ .name = "nudge_cursor", .func = cursornudge },
    .{ .name = "resize_cursor", .func = cursorsize },
    .{ .name = "image_color", .func = imagecolor },
    .{ .name = "image_mipmap", .func = imagemipmap },
    .{ .name = "fill_surface", .func = fillsurface },
    .{ .name = "alloc_surface", .func = allocsurface },
    .{ .name = "raw_surface", .func = rawsurface },
    .{ .name = "color_surface", .func = colorsurface },
    .{ .name = "null_surface", .func = nullsurface },
    .{ .name = "image_surface_properties", .func = getimageprop },
    .{ .name = "image_storage_properties", .func = getimagestorageprop },
    .{ .name = "image_storage_slice", .func = slicestore },
    .{ .name = "render_text", .func = rendertext },
    .{ .name = "text_surface", .func = textsurface },
    .{ .name = "text_dimensions", .func = textdimensions },
    .{ .name = "random_surface", .func = randomsurface },
    .{ .name = "force_image_blend", .func = forceblend },
    .{ .name = "image_hit", .func = hittest },
    .{ .name = "pick_items", .func = pick },
    .{ .name = "image_surface_initial_properties", .func = getimageinitprop },
    .{ .name = "image_surface_resolve_properties", .func = getimageresolveprop },
    .{ .name = "image_surface_resolve", .func = getimageresolveprop },
    .{ .name = "image_surface_initial", .func = getimageinitprop },
    .{ .name = null, .func = null },
};

const threedfuns = [_]luaL_Reg{
    .{ .name = "new_3dmodel", .func = buildmodel },
    .{ .name = "finalize_3dmodel", .func = finalmodel },
    .{ .name = "add_3dmesh", .func = loadmesh },
    .{ .name = "attrtag_model", .func = attrtag },
    .{ .name = "move3d_model", .func = movemodel },
    .{ .name = "rotate3d_model", .func = rotatemodel },
    .{ .name = "orient3d_model", .func = orientmodel },
    .{ .name = "scale3d_model", .func = scalemodel },
    .{ .name = "forward3d_model", .func = forwardmodel },
    .{ .name = "strafe3d_model", .func = strafemodel },
    .{ .name = "step3d_model", .func = stepmodel },
    .{ .name = "camtag_model", .func = camtag },
    .{ .name = "build_3dplane", .func = buildplane },
    .{ .name = "build_3dbox", .func = buildbox },
    .{ .name = "build_sphere", .func = buildsphere },
    .{ .name = "build_cylinder", .func = buildcylinder },
    .{ .name = "build_pointcloud", .func = pointcloud },
    .{ .name = "scale_3dvertices", .func = scale3dverts },
    .{ .name = "swizzle_model", .func = swizzlemodel },
    .{ .name = "mesh_shader", .func = setmeshshader },
    .{ .name = null, .func = null },
};

const sysfuns = [_]luaL_Reg{
    .{ .name = "shutdown", .func = alua_shutdown },
    .{ .name = "warning", .func = warning },
    .{ .name = "shmifmon", .func = shmifmon_lua },
    .{ .name = "system_load", .func = systemload },
    .{ .name = "system_context_size", .func = systemcontextsize },
    .{ .name = "system_snapshot", .func = syssnap },
    .{ .name = "system_collapse", .func = syscollapse },
    .{ .name = "subsystem_reset", .func = subsys_reset },
    .{ .name = "utf8kind", .func = utf8kind },
    .{ .name = "decode_modifiers", .func = decodemod },
    .{ .name = "benchmark_enable", .func = togglebench },
    .{ .name = "benchmark_tracedata", .func = benchtracedata },
    .{ .name = "benchmark_timestamp", .func = timestamp },
    .{ .name = "benchmark_data", .func = getbenchvals },
    .{ .name = "appl_arguments", .func = getapplarguments },
    .{ .name = "system_identstr", .func = getidentstr },
    .{ .name = "system_defaultfont", .func = setdefaultfont },
    .{ .name = "engine_introspect", .func = engineintrospect },
    .{ .name = "frameserver_debugstall", .func = debugstall },
    .{ .name = "VRES_AUTORES", .func = videocanvasrsz },
    // ZCS-Live Phase 5: open a deep view over a live may.zcs arena memfd.
    // Returns a `zcsDeep` userdata with :name(tid,idx) / :summary() / :close().
    .{ .name = "zcs_deep_open", .func = zcs_deep_open_lua },
    .{ .name = null, .func = null },
};

const iofuns = [_]luaL_Reg{
    .{ .name = "kbd_repeat", .func = kbdrepeat },
    .{ .name = "toggle_mouse_grab", .func = mousegrab },
    .{ .name = "input_capabilities", .func = inputcap },
    .{ .name = "input_samplebase", .func = inputbase },
    .{ .name = "input_remap_translation", .func = inputremaptranslation },
    .{ .name = "set_led", .func = setled },
    .{ .name = "led_intensity", .func = led_intensity },
    .{ .name = "set_led_rgb", .func = led_rgb },
    .{ .name = "controller_leds", .func = n_leds },
    .{ .name = "vr_setup", .func = vr_setup },
    .{ .name = "vr_map_limb", .func = vr_maplimb },
    .{ .name = "vr_metadata", .func = vr_getmeta },
    .{ .name = "inputanalog_filter", .func = inputfilteranalog },
    .{ .name = "inputanalog_query", .func = inputanalogquery },
    .{ .name = "inputanalog_toggle", .func = inputanalogtoggle },
    .{ .name = null, .func = null },
};

const vidsysfuns = [_]luaL_Reg{
    .{ .name = "switch_default_scalemode", .func = setscalemode },
    .{ .name = "switch_default_texmode", .func = settexmode },
    .{ .name = "switch_default_imageproc", .func = setimageproc },
    .{ .name = "switch_default_texfilter", .func = settexfilter },
    .{ .name = "switch_default_blendmode", .func = setblendmode },
    .{ .name = "set_context_attachment", .func = setdefattach },
    .{ .name = "resize_video_canvas", .func = videocanvasrsz },
    .{ .name = "video_displaymodes", .func = videodisplay },
    .{ .name = "video_displaydescr", .func = videodispdescr },
    .{ .name = "video_displaygamma", .func = videodispgamma },
    .{ .name = "map_video_display", .func = videomapping },
    .{ .name = "video_display_state", .func = videodpms },
    .{ .name = "video_3dorder", .func = v3dorder },
    .{ .name = "build_shader", .func = buildshader },
    .{ .name = "delete_shader", .func = deleteshader },
    .{ .name = "valid_vid", .func = validvid },
    .{ .name = "video_synchronization", .func = videosynch },
    .{ .name = "shader_uniform", .func = shader_uniform },
    .{ .name = "shader_ugroup", .func = shader_ugroup },
    .{ .name = "push_video_context", .func = pushcontext },
    .{ .name = "storepush_video_context", .func = pushcontext_ext },
    .{ .name = "storepop_video_context", .func = popcontext_ext },
    .{ .name = "pop_video_context", .func = popcontext },
    .{ .name = "current_context_usage", .func = contextusage },
    .{ .name = null, .func = null },
};

const netfuns = [_]luaL_Reg{
    .{ .name = "net_open", .func = net_open },
    .{ .name = "net_discover", .func = net_discover },
    .{ .name = "net_listen", .func = net_listen },
    .{ .name = null, .func = null },
};

// ============================================================================
// arcan_lua_pushglobalconsts (C:13192-13431)
//
// Pushes ~200 global integer constants and a handful of string/number
// constants into the Lua global table.
// ============================================================================
export fn arcan_lua_pushglobalconsts(ctx: ?*lua_State) void {
    const mode = c.platform_video_dimensions();

    const consttbl = [_]struct { key: [*c]const u8, val: f64 }{
        .{ .key = "EXIT_SUCCESS", .val = c.EXIT_SUCCESS },
        .{ .key = "EXIT_FAILURE", .val = c.EXIT_FAILURE },
        .{ .key = "EXIT_SILENT", .val = 256 },

        // VRESW/VRESH — legacy, should be replaced with physical dimension queries
        .{ .key = "VRESW", .val = @floatFromInt(mode.width) },
        .{ .key = "VRESH", .val = @floatFromInt(mode.height) },
        .{ .key = "MAX_SURFACEW", .val = @floatFromInt(MAX_SURFACEW) },
        .{ .key = "MAX_SURFACEH", .val = @floatFromInt(MAX_SURFACEH) },
        .{ .key = "MAX_TARGETW", .val = @floatFromInt(c.ARCAN_SHMPAGE_MAXW) },
        .{ .key = "MAX_TARGETH", .val = @floatFromInt(c.ARCAN_SHMPAGE_MAXH) },
        .{ .key = "STACK_MAXCOUNT", .val = @floatFromInt(c.CONTEXT_STACK_LIMIT) },
        .{ .key = "FRAMESET_SPLIT", .val = @floatFromInt(c.ARCAN_FRAMESET_SPLIT) },
        .{ .key = "FRAMESET_MULTITEXTURE", .val = @floatFromInt(c.ARCAN_FRAMESET_MULTITEXTURE) },
        .{ .key = "FRAMESET_NODETACH", .val = @floatFromInt(FRAMESET_NODETACH) },
        .{ .key = "FRAMESET_DETACH", .val = @floatFromInt(FRAMESET_DETACH) },
        .{ .key = "FRAMESERVER_INPUT", .val = 41 },
        .{ .key = "FRAMESERVER_OUTPUT", .val = 42 },
        .{ .key = "BLEND_NONE", .val = @floatFromInt(c.BLEND_NONE) },
        .{ .key = "BLEND_ADD", .val = @floatFromInt(c.BLEND_ADD) },
        .{ .key = "BLEND_SUB", .val = @floatFromInt(c.BLEND_SUB) },
        .{ .key = "BLEND_MULTIPLY", .val = @floatFromInt(c.BLEND_MULTIPLY) },
        .{ .key = "BLEND_NORMAL", .val = @floatFromInt(c.BLEND_NORMAL) },
        .{ .key = "BLEND_FORCE", .val = @floatFromInt(c.BLEND_FORCE) },
        .{ .key = "BLEND_PREMULTIPLIED", .val = @floatFromInt(c.BLEND_PREMUL) },
        .{ .key = "ANCHOR_UL", .val = @floatFromInt(c.ANCHORP_UL) },
        .{ .key = "ANCHOR_UR", .val = @floatFromInt(c.ANCHORP_UR) },
        .{ .key = "ANCHOR_LL", .val = @floatFromInt(c.ANCHORP_LL) },
        .{ .key = "ANCHOR_LR", .val = @floatFromInt(c.ANCHORP_LR) },
        .{ .key = "ANCHOR_C", .val = @floatFromInt(c.ANCHORP_C) },
        .{ .key = "ANCHOR_UC", .val = @floatFromInt(c.ANCHORP_UC) },
        .{ .key = "ANCHOR_LC", .val = @floatFromInt(c.ANCHORP_LC) },
        .{ .key = "ANCHOR_CL", .val = @floatFromInt(c.ANCHORP_CL) },
        .{ .key = "ANCHOR_CR", .val = @floatFromInt(c.ANCHORP_CR) },
        .{ .key = "ANCHOR_SCALE_NONE", .val = 0 },
        .{ .key = "ANCHOR_SCALE_W", .val = @floatFromInt(c.SCALEM_WIDTH) },
        .{ .key = "ANCHOR_SCALE_H", .val = @floatFromInt(c.SCALEM_HEIGHT) },
        .{ .key = "ANCHOR_SCALE_WH", .val = @floatFromInt(c.SCALEM_WIDTH_HEIGHT) },
        .{ .key = "FRAMESERVER_LOOP", .val = 0 },
        .{ .key = "FRAMESERVER_NOLOOP", .val = 1 },
        .{ .key = "TYPE_FRAMESERVER", .val = @floatFromInt(c.ARCAN_TAG_FRAMESERV) },
        .{ .key = "TYPE_3DOBJECT", .val = @floatFromInt(c.ARCAN_TAG_3DOBJ) },
        .{ .key = "TARGET_SYNCHRONOUS", .val = @floatFromInt(TARGET_FLAG_SYNCHRONOUS) },
        .{ .key = "TARGET_NOALPHA", .val = @floatFromInt(TARGET_FLAG_NO_ALPHA_UPLOAD) },
        .{ .key = "TARGET_VSTORE_SYNCH", .val = @floatFromInt(TARGET_FLAG_VSTORE_SYNCH) },
        .{ .key = "TARGET_VERBOSE", .val = @floatFromInt(TARGET_FLAG_VERBOSE) },
        .{ .key = "TARGET_AUTOCLOCK", .val = @floatFromInt(TARGET_FLAG_AUTOCLOCK) },
        .{ .key = "TARGET_NOBUFFERPASS", .val = @floatFromInt(TARGET_FLAG_NO_BUFFERPASS) },
        .{ .key = "TARGET_ALLOWCM", .val = @floatFromInt(TARGET_FLAG_ALLOW_CM) },
        .{ .key = "TARGET_ALLOWHDR", .val = @floatFromInt(TARGET_FLAG_ALLOW_HDR) },
        .{ .key = "TARGET_ALLOWLODEF", .val = 0 }, // deprecated
        .{ .key = "TARGET_ALLOWVECTOR", .val = 0 }, // deprecated
        .{ .key = "TARGET_ALLOWINPUT", .val = @floatFromInt(TARGET_FLAG_ALLOW_INPUT) },
        .{ .key = "TARGET_ALLOWGPU", .val = @floatFromInt(TARGET_FLAG_ALLOW_GPUAUTH) },
        .{ .key = "TARGET_LIMITSIZE", .val = @floatFromInt(TARGET_FLAG_LIMIT_SIZE) },
        .{ .key = "TARGET_SYNCHSIZE", .val = @floatFromInt(TARGET_FLAG_SYNCH_SIZE) },
        .{ .key = "TARGET_BLOCKADOPT", .val = @floatFromInt(TARGET_FLAG_NO_ADOPT) },
        .{ .key = "TARGET_DRAINQUEUE", .val = @floatFromInt(TARGET_FLAG_DRAIN_QUEUE) },
        .{ .key = "DISPLAY_STANDBY", .val = @floatFromInt(c.ADPMS_STANDBY) },
        .{ .key = "DISPLAY_OFF", .val = @floatFromInt(c.ADPMS_OFF) },
        .{ .key = "DISPLAY_SUSPEND", .val = @floatFromInt(c.ADPMS_SUSPEND) },
        .{ .key = "DISPLAY_ON", .val = @floatFromInt(c.ADPMS_ON) },
        .{ .key = "DEVICE_INDIRECT", .val = @floatFromInt(DEVICE_INDIRECT) },
        .{ .key = "DEVICE_DIRECT", .val = @floatFromInt(DEVICE_DIRECT) },
        .{ .key = "DEVICE_LOST", .val = @floatFromInt(DEVICE_LOST) },
        .{ .key = "ANCHORHINT_SEGMENT", .val = @floatFromInt(ANCHORHINT_SEGMENT) },
        .{ .key = "ANCHORHINT_EXTERNAL", .val = @floatFromInt(ANCHORHINT_EXTERNAL) },
        .{ .key = "ANCHORHINT_PROXY", .val = @floatFromInt(ANCHORHINT_PROXY) },
        .{ .key = "ANCHORHINT_PROXY_EXTERNAL", .val = @floatFromInt(ANCHORHINT_PROXY_EXTERNAL) },
        .{ .key = "RENDERTARGET_NOSCALE", .val = @floatFromInt(RENDERTARGET_NOSCALE) },
        .{ .key = "RENDERTARGET_SCALE", .val = @floatFromInt(RENDERTARGET_SCALE) },
        .{ .key = "RENDERTARGET_NODETACH", .val = @floatFromInt(RENDERTARGET_NODETACH) },
        .{ .key = "RENDERTARGET_DETACH", .val = @floatFromInt(RENDERTARGET_DETACH) },
        .{ .key = "RENDERTARGET_COLOR", .val = @floatFromInt(RENDERFMT_COLOR) },
        .{ .key = "RENDERTARGET_DEPTH", .val = @floatFromInt(RENDERFMT_DEPTH) },
        .{ .key = "RENDERTARGET_MULTISAMPLE", .val = @floatFromInt(RENDERFMT_MSAA) },
        .{ .key = "RENDERTARGET_ALPHA", .val = @floatFromInt(RENDERFMT_RETAIN_ALPHA) },
        .{ .key = "RENDERTARGET_FULL", .val = @floatFromInt(RENDERFMT_FULL) },
        .{ .key = "READBACK_MANUAL", .val = 0 },
        .{ .key = "SHADER_DOMAIN_RENDERTARGET", .val = 1 },
        .{ .key = "SHADER_DOMAIN_RENDERTARGET_HARD", .val = 2 },
        .{ .key = "ROTATE_RELATIVE", .val = 10 }, // CONST_ROTATE_RELATIVE
        .{ .key = "ROTATE_ABSOLUTE", .val = 5 }, // CONST_ROTATE_ABSOLUTE
        .{ .key = "SEEK_RELATIVE", .val = 1 },
        .{ .key = "SEEK_ABSOLUTE", .val = 0 },
        .{ .key = "SEEK_TIME", .val = 1 },
        .{ .key = "SEEK_SPACE", .val = 0 },
        .{ .key = "TEX_REPEAT", .val = @floatFromInt(c.ARCAN_VTEX_REPEAT) },
        .{ .key = "TEX_CLAMP", .val = @floatFromInt(c.ARCAN_VTEX_CLAMP) },
        .{ .key = "FILTER_NONE", .val = @floatFromInt(c.ARCAN_VFILTER_NONE) },
        .{ .key = "FILTER_LINEAR", .val = @floatFromInt(c.ARCAN_VFILTER_LINEAR) },
        .{ .key = "FILTER_BILINEAR", .val = @floatFromInt(c.ARCAN_VFILTER_BILINEAR) },
        .{ .key = "FILTER_TRILINEAR", .val = @floatFromInt(c.ARCAN_VFILTER_TRILINEAR) },
        .{ .key = "INTERP_LINEAR", .val = @floatFromInt(c.ARCAN_VINTER_LINEAR) },
        .{ .key = "INTERP_SINE", .val = @floatFromInt(c.ARCAN_VINTER_SINE) },
        .{ .key = "INTERP_EXPIN", .val = @floatFromInt(c.ARCAN_VINTER_EXPIN) },
        .{ .key = "INTERP_EXPOUT", .val = @floatFromInt(c.ARCAN_VINTER_EXPOUT) },
        .{ .key = "INTERP_EXPINOUT", .val = @floatFromInt(c.ARCAN_VINTER_EXPINOUT) },
        .{ .key = "INTERP_SMOOTHSTEP", .val = @floatFromInt(c.ARCAN_VINTER_SMOOTHSTEP) },
        .{ .key = "SCALE_NOPOW2", .val = @floatFromInt(c.ARCAN_VIMAGE_NOPOW2) },
        .{ .key = "SCALE_POW2", .val = @floatFromInt(c.ARCAN_VIMAGE_SCALEPOW2) },
        .{ .key = "IMAGEPROC_NORMAL", .val = @floatFromInt(c.IMAGEPROC_NORMAL) },
        .{ .key = "IMAGEPROC_FLIPH", .val = @floatFromInt(c.IMAGEPROC_FLIPH) },
        .{ .key = "WORLDID", .val = @floatFromInt(c.ARCAN_VIDEO_WORLDID) },
        .{ .key = "CLIP_ON", .val = @floatFromInt(c.ARCAN_CLIP_ON) },
        .{ .key = "CLIP_OFF", .val = @floatFromInt(c.ARCAN_CLIP_OFF) },
        .{ .key = "CLIP_SHALLOW", .val = @floatFromInt(c.ARCAN_CLIP_SHALLOW) },
        .{ .key = "BADID", .val = @floatFromInt(c.ARCAN_EID) },
        .{ .key = "CLOCKRATE", .val = @floatFromInt(c.ARCAN_TIMER_TICK) },
        .{ .key = "CLOCK", .val = 0 },
        .{ .key = "TRACE_TRIGGER_ONESHOT", .val = 0 },
        .{ .key = "TRACE_TRIGGER_ENTER", .val = 1 },
        .{ .key = "TRACE_TRIGGER_EXIT", .val = 2 },
        .{ .key = "TRACE_PATH_DEFAULT", .val = @floatFromInt(c.TRACE_SYS_DEFAULT) },
        .{ .key = "TRACE_PATH_SLOW", .val = @floatFromInt(c.TRACE_SYS_SLOW) },
        .{ .key = "TRACE_PATH_WARNING", .val = @floatFromInt(c.TRACE_SYS_WARN) },
        .{ .key = "TRACE_PATH_ERROR", .val = @floatFromInt(c.TRACE_SYS_ERROR) },
        .{ .key = "TRACE_PATH_FAST", .val = @floatFromInt(c.TRACE_SYS_FAST) },
        .{ .key = "ALLOC_QUALITY_LOW", .val = @floatFromInt(c.VSTORE_HINT_LODEF) },
        .{ .key = "ALLOC_QUALITY_NORMAL", .val = @floatFromInt(c.VSTORE_HINT_NORMAL) },
        .{ .key = "ALLOC_QUALITY_HIGH", .val = @floatFromInt(c.VSTORE_HINT_HIDEF) },
        .{ .key = "ALLOC_QUALITY_FLOAT16", .val = @floatFromInt(c.VSTORE_HINT_F16) },
        .{ .key = "ALLOC_QUALITY_FLOAT32", .val = @floatFromInt(c.VSTORE_HINT_F32) },
        .{ .key = "APPL_RESOURCE", .val = @floatFromInt(c.RESOURCE_APPL) },
        .{ .key = "APPL_STATE_RESOURCE", .val = @floatFromInt(c.RESOURCE_APPL_STATE) },
        .{ .key = "APPL_TEMP_RESOURCE", .val = @floatFromInt(c.RESOURCE_APPL_TEMP) },
        .{ .key = "SHARED_RESOURCE", .val = @floatFromInt(c.RESOURCE_APPL_SHARED) },
        .{ .key = "SYS_SCRIPT_RESOURCE", .val = @floatFromInt(c.RESOURCE_SYS_SCRIPTS) },
        .{ .key = "SYS_APPL_RESOURCE", .val = @floatFromInt(c.RESOURCE_SYS_APPLBASE) },
        .{ .key = "SYS_FONT_RESOURCE", .val = @floatFromInt(c.RESOURCE_SYS_FONT) },
        .{ .key = "ALL_RESOURCES", .val = @floatFromInt(c.DEFAULT_USERMASK) },
        .{ .key = "API_VERSION_MAJOR", .val = @floatFromInt(c.LUAAPI_VERSION_MAJOR) },
        .{ .key = "API_VERSION_MINOR", .val = @floatFromInt(c.LUAAPI_VERSION_MINOR) },
        .{ .key = "HISTOGRAM_SPLIT", .val = @floatFromInt(HIST_SPLIT) },
        .{ .key = "HISTOGRAM_MERGE", .val = @floatFromInt(HIST_MERGE) },
        .{ .key = "HISTOGRAM_MERGE_NOALPHA", .val = @floatFromInt(HIST_MERGE_NOALPHA) },
        .{ .key = "LAUNCH_EXTERNAL", .val = 0 },
        .{ .key = "LAUNCH_INTERNAL", .val = 1 },
        .{ .key = "HINT_NONE", .val = @floatFromInt(c.HINT_NONE) },
        .{ .key = "HINT_PRIMARY", .val = @floatFromInt(c.HINT_FL_PRIMARY) },
        .{ .key = "HINT_FIT", .val = @floatFromInt(c.HINT_FIT) },
        .{ .key = "HINT_CROP", .val = @floatFromInt(c.HINT_CROP) },
        .{ .key = "HINT_ROTATE_CW_90", .val = @floatFromInt(c.HINT_ROTATE_CW_90) },
        .{ .key = "HINT_ROTATE_CCW_90", .val = @floatFromInt(c.HINT_ROTATE_CCW_90) },
        .{ .key = "HINT_YFLIP", .val = @floatFromInt(c.HINT_YFLIP) },
        .{ .key = "HINT_ROTATE_180", .val = @floatFromInt(c.HINT_ROTATE_180) },
        .{ .key = "HINT_CURSOR", .val = @floatFromInt(c.HINT_CURSOR) },
        .{ .key = "HINT_DIRECT", .val = @floatFromInt(c.HINT_DIRECT) },
        .{ .key = "TD_HINT_CONTINUED", .val = 1 },
        .{ .key = "TD_HINT_INVISIBLE", .val = 2 },
        .{ .key = "TD_HINT_UNFOCUSED", .val = 4 },
        .{ .key = "TD_HINT_MAXIMIZED", .val = 8 },
        .{ .key = "TD_HINT_FULLSCREEN", .val = 16 },
        .{ .key = "TD_HINT_DETACHED", .val = 32 },
        .{ .key = "TD_HINT_IGNORE", .val = 128 },
        .{ .key = "MASK_LIVING", .val = @floatFromInt(c.MASK_LIVING) },
        .{ .key = "MASK_ORIENTATION", .val = @floatFromInt(c.MASK_ORIENTATION) },
        .{ .key = "MASK_OPACITY", .val = @floatFromInt(c.MASK_OPACITY) },
        .{ .key = "MASK_POSITION", .val = @floatFromInt(c.MASK_POSITION) },
        .{ .key = "MASK_SCALE", .val = @floatFromInt(c.MASK_SCALE) },
        .{ .key = "MASK_UNPICKABLE", .val = @floatFromInt(c.MASK_UNPICKABLE) },
        .{ .key = "MASK_FRAMESET", .val = @floatFromInt(c.MASK_FRAMESET) },
        .{ .key = "MASK_MAPPING", .val = @floatFromInt(c.MASK_MAPPING) },
        .{ .key = "FORMAT_PNG", .val = @floatFromInt(OUTFMT_PNG) },
        .{ .key = "FORMAT_PNG_FLIP", .val = @floatFromInt(OUTFMT_PNG_FLIP) },
        .{ .key = "FORMAT_RAW8", .val = @floatFromInt(OUTFMT_RAW8) },
        .{ .key = "FORMAT_RAW24", .val = @floatFromInt(OUTFMT_RAW24) },
        .{ .key = "FORMAT_RAW32", .val = @floatFromInt(OUTFMT_RAW32) },
        .{ .key = "ORDER_FIRST", .val = @floatFromInt(c.ORDER3D_FIRST) },
        .{ .key = "ORDER_NONE", .val = @floatFromInt(c.ORDER3D_NONE) },
        .{ .key = "ORDER_LAST", .val = @floatFromInt(c.ORDER3D_LAST) },
        .{ .key = "ORDER_SKIP", .val = @floatFromInt(c.ORDER3D_NONE) },
        .{ .key = "MOUSE_GRABON", .val = @floatFromInt(MOUSE_GRAB_ON) },
        .{ .key = "MOUSE_GRABOFF", .val = @floatFromInt(MOUSE_GRAB_OFF) },
        .{ .key = "MOUSE_BTNLEFT", .val = 1 },
        .{ .key = "MOUSE_BTNMIDDLE", .val = 2 },
        .{ .key = "MOUSE_BTNRIGHT", .val = 3 },
        // Note: SHADER_DOMAIN_RENDERTARGET and SHADER_DOMAIN_RENDERTARGET_HARD
        // appear twice in the C table — duplicates are harmless (last write wins).
        .{ .key = "SHADER_DOMAIN_RENDERTARGET", .val = 1 },
        .{ .key = "SHADER_DOMAIN_RENDERTARGET_HARD", .val = 2 },
        .{ .key = "LEDCONTROLLERS", .val = @floatFromInt(c.arcan_led_controllers()) },
        .{ .key = "KEY_CONFIG", .val = @floatFromInt(c.DVT_CONFIG) },
        .{ .key = "KEY_TARGET", .val = @floatFromInt(c.DVT_TARGET) },
        .{ .key = "NOW", .val = 0 },
        .{ .key = "NOPERSIST", .val = 0 },
        .{ .key = "PERSIST", .val = 1 },
        .{ .key = "DISCOVER_PASSIVE", .val = 1 }, // CONST_DISCOVER_PASSIVE
        .{ .key = "DISCOVER_SWEEP", .val = 2 }, // CONST_DISCOVER_SWEEP
        .{ .key = "DISCOVER_BROADCAST", .val = 3 }, // CONST_DISCOVER_BROADCAST
        .{ .key = "DISCOVER_DIRECTORY", .val = 4 }, // CONST_DISCOVER_DIRECTORY
        .{ .key = "DISCOVER_TEST", .val = 8 }, // CONST_DISCOVER_TEST
        .{ .key = "TRUST_KNOWN", .val = 11 }, // CONST_TRUST_KNOWN
        .{ .key = "TRUST_PERMIT_UNKNOWN", .val = 12 }, // CONST_TRUST_PERMIT_UNKNOWN
        .{ .key = "TRUST_TRANSITIVE", .val = 13 }, // CONST_TRUST_TRANSITIVE
        .{ .key = "TRANSLATION_CLEAR", .val = @floatFromInt(c.EVENT_TRANSLATION_CLEAR) },
        .{ .key = "TRANSLATION_SET", .val = @floatFromInt(c.EVENT_TRANSLATION_SET) },
        .{ .key = "TRANSLATION_REMAP", .val = @floatFromInt(c.EVENT_TRANSLATION_REMAP) },
        .{ .key = "DEBUGLEVEL", .val = @floatFromInt(lua_debug_level) },
    };

    for (&consttbl) |*entry| {
        c.arcan_lua_setglobalnum(ctx, entry.key, entry.val);
    }

    // Physical pixels-per-cm derived from display dimensions
    const hppcm: f64 = if (mode.width != 0 and mode.phy_width != 0)
        10.0 * (@as(f64, @floatFromInt(mode.width)) / @as(f64, @floatFromInt(mode.phy_width)))
    else
        38.4;
    const vppcm: f64 = if (mode.height != 0 and mode.phy_height != 0)
        10.0 * (@as(f64, @floatFromInt(mode.height)) / @as(f64, @floatFromInt(mode.phy_height)))
    else
        38.4;

    c.lua_pushnumber(ctx, hppcm);
    c.lua_setglobal(ctx, "HPPCM");

    c.lua_pushnumber(ctx, vppcm);
    c.lua_setglobal(ctx, "VPPCM");

    c.lua_pushnumber(ctx, c.MM_PER_PT);
    c.lua_setglobal(ctx, "FONT_PT_SZ");

    _ = c.arcan_video_rendertargetdensity(
        c.ARCAN_VIDEO_WORLDID,
        @floatCast(hppcm),
        @floatCast(vppcm),
        false,
        false,
    );
    c.arcan_lua_setglobalstr(ctx, "GL_VERSION", c.agp_ident());
    c.arcan_lua_setglobalstr(ctx, "SHADER_LANGUAGE", c.agp_shader_language());
    c.arcan_lua_setglobalstr(ctx, "FRAMESERVER_MODES", c.arcan_frameserver_atypes());
    c.arcan_lua_setglobalstr(ctx, "APPLID", c.arcan_appl_id());
    c.arcan_lua_setglobalstr(ctx, "API_ENGINE_BUILD", "mayhem-2026-03-09");

    c.arcan_process_title(c.arcan_appl_id());

    const crash_src = c.alt_trace_crash_source();
    if (crash_src != null) {
        c.arcan_lua_setglobalstr(ctx, "CRASH_SOURCE", crash_src);
        c.alt_trace_set_crash_source(null);
    }
}

// ══════════════════════════════════════════════════════════════════════
// /tmp/arcan_lua_part12b.zig
// ══════════════════════════════════════════════════════════════════════

// === Part 12b: State Snapshot/Grab, Dump Helpers, Lookup Tables ===
//
// Ported from arcan_lua.c lines 13440-14086.
// Functions: vobj_flags, lut_filtermode, lut_imageproc, lut_scale,
//   lut_framemode, lut_clipmode, lut_blendmode, fprintf_float,
//   lut_txmode, lut_kind, dump_props, qused, fsrvtos, fput_luasafe_str,
//   dump_vstate, dump_vobject, dump_rtgt, arcan_lua_statesnap,
//   arcan_lua_stategrab


// External symbols


// Static lookup functions

fn vobj_flags(src: [*c]c.arcan_vobject) [*c]const u8 {
    const S = struct {
        var fbuf: [44]u8 = std.mem.zeroes([44]u8);
    };
    S.fbuf[0] = 0;
    if ((src.*.flags & @as(c_uint, @bitCast(@as(c_int, c.FL_PRSIST)))) > 0) {
        _ = c.strcat(&S.fbuf, "persist ");
    }
    if (src.*.clip != @as(c_uint, @bitCast(@as(c_int, c.ARCAN_CLIP_OFF)))) {
        _ = c.strcat(&S.fbuf, "clip ");
    }
    if ((src.*.flags & @as(c_uint, @bitCast(@as(c_int, c.FL_NASYNC)))) > 0) {
        _ = c.strcat(&S.fbuf, "noasynch ");
    }
    if ((src.*.flags & @as(c_uint, @bitCast(@as(c_int, c.FL_TCYCLE)))) > 0) {
        _ = c.strcat(&S.fbuf, "cycletransform ");
    }
    if ((src.*.flags & @as(c_uint, @bitCast(@as(c_int, c.FL_ORDOFS)))) > 0) {
        _ = c.strcat(&S.fbuf, "order ");
    }
    return &S.fbuf;
}

fn lut_filtermode(mode_in: c_uint) [*c]const u8 {
    const mode = mode_in & ~@as(c_uint, @bitCast(@as(c_int, c.ARCAN_VFILTER_MIPMAP)));
    return switch (mode) {
        @as(c_uint, @bitCast(@as(c_int, c.ARCAN_VFILTER_NONE))) => "none",
        @as(c_uint, @bitCast(@as(c_int, c.ARCAN_VFILTER_LINEAR))) => "linear",
        @as(c_uint, @bitCast(@as(c_int, c.ARCAN_VFILTER_BILINEAR))) => "bilinear",
        @as(c_uint, @bitCast(@as(c_int, c.ARCAN_VFILTER_TRILINEAR))) => "trilinear",
        else => "[missing filter]",
    };
}

fn lut_imageproc(mode: c_uint) [*c]const u8 {
    return switch (mode) {
        @as(c_uint, @bitCast(@as(c_int, c.IMAGEPROC_NORMAL))) => "normal",
        @as(c_uint, @bitCast(@as(c_int, c.IMAGEPROC_FLIPH))) => "vflip",
        else => "[missing proc]",
    };
}

fn lut_scale(mode: c_uint) [*c]const u8 {
    return switch (mode) {
        @as(c_uint, @bitCast(@as(c_int, c.ARCAN_VIMAGE_NOPOW2))) => "nopow2",
        @as(c_uint, @bitCast(@as(c_int, c.ARCAN_VIMAGE_SCALEPOW2))) => "scalepow2",
        else => "[missing scale]",
    };
}

fn lut_framemode(mode: c_uint) [*c]const u8 {
    return switch (mode) {
        @as(c_uint, @bitCast(@as(c_int, c.ARCAN_FRAMESET_SPLIT))) => "split",
        @as(c_uint, @bitCast(@as(c_int, c.ARCAN_FRAMESET_MULTITEXTURE))) => "multitexture",
        else => "[missing framemode]",
    };
}

fn lut_clipmode(mode: c_uint) [*c]const u8 {
    return switch (mode) {
        @as(c_uint, @bitCast(@as(c_int, c.ARCAN_CLIP_OFF))) => "disabled",
        @as(c_uint, @bitCast(@as(c_int, c.ARCAN_CLIP_ON))) => "stencil deep",
        @as(c_uint, @bitCast(@as(c_int, c.ARCAN_CLIP_SHALLOW))) => "stencil shallow",
        else => "[missing clipmode]",
    };
}

fn lut_blendmode(func: c_uint) [*c]const u8 {
    return switch (func & ~@as(c_uint, @bitCast(@as(c_int, c.BLEND_FORCE)))) {
        @as(c_uint, @bitCast(@as(c_int, c.BLEND_NONE))) => "disabled",
        @as(c_uint, @bitCast(@as(c_int, c.BLEND_NORMAL))) => "normal",
        @as(c_uint, @bitCast(@as(c_int, c.BLEND_ADD))) => "additive",
        @as(c_uint, @bitCast(@as(c_int, c.BLEND_MULTIPLY))) => "multiply",
        @as(c_uint, @bitCast(@as(c_int, c.BLEND_SUB))) => "subtract",
        @as(c_uint, @bitCast(@as(c_int, c.BLEND_PREMUL))) => "premultiplied",
        else => "[missing blendmode]",
    };
}

/// Write a float to FILE*, avoiding locale-dependent radix issues.
/// Splits integer and fractional parts manually.
fn fprintf_float(dst: ?*c.FILE, pre: [*c]const u8, in_val: f32, post: [*c]const u8) void {
    if (std.math.isNan(in_val)) {
        _ = c.fprintf(dst, "%snan%s", pre, post);
    } else if (std.math.isInf(in_val)) {
        _ = c.fprintf(dst, "%sinf%s", pre, post);
    } else {
        var intp: f32 = undefined;
        const fractp = c.modff(in_val, &intp);
        const int_part: c_int = @intFromFloat(intp);
        const frac_i: c_int = @intFromFloat(fractp);
        const frac_abs: c_int = if (frac_i < 0) -frac_i else frac_i;
        _ = c.fprintf(dst, "%s%d.%d%s", pre, int_part, frac_abs, post);
    }
}

fn lut_txmode(txmode: c_int) [*c]const u8 {
    return switch (txmode) {
        c.ARCAN_VTEX_REPEAT => "repeat",
        c.ARCAN_VTEX_CLAMP => "clamp(edge)",
        else => "unknown(broken)",
    };
}

fn lut_kind(src: [*c]c.arcan_vobject) [*c]const u8 {
    return switch (src.*.feed.state.tag) {
        c.ARCAN_TAG_NONE => "none",
        c.ARCAN_TAG_IMAGE => if (src.*.vstore.*.txmapped != 0) "texture" else "single color",
        c.ARCAN_TAG_FRAMESERV => "frameserver",
        c.ARCAN_TAG_ASYNCIMGLD => "textured_loading",
        c.ARCAN_TAG_ASYNCIMGRD => "textured_ready",
        c.ARCAN_TAG_3DOBJ => "3dobject",
        c.ARCAN_TAG_3DCAMERA => "3dcamera",
        c.ARCAN_TAG_CUSTOMPROC => "custom",
        c.ARCAN_TAG_LWA => "lwa",
        c.ARCAN_TAG_VR => "vr",
        c.ARCAN_TAG_TEXT => "text",
        else => "invalid",
    };
}

/// Dump surface_properties to FILE* as Lua code.
fn dump_props(dst: ?*c.FILE, props: c.surface_properties) void {
    fprintf_float(dst, "props.position = {", props.position.unnamed_0.unnamed_0.x, ", ");
    fprintf_float(dst, "", props.position.unnamed_0.unnamed_0.y, ", ");
    fprintf_float(dst, "", props.position.unnamed_0.unnamed_0.z, "};\n");

    fprintf_float(dst, "props.scale = {", props.scale.unnamed_0.unnamed_0.x, ", ");
    fprintf_float(dst, "", props.scale.unnamed_0.unnamed_0.y, ", ");
    fprintf_float(dst, "", props.scale.unnamed_0.unnamed_0.z, "};\n");

    fprintf_float(dst, "props.rotation = {", props.rotation.roll, ", ");
    fprintf_float(dst, "", props.rotation.pitch, ", ");
    fprintf_float(dst, "", props.rotation.yaw, "};\n");

    fprintf_float(dst, "props.opacity = ", props.opa, ";\n");
}

/// Count used events in an event queue.
fn qused(dq: [*c]c.arcan_evctx) c_int {
    const front: c_int = @bitCast(dq.*.front.*);
    const back: c_int = @bitCast(dq.*.back.*);
    const sz: c_int = @bitCast(dq.*.eventbuf_sz);
    return if (front > back) (sz - front) + back else back - front;
}

/// Dump frameserver state for a vobject to FILE*.
fn dump_vstate(dst: ?*c.FILE, vobj: [*c]c.arcan_vobject) void {
    if (vobj.*.feed.state.ptr == null or vobj.*.feed.state.tag != c.ARCAN_TAG_FRAMESERV)
        return;

    const fsrv: *c.arcan_frameserver = @ptrCast(@alignCast(vobj.*.feed.state.ptr));

    _ = c.fprintf(dst,
        "vobj.fsrv = {" ++
        "\tlastpts = %lld," ++
        "\taudbuf_sz = %d," ++
        "\taudbuf_used = %d," ++
        "\tchild_alive = %d," ++
        "\tinevq_sz = %d," ++
        "\tinevq_used = %d," ++
        "\toutevq_sz = %d," ++
        "\toutevq_used = %d,",
        @as(c_longlong, @bitCast(fsrv.lastpts)),
        @as(c_int, @bitCast(@as(c_uint, @truncate(fsrv.sz_audb)))),
        @as(c_int, @truncate(fsrv.ofs_audb)),
        @as(c_int, @intFromBool(fsrv_helper_get_flag_alive(@ptrCast(fsrv)))),
        @as(c_int, @bitCast(fsrv.inqueue.eventbuf_sz)),
        qused(&fsrv.inqueue),
        @as(c_int, @bitCast(fsrv.outqueue.eventbuf_sz)),
        qused(&fsrv.outqueue),
    );

    _ = c.fprintf(dst, "\tsource = ");
    fput_luasafe_str(dst, if (fsrv.source != null) fsrv.source else "NULL");
    _ = c.fprintf(dst, ",\n\tkind = ");
    fput_luasafe_str(dst, fsrvtos(fsrv.segid));
    _ = c.fprintf(dst, "};\n");
}
