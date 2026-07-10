/// shmif ABI constant validation tests
///
/// Tier 9: Validates every ABI constant that real callers depend on. These are
/// compile-time accessible values that must match exact numeric expectations
/// for cross-language/cross-compiler interop.
const std = @import("std");
const testing = std.testing;

const c = @import("shmif_types");

// 9a. Page geometry constants

test "PP_SHMPAGE_MAXW = 8192" {
    try testing.expectEqual(@as(c_int, 8192), c.PP_SHMPAGE_MAXW);
}

test "PP_SHMPAGE_MAXH = 8192" {
    try testing.expectEqual(@as(c_int, 8192), c.PP_SHMPAGE_MAXH);
}

test "PP_SHMPAGE_STARTSZ = 2014088" {
    try testing.expectEqual(@as(c_int, 2014088), c.PP_SHMPAGE_STARTSZ);
}

test "PP_SHMPAGE_MAXSZ = 104857600 (100 MiB)" {
    try testing.expectEqual(@as(c_int, 104857600), c.PP_SHMPAGE_MAXSZ);
}

test "PP_SHMPAGE_ALIGN = 64" {
    try testing.expectEqual(@as(c_int, 64), c.PP_SHMPAGE_ALIGN);
}

// 9b. Signal mask constants

test "SHMIF_SIGVID = 1" {
    try testing.expectEqual(@as(c_uint, 1), c.SHMIF_SIGVID);
}

test "SHMIF_SIGAUD = 2" {
    try testing.expectEqual(@as(c_uint, 2), c.SHMIF_SIGAUD);
}

test "SHMIF_SIGBLK_FORCE = 0" {
    try testing.expectEqual(@as(c_uint, 0), c.SHMIF_SIGBLK_FORCE);
}

test "SHMIF_SIGBLK_NONE = 4" {
    try testing.expectEqual(@as(c_uint, 4), c.SHMIF_SIGBLK_NONE);
}

test "SIGVID | SIGAUD | SIGBLK_NONE = 7 (common combo)" {
    const combo = c.SHMIF_SIGVID | c.SHMIF_SIGAUD | c.SHMIF_SIGBLK_NONE;
    try testing.expectEqual(@as(c_uint, 7), combo);
}

test "SHMIF_SIGVID_AUTO_DIRTY = 8" {
    try testing.expectEqual(@as(c_uint, 8), c.SHMIF_SIGVID_AUTO_DIRTY);
}

// 9c. Audio constants

test "ARCAN_SHMIF_SAMPLERATE = 48000, ACHANNELS = 2" {
    try testing.expectEqual(@as(c_int, 48000), c.ARCAN_SHMIF_SAMPLERATE);
    try testing.expectEqual(@as(c_int, 2), c.ARCAN_SHMIF_ACHANNELS);
}

// 9d. Connection flags

test "connection flags are distinct bits" {
    try testing.expectEqual(@as(c_uint, 0), c.SHMIF_NOFLAGS);
    try testing.expectEqual(@as(c_uint, 4), c.SHMIF_ACQUIRE_FATALFAIL);
    try testing.expectEqual(@as(c_uint, 16), c.SHMIF_CONNECT_LOOP);

    // Verify they can be OR'd without collision
    const combo = c.SHMIF_ACQUIRE_FATALFAIL | c.SHMIF_CONNECT_LOOP;
    try testing.expectEqual(@as(c_uint, 20), combo);
}

// 9e. Meta type constants

test "meta types are distinct bits" {
    try testing.expectEqual(@as(c_uint, 0), c.SHMIF_META_NONE);
    try testing.expectEqual(@as(c_uint, 2), c.SHMIF_META_CM);
    try testing.expectEqual(@as(c_uint, 4), c.SHMIF_META_HDR);
    try testing.expectEqual(@as(c_uint, 16), c.SHMIF_META_VR);
    try testing.expectEqual(@as(c_uint, 32), c.SHMIF_META_VENC);

    // Non-zero values are distinct bits
    const all = c.SHMIF_META_CM | c.SHMIF_META_HDR | c.SHMIF_META_VR | c.SHMIF_META_VENC;
    try testing.expectEqual(@as(c_uint, 2 | 4 | 16 | 32), all);
}

// 9f. Keyboard modifier flags

test "ARKMOD values accessible and correct" {
    try testing.expectEqual(@as(c_uint, 0x0000), c.ARKMOD_NONE);
    try testing.expectEqual(@as(c_uint, 0x0001), c.ARKMOD_LSHIFT);
    try testing.expectEqual(@as(c_uint, 0x0002), c.ARKMOD_RSHIFT);
    try testing.expectEqual(@as(c_uint, 0x0040), c.ARKMOD_LCTRL);
    try testing.expectEqual(@as(c_uint, 0x0080), c.ARKMOD_RCTRL);
    try testing.expectEqual(@as(c_uint, 0x0100), c.ARKMOD_LALT);
    try testing.expectEqual(@as(c_uint, 0x0200), c.ARKMOD_RALT);
    try testing.expectEqual(@as(c_uint, 0x0400), c.ARKMOD_LMETA);
    try testing.expectEqual(@as(c_uint, 0x0800), c.ARKMOD_RMETA);
    try testing.expectEqual(@as(c_uint, 0x1000), c.ARKMOD_NUM);
    try testing.expectEqual(@as(c_uint, 0x2000), c.ARKMOD_CAPS);
    try testing.expectEqual(@as(c_uint, 0x4000), c.ARKMOD_MODE);
    try testing.expectEqual(@as(c_uint, 0x8000), c.ARKMOD_REPEAT);
}

test "ARKMOD non-NONE values are powers of 2 (bitmask)" {
    const mods = [_]c_uint{
        c.ARKMOD_LSHIFT, c.ARKMOD_RSHIFT, c.ARKMOD_LCTRL, c.ARKMOD_RCTRL,
        c.ARKMOD_LALT,   c.ARKMOD_RALT,   c.ARKMOD_LMETA,  c.ARKMOD_RMETA,
        c.ARKMOD_NUM,    c.ARKMOD_CAPS,    c.ARKMOD_MODE,   c.ARKMOD_REPEAT,
    };
    for (mods) |m| {
        try testing.expect(m != 0);
        // Power of 2: m & (m - 1) == 0
        try testing.expectEqual(@as(c_uint, 0), m & (m - 1));
    }
}

// 9g. Mouse button indices

test "mouse button indices" {
    try testing.expectEqual(@as(c_uint, 1), c.MBTN_LEFT_IND);
    try testing.expectEqual(@as(c_uint, 2), c.MBTN_RIGHT_IND);
    try testing.expectEqual(@as(c_uint, 3), c.MBTN_MIDDLE_IND);
    try testing.expectEqual(@as(c_uint, 4), c.MBTN_WHEEL_UP_IND);
    try testing.expectEqual(@as(c_uint, 5), c.MBTN_WHEEL_DOWN_IND);
}

// 9h. IO sub-enum completeness

test "EVENT_IO sub-kinds" {
    try testing.expectEqual(@as(c_uint, 0), c.EVENT_IO_BUTTON);
    try testing.expectEqual(@as(c_uint, 1), c.EVENT_IO_AXIS_MOVE);
    // Verify the remaining are accessible and distinct
    const touch: c_uint = c.EVENT_IO_TOUCH;
    const status: c_uint = c.EVENT_IO_STATUS;
    const eyes: c_uint = c.EVENT_IO_EYES;
    try testing.expect(touch != status);
    try testing.expect(status != eyes);
}

