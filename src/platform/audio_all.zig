// audio_all.zig — OpenAL audio platform aggregate for the arcan_vk engine
// link: the platform_audio_* implementation plus the runtime-dlopen AL/ALC
// shim it links against. Rooted at src/platform/ so both subdirs resolve.
comptime {
    _ = @import("audio/openal.zig");
    _ = @import("dl/dl_openal.zig");
    // drm dlopen shim — psep_open/vk_gbm_kms reference drm* symbols; the shim
    // resolves them at runtime (and no-ops gracefully when libdrm is absent,
    // which is always the case on macOS).
    _ = @import("dl/dl_drm.zig");
}
