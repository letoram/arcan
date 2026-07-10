// Standalone-arcan-exe entry point.
// arcan_main.zig exports `arcan_main` (renamed from `main` per MAY-110 step A
// so the engine archive can be linked into `may` without symbol collision).
// The legacy standalone `arcan` exe target still needs a C `main` symbol —
// this file provides exactly that. Built ONLY into createArcanVk's exe; NOT
// linked into may.

extern fn arcan_main(argc: c_int, argv: [*c][*c]u8) c_int;

export fn main(argc: c_int, argv: [*c][*c]u8) c_int {
    return arcan_main(argc, argv);
}
