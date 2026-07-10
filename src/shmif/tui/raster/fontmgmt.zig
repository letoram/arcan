// Pure Zig port of tui/raster/fontmgmt.c
//
// Font management for the TUI raster: loading/switching truetype and bitmap
// fonts, responding to FONTHINT events, and setting up the initial font state.
//
// Key design choices:
// - tui_context is opaque; all field accesses go through verified byte offsets
//   (computed by compute_offsets.c on aarch64-linux).
// - tui_font fields also accessed via byte offsets (sizeof=24, from raster.h).
// - arcan_tgtevent is known from the arcan module (arcan_zig_types.zig).
// - TTF_Font and tui_pixelfont remain opaque — only passed through extern fn.

const std = @import("std");
const arcan = @import("arcan");

// Constants

const BADFD: c_int = -1;

// TTF style/hinting (from arcan_ttf.h)
const TTF_STYLE_NORMAL: c_int = 0x00;
const TTF_HINTING_NORMAL: c_int = 3;

// dirty_state values (from tui_int.h)
const DIRTY_FULL: c_int = 4;

// fseek whence constants
const SEEK_END: c_int = 2;
const SEEK_SET: c_int = 0;

// Opaque C types

// TTF_Font (typedef struct c_font_ref TTF_Font) — only passed as pointer.
const TTF_Font = opaque {};

// tui_pixelfont — only passed as pointer.
const tui_pixelfont = opaque {};

// tui_raster_context — only passed as pointer.
const tui_raster_context = opaque {};

// tui_context field offsets (aarch64-linux, from compute_offsets.c)
//
// struct tui_context relevant fields:
//   raster      @ 16   *tui_raster_context
//   font[0]     @ 96   *tui_font  (pointer to allocated struct)
//   font[1]     @ 104  *tui_font
//   font_sz     @ 112  f32  (size in mm)
//   hint        @ 116  c_int (TTF_HINTING_*)
//   ppcm        @ 124  f32  (pixels per centimeter)
//   dirty       @ 128  c_int (enum dirty_state)
//   cell_auth   @ 400  bool (server-side has hinted cell dimensions)
//   cell_w      @ 404  c_int
//   cell_h      @ 408  c_int
//   acon        @ 2808 struct arcan_shmif_cont (embedded, not pointer)
//   acon.w      @ 2888 usize  (= acon+80)
//   acon.h      @ 2896 usize  (= acon+88)

const OFF_RASTER: usize = 16;
const OFF_FONT0: usize = 96;
const OFF_FONT1: usize = 104;
const OFF_FONT_SZ: usize = 112;
const OFF_HINT: usize = 116;
const OFF_PPCM: usize = 124;
const OFF_DIRTY: usize = 128;
const OFF_CELL_AUTH: usize = 400;
const OFF_CELL_W: usize = 404;
const OFF_CELL_H: usize = 408;
const OFF_ACON: usize = 2808;
const OFF_ACON_W: usize = 2888;
const OFF_ACON_H: usize = 2896;

// tui_font field offsets (sizeof=24, from compute_offsets.c + raster.h)
//
// struct tui_font layout:
//   union { *tui_pixelfont bitmap; *TTF_Font truetype; }  @ 0   (8 bytes, pointer)
//   bool vector                                            @ 8
//   int  fd                                               @ 12
//   int  hint                                             @ 16

const FONT_OFF_PTR: usize = 0;
const FONT_OFF_VECTOR: usize = 8;
const FONT_OFF_FD: usize = 12;
const FONT_SIZEOF: usize = 24;

// Byte-offset helpers

inline fn bytePtr(base: *anyopaque, off: usize) [*]u8 {
    return @as([*]u8, @ptrCast(base)) + off;
}

inline fn readAt(comptime T: type, base: *anyopaque, off: usize) T {
    const p: *align(1) const T = @ptrCast(bytePtr(base, off));
    return p.*;
}

inline fn writeAt(comptime T: type, base: *anyopaque, off: usize, val: T) void {
    const p: *align(1) T = @ptrCast(bytePtr(base, off));
    p.* = val;
}

// tui_context accessors

fn getRaster(tui: *anyopaque) ?*tui_raster_context {
    return readAt(?*tui_raster_context, tui, OFF_RASTER);
}

fn setRaster(tui: *anyopaque, v: ?*tui_raster_context) void {
    writeAt(?*tui_raster_context, tui, OFF_RASTER, v);
}

