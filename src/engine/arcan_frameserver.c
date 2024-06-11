/*
 * Copyright 2003-2020, Björn Ståhl
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
#include "arcan_shmif_sub.h"
#include "arcan_tui.h"
#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_audio.h"
#include "arcan_audioint.h"
#include "arcan_renderfun.h"

#define FRAMESERVER_PRIVATE
#include "arcan_frameserver.h"
#include "arcan_conductor.h"

#include "arcan_event.h"
#include "arcan_img.h"

/* temporary workaround while migrating */
typedef struct TTF_Font TTF_Font;
#include "../shmif/tui/raster/raster.h"

/*
 * implementation defined for out-of-order execution
 * and reordering protection
 */
#ifndef FORCE_SYNCH
	#define FORCE_SYNCH() {\
		asm volatile("": : :"memory");\
		__sync_synchronize();\
	}
#endif

static int g_buffers_locked;

static inline void emit_deliveredframe(arcan_frameserver* src,
	unsigned long long pts, unsigned long long framecount);
static inline void emit_droppedframe(arcan_frameserver* src,
	unsigned long long pts, unsigned long long framecount);

static void autoclock_frame(arcan_frameserver* tgt)
{
	if (!tgt->clock.left)
		return;

	if (!tgt->clock.frametime)
		tgt->clock.frametime = arcan_frametime();

	int64_t delta = arcan_frametime() - tgt->clock.frametime;

/* something horribly wrong, rebase */
	if (delta < 0){
		tgt->clock.frametime = arcan_frametime();
		return;
	}
	else if (delta == 0)
		return;

/* this is a course-grained optimistic 'wait at least n' timer */
	if (tgt->clock.left <= delta){
		tgt->clock.left = tgt->clock.start;
		tgt->clock.frametime = arcan_frametime();
		arcan_event ev = {
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_STEPFRAME,
			.tgt.ioevs[0].iv = delta / tgt->clock.start,
			.tgt.ioevs[1].uiv = tgt->clock.id
		};

/* don't re-arm if it is a one-off */
		if (tgt->clock.once){
			tgt->clock.left = 0;
		}

		platform_fsrv_pushevent(tgt, &ev);
	}
	else
		tgt->clock.left -= delta;
}

arcan_errc arcan_frameserver_free(arcan_frameserver* src)
{
	if (!src)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (src->fused){
		src->fuse_blown = true;
		return ARCAN_OK;
	}

	arcan_conductor_deregister_frameserver(src);
	arcan_frameserver_close_bufferqueues(src, true, true);

	arcan_aobj_id aid = src->aid;
	uintptr_t tag = src->tag;
	arcan_vobj_id vid = src->vid;

/* unhook audio monitors */
	arcan_aobj_id* base = src->alocks;
	while (base && *base){
		arcan_audio_hookfeed(*base, NULL, NULL, NULL);
		base++;
	}
	src->alocks = NULL;

/* release the font group as well, this has the side effect of a 'pacify-target'
 * call where the frameserver is transformed to a normal video object - no
 * being drawable or responding to font size changes (as font state is lost glyph
 * caches can't be rebuilt or used) - something to reconsider when we can do
 * shared atlases */
	arcan_renderfun_release_fontgroup(src->desc.text.group);
	src->desc.text.group = NULL;

	char msg[32];

	if (src->cookie_fail)
		snprintf(msg, COUNT_OF(msg), "Integrity cookie mismatch");
	else if (!platform_fsrv_lastwords(src, msg, COUNT_OF(msg)))
		snprintf(msg, COUNT_OF(msg), "Couldn't access metadata (SIGBUS?)");

/* make sure there is no other weird dangling state around and forward the
 * client 'last words' as a troubleshooting exit 'status' */
	vfunc_state emptys = {0};
	arcan_video_alterfeed(vid, FFUNC_NULL, emptys);

/* will free, so no UAF here - only time the function returns false is when we
 * are somehow running it twice one the same src */
	if (!platform_fsrv_destroy(src)){
		return ARCAN_ERRC_UNACCEPTED_STATE;
	}

	arcan_audio_stop(aid);

	arcan_event sevent = {
		.category = EVENT_FSRV,
		.fsrv.kind = EVENT_FSRV_TERMINATED,
		.fsrv.video = vid,
		.fsrv.fmt_fl = 0,
		.fsrv.audio = aid,
		.fsrv.otag = tag
	};

	memcpy(&sevent.fsrv.message, msg, COUNT_OF(msg));
	arcan_event_enqueue(arcan_event_defaultctx(), &sevent);

	return ARCAN_OK;
}

/*
 * specialized case, during recovery and adoption the lose association between
 * tgt->parent (vid) is broken as the vid may in some rare cases be reassigned
 * when there's context namespace collisions.
 */
static void default_adoph(arcan_frameserver* tgt, arcan_vobj_id id)
{
	tgt->parent.vid = arcan_video_findstate(
		ARCAN_TAG_FRAMESERV, tgt->parent.ptr);
	tgt->vid = id;
}

