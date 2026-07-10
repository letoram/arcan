// SPDX-License-Identifier: BSD-3-Clause
// Zig port of parse-edid.c (originally © 2011 Saleem Abdulrasool).
// Parses an EDID 1.x block + CEA-861 extensions + HDMI VSDB and prints to
// stdout. Exposed via `export fn parse_edid(data: [*]const u8) void` so that
// shmmon.zig (or any C caller) can link it in directly.
//
// Layout structs are authored as `packed struct(uXX)` to mirror the byte-
// precise EDID/CEA-861 spec. libc `printf`/`fprintf` are used directly so
// the textual output stays byte-for-byte identical to the C original.

const std = @import("std");

// ---------------------------------------------------------------------------
// libc externs — use directly to preserve the C version's exact printf format
// strings (including the %.f, %0.3f, and backspace/pad tricks).
// ---------------------------------------------------------------------------

const libc = @import("posix");
const FILE = libc.FILE;
const printf = libc.printf;
const fprintf = libc.fprintf;
const putchar = libc.putchar;
extern "c" fn sqrt(x: f64) f64; // sqrt is parse-edid only — keep local

// One indirect call site below uses `stderr`; alias the libc extern var
// so that line stays unchanged.
inline fn stderr_ptr() *FILE { return libc.stderr; }

// ---------------------------------------------------------------------------
// Constants (ex-edid.h / cea861.h / hdmi.h)
// ---------------------------------------------------------------------------

const EDID_BLOCK_SIZE: u8 = 0x80;

const EDID_HEADER = [_]u8{ 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00 };
const EDID_STANDARD_TIMING_DESCRIPTOR_INVALID = [_]u8{ 0x01, 0x01 };

const EDID_EXTENSION_CEA: u8 = 0x02;

const EDID_DISPLAY_TYPE_MONOCHROME: u8 = 0;
const EDID_DISPLAY_TYPE_RGB: u8 = 1;
const EDID_DISPLAY_TYPE_NON_RGB: u8 = 2;
const EDID_DISPLAY_TYPE_UNDEFINED: u8 = 3;

const EDID_ASPECT_RATIO_16_10: u8 = 0;
const EDID_ASPECT_RATIO_4_3: u8 = 1;
const EDID_ASPECT_RATIO_5_4: u8 = 2;
const EDID_ASPECT_RATIO_16_9: u8 = 3;

const EDID_MONTIOR_DESCRIPTOR_MANUFACTURER_DEFINED: u8 = 0x0f;
const EDID_MONITOR_DESCRIPTOR_MONITOR_NAME: u8 = 0xfc;
const EDID_MONITOR_DESCRIPTOR_MONITOR_RANGE_LIMITS: u8 = 0xfd;
const EDID_MONITOR_DESCRIPTOR_ASCII_STRING: u8 = 0xfe;
const EDID_MONITOR_DESCRIPTOR_MONITOR_SERIAL_NUMBER: u8 = 0xff;

const CEA861_DATA_BLOCK_TYPE_AUDIO: u3 = 1;
const CEA861_DATA_BLOCK_TYPE_VIDEO: u3 = 2;
const CEA861_DATA_BLOCK_TYPE_VENDOR_SPECIFIC: u3 = 3;
const CEA861_DATA_BLOCK_TYPE_SPEAKER_ALLOCATION: u3 = 4;

const CEA861_AUDIO_FORMAT_LPCM: u4 = 1;
const CEA861_AUDIO_FORMAT_AC_3: u4 = 2;

const HDMI_VSDB_EXTENSION_FLAGS_OFFSET: u8 = 0x06;
const HDMI_VSDB_MAX_TMDS_OFFSET: u8 = 0x07;
const HDMI_VSDB_LATENCY_FIELDS_OFFSET: u8 = 0x08;

const HDMI_OUI = [_]u8{ 0x00, 0x0C, 0x03 };

// ---------------------------------------------------------------------------
// Packed struct layouts (bit-precise, little-endian as per EDID/CEA-861 spec)
// ---------------------------------------------------------------------------

// 18 bytes — same layout as struct edid_detailed_timing_descriptor.
const EdidDetailedTiming = packed struct(u144) {
    pixel_clock: u16, // * 10000
    horizontal_active_lo: u8,
    horizontal_blanking_lo: u8,
    horizontal_blanking_hi: u4,
    horizontal_active_hi: u4,
    vertical_active_lo: u8,
    vertical_blanking_lo: u8,
    vertical_blanking_hi: u4,
    vertical_active_hi: u4,
    horizontal_sync_offset_lo: u8,
    horizontal_sync_pulse_width_lo: u8,
    vertical_sync_pulse_width_lo: u4,
    vertical_sync_offset_lo: u4,
    vertical_sync_pulse_width_hi: u2,
    vertical_sync_offset_hi: u2,
    horizontal_sync_pulse_width_hi: u2,
    horizontal_sync_offset_hi: u2,
    horizontal_image_size_lo: u8,
    vertical_image_size_lo: u8,
    vertical_image_size_hi: u4,
    horizontal_image_size_hi: u4,
    horizontal_border: u8,
    vertical_border: u8,
    stereo_mode_lo: u1,
    signal_pulse_polarity: u1,
    signal_serration_polarity: u1,
    signal_sync: u2,
    stereo_mode_hi: u2,
    interlaced: u1,
};

// 18-byte monitor descriptor view (alternative view of the same 18-byte slot).
// flag0 is two bytes, but the C code treats it as u16 (little-endian).
const EdidMonitorDescriptor = extern struct {
    flag0: u16 align(1),
    flag1: u8,
    tag: u8,
    flag2: u8,
    data: [13]u8,
};

// struct edid — 128 bytes total
const Edid = extern struct {
    header: [8]u8, // 0x00
    manufacturer: u16 align(1), // 0x08 (big-endian on wire but read as LE u16 in source)
    product: [2]u8, // 0x0a
    serial_number: [4]u8, // 0x0c
    manufacture_week: u8, // 0x10
    manufacture_year: u8, // 0x11 (= value + 1990)
    version: u8, // 0x12
    revision: u8, // 0x13
    video_input_definition: u8, // 0x14 (digital/analog union byte)
    maximum_horizontal_image_size: u8, // 0x15 cm
    maximum_vertical_image_size: u8, // 0x16 cm
    display_transfer_characteristics: u8, // 0x17
    feature_support: u8, // 0x18
    // color characteristics — two packed bytes of lo bits
    color_lo_0: u8, // 0x19 green_y_low:2 green_x_low:2 red_y_low:2 red_x_low:2
    color_lo_1: u8, // 0x1a white_y_low:2 white_x_low:2 blue_y_low:2 blue_x_low:2
    red_x: u8, // 0x1b
    red_y: u8, // 0x1c
    green_x: u8, // 0x1d
    green_y: u8, // 0x1e
    blue_x: u8, // 0x1f
    blue_y: u8, // 0x20
    white_x: u8, // 0x21
    white_y: u8, // 0x22
    established_timings_0: u8, // 0x23
    established_timings_1: u8, // 0x24
    manufacturer_timings: u8, // 0x25
    standard_timing_id: [8][2]u8, // 0x26 .. 0x35 (16 bytes)
    detailed_timings: [4][18]u8, // 0x36 .. 0x7d (72 bytes)
    extensions: u8, // 0x7e
    checksum: u8, // 0x7f
};

