// Zig port of shmmon.c — opens an arcan shmif page (by path or /proc/<pid>/fd/N),
// dumps parsed page header (cookie, dms, pids, audio/video state, event queues).
// Reuses shmif_offsets / shmif_types bindings instead of redeclaring the layout.

const std = @import("std");
const off = @import("shmif_offsets");
const c = @import("shmif_types");
const libc = @import("posix");
const shmif = @import("shmif_api");

// Re-exports so the existing call sites compile untouched. Source of
// truth lives in src/platform/posix/libc.zig and src/shmif/shmif_api.zig.
const printf = libc.printf;
const putchar = libc.putchar;
const open = libc.open;
const close = libc.close;
const mmap = libc.mmap;
const munmap = libc.munmap;
const malloc = libc.malloc;
const free = libc.free;
const memcpy = libc.memcpy;
const signal = libc.signal;
const sigsetjmp = libc.sigsetjmp;
const siglongjmp = libc.siglongjmp;
const arcan_shmif_cookie = shmif.arcan_shmif_cookie;
const arcan_shmif_eventstr = shmif.arcan_shmif_eventstr;

// fprintf in shmmon was declared with `?*anyopaque` for the stream and
// stderr as `?*anyopaque` (untyped) so the call sites pass `stderr` directly.
// Keep that local signature pair to avoid touching ~10 call sites.
extern fn fprintf(stream: ?*anyopaque, fmt: [*:0]const u8, ...) c_int;
extern var stderr: ?*anyopaque;

// parse_edid — other agent provides this (C or Zig). Keep the signature
// matching the original C decl: void parse_edid(const uint8_t* const data).
extern fn parse_edid(data: [*]const u8) void;

// POSIX constants (aarch64 linux)
const O_RDONLY: c_int = 0;
const PROT_READ: c_int = 1;
const MAP_SHARED: c_int = 1;
const MAP_FAILED: ?*anyopaque = @ptrFromInt(std.math.maxInt(usize));
const SIGBUS: c_int = 7;

// Opaque jmp_buf: on glibc aarch64 sigjmp_buf is 40 unsigned longs; overshoot for safety.
const JmpBuf = [512]u8;
var recover: JmpBuf align(16) = undefined;

fn busHandler(_: c_int) callconv(.c) void {
    siglongjmp(@ptrCast(&recover), 1);
}

fn warnCStr(msg: [*:0]const u8) void {
    _ = fprintf(stderr, "%s", msg);
}

fn showUse() void {
    _ = printf("Usage: shmmon /dev/shm/arcan_XXX_XXXm or /proc/pid/fds/XX\n");
}

// dump a single arcan_event via shmif_eventstr
fn dumpEvent(ev: c.arcan_event) void {
    var buf: [512]u8 = undefined;
    // arcan_shmif_eventstr returns an internal buffer when buf is null; pass
    // our stack buffer for thread-safety parity.
    const s = arcan_shmif_eventstr(&ev, &buf, buf.len);
    if (s == null) return;
    _ = printf("%s\n", @as([*:0]const u8, @ptrCast(s)));
}

