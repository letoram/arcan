// Pure Zig port of engine/arcan_renderfun.c — format string text rendering,
// font cache, font groups, stretch blit, TUI synch.
//
// All opaque struct access via extern fn declarations or byte-offset accessors.
// The stb_image_resize2 implementation stays in C (included via the .c file's
// #define STB_IMAGE_RESIZE_IMPLEMENTATION) and is called here as extern fn.

const std = @import("std");
const c = @import("posix");

// Constants

const ARCAN_FONT_CACHE_LIMIT: usize = 8;

const TTF_HINTING_NORMAL: c_int = 3;
const TTF_STYLE_NORMAL: c_int = 0x00;
const TTF_STYLE_BOLD: c_int = 0x01;
const TTF_STYLE_ITALIC: c_int = 0x02;
const TTF_STYLE_UNDERLINE: c_int = 0x04;

const EPSILON: f32 = 0.000001;
const BADFD: c_int = -1;

const TEXT_EMBEDDEDICON_MAXW: usize = 256;
const TEXT_EMBEDDEDICON_MAXH: usize = 256;

const CONST_MAX_SURFACEW: usize = 8192;
const CONST_MAX_SURFACEH: usize = 4096;

const ARCAN_OK: c_int = 0;

// mem enums (C values)
const ARCAN_MEM_VBUFFER: c_int = 1;
const ARCAN_MEM_VSTRUCT: c_int = 2;
const ARCAN_MEM_BZERO: c_int = 1;
const ARCAN_MEM_TEMPORARY: c_int = 2;
const ARCAN_MEM_NONFATAL: c_int = 8;
const ARCAN_MEMALIGN_PAGE: c_int = 1;
const ARCAN_MEMALIGN_NATURAL: c_int = 0;

// resource namespace flags
const RESOURCE_SYS_FONT: c_int = 128;
const RESOURCE_APPL_SHARED: c_int = 4;
const RESOURCE_APPL: c_int = 2;
const ARES_FILE: c_int = 1;

// STBIR pixel layout
const STBIR_RGBA: c_int = 4;

// TXSTATE
const TXSTATE_TEX2D: c_int = 1;

// stream type
const STREAM_RAW_DIRECT: c_int = 1;

const av_pixel = u32;
const file_handle = c_int;

// C struct types

const data_source = extern struct {
    fd: c_int = BADFD,
    start: c_longlong = 0,
    len: c_longlong = 0,
    source: [*c]u8 = null,
};

const map_region = extern struct {
    ptr: [*c]u8 = null,
    zbyte: u8 = 0,
    sz: usize = 0,
    mmap: bool = false,
};

// Extern C functions

extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn arcan_alloc_mem(sz: usize, memtype: c_int, hint: c_int, alignment: c_int) ?*anyopaque;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn arcan_find_resource(name: [*c]const u8, ns: c_int, rtype: c_int, outpath: ?*anyopaque) [*c]u8;
extern fn arcan_open_resource(name: [*c]const u8) data_source;
extern fn arcan_map_resource(src: *data_source, wr: bool) map_region;
extern fn arcan_release_resource(src: *data_source) void;
extern fn arcan_release_map(region: map_region) bool;

extern fn arcan_img_decode(
    hint: [*c]const u8,
    inbuf: [*c]u8,
    inbuf_sz: usize,
    outbuf: *?[*]u32,
    outw: *usize,
    outh: *usize,
    meta: ?*anyopaque,
    raw: bool,
) c_int;
extern fn arcan_img_repack(buf: [*]u32, w: usize, h: usize) ?[*]u32;

// stbir_resize_uint8_linear is provided by the STB implementation (compiled from C helper)
extern fn stbir_resize_uint8_linear(
    input: [*c]const u8,
    input_w: c_int,
    input_h: c_int,
    input_stride: c_int,
    output: [*c]u8,
    output_w: c_int,
    output_h: c_int,
    output_stride: c_int,
    pixel_layout: c_int,
) ?*anyopaque;

// TTF functions
extern fn TTF_OpenFont(file: [*c]const u8, ptsize: c_int, hdpi: u16, vdpi: u16) ?*anyopaque;
extern fn TTF_OpenFontFD(fd: c_int, ptsize: c_int, hdpi: u16, vdpi: u16) ?*anyopaque;
extern fn TTF_CloseFont(font: *anyopaque) void;
extern fn TTF_FontAscent(font: *anyopaque) c_int;
extern fn TTF_FontDescent(font: *anyopaque) c_int;
extern fn TTF_FontHeight(font: *anyopaque) c_int;
extern fn TTF_FontLineSkip(font: *anyopaque) c_int;
extern fn TTF_SetFontHinting(font: *anyopaque, hinting: c_int) void;
extern fn TTF_SetFontStyle(font: *anyopaque, style: c_int) void;
extern fn TTF_SizeUTF8chain(
    fonts: [*]?*anyopaque,
    n: usize,
    text: [*c]const u8,
    w: *c_int,
    h: *c_int,
    style: c_int,
) c_int;
extern fn TTF_RenderUTF8chain(
    dst: [*]u32,
    w: usize,
    h: usize,
    pitch: usize,
    fonts: [*]?*anyopaque,
    n: usize,
    text: [*c]const u8,
    col: [*]const u8,
    style: c_int,
) bool;
extern fn TTF_ReplaceFont(font: *anyopaque, pt: c_int, hdpi: u16, vdpi: u16) ?*anyopaque;
extern fn TTF_ProbeFont(font: *anyopaque, dw: *usize, dh: *usize) void;

// Pixelfont functions
extern fn tui_pixelfont_open(limit: usize) ?*anyopaque;
extern fn tui_pixelfont_close(ctx: *anyopaque) void;
extern fn tui_pixelfont_setsz(ctx: *anyopaque, px_sz: usize, w: *usize, h: *usize) void;
extern fn tui_pixelfont_draw(
    ctx: *anyopaque,
    dst: [*]u32,
    pitch: usize,
    cp: u32,
    x: usize,
    y: usize,
    fg: u32,
    bg: u32,
    maxx: usize,
    maxy: usize,
    bgign: bool,
) void;
extern fn tui_pixelfont_valid(buf: [*]u8, buf_sz: usize) bool;

extern fn UTF8_to_UTF32(out: [*]u32, in_buf: [*c]const u8, len: usize) c_int;

// TUI raster functions
extern fn tui_raster_setup(cell_w: usize, cell_h: usize) ?*anyopaque;
extern fn tui_raster_setfont(ctx: *anyopaque, src: [*]?*anyopaque, n_fonts: usize) void;
extern fn tui_raster_free(ctx: ?*anyopaque) void;
// tui_raster_renderagp, tui_screen_tpack_sz, tui_screen_tpack are used
// by arcan_video_tuisynch which stays in the C helper file.

// AGP functions (used by process_chain when dst_vobj is set)
extern fn agp_readback_synchronous(vs: *anyopaque) void;
extern fn agp_resize_vstore(vs: *anyopaque, w: usize, h: usize) void;

// Video object functions
extern fn arcan_video_getobject(id: c_longlong) ?*anyopaque;

// Math functions
extern fn arcan_mm_to_pt(mm: f32) f32;
extern fn arcan_pt_to_mm(pt: f32) f32;

// libc
extern fn close(fd: c_int) c_int;
extern fn free(ptr: ?*anyopaque) void;
extern fn malloc(sz: usize) ?*anyopaque;
extern fn strdup(s: [*c]const u8) [*c]u8;
extern fn strcmp(a: [*c]const u8, b: [*c]const u8) c_int;
extern fn strlen(s: [*c]const u8) usize;
extern fn strtol(s: [*c]const u8, endp: ?*[*c]u8, base: c_int) c_long;
extern fn strtoul(s: [*c]const u8, endp: ?*[*c]u8, base: c_int) c_ulong;
extern fn memset(dst: ?*anyopaque, val: c_int, len: usize) ?*anyopaque;
extern fn memcpy(dst: ?*anyopaque, src: ?*const anyopaque, len: usize) ?*anyopaque;
extern fn memmove(dst: ?*anyopaque, src: ?*const anyopaque, len: usize) ?*anyopaque;
extern fn isxdigit(ch: c_int) c_int;
extern fn isdigit(ch: c_int) c_int;
extern fn isspace(ch: c_int) c_int;
extern fn open(path: [*c]const u8, flags: c_int, ...) callconv(.c) c_int;
extern fn roundf(x: f32) f32;

const O_RDONLY: c_int = 0;

// Inline helpers

inline fn RGBA(r: u8, g_arg: u8, b: u8, a: u8) u32 {
    return (@as(u32, a) << 24) | (@as(u32, r) << 16) | (@as(u32, g_arg) << 8) | @as(u32, b);
}

inline fn PT_TO_HPX(pt: anytype) f32 {
    return @as(f32, @floatFromInt(pt)) * (1.0 / 72.0) * default_hdpi;
}

inline fn PT_TO_VPX(pt: anytype) f32 {
    return @as(f32, @floatFromInt(pt)) * (1.0 / 72.0) * default_vdpi;
}

fn fabsf(x: f32) f32 {
    return @abs(x);
}

// Internal structs

const font_entry_chain = struct {
    data: [4]?*anyopaque = .{ null, null, null, null },
    fd: [4]file_handle = .{ BADFD, BADFD, BADFD, BADFD },
    count: usize = 0,
};