comptime {
    // Packed structs may have aligned @sizeOf > @bitSizeOf/8; verify bit width.
    std.debug.assert(@bitSizeOf(EdidDetailedTiming) == 144);
    // Edid layout must match the 128-byte wire format exactly.
    // Use offsets to verify (extern struct alignment may pad @sizeOf otherwise).
    std.debug.assert(@offsetOf(Edid, "extensions") == 0x7e);
    std.debug.assert(@offsetOf(Edid, "checksum") == 0x7f);
}

// ---------------------------------------------------------------------------
// Accessor helpers — equivalent to the edid.h static inlines
// ---------------------------------------------------------------------------

fn edidDetailedTimingPixelClock(d: *align(1) const EdidDetailedTiming) u32 {
    return @as(u32, d.pixel_clock) * 10000;
}
fn edidDetailedTimingHBlank(d: *align(1) const EdidDetailedTiming) u16 {
    return (@as(u16, d.horizontal_blanking_hi) << 8) | d.horizontal_blanking_lo;
}
fn edidDetailedTimingHActive(d: *align(1) const EdidDetailedTiming) u16 {
    return (@as(u16, d.horizontal_active_hi) << 8) | d.horizontal_active_lo;
}
fn edidDetailedTimingVBlank(d: *align(1) const EdidDetailedTiming) u16 {
    return (@as(u16, d.vertical_blanking_hi) << 8) | d.vertical_blanking_lo;
}
fn edidDetailedTimingVActive(d: *align(1) const EdidDetailedTiming) u16 {
    return (@as(u16, d.vertical_active_hi) << 8) | d.vertical_active_lo;
}
fn edidDetailedTimingVSyncOffset(d: *align(1) const EdidDetailedTiming) u8 {
    return (@as(u8, d.vertical_sync_offset_hi) << 4) | d.vertical_sync_offset_lo;
}
fn edidDetailedTimingVSyncPulseWidth(d: *align(1) const EdidDetailedTiming) u8 {
    return (@as(u8, d.vertical_sync_pulse_width_hi) << 4) | d.vertical_sync_pulse_width_lo;
}
fn edidDetailedTimingHSyncOffset(d: *align(1) const EdidDetailedTiming) u8 {
    return (@as(u8, d.horizontal_sync_offset_hi) << 4) | d.horizontal_sync_offset_lo;
}
fn edidDetailedTimingHSyncPulseWidth(d: *align(1) const EdidDetailedTiming) u8 {
    return (@as(u8, d.horizontal_sync_pulse_width_hi) << 4) | d.horizontal_sync_pulse_width_lo;
}

// Aspect-ratio heuristic, exact match with _aspect_ratio() in C.
fn aspectRatio(hres: u16, vres: u16) [*:0]const u8 {
    const vr = @as(u32, vres);
    const hr = @as(u32, hres);
    // Test each ratio (x:y): hres == vres*x/y && (vres*x) % y == 0
    if (hr == (vr * 16) / 10 and (vr * 16) % 10 == 0) return "16:10";
    if (hr == (vr * 4) / 3 and (vr * 4) % 3 == 0) return "4:3";
    if (hr == (vr * 5) / 4 and (vr * 5) % 4 == 0) return "5:4";
    if (hr == (vr * 16) / 9 and (vr * 16) % 9 == 0) return "16:9";
    return "unknown";
}

fn edidManufacturer(e: *align(1) const Edid, buf: *[4]u8) void {
    // Wire order: big-endian u16 where the 16 bits encode three 5-bit letters.
    // The C code reads it as host-order u16 and does the bit shuffling; that's
    // actually wrong on BE hosts but matches the original behaviour on LE,
    // which is what the shmmon binary has always run on. Preserve that.
    const m = e.manufacturer;
    buf[0] = '@' + @as(u8, @truncate((m & 0x007c) >> 2));
    buf[1] = '@' + (@as(u8, @truncate(((m & 0x0003) >> 0) << 3)) |
        @as(u8, @truncate(((m & 0xe000) >> 13) << 0)));
    buf[2] = '@' + @as(u8, @truncate((m & 0x1f00) >> 8));
    buf[3] = 0;
}

fn edidGamma(e: *align(1) const Edid) f64 {
    return (@as(f64, @floatFromInt(e.display_transfer_characteristics)) + 100.0) / 100.0;
}

fn isMonitorDescriptor(e: *align(1) const Edid, idx: usize) bool {
    const slot = &e.detailed_timings[idx];
    const mon: *align(1) const EdidMonitorDescriptor = @ptrCast(@alignCast(slot));
    return mon.flag0 == 0x0000 and mon.flag1 == 0x00 and mon.flag2 == 0x00;
}

// 10-bit CIE fixed point -> float.
fn edidDecodeFixedPoint(value_in: u16) f64 {
    var value = value_in;
    var result: f64 = 0.0;
    var i: u8 = 0;
    while (value != 0 and i < 10) : ({
        i += 1;
        value >>= 1;
    }) {
        if ((value & 0x1) != 0) {
            const denom: f64 = @floatFromInt(@as(u32, 1) << @intCast(10 - i));
            result += 1.0 / denom;
        }
    }
    return result;
}

// ---------------------------------------------------------------------------
// dump_section helpers
// ---------------------------------------------------------------------------

fn dumpSection(name: [*:0]const u8, buffer: [*]const u8, offset: u8, length: u8) void {
    var value = buffer + offset;
    _ = printf("%33.33s: ", name);

    var l: u32 = 35;
    var i: u8 = 0;
    while (i < length) : (i += 1) {
        l += 3;
        if (l > 89) {
            _ = printf("\x08\n%35s", @as([*:0]const u8, ""));
            l = 35;
        }
        _ = printf("%02x ", @as(c_uint, value[0]));
        value += 1;
    }
    _ = printf("\x08\n");
}

fn dumpEdid1(buffer: [*]const u8) void {
    dumpSection("header", buffer, 0x00, 0x08);
    dumpSection("vendor/product identification", buffer, 0x08, 0x0a);
    dumpSection("edid struct version/revision", buffer, 0x12, 0x02);
    dumpSection("basic display parameters/features", buffer, 0x14, 0x05);
    dumpSection("color characteristics", buffer, 0x19, 0x0a);
    dumpSection("established timings", buffer, 0x23, 0x03);
    dumpSection("standard timing identification", buffer, 0x26, 0x10);
    dumpSection("detailed timing 0", buffer, 0x36, 0x12);
    dumpSection("detailed timing 1", buffer, 0x48, 0x12);
    dumpSection("detailed timing 2", buffer, 0x5a, 0x12);
    dumpSection("detailed timing 3", buffer, 0x6c, 0x12);
    dumpSection("extensions", buffer, 0x7e, 0x01);
    dumpSection("checksum", buffer, 0x7f, 0x01);
    _ = printf("\n");
}

