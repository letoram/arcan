// Zig reimplementation of arcan_shmif_evhelper.c
// Drop-in C-ABI-compatible replacement for evhelper functions.
//
// Exports: arcan_shmif_multipart_message, arcan_shmif_pushutf8,
//          arcan_shmif_descrevent, arcan_shmif_acquireloop
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const off = @import("shmif_offsets");
const c = @import("shmif_types");

// UTF-8 DFA Decoder (from Bjoern Hoehrmann)
// Inlined from frameserver/util/utf8.c

const UTF8_ACCEPT: u32 = 0;
const UTF8_REJECT: u32 = 1;

const utf8d = [_]u8{
    // 00..1f
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    // 20..3f
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    // 40..5f
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    // 60..7f
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    // 80..9f
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,   9,
    // a0..bf
    7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,
    // c0..df
    8,   8,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,
    // e0..ef
    0xa, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x4, 0x3, 0x3,
    // f0..ff
    0xb, 0x6, 0x6, 0x6, 0x5, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8,
    // s0..s0
    0x0, 0x1, 0x2, 0x3, 0x5, 0x8, 0x7, 0x1, 0x1, 0x1, 0x4, 0x6, 0x1, 0x1, 0x1, 0x1,
    // s1..s2
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,
    1,   0,   1,   1,   1,   1,   1,   0,   1,   0,   1,   1,   1,   1,   1,   1,
    // s3..s4
      1,   2,   1,   1,   1,   1,   1,   2,   1,   2,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   2,   1,   1,   1,   1,   1,   1,   1,   1,
    // s5..s6
      1,   2,   1,   1,   1,   1,   1,   1,   1,   2,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   3,   1,   3,   1,   1,   1,   1,   1,   1,
    // s7..s8
      1,   3,   1,   1,   1,   1,   1,   3,   1,   3,   1,   1,   1,   1,   1,   1,
    1,   3,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,
};

fn utf8_decode(state: *u32, codep: *u32, byte: u32) u32 {
    const typ: u32 = utf8d[byte];

    codep.* = if (state.* != UTF8_ACCEPT)
        (byte & 0x3f) | (codep.* << 6)
    else
        (@as(u32, 0xff) >> @intCast(typ)) & byte;

    state.* = utf8d[256 + state.* * 16 + typ];
    return state.*;
}

// Extern C declarations

extern fn arcan_shmif_enqueue(
    ctx: *c.struct_arcan_shmif_cont,
    ev: *c.arcan_event,
) c_int;

extern fn arcan_shmif_wait(
    ctx: *c.struct_arcan_shmif_cont,
    ev: *c.arcan_event,
) c_int;

extern fn arcan_shmif_dupfd(fd: c_int, dstnum: c_int, blocking: bool) c_int;

extern fn snprintf(noalias buf: [*c]u8, size: usize, noalias fmt: [*c]const u8, ...) c_int;
extern fn memcpy(noalias dst: ?*anyopaque, noalias src: ?*const anyopaque, n: usize) ?*anyopaque;
extern fn strlen(s: [*c]const u8) usize;
extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

// multipart_message

export fn arcan_shmif_multipart_message(
    C: ?*c.struct_arcan_shmif_cont,
    ev: ?*c.arcan_event,
    out: ?*[*c]u8,
    bad: ?*bool,
) bool {
    if (is_freestanding) return false;
    const ctx = C orelse {
        if (bad) |b| b.* = true;
        return false;
    };
    const event = ev orelse {
        if (bad) |b| b.* = true;
        return false;
    };
    const out_ptr = out orelse {
        if (bad) |b| b.* = true;
        return false;
    };
    const bad_ptr = bad orelse return false;

    if (event.category().* != c.EVENT_TARGET or
        event.tgt().kind != c.TARGET_COMMAND_MESSAGE)
    {
        bad_ptr.* = true;
        return false;
    }

    const P: *anyopaque = @ptrCast(@alignCast(ctx.priv));
    const msg_ptr: [*c]const u8 = @ptrCast(&event.tgt().message());
    const msglen = strlen(msg_ptr);

    if (off.Hidden.getFlushMultipart(P)) {
        off.Hidden.setFlushMultipart(P, false);
        off.Hidden.setMultipartOfs(P, 0);
    }

    const end_multipart = event.tgt().ioevs[0].iv == 0;

    if (end_multipart)
        off.Hidden.setFlushMultipart(P, true);

    const multipart_buf_size: usize = 1024;
    if (msglen + off.Hidden.getMultipartOfs(P) >= multipart_buf_size) {
        bad_ptr.* = true;
        return false;
    }

    _ = memcpy(
        @as(?*anyopaque, @ptrCast(off.Hidden.getMultipartPtr(P) + off.Hidden.getMultipartOfs(P))),
        @as(?*const anyopaque, @ptrCast(msg_ptr)),
        msglen,
    );
    off.Hidden.setMultipartOfs(P, off.Hidden.getMultipartOfs(P) + msglen);
    (off.Hidden.getMultipartPtr(P) + off.Hidden.getMultipartOfs(P))[0] = 0;
    out_ptr.* = @ptrCast(off.Hidden.getMultipartPtr(P));
    bad_ptr.* = false;

    return end_multipart;
}

