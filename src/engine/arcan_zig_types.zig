// Shared Zig type definitions for arcan engine/platform/TUI ported modules.
// Manually translated from C headers — no @cImport needed.
// All types are extern struct/union/enum matching C ABI layout.

const std = @import("std");

// Basic type aliases
pub const arcan_errc = i8;
pub const arcan_aobj_id = c_int;
pub const arcan_vobj_id = i64;
pub const shmif_pixel = u32;
pub const shmif_asample = i16;

// Error codes
pub const ARCAN_OK: arcan_errc = 0;
pub const ARCAN_ERRC_NO_SUCH_OBJECT: arcan_errc = -7;
pub const ARCAN_ERRC_BAD_ARGUMENT: arcan_errc = -5;
pub const ARCAN_ERRC_NOAUDIO: arcan_errc = -11;

// Namespace enum (bitmask)
pub const RESOURCE_APPL_TEMP: c_int = 1;
pub const RESOURCE_APPL: c_int = 2;
pub const RESOURCE_APPL_SHARED: c_int = 4;
pub const RESOURCE_APPL_STATE: c_int = 8;
pub const RESOURCE_SYS_APPLBASE: c_int = 16;
pub const RESOURCE_SYS_APPLSTORE: c_int = 32;
pub const RESOURCE_SYS_APPLSTATE: c_int = 64;
pub const RESOURCE_SYS_FONT: c_int = 128;
pub const RESOURCE_SYS_BINS: c_int = 256;
pub const RESOURCE_SYS_LIBS: c_int = 512;
pub const RESOURCE_SYS_DEBUG: c_int = 1024;
pub const RESOURCE_SYS_SCRIPTS: c_int = 2048;
pub const RESOURCE_NS_USER: c_int = 4096;
pub const RESOURCE_SYS_ENDM: c_int = 2048;

// Event categories
pub const EVENT_SYSTEM: u8 = 1;
pub const EVENT_IO: u8 = 2;
pub const EVENT_VIDEO: u8 = 4;
pub const EVENT_AUDIO: u8 = 8;
pub const EVENT_TARGET: u8 = 16;
pub const EVENT_FSRV: u8 = 32;
pub const EVENT_EXTERNAL: u8 = 64;

// Segment IDs
pub const SEGID_TUI: c_int = 24;

// Target commands (arcan_tgtevent.kind)
pub const TARGET_COMMAND_EXIT: c_int = 1;
pub const TARGET_COMMAND_MESSAGE: c_int = 17;

// External event kinds
pub const EVENT_EXTERNAL_MESSAGE: c_int = 0;
pub const EVENT_EXTERNAL_LABELHINT: c_int = 15;
pub const EVENT_EXTERNAL_SEGREQ: c_int = 10;

// IO device kinds
pub const EVENT_IDEVKIND_KEYBOARD: c_int = 1;
pub const EVENT_IDEVKIND_MOUSE: c_int = 2;
pub const EVENT_IDEVKIND_GAMEDEV: c_int = 4;

// IO data types
pub const EVENT_IDATATYPE_ANALOG: c_int = 1;
pub const EVENT_IDATATYPE_DIGITAL: c_int = 2;
pub const EVENT_IDATATYPE_TRANSLATED: c_int = 4;
pub const EVENT_IDATATYPE_TOUCH: c_int = 8;
pub const EVENT_IDATATYPE_EYES: c_int = 16;

// IO flags
pub const ARCAN_IOFL_GESTURE: u8 = 1;
pub const ARCAN_IOFL_ENTER: u8 = 2;
pub const ARCAN_IOFL_LEAVE: u8 = 4;

// Key modifiers (ARKMOD)
pub const ARKMOD_NONE: c_int = 0x0000;
pub const ARKMOD_LSHIFT: c_int = 0x0001;
pub const ARKMOD_RSHIFT: c_int = 0x0002;
pub const ARKMOD_LCTRL: c_int = 0x0040;
pub const ARKMOD_RCTRL: c_int = 0x0080;
pub const ARKMOD_LALT: c_int = 0x0100;
pub const ARKMOD_RALT: c_int = 0x0200;
pub const ARKMOD_LMETA: c_int = 0x0400;
pub const ARKMOD_RMETA: c_int = 0x0800;

// TUI modifier masks (TUIM)
pub const TUIM_NONE: u16 = 0x0000;
pub const TUIM_LSHIFT: u16 = 0x0001;
pub const TUIM_RSHIFT: u16 = 0x0002;
pub const TUIM_SHIFT: u16 = 0x0003;
pub const TUIM_LCTRL: u16 = 0x0040;
pub const TUIM_RCTRL: u16 = 0x0080;
pub const TUIM_CTRL: u16 = 0x00c0;
pub const TUIM_LALT: u16 = 0x0100;
pub const TUIM_RALT: u16 = 0x0200;
pub const TUIM_ALT: u16 = 0x0300;
pub const TUIM_LMETA: u16 = 0x0400;
pub const TUIM_RMETA: u16 = 0x0800;
pub const TUIM_META: u16 = 0x0c00;
pub const TUIM_REPEAT: u16 = 0x8000;

// Key symbols (TUIK)
pub const TUIK_UP: u32 = 273;
pub const TUIK_DOWN: u32 = 274;
pub const TUIK_PAGEUP: u32 = 280;
pub const TUIK_PAGEDOWN: u32 = 281;
pub const TUIK_RSHIFT: u32 = 303;
pub const TUIK_LSHIFT: u32 = 304;
pub const TUIK_RCTRL: u32 = 305;
pub const TUIK_LCTRL: u32 = 306;
pub const TUIK_RALT: u32 = 307;
pub const TUIK_LALT: u32 = 308;
pub const TUIK_RMETA: u32 = 309;
pub const TUIK_LMETA: u32 = 310;
pub const TUIK_COMPOSE: u32 = 314;
pub const TUIK_PRINT: u32 = 316;

// Mouse buttons (TUIBTN)
pub const TUIBTN_LEFT: u16 = 1;
pub const TUIBTN_RIGHT: u16 = 2;
pub const TUIBTN_MIDDLE: u16 = 3;
pub const TUIBTN_WHEEL_UP: u16 = 4;
pub const TUIBTN_WHEEL_DOWN: u16 = 5;

// Constants
pub const ASHMIF_MSTATE_SZ = 32;
pub const TUI_COL_LIMIT = 36;

// arcan_shmif_region
pub const arcan_shmif_region = extern struct {
    x1: u16,
    x2: u16,
    y1: u16,
    y2: u16,
};

// arcan_ioevent_data (union)
pub const arcan_ioevent_data = extern union {
    digital: extern struct {
        active: u8,
    },
    analog: extern struct {
        gotrel: i8,
        nvalues: u8,
        axisval: [4]i16,
        active: u8,
    },
    touch: extern struct {
        active: u8,
        x: i16,
        y: i16,
        pressure: f32,
        size: f32,
        tilt_x: u16,
        tilt_y: u16,
        tool: u8,
    },
    eyes: extern struct {
        head_pos: [3]f32,
        head_ang: [3]f32,
        gaze_x1: f32,
        gaze_y1: f32,
        gaze_x2: f32,
        gaze_y2: f32,
        blink_left: u8,
        blink_right: u8,
        present: u8,
    },
    status: extern struct {
        action: u8,
        devkind: u8,
        devref: u16,
        domain: u8,
    },
    translated: extern struct {
        utf8: [5]u8,
        active: u8,
        scancode: u8,
        keysym: u32,
        modifiers: u16,
    },
};

// arcan_ioevent
pub const arcan_ioevent = extern struct {
    kind: c_int, // ARCAN_EVENT_IO
    devkind: c_int, // ARCAN_EVENT_IDEVKIND
    datatype: c_int, // ARCAN_EVENT_IDATATYPE
    label: [16]u8,
    flags: u8,
    devid: u16,
    subid: u16,
    dst: u32,
    pts: u64,
    input: arcan_ioevent_data,
};

// arcan_tgtevent
pub const arcan_tgtevent = extern struct {
    kind: c_int,
    ioevs: [8]extern union {
        uiv: u32,
        iv: i32,
        fv: f32,
        cv: [4]u8,
    },
    code: c_int,
    message: extern union {
        message: [78]u8,
        bmessage: [78]u8,
        timestamp: u64,
    },
};

