// Zig port of a12/net/dir_supp.c — directory support functions for arcan-net.
// Utility functions for directory operations: appl packaging, signature
// verification, path management, and the shared I/O event loop.
// Copyright: Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");
const builtin = @import("builtin");
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    pub const chdir = libc.chdir;
    pub const close = libc.close;
    pub const execve = libc.execve;
    pub const _exit = libc._exit;
    pub const fchdir = libc.fchdir;
    pub const fclose = libc.fclose;
    pub const fcntl = libc.fcntl;
    pub const FD_CLOEXEC = libc.FD_CLOEXEC;
    pub const fdopen = libc.fdopen;
    pub const feof = libc.feof;
    pub const fflush = libc.fflush;
    pub const fgets = libc.fgets;
    pub const FILE = libc.FILE;
    pub const fork = libc.fork;
    pub const fprintf = libc.fprintf;
    pub const fputs = libc.fputs;
    pub const fread = libc.fread;
    pub const free = libc.free;
    pub const fseek = libc.fseek;
    pub const F_SETFD = libc.F_SETFD;
    pub const fwrite = libc.fwrite;
    pub const lseek = libc.lseek;
    pub const mkstemp = libc.mkstemp;
    pub const O_CREAT = libc.O_CREAT;
    pub const O_DIRECTORY = libc.O_DIRECTORY;
    pub const open = libc.open;
    pub const openat = libc.openat;
    pub const open_memstream = libc.open_memstream;
    pub const O_RDONLY = libc.O_RDONLY;
    pub const O_RDWR = libc.O_RDWR;
    pub const O_TRUNC = libc.O_TRUNC;
    pub const pipe = libc.pipe;
    pub const poll = libc.poll;
    pub const POLLERR = libc.POLLERR;
    pub const pollfd = libc.struct_pollfd;
    pub const POLLHUP = libc.POLLHUP;
    pub const POLLIN = libc.POLLIN;
    pub const POLLOUT = libc.POLLOUT;
    pub const pthread_attr_init = libc.pthread_attr_init;
    pub const pthread_attr_setdetachstate = libc.pthread_attr_setdetachstate;
    pub const pthread_attr_t = libc.pthread_attr_t;
    pub const pthread_create = libc.pthread_create;
    pub const PTHREAD_CREATE_DETACHED = libc.PTHREAD_CREATE_DETACHED;
    // consumer uses struct_ioloop_shared.lock which has anet's nominal
    // pthread_mutex_t; re-expose pthread_mutex_lock/unlock with anet's
    // pointer type so consumer need not cast each call site.
    pub extern "c" fn pthread_mutex_lock(mutex: *anet.pthread_mutex_t) c_int;
    pub extern "c" fn pthread_mutex_unlock(mutex: *anet.pthread_mutex_t) c_int;
    pub const pthread_t = libc.pthread_t;
    pub const read = libc.read;
    pub const SEEK_END = libc.SEEK_END;
    pub const SEEK_SET = libc.SEEK_SET;
    pub const setsid = libc.setsid;
    pub const sigaction = libc.sigaction;
    pub const SIGINT = libc.SIGINT;
    pub const snprintf = libc.snprintf;
    pub const STDERR_FILENO = libc.STDERR_FILENO;
    pub const STDIN_FILENO = libc.STDIN_FILENO;
    pub const STDOUT_FILENO = libc.STDOUT_FILENO;
    pub const strcmp = libc.strcmp;
    pub const strtoul = libc.strtoul;
    pub const strtoull = libc.strtoull;
    pub const struct_sigaction = libc.struct_sigaction;
    pub const unlink = libc.unlink;
    pub const write = libc.write;

    pub const EVENT_EXTERNAL = shmif.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_BCHUNKSTATE = shmif.EVENT_EXTERNAL_BCHUNKSTATE;
    pub const EVENT_TARGET = shmif.EVENT_TARGET;
    pub const TARGET_COMMAND_BCHUNK_IN = shmif.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_BCHUNK_OUT = shmif.TARGET_COMMAND_BCHUNK_OUT;
    pub const TARGET_COMMAND_REQFAIL = shmif.TARGET_COMMAND_REQFAIL;
    pub const struct_arcan_event = shmif.struct_arcan_event;
    pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
    pub const struct_arg_arr = shmif.struct_arg_arr;
    pub const struct_arcan_strarr = shmif.struct_arcan_strarr;

    // Consumer routes state through struct_ioloop_shared.S which carries
    // anet_types' nominal; alias here for consistency.
    pub const struct_a12_state = anet.struct_a12_state;

    pub const BREQ_LOAD = anet.BREQ_LOAD;
    pub const BREQ_STORE = anet.BREQ_STORE;
    pub const MULTIPART_BAD_EVENT = anet.MULTIPART_BAD_EVENT;
    pub const MULTIPART_BAD_FMT = anet.MULTIPART_BAD_FMT;
    pub const MULTIPART_BAD_MSG = anet.MULTIPART_BAD_MSG;
    pub const MULTIPART_OOM = anet.MULTIPART_OOM;
    pub const SIG_PRIVK_SZ = anet.SIG_PRIVK_SZ;
    pub const SIG_PUBK_SZ = anet.SIG_PUBK_SZ;
    pub const SIG_VAL_SZ = anet.SIG_VAL_SZ;
    pub const struct_appl_meta = anet.struct_appl_meta;
    pub const struct_dircl = anet.struct_dircl;
    pub const struct_evqueue_entry = anet.struct_evqueue_entry;
    pub const struct_global_cfg = anet.struct_global_cfg;
    pub const struct_ioloop_shared = anet.struct_ioloop_shared;
};

// Provided separately because including <sys/socket.h>/<sys/stat.h> pulls in
// headers that translate-c cannot render due to conditional bitfields in
// musl's struct timespec.
extern "c" fn recv(sockfd: c_int, buf: ?*anyopaque, len: usize, flags: c_int) isize;
extern "c" fn mkdirat(dirfd: c_int, path: [*c]const u8, mode: c_uint) c_int;
const S_IRWXU: c_uint = 0o700;

// Tracing
// Mirrored from the C TRACE macro: only emit when A12_TRACE_DIRECTORY is set.
// Because a12int_trace is a varargs C function we call it only from
// fixed-format helpers below; trace calls elsewhere are commented out.

// Constants
const SIG_PUBK_SZ: usize = c.SIG_PUBK_SZ;
const SIG_PRIVK_SZ: usize = c.SIG_PRIVK_SZ;
const SIG_VAL_SZ: usize = c.SIG_VAL_SZ;

