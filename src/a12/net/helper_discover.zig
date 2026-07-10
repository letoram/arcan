// Zig port of a12/net/a12_helper_discover.c — A12 local service discovery
// Implements beacon building, sending, and listening for peer discovery
// via UDP multicast/broadcast on the local network.
// Copyright: Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");

// Dispatch struct replacing the prior `@cImport` block. Each alias routes
// to the appropriate hand-written replacement module (zero `@cImport`
// left).
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    // libc — sockets / poll / ctype
    pub const bind = libc.bind;
    pub const close = libc.close;
    pub const getnameinfo = libc.getnameinfo;
    pub const htonl = libc.htonl;
    pub const htons = libc.htons;
    pub const inet_pton = libc.inet_pton;
    pub const poll = libc.poll;
    pub const recvmsg = libc.recvmsg;
    pub const sendto = libc.sendto;
    pub const setsockopt = libc.setsockopt;
    pub const sleep = libc.sleep;
    pub const socket = libc.socket;

    pub const AF_INET = libc.AF_INET;
    pub const AF_INET6 = libc.AF_INET6;
    pub const EINTR = libc.EINTR;
    pub const INADDR_ANY = libc.INADDR_ANY;
    pub const INADDR_BROADCAST = libc.INADDR_BROADCAST;
    pub const INET6_ADDRSTRLEN = libc.INET6_ADDRSTRLEN;
    pub const IP_MULTICAST_LOOP = libc.IP_MULTICAST_LOOP;
    pub const IP_PKTINFO = libc.IP_PKTINFO;
    pub const IPPROTO_IP = libc.IPPROTO_IP;
    pub const IPPROTO_IPV6 = libc.IPPROTO_IPV6;
    pub const IPPROTO_UDP = libc.IPPROTO_UDP;
    pub const IPV6_JOIN_GROUP = libc.IPV6_JOIN_GROUP;
    pub const IPV6_MULTICAST_HOPS = libc.IPV6_MULTICAST_HOPS;
    pub const IPV6_MULTICAST_LOOP = libc.IPV6_MULTICAST_LOOP;
    pub const MSG_DONTWAIT = libc.MSG_DONTWAIT;
    pub const NI_NUMERICHOST = libc.NI_NUMERICHOST;
    pub const NI_NUMERICSERV = libc.NI_NUMERICSERV;
    pub const POLLERR = libc.POLLERR;
    pub const POLLHUP = libc.POLLHUP;
    pub const POLLIN = libc.POLLIN;
    pub const SO_BROADCAST = libc.SO_BROADCAST;
    pub const SOCK_DGRAM = libc.SOCK_DGRAM;
    pub const socklen_t = libc.socklen_t;
    pub const SOL_SOCKET = libc.SOL_SOCKET;
    pub const SO_REUSEADDR = libc.SO_REUSEADDR;

    pub const struct_cmsghdr = libc.struct_cmsghdr;
    pub const struct_in_addr = libc.struct_in_addr;
    pub const struct_in_pktinfo = libc.struct_in_pktinfo;
    pub const struct_iovec = libc.struct_iovec;
    pub const struct_ipv6_mreq = libc.struct_ipv6_mreq;
    pub const struct_msghdr = libc.struct_msghdr;
    pub const struct_pollfd = libc.struct_pollfd;
    pub const struct_sockaddr = libc.struct_sockaddr;
    pub const struct_sockaddr_in = libc.struct_sockaddr_in;
    pub const struct_sockaddr_in6 = libc.struct_sockaddr_in6;

    // a12 — blake3 hasher type
    pub const blake3_hasher = a12.blake3_hasher;

    // shmif / anet — keystore / shmif cont / discover opts
    pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
    pub const struct_anet_discover_opts = anet.struct_anet_discover_opts;
    pub const struct_keystore_mask = anet.struct_keystore_mask;
};

// Constants

