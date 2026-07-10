// evdev_types — hand-translated subset of linux/input.h + linux/input-event-codes.h
// used by platform/evdev/event.zig.
//
// Mirrors shmif_types.zig style: plain `extern struct`s + constants, no
// `@cImport`. The kernel UAPI is ABI-frozen for these fields so a
// hand copy is safe.

// struct input_id — EVIOCGID result.
pub const input_id = extern struct {
    bustype: u16 = 0,
    vendor: u16 = 0,
    product: u16 = 0,
    version: u16 = 0,
};

// struct input_absinfo — EVIOCGABS result.
pub const input_absinfo = extern struct {
    value: i32 = 0,
    minimum: i32 = 0,
    maximum: i32 = 0,
    fuzz: i32 = 0,
    flat: i32 = 0,
    resolution: i32 = 0,
};

// struct timeval — linux/time.h (tv_sec + tv_usec pair used by input_event).
pub const timeval = extern struct {
    tv_sec: c_long = 0,
    tv_usec: c_long = 0,
};

// struct input_event — /dev/input/eventN wire format.
pub const input_event = extern struct {
    time: timeval = .{},
    type: u16 = 0,
    code: u16 = 0,
    value: i32 = 0,
};

// EV_* event type codes (linux/input-event-codes.h).
pub const EV_SYN: u16 = 0x00;
pub const EV_KEY: u16 = 0x01;
pub const EV_REL: u16 = 0x02;
pub const EV_ABS: u16 = 0x03;
pub const EV_SW: u16 = 0x05;
pub const EV_LED: u16 = 0x11;
pub const EV_REP: u16 = 0x14;
pub const EV_MAX: u16 = 0x1f;

// KEY_* codes — only the function keys used by the VT-switch combo.
pub const KEY_F1: u16 = 59;
pub const KEY_F10: u16 = 68;
pub const KEY_MAX: u16 = 0x2ff;

// BTN_* codes.
pub const BTN_MOUSE: u16 = 0x110;
pub const BTN_LEFT: u16 = 0x110;
pub const BTN_RIGHT: u16 = 0x111;
pub const BTN_MIDDLE: u16 = 0x112;
pub const BTN_JOYSTICK: u16 = 0x120;
pub const BTN_GAMEPAD: u16 = 0x130;
pub const BTN_TOUCH: u16 = 0x14a;
pub const BTN_WHEEL: u16 = 0x150;

// REL_* codes.
pub const REL_X: u16 = 0x00;
pub const REL_Y: u16 = 0x01;
pub const REL_Z: u16 = 0x02;
pub const REL_RX: u16 = 0x03;
pub const REL_RY: u16 = 0x04;
pub const REL_RZ: u16 = 0x05;
pub const REL_HWHEEL: u16 = 0x06;
pub const REL_DIAL: u16 = 0x07;
pub const REL_WHEEL: u16 = 0x08;
pub const REL_MAX: u16 = 0x0f;

// ABS_* codes.
pub const ABS_X: u16 = 0x00;
pub const ABS_Y: u16 = 0x01;
pub const ABS_THROTTLE: u16 = 0x06;
pub const ABS_HAT0X: u16 = 0x10;
pub const ABS_HAT3Y: u16 = 0x17;
pub const ABS_DISTANCE: u16 = 0x19;
pub const ABS_MT_SLOT: u16 = 0x2f;
pub const ABS_MT_POSITION_X: u16 = 0x35;
pub const ABS_MT_POSITION_Y: u16 = 0x36;
pub const ABS_MT_TRACKING_ID: u16 = 0x39;
pub const ABS_MT_PRESSURE: u16 = 0x3a;
pub const ABS_MT_TOOL_Y: u16 = 0x3d;
pub const ABS_MAX: u16 = 0x3f;

// LED_* ioctl counts.
pub const LED_MAX: u16 = 0x0f;

// REP_* codes.
pub const REP_DELAY: u16 = 0x00;
pub const REP_PERIOD: u16 = 0x01;

// inotify — sys/inotify.h + linux/inotify.h. Only the bits the event
// loop reads.
pub const IN_CREATE: u32 = 0x00000100;
pub const IN_ISDIR: u32 = 0x40000000;
pub const IN_CLOEXEC: c_int = 0o2000000;
pub const IN_NONBLOCK: c_int = 0o4000;

pub const inotify_event = extern struct {
    wd: c_int = 0,
    mask: u32 = 0,
    cookie: u32 = 0,
    len: u32 = 0,
    // `char name[]` flex array — callers advance past the struct by `len`.
};

pub extern "c" fn inotify_init1(flags: c_int) c_int;
pub extern "c" fn inotify_add_watch(fd: c_int, pathname: [*c]const u8, mask: u32) c_int;
