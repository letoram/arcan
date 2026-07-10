// Standalone-arcan-net-exe entry point.
// net.zig exports `arcan_net_main` (renamed from `main` so the a12 archive
// can be linked into `may` without symbol collision). The legacy standalone
// `arcan-net` exe target still needs a C `main` symbol — this file provides
// exactly that. Built ONLY into createArcanNet's exe; NOT linked into may.

extern fn arcan_net_main(argc: c_int, argv: [*c][*c]u8) c_int;

export fn main(argc: c_int, argv: [*c][*c]u8) c_int {
    return arcan_net_main(argc, argv);
}
