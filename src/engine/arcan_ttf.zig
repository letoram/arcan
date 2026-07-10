// Pure Zig TrueType font rendering — replaces FreeType dependency.
// Uses andrewrk/TrueType (pure Zig TTF/OTF parser + rasterizer).
//
// Same exported C ABI as the previous FreeType-based version so that
// arcan_renderfun.zig, raster.zig, and fontmgmt.zig work unchanged.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

const TrueType = @import("TrueType");

extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;

// C imports (non-FreeType)
const c = if (is_freestanding) struct {
    pub const struct_stat = extern struct { st_dev: u64 = 0, st_ino: u64 = 0 };
    pub inline fn fileno(_: ?*anyopaque) c_int {
        return -1;
    }
    pub inline fn strlen(s: [*c]const u8) usize {
        var i: usize = 0;
        while (s[i] != 0) : (i += 1) {}
        return i;
    }
    pub inline fn stat(_: [*c]const u8, _: *struct_stat) c_int {
        return -1;
    }
    pub inline fn fstat(_: c_int, _: *struct_stat) c_int {
        return -1;
    }
    pub inline fn close(_: c_int) c_int {
        return 0;
    }
    pub const arcan_vobj_id = i64;
} else @import("posix");

// Constants
const FONT_CACHE_SIZE: usize = 128;

const CACHED_METRICS: c_int = 0x10;
const CACHED_PIXMAP: c_int = 0x02;

const TTF_STYLE_NORMAL: c_int = 0x00;
const TTF_STYLE_BOLD: c_int = 0x01;
const TTF_STYLE_ITALIC: c_int = 0x02;
const TTF_STYLE_UNDERLINE: c_int = 0x04;
const TTF_STYLE_STRIKETHROUGH: c_int = 0x08;

const TTF_STYLE_NO_GLYPH_CHANGE: c_int = TTF_STYLE_UNDERLINE | TTF_STYLE_STRIKETHROUGH;

const TTF_HINTING_NORMAL: c_int = 3;
const TTF_HINTING_LIGHT: c_int = 2;
const TTF_HINTING_MONO: c_int = 1;
const TTF_HINTING_NONE: c_int = 0;
const TTF_HINTING_RGB: c_int = 4;
const TTF_HINTING_VRGB: c_int = 5;

// av_pixel / PIXEL / PACK
const av_pixel = u32;
const PIXEL = av_pixel;

inline fn PACK(r_arg: u32, g_arg: u32, b_arg: u32, a_arg: u32) PIXEL {
    return (a_arg << 24) | (r_arg << 16) | (g_arg << 8) | b_arg;
}

// Allocator
//
// Hosted builds: use std.heap.DebugAllocator while we're hunting bug 0031
// (TrueType.codepointGlyphIndex SIGSEGV via use-after-free of font_bytes
// or TTF_Font_Internal).  `.retain_metadata = true` + `.never_unmap = true`
// keep freed regions mapped-but-poisoned and preserve allocation/free
// stack traces.  Reads after a free then produce a logged error with
// BOTH stacks (alloc-site and free-site) instead of a silent segfault,
// so we can pin the actual culprit instead of guessing at lifecycle.
//
// Trade-off: every allocation effectively leaks until process exit
// (the metadata + page is never returned to the OS).  Acceptable for
// a debug session; revert to c_allocator once bug 0031 is fixed.
//
// Freestanding builds keep page_allocator (no libc, no debug machinery).
var ttf_debug_allocator: std.heap.DebugAllocator(.{
    .retain_metadata = true,
    .never_unmap = true,
}) = .init;
const gpa = if (is_freestanding) std.heap.page_allocator else ttf_debug_allocator.allocator();

// Cached glyph information
const c_glyph = struct {
    stored: c_int = 0,
    index: TrueType.GlyphIndex = .notdef,
    // Rasterized alpha bitmap (owned, allocated via gpa)
    alpha_buf: ?[]u8 = null,
    alpha_width: u16 = 0,
    alpha_height: u16 = 0,
    alpha_off_x: i16 = 0,
    alpha_off_y: i16 = 0,
    // Metrics
    minx: c_int = 0,
    maxx: c_int = 0,
    miny: c_int = 0,
    maxy: c_int = 0,
    yoffset: c_int = 0,
    advance: c_int = 0,
    cached: u32 = 0,
};

// Internal font structure
const TTF_Font_Internal = struct {
    tt: ?TrueType = null,
    font_bytes: ?[]const u8 = null, // owned, allocated via gpa (or mmap'd)
    font_bytes_owned: bool = false,
    scale: f32 = 0.0,

    height: c_int = 0,
    ascent: c_int = 0,
    descent: c_int = 0,
    lineskip: c_int = 0,
    face_style: c_int = 0,
    style: c_int = 0,
    outline: c_int = 0,
    kerning: c_int = 1,
    glyph_overhang: c_int = 0,
    glyph_italics: f32 = 0.0,
    underline_offset: c_int = 0,
    underline_height: c_int = 0,
    current: ?*c_glyph = null,
    cache: [257]c_glyph = [_]c_glyph{.{}} ** 257,
    ptsize: c_int = 0,
    hinting: c_int = TTF_HINTING_NORMAL,
    cached_height: c_int = 0,
    cached_width: c_int = 0,
    // For cache key (dev/ino from the fd used to open)
    src_fd: c_int = -1,
};

const dev_t = u64;
const ino_t = u64;

// Font cache entry
const c_font = struct {
    font: ?*TTF_Font_Internal = null,
    original: ?*c_font = null,
    dev: dev_t = 0,
    ino: ino_t = 0,
    ptsize: c_int = 0,
    hdpi: u16 = 0,
    vdpi: u16 = 0,
    ref_count: c_uint = 0,
};

// Font cache reference (the public TTF_Font type)
const c_font_ref = struct {
    font: ?*TTF_Font_Internal = null,
    cache_entry: ?*c_font = null,
};

const TTF_Font = c_font_ref;

// Thread-local state
threadlocal var TTF_initialized: c_int = 0;

// Font cache
var font_cache: [FONT_CACHE_SIZE]c_font = [_]c_font{.{}} ** FONT_CACHE_SIZE;
var font_cache_usage: c_int = 0;

// Thread-local unicode buffer
threadlocal var pool_cnt: usize = 0;
threadlocal var unicode_buf: ?[*]u32 = null;

// External C functions
extern fn arcan_shmif_dupfd(fd: c_int, dstnum: c_int, nonblocking: bool) callconv(.c) c_int;
extern fn arcan_trace_mark(
    [*c]const u8,
    [*c]const u8,
    u8,
    u8,
    u32,
    usize,
    [*c]const u8,
    [*c]const u8,
    [*c]const u8,
    c_int,
) callconv(.c) void;
extern var arcan_trace_enabled: bool;

inline fn trace_mark_oneshot(
    cat: [*c]const u8,
    name: [*c]const u8,
    sys: u8,
    msg: [*c]const u8,
) void {
    if (arcan_trace_enabled) {
        arcan_trace_mark(cat, name, 0, sys, 0, 0, msg, @as([*c]const u8, @ptrCast("arcan_ttf.zig")), @as([*c]const u8, @ptrCast("")), 0);
    }
}

const TRACE_SYS_DEFAULT: u8 = 0;
const TRACE_SYS_WARN: u8 = 3;
const TRACE_SYS_ERROR: u8 = 4;

// C library / POSIX functions
const FILE = if (is_freestanding) anyopaque else c.FILE;

extern fn fopen([*c]const u8, [*c]const u8) callconv(.c) ?*FILE;
extern fn fclose(?*FILE) callconv(.c) c_int;
extern fn fseek(?*FILE, c_long, c_int) callconv(.c) c_int;
extern fn ftell(?*FILE) callconv(.c) c_long;
extern fn fread(?*anyopaque, usize, usize, ?*FILE) callconv(.c) usize;
extern fn fdopen(c_int, [*c]const u8) callconv(.c) ?*FILE;

extern fn malloc(usize) callconv(.c) ?*anyopaque;
extern fn free(?*anyopaque) callconv(.c) void;

const SEEK_SET: c_int = 0;
const SEEK_END: c_int = 2;

const StatResult = struct { dev: dev_t, ino: ino_t };

// Bug 0125 — DO NOT SOFTEN.
// std.posix.fstat / std.posix.fstatat hit `unreachable` on EBADF and EINVAL.
// That panic is load-bearing: a bad fd reaching here is an upstream contract
// violation (set_font_slot / setfont / targetfonthint passed a stale fd, or
// set_font_slot's destroy-then-replace pattern cleared the slot before
// validating the replacement). Earlier this session I switched to libc fstat
// returning -1 — the panic became silent, fonts disappeared instead of arcan
// crashing visibly. User reverted that with the rule "a system in invalid
// state is worse than a system that dies." See bug 0125 + memory entry
// feedback_no_panics_in_compositor_hot_paths.md.
//
// The probe-via-libc-then-std.posix pattern below preserves the panic
// (std.posix.fstat still panics) but emits a stderr breadcrumb tagged
// "[bug 0125]" with the fd value just before the panic, so journalctl
// alongside the next coredump self-identifies as this bug.
fn do_stat_path(path: [*c]const u8) ?StatResult {
    if (is_freestanding) return null;
    {
        var probe: c.struct_stat = undefined;
        if (c.stat(path, &probe) != 0) {
            const e = std.c._errno().*;
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf,
                "[bug 0125] do_stat_path: about to panic — path={s} errno={d} (see ticket 0125 — `bugs show 0125-arcan-ttf-fstat-unreachable-on-font-replace`)\n",
                .{ std.mem.span(@as([*:0]const u8, @ptrCast(path))), e }) catch "[bug 0125] do_stat_path: about to panic\n";
            _ = std.posix.write(2, msg) catch {};
        }
    }
    const s = std.posix.fstatat(std.posix.AT.FDCWD, std.mem.span(@as([*:0]const u8, @ptrCast(path))), 0) catch return null;
    return .{ .dev = @intCast(s.dev), .ino = @intCast(s.ino) };
}

fn do_fstat_fd(fd: c_int) ?StatResult {
    if (is_freestanding) return null;
    {
        var probe: c.struct_stat = undefined;
        if (c.fstat(fd, &probe) != 0) {
            const e = std.c._errno().*;
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf,
                "[bug 0125] do_fstat_fd: about to panic — fd={d} errno={d} (see ticket 0125 — `bugs show 0125-arcan-ttf-fstat-unreachable-on-font-replace`). Walk back through set_font_slot → setfont → targetfonthint to find the bad-fd source. Do NOT soften this panic.\n",
                .{ fd, e }) catch "[bug 0125] do_fstat_fd: about to panic\n";
            _ = std.posix.write(2, msg) catch {};
        }
    }
    const s = std.posix.fstat(@intCast(fd)) catch return null;
    return .{ .dev = @intCast(s.dev), .ino = @intCast(s.ino) };
}

inline fn do_fileno(stream: ?*FILE) c_int {
    return c.fileno(stream);
}
inline fn do_fcntl_i(fd: c_int, cmd: c_int, arg: c_int) c_int {
    return c.fcntl(fd, cmd, arg);
}
inline fn do_close(fd: c_int) c_int {
    return c.close(fd);
}
inline fn do_strlen(s: [*c]const u8) usize {
    return c.strlen(s);
}

// Style helpers
inline fn TTF_HANDLE_STYLE_BOLD(font: *TTF_Font_Internal) bool {
    return ((font.style & TTF_STYLE_BOLD) != 0) and
        ((font.face_style & TTF_STYLE_BOLD) == 0);
}

inline fn TTF_HANDLE_STYLE_ITALIC(font: *TTF_Font_Internal) bool {
    return ((font.style & TTF_STYLE_ITALIC) != 0) and
        ((font.face_style & TTF_STYLE_ITALIC) == 0);
}

inline fn TTF_HANDLE_STYLE_UNDERLINE(font: *TTF_Font_Internal) bool {
    return (font.style & TTF_STYLE_UNDERLINE) != 0;
}

// Read file into allocated buffer
fn read_file_from_stream(src: *FILE) ?[]u8 {
    const pos = ftell(src);
    if (pos < 0) return null;
    _ = fseek(src, 0, SEEK_END);
    const end = ftell(src);
    if (end <= pos) return null;
    _ = fseek(src, pos, SEEK_SET);

    const size: usize = @intCast(end - pos);
    const buf = gpa.alloc(u8, size) catch return null;
    const nread = fread(@ptrCast(buf.ptr), 1, size, src);
    if (nread != size) {
        gpa.free(buf);
        return null;
    }
    return buf;
}

// Compute font metrics from TrueType at a given scale
fn compute_metrics(font: *TTF_Font_Internal, tt: *const TrueType, scale: f32) void {
    const vm = tt.verticalMetrics();
    font.ascent = @intFromFloat(@round(@as(f32, @floatFromInt(vm.ascent)) * scale));
    font.descent = @intFromFloat(@round(@as(f32, @floatFromInt(vm.descent)) * scale));
    font.height = font.ascent - font.descent + 1;
    font.lineskip = @intFromFloat(@round(@as(f32, @floatFromInt(vm.ascent - vm.descent + vm.line_gap)) * scale));
    // Approximate underline from descent
    font.underline_offset = @divTrunc(font.descent, 2);
    font.underline_height = @max(1, @divTrunc(font.height, 14));
    font.glyph_overhang = @divTrunc(font.height, 10);
    font.glyph_italics = 0.207 * @as(f32, @floatFromInt(font.height));
}