// ---------------------------------------------------------------------------
// CEA-861 hex dump
// ---------------------------------------------------------------------------

fn dumpCea861(buffer: [*]const u8) void {
    // struct cea861_timing_block layout: bytes 0..3 = tag/revision/dtd_offset/flags.
    const dtd_offset = buffer[2];
    const dof: u8 = 4; // offsetof(cea861_timing_block, data)

    dumpSection("cea extension header", buffer, 0x00, 0x04);

    if (dtd_offset > dof)
        dumpSection("data block collection", buffer, 0x04, dtd_offset - dof);

    var i: u8 = 0;
    var pos: usize = dtd_offset;
    // Walk DTDs while pixel_clock != 0 (u16 LE at offset 0 of each descriptor).
    while (pos + 18 <= 128) : ({
        i += 1;
        pos += 18;
    }) {
        const pclk: u16 = @as(u16, buffer[pos]) | (@as(u16, buffer[pos + 1]) << 8);
        if (pclk == 0) break;

        var hdr: [64]u8 = undefined;
        const hdrz = std.fmt.bufPrintZ(&hdr, "detailed timing descriptor {d:0>3}", .{i}) catch "detailed timing descriptor";
        dumpSection(hdrz.ptr, buffer + pos, 0x00, 18);
    }

    // padding from pos (== end of DTDs) through byte 0x7e-ish (before checksum)
    // C computes: dof + sizeof(data)=123 - (dtd-buffer) i.e. 127 - pos
    if (pos < 127) {
        dumpSection("padding", buffer, @intCast(pos), @intCast(127 - pos));
    } else {
        // C version happily calls with 0 length if pos == 127 — matches.
        dumpSection("padding", buffer, @intCast(pos), 0);
    }
    dumpSection("checksum", buffer, 0x7f, 0x01);
    _ = printf("\n");
}

// ---------------------------------------------------------------------------
// Timing / mode string formatting (uses libc snprintf-style via printf calls)
// ---------------------------------------------------------------------------

fn printEdidTimingString(d: *align(1) const EdidDetailedTiming) void {
    const hres = edidDetailedTimingHActive(d);
    const vres = edidDetailedTimingVActive(d);
    const htotal: u32 = @as(u32, hres) + edidDetailedTimingHBlank(d);
    const vtotal: u32 = @as(u32, vres) + edidDetailedTimingVBlank(d);

    const refresh: f64 = @as(f64, @floatFromInt(edidDetailedTimingPixelClock(d))) /
        (@as(f64, @floatFromInt(vtotal)) * @as(f64, @floatFromInt(htotal)));

    const ip: u8 = if (d.interlaced != 0) 'i' else 'p';
    _ = printf(
        "%ux%u%c at %.fHz (%s)",
        @as(c_uint, hres),
        @as(c_uint, vres),
        @as(c_int, ip),
        refresh,
        aspectRatio(hres, vres),
    );
}

fn printEdidModeString(d: *align(1) const EdidDetailedTiming) void {
    const xres = edidDetailedTimingHActive(d);
    const yres = edidDetailedTimingVActive(d);
    const pixclk = edidDetailedTimingPixelClock(d);
    const lower_margin = edidDetailedTimingVSyncOffset(d);
    const right_margin = edidDetailedTimingHSyncOffset(d);
    const hspw = edidDetailedTimingHSyncPulseWidth(d);
    const vspw = edidDetailedTimingVSyncPulseWidth(d);
    const hblank = edidDetailedTimingHBlank(d);
    const vblank = edidDetailedTimingVBlank(d);

    const mhz: f64 = @as(f64, @floatFromInt(pixclk)) / 1_000_000.0;
    const hsync: u8 = if (d.signal_pulse_polarity != 0) '+' else '-';
    const vsync: u8 = if (d.signal_serration_polarity != 0) '+' else '-';

    _ = printf(
        "\"%ux%u\" %.3f %u %u %u %u %u %u %u %u %chsync %cvsync",
        @as(c_uint, xres),
        @as(c_uint, yres),
        mhz,
        @as(c_uint, xres),
        @as(c_uint, xres + right_margin),
        @as(c_uint, xres + right_margin + hspw),
        @as(c_uint, xres + hblank),
        @as(c_uint, yres),
        @as(c_uint, yres + lower_margin),
        @as(c_uint, yres + lower_margin + vspw),
        @as(c_uint, yres + vblank),
        @as(c_int, hsync),
        @as(c_int, vsync),
    );
}

// ---------------------------------------------------------------------------
// disp_edid1 — primary EDID summary
// ---------------------------------------------------------------------------

