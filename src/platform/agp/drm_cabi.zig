// Hand-written replacement for vk_gbm_kms.zig's @cImport of xf86drm.h +
// xf86drmMode.h. The no-LLVM self-hosted fork can't run @cImport, so
// this file redeclares the libdrm types / constants / function prototypes
// used by vk_gbm_kms.zig. Symbols resolve against dl_drm.zig at link time
// (which in turn dlopens libdrm.so.2 at runtime — same pattern as dl_xkb
// and dl_openal).
//
// Structs are extern and match libdrm 2.4.x layouts exactly (check against
// /usr/include/xf86drm.h and /usr/include/xf86drmMode.h). Fields we don't
// touch are still present so layout / sizeof invariants hold for any code
// that reads/writes through these pointers.

// ── constants ───────────────────────────────────────────────────────

// drmModeConnection enum (xf86drmMode.h)
pub const DRM_MODE_CONNECTED: c_int = 1;
pub const DRM_MODE_DISCONNECTED: c_int = 2;
pub const DRM_MODE_UNKNOWNCONNECTION: c_int = 3;

// drm_mode.h
pub const DRM_MODE_TYPE_PREFERRED: u32 = 1 << 3;
pub const DRM_MODE_PAGE_FLIP_EVENT: u32 = 0x01;
pub const DRM_DISPLAY_MODE_LEN: usize = 32;
pub const DRM_PROP_NAME_LEN: usize = 32;

// drmModeObject type tags (drm_mode.h)
pub const DRM_MODE_OBJECT_CRTC: u32 = 0xcccccccc;
pub const DRM_MODE_OBJECT_CONNECTOR: u32 = 0xc0c0c0c0;
pub const DRM_MODE_OBJECT_ENCODER: u32 = 0xe0e0e0e0;
pub const DRM_MODE_OBJECT_PLANE: u32 = 0xeeeeeeee;
pub const DRM_MODE_OBJECT_FB: u32 = 0xfbfbfbfb;
pub const DRM_MODE_OBJECT_BLOB: u32 = 0xbbbbbbbb;
pub const DRM_MODE_OBJECT_PROPERTY: u32 = 0xb0b0b0b0;

// ── types ───────────────────────────────────────────────────────────

pub const drmModeModeInfo = extern struct {
    clock: u32,
    hdisplay: u16, hsync_start: u16, hsync_end: u16, htotal: u16, hskew: u16,
    vdisplay: u16, vsync_start: u16, vsync_end: u16, vtotal: u16, vscan: u16,
    vrefresh: u32,
    flags: u32,
    type: u32,
    name: [DRM_DISPLAY_MODE_LEN]u8,
};

pub const drmModeRes = extern struct {
    count_fbs: c_int,
    fbs: [*c]u32,
    count_crtcs: c_int,
    crtcs: [*c]u32,
    count_connectors: c_int,
    connectors: [*c]u32,
    count_encoders: c_int,
    encoders: [*c]u32,
    min_width: u32, max_width: u32,
    min_height: u32, max_height: u32,
};

pub const drmModeConnector = extern struct {
    connector_id: u32,
    encoder_id: u32,
    connector_type: u32,
    connector_type_id: u32,
    connection: c_int, // drmModeConnection enum
    mmWidth: u32, mmHeight: u32,
    subpixel: c_int, // drmModeSubPixel enum
    count_modes: c_int,
    modes: [*c]drmModeModeInfo,
    count_props: c_int,
    props: [*c]u32,
    prop_values: [*c]u64,
    count_encoders: c_int,
    encoders: [*c]u32,
};

pub const drmModeEncoder = extern struct {
    encoder_id: u32,
    encoder_type: u32,
    crtc_id: u32,
    possible_crtcs: u32,
    possible_clones: u32,
};

pub const drmModeCrtc = extern struct {
    crtc_id: u32,
    buffer_id: u32,
    x: u32, y: u32,
    width: u32, height: u32,
    mode_valid: c_int,
    mode: drmModeModeInfo,
    gamma_size: c_int,
};

pub const drmModeObjectProperties = extern struct {
    count_props: u32,
    props: [*c]u32,
    prop_values: [*c]u64,
};

pub const drmModePropertyEnum = extern struct {
    value: u64,
    name: [DRM_PROP_NAME_LEN]u8,
};

