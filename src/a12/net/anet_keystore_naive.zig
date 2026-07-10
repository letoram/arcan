// Zig port of frameserver/util/anet_keystore_naive.c — file-based keystore
// Copyright: Bjorn Stahl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com
//
// Compile-time flags mirrored:
//   WANT_KEYSTORE_HASHER — enables blake3-based known-accepted-challenge

const std = @import("std");
const shmif = @import("shmif_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    pub const closedir = libc.closedir;
    pub const DT_REG = libc.DT_REG;
    pub const dup = libc.dup;
    pub const fclose = libc.fclose;
    pub const fdopen = libc.fdopen;
    pub const fdopendir = libc.fdopendir;
    pub const fgets = libc.fgets;
    pub const flock = libc.flock;
    pub const fprintf = libc.fprintf;
    pub const free = libc.free;
    pub const ftruncate = libc.ftruncate;
    pub const getline = libc.getline;
    pub const LOCK_EX = libc.LOCK_EX;
    pub const LOCK_UN = libc.LOCK_UN;
    pub const lseek = libc.lseek;
    pub const mkdirat = libc.mkdirat;
    pub const mkstemp = libc.mkstemp;
    pub const O_CLOEXEC = libc.O_CLOEXEC;
    pub const O_CREAT = libc.O_CREAT;
    pub const O_DIRECTORY = libc.O_DIRECTORY;
    pub const O_EXCL = libc.O_EXCL;
    pub const open = libc.open;
    pub const openat = libc.openat;
    pub const O_RDONLY = libc.O_RDONLY;
    pub const O_RDWR = libc.O_RDWR;
    pub const O_WRONLY = libc.O_WRONLY;
    pub const readdir = libc.readdir;
    pub const SEEK_END = libc.SEEK_END;
    pub const SEEK_SET = libc.SEEK_SET;
    pub const S_IRUSR = libc.S_IRUSR;
    pub const S_IRWXU = libc.S_IRWXU;
    pub const S_IWUSR = libc.S_IWUSR;
    pub const STDERR_FILENO = libc.STDERR_FILENO;
    pub const struct_dirent = libc.struct_dirent;
    pub const unlink = libc.unlink;
    pub const unlinkat = libc.unlinkat;

    pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
    pub const A12HELPER_PROVIDER_BASEDIR = anet.A12HELPER_PROVIDER_BASEDIR;
    pub const struct_keystore_provider = anet.struct_keystore_provider;
};

// x25519 key operations (from external/x25519.c, linked separately)
extern "c" fn x25519_private_key(privk: *[32]u8) void;
extern "c" fn x25519_public_key(privk: *const [32]u8, pubk: *[32]u8) void;

// ed25519 from monocypher
extern "c" fn crypto_ed25519_key_pair(privk: *[64]u8, pubk: *[32]u8, seed: *const [32]u8) void;

// arcan_random provided by the arcan platform layer
extern "c" fn arcan_random(dst: [*]u8, sz: usize) void;

// Base64 LUTs

const b64enc_lut = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef" ++
    "ghijklmnopqrstuvwxyz0123456789+/";

const b64dec_lut = blk: {
    var t = [_]u8{0} ** 256;
    const enc = b64enc_lut;
    for (enc, 0..) |ch, i| t[ch] = @intCast(i);
    break :blk t;
};

// Public base64 helpers

pub export fn a12helper_tob64(
    data: [*]const u8, inl: usize, outl: *usize) ?[*]u8
{
    const mlen = inl % 3;
    const pad: usize = if (mlen == 1) 2 else if (mlen == 2) 1 else 0;
    outl.* = (inl * 4) / 3 + pad + 2;

    const res = std.heap.c_allocator.alloc(u8, outl.*) catch return null;
    var wrk: usize = 0;
    var ofs: usize = 0;

    while (ofs < inl - mlen) : (ofs += 3) {
        const val: u32 = (@as(u32, data[ofs]) << 16) +
                         (@as(u32, data[ofs+1]) << 8) +
                          @as(u32, data[ofs+2]);
        res[wrk+0] = b64enc_lut[(val >> 18) & 63];
        res[wrk+1] = b64enc_lut[(val >> 12) & 63];
        res[wrk+2] = b64enc_lut[(val >>  6) & 63];
        res[wrk+3] = b64enc_lut[(val >>  0) & 63];
        wrk += 4;
    }

    if (pad == 2) {
        res[wrk+0] = b64enc_lut[data[ofs] >> 2];
        res[wrk+1] = b64enc_lut[(data[ofs] & 3) << 4];
        res[wrk+2] = '=';
        res[wrk+3] = '=';
        wrk += 4;
    } else if (pad == 1) {
        res[wrk+0] = b64enc_lut[data[ofs] >> 2];
        res[wrk+1] = b64enc_lut[((data[ofs] & 3) << 4) + (data[ofs+1] >> 4)];
        res[wrk+2] = b64enc_lut[(data[ofs+1] & 15) << 2];
        res[wrk+3] = '=';
        wrk += 4;
    }
    res[wrk] = 0;
    return res.ptr;
}