// Extern C functions not pulled in by @cImport
extern "c" fn a12int_get_directory(S: ?*c.struct_a12_state, ts: *u64) *c.struct_appl_meta;
extern "c" fn a12int_trace(mask: c_int, fmt: [*:0]const u8, ...) void;
extern "c" fn a12_flush(S: ?*c.struct_a12_state, out: *[*]u8, hint: c_int) usize;
extern "c" fn a12_unpack(S: ?*c.struct_a12_state, buf: [*]u8, sz: usize, tag: ?*anyopaque, cb: ?*const anyopaque) void;
extern "c" fn a12_ok(S: ?*c.struct_a12_state) c_int;
extern "c" fn a12_tunnel_descriptor(S: ?*c.struct_a12_state, chid: u8, ok: *bool) c_int;
extern "c" fn a12_write_tunnel(S: ?*c.struct_a12_state, chid: u8, buf: [*]const u8, sz: usize) void;
extern "c" fn a12_drop_tunnel(S: ?*c.struct_a12_state, chid: u8) void;
extern "c" fn arcan_random(dst: [*]u8, sz: usize) void;
extern "c" fn arg_unpack(buf: [*:0]const u8) ?*c.struct_arg_arr;
extern "c" fn arg_lookup(args: *c.struct_arg_arr, key: [*:0]const u8, ind: c_uint, val: *?[*:0]const u8) bool;
extern "c" fn arg_add(hint: ?*anyopaque, args: **c.struct_arg_arr, key: [*:0]const u8, val: ?[*:0]const u8, dup: bool) void;
extern "c" fn arg_remove(args: *c.struct_arg_arr, key: [*:0]const u8) void;
extern "c" fn arg_cleanup(args: *c.struct_arg_arr) void;
extern "c" fn arg_serialize(args: *c.struct_arg_arr) ?[*:0]u8;
extern "c" fn a12helper_tob64(data: [*]const u8, len: usize, outl: *usize) ?[*:0]u8;
extern "c" fn a12helper_fromb64(instr: [*]const u8, lim: usize, outb: [*]u8) bool;
extern "c" fn a12helper_keystore_get_sigkey(tag: [*:0]const u8, pubk: [*]u8, privk: [*]u8) bool;
extern "c" fn a12helper_keystore_hostkey(tag: [*:0]const u8, index: c_int, privk: [*]u8, host: *?[*:0]u8, port: *u16) bool;
extern "c" fn a12helper_keystore_accept_ephemeral(pubk: [*]u8, tag: [*:0]const u8, ident: [*:0]const u8) void;
extern "c" fn arcan_shmif_enqueue(C: *c.struct_arcan_shmif_cont, ev: *const c.struct_arcan_event) void;
extern "c" fn arcan_shmif_wait(C: *c.struct_arcan_shmif_cont, ev: *c.struct_arcan_event) c_int;
extern "c" fn arcan_shmif_descrevent(ev: *c.struct_arcan_event) bool;
extern "c" fn arcan_shmif_dupfd(fd: c_int, newfd: c_int, nonblock: bool) c_int;
extern "c" fn x25519_private_key(privk: [*]u8) void;
extern "c" fn x25519_public_key(privk: [*]const u8, pubk: [*]u8) void;
extern "c" fn dirsrv_global_lock(file: [*:0]const u8, line: c_int) void;
extern "c" fn dirsrv_global_unlock(file: [*:0]const u8, line: c_int) void;
extern "c" fn dirsrv_set_source_mask(pubk: [*]u8, appid: u16, identity: [*]u8, dstpubk: [*]u8) void;
extern "c" fn dirsrv_opts() *c.struct_global_cfg;

// A12_FLUSH_ALL = 0, matches the C enum
const A12_FLUSH_ALL: c_int = 0;
const A12_TRACE_DIRECTORY: c_int = 1 << 9; // from a12.h

// TunnelMeta

const TunnelMeta = struct {
    I: *c.struct_ioloop_shared,
    tunid: u8,
};

fn tunnelThread(tag: ?*anyopaque) callconv(.c) ?*anyopaque {
    const meta: *TunnelMeta = @ptrCast(@alignCast(tag.?));
    const I = meta.I;
    const S = I.S;

    const gpa = std.heap.c_allocator;
    const buf = gpa.alloc(u8, 8832) catch {
        gpa.destroy(meta);
        return null;
    };
    defer gpa.free(buf);

    while (true) {
        var tun_ok: bool = false;
        _ = c.pthread_mutex_lock(&I.lock);
        const fd = a12_tunnel_descriptor(S, meta.tunid, &tun_ok);
        _ = c.pthread_mutex_unlock(&I.lock);

        if (!tun_ok) break;

        const nr = std.posix.read(@intCast(fd), buf) catch |e| {
            if (e == error.WouldBlock or e == error.Interrupted) continue;
            break;
        };
        if (nr == 0) break;

        _ = c.pthread_mutex_lock(&I.lock);
        a12_write_tunnel(S, meta.tunid, buf.ptr, nr);
        _ = c.pthread_mutex_unlock(&I.lock);

        // wake the ioloop
        const tunid = meta.tunid;
        _ = std.posix.write(@intCast(I.wakeup), std.mem.asBytes(&tunid)) catch {};
    }

    _ = c.pthread_mutex_lock(&I.lock);
    a12_drop_tunnel(S, meta.tunid);
    _ = c.pthread_mutex_unlock(&I.lock);

    // close the raw fd (must re-acquire to get final fd value)
    _ = c.pthread_mutex_lock(&I.lock);
    var final_ok: bool = false;
    const final_fd = a12_tunnel_descriptor(S, meta.tunid, &final_ok);
    _ = c.pthread_mutex_unlock(&I.lock);
    if (final_ok) _ = c.close(final_fd);

    gpa.destroy(meta);
    return null;
}

pub export fn anet_directory_tunnel_thread(I: *c.struct_ioloop_shared, chid: u8) void {
    const gpa = std.heap.c_allocator;
    const meta = gpa.create(TunnelMeta) catch return;
    meta.* = .{ .I = I, .tunid = chid };

    var pth: c.pthread_t = undefined;
    var attr: c.pthread_attr_t = undefined;
    _ = c.pthread_attr_init(&attr);
    _ = c.pthread_attr_setdetachstate(&attr, c.PTHREAD_CREATE_DETACHED);
    _ = c.pthread_create(&pth, &attr, tunnelThread, meta);
}

// Current loop singleton
var current_loop: ?*c.struct_ioloop_shared = null;

pub export fn anet_directory_ioloop_current() ?*c.struct_ioloop_shared {
    return current_loop;
}

// Main I/O event loop

