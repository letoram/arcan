// Pure Zig port of tui/core/setup.c
// TUI context setup, teardown, initial connection binding, and built-in palette.

const std = @import("std");
const arcan = @import("arcan");

// Constants

// External event kinds (from arcan_shmif_event.h)
const EVENT_EXTERNAL_SEGREQ: c_int = 10;
const EVENT_EXTERNAL_CLOCKREQ: c_int = 18;

// Segment IDs. Use the shmif_types values — those are what the engine and
// the tui dispatcher both agree on over the wire. The constant in
// arcan_shmif_event.h is stale (says 21 for CLIPBOARD), and hardcoding 21
// here made the SEGREQ go out with a kind the engine didn't recognise as
// a clipboard request, so NEWSEGMENT (kind=16) never came back,
// clipOutHasVidp() stayed false, and every arcan_tui_copy silently dropped.
const shmif_types = @import("shmif_types");
const SEGID_CLIPBOARD = shmif_types.SEGID_CLIPBOARD;
const SEGID_TUI = shmif_types.SEGID_TUI;

// shmif render hints (from arcan_shmif_control.h enum rhint_mask)
const SHMIF_RHINT_TPACK: u32 = 128;
const SHMIF_RHINT_VSIGNAL_EV: u32 = 32;

// arcan_shmif_open flags
const SHMIF_ACQUIRE_FATALFAIL: c_uint = 4;

// arcan_shmif_type enum values (from arcan_shmif_control.h)
const SHMIF_ACCESSIBILITY: c_int = 2;

// TUI color group constants (from arcan_tuisym.h enum tui_color_group)
const TUI_COL_PRIMARY: c_int = 2;
const TUI_COL_SECONDARY: c_int = 3;
const TUI_COL_BG: c_int = 4;
const TUI_COL_TEXT: c_int = 5;
const TUI_COL_CURSOR: c_int = 6;
const TUI_COL_ALTCURSOR: c_int = 7;
const TUI_COL_HIGHLIGHT: c_int = 8;
const TUI_COL_LABEL: c_int = 9;
const TUI_COL_WARNING: c_int = 10;
const TUI_COL_ERROR: c_int = 11;
const TUI_COL_ALERT: c_int = 12;
const TUI_COL_REFERENCE: c_int = 13;
const TUI_COL_INACTIVE: c_int = 14;
const TUI_COL_UI: c_int = 15;
// TUI_COL_TBASE = 16 (follows TUI_COL_UI=15 in the enum)
// From arcan_tuisym.h: TUI_COL_TBASE is the next value after TUI_COL_UI (15)
const TUI_COL_TBASE: c_int = 16;
const TUI_COL_LIMIT: usize = 36;

// TUI attribute flags (from arcan_tuisym.h enum tui_attr_flags)
const TUI_ATTR_COLOR_INDEXED: u16 = 512;

// TUI context flags (from arcan_tuisym.h enum tui_context_flags)
const TUI_ALTERNATE: u32 = 64;

// Default pixel density (from arcan_shmif_control.h)
const ARCAN_SHMPAGE_DEFAULT_PPCM: f32 = 37.795276;

// tui_context field offsets (verified with gcc offsetof on aarch64-linux)
// Full derivation in /tmp/compute_offsets2.c using actual arcan headers.

const OFF_BASE: usize = 24; // struct tui_cell* base
const OFF_DEFATTR: usize = 48; // struct tui_screen_attr defattr
const OFF_FLAGS: usize = 80; // unsigned flags
const OFF_FONT_SZ: usize = 112; // float font_sz
const OFF_PPCM: usize = 124; // float ppcm
const OFF_MOUSE_STATE: usize = 140; // uint8_t mouse_state[ASHMIF_MSTATE_SZ]
const OFF_ROWS: usize = 228; // int rows
const OFF_COLS: usize = 232; // int cols
const OFF_CELL_W: usize = 404; // int cell_w
const OFF_CELL_H: usize = 408; // int cell_h
const OFF_MODIFIERS: usize = 428; // int modifiers
const OFF_COLORS: usize = 432; // struct color colors[TUI_COL_LIMIT]
const OFF_CURSOR: usize = 728; // enum tui_cursors cursor (c_int)
const OFF_ALPHA: usize = 736; // uint8_t alpha
const OFF_PARENT: usize = 752; // struct tui_context* parent
const OFF_CHILDREN: usize = 760; // struct tui_context* children[256]
const OFF_ACON: usize = 2808; // struct arcan_shmif_cont acon
const OFF_CLIP_IN: usize = 3000; // struct arcan_shmif_cont clip_in
const OFF_CLIP_OUT: usize = 3192; // struct arcan_shmif_cont clip_out
const OFF_PENDING_HANDOVER: usize = 3384; // uint32_t pending_handover
const OFF_VIEWPORT_PROXY: usize = 3388; // uint32_t viewport_proxy
const OFF_LAST_IDENT: usize = 3392; // struct arcan_event last_ident
const OFF_LAST_STATE_SZ: usize = 3520; // struct arcan_event last_state_sz
const OFF_HANDLERS: usize = 3880; // struct tui_cbcfg handlers

