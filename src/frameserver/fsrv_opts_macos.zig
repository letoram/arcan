// fsrv_opts for the macOS arcan_vk build (stands in for the build.zig
// b.addOptions module). Terminal (lash/cat9, pure Zig) only — the other
// archetypes need ffmpeg/a12/ghostty deps not yet ported.
pub const is_chainloader = false;
pub const default_mode: ?[]const u8 = "terminal";
pub const enable_avfeed = false;
pub const enable_bun = false;
pub const enable_decode = false;
pub const enable_encode = false;
pub const enable_game = false;
pub const enable_net = false;
pub const enable_probe = false;
pub const enable_remoting = false;
pub const enable_terminal = true;