// decode_apad — parse offset table, ramps, optional EDID
fn decodeApad(apad: [*]const u8, apad_sz: usize) void {
    if (apad_sz < @sizeOf(c.struct_arcan_shmif_ofstbl)) {
        _ = printf(
            "apad-region: [size mismatch: %zu, expected >= %zu]\n",
            apad_sz,
            @as(usize, @sizeOf(c.struct_arcan_shmif_ofstbl)),
        );
        return;
    }

    var ofsets: c.struct_arcan_shmif_ofstbl = std.mem.zeroes(c.struct_arcan_shmif_ofstbl);
    _ = memcpy(&ofsets, apad, @sizeOf(c.struct_arcan_shmif_ofstbl));
    const ofs = &ofsets.unnamed_0.unnamed_0;

    _ = printf(
        "apad-region, RVAs:\n" ++
            "\tcolor-mgmt: %u+%ub\n" ++
            "\tVR: %u+%ub\n" ++
            "\tHDR: %u+%ub\n" ++
            "\tVector: %u+%ub\n",
        ofs.ofs_ramp, ofs.sz_ramp,
        ofs.ofs_vr, ofs.sz_vr,
        ofs.ofs_hdr, ofs.sz_hdr,
        ofs.ofs_vector, ofs.sz_vector,
    );

    if (ofs.sz_ramp == 0) return;

    // Read ramp header at base+ofs_ramp. Layout: magic u32, dirty_in u8,
    // dirty_out u8, n_blocks u8, (pad), then ramp_block[] of 16568 bytes.
    const ramp_base = apad + ofs.ofs_ramp;
    var magic: u32 = 0;
    _ = memcpy(&magic, ramp_base, 4);
    if (magic != c.ARCAN_SHMIF_RAMPMAGIC) {
        _ = printf(
            "color-mgmt MAGIC MISMATCH (%x vs %x)\n",
            magic,
            @as(u32, c.ARCAN_SHMIF_RAMPMAGIC),
        );
    }
    const dirty_in: u8 = ramp_base[4];
    // dirty_out intentionally unused (mirrors C which reads dirty_in twice)
    const n_blocks: u8 = ramp_base[6];

    _ = printf("color-mgmt (blocks: %u):\n\tdirty-in: ", @as(c_uint, n_blocks));
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const bit: u8 = @as(u8, 1) << @intCast((i << 1) & 7);
        _ = putchar(if ((bit & dirty_in) > 0) '1' else '0');
    }
    _ = printf("\n\tdirty-out: ");
    i = 0;
    while (i < 8) : (i += 1) {
        const bit: u8 = @as(u8, 1) << @intCast((i << 1) & 7);
        _ = putchar(if ((bit & dirty_in) > 0) '1' else '0');
    }

    _ = printf("\ncolor-mgmt, blocks:\n");

    // ramp_block: edid[128] + plane_sizes (256 u16) + plane_data (2048 u8) + checksum u16.
    // Per shmif_types.struct_ramp_block + SHMIF_CMRAMP_UPLIM bytes trailing.
    const RampBlock = extern struct {
        block: c.struct_ramp_block,
        plane_lim: [c.SHMIF_CMRAMP_PLIM * c.SHMIF_CMRAMP_UPLIM]u8,
    };

    const ramps_base = ramp_base + 8; // header is 8 bytes before ramps[]
    var bi: usize = 0;
    while (bi < n_blocks) : (bi += 1) {
        var disp_block: RampBlock = std.mem.zeroes(RampBlock);
        const src = ramps_base + bi * off.Ramp.sizeof_ramp_block;
        _ = memcpy(&disp_block, src, @sizeOf(RampBlock));

        const csum_len: usize = 128 +
            @as(usize, @intCast(c.SHMIF_CMRAMP_PLIM)) *
                @as(usize, @intCast(c.SHMIF_CMRAMP_UPLIM));
        const edid_ptr: [*]const u8 = @ptrCast(&disp_block.block.edid);
        const checksum = subpChecksum(edid_ptr, csum_len);

        if (disp_block.block.checksum != checksum) {
            _ = printf(
                "[%zu] - checksum mismatch (%u != %u)\n",
                bi,
                @as(c_uint, checksum),
                @as(c_uint, disp_block.block.checksum),
            );
            continue;
        }

        // disp_block.block has no 'format' field in our Zig binding; the C code
        // reads it from the ramp_block struct — fall back to 0 for parity.
        _ = printf("[%zu] - format: 0 sizes:\n", bi);
        for (disp_block.block.plane_lim, 0..) |sz, j| {
            _ = printf("\t[%zu][%zu] %u bytes\n", bi, j, @as(c_uint, sz));
        }

        var edid_nonzero = false;
        for (disp_block.block.edid) |byte| {
            if (byte != 0) {
                edid_nonzero = true;
                break;
            }
        }
        if (edid_nonzero) {
            _ = printf("[%zu] EDID contents:\n", bi);
            parse_edid(&disp_block.block.edid);
        }
    }
}

// BSD-style checksum (mirrors subp_checksum from arcan_shmif_sub.h)
fn subpChecksum(buf: [*]const u8, len: usize) u16 {
    var res: u16 = 0;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        res = @intCast(((@as(u32, res) >> 1) + buf[i]) & 0xffff);
    }
    return res;
}