// arcan_extevent
pub const arcan_extevent = extern struct {
    kind: c_int,
    source: i64,
    payload: extern union {
        message: extern struct {
            data: [78]u8,
            multipart: u8,
        },
        labelhint: extern struct {
            label: [16]u8,
            initial: u16,
            descr: [53]u8,
            vsym: [5]u8,
            subv: u16,
            idatatype: u8,
            modifiers: u16,
        },
        segreq: extern struct {
            id: u32,
            width: u16,
            height: u16,
            xofs: i16,
            yofs: i16,
            dir: u8,
            hints: u8,
            kind: c_int,
        },
        viewport: extern struct {
            x: i32,
            y: i32,
            w: u32,
            h: u32,
            parent: u32,
            border: [4]u8,
            edge: u8,
            order: i8,
            embedded: u8,
            invisible: u8,
            focus: u8,
            anchor_edge: u8,
            anchor_pos: u8,
            ext_id: u32,
        },
        clock: extern struct {
            rate: u32,
            dynamic: u8,
            once: u8,
            id: u32,
        },
        registr: extern struct {
            title: [64]u8,
            kind: c_int,
            guid: [2]u64,
        },
        bchunk: extern struct {
            size_or_ns: u64,
            input: u8,
            hint: u8,
            stream: u8,
            extensions: [68]u8,
            identifier: u32,
        },
        stateinf: extern struct {
            size: u32,
            @"type": u32,
        },
        streamstat: extern struct {
            timestr: [9]u8,
            timelim: [9]u8,
            completion: f32,
            streaming: u8,
            frameno: u32,
            identifier: u32,
        },
        framestatus: extern struct {
            framenumber: u32,
            pts: u64,
            acquired: u64,
            fhint: f32,
        },
        content: extern struct {
            x_pos: f32,
            x_sz: f32,
            y_pos: f32,
            y_sz: f32,
            width: f32,
            height: f32,
            cell_w: u8,
            cell_h: u8,
            min_w: u32,
            min_h: u32,
            max_w: u32,
            max_h: u32,
        },
        coreopt: extern struct {
            index: u8,
            @"type": u8,
            data: [77]u8,
        },
        privdrop: extern struct {
            external: u8,
            sandboxed: u8,
            networked: u8,
        },
        inputmask: extern struct {
            device: u32,
            types: u32,
        },
        netstate: extern struct {
            name: [66]u8,
            space: u8,
            state: u8,
            @"type": u8,
            port: u16,
            ns: u16,
        },
        bstream: extern struct {
            stride: u32,
            format: u32,
            offset: u32,
            mod_hi: u32,
            mod_lo: u32,
            gpuid: u32,
            width: u32,
            height: u32,
            left: u8,
            flags: u8,
        },
        streaminf: extern struct {
            streamid: u8,
            datakind: u8,
            langid: [4]u8,
        },
    },
    frame_id: u64,
};

// arcan_sevent (system event)
pub const arcan_sevent = extern struct {
    kind: c_uint = 0,
    errcode: c_int = 0,
    unnamed_0: extern union {
        tagv: extern struct { hitag: u32 = 0, lotag: u32 = 0 },
        mesg: extern struct { dyneval_msg: ?[*:0]u8 = null },
        data: extern struct { fd: c_int = 0, _pad: [4]u8 = .{ 0, 0, 0, 0 }, otag: isize = 0 },
        message: [64]u8,
    } = .{ .message = std.mem.zeroes([64]u8) },
};

// arcan_vevent (video event) — internal engine only
pub const arcan_vevent = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    source: i64 = 0,
    unnamed_0: extern union {
        unnamed_0: extern struct {
            width: i16 = 0,
            height: i16 = 0,
            flags: c_int = 0,
            vppcm: f32 = 0,
            displayid: c_int = 0,
            ledctrl: c_int = 0,
            ledid: c_int = 0,
            cardid: c_int = 0,
        },
        slot: c_int,
    } = .{ .slot = 0 },
    data: isize = 0,
};

// arcan_aevent (audio event)
pub const arcan_aevent = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    source: i32 = 0,
    _pad_source: [4]u8 = .{ 0, 0, 0, 0 },
    unnamed_0: extern union {
        otag: isize,
        data: [*c]usize,
    } = .{ .otag = 0 },
};

// arcan_fsrvevent_full (frameserver event — sized for union)
pub const arcan_fsrvevent_full = extern struct {
    kind: c_int = 0,
    _pad_kind: [4]u8 = .{ 0, 0, 0, 0 },
    unnamed_0: extern union {
        unnamed_0: extern struct {
            audio: i32 = 0,
            _pad_audio: [4]u8 = .{ 0, 0, 0, 0 },
            width: usize = 0,
            height: usize = 0,
            xofs: usize = 0,
            yofs: usize = 0,
            fmt_fl: i8 = 0,
            _pad_fmt: [7]u8 = std.mem.zeroes([7]u8),
            pts: u64 = 0,
            counter: u64 = 0,
            message: [32]u8 = std.mem.zeroes([32]u8),
        },
        unnamed_1: extern struct {
            ident: [32]u8 = std.mem.zeroes([32]u8),
            descriptor: i64 = 0,
        },
        unnamed_2: extern struct {
            aproto: c_int = 0,
        },
        unnamed_3: extern struct {
            limb: c_uint = 0,
        },
        input: arcan_ioevent,
    } = .{ .unnamed_0 = .{} },
    video: i64 = 0,
    otag: isize = 0,
};

// arcan_event (128 bytes, union of category-tagged events + pad)
// Matches @cImport's 3-level unnamed_0 structure:
//   ev.unnamed_0.unnamed_0.category and ev.unnamed_0.unnamed_0.unnamed_0.vid/tgt/etc
pub const arcan_event = extern union {
    unnamed_0: extern struct {
        unnamed_0: extern struct {
            unnamed_0: extern union {
                io: arcan_ioevent,
                vid: arcan_vevent,
                aud: arcan_aevent,
                sys: arcan_sevent,
                tgt: arcan_tgtevent,
                ext: arcan_extevent,
                fsrv: arcan_fsrvevent_full,
            },
            category: u8,
        },
    },
    pad: [128]u8,

    const Self = @This();

    pub fn zeroes() Self {
        return .{ .pad = std.mem.zeroes([128]u8) };
    }

    // category is after the inner union. Verify at comptime.
    const CATEGORY_OFFSET = @offsetOf(@TypeOf(@as(Self, undefined).unnamed_0.unnamed_0), "category");

    pub fn getCategory(self: *const Self) u8 {
        return @as(*const [128]u8, @ptrCast(self))[CATEGORY_OFFSET];
    }

    pub fn setCategory(self: *Self, cat: u8) void {
        self.unnamed_0.unnamed_0.category = cat;
    }

    pub fn asExt(self: *Self) *arcan_extevent {
        return @ptrCast(self);
    }

    pub fn asExtConst(self: *const Self) *const arcan_extevent {
        return @ptrCast(self);
    }

    pub fn asTgt(self: *const Self) *const arcan_tgtevent {
        return @ptrCast(self);
    }

    pub fn asTgtMut(self: *Self) *arcan_tgtevent {
        return @ptrCast(self);
    }

    pub fn asIo(self: *const Self) *const arcan_ioevent {
        return @ptrCast(self);
    }

    pub fn asIoMut(self: *Self) *arcan_ioevent {
        return @ptrCast(self);
    }
};

// Verify size at compile time
comptime {
    if (@sizeOf(arcan_event) != 128)
        @compileError("arcan_event must be 128 bytes");
}

// arcan_shmif_cont
// Opaque by default — we provide field access via offsets for the fields we need.
// For TUI code that embeds shmif_cont (tui_context.acon, .clip_in, .clip_out),
// we need the full struct so it occupies the right space in tui_context.
// Use the opaque pointer type for function signatures.
pub const arcan_shmif_cont = opaque {};

// tui_screen_attr
pub const tui_screen_attr = extern struct {
    fc: [3]u8,
    bc: [3]u8,
    aflags: u16,
    custom_id: u8,
};

// tui_cell
pub const tui_cell = extern struct {
    attr: tui_screen_attr,
    ch: u32,
    draw_ch: u32,
    real_x: u32,
    cell_w: u8,
    fstamp: u8,
};

// tui_constraints
pub const tui_constraints = extern struct {
    anch_row: c_int,
    anch_col: c_int,
    max_rows: c_int,
    max_cols: c_int,
    min_rows: c_int,
    min_cols: c_int,
    hide: c_int,
    embed: c_int,
};

// tui_labelent
pub const tui_labelent = extern struct {
    label: [16]u8,
    descr: [58]u8,
    vsym: [5]u8,
    idatatype: u8,
    initial: u16,
    subv: u16,
    modifiers: u16,
};