/// Number of key slots that fit in a single beacon packet.
const beacon_key_cap: usize = 15;
/// Per-key hash size in a beacon (32-byte truncated BLAKE3).
const beacon_member_size: usize = 32;
/// Discovery port used for beacon send and receive.
const beacon_port: u16 = 6680;
/// Raw beacon MTU budget (must be ≤ 9000 bytes for UDP).
const mtu_size: usize = 9000;
/// Beacon packet header size: 8-byte checksum + 8-byte challenge.
const header_size: usize = 16;
/// Buffer size for one beacon packet (header + all key hashes).
const buf_sz: usize = beacon_key_cap * beacon_member_size + header_size;

// Extern declarations

const Blake3Hasher = c.blake3_hasher;

extern "c" fn blake3_hasher_init(self: *Blake3Hasher) void;
extern "c" fn blake3_hasher_update(self: *Blake3Hasher, input: *const anyopaque, input_len: usize) void;
extern "c" fn blake3_hasher_finalize(self: *const Blake3Hasher, out: [*]u8, out_len: usize) void;

extern "c" fn arcan_random(dst: [*]u8, ntc: usize) void;
extern "c" fn arcan_timemillis() c_ulonglong;
extern "c" fn pack_u64(src: u64, outb: [*]u8) void;
extern "c" fn unpack_u64(dst: *u64, inbuf: [*]u8) void;
extern "c" fn strerror(errnum: c_int) [*:0]const u8;

extern "c" fn a12helper_keystore_public_tagset(mask: *c.struct_keystore_mask) bool;
extern "c" fn a12helper_keystore_known_accepted_challenge(
    pubk: [*]const u8,
    chg: [*]const u8,
    on_beacon: OnBeaconFn,
    shmif_C: ?*c.struct_arcan_shmif_cont,
    addr: [*]u8,
) bool;

// Callback type aliases
// Use [*c] pointer types to match exactly what @cImport generates for the
// function pointer fields in struct_anet_discover_opts.

pub const OnBeaconFn = *const fn (
    shmif_C: [*c]c.struct_arcan_shmif_cont,
    kpub: [*c]const u8,
    nonce: [*c]const u8,
    tag: [*c]const u8,
    addr: [*c]u8,
) callconv(.c) bool;

pub const OnUnknownFn = *const fn (addr: [*c]u8) callconv(.c) void;
pub const OnShmifFn = *const fn (shmif_C: [*c]c.struct_arcan_shmif_cont) callconv(.c) bool;

// Module-level state

/// Per-process beacon tracking map (keyed by sender IP string).
/// Populated lazily on first call to a12helper_listen_beacon.
const BeaconMap = std.StringHashMap(*Beacon);
var known_beacons: ?BeaconMap = null;

// Internal data structures

/// One received beacon packet with its raw bytes and parsed header.
/// Layout mirrors the C wire format:
///   [0..8)   chk   — BLAKE3 checksum of (chg || keys)
///   [8..16)  chg   — 64-bit challenge counter
///   [16..)   keys  — beacon_member_size-byte entries
const BeaconSlot = struct {
    raw: [mtu_size]u8 = std.mem.zeroes([mtu_size]u8),
    /// Length of the keys region (total received bytes minus header_size).
    len: usize = 0,
    /// Receive timestamp in milliseconds (arcan_timemillis).
    ts: u64 = 0,

    fn chk(self: *BeaconSlot) *[8]u8 {
        return self.raw[0..8];
    }
    fn chg(self: *BeaconSlot) *[8]u8 {
        return self.raw[8..16];
    }
    /// Slice of the keyset region only (bytes 16 .. 16+len).
    fn keys(self: *BeaconSlot) []u8 {
        return self.raw[header_size .. header_size + self.len];
    }
};

/// Pair of successive beacon packets from the same sender, used to
/// verify the liveness and integrity of the announce.
const Beacon = struct {
    slot: [2]BeaconSlot = .{ BeaconSlot{}, BeaconSlot{} },
    tag: ?[*:0]u8 = null,
};

