/// shmif sub-protocol struct layout and enum completeness tests
///
/// Tier 4: Verifies that sub-protocol struct sizes match between Zig's
/// @cImport and C, and that all enum values are accessible from Zig.
const std = @import("std");
const testing = std.testing;

const c = @import("shmif_types");

// C helper externs (shmif_test_helpers.c)

extern fn shmif_test_sizeof_ramp_block() usize;
extern fn shmif_test_sizeof_hdr() usize;
extern fn shmif_test_sizeof_venc() usize;
extern fn shmif_test_sizeof_ofstbl() usize;

// 4a. Sub-protocol struct sizes

test "ramp_block size matches C" {
    const zig_size = @sizeOf(c.struct_ramp_block);
    const c_size = shmif_test_sizeof_ramp_block();
    try testing.expect(c_size > 0);
    try testing.expectEqual(c_size, zig_size);
}

test "arcan_shmif_hdr size matches C" {
    const zig_size = @sizeOf(c.struct_arcan_shmif_hdr);
    const c_size = shmif_test_sizeof_hdr();
    try testing.expect(c_size > 0);
    try testing.expectEqual(c_size, zig_size);
}

test "arcan_shmif_venc size matches C" {
    const zig_size = @sizeOf(c.struct_arcan_shmif_venc);
    const c_size = shmif_test_sizeof_venc();
    try testing.expect(c_size > 0);
    try testing.expectEqual(c_size, zig_size);
}

test "arcan_shmif_ofstbl size matches C" {
    const zig_size = @sizeOf(c.struct_arcan_shmif_ofstbl);
    const c_size = shmif_test_sizeof_ofstbl();
    try testing.expect(c_size > 0);
    try testing.expectEqual(c_size, zig_size);
}

test "ramp_block planes array has SHMIF_CMRAMP_UPLIM floats" {
    const uplim: usize = @intCast(c.SHMIF_CMRAMP_UPLIM);
    try testing.expectEqual(@as(usize, 4095), uplim);

    // The planes field in ramp_block should have SHMIF_CMRAMP_UPLIM elements
    const rb = std.mem.zeroes(c.struct_ramp_block);
    try testing.expectEqual(uplim, rb.planes.len);
}

test "arcan_shmif_ofstbl offsets array has 32 elements" {
    const tbl = std.mem.zeroes(c.struct_arcan_shmif_ofstbl);
    // The offsets array is inside an anonymous union
    try testing.expectEqual(@as(usize, 32), tbl.unnamed_0.offsets.len);
}

// 4b. SEGID enum completeness

test "SEGID enum: all 31 values accessible" {
    // Verify each SEGID value is accessible and has the expected integer value
    try testing.expectEqual(@as(c_int, 0), c.SEGID_UNKNOWN);
    try testing.expectEqual(@as(c_int, 1), c.SEGID_LWA);
    try testing.expectEqual(@as(c_int, 2), c.SEGID_NETWORK_SERVER);
    try testing.expectEqual(@as(c_int, 3), c.SEGID_NETWORK_CLIENT);
    try testing.expectEqual(@as(c_int, 4), c.SEGID_MEDIA);
    try testing.expectEqual(@as(c_int, 5), c.SEGID_TERMINAL);
    try testing.expectEqual(@as(c_int, 6), c.SEGID_REMOTING);
    try testing.expectEqual(@as(c_int, 7), c.SEGID_ENCODER);
    try testing.expectEqual(@as(c_int, 8), c.SEGID_SENSOR);
    try testing.expectEqual(@as(c_int, 9), c.SEGID_GAME);
    try testing.expectEqual(@as(c_int, 10), c.SEGID_APPLICATION);
    try testing.expectEqual(@as(c_int, 11), c.SEGID_BROWSER);
    try testing.expectEqual(@as(c_int, 12), c.SEGID_VM);
    try testing.expectEqual(@as(c_int, 13), c.SEGID_HMD_SBS);
    try testing.expectEqual(@as(c_int, 14), c.SEGID_HMD_L);
    try testing.expectEqual(@as(c_int, 15), c.SEGID_HMD_R);
    try testing.expectEqual(@as(c_int, 16), c.SEGID_POPUP);
    try testing.expectEqual(@as(c_int, 17), c.SEGID_ICON);
    try testing.expectEqual(@as(c_int, 18), c.SEGID_TITLEBAR);
    try testing.expectEqual(@as(c_int, 19), c.SEGID_CURSOR);
    try testing.expectEqual(@as(c_int, 20), c.SEGID_ACCESSIBILITY);
    try testing.expectEqual(@as(c_int, 21), c.SEGID_CLIPBOARD);
    try testing.expectEqual(@as(c_int, 22), c.SEGID_CLIPBOARD_PASTE);
    try testing.expectEqual(@as(c_int, 23), c.SEGID_WIDGET);
    try testing.expectEqual(@as(c_int, 24), c.SEGID_TUI);
    try testing.expectEqual(@as(c_int, 25), c.SEGID_SERVICE);
    try testing.expectEqual(@as(c_int, 26), c.SEGID_BRIDGE_X11);
    try testing.expectEqual(@as(c_int, 27), c.SEGID_BRIDGE_WAYLAND);
    try testing.expectEqual(@as(c_int, 28), c.SEGID_HANDOVER);
    try testing.expectEqual(@as(c_int, 29), c.SEGID_AUDIO);
    try testing.expectEqual(@as(c_int, 30), c.SEGID_BRIDGE_ALLOCATOR);
    try testing.expectEqual(@as(c_int, 254), c.SEGID_MONITOR);
    try testing.expectEqual(@as(c_int, 255), c.SEGID_DEBUG);
}

