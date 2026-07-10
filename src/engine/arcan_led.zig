// Pure Zig port of engine/arcan_led.c — zero C helpers.
// LED controller interface: registry, FIFO communication, protocol commands.
// No USB_SUPPORT in compositor build — no hidapi dependency.

const std = @import("std");

const c = struct {
    extern fn open(path: [*c]const u8, flags: c_int, ...) callconv(.c) c_int;
    extern fn write(fd: c_int, buf: [*c]const u8, count: usize) isize;
    extern fn close(fd: c_int) c_int;
    extern fn free(ptr: ?*anyopaque) void;

    const O_NONBLOCK: c_int = 0o4000;
    const O_WRONLY: c_int = 0o1;
    const EAGAIN: c_int = 11;
    const EPIPE: c_int = 32;
};

extern fn __errno_location() *c_int;

// Engine callbacks (defined in arcan_event.c)
extern fn arcan_led_added(devid: c_int, refdev: c_int, label: [*c]const u8) void;
extern fn arcan_led_removed(devid: c_int) void;
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;

// Database API
const arcan_dbh = anyopaque;
extern fn arcan_db_get_shared(appl: *[*c]const u8) ?*arcan_dbh;
extern fn arcan_db_appl_val(dbh: ?*arcan_dbh, appl: [*c]const u8, key: [*c]const u8) [*c]u8;

const MAX_LED_CONTROLLERS = 64;

const ControllerType = enum(c_int) {
    pacdrive = 1,
    arcan_ledctrl = 2,
};

const led_capabilities = extern struct {
    nleds: c_int,
    variable_brightness: bool,
    rgb: bool,
};

const LedController = struct {
    ctrl_type: ControllerType = .arcan_ledctrl,
    caps: led_capabilities = .{ .nleds = 0, .variable_brightness = false, .rgb = false },
    devid: u64 = 0,
    errc: c_int = 0,
    fd: c_int = -1,
    ledmask: u16 = 0,
    path: [*c]u8 = null,
    no_close: bool = false,
};

const UsbEnt = struct {
    vid: u16,
    pid: u16,
};

const usb_tbl = [_]UsbEnt{
    .{ .vid = 0xd209, .pid = 0x1500 },
    .{ .vid = 0xd209, .pid = 0x1501 },
    .{ .vid = 0xd209, .pid = 0x1502 },
    .{ .vid = 0xd209, .pid = 0x1503 },
    .{ .vid = 0xd209, .pid = 0x1504 },
    .{ .vid = 0xd209, .pid = 0x1505 },
    .{ .vid = 0xd209, .pid = 0x1506 },
    .{ .vid = 0xd209, .pid = 0x1507 },
    .{ .vid = 0xd209, .pid = 0x1508 },
};

var controllers: [MAX_LED_CONTROLLERS]LedController = [_]LedController{.{}} ** MAX_LED_CONTROLLERS;
var ctrl_mask: u64 = 0;
var n_controllers: c_int = 0;

fn find_free_ind() c_int {
    for (0..MAX_LED_CONTROLLERS) |i| {
        if ((ctrl_mask & (@as(u64, 1) << @intCast(i))) == 0)
            return @intCast(i);
    }
    return -1;
}

fn get_device(devind: u8) ?*LedController {
    if (devind >= MAX_LED_CONTROLLERS or
        (ctrl_mask & (@as(u64, 1) << @intCast(devind))) == 0)
        return null;
    return &controllers[devind];
}

fn write_leddev(dev: *LedController, ind: c_int, buf: [*c]const u8, sz: usize) c_int {
    if (dev.fd == -1) {
        dev.fd = c.open(dev.path, c.O_NONBLOCK | c.O_WRONLY);
        if (dev.fd == -1)
            return 0;
    }

    while (true) {
        const rv = c.write(dev.fd, buf, sz);
        if (rv == -1) {
            const err = __errno_location().*;
            if (err == c.EAGAIN)
                return 0;
            if (err == c.EPIPE) {
                if (!dev.no_close) {
                    _ = arcan_led_remove(@intCast(@as(u32, @bitCast(ind))));
                    return -1;
                }
                break;
            }
            return 0;
        }
        if (rv == @as(isize, @intCast(sz)))
            return 1;
        return 0;
    }
    return 0;
}

fn register_fifo(path: [*c]u8, ind: c_int) bool {
    if (ind < 0 or ind > 99)
        return false;

    var buf: [32]u8 = undefined;
    const label = std.fmt.bufPrintZ(&buf, "(led-fifo {d})", .{ind}) catch return false;
    _ = label;

    const ledid = arcan_led_register(-1, -1, &buf, .{
        .nleds = 255,
        .variable_brightness = true,
        .rgb = true,
    });

    if (ledid != -1) {
        const uid: usize = @intCast(@as(u8, @bitCast(ledid)));
        controllers[uid].no_close = true;
        controllers[uid].path = path;
        return true;
    }
    return false;
}

