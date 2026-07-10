// Pure Zig port of pixelfont.c — PSF2 bitmap font rasterization.
// Replaces uthash with std.AutoHashMap.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

const shmif_pixel = u32;
const Allocator = if (is_freestanding) void else std.heap.c_allocator;

// Font data from shmif_types (extern symbols linked from C object files)
const c = @import("shmif_types");

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

// UTF-8 decoder
const UTF8_ACCEPT: u32 = 0;
const UTF8_REJECT: u32 = 1;

const utf8d = [_]u8{
    // 00..1f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 20..3f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 40..5f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 60..7f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 80..9f
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
    // a0..bf
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    // c0..df
    8, 8, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    // e0..ef
    0xa, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x4, 0x3, 0x3,
    // f0..ff
    0xb, 0x6, 0x6, 0x6, 0x5, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8,
    // s0..s0
    0x0, 0x1, 0x2, 0x3, 0x5, 0x8, 0x7, 0x1, 0x1, 0x1, 0x4, 0x6, 0x1, 0x1, 0x1, 0x1,
    // s1..s2
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1,
    // s3..s4
    1, 2, 1, 1, 1, 1, 1, 2, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1,
    // s5..s6
    1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 1, 3, 1, 1, 1, 1, 1, 1,
    // s7..s8
    1, 3, 1, 1, 1, 1, 1, 3, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
};

fn utf8_decode(state: *u32, codep: *u32, byte: u32) u32 {
    const utype = utf8d[@intCast(byte)];
    codep.* = if (state.* != UTF8_ACCEPT)
        (byte & 0x3f) | (codep.* << 6)
    else
        (@as(u32, 0xff) >> @intCast(utype)) & byte;
    state.* = utf8d[256 + state.* * 16 + utype];
    return state.*;
}

// Internal types

const GlyphMap = std.AutoHashMap(u32, [*]const u8);

const BitmapFont = struct {
    fontdata: []u8,
    chsz: usize,
    w: usize,
    h: usize,
};

const FontEntry = struct {
    sz: usize = 0,
    font: ?*BitmapFont = null,
    shared_ht: bool = false,
    ht: ?*GlyphMap = null,
};

const TuiPixelfont = struct {
    n_fonts: usize,
    active_font: ?*FontEntry = null,
    active_font_px: usize = 0,
    fonts: []FontEntry,
};

// PSF2 header decode

const Psf2Header = struct {
    glyph_count: usize,
    glyph_bytes: usize,
    w: usize,
    h: usize,
    ofs: usize,
};

fn psf2_decode_header(buf: []const u8) ?Psf2Header {
    if (buf.len < 32) return null;

    // Check magic: 0x72 0xb5 0x4a 0x86
    if (buf[0] != 0x72 or buf[1] != 0xb5 or buf[2] != 0x4a or buf[3] != 0x86)
        return null;

    var u32s: [8]u32 = undefined;
    const bytes: *const [32]u8 = buf[0..32];
    inline for (0..8) |i| {
        u32s[i] = std.mem.readInt(u32, bytes[i * 4 ..][0..4], .little);
    }

    return .{
        .glyph_count = u32s[4],
        .glyph_bytes = u32s[5],
        .w = u32s[7],
        .h = u32s[6],
        .ofs = u32s[2],
    };
}

// PSF2 font loader

fn open_psf2(buf: []const u8, ht: *GlyphMap) ?*BitmapFont {
    const hdr = psf2_decode_header(buf) orelse return null;

    const pos_start = hdr.ofs;
    const glyphbuf_sz = hdr.glyph_count * hdr.glyph_bytes;

    // Allocate font + glyph data in one block
    const font = Allocator.create(BitmapFont) catch return null;
    const fontdata = Allocator.alloc(u8, glyphbuf_sz) catch {
        Allocator.destroy(font);
        return null;
    };

    font.* = .{
        .fontdata = fontdata,
        .chsz = hdr.glyph_bytes,
        .w = hdr.w,
        .h = hdr.h,
    };

    @memcpy(fontdata, buf[pos_start..][0..glyphbuf_sz]);

    // Parse unicode table after glyph data
    var pos = hdr.ofs + glyphbuf_sz;
    var state: u32 = 0;
    var codepoint: u32 = 0;
    var ind: usize = 0;

    while (pos < buf.len and ind < hdr.glyph_count) {
        if (buf[pos] == 0xff) {
            ind += 1;
        } else if (buf[pos] == 0xfe) {
            // Unicode ranges not supported
        } else if (utf8_decode(&state, &codepoint, buf[pos]) == UTF8_REJECT) {
            // Invalid UTF-8 sequence
            return font;
        } else if (state == UTF8_ACCEPT) {
            const data_ptr: [*]const u8 = fontdata.ptr + hdr.glyph_bytes * ind;
            ht.put(codepoint, data_ptr) catch {};
            state = 0;
            codepoint = 0;
        }
        pos += 1;
    }

    return font;
}