test "EVENT_IDEVKIND values" {
    try testing.expectEqual(@as(c_uint, 1), c.EVENT_IDEVKIND_KEYBOARD);
    try testing.expectEqual(@as(c_uint, 2), c.EVENT_IDEVKIND_MOUSE);
    try testing.expectEqual(@as(c_uint, 4), c.EVENT_IDEVKIND_GAMEDEV);
    try testing.expectEqual(@as(c_uint, 8), c.EVENT_IDEVKIND_TOUCHDISP);
    try testing.expectEqual(@as(c_uint, 16), c.EVENT_IDEVKIND_LEDCTRL);
    try testing.expectEqual(@as(c_uint, 32), c.EVENT_IDEVKIND_EYETRACKER);
}

test "EVENT_IDATATYPE values" {
    try testing.expectEqual(@as(c_uint, 1), c.EVENT_IDATATYPE_ANALOG);
    try testing.expectEqual(@as(c_uint, 2), c.EVENT_IDATATYPE_DIGITAL);
    try testing.expectEqual(@as(c_uint, 4), c.EVENT_IDATATYPE_TRANSLATED);
    try testing.expectEqual(@as(c_uint, 8), c.EVENT_IDATATYPE_TOUCH);
    try testing.expectEqual(@as(c_uint, 16), c.EVENT_IDATATYPE_EYES);
}

// 9i. Mouse state flag completeness

test "ARCAN_MOUSESTATE flag values" {
    try testing.expectEqual(@as(c_int, 0), c.ARCAN_MOUSESTATE_ABSOLUTE);
    try testing.expectEqual(@as(c_int, 1), c.ARCAN_MOUSESTATE_RELATIVE);
    try testing.expectEqual(@as(c_int, 2), c.ARCAN_MOUSESTATE_NOCLAMP);
}

// 9j. HDR EOTF enum

test "SHMIF_EOTF enum values" {
    try testing.expectEqual(@as(c_uint, 0), c.SHMIF_EOTF_SDR);
    try testing.expectEqual(@as(c_uint, 1), c.SHMIF_EOTF_HDR);
    try testing.expectEqual(@as(c_uint, 2), c.SHMIF_EOTF_ST2084);
    try testing.expectEqual(@as(c_uint, 3), c.SHMIF_EOTF_HLG);
}

// ═══════════════════════════════════════════════════════════════════
// Edge case tests — Round 4
// ═══════════════════════════════════════════════════════════════════

// 9k. Page geometry relationships

test "STARTSZ < MAXSZ" {
    const start: u64 = @intCast(c.PP_SHMPAGE_STARTSZ);
    const max: u64 = @intCast(c.PP_SHMPAGE_MAXSZ);
    try testing.expect(start < max);
}

test "MAXW * MAXH * 4 > STARTSZ (max pixel buffer exceeds start)" {
    const max_pixels: u64 = @as(u64, @intCast(c.PP_SHMPAGE_MAXW)) *
        @as(u64, @intCast(c.PP_SHMPAGE_MAXH)) * 4;
    const start: u64 = @intCast(c.PP_SHMPAGE_STARTSZ);
    try testing.expect(max_pixels > start);
}

test "ALIGN is power of 2" {
    const align_val: c_uint = @intCast(c.PP_SHMPAGE_ALIGN);
    try testing.expect(align_val != 0);
    try testing.expectEqual(@as(c_uint, 0), align_val & (align_val - 1));
}

test "MAXSZ is aligned to PP_SHMPAGE_ALIGN" {
    const align_val: u64 = @intCast(c.PP_SHMPAGE_ALIGN);
    const max: u64 = @intCast(c.PP_SHMPAGE_MAXSZ);
    try testing.expectEqual(@as(u64, 0), max % align_val);
}

test "PP_QUEUE_SZ = 127" {
    try testing.expectEqual(@as(c_int, 127), c.PP_QUEUE_SZ);
}

// 9l. Render hint flags (SHMIF_RHINT)

test "SHMIF_RHINT flag values" {
    try testing.expectEqual(@as(c_int, 0), c.SHMIF_RHINT_ORIGO_UL);
    try testing.expectEqual(@as(c_int, 1), c.SHMIF_RHINT_ORIGO_LL);
    try testing.expectEqual(@as(c_int, 2), c.SHMIF_RHINT_SUBREGION);
    try testing.expectEqual(@as(c_int, 4), c.SHMIF_RHINT_IGNORE_ALPHA);
    try testing.expectEqual(@as(c_int, 8), c.SHMIF_RHINT_CSPACE_SRGB);
    try testing.expectEqual(@as(c_int, 16), c.SHMIF_RHINT_AUTH_TOK);
    try testing.expectEqual(@as(c_int, 32), c.SHMIF_RHINT_VSIGNAL_EV);
    try testing.expectEqual(@as(c_int, 64), c.SHMIF_RHINT_EMPTY);
    try testing.expectEqual(@as(c_int, 128), c.SHMIF_RHINT_TPACK);
}

test "SHMIF_RHINT non-zero values are distinct bits" {
    const hints = [_]c_int{
        c.SHMIF_RHINT_ORIGO_LL, c.SHMIF_RHINT_SUBREGION,
        c.SHMIF_RHINT_IGNORE_ALPHA, c.SHMIF_RHINT_CSPACE_SRGB,
        c.SHMIF_RHINT_AUTH_TOK, c.SHMIF_RHINT_VSIGNAL_EV,
        c.SHMIF_RHINT_EMPTY, c.SHMIF_RHINT_TPACK,
    };
    // All are powers of 2
    for (hints) |h| {
        try testing.expect(h != 0);
        const uh: c_uint = @bitCast(h);
        try testing.expectEqual(@as(c_uint, 0), uh & (uh - 1));
    }
    // All combined fit in a byte
    var all: c_int = 0;
    for (hints) |h| all |= h;
    try testing.expectEqual(@as(c_int, 255), all);
}

test "SHMIF_RHINT common combos" {
    // TPACK + VSIGNAL_EV (TUI with event signaling)
    const combo1 = c.SHMIF_RHINT_TPACK | c.SHMIF_RHINT_VSIGNAL_EV;
    try testing.expectEqual(@as(c_int, 160), combo1);

    // SUBREGION + IGNORE_ALPHA (partial update, no alpha)
    const combo2 = c.SHMIF_RHINT_SUBREGION | c.SHMIF_RHINT_IGNORE_ALPHA;
    try testing.expectEqual(@as(c_int, 6), combo2);
}

// 9m. Segment ID completeness

test "SEGID core values" {
    try testing.expectEqual(@as(c_int, 0), @as(c_int, c.SEGID_UNKNOWN));
    try testing.expectEqual(@as(c_int, 1), @as(c_int, c.SEGID_LWA));
    try testing.expectEqual(@as(c_int, 2), @as(c_int, c.SEGID_NETWORK_SERVER));
    try testing.expectEqual(@as(c_int, 3), @as(c_int, c.SEGID_NETWORK_CLIENT));
    try testing.expectEqual(@as(c_int, 4), @as(c_int, c.SEGID_MEDIA));
    try testing.expectEqual(@as(c_int, 5), @as(c_int, c.SEGID_TERMINAL));
    try testing.expectEqual(@as(c_int, 6), @as(c_int, c.SEGID_REMOTING));
    try testing.expectEqual(@as(c_int, 7), @as(c_int, c.SEGID_ENCODER));
}