const font_entry = struct {
    chain: font_entry_chain = .{},
    identifier: [*c]u8 = null,
    size: usize = 0,
    vdpi: f32 = 0,
    hdpi: f32 = 0,
    usecount: u32 = 0,
};

const img_cons = struct {
    w: c_uint = 0,
    h: c_uint = 0,
    bpp: u8 = 0,
};

const text_format = struct {
    // font specification
    font: ?*font_entry = null,
    col: [4]u8 = .{ 0xff, 0xff, 0xff, 0xff },
    style: c_int = 0,
    alpha: u8 = 0,

    // used in the fallback case when !font
    pt_size: usize = 0,
    px_skip: usize = 0,

    // for forced loading of images
    surf: struct {
        w: usize = 0,
        h: usize = 0,
        buf: ?[*]av_pixel = null,
    } = .{},
    imgcons: img_cons = .{},

    // temporary pointer-alias into line of text where the format was extracted
    endofs: [*c]u8 = null,

    // metrics
    lineheight: c_int = 0,
    height: c_int = 0,
    skip: c_int = 0,
    ascent: c_int = 0,
    descent: c_int = 0,

    // metric-overrides
    halign: usize = 0,

    // whitespace management
    cr: bool = false,
    tab: u8 = 0,
    newline: u8 = 0,
};

const rcell = struct {
    width: c_uint = 0,
    height: c_uint = 0,
    skipv: c_int = 0,
    ascent: c_int = 0,
    descent: c_int = 0,

    data: extern union {
        surf: extern struct {
            w: usize,
            h: usize,
            buf: ?[*]av_pixel,
        },
        format: extern struct {
            newline: u8,
            tab: u8,
            cr: bool,
        },
    } = .{ .surf = .{ .w = 0, .h = 0, .buf = null } },

    next: ?*rcell = null,
};

const renderline_meta = extern struct {
    height: c_int = 0,
    ystart: c_int = 0,
    ascent: c_int = 0,
};

// tui_font as used by fontgroup (mirrors struct tui_font from raster.h)
// MUST be extern struct to match C layout (byte-offset access via engine_offsets.zig)
const tui_font = extern struct {
    font_data: ?*anyopaque = null, // union { bitmap, truetype } at offset 0
    vector: bool = false, // offset 8
    fd: c_int = -1, // offset 12
    hint: c_int = 0, // offset 16
};

const fontgroup = struct {
    font: ?[*]tui_font = null,
    raster: ?*anyopaque = null,
    used: usize = 0,
    w: usize = 0,
    h: usize = 0,
    ppcm: f32 = 0,
    size_mm: f32 = 0,
    is_builtin: bool = false, // tracks if font == &builtin_bitmap
};

// Static state

var default_hint: c_int = TTF_HINTING_NORMAL;
var default_vdpi: f32 = 72.0;
var default_hdpi: f32 = 72.0;

// for embedded blit
var vid_ofs: i64 = 0;

var last_style: text_format = .{
    .col = .{ 0xff, 0xff, 0xff, 0xff },
};

var font_cache_size: c_uint = ARCAN_FONT_CACHE_LIMIT;
var builtin_bitmap_data: tui_font = .{};
var font_cache: [ARCAN_FONT_CACHE_LIMIT]font_entry = [_]font_entry{.{}} ** ARCAN_FONT_CACHE_LIMIT;

// nexthigher

fn nexthigher(k_arg: u16) u16 {
    var k = k_arg -% 1;
    comptime var i: u5 = 1;
    inline while (i < 16) : (i *= 2) {
        k = k | (k >> @intCast(i));
    }
    return k +% 1;
}

// Public functions

// IMPORTANT: `fd` is a BORROWED handle into font_cache[0]. Callers must
// NOT close it. To take ownership (e.g. handing to fontgroup_replace,
// arcan_renderfun_fontgroup, or platform_fsrv_pushfd-then-close), `dup()`
// it first. Bug 0125 root cause was lua targetfonthint closing this
// borrowed fd, which silently invalidated the cache slot — every
// subsequent set_font_slot caller ended up with an EBADF on a stale fd.
export fn arcan_video_fontdefaults(
    fd: ?*file_handle,
    pt_sz: ?*c_int,
    hint: ?*c_int,
) void {
    if (fd) |f| f.* = font_cache[0].chain.fd[0];
    if (pt_sz) |p| p.* = @intCast(font_cache[0].size);
    if (hint) |h| h.* = default_hint;
}

export fn arcan_renderfun_outputdensity(hppcm: f32, vppcm: f32) void {
    default_hdpi = if (vppcm > EPSILON) 2.54 * vppcm else 72.0;
    default_vdpi = if (hppcm > EPSILON) 2.54 * hppcm else 72.0;
}

export fn arcan_renderfun_vidoffset(ofs: i64) void {
    vid_ofs = ofs;
}

// size_font_chain

fn size_font_chain(
    cstyle: *text_format,
    base: [*c]const u8,
    w: *c_int,
    h: *c_int,
) c_int {
    if (cstyle.font) |fnt| {
        if (fnt.chain.data[0] != null) {
            return TTF_SizeUTF8chain(
                &fnt.chain.data,
                fnt.chain.count,
                base,
                w,
                h,
                cstyle.style,
            );
        }
    }
    // fallback: bitmap font
    const blen = strlen(base);
    h.* = cstyle.height;
    w.* = @intCast(cstyle.px_skip * blen);
    return 0;
}

// update_style

fn update_style(dst: *text_format, font_opt: ?*font_entry) void {
    // if the font has not been set, use the built-in bitmap one
    const use_bitmap = if (font_opt) |f| f.chain.data[0] == null else true;
    if (use_bitmap) {
        var h: usize = 0;
        const px_sz = PT_TO_HPX(dst.pt_size);
        const px_sz_int: usize = @intFromFloat(@floor(px_sz));
        if (builtin_bitmap_data.font_data) |bmp| {
            tui_pixelfont_setsz(bmp, px_sz_int, &dst.px_skip, &h);
        }
        const h_half: c_int = @intCast(h >> 1);
        dst.descent = h_half;
        dst.ascent = h_half;
        dst.height = @intCast(h);
        const skip_val: c_int = @intFromFloat(@trunc(px_sz * 1.5 - px_sz));
        dst.skip = if (skip_val == 0) 1 else skip_val;
        dst.font = null;
        return;
    }

    // otherwise query the font for the specific metrics
    const font = font_opt.?;
    dst.ascent = TTF_FontAscent(font.chain.data[0].?);
    dst.descent = -1 * TTF_FontDescent(font.chain.data[0].?);
    dst.height = TTF_FontHeight(font.chain.data[0].?);
    dst.skip = dst.height - TTF_FontLineSkip(font.chain.data[0].?);
    dst.font = font;
}

// zap_slot

fn zap_slot(i: usize) void {
    for (0..font_cache[i].chain.count) |j| {
        if (font_cache[i].chain.fd[j] != BADFD) {
            _ = close(font_cache[i].chain.fd[j]);
            font_cache[i].chain.fd[j] = BADFD;
        }
        if (font_cache[i].chain.data[j]) |d| {
            TTF_CloseFont(d);
            font_cache[i].chain.data[j] = null;
        }
    }
    free(@ptrCast(font_cache[i].identifier));
    font_cache[i] = .{};
}

// set_style

fn set_style(dst: *text_format, font: ?*font_entry) void {
    dst.newline = 0;
    dst.tab = 0;
    dst.cr = false;
    dst.col = .{ 0xff, 0xff, 0xff, 0xff };
    update_style(dst, font);
}

// grab_font