// Public API (exported with C ABI)

export fn tui_pixelfont_valid(buf: [*]const u8, buf_sz: usize) bool {
    if (buf_sz < 32) return false;
    return psf2_decode_header(buf[0..buf_sz]) != null;
}

export fn tui_pixelfont_open(lim: usize) ?*TuiPixelfont {
    if (is_freestanding) return null;
    if (lim < 3) return null;

    const fonts = Allocator.alloc(FontEntry, lim) catch return null;
    @memset(fonts, FontEntry{});

    const ctx = Allocator.create(TuiPixelfont) catch {
        Allocator.free(fonts);
        return null;
    };
    ctx.* = .{
        .n_fonts = lim,
        .fonts = fonts,
    };

    var fontstatus = false;
    fontstatus = tui_pixelfont_load_inner(ctx, c.Lat15_Terminus32x16_psf, c.Lat15_Terminus32x16_psf_len, 32, false) or fontstatus;
    fontstatus = tui_pixelfont_load_inner(ctx, c.Lat15_Terminus22x11_psf, c.Lat15_Terminus22x11_psf_len, 22, false) or fontstatus;
    fontstatus = tui_pixelfont_load_inner(ctx, c.Lat15_Terminus12x6_psf, c.Lat15_Terminus12x6_psf_len, 12, false) or fontstatus;

    if (!fontstatus) {
        Allocator.free(fonts);
        Allocator.destroy(ctx);
        return null;
    }

    ctx.active_font = &ctx.fonts[0];
    if (ctx.fonts[0].font) |f| {
        ctx.fonts[0].sz = f.h;
    }

    return ctx;
}

export fn tui_pixelfont_close(ctx: ?*TuiPixelfont) void {
    if (is_freestanding) return;
    const p = ctx orelse return;
    for (p.fonts) |*fe| {
        if (fe.font) |f| {
            if (!fe.shared_ht) {
                if (fe.ht) |ht| {
                    ht.deinit();
                    Allocator.destroy(ht);
                }
            }
            Allocator.free(f.fontdata);
            Allocator.destroy(f);
            fe.font = null;
            fe.sz = 0;
            fe.shared_ht = false;
            fe.ht = null;
        }
    }
    Allocator.free(p.fonts);
    Allocator.destroy(p);
}

fn tui_pixelfont_load_inner(
    ctx: *TuiPixelfont,
    buf: [*]const u8,
    buf_sz: usize,
    px_sz: usize,
    merge: bool,
) bool {
    if (buf_sz < 32) return false;
    if (psf2_decode_header(buf[0..buf_sz]) == null) return false;

    // If not merge, clear existing fonts for this size slot
    if (!merge) {
        for (ctx.fonts) |*fe| {
            if (fe.font != null and fe.sz == px_sz) {
                if (!fe.shared_ht) {
                    if (fe.ht) |ht| {
                        ht.deinit();
                        Allocator.destroy(ht);
                    }
                }
                if (fe.font) |f| {
                    Allocator.free(f.fontdata);
                    Allocator.destroy(f);
                }
                fe.font = null;
                fe.sz = 0;
                fe.shared_ht = false;
                fe.ht = null;
            }
        }
    }

    // Find empty slot
    var dst: ?*FontEntry = null;
    for (ctx.fonts) |*fe| {
        if (fe.font == null) {
            dst = fe;
            break;
        }
    }
    const slot = dst orelse return false;

    // Share hash table if merging
    if (merge) {
        for (ctx.fonts) |*fe| {
            if (fe.font != null and fe.sz == px_sz) {
                slot.shared_ht = true;
                slot.ht = fe.ht;
                break;
            }
        }
    }

    // Create hash map if needed
    if (slot.ht == null) {
        slot.ht = Allocator.create(GlyphMap) catch return false;
        slot.ht.?.* = GlyphMap.init(Allocator);
    }

    slot.font = open_psf2(buf[0..buf_sz], slot.ht.?) orelse {
        if (!slot.shared_ht) {
            if (slot.ht) |ht| {
                ht.deinit();
                Allocator.destroy(ht);
            }
        }
        slot.shared_ht = false;
        slot.ht = null;
        return false;
    };
    slot.sz = px_sz;

    return true;
}