test "SEGID extended values" {
    try testing.expectEqual(@as(c_int, 9), @as(c_int, c.SEGID_GAME));
    try testing.expectEqual(@as(c_int, 13), @as(c_int, c.SEGID_HMD_SBS));
    try testing.expectEqual(@as(c_int, 14), @as(c_int, c.SEGID_HMD_L));
    try testing.expectEqual(@as(c_int, 15), @as(c_int, c.SEGID_HMD_R));
    try testing.expectEqual(@as(c_int, 16), @as(c_int, c.SEGID_POPUP));
    try testing.expectEqual(@as(c_int, 17), @as(c_int, c.SEGID_ICON));
    try testing.expectEqual(@as(c_int, 19), @as(c_int, c.SEGID_CURSOR));
    try testing.expectEqual(@as(c_int, 20), @as(c_int, c.SEGID_ACCESSIBILITY));
}

test "SEGID clipboard and UI values" {
    try testing.expectEqual(@as(c_int, 21), @as(c_int, c.SEGID_CLIPBOARD));
    try testing.expectEqual(@as(c_int, 22), @as(c_int, c.SEGID_CLIPBOARD_PASTE));
    try testing.expectEqual(@as(c_int, 23), @as(c_int, c.SEGID_WIDGET));
    try testing.expectEqual(@as(c_int, 24), @as(c_int, c.SEGID_TUI));
}

test "SEGID bridge and special values" {
    try testing.expectEqual(@as(c_int, 26), @as(c_int, c.SEGID_BRIDGE_X11));
    try testing.expectEqual(@as(c_int, 27), @as(c_int, c.SEGID_BRIDGE_WAYLAND));
    try testing.expectEqual(@as(c_int, 28), @as(c_int, c.SEGID_HANDOVER));
}

test "SEGID boundary values (MONITOR=254, DEBUG=255)" {
    try testing.expectEqual(@as(c_int, 254), @as(c_int, c.SEGID_MONITOR));
    try testing.expectEqual(@as(c_int, 255), @as(c_int, c.SEGID_DEBUG));
}

test "all SEGID values are unique" {
    const segids = [_]c_int{
        c.SEGID_UNKNOWN,         c.SEGID_LWA,         c.SEGID_NETWORK_SERVER,
        c.SEGID_NETWORK_CLIENT,  c.SEGID_MEDIA,        c.SEGID_TERMINAL,
        c.SEGID_REMOTING,        c.SEGID_ENCODER,      c.SEGID_GAME,
        c.SEGID_HMD_SBS,        c.SEGID_HMD_L,        c.SEGID_HMD_R,
        c.SEGID_POPUP,          c.SEGID_ICON,          c.SEGID_CURSOR,
        c.SEGID_ACCESSIBILITY,   c.SEGID_CLIPBOARD,    c.SEGID_CLIPBOARD_PASTE,
        c.SEGID_WIDGET,         c.SEGID_TUI,           c.SEGID_BRIDGE_X11,
        c.SEGID_BRIDGE_WAYLAND, c.SEGID_HANDOVER,      c.SEGID_MONITOR,
        c.SEGID_DEBUG,
    };
    for (segids, 0..) |a, i| {
        for (segids[i + 1 ..]) |b| {
            try testing.expect(a != b);
        }
    }
}

// 9n. Buffer limits

test "ARCAN_SHMIF_ABUFC_LIM = 12" {
    try testing.expectEqual(@as(c_int, 12), c.ARCAN_SHMIF_ABUFC_LIM);
}

test "ARCAN_SHMIF_VBUFC_LIM = 3" {
    try testing.expectEqual(@as(c_int, 3), c.ARCAN_SHMIF_VBUFC_LIM);
}

test "ARCAN_SHMPAGE_VCHANNELS = 4" {
    try testing.expectEqual(@as(c_int, 4), c.ARCAN_SHMPAGE_VCHANNELS);
}

test "ABUFC_LIM > VBUFC_LIM (audio needs more buffers)" {
    try testing.expect(c.ARCAN_SHMIF_ABUFC_LIM > c.ARCAN_SHMIF_VBUFC_LIM);
}

// 9o. TARGET_COMMAND enum completeness

test "TARGET_COMMAND sequential values 1-30" {
    try testing.expectEqual(@as(c_int, 1), @as(c_int, c.TARGET_COMMAND_EXIT));
    try testing.expectEqual(@as(c_int, 2), @as(c_int, c.TARGET_COMMAND_FRAMESKIP));
    try testing.expectEqual(@as(c_int, 3), @as(c_int, c.TARGET_COMMAND_STEPFRAME));
    try testing.expectEqual(@as(c_int, 4), @as(c_int, c.TARGET_COMMAND_COREOPT));
    try testing.expectEqual(@as(c_int, 5), @as(c_int, c.TARGET_COMMAND_STORE));
    try testing.expectEqual(@as(c_int, 6), @as(c_int, c.TARGET_COMMAND_RESTORE));
    try testing.expectEqual(@as(c_int, 7), @as(c_int, c.TARGET_COMMAND_BCHUNK_IN));
    try testing.expectEqual(@as(c_int, 8), @as(c_int, c.TARGET_COMMAND_BCHUNK_OUT));
    try testing.expectEqual(@as(c_int, 9), @as(c_int, c.TARGET_COMMAND_RESET));
    try testing.expectEqual(@as(c_int, 10), @as(c_int, c.TARGET_COMMAND_PAUSE));
    try testing.expectEqual(@as(c_int, 11), @as(c_int, c.TARGET_COMMAND_UNPAUSE));
    try testing.expectEqual(@as(c_int, 12), @as(c_int, c.TARGET_COMMAND_SEEKTIME));
    try testing.expectEqual(@as(c_int, 13), @as(c_int, c.TARGET_COMMAND_SEEKCONTENT));
    try testing.expectEqual(@as(c_int, 14), @as(c_int, c.TARGET_COMMAND_DISPLAYHINT));
    try testing.expectEqual(@as(c_int, 15), @as(c_int, c.TARGET_COMMAND_SETIODEV));
    try testing.expectEqual(@as(c_int, 16), @as(c_int, c.TARGET_COMMAND_STREAMSET));
    try testing.expectEqual(@as(c_int, 17), @as(c_int, c.TARGET_COMMAND_ATTENUATE));
    try testing.expectEqual(@as(c_int, 18), @as(c_int, c.TARGET_COMMAND_AUDDELAY));
    try testing.expectEqual(@as(c_int, 19), @as(c_int, c.TARGET_COMMAND_NEWSEGMENT));
    try testing.expectEqual(@as(c_int, 20), @as(c_int, c.TARGET_COMMAND_REQFAIL));
    try testing.expectEqual(@as(c_int, 21), @as(c_int, c.TARGET_COMMAND_BUFFER_FAIL));
    try testing.expectEqual(@as(c_int, 22), @as(c_int, c.TARGET_COMMAND_DEVICE_NODE));
    try testing.expectEqual(@as(c_int, 23), @as(c_int, c.TARGET_COMMAND_GRAPHMODE));
    try testing.expectEqual(@as(c_int, 24), @as(c_int, c.TARGET_COMMAND_MESSAGE));
    try testing.expectEqual(@as(c_int, 25), @as(c_int, c.TARGET_COMMAND_FONTHINT));
    try testing.expectEqual(@as(c_int, 26), @as(c_int, c.TARGET_COMMAND_GEOHINT));
    try testing.expectEqual(@as(c_int, 27), @as(c_int, c.TARGET_COMMAND_OUTPUTHINT));
    try testing.expectEqual(@as(c_int, 28), @as(c_int, c.TARGET_COMMAND_ACTIVATE));
    try testing.expectEqual(@as(c_int, 29), @as(c_int, c.TARGET_COMMAND_DEVICESTATE));
    try testing.expectEqual(@as(c_int, 30), @as(c_int, c.TARGET_COMMAND_ANCHORHINT));
}

