/// shmif ABI layout verification tests
///
/// These tests verify that C struct sizes, offsets, and alignments match
/// the ABI contract.  struct arcan_shmif_page is opaque to @cImport (due
/// to volatile _Atomic / _Alignas fields), so page-level queries go through
/// a thin C helper (shmif_test_helpers.c).
const std = @import("std");
const testing = std.testing;

const c = @import("shmif_types");

// C helper externs (shmif_test_helpers.c)

extern fn shmif_test_sizeof_page() usize;
extern fn shmif_test_sizeof_event() usize;
extern fn shmif_test_sizeof_region() usize;
extern fn shmif_test_sizeof_ioevent() usize;
extern fn shmif_test_sizeof_tgtevent() usize;
extern fn shmif_test_sizeof_extevent() usize;

extern fn shmif_test_offsetof_cookie() usize;
extern fn shmif_test_offsetof_resized() usize;
extern fn shmif_test_offsetof_aready() usize;
extern fn shmif_test_offsetof_abufused() usize;
extern fn shmif_test_offsetof_childevq_front() usize;
extern fn shmif_test_offsetof_childevq_back() usize;
extern fn shmif_test_offsetof_parentevq_front() usize;

extern fn shmif_test_alignof_page() usize;
extern fn shmif_test_offsetof_async() usize;
extern fn shmif_test_offsetof_vsync() usize;
extern fn shmif_test_offsetof_esync() usize;

extern fn shmif_test_offsetof_category() usize;

extern fn shmif_test_evqueue_sz() usize;
extern fn shmif_test_sizeof_evqueue_slot() usize;

// 1a. Core type sizes

test "arcan_event is exactly 128 bytes" {
    try testing.expectEqual(@as(usize, 128), @sizeOf(c.arcan_event));
    try testing.expectEqual(@as(usize, 128), shmif_test_sizeof_event());
}

test "arcan_shmif_region is 8 bytes (4x uint16)" {
    try testing.expectEqual(@as(usize, 8), @sizeOf(c.struct_arcan_shmif_region));
    try testing.expectEqual(@as(usize, 8), shmif_test_sizeof_region());
}

test "arcan_shmif_page size is stable and sane" {
    const page_size = shmif_test_sizeof_page();
    // Must be substantially larger than an event (contains two event queues)
    try testing.expect(page_size > 128);
    // The two event queues alone are 2 * 127 * 128 bytes = 32512
    try testing.expect(page_size > 32512);
}

// 1b. shmif_page field offsets — cookie contract
//
// arcan_shmif_cookie() packs these offsets into a uint64:
//   byte 0: sizeof(arcan_event) + sizeof(arcan_shmif_page)  (truncated to u8)
//   byte 1: offsetof(page, cookie)
//   byte 2: offsetof(page, resized)
//   byte 3: offsetof(page, aready)
//   byte 4: offsetof(page, abufused)
//   byte 5: offsetof(page, childevq.front)
//   byte 6: offsetof(page, childevq.back)
//   byte 7: offsetof(page, parentevq.front)

test "shmif_page resized offset is at byte 2 (after major + minor)" {
    try testing.expectEqual(@as(usize, 2), shmif_test_offsetof_resized());
}

test "shmif_page aready offset is at byte 4 (after major+minor+resized+dms)" {
    try testing.expectEqual(@as(usize, 4), shmif_test_offsetof_aready());
}

test "shmif_page field ordering is monotonically increasing" {
    const cookie = shmif_test_offsetof_cookie();
    const resized = shmif_test_offsetof_resized();
    const aready = shmif_test_offsetof_aready();
    const abufused = shmif_test_offsetof_abufused();
    const childevq_front = shmif_test_offsetof_childevq_front();
    const childevq_back = shmif_test_offsetof_childevq_back();
    const parentevq_front = shmif_test_offsetof_parentevq_front();

    try testing.expect(resized < aready);
    try testing.expect(aready < cookie);
    try testing.expect(cookie > 0);
    try testing.expect(abufused > aready);
    try testing.expect(childevq_front > abufused);
    try testing.expect(childevq_front < childevq_back);
    try testing.expect(childevq_back < parentevq_front);
}

