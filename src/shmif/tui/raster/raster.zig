// Pure Zig port of raster.c — TUI raster: cell unpacking, glyph drawing,
// cursor rendering, and buffer-to-pixel rasterization.
//
// Compiled with NO_ARCAN_AGP in the TUI library context, so
// tui_raster_renderagp is not included (it requires agp_vstore / stream_meta
// from the AGP platform layer).

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

const shmif_pixel = u32;
const Allocator = std.heap.c_allocator;

const c = @import("shmif_types");

// Local tui_font layout (mirrors struct tui_font from raster.h)
// shmif_types.tui_font is opaque (_data:[8]u8) — define real layout here.
// Layout verified: union ptr@0, vector@8, fd@12, hint@16, sizeof=24.
const tui_pixelfont = opaque {};
const TTF_Font = c.TTF_Font;

const TuiFont = extern struct {
    unnamed_0: extern union {
        bitmap: ?*tui_pixelfont,
        truetype: ?*TTF_Font,
    },
    vector: bool,
    _pad: [3]u8 = .{ 0, 0, 0 },
    fd: c_int,
    hint: c_int,
    _pad2: [4]u8 = .{ 0, 0, 0, 0 },
};

// Extern TTF/pixelfont functions with correct signatures
// (shmif_types.zig has simplified signatures that don't match the real impls)
extern fn tui_pixelfont_draw(
    ctx: ?*tui_pixelfont,
    vidp: [*]shmif_pixel,
    pitch: usize,
    cp: u32,
    x: c_int,
    y: c_int,
    fg: shmif_pixel,
    bg: shmif_pixel,
    maxx: c_int,
    maxy: c_int,
    bgign: bool,
) void;

extern fn TTF_SetFontStyle(font: ?*TTF_Font, style: c_int) void;

extern fn TTF_RenderUNICODEglyph(
    dst: [*c]shmif_pixel,
    width: usize,
    height: usize,
    stride: c_int,
    font: [*c]?*TTF_Font,
    n: usize,
    ch: u32,
    xstart: [*c]c_uint,
    fg: [*c]u8,
    bg: [*c]u8,
    usebg: bool,
    use_kerning: bool,
    style: c_int,
    advance: [*c]c_int,
    prev_index: [*c]c_uint,
) bool;

// Constants from raster_const.h
const raster_cell_sz: usize = 12;
const raster_hdr_sz: usize = 16;
const raster_line_sz: usize = 9;

// Constants from raster.h enums

// cell_attr
const CATTR_BOLD: u8 = 1;
const CATTR_UNDERLINE: u8 = 2;
const CATTR_UNDERLINE_ALT: u8 = 4;
const CATTR_ITALIC: u8 = 8;
const CATTR_STRIKETHROUGH: u8 = 16;
const CATTR_CURSOR: u8 = 32;
const CATTR_SHAPEBREAK: u8 = 64;
const CATTR_SKIP: u8 = 128;

// cell_extr_attr
const CEATTR_BORDER_R: u8 = 4;
const CEATTR_BORDER_D: u8 = 8;
const CEATTR_BORDER_L: u8 = 16;
const CEATTR_BORDER_T: u8 = 32;

// cursor_states
const CURSOR_ACTIVE: u8 = 2;
const CURSOR_EXTHDRv1: u8 = 8;
const CURSOR_BLOCK: u8 = 16;
const CURSOR_BAR: u8 = 32;
const CURSOR_UNDER: u8 = 64;
const CURSOR_HOLLOW: u8 = 128;

// raster_flags
const RPACK_DFRAME: u16 = 2;

// TTF style constants
const TTF_STYLE_NORMAL: c_int = 0x00;
const TTF_STYLE_BOLD: c_int = 0x01;
const TTF_STYLE_ITALIC: c_int = 0x02;

// draw_box_px (inline from draw.h)
fn draw_box_px(
    px: [*]shmif_pixel,
    pitch: usize,
    max_w: usize,
    max_h: usize,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
    col: shmif_pixel,
) void {
    if (x >= max_w or y >= max_h or x + w > max_w or y + h > max_h) return;
    const ux = if (x + w > max_w) max_w else x + w;
    const uy = if (y + h > max_h) max_h else y + h;
    var cy = y;
    while (cy < uy) : (cy += 1) {
        var cx = x;
        while (cx < ux) : (cx += 1) {
            px[cy * pitch + cx] = col;
        }
    }
}

