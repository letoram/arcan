// Stub H264 decoder — compiled in when `-Dwith_ffmpeg=false` (the default).
// The three C-ABI entry points match h264_decode.zig exactly; they always
// report "no decoder available", so a12_decode's caller falls back to the
// stream_fail + STEPFRAME-kick path.

pub export fn a12_h264_setup(chid: u8) bool {
    _ = chid;
    return false;
}

pub export fn a12_h264_decode(
    chid: u8,
    data: [*]const u8,
    data_sz: usize,
    out_bgra: [*]u8,
    out_pitch: c_int,
    out_w: c_int,
    out_h: c_int,
) c_int {
    _ = chid;
    _ = data;
    _ = data_sz;
    _ = out_bgra;
    _ = out_pitch;
    _ = out_w;
    _ = out_h;
    return -1;
}

pub export fn a12_h264_free(chid: u8) void {
    _ = chid;
}