// arcan_shmif_cont embedded field offsets (verified by compute)
const SHMIF_OFF_ADDR: usize = 0; // arcan_shmif_page* addr
const SHMIF_OFF_VIDP: usize = 8; // shmif_pixel* vidp
const SHMIF_OFF_W: usize = 80; // uint32_t w
const SHMIF_OFF_H: usize = 88; // uint32_t h
const SHMIF_OFF_HINTS: usize = 128; // uint32_t hints
const SHMIF_OFF_USER: usize = 152; // void* user

const SHMIF_CONT_SIZE: usize = 192;

// sizeof(struct tui_context) = 4104 (verified with actual headers)
const TUI_CONTEXT_SIZE: usize = 4104;

// sizeof(struct tui_screen_attr) = 10 (fc[3] + bc[3] + aflags(u16) + custom_id(u8) + pad(u8))
// Actually from compute: sizeof=10, layout fc[3],bc[3],aflags(u16),custom_id(u8) = 9 + 1 pad = 10
const TUI_SCREEN_ATTR_SIZE: usize = 10;

// struct color: rgb[3] + bg[3] + bgset(bool) = 7 bytes (no padding, verified)
const COLOR_SIZE: usize = 7;
const COLOR_OFF_BG: usize = 3;
const COLOR_OFF_BGSET: usize = 6;

// tui_context.children is pointer-array of 256 nullable pointers
const CHILDREN_COUNT: usize = 256;
const PTR_SIZE: usize = @sizeOf(usize);

// arcan_shmif_open_ext return value type
// arcan_shmif_open_ext returns arcan_shmif_cont by value (192 bytes).
// We cannot use arcan.arcan_shmif_cont directly since it's opaque.
const ShmifContVal = extern struct {
    data: [SHMIF_CONT_SIZE]u8 align(8),
};

// C struct types matching the C ABI

const ShmifOpenExt = extern struct {
    @"type": c_int,
    title: [*c]const u8,
    ident: [*c]const u8,
    guid: [2]u64,
};

// shmif_resize_ext (from arcan_shmif_control.h)
const ShmifResizeExt = extern struct {
    meta: u32 = 0,
    abuf_sz: usize = 0,
    abuf_cnt: isize = -1,
    samplerate: isize = -1,
    vbuf_cnt: isize = -1,
    rows: usize = 0,
    cols: usize = 0,
    nops: usize = 0,
    op_fm: usize = 0,
};

// arcan_shmif_initial (from arcan_shmif_control.h)
// Layout: fonts[4]{fd,type,hinting,size_mm}, density, rgb_layout,
//         display_width_px, display_height_px, rate, lang[4], country[4],
//         text_lang[4], latitude, longitude, elevation, render_node, timezone,
//         colors[36]{fg[3],bg[3],fg_set,bg_set}, cell_w, cell_h
const ShmifInitialColor = extern struct {
    fg: [3]u8,
    bg: [3]u8,
    fg_set: bool,
    bg_set: bool,
};

const ShmifInitialFont = extern struct {
    fd: c_int,
    @"type": c_int,
    hinting: c_int,
    size_mm: f32,
};

const ShmifInitial = extern struct {
    fonts: [4]ShmifInitialFont,
    density: f32,
    rgb_layout: c_int,
    display_width_px: usize,
    display_height_px: usize,
    rate: u16,
    lang: [4]u8,
    country: [4]u8,
    text_lang: [4]u8,
    latitude: f32,
    longitude: f32,
    elevation: f32,
    render_node: c_int,
    timezone: c_int,
    colors: [36]ShmifInitialColor,
    cell_w: usize,
    cell_h: usize,
};

// arg_arr is opaque
const ArgArr = opaque {};

// External function declarations

extern fn arcan_shmif_open_ext(
    flags: c_uint,
    args: ?*?*anyopaque,
    ext: ShmifOpenExt,
    ext_sz: usize,
) callconv(.c) ShmifContVal;

