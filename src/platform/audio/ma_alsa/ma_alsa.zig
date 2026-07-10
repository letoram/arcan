const std = @import("std");
const harness = @import("core.zig");

const ma_bool32 = harness.c.ma_bool32;
const ma_uint32 = harness.c.ma_uint32;
const ma_channel = harness.c.ma_channel;
const ma_context = harness.c.ma_context;
const ma_device = harness.c.ma_device;
const ma_device_id = harness.c.ma_device_id;
const ma_device_type = harness.c.ma_device_type;
const ma_device_info = harness.c.ma_device_info;
const ma_device_config = harness.c.ma_device_config;
const ma_device_descriptor = harness.c.ma_device_descriptor;
const ma_context_config = harness.c.ma_context_config;
const ma_backend_callbacks = harness.c.ma_backend_callbacks;
const ma_format = harness.c.ma_format;
const ma_share_mode = harness.c.ma_share_mode;
const ma_result = harness.c.ma_result;
const ma_proc = harness.c.ma_proc;
const ma_enum_devices_callback_proc = harness.c.ma_enum_devices_callback_proc;
const struct_pollfd = harness.c.struct_pollfd;
const ma_uint64 = harness.c.ma_uint64;

// constants/enums
const MA_SUCCESS = harness.c.MA_SUCCESS;
const MA_CHANNEL_MONO = harness.c.MA_CHANNEL_MONO;
const ma_backend_alsa = harness.c.ma_backend_alsa;
const ma_device_type_playback = harness.c.ma_device_type_playback;
const ma_device_type_capture = harness.c.ma_device_type_capture;
const ma_device_type_duplex = harness.c.ma_device_type_duplex;
const ma_standard_sample_rate_min = harness.c.ma_standard_sample_rate_min;

// helpers
const ma_strcmp = harness.c.ma_strcmp;
const ma_strcpy_s = harness.c.ma_strcpy_s;
const ma_dlopen = harness.c.ma_dlopen;
const ma_mutex_lock = harness.c.ma_mutex_lock;
const ma_device_get_state = harness.c.ma_device_get_state;

// libc
const close = harness.c.close;
const poll = harness.c.poll;
const nfds_t = harness.c.nfds_t;

// More aliases (filled in after first sema pass)
const MA_CHANNEL_FRONT_LEFT = harness.c.MA_CHANNEL_FRONT_LEFT;
const ma_calloc = harness.c.ma_calloc;
const ma_context_get_log = harness.c.ma_context_get_log;
const ma_device_state_started = harness.c.ma_device_state_started;
const ma_dlclose = harness.c.ma_dlclose;
const ma_free = harness.c.ma_free;
const ma_log_post = harness.c.ma_log_post;
const ma_log_postf = harness.c.ma_log_postf;
const ma_mutex_unlock = harness.c.ma_mutex_unlock;
const MA_NO_DEVICE = harness.c.MA_NO_DEVICE;
const ma_share_mode_exclusive = harness.c.ma_share_mode_exclusive;
const ma_standard_sample_rate_max = harness.c.ma_standard_sample_rate_max;
const ma_strncpy_s = harness.c.ma_strncpy_s;
const g_maStandardSampleRatePriorities = &harness.c.g_maStandardSampleRatePriorities;
const MA_CHANNEL_FRONT_RIGHT = harness.c.MA_CHANNEL_FRONT_RIGHT;
const ma_device_get_log = harness.c.ma_device_get_log;
const ma_device_info_name_size = @sizeOf(@FieldType(harness.c.ma_device_info, "name"));
const ma_device_type_loopback = harness.c.ma_device_type_loopback;
const ma_format_s16 = harness.c.ma_format_s16;
const ma_itoa_s = harness.c.ma_itoa_s;
const MA_LOG_LEVEL_DEBUG = harness.c.MA_LOG_LEVEL_DEBUG;
const MA_LOG_LEVEL_ERROR = harness.c.MA_LOG_LEVEL_ERROR;
const ma_mutex_uninit = harness.c.ma_mutex_uninit;
const ma_result_from_errno = harness.c.ma_result_from_errno;
const ma_share_mode_shared = harness.c.ma_share_mode_shared;
const MA_CHANNEL_TOP_CENTER = harness.c.MA_CHANNEL_TOP_CENTER;
const ma_malloc = harness.c.ma_malloc;
const MA_CHANNEL_FRONT_RIGHT_CENTER = harness.c.MA_CHANNEL_FRONT_RIGHT_CENTER;
const MA_ERROR = harness.c.MA_ERROR;
const MA_CHANNEL_FRONT_LEFT_CENTER = harness.c.MA_CHANNEL_FRONT_LEFT_CENTER;
const ma_standard_channel_map_alsa = harness.c.ma_standard_channel_map_alsa;
const MA_CHANNEL_BACK_CENTER = harness.c.MA_CHANNEL_BACK_CENTER;
const ma_channel_map_init_standard = harness.c.ma_channel_map_init_standard;
const MA_CHANNEL_SIDE_RIGHT = harness.c.MA_CHANNEL_SIDE_RIGHT;
const ma_prev_power_of_2 = harness.c.ma_prev_power_of_2;
const ma_calculate_buffer_size_in_frames_from_descriptor = harness.c.ma_calculate_buffer_size_in_frames_from_descriptor;
const MA_CHANNEL_SIDE_LEFT = harness.c.MA_CHANNEL_SIDE_LEFT;
const MA_CHANNEL_LFE = harness.c.MA_CHANNEL_LFE;
const ma_format_u8 = harness.c.ma_format_u8;
const ma_format_unknown = harness.c.ma_format_unknown;
const MA_CHANNEL_FRONT_CENTER = harness.c.MA_CHANNEL_FRONT_CENTER;
const MA_DEVICE_NOT_STARTED = harness.c.MA_DEVICE_NOT_STARTED;
const ma_format_f32 = harness.c.ma_format_f32;
const MA_FORMAT_NOT_SUPPORTED = harness.c.MA_FORMAT_NOT_SUPPORTED;
const ma_mutex_init = harness.c.ma_mutex_init;
const __errno_location = harness.c.__errno_location;
const g_maFormatPriorities = &harness.c.g_maFormatPriorities;
const MA_CHANNEL_BACK_RIGHT = harness.c.MA_CHANNEL_BACK_RIGHT;
const ma_dlsym = harness.c.ma_dlsym;
const ma_format_s32 = harness.c.ma_format_s32;
const ma_realloc = harness.c.ma_realloc;
const free = harness.c.free;
const MA_CHANNEL_BACK_LEFT = harness.c.MA_CHANNEL_BACK_LEFT;
const MA_DEVICE_TYPE_NOT_SUPPORTED = harness.c.MA_DEVICE_TYPE_NOT_SUPPORTED;
const MA_FAILED_TO_OPEN_BACKEND_DEVICE = harness.c.MA_FAILED_TO_OPEN_BACKEND_DEVICE;
const ma_format_s24 = harness.c.ma_format_s24;
const ma_is_standard_sample_rate = harness.c.ma_is_standard_sample_rate;
const MA_LOG_LEVEL_WARNING = harness.c.MA_LOG_LEVEL_WARNING;
const MA_NO_BACKEND = harness.c.MA_NO_BACKEND;
const MA_OUT_OF_MEMORY = harness.c.MA_OUT_OF_MEMORY;
const ma_strcat_s = harness.c.ma_strcat_s;
const read = harness.c.read;
const write = harness.c.write;
const MA_CHANNEL_TOP_FRONT_LEFT = harness.c.MA_CHANNEL_TOP_FRONT_LEFT;
const MA_CHANNEL_TOP_FRONT_RIGHT = harness.c.MA_CHANNEL_TOP_FRONT_RIGHT;
const MA_CHANNEL_TOP_FRONT_CENTER = harness.c.MA_CHANNEL_TOP_FRONT_CENTER;
const ma_bool8 = harness.c.ma_bool8;
const eventfd = harness.c.eventfd;
const ma_device_id_alsa_size = @sizeOf(@FieldType(harness.c.ma_device_id, "alsa"));
const ma_ptr = harness.c.ma_ptr;
const MA_CHANNEL_TOP_BACK_LEFT = harness.c.MA_CHANNEL_TOP_BACK_LEFT;
const ma_channel_map_copy = harness.c.ma_channel_map_copy;
const MA_CHANNEL_TOP_BACK_RIGHT = harness.c.MA_CHANNEL_TOP_BACK_RIGHT;
const MA_CHANNEL_TOP_BACK_CENTER = harness.c.MA_CHANNEL_TOP_BACK_CENTER;

// Anonymous structs — cimport names them struct_unnamed_<N>; the number is
// stable per inclusion but not exported. Reach them via @FieldType.
const struct_unnamed_65 = @typeInfo(@FieldType(harness.c.ma_device_info, "nativeDataFormats")).array.child;
const struct_unnamed_17 = @FieldType(@FieldType(harness.c.ma_device, "unnamed_0"), "alsa");

// Macros that translate-c could not resolve — provide direct Zig equivalents.
fn ma_is_big_endian() callconv(.c) c_int {
    return @intFromBool(@import("builtin").cpu.arch.endian() == .big);
}
fn ma_is_little_endian() callconv(.c) c_int {
    return @intFromBool(@import("builtin").cpu.arch.endian() == .little);
}
fn ma_zero_memory_default(p: ?*anyopaque, sz: usize) callconv(.c) void {
    if (p) |ptr| @memset(@as([*]u8, @ptrCast(ptr))[0..sz], 0);
}

