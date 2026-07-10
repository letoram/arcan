// Pure-Zig Cocoa window with a CAMetalLayer for the macOS Vulkan WSI
// (VK_EXT_metal_surface) — no Objective-C source, just the objc runtime
// C ABI (objc_msgSend / objc_allocateClassPair), in the same spirit as
// xcb_cabi.zig / drm_cabi.zig. arm64-only assumption: every message goes
// through plain objc_msgSend (no stret/fpret variants on Apple Silicon).
//
// Exports (C ABI, consumed by vk_metal.zig and the vk_window harness):
//   soma_window_create(w, h, title) -> CAMetalLayer*   (null on failure)
//   soma_window_poll() -> bool                          (pump; false = closed)
//   soma_window_next_event(*SomaEvent) -> bool          (drain input ring)
//
// No link-time framework/libobjc dependency: everything below libSystem is
// resolved at runtime via dlopen/dlsym ("dlopen everything"), so the binary
// can be cross-linked from Linux against zig's bundled libSystem stubs.

const std = @import("std");

// ── objc runtime cabi ──────────────────────────────────────────────────────
const id = ?*anyopaque;
const Class = ?*anyopaque;
const SEL = ?*anyopaque;

// dlopen/dlsym are libSystem — the only link-time dependency we keep.
const RTLD_NOW: c_int = 0x2;
const RTLD_GLOBAL: c_int = 0x8;
const RTLD_DEFAULT: ?*anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -2))));
extern "c" fn dlopen(path: ?[*:0]const u8, mode: c_int) ?*anyopaque;
extern "c" fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;

const rt = struct {
    var objc_getClass: *const fn ([*:0]const u8) callconv(.c) Class = undefined;
    var sel_registerName: *const fn ([*:0]const u8) callconv(.c) SEL = undefined;
    var objc_allocateClassPair: *const fn (Class, [*:0]const u8, usize) callconv(.c) Class = undefined;
    var objc_registerClassPair: *const fn (Class) callconv(.c) void = undefined;
    var class_addMethod: *const fn (Class, SEL, ?*const anyopaque, [*:0]const u8) callconv(.c) bool = undefined;
    var objc_msgSend: *const anyopaque = undefined;
    var MTLCreateSystemDefaultDevice: *const fn () callconv(.c) id = undefined;
    var NSDefaultRunLoopMode: *id = undefined;
    var ready: bool = false;
};

fn rtResolve() bool {
    if (rt.ready) return true;
    // libobjc + the frameworks whose classes we message. Loading a framework
    // registers its ObjC classes with the runtime; RTLD_GLOBAL exposes its C
    // symbols to the RTLD_DEFAULT lookups below.
    if (dlopen("/usr/lib/libobjc.A.dylib", RTLD_NOW | RTLD_GLOBAL) == null) return false;
    if (dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_NOW | RTLD_GLOBAL) == null) return false;
    if (dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_NOW | RTLD_GLOBAL) == null) return false;
    if (dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_NOW | RTLD_GLOBAL) == null) return false;
    rt.objc_getClass = @ptrCast(@alignCast(dlsym(RTLD_DEFAULT, "objc_getClass") orelse return false));
    rt.sel_registerName = @ptrCast(@alignCast(dlsym(RTLD_DEFAULT, "sel_registerName") orelse return false));
    rt.objc_allocateClassPair = @ptrCast(@alignCast(dlsym(RTLD_DEFAULT, "objc_allocateClassPair") orelse return false));
    rt.objc_registerClassPair = @ptrCast(@alignCast(dlsym(RTLD_DEFAULT, "objc_registerClassPair") orelse return false));
    rt.class_addMethod = @ptrCast(@alignCast(dlsym(RTLD_DEFAULT, "class_addMethod") orelse return false));
    rt.objc_msgSend = dlsym(RTLD_DEFAULT, "objc_msgSend") orelse return false;
    rt.MTLCreateSystemDefaultDevice = @ptrCast(@alignCast(dlsym(RTLD_DEFAULT, "MTLCreateSystemDefaultDevice") orelse return false));
    rt.NSDefaultRunLoopMode = @ptrCast(@alignCast(dlsym(RTLD_DEFAULT, "NSDefaultRunLoopMode") orelse return false));
    rt.ready = true;
    return true;
}

