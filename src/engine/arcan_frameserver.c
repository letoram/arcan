/*
 * Copyright 2003-2017, Björn Ståhl
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
#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_audio.h"
#include "arcan_audioint.h"

#define FRAMESERVER_PRIVATE
#include "arcan_frameserver.h"
#include "arcan_conductor.h"

#include "arcan_event.h"
#include "arcan_img.h"

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
	if (delta < 0){

	}
	else if (delta == 0)
		return;

	if (tgt->clock.left <= delta){
		tgt->clock.left = tgt->clock.start;
		tgt->clock.frametime = arcan_frametime();
		arcan_event ev = {
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_STEPFRAME,
			.tgt.ioevs[0].iv = delta / tgt->clock.start,
			.tgt.ioevs[1].iv = 1
		};
		platform_fsrv_pushevent(tgt, &ev);
	}
	else
		tgt->clock.left -= delta;
}

arcan_errc arcan_frameserver_free(arcan_frameserver* src)
{
	if (!src)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	arcan_conductor_deregister_frameserver(src);

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

	char msg[32];
	if (!platform_fsrv_lastwords(src, msg, COUNT_OF(msg)))
		snprintf(msg, COUNT_OF(msg), "Couldn't access metadata (SIGBUS?)");

/* will free, so no UAF here - only time the function returns false is when we
 * are somehow running it twice one the same src */
	if (!platform_fsrv_destroy(src))
		return ARCAN_ERRC_UNACCEPTED_STATE;

	arcan_audio_stop(aid);
	vfunc_state emptys = {0};

	arcan_video_alterfeed(vid, FFUNC_NULL, emptys);

	arcan_event sevent = {
		.category = EVENT_FSRV,
		.fsrv.kind = EVENT_FSRV_TERMINATED,
		.fsrv.video = vid,
		.fsrv.glsource = false,
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

static bool arcan_frameserver_control_chld(arcan_frameserver* src){
/* bunch of terminating conditions -- frameserver messes with the structure to
 * provoke a vulnerability, frameserver dying or timing out, ... */
	bool alive = src->flags.alive && src->shm.ptr &&
		src->shm.ptr->cookie == arcan_shmif_cookie() &&
		platform_fsrv_validchild(src);

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

static bool push_buffer(arcan_frameserver* src,
	struct agp_vstore* store, struct arcan_shmif_region* dirty)
{
	struct stream_meta stream = {.buf = NULL};
	bool explicit = src->flags.explicit;

/* we know that vpending contains the latest region that was synched,
 * so the ~vready mask should be the bits that we want to keep. */
	int vready = atomic_load_explicit(&src->shm.ptr->vready,memory_order_consume);
	int vmask=~atomic_load_explicit(&src->shm.ptr->vpending,memory_order_consume);
	vready = (vready <= 0 || vready > src->vbuf_cnt) ? 0 : vready - 1;
	shmif_pixel* buf = src->vbufs[vready];

/* Need to do this check here as-well as in the regular frameserver tick
 * control because the backing store might have changed somehwere else. */
	if (src->desc.width != store->w || src->desc.height != store->h ||
		src->desc.hints != src->desc.pending_hints || src->desc.rz_flag){

		arcan_event rezev = {
			.category = EVENT_FSRV,
			.fsrv.kind = EVENT_FSRV_RESIZED,
			.fsrv.width = src->desc.width,
			.fsrv.height = src->desc.height,
			.fsrv.video = src->vid,
			.fsrv.audio = src->aid,
			.fsrv.otag = src->tag,
			.fsrv.glsource = src->desc.hints & SHMIF_RHINT_ORIGO_LL
		};

		if (src->flags.rz_ack){
/* mark ack and send event */
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

		src->desc.hints = src->desc.pending_hints;
		store->vinf.text.d_fmt = (src->desc.hints & SHMIF_RHINT_IGNORE_ALPHA) ||
			src->flags.no_alpha_copy ? GL_NOALPHA_PIXEL_FORMAT : GL_STORE_PIXEL_FORMAT;

		arcan_video_resizefeed(src->vid, src->desc.width, src->desc.height);

		src->desc.rz_flag = false;
		explicit = true;
	}

	if (-1 != src->vstream.handle){
		bool failev = src->vstream.dead;

/* the vstream can die because of a format mismatch, platform validation failure
 * or triggered by manually disabling it for this frameserver */
		if (!failev){
			stream.handle = src->vstream.handle;
			store->vinf.text.stride = src->vstream.stride;
			store->vinf.text.format = src->vstream.format;
			stream = agp_stream_prepare(store, stream, STREAM_HANDLE);
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
			src->vstream.dead = true;
			close(src->vstream.handle);
			src->vstream.handle = -1;
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
	}
	stream = agp_stream_prepare(store, stream, explicit ?
		STREAM_RAW_DIRECT_SYNCHRONOUS : (
			src->flags.local_copy ? STREAM_RAW_DIRECT_COPY : STREAM_RAW_DIRECT));

	agp_stream_commit(store, stream);
commit_mask:
	atomic_fetch_and(&src->shm.ptr->vpending, vmask);
	return true;
}

enum arcan_ffunc_rv arcan_frameserver_nullfeed FFUNC_HEAD
{
	arcan_frameserver* tgt = state.ptr;

	if (!tgt || state.tag != ARCAN_TAG_FRAMESERV)
		return FRV_NOFRAME;

	TRAMP_GUARD(FRV_NOFRAME, tgt);

	if (cmd == FFUNC_DESTROY)
		arcan_frameserver_free(state.ptr);

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
	if (!tgt->flags.release_pending){
		return 0;
	}

	tgt->flags.release_pending = false;
	TRAMP_GUARD(0, tgt);

	atomic_store_explicit(&tgt->shm.ptr->vready, 0, memory_order_release);
	arcan_sem_post( tgt->vsync );
		if (tgt->desc.hints & SHMIF_RHINT_VSIGNAL_EV){
			platform_fsrv_pushevent(tgt, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_STEPFRAME,
				.tgt.ioevs[0].iv = 1,
				.tgt.ioevs[1].iv = 0
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
/* silent compiler, this should not happen for a target with a
 * frameserver feeding it */
	case FFUNC_READBACK:
	break;

	case FFUNC_POLL:
		if (shmpage->resized){
			arcan_frameserver_tick_control(tgt, false, FFUNC_VFRAME);
			goto no_out;
		}

		if (tgt->playstate != ARCAN_PLAYING)
			goto no_out;

/* use this opportunity to make sure that we treat audio as well,
 * when theres the one there is usually the other */
			do_aud = (atomic_load(&tgt->shm.ptr->aready) > 0 &&
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
		arcan_frameserver_free( tgt );
	break;

	case FFUNC_RENDER:
		arcan_event_queuetransfer(
			arcan_event_defaultctx(), &tgt->inqueue, tgt->queue_mask, 0.5, tgt);

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
		if (g_buffers_locked == 1 || tgt->flags.locked || !push_buffer(tgt,
				dst_store, shmpage->hints & SHMIF_RHINT_SUBREGION ? &dirty : NULL)){
			goto no_out;
		}

/* for tighter latency management, here is where the estimated next
 * synch deadline for any output it is used on could/should be set,
 * though it feeds back into the need of the conductor- refactor */
		dst_store->vinf.text.vpts = shmpage->vpts;

/* for some connections, we want additional statistics */
		if (tgt->desc.callback_framestate)
			emit_deliveredframe(tgt, shmpage->vpts, tgt->desc.framecount);
		tgt->desc.framecount++;

/* interactive frameserver blocks on vsemaphore only,
 * so set monitor flags and wake up */
		if (g_buffers_locked != 2){
			atomic_store_explicit(&shmpage->vready, 0, memory_order_release);

			arcan_sem_post( tgt->vsync );
			if (tgt->desc.hints & SHMIF_RHINT_VSIGNAL_EV){
				platform_fsrv_pushevent(tgt, &(struct arcan_event){
					.category = EVENT_TARGET,
					.tgt.kind = TARGET_COMMAND_STEPFRAME,
					.tgt.ioevs[0].iv = 1,
					.tgt.ioevs[1].iv = 0
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
			platform_fsrv_pushevent(src, &ev);
		}

		if (src->flags.autoclock && src->clock.frame)
			autoclock_frame(src);

		arcan_event_queuetransfer(
			arcan_event_defaultctx(), &src->inqueue, src->queue_mask, 0.5, src);
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

	TRAMP_GUARD(FRV_NOFRAME, src);

	if (cmd == FFUNC_DESTROY)
		arcan_frameserver_free(state.ptr);

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

/*
 * if the frameserver isn't ready to receive (semaphore unlocked) then the
 * frame will be dropped, a warning noting that the frameserver isn't fast
 * enough to deal with the data (allowed to duplicate frame to maintain
 * framerate, it can catch up reasonably by using less CPU intensive frame
 * format. Audio will keep on buffering until overflow.
 */
	else if (cmd == FFUNC_READBACK){
		if (src->shm.ptr && !src->shm.ptr->vready){
			memcpy(src->vbufs[0], buf, buf_sz);
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
			arcan_event ev  = {
				.tgt.kind = TARGET_COMMAND_STEPFRAME,
				.category = EVENT_TARGET,
				.tgt.ioevs[0] = src->vfcount++
			};

			src->shm.ptr->vready = true;
			platform_fsrv_pushevent(src, &ev);

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
	return FRV_NOFRAME;
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
	arcan_event deliv = {
		.category = EVENT_FSRV,
		.fsrv.kind = EVENT_FSRV_DELIVEREDFRAME,
		.fsrv.pts = pts,
		.fsrv.counter = framecount,
		.fsrv.otag = src->tag,
		.fsrv.audio = src->aid,
		.fsrv.video = src->vid
	};

	arcan_event_enqueue(arcan_event_defaultctx(), &deliv);
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

	struct arcan_shmif_ramp* hdr = src->desc.aext.gamma;
	if (!hdr || hdr->magic != ARCAN_SHMIF_RAMPMAGIC)
		return false;

/* note, we can't rely on the page block counter as the source isn't trusted to
 * set/manage that information, rely on the requirement that display- index set
 * size is constant */
	size_t lim;
	platform_video_displays(NULL, &lim);

	if (index >= lim)
		return false;

/* only allow ramp-retrieval once and only for one that is marked dirty */
	if (!(hdr->dirty_out & (1 << index)))
		return false;

/* we always ignore EDID, that one is read/only */
	struct ramp_block block;
	memcpy(&block, &hdr->ramps[index * 2], sizeof(struct ramp_block));

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

	atomic_fetch_and(&hdr->dirty_out, ~(1<<index));
	return true;
}

/*
 * Used to update a specific client's perception of a specific ramp,
 * the index must be < (ramp_limit-1) which is a platform defined static
 * upper limit of supported number of displays and ramps.
 */
bool arcan_frameserver_setramps(arcan_frameserver* src,
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
arcan_errc arcan_frameserver_audioframe_direct(arcan_aobj* aobj,
	arcan_aobj_id id, unsigned buffer, bool cont, void* tag)
{
	arcan_frameserver* src = (arcan_frameserver*) tag;

	if (buffer == -1 || src->segid == SEGID_UNKNOWN)
		return ARCAN_ERRC_NOTREADY;

	assert(src->watch_const == 0xfeed);

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
		platform_fsrv_leave(src);
		return ARCAN_ERRC_NOTREADY;
	}

	if (0 == amask || ((1<<ind)&amask) == 0){
		atomic_store_explicit(&src->shm.ptr->aready, 0, memory_order_release);
		platform_fsrv_leave(src);
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

	arcan_audio_buffer(aobj, buffer,
		src->abufs[prev], src->shm.ptr->abufused[prev],
		src->desc.channels, src->desc.samplerate, tag
	);

	atomic_store(&src->shm.ptr->abufused[prev], 0);
	int last = atomic_fetch_and_explicit(&src->shm.ptr->apending,
		~(1 << prev), memory_order_release);

/* check for cont and > 1, wait for signal.. else release */
	if (!cont){
		atomic_store_explicit(&src->shm.ptr->aready, 0, memory_order_release);
		platform_fsrv_leave(src);
		arcan_sem_post(src->async);
	}

	return ARCAN_OK;
}

bool arcan_frameserver_tick_control(
	arcan_frameserver* src, bool tick, int dst_ffunc)
{
	bool fail = true;
	if (!arcan_frameserver_control_chld(src) || !src || !src->shm.ptr ||
		!src->shm.ptr->dms || src->playstate == ARCAN_PAUSED)
		goto leave;

/*
 * Only allow the two categories below, and only let the internal event queue
 * be filled to half in order to not have a crazy frameserver starve the main
 * process.
 */
	arcan_event_queuetransfer(
		arcan_event_defaultctx(), &src->inqueue, src->queue_mask, 0.5, src);

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
				.tgt.ioevs[1].iv = 1
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

	arcan_audio_rebuild(fsrv->aid);

	return ARCAN_OK;
}