pub export fn anet_directory_ioloop(I: *c.struct_ioloop_shared) void {
    const errmask: c_short = c.POLLERR | c.POLLHUP;

    var sigpipe: [2]c_int = .{ -1, -1 };
    _ = c.pipe(&sigpipe);
    _ = c.fcntl(sigpipe[0], c.F_SETFD, c.FD_CLOEXEC);
    _ = c.fcntl(sigpipe[1], c.F_SETFD, c.FD_CLOEXEC);

    retry: while (true) {
        current_loop = I;

        var fds: [6]c.pollfd = .{
            .{ .fd = I.userfd,  .events = c.POLLIN | errmask, .revents = 0 },
            .{ .fd = I.fdin,    .events = c.POLLIN | errmask, .revents = 0 },
            .{ .fd = -1,        .events = c.POLLOUT | errmask, .revents = 0 },
            .{ .fd = sigpipe[0],.events = c.POLLIN | errmask, .revents = 0 },
            .{ .fd = -1,        .events = c.POLLIN | errmask, .revents = 0 },
            .{ .fd = I.userfd2, .events = c.POLLIN | errmask, .revents = 0 },
        };

        I.wakeup = sigpipe[1];
        const S = I.S;

        var inbuf: [9000]u8 = undefined;
        var outbuf: [*]u8 = undefined;
        var ts: u64 = 0;

        _ = c.fcntl(I.fdin,  c.F_SETFD, c.FD_CLOEXEC);
        _ = c.fcntl(I.fdout, c.F_SETFD, c.FD_CLOEXEC);

        var outbuf_sz = a12_flush(S, &outbuf, A12_FLUSH_ALL);
        if (outbuf_sz != 0) fds[2].fd = I.fdout;

        var locked = false;

        while (I.shutdown == false and a12_ok(S) != 0) {
            const rc = c.poll(&fds, fds.len, -1);
            if (rc == -1) {
                const err = std.posix.errno(rc);
                if (err == .INTR or err == .AGAIN) continue;
            }

            _ = c.pthread_mutex_lock(&I.lock);
            locked = true;

            if (fds[0].revents != 0) {
                I.on_userfd.?(I, (fds[0].revents & errmask) == 0);
            }
            if (fds[5].revents != 0) {
                I.on_userfd2.?(I, (fds[5].revents & errmask) == 0);
            }
            if (fds[4].revents != 0) {
                I.on_shmif.?(I, (fds[4].revents & errmask) == 0);
            }

            // flush tunnel wakeup pipe
            if (fds[3].revents != 0) {
                var discard: [1024]u8 = undefined;
                _ = c.read(fds[3].fd, &discard, discard.len);
            }

            if ((fds[2].revents & c.POLLOUT) != 0 and outbuf_sz != 0) {
                const nw = c.write(I.fdout, outbuf, outbuf_sz);
                if (nw > 0) {
                    outbuf += @intCast(nw);
                    outbuf_sz -= @intCast(nw);
                }
            }

            if ((fds[1].revents & c.POLLIN) != 0) {
                const nr = recv(I.fdin, &inbuf, inbuf.len, 0);
                if (nr == -1) {
                    const err = std.posix.errno(nr);
                    if (err != .AGAIN and err != .INTR) {
                        locked = false;
                        _ = c.pthread_mutex_unlock(&I.lock);
                        break;
                    }
                } else if (nr == 0) {
                    locked = false;
                    _ = c.pthread_mutex_unlock(&I.lock);
                    break;
                } else {
                    a12_unpack(S, &inbuf, @intCast(nr), I, I.on_event);

                    if (I.on_directory) |on_dir| {
                        var new_ts: u64 = 0;
                        const dir = a12int_get_directory(S, &new_ts);
                        if (new_ts != ts) {
                            ts = new_ts;
                            if (!on_dir(I, dir)) {
                                locked = false;
                                _ = c.pthread_mutex_unlock(&I.lock);
                                break;
                            }
                        }
                    }
                }
            }

            if (outbuf_sz == 0) {
                outbuf_sz = a12_flush(S, &outbuf, A12_FLUSH_ALL);
                if (outbuf_sz == 0 and I.shutdown) {
                    locked = false;
                    _ = c.pthread_mutex_unlock(&I.lock);
                    break;
                }
            }

            fds[0].revents = 0;
            fds[1].revents = 0;
            fds[2].revents = 0;
            fds[3].revents = 0;
            fds[4].revents = 0;
            fds[5].revents = 0;

            fds[2].fd = if (outbuf_sz != 0) I.fdout else -1;
            fds[0].fd = I.userfd;
            fds[4].fd = if (I.shmif.addr != null) I.shmif.epipe else -1;
            fds[5].fd = I.userfd2;

            locked = false;
            _ = c.pthread_mutex_unlock(&I.lock);
        }

        if (locked) _ = c.pthread_mutex_unlock(&I.lock);

        // reconnect path
        if (I.shutdown == false) {
            if (I.on_disconnected) |on_dc| {
                if (on_dc(I)) continue :retry;
            }
        }

        break;
    }

    _ = c.close(I.wakeup);
    _ = c.close(sigpipe[0]);
    current_loop = null;
}

// buf_memfd

pub export fn buf_memfd(buf: [*]const u8, buf_sz: usize) c_int {
    var template: [13:0]u8 = "anetdirXXXXXX".*;
    const fd = c.mkstemp(&template);
    if (fd == -1) return -1;

    _ = c.unlink(&template);

    var pos: usize = 0;
    var remaining = buf_sz;
    while (remaining > 0) {
        const nw = c.write(fd, buf + pos, remaining);
        if (nw == -1) {
            const err = std.posix.errno(nw);
            if (err == .INTR or err == .AGAIN) continue;
            _ = c.close(fd);
            return -1;
        }
        remaining -= @intCast(nw);
        pos += @intCast(nw);
    }

    _ = c.lseek(fd, 0, c.SEEK_SET);
    return fd;
}

// file_to_membuf
// Rewind [applin] and copy its contents into a dynamically allocated memory
// buffer via open_memstream.  Both the original and the new FILE* remain open.

pub export fn file_to_membuf(
    applin: ?*c.FILE,
    out: *?[*:0]u8,
    out_sz: *usize,
) ?*c.FILE {
    if (applin == null) return null;

    _ = c.fseek(applin.?, 0, c.SEEK_SET);

    const applbuf = c.open_memstream(@ptrCast(out), out_sz) orelse return null;

    var buf: [4096]u8 = undefined;
    var ok = true;
    while (true) {
        const nr = c.fread(&buf, 1, buf.len, applin.?);
        if (nr == 0) break;
        if (c.fwrite(&buf, nr, 1, applbuf) != 1) {
            ok = false;
            break;
        }
    }

    if (!ok) {
        _ = c.fclose(applbuf);
        return null;
    }

    _ = c.fflush(applbuf);
    return applbuf;
}

// Path helpers

/// Recreate every directory component of [path] relative to [cdir].
fn ensurePath(cdir: c_int, path: []const u8) bool {
    const gpa = std.heap.c_allocator;
    // Allocate path.len + 1 so we always have room for a NUL terminator
    // at the current segment break, including the last segment where i ==
    // path.len. mkdirat reads a C string from wrk.ptr; without the +1 we'd
    // either OOB-write the NUL or hand mkdirat a non-terminated buffer.
    const wrk = gpa.alloc(u8, path.len + 1) catch return false;
    defer gpa.free(wrk);
    @memcpy(wrk[0..path.len], path);
    wrk[path.len] = 0;

    var i: usize = 0;
    while (i <= path.len) {
        // skip leading separators
        while (i < path.len and wrk[i] == '/') i += 1;
        // find next separator
        const start = i;
        while (i < path.len and wrk[i] != '/') i += 1;

        const finished = (i >= path.len);
        const saved = wrk[i];
        wrk[i] = 0;

        if (start < i) {
            _ = mkdirat(cdir, @ptrCast(wrk.ptr), S_IRWXU);
        }

        if (finished) return true;
        wrk[i] = saved;
    }
    return true;
}