export fn arcan_led_register(
    cmd_ch: c_int,
    devref: c_int,
    label: [*c]const u8,
    caps: led_capabilities,
) i8 {
    const id = find_free_ind();
    if (id == -1) return -1;

    const uid: usize = @intCast(id);
    ctrl_mask |= @as(u64, 1) << @intCast(uid);
    controllers[uid].devid = uid;
    controllers[uid].fd = cmd_ch;
    controllers[uid].ctrl_type = .arcan_ledctrl;
    controllers[uid].ledmask = 0;
    controllers[uid].caps = caps;
    controllers[uid].errc = 0;
    controllers[uid].no_close = false;

    n_controllers += 1;
    arcan_led_added(id, devref, label);
    return @intCast(id);
}

export fn arcan_led_remove(device: u8) bool {
    const leddev = get_device(device) orelse return false;
    _ = leddev;

    ctrl_mask &= ~(@as(u64, 1) << @intCast(device));
    n_controllers -= 1;
    arcan_led_removed(@intCast(device));
    return true;
}

export fn arcan_led_known(vid: u16, pid: u16) bool {
    for (usb_tbl) |ent| {
        if (ent.vid == vid and ent.pid == pid)
            return true;
    }
    return false;
}

export fn arcan_led_init() void {
    var appl: [*c]const u8 = null;
    const dbh = arcan_db_get_shared(&appl);

    var kv = arcan_db_appl_val(dbh, appl, "ext_led");
    if (kv != null and register_fifo(kv, 1)) {
        for (2..10) |i| {
            var work: [16]u8 = undefined;
            const key = std.fmt.bufPrintZ(&work, "ext_led_{d}", .{i}) catch break;
            _ = key;
            kv = arcan_db_appl_val(dbh, appl, &work);
            if (kv == null or !register_fifo(kv, @intCast(i))) {
                c.free(kv);
            }
        }
    } else {
        c.free(kv);
    }
}

export fn arcan_led_controllers() u64 {
    return ctrl_mask;
}

export fn arcan_led_intensity(device: u8, led: i16, intensity_arg: u8) c_int {
    const leddev = get_device(device) orelse return 0;
    const di: u16 = if (led < 0) 255 else @intCast(led);

    if (leddev.caps.nleds > 0 and di != 255 and di > @as(u16, @intCast(leddev.caps.nleds - 1)))
        return 0;

    var intensity = intensity_arg;
    if (!leddev.caps.variable_brightness)
        intensity = if (intensity > 0) 255 else 0;

    switch (controllers[device].ctrl_type) {
        .arcan_ledctrl => {
            if (led < 0)
                return write_leddev(leddev, @intCast(device), &[_]u8{ 'A', 0, 'i', intensity, 'c', 0 }, 6)
            else
                return write_leddev(leddev, @intCast(device), &[_]u8{ 'a', @intCast(led), 'i', intensity, 'c', 0 }, 6);
        },
        .pacdrive => {
            return 0;
        },
    }
}

export fn arcan_led_rgb(device: u8, led: i16, r: u8, g: u8, b: u8, buffer: bool) c_int {
    const leddev = get_device(device) orelse return -1;
    if (!leddev.caps.rgb or led > @as(i16, @intCast(leddev.caps.nleds)))
        return -1;

    switch (leddev.ctrl_type) {
        .arcan_ledctrl => {
            const v = if (led < 0)
                write_leddev(leddev, @intCast(device), &[_]u8{ 'A', 0 }, 2)
            else
                write_leddev(leddev, @intCast(device), &[_]u8{ 'a', @intCast(led) }, 2);

            if (v == 1)
                return write_leddev(leddev, @intCast(device), &[_]u8{ 'r', r, 'g', g, 'b', b, 'c', if (buffer) 255 else 0 }, 8)
            else
                return v;
        },
        .pacdrive => {
            return -1;
        },
    }
}

export fn arcan_led_capabilities(device: u8) led_capabilities {
    const leddev = get_device(device) orelse
        return .{ .nleds = 0, .variable_brightness = false, .rgb = false };
    return leddev.caps;
}

export fn arcan_led_shutdown() void {
    var i: usize = 0;
    while (i < MAX_LED_CONTROLLERS and n_controllers > 0) : (i += 1) {
        if ((ctrl_mask & (@as(u64, 1) << @intCast(i))) != 0) {
            n_controllers -= 1;
            switch (controllers[i].ctrl_type) {
                .pacdrive => {},
                .arcan_ledctrl => {
                    _ = c.write(controllers[i].fd, &[_]u8{ 'o', 0 }, 2);
                    _ = c.close(controllers[i].fd);
                    c.free(controllers[i].path);
                    controllers[i].path = null;
                },
            }
        }
    }
    ctrl_mask = 0;
}