// Same-named shims so the message-send call sites below read unchanged.
fn objc_getClass(name: [*:0]const u8) Class {
    return rt.objc_getClass(name);
}
fn objc_allocateClassPair(superclass: Class, name: [*:0]const u8, extra_bytes: usize) Class {
    return rt.objc_allocateClassPair(superclass, name, extra_bytes);
}
fn objc_registerClassPair(cls: Class) void {
    rt.objc_registerClassPair(cls);
}
fn class_addMethod(cls: Class, name: SEL, imp: ?*const anyopaque, types: [*:0]const u8) bool {
    return rt.class_addMethod(cls, name, imp, types);
}
fn MTLCreateSystemDefaultDevice() id {
    return rt.MTLCreateSystemDefaultDevice();
}

fn msg(comptime Fn: type) *const Fn {
    return @ptrCast(@alignCast(rt.objc_msgSend));
}
fn sel(name: [*:0]const u8) SEL {
    return rt.sel_registerName(name);
}

const CGPoint = extern struct { x: f64, y: f64 };
const CGSize = extern struct { width: f64, height: f64 };
const CGRect = extern struct { origin: CGPoint, size: CGSize };

// NSEventModifierFlags
const FLAG_CAPS: u64 = 1 << 16;
const FLAG_SHIFT: u64 = 1 << 17;
const FLAG_CTRL: u64 = 1 << 18;
const FLAG_ALT: u64 = 1 << 19;
const FLAG_CMD: u64 = 1 << 20;

// ── event ring (ABI shared with vk_metal.zig — keep in sync) ───────────────
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

const MOD_SHIFT = 1;
const MOD_CTRL = 2;
const MOD_ALT = 4;
const MOD_META = 8;
const MOD_CAPS = 16;

const RING_CAP = 512;
var ring: [RING_CAP]SomaEvent = undefined;
var ring_r: usize = 0;
var ring_w: usize = 0;

fn ringPush(ev: *const SomaEvent) void {
    const next = (ring_w + 1) % RING_CAP;
    if (next == ring_r) return; // full — drop
    ring[ring_w] = ev.*;
    ring_w = next;
}

export fn soma_window_next_event(out: *SomaEvent) bool {
    if (ring_r == ring_w) return false;
    out.* = ring[ring_r];
    ring_r = (ring_r + 1) % RING_CAP;
    return true;
}

fn modsFromFlags(flags: u64) u32 {
    var m: u32 = 0;
    if (flags & FLAG_SHIFT != 0) m |= MOD_SHIFT;
    if (flags & FLAG_CTRL != 0) m |= MOD_CTRL;
    if (flags & FLAG_ALT != 0) m |= MOD_ALT;
    if (flags & FLAG_CMD != 0) m |= MOD_CAPS & 0 | MOD_META;
    if (flags & FLAG_CAPS != 0) m |= MOD_CAPS;
    return m;
}

// ── window state ───────────────────────────────────────────────────────────
var g_app: id = null;
var g_window: id = null;
var g_layer: id = null;
var g_view: id = null;
var g_delegate: id = null;
var g_running: bool = true;
var g_prev_flags: u64 = 0;
var g_classes_ready = false;

fn newPool() id {
    const cls = objc_getClass("NSAutoreleasePool");
    const p = msg(fn (Class, SEL) callconv(.c) id)(cls, sel("alloc"));
    return msg(fn (id, SEL) callconv(.c) id)(p, sel("init"));
}
fn drainPool(p: id) void {
    _ = msg(fn (id, SEL) callconv(.c) void)(p, sel("drain"));
}

// ── view subclass IMPs (input capture) ─────────────────────────────────────
fn impReturnTrue(self_: id, _cmd: SEL) callconv(.c) bool {
    _ = self_;
    _ = _cmd;
    return true;
}
fn impAcceptsFirstMouse(self_: id, _cmd: SEL, ev: id) callconv(.c) bool {
    _ = self_;
    _ = _cmd;
    _ = ev;
    return true;
}

fn eventMods(event: id) u32 {
    const flags = msg(fn (id, SEL) callconv(.c) u64)(event, sel("modifierFlags"));
    return modsFromFlags(flags);
}