fn dispEdid1(edid: *align(1) const Edid) void {
    var monitor_serial_number: [14]u8 = @splat(0);
    var monitor_model_name: [14]u8 = @splat(0);
    var has_ascii_string: bool = false;
    var has_range_limits: bool = false;
    var rl_min_v: u8 = 0;
    var rl_max_v: u8 = 0;
    var rl_min_h: u8 = 0;
    var rl_max_h: u8 = 0;
    var rl_max_pixclk: u8 = 0;
    var manufacturer: [4]u8 = @splat(0);

    edidManufacturer(edid, &manufacturer);

    const vlen = edid.maximum_vertical_image_size;
    const hlen = edid.maximum_horizontal_image_size;

    // Decode video_input_definition byte
    const vid_digital = (edid.video_input_definition & 0x80) != 0;
    const vid_dfp_1x = (edid.video_input_definition & 0x01) != 0;

    // Decode feature_support byte
    const fs = edid.feature_support;
    const fs_default_gtf = (fs & 0x01) != 0;
    const fs_preferred = (fs & 0x02) != 0;
    const fs_srgb = (fs & 0x04) != 0;
    const fs_display_type: u8 = (fs >> 3) & 0x03;
    const fs_active_off = (fs & 0x20) != 0;
    const fs_suspend = (fs & 0x40) != 0;
    const fs_standby = (fs & 0x80) != 0;

    // Walk detailed_timings for monitor descriptors
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        if (!isMonitorDescriptor(edid, i)) continue;
        const mon: *align(1) const EdidMonitorDescriptor = @ptrCast(@alignCast(&edid.detailed_timings[i]));

        switch (mon.tag) {
            EDID_MONTIOR_DESCRIPTOR_MANUFACTURER_DEFINED => {},
            EDID_MONITOR_DESCRIPTOR_ASCII_STRING => {
                has_ascii_string = true;
            },
            EDID_MONITOR_DESCRIPTOR_MONITOR_NAME => {
                copyDescriptorString(&monitor_model_name, &mon.data);
            },
            EDID_MONITOR_DESCRIPTOR_MONITOR_RANGE_LIMITS => {
                has_range_limits = true;
                rl_min_v = mon.data[0];
                rl_max_v = mon.data[1];
                rl_min_h = mon.data[2];
                rl_max_h = mon.data[3];
                rl_max_pixclk = mon.data[4];
            },
            EDID_MONITOR_DESCRIPTOR_MONITOR_SERIAL_NUMBER => {
                copyDescriptorString(&monitor_serial_number, &mon.data);
            },
            else => {
                _ = fprintf(stderr_ptr(), "unknown monitor descriptor type 0x%02x\n", @as(c_uint, mon.tag));
            },
        }
    }

    _ = printf("Monitor\n");

    const model_ptr: [*:0]const u8 = if (monitor_model_name[0] != 0)
        @ptrCast(&monitor_model_name[0])
    else
        "n/a";
    _ = printf("  Model name............... %s\n", model_ptr);

    _ = printf("  Manufacturer............. %s\n", @as([*:0]const u8, @ptrCast(&manufacturer[0])));

    // Product code: printed as a single u16 (little-endian host interpretation).
    const product_u16: u16 = @as(u16, edid.product[0]) | (@as(u16, edid.product[1]) << 8);
    _ = printf("  Product code............. %u\n", @as(c_uint, product_u16));

    const serial_u32: u32 = @as(u32, edid.serial_number[0]) |
        (@as(u32, edid.serial_number[1]) << 8) |
        (@as(u32, edid.serial_number[2]) << 16) |
        (@as(u32, edid.serial_number[3]) << 24);
    if (serial_u32 != 0) {
        _ = printf("  Module serial number..... %u\n", @as(c_uint, serial_u32));
    }

    const serial_ptr: [*:0]const u8 = if (monitor_serial_number[0] != 0)
        @ptrCast(&monitor_serial_number[0])
    else
        "n/a";
    _ = printf("  Serial number............ %s\n", serial_ptr);

    _ = printf("  Manufacture date......... %u", @as(c_uint, @as(u32, edid.manufacture_year) + 1990));
    if (edid.manufacture_week <= 52)
        _ = printf(", ISO week %u", @as(c_uint, edid.manufacture_week));
    _ = printf("\n");

    _ = printf("  EDID revision............ %u.%u\n", @as(c_uint, edid.version), @as(c_uint, edid.revision));

    _ = printf("  Input signal type........ %s\n", @as([*:0]const u8, if (vid_digital) "Digital" else "Analog"));
    if (vid_digital) {
        _ = printf("  VESA DFP 1.x supported... %s\n", @as([*:0]const u8, if (vid_dfp_1x) "Yes" else "No"));
    }

    const display_type_str: [*:0]const u8 = switch (fs_display_type) {
        EDID_DISPLAY_TYPE_MONOCHROME => "Monochrome or greyscale",
        EDID_DISPLAY_TYPE_RGB => "sRGB colour",
        EDID_DISPLAY_TYPE_NON_RGB => "Non-sRGB colour",
        else => "Undefined",
    };
    _ = printf("  Display type............. %s\n", display_type_str);

    const diag_mm: f64 = sqrt(@as(f64, @floatFromInt(@as(u32, hlen) * @as(u32, hlen) + @as(u32, vlen) * @as(u32, vlen))));
    _ = printf(
        "  Screen size.............. %u mm x %u mm (%.1f in)\n",
        @as(c_uint, @as(u32, hlen) * 10),
        @as(c_uint, @as(u32, vlen) * 10),
        diag_mm * 0.3937,
    );

    // Power management
    const any_pm = fs_active_off or fs_suspend or fs_standby;
    _ = printf(
        "  Power management......... %s%s%s%s\n",
        @as([*:0]const u8, if (fs_active_off) "Active off, " else ""),
        @as([*:0]const u8, if (fs_suspend) "Suspend, " else ""),
        @as([*:0]const u8, if (fs_standby) "Standby, " else ""),
        @as([*:0]const u8, if (any_pm) "\x08\x08  " else "n/a"),
    );

    _ = printf("  Extension blocks......... %u\n", @as(c_uint, edid.extensions));
    _ = printf("\n");

    if (has_ascii_string) {
        _ = printf("General purpose ASCII string\n");
        var j: usize = 0;
        while (j < 4) : (j += 1) {
            if (!isMonitorDescriptor(edid, j)) continue;
            const mon: *align(1) const EdidMonitorDescriptor = @ptrCast(@alignCast(&edid.detailed_timings[j]));
            if (mon.tag == EDID_MONITOR_DESCRIPTOR_ASCII_STRING) {
                var s: [14]u8 = @splat(0);
                copyDescriptorString(&s, &mon.data);
                _ = printf("  ASCII string............. %s\n", @as([*:0]const u8, @ptrCast(&s[0])));
            }
        }
        _ = printf("\n");
    }

    // Color characteristics
    // color_lo_0: green_y_low:2(7:6) green_x_low:2(5:4) red_y_low:2(3:2) red_x_low:2(1:0)
    // color_lo_1: white_y_low:2(7:6) white_x_low:2(5:4) blue_y_low:2(3:2) blue_x_low:2(1:0)
    const cl0 = edid.color_lo_0;
    const cl1 = edid.color_lo_1;
    const red_x_low: u8 = (cl0 >> 0) & 0x3;
    const red_y_low: u8 = (cl0 >> 2) & 0x3;
    const green_x_low: u8 = (cl0 >> 4) & 0x3;
    const green_y_low: u8 = (cl0 >> 6) & 0x3;
    const blue_x_low: u8 = (cl1 >> 0) & 0x3;
    const blue_y_low: u8 = (cl1 >> 2) & 0x3;
    const white_x_low: u8 = (cl1 >> 4) & 0x3;
    const white_y_low: u8 = (cl1 >> 6) & 0x3;

    const red_x16: u16 = (@as(u16, edid.red_x) << 2) | red_x_low;
    const red_y16: u16 = (@as(u16, edid.red_y) << 2) | red_y_low;
    const green_x16: u16 = (@as(u16, edid.green_x) << 2) | green_x_low;
    const green_y16: u16 = (@as(u16, edid.green_y) << 2) | green_y_low;
    const blue_x16: u16 = (@as(u16, edid.blue_x) << 2) | blue_x_low;
    const blue_y16: u16 = (@as(u16, edid.blue_y) << 2) | blue_y_low;
    const white_x16: u16 = (@as(u16, edid.white_x) << 2) | white_x_low;
    const white_y16: u16 = (@as(u16, edid.white_y) << 2) | white_y_low;

    _ = printf("Color characteristics\n");
    _ = printf("  Default color space...... %ssRGB\n", @as([*:0]const u8, if (fs_srgb) "" else "Non-"));
    _ = printf("  Display gamma............ %.2f\n", edidGamma(edid));
    _ = printf("  Red chromaticity......... Rx %0.3f - Ry %0.3f\n", edidDecodeFixedPoint(red_x16), edidDecodeFixedPoint(red_y16));
    _ = printf("  Green chromaticity....... Gx %0.3f - Gy %0.3f\n", edidDecodeFixedPoint(green_x16), edidDecodeFixedPoint(green_y16));
    _ = printf("  Blue chromaticity........ Bx %0.3f - By %0.3f\n", edidDecodeFixedPoint(blue_x16), edidDecodeFixedPoint(blue_y16));
    _ = printf("  White point (default).... Wx %0.3f - Wy %0.3f\n", edidDecodeFixedPoint(white_x16), edidDecodeFixedPoint(white_y16));
    _ = printf("\n");

    _ = printf("Timing characteristics\n");
    if (has_range_limits) {
        _ = printf("  Horizontal scan range.... %u - %u kHz\n", @as(c_uint, rl_min_h), @as(c_uint, rl_max_h));
        _ = printf("  Vertical scan range...... %u - %u Hz\n", @as(c_uint, rl_min_v), @as(c_uint, rl_max_v));
        _ = printf("  Video bandwidth.......... %u MHz\n", @as(c_uint, @as(u32, rl_max_pixclk) * 10));
    }

    _ = printf("  GTF standard............. %sSupported\n", @as([*:0]const u8, if (fs_default_gtf) "" else "Not "));

    _ = printf("  Preferred timing......... %s\n", @as([*:0]const u8, if (fs_preferred) "Yes" else "No"));

    if (fs_preferred) {
        const dt0: *align(1) const EdidDetailedTiming = @ptrCast(@alignCast(&edid.detailed_timings[0]));
        _ = printf("  Native/preferred timing.. ");
        printEdidTimingString(dt0);
        _ = printf("\n");
        _ = printf("    Modeline............... ");
        printEdidModeString(dt0);
        _ = printf("\n");
    } else {
        _ = printf("  Native/preferred timing.. n/a\n");
    }
    _ = printf("\n");

    // Established / standard timings
    _ = printf("Standard timings supported\n");
    const et0 = edid.established_timings_0;
    const et1 = edid.established_timings_1;
    if ((et0 & 0x80) != 0) _ = printf("   720 x  400p @ 70Hz - IBM VGA\n");
    if ((et0 & 0x40) != 0) _ = printf("   720 x  400p @ 88Hz - IBM XGA2\n");
    if ((et0 & 0x20) != 0) _ = printf("   640 x  480p @ 60Hz - IBM VGA\n");
    if ((et0 & 0x10) != 0) _ = printf("   640 x  480p @ 67Hz - Apple Mac II\n");
    if ((et0 & 0x08) != 0) _ = printf("   640 x  480p @ 72Hz - VESA\n");
    if ((et0 & 0x04) != 0) _ = printf("   640 x  480p @ 75Hz - VESA\n");
    if ((et0 & 0x02) != 0) _ = printf("   800 x  600p @ 56Hz - VESA\n");
    if ((et0 & 0x01) != 0) _ = printf("   800 x  600p @ 60Hz - VESA\n");
    if ((et1 & 0x80) != 0) _ = printf("   800 x  600p @ 72Hz - VESA\n");
    if ((et1 & 0x40) != 0) _ = printf("   800 x  600p @ 75Hz - VESA\n");
    if ((et1 & 0x20) != 0) _ = printf("   832 x  624p @ 75Hz - Apple Mac II\n");
    if ((et1 & 0x10) != 0) _ = printf("  1024 x  768i @ 87Hz - VESA\n");
    if ((et1 & 0x08) != 0) _ = printf("  1024 x  768p @ 60Hz - VESA\n");
    if ((et1 & 0x04) != 0) _ = printf("  1024 x  768p @ 70Hz - VESA\n");
    if ((et1 & 0x02) != 0) _ = printf("  1024 x  768p @ 75Hz - VESA\n");
    if ((et1 & 0x01) != 0) _ = printf("  1280 x 1024p @ 75Hz - VESA\n");

    var sti: usize = 0;
    while (sti < 8) : (sti += 1) {
        const raw = edid.standard_timing_id[sti];
        if (raw[0] == EDID_STANDARD_TIMING_DESCRIPTOR_INVALID[0] and
            raw[1] == EDID_STANDARD_TIMING_DESCRIPTOR_INVALID[1]) continue;
        const hactive: u32 = (@as(u32, raw[0]) + 31) * 8;
        const aspect: u8 = (raw[1] >> 6) & 0x3;
        const refresh: u32 = @as(u32, raw[1] & 0x3f) + 60;
        const vactive: u32 = switch (aspect) {
            EDID_ASPECT_RATIO_16_10 => (hactive * 10) >> 4,
            EDID_ASPECT_RATIO_4_3 => (hactive * 3) >> 2,
            EDID_ASPECT_RATIO_5_4 => (hactive << 2) / 5,
            EDID_ASPECT_RATIO_16_9 => (hactive * 9) >> 4,
            else => hactive,
        };
        _ = printf(
            "  %4u x %4u%c @ %uHz - VESA STD\n",
            @as(c_uint, hactive),
            @as(c_uint, vactive),
            @as(c_int, 'p'),
            @as(c_uint, refresh),
        );
    }
    _ = printf("\n");
}