// dump_snapshot — parse a local copy of the shm page header
fn dumpSnapshot(page: *anyopaque, qlim: usize) void {
    const major = off.Page.getMajor(page);
    const minor = off.Page.getMinor(page);
    const cookie = off.Page.getCookie(page);
    const dms = off.Page.getDms(page);

    _ = printf(
        "version: %u, %u\ncookie: %s\n",
        @as(c_uint, major),
        @as(c_uint, minor),
        @as([*:0]const u8, if (arcan_shmif_cookie() == cookie) "match" else "fail"),
    );

    _ = printf("dead man switch: %s\n", @as([*:0]const u8, if (dms != 0) "OK" else "Dead"));
    _ = printf("monitor pid: %d\n", off.Page.getParent(page));
    _ = printf("size: %zu\n", @as(usize, off.Page.getSegmentSize(page)));

    _ = printf(
        "audio(%zu bytes @ %zu Hz):\n\t last: %d, pending: %d\n",
        @as(usize, off.Page.getAbufsize(page)),
        @as(usize, off.Page.getAudiorate(page)),
        @as(c_int, @intCast(off.Page.getAready(page))),
        @as(c_int, @intCast(off.Page.getApending(page))),
    );

    _ = printf(
        "video(%zu*%zu] rz-ack-pending: %d):\n\tlast: %d, pending: %d, ts: %llu\n\t",
        @as(usize, off.Page.getW(page)),
        @as(usize, off.Page.getH(page)),
        @as(c_int, off.Page.getResized(page)),
        @as(c_int, @intCast(off.Page.getVready(page))),
        @as(c_int, @intCast(off.Page.getVpending(page))),
        off.Page.getVpts(page),
    );

    const dirty_raw = off.Page.getDirtyRaw(page);
    const dirty: c.arcan_shmif_region = @bitCast(dirty_raw);
    _ = printf(
        "dirty region: %zu,%zu - %zu,%zu\n\t",
        @as(usize, dirty.x1), @as(usize, dirty.y1),
        @as(usize, dirty.x2), @as(usize, dirty.y2),
    );

    const hints = off.Page.getHints(page);
    _ = printf("render hints:\n\t\t");
    if ((hints & @as(u8, @intCast(c.SHMIF_RHINT_ORIGO_LL))) != 0)
        _ = printf("origo-ll ")
    else
        _ = printf("origo-ul ");
    if ((hints & @as(u8, @intCast(c.SHMIF_RHINT_SUBREGION))) != 0)
        _ = printf("subregion ");
    if ((hints & @as(u8, @intCast(c.SHMIF_RHINT_IGNORE_ALPHA))) != 0)
        _ = printf("ignore-alpha ");
    if ((hints & @as(u8, @intCast(c.SHMIF_RHINT_CSPACE_SRGB))) != 0)
        _ = printf("sRGB ");
    if ((hints & @as(u8, @intCast(c.SHMIF_RHINT_AUTH_TOK))) != 0)
        _ = printf("auth-token ");

    dumpQueue(page, qlim, .child);
    dumpQueue(page, qlim, .parent);

    _ = printf("\nlast words: ");
    var j: usize = 0;
    while (j < off.Page.sizeof_last_words) : (j += 1) {
        const ch = off.Page.getLastWordsChar(page, j);
        if (ch == 0) break;
        _ = putchar(@as(c_int, ch));
    }

    const apad = off.Page.getApad(page);
    const apad_type = off.Page.getApadType(page);
    _ = printf("\naux- protocols (size: %zu):\n\t", @as(usize, apad));
    if ((apad_type & @as(u32, @intCast(c.SHMIF_META_CM))) != 0)
        _ = printf("color-mgmt ");
    // SHMIF_META_HDRF16 / SHMIF_META_VOBJ / SHMIF_META_LDEF — not in shmif headers,
    // were stubbed to 0 in the C build; omitted here.
    if ((apad_type & @as(u32, @intCast(c.SHMIF_META_VR))) != 0)
        _ = printf("vr ");
    _ = printf("\n");
}

const QueueSide = enum { child, parent };