test "cookie computation matches C arcan_shmif_cookie()" {
    // Recompute the cookie in pure Zig using the same algorithm as the C function
    const page_size = shmif_test_sizeof_page();
    const event_size = shmif_test_sizeof_event();

    var zig_cookie: u64 = event_size + page_size;
    zig_cookie |= @as(u64, @truncate(@as(u64, shmif_test_offsetof_cookie()))) << 8;
    zig_cookie |= @as(u64, @truncate(@as(u64, shmif_test_offsetof_resized()))) << 16;
    zig_cookie |= @as(u64, @truncate(@as(u64, shmif_test_offsetof_aready()))) << 24;
    zig_cookie |= @as(u64, @truncate(@as(u64, shmif_test_offsetof_abufused()))) << 32;
    zig_cookie |= @as(u64, @truncate(@as(u64, shmif_test_offsetof_childevq_front()))) << 40;
    zig_cookie |= @as(u64, @truncate(@as(u64, shmif_test_offsetof_childevq_back()))) << 48;
    zig_cookie |= @as(u64, @truncate(@as(u64, shmif_test_offsetof_parentevq_front()))) << 56;

    // Call the actual C function
    const c_cookie = c.arcan_shmif_cookie();
    try testing.expectEqual(c_cookie, zig_cookie);
}

// 1c. Alignment verification

test "page.async is aligned to FUTEX_ALIGN (8)" {
    try testing.expectEqual(@as(usize, 0), shmif_test_offsetof_async() % 8);
}

test "page.vsync is aligned to FUTEX_ALIGN (8)" {
    try testing.expectEqual(@as(usize, 0), shmif_test_offsetof_vsync() % 8);
}

test "page.esync is aligned to FUTEX_ALIGN (8)" {
    try testing.expectEqual(@as(usize, 0), shmif_test_offsetof_esync() % 8);
}

test "arcan_shmif_page alignment accommodates adata (_Alignas 16)" {
    const page_align = shmif_test_alignof_page();
    try testing.expect(page_align >= 16);
}

// 1d. Event union layout

test "arcan_ioevent fits in 127 bytes" {
    try testing.expect(shmif_test_sizeof_ioevent() <= 127);
}

test "arcan_tgtevent fits in 127 bytes" {
    try testing.expect(shmif_test_sizeof_tgtevent() <= 127);
}

test "arcan_extevent fits in 127 bytes" {
    try testing.expect(shmif_test_sizeof_extevent() <= 127);
}

test "event category field offset is consistent with struct layout" {
    // Category sits right after the inner union (io/tgt/ext/...), NOT at byte 127.
    // The pad[128] member ensures the outer union is 128 bytes total, but category
    // is at the offset dictated by the largest union variant's size.
    const cat_off = shmif_test_offsetof_category();
    try testing.expect(cat_off < 128);
    try testing.expect(cat_off > 0);
    // On this platform, the largest inner union member ends at byte 120
    try testing.expectEqual(@as(usize, 120), cat_off);
}

// 1e. Compile-time constants

test "PP_QUEUE_SZ is 127" {
    try testing.expectEqual(@as(c_int, 127), c.PP_QUEUE_SZ);
}

test "ARCAN_SHMIF_ABUFC_LIM is 12" {
    try testing.expectEqual(@as(c_int, 12), c.ARCAN_SHMIF_ABUFC_LIM);
}

test "ARCAN_SHMIF_VBUFC_LIM is 3" {
    try testing.expectEqual(@as(c_int, 3), c.ARCAN_SHMIF_VBUFC_LIM);
}

test "ASHMIF_VERSION_MAJOR is 0" {
    try testing.expectEqual(@as(c_int, 0), c.ASHMIF_VERSION_MAJOR);
}

test "ASHMIF_VERSION_MINOR is 18" {
    try testing.expectEqual(@as(c_int, 18), c.ASHMIF_VERSION_MINOR);
}

// 1f. Event queue geometry

test "event queue has PP_QUEUE_SZ slots" {
    try testing.expectEqual(@as(usize, 127), shmif_test_evqueue_sz());
}

test "each event queue slot is 128 bytes" {
    try testing.expectEqual(@as(usize, 128), shmif_test_sizeof_evqueue_slot());
}

// ═══════════════════════════════════════════════════════════════════
// Tier 10: Sub-struct field offset verification for Zig reimpl
// ═══════════════════════════════════════════════════════════════════

// C helper externs for sub-struct offsets

extern fn shmif_test_offsetof_io_kind() usize;
extern fn shmif_test_offsetof_io_devkind() usize;
extern fn shmif_test_offsetof_io_datatype() usize;
extern fn shmif_test_offsetof_io_label() usize;
extern fn shmif_test_offsetof_io_flags() usize;
extern fn shmif_test_offsetof_io_devid() usize;
extern fn shmif_test_offsetof_io_subid() usize;
extern fn shmif_test_offsetof_io_dst() usize;
extern fn shmif_test_offsetof_io_pts() usize;
extern fn shmif_test_offsetof_io_input() usize;

