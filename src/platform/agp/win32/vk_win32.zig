// Windows Win32-surface WSI for the vk-display platform — the win32_window.zig
// counterpart of vk_metal.zig / vk_xcb.zig. Window + input come from
// win32_window.zig (event ring); the surface is VK_KHR_win32_surface; the
// swapchain is the shared vk_wsi.Swapchain (pure Vulkan, WSI-agnostic).
//
// user32/gdi32 are dlopen'd inside win32_window.zig; nothing here is linked
// directly. The Vulkan entry points come from the dlopen'd vulkan-1.dll loader.

const std = @import("std");
const vk = @import("vulkan");

// ── win32_window.zig ABI (keep in sync) ─────────────────────────────────────
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
extern fn soma_window_hinstance() ?*anyopaque;
extern fn soma_window_poll() bool;
extern fn soma_window_next_event(out: *SomaEvent) bool;

pub const Win32Window = struct {
    hwnd: *anyopaque,
    hinstance: ?*anyopaque,
    width: u16,
    height: u16,
    alive: bool = true,
    exit_sent: bool = false,
    input_events: [128]SomaEvent = undefined,
    input_count: usize = 0,
};

pub fn createWin32Window(w: u16, h: u16, title: [*:0]const u8) !Win32Window {
    const hwnd = soma_window_create(@intCast(w), @intCast(h), title) orelse
        return error.WindowCreateFailed;
    return .{ .hwnd = hwnd, .hinstance = soma_window_hinstance(), .width = w, .height = h };
}

pub fn createWin32Surface(vki: anytype, instance: vk.Instance, win: *Win32Window) !vk.SurfaceKHR {
    return vki.createWin32SurfaceKHR(instance, &.{
        .hinstance = @ptrCast(win.hinstance),
        .hwnd = @ptrCast(win.hwnd),
    }, null);
}

pub fn pollEvents(win: *Win32Window) void {
    if (!soma_window_poll()) win.alive = false;
    win.input_count = 0;
    var ev: SomaEvent = undefined;
    while (win.input_count < win.input_events.len and soma_window_next_event(&ev)) {
        if (ev.kind == EV_CLOSE) win.alive = false;
        win.input_events[win.input_count] = ev;
        win.input_count += 1;
    }
}

// ── SDL 1.2 keysyms (what the engine's TRANSLATED events carry) ─────────────
const K_BACKSPACE = 8;
const K_TAB = 9;
const K_RETURN = 13;
const K_ESCAPE = 27;
const K_SPACE = 32;
const K_DELETE = 127;
const K_UP = 273;
const K_DOWN = 274;
const K_RIGHT = 275;
const K_LEFT = 276;
const K_INSERT = 277;
const K_HOME = 278;
const K_END = 279;
const K_PAGEUP = 280;
const K_PAGEDOWN = 281;
const K_F1 = 282; // F1..F12 = 282..293
const K_LSHIFT = 304;
const K_LCTRL = 306;
const K_LALT = 308;

// Windows virtual-key code (VK_*) → SDL 1.2 keysym
pub fn winKeyToSdl12(vkcode: u32) u16 {
    return switch (vkcode) {
        0x08 => K_BACKSPACE,
        0x09 => K_TAB,
        0x0D => K_RETURN,
        0x1B => K_ESCAPE,
        0x20 => K_SPACE,
        0x25 => K_LEFT,
        0x26 => K_UP,
        0x27 => K_RIGHT,
        0x28 => K_DOWN,
        0x2D => K_INSERT,
        0x2E => K_DELETE,
        0x24 => K_HOME,
        0x23 => K_END,
        0x21 => K_PAGEUP,
        0x22 => K_PAGEDOWN,
        0x10 => K_LSHIFT,
        0x11 => K_LCTRL,
        0x12 => K_LALT,
        0x30...0x39 => @intCast(vkcode), // '0'..'9' == VK 0x30..0x39
        0x41...0x5A => @intCast(vkcode + 0x20), // 'A'..'Z' -> lowercase 'a'..'z'
        0x70...0x7B => @intCast(K_F1 + (vkcode - 0x70)), // VK_F1..VK_F12
        else => 0,
    };
}

pub fn modsToSdl12(mods: u32) u16 {
    var out: u16 = 0;
    if (mods & MOD_SHIFT != 0) out |= 0x0001;
    if (mods & MOD_CTRL != 0) out |= 0x0040;
    if (mods & MOD_ALT != 0) out |= 0x0100;
    if (mods & MOD_META != 0) out |= 0x0400;
    if (mods & MOD_CAPS != 0) out |= 0x2000;
    return out;
}