// tui_cbcfg (callback function pointer table)
// We represent this as a bag of nullable function pointers + tag.
// The full struct for field access — each fn ptr is ?*const fn(...).
pub const tui_cbcfg = extern struct {
    tag: ?*anyopaque,
    query_label: ?*const fn (?*tui_context, usize, [*c]const u8, [*c]const u8, *tui_labelent, ?*anyopaque) callconv(.c) bool,
    input_label: ?*const fn (?*tui_context, [*c]const u8, bool, ?*anyopaque) callconv(.c) bool,
    input_alabel: ?*const fn (?*tui_context, [*c]const u8, [*c]const i16, usize, bool, u8, ?*anyopaque) callconv(.c) bool,
    input_mouse_motion: ?*const fn (?*tui_context, bool, c_int, c_int, c_int, ?*anyopaque) callconv(.c) void,
    input_mouse_button: ?*const fn (?*tui_context, c_int, c_int, c_int, bool, c_int, ?*anyopaque) callconv(.c) void,
    input_utf8: ?*const fn (?*tui_context, [*c]const u8, usize, ?*anyopaque) callconv(.c) bool,
    input_key: ?*const fn (?*tui_context, u32, u8, u16, u16, ?*anyopaque) callconv(.c) void,
    input_misc: ?*const fn (?*tui_context, *const arcan_ioevent, ?*anyopaque) callconv(.c) void,
    state: ?*const fn (?*tui_context, bool, c_int, ?*anyopaque) callconv(.c) void,
    bchunk: ?*const fn (?*tui_context, bool, u64, c_int, [*c]const u8, ?*anyopaque) callconv(.c) void,
    vpaste: ?*const fn (?*tui_context, [*c]shmif_pixel, usize, usize, usize, ?*anyopaque) callconv(.c) void,
    apaste: ?*const fn (?*tui_context, [*c]shmif_asample, usize, usize, usize, ?*anyopaque) callconv(.c) void,
    tick: ?*const fn (?*tui_context, ?*anyopaque) callconv(.c) void,
    utf8: ?*const fn (?*tui_context, [*c]const u8, usize, bool, ?*anyopaque) callconv(.c) void,
    resized: ?*const fn (?*tui_context, usize, usize, usize, usize, ?*anyopaque) callconv(.c) void,
    reset: ?*const fn (?*tui_context, c_int, ?*anyopaque) callconv(.c) void,
    geohint: ?*const fn (?*tui_context, f32, f32, f32, [*c]const u8, [*c]const u8, ?*anyopaque) callconv(.c) void,
    recolor: ?*const fn (?*tui_context, ?*anyopaque) callconv(.c) void,
    subwindow: ?*const fn (?*tui_context, ?*arcan_shmif_cont, u32, u8, ?*anyopaque) callconv(.c) bool,
    substitute: ?*const fn (?*tui_context, [*c]tui_cell, usize, usize, ?*anyopaque) callconv(.c) bool,
    resize: ?*const fn (?*tui_context, usize, usize, usize, usize, ?*anyopaque) callconv(.c) void,
    visibility: ?*const fn (?*tui_context, bool, bool, ?*anyopaque) callconv(.c) void,
    exec_state: ?*const fn (?*tui_context, c_int, ?*anyopaque) callconv(.c) void,
    cli_command: ?*const fn (?*tui_context, [*c]const [*c]const u8, usize, c_int, [*c]const u8, *usize) callconv(.c) c_int,
    seek_absolute: ?*const fn (?*tui_context, f32, ?*anyopaque) callconv(.c) void,
    seek_relative: ?*const fn (?*tui_context, isize, isize, ?*anyopaque) callconv(.c) void,
    message: ?*const fn (?*tui_context, [*c]const u8, bool, ?*anyopaque) callconv(.c) void,
};

// color (TUI internal)
pub const color = extern struct {
    rgb: [3]u8,
    bg: [3]u8,
    bgset: bool,
};

// tui_context
// Opaque — we access fields through verified byte offsets (from gcc offsetof).
// This avoids needing C helpers while maintaining zero stubs.
pub const tui_context = opaque {
    const Self = @This();

    // Field byte offsets (verified against gcc offsetof on aarch64-linux)
    const OFF_INACT_TIMER: usize = 88;
    const OFF_MOUSE_X: usize = 132;
    const OFF_MOUSE_Y: usize = 136;
    const OFF_MOUSE_STATE: usize = 140;
    const OFF_MOUSE_BTNMASK: usize = 172;
    const OFF_ROWS: usize = 228;
    const OFF_COLS: usize = 232;
    const OFF_CELL_W: usize = 404;
    const OFF_CELL_H: usize = 408;
    const OFF_MODIFIERS: usize = 428;
    const OFF_ACON: usize = 2808;
    const OFF_CLIP_IN: usize = 3000;
    const OFF_CLIP_OUT: usize = 3192;
    const OFF_HOOKS: usize = 3824;
    const OFF_HOOKS_INPUT: usize = 3832; // hooks.input fn ptr
    const OFF_HANDLERS: usize = 3880;

    // sizeof(arcan_shmif_cont) = 192, sizeof(tui_cbcfg) = 224
    const SHMIF_CONT_SIZE: usize = 192;
    const CBCFG_SIZE: usize = 224;

    // arcan_shmif_cont field offsets
    const SHMIF_OFF_VIDP: usize = 8;
    const SHMIF_OFF_W: usize = 80;
    const SHMIF_OFF_H: usize = 88;

    fn ptrAt(self: *Self, comptime T: type, offset: usize) *T {
        const base: [*]u8 = @ptrCast(self);
        return @ptrCast(@alignCast(base + offset));
    }

    fn ptrAtConst(self: *const Self, comptime T: type, offset: usize) *const T {
        const base: [*]const u8 = @ptrCast(self);
        return @ptrCast(@alignCast(base + offset));
    }

    // shmif_cont accessors
    pub fn getAcon(self: *Self) *arcan_shmif_cont {
        return @ptrCast(self.ptrAt(u8, OFF_ACON));
    }

    pub fn getClipIn(self: *Self) *arcan_shmif_cont {
        return @ptrCast(self.ptrAt(u8, OFF_CLIP_IN));
    }

    pub fn getClipOut(self: *Self) *arcan_shmif_cont {
        return @ptrCast(self.ptrAt(u8, OFF_CLIP_OUT));
    }

    pub fn clipOutHasVidp(self: *Self) bool {
        // vidp is at offset 8 within arcan_shmif_cont
        const vidp: *const ?*anyopaque = @ptrCast(@alignCast(self.ptrAt(u8, OFF_CLIP_OUT + SHMIF_OFF_VIDP)));
        return vidp.* != null;
    }

    pub fn getAconW(self: *const Self) usize {
        return self.ptrAtConst(usize, OFF_ACON + SHMIF_OFF_W).*;
    }

    pub fn getAconH(self: *const Self) usize {
        return self.ptrAtConst(usize, OFF_ACON + SHMIF_OFF_H).*;
    }

    // Scalar field accessors
    pub fn getModifiers(self: *Self) *c_int {
        return self.ptrAt(c_int, OFF_MODIFIERS);
    }

    pub fn getInactTimer(self: *Self) *c_int {
        return self.ptrAt(c_int, OFF_INACT_TIMER);
    }

    pub fn getMouseX(self: *Self) *c_int {
        return self.ptrAt(c_int, OFF_MOUSE_X);
    }

    pub fn getMouseY(self: *Self) *c_int {
        return self.ptrAt(c_int, OFF_MOUSE_Y);
    }

    pub fn getMouseState(self: *Self) [*c]u8 {
        const base: [*]u8 = @ptrCast(self);
        return base + OFF_MOUSE_STATE;
    }

    pub fn getMouseBtnmask(self: *Self) *u32 {
        return self.ptrAt(u32, OFF_MOUSE_BTNMASK);
    }

    pub fn getRows(self: *const Self) c_int {
        return self.ptrAtConst(c_int, OFF_ROWS).*;
    }

    pub fn getCols(self: *const Self) c_int {
        return self.ptrAtConst(c_int, OFF_COLS).*;
    }

    pub fn getCellW(self: *const Self) c_int {
        return self.ptrAtConst(c_int, OFF_CELL_W).*;
    }

    pub fn getCellH(self: *const Self) c_int {
        return self.ptrAtConst(c_int, OFF_CELL_H).*;
    }

    // Callback table accessor
    pub fn getHandlers(self: *Self) *tui_cbcfg {
        return self.ptrAt(tui_cbcfg, OFF_HANDLERS);
    }

    pub fn getHandlersConst(self: *const Self) *const tui_cbcfg {
        return self.ptrAtConst(tui_cbcfg, OFF_HANDLERS);
    }

    // Hooks accessor (hooks.input fn ptr)
    pub const hooks_input_fn = ?*const fn (*Self, *const arcan_ioevent, [*c]const u8) callconv(.c) void;

    pub fn getHooksInput(self: *Self) hooks_input_fn {
        return self.ptrAt(hooks_input_fn, OFF_HOOKS_INPUT).*;
    }
};

// cfg_lookup_fun — function pointer for platform_config_lookup
pub const cfg_lookup_fun = ?*const fn ([*c]const u8, u16, *[*c]u8, usize) callconv(.c) bool;

// arcan_strarr
pub const arcan_strarr = extern struct {
    count: usize,
    limit: usize,
    data: [*c][*c]u8,
    cdata: [*c]?*anyopaque,
};

// UTF-8 decoder (Hoehrmann DFA)
pub const UTF8_ACCEPT: u32 = 0;
pub const UTF8_REJECT: u32 = 1;

const utf8d = [_]u8{
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 00..1f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 20..3f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 40..5f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 60..7f
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, // 80..9f
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // a0..bf
    8, 8, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // c0..df
    0xa, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x4, 0x3, 0x3, // e0..ef
    0xb, 0x6, 0x6, 0x6, 0x5, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, // f0..ff
    0x0, 0x1, 0x2, 0x3, 0x5, 0x8, 0x7, 0x1, 0x1, 0x1, 0x4, 0x6, 0x1, 0x1, 0x1, 0x1, // s0..s0
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, // s1..s2
    1, 2, 1, 1, 1, 1, 1, 2, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, // s3..s4
    1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 1, 3, 1, 1, 1, 1, 1, 1, // s5..s6
    1, 3, 1, 1, 1, 1, 1, 3, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // s7..s8
};

