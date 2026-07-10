// Zig port of tui/widgets/linewnd.c
// All functions are stubs (unimplemented widget).

const c = @import("shmif_types");

export fn arcan_tui_linewnd_render(
    _: ?*c.struct_tui_context,
    _: [*c]c.struct_tui_linewnd_line,
    _: usize,
    _: usize,
    _: usize,
    _: usize,
    _: usize,
    _: [*c]usize,
    _: usize,
    _: c_int,
) usize {
    return 0;
}

export fn arcan_tui_linewnd_set_buffer(
    _: ?*c.struct_tui_context,
    _: [*c]c.struct_tui_linewnd_line,
    _: usize,
) void {}

export fn arcan_tui_linewnd_get_buffer(
    _: ?*c.struct_tui_context,
    _: [*c]c.struct_tui_linewnd_line,
    _: usize,
) usize {
    return 0;
}

export fn arcan_tui_linewnd_add_line(
    _: ?*c.struct_tui_context,
    _: [*c]const c.struct_tui_linewnd_line,
) void {}

export fn arcan_tui_linewnd_release(_: ?*c.struct_tui_context) void {}
