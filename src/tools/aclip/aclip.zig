// arcan-clipboard (aclip) — Zig port of aclip.c.
// Command-line interface to Arcan clipboards. See aclip.1 for the synopsis.
//
// Copyright 2017-2018, Björn Ståhl (original C). Zig port, 2026.
// License: 3-Clause BSD, see COPYING file in arcan source repository.

const std = @import("std");
const builtin = @import("builtin");
const c = @import("shmif_types");
const shmif = @import("shmif_api");
const libc = @import("posix");

// Local re-exports of shmif fns so the existing call sites compile
// untouched. The single source of truth is src/shmif/shmif_api.zig.
const arcan_shmif_open_ext = shmif.arcan_shmif_open_ext;
const arcan_shmif_signal = shmif.arcan_shmif_signal;
const arcan_shmif_wait = shmif.arcan_shmif_wait;
const arcan_shmif_drop = shmif.arcan_shmif_drop;
const arcan_shmif_pushutf8 = shmif.arcan_shmif_pushutf8;

// POSIX: SIGCHLD == 17 on linux/glibc/musl; SIG_IGN == (void(*)(int))1.
const SIGCHLD: c_int = 17;
const SigHandler = libc.SigHandler;
const SIG_IGN: ?SigHandler = @ptrFromInt(@as(usize, 1));
const SIG_ERR: ?SigHandler = @ptrFromInt(std.math.maxInt(usize));

// event helpers (convenience accessors for shmif_types.arcan_event)

fn evCategoryPtr(ev: *c.arcan_event) *u8 {
    return &ev.unnamed_0.unnamed_0.category;
}

fn evExt(ev: *c.arcan_event) *c.arcan_extevent {
    return &ev.unnamed_0.unnamed_0.unnamed_0.ext;
}

fn evTgt(ev: *c.arcan_event) *c.arcan_tgtevent {
    return &ev.unnamed_0.unnamed_0.unnamed_0.tgt;
}

fn evCategory(ev: *const c.arcan_event) u8 {
    return ev.unnamed_0.unnamed_0.category;
}

// dms byte in shmif_page — offset 3 from start of `addr`.
fn pageDms(addr: *anyopaque) u8 {
    const base: [*]volatile u8 = @ptrCast(addr);
    return base[3];
}

// parentevq front/back — offsets 32616/32617 (see shmif_offsets.zig).
const PARENTEVQ_FRONT_OFS: usize = 32616;
const PARENTEVQ_BACK_OFS: usize = 32617;

fn pageParentFront(addr: *anyopaque) u8 {
    const base: [*]volatile u8 = @ptrCast(addr);
    return base[PARENTEVQ_FRONT_OFS];
}

fn pageParentBack(addr: *anyopaque) u8 {
    const base: [*]volatile u8 = @ptrCast(addr);
    return base[PARENTEVQ_BACK_OFS];
}

// state

const State = struct {
    separator: []const u8 = "",
    outf_cmd: ?*std.c.FILE = null, // persistent FILE* used by exec-dispatch
};

// paste: push a message over the clipboard segment

fn paste(state: *State, out: *c.struct_arcan_shmif_cont, msg: []const u8) void {
    _ = state;
    if (out.unnamed_0.vidp == null) return;
    if (msg.len == 0) return;

    var msgev = c.arcan_event.zeroes();
    evCategoryPtr(&msgev).* = @intCast(c.EVENT_EXTERNAL);
    evExt(&msgev).kind = c.EVENT_EXTERNAL_MESSAGE;

    _ = arcan_shmif_pushutf8(out, &msgev, msg.ptr, msg.len);
}

// incoming MESSAGE event → raw FILE*