bool arcan_frameserver_control_chld(arcan_frameserver* src){
/* bunch of terminating conditions -- frameserver messes with the structure to
 * provoke a vulnerability, frameserver dying or timing out, ... */
	bool cookie_match = true;
	bool alive = src->flags.alive && src->shm.ptr && src->shm.ptr->dms;

/* specifically track the cookie failing issue so that we can forward that as an
 * important failure reason since it is indicative of something more than just a
 * buggy client */
	if (alive){
		alive = platform_fsrv_validchild(src);
		if (alive && src->shm.ptr->cookie != arcan_shmif_cookie()){
			src->cookie_fail = true;
			alive = false;
		}
	}

/* subsegment may well be alive when the parent has just died, thus we need to
 * check the state of the parent and if it is dead, clean up just the same,
 * which will likely lead to kill() and a cascade */
	if (alive && src->parent.vid != ARCAN_EID){
		arcan_vobject* vobj = arcan_video_getobject(src->parent.vid);
		if (!vobj || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
			alive = false;
	}

	if (!alive){
/*
 * This one is really ugly and kept around here as a note. The previous idea
 * was that there might still be relevant content in the queue, e.g. descriptor
 * transfers etc. that one might want to preserve, but combined with the drain-
 * enqueue approach to deal with queue saturation and high-priority event like
 * frameserver could lead to an order issue where there are EXTERNAL_ events
 * on the queue after the corresponding frameserver has been terminated, leading
 * to a possible invalid-tag deref into scripting WM.
 *
		arcan_event_queuetransfer(
			arcan_event_defaultctx(), &src->inqueue, src->queue_mask, 0.5, src);
 */

		arcan_frameserver_free(src);
		return false;
	}

	return true;
}

void arcan_frameserver_close_bufferqueues(
	arcan_frameserver* src, bool incoming, bool pending)
{
	if (!src)
		return;

	if (incoming){
		for (size_t i = 0; i < src->vstream.incoming_used; i++){
			if (src->vstream.incoming[i].fd > 0){
				close(src->vstream.incoming[i].fd);
				src->vstream.incoming[i].fd = -1;
			}
		}
		src->vstream.incoming_used = 0;
	}

	if (pending){
		for (size_t i = 0; i < src->vstream.pending_used; i++){
			if (src->vstream.pending[i].fd > 0){
				close(src->vstream.pending[i].fd);
				src->vstream.pending[i].fd = -1;
			}
		}
		src->vstream.pending_used = 0;
	}
}

/*
 * -1 : fail
 *  0 : ok, no-emit
 *  1 : ok
 */
static int push_buffer(arcan_frameserver* src,
	struct agp_vstore* store, struct arcan_shmif_region* dirty)
{
	struct stream_meta stream = {.buf = NULL};
	bool explicit = src->flags.explicit;
	int rv = 1;

/* we know that vpending contains the latest region that was synched,
 * so the ~vready mask should be the bits that we want to keep. */
	int vready = atomic_load_explicit(&src->shm.ptr->vready,memory_order_consume);
	int vmask=~atomic_load_explicit(&src->shm.ptr->vpending,memory_order_consume);

	TRACE_MARK_ONESHOT("frameserver", "buffer-eval", TRACE_SYS_DEFAULT, src->vid, vready, "");

	vready = (vready <= 0 || vready > src->vbuf_cnt) ? 0 : vready - 1;
	shmif_pixel* buf = src->vbufs[vready];

	if (src->shm.ptr->hints & SHMIF_RHINT_EMPTY)
		goto commit_mask;

/* If the HDR subprotocol is enabled, verify and translate into store metadata
 * - explicitly map the metadata format. There is only the one to chose from
 *   right now, but it wouldn't be surprising if that changes. */
	if (src->desc.aext.hdr && !src->flags.block_hdr_meta){
		struct arcan_shmif_hdr fc = *src->desc.aext.hdr;
		store->hdr.model = 1;
		store->hdr.drm = (struct drm_hdr_meta){
			.eotf = fc.drm.eotf,
			.rx = fc.drm.rx,
			.ry = fc.drm.ry,
			.gx = fc.drm.gx,
			.gy = fc.drm.gy,
			.bx = fc.drm.bx,
			.by = fc.drm.by,
			.wpx = fc.drm.wpx,
			.wpy = fc.drm.wpy,
			.cll = fc.drm.cll_max,
			.fll = fc.drm.fll_max
		};
	}

/* Need to do this check here as-well as in the regular frameserver tick
 * control because the backing store might have changed somehwere else. */
	if (src->desc.width != store->w || src->desc.height != store->h ||
		src->desc.hints != src->desc.pending_hints || src->desc.rz_flag){
		src->desc.hints = src->desc.pending_hints;

		TRACE_MARK_ONESHOT("frameserver", "buffer-resize", TRACE_SYS_DEFAULT,
			src->vid, src->desc.width * src->desc.height, "");

		arcan_event rezev = {
			.category = EVENT_FSRV,
			.fsrv.kind = EVENT_FSRV_RESIZED,
			.fsrv.width = src->desc.width,
			.fsrv.height = src->desc.height,
			.fsrv.video = src->vid,
			.fsrv.audio = src->aid,
			.fsrv.otag = src->tag,
			.fsrv.fmt_fl =
				(src->desc.hints & SHMIF_RHINT_ORIGO_LL) |
				(src->desc.hints & SHMIF_RHINT_TPACK)
		};

/* build a tui context for unpacking our store so that we then can use regular
 * tui calls to read the logical values inside _lua.c and for simple text
 * surfaces */
		if (src->desc.hints & SHMIF_RHINT_TPACK){
			if (!store->vinf.text.tpack.tui){
				store->vinf.text.tpack.tui =
					arcan_tui_setup(NULL, NULL,
						&(struct tui_cbcfg){0}, sizeof(struct tui_cbcfg));
			}

			arcan_tui_wndhint(store->vinf.text.tpack.tui, NULL,
				(struct tui_constraints){
					.max_rows = src->desc.rows,
					.max_cols = src->desc.cols
				});
	}

/* Manually enabled mode where the WM side wants access to the resized buffer
 * but also wants to keep the client locked and waiting. */
		if (src->flags.rz_ack){
			if (src->rz_known == 0){
				arcan_event_enqueue(arcan_event_defaultctx(), &rezev);
				src->rz_known = 1;
				return false;
			}
/* still no response, wait */
			else if (src->rz_known == 1){
				return false;
			}
/* ack:ed, continue with resize */
			else
				src->rz_known = 0;
		}
		else
			arcan_event_enqueue(arcan_event_defaultctx(), &rezev);

		store->vinf.text.d_fmt = (src->desc.hints & SHMIF_RHINT_IGNORE_ALPHA) ||
			src->flags.no_alpha_copy ? GL_NOALPHA_PIXEL_FORMAT : GL_STORE_PIXEL_FORMAT;

/* this might not take if the store is locked - i.e. GPU resources will not
 * match local copies, the main context where that matters is if the vobj is
 * mapped to an output display and thus has a fixed buffer resolution */
		arcan_video_resizefeed(src->vid, src->desc.width, src->desc.height);

		src->desc.rz_flag = false;
		explicit = true;
	}

/* special case, the contents is in a compressed format that can either be
 * rasterized or deferred to on-GPU rasterization / atlas lookup, so the other
 * setup isn't strictly needed. */
	if (src->desc.hints & SHMIF_RHINT_TPACK){
		TRACE_MARK_ENTER("frameserver", "buffer-tpack-raster", TRACE_SYS_DEFAULT, src->vid, 0, "");

/* if the font-group is broken (no hints, ...), set a bitmap only one
 * as well as calculate cell dimensions accordingly */
		if (!src->desc.text.group){
			src->desc.text.group = arcan_renderfun_fontgroup(NULL, 0);
			arcan_renderfun_fontgroup_size(src->desc.text.group,
				0, 0, &src->desc.text.cellw, &src->desc.text.cellh);
		}

/* raster is 'built' every update from whatever caching mechanism is in
 * renderfun, it is only valid for the tui_raster_renderagp call as the
 * contents can be invalidated with any resize/font-size/font change. */
		struct tui_raster_context* raster =
			arcan_renderfun_fontraster(src->desc.text.group);

		size_t buf_sz =
			src->desc.width * src->desc.height * sizeof(shmif_pixel);

		arcan_tui_tunpack(store->vinf.text.tpack.tui,
			(uint8_t*) buf, buf_sz, 0, 0, src->desc.cols, src->desc.rows);

/* This is the next step to change, of course we should merge the buffers into
 * a tpack_vstore and then use normal txcos etc. to pick our visible set, and a
 * MSDF text atlas to get drawing lists, removing the last 'big buffer'
 * requirement, as well as drawing the cursor separately. */
		if (-1 == tui_raster_renderagp(raster, store, (uint8_t*) buf,
			src->desc.width * src->desc.height * sizeof(shmif_pixel), &stream)){
			rv = 0;
			goto commit_mask;
		}

/* when dropping renderagp we'd also want to extract the dirty feedback */
		src->desc.region = (struct arcan_shmif_region){
			.x1 = stream.x1,
			.y1 = stream.y1,
			.x2 = stream.x1 + stream.w,
			.y2 = stream.y1 + stream.h
		};
		src->desc.region_valid = true;

/* Raster failed for some reason - tactics would be to send reset and after
 * n- fails kill it for not complying with format - something to finish when
 * we have the atlas bits in place, and have a DEBUG+dump buffer version */
		if (!stream.buf){
			arcan_warning("client-tpack() - couldn't raster buffer\n");
			rv = 0;
			goto commit_mask;
		}

/* The dst-copy is also a hack / problematic in that way - the invalidation
 * should really be handled in some other way */
		if (store->dst_copy){
			struct agp_region reg = {
				.x1 = stream.x1,
				.y1 = stream.y1,
				.x2 = stream.x1 + stream.w,
				.y2 = stream.y1 + stream.h
			};
			agp_vstore_copyreg(store,
				store->dst_copy, reg.x1, reg.y1, reg.x2, reg.y2);
			platform_video_invalidate_map(store->dst_copy, reg);
		}

		stream = agp_stream_prepare(store, stream, STREAM_RAW_DIRECT);
		agp_stream_commit(store, stream);

/* This is where we should return feedback on kerning in px for picking to be
 * possible on the client end. Set the entire buffer regardless of delta
 * since when we get an actual kerning table in the vstore - it will be cheaper
 * with an aligned (rows * cols) memcpy than to jump around and patch in bytes
 * on the lines that have changed and to have the client do the same thing. */
		size_t i = 0;
		if (!src->desc.height || !src->desc.text.cellh){
			TRACE_MARK_EXIT("frameserver",
				"buffer-tpack-raster", TRACE_SYS_WARN, src->vid, 0, "invalid tpack size");
			rv = 0;
			goto commit_mask;
		}

		size_t n_rows = src->desc.rows;
		size_t n_cols = src->desc.cols;
		size_t n_cells = n_rows * n_cols;

/* fake these values as it means we haven't actually probed the font itself */
		if (!src->desc.text.cellw){
			src->desc.text.cellw = src->desc.width / src->desc.cols;
			src->desc.text.cellh = src->desc.height / src->desc.rows;
		}

/* Size is guaranteed to be >= w * h * tui_cell_size + line_hdr * h + static header */
		memset(buf, src->desc.text.cellw, n_cells);
		buf[n_cells] = 0xff;

		TRACE_MARK_EXIT("frameserver", "buffer-tpack-raster", TRACE_SYS_DEFAULT, src->vid, 0, "");
		goto commit_mask;
	}

	if (src->vstream.pending_used){
		bool failev = src->vstream.dead;

		if (!failev){
/* mapping and bound checking is done inside of arcan_event.c */
			memcpy(stream.planes, src->vstream.pending,
				sizeof(struct agp_buffer_plane) * src->vstream.pending_used);
			stream.used = src->vstream.pending_used;
			stream = agp_stream_prepare(store, stream, STREAM_HANDLE);
			src->vstream.pending_used = 0;

/* the vstream can die because of a format mismatch, platform validation failure
 * or triggered by manually disabling it for this frameserver */
			failev = !stream.state;
		}

/* buffer passing failed, mark that as an unsupported mode for some reason, log
 * and send back to client to revert to shared memory and extra copies */
		if (failev){
			arcan_event ev = {
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_BUFFER_FAIL
			};

/* handle format should be abstracted to platform, but right now it is just
 * mapped as a file-descriptor, if iostreams or windows is reintroduced, this
 * will need to be fixed */
			arcan_event_enqueue(&src->outqueue, &ev);
			arcan_frameserver_close_bufferqueues(src, true, true);
			src->vstream.dead = true;

			TRACE_MARK_ONESHOT("frameserver", "buffer-handle", TRACE_SYS_WARN, src->vid, 0, "platform reject");
		}
		else
			agp_stream_commit(store, stream);

		goto commit_mask;
	}

	stream.buf = buf;
/* validate, fallback to fullsynch if we get bad values */

	if (dirty){
		stream.x1 = dirty->x1; stream.w = dirty->x2 - dirty->x1;
		stream.y1 = dirty->y1; stream.h = dirty->y2 - dirty->y1;
		stream.dirty = /* unsigned but int prom. */
			(dirty->x2 - dirty->x1 > 0 && stream.w <= store->w) &&
			(dirty->y2 - dirty->y1 > 0 && stream.h <= store->h);
		src->desc.region = *dirty;
		src->desc.region_valid = true;
	}
	else
		src->desc.region_valid = false;

/* perhaps also convert hints to message string */
	size_t n_px = stream.w * stream.h;
	TRACE_MARK_ENTER("frameserver", "buffer-upload", TRACE_SYS_DEFAULT, src->vid, n_px, "");

	stream = agp_stream_prepare(store, stream, explicit ?
		STREAM_RAW_DIRECT_SYNCHRONOUS : (
			src->flags.local_copy ? STREAM_RAW_DIRECT_COPY : STREAM_RAW_DIRECT));

	agp_stream_commit(store, stream);
	TRACE_MARK_EXIT("frameserver", "buffer-upload", TRACE_SYS_DEFAULT, src->vid, n_px, "upload");

commit_mask:
	atomic_fetch_and(&src->shm.ptr->vpending, vmask);
	TRACE_MARK_ONESHOT("frameserver", "buffer-release", TRACE_SYS_DEFAULT, src->vid, vmask, "release");
	return rv;
}

enum arcan_ffunc_rv arcan_frameserver_nullfeed FFUNC_HEAD
{
	arcan_frameserver* tgt = state.ptr;

	if (!tgt || state.tag != ARCAN_TAG_FRAMESERV)
		return FRV_NOFRAME;

	TRAMP_GUARD(FRV_NOFRAME, tgt);

	if (cmd == FFUNC_DESTROY)
		arcan_frameserver_free(tgt);

	else if (cmd == FFUNC_ADOPT)
		default_adoph(tgt, srcid);

	else if (cmd == FFUNC_TICK){
		if (!arcan_frameserver_control_chld(tgt))
			goto no_out;

		arcan_event_queuetransfer(
			arcan_event_defaultctx(), &tgt->inqueue, tgt->queue_mask, 0.5, tgt);
	}
	else if (cmd == FFUNC_DESTROY)
		arcan_frameserver_free(tgt);

no_out:
	platform_fsrv_leave();
	return FRV_NOFRAME;
}

enum arcan_ffunc_rv arcan_frameserver_pollffunc FFUNC_HEAD
{
	arcan_frameserver* tgt = state.ptr;
	struct arcan_shmif_page* shmpage = tgt->shm.ptr;
	bool term;

	if (state.tag != ARCAN_TAG_FRAMESERV || !shmpage){
		arcan_warning("platform/posix/frameserver.c:socketpoll, called with"
			" invalid source tag, investigate.\n");
		return FRV_NOFRAME;
	}

/* wait for connection, then unlink directory node and switch to verify. */
	switch (cmd){
	case FFUNC_POLL:{
		int sc = platform_fsrv_socketpoll(tgt);
		if (sc == -1){
/* will yield terminate, close the socket etc. and propagate the event */
			if (errno == EBADF){
				arcan_frameserver_free(tgt);
			}
			return FRV_NOFRAME;
		}

		arcan_video_alterfeed(tgt->vid, FFUNC_SOCKVER, state);

/* this is slightly special, we want to allow the option to re-use the
 * listening point descriptor to avoid some problems from the bind/accept stage
 * that could cause pending connections to time out etc. even though the
 * scripting layer wants to reuse the connection point. To deal with this
 * problem, we keep the domain socket open (sc) and forward to the scripting
 * layer so that it may use it as an argument to listen_external (or close it).
 * */
		arcan_event adopt = {
			.category = EVENT_FSRV,
			.fsrv.kind = EVENT_FSRV_EXTCONN,
			.fsrv.descriptor = sc,
			.fsrv.otag = tgt->tag,
			.fsrv.video = tgt->vid
		};
		snprintf(adopt.fsrv.ident, sizeof(adopt.fsrv.ident)/
			sizeof(adopt.fsrv.ident[0]), "%s", tgt->sockkey);

		arcan_event_enqueue(arcan_event_defaultctx(), &adopt);

		return arcan_frameserver_verifyffunc(
			cmd, buf, buf_sz, width, height, mode, state, tgt->vid);
	}
	break;

/* socket is closed in frameserver_destroy */
	case FFUNC_DESTROY:
		arcan_frameserver_free(tgt);
	break;
	default:
	break;
	}

	return FRV_NOFRAME;
}

enum arcan_ffunc_rv arcan_frameserver_verifyffunc FFUNC_HEAD
{
	arcan_frameserver* tgt = state.ptr;
	char ch = '\n';
	bool term;
	size_t ntw;

	switch (cmd){
/* authentication runs one byte at a time over a call barrier, the function
 * will process the entire key even when they start mismatching. LTO could
 * still try and optimize this and become a timing oracle, but havn't been able
 * to. */
	case FFUNC_POLL:
		while (-1 == platform_fsrv_socketauth(tgt)){
			if (errno == EBADF){
				arcan_frameserver_free(tgt);
				return FRV_NOFRAME;
			}
			else if (errno == EWOULDBLOCK){
				return FRV_NOFRAME;
			}
		}
/* connection is authenticated, switch feed to the normal 'null until
 * first refresh' and try it. */
		arcan_video_alterfeed(tgt->vid, FFUNC_NULLFRAME, state);
		arcan_errc errc;
		tgt->aid = arcan_audio_feed((arcan_afunc_cb)
			arcan_frameserver_audioframe_direct, tgt, &errc);
		tgt->sz_audb = 0;
		tgt->ofs_audb = 0;
		tgt->audb = NULL;
/* no point in trying the frame- poll this round, the odds of the other side
 * preempting us, mapping and populating the buffer etc. are not realistic */
		return FRV_NOFRAME;
	break;
	case FFUNC_DESTROY:
		arcan_frameserver_free(tgt);
	break;
	default:
	break;
	}

	return FRV_NOFRAME;
}

/* mainly used for VFRAME- events on full queue so that the client isn't
 * stuck waiting if it only clocks based on STEPFRAME rather than vready */
static void flush_queued(arcan_frameserver* tgt)
{
	size_t torem = 0;
	for (size_t i = 0; i < tgt->n_pending; i++){
		if (ARCAN_OK != platform_fsrv_pushevent(tgt, &tgt->pending_queue[i]))
			return;
		torem++;
	}

/* full dequeue? */
	if (torem == tgt->n_pending){
		tgt->n_pending = 0;
		return;
	}

/* otherwise partial, move */
	tgt->n_pending = tgt->n_pending - torem;
	memmove(tgt->pending_queue, &tgt->pending_queue[torem],
		sizeof(struct arcan_event) * tgt->n_pending);
}

enum arcan_ffunc_rv arcan_frameserver_emptyframe FFUNC_HEAD
{
	arcan_frameserver* tgt = state.ptr;
	if (!tgt || state.tag != ARCAN_TAG_FRAMESERV)
		return FRV_NOFRAME;

	TRAMP_GUARD(FRV_NOFRAME, tgt);

	switch (cmd){
		case FFUNC_POLL:
			if (tgt->shm.ptr->resized){
				if (arcan_frameserver_tick_control(tgt, false, FFUNC_VFRAME) &&
					tgt->shm.ptr && tgt->shm.ptr->vready){
					platform_fsrv_leave();
					return FRV_GOTFRAME;
				}
			}

			if (tgt->n_pending)
				flush_queued(tgt);

			if (tgt->flags.autoclock && tgt->clock.frame)
				autoclock_frame(tgt);
		break;

		case FFUNC_TICK:
			arcan_frameserver_tick_control(tgt, true, FFUNC_VFRAME);
		break;

		case FFUNC_DESTROY:
			arcan_frameserver_free(tgt);
		break;

		case FFUNC_ADOPT:
			default_adoph(tgt, srcid);
		break;

		default:
		break;
	}

	platform_fsrv_leave();
	return FRV_NOFRAME;
}

void arcan_frameserver_lock_buffers(int state)
{
	g_buffers_locked = state;
}

int arcan_frameserver_releaselock(struct arcan_frameserver* tgt)
{
	if (!tgt->flags.release_pending || !tgt->shm.ptr){
		return 0;
	}

	tgt->flags.release_pending = false;
	TRAMP_GUARD(0, tgt);

	atomic_store_explicit(&tgt->shm.ptr->vready, 0, memory_order_release);
	arcan_sem_post( tgt->vsync );
		if (tgt->desc.hints & SHMIF_RHINT_VSIGNAL_EV){
			arcan_vobject* vobj = arcan_video_getobject(tgt->vid);

			TRACE_MARK_ONESHOT("frameserver", "signal", TRACE_SYS_DEFAULT, tgt->vid, 0, "");
			platform_fsrv_pushevent(tgt, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_STEPFRAME,
				.tgt.ioevs[0].iv = 1,
				.tgt.ioevs[1].iv = 0,
				.tgt.ioevs[2].uiv = vobj ? vobj->owner->msc : 0
			});
		}

	platform_fsrv_leave();
	return 0;
}