pub const ma_snd_pcm_uframes_t = c_ulong;
pub const ma_snd_pcm_sframes_t = c_long;
pub const ma_snd_pcm_stream_t = c_int;
pub const ma_snd_pcm_format_t = c_int;
pub const ma_snd_pcm_access_t = c_int;
pub const ma_snd_pcm_state_t = c_int;
pub const struct_ma_snd_pcm_t = opaque {};
pub const ma_snd_pcm_t = struct_ma_snd_pcm_t;
pub const struct_ma_snd_pcm_hw_params_t = opaque {};
pub const ma_snd_pcm_hw_params_t = struct_ma_snd_pcm_hw_params_t;
pub const struct_ma_snd_pcm_sw_params_t = opaque {};
pub const ma_snd_pcm_sw_params_t = struct_ma_snd_pcm_sw_params_t;
pub const struct_ma_snd_pcm_format_mask_t = opaque {};
pub const ma_snd_pcm_format_mask_t = struct_ma_snd_pcm_format_mask_t;
pub const struct_ma_snd_pcm_info_t = opaque {};
pub const ma_snd_pcm_info_t = struct_ma_snd_pcm_info_t;
pub const ma_snd_pcm_channel_area_t = extern struct {
    addr: ?*anyopaque = std.mem.zeroes(?*anyopaque),
    first: c_uint = std.mem.zeroes(c_uint),
    step: c_uint = std.mem.zeroes(c_uint),
};
pub const ma_snd_pcm_chmap_t = extern struct {
    channels: c_uint = std.mem.zeroes(c_uint),
    pos: [1]c_uint = std.mem.zeroes([1]c_uint),
};
pub const ma_snd_pcm_open_proc = ?*const fn ([*c]?*ma_snd_pcm_t, [*c]const u8, ma_snd_pcm_stream_t, c_int) callconv(.c) c_int;
pub const ma_snd_pcm_close_proc = ?*const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_sizeof_proc = ?*const fn () callconv(.c) usize;
pub const ma_snd_pcm_hw_params_any_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_set_format_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, ma_snd_pcm_format_t) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_set_format_first_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]ma_snd_pcm_format_t) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_get_format_mask_proc = ?*const fn (?*ma_snd_pcm_hw_params_t, ?*ma_snd_pcm_format_mask_t) callconv(.c) void;
pub const ma_snd_pcm_hw_params_set_channels_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, c_uint) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_set_channels_near_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]c_uint) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_set_channels_minmax_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_uint) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_set_rate_resample_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, c_uint) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_set_rate_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, c_uint, c_int) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_set_rate_near_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_set_rate_minmax_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_set_buffer_size_near_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]ma_snd_pcm_uframes_t) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_set_periods_near_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_set_access_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, ma_snd_pcm_access_t) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_get_format_proc = ?*const fn (?*const ma_snd_pcm_hw_params_t, [*c]ma_snd_pcm_format_t) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_get_channels_proc = ?*const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_get_channels_min_proc = ?*const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_get_channels_max_proc = ?*const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_get_rate_proc = ?*const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_get_rate_min_proc = ?*const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_get_rate_max_proc = ?*const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_get_buffer_size_proc = ?*const fn (?*const ma_snd_pcm_hw_params_t, [*c]ma_snd_pcm_uframes_t) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_get_periods_proc = ?*const fn (?*const ma_snd_pcm_hw_params_t, [*c]c_uint, [*c]c_int) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_get_access_proc = ?*const fn (?*const ma_snd_pcm_hw_params_t, [*c]ma_snd_pcm_access_t) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_test_format_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, ma_snd_pcm_format_t) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_test_channels_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, c_uint) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_test_rate_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t, c_uint, c_int) callconv(.c) c_int;
pub const ma_snd_pcm_hw_params_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_hw_params_t) callconv(.c) c_int;
pub const ma_snd_pcm_sw_params_sizeof_proc = ?*const fn () callconv(.c) usize;
pub const ma_snd_pcm_sw_params_current_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_sw_params_t) callconv(.c) c_int;
pub const ma_snd_pcm_sw_params_get_boundary_proc = ?*const fn (?*const ma_snd_pcm_sw_params_t, [*c]ma_snd_pcm_uframes_t) callconv(.c) c_int;
pub const ma_snd_pcm_sw_params_set_avail_min_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_sw_params_t, ma_snd_pcm_uframes_t) callconv(.c) c_int;
pub const ma_snd_pcm_sw_params_set_start_threshold_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_sw_params_t, ma_snd_pcm_uframes_t) callconv(.c) c_int;
pub const ma_snd_pcm_sw_params_set_stop_threshold_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_sw_params_t, ma_snd_pcm_uframes_t) callconv(.c) c_int;
pub const ma_snd_pcm_sw_params_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_sw_params_t) callconv(.c) c_int;
pub const ma_snd_pcm_format_mask_sizeof_proc = ?*const fn () callconv(.c) usize;
pub const ma_snd_pcm_format_mask_test_proc = ?*const fn (?*const ma_snd_pcm_format_mask_t, ma_snd_pcm_format_t) callconv(.c) c_int;
pub const ma_snd_pcm_get_chmap_proc = ?*const fn (?*ma_snd_pcm_t) callconv(.c) [*c]ma_snd_pcm_chmap_t;
pub const ma_snd_pcm_state_proc = ?*const fn (?*ma_snd_pcm_t) callconv(.c) ma_snd_pcm_state_t;
pub const ma_snd_pcm_prepare_proc = ?*const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
pub const ma_snd_pcm_start_proc = ?*const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
pub const ma_snd_pcm_drop_proc = ?*const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
pub const ma_snd_pcm_drain_proc = ?*const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
pub const ma_snd_pcm_reset_proc = ?*const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
pub const ma_snd_device_name_hint_proc = ?*const fn (c_int, [*c]const u8, [*c][*c]?*anyopaque) callconv(.c) c_int;
pub const ma_snd_device_name_get_hint_proc = ?*const fn (?*const anyopaque, [*c]const u8) callconv(.c) [*c]u8;
pub const ma_snd_card_get_index_proc = ?*const fn ([*c]const u8) callconv(.c) c_int;
pub const ma_snd_device_name_free_hint_proc = ?*const fn ([*c]?*anyopaque) callconv(.c) c_int;
pub const ma_snd_pcm_mmap_begin_proc = ?*const fn (?*ma_snd_pcm_t, [*c][*c]const ma_snd_pcm_channel_area_t, [*c]ma_snd_pcm_uframes_t, [*c]ma_snd_pcm_uframes_t) callconv(.c) c_int;
pub const ma_snd_pcm_mmap_commit_proc = ?*const fn (?*ma_snd_pcm_t, ma_snd_pcm_uframes_t, ma_snd_pcm_uframes_t) callconv(.c) ma_snd_pcm_sframes_t;
pub const ma_snd_pcm_recover_proc = ?*const fn (?*ma_snd_pcm_t, c_int, c_int) callconv(.c) c_int;
pub const ma_snd_pcm_readi_proc = ?*const fn (?*ma_snd_pcm_t, ?*anyopaque, ma_snd_pcm_uframes_t) callconv(.c) ma_snd_pcm_sframes_t;
pub const ma_snd_pcm_writei_proc = ?*const fn (?*ma_snd_pcm_t, ?*const anyopaque, ma_snd_pcm_uframes_t) callconv(.c) ma_snd_pcm_sframes_t;
pub const ma_snd_pcm_avail_proc = ?*const fn (?*ma_snd_pcm_t) callconv(.c) ma_snd_pcm_sframes_t;
pub const ma_snd_pcm_avail_update_proc = ?*const fn (?*ma_snd_pcm_t) callconv(.c) ma_snd_pcm_sframes_t;
pub const ma_snd_pcm_wait_proc = ?*const fn (?*ma_snd_pcm_t, c_int) callconv(.c) c_int;
pub const ma_snd_pcm_nonblock_proc = ?*const fn (?*ma_snd_pcm_t, c_int) callconv(.c) c_int;
pub const ma_snd_pcm_info_proc = ?*const fn (?*ma_snd_pcm_t, ?*ma_snd_pcm_info_t) callconv(.c) c_int;
pub const ma_snd_pcm_info_sizeof_proc = ?*const fn () callconv(.c) usize;
pub const ma_snd_pcm_info_get_name_proc = ?*const fn (?*const ma_snd_pcm_info_t) callconv(.c) [*c]const u8;
pub const ma_snd_pcm_poll_descriptors_proc = ?*const fn (?*ma_snd_pcm_t, [*c]struct_pollfd, c_uint) callconv(.c) c_int;
pub const ma_snd_pcm_poll_descriptors_count_proc = ?*const fn (?*ma_snd_pcm_t) callconv(.c) c_int;
pub const ma_snd_pcm_poll_descriptors_revents_proc = ?*const fn (?*ma_snd_pcm_t, [*c]struct_pollfd, c_uint, [*c]c_ushort) callconv(.c) c_int;
pub const ma_snd_config_update_free_global_proc = ?*const fn () callconv(.c) c_int;
pub var g_maCommonDeviceNamesALSA: [4][*c]const u8 = [4][*c]const u8{
    "default",
    "null",
    "pulse",
    "jack",
};
pub var g_maBlacklistedPlaybackDeviceNamesALSA: [1][*c]const u8 = [1][*c]const u8{
    "",
};
pub var g_maBlacklistedCaptureDeviceNamesALSA: [1][*c]const u8 = [1][*c]const u8{
    "",
};
pub fn ma_convert_ma_format_to_alsa_format(arg_format: ma_format) callconv(.c) ma_snd_pcm_format_t {
    var ALSAFormats: [6]ma_snd_pcm_format_t = [6]ma_snd_pcm_format_t{
        -@as(c_int, 1),
        1,
        2,
        32,
        10,
        14,
    };
    if (ma_is_big_endian() != 0) {
        ALSAFormats[0] = -@as(c_int, 1);
        ALSAFormats[1] = 1;
        ALSAFormats[2] = 3;
        ALSAFormats[3] = 33;
        ALSAFormats[4] = 11;
        ALSAFormats[5] = 15;
    }
    return ALSAFormats[arg_format];
}
pub fn ma_format_from_alsa(arg_formatALSA: ma_snd_pcm_format_t) callconv(.c) ma_format {
    if (ma_is_little_endian() != 0) {
        return switch (arg_formatALSA) {
            2 => ma_format_s16,
            32 => ma_format_s24,
            10 => ma_format_s32,
            14 => ma_format_f32,
            else => {
                return switch (arg_formatALSA) {
                    1 => ma_format_u8,
                    else => ma_format_unknown,
                };
            },
        };
    } else {
        return switch (arg_formatALSA) {
            3 => ma_format_s16,
            33 => ma_format_s24,
            11 => ma_format_s32,
            15 => ma_format_f32,
            else => {
                return switch (arg_formatALSA) {
                    1 => ma_format_u8,
                    else => ma_format_unknown,
                };
            },
        };
    }
}
pub fn ma_convert_alsa_channel_position_to_ma_channel(arg_alsaChannelPos: c_uint) callconv(.c) ma_channel {
    return switch (arg_alsaChannelPos) {
        2 => MA_CHANNEL_MONO,
        3 => MA_CHANNEL_FRONT_LEFT,
        4 => MA_CHANNEL_FRONT_RIGHT,
        5 => MA_CHANNEL_BACK_LEFT,
        6 => MA_CHANNEL_BACK_RIGHT,
        7 => MA_CHANNEL_FRONT_CENTER,
        8 => MA_CHANNEL_LFE,
        9 => MA_CHANNEL_SIDE_LEFT,
        10 => MA_CHANNEL_SIDE_RIGHT,
        11 => MA_CHANNEL_BACK_CENTER,
        12 => MA_CHANNEL_FRONT_LEFT_CENTER,
        13 => MA_CHANNEL_FRONT_RIGHT_CENTER,
        14, 15, 16, 17, 18, 19, 20 => 0,
        21 => MA_CHANNEL_TOP_CENTER,
        22 => MA_CHANNEL_TOP_FRONT_LEFT,
        23 => MA_CHANNEL_TOP_FRONT_RIGHT,
        24 => MA_CHANNEL_TOP_FRONT_CENTER,
        25 => MA_CHANNEL_TOP_BACK_LEFT,
        26 => MA_CHANNEL_TOP_BACK_RIGHT,
        27 => MA_CHANNEL_TOP_BACK_CENTER,
        else => 0,
    };
}
pub fn ma_is_common_device_name__alsa(arg_name: [*c]const u8) callconv(.c) ma_bool32 {
    var iName: usize = 0;
    while (iName < (@sizeOf([4][*c]const u8) / @sizeOf([*c]const u8))) : (iName +%= 1) {
        if (ma_strcmp(arg_name, g_maCommonDeviceNamesALSA[iName]) == 0) {
            return 1;
        }
    }
    return 0;
}
pub fn ma_is_playback_device_blacklisted__alsa(arg_name: [*c]const u8) callconv(.c) ma_bool32 {
    var iName: usize = 0;
    while (iName < (@sizeOf([1][*c]const u8) / @sizeOf([*c]const u8))) : (iName +%= 1) {
        if (ma_strcmp(arg_name, g_maBlacklistedPlaybackDeviceNamesALSA[iName]) == 0) {
            return 1;
        }
    }
    return 0;
}
pub fn ma_is_capture_device_blacklisted__alsa(arg_name: [*c]const u8) callconv(.c) ma_bool32 {
    var iName: usize = 0;
    while (iName < (@sizeOf([1][*c]const u8) / @sizeOf([*c]const u8))) : (iName +%= 1) {
        if (ma_strcmp(arg_name, g_maBlacklistedCaptureDeviceNamesALSA[iName]) == 0) {
            return 1;
        }
    }
    return 0;
}
pub fn ma_is_device_blacklisted__alsa(arg_deviceType: ma_device_type, arg_name: [*c]const u8) callconv(.c) ma_bool32 {
    if (arg_deviceType == @as(c_uint, @bitCast(ma_device_type_playback))) {
        return ma_is_playback_device_blacklisted__alsa(arg_name);
    } else {
        return ma_is_capture_device_blacklisted__alsa(arg_name);
    }
}
pub fn ma_find_char(arg_str: [*c]const u8, arg_c: u8, arg_index_1: [*c]c_int) callconv(.c) [*c]const u8 {
    var i: c_int = 0;
    while (true) {
        if (arg_str[@as(usize, @intCast(i))] == 0) {
            if (arg_index_1 != null) {
                arg_index_1.* = -1;
            }
            return null;
        }
        if (arg_str[@as(usize, @intCast(i))] == arg_c) {
            if (arg_index_1 != null) {
                arg_index_1.* = i;
            }
            return arg_str + @as(usize, @intCast(i));
        }
        i += 1;
    }
}
pub fn ma_is_device_name_in_hw_format__alsa(arg_hwid: [*c]const u8) callconv(.c) ma_bool32 {
    var commaPos: c_int = undefined;
    var dev: [*c]const u8 = undefined;
    var i: c_int = undefined;
    if (arg_hwid == null) {
        return 0;
    }
    if ((arg_hwid[0] != 'h') or (arg_hwid[1] != 'w') or (arg_hwid[2] != ':')) {
        return 0;
    }
    const hwid = arg_hwid + 3;
    dev = ma_find_char(hwid, @as(u8, @bitCast(@as(i8, @truncate(',')))), &commaPos);
    if (dev == null) {
        return 0;
    } else {
        dev += 1;
    }
    {
        i = 0;
        while (i < commaPos) : (i += 1) {
            if ((hwid[@as(usize, @intCast(i))] < '0') or (hwid[@as(usize, @intCast(i))] > '9')) {
                return 0;
            }
        }
    }
    i = 0;
    while (dev[@as(usize, @intCast(i))] != 0) {
        if ((dev[@as(usize, @intCast(i))] < '0') or (dev[@as(usize, @intCast(i))] > '9')) {
            return 0;
        }
        i += 1;
    }
    return 1;
}
pub fn ma_convert_device_name_to_hw_format__alsa(arg_pContext: [*c]ma_context, arg_dst: [*c]u8, arg_dstSize: usize, arg_src: [*c]const u8) callconv(.c) c_int {
    var colonPos: c_int = undefined;
    var commaPos: c_int = undefined;
    var card: [256]u8 = undefined;
    var dev: [*c]const u8 = undefined;
    var cardIndex: c_int = undefined;
    if (arg_dst == null) {
        return -1;
    }
    if (arg_dstSize < 7) {
        return -1;
    }
    arg_dst[0] = 0;
    if (arg_src == null) {
        return -1;
    }
    if (ma_is_device_name_in_hw_format__alsa(arg_src) != 0) {
        return ma_strcpy_s(arg_dst, arg_dstSize, arg_src);
    }
    const src = ma_find_char(arg_src, @as(u8, @bitCast(@as(i8, @truncate(':')))), &colonPos);
    if (src == null) {
        return -1;
    }
    dev = ma_find_char(src, @as(u8, @bitCast(@as(i8, @truncate(',')))), &commaPos);
    if (dev == null) {
        dev = "0";
        _ = ma_strncpy_s(@as([*c]u8, @ptrCast(@alignCast(&card[0]))), @sizeOf([256]u8), src + 6, @as(usize, @bitCast(@as(isize, -1))));
    } else {
        dev = dev + 5;
        _ = ma_strncpy_s(@as([*c]u8, @ptrCast(@alignCast(&card[0]))), @sizeOf([256]u8), src + 6, @as(usize, @intCast(commaPos - 6)));
    }
    cardIndex = @as(ma_snd_card_get_index_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_card_get_index))).?(arg_dst + 3);
    if (cardIndex < 0) {
        return -2;
    }
    arg_dst[0] = 'h';
    arg_dst[1] = 'w';
    arg_dst[2] = ':';
    if (ma_itoa_s(cardIndex, arg_dst + 3, arg_dstSize - 3, 10) != 0) {
        return -3;
    }
    if (ma_strcat_s(arg_dst, arg_dstSize, ",") != 0) {
        return -3;
    }
    if (ma_strcat_s(arg_dst, arg_dstSize, dev) != 0) {
        return -3;
    }
    return 0;
}
pub fn ma_does_id_exist_in_list__alsa(arg_pUniqueIDs: [*c]ma_device_id, arg_count: ma_uint32, arg_pHWID: [*c]const u8) callconv(.c) ma_bool32 {
    var i: ma_uint32 = undefined;
    std.debug.assert(arg_pHWID != null);
    {
        i = 0;
        while (i < arg_count) : (i +%= 1) {
            if (ma_strcmp(@as([*c]u8, @ptrCast(@alignCast(&arg_pUniqueIDs[i].alsa[0]))), arg_pHWID) == 0) {
                return 1;
            }
        }
    }
    return 0;
}
pub fn ma_context_open_pcm__alsa(arg_pContext: [*c]ma_context, arg_shareMode: ma_share_mode, arg_deviceType: ma_device_type, arg_pDeviceID: [*c]const ma_device_id, arg_openMode: c_int, arg_ppPCM: [*c]?*ma_snd_pcm_t) callconv(.c) ma_result {
    var pPCM: ?*ma_snd_pcm_t = null;
    const stream: ma_snd_pcm_stream_t = if (arg_deviceType == @as(c_uint, @bitCast(ma_device_type_playback))) @as(c_int, 0) else @as(c_int, 1);

    std.debug.assert(arg_pContext != null);
    std.debug.assert(arg_ppPCM != null);

    arg_ppPCM.* = null;

    if (arg_pDeviceID == null) {
        var isDeviceOpen: ma_bool32 = 0;
        var i: usize = 0;
        var defaultDeviceNames: [7][*c]const u8 = [7][*c]const u8{
            "default",
            null,
            null,
            null,
            null,
            null,
            null,
        };

        if (arg_shareMode == @as(c_uint, @bitCast(ma_share_mode_exclusive))) {
            defaultDeviceNames[1] = "hw";
            defaultDeviceNames[2] = "hw:0";
            defaultDeviceNames[3] = "hw:0,0";
        } else {
            if (arg_deviceType == @as(c_uint, @bitCast(ma_device_type_playback))) {
                defaultDeviceNames[1] = "dmix";
                defaultDeviceNames[2] = "dmix:0";
                defaultDeviceNames[3] = "dmix:0,0";
            } else {
                defaultDeviceNames[1] = "dsnoop";
                defaultDeviceNames[2] = "dsnoop:0";
                defaultDeviceNames[3] = "dsnoop:0,0";
            }
            defaultDeviceNames[4] = "hw";
            defaultDeviceNames[5] = "hw:0";
            defaultDeviceNames[6] = "hw:0,0";
        }

        while (i < (@sizeOf([7][*c]const u8) / @sizeOf([*c]const u8))) : (i +%= 1) {
            if ((defaultDeviceNames[i] != null) and (@as(c_int, @bitCast(@as(c_uint, defaultDeviceNames[i][0]))) != @as(c_int, '\x00'))) {
                if (@as(ma_snd_pcm_open_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_open))).?(&pPCM, defaultDeviceNames[i], stream, arg_openMode) == @as(c_int, 0)) {
                    isDeviceOpen = 1;
                    break;
                }
            }
        }

        if (isDeviceOpen == 0) {
            _ = ma_log_postf(ma_context_get_log(arg_pContext), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] snd_pcm_open() failed when trying to open an appropriate default device.");
            return MA_FAILED_TO_OPEN_BACKEND_DEVICE;
        }
    } else {
        var deviceID: ma_device_id = arg_pDeviceID.*;
        var resultALSA: c_int = -@as(c_int, 19);

        if (@as(c_int, @bitCast(@as(c_uint, deviceID.alsa[0]))) != @as(c_int, ':')) {
            resultALSA = @as(ma_snd_pcm_open_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_open))).?(&pPCM, @as([*c]u8, @ptrCast(@alignCast(&deviceID.alsa[0]))), stream, arg_openMode);
        } else {
            var hwid: [256]u8 = undefined;

            if (@as(c_int, @bitCast(@as(c_uint, deviceID.alsa[1]))) == @as(c_int, '\x00')) {
                deviceID.alsa[0] = '\x00';
            }

            if (arg_shareMode == @as(c_uint, @bitCast(ma_share_mode_shared))) {
                if (arg_deviceType == @as(c_uint, @bitCast(ma_device_type_playback))) {
                    _ = ma_strcpy_s(@as([*c]u8, @ptrCast(@alignCast(&hwid[0]))), @sizeOf([256]u8), "dmix");
                } else {
                    _ = ma_strcpy_s(@as([*c]u8, @ptrCast(@alignCast(&hwid[0]))), @sizeOf([256]u8), "dsnoop");
                }
                if (ma_strcat_s(@as([*c]u8, @ptrCast(@alignCast(&hwid[0]))), @sizeOf([256]u8), @as([*c]u8, @ptrCast(@alignCast(&deviceID.alsa[0])))) == @as(c_int, 0)) {
                    resultALSA = @as(ma_snd_pcm_open_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_open))).?(&pPCM, @as([*c]u8, @ptrCast(@alignCast(&hwid[0]))), stream, arg_openMode);
                }
            }

            if (resultALSA != @as(c_int, 0)) {
                _ = ma_strcpy_s(@as([*c]u8, @ptrCast(@alignCast(&hwid[0]))), @sizeOf([256]u8), "hw");
                if (ma_strcat_s(@as([*c]u8, @ptrCast(@alignCast(&hwid[0]))), @sizeOf([256]u8), @as([*c]u8, @ptrCast(@alignCast(&deviceID.alsa[0])))) == @as(c_int, 0)) {
                    resultALSA = @as(ma_snd_pcm_open_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_open))).?(&pPCM, @as([*c]u8, @ptrCast(@alignCast(&hwid[0]))), stream, arg_openMode);
                }
            }
        }

        if (resultALSA < @as(c_int, 0)) {
            _ = ma_log_postf(ma_context_get_log(arg_pContext), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] snd_pcm_open() failed.");
            return ma_result_from_errno(-resultALSA);
        }
    }

    arg_ppPCM.* = pPCM;
    return MA_SUCCESS;
}

