// Hand-written replacement for vk.zig's @cImport (stdio + arcan_math/general/
// video/videoint). Only three names are actually referenced: `c.printf`,
// `c.struct_agp_fenv` (opaque, only used as pointer), and
// `c.struct_agp_render_options` (literal struct from agp_platform.h).

pub extern "c" fn printf(fmt: [*c]const u8, ...) c_int;

pub const struct_agp_fenv = opaque {};

// agp_platform.h: `struct agp_render_options { int line_width; };`
pub const struct_agp_render_options = extern struct {
    line_width: c_int,
};
