// macOS Metal-surface WSI for the vk-display platform — the Cocoa/CAMetalLayer
// counterpart of vk_xcb.zig. Window + input come from soma_window.m (event
// ring); the surface is VK_EXT_metal_surface; the swapchain is the shared
// vk_wsi.Swapchain (pure Vulkan, WSI-agnostic).
//
// Link: soma_window.o -lobjc -framework Cocoa -framework QuartzCore -framework Metal

const std = @import("std");
const vk = @import("vulkan");

// ── soma_window.m ABI (keep in sync) ──────────────────────────────────────
pub const SomaEvent = extern struct {
    kind: u32,
    keycode: u32,
    mods: u32,
    utf8: [8]u8,
    x: f32,
    y: f32,
    button: i32,
    dx: f32,
    dy: f32,
    w: u32,
    h: u32,
};

pub const EV_KEYDOWN = 1;
pub const EV_KEYUP = 2;
pub const EV_MOTION = 3;
pub const EV_BTNDOWN = 4;
pub const EV_BTNUP = 5;
pub const EV_WHEEL = 6;
pub const EV_RESIZE = 7;
pub const EV_CLOSE = 8;

const MOD_SHIFT = 1;
const MOD_CTRL = 2;
const MOD_ALT = 4;
const MOD_META = 8;
const MOD_CAPS = 16;

extern fn soma_window_create(w: c_int, h: c_int, title: [*:0]const u8) ?*anyopaque;
extern fn soma_window_poll() bool;
extern fn soma_window_next_event(out: *SomaEvent) bool;

pub const MetalWindow = struct {
    layer: *anyopaque,
    width: u16,
    height: u16,
    alive: bool = true,
    exit_sent: bool = false,
    // drained input batch for video.zig's processMetalInput
    input_events: [128]SomaEvent = undefined,
    input_count: usize = 0,
};

pub fn createMetalWindow(w: u16, h: u16, title: [*:0]const u8) !MetalWindow {
    const layer = soma_window_create(@intCast(w), @intCast(h), title) orelse
        return error.WindowCreateFailed;
    return .{ .layer = layer, .width = w, .height = h };
}

pub fn createMetalSurface(vki: anytype, instance: vk.Instance, win: *MetalWindow) !vk.SurfaceKHR {
    return vki.createMetalSurfaceEXT(instance, &.{ .p_layer = @ptrCast(win.layer) }, null);
}

// Pump Cocoa + drain the ring into win.input_events. Marks the window dead
// when the user closed it (caller decides how to shut the engine down).
pub fn pollEvents(win: *MetalWindow) void {
    if (!soma_window_poll()) win.alive = false;
    win.input_count = 0;
    var ev: SomaEvent = undefined;
    while (win.input_count < win.input_events.len and soma_window_next_event(&ev)) {
        if (ev.kind == EV_CLOSE) win.alive = false;
        win.input_events[win.input_count] = ev;
        win.input_count += 1;
    }
}

// ── SDL 1.2 keysyms (what the engine's TRANSLATED events carry) ───────────
const K_BACKSPACE = 8;
const K_TAB = 9;
const K_RETURN = 13;
const K_ESCAPE = 27;
const K_SPACE = 32;
const K_DELETE = 127;
const K_KP0 = 256;
const K_KP_PERIOD = 266;
const K_KP_DIVIDE = 267;
const K_KP_MULTIPLY = 268;
const K_KP_MINUS = 269;
const K_KP_PLUS = 270;
const K_KP_ENTER = 271;
const K_KP_EQUALS = 272;
const K_UP = 273;
const K_DOWN = 274;
const K_RIGHT = 275;
const K_LEFT = 276;
const K_INSERT = 277;
const K_HOME = 278;
const K_END = 279;
const K_PAGEUP = 280;
const K_PAGEDOWN = 281;
const K_F1 = 282; // F1..F15 = 282..296
const K_CAPSLOCK = 301;
const K_RSHIFT = 303;
const K_LSHIFT = 304;
const K_RCTRL = 305;
const K_LCTRL = 306;
const K_RALT = 307;
const K_LALT = 308;
const K_RMETA = 309;
const K_LMETA = 310;

