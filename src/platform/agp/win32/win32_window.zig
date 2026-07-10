// Pure-Zig Win32 window for the Windows Vulkan WSI (VK_KHR_win32_surface) —
// the aarch64/x86_64-windows analog of cocoa_window.zig. No Win32 import
// library is link-referenced: user32/gdi32 are resolved at runtime via
// LoadLibrary/GetProcAddress (the "dlopen everything" contract), exactly as
// cocoa_window.zig dlopen's AppKit/Metal. kernel32 (GetModuleHandleW) is the
// one base reference, mirroring cocoa's use of the objc runtime base.
//
// Exports (C ABI, consumed by vk_win32.zig — same surface as cocoa_window):
//   soma_window_create(w, h, title) -> HWND        (null on failure)
//   soma_window_poll() -> bool                       (pump; false = closed)
//   soma_window_next_event(*SomaEvent) -> bool       (drain input ring)
//   soma_window_hinstance() -> HINSTANCE             (for vkCreateWin32SurfaceKHR)

const std = @import("std");

// ── Win32 types ─────────────────────────────────────────────────────────────
const HANDLE = ?*anyopaque;
const HWND = ?*anyopaque;
const HINSTANCE = ?*anyopaque;
const HICON = ?*anyopaque;
const HCURSOR = ?*anyopaque;
const HBRUSH = ?*anyopaque;
const HMENU = ?*anyopaque;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;
const UINT = u32;
const DWORD = u32;
const ATOM = u16;
const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

const POINT = extern struct { x: i32 = 0, y: i32 = 0 };
const MSG = extern struct {
    hwnd: HWND = null,
    message: UINT = 0,
    wParam: WPARAM = 0,
    lParam: LPARAM = 0,
    time: DWORD = 0,
    pt: POINT = .{},
    lPrivate: DWORD = 0,
};
const WNDCLASSEXW = extern struct {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: HINSTANCE,
    hIcon: HICON,
    hCursor: HCURSOR,
    hbrBackground: HBRUSH,
    lpszMenuName: ?[*:0]const u16,
    lpszClassName: ?[*:0]const u16,
    hIconSm: HICON,
};

// window styles / messages
const WS_OVERLAPPEDWINDOW: DWORD = 0x00CF0000;
const WS_VISIBLE: DWORD = 0x10000000;
const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
const SW_SHOW: i32 = 5;
const PM_REMOVE: UINT = 0x0001;
const WM_DESTROY: UINT = 0x0002;
const WM_SIZE: UINT = 0x0005;
const WM_CLOSE: UINT = 0x0010;
const WM_KEYDOWN: UINT = 0x0100;
const WM_KEYUP: UINT = 0x0101;
const WM_CHAR: UINT = 0x0102;
const WM_SYSKEYDOWN: UINT = 0x0104;
const WM_SYSKEYUP: UINT = 0x0105;
const WM_MOUSEMOVE: UINT = 0x0200;
const WM_LBUTTONDOWN: UINT = 0x0201;
const WM_LBUTTONUP: UINT = 0x0202;
const WM_RBUTTONDOWN: UINT = 0x0204;
const WM_RBUTTONUP: UINT = 0x0205;
const WM_MBUTTONDOWN: UINT = 0x0207;
const WM_MBUTTONUP: UINT = 0x0208;
const WM_MOUSEWHEEL: UINT = 0x020A;
const IDC_ARROW: usize = 32512;

