// Platform Video — Vulkan (unified: XCB windowed, VK_KHR_display, LWA nested)
//
// Single binary with runtime mode detection:
//   - ARCAN_CONNPATH/ARCAN_SOCKIN_FD set → LWA (nested compositor via shmif)
//   - DISPLAY set → XCB windowed (VK_KHR_xcb_surface)
//   - Otherwise → VK_KHR_display (direct-to-display)

const std = @import("std");

pub const std_options: std.Options = .{ .log_level = .warn };
const vk = @import("vulkan");
const agp_vk = @import("vk.zig");
const vk_wsi = @import("vk_wsi.zig");
const vk_xcb = @import("vk_xcb.zig");
const vk_offscreen = @import("vk_offscreen.zig");
const vk_gbm_kms = @import("vk_gbm_kms.zig");
const builtin = @import("builtin");
const use_zig_dlopen = (builtin.link_mode == .static and (builtin.abi == .musl or !builtin.link_libc));
extern fn zig_foreign_begin() callconv(.c) void;
extern fn zig_foreign_end() callconv(.c) void;

const c = @import("posix");

// Arcan types (opaque, defined in engine)
// Must match arcan_zig_types.zig / vk_shared.zig layout exactly
const struct_agp_vstore = extern struct {
    refcount: usize = 0, update_ts: u32 = 0, _pad0: [4]u8 = .{0} ** 4,
    vinf: extern union {
        text: extern struct {
            glid: c_uint = 0, _p0: [4]u8 = .{0} ** 4, glid_proxy: ?*c_uint = null,
            rid: c_uint = 0, wid: c_uint = 0,
            s_raw: u32 = 0, _p1: [4]u8 = .{0} ** 4, raw: ?[*]av_pixel = null,
            s_fmt: u64 = 0, d_fmt: u64 = 0, s_type: c_uint = 0, _p2: [4]u8 = .{0} ** 4,
            vpts: u64 = 0, hppcm: f32 = 0, vppcm: f32 = 0,
            kind: c_uint = 0, _p3: [4]u8 = .{0} ** 4,
            unnamed_0: extern union {
                source: [*c]u8, source_arr: [*c][*c]u8,
                tpack: extern struct { buf_sz: usize = 0, buf: ?[*]u8 = null, group: ?*anyopaque = null, tui: ?*anyopaque = null },
            } = .{ .source = null },
            format: c_int = 0, _p4: [4]u8 = .{0} ** 4, stride: usize = 0, handle: i64 = 0, tag: usize = 0,
        },
        col: extern struct { r: f32 = 0, g: f32 = 0, b: f32 = 0 },
    } = .{ .col = .{} },
    dst_copy: ?*struct_agp_vstore = null, _pdc: [8]u8 = .{0} ** 8,
    w: usize = 0, h: usize = 0,
    bpp: u8 = 0, txmapped: u8 = 0, txu: u8 = 0, txv: u8 = 0,
};
const struct_agp_rendertarget = opaque {};
const struct_arcan_evctx = opaque {};
// Bug 0125 third entry point: this struct must match C's
// arcan_shmif_initial EXACTLY. Earlier "minimal layout" had wrong
// ShmifInitFont (12 bytes, fd/size_mm/hinting) instead of the C
// layout (16 bytes, fd/type/hinting/size_mm), so init.fonts[1].fd
// landed at offset 12 — into fonts[0].hinting — and read garbage.
const ShmifInitFont = extern struct {
    fd: c_int = -1,
    @"type": c_int = 0,
    hinting: c_int = 0,
    size_mm: f32 = 0,
};
const struct_arcan_shmif_initial = extern struct {
    // Minimal layout: only fields actually accessed (fonts, density).
    // fonts is 64 bytes (4 × 16); density follows at offset 64,
    // matching C arcan_shmif_control.h.
    fonts: [4]ShmifInitFont = .{ShmifInitFont{}} ** 4,
    density: f32 = 0,
};
comptime {
    if (@sizeOf(ShmifInitFont) != 16)
        @compileError("ShmifInitFont must be 16 bytes to match canonical layout");
    if (@offsetOf(struct_arcan_shmif_initial, "density") != 64)
        @compileError("struct_arcan_shmif_initial.density must be at offset 64");
}
// Full layout — must match C `struct arcan_shmif_cont` from
// arcan_shmif_control.h:262 EXACTLY in size and field offsets.
// arcan_shmif_open_ext / arcan_shmif_acquire return this by value
// (sizeof = 192 bytes on aarch64). The earlier "minimal layout" (56
// bytes) caused the callee to write 192 bytes through the sret pointer
// and smash initLwa's saved-FP/LR on the stack — silent ret-to-junk crash.
const struct_arcan_shmif_cont = extern struct {
    addr: ?*anyopaque = null,
    unnamed_0: extern union { vidp: [*c]u32 } = .{ .vidp = null },
    unnamed_1_audp: ?*anyopaque = null,
    oflow_cookie: i16 = 0,
    abufused: u16 = 0,
    abufpos: u16 = 0,
    abufsize: u16 = 0,
    abufcount: u16 = 0,
    abuf_cnt: u8 = 0,
    epipe: c_int = 0,
    shmh: c_int = 0,
    shmsize: usize = 0,
    unused: [3]usize = .{ 0, 0, 0 },
    w: usize = 0,
    h: usize = 0,
    stride: usize = 0,
    pitch: usize = 0,
    adata: u32 = 0,
    samplerate: usize = 0,
    hints: u8 = 0,
    dirty: extern struct { x1: u16 = 0, x2: u16 = 0, y1: u16 = 0, y2: u16 = 0 } = .{},
    cookie: u64 = 0,
    user: ?*anyopaque = null,
    priv: ?*anyopaque = null,
    privext: ?*anyopaque = null,
    segment_token: u32 = 0,
    vbufsize: usize = 0,
};
comptime {
    if (@sizeOf(struct_arcan_shmif_cont) != 192)
        @compileError("struct_arcan_shmif_cont must be 192 bytes to match C ABI");
}
const struct_arg_arr = opaque {};
const struct_shmif_open_ext = extern struct {
    type: c_uint = 0,
    title: ?[*:0]const u8 = null,
    guid: [2]u64 = .{ 0, 0 },
};
// Must match arcan_zig_types.zig layout exactly (ABI boundary with arcan_video.zig)
const struct_monitor_mode = extern struct {
    id: u32 = 0,
    x: usize = 0,
    y: usize = 0,
    width: usize = 0,
    height: usize = 0,
    phy_width: usize = 0,
    phy_height: usize = 0,
    depth: u8 = 0,
    refresh: u8 = 0,
    _pad0: [6]u8 = .{ 0, 0, 0, 0, 0, 0 },
    subpixel: [*c]const u8 = null,
    primary: bool = false,
    dynamic: bool = false,
};
// All structs below must match their canonical definitions exactly (ABI boundary).
// Canonical sources: arcan_boot_compat.zig, vk_shared.zig
const struct_display_layer_cfg = extern struct {
    x: isize = 0,
    y: isize = 0,
    hint: c_uint = 0,
    opacity: f32 = 0,
};
const struct_platform_mode_opts = extern struct {
    depth: c_int = 0,
    vrr: f32 = 0,
};
const struct_agp_buffer_plane = extern struct {
    fd: c_int = 0,
    fence: c_int = 0,
    w: usize = 0,
    h: usize = 0,
    unnamed_0: extern union {
        gbm: extern struct {
            format: u32 = 0,
            _pad0: [4]u8 = .{ 0, 0, 0, 0 },
            stride: u64 = 0,
            offset: u64 = 0,
            mod_hi: u32 = 0,
            mod_lo: u32 = 0,
        },
    } = .{ .gbm = .{} },
};
const struct_agp_region = extern struct {
    x1: usize = 0,
    y1: usize = 0,
    x2: usize = 0,
    y2: usize = 0,
};

// Arcan event is a large union — treat as an opaque 512-byte blob whose
// inner fields we access through pointers returned by extern C functions.
// We model only the outer structure to match field access patterns used here.
// All structs verified against C via tests/struct_compat/verify_zig_structs.zig
const arcan_ioevent_translated = extern struct {
    utf8: [5]u8 = .{0} ** 5,
    active: u8 = 0,
    scancode: u8 = 0,
    keysym: u32 = 0,
    modifiers: u16 = 0,
};
const arcan_ioevent_digital = extern struct {
    active: u8 = 0,
};
const arcan_ioevent_analog = extern struct {
    gotrel: i8 = 0,
    nvalues: u8 = 0,
    axisval: [4]i16 = .{0} ** 4,
    active: u8 = 0,
};
const arcan_ioevent_touch = extern struct {
    active: u8 = 0,
    _pad0: u8 = 0,
    x: i16 = 0,
    y: i16 = 0,
    pressure: f32 = 0,
    size: f32 = 0,
    tilt_x: u16 = 0,
    tilt_y: u16 = 0,
    tool: u8 = 0,
};
const arcan_ioevent_eyes = extern struct {
    head_pos: [3]f32 = .{0} ** 3,
    head_ang: [3]f32 = .{0} ** 3,
    gaze_x1: f32 = 0,
    gaze_y1: f32 = 0,
    gaze_x2: f32 = 0,
    gaze_y2: f32 = 0,
    blink_left: u8 = 0,
    blink_right: u8 = 0,
    present: u8 = 0,
};
const arcan_ioevent_status = extern struct {
    action: u8 = 0,
    devkind: u8 = 0,
    devref: u16 = 0,
    domain: u8 = 0,
};
const arcan_ioevent_input = extern union {
    translated: arcan_ioevent_translated,
    digital: arcan_ioevent_digital,
    analog: arcan_ioevent_analog,
    touch: arcan_ioevent_touch,
    eyes: arcan_ioevent_eyes,
    status: arcan_ioevent_status,
};
const arcan_ioevent = extern struct {
    kind: c_uint = 0,
    devkind: c_uint = 0,
    datatype: c_uint = 0,
    label: [16]u8 = .{0} ** 16,
    flags: u8 = 0,
    _pad_flags: u8 = 0,
    unnamed_0: extern struct {
        unnamed_0: extern struct {
            devid: u16 = 0,
            subid: u16 = 0,
        } = .{},
    } = .{},
    _pad_dst: [2]u8 = .{0} ** 2,
    dst: u32 = 0,
    pts: u64 = 0,
    input: arcan_ioevent_input = undefined,
};
const arcan_vevent = extern struct {
    kind: c_int = 0,
    source: c_int = 0,
    unnamed_0: extern struct {
        unnamed_0: extern struct {
            displayid: c_int = 0,
            width: c_int = 0,
            height: c_int = 0,
            flags: c_int = 0,
            vppcm: f32 = 0,
        } = .{},
    } = .{},
};
const arcan_sevent = extern struct {
    kind: c_int = 0,
};
const arcan_tgtevent_ioev = extern union {
    iv: c_int,
    fv: f32,
};
const arcan_tgtevent = extern struct {
    kind: c_int = 0,
    ioevs: [6]arcan_tgtevent_ioev = [_]arcan_tgtevent_ioev{.{ .iv = 0 }} ** 6,
};
const arcan_extevent = extern struct {
    kind: c_int = 0,
    unnamed_0: extern union {
        message: extern struct { data: [78]u8 },
    } = undefined,
};
// arcan_event: 128-byte flat buffer. Category is at byte 120.
// Using raw bytes + accessor functions to avoid ANY struct layout mismatch.
const ARCAN_EVENT_CATEGORY_OFFSET = 120;
const arcan_event = extern struct {
    data: [128]u8 = std.mem.zeroes([128]u8),

    fn setCategory(self: *arcan_event, cat: u8) void {
        self.data[ARCAN_EVENT_CATEGORY_OFFSET] = cat;
    }
    fn getIo(self: *arcan_event) *arcan_ioevent {
        return @ptrCast(@alignCast(&self.data));
    }
    fn getSys(self: *arcan_event) *arcan_sevent {
        return @ptrCast(@alignCast(&self.data));
    }
    fn getVid(self: *arcan_event) *arcan_vevent {
        return @ptrCast(@alignCast(&self.data));
    }
    fn getTgt(self: *arcan_event) *arcan_tgtevent {
        return @ptrCast(@alignCast(&self.data));
    }
    fn getExt(self: *arcan_event) *arcan_extevent {
        return @ptrCast(@alignCast(&self.data));
    }
};

// Arcan display state — the video_display global holds default_txcos and dirty
const arcan_video_display_t = extern struct {
    default_txcos: [8]f32,
    dirty: u32,
};
extern var arcan_video_display: arcan_video_display_t;