fn grab_font(fname_arg: ?[*c]const u8, size: usize) ?*font_entry {
    var leasti: usize = 1;
    var leastv: c_int = -1;

    var fname = fname_arg;

    // empty identifier - use default (slot 0)
    if (fname == null) {
        fname = font_cache[0].identifier;
        if (fname == null)
            return null;
    }
    // special case, set default slot to loaded font
    else if (font_cache[0].identifier == null) {
        const fd = open(fname.?, O_RDONLY);
        if (BADFD == fd)
            return null;
        if (!arcan_video_defaultfont(fname.?, fd, @intCast(size), 2, false))
            _ = close(fd);
    }

    // match / track
    var matchf: ?*font_entry = null;
    var i: usize = 0;
    while (i < @as(usize, font_cache_size) and font_cache[i].chain.data[0] != null) : (i += 1) {
        if (i != 0 and @as(c_int, @intCast(font_cache[i].usecount)) < leastv and
            &font_cache[i] != last_style.font)
        {
            leasti = i;
            leastv = @intCast(font_cache[i].usecount);
        }

        if (strcmp(font_cache[i].identifier, fname.?) == 0) {
            if (font_cache[i].chain.fd[0] != BADFD) {
                matchf = &font_cache[i];
            }

            if (font_cache[i].size == size and
                fabsf(font_cache[i].vdpi - default_vdpi) < EPSILON and
                fabsf(font_cache[i].hdpi - default_hdpi) < EPSILON)
            {
                font_cache[i].usecount += 1;
                // goto done equivalent
                const font = &font_cache[i];
                for (0..font.chain.count) |ci| {
                    if (font.chain.data[ci]) |d|
                        TTF_SetFontHinting(d, default_hint);
                }
                return font;
            }
        }
    }

    // rebuild chain
    var newch: font_entry_chain = .{};

    if (matchf) |mf| {
        if (i == @as(usize, font_cache_size)) {
            i = leasti;
        }
        var count: usize = 0;
        for (0..mf.chain.count) |mi| {
            const hdpi_u16: u16 = @intFromFloat(default_hdpi);
            const vdpi_u16: u16 = @intFromFloat(default_vdpi);
            newch.data[count] = TTF_OpenFontFD(mf.chain.fd[mi], @intCast(size), hdpi_u16, vdpi_u16);
            newch.fd[count] = BADFD;
            if (newch.data[count] == null) {
                arcan_warning("grab_font(), couldn't duplicate entire fallback chain (fail @ ind %d)\n", @as(c_int, @intCast(mi)));
            } else {
                count += 1;
            }
        }
        newch.count = count;
    } else {
        const hdpi_u16: u16 = @intFromFloat(default_hdpi);
        const vdpi_u16: u16 = @intFromFloat(default_vdpi);
        newch.data[0] = TTF_OpenFont(fname.?, @intCast(size), hdpi_u16, vdpi_u16);
        newch.fd[0] = BADFD;
        if (newch.data[0] != null)
            newch.count = 1;
    }

    if (newch.count == 0) {
        arcan_warning("grab_font(), Open Font (%s,%d) failed\n", fname.?, @as(c_int, @intCast(size)));
        return null;
    }

    // replace?
    if (i == @as(usize, font_cache_size)) {
        i = leasti;
        zap_slot(i);
    }

    // update counters
    font_cache[i].identifier = strdup(fname.?);
    font_cache[i].usecount += 1;
    font_cache[i].size = size;
    font_cache[i].vdpi = default_vdpi;
    font_cache[i].hdpi = default_hdpi;
    font_cache[i].chain = newch;
    const font = &font_cache[i];

    for (0..font.chain.count) |ci| {
        if (font.chain.data[ci]) |d|
            TTF_SetFontHinting(d, default_hint);
    }
    return font;
}

// arcan_video_defaultfont

export fn arcan_video_defaultfont(
    ident: [*c]const u8,
    fd: file_handle,
    sz: c_int,
    hint: c_int,
    append: bool,
) bool {
    if (BADFD == fd)
        return false;

    const hdpi_u16: u16 = @intFromFloat(default_hdpi);
    const vdpi_u16: u16 = @intFromFloat(default_vdpi);
    const font_ptr = TTF_OpenFontFD(fd, sz, hdpi_u16, vdpi_u16);
    if (font_ptr == null)
        return false;

    if (-1 != default_hint) {
        default_hint = hint;
    }

    if (!append) {
        zap_slot(0);
        font_cache[0].identifier = strdup(ident);
        font_cache[0].size = @intCast(sz);
        font_cache[0].chain.data[0] = font_ptr;
        font_cache[0].chain.fd[0] = fd;
        font_cache[0].chain.count = 1;
        set_style(&last_style, &font_cache[0]);
    } else {
        var dst_i = font_cache[0].chain.count;
        const lim: usize = 4; // COUNT_OF(font_cache[0].chain.data)
        if (dst_i == lim) {
            _ = close(font_cache[0].chain.fd[dst_i - 1]);
            TTF_CloseFont(font_cache[0].chain.data[dst_i - 1].?);
        } else {
            dst_i += 1;
        }

        font_cache[0].chain.count = dst_i;
        font_cache[0].chain.fd[dst_i - 1] = fd;
        font_cache[0].chain.data[dst_i - 1] = font_ptr;
    }

    return true;
}

// arcan_video_reset_fontcache

var fontcache_init: bool = false;

export fn arcan_video_reset_fontcache() void {
    if (!fontcache_init) {
        fontcache_init = true;
        builtin_bitmap_data.font_data = tui_pixelfont_open(64);
        for (0..ARCAN_FONT_CACHE_LIMIT) |i| {
            font_cache[i].chain.fd[0] = BADFD;
        }
    } else {
        for (0..ARCAN_FONT_CACHE_LIMIT) |i| {
            zap_slot(i);
        }
    }
}

// text_loadimage

fn text_loadimage(dst: *text_format, infn: [*c]const u8, cons_arg: img_cons) void {
    var cons = cons_arg;
    const path: [*c]u8 = arcan_find_resource(
        infn,
        RESOURCE_SYS_FONT | RESOURCE_APPL_SHARED | RESOURCE_APPL,
        ARES_FILE,
        null,
    );

    var inres = arcan_open_resource(path);

    free(@ptrCast(path));
    if (inres.fd == BADFD)
        return;

    const inmem = arcan_map_resource(&inres, false);
    if (inmem.ptr == null) {
        arcan_release_resource(&inres);
        return;
    }

    var meta_storage = [_]u8{0} ** 64; // struct arcan_img_meta zeroed
    var imgbuf_opt: ?[*]u32 = null;
    var inw: usize = 0;
    var inh: usize = 0;

    const rv = arcan_img_decode(
        infn,
        inmem.ptr,
        inmem.sz,
        &imgbuf_opt,
        &inw,
        &inh,
        @ptrCast(&meta_storage),
        false,
    );

    _ = arcan_release_map(inmem);
    arcan_release_resource(&inres);

    // repack if the system format doesn't match
    if (imgbuf_opt) |ib| {
        imgbuf_opt = arcan_img_repack(ib, inw, inh);
    }

    if (imgbuf_opt == null or rv != ARCAN_OK)
        return;

    if (cons.w > TEXT_EMBEDDEDICON_MAXW or
        (cons.w == 0 and inw > TEXT_EMBEDDEDICON_MAXW))
        cons.w = TEXT_EMBEDDEDICON_MAXW;

    if (cons.h > TEXT_EMBEDDEDICON_MAXH or
        (cons.h == 0 and inh > TEXT_EMBEDDEDICON_MAXH))
        cons.h = TEXT_EMBEDDEDICON_MAXH;

    // if blit to a specific size is requested, use that
    if ((cons.w != 0 and cons.h != 0) and (inw != cons.w or inh != cons.h)) {
        const dsz = @as(usize, cons.w) * @as(usize, cons.h) * @sizeOf(av_pixel);
        const alloc = arcan_alloc_mem(dsz, ARCAN_MEM_VBUFFER, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);
        if (alloc == null) return;
        dst.surf.buf = @ptrCast(@alignCast(alloc.?));
        _ = arcan_renderfun_stretchblit(
            @ptrCast(imgbuf_opt.?),
            @intCast(inw),
            @intCast(inh),
            dst.surf.buf.?,
            cons.w,
            cons.h,
            0,
        );
        arcan_mem_free(@ptrCast(imgbuf_opt.?));
        dst.surf.w = cons.w;
        dst.surf.h = cons.h;
    }
    // otherwise just keep the entire buffer
    else {
        dst.surf.w = inw;
        dst.surf.h = inh;
        dst.surf.buf = imgbuf_opt;
    }
}

// extract_color

fn extract_color(prev: *text_format, base_arg: [*c]u8) ?[*c]u8 {
    var base = base_arg;
    var cbuf: [3]u8 = undefined;

    // scan 6 characters to the right, check for valid hex
    for (0..6) |i| {
        if (isxdigit(base[i]) == 0) {
            arcan_warning("arcan_video_renderstring(), couldn't scan font colour directive (#rrggbb, 0-9, a-f)\n");
            return null;
        }
    }

    // now we know 6 valid chars are there, time to collect
    cbuf[0] = base[0];
    cbuf[1] = base[1];
    cbuf[2] = 0;
    prev.col[0] = @intCast(strtol(&cbuf, null, 16));

    cbuf[0] = base[2];
    cbuf[1] = base[3];
    cbuf[2] = 0;
    prev.col[1] = @intCast(strtol(&cbuf, null, 16));

    cbuf[0] = base[4];
    cbuf[1] = base[5];
    cbuf[2] = 0;
    prev.col[2] = @intCast(strtol(&cbuf, null, 16));

    base += 6;
    return base;
}

// extract_font

fn extract_font(prev: *text_format, base_arg: [*c]u8) ?[*c]u8 {
    var base = base_arg;
    const fontbase: [*c]u8 = base;
    const orig: [*c]u8 = base;

    var relsign: c_int = 0;
    // find fontname vs fontsize separator
    while (base[0] != ',') {
        if (base[0] == 0) {
            arcan_warning("arcan_video_renderstring(), couldn't scan font directive '%s (%s)'\n", fontbase, orig);
            return null;
        }
        base += 1;
    }
    base[0] = 0;
    base += 1;

    if (base[0] == '+') {
        relsign = 1;
        base += 1;
    } else if (base[0] == '-') {
        relsign = -1;
        base += 1;
    }

    // fontbase points to full fontname, find the size
    const numbase: [*c]u8 = base;
    while (base[0] != 0 and isdigit(base[0]) != 0)
        base += 1;

    // error state, no size specifier
    if (numbase == base) {
        arcan_warning("arcan_video_renderstring(), missing size argument in font specification (%s).\n", orig);
        return base;
    }

    const ch = base[0];
    base[0] = 0;

    // we allow a 'default font size' \f,+n or \f,-n
    var font_sz: c_int = @intCast(strtoul(numbase, null, 10));
    if (relsign != 0 or font_sz == 0)
        font_sz = @as(c_int, @intCast(font_cache[0].size)) + relsign * font_sz;

    // force a sane default
    if (font_sz == 0)
        font_sz = 9;

    // use current 'default-font' if just size is provided
    if (fontbase[0] == 0) {
        const font = grab_font(null, @intCast(font_sz));
        base[0] = ch;
        prev.pt_size = @intCast(font_sz);
        update_style(prev, font);
        return base;
    }

    // find font resource
    const fname: [*c]u8 = arcan_find_resource(
        fontbase,
        RESOURCE_SYS_FONT | RESOURCE_APPL_SHARED | RESOURCE_APPL,
        ARES_FILE,
        null,
    );

    var font: ?*font_entry = null;
    if (fname == null) {
        arcan_warning("arcan_video_renderstring(), couldn't find font (%s) (%s)\n", fontbase, orig);
    } else {
        font = grab_font(fname, @intCast(font_sz));
        if (font == null) {
            arcan_warning("arcan_video_renderstring(), couldn't load font (%s) (%s), (%d)\n", fname, orig, font_sz);
        } else {
            update_style(prev, font);
        }
    }

    arcan_mem_free(@ptrCast(fname));
    base[0] = ch;
    return base;
}

