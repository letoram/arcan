// shmif_engine.zig — shmif root for the arcan_vk engine link: the full client
// aggregate plus the server-side TUI rasterizer pieces the engine references
// (tui_screen_tpack* from core/screen.zig, tui_pixelfont_* from
// raster/pixelfont.zig).
comptime {
    _ = @import("shmif_all.zig");
    _ = @import("tui/tui.zig");
    _ = @import("tui/core/screen.zig");
    _ = @import("tui/core/setup.zig");
    _ = @import("tui/core/input.zig");
    _ = @import("tui/core/dispatch.zig");
    _ = @import("tui/core/clipboard.zig");
    _ = @import("tui/raster/pixelfont.zig");
    _ = @import("tui/raster/font_data.zig");
    _ = @import("tui/raster/fontmgmt.zig");
    // tui/raster/raster.zig is omitted: the engine's arcan_raster.zig exports
    // the same tui_raster_* C surface (they'd collide).
    // debugif/a11y are omitted from shmif_all (client-only links); the engine
    // link has the server side present, so include the real implementations
    // plus the shmifsrv server API and the copywnd widget they use.
    _ = @import("arcan_shmif_debugif.zig");
    _ = @import("arcan_shmif_a11y.zig");
    _ = @import("arcan_shmif_server.zig");
    _ = @import("tui/widgets/copywnd.zig");
    // the tui↔lua bridge (ltui_inherit — lash/cat9 cells run on this)
    _ = @import("tui/lua/tui_lua.zig");
    _ = @import("tui/lua/tui_popen.zig");
    _ = @import("tui/lua/tui_lua_glob.zig");
    // widget set the bridge binds (readline/listwnd/bufferwnd/...)
    _ = @import("tui/widgets/bufferwnd.zig");
    _ = @import("tui/widgets/linewnd.zig");
    _ = @import("tui/widgets/listwnd.zig");
    _ = @import("tui/widgets/readline.zig");
}