// SHMIF_RGBA / SHMIF_RGBA_DECOMP (inline from arcan_shmif_defs.h)
inline fn SHMIF_RGBA(r_: u8, g_: u8, b_: u8, a_: u8) shmif_pixel {
    return (@as(u32, a_) << 24) |
        (@as(u32, r_) << 16) |
        (@as(u32, g_) << 8) |
        (@as(u32, b_));
}

const RgbaComponents = struct { r: u8, g: u8, b: u8, a: u8 };

inline fn SHMIF_RGBA_DECOMP(val: shmif_pixel) RgbaComponents {
    return .{
        .b = @truncate(val & 0x000000ff),
        .g = @truncate((val & 0x0000ff00) >> 8),
        .r = @truncate((val & 0x00ff0000) >> 16),
        .a = @truncate((val & 0xff000000) >> 24),
    };
}

// Internal types

const Cell = struct {
    fc: shmif_pixel,
    bc: shmif_pixel,
    ucs4: u32,
    attr: u8,
    attr_ext: u8,
};

const ExtCursorFn = *const fn (
    *TuiRasterContext,
    usize,
    usize,
    usize,
    usize,
    usize,
    usize,
    c_int,
    [*]u8,
    ?*anyopaque,
) callconv(.c) void;

const TuiRasterContext = extern struct {
    fonts: [4]?*TuiFont,
    last_style: c_int,
    cursor_state: c_int,
    cc: shmif_pixel,
    ext_cursor: ?ExtCursorFn,
    cell_w: usize,
    cell_h: usize,
    min_x: usize,
    min_y: usize,
    max_x: usize,
    max_y: usize,
};

// Exported public API

export fn tui_raster_setfont(
    ctx: ?*TuiRasterContext,
    src: [*]?*TuiFont,
    n_fonts: usize,
) void {
    if (is_freestanding) return;
    const self = ctx orelse return;
    for (0..4) |i| {
        self.fonts[i] = if (i < n_fonts) src[i] else null;
    }
    self.last_style = -1;
}

export fn tui_raster_setup(cell_w: usize, cell_h: usize) ?*TuiRasterContext {
    if (is_freestanding) return null;
    const res = Allocator.create(TuiRasterContext) catch return null;
    res.* = .{
        .fonts = .{ null, null, null, null },
        .last_style = -1,
        .cursor_state = 0,
        .cc = SHMIF_RGBA(0x00, 0xaa, 0x00, 0xff),
        .ext_cursor = null,
        .cell_w = cell_w,
        .cell_h = cell_h,
        .min_x = 0,
        .min_y = 0,
        .max_x = 0,
        .max_y = 0,
    };
    return res;
}

export fn tui_raster_get_cell_size(
    ctx: ?*TuiRasterContext,
    w: *usize,
    h: *usize,
) void {
    if (is_freestanding) return;
    const self = ctx orelse return;
    w.* = self.cell_w;
    h.* = self.cell_h;
}

export fn tui_raster_cell_size(ctx: ?*TuiRasterContext, w: usize, h: usize) void {
    if (is_freestanding) return;
    const self = ctx orelse return;
    self.cell_w = w;
    self.cell_h = h;
}

export fn tui_raster_cursor_color(ctx: ?*TuiRasterContext, col: [*]u8) void {
    if (is_freestanding) return;
    const self = ctx orelse return;
    self.cc = SHMIF_RGBA(col[0], col[1], col[2], 0xff);
}

export fn tui_raster_cursor_control(
    ctx: ?*TuiRasterContext,
    ext_cursor: ?ExtCursorFn,
    _: ?*anyopaque, // tag — stored externally, not used here
) void {
    if (is_freestanding) return;
    const self = ctx orelse return;
    self.ext_cursor = ext_cursor;
}

export fn tui_raster_offset(
    ctx: ?*TuiRasterContext,
    px_x: usize,
    _: usize, // row
    offset: *usize,
) void {
    if (is_freestanding) return;
    _ = ctx;
    offset.* = px_x;
}

