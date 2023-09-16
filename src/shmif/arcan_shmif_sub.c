/*
 * Copyright 2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: negotiable sub-structure support
 */

#include "arcan_shmif.h"

union shmif_ext_substruct arcan_shmif_substruct(
	struct arcan_shmif_cont* ctx, enum shmif_ext_meta meta)
{
	union shmif_ext_substruct sub = {0};
	if (atomic_load(&ctx->addr->apad) < sizeof(struct arcan_shmif_ofstbl))
		return sub;

	uintptr_t base = (uintptr_t) &ctx->addr->adata;

	struct arcan_shmif_ofstbl* aofs =
		(struct arcan_shmif_ofstbl*) &ctx->addr->adata;

	if (aofs->sz_ramp)
		sub.cramp = (struct arcan_shmif_ramp*)(base + aofs->ofs_ramp);

	if (aofs->sz_vr)
		sub.vr = (struct arcan_shmif_vr*)(base + aofs->ofs_vr);

	if (aofs->sz_hdr)
		sub.hdr = (struct arcan_shmif_hdr*)(base + aofs->ofs_hdr);

	if (aofs->sz_vector)
		sub.vector = (struct arcan_shmif_vector*)(base + aofs->ofs_vector);

	if (aofs->sz_venc)
		sub.venc = (struct arcan_shmif_venc*)(base + aofs->ofs_venc);

	return sub;
}

bool arcan_shmifsub_getramp(
	struct arcan_shmif_cont* cont, size_t ind, struct ramp_block* out)
{
	struct arcan_shmif_ramp* hdr =
		arcan_shmif_substruct(cont, SHMIF_META_CM).cramp;

	if (!hdr || hdr->magic != ARCAN_SHMIF_RAMPMAGIC || ind > (hdr->n_blocks >> 1))
		return false;

/* decode and validate */
	struct ramp_block tmp;
	memcpy(&tmp, &hdr->ramps[ind], sizeof(struct ramp_block));
	uint16_t checksum = subp_checksum(
		tmp.edid, sizeof(tmp.edid) + SHMIF_CMRAMP_UPLIM);

	if (checksum != tmp.checksum)
		return false;

	if (out)
		memcpy(out, &tmp, sizeof(struct ramp_block));

/* mark as read, this doesn't really affect the synch- in itself (that's
 * what the checksum is for), but as a hint */
	atomic_fetch_and(&hdr->dirty_in, ~(1<<ind));

	return true;
}

bool arcan_shmifsub_setramp(
	struct arcan_shmif_cont* cont, size_t ind, struct ramp_block* in)
{
	struct arcan_shmif_ramp* hdr = arcan_shmif_substruct(
		cont, SHMIF_META_CM).cramp;

	if (!in || !hdr || ind >= (hdr->n_blocks >> 1))
		return false;

/* update checksum, write and set dirty bit */
	in->checksum = subp_checksum(
		in->edid, sizeof(in->edid) + SHMIF_CMRAMP_UPLIM);

	memcpy(&hdr->ramps[ind*2], in, sizeof(struct ramp_block));

	atomic_fetch_or(&hdr->dirty_out, 1<<ind);

	return true;
}