/// Socket configuration for one UDP endpoint (IPv4 or IPv6).
/// Matches the layout of `struct ipcfg` from a12_helper_discover.c.
/// The C header only forward-declares `struct ipcfg` as opaque, so callers
/// interact with it only through pointers; our layout is private to this file.
pub const IpCfg = extern struct {
    /// Anonymous union in the C source — holds the target sockaddr.
    addr: extern union {
        v6: c.struct_sockaddr_in6,
        v4: c.struct_sockaddr_in,
        base: c.struct_sockaddr,
    },
    ipv6: bool,
    addr_sz: usize,
    err: ?[*:0]const u8,
    sock: c_int,

    fn zero() IpCfg {
        return .{
            .addr = .{ .base = std.mem.zeroes(c.struct_sockaddr) },
            .ipv6 = false,
            .addr_sz = 0,
            .err = null,
            .sock = -1,
        };
    }
};

// unpack_beacon

/// Store packet `buf` into `b.slot[slot]` and, when slot==1, validate the
/// pair for integrity and liveness.
///
/// Returns:
///   0  — first slot stored, awaiting second packet
///  -1  — hard validation failure (drop both slots, restart fresh)
///  -2  — challenge sequence mismatch (slide slot[1]→slot[0], retry)
///   1  — pair fully validated and ready for key dispatch
fn unpackBeacon(
    b: *Beacon,
    slot: u1,
    buf: []const u8,
) struct { status: i32, err: ?[]const u8 } {
    @memcpy(b.slot[slot].raw[0..buf.len], buf);
    b.slot[slot].len = buf.len - header_size;
    b.slot[slot].ts = @intCast(arcan_timemillis());

    // Only cache the first slot; actual validation requires both.
    if (slot == 0) return .{ .status = 0, .err = null };

    // Both slots must carry the same key count.
    if (b.slot[0].len != b.slot[1].len)
        return .{ .status = -1, .err = "beacon length mismatch" };

    // Challenge in slot[1] must be exactly slot[0].chg + 1.
    var chg0: u64 = undefined;
    var chg1: u64 = undefined;
    unpack_u64(&chg0, b.slot[0].chg());
    unpack_u64(&chg1, b.slot[1].chg());
    if (chg1 != chg0 +% 1)
        return .{ .status = -2, .err = "beacon pair challenge mismatch" };

    // Proof-of-time: at least ~1 second between the two packets.
    if (b.slot[1].ts - b.slot[0].ts < 980)
        return .{ .status = -2, .err = "beacon pair too close" };

    // Keyset must be an exact multiple of the member size.
    if (b.slot[0].len % beacon_member_size != 0)
        return .{ .status = -1, .err = "invalid beacon keyset length" };

    // Verify BLAKE3(chg0 || keys0) == chk0.
    var chk_computed: [8]u8 = undefined;
    var temp: Blake3Hasher = undefined;
    blake3_hasher_init(&temp);
    blake3_hasher_update(&temp, b.slot[0].chg(), b.slot[0].len + 8);
    blake3_hasher_finalize(&temp, &chk_computed, 8);
    if (!std.mem.eql(u8, &chk_computed, b.slot[0].chk()))
        return .{ .status = -1, .err = "first beacon checksum fail" };

    // Verify BLAKE3(chg1 || keys1) == chk1.
    blake3_hasher_init(&temp);
    blake3_hasher_update(&temp, b.slot[1].raw[8..].ptr, b.slot[1].len + 8);
    blake3_hasher_finalize(&temp, &chk_computed, 8);
    if (!std.mem.eql(u8, &chk_computed, b.slot[1].chk()))
        return .{ .status = -1, .err = "second beacon checksum fail" };

    return .{ .status = 1, .err = null };
}

// a12helper_build_beacon

