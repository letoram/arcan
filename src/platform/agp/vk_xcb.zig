// AGP Vulkan Backend — XCB Window + Surface
// Creates an XCB window and VK_KHR_xcb_surface when DISPLAY is set.
// Falls back to VK_KHR_display (vk_wsi.zig) when running on bare TTY.
//
// On static musl builds, XCB and xkbcommon-x11 are loaded at runtime via
// zig_dlopen (which delegates to glibc's dlopen). This avoids a dual-xcb
// conflict where both the statically-compiled XCB and the Vulkan ICD's
// system libxcb.so would coexist and crash in xcb_query_tree.

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");

// The no-LLVM self-hosted fork can't run @cImport. xcb_cabi.zig and
// xkb_cabi.zig are pre-translated (stock LLVM zig + translate-c) of the
// same header sets. All types / constants / extern decls preserved
// verbatim — symbols link against the dl_xcb / dl_xkb runtime shims
// (or are dead-eliminated for the runtime-loaded paths guarded by
// use_zig_dlopen).
const xcb = @import("xcb_cabi.zig");
const xkb = @import("xkb_cabi.zig");

// Runtime XCB loading (static musl only)
//
// When statically linked with musl, we cannot link libxcb — the Vulkan ICD
// (Asahi/Mesa) loads its own libxcb.so dynamically, and having two copies
// causes crashes. Instead, load XCB at runtime via zig_dlopen so both the
// compositor and the ICD share the same system libxcb.so.

const use_zig_dlopen = (builtin.link_mode == .static and (builtin.abi == .musl or !builtin.link_libc));
const zig_dlopen = if (use_zig_dlopen) @import("dlopen") else struct {};
extern fn zig_foreign_begin() callconv(.c) void;
extern fn zig_foreign_end() callconv(.c) void;

/// Runtime-loaded XCB function pointers (libxcb.so.1)
const XcbFns = struct {
    connect: *const fn (?[*:0]const u8, ?*c_int) callconv(.c) ?*xcb.xcb_connection_t = undefined,
    connection_has_error: *const fn (*xcb.xcb_connection_t) callconv(.c) c_int = undefined,
    disconnect: *const fn (*xcb.xcb_connection_t) callconv(.c) void = undefined,
    get_setup: *const fn (*xcb.xcb_connection_t) callconv(.c) ?*const xcb.xcb_setup_t = undefined,
    setup_roots_iterator: *const fn (?*const xcb.xcb_setup_t) callconv(.c) xcb.xcb_screen_iterator_t = undefined,
    screen_next: *const fn (*xcb.xcb_screen_iterator_t) callconv(.c) void = undefined,
    generate_id: *const fn (*xcb.xcb_connection_t) callconv(.c) u32 = undefined,
    create_window: *const fn (*xcb.xcb_connection_t, u8, xcb.xcb_window_t, xcb.xcb_window_t, i16, i16, u16, u16, u16, u16, xcb.xcb_visualid_t, u32, ?*const anyopaque) callconv(.c) xcb.xcb_void_cookie_t = undefined,
    change_property: *const fn (*xcb.xcb_connection_t, u8, xcb.xcb_window_t, xcb.xcb_atom_t, xcb.xcb_atom_t, u8, u32, ?*const anyopaque) callconv(.c) xcb.xcb_void_cookie_t = undefined,
    intern_atom: *const fn (*xcb.xcb_connection_t, u8, u16, [*c]const u8) callconv(.c) xcb.xcb_intern_atom_cookie_t = undefined,
    intern_atom_reply: *const fn (*xcb.xcb_connection_t, xcb.xcb_intern_atom_cookie_t, ?*?*xcb.xcb_generic_error_t) callconv(.c) ?*xcb.xcb_intern_atom_reply_t = undefined,
    map_window: *const fn (*xcb.xcb_connection_t, xcb.xcb_window_t) callconv(.c) xcb.xcb_void_cookie_t = undefined,
    flush: *const fn (*xcb.xcb_connection_t) callconv(.c) c_int = undefined,
    request_check: *const fn (*xcb.xcb_connection_t, xcb.xcb_void_cookie_t) callconv(.c) ?*xcb.xcb_generic_error_t = undefined,
    poll_for_event: *const fn (*xcb.xcb_connection_t) callconv(.c) ?*xcb.xcb_generic_event_t = undefined,
    destroy_window: *const fn (*xcb.xcb_connection_t, xcb.xcb_window_t) callconv(.c) xcb.xcb_void_cookie_t = undefined,
    query_extension: *const fn (*xcb.xcb_connection_t, u16, [*c]const u8) callconv(.c) xcb.xcb_query_extension_cookie_t = undefined,
    query_extension_reply: *const fn (*xcb.xcb_connection_t, xcb.xcb_query_extension_cookie_t, ?*?*xcb.xcb_generic_error_t) callconv(.c) ?*xcb.xcb_query_extension_reply_t = undefined,
    // X11 selection handling (CLIPBOARD bridge).
    set_selection_owner: *const fn (*xcb.xcb_connection_t, xcb.xcb_window_t, xcb.xcb_atom_t, xcb.xcb_timestamp_t) callconv(.c) xcb.xcb_void_cookie_t = undefined,
    get_selection_owner: *const fn (*xcb.xcb_connection_t, xcb.xcb_atom_t) callconv(.c) xcb.xcb_get_selection_owner_cookie_t = undefined,
    get_selection_owner_reply: *const fn (*xcb.xcb_connection_t, xcb.xcb_get_selection_owner_cookie_t, ?*?*xcb.xcb_generic_error_t) callconv(.c) ?*xcb.xcb_get_selection_owner_reply_t = undefined,
    convert_selection: *const fn (*xcb.xcb_connection_t, xcb.xcb_window_t, xcb.xcb_atom_t, xcb.xcb_atom_t, xcb.xcb_atom_t, xcb.xcb_timestamp_t) callconv(.c) xcb.xcb_void_cookie_t = undefined,
    get_property: *const fn (*xcb.xcb_connection_t, u8, xcb.xcb_window_t, xcb.xcb_atom_t, xcb.xcb_atom_t, u32, u32) callconv(.c) xcb.xcb_get_property_cookie_t = undefined,
    get_property_reply: *const fn (*xcb.xcb_connection_t, xcb.xcb_get_property_cookie_t, ?*?*xcb.xcb_generic_error_t) callconv(.c) ?*xcb.xcb_get_property_reply_t = undefined,
    get_property_value: *const fn (?*const xcb.xcb_get_property_reply_t) callconv(.c) ?*anyopaque = undefined,
    get_property_value_length: *const fn (?*const xcb.xcb_get_property_reply_t) callconv(.c) c_int = undefined,
    send_event: *const fn (*xcb.xcb_connection_t, u8, xcb.xcb_window_t, u32, [*c]const u8) callconv(.c) xcb.xcb_void_cookie_t = undefined,
    // bug 0010: invisible-cursor support — hide the X11 host pointer
    // when arcan takes over the window so the user sees only durian's
    // software cursor.
    create_pixmap: *const fn (*xcb.xcb_connection_t, u8, xcb.xcb_pixmap_t, xcb.xcb_drawable_t, u16, u16) callconv(.c) xcb.xcb_void_cookie_t = undefined,
    create_cursor: *const fn (*xcb.xcb_connection_t, xcb.xcb_cursor_t, xcb.xcb_pixmap_t, xcb.xcb_pixmap_t, u16, u16, u16, u16, u16, u16, u16, u16) callconv(.c) xcb.xcb_void_cookie_t = undefined,
    change_window_attributes: *const fn (*xcb.xcb_connection_t, xcb.xcb_window_t, u32, ?*const anyopaque) callconv(.c) xcb.xcb_void_cookie_t = undefined,
};

/// Runtime-loaded XCB-XInput function pointers (libxcb-xinput.so.0)
const XcbXInputFns = struct {
    xi_query_version: *const fn (*xcb.xcb_connection_t, u16, u16) callconv(.c) xcb.xcb_input_xi_query_version_cookie_t = undefined,
    xi_query_version_reply: *const fn (*xcb.xcb_connection_t, xcb.xcb_input_xi_query_version_cookie_t, ?*?*xcb.xcb_generic_error_t) callconv(.c) ?*xcb.xcb_input_xi_query_version_reply_t = undefined,
    xi_select_events_checked: *const fn (*xcb.xcb_connection_t, xcb.xcb_window_t, u16, [*c]const xcb.xcb_input_event_mask_t) callconv(.c) xcb.xcb_void_cookie_t = undefined,
    xi_query_device: *const fn (*xcb.xcb_connection_t, xcb.xcb_input_device_id_t) callconv(.c) xcb.xcb_input_xi_query_device_cookie_t = undefined,
    xi_query_device_reply: *const fn (*xcb.xcb_connection_t, xcb.xcb_input_xi_query_device_cookie_t, ?*?*xcb.xcb_generic_error_t) callconv(.c) ?*xcb.xcb_input_xi_query_device_reply_t = undefined,
    xi_query_device_infos_iterator: *const fn (*const xcb.xcb_input_xi_query_device_reply_t) callconv(.c) xcb.xcb_input_xi_device_info_iterator_t = undefined,
    xi_device_info_next: *const fn (*xcb.xcb_input_xi_device_info_iterator_t) callconv(.c) void = undefined,
    xi_device_info_classes_iterator: *const fn (*const xcb.xcb_input_xi_device_info_t) callconv(.c) xcb.xcb_input_device_class_iterator_t = undefined,
    device_class_next: *const fn (*xcb.xcb_input_device_class_iterator_t) callconv(.c) void = undefined,
};

/// Runtime-loaded XCB-XKB function pointers (libxcb-xkb.so.1)
const XcbXkbFns = struct {
    select_events_checked: *const fn (*xcb.xcb_connection_t, xcb.xcb_xkb_device_spec_t, u16, u16, u16, u16, u16, ?*const anyopaque) callconv(.c) xcb.xcb_void_cookie_t = undefined,
    per_client_flags: *const fn (*xcb.xcb_connection_t, xcb.xcb_xkb_device_spec_t, u32, u32, u32, u32, u32) callconv(.c) xcb.xcb_xkb_per_client_flags_cookie_t = undefined,
    per_client_flags_reply: *const fn (*xcb.xcb_connection_t, xcb.xcb_xkb_per_client_flags_cookie_t, ?*?*xcb.xcb_generic_error_t) callconv(.c) ?*xcb.xcb_xkb_per_client_flags_reply_t = undefined,
};

/// Runtime-loaded xkbcommon-x11 function pointers (libxkbcommon-x11.so.0)
const XkbX11Fns = struct {
    setup_xkb_extension: *const fn (?*xkb.xcb_connection_t, u16, u16, xkb.enum_xkb_x11_setup_xkb_extension_flags, ?*u16, ?*u16, ?*u8, ?*u8) callconv(.c) c_int = undefined,
    get_core_keyboard_device_id: *const fn (?*xkb.xcb_connection_t) callconv(.c) i32 = undefined,
    keymap_new_from_device: *const fn (?*xkb.xkb_context, ?*xkb.xcb_connection_t, i32, xkb.enum_xkb_keymap_compile_flags) callconv(.c) ?*xkb.xkb_keymap = undefined,
    state_new_from_device: *const fn (?*xkb.xkb_keymap, ?*xkb.xcb_connection_t, i32) callconv(.c) ?*xkb.xkb_state = undefined,
};

/// Runtime-loaded xkbcommon base function pointers (libxkbcommon.so.0)
/// Must be loaded at runtime when using zig_dlopen so that xkbcommon and
/// xkbcommon-x11 share the same allocator (glibc). Mixing static xkbcommon
/// (musl malloc) with dynamic xkbcommon-x11 (glibc malloc) crashes in realloc.
const XkbBaseFns = struct {
    context_new: *const fn (xkb.enum_xkb_context_flags) callconv(.c) ?*xkb.xkb_context = undefined,
    context_include_path_append: *const fn (?*xkb.xkb_context, [*c]const u8) callconv(.c) c_int = undefined,
    context_unref: *const fn (?*xkb.xkb_context) callconv(.c) void = undefined,
    keymap_new_from_names: *const fn (?*xkb.xkb_context, ?*const xkb.struct_xkb_rule_names, xkb.enum_xkb_keymap_compile_flags) callconv(.c) ?*xkb.xkb_keymap = undefined,
    keymap_unref: *const fn (?*xkb.xkb_keymap) callconv(.c) void = undefined,
    state_new: *const fn (?*xkb.xkb_keymap) callconv(.c) ?*xkb.xkb_state = undefined,
    state_unref: *const fn (?*xkb.xkb_state) callconv(.c) void = undefined,
    state_key_get_one_sym: *const fn (?*xkb.xkb_state, u32) callconv(.c) u32 = undefined,
    state_key_get_utf8: *const fn (?*xkb.xkb_state, u32, [*c]u8, usize) callconv(.c) c_int = undefined,
    state_update_key: *const fn (?*xkb.xkb_state, u32, xkb.enum_xkb_key_direction) callconv(.c) u32 = undefined,
    compose_table_new_from_locale: *const fn (?*xkb.xkb_context, [*c]const u8, xkb.enum_xkb_compose_compile_flags) callconv(.c) ?*xkb.xkb_compose_table = undefined,
    compose_table_new_from_file: *const fn (?*xkb.xkb_context, ?*anyopaque, [*c]const u8, xkb.enum_xkb_compose_format, xkb.enum_xkb_compose_compile_flags) callconv(.c) ?*xkb.xkb_compose_table = undefined,
    compose_table_unref: *const fn (?*xkb.xkb_compose_table) callconv(.c) void = undefined,
    compose_state_new: *const fn (?*xkb.xkb_compose_table, xkb.enum_xkb_compose_state_flags) callconv(.c) ?*xkb.xkb_compose_state = undefined,
    compose_state_unref: *const fn (?*xkb.xkb_compose_state) callconv(.c) void = undefined,
    compose_state_feed: *const fn (?*xkb.xkb_compose_state, u32) callconv(.c) xkb.enum_xkb_compose_feed_result = undefined,
    compose_state_get_status: *const fn (?*xkb.xkb_compose_state) callconv(.c) xkb.enum_xkb_compose_status = undefined,
    compose_state_get_one_sym: *const fn (?*xkb.xkb_compose_state) callconv(.c) u32 = undefined,
    compose_state_get_utf8: *const fn (?*xkb.xkb_compose_state, [*c]u8, usize) callconv(.c) c_int = undefined,
};