pub fn ma_context_enumerate_devices__alsa(arg_pContext: [*c]ma_context, arg_callback: ma_enum_devices_callback_proc, arg_pUserData: ?*anyopaque) callconv(.c) ma_result {
    var resultALSA: c_int = undefined;
    var cbResult: ma_bool32 = 1;
    var ppDeviceHints: [*c][*c]u8 = undefined;
    var pUniqueIDs: [*c]ma_device_id = null;
    var uniqueIDCount: ma_uint32 = 0;
    var ppNextDeviceHint: [*c][*c]u8 = undefined;

    std.debug.assert(arg_pContext != null);
    std.debug.assert(arg_callback != null);

    ma_mutex_lock(&arg_pContext.*.unnamed_0.alsa.internalDeviceEnumLock);
    defer ma_mutex_unlock(&arg_pContext.*.unnamed_0.alsa.internalDeviceEnumLock);
    defer ma_free(@as(?*anyopaque, @ptrCast(pUniqueIDs)), &arg_pContext.*.allocationCallbacks);
    defer _ = @as(ma_snd_device_name_free_hint_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_device_name_free_hint))).?(@as([*c]?*anyopaque, @ptrCast(@alignCast(ppDeviceHints))));

    resultALSA = @as(ma_snd_device_name_hint_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_device_name_hint))).?(-@as(c_int, 1), "pcm", @as([*c][*c]?*anyopaque, @ptrCast(@alignCast(&ppDeviceHints))));
    if (resultALSA < @as(c_int, 0)) {
        return ma_result_from_errno(-resultALSA);
    }

    ppNextDeviceHint = ppDeviceHints;
    while (ppNextDeviceHint.* != null) {
        const NAME: [*c]u8 = @as(ma_snd_device_name_get_hint_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_device_name_get_hint))).?(ppNextDeviceHint.*, "NAME");
        const DESC: [*c]u8 = @as(ma_snd_device_name_get_hint_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_device_name_get_hint))).?(ppNextDeviceHint.*, "DESC");
        const IOID: [*c]u8 = @as(ma_snd_device_name_get_hint_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_device_name_get_hint))).?(ppNextDeviceHint.*, "IOID");
        var deviceType: ma_device_type = ma_device_type_playback;
        var stopEnumeration: ma_bool32 = 0;
        var hwid: [256]u8 = undefined;
        var deviceInfo: ma_device_info = undefined;

        defer {
            free(NAME);
            free(DESC);
            free(IOID);
        }

        if ((IOID == null or ma_strcmp(IOID, "Output") == @as(c_int, 0))) {
            deviceType = ma_device_type_playback;
        }
        if ((IOID != null and ma_strcmp(IOID, "Input") == @as(c_int, 0))) {
            deviceType = ma_device_type_capture;
        }

        if (NAME != null) {
            if (arg_pContext.*.unnamed_0.alsa.useVerboseDeviceEnumeration != 0) {
                _ = ma_strncpy_s(@as([*c]u8, @ptrCast(@alignCast(&hwid[0]))), @sizeOf([256]u8), NAME, @as(usize, @bitCast(@as(isize, -@as(c_int, 1)))));
            } else {
                if (ma_convert_device_name_to_hw_format__alsa(arg_pContext, @as([*c]u8, @ptrCast(@alignCast(&hwid[0]))), @sizeOf([256]u8), NAME) == @as(c_int, 0)) {
                    var dst: [*c]u8 = @as([*c]u8, @ptrCast(@alignCast(&hwid[0])));
                    var src: [*c]u8 = @as([*c]u8, @ptrCast(@alignCast(&hwid[2])));
                    while (true) {
                        dst.* = src.*;
                        if (src.* == '\x00') break;
                        dst += 1;
                        src += 1;
                    }
                } else {
                    _ = ma_strncpy_s(@as([*c]u8, @ptrCast(@alignCast(&hwid[0]))), @sizeOf([256]u8), NAME, @as(usize, @bitCast(@as(isize, -@as(c_int, 1)))));
                }

                if (ma_does_id_exist_in_list__alsa(pUniqueIDs, uniqueIDCount, @as([*c]u8, @ptrCast(@alignCast(&hwid[0])))) != 0) {
                    ppNextDeviceHint += 1;
                    continue;
                }

                {
                    const newCapacity: usize = @sizeOf(ma_device_id) * (uniqueIDCount + 1);
                    const pNewUniqueIDs: [*c]ma_device_id = @as([*c]ma_device_id, @ptrCast(@alignCast(ma_realloc(@as(?*anyopaque, @ptrCast(pUniqueIDs)), newCapacity, &arg_pContext.*.allocationCallbacks))));
                    if (pNewUniqueIDs == null) {
                        ppNextDeviceHint += 1;
                        continue;
                    }

                    pUniqueIDs = pNewUniqueIDs;
                    @memcpy(pUniqueIDs[uniqueIDCount].alsa[0..256], hwid[0..256]);
                    uniqueIDCount += 1;
                }
            }
        } else {
            @memset(hwid[0..256], 0);
        }

        @memset(@as([*]u8, @ptrCast(@alignCast(&deviceInfo)))[0..@sizeOf(ma_device_info)], 0);
        _ = ma_strncpy_s(@as([*c]u8, @ptrCast(@alignCast(&deviceInfo.id.alsa[0]))), ma_device_id_alsa_size, @as([*c]u8, @ptrCast(@alignCast(&hwid[0]))), @as(usize, @bitCast(@as(isize, -@as(c_int, 1)))));

        if (ma_strcmp(@as([*c]u8, @ptrCast(@alignCast(&deviceInfo.id.alsa[0]))), "default") == @as(c_int, 0)) {
            deviceInfo.isDefault = 1;
        }

        if (DESC != null) {
            var lfPos: c_int = undefined;
            var line2: [*c]const u8 = ma_find_char(DESC, '\n', &lfPos);
            if (line2 != null) {
                line2 += 1;

                if (arg_pContext.*.unnamed_0.alsa.useVerboseDeviceEnumeration != 0) {
                    _ = ma_strncpy_s(@as([*c]u8, @ptrCast(@alignCast(&deviceInfo.name[0]))), ma_device_info_name_size, DESC, @as(usize, @bitCast(@as(isize, lfPos))));
                    _ = ma_strcat_s(@as([*c]u8, @ptrCast(@alignCast(&deviceInfo.name[0]))), ma_device_info_name_size, " (");
                    _ = ma_strcat_s(@as([*c]u8, @ptrCast(@alignCast(&deviceInfo.name[0]))), ma_device_info_name_size, line2);
                    _ = ma_strcat_s(@as([*c]u8, @ptrCast(@alignCast(&deviceInfo.name[0]))), ma_device_info_name_size, ")");
                } else {
                    _ = ma_strncpy_s(@as([*c]u8, @ptrCast(@alignCast(&deviceInfo.name[0]))), ma_device_info_name_size, DESC, @as(usize, @bitCast(@as(isize, lfPos))));
                }
            } else {
                _ = ma_strncpy_s(@as([*c]u8, @ptrCast(@alignCast(&deviceInfo.name[0]))), ma_device_info_name_size, DESC, @as(usize, @bitCast(@as(isize, -@as(c_int, 1)))));
            }
        }

        if (ma_is_device_blacklisted__alsa(deviceType, NAME) == 0) {
            cbResult = arg_callback.?(arg_pContext, deviceType, @as([*c]const ma_device_info, @ptrCast(@alignCast(&deviceInfo))), arg_pUserData);
        }

        if (cbResult != 0) {
            if (ma_is_common_device_name__alsa(NAME) != 0 or IOID == null) {
                if (deviceType == ma_device_type_playback) {
                    if (ma_is_capture_device_blacklisted__alsa(NAME) == 0) {
                        cbResult = arg_callback.?(arg_pContext, ma_device_type_capture, @as([*c]const ma_device_info, @ptrCast(@alignCast(&deviceInfo))), arg_pUserData);
                    }
                } else {
                    if (ma_is_playback_device_blacklisted__alsa(NAME) == 0) {
                        cbResult = arg_callback.?(arg_pContext, ma_device_type_playback, @as([*c]const ma_device_info, @ptrCast(@alignCast(&deviceInfo))), arg_pUserData);
                    }
                }
            }
        }

        if (cbResult == 0) {
            stopEnumeration = 1;
        }

        ppNextDeviceHint += 1;

        if (stopEnumeration != 0) {
            break;
        }
    }

    return MA_SUCCESS;
}

