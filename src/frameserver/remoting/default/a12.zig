// Zig port of remoting/default/a12.c — a12-client remoting backend.
// Connects to a remote a12 endpoint (host/port or keystore tag) and maps
// the incoming A/V channel onto the local shmif segment, forwarding IO
// events upstream. anet_cl_setup handles connect + auth; the loop below
// is a plain poll/unpack/flush proxy.
// Copyright: Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    pub const arcan_shmif_cont = shmif.arcan_shmif_cont;
    pub const arcan_event = shmif.arcan_event;
    pub const arg_arr = shmif.struct_arg_arr;
    pub const arg_lookup = shmif.arg_lookup;
    pub const arcan_shmif_poll = shmif.arcan_shmif_poll;
    pub const arcan_shmif_drop = shmif.arcan_shmif_drop;
    pub const arcan_shmif_last_words = shmif.arcan_shmif_last_words;
    pub const poll = libc.poll;
    pub const read = libc.read;
    pub const write = libc.write;
    pub const struct_pollfd = libc.struct_pollfd;
    pub const POLLIN = libc.POLLIN;
    pub const POLLERR = libc.POLLERR;
    pub const POLLNVAL = libc.POLLNVAL;
    pub const POLLHUP = libc.POLLHUP;
    pub const EINTR = libc.EINTR;
    pub const EAGAIN = libc.EAGAIN;
    pub const strtol = libc.strtol;
    pub const fprintf = libc.fprintf;
    pub extern "c" var stderr: *libc.FILE;
    pub extern "c" var stdout: *libc.FILE;
};

fn errnoVal() c_int {
    return std.c._errno().*;
}

fn on_cl_event(
    cont: ?*a12.arcan_shmif_cont,
    chid: c_int,
    ev_opt: ?*a12.arcan_event,
    tag: ?*anyopaque,
) callconv(.c) void {
    _ = cont;
    _ = chid;
    const S: ?*a12.a12_state = @ptrCast(@alignCast(tag));
    const ev: *shmif.arcan_event = @ptrCast(ev_opt orelse return);

    if (ev.category().* == shmif.EVENT_EXTERNAL) {
        switch (@as(c_int, @intCast(ev.ext().kind))) {
            shmif.EVENT_EXTERNAL_REGISTER => {
                var out = shmif.arcan_event.zeroes();
                out.category().* = @intCast(shmif.EVENT_TARGET);
                out.tgt().kind = shmif.TARGET_COMMAND_ACTIVATE;
                _ = a12.a12_channel_enqueue(S, @ptrCast(&out));
            },
            else => {},
        }
    }

    // REGISTER needs an ACTIVATE after any known initials are sent; those
    // initials can (somewhat) be extracted from the cont above.
}

fn main_loop(C: *c.arcan_shmif_cont, S: ?*a12.a12_state, fd: c_int) void {
    // flush incoming data, flush event loop, flush outgoing data with a
    // poll as trigger
    var inbuf: [9000]u8 = undefined;
    var outbuf: [*c]u8 = null;
    var outbuf_sz: usize = 0;

    const errmask: c_short = @intCast(c.POLLERR | c.POLLNVAL | c.POLLHUP);
    var fds = [2]c.struct_pollfd{
        .{ .fd = fd, .events = @as(c_short, @intCast(c.POLLIN)) | errmask, .revents = 0 },
        .{ .fd = C.epipe, .events = @as(c_short, @intCast(c.POLLIN)) | errmask, .revents = 0 },
    };

    // just map incoming A/V buffers to the segment
    a12.a12_set_destination(S, @ptrCast(C), 0);

    outer: while (-1 != c.poll(&fds, 2, -1)) {
        if ((fds[0].revents & errmask) != 0 or (fds[1].revents & errmask) != 0)
            break;

        // incoming data into state machine
        if ((fds[0].revents & @as(c_short, @intCast(c.POLLIN))) != 0) {
            const nr = c.read(fds[0].fd, &inbuf, inbuf.len);
            if (nr > 0)
                a12.a12_unpack(S, &inbuf, @intCast(nr), S, on_cl_event);
        }

        // flush any events; the ones requiring resource allocation on both
        // sides are data transfers and clipboard requests
        var ev: shmif.arcan_event = shmif.arcan_event.zeroes();
        while (c.arcan_shmif_poll(C, &ev) > 0) {
            // forward IO, shutdown on EXIT
            if (ev.category().* == shmif.EVENT_IO) {
                _ = a12.a12_channel_enqueue(S, @ptrCast(&ev));
                continue;
            }

            if (ev.category().* != shmif.EVENT_TARGET)
                continue;

            switch (@as(c_int, @intCast(ev.tgt().kind))) {
                shmif.TARGET_COMMAND_EXIT => a12.a12_channel_shutdown(S, ""),
                else => {},
            }
        }

        outbuf_sz = a12.a12_flush(S, &outbuf, @intCast(a12.A12_FLUSH_ALL));
        while (outbuf_sz > 0) {
            const nw = c.write(fd, outbuf, outbuf_sz);
            if (-1 == nw) {
                const err = errnoVal();
                if (err != c.EINTR and err != c.EAGAIN)
                    break :outer;
                continue;
            }
            outbuf += @intCast(nw);
            outbuf_sz -= @intCast(nw);
        }
    }

    c.arcan_shmif_drop(C);
    _ = a12.a12_free(S);
}