enum arcan_ffunc_rv arcan_frameserver_vdirect FFUNC_HEAD
{
	int rv = FRV_NOFRAME;
	bool do_aud = false;

	if (state.tag != ARCAN_TAG_FRAMESERV || !state.ptr)
		return rv;

	arcan_frameserver* tgt = state.ptr;
	struct arcan_shmif_page* shmpage = tgt->shm.ptr;
	if (!shmpage)
		return FRV_NOFRAME;

/* complexity note here: this is to guard against SIGBUS, which becomes
 * quite ugly with ftruncate on a shared page that should support resize
 * under certain conditions. */
	TRAMP_GUARD(FRV_NOFRAME, tgt);

	if (tgt->segid == SEGID_UNKNOWN){
		arcan_frameserver_tick_control(tgt, false, FFUNC_VFRAME);
		goto no_out;
	}

	switch (cmd){
/* silent compiler, this should not happen for a target with a fsrv sink */
	case FFUNC_READBACK:
	case FFUNC_READBACK_HANDLE:
	break;

	case FFUNC_POLL:
		if (shmpage->resized){
			arcan_frameserver_tick_control(tgt, false, FFUNC_VFRAME);
			goto no_out;
		}

		if (tgt->playstate != ARCAN_PLAYING)
			goto no_out;

		if (tgt->n_pending)
			flush_queued(tgt);

/* use this opportunity to make sure that we treat audio as well,
 * when theres the one there is usually the other */
		do_aud =
			(atomic_load(&tgt->shm.ptr->aready) > 0 &&
			atomic_load(&tgt->shm.ptr->apending) > 0);

		if (tgt->flags.autoclock && tgt->clock.frame)
			autoclock_frame(tgt);

/* caller uses this hint to determine if a transfer should be
 * initiated or not */
		rv = (tgt->shm.ptr->vready &&
			!tgt->flags.release_pending) ? FRV_GOTFRAME : FRV_NOFRAME;
	break;

	case FFUNC_TICK:
		if (!arcan_frameserver_tick_control(tgt, true, FFUNC_VFRAME))
			goto no_out;
	break;

	case FFUNC_DESTROY:
		TRACE_MARK_ONESHOT("frameserver", "free", TRACE_SYS_DEFAULT, tgt->vid, 0, "");
		arcan_frameserver_free( tgt );
	break;

	case FFUNC_RENDER:
		TRACE_MARK_ENTER("frameserver", "queue-transfer", TRACE_SYS_DEFAULT, tgt->vid, 0, "");
			switch (arcan_event_queuetransfer(
				arcan_event_defaultctx(),
				&tgt->inqueue, tgt->queue_mask, tgt->xfer_sat, tgt))
			{
			case -2: /* fuse-fail, free */
				arcan_frameserver_free( tgt );
				TRACE_MARK_EXIT("frameserver", "queue-transfer", TRACE_SYS_DEFAULT, tgt->vid, 0, "");
				goto no_out;
			break;
			case -1: /* re-arm, lost */
				TRAMP_GUARD(FRV_NOFRAME, tgt);
			break;
			default: break;
			}
		TRACE_MARK_EXIT("frameserver", "queue-transfer", TRACE_SYS_DEFAULT, tgt->vid, 0, "");

		struct arcan_vobject* vobj = arcan_video_getobject(tgt->vid);

/* frameset can be set to round-robin rotate, so with a frameset we first
 * find the related vstore and if not, the default */
		struct agp_vstore* dst_store = vobj->frameset ?
			vobj->frameset->frames[vobj->frameset->index].frame : vobj->vstore;
		struct arcan_shmif_region dirty = atomic_load(&shmpage->dirty);

/* while we're here, check if audio should be processed as well */
		do_aud = (atomic_load(&tgt->shm.ptr->aready) > 0 &&
			atomic_load(&tgt->shm.ptr->apending) > 0);

/* sometimes, the buffer transfer is forcibly deferred and this needs
 * to be repeat until it succeeds - this mechanism could/should(?) also
 * be used with the vpts- below, simply defer until the deadline has
 * passed */
		if (g_buffers_locked == 1 || tgt->flags.locked)
			goto no_out;

		int buffer_status = push_buffer(tgt,
			dst_store, shmpage->hints & SHMIF_RHINT_SUBREGION ? &dirty : NULL);

		if (-1 == buffer_status)
			goto no_out;

/* TIMING/PRESENT:
 *     for tighter latency management, here is where the estimated next synch
 *     deadline for any output it is used on could/should be set, though it
 *     feeds back into the need of the conductor- refactor */
		dst_store->vinf.text.vpts = shmpage->vpts;

/*     if there's a clock for being triggered in order to be able to submit
 *     contents at a specific MSC on best effort, forward that now. */
		if (tgt->clock.msc_feedback){
			struct arcan_event ev = {
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_STEPFRAME,
				.tgt.ioevs[0].iv = 1,
				.tgt.ioevs[1].iv = 1,
				.tgt.ioevs[2].uiv = vobj->owner->msc
			};

			if (tgt->clock.present &&
				(tgt->clock.present + 1 <= vobj->owner->msc)){
				TRACE_MARK_ONESHOT("frameserver", "present-msc", TRACE_SYS_DEFAULT, tgt->cookie, tgt->clock.present, "");
				platform_fsrv_pushevent(tgt, &ev);
				tgt->clock.present = 0;
				tgt->clock.msc_feedback = false;
			}
			else if (!tgt->clock.present && tgt->clock.last_msc != vobj->owner->msc){
				platform_fsrv_pushevent(tgt, &ev);
				tgt->clock.last_msc = vobj->owner->msc;
			}
		}

/* for some connections, we want additional statistics */
		if (tgt->desc.callback_framestate && buffer_status)
			emit_deliveredframe(tgt, shmpage->vpts, tgt->desc.framecount);
		tgt->desc.framecount++;
		TRACE_MARK_ONESHOT("frameserver", "frame", TRACE_SYS_DEFAULT, tgt->vid, tgt->desc.framecount, "");

/* interactive frameserver blocks on vsemaphore only,
 * so set monitor flags and wake up */
		if (g_buffers_locked != 2){
			atomic_store_explicit(&shmpage->vready, 0, memory_order_release);

			arcan_sem_post( tgt->vsync );
			if (tgt->desc.hints & SHMIF_RHINT_VSIGNAL_EV){
				TRACE_MARK_ONESHOT("frameserver", "signal", TRACE_SYS_DEFAULT, tgt->vid, 0, "");
				platform_fsrv_pushevent(tgt, &(struct arcan_event){
					.category = EVENT_TARGET,
					.tgt.kind = TARGET_COMMAND_STEPFRAME,
					.tgt.ioevs[0].iv = 1,
					.tgt.ioevs[1].iv = 0,
					.tgt.ioevs[2].uiv = vobj ? vobj->owner->msc : 0
				});
			}
		}
		else
			tgt->flags.release_pending = true;
	break;

	case FFUNC_ADOPT:
		default_adoph(tgt, srcid);
	break;
  }

no_out:
	platform_fsrv_leave();

/* we need to defer the fake invocation here to not mess with
 * the signal- guard */
	if (do_aud){
		arcan_aid_refresh(tgt->aid);
	}