pub fn utf8_decode(state: *u32, codep: *u32, byte: u32) u32 {
    const @"type" = utf8d[@intCast(byte)];
    codep.* = if (state.* != UTF8_ACCEPT)
        (byte & 0x3f) | (codep.* << 6)
    else
        ((@as(u32, 0xff) >> @intCast(@"type"))) & byte;
    state.* = utf8d[256 + state.* * 16 + @"type"];
    return state.*;
}

// Common extern fn declarations
pub extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
pub extern fn arcan_mem_free(ptr: ?*anyopaque) void;
pub extern fn arcan_shmif_enqueue(ctx: ?*arcan_shmif_cont, ev: *const arcan_event) c_int;
pub extern fn arcan_shmif_poll(ctx: ?*arcan_shmif_cont, ev: *arcan_event) c_int;
pub extern fn arcan_shmif_drop(ctx: ?*arcan_shmif_cont) void;
pub extern fn arcan_shmif_pushutf8(ctx: ?*arcan_shmif_cont, ev: *arcan_event, msg: [*c]const u8, len: usize) bool;
pub extern fn arcan_shmif_mousestate_ioev(ctx: ?*arcan_shmif_cont, state: [*c]u8, ioev: *const arcan_ioevent, x: *c_int, y: *c_int) bool;
pub extern fn arcan_expand_resource(label: [*c]const u8, ns: c_int) [*c]u8;
pub extern fn arcan_override_namespace(path: [*c]const u8, ns: c_int) void;
pub extern fn arcan_softoverride_namespace(path: [*c]const u8, ns: c_int) void;
pub extern fn arcan_pin_namespace(ns: c_int) void;
pub extern fn arcan_fetch_namespace(ns: c_int) [*c]const u8;
pub extern fn arcan_lookup_namespace(ns: c_int) [*c]const u8;
pub extern fn arcan_isfile(path: [*c]const u8) bool;
pub extern fn arcan_isdir(path: [*c]const u8) bool;
pub extern fn platform_config_lookup(tag: *usize) cfg_lookup_fun;

// ══════════════════════════════════════════════════════════════════════════════
// Symbols needed by arcan_video.zig (in addition to the above)
// ══════════════════════════════════════════════════════════════════════════════

// Additional error codes
pub const ARCAN_ERRC_CLONE_NOT_PERMITTED: arcan_errc = -2;
pub const ARCAN_ERRC_UNACCEPTED_STATE: arcan_errc = -4;
pub const ARCAN_ERRC_OUT_OF_SPACE: arcan_errc = -6;
pub const ARCAN_ERRC_BAD_RESOURCE: arcan_errc = -8;
pub const ARCAN_ERRC_BADVMODE: arcan_errc = -9;

// Video constants
pub const ARCAN_VIDEO_WORLDID: arcan_vobj_id = -1;
pub const ARCAN_EID: arcan_vobj_id = 0;
pub const CONTEXT_STACK_LIMIT: c_int = 8;
pub const VITEM_CONTEXT_LIMIT: c_int = 65536;
pub const RENDERTARGET_LIMIT: c_int = 64;
pub const BADFD: c_int = -1;
pub const ARCAN_VINTER_LINEAR: c_int = 0;
pub const ARCAN_VTEX_REPEAT: c_uint = 0;
pub const ARCAN_VTEX_CLAMP: c_uint = 1;

// Type aliases
pub const av_pixel = u32;
pub const arcan_tickv = u32;
pub const agp_shader_id = u32;
pub const ffunc_ind = u8;
pub const sem_handle = ?*anyopaque; // sem_t* opaque
pub const arcan_interp_1d_function = ?*const fn (f32, f32, f32) callconv(.c) f32;
pub const arcan_interp_3d_function = ?*const fn (vector, vector, f32) callconv(.c) vector;
pub const arcan_interp_4d_function = ?*const fn (quat, quat, f32) callconv(.c) quat;

// Math types
// Matches @cImport layout: union { struct { x, y, z }, xyz[3] }
pub const vector = extern struct {
    unnamed_0: extern union {
        unnamed_0: extern struct { x: f32, y: f32, z: f32 },
        xyz: [3]f32,
    } = .{ .unnamed_0 = .{ .x = 0, .y = 0, .z = 0 } },
    pub fn init(x: f32, y: f32, z: f32) vector {
        return .{ .unnamed_0 = .{ .unnamed_0 = .{ .x = x, .y = y, .z = z } } };
    }
};
pub const quat = extern struct {
    unnamed_0: extern union {
        unnamed_0: extern struct { x: f32, y: f32, z: f32, w: f32 },
        xyzw: [4]f32,
    } = .{ .unnamed_0 = .{ .x = 0, .y = 0, .z = 0, .w = 0 } },
};
pub const point = vector;
pub const scalefactor = vector;
pub const surface_orientation = extern struct {
    yaw: f32 = 0,
    pitch: f32 = 0,
    roll: f32 = 0,
    quaternion: quat = .{},
};
pub const surface_properties = extern struct {
    position: point = .{},
    scale: scalefactor = .{},
    opa: f32 = 0,
    rotation: surface_orientation = .{},
};
pub const img_cons = extern struct {
    w: c_uint = 0,
    h: c_uint = 0,
    bpp: u8 = 0,
};

// vfunc_state
pub const vfunc_state = extern struct {
    tag: c_int = 0, // volatile int in C
    ptr: ?*anyopaque = null,
};

// Blend function enum
pub const arcan_blendfunc = c_uint;
pub const BLEND_NONE: arcan_blendfunc = 0;
pub const BLEND_NORMAL: arcan_blendfunc = 1;
pub const BLEND_ADD: arcan_blendfunc = 2;
pub const BLEND_MULTIPLY: arcan_blendfunc = 3;
pub const BLEND_SUB: arcan_blendfunc = 4;
pub const BLEND_PREMUL: arcan_blendfunc = 5;
pub const BLEND_FORCE: arcan_blendfunc = 128;

// Clip mode enum
pub const arcan_clipmode = c_uint;
pub const ARCAN_CLIP_OFF: arcan_clipmode = 0;
pub const ARCAN_CLIP_ON: arcan_clipmode = 1;
pub const ARCAN_CLIP_SHALLOW: arcan_clipmode = 2;

// Filter mode enum
pub const arcan_vfilter_mode = c_uint;
pub const ARCAN_VFILTER_NONE: arcan_vfilter_mode = 0;
pub const ARCAN_VFILTER_LINEAR: arcan_vfilter_mode = 1;
pub const ARCAN_VFILTER_BILINEAR: arcan_vfilter_mode = 2;
pub const ARCAN_VFILTER_TRILINEAR: arcan_vfilter_mode = 3;
pub const ARCAN_VFILTER_MIPMAP: arcan_vfilter_mode = 128;

// Image mode enum
pub const arcan_vimage_mode = c_uint;
pub const ARCAN_VIMAGE_NOPOW2: arcan_vimage_mode = 0;
pub const ARCAN_VIMAGE_SCALEPOW2: arcan_vimage_mode = 1;

// Image proc mode enum
pub const arcan_imageproc_mode = c_uint;
pub const IMAGEPROC_NORMAL: arcan_imageproc_mode = 0;
pub const IMAGEPROC_FLIPH: arcan_imageproc_mode = 1;

// Slice type enum
pub const arcan_slicetype = c_uint;
pub const ARCAN_CUBEMAP: arcan_slicetype = 0;
pub const ARCAN_3DTEXTURE: arcan_slicetype = 1;

// Object tags enum
pub const arcan_vobj_tags = c_uint;
pub const ARCAN_TAG_NONE: arcan_vobj_tags = 0;
pub const ARCAN_TAG_IMAGE: arcan_vobj_tags = 1;
pub const ARCAN_TAG_TEXT: arcan_vobj_tags = 2;
pub const ARCAN_TAG_FRAMESERV: arcan_vobj_tags = 3;
pub const ARCAN_TAG_ASYNCIMGLD: arcan_vobj_tags = 4;
pub const ARCAN_TAG_ASYNCIMGRD: arcan_vobj_tags = 5;
pub const ARCAN_TAG_3DOBJ: arcan_vobj_tags = 6;
pub const ARCAN_TAG_3DCAMERA: arcan_vobj_tags = 7;
pub const ARCAN_TAG_CUSTOMPROC: arcan_vobj_tags = 8;
pub const ARCAN_TAG_LWA: arcan_vobj_tags = 9;
pub const ARCAN_TAG_VR: arcan_vobj_tags = 10;