/// Build two beacon packets from the outbound keyset.
///
/// Allocates `one` and `two` (each `*outsz` bytes) via the C allocator.
/// The caller owns these allocations.  Returns the next unconsumed mask entry
/// (null if the whole keyset was consumed).
///
/// Exported with C ABI as `a12helper_build_beacon`.
pub export fn a12helper_build_beacon(
    head: *c.struct_keystore_mask,
    tail: *c.struct_keystore_mask,
    one: *[*]u8,
    two: *[*]u8,
    outsz: *usize,
) ?*c.struct_keystore_mask {
    const gpa = std.heap.c_allocator;

    const wone = gpa.alloc(u8, buf_sz) catch return null;
    errdefer gpa.free(wone);
    const wtwo = gpa.alloc(u8, buf_sz) catch {
        gpa.free(wone);
        return null;
    };

    @memset(wone, 0);
    @memset(wtwo, 0);

    // Generate a random 64-bit challenge; write sequential values into both buffers.
    var chg: u64 = 0;
    arcan_random(@as([*]u8, @ptrCast(&chg)), 8);
    pack_u64(chg, wone[8..].ptr);
    pack_u64(chg +% 1, wtwo[8..].ptr);

    var pos: usize = header_size;

    // On first call with empty mask, populate from the keystore.
    if (tail.tag == null and head == tail)
        _ = a12helper_keystore_public_tagset(tail);

    var cur: ?*c.struct_keystore_mask = tail;

    // For each key: H(chg_n || kpub) → beacon slot.
    while (cur) |entry| {
        if (entry.tag == null or pos >= buf_sz) break;

        var temp: Blake3Hasher = undefined;

        blake3_hasher_init(&temp);
        blake3_hasher_update(&temp, &wone[8], 8);
        blake3_hasher_update(&temp, &entry.pubk, beacon_member_size);
        blake3_hasher_finalize(&temp, wone[pos..].ptr, beacon_member_size);

        blake3_hasher_init(&temp);
        blake3_hasher_update(&temp, &wtwo[8], 8);
        blake3_hasher_update(&temp, &entry.pubk, beacon_member_size);
        blake3_hasher_finalize(&temp, wtwo[pos..].ptr, beacon_member_size);

        cur = entry.next;
        pos += beacon_member_size;
    }

    // Prepend checksum: H(chg || keys) → first 8 bytes.
    var temp: Blake3Hasher = undefined;
    blake3_hasher_init(&temp);
    blake3_hasher_update(&temp, wone[8..].ptr, pos - 8);
    blake3_hasher_finalize(&temp, wone.ptr, 8);

    blake3_hasher_init(&temp);
    blake3_hasher_update(&temp, wtwo[8..].ptr, pos - 8);
    blake3_hasher_finalize(&temp, wtwo.ptr, 8);

    outsz.* = pos;
    one.* = wone.ptr;
    two.* = wtwo.ptr;

    return cur;
}

// compare_addr_ipv4

/// Return true when the ancillary CMSG data in `mh` shows that the packet
/// arrived on the same interface as `addr` — used to skip our own looped-back
/// broadcasts.
fn cmsgAlign(len: usize) usize {
    const sz = @sizeOf(usize);
    return (len + sz - 1) & ~@as(usize, sz - 1);
}

fn compareAddrIpv4(mh: *c.struct_msghdr, addr: c.struct_in_addr) bool {
    if (mh.msg_controllen < @sizeOf(c.struct_cmsghdr)) return false;
    var cursor: [*]u8 = @ptrCast(@alignCast(mh.msg_control));
    const ctl_end = cursor + mh.msg_controllen;
    while (@intFromPtr(cursor) + @sizeOf(c.struct_cmsghdr) <= @intFromPtr(ctl_end)) {
        const msg: *c.struct_cmsghdr = @ptrCast(@alignCast(cursor));
        if (msg.cmsg_len < @sizeOf(c.struct_cmsghdr)) break;
        if (msg.cmsg_level == c.IPPROTO_IP and msg.cmsg_type == c.IP_PKTINFO) {
            const info: *c.struct_in_pktinfo = @ptrCast(@alignCast(cursor + @sizeOf(c.struct_cmsghdr)));
            if (addr.s_addr == info.ipi_spec_dst.s_addr)
                return true;
        }
        cursor += cmsgAlign(msg.cmsg_len);
    }
    return false;
}