fn pushPointerEvent(event: id, kind: u32, button: i32) void {
    const loc = msg(fn (id, SEL) callconv(.c) CGPoint)(event, sel("locationInWindow"));
    const p = msg(fn (id, SEL, CGPoint, id) callconv(.c) CGPoint)(g_view, sel("convertPoint:fromView:"), loc, null);
    const bounds = msg(fn (id, SEL) callconv(.c) CGRect)(g_view, sel("bounds"));
    const dsize = msg(fn (id, SEL) callconv(.c) CGSize)(g_layer, sel("drawableSize"));

    var ev = std.mem.zeroes(SomaEvent);
    ev.kind = kind;
    ev.button = button;
    ev.mods = eventMods(event);
    // view points (bottom-left origin) → drawable pixels (top-left origin)
    const sx: f64 = if (bounds.size.width > 0) dsize.width / bounds.size.width else 1.0;
    const sy: f64 = if (bounds.size.height > 0) dsize.height / bounds.size.height else 1.0;
    ev.x = @floatCast(p.x * sx);
    ev.y = @floatCast((bounds.size.height - p.y) * sy);
    if (kind == EV_WHEEL) {
        ev.dx = @floatCast(msg(fn (id, SEL) callconv(.c) f64)(event, sel("scrollingDeltaX")));
        ev.dy = @floatCast(msg(fn (id, SEL) callconv(.c) f64)(event, sel("scrollingDeltaY")));
    }
    ringPush(&ev);
}

fn impMotion(self_: id, _cmd: SEL, event: id) callconv(.c) void {
    _ = self_;
    _ = _cmd;
    pushPointerEvent(event, EV_MOTION, 0);
}
fn impMouseDown(self_: id, _cmd: SEL, event: id) callconv(.c) void {
    _ = self_;
    _ = _cmd;
    pushPointerEvent(event, EV_BTNDOWN, 1);
}
fn impMouseUp(self_: id, _cmd: SEL, event: id) callconv(.c) void {
    _ = self_;
    _ = _cmd;
    pushPointerEvent(event, EV_BTNUP, 1);
}
fn impRightDown(self_: id, _cmd: SEL, event: id) callconv(.c) void {
    _ = self_;
    _ = _cmd;
    pushPointerEvent(event, EV_BTNDOWN, 2);
}
fn impRightUp(self_: id, _cmd: SEL, event: id) callconv(.c) void {
    _ = self_;
    _ = _cmd;
    pushPointerEvent(event, EV_BTNUP, 2);
}
fn impOtherDown(self_: id, _cmd: SEL, event: id) callconv(.c) void {
    _ = self_;
    _ = _cmd;
    pushPointerEvent(event, EV_BTNDOWN, 3);
}
fn impOtherUp(self_: id, _cmd: SEL, event: id) callconv(.c) void {
    _ = self_;
    _ = _cmd;
    pushPointerEvent(event, EV_BTNUP, 3);
}
fn impWheel(self_: id, _cmd: SEL, event: id) callconv(.c) void {
    _ = self_;
    _ = _cmd;
    pushPointerEvent(event, EV_WHEEL, 0);
}

fn keyEvent(event: id, down: bool) void {
    var ev = std.mem.zeroes(SomaEvent);
    ev.kind = if (down) EV_KEYDOWN else EV_KEYUP;
    ev.keycode = msg(fn (id, SEL) callconv(.c) u16)(event, sel("keyCode"));
    ev.mods = eventMods(event);
    if (down) {
        const chars = msg(fn (id, SEL) callconv(.c) id)(event, sel("characters"));
        if (chars != null) {
            const u = msg(fn (id, SEL) callconv(.c) ?[*:0]const u8)(chars, sel("UTF8String"));
            if (u) |s| {
                const str = std.mem.sliceTo(s, 0);
                const n = @min(str.len, 7);
                // control chars (raw ctrl-combos, esc...) are not text — keep
                // only printable input plus return/tab
                if (n > 0 and str[0] >= 0x20) {
                    @memcpy(ev.utf8[0..n], str[0..n]);
                } else if (n > 0 and (str[0] == 0x0d or str[0] == 0x09)) {
                    ev.utf8[0] = str[0];
                }
            }
        }
    }
    ringPush(&ev);
}

fn impKeyDown(self_: id, _cmd: SEL, event: id) callconv(.c) void {
    _ = self_;
    _ = _cmd;
    keyEvent(event, true);
}
fn impKeyUp(self_: id, _cmd: SEL, event: id) callconv(.c) void {
    _ = self_;
    _ = _cmd;
    keyEvent(event, false);
}