pub export fn a12helper_fromb64(
    instr: [*:0]const u8, lim: usize, outb: [*]u8) bool
{
    const inlen = std.mem.len(instr);
    if (inlen % 4 != 0 or inlen < 2) return false;

    var len: usize = inlen / 4 * 3;
    if (instr[inlen - 1] == '=') len -= 1;
    if (instr[inlen - 2] == '=') len -= 1;
    if (len > lim) return false;

    var j: usize = 0;
    var i: usize = 0;
    while (i < inlen) : (i += 4) {
        const v0: u32 = if (instr[i+0] == '=') 0 else @as(u32, b64dec_lut[instr[i+0]]);
        const v1: u32 = if (instr[i+1] == '=') 0 else @as(u32, b64dec_lut[instr[i+1]]);
        const v2: u32 = if (instr[i+2] == '=') 0 else @as(u32, b64dec_lut[instr[i+2]]);
        const v3: u32 = if (instr[i+3] == '=') 0 else @as(u32, b64dec_lut[instr[i+3]]);
        const val: u32 = (v0 << 18) + (v1 << 12) + (v2 << 6) + v3;

        if (j < len) { outb[j] = @truncate(val >> 16); j += 1; }
        if (j < len) { outb[j] = @truncate(val >>  8); j += 1; }
        if (j < len) { outb[j] = @truncate(val);       j += 1; }
    }
    return j >= lim;
}

// Key entry linked list

const KeyEnt = struct {
    key: [32]u8,
    host: ?[*:0]u8,
    port: usize,
    fn_name: ?[*:0]u8,
    ephem_id: ?[*:0]u8,
    chg: [8]u8,
    pub_chg: [32]u8,
    empty: bool,
    next: ?*KeyEnt,
};

fn alloc_key_ent(key: *const [32]u8) ?*KeyEnt {
    const res = std.heap.c_allocator.create(KeyEnt) catch return null;
    res.* = .{
        .key       = key.*,
        .host      = null,
        .port      = 0,
        .fn_name   = null,
        .ephem_id  = null,
        .chg       = std.mem.zeroes([8]u8),
        .pub_chg   = std.mem.zeroes([32]u8),
        .empty     = false,
        .next      = null,
    };
    return res;
}

fn free_key_ent(ent: *KeyEnt) void {
    const alloc = std.heap.c_allocator;
    if (ent.host)     |h| alloc.free(std.mem.span(h));
    if (ent.fn_name)  |f| alloc.free(std.mem.span(f));
    if (ent.ephem_id) |e| alloc.free(std.mem.span(e));
    alloc.destroy(ent);
}

// Keystore global state

const KeystoreState = struct {
    hosts: ?*KeyEnt = null,
    dirfd_private:  c_int = -1,
    dirfd_accepted: c_int = -1,
    dirfd_state:    c_int = -1,
    dirfd_sig:      c_int = -1,
    open: bool = false,
    provider: c.struct_keystore_provider = std.mem.zeroes(c.struct_keystore_provider),
};

var keystore = KeystoreState{};

// Internal helpers

fn flush_accepted_keys() void {
    var cur = keystore.hosts;
    while (cur) |ent| {
        const next = ent.next;
        @memset(std.mem.asBytes(ent), 0);
        std.heap.c_allocator.destroy(ent);
        cur = next;
    }
    keystore.hosts = null;
}

/// Parse a keystore line: "host[:port] <b64key>"
/// Returns false if malformed.
fn decode_hostline(buf: []u8, endofs: usize,
    outhost: *?[*:0]u8, key: *[32]u8) bool
{
    // Trim trailing whitespace from [0..endofs]
    var end: usize = endofs;
    while (end > 0 and std.ascii.isWhitespace(buf[end - 1])) : (end -= 1) {
        buf[end - 1] = 0;
    }

    // Split on first whitespace: host then key
    var split: usize = 0;
    while (split < end and !std.ascii.isWhitespace(buf[split])) : (split += 1) {}
    if (split == 0 or split >= end) return false;

    buf[split] = 0;
    split += 1;

    // Trim leading whitespace on key part
    while (split < end and std.ascii.isWhitespace(buf[split])) : (split += 1) {}
    // Trim trailing whitespace on key part
    var kend: usize = end;
    while (kend > split and std.ascii.isWhitespace(buf[kend - 1])) : (kend -= 1) {
        buf[kend - 1] = 0;
    }

    outhost.* = @ptrCast(buf.ptr);
    // Ensure a null terminator at buf[kend] so the cast to [*:0]const u8
    // doesn't make fromb64's std.mem.len scan past the line (e.g. into the
    // trailing '\n' or arbitrary getline-allocator slack), which would
    // yield a non-multiple-of-4 length and reject otherwise-valid keys.
    if (kend < buf.len) buf[kend] = 0;
    const key_slice: [*:0]const u8 = @ptrCast(buf[split..kend].ptr);
    return a12helper_fromb64(key_slice, 32, key);
}