/// Returns true when the terminating (non-continuation) part of a
/// multipart message has been written to `outf`.
fn writeEv(ev: *c.arcan_event, outf: *std.c.FILE, separator: []const u8) bool {
    const tgt = evTgt(ev);
    const msg: [*]const u8 = @ptrCast(&tgt.unnamed_0.message);
    const cap = @sizeOf(@TypeOf(tgt.unnamed_0.message));

    if (tgt.ioevs[0].iv != 0) {
        // continuation — find NUL or end of buffer
        var i: usize = 0;
        while (i < cap) : (i += 1) {
            if (msg[i] == 0) break;
        }
        if (i == 0) return false;
        var write_len = i;
        if (i == cap) write_len = cap; // already bounded, keep
        _ = std.c.fwrite(msg, write_len, 1, outf);
        return false;
    }

    // final fragment: write NUL-terminated contents then separator
    var i: usize = 0;
    while (i < cap and msg[i] != 0) : (i += 1) {}
    _ = std.c.fwrite(msg, i, 1, outf);
    if (separator.len != 0)
        _ = std.c.fwrite(separator.ptr, separator.len, 1, outf);
    _ = libc.fflush(outf);
    return true;
}

// event dispatch variants

/// Returns 1 when a complete paste was flushed, -1 on EXIT, 0 otherwise.
fn dispatchEventOutf(ev: *c.arcan_event, outf: *std.c.FILE, state: *State) i32 {
    const tgt = evTgt(ev);
    switch (tgt.kind) {
        c.TARGET_COMMAND_MESSAGE => {
            if (writeEv(ev, outf, state.separator)) return 1;
        },
        c.TARGET_COMMAND_EXIT => return -1,
        // NEWSEGMENT / BCHUNK_IN / BCHUNK_OUT / STEPFRAME: not handled yet.
        else => {},
    }
    return 0;
}

fn dispatchEventOutcmd(ev: *c.arcan_event, cmd: [:0]const u8, state: *State) i32 {
    const tgt = evTgt(ev);
    switch (tgt.kind) {
        c.TARGET_COMMAND_MESSAGE => {
            if (state.outf_cmd == null) {
                state.outf_cmd = libc.popen(cmd.ptr, "w") orelse return -1;
            }
            const f = state.outf_cmd.?;
            _ = writeEv(ev, f, state.separator);
            if (tgt.ioevs[0].iv == 0) {
                _ = libc.pclose(f);
                state.outf_cmd = null;
                return 1;
            }
        },
        c.TARGET_COMMAND_EXIT => return -1,
        else => {},
    }
    return 0;
}

// usage / help

fn usage() void {
    const txt = "Usage: aclip [-hioe:s:l:d:]\n" ++
        "-h    \t--help         \tthis text\n" ++
        "-i    \t--in           \tread/validate UTF-8 from standard input and copy to clipboard\n" ++
        "-I arg\t--in-data arg  \tread/validate UTF-8 and copy to clipboard\n" ++
        "-o    \t--out          \tflush received pastes to stdout\n" ++
        "-e arg\t--exec arg     \tpopen [arg] on received pastes and flush to its stdin\n" ++
        "-p arg\t--separator arg\ttreat [arg] as paste- separator separator (-l >= 0)\n" ++
        "-l arg\t--loop arg     \texit after [arg] discrete paste operations (-0, never exit)\n" ++
        "-s    \t--silent       \tclose stdout and fork into background\n" ++
        "-d arg\t--display arg  \tuse [arg] as connection path istead of ARCAN_CONNPATH env\n";
    _ = std.c.printf("%s", @as([*c]const u8, @ptrCast(txt)));
}

// getopt-style argv parsing
// Handles short (`-x`, `-xarg`, `-x arg`) and long (`--name`, `--name=arg`,
// `--name arg`) forms. Mirrors getopt_long behaviour enough for aclip.

const Opt = struct { short: u8, long: []const u8, arg: bool };

const OPTS = [_]Opt{
    .{ .short = 'h', .long = "help", .arg = false },
    .{ .short = 'i', .long = "in", .arg = false },
    .{ .short = 'I', .long = "in-data", .arg = true },
    .{ .short = 'o', .long = "out", .arg = false },
    .{ .short = 'e', .long = "exec", .arg = true },
    .{ .short = 'p', .long = "separator", .arg = true },
    .{ .short = 'l', .long = "loop", .arg = true },
    .{ .short = 'd', .long = "display", .arg = true },
    .{ .short = 's', .long = "silent", .arg = false },
};

const ParsedOpt = struct { which: u8, arg: ?[]const u8 };

const ParseCtx = struct {
    argv: [][:0]const u8,
    idx: usize = 1,
    short_ofs: usize = 0, // position within current -xyz cluster
    err: bool = false,
};

