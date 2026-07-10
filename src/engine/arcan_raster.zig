// Pure Zig port of engine/arcan_raster.c — TUI pixel rasterization.
// All opaque struct access via byte-offset accessors (no C helpers).

const std = @import("std");
const offsets = @import("engine_offsets");

// C library imports
const c = struct {
    extern fn malloc(size: usize) ?*anyopaque;
    extern fn free(ptr: ?*anyopaque) void;
    extern fn arcan_shmif_dirty(cont: *anyopaque, x1: usize, y1: usize, x2: usize, y2: usize, fl: c_int) c_int;

    // Slug glyph atlas (exported from arcan_ttf.zig)
    extern fn slug_atlas_lookup(font_ptr: ?*anyopaque, codepoint: u32, out: *GlyphInstanceLookup) void;
    extern fn slug_atlas_invalidate() void;

    // Cache font pointer for ADMM calibration (exported from vk_shared.zig)
    extern fn slug_cache_font_ptr(font_ptr: ?*anyopaque) void;

    // Pixelfont
    extern fn tui_pixelfont_draw(
        ctx: *anyopaque,
        dst: [*]u32,
        pitch: usize,
        cp: u32,
        x: c_int,
        y: c_int,
        fg: u32,
        bg: u32,
        maxx: c_int,
        maxy: c_int,
        bgign: bool,
    ) void;
};

// Offset-based accessors for opaque structs
const Cont = @import("shmif_offsets").Cont;
const TuiFont = offsets.TuiFont;
const AgpVstore = offsets.AgpVstore;
const StreamMeta = offsets.StreamMeta;

// Slug glyph atlas result (matches GlyphInstanceData in arcan_ttf.zig)
const GlyphInstanceLookup = extern struct {
    em_min: [2]f32,
    em_max: [2]f32,
    band_transform: [4]f32,
    glyph_data: [4]i32,
    valid: bool,
    sdf_atlas_x: u16 = 0,
    sdf_atlas_y: u16 = 0,
    sdf_atlas_w: u16 = 0,
    sdf_atlas_h: u16 = 0,
    sdf_sample_count: u16 = 0,
};

// SHMIF_RGBA / SHMIF_RGBA_DECOMP

const shmif_pixel = u32;

inline fn SHMIF_RGBA(r: u8, g_arg: u8, b: u8, a: u8) shmif_pixel {
    return (@as(u32, a) << 24) | (@as(u32, r) << 16) | (@as(u32, g_arg) << 8) | @as(u32, b);
}

inline fn SHMIF_RGBA_DECOMP(val: shmif_pixel) [4]u8 {
    return .{
        @truncate(val >> 16), // r
        @truncate(val >> 8), // g
        @truncate(val), // b
        @truncate(val >> 24), // a
    };
}

// Constants from raster.h / raster_const.h / arcan_tuisym.h

const raster_cell_sz: usize = 12;
const raster_hdr_sz: usize = 16;
const raster_line_sz: usize = 9;

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

// cursor_states (from arcan_tuisym.h)
const CURSOR_ACTIVE: u8 = 2;
const CURSOR_EXTHDRv1: u8 = 8;
const CURSOR_BLOCK: u8 = 16;
const CURSOR_BAR: u8 = 32;
const CURSOR_UNDER: u8 = 64;
const CURSOR_HOLLOW: u8 = 128;

// raster_flags
const RPACK_DFRAME: u16 = 2;

// Packed structs matching C __attribute__((packed))

const tui_raster_header = extern struct {
    data_sz: u32 align(1),
    lines: u16 align(1),
    cells: u16 align(1),
    direction: u8 align(1),
    flags: u16 align(1),
    bgc: [4]u8 align(1),
    cursor_state: u8 align(1),
};

const tui_raster_line = extern struct {
    start_line: u16 align(1),
    ncells: u16 align(1),
    offset: u16 align(1),
    content_dir: u8 align(1),
    scroll_dir: u8 align(1),
    line_state: u8 align(1),
};

comptime {
    if (@sizeOf(tui_raster_header) != raster_hdr_sz)
        @compileError("tui_raster_header size mismatch");
    if (@sizeOf(tui_raster_line) != raster_line_sz)
        @compileError("tui_raster_line size mismatch");
}

// Local types

const Cell = struct {
    fc: shmif_pixel,
    bc: shmif_pixel,
    ucs4: u32,
    attr: u8,
    attr_ext: u8,
};