extern fn arcan_shmif_initial(
    ctx: ?*arcan.arcan_shmif_cont,
    out: *?*ShmifInitial,
) callconv(.c) usize;

extern fn arcan_shmif_drop(ctx: ?*arcan.arcan_shmif_cont) callconv(.c) void;

extern fn arcan_shmif_enqueue(
    ctx: ?*arcan.arcan_shmif_cont,
    ev: *const arcan.arcan_event,
) callconv(.c) c_int;

extern fn arcan_shmif_resize_ext(
    ctx: ?*arcan.arcan_shmif_cont,
    w: c_uint,
    h: c_uint,
    ext: ShmifResizeExt,
) callconv(.c) bool;

extern fn arcan_shmif_mousestate_setup(
    ctx: ?*arcan.arcan_shmif_cont,
    absolute: bool,
    state: [*c]u8,
) callconv(.c) void;

extern fn arcan_shmif_last_words(
    ctx: ?*arcan.arcan_shmif_cont,
    msg: [*c]const u8,
) callconv(.c) void;

extern fn arcan_shmif_primary(@"type": c_int) callconv(.c) ?*arcan.arcan_shmif_cont;

extern fn arcan_shmif_setprimary(
    @"type": c_int,
    ctx: ?*arcan.arcan_shmif_cont,
) callconv(.c) void;

extern fn arcan_shmif_args(
    ctx: ?*arcan.arcan_shmif_cont,
) callconv(.c) ?*ArgArr;

extern fn arg_lookup(
    arr: ?*ArgArr,
    key: [*c]const u8,
    ind: c_uint,
    out: *[*c]const u8,
) callconv(.c) bool;

// TUI API functions
extern fn arcan_tui_set_color(
    tui: ?*arcan.tui_context,
    group: c_int,
    rgb: [*c]const u8,
) callconv(.c) void;

extern fn arcan_tui_set_bgcolor(
    tui: ?*arcan.tui_context,
    group: c_int,
    rgb: [*c]const u8,
) callconv(.c) void;

extern fn arcan_tui_announce_io(
    tui: ?*arcan.tui_context,
    force: bool,
    input_descr: [*c]const u8,
    output_descr: [*c]const u8,
) callconv(.c) void;

// Internal TUI functions (defined in other .c/.zig compilation units)
extern fn tui_expose_labels(tui: ?*arcan.tui_context) callconv(.c) void;
extern fn tui_fontmgmt_setup(tui: ?*arcan.tui_context, init: ?*ShmifInitial) callconv(.c) void;
extern fn tui_screen_resized(tui: ?*arcan.tui_context) callconv(.c) void;

// libc
extern fn malloc(size: usize) callconv(.c) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) callconv(.c) void;
extern fn memset(ptr: ?*anyopaque, val: c_int, n: usize) callconv(.c) ?*anyopaque;
extern fn memcpy(dst: ?*anyopaque, src: ?*const anyopaque, n: usize) callconv(.c) ?*anyopaque;
extern fn strtoul(str: [*c]const u8, endptr: ?*[*c]u8, base: c_int) callconv(.c) c_ulong;
extern fn fputs(s: [*c]const u8, stream: ?*anyopaque) callconv(.c) c_int;
extern var stderr: ?*anyopaque;

// Raw byte-offset accessors for tui_context (opaque)

inline fn tuiPtr(tui: *arcan.tui_context, comptime T: type, offset: usize) *T {
    const base: [*]u8 = @ptrCast(tui);
    return @ptrCast(@alignCast(base + offset));
}

inline fn tuiPtrConst(tui: *const arcan.tui_context, comptime T: type, offset: usize) *const T {
    const base: [*]const u8 = @ptrCast(tui);
    return @ptrCast(@alignCast(base + offset));
}

// Return pointer to the embedded arcan_shmif_cont at the given tui offset
inline fn getContAt(tui: *arcan.tui_context, offset: usize) *arcan.arcan_shmif_cont {
    return @ptrCast(tuiPtr(tui, u8, offset));
}

// Check if the embedded shmif_cont at cont_offset has a non-null addr field
inline fn contHasAddr(tui: *arcan.tui_context, cont_offset: usize) bool {
    const p: *const ?*anyopaque = @ptrCast(@alignCast(tuiPtr(tui, u8, cont_offset + SHMIF_OFF_ADDR)));
    return p.* != null;
}