fn nextOpt(ctx: *ParseCtx) ?ParsedOpt {
    while (true) {
        if (ctx.short_ofs != 0) {
            const cur = ctx.argv[ctx.idx - 1];
            if (ctx.short_ofs < cur.len) {
                const ch = cur[ctx.short_ofs];
                ctx.short_ofs += 1;
                const opt = findShort(ch) orelse {
                    _ = libc.fprintf(libc.stderr, "aclip: unknown option -%c\n", @as(c_int, ch));
                    ctx.err = true;
                    return null;
                };
                if (opt.arg) {
                    if (ctx.short_ofs < cur.len) {
                        const a = cur[ctx.short_ofs..];
                        ctx.short_ofs = 0;
                        return .{ .which = opt.short, .arg = a };
                    }
                    ctx.short_ofs = 0;
                    if (ctx.idx >= ctx.argv.len) {
                        _ = libc.fprintf(libc.stderr, "aclip: option -%c requires an argument\n", @as(c_int, ch));
                        ctx.err = true;
                        return null;
                    }
                    const a = ctx.argv[ctx.idx];
                    ctx.idx += 1;
                    return .{ .which = opt.short, .arg = a };
                }
                return .{ .which = opt.short, .arg = null };
            }
            ctx.short_ofs = 0;
        }

        if (ctx.idx >= ctx.argv.len) return null;
        const cur = ctx.argv[ctx.idx];
        ctx.idx += 1;

        if (cur.len < 2 or cur[0] != '-') continue; // ignore positional
        if (std.mem.eql(u8, cur, "--")) return null;

        if (cur[1] == '-') {
            // long option
            const rest = cur[2..];
            var name: []const u8 = rest;
            var inline_arg: ?[]const u8 = null;
            if (std.mem.indexOfScalar(u8, rest, '=')) |eq| {
                name = rest[0..eq];
                inline_arg = rest[eq + 1 ..];
            }
            const opt = findLong(name) orelse {
                _ = libc.fprintf(libc.stderr, "aclip: unknown option --%.*s\n", @as(c_int, @intCast(name.len)), name.ptr);
                ctx.err = true;
                return null;
            };
            if (opt.arg) {
                if (inline_arg) |a| return .{ .which = opt.short, .arg = a };
                if (ctx.idx >= ctx.argv.len) {
                    _ = libc.fprintf(libc.stderr, "aclip: option --%s requires an argument\n", @as([*:0]const u8, @ptrCast(opt.long.ptr)));
                    ctx.err = true;
                    return null;
                }
                const a = ctx.argv[ctx.idx];
                ctx.idx += 1;
                return .{ .which = opt.short, .arg = a };
            }
            return .{ .which = opt.short, .arg = null };
        }

        // short cluster -xyz
        ctx.short_ofs = 1;
    }
}

fn findShort(ch: u8) ?Opt {
    for (OPTS) |o| if (o.short == ch) return o;
    return null;
}

fn findLong(name: []const u8) ?Opt {
    for (OPTS) |o| if (std.mem.eql(u8, o.long, name)) return o;
    return null;
}

// main

