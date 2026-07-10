// plat_engine.zig — full posix platform aggregate for the arcan_vk engine
// link (superset of plat_all.zig, which only serves standalone shmif clients;
// link one or the other, never both — duplicate exports otherwise).
comptime {
    _ = @import("posix/appl.zig");
    _ = @import("posix/base64.zig");
    _ = @import("posix/config.zig");
    _ = @import("posix/dbpath.zig");
    _ = @import("posix/fdpassing_nonblock.zig");
    _ = @import("posix/fdscan.zig");
    _ = @import("posix/fmt_open.zig");
    _ = @import("posix/frameserver.zig");
    _ = @import("posix/fsrv_guard.zig");
    _ = @import("posix/glob.zig");
    _ = @import("posix/launch.zig");
    _ = @import("posix/map_resource.zig");
    _ = @import("posix/mem.zig");
    _ = @import("posix/namespace.zig");
    _ = @import("posix/paths.zig");
    _ = @import("posix/prodthrd.zig");
    _ = @import("posix/psep_open.zig");
    _ = @import("posix/random.zig");
    _ = @import("posix/resource_io.zig");
    _ = @import("posix/sem.zig");
    _ = @import("posix/shmemop.zig");
    _ = @import("posix/strip_traverse.zig");
    _ = @import("posix/sync.zig");
    _ = @import("posix/sync_helpers.zig");
    _ = @import("posix/tempfile.zig");
    _ = @import("posix/time.zig");
    _ = @import("posix/warning.zig");
    _ = @import("stub/setproctitle.zig");
}