// a12helper_listen_beacon

/// Poll `O.IP.sock` for beacon packets, maintain two-slot state per sender
/// address, and fire callbacks on validated beacons.
///
/// Blocks until `poll` is interrupted by a signal (EINTR → clean exit) or
/// `on_shmif` returns false.
///
/// Exported with C ABI as `a12helper_listen_beacon`.
pub export fn a12helper_listen_beacon(
    shmif_C: [*c]c.struct_arcan_shmif_cont,
    O: [*c]c.struct_anet_discover_opts,
    on_beacon: ?OnBeaconFn,
    on_unknown: ?OnUnknownFn,
    on_shmif: ?OnShmifFn,
) void {
    if (known_beacons == null) {
        known_beacons = BeaconMap.init(std.heap.c_allocator);
    }

    const opts: *c.struct_anet_discover_opts = O orelse return;
    const ip_cfg: *IpCfg = @ptrCast(@alignCast(opts.IP));
    const gpa = std.heap.c_allocator;

    var mtu: [mtu_size]u8 = undefined;

    while (true) {
        const epipe: c_int = if (shmif_C != null) shmif_C.*.epipe else -1;
        var ps = [2]c.struct_pollfd{
            .{ .fd = ip_cfg.sock, .events = c.POLLIN | c.POLLERR | c.POLLHUP, .revents = 0 },
            .{ .fd = epipe, .events = c.POLLIN | c.POLLERR | c.POLLHUP, .revents = 0 },
        };

        if (c.poll(&ps, 2, -1) == -1) {
            // EINTR = signal fired; treat as graceful shutdown.
            if (std.c._errno().* != c.EINTR) continue;
            break;
        }

        // UDP packet received
        if (ps[0].revents != 0) {
            var sender_addr: c.struct_sockaddr = std.mem.zeroes(c.struct_sockaddr);
            const sender_len: c.socklen_t = @sizeOf(c.struct_sockaddr);
            var ctrl: [256]u8 = std.mem.zeroes([256]u8);
            var iov = c.struct_iovec{ .iov_base = &mtu, .iov_len = mtu_size };
            var mh = c.struct_msghdr{
                .msg_name = &sender_addr,
                .msg_namelen = sender_len,
                .msg_control = &ctrl,
                .msg_controllen = ctrl.len,
                .msg_iov = &iov,
                .msg_iovlen = 1,
                .msg_flags = 0,
            };

            const nr = c.recvmsg(ip_cfg.sock, &mh, c.MSG_DONTWAIT);
            // Minimum: chk(8) + chg(8) + one full key entry.
            const min_size: isize = @intCast(header_size + beacon_member_size);
            if (nr < min_size) continue;

            // Resolve sender address to a printable string (used as hashmap key).
            var name_buf: [c.INET6_ADDRSTRLEN]u8 = std.mem.zeroes([c.INET6_ADDRSTRLEN]u8);
            if (c.getnameinfo(
                @ptrCast(&sender_addr),
                sender_len,
                &name_buf,
                name_buf.len,
                null,
                0,
                c.NI_NUMERICHOST | c.NI_NUMERICSERV,
            ) != 0) continue;

            const name_len: u32 = @intCast(
                std.mem.indexOfScalar(u8, &name_buf, 0) orelse name_buf.len,
            );

            // Skip packets that arrived from our own interface (looped broadcast).
            if (sender_addr.sa_family == c.AF_INET) {
                const v4: *c.struct_sockaddr_in = @ptrCast(@alignCast(&sender_addr));
                if (compareAddrIpv4(&mh, v4.sin_addr)) continue;
            }
            // IPv6 self-filter via IPV6_RECVPKTINFO is not yet implemented.

            const pkt = mtu[0..@intCast(nr)];
            const name_slice = name_buf[0..name_len];
            const existing = known_beacons.?.get(name_slice);

            if (existing == null) {
                // First packet from this sender: cache and wait for the second.
                const bcn = gpa.create(Beacon) catch continue;
                bcn.* = Beacon{};
                _ = unpackBeacon(bcn, 0, pkt);
                const owned_key = gpa.dupe(u8, name_slice) catch {
                    gpa.destroy(bcn);
                    continue;
                };
                known_beacons.?.put(owned_key, bcn) catch {
                    gpa.free(owned_key);
                    gpa.destroy(bcn);
                };
            } else {
                const bcn: *Beacon = existing.?;
                const result = unpackBeacon(bcn, 1, pkt);

                switch (result.status) {
                    -1 => {
                        // Hard integrity failure: log and discard the pair.
                        std.debug.print("beacon_fail:source={s}:reason={s}\n", .{
                            name_buf[0..name_len],
                            result.err orelse "unknown",
                        });
                    },
                    -2 => {
                        // Sequence mismatch: slide slot[1] to slot[0] and keep waiting.
                        bcn.slot[0] = bcn.slot[1];
                        continue;
                    },
                    0 => {
                        // Graceful path: first-slot-only result; fire with null pubkey.
                        const null_key = [_]u8{0} ** 32;
                        if (on_beacon) |cb|
                            _ = cb(shmif_C, &null_key, bcn.slot[0].chg(), null, &name_buf);
                    },
                    else => {
                        // Fully validated pair: dispatch each key entry to the keystore.
                        var i: usize = 0;
                        while (i < bcn.slot[0].len) : (i += beacon_member_size) {
                            const key_ptr: [*]const u8 = bcn.slot[0].keys()[i..].ptr;
                            if (on_beacon) |cb| {
                                if (!a12helper_keystore_known_accepted_challenge(
                                    key_ptr,
                                    bcn.slot[0].chg(),
                                    cb,
                                    shmif_C,
                                    &name_buf,
                                )) {
                                    if (on_unknown) |ucb| ucb(&name_buf);
                                }
                            }
                        }
                    },
                }

                gpa.destroy(bcn);
                if (known_beacons.?.fetchRemove(name_slice)) |kv| {
                    gpa.free(kv.key);
                }
            }
        }

        // shmif event
        if (shmif_C) |ctx| {
            if (ps[1].revents != 0) {
                if (on_shmif) |cb| {
                    if (!cb(ctx)) return;
                }
            }
        }
    }
}