// TTF_FontIsEqual
export fn TTF_FontIsEqual(a: ?*const TTF_Font_Internal, b: ?*const TTF_Font_Internal) callconv(.c) bool {
    const aa = a orelse return false;
    const bb = b orelse return false;
    return aa.height == bb.height and
        aa.ascent == bb.ascent and
        aa.descent == bb.descent and
        aa.lineskip == bb.lineskip and
        aa.face_style == bb.face_style and
        aa.style == bb.style and
        aa.outline == bb.outline and
        aa.kerning == bb.kerning and
        aa.glyph_overhang == bb.glyph_overhang and
        aa.glyph_italics == bb.glyph_italics and
        aa.underline_offset == bb.underline_offset and
        aa.underline_height == bb.underline_height and
        aa.ptsize == bb.ptsize and
        aa.hinting == bb.hinting;
}

// TTF_FindCachedFont
export fn TTF_FindCachedFont(dev: dev_t, ino: ino_t, ptsize: c_int, hdpi: u16, vdpi: u16) callconv(.c) ?*c_font {
    const usage: usize = @intCast(font_cache_usage);
    for (0..usage) |i| {
        const f = &font_cache[i];
        if (f.original != null)
            continue;
        if (f.dev == dev and f.ino == ino and f.ptsize == ptsize and f.hdpi == hdpi and f.vdpi == vdpi) {
            f.ref_count += 1;
            trace_mark_oneshot("font", "cache-hit", TRACE_SYS_DEFAULT, "");
            return f;
        }
    }

    for (0..FONT_CACHE_SIZE) |i| {
        if (font_cache[i].font != null)
            continue;
        const f = &font_cache[i];
        f.dev = dev;
        f.ino = ino;
        f.ptsize = ptsize;
        f.hdpi = hdpi;
        f.vdpi = vdpi;
        f.original = null;
        f.ref_count = 1;

        if (@as(c_int, @intCast(i)) + 1 > font_cache_usage) {
            font_cache_usage = @as(c_int, @intCast(i)) + 1;
        }

        trace_mark_oneshot("font", "cache-miss", TRACE_SYS_DEFAULT, "");
        return f;
    }

    trace_mark_oneshot("font", "cache-overrun", TRACE_SYS_WARN, "");
    return null;
}

// TTF_FindOrForkCachedFont
export fn TTF_FindOrForkCachedFont(original: ?*c_font, template: ?*const TTF_Font_Internal) callconv(.c) ?*c_font {
    const tmpl = template orelse return null;
    const orig = original orelse return null;
    var result: ?*c_font = null;

    const usage: usize = @intCast(font_cache_usage);
    for (0..usage) |i| {
        if (font_cache[i].font == null)
            continue;
        if (!TTF_FontIsEqual(font_cache[i].font, tmpl))
            continue;
        result = &font_cache[i];
        break;
    }

    if (result == null) {
        for (0..FONT_CACHE_SIZE) |i| {
            if (font_cache[i].font != null)
                continue;
            result = &font_cache[i];
            if (@as(c_int, @intCast(i)) + 1 > font_cache_usage) {
                font_cache_usage = @as(c_int, @intCast(i)) + 1;
            }
            break;
        }
    }

    const res = result orelse return null;

    if (res.font != null) {
        res.ref_count += 1;
        trace_mark_oneshot("font", "cache-hit", TRACE_SYS_DEFAULT, "fork");
        return res;
    }
    trace_mark_oneshot("font", "cache-miss", TRACE_SYS_DEFAULT, "fork");

    res.* = orig.*;
    res.original = orig;
    res.ref_count = 1;

    const forked = gpa.create(TTF_Font_Internal) catch return null;
    forked.* = orig.font.?.*;
    forked.font_bytes_owned = false; // shared with original
    forked.cached_height = 0;
    forked.cached_width = 0;

    // Reset glyph cache.  After `forked.* = orig.font.?.*` above, every
    // c_glyph in forked.cache is a shallow copy whose alpha_buf slice aliases
    // the original's heap-owned buffer.  Freeing here would double-free the
    // original's glyphs as soon as it tears down (bug 0037, family 0009/0031).
    // Just clear; the original retains ownership of those buffers.
    forked.current = &forked.cache[0];
    for (&forked.cache) |*entry| {
        entry.* = .{};
    }

    res.font = forked;
    return res;
}

// TTF_ResetCachedFont
export fn TTF_ResetCachedFont(font: ?*c_font) callconv(.c) void {
    const f = font orelse return;
    const usage: usize = @intCast(font_cache_usage);
    for (0..usage) |i| {
        if (&font_cache[i] != f)
            continue;

        trace_mark_oneshot("font", "cache-release", TRACE_SYS_DEFAULT, "");
        font_cache[i].font = null;

        if (@as(c_int, @intCast(i)) + 1 == font_cache_usage) {
            font_cache_usage -= 1;
        }
        return;
    }

    trace_mark_oneshot("font", "cache-release-fail", TRACE_SYS_ERROR, "");
}

// TTF_SetError
export fn TTF_SetError(_: [*c]const u8) callconv(.c) void {}

// TTF_underline_top_row
export fn TTF_underline_top_row(font_ref: ?*TTF_Font) callconv(.c) c_int {
    const fr = font_ref orelse return 0;
    const font = fr.font orelse return 0;
    return font.ascent - font.underline_offset - 1;
}

// TTF_GetFtFace — stub, no FreeType face
export fn TTF_GetFtFace(_: ?*TTF_Font) callconv(.c) ?*anyopaque {
    return null;
}

// TTF_underline_bottom_row
export fn TTF_underline_bottom_row(font_ref: ?*TTF_Font) callconv(.c) c_int {
    const fr = font_ref orelse return 0;
    const font = fr.font orelse return 0;
    var row = TTF_underline_top_row(font_ref) + font.underline_height;
    if (font.outline > 0) {
        row += font.outline * 2;
    }
    return row;
}

// TTF_strikethrough_top_row
export fn TTF_strikethrough_top_row(font_ref: ?*TTF_Font) callconv(.c) c_int {
    const fr = font_ref orelse return 0;
    const font = fr.font orelse return 0;
    return @divTrunc(font.height, 2);
}

// TTF_Init
export fn TTF_Init() callconv(.c) c_int {
    TTF_initialized += 1;
    return 0;
}

// TTF_OpenFontIndexRW
export fn TTF_OpenFontIndexRW(
    src: ?*FILE,
    freesrc: c_int,
    ptsize: c_int,
    _: u16, // hdpi — TrueType.zig uses pixel height, not DPI
    _: u16, // vdpi
    _: c_long, // index — TrueType.zig reads first font
) callconv(.c) ?*TTF_Font {
    if (is_freestanding) return null;
    const stream = src orelse return null;

    if (TTF_initialized == 0) {
        _ = TTF_Init();
    }

    // Read entire font file into memory
    const font_bytes = read_file_from_stream(stream) orelse {
        if (freesrc != 0) _ = fclose(stream);
        return null;
    };

    if (freesrc != 0) _ = fclose(stream);

    // Parse with TrueType
    const tt = TrueType.load(font_bytes) catch {
        gpa.free(font_bytes);
        return null;
    };

    const font = gpa.create(TTF_Font_Internal) catch {
        gpa.free(font_bytes);
        return null;
    };
    font.* = .{};

    font.tt = tt;
    font.font_bytes = font_bytes;
    font.font_bytes_owned = true;
    // Allow env override for GPU glyph quality testing at high resolution
    const override_sz = std.posix.getenv("ARCAN_FONT_SIZE_OVERRIDE");
    const effective_ptsize = if (override_sz) |sz_str|
        std.fmt.parseInt(c_int, sz_str, 10) catch ptsize
    else
        ptsize;
    font.ptsize = effective_ptsize;
    font.scale = tt.scaleForPixelHeight(@floatFromInt(effective_ptsize));
    font.style = TTF_STYLE_NORMAL;
    font.kerning = 1;

    compute_metrics(font, &tt, font.scale);

    // Set variable font weight from env var (for testing different weights)
    if (tt.isVariable()) {
        const weight_str = std.posix.getenv("ARCAN_FONT_WEIGHT");
        if (weight_str) |ws| {
            const weight = std.fmt.parseFloat(f32, ws) catch 400.0;
            // Find weight axis (wght)
            for (0..tt.getAxisCount()) |i| {
                if (tt.getAxis(@intCast(i))) |axis| {
                    if (std.mem.eql(u8, &axis.tag, "wght")) {
                        var mutable_tt = tt;
                        mutable_tt.setVariation(@intCast(i), weight);
                        font.tt = mutable_tt;
                    }
                }
            }
        }
    }

    // Write font info to /tmp/font_axes.txt
    {
        const dbg = std.fs.createFileAbsolute("/tmp/font_axes.txt", .{}) catch null;
        if (dbg) |df| {
            defer df.close();
            var b: [512]u8 = undefined;
            _ = TrueType.TableId.fvar.asInt();
            _ = TrueType.TableId.gvar.asInt();
            const fb = font.font_bytes orelse &[_]u8{};
            const file_tables = if (fb.len > 6) std.mem.readInt(u16, fb[4..6], .big) else 0;
            // Read first 3 table tags from the file
            var tags: [3][4]u8 = undefined;
            for (0..3) |ti| {
                if (12 + ti * 16 + 4 <= fb.len)
                    tags[ti] = fb[12 + ti * 16 ..][0..4].*
                else
                    tags[ti] = .{ 0, 0, 0, 0 };
            }
            const s = std.fmt.bufPrint(&b, "ptsize={d} isVar={} fvar_off={d} gvar_off={d}\nfont_bytes={d} file_tables={d}\ntag0={s} tag1={s} tag2={s}\n", .{
                effective_ptsize, tt.isVariable(),
                tt.table_offsets[@intFromEnum(TrueType.TableId.fvar)],
                tt.table_offsets[@intFromEnum(TrueType.TableId.gvar)],
                fb.len, file_tables,
                &tags[0], &tags[1], &tags[2],
            }) catch "err\n";
            df.writeAll(s) catch {};
        }
    }
    if (tt.isVariable()) {
        const f = std.fs.createFileAbsolute("/tmp/font_axes.txt", .{}) catch null;
        if (f) |file| {
            defer file.close();
            const n_axes = tt.getAxisCount();
            var buf: [256]u8 = undefined;
            const hdr = std.fmt.bufPrint(&buf, "Variable font: {d} axes, gvar={}\n", .{ n_axes, tt.hasGlyphVariations() }) catch "";
            file.writeAll(hdr) catch {};
            for (0..n_axes) |i| {
                if (tt.getAxis(@intCast(i))) |axis| {
                    const line = std.fmt.bufPrint(&buf, "  {s}: {d:.0}..{d:.0}..{d:.0}\n", .{
                        &axis.tag, axis.min_value, axis.default_value, axis.max_value,
                    }) catch "";
                    file.writeAll(line) catch {};
                }
            }
        }
    }

    const font_ref = gpa.create(TTF_Font) catch {
        gpa.free(font_bytes);
        gpa.destroy(font);
        return null;
    };
    font_ref.* = .{};
    font_ref.font = font;
    font_ref.cache_entry = null;

    return font_ref;
}

// TTF_OpenFontRW
export fn TTF_OpenFontRW(
    src: ?*FILE,
    freesrc: c_int,
    ptsize: c_int,
    hdpi: u16,
    vdpi: u16,
) callconv(.c) ?*TTF_Font {
    return TTF_OpenFontIndexRW(src, freesrc, ptsize, hdpi, vdpi, 0);
}

// TTF_OpenFontIndex
export fn TTF_OpenFontIndex(
    file: [*c]const u8,
    ptsize: c_int,
    hdpi: u16,
    vdpi: u16,
    index: c_long,
) callconv(.c) ?*TTF_Font {
    if (is_freestanding) return null;
    const sr = do_stat_path(file) orelse return null;

    const cached = TTF_FindCachedFont(sr.dev, sr.ino, ptsize, hdpi, vdpi);
    if (cached) |ca| {
        if (ca.font != null) {
            const font_ref = gpa.create(TTF_Font) catch return null;
            font_ref.* = .{};
            font_ref.font = ca.font;
            font_ref.cache_entry = ca;
            return font_ref;
        }
    }

    const rw = fopen(file, "r") orelse return null;
    _ = do_fcntl_i(do_fileno(rw), 2, 1); // F_SETFD, FD_CLOEXEC

    const font_ref = TTF_OpenFontIndexRW(rw, 1, ptsize, hdpi, vdpi, index) orelse return null;

    if (cached) |ca| {
        ca.font = font_ref.font;
        font_ref.cache_entry = ca;
    }

    return font_ref;
}

// TTF_OpenFont
export fn TTF_OpenFont(
    file: [*c]const u8,
    ptsize: c_int,
    hdpi: u16,
    vdpi: u16,
) callconv(.c) ?*TTF_Font {
    return TTF_OpenFontIndex(file, ptsize, hdpi, vdpi, 0);
}