pub fn main() u8 {
    var gpa = std.heap.c_allocator;

    // pull argv as null-terminated slices
    const raw_argv = std.os.argv;
    if (raw_argv.len == 1) {
        usage();
        return 1;
    }

    var argv_list = std.ArrayList([:0]const u8).empty;
    defer argv_list.deinit(gpa);
    for (raw_argv) |a| {
        const s = std.mem.span(a);
        argv_list.append(gpa, s) catch return 1;
    }

    var use_stdin = false;
    var use_stdout = false;
    var silence = false;
    var exec_cmd: ?[:0]u8 = null;
    var copy_arg: ?[:0]u8 = null;
    var loop_counter: i32 = -1;
    var separator_buf: ?[:0]u8 = null;
    defer {
        if (exec_cmd) |s| gpa.free(s);
        if (copy_arg) |s| gpa.free(s);
        if (separator_buf) |s| gpa.free(s);
    }

    var ctx = ParseCtx{ .argv = argv_list.items };
    while (nextOpt(&ctx)) |opt| switch (opt.which) {
        'h' => {
            usage();
            return 0;
        },
        'i' => use_stdin = true,
        'o' => use_stdout = true,
        's' => silence = true,
        'I' => {
            if (copy_arg) |old| gpa.free(old);
            copy_arg = dupZ(gpa, opt.arg orelse "") catch return 1;
        },
        'e' => {
            if (exec_cmd) |old| gpa.free(old);
            exec_cmd = dupZ(gpa, opt.arg orelse "") catch return 1;
        },
        'd' => {
            const v = dupZ(gpa, opt.arg orelse "") catch return 1;
            defer gpa.free(v);
            _ = libc.setenv("ARCAN_CONNPATH", v.ptr, 1);
        },
        'l' => {
            const s = opt.arg orelse "";
            loop_counter = std.fmt.parseInt(i32, s, 10) catch 0;
        },
        'p' => {
            if (separator_buf) |old| gpa.free(old);
            separator_buf = dupZ(gpa, opt.arg orelse "") catch return 1;
        },
        else => {},
    };
    if (ctx.err) return 1;

    if (!use_stdin and !use_stdout and copy_arg == null) {
        _ = libc.fprintf(libc.stderr, "neither [-i], [-I arg] nor [-o] specified.\n");
        usage();
        return 1;
    }

    var state = State{};
    if (separator_buf) |s| state.separator = s;

    // open clipboard segment
    const ext = c.struct_shmif_open_ext{
        .@"type" = @intCast(c.SEGID_CLIPBOARD),
        .title = "",
        .ident = "",
    };
    var con = arcan_shmif_open_ext(
        @bitCast(c.SHMIF_ACQUIRE_FATALFAIL),
        null,
        ext,
        @sizeOf(c.struct_shmif_open_ext),
    );
    _ = arcan_shmif_signal(&con, @intCast(c.SHMIF_SIGVID));

    if (libc.signal(SIGCHLD, SIG_IGN) == SIG_ERR) {
        _ = libc.fprintf(libc.stderr, "ign on sigchld failed\n");
        return 1;
    }

    if (silence) {
        _ = std.c.fclose(libc.stdout);
        if (libc.fork() != 0) return 0;
    }

    // single copy-arg path: push, then drain
    if (copy_arg) |ca| paste(&state, &con, ca);

    // both -i and -o: fork, child handles output, parent handles input
    var drop_exit = true;
    if (use_stdin and use_stdout) {
        const pv = libc.fork();
        if (pv > 0) {
            use_stdin = false; // parent keeps -o
        } else if (pv == 0) {
            use_stdout = false; // child keeps -i
            drop_exit = false;
        }
    }

    // -i: read stdin and forward as paste events
    if (use_stdin) {
        // message payload is 78 bytes; match C: 4x that as buffer
        var buf: [78 * 4]u8 = undefined;
        while (libc.feof(libc.stdin) == 0 and libc.ferror(libc.stdin) == 0) {
            const ntr = std.c.fread(&buf, 1, buf.len - 1, libc.stdin);
            buf[ntr] = 0;
            if (ntr != 0 and ntr < buf.len - 1) {
                paste(&state, &con, buf[0..ntr]);
            }
        }
    }

    // -o: block on events and flush pastes
    if (use_stdout) {
        var ev = c.arcan_event.zeroes();
        const out_file = libc.stdout;
        while (arcan_shmif_wait(&con, &ev) > 0) {
            if (evCategory(&ev) == @as(u8, @intCast(c.EVENT_TARGET))) {
                const sv = if (exec_cmd) |cmd|
                    dispatchEventOutcmd(&ev, cmd, &state)
                else
                    dispatchEventOutf(&ev, out_file, &state);
                if (sv == -1 or (sv == 1 and loop_counter == 1)) break;
                if (loop_counter > 0) loop_counter -= 1;
            }
        }
    }

    // Drain pending events before dropping the segment, otherwise the
    // compositor may tear down before our single paste arrives.
    if (drop_exit) {
        if (con.addr) |addr| {
            while (pageDms(addr) != 0 and
                pageParentFront(addr) != pageParentBack(addr))
            {
                _ = arcan_shmif_signal(&con, @intCast(c.SHMIF_SIGVID));
            }
        }
        arcan_shmif_drop(&con);
    }

    return 0;
}

fn dupZ(alloc: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const out = try alloc.allocSentinel(u8, s.len, 0);
    @memcpy(out, s);
    return out;
}