// Synthesize press/release for the modifier keys themselves.
fn impFlagsChanged(self_: id, _cmd: SEL, event: id) callconv(.c) void {
    _ = self_;
    _ = _cmd;
    const flags = msg(fn (id, SEL) callconv(.c) u64)(event, sel("modifierFlags"));
    const changed = flags ^ g_prev_flags;
    g_prev_flags = flags;
    const watched = [_]u64{ FLAG_SHIFT, FLAG_CTRL, FLAG_ALT, FLAG_CMD, FLAG_CAPS };
    for (watched) |flag| {
        if (changed & flag == 0) continue;
        var ev = std.mem.zeroes(SomaEvent);
        ev.kind = if (flags & flag != 0) EV_KEYDOWN else EV_KEYUP;
        ev.keycode = msg(fn (id, SEL) callconv(.c) u16)(event, sel("keyCode"));
        ev.mods = modsFromFlags(flags);
        ringPush(&ev);
    }
}

// ── window delegate IMP ────────────────────────────────────────────────────
fn impWindowShouldClose(self_: id, _cmd: SEL, sender: id) callconv(.c) bool {
    _ = self_;
    _ = _cmd;
    _ = sender;
    g_running = false;
    var ev = std.mem.zeroes(SomaEvent);
    ev.kind = EV_CLOSE;
    ringPush(&ev);
    return true;
}

fn makeClasses() void {
    if (g_classes_ready) return;
    g_classes_ready = true;

    const view_cls = objc_allocateClassPair(objc_getClass("NSView"), "SomaView", 0);
    _ = class_addMethod(view_cls, sel("acceptsFirstResponder"), @ptrCast(&impReturnTrue), "c@:");
    _ = class_addMethod(view_cls, sel("canBecomeKeyView"), @ptrCast(&impReturnTrue), "c@:");
    _ = class_addMethod(view_cls, sel("acceptsFirstMouse:"), @ptrCast(&impAcceptsFirstMouse), "c@:@");
    _ = class_addMethod(view_cls, sel("keyDown:"), @ptrCast(&impKeyDown), "v@:@");
    _ = class_addMethod(view_cls, sel("keyUp:"), @ptrCast(&impKeyUp), "v@:@");
    _ = class_addMethod(view_cls, sel("flagsChanged:"), @ptrCast(&impFlagsChanged), "v@:@");
    _ = class_addMethod(view_cls, sel("mouseMoved:"), @ptrCast(&impMotion), "v@:@");
    _ = class_addMethod(view_cls, sel("mouseDragged:"), @ptrCast(&impMotion), "v@:@");
    _ = class_addMethod(view_cls, sel("rightMouseDragged:"), @ptrCast(&impMotion), "v@:@");
    _ = class_addMethod(view_cls, sel("otherMouseDragged:"), @ptrCast(&impMotion), "v@:@");
    _ = class_addMethod(view_cls, sel("mouseDown:"), @ptrCast(&impMouseDown), "v@:@");
    _ = class_addMethod(view_cls, sel("mouseUp:"), @ptrCast(&impMouseUp), "v@:@");
    _ = class_addMethod(view_cls, sel("rightMouseDown:"), @ptrCast(&impRightDown), "v@:@");
    _ = class_addMethod(view_cls, sel("rightMouseUp:"), @ptrCast(&impRightUp), "v@:@");
    _ = class_addMethod(view_cls, sel("otherMouseDown:"), @ptrCast(&impOtherDown), "v@:@");
    _ = class_addMethod(view_cls, sel("otherMouseUp:"), @ptrCast(&impOtherUp), "v@:@");
    _ = class_addMethod(view_cls, sel("scrollWheel:"), @ptrCast(&impWheel), "v@:@");
    objc_registerClassPair(view_cls);

    const del_cls = objc_allocateClassPair(objc_getClass("NSObject"), "SomaWinDelegate", 0);
    _ = class_addMethod(del_cls, sel("windowShouldClose:"), @ptrCast(&impWindowShouldClose), "c@:@");
    objc_registerClassPair(del_cls);
}