pub const ma_context_get_device_info_enum_callback_data__alsa = extern struct {
    deviceType: ma_device_type = std.mem.zeroes(ma_device_type),
    pDeviceID: [*c]const ma_device_id = std.mem.zeroes([*c]const ma_device_id),
    shareMode: ma_share_mode = std.mem.zeroes(ma_share_mode),
    pDeviceInfo: [*c]ma_device_info = std.mem.zeroes([*c]ma_device_info),
    foundDevice: ma_bool32 = std.mem.zeroes(ma_bool32),
};

pub fn ma_context_get_device_info_enum_callback__alsa(arg_pContext: ?*anyopaque, arg_deviceType: ma_device_type, arg_pDeviceInfo: [*c]const ma_device_info, arg_pUserData: ?*anyopaque) callconv(.c) ma_bool32 {
    _ = arg_pContext;
    const pData: [*c]ma_context_get_device_info_enum_callback_data__alsa = @as([*c]ma_context_get_device_info_enum_callback_data__alsa, @ptrCast(@alignCast(arg_pUserData)));

    std.debug.assert(pData != null);

    if ((pData.*.pDeviceID == null) and (ma_strcmp(@as([*c]const u8, @ptrCast(@alignCast(&arg_pDeviceInfo.*.id.alsa[0]))), "default") == @as(c_int, 0))) {
        _ = ma_strncpy_s(@as([*c]u8, @ptrCast(@alignCast(&pData.*.pDeviceInfo.*.name[0]))), ma_device_info_name_size, @as([*c]const u8, @ptrCast(@alignCast(&arg_pDeviceInfo.*.name[0]))), @as(usize, @bitCast(@as(isize, -@as(c_int, 1)))));
        pData.*.foundDevice = 1;
    } else {
        if ((pData.*.deviceType == arg_deviceType) and ((pData.*.pDeviceID != null) and (ma_strcmp(@as([*c]const u8, @ptrCast(@alignCast(&pData.*.pDeviceID.*.alsa[0]))), @as([*c]const u8, @ptrCast(@alignCast(&arg_pDeviceInfo.*.id.alsa[0])))) == @as(c_int, 0)))) {
            _ = ma_strncpy_s(@as([*c]u8, @ptrCast(@alignCast(&pData.*.pDeviceInfo.*.name[0]))), ma_device_info_name_size, @as([*c]const u8, @ptrCast(@alignCast(&arg_pDeviceInfo.*.name[0]))), @as(usize, @bitCast(@as(isize, -@as(c_int, 1)))));
            pData.*.foundDevice = 1;
        }
    }

    return @as(ma_bool32, @intFromBool(pData.*.foundDevice == 0));
}

pub fn ma_context_test_rate_and_add_native_data_format__alsa(arg_pContext: [*c]ma_context, arg_pPCM: ?*ma_snd_pcm_t, arg_pHWParams: ?*ma_snd_pcm_hw_params_t, arg_format: ma_format, arg_channels: ma_uint32, arg_sampleRate: ma_uint32, arg_flags: ma_uint32, arg_pDeviceInfo: [*c]ma_device_info) callconv(.c) void {
    std.debug.assert(arg_pPCM != null);
    std.debug.assert(arg_pHWParams != null);
    std.debug.assert(arg_pDeviceInfo != null);

    if ((@as(usize, @bitCast(@as(usize, arg_pDeviceInfo.*.nativeDataFormatCount))) < (@sizeOf([64]struct_unnamed_65) / @sizeOf(struct_unnamed_65))) and (@as(ma_snd_pcm_hw_params_test_rate_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_test_rate))).?(arg_pPCM, arg_pHWParams, arg_sampleRate, @as(c_int, 0)) == @as(c_int, 0))) {
        arg_pDeviceInfo.*.nativeDataFormats[arg_pDeviceInfo.*.nativeDataFormatCount].format = arg_format;
        arg_pDeviceInfo.*.nativeDataFormats[arg_pDeviceInfo.*.nativeDataFormatCount].channels = arg_channels;
        arg_pDeviceInfo.*.nativeDataFormats[arg_pDeviceInfo.*.nativeDataFormatCount].sampleRate = arg_sampleRate;
        arg_pDeviceInfo.*.nativeDataFormats[arg_pDeviceInfo.*.nativeDataFormatCount].flags = arg_flags;
        arg_pDeviceInfo.*.nativeDataFormatCount +%= @as(ma_uint32, @bitCast(@as(c_int, 1)));
    }
}

pub fn ma_context_iterate_rates_and_add_native_data_format__alsa(arg_pContext: [*c]ma_context, arg_pPCM: ?*ma_snd_pcm_t, arg_pHWParams: ?*ma_snd_pcm_hw_params_t, arg_format: ma_format, arg_channels: ma_uint32, arg_flags: ma_uint32, arg_pDeviceInfo: [*c]ma_device_info) callconv(.c) void {
    var iSampleRate: ma_uint32 = 0;
    var minSampleRate: c_uint = undefined;
    var maxSampleRate: c_uint = undefined;
    var sampleRateDir: c_int = undefined;

    _ = @as(ma_snd_pcm_hw_params_get_rate_min_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_rate_min))).?(arg_pHWParams, &minSampleRate, &sampleRateDir);
    _ = @as(ma_snd_pcm_hw_params_get_rate_max_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_rate_max))).?(arg_pHWParams, &maxSampleRate, &sampleRateDir);

    minSampleRate = if (@as(c_uint, @bitCast(ma_standard_sample_rate_min)) > (if (minSampleRate < @as(c_uint, @bitCast(ma_standard_sample_rate_max))) minSampleRate else @as(c_uint, @bitCast(ma_standard_sample_rate_max)))) @as(c_uint, @bitCast(ma_standard_sample_rate_min)) else if (minSampleRate < @as(c_uint, @bitCast(ma_standard_sample_rate_max))) minSampleRate else @as(c_uint, @bitCast(ma_standard_sample_rate_max));
    maxSampleRate = if (@as(c_uint, @bitCast(ma_standard_sample_rate_min)) > (if (maxSampleRate < @as(c_uint, @bitCast(ma_standard_sample_rate_max))) maxSampleRate else @as(c_uint, @bitCast(ma_standard_sample_rate_max)))) @as(c_uint, @bitCast(ma_standard_sample_rate_min)) else if (maxSampleRate < @as(c_uint, @bitCast(ma_standard_sample_rate_max))) maxSampleRate else @as(c_uint, @bitCast(ma_standard_sample_rate_max));

    while (@as(usize, @bitCast(@as(usize, iSampleRate))) < (@sizeOf([14]ma_uint32) / @sizeOf(ma_uint32))) : (iSampleRate +%= @as(ma_uint32, @bitCast(@as(c_int, 1)))) {
        const standardSampleRate: ma_uint32 = g_maStandardSampleRatePriorities[iSampleRate];

        if ((standardSampleRate >= minSampleRate) and (standardSampleRate <= maxSampleRate)) {
            ma_context_test_rate_and_add_native_data_format__alsa(arg_pContext, arg_pPCM, arg_pHWParams, arg_format, arg_channels, standardSampleRate, arg_flags, arg_pDeviceInfo);
        }
    }

    if (ma_is_standard_sample_rate(minSampleRate) == 0) {
        ma_context_test_rate_and_add_native_data_format__alsa(arg_pContext, arg_pPCM, arg_pHWParams, arg_format, arg_channels, minSampleRate, arg_flags, arg_pDeviceInfo);
    }

    if ((ma_is_standard_sample_rate(maxSampleRate) == 0) and (maxSampleRate != minSampleRate)) {
        ma_context_test_rate_and_add_native_data_format__alsa(arg_pContext, arg_pPCM, arg_pHWParams, arg_format, arg_channels, maxSampleRate, arg_flags, arg_pDeviceInfo);
    }
}

