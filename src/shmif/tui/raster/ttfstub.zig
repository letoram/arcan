// Pure Zig port of tui/raster/ttfstub.c — stub TTF functions.
//
// Provides no-op implementations of the TTF calls so that TUI can be
// built without pulling in FreeType. Used when TUI is built with
// TUI_RASTER_NO_TTF (the arcan_tui library path; compositors use the
// real arcan_ttf.c instead).

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

// Opaque C types

const TTF_Font = opaque {};

// shmif_pixel = uint32_t; PIXEL = shmif_pixel when SHMIF_TTF is defined.
const PIXEL = u32;

// POSIX close

const posix = if (is_freestanding) struct {
    pub fn close(_: c_int) callconv(.c) c_int { return -1; }
} else struct {
    pub extern "c" fn close(fd: c_int) c_int;
};

// Stub implementations

export fn TTF_Init() callconv(.c) c_int {
    return 0;
}

export fn TTF_ProbeFont(_: ?*TTF_Font, dw: *usize, dh: *usize) callconv(.c) void {
    dw.* = 0;
    dh.* = 0;
}

/// Open font using a preexisting file descriptor, takes ownership of fd.
export fn TTF_OpenFontFD(fd: c_int, _: c_int, _: u16, _: u16) callconv(.c) ?*TTF_Font {
    _ = posix.close(fd);
    return null;
}

export fn TTF_CloseFont(_: ?*TTF_Font) callconv(.c) void {}

export fn TTF_FindGlyph(
    _: [*c]?*TTF_Font,
    _: c_int,
    _: u32,
    _: c_int,
    _: bool,
) callconv(.c) ?*TTF_Font {
    return null;
}

export fn TTF_RenderUNICODEglyph(
    _: [*c]PIXEL,
    _: usize,
    _: usize,
    _: c_int,
    _: [*c]?*TTF_Font,
    _: usize,
    _: u32,
    _: [*c]c_uint,
    _: [*c]u8,
    _: [*c]u8,
    _: bool,
    _: bool,
    _: c_int,
    _: [*c]c_int,
    _: [*c]c_uint,
) callconv(.c) bool {
    return false;
}

export fn TTF_SetFontHinting(_: ?*TTF_Font, _: c_int) callconv(.c) void {}

export fn TTF_SetFontStyle(_: ?*TTF_Font, _: c_int) callconv(.c) void {}

export fn TTF_FontStyle(_: ?*TTF_Font, _: c_int) callconv(.c) void {}

// Additional stubs for compositor (arcan_renderfun.zig)

export fn TTF_Quit() callconv(.c) void {}

export fn TTF_FontAscent(_: ?*TTF_Font) callconv(.c) c_int { return 0; }
export fn TTF_FontDescent(_: ?*TTF_Font) callconv(.c) c_int { return 0; }
export fn TTF_FontHeight(_: ?*TTF_Font) callconv(.c) c_int { return 0; }
export fn TTF_FontLineSkip(_: ?*TTF_Font) callconv(.c) c_int { return 0; }

export fn TTF_OpenFont(_: [*c]const u8, _: c_int, _: u16, _: u16) callconv(.c) ?*TTF_Font {
    return null;
}

export fn TTF_ReplaceFont(_: *?*TTF_Font, _: ?*TTF_Font) callconv(.c) void {}

export fn TTF_SizeUTF8chain(
    _: [*c]?*TTF_Font, _: usize, _: [*c]const u8,
    _: [*c]c_int, _: [*c]c_int, _: c_int,
) callconv(.c) c_int {
    return -1;
}

export fn TTF_RenderUTF8chain(
    _: [*c]PIXEL, _: usize, _: usize, _: c_int, _: c_int,
    _: [*c]?*TTF_Font, _: usize, _: [*c]const u8,
    _: c_uint, _: c_uint, _: c_int, _: c_int, _: bool,
) callconv(.c) c_int {
    return -1;
}

export fn UTF8_to_UTF32(_: [*c]const u8, _: [*c]u32) callconv(.c) c_int {
    return 0;
}