fn getFont0(tui: *anyopaque) ?*anyopaque {
    return readAt(?*anyopaque, tui, OFF_FONT0);
}

fn getFont1(tui: *anyopaque) ?*anyopaque {
    return readAt(?*anyopaque, tui, OFF_FONT1);
}

fn setFont0(tui: *anyopaque, v: ?*anyopaque) void {
    writeAt(?*anyopaque, tui, OFF_FONT0, v);
}

fn setFont1(tui: *anyopaque, v: ?*anyopaque) void {
    writeAt(?*anyopaque, tui, OFF_FONT1, v);
}

fn getFontSz(tui: *anyopaque) f32 {
    return readAt(f32, tui, OFF_FONT_SZ);
}

fn setFontSz(tui: *anyopaque, v: f32) void {
    writeAt(f32, tui, OFF_FONT_SZ, v);
}

fn getHint(tui: *anyopaque) c_int {
    return readAt(c_int, tui, OFF_HINT);
}

fn setHint(tui: *anyopaque, v: c_int) void {
    writeAt(c_int, tui, OFF_HINT, v);
}

fn getPpcm(tui: *anyopaque) f32 {
    return readAt(f32, tui, OFF_PPCM);
}

fn setDirty(tui: *anyopaque, v: c_int) void {
    writeAt(c_int, tui, OFF_DIRTY, v);
}

fn getCellAuth(tui: *anyopaque) bool {
    return readAt(bool, tui, OFF_CELL_AUTH);
}

fn getCellW(tui: *anyopaque) c_int {
    return readAt(c_int, tui, OFF_CELL_W);
}

fn setCellW(tui: *anyopaque, v: c_int) void {
    writeAt(c_int, tui, OFF_CELL_W, v);
}

fn getCellH(tui: *anyopaque) c_int {
    return readAt(c_int, tui, OFF_CELL_H);
}

fn setCellH(tui: *anyopaque, v: c_int) void {
    writeAt(c_int, tui, OFF_CELL_H, v);
}

// Returns a pointer to the embedded acon (not a pointer-to-pointer).
fn getAconPtr(tui: *anyopaque) *anyopaque {
    return @ptrCast(bytePtr(tui, OFF_ACON));
}

fn getAconW(tui: *anyopaque) usize {
    return readAt(usize, tui, OFF_ACON_W);
}

fn getAconH(tui: *anyopaque) usize {
    return readAt(usize, tui, OFF_ACON_H);
}

// tui_font accessors (via opaque pointer)

fn fontIsVector(font: *anyopaque) bool {
    return readAt(bool, font, FONT_OFF_VECTOR);
}

fn fontSetVector(font: *anyopaque, v: bool) void {
    writeAt(bool, font, FONT_OFF_VECTOR, v);
}

fn fontGetTruetype(font: *anyopaque) ?*TTF_Font {
    return readAt(?*TTF_Font, font, FONT_OFF_PTR);
}

fn fontSetTruetype(font: *anyopaque, v: ?*TTF_Font) void {
    writeAt(?*TTF_Font, font, FONT_OFF_PTR, v);
}

fn fontGetBitmap(font: *anyopaque) ?*tui_pixelfont {
    return readAt(?*tui_pixelfont, font, FONT_OFF_PTR);
}

fn fontSetBitmap(font: *anyopaque, v: ?*tui_pixelfont) void {
    writeAt(?*tui_pixelfont, font, FONT_OFF_PTR, v);
}

fn fontGetFd(font: *anyopaque) c_int {
    return readAt(c_int, font, FONT_OFF_FD);
}

fn fontSetFd(font: *anyopaque, v: c_int) void {
    writeAt(c_int, font, FONT_OFF_FD, v);
}

// External C function declarations

// Math (arcan_math.c — compiled separately into each target that uses TUI)
extern fn arcan_mm_to_pt(mm: f32) usize;
extern fn arcan_pt_to_mm(pt: usize) f32;

// TTF API (arcan_ttf.c)
extern fn TTF_Init() c_int;
extern fn TTF_OpenFontFD(fd: c_int, ptsize: c_int, hdpi: u16, vdpi: u16) ?*TTF_Font;
extern fn TTF_CloseFont(font: *TTF_Font) void;
extern fn TTF_SetFontStyle(font: *TTF_Font, style: c_int) void;
extern fn TTF_SetFontHinting(font: *TTF_Font, hinting: c_int) void;
extern fn TTF_ProbeFont(font: *TTF_Font, dw: *usize, dh: *usize) void;
extern fn TTF_FindGlyph(fonts: [*]?*TTF_Font, n: c_int, ch: u32, want: c_int, by_ind: bool) ?*TTF_Font;