// Arcan video object — fields here MUST sit at the canonical offsets
// from arcan_zig_types.zig:1306 (struct arcan_vobject in C). Earlier
// "minimal" layout placed vstore at offset 0 and txcos at offset 8;
// canonical positions are vstore=24, txcos=88. The wrong offsets meant
// every `vo.*.vstore` read actually returned `parent` and every
// `vo.*.txcos` returned `children`, producing garbage pointers fed to
// arcan_vint_drop_vstore. Bug 0125-adjacent / videomapping crash.
const arcan_vobject = extern struct {
    _pre_vstore: [24]u8 align(8) = .{0} ** 24,    // parent + children + frameset
    vstore: ?*struct_agp_vstore = null,            // canonical offset 24
    _pre_txcos: [56]u8 align(8) = .{0} ** 56,      // flags+origw+origh+program+pad+shape+feed
    txcos: ?[*]f32 = null,                          // canonical offset 88
};
comptime {
    if (@offsetOf(arcan_vobject, "vstore") != 24)
        @compileError("arcan_vobject.vstore must be at canonical offset 24");
    if (@offsetOf(arcan_vobject, "txcos") != 88)
        @compileError("arcan_vobject.txcos must be at canonical offset 88");
}

const arcan_vobj_id = i64;
const av_pixel = u32;
const platform_display_id = usize;
const platform_mode_id = usize;
const vfunc_state = extern struct { ptr: ?*anyopaque = null };

// Arcan constants
const ARCAN_VIDEO_WORLDID: arcan_vobj_id = 1;
const ARCAN_EID: arcan_vobj_id = 0;
const BLEND_NONE: c_uint = 0;
const TXSTATE_TEX2D: c_uint = 1;
const ADPMS_ON: c_uint = 0;
const ADPMS_IGNORE: c_uint = 0xFF;
const ARCAN_ERRC_NO_SUCH_OBJECT: c_int = -7;
const ARCAN_SHMPAGE_DEFAULT_PPCM: f32 = 28.34;

// Shmif segment types / flags
const SEGID_LWA: c_uint = 11;
const SEGID_MEDIA: c_uint = 1;
const SHMIF_NOACTIVATE: c_int = 4;
const SHMIF_NOACTIVATE_RESIZE: c_int = 64;
const SHMIF_DISABLE_GUARD: c_int = 1;
const SHMIF_INPUT: c_int = 0;
const SHMIF_RHINT_VSIGNAL_EV: c_uint = 2;
const SHMIF_SIGVID: c_int = 1;
const SHMIF_SIGBLK_NONE: c_int = 0;

// Event categories and kinds
// Values from C: arcan_shmif_event.h (verified via tests/struct_compat/dump_offsets)
const EVENT_SYSTEM: u8 = 1;
const EVENT_IO: u8 = 2;
const EVENT_VIDEO: u8 = 4;
const EVENT_TARGET: u8 = 16;
const EVENT_EXTERNAL: u8 = 64;

// Verified against C: arcan_shmif_event.h
const EVENT_IO_BUTTON: c_uint = 0;
const EVENT_IO_AXIS_MOVE: c_uint = 1;
// EVENT_IO_TOUCH = 2, EVENT_IO_STATUS = 3 (not used directly)

// Verified against C: arcan_shmif_event.h
const EVENT_IDATATYPE_ANALOG: c_uint = 1;
const EVENT_IDATATYPE_DIGITAL: c_uint = 2;
const EVENT_IDATATYPE_TRANSLATED: c_uint = 4;

// Verified against C: arcan_shmif_event.h
const EVENT_IDEVKIND_KEYBOARD: c_uint = 1;
const EVENT_IDEVKIND_MOUSE: c_uint = 2;
const EVENT_IDEVKIND_GAMEDEV: c_uint = 4;
const EVENT_IDEVKIND_TOUCHDISP: c_uint = 8;
const EVENT_IDEVKIND_STATUS: c_uint = 64;

const EVENT_SYSTEM_EXIT: c_int = 0;
const EVENT_VIDEO_DISPLAY_ADDED: c_int = 0;
const EVENT_VIDEO_DISPLAY_REMOVED: c_int = 1;
const EVENT_VIDEO_DISPLAY_RESET: c_int = 2;
const EVENT_EXTERNAL_CURSORHINT: c_int = 17;

const TARGET_COMMAND_EXIT: c_int = 0;
const TARGET_COMMAND_STEPFRAME: c_int = 6;
const TARGET_COMMAND_DISPLAYHINT: c_int = 19;
const TARGET_COMMAND_FONTHINT: c_int = 25;
const TARGET_COMMAND_RESET: c_int = 7;
const TARGET_COMMAND_NEWSEGMENT: c_int = 16;

const FFUNC_DESTROY: c_uint = 10;
const FFUNC_POLL: c_uint = 0;
const FFUNC_READBACK: c_uint = 6;
const FRV_NOFRAME: c_uint = 26;

const ACAP_TRANSLATED: c_uint = 1;
const ACAP_MOUSE: c_uint = 2;
const ACAP_TOUCH: c_uint = 8;
const ACAP_POSITION: c_uint = 16;
const ACAP_ORIENTATION: c_uint = 32;

// Arcan extern functions
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn arcan_video_getobject(id: arcan_vobj_id) ?*arcan_vobject;
extern fn arcan_video_resize_canvas(w: u32, h: u32) c_int;
extern fn arcan_video_defaultfont(ident: [*c]const u8, fd: c_int, pt_sz: c_int, hinting: c_int, append: bool) c_int;
extern fn arcan_vint_refresh(fract: f32, nd: *usize) u32;
extern fn arcan_vint_drawcursor(erase: bool) void;
extern fn arcan_vint_world() ?*struct_agp_vstore;
extern fn arcan_vint_worldrt() ?*struct_agp_rendertarget;
extern fn arcan_vint_drop_vstore(vs: ?*struct_agp_vstore) void;
extern fn arcan_vint_findrt(vobj: ?*arcan_vobject) ?*struct_agp_rendertarget;
extern fn arcan_vint_findrt_color_store(vobj: ?*arcan_vobject) ?*struct_agp_vstore;
extern fn arcan_event_enqueue(ctx: ?*struct_arcan_evctx, ev: *arcan_event) c_int;
extern fn platform_device_poll(identifier: ?*[*c]u8) c_int;
extern fn arcan_event_denqueue(ctx: ?*struct_arcan_evctx, ev: *arcan_event) c_int;
extern fn arcan_event_defaultctx() ?*struct_arcan_evctx;
extern fn arcan_event_add_source(ctx: ?*struct_arcan_evctx, fd: c_int, mode: c_int, tag: c_int, input: bool) c_int;
extern fn arcan_bench_register_cost(cost: u32) void;
extern fn arcan_conductor_deadline(ms: u32) void;
extern fn arcan_conductor_fakesynch(ms: u8) void;
extern fn arcan_frametime() i64;
extern fn arcan_timemillis() u64;
extern fn arcan_mm_to_pt(mm: f32) f32;
extern fn identity_matrix(m: *[16]f32) void;
extern fn arcan_shmif_open_ext(flags: c_int, arg: ?*?*struct_arg_arr, cfg: struct_shmif_open_ext, cfg_sz: usize) struct_arcan_shmif_cont;
extern fn arcan_shmif_initial(conn: *struct_arcan_shmif_cont, out: *?*struct_arcan_shmif_initial) c_int;
extern fn arcan_shmif_resize(conn: *struct_arcan_shmif_cont, w: u16, h: u16) bool;
extern fn arcan_shmif_signal(conn: *struct_arcan_shmif_cont, mask: c_int) c_int;
extern fn arcan_shmif_enqueue(conn: *struct_arcan_shmif_cont, ev: *arcan_event) c_int;
extern fn arcan_shmif_poll(conn: *struct_arcan_shmif_cont, ev: *arcan_event) c_int;
extern fn arcan_shmif_drop(conn: *struct_arcan_shmif_cont) void;
extern fn arcan_shmif_acquire(conn: *struct_arcan_shmif_cont, arg: ?*anyopaque, seg_type: c_uint, flags: c_int) struct_arcan_shmif_cont;
extern fn arcan_shmif_setprimary(dir: c_int, conn: *struct_arcan_shmif_cont) void;

// AGP functions (vk_shared.zig / vk_shdrmgmt.zig)
extern fn agp_activate_vstore(backing: ?*struct_agp_vstore) void;
extern fn agp_shader_activate(shid: u32) c_int;
extern fn agp_shader_envv(slot: c_uint, value: ?*anyopaque, size: usize) c_int;
extern fn agp_default_shader(shader_type: c_uint) u32;
extern fn agp_draw_vobj(x1: f32, y1: f32, x2: f32, y2: f32, txcos: ?[*]const f32, modelview: ?[*]const f32) void;
extern fn agp_blendstate(mode: c_uint) void;
extern fn agp_activate_rendertarget(tgt: ?*struct_agp_rendertarget) void;
extern fn agp_rendertarget_vstore(tgt: ?*struct_agp_rendertarget) ?*struct_agp_vstore;
extern fn vk_last_rendered_vstore() ?*struct_agp_vstore;
extern fn vk_shared_set_screen_size(w: u32, h: u32) void;
extern fn vk_shared_begin_frame() void;
extern fn vk_shared_end_all_passes() void;
extern fn vk_screen_composite_vstore() ?*struct_agp_vstore;
extern fn agp_save_output(w: usize, h: usize, dst: ?[*]u32, dsz: usize) void;

// VK bridge functions (vk.zig)
extern fn vk_env_set_rendering_active(active: bool) void;
extern fn vk_env_set_rt_viewport(x: i32, y: i32, w: i32, h: i32) void;
extern fn vk_env_set_swapchain_extent(w: u32, h: u32) void;
extern fn vk_env_get_active_texture() u32;
extern fn vk_env_bind_texture(id: u32) void;
extern fn vk_env_is_rendering() bool;
extern fn vk_env_begin_frame_cmd() void;
extern fn vk_env_submit_empty_frame() void;
extern fn vk_env_import_dmabuf_texture(fd: c_int, w: u32, h: u32, stride: u64, offset: u64, drm_format: u32, modifier: u64) u32;
extern fn vk_env_update_dmabuf_texture(id: u32, fd: c_int, w: u32, h: u32, stride: u64, offset: u64, drm_format: u32, modifier: u64) bool;
extern fn vk_env_destroy_texture(id: u32) void;
extern fn vk_env_readback_texture(tex_id: u32, dst: [*]u8, dst_sz: u32) bool;

// LWA Lua integration (engine)
extern fn arcan_lwa_subseg_ev(ctx: ?*anyopaque, src: arcan_vobj_id, cb_tag: usize, ev: *arcan_event) void;
extern var main_lua_context: ?*anyopaque;

// Evdev event layer (renamed exports from evdev/event.zig)
extern fn evdev_event_preinit() void;
extern fn evdev_event_init(ctx: ?*struct_arcan_evctx) void;
extern fn evdev_event_process(ctx: ?*struct_arcan_evctx) void;
extern fn evdev_event_deinit(ctx: ?*struct_arcan_evctx) void;
extern fn evdev_event_reset(ctx: ?*struct_arcan_evctx) void;
extern fn evdev_event_analogstate(devid: c_int, axisid: c_int, lower_bound: ?*c_int, upper_bound: ?*c_int, deadzone: ?*c_int, kernel_size: ?*c_int, mode: ?*c_int) c_int;
extern fn evdev_event_analogall(enable: bool, mouse: bool) void;
extern fn evdev_event_analogfilter(devid: c_int, axisid: c_int, lower_bound: c_int, upper_bound: c_int, deadzone: c_int, buffer_sz: c_int, kind: c_int) void;
extern fn evdev_event_keyrepeat(ctx: ?*struct_arcan_evctx, period: ?*c_int, delay: ?*c_int) void;
extern fn evdev_event_samplebase(devid: c_int, xyz: ?[*]f32) void;
extern fn evdev_event_devlabel(devid: c_int) [*c]const u8;
extern fn evdev_event_translation(devid: c_int, action: c_int, arg: ?*?[*:0]const u8, err: ?*?[*:0]const u8) c_int;
extern fn evdev_event_device_request(space: c_int, path: ?[*:0]const u8) c_int;
extern fn evdev_event_rescan_idev(ctx: ?*struct_arcan_evctx) void;
extern fn evdev_event_capabilities(out: ?*[*c]const u8) c_uint;
extern fn evdev_event_envopts() [*c]const [*c]const u8;
extern fn evdev_device_lock(devind: c_int, lock_state: bool) void;

// Types

const PlatformMode = enum { xcb, khr_display, gbm_kms, lwa };

const MAX_LWA_DISPLAYS = 8;

const LwaDisplay = struct {
    conn: struct_arcan_shmif_cont = std.mem.zeroes(struct_arcan_shmif_cont),
    mapped: bool = false,
    visible: bool = false,
    focused: bool = false,
    dpms: c_uint = 0,
    vstore: ?*struct_agp_vstore = null,
    ppcm: f32 = 0,
    id: usize = 0,
    pending: u64 = 0,
    decay: usize = 0,
};

