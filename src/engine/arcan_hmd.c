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
#include "arcan_shmif.h"
#include "arcan_shmif_hmd.h"
#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_audio.h"
#include "arcan_audioint.h"

#define FRAMESERVER_PRIVATE
#include "arcan_frameserver.h"
#include "arcan_hmd.h"

struct arcan_hmd_ctx {
	arcan_evctx* ctx;
	arcan_frameserver* connection;
};

/*
 * static void hmd_tick(struct arcan_hmd_ctx* ctx)
 * {
 *   check for changes in the capability mask, on arrival,
 *   create a new null object and attach to the connection one
 *   on tick/render, test checksum for matrices and copy into
 *   object.
 * }
 */

struct arcan_hmd_ctx* arcan_hmd_setup(const char* hmdbridge,
	const char* bridge_arg, struct arcan_evctx* evctx, uintptr_t tag)
{
/*
 * 1. build a frameserver envp with the data for the hmdbridge and
 *    enough room to fit the added metadata.
 *
 * 2. build a null-object to act as control and mapping for tick etc.
 *    set the ffunc- to match an exposed ffunc here (also present in _lut)
 *
 * 3. enqueue an event on evctx to tell of the new device
 */
	return NULL;
}

arcan_errc arcan_hmd_reset(struct arcan_hmd_ctx* ctx)
{
/*
 * enqueue a reset event on the ctx
 */
	return ARCAN_ERRC_NOT_IMPLEMENTED;
}

arcan_errc arcan_hmd_camtag(struct arcan_hmd_ctx* ctx,
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
arcan_errc arcan_hmd_distortion(struct arcan_hmd_ctx* ctx,
	float* out_left, float* l_elems, uint8_t* out_right, size_t* r_elems)
{
/*
 * map to bchunk- events if those have been exposed with the
 * special subextensiuon for distortion mesh format
 */
	return ARCAN_ERRC_NOT_IMPLEMENTED;
}

arcan_errc arcan_hmd_displaydata(struct arcan_hmd_ctx* ctx,
	struct hmd_meta* dst)
{
/*
 * copy out from the hmd structure
 */
	return ARCAN_ERRC_NOT_IMPLEMENTED;
}

arcan_errc arcan_hmd_shutdown(struct arcan_hmd_ctx* ctx)
{
/*
 * enqueue an EXIT_ command on the connection, enqueue on evctx
 * to indicate that we're gone
 */
	return ARCAN_ERRC_NOT_IMPLEMENTED;
}