extern fn shmif_test_offsetof_tgt_kind() usize;
extern fn shmif_test_offsetof_tgt_ioevs() usize;
extern fn shmif_test_offsetof_tgt_code() usize;
extern fn shmif_test_offsetof_tgt_message() usize;
extern fn shmif_test_sizeof_tgt_ioevs_element() usize;
extern fn shmif_test_sizeof_tgt_message() usize;

extern fn shmif_test_offsetof_ext_kind() usize;
extern fn shmif_test_offsetof_ext_source() usize;
extern fn shmif_test_offsetof_ext_frame_id() usize;

extern fn shmif_test_sizeof_ext_message() usize;
extern fn shmif_test_sizeof_ext_labelhint() usize;
extern fn shmif_test_sizeof_ext_registr() usize;
extern fn shmif_test_sizeof_ext_segreq() usize;
extern fn shmif_test_sizeof_ext_clock() usize;
extern fn shmif_test_sizeof_ext_bchunk() usize;
extern fn shmif_test_sizeof_ext_viewport() usize;
extern fn shmif_test_sizeof_ext_content() usize;

extern fn shmif_test_sizeof_ioevent_data() usize;
extern fn shmif_test_sizeof_ioevent_data_analog() usize;
extern fn shmif_test_sizeof_ioevent_data_digital() usize;
extern fn shmif_test_sizeof_ioevent_data_translated() usize;
extern fn shmif_test_sizeof_ioevent_data_touch() usize;
extern fn shmif_test_sizeof_ioevent_data_eyes() usize;

extern fn shmif_test_sizeof_ext_labelhint_label() usize;
extern fn shmif_test_sizeof_ext_labelhint_descr() usize;
extern fn shmif_test_sizeof_ext_labelhint_vsym() usize;
extern fn shmif_test_sizeof_ext_registr_title() usize;
extern fn shmif_test_sizeof_ext_registr_guid() usize;
extern fn shmif_test_sizeof_ext_bchunk_extensions() usize;
extern fn shmif_test_sizeof_ext_message_data() usize;
extern fn shmif_test_sizeof_io_label() usize;

extern fn shmif_test_tgt_field_byte(field: c_int, byte_offset: c_int) u8;

// 10a. ioevent field offsets match C

test "ioevent: kind is at offset 0" {
    try testing.expectEqual(@as(usize, 0), shmif_test_offsetof_io_kind());
}

test "ioevent: devkind follows kind" {
    const devkind_off = shmif_test_offsetof_io_devkind();
    try testing.expect(devkind_off >= 4); // after enum
    try testing.expect(devkind_off <= 8);
}

test "ioevent: label is at expected offset" {
    const label_off = shmif_test_offsetof_io_label();
    try testing.expect(label_off >= 12); // after 3 enums (4 bytes each)
}

test "ioevent: field ordering is monotonically increasing" {
    const kind = shmif_test_offsetof_io_kind();
    const devkind = shmif_test_offsetof_io_devkind();
    const datatype = shmif_test_offsetof_io_datatype();
    const label = shmif_test_offsetof_io_label();
    const flags = shmif_test_offsetof_io_flags();
    const devid = shmif_test_offsetof_io_devid();
    const subid = shmif_test_offsetof_io_subid();
    const dst = shmif_test_offsetof_io_dst();
    const pts = shmif_test_offsetof_io_pts();
    const input = shmif_test_offsetof_io_input();

    try testing.expect(kind < devkind);
    try testing.expect(devkind < datatype);
    try testing.expect(datatype < label);
    try testing.expect(label < flags);
    try testing.expect(flags < devid);
    try testing.expect(devid < subid);
    try testing.expect(subid < dst);
    try testing.expect(dst < pts);
    try testing.expect(pts < input);
}

test "ioevent: label is 16 bytes" {
    try testing.expectEqual(@as(usize, 16), shmif_test_sizeof_io_label());
}

test "ioevent: devid and subid are adjacent 16-bit fields" {
    const devid_off = shmif_test_offsetof_io_devid();
    const subid_off = shmif_test_offsetof_io_subid();
    try testing.expectEqual(devid_off + 2, subid_off);
}

test "ioevent: pts is 8-byte aligned" {
    try testing.expectEqual(@as(usize, 0), shmif_test_offsetof_io_pts() % 8);
}

