// Zig port of tui_lua.c — TUI Lua bindings
// Assembled from translate-c chunks with @cImport alias layer.

const std = @import("std");

const c = @import("shmif_types");

// Type aliases
const lua_State = c.lua_State;
const lua_Number = c.lua_Number;
const lua_Integer = c.lua_Integer;
const mode_t = c.mode_t;
const off_t = c.off_t;
const pid_t = c.pid_t;
const arcan_tui_conn = c.arcan_tui_conn;
const arcan_ioevent = c.arcan_ioevent;
const shmif_pixel = c.shmif_pixel;
const shmif_asample = c.shmif_asample;
const struct_tui_context = c.struct_tui_context;
const struct_tui_lmeta = c.struct_tui_lmeta;
const struct_tui_cbcfg = c.struct_tui_cbcfg;
const struct_tui_screen_attr = c.struct_tui_screen_attr;
const struct_tui_cell = c.struct_tui_cell;
const struct_tui_constraints = c.struct_tui_constraints;
const struct_tui_labelent = c.struct_tui_labelent;
const struct_tui_list_entry = c.struct_tui_list_entry;
const struct_tui_readline_opts = c.struct_tui_readline_opts;
const struct_tui_bufferwnd_opts = c.struct_tui_bufferwnd_opts;
const struct_tui_subwnd_req = c.struct_tui_subwnd_req;
const struct_widget_meta = c.struct_widget_meta;
const struct_blobio_meta = c.struct_blobio_meta;
const struct_luaL_Reg = c.struct_luaL_Reg;
const struct_pollfd = c.struct_pollfd;
const struct_stat = c.struct_stat;
const struct_passwd = c.struct_passwd;
const struct_group = c.struct_group;
const struct_nonblock_io = c.struct_nonblock_io;
const struct_io_job = c.struct_io_job;

// TUI constants
const TUI_COL_PRIMARY = c.TUI_COL_PRIMARY;
const TUI_COL_SECONDARY = c.TUI_COL_SECONDARY;
const TUI_COL_BG = c.TUI_COL_BG;
const TUI_COL_TEXT = c.TUI_COL_TEXT;
const TUI_COL_CURSOR = c.TUI_COL_CURSOR;
const TUI_COL_ALTCURSOR = c.TUI_COL_ALTCURSOR;
const TUI_COL_HIGHLIGHT = c.TUI_COL_HIGHLIGHT;
const TUI_COL_LABEL = c.TUI_COL_LABEL;
const TUI_COL_WARNING = c.TUI_COL_WARNING;
const TUI_COL_ERROR = c.TUI_COL_ERROR;
const TUI_COL_ALERT = c.TUI_COL_ALERT;
const TUI_COL_REFERENCE = c.TUI_COL_REFERENCE;
const TUI_COL_INACTIVE = c.TUI_COL_INACTIVE;
const TUI_COL_UI = c.TUI_COL_UI;
const TUI_COL_TBASE = c.TUI_COL_TBASE;
const TUI_ATTR_BOLD = c.TUI_ATTR_BOLD;
const TUI_ATTR_ITALIC = c.TUI_ATTR_ITALIC;
const TUI_ATTR_INVERSE = c.TUI_ATTR_INVERSE;
const TUI_ATTR_UNDERLINE = c.TUI_ATTR_UNDERLINE;
const TUI_ATTR_UNDERLINE_ALT = c.TUI_ATTR_UNDERLINE_ALT;
const TUI_ATTR_PROTECT = c.TUI_ATTR_PROTECT;
const TUI_ATTR_BLINK = c.TUI_ATTR_BLINK;
const TUI_ATTR_STRIKETHROUGH = c.TUI_ATTR_STRIKETHROUGH;
const TUI_ATTR_SHAPE_BREAK = c.TUI_ATTR_SHAPE_BREAK;
const TUI_ATTR_BORDER_LEFT = c.TUI_ATTR_BORDER_LEFT;
const TUI_ATTR_BORDER_RIGHT = c.TUI_ATTR_BORDER_RIGHT;
const TUI_ATTR_BORDER_DOWN = c.TUI_ATTR_BORDER_DOWN;
const TUI_ATTR_BORDER_TOP = c.TUI_ATTR_BORDER_TOP;
const TUI_ATTR_COLOR_INDEXED = c.TUI_ATTR_COLOR_INDEXED;
const TUI_WND_HANDOVER = c.TUI_WND_HANDOVER;
const TUI_WND_TUI = c.TUI_WND_TUI;
const TUI_WND_POPUP = c.TUI_WND_POPUP;
const TUI_WND_DOCKICON = c.TUI_WND_DOCKICON;
const TUI_WND_ACCESSIBILITY = c.TUI_WND_ACCESSIBILITY;
const TUI_CLI_INVALID = c.TUI_CLI_INVALID;
const TUI_MOUSE = c.TUI_MOUSE;
const TUI_MOUSE_FULL = c.TUI_MOUSE_FULL;
const TUI_AUTO_WRAP = c.TUI_AUTO_WRAP;
const TUI_ALTERNATE = c.TUI_ALTERNATE;
const TUI_HIDE_CURSOR = c.TUI_HIDE_CURSOR;
const TUI_MESSAGE_GENERIC = c.TUI_MESSAGE_GENERIC;
const TUI_MESSAGE_ALERT = c.TUI_MESSAGE_ALERT;
const TUI_MESSAGE_FAILURE = c.TUI_MESSAGE_FAILURE;
const TUI_MESSAGE_NOTIFICATION = c.TUI_MESSAGE_NOTIFICATION;
const TUI_MESSAGE_LOCAL = c.TUI_MESSAGE_LOCAL;
const TUI_BGCOPY_KEEPIN = c.TUI_BGCOPY_KEEPIN;
const TUI_BGCOPY_KEEPOUT = c.TUI_BGCOPY_KEEPOUT;
const TUI_BGCOPY_PROGRESS = c.TUI_BGCOPY_PROGRESS;
const TWND_NORMAL = c.TWND_NORMAL;
const TWND_LISTWND = c.TWND_LISTWND;
const TWND_BUFWND = c.TWND_BUFWND;
const TWND_READLINE = c.TWND_READLINE;
const SEGMENT_LIMIT = c.SEGMENT_LIMIT;

// Lua function aliases
const lua_call = c.lua_call;
const lua_createtable = c.lua_createtable;
const lua_getfield = c.lua_getfield;
const lua_getmetatable = c.lua_getmetatable;
const lua_gettop = c.lua_gettop;
const lua_iscfunction = c.lua_iscfunction;
const lua_isnumber = c.lua_isnumber;
const lua_isstring = c.lua_isstring;
const luaL_checkinteger = c.luaL_checkinteger;
const luaL_checklstring = c.luaL_checklstring;
const luaL_checknumber = c.luaL_checknumber;
const luaL_checkudata = c.luaL_checkudata;
const luaL_error = c.luaL_error;
const luaL_newmetatable = c.luaL_newmetatable;
const luaL_optinteger = c.luaL_optinteger;
const luaL_optlstring = c.luaL_optlstring;
const luaL_optnumber = c.luaL_optnumber;
const luaL_ref = c.luaL_ref;
const luaL_unref = c.luaL_unref;
const lua_newuserdata = c.lua_newuserdata;
const lua_objlen = c.lua_objlen;
const lua_pcall = c.lua_pcall;
const lua_pushboolean = c.lua_pushboolean;
const lua_pushcclosure = c.lua_pushcclosure;
const lua_pushinteger = c.lua_pushinteger;
const lua_pushlstring = c.lua_pushlstring;
const lua_pushnil = c.lua_pushnil;
const lua_pushnumber = c.lua_pushnumber;
const lua_pushstring = c.lua_pushstring;
const lua_pushvalue = c.lua_pushvalue;
const lua_rawequal = c.lua_rawequal;
const lua_rawgeti = c.lua_rawgeti;
const lua_rawset = c.lua_rawset;
const lua_replace = c.lua_replace;
const lua_setfield = c.lua_setfield;
const lua_setmetatable = c.lua_setmetatable;
const lua_settable = c.lua_settable;
const lua_settop = c.lua_settop;
const lua_toboolean = c.lua_toboolean;
const lua_tointeger = c.lua_tointeger;
const lua_tolstring = c.lua_tolstring;
const lua_tonumber = c.lua_tonumber;
const lua_type = c.lua_type;
const lua_typename = c.lua_typename;

// arcan_tui function aliases
const arcan_tui_announce_cursor_io = c.arcan_tui_announce_cursor_io;
const arcan_tui_announce_io = c.arcan_tui_announce_io;
const arcan_tui_bgcopy = c.arcan_tui_bgcopy;
const arcan_tui_bufferwnd_release = c.arcan_tui_bufferwnd_release;
const arcan_tui_bufferwnd_seek = c.arcan_tui_bufferwnd_seek;
const arcan_tui_bufferwnd_setup = c.arcan_tui_bufferwnd_setup;
const arcan_tui_bufferwnd_status = c.arcan_tui_bufferwnd_status;
const arcan_tui_bufferwnd_tell = c.arcan_tui_bufferwnd_tell;
const arcan_tui_content_size = c.arcan_tui_content_size;
const arcan_tui_copy = c.arcan_tui_copy;
const arcan_tui_cursorpos = c.arcan_tui_cursorpos;
const arcan_tui_cursor_style = c.arcan_tui_cursor_style;
const arcan_tui_defattr = c.arcan_tui_defattr;
const arcan_tui_defcattr = c.arcan_tui_defcattr;
const arcan_tui_destroy = c.arcan_tui_destroy;
const arcan_tui_dimensions = c.arcan_tui_dimensions;
const arcan_tui_erase_region = c.arcan_tui_erase_region;
const arcan_tui_erase_screen = c.arcan_tui_erase_screen;
const arcan_tui_fdresolve = c.arcan_tui_fdresolve;
const arcan_tui_get_color = c.arcan_tui_get_color;
const arcan_tui_getxy = c.arcan_tui_getxy;
const arcan_tui_handover_pipe = c.arcan_tui_handover_pipe;
const arcan_tui_hasglyph = c.arcan_tui_hasglyph;
const arcan_tui_ident = c.arcan_tui_ident;
const arcan_tui_listwnd_dirty = c.arcan_tui_listwnd_dirty;
const arcan_tui_listwnd_release = c.arcan_tui_listwnd_release;
const arcan_tui_listwnd_setpos = c.arcan_tui_listwnd_setpos;
const arcan_tui_listwnd_setup = c.arcan_tui_listwnd_setup;
const arcan_tui_listwnd_status = c.arcan_tui_listwnd_status;
const arcan_tui_listwnd_tell = c.arcan_tui_listwnd_tell;
const arcan_tui_message = c.arcan_tui_message;
const arcan_tui_move_to = c.arcan_tui_move_to;
const arcan_tui_open_display = c.arcan_tui_open_display;
const arcan_tui_readline_autocomplete = c.arcan_tui_readline_autocomplete;
const arcan_tui_readline_autosuggest = c.arcan_tui_readline_autosuggest;
const arcan_tui_readline_finished = c.arcan_tui_readline_finished;
const arcan_tui_readline_format = c.arcan_tui_readline_format;
const arcan_tui_readline_history = c.arcan_tui_readline_history;
const arcan_tui_readline_prompt = c.arcan_tui_readline_prompt;
const arcan_tui_readline_region = c.arcan_tui_readline_region;
const arcan_tui_readline_release = c.arcan_tui_readline_release;
const arcan_tui_readline_set = c.arcan_tui_readline_set;
const arcan_tui_readline_setup = c.arcan_tui_readline_setup;
const arcan_tui_readline_suggest = c.arcan_tui_readline_suggest;
const arcan_tui_readline_suggest_fix = c.arcan_tui_readline_suggest_fix;
const arcan_tui_refresh = c.arcan_tui_refresh;
const arcan_tui_request_subwnd_ext = c.arcan_tui_request_subwnd_ext;
const arcan_tui_reset = c.arcan_tui_reset;
const arcan_tui_reset_labels = c.arcan_tui_reset_labels;
const arcan_tui_screencopy = c.arcan_tui_screencopy;
const arcan_tui_send_key = c.arcan_tui_send_key;
const arcan_tui_set_color = c.arcan_tui_set_color;
const arcan_tui_set_flags = c.arcan_tui_set_flags;
const arcan_tui_setup = c.arcan_tui_setup;
const arcan_tui_statesize = c.arcan_tui_statesize;
const arcan_tui_tpack = c.arcan_tui_tpack;
const arcan_tui_tunpack = c.arcan_tui_tunpack;
const arcan_tui_ucs4utf8 = c.arcan_tui_ucs4utf8;
const arcan_tui_update_handlers = c.arcan_tui_update_handlers;
const arcan_tui_utf8ucs4 = c.arcan_tui_utf8ucs4;
const arcan_tui_wndhint = c.arcan_tui_wndhint;
const arcan_tui_write_border = c.arcan_tui_write_border;
const arcan_tui_writeattr_at = c.arcan_tui_writeattr_at;
const arcan_tui_writeu8 = c.arcan_tui_writeu8;

// Other C function aliases
pub extern "c" fn arcan_random(dst: [*c]u8, sz: usize) void;
const abort = c.abort;
const chdir = c.chdir;
const close = c.close;
const fchdir = c.fchdir;
const fchmodat = c.fchmodat;
const fchownat = c.fchownat;
const fcntl = c.fcntl;
const ffs = c.ffs;
const free = c.free;
const fstatat = c.fstatat;
const getcwd = c.getcwd;
const getenv = c.getenv;
const getgrgid = c.getgrgid;
const getgrnam = c.getgrnam;
const getpwnam = c.getpwnam;
const getpwuid = c.getpwuid;
const malloc = c.malloc;
const memcpy = c.memcpy;
const memmove = c.memmove;
const mkdirat = c.mkdirat;
const mkfifo = c.mkfifo;
const mkstemp = c.mkstemp;
const open = c.open;
const openat = c.openat;
const pipe = c.pipe;
const poll = c.poll;
const read = c.read;
const readlinkat = c.readlinkat;
const renameat = c.renameat;
const strcasecmp = c.strcasecmp;
const strchr = c.strchr;
const strcmp = c.strcmp;
const strdup = c.strdup;
const strerror = c.strerror;
const strlen = c.strlen;
const unlinkat = c.unlinkat;
const write = c.write;
// stderr accessed via c.stderr
const O_RDONLY = c.O_RDONLY;
const O_WRONLY = c.O_WRONLY;
const O_RDWR = c.O_RDWR;
const O_CREAT = c.O_CREAT;
const O_TRUNC = c.O_TRUNC;
const O_APPEND = c.O_APPEND;
const O_NONBLOCK = c.O_NONBLOCK;
const O_CLOEXEC = c.O_CLOEXEC;
const O_DIRECTORY = c.O_DIRECTORY;
const AT_FDCWD = c.AT_FDCWD;
const AT_SYMLINK_NOFOLLOW = c.AT_SYMLINK_NOFOLLOW;
const POLLIN = c.POLLIN;
const POLLHUP = c.POLLHUP;
const POLLERR = c.POLLERR;
const S_IRUSR = c.S_IRUSR;
const S_IWUSR = c.S_IWUSR;
const S_IRWXU = c.S_IRWXU;
const S_IXUSR = c.S_IXUSR;
const S_IRGRP = c.S_IRGRP;
const EINTR = c.EINTR;
const EAGAIN = c.EAGAIN;
const __errno_location = c.__errno_location;

// Varargs C functions (can't alias from @cImport)
extern "c" fn fprintf(stream: ?*anyopaque, fmt: [*c]const u8, ...) c_int;
extern "c" fn printf(fmt: [*c]const u8, ...) c_int;
extern "c" fn snprintf(buf: [*c]u8, size: usize, fmt: [*c]const u8, ...) c_int;

// External functions from nbio.zig, tui_popen.zig, tui_lua_glob.zig
extern "c" fn alt_nbio_register(ctx: ?*lua_State, add: ?*const fn (c_int, mode_t, isize) callconv(.c) bool, remove_1: ?*const fn (c_int, mode_t, [*c]isize) callconv(.c) bool, err: ?*const fn (?*lua_State, c_int, isize, [*c]const u8) callconv(.c) void) void;
extern "c" fn alt_nbio_process_read(?*lua_State, [*c]struct_nonblock_io, bool) c_int;
extern "c" fn alt_nbio_open(?*lua_State) c_int;
extern "c" fn alt_nbio_nonblock_cloexec(fd: c_int, socket: bool) void;
extern "c" fn alt_nbio_socket(path: [*c]const u8, ns: c_int, out: [*c][*c]u8) c_int;
extern "c" fn alt_nbio_process_write(?*lua_State, [*c]struct_nonblock_io) c_int;
extern "c" fn alt_nbio_data_in(?*lua_State, isize) void;
extern "c" fn alt_nbio_data_out(?*lua_State, isize) void;
extern "c" fn alt_nbio_release() void;
extern "c" fn alt_nbio_import(L: ?*lua_State, fd: c_int, m: mode_t, dst: [*c][*c]struct_nonblock_io, unlink_fn: [*c][*c]u8) bool;
extern "c" fn alt_nbio_close(L: ?*lua_State, ibb: [*c][*c]struct_nonblock_io) c_int;
extern "c" fn tui_popen(L: ?*lua_State) c_int;
extern "c" fn tui_pid_status(L: ?*lua_State) c_int;
extern "c" fn tui_pid_signal(L: ?*lua_State) c_int;
extern "c" fn tui_popen_tbltoenv(L: ?*lua_State, ind: c_int) [*c][*c]u8;
extern "c" fn tui_popen_tbltoargv(L: ?*lua_State, ind: c_int) [*c][*c]u8;
extern "c" fn tui_pty_resize(L: ?*lua_State) c_int;
extern "c" fn tui_glob(L: ?*lua_State) c_int;
extern "c" fn luaL_checkbnumber(L: ?*lua_State, narg: c_int) lua_Number;

// Anonymous type helpers
// These avoid needing to name translate-c's union_unnamed_N / struct_unnamed_N
fn zeroUnnamed0() @TypeOf(@as(struct_tui_lmeta, undefined).unnamed_0) {
    return std.mem.zeroes(@TypeOf(@as(struct_tui_lmeta, undefined).unnamed_0));
}
fn zeroPending() [8]@TypeOf(@as(struct_tui_lmeta, undefined).pending[0]) {
    return std.mem.zeroes([8]@TypeOf(@as(struct_tui_lmeta, undefined).pending[0]));
}
fn zeroReadline() @TypeOf(@as(struct_widget_meta, undefined).unnamed_0.readline) {
    return std.mem.zeroes(@TypeOf(@as(struct_widget_meta, undefined).unnamed_0.readline));
}

// tui_screen_attr anonymous field type helpers
fn zeroAttrFc() @TypeOf(@as(struct_tui_screen_attr, undefined).unnamed_0) {
    return std.mem.zeroes(@TypeOf(@as(struct_tui_screen_attr, undefined).unnamed_0));
}
fn zeroAttrBc() @TypeOf(@as(struct_tui_screen_attr, undefined).unnamed_1) {
    return std.mem.zeroes(@TypeOf(@as(struct_tui_screen_attr, undefined).unnamed_1));
}
fn zeroAttrFlags() @TypeOf(@as(struct_tui_screen_attr, undefined).unnamed_2) {
    return std.mem.zeroes(@TypeOf(@as(struct_tui_screen_attr, undefined).unnamed_2));
}
// widget_meta anonymous union type helper
fn zeroWidgetUnion() @TypeOf(@as(struct_widget_meta, undefined).unnamed_0) {
    return std.mem.zeroes(@TypeOf(@as(struct_widget_meta, undefined).unnamed_0));
}

// End of header, function implementations follow