fn load_accepted_keys() void {
    flush_accepted_keys();

    const tmpdfd = std.posix.dup(keystore.dirfd_accepted) catch return;
    const dir = c.fdopendir(tmpdfd);
    if (dir == null) {
        std.posix.close(tmpdfd);
        return;
    }
    defer _ = c.closedir(dir);

    var host_pp: *?*KeyEnt = &keystore.hosts;

    while (c.readdir(dir)) |ent_raw| {
        const ent: *c.struct_dirent = @ptrCast(ent_raw);
        const dname: [*:0]const u8 = @ptrCast(&ent.d_name);
        const fd = c.openat(keystore.dirfd_accepted, dname,
            c.O_RDONLY | c.O_CLOEXEC);
        if (fd == -1) continue;

        const f = c.fdopen(fd, "r");
        if (f == null) { _ = std.posix.close(@intCast(fd)); continue; }
        defer _ = c.fclose(f);

        var inbuf: ?[*]u8 = null;
        var inlen: usize = 0;
        const nr = c.getline(&inbuf, &inlen, f);
        defer if (inbuf) |b| c.free(b);
        if (nr <= 0 or inlen == 0) continue;

        const line = inbuf.?[0..@as(usize, @intCast(nr))];
        var hoststr: ?[*:0]u8 = null;
        var key: [32]u8 = undefined;
        if (!decode_hostline(line, @as(usize, @intCast(nr)) - 1, &hoststr, &key)) {
            std.debug.print("keystore_naive(): failed to parse {s}\n", .{dname});
            continue;
        }

        const node = alloc_key_ent(&key) orelse continue;
        if (hoststr) |h| {
            const hs = std.mem.span(h);
            node.host = (std.heap.c_allocator.dupeZ(u8, hs) catch null);
        }
        const dns = std.mem.span(dname);
        node.fn_name = (std.heap.c_allocator.dupeZ(u8, dns) catch null);

        host_pp.* = node;
        host_pp = &node.next;
    }
}

fn gen_fn(buf: []u8) void {
    arcan_random(buf.ptr, buf.len);
    for (buf) |*b| b.* = 'a' + (b.* % 21);
}

// Exported keystore API

pub export fn a12helper_keystore_open(p: ?*c.struct_keystore_provider) bool {
    if (p == null) return false;
    if (keystore.open) {
        return std.mem.eql(u8,
            std.mem.asBytes(p.?),
            std.mem.asBytes(&keystore.provider));
    }
    keystore.provider = p.?.*;
    if (keystore.provider.type != c.A12HELPER_PROVIDER_BASEDIR) return false;
    if (keystore.provider.unnamed_0.directory.dirfd < c.STDERR_FILENO) return false;

    const basefd = keystore.provider.unnamed_0.directory.dirfd;
    _ = c.mkdirat(basefd, "accepted", c.S_IRWXU);
    _ = c.mkdirat(basefd, "hostkeys", c.S_IRWXU);
    _ = c.mkdirat(basefd, "state",    c.S_IRWXU);
    _ = c.mkdirat(basefd, "signing",  c.S_IRWXU);

    const fl = c.O_DIRECTORY | c.O_CLOEXEC;
    keystore.dirfd_accepted = c.openat(basefd, "accepted", fl);
    if (keystore.dirfd_accepted == -1) {
        _ = std.posix.close(basefd);
        keystore.provider.unnamed_0.directory.dirfd = -1;
        return false;
    }

    keystore.dirfd_private = c.openat(basefd, "hostkeys", fl);
    if (keystore.dirfd_private == -1) {
        _ = std.posix.close(keystore.dirfd_accepted);
        keystore.dirfd_accepted = -1;
        _ = std.posix.close(basefd);
        keystore.provider.unnamed_0.directory.dirfd = -1;
        return false;
    }

    keystore.dirfd_sig   = c.openat(basefd, "signing", fl);
    keystore.dirfd_state = c.openat(basefd, "state",   fl);

    load_accepted_keys();
    keystore.open = true;
    return true;
}

pub export fn a12helper_keystore_release() bool {
    if (!keystore.open) return false;
    _ = std.posix.close(keystore.provider.unnamed_0.directory.dirfd);
    _ = std.posix.close(keystore.dirfd_accepted);
    _ = std.posix.close(keystore.dirfd_private);
    if (keystore.dirfd_state != -1) _ = std.posix.close(keystore.dirfd_state);
    if (keystore.dirfd_sig   != -1) _ = std.posix.close(keystore.dirfd_sig);
    keystore.provider.unnamed_0.directory.dirfd = -1;
    keystore.dirfd_accepted = -1;
    keystore.dirfd_private  = -1;
    keystore.dirfd_state    = -1;
    keystore.dirfd_sig      = -1;
    keystore.open = false;
    flush_accepted_keys();
    return true;
}

