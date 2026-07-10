// Zig port of frameserver/util/anet_helper.c — outbound connect / bind+listen /
// authentication loop helpers shared across a12-based frameservers.
// Copyright: Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");
const a12 = @import("a12_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    pub const accept = libc.accept;
    pub const AF_UNSPEC = libc.AF_UNSPEC;
    pub const asprintf = libc.asprintf;
    pub const bind = libc.bind;
    pub const close = libc.close;
    pub const connect = libc.connect;
    pub const EAGAIN = libc.EAGAIN;
    pub const EINTR = libc.EINTR;
    pub const __errno_location = libc.__errno_location;
    pub const fcntl = libc.fcntl;
    pub const FD_CLOEXEC = libc.FD_CLOEXEC;
    pub const F_GETFD = libc.F_GETFD;
    pub const fgets = libc.fgets;
    pub const FILE = libc.FILE;
    pub const fprintf = libc.fprintf;
    pub const free = libc.free;
    pub const F_SETFD = libc.F_SETFD;
    pub const IPPROTO_TCP = libc.IPPROTO_TCP;
    pub const isatty = libc.isatty;
    pub const listen = libc.listen;
    pub const malloc = libc.malloc;
    // PRIu16 is a C99 printf macro ("u"); consumers print u16 via {d} format.
    pub const PRIu16 = "u";
    pub const read = libc.read;
    pub const setsockopt = libc.setsockopt;
    pub const sigaction = libc.sigaction;
    pub const SIGCHLD = libc.SIGCHLD;
    pub const SIGPIPE = libc.SIGPIPE;
    pub const sleep = libc.sleep;
    pub const snprintf = libc.snprintf;
    pub const socket = libc.socket;
    pub const socklen_t = libc.socklen_t;
    pub const SOCK_STREAM = libc.SOCK_STREAM;
    pub const SOL_SOCKET = libc.SOL_SOCKET;
    pub const SO_REUSEADDR = libc.SO_REUSEADDR;
    pub const SO_REUSEPORT = libc.SO_REUSEPORT;
    pub const STDIN_FILENO = libc.STDIN_FILENO;
    pub const strcmp = libc.strcmp;
    pub const strdup = libc.strdup;
    pub const strerror = libc.strerror;
    pub const strlen = libc.strlen;
    pub const struct_sigaction = libc.struct_sigaction;
    pub const struct_sockaddr = libc.struct_sockaddr;
    pub const TCP_NODELAY = libc.TCP_NODELAY;
    pub const write = libc.write;

    pub const A12_TRACE_SECURITY = a12.A12_TRACE_SECURITY;
    pub const AUTH_FULL_PK = a12.AUTH_FULL_PK;
    // anet's version of struct_a12_context_options lines up with what
    // args.opts/anet_options.opts return; use it consistently.
    pub const struct_a12_context_options = anet.struct_a12_context_options;
    pub const struct_a12_state = a12.struct_a12_state;

    pub const a12helper_keystore_hostkey = anet.a12helper_keystore_hostkey;
    pub const a12helper_keystore_open = anet.a12helper_keystore_open;
    pub const a12helper_keystore_register = anet.a12helper_keystore_register;
    pub const a12helper_keystore_release = anet.a12helper_keystore_release;
    pub const struct_anet_cl_connection = anet.struct_anet_cl_connection;
    pub const struct_anet_options = anet.struct_anet_options;
};

// External declarations

extern "c" fn a12helper_tob64(data: [*]const u8, inl: usize, outl: *usize) ?[*]u8;
extern "c" fn x25519_public_key(secret: *const [32]u8, public: *[32]u8) void;

