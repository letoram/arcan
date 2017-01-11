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

	struct arcan_shmif_ofstbl* ofsets =
		(struct arcan_shmif_ofstbl*) &ctx->addr->adata;

/* 1. fill in the offsets */

	return sub;
}

bool arcan_shmifsub_getramp(
	struct arcan_shmif_cont* cont, size_t ind, struct ramp_block* out)
{
	struct arcan_shmif_ramp* hdr = arcan_shmif_substruct(
		cont, SHMIF_META_CM).cramp;

/* 2. return the right position */

	if (!hdr)
		return false;

	return false;
}

bool arcan_shmifsub_setramp(
	struct arcan_shmif_cont* cont, size_t ind, struct ramp_block* in)
{
	struct arcan_shmif_ramp* hdr = arcan_shmif_substruct(
		cont, SHMIF_META_CM).cramp;

	if (!hdr)
		return false;

	return false;
}