pub export fn a12helper_keystore_accept(
    pubk: *const [32]u8, connp: ?[*:0]const u8) bool
{
    if (!keystore.open) return false;

    var tmpfn: [9]u8 = std.mem.zeroes([9]u8);
    var fdout: c_int = -1;
    while (true) {
        gen_fn(tmpfn[0..8]);
        tmpfn[8] = 0;
        fdout = c.openat(keystore.dirfd_accepted,
            @as([*:0]const u8, @ptrCast(&tmpfn)),
            c.O_CREAT | c.O_EXCL | c.O_WRONLY,
            c.S_IRUSR | c.S_IWUSR);
        if (fdout >= 0) break;
    }

    const f = c.fdopen(fdout, "w");
    if (f == null) return false;
    defer _ = c.fclose(f);

    const cp: [*:0]const u8 = connp orelse "outbound";
    var outl: usize = 0;
    const buf = a12helper_tob64(pubk, 32, &outl) orelse {
        _ = c.unlinkat(keystore.dirfd_accepted,
            @as([*:0]const u8, @ptrCast(&tmpfn)), 0);
        return false;
    };
    defer std.heap.c_allocator.free(buf[0..outl]);

    _ = c.fprintf(f, "%s %s\n", cp, buf);

    // Add to in-memory list
    var host_pp: *?*KeyEnt = &keystore.hosts;
    while (host_pp.*) |hp| host_pp = &hp.next;
    const node = alloc_key_ent(pubk) orelse return true;
    const cp_s = std.mem.span(cp);
    node.host = (std.heap.c_allocator.dupeZ(u8, cp_s) catch null);
    host_pp.* = node;
    return true;
}

pub export fn a12helper_keystore_accept_ephemeral(
    pubk: *const [32]u8, connp: [*:0]const u8, id: [*:0]const u8) void
{
    var host_pp: *?*KeyEnt = &keystore.hosts;
    while (host_pp.*) |hp| {
        if (hp.empty) {
            hp.empty = false;
            const cp_s = std.mem.span(connp);
            hp.host = (std.heap.c_allocator.dupeZ(u8, cp_s) catch null);
            const id_s = std.mem.span(id);
            hp.ephem_id = (std.heap.c_allocator.dupeZ(u8, id_s) catch null);
            return;
        }
        host_pp = &hp.next;
    }

    const node = alloc_key_ent(pubk) orelse return;
    const cp_s = std.mem.span(connp);
    node.host = (std.heap.c_allocator.dupeZ(u8, cp_s) catch null);
    host_pp.* = node;
}

pub export fn a12helper_keystore_flush_ephemeral(id: [*:0]const u8) void {
    const id_s = std.mem.span(id);
    var cur = keystore.hosts;
    while (cur) |hp| {
        if (hp.ephem_id) |ei| {
            if (std.mem.eql(u8, std.mem.span(ei), id_s)) {
                hp.empty = true;
                std.heap.c_allocator.free(std.mem.span(ei));
                hp.ephem_id = null;
            }
        }
        cur = hp.next;
    }
}

pub export fn a12helper_keystore_accepted(
    pubk: *const [32]u8, connp: ?[*:0]const u8) ?[*:0]const u8
{
    const cp = connp orelse return null;
    const cp_s = std.mem.span(cp);
    if (cp_s.len == 0) return null;

    var ent = keystore.hosts;
    while (ent) |hp| {
        if (!std.mem.eql(u8, &hp.key, pubk)) {
            ent = hp.next;
            continue;
        }
        const h_s = if (hp.host) |h| std.mem.span(h) else {
            ent = hp.next;
            continue;
        };
        if (std.mem.eql(u8, h_s, "*") or std.mem.eql(u8, cp_s, "*"))
            return hp.host;
        if (has_intersection(cp_s, h_s))
            return hp.host;
        ent = hp.next;
    }
    return null;
}

fn has_intersection(a: []const u8, b: []const u8) bool {
    var it_a = std.mem.splitScalar(u8, a, ',');
    while (it_a.next()) |ta| {
        var it_b = std.mem.splitScalar(u8, b, ',');
        while (it_b.next()) |tb| {
            if (std.mem.eql(u8, ta, tb)) return true;
        }
    }
    return false;
}