// Transform mask enum
pub const MASK_NONE: c_int = 0;
pub const MASK_POSITION: c_int = 1;
pub const MASK_SCALE: c_int = 2;
pub const MASK_OPACITY: c_int = 4;
pub const MASK_LIVING: c_int = 8;
pub const MASK_ORIENTATION: c_int = 16;
pub const MASK_UNPICKABLE: c_int = 32;
pub const MASK_FRAMESET: c_int = 64;
pub const MASK_MAPPING: c_int = 128;
pub const MASK_TRANSFORMS: c_int = MASK_POSITION | MASK_SCALE | MASK_OPACITY | MASK_ORIENTATION;

// Parent anchor enum
pub const enum_parent_anchor = c_uint;
pub const ANCHORP_UL: enum_parent_anchor = 1;
pub const ANCHORP_UC: enum_parent_anchor = 2;
pub const ANCHORP_UR: enum_parent_anchor = 3;
pub const ANCHORP_CL: enum_parent_anchor = 4;
pub const ANCHORP_C: enum_parent_anchor = 5;
pub const ANCHORP_CR: enum_parent_anchor = 6;
pub const ANCHORP_LL: enum_parent_anchor = 7;
pub const ANCHORP_LC: enum_parent_anchor = 8;
pub const ANCHORP_LR: enum_parent_anchor = 9;

// Parent scale enum
pub const enum_parent_scale = c_uint;
pub const SCALEM_NONE: enum_parent_scale = 0;
pub const SCALEM_WIDTH: enum_parent_scale = 1;
pub const SCALEM_HEIGHT: enum_parent_scale = 2;
pub const SCALEM_WIDTH_HEIGHT: enum_parent_scale = 3;
pub const SCALEM_DEPTH: enum_parent_scale = 4;

// Order 3D enum
pub const arcan_order3d = c_uint;
pub const ORDER3D_NONE: arcan_order3d = 0;
pub const ORDER3D_FIRST: arcan_order3d = 1;
pub const ORDER3D_LAST: arcan_order3d = 2;

// Frameset mode enum
pub const ARCAN_FRAMESET_SPLIT: c_uint = 0;
pub const ARCAN_FRAMESET_MULTITEXTURE: c_uint = 1;

// Rendertarget mode enum
pub const enum_rendertarget_mode = c_uint;
pub const RENDERTARGET_DEPTH: enum_rendertarget_mode = 0;
pub const RENDERTARGET_COLOR: enum_rendertarget_mode = 1;
pub const RENDERTARGET_COLOR_DEPTH: enum_rendertarget_mode = 2;
pub const RENDERTARGET_COLOR_DEPTH_STENCIL: enum_rendertarget_mode = 3;
pub const RENDERTARGET_RETAIN_ALPHA: enum_rendertarget_mode = 4;

// Rendertarget flags
pub const TGTFL_READING: c_int = 1;
pub const TGTFL_ALIVE: c_int = 2;
pub const TGTFL_NOCLEAR: c_int = 4;

// Vobj flags
pub const FL_INUSE: c_int = 1;
pub const FL_NASYNC: c_int = 2;
pub const FL_TCYCLE: c_int = 4;
pub const FL_ROTOFS: c_int = 18;
pub const FL_ORDOFS: c_int = 16;
pub const FL_PRSIST: c_int = 32;
pub const FL_FULL3D: c_int = 64;
pub const FL_RTGT: c_int = 128;

// Feed function enum
pub const FFUNC_FATAL: c_uint = 0;
pub const FFUNC_NULL: c_uint = 1;
pub const FFUNC_AVFEED: c_uint = 2;
pub const FFUNC_NULLFEED: c_uint = 3;
pub const FFUNC_FEEDCOPY: c_uint = 4;
pub const FFUNC_VFRAME: c_uint = 5;
pub const FFUNC_NULLFRAME: c_uint = 6;
pub const FFUNC_WRAPPED: c_uint = 7;
pub const FFUNC_LUA_PROC: c_uint = 8;
pub const FFUNC_3DOBJ: c_uint = 9;
pub const FFUNC_LWA: c_uint = 10;
pub const FFUNC_VR: c_uint = 11;
pub const FFUNC_SOCKVER: c_uint = 12;
pub const FFUNC_SOCKPOLL: c_uint = 13;

// Feed function commands
pub const FFUNC_POLL: c_uint = 0;
pub const FFUNC_RENDER: c_uint = 1;
pub const FFUNC_TICK: c_uint = 2;
pub const FFUNC_DESTROY: c_uint = 3;
pub const FFUNC_READBACK: c_uint = 4;
pub const FFUNC_READBACK_HANDLE: c_uint = 5;
pub const FFUNC_ADOPT: c_uint = 6;

// Feed function return values
pub const FRV_NOFRAME: c_uint = 0;
pub const FRV_GOTFRAME: c_uint = 1;
pub const FRV_COPIED: c_uint = 2;
pub const FRV_NOUPLOAD: c_uint = 64;

// Shader env slots
pub const MODELVIEW_MATR: c_uint = 0;
pub const PROJECTION_MATR: c_uint = 1;
pub const TEXTURE_MATR: c_uint = 2;
pub const OBJ_OPACITY: c_uint = 3;
pub const TRANS_BLEND: c_uint = 4;
pub const TRANS_MOVE: c_uint = 5;
pub const TRANS_ROTATE: c_uint = 6;
pub const TRANS_SCALE: c_uint = 7;
pub const SIZE_INPUT: c_uint = 8;
pub const SIZE_OUTPUT: c_uint = 9;
pub const SIZE_STORAGE: c_uint = 10;
pub const RTGT_ID: c_uint = 11;
pub const FRACT_TIMESTAMP_F: c_uint = 12;
pub const TIMESTAMP_D: c_uint = 13;

// Shader uniform types
pub const shdrbool: c_uint = 0;
pub const shdrint: c_uint = 1;
pub const shdrfloat: c_uint = 2;
pub const shdrvec2: c_uint = 3;
pub const shdrvec3: c_uint = 4;
pub const shdrvec4: c_uint = 5;
pub const shdrmat4x4: c_uint = 6;

// Shader types enum
pub const BASIC_2D: c_uint = 0;
pub const COLOR_2D: c_uint = 1;
pub const BASIC_3D: c_uint = 2;

// Txstate enum
pub const TXSTATE_OFF: c_uint = 0;
pub const TXSTATE_TEX2D: c_uint = 1;
pub const TXSTATE_DEPTH: c_uint = 2;
pub const TXSTATE_TEX3D: c_uint = 3;
pub const TXSTATE_CUBE: c_uint = 4;
pub const TXSTATE_TPACK: c_uint = 5;

// Storage source enum
pub const STORAGE_IMAGE_URI: c_uint = 0;
pub const STORAGE_TEXT: c_uint = 1;
pub const STORAGE_TEXTARRAY: c_uint = 2;
pub const STORAGE_TPACK: c_uint = 3;

// Pipeline mode enum
pub const PIPELINE_2D: c_uint = 0;
pub const PIPELINE_3D: c_uint = 1;

// AGP mesh type enum
pub const AGP_MESH_TRISOUP: c_uint = 0;
pub const AGP_MESH_POINTCLOUD: c_uint = 1;

// AGP depth func enum
pub const AGP_DEPTH_LESS: c_uint = 0;
pub const AGP_DEPTH_LESSEQUAL: c_uint = 1;
pub const AGP_DEPTH_GREATER: c_uint = 2;
pub const AGP_DEPTH_GREATEREQUAL: c_uint = 3;
pub const AGP_DEPTH_EQUAL: c_uint = 4;
pub const AGP_DEPTH_NOTEQUAL: c_uint = 5;
pub const AGP_DEPTH_ALWAYS: c_uint = 6;

// AGP mesh flags enum
pub const MESH_FACING_FRONT: c_uint = 1;
pub const MESH_FACING_BACK: c_uint = 2;
pub const MESH_FACING_BOTH: c_uint = 3;
pub const MESH_FACING_NODEPTH: c_uint = 4;
pub const MESH_DEBUG_GEOMETRY: c_uint = 8;
pub const MESH_FILL_LINE: c_uint = 16;

// Blitting hint enum
pub const enum_blitting_hint = c_uint;
pub const HINT_NONE: enum_blitting_hint = 0;
pub const HINT_FL_PRIMARY: enum_blitting_hint = 1;
pub const HINT_FIT: enum_blitting_hint = 2;
pub const HINT_CROP: enum_blitting_hint = 4;
pub const HINT_YFLIP: enum_blitting_hint = 8;
pub const HINT_ROTATE_CW_90: enum_blitting_hint = 16;
pub const HINT_ROTATE_CCW_90: enum_blitting_hint = 32;
pub const HINT_ROTATE_180: enum_blitting_hint = 64;
pub const HINT_CURSOR: enum_blitting_hint = 128;
pub const HINT_DIRECT: enum_blitting_hint = 256;

// Tag transform methods enum
pub const enum_tag_transform_methods = c_uint;
pub const TAG_TRANSFORM_SKIP: enum_tag_transform_methods = 0;
pub const TAG_TRANSFORM_LAST: enum_tag_transform_methods = 1;
pub const TAG_TRANSFORM_ALL: enum_tag_transform_methods = 2;