const ExtCursorFn = *const fn (
    ctx: *tui_raster_context,
    x: usize,
    y: usize,
    px: usize,
    py: usize,
    cw: usize,
    pxw: usize,
    style: c_int,
    col: [*]u8,
    tag: ?*anyopaque,
) callconv(.c) void;

const tui_raster_context = extern struct {
    fonts: [4]?*anyopaque = .{ null, null, null, null },
    cursor_state: c_int = 0,
    cc: shmif_pixel = 0,
    _pad0: u32 = 0,
    ext_cursor: ?ExtCursorFn = null,
    cell_w: usize = 0,
    cell_h: usize = 0,
    min_x: usize = 0,
    min_y: usize = 0,
    max_x: usize = 0,
    max_y: usize = 0,
    // GPU glyph rendering state (Slug algorithm)
    gpu_instance_count: u32 = 0,
    gpu_instance_buf: ?[*]GpuCellInstance = null,
};

/// Instance data for GPU glyph rendering — matches slug_glyph.vert layout.
/// Each terminal cell that uses vector font gets one of these queued.
/// 96 bytes per instance: cell_pos(8) + cell_size(8) + em_min(8) + em_max(8)
///   + band_transform(16) + glyph_data(16) + fg_color(16) + bg_color(16)
const GpuCellInstance = extern struct {
    // Vertex shader instance attributes (locations 2-8)
    cell_pos: [2]f32,        // location 2: screen-space cell top-left (pixels)
    cell_size: [2]f32,       // location 3: cell width/height (pixels)
    em_min: [2]f32,          // location 4: em-space bbox min
    em_max: [2]f32,          // location 5: em-space bbox max
    band_transform: [4]f32,  // location 6: (scale.x, scale.y, offset.x, offset.y)
    glyph_data: [4]i32,      // location 7: (loc.x, loc.y, bandMaxX, bandMaxY|flags)
    fg_color: [4]f32,        // location 8: foreground RGBA normalized [0,1]
    bg_color: [4]f32,        // location 9: background RGBA normalized [0,1]
};

comptime {
    if (@sizeOf(GpuCellInstance) != 96)
        @compileError("GpuCellInstance must be 96 bytes");
}

const GPU_MAX_INSTANCES: u32 = 16384; // max cells per frame (200x57 = 11400 at 3024x1710)

/// Convert shmif_pixel (ARGB u32) to normalized [4]f32 RGBA for GPU shaders.
/// shmif_pixel layout: 0xAARRGGBB (A in bits 31-24, R 23-16, G 15-8, B 7-0)
inline fn pixelToFloat4(px: shmif_pixel) [4]f32 {
    const decomp = SHMIF_RGBA_DECOMP(px); // [r, g, b, a]
    return .{
        @as(f32, @floatFromInt(decomp[0])) / 255.0,
        @as(f32, @floatFromInt(decomp[1])) / 255.0,
        @as(f32, @floatFromInt(decomp[2])) / 255.0,
        @as(f32, @floatFromInt(decomp[3])) / 255.0,
    };
}

// Static helpers

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
) bool {
    if (x >= max_w or y >= max_h or x + w > max_w or y + h > max_h)
        return false;

    const ux = if (x + w > max_w) max_w else x + w;
    const uy = if (y + h > max_h) max_h else y + h;

    var cy = y;
    while (cy < uy) : (cy += 1) {
        var cx = x;
        while (cx < ux) : (cx += 1) {
            px[cy * pitch + cx] = col;
        }
    }
    return true;
}

fn unpack_u32(inbuf: [*]const u8) u32 {
    return @as(u32, inbuf[0]) |
        (@as(u32, inbuf[1]) << 8) |
        (@as(u32, inbuf[2]) << 16) |
        (@as(u32, inbuf[3]) << 24);
}

fn unpack_cell(unpack: [*]const u8, alpha: u8) Cell {
    return .{
        .fc = SHMIF_RGBA(unpack[0], unpack[1], unpack[2], 0xff),
        .bc = SHMIF_RGBA(unpack[3], unpack[4], unpack[5], alpha),
        .attr = unpack[6],
        .attr_ext = unpack[7],
        .ucs4 = unpack_u32(unpack + 8),
    };
}

