// Zig port of engine/alt/types.c
// Lua ↔ arcan VID/AID type conversions with randomized base offset.

// Types matching C definitions:
// arcan_vobj_id = long long (i64), arcan_aobj_id = int (c_int)
// lua_Number = double, ARCAN_VIDEO_WORLDID = -1, ARCAN_EID = 0
const ARCAN_VIDEO_WORLDID: i64 = -1;
const ARCAN_EID: i64 = 0;

// Externs — defined in engine C files compiled into the same exe
extern fn arcan_random(dst: [*c]u8, len: usize) void;
extern fn arcan_renderfun_vidoffset(ofs: i64) void;

// Set on alt_setup_context call
export var lua_vid_base: c_uint = 0;

export fn alt_types_rebase() void {
    var rv: u32 = undefined;
    arcan_random(@ptrCast(&rv), 4);
    lua_vid_base = 256 + (rv % 32768);
    arcan_renderfun_vidoffset(@intCast(lua_vid_base));
}

export fn luavid_tovid(innum: f64) i64 {
    const inval: i64 = @intFromFloat(innum);
    if (inval != ARCAN_EID and inval != ARCAN_VIDEO_WORLDID)
        return inval - @as(i64, lua_vid_base)
    else if (inval != ARCAN_VIDEO_WORLDID)
        return ARCAN_EID
    else
        return ARCAN_VIDEO_WORLDID;
}

export fn luaaid_toaid(innum: f64) c_int {
    return @intFromFloat(innum);
}

export fn vid_toluavid(innum: i64) f64 {
    var v = innum;
    if (v != ARCAN_EID and v != ARCAN_VIDEO_WORLDID)
        v += @as(i64, lua_vid_base);
    return @floatFromInt(v);
}
