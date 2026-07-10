// afsrv_bun — Phase 3e scaffold.
//
// When invoked without an entry path, paints the Phase-2 gradient
// skeleton (kept so the cell still has a recognizable visual when
// no TS file is given). When invoked WITH an entry path on argv,
// hands off to bun_runtime; while Phase 3e-link is pending the
// runtime returns Error.NotLinked and we emit a clear marker so
// shmon shows progress through the hand-off, then fall back to
// the gradient loop so the cell still has visible output.
//
// argv resolution: scan std.os.argv for the first element that
// ends in a JS/TS extension and isn't a reserved frameserver mode
// token. Works in all of:
//   afsrv_bun /path/to/main.ts [args...]            # standalone
//   afsrv_bun bun /path/to/main.ts [args...]        # chainloaded
//   afsrv_bun mode=bun /path/to/main.ts [args...]   # explicit
// See fossil ticket 0036 (`bugs show 0036-afsrv-bun-frameserver`) Phase 3e for the full plan.

const std = @import("std");
const c = @import("shmif_types");
const bun_runtime = @import("bun_runtime");

extern "c" var stdout: *anyopaque;
extern "c" var stderr: *anyopaque;

extern "c" fn arcan_shmif_wait(ctx: *c.arcan_shmif_cont, ev: *c.arcan_event) c_int;
extern "c" fn arcan_shmif_enqueue(ctx: *c.arcan_shmif_cont, ev: *const c.arcan_event) c_int;
extern "c" fn arcan_shmif_signal(ctx: *c.arcan_shmif_cont, mask: c_int) c_uint;
extern "c" fn arcan_shmif_resize(ctx: *c.arcan_shmif_cont, w: usize, h: usize) bool;

const canvas_w: usize = 480;
const canvas_h: usize = 240;

fn dump_help() void {
    _ = c.fprintf(stdout,
        "afsrv_bun: arcan frameserver hosting Bun-based agents.\n" ++
        "\n" ++
        "Phase 3e scaffold — when given an entry path on argv,\n" ++
        "drives bun_runtime; until Phase 3e-link wires bun_obj\n" ++
        "into the binary the runtime fails with NotLinked and\n" ++
        "afsrv_bun falls back to the Phase-2 gradient skeleton.\n" ++
        "\n" ++
        "Without an entry path, paints a gradient and waits for\n" ++
        "TARGET_COMMAND_EXIT.\n");
}

fn pack_register(ev: *c.arcan_event, title: []const u8) void {
    ev.* = c.arcan_event.zeroes();
    ev.category().* = c.EVENT_EXTERNAL;
    ev.ext().kind = c.EVENT_EXTERNAL_REGISTER;
    const reg = ev.ext().registr();
    reg.kind = c.SEGID_APPLICATION;
    const max = reg.title.len - 1;
    const n = @min(title.len, max);
    @memcpy(reg.title[0..n], title[0..n]);
    reg.title[n] = 0;
}

fn pack_message(ev: *c.arcan_event, text: []const u8) void {
    ev.* = c.arcan_event.zeroes();
    ev.category().* = c.EVENT_EXTERNAL;
    ev.ext().kind = c.EVENT_EXTERNAL_MESSAGE;
    const msg = ev.ext().message();
    const max = msg.data.len - 1;
    const n = @min(text.len, max);
    @memcpy(msg.data[0..n], text[0..n]);
    msg.data[n] = 0;
    msg.multipart = 0;
}

/// Paint a gradient onto vidp, with a phase-marker stripe along
/// the top so the user can tell at a glance which afsrv_bun
/// generation is rendering.
fn paint_frame(shms: *c.arcan_shmif_cont, tick: u32) void {
    var vp: [*c]u32 = shms.unnamed_0.vidp;
    const w = shms.w;
    const h = shms.h;
    const stripe_h: usize = 24;

    var y: usize = 0;
    while (y < h) : (y += 1) {
        var x: usize = 0;
        while (x < w) : (x += 1) {
            const px: u32 = if (y < stripe_h) blk: {
                const r: u8 = @intCast((tick *% 3) & 0xff);
                break :blk c.SHMIF_RGBA(0xff, @as(u8, 0x33) +% r, 0xaa, 0xff);
            } else blk: {
                const yy = y - stripe_h;
                const max_y = if (h > stripe_h) h - stripe_h else 1;
                const r: u8 = @intCast((x *% 255) / w);
                const g: u8 = @intCast((yy *% 255) / max_y);
                const b: u8 = @intCast((tick *% 5) & 0xff);
                break :blk c.SHMIF_RGBA(r, g, b, 0xff);
            };
            vp[y * w + x] = px;
        }
    }

    _ = arcan_shmif_signal(shms, c.SHMIF_SIGVID);
}