var lwa_disp: [MAX_LWA_DISPLAYS]LwaDisplay = blk: {
    var d: [MAX_LWA_DISPLAYS]LwaDisplay = undefined;
    for (0..MAX_LWA_DISPLAYS) |i| {
        d[i] = .{ .id = i };
    }
    break :blk d;
};

// State

var state = struct {
    mode: PlatformMode = .xcb,
    env: ?*agp_vk.VkEnv = null,
    // Display mode
    swapchain: vk_wsi.Swapchain = .{},
    xcb_window: ?vk_xcb.XcbWindow = null,
    displays: [8]vk_wsi.DisplayInfo = undefined,
    display_count: u32 = 0,
    drm_display_fd: std.posix.fd_t = -1,
    // GBM+KMS direct-display mode (Asahi/Mac Studio): we render into our own
    // VkImages exported as DMA-BUFs and present via drmModePageFlip rather
    // than VK_KHR_swapchain. state.swapchain.extent/format are still mirrored
    // from gbm_swapchain so the rest of video.zig (initPhase2, screen-size
    // exports) doesn't need a per-mode branch.
    gbm_swapchain: vk_gbm_kms.Swapchain = .{},
    gbm_acquired: vk_gbm_kms.Acquired = .{},
    phy_width_mm: u32 = 0,
    phy_height_mm: u32 = 0,
    refresh: u32 = 120,
    // LWA mode
    offscreen: vk_offscreen.OffscreenTarget = .{},
    signal_pending: bool = false,
    // Shared
    canvasw: u16 = 0,
    canvash: u16 = 0,
    projection: [16]f32 = std.mem.zeroes([16]f32),
    clear_color: [4]f32 = .{ 0.05, 0.05, 0.15, 1.0 },
    vid: arcan_vobj_id = undefined,
    vid_ts: u32 = 0,
    last: i64 = 0,
    txcos: [8]f32 = std.mem.zeroes([8]f32),
    drawx: f32 = 0,
    drawy: f32 = 0,
    draww: f32 = 0,
    drawh: f32 = 0,
    frame_count: u32 = 0,
}{};

// Helpers

fn buildOrtho(m: *[16]f32, left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) void {
    @memset(m, 0);
    m[0] = 2.0 / (right - left);
    m[5] = 2.0 / (top - bottom);
    m[10] = 2.0 / (far - near);
    m[12] = -(right + left) / (right - left);
    m[13] = -(top + bottom) / (top - bottom);
    m[14] = -(far + near) / (far - near);
    m[15] = 1.0;
}

fn detectMode() PlatformMode {
    // LWA nesting first: a CONNPATH/SOCKIN_FD means we are a client of a
    // parent arcan (durian under durian) regardless of display system.
    const has_connpath = std.posix.getenv("ARCAN_CONNPATH") != null;
    const has_sockin = std.posix.getenv("ARCAN_SOCKIN_FD") != null;
    if (has_connpath or has_sockin) {
        // When ARCAN_HANDOVER is set, ARCAN_SOCKIN_FD was explicitly given to us
        // by shmif_platform_execve — it's the handover'd socket we MUST use.
        // Only unset SOCKIN_FD when there's no handover (inherited from parent).
        const has_handover = std.posix.getenv("ARCAN_HANDOVER") != null;
        if (has_connpath and has_sockin and !has_handover) {
            _ = c.unsetenv("ARCAN_SOCKIN_FD");
            _ = c.unsetenv("ARCAN_SOCKIN_MEMFD");
        }
        return .lwa;
    }
    if (std.posix.getenv("DISPLAY") != null)
        return .xcb;
    // ARCAN_VIDEO_VK_KHR_DISPLAY=1 forces the Vulkan-ICD-provided display
    // path (works on desktop Intel/AMD/Nvidia). Default is the GBM+KMS
    // backend because the common failure mode on Asahi/Honeykrisp is that
    // VK_KHR_display isn't implemented at all.
    if (std.posix.getenv("ARCAN_VIDEO_VK_KHR_DISPLAY") != null)
        return .khr_display;
    return .gbm_kms;
}

fn setupCommonState(w: u16, h: u16) void {
    state.canvasw = w;
    state.canvash = h;
    state.draww = @floatFromInt(w);
    state.drawh = @floatFromInt(h);
    buildOrtho(&state.projection, 0, @floatFromInt(w), @floatFromInt(h), 0, 0, 1);
    state.vid = ARCAN_VIDEO_WORLDID;
    @memcpy(&state.txcos, &arcan_video_display.default_txcos);
}

// Host-paste stash (Piece 2)
// SelectionNotify lands asynchronously after `paste_from_host()` is
// called. We park the payload here and let the lua appl pop it on a
// timer tick. Single-slot — a fresh paste replaces any prior unconsumed
// payload (rare; durian polls within one frame).
var pending_host_paste: ?[]u8 = null;

fn pending_host_paste_set(buf: []u8) void {
    if (pending_host_paste) |old| std.heap.c_allocator.free(old);
    pending_host_paste = buf;
}

/// C ABI: write the pending paste payload into `out` (max `cap` bytes,
/// no NUL terminator). Returns the *full* payload length (so callers
/// can tell when truncation happened) or 0 if there's nothing pending.
/// On success, the stash is cleared.
export fn platform_video_pop_host_paste(out: [*c]u8, cap: usize) usize {
    const buf = pending_host_paste orelse return 0;
    const n = @min(buf.len, cap);
    if (out != null and n > 0) {
        @memcpy(out[0..n], buf[0..n]);
    }
    const total = buf.len;
    std.heap.c_allocator.free(buf);
    pending_host_paste = null;
    return total;
}

// Platform mode query

export fn platform_is_lwa_mode() bool {
    return state.mode == .lwa;
}

export fn vk_platform_set_clear_color(r: f32, g: f32, b: f32, a: f32) void {
    state.clear_color = .{ r, g, b, a };
}

export fn vk_platform_update_canvas(w: u32, h: u32) void {
    if (state.mode == .lwa) return;
    if (w == 0 or h == 0) return;
    if (w == state.canvasw and h == state.canvash) return;
    state.canvasw = @intCast(w);
    state.canvash = @intCast(h);
    state.draww = @floatFromInt(state.canvasw);
    state.drawh = @floatFromInt(state.canvash);
    buildOrtho(&state.projection, 0, state.draww, state.drawh, 0, 0, 1);
}

// ══════════════════════════════════════════════════════════════════
// platform_video_* Exports
// ══════════════════════════════════════════════════════════════════

export fn platform_video_preinit() void {}

/// Set the host X11 CLIPBOARD selection text. No-op if running on a
/// non-XCB backend (e.g. bare-display vk_wsi). Called from the lua
/// `set_clipboard(str)` builtin via durian's clipboard hook.
export fn platform_video_set_clipboard(text: [*c]const u8, len: usize) void {
    if (state.xcb_window != null) {
        const slice = if (text != null and len > 0)
            text[0..len]
        else
            &[_]u8{};
        vk_xcb.setClipboardText(&state.xcb_window.?, slice);
    }
}

/// Issue a CLIPBOARD ConvertSelection on the host X server. The reply
/// arrives asynchronously as a SelectionNotify, gets queued as a
/// .clipboard_in InputEvent, and is forwarded by processXcbInput.
/// Returns 1 on issue, 0 if no XCB backend or a paste is in flight.
export fn platform_video_request_clipboard_paste() c_int {
    const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
    const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
    const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
    if (state.xcb_window != null) {
        const ok = vk_xcb.requestClipboardPaste(&state.xcb_window.?);
        if (sc_open("/tmp/clip_xbridge.log", "a")) |f| {
            _ = sc_fprintf(f, "request_clipboard_paste: have_xcb_window=1 issued=%d\n", @as(c_int, if (ok) 1 else 0));
            _ = sc_fclose(f);
        }
        return if (ok) 1 else 0;
    }
    if (sc_open("/tmp/clip_xbridge.log", "a")) |f| {
        _ = sc_fprintf(f, "request_clipboard_paste: NO xcb_window\n");
        _ = sc_fclose(f);
    }
    return 0;
}

/// Detect GPU kernel driver from sysfs and set VK_ICD_FILENAMES so the
/// Vulkan loader only tries the ICD that matches the actual hardware.
/// Without this, the loader dlopen's every installed ICD (radeon, nouveau,
/// etc.) which pulls in LLVM and hangs in our custom zig_dlopen linker.
fn selectIcdFromSysfs() void {
    // Already set by user — respect it
    if (std.posix.getenv("VK_ICD_FILENAMES") != null) return;
    if (std.posix.getenv("VK_DRIVER_FILES") != null) return;

    const driver_to_icd = [_]struct { driver: []const u8, icd: [*:0]const u8 }{
        .{ .driver = "asahi", .icd = "/usr/share/vulkan/icd.d/asahi_icd.aarch64.json" },
        .{ .driver = "amdgpu", .icd = "/usr/share/vulkan/icd.d/radeon_icd.x86_64.json" },
        .{ .driver = "i915", .icd = "/usr/share/vulkan/icd.d/intel_icd.x86_64.json" },
        .{ .driver = "xe", .icd = "/usr/share/vulkan/icd.d/intel_icd.x86_64.json" },
        .{ .driver = "nouveau", .icd = "/usr/share/vulkan/icd.d/nouveau_icd.x86_64.json" },
        .{ .driver = "panfrost", .icd = "/usr/share/vulkan/icd.d/panfrost_icd.aarch64.json" },
        .{ .driver = "v3d", .icd = "/usr/share/vulkan/icd.d/broadcom_icd.aarch64.json" },
        .{ .driver = "msm", .icd = "/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json" },
    };

    // Scan /sys/class/drm/card0..card7 for kernel driver name
    var card_idx: u8 = 0;
    while (card_idx < 8) : (card_idx += 1) {
        var path_buf: [128]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, "/sys/class/drm/card{d}/device/driver", .{card_idx}) catch continue;
        const link = std.posix.readlinkZ(path, &path_buf) catch continue;
        const driver_name = std.fs.path.basename(link);

        for (driver_to_icd) |entry| {
            if (std.mem.eql(u8, driver_name, entry.driver)) {
                // Verify the ICD JSON actually exists before setting
                if (std.fs.cwd().access(std.mem.sliceTo(entry.icd, 0), .{})) {
                    std.log.info("vk: detected GPU driver '{s}', selecting ICD: {s}", .{ driver_name, entry.icd });
                    _ = c.setenv("VK_ICD_FILENAMES", entry.icd, 1);
                    return;
                } else |_| {}
            }
        }
    }
    std.log.warn("vk: could not detect GPU driver from sysfs, using all ICDs", .{});
}

export fn platform_video_init(
    width: u16,
    height: u16,
    bpp: u8,
    fs: bool,
    frames: bool,
    caption: ?[*:0]const u8,
) bool {
    _ = bpp;
    _ = fs;
    _ = frames;
    selectIcdFromSysfs();
    state.mode = detectMode();
    return switch (state.mode) {
        .lwa => initLwa(width, height, caption),
        .xcb, .khr_display => initDisplay(width, height, caption),
        .gbm_kms => initGbmKms(width, height, caption),
    };
}

fn initGbmKms(width_in: u16, height_in: u16, caption: ?[*:0]const u8) bool {
    _ = width_in;
    _ = caption;
    _ = height_in;
    var info: vk_gbm_kms.DisplayInfo = .{};
    vk_gbm_kms.acquireDisplay(&state.gbm_acquired, &info) catch |e| {
        std.log.err("vk_gbm_kms: acquireDisplay failed: {s}", .{@errorName(e)});
        return false;
    };

    // Empty instance-extension list → agp_vk.init picks the "headless"
    // device-extension set in vk.zig:3076 (VK_KHR_external_memory_fd +
    // VK_EXT_external_memory_dma_buf + VK_EXT_image_drm_format_modifier).
    state.env = agp_vk.init(&[_][*:0]const u8{}) catch |e| {
        std.log.err("vk_gbm_kms: agp_vk.init failed: {s}", .{@errorName(e)});
        return false;
    };
    const env = state.env.?;

    // Switch to glibc TLS for everything that calls into the dlopened
    // Vulkan ICD (createSwapchain, initPhase2, set_swapchain_extent etc.).
    // Mirrors initDisplay at line 777. Without this, hk_CreateImage and
    // vk_common_CreateShaderModule crash inside libc malloc.
    if (use_zig_dlopen) zig_foreign_begin();
    defer if (use_zig_dlopen) zig_foreign_end();

    state.gbm_swapchain = vk_gbm_kms.createSwapchain(env, &state.gbm_acquired, info.mode_width, info.mode_height) catch |e| {
        std.log.err("vk_gbm_kms: createSwapchain failed: {s}", .{@errorName(e)});
        return false;
    };

    // Stash mode + connector for the modeset that fires on first endFrame.
    vk_gbm_kms.primeForModeset(&state.gbm_acquired);

    // Mirror extent + format into the legacy state.swapchain so unrelated
    // pieces of video.zig (initPhase2, set_swapchain_extent, set_screen_size)
    // see a consistent screen size without per-mode branches.
    state.swapchain.extent = state.gbm_swapchain.extent;
    state.swapchain.format = state.gbm_swapchain.format;
    state.refresh = if (info.refresh_mhz >= 1000) info.refresh_mhz / 1000 else 60;

    const sw: u16 = @intCast(state.swapchain.extent.width);
    const sh: u16 = @intCast(state.swapchain.extent.height);
    setupCommonState(sw, sh);

    if (info.physical_width_mm > 0 and info.physical_height_mm > 0) {
        state.phy_width_mm = info.physical_width_mm;
        state.phy_height_mm = info.physical_height_mm;
    }

    agp_vk.initPhase2(env, state.swapchain.format) catch return false;
    vk_env_set_swapchain_extent(state.swapchain.extent.width, state.swapchain.extent.height);
    vk_shared_set_screen_size(state.swapchain.extent.width, state.swapchain.extent.height);

    std.log.err("vk_gbm_kms: init OK — {d}x{d}@{d}Hz, {d} buffers, mode dispatch ready", .{
        state.swapchain.extent.width, state.swapchain.extent.height, state.refresh, state.gbm_swapchain.image_count,
    });
    return true;
}