test "SEGID_LIM sentinel is INT_MAX" {
    // INT_MAX for c_int (i32) is 2147483647
    try testing.expectEqual(@as(c_int, std.math.maxInt(c_int)), c.SEGID_LIM);
}

// 4c. TARGET_COMMAND enum completeness

test "TARGET_COMMAND enum: all 30 values accessible" {
    try testing.expectEqual(@as(c_int, 1), c.TARGET_COMMAND_EXIT);
    try testing.expectEqual(@as(c_int, 2), c.TARGET_COMMAND_FRAMESKIP);
    try testing.expectEqual(@as(c_int, 3), c.TARGET_COMMAND_STEPFRAME);
    try testing.expectEqual(@as(c_int, 4), c.TARGET_COMMAND_COREOPT);
    try testing.expectEqual(@as(c_int, 5), c.TARGET_COMMAND_STORE);
    try testing.expectEqual(@as(c_int, 6), c.TARGET_COMMAND_RESTORE);
    try testing.expectEqual(@as(c_int, 7), c.TARGET_COMMAND_BCHUNK_IN);
    try testing.expectEqual(@as(c_int, 8), c.TARGET_COMMAND_BCHUNK_OUT);
    try testing.expectEqual(@as(c_int, 9), c.TARGET_COMMAND_RESET);
    try testing.expectEqual(@as(c_int, 10), c.TARGET_COMMAND_PAUSE);
    try testing.expectEqual(@as(c_int, 11), c.TARGET_COMMAND_UNPAUSE);
    try testing.expectEqual(@as(c_int, 12), c.TARGET_COMMAND_SEEKTIME);
    try testing.expectEqual(@as(c_int, 13), c.TARGET_COMMAND_SEEKCONTENT);
    try testing.expectEqual(@as(c_int, 14), c.TARGET_COMMAND_DISPLAYHINT);
    try testing.expectEqual(@as(c_int, 15), c.TARGET_COMMAND_SETIODEV);
    try testing.expectEqual(@as(c_int, 16), c.TARGET_COMMAND_STREAMSET);
    try testing.expectEqual(@as(c_int, 17), c.TARGET_COMMAND_ATTENUATE);
    try testing.expectEqual(@as(c_int, 18), c.TARGET_COMMAND_AUDDELAY);
    try testing.expectEqual(@as(c_int, 19), c.TARGET_COMMAND_NEWSEGMENT);
    try testing.expectEqual(@as(c_int, 20), c.TARGET_COMMAND_REQFAIL);
    try testing.expectEqual(@as(c_int, 21), c.TARGET_COMMAND_BUFFER_FAIL);
    try testing.expectEqual(@as(c_int, 22), c.TARGET_COMMAND_DEVICE_NODE);
    try testing.expectEqual(@as(c_int, 23), c.TARGET_COMMAND_GRAPHMODE);
    try testing.expectEqual(@as(c_int, 24), c.TARGET_COMMAND_MESSAGE);
    try testing.expectEqual(@as(c_int, 25), c.TARGET_COMMAND_FONTHINT);
    try testing.expectEqual(@as(c_int, 26), c.TARGET_COMMAND_GEOHINT);
    try testing.expectEqual(@as(c_int, 27), c.TARGET_COMMAND_OUTPUTHINT);
    try testing.expectEqual(@as(c_int, 28), c.TARGET_COMMAND_ACTIVATE);
    try testing.expectEqual(@as(c_int, 29), c.TARGET_COMMAND_DEVICESTATE);
    try testing.expectEqual(@as(c_int, 30), c.TARGET_COMMAND_ANCHORHINT);
}

test "TARGET_COMMAND_LIMIT sentinel is INT_MAX" {
    try testing.expectEqual(@as(c_int, std.math.maxInt(c_int)), c.TARGET_COMMAND_LIMIT);
}

// 4d. EVENT_EXTERNAL enum completeness