	return rv;
}

/*
 * a little bit special, the vstore is already assumed to contain the state
 * that we want to forward, and there's no audio mixing or similar going on, so
 * just copy.
 */
enum arcan_ffunc_rv arcan_frameserver_feedcopy FFUNC_HEAD
{
	assert(state.ptr);
	assert(state.tag == ARCAN_TAG_FRAMESERV);
	arcan_frameserver* src = (arcan_frameserver*) state.ptr;

	TRAMP_GUARD(FRV_NOFRAME, src);

	if (cmd == FFUNC_DESTROY)
		arcan_frameserver_free(state.ptr);

	else if (cmd == FFUNC_ADOPT)
		default_adoph(src, srcid);

	else if (cmd == FFUNC_POLL){
/* done differently since we don't care if the frameserver
 * wants to resize segments used for recording */
		if (!arcan_frameserver_control_chld(src)){
			platform_fsrv_leave();
			return FRV_NOFRAME;
		}

/* only push an update when the target is ready and the
 * monitored source has updated its backing store */
		if (!src->shm.ptr->vready){
			arcan_vobject* me = arcan_video_getobject(src->vid);
			if (me->vstore->update_ts == src->desc.synch_ts)
				goto leave;
			src->desc.synch_ts = me->vstore->update_ts;

			if (src->shm.ptr->w!=me->vstore->w || src->shm.ptr->h!=me->vstore->h){
				arcan_frameserver_free(state.ptr);
				goto leave;
			}

			arcan_event ev  = {
				.tgt.kind = TARGET_COMMAND_STEPFRAME,
				.category = EVENT_TARGET,
				.tgt.ioevs[0] = src->vfcount++
			};

			memcpy(src->vbufs[0],
				me->vstore->vinf.text.raw, me->vstore->vinf.text.s_raw);
			src->shm.ptr->vpts = me->vstore->vinf.text.vpts;
			src->shm.ptr->vready = true;
			FORCE_SYNCH();

			if (ARCAN_OK != platform_fsrv_pushevent(src, &ev) &&
				src->n_pending < COUNT_OF(src->pending_queue)){
				src->pending_queue[src->n_pending++] = ev;
			}
		}

		if (src->flags.autoclock && src->clock.frame)
			autoclock_frame(src);

		if (-2 ==
			arcan_event_queuetransfer(arcan_event_defaultctx(),
				&src->inqueue, src->queue_mask, src->xfer_sat, src)){
			arcan_frameserver_free(src);
		}
	}

leave:
	platform_fsrv_leave();
	return FRV_NOFRAME;
}