fn initDisplay(width_in: u16, height_in: u16, caption: ?[*:0]const u8) bool {
    var w = width_in;
    var h = height_in;
    if (w == 0 or h == 0) {
        w = 800;
        h = 600;
    }

    const use_xcb = state.mode == .xcb;

    // vk.init() triggers foreignInit via zig_dlopen and wraps its Vulkan calls.
    if (use_xcb) {
        const extensions = [_][*:0]const u8{ "VK_KHR_surface", "VK_KHR_xcb_surface" };
        state.env = agp_vk.init(&extensions) catch return false;
    } else {
        const extensions = [_][*:0]const u8{
            "VK_KHR_surface",
            "VK_KHR_display",
            "VK_EXT_direct_mode_display",
            "VK_EXT_acquire_drm_display",
        };
        state.env = agp_vk.init(&extensions) catch return false;
    }
    const env = state.env.?;

    // Switch to glibc TLS for XCB/swapchain init (foreign.ready is now true after vk.init)
    if (use_zig_dlopen) zig_foreign_begin();
    defer if (use_zig_dlopen) zig_foreign_end();

    var surface: vk.SurfaceKHR = .null_handle;

    if (use_xcb) {
        const title = caption orelse "arcan (Vulkan)";
        state.xcb_window = vk_xcb.createXcbWindow(w, h, title) catch return false;
        surface = vk_xcb.createXcbSurface(env.vki, env.instance, &state.xcb_window.?) catch {
            vk_xcb.destroyXcbWindow(&state.xcb_window.?);
            state.xcb_window = null;
            return false;
        };
    } else {
        state.display_count = vk_wsi.enumerateDisplays(env.vki, env.physical_device, &state.displays) catch 0;
        if (state.display_count == 0) {
            // Apple Silicon: GPU and display are separate DRM devices.
            // Use VK_EXT_acquire_drm_display to acquire from the display card.
            const result = vk_wsi.acquireDrmDisplay(env.vki, env.physical_device, &state.displays) catch |e| {
                std.log.err("vk: acquireDrmDisplay failed: {s}", .{@errorName(e)});
                return false;
            };
            state.display_count = result.count;
            state.drm_display_fd = result.drm_fd;
        }
        if (state.display_count == 0) return false;
        const display = &state.displays[0];
        if (display.mode_count == 0) return false;

        var best_mode_idx: u32 = 0;
        var best_diff: u64 = std.math.maxInt(u64);
        for (0..display.mode_count) |i| {
            const mw = display.modes[i].parameters.visible_region.width;
            const mh = display.modes[i].parameters.visible_region.height;
            const dw: u64 = if (mw >= w) mw - w else w - mw;
            const dh: u64 = if (mh >= h) mh - h else h - mh;
            const diff = dw * dw + dh * dh;
            if (diff < best_diff) {
                best_diff = diff;
                best_mode_idx = @intCast(i);
            }
        }

        const mode = display.modes[best_mode_idx];
        const extent = mode.parameters.visible_region;
        w = @intCast(extent.width);
        h = @intCast(extent.height);
        surface = vk_wsi.createDisplaySurface(env.vki, env.instance, mode.display_mode, extent, display.plane_index) catch return false;
        if (mode.parameters.refresh_rate > 0) {
            state.refresh = mode.parameters.refresh_rate / 1000;
            if (state.refresh == 0) state.refresh = 60;
        }
    }

    state.swapchain = vk_wsi.createSwapchain(env, surface, w, h) catch return false;


    const sw: u16 = @intCast(state.swapchain.extent.width);
    const sh: u16 = @intCast(state.swapchain.extent.height);
    setupCommonState(sw, sh);

    if (state.xcb_window) |xcb_win| {
        const scr_px_w: f32 = @floatFromInt(xcb_win.screen.*.width_in_pixels);
        const scr_mm_w: f32 = @floatFromInt(xcb_win.phy_width_mm);
        const scr_px_h: f32 = @floatFromInt(xcb_win.screen.*.height_in_pixels);
        const scr_mm_h: f32 = @floatFromInt(xcb_win.phy_height_mm);
        if (scr_px_w > 0 and scr_mm_w > 0) {
            const hdpi = scr_px_w / scr_mm_w * 25.4;
            const vdpi = scr_px_h / scr_mm_h * 25.4;
            const fw: f32 = @floatFromInt(state.canvasw);
            const fh: f32 = @floatFromInt(state.canvash);
            state.phy_width_mm = @intFromFloat(fw / hdpi * 25.4);
            state.phy_height_mm = @intFromFloat(fh / vdpi * 25.4);
        }
    }

    agp_vk.initPhase2(env, state.swapchain.format) catch return false;
    vk_env_set_swapchain_extent(state.swapchain.extent.width, state.swapchain.extent.height);
    vk_shared_set_screen_size(state.swapchain.extent.width, state.swapchain.extent.height);
    return true;
}

fn initLwa(width_in: u16, height_in: u16, caption: ?[*:0]const u8) bool {
    var shmarg: ?*struct_arg_arr = null;
    var flags: c_int = SHMIF_NOACTIVATE; // LWA compositor doesn't need preroll
    if (width_in > 32 and height_in > 32)
        flags |= SHMIF_NOACTIVATE_RESIZE;

    arcan_warning("vk_lwa: opening shmif connection (SOCKIN_FD=%s, CONNPATH=%s)\n",
        @as([*:0]const u8, std.posix.getenv("ARCAN_SOCKIN_FD") orelse "(null)"),
        @as([*:0]const u8, std.posix.getenv("ARCAN_CONNPATH") orelse "(null)"));

    lwa_disp[0].conn = arcan_shmif_open_ext(
        @intCast(flags),
        &shmarg,
        struct_shmif_open_ext{
            .type = SEGID_LWA,
            .title = caption orelse "arcan (Vulkan LWA)",
            .guid = .{ 0, 0 },
        },
        @sizeOf(struct_shmif_open_ext),
    );

    if (lwa_disp[0].conn.addr == null) {
        arcan_warning("vk_lwa: shmif_open_ext FAILED\n");
        return false;
    }

    _ = arcan_event_add_source(arcan_event_defaultctx(), lwa_disp[0].conn.epipe, c.O_RDONLY, -1, true);

    var init_ptr: ?*struct_arcan_shmif_initial = null;
    _ = arcan_shmif_initial(&lwa_disp[0].conn, &init_ptr);
    // init_ptr may be null when preroll is skipped (SHMIF_NOACTIVATE) — that's OK

    // Vulkan renders top-down (upper-left origin) — no ORIGO_LL needed
    lwa_disp[0].conn.hints = SHMIF_RHINT_VSIGNAL_EV;

    var w = width_in;
    var h = height_in;
    if (w == 0) w = @intCast(lwa_disp[0].conn.w);
    if (h == 0) h = @intCast(lwa_disp[0].conn.h);
    _ = arcan_shmif_resize(&lwa_disp[0].conn, w, h);

    const no_extensions = [_][*:0]const u8{};
    state.env = agp_vk.init(&no_extensions) catch {
        arcan_warning("vk_lwa: Vulkan init failed\n");
        return false;
    };
    const env = state.env.?;

    // Switch to glibc TLS for Vulkan device calls (createImage, etc.)
    if (use_zig_dlopen) zig_foreign_begin();
    defer if (use_zig_dlopen) zig_foreign_end();

    state.offscreen = vk_offscreen.createOffscreen(env, w, h) catch {
        arcan_warning("vk_lwa: createOffscreen failed\n");
        return false;
    };
    setupCommonState(w, h);

    agp_vk.initPhase2(env, state.offscreen.format) catch return false;
    vk_env_set_swapchain_extent(w, h);
    vk_shared_set_screen_size(w, h);

    // Close the foreign (glibc) TLS window now — everything below this
    // line is arcan-side code (arcan_video_defaultfont, arcan_shmif_*)
    // that reads its own TLS-relative state and crashes if called while
    // tpidr_el0 still points at glibc. The deferred end at function exit
    // is harmless: depth counter prevents a double-restore.
    if (use_zig_dlopen) zig_foreign_end();

    if (init_ptr) |init| {
        if (init.fonts[0].fd != -1) {
            const pt_sz = arcan_mm_to_pt(init.fonts[0].size_mm);
            _ = arcan_video_defaultfont("arcan-default", init.fonts[0].fd, @intFromFloat(pt_sz), init.fonts[0].hinting, false);
            init.fonts[0].fd = -1;
            if (init.fonts[1].fd != -1) {
                const pt_sz2 = arcan_mm_to_pt(init.fonts[1].size_mm);
                _ = arcan_video_defaultfont("arcan-default", init.fonts[1].fd, @intFromFloat(pt_sz2), init.fonts[1].hinting, true);
                init.fonts[1].fd = -1;
            }
        }
        lwa_disp[0].ppcm = init.density;
    }

    lwa_disp[0].mapped = true;
    lwa_disp[0].dpms = ADPMS_ON;
    lwa_disp[0].visible = true;
    lwa_disp[0].focused = true;

    // Hide cursor (LWA composites its own)
    var cursor_ev: arcan_event = undefined; @memset(std.mem.asBytes(&cursor_ev), 0);
    cursor_ev.setCategory(EVENT_EXTERNAL);
    cursor_ev.getExt().*.kind = EVENT_EXTERNAL_CURSORHINT;
    const hmsg = "hidden";
    @memcpy(cursor_ev.getExt().*.unnamed_0.message.data[0..hmsg.len], hmsg);
    _ = arcan_shmif_enqueue(&lwa_disp[0].conn, &cursor_ev);

    arcan_shmif_setprimary(SHMIF_INPUT, &lwa_disp[0].conn);
    return true;
}

// XCB Input Translation