// TTF_ReplaceFont
export fn TTF_ReplaceFont(
    font_ref: ?*TTF_Font,
    ptsize: c_int,
    hdpi: u16,
    vdpi: u16,
) callconv(.c) ?*TTF_Font {
    const fr = font_ref orelse return font_ref;
    const font = fr.font orelse return font_ref;
    if (font.src_fd == -1) return font_ref;
    const newfd = arcan_shmif_dupfd(font.src_fd, -1, true);
    if (newfd == -1)
        return font_ref;

    const new_font = TTF_OpenFontFD(newfd, ptsize, hdpi, vdpi);
    _ = do_close(newfd);

    if (new_font == null) {
        return font_ref;
    }

    TTF_CloseFont(font_ref);
    return new_font;
}

// TTF_OpenFontFD
export fn TTF_OpenFontFD(
    fd: c_int,
    ptsize: c_int,
    hdpi: u16,
    vdpi: u16,
) callconv(.c) ?*TTF_Font {
    if (is_freestanding) return null;
    if (fd == -1)
        return null;

    const sr = do_fstat_fd(fd) orelse return null;

    const cached = TTF_FindCachedFont(sr.dev, sr.ino, ptsize, hdpi, vdpi);
    if (cached) |ca| {
        if (ca.font != null) {
            const font_ref = gpa.create(TTF_Font) catch return null;
            font_ref.* = .{};
            font_ref.font = ca.font;
            font_ref.cache_entry = ca;
            return font_ref;
        }
    }

    const nfd = arcan_shmif_dupfd(fd, -1, true);
    if (nfd == -1)
        return null;

    const fstream = fdopen(nfd, "r") orelse {
        _ = do_close(nfd);
        return null;
    };

    _ = fseek(fstream, SEEK_SET, 0);
    const res = TTF_OpenFontIndexRW(fstream, 1, ptsize, hdpi, vdpi, 0) orelse return null;

    // Store the fd for TTF_ReplaceFont
    if (res.font) |f| f.src_fd = nfd;

    if (cached) |ca| {
        ca.font = res.font;
        res.cache_entry = ca;
    }

    return res;
}

// Flush_Glyph
fn Flush_Glyph(entry: *c_glyph) void {
    if (entry.alpha_buf) |buf| {
        gpa.free(buf);
        entry.alpha_buf = null;
    }
    entry.stored = 0;
    entry.index = .notdef;
    entry.cached = 0;
}

// TTF_Flush_Cache_Internal
export fn TTF_Flush_Cache_Internal(font: ?*TTF_Font_Internal) callconv(.c) void {
    const f = font orelse return;
    for (&f.cache) |*entry| {
        if (entry.cached != 0) {
            Flush_Glyph(entry);
        }
    }
}

// TTF_Flush_Cache
export fn TTF_Flush_Cache(font_ref: ?*TTF_Font) callconv(.c) void {
    const fr = font_ref orelse return;
    trace_mark_oneshot("font", "glyph-cache-flush", TRACE_SYS_DEFAULT, "");
    TTF_Flush_Cache_Internal(fr.font);
}

// bug 0031 hardening: validate that the TrueType slice has not been
// silently invalidated before we hand it to any TrueType routine.
// The pointer-bind pattern (`if (font.tt) |*t| t`) protects against
// rvalue-copy stack churn, but it can't protect against
// use-after-free: if the underlying TTF_Font_Internal or its
// font_bytes buffer was freed elsewhere, `tt.ttf_bytes` will be a
// stale slice header — zeroed if the struct was wiped, plausible
// garbage if the allocator reused the memory.  Reading
// `bytes[index_map..][0..2]` then segfaults in codepointGlyphIndex.
//
// Strategy: cross-check `tt.ttf_bytes` against `font.font_bytes` —
// these two slices are written together (TTF_OpenFontIndexRW lines
// ~490-491) and copied together (TTF_FindOrForkCachedFont:376), so
// `tt.ttf_bytes.ptr == font.font_bytes.?.ptr` is an invariant.  If
// the struct has been freed-and-reused, the random data in the two
// fields will (with overwhelming probability) disagree.  This is a
// metadata-only check — it never reads from the potentially-dangling
// `ttf_bytes` buffer itself, so a stale pointer pointing into
// unmapped memory cannot fault here.
//
// Length-range checks below catch obviously-zeroed or
// obviously-garbage slice headers as well.
//
// All failures emit a `font/tt-corrupt` trace event with the values
// observed, so the next occurrence pinpoints the corruption shape.
fn tt_slice_looks_sane(font: *const TTF_Font_Internal, tt: *const TrueType) bool {
    // bug 0031: when sanity-check fails the cause is structural (UAF / freed
    // font_bytes / corrupt header) — silently returning false made the
    // primary symptom "fonts render blank" instead of a coredump, which
    // hid every recurrence after the oneshot trace fired. Panic so the
    // backtrace pins the live caller.
    if (font.font_bytes) |fb| {
        if (tt.ttf_bytes.ptr != fb.ptr or tt.ttf_bytes.len != fb.len) {
            std.debug.panic(
                "[bug 0031] tt/font_bytes UAF mismatch: tt.bytes={*}/{d} != font.font_bytes={*}/{d}",
                .{ tt.ttf_bytes.ptr, tt.ttf_bytes.len, fb.ptr, fb.len },
            );
        }
    } else {
        std.debug.panic("[bug 0031] tt is set but font.font_bytes=null — UAF on TTF_Font_Internal", .{});
    }

    const sane_min: usize = 64;
    const sane_max: usize = 256 * 1024 * 1024;
    if (tt.ttf_bytes.len < sane_min or tt.ttf_bytes.len > sane_max) {
        std.debug.panic(
            "[bug 0031] ttf_bytes.len={d} out of [{d}, {d}] — corrupt slice header",
            .{ tt.ttf_bytes.len, sane_min, sane_max },
        );
    }
    if (@as(usize, tt.index_map) + 16 > tt.ttf_bytes.len) {
        std.debug.panic(
            "[bug 0031] index_map={d} + 16 > ttf_bytes.len={d} — corrupt TTF header",
            .{ tt.index_map, tt.ttf_bytes.len },
        );
    }
    return true;
}

// Load_Glyph
fn Load_Glyph(
    font: *TTF_Font_Internal,
    ch: u32,
    cached_glyph: *c_glyph,
    want: c_int,
    by_ind: bool,
) c_int {
    // bug 0031 (separate site from bug 0009 fixes): `font.tt orelse …`
    // produces an rvalue COPY of the optional payload; the slice header
    // (ptr,len) lives on a stack temporary that gets clobbered as soon
    // as another routine reuses the slot.  The reads later in this
    // function then dereference the stale pointer → SIGSEGV in
    // TrueType.codepointGlyphIndex via the recursive atlasLookup path.
    // Pointer-bind into font.tt's storage instead.
    const tt: *const TrueType = if (font.tt) |*t| t else return -1;

    // bug 0031 (recurrence 2026-04-30): the pointer-bind alone is not
    // sufficient.  Validate the slice header looks like a real TTF
    // before reading from it — if the font was freed-and-reused (UAF),
    // we'd otherwise dereference garbage in codepointGlyphIndex.
    if (!tt_slice_looks_sane(font, tt)) return -1;

    // Resolve glyph index
    if (cached_glyph.index == .notdef) {
        if (by_ind) {
            cached_glyph.index = @enumFromInt(@as(u16, @truncate(ch)));
        } else {
            cached_glyph.index = tt.codepointGlyphIndex(@intCast(ch & 0x1FFFFF));
        }
        if (cached_glyph.index == .notdef) {
            return -1;
        }
    }

    const scale = font.scale;
    const gi = cached_glyph.index;

    // Compute metrics
    if ((want & CACHED_METRICS) != 0 and (cached_glyph.stored & CACHED_METRICS) == 0) {
        const hm = tt.glyphHMetrics(gi);
        const bbox = tt.glyphBitmapBox(gi, scale, scale);

        cached_glyph.minx = bbox.x0;
        cached_glyph.maxx = bbox.x1;
        cached_glyph.miny = bbox.y0;
        cached_glyph.maxy = bbox.y1;
        cached_glyph.yoffset = bbox.y0; // top of glyph relative to baseline
        cached_glyph.advance = @intFromFloat(@round(@as(f32, @floatFromInt(hm.advance_width)) * scale));

        // Adjust for bold
        if (TTF_HANDLE_STYLE_BOLD(font)) {
            cached_glyph.maxx += font.glyph_overhang;
        }
        if (TTF_HANDLE_STYLE_ITALIC(font)) {
            cached_glyph.maxx += @intFromFloat(@ceil(font.glyph_italics));
        }
        cached_glyph.stored |= CACHED_METRICS;
    }

    // Rasterize
    if ((want & CACHED_PIXMAP) != 0 and (cached_glyph.stored & CACHED_PIXMAP) == 0) {
        var pixels = std.ArrayListUnmanaged(u8){};
        const bmp = tt.glyphBitmap(gpa, &pixels, gi, scale, scale) catch |err| {
            if (err == error.GlyphNotFound) {
                // Space and other non-visual glyphs: no bitmap, but metrics are valid
                cached_glyph.alpha_buf = null;
                cached_glyph.alpha_width = 0;
                cached_glyph.alpha_height = 0;
                cached_glyph.stored |= CACHED_PIXMAP;
                cached_glyph.cached = ch;
                return 0; // success — metrics already computed above
            }
            return -1;
        };

        if (bmp.width > 0 and bmp.height > 0) {
            // Handle bold by smearing right
            if (TTF_HANDLE_STYLE_BOLD(font)) {
                const overhang: usize = @intCast(font.glyph_overhang);
                const new_w: usize = @as(usize, bmp.width) + overhang;
                const new_buf = gpa.alloc(u8, new_w * @as(usize, bmp.height)) catch {
                    pixels.deinit(gpa);
                    return -1;
                };
                @memset(new_buf, 0);
                var row: usize = 0;
                while (row < bmp.height) : (row += 1) {
                    const src_row = pixels.items[row * @as(usize, bmp.width) ..][0..bmp.width];
                    const dst_row = new_buf[row * new_w ..][0..new_w];
                    @memcpy(dst_row[0..bmp.width], src_row);
                    // Smear right for bold
                    var off: usize = 1;
                    while (off <= overhang) : (off += 1) {
                        var col: usize = new_w - 1;
                        while (col >= off) : (col -= 1) {
                            const v = @as(u16, dst_row[col]) + @as(u16, dst_row[col - 1]);
                            dst_row[col] = @intCast(@min(v, 255));
                            if (col == off) break;
                        }
                    }
                }
                pixels.deinit(gpa);
                cached_glyph.alpha_buf = new_buf;
                cached_glyph.alpha_width = @intCast(new_w);
                cached_glyph.alpha_height = bmp.height;
            } else {
                cached_glyph.alpha_buf = pixels.toOwnedSlice(gpa) catch {
                    pixels.deinit(gpa);
                    return -1;
                };
                cached_glyph.alpha_width = bmp.width;
                cached_glyph.alpha_height = bmp.height;
            }
            cached_glyph.alpha_off_x = bmp.off_x;
            cached_glyph.alpha_off_y = bmp.off_y;
        } else {
            pixels.deinit(gpa);
            cached_glyph.alpha_buf = null;
            cached_glyph.alpha_width = 0;
            cached_glyph.alpha_height = 0;
        }
        cached_glyph.stored |= CACHED_PIXMAP;
    }

    cached_glyph.cached = ch;
    return 0;
}

// Find_Glyph
fn Find_Glyph(font: *TTF_Font_Internal, ch: u32, want: c_int, by_ind: bool) c_int {
    const h: usize = ch % 257;
    font.current = &font.cache[h];

    if (font.current.?.cached != ch) {
        Flush_Glyph(font.current.?);
    }

    if ((@as(c_int, font.current.?.stored) & want) != want) {
        return Load_Glyph(font, ch, font.current.?, want, by_ind);
    }
    return 0;
}

// TTF_FindGlyph
export fn TTF_FindGlyph(
    fonts: [*c]?*TTF_Font,
    n: c_int,
    ch: u32,
    want: c_int,
    by_ind: bool,
) callconv(.c) ?*TTF_Font {
    const count: usize = @intCast(n);
    for (0..count) |i| {
        const font_ref = fonts[i] orelse continue;
        const font = font_ref.font orelse continue;
        if (Find_Glyph(font, ch, want, by_ind) != 0)
            continue;
        return font_ref;
    }
    return null;
}

// TTF_CloseFontInternal
export fn TTF_CloseFontInternal(font: ?*TTF_Font_Internal, is_original: bool) callconv(.c) void {
    const f = font orelse return;
    TTF_Flush_Cache_Internal(f);

    if (is_original) {
        if (f.font_bytes_owned) {
            if (f.font_bytes) |bytes| gpa.free(bytes);
        }
        if (f.src_fd != -1) {
            _ = do_close(f.src_fd);
        }
    }

    // bug 0031 hardening: poison the struct before destroy so any
    // surviving caller hitting `font.tt` / `font.font_bytes` is
    // detected by tt_slice_looks_sane (mismatch + length checks)
    // instead of dereferencing the dangling slice.  DebugAllocator's
    // never_unmap+retain_metadata keeps the page mapped, so the
    // poisoned values stay readable until process exit.
    f.tt = null;
    f.font_bytes = null;
    f.font_bytes_owned = false;
    f.current = null;

    gpa.destroy(f);
}

