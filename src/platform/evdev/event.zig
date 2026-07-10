// Zig port of platform/evdev/event.c — Linux evdev input platform layer
//
// Copyright 2014-2020, Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: http://arcan-fe.com

const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ ... })` block. libc routes
// to `posix_libc`; linux/input.h UAPI routes to `evdev_types`; libxkbcommon
// is declared inline (no other Zig consumer). glob(3) / struct_stat / etc.
// come from posix_libc / shmif_types. Zero `@cImport`.
const libc = @import("posix");
const shmif_types = @import("shmif_types");
const evdev_types = @import("evdev_types");

// libxkbcommon — the bits the evdev handler needs. Hand-declared as `extern "c"`
// since no other Zig file consumes xkbcommon; the link happens via the shared
// library (dynamic or static, driven by build.zig).
const xkb = struct {
    pub const xkb_context = opaque {};
    pub const xkb_keymap = opaque {};
    pub const xkb_state = opaque {};

    pub const xkb_rule_names = extern struct {
        rules: [*c]const u8 = null,
        model: [*c]const u8 = null,
        layout: [*c]const u8 = null,
        variant: [*c]const u8 = null,
        options: [*c]const u8 = null,
    };

    pub const XKB_CONTEXT_NO_FLAGS: c_int = 0;
    pub const XKB_KEYMAP_COMPILE_NO_FLAGS: c_int = 0;
    pub const XKB_KEYMAP_FORMAT_TEXT_V1: c_int = 1;
    pub const XKB_KEY_UP: c_int = 0;
    pub const XKB_KEY_DOWN: c_int = 1;
    pub const XKB_STATE_MODS_EFFECTIVE: c_int = 0x08;

    pub extern "c" fn xkb_context_new(flags: c_int) ?*xkb_context;
    pub extern "c" fn xkb_keymap_new_from_names(
        ctx: ?*xkb_context,
        names: *const xkb_rule_names,
        flags: c_int,
    ) ?*xkb_keymap;
    pub extern "c" fn xkb_keymap_unref(keymap: ?*xkb_keymap) void;
    pub extern "c" fn xkb_keymap_get_as_string(
        keymap: ?*xkb_keymap,
        format: c_int,
    ) [*c]u8;
    pub extern "c" fn xkb_keymap_key_repeats(keymap: ?*xkb_keymap, key: u32) c_int;
    pub extern "c" fn xkb_state_new(keymap: ?*xkb_keymap) ?*xkb_state;
    pub extern "c" fn xkb_state_unref(state: ?*xkb_state) void;
    pub extern "c" fn xkb_state_update_key(
        state: ?*xkb_state,
        key: u32,
        direction: c_int,
    ) c_int;
    pub extern "c" fn xkb_state_serialize_mods(state: ?*xkb_state, components: c_int) u32;
    pub extern "c" fn xkb_state_key_get_consumed_mods(state: ?*xkb_state, key: u32) u32;
    pub extern "c" fn xkb_state_key_get_utf8(
        state: ?*xkb_state,
        key: u32,
        buffer: [*c]u8,
        size: usize,
    ) c_int;
};

const c = struct {
    // libc — unistd + fcntl + stdio + stdlib + ctype + string + poll.
    pub const close = libc.close;
    pub const fcntl = libc.fcntl;
    pub const read = libc.read;
    pub const write = libc.write;
    pub const poll = libc.poll;
    pub const pipe = libc.pipe;
    pub const free = libc.free;
    pub const malloc = libc.malloc;
    pub const realloc = libc.realloc;
    pub const memcmp = libc.memcmp;
    pub const snprintf = libc.snprintf;
    pub const strcmp = libc.strcmp;
    pub const strncmp = libc.strncmp;
    pub const strcasecmp = libc.strcasecmp;
    pub const strdup = libc.strdup;
    pub const strerror = libc.strerror;
    pub const strlen = libc.strlen;
    pub const strrchr = libc.strrchr;
    pub const isatty = libc.isatty;
    pub const tolower = libc.tolower;
    pub const fopen = libc.fopen;
    pub const fclose = libc.fclose;
    pub const fgets = libc.fgets;
    pub const fstat = libc.fstat;
    pub const stat = libc.stat;
    pub const readlink = libc.readlink;
    pub const getenv = libc.getenv;

    pub const FILE = libc.FILE;
    pub const struct_stat = libc.struct_stat;
    pub const pollfd = libc.struct_pollfd;

    // fcntl / errno / mode.
    pub const F_GETFD = libc.F_GETFD;
    pub const F_SETFD = libc.F_SETFD;
    pub const F_GETFL = libc.F_GETFL;
    pub const F_SETFL = libc.F_SETFL;
    pub const FD_CLOEXEC = libc.FD_CLOEXEC;
    pub const O_RDWR = libc.O_RDWR;
    pub const O_NONBLOCK = libc.O_NONBLOCK;
    pub const EAGAIN = libc.EAGAIN;
    pub const EINTR = libc.EINTR;
    pub const EACCES: c_int = 13;
    pub const EINVAL: c_int = 22;
    pub const _errno = std.c._errno;
    pub const S_IFCHR = libc.S_IFCHR;
    pub const S_IFBLK = libc.S_IFBLK;
    pub const POLLIN = libc.POLLIN;
    pub const POLLERR = libc.POLLERR;
    pub const POLLHUP = libc.POLLHUP;

    // linux/input.h UAPI
    pub const input_id = evdev_types.input_id;
    pub const input_absinfo = evdev_types.input_absinfo;
    pub const input_event = evdev_types.input_event;
    pub const EV_SYN = evdev_types.EV_SYN;
    pub const EV_KEY = evdev_types.EV_KEY;
    pub const EV_REL = evdev_types.EV_REL;
    pub const EV_ABS = evdev_types.EV_ABS;
    pub const EV_SW = evdev_types.EV_SW;
    pub const EV_LED = evdev_types.EV_LED;
    pub const EV_REP = evdev_types.EV_REP;
    pub const EV_MAX = evdev_types.EV_MAX;
    pub const KEY_F1 = evdev_types.KEY_F1;
    pub const KEY_F10 = evdev_types.KEY_F10;
    pub const KEY_MAX = evdev_types.KEY_MAX;
    pub const BTN_MOUSE = evdev_types.BTN_MOUSE;
    pub const BTN_LEFT = evdev_types.BTN_LEFT;
    pub const BTN_RIGHT = evdev_types.BTN_RIGHT;
    pub const BTN_MIDDLE = evdev_types.BTN_MIDDLE;
    pub const BTN_JOYSTICK = evdev_types.BTN_JOYSTICK;
    pub const BTN_GAMEPAD = evdev_types.BTN_GAMEPAD;
    pub const BTN_TOUCH = evdev_types.BTN_TOUCH;
    pub const BTN_WHEEL = evdev_types.BTN_WHEEL;
    pub const REL_X = evdev_types.REL_X;
    pub const REL_Y = evdev_types.REL_Y;
    pub const REL_Z = evdev_types.REL_Z;
    pub const REL_RX = evdev_types.REL_RX;
    pub const REL_RY = evdev_types.REL_RY;
    pub const REL_RZ = evdev_types.REL_RZ;
    pub const REL_HWHEEL = evdev_types.REL_HWHEEL;
    pub const REL_DIAL = evdev_types.REL_DIAL;
    pub const REL_WHEEL = evdev_types.REL_WHEEL;
    pub const REL_MAX = evdev_types.REL_MAX;
    pub const ABS_X = evdev_types.ABS_X;
    pub const ABS_Y = evdev_types.ABS_Y;
    pub const ABS_THROTTLE = evdev_types.ABS_THROTTLE;
    pub const ABS_HAT0X = evdev_types.ABS_HAT0X;
    pub const ABS_HAT3Y = evdev_types.ABS_HAT3Y;
    pub const ABS_DISTANCE = evdev_types.ABS_DISTANCE;
    pub const ABS_MT_SLOT = evdev_types.ABS_MT_SLOT;
    pub const ABS_MT_POSITION_X = evdev_types.ABS_MT_POSITION_X;
    pub const ABS_MT_POSITION_Y = evdev_types.ABS_MT_POSITION_Y;
    pub const ABS_MT_TRACKING_ID = evdev_types.ABS_MT_TRACKING_ID;
    pub const ABS_MT_PRESSURE = evdev_types.ABS_MT_PRESSURE;
    pub const ABS_MT_TOOL_Y = evdev_types.ABS_MT_TOOL_Y;
    pub const ABS_MAX = evdev_types.ABS_MAX;
    pub const LED_MAX = evdev_types.LED_MAX;
    pub const REP_DELAY = evdev_types.REP_DELAY;
    pub const REP_PERIOD = evdev_types.REP_PERIOD;

    // inotify
    pub const inotify_event = evdev_types.inotify_event;
    pub const inotify_init1 = evdev_types.inotify_init1;
    pub const inotify_add_watch = evdev_types.inotify_add_watch;
    pub const IN_CREATE = evdev_types.IN_CREATE;
    pub const IN_ISDIR = evdev_types.IN_ISDIR;
    pub const IN_CLOEXEC = evdev_types.IN_CLOEXEC;
    pub const IN_NONBLOCK = evdev_types.IN_NONBLOCK;

    // glob (from shmif_types).
    pub const glob_t = shmif_types.glob_t;
    pub const glob = shmif_types.glob;
    pub const globfree = shmif_types.globfree;

    // xkbcommon
    pub const xkb_context = xkb.xkb_context;
    pub const xkb_keymap = xkb.xkb_keymap;
    pub const xkb_state = xkb.xkb_state;
    pub const xkb_rule_names = xkb.xkb_rule_names;
    pub const XKB_CONTEXT_NO_FLAGS = xkb.XKB_CONTEXT_NO_FLAGS;
    pub const XKB_KEYMAP_COMPILE_NO_FLAGS = xkb.XKB_KEYMAP_COMPILE_NO_FLAGS;
    pub const XKB_KEYMAP_FORMAT_TEXT_V1 = xkb.XKB_KEYMAP_FORMAT_TEXT_V1;
    pub const XKB_KEY_UP = xkb.XKB_KEY_UP;
    pub const XKB_KEY_DOWN = xkb.XKB_KEY_DOWN;
    pub const XKB_STATE_MODS_EFFECTIVE = xkb.XKB_STATE_MODS_EFFECTIVE;
    pub const xkb_context_new = xkb.xkb_context_new;
    pub const xkb_keymap_new_from_names = xkb.xkb_keymap_new_from_names;
    pub const xkb_keymap_unref = xkb.xkb_keymap_unref;
    pub const xkb_keymap_get_as_string = xkb.xkb_keymap_get_as_string;
    pub const xkb_keymap_key_repeats = xkb.xkb_keymap_key_repeats;
    pub const xkb_state_new = xkb.xkb_state_new;
    pub const xkb_state_unref = xkb.xkb_state_unref;
    pub const xkb_state_update_key = xkb.xkb_state_update_key;
    pub const xkb_state_serialize_mods = xkb.xkb_state_serialize_mods;
    pub const xkb_state_key_get_consumed_mods = xkb.xkb_state_key_get_consumed_mods;
    pub const xkb_state_key_get_utf8 = xkb.xkb_state_key_get_utf8;
};

// Arcan types — imported from canonical arcan_zig_types
const arcan_types = @import("arcan");
const arcan_evctx = opaque {};
const arcan_event = arcan_types.arcan_event;
const arcan_ioevent = arcan_types.arcan_ioevent;

// LED capabilities (from arcan_led.h)
const led_capabilities = extern struct {
    nleds: c_uint = 0,
    variable_brightness: bool = false,
    rgb: bool = false,
};

// Arcan constants
const ARCAN_ANALOGFILTER_NONE: c_int = 0;
const ARCAN_ANALOGFILTER_PASS: c_int = 1;
const ARCAN_ANALOGFILTER_AVG: c_int = 2;
const ARCAN_ANALOGFILTER_FORGET: c_int = 3;
const ARCAN_ANALOGFILTER_ALAST: c_int = 4;

const ARCAN_OK: c_int = 0;
const ARCAN_ERRC_NO_SUCH_OBJECT: c_int = -7;
const ARCAN_ERRC_BAD_RESOURCE: c_int = -8;

// Must match arcan_mem.h enum arcan_memtypes — VBUFFER=1, VSTRUCT, EXTSTRUCT,
// ABUFFER, STRINGBUF, SHARED, VTAG, ATAG, BINDING=9, MODELDATA, THREADCTX.
// Passing 0 falls into `else => abort()` inside posix/mem.zig's switch.
const ARCAN_MEM_BINDING: c_uint = 9;
const ARCAN_MEM_BZERO: c_uint = 1;
const ARCAN_MEMALIGN_NATURAL: c_uint = 0;

const ACAP_TRANSLATED: c_int = 1;
const ACAP_MOUSE: c_int = 2;
const ACAP_GAMING: c_int = 4;
const ACAP_TOUCH: c_int = 8;
const ACAP_POSITION: c_int = 16;
const ACAP_ORIENTATION: c_int = 32;

const EVENT_IO: c_uint = 2;
const EVENT_IO_BUTTON: c_uint = 0;
const EVENT_IO_AXIS_MOVE: c_uint = 1;
const EVENT_IO_TOUCH: c_uint = 2;
const EVENT_IO_STATUS: c_uint = 3;
const EVENT_IDATATYPE_ANALOG: c_uint = 1;
const EVENT_IDATATYPE_DIGITAL: c_uint = 2;
const EVENT_IDATATYPE_TRANSLATED: c_uint = 4;
const EVENT_IDATATYPE_TOUCH: c_uint = 8;
const EVENT_IDEVKIND_KEYBOARD: c_uint = 1;
const EVENT_IDEVKIND_MOUSE: c_uint = 2;
const EVENT_IDEVKIND_GAMEDEV: c_uint = 4;
const EVENT_IDEVKIND_TOUCHDISP: c_uint = 8;
const EVENT_IDEVKIND_STATUS: c_uint = 64;
const EVENT_IDEV_ADDED: c_int = 0;
const EVENT_IDEV_REMOVED: c_int = 1;
const EVENT_TRANSLATION_CLEAR: c_int = 0;
const EVENT_TRANSLATION_SET: c_int = 1;
const EVENT_TRANSLATION_SERIALIZE_CURRENT: c_int = 2;
const EVENT_TRANSLATION_SERIALIZE_SPEC: c_int = 3;

// Modifier keys (from keycode_xlate.h / arcan_tuisym.h)
const ARKMOD_LSHIFT: c_uint = 0x0001;
const ARKMOD_RSHIFT: c_uint = 0x0002;
const ARKMOD_LCTRL: c_uint = 0x0040;
const ARKMOD_RCTRL: c_uint = 0x0080;
const ARKMOD_LALT: c_uint = 0x0100;
const ARKMOD_RALT: c_uint = 0x0200;
const ARKMOD_LMETA: c_uint = 0x0400;
const ARKMOD_RMETA: c_uint = 0x0800;
const ARKMOD_CAPS: c_uint = 0x2000;
const ARKMOD_MODE: c_uint = 0x4000;
const ARKMOD_REPEAT: c_uint = 0x8000;

// Keycode lookup table and functions (from keycode_xlate.h)
// klut is a lookup table indexed by linux scancode, returning a K_* constant
extern var klut: [512]c_uint;
extern fn init_keyblut() callconv(.c) void;
extern fn lookup_keycode(code: c_uint, mods: u16) u16;
extern fn lookup_character(code: c_uint, mods: u16, compose: bool) u16;

// K_* key constants (from keycode_xlate.h)
// SDL-compatible keysym values — must match keymap.zig and durian's KEYSYM_LABEL_LUT
const K_LSHIFT: c_uint = 304;
const K_RSHIFT: c_uint = 303;
const K_LALT: c_uint = 308;
const K_RALT: c_uint = 307;
const K_LCTRL: c_uint = 306;
const K_RCTRL: c_uint = 305;
const K_LMETA: c_uint = 310;
const K_RMETA: c_uint = 309;
const K_CAPSLOCK: c_uint = 301;
const K_COMPOSE: c_uint = 314;

// Arcan extern functions
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn arcan_event_enqueue(ctx: ?*arcan_evctx, ev: *arcan_event) c_int;
extern fn arcan_event_defaultctx() ?*arcan_evctx;
extern fn arcan_frametime() i64;
extern fn arcan_random(buf: ?*anyopaque, len: usize) void;
extern fn arcan_alloc_mem(sz: usize, mtype: c_uint, mflags: c_uint, malign: c_uint) ?*anyopaque;
extern fn arcan_led_known(vendor: u16, product: u16) bool;
extern fn arcan_led_init() void;
extern fn arcan_led_register(fd: c_int, devid: c_int, label: [*c]const u8, caps: led_capabilities) c_int;
extern fn arcan_led_remove(ctrlid: c_int) c_int;
extern fn arcan_strbuf_tempfile(buf: [*c]const u8, len: usize, err: ?*[*c]const u8) c_int;
extern fn platform_config_lookup(tag: *usize) ?*const fn ([*c]const u8, c_ushort, *[*c]u8, usize) callconv(.c) bool;
extern fn platform_device_open(name: [*c]const u8, flags: c_int) c_int;
extern fn platform_device_release(name: [*c]const u8, ind: c_int) void;

// Constants

// devnode_type enum values from device_db.h (can't @cInclude — function pointer issues)
const DEVNODE_KEYBOARD: c_uint = 0;
const DEVNODE_MOUSE: c_uint = 1;
const DEVNODE_GAME: c_uint = 2;
const DEVNODE_TOUCH: c_uint = 3;
const DEVNODE_SENSOR: c_uint = 4;
const DEVNODE_SWITCH: c_uint = 5;
const DEVNODE_MISSING: c_uint = 6;

// Linux ioctl helpers — @cImport translation of _IOC macro is broken in Zig 0.15
const _IOC_NRSHIFT: u5 = 0;
const _IOC_TYPESHIFT: u5 = 8;
const _IOC_SIZESHIFT: u5 = 16;
const _IOC_DIRSHIFT: u5 = 30;
const _IOC_READ: c_uint = 2;
const _IOC_WRITE: c_uint = 1;

fn _IOC(dir: c_uint, typ: c_uint, nr: c_uint, size: c_uint) c_uint {
    return (dir << _IOC_DIRSHIFT) | (typ << _IOC_TYPESHIFT) | (nr << _IOC_NRSHIFT) | (size << _IOC_SIZESHIFT);
}

fn EVIOCGBIT(ev: anytype, len: anytype) c_uint {
    return _IOC(_IOC_READ, 'E', 0x20 + @as(c_uint, @intCast(ev)), @as(c_uint, @intCast(len)));
}

fn EVIOCGABS(abs: anytype) c_uint {
    return _IOC(_IOC_READ, 'E', 0x40 + @as(c_uint, @intCast(abs)), @sizeOf(c.input_absinfo));
}

fn EVIOCGNAME(len: anytype) c_uint {
    return _IOC(_IOC_READ, 'E', 0x06, @as(c_uint, @intCast(len)));
}

fn EVIOCGUNIQ(len: anytype) c_uint {
    return _IOC(_IOC_READ, 'E', 0x08, @as(c_uint, @intCast(len)));
}

const EVIOCGID: c_uint = _IOC(_IOC_READ, 'E', 0x02, @sizeOf(c.input_id));
const EVIOCGRAB: c_uint = _IOC(_IOC_WRITE, 'E', 0x90, @sizeOf(c_int));
const EVIOCSREP: c_uint = 0x40084503; // _IOW('E', 0x03, unsigned int[2])

// Portable ioctl — musl takes (int, int, ...) while EVIOC* macros are c_uint.
// Declare with c_uint request to match EVIOC* types; ABI is identical.
extern "c" fn ioctl(fd: c_int, request: c_uint, ...) c_int;

const BADFD: c_int = -1;
const MAX_DEVICES: usize = 256;
const MAX_MT_SLOTS: usize = 5;
const NOTIFY_SCAN_DIR: [*:0]const u8 = "/dev/input";

// Types

const axis_opts = struct {
    mode: c_int = 0,
    oldmode: c_int = 0,
    lower: c_int = 0,
    upper: c_int = 0,
    deadzone: c_int = 0,
    inlzone: bool = false,
    inuzone: bool = false,
    indzone: bool = false,
    kernel_sz: c_int = 0,
    kernel_ofs: c_int = 0,
    flt_kernel: [64]i32 = [_]i32{0} ** 64,
};

const devnode_decode_cb = ?*const fn (?*arcan_evctx, *devnode) callconv(.c) void;

const evhandler = struct {
    name: ?[*:0]const u8 = null,
    type: c_uint = 0,
    handler: devnode_decode_cb = null,
    axis_mask: u64 = 0,
    button_mask: u64 = 0,
};

const devnode = struct {
    handle: c_int = BADFD,
    hnd: evhandler = .{},
    label: [256]u8 = [_]u8{0} ** 256,
    path: ?[*:0]u8 = null,
    devnum: u16 = 0,
    button_count: usize = 0,
    trace_count: u32 = 0,
    type: c_uint = DEVNODE_GAME,
    data: DevData = DevData{ .game = .{} },
    touch: TouchData = .{},
    led: LedData = .{},

    const DevData = union {
        sensor: SensorData,
        game: GameData,
        cursor: CursorData,
        keyboard: KeyboardData,
    };
    const SensorData = struct {
        data: axis_opts = .{},
    };
    const GameData = struct {
        axes: u16 = 0,
        buttons: u16 = 0,
        relofs: u16 = 0,
        hats: [16]i8 = [_]i8{0} ** 16,
        adata: ?[*]axis_opts = null,
    };
    const CursorData = struct {
        mx: u16 = 0,
        my: u16 = 0,
        flt: [2]axis_opts = .{ .{}, .{} },
    };
    const KeyboardData = struct {
        state: c_uint = 0,
        xkb_layout: ?*c.xkb_keymap = null,
        xkb_state: ?*c.xkb_state = null,
    };
    const TouchData = struct {
        active: bool = false,
        pending: bool = false,
        x: [MAX_MT_SLOTS]c_int = [_]c_int{0} ** MAX_MT_SLOTS,
        y: [MAX_MT_SLOTS]c_int = [_]c_int{0} ** MAX_MT_SLOTS,
        pressure: c_int = 0,
        size: c_int = 0,
        ind: c_int = 0,
    };
    const LedData = struct {
        gotled: bool = false,
        ctrlid: c_int = 0,
        ind: c_int = 0,
        fds: [2]c_int = .{ BADFD, BADFD },
    };
};

// Global State

var notify_scan_dir: ?[*:0]u8 = null;
const default_eacces_tries: c_int = 8;
const default_eacces_delay: c_int = 1000;

const PendingEntry = struct {
    path: ?[*:0]u8 = null,
    tries: c_int = 0,
    last_ts: i64 = 0,
};
var pending_devs: [8]PendingEntry = [_]PendingEntry{.{}} ** 8;

var gstate: struct {
    mute: bool = false,
    init: bool = false,
    tty: c_int = 0,
    notify: c_int = -1,
    pending: c_int = 0,
} = .{};

var iodev: struct {
    n_devs: usize = 0,
    sz_nodes: usize = 0,
    period: c_uint = 0,
    delay: c_uint = 0,
    mouseid: u16 = 0,
    nodes: ?[*]devnode = null,
    pollset: ?[*]c.pollfd = null,
} = .{};

var xkb_ctx: ?*c.xkb_context = null;

// envopts

const envopts = [_:null]?[*:0]const u8{
    "scandir=path/to/folder",
    "Directory to monitor for device node hotplug (Default: /dev/input)",
    "disable_ttyswap",
    "Disable tty- swapping signal handler",
    "[evdev_type=label]",
    "suffix evdev_type with _n for (n = 2, 3, ...)",
    "evdev_keyboard=label",
    "Force device matching 'label' as a keyboard",
    "evdev_game=label",
    "Force device matching 'label' as a game device",
    "evdev_mouse=label",
    "Force device matching 'label' as a mouse",
    "",
    "",
    "[XKB db keys]",
    "(libkbcommon specific, no ARCAN_ env prefix)",
    "event_xkb_rules",
    "Ruleset (evdev)",
    "event_xkb_variant",
    "Variant within the keymap (intl,dvorak)",
    "event_xkb_model",
    "Keyboard model (pc105)",
    "event_xkb_layout",
    "Layout groups (fr,us)",
    "event_xkb_options",
    "Mapping options (ctrl:nocaps)",
    "[XKB-ENVVARS]",
    "(might be blocked by suid, libxkbcommon)",
    "XKB_DEFAULT_LAYOUT=lang",
    "enable XKB translation maps for keyboards",
    "XKB_DEFAULT_VARIANT=variant",
    "define XKB layout variant",
    "XKB_DEFAULT_MODEL=pc101",
    "define XKB keyboard model",
    "XKB_DEFAULT_RULES=evdev",
    "define XKB ruleset",
};

// device_db static table (from device_db.h)

const device_db = [_]evhandler{
    .{ .name = "Microsoft X-Box 360 pad", .type = DEVNODE_GAME, .handler = defhandler_game },
    .{ .name = "ckb1", .type = DEVNODE_KEYBOARD, .handler = defhandler_kbd },
};

const defhandlers = [_]devnode_decode_cb{
    defhandler_kbd,
    defhandler_mouse,
    defhandler_game,
    defhandler_null,
    defhandler_null,
    defhandler_null,
    defhandler_null,
};

// Bit helpers

const BITS_PER_LONG = @sizeOf(c_ulong) * 8;

inline fn bit_longn(x: usize) usize {
    return x / BITS_PER_LONG;
}

inline fn bit_ofs(x: usize) std.math.Log2Int(c_ulong) {
    return @intCast(x % BITS_PER_LONG);
}

inline fn bit_isset(ary: [*]const c_ulong, bit: usize) bool {
    return ((ary[bit_longn(bit)] >> bit_ofs(bit)) & 1) != 0;
}

inline fn bit_count(x: usize) usize {
    return (x -| 1) / BITS_PER_LONG + 1;
}

// ══════════════════════════════════════════════════════════════════════
// Helper functions
// ══════════════════════════════════════════════════════════════════════

fn lookup_devnode(devid_in: c_int) ?*devnode {
    var devid = devid_in;
    if (devid <= 0)
        devid = @as(c_int, @intCast(iodev.mouseid));

    const nodes = iodev.nodes orelse return null;

    if (devid >= 0 and @as(usize, @intCast(devid)) < iodev.sz_nodes) {
        return &nodes[@intCast(devid)];
    }

    for (0..iodev.sz_nodes) |i| {
        if (nodes[i].devnum == @as(u16, @intCast(devid))) {
            return &nodes[i];
        }
    }

    return null;
}

fn identify(
    fd: c_int,
    path: [*]const u8,
    label: [*]u8,
    label_sz: usize,
    dnum: *u16,
) bool {
    if (ioctl(fd, EVIOCGNAME(@as(c_int, @intCast(label_sz))), label) == -1) {
        _ = c.snprintf(label, label_sz, "unknown");
    }

    var nodeid: c.input_id = std.mem.zeroes(c.input_id);
    if (ioctl(fd, EVIOCGID, &nodeid) == -1) {
        return false;
    }

    if (arcan_led_known(nodeid.vendor, nodeid.product)) {
        arcan_led_init();
        return false;
    }

    const bpl = @sizeOf(c_ulong) * 8;
    const nbits = (@as(usize, c.EV_MAX) - 1) / bpl + 1;
    const buf_size = 12 + nbits * @sizeOf(c_ulong);
    var buf: [buf_size]u8 = [_]u8{0} ** buf_size;
    var bbuf: [buf_size]u8 = [_]u8{0} ** buf_size;

    var hash: c_ulong = 5381;

    if (ioctl(fd, EVIOCGUNIQ(@as(c_int, @intCast(buf.len))), &buf) == -1 or
        c.memcmp(&buf, &bbuf, buf.len) == 0)
    {
        const llen = c.strlen(label);
        for (0..llen) |i| {
            hash = ((hash << 5) +% hash) +% label[i];
        }
        const plen = c.strlen(path);
        for (0..plen) |i| {
            hash = ((hash << 5) +% hash) +% path[i];
        }

        buf[11] ^= @truncate(nodeid.vendor >> 8);
        buf[10] ^= @truncate(nodeid.vendor);
        buf[9] ^= @truncate(nodeid.product >> 8);
        buf[8] ^= @truncate(nodeid.product);
        buf[7] ^= @truncate(nodeid.version >> 8);
        buf[6] ^= @truncate(nodeid.version);

        _ = ioctl(fd, EVIOCGBIT(@as(c_int, 0), @as(c_int, @intCast(buf.len))), &buf);
    }

    for (0..buf.len) |i| {
        hash = ((hash << 5) +% hash) +% buf[i];
    }

    hash &= 0xfffe;
    if (hash < MAX_DEVICES)
        hash += MAX_DEVICES;

    const nodes = iodev.nodes orelse {
        dnum.* = @truncate(hash);
        return true;
    };

    var si: isize = 0;
    while (si < @as(isize, @intCast(iodev.sz_nodes))) {
        if (hash == @as(c_ulong, nodes[@intCast(si)].devnum)) {
            var rv: u16 = undefined;
            arcan_random(@ptrCast(&rv), 2);
            hash = rv & @as(u16, 0xfffe);
            if (hash < MAX_DEVICES)
                hash += MAX_DEVICES;
            if (si > 0)
                si -= 1;
        } else {
            si += 1;
        }
    }

    dnum.* = @truncate(hash);
    return true;
}

fn process_axis(
    ctx: ?*arcan_evctx,
    daxis: *axis_opts,
    samplev_in: i16,
    outv: *i16,
) bool {
    _ = ctx;
    if (daxis.mode == ARCAN_ANALOGFILTER_NONE)
        return false;

    var samplev: i16 = samplev_in;

    if (daxis.mode != ARCAN_ANALOGFILTER_PASS) {
        // Saturating-clamp helpers — daxis.lower/upper/deadzone are c_int
        // and CAN exceed i16 when the device's EVIOCGABS-reported axis
        // bounds are huge (DualSense's motion-sensor / touchpad axes
        // report raw values that overflow i16). Without these clamps
        // process_axis panics on the @intCast(i16) — repro: pair a
        // DualSense, watch arcan crash within ~2s of the controller
        // emitting any motion-sensor axis event. Class of bug fixed in
        // commit-this-fix.
        const I16_MIN: i32 = -32768;
        const I16_MAX: i32 = 32767;
        const lo_i16: i16 = @intCast(@max(@as(i32, I16_MIN), @min(@as(i32, I16_MAX), @as(i32, daxis.lower))));
        const hi_i16: i16 = @intCast(@max(@as(i32, I16_MIN), @min(@as(i32, I16_MAX), @as(i32, daxis.upper))));
        const dz_i32: i32 = if (daxis.deadzone < 0) 0
            else if (daxis.deadzone > @as(c_int, 65535)) 65535
            else @as(i32, daxis.deadzone);

        const abs_sv: i32 = if (samplev < 0) -@as(i32, samplev) else @as(i32, samplev);
        if (abs_sv < dz_i32) {
            if (!daxis.indzone) {
                samplev = 0;
                daxis.indzone = true;
            } else {
                return false;
            }
        } else {
            daxis.indzone = false;
        }

        if (samplev < lo_i16) {
            if (!daxis.inlzone) {
                samplev = lo_i16;
                daxis.inlzone = true;
                daxis.inuzone = false;
            } else {
                return false;
            }
        } else if (samplev > hi_i16) {
            if (!daxis.inuzone) {
                samplev = hi_i16;
                daxis.inuzone = true;
                daxis.inlzone = false;
            } else {
                return false;
            }
        } else {
            daxis.inlzone = false;
            daxis.inuzone = false;
        }

        daxis.flt_kernel[@intCast(daxis.kernel_ofs)] = samplev;
        daxis.kernel_ofs += 1;

        if (daxis.kernel_ofs < daxis.kernel_sz)
            return false;

        if (daxis.kernel_sz > 1) {
            if (daxis.mode == ARCAN_ANALOGFILTER_ALAST) {
                samplev = @intCast(daxis.flt_kernel[@intCast(daxis.kernel_sz - 1)]);
            } else {
                var tot: i32 = 0;
                var ki: c_int = 0;
                while (ki < daxis.kernel_sz) : (ki += 1) {
                    tot += daxis.flt_kernel[@intCast(ki)];
                }
                if (tot != 0) {
                    const avg: i32 = @divTrunc(tot, daxis.kernel_sz);
                    // Saturating clamp — kernel-averaged samples can land
                    // outside i16 when the device reports oversize axes
                    // (same DualSense motion-sensor class as the bounds
                    // clamp above).
                    samplev = @intCast(@max(@as(i32, -32768), @min(@as(i32, 32767), avg)));
                } else samplev = 0;
            }
        }

        daxis.kernel_ofs = 0;
    }

    outv.* = samplev;
    return true;
}

fn set_analogstate(
    dst: *axis_opts,
    lower_bound: c_int,
    upper_bound: c_int,
    deadzone_val: c_int,
    kernel_size: c_int,
    mode: c_int,
) void {
    dst.lower = lower_bound;
    dst.upper = upper_bound;
    dst.deadzone = deadzone_val;
    dst.kernel_sz = kernel_size;
    dst.mode = mode;
    dst.kernel_ofs = 0;
}

fn find_axis(devid: c_int, axisid: c_uint, outn: *bool) ?*axis_opts {
    const node = lookup_devnode(devid);
    outn.* = (node != null);
    const n = node orelse return null;

    return switch (n.type) {
        DEVNODE_SENSOR => if (axisid == 0) &n.data.sensor.data else null,
        DEVNODE_GAME => blk: {
            if (axisid < n.data.game.axes) {
                break :blk &(n.data.game.adata orelse return null)[axisid];
            }
            break :blk null;
        },
        DEVNODE_MOUSE => blk: {
            if (axisid == 0) break :blk &n.data.cursor.flt[0];
            if (axisid == 1) break :blk &n.data.cursor.flt[1];
            break :blk null;
        },
        else => null,
    };
}

fn lookup_type(val: c_uint) [*:0]const u8 {
    return switch (val) {
        DEVNODE_GAME => "game",
        DEVNODE_MOUSE => "mouse",
        DEVNODE_SENSOR => "sensor",
        DEVNODE_KEYBOARD => "keyboard",
        else => "unknown",
    };
}

fn button_count(fd: c_int, bitn: usize, got_mouse: *bool, got_joy: *bool) usize {
    var count: usize = 0;
    var bits: [bit_count(c.KEY_MAX)]c_ulong = undefined;

    if (ioctl(fd, EVIOCGBIT(@as(c_int, @intCast(bitn)), @as(c_int, @intCast(@sizeOf(@TypeOf(bits))))), &bits) == -1)
        return 0;

    for (0..@as(usize, c.KEY_MAX)) |i| {
        if (bit_isset(&bits, i))
            count += 1;
    }

    got_mouse.* = (bit_isset(&bits, c.BTN_MOUSE) or bit_isset(&bits, c.BTN_LEFT) or
        bit_isset(&bits, c.BTN_RIGHT) or bit_isset(&bits, c.BTN_MIDDLE));

    got_joy.* = (bit_isset(&bits, c.BTN_JOYSTICK) or bit_isset(&bits, c.BTN_GAMEPAD) or
        bit_isset(&bits, c.BTN_WHEEL));

    return count;
}

fn check_mouse_axis(fd: c_int, bitn: usize) bool {
    var bits: [bit_count(c.KEY_MAX)]c_ulong = undefined;
    if (ioctl(fd, EVIOCGBIT(@as(c_int, @intCast(bitn)), @as(c_int, @intCast(@sizeOf(@TypeOf(bits))))), &bits) == -1)
        return false;
    return bit_isset(&bits, c.REL_X) and bit_isset(&bits, c.REL_Y);
}

fn to_utf8(utf16: u16, out: *[5]u8) void {
    var cnt: u32 = 1;
    var mask: u32 = 0x800;

    if (utf16 >= 0x80)
        cnt += 1;

    for (0..5) |_| {
        if (@as(u32, utf16) >= mask)
            cnt += 1;
        mask <<= 5;
    }

    if (cnt == 1) {
        out[0] = @truncate(utf16);
        out[1] = 0;
    } else {
        var ofs: u32 = 0;
        var ci: i32 = @intCast(if (cnt - 1 > 4) @as(u32, 4) else cnt - 1);
        while (ci >= 0) : (ci -= 1) {
            const shift: u5 = @intCast(@as(u32, @intCast(ci)) * 6);
            var ch: u8 = @truncate((@as(u32, utf16) >> shift) & 0x3f);
            ch |= 0x80;
            if (@as(u32, @intCast(ci)) == cnt - 1)
                ch |= @truncate(@as(u32, 0xff) << @intCast(8 - cnt));
            out[ofs] = ch;
            ofs += 1;
        }
        out[ofs] = 0;
    }
}

fn map_axes(fd: c_int, bitn: usize, node: *devnode) void {
    var bits: [bit_count(c.ABS_MAX)]c_ulong = undefined;

    if (node.data.game.adata != null)
        return;
    node.data.game.axes = 0;

    if (ioctl(fd, EVIOCGBIT(@as(c_int, @intCast(bitn)), @as(c_int, @intCast(@sizeOf(@TypeOf(bits))))), &bits) != -1) {
        for (0..@as(usize, c.ABS_MAX)) |i| {
            if (bit_isset(&bits, i))
                node.data.game.axes += 1;
        }
    }

    node.data.game.relofs = node.data.game.axes;
    var rel_bits: [bit_count(c.REL_MAX)]c_ulong = undefined;
    if (ioctl(fd, EVIOCGBIT(@as(c_int, c.EV_REL), @as(c_int, @intCast(@sizeOf(@TypeOf(rel_bits))))), &rel_bits) != -1) {
        for (0..@as(usize, c.REL_MAX)) |i| {
            if (bit_isset(&rel_bits, i))
                node.data.game.axes += 1;
        }
    }

    if (node.data.game.axes == 0)
        return;

    node.data.game.adata = @ptrCast(@alignCast(arcan_alloc_mem(
        @sizeOf(axis_opts) * @as(usize, node.data.game.axes),
        ARCAN_MEM_BINDING,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    )));

    var ac: usize = 0;
    for (0..@as(usize, c.ABS_MAX)) |i| {
        if (bit_isset(&bits, i)) {
            var ainf: c.input_absinfo = undefined;
            const ax_ptr = node.data.game.adata orelse return;
            const ax: *axis_opts = &ax_ptr[ac];
            ac += 1;

            ax.* = .{};
            ax.mode = ARCAN_ANALOGFILTER_AVG;
            ax.oldmode = ARCAN_ANALOGFILTER_AVG;
            ax.lower = -32768;
            ax.upper = 32767;

            if (ioctl(fd, EVIOCGABS(@as(c_int, @intCast(i))), &ainf) == -1)
                continue;

            ax.upper = ainf.maximum;
            ax.lower = ainf.minimum;
        }
    }
}

fn setup_led(dst: *devnode, bitn: usize, fd: c_int) void {
    var bits: [bit_count(c.LED_MAX)]c_ulong = undefined;
    if (ioctl(fd, EVIOCGBIT(@as(c_int, @intCast(bitn)), @as(c_int, @intCast(@sizeOf(@TypeOf(bits))))), &bits) == -1)
        return;

    var cnt: usize = 0;
    for (0..@as(usize, c.LED_MAX)) |i| {
        if (bit_isset(&bits, i))
            cnt += 1;
    }
    if (cnt == 0) return;

    if (c.pipe(&dst.led.fds) == -1)
        return;

    for (0..2) |i| {
        var flags = c.fcntl(dst.led.fds[i], c.F_GETFL);
        if (flags != -1)
            _ = c.fcntl(dst.led.fds[i], c.F_SETFL, flags | c.O_NONBLOCK);
        flags = c.fcntl(dst.led.fds[i], c.F_GETFD);
        if (flags != -1)
            _ = c.fcntl(dst.led.fds[i], c.F_SETFD, flags | c.FD_CLOEXEC);
    }

    var ledname: [16]u8 = undefined;
    _ = c.snprintf(&ledname, 16, "%d_led", @as(c_int, @intCast(dst.devnum)));
    dst.led.ctrlid = arcan_led_register(
        dst.led.fds[1],
        @intCast(dst.devnum),
        &ledname,
        led_capabilities{
            .nleds = c.LED_MAX,
            .variable_brightness = false,
            .rgb = false,
        },
    );
    if (dst.led.ctrlid == -1) {
        _ = c.close(dst.led.fds[0]);
        _ = c.close(dst.led.fds[1]);
        dst.led.fds = .{ -1, -1 };
        return;
    }
    dst.led.gotled = true;
    for (0..@as(usize, c.LED_MAX)) |i| {
        var ev_led = std.mem.zeroes(c.input_event);
        ev_led.type = c.EV_LED;
        ev_led.code = @intCast(i);
        ev_led.value = 0;
        _ = c.write(dst.handle, &ev_led, @sizeOf(c.input_event));
    }
}

fn xkb_layout_to_fd(layout: ?*c.xkb_keymap, err: *[*:0]const u8) c_int {
    if (layout == null) {
        err.* = "no active map";
        return -1;
    }
    const map_str = c.xkb_keymap_get_as_string(layout, c.XKB_KEYMAP_FORMAT_TEXT_V1);
    if (map_str == null) {
        err.* = "serialization request rejected";
        return -1;
    }
    return arcan_strbuf_tempfile(map_str, c.strlen(map_str) + 1, @ptrCast(err));
}

fn alloc_node_slot(path: [*]const u8) c_int {
    var hole: c_int = -1;
    const nodes = iodev.nodes orelse {
        // No nodes yet, must grow
        return alloc_grow();
    };

    for (0..iodev.sz_nodes) |i| {
        if (hole == -1 and nodes[i].handle < 0) {
            hole = @intCast(i);
            continue;
        }
        if (nodes[i].path) |p| {
            if (c.strcmp(p, path) == 0) {
                _ = c.close(nodes[i].handle);
                iodev.n_devs -|= 1;
                return @intCast(i);
            }
        }
    }

    if (hole == -1)
        return alloc_grow();

    return hole;
}

fn alloc_grow() c_int {
    const new_cnt = iodev.sz_nodes + 8;
    const nn: ?[*]devnode = @ptrCast(@alignCast(c.realloc(
        @as(?*anyopaque, @ptrCast(iodev.nodes)),
        @sizeOf(devnode) * new_cnt,
    )));
    if (nn == null) return -1;
    iodev.nodes = nn;
    // zero-init new entries
    for (iodev.sz_nodes..new_cnt) |i| {
        nn.?[i] = devnode{};
    }

    const newset: ?[*]c.pollfd = @ptrCast(@alignCast(c.malloc(
        2 * @sizeOf(c.pollfd) * new_cnt,
    )));
    if (newset == null) return -1;

    if (iodev.pollset) |old| c.free(@ptrCast(old));
    for (0..new_cnt) |i| {
        newset.?[i] = std.mem.zeroes(c.pollfd);
        newset.?[i + new_cnt] = std.mem.zeroes(c.pollfd);
        newset.?[i].events = c.POLLIN | c.POLLERR | c.POLLHUP;
        newset.?[i].fd = nn.?[i].handle;
        newset.?[i + new_cnt].events = c.POLLIN;
        newset.?[i + new_cnt].fd = nn.?[i].led.fds[0];
    }

    iodev.pollset = newset;
    const hole: c_int = @intCast(iodev.sz_nodes);
    iodev.sz_nodes = new_cnt;
    return hole;
}

fn send_device_added(ctx: ?*arcan_evctx, node: *devnode) void {
    var addev = arcan_event.zeroes();
    addev.unnamed_0.unnamed_0.category = @intCast(EVENT_IO);
    addev.unnamed_0.unnamed_0.unnamed_0.io.kind = EVENT_IO_STATUS;
    addev.unnamed_0.unnamed_0.unnamed_0.io.devkind = EVENT_IDEVKIND_STATUS;
    addev.unnamed_0.unnamed_0.unnamed_0.io.devid = node.devnum;
    addev.unnamed_0.unnamed_0.unnamed_0.io.input.status.devkind = @truncate(node.type);
    addev.unnamed_0.unnamed_0.unnamed_0.io.input.status.action = EVENT_IDEV_ADDED;

    _ = c.snprintf(
        @as([*c]u8, @ptrCast(&addev.unnamed_0.unnamed_0.unnamed_0.io.label)),
        @sizeOf(@TypeOf(addev.unnamed_0.unnamed_0.unnamed_0.io.label)),
        "%s",
        @as([*c]const u8, @ptrCast(&node.label)),
    );
    _ = arcan_event_enqueue(ctx, &addev);
}

// ══════════════════════════════════════════════════════════════════════
// Device discovery & management
// ══════════════════════════════════════════════════════════════════════

fn discovered(ctx: ?*arcan_evctx, name: [*]const u8, name_len: usize, nopending: bool) bool {
    var buffer: [4096]u8 = undefined;
    var outbuffer: [4096]u8 = undefined;

    _ = c.snprintf(
        &buffer,
        buffer.len,
        "%s/%.*s",
        notify_scan_dir,
        @as(c_int, @intCast(name_len)),
        name,
    );

    const rl = c.readlink(&buffer, &outbuffer, outbuffer.len);
    const open_path: [*c]const u8 = if (rl > 0) @ptrCast(&outbuffer) else @ptrCast(&buffer);
    const fd = platform_device_open(open_path, c.O_NONBLOCK | c.O_RDWR);

    if (fd == -1 and std.c._errno().* == c.EACCES) {
        if (gstate.pending >= @as(c_int, @intCast(pending_devs.len)))
            return false;

        if (nopending)
            return false;

        var j: isize = -1;
        for (0..pending_devs.len) |i| {
            if (pending_devs[i].path == null and j == -1)
                j = @intCast(i);
            if (pending_devs[i].path) |p| {
                if (c.strncmp(name, p, name_len) == 0)
                    return false;
            }
        }

        if (j < 0) return false;
        const ji: usize = @intCast(j);
        gstate.pending += 1;
        pending_devs[ji].path = @ptrCast(c.malloc(name_len + 1));
        if (pending_devs[ji].path) |p| {
            _ = c.snprintf(p, name_len + 1, "%.*s", @as(c_int, @intCast(name_len)), name);
        }
        pending_devs[ji].tries = default_eacces_tries;
        pending_devs[ji].last_ts = arcan_frametime();
        return false;
    }

    if (fd != -1) {
        got_device(ctx, fd, open_path);
        return true;
    } else {
        arcan_warning("input: couldn't open new device (%s), reason: %s\n", name, c.strerror(std.c._errno().*));
    }
    return false;
}

fn process_pending(ctx: ?*arcan_evctx) void {
    for (0..pending_devs.len) |i| {
        const p = pending_devs[i].path orelse continue;

        if (arcan_frametime() - pending_devs[i].last_ts <
            @as(i64, (default_eacces_tries - pending_devs[i].tries + 1)) * @as(i64, default_eacces_delay))
            continue;

        pending_devs[i].last_ts = arcan_frametime();

        if (discovered(ctx, p, c.strlen(p), true)) {
            c.free(@as(?*anyopaque, @ptrCast(pending_devs[i].path)));
            pending_devs[i].path = null;
            gstate.pending -= 1;
        } else {
            pending_devs[i].tries -= 1;
            if (pending_devs[i].tries <= 0) {
                arcan_warning("input(eperm): device(%s) retry count exceeded\n", pending_devs[i].path);
                c.free(@as(?*anyopaque, @ptrCast(pending_devs[i].path)));
                pending_devs[i].path = null;
                gstate.pending -= 1;
            }
        }
    }
}

fn disconnect(ctx: ?*arcan_evctx, node: *devnode) void {
    var addev = arcan_event.zeroes();
    addev.unnamed_0.unnamed_0.category = @intCast(EVENT_IO);
    addev.unnamed_0.unnamed_0.unnamed_0.io.kind = EVENT_IO_STATUS;
    addev.unnamed_0.unnamed_0.unnamed_0.io.devid = node.devnum;
    addev.unnamed_0.unnamed_0.unnamed_0.io.devkind = EVENT_IDEVKIND_STATUS;
    addev.unnamed_0.unnamed_0.unnamed_0.io.input.status.devkind = @truncate(node.type);
    addev.unnamed_0.unnamed_0.unnamed_0.io.input.status.action = EVENT_IDEV_REMOVED;

    _ = c.snprintf(
        @as([*c]u8, @ptrCast(&addev.unnamed_0.unnamed_0.unnamed_0.io.label)),
        @sizeOf(@TypeOf(addev.unnamed_0.unnamed_0.unnamed_0.io.label)),
        "%s",
        @as([*c]const u8, @ptrCast(&node.label)),
    );
    _ = arcan_event_enqueue(ctx, &addev);

    const nodes = iodev.nodes orelse return;
    for (0..iodev.sz_nodes) |i| {
        if (node.devnum == nodes[i].devnum) {
            _ = c.close(node.handle);
            if (node.path) |p| c.free(@as(?*anyopaque, @ptrCast(p)));
            node.path = null;
            node.handle = -1;
            const ps = iodev.pollset orelse continue;
            ps[i].events = 0;
            ps[i].revents = 0;
            ps[i].fd = -1;
            if (node.led.gotled) {
                ps[i + iodev.sz_nodes].fd = -1;
                ps[i + iodev.sz_nodes].events = 0;
                ps[i + iodev.sz_nodes].revents = 0;
                node.led.gotled = false;
                _ = arcan_led_remove(@intCast(node.led.ctrlid));
                _ = c.close(node.led.fds[0]);
                _ = c.close(node.led.fds[1]);
                node.led.fds = .{ -1, -1 };
            }
            if (node.type == DEVNODE_KEYBOARD) {
                if (node.data.keyboard.xkb_state) |xs| {
                    c.xkb_state_unref(xs);
                    node.data.keyboard.xkb_state = null;
                }
                if (node.data.keyboard.xkb_layout) |xl| {
                    c.xkb_keymap_unref(xl);
                    node.data.keyboard.xkb_layout = null;
                }
            }
            iodev.n_devs -|= 1;
        }
    }
}

fn do_led(node: *devnode) void {
    if (!node.led.gotled) {
        arcan_warning("evdev(), pollset corruption? POLLIN on node without LED\n");
        return;
    }

    var buf: [2]u8 = undefined;
    var set: bool = false;

    while (c.read(node.led.fds[0], &buf, 2) == 2) {
        switch (@as(u8, @intCast(c.tolower(buf[0])))) {
            'A' => node.led.ind = -1,
            'a' => node.led.ind = @intCast(buf[1]),
            'r', 'g', 'b' => {},
            'i' => set = buf[1] > 0,
            'c' => {
                if (node.led.ind == -1) {
                    for (0..@as(usize, c.LED_MAX)) |li| {
                        var ev_led = std.mem.zeroes(c.input_event);
                        ev_led.type = c.EV_LED;
                        ev_led.code = @intCast(li);
                        ev_led.value = @intFromBool(set);
                        _ = c.write(node.handle, &ev_led, @sizeOf(c.input_event));
                    }
                } else {
                    var ev_led = std.mem.zeroes(c.input_event);
                    ev_led.type = c.EV_LED;
                    ev_led.code = @intCast(node.led.ind);
                    ev_led.value = @intFromBool(set);
                    _ = c.write(node.handle, &ev_led, @sizeOf(c.input_event));
                }
            },
            else => {},
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// Input handlers
// ══════════════════════════════════════════════════════════════════════

fn update_state(code: c_uint, state: bool, statev: *c_uint) void {
    const modifier: c_uint = switch (klut[code]) {
        K_LSHIFT => ARKMOD_LSHIFT,
        K_RSHIFT => ARKMOD_RSHIFT,
        K_LALT => ARKMOD_LALT,
        K_RALT => ARKMOD_RALT,
        K_LCTRL => ARKMOD_LCTRL,
        K_RCTRL => ARKMOD_RCTRL,
        K_LMETA => ARKMOD_LMETA,
        K_RMETA => ARKMOD_RMETA,
        K_CAPSLOCK => ARKMOD_CAPS,
        K_COMPOSE => ARKMOD_MODE,
        else => return,
    };

    if (state) {
        statev.* |= modifier;
    } else {
        statev.* &= ~modifier;
    }
}

fn defhandler_kbd(out: ?*arcan_evctx, node: *devnode) callconv(.c) void {
    var inev: [64]c.input_event = undefined;
    const evs = c.read(node.handle, &inev, @sizeOf(@TypeOf(inev)));

    if (evs == -1) {
        if (std.c._errno().* != c.EINTR and std.c._errno().* != c.EAGAIN)
            disconnect(out, node);
    }

    if (evs < 0 or @as(usize, @intCast(evs)) < @sizeOf(c.input_event))
        return;

    var newev = arcan_event.zeroes();
    newev.unnamed_0.unnamed_0.category = @intCast(EVENT_IO);
    newev.unnamed_0.unnamed_0.unnamed_0.io.kind = EVENT_IO_BUTTON;
    newev.unnamed_0.unnamed_0.unnamed_0.io.devid = node.devnum;
    newev.unnamed_0.unnamed_0.unnamed_0.io.datatype = EVENT_IDATATYPE_TRANSLATED;
    newev.unnamed_0.unnamed_0.unnamed_0.io.devkind = EVENT_IDEVKIND_KEYBOARD;

    const count = @as(usize, @intCast(evs)) / @sizeOf(c.input_event);
    for (0..count) |i| {
        if (inev[i].type == c.EV_KEY) {
            arcan_warning(
                "EVTRACE kbd: code=%d value=%d devnum=%d\n",
                @as(c_int, inev[i].code),
                inev[i].value,
                @as(c_int, @intCast(node.devnum)),
            );
            newev.unnamed_0.unnamed_0.unnamed_0.io.input.translated.scancode = @truncate(inev[i].code);
            newev.unnamed_0.unnamed_0.unnamed_0.io.input.translated.keysym =
                @as(u16, lookup_keycode(inev[i].code, @truncate(node.data.keyboard.state)));
            newev.unnamed_0.unnamed_0.unnamed_0.io.input.translated.modifiers = @truncate(node.data.keyboard.state);
            update_state(inev[i].code, inev[i].value != 0, &node.data.keyboard.state);
            newev.unnamed_0.unnamed_0.unnamed_0.io.subid = inev[i].code;

            // default 'fallback' translation
            const kcode: u16 = lookup_character(inev[i].code, @as(u16, @truncate(node.data.keyboard.state)), true);
            if (kcode != 0)
                to_utf8(kcode, &newev.unnamed_0.unnamed_0.unnamed_0.io.input.translated.utf8);

            // virtual terminal switching: LCTRL+LALT+Fn
            if (node.data.keyboard.state == (@as(c_uint, ARKMOD_LALT) | @as(c_uint, ARKMOD_LCTRL)) and
                inev[i].code >= c.KEY_F1 and inev[i].code <= c.KEY_F10 and inev[i].value != 0)
            {
                platform_device_release("TTY", @as(c_int, @intCast(inev[i].code)) - c.KEY_F1 + 1);
            }

            // XKB keyboard layout translation
            if (node.data.keyboard.xkb_state) |xs| {
                @memset(&newev.unnamed_0.unnamed_0.unnamed_0.io.input.translated.utf8, 0);
                if (inev[i].value == 0) {
                    _ = c.xkb_state_update_key(xs, inev[i].code + 8, c.XKB_KEY_UP);
                } else if (inev[i].value == 1 or (inev[i].value == 2 and
                    c.xkb_keymap_key_repeats(node.data.keyboard.xkb_layout, inev[i].code + 8) != 0))
                {
                    const eff = c.xkb_state_serialize_mods(xs, c.XKB_STATE_MODS_EFFECTIVE);
                    const cons = c.xkb_state_key_get_consumed_mods(xs, inev[i].code + 8);
                    if ((eff & (~cons)) == 0) {
                        _ = c.xkb_state_key_get_utf8(
                            xs,
                            inev[i].code + 8,
                            @as([*c]u8, @ptrCast(&newev.unnamed_0.unnamed_0.unnamed_0.io.input.translated.utf8)),
                            5,
                        );
                    }
                    _ = c.xkb_state_update_key(xs, inev[i].code + 8, c.XKB_KEY_DOWN);
                }
            }

            // auto-repeat
            if (inev[i].value == 2) {
                if (iodev.period != 0) {
                    newev.unnamed_0.unnamed_0.unnamed_0.io.input.translated.modifiers |= ARKMOD_REPEAT;
                    newev.unnamed_0.unnamed_0.unnamed_0.io.input.translated.active = 0;
                    _ = arcan_event_enqueue(out, &newev);
                    newev.unnamed_0.unnamed_0.unnamed_0.io.input.translated.active = 1;
                    _ = arcan_event_enqueue(out, &newev);
                }
            } else {
                newev.unnamed_0.unnamed_0.unnamed_0.io.input.translated.active = @intFromBool(inev[i].value != 0);
                _ = arcan_event_enqueue(out, &newev);
            }
        }
    }
}

fn flush_pending_touch(ctx: ?*arcan_evctx, node: *devnode) void {
    var newev = arcan_event.zeroes();
    newev.unnamed_0.unnamed_0.category = @intCast(EVENT_IO);
    newev.unnamed_0.unnamed_0.unnamed_0.io.kind = EVENT_IO_TOUCH;
    newev.unnamed_0.unnamed_0.unnamed_0.io.devid = node.devnum;
    newev.unnamed_0.unnamed_0.unnamed_0.io.subid = @intCast(@as(c_uint, @bitCast(node.touch.ind + 128)));
    newev.unnamed_0.unnamed_0.unnamed_0.io.devkind = EVENT_IDEVKIND_TOUCHDISP;
    newev.unnamed_0.unnamed_0.unnamed_0.io.datatype = EVENT_IDATATYPE_TOUCH;
    @memcpy(newev.unnamed_0.unnamed_0.unnamed_0.io.label[0..5], "touch");

    newev.unnamed_0.unnamed_0.unnamed_0.io.input.touch.active = @intFromBool(node.touch.active);
    const slot_idx: usize = @intCast(@min(@as(c_int, @intCast(MAX_MT_SLOTS - 1)), node.touch.ind));
    newev.unnamed_0.unnamed_0.unnamed_0.io.input.touch.x = @intCast(node.touch.x[slot_idx]);
    newev.unnamed_0.unnamed_0.unnamed_0.io.input.touch.y = @intCast(node.touch.y[slot_idx]);
    newev.unnamed_0.unnamed_0.unnamed_0.io.input.touch.pressure = @floatFromInt(node.touch.pressure);
    newev.unnamed_0.unnamed_0.unnamed_0.io.input.touch.size = @floatFromInt(node.touch.size);

    _ = arcan_event_enqueue(ctx, &newev);
    node.touch.pending = false;
    node.touch.active = true;
}

fn decode_mt(ctx: ?*arcan_evctx, node: *devnode, code: c_int, val: c_int) void {
    switch (@as(c_uint, @intCast(code))) {
        c.ABS_X => {
            if (node.touch.ind != 0 and node.touch.pending)
                flush_pending_touch(ctx, node);
            node.touch.ind = 0;
            node.touch.x[0] = val;
            node.touch.pending = true;
        },
        c.ABS_Y => {
            if (node.touch.ind != 0 and node.touch.pending)
                flush_pending_touch(ctx, node);
            node.touch.ind = 0;
            node.touch.y[0] = val;
            node.touch.pending = true;
        },
        c.ABS_MT_PRESSURE => node.touch.pressure = val,
        c.ABS_MT_POSITION_X => {
            node.touch.x[@intCast(@min(@as(c_int, @intCast(MAX_MT_SLOTS - 1)), node.touch.ind))] = val;
            node.touch.pending = true;
        },
        c.ABS_MT_POSITION_Y => {
            node.touch.y[@intCast(@min(@as(c_int, @intCast(MAX_MT_SLOTS - 1)), node.touch.ind))] = val;
            node.touch.pending = true;
        },
        c.ABS_DISTANCE => node.touch.pressure = val,
        c.ABS_MT_TRACKING_ID => {
            if (val == -1) {
                node.touch.active = false;
                node.touch.pending = true;
                flush_pending_touch(ctx, node);
            }
        },
        c.ABS_MT_SLOT => {
            if (node.touch.pending and node.touch.ind != val)
                flush_pending_touch(ctx, node);
            node.touch.ind = val;
        },
        else => {},
    }
}

fn decode_hat(ctx: ?*arcan_evctx, node: *devnode, ind_arg: c_int, val_arg: c_int) void {
    var newev = arcan_event.zeroes();
    newev.unnamed_0.unnamed_0.category = @intCast(EVENT_IO);
    newev.unnamed_0.unnamed_0.unnamed_0.io.kind = EVENT_IO_BUTTON;
    newev.unnamed_0.unnamed_0.unnamed_0.io.devkind = EVENT_IDEVKIND_GAMEDEV;
    newev.unnamed_0.unnamed_0.unnamed_0.io.datatype = EVENT_IDATATYPE_DIGITAL;
    @memcpy(newev.unnamed_0.unnamed_0.unnamed_0.io.label[0..7], "gamepad");

    var ind = ind_arg * 2;
    var val = val_arg;
    const base: c_int = 64;

    newev.unnamed_0.unnamed_0.unnamed_0.io.devid = node.devnum;

    if (val < 0) {
        val = -1;
    } else if (val > 0) {
        val = 1;
    } else {
        newev.unnamed_0.unnamed_0.unnamed_0.io.input.digital.active = 0;
        if (node.data.game.hats[@intCast(ind)] != 0) {
            newev.unnamed_0.unnamed_0.unnamed_0.io.subid = @intCast(@as(c_uint, @bitCast(base + ind)));
            node.data.game.hats[@intCast(ind)] = 0;
            _ = arcan_event_enqueue(ctx, &newev);
        }
        if (node.data.game.hats[@intCast(ind + 1)] != 0) {
            newev.unnamed_0.unnamed_0.unnamed_0.io.subid = @intCast(@as(c_uint, @bitCast(base + ind + 1)));
            node.data.game.hats[@intCast(ind + 1)] = 0;
            _ = arcan_event_enqueue(ctx, &newev);
        }
        return;
    }

    if (val > 0) ind += 1;

    node.data.game.hats[@intCast(ind)] = @truncate(@as(c_int, @bitCast(val)));
    newev.unnamed_0.unnamed_0.unnamed_0.io.input.digital.active = 1;
    newev.unnamed_0.unnamed_0.unnamed_0.io.subid = @intCast(@as(c_uint, @bitCast(base + ind)));
    _ = arcan_event_enqueue(ctx, &newev);
}

fn defhandler_game(ctx: ?*arcan_evctx, node: *devnode) callconv(.c) void {
    var inev: [64]c.input_event = undefined;
    const evs = c.read(node.handle, &inev, @sizeOf(@TypeOf(inev)));

    if (evs == -1) {
        if (std.c._errno().* != c.EINTR and std.c._errno().* != c.EAGAIN)
            disconnect(ctx, node);
    }

    if (evs < 0 or @as(usize, @intCast(evs)) < @sizeOf(c.input_event))
        return;

    var newev = arcan_event.zeroes();
    newev.unnamed_0.unnamed_0.category = @intCast(EVENT_IO);
    newev.unnamed_0.unnamed_0.unnamed_0.io.devkind = EVENT_IDEVKIND_GAMEDEV;
    @memcpy(newev.unnamed_0.unnamed_0.unnamed_0.io.label[0..7], "gamepad");

    var samplev: i16 = 0;

    const count = @as(usize, @intCast(evs)) / @sizeOf(c.input_event);
    for (0..count) |i| {
        switch (@as(c_uint, inev[i].type)) {
            c.EV_KEY => {
                arcan_warning(
                    "EVTRACE game: EV_KEY code=%d value=%d devnum=%d (keyboard keys in game handler!)\n",
                    @as(c_int, inev[i].code),
                    inev[i].value,
                    @as(c_int, @intCast(node.devnum)),
                );
                var ecode = inev[i].code;
                if (ecode >= c.BTN_TOUCH) {
                    ecode -= c.BTN_TOUCH;
                } else if (ecode >= c.BTN_JOYSTICK) {
                    ecode -= c.BTN_JOYSTICK;
                } else if (ecode >= c.BTN_MOUSE) {
                    ecode -= c.BTN_MOUSE - 1;
                }
                if (node.hnd.button_mask != 0 and ecode <= 64 and
                    ((node.hnd.button_mask >> @intCast(ecode)) & 1) != 0)
                    continue;

                newev.unnamed_0.unnamed_0.unnamed_0.io.kind = EVENT_IO_BUTTON;
                newev.unnamed_0.unnamed_0.unnamed_0.io.datatype = EVENT_IDATATYPE_DIGITAL;
                newev.unnamed_0.unnamed_0.unnamed_0.io.input.digital.active = @intCast(@as(u32, @bitCast(inev[i].value)));
                newev.unnamed_0.unnamed_0.unnamed_0.io.subid = ecode;
                newev.unnamed_0.unnamed_0.unnamed_0.io.devid = node.devnum;
                _ = arcan_event_enqueue(ctx, &newev);
            },
            c.EV_SW => {
                newev.unnamed_0.unnamed_0.unnamed_0.io.kind = EVENT_IO_BUTTON;
                newev.unnamed_0.unnamed_0.unnamed_0.io.datatype = EVENT_IDATATYPE_DIGITAL;
                newev.unnamed_0.unnamed_0.unnamed_0.io.input.digital.active = @intCast(@as(u32, @bitCast(inev[i].value)));
                newev.unnamed_0.unnamed_0.unnamed_0.io.subid = inev[i].code;
                newev.unnamed_0.unnamed_0.unnamed_0.io.devid = node.devnum;
                _ = arcan_event_enqueue(ctx, &newev);
            },
            c.EV_REL, c.EV_ABS => {
                if (node.hnd.axis_mask != 0 and inev[i].code <= 64 and
                    ((node.hnd.axis_mask >> @intCast(inev[i].code)) & 1) != 0)
                    continue;

                if (inev[i].code >= c.ABS_HAT0X and inev[i].code <= c.ABS_HAT3Y) {
                    decode_hat(ctx, node, @as(c_int, @intCast(inev[i].code)) - c.ABS_HAT0X, inev[i].value);
                } else if (inev[i].code < node.data.game.axes and
                    process_axis(ctx, &(node.data.game.adata orelse continue)[inev[i].code], @truncate(inev[i].value), &samplev))
                {
                    newev.unnamed_0.unnamed_0.unnamed_0.io.kind = EVENT_IO_AXIS_MOVE;
                    newev.unnamed_0.unnamed_0.unnamed_0.io.datatype = EVENT_IDATATYPE_ANALOG;
                    newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.gotrel = @intFromBool(inev[i].type == c.EV_REL);
                    newev.unnamed_0.unnamed_0.unnamed_0.io.subid = inev[i].code;
                    newev.unnamed_0.unnamed_0.unnamed_0.io.devid = node.devnum;
                    newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.axisval[0] = samplev;
                    newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.nvalues = 2;
                    _ = arcan_event_enqueue(ctx, &newev);
                } else if ((inev[i].code >= c.ABS_X and inev[i].code <= c.ABS_Y) or
                    (inev[i].code >= c.ABS_MT_SLOT and inev[i].code <= c.ABS_MT_TOOL_Y))
                {
                    decode_mt(ctx, node, @intCast(inev[i].code), inev[i].value);
                } else if (inev[i].code == c.REL_X or inev[i].code == c.REL_Y or
                    inev[i].code == c.REL_DIAL or inev[i].code == c.REL_Z or
                    inev[i].code == c.REL_RZ or inev[i].code == c.REL_RX or
                    inev[i].code == c.REL_RY or inev[i].code == c.ABS_THROTTLE)
                {
                    newev.unnamed_0.unnamed_0.unnamed_0.io.kind = EVENT_IO_AXIS_MOVE;
                    newev.unnamed_0.unnamed_0.unnamed_0.io.datatype = EVENT_IDATATYPE_ANALOG;
                    newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.gotrel = 1;
                    newev.unnamed_0.unnamed_0.unnamed_0.io.subid = inev[i].code;
                    newev.unnamed_0.unnamed_0.unnamed_0.io.devid = node.devnum;
                    newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.axisval[0] = @intCast(inev[i].value);
                    newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.nvalues = 1;
                    _ = arcan_event_enqueue(ctx, &newev);
                }
            },
            c.EV_SYN, c.EV_REP => {
                if (node.touch.pending)
                    flush_pending_touch(ctx, node);
            },
            else => {},
        }
    }
}

fn code_to_mouse(code: c_int) c_short {
    return if (code < c.BTN_MOUSE or code >= c.BTN_JOYSTICK)
        -1
    else
        @intCast(code - c.BTN_MOUSE + 1);
}

fn defhandler_mouse(ctx: ?*arcan_evctx, node: *devnode) callconv(.c) void {
    var inev: [64]c.input_event = undefined;
    const evs = c.read(node.handle, &inev, @sizeOf(@TypeOf(inev)));

    if (evs == -1) {
        if (std.c._errno().* != c.EINTR and std.c._errno().* != c.EAGAIN)
            disconnect(ctx, node);
    }

    if (evs < 0 or @as(usize, @intCast(evs)) < @sizeOf(c.input_event))
        return;

    var newev = arcan_event.zeroes();
    newev.unnamed_0.unnamed_0.category = @intCast(EVENT_IO);
    newev.unnamed_0.unnamed_0.unnamed_0.io.devkind = EVENT_IDEVKIND_MOUSE;
    @memcpy(newev.unnamed_0.unnamed_0.unnamed_0.io.label[0..5], "mouse");

    var samplev: i16 = 0;
    newev.unnamed_0.unnamed_0.unnamed_0.io.devid = node.devnum;

    const count = @as(usize, @intCast(evs)) / @sizeOf(c.input_event);
    for (0..count) |i| {
        switch (@as(c_uint, inev[i].type)) {
            c.EV_KEY => {
                const sv = code_to_mouse(@intCast(inev[i].code));
                if (sv < 0) continue;
                newev.unnamed_0.unnamed_0.unnamed_0.io.kind = EVENT_IO_BUTTON;
                newev.unnamed_0.unnamed_0.unnamed_0.io.datatype = EVENT_IDATATYPE_DIGITAL;
                newev.unnamed_0.unnamed_0.unnamed_0.io.input.digital.active = @intCast(@as(u32, @bitCast(inev[i].value)));
                newev.unnamed_0.unnamed_0.unnamed_0.io.subid = @intCast(@as(u16, @bitCast(sv)));
                _ = arcan_event_enqueue(ctx, &newev);
            },
            c.EV_REL => {
                switch (@as(c_uint, inev[i].code)) {
                    c.REL_HWHEEL, c.REL_WHEEL => {
                        const vofs: c_int = if (inev[i].code == c.REL_HWHEEL) 2 else 0;
                        newev.unnamed_0.unnamed_0.unnamed_0.io.kind = EVENT_IO_BUTTON;
                        newev.unnamed_0.unnamed_0.unnamed_0.io.datatype = EVENT_IDATATYPE_DIGITAL;
                        newev.unnamed_0.unnamed_0.unnamed_0.io.input.digital.active = 1;
                        newev.unnamed_0.unnamed_0.unnamed_0.io.subid = @intCast(@as(c_uint, @bitCast(vofs + (if (inev[i].value > 0) @as(c_int, 256) else @as(c_int, 257)))));
                        _ = arcan_event_enqueue(ctx, &newev);
                        newev.unnamed_0.unnamed_0.unnamed_0.io.input.digital.active = 0;
                        _ = arcan_event_enqueue(ctx, &newev);
                    },
                    c.REL_X => {
                        if (process_axis(ctx, &node.data.cursor.flt[0], @truncate(inev[i].value), &samplev)) {
                            samplev = @truncate(inev[i].value);
                            const imx: c_int = @as(c_int, @intCast(node.data.cursor.mx)) + @as(c_int, samplev);
                            node.data.cursor.mx = if (imx < 0) 0 else @intCast(imx);

                            newev.unnamed_0.unnamed_0.unnamed_0.io.kind = EVENT_IO_AXIS_MOVE;
                            newev.unnamed_0.unnamed_0.unnamed_0.io.datatype = EVENT_IDATATYPE_ANALOG;
                            newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.gotrel = 1;
                            newev.unnamed_0.unnamed_0.unnamed_0.io.subid = 0;
                            newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.axisval[0] = samplev;
                            newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.axisval[1] = @intCast(node.data.cursor.mx);
                            newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.nvalues = 2;
                            _ = arcan_event_enqueue(ctx, &newev);
                        }
                    },
                    c.REL_Y => {
                        if (process_axis(ctx, &node.data.cursor.flt[1], @truncate(inev[i].value), &samplev)) {
                            samplev = @truncate(inev[i].value);
                            const imy: c_int = @as(c_int, @intCast(node.data.cursor.my)) + @as(c_int, samplev);
                            node.data.cursor.my = if (imy < 0) 0 else @intCast(imy);

                            newev.unnamed_0.unnamed_0.unnamed_0.io.kind = EVENT_IO_AXIS_MOVE;
                            newev.unnamed_0.unnamed_0.unnamed_0.io.datatype = EVENT_IDATATYPE_ANALOG;
                            newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.gotrel = 1;
                            newev.unnamed_0.unnamed_0.unnamed_0.io.subid = 1;
                            newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.axisval[0] = samplev;
                            newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.axisval[1] = @intCast(node.data.cursor.my);
                            newev.unnamed_0.unnamed_0.unnamed_0.io.input.analog.nvalues = 2;
                            _ = arcan_event_enqueue(ctx, &newev);
                        }
                    },
                    else => {},
                }
            },
            c.EV_ABS => {},
            else => {},
        }
    }
}

fn defhandler_null(out: ?*arcan_evctx, node: *devnode) callconv(.c) void {
    var nbuf: [256]u8 = undefined;
    const evs = c.read(node.handle, &nbuf, nbuf.len);
    if (evs == -1) {
        if (std.c._errno().* != c.EINTR and std.c._errno().* != c.EAGAIN)
            disconnect(out, node);
    }
}

// ══════════════════════════════════════════════════════════════════════
// XKB Translation & Device Setup
// ══════════════════════════════════════════════════════════════════════

fn lookup_dev_handler(idstr: [*:0]const u8) evhandler {
    var tag: usize = 0;
    const get_config = platform_config_lookup(&tag) orelse return .{};

    // Check evdev_keyboard overrides
    {
        var ind: c_ushort = 0;
        var dst: [*c]u8 = null;
        while (get_config("evdev_keyboard", ind, &dst, tag)) : (ind += 1) {
            if (dst != null and c.strcasecmp(dst, idstr) == 0) {
                c.free(@as(?*anyopaque, @ptrCast(dst)));
                return .{ .handler = defhandler_kbd, .type = DEVNODE_KEYBOARD, .name = idstr };
            }
            c.free(@as(?*anyopaque, @ptrCast(dst)));
            dst = null;
        }
    }

    // Check evdev_mouse overrides
    {
        var ind: c_ushort = 0;
        var dst: [*c]u8 = null;
        while (get_config("evdev_mouse", ind, &dst, tag)) : (ind += 1) {
            if (dst != null and c.strcasecmp(dst, idstr) == 0) {
                c.free(@as(?*anyopaque, @ptrCast(dst)));
                return .{ .handler = defhandler_mouse, .type = DEVNODE_MOUSE, .name = idstr };
            }
            c.free(@as(?*anyopaque, @ptrCast(dst)));
            dst = null;
        }
    }

    // Check evdev_game overrides
    {
        var ind: c_ushort = 0;
        var dst: [*c]u8 = null;
        while (get_config("evdev_game", ind, &dst, tag)) : (ind += 1) {
            if (dst != null and c.strcasecmp(dst, idstr) == 0) {
                c.free(@as(?*anyopaque, @ptrCast(dst)));
                return .{ .handler = defhandler_game, .type = DEVNODE_GAME, .name = idstr };
            }
            c.free(@as(?*anyopaque, @ptrCast(dst)));
            dst = null;
        }
    }

    // Check static device_db
    for (&device_db) |*entry| {
        if (c.strcmp(idstr, entry.name orelse continue) == 0)
            return entry.*;
    }

    return .{};
}

fn got_device(ctx: ?*arcan_evctx, fd: c_int, path: [*]const u8) void {
    var node: devnode = .{};
    node.handle = fd;
    node.led.fds = .{ BADFD, BADFD };

    var fdstat: c.struct_stat = undefined;
    if (c.fstat(fd, &fdstat) == -1)
        return;

    if ((fdstat.mode & (c.S_IFCHR | c.S_IFBLK)) == 0)
        return;

    if (!identify(fd, path, &node.label, node.label.len, &node.devnum)) {
        _ = c.close(fd);
        return;
    }

    if (iodev.n_devs >= MAX_DEVICES) {
        arcan_warning("input: device limit reached, ignoring %s.", path);
        _ = c.close(fd);
        return;
    }

    const eh = lookup_dev_handler(@ptrCast(&node.label));

    node.type = DEVNODE_GAME;

    var mouse_ax: bool = false;
    var mouse_btn: bool = false;
    var joystick_btn: bool = false;
    var add_led: c_int = -1;

    const bpl2 = @sizeOf(c_ulong) * 8;
    const nbits2 = (@as(usize, c.EV_MAX) - 1) / bpl2 + 1;
    var prop: [nbits2]c_ulong = [_]c_ulong{0} ** nbits2;

    if (ioctl(fd, EVIOCGBIT(@as(c_int, 0), @as(c_int, @intCast(@sizeOf(@TypeOf(prop))))), &prop) == -1) {
        _ = c.close(fd);
        return;
    }

    for (0..@as(usize, c.EV_MAX)) |bit| {
        if ((prop[bit / bpl2] >> @intCast(bit % bpl2)) & 1 != 0) {
            switch (bit) {
                c.EV_KEY => node.button_count = button_count(fd, bit, &mouse_btn, &joystick_btn),
                c.EV_REL => mouse_ax = check_mouse_axis(fd, bit),
                c.EV_ABS => map_axes(fd, bit, &node),
                c.EV_LED => add_led = @intCast(bit),
                else => {},
            }
        }
    }

    if (eh.handler == null) {
        if (mouse_ax and mouse_btn) {
            node.type = DEVNODE_MOUSE;
            node.data = .{ .cursor = .{} };
            node.data.cursor.flt[0].mode = ARCAN_ANALOGFILTER_PASS;
            node.data.cursor.flt[1].mode = ARCAN_ANALOGFILTER_PASS;

            if (iodev.mouseid == 0)
                iodev.mouseid = node.devnum;
        } else if (!mouse_btn and !joystick_btn and node.button_count > 84) {
            node.type = DEVNODE_KEYBOARD;
            node.data = .{ .keyboard = .{} };

            var rep = [2]c_uint{ 0, 0 };
            _ = ioctl(node.handle, EVIOCSREP, &rep);
        }

        if (node.type < defhandlers.len) {
            node.hnd.handler = defhandlers[node.type];
        }
    } else {
        node.hnd = eh;
        node.type = eh.type;
    }

    // TRACE: device classification result
    arcan_warning(
        "EVTRACE got_device: \"%s\" fd=%d btns=%d mouse_ax=%d mouse_btn=%d joy_btn=%d -> type=%d handler=%s\n",
        @as([*c]const u8, @ptrCast(&node.label)),
        fd,
        @as(c_int, @intCast(node.button_count)),
        @as(c_int, @intFromBool(mouse_ax)),
        @as(c_int, @intFromBool(mouse_btn)),
        @as(c_int, @intFromBool(joystick_btn)),
        @as(c_int, @intCast(node.type)),
        @as([*c]const u8, if (node.hnd.handler != null) "SET" else "NULL"),
    );

    const hole = alloc_node_slot(path);
    if (hole == -1) {
        _ = c.close(fd);
        return;
    }
    const hole_u: usize = @intCast(hole);

    iodev.n_devs += 1;
    node.path = c.strdup(path);
    const ps = iodev.pollset orelse return;
    ps[hole_u].fd = fd;
    ps[hole_u].events = c.POLLIN | c.POLLERR | c.POLLHUP;
    ps[hole_u + iodev.sz_nodes].fd = BADFD;
    send_device_added(ctx, &node);

    if (add_led != -1) {
        setup_led(&node, @intCast(add_led), fd);
        if (node.led.gotled) {
            ps[hole_u + iodev.sz_nodes].fd = node.led.fds[0];
        }
    }
    (iodev.nodes orelse return)[hole_u] = node;

    if (node.type == DEVNODE_KEYBOARD) {
        var trans_err: [*:0]const u8 = "none";
        _ = evdev_event_translation(@intCast(node.devnum), EVENT_TRANSLATION_CLEAR, null, &trans_err);
    }
}

fn find_tty() void {
    var tty: c_int = -1;
    var scantty: bool = true;

    var tag: usize = 0;
    const get_config = platform_config_lookup(&tag) orelse return;
    var ttydev: [*c]u8 = null;
    if (get_config("event_tty_override", 0, &ttydev, tag) and ttydev != null) {
        const fd = platform_device_open(ttydev, c.O_RDWR);
        scantty = false;
        if (fd == -1) {
            arcan_warning("couldn't open TTYOVERRIDE %s, reason: %s\n", ttydev, c.strerror(std.c._errno().*));
        } else {
            tty = fd;
        }
        c.free(@as(?*anyopaque, @ptrCast(ttydev)));
    }

    if (c.isatty(tty) == 0 and scantty) {
        const fpek: ?*c.FILE = c.fopen("/sys/class/tty/tty0/active", "r");
        if (fpek) |fp| {
            var line: [32]u8 = [_]u8{0} ** 32;
            @memcpy(line[0..5], "/dev/");
            if (c.fgets(@as([*c]u8, @ptrCast(&line)) + 5, 32 - 5, fp) != null) {
                const endl: ?[*c]u8 = c.strrchr(&line, '\n');
                if (endl) |e| e[0] = 0;
                tty = platform_device_open(&line, c.O_RDWR);
            }
            _ = c.fclose(fp);
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// Platform API exports
// ══════════════════════════════════════════════════════════════════════

export fn evdev_event_analogstate(
    devid: c_int,
    axisid: c_int,
    lower_bound: *c_int,
    upper_bound: *c_int,
    deadzone: *c_int,
    kernel_size: *c_int,
    mode: *c_int,
) callconv(.c) c_int {
    var gotnode: bool = false;
    const axis = find_axis(devid, @intCast(axisid), &gotnode) orelse {
        return if (gotnode) ARCAN_ERRC_BAD_RESOURCE else ARCAN_ERRC_NO_SUCH_OBJECT;
    };
    lower_bound.* = axis.lower;
    upper_bound.* = axis.upper;
    deadzone.* = axis.deadzone;
    kernel_size.* = axis.kernel_sz;
    mode.* = axis.mode;
    return ARCAN_OK;
}

export fn evdev_event_analogall(enable: bool, mouse: bool) callconv(.c) void {
    _ = enable;
    _ = mouse;
    _ = lookup_devnode(@intCast(iodev.mouseid));
}

export fn evdev_event_analogfilter(
    devid: c_int,
    axisid: c_int,
    lower_bound: c_int,
    upper_bound: c_int,
    deadzone_val: c_int,
    buffer_sz_in: c_int,
    kind: c_int,
) callconv(.c) void {
    if (kind == ARCAN_ANALOGFILTER_FORGET) {
        if (lookup_devnode(devid)) |node|
            disconnect(arcan_event_defaultctx(), node);
        return;
    }
    var gotnode: bool = false;
    const axis = find_axis(devid, @intCast(axisid), &gotnode) orelse return;
    const kernel_lim: c_int = @intCast(axis.flt_kernel.len);
    var buffer_sz = buffer_sz_in;
    if (buffer_sz > kernel_lim) buffer_sz = kernel_lim;
    if (buffer_sz <= 0) buffer_sz = 1;
    set_analogstate(axis, lower_bound, upper_bound, deadzone_val, buffer_sz, kind);
}

export fn evdev_event_process(ctx: ?*arcan_evctx) callconv(.c) void {
    // Linux inotify hotplug
    if (gstate.notify != -1) {
        var inbuf: [1024]u8 = undefined;
        const nr: isize = c.read(gstate.notify, &inbuf, inbuf.len);
        var ofs: usize = 0;

        if (nr > 0) {
            const nru = @as(usize, @intCast(nr));
            while (nru - ofs > @sizeOf(c.inotify_event)) {
                var cur: c.inotify_event = undefined;
                @memcpy(std.mem.asBytes(&cur), inbuf[ofs..][0..@sizeOf(c.inotify_event)]);
                ofs += @sizeOf(c.inotify_event);
                if ((cur.mask & c.IN_CREATE != 0) and (cur.mask & c.IN_ISDIR == 0)) {
                    _ = discovered(ctx, @ptrCast(inbuf[ofs..].ptr), cur.len, false);
                    ofs += cur.len;
                }
            }
        }
    }

    if (gstate.pending != 0)
        process_pending(ctx);

    const ps = iodev.pollset orelse return;
    const nr2 = c.poll(ps, @intCast(iodev.sz_nodes * 2), 0);
    if (nr2 <= 0) return;

    const nodes = iodev.nodes orelse return;
    for (0..iodev.sz_nodes) |i| {
        if (ps[i + iodev.sz_nodes].revents & c.POLLIN != 0)
            do_led(&nodes[i]);

        if (ps[i].fd == -1 or ps[i].revents == 0)
            continue;

        if (ps[i].revents & c.POLLIN == 0) {
            disconnect(ctx, &nodes[i]);
            continue;
        }

        if (nodes[i].hnd.handler) |handler| {
            if (nodes[i].trace_count < 5) {
                nodes[i].trace_count += 1;
                arcan_warning(
                    "EVTRACE dispatch: node[%d] \"%s\" type=%d fd=%d -> handler\n",
                    @as(c_int, @intCast(i)),
                    @as([*c]const u8, @ptrCast(&nodes[i].label)),
                    @as(c_int, @intCast(nodes[i].type)),
                    ps[i].fd,
                );
            }
            handler(ctx, &nodes[i]);
        } else {
            if (nodes[i].trace_count < 5) {
                nodes[i].trace_count += 1;
                arcan_warning(
                    "EVTRACE dispatch: node[%d] \"%s\" type=%d fd=%d -> DUMP (no handler!)\n",
                    @as(c_int, @intCast(i)),
                    @as([*c]const u8, @ptrCast(&nodes[i].label)),
                    @as(c_int, @intCast(nodes[i].type)),
                    ps[i].fd,
                );
            }
            var dump: [256]u8 = undefined;
            _ = c.read(nodes[i].handle, &dump, 256);
        }
    }
}

export fn evdev_event_samplebase(devid: c_int, xyz: [*c]f32) callconv(.c) void {
    const node = lookup_devnode(devid) orelse return;
    if (node.type != DEVNODE_MOUSE) return;
    node.data.cursor.mx = @intFromFloat(xyz[0]);
    node.data.cursor.my = @intFromFloat(xyz[1]);
}

export fn evdev_event_keyrepeat(ctx: ?*arcan_evctx, period_ptr: *c_int, delay_ptr: *c_int) callconv(.c) void {
    _ = ctx;
    var upd: bool = false;

    if (period_ptr.* < 0) {
        period_ptr.* = @intCast(iodev.period);
    } else {
        const tmp = period_ptr.*;
        period_ptr.* = @intCast(iodev.period);
        iodev.period = @intCast(tmp);
        upd = true;
    }

    if (delay_ptr.* < 0) {
        delay_ptr.* = @intCast(iodev.delay);
    } else {
        const tmp = delay_ptr.*;
        delay_ptr.* = @intCast(iodev.delay);
        iodev.delay = @intCast(tmp);
        upd = true;
    }

    if (!upd) return;

    const nodes = iodev.nodes orelse return;
    for (0..iodev.sz_nodes) |i| {
        if (nodes[i].type == DEVNODE_KEYBOARD) {
            var ev = std.mem.zeroes(c.input_event);
            ev.type = c.EV_REP;
            ev.code = c.REP_DELAY;
            ev.value = delay_ptr.*;
            _ = c.write(nodes[i].handle, &ev, @sizeOf(c.input_event));
            ev.code = c.REP_PERIOD;
            ev.value = period_ptr.*;
            _ = c.write(nodes[i].handle, &ev, @sizeOf(c.input_event));
        }
    }
}

export fn evdev_event_translation(
    devid_in: c_int,
    action: c_int,
    arg: [*c]const [*c]const u8,
    err: *[*:0]const u8,
) callconv(.c) c_int {
    var node: ?*devnode = null;

    var did = devid_in;
    if (did < 0) {
        did = -did;
        const nodes = iodev.nodes orelse {
            err.* = "No such device";
            return 0;
        };
        for (0..iodev.sz_nodes) |i| {
            if (nodes[i].type == DEVNODE_KEYBOARD) {
                did -= 1;
                if (did == 0) {
                    node = &nodes[i];
                    break;
                }
            }
        }
    } else {
        node = lookup_devnode(did);
    }

    const n = node orelse {
        err.* = "No such device";
        return 0;
    };
    if (n.type != DEVNODE_KEYBOARD) {
        err.* = "No such device";
        return 0;
    }

    var rules: [*c]u8 = null;
    var model: [*c]u8 = null;
    var variant: [*c]u8 = null;
    var options: [*c]u8 = null;
    var layout_str: [*c]u8 = null;

    var names = std.mem.zeroes(c.xkb_rule_names);

    if (xkb_ctx == null) {
        err.* = "Missing XKB context";
        return 0;
    }

    if (action == EVENT_TRANSLATION_CLEAR) {
        var tag: usize = 0;
        const get_config = platform_config_lookup(&tag) orelse {
            err.* = "No config";
            return 0;
        };
        _ = get_config("event_xkb_rules", 0, &rules, tag);
        _ = get_config("event_xkb_variant", 0, &variant, tag);
        _ = get_config("event_xkb_model", 0, &model, tag);
        _ = get_config("event_xkb_options", 0, &options, tag);
        _ = get_config("event_xkb_layout", 0, &layout_str, tag);

        names.rules = if (rules != null) rules else c.getenv("XKB_DEFAULT_RULES");
        names.model = if (model != null) model else c.getenv("XKB_DEFAULT_MODEL");
        names.variant = if (variant != null) variant else c.getenv("XKB_DEFAULT_VARIANT");
        names.options = if (options != null) options else c.getenv("XKB_DEFAULT_OPTIONS");
        names.layout = if (layout_str != null) layout_str else c.getenv("XKB_DEFAULT_LAYOUT");
    } else if (action == EVENT_TRANSLATION_SET or action == EVENT_TRANSLATION_SERIALIZE_SPEC) {
        names.layout = arg[0];
        if (names.layout != null) names.model = arg[1];
        if (names.model != null) names.variant = arg[2];
        if (names.variant != null) names.options = arg[3];
    } else if (action == EVENT_TRANSLATION_SERIALIZE_CURRENT) {
        return xkb_layout_to_fd(n.data.keyboard.xkb_layout, err);
    } else {
        err.* = "Unsupported action";
        return 0;
    }

    const map = c.xkb_keymap_new_from_names(xkb_ctx, &names, c.XKB_KEYMAP_COMPILE_NO_FLAGS);

    if (action == EVENT_TRANSLATION_SERIALIZE_SPEC) {
        const fd = xkb_layout_to_fd(map, err);
        c.xkb_keymap_unref(map);
        return fd;
    }

    if (n.data.keyboard.xkb_layout != null) {
        if (n.data.keyboard.xkb_state) |xs| c.xkb_state_unref(xs);
        if (n.data.keyboard.xkb_layout) |xl| c.xkb_keymap_unref(xl);
        n.data.keyboard.xkb_state = null;
        n.data.keyboard.xkb_layout = null;
    }

    n.data.keyboard.xkb_layout = map;

    if (n.data.keyboard.xkb_layout != null)
        n.data.keyboard.xkb_state = c.xkb_state_new(n.data.keyboard.xkb_layout);

    c.free(@as(?*anyopaque, @ptrCast(rules)));
    c.free(@as(?*anyopaque, @ptrCast(model)));
    c.free(@as(?*anyopaque, @ptrCast(variant)));
    c.free(@as(?*anyopaque, @ptrCast(options)));

    return 1;
}

export fn evdev_event_device_request(space: c_int, path: [*c]const u8) callconv(.c) c_int {
    _ = space;
    _ = path;
    return -c.EINVAL;
}

export fn evdev_event_rescan_idev(ctx: ?*arcan_evctx) callconv(.c) void {
    var ibuf: [4096]u8 = undefined;
    const scan_dir = notify_scan_dir orelse return;
    _ = c.snprintf(&ibuf, ibuf.len, "%s/*", scan_dir);

    var res = std.mem.zeroes(c.glob_t);
    if (c.glob(&ibuf, 0, null, &res) == 0) {
        var idx: usize = 0;
        while (res.gl_pathv[idx] != null) : (idx += 1) {
            const fd = platform_device_open(res.gl_pathv[idx], c.O_NONBLOCK | c.O_RDWR);
            if (fd != -1)
                got_device(ctx, fd, res.gl_pathv[idx]);
        }
        c.globfree(&res);
    }
}

export fn evdev_event_devlabel(devid: c_int) callconv(.c) [*c]const u8 {
    const node = lookup_devnode(devid) orelse return null;
    return @ptrCast(&node.label);
}

export fn evdev_event_reset(ctx: ?*arcan_evctx) callconv(.c) void {
    _ = ctx;
}

export fn evdev_event_deinit(ctx: ?*arcan_evctx) callconv(.c) void {
    _ = ctx;
    platform_device_release("TTY", -1);

    if (gstate.notify != -1) {
        _ = c.close(gstate.notify);
        gstate.notify = -1;
    }

    if (iodev.nodes) |nodes| {
        for (0..iodev.sz_nodes) |i| {
            if (nodes[i].handle > 0) {
                _ = c.close(nodes[i].handle);
                nodes[i] = devnode{};
            }
        }
    }
    iodev.n_devs = 0;
    gstate.init = false;
}

export fn evdev_device_lock(devind: c_int, state: bool) callconv(.c) void {
    const node = lookup_devnode(devind) orelse return;
    if (node.handle == 0) return;
    _ = ioctl(node.handle, EVIOCGRAB, @as(c_int, @intFromBool(state)));
}

export fn evdev_event_capabilities(out: ?*[*c]const u8) callconv(.c) c_int {
    var rv: c_int = 0;
    if (out) |o| o.* = "evdev";

    const nodes = iodev.nodes orelse return rv;
    for (0..iodev.sz_nodes) |i| {
        if (nodes[i].handle != 0) {
            switch (nodes[i].type) {
                DEVNODE_SENSOR => rv |= ACAP_POSITION | ACAP_ORIENTATION,
                DEVNODE_MOUSE => rv |= ACAP_MOUSE,
                DEVNODE_GAME => rv |= ACAP_GAMING,
                DEVNODE_KEYBOARD => rv |= ACAP_TRANSLATED,
                DEVNODE_TOUCH => rv |= ACAP_TOUCH,
                else => {},
            }
        }
    }
    return rv;
}

export fn evdev_event_envopts() callconv(.c) [*c]const [*c]const u8 {
    return @ptrCast(&envopts);
}

export fn evdev_event_preinit() callconv(.c) void {}

export fn evdev_event_init(ctx: ?*arcan_evctx) callconv(.c) void {
    var tag: usize = 0;
    const get_config = platform_config_lookup(&tag);

    gstate.notify = c.inotify_init1(c.IN_NONBLOCK | c.IN_CLOEXEC);

    init_keyblut();
    xkb_ctx = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);

    if (notify_scan_dir == null)
        notify_scan_dir = c.strdup(NOTIFY_SCAN_DIR);

    find_tty();

    if (get_config) |gc| {
        var newsd: [*c]u8 = null;
        if (gc("event_scandir", 0, &newsd, tag) and newsd != null) {
            c.free(@as(?*anyopaque, @ptrCast(notify_scan_dir)));
            notify_scan_dir = newsd;
        }
    }

    if (gstate.notify == -1 or
        c.inotify_add_watch(gstate.notify, notify_scan_dir.?, c.IN_CREATE) == -1)
    {
        arcan_warning("inotify initialization failure (%s), device discovery disabled.", c.strerror(std.c._errno().*));
        if (gstate.notify != -1) {
            _ = c.close(gstate.notify);
            gstate.notify = -1;
        }
    }

    evdev_event_rescan_idev(ctx);
}