extern "c" fn a12_auth_state(S: *c.struct_a12_state) c_int;
extern "c" fn a12_poll(S: *c.struct_a12_state) c_int;
extern "c" fn a12_unpack(S: *c.struct_a12_state, buf: [*]const u8, sz: usize, tag: ?*anyopaque, cb: ?*const anyopaque) void;
extern "c" fn a12_flush(S: *c.struct_a12_state, out: *[*]u8, hint: c_int) usize;
extern "c" fn a12_error_state(S: *c.struct_a12_state) ?[*:0]const u8;
// Use the a12_types-typed a12_client/a12_server directly. callers that
// produce opts from anet_options (anet_types nominal) ptrCast at the site.
const a12_client = a12.a12_client;
const a12_server = a12.a12_server;
extern "c" fn a12_free(S: *c.struct_a12_state) void;
extern "c" fn a12_set_endpoint(S: *c.struct_a12_state, endp: [*:0]u8) void;
// a12int_trace is a macro in a12.h that references a local `S` variable and
// emits via fprintf(a12_trace_dst, …). Replicate that for anet_cl_setup's
// security-group traces via direct variadic fprintf against the globals.
extern "c" var a12_trace_dst: ?*c.FILE;
extern "c" var a12_trace_targets: c_int;
extern "c" fn a12int_group_tostr(group: c_int) [*:0]const u8;
extern "c" fn arcan_timemillis() c_longlong;
fn anetTrace(group: c_int, comptime fmt: []const u8, args: anytype) void {
    const dst = a12_trace_dst orelse return;
    if ((a12_trace_targets & group) == 0) return;
    const full: [*:0]const u8 = "tag=anet_cl:ts=%lld:group=%s:function=anet_cl_setup:" ++ fmt ++ "\n";
    _ = @call(.auto, c.fprintf, .{
        dst, full,
        arcan_timemillis(),
        a12int_group_tostr(group),
    } ++ args);
}

// BSD/POSIX functions — cImport of sys/socket.h usually exposes these, but we
// force-declare them to keep the layer explicit and avoid translate-c traps on
// some of the more exotic socket helpers.
extern "c" fn shutdown(sockfd: c_int, how: c_int) c_int;

const SHUT_RDWR: c_int = 2;

// anet_helper.h forward-declares `struct addrinfo` without including <netdb.h>,
// so translate-c only sees an opaque type. Mirror the musl layout here and
// bind the netdb entry points as externs.
const socklen_t = c.socklen_t;
const Addrinfo = extern struct {
    ai_flags: c_int,
    ai_family: c_int,
    ai_socktype: c_int,
    ai_protocol: c_int,
    ai_addrlen: socklen_t,
    ai_addr: ?*c.struct_sockaddr,
    ai_canonname: ?[*:0]u8,
    ai_next: ?*Addrinfo,
};
extern "c" fn getaddrinfo(
    node: ?[*:0]const u8, service: ?[*:0]const u8,
    hints: ?*const Addrinfo, res: *?*Addrinfo,
) c_int;
extern "c" fn freeaddrinfo(res: ?*Addrinfo) void;
extern "c" fn getnameinfo(
    sa: ?*const c.struct_sockaddr, salen: socklen_t,
    host: [*]u8, hostlen: socklen_t,
    serv: ?[*]u8, servlen: socklen_t, flags: c_int,
) c_int;
extern "c" fn gai_strerror(errc: c_int) [*:0]const u8;

const NI_MAXHOST: usize = 255;
const NI_MAXSERV: usize = 32;
const NI_NUMERICHOST: c_int = 0x01;
const NI_NUMERICSERV: c_int = 0x02;
const AI_PASSIVE: c_int = 0x01;

// SIG_IGN via sigaction struct rewrite pattern. struct_sigaction's first
// field is the sa_handler function pointer regardless of whether we see
// a cImport-generated layout or the hand-rolled one in posix_libc; write
// SIG_IGN (sentinel 1) into the first pointer slot.
fn ignoreSignal(signum: c_int) void {
    var sa: c.struct_sigaction = std.mem.zeroes(c.struct_sigaction);
    @as(*usize, @ptrCast(&sa)).* = 1; // SIG_IGN
    _ = c.sigaction(signum, &sa, null);
}

// anet_clfd
// From a prefilled addrinfo chain, walk each candidate and return a connected
// socket, or -1 if none worked.