// getnum

fn getnum(base: *[*c]u8, dst: *c_ulong) bool {
    const wbase: [*c]u8 = base.*;

    while (base.*[0] != 0 and isdigit(base.*[0]) != 0)
        base.* += 1;

    if (strlen(wbase) == 0)
        return false;

    const ch = base.*[0];
    base.*[0] = 0;
    dst.* = strtoul(wbase, null, 10);
    base.*[0] = ch;
    base.* += 1;
    return true;
}

// extract_vidref

fn extract_vidref(prev: *text_format, base_arg: [*c]u8, ext: bool) ?[*c]u8 {
    var base = base_arg;
    var vid: c_ulong = 0;
    if (!getnum(&base, &vid)) {
        arcan_warning("arcan_video_renderstring(\\evid), missing vid-ref\n");
        return null;
    }

    const vid_id: c_longlong = @as(c_longlong, @intCast(vid)) - @as(c_longlong, vid_ofs);
    const vobj = arcan_video_getobject(vid_id) orelse {
        arcan_warning("arcan_video_renderstring(\\evid), missing or bad vid-ref (%lu)\n", vid);
        return null;
    };

    // Access vs = vobj->vstore via opaque pointer arithmetic.
    // arcan_vobject layout: parent(8), children(8), childslots(8), vstore(8) at offset 24
    // This is fragile but matches the C code's direct field access.
    // We use the C function approach instead — call through extern.
    // For this complex function that deeply accesses vobj internals,
    // we delegate to the C implementation via a helper.
    _ = vobj;
    _ = ext;
    _ = prev;

    // NOTE: extract_vidref accesses deep internal arcan_vobject and agp_vstore
    // fields (txmapped, vinf.text.raw, w, h) that require offset-based access.
    // For now we call through to the C version.
    // This stub will be filled in when offset accessors are available.
    arcan_warning("arcan_video_renderstring(\\evid), vidref not yet supported in Zig port\n");
    return null;
}

// extract_image_simple

fn extract_image_simple(prev: *text_format, base_arg: [*c]u8) ?[*c]u8 {
    var base = base_arg;
    const wbase: [*c]u8 = base;

    while (base[0] != 0 and base[0] != ',') base += 1;
    if (base[0] != 0) {
        base[0] = 0;
        base += 1;
    }

    if (strlen(wbase) == 0) {
        arcan_warning("arcan_video_renderstring(), missing resource name.\n");
        return null;
    }

    prev.imgcons.w = 0;
    prev.imgcons.h = 0;
    prev.surf.buf = null;

    text_loadimage(prev, wbase, prev.imgcons);

    if (prev.surf.buf != null) {
        prev.imgcons.w = @intCast(prev.surf.w);
        prev.imgcons.h = @intCast(prev.surf.h);
    } else {
        arcan_warning("arcan_video_renderstring(), couldn't load icon (%s)\n", wbase);
    }

    return base;
}

// extract_image

fn extract_image(prev: *text_format, base_arg: [*c]u8) ?[*c]u8 {
    var base = base_arg;

    const widbase: [*c]u8 = base;
    while (base[0] != 0 and base[0] != ',' and isdigit(base[0]) != 0) base += 1;
    if (base[0] != 0 and strlen(widbase) > 0) {
        base[0] = 0;
        base += 1;
    } else {
        arcan_warning("arcan_video_renderstring(), width scan failed, premature end in sized image scan directive (%s)\n", widbase);
        return null;
    }
    const forcew = strtol(widbase, null, 10);
    if (forcew <= 0 or forcew > 1024) {
        arcan_warning("arcan_video_renderstring(), width scan failed, unreasonable width (%d) specified in sized image scan directive (%s)\n", @as(c_int, @intCast(forcew)), widbase);
        return null;
    }

    const hghtbase: [*c]u8 = base;
    while (base[0] != 0 and base[0] != ',' and isdigit(base[0]) != 0) base += 1;
    if (base[0] != 0 and strlen(hghtbase) > 0) {
        base[0] = 0;
        base += 1;
    } else {
        arcan_warning("arcan_video_renderstring(), height scan failed, premature end in sized image scan directive (%s)\n", hghtbase);
        return null;
    }
    const forceh = strtol(hghtbase, null, 10);
    if (forceh <= 0 or forceh > 1024) {
        arcan_warning("arcan_video_renderstring(), height scan failed, unreasonable height (%d) specified in sized image scan directive (%s)\n", @as(c_int, @intCast(forceh)), hghtbase);
        return null;
    }

    const wbase: [*c]u8 = base;
    while (base[0] != 0 and base[0] != ',') base += 1;
    if (base[0] == ',') {
        base[0] = 0;
        base += 1;
    } else {
        arcan_warning("arcan_video_renderstring(), missing resource name terminator (,) in sized image scan directive (%s)\n", wbase);
        return null;
    }

    if (strlen(wbase) > 0) {
        prev.imgcons.w = @intCast(forcew);
        prev.imgcons.h = @intCast(forceh);
        prev.surf.buf = null;
        text_loadimage(prev, wbase, prev.imgcons);
        return base;
    } else {
        arcan_warning("arcan_video_renderstring(), missing resource name.\n");
        return null;
    }
}

// formatend

fn formatend(base_arg: [*c]u8, prev_arg: text_format, orig: [*c]u8, ok: *bool) text_format {
    var prev = prev_arg;
    const failed: text_format = .{};
    // don't carry caret modifiers
    prev.newline = 0;
    prev.tab = 0;
    prev.cr = false;
    var inv = false;
    var whskip = false;
    var base = base_arg;

    while (base[0] != 0) {
        // skip first whitespace
        if (whskip == false and isspace(base[0]) != 0) {
            base += 1;
            whskip = true;
            continue;
        }

        // out of formatstring
        if (base[0] != '\\') {
            prev.endofs = base;
            break;
        }

        // The C code uses goto retry with base-- to handle the '!' prefix.
        // We translate this by peeking at characters without consuming for '!'.
        // First, skip the initial '\' we already know is there.
        // Check for '!' chain: \!<cmd> means invert the next command.
        var scan_pos: usize = 1; // skip the '\'
        while (base[scan_pos] == '!') : (scan_pos += 1) {
            inv = !inv;
        }
        const cmd = base[scan_pos];
        base += scan_pos + 1;

        switch (cmd) {
            't' => {
                prev.tab += 1;
            },
            'n' => {
                prev.newline += 1;
            },
            'r' => {
                prev.cr = true;
            },
            'u' => {
                if (inv)
                    prev.style &= @bitCast(~@as(c_uint, @bitCast(TTF_STYLE_UNDERLINE)))
                else
                    prev.style |= TTF_STYLE_UNDERLINE;
            },
            'b' => {
                if (inv)
                    prev.style &= @bitCast(~@as(c_uint, @bitCast(TTF_STYLE_BOLD)))
                else
                    prev.style |= TTF_STYLE_BOLD;
            },
            'i' => {
                if (inv)
                    prev.style &= @bitCast(~@as(c_uint, @bitCast(TTF_STYLE_ITALIC)))
                else
                    prev.style |= TTF_STYLE_ITALIC;
            },
            'e' => {
                const res = extract_vidref(&prev, base, false);
                if (res) |r| {
                    base = r;
                } else {
                    ok.* = false;
                    return failed;
                }
            },
            'E' => {
                const res = extract_vidref(&prev, base, true);
                if (res) |r| {
                    base = r;
                } else {
                    ok.* = false;
                    return failed;
                }
            },
            'v', 'T', 'H', 'V' => {},
            'p' => {
                const res = extract_image_simple(&prev, base);
                if (res) |r| {
                    base = r;
                } else {
                    ok.* = false;
                    return failed;
                }
            },
            'P' => {
                const res = extract_image(&prev, base);
                if (res) |r| {
                    base = r;
                } else {
                    ok.* = false;
                    return failed;
                }
            },
            '#' => {
                const res = extract_color(&prev, base);
                if (res) |r| {
                    base = r;
                } else {
                    ok.* = false;
                    return failed;
                }
            },
            'f' => {
                const res = extract_font(&prev, base);
                if (res) |r| {
                    base = r;
                } else {
                    ok.* = false;
                    return failed;
                }
            },
            else => {
                arcan_warning("arcan_video_renderstring(), unknown escape sequence: '\\%c' (%s)\n", cmd, orig);
                ok.* = false;
                return failed;
            },
        }

        inv = false;
    }

    if (base[0] == 0)
        prev.endofs = base;

    ok.* = true;
    return prev;
}

