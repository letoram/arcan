// Standalone-frameserver-exe entry point.
// frameserver.zig exports `frameserver_entry` (renamed from `main` so the
// frameserver object can be linked into a single-binary build without
// symbol collision). The standalone afsrv_* / arcan_frameserver exes still
// need a C `main` symbol — this file provides exactly that. Built ONLY
// into the standalone exes; NOT linked into single-binary builds.

extern fn frameserver_entry(argc: c_int, argv: [*c][*c]u8) c_int;

export fn main(argc: c_int, argv: [*c][*c]u8) c_int {
    return frameserver_entry(argc, argv);
}