pub export fn ltui_inherit(L: ?*lua_State, conn: [*c]arcan_tui_conn, T: [*c]struct_tui_lmeta) ?*struct_tui_context {
    register_tuimeta(L);
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(lua_newuserdata(L, @sizeOf(struct_tui_lmeta))));
    if (meta == null) {
        return null;
    }
    init_lmeta(L, meta, T);
    meta.*.tui_state = tui_lref(L, -1, "ltui_inherit", "1579", 7);
    synch_wd(meta);
    meta.*.cwd_fd = open(".", 0 | 16384);
    shared_cbcfg = struct_tui_cbcfg{
        .tag = @ptrCast(meta),
        .query_label = @ptrCast(@constCast(&query_label)),
        .input_label = @ptrCast(@constCast(&on_label)),
        .input_alabel = null,
        .input_mouse_motion = @ptrCast(@constCast(&on_mouse)),
        .input_mouse_button = @ptrCast(@constCast(&on_mouse_button)),
        .input_utf8 = @ptrCast(@constCast(&on_u8)),
        .input_key = @ptrCast(@constCast(&on_key)),
        .input_misc = @ptrCast(@constCast(&on_misc)),
        .state = @ptrCast(@constCast(&on_state)),
        .bchunk = @ptrCast(@constCast(&on_bchunk)),
        .vpaste = @ptrCast(@constCast(&on_vpaste)),
        .apaste = @ptrCast(@constCast(&on_apaste)),
        .tick = @ptrCast(@constCast(&on_tick)),
        .utf8 = @ptrCast(@constCast(&on_utf8_paste)),
        .resized = @ptrCast(@constCast(&on_resized)),
        .reset = @ptrCast(@constCast(&on_reset)),
        .geohint = @ptrCast(@constCast(&on_geohint)),
        .recolor = @ptrCast(@constCast(&on_recolor)),
        .subwindow = @ptrCast(@constCast(&on_subwindow)),
        .substitute = null,
        .resize = @ptrCast(@constCast(&on_resize)),
        .visibility = @ptrCast(@constCast(&on_visibility)),
        .exec_state = @ptrCast(@constCast(&on_exec_state)),
        .cli_command = @ptrCast(@constCast(&on_cli_command)),
        .seek_absolute = @ptrCast(@constCast(&on_seek_absolute)),
        .seek_relative = @ptrCast(@constCast(&on_seek_relative)),
        .message = @ptrCast(@constCast(&on_message)),
    };
    meta.*.href = @as(isize, @bitCast(@as(isize, -@as(c_int, 2))));
    if (lua_type(L, 3) == 5) {
        lua_getfield(L, 3, "handlers");
        if (lua_type(L, -1) == 5) {
            meta.*.href = tui_lref(L, -1, "ltui_inherit", "1624", 5);
            lua_settop(L, -1 - 1);
        } else {
            lua_settop(L, -1 - 1);
            return null;
        }
    }
    meta.*.unnamed_0.tui = arcan_tui_setup(conn, if (T != null) T.*.unnamed_0.tui else null, &shared_cbcfg, @sizeOf(struct_tui_cbcfg));
    if (meta.*.unnamed_0.tui == null) {
        lua_settop(L, -1 - 1);
        return null;
    }
    return meta.*.unnamed_0.tui;
}
pub export fn luaopen_arcantui(L: ?*lua_State) c_int {
    const luaarcantui: [4]struct_luaL_Reg = [4]struct_luaL_Reg{
        struct_luaL_Reg{
            .name = "APIVersion",
            .func = &apiversion,
        },
        struct_luaL_Reg{
            .name = "APIVersionString",
            .func = &apiversionstr,
        },
        struct_luaL_Reg{
            .name = "open",
            .func = &tui_open,
        },
        struct_luaL_Reg{
            .name = "create_local",
            .func = &tui_local,
        },
    };
    lua_createtable(L, 0, 0);
    {
        var i: usize = 0;
        while (i < (@sizeOf([4]struct_luaL_Reg) / @sizeOf(struct_luaL_Reg))) : (i +%= 1) {
            lua_pushstring(L, luaarcantui[i].name);
            lua_pushcclosure(L, luaarcantui[i].func, 0);
            lua_settable(L, -3);
        }
    }
    lua_pushlstring(L, "_COPYRIGHT", 10);
    lua_pushlstring(L, "Copyright (C) Bjorn Stahl", 25);
    lua_settable(L, -3);
    lua_pushlstring(L, "_DESCRIPTION", 12);
    lua_pushlstring(L, "TUI API for Arcan", 17);
    lua_settable(L, -3);
    lua_pushlstring(L, "_VERSION", 8);
    lua_pushlstring(L, "arcantuiapi 1.0.0", 17);
    lua_settable(L, -3);
    register_tuimeta(L);
    return 1;
}
// (struct/extern declarations removed — provided by header aliases)
const struct_unnamed_112 = extern struct {
    fdin: [32]c_int = std.mem.zeroes([32]c_int),
    fdin_tags: [32]isize = std.mem.zeroes([32]isize),
    fdin_used: usize = std.mem.zeroes(usize),
    fdout: [32]struct_pollfd = std.mem.zeroes([32]struct_pollfd),
    fdout_tags: [32]isize = std.mem.zeroes([32]isize),
    fdout_used: usize = std.mem.zeroes(usize),
};
pub var nbio_jobs: struct_unnamed_112 = std.mem.zeroes(struct_unnamed_112);
pub fn nbio_queue_bitmap(set: [*c]usize, map_arg: c_int) callconv(.c) usize {
    var map = map_arg;
    var count: usize = 0;
    while ((ffs(map) != 0) and (count < 32)) {
        const pos: c_int = ffs(map) - 1;
        map &= ~(@as(c_int, 1) << @intCast(pos));
        set[blk: {
            const ref = &count;
            const tmp = ref.*;
            ref.* +%= 1;
            break :blk tmp;
        }] = @as(usize, @bitCast(nbio_jobs.fdin_tags[@as(c_uint, @intCast(pos))]));
    }
    return count;
}
pub fn nbio_dequeue(fd: c_int, mode: mode_t, tag: [*c]isize) callconv(.c) bool {
    var found: bool = false;
    {
        var i: usize = 0;
        while ((mode == @as(mode_t, @bitCast(@as(c_int, 0)))) and (i < nbio_jobs.fdin_used)) : (i +%= 1) {
            if (nbio_jobs.fdin[i] == fd) {
                _ = memmove(@ptrCast(&nbio_jobs.fdin_tags[i]), @as(?*const anyopaque, @ptrCast(&nbio_jobs.fdin_tags[i +% 1])), (nbio_jobs.fdin_used -% i) *% @sizeOf(isize));
                _ = memmove(@ptrCast(&nbio_jobs.fdin[i]), @as(?*const anyopaque, @ptrCast(&nbio_jobs.fdin[i +% 1])), (nbio_jobs.fdin_used -% i) *% @sizeOf(c_int));
                nbio_jobs.fdin_used -%= 1;
                found = true;
                break;
            }
        }
    }
    {
        var i: usize = 0;
        while (i < nbio_jobs.fdout_used) : (i +%= 1) {
            if (nbio_jobs.fdout[i].fd == fd) {
                if (tag != null) {
                    tag.* = nbio_jobs.fdout_tags[i];
                }
                nbio_jobs.fdout_used -%= 1;
                _ = memmove(@ptrCast(&nbio_jobs.fdout_tags[i]), @as(?*const anyopaque, @ptrCast(&nbio_jobs.fdout_tags[i +% 1])), (nbio_jobs.fdout_used -% i) *% @sizeOf(isize));
                _ = memmove(@ptrCast(&nbio_jobs.fdout[i]), @as(?*const anyopaque, @ptrCast(&nbio_jobs.fdout[i +% 1])), (nbio_jobs.fdout_used -% i) *% @sizeOf(struct_pollfd));
                found = true;
                break;
            }
        }
    }
    return found;
}
pub fn nbio_queue(fd: c_int, mode: mode_t, tag: isize) callconv(.c) bool {
    if (fd == -1) return false;
    if (mode == @as(mode_t, @bitCast(@as(c_int, 0)))) {
        if (nbio_jobs.fdin_used >= 32) return false;
        nbio_jobs.fdin[nbio_jobs.fdin_used] = fd;
        nbio_jobs.fdin_tags[nbio_jobs.fdin_used] = tag;
        nbio_jobs.fdin_used +%= 1;
    }
    if (mode == @as(mode_t, @bitCast(@as(c_int, 1)))) {
        if (nbio_jobs.fdout_used >= 32) return false;
        nbio_jobs.fdout[nbio_jobs.fdout_used].fd = fd;
        nbio_jobs.fdout[nbio_jobs.fdout_used].events = @as(c_short, @bitCast(@as(c_short, @truncate((4 | 8) | 16))));
        nbio_jobs.fdout_tags[nbio_jobs.fdout_used] = tag;
        nbio_jobs.fdout_used +%= 1;
    }
    if ((mode != @as(mode_t, @bitCast(@as(c_int, 0)))) and (mode != @as(mode_t, @bitCast(@as(c_int, 1))))) {
        abort();
    }
    return true;
}
pub fn nbio_run_outbound(L: ?*lua_State) callconv(.c) void {
    var set: [32]isize = undefined;
    var count: c_int = 0;
    var pv: c_int = undefined;
    if (nbio_jobs.fdout_used == 0) return;
    if ((blk: {
        const tmp = poll(@ptrCast(@alignCast(&nbio_jobs.fdout[0])), nbio_jobs.fdout_used, 0);
        pv = tmp;
        break :blk tmp;
    }) > 0) {
        {
            var i: usize = 0;
            while ((i < nbio_jobs.fdout_used) and (pv != 0)) : (i +%= 1) {
                if (nbio_jobs.fdout[i].revents != 0) {
                    set[@as(c_uint, @intCast(blk: {
                        const ref = &count;
                        const tmp = ref.*;
                        ref.* += 1;
                        break :blk tmp;
                    }))] = nbio_jobs.fdout_tags[i];
                    pv -= 1;
                }
            }
        }
    }
    {
        var i: c_int = 0;
        while (i < count) : (i += 1) {
            alt_nbio_data_out(L, set[@as(c_uint, @intCast(i))]);
        }
    }
}
pub const req_cookie: u32 = @as(u32, @bitCast(@as(c_int, 65261)));
pub var shared_cbcfg: struct_tui_cbcfg = struct_tui_cbcfg{
    .tag = null,
    .query_label = null,
    .input_label = null,
    .input_alabel = null,
    .input_mouse_motion = null,
    .input_mouse_button = null,
    .input_utf8 = null,
    .input_key = null,
    .input_misc = null,
    .state = null,
    .bchunk = null,
    .vpaste = null,
    .apaste = null,
    .tick = null,
    .utf8 = null,
    .resized = null,
    .reset = null,
    .geohint = null,
    .recolor = null,
    .subwindow = null,
    .substitute = null,
    .resize = null,
    .visibility = null,
    .exec_state = null,
    .cli_command = null,
    .seek_absolute = null,
    .seek_relative = null,
    .message = null,
};
pub var udata_list: [6][*c]const u8 = [6][*c]const u8{
    "Arcan TUI",
    "widget_readline",
    "widget_listview",
    "widget_bufferview",
    "nonblockIO",
    "nonblockIOs",
};
pub fn match_udata(L: ?*lua_State, pos: isize) callconv(.c) [*c]const u8 {
    if (0 == lua_getmetatable(L, @as(c_int, @truncate(pos)))) return null;
    {
        var i: usize = 0;
        while (i < 6) : (i +%= 1) {
            _ = lua_getfield(L, -1001000, udata_list[i]);
            if (lua_rawequal(L, -1, -2) != 0) {
                lua_settop(L, -2 - 1);
                return udata_list[i];
            }
            lua_settop(L, -1 - 1);
        }
    }
    lua_settop(L, -1 - 1);
    return null;
}
pub fn dump_ltop(ctx: ?*lua_State, i_arg: c_int) callconv(.c) void {
    var i = i_arg;
    const t: c_int = lua_type(ctx, i);
    if (i < 0) {
        i = (lua_gettop(ctx) - i) + 1;
    }
    while (true) {
        switch (t) {
            1 => {
                _ = fprintf(c.stderr, "%d\t%s\n", i, if (lua_toboolean(ctx, i) != 0) @as([*c]const u8, "true") else @as([*c]const u8, "false"));
                break;
            },
            4 => {
                _ = fprintf(c.stderr, "%d\t'%s'\n", i, lua_tolstring(ctx, i, null));
                break;
            },
            3 => {
                _ = fprintf(c.stderr, "%d\t%g\n", i, lua_tonumber(ctx, i));
                break;
            },
            7 => {
                {
                    const @"type": [*c]const u8 = match_udata(ctx, @as(isize, @bitCast(@as(isize, i))));
                    if (@"type" != null) {
                        _ = fprintf(c.stderr, "%d\tuserdata:%s\n", i, @"type");
                    } else {
                        _ = fprintf(c.stderr, "%d\tuserdata(unknown)\n", i);
                    }
                }
                break;
            },
            else => {
                _ = fprintf(c.stderr, "%d\t%s\n", i, lua_typename(ctx, t));
                break;
            },
        }
        break;
    }
}
pub fn dump_stack(ctx: ?*lua_State) callconv(.c) void {
    const top: c_int = lua_gettop(ctx);
    _ = fprintf(c.stderr, "-- stack dump (%d)--\n", top);
    {
        var i: usize = 1;
        while (i <= @as(usize, @bitCast(@as(isize, top)))) : (i +%= 1) {
            dump_ltop(ctx, @as(c_int, @bitCast(@as(c_uint, @truncate(i)))));
        }
    }
    _ = fprintf(c.stderr, "\n");
}
pub fn dump_traceback(L: ?*lua_State) callconv(.c) void {
    dump_stack(L);
    // Lua 5.4: globals live in registry at LUA_RIDX_GLOBALS=2.
    // LuaJIT's LUA_GLOBALSINDEX (-10002) was a pseudo-index; invalid in 5.4.
    _ = lua_rawgeti(L, -1001000, 2);
    _ = lua_getfield(L, -1, "debug");
    lua_replace(L, -2);
    _ = lua_getfield(L, -1, "traceback");
    lua_call(L, 0, 1);
    const trace: [*c]const u8 = lua_tolstring(L, -1, null);
    _ = printf("%s\n", trace);
    lua_settop(L, -2 - 1);
    dump_stack(L);
}
pub fn dump_state(T: [*c]struct_tui_lmeta) callconv(.c) void {
    _ = fprintf(c.stderr, "tui_state:\n\thtable:%d\n\twidget:%d\n\t\tstate:%d\n\t\tclosure:%d\n", @as(c_int, @truncate(T.*.href)), T.*.widget_mode, @as(c_int, @truncate(if (T.*.widget_state == @as(isize, @bitCast(@as(isize, -@as(c_int, 2))))) @as(isize, @bitCast(@as(isize, -@as(c_int, 1)))) else T.*.widget_state)), @as(c_int, @truncate(if (T.*.widget_closure == @as(isize, @bitCast(@as(isize, -@as(c_int, 2))))) @as(isize, @bitCast(@as(isize, -@as(c_int, 1)))) else T.*.widget_closure)));
    if (T.*.widget_mode != c.TWND_NORMAL) {
        _ = blk: {
            _ = fprintf(c.stderr, "widget-resolve:\n");
            break :blk fprintf(c.stderr, "state->");
        };
        lua_rawgeti(T.*.lua, -1001000, @as(c_int, @truncate(T.*.widget_state)));
        dump_ltop(T.*.lua, -1);
        lua_settop(T.*.lua, -1 - 1);
        _ = fprintf(c.stderr, "closure->");
        lua_rawgeti(T.*.lua, -1001000, @as(c_int, @truncate(T.*.widget_closure)));
        dump_ltop(T.*.lua, -1);
        lua_settop(T.*.lua, -1 - 1);
    }
    dump_stack(T.*.lua);
}
pub fn register_tuimeta(L: ?*lua_State) callconv(.c) void {
    const tui_methods: [62]struct_luaL_Reg = [62]struct_luaL_Reg{
        struct_luaL_Reg{
            .name = "alive",
            .func = &alive,
        },
        struct_luaL_Reg{
            .name = "debugtrigger",
            .func = &debug,
        },
        struct_luaL_Reg{
            .name = "process",
            .func = &process,
        },
        struct_luaL_Reg{
            .name = "refresh",
            .func = &refresh,
        },
        struct_luaL_Reg{
            .name = "write",
            .func = &writeu8,
        },
        struct_luaL_Reg{
            .name = "write_to",
            .func = &write_tou8,
        },
        struct_luaL_Reg{
            .name = "write_border",
            .func = &write_border,
        },
        struct_luaL_Reg{
            .name = "get",
            .func = &getxy,
        },
        struct_luaL_Reg{
            .name = "set_handlers",
            .func = &settbl,
        },
        struct_luaL_Reg{
            .name = "update_identity",
            .func = &setident,
        },
        struct_luaL_Reg{
            .name = "set_default",
            .func = &defattr,
        },
        struct_luaL_Reg{
            .name = "reset",
            .func = &reset,
        },
        struct_luaL_Reg{
            .name = "reset_labels",
            .func = &resetlabels,
        },
        struct_luaL_Reg{
            .name = "to_clipboard",
            .func = &setcopy,
        },
        struct_luaL_Reg{
            .name = "cursor_pos",
            .func = &getcursor,
        },
        struct_luaL_Reg{
            .name = "new_window",
            .func = &reqwnd,
        },
        struct_luaL_Reg{
            .name = "erase",
            .func = &erase_screen,
        },
        struct_luaL_Reg{
            .name = "erase_region",
            .func = &erase_region,
        },
        struct_luaL_Reg{
            .name = "cursor_to",
            .func = &cursor_to,
        },
        struct_luaL_Reg{
            .name = "dimensions",
            .func = &screen_dimensions,
        },
        struct_luaL_Reg{
            .name = "close",
            .func = &tuiclose,
        },
        struct_luaL_Reg{
            .name = "get_color",
            .func = &color_get,
        },
        struct_luaL_Reg{
            .name = "set_color",
            .func = &color_set,
        },
        struct_luaL_Reg{
            .name = "set_flags",
            .func = &set_flags,
        },
        struct_luaL_Reg{
            .name = "announce_io",
            .func = &announce_io,
        },
        struct_luaL_Reg{
            .name = "request_io",
            .func = &request_io,
        },
        struct_luaL_Reg{
            .name = "announce_cursor_io",
            .func = &announce_cursor_io,
        },
        struct_luaL_Reg{
            .name = "alert",
            .func = &alert,
        },
        struct_luaL_Reg{
            .name = "message",
            .func = &message,
        },
        struct_luaL_Reg{
            .name = "notification",
            .func = &notification,
        },
        struct_luaL_Reg{
            .name = "failure",
            .func = &failure,
        },
        struct_luaL_Reg{
            .name = "state_size",
            .func = &statesize,
        },
        struct_luaL_Reg{
            .name = "content_size",
            .func = &contentsize,
        },
        struct_luaL_Reg{
            .name = "send_key",
            .func = &sendkey,
        },
        struct_luaL_Reg{
            .name = "revert",
            .func = &revertwnd,
        },
        struct_luaL_Reg{
            .name = "listview",
            .func = &listwnd,
        },
        struct_luaL_Reg{
            .name = "bufferview",
            .func = &bufferwnd,
        },
        struct_luaL_Reg{
            .name = "readline",
            .func = &readline,
        },
        struct_luaL_Reg{
            .name = "utf8_step",
            .func = &utf8step,
        },
        struct_luaL_Reg{
            .name = "utf8_len",
            .func = &utf8length,
        },
        struct_luaL_Reg{
            .name = "popen",
            .func = &popen_wrap,
        },
        struct_luaL_Reg{
            .name = "pwait",
            .func = &tui_pid_status,
        },
        struct_luaL_Reg{
            .name = "psignal",
            .func = &tui_pid_signal,
        },
        struct_luaL_Reg{
            .name = "phandover",
            .func = &tui_phandover,
        },
        struct_luaL_Reg{
            .name = "fopen",
            .func = &tui_fopen,
        },
        struct_luaL_Reg{
            .name = "funlink",
            .func = &tui_funlink,
        },
        struct_luaL_Reg{
            .name = "frename",
            .func = &tui_frename,
        },
        struct_luaL_Reg{
            .name = "fstatus",
            .func = &tui_fstatus,
        },
        struct_luaL_Reg{
            .name = "fmkdir",
            .func = &tui_fmkdir,
        },
        struct_luaL_Reg{
            .name = "tempfile",
            .func = &tui_mktemp,
        },
        struct_luaL_Reg{
            .name = "tempdir",
            .func = &tui_mkdtemp,
        },
        struct_luaL_Reg{
            .name = "fchmod",
            .func = &tui_fchmod,
        },
        struct_luaL_Reg{
            .name = "fchown",
            .func = &tui_fchown,
        },
        struct_luaL_Reg{
            .name = "fglob",
            .func = &tui_glob,
        },
        struct_luaL_Reg{
            .name = "bgcopy",
            .func = &tui_fbond,
        },
        struct_luaL_Reg{
            .name = "getenv",
            .func = &tui_getenv,
        },
        struct_luaL_Reg{
            .name = "chdir",
            .func = &tui_chdir,
        },
        struct_luaL_Reg{
            .name = "hint",
            .func = &tui_wndhint,
        },
        struct_luaL_Reg{
            .name = "has_glyph",
            .func = &tui_hasglyph,
        },
        struct_luaL_Reg{
            .name = "tpack",
            .func = &tui_tpack,
        },
        struct_luaL_Reg{
            .name = "tunpack",
            .func = &tui_tunpack,
        },
        struct_luaL_Reg{
            .name = "copy_region",
            .func = &tui_screencopy,
        },
    };
    if (luaL_newmetatable(L, "Arcan TUI") != 0) {
        {
            var i: usize = 0;
            while (i < (@sizeOf([62]struct_luaL_Reg) / @sizeOf(struct_luaL_Reg))) : (i +%= 1) {
                lua_pushcclosure(L, tui_methods[i].func, 0);
                lua_setfield(L, -2, tui_methods[i].name);
            }
        }
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__newindex");
        lua_pushcclosure(L, &collect, 0);
        lua_setfield(L, -2, "__gc");
        lua_pushcclosure(L, &tui_tostring, 0);
        lua_setfield(L, -2, "__tostring");
        alt_nbio_register(L, &nbio_queue, &nbio_dequeue, &nbio_error);
    }
    lua_settop(L, -1 - 1);
    const struct_unnamed_113 = extern struct {
        key: [*c]const u8 = std.mem.zeroes([*c]const u8),
        val: c_int = std.mem.zeroes(c_int),
    };
    const flagtbl: [4]struct_unnamed_113 = [4]struct_unnamed_113{
        struct_unnamed_113{
            .key = "auto_wrap",
            .val = TUI_AUTO_WRAP,
        },
        struct_unnamed_113{
            .key = "hide_cursor",
            .val = TUI_HIDE_CURSOR,
        },
        struct_unnamed_113{
            .key = "mouse",
            .val = TUI_MOUSE,
        },
        struct_unnamed_113{
            .key = "mouse_full",
            .val = TUI_MOUSE_FULL,
        },
    };
    lua_pushlstring(L, "flags", 5);
    lua_createtable(L, 0, 0);
    {
        var i: usize = 0;
        while (i < 4) : (i +%= 1) {
            lua_pushstring(L, flagtbl[i].key);
            lua_pushnumber(L, @as(lua_Number, @floatFromInt(flagtbl[i].val)));
            lua_rawset(L, -3);
        }
    }
    lua_settable(L, -3);
    lua_pushlstring(L, "attr", 4);
    lua_pushcclosure(L, &tui_attr, 0);
    lua_settable(L, -3);
    const struct_unnamed_114 = extern struct {
        key: [*c]const u8 = std.mem.zeroes([*c]const u8),
        val: c_int = std.mem.zeroes(c_int),
    };
    const coltbl: [30]struct_unnamed_114 = [30]struct_unnamed_114{
        struct_unnamed_114{
            .key = "primary",
            .val = TUI_COL_PRIMARY,
        },
        struct_unnamed_114{
            .key = "secondary",
            .val = TUI_COL_SECONDARY,
        },
        struct_unnamed_114{
            .key = "background",
            .val = TUI_COL_BG,
        },
        struct_unnamed_114{
            .key = "text",
            .val = TUI_COL_TEXT,
        },
        struct_unnamed_114{
            .key = "cursor",
            .val = TUI_COL_CURSOR,
        },
        struct_unnamed_114{
            .key = "altcursor",
            .val = TUI_COL_ALTCURSOR,
        },
        struct_unnamed_114{
            .key = "highlight",
            .val = TUI_COL_HIGHLIGHT,
        },
        struct_unnamed_114{
            .key = "label",
            .val = TUI_COL_LABEL,
        },
        struct_unnamed_114{
            .key = "warning",
            .val = TUI_COL_WARNING,
        },
        struct_unnamed_114{
            .key = "error",
            .val = TUI_COL_ERROR,
        },
        struct_unnamed_114{
            .key = "alert",
            .val = TUI_COL_ALERT,
        },
        struct_unnamed_114{
            .key = "inactive",
            .val = TUI_COL_INACTIVE,
        },
        struct_unnamed_114{
            .key = "reference",
            .val = TUI_COL_REFERENCE,
        },
        struct_unnamed_114{
            .key = "ui",
            .val = TUI_COL_UI,
        },
        struct_unnamed_114{
            .key = "ref_black",
            .val = TUI_COL_TBASE + 0,
        },
        struct_unnamed_114{
            .key = "ref_red",
            .val = TUI_COL_TBASE + 1,
        },
        struct_unnamed_114{
            .key = "ref_green",
            .val = TUI_COL_TBASE + 2,
        },
        struct_unnamed_114{
            .key = "ref_yellow",
            .val = TUI_COL_TBASE + 3,
        },
        struct_unnamed_114{
            .key = "ref_blue",
            .val = TUI_COL_TBASE + 4,
        },
        struct_unnamed_114{
            .key = "ref_magenta",
            .val = TUI_COL_TBASE + 5,
        },
        struct_unnamed_114{
            .key = "ref_cyan",
            .val = TUI_COL_TBASE + 6,
        },
        struct_unnamed_114{
            .key = "ref_grey",
            .val = TUI_COL_TBASE + 8,
        },
        struct_unnamed_114{
            .key = "ref_light_grey",
            .val = TUI_COL_TBASE + 7,
        },
        struct_unnamed_114{
            .key = "ref_light_red",
            .val = TUI_COL_TBASE + 9,
        },
        struct_unnamed_114{
            .key = "ref_light_green",
            .val = TUI_COL_TBASE + 10,
        },
        struct_unnamed_114{
            .key = "ref_light_yellow",
            .val = TUI_COL_TBASE + 11,
        },
        struct_unnamed_114{
            .key = "ref_light_blue",
            .val = TUI_COL_TBASE + 12,
        },
        struct_unnamed_114{
            .key = "ref_light_magenta",
            .val = TUI_COL_TBASE + 13,
        },
        struct_unnamed_114{
            .key = "ref_light_cyan",
            .val = TUI_COL_TBASE + 14,
        },
        struct_unnamed_114{
            .key = "ref_white",
            .val = TUI_COL_TBASE + 15,
        },
    };
    lua_pushlstring(L, "colors", 6);
    lua_createtable(L, 0, 0);
    {
        var i: usize = 0;
        while (i < 30) : (i +%= 1) {
            lua_pushstring(L, coltbl[i].key);
            lua_pushnumber(L, @as(lua_Number, @floatFromInt(coltbl[i].val)));
            lua_rawset(L, -3);
        }
    }
    lua_settable(L, -3);
    const struct_unnamed_115 = extern struct {
        key: [*c]const u8 = std.mem.zeroes([*c]const u8),
        val: c_int = std.mem.zeroes(c_int),
    };
    var symtbl: [135]struct_unnamed_115 = [135]struct_unnamed_115{
        struct_unnamed_115{
            .key = "TUIK_UNKNOWN",
            .val = c.TUIK_UNKNOWN,
        },
        struct_unnamed_115{
            .key = "TUIK_FIRST",
            .val = c.TUIK_FIRST,
        },
        struct_unnamed_115{
            .key = "TUIK_BACKSPACE",
            .val = c.TUIK_BACKSPACE,
        },
        struct_unnamed_115{
            .key = "TUIK_TAB",
            .val = c.TUIK_TAB,
        },
        struct_unnamed_115{
            .key = "TUIK_CLEAR",
            .val = c.TUIK_CLEAR,
        },
        struct_unnamed_115{
            .key = "TUIK_RETURN",
            .val = c.TUIK_RETURN,
        },
        struct_unnamed_115{
            .key = "TUIK_PAUSE",
            .val = c.TUIK_PAUSE,
        },
        struct_unnamed_115{
            .key = "TUIK_ESCAPE",
            .val = c.TUIK_ESCAPE,
        },
        struct_unnamed_115{
            .key = "TUIK_SPACE",
            .val = c.TUIK_SPACE,
        },
        struct_unnamed_115{
            .key = "TUIK_EXCLAIM",
            .val = c.TUIK_EXCLAIM,
        },
        struct_unnamed_115{
            .key = "TUIK_QUOTEDBL",
            .val = c.TUIK_QUOTEDBL,
        },
        struct_unnamed_115{
            .key = "TUIK_HASH",
            .val = c.TUIK_HASH,
        },
        struct_unnamed_115{
            .key = "TUIK_DOLLAR",
            .val = c.TUIK_DOLLAR,
        },
        struct_unnamed_115{
            .key = "TUIK_0",
            .val = c.TUIK_0,
        },
        struct_unnamed_115{
            .key = "TUIK_1",
            .val = c.TUIK_1,
        },
        struct_unnamed_115{
            .key = "TUIK_2",
            .val = c.TUIK_2,
        },
        struct_unnamed_115{
            .key = "TUIK_3",
            .val = c.TUIK_3,
        },
        struct_unnamed_115{
            .key = "TUIK_4",
            .val = c.TUIK_4,
        },
        struct_unnamed_115{
            .key = "TUIK_5",
            .val = c.TUIK_5,
        },
        struct_unnamed_115{
            .key = "TUIK_6",
            .val = c.TUIK_6,
        },
        struct_unnamed_115{
            .key = "TUIK_7",
            .val = c.TUIK_7,
        },
        struct_unnamed_115{
            .key = "TUIK_8",
            .val = c.TUIK_8,
        },
        struct_unnamed_115{
            .key = "TUIK_9",
            .val = c.TUIK_9,
        },
        struct_unnamed_115{
            .key = "TUIK_MINUS",
            .val = c.TUIK_MINUS,
        },
        struct_unnamed_115{
            .key = "TUIK_EQUALS",
            .val = c.TUIK_EQUALS,
        },
        struct_unnamed_115{
            .key = "TUIK_A",
            .val = c.TUIK_A,
        },
        struct_unnamed_115{
            .key = "TUIK_B",
            .val = c.TUIK_B,
        },
        struct_unnamed_115{
            .key = "TUIK_C",
            .val = c.TUIK_C,
        },
        struct_unnamed_115{
            .key = "TUIK_D",
            .val = c.TUIK_D,
        },
        struct_unnamed_115{
            .key = "TUIK_E",
            .val = c.TUIK_E,
        },
        struct_unnamed_115{
            .key = "TUIK_F",
            .val = c.TUIK_F,
        },
        struct_unnamed_115{
            .key = "TUIK_G",
            .val = c.TUIK_G,
        },
        struct_unnamed_115{
            .key = "TUIK_H",
            .val = c.TUIK_H,
        },
        struct_unnamed_115{
            .key = "TUIK_I",
            .val = c.TUIK_I,
        },
        struct_unnamed_115{
            .key = "TUIK_J",
            .val = c.TUIK_J,
        },
        struct_unnamed_115{
            .key = "TUIK_K",
            .val = c.TUIK_K,
        },
        struct_unnamed_115{
            .key = "TUIK_L",
            .val = c.TUIK_L,
        },
        struct_unnamed_115{
            .key = "TUIK_M",
            .val = c.TUIK_M,
        },
        struct_unnamed_115{
            .key = "TUIK_N",
            .val = c.TUIK_N,
        },
        struct_unnamed_115{
            .key = "TUIK_O",
            .val = c.TUIK_O,
        },
        struct_unnamed_115{
            .key = "TUIK_P",
            .val = c.TUIK_P,
        },
        struct_unnamed_115{
            .key = "TUIK_Q",
            .val = c.TUIK_Q,
        },
        struct_unnamed_115{
            .key = "TUIK_R",
            .val = c.TUIK_R,
        },
        struct_unnamed_115{
            .key = "TUIK_S",
            .val = c.TUIK_S,
        },
        struct_unnamed_115{
            .key = "TUIK_T",
            .val = c.TUIK_T,
        },
        struct_unnamed_115{
            .key = "TUIK_U",
            .val = c.TUIK_U,
        },
        struct_unnamed_115{
            .key = "TUIK_V",
            .val = c.TUIK_V,
        },
        struct_unnamed_115{
            .key = "TUIK_W",
            .val = c.TUIK_W,
        },
        struct_unnamed_115{
            .key = "TUIK_X",
            .val = c.TUIK_X,
        },
        struct_unnamed_115{
            .key = "TUIK_Y",
            .val = c.TUIK_Y,
        },
        struct_unnamed_115{
            .key = "TUIK_Z",
            .val = c.TUIK_Z,
        },
        struct_unnamed_115{
            .key = "TUIK_LESS",
            .val = c.TUIK_LESS,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_LEFTBRACE",
            .val = c.TUIK_KP_LEFTBRACE,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_RIGHTBRACE",
            .val = c.TUIK_KP_RIGHTBRACE,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_ENTER",
            .val = c.TUIK_KP_ENTER,
        },
        struct_unnamed_115{
            .key = "TUIK_LCTRL",
            .val = c.TUIK_LCTRL,
        },
        struct_unnamed_115{
            .key = "TUIK_SEMICOLON",
            .val = c.TUIK_SEMICOLON,
        },
        struct_unnamed_115{
            .key = "TUIK_COLON",
            .val = c.TUIK_COLON,
        },
        struct_unnamed_115{
            .key = "TUIK_APOSTROPHE",
            .val = c.TUIK_APOSTROPHE,
        },
        struct_unnamed_115{
            .key = "TUIK_GRAVE",
            .val = c.TUIK_GRAVE,
        },
        struct_unnamed_115{
            .key = "TUIK_LSHIFT",
            .val = c.TUIK_LSHIFT,
        },
        struct_unnamed_115{
            .key = "TUIK_BACKSLASH",
            .val = c.TUIK_BACKSLASH,
        },
        struct_unnamed_115{
            .key = "TUIK_COMMA",
            .val = c.TUIK_COMMA,
        },
        struct_unnamed_115{
            .key = "TUIK_PERIOD",
            .val = c.TUIK_PERIOD,
        },
        struct_unnamed_115{
            .key = "TUIK_SLASH",
            .val = c.TUIK_SLASH,
        },
        struct_unnamed_115{
            .key = "TUIK_RSHIFT",
            .val = c.TUIK_RSHIFT,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_MULTIPLY",
            .val = c.TUIK_KP_MULTIPLY,
        },
        struct_unnamed_115{
            .key = "TUIK_LALT",
            .val = c.TUIK_LALT,
        },
        struct_unnamed_115{
            .key = "TUIK_CAPSLOCK",
            .val = c.TUIK_CAPSLOCK,
        },
        struct_unnamed_115{
            .key = "TUIK_F1",
            .val = c.TUIK_F1,
        },
        struct_unnamed_115{
            .key = "TUIK_F2",
            .val = c.TUIK_F2,
        },
        struct_unnamed_115{
            .key = "TUIK_F3",
            .val = c.TUIK_F3,
        },
        struct_unnamed_115{
            .key = "TUIK_F4",
            .val = c.TUIK_F4,
        },
        struct_unnamed_115{
            .key = "TUIK_F5",
            .val = c.TUIK_F5,
        },
        struct_unnamed_115{
            .key = "TUIK_F6",
            .val = c.TUIK_F6,
        },
        struct_unnamed_115{
            .key = "TUIK_F7",
            .val = c.TUIK_F7,
        },
        struct_unnamed_115{
            .key = "TUIK_F8",
            .val = c.TUIK_F8,
        },
        struct_unnamed_115{
            .key = "TUIK_F9",
            .val = c.TUIK_F9,
        },
        struct_unnamed_115{
            .key = "TUIK_F10",
            .val = c.TUIK_F10,
        },
        struct_unnamed_115{
            .key = "TUIK_NUMLOCKCLEAR",
            .val = c.TUIK_NUMLOCKCLEAR,
        },
        struct_unnamed_115{
            .key = "TUIK_SCROLLLOCK",
            .val = c.TUIK_SCROLLLOCK,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_0",
            .val = c.TUIK_KP_0,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_1",
            .val = c.TUIK_KP_1,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_2",
            .val = c.TUIK_KP_2,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_3",
            .val = c.TUIK_KP_3,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_4",
            .val = c.TUIK_KP_4,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_5",
            .val = c.TUIK_KP_5,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_6",
            .val = c.TUIK_KP_6,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_7",
            .val = c.TUIK_KP_7,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_8",
            .val = c.TUIK_KP_8,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_9",
            .val = c.TUIK_KP_9,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_MINUS",
            .val = c.TUIK_KP_MINUS,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_PLUS",
            .val = c.TUIK_KP_PLUS,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_PERIOD",
            .val = c.TUIK_KP_PERIOD,
        },
        struct_unnamed_115{
            .key = "TUIK_INTERNATIONAL1",
            .val = c.TUIK_INTERNATIONAL1,
        },
        struct_unnamed_115{
            .key = "TUIK_INTERNATIONAL2",
            .val = c.TUIK_INTERNATIONAL2,
        },
        struct_unnamed_115{
            .key = "TUIK_F11",
            .val = c.TUIK_F11,
        },
        struct_unnamed_115{
            .key = "TUIK_F12",
            .val = c.TUIK_F12,
        },
        struct_unnamed_115{
            .key = "TUIK_INTERNATIONAL3",
            .val = c.TUIK_INTERNATIONAL3,
        },
        struct_unnamed_115{
            .key = "TUIK_INTERNATIONAL4",
            .val = c.TUIK_INTERNATIONAL4,
        },
        struct_unnamed_115{
            .key = "TUIK_INTERNATIONAL5",
            .val = c.TUIK_INTERNATIONAL5,
        },
        struct_unnamed_115{
            .key = "TUIK_INTERNATIONAL6",
            .val = c.TUIK_INTERNATIONAL6,
        },
        struct_unnamed_115{
            .key = "TUIK_INTERNATIONAL7",
            .val = c.TUIK_INTERNATIONAL7,
        },
        struct_unnamed_115{
            .key = "TUIK_INTERNATIONAL8",
            .val = c.TUIK_INTERNATIONAL8,
        },
        struct_unnamed_115{
            .key = "TUIK_INTERNATIONAL9",
            .val = c.TUIK_INTERNATIONAL9,
        },
        struct_unnamed_115{
            .key = "TUIK_RCTRL",
            .val = c.TUIK_RCTRL,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_DIVIDE",
            .val = c.TUIK_KP_DIVIDE,
        },
        struct_unnamed_115{
            .key = "TUIK_SYSREQ",
            .val = c.TUIK_SYSREQ,
        },
        struct_unnamed_115{
            .key = "TUIK_RALT",
            .val = c.TUIK_RALT,
        },
        struct_unnamed_115{
            .key = "TUIK_HOME",
            .val = c.TUIK_HOME,
        },
        struct_unnamed_115{
            .key = "TUIK_UP",
            .val = c.TUIK_UP,
        },
        struct_unnamed_115{
            .key = "TUIK_PAGEUP",
            .val = c.TUIK_PAGEUP,
        },
        struct_unnamed_115{
            .key = "TUIK_LEFT",
            .val = c.TUIK_LEFT,
        },
        struct_unnamed_115{
            .key = "TUIK_RIGHT",
            .val = c.TUIK_RIGHT,
        },
        struct_unnamed_115{
            .key = "TUIK_END",
            .val = c.TUIK_END,
        },
        struct_unnamed_115{
            .key = "TUIK_DOWN",
            .val = c.TUIK_DOWN,
        },
        struct_unnamed_115{
            .key = "TUIK_PAGEDOWN",
            .val = c.TUIK_PAGEDOWN,
        },
        struct_unnamed_115{
            .key = "TUIK_INSERT",
            .val = c.TUIK_INSERT,
        },
        struct_unnamed_115{
            .key = "TUIK_DELETE",
            .val = c.TUIK_DELETE,
        },
        struct_unnamed_115{
            .key = "TUIK_LMETA",
            .val = c.TUIK_LMETA,
        },
        struct_unnamed_115{
            .key = "TUIK_RMETA",
            .val = c.TUIK_RMETA,
        },
        struct_unnamed_115{
            .key = "TUIK_COMPOSE",
            .val = c.TUIK_COMPOSE,
        },
        struct_unnamed_115{
            .key = "TUIK_MUTE",
            .val = c.TUIK_MUTE,
        },
        struct_unnamed_115{
            .key = "TUIK_VOLUMEDOWN",
            .val = c.TUIK_VOLUMEDOWN,
        },
        struct_unnamed_115{
            .key = "TUIK_VOLUMEUP",
            .val = c.TUIK_VOLUMEUP,
        },
        struct_unnamed_115{
            .key = "TUIK_POWER",
            .val = c.TUIK_POWER,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_EQUALS",
            .val = c.TUIK_EQUALS,
        },
        struct_unnamed_115{
            .key = "TUIK_KP_PLUSMINUS",
            .val = c.TUIK_KP_PLUSMINUS,
        },
        struct_unnamed_115{
            .key = "TUIK_LANG1",
            .val = c.TUIK_LANG1,
        },
        struct_unnamed_115{
            .key = "TUIK_LANG2",
            .val = c.TUIK_LANG2,
        },
        struct_unnamed_115{
            .key = "TUIK_LANG3",
            .val = c.TUIK_LANG3,
        },
        struct_unnamed_115{
            .key = "TUIK_LGUI",
            .val = c.TUIK_LGUI,
        },
        struct_unnamed_115{
            .key = "TUIK_RGUI",
            .val = c.TUIK_RGUI,
        },
        struct_unnamed_115{
            .key = "TUIK_STOP",
            .val = c.TUIK_STOP,
        },
        struct_unnamed_115{
            .key = "TUIK_AGAIN",
            .val = c.TUIK_AGAIN,
        },
    };
    lua_pushlstring(L, "keys", 4);
    lua_createtable(L, 0, 0);
    {
        var i: usize = 0;
        while (i < 135) : (i +%= 1) {
            lua_pushstring(L, &symtbl[i].key[5]);
            lua_pushnumber(L, @as(lua_Number, @floatFromInt(symtbl[i].val)));
            lua_rawset(L, -3);
            lua_pushnumber(L, @as(lua_Number, @floatFromInt(symtbl[i].val)));
            lua_pushstring(L, &symtbl[i].key[5]);
            lua_rawset(L, -3);
        }
    }
    lua_settable(L, -3);
    const struct_unnamed_116 = extern struct {
        key: [*c]const u8 = std.mem.zeroes([*c]const u8),
        val: c_int = std.mem.zeroes(c_int),
    };
    const modtbl: [13]struct_unnamed_116 = [13]struct_unnamed_116{
        struct_unnamed_116{
            .key = "LSHIFT",
            .val = c.TUIM_LSHIFT,
        },
        struct_unnamed_116{
            .key = "RSHIFT",
            .val = c.TUIM_RSHIFT,
        },
        struct_unnamed_116{
            .key = "SHIFT",
            .val = c.TUIM_LSHIFT | c.TUIM_RSHIFT,
        },
        struct_unnamed_116{
            .key = "LCTRL",
            .val = c.TUIM_LCTRL,
        },
        struct_unnamed_116{
            .key = "RCTRL",
            .val = c.TUIM_RCTRL,
        },
        struct_unnamed_116{
            .key = "CTRL",
            .val = c.TUIM_LCTRL | c.TUIM_RCTRL,
        },
        struct_unnamed_116{
            .key = "LALT",
            .val = c.TUIM_LALT,
        },
        struct_unnamed_116{
            .key = "RALT",
            .val = c.TUIM_RALT,
        },
        struct_unnamed_116{
            .key = "ALT",
            .val = c.TUIM_LALT | c.TUIM_RALT,
        },
        struct_unnamed_116{
            .key = "LMETA",
            .val = c.TUIM_LMETA,
        },
        struct_unnamed_116{
            .key = "RMETA",
            .val = c.TUIM_RMETA,
        },
        struct_unnamed_116{
            .key = "META",
            .val = c.TUIM_LMETA | c.TUIM_RMETA,
        },
        struct_unnamed_116{
            .key = "REPEAT",
            .val = c.TUIM_REPEAT,
        },
    };
    lua_pushlstring(L, "modifiers", 9);
    lua_createtable(L, 0, 0);
    {
        var i: usize = 0;
        while (i < 13) : (i +%= 1) {
            lua_pushstring(L, modtbl[i].key);
            lua_pushnumber(L, @as(lua_Number, @floatFromInt(modtbl[i].val)));
            lua_rawset(L, -3);
        }
    }
    lua_settable(L, -3);
    if (luaL_newmetatable(L, "widget_readline") != 0) {
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        lua_pushcclosure(L, &readline_prompt, 0);
        lua_setfield(L, -2, "set_prompt");
        lua_pushcclosure(L, &readline_history, 0);
        lua_setfield(L, -2, "set_history");
        lua_pushcclosure(L, &readline_suggest, 0);
        lua_setfield(L, -2, "suggest");
        lua_pushcclosure(L, &readline_set, 0);
        lua_setfield(L, -2, "set");
        lua_pushcclosure(L, &readline_get, 0);
        lua_setfield(L, -2, "get");
        lua_pushcclosure(L, &readline_region, 0);
        lua_setfield(L, -2, "bounding_box");
        lua_pushcclosure(L, &readline_autocomplete, 0);
        lua_setfield(L, -2, "autocomplete");
    }
    lua_settop(L, -1 - 1);
    if (luaL_newmetatable(L, "widget_listview") != 0) {
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        lua_pushcclosure(L, &listwnd_pos, 0);
        lua_setfield(L, -2, "position");
        lua_pushcclosure(L, &listwnd_update, 0);
        lua_setfield(L, -2, "update");
    }
    lua_settop(L, -1 - 1);
    if (luaL_newmetatable(L, "widget_bufferview") != 0) {
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        lua_pushcclosure(L, &bufferwnd_seek, 0);
        lua_setfield(L, -2, "seek");
    }
    lua_settop(L, -1 - 1);
}
pub fn init_lmeta(L: ?*lua_State, l: [*c]struct_tui_lmeta, p: [*c]struct_tui_lmeta) callconv(.c) void {
    l.* = struct_tui_lmeta{
        .unnamed_0 = zeroUnnamed0(),
        .submeta = std.mem.zeroes([64][*c]struct_tui_lmeta),
        .parent = p,
        .n_subs = std.mem.zeroes(usize),
        .pending_mask = std.mem.zeroes(u8),
        .pending = zeroPending(),
        .embed = 0,
        .tui_state = @as(isize, @bitCast(@as(isize, -2))),
        .href = @as(isize, @bitCast(@as(isize, -2))),
        .widget_mode = 0,
        .widget_closure = @as(isize, @bitCast(@as(isize, -2))),
        .widget_state = @as(isize, @bitCast(@as(isize, -2))),
        .widget_meta = null,
        .in_callback = false,
        .blobs = null,
        .cwd = null,
        .cwd_sz = std.mem.zeroes(usize),
        .cwd_fd = -1,
        .in_subwnd = null,
        .subwnd_handover = 0,
        .lua = L,
    };
    l.*.submeta[0] = l;
    _ = lua_getfield(L, -1001000, "Arcan TUI");
    _ = lua_setmetatable(L, -2);
}
pub fn luaL_optbnumber(L: ?*lua_State, narg: c_int, opt: lua_Number) callconv(.c) bool {
    if (lua_isnumber(L, narg) != 0) return lua_tonumber(L, narg) != 0 else if (lua_type(L, narg) == 1) return lua_toboolean(L, narg) != 0 else return opt != 0;
    return false;
}
pub fn on_label(T: ?*struct_tui_context, label: [*c]const u8, act: bool, t: ?*anyopaque) callconv(.c) bool {
    _ = T;
    _ = act;
    if (t == null) return false;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return false;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for false");
    }
    lua_getfield(L, -1, "label");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return false;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_pushstring(L, label);
    if (0 != lua_pcall(L, 2, 1, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
    return false;
}
pub fn intblbool(L: ?*lua_State, ind: c_int, field: [*c]const u8) callconv(.c) bool {
    lua_getfield(L, ind, field);
    const rv: bool = lua_toboolean(L, -1) != 0;
    lua_settop(L, -1 - 1);
    return rv;
}
pub fn intblint(L: ?*lua_State, ind: c_int, field: [*c]const u8, ok: [*c]bool) callconv(.c) c_int {
    lua_getfield(L, ind, field);
    ok.* = lua_isnumber(L, -1) != 0;
    const rv: c_int = @as(c_int, @truncate(lua_tointeger(L, -1)));
    lua_settop(L, -1 - 1);
    return rv;
}
pub fn tui_lref(L: ?*lua_State, ind: c_int, func: [*c]const u8, src: [*c]const u8, @"type": c_int) callconv(.c) isize {
    _ = func;
    _ = src;
    if (lua_type(L, ind) != @"type") {
        _ = luaL_error(L, "requested ref of unexpected type");
        return @as(isize, @bitCast(@as(isize, -2)));
    }
    lua_pushvalue(L, ind);
    const ret: isize = @as(isize, @bitCast(@as(isize, luaL_ref(L, -1001000))));
    return ret;
}
pub fn tui_lunref(L: ?*lua_State, val: isize, src: [*c]const u8, @"type": c_int) callconv(.c) isize {
    _ = src;
    if (val == @as(isize, @bitCast(@as(isize, -2)))) return @as(isize, @bitCast(@as(isize, -2)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(val)));
    if (lua_type(L, -1) != @"type") {
        _ = luaL_error(L, "requested unref of unexpected type");
        return @as(isize, @bitCast(@as(isize, -2)));
    }
    lua_settop(L, -1 - 1);
    luaL_unref(L, -1001000, @as(c_int, @truncate(val)));
    return @as(isize, @bitCast(@as(isize, -2)));
}
pub fn get_wndhint(ib: [*c]struct_tui_lmeta, L: ?*lua_State, ind: c_int) callconv(.c) struct_tui_constraints {
    var res: struct_tui_constraints = struct_tui_constraints{
        .anch_row = 0,
        .anch_col = 0,
        .max_rows = 0,
        .max_cols = 0,
        .min_rows = 0,
        .min_cols = 0,
        .hide = 0,
        .embed = 0,
    };
    var ok: bool = undefined;
    var num: c_int = intblint(L, ind, "anchor_row", &ok);
    if (ok) {
        res.anch_row = num;
    }
    num = intblint(L, ind, "anchor_col", &ok);
    if (ok) {
        res.anch_col = num;
    }
    num = intblint(L, ind, "max_rows", &ok);
    if (ok) {
        res.max_rows = num;
    }
    num = intblint(L, ind, "min_rows", &ok);
    if (ok) {
        res.min_rows = num;
    }
    num = intblint(L, ind, "max_cols", &ok);
    if (ok) {
        res.max_cols = num;
    }
    num = intblint(L, ind, "min_cols", &ok);
    if (ok) {
        res.min_cols = num;
    }
    if (ib.*.embed != 0) {
        if (intblbool(L, ind, "scale")) {
            ib.*.embed = 2;
        } else if (intblbool(L, ind, "scale-hint")) {
            ib.*.embed = 3;
        } else {
            ib.*.embed = 1;
        }
    }
    res.embed = ib.*.embed;
    res.hide = @intFromBool(intblbool(L, ind, "hidden"));
    return res;
}
pub fn on_u8(T: ?*struct_tui_context, @"u8": [*c]const u8, len: usize, t: ?*anyopaque) callconv(.c) bool {
    _ = T;
    if (t == null) return false;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return false;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for false");
    }
    lua_getfield(L, -1, "utf8");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return false;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_pushlstring(L, @"u8", len);
    if (0 != lua_pcall(L, 2, 1, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    var rv: bool = false;
    if (lua_isnumber(L, -1) != 0) {
        rv = lua_tonumber(L, -1) != 0;
    } else if (lua_type(L, -1) == 1) {
        rv = lua_toboolean(L, -1) != 0;
    }
    lua_settop(L, -1 - 1);
    lua_settop(L, -2 - 1);
    return rv;
}
pub fn on_message(T: ?*struct_tui_context, msg: [*c]const u8, cont: bool, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "message");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_pushstring(L, msg);
    lua_pushboolean(L, @intFromBool(cont));
    if (0 != lua_pcall(L, 2, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_mouse(T: ?*struct_tui_context, relative: bool, x: c_int, y: c_int, modifiers: c_int, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "mouse_motion");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_pushboolean(L, @intFromBool(relative));
    lua_pushnumber(L, @floatFromInt(x));
    lua_pushnumber(L, @floatFromInt(y));
    lua_pushnumber(L, @floatFromInt(modifiers));
    if (0 != lua_pcall(L, 5, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_mouse_button(T: ?*struct_tui_context, x: c_int, y: c_int, subid: c_int, active: bool, modifiers: c_int, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "mouse_button");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_pushnumber(L, @floatFromInt(subid));
    lua_pushnumber(L, @floatFromInt(x));
    lua_pushnumber(L, @floatFromInt(y));
    lua_pushnumber(L, @floatFromInt(modifiers));
    lua_pushboolean(L, @intFromBool(active));
    if (0 != lua_pcall(L, 6, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_key(T: ?*struct_tui_context, xkeysym: u32, scancode: u8, mods: u16, subid: u16, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "key");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_pushnumber(L, @floatFromInt(subid));
    lua_pushnumber(L, @floatFromInt(xkeysym));
    lua_pushnumber(L, @floatFromInt(scancode));
    lua_pushnumber(L, @floatFromInt(mods));
    if (0 != lua_pcall(L, 5, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_misc(T: ?*struct_tui_context, ev: [*c]const arcan_ioevent, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    _ = ev;
    _ = t;
}
pub fn on_recolor(T: ?*struct_tui_context, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "recolor");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    if (0 != lua_pcall(L, 1, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_reset(T: ?*struct_tui_context, level: c_int, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "reset");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_pushnumber(L, @floatFromInt(level));
    if (0 != lua_pcall(L, 2, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_state(T: ?*struct_tui_context, input: bool, fd: c_int, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, if (@intFromBool(input) != 0) "state_in" else "state_out");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    if (alt_nbio_import(L, fd, @as(mode_t, @bitCast(if (@intFromBool(input) != 0) @as(c_int, 0) else @as(c_int, 1))), null, null)) {
        if (0 != lua_pcall(L, 2, 0, 0)) {
            _ = luaL_error(L, lua_tolstring(L, -1, null));
        }
    } else {
        lua_settop(L, -1 - 1);
    }
    lua_settop(L, -2 - 1);
}
pub fn on_bchunk(T: ?*struct_tui_context, input: bool, size: u64, fd: c_int, @"type": [*c]const u8, t: ?*anyopaque) callconv(.c) void {
    _ = size;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, if (@intFromBool(input) != 0) "bchunk_in" else "bchunk_out");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    if (alt_nbio_import(L, fd, @as(mode_t, @bitCast(if (@intFromBool(input) != 0) @as(c_int, 0) else @as(c_int, 1))), null, null)) {
        lua_pushstring(L, @"type");
        const fdp: [*c]u8 = arcan_tui_fdresolve(T, fd);
        if (fdp != null) {
            lua_pushstring(L, fdp);
        } else {
            lua_pushnil(L);
        }
        if (0 != lua_pcall(L, 4, 0, 0)) {
            _ = luaL_error(L, lua_tolstring(L, -1, null));
        }
        free(@as(?*anyopaque, @ptrCast(fdp)));
    } else {
        lua_settop(L, -1 - 1);
    }
    lua_settop(L, -2 - 1);
}
pub fn on_vpaste(T: ?*struct_tui_context, vidp: [*c]shmif_pixel, w: usize, h: usize, stride: usize, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    _ = vidp;
    _ = w;
    _ = h;
    _ = stride;
    _ = t;
}
pub fn on_apaste(T: ?*struct_tui_context, audp: [*c]shmif_asample, n_samples: usize, frequency: usize, nch: usize, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    _ = audp;
    _ = n_samples;
    _ = frequency;
    _ = nch;
    _ = t;
}
pub fn on_tick(T: ?*struct_tui_context, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "tick");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    if (0 != lua_pcall(L, 1, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_utf8_paste(T: ?*struct_tui_context, str: [*c]const u8, len: usize, cont: bool, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "paste");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_pushlstring(L, str, len);
    lua_pushnumber(L, @floatFromInt(@intFromBool(cont)));
    if (0 != lua_pcall(L, 3, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_resized(T: ?*struct_tui_context, neww: usize, newh: usize, col: usize, row: usize, t: ?*anyopaque) callconv(.c) void {
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "resized");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    if (meta.*.unnamed_0.tui == null) {
        meta.*.unnamed_0.tui = T;
    }
    lua_pushnumber(L, @floatFromInt(col));
    lua_pushnumber(L, @floatFromInt(row));
    lua_pushnumber(L, @floatFromInt(neww));
    lua_pushnumber(L, @floatFromInt(newh));
    if (0 != lua_pcall(L, 5, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_resize(T: ?*struct_tui_context, neww: usize, newh: usize, col: usize, row: usize, t: ?*anyopaque) callconv(.c) void {
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    lua_getfield(L, -1, "resize");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -2 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    if (meta.*.unnamed_0.tui == null) {
        meta.*.unnamed_0.tui = T;
    }
    lua_pushnumber(L, @floatFromInt(col));
    lua_pushnumber(L, @floatFromInt(row));
    lua_pushnumber(L, @floatFromInt(neww));
    lua_pushnumber(L, @floatFromInt(newh));
    if (0 != lua_pcall(L, 5, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn tui_phandover(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib.*.in_subwnd == null) {
        _ = luaL_error(L, "phandover(...) - only permitted inside subwindow closure");
    }
    var env: [*c][*c]u8 = null;
    var argv: [*c][*c]u8 = null;
    const path: [*c]const u8 = luaL_checklstring(L, 2, null);
    const mode: [*c]const u8 = luaL_checklstring(L, 3, null);
    if (lua_type(L, 4) == 5) {
        argv = tui_popen_tbltoargv(L, 4);
    }
    if (lua_type(L, 5) == 5) {
        env = tui_popen_tbltoenv(L, 5);
    }
    var fds: [3]c_int = [3]c_int{
        -1,
        -1,
        -1,
    };
    var fds_ptr: [3][*c]c_int = [3][*c]c_int{
        &fds[0],
        &fds[1],
        &fds[2],
    };
    if (strchr(mode, 'r') == null) {
        fds_ptr[1] = null;
    }
    if (strchr(mode, 'w') == null) {
        fds_ptr[0] = null;
    }
    if (strchr(mode, 'e') == null) {
        fds_ptr[2] = null;
    }
    const pid: pid_t = arcan_tui_handover_pipe(ib.*.unnamed_0.tui, null, path, argv, env, @ptrCast(@alignCast(&fds_ptr[0])), @as(usize, @bitCast(@as(isize, 3))));
    ib.*.subwnd_handover = @intFromBool(pid != -1);
    if (env != null) {
        var cur: [*c][*c]u8 = env;
        while (cur.* != null) {
            free(@as(?*anyopaque, @ptrCast((blk: {
                const ref = &cur;
                const tmp = ref.*;
                ref.* += 1;
                break :blk tmp;
            }).*)));
        }
        free(@as(?*anyopaque, @ptrCast(env)));
    }
    if (argv != null) {
        var cur: [*c][*c]u8 = argv;
        while (cur.* != null) {
            free(@as(?*anyopaque, @ptrCast((blk: {
                const ref = &cur;
                const tmp = ref.*;
                ref.* += 1;
                break :blk tmp;
            }).*)));
        }
        free(@as(?*anyopaque, @ptrCast(argv)));
    }
    ib.*.in_subwnd = null;
    if (-1 == pid) return 0;
    _ = alt_nbio_import(L, fds[0], @as(mode_t, @bitCast(@as(c_int, 1))), null, null);
    _ = alt_nbio_import(L, fds[1], @as(mode_t, @bitCast(@as(c_int, 0))), null, null);
    _ = alt_nbio_import(L, fds[2], @as(mode_t, @bitCast(@as(c_int, 0))), null, null);
    lua_pushnumber(L, @floatFromInt(pid));
    return 4;
}
pub fn on_subwindow(T: ?*struct_tui_context, new: [*c]arcan_tui_conn, id: u32, @"type": u8, t: ?*anyopaque) callconv(.c) bool {
    var mid = id;
    mid ^= req_cookie;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return false;
    if ((mid >= 8) or !((@as(c_int, @bitCast(@as(c_uint, meta.*.pending_mask))) & (@as(c_int, 1) << @intCast(mid))) != 0)) return false;
    const cb: isize = meta.*.pending[mid].id;
    meta.*.pending[mid].id = @as(isize, @bitCast(@as(isize, -2)));
    meta.*.pending_mask &= @as(u8, @bitCast(@as(i8, @truncate(~(@as(c_int, 1) << @intCast(mid))))));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(cb)));
    if (lua_type(L, -1) != 6) {
        _ = luaL_error(L, "on_subwindow() bad/broken cb-id");
    }
    luaL_unref(L, -1001000, @as(c_int, @truncate(cb)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    if (new == null) {
        if (0 != lua_pcall(L, 1, 0, 0)) {
            _ = luaL_error(L, lua_tolstring(L, -1, null));
        }
        return false;
    }
    const cbcfg = struct {
        var static: struct_tui_cbcfg = std.mem.zeroes(struct_tui_cbcfg);
    };
    _ = memcpy(@as(?*anyopaque, @ptrCast(&cbcfg.static)), @as(?*const anyopaque, @ptrCast(&shared_cbcfg)), @sizeOf(struct_tui_cbcfg));
    const nud: [*c]struct_tui_lmeta = @ptrCast(@alignCast(lua_newuserdata(L, @sizeOf(struct_tui_lmeta))));
    cbcfg.static.tag = @as(?*anyopaque, @ptrCast(nud));
    if (nud == null) {
        if (0 != lua_pcall(L, 1, 0, 0)) {
            _ = luaL_error(L, lua_tolstring(L, -1, null));
        }
        return false;
    }
    init_lmeta(L, nud, meta);
    const ctx: ?*struct_tui_context = arcan_tui_setup(new, T, &cbcfg.static, @sizeOf(struct_tui_cbcfg));
    if (ctx == null) {
        if (0 != lua_pcall(L, 1, 0, 0)) {
            _ = luaL_error(L, lua_tolstring(L, -1, null));
        }
        return false;
    }
    nud.*.unnamed_0.tui = ctx;
    nud.*.embed = meta.*.pending[mid].embed;
    _ = arcan_tui_update_handlers(ctx, &cbcfg.static, null, @sizeOf(struct_tui_cbcfg));
    if (@as(c_int, @bitCast(@as(c_uint, @"type"))) == TUI_WND_HANDOVER) {
        meta.*.in_subwnd = new;
    }
    if ((@as(c_int, @bitCast(@as(c_uint, @"type"))) != TUI_WND_HANDOVER) or (nud.*.embed != 0)) {
        nud.*.tui_state = tui_lref(L, -1, "on_subwindow", "755", 7);
        var wnd_i: usize = 0;
        while (wnd_i < @as(usize, @bitCast(@as(isize, 64)))) : (wnd_i +%= 1) {
            if (meta.*.unnamed_0.subs[wnd_i] == null) {
                meta.*.unnamed_0.subs[wnd_i] = ctx;
                meta.*.submeta[wnd_i] = nud;
                meta.*.n_subs +%= 1;
                break;
            }
        }
    }
    if (0 != lua_pcall(L, 2, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    var ok: bool = true;
    if (meta.*.in_subwnd == null and (@as(c_int, @bitCast(@as(c_uint, @"type"))) == TUI_WND_HANDOVER)) {
        ok = meta.*.subwnd_handover != 0;
    }
    meta.*.in_subwnd = null;
    return ok;
}
pub fn query_label(T: ?*struct_tui_context, ind: usize, country: [*c]const u8, lang: [*c]const u8, dstlbl: [*c]struct_tui_labelent, t: ?*anyopaque) callconv(.c) bool {
    _ = T;
    if (t == null) return false;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return false;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for false");
    }
    lua_getfield(L, -1, "query_label");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return false;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_pushnumber(L, @floatFromInt(ind +% @as(usize, @bitCast(@as(isize, 1)))));
    lua_pushstring(L, country);
    lua_pushstring(L, lang);
    if (0 != lua_pcall(L, 4, 5, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    const msg: [*c]const u8 = luaL_optlstring(L, -5, null, null);
    const descr: [*c]const u8 = luaL_optlstring(L, -4, null, null);
    const gotrep: bool = msg != @as([*c]const u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(0)))));
    if (gotrep) {
        _ = snprintf(@as([*c]u8, @ptrCast(@alignCast(&dstlbl.*.label[0]))), (@sizeOf([16]u8) / @sizeOf(u8)) / @as(usize, @intFromBool(!((@sizeOf([16]u8) % @sizeOf(u8)) != 0))), "%s", msg);
        _ = snprintf(@as([*c]u8, @ptrCast(@alignCast(&dstlbl.*.descr[0]))), (@sizeOf([58]u8) / @sizeOf(u8)) / @as(usize, @intFromBool(!((@sizeOf([58]u8) % @sizeOf(u8)) != 0))), "%s", if (descr != null) descr else @as([*c]const u8, ""));
        dstlbl.*.initial = @as(u16, @intFromFloat(luaL_optnumber(L, -3, @as(lua_Number, @floatFromInt(@as(c_int, 0))))));
        dstlbl.*.modifiers = @as(u16, @intFromFloat(luaL_optnumber(L, -2, @as(lua_Number, @floatFromInt(@as(c_int, 0))))));
        const vsym: [*c]const u8 = luaL_optlstring(L, -1, null, null);
        if (vsym != null) {
            _ = snprintf(@as([*c]u8, @ptrCast(@alignCast(@as([*c]u8, @ptrCast(@alignCast(&dstlbl.*.vsym[0])))))), (@sizeOf([5]u8) / @sizeOf(u8)) / @as(usize, @intFromBool(!((@sizeOf([5]u8) % @sizeOf(u8)) != 0))), "%s", vsym);
        }
        dstlbl.*.idatatype = 0;
    }
    lua_settop(L, -5 - 1);
    lua_settop(L, -2 - 1);
    return gotrep;
}
pub fn on_geohint(T: ?*struct_tui_context, lat: f32, longitude: f32, elev: f32, a3_country: [*c]const u8, a3_language: [*c]const u8, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "geohint");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_pushstring(L, a3_country);
    lua_pushstring(L, a3_language);
    lua_pushnumber(L, @floatCast(lat));
    lua_pushnumber(L, @floatCast(longitude));
    lua_pushnumber(L, @floatCast(elev));
    if (0 != lua_pcall(L, 6, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_visibility(T: ?*struct_tui_context, visible: bool, focus: bool, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "visibility");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_pushboolean(L, @intFromBool(visible));
    lua_pushboolean(L, @intFromBool(focus));
    if (0 != lua_pcall(L, 3, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_exec_state(T: ?*struct_tui_context, state: c_int, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "exec_state");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    switch (state) {
        0 => {
            lua_pushstring(L, "resume");
        },
        1 => {
            lua_pushstring(L, "suspend");
        },
        2 => {
            lua_pushstring(L, "shutdown");
        },
        else => {
            lua_settop(L, -1 - 1);
            return;
        },
    }
    if (0 != lua_pcall(L, 2, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_seek_absolute(T: ?*struct_tui_context, pct: f32, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "seek_absolute");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_pushnumber(L, @floatCast(pct));
    if (0 != lua_pcall(L, 2, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_seek_relative(T: ?*struct_tui_context, rows: isize, cols: isize, t: ?*anyopaque) callconv(.c) void {
    _ = T;
    if (t == null) return;
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    const L: ?*lua_State = meta.*.lua;
    if (meta.*.href == @as(isize, @bitCast(@as(isize, -2)))) return;
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.href)));
    if (lua_type(L, -1) != 5) {
        _ = luaL_error(L, "broken href in handler for ");
    }
    lua_getfield(L, -1, "seek_relative");
    if (lua_type(L, -1) != 6) {
        lua_settop(L, -3 - 1);
        return;
    }
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(meta.*.tui_state)));
    lua_pushnumber(L, @floatFromInt(rows));
    lua_pushnumber(L, @floatFromInt(cols));
    if (0 != lua_pcall(L, 3, 0, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    lua_settop(L, -2 - 1);
}
pub fn on_readline_filter(ch: u32, len: usize, t: ?*anyopaque) callconv(.c) bool {
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    if (meta.*.widget_meta == null or (meta.*.widget_meta.?.*.unnamed_0.readline.filter == @as(isize, @bitCast(@as(isize, -2))))) {
        return true;
    }
    var buf: [4]u8 = undefined;
    const used: usize = arcan_tui_ucs4utf8(ch, @as([*c]u8, @ptrCast(@alignCast(&buf[0]))));
    if (used == 0) {
        return true;
    }
    var res: bool = true;
    const L: ?*lua_State = meta.*.lua;
    lua_rawgeti(meta.*.lua, -1001000, @as(c_int, @truncate(meta.*.widget_meta.?.*.unnamed_0.readline.filter)));
    lua_rawgeti(meta.*.lua, -1001000, @as(c_int, @truncate(meta.*.widget_state)));
    lua_pushlstring(L, @as([*c]u8, @ptrCast(@alignCast(&buf[0]))), used);
    lua_pushinteger(L, @as(lua_Integer, @bitCast(len)));
    if (0 != lua_pcall(L, 3, 1, 0)) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    if (lua_type(L, -1) == 1) {
        res = lua_toboolean(L, -1) != 0;
    } else if (lua_type(L, -1) == 0) {} else {
        _ = luaL_error(L, "verify() bad return type, expected boolean");
    }
    lua_settop(L, -1 - 1);
    return res;
}
pub fn on_readline_suggest_item(item: [*c]const u8, hint: [*c]const u8, t: ?*anyopaque) callconv(.c) void {
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    if (meta.*.widget_meta == null or (meta.*.widget_meta.?.*.unnamed_0.readline.item == @as(isize, @bitCast(@as(isize, -2))))) {
        return;
    }
    const L: ?*lua_State = meta.*.lua;
    lua_rawgeti(meta.*.lua, -1001000, @as(c_int, @truncate(meta.*.widget_meta.?.*.unnamed_0.readline.item)));
    lua_rawgeti(meta.*.lua, -1001000, @as(c_int, @truncate(meta.*.widget_state)));
    lua_pushstring(L, item);
    lua_pushstring(L, hint);
    const rv: c_int = lua_pcall(L, 3, 0, 0);
    if (0 != rv) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
}
pub fn on_readline_verify(message_1: [*c]const u8, prefix: usize, suggest: bool, t: ?*anyopaque) callconv(.c) isize {
    const meta: [*c]struct_tui_lmeta = @ptrCast(@alignCast(t));
    if (meta.*.widget_meta == null or (meta.*.widget_meta.?.*.unnamed_0.readline.verify == @as(isize, @bitCast(@as(isize, -2))))) {
        return @as(isize, @bitCast(@as(isize, -1)));
    }
    const L: ?*lua_State = meta.*.lua;
    lua_rawgeti(meta.*.lua, -1001000, @as(c_int, @truncate(meta.*.widget_meta.?.*.unnamed_0.readline.verify)));
    lua_rawgeti(meta.*.lua, -1001000, @as(c_int, @truncate(meta.*.widget_state)));
    var res: isize = @as(isize, @bitCast(@as(isize, -1)));
    lua_pushlstring(L, message_1, prefix);
    lua_pushstring(L, message_1);
    lua_pushboolean(L, @intFromBool(suggest));
    const rv: c_int = lua_pcall(L, 4, 1, 0);
    if (0 != rv) {
        _ = luaL_error(L, lua_tolstring(L, -1, null));
    }
    if (lua_type(L, -1) == 1) {
        if (lua_toboolean(L, -1) == 0) {
            res = 0;
        }
    } else if (lua_type(L, -1) == 3) {
        res = lua_tointeger(L, -1);
        if (res < 0) {
            res *= @as(isize, @bitCast(@as(isize, -1)));
        }
    }
    lua_settop(L, -1 - 1);
    return res;
}
pub fn on_cli_command(T: ?*struct_tui_context, argv: [*c][*c]const u8, n_elem: usize, command: c_int, feedback: [*c][*c]const u8, n_results: [*c]usize) callconv(.c) c_int {
    _ = T;
    _ = argv;
    _ = n_elem;
    _ = command;
    _ = feedback;
    _ = n_results;
    return TUI_CLI_INVALID;
}
pub fn add_attr_tbl(L: ?*lua_State, attr: struct_tui_screen_attr) callconv(.c) void {
    lua_createtable(L, 0, 0);
    if ((@as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_COLOR_INDEXED) != 0) {
        lua_pushstring(L, "fc");
        lua_pushnumber(L, @floatFromInt(attr.unnamed_0.fc[0]));
        lua_rawset(L, -3);

        lua_pushstring(L, "bc");
        lua_pushnumber(L, @floatFromInt(attr.unnamed_1.bc[0]));
        lua_rawset(L, -3);
    } else {
        lua_pushstring(L, "fr");
        lua_pushnumber(L, @floatFromInt(attr.unnamed_0.unnamed_0.fr));
        lua_rawset(L, -3);

        lua_pushstring(L, "fg");
        lua_pushnumber(L, @floatFromInt(attr.unnamed_0.unnamed_0.fg));
        lua_rawset(L, -3);

        lua_pushstring(L, "fb");
        lua_pushnumber(L, @floatFromInt(attr.unnamed_0.unnamed_0.fb));
        lua_rawset(L, -3);

        lua_pushstring(L, "br");
        lua_pushnumber(L, @floatFromInt(attr.unnamed_1.unnamed_0.br));
        lua_rawset(L, -3);

        lua_pushstring(L, "bg");
        lua_pushnumber(L, @floatFromInt(attr.unnamed_1.unnamed_0.bg));
        lua_rawset(L, -3);

        lua_pushstring(L, "bb");
        lua_pushnumber(L, @floatFromInt(attr.unnamed_1.unnamed_0.bb));
        lua_rawset(L, -3);
    }
    lua_pushstring(L, "bold");
    lua_pushboolean(L, @as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_BOLD);
    lua_rawset(L, -3);

    lua_pushstring(L, "italic");
    lua_pushboolean(L, @as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_ITALIC);
    lua_rawset(L, -3);

    lua_pushstring(L, "inverse");
    lua_pushboolean(L, @as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_INVERSE);
    lua_rawset(L, -3);

    lua_pushstring(L, "underline");
    lua_pushboolean(L, @as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_UNDERLINE);
    lua_rawset(L, -3);

    lua_pushstring(L, "underline_alt");
    lua_pushboolean(L, @as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_UNDERLINE_ALT);
    lua_rawset(L, -3);

    lua_pushstring(L, "protect");
    lua_pushboolean(L, @as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_PROTECT);
    lua_rawset(L, -3);

    lua_pushstring(L, "blink");
    lua_pushboolean(L, @as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_BLINK);
    lua_rawset(L, -3);

    lua_pushstring(L, "strikethrough");
    lua_pushboolean(L, @as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_STRIKETHROUGH);
    lua_rawset(L, -3);

    lua_pushstring(L, "break");
    lua_pushboolean(L, @as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_SHAPE_BREAK);
    lua_rawset(L, -3);

    lua_pushstring(L, "border_left");
    lua_pushboolean(L, @as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_BORDER_LEFT);
    lua_rawset(L, -3);

    lua_pushstring(L, "border_right");
    lua_pushboolean(L, @as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_BORDER_RIGHT);
    lua_rawset(L, -3);

    lua_pushstring(L, "border_down");
    lua_pushboolean(L, @as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_BORDER_DOWN);
    lua_rawset(L, -3);

    lua_pushstring(L, "border_top");
    lua_pushboolean(L, @as(c_int, @bitCast(@as(c_uint, attr.unnamed_2.aflags))) & TUI_ATTR_BORDER_TOP);
    lua_rawset(L, -3);

    lua_pushstring(L, "id");
    lua_pushnumber(L, @floatFromInt(attr.custom_id));
    lua_rawset(L, -3);
}
pub fn free_history(m: [*c]struct_widget_meta) callconv(.c) void {
    if (m.*.unnamed_0.readline.history == null) return;
    {
        var i: usize = 0;
        while (i < m.*.unnamed_0.readline.history_sz) : (i +%= 1) {
            free(@as(?*anyopaque, @ptrCast(m.*.unnamed_0.readline.history[i])));
        }
    }
    free(@as(?*anyopaque, @ptrCast(m.*.unnamed_0.readline.history)));
    m.*.unnamed_0.readline.history = null;
}
pub fn free_suggest(m: [*c]struct_widget_meta) callconv(.c) void {
    if (m.*.unnamed_0.readline.suggest == null) return;
    {
        var i: usize = 0;
        while (i < m.*.unnamed_0.readline.suggest_sz) : (i +%= 1) {
            free(@as(?*anyopaque, @ptrCast(m.*.unnamed_0.readline.suggest[i])));
        }
    }
    free(@as(?*anyopaque, @ptrCast(m.*.unnamed_0.readline.suggest)));
    m.*.unnamed_0.readline.suggest = null;
}
pub fn revert(L: ?*lua_State, M: [*c]struct_tui_lmeta) callconv(.c) void {
    switch (M.*.widget_mode) {
        0 => {},
        1 => {
            _ = arcan_tui_listwnd_release(M.*.unnamed_0.tui);
            if (M.*.widget_meta != null) {
                free(@as(?*anyopaque, @ptrCast(M.*.widget_meta.?.*.unnamed_0.listview.ents)));
                M.*.widget_meta.?.*.unnamed_0.listview.ents = null;
            }
        },
        2 => {
            arcan_tui_bufferwnd_release(M.*.unnamed_0.tui);
            if (M.*.widget_meta != null) {
                free(@as(?*anyopaque, @ptrCast(M.*.widget_meta.?.*.unnamed_0.bufferview.buf)));
                M.*.widget_meta.?.*.unnamed_0.bufferview.buf = null;
            }
        },
        3 => {
            arcan_tui_readline_release(M.*.unnamed_0.tui);
            if (M.*.widget_meta != null) {
                const wm: [*c]struct_widget_meta = M.*.widget_meta;
                M.*.widget_meta.?.*.unnamed_0.readline.verify = tui_lunref(L, wm.*.unnamed_0.readline.verify, "revert-readline-flt", 6);
                M.*.widget_meta.?.*.unnamed_0.readline.filter = tui_lunref(L, wm.*.unnamed_0.readline.filter, "revert-readline-ver", 6);
                M.*.widget_meta.?.*.unnamed_0.readline.item = tui_lunref(L, wm.*.unnamed_0.readline.item, "revert-readline-itm", 6);
                free_history(wm);
                free_suggest(wm);
            }
        },
        4 => {},
        else => {},
    }
    M.*.widget_mode = c.TWND_NORMAL;
    if (M.*.widget_meta != null) {
        M.*.widget_meta.?.*.parent = null;
        M.*.widget_meta = null;
    }
    M.*.widget_closure = tui_lunref(L, M.*.widget_closure, "revert_full_closure", 6);
    M.*.widget_state = tui_lunref(L, M.*.widget_state, "revert_full_state", 7);
}
pub fn callback_revert(L: ?*lua_State, M: [*c]struct_tui_lmeta, _: [*c]const u8, n: c_int, r: c_int) callconv(.c) void {
    const closure: isize = M.*.widget_closure;
    const state: isize = M.*.widget_state;
    M.*.widget_closure = @as(isize, @bitCast(@as(isize, -2)));
    M.*.widget_state = @as(isize, @bitCast(@as(isize, -2)));
    revert(L, M);
    while (true) {
        if (0 != lua_pcall(L, n, r, 0)) {
            _ = luaL_error(L, lua_tolstring(L, -1, null));
        }
        if (!false) break;
    }
    _ = tui_lunref(L, closure, "revert-callback-closure", 6);
    _ = tui_lunref(L, state, "revert-callback-state", 7);
}
pub fn apply_table(L: ?*lua_State, ind: c_int, attr: [*c]struct_tui_screen_attr) callconv(.c) void {
    attr.*.unnamed_2.aflags = 0;
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_BOLD * @as(c_int, @intFromBool(intblbool(L, ind, "bold")))))));
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_UNDERLINE * @as(c_int, @intFromBool(intblbool(L, ind, "underline")))))));
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_ITALIC * @as(c_int, @intFromBool(intblbool(L, ind, "italic")))))));
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_INVERSE * @as(c_int, @intFromBool(intblbool(L, ind, "inverse")))))));
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_UNDERLINE * @as(c_int, @intFromBool(intblbool(L, ind, "underline")))))));
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_UNDERLINE_ALT * @as(c_int, @intFromBool(intblbool(L, ind, "underline_alt")))))));
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_PROTECT * @as(c_int, @intFromBool(intblbool(L, ind, "protect")))))));
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_BLINK * @as(c_int, @intFromBool(intblbool(L, ind, "blink")))))));
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_STRIKETHROUGH * @as(c_int, @intFromBool(intblbool(L, ind, "strikethrough")))))));
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_SHAPE_BREAK * @as(c_int, @intFromBool(intblbool(L, ind, "break")))))));
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_BORDER_LEFT * @as(c_int, @intFromBool(intblbool(L, ind, "border_left")))))));
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_BORDER_RIGHT * @as(c_int, @intFromBool(intblbool(L, ind, "border_right")))))));
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_BORDER_TOP * @as(c_int, @intFromBool(intblbool(L, ind, "border_top")))))));
    attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_BORDER_DOWN * @as(c_int, @intFromBool(intblbool(L, ind, "border_down")))))));
    var ok: bool = undefined;
    attr.*.custom_id = @as(u8, @bitCast(@as(i8, @truncate(intblint(L, ind, "id", &ok)))));
    attr.*.unnamed_0.unnamed_0.fg = blk: {
        const tmp = blk_1: {
            const tmp_2: u8 = 0;
            attr.*.unnamed_0.unnamed_0.fr = tmp_2;
            break :blk_1 tmp_2;
        };
        attr.*.unnamed_0.unnamed_0.fb = tmp;
        break :blk tmp;
    };
    attr.*.unnamed_1.unnamed_0.bg = blk: {
        const tmp = blk_1: {
            const tmp_2: u8 = 0;
            attr.*.unnamed_1.unnamed_0.br = tmp_2;
            break :blk_1 tmp_2;
        };
        attr.*.unnamed_1.unnamed_0.bb = tmp;
        break :blk tmp;
    };
    const val: c_int = intblint(L, ind, "fc", &ok);
    if ((-1 != val) and (@as(c_int, @intFromBool(ok)) != 0)) {
        attr.*.unnamed_2.aflags |= @as(u16, @bitCast(@as(c_short, @truncate(TUI_ATTR_COLOR_INDEXED))));
        attr.*.unnamed_0.fc[0] = @as(u8, @bitCast(@as(i8, @truncate(val))));
        attr.*.unnamed_1.bc[0] = @as(u8, @bitCast(@as(i8, @truncate(intblint(L, ind, "bc", &ok)))));
    } else {
        _ = intblint(L, ind, "fr", &ok);
        if (ok) {
            attr.*.unnamed_0.unnamed_0.fr = @as(u8, @bitCast(@as(i8, @truncate(intblint(L, ind, "fr", &ok)))));
            attr.*.unnamed_0.unnamed_0.fg = @as(u8, @bitCast(@as(i8, @truncate(intblint(L, ind, "fg", &ok)))));
            attr.*.unnamed_0.unnamed_0.fb = @as(u8, @bitCast(@as(i8, @truncate(intblint(L, ind, "fb", &ok)))));
        } else {
            attr.*.unnamed_0.unnamed_0.fr = blk: {
                const tmp = blk_1: {
                    const tmp_2 = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 196)))));
                    attr.*.unnamed_0.unnamed_0.fb = tmp_2;
                    break :blk_1 tmp_2;
                };
                attr.*.unnamed_0.unnamed_0.fg = tmp;
                break :blk tmp;
            };
        }
        _ = intblint(L, ind, "br", &ok);
        if (ok) {
            attr.*.unnamed_1.unnamed_0.br = @as(u8, @bitCast(@as(i8, @truncate(intblint(L, ind, "br", &ok)))));
            attr.*.unnamed_1.unnamed_0.bg = @as(u8, @bitCast(@as(i8, @truncate(intblint(L, ind, "bg", &ok)))));
            attr.*.unnamed_1.unnamed_0.bb = @as(u8, @bitCast(@as(i8, @truncate(intblint(L, ind, "bb", &ok)))));
        }
    }
}
pub fn tui_attr(L: ?*lua_State) callconv(.c) c_int {
    var attr: struct_tui_screen_attr = struct_tui_screen_attr{
        .unnamed_0 = .{
            .unnamed_0 = .{
                .fr = 128,
                .fg = 128,
                .fb = 128,
            },
        },
        .unnamed_1 = zeroAttrBc(),
        .unnamed_2 = zeroAttrFlags(),
        .custom_id = std.mem.zeroes(u8),
    };
    var ci: c_int = 1;
    if (lua_type(L, ci) == 7) {
        const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, blk: {
            const ref = &ci;
            const tmp = ref.*;
            ref.* += 1;
            break :blk tmp;
        }, "Arcan TUI")));
        arcan_tui_get_color(ib.*.unnamed_0.tui, TUI_COL_PRIMARY, @ptrCast(@alignCast(&attr.unnamed_0.fc[0])));
        arcan_tui_get_color(ib.*.unnamed_0.tui, TUI_COL_BG, @ptrCast(@alignCast(&attr.unnamed_1.bc[0])));
        ci += 1;
    }
    if (lua_type(L, ci) == 5) {
        apply_table(L, ci, &attr);
    }
    add_attr_tbl(L, attr);
    return 1;
}
pub fn defattr(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    if (lua_type(L, 2) == 5) {
        var rattr: struct_tui_screen_attr = struct_tui_screen_attr{
            .unnamed_0 = zeroAttrFc(),
            .unnamed_1 = zeroAttrBc(),
            .unnamed_2 = zeroAttrFlags(),
            .custom_id = std.mem.zeroes(u8),
        };
        apply_table(L, 2, &rattr);
        add_attr_tbl(L, arcan_tui_defattr(ib.*.unnamed_0.tui, &rattr));
    } else {
        add_attr_tbl(L, arcan_tui_defcattr(ib.*.unnamed_0.tui, TUI_COL_TEXT));
    }
    return 1;
}
pub fn getxy(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    const x: usize = @bitCast(luaL_checkinteger(L, 2));
    const y: usize = @bitCast(luaL_checkinteger(L, 3));
    const front: bool = luaL_optbnumber(L, 4, @as(lua_Number, @floatFromInt(@as(c_int, 1))));
    const cell: struct_tui_cell = arcan_tui_getxy(ib.*.unnamed_0.tui, x, y, front);
    var str: [4]u8 = undefined;
    const str_sz: usize = arcan_tui_ucs4utf8(cell.ch, @ptrCast(@alignCast(&str[0])));
    lua_pushlstring(L, @ptrCast(@alignCast(&str[0])), str_sz);
    add_attr_tbl(L, cell.attr);
    return 2;
}
pub fn screen_dimensions(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    var rows: usize = undefined;
    var cols: usize = undefined;
    arcan_tui_dimensions(ib.*.unnamed_0.tui, &rows, &cols);
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(cols)));
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(rows)));
    return 2;
}
pub fn erase_region(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    const x1: usize = @bitCast(luaL_checkinteger(L, 2));
    const y1: usize = @bitCast(luaL_checkinteger(L, 3));
    const x2: usize = @bitCast(luaL_checkinteger(L, 4));
    const y2: usize = @bitCast(luaL_checkinteger(L, 5));
    const prot: bool = luaL_optbnumber(L, 6, @as(lua_Number, @floatFromInt(@as(c_int, 0))));
    var rows: usize = undefined;
    var cols: usize = undefined;
    arcan_tui_dimensions(ib.*.unnamed_0.tui, &rows, &cols);
    if ((((x1 < x2) and (y1 < y2)) and (x1 < cols)) and (y1 < rows)) {
        arcan_tui_erase_region(ib.*.unnamed_0.tui, x1, y1, x2, y2, prot);
    }
    return 0;
}
pub fn erase_screen(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    const prot: bool = luaL_optbnumber(L, 2, @as(lua_Number, @floatFromInt(@as(c_int, 0))));
    arcan_tui_erase_screen(ib.*.unnamed_0.tui, prot);
    return 0;
}
pub fn cursor_to(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    const x: c_int = @as(c_int, @truncate(luaL_checkinteger(L, 2)));
    const y: c_int = @as(c_int, @truncate(luaL_checkinteger(L, 3)));
    var fl: c_int = 0;
    const style: [*c]const u8 = luaL_optlstring(L, 4, null, null);
    if (style != null) {
        if (strcmp(style, "block") == 0) {
            fl = c.CURSOR_BLOCK;
        } else if (strcmp(style, "bar") == 0) {
            fl = c.CURSOR_BAR;
        } else if (strcmp(style, "underline") == 0) {
            fl = c.CURSOR_UNDER;
        } else if (strcmp(style, "frame") == 0) {
            fl = c.CURSOR_HOLLOW;
        }
    }
    var col: [*c]u8 = null;
    var colv: [3]u8 = [3]u8{ 0, 0, 0 };
    if (((lua_type(L, 5) == 3) and (lua_type(L, 6) == 3)) and (lua_type(L, 7) == 3)) {
        colv[0] = @intFromFloat(lua_tonumber(L, 5));
        colv[1] = @intFromFloat(lua_tonumber(L, 6));
        colv[2] = @intFromFloat(lua_tonumber(L, 7));
        col = @ptrCast(@alignCast(&colv[0]));
        if (luaL_optnumber(L, 8, @as(lua_Number, @floatFromInt(@as(c_int, 0)))) != 0) {
            fl |= c.CURSOR_BLINK;
        }
    } else if (luaL_optnumber(L, 5, @as(lua_Number, @floatFromInt(@as(c_int, 0)))) != 0) {
        fl |= c.CURSOR_BLINK;
    }
    var rows: usize = undefined;
    var cols: usize = undefined;
    arcan_tui_dimensions(ib.*.unnamed_0.tui, &rows, &cols);
    if ((((x >= 0) and (y >= 0)) and (@as(usize, @bitCast(@as(isize, x))) < cols)) and (@as(usize, @bitCast(@as(isize, y))) < rows)) {
        arcan_tui_move_to(ib.*.unnamed_0.tui, @as(usize, @bitCast(@as(isize, x))), @as(usize, @bitCast(@as(isize, y))));
    }
    if ((col != null) or (fl != 0)) {
        _ = arcan_tui_cursor_style(ib.*.unnamed_0.tui, fl, null);
    }
    return 0;
}
pub fn synch_wd(md: [*c]struct_tui_lmeta) callconv(.c) void {
    if (!(md.*.cwd != null)) {
        md.*.cwd_sz = @as(usize, @bitCast(@as(isize, @as(c_int, 4096) + 1)));
        md.*.cwd = @ptrCast(@alignCast(malloc(md.*.cwd_sz)));
        if (!(md.*.cwd != null)) {
            return;
        }
    }
    while (@as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(usize, 0)))))) == getcwd(@ptrCast(@alignCast(md.*.cwd)), md.*.cwd_sz)) {
        while (true) {
            switch (__errno_location().*) {
                36 => {
                    free(@as(?*anyopaque, @ptrCast(md.*.cwd)));
                    md.*.cwd_sz *%= @as(usize, @bitCast(@as(isize, @as(c_int, 2))));
                    md.*.cwd = @ptrCast(@alignCast(malloc(md.*.cwd_sz)));
                    if (!(md.*.cwd != null)) return;
                    break;
                },
                13 => {
                    _ = snprintf(@ptrCast(@alignCast(md.*.cwd)), md.*.cwd_sz, "[access denied]");
                    break;
                },
                22 => {
                    _ = snprintf(@ptrCast(@alignCast(md.*.cwd)), md.*.cwd_sz, "[invalid]");
                    break;
                },
                else => return,
            }
            break;
        }
    }
}
pub fn tui_wndhint(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    var tbli: c_int = 2;
    var parent: [*c]struct_tui_lmeta = null;
    if (lua_type(L, 2) == 7) {
        parent = @ptrCast(@alignCast(luaL_checkudata(L, 2, "Arcan TUI")));
        tbli = 3;
    }
    var cons: struct_tui_constraints = struct_tui_constraints{
        .anch_row = 0,
        .anch_col = 0,
        .max_rows = 0,
        .max_cols = 0,
        .min_rows = 0,
        .min_cols = 0,
        .hide = 0,
        .embed = ib.*.embed,
    };
    if (lua_type(L, tbli) == 5) {
        cons = get_wndhint(ib, L, tbli);
    }
    arcan_tui_wndhint(ib.*.unnamed_0.tui, if (parent != null) parent.*.unnamed_0.tui else null, cons);
    return 0;
}
pub fn tui_mktemp(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    const base: [*c]const u8 = luaL_optlstring(L, 2, "atuiXXXXXX", null);
    var temp: [*c]u8 = strdup(base);
    const fd: c_int = mkstemp(temp);
    if (-1 == fd) {
        free(@as(?*anyopaque, @ptrCast(temp)));
        lua_pushboolean(L, 0);
        lua_pushstring(L, strerror(__errno_location().*));
        return 2;
    }
    _ = alt_nbio_import(L, fd, @as(mode_t, @bitCast(@as(c_int, 2))), null, &temp);
    alt_nbio_nonblock_cloexec(fd, true);
    lua_pushstring(L, temp);
    return 2;
}
pub fn tui_mkdtemp(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    const base: [*c]const u8 = luaL_optlstring(L, 2, "atuidXXXXXX", null);
    const len: usize = strlen(base);
    if (((((((len <= 6) or (base[len -% 1] != 'X')) or (base[len -% 2] != 'X')) or (base[len -% 3] != 'X')) or (base[len -% 4] != 'X')) or (base[len -% 5] != 'X')) or (base[len -% 6] != 'X')) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "template error, expecting trailing XXXXXX");
        return 2;
    }
    var work: [*c]u8 = strdup(base);
    var tries: usize = 10;
    while ((work != null) and ((blk: {
        const ref = &tries;
        const tmp = ref.*;
        ref.* -%= 1;
        break :blk tmp;
    }) > 0)) {
        const union_unnamed_117 = extern union {
            rv: u32,
            rng: [4]u8,
        };
        var rval: union_unnamed_117 = undefined;
        arcan_random(@ptrCast(@alignCast(&rval.rv)), 4);
        {
            var i: usize = 0;
            while (i < 4) : (i +%= 1) {
                work[(len -% 1) -% i] = @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, @bitCast(@as(c_uint, @as(u8, @bitCast(@as(i8, @truncate(@import("std").zig.c_translation.signedRemainder(@as(c_int, @bitCast(@as(c_uint, rval.rng[i]))), 24)))))))) + 'a'))));
            }
        }
        const status: c_int = mkdirat(ib.*.cwd_fd, work, @as(mode_t, @bitCast(@as(c_int, 448))));
        if (0 == status) {
            lua_pushstring(L, work);
            free(@as(?*anyopaque, @ptrCast(work)));
            return 1;
        }
        if ((-1 == status) and (__errno_location().* != 17)) break;
    }
    free(@as(?*anyopaque, @ptrCast(work)));
    lua_pushboolean(L, 0);
    lua_pushstring(L, strerror(__errno_location().*));
    return 2;
}
pub fn tui_chdir(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    var status: c_int = 0;
    if ((-1 == ib.*.cwd_fd) and (-1 == fchdir(ib.*.cwd_fd))) {
        lua_pushstring(L, "[unknown]");
        lua_pushstring(L, "couldn't open .");
        return 2;
    }
    const wd: [*c]const u8 = luaL_optlstring(L, 2, null, null);
    if (wd != null) {
        status = chdir(wd);
    }
    synch_wd(ib);
    lua_pushstring(L, if (ib.*.cwd != null) @as([*c]const u8, @ptrCast(@alignCast(ib.*.cwd))) else "[unknown]");
    if (-1 == status) {
        lua_pushstring(L, strerror(__errno_location().*));
        return 2;
    } else {
        if (-1 != ib.*.cwd_fd) {
            _ = close(ib.*.cwd_fd);
        }
        ib.*.cwd_fd = open(".", @as(c_int, 0) | @as(c_int, 16384));
    }
    return 1;
}
pub fn tui_local(L: ?*lua_State) callconv(.c) c_int {
    var ib: [*c]struct_tui_lmeta = null;
    var ci: usize = 1;
    if (lua_type(L, @as(c_int, @intCast(ci))) == 7) {
        ib = @ptrCast(@alignCast(luaL_checkudata(L, @as(c_int, @intCast(blk: {
            const ref = &ci;
            const tmp = ref.*;
            ref.* +%= 1;
            break :blk tmp;
        })), "Arcan TUI")));
        ci +%= 1;
    }
    var w: usize = 80;
    var h: usize = 25;
    if (lua_type(L, @as(c_int, @intCast(ci))) == 3) {
        w = @intFromFloat(lua_tonumber(L, @as(c_int, @intCast(ci))));
        h = @intFromFloat(luaL_optnumber(L, @as(c_int, @intCast(ci +% 1)), @as(lua_Number, @floatFromInt(@as(c_int, 25)))));
    }
    const res: ?*struct_tui_context = ltui_inherit(L, null, ib);
    if (!(res != null)) return 0;
    arcan_tui_wndhint(res, if (ib != null) ib.*.unnamed_0.tui else null, struct_tui_constraints{
        .anch_row = 0,
        .anch_col = 0,
        .max_rows = @as(c_int, @intCast(h)),
        .max_cols = @as(c_int, @intCast(w)),
        .min_rows = 0,
        .min_cols = 0,
        .hide = 0,
        .embed = 0,
    });
    return 1;
}
pub fn tui_open(L: ?*lua_State) callconv(.c) c_int {
    const title: [*c]const u8 = luaL_checklstring(L, 1, null);
    const ident: [*c]const u8 = luaL_checklstring(L, 2, null);
    const conn: [*c]arcan_tui_conn = arcan_tui_open_display(title, ident);
    return if (ltui_inherit(L, conn, null) != null) @as(c_int, 1) else @as(c_int, 0);
}
pub fn compact(ib: [*c]struct_tui_lmeta) callconv(.c) void {
    {
        var i: usize = 1;
        while (i < (ib.*.n_subs +% 1)) {
            if (ib.*.unnamed_0.subs[i] != null) {
                i +%= 1;
                continue;
            }
            _ = memmove(@as(?*anyopaque, @ptrCast(&ib.*.submeta[i])), @as(?*const anyopaque, @ptrCast(&ib.*.submeta[i +% 1])), @sizeOf(?*anyopaque) *% (64 -% i));
            _ = memmove(@as(?*anyopaque, @ptrCast(&ib.*.unnamed_0.subs[i])), @as(?*const anyopaque, @ptrCast(&ib.*.unnamed_0.subs[i +% 1])), @sizeOf(?*anyopaque) *% (64 -% i));
            ib.*.n_subs -%= 1;
        }
    }
}
pub fn tuiclose(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    revert(L, ib);
    arcan_tui_destroy(ib.*.unnamed_0.tui, luaL_optlstring(L, 2, null, null));
    ib.*.unnamed_0.tui = null;
    ib.*.tui_state = tui_lunref(L, ib.*.tui_state, "close", 7);
    if (ib.*.parent != null) {
        {
            var i: usize = 1;
            while (i < (ib.*.parent.*.n_subs +% 1)) : (i +%= 1) {
                if (ib.*.parent.*.submeta[i] == ib) {
                    ib.*.parent.*.submeta[i] = null;
                    ib.*.parent.*.unnamed_0.subs[i] = null;
                    break;
                }
            }
        }
        compact(ib.*.parent);
    }
    if (ib.*.href != @as(isize, @bitCast(@as(isize, -2)))) {
        lua_rawgeti(L, -1001000, @as(c_int, @truncate(ib.*.href)));
        lua_getfield(L, -1, "destroy");
        if (lua_type(L, -1) != 6) {
            lua_settop(L, -2 - 1);
            return 0;
        }
        lua_pushvalue(L, -3);
        while (true) {
            if (0 != lua_pcall(L, 1, 0, 0)) {
                _ = luaL_error(L, lua_tolstring(L, -1, null));
            }
            if (!false) break;
        }
    }
    return 0;
}
pub fn collect(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null)) return 0;
    if (ib.*.unnamed_0.tui != null) {
        arcan_tui_destroy(ib.*.unnamed_0.tui, null);
        ib.*.unnamed_0.tui = null;
    }
    ib.*.href = tui_lunref(L, ib.*.href, "tui-collect", 5);
    free(@as(?*anyopaque, @ptrCast(ib.*.cwd)));
    ib.*.cwd = null;
    if (-1 != ib.*.cwd_fd) {
        _ = close(ib.*.cwd_fd);
        ib.*.cwd_fd = -1;
    }
    return 0;
}
pub fn settbl(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    ib.*.href = tui_lunref(L, ib.*.href, "tui-settable", 5);
    ib.*.href = tui_lref(L, 2, "settbl", "1735", 5);
    return 0;
}
pub fn setident(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    const ident: [*c]const u8 = luaL_optlstring(L, 2, "", null);
    arcan_tui_ident(ib.*.unnamed_0.tui, ident);
    return 0;
}
pub fn setcopy(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    const pstr: [*c]const u8 = luaL_optlstring(L, 2, "", null);
    lua_pushboolean(L, @intFromBool(arcan_tui_copy(ib.*.unnamed_0.tui, pstr)));
    return 1;
}
pub fn reqwnd(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    var meta: struct_tui_subwnd_req = struct_tui_subwnd_req{
        .hint = 0,
    };
    // rows/cols tracking for wndhint after subwindow creation
    var req_rows: usize = 0;
    var req_cols: usize = 0;
    const @"type": [*c]const u8 = luaL_optlstring(L, 2, "tui", null);
    var ind: c_int = undefined;
    var ref: isize = @as(isize, @bitCast(@as(isize, -2)));
    if ((blk: {
        ind = 2;
        break :blk lua_type(L, 2) == 6;
    }) or (blk: {
        ind = 3;
        break :blk lua_type(L, 3) == 6;
    })) {
        ref = tui_lref(L, ind, "reqwnd", "1771", 6);
    } else {
        _ = luaL_error(L, "new_window(type, >closure<, ...) closure missing");
    }
    var hintstr: [*c]const u8 = null;
    while ((blk: {
        const ref_1 = &ind;
        ref_1.* += 1;
        break :blk ref_1.*;
    }) <= lua_gettop(L)) {
        if (lua_type(L, ind) == 3) {
            if (!(req_rows != 0)) {
                req_rows = @intFromFloat(lua_tonumber(L, ind));
            } else if (!(req_cols != 0)) {
                req_cols = @intFromFloat(lua_tonumber(L, ind));
            } else {
                _ = luaL_error(L, "new_window(type, closure, >w, h<, [hint]) number argument overflow ");
            }
        } else if (lua_type(L, ind) == 4) {
            if (hintstr != null) {
                _ = luaL_error(L, "new_window(type, closure, [w, h], hint) hint argument overflow");
            }
            hintstr = lua_tolstring(L, ind, null);
        } else {
            _ = luaL_error(L, "new_window(type, closure, >...<) unexpected argument type");
        }
    }
    var embed_fl: c_int = 0;
    if (hintstr != null) {
        if (strcmp(hintstr, "split") == 0) {
            meta.hint = c.TUIWND_SPLIT_NONE;
        } else if (strcmp(hintstr, "split-l") == 0) {
            meta.hint = c.TUIWND_SPLIT_LEFT;
        } else if (strcmp(hintstr, "split-r") == 0) {
            meta.hint = c.TUIWND_SPLIT_RIGHT;
        } else if (strcmp(hintstr, "split-t") == 0) {
            meta.hint = c.TUIWND_SPLIT_TOP;
        } else if (strcmp(hintstr, "split-d") == 0) {
            meta.hint = c.TUIWND_SPLIT_DOWN;
        } else if (strcmp(hintstr, "join-l") == 0) {
            meta.hint = c.TUIWND_JOIN_LEFT;
        } else if (strcmp(hintstr, "join-r") == 0) {
            meta.hint = c.TUIWND_JOIN_RIGHT;
        } else if (strcmp(hintstr, "join-t") == 0) {
            meta.hint = c.TUIWND_JOIN_TOP;
        } else if (strcmp(hintstr, "join-d") == 0) {
            meta.hint = c.TUIWND_JOIN_DOWN;
        } else if (strcmp(hintstr, "tab") == 0) {
            meta.hint = c.TUIWND_TAB;
        } else if (strcmp(hintstr, "embed") == 0) {
            embed_fl = 1;
            meta.hint = c.TUIWND_EMBED;
        } else if (strcmp(hintstr, "embed-scale") == 0) {
            meta.hint = c.TUIWND_EMBED;
            embed_fl = 2;
        } else if (strcmp(hintstr, "embed-sync") == 0) {
            meta.hint = c.TUIWND_EMBED;
            embed_fl = 3;
        } else if (strcmp(hintstr, "swallow") == 0) {
            meta.hint = c.TUIWND_SWALLOW;
        } else {
            _ = luaL_error(L, "new_window(..., >hint<) unknown hint (split-(tldr), join-(tldr), tab or embed");
        }
    }
    var tui_type: c_int = TUI_WND_TUI;
    if (strcmp(@"type", "popup") == 0) {
        tui_type = TUI_WND_POPUP;
    } else if (strcmp(@"type", "dock") == 0) {
        tui_type = TUI_WND_DOCKICON;
    } else if (strcmp(@"type", "handover") == 0) {
        tui_type = TUI_WND_HANDOVER;
    } else if (strcmp(@"type", "accessibility") == 0) {
        tui_type = TUI_WND_ACCESSIBILITY;
    } else if (strcmp(@"type", "tui") == 0) {} else {
        _ = luaL_error(L, "new_window(>type<, ...) unsupported type (popup, handover, dock, tui, accessibility)");
    }
    if (@as(c_int, @bitCast(@as(c_uint, ib.*.pending_mask))) == 255) {
        lua_pushboolean(L, 0);
        return 1;
    }
    const bitind: c_int = ffs(~@as(c_int, @bitCast(@as(c_uint, ib.*.pending_mask)))) - 1;
    ib.*.pending[@intCast(bitind)].id = ref;
    ib.*.pending[@intCast(bitind)].hint = meta.hint;
    ib.*.pending[@intCast(bitind)].embed = embed_fl;
    ib.*.pending_mask |= @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 1) << @intCast(bitind)))));
    lua_pushboolean(L, 1);
    arcan_tui_request_subwnd_ext(ib.*.unnamed_0.tui, tui_type, meta.hint, @as(u32, @bitCast(bitind)) ^ req_cookie, 0);
    return 1;
}
pub fn alive(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    lua_pushboolean(L, @intFromBool(ib.*.unnamed_0.tui != @as(?*struct_tui_context, @ptrCast(@as(?*anyopaque, @ptrFromInt(@as(usize, 0)))))));
    return 1;
}
pub fn run_sub_bitmap(ib: [*c]struct_tui_lmeta, map: c_int) callconv(.c) void {
    var map_ = map;
    const count: c_int = 0;
    while ((ffs(map_) != 0) and (count < 32)) {
        const pos: c_int = ffs(map_) - 1;
        map_ &= ~(@as(c_int, 1) << @intCast(pos));
        if (pos != 0) {
            ib.*.unnamed_0.subs[@intCast(pos)] = null;
            ib.*.submeta[@intCast(pos)] = null;
        }
    }
    compact(ib);
}
pub fn process_widget(L: ?*lua_State, T: [*c]struct_tui_lmeta) callconv(.c) void {
    if (!(T.*.widget_mode != 0)) return;
    while (true) {
        switch (T.*.widget_mode) {
            1 => {
                {
                    var ent: [*c]struct_tui_list_entry = null;
                    const ls_status = arcan_tui_listwnd_status(T.*.unnamed_0.tui);
                    _ = &ent;
                    if (ls_status != 0) {
                        lua_rawgeti(L, -1001000, @as(c_int, @truncate(T.*.widget_closure)));
                        if (ent != null) {
                            lua_pushnumber(L, @as(lua_Number, @floatFromInt(ent.*.tag)));
                        } else {
                            lua_pushnil(L);
                        }
                        callback_revert(L, T, "listwnd_ok", 1, 0);
                    }
                }
                break;
            },
            2 => {
                {
                    const sc: c_int = arcan_tui_bufferwnd_status(T.*.unnamed_0.tui);
                    lua_rawgeti(L, -1001000, @as(c_int, @truncate(T.*.widget_closure)));
                    lua_rawgeti(L, -1001000, @as(c_int, @truncate(T.*.widget_state)));
                    if (sc == 1) return;
                    if (sc == 0) {
                        lua_pushlstring(L, @ptrCast(@alignCast(T.*.widget_meta.?.*.unnamed_0.bufferview.buf)), T.*.widget_meta.?.*.unnamed_0.bufferview.sz);
                    } else if (sc == -1) {
                        lua_pushnil(L);
                    }
                    callback_revert(L, T, "bufferview_ok", 2, 0);
                }
                break;
            },
            3 => {
                {
                    var buf: [*c]u8 = undefined;
                    const sc: c_int = arcan_tui_readline_finished(T.*.unnamed_0.tui, &buf);
                    if (sc != 0) {
                        lua_rawgeti(L, -1001000, @as(c_int, @truncate(T.*.widget_closure)));
                        lua_rawgeti(L, -1001000, @as(c_int, @truncate(T.*.widget_state)));
                        if (buf != null) {
                            lua_pushstring(L, buf);
                        } else {
                            lua_pushnil(L);
                        }
                        callback_revert(L, T, "readline_ok", 2, 0);
                    }
                }
                break;
            },
            else => break,
        }
        break;
    }
}
// src/shmif/tui/lua/tui_lua.c:1982:1: warning: TODO implement translation of stmt class LabelStmtClass