// 10b. tgtevent field offsets match C

test "tgtevent: kind is at offset 0" {
    try testing.expectEqual(@as(usize, 0), shmif_test_offsetof_tgt_kind());
}

test "tgtevent: ioevs follows kind" {
    const ioevs_off = shmif_test_offsetof_tgt_ioevs();
    try testing.expectEqual(@as(usize, 4), ioevs_off);
}

test "tgtevent: each ioevs element is 4 bytes" {
    try testing.expectEqual(@as(usize, 4), shmif_test_sizeof_tgt_ioevs_element());
}

test "tgtevent: ioevs array spans 32 bytes (8 * 4)" {
    const ioevs_off = shmif_test_offsetof_tgt_ioevs();
    const code_off = shmif_test_offsetof_tgt_code();
    try testing.expectEqual(@as(usize, 32), code_off - ioevs_off);
}

test "tgtevent: code follows ioevs at offset 36" {
    try testing.expectEqual(@as(usize, 36), shmif_test_offsetof_tgt_code());
}

test "tgtevent: message follows code" {
    const code_off = shmif_test_offsetof_tgt_code();
    const msg_off = shmif_test_offsetof_tgt_message();
    try testing.expect(msg_off > code_off);
    try testing.expectEqual(@as(usize, 40), msg_off); // code(4) + padding
}

test "tgtevent: message is 78 bytes" {
    try testing.expectEqual(@as(usize, 78), shmif_test_sizeof_tgt_message());
}

test "tgtevent: total size is stable" {
    const total = shmif_test_sizeof_tgtevent();
    // kind(4) + ioevs(32) + code(4) + message(78) + padding = ~120
    try testing.expect(total >= 118);
    try testing.expect(total <= 127); // must fit in event union
}

// 10c. extevent field offsets match C

test "extevent: kind is at offset 0" {
    try testing.expectEqual(@as(usize, 0), shmif_test_offsetof_ext_kind());
}

test "extevent: source follows kind (aligned to 8)" {
    const source_off = shmif_test_offsetof_ext_source();
    try testing.expectEqual(@as(usize, 8), source_off); // kind(4) + padding(4) for int64_t alignment
}

test "extevent: frame_id is the last field" {
    const frame_id_off = shmif_test_offsetof_ext_frame_id();
    const total = shmif_test_sizeof_extevent();
    // frame_id is uint64_t (8 bytes), so it should be at total - 8
    try testing.expectEqual(total - 8, frame_id_off);
}

test "extevent: union starts after source (offset 16)" {
    // The union should start at offset 16 (kind=4 + pad=4 + source=8)
    const source_off = shmif_test_offsetof_ext_source();
    try testing.expect(source_off + 8 == 16);
}

// 10d. ext sub-union member sizes

test "ext.message size: data[78] + multipart(1) = 79" {
    try testing.expectEqual(@as(usize, 79), shmif_test_sizeof_ext_message());
}

test "ext.message.data is exactly 78 bytes" {
    try testing.expectEqual(@as(usize, 78), shmif_test_sizeof_ext_message_data());
}

test "ext.labelhint.label is 16 bytes" {
    try testing.expectEqual(@as(usize, 16), shmif_test_sizeof_ext_labelhint_label());
}

test "ext.labelhint.descr is 53 bytes" {
    try testing.expectEqual(@as(usize, 53), shmif_test_sizeof_ext_labelhint_descr());
}

test "ext.labelhint.vsym is 5 bytes" {
    try testing.expectEqual(@as(usize, 5), shmif_test_sizeof_ext_labelhint_vsym());
}

test "ext.registr.title is 64 bytes" {
    try testing.expectEqual(@as(usize, 64), shmif_test_sizeof_ext_registr_title());
}

test "ext.registr.guid is 16 bytes (2 * uint64)" {
    try testing.expectEqual(@as(usize, 16), shmif_test_sizeof_ext_registr_guid());
}

test "ext.bchunk.extensions is 68 bytes" {
    try testing.expectEqual(@as(usize, 68), shmif_test_sizeof_ext_bchunk_extensions());
}