pub export fn anet_clfd(addr: ?*Addrinfo) c_int {
    var clfd: c_int = -1;

    var cur = addr;
    while (cur) |n| : (cur = n.ai_next) {
        clfd = c.socket(n.ai_family, n.ai_socktype, n.ai_protocol);
        if (clfd == -1) continue;

        if (c.connect(clfd, n.ai_addr, n.ai_addrlen) != -1) {
            var hostaddr: [NI_MAXHOST]u8 = undefined;
            var hostport: [NI_MAXSERV]u8 = undefined;
            _ = getnameinfo(
                n.ai_addr, n.ai_addrlen,
                &hostaddr, hostaddr.len,
                &hostport, hostport.len,
                NI_NUMERICSERV | NI_NUMERICHOST,
            );
            var optval: c_int = 1;
            _ = c.setsockopt(clfd, c.IPPROTO_TCP, c.TCP_NODELAY,
                &optval, @sizeOf(c_int));
            return clfd;
        }

        _ = c.close(clfd);
        clfd = -1;
    }

    return clfd;
}

// flushout: internal authentication write-drain

fn flushout(S: *c.struct_a12_state, fdout: c_int, err: *?[*:0]u8) bool {
    var buf: [*]u8 = undefined;
    var out = a12_flush(S, &buf, 0);

    while (out != 0) {
        const nw = c.write(fdout, buf, out);
        if (nw == -1) {
            const eno = c.__errno_location().*;
            if (eno == c.EAGAIN or eno == c.EINTR) continue;

            var ebuf: [64]u8 = undefined;
            _ = c.snprintf(&ebuf, ebuf.len,
                "[%d] write fail during authentication\n", eno);
            err.* = c.strdup(&ebuf);
            return false;
        }
        out -= @intCast(nw);
        buf += @intCast(nw);
    }

    return true;
}

// anet_authenticate
// Blocking read/write cycle feeding the state machine until AUTH_FULL_PK or
// failure. The caller is responsible for freeing *err and tearing down the
// context on false.

pub export fn anet_authenticate(
    S: *c.struct_a12_state, fdin: c_int, fdout: c_int, err: *?[*:0]u8,
) bool {
    var inbuf: [4096]u8 = undefined;

    while (flushout(S, fdout, err)
        and a12_auth_state(S) != c.AUTH_FULL_PK
        and a12_poll(S) >= 0)
    {
        const nr = c.read(fdin, &inbuf, inbuf.len);
        if (nr > 0) {
            a12_unpack(S, &inbuf, @intCast(nr), null, null);
        } else {
            const eno = c.__errno_location().*;
            if (nr == 0 or (eno != c.EAGAIN and eno != c.EINTR)) {
                var ebuf: [64]u8 = undefined;
                _ = c.snprintf(&ebuf, ebuf.len,
                    "[%d] read fail during authentication\n", eno);
                err.* = c.strdup(&ebuf);
                return false;
            }
        }
    }

    if (a12_auth_state(S) != c.AUTH_FULL_PK) {
        if (a12_error_state(S)) |lw| {
            err.* = c.strdup(lw);
        }
        return false;
    }
    return true;
}

// a12helper_query_untrusted_key
// isatty prompt for handling a never-seen public key.

pub export fn a12helper_query_untrusted_key(
    trust_domain: [*:0]const u8,
    kpub_b64: [*:0]u8,
    kpub: *const [32]u8,
    out_tag: *?[*:0]u8,
    prefix_ofs: *usize,
) bool {
    prefix_ofs.* = 0;
    if (c.isatty(c.STDIN_FILENO) == 0) return false;

    const empty = std.mem.zeroes([32]u8);
    if (std.mem.eql(u8, &empty, kpub)) {
        _ = c.fprintf(libc.stdout,
            "The other end supplied an untrusted, all-zero public key. Rejecting.\n");
        return false;
    }

    _ = c.fprintf(libc.stdout,
        "The other end is using an unknown public key (%s).\n" ++
        "Are you sure you want to continue (yes/no/remember):\n", kpub_b64);

    var buf: [16]u8 = std.mem.zeroes([16]u8);
    _ = c.fgets(&buf, buf.len, libc.stdin);

    if (c.strcmp(&buf, "yes\n") == 0) {
        out_tag.* = c.strdup("");
        return true;
    }
    if (c.strcmp(&buf, "remember\n") == 0) {
        _ = c.fprintf(libc.stdout,
            "Specify an identifier tag (or empty for default):\n");

        _ = c.fgets(&buf, buf.len, libc.stdin);
        const len = c.strlen(&buf);
        if (len > 1) {
            buf[len - 1] = 0; // strip \n
            const td_len = c.strlen(trust_domain);
            const tot = len + td_len + 2;
            const mem = c.malloc(tot) orelse return false;
            out_tag.* = @ptrCast(mem);
            prefix_ofs.* = td_len + 1;
            _ = c.snprintf(@ptrCast(mem), tot, "%s-%s", trust_domain, &buf);
        } else {
            prefix_ofs.* = 0;
            out_tag.* = c.strdup(trust_domain);
        }
        return true;
    }

    return false;
}