export fn tui_raster_render(
    ctx: ?*TuiRasterContext,
    dst: [*c]c.arcan_shmif_cont,
    buf: [*]u8,
    buf_sz: usize,
) c_int {
    if (is_freestanding) return -1;
    const self = ctx orelse return -1;
    if (self.fonts[0] == null or buf_sz < raster_hdr_sz)
        return -1;

    const vidp: [*]shmif_pixel = dst.*.unnamed_0.vidp orelse return -1;

    var x1: u16 = undefined;
    var y1: u16 = undefined;
    var x2: u16 = undefined;
    var y2: u16 = undefined;

    if (raster_tobuf(
        self,
        vidp,
        dst.*.pitch,
        dst.*.w,
        dst.*.h,
        &x1,
        &y1,
        &x2,
        &y2,
        buf,
        buf_sz,
    ) == -1)
        return -1;

    if (x2 > @as(u16, @intCast(dst.*.w)))
        x2 = @intCast(dst.*.w);

    _ = c.arcan_shmif_dirty(dst, x1, y1, x2, y2, 0);
    return 1;
}

export fn tui_raster_free(ctx: ?*TuiRasterContext) void {
    if (is_freestanding) return;
    const self = ctx orelse return;
    Allocator.destroy(self);
}

// Static helpers

fn unpack_u32(inbuf: [*]u8) u32 {
    return (@as(u32, inbuf[0]) << 0) |
        (@as(u32, inbuf[1]) << 8) |
        (@as(u32, inbuf[2]) << 16) |
        (@as(u32, inbuf[3]) << 24);
}

fn unpack_cell(unpack: [*]u8, alpha: u8) Cell {
    return .{
        .fc = SHMIF_RGBA(unpack[0], unpack[1], unpack[2], 0xff),
        .bc = SHMIF_RGBA(unpack[3], unpack[4], unpack[5], alpha),
        .attr = unpack[6],
        .attr_ext = unpack[7],
        .ucs4 = unpack_u32(unpack + 8),
    };
}

fn drawborder_edge(
    ctx: *TuiRasterContext,
    cell: *Cell,
    vidp: [*]shmif_pixel,
    pitch: usize,
    x: usize,
    y: usize,
    maxx: usize,
    maxy: usize,
    bv: u8,
) void {
    // increase the border size when the cell size goes up, but keep uniform
    var n_row = (ctx.cell_h + 15) / 16;
    var n_col = (ctx.cell_w + 15) / 16;

    if (n_row > n_col)
        n_row = n_col
    else
        n_col = n_row;

    if (bv & CEATTR_BORDER_T != 0) {
        draw_box_px(vidp, pitch, maxx, maxy, x, y, ctx.cell_w, n_row, cell.fc);
    }

    if (bv & CEATTR_BORDER_D != 0) {
        const by = y + ctx.cell_h -| n_row;
        draw_box_px(vidp, pitch, maxx, maxy, x, by, ctx.cell_w, n_row, cell.fc);
    }

    if (bv & CEATTR_BORDER_L != 0) {
        draw_box_px(vidp, pitch, maxx, maxy, x, y, n_col, ctx.cell_h, cell.fc);
    }

    if (bv & CEATTR_BORDER_R != 0) {
        const bx = x + ctx.cell_w -| n_col;
        draw_box_px(vidp, pitch, maxx, maxy, bx, y, n_col, ctx.cell_h, cell.fc);
    }
}

fn linehint(
    ctx: *TuiRasterContext,
    cell: *Cell,
    vidp: [*]shmif_pixel,
    pitch: usize,
    x: usize,
    y: usize,
    maxx: usize,
    maxy: usize,
    strikethrough: bool,
    underline: bool,
) void {
    if (underline) {
        const n_lines = @as(usize, @intFromFloat(@as(f64, @floatFromInt(ctx.cell_h)) * 0.05)) | 1;
        draw_box_px(vidp, pitch, maxx, maxy,
            x, y + ctx.cell_h -| n_lines, ctx.cell_w, n_lines, cell.fc);
    }

    if (strikethrough) {
        const n_lines = @as(usize, @intFromFloat(@as(f64, @floatFromInt(ctx.cell_h)) * 0.05)) | 1;
        const half_h = ctx.cell_h >> 1;
        const half_n = n_lines >> 1;
        draw_box_px(vidp, pitch, maxx, maxy,
            x, y + half_h -| half_n, ctx.cell_w, n_lines, cell.fc);
    }
}