export fn tui_pixelfont_load(
    ctx: ?*TuiPixelfont,
    buf: [*]const u8,
    buf_sz: usize,
    px_sz: usize,
    merge: bool,
) bool {
    if (is_freestanding) return false;
    return tui_pixelfont_load_inner(ctx orelse return false, buf, buf_sz, px_sz, merge);
}

export fn tui_pixelfont_setsz(ctx: ?*TuiPixelfont, px: usize, w: *usize, h: *usize) void {
    const p = ctx orelse return;
    const af = p.active_font orelse return;

    var best_dist: usize = if (af.sz > px) af.sz - px else px - af.sz;

    if (p.active_font_px != px) {
        for (p.fonts) |*fe| {
            if (fe.font != null) {
                const nd: usize = if (fe.sz > px) fe.sz - px else px - fe.sz;
                if (nd < best_dist) {
                    best_dist = nd;
                    p.active_font = fe;
                }
            }
        }
    }

    if (p.active_font) |active| {
        if (active.font) |f| {
            w.* = f.w;
            h.* = f.h;
        }
    }
    p.active_font_px = px;
}

export fn tui_pixelfont_hascp(ctx: ?*TuiPixelfont, cp: u32) bool {
    const p = ctx orelse return false;
    const af = p.active_font orelse return false;
    const ht = af.ht orelse return false;
    return ht.get(cp) != null;
}

export fn tui_pixelfont_draw(
    ctx: ?*TuiPixelfont,
    vidp: [*]shmif_pixel,
    pitch: usize,
    cp: u32,
    x_arg: c_int,
    y_arg: c_int,
    fg: shmif_pixel,
    bg: shmif_pixel,
    maxx: c_int,
    maxy: c_int,
    bgign: bool,
) void {
    const p = ctx orelse return;
    const font = p.active_font orelse return;
    const bf = font.font orelse return;
    const ht = font.ht orelse return;

    if (x_arg >= maxx or y_arg >= maxy) return;

    const glyph_data: ?[*]const u8 = ht.get(cp);

    const font_w: c_int = @intCast(bf.w);
    const font_h: c_int = @intCast(bf.h);

    if (glyph_data == null) {
        // No glyph found — fill with background
        var w: usize = bf.w;
        var h: usize = bf.h;
        if (x_arg < 0 or y_arg < 0) return;
        const x: usize = @intCast(x_arg);
        const y: usize = @intCast(y_arg);
        const mx: usize = @intCast(maxx);
        const my: usize = @intCast(maxy);
        if (w + x >= mx) w = mx - x;
        if (h + y >= my) h = my - y;
        if (!bgign) draw_box_px(vidp, pitch, mx, my, x, y, w, h, bg);
        return;
    }

    const data = glyph_data.?;

    // Handle partial clipping against screen regions
    var bind: usize = 0;
    var row: c_int = 0;
    var x = x_arg;
    var y = y_arg;

    if (y < 0) {
        row = -y;
        var bpr: usize = bf.w / 8;
        if (bf.w % 8 != 0 or bpr == 0) bpr += 1;
        bind = @intCast(@as(c_int, @intCast(bpr)) * (-y));
        y = 0;
    }

    var colst: c_int = 0;
    if (x < 0) {
        colst = -x;
        x = 0;
    }

    if (font_w + x > maxx or font_h + y > maxy) return;

    while (row < font_h and y < maxy) : ({
        row += 1;
        y += 1;
    }) {
        const y_u: usize = @intCast(y);
        const x_u: usize = @intCast(x);
        const pos = vidp + y_u * pitch + x_u;
        var col = colst;
        while (col < font_w) : (bind += 1) {
            var lx = x;
            var bit: i4 = 7;
            while (bit >= 0 and col < font_w and lx < maxx) : ({
                bit -= 1;
                col += 1;
                lx += 1;
            }) {
                const col_u: usize = @intCast(col);
                if ((@as(u8, 1) << @intCast(bit)) & data[bind] != 0) {
                    pos[col_u] = fg;
                } else if (!bgign) {
                    pos[col_u] = bg;
                }
            }
        }
    }
}