/// Parse host:port from a keyfile host entry.
/// Returns the host part (may modify `host` in place for IPv6).
fn unpack_host(host: []u8, defport: usize,
    outport: *u16, errfmt: *?[*:0]const u8) ?[]u8
{
    if (host.len == 0) {
        errfmt.* = "empty host in keyfile [%s]:%zu\n";
        return null;
    }

    // Find last ':'
    const colon = std.mem.lastIndexOfScalar(u8, host, ':');
    if (colon == null) {
        outport.* = @intCast(defport);
        return host;
    }
    const ci = colon.?;
    if (ci == 0) {
        errfmt.* = "malformed host in keyfile [%s:%zu]\n";
        return null;
    }

    // IPv6 [addr]:port detection
    if (host[ci - 1] != ']') {
        const port_s = host[ci+1..];
        const port = std.fmt.parseInt(u16, port_s, 10) catch 0;
        if (port == 0) {
            errfmt.* = "invalid port for host in keyfile [%s:%zu]\n";
            return null;
        }
        outport.* = port;
        return host[0..ci];
    }

    if (host[0] != '[') {
        errfmt.* = "malformed IPv6 notation in keyfile [%s:%zu]\n";
        return null;
    }

    const port_s = host[ci+1..];
    const port = std.fmt.parseInt(u16, port_s, 10) catch 0;
    if (port == 0) {
        errfmt.* = "invalid port for host in keyfile [%s:%zu]\n";
        return null;
    }
    outport.* = port;
    // Slide the addr left: remove leading '[' and trailing ']'
    std.mem.copyForwards(u8, host[0..], host[1..ci-1]);
    return host[0..ci-2];
}

pub export fn a12helper_keystore_hostkey(
    tagname: [*:0]const u8, index: usize,
    privk: *[32]u8, outhost: *?[*:0]u8, outport: *u16) bool
{
    if (!keystore.open) return false;
    outhost.* = null;

    const tag_s = std.mem.span(tagname);
    const fin = c.openat(keystore.dirfd_private, tagname,
        c.O_RDONLY | c.O_CLOEXEC);
    if (fin == -1) return false;

    const fpek = c.fdopen(fin, "r");
    if (fpek == null) { _ = std.posix.close(@intCast(fin)); return false; }
    defer _ = c.fclose(fpek);

    var res = false;
    var idx = index;
    var lineno: usize = 0;
    var inbuf: ?[*]u8 = null;
    var inlen: usize = 0;

    while (true) {
        const nr_signed: c_long = c.getline(&inbuf, &inlen, fpek);
        if (nr_signed == -1) break;
        lineno += 1;
        // Do NOT free inbuf between iterations — getline realloc's it in place.
        const nr: usize = @intCast(nr_signed);
        // Pass the full line including the trailing '\n' + getline's NUL
        // terminator so decode_hostline can write a NUL over the '\n' after
        // the b64 content, letting a12helper_fromb64's strlen-based parser
        // see the correct content length.
        const line = (inbuf orelse continue)[0..nr + 1];
        const line_len: usize = nr;

        var hoststr: ?[*:0]u8 = null;
        // endofs = nr (includes the trailing \n); decode_hostline's trim
        // loop converts the \n to 0 so a12helper_fromb64's strlen sees the
        // correct b64 content length.
        res = decode_hostline(line, line_len, &hoststr, privk);
        if (!res) {
            std.debug.print("bad key entry in keyfile [{s}]:{d}\n", .{ tag_s, lineno });
            continue;
        }

        var errfmt: ?[*:0]const u8 = null;
        const host_s = std.mem.span(hoststr orelse "");
        const host_mut = std.heap.c_allocator.dupe(u8, host_s) catch continue;
        defer std.heap.c_allocator.free(host_mut);

        const parsed = unpack_host(host_mut, 6680, outport, &errfmt);
        if (parsed == null) {
            std.debug.print("{s}", .{errfmt orelse "parse error\n"});
            continue;
        }

        if (idx == 0) {
            const copy = std.heap.c_allocator.dupeZ(u8, parsed.?) catch {
                res = false;
                break;
            };
            outhost.* = copy.ptr;
            res = true;
            break;
        }
        res = false;
        idx -= 1;
    }

    // getline's realloc buffer — free once after loop.
    if (inbuf) |b| c.free(b);

    if (!res) {
        if (outhost.*) |h| {
            std.heap.c_allocator.free(std.mem.span(h));
            outhost.* = null;
        }
    }
    return res and idx == 0;
}