// draw_builtin

fn draw_builtin(
    cnode: *rcell,
    base: [*c]const u8,
    style: *text_format,
    w: c_int,
    h: c_int,
) void {
    const len = strlen(base);
    if (len == 0) return;

    // VLA replacement: stack buffer up to 4096, heap above
    var stack_buf: [4096]u32 = undefined;
    var heap_buf: ?[*]u32 = null;
    var ucs4: [*]u32 = undefined;

    if (len + 1 <= 4096) {
        ucs4 = &stack_buf;
    } else {
        heap_buf = @ptrCast(@alignCast(malloc((len + 1) * @sizeOf(u32))));
        if (heap_buf == null) return;
        ucs4 = heap_buf.?;
    }
    defer {
        if (heap_buf) |hb| free(@ptrCast(hb));
    }

    _ = UTF8_to_UTF32(ucs4, base, len);

    const bmp = builtin_bitmap_data.font_data orelse return;
    const fg = RGBA(style.col[0], style.col[1], style.col[2], style.col[3]);
    const buf = cnode.data.surf.buf orelse return;
    const wu: usize = @intCast(w);
    const hu: usize = @intCast(h);

    for (0..len) |i_idx| {
        tui_pixelfont_draw(
            bmp,
            buf,
            wu,
            ucs4[i_idx],
            i_idx * style.px_skip,
            0,
            fg,
            0,
            wu,
            hu,
            true,
        );
    }
}

// render_alloc

fn render_alloc(
    cnode: *rcell,
    base: [*c]const u8,
    style: *text_format,
) bool {
    var w: c_int = 0;
    var h: c_int = 0;

    if (size_font_chain(style, base, &w, &h) != 0) {
        arcan_warning("arcan_video_renderstring(), couldn't size node.\n");
        return false;
    }

    if (w == 0 or @as(usize, @intCast(w)) > CONST_MAX_SURFACEW or
        h == 0 or @as(usize, @intCast(h)) > CONST_MAX_SURFACEH)
    {
        return false;
    }

    const wu: usize = @intCast(w);
    const hu: usize = @intCast(h);
    const dsz = wu * hu * @sizeOf(av_pixel);
    const alloc = arcan_alloc_mem(dsz, ARCAN_MEM_VBUFFER, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);
    if (alloc == null) {
        arcan_warning("arcan_video_renderstring(%d,%d), failed alloc.\n", w, h);
        return false;
    }
    cnode.data.surf.buf = @ptrCast(@alignCast(alloc.?));

    // clear manually (BZERO on VBUFFER sets FULLALPHA)
    const buf = cnode.data.surf.buf.?;
    for (0..wu * hu) |i| {
        buf[i] = 0;
    }

    // if there is no font, use the built-in default
    if (style.font == null) {
        draw_builtin(cnode, base, style, w, h);
    } else {
        const fnt = style.font.?;
        if (!TTF_RenderUTF8chain(
            buf,
            wu,
            hu,
            wu,
            &fnt.chain.data,
            fnt.chain.count,
            base,
            &style.col,
            style.style,
        )) {
            arcan_warning("arcan_video_renderstring(), failed to render.\n");
            arcan_mem_free(@ptrCast(buf));
            cnode.data.surf.buf = null;
            return false;
        }
    }

    cnode.data.surf.w = wu;
    cnode.data.surf.h = hu;
    cnode.ascent = style.ascent;
    cnode.height = @intCast(style.height);
    cnode.descent = style.descent;
    cnode.skipv = style.skip;

    return true;
}

// currstyle_cnode

fn currstyle_cnode(
    curr_style: *text_format,
    base: [*c]const u8,
    cnode: *rcell,
    sizeonly: bool,
) void {
    if (sizeonly) {
        if (curr_style.font) |fnt| {
            var dw: c_int = 0;
            var dh: c_int = 0;
            _ = size_font_chain(curr_style, base, &dw, &dh);
            cnode.ascent = TTF_FontAscent(fnt.chain.data[0].?);
            cnode.width = @intCast(dw);
            cnode.descent = TTF_FontDescent(fnt.chain.data[0].?);
            cnode.height = @intCast(TTF_FontHeight(fnt.chain.data[0].?));
        } else {
            cnode.width = curr_style.imgcons.w;
            cnode.height = curr_style.imgcons.h;
        }
        return;
    }

    // image or render font
    if (curr_style.surf.buf != null) {
        cnode.data.surf.buf = curr_style.surf.buf;
        cnode.data.surf.w = curr_style.surf.w;
        cnode.data.surf.h = curr_style.surf.h;
        curr_style.surf.buf = null;
        return;
    }

    if (!render_alloc(cnode, base, curr_style)) {
        // reset
        set_style(&last_style, &font_cache[0]);
    }
}

// trystep

fn trystep(cnode: *rcell, force: bool) *rcell {
    if (force or cnode.data.surf.buf != null) {
        const alloc = arcan_alloc_mem(
            @sizeOf(rcell),
            ARCAN_MEM_VSTRUCT,
            ARCAN_MEM_TEMPORARY | ARCAN_MEM_BZERO,
            ARCAN_MEMALIGN_NATURAL,
        );
        if (alloc) |a| {
            const new_node: *rcell = @ptrCast(@alignCast(a));
            new_node.* = .{};
            cnode.next = new_node;
            return new_node;
        }
    }
    return cnode;
}

// build_textchain

fn build_textchain(
    message: [*c]u8,
    root: *rcell,
    sizeonly: bool,
    nolast: bool,
    reset: bool,
) c_int {
    var rv: c_int = 0;

    const curr_style: *text_format = &last_style;
    if (reset)
        set_style(curr_style, &font_cache[0]);

    var cnode: *rcell = root;
    var current: [*c]u8 = message;
    var base: [*c]u8 = message;
    var msglen: c_int = 0;

    // outer loop, find first split-point
    while (current[0] != 0) {
        if (current[0] == '\\') {
            // special case, escape \\
            if (current[1] == '\\') {
                _ = memmove(@ptrCast(current), @ptrCast(current + 1), strlen(current));
                current += 1;
                msglen += 1;
            }
            // split-point found
            else {
                if (msglen > 0) {
                    current[0] = 0;
                    // render surface and slide window
                    currstyle_cnode(curr_style, base, cnode, sizeonly);
                    // slide-alloc list of rendered blocks
                    cnode = trystep(cnode, false);
                    current[0] = '\\';
                }

                // scan format-options and slide to end
                var okstatus: bool = undefined;
                curr_style.* = formatend(current, curr_style.*, message, &okstatus);
                if (!okstatus)
                    return -1;

                // caret modifiers need to be separately chained
                if (curr_style.newline != 0 or curr_style.tab != 0 or curr_style.cr) {
                    cnode = trystep(cnode, false);
                    rv += @as(c_int, curr_style.newline);
                    cnode.data = .{ .format = .{
                        .newline = curr_style.newline,
                        .tab = curr_style.tab,
                        .cr = curr_style.cr,
                    } };
                    cnode = trystep(cnode, true);
                }

                if (curr_style.surf.buf != null) {
                    currstyle_cnode(curr_style, base, cnode, sizeonly);
                    cnode = trystep(cnode, false);
                }

                current = curr_style.endofs;
                base = current;
                if (current == null)
                    return -1;

                msglen = 0;
            }
        } else {
            msglen += 1;
            current += 1;
        }
    }

    // last element
    if (msglen > 0) {
        cnode.next = null;
        if (sizeonly) {
            var sw: c_int = 0;
            var sh: c_int = 0;
            _ = size_font_chain(curr_style, base, &sw, &sh);
            cnode.width = @intCast(sw);
            cnode.height = @intCast(sh);
        } else {
            _ = render_alloc(cnode, base, curr_style);
        }
    }

    // special handling needed for longer append chains
    if (!nolast) {
        cnode = trystep(cnode, true);
        cnode.data = .{ .format = .{ .newline = 1, .tab = 0, .cr = false } };
        rv += 1;
    }

    return rv;
}

// round_mult

fn round_mult(num: c_uint, mult: c_uint) c_uint {
    if (num == 0 or mult == 0)
        return mult; // intended ;-)
    const remain = num % mult;
    return if (remain != 0) num + mult - remain else num;
}

// get_tabofs

fn get_tabofs(offset: c_int, tabc: c_int, tab_spacing: i8) c_uint {
    const ofs: c_uint = @intCast(if (offset < 0) 0 else offset);
    if (tab_spacing != 0) {
        const ts: c_uint = @intCast(if (tab_spacing < 0) -tab_spacing else tab_spacing);
        const rounded = round_mult(ofs, ts);
        const tc: c_uint = @intCast(if (tabc < 1) 0 else tabc - 1);
        return @intFromFloat(@floor(PT_TO_HPX(rounded + tc * ts)));
    }
    return @intFromFloat(@floor(PT_TO_HPX(ofs)));
}

// copy_rect