// pushutf8

export fn arcan_shmif_pushutf8(
    acon: ?*c.struct_arcan_shmif_cont,
    base: ?*c.arcan_event,
    msg: [*c]const u8,
    len_in: usize,
) bool {
    if (is_freestanding) return false;
    const ctx = acon orelse return false;
    const ev = base orelse return false;
    var remaining = len_in;
    var outs: [*c]const u8 = msg;

    const ext = ev.ext();
    const maxlen = @sizeOf(@TypeOf(ext.unnamed_0.message.data)) - 1;

    // utf8-point aligned against block size
    while (remaining > maxlen) {
        var state: u32 = 0;
        var codepoint: u32 = 0;
        var lastok: usize = 0;

        for (0..maxlen) |i| {
            if (UTF8_ACCEPT == utf8_decode(&state, &codepoint, @as(u32, outs[i])))
                lastok = i;

            if (i != lastok) {
                if (i == 0)
                    return false;
            }
        }

        const copy_len = lastok + 1;
        _ = memcpy(
            @as(?*anyopaque, @ptrCast(&ext.unnamed_0.message.data)),
            @as(?*const anyopaque, @ptrCast(outs)),
            copy_len,
        );
        ext.unnamed_0.message.data[copy_len] = 0;
        remaining -= copy_len;
        outs += copy_len;

        ext.unnamed_0.message.multipart = if (remaining != 0) 1 else 0;

        _ = arcan_shmif_enqueue(ctx, ev);
    }

    // flush remaining
    if (remaining != 0) {
        const base_sz = @sizeOf(@TypeOf(ext.unnamed_0.message.data));
        _ = snprintf(
            @as([*c]u8, @ptrCast(&ext.unnamed_0.message.data)),
            base_sz,
            "%s",
            outs,
        );
        ext.unnamed_0.message.multipart = 0;
        _ = arcan_shmif_enqueue(ctx, ev);
    }

    return true;
}

// descrevent

export fn arcan_shmif_descrevent(ev: ?*c.arcan_event) bool {
    if (is_freestanding) return false;
    const event = ev orelse return false;

    if (event.category().* != c.EVENT_TARGET)
        return false;

    const list = [_]c_uint{
        c.TARGET_COMMAND_STORE,
        c.TARGET_COMMAND_RESTORE,
        c.TARGET_COMMAND_DEVICE_NODE,
        c.TARGET_COMMAND_FONTHINT,
        c.TARGET_COMMAND_BCHUNK_IN,
        c.TARGET_COMMAND_BCHUNK_OUT,
        c.TARGET_COMMAND_NEWSEGMENT,
    };

    for (list) |item| {
        if (event.tgt().kind == item and
            event.tgt().ioevs[0].iv != c.BADFD)
            return true;
    }

    return false;
}

// acquireloop

export fn arcan_shmif_acquireloop(
    ctx: ?*c.struct_arcan_shmif_cont,
    acqev: ?*c.arcan_event,
    evpool: ?*[*c]c.arcan_event,
    evpool_sz: ?*isize,
) bool {
    if (is_freestanding) return false;
    const cont = ctx orelse return false;
    const aqev = acqev orelse return false;
    const pool_ptr = evpool orelse return false;
    const sz_ptr = evpool_sz orelse return false;

    // preallocate a buffer "large enough", some unreasonable threshold
    var ul: usize = 512;
    const alloc_sz = @sizeOf(c.arcan_event) * ul;
    const raw = malloc(alloc_sz) orelse return false;
    pool_ptr.* = @ptrCast(@alignCast(raw));

    sz_ptr.* = 0;
    while (arcan_shmif_wait(cont, aqev) != 0 and ul > 0) {
        ul -= 1;
        // event to buffer?
        if (aqev.category().* != c.EVENT_TARGET or
            (aqev.tgt().kind != c.TARGET_COMMAND_NEWSEGMENT and
                aqev.tgt().kind != c.TARGET_COMMAND_REQFAIL))
        {
            // dup-copy the descriptor so it doesn't get freed in shmif_wait
            if (arcan_shmif_descrevent(aqev)) {
                aqev.tgt().ioevs[0].iv =
                    arcan_shmif_dupfd(aqev.tgt().ioevs[0].iv, -1, true);
            }
            const idx: usize = @intCast(sz_ptr.*);
            pool_ptr.*[idx] = aqev.*;
            sz_ptr.* += 1;
        } else {
            return true;
        }
    }

    // broken pool
    sz_ptr.* = -1;
    free(@as(?*anyopaque, @ptrCast(pool_ptr.*)));
    pool_ptr.* = null;
    return false;
}