test "TARGET_COMMAND all values are unique" {
    const cmds = [_]c_int{
        c.TARGET_COMMAND_EXIT,         c.TARGET_COMMAND_FRAMESKIP,
        c.TARGET_COMMAND_STEPFRAME,    c.TARGET_COMMAND_COREOPT,
        c.TARGET_COMMAND_STORE,        c.TARGET_COMMAND_RESTORE,
        c.TARGET_COMMAND_BCHUNK_IN,    c.TARGET_COMMAND_BCHUNK_OUT,
        c.TARGET_COMMAND_RESET,        c.TARGET_COMMAND_PAUSE,
        c.TARGET_COMMAND_UNPAUSE,      c.TARGET_COMMAND_SEEKTIME,
        c.TARGET_COMMAND_SEEKCONTENT,   c.TARGET_COMMAND_DISPLAYHINT,
        c.TARGET_COMMAND_SETIODEV,     c.TARGET_COMMAND_STREAMSET,
        c.TARGET_COMMAND_ATTENUATE,    c.TARGET_COMMAND_AUDDELAY,
        c.TARGET_COMMAND_NEWSEGMENT,   c.TARGET_COMMAND_REQFAIL,
        c.TARGET_COMMAND_BUFFER_FAIL,  c.TARGET_COMMAND_DEVICE_NODE,
        c.TARGET_COMMAND_GRAPHMODE,    c.TARGET_COMMAND_MESSAGE,
        c.TARGET_COMMAND_FONTHINT,     c.TARGET_COMMAND_GEOHINT,
        c.TARGET_COMMAND_OUTPUTHINT,   c.TARGET_COMMAND_ACTIVATE,
        c.TARGET_COMMAND_DEVICESTATE,  c.TARGET_COMMAND_ANCHORHINT,
    };
    for (cmds, 0..) |a, i| {
        for (cmds[i + 1 ..]) |b| {
            try testing.expect(a != b);
        }
    }
}

// 9p. EVENT_EXTERNAL enum completeness

test "EVENT_EXTERNAL sequential values" {
    try testing.expectEqual(@as(c_int, 0), @as(c_int, c.EVENT_EXTERNAL_MESSAGE));
    try testing.expectEqual(@as(c_int, 1), @as(c_int, c.EVENT_EXTERNAL_COREOPT));
    try testing.expectEqual(@as(c_int, 2), @as(c_int, c.EVENT_EXTERNAL_IDENT));
    try testing.expectEqual(@as(c_int, 3), @as(c_int, c.EVENT_EXTERNAL_FAILURE));
    try testing.expectEqual(@as(c_int, 4), @as(c_int, c.EVENT_EXTERNAL_BUFFERSTREAM));
    try testing.expectEqual(@as(c_int, 5), @as(c_int, c.EVENT_EXTERNAL_FRAMESTATUS));
    try testing.expectEqual(@as(c_int, 6), @as(c_int, c.EVENT_EXTERNAL_STREAMINFO));
    try testing.expectEqual(@as(c_int, 7), @as(c_int, c.EVENT_EXTERNAL_STREAMSTATUS));
    try testing.expectEqual(@as(c_int, 8), @as(c_int, c.EVENT_EXTERNAL_STATESIZE));
    try testing.expectEqual(@as(c_int, 9), @as(c_int, c.EVENT_EXTERNAL_FLUSHAUD));
    try testing.expectEqual(@as(c_int, 10), @as(c_int, c.EVENT_EXTERNAL_SEGREQ));
    try testing.expectEqual(@as(c_int, 12), @as(c_int, c.EVENT_EXTERNAL_CURSORHINT));
    try testing.expectEqual(@as(c_int, 13), @as(c_int, c.EVENT_EXTERNAL_VIEWPORT));
    try testing.expectEqual(@as(c_int, 14), @as(c_int, c.EVENT_EXTERNAL_CONTENT));
    try testing.expectEqual(@as(c_int, 15), @as(c_int, c.EVENT_EXTERNAL_LABELHINT));
    try testing.expectEqual(@as(c_int, 16), @as(c_int, c.EVENT_EXTERNAL_REGISTER));
    try testing.expectEqual(@as(c_int, 17), @as(c_int, c.EVENT_EXTERNAL_ALERT));
    try testing.expectEqual(@as(c_int, 18), @as(c_int, c.EVENT_EXTERNAL_CLOCKREQ));
    try testing.expectEqual(@as(c_int, 19), @as(c_int, c.EVENT_EXTERNAL_BCHUNKSTATE));
    try testing.expectEqual(@as(c_int, 20), @as(c_int, c.EVENT_EXTERNAL_PRIVDROP));
    try testing.expectEqual(@as(c_int, 21), @as(c_int, c.EVENT_EXTERNAL_INPUTMASK));
    try testing.expectEqual(@as(c_int, 22), @as(c_int, c.EVENT_EXTERNAL_NETSTATE));
}

test "EVENT_EXTERNAL all values are unique" {
    const exts = [_]c_int{
        c.EVENT_EXTERNAL_MESSAGE,      c.EVENT_EXTERNAL_COREOPT,
        c.EVENT_EXTERNAL_IDENT,        c.EVENT_EXTERNAL_FAILURE,
        c.EVENT_EXTERNAL_BUFFERSTREAM, c.EVENT_EXTERNAL_FRAMESTATUS,
        c.EVENT_EXTERNAL_STREAMINFO,   c.EVENT_EXTERNAL_STREAMSTATUS,
        c.EVENT_EXTERNAL_STATESIZE,    c.EVENT_EXTERNAL_FLUSHAUD,
        c.EVENT_EXTERNAL_SEGREQ,       c.EVENT_EXTERNAL_CURSORHINT,
        c.EVENT_EXTERNAL_VIEWPORT,     c.EVENT_EXTERNAL_CONTENT,
        c.EVENT_EXTERNAL_LABELHINT,    c.EVENT_EXTERNAL_REGISTER,
        c.EVENT_EXTERNAL_ALERT,        c.EVENT_EXTERNAL_CLOCKREQ,
        c.EVENT_EXTERNAL_BCHUNKSTATE,  c.EVENT_EXTERNAL_PRIVDROP,
        c.EVENT_EXTERNAL_INPUTMASK,    c.EVENT_EXTERNAL_NETSTATE,
    };
    for (exts, 0..) |a, i| {
        for (exts[i + 1 ..]) |b| {
            try testing.expect(a != b);
        }
    }
}

// 9q. TARGET_SKIP modes

test "TARGET_SKIP mode values" {
    try testing.expectEqual(@as(c_int, 0), @as(c_int, c.TARGET_SKIP_AUTO));
    try testing.expectEqual(@as(c_int, -1), @as(c_int, c.TARGET_SKIP_NONE));
    try testing.expectEqual(@as(c_int, -2), @as(c_int, c.TARGET_SKIP_REVERSE));
    try testing.expectEqual(@as(c_int, -3), @as(c_int, c.TARGET_SKIP_ROLLBACK));
    try testing.expectEqual(@as(c_int, 1), @as(c_int, c.TARGET_SKIP_STEP));
    try testing.expectEqual(@as(c_int, 10), @as(c_int, c.TARGET_SKIP_FASTFWD));
}