// Copy up to 13 bytes from descriptor .data[] into a local 14-byte buffer,
// NUL-terminating at the first '\n' or at byte 13.
fn copyDescriptorString(dst: *[14]u8, src: *const [13]u8) void {
    var k: usize = 0;
    while (k < 13) : (k += 1) {
        if (src[k] == '\n') break;
        dst[k] = src[k];
    }
    dst[k] = 0;
}

// ---------------------------------------------------------------------------
// CEA-861 data-block handlers
// ---------------------------------------------------------------------------

fn dispCea861AudioData(header: [*]const u8) void {
    // header[0] = tag<<5 | length:5
    const length: u8 = header[0] & 0x1f;
    const sad_size: u8 = 3; // bytes per short audio descriptor
    const descriptors: u8 = length / sad_size;

    _ = printf("CE audio data (formats supported)\n");
    var i: u8 = 0;
    while (i < descriptors) : (i += 1) {
        const sad = header + 1 + @as(usize, i) * sad_size;
        const b0 = sad[0];
        const b1 = sad[1];
        const b2 = sad[2];

        const channels: u8 = b0 & 0x7; // +1 on print
        const audio_format: u4 = @truncate((b0 >> 3) & 0xf);

        const sr_32: u8 = (b1 >> 0) & 1;
        const sr_44: u8 = (b1 >> 1) & 1;
        const sr_48: u8 = (b1 >> 2) & 1;
        const sr_88: u8 = (b1 >> 3) & 1;
        const sr_96: u8 = (b1 >> 4) & 1;
        const sr_176: u8 = (b1 >> 5) & 1;
        const sr_192: u8 = (b1 >> 6) & 1;

        switch (audio_format) {
            CEA861_AUDIO_FORMAT_LPCM => {
                const b16: u8 = (b2 >> 0) & 1;
                const b20: u8 = (b2 >> 1) & 1;
                const b24: u8 = (b2 >> 2) & 1;
                const multi = (@as(u32, b16) + b20 + b24) > 1;
                _ = printf(
                    "  LPCM    %u-channel, %s%s%s\x08%s",
                    @as(c_uint, channels + 1),
                    @as([*:0]const u8, if (b16 != 0) "16/" else ""),
                    @as([*:0]const u8, if (b20 != 0) "20/" else ""),
                    @as([*:0]const u8, if (b24 != 0) "24/" else ""),
                    @as([*:0]const u8, if (multi) " bit depths" else "-bit"),
                );
            },
            CEA861_AUDIO_FORMAT_AC_3 => {
                _ = printf(
                    "  AC-3    %u-channel, %4uk max. bit rate",
                    @as(c_uint, channels + 1),
                    @as(c_uint, @as(u32, b2) << 3),
                );
            },
            else => {
                _ = fprintf(stderr_ptr(), "unknown audio format 0x%02x\n", @as(c_uint, audio_format));
                continue;
            },
        }

        _ = printf(
            " at %s%s%s%s%s%s%s\x08 kHz\n",
            @as([*:0]const u8, if (sr_32 != 0) "32/" else ""),
            @as([*:0]const u8, if (sr_44 != 0) "44.1/" else ""),
            @as([*:0]const u8, if (sr_48 != 0) "48/" else ""),
            @as([*:0]const u8, if (sr_88 != 0) "88.2/" else ""),
            @as([*:0]const u8, if (sr_96 != 0) "96/" else ""),
            @as([*:0]const u8, if (sr_176 != 0) "176.4/" else ""),
            @as([*:0]const u8, if (sr_192 != 0) "192/" else ""),
        );
    }
    _ = printf("\n");
}