fn copy_rect(
    dst: [*]av_pixel,
    dst_sz: usize,
    surf: *rcell,
    width: usize,
    height: usize,
    x: usize,
    y: usize,
) void {
    const high = @sizeOf(av_pixel) * height * width;
    if (high > dst_sz) {
        arcan_warning("arcan_video_renderstring():copy_rect OOB, %zu/%zu\n", high, dst_sz);
        return;
    }

    const surf_buf = surf.data.surf.buf orelse return;
    const surf_w = surf.data.surf.w;
    const surf_h = surf.data.surf.h;

    var row: usize = 0;
    while (row < surf_h and row < height - y) : (row += 1) {
        const dst_start = (y + row) * width + x;
        const src_start = row * surf_w;
        const copy_len = surf_w * @sizeOf(av_pixel);
        _ = memcpy(
            @ptrCast(&dst[dst_start]),
            @ptrCast(&surf_buf[src_start]),
            copy_len,
        );
    }
}

// cleanup_chain

fn cleanup_chain(root_arg: ?*rcell) void {
    var root = root_arg;
    while (root) |node| {
        if (node.data.surf.buf) |buf| {
            arcan_mem_free(@ptrCast(buf));
        }
        // zero out to detect use-after-free
        node.data.surf.buf = null;

        const prev = node;
        root = node.next;
        prev.next = null;
        arcan_mem_free(@ptrCast(prev));
    }
}

// process_chain

fn process_chain(
    root: *rcell,
    dst_vobj: ?*anyopaque,
    chainlines: usize,
    norender: bool,
    pot: bool,
    n_lines: ?*c_uint,
    lineheights: ?*?[*]renderline_meta,
    dw: *usize,
    dh: *usize,
    d_sz: *u32,
    maxw: *usize,
    maxh: *usize,
) ?[*]av_pixel {
    var cnode: ?*rcell = root;
    var linecount: c_uint = 0;
    maxw.* = 0;
    maxh.* = 0;
    var lineh: c_int = 0;
    var fonth: c_int = 0;
    var ascenth: c_int = 0;
    var curw: c_int = 0;

    var line_spacing: c_int = 0;
    const fixed_spacing: bool = false;

    // allocate lines array
    const lines_alloc = arcan_alloc_mem(
        @sizeOf(renderline_meta) * (chainlines + 1),
        ARCAN_MEM_VSTRUCT,
        ARCAN_MEM_BZERO | ARCAN_MEM_TEMPORARY,
        ARCAN_MEMALIGN_NATURAL,
    );
    if (lines_alloc == null) {
        cleanup_chain(root);
        return null;
    }
    const lines: [*]renderline_meta = @ptrCast(@alignCast(lines_alloc.?));

    // (A) figure out visual constraints
    while (cnode) |cn| {
        // data node
        if (cn.data.surf.buf != null) {
            if (!fixed_spacing)
                line_spacing = cn.skipv;

            const surf_h: c_int = @intCast(cn.data.surf.h);
            if (lineh + line_spacing <= 0 or surf_h > lineh + line_spacing)
                lineh = surf_h;

            if (cn.ascent > ascenth)
                ascenth = cn.ascent;

            if (cn.height > fonth)
                fonth = @intCast(cn.height);

            const surf_w: c_int = @intCast(cn.data.surf.w);
            curw += surf_w;
        }
        // format node
        else {
            if (cn.data.format.cr) {
                curw = 0;
            }

            if (cn.data.format.tab != 0)
                curw = @intCast(get_tabofs(curw, cn.data.format.tab, 0));

            if (cn.data.format.newline > 0) {
                var nl: c_int = cn.data.format.newline;
                while (nl > 0) : (nl -= 1) {
                    lines[linecount].ystart = @intCast(maxh.*);
                    lines[linecount].height = fonth;
                    lines[linecount].ascent = ascenth;
                    linecount += 1;
                    maxh.* += @intCast(lineh + line_spacing);
                    ascenth = 0;
                    fonth = 0;
                    lineh = 0;
                }
            }
        }

        if (curw > 0 and @as(usize, @intCast(curw)) > maxw.*)
            maxw.* = @intCast(curw);

        cnode = cn.next;
    }

    // (B) render into destination buffers
    dw.* = if (pot) nexthigher(@intCast(maxw.*)) else maxw.*;
    dh.* = if (pot) nexthigher(@intCast(maxh.*)) else maxh.*;

    d_sz.* = @intCast(dw.* * dh.* * @sizeOf(av_pixel));

    if (norender) {
        cleanup_chain(root);
        return null;
    }

    var raw: ?[*]av_pixel = null;

    // TODO: if dst_vobj is set, resize its backing store
    // This requires accessing vobj->vstore which is opaque from Zig.
    // For now we always allocate a new buffer.
    _ = dst_vobj;
    {
        const alloc = arcan_alloc_mem(d_sz.*, ARCAN_MEM_VBUFFER, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);
        if (alloc) |a| {
            raw = @ptrCast(@alignCast(a));
        }
    }

    if (raw == null or d_sz.* == 0) {
        cleanup_chain(root);
        return raw;
    }

    _ = memset(@ptrCast(raw.?), 0, d_sz.*);
    cnode = root;
    curw = 0;
    var line: usize = 0;

    while (cnode) |cn| {
        if (cn.data.surf.buf != null) {
            const ystart: usize = @intCast(lines[line].ystart);
            copy_rect(raw.?, d_sz.*, cn, dw.*, dh.*, @intCast(if (curw < 0) 0 else curw), ystart);
            curw += @intCast(cn.data.surf.w);
        } else {
            if (cn.data.format.tab > 0)
                curw = @intCast(get_tabofs(curw, cn.data.format.tab, 0));

            if (cn.data.format.cr)
                curw = 0;

            if (cn.data.format.newline > 0)
                line += cn.data.format.newline;
        }
        cnode = cn.next;
    }

    if (n_lines) |nl| nl.* = linecount;

    if (lineheights) |lh| {
        lh.* = lines;
    } else {
        arcan_mem_free(@ptrCast(lines));
    }

    // TODO: if dst_vobj, call agp_resize_vstore and set density fields

    cleanup_chain(root);
    return raw;
}

// arcan_renderfun_renderfmtstr_extended

export fn arcan_renderfun_renderfmtstr_extended(
    msgarray: ?[*]const [*c]const u8,
    dstore: c_longlong,
    pot: bool,
    n_lines_ptr: ?*c_uint,
    lineheights: ?*?[*]renderline_meta,
    dw: *usize,
    dh: *usize,
    d_sz: *u32,
    maxw: *usize,
    maxh: *usize,
    norender: bool,
) ?[*]av_pixel {
    const root_alloc = arcan_alloc_mem(
        @sizeOf(rcell),
        ARCAN_MEM_VSTRUCT,
        ARCAN_MEM_BZERO | ARCAN_MEM_TEMPORARY,
        ARCAN_MEMALIGN_NATURAL,
    );
    if (root_alloc == null) return null;
    const root: *rcell = @ptrCast(@alignCast(root_alloc.?));
    root.* = .{};

    const msgs = msgarray orelse return null;
    if (msgs[0] == null) return null;

    last_style.newline = 0;
    last_style.tab = 0;
    last_style.cr = false;

    var acc: usize = 0;
    var ind: usize = 0;
    var cur: *rcell = root;

    while (msgs[ind] != null) {
        if (msgs[ind][0] == 0) {
            ind += 1;
            continue;
        }

        if (ind % 2 == 0) {
            const work = strdup(msgs[ind]);
            const nlines = build_textchain(work, cur, false, true, ind == 0);
            arcan_mem_free(@ptrCast(work));
            if (nlines == -1) break;
            acc += @intCast(nlines);
            while (cur.next != null) {
                cur = cur.next.?;
            }
        }
        // %2+1, no format-string input, just treat as text
        else {
            const alloc = arcan_alloc_mem(
                @sizeOf(rcell),
                ARCAN_MEM_VSTRUCT,
                ARCAN_MEM_BZERO | ARCAN_MEM_TEMPORARY,
                ARCAN_MEMALIGN_NATURAL,
            );
            if (alloc) |a| {
                const new_node: *rcell = @ptrCast(@alignCast(a));
                new_node.* = .{};
                cur.next = new_node;
                cur = new_node;
                currstyle_cnode(&last_style, msgs[ind], cur, false);
            }
        }
        ind += 1;
    }

    // append newline
    const nl_alloc = arcan_alloc_mem(
        @sizeOf(rcell),
        ARCAN_MEM_VSTRUCT,
        ARCAN_MEM_TEMPORARY | ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    );
    if (nl_alloc) |a| {
        const nl_node: *rcell = @ptrCast(@alignCast(a));
        nl_node.* = .{};
        nl_node.data = .{ .format = .{ .newline = 1, .tab = 0, .cr = false } };
        cur.next = nl_node;
    }

    return process_chain(
        root,
        arcan_video_getobject(dstore),
        acc + 1,
        norender,
        pot,
        n_lines_ptr,
        lineheights,
        dw,
        dh,
        d_sz,
        maxw,
        maxh,
    );
}

// arcan_renderfun_renderfmtstr