// build_ipv6

fn buildIpv6(cfg: *c.struct_anet_discover_opts, _broadcast: bool) IpCfg {
    _ = _broadcast;
    var res = IpCfg.zero();
    res.ipv6 = true;
    res.addr_sz = @sizeOf(c.struct_sockaddr_in6);

    const s = c.socket(c.AF_INET6, c.SOCK_DGRAM, c.IPPROTO_UDP);
    if (s == -1) {
        res.err = "couldn't build ipv6 socket";
        return res;
    }

    const on: c_int = 1;
    if (c.setsockopt(s, c.SOL_SOCKET, c.SO_REUSEADDR, &on, @sizeOf(c_int)) == -1) {
        _ = c.close(s);
        res.err = "sockopt.reuseaddr rejected";
        return res;
    }

    const hops: c_int = 255;
    if (c.setsockopt(s, c.IPPROTO_IPV6, c.IPV6_MULTICAST_HOPS, &hops, @sizeOf(c_int)) == -1) {
        _ = c.close(s);
        res.err = "sockopt.n_hops rejected";
        return res;
    }

    if (c.setsockopt(s, c.IPPROTO_IPV6, c.IPV6_MULTICAST_LOOP, &on, @sizeOf(c_int)) == -1) {
        _ = c.close(s);
        res.err = "sockopt.loop rejected";
        return res;
    }

    // Parse the multicast group address string from cfg.
    const ipv6_str: [*:0]const u8 = cfg.ipv6 orelse {
        _ = c.close(s);
        res.err = "ipv6.multicast_addr missing";
        return res;
    };

    res.addr.v6 = std.mem.zeroes(c.struct_sockaddr_in6);
    res.addr.v6.sin6_family = c.AF_INET6;
    res.addr.v6.sin6_port = beacon_port;

    if (c.inet_pton(c.AF_INET6, ipv6_str, &res.addr.v6.sin6_addr) != 1) {
        _ = c.close(s);
        res.err = "ipv6.multicast_addr invalid";
        return res;
    }

    var mreq = c.struct_ipv6_mreq{
        .ipv6mr_multiaddr = res.addr.v6.sin6_addr,
        .ipv6mr_interface = 0,
    };
    if (c.setsockopt(s, c.IPPROTO_IPV6, c.IPV6_JOIN_GROUP, &mreq, @sizeOf(c.struct_ipv6_mreq)) != 0) {
        _ = c.close(s);
        res.err = "sockopt.join_mcast rejected";
        return res;
    }

    if (c.bind(s, @ptrCast(&res.addr.base), @intCast(res.addr_sz)) == -1) {
        _ = c.close(s);
        res.err = "ipv6.bind rejected";
        return res;
    }

    res.sock = s;
    return res;
}