// TTF_CloseFont
export fn TTF_CloseFont(font_ref: ?*TTF_Font) callconv(.c) void {
    const fr = font_ref orelse return;

    if (fr.font == null) {
        gpa.destroy(fr);
        return;
    }

    if (fr.cache_entry) |current| {
        const original = current.original;

        current.ref_count -= 1;

        if (current.ref_count == 0) {
            TTF_CloseFontInternal(current.font, original == null);
            TTF_ResetCachedFont(current);
        }

        if (original) |orig| {
            if (orig.ref_count == 0) {
                return;
            }
            orig.ref_count -= 1;
            if (orig.ref_count == 0) {
                TTF_CloseFontInternal(orig.font, true);
                TTF_ResetCachedFont(orig);
            }
        }
    } else {
        TTF_CloseFontInternal(fr.font, true);
    }

    gpa.destroy(fr);
}

// TTF_Resize
export fn TTF_Resize(_: ?*TTF_Font, _: c_int, _: u16, _: u16) callconv(.c) void {
    trace_mark_oneshot("font", "stub", TRACE_SYS_WARN, "TTF_Resize is stubbed due to font caching constraints");
}

// UTF8 to UTF32 conversion tables
const u8lenlut = [256]u8{
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5,
};

const u8ofslut = [6]u32{
    0x00000000, 0x00003080, 0x000E2080,
    0x03C82080, 0xFA082080, 0x82082080,
};

// UTF8_to_UTF32
export fn UTF8_to_UTF32(out: [*c]u32, in_buf: [*c]const u8, len: usize) callconv(.c) c_int {
    var outp = out;
    var i: usize = 0;

    while (i < len) {
        var ch: u32 = 0;
        const nr = u8lenlut[in_buf[i]];

        var remaining = nr;
        while (remaining > 0) : (remaining -= 1) {
            ch += in_buf[i];
            i += 1;
            ch <<= 6;
        }
        ch += in_buf[i];
        i += 1;

        ch -= u8ofslut[nr];

        if (ch <= 0x0010FFFF) {
            if (ch >= 0xD800 and ch <= 0xDFFF) {
                outp[0] = 0x0000FFFD;
            } else {
                outp[0] = ch;
            }
        } else {
            outp[0] = 0x0000FFFD;
        }
        outp += 1;
    }
    outp[0] = 0;
    return 1;
}

// TTF_FontHeight
export fn TTF_FontHeight(font_ref: ?*const TTF_Font) callconv(.c) c_int {
    const fr = font_ref orelse return 0;
    const font = fr.font orelse return 0;
    return font.height;
}

// TTF_FontAscent
export fn TTF_FontAscent(font_ref: ?*const TTF_Font) callconv(.c) c_int {
    const fr = font_ref orelse return 0;
    const font = fr.font orelse return 0;
    return font.ascent;
}

// TTF_FontDescent
export fn TTF_FontDescent(font_ref: ?*const TTF_Font) callconv(.c) c_int {
    const fr = font_ref orelse return 0;
    const font = fr.font orelse return 0;
    return font.descent;
}

// TTF_FontLineSkip
export fn TTF_FontLineSkip(font_ref: ?*const TTF_Font) callconv(.c) c_int {
    const fr = font_ref orelse return 0;
    const font = fr.font orelse return 0;
    return font.lineskip;
}

// TTF_GetFontKerning
export fn TTF_GetFontKerning(font_ref: ?*const TTF_Font) callconv(.c) c_int {
    const fr = font_ref orelse return 0;
    const font = fr.font orelse return 0;
    return font.kerning;
}

// TTF_SetFontKerning
export fn TTF_SetFontKerning(font_ref: ?*TTF_Font, allowed: c_int) callconv(.c) void {
    const fr = font_ref orelse return;
    const font = fr.font orelse return;
    if (font.kerning == allowed)
        return;

    if (fr.cache_entry) |entry| {
        var template = font.*;
        template.kerning = allowed;
        const fork = TTF_FindOrForkCachedFont(entry, &template) orelse return;
        fr.font = fork.font;
        fr.cache_entry = fork;
    }

    if (fr.font) |f| {
        f.kerning = allowed;
    }
}

// TTF_FontFaces
export fn TTF_FontFaces(_: ?*const TTF_Font) callconv(.c) c_long {
    return 1; // TrueType.zig reads only one font from a file
}

// TTF_FontFaceIsFixedWidth
export fn TTF_FontFaceIsFixedWidth(_: ?*const TTF_Font) callconv(.c) c_int {
    // TrueType.zig doesn't expose this; return 0 (variable width)
    return 0;
}

// TTF_FontFaceFamilyName
export fn TTF_FontFaceFamilyName(_: ?*const TTF_Font) callconv(.c) [*c]u8 {
    // TrueType.zig doesn't expose name table; return null
    return null;
}

// TTF_FontFaceStyleName
export fn TTF_FontFaceStyleName(_: ?*const TTF_Font) callconv(.c) [*c]u8 {
    return null;
}

// TTF_SetFontStyle
export fn TTF_SetFontStyle(font_ref: ?*TTF_Font, style: c_int) callconv(.c) void {
    const fr = font_ref orelse return;
    const font = fr.font orelse return;
    const new_style = style | font.face_style;

    if (font.style == new_style)
        return;

    if (fr.cache_entry) |entry| {
        var template = font.*;
        template.style = new_style;
        const fork = TTF_FindOrForkCachedFont(entry, &template) orelse return;
        fr.font = fork.font;
        fr.cache_entry = fork;
    }

    const old_style = fr.font.?.style;
    fr.font.?.style = new_style;
    if ((new_style | TTF_STYLE_NO_GLYPH_CHANGE) != (old_style | TTF_STYLE_NO_GLYPH_CHANGE)) {
        TTF_Flush_Cache(fr);
    }
}

// size_upool
fn size_upool(len: c_int) void {
    if (len <= 0)
        return;

    const ulen: usize = @intCast(len);
    if (pool_cnt < ulen) {
        if (unicode_buf) |buf| {
            free(@ptrCast(buf));
        }
        const ptr = malloc((ulen + 1) * @sizeOf(u32)) orelse {
            unicode_buf = null;
            pool_cnt = 0;
            return;
        };
        unicode_buf = @ptrCast(@alignCast(ptr));
        pool_cnt = ulen + 1;
    }
}

// TTF_SizeUTF8chain
export fn TTF_SizeUTF8chain(
    font: [*c]?*TTF_Font,
    n: usize,
    text: [*c]const u8,
    w: ?*c_int,
    h: ?*c_int,
    style: c_int,
) callconv(.c) c_int {
    const unicode_len: c_int = @intCast(do_strlen(text));
    size_upool(unicode_len + 1);

    const buf = unicode_buf orelse return -1;
    _ = UTF8_to_UTF32(buf, text, @intCast(unicode_len));
    return TTF_SizeUNICODEchain(font, n, buf, w, h, style);
}

// TTF_SizeUTF8
export fn TTF_SizeUTF8(
    font: ?*TTF_Font,
    text: [*c]const u8,
    w: ?*c_int,
    h: ?*c_int,
    style: c_int,
) callconv(.c) c_int {
    var font_arr = [_]?*TTF_Font{font};
    return TTF_SizeUTF8chain(&font_arr, 1, text, w, h, style);
}

// TTF_SizeUNICODE
export fn TTF_SizeUNICODE(
    font: ?*TTF_Font,
    text: [*c]const u32,
    w: ?*c_int,
    h: ?*c_int,
    style: c_int,
) callconv(.c) c_int {
    var font_arr = [_]?*TTF_Font{font};
    return TTF_SizeUNICODEchain(&font_arr, 1, text, w, h, style);
}

// TTF_SizeUNICODEchain
export fn TTF_SizeUNICODEchain(
    font: [*c]?*TTF_Font,
    n: usize,
    text: [*c]const u32,
    w: ?*c_int,
    h: ?*c_int,
    _: c_int,
) callconv(.c) c_int {
    var x: c_int = 0;
    var minx: c_int = 0;
    var maxx: c_int = 0;
    var miny: c_int = 0;
    var maxy: c_int = 0;
    var prev_index: TrueType.GlyphIndex = .notdef;
    var outline_delta: c_int = 0;

    if (TTF_initialized == 0) {
        TTF_SetError("Library not initialized");
        return -1;
    }

    const font0 = font[0] orelse return -1;
    const font0_internal = font0.font orelse return -1;
    // bug 0031: pointer-bind, not rvalue-copy.  `font0_internal.tt orelse …`
    // copies the TrueType payload onto a stack temp; its `ttf_bytes` slice
    // header is dangling once the temp's slot is reused, and the next
    // `tt0.glyphKernAdvance(...)` SIGSEGVs in TrueType.codepointGlyphIndex.
    const tt0: *const TrueType = if (font0_internal.tt) |*t| t else return -1;

    const use_kerning: bool = font0_internal.kerning != 0;

    if (font0_internal.outline > 0) {
        outline_delta = font0_internal.outline * 2;
    }

    var ch = text;
    while (ch[0] != 0) : (ch += 1) {
        const char_val = ch[0];
        const outf = TTF_FindGlyph(font, @intCast(n), char_val, CACHED_METRICS, false) orelse {
            continue;
        };
        const outf_internal = outf.font orelse continue;
        const glyph_entry = outf_internal.current orelse continue;

        // kerning
        if (use_kerning and prev_index != .notdef and glyph_entry.index != .notdef) {
            const kern = tt0.glyphKernAdvance(prev_index, glyph_entry.index);
            x += @intFromFloat(@round(@as(f32, @floatFromInt(kern)) * font0_internal.scale));
        }

        var z = x + glyph_entry.minx;
        if (minx > z)
            minx = z;

        if (TTF_HANDLE_STYLE_BOLD(outf_internal)) {
            x += outf_internal.glyph_overhang;
        }
        if (glyph_entry.advance > glyph_entry.maxx) {
            z = x + glyph_entry.advance;
        } else {
            z = x + glyph_entry.maxx;
        }
        if (maxx < z)
            maxx = z;

        x += glyph_entry.advance;

        if (glyph_entry.miny < miny)
            miny = glyph_entry.miny;

        if (glyph_entry.maxy > maxy)
            maxy = glyph_entry.maxy;

        prev_index = glyph_entry.index;
    }

    if (w) |wp| {
        wp.* = (maxx - minx) + outline_delta;
    }
    if (h) |hp| {
        hp.* = (font0_internal.ascent - miny) + outline_delta;
        if (hp.* < font0_internal.height) {
            hp.* = font0_internal.height;
        }
        if (TTF_HANDLE_STYLE_UNDERLINE(font0_internal)) {
            const bottom_row = TTF_underline_bottom_row(font0);
            if (hp.* < bottom_row) {
                hp.* = bottom_row;
            }
        }
    }
    return 0;
}

// Pixel packing helpers
inline fn pack_pixel_bg(fg: [*c]u8, bg: [*c]u8, a: u8) PIXEL {
    if (a == 0)
        return PACK(bg[0], bg[1], bg[2], bg[3]);

    if (a == 255)
        return PACK(fg[0], fg[1], fg[2], 0xff);

    const a32: u32 = a;
    var r: u32 = 0x80 + (a32 * @as(u32, fg[0]) + @as(u32, bg[0]) * (255 - a32));
    r = (r + (r >> 8)) >> 8;
    var g: u32 = 0x80 + (a32 * @as(u32, fg[1]) + @as(u32, bg[1]) * (255 - a32));
    g = (g + (g >> 8)) >> 8;
    var b: u32 = 0x80 + (a32 * @as(u32, fg[2]) + @as(u32, bg[2]) * (255 - a32));
    b = (b + (b >> 8)) >> 8;
    const av: u8 = if (a < bg[3] or a -| bg[3] < bg[3]) bg[3] else a;
    return PACK(r, g, b, av);
}

inline fn pack_pixel(fg: [*c]u8, a: u8) PIXEL {
    const fa: u8 = if (a > 0) 1 else 0;
    return PACK(@as(u32, fg[0]) * fa, @as(u32, fg[1]) * fa, @as(u32, fg[2]) * fa, a);
}