// Blake3 / Ed25519 wrappers
// Use Zig's standard library instead of the C blake3/monocypher implementations.

fn blake3Hash16(data: []const u8, out: *[16]u8) void {
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(data);
    var full: [32]u8 = undefined;
    hasher.final(&full);
    @memcpy(out, full[0..16]);
}

/// Hash a serialised arg_arr and return the first 16 bytes.
fn buildArgArrHashSign(args: *c.struct_arg_arr, out: *[16]u8) void {
    const serialised = arg_serialize(args) orelse {
        @memset(out, 0);
        return;
    };
    defer c.free(serialised);
    const len = std.mem.len(serialised);
    blake3Hash16(serialised[0..len], out);
}

fn checkArgArrSign(
    args: *c.struct_arg_arr,
    insig_pk: *[32]u8,
    outsig_pk: *[32]u8,
    errmsg: *[*:0]const u8,
) bool {
    const null_sig = [_]u8{0} ** SIG_PUBK_SZ;

    // if insig_pk is zeroed try to pull the key from the manifest itself
    if (std.mem.eql(u8, insig_pk, &null_sig)) {
        var ksig_b64: ?[*:0]const u8 = null;
        if (arg_lookup(args, "ksig", 0, &ksig_b64)) {
            if (ksig_b64 == null) {
                errmsg.* = "signature key value empty in manifest";
                return false;
            }
            const kb64_slice = std.mem.span(ksig_b64.?);
            if (!a12helper_fromb64(@ptrCast(kb64_slice.ptr), SIG_PUBK_SZ, insig_pk)) {
                errmsg.* = "bad signature key in manifest";
                return false;
            }
        }
    }

    // still zero → no signature required
    if (std.mem.eql(u8, insig_pk, &null_sig)) return true;

    var ksig_b64: ?[*:0]const u8 = null;
    if (arg_lookup(args, "ksig", 0, &ksig_b64)) {
        if (ksig_b64 == null) {
            errmsg.* = "signature key value empty in manifest";
            return false;
        }
        const kb64_slice = std.mem.span(ksig_b64.?);
        if (!a12helper_fromb64(@ptrCast(kb64_slice.ptr), SIG_PUBK_SZ, outsig_pk)) {
            errmsg.* = "bad signature key in manifest";
            return false;
        }
    } else {
        errmsg.* = "signature key expected but not present";
        return false;
    }

    var sign_b64: ?[*:0]const u8 = null;
    if (!arg_lookup(args, "sign", 0, &sign_b64)) {
        errmsg.* = "signature missing from manifest";
        return false;
    }
    if (sign_b64 == null) {
        errmsg.* = "signature value empty in manifest";
        return false;
    }

    if (!std.mem.eql(u8, insig_pk, outsig_pk)) {
        errmsg.* = "reference signature doesn't match manifest signature";
        return false;
    }

    var sign_raw: [SIG_VAL_SZ]u8 = undefined;
    const sb64_slice = std.mem.span(sign_b64.?);
    if (!a12helper_fromb64(@ptrCast(sb64_slice.ptr), SIG_VAL_SZ, &sign_raw)) {
        errmsg.* = "bad signature value in manifest";
        return false;
    }

    arg_remove(args, "sign");
    arg_remove(args, "ksig");

    var hash_data: [16]u8 = undefined;
    buildArgArrHashSign(args, &hash_data);

    // Verify ed25519 signature using std.crypto.sign.Ed25519
    const pubk_bytes: [32]u8 = outsig_pk[0..32].*;
    const sig_bytes: [64]u8 = sign_raw[0..64].*;

    const pk = std.crypto.sign.Ed25519.PublicKey.fromBytes(pubk_bytes) catch {
        errmsg.* = "invalid ed25519 public key";
        return false;
    };
    const sig = std.crypto.sign.Ed25519.Signature.fromBytes(sig_bytes);
    sig.verify(&hash_data, pk) catch {
        errmsg.* = "signature doesn't match key";
        return false;
    };

    return true;
}

// verify_appl_pkg

pub export fn verify_appl_pkg(
    buf: [*]u8,
    buf_sz: usize,
    insig_pk: *[32]u8,
    outsig_pk: *[32]u8,
    errmsg: *?[*:0]const u8,
) ?[*:0]u8 {
    const gpa = std.heap.c_allocator;

    // find first newline — that delimits the packet header
    var lineend: usize = 0;
    while (lineend < buf_sz and buf[lineend] != '\n') : (lineend += 1) {}

    if (lineend >= buf_sz or buf[lineend] != '\n') {
        errmsg.* = "bad/missing header";
        return null;
    }

    // temporarily NUL-terminate the header line for arg_unpack
    buf[lineend] = 0;
    const args = arg_unpack(@ptrCast(buf));
    buf[lineend] = '\n';

    if (args == null) {
        errmsg.* = "malformed header";
        return null;
    }
    defer arg_cleanup(args.?);

    var em: [*:0]const u8 = "";
    if (!checkArgArrSign(args.?, insig_pk, outsig_pk, &em)) {
        errmsg.* = em;
        return null;
    }

    // verify that the data block hash matches what the header says
    var datahash_val: ?[*:0]const u8 = null;
    if (arg_lookup(args.?, "hash", 0, &datahash_val)) {
        if (datahash_val == null) {
            errmsg.* = "missing data block hash value";
            return null;
        }

        const data_start = lineend + 1;
        var hash_data: [16]u8 = undefined;
        blake3Hash16(buf[data_start..buf_sz], &hash_data);

        var dummy_outl: usize = 0;
        const hash_b64_ptr = a12helper_tob64(&hash_data, 16, &dummy_outl);
        if (hash_b64_ptr == null) {
            errmsg.* = "data - manifest checksum mismatch";
            return null;
        }
        defer c.free(hash_b64_ptr.?);

        if (c.strcmp(hash_b64_ptr.?, datahash_val.?) != 0) {
            errmsg.* = "data - manifest checksum mismatch";
            return null;
        }
    }

    // extract and validate the appl name
    var outname_val: ?[*:0]const u8 = null;
    if (arg_lookup(args.?, "name", 0, &outname_val) and outname_val != null) {
        const name_slice = std.mem.span(outname_val.?);
        if (name_slice.len == 0 or !std.ascii.isAlphabetic(name_slice[0])) {
            errmsg.* = "malformed appl-name";
            return null;
        }
        for (name_slice[1..]) |ch| {
            if (!std.ascii.isAlphanumeric(ch) and ch != '_') {
                errmsg.* = "malformed appl-name";
                return null;
            }
        }

        const res = gpa.dupeZ(u8, name_slice) catch {
            errmsg.* = "appl-name dupeZ alloc failed";
            return null;
        };
        errmsg.* = "";
        return res.ptr;
    }

    errmsg.* = "name field missing from manifest";
    return null;
}

// extract_appl_pkg