pub fn ma_context_get_device_info__alsa(arg_pContext: [*c]ma_context, arg_deviceType: ma_device_type, arg_pDeviceID: [*c]const ma_device_id, arg_pDeviceInfo: [*c]ma_device_info) callconv(.c) ma_result {
    var data: ma_context_get_device_info_enum_callback_data__alsa = undefined;
    var result: ma_result = undefined;
    var resultALSA: c_int = undefined;
    var pPCM: ?*ma_snd_pcm_t = undefined;
    var pHWParams: ?*ma_snd_pcm_hw_params_t = undefined;
    var iFormat: ma_uint32 = 0;
    var iChannel: ma_uint32 = undefined;

    std.debug.assert(arg_pContext != null);

    data.deviceType = arg_deviceType;
    data.pDeviceID = arg_pDeviceID;
    data.pDeviceInfo = arg_pDeviceInfo;
    data.foundDevice = 0;

    result = ma_context_enumerate_devices__alsa(arg_pContext, &ma_context_get_device_info_enum_callback__alsa, @as(?*anyopaque, @ptrCast(&data)));
    if (result != MA_SUCCESS) {
        return result;
    }

    if (data.foundDevice == 0) {
        return MA_NO_DEVICE;
    }

    if (ma_strcmp(@as([*c]u8, @ptrCast(@alignCast(&arg_pDeviceInfo.*.id.alsa[0]))), "default") == @as(c_int, 0)) {
        arg_pDeviceInfo.*.isDefault = 1;
    }

    result = ma_context_open_pcm__alsa(arg_pContext, @as(c_uint, @bitCast(ma_share_mode_shared)), arg_deviceType, arg_pDeviceID, @as(c_int, 0), &pPCM);
    if (result != MA_SUCCESS) {
        return result;
    }

    pHWParams = @as(?*ma_snd_pcm_hw_params_t, @ptrCast(ma_calloc(@as(ma_snd_pcm_hw_params_sizeof_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_sizeof))).?(), &arg_pContext.*.allocationCallbacks)));
    if (pHWParams == null) {
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        return MA_OUT_OF_MEMORY;
    }

    resultALSA = @as(ma_snd_pcm_hw_params_any_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_any))).?(pPCM, pHWParams);
    if (resultALSA < @as(c_int, 0)) {
        ma_free(@as(?*anyopaque, @ptrCast(pHWParams)), &arg_pContext.*.allocationCallbacks);
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        _ = ma_log_postf(ma_context_get_log(arg_pContext), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to initialize hardware parameters. snd_pcm_hw_params_any() failed.");
        return ma_result_from_errno(-resultALSA);
    }

    while (@as(usize, @bitCast(@as(usize, iFormat))) < (@sizeOf([5]ma_format) / @sizeOf(ma_format))) : (iFormat +%= @as(ma_uint32, @bitCast(@as(c_int, 1)))) {
        const format: ma_format = g_maFormatPriorities[iFormat];

        _ = @as(ma_snd_pcm_hw_params_any_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_any))).?(pPCM, pHWParams);

        if (@as(ma_snd_pcm_hw_params_test_format_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_test_format))).?(pPCM, pHWParams, ma_convert_ma_format_to_alsa_format(format)) == @as(c_int, 0)) {
            var minChannels: c_uint = undefined;
            var maxChannels: c_uint = undefined;

            _ = @as(ma_snd_pcm_hw_params_set_format_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_format))).?(pPCM, pHWParams, ma_convert_ma_format_to_alsa_format(format));
            _ = @as(ma_snd_pcm_hw_params_get_channels_min_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_channels_min))).?(pHWParams, &minChannels);
            _ = @as(ma_snd_pcm_hw_params_get_channels_max_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_channels_max))).?(pHWParams, &maxChannels);

            if (minChannels > @as(c_uint, @bitCast(@as(c_int, 254)))) {
                continue;
            }
            if (maxChannels < @as(c_uint, @bitCast(@as(c_int, 1)))) {
                continue;
            }

            minChannels = if (@as(c_uint, @bitCast(@as(c_int, 1))) > (if (minChannels < @as(c_uint, @bitCast(@as(c_int, 254)))) minChannels else @as(c_uint, @bitCast(@as(c_int, 254))))) @as(c_uint, @bitCast(@as(c_int, 1))) else if (minChannels < @as(c_uint, @bitCast(@as(c_int, 254)))) minChannels else @as(c_uint, @bitCast(@as(c_int, 254)));
            maxChannels = if (@as(c_uint, @bitCast(@as(c_int, 1))) > (if (maxChannels < @as(c_uint, @bitCast(@as(c_int, 254)))) maxChannels else @as(c_uint, @bitCast(@as(c_int, 254))))) @as(c_uint, @bitCast(@as(c_int, 1))) else if (maxChannels < @as(c_uint, @bitCast(@as(c_int, 254)))) maxChannels else @as(c_uint, @bitCast(@as(c_int, 254)));

            if ((minChannels == @as(c_uint, @bitCast(@as(c_int, 1)))) and (maxChannels == @as(c_uint, @bitCast(@as(c_int, 254))))) {
                ma_context_iterate_rates_and_add_native_data_format__alsa(arg_pContext, pPCM, pHWParams, format, @as(ma_uint32, @bitCast(@as(c_int, 0))), @as(ma_uint32, @bitCast(@as(c_int, 0))), arg_pDeviceInfo);
            } else {
                iChannel = minChannels;
                while (iChannel <= maxChannels) : (iChannel +%= @as(ma_uint32, @bitCast(@as(c_int, 1)))) {
                    const channels: c_uint = iChannel;

                    _ = @as(ma_snd_pcm_hw_params_any_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_any))).?(pPCM, pHWParams);
                    _ = @as(ma_snd_pcm_hw_params_set_format_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_format))).?(pPCM, pHWParams, ma_convert_ma_format_to_alsa_format(format));

                    if (@as(ma_snd_pcm_hw_params_test_channels_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_test_channels))).?(pPCM, pHWParams, channels) == @as(c_int, 0)) {
                        _ = @as(ma_snd_pcm_hw_params_set_channels_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_channels))).?(pPCM, pHWParams, channels);
                        ma_context_iterate_rates_and_add_native_data_format__alsa(arg_pContext, pPCM, pHWParams, format, channels, @as(ma_uint32, @bitCast(@as(c_int, 0))), arg_pDeviceInfo);
                    }
                }
            }
        }
    }

    ma_free(@as(?*anyopaque, @ptrCast(pHWParams)), &arg_pContext.*.allocationCallbacks);
    _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(arg_pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);

    return MA_SUCCESS;
}