// render_unicode
fn render_unicode(
    dst: [*]PIXEL,
    width: usize,
    height: usize,
    stride: c_int,
    font0_ref: ?*TTF_Font,
    outf_ref: *TTF_Font,
    xstart: *c_uint,
    fg: [*c]u8,
    bg: [*c]u8,
    usebg: bool,
    use_kerning: bool,
    advance: *c_int,
    prev_index: *TrueType.GlyphIndex,
) bool {
    const outf = outf_ref.font orelse return false;
    const glyph_entry = outf.current orelse return false;
    advance.* = glyph_entry.advance;

    const gwidth: c_int = @intCast(glyph_entry.alpha_width);

    // Kerning
    if (use_kerning and prev_index.* != .notdef and glyph_entry.index != .notdef) {
        const font0 = if (font0_ref) |f0| f0.font else null;
        if (font0) |f0_internal| {
            // bug 0031: capture by pointer (`|*tt|`), not by value (`|tt|`).
            // Value-capture rvalue-copies the TrueType payload — its
            // `ttf_bytes` slice header dangles once the temp slot is
            // reused, and `tt.glyphKernAdvance` then reads stale ptr.
            if (f0_internal.tt) |*tt| {
                const kern = tt.glyphKernAdvance(prev_index.*, glyph_entry.index);
                const kern_px: c_int = @intFromFloat(@round(@as(f32, @floatFromInt(kern)) * f0_internal.scale));
                xstart.* +%= @bitCast(kern_px);
            }
        }
    }

    // Render alpha bitmap into RGBA destination
    const alpha_buf = glyph_entry.alpha_buf orelse {
        // No bitmap (space character etc.) — just advance
        if (TTF_HANDLE_STYLE_BOLD(outf))
            xstart.* += @intCast(outf.glyph_overhang);
        prev_index.* = glyph_entry.index;
        return true;
    };

    const bmp_w: usize = @intCast(glyph_entry.alpha_width);
    const bmp_h: usize = @intCast(glyph_entry.alpha_height);

    // yoffset: TrueType.zig gives off_y as top-left offset from origin
    // In arcan's coordinate system, yoffset positions the glyph relative to
    // the top of the cell (ascent line)
    const y_off: c_int = outf.ascent + @as(c_int, glyph_entry.alpha_off_y);
    const x_off: c_int = @as(c_int, @intCast(xstart.*)) + @as(c_int, glyph_entry.alpha_off_x);

    var row: usize = 0;
    while (row < bmp_h) : (row += 1) {
        const dest_y: c_int = y_off + @as(c_int, @intCast(row));
        if (dest_y < 0 or dest_y >= @as(c_int, @intCast(height)))
            continue;

        const dest_y_u: usize = @intCast(dest_y);
        var col: usize = 0;
        while (col < bmp_w and col < @as(usize, @intCast(gwidth))) : (col += 1) {
            const dest_x: c_int = x_off + @as(c_int, @intCast(col));
            if (dest_x < 0 or dest_x >= @as(c_int, @intCast(width)))
                continue;

            const dest_x_u: usize = @intCast(dest_x);
            const out_idx = dest_y_u * @as(usize, @intCast(stride)) + dest_x_u;
            const a = alpha_buf[row * bmp_w + col];

            if (usebg) {
                dst[out_idx] = pack_pixel_bg(fg, bg, a);
            } else if (a != 0) {
                dst[out_idx] = pack_pixel(fg, a);
            }
        }
    }

    if (TTF_HANDLE_STYLE_BOLD(outf))
        xstart.* += @intCast(outf.glyph_overhang);

    prev_index.* = glyph_entry.index;
    return true;
}

// TTF_RenderUNICODEindex
export fn TTF_RenderUNICODEindex(
    dst: [*c]PIXEL,
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
    _: c_int, // style
    advance: [*c]c_int,
    prev_index: [*c]c_uint,
) callconv(.c) bool {
    const outf = TTF_FindGlyph(font, @intCast(n), ch, CACHED_METRICS | CACHED_PIXMAP, true) orelse return false;
    var pi: TrueType.GlyphIndex = @enumFromInt(@as(u16, @truncate(prev_index[0])));
    const result = render_unicode(
        dst,
        width,
        height,
        stride,
        font[0],
        outf,
        xstart,
        fg,
        bg,
        usebg,
        use_kerning,
        advance,
        &pi,
    );
    prev_index[0] = @intFromEnum(pi);
    return result;
}

// TTF_RenderUTF8chain
export fn TTF_RenderUTF8chain(
    dst: [*c]PIXEL,
    width: usize,
    height: usize,
    stride: c_int,
    font: [*c]?*TTF_Font,
    n: usize,
    intext: [*c]const u8,
    fg: [*c]u8,
    _: c_int, // style
) callconv(.c) bool {
    if (intext == null or intext[0] == 0)
        return true;

    const unicode_len: c_int = @intCast(do_strlen(intext));
    size_upool(unicode_len + 1);
    const text = unicode_buf orelse return false;
    _ = UTF8_to_UTF32(text, intext, @intCast(unicode_len));

    var xstart: c_uint = 0;
    var prev_index: TrueType.GlyphIndex = .notdef;

    const font0 = font[0] orelse return false;
    const font0_internal = font0.font orelse return false;
    const use_kerning = font0_internal.kerning != 0;

    var ch = text;
    while (ch[0] != 0) : (ch += 1) {
        var adv: c_int = 0;

        const outf = TTF_FindGlyph(font, @intCast(n), ch[0], CACHED_METRICS | CACHED_PIXMAP, false) orelse continue;

        _ = render_unicode(
            dst,
            width,
            height,
            stride,
            font0,
            outf,
            &xstart,
            fg,
            fg,
            false,
            use_kerning,
            &adv,
            &prev_index,
        );

        xstart +%= @intCast(adv);
    }
    return true;
}

// TTF_GetFontStyle
export fn TTF_GetFontStyle(font_ref: ?*const TTF_Font) callconv(.c) c_int {
    const fr = font_ref orelse return 0;
    const font = fr.font orelse return 0;
    return font.style;
}

// TTF_SetFontOutline
export fn TTF_SetFontOutline(font_ref: ?*TTF_Font, outline: c_int) callconv(.c) void {
    const fr = font_ref orelse return;
    const font = fr.font orelse return;
    if (font.outline == outline)
        return;

    if (fr.cache_entry) |entry| {
        var template = font.*;
        template.outline = outline;
        const fork = TTF_FindOrForkCachedFont(entry, &template) orelse return;
        fr.font = fork.font;
        fr.cache_entry = fork;
    }

    if (fr.font) |f| {
        if (f.outline != outline) {
            f.outline = outline;
            TTF_Flush_Cache(fr);
        }
    }
}

// TTF_GetFontOutline
export fn TTF_GetFontOutline(font_ref: ?*const TTF_Font) callconv(.c) c_int {
    const fr = font_ref orelse return 0;
    const font = fr.font orelse return 0;
    return font.outline;
}

// TTF_SetFontHinting
// TrueType.zig has no hinting — we store the preference but it's a no-op
export fn TTF_SetFontHinting(font_ref: ?*TTF_Font, hinting: c_int) callconv(.c) void {
    const fr = font_ref orelse return;
    const font = fr.font orelse return;

    if (font.hinting == hinting)
        return;

    if (fr.cache_entry) |entry| {
        var template = font.*;
        template.hinting = hinting;
        const fork = TTF_FindOrForkCachedFont(entry, &template) orelse return;
        fr.font = fork.font;
        fr.cache_entry = fork;
    }

    if (fr.font) |f| {
        if (f.hinting != hinting) {
            f.hinting = hinting;
            TTF_Flush_Cache(fr);
        }
    }
}

// TTF_GetFontHinting
export fn TTF_GetFontHinting(_: ?*const TTF_Font) callconv(.c) c_int {
    return TTF_HINTING_NONE; // TrueType.zig does not hint
}

// TTF_Quit
export fn TTF_Quit() callconv(.c) void {
    if (TTF_initialized != 0) {
        TTF_initialized -= 1;
    }
}

// TTF_WasInit
export fn TTF_WasInit() callconv(.c) c_int {
    return TTF_initialized;
}

// TTF_GetFontKerningSize
export fn TTF_GetFontKerningSize(font_ref: ?*TTF_Font, prev_idx: c_int, idx: c_int) callconv(.c) c_int {
    const fr = font_ref orelse return 0;
    const font = fr.font orelse return 0;
    // bug 0031: pointer-bind into font.tt to avoid the rvalue-copy
    // slice-header staleness that crashes on cmap reads.
    const tt: *const TrueType = if (font.tt) |*t| t else return 0;
    if (!tt_slice_looks_sane(font, tt)) return 0;
    const a: TrueType.GlyphIndex = @enumFromInt(@as(u16, @intCast(prev_idx)));
    const b_idx: TrueType.GlyphIndex = @enumFromInt(@as(u16, @intCast(idx)));
    const kern = tt.glyphKernAdvance(a, b_idx);
    return @intFromFloat(@round(@as(f32, @floatFromInt(kern)) * font.scale));
}

// TTF_ProbeFont
export fn TTF_ProbeFont(font_ref: ?*TTF_Font, dw: *usize, dh: *usize) callconv(.c) void {
    const fr = font_ref orelse return;
    const font = fr.font orelse return;

    if (font.cached_width > 0 and font.cached_height > 0) {
        dw.* = @intCast(font.cached_width);
        dh.* = @intCast(font.cached_height);
        return;
    }

    // Derive cell dimensions directly from font metrics.
    // Width: advance width of 'M' — all glyphs share the same advance in monospace.
    // Height: font.height (ascent - descent + 1), computed at font open time.
    // bug 0031: pointer-bind into font.tt to avoid the rvalue-copy
    // slice-header staleness; @panic kept for the truly-null case.
    const tt: *const TrueType = if (font.tt) |*t| t else @panic("TTF_ProbeFont: font.tt is null");
    if (!tt_slice_looks_sane(font, tt)) @panic("TTF_ProbeFont: font.tt slice corrupt — see trace bus");
    const gi = tt.codepointGlyphIndex('M');
    const hm = tt.glyphHMetrics(gi);
    const adv_w: usize = @intFromFloat(@round(@as(f32, @floatFromInt(hm.advance_width)) * font.scale));

    if (adv_w == 0) @panic("TTF_ProbeFont: advance_width * scale == 0");
    if (font.height <= 0) @panic("TTF_ProbeFont: font.height <= 0");
    if (font.scale == 0) @panic("TTF_ProbeFont: font.scale == 0");

    dw.* = adv_w;
    dh.* = @intCast(font.height);

    font.cached_width = @intCast(dw.*);
    font.cached_height = @intCast(dh.*);
}

// ════════════════════════════════════════════════════════════════════════
// GPU Glyph Atlas — Slug algorithm curve/band data management
// ════════════════════════════════════════════════════════════════════════
//
// Provides C-ABI functions for arcan_raster.zig to look up glyph curve data.
// Manages a global atlas of curve/band textures for all cached glyphs.
// The Vulkan backend uploads these textures once and references them per-glyph.

const slug = @import("slug_glyph.zig");

/// Per-glyph atlas entry: location in the global curve/band textures.
const GlyphAtlasEntry = struct {
    /// Identity: codepoint + font pointer hash for collision detection
    codepoint: u32,
    font_hash: usize,
    /// Band transform: maps em-space coord to band index
    band_transform: [4]f32, // scale.x, scale.y, offset.x, offset.y
    /// Glyph data: location in band texture + band counts
    glyph_data: [4]i32, // loc.x, loc.y, bandMaxX, bandMaxY
    /// Em-space bounding box (for vertex shader UV mapping)
    em_min: [2]f32,
    em_max: [2]f32,
    /// Offset into global curve/band arrays
    curve_offset: u32, // texel offset in global curve texture
    band_offset: u32, // texel offset in global band texture
    /// Sizes for this glyph's data
    num_curve_texels: u32,
    num_band_texels: u32,
    /// SDF atlas region — pixel position + size in persistent SDF atlas
    sdf_atlas_x: u16 = 0,
    sdf_atlas_y: u16 = 0,
    sdf_atlas_w: u16 = 0,
    sdf_atlas_h: u16 = 0,
    sdf_sample_count: u16 = 0, // frames accumulated (0 = not in atlas)
};