pub const drmModePropertyRes = extern struct {
    prop_id: u32,
    flags: u32,
    name: [DRM_PROP_NAME_LEN]u8,
    count_values: c_int,
    values: [*c]u64,
    count_enums: c_int,
    enums: [*c]drmModePropertyEnum,
    count_blobs: c_int,
    blob_ids: [*c]u32,
};

pub const drmEventContext = extern struct {
    version: c_int,
    vblank_handler: ?*const fn (c_int, c_uint, c_uint, c_uint, ?*anyopaque) callconv(.c) void,
    page_flip_handler: ?*const fn (c_int, c_uint, c_uint, c_uint, ?*anyopaque) callconv(.c) void,
    page_flip_handler2: ?*const fn (c_int, c_uint, c_uint, c_uint, c_uint, ?*anyopaque) callconv(.c) void,
    sequence_handler: ?*const fn (c_int, u64, u64, u64) callconv(.c) void,
};

// ── functions — linked against dl_drm.zig shim ──────────────────────

pub extern "c" fn drmSetMaster(fd: c_int) c_int;
pub extern "c" fn drmDropMaster(fd: c_int) c_int;

pub extern "c" fn drmModeGetResources(fd: c_int) ?*drmModeRes;
pub extern "c" fn drmModeFreeResources(ptr: ?*drmModeRes) void;
pub extern "c" fn drmModeGetConnector(fd: c_int, connector_id: u32) ?*drmModeConnector;
pub extern "c" fn drmModeFreeConnector(ptr: ?*drmModeConnector) void;
pub extern "c" fn drmModeGetEncoder(fd: c_int, encoder_id: u32) ?*drmModeEncoder;
pub extern "c" fn drmModeFreeEncoder(ptr: ?*drmModeEncoder) void;
pub extern "c" fn drmModeGetCrtc(fd: c_int, crtc_id: u32) ?*drmModeCrtc;
pub extern "c" fn drmModeFreeCrtc(ptr: ?*drmModeCrtc) void;

pub extern "c" fn drmModeSetCrtc(
    fd: c_int, crtc_id: u32, buffer_id: u32,
    x: u32, y: u32,
    connectors: ?*u32, count: c_int,
    mode: ?*drmModeModeInfo,
) c_int;

pub extern "c" fn drmModeAddFB2(
    fd: c_int, width: u32, height: u32,
    pixel_format: u32,
    bo_handles: *const [4]u32,
    pitches: *const [4]u32,
    offsets: *const [4]u32,
    buf_id: *u32,
    flags: u32,
) c_int;

pub extern "c" fn drmModeAddFB2WithModifiers(
    fd: c_int, width: u32, height: u32,
    pixel_format: u32,
    bo_handles: *const [4]u32,
    pitches: *const [4]u32,
    offsets: *const [4]u32,
    modifier: *const [4]u64,
    buf_id: *u32,
    flags: u32,
) c_int;

pub extern "c" fn drmModeRmFB(fd: c_int, buffer_id: u32) c_int;

pub extern "c" fn drmModePageFlip(
    fd: c_int, crtc_id: u32, fb_id: u32,
    flags: u32, user_data: ?*anyopaque,
) c_int;

pub extern "c" fn drmHandleEvent(fd: c_int, evctx: *drmEventContext) c_int;

pub extern "c" fn drmPrimeFDToHandle(fd: c_int, prime_fd: c_int, handle_out: *u32) c_int;

// MAY-201: connector-property API used by vk_gbm_kms.setDpms to pin the
// DPMS property to ON at boot. drmModeObjectGetProperties enumerates all
// properties on a given object id (object_type = DRM_MODE_OBJECT_CONNECTOR
// here); drmModeGetProperty resolves a prop_id to its name + flags;
// drmModeConnectorSetProperty writes a new value. The dl_drm.zig shim
// dlopens these alongside the rest of libdrm.
pub extern "c" fn drmModeObjectGetProperties(
    fd: c_int, object_id: u32, object_type: u32,
) ?*drmModeObjectProperties;
pub extern "c" fn drmModeFreeObjectProperties(ptr: ?*drmModeObjectProperties) void;
pub extern "c" fn drmModeGetProperty(fd: c_int, prop_id: u32) ?*drmModePropertyRes;
pub extern "c" fn drmModeFreeProperty(ptr: ?*drmModePropertyRes) void;
pub extern "c" fn drmModeConnectorSetProperty(
    fd: c_int, connector_id: u32, property_id: u32, value: u64,
) c_int;