test "TARGET_SKIP negative modes are distinct" {
    try testing.expect(@as(c_int, c.TARGET_SKIP_NONE) != @as(c_int, c.TARGET_SKIP_REVERSE));
    try testing.expect(@as(c_int, c.TARGET_SKIP_REVERSE) != @as(c_int, c.TARGET_SKIP_ROLLBACK));
    try testing.expect(@as(c_int, c.TARGET_SKIP_NONE) != @as(c_int, c.TARGET_SKIP_ROLLBACK));
}

// 9r. IO flags

test "ARCAN_IOFL flag values" {
    try testing.expectEqual(@as(c_int, 1), @as(c_int, c.ARCAN_IOFL_GESTURE));
    try testing.expectEqual(@as(c_int, 2), @as(c_int, c.ARCAN_IOFL_ENTER));
    try testing.expectEqual(@as(c_int, 4), @as(c_int, c.ARCAN_IOFL_LEAVE));
}

test "ARCAN_IOFL flags are distinct bits" {
    const flags = [_]c_int{
        c.ARCAN_IOFL_GESTURE, c.ARCAN_IOFL_ENTER, c.ARCAN_IOFL_LEAVE,
    };
    for (flags) |f| {
        try testing.expect(f != 0);
        const uf: c_uint = @bitCast(f);
        try testing.expectEqual(@as(c_uint, 0), uf & (uf - 1));
    }
}

// 9s. Signal mask bitwise properties

test "signal masks are distinct bits (SIGVID, SIGAUD, SIGBLK_NONE)" {
    // These three are commonly OR'd together
    const vid: c_uint = c.SHMIF_SIGVID;
    const aud: c_uint = c.SHMIF_SIGAUD;
    const blk: c_uint = c.SHMIF_SIGBLK_NONE;
    try testing.expectEqual(@as(c_uint, 0), vid & aud);
    try testing.expectEqual(@as(c_uint, 0), vid & blk);
    try testing.expectEqual(@as(c_uint, 0), aud & blk);
}

test "SIGVID_AUTO_DIRTY does not collide with SIGBLK_NONE" {
    try testing.expectEqual(@as(c_uint, 0), c.SHMIF_SIGVID_AUTO_DIRTY & c.SHMIF_SIGBLK_NONE);
}

test "all signal flags combined" {
    const all = c.SHMIF_SIGVID | c.SHMIF_SIGAUD | c.SHMIF_SIGBLK_NONE | c.SHMIF_SIGVID_AUTO_DIRTY;
    try testing.expectEqual(@as(c_uint, 1 | 2 | 4 | 8), all);
    try testing.expectEqual(@as(c_uint, 15), all);
}

// 9t. EVENT_IDEVKIND power-of-2 verification

test "EVENT_IDEVKIND values are powers of 2" {
    const kinds = [_]c_uint{
        c.EVENT_IDEVKIND_KEYBOARD, c.EVENT_IDEVKIND_MOUSE,
        c.EVENT_IDEVKIND_GAMEDEV,  c.EVENT_IDEVKIND_TOUCHDISP,
        c.EVENT_IDEVKIND_LEDCTRL,  c.EVENT_IDEVKIND_EYETRACKER,
    };
    for (kinds) |k| {
        try testing.expect(k != 0);
        try testing.expectEqual(@as(c_uint, 0), k & (k - 1));
    }
}

test "EVENT_IDEVKIND all combined has 6 bits set" {
    const all = c.EVENT_IDEVKIND_KEYBOARD | c.EVENT_IDEVKIND_MOUSE |
        c.EVENT_IDEVKIND_GAMEDEV | c.EVENT_IDEVKIND_TOUCHDISP |
        c.EVENT_IDEVKIND_LEDCTRL | c.EVENT_IDEVKIND_EYETRACKER;
    try testing.expectEqual(@as(c_uint, 63), all); // 1|2|4|8|16|32
}

test "EVENT_IDATATYPE values are powers of 2" {
    const types = [_]c_uint{
        c.EVENT_IDATATYPE_ANALOG, c.EVENT_IDATATYPE_DIGITAL,
        c.EVENT_IDATATYPE_TRANSLATED, c.EVENT_IDATATYPE_TOUCH,
        c.EVENT_IDATATYPE_EYES,
    };
    for (types) |t| {
        try testing.expect(t != 0);
        try testing.expectEqual(@as(c_uint, 0), t & (t - 1));
    }
}

// 9u. Mouse state combined modes

test "ARCAN_MOUSESTATE NOCLAMP can combine with RELATIVE" {
    const combo: c_int = c.ARCAN_MOUSESTATE_RELATIVE | c.ARCAN_MOUSESTATE_NOCLAMP;
    try testing.expectEqual(@as(c_int, 3), combo);
}

test "ARCAN_MOUSESTATE ABSOLUTE is zero (default)" {
    try testing.expectEqual(@as(c_int, 0), c.ARCAN_MOUSESTATE_ABSOLUTE);
    // OR'ing with ABSOLUTE changes nothing
    try testing.expectEqual(c.ARCAN_MOUSESTATE_RELATIVE,
        c.ARCAN_MOUSESTATE_RELATIVE | c.ARCAN_MOUSESTATE_ABSOLUTE);
}

// 9v. Mouse button indices are sequential

test "mouse button indices are sequential 1..5" {
    try testing.expectEqual(c.MBTN_LEFT_IND + 1, c.MBTN_RIGHT_IND);
    try testing.expectEqual(c.MBTN_RIGHT_IND + 1, c.MBTN_MIDDLE_IND);
    try testing.expectEqual(c.MBTN_MIDDLE_IND + 1, c.MBTN_WHEEL_UP_IND);
    try testing.expectEqual(c.MBTN_WHEEL_UP_IND + 1, c.MBTN_WHEEL_DOWN_IND);
}

// 9w. ARKMOD combined masks

test "ARKMOD shift combo" {
    const both_shift = c.ARKMOD_LSHIFT | c.ARKMOD_RSHIFT;
    try testing.expectEqual(@as(c_uint, 0x0003), both_shift);
}

test "ARKMOD ctrl combo" {
    const both_ctrl = c.ARKMOD_LCTRL | c.ARKMOD_RCTRL;
    try testing.expectEqual(@as(c_uint, 0x00C0), both_ctrl);
}

test "ARKMOD alt combo" {
    const both_alt = c.ARKMOD_LALT | c.ARKMOD_RALT;
    try testing.expectEqual(@as(c_uint, 0x0300), both_alt);
}

test "ARKMOD meta combo" {
    const both_meta = c.ARKMOD_LMETA | c.ARKMOD_RMETA;
    try testing.expectEqual(@as(c_uint, 0x0C00), both_meta);
}

test "ARKMOD all modifiers combined" {
    const all = c.ARKMOD_LSHIFT | c.ARKMOD_RSHIFT | c.ARKMOD_LCTRL | c.ARKMOD_RCTRL |
        c.ARKMOD_LALT | c.ARKMOD_RALT | c.ARKMOD_LMETA | c.ARKMOD_RMETA |
        c.ARKMOD_NUM | c.ARKMOD_CAPS | c.ARKMOD_MODE | c.ARKMOD_REPEAT;
    try testing.expectEqual(@as(c_uint, 0xFFC3), all);
}

test "ARKMOD all modifiers fit in u16" {
    const all = c.ARKMOD_LSHIFT | c.ARKMOD_RSHIFT | c.ARKMOD_LCTRL | c.ARKMOD_RCTRL |
        c.ARKMOD_LALT | c.ARKMOD_RALT | c.ARKMOD_LMETA | c.ARKMOD_RMETA |
        c.ARKMOD_NUM | c.ARKMOD_CAPS | c.ARKMOD_MODE | c.ARKMOD_REPEAT;
    try testing.expect(all <= 0xFFFF);
}