// Pixel font API (pixelfont.c)
extern fn tui_pixelfont_open(limit: usize) ?*tui_pixelfont;
extern fn tui_pixelfont_close(ctx: *tui_pixelfont) void;
extern fn tui_pixelfont_hascp(ctx: *tui_pixelfont, cp: u32) bool;
extern fn tui_pixelfont_setsz(ctx: *tui_pixelfont, px: usize, w: *usize, h: *usize) void;
extern fn tui_pixelfont_load(ctx: *tui_pixelfont, buf: [*]u8, buf_sz: usize, px_sz: usize, merge: bool) bool;
extern fn tui_pixelfont_valid(buf: [*]const u8, buf_sz: usize) bool;

// Raster API (raster.c)
extern fn tui_raster_setup(cell_w: usize, cell_h: usize) ?*tui_raster_context;
extern fn tui_raster_cell_size(ctx: *tui_raster_context, w: usize, h: usize) void;
// void tui_raster_setfont(ctx, struct tui_font** src, size_t n_fonts)
// src is the address of tui->font[0] (array of two *tui_font pointers)
extern fn tui_raster_setfont(ctx: *tui_raster_context, src: [*]?*anyopaque, n_fonts: usize) void;

// Screen API (screen.c)
extern fn tui_screen_resized(tui: *anyopaque) void;

// shmif API
extern fn arcan_shmif_dupfd(fd: c_int, dstnum: c_int, nonblocking: bool) c_int;
extern fn arcan_shmif_resize_ext(ctx: *anyopaque, width: c_uint, height: c_uint, req: ShmifResizeExt) bool;