fn drawcursor_px(
    ctx: *TuiRasterContext,
    vidp: [*]shmif_pixel,
    pitch: usize,
    x: usize,
    y: usize,
    maxx: usize,
    maxy: usize,
    cc: shmif_pixel,
) void {
    var cell = Cell{
        .fc = cc,
        .bc = 0,
        .ucs4 = 0,
        .attr = 0,
        .attr_ext = 0,
    };

    const state: u8 = @intCast(ctx.cursor_state & 0xff);
    if (state & CURSOR_UNDER != 0) {
        drawborder_edge(ctx, &cell, vidp, pitch, x, y, maxx, maxy, CEATTR_BORDER_D);
    } else if (state & CURSOR_HOLLOW != 0) {
        drawborder_edge(ctx, &cell, vidp, pitch, x, y, maxx, maxy,
            CEATTR_BORDER_D | CEATTR_BORDER_T | CEATTR_BORDER_L | CEATTR_BORDER_R);
    } else if (state & CURSOR_BAR != 0) {
        drawborder_edge(ctx, &cell, vidp, pitch, x, y, maxx, maxy, CEATTR_BORDER_L);
    }
}

fn drawglyph(
    ctx: *TuiRasterContext,
    cell: *Cell,
    vidp: [*]shmif_pixel,
    pitch: usize,
    x: usize,
    y: usize,
    maxx: usize,
    maxy: usize,
) usize {
    var draw_cursor = false;

    const font0 = ctx.fonts[0] orelse return ctx.cell_w;

    if (!font0.vector) {
        // Bitmap font path
        if (cell.attr & CATTR_CURSOR != 0) {
            if (ctx.cursor_state == (CURSOR_ACTIVE | CURSOR_BLOCK))
                cell.bc = ctx.cc
            else
                draw_cursor = true;
        }

        // linear search for cp, on fail, fill with background
        tui_pixelfont_draw(
            font0.unnamed_0.bitmap,
            vidp,
            pitch,
            cell.ucs4,
            @intCast(x),
            @intCast(y),
            cell.fc,
            cell.bc,
            @intCast(maxx),
            @intCast(maxy),
            false,
        );

        // add line-marks
        if (cell.ucs4 != 0 and
            (cell.attr & (CATTR_STRIKETHROUGH | CATTR_UNDERLINE) != 0))
        {
            linehint(ctx, cell, vidp, pitch, x, y, maxx, maxy,
                cell.attr & CATTR_STRIKETHROUGH != 0,
                cell.attr & CATTR_UNDERLINE != 0);
        }

        drawborder_edge(ctx, cell, vidp, pitch, x, y, maxx, maxy, cell.attr_ext);

        if (draw_cursor) {
            drawcursor_px(ctx, vidp, pitch, x, y, maxx, maxy, ctx.cc);
        }

        return ctx.cell_w;
    }

    // Vector font drawing
    var nfonts: usize = 1;
    var fonts: [2]?*TTF_Font = .{ font0.unnamed_0.truetype, null };
    if (ctx.fonts[1]) |font1| {
        if (font1.vector and font1.unnamed_0.truetype != null) {
            nfonts = 2;
            fonts[1] = font1.unnamed_0.truetype;
        }
    }

    // Clear to bg-color; use cursor color if applicable
    var bc = cell.bc;
    if (cell.attr & CATTR_CURSOR != 0) {
        if (ctx.cursor_state == (CURSOR_ACTIVE | CURSOR_BLOCK)) {
            bc = ctx.cc;
        } else {
            draw_cursor = true;
        }
    }

    draw_box_px(vidp, pitch, maxx, maxy, x, y, ctx.cell_w, ctx.cell_h, bc);

    // fast-path: just clear to background and draw line attrs
    if (cell.ucs4 == 0) {
        drawborder_edge(ctx, cell, vidp, pitch, x, y, maxx, maxy, cell.attr_ext);
        if (draw_cursor) {
            drawcursor_px(ctx, vidp, pitch, x, y, maxx, maxy, ctx.cc);
        }
        return ctx.cell_w;
    }

    var prem: c_int = TTF_STYLE_NORMAL;
    if (cell.attr & CATTR_ITALIC != 0) prem |= TTF_STYLE_ITALIC;
    if (cell.attr & CATTR_BOLD != 0) prem |= TTF_STYLE_BOLD;

    // Only update style when changed (expensive, can flush glyph cache)
    if (prem != ctx.last_style) {
        ctx.last_style = prem;
        TTF_SetFontStyle(fonts[0], prem);
        if (fonts[1]) |f1| {
            TTF_SetFontStyle(f1, prem);
        }
    }

    const fg_decomp = SHMIF_RGBA_DECOMP(cell.fc);
    const bg_decomp = SHMIF_RGBA_DECOMP(bc);
    var fg = [4]u8{ fg_decomp.r, fg_decomp.g, fg_decomp.b, fg_decomp.a };
    var bg_arr = [4]u8{ bg_decomp.r, bg_decomp.g, bg_decomp.b, bg_decomp.a };

    var adv: c_int = 0;
    var xs: c_uint = 0;
    var ind: c_uint = 0;

    // Cast [2]?*TTF_Font to [*c]?*TTF_Font for C call
    var fonts_arr: [2]?*TTF_Font = fonts;
    _ = TTF_RenderUNICODEglyph(
        vidp + y * pitch + x,
        ctx.cell_w,
        ctx.cell_h,
        @intCast(pitch),
        @ptrCast(&fonts_arr),
        nfonts,
        cell.ucs4,
        &xs,
        &fg,
        &bg_arr,
        true,
        true,
        ctx.last_style,
        &adv,
        &ind,
    );

    // add line-marks
    if (cell.ucs4 != 0 and
        (cell.attr & (CATTR_STRIKETHROUGH | CATTR_UNDERLINE) != 0))
    {
        linehint(ctx, cell, vidp, pitch, x, y, maxx, maxy,
            cell.attr & CATTR_STRIKETHROUGH != 0,
            cell.attr & CATTR_UNDERLINE != 0);
    }

    drawborder_edge(ctx, cell, vidp, pitch, x, y, maxx, maxy, cell.attr_ext);
    if (draw_cursor) {
        drawcursor_px(ctx, vidp, pitch, x, y, maxx, maxy, ctx.cc);
    }

    return ctx.cell_w;
}