// Video event subtypes
pub const EVENT_VIDEO_EXPIRE: c_uint = 0;
pub const EVENT_VIDEO_CHAIN_OVER: c_uint = 1;
pub const EVENT_VIDEO_DISPLAY_RESET: c_uint = 2;
pub const EVENT_VIDEO_DISPLAY_ADDED: c_uint = 3;
pub const EVENT_VIDEO_DISPLAY_REMOVED: c_uint = 4;
pub const EVENT_VIDEO_DISPLAY_CHANGED: c_uint = 5;
pub const EVENT_VIDEO_ASYNCHIMAGE_LOADED: c_uint = 6;
pub const EVENT_VIDEO_ASYNCHIMAGE_FAILED: c_uint = 7;

// Memory type/hint/align enums
pub const ARCAN_MEM_VBUFFER: c_uint = 1;
pub const ARCAN_MEM_VSTRUCT: c_uint = 2;
pub const ARCAN_MEM_EXTSTRUCT: c_uint = 3;
pub const ARCAN_MEM_ABUFFER: c_uint = 4;
pub const ARCAN_MEM_STRINGBUF: c_uint = 5;
pub const ARCAN_MEM_SHARED: c_uint = 6;
pub const ARCAN_MEM_VTAG: c_uint = 7;
pub const ARCAN_MEM_ATAG: c_uint = 8;
pub const ARCAN_MEM_BINDING: c_uint = 9;
pub const ARCAN_MEM_MODELDATA: c_uint = 10;
pub const ARCAN_MEM_THREADCTX: c_uint = 11;

pub const ARCAN_MEM_BZERO: c_uint = 1;
pub const ARCAN_MEM_TEMPORARY: c_uint = 2;
pub const ARCAN_MEM_EXEC: c_uint = 4;
pub const ARCAN_MEM_NONFATAL: c_uint = 8;
pub const ARCAN_MEM_READONLY: c_uint = 16;
pub const ARCAN_MEM_SENSITIVE: c_uint = 32;

pub const ARCAN_MEMALIGN_NATURAL: c_uint = 0;
pub const ARCAN_MEMALIGN_PAGE: c_uint = 1;
pub const ARCAN_MEMALIGN_SIMD: c_uint = 2;

// ══════════════════════════════════════════════════════════════════════════════
// Opaque struct types (accessed only via pointer)
// ══════════════════════════════════════════════════════════════════════════════

pub const struct_arcan_frameserver = anyopaque;
pub const struct_arcan_img_meta = extern struct {
    compressed: bool = false,
    mipmapped: bool = false,
    pwidth: c_int = 0,
    pheight: c_int = 0,
    c_size: usize = 0,
};
pub const struct_arcan_rstrarg = extern struct {
    multiple: bool = false,
    _pad0: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
    unnamed_0: extern union {
        message: [*c]u8,
        array: [*c][*c]u8,
    } = .{ .message = null },
};
pub const struct_renderline_meta = extern struct {
    height: c_int = 0,
    ystart: c_int = 0,
    ascent: c_int = 0,
};

// drm_hdr_meta
pub const drm_hdr_meta = extern struct {
    eotf: c_int = 0,
    rx: f32 = 0, ry: f32 = 0, gx: f32 = 0, gy: f32 = 0, bx: f32 = 0, by: f32 = 0,
    wpx: f32 = 0, wpy: f32 = 0,
    master_min: f32 = 0, master_max: f32 = 0,
    cll: f32 = 0, fll: f32 = 0,
};

// agp_vstore (full struct with field access needed)
pub const struct_agp_vstore = extern struct {
    refcount: usize = 0, update_ts: u32 = 0, _pad0: [4]u8 = .{ 0, 0, 0, 0 },
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
    dst_copy: ?*struct_agp_vstore = null,
    w: usize = 0, h: usize = 0,
    bpp: u8 = 0, txmapped: u8 = 0, txu: u8 = 0, txv: u8 = 0,
    scale: u8 = 0, imageproc: u8 = 0, filtermode: u8 = 0,
    _pad_hdr: [1]u8 = .{0},
    hdr: extern struct {
        model: c_int = 0,
        drm: drm_hdr_meta = std.mem.zeroes(drm_hdr_meta),
    } = .{},
};

// agp_rendertarget (sized opaque)
pub const struct_agp_rendertarget = extern struct { _data: [256]u8 = std.mem.zeroes([256]u8) };

// agp_mesh_store (full struct — accessed by 3D code)
pub const struct_agp_mesh_store = extern struct {
    shared_buffer: [*c]u8 = null,
    shared_buffer_sz: usize = 0,
    verts: [*c]f32 = null,
    txcos: [*c]f32 = null,
    txcos2: [*c]f32 = null,
    normals: [*c]f32 = null,
    colors: [*c]f32 = null,
    tangents: [*c]f32 = null,
    bitangents: [*c]f32 = null,
    weights: [*c]f32 = null,
    joints: [*c]u16 = null,
    indices: [*c]c_uint = null,
    vertex_size: usize = 0,
    n_vertices: usize = 0,
    n_indices: usize = 0,
    @"type": c_uint = 0,
    depth_func: c_uint = 0,
    @"opaque": usize = 0,
    dirty: bool = false,
    nodepth: bool = false,
    validated: bool = false,
};

// surface_transform (needs @sizeOf and @offsetOf)
pub const struct_transf_move = extern struct {
    interp: u8 = 0,
    _pad0: [3]u8 = .{ 0, 0, 0 },
    startt: arcan_tickv = 0,
    endt: arcan_tickv = 0,
    startp: point = .{},
    endp: point = .{},
    tag: isize = 0,
};
pub const struct_transf_scale = extern struct {
    interp: u8 = 0,
    _pad0: [3]u8 = .{ 0, 0, 0 },
    startt: arcan_tickv = 0,
    endt: arcan_tickv = 0,
    startd: scalefactor = .{},
    endd: scalefactor = .{},
    tag: isize = 0,
};
pub const struct_transf_blend = extern struct {
    interp: u8 = 0,
    _pad0: [3]u8 = .{ 0, 0, 0 },
    startt: arcan_tickv = 0,
    endt: arcan_tickv = 0,
    startopa: f32 = 0,
    endopa: f32 = 0,
    tag: isize = 0,
};
pub const struct_transf_rotate = extern struct {
    interp: arcan_interp_4d_function = null,
    startt: arcan_tickv = 0,
    endt: arcan_tickv = 0,
    starto: surface_orientation = .{},
    endo: surface_orientation = .{},
    tag: isize = 0,
};
pub const struct_surface_transform = extern struct {
    move: struct_transf_move = .{},
    scale: struct_transf_scale = .{},
    blend: struct_transf_blend = .{},
    rotate: struct_transf_rotate = .{},
    next: ?*struct_surface_transform = null,
};

// frameset_store
pub const struct_frameset_store = extern struct {
    frame: [*c]struct_agp_vstore = null,
    txcos: [8]f32 = std.mem.zeroes([8]f32),
};

// vobject_frameset
pub const struct_vobject_frameset = extern struct {
    frames: [*c]struct_frameset_store = null,
    n_frames: usize = 0,
    index: usize = 0,
    ctr: c_int = 0,
    mctr: c_int = 0,
    mode: c_uint = 0, // arcan_framemode
};
pub const vobject_frameset = struct_vobject_frameset;

// arcan_vobject_litem (linked list element)
pub const struct_arcan_vobject_litem = extern struct {
    elem: [*c]arcan_vobject = @ptrFromInt(0),
    next: [*c]struct_arcan_vobject_litem = @ptrFromInt(0),
    previous: [*c]struct_arcan_vobject_litem = @ptrFromInt(0),
};

// rendertarget (full struct, fields are accessed)
pub const struct_rendertarget = extern struct {
    base: [16]f32 align(16) = std.mem.zeroes([16]f32),
    projection: [16]f32 align(16) = std.mem.zeroes([16]f32),
    shid: agp_shader_id = 0, _p0: [4]u8 = .{0} ** 4,
    frame_cookie: u64 = 0, msc: u64 = 0,
    force_shid: bool = false, inv_y: bool = false, _p1: [2]u8 = .{0} ** 2,
    id: c_int = 0,
    color: [*c]arcan_vobject = @ptrFromInt(0),
    first: [*c]struct_arcan_vobject_litem = @ptrFromInt(0),
    link: [*c]struct_rendertarget = @ptrFromInt(0),
    art: [*c]struct_agp_rendertarget = @ptrFromInt(0),
    mode: c_uint = 0, flags: c_uint = 0, order3d: c_uint = 0, _p2: [4]u8 = .{0} ** 4,
    readback: c_int = 0, readcnt: c_int = 0,
    hwreadback: bool = false, _p3: [3]u8 = .{0} ** 3,
    refresh: c_int = 0, refreshcnt: c_int = 0,
    transfc: usize = 0, uploadc: usize = 0, dirtyc: usize = 0,
    hppcm: f32 = 0, vppcm: f32 = 0,
    camtag: arcan_vobj_id = 0, min_order: usize = 0, max_order: usize = 0,
};