// Check if the embedded shmif_cont at cont_offset has a non-null vidp field
inline fn contHasVidp(tui: *arcan.tui_context, cont_offset: usize) bool {
    const p: *const ?*anyopaque = @ptrCast(@alignCast(tuiPtr(tui, u8, cont_offset + SHMIF_OFF_VIDP)));
    return p.* != null;
}

// Get a u32 field at byte offset within the embedded cont
inline fn contU32At(tui: *arcan.tui_context, cont_offset: usize, field_off: usize) *u32 {
    return @ptrCast(@alignCast(tuiPtr(tui, u8, cont_offset + field_off)));
}

// Access child pointer at index i in children[256] array
inline fn getChild(tui: *arcan.tui_context, i: usize) ?*arcan.tui_context {
    const base: [*]u8 = @ptrCast(tui);
    const slot: *?*arcan.tui_context = @ptrCast(@alignCast(base + OFF_CHILDREN + i * PTR_SIZE));
    return slot.*;
}

inline fn setChild(tui: *arcan.tui_context, i: usize, val: ?*arcan.tui_context) void {
    const base: [*]u8 = @ptrCast(tui);
    const slot: *?*arcan.tui_context = @ptrCast(@alignCast(base + OFF_CHILDREN + i * PTR_SIZE));
    slot.* = val;
}

// static: apply_arg — apply command-line overrides from arg_arr

fn apply_arg(src: *arcan.tui_context, args: ?*ArgArr) void {
    if (args == null) return;

    var val: [*c]const u8 = undefined;
    val = null;
    if (arg_lookup(args, "bgalpha", 0, &val) and val != null) {
        const v = strtoul(val, null, 10);
        tuiPtr(src, u8, OFF_ALPHA).* = @truncate(v);
    }
}

// exported: tui_queue_requests

pub export fn tui_queue_requests(tui: ?*arcan.tui_context, clipboard: bool, ident: bool) void {
    const t = tui orelse return;
    const acon = getContAt(t, OFF_ACON);

    // Request clipboard segment for cut/paste operations
    if (clipboard) {
        var ev = arcan.arcan_event.zeroes();
        ev.setCategory(arcan.EVENT_EXTERNAL);
        const ext = ev.asExt();
        ext.kind = EVENT_EXTERNAL_SEGREQ;
        ext.payload.segreq.width = 1;
        ext.payload.segreq.height = 1;
        ext.payload.segreq.kind = SEGID_CLIPBOARD;
        ext.payload.segreq.id = 0xfeedface;
        _ = arcan_shmif_enqueue(acon, &ev);
    }

    // Always request a timer (for cursor blinking and tick callbacks)
    {
        var ev = arcan.arcan_event.zeroes();
        ev.setCategory(arcan.EVENT_EXTERNAL);
        const ext = ev.asExt();
        ext.kind = EVENT_EXTERNAL_CLOCKREQ;
        ext.payload.clock.rate = 1;
        ext.payload.clock.id = 0xabcdef00;
        _ = arcan_shmif_enqueue(acon, &ev);
    }

    // On crash recovery: re-send identity events
    if (ident) {
        const last_ident = tuiPtr(t, arcan.arcan_event, OFF_LAST_IDENT);
        if (last_ident.asExt().kind != 0) {
            _ = arcan_shmif_enqueue(acon, last_ident);
        }
        const last_state_sz = tuiPtr(t, arcan.arcan_event, OFF_LAST_STATE_SZ);
        _ = arcan_shmif_enqueue(acon, last_state_sz);
    }

    tui_expose_labels(tui);
}

// static: set_builtin_palette