pub fn process(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    const timeout: c_int = @as(c_int, @intFromFloat(luaL_optnumber(L, 2, @as(lua_Number, @floatFromInt(@as(c_int, -1))))));
    var res: c.struct_tui_process_res = undefined;

    // repoll loop (goto repoll in C)
    while (true) {
        res = c.arcan_tui_process(
            @ptrCast(&ib.*.unnamed_0), @as(c_int, @intCast(ib.*.n_subs + 1)), @as(?*c_int, @ptrCast(&nbio_jobs.fdin)), nbio_jobs.fdin_used, timeout,
        );

        if (res.errc != c.TUI_ERRC_BAD_CTX) break;

        if (ib.*.n_subs != 0) {
            run_sub_bitmap(ib, @as(c_int, @bitCast(res.bad)));
        }
        if ((1 & res.bad) != 0) {
            lua_pushboolean(L, 0);
            lua_pushstring(L, "primary context terminated");
            return 2;
        }
        // continue = goto repoll
    }

    if ((nbio_jobs.fdin_used != 0) and (res.bad != 0 or res.ok)) {
        var set: [64]usize = std.mem.zeroes([64]usize);
        var count: usize = 0;
        count += nbio_queue_bitmap(&set, @as(c_int, @intFromBool(res.ok)));
        count += nbio_queue_bitmap(@ptrCast(&set[count]), @as(c_int, res.bad));
        var si: usize = 0;
        while (si < count) : (si += 1) {
            alt_nbio_data_in(L, @as(isize, @bitCast(set[si])));
        }
    }

    nbio_run_outbound(L);

    {
        var si: usize = 0;
        while (si < ib.*.n_subs + 1) : (si += 1) {
            var out: c.struct_tui_cbcfg = undefined;
            if (c.arcan_tui_update_handlers(ib.*.unnamed_0.subs[si], null, &out, @sizeOf(c.struct_tui_cbcfg))) {
                process_widget(L, ib.*.submeta[si]);
            }
        }
    }

    if (res.errc == c.TUI_ERRC_OK or res.errc == c.TUI_ERRC_BAD_FD) {
        lua_pushboolean(L, 1);
        return 1;
    }

    lua_pushboolean(L, 0);
    switch (res.errc) {
        c.TUI_ERRC_BAD_ARG => lua_pushlstring(L, "bad argument", 12),
        c.TUI_ERRC_BAD_CTX => lua_pushlstring(L, "broken context", 14),
        else => lua_pushlstring(L, "unexpected return", 17),
    }
    return 2;
}
pub fn getcursor(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    var x: usize = undefined;
    var y: usize = undefined;
    arcan_tui_cursorpos(ib.*.unnamed_0.tui, &x, &y);
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(x)));
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(y)));
    return 2;
}
pub fn write_border(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    const x1: usize = @bitCast(luaL_checkinteger(L, 2));
    const y1: usize = @bitCast(luaL_checkinteger(L, 3));
    const x2: usize = @bitCast(luaL_checkinteger(L, 4));
    const y2: usize = @bitCast(luaL_checkinteger(L, 5));
    const fl: c_int = @as(c_int, @truncate(luaL_optinteger(L, 7, @as(lua_Integer, @bitCast(@as(isize, @as(c_int, 0)))))));
    var mattr: struct_tui_screen_attr = arcan_tui_defattr(ib.*.unnamed_0.tui, null);
    if (lua_type(L, 6) == 5) {
        apply_table(L, 6, &mattr);
    }
    arcan_tui_write_border(ib.*.unnamed_0.tui, mattr, x1, y1, x2, y2, fl);
    return 0;
}
pub fn write_tou8(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    var attr: [*c]struct_tui_screen_attr = null;
    var mattr: struct_tui_screen_attr = std.mem.zeroes(struct_tui_screen_attr);

    const x: usize = @bitCast(luaL_checkinteger(L, 2));
    const y: usize = @bitCast(luaL_checkinteger(L, 3));
    var ox: usize = undefined;
    var oy: usize = undefined;
    arcan_tui_cursorpos(ib.*.unnamed_0.tui, &ox, &oy);

    // overloaded form: if arg 4 is a table, just swap attribute
    if (lua_type(L, 4) == 5) {
        apply_table(L, 4, &mattr);
        arcan_tui_writeattr_at(ib.*.unnamed_0.tui, &mattr, x, y);
        lua_pushboolean(L, 1);
    } else {
        var len: usize = undefined;
        const buf: [*c]const u8 = luaL_checklstring(L, 4, &len);
        if (lua_type(L, 5) == 5) {
            apply_table(L, 5, &mattr);
            attr = &mattr;
        }
        arcan_tui_move_to(ib.*.unnamed_0.tui, x, y);
        lua_pushboolean(L, @intFromBool(arcan_tui_writeu8(ib.*.unnamed_0.tui, @ptrCast(@constCast(@volatileCast(buf))), len, attr) > 0));
    }

    // out:
    arcan_tui_cursorpos(ib.*.unnamed_0.tui, &ox, &oy);
    lua_pushinteger(L, @as(lua_Integer, @bitCast(ox)));
    lua_pushinteger(L, @as(lua_Integer, @bitCast(oy)));
    return 3;
}
pub fn writeu8(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    var attr: [*c]struct_tui_screen_attr = null;
    var mattr: struct_tui_screen_attr = struct_tui_screen_attr{
        .unnamed_0 = zeroAttrFc(),
        .unnamed_1 = zeroAttrBc(),
        .unnamed_2 = zeroAttrFlags(),
        .custom_id = std.mem.zeroes(u8),
    };
    var len: usize = undefined;
    const buf: [*c]const u8 = luaL_checklstring(L, 2, &len);
    if (lua_type(L, 3) == 5) {
        apply_table(L, 3, &mattr);
        attr = &mattr;
    }
    lua_pushboolean(L, @intFromBool(arcan_tui_writeu8(ib.*.unnamed_0.tui, @ptrCast(@constCast(@volatileCast(buf))), len, attr) > 0));
    return 1;
}
pub fn reset(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    revert(L, ib);
    arcan_tui_reset(ib.*.unnamed_0.tui);
    return 0;
}
pub fn color_get(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    var dst: [3]u8 = [3]u8{ 128, 128, 128 };
    arcan_tui_get_color(ib.*.unnamed_0.tui, @as(c_int, @truncate(luaL_checkinteger(L, 2))), @ptrCast(@alignCast(&dst[0])));
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(dst[0])));
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(dst[1])));
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(dst[2])));
    return 3;
}
pub fn set_flags(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    var flags: u32 = @bitCast(TUI_ALTERNATE);
    {
        var i: usize = 2;
        while (i <= @as(usize, @bitCast(@as(isize, lua_gettop(L))))) : (i +%= 1) {
            const val: u32 = @as(u32, @bitCast(@as(c_int, @truncate(luaL_checkinteger(L, @as(c_int, @intCast(i)))))));
            if ((val != 0) and ((val & (val -% 1)) == 0)) {
                flags |= val;
            } else {
                _ = luaL_error(L, "bad flag value (2^n, n >= 1)");
            }
        }
    }
    _ = arcan_tui_set_flags(ib.*.unnamed_0.tui, @bitCast(flags));
    return 0;
}
pub fn color_set(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    var dst: [3]u8 = [3]u8{
        @as(u8, @bitCast(@as(i8, @truncate(luaL_checkinteger(L, 3))))),
        @as(u8, @bitCast(@as(i8, @truncate(luaL_checkinteger(L, 4))))),
        @as(u8, @bitCast(@as(i8, @truncate(luaL_checkinteger(L, 5))))),
    };
    arcan_tui_set_color(ib.*.unnamed_0.tui, @as(c_int, @truncate(luaL_checkinteger(L, 2))), @ptrCast(@alignCast(&dst[0])));
    return 0;
}
pub fn alert(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    _ = arcan_tui_message(ib.*.unnamed_0.tui, TUI_MESSAGE_ALERT, luaL_checklstring(L, 2, null));
    return 0;
}
pub fn message(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    var ind: c_int = 2;
    var db: [*c]struct_tui_lmeta = ib;
    var msgtype: c_int = TUI_MESSAGE_GENERIC;
    if (lua_type(L, 2) == 7) {
        db = @ptrCast(@alignCast(luaL_checkudata(L, 2, "Arcan TUI")));
        if (!(db != null) or !(db.*.unnamed_0.tui != null)) {
            _ = luaL_error(L, if (!(db != null)) "no userdata" else "userdata isn't a tui context");
        }
        msgtype = TUI_MESSAGE_LOCAL;
        ind += 1;
    }
    _ = arcan_tui_message(db.*.unnamed_0.tui, msgtype, luaL_checklstring(L, ind, null));
    return 0;
}
pub fn notification(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    _ = arcan_tui_message(ib.*.unnamed_0.tui, TUI_MESSAGE_NOTIFICATION, luaL_checklstring(L, 2, null));
    return 0;
}
pub fn failure(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    _ = arcan_tui_message(ib.*.unnamed_0.tui, TUI_MESSAGE_FAILURE, luaL_checklstring(L, 2, null));
    return 0;
}
pub fn refresh_node(t: [*c]struct_tui_lmeta) callconv(.c) c_int {
    const rc: c_int = arcan_tui_refresh(t.*.unnamed_0.tui);
    {
        var i: usize = 0;
        while (i < t.*.n_subs) : (i +%= 1) {
            _ = refresh_node(t.*.submeta[i +% 1]);
        }
    }
    return rc;
}
pub fn refresh(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    var recurse: bool = true;
    if ((lua_type(L, 2) == 1) and !(lua_toboolean(L, 2) != 0)) {
        recurse = false;
    }
    var rc: c_int = undefined;
    if (!recurse) {
        rc = arcan_tui_refresh(ib.*.unnamed_0.tui);
    } else {
        rc = refresh_node(ib);
    }
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(rc)));
    return 1;
}
pub fn announce_io(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if ((!(ib != null) or !(ib.*.unnamed_0.tui != null)) or (ib.*.widget_mode != c.TWND_NORMAL)) {
        _ = luaL_error(L, "window not in normal state");
    }
    const input: [*c]const u8 = luaL_optlstring(L, 2, "", null);
    const output: [*c]const u8 = luaL_optlstring(L, 3, "", null);
    arcan_tui_announce_io(ib.*.unnamed_0.tui, false, input, output);
    return 0;
}
pub fn resetlabels(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    arcan_tui_reset_labels(ib.*.unnamed_0.tui);
    return 0;
}
pub fn request_io(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    const input: [*c]const u8 = luaL_optlstring(L, 2, "", null);
    const output: [*c]const u8 = luaL_optlstring(L, 3, "", null);
    arcan_tui_announce_io(ib.*.unnamed_0.tui, true, input, output);
    return 0;
}
pub fn announce_cursor_io(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    const descr: [*c]const u8 = luaL_optlstring(L, 2, null, null);
    arcan_tui_announce_cursor_io(ib.*.unnamed_0.tui, descr);
    return 0;
}
pub fn statesize(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    const state_sz: usize = @bitCast(luaL_checkinteger(L, 2));
    arcan_tui_statesize(ib.*.unnamed_0.tui, state_sz);
    return 0;
}
pub fn contentsize(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    const row_ofs: usize = @bitCast(luaL_checkinteger(L, 2));
    const row_tot: usize = @bitCast(luaL_checkinteger(L, 3));
    const col_ofs: usize = @bitCast(luaL_optinteger(L, 4, @as(lua_Integer, @bitCast(@as(isize, @as(c_int, 0))))));
    const col_tot: usize = @bitCast(luaL_optinteger(L, 5, @as(lua_Integer, @bitCast(@as(isize, @as(c_int, 0))))));
    arcan_tui_content_size(ib.*.unnamed_0.tui, row_ofs, row_tot, col_ofs, col_tot);
    return 0;
}
pub fn sendkey(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    var l: usize = undefined;
    const @"u8": [*c]const u8 = luaL_checklstring(L, 2, &l);
    var sym: u32 = 0;
    var scode: u8 = 0;
    var mods: u16 = 0;
    var sub: u16 = 0;
    var label: [*c]const u8 = null;
    var ind: usize = 2;
    while ((blk: {
        const ref = &ind;
        ref.* +%= 1;
        break :blk ref.*;
    }) <= @as(usize, @bitCast(@as(isize, lua_gettop(L))))) {
        if (lua_type(L, @as(c_int, @intCast(ind))) == 4) {
            if (label != null) {
                _ = luaL_error(L, "sendkey, label provided twice");
            }
            label = lua_tolstring(L, @as(c_int, @intCast(ind)), null);
        } else if (lua_type(L, @as(c_int, @intCast(ind))) == 3) {
            if (!(sub != 0)) {
                sub = @as(u16, @bitCast(@as(c_short, @truncate(lua_tointeger(L, @as(c_int, @intCast(ind)))))));
            } else if (!(sym != 0)) {
                sym = @as(u32, @bitCast(@as(c_int, @truncate(lua_tointeger(L, @as(c_int, @intCast(ind)))))));
            } else if (!(scode != 0)) {
                scode = @as(u8, @bitCast(@as(i8, @truncate(lua_tointeger(L, @as(c_int, @intCast(ind)))))));
            } else if (!(mods != 0)) {
                mods = @as(u16, @bitCast(@as(c_short, @truncate(lua_tointeger(L, @as(c_int, @intCast(ind)))))));
            } else {
                _ = luaL_error(L, "sendkey, too many arguments provided");
            }
        } else {
            _ = luaL_error(L, "sendkey, unexpected argument (expected number or string)");
        }
    }
    var key: [4]u8 = [1]u8{0} ++ [1]u8{std.mem.zeroes(u8)} ** 3;
    if (l <= 4) {
        _ = memcpy(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(@alignCast(&key[0]))))), @as(?*const anyopaque, @ptrCast(@"u8")), l);
    } else {
        _ = luaL_error(L, "sendkey, expected single utf8 codepoint");
    }
    arcan_tui_send_key(ib.*.unnamed_0.tui, @ptrCast(@alignCast(&key[0])), label, sym, scode, mods, sub);
    return 0;
}
pub fn revertwnd(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    revert(L, ib);
    return 0;
}
pub fn extract_listent(L: ?*lua_State, base: [*c]struct_tui_list_entry, i: usize) callconv(.c) void {
    var attr: c_int = 0;
    if (intblbool(L, -1, "checked")) {
        attr |= c.LIST_CHECKED;
    }
    if (intblbool(L, -1, "has_sub")) {
        attr |= c.LIST_HAS_SUB;
    }
    if (intblbool(L, -1, "separator")) {
        attr |= c.LIST_SEPARATOR;
    }
    if (intblbool(L, -1, "passive")) {
        attr |= c.LIST_PASSIVE;
    }
    if (intblbool(L, -1, "itemlabel")) {
        attr |= c.LIST_LABEL;
    }
    if (intblbool(L, -1, "hidden")) {
        attr |= c.LIST_HIDE;
    }
    base[i] = struct_tui_list_entry{
        .label = null,
        .shortcut = null,
        .attributes = @as(u8, @bitCast(@as(i8, @truncate(attr)))),
        .indent = 0,
        .tag = i +% 1,
    };
    var ok: bool = undefined;
    const iv: c_int = intblint(L, -1, "indent", &ok);
    if (ok) {
        base[i].indent = @as(u8, @bitCast(@as(i8, @truncate(iv))));
    }
    lua_getfield(L, -1, "label");
    base[i].label = strdup(luaL_checklstring(L, -1, null));
    lua_settop(L, -1 - 1);
    lua_getfield(L, -1, "shortcut");
    base[i].shortcut = strdup(luaL_optlstring(L, -1, "", null));
    lua_settop(L, -1 - 1);
}
pub fn readline(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, if (!(ib != null)) "no userdata" else "no tui context");
    }
    revert(L, ib);
    const ofs: isize = 2;
    var opts: struct_tui_readline_opts = struct_tui_readline_opts{
        .anchor_row = 0,
        .n_rows = 1,
        .margin_left = 0,
        .margin_right = 0,
        .allow_exit = false,
        .autocomplete = null,
        .filter_character = &on_readline_filter,
        .mask_character = 0,
        .multiline = false,
        .tab_completion = true,
        .verify = &on_readline_verify,
        .mouse_forward = false,
        .paste_forward = false,
        .block_builtin_bindings = false,
        .popup = null,
        .completion_compact = false,
        .linefeed_expand = false,
        .whitespace_expand = false,
        .suggest_item = &on_readline_suggest_item,
    };
    if (!(lua_type(L, @as(c_int, @truncate(ofs))) == 6) or (lua_iscfunction(L, @as(c_int, @truncate(ofs))) != 0)) {
        _ = luaL_error(L, "readline(closure, [table]) - missing closure");
    }
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(lua_newuserdata(L, @sizeOf(struct_widget_meta))));
    if (!(meta != null)) {
        _ = luaL_error(L, "couldn't allocate userdata");
    }
    meta.* = struct_widget_meta{
        .parent = null,
        .unnamed_0 = .{
            .readline = .{
                .verify = @as(isize, @bitCast(@as(isize, -2))),
                .filter = @as(isize, @bitCast(@as(isize, -2))),
                .item = @as(isize, @bitCast(@as(isize, -2))),
                .history = null,
                .history_sz = std.mem.zeroes(usize),
                .suggest = null,
                .suggest_sz = std.mem.zeroes(usize),
            },
        },
    };
    const tbl: c_int = @as(c_int, @truncate(ofs + 1));
    if (lua_type(L, tbl) == 5) {
        var ok: bool = undefined;
        var vl: c_int = intblint(L, tbl, "anchor", &ok);
        if (ok) {
            opts.anchor_row = @as(isize, @bitCast(@as(isize, vl)));
        }
        vl = intblint(L, tbl, "rows", &ok);
        if (ok) {
            opts.n_rows = @as(usize, @bitCast(@as(isize, vl)));
        }
        vl = intblint(L, tbl, "margin_left", &ok);
        if ((@as(c_int, @intFromBool(ok)) != 0) and (vl >= 0)) {
            opts.margin_left = @as(usize, @bitCast(@as(isize, c.abs(vl))));
        }
        vl = intblint(L, tbl, "margin_right", &ok);
        if ((@as(c_int, @intFromBool(ok)) != 0) and (vl >= 0)) {
            opts.margin_right = @as(usize, @bitCast(@as(isize, c.abs(vl))));
        }
        if (intblbool(L, tbl, "cancellable")) {
            opts.allow_exit = true;
        }
        if (intblbool(L, tbl, "multiline")) {
            opts.multiline = true;
        }
        if (intblbool(L, tbl, "tab_input")) {
            opts.tab_completion = false;
        }
        if (intblbool(L, tbl, "block_builtin")) {
            opts.block_builtin_bindings = true;
        }
        if (intblbool(L, tbl, "compact")) {
            opts.completion_compact = true;
        }
        if (intblbool(L, tbl, "linefeed_expand")) {
            opts.linefeed_expand = true;
        }
        if (intblbool(L, tbl, "whitespace_expand")) {
            opts.whitespace_expand = true;
        }
        opts.mouse_forward = intblbool(L, tbl, "forward_mouse");
        opts.paste_forward = intblbool(L, tbl, "forward_paste");
        lua_getfield(L, tbl, "mask_character");
        if (lua_isstring(L, -1) != 0) {
            _ = arcan_tui_utf8ucs4(lua_tolstring(L, -1, null), &opts.mask_character);
        }
        lua_settop(L, -1 - 1);
        lua_getfield(L, tbl, "verify");
        if ((lua_type(L, -1) == 6) and !(lua_iscfunction(L, -1) != 0)) {
            meta.*.unnamed_0.readline.verify = tui_lref(L, -1, "readline", "2494", 6);
        }
        lua_settop(L, -1 - 1);
        lua_getfield(L, tbl, "item");
        if ((lua_type(L, -1) == 6) and !(lua_iscfunction(L, -1) != 0)) {
            meta.*.unnamed_0.readline.item = tui_lref(L, -1, "readline", "2499", 6);
        }
        lua_settop(L, -1 - 1);
        lua_getfield(L, tbl, "filter");
        if ((lua_type(L, -1) == 6) and !(lua_iscfunction(L, -1) != 0)) {
            meta.*.unnamed_0.readline.filter = tui_lref(L, -1, "readline", "2504", 6);
        }
        lua_settop(L, -1 - 1);
    }
    ib.*.widget_closure = tui_lref(L, @as(c_int, @truncate(ofs)), "readline", "2509", 6);
    ib.*.widget_mode = c.TWND_READLINE;
    meta.*.parent = ib;
    ib.*.widget_meta = meta;
    _ = lua_getfield(L, -1001000, "widget_readline");
    _ = lua_setmetatable(L, -2);
    arcan_tui_readline_setup(ib.*.unnamed_0.tui, &opts, @sizeOf(struct_tui_readline_opts));
    ib.*.widget_state = tui_lref(L, -1, "readline", "2526", 7);
    return 1;
}
pub fn readline_region(L: ?*lua_State) callconv(.c) c_int {
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "widget_readline")));
    if (!(meta != null) or !(meta.*.parent != null)) {
        _ = luaL_error(L, "readline: API error, widget metadata freed");
    }
    const ib: [*c]struct_tui_lmeta = meta.*.parent;
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, "readline: parent window closed");
    }
    if (ib.*.widget_mode != c.TWND_READLINE) return 0;
    const x1: usize = @bitCast(luaL_checkinteger(L, 2));
    const y1: usize = @bitCast(luaL_checkinteger(L, 3));
    const x2: usize = @bitCast(luaL_checkinteger(L, 4));
    const y2: usize = @bitCast(luaL_checkinteger(L, 5));
    arcan_tui_readline_region(ib.*.unnamed_0.tui, x1, y1, x2, y2);
    return 0;
}
pub fn bufferwnd_seek(L: ?*lua_State) callconv(.c) c_int {
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "widget_bufferview")));
    if (!(meta != null) or !(meta.*.parent != null)) {
        _ = luaL_error(L, "bufferview: API error, widget metadata freed");
    }
    const ib: [*c]struct_tui_lmeta = meta.*.parent;
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, "readline: parent window closed");
    }
    if (ib.*.widget_mode != c.TWND_BUFWND) return 0;
    const pos: usize = @bitCast(luaL_checkinteger(L, 2));
    arcan_tui_bufferwnd_seek(ib.*.unnamed_0.tui, pos);
    return 0;
}
pub fn bufferwnd_tell(L: ?*lua_State) callconv(.c) c_int {
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "widget_bufferview")));
    if (!(meta != null) or !(meta.*.parent != null)) {
        _ = luaL_error(L, "bufferview: API error, widget metadata freed");
    }
    const ib: [*c]struct_tui_lmeta = meta.*.parent;
    if (!(ib != null) or !(ib.*.unnamed_0.tui != null)) {
        _ = luaL_error(L, "readline: parent window closed");
    }
    if (ib.*.widget_mode != c.TWND_BUFWND) return 0;
    const pos: usize = arcan_tui_bufferwnd_tell(ib.*.unnamed_0.tui, null);
    lua_pushinteger(L, @as(lua_Integer, @bitCast(pos)));
    return 1;
}
pub fn bufferwnd(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if ((!(ib != null) or !(ib.*.unnamed_0.tui != null)) or (ib.*.widget_mode != c.TWND_NORMAL)) {
        _ = luaL_error(L, "window not in normal state");
    }
    revert(L, ib);
    var opts: struct_tui_bufferwnd_opts = struct_tui_bufferwnd_opts{
        .read_only = true,
        .allow_exit = true,
        .hide_cursor = false,
        .view_mode = c.BUFFERWND_VIEW_UTF8,
        .wrap_mode = c.BUFFERWND_WRAP_ACCEPT_LF,
        .color_mode = c.BUFFERWND_COLOR_NONE,
        .hex_mode = c.BUFFERWND_HEX_BASIC,
        .custom_attr = null,
        .commit = null,
        .cbtag = null,
        .offset = 0,
    };
    if (lua_type(L, 2) != 4) {
        _ = luaL_error(L, "bufferview(wnd, >string<, closure, opts - missing data string");
    }
    if (!(lua_type(L, 3) == 6) or (lua_iscfunction(L, 3) != 0)) {
        _ = luaL_error(L, "bufferview(wnd, string, >closure<, opts - missing closure");
    }
    if (lua_type(L, 4) == 5) {
        if (intblbool(L, 4, "hex")) {
            opts.view_mode = c.BUFFERWND_VIEW_HEX;
            opts.hex_mode = c.BUFFERWND_HEX_BASIC;
        }
        if (intblbool(L, 4, "hex_detail")) {
            opts.view_mode = c.BUFFERWND_VIEW_HEX_DETAIL;
            opts.hex_mode = c.BUFFERWND_HEX_ASCII;
        }
        if (intblbool(L, 4, "hex_detail_meta")) {
            opts.view_mode = c.BUFFERWND_VIEW_HEX_DETAIL;
            opts.hex_mode = c.BUFFERWND_HEX_META;
        }
        if (!intblbool(L, 4, "read_only")) {
            opts.read_only = false;
        }
        if (intblbool(L, 4, "block_exit")) {
            opts.allow_exit = false;
        }
        if (intblbool(L, 4, "hide_cursor")) {
            opts.hide_cursor = true;
        }
        if (intblbool(L, 4, "ignore_lf")) {
            opts.wrap_mode = c.BUFFERWND_WRAP_ALL;
        }
    }
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(lua_newuserdata(L, @sizeOf(struct_widget_meta))));
    if (!(meta != null)) {
        _ = luaL_error(L, "couldn't allocate userdata");
    }
    meta.* = struct_widget_meta{
        .parent = ib,
        .unnamed_0 = zeroWidgetUnion(),
    };
    var len: usize = undefined;
    const buf: [*c]const u8 = luaL_checklstring(L, 2, &len);
    meta.*.unnamed_0.bufferview.buf = @ptrCast(@alignCast(malloc(len)));
    if (meta.*.unnamed_0.bufferview.buf == null) {
        _ = luaL_error(L, "bufferview buffer allocation failure");
    }
    _ = memcpy(@as(?*anyopaque, @ptrCast(meta.*.unnamed_0.bufferview.buf)), @as(?*const anyopaque, @ptrCast(buf)), len);
    meta.*.unnamed_0.bufferview.sz = len;
    ib.*.widget_mode = c.TWND_BUFWND;
    ib.*.widget_meta = meta;
    ib.*.widget_closure = tui_lref(L, 3, "bufferwnd", "2637", 6);
    arcan_tui_bufferwnd_setup(ib.*.unnamed_0.tui, meta.*.unnamed_0.bufferview.buf, meta.*.unnamed_0.bufferview.sz, &opts, @sizeOf(struct_tui_bufferwnd_opts));
    ib.*.widget_state = tui_lref(L, -1, "bufferwnd", "2642", 7);
    return 1;
}
pub fn table_to_list(L: ?*lua_State, M: [*c]struct_widget_meta, ind: c_int) callconv(.c) void {
    const nelems: c_int = @bitCast(@as(c_uint, @truncate(lua_objlen(L, ind))));
    if (nelems <= 0) {
        _ = luaL_error(L, "listview(table, closure) - table has 0 elements");
    }
    if (M.*.unnamed_0.listview.ents != null) {
        free(@as(?*anyopaque, @ptrCast(M.*.unnamed_0.listview.ents)));
        M.*.unnamed_0.listview.ents = null;
    }
    const tmplist: [*c]struct_tui_list_entry = @ptrCast(@alignCast(malloc(@sizeOf(struct_tui_list_entry) *% @as(usize, @bitCast(@as(isize, nelems))))));
    if (tmplist == null) {
        _ = luaL_error(L, "listview(table, closure) - couldn't store table");
    }
    {
        var i: usize = 0;
        while (i < @as(usize, @bitCast(@as(isize, nelems)))) : (i +%= 1) {
            lua_rawgeti(L, 2, @as(c_int, @bitCast(@as(c_uint, @truncate(i +% 1)))));
            extract_listent(L, tmplist, i);
            lua_settop(L, -1 - 1);
        }
    }
    M.*.unnamed_0.listview.ents = tmplist;
    M.*.unnamed_0.listview.n_ents = @as(usize, @bitCast(@as(isize, nelems)));
}
pub fn listwnd(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if ((ib == null or ib.*.unnamed_0.tui == null) or (ib.*.widget_mode != c.TWND_NORMAL)) {
        _ = luaL_error(L, "window not in normal state");
    }
    revert(L, ib);
    if (lua_type(L, 2) != 5) {
        _ = luaL_error(L, "listview(table, closure) - missing table");
    }
    if (!(lua_type(L, 3) == 6) or (lua_iscfunction(L, 3) != 0)) {
        _ = luaL_error(L, "listview(table, closure) - missing closure function");
    }
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(lua_newuserdata(L, @sizeOf(struct_widget_meta))));
    if (meta == null) {
        _ = luaL_error(L, "couldn't allocate userdata");
    }
    _ = lua_getfield(L, -1001000, "widget_listview");
    _ = lua_setmetatable(L, -2);
    meta.* = struct_widget_meta{
        .parent = ib,
        .unnamed_0 = zeroWidgetUnion(),
    };
    table_to_list(L, meta, 2);
    ib.*.widget_mode = c.TWND_LISTWND;
    ib.*.widget_meta = meta;
    ib.*.widget_closure = tui_lref(L, 3, "listwnd", "2707", 6);
    _ = arcan_tui_listwnd_setup(ib.*.unnamed_0.tui, meta.*.unnamed_0.listview.ents, meta.*.unnamed_0.listview.n_ents);
    ib.*.widget_state = tui_lref(L, -1, "listwnd", "2712", 7);
    return 1;
}
pub fn utf8len(msg_arg: [*c]const u8) callconv(.c) isize {
    var msg = msg_arg;
    var res: isize = 0;
    var tmp: u32 = undefined;
    while (msg.* != 0) {
        const step: usize = arcan_tui_utf8ucs4(msg, &tmp);
        if (step == 0) return -1;
        msg += step;
        res += 1;
    }
    return res;
}
pub fn utf8length(L: ?*lua_State) callconv(.c) c_int {
    var ci: usize = 1;
    if (lua_type(L, @as(c_int, @bitCast(@as(c_uint, @truncate(ci))))) == 7) {
        ci +%= 1;
    }
    const msg: [*c]const u8 = luaL_checklstring(L, @as(c_int, @bitCast(@as(c_uint, @truncate(ci)))), null);
    lua_pushinteger(L, utf8len(msg));
    return 1;
}
pub fn readline_prompt(L: ?*lua_State) callconv(.c) c_int {
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "widget_readline")));
    if (meta == null or meta.*.parent == null) {
        _ = luaL_error(L, "readline: API error, widget metadata freed");
    }
    const ib: [*c]struct_tui_lmeta = meta.*.parent;
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, "readline: parent window closed");
    }
    if (ib.*.widget_mode != c.TWND_READLINE) return 0;
    var rattr: struct_tui_screen_attr = arcan_tui_defcattr(ib.*.unnamed_0.tui, TUI_COL_LABEL);
    var n_cells: usize = 1;
    var prompt: [*c]struct_tui_cell = null;
    if (lua_type(L, 2) == 5) {
        const nelem: usize = lua_objlen(L, 2);
        var ltot: usize = 0;
        {
            var i: usize = 1;
            while (i <= nelem) : (i +%= 1) {
                lua_rawgeti(L, 2, @as(c_int, @bitCast(@as(c_uint, @truncate(i)))));
                if (lua_type(L, -1) == 5) {
                    lua_settop(L, -1 - 1);
                } else if (lua_type(L, -1) == 4) {
                    const msg: [*c]const u8 = lua_tolstring(L, -1, null);
                    const len: isize = utf8len(msg);
                    if (@as(isize, @bitCast(@as(isize, -@as(c_int, 1)))) == len) {
                        _ = luaL_error(L, "invalid utf8 string in prompt");
                    }
                    ltot +%= @as(usize, @bitCast(len));
                    lua_settop(L, -1 - 1);
                } else {
                    _ = luaL_error(L, "(attr-table or string) expected in prompt table");
                }
            }
        }
        n_cells = ltot +% 1;
        prompt = @ptrCast(@alignCast(malloc(n_cells *% @sizeOf(struct_tui_cell))));
        var celli: usize = 0;
        {
            var i: usize = 1;
            while (i <= nelem) : (i +%= 1) {
                lua_rawgeti(L, 2, @as(c_int, @bitCast(@as(c_uint, @truncate(i)))));
                if (lua_type(L, -1) == 5) {
                    apply_table(L, -1, &rattr);
                    lua_settop(L, -1 - 1);
                } else if (lua_type(L, -1) == 4) {
                    var msg: [*c]const u8 = lua_tolstring(L, -1, null);
                    while (msg.* != 0) {
                        prompt[celli] = struct_tui_cell{
                            .attr = rattr,
                            .ch = 0,
                            .draw_ch = 0,
                            .real_x = 0,
                            .cell_w = 0,
                            .fstamp = 0,
                        };
                        msg += @as(usize, @bitCast(@as(isize, @intCast(arcan_tui_utf8ucs4(msg, &prompt[celli].ch)))));
                        celli +%= 1;
                    }
                    lua_settop(L, -1 - 1);
                }
            }
        }
        prompt[celli] = struct_tui_cell{
            .attr = struct_tui_screen_attr{
                .unnamed_0 = .{
                    .fc = [1]u8{
                        0,
                    } ++ [1]u8{0} ** 2,
                },
                .unnamed_1 = zeroAttrBc(),
                .unnamed_2 = zeroAttrFlags(),
                .custom_id = 0,
            },
            .ch = 0,
            .draw_ch = 0,
            .real_x = 0,
            .cell_w = 0,
            .fstamp = 0,
        };
    } else if (lua_type(L, 2) == 4) {
        var msg: [*c]const u8 = lua_tolstring(L, 2, null);
        const len: isize = utf8len(msg);
        if (@as(isize, @bitCast(@as(isize, -@as(c_int, 1)))) == len) {
            _ = luaL_error(L, "invalid utf8 string in prompt");
        }
        n_cells = @as(usize, @bitCast(len + 1));
        prompt = @ptrCast(@alignCast(malloc(n_cells *% @sizeOf(struct_tui_cell))));
        {
            var i: usize = 0;
            while (i < (n_cells -% 1)) : (i +%= 1) {
                prompt[i] = struct_tui_cell{
                    .attr = std.mem.zeroes(struct_tui_screen_attr),
                    .ch = 0,
                    .draw_ch = 0,
                    .real_x = 0,
                    .cell_w = 0,
                    .fstamp = 0,
                };
                msg += @as(usize, @bitCast(@as(isize, @intCast(arcan_tui_utf8ucs4(msg, &prompt[i].ch)))));
                prompt[i].attr = rattr;
            }
        }
        prompt[n_cells -% 1] = struct_tui_cell{
            .attr = std.mem.zeroes(struct_tui_screen_attr),
            .ch = 0,
            .draw_ch = 0,
            .real_x = 0,
            .cell_w = 0,
            .fstamp = 0,
        };
    } else {
        _ = luaL_error(L, "expected table or string");
    }
    arcan_tui_readline_prompt(ib.*.unnamed_0.tui, prompt);
    return 0;
}
pub fn readline_suggest(L: ?*lua_State) callconv(.c) c_int {
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "widget_readline")));
    if (meta == null or meta.*.parent == null) {
        _ = luaL_error(L, "readline: API error, widget metadata freed");
    }
    const ib: [*c]struct_tui_lmeta = meta.*.parent;
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, "readline: parent window closed");
    }
    if (ib.*.widget_mode != c.TWND_READLINE) return 0;
    var count: usize = 0;
    var new_suggest: [*c][*c]u8 = null;
    const index_1: usize = 2;
    if (lua_type(L, 2) == 1) {
        arcan_tui_readline_autosuggest(ib.*.unnamed_0.tui, lua_toboolean(L, 2) != 0);
        return 0;
    }
    if (lua_type(L, @as(c_int, @bitCast(@as(c_uint, @truncate(index_1))))) != 5) {
        _ = luaL_error(L, "suggest(table) - missing table");
    }
    const nelem: isize = @as(isize, @bitCast(lua_objlen(L, @as(c_int, @bitCast(@as(c_uint, @truncate(index_1)))))));
    var starti: usize = 0;
    var hint_ext: bool = false;
    lua_getfield(L, @as(c_int, @bitCast(@as(c_uint, @truncate(index_1)))), "hint");
    if (lua_type(L, -1) == 5) {
        hint_ext = true;
    }
    lua_settop(L, -1 - 1);
    var title: [*c]u8 = null;
    lua_getfield(L, @as(c_int, @bitCast(@as(c_uint, @truncate(index_1)))), "title");
    if (lua_type(L, -1) == 4) {
        const tmp: [*c]const u8 = lua_tolstring(L, -1, null);
        const tlen: usize = strlen(tmp);
        title = @ptrCast(@alignCast(malloc(tlen +% 2)));
        if (title == null) {
            _ = luaL_error(L, "set_siggest(alloc) - out of memory");
        }
        _ = memcpy(@as(?*anyopaque, @ptrCast(title)), @as(?*const anyopaque, @ptrCast(tmp)), tlen);
        title[tlen] = '\x00';
        title[tlen +% 1] = '\x00';
        starti +%= 1;
        count +%= 1;
    }
    lua_settop(L, -1 - 1);
    if (nelem < 0) {
        _ = luaL_error(L, "suggest(table) - negative length");
    }
    if (nelem != 0) {
        new_suggest = @ptrCast(@alignCast(malloc((@as(usize, @bitCast(nelem)) +% starti) *% @sizeOf([*c]u8))));
        if (new_suggest == null) {
            _ = luaL_error(L, "set_suggest(alloc) - out of memory");
        }
        if (title != null) {
            new_suggest[0] = title;
        }
        {
            var i: usize = 0;
            while (i < @as(usize, @bitCast(nelem))) : (i +%= 1) {
                lua_rawgeti(L, 2, @as(c_int, @bitCast(@as(c_uint, @truncate(i +% 1)))));
                if (lua_type(L, -1) != 4) {
                    _ = luaL_error(L, "set_suggest - expected string in suggest");
                }
                const a1: [*c]const u8 = lua_tolstring(L, -1, null);
                if (hint_ext) {
                    lua_getfield(L, @as(c_int, @bitCast(@as(c_uint, @truncate(index_1)))), "hint");
                    lua_rawgeti(L, -1, @as(c_int, @bitCast(@as(c_uint, @truncate(i +% 1)))));
                    var a2: [*c]const u8 = "";
                    if (lua_type(L, -1) == 4) {
                        a2 = lua_tolstring(L, -1, null);
                    }
                    const len: usize = (strlen(a1) +% strlen(a2)) +% 2;
                    new_suggest[starti +% i] = @ptrCast(@alignCast(malloc(len)));
                    _ = snprintf(new_suggest[starti +% i], len, "%s%c%s", a1, @as(c_int, 0), a2);
                    lua_settop(L, -2 - 1);
                } else {
                    new_suggest[starti +% i] = strdup(a1);
                    if (new_suggest[starti +% i] == null) {
                        free(@as(?*anyopaque, @ptrCast(new_suggest)));
                        _ = luaL_error(L, "set_suggest(hint, alloc) - out of memory");
                    }
                }
                count +%= 1;
                lua_settop(L, -1 - 1);
            }
        }
    }
    free_suggest(meta);
    const mode: [*c]const u8 = luaL_optlstring(L, @as(c_int, @bitCast(@as(c_uint, @truncate(index_1 +% 1)))), "word", null);
    var mv: c_int = c.READLINE_SUGGEST_WORD;
    if (strcasecmp(mode, "insert") == 0) {
        mv = c.READLINE_SUGGEST_INSERT;
    } else if (strcasecmp(mode, "word") == 0) {
        mv = c.READLINE_SUGGEST_WORD;
    } else if (strcasecmp(mode, "substitute") == 0) {
        mv = c.READLINE_SUGGEST_SUBSTITUTE;
    } else if (strcasecmp(mode, "ignore") == 0) {
        mv = c.READLINE_SUGGEST_IGNORE;
    } else {
        _ = luaL_error(L, "set_suggest(str:mode) expected insert, word or substitute");
    }
    if (title != null) {
        mv |= c.READLINE_SUGGEST_TITLE_HINT;
    }
    if (hint_ext) {
        mv |= c.READLINE_SUGGEST_HINT;
    }
    meta.*.unnamed_0.readline.suggest = new_suggest;
    meta.*.unnamed_0.readline.suggest_sz = count;
    arcan_tui_readline_suggest(meta.*.parent.*.unnamed_0.tui, mv, @ptrCast(@alignCast(new_suggest)), count);
    const prefix: [*c]const u8 = luaL_optlstring(L, @as(c_int, @bitCast(@as(c_uint, @truncate(index_1 +% 2)))), null, null);
    const suffix: [*c]const u8 = luaL_optlstring(L, @as(c_int, @bitCast(@as(c_uint, @truncate(index_1 +% 3)))), null, null);
    arcan_tui_readline_suggest_fix(meta.*.parent.*.unnamed_0.tui, prefix, suffix);
    return 0;
}
pub fn readline_get(L: ?*lua_State) callconv(.c) c_int {
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "widget_readline")));
    if (meta == null or meta.*.parent == null) {
        _ = luaL_error(L, "readline: API error, widget metadata freed");
    }
    const ib: [*c]struct_tui_lmeta = meta.*.parent;
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, "readline: parent window closed");
    }
    if (ib.*.widget_mode != c.TWND_READLINE) return 0;
    var buf: [*c]u8 = undefined;
    _ = arcan_tui_readline_finished(ib.*.unnamed_0.tui, &buf);
    if (buf != null) {
        lua_pushstring(L, buf);
    } else {
        lua_pushstring(L, "");
    }
    return 1;
}
pub fn readline_set(L: ?*lua_State) callconv(.c) c_int {
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "widget_readline")));
    if (meta == null or meta.*.parent == null) {
        _ = luaL_error(L, "readline: API error, widget metadata freed");
    }
    const ib: [*c]struct_tui_lmeta = meta.*.parent;
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, "readline: parent window closed");
    }
    if (ib.*.widget_mode != c.TWND_READLINE) return 0;
    var ind: c_int = 2;
    if (lua_type(L, ind) == 4) {
        const msg: [*c]const u8 = luaL_checklstring(L, 2, null);
        if (strlen(msg) == 0) {
            arcan_tui_readline_set(ib.*.unnamed_0.tui, null);
        } else {
            arcan_tui_readline_set(ib.*.unnamed_0.tui, msg);
        }
        ind += 1;
    }
    if (lua_type(L, ind) == 5) {
        const nelem: isize = @as(isize, @bitCast(lua_objlen(L, ind)));
        if (nelem <= 0) return 0;
        if (@import("std").zig.c_translation.signedRemainder(nelem, 2) != 0) {
            _ = luaL_error(L, "readline:set(>table<) table fmt should be {ofs, fmttbl, ofs2, fmttbl2, ...}");
        }
        const count: usize = @as(usize, @bitCast(@divTrunc(nelem, 2)));
        var ofs: [*c]usize = @ptrCast(@alignCast(malloc(count *% @sizeOf(usize))));
        var attr: [*c]struct_tui_screen_attr = @ptrCast(@alignCast(malloc(count *% @sizeOf(struct_tui_screen_attr))));
        {
            var i: usize = 0;
            while (i < count) : (i +%= 1) {
                lua_rawgeti(L, ind, @as(c_int, @bitCast(@as(c_uint, @truncate(i *% 2)))));
                if (lua_type(L, -1) != 3) {
                    _ = luaL_error(L, "readline:set(>table<) expected ch offset number");
                }
                ofs[i] = @as(usize, @intFromFloat(lua_tonumber(L, -1)));
                lua_settop(L, -1 - 1);
                lua_rawgeti(L, ind, @as(c_int, @bitCast(@as(c_uint, @truncate((i *% 2) +% 1)))));
                if (lua_type(L, -1) != 5) {
                    _ = luaL_error(L, "readline:set(>table<) expected attribute table");
                }
                apply_table(L, -1, &attr[i]);
                lua_settop(L, -1 - 1);
            }
        }
        arcan_tui_readline_format(ib.*.unnamed_0.tui, ofs, attr, count);
    }
    return 0;
}
pub fn readline_autocomplete(L: ?*lua_State) callconv(.c) c_int {
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "widget_readline")));
    if (meta == null or meta.*.parent == null) {
        _ = luaL_error(L, "readline: API error, widget metadata freed");
    }
    const ib: [*c]struct_tui_lmeta = meta.*.parent;
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, "readline: parent window closed");
    }
    if (ib.*.widget_mode != c.TWND_READLINE) return 0;
    const msg: [*c]const u8 = luaL_checklstring(L, 2, null);
    if (strlen(msg) == 0) {
        arcan_tui_readline_autocomplete(ib.*.unnamed_0.tui, null);
    } else {
        arcan_tui_readline_autocomplete(ib.*.unnamed_0.tui, msg);
    }
    return 0;
}
pub fn readline_history(L: ?*lua_State) callconv(.c) c_int {
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "widget_readline")));
    if (meta == null or meta.*.parent == null) {
        _ = luaL_error(L, "readline: API error, widget metadata freed");
    }
    const ib: [*c]struct_tui_lmeta = meta.*.parent;
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, "readline: parent window closed");
    }
    if (ib.*.widget_mode != c.TWND_READLINE) return 0;
    var count: usize = 0;
    var new_history: [*c][*c]u8 = null;
    if (lua_type(L, 2) != 5) {
        _ = luaL_error(L, "set_history(table) - missing table");
    }
    const nelem: isize = @as(isize, @bitCast(lua_objlen(L, 2)));
    if (nelem < 0) {
        _ = luaL_error(L, "set_history(table) - negative length");
    }
    if (nelem != 0) {
        new_history = @ptrCast(@alignCast(malloc(@as(usize, @bitCast(nelem)) *% @sizeOf([*c]u8))));
        if (new_history == null) {
            _ = luaL_error(L, "set_history(alloc) - out of memory");
        }
        {
            var i: usize = 0;
            while (i < @as(usize, @bitCast(nelem))) : (i +%= 1) {
                lua_rawgeti(L, 2, @as(c_int, @bitCast(@as(c_uint, @truncate(i +% 1)))));
                if (lua_type(L, -1) != 4) {
                    _ = luaL_error(L, "set_history - expected string in history");
                }
                new_history[i] = strdup(lua_tolstring(L, -1, null));
                count +%= 1;
                lua_settop(L, -1 - 1);
            }
        }
    }
    free_history(meta);
    meta.*.unnamed_0.readline.history = new_history;
    meta.*.unnamed_0.readline.history_sz = count;
    arcan_tui_readline_history(meta.*.parent.*.unnamed_0.tui, @ptrCast(@alignCast(new_history)), count);
    return 0;
}
pub fn listwnd_pos(L: ?*lua_State) callconv(.c) c_int {
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "widget_listview")));
    if (meta == null or meta.*.parent == null) {
        _ = luaL_error(L, "listview: API error, widget metadata freed");
    }
    const ib: [*c]struct_tui_lmeta = meta.*.parent;
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, "readline: parent window closed");
    }
    if (ib.*.widget_mode != c.TWND_LISTWND) return 0;
    const new: c_int = @truncate(luaL_optinteger(L, 2, @as(lua_Integer, @bitCast(@as(isize, -@as(c_int, 1))))));
    if (new > 0) {
        arcan_tui_listwnd_setpos(ib.*.unnamed_0.tui, @as(usize, @bitCast(@as(isize, new))));
    }
    const pos: usize = arcan_tui_listwnd_tell(ib.*.unnamed_0.tui);
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(pos + 1)));
    return 1;
}
pub fn listwnd_update(L: ?*lua_State) callconv(.c) c_int {
    const meta: [*c]struct_widget_meta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "widget_listview")));
    if (meta == null or meta.*.parent == null) {
        _ = luaL_error(L, "listview: API error, widget metadata freed");
    }
    const ib: [*c]struct_tui_lmeta = meta.*.parent;
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, "readline: parent window closed");
    }
    if (ib.*.widget_mode != c.TWND_LISTWND) return 0;
    var pos: c_int = @intFromFloat(luaL_checknumber(L, 2));
    if ((pos <= 0) or (@as(usize, @bitCast(@as(isize, pos))) >= meta.*.unnamed_0.listview.n_ents)) {
        _ = luaL_error(L, "listview:update(index, tbl) - index out of bounds");
    }
    pos -= 1;
    if (lua_type(L, 3) != 5) {
        _ = luaL_error(L, "listview:update(index, tbl) - tbl argument bad / missing");
    }
    lua_pushvalue(L, 3);
    extract_listent(L, meta.*.unnamed_0.listview.ents, @as(usize, @bitCast(@as(isize, pos))));
    lua_settop(L, -1 - 1);
    arcan_tui_listwnd_dirty(ib.*.unnamed_0.tui);
    return 0;
}
pub fn apiversion(L: ?*lua_State) callconv(.c) c_int {
    lua_createtable(L, 0, 0);
    lua_pushinteger(L, 1);
    lua_setfield(L, -2, "major");
    lua_pushinteger(L, 0);
    lua_setfield(L, -2, "minor");
    lua_pushinteger(L, 0);
    lua_setfield(L, -2, "micro");
    return 1;
}
pub fn apiversionstr(L: ?*lua_State) callconv(.c) c_int {
    lua_pushstring(L, "1.0.0");
    return 1;
}
pub fn tui_tostring(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        lua_pushstring(L, "tui(closed)");
    } else {
        while (true) {
            switch (ib.*.widget_mode) {
                3 => {
                    lua_pushstring(L, "tui(readline)");
                    break;
                },
                2 => {
                    lua_pushstring(L, "tui(bufferview)");
                    break;
                },
                4 => {
                    lua_pushstring(L, "tui(listview)");
                    break;
                },
                else => {
                    lua_pushstring(L, "tui(window)");
                    break;
                },
            }
            break;
        }
    }
    return 1;
}
pub fn utf8step(L: ?*lua_State) callconv(.c) c_int {
    var ci: usize = 1;
    if (lua_type(L, @as(c_int, @bitCast(@as(c_uint, @truncate(ci))))) == 7) {
        ci +%= 1;
    }
    const msg: [*c]const u8 = luaL_checklstring(L, @as(c_int, @bitCast(@as(c_uint, @truncate(ci)))), null);
    const step: isize = @intFromFloat(luaL_optnumber(L, @as(c_int, @bitCast(@as(c_uint, @truncate(ci +% 1)))), @as(lua_Number, @floatFromInt(@as(c_int, 1)))));
    var ofs: isize = @intFromFloat(luaL_optnumber(L, @as(c_int, @bitCast(@as(c_uint, @truncate(ci +% 2)))), @as(lua_Number, @floatFromInt(@as(c_int, 1)))) - @as(lua_Number, @floatFromInt(@as(c_int, 1))));
    const len: isize = @as(isize, @bitCast(strlen(msg)));
    if ((len == 0 or (ofs > len)) or (ofs < 0)) {
        lua_pushnumber(L, @as(lua_Number, @floatFromInt(-@as(c_int, 1))));
        return 1;
    }
    while ((@as(c_int, @bitCast(@as(c_uint, (blk: {
        const tmp = ofs;
        if (tmp >= 0) break :blk msg + @as(usize, @intCast(tmp)) else break :blk msg - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
    }).*))) & 192) == 128) {
        ofs = ofs - 1;
        if (ofs < 0) {
            lua_pushnumber(L, @as(lua_Number, @floatFromInt(-@as(c_int, 1))));
            return 1;
        }
    }
    const sign: isize = @as(isize, @intFromBool(step > 0)) - @as(isize, @intFromBool(step < 0));
    var ns: isize = sign * step;
    while (((ofs >= 0) and (ofs < len)) and (ns != 0)) {
        ofs += sign;
        while ((((@as(c_int, @bitCast(@as(c_uint, (blk: {
            const tmp = ofs;
            if (tmp >= 0) break :blk msg + @as(usize, @intCast(tmp)) else break :blk msg - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*))) & 192) == 128) and (ofs < len)) and (ofs >= 0)) {
            ofs += sign;
        }
        ns -= 1;
    }
    if (ns != 0) {
        lua_pushnumber(L, @as(lua_Number, @floatFromInt(-@as(c_int, 1))));
    } else {
        lua_pushnumber(L, @as(lua_Number, @floatFromInt(ofs + 1)));
        lua_pushlstring(L, &(blk: {
            const tmp = ofs;
            if (tmp >= 0) break :blk msg + @as(usize, @intCast(tmp)) else break :blk msg - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*, @as(usize, @bitCast(utf8len(&(blk: {
            const tmp = ofs;
            if (tmp >= 0) break :blk msg + @as(usize, @intCast(tmp)) else break :blk msg - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        }).*))));
        return 2;
    }
    return 1;
}
pub fn nbio_error(L: ?*lua_State, fd: c_int, tag: isize, src: [*c]const u8) callconv(.c) void {
    _ = L;
    _ = fd;
    _ = tag;
    _ = src;
}
pub fn tui_fmkdir(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    const src: [*c]const u8 = luaL_checklstring(L, 2, null);
    if (-@as(c_int, 1) == ib.*.cwd_fd) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "invalid current working directory");
        return 2;
    }
    const status: c_int = mkdirat(ib.*.cwd_fd, src, @as(mode_t, @bitCast(@as(c_int, 448))));
    if (-@as(c_int, 1) == status) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, strerror(__errno_location().*));
        return 2;
    }
    lua_pushboolean(L, 1);
    return 1;
}
pub fn tui_fstatus(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    const src: [*c]const u8 = luaL_checklstring(L, 2, null);
    var s: struct_stat = undefined;
    if (-@as(c_int, 1) == fstatat(ib.*.cwd_fd, src, &s, 4096 | 256)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, strerror(__errno_location().*));
        return 2;
    }
    lua_pushboolean(L, 1);
    if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 61440)))) == @as(mode_t, @bitCast(@as(c_int, 16384)))) {
        lua_pushstring(L, "directory");
    } else if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 61440)))) == @as(mode_t, @bitCast(@as(c_int, 32768)))) {
        lua_pushstring(L, "file");
    } else if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 61440)))) == @as(mode_t, @bitCast(@as(c_int, 4096)))) {
        lua_pushstring(L, "fifo");
    } else if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 61440)))) == @as(mode_t, @bitCast(@as(c_int, 49152)))) {
        lua_pushstring(L, "socket");
    } else if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 61440)))) == @as(mode_t, @bitCast(@as(c_int, 40960)))) {
        lua_pushstring(L, "link");
    } else {
        lua_pushstring(L, "unknown");
    }
    if (!luaL_optbnumber(L, 3, @as(lua_Number, @floatFromInt(@as(c_int, 0))))) return 2;
    lua_createtable(L, 0, 0);
    lua_pushstring(L, "size");
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(s.st_size)));
    lua_rawset(L, -3);
    lua_pushstring(L, "inode");
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(s.st_ino)));
    lua_rawset(L, -3);
    lua_pushstring(L, "mode");
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(s.st_mode)));
    lua_rawset(L, -3);
    if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 61440)))) == @as(mode_t, @bitCast(@as(c_int, 40960)))) {
        lua_pushstring(L, "link");
        var buf: [16384]u8 = undefined;
        const sz: isize = readlinkat(ib.*.cwd_fd, src, @ptrCast(&buf[0]), @sizeOf([16384]u8));
        if (sz > 0) {
            lua_pushlstring(L, @ptrCast(&buf[0]), @as(usize, @bitCast(sz)));
        } else {
            lua_pushstring(L, "(bad)");
        }
        lua_rawset(L, -3);
    }
    lua_pushstring(L, "mode_string");
    var modestr: [10:0]u8 = "----------".*;
    if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 2048) | @as(c_int, 1024)))) != 0) {
        modestr[0] = 's';
    }
    if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 256)))) != 0) {
        modestr[1] = 'r';
    }
    if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 128)))) != 0) {
        modestr[2] = 'w';
    }
    if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 64)))) != 0) {
        modestr[3] = 'x';
    }
    if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 256) >> @intCast(3)))) != 0) {
        modestr[4] = 'r';
    }
    if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 128) >> @intCast(3)))) != 0) {
        modestr[5] = 'w';
    }
    if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 64) >> @intCast(3)))) != 0) {
        modestr[6] = 'x';
    }
    if ((s.st_mode & @as(mode_t, @bitCast((@as(c_int, 256) >> @intCast(3)) >> @intCast(3)))) != 0) {
        modestr[7] = 'r';
    }
    if ((s.st_mode & @as(mode_t, @bitCast((@as(c_int, 128) >> @intCast(3)) >> @intCast(3)))) != 0) {
        modestr[8] = 'w';
    }
    if ((s.st_mode & @as(mode_t, @bitCast((@as(c_int, 64) >> @intCast(3)) >> @intCast(3)))) != 0) {
        modestr[9] = 'x';
    }
    lua_pushstring(L, @ptrCast(&modestr[0]));
    lua_rawset(L, -3);
    lua_pushstring(L, "gid");
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(s.st_gid)));
    lua_rawset(L, -3);
    lua_pushstring(L, "uid");
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(s.st_uid)));
    lua_rawset(L, -3);
    lua_pushstring(L, "ctime");
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(s.st_ctim.tv_sec)));
    lua_rawset(L, -3);
    lua_pushstring(L, "mtime");
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(s.st_mtim.tv_sec)));
    lua_rawset(L, -3);
    lua_pushstring(L, "atime");
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(s.st_atim.tv_sec)));
    lua_rawset(L, -3);
    const pw: [*c]struct_passwd = getpwuid(s.st_uid);
    lua_pushstring(L, "user");
    if (pw == null) {
        lua_pushstring(L, "[missing]");
    } else {
        lua_pushstring(L, pw.*.pw_name);
    }
    lua_rawset(L, -3);
    const gr: [*c]struct_group = getgrgid(s.st_gid);
    lua_pushstring(L, "group");
    if (gr == null) {
        lua_pushstring(L, "[missing]");
    } else {
        lua_pushstring(L, gr.*.gr_name);
    }
    lua_rawset(L, -3);
    return 3;
}
pub fn tui_frename(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    const src: [*c]const u8 = luaL_checklstring(L, 2, null);
    const dst: [*c]const u8 = luaL_checklstring(L, 3, null);
    const rv: c_int = renameat(ib.*.cwd_fd, src, ib.*.cwd_fd, dst);
    if (rv == -1) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, strerror(__errno_location().*));
        return 2;
    }
    lua_pushboolean(L, 1);
    return 1;
}
pub fn tui_fchmod(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    const name: [*c]const u8 = luaL_checklstring(L, 2, null);
    const number: c_int = @intFromFloat(luaL_checknumber(L, 3));
    if (-@as(c_int, 1) == ib.*.cwd_fd) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "invalid current working directory");
        return 2;
    }
    if (-@as(c_int, 1) == fchmodat(ib.*.cwd_fd, name, @as(mode_t, @bitCast(number)), 0)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, strerror(__errno_location().*));
        return 2;
    }
    lua_pushboolean(L, 1);
    return 1;
}
pub fn tui_fchown(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    const name: [*c]const u8 = luaL_checklstring(L, 2, null);
    const user: [*c]const u8 = luaL_optlstring(L, 3, "", null);
    const group_1: [*c]const u8 = luaL_optlstring(L, 4, "", null);
    var uid: c.uid_t = @as(c.uid_t, @bitCast(-@as(c_int, 1)));
    var gid: c.gid_t = @as(c.gid_t, @bitCast(-@as(c_int, 1)));
    if (user.* != 0) {
        const pw: [*c]struct_passwd = getpwnam(user);
        if (pw == null) {
            lua_pushboolean(L, 0);
            lua_pushstring(L, "invalid user");
            return 2;
        }
        uid = pw.*.pw_uid;
    }
    if (group_1.* != 0) {
        const gdata: [*c]struct_group = getgrnam(group_1);
        if (gdata == null) {
            lua_pushboolean(L, 0);
            lua_pushstring(L, "invalid group");
            return 2;
        }
        gid = gdata.*.gr_gid;
    }
    if (-@as(c_int, 1) == fchownat(ib.*.cwd_fd, name, uid, gid, 0)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, strerror(__errno_location().*));
        return 2;
    }
    lua_pushboolean(L, 1);
    return 1;
}
pub fn tui_funlink(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    const name: [*c]const u8 = luaL_checklstring(L, 2, null);
    if (-@as(c_int, 1) == ib.*.cwd_fd) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "invalid current working directory");
        return 2;
    }
    var s: struct_stat = undefined;
    if (-@as(c_int, 1) == fstatat(ib.*.cwd_fd, name, &s, 4096 | 256)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, strerror(__errno_location().*));
        return 2;
    }
    var fl: c_int = 0;
    if ((s.st_mode & @as(mode_t, @bitCast(@as(c_int, 61440)))) == @as(mode_t, @bitCast(@as(c_int, 16384)))) {
        fl = 512;
    }
    if (-@as(c_int, 1) == unlinkat(ib.*.cwd_fd, name, fl)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, strerror(__errno_location().*));
        return 2;
    }
    lua_pushboolean(L, 1);
    return 1;
}
pub fn tui_fopen(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    const name: [*c]const u8 = luaL_checklstring(L, 2, null);
    const mode: [*c]const u8 = luaL_optlstring(L, 3, "r", null);
    var omode: mode_t = 0;
    var flags: c_int = 0;
    if (strcmp(mode, "r") == 0) {
        omode = 0;
    } else if (strcmp(mode, "w") == 0) {
        omode = 1;
        flags = 64;
    } else if (strcmp(mode, "a") == 0) {
        omode = 1;
        flags = 64 | 1024;
    } else if (strcmp(mode, "fifo-in") == 0) {
        omode = @as(mode_t, @bitCast(@as(c_int, 0) | @as(c_int, 2048)));
        _ = c.mkfifo(name, @as(mode_t, @bitCast(@as(c_int, 256) | @as(c_int, 128))));
    } else if (strcmp(mode, "unix") == 0) {
        var unlink_fn: [*c]u8 = undefined;
        const fd: c_int = alt_nbio_socket(name, 0, &unlink_fn);
        if (fd != -1) {
            _ = alt_nbio_import(L, fd, @as(mode_t, @bitCast(@as(c_int, 2))), null, &unlink_fn);
            alt_nbio_nonblock_cloexec(fd, true);
            return 1;
        }
        lua_pushboolean(L, 0);
        lua_pushstring(L, strerror(__errno_location().*));
        return 2;
    } else {
        _ = luaL_error(L, "unsupported file mode, expected 'r', 'w', 'a' or 'unix'");
    }
    const fd: c_int = openat(ib.*.cwd_fd, name, @as(c_int, @bitCast(omode | @as(mode_t, @bitCast(flags)))), @as(c_int, 384));
    if (-@as(c_int, 1) == fd) {
        lua_pushboolean(L, 0);
        return 1;
    }
    _ = alt_nbio_import(L, fd, omode, null, null);
    return 1;
}
pub fn tui_fbond(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    const src: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, 2, "nonblockIO")));
    const dst: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, 3, "nonblockIO")));
    if (src.* == null) {
        _ = luaL_error(L, "trying to use a closed source blobio");
    }
    if (dst.* == null) {
        _ = luaL_error(L, "trying to use a closed destination blobio");
    }
    const sio: [*c]struct_nonblock_io = src.*;
    const dio: [*c]struct_nonblock_io = dst.*;
    if (sio.*.mode == @as(mode_t, @bitCast(@as(c_int, 1)))) {
        _ = luaL_error(L, "source is write-only");
    }
    if (dio.*.mode == @as(mode_t, @bitCast(@as(c_int, 0)))) {
        _ = luaL_error(L, "destination is read-only");
    }
    var pair: [2]c_int = undefined;
    if (-@as(c_int, 1) == pipe(@ptrCast(&pair[0]))) {
        lua_pushboolean(L, 0);
        return 1;
    }
    const fdin: c_int = sio.*.fd;
    const fdout: c_int = dio.*.fd;
    sio.*.fd = -1;
    dio.*.fd = -1;
    const optstr: [*c]const u8 = luaL_optlstring(L, 4, "", null);
    var flags: c_int = 0;
    if (strchr(optstr, 'r') == null) {
        _ = alt_nbio_close(L, src);
    } else {
        flags |= TUI_BGCOPY_KEEPIN;
    }
    if (strchr(optstr, 'w') == null) {
        _ = alt_nbio_close(L, dst);
    } else {
        flags |= TUI_BGCOPY_KEEPOUT;
    }
    if (strchr(optstr, 'p') != null) {
        flags |= TUI_BGCOPY_PROGRESS;
    }
    _ = fcntl(pair[0], 2, fcntl(pair[0], 1) | 1);
    _ = fcntl(pair[1], 2, fcntl(pair[0], 1) | 1);
    var ret: [*c]struct_nonblock_io = undefined;
    _ = alt_nbio_import(L, pair[0], @as(mode_t, @bitCast(@as(c_int, 0))), &ret, null);
    if (ret != null) {
        arcan_tui_bgcopy(ib.*.unnamed_0.tui, fdin, fdout, pair[1], flags);
    }
    return 1;
}
pub fn tui_getenv(L: ?*lua_State) callconv(.c) c_int {
    var ci: usize = 1;
    if (lua_type(L, @as(c_int, @bitCast(@as(c_uint, @truncate(ci))))) == 7) {
        ci +%= 1;
    }
    const key: [*c]const u8 = luaL_optlstring(L, @as(c_int, @bitCast(@as(c_uint, @truncate(ci)))), null, null);
    if (key != null) {
        const val: [*c]const u8 = getenv(key);
        if (val != null) {
            lua_pushstring(L, val);
        } else {
            lua_pushnil(L);
        }
        return 1;
    }
    const ExternLocal_environ = struct {
        extern var environ: [*c][*c]u8;
    };
    var pos: usize = 0;
    lua_createtable(L, 0, 0);
    while (ExternLocal_environ.environ[pos] != null) {
        const key_1: [*c]u8 = ExternLocal_environ.environ[pos];
        const val: [*c]u8 = strchr(key_1, '=');
        if (val != null) {
            const len: usize = @intFromPtr(val) -% @intFromPtr(key_1);
            lua_pushlstring(L, key_1, len);
            lua_pushstring(L, &val[1]);
        } else {
            lua_pushstring(L, ExternLocal_environ.environ[pos]);
            lua_pushboolean(L, 1);
        }
        lua_rawset(L, -3);
        pos +%= 1;
    }
    return 1;
}
pub fn tui_tpack(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    var buf: [*c]u8 = undefined;
    var buf_sz: usize = undefined;
    if (arcan_tui_tpack(ib.*.unnamed_0.tui, &buf, &buf_sz)) {
        lua_pushlstring(L, @ptrCast(@alignCast(buf)), buf_sz);
        free(@as(?*anyopaque, @ptrCast(buf)));
    } else {
        lua_pushnil(L);
    }
    return 1;
}
pub fn debug(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    dump_state(ib);
    return 0;
}
pub fn tui_screencopy(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    const x1: usize = @intFromFloat(luaL_checknumber(L, 2));
    const y1: usize = @intFromFloat(luaL_checknumber(L, 3));
    const x2: usize = @intFromFloat(luaL_checknumber(L, 4));
    const y2: usize = @intFromFloat(luaL_checknumber(L, 5));
    const db: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 6, "Arcan TUI")));
    if (db == null or db.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context on dst");
    }
    const dx: usize = @intFromFloat(luaL_optnumber(L, 7, @as(lua_Number, @floatFromInt(@as(c_int, 0)))));
    const dy: usize = @intFromFloat(luaL_optnumber(L, 8, @as(lua_Number, @floatFromInt(@as(c_int, 0)))));
    arcan_tui_screencopy(ib.*.unnamed_0.tui, db.*.unnamed_0.tui, x1, y1, x2, y2, dx, dy);
    return 0;
}
pub fn tui_tunpack(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    var len: usize = undefined;
    const buf: [*c]const u8 = luaL_checklstring(L, 2, &len);
    var rows: usize = undefined;
    var cols: usize = undefined;
    arcan_tui_dimensions(ib.*.unnamed_0.tui, &rows, &cols);
    const x: usize = @intFromFloat(luaL_optnumber(L, 3, @as(lua_Number, @floatFromInt(@as(c_int, 0)))));
    const y: usize = @intFromFloat(luaL_optnumber(L, 4, @as(lua_Number, @floatFromInt(@as(c_int, 0)))));
    const w: usize = @intFromFloat(luaL_optnumber(L, 5, @as(lua_Number, @floatFromInt(@as(c_int, 0)))));
    const h: usize = @intFromFloat(luaL_optnumber(L, 6, @as(lua_Number, @floatFromInt(@as(c_int, 0)))));
    lua_pushboolean(L, @intFromBool(arcan_tui_tunpack(ib.*.unnamed_0.tui, @ptrCast(@constCast(@volatileCast(buf))), len, x, y, w, h)));
    return 1;
}
pub fn popen_wrap(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    if ((-@as(c_int, 1) == ib.*.cwd_fd) or (-@as(c_int, 1) == fchdir(ib.*.cwd_fd))) {
        if (ib.*.cwd) |cwd_ptr| {
            _ = chdir(@as([*c]const u8, @ptrCast(@alignCast(cwd_ptr))));
        }
    }
    return tui_popen(L);
}
pub fn tui_hasglyph(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c]struct_tui_lmeta = @ptrCast(@alignCast(luaL_checkudata(L, 1, "Arcan TUI")));
    if (ib == null or ib.*.unnamed_0.tui == null) {
        _ = luaL_error(L, if (ib == null) "no userdata" else "no tui context");
    }
    var cp: u32 = 0;
    if (lua_type(L, -1) == 3) {
        cp = @intFromFloat(lua_tonumber(L, -1));
    } else if (lua_type(L, -1) == 4) {
        const buf: [*c]const u8 = lua_tolstring(L, -1, null);
        var work: [4]u8 = [1]u8{
            0,
        } ++ [1]u8{0} ** 3;
        {
            var i: usize = 0;
            while ((i < 4) and (@as(c_int, @bitCast(@as(c_uint, buf[i]))) != 0)) : (i +%= 1) {
                work[i] = buf[i];
            }
        }
        if (@as(isize, @bitCast(@as(isize, -@as(c_int, 1)))) == arcan_tui_utf8ucs4(@ptrCast(&work[0]), &cp)) {
            lua_pushboolean(L, 0);
            lua_pushboolean(L, 0);
            return 2;
        }
    } else {
        _ = luaL_error(L, "has_glyph: expected u32-cp (number) or utf8- string");
    }
    lua_pushboolean(L, @intFromBool(arcan_tui_hasglyph(ib.*.unnamed_0.tui, cp)));
    lua_pushboolean(L, 1);
    return 2;
}