// 9x. Event category constants

test "event categories are accessible" {
    const io: c_uint = c.EVENT_IO;
    const tgt: c_uint = c.EVENT_TARGET;
    const ext: c_uint = c.EVENT_EXTERNAL;
    // All distinct
    try testing.expect(io != tgt);
    try testing.expect(tgt != ext);
    try testing.expect(io != ext);
    // All nonzero
    try testing.expect(io != 0);
    try testing.expect(tgt != 0);
    try testing.expect(ext != 0);
}

// 9y. Meta type edge cases

test "meta types: all non-zero are distinct bits" {
    const metas = [_]c_uint{
        c.SHMIF_META_CM, c.SHMIF_META_HDR,
        c.SHMIF_META_VR, c.SHMIF_META_VENC,
    };
    for (metas) |m| {
        try testing.expect(m != 0);
        try testing.expectEqual(@as(c_uint, 0), m & (m - 1));
    }
}

test "meta types: NONE OR'd with anything is identity" {
    try testing.expectEqual(c.SHMIF_META_CM, c.SHMIF_META_NONE | c.SHMIF_META_CM);
    try testing.expectEqual(c.SHMIF_META_VR, c.SHMIF_META_NONE | c.SHMIF_META_VR);
}

// 9z. Connection flag edge cases

test "SHMIF_NOFLAGS is identity for OR" {
    try testing.expectEqual(c.SHMIF_ACQUIRE_FATALFAIL,
        c.SHMIF_NOFLAGS | c.SHMIF_ACQUIRE_FATALFAIL);
    try testing.expectEqual(c.SHMIF_CONNECT_LOOP,
        c.SHMIF_NOFLAGS | c.SHMIF_CONNECT_LOOP);
}

test "ACQUIRE_FATALFAIL and CONNECT_LOOP are distinct bits" {
    try testing.expectEqual(@as(c_uint, 0),
        c.SHMIF_ACQUIRE_FATALFAIL & c.SHMIF_CONNECT_LOOP);
}

// 9aa. HDR EOTF edge cases

test "SHMIF_EOTF values are sequential 0..3" {
    try testing.expectEqual(c.SHMIF_EOTF_SDR + 1, c.SHMIF_EOTF_HDR);
    try testing.expectEqual(c.SHMIF_EOTF_HDR + 1, c.SHMIF_EOTF_ST2084);
    try testing.expectEqual(c.SHMIF_EOTF_ST2084 + 1, c.SHMIF_EOTF_HLG);
}

test "SHMIF_EOTF all values fit in 2 bits" {
    try testing.expect(c.SHMIF_EOTF_HLG < 4);
}

// 9ab. IO sub-enum edge cases

test "EVENT_IO_BUTTON is zero (default)" {
    try testing.expectEqual(@as(c_uint, 0), c.EVENT_IO_BUTTON);
}

test "all EVENT_IO sub-kinds are unique" {
    const kinds = [_]c_uint{
        c.EVENT_IO_BUTTON, c.EVENT_IO_AXIS_MOVE,
        c.EVENT_IO_TOUCH, c.EVENT_IO_STATUS, c.EVENT_IO_EYES,
    };
    for (kinds, 0..) |a, i| {
        for (kinds[i + 1 ..]) |b| {
            try testing.expect(a != b);
        }
    }
}

// 9ac. Audio constant relationships

test "SAMPLERATE is standard 48kHz" {
    // 48000 is divisible by common audio frame sizes
    try testing.expectEqual(@as(c_int, 0), @rem(c.ARCAN_SHMIF_SAMPLERATE, 100));
    try testing.expectEqual(@as(c_int, 0), @rem(c.ARCAN_SHMIF_SAMPLERATE, 1000));
}

test "ACHANNELS is even (stereo)" {
    try testing.expectEqual(@as(c_int, 0), @rem(c.ARCAN_SHMIF_ACHANNELS, 2));
}

// 9ad. Queue size properties

test "PP_QUEUE_SZ is positive and reasonable" {
    try testing.expect(c.PP_QUEUE_SZ > 0);
    try testing.expect(c.PP_QUEUE_SZ <= 256);
}

test "PP_QUEUE_SZ is power-of-2 minus 1 (mask-friendly)" {
    // 127 = 128 - 1 = 0x7F, useful for & masking
    const qsz: c_uint = @intCast(c.PP_QUEUE_SZ);
    try testing.expectEqual(@as(c_uint, 0), (qsz + 1) & qsz);
}

// ═══════════════════════════════════════════════════════════════════
// Tier 10: Zig reimplementation safety tests
// ═══════════════════════════════════════════════════════════════════

// 10a. String buffer sizes via Zig @sizeOf

test "tgt.message is exactly 78 bytes in Zig" {
    const tgt_type = c.arcan_tgtevent;
    const tgt: tgt_type = std.mem.zeroes(tgt_type);
    try testing.expectEqual(@as(usize, 78), @as(usize, tgt.unnamed_0.message.len));
}

test "ext.message.data is exactly 78 bytes in Zig" {
    const ext_type = c.arcan_extevent;
    const ext: ext_type = std.mem.zeroes(ext_type);
    try testing.expectEqual(@as(usize, 78), @as(usize, ext.unnamed_0.message.data.len));
}

test "io.label is exactly 16 bytes in Zig" {
    const io_type = c.arcan_ioevent;
    const io: io_type = std.mem.zeroes(io_type);
    try testing.expectEqual(@as(usize, 16), @as(usize, io.label.len));
}

test "ext.labelhint.label is exactly 16 bytes in Zig" {
    const ext_type = c.arcan_extevent;
    const ext: ext_type = std.mem.zeroes(ext_type);
    try testing.expectEqual(@as(usize, 16), @as(usize, ext.unnamed_0.labelhint.label.len));
}

test "ext.labelhint.descr is exactly 53 bytes in Zig" {
    const ext_type = c.arcan_extevent;
    const ext: ext_type = std.mem.zeroes(ext_type);
    try testing.expectEqual(@as(usize, 53), @as(usize, ext.unnamed_0.labelhint.descr.len));
}

test "ext.labelhint.vsym is exactly 5 bytes in Zig" {
    const ext_type = c.arcan_extevent;
    const ext: ext_type = std.mem.zeroes(ext_type);
    try testing.expectEqual(@as(usize, 5), @as(usize, ext.unnamed_0.labelhint.vsym.len));
}

test "ext.registr.title is exactly 64 bytes in Zig" {
    const ext_type = c.arcan_extevent;
    const ext: ext_type = std.mem.zeroes(ext_type);
    try testing.expectEqual(@as(usize, 64), @as(usize, ext.unnamed_0.registr.title.len));
}

test "ext.registr.guid is exactly 2 elements in Zig" {
    const ext_type = c.arcan_extevent;
    const ext: ext_type = std.mem.zeroes(ext_type);
    try testing.expectEqual(@as(usize, 2), @as(usize, ext.unnamed_0.registr.guid.len));
}

test "ext.bchunk.extensions is exactly 68 bytes in Zig" {
    const ext_type = c.arcan_extevent;
    const ext: ext_type = std.mem.zeroes(ext_type);
    try testing.expectEqual(@as(usize, 68), @as(usize, ext.unnamed_0.bchunk.extensions.len));
}

