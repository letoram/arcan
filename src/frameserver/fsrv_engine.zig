// fsrv_engine.zig — in-process frameserver set for the macOS arcan_vk link:
// the dispatch (frameserver_dispatch, called in the forked child by
// posix/launch.zig) plus the lash terminal (afsrv_terminal — cat9's host).
comptime {
    _ = @import("frameserver.zig");
    _ = @import("terminal_lash/entry.zig");
    // lash's lua REPL host (arcterm_luacli_run lives here)
    _ = @import("terminal/default/cli_lua.zig");
}