pub export fn a12helper_keystore_register(
    tagname: [*:0]const u8, host: [*:0]const u8, port: u16,
    pubk: *[32]u8, priv: ?*[32]u8) bool
{
    if (!keystore.open) return false;

    var privk: [32]u8 = undefined;
    if (priv) |p| {
        privk = p.*;
    } else {
        x25519_private_key(&privk);
    }
    x25519_public_key(&privk, pubk);

    const fout = c.openat(keystore.dirfd_private, tagname,
        c.O_WRONLY | c.O_CREAT | c.O_CLOEXEC,
        c.S_IRUSR | c.S_IWUSR);
    if (fout == -1) {
        std.debug.print("couldn't open or create tag ({s}) for private key\n", .{tagname});
        return false;
    }

    var key_b64sz: usize = 0;
    const b64 = a12helper_tob64(&privk, 32, &key_b64sz) orelse {
        _ = std.posix.close(@intCast(fout));
        return false;
    };
    defer std.heap.c_allocator.free(b64[0..key_b64sz]);

    const host_s = std.mem.span(host);
    // a12helper_tob64 returns a NUL-terminated buffer and sets key_b64sz to
    // (content_bytes + 1). Strip the sentinel from the content slice we
    // feed to {s}; otherwise the NUL is written between the b64 key and
    // the trailing '\n' on 2nd+ entries (subsequent getline reads hit a
    // premature string terminator).
    const b64_content = std.mem.sliceTo(b64[0..key_b64sz], 0);
    const line = std.fmt.allocPrint(std.heap.c_allocator,
        "{s}:{d} {s}\n", .{ host_s, port, b64_content }) catch {
        _ = std.posix.close(@intCast(fout));
        return false;
    };
    defer std.heap.c_allocator.free(line);

    // Exclusive lock, seek to end, append
    if (c.flock(fout, c.LOCK_EX) == -1) {
        std.debug.print("couldn't lock keystore for writing\n", .{});
        _ = std.posix.close(@intCast(fout));
        return false;
    }
    defer _ = c.flock(fout, c.LOCK_UN);

    const base_pos = c.lseek(fout, 0, c.SEEK_END);
    var out_pos: usize = 0;
    var write_ok = true;
    while (out_pos < line.len) {
        const nw = std.posix.write(@intCast(fout), line[out_pos..line.len]) catch |err| {
            if (err == error.Interrupted) continue;
            _ = c.ftruncate(fout, base_pos);
            std.debug.print("failed to write new key entry\n", .{});
            write_ok = false;
            break;
        };
        out_pos += nw;
    }
    _ = std.posix.close(@intCast(fout));
    return write_ok;
}

pub export fn a12helper_keystore_tags(
    cb: ?*const fn ([*c]const u8, ?*anyopaque) callconv(.c) bool,
    tag: ?*anyopaque) bool
{
    const callback = cb orelse return false;

    const tmpdfd = std.posix.dup(keystore.dirfd_private) catch {
        _ = callback(null, tag);
        return false;
    };
    const dir = c.fdopendir(tmpdfd);
    if (dir == null) {
        _ = std.posix.close(tmpdfd);
        _ = callback(null, tag);
        return false;
    }
    defer _ = c.closedir(dir);

    while (c.readdir(dir)) |dent_raw| {
        const dent: *c.struct_dirent = @ptrCast(dent_raw);
        if (dent.d_type == c.DT_REG) {
            const dname: [*:0]const u8 = @ptrCast(&dent.d_name);
            if (std.mem.eql(u8, std.mem.span(dname), "default")) continue;
            if (!callback(dname, tag)) break;
        }
    }
    _ = callback(null, tag);
    return true;
}

pub export fn a12helper_keystore_enumerate(ref: *usize, pubk: *[32]u8) bool {
    if (keystore.dirfd_state == -1) return false;

    if (ref.* == 0) {
        ref.* = @intFromPtr(keystore.hosts);
        if (keystore.hosts) |h| {
            pubk.* = h.key;
            return true;
        }
        return false;
    }

    const ent: *KeyEnt = @ptrFromInt(ref.*);
    const next = ent.next orelse return false;
    pubk.* = next.key;
    ref.* = @intFromPtr(next);
    return true;
}

pub export fn a12helper_keystore_get_sigkey(
    tag: [*:0]const u8, pubk: *[32]u8, privk: *[64]u8) bool
{
    if (keystore.dirfd_sig == -1) return false;

    const inf = c.openat(keystore.dirfd_sig, tag, c.O_RDONLY);
    if (inf == -1) return false;

    const fin = c.fdopen(inf, "r");
    if (fin == null) { _ = std.posix.close(@intCast(inf)); return false; }
    defer _ = c.fclose(fin);

    var priv_raw: [128]u8 = undefined;
    if (c.fgets(&priv_raw, 128, fin) == null) return false;
    const slen = std.mem.len(@as([*:0]u8, @ptrCast(&priv_raw)));
    if (slen == 0 or priv_raw[slen-1] != '\n') return false;
    priv_raw[slen-1] = 0;

    if (!a12helper_fromb64(@ptrCast(&priv_raw), 64, privk)) return false;

    var pub_raw: [128]u8 = undefined;
    if (c.fgets(&pub_raw, 128, fin) == null) {
        @memset(privk, 0);
        return false;
    }
    const plen = std.mem.len(@as([*:0]u8, @ptrCast(&pub_raw)));
    if (plen == 0 or pub_raw[plen-1] != '\n') {
        @memset(privk, 0);
        return false;
    }
    pub_raw[plen-1] = 0;

    if (!a12helper_fromb64(@ptrCast(&pub_raw), 32, pubk)) {
        @memset(privk, 0);
        return false;
    }
    return true;
}

