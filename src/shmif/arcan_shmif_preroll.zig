// Zig reimplementation of arcan_shmif_preroll.c
// Drop-in C-ABI-compatible replacement for preroll functions.
//
// Exports: shmifint_drop_initial, shmifint_preroll_loop
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const off = @import("shmif_offsets");
const c = @import("shmif_types");

// Extern C declarations

extern fn close(fd: c_int) c_int;
extern fn strcmp(a: [*c]const u8, b: [*c]const u8) c_int;
extern fn memcpy(noalias dst: ?*anyopaque, noalias src: ?*const anyopaque, n: usize) ?*anyopaque;
extern fn write(fd: c_int, buf: ?*const anyopaque, count: usize) isize;
extern fn strlen(s: [*c]const u8) usize;

fn dbg_write(msg: [*c]const u8) void {
    _ = write(2, msg, strlen(msg));
}

extern fn arcan_shmif_wait(
    ctx: *c.struct_arcan_shmif_cont,
    ev: *c.arcan_event,
) c_int;

extern fn arcan_shmif_resize(
    ctx: *c.struct_arcan_shmif_cont,
    w: c_uint,
    h: c_uint,
) bool;

extern fn arcan_shmif_dupfd(fd: c_int, dstnum: c_int, blocking: bool) c_int;
extern fn arcan_shmif_drop(ctx: *c.struct_arcan_shmif_cont) void;
extern fn shmif_platform_dupfd_to(fd: c_int, dstnum: c_int, fflags: c_int, fdopt: c_int) c_int;


const STDIN_FILENO: c_int = 0;
const STDOUT_FILENO: c_int = 1;
const BADFD: c_int = -1;

// shmifint_drop_initial

export fn shmifint_drop_initial(ctx: ?*c.struct_arcan_shmif_cont) void {
    if (is_freestanding) return;
    const cont = ctx orelse return;
    if (cont.priv == null) return;
    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));
    if (!off.Hidden.getValidInitial(P)) return;

    const init: *c.struct_arcan_shmif_initial = @ptrCast(@alignCast(off.Hidden.getInitialPtr(P)));

    if (init.render_node != -1) {
        _ = close(init.render_node);
        init.render_node = -1;
    }

    for (&init.fonts) |*font| {
        if (font.fd != -1) {
            _ = close(font.fd);
            font.fd = -1;
        }
    }

    off.Hidden.setValidInitial(P, false);
}

// shmifint_preroll_loop