export fn arcan_renderfun_renderfmtstr(
    message: [*c]const u8,
    dstore: c_longlong,
    pot: bool,
    n_lines_ptr: ?*c_uint,
    lineheights: ?*?[*]renderline_meta,
    dw: *usize,
    dh: *usize,
    d_sz: *u32,
    maxw: *usize,
    maxh: *usize,
    norender: bool,
) ?[*]av_pixel {
    if (message == null) return null;

    const root_alloc = arcan_alloc_mem(
        @sizeOf(rcell),
        ARCAN_MEM_VSTRUCT,
        ARCAN_MEM_BZERO | ARCAN_MEM_TEMPORARY,
        ARCAN_MEMALIGN_NATURAL,
    );
    if (root_alloc == null) return null;
    const root: *rcell = @ptrCast(@alignCast(root_alloc.?));
    root.* = .{};

    const work = strdup(message);
    last_style.newline = 0;
    last_style.tab = 0;
    last_style.cr = false;

    const chainlines = build_textchain(work, root, false, false, true);
    arcan_mem_free(@ptrCast(work));

    if (chainlines > 0) {
        return process_chain(
            root,
            arcan_video_getobject(dstore),
            @intCast(chainlines),
            norender,
            pot,
            n_lines_ptr,
            lineheights,
            dw,
            dh,
            d_sz,
            maxw,
            maxh,
        );
    }

    return null;
}

// fontgroup public API

fn close_font_slot(grp: *fontgroup, slot: usize) void {
    if (grp.font == null) return;
    const fonts = grp.font.?;
    const f = &fonts[slot];

    if (f.fd == -1 or f.fd == BADFD or grp.is_builtin)
        return;

    _ = close(f.fd);
    f.fd = -1;
    if (f.vector) {
        if (f.font_data) |d| {
            TTF_CloseFont(d);
            f.font_data = null;
        }
    } else {
        if (f.font_data) |d| {
            tui_pixelfont_close(d);
            f.font_data = null;
        }
    }
}

fn consume_pixel_font(grp: *fontgroup, fd: c_int) c_int {
    var src: data_source = .{ .fd = fd };

    const map = arcan_map_resource(&src, false);
    if (map.ptr == null or map.sz < 32 or !tui_pixelfont_valid(map.ptr, 23)) {
        _ = arcan_release_map(map);
        return 0;
    }

    const fonts = grp.font orelse return 0;

    // prohibit mixing and matching vector/bitmap
    if (fonts[0].font_data != null and fonts[0].vector) {
        close_font_slot(grp, 0);
        fonts[0].vector = false;
    }

    var i: usize = 1;
    while (i < grp.used) : (i += 1) {
        close_font_slot(grp, i);
    }

    // re-use current bitmap group or build one if it isn't there
    if (fonts[0].font_data == null) {
        fonts[0].font_data = tui_pixelfont_open(64);
        if (fonts[0].font_data == null) {
            _ = close(fd);
            _ = arcan_release_map(map);
            return -1;
        }
    }

    _ = close(fd);
    return 1;
}

fn font_group_ptpx(grp: *fontgroup, pt: ?*usize, px: ?*usize) void {
    var pt_size = arcan_mm_to_pt(grp.size_mm);
    if (pt_size < 4.0) pt_size = 4.0;

    if (pt) |p| p.* = @intFromFloat(@floor(pt_size));
    if (px) |p| p.* = @intFromFloat(roundf(arcan_pt_to_mm(pt_size) * 0.1 * grp.ppcm));
}

fn set_font_slot(grp: *fontgroup, slot: usize, fd: c_int) void {
    if (fd == -1) return;
    if (grp.is_builtin) {
        _ = close(fd);
        return;
    }

    // Validate-then-swap: probe the new fd before disturbing the existing
    // slot. The previous destroy-then-replace pattern called close_font_slot
    // up front, so any subsequent rejection (consume_pixel_font miss followed
    // by TTF_OpenFontFD failure, or arcan_ttf.do_fstat_fd panic on a stale
    // fd) left the slot empty with no replacement — the user-visible symptom
    // was "fonts disappear". See bug 0125 +
    // feedback_no_panics_in_compositor_hot_paths: the right fix is to stop
    // creating the invalid state, not to soften the panic that detects it.
    {
        var probe: c.struct_stat = undefined;
        if (c.fstat(fd, &probe) != 0) {
            const e: c_int = if (comptime @import("builtin").os.tag == .freestanding) 0 else std.c._errno().*;
            var buf: [220]u8 = undefined;
            const msg = std.fmt.bufPrintZ(&buf, "[bug 0125] set_font_slot: rejecting bad fd={d} errno={d} slot={d} (existing slot preserved)\n", .{ fd, e, slot }) catch "[bug 0125] set_font_slot: rejecting bad fd\n";
            if (comptime @import("builtin").os.tag != .freestanding) {
                std.fs.File.stderr().writeAll(msg) catch {};
            }
            _ = close(fd);
            return;
        }
    }

    // first check for a supported pixel font format. consume_pixel_font is
    // already validate-then-swap internally — it gates on tui_pixelfont_valid
    // before mutating the group, and pixel-mode is a global mode-switch
    // (slot 0 holds the font, all others must clear). We therefore do NOT
    // pre-close the requested slot — consume_pixel_font handles its own
    // destroys after validation succeeds.
    const pfstat = consume_pixel_font(grp, fd);
    if (pfstat != 0) return;

    const fonts = grp.font orelse {
        _ = close(fd);
        return;
    };

    // Defer the TTF open until the real size is known (see fontgroup_size).
    // The fstat probe above already verified the fd is a real file; safe to
    // stash. Now release the existing slot — the replacement is committed.
    if (!(grp.size_mm > 0)) {
        close_font_slot(grp, slot);
        fonts[slot].fd = fd;
        fonts[slot].vector = true;
        fonts[slot].font_data = null;
        return;
    }

    // assume vector and try TTF on the new fd. TTF_OpenFontFD is the second
    // validator: if it returns null the file is not a parseable TTF/OTF;
    // close the new fd and leave the existing slot intact.
    var pt_sz: usize = 0;
    font_group_ptpx(grp, &pt_sz, null);
    const dpi: f32 = grp.ppcm * 2.54;
    const dpi_u16: u16 = @intFromFloat(dpi);

    const new_font = TTF_OpenFontFD(fd, @intCast(pt_sz), dpi_u16, dpi_u16);
    if (new_font == null) {
        _ = close(fd);
        return;
    }

    // Replacement validated — only NOW destroy the existing slot.
    close_font_slot(grp, slot);
    fonts[slot].font_data = new_font;
    fonts[slot].fd = fd;
    fonts[slot].vector = true;
    TTF_SetFontStyle(new_font.?, TTF_STYLE_NORMAL);
    TTF_SetFontStyle(new_font.?, TTF_HINTING_NORMAL);
}

fn build_font_group(grp: *fontgroup, fds: ?[*]c_int, n_fonts: usize) void {
    // safe defaults — leave size_mm at 0 so set_font_slot defers the TTF
    // open until the caller provides a real size via fontgroup_size.
    grp.ppcm = 37.795276;
    grp.size_mm = 0;

    // default requested
    if (n_fonts == 0 or fds == null or fds.?[0] == -1) {
        // fallback_bitmap
        grp.used = 1;
        if (grp.font != null and !grp.is_builtin)
            arcan_mem_free(@ptrCast(grp.font.?));
        grp.font = @ptrCast(&builtin_bitmap_data);
        grp.is_builtin = true;
        return;
    }

    grp.used = n_fonts;
    const alloc = arcan_alloc_mem(
        @sizeOf(tui_font) * n_fonts,
        ARCAN_MEM_VSTRUCT,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    );
    if (alloc == null) {
        // fallback_bitmap
        grp.used = 1;
        grp.font = @ptrCast(&builtin_bitmap_data);
        grp.is_builtin = true;
        return;
    }
    grp.font = @ptrCast(@alignCast(alloc.?));
    grp.is_builtin = false;

    // zero-init
    for (0..n_fonts) |i| {
        grp.font.?[i] = .{};
    }

    // probe types, fill out the font structure accordingly
    for (0..n_fonts) |i| {
        set_font_slot(grp, i, fds.?[i]);
    }
}

export fn arcan_renderfun_fontgroup(fds: ?[*]c_int, n_fonts: usize) ?*fontgroup {
    const alloc = arcan_alloc_mem(
        @sizeOf(fontgroup),
        ARCAN_MEM_VSTRUCT,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    );
    if (alloc == null) return null;

    const grp: *fontgroup = @ptrCast(@alignCast(alloc.?));
    grp.* = .{};

    build_font_group(grp, fds, n_fonts);

    return grp;
}

export fn arcan_renderfun_fontgroup_replace(
    group: ?*fontgroup,
    slot: c_int,
    new_fd: c_int,
) void {
    const grp = group orelse return;

    // always invalidate any cached raster
    if (grp.raster) |r| {
        tui_raster_free(r);
        grp.raster = null;
    }

    // can't accommodate, ignore
    if (@as(usize, @intCast(slot)) >= grp.used) {
        if (new_fd != -1)
            _ = close(new_fd);
        return;
    }

    // Instrumentation: if the slot already holds a TTF / fd, set_font_slot
    // is responsible for releasing it. If a future refactor drops the
    // close_font_slot call inside set_font_slot the leak would silently
    // re-emerge — this trace marks every replace-over-occupied so the
    // pattern is observable in fsrv_*.txt instead of needing lsof.
    if (!grp.is_builtin) {
        if (grp.font) |fonts| {
            const s: usize = @intCast(slot);
            if (s < grp.used and (fonts[s].fd != -1 or fonts[s].font_data != null)) {
                var buf: [160]u8 = undefined;
                const msg = std.fmt.bufPrintZ(&buf,
                    "fontgroup_replace: slot={d} replacing fd={d} font_data={?*} (terminal open/close path)",
                    .{ slot, fonts[s].fd, fonts[s].font_data }) catch "fontgroup_replace: replace-over-occupied";
                arcan_warning("[font-cache] %s\n", msg.ptr);
            }
        }
    }

    set_font_slot(grp, @intCast(slot), new_fd);
}