pub export fn extract_appl_pkg(
    fin: *c.FILE,
    cdir: c_int,
    basename: [*:0]const u8,
    msg: *?[*:0]const u8,
    manifest: ?**c.struct_arg_arr,
) bool {
    const gpa = std.heap.c_allocator;
    _ = c.fseek(fin, 0, c.SEEK_SET);

    var line: [1024]u8 = undefined;
    if (c.fgets(&line, line.len, fin) == null) return false;

    const args = arg_unpack(@ptrCast(&line)) orelse {
        msg.* = "broken manifest";
        return false;
    };

    _ = mkdirat(cdir, basename, S_IRWXU);
    const bdir = c.openat(cdir, basename, c.O_DIRECTORY);
    if (bdir == -1) {
        arg_cleanup(args);
        msg.* = "couldn't open basedir";
        return false;
    }

    const mfd = c.openat(bdir, ".manifest", c.O_CREAT | c.O_TRUNC | c.O_RDWR, @as(c_uint, 0o600));

    if (manifest) |m| {
        m.* = args;
    } else {
        arg_cleanup(args);
    }

    if (mfd == -1) {
        _ = c.close(bdir);
        msg.* = "couldn't create .manifest";
        return false;
    }

    const mfout = c.fdopen(mfd, "w");
    _ = c.fputs(@ptrCast(&line), mfout);
    _ = c.fclose(mfout);

    var in_file = false;
    var lastpath: ?[]u8 = null;
    defer if (lastpath) |lp| gpa.free(lp);

    while (c.feof(fin) == 0) {
        if (c.fgets(&line, line.len, fin) == null) break;

        const len = std.mem.len(@as([*:0]u8, @ptrCast(&line)));
        if (len == 0) {
            msg.* = "invalid file entry header";
            break;
        }

        line[len - 1] = 0; // strip newline for arg_unpack
        const entry = arg_unpack(@ptrCast(&line)) orelse break;
        defer arg_cleanup(entry);

        in_file = true;

        var path_val: ?[*:0]const u8 = null;
        var name_val: ?[*:0]const u8 = null;
        var size_val: ?[*:0]const u8 = null;

        if (!arg_lookup(entry, "path", 0, &path_val) or path_val == null) {
            msg.* = "broken path entry in file header";
            break;
        }
        if (!arg_lookup(entry, "name", 0, &name_val) or name_val == null) {
            msg.* = "broken name entry in file header";
            break;
        }
        if (!arg_lookup(entry, "size", 0, &size_val) or size_val == null) {
            msg.* = "missing size in file header";
            break;
        }

        const size_str = std.mem.span(size_val.?);
        const ntc_val = std.fmt.parseInt(usize, size_str, 10) catch {
            msg.* = "invalid size entry in file header";
            break;
        };

        const path_slice = std.mem.span(path_val.?);
        const plen = path_slice.len;

        if (plen > 0) {
            const need_mkdir = blk: {
                if (lastpath) |lp| {
                    break :blk !std.mem.eql(u8, lp, path_slice);
                }
                break :blk true;
            };
            if (need_mkdir) {
                if (lastpath) |lp| gpa.free(lp);
                lastpath = gpa.dupe(u8, path_slice) catch null;
                _ = ensurePath(bdir, path_slice);
            }
        }

        const name_slice = std.mem.span(name_val.?);
        const fn_str: []u8 = if (plen == 0)
            gpa.dupe(u8, name_slice) catch {
                msg.* = "couldn't allocate path";
                break;
            }
        else
            std.fmt.allocPrint(gpa, "{s}/{s}", .{ path_slice, name_slice }) catch {
                msg.* = "couldn't allocate path";
                break;
            };
        defer gpa.free(fn_str);

        // NUL-terminate for openat
        const fn_z = gpa.dupeZ(u8, fn_str) catch {
            msg.* = "couldn't allocate path";
            break;
        };
        defer gpa.free(fn_z);

        const ffd = c.openat(bdir, fn_z.ptr, c.O_CREAT | c.O_TRUNC | c.O_RDWR, @as(c_uint, 0o600));
        if (ffd == -1) {
            msg.* = "couldn't create file";
            break;
        }

        const fout = c.fdopen(ffd, "w");
        var remaining: usize = ntc_val;
        while (remaining > 0) {
            var fbuf: [4096]u8 = undefined;
            const to_read = @min(fbuf.len, remaining);
            const nr = c.fread(&fbuf, 1, to_read, fin);
            if (nr == 0) break;
            _ = c.fwrite(&fbuf, 1, nr, fout);
            remaining -= nr;
        }

        if (remaining != 0) {
            _ = c.fclose(fout);
            msg.* = "truncated / corrupted package";
            break;
        }

        _ = c.fclose(fout);
        in_file = false;
    }

    _ = c.close(bdir);
    return c.feof(fin) != 0 and !in_file;
}

// build_appl_pkg