test "EVENT_EXTERNAL enum: all 22 values accessible" {
    try testing.expectEqual(@as(c_int, 0), c.EVENT_EXTERNAL_MESSAGE);
    try testing.expectEqual(@as(c_int, 1), c.EVENT_EXTERNAL_COREOPT);
    try testing.expectEqual(@as(c_int, 2), c.EVENT_EXTERNAL_IDENT);
    try testing.expectEqual(@as(c_int, 3), c.EVENT_EXTERNAL_FAILURE);
    try testing.expectEqual(@as(c_int, 4), c.EVENT_EXTERNAL_BUFFERSTREAM);
    try testing.expectEqual(@as(c_int, 5), c.EVENT_EXTERNAL_FRAMESTATUS);
    try testing.expectEqual(@as(c_int, 6), c.EVENT_EXTERNAL_STREAMINFO);
    try testing.expectEqual(@as(c_int, 7), c.EVENT_EXTERNAL_STREAMSTATUS);
    try testing.expectEqual(@as(c_int, 8), c.EVENT_EXTERNAL_STATESIZE);
    try testing.expectEqual(@as(c_int, 9), c.EVENT_EXTERNAL_FLUSHAUD);
    try testing.expectEqual(@as(c_int, 10), c.EVENT_EXTERNAL_SEGREQ);
    // Note: 11 is skipped in the enum
    try testing.expectEqual(@as(c_int, 12), c.EVENT_EXTERNAL_CURSORHINT);
    try testing.expectEqual(@as(c_int, 13), c.EVENT_EXTERNAL_VIEWPORT);
    try testing.expectEqual(@as(c_int, 14), c.EVENT_EXTERNAL_CONTENT);
    try testing.expectEqual(@as(c_int, 15), c.EVENT_EXTERNAL_LABELHINT);
    try testing.expectEqual(@as(c_int, 16), c.EVENT_EXTERNAL_REGISTER);
    try testing.expectEqual(@as(c_int, 17), c.EVENT_EXTERNAL_ALERT);
    try testing.expectEqual(@as(c_int, 18), c.EVENT_EXTERNAL_CLOCKREQ);
    try testing.expectEqual(@as(c_int, 19), c.EVENT_EXTERNAL_BCHUNKSTATE);
    try testing.expectEqual(@as(c_int, 20), c.EVENT_EXTERNAL_PRIVDROP);
    try testing.expectEqual(@as(c_int, 21), c.EVENT_EXTERNAL_INPUTMASK);
    try testing.expectEqual(@as(c_int, 22), c.EVENT_EXTERNAL_NETSTATE);
}

test "EVENT_EXTERNAL_ULIM sentinel is INT_MAX" {
    try testing.expectEqual(@as(c_int, std.math.maxInt(c_int)), c.EVENT_EXTERNAL_ULIM);
}

// 4e. SHMIF_RHINT flags

test "SHMIF_RHINT flags have expected values" {
    try testing.expectEqual(@as(c_uint, 0), c.SHMIF_RHINT_ORIGO_UL);
    try testing.expectEqual(@as(c_uint, 1), c.SHMIF_RHINT_ORIGO_LL);
    try testing.expectEqual(@as(c_uint, 2), c.SHMIF_RHINT_SUBREGION);
    try testing.expectEqual(@as(c_uint, 4), c.SHMIF_RHINT_IGNORE_ALPHA);
    try testing.expectEqual(@as(c_uint, 8), c.SHMIF_RHINT_CSPACE_SRGB);
    try testing.expectEqual(@as(c_uint, 16), c.SHMIF_RHINT_AUTH_TOK);
    try testing.expectEqual(@as(c_uint, 32), c.SHMIF_RHINT_VSIGNAL_EV);
    try testing.expectEqual(@as(c_uint, 64), c.SHMIF_RHINT_EMPTY);
    try testing.expectEqual(@as(c_uint, 128), c.SHMIF_RHINT_TPACK);
}

test "SHMIF_RHINT non-zero flags are powers of 2 (bitmask)" {
    const flags = [_]c_uint{
        c.SHMIF_RHINT_ORIGO_LL,
        c.SHMIF_RHINT_SUBREGION,
        c.SHMIF_RHINT_IGNORE_ALPHA,
        c.SHMIF_RHINT_CSPACE_SRGB,
        c.SHMIF_RHINT_AUTH_TOK,
        c.SHMIF_RHINT_VSIGNAL_EV,
        c.SHMIF_RHINT_EMPTY,
        c.SHMIF_RHINT_TPACK,
    };
    for (flags) |f| {
        try testing.expect(f > 0);
        try testing.expectEqual(@as(c_uint, 0), f & (f - 1)); // Power of 2 check
    }
}

// 4f. Miscellaneous constants

test "ASHMIF_MSTATE_SZ is 32" {
    try testing.expectEqual(@as(c_int, 32), c.ASHMIF_MSTATE_SZ);
}

test "SHMIF_CMRAMP_PLIM is 4" {
    try testing.expectEqual(@as(c_int, 4), c.SHMIF_CMRAMP_PLIM);
}