// C stdlib
extern fn malloc(sz: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn memset(ptr: *anyopaque, c: c_int, n: usize) *anyopaque;
extern fn ceilf(x: f32) f32;

// C POSIX file I/O
extern fn dup(fd: c_int) c_int;
extern fn fdopen(fd: c_int, mode: [*c]const u8) ?*anyopaque;
extern fn fseek(stream: *anyopaque, offset: c_long, whence: c_int) c_int;
extern fn ftell(stream: *anyopaque) c_long;
extern fn fread(ptr: *anyopaque, size: usize, nmemb: usize, stream: *anyopaque) usize;
extern fn fclose(stream: *anyopaque) c_int;

// fprintf to stderr for LOG() macro equivalent
extern fn fprintf(stream: *anyopaque, fmt: [*c]const u8, ...) c_int;
extern var stderr: *anyopaque;

// shmif_resize_ext (used in tui_fontmgmt_invalidate)
// Matches struct shmif_resize_ext from arcan_shmif_control.h.
// Verified offsets: meta@0, abuf_sz@8, abuf_cnt@16, samplerate@24,
//                   vbuf_cnt@32, rows@40, cols@48.

const ShmifResizeExt = extern struct {
    meta: u32 = 0,
    abuf_sz: usize = 0,
    abuf_cnt: isize,
    samplerate: isize = 0,
    vbuf_cnt: isize,
    rows: usize,
    cols: usize,
    nops: usize = 0,
    op_fm: usize = 0,
};

// arcan_shmif_initial font sub-struct (used in tui_fontmgmt_setup)
// Only the fonts[4] array is needed here.
// Each fonts[i] = { int fd; int type; int hinting; float size_mm; } (16 bytes).
// fonts[0].fd @ 0, fonts[0].size_mm @ 12
// fonts[1].fd @ 16, fonts[1].size_mm @ 28

const InitialFont = extern struct {
    fd: c_int,
    @"type": c_int,
    hinting: c_int,
    size_mm: f32,
};

// Only fonts[4] is accessed; the rest is opaque padding.
const ArcanShmifInitial = extern struct {
    fonts: [4]InitialFont,
    // remainder of struct not accessed here (density, display dims, etc.)
};

// Static (internal) helper functions

/// Load or replace the truetype font in font slot [mode==0 → 0, else 1].
/// Takes ownership of fd (via TTF_OpenFontFD). Returns true on success.
fn tryload_truetype(
    tui: *anyopaque,
    fd: c_int,
    mode: c_int,
    pt_size: usize,
    dpi: f32,
) bool {
    const slot: usize = if (mode == 0) 0 else 1;
    const font_slot: *anyopaque = (if (slot == 0) getFont0(tui) else getFont1(tui)) orelse
        return false;

    const dpi_u16: u16 = @intFromFloat(@max(0.0, @min(65535.0, dpi)));
    const new_font = TTF_OpenFontFD(fd, @intCast(pt_size), dpi_u16, dpi_u16) orelse
        return false;

    _ = fprintf(stderr, "open_font(%zu pt, %f dpi)\n", pt_size, dpi);

    // Release any pre-existing font in this slot
    if (fontIsVector(font_slot)) {
        if (fontGetTruetype(font_slot)) |old_tt|
            TTF_CloseFont(old_tt);
    } else {
        if (fontGetBitmap(font_slot)) |old_bm|
            tui_pixelfont_close(old_bm);
    }

    fontSetTruetype(font_slot, new_font);
    fontSetFd(font_slot, fd);
    fontSetVector(font_slot, true);
    TTF_SetFontStyle(new_font, TTF_STYLE_NORMAL);
    TTF_SetFontHinting(new_font, getHint(tui));

    // The first slot determines cell size (probe for grid-friendly dimensions)
    if (mode == 0) {
        var dw: usize = 0;
        var dh: usize = 0;
        TTF_ProbeFont(new_font, &dw, &dh);
        if (dw != 0 and dh != 0 and !getCellAuth(tui)) {
            setCellW(tui, @intCast(dw));
            setCellH(tui, @intCast(dh));
        }
        _ = fprintf(stderr, "open_font::probe(%zu, %zu)\n", dw, dh);
    }

    return true;
}

/// Try to load a PSF2 bitmap font from fd into the primary font slot.
/// Slot 1 is cleared when switching to bitmap mode (bitmap merges directly).
/// Returns true on success.
fn tryload_bitmap(
    tui: *anyopaque,
    fd: c_int,
    mode: c_int,
    px_sz: usize,
) bool {
    const work = dup(fd);
    if (work == -1)
        return false;

    const fpek = fdopen(work, "r") orelse return false;

    var rv = false;
    var buf_raw: ?*anyopaque = null;

    load: {
        _ = fseek(fpek, 0, SEEK_END);
        const buf_sz_long = ftell(fpek);
        _ = fseek(fpek, 0, SEEK_SET);

        if (buf_sz_long <= 0) break :load;
        const buf_sz: usize = @intCast(buf_sz_long);

        buf_raw = malloc(buf_sz) orelse break :load;
        const buf_u8: [*]u8 = @ptrCast(buf_raw.?);

        // Read all bytes; not bitmap? bail so caller can try freetype
        if (1 != fread(buf_raw.?, buf_sz, 1, fpek)) break :load;
        _ = fseek(fpek, 0, SEEK_SET);

        if (!tui_pixelfont_valid(buf_u8, buf_sz)) break :load;

        // Switching to bitmap: flush any existing vector fonts
        const font0: *anyopaque = getFont0(tui) orelse break :load;

        if (fontIsVector(font0)) {
            if (fontGetTruetype(font0)) |old_tt|
                TTF_CloseFont(old_tt);
            fontSetVector(font0, false);
            const new_bm = tui_pixelfont_open(64) orelse break :load;
            fontSetBitmap(font0, new_bm);
        }

        // Slot 1 not used for bitmap (merging is done directly into slot 0)
        if (getFont1(tui)) |font1| {
            if (fontIsVector(font1)) {
                fontSetVector(font1, false);
                if (fontGetTruetype(font1)) |old_tt|
                    TTF_CloseFont(old_tt);
                fontSetVector(font1, false);
                fontSetBitmap(font1, null);
            }
        }

        const bm: *tui_pixelfont = fontGetBitmap(font0) orelse break :load;
        rv = tui_pixelfont_load(bm, buf_u8, buf_sz, px_sz, mode == 1);
    }

    free(buf_raw);
    _ = fclose(fpek);
    return rv;
}

/// Core font-size setup / switching logic.
/// font_sz is in millimeters (cm/pt conversion happens here).
/// mode 0 = primary slot, 1 = append/alternate.
fn setup_font(tui: *anyopaque, fd: c_int, font_sz_in: f32, mode: c_int) bool {
    // Keep current size if caller passes <= 0
    var font_sz: f32 = font_sz_in;
    if (!(font_sz > 0))
        font_sz = getFontSz(tui);
    setFontSz(tui, font_sz);

    const pt_size = arcan_mm_to_pt(font_sz);
    // Pixel size for bitmap font (nearest match)
    const px_sz: usize = @intFromFloat(ceilf(arcan_pt_to_mm(pt_size) * 0.1 * getPpcm(tui)));

    // Clamp point size — below 4pt becomes invisible
    const pt_clamped: usize = if (pt_size < 4) 4 else pt_size;

    const modeind: c_int = if (mode >= 1) 1 else 0;

    if (fd != BADFD) {
        // Descriptor provided — try bitmap first, fall back to truetype
        if (tryload_bitmap(tui, fd, modeind, px_sz)) {
            // Update cell size from bitmap font's chosen size
            if (getFont0(tui)) |f0| {
                if (fontGetBitmap(f0)) |bm| {
                    var w: usize = 0;
                    var h: usize = 0;
                    tui_pixelfont_setsz(bm, px_sz, &w, &h);
                    setCellW(tui, @intCast(w));
                    setCellH(tui, @intCast(h));
                }
            }
        } else {
            // Not bitmap — try truetype (may also be ignored if it fails)
            _ = tryload_truetype(tui, fd, mode, pt_clamped, getPpcm(tui) * 2.54);
        }
    } else {
        // No new descriptor — re-apply size to whichever font is active
        if (getFont0(tui)) |f0| {
            if (fontIsVector(f0)) {
                _ = tryload_truetype(tui, fontGetFd(f0), 0, pt_clamped, getPpcm(tui) * 2.54);
            } else {
                // Bitmap: create a fresh container and re-probe the size
                const bm = tui_pixelfont_open(64);
                fontSetBitmap(f0, bm);
                if (bm) |b| {
                    var w: usize = 0;
                    var h: usize = 0;
                    tui_pixelfont_setsz(b, px_sz, &w, &h);
                    setCellW(tui, @intCast(w));
                    setCellH(tui, @intCast(h));
                }
            }
        }
    }

    return true;
}

// Exported functions

/// Check whether any loaded font has a glyph for codepoint [cp].
/// Uses TTF_FindGlyph for truetype, tui_pixelfont_hascp for bitmap.
export fn tui_fontmgmt_hasglyph(tui_opaque: ?*anyopaque, cp: u32) bool {
    const tui = tui_opaque orelse return false;
    const font0: *anyopaque = getFont0(tui) orelse return false;

    if (fontIsVector(font0)) {
        var ary: [2]?*TTF_Font = .{ fontGetTruetype(font0), null };
        var count: c_int = 1;

        if (getFont1(tui)) |font1| {
            if (fontGetTruetype(font1)) |tt1| {
                ary[1] = tt1;
                count += 1;
            }
        }

        return TTF_FindGlyph(&ary, count, cp, 0, false) != null;
    }

    // Bitmap path
    if (fontGetBitmap(font0)) |bm|
        return tui_pixelfont_hascp(bm, cp);

    // No bitmap — assume glyph is present
    return true;
}

/// Process a TARGET_COMMAND_FONTHINT event and update font / dirty state.
/// ev is struct arcan_tgtevent* (matches arcan.arcan_tgtevent layout).
export fn tui_fontmgmt_fonthint(
    tui_opaque: ?*anyopaque,
    ev: ?*const arcan.arcan_tgtevent,
) void {
    const tui = tui_opaque orelse return;
    const tev = ev orelse return;

    // ioevs[0].iv: fd (BADFD = -1 means no new font)
    // ioevs[2].fv: font size in cm (> 0 to use)
    // ioevs[3].iv: hinting mode (-1 = keep current)
    // ioevs[4].iv: font mode (0 = primary, 1 = append/alt)

    var fd: c_int = BADFD;
    if (tev.ioevs[0].iv != BADFD)
        fd = arcan_shmif_dupfd(tev.ioevs[0].iv, -1, true);

    switch (tev.ioevs[3].iv) {
        -1 => {}, // keep current hinting
        else => |hint| setHint(tui, hint),
    }

    const font_sz: f32 = if (tev.ioevs[2].fv > 0) tev.ioevs[2].fv else 0;
    _ = setup_font(tui, fd, font_sz, tev.ioevs[4].iv);

    setDirty(tui, DIRTY_FULL);

    if (getRaster(tui)) |raster|
        tui_raster_cell_size(raster, @intCast(getCellW(tui)), @intCast(getCellH(tui)));

    tui_screen_resized(tui);
}

/// Invalidate cached font state (e.g. after DPI change).
/// If cell dimensions change, request a resize from the server.
export fn tui_fontmgmt_invalidate(tui_opaque: ?*anyopaque) void {
    const tui = tui_opaque orelse return;

    const old_cell_w = getCellW(tui);
    const old_cell_h = getCellH(tui);

    _ = setup_font(tui, BADFD, getFontSz(tui), 0);

    if (old_cell_w != getCellW(tui) or old_cell_h != getCellH(tui)) {
        const acon_w = getAconW(tui);
        const acon_h = getAconH(tui);
        const new_cell_w: usize = @intCast(getCellW(tui));
        const new_cell_h: usize = @intCast(getCellH(tui));

        // NOTE: C code divides acon.h by cell_w and acon.w by cell_h —
        // this matches the original verbatim (likely a pre-existing bug).
        const rows: usize = if (new_cell_w > 0) acon_h / new_cell_w else 0;
        const cols: usize = if (new_cell_h > 0) acon_w / new_cell_h else 0;

        const req = ShmifResizeExt{
            .vbuf_cnt = -1,
            .abuf_cnt = -1,
            .rows = rows,
            .cols = cols,
        };

        if (arcan_shmif_resize_ext(
            getAconPtr(tui),
            @intCast(cols * new_cell_w),
            @intCast(rows * new_cell_h),
            req,
        )) {
            if (getRaster(tui)) |raster|
                tui_raster_cell_size(raster, new_cell_w, new_cell_h);
            tui_screen_resized(tui);
            setDirty(tui, DIRTY_FULL);
        }
    }
}

/// Copy font state from parent into tui (currently a no-op in C).
export fn tui_fontmgmt_inherit(
    tui_opaque: ?*anyopaque,
    parent: ?*anyopaque,
) void {
    _ = tui_opaque;
    _ = parent;
    // deliberately empty — matches the C implementation
}

/// Allocate and initialise font slots; load initial fonts from [init].
/// If init is null, load the built-in default at 3.527780 mm (≈ 10pt at 96 DPI).
export fn tui_fontmgmt_setup(
    tui_opaque: ?*anyopaque,
    init_opaque: ?*anyopaque,
) void {
    const tui = tui_opaque orelse return;

    // Allocate the backing memory for both tui_font structs in one block.
    // tui->font[0] = &fonts[0], tui->font[1] = &fonts[1]
    const alloc_sz = FONT_SIZEOF * 2;
    const fonts_raw = malloc(alloc_sz) orelse return;
    _ = memset(fonts_raw, 0, alloc_sz);

    const fonts_u8: [*]u8 = @ptrCast(fonts_raw);
    setFont0(tui, @ptrCast(fonts_u8));
    setFont1(tui, @ptrCast(fonts_u8 + FONT_SIZEOF));

    _ = TTF_Init();
    setHint(tui, TTF_HINTING_NORMAL);

    if (init_opaque) |init_raw| {
        const init: *ArcanShmifInitial = @ptrCast(@alignCast(init_raw));
        _ = setup_font(tui, init.fonts[0].fd, init.fonts[0].size_mm, 0);
        init.fonts[0].fd = -1;

        if (init.fonts[1].fd != -1) {
            // Note: uses fonts[0].size_mm for the secondary font (matches C)
            _ = setup_font(tui, init.fonts[1].fd, init.fonts[0].size_mm, 1);
            init.fonts[1].fd = -1;
        }
    } else {
        // Built-in default: 16.933 mm ≈ 48pt (matches build.zig HiDPI profile)
        _ = setup_font(tui, -1, 16.933, 0);
    }

    // Create raster context sized for the chosen cell dimensions
    const new_raster = tui_raster_setup(
        @intCast(getCellW(tui)),
        @intCast(getCellH(tui)),
    );
    setRaster(tui, new_raster);

    // Hand the font pointer array to the raster.
    // tui->font is struct tui_font*[2] stored as two adjacent pointers at OFF_FONT0.
    // tui_raster_setfont expects (ctx, struct tui_font** src, n) where src points
    // at the font[0] pointer slot (i.e., the address of tui->font[0]).
    if (new_raster) |raster| {
        const font_arr: [*]?*anyopaque = @ptrCast(@alignCast(bytePtr(tui, OFF_FONT0)));
        tui_raster_setfont(raster, font_arr, 2);
    }
}
