// Pure Zig port of engine/arcan_img.c — zero C helpers.
// Image decode/encode: PNG/JPEG via stb_image. The stb_image /
// stb_image_write implementations come from the translated Zig file at
// src/engine/external/stb_image.zig (produced via `zig translate-c` on
// a shim that defines STB_IMAGE_IMPLEMENTATION /
// STB_IMAGE_WRITE_IMPLEMENTATION). Binaries linking this Zig file must
// also link that translated module's .o.
// On freestanding targets (bootstrap) no image decode/encode takes
// place; pure-stub shims are provided locally via `is_freestanding`.

const builtin = @import("builtin");
const libc = @import("posix");
const is_freestanding_img = (builtin.os.tag == .freestanding);

// Dispatch struct replacing the prior mix of local `extern fn` decls and
// ad-hoc C helpers. Each alias routes to the appropriate hand-written
// replacement module so call sites stay on the `c.X` / `stb.X` spellings.
const c = struct {
    // libc (stdio + mem)
    pub const fwrite = libc.fwrite;
    pub const memcpy = libc.memcpy;
    pub const strlen = libc.strlen;
};

const stb = if (is_freestanding_img) struct {
    pub fn stbi_load_from_memory(_: [*c]const u8, _: c_int, _: *c_int, _: *c_int, _: *c_int, _: c_int) callconv(.c) [*c]u8 { return null; }
    pub fn stbi_set_flip_vertically_on_load(_: c_int) callconv(.c) void {}
    pub fn stbi_write_png_to_mem(_: [*c]const u8, _: c_int, _: c_int, _: c_int, _: c_int, _: *c_int) callconv(.c) [*c]u8 { return null; }
} else struct {
    pub extern fn stbi_load_from_memory(
        buffer: [*c]const u8,
        len: c_int,
        x: *c_int,
        y: *c_int,
        channels_in_file: *c_int,
        desired_channels: c_int,
    ) [*c]u8;
    pub extern fn stbi_set_flip_vertically_on_load(flag_true_if_should_flip: c_int) void;
    pub extern fn stbi_write_png_to_mem(
        pixels: [*c]const u8,
        stride_bytes: c_int,
        x: c_int,
        y: c_int,
        n: c_int,
        out_len: *c_int,
    ) [*c]u8;
};

// Engine memory allocator
extern fn arcan_alloc_mem(sz: usize, memtype: c_int, hint: c_int, @"align": c_int) ?[*]u8;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;

const ARCAN_MEM_VBUFFER: c_int = 1;
const ARCAN_MEM_TEMPORARY: c_int = 2;
const ARCAN_MEM_NONFATAL: c_int = 8;
const ARCAN_MEMALIGN_PAGE: c_int = 1;

const ARCAN_OK: c_int = 0;
const ARCAN_ERRC_OUT_OF_SPACE: c_int = -6;
const ARCAN_ERRC_BAD_RESOURCE: c_int = -8;
const ARCAN_ERRC_UNSUPPORTED_FORMAT: c_int = -12;

export fn arcan_img_outpng(
    dst: *anyopaque,
    inbuf: [*c]u32,
    inw: usize,
    inh: usize,
    vflip: bool,
) c_int {
    var outbuf: [*]u8 = @ptrCast(inbuf);
    var dynout = false;

    if (vflip) {
        // Need row reversal
        const stride = inw * 4;
        const mem = arcan_alloc_mem(stride * inh, ARCAN_MEM_VBUFFER,
            ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE) orelse
            return ARCAN_ERRC_OUT_OF_SPACE;

        var step: usize = 0;
        var row: isize = @as(isize, @intCast(inh)) - 1;
        while (row >= 0) : ({
            row -= 1;
            step += 1;
        }) {
            const r: usize = @intCast(row);
            _ = c.memcpy(mem + step * stride, @as([*]const u8, @ptrCast(inbuf + r * inw)), stride);
        }
        outbuf = mem;
        dynout = true;
    }

    var outln: c_int = 0;
    const png = stb.stbi_write_png_to_mem(outbuf, 0, @intCast(inw), @intCast(inh), 4, &outln);
    if (outln > 0)
        _ = c.fwrite(png, 1, @intCast(outln), @ptrCast(dst));
    arcan_mem_free(png);
    if (dynout)
        arcan_mem_free(outbuf);
    return ARCAN_OK;
}

export fn arcan_img_repack(inbuf: [*c]u32, inw: usize, inh: usize) [*c]u32 {
    // av_pixel is always u32 (4 bytes) and RGBA byte order matches stbi — no repack needed
    _ = .{ inw, inh };
    return inbuf;
}

export fn arcan_pkm_raw(
    inbuf: [*c]const u8,
    inbuf_sz: usize,
    outbuf: *[*c]u32,
    outw: *usize,
    outh: *usize,
    meta: ?*anyopaque,
) c_int {
    _ = .{ inbuf, inbuf_sz, outbuf, outw, outh, meta };
    return ARCAN_ERRC_UNSUPPORTED_FORMAT;
}

export fn arcan_dds_raw(
    inbuf: [*c]const u8,
    inbuf_sz: usize,
    outbuf: *[*c]u32,
    outw: *usize,
    outh: *usize,
    meta: ?*anyopaque,
) c_int {
    _ = .{ inbuf, inbuf_sz, outbuf, outw, outh, meta };
    return ARCAN_ERRC_UNSUPPORTED_FORMAT;
}

var initialized = false;

export fn arcan_img_init() void {
    if (initialized) return;
    initialized = true;
}

fn endswith_ci(s: [*c]const u8, len: usize, needle: []const u8) bool {
    if (len < needle.len) return false;
    const start = len - needle.len;
    for (0..needle.len) |i| {
        const ch = s[start + i];
        const lower: u8 = if (ch >= 'A' and ch <= 'Z') ch + 32 else ch;
        if (lower != needle[i]) return false;
    }
    return true;
}

export fn arcan_img_decode(
    hint: [*c]const u8,
    inbuf: [*c]u8,
    inbuf_sz: usize,
    outbuf: *[*c]u32,
    outw: *usize,
    outh: *usize,
    meta: ?*anyopaque,
    vflip: bool,
) c_int {
    const len = c.strlen(hint);

    if (len >= 3) {
        if (endswith_ci(hint, len, "png") or
            endswith_ci(hint, len, "jpg") or
            (len >= 4 and endswith_ci(hint, len, "jpeg")))
        {
            var w: c_int = 0;
            var h: c_int = 0;
            var outf: c_int = 0;
            stb.stbi_set_flip_vertically_on_load(if (vflip) @as(c_int, 1) else @as(c_int, 0));
            const buf: [*c]u32 = @ptrCast(@alignCast(stb.stbi_load_from_memory(@ptrCast(inbuf), @intCast(inbuf_sz), &w, &h, &outf, 4)));
            if (buf != null) {
                outbuf.* = buf;
                outw.* = @intCast(w);
                outh.* = @intCast(h);
                return ARCAN_OK;
            }
        } else if (endswith_ci(hint, len, "pkm")) {
            return arcan_pkm_raw(@ptrCast(inbuf), inbuf_sz, outbuf, outw, outh, meta);
        } else if (endswith_ci(hint, len, "dds")) {
            return arcan_dds_raw(@ptrCast(inbuf), inbuf_sz, outbuf, outw, outh, meta);
        }
    }

    return ARCAN_ERRC_BAD_RESOURCE;
}