// build_ipv4

fn buildIpv4(_cfg: *c.struct_anet_discover_opts, broadcast: bool) IpCfg {
    _ = _cfg;
    var res = IpCfg.zero();
    res.addr_sz = @sizeOf(c.struct_sockaddr_in);
    res.sock = c.socket(c.AF_INET, c.SOCK_DGRAM, c.IPPROTO_UDP);

    if (res.sock == -1) {
        res.err = "couldn't build ipv4 socket";
        return res;
    }

    const on: c_int = 1;
    if (c.setsockopt(res.sock, c.SOL_SOCKET, c.SO_BROADCAST, &on, @sizeOf(c_int)) != 0) {
        _ = c.close(res.sock);
        res.err = "sockopt.broadcast rejected";
        res.sock = -1;
        return res;
    }

    // Request ancillary destination-address information (for loopback filtering).
    _ = c.setsockopt(res.sock, c.IPPROTO_IP, c.IP_PKTINFO, &on, @sizeOf(c_int));
    _ = c.setsockopt(res.sock, c.SOL_SOCKET, c.SO_REUSEADDR, &on, @sizeOf(c_int));

    if (c.setsockopt(res.sock, c.IPPROTO_IP, c.IP_MULTICAST_LOOP, &on, @sizeOf(c_int)) != 0) {
        _ = c.close(res.sock);
        res.err = "sockopt.multicast_loop rejected";
        res.sock = -1;
        return res;
    }

    res.addr.v4 = std.mem.zeroes(c.struct_sockaddr_in);
    res.addr.v4.sin_family = c.AF_INET;
    res.addr.v4.sin_port = c.htons(beacon_port);
    if (broadcast) {
        res.addr.v4.sin_addr.s_addr = c.htonl(c.INADDR_BROADCAST);
    } else {
        res.addr.v4.sin_addr.s_addr = c.htons(c.INADDR_ANY);
    }

    if (c.bind(res.sock, @ptrCast(&res.addr.base), @intCast(res.addr_sz)) == -1) {
        // Log but do not close — the C original also only sets .err and returns.
        res.err = "ipv4.bind rejected";
    }

    return res;
}

// a12helper_discover_ipcfg

/// Configure the UDP socket described by `cfg`.  When `beacon` is true the
/// socket is set up for sending (broadcast/multicast target); when false it is
/// bound for receiving.
///
/// On success, allocates an `IpCfg` on the C heap, stores the pointer in
/// `cfg.IP`, and returns null.  On failure returns a static error string.
///
/// Exported with C ABI as `a12helper_discover_ipcfg`.
pub export fn a12helper_discover_ipcfg(
    cfg: *c.struct_anet_discover_opts,
    beacon: bool,
) ?[*:0]const u8 {
    const ip: IpCfg = if (cfg.ipv6 != null)
        buildIpv6(cfg, beacon)
    else
        buildIpv4(cfg, beacon);

    if (ip.err) |err| return err;

    const gpa = std.heap.c_allocator;
    const heap_cfg = gpa.create(IpCfg) catch return "out of memory";
    heap_cfg.* = ip;
    cfg.IP = @ptrCast(heap_cfg);
    return null;
}