// anet_connect_to
// Edge-case outbound connect that ignores keystore enumeration.

pub export fn anet_connect_to(arg: *c.struct_anet_options) c.struct_anet_cl_connection {
    var res = c.struct_anet_cl_connection{
        .fd = -1,
        .state = null,
        .errmsg = null,
        .auth_failed = false,
    };

    var hints = std.mem.zeroes(Addrinfo);
    hints.ai_family = c.AF_UNSPEC;
    hints.ai_socktype = c.SOCK_STREAM;

    var addr: ?*Addrinfo = null;
    if (arg.host == null) {
        res.errmsg = c.strdup("missing host");
        return res;
    }

    const ec = getaddrinfo(arg.host, arg.port, &hints, &addr);
    if (ec != 0) {
        var buf: [128]u8 = undefined;
        const host = if (arg.host != null) arg.host else @as([*c]const u8, "(host missing)");
        _ = c.snprintf(&buf, buf.len, "couldn't resolve %s: %s\n",
            host, gai_strerror(ec));
        res.errmsg = c.strdup(&buf);
        return res;
    }

    // Retry connect() while arg->retry_count permits.
    while (true) {
        res.fd = anet_clfd(addr);
        if (res.fd != -1) break;
        if (arg.retry_count == 0) break;
        arg.retry_count -= 1;
        _ = c.sleep(1);
    }

    if (res.fd == -1) {
        var buf: [128]u8 = undefined;
        _ = c.snprintf(&buf, buf.len, "couldn't connect to %s:%s\n",
            arg.host, arg.port);
        res.errmsg = c.strdup(&buf);
        freeaddrinfo(addr);
        return res;
    }

    // Build state machine and run authentication. anet_cl_connection.state is
    // the anet_types opaque variant; cast from a12_types.
    res.state = @ptrCast(a12_client(@ptrCast(arg.opts)));
    freeaddrinfo(addr);

    if (anet_authenticate(@ptrCast(res.state.?), res.fd, res.fd, @ptrCast(&res.errmsg))) {
        var epn: [*c]u8 = undefined;
        if (c.asprintf(&epn, "%s:%s", arg.host, arg.port) > 0) {
            a12_set_endpoint(@ptrCast(res.state.?), @ptrCast(epn));
        }
        return res;
    }

    if (res.fd != -1) {
        _ = shutdown(res.fd, SHUT_RDWR);
        _ = c.close(res.fd);
    }

    res.auth_failed = true;
    res.fd = -1;
    a12_free(@ptrCast(res.state.?));
    res.state = null;
    return res;
}

// anet_cl_setup
// High-level outbound connect: honours keystore tag lookup when arg->key is set,
// otherwise falls back to the "default" entry and anet_connect_to.