fn dump_help(reason: [*:0]const u8) void {
    _ = c.fprintf(c.stdout,
        \\Error: %s
        \\Environment variables:
        \\ARCAN_CONNPATH=path_to_server
        \\ARCAN_ARG=packed_args (key1=value:key2:key3=value)
        \\
        \\Accepted packed_args:
        \\   key        value        description
        \\---------  -----------  -----------------
        \\ pass       val          use this (7-bit ascii) password for auth
        \\ host       hostname     connect to the specified host
        \\ port       portnum      use the specified port for connecting
        \\ tag        keyid        specify keystore identifier (can set host)
        \\ trace      level        set trace mask (see arcan-net for values) for debug
        \\ store      path         path to keystore base
        \\ cache      path         path to binary file cache
        \\---------  -----------  ----------------
        \\
    , reason);
}

export fn run_a12(cont: ?*c.arcan_shmif_cont, args: ?*c.arg_arr) c_int {
    var host: [*c]const u8 = null;
    var port: [*c]const u8 = "6680";
    var keyid: [*c]const u8 = null;

    const opts: [*c]anet.struct_a12_context_options =
        @ptrCast(@alignCast(a12.a12_sensitive_alloc(@sizeOf(anet.struct_a12_context_options))));

    _ = c.arg_lookup(@ptrCast(args), "host", 0, &host);
    _ = c.arg_lookup(@ptrCast(args), "tag", 0, &keyid);

    if (host == null and keyid == null) {
        c.arcan_shmif_last_words(cont, "missing host or key argument");
        dump_help("missing host or key argument");
        return 1;
    }

    var tmp: [*c]const u8 = null;
    if (c.arg_lookup(@ptrCast(args), "port", 0, &tmp)) {
        if (tmp == null or tmp[0] == 0) {
            c.arcan_shmif_last_words(cont, "missing or invalid port value");
            dump_help("missing or invalid port value");
            return 1;
        }
        port = tmp;
    }

    if (c.arg_lookup(@ptrCast(args), "trace", 0, &tmp) and tmp != null) {
        const arg = c.strtol(tmp, null, 10);
        a12.a12_set_trace_level(@intCast(arg), @ptrCast(c.stderr));
    }

    // after this point access to the keystore can be revoked; ideally this
    // information would come from arcan as well, to consider when afsrv_net
    // is updated
    var netarg = anet.struct_anet_options{
        .host = if (host != null) std.mem.span(@as([*:0]const u8, @ptrCast(host))) else null,
        .port = if (port != null) std.mem.span(@as([*:0]const u8, @ptrCast(port))) else null,
        .key = if (keyid != null) std.mem.span(@as([*:0]const u8, @ptrCast(keyid))) else null,
        .opts = opts,
    };

    const con = anet.anet_cl_setup(&netarg);

    if (con.state == null) {
        c.arcan_shmif_last_words(cont, @ptrCast(con.errmsg));
        _ = c.fprintf(c.stderr, "%s\n", con.errmsg);
        return 1;
    }

    main_loop(cont.?, @ptrCast(con.state), con.fd);

    return 0;
}
