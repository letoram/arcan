// STB image extern declarations — dispatch module exposing the subset of
// stb_image / stb_image_write functions used by arcan_img.zig. The actual
// implementations live in src/engine/external/stb_image_impl.c (a single C
// TU that defines STB_IMAGE_IMPLEMENTATION / STB_IMAGE_WRITE_IMPLEMENTATION
// and #includes the header-only libraries). Binaries that compile this
// module must add that .c stub to their build so the extern references
// resolve at link time.
//
// The original @cImport pulled the STB headers with their implementation
// macros set — that's been replaced by the C-stub pattern used elsewhere in
// this tree (see src/a12/net/hashmap_impl.c for the prior example).

pub extern fn stbi_load_from_memory(
    buffer: [*c]const u8,
    len: c_int,
    x: *c_int,
    y: *c_int,
    channels_in_file: *c_int,
    desired_channels: c_int,
) [*c]u8;

pub extern fn stbi_image_free(retval_from_stbi_load: ?*anyopaque) void;

pub extern fn stbi_set_flip_vertically_on_load(flag_true_if_should_flip: c_int) void;

pub extern fn stbi_write_png_to_mem(
    pixels: [*c]const u8,
    stride_bytes: c_int,
    x: c_int,
    y: c_int,
    n: c_int,
    out_len: *c_int,
) [*c]u8;

// stb_image_write tunables — global c_ints declared in stb_image_write.h.
// The .c stub's STB_IMAGE_WRITE_IMPLEMENTATION emits storage for these; the
// extern decls below let Zig consumers read/write them without @cImport.
pub extern var stbi_write_png_compression_level: c_int;
pub extern var stbi_write_force_png_filter: c_int;