fn drawborder_edge(
    ctx: *tui_raster_context,
    cell: *Cell,
    vidp: [*]shmif_pixel,
    pitch: usize,
    x: usize,
    y: usize,
    maxx: usize,
    maxy: usize,
    bv: u8,
) void {
    var n_row: usize = (ctx.cell_h + 15) / 16;
    var n_col: usize = (ctx.cell_w + 15) / 16;

    if (n_row > n_col)
        n_row = n_col
    else
        n_col = n_row;

    if (bv & CEATTR_BORDER_T != 0) {
        _ = draw_box_px(vidp, pitch, maxx, maxy, x, y, ctx.cell_w, n_row, cell.fc);
    }
    if (bv & CEATTR_BORDER_D != 0) {
        _ = draw_box_px(vidp, pitch, maxx, maxy, x, y + ctx.cell_h - n_row, ctx.cell_w, n_row, cell.fc);
    }
    if (bv & CEATTR_BORDER_L != 0) {
        _ = draw_box_px(vidp, pitch, maxx, maxy, x, y, n_col, ctx.cell_h, cell.fc);
    }
    if (bv & CEATTR_BORDER_R != 0) {
        _ = draw_box_px(vidp, pitch, maxx, maxy, x + ctx.cell_w - n_col, y, n_col, ctx.cell_h, cell.fc);
    }
}

fn linehint(
    ctx: *tui_raster_context,
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
        const n_lines: usize = @as(usize, @intFromFloat(@as(f64, @floatFromInt(ctx.cell_h)) * 0.05)) | 1;
        _ = draw_box_px(vidp, pitch, maxx, maxy, x, y + ctx.cell_h - n_lines, ctx.cell_w, n_lines, cell.fc);
    }
    if (strikethrough) {
        const n_lines: usize = @as(usize, @intFromFloat(@as(f64, @floatFromInt(ctx.cell_h)) * 0.05)) | 1;
        _ = draw_box_px(vidp, pitch, maxx, maxy, x, y + (ctx.cell_h >> 1) -| (n_lines >> 1), ctx.cell_w, n_lines, cell.fc);
    }
}

fn drawcursor_px(
    ctx: *tui_raster_context,
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

    if (ctx.cursor_state & CURSOR_UNDER != 0) {
        drawborder_edge(ctx, &cell, vidp, pitch, x, y, maxx, maxy, CEATTR_BORDER_D);
    } else if (ctx.cursor_state & CURSOR_HOLLOW != 0) {
        drawborder_edge(ctx, &cell, vidp, pitch, x, y, maxx, maxy, CEATTR_BORDER_D | CEATTR_BORDER_T | CEATTR_BORDER_L | CEATTR_BORDER_R);
    } else if (ctx.cursor_state & CURSOR_BAR != 0) {
        drawborder_edge(ctx, &cell, vidp, pitch, x, y, maxx, maxy, CEATTR_BORDER_L);
    }
}