/// Returned to arcan_raster.zig via C ABI — the fields needed per instance.
const GlyphInstanceData = extern struct {
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

const ATLAS_CACHE_SIZE: usize = 16384;
const ATLAS_CURVE_TEX_WIDTH: u32 = 4096;
const ATLAS_BAND_TEX_WIDTH: u32 = 4096;
const MAX_CURVE_TEXELS: u32 = 4096 * 256; // 256 rows
const MAX_BAND_TEXELS: u32 = 4096 * 256;

/// Global atlas state
var atlas_initialized: bool = false;
var atlas_cache: [ATLAS_CACHE_SIZE]?GlyphAtlasEntry = [_]?GlyphAtlasEntry{null} ** ATLAS_CACHE_SIZE;
var atlas_curve_data: ?[]f32 = null; // RGBA f32 per texel, length = texels * 4
var atlas_band_data: ?[]u16 = null; // RGBA u16 per texel, length = texels * 4
var atlas_curve_offset: u32 = 0; // next free texel in curve texture
var atlas_band_offset: u32 = 0; // next free texel in band texture
var atlas_dirty: bool = false; // true when new glyphs added since last upload

// SDF atlas region allocator (row-packing)
const SDF_ATLAS_SIZE: u32 = 4096;
var sdf_next_x: u16 = 0;
var sdf_next_y: u16 = 0;
var sdf_row_height: u16 = 0;

/// Allocate a region in the SDF atlas using row-packing.
/// Returns (x, y) position or null if atlas is full.
const SdfAtlasRegion = struct { x: u16, y: u16 };

fn sdfAtlasAlloc(w: u16, h: u16) ?SdfAtlasRegion {
    if (w == 0 or h == 0) return null;
    // Try placing at current position
    if (sdf_next_x + w > SDF_ATLAS_SIZE) {
        // Move to next row
        sdf_next_x = 0;
        sdf_next_y += sdf_row_height;
        sdf_row_height = 0;
    }
    if (sdf_next_y + h > SDF_ATLAS_SIZE) return null; // atlas full
    const result = SdfAtlasRegion{ .x = sdf_next_x, .y = sdf_next_y };
    sdf_next_x += w;
    sdf_row_height = @max(sdf_row_height, h);
    return result;
}

fn atlasInit() void {
    if (atlas_initialized) return;
    atlas_initialized = true;

    // Allocate global texture data buffers
    atlas_curve_data = gpa.alloc(f32, MAX_CURVE_TEXELS * 4) catch {
        return;
    };
    atlas_band_data = gpa.alloc(u16, MAX_BAND_TEXELS * 4) catch {
        if (atlas_curve_data) |cd| gpa.free(cd);
        atlas_curve_data = null;
        return;
    };

    // Zero-fill
    if (atlas_curve_data) |cd| @memset(cd, 0);
    if (atlas_band_data) |bd| @memset(bd, 0);

}

/// Look up or create atlas entry for a glyph.
/// font_ptr: opaque pointer to TTF_Font_Internal
/// codepoint: Unicode codepoint
fn atlasLookup(font_ptr: *anyopaque, codepoint: u32) ?*const GlyphAtlasEntry {
    atlasInit();

    // bug 0114 instrumentation: atlas_*_data null after atlasInit() means
    // atlasInit's allocations failed. This was previously a silent return
    // null — every glyph from then on rendered blank with no log. Panic
    // so allocation failures during the live "fonts disappear" repro
    // pinpoint themselves.
    const curve_buf = atlas_curve_data orelse {
        std.debug.panic("[atlas init failed] atlas_curve_data is null after atlasInit() — gpa.alloc returned null", .{});
    };
    const band_buf = atlas_band_data orelse {
        std.debug.panic("[atlas init failed] atlas_band_data is null after atlasInit() — gpa.alloc returned null", .{});
    };

    // bug 0116 ROOT-CAUSE FIX: hash by the underlying TTF_Font_Internal
    // pointer, NOT the c_font_ref wrapper.
    //
    // TTF_OpenFontFD allocates a fresh c_font_ref struct on every call,
    // even when the underlying font (keyed by dev/ino in the c_font
    // cache) is shared. A single fontgroup_replace per terminal therefore
    // hands `drawglyph` a brand-new wrapper pointer for the *same*
    // physical font — every wrapper produces a distinct atlas key, the
    // cache pretends to be cold for every glyph the engine has already
    // rasterized, and the cache_entry that *was* populated for the prior
    // wrapper just sits there occupying slots until its hash chain gets
    // evicted by collision.
    //
    // Combined with tui_raster_setfont's "removed" branch (bug 0115),
    // this is what made multi-terminal sessions look like the atlas
    // kept losing characters: every fontgroup_replace produced a new
    // wrapper, the old wrapper's c_font_ref was closed, and
    // slug_atlas_invalidate wiped the global atlas. Hashing by the
    // shared internal font (`font_ref.font`, deduped by inode in
    // TTF_FindOrForkCachedFont) means a re-pushed font fd reuses the
    // existing atlas entries instead of creating shadow keys, so the
    // wrapper churn stops mattering.
    //
    // Resolve the wrapper first so we can hash by the shared font.
    // Pre-existing race-detect panic (font_ref.font == null) stays.
    const font_ref: *TTF_Font = @ptrCast(@alignCast(font_ptr));
    const font: *TTF_Font_Internal = font_ref.font orelse {
        // Caller handed us a TTF_Font_Public whose .font field is null.
        // This was the failure shape that landed glyphs as blank during
        // the bug 0031 family — render path racing against TTF_CloseFont's
        // ref_count==0 branch which clears font_ref.font. Panic so the
        // backtrace pins the race.
        std.debug.panic("[font race] font_ref.font is null — TTF_Font_Public was closed while still referenced by render path (font_ptr=0x{x} cp=U+{X:0>4})", .{ @intFromPtr(font_ptr), codepoint });
    };
    const font_hash = @intFromPtr(font);
    const hash: usize = (@as(usize, codepoint) *% 2654435761 +% font_hash) % ATLAS_CACHE_SIZE;

    // Cache hit? Validate identity to detect hash collisions.
    if (atlas_cache[hash]) |*entry| {
        if (entry.codepoint == codepoint and entry.font_hash == font_hash) {
            return entry;
        }
        // Hash collision — evict. With 16384 slots and a shared-by-inode
        // hash, the typical working set is tiny so collisions are rare.
        atlas_cache[hash] = null;
    }
    // bug 0009: must take a pointer into the optional's actual storage,
    // not into a stack-temp copy of its payload.  `&(font.tt orelse …)`
    // and `&font.tt.?` BOTH go through an rvalue copy — the slice
    // header (ttf_bytes) inside the copy becomes dangling once the
    // temporary's stack slot is reused.  `if (font.tt) |*t|` binds `t`
    // as `*TrueType` pointing into font.tt's storage, durable as long
    // as `font` lives.
    const tt: *const TrueType = if (font.tt) |*t| t else {
        std.debug.panic("[font race] font.tt is null — TTF_Font_Internal was poisoned (TTF_CloseFontInternal path) while atlas lookup in flight (font_ptr=0x{x} cp=U+{X:0>4})", .{ font_hash, codepoint });
    };
    if (!tt_slice_looks_sane(font, tt)) return null;

    if (codepoint > 0x10FFFF) return null;
    const glyph_index = tt.codepointGlyphIndex(@intCast(codepoint));
    if (glyph_index == .notdef) {
        // Legitimate: this font does not contain the codepoint. Caller
        // walks the fallback chain. NOT a panic.
        return null;
    }

    // Extract curves from TrueType outline.
    //
    // GlyphNotFound is *legitimate*: TrueType.glyfOffset returns it when
    // loca[i] == loca[i+1] (zero-outline glyph — the standard TTF
    // convention for whitespace; see TrueType.zig:1070 + the explicit
    // "// e.g. space character" comment at 1090). cmap routes U+0020 to
    // such an entry and we'd otherwise panic on every space ever
    // rendered, which is precisely the "fonts disappear" repro
    // (live arcan PID 256420 panic 19:16:20 was U+0020 / gi=821).
    // Return null so the caller skips raster — no fallback needed.
    //
    // Other errors (OutOfMemory, the various charstring stack errors)
    // are real structural failures — panic to keep them visible.
    const vertices = tt.glyphShape(gpa, glyph_index) catch |err| switch (err) {
        error.GlyphNotFound => return null,
        else => std.debug.panic("[glyph extract] glyphShape failed: {} (font_ptr=0x{x} cp=U+{X:0>4} gi={})", .{ err, font_hash, codepoint, @intFromEnum(glyph_index) }),
    };
    defer gpa.free(vertices);

    const curves = slug.extractCurves(gpa, vertices) catch |err| {
        std.debug.panic("[glyph extract] slug.extractCurves failed: {} (font_ptr=0x{x} cp=U+{X:0>4} verts={d})", .{ err, font_hash, codepoint, vertices.len });
    };
    defer gpa.free(curves);

    if (curves.len == 0) {
        // A glyph with notdef-not-set but zero curves is degenerate:
        // either legitimately empty (similar to GlyphNotFound space) or
        // slug.extractCurves dropped a real glyph (compound recursion?).
        // Log codepoint + font_ptr so the next missing-char repro names
        // the offending entries — this is bug 0115's partial-loss
        // follow-up, NOT a panic site since some empties are legitimate.
        const Once = struct { var seen: [128]u32 = [_]u32{0} ** 128; var n: usize = 0; };
        var dup = false;
        for (Once.seen[0..Once.n]) |seen_cp| if (seen_cp == codepoint) { dup = true; break; };
        if (!dup and Once.n < Once.seen.len) {
            Once.seen[Once.n] = codepoint;
            Once.n += 1;
            arcan_warning(
                "[atlas miss] curves.len=0 (font_ptr=0x%lx cp=U+%04X gi=%u verts=%zu)\n",
                @as(c_ulong, font_hash), codepoint, @intFromEnum(glyph_index), vertices.len,
            );
        }
        return null;
    }

    // Determine band count based on complexity
    // More bands = finer spatial partitioning = better coverage accuracy at small sizes
    const num_bands: u16 = if (curves.len <= 4) 4 else if (curves.len <= 16) 8 else 12;

    var gpu_data = slug.buildGlyphGpuData(gpa, curves, num_bands, num_bands) catch |err| {
        std.debug.panic("[glyph extract] slug.buildGlyphGpuData failed: {} (font_ptr=0x{x} cp=U+{X:0>4} curves={d} bands={d})", .{ err, font_hash, codepoint, curves.len, num_bands });
    };
    defer gpu_data.deinit();

    // Atlas exhaustion is the live "fonts disappear" symptom: each new
    // TTF_Font (one per dup'd fd, one per terminal open/close cycle)
    // pushes a new (font_ptr, codepoint) hash into the atlas cache, but
    // atlas_curve_offset / atlas_band_offset are append-only — never
    // reclaimed when a font closes. After enough churn the offsets cross
    // MAX_CURVE_TEXELS / MAX_BAND_TEXELS and atlasLookup silently returns
    // null forever — every subsequent glyph renders blank with no log
    // and no crash. Per "asserts/panics when shit breaks": panic now so
    // the failure mode is loud and points at the eviction bug instead of
    // being a long-running mystery.
    if (atlas_curve_offset + gpu_data.num_curve_texels > MAX_CURVE_TEXELS) {
        std.debug.panic(
            "[atlas exhausted] curve buffer full: offset={d} + need={d} > MAX={d} (font_ptr=0x{x} codepoint=U+{X:0>4}) — fonts will silently disappear, eviction not implemented",
            .{ atlas_curve_offset, gpu_data.num_curve_texels, MAX_CURVE_TEXELS, font_hash, codepoint },
        );
    }
    if (atlas_band_offset + gpu_data.num_band_texels > MAX_BAND_TEXELS) {
        std.debug.panic(
            "[atlas exhausted] band buffer full: offset={d} + need={d} > MAX={d} (font_ptr=0x{x} codepoint=U+{X:0>4}) — fonts will silently disappear, eviction not implemented",
            .{ atlas_band_offset, gpu_data.num_band_texels, MAX_BAND_TEXELS, font_hash, codepoint },
        );
    }

    // Copy curve data into global buffer
    const curve_start = atlas_curve_offset * 4;
    const curve_len = gpu_data.num_curve_texels * 4;
    @memcpy(curve_buf[curve_start..][0..curve_len], gpu_data.curve_data[0..curve_len]);

    // Copy band data into global buffer
    // Band data has internal offsets (list_offset) relative to glyph start.
    // We need to adjust these offsets to be relative to the global band texture.
    const band_start = atlas_band_offset * 4;
    const band_len = gpu_data.num_band_texels * 4;
    @memcpy(band_buf[band_start..][0..band_len], gpu_data.band_data[0..band_len]);

    // Compute glyph bounding box in em-space
    var bbox_min_x: f32 = std.math.inf(f32);
    var bbox_min_y: f32 = std.math.inf(f32);
    var bbox_max_x: f32 = -std.math.inf(f32);
    var bbox_max_y: f32 = -std.math.inf(f32);
    for (curves) |crv| {
        bbox_min_x = @min(bbox_min_x, crv.minX());
        bbox_min_y = @min(bbox_min_y, crv.minY());
        bbox_max_x = @max(bbox_max_x, crv.maxX());
        bbox_max_y = @max(bbox_max_y, crv.maxY());
    }

    // The glyph_data.xy encodes the texel location in the band texture.
    // The band texture coordinates are: x = texel % ATLAS_BAND_TEX_WIDTH, y = texel / ATLAS_BAND_TEX_WIDTH
    const band_loc_x: i32 = @intCast(atlas_band_offset % ATLAS_BAND_TEX_WIDTH);
    const band_loc_y: i32 = @intCast(atlas_band_offset / ATLAS_BAND_TEX_WIDTH);

    // Curve texture offset: the band data's curve list entries reference curve texels.
    // These offsets are relative to the glyph's curve start, so we need to store
    // the curve_offset for later. The shader fetches curves by absolute texel coords.
    // For now, the curve_data texel coords in band_data are relative to (0,0).
    // We need the shader to add curve_offset to those coords.
    // Since the shader uses absolute coords (curveLoc from band data), the band data's
    // curve references need to point to the absolute location in the curve texture.
    // The buildGlyphGpuData creates band_data with curve references starting at texel 0.
    // We need to offset those by atlas_curve_offset.
    //
    // Band data format: each curve list entry is (curve_texel_x, curve_texel_y, 0, 0) in u16.
    // The curve texels are laid out linearly starting at atlas_curve_offset.
    // We need to add atlas_curve_offset to each curve reference's (x,y) -> linear position,
    // then convert back to (x,y) in the ATLAS_CURVE_TEX_WIDTH grid.
    //
    // Actually, looking at the shader: curveLoc = ivec2(texelFetch(bandTexture, ...).xy)
    // Then: texelFetch(curveTexture, curveLoc, 0)
    // So curveTexture is addressed by (x,y) texel coordinates.
    // The curve data is stored linearly, so texel N is at (N % width, N / width).
    //
    // Fix up curve references in the band data:
    const total_bands = @as(u32, num_bands) + @as(u32, num_bands);
    // Curve list entries start after the band headers
    var i: u32 = total_bands;
    while (i < gpu_data.num_band_texels) : (i += 1) {
        const idx = (atlas_band_offset + i) * 4;
        // Read original curve texel coords (relative to glyph start at texel 0)
        const orig_x: u32 = band_buf[idx];
        const orig_y: u32 = band_buf[idx + 1];
        // Note: do NOT skip (0,0) entries — curve index 0 is valid!
        // The band_data is pre-zeroed and unused entries stay (0,0,0,0),
        // but we only iterate up to num_band_texels, so no padding issue.
        // Convert to linear index, add global offset, convert back to 2D
        const orig_linear = orig_y * ATLAS_CURVE_TEX_WIDTH + orig_x;
        const new_linear = orig_linear + atlas_curve_offset;
        band_buf[idx] = @intCast(new_linear % ATLAS_CURVE_TEX_WIDTH);
        band_buf[idx + 1] = @intCast(new_linear / ATLAS_CURVE_TEX_WIDTH);
    }

    // Also fix up band header offsets (list_offset field)
    // Band headers: each is (curve_count, list_offset, 0, 0)
    // list_offset is relative to glyph_loc, which we'll set to atlas_band_offset
    // So list_offset doesn't need adjustment — it's relative to glyph_loc.xy

    // Compute glyph bounding box from curve control points.
    // Used to expand em_min/em_max so no curve edge gets clipped.
    var glyph_bb_min_x: f32 = std.math.inf(f32);
    var glyph_bb_max_x: f32 = -std.math.inf(f32);
    var glyph_bb_min_y: f32 = std.math.inf(f32);
    var glyph_bb_max_y: f32 = -std.math.inf(f32);
    for (curves) |crv| {
        glyph_bb_min_x = @min(glyph_bb_min_x, @min(crv.p1[0], @min(crv.p2[0], crv.p3[0])));
        glyph_bb_max_x = @max(glyph_bb_max_x, @max(crv.p1[0], @max(crv.p2[0], crv.p3[0])));
        glyph_bb_min_y = @min(glyph_bb_min_y, @min(crv.p1[1], @min(crv.p2[1], crv.p3[1])));
        glyph_bb_max_y = @max(glyph_bb_max_y, @max(crv.p1[1], @max(crv.p2[1], crv.p3[1])));
    }

    const entry = GlyphAtlasEntry{
        .codepoint = codepoint,
        .font_hash = font_hash,
        .band_transform = if (gpu_data.is_rect)
            // Rectangle fast-path: repurpose band_transform to carry
            // (min_x, min_y, max_x, max_y) in em-space for box SDF.
            .{
                gpu_data.curve_data[0], // min_x
                gpu_data.curve_data[1], // min_y
                gpu_data.curve_data[2], // max_x
                gpu_data.curve_data[3], // max_y
            }
        else
            .{
                gpu_data.band_scale[0],
                gpu_data.band_scale[1],
                gpu_data.band_offset[0],
                gpu_data.band_offset[1],
            },
        .glyph_data = .{
            band_loc_x,
            band_loc_y,
            @as(i32, gpu_data.band_max_x),
            @as(i32, gpu_data.band_max_y) | if (gpu_data.is_rect) @as(i32, 0x100) else @as(i32, 0),
        },
        // Simple em range: cell_dim / font.scale with symmetric padding.
        // This is the original formula that works correctly at all font sizes.
        .em_min = .{
            blk: {
                const adv = @as(f32, @floatFromInt(tt.glyphHMetrics(glyph_index).advance_width));
                const cell_x_em = @as(f32, @floatFromInt(font.cached_width)) / font.scale;
                const x_pad = (cell_x_em - adv) / 2.0;
                break :blk -x_pad;
            },
            blk: {
                const vm = tt.verticalMetrics();
                const asc = @as(f32, @floatFromInt(vm.ascent));
                const desc = @as(f32, @floatFromInt(vm.descent));
                const cell_em = @as(f32, @floatFromInt(font.cached_height)) / font.scale;
                const font_em = asc - desc;
                const pad = (cell_em - font_em) / 2.0;
                break :blk desc - pad;
            },
        },
        .em_max = .{
            blk: {
                const adv = @as(f32, @floatFromInt(tt.glyphHMetrics(glyph_index).advance_width));
                const cell_x_em = @as(f32, @floatFromInt(font.cached_width)) / font.scale;
                const x_pad = (cell_x_em - adv) / 2.0;
                break :blk adv + x_pad;
            },
            blk: {
                const vm = tt.verticalMetrics();
                const asc = @as(f32, @floatFromInt(vm.ascent));
                const desc = @as(f32, @floatFromInt(vm.descent));
                const cell_em = @as(f32, @floatFromInt(font.cached_height)) / font.scale;
                const font_em = asc - desc;
                const pad = (cell_em - font_em) / 2.0;
                break :blk asc + pad;
            },
        },
        .curve_offset = atlas_curve_offset,
        .band_offset = atlas_band_offset,
        .num_curve_texels = gpu_data.num_curve_texels,
        .num_band_texels = gpu_data.num_band_texels,
    };

    atlas_curve_offset += gpu_data.num_curve_texels;
    atlas_band_offset += gpu_data.num_band_texels;
    atlas_dirty = true;

    // Assign SDF atlas region for this glyph (cell_w x cell_h pixels)
    // Use override dimensions if set (for multi-size ADMM calibration)
    var sdf_entry = entry;
    const cell_w: u16 = if (sdf_cell_override_w > 0) sdf_cell_override_w else @intCast(font.cached_width);
    const cell_h: u16 = if (sdf_cell_override_h > 0) sdf_cell_override_h else @intCast(font.cached_height);
    // Detect cell size changes — should trigger atlas invalidation
    const CS = struct { var prev_w: u16 = 0; var prev_h: u16 = 0; };
    if (CS.prev_w != 0 and (CS.prev_w != cell_w or CS.prev_h != cell_h)) {
    }
    CS.prev_w = cell_w;
    CS.prev_h = cell_h;
    if (sdfAtlasAlloc(cell_w, cell_h)) |region| {
        sdf_entry.sdf_atlas_x = region.x;
        sdf_entry.sdf_atlas_y = region.y;
        sdf_entry.sdf_atlas_w = cell_w;
        sdf_entry.sdf_atlas_h = cell_h;
        sdf_entry.sdf_sample_count = 0;
    }

    atlas_cache[hash] = sdf_entry;

    const S = struct { var logged: u32 = 0; };
    if (S.logged < 3) {
        S.logged += 1;
        // Dump gpu_data directly (before deferred free)
        const max_dump_bands = @min(3, @as(usize, num_bands));
        const max_band_idx = gpu_data.num_band_texels;
        for (0..max_dump_bands) |bi| {
            if (bi * 4 + 1 < max_band_idx * 4) {
            }
        }
        if (gpu_data.num_curve_texels >= 2) {
        }
    }

    return &atlas_cache[hash].?;
}

// C-ABI exports for arcan_raster.zig

/// Look up glyph data for a codepoint. Returns instance data needed for GPU rendering.
/// font_ptr: opaque pointer from TuiFont.getTruetype()
export fn slug_atlas_lookup(
    font_ptr: ?*anyopaque,
    codepoint: u32,
    out: *GlyphInstanceData,
) void {
    out.valid = false;
    const fp = font_ptr orelse {
        // bug 0115 partial-loss tripwire: drawglyph passed a null font
        // pointer — fontgroup slot has font_data == null. Used to be a
        // silent return, leaving the cell blank without any signal.
        const Once = struct { var seen: [128]u32 = [_]u32{0} ** 128; var n: usize = 0; };
        var dup = false;
        for (Once.seen[0..Once.n]) |seen_cp| if (seen_cp == codepoint) { dup = true; break; };
        if (!dup and Once.n < Once.seen.len) {
            Once.seen[Once.n] = codepoint;
            Once.n += 1;
            arcan_warning(
                "[atlas miss] slug_atlas_lookup: null font_ptr (cp=U+%04X) — fontgroup slot has font_data=null\n",
                codepoint,
            );
        }
        return;
    };
    const entry = atlasLookup(fp, codepoint) orelse return;

    out.em_min = entry.em_min;
    out.em_max = entry.em_max;
    out.band_transform = entry.band_transform;
    out.glyph_data = entry.glyph_data;
    out.valid = true;
    out.sdf_atlas_x = entry.sdf_atlas_x;
    out.sdf_atlas_y = entry.sdf_atlas_y;
    out.sdf_atlas_w = entry.sdf_atlas_w;
    out.sdf_atlas_h = entry.sdf_atlas_h;
    out.sdf_sample_count = entry.sdf_sample_count;
}

/// Get the global curve texture data for upload to GPU.
/// Returns pointer to RGBA f32 data and the number of texels used.
export fn slug_atlas_get_curve_data(
    out_texels: *u32,
    out_width: *u32,
) ?[*]const f32 {
    out_texels.* = atlas_curve_offset;
    out_width.* = ATLAS_CURVE_TEX_WIDTH;
    return if (atlas_curve_data) |cd| cd.ptr else null;
}

/// Get the global band texture data for upload to GPU.
/// Returns pointer to RGBA u16 data and the number of texels used.
export fn slug_atlas_get_band_data(
    out_texels: *u32,
    out_width: *u32,
) ?[*]const u16 {
    out_texels.* = atlas_band_offset;
    out_width.* = ATLAS_BAND_TEX_WIDTH;
    return if (atlas_band_data) |bd| bd.ptr else null;
}

/// Check if atlas has new data since last upload.
export fn slug_atlas_is_dirty() bool {
    return atlas_dirty;
}

/// Mark atlas as uploaded (clear dirty flag).
export fn slug_atlas_mark_clean() void {
    atlas_dirty = false;
}

/// Increment SDF sample counts for all cached glyphs (call once per frame).
/// At frame 16, jump to 255 (converged sentinel) — no more accumulation needed.
export fn slug_atlas_increment_sample_counts() void {
    for (&atlas_cache) |*entry_opt| {
        if (entry_opt.*) |*entry| {
            if (entry.sdf_sample_count < 255) {
                entry.sdf_sample_count += 1;
                if (entry.sdf_sample_count >= 16) {
                    entry.sdf_sample_count = 255; // frozen
                }
            }
        }
    }
}

/// SDF atlas diagnostics — written to by slug_atlas_get_sdf_stats.
const SdfStats = extern struct {
    total_glyphs: u32,    // entries in atlas cache
    converged: u32,       // sample_count >= 16
    max_sample_count: u16,
    min_sample_count: u16,
    sdf_alloc_x: u16,    // current allocator position
    sdf_alloc_y: u16,
};

/// SDF atlas entry info for dump — returned by slug_atlas_iter_sdf.
const SdfEntryInfo = extern struct {
    codepoint: u32,
    sdf_x: u16,
    sdf_y: u16,
    sdf_w: u16,
    sdf_h: u16,
    sample_count: u16,
};

/// Iterate all atlas entries with SDF regions. Returns count written to out array.
export fn slug_atlas_iter_sdf(out: [*]SdfEntryInfo, max_entries: u32) u32 {
    var n: u32 = 0;
    for (atlas_cache) |entry_opt| {
        if (n >= max_entries) break;
        if (entry_opt) |entry| {
            if (entry.sdf_atlas_w > 0 and entry.sdf_atlas_h > 0) {
                out[n] = .{
                    .codepoint = entry.codepoint,
                    .sdf_x = entry.sdf_atlas_x,
                    .sdf_y = entry.sdf_atlas_y,
                    .sdf_w = entry.sdf_atlas_w,
                    .sdf_h = entry.sdf_atlas_h,
                    .sample_count = entry.sdf_sample_count,
                };
                n += 1;
            }
        }
    }
    return n;
}

/// Get current SDF atlas statistics for diagnostics.
export fn slug_atlas_get_sdf_stats(out: *SdfStats) void {
    var total: u32 = 0;
    var converged: u32 = 0;
    var max_sc: u16 = 0;
    var min_sc: u16 = 255;
    for (atlas_cache) |entry_opt| {
        if (entry_opt) |entry| {
            total += 1;
            if (entry.sdf_sample_count >= 255) converged += 1;
            max_sc = @max(max_sc, entry.sdf_sample_count);
            min_sc = @min(min_sc, entry.sdf_sample_count);
        }
    }
    out.* = .{
        .total_glyphs = total,
        .converged = converged,
        .max_sample_count = max_sc,
        .min_sample_count = if (total > 0) min_sc else 0,
        .sdf_alloc_x = sdf_next_x,
        .sdf_alloc_y = sdf_next_y,
    };
}

// bug 0117 / 0118 phase 1.4: gdb-attach equivalent for the slug
// atlas. Single struct snapshot of every global the bug 0116 hunt
// needed to read with `nm + gdb -batch -p PID`. Designed to be
// cheap (no iteration of atlas_cache; just direct loads), so the
// inside-arcan agent can poll it from a render-hot frame without
// stalling.
//
// For counted aggregates (cache occupancy, by-font breakdown) use
// slug_atlas_get_sdf_stats above — that walks the cache. This
// accessor is the "what's the writeable state" snapshot.
const SlugAtlasState = extern struct {
    curve_offset: u32,
    band_offset: u32,
    max_curve_texels: u32,
    max_band_texels: u32,
    cache_size: u32,
    sdf_next_x: u16,
    sdf_next_y: u16,
    sdf_row_height: u16,
    dirty: u8,
    initialized: u8,
};

export fn slug_atlas_get_state(out: *SlugAtlasState) void {
    out.* = .{
        .curve_offset = atlas_curve_offset,
        .band_offset = atlas_band_offset,
        .max_curve_texels = MAX_CURVE_TEXELS,
        .max_band_texels = MAX_BAND_TEXELS,
        .cache_size = ATLAS_CACHE_SIZE,
        .sdf_next_x = sdf_next_x,
        .sdf_next_y = sdf_next_y,
        .sdf_row_height = sdf_row_height,
        .dirty = if (atlas_dirty) 1 else 0,
        .initialized = if (atlas_initialized) 1 else 0,
    };
}

// STB reference atlas loader (on-disk, pre-generated)
// Format: STBA header (16B) + index (8B × N) + data (cell_w × cell_h × N)
// Generated offline by gen_stb_atlas.c, loaded at runtime for GPU comparison.

var stb_ref_buffer: ?[]u8 = null; // 4096×4096 R8, same layout as SDF atlas
var stb_atlas_loaded: bool = false;

const StbAtlasHeader = extern struct {
    magic: u32,     // 0x53544241 "STBA"
    version: u32,
    cell_w: u16,
    cell_h: u16,
    num_glyphs: u32,
};

const StbIndexEntry = extern struct {
    codepoint: u32,
    offset: u32,
};

/// Load pre-generated stb atlas and blit each glyph's reference data into
/// the stb_ref_buffer at the same atlas coordinates as the SDF atlas.
/// Called from vk_shared.zig after SDF atlas allocation is stable.
export fn slug_atlas_load_stb_ref(ptsize: u32) bool {
    // Allocate R8 buffer matching SDF atlas dimensions
    if (stb_ref_buffer == null) {
        stb_ref_buffer = gpa.alloc(u8, SDF_ATLAS_SIZE * SDF_ATLAS_SIZE) catch {
            return false;
        };
    }
    const buf = stb_ref_buffer.?;
    @memset(buf, 0);

    // Try to open the atlas file
    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "data/resources/fonts/stb_atlas_{d}px.bin", .{ptsize}) catch return false;
    const file = std.fs.cwd().openFile(path, .{}) catch {
        return false;
    };
    defer file.close();

    // Read entire file
    const file_size = file.getEndPos() catch return false;
    const file_data = gpa.alloc(u8, file_size) catch return false;
    defer gpa.free(file_data);
    const n_read = file.readAll(file_data) catch return false;
    if (n_read < @sizeOf(StbAtlasHeader)) return false;

    const hdr: StbAtlasHeader = @as(*const StbAtlasHeader, @ptrCast(@alignCast(file_data.ptr))).*;
    if (hdr.magic != 0x53544241) {
        return false;
    }

    const idx_start = @sizeOf(StbAtlasHeader);
    const idx_size = @as(usize, hdr.num_glyphs) * @sizeOf(StbIndexEntry);
    const data_start = idx_start + idx_size;
    if (data_start > file_data.len) return false;

    const index: [*]const StbIndexEntry = @ptrCast(@alignCast(file_data[idx_start..].ptr));
    const data_buf = file_data[data_start..];

    // For each glyph in our SDF atlas cache, find its stb data and blit
    var n_linked: u32 = 0;
    for (atlas_cache) |entry_opt| {
        const entry = entry_opt orelse continue;
        if (entry.sdf_atlas_w == 0 or entry.sdf_atlas_h == 0) continue;

        // Binary search for codepoint in stb index
        var lo: u32 = 0;
        var hi: u32 = hdr.num_glyphs;
        var found: bool = false;
        var stb_offset: u32 = 0;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (index[mid].codepoint < entry.codepoint) {
                lo = mid + 1;
            } else if (index[mid].codepoint > entry.codepoint) {
                hi = mid;
            } else {
                stb_offset = index[mid].offset;
                found = true;
                break;
            }
        }
        if (!found) continue;

        // Blit stb data into ref buffer at SDF atlas coordinates
        const src_w: u32 = @min(hdr.cell_w, entry.sdf_atlas_w);
        const src_h: u32 = @min(hdr.cell_h, entry.sdf_atlas_h);

        var row: u32 = 0;
        while (row < src_h) : (row += 1) {
            const src_off = stb_offset + row * hdr.cell_w;
            const dst_off = (@as(u32, entry.sdf_atlas_y) + row) * SDF_ATLAS_SIZE + @as(u32, entry.sdf_atlas_x);
            if (src_off + src_w <= data_buf.len and dst_off + src_w <= buf.len) {
                @memcpy(buf[dst_off..][0..src_w], data_buf[src_off..][0..src_w]);
            }
        }
        n_linked += 1;
    }

    stb_atlas_loaded = true;
    return true;
}