// Packed header/line structs for memcpy from buffer

const TuiRasterHeader = extern struct {
    data_sz: u32,
    lines: u16,
    cells: u16,
    direction: u8,
    flags: u16 align(1),
    bgc: [4]u8,
    cursor_state: u8,
};

const TuiRasterLine = extern struct {
    start_line: u16,
    ncells: u16,
    offset: u16,
    content_dir: u8,
    scroll_dir: u8,
    line_state: u8,
};

fn raster_tobuf(
    ctx: *TuiRasterContext,
    vidp: [*]shmif_pixel,
    pitch: usize,
    max_w: usize,
    max_h: usize,
    x1: *u16,
    y1: *u16,
    x2: *u16,
    y2: *u16,
    buf_in: [*]u8,
    buf_sz_in: usize,
) c_int {
    if (buf_sz_in == 0 or buf_sz_in < @sizeOf(TuiRasterHeader))
        return -1;

    var buf = buf_in;
    var buf_sz = buf_sz_in;

    // Read header via memcpy (packed struct)
    var hdr: TuiRasterHeader = undefined;
    @memcpy(
        @as([*]u8, @ptrCast(&hdr))[0..@sizeOf(TuiRasterHeader)],
        buf[0..@sizeOf(TuiRasterHeader)],
    );

    const update = (hdr.flags & RPACK_DFRAME) != 0;
    const extcursor = (hdr.cursor_state & CURSOR_EXTHDRv1) != 0;

    // Verify header data_sz against computed size
    const hdr_ver_sz: usize = @as(usize, hdr.lines) * raster_line_sz +
        @as(usize, hdr.cells) * raster_cell_sz + raster_hdr_sz +
        @as(usize, @intFromBool(extcursor)) * 3;

    if (hdr.data_sz > buf_sz or hdr.data_sz != hdr_ver_sz) {
        return -1;
    }

    buf_sz -= @sizeOf(TuiRasterHeader);
    buf += @sizeOf(TuiRasterHeader);

    if (extcursor) {
        tui_raster_cursor_color(ctx, buf);
        buf_sz -= 3;
        buf += 3;
    }

    const bgc = SHMIF_RGBA(hdr.bgc[0], hdr.bgc[1], hdr.bgc[2], hdr.bgc[3]);

    // dframe: set 'always replaced' region
    if (update) {
        y1.* = @intCast(max_h);
        y2.* = 0;
        x1.* = @intCast(max_w);
        x2.* = 0;

        // early out empty dframe
        if (hdr.lines == 0)
            return -1;
    } else {
        // full-frame: pre-clear the pad region
        x1.* = 0;
        y1.* = 0;
        x2.* = @intCast(max_w);
        y2.* = @intCast(max_h);

        const pad_w = max_w % ctx.cell_w;
        const pad_h = max_h % ctx.cell_h;

        if (pad_w != 0) {
            const start = max_w - pad_w;
            draw_box_px(vidp, pitch, max_w, max_h, start, 0, pad_w, max_h, bgc);
        }
        if (pad_h != 0) {
            const start = max_h - pad_h;
            draw_box_px(vidp, pitch, max_w, max_h, 0, start, max_w, pad_h, bgc);
        }
    }

    ctx.cursor_state = @as(c_int, hdr.cursor_state) & ~@as(c_int, CURSOR_EXTHDRv1);

    var cur_y: isize = -1;
    var last_line: usize = 0;
    var draw_y: usize = 0;

    var line_i: u16 = 0;
    while (line_i < hdr.lines and buf_sz > 0) : (line_i += 1) {
        if (buf_sz < @sizeOf(TuiRasterLine))
            return -1;

        // read / unpack line metadata
        var line: TuiRasterLine = undefined;
        @memcpy(
            @as([*]u8, @ptrCast(&line))[0..@sizeOf(TuiRasterLine)],
            buf[0..@sizeOf(TuiRasterLine)],
        );
        buf += @sizeOf(TuiRasterLine);
        buf_sz -= @sizeOf(TuiRasterLine);

        // remember the lowest line we were at
        if (line.start_line > last_line)
            last_line = line.start_line;

        if (update and cur_y == -1) {
            y1.* = @intCast(@as(usize, line.start_line) * ctx.cell_h);
        }

        // skip omitted lines
        if (cur_y != @as(isize, line.start_line)) {
            cur_y = line.start_line;
        }
        draw_y = @intCast(@as(usize, @intCast(cur_y)) * ctx.cell_h);

        if (draw_y < y1.*) {
            y1.* = @intCast(draw_y);
        }

        // Shaping, BiDi, ... missing here now while we get the rest in place
        var draw_x: usize = @as(usize, line.offset) * ctx.cell_w;

        if (draw_x < x1.*) {
            x1.* = @intCast(draw_x);
        }

        var cell_i: usize = line.offset;
        var remaining_cells = line.ncells;
        while (remaining_cells > 0 and buf_sz >= raster_cell_sz) {
            remaining_cells -= 1;

            // extract each cell
            var cell = unpack_cell(buf, hdr.bgc[3]);
            buf += raster_cell_sz;
            buf_sz -= raster_cell_sz;

            // outsource cursor? invoke external handler
            if ((cell.attr & CATTR_CURSOR != 0) and ctx.ext_cursor != null) {
                const rgba_comp = SHMIF_RGBA_DECOMP(ctx.cc);
                var rgba = [4]u8{ rgba_comp.r, rgba_comp.g, rgba_comp.b, rgba_comp.a };
                ctx.ext_cursor.?(
                    ctx,
                    cell_i,
                    @intCast(cur_y),
                    draw_x,
                    draw_y,
                    ctx.cell_w,
                    ctx.cell_h,
                    ctx.cursor_state,
                    &rgba,
                    null,
                );
                cell.attr &= ~CATTR_CURSOR;
            }

            // skip bit is set
            if (cell.attr & CATTR_SKIP != 0) {
                draw_x += ctx.cell_w;
                cell_i += 1;
                continue;
            }

            // blit or discard if OOB
            if (draw_x + ctx.cell_w <= max_w and draw_y + ctx.cell_h <= max_h) {
                draw_x += drawglyph(ctx, &cell, vidp, pitch, draw_x, draw_y, max_w, max_h);
            }

            if (x2.* < @as(u16, @intCast(@min(draw_x, std.math.maxInt(u16)))) and draw_x <= max_w) {
                x2.* = @intCast(draw_x);
            }

            cell_i += 1;
        }

        cur_y += 1;
    }

    y2.* = @intCast((last_line + 1) * ctx.cell_h);

    return 1;
}