const Cea861Timing = struct {
    hactive: u16,
    vactive: u16,
    interlaced: bool,
    vfreq: f64,
};

// Minimal table mirroring cea861.h (indices 1..64, indices not listed are
// zeroed). We only need hactive/vactive/interlaced/vfreq for disp output.
const cea861_timings = blk: {
    var t: [65]Cea861Timing = @splat(.{ .hactive = 0, .vactive = 0, .interlaced = false, .vfreq = 0 });
    t[1] = .{ .hactive = 640, .vactive = 480, .interlaced = false, .vfreq = 59.940 };
    t[2] = .{ .hactive = 720, .vactive = 480, .interlaced = false, .vfreq = 59.940 };
    t[3] = .{ .hactive = 720, .vactive = 480, .interlaced = false, .vfreq = 59.940 };
    t[4] = .{ .hactive = 1280, .vactive = 720, .interlaced = false, .vfreq = 60.000 };
    t[5] = .{ .hactive = 1920, .vactive = 1080, .interlaced = true, .vfreq = 60.000 };
    t[6] = .{ .hactive = 1440, .vactive = 480, .interlaced = true, .vfreq = 59.940 };
    t[7] = .{ .hactive = 1440, .vactive = 480, .interlaced = true, .vfreq = 59.940 };
    t[8] = .{ .hactive = 1440, .vactive = 240, .interlaced = false, .vfreq = 60.054 };
    t[9] = .{ .hactive = 1440, .vactive = 240, .interlaced = false, .vfreq = 59.826 };
    t[10] = .{ .hactive = 2880, .vactive = 480, .interlaced = true, .vfreq = 59.940 };
    t[11] = .{ .hactive = 2880, .vactive = 480, .interlaced = true, .vfreq = 59.940 };
    t[12] = .{ .hactive = 2880, .vactive = 240, .interlaced = false, .vfreq = 60.054 };
    t[13] = .{ .hactive = 2880, .vactive = 240, .interlaced = false, .vfreq = 59.826 };
    t[14] = .{ .hactive = 1440, .vactive = 480, .interlaced = false, .vfreq = 59.940 };
    t[15] = .{ .hactive = 1440, .vactive = 480, .interlaced = false, .vfreq = 59.940 };
    t[16] = .{ .hactive = 1920, .vactive = 1080, .interlaced = false, .vfreq = 60.000 };
    t[17] = .{ .hactive = 720, .vactive = 576, .interlaced = false, .vfreq = 50.000 };
    t[18] = .{ .hactive = 720, .vactive = 576, .interlaced = false, .vfreq = 50.000 };
    t[19] = .{ .hactive = 1280, .vactive = 720, .interlaced = false, .vfreq = 50.000 };
    t[20] = .{ .hactive = 1920, .vactive = 1080, .interlaced = true, .vfreq = 50.000 };
    t[21] = .{ .hactive = 1440, .vactive = 576, .interlaced = true, .vfreq = 50.000 };
    t[22] = .{ .hactive = 1440, .vactive = 576, .interlaced = true, .vfreq = 50.000 };
    t[23] = .{ .hactive = 1440, .vactive = 288, .interlaced = false, .vfreq = 50.080 };
    t[24] = .{ .hactive = 1440, .vactive = 288, .interlaced = false, .vfreq = 49.920 };
    t[25] = .{ .hactive = 2880, .vactive = 576, .interlaced = true, .vfreq = 50.000 };
    t[26] = .{ .hactive = 2880, .vactive = 576, .interlaced = true, .vfreq = 50.000 };
    t[27] = .{ .hactive = 2880, .vactive = 288, .interlaced = false, .vfreq = 50.080 };
    t[28] = .{ .hactive = 2880, .vactive = 288, .interlaced = false, .vfreq = 49.920 };
    t[29] = .{ .hactive = 1440, .vactive = 576, .interlaced = false, .vfreq = 50.000 };
    t[30] = .{ .hactive = 1440, .vactive = 576, .interlaced = false, .vfreq = 50.000 };
    t[31] = .{ .hactive = 1920, .vactive = 1080, .interlaced = false, .vfreq = 50.000 };
    t[32] = .{ .hactive = 1920, .vactive = 1080, .interlaced = false, .vfreq = 24.000 };
    t[33] = .{ .hactive = 1920, .vactive = 1080, .interlaced = false, .vfreq = 25.000 };
    t[34] = .{ .hactive = 1920, .vactive = 1080, .interlaced = false, .vfreq = 30.000 };
    t[35] = .{ .hactive = 2880, .vactive = 480, .interlaced = false, .vfreq = 59.940 };
    t[36] = .{ .hactive = 2880, .vactive = 480, .interlaced = false, .vfreq = 59.940 };
    t[37] = .{ .hactive = 2880, .vactive = 576, .interlaced = false, .vfreq = 50.000 };
    t[38] = .{ .hactive = 2880, .vactive = 576, .interlaced = false, .vfreq = 50.000 };
    t[39] = .{ .hactive = 1920, .vactive = 1080, .interlaced = true, .vfreq = 50.000 };
    t[40] = .{ .hactive = 1920, .vactive = 1080, .interlaced = true, .vfreq = 100.000 };
    t[41] = .{ .hactive = 1280, .vactive = 720, .interlaced = false, .vfreq = 100.000 };
    t[42] = .{ .hactive = 720, .vactive = 576, .interlaced = false, .vfreq = 100.000 };
    t[43] = .{ .hactive = 720, .vactive = 576, .interlaced = false, .vfreq = 100.000 };
    t[44] = .{ .hactive = 1440, .vactive = 576, .interlaced = true, .vfreq = 100.000 };
    t[45] = .{ .hactive = 1440, .vactive = 576, .interlaced = true, .vfreq = 100.000 };
    t[46] = .{ .hactive = 1920, .vactive = 1080, .interlaced = true, .vfreq = 120.000 };
    t[47] = .{ .hactive = 1280, .vactive = 720, .interlaced = false, .vfreq = 120.000 };
    t[48] = .{ .hactive = 720, .vactive = 480, .interlaced = false, .vfreq = 119.880 };
    t[49] = .{ .hactive = 720, .vactive = 480, .interlaced = false, .vfreq = 119.880 };
    t[50] = .{ .hactive = 1440, .vactive = 480, .interlaced = true, .vfreq = 119.880 };
    t[51] = .{ .hactive = 1440, .vactive = 480, .interlaced = true, .vfreq = 119.880 };
    t[52] = .{ .hactive = 720, .vactive = 576, .interlaced = false, .vfreq = 200.000 };
    t[53] = .{ .hactive = 720, .vactive = 576, .interlaced = false, .vfreq = 200.000 };
    t[54] = .{ .hactive = 1440, .vactive = 576, .interlaced = true, .vfreq = 200.000 };
    t[55] = .{ .hactive = 1440, .vactive = 576, .interlaced = true, .vfreq = 200.000 };
    t[56] = .{ .hactive = 720, .vactive = 480, .interlaced = false, .vfreq = 239.760 };
    t[57] = .{ .hactive = 720, .vactive = 480, .interlaced = false, .vfreq = 239.760 };
    t[58] = .{ .hactive = 1440, .vactive = 480, .interlaced = true, .vfreq = 239.760 };
    t[59] = .{ .hactive = 1440, .vactive = 480, .interlaced = true, .vfreq = 239.760 };
    t[60] = .{ .hactive = 1280, .vactive = 720, .interlaced = false, .vfreq = 24.000 };
    t[61] = .{ .hactive = 1280, .vactive = 720, .interlaced = false, .vfreq = 25.000 };
    t[62] = .{ .hactive = 1280, .vactive = 720, .interlaced = false, .vfreq = 30.000 };
    t[63] = .{ .hactive = 1920, .vactive = 1080, .interlaced = false, .vfreq = 120.000 };
    t[64] = .{ .hactive = 1920, .vactive = 1080, .interlaced = false, .vfreq = 100.000 };
    break :blk t;
};