fn dumpQueue(page: *anyopaque, qlim: usize, side: QueueSide) void {
    const evbuf = switch (side) {
        .child => off.Page.childevqEventbuf(page),
        .parent => off.Page.parentevqEventbuf(page),
    };
    const front = switch (side) {
        .child => off.Page.childevqFrontPtr(page).*,
        .parent => off.Page.parentevqFrontRead(page),
    };
    const back = switch (side) {
        .child => off.Page.childevqBackPtr(page).*,
        .parent => off.Page.parentevqBackRead(page),
    };

    _ = printf(switch (side) {
        .child => @as([*:0]const u8, "\nqueue(in):\n"),
        .parent => @as([*:0]const u8, "queue(out):\n"),
    });

    var cur: u8 = front;
    var i: usize = 0;
    while (i < qlim) : (i += 1) {
        const label: [*:0]const u8 = if (cur == front and cur == back)
            "F/B"
        else if (cur == front)
            "F"
        else if (cur == back)
            "B"
        else
            " ";

        // Pull event into a local, parse category.
        var ev: c.arcan_event = c.arcan_event.zeroes();
        const src = evbuf + @as(usize, cur) * off.Page.sizeof_event;
        _ = memcpy(&ev, src, @sizeOf(c.arcan_event));
        if (ev.unnamed_0.unnamed_0.category != 0) {
            _ = printf("%s\t[%d] ", label, @as(c_int, cur));
            dumpEvent(ev);
        }

        if (cur == 0) {
            cur = @intCast(off.Page.pp_queue_sz - 1);
        } else {
            cur -= 1;
        }
    }
}

// entry point
export fn main(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    if (argc <= 1) {
        showUse();
        return 1;
    }

    const path: [*:0]const u8 = @ptrCast(argv[1]);

    var apad_reg: ?*anyopaque = null;
    var addr: ?*anyopaque = null;
    var addr_sz: usize = 0;

    const fd = open(path, O_RDONLY);
    if (fd == -1) {
        _ = fprintf(stderr, "couldn't open %s\n", path);
        return 1;
    }

    // SIG_ERR = (void*)-1 on POSIX. signal() returns the previous handler on
    // success (may legitimately be NULL = SIG_DFL) so we only fail on -1.
    const SIG_ERR: ?libc.SigHandler = @ptrFromInt(@as(usize, std.math.maxInt(usize)));
    if (signal(SIGBUS, &busHandler) == SIG_ERR) {
        _ = fprintf(stderr, "Couldn't install SIGBUS handler.\n");
    }

    if (sigsetjmp(@ptrCast(&recover), 1) != 0) {
        _ = fprintf(stderr, "SIGBUS during read, retrying.\n");
        if (addr) |a| {
            _ = munmap(a, addr_sz);
            addr = null;
        }
        if (apad_reg) |a| {
            free(a);
            apad_reg = null;
        }
    }

    // First pass: only map the minimal header range — we need segment_size
    // from the header to know the real size.
    addr = mmap(null, off.Page.sizeof_page, PROT_READ, MAP_SHARED, fd, 0);
    if (addr == MAP_FAILED or addr == null) {
        _ = fprintf(stderr, "couldn't map shmpage\n");
        return 1;
    }
    addr_sz = off.Page.sizeof_page;

    // Copy header bytes into a private buffer, then dump.
    var base_buf: [off.Page.sizeof_page]u8 align(16) = undefined;
    _ = memcpy(&base_buf, addr, off.Page.sizeof_page);
    dumpSnapshot(&base_buf, off.Page.pp_queue_sz);

    // Read segment_size from our private copy, then remap the full range.
    const seg_size: usize = @as(usize, off.Page.getSegmentSize(&base_buf));
    _ = munmap(addr.?, off.Page.sizeof_page);
    addr = mmap(null, seg_size, PROT_READ, MAP_SHARED, fd, 0);
    addr_sz = seg_size;
    if (addr == MAP_FAILED or addr == null) {
        _ = fprintf(stderr, "couldn't map entire shmpage- range\n");
        return 1;
    }

    // Refresh header copy (apad may have changed since first mmap).
    _ = memcpy(&base_buf, addr, off.Page.sizeof_page);
    const apad = off.Page.getApad(&base_buf);
    if (apad != 0) {
        apad_reg = malloc(apad);
        if (apad_reg == null) {
            _ = fprintf(stderr, "apad- buffer allocation failure (%u bytes)\n", apad);
        } else {
            const adata_src: [*]const u8 =
                @as([*]const u8, @ptrCast(addr.?)) + off.Page.sizeof_page;
            _ = memcpy(apad_reg, adata_src, apad);
            decodeApad(@ptrCast(apad_reg.?), apad);
            free(apad_reg);
            apad_reg = null;
        }
    }

    _ = close(fd);
    return 0;
}