// arcan_vobject (full struct, many fields accessed directly)
pub const arcan_vobject = extern struct {
    parent: ?*arcan_vobject = null,
    children: [*c]?*arcan_vobject = @ptrFromInt(0),
    frameset: ?*struct_vobject_frameset = null,
    vstore: [*c]struct_agp_vstore = null,
    flags: c_uint = 0,
    origw: u16 = 0,
    origh: u16 = 0,
    program: agp_shader_id = 0,
    _pad_shape: [4]u8 = .{ 0, 0, 0, 0 },
    shape: ?*struct_agp_mesh_store = null,
    feed: extern struct {
        ffunc: c_uint = 0,
        _pad0: [4]u8 = .{ 0, 0, 0, 0 },
        state: vfunc_state = .{},
        pcookie: u64 = 0,
    } = .{},
    txcos: [*c]f32 = null,
    blendmode: arcan_blendfunc = 0,
    order: c_int = 0,
    current: surface_properties = std.mem.zeroes(surface_properties),
    origo_ofs: point = std.mem.zeroes(point),
    _pad_align: [4]u8 = .{ 0, 0, 0, 0 },
    transform: ?*struct_surface_transform = null,
    mask: c_int = 0,
    clip: arcan_clipmode = 0,
    clip_src: arcan_vobj_id = 0,
    valid_cache: bool = false,
    rotate_state: bool = false,
    _pad_vc: [6]u8 = .{ 0, 0, 0, 0, 0, 0 },
    prop_cache: surface_properties = std.mem.zeroes(surface_properties),
    prop_matr: [16]f32 align(16) = std.mem.zeroes([16]f32),
    last_updated: c_ulong = 0,
    lifetime: c_long = 0,
    p_anchor: enum_parent_anchor = 0,
    p_scale: enum_parent_scale = 0,
    p_anchor_shift: enum_parent_anchor = 0,
    childslots: c_uint = 0,
    owner: [*c]struct_rendertarget = null,
    cellid: arcan_vobj_id = 0,
    extrefc: extern struct { attachments: c_int = 0, links: c_int = 0 } = .{},
    tracetag: ?[*:0]u8 = null,
    alttext: ?[*:0]u8 = null,
};

// arcan_video_display (full struct with fields accessed)
pub const struct_arcan_video_display = extern struct {
    suspended: bool = false,
    fullscreen: bool = false,
    conservative: bool = false,
    in_video: bool = false,
    no_stdout: bool = false,
    _pad0: [3]u8 = std.mem.zeroes([3]u8),
    cookie: u64 = 0,
    dirty: c_int = 0,
    _pad1: [4]u8 = std.mem.zeroes([4]u8),
    ignore_dirty: usize = 0,
    order3d: arcan_order3d = 0,
    _pad2: [4]u8 = std.mem.zeroes([4]u8),
    cursor: extern struct {
        vstore: [*c]struct_agp_vstore = null,
        x: c_int = 0,
        ox: c_int = 0,
        y: c_int = 0,
        oy: c_int = 0,
        w: usize = 0,
        h: usize = 0,
        active: bool = false,
    } = .{},
    default_vitemlim: c_uint = 0,
    _pad3: [4]u8 = std.mem.zeroes([4]u8),
    default_projection: [16]f32 = std.mem.zeroes([16]f32),
    window_projection: [16]f32 = std.mem.zeroes([16]f32),
    default_txcos: [8]f32 = std.mem.zeroes([8]f32),
    cursor_txcos: [8]f32 = std.mem.zeroes([8]f32),
    mirror_txcos: [8]f32 = std.mem.zeroes([8]f32),
    scalemode: arcan_vimage_mode = 0,
    imageproc: arcan_imageproc_mode = 0,
    filtermode: arcan_vfilter_mode = 0,
    blendmode: arcan_blendfunc = 0,
    deftxs: c_uint = 0,
    deftxt: c_uint = 0,
    mipmap: bool = false,
    _pad4: [3]u8 = std.mem.zeroes([3]u8),
    c_ticks: arcan_tickv = 0,
    c_lerp: f32 = 0,
    msasamples: u8 = 0,
    _pad5: [7]u8 = std.mem.zeroes([7]u8),
    txdump: ?[*:0]u8 = null,
};

// arcan_video_context (full struct with fields accessed)
pub const struct_arcan_video_context = extern struct {
    vitem_ofs: c_uint = 0,
    vitem_limit: c_uint = 0,
    nalive: c_long = 0,
    last_tickstamp: arcan_tickv = 0,
    _pad0: [4]u8 = std.mem.zeroes([4]u8),
    world: arcan_vobject = .{},
    vitems_pool: [*c]arcan_vobject = null,
    rtargets: [RENDERTARGET_LIMIT]struct_rendertarget = std.mem.zeroes([RENDERTARGET_LIMIT]struct_rendertarget),
    attachment: ?*struct_rendertarget = null,
    n_rtargets: isize = 0,
    stdoutp: struct_rendertarget = std.mem.zeroes(struct_rendertarget),
};

// arcan_evctx (sized opaque — only used as pointer from arcan_event_defaultctx)
pub const struct_arcan_evctx = anyopaque;