fn drawglyph(
    ctx: *tui_raster_context,
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

    if (!TuiFont.isVector(font0)) {
        // Bitmap font path
        if (cell.attr & CATTR_CURSOR != 0) {
            if (ctx.cursor_state == (CURSOR_ACTIVE | CURSOR_BLOCK))
                cell.bc = ctx.cc
            else
                draw_cursor = true;
        }

        c.tui_pixelfont_draw(
            TuiFont.getBitmap(font0),
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

        if (cell.ucs4 != 0 and (cell.attr & (CATTR_STRIKETHROUGH | CATTR_UNDERLINE) != 0)) {
            linehint(ctx, cell, vidp, pitch, x, y, maxx, maxy, cell.attr & CATTR_STRIKETHROUGH != 0, cell.attr & CATTR_UNDERLINE != 0);
        }

        drawborder_edge(ctx, cell, vidp, pitch, x, y, maxx, maxy, cell.attr_ext);

        if (draw_cursor) {
            drawcursor_px(ctx, vidp, pitch, x, y, maxx, maxy, ctx.cc);
        }

        return ctx.cell_w;
    }

    // Vector font path — full GPU rendering (bg + text + decorations)
    var bc = cell.bc;
    if (cell.attr & CATTR_CURSOR != 0) {
        if (ctx.cursor_state == (CURSOR_ACTIVE | CURSOR_BLOCK))
            bc = ctx.cc
        else
            draw_cursor = true;
    }

    // Queue GPU instance for EVERY cell — shader handles bg, text, and decorations
    if (ctx.gpu_instance_buf) |buf| {
        if (ctx.gpu_instance_count < GPU_MAX_INSTANCES) {
            const fg_rgba = pixelToFloat4(if (draw_cursor) ctx.cc else cell.fc);
            var bg_rgba = pixelToFloat4(bc);
            // Force opaque background — GPU draws directly to vstore, no alpha compositing
            bg_rgba[3] = 1.0;

            // Build decoration flags (packed into glyph_data[3] bits 9-15)
            var deco_flags: i32 = 0;
            if (cell.attr & CATTR_UNDERLINE != 0) deco_flags |= 0x200;
            if (cell.attr & CATTR_STRIKETHROUGH != 0) deco_flags |= 0x400;
            if (cell.attr_ext & CEATTR_BORDER_T != 0) deco_flags |= 0x800;
            if (cell.attr_ext & CEATTR_BORDER_D != 0) deco_flags |= 0x1000;
            if (cell.attr_ext & CEATTR_BORDER_L != 0) deco_flags |= 0x2000;
            if (cell.attr_ext & CEATTR_BORDER_R != 0) deco_flags |= 0x4000;
            if (draw_cursor) deco_flags |= 0x8000;

            if (cell.ucs4 != 0) {
                // Glyph cell — look up Slug curves
                var glyph_lookup = GlyphInstanceLookup{
                    .em_min = .{ 0.0, 0.0 },
                    .em_max = .{ 1.0, 1.0 },
                    .band_transform = .{ 1.0, 1.0, 0.0, 0.0 },
                    .glyph_data = .{ 0, 0, 0, 0 },
                    .valid = false,
                };
                const tt_font = TuiFont.getTruetype(font0);
                c.slug_cache_font_ptr(tt_font);
                c.slug_atlas_lookup(tt_font, cell.ucs4, &glyph_lookup);

                var gd = glyph_lookup.glyph_data;
                // Preserve band_max_y (bits 0-7) AND rect-path flag (bit 8);
                // deco_flags occupy bits 9+ and never collide.
                gd[3] = (gd[3] & 0x1FF) | deco_flags;
                buf[ctx.gpu_instance_count] = .{
                    .cell_pos = .{ @floatFromInt(x), @floatFromInt(y) },
                    .cell_size = .{ @floatFromInt(ctx.cell_w), @floatFromInt(ctx.cell_h) },
                    .em_min = glyph_lookup.em_min,
                    .em_max = glyph_lookup.em_max,
                    .band_transform = glyph_lookup.band_transform,
                    .glyph_data = gd,
                    .fg_color = fg_rgba,
                    .bg_color = bg_rgba,
                };
            } else {
                // Empty cell — shader fills bg_color (glyph_data.xyz=0)
                buf[ctx.gpu_instance_count] = .{
                    .cell_pos = .{ @floatFromInt(x), @floatFromInt(y) },
                    .cell_size = .{ @floatFromInt(ctx.cell_w), @floatFromInt(ctx.cell_h) },
                    .em_min = .{ 0.0, 0.0 },
                    .em_max = .{ 1.0, 1.0 },
                    .band_transform = .{ 1.0, 1.0, 0.0, 0.0 },
                    .glyph_data = .{ 0, 0, 0, deco_flags },
                    .fg_color = fg_rgba,
                    .bg_color = bg_rgba,
                };
            }
            ctx.gpu_instance_count += 1;
        }
    }

    return ctx.cell_w;
}

fn raster_tobuf(
    ctx: *tui_raster_context,
    vidp: [*]shmif_pixel,
    pitch: usize,
    max_w: usize,
    max_h: usize,
    x1: *u16,
    y1: *u16,
    x2: *u16,
    y2: *u16,
    buf_arg: [*]u8,
    buf_sz_arg: usize,
) c_int {
    if (buf_sz_arg == 0 or buf_sz_arg < @sizeOf(tui_raster_header))
        return -1;

    var buf = buf_arg;
    var buf_sz = buf_sz_arg;
    var update = false;

    // Read header
    var hdr: tui_raster_header = undefined;
    @memcpy(std.mem.asBytes(&hdr), buf[0..@sizeOf(tui_raster_header)]);
    const extcursor = (hdr.cursor_state & CURSOR_EXTHDRv1) != 0;

    // Verify size
    const hdr_ver_sz: usize = @as(usize, hdr.lines) * raster_line_sz +
        @as(usize, hdr.cells) * raster_cell_sz + raster_hdr_sz +
        @as(usize, if (extcursor) @as(usize, 3) else 0);

    if (hdr.data_sz > buf_sz or hdr.data_sz != hdr_ver_sz)
        return -1;

    buf_sz -= @sizeOf(tui_raster_header);
    buf += @sizeOf(tui_raster_header);

    if (extcursor) {
        tui_raster_cursor_color(ctx, buf);
        buf_sz -= 3;
        buf += 3;
    }

    const bgc = SHMIF_RGBA(hdr.bgc[0], hdr.bgc[1], hdr.bgc[2], hdr.bgc[3]);

    if (hdr.flags & RPACK_DFRAME != 0) {
        update = true;
        y1.* = @intCast(max_h);
        y2.* = 0;
        x1.* = @intCast(max_w);
        x2.* = 0;

        if (hdr.lines == 0)
            return -1;
    } else {
        x1.* = 0;
        y1.* = 0;
        x2.* = @intCast(max_w);
        y2.* = @intCast(max_h);

        const pad_w = max_w % ctx.cell_w;
        const pad_h = max_h % ctx.cell_h;

        if (pad_w != 0) {
            const start = max_w - pad_w;
            _ = draw_box_px(vidp, pitch, max_w, max_h, start, 0, pad_w, max_h, bgc);
        }
        if (pad_h != 0) {
            const start = max_h - pad_h;
            _ = draw_box_px(vidp, pitch, max_w, max_h, 0, start, max_w, pad_h, bgc);
        }
    }

    ctx.cursor_state = @as(c_int, hdr.cursor_state) & ~@as(c_int, CURSOR_EXTHDRv1);

    var cur_y: isize = -1;
    var last_line: usize = 0;
    var draw_y: usize = 0;

    for (0..hdr.lines) |_| {
        if (buf_sz == 0) break;
        if (buf_sz < @sizeOf(tui_raster_line))
            return -1;

        // Read line metadata
        var line: tui_raster_line = undefined;
        @memcpy(std.mem.asBytes(&line), buf[0..@sizeOf(tui_raster_line)]);
        buf += @sizeOf(tui_raster_line);
        buf_sz -= @sizeOf(tui_raster_line);

        if (line.start_line > last_line)
            last_line = line.start_line;

        if (update and cur_y == -1) {
            y1.* = @intCast(@as(usize, line.start_line) * ctx.cell_h);
        }

        if (cur_y != @as(isize, @intCast(line.start_line))) {
            cur_y = @intCast(line.start_line);
        }
        draw_y = @as(usize, @intCast(cur_y)) * ctx.cell_h;

        if (draw_y < y1.*) {
            y1.* = @intCast(draw_y);
        }

        var draw_x: usize = @as(usize, line.offset) * ctx.cell_w;
        var cell_i: usize = line.offset;

        if (draw_x < x1.*) {
            x1.* = @intCast(draw_x);
        }

        var ncells_left = line.ncells;
        while (ncells_left > 0 and buf_sz >= raster_cell_sz) {
            ncells_left -= 1;

            var cell = unpack_cell(buf, hdr.bgc[3]);
            buf += raster_cell_sz;
            buf_sz -= raster_cell_sz;

            // External cursor handling
            if ((cell.attr & CATTR_CURSOR != 0) and ctx.ext_cursor != null) {
                var rgba = SHMIF_RGBA_DECOMP(ctx.cc);
                ctx.ext_cursor.?(
                    ctx,
                    cell_i,
                    @intCast(@as(usize, @intCast(cur_y))),
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

            if (cell.attr & CATTR_SKIP != 0) {
                draw_x += ctx.cell_w;
                cell_i += 1;
                continue;
            }

            if (draw_x + ctx.cell_w <= max_w and draw_y + ctx.cell_h <= max_h) {
                draw_x += drawglyph(ctx, &cell, vidp, pitch, draw_x, draw_y, max_w, max_h);
            } else {
                cell_i += 1;
                continue;
            }

            const next_x: u16 = @intCast(draw_x + ctx.cell_w);
            if (x2.* < next_x and next_x <= @as(u16, @intCast(max_w))) {
                x2.* = next_x;
            }

            cell_i += 1;
        }

        cur_y += 1;
    }

    // BUG-12: (last_line+1)*cell_h can exceed u16 with HiDPI cell_h≈48 and
    // last_line >= 1365, or if a malformed client payload reports a bogus
    // start_line. Clamp against max_h (same bound we already use for y1).
    const y2_raw: usize = (last_line + 1) * ctx.cell_h;
    y2.* = @intCast(@min(y2_raw, max_h));
    return 1;
}

// tui_raster_renderagp (previously in arcan_raster_helpers.c)

export fn tui_raster_renderagp(
    ctx: ?*tui_raster_context,
    dst: ?*anyopaque,
    buf: [*]u8,
    buf_sz: usize,
    out: *anyopaque,
) c_int {
    const ctx_p = ctx orelse return -1;
    const dst_p = dst orelse return -1;
    if (buf_sz < @sizeOf(tui_raster_header))
        return -1;

    const raw = AgpVstore.getVinfTextRaw(dst_p);
    const w = AgpVstore.getW(dst_p);
    const h = AgpVstore.getH(dst_p);
    // First delta frame on an uninitialized buffer (BZERO'd, all pixels == 0):
    // fill with TPACK background color so non-dirty areas aren't black.
    // Any real rendered pixel has alpha=0xFF, so raw[0]==0 means uninitialized.
    const pixels: [*]shmif_pixel = @ptrCast(@alignCast(raw));
    var force_full: bool = false;
    if (pixels[0] == 0 and buf_sz >= @sizeOf(tui_raster_header)) {
        var hdr_peek: tui_raster_header = undefined;
        @memcpy(std.mem.asBytes(&hdr_peek), buf[0..@sizeOf(tui_raster_header)]);
        if (hdr_peek.flags & RPACK_DFRAME != 0) {
            const bgc = SHMIF_RGBA(hdr_peek.bgc[0], hdr_peek.bgc[1], hdr_peek.bgc[2], hdr_peek.bgc[3]);
            const npixels = @as(usize, w) * @as(usize, h);
            for (0..npixels) |i| {
                pixels[i] = bgc;
            }
            force_full = true;
        }
    }

    var x1: u16 = undefined;
    var y1: u16 = undefined;
    var x2: u16 = undefined;
    var y2: u16 = undefined;

    if (raster_tobuf(ctx_p, raw, w, w, h, &x1, &y1, &x2, &y2, buf, buf_sz) == -1) {
        StreamMeta.zero(out);
        return -1;
    }

    // If GPU path was active, the instance buffer now contains cells to render.
    // The Vulkan compositor will pick these up via tui_raster_gpu_flush() after
    // uploading the CPU-rasterized background to the GPU texture.
    // (The actual GPU draw is issued by the AGP layer, not here.)

    StreamMeta.setBuf(out, @ptrCast(raw));
    if (force_full) {
        StreamMeta.setDirty(out, false);
    } else {
        StreamMeta.setDirty(out, true);
        StreamMeta.setX1(out, x1);
        StreamMeta.setY1(out, y1);
        StreamMeta.setW(out, @as(u32, x2) -| @as(u32, x1));
        StreamMeta.setH(out, @as(u32, y2) -| @as(u32, y1));
    }
    return 0;
}

// Exported public API

export fn tui_raster_setup(cell_w: usize, cell_h: usize) ?*tui_raster_context {
    const mem = c.malloc(@sizeOf(tui_raster_context)) orelse return null;
    const res: *tui_raster_context = @ptrCast(@alignCast(mem));
    res.* = .{
        .cell_w = cell_w,
        .cell_h = cell_h,
        .cc = SHMIF_RGBA(0x00, 0xaa, 0x00, 0xff),
    };

    // GPU-only glyph rendering (Slug algorithm) — always on
    tui_raster_gpu_enable(res, true);

    return res;
}

export fn tui_raster_setfont(ctx: *tui_raster_context, src: [*]?*anyopaque, n_fonts: usize) void {
    // bug 0115: the atlas is GLOBAL across all raster contexts. Calling
    // slug_atlas_invalidate() wipes glyphs every other terminal had cached.
    // The previous condition fired on null -> font (initial setup of any
    // new raster context), so opening a second terminal blew away the
    // first terminal's atlas every time. Live arcan PID 267830 caught at
    // atlas_curve_offset=0, atlas_dirty=1 — exactly the post-wipe state.
    //
    // Only invalidate when a slot that *was* holding a font is being
    // replaced or cleared. The initial null -> font_ptr transition for a
    // fresh context contributes nothing to invalidate (those glyphs
    // weren't in the atlas anyway), and the same-font no-op case stays
    // a no-op.
    var removed = false;
    for (0..4) |i| {
        const new_font = if (i < n_fonts) src[i] else null;
        if (ctx.fonts[i] != null and ctx.fonts[i] != new_font) removed = true;
        ctx.fonts[i] = new_font;
    }
    if (removed) c.slug_atlas_invalidate();
}

export fn tui_raster_get_cell_size(ctx: *tui_raster_context, w: *usize, h: *usize) void {
    w.* = ctx.cell_w;
    h.* = ctx.cell_h;
}

export fn tui_raster_cell_size(ctx: *tui_raster_context, w: usize, h: usize) void {
    ctx.cell_w = w;
    ctx.cell_h = h;
}

export fn tui_raster_cursor_color(ctx: *tui_raster_context, col: [*]const u8) void {
    ctx.cc = SHMIF_RGBA(col[0], col[1], col[2], 0xff);
}

export fn tui_raster_cursor_control(
    ctx: *tui_raster_context,
    ext_cursor: ?ExtCursorFn,
    tag: ?*anyopaque,
) void {
    _ = tag;
    ctx.ext_cursor = ext_cursor;
}

export fn tui_raster_render(
    ctx: ?*tui_raster_context,
    dst: ?*anyopaque,
    buf: [*]u8,
    buf_sz: usize,
) c_int {
    const ctx_p = ctx orelse return -1;
    const dst_p = dst orelse return -1;
    if (ctx_p.fonts[0] == null or buf_sz < @sizeOf(tui_raster_header))
        return -1;

    const vidp = Cont.getVidp(dst_p);
    const pitch = Cont.getPitch(dst_p);
    const w = Cont.getW(dst_p);
    const h = Cont.getH(dst_p);

    var x1: u16 = undefined;
    var y1: u16 = undefined;
    var x2: u16 = undefined;
    var y2: u16 = undefined;
    if (raster_tobuf(ctx_p, vidp, pitch, w, h, &x1, &y1, &x2, &y2, buf, buf_sz) == -1)
        return -1;

    if (x2 > @as(u16, @intCast(w)))
        x2 = @intCast(w);

    _ = c.arcan_shmif_dirty(dst_p, x1, y1, x2, y2, 0);
    return 1;
}

export fn tui_raster_offset(
    ctx: *tui_raster_context,
    px_x: usize,
    row: usize,
    offset: *usize,
) void {
    _ = ctx;
    _ = row;
    offset.* = px_x;
}

export fn tui_raster_free(ctx: ?*tui_raster_context) void {
    const p = ctx orelse return;
    if (p.gpu_instance_buf) |buf| {
        c.free(@ptrCast(buf));
        p.gpu_instance_buf = null;
    }
    c.free(p);
}

// GPU glyph rendering API

/// Allocate the GPU glyph instance buffer (Slug algorithm).
/// Called once at init. GPU rendering is the only path — no CPU fallback.
export fn tui_raster_gpu_enable(ctx: ?*tui_raster_context, _: bool) void {
    const p = ctx orelse return;
    if (p.gpu_instance_buf == null) {
        const mem = c.malloc(@sizeOf(GpuCellInstance) * GPU_MAX_INSTANCES);
        p.gpu_instance_buf = if (mem) |m| @ptrCast(@alignCast(m)) else null;
        if (p.gpu_instance_buf == null) {
        }
    }
}

/// Get the queued GPU glyph instances from the last raster_tobuf call.
/// Returns the instance buffer pointer and count. Resets the count to 0.
/// Caller must issue the GPU draw call before the next raster_tobuf.
export fn tui_raster_gpu_flush(
    ctx: ?*tui_raster_context,
    out_count: *u32,
) ?*const anyopaque {
    const p = ctx orelse {
        out_count.* = 0;
        return null;
    };
    // Debug instance data dump removed — was only needed during development.
    out_count.* = p.gpu_instance_count;
    p.gpu_instance_count = 0;
    if (p.gpu_instance_buf) |buf| return @ptrCast(buf);
    return null;
}

/// Check if GPU glyph rendering is enabled.
export fn tui_raster_gpu_is_enabled(ctx: ?*tui_raster_context) bool {
    const p = ctx orelse return false;
    return p.gpu_instance_buf != null;
}
