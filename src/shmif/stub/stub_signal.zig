// Pure-Zig replacement for src/shmif/stub/stub_signal.c — ext-signal stub
// exported by libarcan_shmif_ext.a. Always returns -1 (no-op stub used when
// arcan is built without EGL/GL ext signalling).

export fn arcan_shmifext_signal(
    con: ?*anyopaque,
    display: usize,
    mask: c_int,
    tex_id: usize,
    ...,
) callconv(.c) c_int {
    _ = con;
    _ = display;
    _ = mask;
    _ = tex_id;
    return -1;
}