pub export fn anet_cl_setup(arg: *c.struct_anet_options) c.struct_anet_cl_connection {
    var res = c.struct_anet_cl_connection{
        .fd = -1,
        .state = null,
        .errmsg = null,
        .auth_failed = false,
    };

    // Retry keystore open once (e.g. after a release/rebind in another worker).
    if (!c.a12helper_keystore_open(&arg.keystore)) {
        _ = c.a12helper_keystore_release();
        if (!c.a12helper_keystore_open(&arg.keystore)) {
            res.errmsg = c.strdup("couldn't open keystore\n");
            return res;
        }
    }

    if (arg.key) |key_nn| {
        var i: usize = 0;
        var host: [*c]u8 = undefined;
        var port: u16 = 0;

        // Seed the error with a lookup-failure message; cleared on the first
        // successful hostkey match, or propagated if no entry connects.
        {
            var buf: [128]u8 = undefined;
            _ = c.snprintf(&buf, buf.len, "keystore: no match for %s\n", key_nn);
            res.errmsg = c.strdup(&buf);
        }

        while (c.a12helper_keystore_hostkey(
            arg.key, i, @ptrCast(&arg.opts.*.priv_key), &host, &port))
        {
            i += 1;
            if (res.errmsg != null) {
                c.free(res.errmsg);
                res.errmsg = null;
            }

            // Dupe the options struct so we can edit it per-attempt.
            var tmpcfg = arg.*;
            if (!arg.ignore_key_host) {
                tmpcfg.host = host;
                tmpcfg.key = null;
            } else {
                tmpcfg.key = null;
            }

            // Port needs to go to getaddrinfo as a decimal service string.
            var pbuf: [8:0]u8 = std.mem.zeroes([8:0]u8);
            _ = c.snprintf(&pbuf, pbuf.len, "%" ++ c.PRIu16, port);
            tmpcfg.port = &pbuf;

            res = anet_connect_to(&tmpcfg);
            c.free(host);

            if (arg.ignore_key_host or res.errmsg == null) break;
        }

        return res;
    }

    // No tag specified — ensure a "default" entry exists, then connect directly.
    var outhost: [*c]u8 = undefined;
    var outport: u16 = 0;
    var pubk: [32]u8 = undefined;

    if (!c.a12helper_keystore_hostkey(
        "default", 0, @ptrCast(&arg.opts.*.priv_key), &outhost, &outport))
    {
        _ = c.a12helper_keystore_register("default", "127.0.0.1", 6680, &pubk, null);
        anetTrace(c.A12_TRACE_SECURITY, "creating_outbound_default", .{});

        // keystore_register writes a fresh random priv key to disk but leaves
        // our in-memory priv_key untouched — so without this re-lookup the
        // handshake would run with an uninitialised (all-zero) priv_key, and
        // every first-contact client across every install produces the same
        // deterministic zero-derived public key. That's observably bad: the
        // outbound hash `L+V9o0f…` was identical across fresh state dirs,
        // and servers with `-a 1` (accept ONE unknown key) correctly refused
        // the second client they saw as a replay. Re-read the just-written
        // key so the actual random bytes feed the handshake. Upstream C has
        // the same bug (frameserver/util/anet_helper.c:302) — they just
        // hadn't noticed because most flows reuse state. Fixing here only;
        // the C side can mirror if it matters later.
        if (!c.a12helper_keystore_hostkey(
            "default", 0, @ptrCast(&arg.opts.*.priv_key), &outhost, &outport))
        {
            // Register succeeded but readback failed — keystore is broken.
            // Propagate rather than ship a bogus handshake.
            res.errmsg = c.strdup("keystore: register/readback mismatch for 'default'\n");
            return res;
        }
        c.free(outhost);
    } else {
        c.free(outhost);
    }

    // Trace the outbound public key.
    x25519_public_key(@ptrCast(&arg.opts.*.priv_key), &pubk);
    var outl: usize = 0;
    if (a12helper_tob64(&pubk, 32, &outl)) |req| {
        anetTrace(c.A12_TRACE_SECURITY, "outbound=%s", .{req});
        std.heap.c_allocator.free(req[0..outl]);
    }

    return anet_connect_to(arg);
}

// anet_listen
// Blocking listen+accept loop. Returns only on failure; dispatch() is invoked
// for every inbound connection with a freshly allocated a12_state.

const DispatchFn = *const fn (
    S: *c.struct_a12_state, fd: c_int, tag: ?*anyopaque) callconv(.c) void;

