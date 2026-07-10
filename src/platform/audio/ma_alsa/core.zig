// Pure-Zig miniaudio core stubs — slim, ALSA-only.
//
// This file replaces the @cImport-based sema_harness.zig. It hand-ports just
// enough of miniaudio's API surface for the ALSA backend (ma_alsa.zig) to
// compile and link without any C-side dependency on miniaudio. libasound is
// still loaded at runtime via dlopen (unchanged).
//
// Layout: a single `pub const c = struct { ... };` namespace mirroring what
// translate-c would have produced from miniaudio.h. ma_alsa.zig keeps its
// existing `harness.c.X` aliases unchanged.

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
// Cosmo-style runtime dlopen — strong symbols live in zig_dlopen.o, this
// module just provides extern decls. dl_alsa.zig is a separate object that
// exports per-symbol TLS-switched shims.
const dl = @import("dlopen");
extern fn dl_alsa_shim_lookup(name: [*:0]const u8) callconv(.c) ?*anyopaque;

pub const c = struct {

    // ============================================================
    // Section 1 — typedefs
    // ============================================================
    pub const ma_bool32 = u32;
    pub const ma_bool8 = u8;
    pub const ma_uint8 = u8;
    pub const ma_uint16 = u16;
    pub const ma_uint32 = u32;
    pub const ma_uint64 = u64;
    pub const ma_int32 = i32;
    pub const ma_int64 = i64;
    pub const ma_channel = u8;
    pub const ma_proc = ?*const fn () callconv(.c) void;
    pub const ma_ptr = ?*anyopaque;

    // ============================================================
    // Section 2 — enums (defined as plain c_int values to match
    // translate-c's lowering, since ma_alsa.zig uses
    // `@as(c_uint, @bitCast(ma_X))` casting on these)
    // ============================================================

    // ma_format
    pub const ma_format = c_uint;
    pub const ma_format_unknown: c_int = 0;
    pub const ma_format_u8: c_int = 1;
    pub const ma_format_s16: c_int = 2;
    pub const ma_format_s24: c_int = 3;
    pub const ma_format_s32: c_int = 4;
    pub const ma_format_f32: c_int = 5;
    pub const ma_format_count: c_int = 6;

    // ma_device_type (bitmask: playback=1, capture=2, duplex=3, loopback=4)
    pub const ma_device_type = c_uint;
    pub const ma_device_type_playback: c_int = 1;
    pub const ma_device_type_capture: c_int = 2;
    pub const ma_device_type_duplex: c_int = 3;
    pub const ma_device_type_loopback: c_int = 4;

    // ma_share_mode
    pub const ma_share_mode = c_uint;
    pub const ma_share_mode_shared: c_int = 0;
    pub const ma_share_mode_exclusive: c_int = 1;

    // ma_backend
    pub const ma_backend = c_uint;
    pub const ma_backend_wasapi: c_int = 0;
    pub const ma_backend_dsound: c_int = 1;
    pub const ma_backend_winmm: c_int = 2;
    pub const ma_backend_coreaudio: c_int = 3;
    pub const ma_backend_sndio: c_int = 4;
    pub const ma_backend_audio4: c_int = 5;
    pub const ma_backend_oss: c_int = 6;
    pub const ma_backend_pulseaudio: c_int = 7;
    pub const ma_backend_alsa: c_int = 8;
    pub const ma_backend_jack: c_int = 9;
    pub const ma_backend_aaudio: c_int = 10;
    pub const ma_backend_opensl: c_int = 11;
    pub const ma_backend_webaudio: c_int = 12;
    pub const ma_backend_custom: c_int = 13;
    pub const ma_backend_null: c_int = 14;

    // ma_device_state
    pub const ma_device_state = c_uint;
    pub const ma_device_state_uninitialized: c_int = 0;
    pub const ma_device_state_stopped: c_int = 1;
    pub const ma_device_state_started: c_int = 2;
    pub const ma_device_state_starting: c_int = 3;
    pub const ma_device_state_stopping: c_int = 4;

    // ma_log_level
    pub const ma_log_level = c_uint;
    pub const MA_LOG_LEVEL_DEBUG: c_int = 4;
    pub const MA_LOG_LEVEL_INFO: c_int = 3;
    pub const MA_LOG_LEVEL_WARNING: c_int = 2;
    pub const MA_LOG_LEVEL_ERROR: c_int = 1;

    // ma_result codes (ma_alsa.zig only references a handful — bring those plus
    // a few common ones).
    pub const ma_result = c_int;
    pub const MA_SUCCESS: c_int = 0;
    pub const MA_ERROR: c_int = -1;
    pub const MA_INVALID_ARGS: c_int = -2;
    pub const MA_INVALID_OPERATION: c_int = -3;
    pub const MA_OUT_OF_MEMORY: c_int = -4;
    pub const MA_OUT_OF_RANGE: c_int = -5;
    pub const MA_ACCESS_DENIED: c_int = -6;
    pub const MA_DOES_NOT_EXIST: c_int = -7;
    pub const MA_FORMAT_NOT_SUPPORTED: c_int = -100;
    pub const MA_DEVICE_TYPE_NOT_SUPPORTED: c_int = -101;
    pub const MA_SHARE_MODE_NOT_SUPPORTED: c_int = -102;
    pub const MA_NO_BACKEND: c_int = -103;
    pub const MA_NO_DEVICE: c_int = -104;
    pub const MA_API_NOT_FOUND: c_int = -105;
    pub const MA_INVALID_DEVICE_CONFIG: c_int = -106;
    pub const MA_DEVICE_NOT_INITIALIZED: c_int = -200;
    pub const MA_DEVICE_ALREADY_INITIALIZED: c_int = -201;
    pub const MA_DEVICE_NOT_STARTED: c_int = -202;
    pub const MA_DEVICE_NOT_STOPPED: c_int = -203;
    pub const MA_FAILED_TO_INIT_BACKEND: c_int = -300;
    pub const MA_FAILED_TO_OPEN_BACKEND_DEVICE: c_int = -301;
    pub const MA_FAILED_TO_START_BACKEND_DEVICE: c_int = -302;
    pub const MA_FAILED_TO_STOP_BACKEND_DEVICE: c_int = -303;

    // Channel positions (ma_channel — values are u8)
    pub const MA_CHANNEL_NONE: c_int = 0;
    pub const MA_CHANNEL_MONO: c_int = 1;
    pub const MA_CHANNEL_FRONT_LEFT: c_int = 2;
    pub const MA_CHANNEL_FRONT_RIGHT: c_int = 3;
    pub const MA_CHANNEL_FRONT_CENTER: c_int = 4;
    pub const MA_CHANNEL_LFE: c_int = 5;
    pub const MA_CHANNEL_BACK_LEFT: c_int = 6;
    pub const MA_CHANNEL_BACK_RIGHT: c_int = 7;
    pub const MA_CHANNEL_FRONT_LEFT_CENTER: c_int = 8;
    pub const MA_CHANNEL_FRONT_RIGHT_CENTER: c_int = 9;
    pub const MA_CHANNEL_BACK_CENTER: c_int = 10;
    pub const MA_CHANNEL_SIDE_LEFT: c_int = 11;
    pub const MA_CHANNEL_SIDE_RIGHT: c_int = 12;
    pub const MA_CHANNEL_TOP_CENTER: c_int = 13;
    pub const MA_CHANNEL_TOP_FRONT_LEFT: c_int = 14;
    pub const MA_CHANNEL_TOP_FRONT_CENTER: c_int = 15;
    pub const MA_CHANNEL_TOP_FRONT_RIGHT: c_int = 16;
    pub const MA_CHANNEL_TOP_BACK_LEFT: c_int = 17;
    pub const MA_CHANNEL_TOP_BACK_CENTER: c_int = 18;
    pub const MA_CHANNEL_TOP_BACK_RIGHT: c_int = 19;

    // Standard sample rate priorities (used by hw_params iteration)
    pub const ma_standard_sample_rate = c_uint;
    pub const ma_standard_sample_rate_48000: c_int = 48000;
    pub const ma_standard_sample_rate_44100: c_int = 44100;
    pub const ma_standard_sample_rate_min: c_int = 8000;
    pub const ma_standard_sample_rate_max: c_int = 384000;

    pub const ma_performance_profile = c_uint;
    pub const ma_performance_profile_low_latency: c_int = 0;
    pub const ma_performance_profile_conservative: c_int = 1;

    // Standard channel maps
    pub const ma_standard_channel_map = c_uint;
    pub const ma_standard_channel_map_microsoft: c_int = 0;
    pub const ma_standard_channel_map_alsa: c_int = 1;
    pub const ma_standard_channel_map_default: c_int = ma_standard_channel_map_microsoft;

    // ============================================================
    // Section 3 — global priority arrays (referenced as &arrays in body)
    // ============================================================
    pub const g_maFormatPriorities = [_]c_uint{
        @bitCast(ma_format_s16),
        @bitCast(ma_format_f32),
        @bitCast(ma_format_s32),
        @bitCast(ma_format_s24),
        @bitCast(ma_format_u8),
    };

    pub const g_maStandardSampleRatePriorities = [_]c_uint{
        48000, 44100, 32000, 24000, 22050, 88200, 96000,
        16000, 11025, 8000, 192000, 176400, 352800, 384000,
    };

    // ============================================================
    // Section 4 — small supporting structs
    // ============================================================
    pub const ma_allocation_callbacks = extern struct {
        pUserData: ?*anyopaque = null,
        onMalloc: ?*const fn (sz: usize, pUserData: ?*anyopaque) callconv(.c) ?*anyopaque = null,
        onRealloc: ?*const fn (p: ?*anyopaque, sz: usize, pUserData: ?*anyopaque) callconv(.c) ?*anyopaque = null,
        onFree: ?*const fn (p: ?*anyopaque, pUserData: ?*anyopaque) callconv(.c) void = null,
    };

    // ma_log — opaque handle. Logging in our standalone build is a stub that
    // routes through std.log.
    pub const ma_log = extern struct {
        pUserData: ?*anyopaque = null,
        // We don't need real fields — body code only takes &ma_log addresses.
        _opaque: [128]u8 align(8) = std.mem.zeroes([128]u8),
    };

    // ma_mutex — pthread_mutex_t-shaped; std.Thread.Mutex would also work but
    // we keep the C ABI-ish shape so the layout is predictable.
    // pthread_mutex_t — 48 bytes align 8 on glibc aarch64; 40 on musl. Use 48
    // (the glibc size) so the struct is layout-safe on either libc; the extra
    // 8 bytes on musl are simply unused.
    pub const ma_mutex = extern struct {
        _data: [48]u8 align(8) = std.mem.zeroes([48]u8),
    };

    // ============================================================
    // Section 5 — ALSA-specific structs (the inner of ma_context.unnamed_0
    // and ma_device.unnamed_0)
    // ============================================================
    pub const ma_context_alsa = extern struct {
        asoundSO: ?*anyopaque = null,
        // ALSA function pointer table (mirrors libasound's symbols). Kept as
        // ma_proc-typed slots — the body code casts them to per-prototype
        // typedefs at every call site.
        snd_pcm_open: ma_proc = null,
        snd_pcm_close: ma_proc = null,
        snd_pcm_hw_params_sizeof: ma_proc = null,
        snd_pcm_hw_params_any: ma_proc = null,
        snd_pcm_hw_params_set_format: ma_proc = null,
        snd_pcm_hw_params_set_format_first: ma_proc = null,
        snd_pcm_hw_params_get_format_mask: ma_proc = null,
        snd_pcm_hw_params_set_channels: ma_proc = null,
        snd_pcm_hw_params_set_channels_near: ma_proc = null,
        snd_pcm_hw_params_set_channels_minmax: ma_proc = null,
        snd_pcm_hw_params_set_rate_resample: ma_proc = null,
        snd_pcm_hw_params_set_rate: ma_proc = null,
        snd_pcm_hw_params_set_rate_near: ma_proc = null,
        snd_pcm_hw_params_set_rate_minmax: ma_proc = null,
        snd_pcm_hw_params_set_buffer_size_near: ma_proc = null,
        snd_pcm_hw_params_set_periods_near: ma_proc = null,
        snd_pcm_hw_params_set_access: ma_proc = null,
        snd_pcm_hw_params_get_format: ma_proc = null,
        snd_pcm_hw_params_get_channels: ma_proc = null,
        snd_pcm_hw_params_get_channels_min: ma_proc = null,
        snd_pcm_hw_params_get_channels_max: ma_proc = null,
        snd_pcm_hw_params_get_rate: ma_proc = null,
        snd_pcm_hw_params_get_rate_min: ma_proc = null,
        snd_pcm_hw_params_get_rate_max: ma_proc = null,
        snd_pcm_hw_params_get_buffer_size: ma_proc = null,
        snd_pcm_hw_params_get_periods: ma_proc = null,
        snd_pcm_hw_params_get_access: ma_proc = null,
        snd_pcm_hw_params_test_format: ma_proc = null,
        snd_pcm_hw_params_test_channels: ma_proc = null,
        snd_pcm_hw_params_test_rate: ma_proc = null,
        snd_pcm_hw_params: ma_proc = null,
        snd_pcm_sw_params_sizeof: ma_proc = null,
        snd_pcm_sw_params_current: ma_proc = null,
        snd_pcm_sw_params_get_boundary: ma_proc = null,
        snd_pcm_sw_params_set_avail_min: ma_proc = null,
        snd_pcm_sw_params_set_start_threshold: ma_proc = null,
        snd_pcm_sw_params_set_stop_threshold: ma_proc = null,
        snd_pcm_sw_params: ma_proc = null,
        snd_pcm_format_mask_sizeof: ma_proc = null,
        snd_pcm_format_mask_test: ma_proc = null,
        snd_pcm_get_chmap: ma_proc = null,
        snd_pcm_state: ma_proc = null,
        snd_pcm_prepare: ma_proc = null,
        snd_pcm_start: ma_proc = null,
        snd_pcm_drop: ma_proc = null,
        snd_pcm_drain: ma_proc = null,
        snd_pcm_reset: ma_proc = null,
        snd_device_name_hint: ma_proc = null,
        snd_device_name_get_hint: ma_proc = null,
        snd_card_get_index: ma_proc = null,
        snd_device_name_free_hint: ma_proc = null,
        snd_pcm_mmap_begin: ma_proc = null,
        snd_pcm_mmap_commit: ma_proc = null,
        snd_pcm_recover: ma_proc = null,
        snd_pcm_readi: ma_proc = null,
        snd_pcm_writei: ma_proc = null,
        snd_pcm_avail: ma_proc = null,
        snd_pcm_avail_update: ma_proc = null,
        snd_pcm_wait: ma_proc = null,
        snd_pcm_nonblock: ma_proc = null,
        snd_pcm_info: ma_proc = null,
        snd_pcm_info_sizeof: ma_proc = null,
        snd_pcm_info_get_name: ma_proc = null,
        snd_pcm_poll_descriptors: ma_proc = null,
        snd_pcm_poll_descriptors_count: ma_proc = null,
        snd_pcm_poll_descriptors_revents: ma_proc = null,
        snd_config_update_free_global: ma_proc = null,

        internalDeviceEnumLock: ma_mutex = .{},
        useVerboseDeviceEnumeration: ma_bool32 = 0,
    };

    pub const ma_device_alsa = extern struct {
        pPCMPlayback: ?*anyopaque = null,
        pPCMCapture: ?*anyopaque = null,
        pPollDescriptorsPlayback: ?*anyopaque = null,
        pPollDescriptorsCapture: ?*anyopaque = null,
        pollDescriptorCountPlayback: c_int = 0,
        pollDescriptorCountCapture: c_int = 0,
        wakeupfdPlayback: c_int = -1,
        wakeupfdCapture: c_int = -1,
        isUsingMMapPlayback: ma_bool8 = 0,
        isUsingMMapCapture: ma_bool8 = 0,
    };

    // ============================================================
    // Section 6 — ma_device_id, ma_device_info, ma_device_descriptor,
    // ma_device_config, ma_context_config, ma_backend_callbacks
    // ============================================================
    pub const ma_device_id = extern union {
        wasapi: [64]i16, // padding for largest variant
        dsound: [16]u8,
        winmm: c_uint,
        alsa: [256]u8,
        pulse: [256]u8,
        jack: c_int,
        coreaudio: [256]u8,
        sndio: [256]u8,
        audio4: [256]u8,
        oss: [64]u8,
        aaudio: i32,
        opensl: u32,
        webaudio: [32]u8,
        custom: extern union { i: c_int, s: [256]u8, p: ?*anyopaque },
        nullbackend: c_int,
    };

    pub const ma_device_native_data_format = extern struct {
        format: ma_format = ma_format_unknown,
        channels: ma_uint32 = 0,
        sampleRate: ma_uint32 = 0,
        flags: ma_uint32 = 0,
    };

    pub const MA_MAX_DEVICE_NAME_LENGTH = 255;
    pub const MA_MAX_CHANNELS = 254;

    pub const ma_device_info = extern struct {
        id: ma_device_id = std.mem.zeroes(ma_device_id),
        name: [MA_MAX_DEVICE_NAME_LENGTH + 1]u8 = std.mem.zeroes([MA_MAX_DEVICE_NAME_LENGTH + 1]u8),
        isDefault: ma_bool32 = 0,
        nativeDataFormatCount: ma_uint32 = 0,
        nativeDataFormats: [64]ma_device_native_data_format = std.mem.zeroes([64]ma_device_native_data_format),
    };

    pub const ma_device_descriptor = extern struct {
        pDeviceID: [*c]const ma_device_id = null,
        shareMode: ma_share_mode = ma_share_mode_shared,
        format: ma_format = ma_format_unknown,
        channels: ma_uint32 = 0,
        sampleRate: ma_uint32 = 0,
        channelMap: [MA_MAX_CHANNELS]ma_channel = std.mem.zeroes([MA_MAX_CHANNELS]ma_channel),
        periodSizeInFrames: ma_uint32 = 0,
        periodSizeInMilliseconds: ma_uint32 = 0,
        periodCount: ma_uint32 = 0,
    };

    pub const ma_device_config_alsa = extern struct {
        noMMap: ma_bool32 = 0,
        noAutoFormat: ma_bool32 = 0,
        noAutoChannels: ma_bool32 = 0,
        noAutoResample: ma_bool32 = 0,
        useVerboseDeviceEnumeration: ma_bool32 = 0,
    };

    pub const ma_device_config = extern struct {
        deviceType: ma_device_type = 0,
        sampleRate: ma_uint32 = 0,
        performanceProfile: ma_performance_profile = ma_performance_profile_low_latency,
        // ... many fields elided; the only ALSA-specific one is `alsa`:
        alsa: ma_device_config_alsa = .{},
    };

    pub const ma_context_config_alsa = extern struct {
        useVerboseDeviceEnumeration: ma_bool32 = 0,
    };

    pub const ma_context_config = extern struct {
        pLog: ?*ma_log = null,
        threadPriority: c_int = 0,
        threadStackSize: usize = 0,
        pUserData: ?*anyopaque = null,
        allocationCallbacks: ma_allocation_callbacks = .{},
        alsa: ma_context_config_alsa = .{},
    };

    // The ma_context first arg here is *opaque from this typedef's POV —
    // using `[*c]ma_context` would create a struct-layout dependency loop
    // (ma_context contains ma_backend_callbacks, which references this
    // callback type). Callers cast back as needed.
    pub const ma_enum_devices_callback_proc = ?*const fn (
        pContext: ?*anyopaque,
        deviceType: ma_device_type,
        pInfo: [*c]const ma_device_info,
        pUserData: ?*anyopaque,
    ) callconv(.c) ma_bool32;

    pub const ma_backend_callbacks = extern struct {
        onContextInit: ?*const fn ([*c]ma_context, [*c]const ma_context_config, [*c]ma_backend_callbacks) callconv(.c) ma_result = null,
        onContextUninit: ?*const fn ([*c]ma_context) callconv(.c) ma_result = null,
        onContextEnumerateDevices: ?*const fn ([*c]ma_context, ma_enum_devices_callback_proc, ?*anyopaque) callconv(.c) ma_result = null,
        onContextGetDeviceInfo: ?*const fn ([*c]ma_context, ma_device_type, [*c]const ma_device_id, [*c]ma_device_info) callconv(.c) ma_result = null,
        onDeviceInit: ?*const fn ([*c]ma_device, [*c]const ma_device_config, [*c]ma_device_descriptor, [*c]ma_device_descriptor) callconv(.c) ma_result = null,
        onDeviceUninit: ?*const fn ([*c]ma_device) callconv(.c) ma_result = null,
        onDeviceStart: ?*const fn ([*c]ma_device) callconv(.c) ma_result = null,
        onDeviceStop: ?*const fn ([*c]ma_device) callconv(.c) ma_result = null,
        onDeviceRead: ?*const fn ([*c]ma_device, ?*anyopaque, ma_uint32, [*c]ma_uint32) callconv(.c) ma_result = null,
        onDeviceWrite: ?*const fn ([*c]ma_device, ?*const anyopaque, ma_uint32, [*c]ma_uint32) callconv(.c) ma_result = null,
        onDeviceDataLoop: ?*const fn ([*c]ma_device) callconv(.c) ma_result = null,
        onDeviceDataLoopWakeup: ?*const fn ([*c]ma_device) callconv(.c) ma_result = null,
    };

    // ============================================================
    // Section 7 — ma_context, ma_device (slim, ALSA-only)
    // ============================================================
    pub const ma_context = extern struct {
        backend: ma_backend = ma_backend_alsa,
        callbacks: ma_backend_callbacks = .{},
        pLog: ?*ma_log = null,
        log: ma_log = .{},
        threadPriority: c_int = 0,
        threadStackSize: usize = 0,
        pUserData: ?*anyopaque = null,
        allocationCallbacks: ma_allocation_callbacks = .{},
        unnamed_0: extern union {
            alsa: ma_context_alsa,
        } = .{ .alsa = .{} },
    };

    pub const ma_device = extern struct {
        pContext: [*c]ma_context = null,
        type: ma_device_type = 0,
        unnamed_0: extern union {
            alsa: ma_device_alsa,
        } = .{ .alsa = .{} },
    };

    // ============================================================
    // Section 8 — helpers (kept callable from ma_alsa.zig as plain
    // functions, exported via `pub fn` inside the `c` namespace)
    // ============================================================

    // String helpers — thin wrappers over std.mem / std.c
    pub extern "c" fn strcmp(a: [*c]const u8, b: [*c]const u8) c_int;
    pub fn ma_strcmp(a: [*c]const u8, b: [*c]const u8) callconv(.c) c_int {
        return strcmp(a, b);
    }
    pub fn ma_strcpy_s(dst: [*c]u8, dstSize: usize, src: [*c]const u8) callconv(.c) c_int {
        if (dst == null or src == null or dstSize == 0) return MA_INVALID_ARGS;
        var i: usize = 0;
        while (i + 1 < dstSize and src[i] != 0) : (i += 1) dst[i] = src[i];
        dst[i] = 0;
        if (src[i] != 0) return MA_OUT_OF_RANGE;
        return MA_SUCCESS;
    }
    pub fn ma_strncpy_s(dst: [*c]u8, dstSize: usize, src: [*c]const u8, count: usize) callconv(.c) c_int {
        if (dst == null or src == null or dstSize == 0) return MA_INVALID_ARGS;
        const n = if (count == std.math.maxInt(usize)) std.mem.len(src) else count;
        const copyLen = if (n + 1 > dstSize) dstSize - 1 else n;
        var i: usize = 0;
        while (i < copyLen and src[i] != 0) : (i += 1) dst[i] = src[i];
        dst[i] = 0;
        return if (i == n or src[i] == 0) MA_SUCCESS else MA_OUT_OF_RANGE;
    }
    pub fn ma_strcat_s(dst: [*c]u8, dstSize: usize, src: [*c]const u8) callconv(.c) c_int {
        if (dst == null or src == null or dstSize == 0) return MA_INVALID_ARGS;
        var dstLen: usize = 0;
        while (dstLen < dstSize and dst[dstLen] != 0) : (dstLen += 1) {}
        if (dstLen == dstSize) return MA_INVALID_ARGS;
        return ma_strcpy_s(@as([*c]u8, dst + dstLen), dstSize - dstLen, src);
    }
    pub fn ma_itoa_s(value: c_int, dst: [*c]u8, dstSize: usize, radix: c_int) callconv(.c) c_int {
        if (dst == null or dstSize == 0) return MA_INVALID_ARGS;
        var buf: [32]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, "{}", .{value}) catch return MA_INVALID_ARGS;
        _ = radix;
        if (slice.len + 1 > dstSize) return MA_OUT_OF_RANGE;
        @memcpy(dst[0..slice.len], slice);
        dst[slice.len] = 0;
        return MA_SUCCESS;
    }

    // Allocation helpers — pass through the user's callbacks if provided,
    // otherwise fall back to std.c.{malloc, calloc, realloc, free}.
    pub fn ma_malloc(sz: usize, pCb: [*c]const ma_allocation_callbacks) callconv(.c) ?*anyopaque {
        if (pCb != null and pCb.*.onMalloc != null) return pCb.*.onMalloc.?(sz, pCb.*.pUserData);
        return std.c.malloc(sz);
    }
    pub fn ma_calloc(sz: usize, pCb: [*c]const ma_allocation_callbacks) callconv(.c) ?*anyopaque {
        const p = ma_malloc(sz, pCb);
        if (p) |raw| {
            @memset(@as([*]u8, @ptrCast(raw))[0..sz], 0);
        }
        return p;
    }
    pub fn ma_realloc(p: ?*anyopaque, sz: usize, pCb: [*c]const ma_allocation_callbacks) callconv(.c) ?*anyopaque {
        if (pCb != null and pCb.*.onRealloc != null) return pCb.*.onRealloc.?(p, sz, pCb.*.pUserData);
        return std.c.realloc(p, sz);
    }
    pub fn ma_free(p: ?*anyopaque, pCb: [*c]const ma_allocation_callbacks) callconv(.c) void {
        if (pCb != null and pCb.*.onFree != null) {
            pCb.*.onFree.?(p, pCb.*.pUserData);
            return;
        }
        std.c.free(p);
    }

    // dlopen helpers — route through zig_dlopen (cosmo-style, static-musl).
    // ma_dlsym FIRST checks our dl_alsa shim table — for known snd_* names we
    // return the address of a TLS-switching wrapper that lives in dl_alsa.o.
    // For anything else (which shouldn't happen for ALSA-only) we fall through
    // to the real zig_dlsym.
    const RTLD_NOW: c_int = 2;
    pub fn ma_dlopen(_pLog: ?*ma_log, path: [*c]const u8) callconv(.c) ?*anyopaque {
        _ = _pLog;
        // [*c]const u8 → [*:0]const u8 — both are null-terminated when used as
        // a path; cast through anyopaque is the standard bridge.
        const path_z: [*:0]const u8 = @ptrCast(path);
        return dl.zig_dlopen(path_z, RTLD_NOW);
    }
    pub fn ma_dlsym(_pLog: ?*ma_log, handle: ?*anyopaque, name: [*c]const u8) callconv(.c) ma_proc {
        _ = _pLog;
        const name_z: [*:0]const u8 = @ptrCast(name);
        if (dl_alsa_shim_lookup(name_z)) |shim| {
            return @ptrCast(@alignCast(shim));
        }
        const sym = dl.zig_dlsym(handle, name_z);
        return @ptrCast(@alignCast(sym));
    }
    pub fn ma_dlclose(_pLog: ?*ma_log, handle: ?*anyopaque) callconv(.c) void {
        _ = _pLog;
        _ = dl.zig_dlclose(handle);
    }

    // Logging stubs — route to std.log
    pub fn ma_log_post(_pLog: ?*ma_log, level: ma_uint32, message: [*c]const u8) callconv(.c) ma_result {
        _ = _pLog;
        const slice = std.mem.span(message);
        switch (level) {
            @as(c_uint, @intCast(MA_LOG_LEVEL_DEBUG)) => std.log.debug("{s}", .{slice}),
            @as(c_uint, @intCast(MA_LOG_LEVEL_INFO)) => std.log.info("{s}", .{slice}),
            @as(c_uint, @intCast(MA_LOG_LEVEL_WARNING)) => std.log.warn("{s}", .{slice}),
            else => std.log.err("{s}", .{slice}),
        }
        return MA_SUCCESS;
    }
    pub fn ma_log_postf(_pLog: ?*ma_log, level: ma_uint32, fmt: [*c]const u8, ...) callconv(.c) ma_result {
        _ = _pLog;
        _ = level;
        _ = fmt;
        // Variadic with C printf semantics is non-trivial in pure Zig — for
        // now we silently swallow formatted log messages. Real impl would
        // call vsnprintf via std.c.
        return MA_SUCCESS;
    }

    // Mutex helpers — std.Thread.Mutex would mismatch the extern struct
    // layout, so we use pthread directly via std.c.
    pub extern "c" fn pthread_mutex_init(m: *anyopaque, attr: ?*anyopaque) c_int;
    pub extern "c" fn pthread_mutex_lock(m: *anyopaque) c_int;
    pub extern "c" fn pthread_mutex_unlock(m: *anyopaque) c_int;
    pub extern "c" fn pthread_mutex_destroy(m: *anyopaque) c_int;
    pub fn ma_mutex_init(m: *ma_mutex) callconv(.c) ma_result {
        return if (pthread_mutex_init(@ptrCast(m), null) == 0) MA_SUCCESS else MA_ERROR;
    }
    pub fn ma_mutex_lock(m: *ma_mutex) callconv(.c) void {
        _ = pthread_mutex_lock(@ptrCast(m));
    }
    pub fn ma_mutex_unlock(m: *ma_mutex) callconv(.c) void {
        _ = pthread_mutex_unlock(@ptrCast(m));
    }
    pub fn ma_mutex_uninit(m: *ma_mutex) callconv(.c) void {
        _ = pthread_mutex_destroy(@ptrCast(m));
    }

    // Channel-map helpers
    pub fn ma_channel_map_init_standard(
        standard_map: ma_standard_channel_map,
        pChannelMap: [*c]ma_channel,
        channelMapCap: usize,
        channels: ma_uint32,
    ) callconv(.c) void {
        _ = standard_map;
        if (pChannelMap == null or channelMapCap == 0 or channels == 0) return;
        // Simple stereo/mono fill — close enough for a slim port.
        const positions = [_]ma_channel{
            @as(u8, @intCast(MA_CHANNEL_FRONT_LEFT)),
            @as(u8, @intCast(MA_CHANNEL_FRONT_RIGHT)),
            @as(u8, @intCast(MA_CHANNEL_FRONT_CENTER)),
            @as(u8, @intCast(MA_CHANNEL_LFE)),
            @as(u8, @intCast(MA_CHANNEL_BACK_LEFT)),
            @as(u8, @intCast(MA_CHANNEL_BACK_RIGHT)),
            @as(u8, @intCast(MA_CHANNEL_SIDE_LEFT)),
            @as(u8, @intCast(MA_CHANNEL_SIDE_RIGHT)),
        };
        const limit: usize = @min(channels, channelMapCap);
        var i: usize = 0;
        while (i < limit) : (i += 1) {
            pChannelMap[i] = if (i < positions.len) positions[i] else @as(u8, @intCast(MA_CHANNEL_NONE));
        }
    }
    pub fn ma_channel_map_copy(
        pOut: [*c]ma_channel,
        pIn: [*c]const ma_channel,
        channels: ma_uint32,
    ) callconv(.c) void {
        if (pOut == null or pIn == null) return;
        @memcpy(pOut[0..channels], pIn[0..channels]);
    }

    // Lifecycle / accessors
    pub fn ma_device_get_state(pDevice: [*c]const ma_device) callconv(.c) ma_uint32 {
        _ = pDevice;
        // Slim port — runtime state machine isn't implemented here. The body
        // calls this from poll loops; returning "started" keeps loops going.
        return @as(c_uint, @intCast(ma_device_state_started));
    }
    pub fn ma_device_get_log(pDevice: [*c]ma_device) callconv(.c) ?*ma_log {
        if (pDevice == null) return null;
        return ma_context_get_log(pDevice.*.pContext);
    }
    pub fn ma_context_get_log(pContext: [*c]ma_context) callconv(.c) ?*ma_log {
        if (pContext == null) return null;
        return if (pContext.*.pLog) |l| l else &pContext.*.log;
    }

    // Math/util
    pub fn ma_prev_power_of_2(x: ma_uint32) callconv(.c) ma_uint32 {
        if (x == 0) return 0;
        var v = x;
        v |= v >> 1;
        v |= v >> 2;
        v |= v >> 4;
        v |= v >> 8;
        v |= v >> 16;
        return v - (v >> 1);
    }
    pub fn ma_is_standard_sample_rate(rate: ma_uint32) callconv(.c) ma_bool32 {
        for (g_maStandardSampleRatePriorities) |sr| if (rate == sr) return 1;
        return 0;
    }
    pub fn ma_result_from_errno(err: c_int) callconv(.c) ma_result {
        const E = std.os.linux.E;
        return switch (@as(E, @enumFromInt(err))) {
            .SUCCESS => MA_SUCCESS,
            .NOENT => MA_DOES_NOT_EXIST,
            .ACCES, .PERM => MA_ACCESS_DENIED,
            .NOMEM => MA_OUT_OF_MEMORY,
            .BUSY => MA_DEVICE_NOT_INITIALIZED,
            .INVAL => MA_INVALID_ARGS,
            else => MA_ERROR,
        };
    }
    pub fn ma_calculate_buffer_size_in_frames_from_descriptor(
        pDescriptor: [*c]const ma_device_descriptor,
        nativeSampleRate: ma_uint32,
        performanceProfile: ma_performance_profile,
    ) callconv(.c) ma_uint32 {
        if (pDescriptor == null) return 0;
        if (pDescriptor.*.periodSizeInFrames != 0) return pDescriptor.*.periodSizeInFrames;
        if (pDescriptor.*.periodSizeInMilliseconds != 0) {
            const ms: u64 = pDescriptor.*.periodSizeInMilliseconds;
            const sr: u64 = if (nativeSampleRate != 0) nativeSampleRate else 48000;
            return @as(ma_uint32, @intCast((ms * sr) / 1000));
        }
        // Defaults — low_latency: 10ms @ native rate. conservative: 100ms.
        const ms: u64 = if (performanceProfile == ma_performance_profile_low_latency) 10 else 100;
        const sr: u64 = if (nativeSampleRate != 0) nativeSampleRate else 48000;
        return @as(ma_uint32, @intCast((ms * sr) / 1000));
    }

    // ============================================================
    // Section 9 — libc / linux bindings
    // ============================================================
    pub const struct_pollfd = extern struct {
        fd: c_int = -1,
        events: c_short = 0,
        revents: c_short = 0,
    };
    pub const nfds_t = c_ulong;

    pub extern "c" fn close(fd: c_int) c_int;
    pub extern "c" fn read(fd: c_int, buf: ?*anyopaque, count: usize) isize;
    pub extern "c" fn write(fd: c_int, buf: ?*const anyopaque, count: usize) isize;
    pub extern "c" fn poll(fds: [*c]struct_pollfd, nfds: nfds_t, timeout: c_int) c_int;
    pub extern "c" fn eventfd(initval: c_uint, flags: c_int) c_int;
    pub extern "c" fn __errno_location() *c_int;

    // libasound returns glibc-malloc'd strings (e.g. snd_device_name_get_hint).
    // Our static-musl `free` would assert on a foreign meta pointer, so we
    // route `free()` through a TLS-switched glibc-side free resolved at runtime.
    var libc_handle: ?*anyopaque = null;
    var p_glibc_free: ?*const fn (?*anyopaque) callconv(.c) void = null;
    pub fn free(p: ?*anyopaque) callconv(.c) void {
        if (p == null) return;
        if (p_glibc_free == null) {
            if (libc_handle == null) {
                libc_handle = dl.zig_dlopen("libc.so.6", 1) orelse
                    dl.zig_dlopen("libc.so", 1);
            }
            if (libc_handle) |h| {
                if (dl.zig_dlsym(h, "free")) |s| {
                    p_glibc_free = @ptrCast(@alignCast(s));
                }
            }
        }
        const f = p_glibc_free orelse return;
        dl.zig_foreign_begin();
        defer dl.zig_foreign_end();
        f(p);
    }
};