enum arcan_ffunc_rv arcan_frameserver_avfeedframe FFUNC_HEAD
{
	assert(state.ptr);
	assert(state.tag == ARCAN_TAG_FRAMESERV);
	arcan_frameserver* src = (arcan_frameserver*) state.ptr;

	int rv = FRV_NOFRAME;
	TRAMP_GUARD(FRV_NOFRAME, src);

	if (cmd == FFUNC_DESTROY)
		arcan_frameserver_free(src);

	else if (cmd == FFUNC_ADOPT)
		default_adoph(src, srcid);

	else if (cmd == FFUNC_TICK){
/* done differently since we don't care if the frameserver
 * wants to resize segments used for recording */
		if (!arcan_frameserver_control_chld(src))
			goto no_out;

		arcan_event_queuetransfer(
			arcan_event_defaultctx(), &src->inqueue, src->queue_mask, 0.5, src);
	}
/* mark that we are actually busy still */
	else if (cmd == FFUNC_POLL){
		if (atomic_load(&src->shm.ptr->vready)){
			rv = FRV_GOTFRAME;
			goto no_out;
		}
	}
/*
 * if the frameserver isn't ready to receive (semaphore unlocked) then the
 * frame will be dropped, a warning noting that the frameserver isn't fast
 * enough to deal with the data (allowed to duplicate frame to maintain
 * framerate, it can catch up reasonably by using less CPU intensive frame
 * format. Audio will keep on buffering until overflow.
 */
	else if (cmd == FFUNC_READBACK || cmd == FFUNC_READBACK_HANDLE){
		if (!src->shm.ptr){
			vfunc_state emptys = {0};
			arcan_video_alterfeed(src->vid, FFUNC_NULL, emptys);
			rv = FRV_NOFRAME;
			goto no_out;
		}

		if (src->shm.ptr && !src->shm.ptr->vready){
			arcan_event ev  = {
				.tgt.kind = TARGET_COMMAND_STEPFRAME,
				.category = EVENT_TARGET,
			};

			if (src->ofs_audb){
				memcpy(src->abufs[0], src->audb, src->ofs_audb);
				src->shm.ptr->abufused[0] = src->ofs_audb;
				src->ofs_audb = 0;
			}

/*
 * it is possible that we deliver more videoframes than we can legitimately
 * encode in the target framerate, it is up to the frameserver to determine
 * when to drop and when to double frames
 */
			struct arcan_shmif_region reg;
			if (src->desc.region_valid)
				reg = src->desc.region;
			else
				reg = (struct arcan_shmif_region){
					.x2 = src->desc.width, .y2 = src->desc.height
				};

			atomic_store(&src->shm.ptr->vpts, arcan_timemillis());
			atomic_store(&src->shm.ptr->dirty, reg);

	/* only mark vready if we go the manual buffer route, otherwise the device
	 * events act as clock */
			if (cmd == FFUNC_READBACK){
				memcpy(src->vbufs[0], buf, buf_sz);
				ev.tgt.ioevs[0].iv = src->vfcount++;
				atomic_store(&src->shm.ptr->vready, 1);
				platform_fsrv_pushevent(src, &ev);
			}

/* for handle-passing we swap the vstore instead and send that one - ideally we
 * would send the set once and then instead use the STEPFRAME to mark which
 * slot that is now signalled and let the sink update a mask of which ones it
 * currently holds. */
			else {
				ev.tgt.kind = TARGET_COMMAND_DEVICE_NODE;
				ev.tgt.ioevs[2].iv = 0; /* indirect handle, will be static RGBx */
				ev.tgt.ioevs[3].iv = 0; /* GBM buffer */

/* If we can't export the vstore, log a warning about the fact and then disable
 * the handle-passing capability flag. This applies for 'cant export at all' or
 * export as multiple output planes (still need basic bringup of 1p) */
				size_t np;
				struct agp_buffer_plane planes[4];
				struct rendertarget* tgt;
				arcan_vobject* vobj = arcan_video_getobject(src->vid);

				if (!vobj || !(tgt = arcan_vint_findrt(vobj))){
					arcan_warning(
						"Couldn't find rendertarget for frameserver, revert shm", src->vid);
					goto no_out;
				}

/* this will cause the first frame to be deferred in delivery, if latency
 * is important the prior processing need to push multiple updates even if
 * no change to prime the chain. */
				bool swap = false;
				struct agp_vstore* vs = agp_rendertarget_swap(tgt->art, &swap);
				if (!swap){
					goto no_out;
				}

				if (1 != (np =
					platform_video_export_vstore(vs, planes, COUNT_OF(planes)))){
					arcan_warning(
						"Platform rejected export of (%"PRIxVOBJ"), revert shm", 1);
					tgt->hwreadback = false;
				}
/* only export the plane- descriptor and not the fence, as we are locked into a
 * 1-event-1-fd and the variants of fd slots % 4 != 0 versus having the
 * aforementioned allocation scheme aren't worh it, especially since OUTPUT
 * doesn't permit resize. */
				else {
					platform_fsrv_pushfd(src, &ev, planes[0].fd);
				}

/* after export we don't need the created handles, ownership goes to recpt. */
				if (np){
					for (size_t i = 0; i < np; i++){
						if (-1 != planes[i].fd)
							close(planes[i].fd);
						if (-1 != planes[i].fence)
							close(planes[i].fence);
					}
				}
			}

			if (src->desc.callback_framestate)
				emit_deliveredframe(src, 0, src->desc.framecount++);
		}
		else {
			if (src->desc.callback_framestate)
				emit_droppedframe(src, 0, src->desc.dropcount++);
		}
	}
	else
			;

no_out:
	platform_fsrv_leave();
	return rv;
}