fn setBuiltinPalette(ctx: *arcan.tui_context) void {
    arcan_tui_set_color(ctx, TUI_COL_CURSOR, &[_]u8{ 0x00, 0xff, 0x00 });
    arcan_tui_set_bgcolor(ctx, TUI_COL_CURSOR, &[_]u8{ 0x00, 0xff, 0x00 });

    arcan_tui_set_color(ctx, TUI_COL_ALTCURSOR, &[_]u8{ 0xff, 0xff, 0x00 });
    arcan_tui_set_bgcolor(ctx, TUI_COL_ALTCURSOR, &[_]u8{ 0xff, 0xff, 0x00 });

    arcan_tui_set_color(ctx, TUI_COL_PRIMARY, &[_]u8{ 0xff, 0xff, 0xff });
    arcan_tui_set_color(ctx, TUI_COL_SECONDARY, &[_]u8{ 0xaa, 0xaa, 0xaa });

    arcan_tui_set_bgcolor(ctx, TUI_COL_BG, &[_]u8{ 0x10, 0x10, 0x10 });

    arcan_tui_set_color(ctx, TUI_COL_TEXT, &[_]u8{ 0xaa, 0xaa, 0xaa });
    arcan_tui_set_bgcolor(ctx, TUI_COL_TEXT, &[_]u8{ 0x10, 0x10, 0x10 });

    arcan_tui_set_color(ctx, TUI_COL_HIGHLIGHT, &[_]u8{ 246, 84, 0 });
    arcan_tui_set_bgcolor(ctx, TUI_COL_HIGHLIGHT, &[_]u8{ 0x10, 0x10, 0x10 });

    arcan_tui_set_color(ctx, TUI_COL_LABEL, &[_]u8{ 0xff, 0xff, 0xff });
    arcan_tui_set_bgcolor(ctx, TUI_COL_LABEL, &[_]u8{ 0x00, 0x00, 0x00 });

    arcan_tui_set_color(ctx, TUI_COL_WARNING, &[_]u8{ 255, 255, 255 });
    arcan_tui_set_bgcolor(ctx, TUI_COL_WARNING, &[_]u8{ 246, 84, 0 });

    arcan_tui_set_color(ctx, TUI_COL_ERROR, &[_]u8{ 255, 255, 255 });
    arcan_tui_set_bgcolor(ctx, TUI_COL_ERROR, &[_]u8{ 190, 0, 0 });

    arcan_tui_set_color(ctx, TUI_COL_ALERT, &[_]u8{ 190, 0, 0 });
    arcan_tui_set_bgcolor(ctx, TUI_COL_ALERT, &[_]u8{ 0x10, 0x10, 0x10 });

    arcan_tui_set_color(ctx, TUI_COL_REFERENCE, &[_]u8{ 31, 104, 230 });
    arcan_tui_set_bgcolor(ctx, TUI_COL_REFERENCE, &[_]u8{ 0x10, 0x10, 0x10 });

    arcan_tui_set_color(ctx, TUI_COL_INACTIVE, &[_]u8{ 0x80, 0x80, 0x80 });
    arcan_tui_set_bgcolor(ctx, TUI_COL_INACTIVE, &[_]u8{ 0x00, 0x00, 0x00 });

    arcan_tui_set_color(ctx, TUI_COL_UI, &[_]u8{ 255, 255, 255 });
    arcan_tui_set_bgcolor(ctx, TUI_COL_UI, &[_]u8{ 31, 104, 230 });

    // Legacy terminal color set (TUI_COL_TBASE + 0..17)
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 0, &[_]u8{ 0, 0, 0 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 1, &[_]u8{ 205, 0, 0 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 2, &[_]u8{ 0, 205, 0 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 3, &[_]u8{ 205, 205, 0 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 4, &[_]u8{ 0, 0, 238 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 5, &[_]u8{ 205, 0, 205 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 6, &[_]u8{ 0, 205, 205 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 7, &[_]u8{ 229, 229, 229 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 8, &[_]u8{ 127, 127, 127 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 9, &[_]u8{ 255, 0, 0 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 10, &[_]u8{ 0, 255, 0 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 11, &[_]u8{ 255, 255, 0 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 12, &[_]u8{ 0, 0, 255 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 13, &[_]u8{ 255, 0, 255 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 14, &[_]u8{ 0, 255, 255 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 15, &[_]u8{ 255, 255, 255 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 16, &[_]u8{ 229, 229, 229 });
    arcan_tui_set_color(ctx, TUI_COL_TBASE + 17, &[_]u8{ 0, 0, 0 });
}

// static: late_bind — bind/unbind a shmif connection to a tui context

fn late_bind(
    con: ?*arcan.arcan_shmif_cont,
    res: *arcan.tui_context,
    setup: bool,
) bool {
    _ = setup;

    // Unbind: zero out acon
    if (con == null) {
        _ = memset(tuiPtr(res, u8, OFF_ACON), 0, SHMIF_CONT_SIZE);
        return true;
    }

    // Attach: copy *con into res->acon
    _ = memcpy(tuiPtr(res, u8, OFF_ACON), con, SHMIF_CONT_SIZE);

    // Detect managed context (opened via arcan_tui_open_display, user==0xdeadbeef)
    var managed = false;
    {
        const user_ptr: *const usize = @ptrCast(@alignCast(
            @as([*]const u8, @ptrCast(con)) + SHMIF_OFF_USER,
        ));
        if (user_ptr.* == 0xdeadbeef) {
            managed = true;
            free(con); // release the malloc'd shell from open_display
        }
    }

    // Retrieve initial display-server configuration
    var init: ?*ShmifInitial = null;
    const acon = getContAt(res, OFF_ACON);
    const init_sz = arcan_shmif_initial(acon, &init);
    if (init_sz != @sizeOf(ShmifInitial) and managed) {
        _ = fputs("initial structure size mismatch, out-of-synch header/shmif lib\n", stderr);
        arcan_shmif_drop(acon);
        free(res);
        return false;
    }

    // Set ppcm and cell dimensions from initial state (only if not already set by parent)
    const ppcm_ptr = tuiPtr(res, f32, OFF_PPCM);
    if (ppcm_ptr.* == 0.0) {
        if (init) |i| {
            ppcm_ptr.* = i.density;
            tuiPtr(res, c_int, OFF_CELL_W).* = @intCast(i.cell_w);
            tuiPtr(res, c_int, OFF_CELL_H).* = @intCast(i.cell_h);
        } else {
            ppcm_ptr.* = ARCAN_SHMPAGE_DEFAULT_PPCM;
        }
    }

    if (tuiPtr(res, c_int, OFF_CELL_W).* == 0)
        tuiPtr(res, c_int, OFF_CELL_W).* = 8;
    if (tuiPtr(res, c_int, OFF_CELL_H).* == 0)
        tuiPtr(res, c_int, OFF_CELL_H).* = 8;

    tui_fontmgmt_setup(res, init);

    // Initialize mouse state machine
    {
        const mouse_state: [*c]u8 = @ptrCast(tuiPtr(res, u8, OFF_MOUSE_STATE));
        arcan_shmif_mousestate_setup(acon, false, mouse_state);
    }

    // Enable tpack and vsignal render hints on the connection
    contU32At(res, OFF_ACON, SHMIF_OFF_HINTS).* = SHMIF_RHINT_TPACK | SHMIF_RHINT_VSIGNAL_EV;

    // Request clipboard segment and timer; no IDENT re-send at this point
    tui_queue_requests(res, true, false);

    // Resize connection to match current dimensions with tpack row/col metadata
    {
        const w = contU32At(res, OFF_ACON, SHMIF_OFF_W).*;
        const h = contU32At(res, OFF_ACON, SHMIF_OFF_H).*;
        const cell_w: u32 = @intCast(tuiPtr(res, c_int, OFF_CELL_W).*);
        const cell_h: u32 = @intCast(tuiPtr(res, c_int, OFF_CELL_H).*);

        _ = arcan_shmif_resize_ext(acon, w, h, ShmifResizeExt{
            .vbuf_cnt = -1,
            .abuf_cnt = -1,
            .rows = if (cell_h > 0) h / cell_h else 0,
            .cols = if (cell_w > 0) w / cell_w else 0,
        });
    }

    // Apply color palette from display-server initial state
    if (init) |i| {
        const colors_base: [*]u8 = @ptrCast(tuiPtr(res, u8, OFF_COLORS));
        var idx: usize = 0;
        while (idx < i.colors.len and idx < TUI_COL_LIMIT) : (idx += 1) {
            const ic = &i.colors[idx];
            const cp = colors_base + idx * COLOR_SIZE;
            if (ic.fg_set) {
                cp[0] = ic.fg[0];
                cp[1] = ic.fg[1];
                cp[2] = ic.fg[2];
            }
            if (ic.bg_set) {
                cp[COLOR_OFF_BG + 0] = ic.bg[0];
                cp[COLOR_OFF_BG + 1] = ic.bg[1];
                cp[COLOR_OFF_BG + 2] = ic.bg[2];
                cp[COLOR_OFF_BGSET] = 1; // bool true
            }
        }
    }

    tui_screen_resized(res);

    // Notify caller of the initial resize
    const handlers = tuiPtr(res, arcan.tui_cbcfg, OFF_HANDLERS);
    if (handlers.resized) |resized_fn| {
        const w = contU32At(res, OFF_ACON, SHMIF_OFF_W).*;
        const h = contU32At(res, OFF_ACON, SHMIF_OFF_H).*;
        const cols: usize = @intCast(tuiPtr(res, c_int, OFF_COLS).*);
        const rows: usize = @intCast(tuiPtr(res, c_int, OFF_ROWS).*);
        resized_fn(res, @intCast(w), @intCast(h), cols, rows, handlers.tag);
    }

    return true;
}

// exported: arcan_tui_open_display

pub export fn arcan_tui_open_display(
    title: [*c]const u8,
    ident: [*c]const u8,
) ?*arcan.arcan_shmif_cont {
    const buf = malloc(SHMIF_CONT_SIZE) orelse return null;
    _ = memset(buf, 0, SHMIF_CONT_SIZE);

    // Open the shmif connection (returns by value)
    const opened = arcan_shmif_open_ext(
        SHMIF_ACQUIRE_FATALFAIL,
        null,
        ShmifOpenExt{
            .@"type" = SEGID_TUI,
            .title = title,
            .ident = ident,
            .guid = .{ 0, 0 },
        },
        @sizeOf(ShmifOpenExt),
    );

    // Copy the by-value result into our heap buffer
    _ = memcpy(buf, &opened, SHMIF_CONT_SIZE);

    // Check addr field (offset 0) is non-null — connection succeeded
    const addr_ptr: *const ?*anyopaque = @ptrCast(@alignCast(
        @as([*]const u8, @ptrCast(buf)),
    ));
    if (addr_ptr.* == null) {
        free(buf);
        return null;
    }

    // Mark as managed by setting user = 0xdeadbeef
    const user_ptr: *usize = @ptrCast(@alignCast(
        @as([*]u8, @ptrCast(buf)) + SHMIF_OFF_USER,
    ));
    user_ptr.* = 0xdeadbeef;

    const res: *arcan.arcan_shmif_cont = @ptrCast(@alignCast(buf));
    return res;
}

// exported: arcan_tui_destroy

pub export fn arcan_tui_destroy(tui: ?*arcan.tui_context, message: [*c]const u8) void {
    const t = tui orelse return;

    // If this is the registered accessibility primary, unregister it
    {
        const acon = getContAt(t, OFF_ACON);
        if (arcan_shmif_primary(SHMIF_ACCESSIBILITY) == acon) {
            arcan_shmif_setprimary(SHMIF_ACCESSIBILITY, null);
        }
    }

    // Remove self from parent's children list
    const parent_ptr = tuiPtr(t, ?*arcan.tui_context, OFF_PARENT);
    if (parent_ptr.*) |parent| {
        var i: usize = 0;
        while (i < CHILDREN_COUNT) : (i += 1) {
            if (getChild(parent, i) == tui) {
                setChild(parent, i, null);
                break;
            }
        }
        parent_ptr.* = null;
    }

    // Clear parent pointer in all children (avoid dangling)
    {
        var i: usize = 0;
        while (i < CHILDREN_COUNT) : (i += 1) {
            if (getChild(t, i)) |child| {
                const child_parent = tuiPtr(child, ?*arcan.tui_context, OFF_PARENT);
                if (child_parent.* == tui)
                    child_parent.* = null;
            }
        }
    }

    // Drop input clipboard segment if live
    if (contHasVidp(t, OFF_CLIP_IN)) {
        arcan_shmif_drop(getContAt(t, OFF_CLIP_IN));
    }

    // Drop output clipboard segment if live
    if (contHasVidp(t, OFF_CLIP_OUT)) {
        arcan_shmif_drop(getContAt(t, OFF_CLIP_OUT));
    }

    // Send last words (if any) and drop main connection
    if (contHasAddr(t, OFF_ACON)) {
        if (message != null) {
            arcan_shmif_last_words(getContAt(t, OFF_ACON), message);
        }
        arcan_shmif_drop(getContAt(t, OFF_ACON));
    }

    // Free the cell buffer (tui->base, a *tui_cell allocation)
    const base_ptr = tuiPtr(t, ?*anyopaque, OFF_BASE);
    free(base_ptr.*);

    // Zero-wipe and free the context
    _ = memset(t, 0, TUI_CONTEXT_SIZE);
    free(t);
}

// exported: arcan_tui_bind

pub export fn arcan_tui_bind(
    con: ?*arcan.arcan_shmif_cont,
    orphan: ?*arcan.tui_context,
) bool {
    const t = orphan orelse return false;
    return late_bind(con, t, false);
}

// exported: arcan_tui_setup
// In C this is variadic (size_t cbs_sz, ...) but the varargs are never used.
// We export a non-variadic version; on aarch64 the calling convention is
// compatible for the fixed named arguments.

pub export fn arcan_tui_setup(
    con: ?*arcan.arcan_shmif_cont,
    parent: ?*arcan.tui_context,
    cbs: ?*const arcan.tui_cbcfg,
    cbs_sz: usize,
) ?*arcan.tui_context {
    if (cbs == null) return null;

    const buf = malloc(TUI_CONTEXT_SIZE) orelse return null;
    _ = memset(buf, 0, TUI_CONTEXT_SIZE);
    const res: *arcan.tui_context = @ptrCast(@alignCast(buf));

    // Initialize scalar fields
    tuiPtr(res, u8, OFF_ALPHA).* = 0xff;
    tuiPtr(res, f32, OFF_FONT_SZ).* = 0.0416;
    tuiPtr(res, u32, OFF_FLAGS).* = TUI_ALTERNATE;
    tuiPtr(res, c_int, OFF_CELL_W).* = 8;
    tuiPtr(res, c_int, OFF_CELL_H).* = 8;

    // Initialize defattr: {.bc = TUI_COL_TEXT, .fc = TUI_COL_TEXT, .aflags = TUI_ATTR_COLOR_INDEXED}
    // tui_screen_attr layout: fc[3], bc[3], aflags(u16), custom_id(u8) — total 10 bytes
    // With TUI_ATTR_COLOR_INDEXED, fc[0]/bc[0] hold the palette index.
    {
        const da: [*]u8 = @ptrCast(tuiPtr(res, u8, OFF_DEFATTR));
        da[0] = @intCast(TUI_COL_TEXT); // fc[0] = color index
        da[1] = 0;
        da[2] = 0;
        da[3] = @intCast(TUI_COL_TEXT); // bc[0] = color index
        da[4] = 0;
        da[5] = 0;
        const aflags: *u16 = @ptrCast(@alignCast(da + 6));
        aflags.* = TUI_ATTR_COLOR_INDEXED;
        da[8] = 0; // custom_id = 0
    }

    // Validate and copy the callback table.
    // cbs_sz must be <= sizeof(tui_cbcfg) and aligned to pointer size.
    if (cbs_sz > @sizeOf(arcan.tui_cbcfg) or cbs_sz % @sizeOf(*anyopaque) != 0) {
        _ = fputs("arcan_tui(), caller provided bad size field\n", stderr);
        free(buf);
        return null;
    }
    _ = memcpy(tuiPtr(res, u8, OFF_HANDLERS), cbs, cbs_sz);

    // Set the built-in color palette
    setBuiltinPalette(res);

    // Apply command-line argument overrides (e.g. bgalpha=...)
    // Skip if con is NULL or the reserved sentinel (-1)
    const con_uptr: usize = @intFromPtr(con);
    const neg1_uptr: usize = @bitCast(@as(isize, -1));
    if (con != null and con_uptr != neg1_uptr) {
        apply_arg(res, arcan_shmif_args(con));
    }

    // Inherit settings from parent context
    if (parent) |p| {
        tuiPtr(res, u8, OFF_ALPHA).* = tuiPtr(p, u8, OFF_ALPHA).*;
        tuiPtr(res, c_int, OFF_CURSOR).* = tuiPtr(p, c_int, OFF_CURSOR).*;
        tuiPtr(res, f32, OFF_PPCM).* = tuiPtr(p, f32, OFF_PPCM).*;

        // Handle pending handover subwindow: absorb it into res as a proxy
        const pending = tuiPtr(p, u32, OFF_PENDING_HANDOVER);
        if (pending.* != 0) {
            tuiPtr(res, u32, OFF_VIEWPORT_PROXY).* = pending.*;
            pending.* = 0;

            // Establish parent-child link
            tuiPtr(res, ?*arcan.tui_context, OFF_PARENT).* = p;
            var i: usize = 0;
            while (i < CHILDREN_COUNT) : (i += 1) {
                if (getChild(p, i) == null) {
                    setChild(p, i, res);
                    break;
                }
            }
        }
    }

    // Bind the connection (does font setup, resize, initial events)
    if (con != null and con_uptr != neg1_uptr) {
        _ = late_bind(con, res, true);
    }

    // After binding, inherit color palette and defattr from parent
    // (done after late_bind so late_bind's initial colors don't overwrite parent's)
    if (parent) |p| {
        _ = memcpy(
            tuiPtr(res, u8, OFF_COLORS),
            tuiPtrConst(p, u8, OFF_COLORS),
            TUI_COL_LIMIT * COLOR_SIZE,
        );
        _ = memcpy(
            tuiPtr(res, u8, OFF_DEFATTR),
            tuiPtrConst(p, u8, OFF_DEFATTR),
            TUI_SCREEN_ATTR_SIZE,
        );
    }

    // Announce supported I/O formats to the display server
    arcan_tui_announce_io(res, false, null, "tui-raw");

    return res;
}