test "ext.coreopt.data is exactly 77 bytes in Zig" {
    const ext_type = c.arcan_extevent;
    const ext: ext_type = std.mem.zeroes(ext_type);
    try testing.expectEqual(@as(usize, 77), @as(usize, ext.unnamed_0.coreopt.data.len));
}

test "ext.streaminf.langid is exactly 4 bytes in Zig" {
    const ext_type = c.arcan_extevent;
    const ext: ext_type = std.mem.zeroes(ext_type);
    try testing.expectEqual(@as(usize, 4), @as(usize, ext.unnamed_0.streaminf.langid.len));
}

test "ext.viewport.border is exactly 4 bytes in Zig" {
    const ext_type = c.arcan_extevent;
    const ext: ext_type = std.mem.zeroes(ext_type);
    try testing.expectEqual(@as(usize, 4), @as(usize, ext.unnamed_0.viewport.border.len));
}

test "tgt.ioevs is exactly 8 elements in Zig" {
    const tgt_type = c.arcan_tgtevent;
    const tgt: tgt_type = std.mem.zeroes(tgt_type);
    try testing.expectEqual(@as(usize, 8), @as(usize, tgt.ioevs.len));
}

test "io.input.analog.axisval is exactly 4 elements in Zig" {
    const io_type = c.arcan_ioevent;
    const io: io_type = std.mem.zeroes(io_type);
    try testing.expectEqual(@as(usize, 4), @as(usize, io.input.analog.axisval.len));
}

test "io.input.translated.utf8 is exactly 5 bytes in Zig" {
    const io_type = c.arcan_ioevent;
    const io: io_type = std.mem.zeroes(io_type);
    try testing.expectEqual(@as(usize, 5), @as(usize, io.input.translated.utf8.len));
}

test "io.input.eyes.head_pos is exactly 3 floats in Zig" {
    const io_type = c.arcan_ioevent;
    const io: io_type = std.mem.zeroes(io_type);
    try testing.expectEqual(@as(usize, 3), @as(usize, io.input.eyes.head_pos.len));
}

test "io.input.eyes.head_ang is exactly 3 floats in Zig" {
    const io_type = c.arcan_ioevent;
    const io: io_type = std.mem.zeroes(io_type);
    try testing.expectEqual(@as(usize, 3), @as(usize, io.input.eyes.head_ang.len));
}

// 10b. Struct sizes match C

test "arcan_event is 128 bytes in Zig" {
    try testing.expectEqual(@as(usize, 128), @sizeOf(c.arcan_event));
}

test "arcan_shmif_region is 8 bytes in Zig" {
    try testing.expectEqual(@as(usize, 8), @sizeOf(c.struct_arcan_shmif_region));
}

test "ioevs element union is exactly 4 bytes" {
    const tgt_type = c.arcan_tgtevent;
    const tgt: tgt_type = std.mem.zeroes(tgt_type);
    try testing.expectEqual(@as(usize, 4), @sizeOf(@TypeOf(tgt.ioevs[0])));
}

// 10c. Enum type backing sizes

test "TARGET_COMMAND enum values fit in i32" {
    const max_cmd: c_int = c.TARGET_COMMAND_ANCHORHINT; // 30
    try testing.expect(max_cmd <= std.math.maxInt(i32));
    try testing.expect(max_cmd > 0);
}

test "EVENT_EXTERNAL enum values fit in i32" {
    const max_ext: c_int = c.EVENT_EXTERNAL_NETSTATE; // 22
    try testing.expect(max_ext <= std.math.maxInt(i32));
    try testing.expect(max_ext >= 0);
}

test "SEGID values fit in u8 (0..255)" {
    const segids = [_]c_int{
        c.SEGID_UNKNOWN, c.SEGID_LWA, c.SEGID_NETWORK_SERVER,
        c.SEGID_NETWORK_CLIENT, c.SEGID_MEDIA, c.SEGID_TERMINAL,
        c.SEGID_REMOTING, c.SEGID_ENCODER, c.SEGID_GAME,
        c.SEGID_HMD_SBS, c.SEGID_HMD_L, c.SEGID_HMD_R,
        c.SEGID_POPUP, c.SEGID_ICON, c.SEGID_CURSOR,
        c.SEGID_ACCESSIBILITY, c.SEGID_CLIPBOARD, c.SEGID_CLIPBOARD_PASTE,
        c.SEGID_WIDGET, c.SEGID_TUI, c.SEGID_BRIDGE_X11,
        c.SEGID_BRIDGE_WAYLAND, c.SEGID_HANDOVER, c.SEGID_MONITOR,
        c.SEGID_DEBUG,
    };
    for (segids) |s| {
        try testing.expect(s >= 0);
        try testing.expect(s <= 255);
    }
}

test "SEGID_UNKNOWN is 0 (default/sentinel)" {
    try testing.expectEqual(@as(c_int, 0), @as(c_int, c.SEGID_UNKNOWN));
}

// 10d. TARGET_COMMAND starts at 1 (EXIT)

test "TARGET_COMMAND_EXIT is 1 (first valid command)" {
    try testing.expectEqual(@as(c_int, 1), @as(c_int, c.TARGET_COMMAND_EXIT));
}

test "EVENT_EXTERNAL_MESSAGE is 0 (first external event)" {
    try testing.expectEqual(@as(c_int, 0), @as(c_int, c.EVENT_EXTERNAL_MESSAGE));
}

// 10e. Gap verification in enum ranges

test "EVENT_EXTERNAL: value 11 is skipped (no KEYINPUT)" {
    // Values go 0-10, then 12+ (11 was removed/skipped)
    try testing.expectEqual(@as(c_int, 10), @as(c_int, c.EVENT_EXTERNAL_SEGREQ));
    try testing.expectEqual(@as(c_int, 12), @as(c_int, c.EVENT_EXTERNAL_CURSORHINT));
}

test "SEGID: gaps exist in range (no value 8, 10, 11, 12, 18, 25)" {
    // SEGID_ENCODER=7, SEGID_GAME=9 — gap at 8
    try testing.expectEqual(@as(c_int, 7), @as(c_int, c.SEGID_ENCODER));
    try testing.expectEqual(@as(c_int, 9), @as(c_int, c.SEGID_GAME));
    // SEGID_GAME=9, HMD_SBS=13 — gaps at 10,11,12
    try testing.expectEqual(@as(c_int, 13), @as(c_int, c.SEGID_HMD_SBS));
}

// 10f. Cross-constant relationships

test "MAXW * MAXH * VCHANNELS computes correct max buffer" {
    const max_buf: u64 = @as(u64, @intCast(c.PP_SHMPAGE_MAXW)) *
        @as(u64, @intCast(c.PP_SHMPAGE_MAXH)) *
        @as(u64, @intCast(c.ARCAN_SHMPAGE_VCHANNELS));
    try testing.expectEqual(@as(u64, 8192 * 8192 * 4), max_buf);
}

test "MAXSZ can hold at least PP_SHMPAGE_STARTSZ" {
    try testing.expect(c.PP_SHMPAGE_MAXSZ > c.PP_SHMPAGE_STARTSZ);
}

test "two full event queues fit in page size minimum" {
    // Each queue: 127 * 128 bytes + 2 bytes (front/back) = 16258
    // Two queues: 32516
    // Plus other page fields
    const two_queues: usize = 2 * @as(usize, c.PP_QUEUE_SZ) * 128;
    try testing.expect(@as(usize, @intCast(c.PP_SHMPAGE_STARTSZ)) > two_queues);
}

// 10g. Bitmask validation for combined enums