/* assumptions:
 * buf_sz doesn't contain partial samples (% (bytes per sample * channels))
 * dst->amixer inaud is allocated and allocation count matches n_aids */
static void feed_amixer(arcan_frameserver* dst, arcan_aobj_id srcid,
	int16_t* buf, int nsamples)
{
/* formats; nsamples (samples in, 2 samples / frame)
 * cur->inbuf; samples converted to float with gain, 2 samples / frame)
 * dst->outbuf; SINT16, in bytes, ofset in bytes */
	size_t minv = INT_MAX;

/* 1. Convert to float and buffer. Find the lowest common number of samples
 * buffered. Truncate if needed. Assume source feeds L/R */
	for (int i = 0; i < dst->amixer.n_aids; i++){
		struct frameserver_audsrc* cur = dst->amixer.inaud + i;

		if (cur->src_aid == srcid){
			int ulim = sizeof(cur->inbuf) / sizeof(float);
			int count = 0;

			while (nsamples-- && cur->inofs < ulim){
				float val = *buf++;
				cur->inbuf[cur->inofs++] =
					(count++ % 2 ? cur->l_gain : cur->r_gain) * (val / 32767.0f);
			}
		}

		if (cur->inofs < minv)
			minv = cur->inofs;
	}

/*
 * 2. If number of samples exceeds some threshold, mix (minv)
 * samples together and store in dst->outb Formulae used:
 * A = float(sampleA) * gainA.
 * B = float(sampleB) * gainB. Z = A + B - A * B
 */
		if (minv != INT_MAX && minv > 512 && dst->sz_audb - dst->ofs_audb > 0){
/* clamp */
			if (dst->ofs_audb + minv * sizeof(uint16_t) > dst->sz_audb)
				minv = (dst->sz_audb - dst->ofs_audb) / sizeof(uint16_t);

			for (int sc = 0; sc < minv; sc++){
				float work_sample = 0;

			for (int i = 0; i < dst->amixer.n_aids; i++){
				work_sample += dst->amixer.inaud[i].inbuf[sc] - (work_sample *
					dst->amixer.inaud[i].inbuf[sc]);
			}
/* clip output */
			int16_t sample_conv = work_sample >= 1.0 ? 32767.0 :
				(work_sample < -1.0 ? -32768 : work_sample * 32767);
			memcpy(&dst->audb[dst->ofs_audb], &sample_conv, sizeof(int16_t));
			dst->ofs_audb += sizeof(int16_t);
		}
/* 2b. Reset intermediate buffers, slide if needed. */
		for (int j = 0; j < dst->amixer.n_aids; j++){
			struct frameserver_audsrc* cur = dst->amixer.inaud + j;
			if (cur->inofs > minv){
				memmove(cur->inbuf, &cur->inbuf[minv], (cur->inofs - minv) *
					sizeof(float));
				cur->inofs -= minv;
			}
			else
				cur->inofs = 0;
		}
	}

}

void arcan_frameserver_update_mixweight(arcan_frameserver* dst,
	arcan_aobj_id src, float left, float right)
{
	for (int i = 0; i < dst->amixer.n_aids; i++){
		if (src == 0 || dst->amixer.inaud[i].src_aid == src){
			dst->amixer.inaud[i].l_gain = left;
			dst->amixer.inaud[i].r_gain = right;
		}
	}
}

