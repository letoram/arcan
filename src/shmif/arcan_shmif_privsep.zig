// Zig reimplementation of arcan_shmif_privsep.c
// Drop-in C-ABI-compatible replacement for privsep functions.
//
// Exports: arcan_shmif_privsep, shmifint_privsep_mark_fd
//
//
const std = @import("std");
const builtin = @import("builtin");
const c = @import("shmif_types");

extern "c" fn unveil(path: ?[*:0]const u8, permissions: ?[*:0]const u8) c_int;
extern "c" fn pledge(promises: ?[*:0]const u8, execpromises: ?[*:0]const u8) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
extern "c" fn prctl(option: c_int, arg2: c_ulong, arg3: c_ulong, arg4: c_ulong, arg5: c_ulong) c_int;

const PR_SET_NO_NEW_PRIVS: c_int = 38;

// shmifint_privsep_mark_fd
// On Linux this is a stub (just returns fd). FreeBSD uses capsicum
// (handled by C version). OpenBSD doesn't need fd tagging.

export fn shmifint_privsep_mark_fd(fd: c_int, _: c_int) c_int {
    return fd;
}

// arcan_shmif_privsep

export fn arcan_shmif_privsep(
    _: ?*c.struct_arcan_shmif_cont,
    pledge_str: ?[*:0]const u8,
    nodes: [*c]?*c.struct_shmif_privsep_node,
    _: c_int,
) void {
    if (comptime builtin.os.tag == .openbsd) {
        var i: usize = 0;
        while (nodes[i]) |node| : (i += 1) {
            _ = unveil(node.path, node.perm);
        }

        _ = unveil(null, null);

        if (pledge_str) |ps| {
            var resolved: ?[*:0]const u8 = ps;

            if (c.strcmp(ps, "shmif") == 0 or
                c.strcmp(ps, "decode") == 0 or
                c.strcmp(ps, "encode") == 0 or
                c.strcmp(ps, "a12-srv") == 0 or
                c.strcmp(ps, "a12-cl") == 0)
            {
                resolved = c.SHMIF_PLEDGE_PREFIX;
            } else if (c.strcmp(ps, "minimal") == 0) {
                resolved = "stdio";
            } else if (c.strcmp(ps, "minimalfd") == 0) {
                resolved = "stdio sendfd recvfd";
            }

            _ = pledge(resolved, null);
        }
    } else if (comptime builtin.os.tag == .linux) {
        if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0 or getenv("ARCAN_SHMIF_DEBUG") != null) {
            return;
        }

        // ignore landlock for now if we have an allowlist
        if (nodes != null and nodes[0] != null)
            return;

        // landlock ABI version probe
        const SYS_landlock_create_ruleset = 444;
        const SYS_landlock_restrict_self = 446;
        const LANDLOCK_CREATE_RULESET_VERSION: c_ulong = 1 << 0;

        const abi_raw = std.os.linux.syscall3(
            @enumFromInt(SYS_landlock_create_ruleset),
            0,
            0,
            LANDLOCK_CREATE_RULESET_VERSION,
        );
        const abi: isize = @bitCast(abi_raw);
        if (abi <= 0) return;

        // landlock_ruleset_attr: fs access mask based on ABI version
        // (from landlock-examples, forward-compatible)
        const LandlockRulesetAttr = extern struct {
            handled_access_fs: u64 = 0,
            handled_access_net: u64 = 0,
        };

        const attr_table = [_]LandlockRulesetAttr{
            .{}, // index 0 unused
            .{ .handled_access_fs = (1 << 13) - 1 }, // ABI 1
            .{ .handled_access_fs = (1 << 14) - 1 }, // ABI 2
            .{ .handled_access_fs = (1 << 15) - 1 }, // ABI 3
            .{ .handled_access_fs = (1 << 15) - 1, .handled_access_net = (1 << 2) - 1 }, // ABI 4
            .{ .handled_access_fs = (1 << 16) - 1, .handled_access_net = (1 << 2) - 1 }, // ABI 5
        };

        const clamped_abi: usize = @intCast(@min(abi, attr_table.len - 1));
        const attr = attr_table[clamped_abi];

        const ruleset_fd_raw = std.os.linux.syscall3(
            @enumFromInt(SYS_landlock_create_ruleset),
            @intFromPtr(&attr),
            @sizeOf(LandlockRulesetAttr),
            0,
        );
        const ruleset_fd: isize = @bitCast(ruleset_fd_raw);
        if (ruleset_fd < 0) return;

        const res_raw = std.os.linux.syscall2(
            @enumFromInt(SYS_landlock_restrict_self),
            @as(usize, @bitCast(ruleset_fd)),
            0,
        );
        _ = close(@intCast(ruleset_fd));
        _ = res_raw;
    }
    // else: no-op for other platforms
}