pub export fn a12helper_keystore_gen_sigkey(tag: [*:0]const u8, overwrite: bool) bool {
    if (keystore.dirfd_sig == -1) return false;

    const sfd_check = c.openat(keystore.dirfd_sig, tag, c.O_RDONLY);
    if (sfd_check != -1) {
        _ = std.posix.close(@intCast(sfd_check));
        if (!overwrite) return false;
    }

    var seed: [32]u8 = undefined;
    arcan_random(&seed, 32);

    var kpriv: [64]u8 = undefined;
    var kpub: [32]u8 = undefined;
    crypto_ed25519_key_pair(&kpriv, &kpub, &seed);

    const sfd = c.openat(keystore.dirfd_sig, tag,
        c.O_CREAT | c.O_WRONLY,
        c.S_IRUSR | c.S_IWUSR);
    if (sfd == -1) {
        std.debug.print("couldn't create signing key file for {s}\n", .{tag});
        return false;
    }

    const fout = c.fdopen(sfd, "w");
    defer _ = c.fclose(fout);

    var outl: usize = 0;
    const b64_priv = a12helper_tob64(&kpriv, 64, &outl) orelse return false;
    _ = c.fprintf(fout, "%s\n", b64_priv);
    std.heap.c_allocator.free(b64_priv[0..outl]);

    const b64_pub = a12helper_tob64(&kpub, 32, &outl) orelse return false;
    _ = c.fprintf(fout, "%s\n", b64_pub);
    std.heap.c_allocator.free(b64_pub[0..outl]);

    return true;
}

fn ent_from_pubk(pubk: *const [32]u8) ?*KeyEnt {
    if (keystore.dirfd_state == -1) return null;
    var ent = keystore.hosts;
    while (ent) |hp| {
        if (std.mem.eql(u8, &hp.key, pubk)) return hp;
        ent = hp.next;
    }
    return null;
}

pub export fn a12helper_keystore_statestore(
    pubk: *const [32]u8, name: [*:0]const u8,
    sz: usize, mode: [*:0]const u8) c_int
{
    _ = sz;
    const ent = ent_from_pubk(pubk) orelse return -1;

    const fn_s: [*:0]const u8 = ent.fn_name orelse return -1;
    _ = c.mkdirat(keystore.dirfd_state, fn_s, c.S_IRWXU);
    const dfd = c.openat(keystore.dirfd_state, fn_s,
        c.O_DIRECTORY | c.O_CLOEXEC);
    if (dfd == -1) return -1;

    const name_s = std.mem.span(name);
    if (std.mem.eql(u8, name_s, ".index")) {
        if (mode[0] != 'r') { _ = std.posix.close(@intCast(dfd)); return -1; }
        // Build listing in a temp memfd
        const alloc = std.heap.c_allocator;
        var list: std.ArrayList(u8) = .empty;
        defer list.deinit(alloc);
        list.appendSlice(alloc, "a12:directory_index:version=1\n") catch {
            _ = std.posix.close(@intCast(dfd));
            return -1;
        };
        const ldir = c.fdopendir(c.dup(dfd));
        if (ldir != null) {
            defer _ = c.closedir(ldir);
            while (c.readdir(ldir)) |de_raw| {
                const de: *c.struct_dirent = @ptrCast(de_raw);
                if (de.d_type == c.DT_REG) {
                    const dn: [*:0]const u8 = @ptrCast(&de.d_name);
                    var buf: [256]u8 = undefined;
                    const line = std.fmt.bufPrint(&buf, "file={s}\n", .{dn}) catch continue;
                    list.appendSlice(alloc, line) catch {};
                }
            }
        }
        _ = std.posix.close(@intCast(dfd));
        return buf_memfd(list.items);
    }

    const mode_s = std.mem.span(mode);
    const ret = if (std.mem.eql(u8, mode_s, "w+"))
        c.openat(dfd, name,
            c.O_CREAT | c.O_RDWR | c.O_CLOEXEC,
            c.S_IRUSR | c.S_IWUSR)
    else
        c.openat(dfd, name, c.O_RDONLY | c.O_CLOEXEC);

    _ = std.posix.close(@intCast(dfd));
    return ret;
}

fn buf_memfd(buf: []const u8) c_int {
    var template = "anetdirXXXXXX".*;
    const out = c.mkstemp(&template);
    if (out == -1) return -1;
    _ = c.unlink(&template);

    var pos: usize = 0;
    while (pos < buf.len) {
        const nw = std.posix.write(@intCast(out), buf[pos..]) catch |err| {
            if (err == error.Interrupted) continue;
            _ = std.posix.close(@intCast(out));
            return -1;
        };
        pos += nw;
    }
    _ = c.lseek(out, 0, c.SEEK_SET);
    return out;
}

pub export fn a12helper_keystore_stateunlink(
    pubk: *const [32]u8, name: [*:0]const u8) bool
{
    const name_s = std.mem.span(name);
    if (name_s.len == 0 or name_s[0] == '/') return false;

    const ent = ent_from_pubk(pubk) orelse return false;
    const fn_s: [*:0]const u8 = ent.fn_name orelse return false;
    const dfd = c.openat(keystore.dirfd_state, fn_s,
        c.O_DIRECTORY | c.O_CLOEXEC);
    if (dfd == -1) return false;
    const rv = c.unlinkat(dfd, name, 0);
    _ = std.posix.close(@intCast(dfd));
    return rv == 0;
}

