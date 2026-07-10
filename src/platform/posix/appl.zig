// Pure Zig port of posix/appl.c — zero C helpers.
// Application loader: verify and load appl (Lua script) by ID.

const std = @import("std");
const arcan = @import("arcan");

const c = struct {
    extern fn isalnum(c_arg: c_int) c_int;
    extern fn strdup(s: [*c]const u8) [*c]u8;
    extern fn free(ptr: ?*anyopaque) void;
    extern fn strcmp(a: [*c]const u8, b: [*c]const u8) c_int;
    extern fn strncmp(a: [*c]const u8, b: [*c]const u8, n: usize) c_int;
    extern fn strlen(s: [*c]const u8) usize;
    extern fn dirname(path: [*c]u8) [*c]u8;
    extern fn basename(path: [*c]u8) [*c]u8;
};

var appl_len: usize = 0;
var g_appl_id: [*c]const u8 = "#appl not initialized";
var appl_script: [*c]const u8 = null;

export fn arcan_verifyload_appl(appl_id: [*c]const u8, errc: *[*c]const u8) bool {
    if (appl_id == null) {
        errc.* = "no application specified";
        return false;
    }
    var app_len = c.strlen(appl_id);
    if (app_len == 0) {
        errc.* = "no application specified";
        return false;
    }

    var base: [*c]u8 = c.strdup(appl_id);
    var expand = true;

    if (appl_id[0] == '/' or appl_id[0] == '\\' or appl_id[0] == '.') {
        var work = c.strdup(base);
        const dir = c.strdup(c.dirname(work));
        c.free(work);

        work = c.strdup(base);
        c.free(base);
        base = c.strdup(c.basename(work));
        c.free(work);

        arcan.arcan_override_namespace(appl_id, arcan.RESOURCE_APPL);
        arcan.arcan_softoverride_namespace(appl_id, arcan.RESOURCE_APPL_TEMP);
        arcan.arcan_softoverride_namespace(dir, arcan.RESOURCE_SYS_APPLBASE);
        arcan.arcan_softoverride_namespace(dir, arcan.RESOURCE_SYS_APPLSTORE);

        c.free(dir);
        expand = false;
    }

    app_len = c.strlen(base);
    for (0..app_len) |i| {
        const ch: c_int = @intCast(base[i]);
        if (c.isalnum(ch) == 0 and base[i] != '_') {
            errc.* = "invalid character in appl_id (only a..Z _ 0..9 allowed)";
            return false;
        }
    }

    if (expand) {
        var dir = arcan.arcan_expand_resource(base, arcan.RESOURCE_SYS_APPLBASE);
        if (dir == null) {
            errc.* = "missing application base";
            c.free(base);
            return false;
        }
        arcan.arcan_override_namespace(dir, arcan.RESOURCE_APPL);
        arcan.arcan_mem_free(dir);

        dir = arcan.arcan_expand_resource(base, arcan.RESOURCE_SYS_APPLSTORE);
        if (dir == null) {
            errc.* = "missing application temporary store";
            c.free(base);
            return false;
        }
        arcan.arcan_override_namespace(dir, arcan.RESOURCE_APPL_TEMP);
        arcan.arcan_mem_free(dir);
    }

    const p_a = arcan.arcan_expand_resource("", arcan.RESOURCE_APPL_SHARED);
    var p_b = arcan.arcan_expand_resource("", arcan.RESOURCE_SYS_APPLSTATE);
    if (p_b == null) {
        arcan.arcan_softoverride_namespace(p_a, arcan.RESOURCE_APPL_STATE);
    } else if (p_a != null and c.strncmp(p_a, p_b, c.strlen(p_a)) == 0) {
        arcan.arcan_softoverride_namespace(p_b, arcan.RESOURCE_APPL_STATE);
    } else {
        arcan.arcan_mem_free(p_b);
        p_b = arcan.arcan_expand_resource(base, arcan.RESOURCE_SYS_APPLSTATE);
        arcan.arcan_softoverride_namespace(p_b, arcan.RESOURCE_APPL_STATE);
    }
    arcan.arcan_mem_free(p_a);
    arcan.arcan_mem_free(p_b);

    // Build "basename.lua" using bufPrintZ
    var wbuf: [256]u8 = undefined;
    const lua_name = std.fmt.bufPrintZ(&wbuf, "{s}.lua", .{
        @as([*c]const u8, base)[0..app_len],
    }) catch return false;
    _ = lua_name;

    const script_path = arcan.arcan_expand_resource(&wbuf, arcan.RESOURCE_APPL);
    if (script_path == null or !arcan.arcan_isfile(script_path)) {
        errc.* = "missing script matching appl_id (see appname/appname.lua)";
        arcan.arcan_mem_free(script_path);
        return false;
    }

    // Check for fonts directory
    var fbuf: [256]u8 = undefined;
    const font_name = std.fmt.bufPrintZ(&fbuf, "/fonts", .{}) catch null;
    _ = font_name;
    const font_path = arcan.arcan_expand_resource(&fbuf, arcan.RESOURCE_APPL);
    if (font_path != null) {
        if (arcan.arcan_isdir(font_path))
            arcan.arcan_override_namespace(font_path, arcan.RESOURCE_SYS_FONT);
        c.free(font_path);
    }

    if (c.strcmp(g_appl_id, "#appl not initialized") != 0)
        arcan.arcan_mem_free(@constCast(g_appl_id));

    g_appl_id = base;
    appl_len = app_len;
    appl_script = script_path;

    return true;
}

export fn arcan_appl_basesource(file: *bool) [*c]const u8 {
    file.* = true;
    return appl_script;
}

export fn arcan_appl_id() [*c]const u8 {
    return g_appl_id;
}

export fn arcan_appl_id_len() usize {
    return appl_len;
}