// ── exported API ───────────────────────────────────────────────────────────
export fn soma_window_create(w: c_int, h: c_int, title: [*:0]const u8) ?*anyopaque {
    if (!rtResolve()) {
        std.log.err("cocoa: dlopen/dlsym of libobjc/AppKit/QuartzCore/Metal failed", .{});
        return null;
    }
    const pool = newPool();
    defer drainPool(pool);

    makeClasses();

    const app = msg(fn (Class, SEL) callconv(.c) id)(objc_getClass("NSApplication"), sel("sharedApplication"));
    g_app = app;
    // NSApplicationActivationPolicyRegular = 0
    _ = msg(fn (id, SEL, i64) callconv(.c) bool)(app, sel("setActivationPolicy:"), 0);

    const rect = CGRect{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = @floatFromInt(w), .height = @floatFromInt(h) },
    };

    // v1: fixed-size window (Titled|Closable|Miniaturizable, no Resizable) —
    // swapchain extent stays w×h, no recreate path needed.
    var win = msg(fn (Class, SEL) callconv(.c) id)(objc_getClass("NSWindow"), sel("alloc"));
    win = msg(fn (id, SEL, CGRect, u64, u64, bool) callconv(.c) id)(
        win,
        sel("initWithContentRect:styleMask:backing:defer:"),
        rect,
        1 | 2 | 4, // Titled | Closable | Miniaturizable
        2, // NSBackingStoreBuffered
        false,
    );
    if (win == null) return null;
    g_window = win;

    const nstitle = msg(fn (Class, SEL, [*:0]const u8) callconv(.c) id)(objc_getClass("NSString"), sel("stringWithUTF8String:"), title);
    _ = msg(fn (id, SEL, id) callconv(.c) void)(win, sel("setTitle:"), nstitle);

    const layer = msg(fn (Class, SEL) callconv(.c) id)(objc_getClass("CAMetalLayer"), sel("layer"));
    if (layer == null) return null;
    g_layer = layer;
    _ = msg(fn (id, SEL, id) callconv(.c) void)(layer, sel("setDevice:"), MTLCreateSystemDefaultDevice());
    _ = msg(fn (id, SEL, u64) callconv(.c) void)(layer, sel("setPixelFormat:"), 80); // MTLPixelFormatBGRA8Unorm
    _ = msg(fn (id, SEL, bool) callconv(.c) void)(layer, sel("setFramebufferOnly:"), true);
    _ = msg(fn (id, SEL, CGSize) callconv(.c) void)(layer, sel("setDrawableSize:"), rect.size);

    var view = msg(fn (Class, SEL) callconv(.c) id)(objc_getClass("SomaView"), sel("alloc"));
    view = msg(fn (id, SEL, CGRect) callconv(.c) id)(view, sel("initWithFrame:"), rect);
    g_view = view;
    _ = msg(fn (id, SEL, bool) callconv(.c) void)(view, sel("setWantsLayer:"), true);
    _ = msg(fn (id, SEL, id) callconv(.c) void)(view, sel("setLayer:"), layer);
    _ = msg(fn (id, SEL, id) callconv(.c) void)(win, sel("setContentView:"), view);
    _ = msg(fn (id, SEL, id) callconv(.c) bool)(win, sel("makeFirstResponder:"), view);
    _ = msg(fn (id, SEL, bool) callconv(.c) void)(win, sel("setAcceptsMouseMovedEvents:"), true);

    const del = msg(fn (Class, SEL) callconv(.c) id)(objc_getClass("SomaWinDelegate"), sel("new"));
    g_delegate = del;
    _ = msg(fn (id, SEL, id) callconv(.c) void)(win, sel("setDelegate:"), del);

    _ = msg(fn (id, SEL) callconv(.c) void)(win, sel("center"));
    _ = msg(fn (id, SEL, id) callconv(.c) void)(win, sel("makeKeyAndOrderFront:"), null);
    _ = msg(fn (id, SEL, bool) callconv(.c) void)(app, sel("activateIgnoringOtherApps:"), true);

    return layer;
}

export fn soma_window_poll() bool {
    const pool = newPool();
    defer drainPool(pool);
    while (true) {
        const past = msg(fn (Class, SEL) callconv(.c) id)(objc_getClass("NSDate"), sel("distantPast"));
        const ev = msg(fn (id, SEL, u64, id, id, bool) callconv(.c) id)(
            g_app,
            sel("nextEventMatchingMask:untilDate:inMode:dequeue:"),
            ~@as(u64, 0), // NSEventMaskAny
            past,
            rt.NSDefaultRunLoopMode.*,
            true,
        );
        if (ev == null) break;
        _ = msg(fn (id, SEL, id) callconv(.c) void)(g_app, sel("sendEvent:"), ev);
    }
    return g_running;
}