// macOS virtual keycode (kVK_*) → SDL 1.2 keysym
pub fn macKeyToSdl12(keycode: u32) u16 {
    return switch (keycode) {
        0 => 'a', 1 => 's', 2 => 'd', 3 => 'f', 4 => 'h', 5 => 'g',
        6 => 'z', 7 => 'x', 8 => 'c', 9 => 'v', 11 => 'b', 12 => 'q',
        13 => 'w', 14 => 'e', 15 => 'r', 16 => 'y', 17 => 't',
        18 => '1', 19 => '2', 20 => '3', 21 => '4', 22 => '6', 23 => '5',
        24 => '=', 25 => '9', 26 => '7', 27 => '-', 28 => '8', 29 => '0',
        30 => ']', 31 => 'o', 32 => 'u', 33 => '[', 34 => 'i', 35 => 'p',
        36 => K_RETURN, 37 => 'l', 38 => 'j', 39 => '\'', 40 => 'k',
        41 => ';', 42 => '\\', 43 => ',', 44 => '/', 45 => 'n', 46 => 'm',
        47 => '.', 48 => K_TAB, 49 => K_SPACE, 50 => '`',
        51 => K_BACKSPACE, 53 => K_ESCAPE,
        54 => K_RMETA, 55 => K_LMETA, 56 => K_LSHIFT, 57 => K_CAPSLOCK,
        58 => K_LALT, 59 => K_LCTRL, 60 => K_RSHIFT, 61 => K_RALT,
        62 => K_RCTRL,
        65 => K_KP_PERIOD, 67 => K_KP_MULTIPLY, 69 => K_KP_PLUS,
        75 => K_KP_DIVIDE, 76 => K_KP_ENTER, 78 => K_KP_MINUS,
        81 => K_KP_EQUALS,
        82 => K_KP0, 83 => K_KP0 + 1, 84 => K_KP0 + 2, 85 => K_KP0 + 3,
        86 => K_KP0 + 4, 87 => K_KP0 + 5, 88 => K_KP0 + 6, 89 => K_KP0 + 7,
        91 => K_KP0 + 8, 92 => K_KP0 + 9,
        96 => K_F1 + 4, 97 => K_F1 + 5, 98 => K_F1 + 6, 99 => K_F1 + 2,
        100 => K_F1 + 7, 101 => K_F1 + 8, 103 => K_F1 + 10,
        105 => K_F1 + 12, 106 => K_F1 + 15, 107 => K_F1 + 13,
        109 => K_F1 + 9, 111 => K_F1 + 11, 113 => K_F1 + 14,
        114 => K_INSERT, 115 => K_HOME, 116 => K_PAGEUP,
        117 => K_DELETE, 118 => K_F1 + 3, 119 => K_END, 120 => K_F1 + 1,
        121 => K_PAGEDOWN, 122 => K_F1, 123 => K_LEFT, 124 => K_RIGHT,
        125 => K_DOWN, 126 => K_UP,
        else => 0,
    };
}

// SOMA_MOD_* → SDL 1.2 KMOD bitmask (ARKMOD_*: LSHIFT=1, LCTRL=64,
// LALT=256, LMETA=1024, CAPS=8192)
pub fn modsToSdl12(mods: u32) u16 {
    var out: u16 = 0;
    if (mods & MOD_SHIFT != 0) out |= 0x0001;
    if (mods & MOD_CTRL != 0) out |= 0x0040;
    if (mods & MOD_ALT != 0) out |= 0x0100;
    if (mods & MOD_META != 0) out |= 0x0400;
    if (mods & MOD_CAPS != 0) out |= 0x2000;
    return out;
}