fn dispCea861VideoData(header: [*]const u8) void {
    const length: u8 = header[0] & 0x1f;
    _ = printf("CE video identifiers (VICs) - timing/formats supported\n");
    var i: u8 = 0;
    while (i < length) : (i += 1) {
        const svd = header[1 + i];
        const vic: u8 = svd & 0x7f;
        const native: u8 = (svd >> 7) & 0x1;
        const timing = if (vic < cea861_timings.len) cea861_timings[vic] else Cea861Timing{ .hactive = 0, .vactive = 0, .interlaced = false, .vfreq = 0 };
        const mode: u8 = if (timing.interlaced) 'i' else 'p';
        _ = printf(
            " %s CEA Mode %02u: %4u x %4u%c @ %.fHz\n",
            @as([*:0]const u8, if (native != 0) "*" else " "),
            @as(c_uint, vic),
            @as(c_uint, timing.hactive),
            @as(c_uint, timing.vactive),
            @as(c_int, mode),
            timing.vfreq,
        );
    }
    _ = printf("\n");
}

fn dispCea861VendorData(header: [*]const u8) void {
    const length: u8 = header[0] & 0x1f;
    // OUI printed in reverse (MSB first) from bytes [1..3]
    const oui0 = header[3];
    const oui1 = header[2];
    const oui2 = header[1];

    _ = printf("CEA vendor specific data (VSDB)\n");
    _ = printf("  IEEE registration number. 0x");
    _ = printf("%02X", @as(c_uint, oui0));
    _ = printf("%02X", @as(c_uint, oui1));
    _ = printf("%02X", @as(c_uint, oui2));
    _ = printf("\n");

    // HDMI_OUI comparison: bytes[1..3] should equal {LSB=0x03, 0x0C, 0x00}
    // (HDMI_OUI itself is {0x00,0x0C,0x03}, reversed on wire)
    const is_hdmi = header[1] == 0x03 and header[2] == 0x0C and header[3] == 0x00;
    if (is_hdmi) {
        // Physical address bytes at header[4..5]
        const pc_ab = header[4];
        const pc_cd = header[5];
        // Per hdmi.h packed struct: byte4 = [pc_a:4 | pc_b:4], byte5 = [pc_c:4 | pc_d:4]
        // The bit-field order (LSB-first on LE) means the first field (pc_b) occupies the low nibble.
        const pc_b: u8 = pc_ab & 0x0f;
        const pc_a: u8 = (pc_ab >> 4) & 0x0f;
        const pc_d: u8 = pc_cd & 0x0f;
        const pc_c: u8 = (pc_cd >> 4) & 0x0f;
        _ = printf(
            "  CEC physical address..... %u.%u.%u.%u\n",
            @as(c_uint, pc_a),
            @as(c_uint, pc_b),
            @as(c_uint, pc_c),
            @as(c_uint, pc_d),
        );

        if (length >= HDMI_VSDB_EXTENSION_FLAGS_OFFSET) {
            const flags = header[6];
            // bit7 audio_info, bit6 48bpp, bit5 36bpp, bit4 30bpp, bit3 yuv444, bit0 dvi_dual
            _ = printf("  Supports AI (ACP, ISRC).. %s\n", @as([*:0]const u8, if ((flags & 0x80) != 0) "Yes" else "No"));
            _ = printf("  Supports 48bpp........... %s\n", @as([*:0]const u8, if ((flags & 0x40) != 0) "Yes" else "No"));
            _ = printf("  Supports 36bpp........... %s\n", @as([*:0]const u8, if ((flags & 0x20) != 0) "Yes" else "No"));
            _ = printf("  Supports 30bpp........... %s\n", @as([*:0]const u8, if ((flags & 0x10) != 0) "Yes" else "No"));
            _ = printf("  Supports YCbCr 4:4:4..... %s\n", @as([*:0]const u8, if ((flags & 0x08) != 0) "Yes" else "No"));
            _ = printf("  Supports dual-link DVI... %s\n", @as([*:0]const u8, if ((flags & 0x01) != 0) "Yes" else "No"));
        }

        if (length >= HDMI_VSDB_MAX_TMDS_OFFSET) {
            const max_tmds = header[7];
            if (max_tmds != 0)
                _ = printf("  Maximum TMDS clock....... %uMHz\n", @as(c_uint, @as(u32, max_tmds) * 5))
            else
                _ = printf("  Maximum TMDS clock....... n/a\n");
        }

        if (length >= HDMI_VSDB_LATENCY_FIELDS_OFFSET) {
            const lat_flags = header[8];
            // bit7 latency_fields, bit6 interlaced_latency_fields
            const has_latency = (lat_flags & 0x80) != 0;
            const has_ilatency = (lat_flags & 0x40) != 0;

            if (has_latency and length >= 10) {
                const vid = header[9];
                const aud = header[10];
                const tag: [*:0]const u8 = if (has_ilatency) "(p)" else "...";
                _ = printf("  Video latency %s........ %ums\n", tag, @as(c_uint, (@as(u32, vid) - 1) << 1));
                _ = printf("  Audio latency %s........ %ums\n", tag, @as(c_uint, (@as(u32, aud) - 1) << 1));
            }
            if (has_ilatency and length >= 12) {
                const ivid = header[11];
                const iaud = header[12];
                _ = printf("  Video latency (i)........ %ums\n", @as(c_uint, ivid));
                _ = printf("  Audio latency (i)........ %ums\n", @as(c_uint, iaud));
            }
        }
    }
    _ = printf("\n");
}

