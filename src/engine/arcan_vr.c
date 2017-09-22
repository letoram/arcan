/*
 * Copyright 2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>
#include <assert.h>
#include <limits.h>
#include <setjmp.h>

#include <sys/types.h>
#include <sys/socket.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_db.h"
#include "arcan_shmif.h"
#include "arcan_shmif_sub.h"
#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_audio.h"
#include "arcan_audioint.h"
#include "arcan_3dbase.h"

#define FRAMESERVER_PRIVATE
#include "arcan_frameserver.h"
#include "arcan_vr.h"

/*
 * left: metadata, samples, ...
 */

struct arcan_vr_ctx {
	arcan_evctx* ctx;
	arcan_frameserver* connection;
	uint64_t map;
	arcan_vobj_id limb_map[LIMB_LIM];
};

struct arcan_vr_ctx* arcan_vr_setup(
	const char* bridge_arg, struct arcan_evctx* evctx, uintptr_t tag)
{
	const char* appl;
	struct arcan_dbh* dbh = arcan_db_get_shared(&appl);

	char* kv = arcan_db_appl_val(dbh, appl, "ext_vr");
	if (!kv)
		return NULL;

/*
 * build a frameserver context and envp with the data for the vrbridge
 * and with the subprotocol permissions enabled
 */
	struct arcan_strarr arr_argv = {0}, arr_env = {0};
	arcan_mem_growarr(&arr_argv);
	arr_argv.data[0] = strdup(kv);
	arr_argv.count = 1;

	char* kvd = arcan_db_appl_val(dbh, appl, "ext_vr_debug");
	if (kvd){
		arcan_mem_growarr(&arr_env);
		arr_env.data[0] = strdup("ARCAN_VR_DEBUGATTACH=1");
		arr_env.count = 1;
		free(kvd);
	}

/*
 * There might be some merit to enabling the VOBJ- substructure as well since
 * some providers might want to come with distortion meshes or reference-
 * models for tool-limbs
 */
	struct frameserver_envp args = {
		.metamask = SHMIF_META_VR | SHMIF_META_VOBJ,
		.use_builtin = false,
		.args.external.fname = kv,
		.args.external.envv = &arr_env,
		.args.external.argv = &arr_argv,
		.args.external.resource = strdup(bridge_arg)
	};

	struct arcan_vr_ctx* vrctx = arcan_alloc_mem(
		sizeof(struct arcan_vr_ctx), ARCAN_MEM_VSTRUCT,
		ARCAN_MEM_BZERO | ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_NATURAL
	);

	if (!vrctx)
		return NULL;

	struct arcan_frameserver* mvctx = platform_launch_fork(&args, tag);
	arcan_mem_freearr(&arr_argv);
	arcan_mem_freearr(&arr_env);
	free(args.args.external.resource);

	if (!mvctx){
		arcan_mem_free(vrctx);
		arcan_mem_free(mvctx);
		return NULL;
	}

	vrctx->ctx = evctx;
	vrctx->connection = mvctx;
	mvctx->segid = SEGID_SENSOR;
	arcan_video_alterfeed(mvctx->vid, FFUNC_VR,
		(struct vfunc_state){
		.tag = ARCAN_TAG_VR,
		.ptr = vrctx
	});

/* nothing more we need to preroll so activate immediately */
	platform_fsrv_pushevent(mvctx,
		&(arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_ACTIVATE
	});

	return vrctx;
}

/*
 * This ffunc is a simplified version of the arcan_frameserver_emptyframe
 * where we also check limb updates and synch position / head tracking
 */
enum arcan_ffunc_rv arcan_vr_ffunc FFUNC_HEAD
{
	struct arcan_vr_ctx* ctx = state.ptr;
	struct arcan_frameserver* tgt = ctx->connection;

	if (!tgt || state.tag != ARCAN_TAG_VR)
		return FRV_NOFRAME;

	struct arcan_shmif_vr* vr = tgt->desc.aext.vr;
/* poll allocation mask for events */