fn processXcbInput(xcb_win: *vk_xcb.XcbWindow) void {
    const ctx = arcan_event_defaultctx();

    for (0..xcb_win.input_count) |i| {
        const ie = &xcb_win.input_events[i];

        switch (ie.kind) {
            .key_press, .key_release => {
                var ev: arcan_event = undefined; @memset(std.mem.asBytes(&ev), 0);
                ev.setCategory(EVENT_IO);
                const io = ev.getIo();
                io.kind = EVENT_IO_BUTTON;
                io.datatype = EVENT_IDATATYPE_TRANSLATED;
                io.devkind = EVENT_IDEVKIND_KEYBOARD;
                io.unnamed_0.unnamed_0.devid = 0;
                io.unnamed_0.unnamed_0.subid = ie.scancode;
                io.input.translated.active = if (ie.kind == .key_press) 1 else 0;
                io.input.translated.scancode = @truncate(ie.scancode);
                io.input.translated.keysym = @truncate(vk_xcb.xkbToSdl12(ie.keysym));
                io.input.translated.modifiers = ie.mods;
                for (0..5) |j| {
                    io.input.translated.utf8[j] = ie.utf8[j];
                }
                _ = arcan_event_enqueue(ctx, &ev);
            },
            .button_press, .button_release => {
                const pressed = (ie.kind == .button_press);
                const xcb_btn = ie.button;

                if (xcb_btn == 4 or xcb_btn == 5) {
                    var ev: arcan_event = undefined; @memset(std.mem.asBytes(&ev), 0);
                    ev.setCategory(EVENT_IO);
                    const io = ev.getIo();
                    io.kind = EVENT_IO_BUTTON;
                    io.datatype = EVENT_IDATATYPE_DIGITAL;
                    io.devkind = EVENT_IDEVKIND_MOUSE;
                    io.unnamed_0.unnamed_0.devid = 0;
                    io.unnamed_0.unnamed_0.subid = if (xcb_btn == 4) 4 else 5;
                    if (pressed) {
                        io.input.digital.active = 1;
                        _ = arcan_event_enqueue(ctx, &ev);
                        io.input.digital.active = 0;
                        _ = arcan_event_enqueue(ctx, &ev);
                    }
                } else {
                    var ev: arcan_event = undefined; @memset(std.mem.asBytes(&ev), 0);
                    ev.setCategory(EVENT_IO);
                    const io = ev.getIo();
                    io.kind = EVENT_IO_BUTTON;
                    io.datatype = EVENT_IDATATYPE_DIGITAL;
                    io.devkind = EVENT_IDEVKIND_MOUSE;
                    io.unnamed_0.unnamed_0.devid = 0;
                    io.unnamed_0.unnamed_0.subid = switch (xcb_btn) {
                        1 => 1,
                        2 => 3,
                        3 => 2,
                        else => @as(u16, xcb_btn),
                    };
                    io.input.digital.active = if (pressed) 1 else 0;
                    _ = arcan_event_enqueue(ctx, &ev);
                }
            },
            .motion => {
                const win_w: i16 = @intCast(state.swapchain.extent.width);
                const win_h: i16 = @intCast(state.swapchain.extent.height);
                const can_w: i16 = @intCast(state.canvasw);
                const can_h: i16 = @intCast(state.canvash);
                const scaled_x: i16 = if (win_w > 0)
                    @intCast(@divTrunc(@as(i32, ie.x) * @as(i32, can_w), @as(i32, win_w)))
                else
                    ie.x;
                const scaled_y: i16 = if (win_h > 0)
                    @intCast(@divTrunc(@as(i32, ie.y) * @as(i32, can_h), @as(i32, win_h)))
                else
                    ie.y;

                var ev: arcan_event = undefined; @memset(std.mem.asBytes(&ev), 0);
                ev.setCategory(EVENT_IO);
                const io = ev.getIo();
                io.kind = EVENT_IO_AXIS_MOVE;
                io.datatype = EVENT_IDATATYPE_ANALOG;
                io.devkind = EVENT_IDEVKIND_MOUSE;
                io.unnamed_0.unnamed_0.devid = 0;
                io.unnamed_0.unnamed_0.subid = 0;
                io.input.analog.nvalues = 1;
                io.input.analog.axisval[0] = scaled_x;
                _ = arcan_event_enqueue(ctx, &ev);

                io.unnamed_0.unnamed_0.subid = 1;
                io.input.analog.axisval[0] = scaled_y;
                _ = arcan_event_enqueue(ctx, &ev);
            },
            .clipboard_in => {
                // Stash the host-paste text in a process-global so the
                // lua appl can pop it via `pop_host_paste()`. Durian binds
                // a key to: paste_from_host() → next frame → pop_host_paste()
                // → target_input the result into the focused window.
                if (ie.clip_text) |buf| {
                    pending_host_paste_set(buf);
                    ie.clip_text = null; // ownership transferred
                }
                vk_xcb.freeClipboardEvent(ie);
            },
        }
    }
}

// Synch

export fn platform_video_synch(
    _: u64,
    fract: f32,
    pre: ?*const fn () callconv(.c) void,
    post: ?*const fn () callconv(.c) void,
) void {
    switch (state.mode) {
        .lwa => synchLwa(fract, pre, post),
        .xcb, .khr_display, .gbm_kms => synchDisplay(fract, pre, post),
    }
}

fn synchDisplay(fract: f32, pre: ?*const fn () callconv(.c) void, post: ?*const fn () callconv(.c) void) void {
    // bug 0234: pace the conductor unconditionally. Without this call the
    // gbm_kms / xcb / khr_display render path can leave
    // conductor.set_deadline at -1, which makes arcan_conductor_run
    // busy-loop because (next_synch == 0) short-circuits its gating
    // condition. On a real display vk_wsi.endFrame blocks on a real
    // vblank and provides implicit pacing; on a phantom-HDMI HPD (e.g.
    // a Mac Studio with no TV plugged in but the connector reporting
    // connected) endFrame returns immediately and the loop spirals to
    // ~9000 fps on one core. Setting the deadline early covers
    // swapchain-recreate failure and other early-return paths too.
    const deadline: u8 = blk: {
        const refresh: u32 = if (state.refresh == 0) 60 else state.refresh;
        const ms: u32 = 1000 / refresh;
        break :blk @intCast(@min(ms, @as(u32, 255)));
    };
    arcan_conductor_deadline(deadline);

    // bug 0128 second half: when running render-only on gbm_kms (no
    // connector at boot), check for a netlink hotplug event each frame
    // and promote to headful when a connector arrives. Cheap when
    // nothing changed (one syscall, returns 0 immediately). Only runs
    // in gbm_kms mode — xcb / khr_display / lwa have their own resize
    // paths.
    if (state.mode == .gbm_kms and state.gbm_acquired.disp_fd < 0) {
        const polled = platform_device_poll(null);
        if (polled == 2) {
            if (state.env) |env| {
                if (vk_gbm_kms.tryPromoteToHeadful(env, &state.gbm_acquired, &state.gbm_swapchain)) {
                    arcan_warning("vk_gbm_kms: promoted to headful via hotplug — emitting EVENT_VIDEO_DISPLAY_RESET\n");
                    var ev: arcan_event = undefined;
                    @memset(std.mem.asBytes(&ev), 0);
                    ev.setCategory(EVENT_VIDEO);
                    ev.getVid().*.kind = @intCast(EVENT_VIDEO_DISPLAY_RESET);
                    _ = arcan_event_enqueue(arcan_event_defaultctx(), &ev);
                }
            }
        }
    }

    // XCB display path
    // NOTE: Do NOT wrap entire synchDisplay with zig_foreign_begin/end!
    // The function body includes engine code (arcan_vint_refresh, processXcbInput)
    // that calls musl functions. musl's __errno_location uses tpidr_el0 to find TLS —
    // under glibc TLS, it writes errno to glibc's TLS area, corrupting tcache/malloc state.
    // Instead, individual vk_env_* functions have their own TLS wrapping.
    // Poll XCB events before frame
    if (state.xcb_window != null) {
        const xcb_win = &state.xcb_window.?;
        vk_xcb.pollEvents(xcb_win);
        processXcbInput(xcb_win);
        if (xcb_win.close_requested) {
            var ev: arcan_event = undefined; @memset(std.mem.asBytes(&ev), 0);
            ev.setCategory(EVENT_SYSTEM);
            ev.getSys().*.kind = EVENT_SYSTEM_EXIT;
            _ = arcan_event_enqueue(arcan_event_defaultctx(), &ev);
            xcb_win.close_requested = false;
        }
        if (xcb_win.resize_pending) {
            if (state.env) |env| {
                vk_wsi.destroySwapchainOnly(env, &state.swapchain);
                state.swapchain = vk_wsi.createSwapchain(
                    env,
                    state.swapchain.surface,
                    xcb_win.width,
                    xcb_win.height,
                ) catch {
                    arcan_warning("swapchain recreate failed on resize\n");
                    if (post) |p| p();
                    return;
                };
                const new_w = state.swapchain.extent.width;
                const new_h = state.swapchain.extent.height;
                vk_env_set_swapchain_extent(new_w, new_h);
                vk_shared_set_screen_size(new_w, new_h);
                vk_platform_update_canvas(new_w, new_h);
                _ = arcan_video_resize_canvas(new_w, new_h);
                arcan_video_display.dirty += 1;

                var ev: arcan_event = undefined; @memset(std.mem.asBytes(&ev), 0);
                ev.setCategory(EVENT_VIDEO);
                ev.getVid().*.kind = EVENT_VIDEO_DISPLAY_RESET;
                ev.getVid().*.source = -1;
                ev.getVid().*.unnamed_0.unnamed_0.displayid = 0;
                ev.getVid().*.unnamed_0.unnamed_0.width = @intCast(new_w);
                ev.getVid().*.unnamed_0.unnamed_0.height = @intCast(new_h);
                _ = arcan_event_enqueue(arcan_event_defaultctx(), &ev);
            }
            xcb_win.resize_pending = false;
        }
    }

    if (pre) |p| p();

    const env = state.env orelse {
        if (post) |p| p();
        return;
    };

    var vobj = arcan_video_getobject(state.vid);
    if (vobj == null) {
        state.vid = ARCAN_VIDEO_WORLDID;
        vobj = arcan_video_getobject(ARCAN_VIDEO_WORLDID);
    }

    vk_env_begin_frame_cmd();
    vk_shared_begin_frame();

    var nd: usize = 0;
    const cost = arcan_vint_refresh(fract, &nd);
    vk_shared_end_all_passes();

    var ds_from_rt = false;
    const ds: ?*struct_agp_vstore = blk: {
        if (state.vid == ARCAN_VIDEO_WORLDID) {
            // Use the largest rendered RT — this is the Vulkan texture the scene was drawn into
            const last_store = vk_last_rendered_vstore();
            if (last_store) |ls| {
                if (ls.vinf.text.glid != 0) { ds_from_rt = true; break :blk last_store; }
            }
            // Fallbacks
            const screen_store = vk_screen_composite_vstore();
            if (screen_store != null) { ds_from_rt = true; break :blk screen_store; }
            const world_rt_ptr = arcan_vint_worldrt();
            const rt_store = agp_rendertarget_vstore(world_rt_ptr);
            if (rt_store) |rs| {
                if (rs.vinf.text.glid != 0) { ds_from_rt = true; break :blk rt_store; }
            }
            break :blk arcan_vint_world();
        } else if (vobj) |vo| {
            // Non-WORLDID: this vobj is a display RT. Get its backing vstore.
            const rs = arcan_vint_findrt_color_store(vo);
            if (rs) |s| {
                if (s.vinf.text.glid != 0) { ds_from_rt = true; break :blk rs; }
            }
            // Fallback: vobj's own store
            if (vo.*.vstore) |vs| {
                if (vs.vinf.text.glid != 0) break :blk vo.*.vstore;
            }
            // Last resort: last rendered RT
            const lr = vk_last_rendered_vstore();
            if (lr) |ls| {
                if (ls.vinf.text.glid != 0) { ds_from_rt = true; break :blk lr; }
            }
        }
        break :blk null;
    };

    state.frame_count += 1;

    if (nd == 0) {
        if (ds) |d| {
            if (state.vid_ts == d.update_ts) {
                vk_env_submit_empty_frame();
                arcan_conductor_fakesynch(deadline);
                state.last = arcan_frametime();
                if (post) |p| p();
                return;
            }
        }
    }

    if (state.mode == .gbm_kms) {
        vk_gbm_kms.beginFrame(env, &state.gbm_swapchain, state.clear_color) catch {
            state.last = arcan_frametime();
            if (post) |p| p();
            return;
        };
    } else {
        vk_wsi.beginFrame(env, &state.swapchain, state.clear_color) catch {
            state.last = arcan_frametime();
            if (post) |p| p();
            return;
        };
    }
    vk_env_set_rendering_active(true);

    // Reset RT viewport so composite uses full swapchain extent, not the
    // last sub-RT's dimensions (which would clip the output).
    vk_env_set_rt_viewport(0, 0, 0, 0);

    if (ds) |d| {
        agp_activate_vstore(d);
        const shid = agp_default_shader(0);
        _ = agp_shader_activate(shid);
        const PROJECTION_MATR = 1;
        _ = agp_shader_envv(PROJECTION_MATR, @ptrCast(&state.projection), @sizeOf(f32) * 16);
        var imatr: [16]f32 align(16) = undefined;
        identity_matrix(&imatr);
        _ = agp_shader_envv(0, @ptrCast(&imatr), @sizeOf(f32) * 16);
        var unit_opa: f32 = 1.0;
        _ = agp_shader_envv(3, @ptrCast(&unit_opa), @sizeOf(f32));
        agp_blendstate(BLEND_NONE);
        state.vid_ts = d.update_ts;
        // NOTE: arcan_video_display.default_txcos is at the WRONG offset in our
        // hand-written extern struct (offset 0 instead of the real C offset).
        // Use known-good values directly until struct layout is fixed.
        const good_txcos = [8]f32{ 0, 0, 1, 0, 1, 1, 0, 1 };
        var flipped_txcos: [8]f32 = undefined;
        const txcos: [*]const f32 = blk: {
            if (state.vid == ARCAN_VIDEO_WORLDID or ds_from_rt)
                break :blk &good_txcos;
            const src: [*]const f32 = if (vobj) |vo|
                (vo.*.txcos orelse &good_txcos)
            else
                &good_txcos;
            flipped_txcos[0] = src[0]; flipped_txcos[1] = src[7];
            flipped_txcos[2] = src[2]; flipped_txcos[3] = src[5];
            flipped_txcos[4] = src[4]; flipped_txcos[5] = src[3];
            flipped_txcos[6] = src[6]; flipped_txcos[7] = src[1];
            break :blk &flipped_txcos;
        };
        agp_draw_vobj(state.drawx, state.drawy, state.draww, state.drawh, txcos, null);
    } else {}

    arcan_vint_drawcursor(false);
    vk_shared_end_all_passes();
    vk_env_set_rendering_active(false);
    if (state.mode == .gbm_kms) {
        vk_gbm_kms.endFrame(env, &state.gbm_swapchain, &state.gbm_acquired) catch {};
    } else {
        vk_wsi.endFrame(env, &state.swapchain) catch {};
    }

    arcan_bench_register_cost(cost);
    state.last = arcan_frametime();
    if (post) |p| p();
}