fn dispCea861SpeakerAllocation(header: [*]const u8) void {
    const b0 = header[1];
    const b1 = header[2];
    _ = printf("CEA speaker allocation data\n");
    _ = printf(
        "  Channel configuration.... %u.%u\n",
        @as(c_uint, (@popCount(b0 & 0xe9) << 1) + (@popCount(b0 & 0x14) << 0) +
            (@popCount(b1 & 0x01) << 1) + (@popCount(b1 & 0x06) << 0)),
        @as(c_uint, b0 & 0x02),
    );
    _ = printf("  Front left/right......... %s\n", yn(b0 & 0x01));
    _ = printf("  Front LFE................ %s\n", yn(b0 & 0x02));
    _ = printf("  Front center............. %s\n", yn(b0 & 0x04));
    _ = printf("  Rear left/right.......... %s\n", yn(b0 & 0x08));
    _ = printf("  Rear center.............. %s\n", yn(b0 & 0x10));
    _ = printf("  Front left/right center.. %s\n", yn(b0 & 0x20));
    _ = printf("  Rear left/right center... %s\n", yn(b0 & 0x40));
    _ = printf("  Front left/right wide.... %s\n", yn(b0 & 0x80));
    _ = printf("  Front left/right high.... %s\n", yn(b1 & 0x01));
    _ = printf("  Top center............... %s\n", yn(b1 & 0x02));
    _ = printf("  Front center high........ %s\n", yn(b1 & 0x04));
    _ = printf("\n");
}

fn yn(v: u8) [*:0]const u8 {
    return if (v != 0) "Yes" else "No";
}

fn dispCea861(ext: [*]const u8) void {
    const revision = ext[1];
    const dtd_offset = ext[2];
    const flags = ext[3];
    const offset: u8 = 4; // offsetof(data)

    _ = printf("CEA-861 Information\n");
    _ = printf("  Revision number.......... %u\n", @as(c_uint, revision));

    if (revision >= 2) {
        const underscan = (flags & 0x80) != 0;
        const basic_audio = (flags & 0x40) != 0;
        const yuv444 = (flags & 0x20) != 0;
        const yuv422 = (flags & 0x10) != 0;
        const native_dtds: u8 = flags & 0x0f;
        _ = printf("  IT underscan............. %supported\n", @as([*:0]const u8, if (underscan) "S" else "Not s"));
        _ = printf("  Basic audio.............. %supported\n", @as([*:0]const u8, if (basic_audio) "S" else "Not s"));
        _ = printf("  YCbCr 4:4:4.............. %supported\n", @as([*:0]const u8, if (yuv444) "S" else "Not s"));
        _ = printf("  YCbCr 4:2:2.............. %supported\n", @as([*:0]const u8, if (yuv422) "S" else "Not s"));
        _ = printf("  Native formats........... %u\n", @as(c_uint, native_dtds));
    }

    // Walk DTDs
    var pos: usize = dtd_offset;
    var idx: u8 = 0;
    while (pos + 18 <= 128) : ({
        idx += 1;
        pos += 18;
    }) {
        const pclk: u16 = @as(u16, ext[pos]) | (@as(u16, ext[pos + 1]) << 8);
        if (pclk == 0) break;
        const dtd: *align(1) const EdidDetailedTiming = @ptrCast(@alignCast(ext + pos));
        _ = printf("  Detailed timing #%u....... ", @as(c_uint, idx + 1));
        printEdidTimingString(dtd);
        _ = printf("\n");
        _ = printf("    Modeline............... ");
        printEdidModeString(dtd);
        _ = printf("\n");
    }
    _ = printf("\n");

    if (revision >= 3) {
        var index: usize = 0;
        const end: usize = @as(usize, dtd_offset) - offset;
        while (index < end) {
            const header = ext + offset + index;
            const length: u8 = header[0] & 0x1f;
            const tag: u3 = @truncate((header[0] >> 5) & 0x7);

            switch (tag) {
                CEA861_DATA_BLOCK_TYPE_AUDIO => dispCea861AudioData(header),
                CEA861_DATA_BLOCK_TYPE_VIDEO => dispCea861VideoData(header),
                CEA861_DATA_BLOCK_TYPE_VENDOR_SPECIFIC => dispCea861VendorData(header),
                CEA861_DATA_BLOCK_TYPE_SPEAKER_ALLOCATION => dispCea861SpeakerAllocation(header),
                else => {
                    _ = fprintf(stderr_ptr(), "unknown CEA-861 data block type 0x%02x\n", @as(c_uint, tag));
                },
            }

            index += @as(usize, length) + 1;
            if (length == 0) break; // guard against infinite loop on malformed data
        }
    }
    _ = printf("\n");
}

// ---------------------------------------------------------------------------
// Public entrypoint
// ---------------------------------------------------------------------------

/// Parse a 128-byte EDID block (plus any extension blocks referenced by the
/// `extensions` byte) and print a decoded summary to stdout.
/// C-ABI compatible drop-in for `void parse_edid(const uint8_t *data)`.
export fn parse_edid(data: [*]const u8) callconv(.c) void {
    const edid: *align(1) const Edid = @ptrCast(@alignCast(data));

    dumpEdid1(data);
    dispEdid1(edid);

    var i: u8 = 0;
    while (i < edid.extensions) : (i += 1) {
        // each extension is 128 bytes starting at data + 128*(i+1)
        const ext = data + 128 + @as(usize, i) * 128;
        const tag = ext[0];
        switch (tag) {
            EDID_EXTENSION_CEA => {
                dumpCea861(ext);
                dispCea861(ext);
            },
            else => {
                _ = fprintf(stderr_ptr(),
                    "WARNING: block %u contains unknown extension (%#04x)\n",
                    @as(c_uint, i),
                    @as(c_uint, tag),
                );
            },
        }
    }
}