/// Get the stb reference buffer for GPU upload (R8, SDF_ATLAS_SIZE x SDF_ATLAS_SIZE).
export fn slug_atlas_get_stb_ref(out_w: *u32, out_h: *u32) ?[*]const u8 {
    out_w.* = SDF_ATLAS_SIZE;
    out_h.* = SDF_ATLAS_SIZE;
    return if (stb_ref_buffer) |b| b.ptr else null;
}

/// Check if stb reference atlas is loaded.
export fn slug_atlas_stb_loaded() bool {
    return stb_atlas_loaded;
}

// Multi-size STB reference storage (all 101 sizes 8-108px in RAM)

const STB_SIZE_MIN: u32 = 8;
const STB_SIZE_MAX: u32 = 108;
const STB_SIZE_COUNT: u32 = STB_SIZE_MAX - STB_SIZE_MIN + 1; // 101

const StbSizeEntry = struct {
    data: ?[]u8, // raw file contents
    header: StbAtlasHeader,
};

var stb_all_sizes: [STB_SIZE_COUNT]StbSizeEntry = [_]StbSizeEntry{.{
    .data = null,
    .header = .{ .magic = 0, .version = 0, .cell_w = 0, .cell_h = 0, .num_glyphs = 0 },
}} ** STB_SIZE_COUNT;
var stb_all_loaded: bool = false;

