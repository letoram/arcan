// Zig reimplementation of arcan_shmif_sub.c
// Drop-in C-ABI-compatible replacement for negotiable sub-structure support.
//
// Exports: arcan_shmif_substruct, arcan_shmifsub_getramp, arcan_shmifsub_setramp
//
// Note: struct arcan_shmif_page and struct arcan_shmif_ramp are opaque in
// Zig's @cImport (they contain _Atomic / _Alignas fields). We use the
// shmif_offsets module for byte-offset accessors instead of C helpers.
//
const std = @import("std");
const off = @import("shmif_offsets");
const c = @import("shmif_types");

/// Replicate subp_checksum from arcan_shmif_sub.h.
/// BSD checksum -- the |= 0x10000 is a no-op (bit 16 truncated to u16).
fn subpChecksum(buf: [*]const u8, len: usize) u16 {
    var res: u16 = 0;
    for (0..len) |i| {
        res = @intCast(((@as(u32, res) >> 1) + buf[i]) & 0xffff);
    }
    return res;
}

export fn arcan_shmif_substruct(
    ctx: *c.struct_arcan_shmif_cont,
    meta: c.enum_shmif_ext_meta,
) c.union_shmif_ext_substruct {
    _ = meta;
    var sub: c.union_shmif_ext_substruct = undefined;
    @memset(std.mem.asBytes(&sub), 0);

    const page: *anyopaque = ctx.*.addr orelse return sub;

    // atomic_load(&ctx->addr->apad)
    if (@atomicLoad(u32, off.Page.getApadPtr(page), .seq_cst) < @sizeOf(c.struct_arcan_shmif_ofstbl))
        return sub;

    const base: usize = off.Page.getAdataAddr(page);

    const aofs: *c.struct_arcan_shmif_ofstbl = @ptrFromInt(base);

    // anonymous union -> anonymous struct inside arcan_shmif_ofstbl
    const ofs = &aofs.*.unnamed_0.unnamed_0;

    if (ofs.sz_ramp != 0)
        sub.cramp = @ptrFromInt(base + ofs.ofs_ramp);

    if (ofs.sz_vr != 0)
        sub.vr = @ptrFromInt(base + ofs.ofs_vr);

    if (ofs.sz_hdr != 0)
        sub.hdr = @ptrFromInt(base + ofs.ofs_hdr);

    if (ofs.sz_vector != 0)
        sub.vector = @ptrFromInt(base + ofs.ofs_vector);

    if (ofs.sz_venc != 0)
        sub.venc = @ptrFromInt(base + ofs.ofs_venc);

    return sub;
}

export fn arcan_shmifsub_getramp(
    cont: *c.struct_arcan_shmif_cont,
    ind: usize,
    out: ?*c.struct_ramp_block,
) bool {
    const sub = arcan_shmif_substruct(cont, c.SHMIF_META_CM);
    const ramp_opaque: *anyopaque = sub.cramp orelse return false;

    if (off.Ramp.getMagic(ramp_opaque) != c.ARCAN_SHMIF_RAMPMAGIC) return false;
    if (ind > (@as(usize, off.Ramp.getNBlocks(ramp_opaque)) >> 1)) return false;

    // decode and validate: memcpy(&tmp, &hdr->ramps[ind], sizeof(struct ramp_block))
    var tmp: c.struct_ramp_block = undefined;
    const tmp_bytes: [*]u8 = @ptrCast(&tmp);
    const src_bytes: [*]const u8 = off.Ramp.getBlockPtr(ramp_opaque, ind);
    @memcpy(tmp_bytes[0..@sizeOf(c.struct_ramp_block)], src_bytes[0..@sizeOf(c.struct_ramp_block)]);

    // checksum covers edid + plane-data
    const checksum = subpChecksum(
        &tmp.edid,
        @sizeOf(@TypeOf(tmp.edid)) + c.SHMIF_CMRAMP_UPLIM,
    );

    if (checksum != tmp.checksum) return false;

    if (out) |outp| {
        const out_bytes: [*]u8 = @ptrCast(outp);
        @memcpy(out_bytes[0..@sizeOf(c.struct_ramp_block)], tmp_bytes[0..@sizeOf(c.struct_ramp_block)]);
    }

    // atomic_fetch_and(&hdr->dirty_in, ~(1<<ind)) -- mark as read
    const dirty_in = off.Ramp.getDirtyInPtr(ramp_opaque);
    _ = @atomicRmw(u8, dirty_in, .And, ~(@as(u8, 1) << @intCast(ind)), .seq_cst);

    return true;
}

export fn arcan_shmifsub_setramp(
    cont: *c.struct_arcan_shmif_cont,
    ind: usize,
    in_ramp: ?*c.struct_ramp_block,
) bool {
    const inp = in_ramp orelse return false;

    const sub = arcan_shmif_substruct(cont, c.SHMIF_META_CM);
    const ramp_opaque: *anyopaque = sub.cramp orelse return false;

    if (ind >= (@as(usize, off.Ramp.getNBlocks(ramp_opaque)) >> 1)) return false;

    // update checksum
    inp.*.checksum = subpChecksum(
        &inp.*.edid,
        @sizeOf(@TypeOf(inp.*.edid)) + c.SHMIF_CMRAMP_UPLIM,
    );

    // memcpy(&hdr->ramps[ind*2], in, sizeof(struct ramp_block))
    const dst_bytes: [*]u8 = off.Ramp.getBlockPtr(ramp_opaque, ind * 2);
    const src_bytes: [*]const u8 = @ptrCast(inp);
    @memcpy(dst_bytes[0..@sizeOf(c.struct_ramp_block)], src_bytes[0..@sizeOf(c.struct_ramp_block)]);

    // atomic_fetch_or(&hdr->dirty_out, 1<<ind)
    const dirty_out = off.Ramp.getDirtyOutPtr(ramp_opaque);
    _ = @atomicRmw(u8, dirty_out, .Or, @as(u8, 1) << @intCast(ind), .seq_cst);

    return true;
}