// monitor_mode (returned by platform_video_dimensions)
pub const struct_monitor_mode = extern struct {
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

// asynch_readback_meta (returned by agp_poll_readback)
pub const struct_asynch_readback_meta = extern struct {
    ptr: ?[*]av_pixel = null,
    buf_sz: usize = 0,
    w: usize = 0,
    h: usize = 0,
    stride: usize = 0,
    release: ?*const fn (?*anyopaque) callconv(.c) void = null,
    tag: ?*anyopaque = null,
};

// data_source / map_region (used by arcan_open_resource etc.)
pub const data_source = extern struct {
    fd: c_int = 0,
    _pad0: [4]u8 = .{ 0, 0, 0, 0 },
    start: isize = 0, // off_t
    len: isize = 0, // off_t
    source: [*c]u8 = null,
};
pub const map_region = extern struct {
    unnamed_0: extern struct {
        ptr: [*c]u8 = null,
    } = .{},
    zbyte: u8 = 0,
    _pad0: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
    sz: usize = 0,
    mmap: bool = false,
};

// default_quat (extern global)
pub extern var default_quat: quat;

// pthread types
pub const pthread_t = usize;

// DEG2RAD (inline function, not a C macro — Zig comptime)
pub inline fn DEG2RAD(x: f32) f32 {
    return x * std.math.pi / 180.0;
}

// ══════════════════════════════════════════════════════════════════════════════
// 1D / 3D interpolation functions
// ══════════════════════════════════════════════════════════════════════════════

pub extern fn interp_1d_linear(startv: f32, stopv: f32, fract: f32) f32;
pub extern fn interp_1d_sine(startv: f32, endv: f32, fract: f32) f32;
pub extern fn interp_1d_expout(startv: f32, endv: f32, fract: f32) f32;
pub extern fn interp_1d_expin(startv: f32, endv: f32, fract: f32) f32;
pub extern fn interp_1d_expinout(startv: f32, endv: f32, fract: f32) f32;
pub extern fn interp_1d_smoothstep(startv: f32, endv: f32, fract: f32) f32;

pub extern fn interp_3d_linear(startv: vector, stopv: vector, fract: f32) vector;
pub extern fn interp_3d_sine(startv: vector, endv: vector, fract: f32) vector;
pub extern fn interp_3d_expout(startv: vector, endv: vector, fract: f32) vector;
pub extern fn interp_3d_expin(startv: vector, endv: vector, fract: f32) vector;
pub extern fn interp_3d_expinout(startv: vector, endv: vector, fract: f32) vector;
pub extern fn interp_3d_smoothstep(startv: vector, endv: vector, fract: f32) vector;

pub extern fn nlerp_quat180(a: quat, b: quat, f: f32) quat;
pub extern fn nlerp_quat360(a: quat, b: quat, f: f32) quat;

// ══════════════════════════════════════════════════════════════════════════════
// Math functions
// ══════════════════════════════════════════════════════════════════════════════

pub extern fn identity_matrix(m: [*c]f32) void;
pub extern fn scale_matrix(m: [*c]f32, sx: f32, sy: f32, sz: f32) void;
pub extern fn translate_matrix(m: [*c]f32, tx: f32, ty: f32, tz: f32) void;
pub extern fn multiply_matrix(dst: [*c]f32, a: [*c]const f32, b: [*c]const f32) void;
pub extern fn build_orthographic_matrix(m: [*c]f32, left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) void;
pub extern fn build_quat_taitbryan(roll: f32, pitch: f32, yaw: f32) quat;
pub extern fn matr_quatf(a: quat, dmatr: [*c]f32) [*c]f32;
pub extern fn matr_rotatef(ang: f32, dst: [*c]f32) [*c]f32;
pub extern fn angle_quat(a: quat) vector;
pub extern fn norm_quat(src: quat) quat;
pub extern fn mul_quat(a: quat, b: quat) quat;

// ══════════════════════════════════════════════════════════════════════════════
// AGP functions
// ══════════════════════════════════════════════════════════════════════════════

pub extern fn agp_init() void;
pub extern fn agp_activate_rendertarget(tgt: ?*struct_agp_rendertarget) void;
pub extern fn agp_activate_stencil() void;
pub extern fn agp_activate_vstore(backing: ?*struct_agp_vstore) void;
pub extern fn agp_activate_vstore_multi(backing: [*c]?*struct_agp_vstore, n: usize) void;
pub extern fn agp_blendstate(mode: arcan_blendfunc) void;
pub extern fn agp_deactivate_vstore() void;
pub extern fn agp_default_shader(t: c_uint) agp_shader_id;
pub extern fn agp_disable_stencil() void;
pub extern fn agp_draw_vobj(x1: f32, y1: f32, x2: f32, y2: f32, txcos: [*c]const f32, modelview: [*c]const f32) void;
pub extern fn agp_drop_mesh(s: ?*struct_agp_mesh_store) void;
pub extern fn agp_drop_rendertarget(tgt: ?*struct_agp_rendertarget) void;
pub extern fn agp_drop_vstore(backing: ?*struct_agp_vstore) void;
pub extern fn agp_empty_vstore(backing: ?*struct_agp_vstore, w: usize, h: usize) void;
pub extern fn agp_null_vstore(backing: ?*struct_agp_vstore) void;
pub extern fn agp_pipeline_hint(mode: c_uint) void;
pub extern fn agp_poll_readback(vs: ?*struct_agp_vstore) struct_asynch_readback_meta;
pub extern fn agp_prepare_stencil() void;
pub extern fn agp_readback_synchronous(dst: ?*struct_agp_vstore) void;
pub extern fn agp_rendertarget_clear() void;
pub extern fn agp_rendertarget_clearcolor(tgt: ?*struct_agp_rendertarget, r: f32, g: f32, b: f32, a: f32) void;
pub extern fn agp_rendertarget_proxy(tgt: ?*struct_agp_rendertarget, proxy_state: ?*const fn (?*struct_agp_rendertarget, usize) callconv(.c) bool, tag: usize) void;
pub extern fn agp_rendertarget_swapstore(tgt: ?*struct_agp_rendertarget, vstore: ?*struct_agp_vstore) bool;
pub extern fn agp_request_readback(vs: ?*struct_agp_vstore) void;
pub extern fn agp_resize_rendertarget(tgt: ?*struct_agp_rendertarget, neww: usize, newh: usize) void;
pub extern fn agp_resize_vstore(backing: ?*struct_agp_vstore, w: usize, h: usize) void;
pub extern fn agp_save_output(w: usize, h: usize, dst: [*c]av_pixel, dsz: usize) void;
pub extern fn agp_setup_rendertarget(vs: ?*struct_agp_vstore, mode: c_uint) ?*struct_agp_rendertarget;
pub extern fn agp_shader_activate(shid: agp_shader_id) c_int;
pub extern fn agp_shader_envv(slot: c_uint, value: ?*anyopaque, size: usize) c_int;
pub extern fn agp_shader_flush() void;
pub extern fn agp_shader_forceunif(label: [*c]const u8, utype: c_uint, value: ?*anyopaque) void;
pub extern fn agp_shader_rebuild_all() void;
pub extern fn agp_shader_valid(shid: agp_shader_id) bool;
pub extern fn agp_slice_synch(backing: ?*struct_agp_vstore, n_slices: usize, slices: [*c]?*struct_agp_vstore) bool;
pub extern fn agp_slice_vstore(backing: ?*struct_agp_vstore, n_slices: usize, base_size: usize, state: c_uint) bool;
pub extern fn agp_submit_mesh(mesh: ?*struct_agp_mesh_store, flags: c_uint) void;
pub extern fn agp_update_vstore(backing: ?*struct_agp_vstore, copy: bool) void;

// ══════════════════════════════════════════════════════════════════════════════
// Engine functions
// ══════════════════════════════════════════════════════════════════════════════

pub extern fn arcan_fatal(msg: [*c]const u8, ...) callconv(.c) void;
pub extern fn arcan_alloc_mem(sz: usize, memtype: c_uint, hint: c_uint, alignment: c_uint) ?*anyopaque;
pub extern fn arcan_alloc_fillmem(src: ?*const anyopaque, sz: usize, memtype: c_uint, hint: c_uint, alignment: c_uint) ?*anyopaque;
pub extern fn arcan_random(dst: [*c]u8, sz: usize) void;
pub extern fn arcan_timemillis() c_longlong;
pub extern fn arcan_frametime() i64;

// Event functions
pub extern fn arcan_event_defaultctx() ?*struct_arcan_evctx;
pub extern fn arcan_event_init(ctx: ?*struct_arcan_evctx) void;
pub extern fn arcan_event_deinit(ctx: ?*struct_arcan_evctx, flush: bool) void;
pub extern fn arcan_event_enqueue(ctx: ?*struct_arcan_evctx, ev: *const arcan_event) c_int;
pub extern fn arcan_event_purge() void;

// Semaphore functions
pub extern fn arcan_sem_init(sem: *sem_handle, value: c_uint) c_int;
pub extern fn arcan_sem_post(sem: sem_handle) c_int;
pub extern fn arcan_sem_wait(sem: sem_handle) c_int;

// Audio functions
pub extern fn arcan_audio_play(id: arcan_aobj_id, gain_override: bool, gain: f32, tag: isize) arcan_errc;
pub extern fn arcan_audio_purge(save: [*c]arcan_aobj_id, save_count: usize) void;

// Image loading
pub extern fn arcan_open_resource(name: [*c]const u8) data_source;
pub extern fn arcan_release_resource(ds: *data_source) void;
pub extern fn arcan_map_resource(ds: *data_source, wr: bool) map_region;
pub extern fn arcan_release_map(region: map_region) bool;
pub extern fn arcan_img_decode(hint: [*c]const u8, inbuf: [*c]u8, inbuf_sz: usize, outbuf: *[*c]u32, outw: *usize, outh: *usize, outm: *struct_arcan_img_meta, vflip: bool) arcan_errc;
pub extern fn arcan_img_repack(inbuf: [*c]u32, inw: usize, inh: usize) [*c]av_pixel;

// Render / font functions
pub extern fn arcan_renderfun_outputdensity(vppcm: f32, hppcm: f32) void;
pub extern fn arcan_renderfun_release_fontgroup(group: ?*anyopaque) void;
pub extern fn arcan_renderfun_renderfmtstr(message: [*c]const u8, dst: arcan_vobj_id, pot: bool, n_lines: *c_uint, lineheights: *[*c]struct_renderline_meta, dw: *usize, dh: *usize, d_sz: *u32, maxw: *usize, maxh: *usize, norender: bool) [*c]av_pixel;
pub extern fn arcan_renderfun_renderfmtstr_extended(message: [*c]const [*c]const u8, dst: arcan_vobj_id, pot: bool, n_lines: *c_uint, lineheights: *[*c]struct_renderline_meta, dw: *usize, dh: *usize, d_sz: *u32, maxw: *usize, maxh: *usize, norender: bool) [*c]av_pixel;
pub extern fn arcan_renderfun_stretchblit(src: [*c]u8, inw: c_int, inh: c_int, dst: [*c]u32, dstw: usize, dsth: usize, flipv: c_int) c_int;

// Video object internal functions
pub extern fn arcan_resolve_vidprop(vobj: ?*arcan_vobject, lerp: f32, props: *surface_properties) void;
pub extern fn arcan_ffunc_lookup(ind: ffunc_ind) ?*const fn (cmd: c_uint, buf: [*c]av_pixel, buf_sz: usize, width: u16, height: u16, mode: c_uint, state: vfunc_state, srcid: arcan_vobj_id) callconv(.c) c_uint;
pub extern fn arcan_video_deleteobject(id: arcan_vobj_id) arcan_errc;
pub extern fn arcan_video_forceupdate(vid: arcan_vobj_id, ignoredirty: bool) arcan_errc;
pub extern fn arcan_video_reset_fontcache() void;

// 3D functions
pub extern fn arcan_3d_refresh(camtag: arcan_vobj_id, cell: ?*struct_arcan_vobject_litem, frag: f32) ?*struct_arcan_vobject_litem;
pub extern fn arcan_3d_obj_bb_intersect(cam: arcan_vobj_id, obj: arcan_vobj_id, x: c_int, y: c_int) bool;

// Platform video functions
pub extern fn platform_video_init(w: u16, h: u16, bpp: u8, fs: bool, frames: bool, caption: [*c]const u8) bool;
pub extern fn platform_video_shutdown() void;
pub extern fn platform_video_prepare_external() void;
pub extern fn platform_video_restore_external() void;
pub extern fn platform_video_decay() usize;
pub extern fn platform_video_dimensions() struct_monitor_mode;
pub extern fn platform_video_query_displays() void;

// TTF
pub extern fn TTF_Quit() void;

// Libc functions
pub extern fn memmove(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;
pub extern fn strdup(s: [*c]const u8) [*c]u8;
pub extern fn pthread_create(thread: *pthread_t, attr: ?*const anyopaque, start_routine: ?*const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) c_int;
pub extern fn pthread_join(thread: pthread_t, retval: ?*?*anyopaque) c_int;