void arcan_frameserver_avfeed_mixer(arcan_frameserver* dst, int n_sources,
	arcan_aobj_id* sources)
{
	assert(sources != NULL && dst != NULL && n_sources > 0);

	if (dst->amixer.n_aids)
		arcan_mem_free(dst->amixer.inaud);

	dst->amixer.inaud = arcan_alloc_mem(
		n_sources * sizeof(struct frameserver_audsrc),
		ARCAN_MEM_ATAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	for (int i = 0; i < n_sources; i++){
		dst->amixer.inaud[i].l_gain  = 1.0;
		dst->amixer.inaud[i].r_gain  = 1.0;
		dst->amixer.inaud[i].inofs   = 0;
		dst->amixer.inaud[i].src_aid = *sources++;
	}

	dst->amixer.n_aids = n_sources;
}

void arcan_frameserver_avfeedmon(arcan_aobj_id src, uint8_t* buf,
	size_t buf_sz, unsigned channels, unsigned frequency, void* tag)
{
	arcan_frameserver* dst = tag;
	assert((intptr_t)(buf) % 4 == 0);

/*
 * FIXME: This is a victim of a recent shmif refactor where we started to
 * allow negotating different samplerates. This should be complemented with
 * the speex- resampler that's in the codebase already
 */
	if (frequency != ARCAN_SHMIF_SAMPLERATE){
		static bool warn;
		if (!warn){
			arcan_warning("arcan_frameserver_avfeedmon(), monitoring an audio feed\n"
				"with a non-native samplerate, this is >currently< supported for\n"
				"playback but not for recording (TOFIX).\n");
			warn = true;
		}
	}

/*
 * with no mixing setup (lowest latency path), we just feed the sync buffer
 * shared with the frameserver. otherwise we forward to the amixer that is
 * responsible for pushing as much as has been generated by all the defined
 * sources
 */
	if (dst->amixer.n_aids > 0){
		feed_amixer(dst, src, (int16_t*) buf, buf_sz >> 1);
	}
	else if (dst->ofs_audb + buf_sz < dst->sz_audb){
			memcpy(dst->audb + dst->ofs_audb, buf, buf_sz);
			dst->ofs_audb += buf_sz;
	}
	else;
}

static inline void emit_deliveredframe(arcan_frameserver* src,
	unsigned long long pts, unsigned long long framecount)
{
	arcan_event ev = {
		.category = EVENT_FSRV,
		.fsrv.kind = EVENT_FSRV_DELIVEREDFRAME,
		.fsrv.pts = pts,
		.fsrv.counter = framecount,
		.fsrv.otag = src->tag,
		.fsrv.audio = src->aid,
		.fsrv.video = src->vid
	};

	if (src->desc.region_valid){
		ev.fsrv.xofs = src->desc.region.x1;
		ev.fsrv.yofs = src->desc.region.y1;
		ev.fsrv.width = src->desc.region.x2 - src->desc.region.x1;
		ev.fsrv.height = src->desc.region.y2 - src->desc.region.y1;
	}
	else{
		ev.fsrv.width = src->desc.width;
		ev.fsrv.height = src->desc.height;
	}

	arcan_event_enqueue(arcan_event_defaultctx(), &ev);
}

static inline void emit_droppedframe(arcan_frameserver* src,
	unsigned long long pts, unsigned long long dropcount)
{
	arcan_event deliv = {
		.category = EVENT_FSRV,
		.fsrv.kind = EVENT_FSRV_DROPPEDFRAME,
		.fsrv.pts = pts,
		.fsrv.counter = dropcount,
		.fsrv.otag = src->tag,
		.fsrv.audio = src->aid,
		.fsrv.video = src->vid
	};

	arcan_event_enqueue(arcan_event_defaultctx(), &deliv);
}

bool arcan_frameserver_getramps(arcan_frameserver* src,
	size_t index, float* table, size_t table_sz, size_t* ch_sz)
{
	if (!ch_sz || !table || !src || !src->desc.aext.gamma)
		return false;

	struct arcan_shmif_ramp* dm = src->desc.aext.gamma;
	if (!dm || dm->magic != ARCAN_SHMIF_RAMPMAGIC)
		return false;

/* note, we can't rely on the page block counter as the source isn't trusted to
 * set/manage that information, rely on the requirement that display- index set
 * size is constant */
	size_t lim;
	platform_video_displays(NULL, &lim);

	if (index >= lim)
		return false;

/* only allow ramp-retrieval once and only for one that is marked dirty */
	if (!(dm->dirty_out & (1 << index)))
		return false;

/* we always ignore EDID, that one is read/only */
	struct ramp_block block;
	memcpy(&block, &dm->ramps[index * 2], sizeof(struct ramp_block));

	uint16_t checksum = subp_checksum(
		block.edid, sizeof(block.edid) + SHMIF_CMRAMP_UPLIM);

/* Checksum verification failed, either this has been done deliberately and
 * we're in a bit of a situation since there's no strong mechanism for the
 * caller to know this is the reason and that we need to wait and recheck.
 * If we revert the tracking-bit, the event updates will be correct again,
 * but we are introducing a 'sortof' event-queue storm of 1 event/tick.
 *
 * The decision, for now, is to take that risk and let the ratelimit+kill
 * action happen in the scripting layer. */

	src->desc.aext.gamma_map &= ~(1 << index);
	if (checksum != block.checksum)
		return false;

	memcpy(table, block.planes,
		table_sz < SHMIF_CMRAMP_UPLIM ? table_sz : SHMIF_CMRAMP_UPLIM);

	memcpy(ch_sz, block.plane_sizes, sizeof(size_t)*SHMIF_CMRAMP_PLIM);

	atomic_fetch_and(&dm->dirty_out, ~(1<<index));
	return true;
}

/*
 * Used to update a specific client's perception of a specific ramp,
 * the index must be < (ramp_limit-1) which is a platform defined static
 * upper limit of supported number of displays and ramps.
 */
bool arcan_frameserver_setramps(
	arcan_frameserver* src,
	size_t index,
	float* table, size_t table_sz,
	size_t ch_sz[SHMIF_CMRAMP_PLIM],
	uint8_t* edid, size_t edid_sz)
{
	if (!ch_sz || !table || !src || !src->desc.aext.gamma)
		return false;

	size_t lim;
	platform_video_displays(NULL, &lim);

	if (index >= lim)
		return false;

/* verify that we fit */
	size_t sum = 0;
	for (size_t i = 0; i < SHMIF_CMRAMP_PLIM; i++){
		sum += ch_sz[i];
	}
	if (sum > SHMIF_CMRAMP_UPLIM)
		return false;

/* prepare a local copy and throw it in there */
	struct ramp_block block = {0};
	memcpy(block.plane_sizes, ch_sz, sizeof(size_t)*SHMIF_CMRAMP_PLIM);

/* first the actual samples */
	size_t pdata_sz = SHMIF_CMRAMP_UPLIM;
	if (pdata_sz > table_sz)
		pdata_sz = table_sz;
	memcpy(block.planes, table, pdata_sz);

/* EDID block is optional, full == 0 to indicate disabled */
	size_t edid_bsz = sizeof(src->desc.aext.gamma->ramps[index].edid);
	if (edid && edid_sz == edid_bsz)
		memcpy(src->desc.aext.gamma->ramps[index].edid, edid, edid_bsz);

/* checksum only applies to edid+planedata */
	block.checksum = subp_checksum(
		(uint8_t*)block.edid, edid_bsz + SHMIF_CMRAMP_UPLIM);

/* flush- to buffer */
	memcpy(&src->desc.aext.gamma->ramps[index], &block, sizeof(block));

/* and set the magic bit */
	atomic_fetch_or(&src->desc.aext.gamma->dirty_in, 1 << index);

	return true;
}

/*
 * This is a legacy- feed interface and doesn't reflect how the shmif audio
 * buffering works. Hence we ignore queing to the selected buffer, and instead
 * use a populate function to retrieve at most n' buffers that we then fill.
 */
arcan_errc arcan_frameserver_audioframe_direct(void* aobj,
	arcan_aobj_id id, unsigned buffer, bool cont, void* tag)
{
	arcan_frameserver* src = (arcan_frameserver*) tag;

	if (buffer == -1 || src->segid == SEGID_UNKNOWN)
		return ARCAN_ERRC_NOTREADY;

	if (src->watch_const != 0xfeed)
		return ARCAN_ERRC_UNACCEPTED_STATE;

/* we need to switch to an interface where we can retrieve a set number of
 * buffers, matching the number of set bits in amask, then walk from ind-1 and
 * buffering all */
	if (!src->shm.ptr)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	TRAMP_GUARD(ARCAN_ERRC_UNACCEPTED_STATE, src);

	volatile int ind = atomic_load(&src->shm.ptr->aready) - 1;
	volatile int amask = atomic_load(&src->shm.ptr->apending);

/* sanity check, untrusted source */
	if (ind >= src->abuf_cnt || ind < 0){
		platform_fsrv_leave();
		return ARCAN_ERRC_NOTREADY;
	}

	if (0 == amask || ((1<<ind)&amask) == 0){
		atomic_store_explicit(&src->shm.ptr->aready, 0, memory_order_release);
		platform_fsrv_leave();
		arcan_sem_post(src->async);
		return ARCAN_ERRC_NOTREADY;
	}

/* find oldest buffer, we know there is at least one */
	int i = ind, prev;
	do {
		prev = i;
		i--;
		if (i < 0)
			i = src->abuf_cnt-1;
	} while (i != ind && ((1<<i)&amask) > 0);

	if (!src->audio_flush_pending){
		arcan_audio_buffer(aobj, buffer,
			src->abufs[prev], src->shm.ptr->abufused[prev],
			src->desc.channels, src->desc.samplerate, tag
		);

		atomic_store(&src->shm.ptr->abufused[prev], 0);
		int last = atomic_fetch_and_explicit(&src->shm.ptr->apending,
				~(1 << prev), memory_order_release);
	}
	else {
		atomic_store(&src->shm.ptr->apending, 0);
		src->audio_flush_pending = false;
	}

/* check for cont and > 1, wait for signal.. else release */
	if (!cont){
		atomic_store_explicit(&src->shm.ptr->aready, 0, memory_order_release);
		platform_fsrv_leave();
		arcan_sem_post(src->async);
	}

	return ARCAN_OK;
}

bool arcan_frameserver_tick_control(
	arcan_frameserver* src, bool tick, int dst_ffunc)
{
	bool fail = true;
	if (!arcan_frameserver_control_chld(src) || src->playstate == ARCAN_PAUSED)
		goto leave;

/* Same event-queue transfer issues as marked elsewhere, if xfer-sat goes to
 * drain, VM accepts drain and modifies fsrv state special action is needed.
 * Nesting longjmp handlers </3 */
	int rv =
		arcan_event_queuetransfer(arcan_event_defaultctx(),
			&src->inqueue, src->queue_mask, src->xfer_sat, src);

	if (-2 == rv){
		arcan_frameserver_free(src);
		goto leave;
	}

	if (-1 == rv)
		goto leave;

	if (!src->shm.ptr->resized){
		fail = false;
		goto leave;
	}

	FORCE_SYNCH();

/*
 * This used to be considered suspicious behavior but with the option to switch
 * buffering strategies, and the protocol for that is the same as resize, we no
 * longer warn, but keep the code here commented as a note to it

 if (src->desc.width == neww && src->desc.height == newh){
		arcan_warning("tick_control(), source requested "
			"resize to current dimensions.\n");
		goto leave;
	}

	in the same fashion, we killed on resize failure, but that did not work well
	with switching buffer strategies (valid buffer in one size, failed because
	size over reach with other strategy, so now there's a failure mechanism.
 */

/* Invalidate any ongoing buffer-streams */
	if (src->desc.width != src->shm.ptr->w || src->desc.height != src->shm.ptr->h){
		arcan_frameserver_close_bufferqueues(src, true, true);
	}

	int rzc = platform_fsrv_resynch(src);
	if (rzc <= 0)
		goto leave;
	else if (rzc == 2){
		arcan_event_enqueue(arcan_event_defaultctx(),
			&(struct arcan_event){
				.category = EVENT_FSRV,
				.fsrv.kind = EVENT_FSRV_APROTO,
				.fsrv.video = src->vid,
				.fsrv.aproto = src->desc.aproto,
				.fsrv.otag = src->tag,
			});
	}
	fail = false;

/*
 * at this stage, frameserver impl. should have remapped event queues,
 * vbuf/abufs, and signaled the connected process. Make sure we are running the
 * right feed function (may have been turned into another or started in a
 * passive one
 */
	vfunc_state cstate = *arcan_video_feedstate(src->vid);
	arcan_video_alterfeed(src->vid, dst_ffunc, cstate);

/*
 * Check if the dirty- mask for the ramp- subproto has changed, enqueue the
 * ones that havn't been retrieved (hence the local map) as ramp-update events.
 * There's no copy- and mark as read, that has to be done from the next layer.
 */
leave:
	if (!fail && src->desc.aproto & SHMIF_META_CM && src->desc.aext.gamma){
		uint8_t in_map = atomic_load(&src->desc.aext.gamma->dirty_out);
		for (size_t i = 0; i < 8; i++){
			if ((in_map & (1 << i)) && !(src->desc.aext.gamma_map & (1 << i))){
				arcan_event_enqueue(arcan_event_defaultctx(), &(arcan_event){
					.category = EVENT_FSRV,
					.fsrv.kind = EVENT_FSRV_GAMMARAMP,
					.fsrv.counter = i,
					.fsrv.video = src->vid
				});
				src->desc.aext.gamma_map |= 1 << i;
			}
		}
	}

/* want the event to be queued after resize so the possible reaction (i.e.
 * redraw + synch) aligns with pending resize */
	if (!fail && tick){
		if (0 >= --src->clock.left){
			src->clock.left = src->clock.start;
			platform_fsrv_pushevent(src, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_STEPFRAME,
				.tgt.ioevs[0].iv = 1,
				.tgt.ioevs[1].iv = src->clock.id
			});
		}
	}
	return !fail;
}