pub export fn build_appl_pkg(
    name: [*:0]u8,
    dst: *c.struct_appl_meta,
    cdir: c_int,
    signtag: ?[*:0]const u8,
) bool {
    const gpa = std.heap.c_allocator;

    // save/restore CWD
    const olddir = c.open(".", c.O_DIRECTORY);
    defer _ = c.close(olddir);

    _ = c.fchdir(cdir);
    _ = c.chdir(name);

    // open_memstream for data accumulation
    var buf: [*c]u8 = null;
    var buf_sz: usize = 0;
    const fdata = c.open_memstream(&buf, &buf_sz) orelse {
        _ = c.fchdir(olddir);
        return false;
    };

    // signing keys
    var pubk: [SIG_PUBK_SZ]u8 = undefined;
    var privk: [SIG_PRIVK_SZ]u8 = undefined;
    if (signtag != null) {
        if (!a12helper_keystore_get_sigkey(signtag.?, &pubk, &privk)) {
            _ = c.fprintf(libc.stderr, "build_appl:couldn't open keystore-sign tag %s", signtag.?);
            _ = c.fclose(fdata);
            _ = c.fchdir(olddir);
            return false;
        }
    }

    // read .manifest or use default
    const mfd = c.openat(cdir, ".manifest", c.O_RDONLY);
    var header: ?*c.struct_arg_arr = null;

    if (mfd != -1) {
        const end = c.lseek(mfd, 0, c.SEEK_END);
        _ = c.lseek(mfd, 0, c.SEEK_SET);
        if (end < 0) {
            _ = c.fprintf(libc.stderr, "build_appl:can't read .manifest\n");
            _ = c.close(mfd);
            _ = c.fclose(fdata);
            _ = c.fchdir(olddir);
            return false;
        }

        const msize: usize = @intCast(end);
        const mbuf = gpa.alloc(u8, msize + 1) catch {
            _ = c.close(mfd);
            _ = c.fclose(fdata);
            _ = c.fchdir(olddir);
            return false;
        };
        defer gpa.free(mbuf);

        const fpek = c.fdopen(mfd, "r");
        _ = c.fread(mbuf.ptr, msize, 1, fpek);
        _ = c.fclose(fpek);

        // strip trailing whitespace
        var pos: usize = msize;
        mbuf[pos] = 0;
        while (pos > 0 and std.ascii.isWhitespace(mbuf[pos - 1])) {
            pos -= 1;
            mbuf[pos] = 0;
        }

        header = arg_unpack(@ptrCast(mbuf.ptr));
    } else {
        header = arg_unpack("version=1:perm=restricted");
    }

    if (header == null) {
        _ = c.fprintf(libc.stderr, "build_appl:malformed .manifest\n");
        _ = c.fclose(fdata);
        _ = c.fchdir(olddir);
        return false;
    }
    defer if (header != null) arg_cleanup(header.?);

    if (signtag != null) {
        arg_remove(header.?, "sign");
        arg_remove(header.?, "ksig");
        arg_remove(header.?, "hash");
    }

    // compute work_name: basename after last '/'
    const name_slice = std.mem.span(name);
    const work_name: [*:0]const u8 = blk: {
        if (name_slice[0] == '/' or name_slice[0] == '.') {
            if (std.mem.lastIndexOf(u8, name_slice, "/")) |idx| {
                break :blk @ptrCast(name + idx + 1);
            }
        }
        break :blk name;
    };

    arg_add(null, &header.?, "name", work_name, true);

    // walk directory with std.fs, sort entries alphabetically
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const FileEntry = struct {
        rel_path: []const u8, // relative to cwd (e.g. "subdir/file.lua")
        dir_part: []const u8, // directory component (may be empty)
        name_part: []const u8, // filename only
    };

    var entries: std.ArrayList(FileEntry) = .empty;
    defer entries.deinit(arena);

    var walk_dir = std.fs.cwd().openDir(".", .{ .iterate = true }) catch {
        _ = c.fclose(fdata);
        _ = c.fchdir(olddir);
        return false;
    };
    defer walk_dir.close();

    var walker = walk_dir.walk(arena) catch {
        _ = c.fclose(fdata);
        _ = c.fchdir(olddir);
        return false;
    };
    defer walker.deinit();

    while (walker.next() catch null) |we| {
        if (we.kind != .file) continue;
        // skip dot-files
        if (we.basename[0] == '.') continue;

        const rel = arena.dupeZ(u8, we.path) catch continue;
        const base = arena.dupeZ(u8, we.basename) catch continue;
        const dir_part = if (we.path.len > we.basename.len)
            arena.dupeZ(u8, we.path[0 .. we.path.len - we.basename.len - 1]) catch continue
        else
            arena.dupeZ(u8, "") catch continue;

        entries.append(arena, .{
            .rel_path = rel,
            .dir_part = dir_part,
            .name_part = base,
        }) catch continue;
    }

    // sort lexicographically by full relative path
    std.mem.sort(FileEntry, entries.items, {}, struct {
        fn lt(_: void, a: FileEntry, b: FileEntry) bool {
            return std.mem.lessThan(u8, a.rel_path, b.rel_path);
        }
    }.lt);

    // accumulate into fdata
    for (entries.items) |fe| {
        const file = std.fs.cwd().openFile(fe.rel_path, .{}) catch continue;
        defer file.close();

        const fbuf = file.readToEndAlloc(gpa, 64 * 1024 * 1024) catch continue;
        defer gpa.free(fbuf);

        // write file header
        _ = c.fprintf(fdata, "path=%s:name=%s:size=%zu\n",
            @as([*:0]const u8, @ptrCast(fe.dir_part.ptr)),
            @as([*:0]const u8, @ptrCast(fe.name_part.ptr)),
            fbuf.len);
        _ = c.fflush(fdata);
        _ = c.fwrite(fbuf.ptr, fbuf.len, 1, fdata);
    }

    _ = c.fclose(fdata);

    // hash over all data
    var hash_data: [16]u8 = undefined;
    blake3Hash16(buf[0..buf_sz], &hash_data);

    var dummy_outl: usize = 0;
    const pub_b64 = a12helper_tob64(&hash_data, 16, &dummy_outl);
    if (pub_b64 == null) {
        c.free(buf);
        _ = c.fchdir(olddir);
        return false;
    }
    arg_add(null, &header.?, "hash", pub_b64.?, false);
    c.free(pub_b64.?);

    const out_header = arg_serialize(header.?) orelse {
        c.free(buf);
        _ = c.fchdir(olddir);
        return false;
    };
    defer c.free(out_header);

    var outbuf_sz: usize = 0;
    const fpkg = c.open_memstream(&dst.buf, &outbuf_sz) orelse {
        c.free(buf);
        _ = c.fchdir(olddir);
        return false;
    };

    if (signtag != null) {
        buildArgArrHashSign(header.?, &hash_data);

        // Ed25519 sign with std.crypto
        var sign_bytes: [64]u8 = undefined;
        const sk = std.crypto.sign.Ed25519.SecretKey.fromBytes(privk[0..64].*) catch {
            _ = c.fclose(fpkg);
            c.free(buf);
            _ = c.fchdir(olddir);
            return false;
        };
        const kp = std.crypto.sign.Ed25519.KeyPair.fromSecretKey(sk) catch {
            _ = c.fclose(fpkg);
            c.free(buf);
            _ = c.fchdir(olddir);
            return false;
        };
        const sig = kp.sign(&hash_data, null) catch {
            _ = c.fclose(fpkg);
            c.free(buf);
            _ = c.fchdir(olddir);
            return false;
        };
        sign_bytes = sig.toBytes();

        var pubk_outl: usize = 0;
        var sign_outl: usize = 0;
        const pubk_b64 = a12helper_tob64(&pubk, 32, &pubk_outl);
        const sign_b64 = a12helper_tob64(&sign_bytes, 64, &sign_outl);
        defer {
            if (pubk_b64) |p| c.free(p);
            if (sign_b64) |s| c.free(s);
        }

        if (pubk_b64 == null or sign_b64 == null) {
            _ = c.fclose(fpkg);
            c.free(buf);
            _ = c.fchdir(olddir);
            return false;
        }

        _ = c.fprintf(fpkg, "ksig=%s:sign=%s:%s\n", pubk_b64.?, sign_b64.?, out_header);
    } else {
        _ = c.fprintf(fpkg, "%s\n", out_header);
    }

    _ = c.fwrite(buf, buf_sz, 1, fpkg);
    _ = c.fflush(fpkg);
    _ = c.fclose(fpkg);
    c.free(buf);

    dst.buf_sz = @intCast(outbuf_sz);

    // hash the complete package blob for quick identity checks
    var pkg_hash: [16]u8 = undefined;
    blake3Hash16((dst.buf orelse unreachable)[0..dst.buf_sz], &pkg_hash);
    @memcpy(&dst.hash, pkg_hash[0..4]);

    _ = c.snprintf(@ptrCast(&dst.appl.name), dst.appl.name.len, "%s", work_name);

    // append an empty sentinel node
    const next_node = gpa.create(c.struct_appl_meta) catch {
        _ = c.fchdir(olddir);
        return false;
    };
    next_node.* = std.mem.zeroes(c.struct_appl_meta);
    dst.next = next_node;

    _ = c.fchdir(olddir);
    return true;
}

// anet_directory_random_ident

pub export fn anet_directory_random_ident(dst: [*]u8, nb: usize) void {
    const rnd_buf = std.heap.c_allocator.alloc(u8, nb) catch return;
    defer std.heap.c_allocator.free(rnd_buf);
    arcan_random(rnd_buf.ptr, nb);
    for (0..nb) |i| {
        dst[i] = 'a' + (rnd_buf[i] % 26);
    }
}

