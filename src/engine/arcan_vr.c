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

struct arcan_vr_ctx {
	arcan_evctx* ctx;
	arcan_frameserver* connection;
	arcan_vobj_id limb_map[LIMB_LIM];
};

/*
 * static void vr_tick(struct arcan_vr_ctx* ctx)
 * {
 *   check for changes in the capability mask, on arrival,
 *   create a new null object and attach to the connection one
 *   on tick/render, test checksum for matrices and copy into
 *   object.
 * }
 */

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
	arcan_video_alterfeed(mvctx->vid, FFUNC_VR, (struct vfunc_state){
		.tag = ARCAN_TAG_FRAMESERV,
		.ptr = vrctx
	});

	return vrctx;
}

arcan_errc arcan_vr_release(struct arcan_vr_ctx* ctx, arcan_vobj_id ind)
{
	return ARCAN_ERRC_NOT_IMPLEMENTED;
}

arcan_errc arcan_vr_reset(struct arcan_vr_ctx* ctx)
{
/*
 * enqueue a reset event on the ctx, drop all mappings etc.
 */
	return ARCAN_ERRC_NOT_IMPLEMENTED;
}

/*
 * This ffunc is a simplified version of the arcan_frameserver_emptyframe
 * where we also check limb updates and synch position / head tracking
 */
enum arcan_ffunc_rv arcan_vr_ffunc FFUNC_HEAD
{
	struct arcan_vr_ctx* ctx = state.ptr;
	struct arcan_frameserver* tgt = ctx->connection;

	if (!tgt || state.tag != ARCAN_TAG_FRAMESERV)
		return FRV_NOFRAME;

/* check if allocation mask has changed, if so, a new device has been
 * detected. */

	if (cmd == FFUNC_POLL){
	}
	else if (cmd == FFUNC_TICK){

	}
/*
 * Run the null-feed as a default handler
 */
	return arcan_frameserver_nullfeed(
		cmd, buf, buf_sz, width, height, mode, state, srcid);
}

arcan_errc arcan_vr_camtag(struct arcan_vr_ctx* ctx,
	arcan_vobj_id left, arcan_vobj_id right)
{
/*
 * find the leye/reye metadata and behave similar to a camtag
 */
	return ARCAN_ERRC_NOT_IMPLEMENTED;
}

/*
 * Retrieve (if possible) two distortion meshes to use for texturing
 * the camtagged rendertargets. The output data is formatted planar:
 * plane-1[x, y, z] plane-2[s, t] with n_elems in each plane.
 */
arcan_errc arcan_vr_distortion(struct arcan_vr_ctx* ctx,
	float* out_left, float* l_elems, uint8_t* out_right, size_t* r_elems)
{
/*
 * map to bchunk- events if those have been exposed with the
 * special subextensiuon for distortion mesh format
 */
	return ARCAN_ERRC_NOT_IMPLEMENTED;
}

arcan_errc arcan_vr_displaydata(struct arcan_vr_ctx* ctx,
	struct vr_meta* dst)
{
/*
 * copy out from the vr structure
 */
	return ARCAN_ERRC_NOT_IMPLEMENTED;
}

arcan_errc arcan_vr_shutdown(struct arcan_vr_ctx* ctx)
{
/*
 * enqueue an EXIT_ command on the connection, enqueue on evctx
 * to indicate that we're gone
 */
	return ARCAN_ERRC_NOT_IMPLEMENTED;
}