pub fn ma_device_uninit__alsa(arg_pDevice: [*c]ma_device) callconv(.c) ma_result {
    std.debug.assert(arg_pDevice != null);

    if (@as(?*ma_snd_pcm_t, @ptrCast(arg_pDevice.*.unnamed_0.alsa.pPCMCapture)) != null) {
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(arg_pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(@as(?*ma_snd_pcm_t, @ptrCast(arg_pDevice.*.unnamed_0.alsa.pPCMCapture)));
        _ = close(arg_pDevice.*.unnamed_0.alsa.wakeupfdCapture);
        ma_free(arg_pDevice.*.unnamed_0.alsa.pPollDescriptorsCapture, &arg_pDevice.*.pContext.*.allocationCallbacks);
    }

    if (@as(?*ma_snd_pcm_t, @ptrCast(arg_pDevice.*.unnamed_0.alsa.pPCMPlayback)) != null) {
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(arg_pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(@as(?*ma_snd_pcm_t, @ptrCast(arg_pDevice.*.unnamed_0.alsa.pPCMPlayback)));
        _ = close(arg_pDevice.*.unnamed_0.alsa.wakeupfdPlayback);
        ma_free(arg_pDevice.*.unnamed_0.alsa.pPollDescriptorsPlayback, &arg_pDevice.*.pContext.*.allocationCallbacks);
    }

    return MA_SUCCESS;
}
pub fn ma_device_init_by_type__alsa(arg_pDevice: [*c]ma_device, arg_pConfig: [*c]const ma_device_config, arg_pDescriptor: [*c]ma_device_descriptor, arg_deviceType: ma_device_type) callconv(.c) ma_result {
    var pDevice = arg_pDevice;
    _ = &pDevice;
    var pConfig = arg_pConfig;
    _ = &pConfig;
    var pDescriptor = arg_pDescriptor;
    _ = &pDescriptor;
    var deviceType = arg_deviceType;
    _ = &deviceType;
    var result: ma_result = undefined;
    _ = &result;
    var resultALSA: c_int = undefined;
    _ = &resultALSA;
    var pPCM: ?*ma_snd_pcm_t = undefined;
    _ = &pPCM;
    var isUsingMMap: ma_bool32 = undefined;
    _ = &isUsingMMap;
    var formatALSA: ma_snd_pcm_format_t = undefined;
    _ = &formatALSA;
    var internalFormat: ma_format = undefined;
    _ = &internalFormat;
    var internalChannels: ma_uint32 = undefined;
    _ = &internalChannels;
    var internalSampleRate: ma_uint32 = undefined;
    _ = &internalSampleRate;
    var internalChannelMap: [254]ma_channel = undefined;
    _ = &internalChannelMap;
    var internalPeriodSizeInFrames: ma_uint32 = undefined;
    _ = &internalPeriodSizeInFrames;
    var internalPeriods: ma_uint32 = undefined;
    _ = &internalPeriods;
    var openMode: c_int = undefined;
    _ = &openMode;
    var pHWParams: ?*ma_snd_pcm_hw_params_t = undefined;
    _ = &pHWParams;
    var pSWParams: ?*ma_snd_pcm_sw_params_t = undefined;
    _ = &pSWParams;
    var bufferBoundary: ma_snd_pcm_uframes_t = undefined;
    _ = &bufferBoundary;
    var pollDescriptorCount: c_int = undefined;
    _ = &pollDescriptorCount;
    var pPollDescriptors: [*c]struct_pollfd = undefined;
    _ = &pPollDescriptors;
    var wakeupfd: c_int = undefined;
    _ = &wakeupfd;
    std.debug.assert(pConfig != null);
    std.debug.assert(deviceType != @as(c_uint, @bitCast(ma_device_type_duplex)));
    std.debug.assert(pDevice != null);
    formatALSA = ma_convert_ma_format_to_alsa_format(pDescriptor.*.format);
    openMode = 0;
    if (pConfig.*.alsa.noAutoResample != 0) {
        openMode |= @as(c_int, 65536);
    }
    if (pConfig.*.alsa.noAutoChannels != 0) {
        openMode |= @as(c_int, 131072);
    }
    if (pConfig.*.alsa.noAutoFormat != 0) {
        openMode |= @as(c_int, 262144);
    }
    result = ma_context_open_pcm__alsa(pDevice.*.pContext, pDescriptor.*.shareMode, deviceType, pDescriptor.*.pDeviceID, openMode, &pPCM);
    if (result != MA_SUCCESS) {
        return result;
    }
    pHWParams = @as(?*ma_snd_pcm_hw_params_t, @ptrCast(ma_calloc(@as(ma_snd_pcm_hw_params_sizeof_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_hw_params_sizeof))).?(), &pDevice.*.pContext.*.allocationCallbacks)));
    if (pHWParams == null) {
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to allocate memory for hardware parameters.");
        return MA_OUT_OF_MEMORY;
    }
    resultALSA = @as(ma_snd_pcm_hw_params_any_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_hw_params_any))).?(pPCM, pHWParams);
    if (resultALSA < @as(c_int, 0)) {
        ma_free(@as(?*anyopaque, @ptrCast(pHWParams)), &pDevice.*.pContext.*.allocationCallbacks);
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to initialize hardware parameters. snd_pcm_hw_params_any() failed.");
        return ma_result_from_errno(-resultALSA);
    }
    isUsingMMap = 0;
    if (!(isUsingMMap != 0)) {
        resultALSA = @as(ma_snd_pcm_hw_params_set_access_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_access))).?(pPCM, pHWParams, @as(c_int, 3));
        if (resultALSA < @as(c_int, 0)) {
            ma_free(@as(?*anyopaque, @ptrCast(pHWParams)), &pDevice.*.pContext.*.allocationCallbacks);
            _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
            _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to set access mode to neither SND_PCM_ACCESS_MMAP_INTERLEAVED nor SND_PCM_ACCESS_RW_INTERLEAVED. snd_pcm_hw_params_set_access() failed.");
            return ma_result_from_errno(-resultALSA);
        }
    }
    {
        if ((formatALSA == -@as(c_int, 1)) or (@as(ma_snd_pcm_hw_params_test_format_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_hw_params_test_format))).?(pPCM, pHWParams, formatALSA) != @as(c_int, 0))) {
            var iFormat: usize = undefined;
            _ = &iFormat;
            formatALSA = -@as(c_int, 1);
            {
                iFormat = 0;
                while (iFormat < (@sizeOf([5]ma_format) / @sizeOf(ma_format))) : (iFormat +%= 1) {
                    if (@as(ma_snd_pcm_hw_params_test_format_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_hw_params_test_format))).?(pPCM, pHWParams, ma_convert_ma_format_to_alsa_format(g_maFormatPriorities[iFormat])) == @as(c_int, 0)) {
                        formatALSA = ma_convert_ma_format_to_alsa_format(g_maFormatPriorities[iFormat]);
                        break;
                    }
                }
            }
            if (formatALSA == -@as(c_int, 1)) {
                ma_free(@as(?*anyopaque, @ptrCast(pHWParams)), &pDevice.*.pContext.*.allocationCallbacks);
                _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
                _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Format not supported. The device does not support any miniaudio formats.");
                return MA_FORMAT_NOT_SUPPORTED;
            }
        }
        resultALSA = @as(ma_snd_pcm_hw_params_set_format_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_format))).?(pPCM, pHWParams, formatALSA);
        if (resultALSA < @as(c_int, 0)) {
            ma_free(@as(?*anyopaque, @ptrCast(pHWParams)), &pDevice.*.pContext.*.allocationCallbacks);
            _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
            _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Format not supported. snd_pcm_hw_params_set_format() failed.");
            return ma_result_from_errno(-resultALSA);
        }
        internalFormat = ma_format_from_alsa(formatALSA);
        if (internalFormat == @as(c_uint, @bitCast(ma_format_unknown))) {
            ma_free(@as(?*anyopaque, @ptrCast(pHWParams)), &pDevice.*.pContext.*.allocationCallbacks);
            _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
            _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] The chosen format is not supported by miniaudio.");
            return MA_FORMAT_NOT_SUPPORTED;
        }
    }
    {
        var channels: c_uint = pDescriptor.*.channels;
        _ = &channels;
        if (channels == @as(c_uint, @bitCast(@as(c_int, 0)))) {
            channels = 2;
        }
        resultALSA = @as(ma_snd_pcm_hw_params_set_channels_near_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_channels_near))).?(pPCM, pHWParams, &channels);
        if (resultALSA < @as(c_int, 0)) {
            ma_free(@as(?*anyopaque, @ptrCast(pHWParams)), &pDevice.*.pContext.*.allocationCallbacks);
            _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
            _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to set channel count. snd_pcm_hw_params_set_channels_near() failed.");
            return ma_result_from_errno(-resultALSA);
        }
        internalChannels = @as(ma_uint32, @bitCast(channels));
    }
    {
        var sampleRate: c_uint = undefined;
        _ = &sampleRate;
        _ = @as(ma_snd_pcm_hw_params_set_rate_resample_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_rate_resample))).?(pPCM, pHWParams, @as(c_uint, @bitCast(@as(c_int, 0))));
        sampleRate = pDescriptor.*.sampleRate;
        if (sampleRate == @as(c_uint, @bitCast(@as(c_int, 0)))) {
            sampleRate = @as(c_uint, @bitCast(@as(c_int, 48000)));
        }
        resultALSA = @as(ma_snd_pcm_hw_params_set_rate_near_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_rate_near))).?(pPCM, pHWParams, &sampleRate, null);
        if (resultALSA < @as(c_int, 0)) {
            ma_free(@as(?*anyopaque, @ptrCast(pHWParams)), &pDevice.*.pContext.*.allocationCallbacks);
            _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
            _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Sample rate not supported. snd_pcm_hw_params_set_rate_near() failed.");
            return ma_result_from_errno(-resultALSA);
        }
        internalSampleRate = @as(ma_uint32, @bitCast(sampleRate));
    }
    {
        var periods: ma_uint32 = pDescriptor.*.periodCount;
        _ = &periods;
        resultALSA = @as(ma_snd_pcm_hw_params_set_periods_near_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_periods_near))).?(pPCM, pHWParams, &periods, null);
        if (resultALSA < @as(c_int, 0)) {
            ma_free(@as(?*anyopaque, @ptrCast(pHWParams)), &pDevice.*.pContext.*.allocationCallbacks);
            _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
            _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to set period count. snd_pcm_hw_params_set_periods_near() failed.");
            return ma_result_from_errno(-resultALSA);
        }
        internalPeriods = periods;
    }
    {
        var actualBufferSizeInFrames: ma_snd_pcm_uframes_t = @as(ma_snd_pcm_uframes_t, @bitCast(@as(usize, ma_calculate_buffer_size_in_frames_from_descriptor(pDescriptor, internalSampleRate, pConfig.*.performanceProfile) *% internalPeriods)));
        _ = &actualBufferSizeInFrames;
        resultALSA = @as(ma_snd_pcm_hw_params_set_buffer_size_near_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_buffer_size_near))).?(pPCM, pHWParams, &actualBufferSizeInFrames);
        if (resultALSA < @as(c_int, 0)) {
            ma_free(@as(?*anyopaque, @ptrCast(pHWParams)), &pDevice.*.pContext.*.allocationCallbacks);
            _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
            _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to set buffer size for device. snd_pcm_hw_params_set_buffer_size() failed.");
            return ma_result_from_errno(-resultALSA);
        }
        internalPeriodSizeInFrames = @as(ma_uint32, @bitCast(@as(c_uint, @truncate(actualBufferSizeInFrames / @as(ma_snd_pcm_uframes_t, @bitCast(@as(usize, internalPeriods)))))));
    }
    resultALSA = @as(ma_snd_pcm_hw_params_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_hw_params))).?(pPCM, pHWParams);
    if (resultALSA < @as(c_int, 0)) {
        ma_free(@as(?*anyopaque, @ptrCast(pHWParams)), &pDevice.*.pContext.*.allocationCallbacks);
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to set hardware parameters. snd_pcm_hw_params() failed.");
        return ma_result_from_errno(-resultALSA);
    }
    ma_free(@as(?*anyopaque, @ptrCast(pHWParams)), &pDevice.*.pContext.*.allocationCallbacks);
    pHWParams = null;
    pSWParams = @as(?*ma_snd_pcm_sw_params_t, @ptrCast(ma_calloc(@as(ma_snd_pcm_sw_params_sizeof_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_sw_params_sizeof))).?(), &pDevice.*.pContext.*.allocationCallbacks)));
    if (pSWParams == null) {
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to allocate memory for software parameters.");
        return MA_OUT_OF_MEMORY;
    }
    resultALSA = @as(ma_snd_pcm_sw_params_current_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_sw_params_current))).?(pPCM, pSWParams);
    if (resultALSA < @as(c_int, 0)) {
        ma_free(@as(?*anyopaque, @ptrCast(pSWParams)), &pDevice.*.pContext.*.allocationCallbacks);
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to initialize software parameters. snd_pcm_sw_params_current() failed.");
        return ma_result_from_errno(-resultALSA);
    }
    resultALSA = @as(ma_snd_pcm_sw_params_set_avail_min_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_sw_params_set_avail_min))).?(pPCM, pSWParams, @as(ma_snd_pcm_uframes_t, @bitCast(@as(usize, ma_prev_power_of_2(internalPeriodSizeInFrames)))));
    if (resultALSA < @as(c_int, 0)) {
        ma_free(@as(?*anyopaque, @ptrCast(pSWParams)), &pDevice.*.pContext.*.allocationCallbacks);
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] snd_pcm_sw_params_set_avail_min() failed.");
        return ma_result_from_errno(-resultALSA);
    }
    resultALSA = @as(ma_snd_pcm_sw_params_get_boundary_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_sw_params_get_boundary))).?(pSWParams, &bufferBoundary);
    if (resultALSA < @as(c_int, 0)) {
        bufferBoundary = @as(ma_snd_pcm_uframes_t, @bitCast(@as(usize, internalPeriodSizeInFrames *% internalPeriods)));
    }
    if ((deviceType == @as(c_uint, @bitCast(ma_device_type_playback))) and !(isUsingMMap != 0)) {
        resultALSA = @as(ma_snd_pcm_sw_params_set_start_threshold_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_sw_params_set_start_threshold))).?(pPCM, pSWParams, @as(ma_snd_pcm_uframes_t, @bitCast(@as(usize, internalPeriodSizeInFrames *% @as(ma_uint32, @bitCast(@as(c_int, 2)))))));
        if (resultALSA < @as(c_int, 0)) {
            ma_free(@as(?*anyopaque, @ptrCast(pSWParams)), &pDevice.*.pContext.*.allocationCallbacks);
            _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
            _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to set start threshold for playback device. snd_pcm_sw_params_set_start_threshold() failed.");
            return ma_result_from_errno(-resultALSA);
        }
        resultALSA = @as(ma_snd_pcm_sw_params_set_stop_threshold_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_sw_params_set_stop_threshold))).?(pPCM, pSWParams, bufferBoundary);
        if (resultALSA < @as(c_int, 0)) {
            ma_free(@as(?*anyopaque, @ptrCast(pSWParams)), &pDevice.*.pContext.*.allocationCallbacks);
            _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
            _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to set stop threshold for playback device. snd_pcm_sw_params_set_stop_threshold() failed.");
            return ma_result_from_errno(-resultALSA);
        }
    }
    resultALSA = @as(ma_snd_pcm_sw_params_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_sw_params))).?(pPCM, pSWParams);
    if (resultALSA < @as(c_int, 0)) {
        ma_free(@as(?*anyopaque, @ptrCast(pSWParams)), &pDevice.*.pContext.*.allocationCallbacks);
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to set software parameters. snd_pcm_sw_params() failed.");
        return ma_result_from_errno(-resultALSA);
    }
    ma_free(@as(?*anyopaque, @ptrCast(pSWParams)), &pDevice.*.pContext.*.allocationCallbacks);
    pSWParams = null;
    {
        var pChmap: [*c]ma_snd_pcm_chmap_t = null;
        _ = &pChmap;
        if (pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_get_chmap != null) {
            pChmap = @as(ma_snd_pcm_get_chmap_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_get_chmap))).?(pPCM);
        }
        if (pChmap != null) {
            var iChannel: ma_uint32 = undefined;
            _ = &iChannel;
            if (pChmap.*.channels >= internalChannels) {
                {
                    iChannel = 0;
                    while (iChannel < internalChannels) : (iChannel +%= 1) {
                        internalChannelMap[iChannel] = ma_convert_alsa_channel_position_to_ma_channel(pChmap.*.pos[iChannel]);
                    }
                }
            } else {
                var i: ma_uint32 = undefined;
                _ = &i;
                var isValid: ma_bool32 = 1;
                _ = &isValid;
                ma_channel_map_init_standard(@as(c_uint, @bitCast(ma_standard_channel_map_alsa)), @as([*c]ma_channel, @ptrCast(@alignCast(&internalChannelMap[@as(usize, @intCast(0))]))), @sizeOf([254]ma_channel) / @sizeOf(ma_channel), internalChannels);
                {
                    iChannel = 0;
                    while (iChannel < pChmap.*.channels) : (iChannel +%= 1) {
                        internalChannelMap[iChannel] = ma_convert_alsa_channel_position_to_ma_channel(pChmap.*.pos[iChannel]);
                    }
                }
                {
                    i = 0;
                    while ((i < internalChannels) and (isValid != 0)) : (i +%= 1) {
                        var j: ma_uint32 = undefined;
                        _ = &j;
                        {
                            j = i +% @as(ma_uint32, @bitCast(@as(c_int, 1)));
                            while (j < internalChannels) : (j +%= 1) {
                                if (@as(c_int, @bitCast(@as(c_uint, internalChannelMap[i]))) == @as(c_int, @bitCast(@as(c_uint, internalChannelMap[j])))) {
                                    isValid = 0;
                                    break;
                                }
                            }
                        }
                    }
                }
                if (!(isValid != 0)) {
                    ma_channel_map_init_standard(@as(c_uint, @bitCast(ma_standard_channel_map_alsa)), @as([*c]ma_channel, @ptrCast(@alignCast(&internalChannelMap[@as(usize, @intCast(0))]))), @sizeOf([254]ma_channel) / @sizeOf(ma_channel), internalChannels);
                }
            }
            free(@as(?*anyopaque, @ptrCast(pChmap)));
            pChmap = null;
        } else {
            ma_channel_map_init_standard(@as(c_uint, @bitCast(ma_standard_channel_map_alsa)), @as([*c]ma_channel, @ptrCast(@alignCast(&internalChannelMap[@as(usize, @intCast(0))]))), @sizeOf([254]ma_channel) / @sizeOf(ma_channel), internalChannels);
        }
    }
    pollDescriptorCount = @as(ma_snd_pcm_poll_descriptors_count_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_poll_descriptors_count))).?(pPCM);
    if (pollDescriptorCount <= @as(c_int, 0)) {
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to retrieve poll descriptors count.");
        return MA_ERROR;
    }
    pPollDescriptors = @as([*c]struct_pollfd, @ptrCast(@alignCast(ma_malloc(@sizeOf(struct_pollfd) *% @as(usize, @bitCast(@as(isize, pollDescriptorCount + @as(c_int, 1)))), &pDevice.*.pContext.*.allocationCallbacks))));
    if (pPollDescriptors == null) {
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to allocate memory for poll descriptors.");
        return MA_OUT_OF_MEMORY;
    }
    wakeupfd = eventfd(@as(c_uint, @bitCast(@as(c_int, 0))), @as(c_int, 0));
    if (wakeupfd < @as(c_int, 0)) {
        ma_free(@as(?*anyopaque, @ptrCast(pPollDescriptors)), &pDevice.*.pContext.*.allocationCallbacks);
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to create eventfd for poll wakeup.");
        return ma_result_from_errno(__errno_location().*);
    }
    pPollDescriptors[@as(c_uint, @intCast(@as(c_int, 0)))].fd = wakeupfd;
    pPollDescriptors[@as(c_uint, @intCast(@as(c_int, 0)))].events = 1;
    pPollDescriptors[@as(c_uint, @intCast(@as(c_int, 0)))].revents = 0;
    pollDescriptorCount = @as(ma_snd_pcm_poll_descriptors_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_poll_descriptors))).?(pPCM, pPollDescriptors + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))), @as(c_uint, @bitCast(pollDescriptorCount)));
    if (pollDescriptorCount <= @as(c_int, 0)) {
        _ = close(wakeupfd);
        ma_free(@as(?*anyopaque, @ptrCast(pPollDescriptors)), &pDevice.*.pContext.*.allocationCallbacks);
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to retrieve poll descriptors.");
        return MA_ERROR;
    }
    if (deviceType == @as(c_uint, @bitCast(ma_device_type_capture))) {
        pDevice.*.unnamed_0.alsa.pollDescriptorCountCapture = pollDescriptorCount;
        pDevice.*.unnamed_0.alsa.pPollDescriptorsCapture = @as(?*anyopaque, @ptrCast(pPollDescriptors));
        pDevice.*.unnamed_0.alsa.wakeupfdCapture = wakeupfd;
    } else {
        pDevice.*.unnamed_0.alsa.pollDescriptorCountPlayback = pollDescriptorCount;
        pDevice.*.unnamed_0.alsa.pPollDescriptorsPlayback = @as(?*anyopaque, @ptrCast(pPollDescriptors));
        pDevice.*.unnamed_0.alsa.wakeupfdPlayback = wakeupfd;
    }
    resultALSA = @as(ma_snd_pcm_prepare_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_prepare))).?(pPCM);
    if (resultALSA < @as(c_int, 0)) {
        _ = close(wakeupfd);
        ma_free(@as(?*anyopaque, @ptrCast(pPollDescriptors)), &pDevice.*.pContext.*.allocationCallbacks);
        _ = @as(ma_snd_pcm_close_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_close))).?(pPCM);
        _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to prepare device.");
        return ma_result_from_errno(-resultALSA);
    }
    if (deviceType == @as(c_uint, @bitCast(ma_device_type_capture))) {
        pDevice.*.unnamed_0.alsa.pPCMCapture = @as(ma_ptr, @ptrCast(pPCM));
        pDevice.*.unnamed_0.alsa.isUsingMMapCapture = @as(ma_bool8, @bitCast(@as(u8, @truncate(isUsingMMap))));
    } else {
        pDevice.*.unnamed_0.alsa.pPCMPlayback = @as(ma_ptr, @ptrCast(pPCM));
        pDevice.*.unnamed_0.alsa.isUsingMMapPlayback = @as(ma_bool8, @bitCast(@as(u8, @truncate(isUsingMMap))));
    }
    pDescriptor.*.format = internalFormat;
    pDescriptor.*.channels = internalChannels;
    pDescriptor.*.sampleRate = internalSampleRate;
    ma_channel_map_copy(@as([*c]ma_channel, @ptrCast(@alignCast(&pDescriptor.*.channelMap[@as(usize, @intCast(0))]))), @as([*c]ma_channel, @ptrCast(@alignCast(&internalChannelMap[@as(usize, @intCast(0))]))), if (internalChannels < @as(ma_uint32, @bitCast(@as(c_int, 254)))) internalChannels else @as(ma_uint32, @bitCast(@as(c_int, 254))));
    pDescriptor.*.periodSizeInFrames = internalPeriodSizeInFrames;
    pDescriptor.*.periodCount = internalPeriods;
    return MA_SUCCESS;
}
pub fn ma_device_init__alsa(arg_pDevice: [*c]ma_device, arg_pConfig: [*c]const ma_device_config, arg_pDescriptorPlayback: [*c]ma_device_descriptor, arg_pDescriptorCapture: [*c]ma_device_descriptor) callconv(.c) ma_result {
    var pDevice = arg_pDevice;
    _ = &pDevice;
    var pConfig = arg_pConfig;
    _ = &pConfig;
    var pDescriptorPlayback = arg_pDescriptorPlayback;
    _ = &pDescriptorPlayback;
    var pDescriptorCapture = arg_pDescriptorCapture;
    _ = &pDescriptorCapture;
    std.debug.assert(pDevice != null);
    ma_zero_memory_default(@as(?*anyopaque, @ptrCast(&pDevice.*.unnamed_0.alsa)), @sizeOf(struct_unnamed_17));
    if (pConfig.*.deviceType == @as(c_uint, @bitCast(ma_device_type_loopback))) {
        return MA_DEVICE_TYPE_NOT_SUPPORTED;
    }
    if ((pConfig.*.deviceType == @as(c_uint, @bitCast(ma_device_type_capture))) or (pConfig.*.deviceType == @as(c_uint, @bitCast(ma_device_type_duplex)))) {
        var result: ma_result = ma_device_init_by_type__alsa(pDevice, pConfig, pDescriptorCapture, @as(c_uint, @bitCast(ma_device_type_capture)));
        _ = &result;
        if (result != MA_SUCCESS) {
            return result;
        }
    }
    if ((pConfig.*.deviceType == @as(c_uint, @bitCast(ma_device_type_playback))) or (pConfig.*.deviceType == @as(c_uint, @bitCast(ma_device_type_duplex)))) {
        var result: ma_result = ma_device_init_by_type__alsa(pDevice, pConfig, pDescriptorPlayback, @as(c_uint, @bitCast(ma_device_type_playback)));
        _ = &result;
        if (result != MA_SUCCESS) {
            return result;
        }
    }
    return MA_SUCCESS;
}
pub fn ma_device_start__alsa(arg_pDevice: [*c]ma_device) callconv(.c) ma_result {
    var pDevice = arg_pDevice;
    _ = &pDevice;
    var resultALSA: c_int = undefined;
    if ((pDevice.*.type == @as(c_uint, @bitCast(ma_device_type_capture))) or (pDevice.*.type == @as(c_uint, @bitCast(ma_device_type_duplex)))) {
        resultALSA = @as(ma_snd_pcm_start_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_start))).?(@as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMCapture)));
        if (resultALSA < 0) {
            _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to start capture device.");
            return ma_result_from_errno(-resultALSA);
        }
    }
    if ((pDevice.*.type == @as(c_uint, @bitCast(ma_device_type_playback))) or (pDevice.*.type == @as(c_uint, @bitCast(ma_device_type_duplex)))) {
        resultALSA = @as(ma_snd_pcm_start_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_start))).?(@as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMPlayback)));
        if (resultALSA < 0) {
            _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to start playback device.");
            return ma_result_from_errno(-resultALSA);
        }
    }
    return MA_SUCCESS;
}
pub fn ma_device_stop__alsa(arg_pDevice: [*c]ma_device) callconv(.c) ma_result {
    var pDevice = arg_pDevice;
    _ = &pDevice;
    var resultPoll: c_int = undefined;
    var resultRead: c_int = undefined;
    if ((pDevice.*.type == @as(c_uint, @bitCast(ma_device_type_capture))) or (pDevice.*.type == @as(c_uint, @bitCast(ma_device_type_duplex)))) {
        _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] Dropping capture device...\n"));
        _ = @as(ma_snd_pcm_drop_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_drop))).?(@as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMCapture)));
        _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] Dropping capture device successful.\n"));
        _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] Preparing capture device...\n"));
        if (@as(ma_snd_pcm_prepare_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_prepare))).?(@as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMCapture))) < 0) {
            _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] Preparing capture device failed.\n"));
        } else {
            _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] Preparing capture device successful.\n"));
        }
        resultPoll = poll(@as([*c]struct_pollfd, @ptrCast(@alignCast(pDevice.*.unnamed_0.alsa.pPollDescriptorsCapture))), @as(nfds_t, @bitCast(@as(isize, @as(c_int, 1)))), @as(c_int, 0));
        if (resultPoll > 0) {
            var t: ma_uint64 = undefined;
            resultRead = @as(c_int, @bitCast(@as(c_int, @truncate(read(@as([*c]struct_pollfd, @ptrCast(@alignCast(pDevice.*.unnamed_0.alsa.pPollDescriptorsCapture)))[@as(c_uint, @intCast(@as(c_int, 0)))].fd, @as(?*anyopaque, @ptrCast(&t)), @sizeOf(ma_uint64))))));
            if (@as(usize, @bitCast(@as(isize, resultRead))) != @sizeOf(ma_uint64)) {
                _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), "[ALSA] Failed to read from capture wakeupfd. read() = %d\n", resultRead);
            }
        }
    }
    if ((pDevice.*.type == @as(c_uint, @bitCast(ma_device_type_playback))) or (pDevice.*.type == @as(c_uint, @bitCast(ma_device_type_duplex)))) {
        _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] Dropping playback device...\n"));
        _ = @as(ma_snd_pcm_drop_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_drop))).?(@as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMPlayback)));
        _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] Dropping playback device successful.\n"));
        _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] Preparing playback device...\n"));
        if (@as(ma_snd_pcm_prepare_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_prepare))).?(@as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMPlayback))) < 0) {
            _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] Preparing playback device failed.\n"));
        } else {
            _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] Preparing playback device successful.\n"));
        }
        resultPoll = poll(@as([*c]struct_pollfd, @ptrCast(@alignCast(pDevice.*.unnamed_0.alsa.pPollDescriptorsPlayback))), @as(nfds_t, @bitCast(@as(isize, @as(c_int, 1)))), @as(c_int, 0));
        if (resultPoll > 0) {
            var t: ma_uint64 = undefined;
            resultRead = @as(c_int, @bitCast(@as(c_int, @truncate(read(@as([*c]struct_pollfd, @ptrCast(@alignCast(pDevice.*.unnamed_0.alsa.pPollDescriptorsPlayback)))[@as(c_uint, @intCast(@as(c_int, 0)))].fd, @as(?*anyopaque, @ptrCast(&t)), @sizeOf(ma_uint64))))));
            if (@as(usize, @bitCast(@as(isize, resultRead))) != @sizeOf(ma_uint64)) {
                _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), "[ALSA] Failed to read from playback wakeupfd. read() = %d\n", resultRead);
            }
        }
    }
    return MA_SUCCESS;
}
pub fn ma_device_wait__alsa(arg_pDevice: [*c]ma_device, arg_pPCM: ?*ma_snd_pcm_t, arg_pPollDescriptors: [*c]struct_pollfd, arg_pollDescriptorCount: c_int, arg_requiredEvent: c_short) callconv(.c) ma_result {
    var pDevice = arg_pDevice;
    _ = &pDevice;
    var pPCM = arg_pPCM;
    _ = &pPCM;
    var pPollDescriptors = arg_pPollDescriptors;
    _ = &pPollDescriptors;
    var pollDescriptorCount = arg_pollDescriptorCount;
    _ = &pollDescriptorCount;
    var requiredEvent = arg_requiredEvent;
    _ = &requiredEvent;
    while (true) {
        var revents: c_ushort = undefined;
        var resultALSA: c_int = undefined;
        const resultPoll: c_int = poll(pPollDescriptors, @as(nfds_t, @bitCast(@as(isize, pollDescriptorCount))), -@as(c_int, 1));
        if (resultPoll < 0) {
            _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_WARNING)), "[ALSA] poll() failed.\n");
            continue;
        }
        if ((@as(c_int, @bitCast(@as(c_int, pPollDescriptors[@as(c_uint, @intCast(@as(c_int, 0)))].revents))) & @as(c_int, 1)) != 0) {
            var t: ma_uint64 = undefined;
            const resultRead: c_int = @as(c_int, @bitCast(@as(c_int, @truncate(read(pPollDescriptors[@as(c_uint, @intCast(@as(c_int, 0)))].fd, @as(?*anyopaque, @ptrCast(&t)), @sizeOf(ma_uint64))))));
            if (resultRead < 0) {
                _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] read() failed.\n");
                return ma_result_from_errno(__errno_location().*);
            }
            _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] POLLIN set for wakeupfd\n"));
            return MA_DEVICE_NOT_STARTED;
        }
        resultALSA = @as(ma_snd_pcm_poll_descriptors_revents_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_poll_descriptors_revents))).?(pPCM, pPollDescriptors + @as(usize, @bitCast(@as(isize, @intCast(@as(c_int, 1))))), @as(c_uint, @bitCast(pollDescriptorCount - @as(c_int, 1))), &revents);
        if (resultALSA < 0) {
            _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] snd_pcm_poll_descriptors_revents() failed.\n");
            return ma_result_from_errno(-resultALSA);
        }
        if ((@as(c_int, @bitCast(@as(c_uint, revents))) & @as(c_int, 8)) != 0) {
            const state: ma_snd_pcm_state_t = @as(ma_snd_pcm_state_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_state))).?(pPCM);
            if (state == @as(c_int, 4)) {} else {
                _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_WARNING)), "[ALSA] POLLERR detected. status = %d\n", @as(ma_snd_pcm_state_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_state))).?(pPCM));
            }
        }
        if ((@as(c_int, @bitCast(@as(c_uint, revents))) & @as(c_int, @bitCast(@as(c_int, requiredEvent)))) == @as(c_int, @bitCast(@as(c_int, requiredEvent)))) {
            break;
        }
    }
    return MA_SUCCESS;
}
pub fn ma_device_wait_read__alsa(arg_pDevice: [*c]ma_device) callconv(.c) ma_result {
    var pDevice = arg_pDevice;
    _ = &pDevice;
    return ma_device_wait__alsa(pDevice, @as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMCapture)), @as([*c]struct_pollfd, @ptrCast(@alignCast(pDevice.*.unnamed_0.alsa.pPollDescriptorsCapture))), pDevice.*.unnamed_0.alsa.pollDescriptorCountCapture + @as(c_int, 1), @as(c_short, @bitCast(@as(c_short, @truncate(@as(c_int, 1))))));
}
pub fn ma_device_wait_write__alsa(arg_pDevice: [*c]ma_device) callconv(.c) ma_result {
    var pDevice = arg_pDevice;
    _ = &pDevice;
    return ma_device_wait__alsa(pDevice, @as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMPlayback)), @as([*c]struct_pollfd, @ptrCast(@alignCast(pDevice.*.unnamed_0.alsa.pPollDescriptorsPlayback))), pDevice.*.unnamed_0.alsa.pollDescriptorCountPlayback + @as(c_int, 1), @as(c_short, @bitCast(@as(c_short, @truncate(@as(c_int, 4))))));
}
pub fn ma_device_read__alsa(arg_pDevice: [*c]ma_device, arg_pFramesOut: ?*anyopaque, arg_frameCount: ma_uint32, arg_pFramesRead: [*c]ma_uint32) callconv(.c) ma_result {
    var pDevice = arg_pDevice;
    _ = &pDevice;
    var pFramesOut = arg_pFramesOut;
    _ = &pFramesOut;
    var frameCount = arg_frameCount;
    _ = &frameCount;
    var pFramesRead = arg_pFramesRead;
    _ = &pFramesRead;
    var resultALSA: ma_snd_pcm_sframes_t = 0;
    std.debug.assert(pDevice != null);
    std.debug.assert(pFramesOut != null);
    if (pFramesRead != null) {
        pFramesRead.* = 0;
    }
    while (ma_device_get_state(pDevice) == @as(c_uint, @bitCast(ma_device_state_started))) {
        var result: ma_result = undefined;
        result = ma_device_wait_read__alsa(pDevice);
        if (result != MA_SUCCESS) {
            return result;
        }
        resultALSA = @as(ma_snd_pcm_readi_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_readi))).?(@as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMCapture)), pFramesOut, @as(ma_snd_pcm_uframes_t, @bitCast(@as(usize, frameCount))));
        if (resultALSA >= @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, @as(c_int, 0))))) {
            break;
        } else {
            if (resultALSA == @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, -@as(c_int, 11))))) {
                continue;
            } else if (resultALSA == @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, -@as(c_int, 32))))) {
                _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "EPIPE (read)\n"));
                resultALSA = @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, @as(ma_snd_pcm_recover_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_recover))).?(@as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMCapture)), @as(c_int, @bitCast(@as(c_int, @truncate(resultALSA)))), @as(c_int, 1)))));
                if (resultALSA < @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, @as(c_int, 0))))) {
                    _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to recover device after overrun.");
                    return ma_result_from_errno(@as(c_int, @bitCast(@as(c_int, @truncate(-resultALSA)))));
                }
                resultALSA = @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, @as(ma_snd_pcm_start_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_start))).?(@as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMCapture))))));
                if (resultALSA < @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, @as(c_int, 0))))) {
                    _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to start device after underrun.");
                    return ma_result_from_errno(@as(c_int, @bitCast(@as(c_int, @truncate(-resultALSA)))));
                }
                continue;
            }
        }
    }
    if (pFramesRead != null) {
        pFramesRead.* = @as(ma_uint32, @bitCast(@as(c_int, @truncate(resultALSA))));
    }
    return MA_SUCCESS;
}
pub fn ma_device_write__alsa(arg_pDevice: [*c]ma_device, arg_pFrames: ?*const anyopaque, arg_frameCount: ma_uint32, arg_pFramesWritten: [*c]ma_uint32) callconv(.c) ma_result {
    var pDevice = arg_pDevice;
    _ = &pDevice;
    var pFrames = arg_pFrames;
    _ = &pFrames;
    var frameCount = arg_frameCount;
    _ = &frameCount;
    var pFramesWritten = arg_pFramesWritten;
    _ = &pFramesWritten;
    var resultALSA: ma_snd_pcm_sframes_t = 0;
    std.debug.assert(pDevice != null);
    std.debug.assert(pFrames != null);
    if (pFramesWritten != null) {
        pFramesWritten.* = 0;
    }
    while (ma_device_get_state(pDevice) == @as(c_uint, @bitCast(ma_device_state_started))) {
        var result: ma_result = undefined;
        result = ma_device_wait_write__alsa(pDevice);
        if (result != MA_SUCCESS) {
            return result;
        }
        resultALSA = @as(ma_snd_pcm_writei_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_writei))).?(@as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMPlayback)), pFrames, @as(ma_snd_pcm_uframes_t, @bitCast(@as(usize, frameCount))));
        if (resultALSA >= @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, @as(c_int, 0))))) {
            break;
        } else {
            if (resultALSA == @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, -@as(c_int, 11))))) {
                continue;
            } else if (resultALSA == @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, -@as(c_int, 32))))) {
                _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "EPIPE (write)\n"));
                resultALSA = @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, @as(ma_snd_pcm_recover_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_recover))).?(@as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMPlayback)), @as(c_int, @bitCast(@as(c_int, @truncate(resultALSA)))), @as(c_int, 1)))));
                if (resultALSA < @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, @as(c_int, 0))))) {
                    _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to recover device after underrun.");
                    return ma_result_from_errno(@as(c_int, @bitCast(@as(c_int, @truncate(-resultALSA)))));
                }
                resultALSA = @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, @as(ma_snd_pcm_start_proc, @ptrCast(@alignCast(pDevice.*.pContext.*.unnamed_0.alsa.snd_pcm_start))).?(@as(?*ma_snd_pcm_t, @ptrCast(pDevice.*.unnamed_0.alsa.pPCMPlayback))))));
                if (resultALSA < @as(ma_snd_pcm_sframes_t, @bitCast(@as(isize, @as(c_int, 0))))) {
                    _ = ma_log_post(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), "[ALSA] Failed to start device after underrun.");
                    return ma_result_from_errno(@as(c_int, @bitCast(@as(c_int, @truncate(-resultALSA)))));
                }
                continue;
            }
        }
    }
    if (pFramesWritten != null) {
        pFramesWritten.* = @as(ma_uint32, @bitCast(@as(c_int, @truncate(resultALSA))));
    }
    return MA_SUCCESS;
}
pub fn ma_device_data_loop_wakeup__alsa(arg_pDevice: [*c]ma_device) callconv(.c) ma_result {
    var pDevice = arg_pDevice;
    _ = &pDevice;
    var t: ma_uint64 = 1;
    var resultWrite: c_int = 0;
    std.debug.assert(pDevice != null);
    _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] Waking up...\n"));
    if (pDevice.*.unnamed_0.alsa.pPollDescriptorsCapture != null) {
        resultWrite = @as(c_int, @bitCast(@as(c_int, @truncate(write(pDevice.*.unnamed_0.alsa.wakeupfdCapture, @as(?*const anyopaque, @ptrCast(&t)), @sizeOf(ma_uint64))))));
    }
    if (pDevice.*.unnamed_0.alsa.pPollDescriptorsPlayback != null) {
        resultWrite = @as(c_int, @bitCast(@as(c_int, @truncate(write(pDevice.*.unnamed_0.alsa.wakeupfdPlayback, @as(?*const anyopaque, @ptrCast(&t)), @sizeOf(ma_uint64))))));
    }
    if (resultWrite < 0) {
        _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), @as([*:0]const u8, "[ALSA] write() failed.\n"));
        return ma_result_from_errno(__errno_location().*);
    }
    _ = ma_log_postf(ma_device_get_log(pDevice), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] Waking up completed successfully.\n"));
    return MA_SUCCESS;
}
pub fn ma_context_uninit__alsa(arg_pContext: [*c]ma_context) callconv(.c) ma_result {
    var pContext = arg_pContext;
    _ = &pContext;
    std.debug.assert(pContext != null);
    std.debug.assert(pContext.*.backend == @as(c_uint, @bitCast(ma_backend_alsa)));
    _ = @as(ma_snd_config_update_free_global_proc, @ptrCast(@alignCast(pContext.*.unnamed_0.alsa.snd_config_update_free_global))).?();
    ma_dlclose(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO);
    ma_mutex_uninit(&pContext.*.unnamed_0.alsa.internalDeviceEnumLock);
    return MA_SUCCESS;
}
pub fn ma_context_init__alsa(arg_pContext: [*c]ma_context, arg_pConfig: [*c]const ma_context_config, arg_pCallbacks: [*c]ma_backend_callbacks) callconv(.c) ma_result {
    var pContext = arg_pContext;
    _ = &pContext;
    var pConfig = arg_pConfig;
    _ = &pConfig;
    var pCallbacks = arg_pCallbacks;
    _ = &pCallbacks;
    var result: ma_result = undefined;
    const libasoundNames: [2][*c]const u8 = [2][*c]const u8{
        "libasound.so.2",
        "libasound.so",
    };
    var i: usize = undefined;
    {
        i = 0;
        while (i < (@sizeOf([2][*c]const u8) / @sizeOf([*c]const u8))) : (i +%= 1) {
            pContext.*.unnamed_0.alsa.asoundSO = ma_dlopen(ma_context_get_log(pContext), libasoundNames[i]);
            if (pContext.*.unnamed_0.alsa.asoundSO != null) {
                break;
            }
        }
    }
    if (pContext.*.unnamed_0.alsa.asoundSO == null) {
        _ = ma_log_postf(ma_context_get_log(pContext), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_DEBUG)), @as([*:0]const u8, "[ALSA] Failed to open shared object.\n"));
        return MA_NO_BACKEND;
    }
    pContext.*.unnamed_0.alsa.snd_pcm_open = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_open");
    pContext.*.unnamed_0.alsa.snd_pcm_close = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_close");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_sizeof = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_sizeof");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_any = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_any");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_format = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_set_format");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_format_first = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_set_format_first");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_format_mask = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_get_format_mask");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_channels = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_set_channels");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_channels_near = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_set_channels_near");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_channels_minmax = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_set_channels_minmax");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_rate_resample = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_set_rate_resample");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_rate = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_set_rate");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_rate_near = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_set_rate_near");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_buffer_size_near = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_set_buffer_size_near");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_periods_near = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_set_periods_near");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_set_access = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_set_access");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_format = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_get_format");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_channels = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_get_channels");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_channels_min = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_get_channels_min");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_channels_max = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_get_channels_max");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_rate = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_get_rate");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_rate_min = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_get_rate_min");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_rate_max = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_get_rate_max");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_buffer_size = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_get_buffer_size");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_periods = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_get_periods");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_get_access = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_get_access");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_test_format = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_test_format");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_test_channels = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_test_channels");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params_test_rate = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params_test_rate");
    pContext.*.unnamed_0.alsa.snd_pcm_hw_params = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_hw_params");
    pContext.*.unnamed_0.alsa.snd_pcm_sw_params_sizeof = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_sw_params_sizeof");
    pContext.*.unnamed_0.alsa.snd_pcm_sw_params_current = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_sw_params_current");
    pContext.*.unnamed_0.alsa.snd_pcm_sw_params_get_boundary = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_sw_params_get_boundary");
    pContext.*.unnamed_0.alsa.snd_pcm_sw_params_set_avail_min = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_sw_params_set_avail_min");
    pContext.*.unnamed_0.alsa.snd_pcm_sw_params_set_start_threshold = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_sw_params_set_start_threshold");
    pContext.*.unnamed_0.alsa.snd_pcm_sw_params_set_stop_threshold = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_sw_params_set_stop_threshold");
    pContext.*.unnamed_0.alsa.snd_pcm_sw_params = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_sw_params");
    pContext.*.unnamed_0.alsa.snd_pcm_format_mask_sizeof = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_format_mask_sizeof");
    pContext.*.unnamed_0.alsa.snd_pcm_format_mask_test = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_format_mask_test");
    pContext.*.unnamed_0.alsa.snd_pcm_get_chmap = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_get_chmap");
    pContext.*.unnamed_0.alsa.snd_pcm_state = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_state");
    pContext.*.unnamed_0.alsa.snd_pcm_prepare = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_prepare");
    pContext.*.unnamed_0.alsa.snd_pcm_start = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_start");
    pContext.*.unnamed_0.alsa.snd_pcm_drop = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_drop");
    pContext.*.unnamed_0.alsa.snd_pcm_drain = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_drain");
    pContext.*.unnamed_0.alsa.snd_pcm_reset = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_reset");
    pContext.*.unnamed_0.alsa.snd_device_name_hint = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_device_name_hint");
    pContext.*.unnamed_0.alsa.snd_device_name_get_hint = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_device_name_get_hint");
    pContext.*.unnamed_0.alsa.snd_card_get_index = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_card_get_index");
    pContext.*.unnamed_0.alsa.snd_device_name_free_hint = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_device_name_free_hint");
    pContext.*.unnamed_0.alsa.snd_pcm_mmap_begin = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_mmap_begin");
    pContext.*.unnamed_0.alsa.snd_pcm_mmap_commit = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_mmap_commit");
    pContext.*.unnamed_0.alsa.snd_pcm_recover = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_recover");
    pContext.*.unnamed_0.alsa.snd_pcm_readi = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_readi");
    pContext.*.unnamed_0.alsa.snd_pcm_writei = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_writei");
    pContext.*.unnamed_0.alsa.snd_pcm_avail = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_avail");
    pContext.*.unnamed_0.alsa.snd_pcm_avail_update = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_avail_update");
    pContext.*.unnamed_0.alsa.snd_pcm_wait = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_wait");
    pContext.*.unnamed_0.alsa.snd_pcm_nonblock = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_nonblock");
    pContext.*.unnamed_0.alsa.snd_pcm_info = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_info");
    pContext.*.unnamed_0.alsa.snd_pcm_info_sizeof = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_info_sizeof");
    pContext.*.unnamed_0.alsa.snd_pcm_info_get_name = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_info_get_name");
    pContext.*.unnamed_0.alsa.snd_pcm_poll_descriptors = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_poll_descriptors");
    pContext.*.unnamed_0.alsa.snd_pcm_poll_descriptors_count = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_poll_descriptors_count");
    pContext.*.unnamed_0.alsa.snd_pcm_poll_descriptors_revents = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_pcm_poll_descriptors_revents");
    pContext.*.unnamed_0.alsa.snd_config_update_free_global = ma_dlsym(ma_context_get_log(pContext), pContext.*.unnamed_0.alsa.asoundSO, "snd_config_update_free_global");
    pContext.*.unnamed_0.alsa.useVerboseDeviceEnumeration = pConfig.*.alsa.useVerboseDeviceEnumeration;
    result = ma_mutex_init(&pContext.*.unnamed_0.alsa.internalDeviceEnumLock);
    if (result != MA_SUCCESS) {
        _ = ma_log_postf(ma_context_get_log(pContext), @as(ma_uint32, @bitCast(MA_LOG_LEVEL_ERROR)), @as([*:0]const u8, "[ALSA] WARNING: Failed to initialize mutex for internal device enumeration."));
        return result;
    }
    pCallbacks.*.onContextInit = &ma_context_init__alsa;
    pCallbacks.*.onContextUninit = &ma_context_uninit__alsa;
    pCallbacks.*.onContextEnumerateDevices = &ma_context_enumerate_devices__alsa;
    pCallbacks.*.onContextGetDeviceInfo = &ma_context_get_device_info__alsa;
    pCallbacks.*.onDeviceInit = &ma_device_init__alsa;
    pCallbacks.*.onDeviceUninit = &ma_device_uninit__alsa;
    pCallbacks.*.onDeviceStart = &ma_device_start__alsa;
    pCallbacks.*.onDeviceStop = &ma_device_stop__alsa;
    pCallbacks.*.onDeviceRead = &ma_device_read__alsa;
    pCallbacks.*.onDeviceWrite = &ma_device_write__alsa;
    pCallbacks.*.onDeviceDataLoop = null;
    pCallbacks.*.onDeviceDataLoopWakeup = &ma_device_data_loop_wakeup__alsa;
    return MA_SUCCESS;
}