// anet_directory_merge_multipart
// Thread-local state for coalescing multipart messages.

const MultipartState = struct {
    sz: usize = 0,
    cnt: usize = 0,
    buf: ?[]u8 = null,
};

threadlocal var mp_state: MultipartState = .{};

pub export fn anet_directory_merge_multipart(
    ev: ?*c.struct_arcan_event,
    outarg: ?**c.struct_arg_arr,
    outbuf: ?*?[*:0]u8,
    err: *c_int,
) bool {
    const gpa = std.heap.c_allocator;

    // NULL ev → free TLS state
    if (ev == null) {
        if (mp_state.sz != 0) {
            if (mp_state.buf) |b| gpa.free(b);
            mp_state = .{};
        }
        return true;
    }

    var src: [*:0]u8 = undefined;
    var multipart: bool = undefined;
    var cap: usize = undefined;

    const cat = ev.?.unnamed_0.unnamed_0.category;
    if (cat == c.EVENT_EXTERNAL) {
        multipart = ev.?.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.multipart != 0;
        src = @ptrCast(&ev.?.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data);
        cap = ev.?.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data.len;
    } else if (cat == c.EVENT_TARGET) {
        src = @ptrCast(&ev.?.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message);
        multipart = ev.?.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv != 0;
        cap = ev.?.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message.len;
    } else {
        err.* = c.MULTIPART_BAD_EVENT;
        return false;
    }

    // fast path: single message, nothing buffered
    if (!multipart and mp_state.sz == 0) {
        if (outarg) |oa| {
            oa.* = arg_unpack(src) orelse {
                mp_state.cnt = 0;
                err.* = c.MULTIPART_BAD_FMT;
                return false;
            };
        } else if (outbuf) |ob| {
            const src_slice = std.mem.span(src);
            const duped = gpa.dupeZ(u8, src_slice) catch {
                err.* = c.MULTIPART_OOM;
                return false;
            };
            ob.* = duped.ptr;
        }
        mp_state.cnt = 0;
        return true;
    }

    const src_slice = src[0..std.mem.len(src)];
    const len = src_slice.len;

    if (len == cap) {
        mp_state.cnt = 0;
        err.* = c.MULTIPART_BAD_MSG;
        return false;
    }

    // grow buffer if needed
    if (len + mp_state.cnt >= mp_state.sz) {
        const new_sz = mp_state.sz + 4096;
        const new_buf = gpa.alloc(u8, new_sz) catch {
            err.* = c.MULTIPART_OOM;
            return false;
        };
        if (mp_state.sz != 0) {
            if (mp_state.buf) |old| {
                @memcpy(new_buf[0..mp_state.cnt], old[0..mp_state.cnt]);
                gpa.free(old);
            }
        }
        mp_state.buf = new_buf;
        mp_state.sz = new_sz;
    }

    const mb = mp_state.buf.?;
    @memcpy(mb[mp_state.cnt .. mp_state.cnt + len], src_slice);
    mp_state.cnt += len;
    mb[mp_state.cnt] = 0;

    if (multipart) {
        err.* = 0;
        return false;
    }

    // final chunk: unpack and reset
    const z_src: [*:0]const u8 = @ptrCast(mb.ptr);
    const parsed = arg_unpack(z_src) orelse {
        mp_state.cnt = 0;
        err.* = c.MULTIPART_BAD_FMT;
        return false;
    };
    mp_state.cnt = 0;

    if (outarg) |oa| oa.* = parsed;
    err.* = 0;
    return true;
}

// dir_block_synch_request

pub export fn dir_block_synch_request(
    C: *c.struct_arcan_shmif_cont,
    ev: c.struct_arcan_event,
    reply: *c.struct_evqueue_entry,
    cat_ok: c_int,
    kind_ok: c_int,
    cat_fail: c_int,
    kind_fail: c_int,
) bool {
    const gpa = std.heap.c_allocator;
    reply.* = std.mem.zeroes(c.struct_evqueue_entry);

    var mutable_ev = ev;
    if (ev.unnamed_0.unnamed_0.unnamed_0.ext.kind != 0)
        arcan_shmif_enqueue(C, &mutable_ev);

    var cur_reply = reply;
    while (arcan_shmif_wait(C, &mutable_ev) != 0) {
        // tgt.kind is at the same union offset regardless of category
        const kind = mutable_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind;
        if ((cat_ok == mutable_ev.unnamed_0.unnamed_0.category and kind == kind_ok) or
            (cat_fail == mutable_ev.unnamed_0.unnamed_0.category and kind == kind_fail))
        {
            cur_reply.ev = mutable_ev;
            cur_reply.next = null;
            return true;
        }

        // dup descriptor events before the next shmif call closes the fd
        if (arcan_shmif_descrevent(&mutable_ev)) {
            mutable_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv =
                arcan_shmif_dupfd(mutable_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, -1, true);
        }

        cur_reply.ev = mutable_ev;
        const next_node = gpa.create(c.struct_evqueue_entry) catch return false;
        next_node.* = std.mem.zeroes(c.struct_evqueue_entry);
        cur_reply.next = next_node;
        cur_reply = next_node;
    }

    return false;
}

// dir_request_resource

pub export fn dir_request_resource(
    C: *c.struct_arcan_shmif_cont,
    ns: usize,
    id: [*:0]const u8,
    mode: c_int,
    pending: *c.struct_evqueue_entry,
) bool {
    var ev = c.struct_arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_BCHUNKSTATE;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.input = if (mode == c.BREQ_LOAD) 1 else 0;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns = @intCast(ns);

    _ = c.snprintf(
        @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions),
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions.len,
        "%s",
        id,
    );

    const kind: c_int = if (mode == c.BREQ_STORE)
        c.TARGET_COMMAND_BCHUNK_OUT
    else
        c.TARGET_COMMAND_BCHUNK_IN;

    return dir_block_synch_request(
        C,
        ev,
        pending,
        c.EVENT_TARGET, kind,
        c.EVENT_TARGET, c.TARGET_COMMAND_REQFAIL,
    );
}

// dir_unpack_index

