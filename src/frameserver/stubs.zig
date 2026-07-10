//! Stubs for upstream C-side externs that the frameserver archetypes
//! reach for (ffmpeg, libpng-via-c, upstream a12.c remoting client).
//! We don't compile any C in may, so these are provided as Zig exports
//! that emit `last_words("feature not built")` and return failure.
//!
//! When a real Zig port lands (e.g. an a12 remoting client built on
//! liba12.a, or a ffmpeg binding for decode_av), delete the matching
//! stub here and let the new symbol take over.

const shmif = @import("shmif_types");

extern "c" fn arcan_shmif_last_words(
    ctx: ?*shmif.struct_arcan_shmif_cont,
    msg: [*c]const u8,
) void;

// decode_av — invoked by decode.zig when ARCAN_ARG selects audio/video
// playback (ffmpeg/libav backend in upstream C).
export fn decode_av(
    cont: ?*shmif.struct_arcan_shmif_cont,
    args: ?*shmif.struct_arg_arr,
) callconv(.c) c_int {
    _ = args;
    arcan_shmif_last_words(cont, "decode_av: ffmpeg backend not built into may");
    return 1;
}

// encode.zig externs — upstream C provides these via a12.c +
// encode_ffmpeg.c + encode_presets.c.
export fn a12_serv_run(
    args: ?*shmif.struct_arg_arr,
    cont: shmif.struct_arcan_shmif_cont,
) callconv(.c) c_int {
    _ = args;
    var c_mut = cont;
    arcan_shmif_last_words(&c_mut, "a12_serv_run: encode-side a12 server not built");
    return 1;
}

// png_stream_run is provided by src/frameserver/encode/default/img.zig
// (the real impl), so no stub here.

export fn ffmpeg_run(
    args: ?*shmif.struct_arg_arr,
    cont: ?*shmif.struct_arcan_shmif_cont,
) callconv(.c) c_int {
    _ = args;
    arcan_shmif_last_words(cont, "ffmpeg_run: ffmpeg backend not built into may");
    return 1;
}

// remoting.zig extern — upstream C provides via a12.c.
export fn run_a12(
    cont: ?*shmif.struct_arcan_shmif_cont,
    args: ?*shmif.struct_arg_arr,
) callconv(.c) c_int {
    _ = args;
    arcan_shmif_last_words(cont, "run_a12: remoting a12 client not built (use afsrv_net)");
    return 1;
}