	TRAMP_GUARD(FRV_NOFRAME, tgt);
	if (cmd == FFUNC_POLL && vr){
		for (size_t i = 0; i < LIMB_LIM; i++){
			if (!ctx->limb_map[i])
				continue;

/* naive approach: copy / verify data, update position state for object if they
 * match */
		}
	}
	else if (cmd == FFUNC_TICK && vr){
/* check allocation masks */
		uint_least64_t map = atomic_load(&vr->limb_mask);
		uint64_t new = map & ~ctx->map;
		uint64_t lost = ctx->map & ~map;

		if (new){
			for (uint64_t i = 0; i < LIMB_LIM; i++){
				if ((1 << i) & new){
					arcan_event_enqueue(arcan_event_defaultctx(),
					&(struct arcan_event){
						.category = EVENT_FSRV,
						.fsrv.kind = EVENT_FSRV_ADDVRLIMB,
						.fsrv.limb = i
					});
				}
			}
		}

		if (lost){
			for (uint64_t i = 0; i < LIMB_LIM; i++){
				if ((1 << i) & lost){
					arcan_event_enqueue(arcan_event_defaultctx(),
					&(struct arcan_event){
						.category = EVENT_FSRV,
						.fsrv.kind = EVENT_FSRV_LOSTVRLIMB,
						.fsrv.limb = i
					});
					if (ctx->limb_map[i])
						arcan_3d_bindvr(ctx->limb_map[i], NULL);
				}
			}
		}
		ctx->map = map;
	}
	else if (cmd == FFUNC_DESTROY && vr){
/* dms will deal with shutdown / deallocation */
		for (size_t i = 0; i < LIMB_LIM; i++){
			if (ctx->limb_map[i]){
				arcan_3d_bindvr(ctx->limb_map[i], NULL);
				ctx->limb_map[i] = 0;
			}
		}
	}

/* Run the null-feed as a default handler */
	struct vfunc_state inst = {
		.ptr = tgt,
		.tag = ARCAN_TAG_FRAMESERV
	};

/* _feed will reenter, need to use full vdirecct so that we get resize-
 * behavior, needed for the extra aproto- mapping to work */
	platform_fsrv_leave();
	return arcan_frameserver_vdirect(
		cmd, buf, buf_sz, width, height, mode, inst, srcid);
}

arcan_errc arcan_vr_maplimb(
	struct arcan_vr_ctx* ctx, unsigned ind, arcan_vobj_id vid)
{
	if (!ctx)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	if (ind >= LIMB_LIM)
		return ARCAN_ERRC_OUT_OF_SPACE;

/* only 1:1 allowed */
	for (size_t i = 0; i < LIMB_LIM; i++)
		if (ctx->limb_map[i] == vid)
			return ARCAN_ERRC_UNACCEPTED_STATE;

/* unmap- pre-existing? */
	if (ctx->limb_map[ind])
		arcan_3d_bindvr(ctx->limb_map[ind], NULL);

	ctx->limb_map[ind] = vid;
	return arcan_3d_bindvr(vid, ctx);
}

arcan_errc arcan_vr_release(struct arcan_vr_ctx* ctx, arcan_vobj_id vid)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	for (size_t i = 0; i < LIMB_LIM; i++)
		if (ctx->limb_map[i] == vid){
			ctx->limb_map[i] = 0;
			rv = ARCAN_OK;
		}
	return rv;
}

arcan_errc arcan_vr_displaydata(
	struct arcan_vr_ctx* ctx, struct vr_meta* dst)
{
	struct arcan_frameserver* tgt = ctx->connection;

	if (!tgt || !tgt->desc.aext.vr)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct arcan_shmif_vr* vr = tgt->desc.aext.vr;
	TRAMP_GUARD(ARCAN_ERRC_UNACCEPTED_STATE, tgt);
	*dst = vr->meta;
	platform_fsrv_leave();
	return ARCAN_OK;
}

arcan_errc arcan_vr_shutdown(struct arcan_vr_ctx* ctx)
{
/*
 * enqueue an EXIT_ command on the connection (if alive), enqueue on evctx
 * to indicate that we're gone
 */
	return ARCAN_ERRC_NOT_IMPLEMENTED;
}