pub export fn dir_unpack_index(fd: c_int) ?*c.struct_appl_meta {
    const gpa = std.heap.c_allocator;
    const fpek = c.fdopen(fd, "r") orelse return null;
    defer _ = c.fclose(fpek);

    var first: ?*c.struct_appl_meta = null;
    var cur: *?*c.struct_appl_meta = &first;

    var n: usize = 0;
    while (c.feof(fpek) == 0) {
        var line: [256]u8 = undefined;
        const res = c.fgets(&line, line.len, fpek);
        if (res == null) continue;
        n += 1;

        const entry = arg_unpack(@ptrCast(&line)) orelse continue;
        defer arg_cleanup(entry);

        var kind_val: ?[*:0]const u8 = null;
        if (!arg_lookup(entry, "kind", 0, &kind_val) or kind_val == null) continue;

        var name_val: ?[*:0]const u8 = null;
        _ = arg_lookup(entry, "name", 0, &name_val);

        const node = gpa.create(c.struct_appl_meta) catch continue;
        node.* = std.mem.zeroes(c.struct_appl_meta);

        if (name_val) |nv| {
            _ = c.snprintf(@ptrCast(&node.appl.name), node.appl.name.len, "%s", nv);
        }

        var tmp: ?[*:0]const u8 = null;

        if (arg_lookup(entry, "categories", 0, &tmp) and tmp != null) {
            node.categories = @intCast(c.strtoul(tmp.?, null, 10));
        }
        if (arg_lookup(entry, "size", 0, &tmp) and tmp != null) {
            node.buf_sz = @intCast(c.strtoul(tmp.?, null, 10));
        }
        if (arg_lookup(entry, "id", 0, &tmp) and tmp != null) {
            node.identifier = @intCast(c.strtoul(tmp.?, null, 10));
        }
        if (arg_lookup(entry, "hash", 0, &tmp) and tmp != null) {
            const hval = c.strtoul(tmp.?, null, 16);
            const hbytes = std.mem.asBytes(&hval);
            @memcpy(&node.hash, hbytes[0..4]);
        }
        if (arg_lookup(entry, "timestamp", 0, &tmp) and tmp != null) {
            node.update_ts = c.strtoull(tmp.?, null, 10);
        }

        cur.* = node;
        cur = &node.next;
    }

    return first;
}

// HAVE_DIRSRV: anet_directory_dirsrv_exec_source

pub export fn anet_directory_dirsrv_exec_source(
    dst: ?*c.struct_dircl,
    applid: u16,
    ident: ?[*:0]const u8,
    exec: [*:0]u8,
    argv: *c.struct_arcan_strarr,
    envv: *c.struct_arcan_strarr,
) bool {
    const gpa = std.heap.c_allocator;

    // generate ephemeral x25519 keypair
    var private: [32]u8 = undefined;
    var public: [32]u8 = undefined;
    x25519_private_key(&private);
    x25519_public_key(&private, &public);

    var priv_outl: usize = 0;
    var pub_outl: usize = 0;

    var tmp_ident_buf: [8]u8 = undefined;
    const actual_ident: [*:0]const u8 = if (ident) |id| id else blk: {
        anet_directory_random_ident(&tmp_ident_buf, 7);
        tmp_ident_buf[7] = 0;
        break :blk @ptrCast(&tmp_ident_buf);
    };

    a12helper_keystore_accept_ephemeral(&public, "_local", actual_ident);

    var emptyid: [16]u8 = .{0} ** 16;

    // NOTE: __FILE__ / __LINE__ are not available in Zig; pass module name
    dirsrv_global_lock("dir_supp.zig", 0);
    if (dst) |d| {
        dirsrv_set_source_mask(&public, applid, &emptyid, &d.pubk);
    } else {
        var emptyk: [32]u8 = .{0} ** 32;
        dirsrv_set_source_mask(&public, applid, &emptyid, &emptyk);
    }
    dirsrv_global_unlock("dir_supp.zig", 0);

    // get server host key
    var srvprivk: [32]u8 = undefined;
    var srvpubk: [32]u8 = undefined;
    var host_ptr: ?[*:0]u8 = null;
    var tmpport: u16 = 0;
    _ = a12helper_keystore_hostkey("default", 0, &srvprivk, &host_ptr, &tmpport);
    x25519_public_key(&srvprivk, &srvpubk);

    const priv_b64 = a12helper_tob64(&private, 32, &priv_outl) orelse return false;
    defer c.free(priv_b64);
    const pub_b64 = a12helper_tob64(&srvpubk, 32, &pub_outl) orelse return false;
    defer c.free(pub_b64);

    // build outargv — size = argv.count + 13
    const argc: usize = if (argv.count > 0) @intCast(argv.count) else 0;
    const outargv = gpa.alloc(?[*:0]u8, argc + 13) catch return false;
    defer gpa.free(outargv);
    @memset(outargv, null);

    const opts = dirsrv_opts();
    var ind: usize = 0;
    outargv[ind] = opts.path_self; ind += 1;
    outargv[ind] = @constCast("-d"); ind += 1;
    outargv[ind] = @constCast("8191"); ind += 1;
    outargv[ind] = @constCast("--stderr-log"); ind += 1;
    outargv[ind] = @constCast("--force-kpub"); ind += 1;
    outargv[ind] = pub_b64; ind += 1;
    outargv[ind] = @constCast("--ident"); ind += 1;
    outargv[ind] = @ptrCast(@constCast(actual_ident)); ind += 1;
    outargv[ind] = @constCast("localhost"); ind += 1;
    outargv[ind] = @constCast("--"); ind += 1;
    outargv[ind] = exec; ind += 1;
    // skip argv[0] (self)
    if (argc > 1) {
        for (1..argc) |i| {
            outargv[ind] = argv.unnamed_0.data[i];
            ind += 1;
        }
    }

    // build outenv
    const envc: usize = if (envv.count > 0) @intCast(envv.count) else 0;
    const outenv = gpa.alloc(?[*:0]u8, envc + 2) catch return false;
    defer gpa.free(outenv);
    @memset(outenv, null);

    for (0..envc) |i| outenv[i] = envv.unnamed_0.data[i];

    // A12_USEPRIV=<b64>
    const envinf = std.fmt.allocPrintSentinel(gpa, "A12_USEPRIV={s}", .{std.mem.span(priv_b64)}, 0) catch return false;
    defer gpa.free(envinf);
    outenv[envc] = envinf.ptr;

    // log filename
    var msg: ?[*:0]u8 = null;
    const log_name = std.fmt.allocPrintSentinel(gpa, "launch_{s}.log", .{std.mem.span(actual_ident)}, 0) catch null;
    defer if (log_name) |ln| gpa.free(ln);
    if (log_name) |ln| msg = ln.ptr;

    // double-fork to daemonise
    const pid = c.fork();
    if (pid == 0) {
        if (c.fork() != 0) c._exit(0);

        _ = c.close(c.STDIN_FILENO);
        _ = c.close(c.STDOUT_FILENO);
        _ = c.close(c.STDERR_FILENO);

        var sa = std.mem.zeroes(c.struct_sigaction);
        _ = c.sigaction(c.SIGINT, &sa, null);

        _ = c.open("/dev/null", c.O_RDWR); // stdin
        _ = c.open("/dev/null", c.O_RDWR); // stdout

        var opened_log = false;
        if (msg) |m| {
            if (c.openat(opts.dirsrv.appl_logdfd, m, c.O_RDWR | c.O_CREAT, @as(c_uint, 0o700)) != -1) {
                opened_log = true;
            }
        }
        if (!opened_log) {
            _ = c.open("/dev/null", c.O_RDWR);
        }

        _ = c.setsid();
        _ = c.execve(opts.path_self orelse "", @ptrCast(outargv.ptr), @ptrCast(outenv.ptr));
        c._exit(1);
    }

    // SIGCHLD is dropped by default; no waitpid needed here.
    return true;
}