arcan_errc arcan_frameserver_pause(arcan_frameserver* src)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (src) {
		src->playstate = ARCAN_PAUSED;
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_frameserver_resume(arcan_frameserver* src)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	if (src)
		src->playstate = ARCAN_PLAYING;

	return rv;
}

arcan_errc arcan_frameserver_flush(arcan_frameserver* fsrv)
{
	if (!fsrv)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	fsrv->audio_flush_pending = true;
	arcan_audio_rebuild(fsrv->aid);

	return ARCAN_OK;
}

arcan_errc arcan_frameserver_setfont(
	struct arcan_frameserver* fsrv, int fd, float sz, int hint, int slot)
{
	if (!fsrv)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	bool replace = true;
	bool reprobe = false;

/* always update primary slot size */
	if (slot == 0){
		if (sz > EPSILON){
			fsrv->desc.text.szmm = sz;
			reprobe = true;
		}

/* first time and main slot? then build the group */
		if (!fsrv->desc.text.group){
			if (fsrv->desc.hint.ppcm < EPSILON){
				arcan_vobject* vobj = arcan_video_getobject(fsrv->vid);

/* Protect against someone in the future creating a frameserver first and
 * force-setting a font in the platform or elsewhere without properly attaching
 * it to a valid and attached vobject - note that vppcm/hppcm are treated as
 * uniform here which isn't entirely correct. Freetype can deal with vdpi!=hdpi
 * but we missed it in the DISPLAYHINT event format "square assumed" */
				struct rendertarget* tgt;
				if (!vobj || !(tgt = arcan_vint_findrt(vobj))){
					fsrv->desc.hint.ppcm = 38.7;
				}
				else {
					fsrv->desc.hint.ppcm = tgt->vppcm;
				}
			}

			fsrv->desc.text.group =
				arcan_renderfun_fontgroup((int[]){dup(fd), BADFD, BADFD, BADFD}, 4);
			replace = false;
		}
	}

/* supplementary slot but no group? */
	if (!fsrv->desc.text.group){
		close(fd);
		return ARCAN_ERRC_UNACCEPTED_STATE;
	}

	if (replace && fd != -1)
		arcan_renderfun_fontgroup_replace(fsrv->desc.text.group, slot, fd);

	if (reprobe && fsrv->desc.hint.ppcm > EPSILON){
		arcan_renderfun_fontgroup_size(fsrv->desc.text.group,
			fsrv->desc.text.szmm, fsrv->desc.hint.ppcm,
			&fsrv->desc.text.cellw, &fsrv->desc.text.cellh);
	}

	return ARCAN_OK;
}

void arcan_frameserver_displayhint(
	struct arcan_frameserver* fsrv, size_t w, size_t h, float ppcm)
{
	if (!fsrv)
		return;

	if (w > 0)
		fsrv->desc.hint.width = w;

	if (h > 0)
		fsrv->desc.hint.height = h;

/* if we have a new density, this should be forwarded to any attached
 * rasterizer which may cause a different cell size to be communicated */
	if (ppcm > EPSILON && ppcm != fsrv->desc.hint.ppcm){
		fsrv->desc.hint.ppcm = ppcm;

/* we don't actually care to use the raster, just want to re-probe size */
		if (fsrv->desc.text.group){
			arcan_renderfun_fontgroup_size(fsrv->desc.text.group,
				0, ppcm, &fsrv->desc.text.cellw, &fsrv->desc.text.cellh);
		}
	}
}