test "ext sub-union members all fit within extevent" {
    const ext_size = shmif_test_sizeof_extevent();
    try testing.expect(shmif_test_sizeof_ext_message() < ext_size);
    try testing.expect(shmif_test_sizeof_ext_labelhint() < ext_size);
    try testing.expect(shmif_test_sizeof_ext_registr() < ext_size);
    try testing.expect(shmif_test_sizeof_ext_segreq() < ext_size);
    try testing.expect(shmif_test_sizeof_ext_clock() < ext_size);
    try testing.expect(shmif_test_sizeof_ext_bchunk() < ext_size);
    try testing.expect(shmif_test_sizeof_ext_viewport() < ext_size);
    try testing.expect(shmif_test_sizeof_ext_content() < ext_size);
}

// 10e. ioevent_data union member sizes

test "ioevent_data union size is determined by largest member" {
    const union_sz = shmif_test_sizeof_ioevent_data();
    try testing.expect(union_sz >= shmif_test_sizeof_ioevent_data_analog());
    try testing.expect(union_sz >= shmif_test_sizeof_ioevent_data_digital());
    try testing.expect(union_sz >= shmif_test_sizeof_ioevent_data_translated());
    try testing.expect(union_sz >= shmif_test_sizeof_ioevent_data_touch());
    try testing.expect(union_sz >= shmif_test_sizeof_ioevent_data_eyes());
}

test "ioevent_data.digital is smallest (1 byte: active)" {
    try testing.expectEqual(@as(usize, 1), shmif_test_sizeof_ioevent_data_digital());
}

test "ioevent_data.eyes is large (float arrays)" {
    const eyes_sz = shmif_test_sizeof_ioevent_data_eyes();
    // head_pos[3]=12 + head_ang[3]=12 + gaze_x1..y2=16 + blink_lr=2 + present=1 = 43
    try testing.expect(eyes_sz >= 43);
}

test "ioevent_data.translated has keysym and modifiers" {
    const trans_sz = shmif_test_sizeof_ioevent_data_translated();
    // utf8[5]=5 + active=1 + scancode=1 + padding + keysym=4 + modifiers=2 >= 13
    try testing.expect(trans_sz >= 13);
}

// 10f. Byte-level tgt event field positioning

test "tgt: kind field writes to byte 0" {
    // field=0 writes 0xABCDEF01 to kind (enum at offset 0)
    const byte0 = shmif_test_tgt_field_byte(0, 0);
    // On little-endian, byte 0 should be 0x01
    try testing.expectEqual(@as(u8, 0x01), byte0);
}

test "tgt: ioevs[0] starts at byte 4" {
    // field=1 writes 0xDEADBEEF to ioevs[0].uiv
    const byte4 = shmif_test_tgt_field_byte(1, 4);
    // On little-endian, byte 4 should be 0xEF
    try testing.expectEqual(@as(u8, 0xEF), byte4);
}

test "tgt: ioevs[7] starts at byte 32" {
    // field=2 writes 0xCAFEBABE to ioevs[7].uiv
    // ioevs[7] offset = 4 + 7*4 = 32
    const byte32 = shmif_test_tgt_field_byte(2, 32);
    // On little-endian, 0xCAFEBABE: byte32=0xBE
    try testing.expectEqual(@as(u8, 0xBE), byte32);
}

test "tgt: code at byte 36" {
    // field=3 writes 0x12345678 to code
    const byte36 = shmif_test_tgt_field_byte(3, 36);
    try testing.expectEqual(@as(u8, 0x78), byte36); // LE
}

test "tgt: message starts at byte 40" {
    // field=4 fills message with 0xFF
    const byte40 = shmif_test_tgt_field_byte(4, 40);
    try testing.expectEqual(@as(u8, 0xFF), byte40);
}

test "tgt: bytes before message are not affected by message write" {
    // field=4 fills message with 0xFF; bytes before message should be 0
    const byte36 = shmif_test_tgt_field_byte(4, 36);
    try testing.expectEqual(@as(u8, 0), byte36); // code area should be 0
}

// 10g. Union aliasing: ioevs members share same bytes

test "ioevs: iv and uiv share the same bytes" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.category().* = c.EVENT_TARGET;
    const tgt = &ev.tgt();
    tgt.ioevs[0].iv = -1; // 0xFFFFFFFF in unsigned
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), tgt.ioevs[0].uiv);
}

test "ioevs: iv and cv share the same bytes" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.category().* = c.EVENT_TARGET;
    const tgt = &ev.tgt();
    tgt.ioevs[0].cv = .{ 0x12, 0x34, 0x56, 0x78 };
    // On LE: iv = 0x78563412
    try testing.expectEqual(@as(i32, 0x78563412), tgt.ioevs[0].iv);
}