pub export fn anet_listen(
    args: *c.struct_anet_options,
    errdst: ?*?[*:0]u8,
    dispatch: ?DispatchFn,
    tag: ?*anyopaque,
) bool {
    ignoreSignal(c.SIGPIPE);
    ignoreSignal(c.SIGCHLD);
    if (errdst) |e| e.* = null;

    // Address resolution.
    var hints = std.mem.zeroes(Addrinfo);
    hints.ai_flags = AI_PASSIVE;

    var addr: ?*Addrinfo = null;
    var ec = getaddrinfo(args.host, args.port, &hints, &addr);
    if (ec != 0) {
        if (errdst) |e|
            _ = c.asprintf(@ptrCast(e),
                "couldn't resolve address: %s\n", gai_strerror(ec));
        return false;
    }

    const ainfo = addr.?;
    var hostaddr: [NI_MAXHOST]u8 = undefined;
    var hostport: [NI_MAXSERV]u8 = undefined;
    ec = getnameinfo(
        ainfo.ai_addr, ainfo.ai_addrlen,
        &hostaddr, hostaddr.len,
        &hostport, hostport.len,
        NI_NUMERICSERV | NI_NUMERICHOST,
    );
    if (ec != 0) {
        if (errdst) |e|
            _ = c.asprintf(@ptrCast(e),
                "couldn't resolve address: %s\n", gai_strerror(ec));
        freeaddrinfo(addr);
        return false;
    }

    // Socket + bind + listen.
    const sockin_fd = c.socket(ainfo.ai_family, c.SOCK_STREAM, 0);
    if (sockin_fd == -1) {
        if (errdst) |e|
            _ = c.asprintf(@ptrCast(e),
                "couldn't create socket: %s\n", c.strerror(ec));
        freeaddrinfo(addr);
        return false;
    }

    // SOCK_CLOEXEC isn't universally available on the OS X build leg.
    const flags = c.fcntl(sockin_fd, c.F_GETFD);
    if (flags != -1) {
        _ = c.fcntl(sockin_fd, c.F_SETFD, flags | c.FD_CLOEXEC);
    }

    var optval: c_int = 1;
    _ = c.setsockopt(sockin_fd, c.SOL_SOCKET, c.SO_REUSEADDR,
        &optval, @sizeOf(c_int));
    _ = c.setsockopt(sockin_fd, c.SOL_SOCKET, c.SO_REUSEPORT,
        &optval, @sizeOf(c_int));
    _ = c.setsockopt(sockin_fd, c.IPPROTO_TCP, c.TCP_NODELAY,
        &optval, @sizeOf(c_int));

    ec = c.bind(sockin_fd, ainfo.ai_addr, ainfo.ai_addrlen);
    if (ec != 0) {
        if (errdst) |e|
            _ = c.asprintf(@ptrCast(e),
                "error binding (%s:%s): %s\n",
                @as([*c]u8, &hostaddr), @as([*c]u8, &hostport),
                c.strerror(c.__errno_location().*));
        freeaddrinfo(addr);
        _ = c.close(sockin_fd);
        return false;
    }

    ec = c.listen(sockin_fd, 5);
    if (ec != 0) {
        if (errdst) |e|
            _ = c.asprintf(@ptrCast(e),
                "couldn't listen (%s:%s): %s\n",
                @as([*c]u8, &hostaddr), @as([*c]u8, &hostport),
                c.strerror(c.__errno_location().*));
        _ = c.close(sockin_fd);
        freeaddrinfo(addr);
        // Note: upstream C falls through to the accept loop after a listen
        // failure; we preserve that behaviour bit-for-bit.
    }

    // accept loop: never returns on success.
    const disp = dispatch orelse return false;
    while (true) {
        var in_addr: c.struct_sockaddr = undefined;
        var addrlen: c.socklen_t = @sizeOf(c.struct_sockaddr);

        const infd = c.accept(sockin_fd, &in_addr, &addrlen);
        const ast = a12_server(@ptrCast(args.opts)) orelse {
            if (errdst) |e|
                _ = c.asprintf(@ptrCast(e),
                    "Couldn't allocate client state machine\n");
            _ = c.close(infd);
            return false;
        };

        var ha: [NI_MAXHOST]u8 = undefined;
        _ = getnameinfo(&in_addr, addrlen,
            &ha, ha.len, null, 0, NI_NUMERICHOST);
        a12_set_endpoint(ast, c.strdup(&ha));

        disp(ast, infd, tag);
    }
}
