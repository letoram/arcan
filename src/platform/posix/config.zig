// Pure Zig port of posix/config.c — platform_config_lookup().
// Returns a function pointer that looks up config keys:
// first in env vars (ARCAN_KEY), then in the arcan DB.

const std = @import("std");

const c = struct {
    extern fn getenv(name: [*c]const u8) [*c]u8;
    extern fn strdup(s: [*c]const u8) [*c]u8;
    extern fn snprintf(buf: [*c]u8, size: usize, fmt: [*c]const u8, ...) callconv(.c) c_int;
};

extern fn arcan_db_get_shared(appl: *[*c]const u8) ?*anyopaque;
extern fn arcan_db_appl_val(dbh: ?*anyopaque, appl: [*c]const u8, key: [*c]const u8) [*c]u8;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;

const token: usize = 0xdeadbabe;

const CfgLookupFun = *const fn (
    key: [*c]const u8,
    ind: c_ushort,
    val: ?*[*c]u8,
    tag: usize,
) callconv(.c) bool;

fn lookup(
    key: [*c]const u8,
    ind: c_ushort,
    val: ?*[*c]u8,
    tag: usize,
) callconv(.c) bool {
    if (key == null or tag != token or ind > 0) {
        if (val) |v| v.* = null;
        return false;
    }

    // Build "ARCAN_<KEY>" (uppercased) in a fixed buffer.
    // Max key length ~256 + "ARCAN_" prefix + NUL = 280 bytes.
    var tmpbuf: [280]u8 = undefined;

    if (ind > 0) {
        _ = c.snprintf(&tmpbuf, tmpbuf.len, "ARCAN_%s_%u", key, @as(c_uint, ind));
    } else {
        _ = c.snprintf(&tmpbuf, tmpbuf.len, "ARCAN_%s", key);
    }

    // Uppercase in-place
    for (&tmpbuf) |*ch| {
        if (ch.* == 0) break;
        if (ch.* >= 'a' and ch.* <= 'z') ch.* -= 32;
    }

    var test_val: [*c]u8 = c.getenv(&tmpbuf);
    if (test_val != null) {
        if (val) |v| v.* = c.strdup(test_val);
    }

    // Fallback to database config in arcan appl-space
    if (test_val == null) {
        var appl: [*c]const u8 = null;
        const dbh = arcan_db_get_shared(&appl);
        if (ind > 0) {
            _ = c.snprintf(&tmpbuf, tmpbuf.len, "%s_%u", key, @as(c_uint, ind));
        } else {
            _ = c.snprintf(&tmpbuf, tmpbuf.len, "%s", key);
        }
        test_val = arcan_db_appl_val(dbh, appl, &tmpbuf);
        if (test_val != null) {
            if (val) |v| {
                v.* = test_val;
            }
        } else {
            arcan_mem_free(test_val);
        }
    }

    return test_val != null;
}

export fn platform_config_lookup(tag: ?*usize) ?CfgLookupFun {
    if (tag) |t| {
        t.* = token;
        return lookup;
    }
    return null;
}