fn synchLwa(fract: f32, pre: ?*const fn () callconv(.c) void, post: ?*const fn () callconv(.c) void) void {
    // LWA display path
    if (pre) |p| p();

    const env = state.env orelse {
        if (post) |p| p();
        return;
    };

    var vobj = arcan_video_getobject(state.vid);
    if (vobj == null) {
        state.vid = ARCAN_VIDEO_WORLDID;
        vobj = arcan_video_getobject(ARCAN_VIDEO_WORLDID);
    }

    vk_env_begin_frame_cmd();
    vk_shared_begin_frame();

    var nd: usize = 0;
    const cost = arcan_vint_refresh(fract, &nd);
    vk_shared_end_all_passes();

    var ds_from_rt = false;
    const ds: ?*struct_agp_vstore = blk: {
        if (state.vid == ARCAN_VIDEO_WORLDID) {
            // Use the largest rendered RT — this is the Vulkan texture the scene was drawn into
            const last_store = vk_last_rendered_vstore();
            if (last_store) |ls| {
                if (ls.vinf.text.glid != 0) { ds_from_rt = true; break :blk last_store; }
            }
            // Fallbacks
            const screen_store = vk_screen_composite_vstore();
            if (screen_store != null) { ds_from_rt = true; break :blk screen_store; }
            const world_rt_ptr = arcan_vint_worldrt();
            const rt_store = agp_rendertarget_vstore(world_rt_ptr);
            if (rt_store) |rs| {
                if (rs.vinf.text.glid != 0) { ds_from_rt = true; break :blk rt_store; }
            }
            break :blk arcan_vint_world();
        } else if (vobj) |vo| {
            // Non-WORLDID: this vobj is a display RT. Get its backing vstore.
            const rs = arcan_vint_findrt_color_store(vo);
            if (rs) |s| {
                if (s.vinf.text.glid != 0) { ds_from_rt = true; break :blk rs; }
            }
            // Fallback: vobj's own store
            if (vo.*.vstore) |vs| {
                if (vs.vinf.text.glid != 0) break :blk vo.*.vstore;
            }
            // Last resort: last rendered RT
            const lr = vk_last_rendered_vstore();
            if (lr) |ls| {
                if (ls.vinf.text.glid != 0) { ds_from_rt = true; break :blk lr; }
            }
        }
        break :blk null;
    };

    state.frame_count += 1;

    if (nd == 0) {
        if (ds) |d| {
            if (state.vid_ts == d.update_ts) {
                vk_env_submit_empty_frame();
                arcan_conductor_fakesynch(4);
                state.last = arcan_frametime();
                if (post) |p| p();
                return;
            }
        }
    }

    vk_offscreen.beginFrame(env, &state.offscreen, state.clear_color) catch {
        state.last = arcan_frametime();
        if (post) |p| p();
        return;
    };
    vk_env_set_rendering_active(true);

    // Reset RT viewport so composite uses full offscreen extent
    vk_env_set_rt_viewport(0, 0, 0, 0);

    if (ds) |d| {
        agp_activate_vstore(d);
        const shid = agp_default_shader(0);
        _ = agp_shader_activate(shid);
        const PROJECTION_MATR = 1;
        _ = agp_shader_envv(PROJECTION_MATR, @ptrCast(&state.projection), @sizeOf(f32) * 16);
        var imatr: [16]f32 align(16) = undefined;
        identity_matrix(&imatr);
        _ = agp_shader_envv(0, @ptrCast(&imatr), @sizeOf(f32) * 16);
        var unit_opa: f32 = 1.0;
        _ = agp_shader_envv(3, @ptrCast(&unit_opa), @sizeOf(f32));
        agp_blendstate(BLEND_NONE);
        state.vid_ts = d.update_ts;
        const good_txcos2 = [8]f32{ 0, 0, 1, 0, 1, 1, 0, 1 };
        var flipped_txcos2: [8]f32 = undefined;
        const txcos: [*]const f32 = blk: {
            if (state.vid == ARCAN_VIDEO_WORLDID)
                break :blk &good_txcos2;
            const src: [*]const f32 = if (vobj) |vo|
                (vo.*.txcos orelse &good_txcos2)
            else
                &good_txcos2;
            flipped_txcos2[0] = src[0]; flipped_txcos2[1] = src[7];
            flipped_txcos2[2] = src[2]; flipped_txcos2[3] = src[5];
            flipped_txcos2[4] = src[4]; flipped_txcos2[5] = src[3];
            flipped_txcos2[6] = src[6]; flipped_txcos2[7] = src[1];
            break :blk &flipped_txcos2;
        };
        agp_draw_vobj(state.drawx, state.drawy, state.draww, state.drawh, txcos, null);
    }

    arcan_vint_drawcursor(false);
    vk_env_set_rendering_active(false);

    vk_offscreen.endFrame(env, &state.offscreen) catch {
        arcan_bench_register_cost(cost);
        state.last = arcan_frametime();
        if (post) |p| p();
        return;
    };

    // Wait for GPU readback
    {
        if (comptime use_zig_dlopen) zig_foreign_begin();
        defer if (comptime use_zig_dlopen) zig_foreign_end();
        _ = env.vkd.waitForFences(env.device, 1, @ptrCast(&env.frame_fence), .true, std.math.maxInt(u64)) catch {};
    }

    // Copy pixels to shmif video page
    if (vk_offscreen.readPixels(&state.offscreen)) |pixels| {
        const vidp_raw: [*c]u32 = lwa_disp[0].conn.unnamed_0.vidp;
        if (vidp_raw == null) {
            arcan_bench_register_cost(cost);
            state.last = arcan_frametime();
            if (post) |p| p();
            return;
        }
        const vidp: [*]u8 = @ptrCast(vidp_raw);
        const ww: usize = state.canvasw;
        const hh: usize = state.canvash;
        const row_bytes = ww * 4;
        const pitch: usize = lwa_disp[0].conn.pitch;
        for (0..hh) |y| {
            // The offscreen pass on this path renders top-down already (no
            // negative-viewport flip on macOS) — copy rows straight; a row
            // reversal here shows the nested desktop upside-down.
            const src_off = y * row_bytes;
            const dst_off = y * pitch * 4;
            @memcpy(vidp[dst_off .. dst_off + row_bytes], pixels[src_off .. src_off + row_bytes]);
        }
        _ = arcan_shmif_signal(&lwa_disp[0].conn, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
        lwa_disp[0].pending = arcan_timemillis();
    } else {
        // readPixels returned null — no frame to send
    }

    arcan_conductor_deadline(4);
    arcan_bench_register_cost(cost);
    state.last = arcan_frametime();
    if (post) |p| p();
}

// Shutdown / Recovery / Misc

export fn platform_video_shutdown() void {
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();
    if (state.mode == .lwa) {
        if (state.env) |env| {
            vk_offscreen.destroyOffscreen(env, &state.offscreen);
            env.deinit();
            state.env = null;
        }
        for (0..MAX_LWA_DISPLAYS) |i| {
            if (lwa_disp[i].conn.addr != null) {
                arcan_shmif_drop(&lwa_disp[i].conn);
                lwa_disp[i] = .{ .id = i };
            }
        }
    } else {
        if (state.env) |env| {
            vk_wsi.destroySwapchain(env, &state.swapchain);
            env.deinit();
            state.env = null;
        }
        if (state.xcb_window != null) {
            vk_xcb.destroyXcbWindow(&state.xcb_window.?);
            state.xcb_window = null;
        }
        if (state.drm_display_fd >= 0) {
            std.posix.close(state.drm_display_fd);
            state.drm_display_fd = -1;
        }
    }
}

export fn platform_video_recovery() void {
    if (state.mode == .lwa) {
        var ev: arcan_event = undefined; @memset(std.mem.asBytes(&ev), 0);
        ev.setCategory(EVENT_VIDEO);
        ev.getVid().*.kind = EVENT_VIDEO_DISPLAY_ADDED;
        _ = arcan_event_enqueue(arcan_event_defaultctx(), &ev);
    }
}

export fn platform_video_prepare_external() void {}
export fn platform_video_restore_external() void {}

export fn platform_video_reset(id: c_int, swap: c_int) void {
    _ = id;
    _ = swap;
}

export fn platform_video_minimize() void {}

const display_envopts = [_:null]?[*:0]const u8{
    "ARCAN_VIDEO_VK_VALIDATION=1",
    "enable Vulkan validation layers",
    null,
};

const lwa_envopts = [_:null]?[*:0]const u8{
    "ARCAN_CONNPATH=/path/to/socket",
    "shmif connection path to parent arcan",
    null,
};

export fn platform_video_envopts() [*]const ?[*:0]const u8 {
    return switch (state.mode) {
        .lwa => &lwa_envopts,
        .xcb, .khr_display, .gbm_kms => &display_envopts,
    };
}

export fn platform_video_gfxsym(sym: ?[*:0]const u8) ?*anyopaque {
    _ = sym;
    return null;
}

// DMA-BUF Import (shared across all modes)

export fn platform_video_map_handle(dst: ?*struct_agp_vstore, handle: i64) bool {
    const s = dst orelse return false;
    const fd: c_int = @intCast(handle & 0xFFFFFFFF);
    if (fd < 0) return false;

    const w: u32 = @intCast(s.w);
    const h: u32 = @intCast(s.h);
    const stride: u64 = @as(u64, w) * @sizeOf(av_pixel);

    arcan_warning("[map_handle] fd=%d glid=%u %ux%u stride=%lu\n", fd, s.vinf.text.glid, w, h, stride);

    if (s.vinf.text.glid != 0) {
        // In-place update: reuse slot + descriptor set
        if (vk_env_update_dmabuf_texture(s.vinf.text.glid, fd, w, h, stride, 0, 0x34325258, 0)) {
            arcan_warning("[map_handle] update OK glid=%u\n", s.vinf.text.glid);
            return true;
        }
        // Fallback: destroy + reimport
        arcan_warning("[map_handle] update FAILED glid=%u, reimporting\n", s.vinf.text.glid);
        vk_env_destroy_texture(s.vinf.text.glid);
        s.vinf.text.glid = 0;
    }

    const glid = vk_env_import_dmabuf_texture(fd, w, h, stride, 0, 0x34325258, 0);
    if (glid == 0) {
        arcan_warning("[map_handle] import FAILED fd=%d %ux%u\n", fd, w, h);
        return false;
    }

    arcan_warning("[map_handle] import OK glid=%u fd=%d %ux%u\n", glid, fd, w, h);
    s.vinf.text.glid = glid;
    s.vinf.text.s_raw = 0;
    s.bpp = @sizeOf(av_pixel);
    s.txmapped = TXSTATE_TEX2D;
    if (s.refcount == 0) s.refcount = 1;
    return true;
}

export fn platform_video_map_buffer(
    vs: ?*struct_agp_vstore,
    planes: ?*struct_agp_buffer_plane,
    n: usize,
) bool {
    const s = vs orelse return false;
    const p: [*]struct_agp_buffer_plane = @ptrCast(planes orelse return false);
    if (n == 0) return false;

    const plane = &p[0];
    const pw: u32 = @intCast(plane.w);
    const ph: u32 = @intCast(plane.h);
    const eff_w = if (pw > 0) pw else @as(u32, @intCast(s.w));
    const eff_h = if (ph > 0) ph else @as(u32, @intCast(s.h));
    const modifier: u64 = (@as(u64, plane.unnamed_0.gbm.mod_hi) << 32) | @as(u64, plane.unnamed_0.gbm.mod_lo);

    arcan_warning("[map_buffer] fd=%d glid=%u %ux%u fmt=0x%x mod=0x%lx\n", plane.fd, s.vinf.text.glid, eff_w, eff_h, plane.unnamed_0.gbm.format, modifier);

    if (s.vinf.text.glid != 0) {
        // In-place update: reuse slot + descriptor set
        if (vk_env_update_dmabuf_texture(s.vinf.text.glid, plane.fd, eff_w, eff_h, plane.unnamed_0.gbm.stride, plane.unnamed_0.gbm.offset, plane.unnamed_0.gbm.format, modifier)) {
            arcan_warning("[map_buffer] update OK glid=%u\n", s.vinf.text.glid);
            if (pw > 0) s.w = @intCast(pw);
            if (ph > 0) s.h = @intCast(ph);
            return true;
        }
        // Fallback: destroy + reimport
        arcan_warning("[map_buffer] update FAILED glid=%u, reimporting\n", s.vinf.text.glid);
        vk_env_destroy_texture(s.vinf.text.glid);
        s.vinf.text.glid = 0;
    }

    const glid = vk_env_import_dmabuf_texture(plane.fd, eff_w, eff_h, plane.unnamed_0.gbm.stride, plane.unnamed_0.gbm.offset, plane.unnamed_0.gbm.format, modifier);
    if (glid == 0) {
        arcan_warning("[map_buffer] import FAILED fd=%d %ux%u\n", plane.fd, eff_w, eff_h);
        return false;
    }

    arcan_warning("[map_buffer] import OK glid=%u fd=%d %ux%u\n", glid, plane.fd, eff_w, eff_h);
    s.vinf.text.glid = glid;
    s.vinf.text.s_raw = 0;
    if (pw > 0) s.w = @intCast(pw);
    if (ph > 0) s.h = @intCast(ph);
    s.bpp = @sizeOf(av_pixel);
    s.txmapped = TXSTATE_TEX2D;
    if (s.refcount == 0) s.refcount = 1;
    return true;
}

export fn platform_video_export_vstore(vs: ?*struct_agp_vstore, planes: ?*struct_agp_buffer_plane, n: usize) usize {
    _ = vs;
    _ = planes;
    _ = n;
    return 0;
}

export fn platform_video_auth(cardn: c_int, token: c_uint) bool {
    _ = cardn;
    _ = token;
    return false;
}

export fn platform_video_cardhandle(cardn: c_int, buffer_method: ?*c_int, metadata_sz: ?*usize, metadata: ?*?[*]u8) c_int {
    _ = cardn;
    _ = buffer_method;
    _ = metadata_sz;
    _ = metadata;
    return -1;
}

// Display management (mode-dependent)

export fn platform_video_decay() usize {
    if (state.mode == .lwa) {
        var decay: usize = 0;
        for (0..MAX_LWA_DISPLAYS) |i| {
            if (lwa_disp[i].decay > decay) decay = lwa_disp[i].decay;
            lwa_disp[i].decay = 0;
        }
        return decay;
    }
    return 0;
}

export fn platform_video_displays(dids: ?*platform_display_id, lim: ?*usize) usize {
    if (state.mode == .lwa) {
        var rv: usize = 0;
        for (0..MAX_LWA_DISPLAYS) |i| {
            if (lwa_disp[i].conn.unnamed_0.vidp == null) continue;
            if (dids != null and lim != null and lim.?.* < rv) {
                dids.?.* = @intCast(lwa_disp[i].id);
            }
            rv += 1;
        }
        if (lim) |l| l.* = MAX_LWA_DISPLAYS;
        return rv;
    }
    // Display mode: single display
    if (dids != null and lim != null and lim.?.* > 0) {
        dids.?.* = 0;
    }
    if (lim) |l| l.* = 1;
    return 1;
}

export fn platform_video_dpms(did: platform_display_id, dpms_state: c_uint) c_uint {
    if (state.mode == .lwa) {
        if (did >= MAX_LWA_DISPLAYS or !lwa_disp[did].mapped) return ADPMS_IGNORE;
        if (dpms_state == ADPMS_IGNORE) return lwa_disp[did].dpms;
        lwa_disp[did].dpms = dpms_state;
        return dpms_state;
    }

    // MAY-201: forward DPMS state changes to KMS so durian's
    // display_all_mode(DISPLAY_ON) actually pins the connector ON at
    // the kernel and prevents the TV from being told it can sleep.
    // ADPMS_IGNORE = read-only query; we don't track stored state for
    // the KMS branch yet — just report ON since that's the only state
    // we ever set. ADPMS_ON/STANDBY/SUSPEND/OFF map 1:1 onto the
    // kernel DPMS values 0/1/2/3.
    if (dpms_state == ADPMS_IGNORE) return ADPMS_ON;
    if (state.gbm_swapchain.drm_fd >= 0) {
        _ = vk_gbm_kms.setDpms(&state.gbm_swapchain, dpms_state);
    }
    return dpms_state;
}

export fn platform_video_query_displays() void {}

export fn platform_video_display_edid(did: platform_display_id, out: ?*?[*:0]u8, sz: ?*usize) bool {
    _ = did;
    if (out) |o| o.* = null;
    if (sz) |s| s.* = 0;
    return false;
}

export fn platform_video_set_display_gamma(did: platform_display_id, n_ramps: usize, r: ?[*]u16, g: ?[*]u16, b: ?[*]u16) bool {
    _ = did;
    _ = n_ramps;
    _ = r;
    _ = g;
    _ = b;
    return false;
}

export fn platform_video_get_display_gamma(did: platform_display_id, n_ramps: ?*usize, outb: ?*?[*]u16) bool {
    _ = did;
    _ = n_ramps;
    _ = outb;
    return false;
}

export fn platform_video_specify_mode(disp_id: platform_display_id, mode: struct_monitor_mode) bool {
    if (state.mode == .lwa) {
        if (disp_id >= MAX_LWA_DISPLAYS or lwa_disp[disp_id].conn.addr == null) return false;
        const ok = arcan_shmif_resize(&lwa_disp[disp_id].conn, @intCast(mode.width), @intCast(mode.height));
        if (!ok) return false;
        if (disp_id == 0) {
            if (state.env) |env| {
                const w: u16 = @intCast(mode.width);
                const h: u16 = @intCast(mode.height);
                vk_offscreen.resize(env, &state.offscreen, w, h) catch return false;
                state.canvasw = w;
                state.canvash = h;
                state.draww = @floatFromInt(w);
                state.drawh = @floatFromInt(h);
                buildOrtho(&state.projection, 0, @floatFromInt(w), @floatFromInt(h), 0, 0, 1);
                vk_env_set_swapchain_extent(w, h);
                vk_shared_set_screen_size(w, h);
            }
        }
        return true;
    }
    // Display mode
    if (disp_id != 0) return false;
    if (mode.width == 0 or mode.height == 0) return false;
    if (mode.width == state.canvasw and mode.height == state.canvash) return true;
    state.canvasw = @intCast(mode.width);
    state.canvash = @intCast(mode.height);
    state.draww = @floatFromInt(state.canvasw);
    state.drawh = @floatFromInt(state.canvash);
    buildOrtho(&state.projection, 0, state.draww, state.drawh, 0, 0, 1);
    return true;
}

export fn platform_video_set_mode(disp_id: platform_display_id, mode_id: platform_mode_id, opts: struct_platform_mode_opts) bool {
    _ = opts;
    return disp_id == 0 and mode_id == 0;
}

export fn platform_video_query_modes(id: platform_display_id, count: ?*usize) ?*struct_monitor_mode {
    _ = id;
    const S = struct {
        var mode_val: struct_monitor_mode = undefined;
    };
    S.mode_val = std.mem.zeroes(struct_monitor_mode);
    S.mode_val.width = state.canvasw;
    S.mode_val.height = state.canvash;
    S.mode_val.depth = @sizeOf(av_pixel) * 8;
    S.mode_val.refresh = if (state.mode == .lwa) 60 else @intCast(state.refresh);
    if (state.mode == .lwa) S.mode_val.dynamic = true;
    if (state.mode != .lwa) {
        S.mode_val.phy_width = state.phy_width_mm;
        S.mode_val.phy_height = state.phy_height_mm;
    }
    if (count) |cnt| cnt.* = 1;
    return &S.mode_val;
}

export fn platform_video_dimensions() struct_monitor_mode {
    var res = std.mem.zeroes(struct_monitor_mode);
    res.width = state.canvasw;
    res.height = state.canvash;
    if (state.mode == .lwa) {
        if (lwa_disp[0].ppcm > 0) {
            res.phy_width = @intFromFloat(@as(f32, @floatFromInt(state.canvasw)) / lwa_disp[0].ppcm * 10.0);
            res.phy_height = @intFromFloat(@as(f32, @floatFromInt(state.canvash)) / lwa_disp[0].ppcm * 10.0);
        }
    } else {
        res.phy_width = state.phy_width_mm;
        res.phy_height = state.phy_height_mm;
    }
    return res;
}

export fn platform_video_map_display(vid: arcan_vobj_id, id: platform_display_id, hint: c_uint) bool {
    if (state.mode == .lwa) {
        var cfg = std.mem.zeroes(struct_display_layer_cfg);
        cfg.opacity = 1.0;
        cfg.hint = hint;
        return platform_video_map_display_layer(vid, id, 0, cfg) >= 0;
    }
    return false;
}

export fn platform_video_map_display_layer(
    vid: arcan_vobj_id,
    id: platform_display_id,
    layer_index: usize,
    cfg: struct_display_layer_cfg,
) isize {
    // XCB/display mode: route the mapped vid for platform composite
    if (state.mode != .lwa) {
        if (id == 0 and layer_index == 0) {
            state.vid = vid;
        }
        return 0;
    }
    if (state.mode == .lwa) {
        _ = cfg;
        if (id >= MAX_LWA_DISPLAYS) return -1;
        if (lwa_disp[id].conn.addr == null) return -1;

        if (lwa_disp[id].vstore) |vs| {
            if (vs != arcan_vint_world()) {
                arcan_vint_drop_vstore(vs);
                lwa_disp[id].vstore = null;
            }
        }
        lwa_disp[id].mapped = false;

        if (vid == ARCAN_VIDEO_WORLDID) {
            if (arcan_vint_world() == null) return -1;
            lwa_disp[id].conn.hints = 0; // Vulkan: upper-left origin, no ORIGO_LL
            lwa_disp[id].vstore = arcan_vint_world();
            lwa_disp[id].mapped = true;
            return 0;
        } else if (vid == ARCAN_EID) {
            return 0;
        } else {
            const vobj_ptr = arcan_video_getobject(vid);
            if (vobj_ptr == null) return -1;
            const vo = vobj_ptr.?;
            if (vo.*.vstore == null) return -1;
            lwa_disp[id].conn.hints = 0;
            lwa_disp[id].vstore = vo.*.vstore;
        }

        if (layer_index != 0) return -1;
        lwa_disp[id].vstore.?.*.refcount += 1;
        lwa_disp[id].mapped = true;
        return 0;
    }
    // Display mode
    if (id != 0 or layer_index != 0) return -1;
    return 0;
}

export fn platform_video_invalidate_map(vstore: ?*struct_agp_vstore, region: struct_agp_region) void {
    _ = vstore;
    _ = region;
}

export fn platform_video_display_id(id: platform_display_id, mode_id: platform_mode_id, mode: struct_monitor_mode) bool {
    _ = id;
    _ = mode_id;
    _ = mode;
    return false;
}

export fn platform_video_capstr() [*:0]const u8 {
    return switch (state.mode) {
        .lwa => "Video Platform (Vulkan LWA)",
        .xcb => "Video Platform (Vulkan XCB)",
        .khr_display => "Video Platform (Vulkan VK_KHR_display)",
        .gbm_kms => "Video Platform (Vulkan GBM+KMS direct)",
    };
}

// ══════════════════════════════════════════════════════════════════
// LWA-specific exports
// ══════════════════════════════════════════════════════════════════

export fn platform_lwa_targetevent(tgt: ?*anyopaque, ev: *arcan_event) bool {
    if (state.mode != .lwa) return false;
    if (tgt == null) {
        return arcan_shmif_enqueue(&lwa_disp[0].conn, ev) != 0;
    }
    const con: *struct_arcan_shmif_cont = @ptrCast(@alignCast(tgt));
    return arcan_shmif_enqueue(con, ev) != 0;
}

export fn platform_lwa_allocbind_feed(
    ctx: ?*anyopaque,
    rtgt: arcan_vobj_id,
    seg_type: c_uint,
    cbtag: usize,
) bool {
    _ = ctx;
    _ = rtgt;
    _ = seg_type;
    _ = cbtag;
    return false;
}

export fn arcan_lwa_ffunc(
    cmd: c_uint,
    buf: ?[*]u32,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state_arg: vfunc_state,
    srcid: arcan_vobj_id,
) c_uint {
    _ = buf;
    _ = buf_sz;
    _ = width;
    _ = height;
    _ = mode;
    _ = state_arg;
    _ = srcid;
    if (cmd == FFUNC_DESTROY) return 0;
    if (cmd == FFUNC_POLL) return FRV_NOFRAME;
    if (cmd == FFUNC_READBACK) return FRV_NOFRAME;
    return FRV_NOFRAME;
}

// LWA shmif event processing

fn lwaEventProcessDisp(ctx: ?*struct_arcan_evctx, d: *LwaDisplay, did: usize) void {
    if (d.conn.addr == null) return;

    var ev: arcan_event = undefined;
    var rv: c_int = undefined;
    while (true) {
        rv = arcan_shmif_poll(&d.conn, &ev);
        if (rv != 1) break;

        if (ev.data[ARCAN_EVENT_CATEGORY_OFFSET] == EVENT_TARGET) {
            const kind = ev.getTgt().kind;

            if (kind == TARGET_COMMAND_STEPFRAME) {
                arcan_conductor_deadline(0);
                d.pending = 0;
            } else if (kind == TARGET_COMMAND_EXIT) {
                if (did == 0) {
                    var exit_ev: arcan_event = undefined; @memset(std.mem.asBytes(&exit_ev), 0);
                    exit_ev.setCategory(EVENT_SYSTEM);
                    exit_ev.getSys().*.kind = EVENT_SYSTEM_EXIT;
                    d.conn.unnamed_0.vidp = null;
                    _ = arcan_event_enqueue(ctx, &exit_ev);
                } else {
                    var rem_ev: arcan_event = undefined; @memset(std.mem.asBytes(&rem_ev), 0);
                    rem_ev.setCategory(EVENT_VIDEO);
                    rem_ev.getVid().*.kind = EVENT_VIDEO_DISPLAY_REMOVED;
                    rem_ev.getVid().*.unnamed_0.unnamed_0.displayid = @intCast(d.id);
                    _ = arcan_event_enqueue(ctx, &rem_ev);
                    arcan_shmif_drop(&d.conn);
                    if (d.vstore) |vs| {
                        arcan_vint_drop_vstore(vs);
                        d.vstore = null;
                    }
                    d.* = .{ .id = did };
                }
                return;
            } else if (kind == TARGET_COMMAND_DISPLAYHINT) {
                const tgt = ev.getTgt();
                var update = false;
                var w: usize = d.conn.w;
                var h: usize = d.conn.h;

                if (tgt.ioevs[0].iv > 0 and tgt.ioevs[1].iv > 0) {
                    const nw: usize = @intCast(tgt.ioevs[0].iv);
                    const nh: usize = @intCast(tgt.ioevs[1].iv);
                    update = nw != d.conn.w or nh != d.conn.h;
                    w = nw;
                    h = nh;
                }

                const flags_val = tgt.ioevs[2].iv;
                if (flags_val & 128 == 0) {
                    d.visible = (flags_val & 2) == 0;
                    d.focused = (flags_val & 4) == 0;
                }

                if (tgt.ioevs[4].fv > 0 and tgt.ioevs[4].fv != d.ppcm) {
                    update = true;
                    d.ppcm = tgt.ioevs[4].fv;
                }

                if (update) {
                    var disp_ev: arcan_event = undefined; @memset(std.mem.asBytes(&disp_ev), 0);
                    disp_ev.setCategory(EVENT_VIDEO);
                    disp_ev.getVid().*.kind = EVENT_VIDEO_DISPLAY_RESET;
                    disp_ev.getVid().*.source = -1;
                    disp_ev.getVid().*.unnamed_0.unnamed_0.displayid = @intCast(d.id);
                    disp_ev.getVid().*.unnamed_0.unnamed_0.width = @intCast(w);
                    disp_ev.getVid().*.unnamed_0.unnamed_0.height = @intCast(h);
                    disp_ev.getVid().*.unnamed_0.unnamed_0.flags = flags_val;
                    disp_ev.getVid().*.unnamed_0.unnamed_0.vppcm = d.ppcm;
                    _ = arcan_event_denqueue(ctx, &disp_ev);
                }
            } else if (kind == TARGET_COMMAND_FONTHINT) {
                const tgt = ev.getTgt();
                var newfd: c_int = -1;
                var font_sz: c_int = 0;
                const hint_val = tgt.ioevs[3].iv;

                if (tgt.ioevs[1].iv == 1 and tgt.ioevs[0].iv != -1) {
                    newfd = std.c.dup(tgt.ioevs[0].iv);
                }
                if (tgt.ioevs[2].fv > 0) {
                    font_sz = @intFromFloat(@ceil(d.ppcm * tgt.ioevs[2].fv));
                }
                _ = arcan_video_defaultfont("arcan-default", newfd, @intCast(font_sz), hint_val, tgt.ioevs[4].iv != 0);

                var font_ev: arcan_event = undefined; @memset(std.mem.asBytes(&font_ev), 0);
                font_ev.setCategory(EVENT_VIDEO);
                font_ev.getVid().*.kind = EVENT_VIDEO_DISPLAY_RESET;
                font_ev.getVid().*.source = -2;
                font_ev.getVid().*.unnamed_0.unnamed_0.displayid = @intCast(d.id);
                font_ev.getVid().*.unnamed_0.unnamed_0.vppcm = tgt.ioevs[2].fv;
                _ = arcan_event_enqueue(ctx, &font_ev);
            } else if (kind == TARGET_COMMAND_RESET) {
                const tgt = ev.getTgt();
                if (tgt.ioevs[0].iv == 0 or tgt.ioevs[0].iv == 1) {
                    var reset_ev: arcan_event = undefined; @memset(std.mem.asBytes(&reset_ev), 0);
                    reset_ev.setCategory(EVENT_SYSTEM);
                    reset_ev.getSys().*.kind = EVENT_SYSTEM_EXIT;
                    _ = arcan_event_enqueue(ctx, &reset_ev);
                } else {
                    lwa_disp[0].decay = 4;
                }
            } else if (kind == TARGET_COMMAND_NEWSEGMENT) {
                lwaMapWindow(&d.conn, ctx, ev.getTgt().*.ioevs[2].iv, did);
            } else {
                if (did == 0) {
                    arcan_lwa_subseg_ev(main_lua_context, ARCAN_VIDEO_WORLDID, 0, &ev);
                }
            }
        } else {
            _ = arcan_event_enqueue(ctx, &ev);
        }
    }

    if (rv == -1 and did == 0) {
        var exit_ev: arcan_event = undefined; @memset(std.mem.asBytes(&exit_ev), 0);
        exit_ev.setCategory(EVENT_SYSTEM);
        exit_ev.getSys().*.kind = EVENT_SYSTEM_EXIT;
        _ = arcan_event_enqueue(ctx, &exit_ev);
    }
}

fn lwaMapWindow(conn: *struct_arcan_shmif_cont, ctx: ?*struct_arcan_evctx, kind: c_int, _: usize) void {
    if (kind != SEGID_MEDIA) return;

    var slot: ?usize = null;
    for (0..MAX_LWA_DISPLAYS) |i| {
        if (lwa_disp[i].conn.addr == null) {
            slot = i;
            break;
        }
    }
    const i = slot orelse return;

    lwa_disp[i].conn = arcan_shmif_acquire(conn, null, SEGID_LWA, SHMIF_DISABLE_GUARD);
    lwa_disp[i].ppcm = ARCAN_SHMPAGE_DEFAULT_PPCM;
    lwa_disp[i].dpms = ADPMS_ON;
    lwa_disp[i].visible = true;

    var ev: arcan_event = undefined; @memset(std.mem.asBytes(&ev), 0);
    ev.setCategory(EVENT_VIDEO);
    ev.getVid().*.kind = EVENT_VIDEO_DISPLAY_ADDED;
    ev.getVid().*.source = -1;
    ev.getVid().*.unnamed_0.unnamed_0.displayid = @intCast(i);
    ev.getVid().*.unnamed_0.unnamed_0.width = @intCast(conn.w);
    ev.getVid().*.unnamed_0.unnamed_0.height = @intCast(conn.h);
    _ = arcan_event_enqueue(ctx, &ev);
}

// ══════════════════════════════════════════════════════════════════
// Event Layer Dispatch (wraps evdev for display, stubs for LWA)
// ══════════════════════════════════════════════════════════════════

export fn platform_event_preinit() void {
    if (state.mode != .lwa) evdev_event_preinit();
}

export fn platform_event_init(ctx: ?*struct_arcan_evctx) void {
    if (state.mode != .lwa) evdev_event_init(ctx);
}

export fn platform_event_process(ctx: ?*struct_arcan_evctx) void {
    if (state.mode == .lwa) {
        state.signal_pending = false;
        for (0..MAX_LWA_DISPLAYS) |i| {
            lwaEventProcessDisp(ctx, &lwa_disp[i], i);
            if (lwa_disp[i].pending > 0 and arcan_timemillis() -| lwa_disp[i].pending < 64)
                state.signal_pending = true;
        }
    } else {
        evdev_event_process(ctx);
    }
}

export fn platform_event_deinit(ctx: ?*struct_arcan_evctx) void {
    if (state.mode != .lwa) evdev_event_deinit(ctx);
}

export fn platform_event_reset(ctx: ?*struct_arcan_evctx) void {
    if (state.mode != .lwa) evdev_event_reset(ctx);
}

export fn platform_event_analogstate(
    devid: c_int,
    axisid: c_int,
    lower_bound: ?*c_int,
    upper_bound: ?*c_int,
    deadzone: ?*c_int,
    kernel_size: ?*c_int,
    mode: ?*c_int,
) c_int {
    if (state.mode == .lwa) return ARCAN_ERRC_NO_SUCH_OBJECT;
    return evdev_event_analogstate(devid, axisid, lower_bound, upper_bound, deadzone, kernel_size, mode);
}

export fn platform_event_analogall(enable: bool, mouse: bool) void {
    if (state.mode != .lwa) evdev_event_analogall(enable, mouse);
}

export fn platform_event_analogfilter(
    devid: c_int,
    axisid: c_int,
    lower_bound: c_int,
    upper_bound: c_int,
    deadzone: c_int,
    buffer_sz: c_int,
    kind: c_int,
) void {
    if (state.mode != .lwa) evdev_event_analogfilter(devid, axisid, lower_bound, upper_bound, deadzone, buffer_sz, kind);
}

export fn platform_event_keyrepeat(ctx: ?*struct_arcan_evctx, period: ?*c_int, delay: ?*c_int) void {
    if (state.mode == .lwa) {
        if (period) |p| p.* = 0;
        if (delay) |d| d.* = 0;
    } else {
        evdev_event_keyrepeat(ctx, period, delay);
    }
}

export fn platform_event_samplebase(devid: c_int, xyz: ?[*]f32) void {
    if (state.mode != .lwa) evdev_event_samplebase(devid, xyz);
}

export fn platform_event_devlabel(devid: c_int) [*:0]const u8 {
    if (state.mode == .lwa) return "no device";
    // evdev_event_devlabel returns [*c]const u8 (nullable). Returns null
    // when lookup_devnode(devid) misses — happens during DEVICE_ADDED
    // event enqueue if the node-registration order isn't strictly before
    // the event-emit order (e.g. system devices that got_device handles
    // but didn't fully slot). Guard the @ptrCast so durian doesn't panic
    // on rescan.
    const label = evdev_event_devlabel(devid);
    if (label == null) return "unknown";
    return @ptrCast(label);
}

export fn platform_event_translation(
    devid: c_int,
    action: c_int,
    names: ?*?[*:0]const u8,
    err: ?*?[*:0]const u8,
) c_int {
    if (state.mode == .lwa) {
        if (err) |e| e.* = "Not Supported";
        return -1;
    }
    return evdev_event_translation(devid, action, names, err);
}

export fn platform_event_device_request(space: c_int, path: ?[*:0]const u8) c_int {
    if (state.mode == .lwa) return -1;
    return evdev_event_device_request(space, path);
}

export fn platform_event_rescan_idev(ctx: ?*struct_arcan_evctx) void {
    if (state.mode != .lwa) evdev_event_rescan_idev(ctx);
}

export fn platform_event_capabilities(out: ?*[*c]const u8) c_uint {
    if (state.mode == .lwa) {
        if (out) |o| o.* = @ptrCast("vk-lwa");
        return ACAP_TRANSLATED | ACAP_MOUSE | ACAP_TOUCH | ACAP_POSITION | ACAP_ORIENTATION;
    }
    return evdev_event_capabilities(out);
}

const lwa_event_envopts = [_:null]?[*:0]const u8{null};

export fn platform_event_envopts() [*]const ?[*:0]const u8 {
    if (state.mode == .lwa) return &lwa_event_envopts;
    return @ptrCast(evdev_event_envopts());
}

export fn platform_device_lock(devind: c_int, lock_state: bool) void {
    if (state.mode != .lwa) evdev_device_lock(devind, lock_state);
}

export fn platform_key_repeat(ctx: ?*struct_arcan_evctx, rate: c_uint) void {
    _ = ctx;
    _ = rate;
}