/// Load ALL stb atlas files (8-108px) into CPU RAM. ~123MB total.
export fn slug_atlas_load_all_stb_refs() bool {
    if (stb_all_loaded) return true;
    var n_loaded: u32 = 0;
    var total_bytes: usize = 0;

    for (STB_SIZE_MIN..STB_SIZE_MAX + 1) |ptsize| {
        const idx = ptsize - STB_SIZE_MIN;
        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "data/resources/fonts/stb_atlas_{d}px.bin", .{ptsize}) catch continue;
        const file = std.fs.cwd().openFile(path, .{}) catch continue;
        defer file.close();

        const file_size = file.getEndPos() catch continue;
        const file_data = gpa.alloc(u8, file_size) catch continue;
        const n_read = file.readAll(file_data) catch {
            gpa.free(file_data);
            continue;
        };
        if (n_read < @sizeOf(StbAtlasHeader)) {
            gpa.free(file_data);
            continue;
        }

        const hdr: StbAtlasHeader = @as(*const StbAtlasHeader, @ptrCast(@alignCast(file_data.ptr))).*;
        if (hdr.magic != 0x53544241) {
            gpa.free(file_data);
            continue;
        }

        stb_all_sizes[idx] = .{ .data = file_data, .header = hdr };
        n_loaded += 1;
        total_bytes += file_size;
    }

    stb_all_loaded = true;
    return n_loaded > 0;
}

/// Blit a specific size's STB reference into the shared stb_ref_buffer,
/// using the current SDF atlas layout. Returns true if any glyphs were linked.
export fn slug_atlas_blit_stb_for_size(ptsize: u32) bool {
    if (ptsize < STB_SIZE_MIN or ptsize > STB_SIZE_MAX) return false;
    const idx = ptsize - STB_SIZE_MIN;
    const entry = &stb_all_sizes[idx];
    const file_data = entry.data orelse return false;
    const hdr = entry.header;

    // Ensure buffer exists
    if (stb_ref_buffer == null) {
        stb_ref_buffer = gpa.alloc(u8, SDF_ATLAS_SIZE * SDF_ATLAS_SIZE) catch return false;
    }
    const buf = stb_ref_buffer.?;
    @memset(buf, 0);

    const idx_start = @sizeOf(StbAtlasHeader);
    const idx_size = @as(usize, hdr.num_glyphs) * @sizeOf(StbIndexEntry);
    const data_start = idx_start + idx_size;
    if (data_start > file_data.len) return false;

    const index: [*]const StbIndexEntry = @ptrCast(@alignCast(file_data[idx_start..].ptr));
    const data_buf = file_data[data_start..];

    var n_linked: u32 = 0;
    for (atlas_cache) |entry_opt| {
        const ae = entry_opt orelse continue;
        if (ae.sdf_atlas_w == 0 or ae.sdf_atlas_h == 0) continue;

        // Binary search for codepoint
        var lo: u32 = 0;
        var hi: u32 = hdr.num_glyphs;
        var found: bool = false;
        var stb_offset: u32 = 0;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (index[mid].codepoint < ae.codepoint) {
                lo = mid + 1;
            } else if (index[mid].codepoint > ae.codepoint) {
                hi = mid;
            } else {
                stb_offset = index[mid].offset;
                found = true;
                break;
            }
        }
        if (!found) continue;

        const src_w: u32 = @min(hdr.cell_w, ae.sdf_atlas_w);
        const src_h: u32 = @min(hdr.cell_h, ae.sdf_atlas_h);
        var row: u32 = 0;
        while (row < src_h) : (row += 1) {
            const src_off = stb_offset + row * hdr.cell_w;
            const dst_off = (@as(u32, ae.sdf_atlas_y) + row) * SDF_ATLAS_SIZE + @as(u32, ae.sdf_atlas_x);
            if (src_off + src_w <= data_buf.len and dst_off + src_w <= buf.len) {
                @memcpy(buf[dst_off..][0..src_w], data_buf[src_off..][0..src_w]);
            }
        }
        n_linked += 1;
    }

    stb_atlas_loaded = true;
    return n_linked > 0;
}

/// Get cell dimensions for a given point size (from loaded STB header).
export fn slug_atlas_get_stb_cell_size(ptsize: u32, out_w: *u16, out_h: *u16) bool {
    if (ptsize < STB_SIZE_MIN or ptsize > STB_SIZE_MAX) return false;
    const idx = ptsize - STB_SIZE_MIN;
    const hdr = stb_all_sizes[idx].header;
    if (hdr.magic != 0x53544241) return false;
    out_w.* = hdr.cell_w;
    out_h.* = hdr.cell_h;
    return true;
}

// Cell dimension override for multi-size ADMM calibration.
// When > 0, atlasLookup uses these instead of font.cached_width/height.
var sdf_cell_override_w: u16 = 0;
var sdf_cell_override_h: u16 = 0;
var sdf_scale_override: f32 = 0; // when > 0, replaces font.scale in em calculations

/// Set cell dimension and scale override for SDF atlas allocation.
/// ptsize=0 restores default behavior.
export fn slug_atlas_set_cell_override(w: u16, h: u16) void {
    sdf_cell_override_w = w;
    sdf_cell_override_h = h;
}

export fn slug_atlas_set_scale_override(scale: f32) void {
    sdf_scale_override = scale;
}

/// Compute the pixel scale for a given ptsize using the font's vertical metrics.
/// Returns scaleForPixelHeight(ptsize) = ptsize / (ascent - descent).
export fn slug_atlas_compute_scale(font_ptr: ?*anyopaque, ptsize: u32) f32 {
    const fp = font_ptr orelse return 0;
    const font_ref: *TTF_Font = @ptrCast(@alignCast(fp));
    const font: *TTF_Font_Internal = font_ref.font orelse return 0;
    const tt: *const TrueType = if (font.tt) |*t| t else return 0;
    if (!tt_slice_looks_sane(font, tt)) return 0;
    return tt.scaleForPixelHeight(@floatFromInt(ptsize));
}

/// Full atlas reset for multi-size calibration.
/// Clears cache, resets SDF allocator and curve/band offsets.
/// Next slug_atlas_lookup calls will re-extract curves and allocate fresh SDF regions.
export fn slug_atlas_reset_sdf() void {
    atlas_cache = [_]?GlyphAtlasEntry{null} ** ATLAS_CACHE_SIZE;
    atlas_curve_offset = 0;
    atlas_band_offset = 0;
    sdf_next_x = 0;
    sdf_next_y = 0;
    sdf_row_height = 0;
    atlas_dirty = true;
    if (atlas_curve_data) |cd| @memset(cd, 0);
    if (atlas_band_data) |bd| @memset(bd, 0);
}

/// Invalidate entire atlas — call when fonts change.
/// Clears cache and resets texture offsets. Next lookups will re-extract glyphs.
export fn slug_atlas_invalidate() void {
    atlas_cache = [_]?GlyphAtlasEntry{null} ** ATLAS_CACHE_SIZE;
    atlas_curve_offset = 0;
    atlas_band_offset = 0;
    atlas_dirty = true; // force texture re-upload
    if (atlas_curve_data) |cd| @memset(cd, 0);
    if (atlas_band_data) |bd| @memset(bd, 0);
    // Reset SDF atlas allocator
    sdf_next_x = 0;
    sdf_next_y = 0;
    sdf_row_height = 0;
}