export fn shmifint_preroll_loop(
    cont: ?*c.struct_arcan_shmif_cont,
    resize: bool,
) bool {
    if (is_freestanding) return false;
    const ctx = cont orelse return false;
    if (ctx.priv == null) return false;
    const P: *anyopaque = @ptrCast(@alignCast(ctx.priv));

    var ev: c.arcan_event = c.arcan_event.zeroes();
    var def: c.struct_arcan_shmif_initial = std.mem.zeroes(c.struct_arcan_shmif_initial);

    // Set defaults
    def.country[0] = 'G';
    def.country[1] = 'B';
    def.country[2] = 'R';
    def.country[3] = 0;
    def.lang[0] = 'E';
    def.lang[1] = 'N';
    def.lang[2] = 'G';
    def.lang[3] = 0;
    def.text_lang[0] = 'E';
    def.text_lang[1] = 'N';
    def.text_lang[2] = 'G';
    def.text_lang[3] = 0;
    def.latitude = 51.48;
    def.longitude = 0.001475;
    def.render_node = -1;
    def.density = c.ARCAN_SHMPAGE_DEFAULT_PPCM;
    def.fonts[0].fd = -1;
    // ≈48pt at 96dpi — matches the HiDPI build default at
    // src/shmif/tui/raster/fontmgmt.zig:635 so clients that activate before
    // FONTHINT arrives do not wedge themselves at the legacy 10pt default.
    def.fonts[0].size_mm = 16.933;
    def.fonts[1].fd = -1;
    def.fonts[2].fd = -1;
    def.fonts[3].fd = -1;

    var w: usize = 640;
    var h: usize = 480;
    var font_ind: usize = 0;

    const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
    const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
    const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
    const sc_getpid = @extern(*const fn () callconv(.c) c_int, .{ .name = "getpid" });

    dbg_write("[preroll] entering wait loop\n");

    // Candidate 2 verification: log child's shmfd inode + sizeof(arcan_event)
    {
        const s: c_ulonglong = @intCast(@sizeOf(c.arcan_event));
        if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
            _ = sc_fprintf(f, "[%d] preroll: child sizeof(arcan_event)=%llu\n",
                sc_getpid(), s);
            _ = sc_fclose(f);
        }
    }
    // Candidate 2 verification: log child's shmfd inode so we can correlate
    // with parent's shmfd inode. If inodes match, same memfd → shared memory.
    {
        const Stat = std.os.linux.Stat;
        const sc_fstat = @extern(*const fn (fd: c_int, buf: *Stat) callconv(.c) c_int, .{ .name = "fstat" });
        var sb: Stat = undefined;
        const rc = sc_fstat(ctx.shmh, &sb);
        if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
            _ = sc_fprintf(f, "[%d] preroll: child shmfd-check shmh=%d rc=%d ino=%llu size=%lld addr=%p\n",
                sc_getpid(), ctx.shmh, rc,
                @as(c_ulonglong, @intCast(sb.ino)),
                @as(c_longlong, @intCast(sb.size)),
                ctx.addr);
            _ = sc_fclose(f);
        }
    }

    if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
        _ = sc_fprintf(f, "[%d] preroll: enums EXIT=%d FRAMESKIP=%d STEPFRAME=%d COREOPT=%d RESET=%d PAUSE=%d UNPAUSE=%d BCHUNK_IN=%d BCHUNK_OUT=%d\n",
            sc_getpid(),
            @as(c_int, c.TARGET_COMMAND_EXIT),
            @as(c_int, c.TARGET_COMMAND_FRAMESKIP),
            @as(c_int, c.TARGET_COMMAND_STEPFRAME),
            @as(c_int, c.TARGET_COMMAND_COREOPT),
            @as(c_int, c.TARGET_COMMAND_RESET),
            @as(c_int, c.TARGET_COMMAND_PAUSE),
            @as(c_int, c.TARGET_COMMAND_UNPAUSE),
            @as(c_int, c.TARGET_COMMAND_BCHUNK_IN),
            @as(c_int, c.TARGET_COMMAND_BCHUNK_OUT));
        _ = sc_fclose(f);
    }
    if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
        _ = sc_fprintf(f, "[%d] preroll: enums ACTIVATE=%d DISPLAYHINT=%d FONTHINT=%d DEVICE_NODE=%d BUFFER_FAIL=%d NEWSEGMENT=%d REQFAIL=%d GRAPHMODE=%d MESSAGE=%d GEOHINT=%d OUTPUTHINT=%d SEEKTIME=%d SEEKCONTENT=%d SETIODEV=%d STREAMSET=%d ATTENUATE=%d AUDDELAY=%d DEVICESTATE=%d ANCHORHINT=%d STORE=%d RESTORE=%d\n",
            sc_getpid(),
            @as(c_int, c.TARGET_COMMAND_ACTIVATE),
            @as(c_int, c.TARGET_COMMAND_DISPLAYHINT),
            @as(c_int, c.TARGET_COMMAND_FONTHINT),
            @as(c_int, c.TARGET_COMMAND_DEVICE_NODE),
            @as(c_int, c.TARGET_COMMAND_BUFFER_FAIL),
            @as(c_int, c.TARGET_COMMAND_NEWSEGMENT),
            @as(c_int, c.TARGET_COMMAND_REQFAIL),
            @as(c_int, c.TARGET_COMMAND_GRAPHMODE),
            @as(c_int, c.TARGET_COMMAND_MESSAGE),
            @as(c_int, c.TARGET_COMMAND_GEOHINT),
            @as(c_int, c.TARGET_COMMAND_OUTPUTHINT),
            @as(c_int, c.TARGET_COMMAND_SEEKTIME),
            @as(c_int, c.TARGET_COMMAND_SEEKCONTENT),
            @as(c_int, c.TARGET_COMMAND_SETIODEV),
            @as(c_int, c.TARGET_COMMAND_STREAMSET),
            @as(c_int, c.TARGET_COMMAND_ATTENUATE),
            @as(c_int, c.TARGET_COMMAND_AUDDELAY),
            @as(c_int, c.TARGET_COMMAND_DEVICESTATE),
            @as(c_int, c.TARGET_COMMAND_ANCHORHINT),
            @as(c_int, c.TARGET_COMMAND_STORE),
            @as(c_int, c.TARGET_COMMAND_RESTORE));
        _ = sc_fclose(f);
    }
    var iter: u32 = 0;
    while (arcan_shmif_wait(ctx, &ev) != 0) {
        iter += 1;
        if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
            const cat = ev.category().*;
            const kind: c_int = if (cat == c.EVENT_TARGET)
                @intCast(ev.tgt().kind)
                else -99;
            // Also read shm directly to sanity-check back value
            const back_byte = if (ctx.addr) |a| @as([*]u8, @ptrCast(a))[16353] else 0xAA;
            const front_byte = if (ctx.addr) |a| @as([*]u8, @ptrCast(a))[16352] else 0xAA;
            // Probe 3: read parent's signatures at offset 17000 (near) and 32800 (far)
            const sig_near_mmap: u64 = if (ctx.addr) |a|
                @as(*volatile u64, @ptrCast(@alignCast(@as([*]u8, @ptrCast(a)) + 17000))).*
                else 0;
            const sig_far_mmap: u64 = if (ctx.addr) |a|
                @as(*volatile u64, @ptrCast(@alignCast(@as([*]u8, @ptrCast(a)) + 32800))).*
                else 0;
            const sc_pread = @extern(*const fn (fd: c_int, buf: [*]u8, count: usize, off: i64) callconv(.c) isize, .{ .name = "pread" });
            var buf_near: [8]u8 = undefined;
            var buf_far: [8]u8 = undefined;
            var buf_slot0: [8]u8 = undefined;
            _ = sc_pread(ctx.shmh, &buf_near, 8, 17000);
            _ = sc_pread(ctx.shmh, &buf_far, 8, 32800);
            _ = sc_pread(ctx.shmh, &buf_slot0, 8, 96);
            const sig_near_pread: u64 = std.mem.readInt(u64, &buf_near, .little);
            const sig_far_pread: u64 = std.mem.readInt(u64, &buf_far, .little);
            const slot0_pread: u64 = std.mem.readInt(u64, &buf_slot0, .little);
            // Also mmap-read slot 0 via raw bytes
            const slot0_mmap: u64 = if (ctx.addr) |a|
                @as(*align(1) const u64, @ptrCast(@as([*]const u8, @ptrCast(a)) + 96)).*
                else 0;
            _ = sc_fprintf(f, "[%d] preroll: iter=%u cat=%d kind=%d shm_front=%u shm_back=%u slot0_mmap=%llx slot0_pread=%llx near_mmap=%llx near_pread=%llx far_mmap=%llx far_pread=%llx\n",
                sc_getpid(), iter, cat, kind,
                @as(c_uint, front_byte), @as(c_uint, back_byte),
                slot0_mmap, slot0_pread,
                sig_near_mmap, sig_near_pread, sig_far_mmap, sig_far_pread);
            _ = sc_fclose(f);
        }
        if (ev.category().* != c.EVENT_TARGET) {
            dbg_write("[preroll] non-target event, skipping\n");
            continue;
        }

        const tgt = ev.tgt();

        if (tgt.kind == c.TARGET_COMMAND_ACTIVATE) {
            // Bug 0125: write `def` to `init` BEFORE setValidInitial so
            // consumers (arcan_video_defaultfont via vk_lwa) never see
            // ValidInitial=true with garbage fonts[i].fd. Symmetric with
            // the death-path fix at line ~370.
            const init: *c.struct_arcan_shmif_initial = @ptrCast(@alignCast(off.Hidden.getInitialPtr(P)));
            init.* = def;
            off.Hidden.setValidInitial(P, true);
            if (resize)
                _ = arcan_shmif_resize(ctx, @intCast(w), @intCast(h));
            return true;
        } else if (tgt.kind == c.TARGET_COMMAND_DISPLAYHINT) {
            if (tgt.ioevs[0].iv != 0)
                w = @intCast(tgt.ioevs[0].iv);
            if (tgt.ioevs[1].iv != 0)
                h = @intCast(tgt.ioevs[1].iv);
            if (tgt.ioevs[4].fv > 0.0001)
                def.density = tgt.ioevs[4].fv;
            if (tgt.ioevs[5].iv != 0)
                def.cell_w = @intCast(tgt.ioevs[5].iv);
            if (tgt.ioevs[6].iv != 0)
                def.cell_h = @intCast(tgt.ioevs[6].iv);
        } else if (tgt.kind == c.TARGET_COMMAND_OUTPUTHINT) {
            if (tgt.ioevs[0].iv != 0)
                def.display_width_px = @intCast(tgt.ioevs[0].iv);
            if (tgt.ioevs[1].iv != 0)
                def.display_height_px = @intCast(tgt.ioevs[1].iv);
            if (tgt.ioevs[2].iv != 0)
                def.rate = @intCast(tgt.ioevs[2].iv);
        } else if (tgt.kind == c.TARGET_COMMAND_GRAPHMODE) {
            const bg = (tgt.ioevs[0].iv & 256) > 0;
            const slot: c_int = tgt.ioevs[0].iv & (~@as(c_int, 256));
            def.colors[1].bg[0] = 255;
            def.colors[1].bg_set = true;

            if (slot >= 0 and slot < @as(c_int, @intCast(def.colors.len))) {
                const sidx: usize = @intCast(slot);
                if (bg) {
                    def.colors[sidx].bg_set = true;
                    def.colors[sidx].bg[0] = @intFromFloat(tgt.ioevs[1].fv);
                    def.colors[sidx].bg[1] = @intFromFloat(tgt.ioevs[2].fv);
                    def.colors[sidx].bg[2] = @intFromFloat(tgt.ioevs[3].fv);
                } else {
                    def.colors[sidx].fg_set = true;
                    def.colors[sidx].fg[0] = @intFromFloat(tgt.ioevs[1].fv);
                    def.colors[sidx].fg[1] = @intFromFloat(tgt.ioevs[2].fv);
                    def.colors[sidx].fg[2] = @intFromFloat(tgt.ioevs[3].fv);
                }
            }
        } else if (tgt.kind == c.TARGET_COMMAND_DEVICE_NODE) {
            // alt-con will be updated automatically, due to normal wait handler
            if (tgt.ioevs[0].iv != -1) {
                def.render_node = arcan_shmif_dupfd(
                    tgt.ioevs[0].iv,
                    -1,
                    true,
                );
            }
        } else if (tgt.kind == c.TARGET_COMMAND_FONTHINT) {
            def.fonts[font_ind].hinting = tgt.ioevs[3].iv;

            // protect against a bad value there, disabling the size isn't permitted
            if (tgt.ioevs[2].fv > 0)
                def.fonts[font_ind].size_mm = tgt.ioevs[2].fv;
            if (font_ind < 3) {
                if (tgt.ioevs[0].iv != -1) {
                    const new_fd = arcan_shmif_dupfd(
                        tgt.ioevs[0].iv,
                        -1,
                        true,
                    );
                    // Bug 0125: validate the duped fd is fstattable
                    // before storing. dup() can succeed yielding an fd
                    // that downstream fstat rejects (e.g. durden's
                    // process-local fd not actually open here), and
                    // arcan_video_defaultfont's fstat then panics.
                    var probe: c.struct_stat = undefined;
                    if (new_fd != -1 and c.fstat(new_fd, &probe) == 0) {
                        def.fonts[font_ind].fd = new_fd;
                    } else {
                        def.fonts[font_ind].fd = -1;
                        if (new_fd != -1) _ = c.close(new_fd);
                    }
                    font_ind += 1;
                }
            }
        } else if (tgt.kind == c.TARGET_COMMAND_BCHUNK_IN) {
            // allow remapping of stdin but don't CLOEXEC it
            if (strcmp(@as([*c]const u8, @ptrCast(&tgt.unnamed_0.message)), "stdin") == 0)
                _ = shmif_platform_dupfd_to(tgt.ioevs[0].iv, STDIN_FILENO, 0, 0);
        } else if (tgt.kind == c.TARGET_COMMAND_BCHUNK_OUT) {
            // allow remapping of stdout but don't CLOEXEC it
            if (strcmp(@as([*c]const u8, @ptrCast(&tgt.unnamed_0.message)), "stdout") == 0)
                _ = shmif_platform_dupfd_to(tgt.ioevs[0].iv, STDOUT_FILENO, 0, 0);
        } else if (tgt.kind == c.TARGET_COMMAND_GEOHINT) {
            def.latitude = tgt.ioevs[0].fv;
            def.longitude = tgt.ioevs[1].fv;
            def.elevation = tgt.ioevs[2].fv;
            if (tgt.ioevs[3].cv[0] != 0)
                _ = memcpy(
                    @as(?*anyopaque, @ptrCast(&def.country)),
                    @as(?*const anyopaque, @ptrCast(&tgt.ioevs[3].cv)),
                    3,
                );
            if (tgt.ioevs[4].cv[0] != 0)
                _ = memcpy(
                    @as(?*anyopaque, @ptrCast(&def.lang)),
                    @as(?*const anyopaque, @ptrCast(&tgt.ioevs[3].cv)),
                    3,
                );
            if (tgt.ioevs[5].cv[0] != 0)
                _ = memcpy(
                    @as(?*anyopaque, @ptrCast(&def.text_lang)),
                    @as(?*const anyopaque, @ptrCast(&tgt.ioevs[4].cv)),
                    3,
                );
            def.timezone = tgt.ioevs[5].iv;
        }
        // default: no-op for unhandled event kinds
    }

    // this will only be called during first setup, so the _drop is safe here
    // as the mutex lock it performs have not been exposed to the user
    //
    // Commit `def` to the shared `init` slot BEFORE setValidInitial — the
    // ACTIVATE path at line ~237 does `init.* = def` then setValidInitial.
    // Without the assignment here, callers (e.g. video.initLwa →
    // arcan_video_defaultfont) saw ValidInitial=true but read uninitialised
    // memory for fonts[i].fd, then fed garbage like fd=1095447355 into
    // TTF_OpenFontFD → fstat → unreachable panic (bug 0125, second entry
    // point reproduced 2026-05-02 by `arcan welcome` against durden).
    dbg_write("[preroll] wait returned 0, connection died/timed out\n");
    const init: *c.struct_arcan_shmif_initial = @ptrCast(@alignCast(off.Hidden.getInitialPtr(P)));
    init.* = def;
    off.Hidden.setValidInitial(P, true);
    arcan_shmif_drop(ctx);
    return false;
}