test "all SHMIF_RHINT values OR'd together stay within u8" {
    const all: c_int = c.SHMIF_RHINT_ORIGO_LL | c.SHMIF_RHINT_SUBREGION |
        c.SHMIF_RHINT_IGNORE_ALPHA | c.SHMIF_RHINT_CSPACE_SRGB |
        c.SHMIF_RHINT_AUTH_TOK | c.SHMIF_RHINT_VSIGNAL_EV |
        c.SHMIF_RHINT_EMPTY | c.SHMIF_RHINT_TPACK;
    try testing.expect(all <= 255);
    try testing.expect(all >= 0);
}

test "all EVENT_IDEVKIND values OR'd together stay within u8" {
    const all: c_uint = c.EVENT_IDEVKIND_KEYBOARD | c.EVENT_IDEVKIND_MOUSE |
        c.EVENT_IDEVKIND_GAMEDEV | c.EVENT_IDEVKIND_TOUCHDISP |
        c.EVENT_IDEVKIND_LEDCTRL | c.EVENT_IDEVKIND_EYETRACKER;
    try testing.expect(all <= 255);
}

test "all EVENT_IDATATYPE values OR'd together stay within u8" {
    const all: c_uint = c.EVENT_IDATATYPE_ANALOG | c.EVENT_IDATATYPE_DIGITAL |
        c.EVENT_IDATATYPE_TRANSLATED | c.EVENT_IDATATYPE_TOUCH |
        c.EVENT_IDATATYPE_EYES;
    try testing.expect(all <= 255);
}

test "all ARKMOD values OR'd stay within u16" {
    const all: c_uint = c.ARKMOD_LSHIFT | c.ARKMOD_RSHIFT |
        c.ARKMOD_LCTRL | c.ARKMOD_RCTRL |
        c.ARKMOD_LALT | c.ARKMOD_RALT |
        c.ARKMOD_LMETA | c.ARKMOD_RMETA |
        c.ARKMOD_NUM | c.ARKMOD_CAPS | c.ARKMOD_MODE | c.ARKMOD_REPEAT;
    try testing.expect(all <= 0xFFFF);
}

// 10h. ARCAN_MOUSESTATE modes are small ints

test "mousestate modes fit in 2 bits" {
    try testing.expect(c.ARCAN_MOUSESTATE_ABSOLUTE < 4);
    try testing.expect(c.ARCAN_MOUSESTATE_RELATIVE < 4);
    try testing.expect(c.ARCAN_MOUSESTATE_NOCLAMP < 4);
}

// 10i. Event category bit positions

test "EVENT_IO bit position is 1 (value 2)" {
    try testing.expectEqual(@as(c_uint, 2), c.EVENT_IO);
    try testing.expectEqual(@as(c_uint, 0), c.EVENT_IO & 1); // bit 0 is clear
}

test "EVENT_TARGET bit position is 4 (value 16)" {
    try testing.expectEqual(@as(c_uint, 16), c.EVENT_TARGET);
}

test "EVENT_EXTERNAL bit position is 6 (value 64)" {
    try testing.expectEqual(@as(c_uint, 64), c.EVENT_EXTERNAL);
}

test "all event categories are powers of 2" {
    const cats = [_]c_uint{
        c.EVENT_IO, c.EVENT_SYSTEM, c.EVENT_VIDEO,
        c.EVENT_AUDIO, c.EVENT_TARGET, c.EVENT_FSRV, c.EVENT_EXTERNAL,
    };
    for (cats) |cat| {
        try testing.expect(cat != 0);
        try testing.expectEqual(@as(c_uint, 0), cat & (cat - 1));
    }
}

test "all event categories fit in u8" {
    const cats = [_]c_uint{
        c.EVENT_IO, c.EVENT_SYSTEM, c.EVENT_VIDEO,
        c.EVENT_AUDIO, c.EVENT_TARGET, c.EVENT_FSRV, c.EVENT_EXTERNAL,
    };
    for (cats) |cat| {
        try testing.expect(cat < 256);
    }
}

// 10j. SHMIF_SIGBLK interaction

test "SIGBLK_FORCE is zero (no blocking)" {
    try testing.expectEqual(@as(c_uint, 0), c.SHMIF_SIGBLK_FORCE);
    // OR'ing with FORCE changes nothing
    try testing.expectEqual(c.SHMIF_SIGVID, c.SHMIF_SIGVID | c.SHMIF_SIGBLK_FORCE);
}

test "common signal combos" {
    // Video only, blocking
    try testing.expectEqual(@as(c_uint, 1), c.SHMIF_SIGVID | c.SHMIF_SIGBLK_FORCE);
    // Audio only, blocking
    try testing.expectEqual(@as(c_uint, 2), c.SHMIF_SIGAUD | c.SHMIF_SIGBLK_FORCE);
    // Both, non-blocking
    try testing.expectEqual(@as(c_uint, 7), c.SHMIF_SIGVID | c.SHMIF_SIGAUD | c.SHMIF_SIGBLK_NONE);
    // Video + auto-dirty + non-blocking
    try testing.expectEqual(@as(c_uint, 13), c.SHMIF_SIGVID | c.SHMIF_SIGVID_AUTO_DIRTY | c.SHMIF_SIGBLK_NONE);
}

// 10k. SHMIF_RHINT_TPACK is highest bit

test "SHMIF_RHINT_TPACK is the highest RHINT value" {
    try testing.expect(c.SHMIF_RHINT_TPACK >= c.SHMIF_RHINT_ORIGO_LL);
    try testing.expect(c.SHMIF_RHINT_TPACK >= c.SHMIF_RHINT_SUBREGION);
    try testing.expect(c.SHMIF_RHINT_TPACK >= c.SHMIF_RHINT_IGNORE_ALPHA);
    try testing.expect(c.SHMIF_RHINT_TPACK >= c.SHMIF_RHINT_CSPACE_SRGB);
    try testing.expect(c.SHMIF_RHINT_TPACK >= c.SHMIF_RHINT_AUTH_TOK);
    try testing.expect(c.SHMIF_RHINT_TPACK >= c.SHMIF_RHINT_VSIGNAL_EV);
    try testing.expect(c.SHMIF_RHINT_TPACK >= c.SHMIF_RHINT_EMPTY);
}

// 10l. SEGID ordering properties

test "SEGID_MONITOR and SEGID_DEBUG are at the high end" {
    const all_normal = [_]c_int{
        c.SEGID_UNKNOWN, c.SEGID_LWA, c.SEGID_NETWORK_SERVER,
        c.SEGID_NETWORK_CLIENT, c.SEGID_MEDIA, c.SEGID_TERMINAL,
        c.SEGID_REMOTING, c.SEGID_ENCODER, c.SEGID_GAME,
        c.SEGID_HMD_SBS, c.SEGID_HMD_L, c.SEGID_HMD_R,
        c.SEGID_POPUP, c.SEGID_ICON, c.SEGID_CURSOR,
        c.SEGID_ACCESSIBILITY, c.SEGID_CLIPBOARD, c.SEGID_CLIPBOARD_PASTE,
        c.SEGID_WIDGET, c.SEGID_TUI, c.SEGID_BRIDGE_X11,
        c.SEGID_BRIDGE_WAYLAND, c.SEGID_HANDOVER,
    };
    for (all_normal) |s| {
        try testing.expect(s < @as(c_int, c.SEGID_MONITOR));
        try testing.expect(s < @as(c_int, c.SEGID_DEBUG));
    }
}

test "SEGID_DEBUG is the maximum SEGID value (255)" {
    try testing.expectEqual(@as(c_int, 255), @as(c_int, c.SEGID_DEBUG));
}