// anet_discover_send_beacon

/// Build and transmit one beacon pair.  Sends packet one, waits 1 second,
/// then sends packet two.  On an empty keyset the function sleeps
/// `cfg.timesleep` seconds and returns true to signal the caller to loop.
/// Returns false only on a hard send error.
///
/// Exported with C ABI as `anet_discover_send_beacon`.
pub export fn anet_discover_send_beacon(cfg: *c.struct_anet_discover_opts) bool {
    const ip_cfg: *IpCfg = @ptrCast(@alignCast(cfg.IP));
    if (ip_cfg.sock <= 0) return false;

    var mask = std.mem.zeroes(c.struct_keystore_mask);
    var cur: ?*c.struct_keystore_mask = &mask;

    var size: usize = undefined;
    var one_ptr: [*]u8 = undefined;
    var two_ptr: [*]u8 = undefined;

    cur = a12helper_build_beacon(&mask, cur.?, &one_ptr, &two_ptr, &size);

    const gpa = std.heap.c_allocator;

    if (size <= header_size) {
        // Nothing to send: release allocations and keystore chain, then backoff.
        gpa.free(one_ptr[0..buf_sz]);
        gpa.free(two_ptr[0..buf_sz]);

        var tmp: [*c]c.struct_keystore_mask = mask.next;
        while (tmp != null) {
            const node: *c.struct_keystore_mask = @ptrCast(tmp);
            // tag memory is owned by the keystore; do not free.
            const next = node.next;
            gpa.destroy(node);
            tmp = next;
        }

        _ = c.sleep(@intCast(cfg.timesleep));
        return true;
    }

    // Send first beacon packet.
    const sent1 = c.sendto(
        ip_cfg.sock,
        one_ptr,
        size,
        0,
        @ptrCast(&ip_cfg.addr.base),
        @intCast(ip_cfg.addr_sz),
    );
    if (@as(usize, @bitCast(sent1)) != size) {
        std.debug.print("couldn't send beacon: {s}\n", .{strerror(std.c._errno().*)});
        gpa.free(one_ptr[0..buf_sz]);
        gpa.free(two_ptr[0..buf_sz]);
        return false;
    }

    // The 1-second gap is required for the receiver's liveness proof check.
    _ = c.sleep(1);

    _ = c.sendto(
        ip_cfg.sock,
        two_ptr,
        size,
        0,
        @ptrCast(&ip_cfg.addr.base),
        @intCast(ip_cfg.addr_sz),
    );

    gpa.free(one_ptr[0..buf_sz]);
    gpa.free(two_ptr[0..buf_sz]);
    return true;
}

// anet_discover_listen_beacon

/// Validate the socket and enter the beacon-receive poll loop.
/// Dead code after `a12helper_listen_beacon` in the C source (the second bind
/// and listen call) is intentionally omitted.
///
/// Exported with C ABI as `anet_discover_listen_beacon`.
pub export fn anet_discover_listen_beacon(cfg: *c.struct_anet_discover_opts) void {
    const ip_cfg: *IpCfg = @ptrCast(@alignCast(cfg.IP));
    if (ip_cfg.sock <= 0) {
        std.debug.print("_listen(cfg) - config missing socket\n", .{});
        return;
    }

    a12helper_listen_beacon(
        cfg.C,
        cfg,
        @ptrCast(@alignCast(cfg.discover_beacon)),
        @ptrCast(@alignCast(cfg.discover_unknown)),
        @ptrCast(@alignCast(cfg.on_shmif)),
    );
}