pub export fn a12helper_keystore_dirfd(err: ?*[*c]const u8) c_int {
    const basedir = @import("shmif_types").getenvSpan("ARCAN_STATEPATH") orelse {
        if (err) |e| e.* = "Missing keystore (set ARCAN_STATEPATH)";
        return -1;
    };

    const dirc = std.heap.c_allocator.dupeZ(u8, basedir) catch {
        if (err) |e| e.* = "alloc failure";
        return -1;
    };
    defer std.heap.c_allocator.free(dirc);

    const dir = c.open(dirc.ptr, c.O_DIRECTORY | c.O_CLOEXEC);
    if (dir == -1) {
        if (err) |e| e.* = "Error opening basedir, check permissions and type";
        return -1;
    }

    const hostkeys = c.openat(dir, "hostkeys", c.O_DIRECTORY | c.O_CLOEXEC);
    if (hostkeys != -1) {
        _ = std.posix.close(@intCast(hostkeys));
        return dir;
    }

    var keydir = c.openat(dir, "a12", c.O_DIRECTORY | c.O_CLOEXEC);
    if (keydir == -1) {
        _ = c.mkdirat(dir, "a12", c.S_IRWXU);
        keydir = c.openat(dir, "a12", c.O_DIRECTORY | c.O_CLOEXEC);
    }
    _ = std.posix.close(@intCast(dir));
    return keydir;
}

// WANT_KEYSTORE_HASHER

pub export fn a12helper_keystore_known_accepted_challenge(
    pubk: *const [32]u8,
    chg: *const [8]u8,
    on_beacon: ?*const fn (
        *c.struct_arcan_shmif_cont,
        *const [32]u8,
        *const [8]u8,
        [*c]const u8,
        [*c]u8
    ) callconv(.c) bool,
    C: ?*c.struct_arcan_shmif_cont,
    addr: ?[*:0]u8) bool
{
    if (!keystore.open) return false;
    const cb = on_beacon orelse return false;

    var ent = keystore.hosts;
    if (ent == null) return false;

    while (ent) |hp| {
        // If challenge changed, recompute hash
        if (!std.mem.eql(u8, &hp.chg, chg)) {
            hp.chg = chg.*;
            var blake3 = std.crypto.hash.Blake3.init(.{});
            blake3.update(chg);
            blake3.update(&hp.key);
            blake3.final(&hp.pub_chg);
        }

        if (std.mem.eql(u8, pubk, &hp.pub_chg)) {
            _ = cb(C.?, &hp.key, chg, hp.host, addr);
        }
        ent = hp.next;
    }
    return false;
}

const KeystoreMask = extern struct {
    tag: ?[*:0]u8,
    pubk: [32]u8,
    next: ?*KeystoreMask,
};

fn in_mask(mask: ?*KeystoreMask, tag: []const u8, last: *?*KeystoreMask) bool {
    var m = mask;
    while (m) |mp| {
        if (mp.tag) |t| {
            if (std.mem.eql(u8, std.mem.span(t), tag)) return true;
        }
        if (mp.next == null) last.* = mp;
        m = mp.next;
    }
    return false;
}

pub export fn a12helper_keystore_public_tagset(mask: ?*KeystoreMask) bool {
    if (!keystore.open) return false;

    const tmpdfd = std.posix.dup(keystore.dirfd_private) catch return false;
    const dir = c.fdopendir(tmpdfd);
    if (dir == null) {
        _ = std.posix.close(tmpdfd);
        return false;
    }
    defer _ = c.closedir(dir);

    var last: ?*KeystoreMask = null;

    while (c.readdir(dir)) |dent_raw| {
        const dent: *c.struct_dirent = @ptrCast(dent_raw);
        if (dent.d_type != c.DT_REG) continue;
        const dname: [*:0]const u8 = @ptrCast(&dent.d_name);
        const tag_s = std.mem.span(dname);
        if (in_mask(mask, tag_s, &last)) continue;

        var outhost: ?[*:0]u8 = null;
        var outport: u16 = 0;
        var privk: [32]u8 = undefined;
        if (!a12helper_keystore_hostkey(dname, 0, &privk, &outhost, &outport)) continue;
        if (outhost) |h| { std.heap.c_allocator.free(std.mem.span(h)); }

        const lp = last orelse continue;
        lp.tag = (std.heap.c_allocator.dupeZ(u8, tag_s) catch continue).ptr;

        const next = std.heap.c_allocator.create(KeystoreMask) catch continue;
        next.* = .{ .tag = null, .pubk = std.mem.zeroes([32]u8), .next = null };
        lp.next = next;

        x25519_public_key(&privk, &lp.pubk);
    }

    return false; // dent == NULL — all processed
}