/// Walk std.os.argv looking for the first arg that ends in a known
/// JS/TS extension and isn't a reserved frameserver mode token.
fn resolveEntry() ?[]const u8 {
    const argv = std.os.argv;
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        if (i == 0) continue;
        const a = std.mem.span(argv[i]);
        if (std.mem.eql(u8, a, "bun")) continue;
        if (std.mem.eql(u8, a, "terminal")) continue;
        if (std.mem.eql(u8, a, "decode")) continue;
        if (std.mem.eql(u8, a, "encode")) continue;
        if (std.mem.eql(u8, a, "remoting")) continue;
        if (std.mem.eql(u8, a, "game")) continue;
        if (std.mem.eql(u8, a, "avfeed")) continue;
        if (std.mem.eql(u8, a, "net")) continue;
        if (std.mem.eql(u8, a, "probe")) continue;
        if (std.mem.startsWith(u8, a, "mode=")) continue;
        if (std.mem.endsWith(u8, a, ".ts")) return a;
        if (std.mem.endsWith(u8, a, ".tsx")) return a;
        if (std.mem.endsWith(u8, a, ".js")) return a;
        if (std.mem.endsWith(u8, a, ".mjs")) return a;
        if (std.mem.endsWith(u8, a, ".cjs")) return a;
    }
    return null;
}

fn run_skeleton_loop(shms: *c.arcan_shmif_cont) c_int {
    var tick: u32 = 0;
    paint_frame(shms, tick);
    var ev: c.arcan_event = undefined;
    while (arcan_shmif_wait(shms, &ev) != 0) {
        if (ev.category().* == c.EVENT_TARGET) {
            if (ev.tgt().kind == c.TARGET_COMMAND_EXIT) {
                _ = c.fprintf(stdout, "afsrv_bun: server requested exit\n");
                return 0;
            }
            tick +%= 1;
            paint_frame(shms, tick);
        }
    }
    return 0;
}

export fn afsrv_bun(con: ?*c.arcan_shmif_cont, args: ?*c.arg_arr) callconv(.c) c_int {
    _ = args;
    const con_ptr = con orelse {
        dump_help();
        return 1;
    };
    var shms: c.arcan_shmif_cont = con_ptr.*;

    if (!arcan_shmif_resize(&shms, canvas_w, canvas_h)) {
        _ = c.fprintf(stderr, "afsrv_bun: resize to %zux%zu failed\n",
            @as(usize, canvas_w), @as(usize, canvas_h));
        return 1;
    }

    var ev: c.arcan_event = undefined;
    pack_register(&ev, "afsrv_bun");
    _ = arcan_shmif_enqueue(&shms, &ev);

    if (resolveEntry()) |path| {
        pack_message(&ev, "afsrv_bun:phase=3e:vm-up");
        _ = arcan_shmif_enqueue(&shms, &ev);

        if (bun_runtime.init()) |runtime_value| {
            var rt = runtime_value;
            defer bun_runtime.deinit(&rt);

            if (bun_runtime.runEntryPoint(&rt, path)) |_| {
                pack_message(&ev, "afsrv_bun:phase=3e:eval-ok");
                _ = arcan_shmif_enqueue(&shms, &ev);
            } else |err| {
                switch (err) {
                    error.EntryNotFound => pack_message(&ev,
                        "afsrv_bun:phase=3e:entry-not-found"),
                    else => pack_message(&ev,
                        "afsrv_bun:phase=3e:eval-failed"),
                }
                _ = arcan_shmif_enqueue(&shms, &ev);
            }

            pack_message(&ev, "afsrv_bun:phase=3e:exit");
            _ = arcan_shmif_enqueue(&shms, &ev);
            return 0;
        } else |err| {
            switch (err) {
                error.NotLinked => pack_message(&ev,
                    "afsrv_bun:phase=3e:bun-not-linked"),
                else => pack_message(&ev,
                    "afsrv_bun:phase=3e:init-failed"),
            }
            _ = arcan_shmif_enqueue(&shms, &ev);
            return run_skeleton_loop(&shms);
        }
    }

    pack_message(&ev, "afsrv_bun:hello:phase=2:skeleton");
    _ = arcan_shmif_enqueue(&shms, &ev);
    return run_skeleton_loop(&shms);
}