test "ioevs: fv bit pattern matches iv reinterpretation" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.category().* = c.EVENT_TARGET;
    const tgt = &ev.tgt();
    tgt.ioevs[0].fv = 1.0;
    // IEEE 754: 1.0f = 0x3F800000
    try testing.expectEqual(@as(u32, 0x3F800000), tgt.ioevs[0].uiv);
}

test "ioevs: zero in all union arms" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    const tgt = &ev.tgt();
    // All zeroes: iv=0, uiv=0, fv=0.0, cv={0,0,0,0}
    try testing.expectEqual(@as(i32, 0), tgt.ioevs[0].iv);
    try testing.expectEqual(@as(u32, 0), tgt.ioevs[0].uiv);
    try testing.expectEqual(@as(f32, 0.0), tgt.ioevs[0].fv);
    try testing.expectEqual([4]u8{ 0, 0, 0, 0 }, tgt.ioevs[0].cv);
}

// 10h. Category position in raw bytes

test "category byte position: write category, verify in raw bytes" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.category().* = 0xAB;
    const raw = std.mem.asBytes(&ev);
    // Category is at offset 120
    try testing.expectEqual(@as(u8, 0xAB), raw[120]);
}

test "category byte: all other bytes zero when only category is set" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.category().* = c.EVENT_TARGET;
    const raw = std.mem.asBytes(&ev);
    // Only byte 120 should be non-zero
    var nonzero_count: usize = 0;
    for (raw) |b| {
        if (b != 0) nonzero_count += 1;
    }
    try testing.expectEqual(@as(usize, 1), nonzero_count);
}

// 10i. tgt and ext overlay in event union

test "tgt and ext start at same byte offset within event" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    const tgt_ptr: usize = @intFromPtr(&ev.tgt());
    const ext_ptr: usize = @intFromPtr(&ev.ext());
    const ev_ptr: usize = @intFromPtr(&ev);
    // Both should start at the beginning of the event (offset 0)
    try testing.expectEqual(ev_ptr, tgt_ptr);
    try testing.expectEqual(ev_ptr, ext_ptr);
}

test "io, tgt, ext all start at event base address" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    const base: usize = @intFromPtr(&ev);
    const io_ptr: usize = @intFromPtr(&ev.io());
    const tgt_ptr: usize = @intFromPtr(&ev.tgt());
    const ext_ptr: usize = @intFromPtr(&ev.ext());
    try testing.expectEqual(base, io_ptr);
    try testing.expectEqual(base, tgt_ptr);
    try testing.expectEqual(base, ext_ptr);
}

// 10j. Zig @sizeOf cross-check against C sizeof

test "Zig @sizeOf(arcan_ioevent) matches C" {
    try testing.expectEqual(shmif_test_sizeof_ioevent(), @sizeOf(c.arcan_ioevent));
}

test "Zig @sizeOf(arcan_tgtevent) matches C" {
    try testing.expectEqual(shmif_test_sizeof_tgtevent(), @sizeOf(c.arcan_tgtevent));
}

test "Zig @sizeOf(arcan_extevent) matches C" {
    try testing.expectEqual(shmif_test_sizeof_extevent(), @sizeOf(c.arcan_extevent));
}

test "Zig @sizeOf(arcan_event) matches C (128)" {
    try testing.expectEqual(shmif_test_sizeof_event(), @sizeOf(c.arcan_event));
    try testing.expectEqual(@as(usize, 128), @sizeOf(c.arcan_event));
}

// 10k. Padding and alignment between event sub-structs

test "tgt + ext + io all fit within 120 bytes (category at 120)" {
    const cat_off = shmif_test_offsetof_category();
    try testing.expect(shmif_test_sizeof_ioevent() <= cat_off);
    try testing.expect(shmif_test_sizeof_tgtevent() <= cat_off);
    try testing.expect(shmif_test_sizeof_extevent() <= cat_off);
}

test "pad[128] covers entire event including category" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    // Write through pad
    ev.unnamed_0.pad[120] = 42;
    // Read through category
    try testing.expectEqual(@as(u8, 42), ev.category().*);
}

test "writing category does not corrupt tgt.kind" {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    // Write tgt.kind first
    ev.tgt().kind = c.TARGET_COMMAND_DISPLAYHINT;
    // Then set category
    ev.category().* = c.EVENT_TARGET;
    // tgt.kind should be unchanged (they don't overlap)
    try testing.expectEqual(
        @as(@TypeOf(ev.tgt().kind), c.TARGET_COMMAND_DISPLAYHINT),
        ev.tgt().kind,
    );
}