// ── runtime-resolved user32/kernel32 entrypoints (dlopen'd) ──────────────────
extern "kernel32" fn LoadLibraryA(name: [*:0]const u8) callconv(.winapi) HANDLE;
extern "kernel32" fn GetProcAddress(mod: HANDLE, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetModuleHandleW(name: ?[*:0]const u16) callconv(.winapi) HINSTANCE;

const rt = struct {
    var RegisterClassExW: *const fn (*const WNDCLASSEXW) callconv(.winapi) ATOM = undefined;
    var CreateWindowExW: *const fn (DWORD, ?[*:0]const u16, ?[*:0]const u16, DWORD, i32, i32, i32, i32, HWND, HMENU, HINSTANCE, ?*anyopaque) callconv(.winapi) HWND = undefined;
    var DefWindowProcW: *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT = undefined;
    var ShowWindow: *const fn (HWND, i32) callconv(.winapi) c_int = undefined;
    var DestroyWindow: *const fn (HWND) callconv(.winapi) c_int = undefined;
    var PeekMessageW: *const fn (*MSG, HWND, UINT, UINT, UINT) callconv(.winapi) c_int = undefined;
    var TranslateMessage: *const fn (*const MSG) callconv(.winapi) c_int = undefined;
    var DispatchMessageW: *const fn (*const MSG) callconv(.winapi) LRESULT = undefined;
    var LoadCursorW: *const fn (HINSTANCE, usize) callconv(.winapi) HCURSOR = undefined;
    var ready: bool = false;
};

fn rtResolve() bool {
    if (rt.ready) return true;
    const u32dll = LoadLibraryA("user32.dll") orelse return false;
    const g = struct {
        fn sym(m: HANDLE, comptime T: type, name: [*:0]const u8) ?T {
            return @ptrCast(@alignCast(GetProcAddress(m, name) orelse return null));
        }
    };
    rt.RegisterClassExW = g.sym(u32dll, @TypeOf(rt.RegisterClassExW), "RegisterClassExW") orelse return false;
    rt.CreateWindowExW = g.sym(u32dll, @TypeOf(rt.CreateWindowExW), "CreateWindowExW") orelse return false;
    rt.DefWindowProcW = g.sym(u32dll, @TypeOf(rt.DefWindowProcW), "DefWindowProcW") orelse return false;
    rt.ShowWindow = g.sym(u32dll, @TypeOf(rt.ShowWindow), "ShowWindow") orelse return false;
    rt.DestroyWindow = g.sym(u32dll, @TypeOf(rt.DestroyWindow), "DestroyWindow") orelse return false;
    rt.PeekMessageW = g.sym(u32dll, @TypeOf(rt.PeekMessageW), "PeekMessageW") orelse return false;
    rt.TranslateMessage = g.sym(u32dll, @TypeOf(rt.TranslateMessage), "TranslateMessage") orelse return false;
    rt.DispatchMessageW = g.sym(u32dll, @TypeOf(rt.DispatchMessageW), "DispatchMessageW") orelse return false;
    rt.LoadCursorW = g.sym(u32dll, @TypeOf(rt.LoadCursorW), "LoadCursorW") orelse return false;
    rt.ready = true;
    return true;
}

// ── event ring (ABI shared with vk_win32.zig / video.zig — keep in sync) ─────
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
const EV_KEYDOWN = 1;
const EV_KEYUP = 2;
const EV_MOTION = 3;
const EV_BTNDOWN = 4;
const EV_BTNUP = 5;
const EV_WHEEL = 6;
const EV_CLOSE = 8;

const RING_CAP = 512;
var ring: [RING_CAP]SomaEvent = undefined;
var ring_r: usize = 0;
var ring_w: usize = 0;

fn ringPush(ev: SomaEvent) void {
    const next = (ring_w + 1) % RING_CAP;
    if (next == ring_r) return; // full, drop
    ring[ring_w] = ev;
    ring_w = next;
}

fn zeroEv(kind: u32) SomaEvent {
    var ev = std.mem.zeroes(SomaEvent);
    ev.kind = kind;
    return ev;
}

var g_hwnd: HWND = null;
var g_hinstance: HINSTANCE = null;
var g_running: bool = true;

fn loWord(l: LPARAM) i16 {
    return @bitCast(@as(u16, @truncate(@as(usize, @bitCast(l)))));
}
fn hiWord(l: LPARAM) i16 {
    return @bitCast(@as(u16, @truncate(@as(usize, @bitCast(l)) >> 16)));
}

fn wndProc(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT {
    switch (msg) {
        WM_CLOSE, WM_DESTROY => {
            g_running = false;
            ringPush(zeroEv(EV_CLOSE));
            return 0;
        },
        WM_KEYDOWN, WM_SYSKEYDOWN => {
            var ev = zeroEv(EV_KEYDOWN);
            ev.keycode = @truncate(wParam);
            ringPush(ev);
            return 0;
        },
        WM_KEYUP, WM_SYSKEYUP => {
            var ev = zeroEv(EV_KEYUP);
            ev.keycode = @truncate(wParam);
            ringPush(ev);
            return 0;
        },
        WM_MOUSEMOVE => {
            var ev = zeroEv(EV_MOTION);
            ev.x = @floatFromInt(loWord(lParam));
            ev.y = @floatFromInt(hiWord(lParam));
            ringPush(ev);
            return 0;
        },
        WM_LBUTTONDOWN => { pushBtn(EV_BTNDOWN, 0); return 0; },
        WM_LBUTTONUP => { pushBtn(EV_BTNUP, 0); return 0; },
        WM_RBUTTONDOWN => { pushBtn(EV_BTNDOWN, 2); return 0; },
        WM_RBUTTONUP => { pushBtn(EV_BTNUP, 2); return 0; },
        WM_MBUTTONDOWN => { pushBtn(EV_BTNDOWN, 1); return 0; },
        WM_MBUTTONUP => { pushBtn(EV_BTNUP, 1); return 0; },
        WM_MOUSEWHEEL => {
            var ev = zeroEv(EV_WHEEL);
            ev.dy = @floatFromInt(hiWord(lParam)); // WHEEL_DELTA multiples
            ringPush(ev);
            return 0;
        },
        else => return rt.DefWindowProcW(hwnd, msg, wParam, lParam),
    }
}

fn pushBtn(kind: u32, button: i32) void {
    var ev = zeroEv(kind);
    ev.button = button;
    ringPush(ev);
}

// ── UTF-16 helpers (window class/title are wide strings) ─────────────────────
var class_w: [32]u16 = undefined;
var title_w: [256]u16 = undefined;

fn utf8ToW(dst: []u16, src: [*:0]const u8) [*:0]const u16 {
    var i: usize = 0;
    while (src[i] != 0 and i + 1 < dst.len) : (i += 1) dst[i] = src[i];
    dst[i] = 0;
    return @ptrCast(dst.ptr);
}

// ── exported API ─────────────────────────────────────────────────────────────
export fn soma_window_create(w: c_int, h: c_int, title: [*:0]const u8) HWND {
    if (!rtResolve()) {
        std.log.err("win32: user32.dll dlopen/resolve failed", .{});
        return null;
    }
    g_hinstance = GetModuleHandleW(null);

    const cls = utf8ToW(&class_w, "SomaVkWindow");
    var wc = std.mem.zeroes(WNDCLASSEXW);
    wc.cbSize = @sizeOf(WNDCLASSEXW);
    wc.style = 0x0003; // CS_HREDRAW | CS_VREDRAW
    wc.lpfnWndProc = &wndProc;
    wc.hInstance = g_hinstance;
    wc.hCursor = rt.LoadCursorW(null, IDC_ARROW);
    wc.lpszClassName = cls;
    _ = rt.RegisterClassExW(&wc);

    const ttl = utf8ToW(&title_w, title);
    g_hwnd = rt.CreateWindowExW(
        0,
        cls,
        ttl,
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        w,
        h,
        null,
        null,
        g_hinstance,
        null,
    );
    if (g_hwnd == null) return null;
    _ = rt.ShowWindow(g_hwnd, SW_SHOW);
    return g_hwnd;
}

export fn soma_window_hinstance() HINSTANCE {
    return g_hinstance;
}

export fn soma_window_poll() bool {
    var msg: MSG = .{};
    while (rt.PeekMessageW(&msg, null, 0, 0, PM_REMOVE) != 0) {
        _ = rt.TranslateMessage(&msg);
        _ = rt.DispatchMessageW(&msg);
    }
    return g_running;
}

export fn soma_window_next_event(out: *SomaEvent) bool {
    if (ring_r == ring_w) return false;
    out.* = ring[ring_r];
    ring_r = (ring_r + 1) % RING_CAP;
    return true;
}