var xcb_fns: XcbFns = undefined;
var xcb_xkb_fns: XcbXkbFns = undefined;
var xcb_xinput_fns: XcbXInputFns = undefined;
var xkb_x11_fns: XkbX11Fns = undefined;
var xkb_base_fns: XkbBaseFns = undefined;
var xcb_loaded: bool = false;
var xcb_xkb_loaded: bool = false;
var xcb_xinput_loaded: bool = false;
var xkb_x11_loaded: bool = false;
var xkb_base_loaded: bool = false;

/// glibc's free — must be used for memory allocated by runtime-loaded XCB
/// (XCB uses glibc's malloc; musl's free can't handle glibc allocations)
var glibc_free_fn: ?*const fn (?*anyopaque) callconv(.c) void = null;

/// Free memory allocated by XCB (glibc's free when using zig_dlopen, musl's otherwise)
fn xcb_free(ptr: ?*anyopaque) void {
    if (use_zig_dlopen) {
        if (glibc_free_fn) |f| f(ptr) else std.c.free(ptr);
    } else {
        std.c.free(ptr);
    }
}

fn dlsymT(comptime T: type, handle: *anyopaque, name: [*:0]const u8) ?T {
    const ptr = zig_dlopen.zig_dlsym(handle, name) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn loadXcb() bool {
    if (xcb_loaded) return true;
    const handle = zig_dlopen.zig_dlopen("libxcb.so.1", 1) orelse {
        _ = stdio.printf("[vk_xcb] zig_dlopen(\"libxcb.so.1\") failed\n");
        return false;
    };
    xcb_fns.connect = dlsymT(@TypeOf(xcb_fns.connect), handle, "xcb_connect") orelse return dlFail("xcb_connect");
    xcb_fns.connection_has_error = dlsymT(@TypeOf(xcb_fns.connection_has_error), handle, "xcb_connection_has_error") orelse return dlFail("xcb_connection_has_error");
    xcb_fns.disconnect = dlsymT(@TypeOf(xcb_fns.disconnect), handle, "xcb_disconnect") orelse return dlFail("xcb_disconnect");
    xcb_fns.get_setup = dlsymT(@TypeOf(xcb_fns.get_setup), handle, "xcb_get_setup") orelse return dlFail("xcb_get_setup");
    xcb_fns.setup_roots_iterator = dlsymT(@TypeOf(xcb_fns.setup_roots_iterator), handle, "xcb_setup_roots_iterator") orelse return dlFail("xcb_setup_roots_iterator");
    xcb_fns.screen_next = dlsymT(@TypeOf(xcb_fns.screen_next), handle, "xcb_screen_next") orelse return dlFail("xcb_screen_next");
    xcb_fns.generate_id = dlsymT(@TypeOf(xcb_fns.generate_id), handle, "xcb_generate_id") orelse return dlFail("xcb_generate_id");
    xcb_fns.create_window = dlsymT(@TypeOf(xcb_fns.create_window), handle, "xcb_create_window") orelse return dlFail("xcb_create_window");
    xcb_fns.change_property = dlsymT(@TypeOf(xcb_fns.change_property), handle, "xcb_change_property") orelse return dlFail("xcb_change_property");
    xcb_fns.intern_atom = dlsymT(@TypeOf(xcb_fns.intern_atom), handle, "xcb_intern_atom") orelse return dlFail("xcb_intern_atom");
    xcb_fns.intern_atom_reply = dlsymT(@TypeOf(xcb_fns.intern_atom_reply), handle, "xcb_intern_atom_reply") orelse return dlFail("xcb_intern_atom_reply");
    xcb_fns.map_window = dlsymT(@TypeOf(xcb_fns.map_window), handle, "xcb_map_window") orelse return dlFail("xcb_map_window");
    xcb_fns.flush = dlsymT(@TypeOf(xcb_fns.flush), handle, "xcb_flush") orelse return dlFail("xcb_flush");
    xcb_fns.request_check = dlsymT(@TypeOf(xcb_fns.request_check), handle, "xcb_request_check") orelse return dlFail("xcb_request_check");
    xcb_fns.poll_for_event = dlsymT(@TypeOf(xcb_fns.poll_for_event), handle, "xcb_poll_for_event") orelse return dlFail("xcb_poll_for_event");
    xcb_fns.destroy_window = dlsymT(@TypeOf(xcb_fns.destroy_window), handle, "xcb_destroy_window") orelse return dlFail("xcb_destroy_window");
    xcb_fns.query_extension = dlsymT(@TypeOf(xcb_fns.query_extension), handle, "xcb_query_extension") orelse return dlFail("xcb_query_extension");
    xcb_fns.query_extension_reply = dlsymT(@TypeOf(xcb_fns.query_extension_reply), handle, "xcb_query_extension_reply") orelse return dlFail("xcb_query_extension_reply");
    xcb_fns.set_selection_owner = dlsymT(@TypeOf(xcb_fns.set_selection_owner), handle, "xcb_set_selection_owner") orelse return dlFail("xcb_set_selection_owner");
    xcb_fns.get_selection_owner = dlsymT(@TypeOf(xcb_fns.get_selection_owner), handle, "xcb_get_selection_owner") orelse return dlFail("xcb_get_selection_owner");
    xcb_fns.get_selection_owner_reply = dlsymT(@TypeOf(xcb_fns.get_selection_owner_reply), handle, "xcb_get_selection_owner_reply") orelse return dlFail("xcb_get_selection_owner_reply");
    xcb_fns.convert_selection = dlsymT(@TypeOf(xcb_fns.convert_selection), handle, "xcb_convert_selection") orelse return dlFail("xcb_convert_selection");
    xcb_fns.get_property = dlsymT(@TypeOf(xcb_fns.get_property), handle, "xcb_get_property") orelse return dlFail("xcb_get_property");
    xcb_fns.get_property_reply = dlsymT(@TypeOf(xcb_fns.get_property_reply), handle, "xcb_get_property_reply") orelse return dlFail("xcb_get_property_reply");
    xcb_fns.get_property_value = dlsymT(@TypeOf(xcb_fns.get_property_value), handle, "xcb_get_property_value") orelse return dlFail("xcb_get_property_value");
    xcb_fns.get_property_value_length = dlsymT(@TypeOf(xcb_fns.get_property_value_length), handle, "xcb_get_property_value_length") orelse return dlFail("xcb_get_property_value_length");
    xcb_fns.send_event = dlsymT(@TypeOf(xcb_fns.send_event), handle, "xcb_send_event") orelse return dlFail("xcb_send_event");
    // bug 0010: invisible-cursor support
    xcb_fns.create_pixmap = dlsymT(@TypeOf(xcb_fns.create_pixmap), handle, "xcb_create_pixmap") orelse return dlFail("xcb_create_pixmap");
    xcb_fns.create_cursor = dlsymT(@TypeOf(xcb_fns.create_cursor), handle, "xcb_create_cursor") orelse return dlFail("xcb_create_cursor");
    xcb_fns.change_window_attributes = dlsymT(@TypeOf(xcb_fns.change_window_attributes), handle, "xcb_change_window_attributes") orelse return dlFail("xcb_change_window_attributes");
    // Load glibc's free for XCB-allocated memory (musl's free can't handle glibc allocations)
    glibc_free_fn = dlsymT(@TypeOf(glibc_free_fn.?), handle, "free") orelse {
        _ = stdio.printf("[vk_xcb] warning: could not load glibc free\n");
        return dlFail("free");
    };
    xcb_loaded = true;
    return true;
}

fn loadXcbXkb() bool {
    if (xcb_xkb_loaded) return true;
    const handle = zig_dlopen.zig_dlopen("libxcb-xkb.so.1", 1) orelse {
        _ = stdio.printf("[vk_xcb] zig_dlopen(\"libxcb-xkb.so.1\") failed\n");
        return false;
    };
    xcb_xkb_fns.select_events_checked = dlsymT(@TypeOf(xcb_xkb_fns.select_events_checked), handle, "xcb_xkb_select_events_checked") orelse return dlFail("xcb_xkb_select_events_checked");
    xcb_xkb_fns.per_client_flags = dlsymT(@TypeOf(xcb_xkb_fns.per_client_flags), handle, "xcb_xkb_per_client_flags") orelse return dlFail("xcb_xkb_per_client_flags");
    xcb_xkb_fns.per_client_flags_reply = dlsymT(@TypeOf(xcb_xkb_fns.per_client_flags_reply), handle, "xcb_xkb_per_client_flags_reply") orelse return dlFail("xcb_xkb_per_client_flags_reply");
    xcb_xkb_loaded = true;
    return true;
}

fn loadXcbXInput() bool {
    if (xcb_xinput_loaded) return true;
    const handle = zig_dlopen.zig_dlopen("libxcb-xinput.so.0", 1) orelse {
        _ = stdio.printf("[vk_xcb] zig_dlopen(\"libxcb-xinput.so.0\") failed (scroll on touchpads will not work)\n");
        return false;
    };
    xcb_xinput_fns.xi_query_version = dlsymT(@TypeOf(xcb_xinput_fns.xi_query_version), handle, "xcb_input_xi_query_version") orelse return dlFail("xcb_input_xi_query_version");
    xcb_xinput_fns.xi_query_version_reply = dlsymT(@TypeOf(xcb_xinput_fns.xi_query_version_reply), handle, "xcb_input_xi_query_version_reply") orelse return dlFail("xcb_input_xi_query_version_reply");
    xcb_xinput_fns.xi_select_events_checked = dlsymT(@TypeOf(xcb_xinput_fns.xi_select_events_checked), handle, "xcb_input_xi_select_events_checked") orelse return dlFail("xcb_input_xi_select_events_checked");
    xcb_xinput_fns.xi_query_device = dlsymT(@TypeOf(xcb_xinput_fns.xi_query_device), handle, "xcb_input_xi_query_device") orelse return dlFail("xcb_input_xi_query_device");
    xcb_xinput_fns.xi_query_device_reply = dlsymT(@TypeOf(xcb_xinput_fns.xi_query_device_reply), handle, "xcb_input_xi_query_device_reply") orelse return dlFail("xcb_input_xi_query_device_reply");
    xcb_xinput_fns.xi_query_device_infos_iterator = dlsymT(@TypeOf(xcb_xinput_fns.xi_query_device_infos_iterator), handle, "xcb_input_xi_query_device_infos_iterator") orelse return dlFail("xcb_input_xi_query_device_infos_iterator");
    xcb_xinput_fns.xi_device_info_next = dlsymT(@TypeOf(xcb_xinput_fns.xi_device_info_next), handle, "xcb_input_xi_device_info_next") orelse return dlFail("xcb_input_xi_device_info_next");
    xcb_xinput_fns.xi_device_info_classes_iterator = dlsymT(@TypeOf(xcb_xinput_fns.xi_device_info_classes_iterator), handle, "xcb_input_xi_device_info_classes_iterator") orelse return dlFail("xcb_input_xi_device_info_classes_iterator");
    xcb_xinput_fns.device_class_next = dlsymT(@TypeOf(xcb_xinput_fns.device_class_next), handle, "xcb_input_device_class_next") orelse return dlFail("xcb_input_device_class_next");
    xcb_xinput_loaded = true;
    return true;
}

fn loadXkbX11() bool {
    if (xkb_x11_loaded) return true;
    const handle = zig_dlopen.zig_dlopen("libxkbcommon-x11.so.0", 1) orelse {
        _ = stdio.printf("[vk_xcb] zig_dlopen(\"libxkbcommon-x11.so.0\") failed\n");
        return false;
    };
    xkb_x11_fns.setup_xkb_extension = dlsymT(@TypeOf(xkb_x11_fns.setup_xkb_extension), handle, "xkb_x11_setup_xkb_extension") orelse return dlFail("xkb_x11_setup_xkb_extension");
    xkb_x11_fns.get_core_keyboard_device_id = dlsymT(@TypeOf(xkb_x11_fns.get_core_keyboard_device_id), handle, "xkb_x11_get_core_keyboard_device_id") orelse return dlFail("xkb_x11_get_core_keyboard_device_id");
    xkb_x11_fns.keymap_new_from_device = dlsymT(@TypeOf(xkb_x11_fns.keymap_new_from_device), handle, "xkb_x11_keymap_new_from_device") orelse return dlFail("xkb_x11_keymap_new_from_device");
    xkb_x11_fns.state_new_from_device = dlsymT(@TypeOf(xkb_x11_fns.state_new_from_device), handle, "xkb_x11_state_new_from_device") orelse return dlFail("xkb_x11_state_new_from_device");
    xkb_x11_loaded = true;
    return true;
}

fn loadXkbBase() bool {
    if (xkb_base_loaded) return true;
    const handle = zig_dlopen.zig_dlopen("libxkbcommon.so.0", 1) orelse {
        _ = stdio.printf("[vk_xcb] zig_dlopen(\"libxkbcommon.so.0\") failed\n");
        return false;
    };
    xkb_base_fns.context_new = dlsymT(@TypeOf(xkb_base_fns.context_new), handle, "xkb_context_new") orelse return dlFail("xkb_context_new");
    xkb_base_fns.context_include_path_append = dlsymT(@TypeOf(xkb_base_fns.context_include_path_append), handle, "xkb_context_include_path_append") orelse return dlFail("xkb_context_include_path_append");
    xkb_base_fns.context_unref = dlsymT(@TypeOf(xkb_base_fns.context_unref), handle, "xkb_context_unref") orelse return dlFail("xkb_context_unref");
    xkb_base_fns.keymap_new_from_names = dlsymT(@TypeOf(xkb_base_fns.keymap_new_from_names), handle, "xkb_keymap_new_from_names") orelse return dlFail("xkb_keymap_new_from_names");
    xkb_base_fns.keymap_unref = dlsymT(@TypeOf(xkb_base_fns.keymap_unref), handle, "xkb_keymap_unref") orelse return dlFail("xkb_keymap_unref");
    xkb_base_fns.state_new = dlsymT(@TypeOf(xkb_base_fns.state_new), handle, "xkb_state_new") orelse return dlFail("xkb_state_new");
    xkb_base_fns.state_unref = dlsymT(@TypeOf(xkb_base_fns.state_unref), handle, "xkb_state_unref") orelse return dlFail("xkb_state_unref");
    xkb_base_fns.state_key_get_one_sym = dlsymT(@TypeOf(xkb_base_fns.state_key_get_one_sym), handle, "xkb_state_key_get_one_sym") orelse return dlFail("xkb_state_key_get_one_sym");
    xkb_base_fns.state_key_get_utf8 = dlsymT(@TypeOf(xkb_base_fns.state_key_get_utf8), handle, "xkb_state_key_get_utf8") orelse return dlFail("xkb_state_key_get_utf8");
    xkb_base_fns.state_update_key = dlsymT(@TypeOf(xkb_base_fns.state_update_key), handle, "xkb_state_update_key") orelse return dlFail("xkb_state_update_key");
    xkb_base_fns.compose_table_new_from_locale = dlsymT(@TypeOf(xkb_base_fns.compose_table_new_from_locale), handle, "xkb_compose_table_new_from_locale") orelse return dlFail("xkb_compose_table_new_from_locale");
    xkb_base_fns.compose_table_new_from_file = dlsymT(@TypeOf(xkb_base_fns.compose_table_new_from_file), handle, "xkb_compose_table_new_from_file") orelse return dlFail("xkb_compose_table_new_from_file");
    xkb_base_fns.compose_table_unref = dlsymT(@TypeOf(xkb_base_fns.compose_table_unref), handle, "xkb_compose_table_unref") orelse return dlFail("xkb_compose_table_unref");
    xkb_base_fns.compose_state_new = dlsymT(@TypeOf(xkb_base_fns.compose_state_new), handle, "xkb_compose_state_new") orelse return dlFail("xkb_compose_state_new");
    xkb_base_fns.compose_state_unref = dlsymT(@TypeOf(xkb_base_fns.compose_state_unref), handle, "xkb_compose_state_unref") orelse return dlFail("xkb_compose_state_unref");
    xkb_base_fns.compose_state_feed = dlsymT(@TypeOf(xkb_base_fns.compose_state_feed), handle, "xkb_compose_state_feed") orelse return dlFail("xkb_compose_state_feed");
    xkb_base_fns.compose_state_get_status = dlsymT(@TypeOf(xkb_base_fns.compose_state_get_status), handle, "xkb_compose_state_get_status") orelse return dlFail("xkb_compose_state_get_status");
    xkb_base_fns.compose_state_get_one_sym = dlsymT(@TypeOf(xkb_base_fns.compose_state_get_one_sym), handle, "xkb_compose_state_get_one_sym") orelse return dlFail("xkb_compose_state_get_one_sym");
    xkb_base_fns.compose_state_get_utf8 = dlsymT(@TypeOf(xkb_base_fns.compose_state_get_utf8), handle, "xkb_compose_state_get_utf8") orelse return dlFail("xkb_compose_state_get_utf8");
    xkb_base_loaded = true;
    return true;
}

fn dlFail(name: [*:0]const u8) bool {
    _ = stdio.printf("[vk_xcb] dlsym failed: %s\n", name);
    return false;
}

/// Initialise XInput2 on the given window. Required for trackpad scroll on
/// XWayland / modern X servers — legacy core ButtonPress only carries
/// wheel events for hardware mice. Sets `win.xi_major_opcode` on success.
fn initXInput2(win: *XcbWindow) void {
    if (use_zig_dlopen and !loadXcbXInput()) return;

    // Look up XInputExtension's major opcode (events come back as
    // XCB_GE_GENERIC and need this to be matched).
    const ext_name = "XInputExtension";
    const qcookie = xcb_query_extension(win.connection, @intCast(ext_name.len), ext_name);
    const qreply = xcb_query_extension_reply(win.connection, qcookie, null) orelse {
        _ = stdio.printf("[vk_xcb] XInput extension not present on this server\n");
        return;
    };
    const present = qreply.present;
    const opcode = qreply.major_opcode;
    xcb_free(qreply);
    if (present == 0) {
        _ = stdio.printf("[vk_xcb] XInput extension not present (present=0)\n");
        return;
    }

    // Negotiate version >= 2.0. Server replies with the version it
    // actually supports; we only require 2.0 for ButtonPress + Motion.
    const vcookie = xcb_input_xi_query_version(win.connection, 2, 0);
    const vreply = xcb_input_xi_query_version_reply(win.connection, vcookie, null) orelse {
        _ = stdio.printf("[vk_xcb] XInput xi_query_version failed\n");
        return;
    };
    const major = vreply.major_version;
    const minor = vreply.minor_version;
    xcb_free(vreply);
    if (major < 2) {
        _ = stdio.printf("[vk_xcb] XInput too old: %u.%u (need >= 2.0)\n", @as(c_uint, major), @as(c_uint, minor));
        return;
    }

    // Subscribe to ButtonPress + ButtonRelease + Motion for the master
    // pointer. Smooth-scroll trackpads deliver scroll via XI_Motion with
    // scroll-class valuator deltas, not legacy button 4/5 — see the
    // follow-up scroll-class query below for how we decode those deltas.
    // Bit positions: XCB_INPUT_BUTTON_PRESS=4, BUTTON_RELEASE=5, MOTION=6.
    const Mask = extern struct {
        head: xcb.xcb_input_event_mask_t,
        bits: u32,
    };
    var em = Mask{
        .head = .{
            .deviceid = xcb.XCB_INPUT_DEVICE_ALL_MASTER,
            .mask_len = 1,
        },
        .bits = xcb.XCB_INPUT_XI_EVENT_MASK_BUTTON_PRESS |
            xcb.XCB_INPUT_XI_EVENT_MASK_BUTTON_RELEASE |
            xcb.XCB_INPUT_XI_EVENT_MASK_MOTION,
    };
    const cookie = xcb_input_xi_select_events_checked(win.connection, win.window, 1, @ptrCast(&em.head));
    if (xcb_request_check(win.connection, cookie)) |err| {
        _ = stdio.printf("[vk_xcb] xi_select_events failed: error_code=%u\n", @as(c_uint, err.error_code));
        xcb_free(err);
        return;
    }

    win.xi_major_opcode = opcode;
    queryScrollClasses(win);
}

/// Walk the master pointer's device classes, remember any SCROLL_CLASS
/// entries. Smooth-scroll valuator deltas get decoded against these at
/// XI_Motion time. Silent no-op if the query fails — we fall back to
/// whatever legacy button 4/5 events XWayland emits for us.
fn queryScrollClasses(win: *XcbWindow) void {
    const qcookie = xcb_input_xi_query_device(win.connection, xcb.XCB_INPUT_DEVICE_ALL_MASTER);
    const reply = xcb_input_xi_query_device_reply(win.connection, qcookie, null) orelse return;
    defer xcb_free(reply);

    var dev_it = xcb_input_xi_query_device_infos_iterator(reply);
    while (dev_it.rem > 0) : (xcb_input_xi_device_info_next(&dev_it)) {
        if (dev_it.data == null) continue;
        const info = &dev_it.data[0];
        // We only care about the master pointer devices (type 1 = master pointer).
        if (info.type != xcb.XCB_INPUT_DEVICE_TYPE_MASTER_POINTER) continue;

        var cls_it = xcb_input_xi_device_info_classes_iterator(@ptrCast(info));
        while (cls_it.rem > 0) : (xcb_input_device_class_next(&cls_it)) {
            if (cls_it.data == null) continue;
            const cls = &cls_it.data[0];
            if (cls.type != xcb.XCB_INPUT_DEVICE_CLASS_TYPE_SCROLL) continue;
            if (win.scroll_axes_len >= win.scroll_axes.len) break;

            // The scroll class extends device_class_t; its payload follows
            // the common header. xcb_input_scroll_class_t layout:
            //   type(u16) len(u16) sourceid(u16) number(u16) scroll_type(u16)
            //   pad[2] flags(u32) increment(fp3232)
            const sc: *const xcb.xcb_input_scroll_class_t = @ptrCast(@alignCast(cls));
            const inc_int: f64 = @floatFromInt(sc.increment.integral);
            const inc_frac: f64 = @as(f64, @floatFromInt(sc.increment.frac)) / 4294967296.0;
            const increment = inc_int + inc_frac;
            if (increment == 0) continue; // defensive; spec says non-zero

            win.scroll_axes[win.scroll_axes_len] = .{
                .valuator = sc.number,
                .scroll_type = sc.scroll_type,
                .increment = increment,
            };
            win.scroll_axes_len += 1;
        }
    }
}

/// Decode an XI_Motion event. Subscribing to XI_Motion via XInput2 makes
/// XWayland suppress the legacy XCB_MOTION_NOTIFY for this device — so we
/// must translate XI_Motion into the same `.motion` InputEvent that the
/// core path emits (otherwise cursor-tracking and click-focus break).
/// On top of that, we decode scroll-class valuator deltas and synthesise
/// press/release pairs for button 4/5 (vertical) or 6/7 (horizontal).
fn handleXiMotion(win: *XcbWindow, event: *xcb.xcb_generic_event_t) void {
    const motion: *const xcb.xcb_input_motion_event_t = @ptrCast(@alignCast(event));

    // Emit ordinary cursor motion unconditionally. event_x/event_y are
    // FP1616 (i32, 16.16 fixed point) in window coordinates.
    pushEvent(win, .{
        .kind = .motion,
        .x = @truncate(@as(i32, motion.event_x) >> 16),
        .y = @truncate(@as(i32, motion.event_y) >> 16),
        .mods = xcbModsToArkmod(@truncate(motion.mods.effective)),
    });

    if (win.scroll_axes_len == 0) return;

    // XI_Motion wire layout (past the common event header) concludes with:
    //   valuator_mask[valuators_len]  (u32 LE words, one bit per valuator)
    //   axisvalues[popcount(mask)]    (fp3232)
    // Both follow `buttons_mask[buttons_len]` which we skip.
    const raw: [*]const u8 = @ptrCast(event);
    // `length` on the event header is the length in 4-byte units, past a
    // fixed 32-byte prefix — but we don't actually need it to locate the
    // trailing arrays because the struct layout fixes the starting offset.
    const button_mask_u32: [*]const u32 = @ptrCast(@alignCast(raw + @sizeOf(xcb.xcb_input_motion_event_t)));
    const valuator_mask_u32 = button_mask_u32 + motion.buttons_len;
    const valuator_mask: []const u32 = valuator_mask_u32[0..motion.valuators_len];
    const axisvalues_raw: [*]const xcb.xcb_input_fp3232_t = @ptrCast(@alignCast(valuator_mask_u32 + motion.valuators_len));

    // Walk the mask bit-by-bit; the i-th set bit maps to axisvalues[i].
    var axis_idx: usize = 0;
    for (valuator_mask, 0..) |word, word_idx| {
        if (word == 0) continue;
        var bit: u5 = 0;
        while (true) : (bit +%= 1) {
            const valuator_num: u16 = @intCast(word_idx * 32 + @as(usize, bit));
            if ((word >> bit) & 1 != 0) {
                // Match against recorded scroll-class valuators.
                for (win.scroll_axes[0..win.scroll_axes_len]) |*ax| {
                    if (ax.valuator != valuator_num) continue;
                    const fp = axisvalues_raw[axis_idx];
                    const v: f64 = @as(f64, @floatFromInt(fp.integral)) +
                        @as(f64, @floatFromInt(fp.frac)) / 4294967296.0;

                    // First motion on this axis: anchor last_value without
                    // emitting anything (delta would be bogus).
                    if (!ax.has_last) {
                        ax.last_value = v;
                        ax.has_last = true;
                        break;
                    }
                    const delta_units = v - ax.last_value;
                    ax.last_value = v;
                    ax.accum += delta_units / ax.increment;

                    // Emit one synthetic wheel press/release per detent crossed.
                    while (ax.accum >= 1.0 or ax.accum <= -1.0) {
                        const down = (ax.accum > 0);
                        // Vertical: button 4 = up, 5 = down. Horizontal: 6 = left, 7 = right.
                        // XInput2 scroll_type: 1 = vertical, 2 = horizontal. Sign of the
                        // delta picks up-vs-down / left-vs-right.
                        const subid: u8 = if (ax.scroll_type == 1)
                            (if (down) 5 else 4)
                        else
                            (if (down) 7 else 6);
                        pushEvent(win, .{
                            .kind = .button_press,
                            .button = subid,
                            .x = @truncate(@as(i32, motion.event_x) >> 16),
                            .y = @truncate(@as(i32, motion.event_y) >> 16),
                            .mods = xcbModsToArkmod(@truncate(motion.mods.effective)),
                        });
                        pushEvent(win, .{
                            .kind = .button_release,
                            .button = subid,
                            .x = @truncate(@as(i32, motion.event_x) >> 16),
                            .y = @truncate(@as(i32, motion.event_y) >> 16),
                            .mods = xcbModsToArkmod(@truncate(motion.mods.effective)),
                        });
                        ax.accum += if (down) -1.0 else 1.0;
                    }
                    break;
                }
                axis_idx += 1;
            }
            if (bit == 31) break;
        }
    }
}

/// Take ownership of the X11 CLIPBOARD selection and remember `text`
/// (heap-copied) as the payload to serve on subsequent SelectionRequests.
/// Pass an empty slice (or call `clearClipboardOwnership`) to release.
pub fn setClipboardText(win: *XcbWindow, text: []const u8) void {
    if (win.atom_clipboard == 0) return; // atoms not interned, skip
    if (win.clipboard_text) |old| {
        std.heap.c_allocator.free(old);
        win.clipboard_text = null;
    }
    if (text.len > 0) {
        const buf = std.heap.c_allocator.alloc(u8, text.len) catch return;
        @memcpy(buf, text);
        win.clipboard_text = buf;
        _ = xcb_set_selection_owner(win.connection, win.window, win.atom_clipboard, xcb.XCB_TIME_CURRENT_TIME);
        _ = xcb_flush(win.connection);
    } else {
        // Releasing ownership: pass owner=None.
        _ = xcb_set_selection_owner(win.connection, 0, win.atom_clipboard, xcb.XCB_TIME_CURRENT_TIME);
        _ = xcb_flush(win.connection);
    }
}

/// Ask the current CLIPBOARD owner for UTF-8 data. The reply lands as
/// a SelectionNotify event in pollEvents, which queues a `.clipboard_in`
/// InputEvent. No-op (returns false) if a paste is already in flight.
pub fn requestClipboardPaste(win: *XcbWindow) bool {
    if (win.atom_clipboard == 0 or win.atom_utf8_string == 0 or win.atom_arcan_clip_data == 0) return false;
    if (win.clipboard_paste_pending) return false;
    win.clipboard_paste_pending = true;
    _ = xcb_convert_selection(win.connection, win.window, win.atom_clipboard, win.atom_utf8_string, win.atom_arcan_clip_data, xcb.XCB_TIME_CURRENT_TIME);
    _ = xcb_flush(win.connection);
    return true;
}

/// Another X client wants our CLIPBOARD content. Reply per ICCCM:
///   - target = TARGETS → list of supported types (TARGETS, UTF8_STRING, STRING, TEXT)
///   - target = UTF8_STRING / STRING / TEXT / "text/plain;charset=utf-8" →
///     write our `clipboard_text` to the requestor's `property` and SendEvent
///     a SelectionNotify pointing at it.
///   - anything else → SelectionNotify with property = None (refused).
fn handleSelectionRequest(win: *XcbWindow, event: *xcb.xcb_generic_event_t) void {
    const req: *const xcb.xcb_selection_request_event_t = @ptrCast(@alignCast(event));

    var reply = std.mem.zeroes(xcb.xcb_selection_notify_event_t);
    reply.response_type = xcb.XCB_SELECTION_NOTIFY;
    reply.time = req.time;
    reply.requestor = req.requestor;
    reply.selection = req.selection;
    reply.target = req.target;
    reply.property = 0; // None — flips to req.property only on success.

    if (req.selection == win.atom_clipboard) serve: {
        const text = win.clipboard_text orelse break :serve;
        if (req.target == win.atom_targets) {
            const supported = [_]xcb.xcb_atom_t{ win.atom_targets, win.atom_utf8_string, xcb.XCB_ATOM_STRING };
            _ = xcb_change_property(win.connection, xcb.XCB_PROP_MODE_REPLACE, req.requestor, req.property, xcb.XCB_ATOM_ATOM, 32, @intCast(supported.len), &supported);
            reply.property = req.property;
        } else if (req.target == win.atom_utf8_string or req.target == xcb.XCB_ATOM_STRING) {
            _ = xcb_change_property(win.connection, xcb.XCB_PROP_MODE_REPLACE, req.requestor, req.property, req.target, 8, @intCast(text.len), text.ptr);
            reply.property = req.property;
        }
    }

    _ = xcb_send_event(win.connection, 0, req.requestor, 0, @ptrCast(&reply));
    _ = xcb_flush(win.connection);
}

/// Reply to our own ConvertSelection. Pull the property data from the
/// requestor (= our own window) and queue a `.clipboard_in` InputEvent
/// with the heap-owned UTF-8 payload for the platform layer to forward
/// into arcan's clipboard.
fn handleSelectionNotify(win: *XcbWindow, event: *xcb.xcb_generic_event_t) void {
    const note: *const xcb.xcb_selection_notify_event_t = @ptrCast(@alignCast(event));
    win.clipboard_paste_pending = false;

    if (note.property == 0) return; // refused / no data

    const ck = xcb_get_property(win.connection, 0, note.requestor, note.property, 0, 0, 1024 * 1024);
    const reply = xcb_get_property_reply(win.connection, ck, null) orelse return;
    defer xcb_free(reply);

    const value_len = xcb_get_property_value_length(reply);
    if (value_len <= 0) return;
    const value = xcb_get_property_value(reply) orelse return;

    const src: [*]const u8 = @ptrCast(value);
    const slice_src = src[0..@intCast(value_len)];
    const buf = std.heap.c_allocator.alloc(u8, slice_src.len) catch return;
    @memcpy(buf, slice_src);

    pushEvent(win, .{ .kind = .clipboard_in, .clip_text = buf });
}

// Dispatch wrappers
// When use_zig_dlopen is true, call through runtime-loaded function pointers.
// When false, call the @cImport functions directly (linked at build time).

inline fn xcb_connect(displayname: ?[*:0]const u8, screenp: ?*c_int) ?*xcb.xcb_connection_t {
    if (use_zig_dlopen) return xcb_fns.connect(displayname, screenp) else return xcb.xcb_connect(displayname, screenp);
}
inline fn xcb_connection_has_error(conn: *xcb.xcb_connection_t) c_int {
    if (use_zig_dlopen) return xcb_fns.connection_has_error(conn) else return xcb.xcb_connection_has_error(conn);
}
inline fn xcb_disconnect(conn: *xcb.xcb_connection_t) void {
    if (use_zig_dlopen) xcb_fns.disconnect(conn) else xcb.xcb_disconnect(conn);
}
inline fn xcb_get_setup(conn: *xcb.xcb_connection_t) ?*const xcb.xcb_setup_t {
    if (use_zig_dlopen) return xcb_fns.get_setup(conn) else return xcb.xcb_get_setup(conn);
}
inline fn xcb_setup_roots_iterator(setup: ?*const xcb.xcb_setup_t) xcb.xcb_screen_iterator_t {
    if (use_zig_dlopen) return xcb_fns.setup_roots_iterator(setup) else return xcb.xcb_setup_roots_iterator(setup);
}
inline fn xcb_screen_next(iter: *xcb.xcb_screen_iterator_t) void {
    if (use_zig_dlopen) xcb_fns.screen_next(iter) else xcb.xcb_screen_next(iter);
}
inline fn xcb_generate_id(conn: *xcb.xcb_connection_t) u32 {
    if (use_zig_dlopen) return xcb_fns.generate_id(conn) else return xcb.xcb_generate_id(conn);
}
inline fn xcb_create_window(conn: *xcb.xcb_connection_t, depth: u8, wid: xcb.xcb_window_t, parent: xcb.xcb_window_t, x: i16, y: i16, w: u16, h: u16, border_width: u16, class: u16, visual: xcb.xcb_visualid_t, value_mask: u32, value_list: ?*const anyopaque) xcb.xcb_void_cookie_t {
    if (use_zig_dlopen) return xcb_fns.create_window(conn, depth, wid, parent, x, y, w, h, border_width, class, visual, value_mask, value_list) else return xcb.xcb_create_window(conn, depth, wid, parent, x, y, w, h, border_width, class, visual, value_mask, value_list);
}
inline fn xcb_change_property(conn: *xcb.xcb_connection_t, mode: u8, window: xcb.xcb_window_t, property: xcb.xcb_atom_t, @"type": xcb.xcb_atom_t, format: u8, data_len: u32, data: ?*const anyopaque) xcb.xcb_void_cookie_t {
    if (use_zig_dlopen) return xcb_fns.change_property(conn, mode, window, property, @"type", format, data_len, data) else return xcb.xcb_change_property(conn, mode, window, property, @"type", format, data_len, data);
}
inline fn xcb_intern_atom(conn: *xcb.xcb_connection_t, only_if_exists: u8, name_len: u16, name: [*c]const u8) xcb.xcb_intern_atom_cookie_t {
    if (use_zig_dlopen) return xcb_fns.intern_atom(conn, only_if_exists, name_len, name) else return xcb.xcb_intern_atom(conn, only_if_exists, name_len, name);
}
inline fn xcb_intern_atom_reply(conn: *xcb.xcb_connection_t, cookie: xcb.xcb_intern_atom_cookie_t, err: ?*?*xcb.xcb_generic_error_t) ?*xcb.xcb_intern_atom_reply_t {
    if (use_zig_dlopen) return xcb_fns.intern_atom_reply(conn, cookie, err) else return xcb.xcb_intern_atom_reply(conn, cookie, err);
}
inline fn xcb_map_window(conn: *xcb.xcb_connection_t, window: xcb.xcb_window_t) xcb.xcb_void_cookie_t {
    if (use_zig_dlopen) return xcb_fns.map_window(conn, window) else return xcb.xcb_map_window(conn, window);
}
inline fn xcb_flush(conn: *xcb.xcb_connection_t) c_int {
    if (use_zig_dlopen) return xcb_fns.flush(conn) else return xcb.xcb_flush(conn);
}
inline fn xcb_request_check(conn: *xcb.xcb_connection_t, cookie: xcb.xcb_void_cookie_t) ?*xcb.xcb_generic_error_t {
    if (use_zig_dlopen) return xcb_fns.request_check(conn, cookie) else return xcb.xcb_request_check(conn, cookie);
}
inline fn xcb_poll_for_event(conn: *xcb.xcb_connection_t) ?*xcb.xcb_generic_event_t {
    if (use_zig_dlopen) return xcb_fns.poll_for_event(conn) else return xcb.xcb_poll_for_event(conn);
}
inline fn xcb_destroy_window(conn: *xcb.xcb_connection_t, window: xcb.xcb_window_t) xcb.xcb_void_cookie_t {
    if (use_zig_dlopen) return xcb_fns.destroy_window(conn, window) else return xcb.xcb_destroy_window(conn, window);
}
inline fn xcb_create_pixmap(conn: *xcb.xcb_connection_t, depth: u8, pid: xcb.xcb_pixmap_t, drawable: xcb.xcb_drawable_t, w: u16, h: u16) xcb.xcb_void_cookie_t {
    if (use_zig_dlopen) return xcb_fns.create_pixmap(conn, depth, pid, drawable, w, h) else return xcb.xcb_create_pixmap(conn, depth, pid, drawable, w, h);
}
inline fn xcb_create_cursor(conn: *xcb.xcb_connection_t, cid: xcb.xcb_cursor_t, source: xcb.xcb_pixmap_t, mask: xcb.xcb_pixmap_t, fr: u16, fg: u16, fb: u16, br: u16, bg: u16, bb: u16, x: u16, y: u16) xcb.xcb_void_cookie_t {
    if (use_zig_dlopen) return xcb_fns.create_cursor(conn, cid, source, mask, fr, fg, fb, br, bg, bb, x, y) else return xcb.xcb_create_cursor(conn, cid, source, mask, fr, fg, fb, br, bg, bb, x, y);
}
inline fn xcb_change_window_attributes(conn: *xcb.xcb_connection_t, window: xcb.xcb_window_t, value_mask: u32, value_list: ?*const anyopaque) xcb.xcb_void_cookie_t {
    if (use_zig_dlopen) return xcb_fns.change_window_attributes(conn, window, value_mask, value_list) else return xcb.xcb_change_window_attributes(conn, window, value_mask, value_list);
}
inline fn xcb_xkb_select_events_checked(conn: *xcb.xcb_connection_t, device_spec: xcb.xcb_xkb_device_spec_t, affect_which: u16, clear: u16, select_all: u16, affect_map: u16, map: u16, details: ?*const anyopaque) xcb.xcb_void_cookie_t {
    if (use_zig_dlopen) return xcb_xkb_fns.select_events_checked(conn, device_spec, affect_which, clear, select_all, affect_map, map, details) else return xcb.xcb_xkb_select_events_checked(conn, device_spec, affect_which, clear, select_all, affect_map, map, details);
}
inline fn xcb_xkb_per_client_flags(conn: *xcb.xcb_connection_t, device_spec: xcb.xcb_xkb_device_spec_t, change: u32, value: u32, ctrls_to_change: u32, auto_ctrls: u32, auto_ctrls_values: u32) xcb.xcb_xkb_per_client_flags_cookie_t {
    if (use_zig_dlopen) return xcb_xkb_fns.per_client_flags(conn, device_spec, change, value, ctrls_to_change, auto_ctrls, auto_ctrls_values) else return xcb.xcb_xkb_per_client_flags(conn, device_spec, change, value, ctrls_to_change, auto_ctrls, auto_ctrls_values);
}
inline fn xcb_xkb_per_client_flags_reply(conn: *xcb.xcb_connection_t, cookie: xcb.xcb_xkb_per_client_flags_cookie_t, err: ?*?*xcb.xcb_generic_error_t) ?*xcb.xcb_xkb_per_client_flags_reply_t {
    if (use_zig_dlopen) return xcb_xkb_fns.per_client_flags_reply(conn, cookie, err) else return xcb.xcb_xkb_per_client_flags_reply(conn, cookie, err);
}
inline fn xcb_query_extension(conn: *xcb.xcb_connection_t, name_len: u16, name: [*c]const u8) xcb.xcb_query_extension_cookie_t {
    if (use_zig_dlopen) return xcb_fns.query_extension(conn, name_len, name) else return xcb.xcb_query_extension(conn, name_len, name);
}
inline fn xcb_query_extension_reply(conn: *xcb.xcb_connection_t, cookie: xcb.xcb_query_extension_cookie_t, err: ?*?*xcb.xcb_generic_error_t) ?*xcb.xcb_query_extension_reply_t {
    if (use_zig_dlopen) return xcb_fns.query_extension_reply(conn, cookie, err) else return xcb.xcb_query_extension_reply(conn, cookie, err);
}
inline fn xcb_set_selection_owner(conn: *xcb.xcb_connection_t, owner: xcb.xcb_window_t, selection: xcb.xcb_atom_t, time: xcb.xcb_timestamp_t) xcb.xcb_void_cookie_t {
    if (use_zig_dlopen) return xcb_fns.set_selection_owner(conn, owner, selection, time) else return xcb.xcb_set_selection_owner(conn, owner, selection, time);
}
inline fn xcb_get_selection_owner(conn: *xcb.xcb_connection_t, selection: xcb.xcb_atom_t) xcb.xcb_get_selection_owner_cookie_t {
    if (use_zig_dlopen) return xcb_fns.get_selection_owner(conn, selection) else return xcb.xcb_get_selection_owner(conn, selection);
}
inline fn xcb_get_selection_owner_reply(conn: *xcb.xcb_connection_t, cookie: xcb.xcb_get_selection_owner_cookie_t, err: ?*?*xcb.xcb_generic_error_t) ?*xcb.xcb_get_selection_owner_reply_t {
    if (use_zig_dlopen) return xcb_fns.get_selection_owner_reply(conn, cookie, err) else return xcb.xcb_get_selection_owner_reply(conn, cookie, err);
}
inline fn xcb_convert_selection(conn: *xcb.xcb_connection_t, requestor: xcb.xcb_window_t, selection: xcb.xcb_atom_t, target: xcb.xcb_atom_t, property: xcb.xcb_atom_t, time: xcb.xcb_timestamp_t) xcb.xcb_void_cookie_t {
    if (use_zig_dlopen) return xcb_fns.convert_selection(conn, requestor, selection, target, property, time) else return xcb.xcb_convert_selection(conn, requestor, selection, target, property, time);
}
inline fn xcb_get_property(conn: *xcb.xcb_connection_t, delete_arg: u8, window: xcb.xcb_window_t, property: xcb.xcb_atom_t, type_arg: xcb.xcb_atom_t, long_offset: u32, long_length: u32) xcb.xcb_get_property_cookie_t {
    if (use_zig_dlopen) return xcb_fns.get_property(conn, delete_arg, window, property, type_arg, long_offset, long_length) else return xcb.xcb_get_property(conn, delete_arg, window, property, type_arg, long_offset, long_length);
}
inline fn xcb_get_property_reply(conn: *xcb.xcb_connection_t, cookie: xcb.xcb_get_property_cookie_t, err: ?*?*xcb.xcb_generic_error_t) ?*xcb.xcb_get_property_reply_t {
    if (use_zig_dlopen) return xcb_fns.get_property_reply(conn, cookie, err) else return xcb.xcb_get_property_reply(conn, cookie, err);
}
inline fn xcb_get_property_value(reply: ?*const xcb.xcb_get_property_reply_t) ?*anyopaque {
    if (use_zig_dlopen) return xcb_fns.get_property_value(reply) else return xcb.xcb_get_property_value(reply);
}
inline fn xcb_get_property_value_length(reply: ?*const xcb.xcb_get_property_reply_t) c_int {
    if (use_zig_dlopen) return xcb_fns.get_property_value_length(reply) else return xcb.xcb_get_property_value_length(reply);
}
inline fn xcb_send_event(conn: *xcb.xcb_connection_t, propagate: u8, destination: xcb.xcb_window_t, event_mask: u32, event: [*c]const u8) xcb.xcb_void_cookie_t {
    if (use_zig_dlopen) return xcb_fns.send_event(conn, propagate, destination, event_mask, event) else return xcb.xcb_send_event(conn, propagate, destination, event_mask, event);
}
inline fn xcb_input_xi_query_version(conn: *xcb.xcb_connection_t, major: u16, minor: u16) xcb.xcb_input_xi_query_version_cookie_t {
    if (use_zig_dlopen) return xcb_xinput_fns.xi_query_version(conn, major, minor) else return xcb.xcb_input_xi_query_version(conn, major, minor);
}
inline fn xcb_input_xi_query_version_reply(conn: *xcb.xcb_connection_t, cookie: xcb.xcb_input_xi_query_version_cookie_t, err: ?*?*xcb.xcb_generic_error_t) ?*xcb.xcb_input_xi_query_version_reply_t {
    if (use_zig_dlopen) return xcb_xinput_fns.xi_query_version_reply(conn, cookie, err) else return xcb.xcb_input_xi_query_version_reply(conn, cookie, err);
}
inline fn xcb_input_xi_select_events_checked(conn: *xcb.xcb_connection_t, window: xcb.xcb_window_t, num_mask: u16, masks: [*c]const xcb.xcb_input_event_mask_t) xcb.xcb_void_cookie_t {
    if (use_zig_dlopen) return xcb_xinput_fns.xi_select_events_checked(conn, window, num_mask, masks) else return xcb.xcb_input_xi_select_events_checked(conn, window, num_mask, masks);
}
inline fn xcb_input_xi_query_device(conn: *xcb.xcb_connection_t, deviceid: xcb.xcb_input_device_id_t) xcb.xcb_input_xi_query_device_cookie_t {
    if (use_zig_dlopen) return xcb_xinput_fns.xi_query_device(conn, deviceid) else return xcb.xcb_input_xi_query_device(conn, deviceid);
}
inline fn xcb_input_xi_query_device_reply(conn: *xcb.xcb_connection_t, cookie: xcb.xcb_input_xi_query_device_cookie_t, err: ?*?*xcb.xcb_generic_error_t) ?*xcb.xcb_input_xi_query_device_reply_t {
    if (use_zig_dlopen) return xcb_xinput_fns.xi_query_device_reply(conn, cookie, err) else return xcb.xcb_input_xi_query_device_reply(conn, cookie, err);
}
inline fn xcb_input_xi_query_device_infos_iterator(reply: *const xcb.xcb_input_xi_query_device_reply_t) xcb.xcb_input_xi_device_info_iterator_t {
    if (use_zig_dlopen) return xcb_xinput_fns.xi_query_device_infos_iterator(reply) else return xcb.xcb_input_xi_query_device_infos_iterator(reply);
}
inline fn xcb_input_xi_device_info_next(it: *xcb.xcb_input_xi_device_info_iterator_t) void {
    if (use_zig_dlopen) xcb_xinput_fns.xi_device_info_next(it) else xcb.xcb_input_xi_device_info_next(it);
}
inline fn xcb_input_xi_device_info_classes_iterator(info: *const xcb.xcb_input_xi_device_info_t) xcb.xcb_input_device_class_iterator_t {
    if (use_zig_dlopen) return xcb_xinput_fns.xi_device_info_classes_iterator(info) else return xcb.xcb_input_xi_device_info_classes_iterator(info);
}
inline fn xcb_input_device_class_next(it: *xcb.xcb_input_device_class_iterator_t) void {
    if (use_zig_dlopen) xcb_xinput_fns.device_class_next(it) else xcb.xcb_input_device_class_next(it);
}

// xkbcommon-x11 dispatch wrappers
inline fn xkb_x11_setup_xkb_extension(conn: ?*xkb.xcb_connection_t, major: u16, minor: u16, flags: xkb.enum_xkb_x11_setup_xkb_extension_flags, major_out: ?*u16, minor_out: ?*u16, base_event: ?*u8, base_error: ?*u8) c_int {
    if (use_zig_dlopen) return xkb_x11_fns.setup_xkb_extension(conn, major, minor, flags, major_out, minor_out, base_event, base_error) else return xkb.xkb_x11_setup_xkb_extension(conn, major, minor, flags, major_out, minor_out, base_event, base_error);
}
inline fn xkb_x11_get_core_keyboard_device_id(conn: ?*xkb.xcb_connection_t) i32 {
    if (use_zig_dlopen) return xkb_x11_fns.get_core_keyboard_device_id(conn) else return xkb.xkb_x11_get_core_keyboard_device_id(conn);
}
inline fn xkb_x11_keymap_new_from_device(ctx: ?*xkb.xkb_context, conn: ?*xkb.xcb_connection_t, device_id: i32, flags: xkb.enum_xkb_keymap_compile_flags) ?*xkb.xkb_keymap {
    if (use_zig_dlopen) return xkb_x11_fns.keymap_new_from_device(ctx, conn, device_id, flags) else return xkb.xkb_x11_keymap_new_from_device(ctx, conn, device_id, flags);
}
inline fn xkb_x11_state_new_from_device(keymap: ?*xkb.xkb_keymap, conn: ?*xkb.xcb_connection_t, device_id: i32) ?*xkb.xkb_state {
    if (use_zig_dlopen) return xkb_x11_fns.state_new_from_device(keymap, conn, device_id) else return xkb.xkb_x11_state_new_from_device(keymap, conn, device_id);
}

// xkbcommon base dispatch wrappers
inline fn xkb_context_new(flags: xkb.enum_xkb_context_flags) ?*xkb.xkb_context {
    if (use_zig_dlopen) return xkb_base_fns.context_new(flags) else return xkb.xkb_context_new(flags);
}
inline fn xkb_context_include_path_append(ctx: ?*xkb.xkb_context, path: [*c]const u8) c_int {
    if (use_zig_dlopen) return xkb_base_fns.context_include_path_append(ctx, path) else return xkb.xkb_context_include_path_append(ctx, path);
}
inline fn xkb_context_unref(ctx: ?*xkb.xkb_context) void {
    if (use_zig_dlopen) xkb_base_fns.context_unref(ctx) else xkb.xkb_context_unref(ctx);
}
inline fn xkb_keymap_new_from_names(ctx: ?*xkb.xkb_context, names: ?*const xkb.struct_xkb_rule_names, flags: xkb.enum_xkb_keymap_compile_flags) ?*xkb.xkb_keymap {
    if (use_zig_dlopen) return xkb_base_fns.keymap_new_from_names(ctx, names, flags) else return xkb.xkb_keymap_new_from_names(ctx, names, flags);
}
inline fn xkb_keymap_unref(keymap: ?*xkb.xkb_keymap) void {
    if (use_zig_dlopen) xkb_base_fns.keymap_unref(keymap) else xkb.xkb_keymap_unref(keymap);
}
inline fn xkb_state_new(keymap: ?*xkb.xkb_keymap) ?*xkb.xkb_state {
    if (use_zig_dlopen) return xkb_base_fns.state_new(keymap) else return xkb.xkb_state_new(keymap);
}
inline fn xkb_state_unref(state: ?*xkb.xkb_state) void {
    if (use_zig_dlopen) xkb_base_fns.state_unref(state) else xkb.xkb_state_unref(state);
}
inline fn xkb_state_key_get_one_sym(state: ?*xkb.xkb_state, key: u32) u32 {
    if (use_zig_dlopen) return xkb_base_fns.state_key_get_one_sym(state, key) else return xkb.xkb_state_key_get_one_sym(state, key);
}
inline fn xkb_state_key_get_utf8(state: ?*xkb.xkb_state, key: u32, buf: [*c]u8, size: usize) c_int {
    if (use_zig_dlopen) return xkb_base_fns.state_key_get_utf8(state, key, buf, size) else return xkb.xkb_state_key_get_utf8(state, key, buf, size);
}
inline fn xkb_state_update_key(state: ?*xkb.xkb_state, key: u32, dir: xkb.enum_xkb_key_direction) u32 {
    if (use_zig_dlopen) return xkb_base_fns.state_update_key(state, key, dir) else return xkb.xkb_state_update_key(state, key, dir);
}
inline fn xkb_compose_table_new_from_locale(ctx: ?*xkb.xkb_context, locale: [*c]const u8, flags: xkb.enum_xkb_compose_compile_flags) ?*xkb.xkb_compose_table {
    if (use_zig_dlopen) return xkb_base_fns.compose_table_new_from_locale(ctx, locale, flags) else return xkb.xkb_compose_table_new_from_locale(ctx, locale, flags);
}
inline fn xkb_compose_table_new_from_file(ctx: ?*xkb.xkb_context, file: ?*anyopaque, locale: [*c]const u8, format: xkb.enum_xkb_compose_format, flags: xkb.enum_xkb_compose_compile_flags) ?*xkb.xkb_compose_table {
    if (use_zig_dlopen) return xkb_base_fns.compose_table_new_from_file(ctx, file, locale, format, flags) else return xkb.xkb_compose_table_new_from_file(ctx, @ptrCast(file), locale, format, flags);
}
inline fn xkb_compose_table_unref(table: ?*xkb.xkb_compose_table) void {
    if (use_zig_dlopen) xkb_base_fns.compose_table_unref(table) else xkb.xkb_compose_table_unref(table);
}
inline fn xkb_compose_state_new(table: ?*xkb.xkb_compose_table, flags: xkb.enum_xkb_compose_state_flags) ?*xkb.xkb_compose_state {
    if (use_zig_dlopen) return xkb_base_fns.compose_state_new(table, flags) else return xkb.xkb_compose_state_new(table, flags);
}
inline fn xkb_compose_state_unref(state: ?*xkb.xkb_compose_state) void {
    if (use_zig_dlopen) xkb_base_fns.compose_state_unref(state) else xkb.xkb_compose_state_unref(state);
}
inline fn xkb_compose_state_feed(state: ?*xkb.xkb_compose_state, keysym: u32) xkb.enum_xkb_compose_feed_result {
    if (use_zig_dlopen) return xkb_base_fns.compose_state_feed(state, keysym) else return xkb.xkb_compose_state_feed(state, keysym);
}
inline fn xkb_compose_state_get_status(state: ?*xkb.xkb_compose_state) xkb.enum_xkb_compose_status {
    if (use_zig_dlopen) return xkb_base_fns.compose_state_get_status(state) else return xkb.xkb_compose_state_get_status(state);
}
inline fn xkb_compose_state_get_one_sym(state: ?*xkb.xkb_compose_state) u32 {
    if (use_zig_dlopen) return xkb_base_fns.compose_state_get_one_sym(state) else return xkb.xkb_compose_state_get_one_sym(state);
}
inline fn xkb_compose_state_get_utf8(state: ?*xkb.xkb_compose_state, buf: [*c]u8, size: usize) c_int {
    if (use_zig_dlopen) return xkb_base_fns.compose_state_get_utf8(state, buf, size) else return xkb.xkb_compose_state_get_utf8(state, buf, size);
}

// Input Event Types

pub const InputEventKind = enum {
    key_press,
    key_release,
    button_press,
    button_release,
    motion,
    /// Paste from host X11 CLIPBOARD landed via SelectionNotify. The
    /// payload is owned by the InputEvent (heap-allocated `clip_text`
    /// slice); the consumer must free it after copying.
    clipboard_in,
};

pub const InputEvent = struct {
    kind: InputEventKind,
    scancode: u16 = 0, // evdev scancode (X11 keycode - 8)
    keysym: u32 = 0, // xkbcommon keysym
    button: u8 = 0, // XCB button number
    x: i16 = 0, // window-relative X
    y: i16 = 0, // window-relative Y
    mods: u16 = 0, // arcan modifier bitmask
    utf8: [8]u8 = std.mem.zeroes([8]u8),
    /// Heap-allocated UTF-8 payload for `.clipboard_in` events. The
    /// consumer takes ownership and must free via `freeClipboardEvent`.
    clip_text: ?[]u8 = null,
};

/// Free the heap payload of a clipboard_in InputEvent. Safe to call on
/// other event kinds (no-op).
pub fn freeClipboardEvent(ie: *InputEvent) void {
    if (ie.clip_text) |buf| {
        std.heap.c_allocator.free(buf);
        ie.clip_text = null;
    }
}

const MAX_INPUT_EVENTS = 128;

pub const XcbWindow = struct {
    connection: *xcb.xcb_connection_t,
    window: xcb.xcb_window_t,
    screen: *xcb.xcb_screen_t,
    wm_delete_window: xcb.xcb_atom_t,
    wm_protocols: xcb.xcb_atom_t,
    width: u32,
    height: u32,
    phy_width_mm: u32 = 0, // physical screen width in mm (from X screen)
    phy_height_mm: u32 = 0, // physical screen height in mm (from X screen)
    resize_pending: bool = false,
    close_requested: bool = false,
    // Input event buffer
    input_events: [MAX_INPUT_EVENTS]InputEvent = undefined,
    input_count: u32 = 0,
    // xkbcommon state for keyboard translation
    xkb_ctx: ?*xkb.xkb_context = null,
    xkb_keymap: ?*xkb.xkb_keymap = null,
    xkb_state: ?*xkb.xkb_state = null,
    xkb_device_id: i32 = -1,
    xkb_event_base: u8 = 0, // XKB extension event base for pollEvents
    // Compose state for dead key sequences (e.g. dead_acute + e → é)
    xkb_compose_table: ?*xkb.xkb_compose_table = null,
    xkb_compose_state: ?*xkb.xkb_compose_state = null,
    // XInput2 major opcode — 0 if XInput2 init failed (we then fall back to
    // legacy core ButtonPress for wheel events). Set when init succeeds and
    // used in pollEvents to dispatch XCB_GE_GENERIC events.
    xi_major_opcode: u8 = 0,
    // XInput2 scroll-class axes for the master pointer. Smooth scroll on
    // XWayland / libinput delivers valuator deltas via XI_Motion rather
    // than discrete button 4/5 events. We cache the (valuator_number,
    // scroll_type, increment) once at init and accumulate fractional
    // clicks; each time |accumulator| crosses 1.0 we synthesise a
    // press/release for button 4/5 (vertical) or 6/7 (horizontal).
    scroll_axes: [4]ScrollAxis = @splat(.{}),
    scroll_axes_len: u8 = 0,
    // X11 CLIPBOARD bridge state.
    atom_clipboard: xcb.xcb_atom_t = 0,
    atom_utf8_string: xcb.xcb_atom_t = 0,
    atom_targets: xcb.xcb_atom_t = 0,
    atom_arcan_clip_data: xcb.xcb_atom_t = 0,
    /// When arcan owns CLIPBOARD, this is the served payload (UTF-8). Owned
    /// by the heap; freed via `arcan_alloc.free` when replaced or window
    /// destroyed. `null` when we don't own the selection.
    clipboard_text: ?[]u8 = null,
    /// Set when we issued a ConvertSelection and are awaiting the
    /// SelectionNotify reply. Multiple in-flight requests are coalesced.
    clipboard_paste_pending: bool = false,
};

const ScrollAxis = struct {
    valuator: u16 = 0,
    scroll_type: u16 = 0, // 1=vertical, 2=horizontal
    increment: f64 = 1.0, // valuator units per detent click
    last_value: f64 = 0.0,
    has_last: bool = false,
    accum: f64 = 0.0,
};

/// Convert X11/XKB keysym to SDL 1.2 keysym (arcan's keyboard.lua expects SDL 1.2 format)
pub fn xkbToSdl12(ks: u32) u32 {
    // ASCII range (0x20-0x7e) maps directly
    if (ks >= 0x20 and ks <= 0x7e) return ks;
    // Latin-1 supplement (0xa0-0xff) maps directly
    if (ks >= 0xa0 and ks <= 0xff) return ks;

    return switch (ks) {
        0xff08 => 8, // BackSpace
        0xff09 => 9, // Tab
        0xfe20 => 9, // ISO_Left_Tab — XKB sends this for shift+tab; treat as TAB
                     // and let the modifier reach the encoder (claude shift+tab).
        0xff0b => 12, // Clear
        0xff0d => 13, // Return
        0xff13 => 19, // Pause
        0xff1b => 27, // Escape
        0xffff => 127, // Delete
        // Keypad
        0xffb0 => 256, // KP_0
        0xffb1 => 257,
        0xffb2 => 258,
        0xffb3 => 259,
        0xffb4 => 260,
        0xffb5 => 261,
        0xffb6 => 262,
        0xffb7 => 263,
        0xffb8 => 264,
        0xffb9 => 265, // KP_9
        0xffae => 266, // KP_Decimal
        0xffaf => 267, // KP_Divide
        0xffaa => 268, // KP_Multiply
        0xffad => 269, // KP_Subtract
        0xffab => 270, // KP_Add
        0xff8d => 271, // KP_Enter
        0xffbd => 272, // KP_Equal
        // Navigation
        0xff52 => 273, // Up
        0xff54 => 274, // Down
        0xff53 => 275, // Right
        0xff51 => 276, // Left
        0xff63 => 277, // Insert
        0xff50 => 278, // Home
        0xff57 => 279, // End
        0xff55 => 280, // Page_Up
        0xff56 => 281, // Page_Down
        // Function keys
        0xffbe => 282, // F1
        0xffbf => 283,
        0xffc0 => 284,
        0xffc1 => 285,
        0xffc2 => 286,
        0xffc3 => 287,
        0xffc4 => 288,
        0xffc5 => 289,
        0xffc6 => 290,
        0xffc7 => 291,
        0xffc8 => 292,
        0xffc9 => 293, // F12
        0xffca => 294,
        0xffcb => 295,
        0xffcc => 296, // F15
        // Modifiers + locks
        0xff7f => 300, // Num_Lock
        0xffe5 => 301, // Caps_Lock
        0xff14 => 302, // Scroll_Lock
        0xffe2 => 303, // Shift_R
        0xffe1 => 304, // Shift_L
        0xffe4 => 305, // Control_R
        0xffe3 => 306, // Control_L
        0xffea => 307, // Alt_R
        0xffe9 => 308, // Alt_L
        0xffe8 => 309, // Meta_R
        0xffe7 => 310, // Meta_L
        0xffeb => 311, // Super_L
        0xffec => 312, // Super_R
        0xff7e => 313, // Mode_switch
        0xff20 => 314, // Multi_key (Compose)
        0xff6a => 315, // Help
        0xff61 => 316, // Print
        0xff15 => 317, // Sys_Req
        0xff6b => 318, // Break
        0xff67 => 319, // Menu
        else => ks, // pass through unknown
    };
}

// stdio.printf — called for early-startup diagnostics before std is safe
// to use. locale_c was declared but never referenced, so dropped here.
const stdio = struct {
    pub extern "c" fn printf(fmt: [*c]const u8, ...) c_int;
    // fopen + fclose + FILE: reached only on the !use_zig_dlopen path
    // in initCompose. Even when that branch is dead at runtime, Zig
    // type-checks it, so this stdio struct has to expose the symbols.
    pub const FILE = opaque {};
    pub extern "c" fn fopen(path: [*c]const u8, mode: [*c]const u8) ?*FILE;
    pub extern "c" fn fclose(stream: *FILE) c_int;
};

fn getLocale() [*c]const u8 {
    // Try environment variables in standard priority order
    const vars = [_][*c]const u8{ "LC_ALL", "LC_CTYPE", "LANG" };
    for (vars) |v| {
        if (std.c.getenv(v)) |val| {
            if (val[0] != 0) return val;
        }
    }
    return "en_US.UTF-8";
}

fn getComposeLocale() [*c]const u8 {
    // xkbcommon compose file lookup is case-sensitive on the charset part.
    // Fedora sets LANG=en_US.utf8 but compose files live under en_US.UTF-8.
    // Always use canonical UTF-8 form for compose table.
    return "en_US.UTF-8";
}

fn initCompose(win: *XcbWindow) void {
    const locale = getComposeLocale();
    if (use_zig_dlopen) {
        // Under zig_dlopen, xkbcommon is a glibc .so — use _from_locale so it does
        // its own file I/O (glibc fopen). We can't pass musl's FILE* to glibc code.
        win.xkb_compose_table = xkb_compose_table_new_from_locale(
            win.xkb_ctx,
            locale,
            xkb.XKB_COMPOSE_COMPILE_NO_FLAGS,
        ) orelse {
            _ = stdio.printf("[vk_xcb] xkb_compose_table_new_from_locale('%s') failed\n", locale);
            return;
        };
    } else {
        const compose_path = "/usr/share/X11/locale/en_US.UTF-8/Compose";
        const file = stdio.fopen(compose_path, "r") orelse {
            _ = stdio.printf("[vk_xcb] compose: can't open %s\n", compose_path);
            return;
        };
        win.xkb_compose_table = xkb_compose_table_new_from_file(
            win.xkb_ctx,
            @ptrCast(file),
            locale,
            xkb.XKB_COMPOSE_FORMAT_TEXT_V1,
            xkb.XKB_COMPOSE_COMPILE_NO_FLAGS,
        ) orelse {
            _ = stdio.printf("[vk_xcb] xkb_compose_table_new_from_file('%s') failed\n", compose_path);
            _ = stdio.fclose(file);
            return;
        };
        _ = stdio.fclose(file);
    }
    win.xkb_compose_state = xkb_compose_state_new(
        win.xkb_compose_table,
        xkb.XKB_COMPOSE_STATE_NO_FLAGS,
    ) orelse {
        _ = stdio.printf("[vk_xcb] xkb_compose_state_new failed\n");
        xkb_compose_table_unref(win.xkb_compose_table);
        win.xkb_compose_table = null;
        return;
    };
}

fn setupXkbEvents(win: *XcbWindow) void {
    if (use_zig_dlopen and !loadXcbXkb()) return;
    // Subscribe to XKB new-keyboard-notify + map-notify + state-notify
    // so we can detect runtime layout changes
    const required_events: u16 = xcb.XCB_XKB_EVENT_TYPE_NEW_KEYBOARD_NOTIFY |
        xcb.XCB_XKB_EVENT_TYPE_MAP_NOTIFY |
        xcb.XCB_XKB_EVENT_TYPE_STATE_NOTIFY;
    const required_map_parts: u16 = xcb.XCB_XKB_MAP_PART_KEY_TYPES |
        xcb.XCB_XKB_MAP_PART_KEY_SYMS |
        xcb.XCB_XKB_MAP_PART_MODIFIER_MAP |
        xcb.XCB_XKB_MAP_PART_VIRTUAL_MODS |
        xcb.XCB_XKB_MAP_PART_VIRTUAL_MOD_MAP;
    const cookie = xcb_xkb_select_events_checked(
        win.connection,
        xcb.XCB_XKB_ID_USE_CORE_KBD,
        required_events,
        0, // clear
        required_events, // select_all
        required_map_parts, // affect_map
        required_map_parts, // map
        null, // details (only needed for per-key)
    );
    const err = xcb_request_check(win.connection, cookie);
    if (err) |e| {
        _ = stdio.printf("[vk_xcb] xcb_xkb_select_events failed (err=%d)\n", @as(c_int, e.*.error_code));
        xcb_free(e);
    }

    // Ask the X server to suppress autorepeat press/release pairs for this
    // connection. Without this, every held key generates a press event at
    // the system autorepeat rate (~30 Hz), and durian's dispatch fires the
    // bound action once per press — saturating the shmif event outqueue on
    // e.g. m1+=/m1+- font bumps with multiple terminals open. Upstream
    // arcan's SDL/x11 backends set this via XkbSetDetectableAutoRepeat;
    // durian's iostatem then provides the synthetic repeat for text input
    // and the like. One press → one bound action; held key is silent until
    // actual release.
    const pcf_flag: u32 = xcb.XCB_XKB_PER_CLIENT_FLAG_DETECTABLE_AUTO_REPEAT;
    const pcf_cookie = xcb_xkb_per_client_flags(
        win.connection,
        xcb.XCB_XKB_ID_USE_CORE_KBD,
        pcf_flag, // change mask
        pcf_flag, // value (bit set → enable)
        0, // ctrlsToChange
        0, // autoCtrls
        0, // autoCtrlsValues
    );
    var pcf_err: ?*xcb.xcb_generic_error_t = null;
    const pcf_reply = xcb_xkb_per_client_flags_reply(win.connection, pcf_cookie, &pcf_err);
    if (pcf_reply) |r| xcb_free(r);
    if (pcf_err) |e| {
        _ = stdio.printf("[vk_xcb] xcb_xkb_per_client_flags failed (err=%d) — autorepeat storms may reach dispatch\n", @as(c_int, e.*.error_code));
        xcb_free(e);
    }
}

fn reinitXkbFromDevice(win: *XcbWindow) void {
    const xconn: ?*xkb.xcb_connection_t = @ptrCast(win.connection);

    // Release old keymap/state but keep context
    if (win.xkb_state) |s| xkb_state_unref(s);
    if (win.xkb_keymap) |k| xkb_keymap_unref(k);
    win.xkb_state = null;
    win.xkb_keymap = null;

    win.xkb_keymap = xkb_x11_keymap_new_from_device(
        win.xkb_ctx,
        xconn,
        win.xkb_device_id,
        xkb.XKB_KEYMAP_COMPILE_NO_FLAGS,
    ) orelse {
        _ = stdio.printf("[vk_xcb] reinit: xkb_x11_keymap_new_from_device failed\n");
        return;
    };
    win.xkb_state = xkb_x11_state_new_from_device(
        win.xkb_keymap,
        xconn,
        win.xkb_device_id,
    );
    if (win.xkb_state == null) {
        _ = stdio.printf("[vk_xcb] reinit: xkb_x11_state_new_from_device failed\n");
        xkb_keymap_unref(win.xkb_keymap);
        win.xkb_keymap = null;
    }
}

fn initXkb(win: *XcbWindow) void {
    // Load xkbcommon base at runtime if using zig_dlopen (must use same allocator as xkbcommon-x11)
    if (use_zig_dlopen and !loadXkbBase()) {
        _ = stdio.printf("[vk_xcb] failed to load libxkbcommon.so.0, keyboard input disabled\n");
        return;
    }
    // Create context without default paths (Zig pkg has wrong compiled-in path)
    win.xkb_ctx = xkb_context_new(xkb.XKB_CONTEXT_NO_DEFAULT_INCLUDES) orelse {
        _ = stdio.printf("[vk_xcb] xkb_context_new failed\n");
        return;
    };
    // Add system XKB data path
    _ = xkb_context_include_path_append(win.xkb_ctx, "/usr/share/X11/xkb");

    // Load xkbcommon-x11 at runtime if needed
    if (use_zig_dlopen and !loadXkbX11()) {
        // Fall through to hardcoded fallback below
    } else {
        // Try xkb_x11: queries the actual compiled keymap from the X server.
        // This works correctly under Xwayland where _XKB_RULES_NAMES is unreliable.
        const xconn: ?*xkb.xcb_connection_t = @ptrCast(win.connection);
        var first_xkb_event: u8 = 0;
        if (xkb_x11_setup_xkb_extension(
            xconn,
            xkb.XKB_X11_MIN_MAJOR_XKB_VERSION,
            xkb.XKB_X11_MIN_MINOR_XKB_VERSION,
            xkb.XKB_X11_SETUP_XKB_EXTENSION_NO_FLAGS,
            null,
            null,
            &first_xkb_event,
            null,
        ) != 0) {
            win.xkb_event_base = first_xkb_event;
            win.xkb_device_id = xkb_x11_get_core_keyboard_device_id(xconn);
            if (win.xkb_device_id >= 0) {
                win.xkb_keymap = xkb_x11_keymap_new_from_device(
                    win.xkb_ctx,
                    xconn,
                    win.xkb_device_id,
                    xkb.XKB_KEYMAP_COMPILE_NO_FLAGS,
                );
                if (win.xkb_keymap != null) {
                    win.xkb_state = xkb_x11_state_new_from_device(
                        win.xkb_keymap,
                        xconn,
                        win.xkb_device_id,
                    );
                    if (win.xkb_state != null) {
                        initCompose(win);
                        setupXkbEvents(win);
                        return;
                    }
                    xkb_keymap_unref(win.xkb_keymap);
                    win.xkb_keymap = null;
                }
            }
        }
    }
    // Fallback: hardcoded layout (same as old behavior)
    var names: xkb.struct_xkb_rule_names = std.mem.zeroes(xkb.struct_xkb_rule_names);
    names.rules = "evdev";
    names.model = "pc105";
    names.layout = "us";
    win.xkb_keymap = xkb_keymap_new_from_names(
        win.xkb_ctx,
        &names,
        xkb.XKB_KEYMAP_COMPILE_NO_FLAGS,
    ) orelse {
        _ = stdio.printf("[vk_xcb] xkb_keymap_new_from_names failed\n");
        xkb_context_unref(win.xkb_ctx);
        win.xkb_ctx = null;
        return;
    };
    win.xkb_state = xkb_state_new(win.xkb_keymap) orelse {
        _ = stdio.printf("[vk_xcb] xkb_state_new failed\n");
        xkb_keymap_unref(win.xkb_keymap);
        xkb_context_unref(win.xkb_ctx);
        win.xkb_keymap = null;
        win.xkb_ctx = null;
        return;
    };
    initCompose(win);
}

fn deinitXkb(win: *XcbWindow) void {
    if (win.xkb_compose_state) |cs| xkb_compose_state_unref(cs);
    if (win.xkb_compose_table) |ct| xkb_compose_table_unref(ct);
    if (win.xkb_state) |s| xkb_state_unref(s);
    if (win.xkb_keymap) |k| xkb_keymap_unref(k);
    if (win.xkb_ctx) |c| xkb_context_unref(c);
    win.xkb_compose_state = null;
    win.xkb_compose_table = null;
    win.xkb_state = null;
    win.xkb_keymap = null;
    win.xkb_ctx = null;
}

pub fn createXcbWindow(w: u32, h: u32, title: [*:0]const u8) !XcbWindow {
    // Load XCB at runtime for static musl builds
    if (use_zig_dlopen and !loadXcb()) return error.XcbConnectFailed;

    // Connect to X server
    var screen_num: c_int = 0;
    const conn = xcb_connect(null, &screen_num) orelse return error.XcbConnectFailed;
    if (xcb_connection_has_error(conn) != 0) {
        xcb_disconnect(conn);
        return error.XcbConnectFailed;
    }

    // Get screen
    const setup = xcb_get_setup(conn);
    var iter = xcb_setup_roots_iterator(setup);
    var i: c_int = 0;
    while (i < screen_num) : (i += 1) {
        xcb_screen_next(&iter);
    }
    const screen = iter.data orelse {
        xcb_disconnect(conn);
        return error.XcbNoScreen;
    };

    // Create window
    const win = xcb_generate_id(conn);
    const event_mask: u32 = xcb.XCB_EVENT_MASK_STRUCTURE_NOTIFY |
        xcb.XCB_EVENT_MASK_KEY_PRESS |
        xcb.XCB_EVENT_MASK_KEY_RELEASE |
        xcb.XCB_EVENT_MASK_BUTTON_PRESS |
        xcb.XCB_EVENT_MASK_BUTTON_RELEASE |
        xcb.XCB_EVENT_MASK_POINTER_MOTION |
        xcb.XCB_EVENT_MASK_EXPOSURE;
    const values = [_]u32{event_mask};

    _ = xcb_create_window(
        conn,
        xcb.XCB_COPY_FROM_PARENT, // depth
        win,
        screen.*.root,
        0,
        0, // x, y
        @intCast(w),
        @intCast(h),
        0, // border
        xcb.XCB_WINDOW_CLASS_INPUT_OUTPUT,
        screen.*.root_visual,
        xcb.XCB_CW_EVENT_MASK,
        &values,
    );

    // bug 0010 (re-applied 2026-04-29): hide the X11 host pointer.
    // 1×1 depth-1 pixmap (zero-initialised by the server) used as
    // both source AND mask of an xcb_cursor — the resulting cursor
    // renders nothing.  XCB_CW_CURSOR only changes the cursor image
    // shown when the pointer is over arcan's window; it does NOT
    // grab the pointer.  If user reports flow disruption, the cause
    // is visual (can't see where mouse is when over arcan), not
    // capture — durian's software cursor still draws.
    const blank_pixmap = xcb_generate_id(conn);
    _ = xcb_create_pixmap(conn, 1, blank_pixmap, win, 1, 1);
    const blank_cursor = xcb_generate_id(conn);
    _ = xcb_create_cursor(conn, blank_cursor, blank_pixmap, blank_pixmap,
        0, 0, 0, 0, 0, 0, 0, 0);
    const cursor_values = [_]u32{blank_cursor};
    _ = xcb_change_window_attributes(conn, win,
        @as(u32, @intCast(xcb.XCB_CW_CURSOR)), &cursor_values);

    // Set window title
    _ = xcb_change_property(
        conn,
        xcb.XCB_PROP_MODE_REPLACE,
        win,
        xcb.XCB_ATOM_WM_NAME,
        xcb.XCB_ATOM_STRING,
        8,
        @intCast(std.mem.len(title)),
        title,
    );

    // Intern WM_DELETE_WINDOW for close handling.
    // Both atoms use only_if_exists=0 so they are created if absent —
    // using 1 for WM_PROTOCOLS caused silent failure when the atom had
    // not yet been interned by the window manager, skipping the
    // xcb_change_property call and leaving the close button inert.
    const proto_cookie = xcb_intern_atom(conn, 0, 12, "WM_PROTOCOLS");
    const delete_cookie = xcb_intern_atom(conn, 0, 16, "WM_DELETE_WINDOW");

    const proto_reply = xcb_intern_atom_reply(conn, proto_cookie, null);
    const delete_reply = xcb_intern_atom_reply(conn, delete_cookie, null);

    var wm_protocols: xcb.xcb_atom_t = 0;
    var wm_delete_window: xcb.xcb_atom_t = 0;

    if (proto_reply) |pr| {
        wm_protocols = pr.*.atom;
        xcb_free(pr);
    }
    if (delete_reply) |dr| {
        wm_delete_window = dr.*.atom;
        xcb_free(dr);
    }

    if (wm_protocols != 0 and wm_delete_window != 0) {
        _ = xcb_change_property(
            conn,
            xcb.XCB_PROP_MODE_REPLACE,
            win,
            wm_protocols,
            xcb.XCB_ATOM_ATOM,
            32,
            1,
            @ptrCast(&wm_delete_window),
        );
    } else {
        _ = stdio.printf("[vk_xcb] WARNING: WM_DELETE_WINDOW registration failed\n");
    }

    // Map (show) window
    _ = xcb_map_window(conn, win);
    _ = xcb_flush(conn);

    var xcb_win = XcbWindow{
        .connection = conn,
        .window = win,
        .screen = screen,
        .wm_delete_window = wm_delete_window,
        .wm_protocols = wm_protocols,
        .width = w,
        .height = h,
        .phy_width_mm = screen.*.width_in_millimeters,
        .phy_height_mm = screen.*.height_in_millimeters,
    };

    // Initialize xkbcommon for keyboard translation (queries X11 layout)
    initXkb(&xcb_win);

    // Initialise XInput2 for trackpad scroll (XWayland never synthesises
    // legacy core button 4/5 from Wayland axis events).
    initXInput2(&xcb_win);

    // Intern atoms used by the X11 CLIPBOARD bridge. Failures are
    // tolerated — set_selection_owner will silently no-op if atoms are 0.
    initClipboardAtoms(&xcb_win);

    return xcb_win;
}

/// Intern the four atoms we need for the CLIPBOARD bridge.
fn initClipboardAtoms(win: *XcbWindow) void {
    const Pair = struct { name: []const u8, dst: *xcb.xcb_atom_t };
    const pairs = [_]Pair{
        .{ .name = "CLIPBOARD", .dst = &win.atom_clipboard },
        .{ .name = "UTF8_STRING", .dst = &win.atom_utf8_string },
        .{ .name = "TARGETS", .dst = &win.atom_targets },
        .{ .name = "ARCAN_CLIP_DATA", .dst = &win.atom_arcan_clip_data },
    };
    for (pairs) |p| {
        const ck = xcb_intern_atom(win.connection, 0, @intCast(p.name.len), p.name.ptr);
        if (xcb_intern_atom_reply(win.connection, ck, null)) |r| {
            p.dst.* = r.atom;
            xcb_free(r);
        }
    }
}

pub fn createXcbSurface(
    vki: vk.InstanceWrapper,
    instance: vk.Instance,
    xcb_win: *const XcbWindow,
) !vk.SurfaceKHR {
    // vulkan-zig's xcb_connection_t is a different opaque type than @cImport's,
    // but both are just pointers to the same underlying C type — @ptrCast is safe.
    return vki.createXcbSurfaceKHR(instance, &.{
        .connection = @ptrCast(xcb_win.connection),
        .window = xcb_win.window,
    }, null) catch return error.XcbSurfaceCreateFailed;
}

fn pushEvent(xcb_win: *XcbWindow, ev: InputEvent) void {
    if (xcb_win.input_count < MAX_INPUT_EVENTS) {
        xcb_win.input_events[xcb_win.input_count] = ev;
        xcb_win.input_count += 1;
    }
}

/// Convert XCB modifier state to arcan ARKMOD bitmask
fn xcbModsToArkmod(xcb_state: u16) u16 {
    var mods: u16 = 0;
    if (xcb_state & 0x0001 != 0) mods |= 0x0001 | 0x0002; // Shift → ARKMOD_LSHIFT|RSHIFT
    if (xcb_state & 0x0002 != 0) mods |= 0x2000; // Lock → ARKMOD_CAPS
    if (xcb_state & 0x0004 != 0) mods |= 0x0040 | 0x0080; // Control → ARKMOD_LCTRL|RCTRL
    if (xcb_state & 0x0008 != 0) mods |= 0x0100 | 0x0200; // Mod1 (Alt) → ARKMOD_LALT|RALT
    if (xcb_state & 0x0010 != 0) mods |= 0x1000; // Mod2 (NumLock) → ARKMOD_NUM
    if (xcb_state & 0x0040 != 0) mods |= 0x0400 | 0x0800; // Mod4 (Super) → ARKMOD_LMETA|RMETA
    return mods;
}

pub fn pollEvents(xcb_win: *XcbWindow) void {
    // TLS switch: XCB calls go through glibc-loaded function pointers
    if (comptime use_zig_dlopen) zig_foreign_begin();
    defer if (comptime use_zig_dlopen) zig_foreign_end();

    xcb_win.input_count = 0;

    while (true) {
        const event = xcb_poll_for_event(xcb_win.connection) orelse break;
        const response_type = event.*.response_type & 0x7f;

        switch (response_type) {
            xcb.XCB_CONFIGURE_NOTIFY => {
                const cfg: *const xcb.xcb_configure_notify_event_t = @ptrCast(@alignCast(event));
                const new_w: u32 = cfg.width;
                const new_h: u32 = cfg.height;
                if (new_w != xcb_win.width or new_h != xcb_win.height) {
                    xcb_win.width = new_w;
                    xcb_win.height = new_h;
                    xcb_win.resize_pending = true;
                }
            },
            xcb.XCB_CLIENT_MESSAGE => {
                const msg: *const xcb.xcb_client_message_event_t = @ptrCast(@alignCast(event));
                if (msg.data.data32[0] == xcb_win.wm_delete_window) {
                    xcb_win.close_requested = true;
                }
            },
            xcb.XCB_SELECTION_REQUEST => {
                handleSelectionRequest(xcb_win, event);
            },
            xcb.XCB_SELECTION_NOTIFY => {
                handleSelectionNotify(xcb_win, event);
            },
            xcb.XCB_SELECTION_CLEAR => {
                // Some other client took CLIPBOARD ownership. Drop our cached
                // text so we don't keep serving stale data.
                if (xcb_win.clipboard_text) |buf| {
                    std.heap.c_allocator.free(buf);
                    xcb_win.clipboard_text = null;
                }
            },
            xcb.XCB_KEY_PRESS, xcb.XCB_KEY_RELEASE => {
                const key: *const xcb.xcb_key_press_event_t = @ptrCast(@alignCast(event));
                const x11_keycode: u32 = key.detail;
                const evdev_scancode: u16 = if (x11_keycode >= 8) @intCast(x11_keycode - 8) else 0;
                const pressed = (response_type == xcb.XCB_KEY_PRESS);

                var ie = InputEvent{
                    .kind = if (pressed) .key_press else .key_release,
                    .scancode = evdev_scancode,
                    .mods = xcbModsToArkmod(key.state),
                };

                // Use xkbcommon for keysym + UTF-8 translation
                if (xcb_win.xkb_state) |xkb_st| {
                    ie.keysym = xkb_state_key_get_one_sym(xkb_st, x11_keycode);

                    if (pressed) {
                        // Feed keysym through compose state for dead key handling
                        if (xcb_win.xkb_compose_state) |cs| {
                            _ = xkb_compose_state_feed(cs, ie.keysym);
                            const status = xkb_compose_state_get_status(cs);
                            switch (status) {
                                xkb.XKB_COMPOSE_COMPOSED => {
                                    // Compose sequence complete — use composed result
                                    ie.keysym = xkb_compose_state_get_one_sym(cs);
                                    _ = xkb_compose_state_get_utf8(cs, &ie.utf8, ie.utf8.len);
                                },
                                xkb.XKB_COMPOSE_COMPOSING => {
                                    // In the middle of a dead key sequence — suppress this key
                                    _ = xkb_state_update_key(
                                        xkb_st,
                                        x11_keycode,
                                        xkb.XKB_KEY_DOWN,
                                    );
                                    // Don't emit an event; skip to release handling
                                    xcb_free(event);
                                    continue;
                                },
                                xkb.XKB_COMPOSE_CANCELLED => {
                                    // Invalid sequence — reset and use raw keysym
                                    _ = xkb_state_key_get_utf8(xkb_st, x11_keycode, &ie.utf8, ie.utf8.len);
                                },
                                else => {
                                    // XKB_COMPOSE_NOTHING — not a compose sequence, use raw
                                    _ = xkb_state_key_get_utf8(xkb_st, x11_keycode, &ie.utf8, ie.utf8.len);
                                },
                            }
                        } else {
                            _ = xkb_state_key_get_utf8(xkb_st, x11_keycode, &ie.utf8, ie.utf8.len);
                        }
                    }

                    // Update xkb modifier state
                    _ = xkb_state_update_key(
                        xkb_st,
                        x11_keycode,
                        if (pressed) xkb.XKB_KEY_DOWN else xkb.XKB_KEY_UP,
                    );
                }

                pushEvent(xcb_win, ie);
            },
            xcb.XCB_BUTTON_PRESS, xcb.XCB_BUTTON_RELEASE => {
                const btn: *const xcb.xcb_button_press_event_t = @ptrCast(@alignCast(event));
                const pressed = (response_type == xcb.XCB_BUTTON_PRESS);

                pushEvent(xcb_win, .{
                    .kind = if (pressed) .button_press else .button_release,
                    .button = btn.detail,
                    .x = btn.event_x,
                    .y = btn.event_y,
                    .mods = xcbModsToArkmod(btn.state),
                });
            },
            xcb.XCB_MOTION_NOTIFY => {
                const motion: *const xcb.xcb_motion_notify_event_t = @ptrCast(@alignCast(event));
                pushEvent(xcb_win, .{
                    .kind = .motion,
                    .x = motion.event_x,
                    .y = motion.event_y,
                    .mods = xcbModsToArkmod(motion.state),
                });
            },
            xcb.XCB_GE_GENERIC => {
                // XInput2 events: response_type=35, extension byte must
                // match XInput's major opcode. Ignored when XI2 init failed.
                const ge: *const xcb.xcb_ge_generic_event_t = @ptrCast(@alignCast(event));
                if (xcb_win.xi_major_opcode == 0 or ge.extension != xcb_win.xi_major_opcode) {
                    // not our XI event — fall through (event will be freed below)
                } else switch (ge.event_type) {
                    xcb.XCB_INPUT_BUTTON_PRESS, xcb.XCB_INPUT_BUTTON_RELEASE => {
                        const btn: *const xcb.xcb_input_button_press_event_t = @ptrCast(@alignCast(event));
                        const pressed = (ge.event_type == xcb.XCB_INPUT_BUTTON_PRESS);
                        // event_x/y are FP1616 (i32, 16.16 fixed point); >> 16 → int pixels.
                        const ex: i16 = @truncate(@as(i32, btn.event_x) >> 16);
                        const ey: i16 = @truncate(@as(i32, btn.event_y) >> 16);
                        pushEvent(xcb_win, .{
                            .kind = if (pressed) .button_press else .button_release,
                            .button = @intCast(btn.detail & 0xFF),
                            .x = ex,
                            .y = ey,
                            .mods = xcbModsToArkmod(@truncate(btn.mods.effective)),
                        });
                    },
                    xcb.XCB_INPUT_MOTION => {
                        handleXiMotion(xcb_win, event);
                    },
                    else => {},
                }
            },
            else => {
                // Check for XKB extension events (map change, new keyboard, state notify)
                if (xcb_win.xkb_event_base != 0 and response_type == xcb_win.xkb_event_base) {
                    // XKB events use the first byte of the event data as xkbType
                    const xkb_event: [*]const u8 = @ptrCast(event);
                    const xkb_type = xkb_event[1]; // pad0 field holds the xkb event type
                    switch (xkb_type) {
                        xcb.XCB_XKB_NEW_KEYBOARD_NOTIFY, xcb.XCB_XKB_MAP_NOTIFY => {
                            reinitXkbFromDevice(xcb_win);
                        },
                        xcb.XCB_XKB_STATE_NOTIFY => {
                            // The X server's XKB state changed (modifiers, group/layout switch)
                            // Re-sync our xkb_state from the server
                            const xconn: ?*xkb.xcb_connection_t = @ptrCast(xcb_win.connection);
                            if (xcb_win.xkb_state) |old_state| {
                                if (xcb_win.xkb_keymap) |_| {
                                    const new_state = xkb_x11_state_new_from_device(
                                        xcb_win.xkb_keymap,
                                        xconn,
                                        xcb_win.xkb_device_id,
                                    );
                                    if (new_state) |ns| {
                                        xkb_state_unref(old_state);
                                        xcb_win.xkb_state = ns;
                                    }
                                }
                            }
                        },
                        else => {},
                    }
                }
            },
        }

        xcb_free(event);
    }
}

pub fn destroyXcbWindow(xcb_win: *XcbWindow) void {
    deinitXkb(xcb_win);
    _ = xcb_destroy_window(xcb_win.connection, xcb_win.window);
    xcb_disconnect(xcb_win.connection);
}