export fn arcan_renderfun_release_fontgroup(group: ?*fontgroup) void {
    const grp = group orelse return;

    for (0..grp.used) |i| {
        close_font_slot(grp, i);
    }

    grp.used = 0;

    tui_raster_free(grp.raster);

    if (!grp.is_builtin) {
        if (grp.font) |f|
            arcan_mem_free(@ptrCast(f));
    }
    arcan_mem_free(@ptrCast(grp));
}

export fn arcan_renderfun_fontgroup_size(
    group: ?*fontgroup,
    size_mm: f32,
    ppcm: f32,
    w: *usize,
    h: *usize,
) void {
    const grp = group orelse return;

    // invalidate raster on size change
    if (grp.raster) |r| {
        tui_raster_free(r);
        grp.raster = null;
    }

    if (size_mm > EPSILON)
        grp.size_mm = size_mm;

    if (ppcm > EPSILON)
        grp.ppcm = ppcm;

    // recalculate new sizes
    var pt: usize = 0;
    var px: usize = 0;
    font_group_ptpx(grp, &pt, &px);
    const dpi: f32 = grp.ppcm * 2.54;
    const dpi_u16: u16 = @intFromFloat(dpi);

    const fonts = grp.font orelse return;

    // re-open each font for the new pt. If the slot was deferred by
    // build_font_group (font_data == null but fd is valid), perform the
    // first-time TTF_OpenFontFD here so the open happens at the correct size.
    for (0..grp.used) |i| {
        if (!fonts[i].vector) continue;
        if (fonts[i].font_data) |fd_data| {
            fonts[i].font_data = TTF_ReplaceFont(fd_data, @intCast(pt), dpi_u16, dpi_u16);
        } else if (fonts[i].fd != -1 and fonts[i].fd != BADFD) {
            const nf = TTF_OpenFontFD(fonts[i].fd, @intCast(pt), dpi_u16, dpi_u16);
            if (nf != null) {
                fonts[i].font_data = nf;
                TTF_SetFontStyle(nf.?, TTF_STYLE_NORMAL);
                TTF_SetFontStyle(nf.?, TTF_HINTING_NORMAL);
            }
        }
    }

    // reprobe based on first slot
    if (fonts[0].vector) {
        grp.w = 0;
        grp.h = 0;
        TTF_ProbeFont(fonts[0].font_data.?, &grp.w, &grp.h);
    } else {
        if (fonts[0].font_data) |bmp| {
            tui_pixelfont_setsz(bmp, px, &grp.w, &grp.h);
        }
    }

    w.* = grp.w;
    h.* = grp.h;
}

export fn arcan_renderfun_fontraster(group: ?*fontgroup) ?*anyopaque {
    const grp = group orelse return null;
    const fonts = grp.font orelse return null;

    // if we don't have a valid font, the raster is pointless
    if ((fonts[0].vector and fonts[0].font_data == null) or
        (!fonts[0].vector and fonts[0].font_data == null))
        return null;

    // if we have a cached raster, return it
    if (grp.raster) |r| return r;

    // build a new font pointer list
    var lst: [4]?*anyopaque = .{ null, null, null, null };
    for (0..@min(grp.used, 4)) |i| {
        lst[i] = @ptrCast(&fonts[i]);
    }

    grp.raster = tui_raster_setup(grp.w, grp.h);
    if (grp.raster) |r| {
        tui_raster_setfont(r, &lst, grp.used);
    }

    return grp.raster;
}

// arcan_renderfun_stretchblit

export fn arcan_renderfun_stretchblit(
    src: [*c]u8,
    inw: c_int,
    inh: c_int,
    dst: [*]u32,
    dstw: usize,
    dsth: usize,
    flipv: c_int,
) c_int {
    const pack_tight: c_int = 0;

    if (null == stbir_resize_uint8_linear(
        src,
        inw,
        inh,
        pack_tight,
        @ptrCast(dst),
        @intCast(dstw),
        @intCast(dsth),
        pack_tight,
        STBIR_RGBA,
    ))
        return -1;

    if (flipv == 0)
        return 1;

    // vertical flip: swap rows from top and bottom
    const stride = dstw * 4;
    var y: usize = 0;
    while (y < dsth >> 1) : (y += 1) {
        if (y == (dsth - 1 - y))
            continue;

        // swap row y with row (dsth-1-y) using memcpy via a stack buffer
        const top_start = y * dstw;
        const bot_start = (dsth - 1 - y) * dstw;
        // Use per-pixel swap to avoid VLA
        var x: usize = 0;
        while (x < dstw) : (x += 1) {
            const tmp = dst[top_start + x];
            dst[top_start + x] = dst[bot_start + x];
            dst[bot_start + x] = tmp;
        }
    }
    _ = stride;

    return 1;
}

// arcan_video_tuisynch
// Syncs a TUI-backed vobject: tpack the screen, rasterize via AGP, stream upload.
// Accesses opaque vobj/vstore/tpack fields via byte-offset accessors in engine_offsets.

const engine_offsets = @import("engine_offsets");
const Vobj = engine_offsets.Vobj;
const AgpVstore = engine_offsets.AgpVstore;
const RenderTarget = engine_offsets.RenderTarget;
const VideoDisplay = engine_offsets.VideoDisplay;

const builtin_rfun = @import("builtin");
const is_freestanding_rfun = (builtin_rfun.os.tag == .freestanding);

// Arcan C headers removed — using inline Zig type definitions.
const agp = struct {
    const struct_stream_meta = extern struct {
        buf: ?*anyopaque = null,
        x1: c_int = 0,
        y1: c_int = 0,
        w: c_int = 0,
        h: c_int = 0,
        dirty: bool = false,
    };
    const struct_agp_vstore = anyopaque;
    const STREAM_RAW_DIRECT: c_uint = 0;
};

const tpack_gen_opts = extern struct { full: bool = false, synch: bool = false, back: bool = false };
extern fn tui_screen_tpack_sz(tui: ?*anyopaque) usize;
extern fn tui_screen_tpack(tui: ?*anyopaque, opts: tpack_gen_opts, buf: [*]u8, buf_sz: usize) usize;
extern fn tui_raster_renderagp(raster: ?*anyopaque, vs: *anyopaque, buf: [*]u8, buf_sz: usize, stream_out: *agp.struct_stream_meta) c_int;
extern fn tui_raster_gpu_is_enabled(ctx: ?*anyopaque) bool;
extern fn tui_raster_gpu_flush(ctx: ?*anyopaque, out_count: *u32) ?*const anyopaque;

extern fn agp_stream_prepare(vs: ?*agp.struct_agp_vstore, base: agp.struct_stream_meta, stream_type: c_uint) agp.struct_stream_meta;
extern fn agp_stream_commit(vs: ?*agp.struct_agp_vstore, meta: agp.struct_stream_meta) void;
extern fn agp_slug_draw_instances(instances: ?*const anyopaque, count: u32, tex_id: u32) void;
extern fn vk_env_texture_matches_size(tex_id: u32, w: u32, h: u32) bool;

extern var arcan_video_display: anyopaque;

fn flagDirty(vobj: *anyopaque) void {
    if (Vobj.getOwner(vobj)) |owner| {
        RenderTarget.incrementTransfc(owner);
    }
    VideoDisplay.incrementDirty(&arcan_video_display);
}

export fn arcan_video_tuisynch(id: c_longlong) void {
    if (is_freestanding_rfun) return;
    const vobj = arcan_video_getobject(id) orelse return;
    const vs = Vobj.getVstore(vobj) orelse return;
    const group_ptr: ?*fontgroup = @ptrCast(@alignCast(AgpVstore.getTpackGroup(vs)));
    const raster = arcan_renderfun_fontraster(group_ptr) orelse return;
    const tui = AgpVstore.getTpackTui(vs);

    var pack_sz = tui_screen_tpack_sz(tui);
    const buf_ptr: ?*anyopaque = malloc(pack_sz);
    const buf: [*]u8 = @ptrCast(buf_ptr orelse return);
    defer free(buf_ptr);

    pack_sz = tui_screen_tpack(tui, .{}, buf, pack_sz);

    var stream = std.mem.zeroes(agp.struct_stream_meta);
    if (tui_raster_renderagp(raster, vs, buf, pack_sz, &stream) != -1) {
        var gpu_count: u32 = 0;
        const instances = tui_raster_gpu_flush(raster, &gpu_count);
        var tex_id = AgpVstore.getGlid(vs);
        const vsw: u32 = @intCast(AgpVstore.getW(vs));
        const vsh: u32 = @intCast(AgpVstore.getH(vs));
        if (tex_id == 0 or !vk_env_texture_matches_size(tex_id, vsw, vsh)) {
            // Texture missing or wrong size — recreate
            stream = agp_stream_prepare(@ptrCast(@alignCast(vs)), stream, agp.STREAM_RAW_DIRECT);
            agp_stream_commit(@ptrCast(@alignCast(vs)), stream);
            tex_id = AgpVstore.getGlid(vs);
        }
        agp_slug_draw_instances(if (instances) |i| @as(?*const anyopaque, @ptrCast(i)) else null, gpu_count, tex_id);
    }

    flagDirty(vobj);
}
