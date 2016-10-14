/*
 * Copyright 2003-2016, Björn Ståhl
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
#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_audio.h"
#include "arcan_audioint.h"

#define FRAMESERVER_PRIVATE
#include "arcan_frameserver.h"

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

static uint64_t cookie;

static inline void emit_deliveredframe(arcan_frameserver* src,
	unsigned long long pts, unsigned long long framecount);
static inline void emit_droppedframe(arcan_frameserver* src,
	unsigned long long pts, unsigned long long framecount);

/*
 * Check if the frameserver is still alive, that the shared memory page
 * is intact and look for any state-changes, e.g. resize (which would
 * require a recalculation of shared memory layout. These are used by the
 * various feedfunctions and should not need to be triggered elsewhere.
 */
static void tick_control(arcan_frameserver*, bool);
bool arcan_frameserver_resize(arcan_frameserver*);

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
		arcan_frameserver_pushevent(tgt, &ev);
	}
	else
		tgt->clock.left -= delta;
}

arcan_errc arcan_frameserver_free(arcan_frameserver* src)
{
	if (!src)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct arcan_shmif_page* shmpage = (struct arcan_shmif_page*)
		src->shm.ptr;

	if (!src->flags.alive)
		return ARCAN_ERRC_UNACCEPTED_STATE;

/* unhook audio monitors */
	arcan_aobj_id* base = src->alocks;
	while (base && *base){
		arcan_audio_hookfeed(*base, NULL, NULL, NULL);
		base++;
	}

	jmp_buf buf;
	if (0 != setjmp(buf))
		goto out;

	arcan_frameserver_enter(src, buf);
/* be nice and say that you'll be dropped off */
	if (shmpage){
		arcan_event exev = {
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_EXIT
		};
		arcan_frameserver_pushevent(src, &exev);

/* and flick any other switch that might keep the child locked */
		shmpage->dms = false;
		shmpage->vready = false;
		shmpage->aready = false;
		arcan_sem_post( src->vsync );
		arcan_sem_post( src->async );
	}
/* if BUS happens during _enter, the handler will take
 * care of dropping shared */
	arcan_frameserver_dropshared(src);
	arcan_frameserver_leave();

out:
	arcan_audio_stop(src->aid);
	arcan_frameserver_killchild(src);

	src->child = BROKEN_PROCESS_HANDLE;
	src->flags.alive = false;

	vfunc_state emptys = {0};
	arcan_mem_free(src->audb);

	if (BADFD != src->dpipe){
		close(src->dpipe);
		src->dpipe = BADFD;
	}

	arcan_video_alterfeed(src->vid, FFUNC_NULL, emptys);

	arcan_event sevent = {
		.category = EVENT_FSRV,
		.fsrv.kind = EVENT_FSRV_TERMINATED,
		.fsrv.video = src->vid,
		.fsrv.glsource = false,
		.fsrv.audio = src->aid,
		.fsrv.otag = src->tag
	};
	arcan_event_enqueue(arcan_event_defaultctx(), &sevent);

/* we don't reset state here for once as the
 * data might be useful in core dumps */
	src->watch_const = 0xdead;
	arcan_mem_free(src);
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

/* won't do anything on windows */
void arcan_frameserver_dropsemaphores_keyed(char* key)
{
	char* work = strdup(key);
		work[ strlen(work) - 1] = 'v';
		arcan_sem_unlink(NULL, work);
		work[strlen(work) - 1] = 'a';
		arcan_sem_unlink(NULL, work);
		work[strlen(work) - 1] = 'e';
		arcan_sem_unlink(NULL, work);
	arcan_mem_free(work);
}

void arcan_frameserver_dropsemaphores(arcan_frameserver* src){
	if (src && src->shm.key && src->shm.ptr){
		arcan_frameserver_dropsemaphores_keyed(src->shm.key);
	}
}

static bool arcan_frameserver_control_chld(arcan_frameserver* src){
/* bunch of terminating conditions -- frameserver messes with the structure to
 * provoke a vulnerability, frameserver dying or timing out, ... */
	bool alive = src->flags.alive && src->shm.ptr
		&& src->shm.ptr->cookie == cookie && arcan_frameserver_validchild(src);

/* subsegment may well be alive when the parent has just died, thus we need to
 * check the state of the parent and if it is dead, clean up just the same,
 * which will likely lead to kill() and a cascade */
	if (alive && src->parent.vid != ARCAN_EID){
		arcan_vobject* vobj = arcan_video_getobject(src->parent.vid);
		if (!vobj || vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
			alive = false;
	}

	if (!alive){
		arcan_event_queuetransfer(arcan_event_defaultctx(), &src->inqueue,
			src->queue_mask, 0.5, src->vid);

		arcan_frameserver_free(src);
		return false;
	}

	return true;
}

arcan_errc arcan_frameserver_pushevent(arcan_frameserver* dst,
	arcan_event* ev)
{
	if (!dst || !ev || !dst->outqueue.back)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	TRAMP_GUARD(ARCAN_ERRC_UNACCEPTED_STATE, dst);

	arcan_errc rv = dst->flags.alive && (dst->shm.ptr && dst->shm.ptr->dms) ?
		arcan_event_enqueue(&dst->outqueue, ev) : ARCAN_ERRC_UNACCEPTED_STATE;

#ifndef MSG_DONTWAIT
#define MSG_DONTWAIT 0
#endif

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

/* this has the effect of a ping message, when we have moved event
 * passing to the socket, the data will be mixed in here */
	arcan_pushhandle(-1, dst->dpipe);
	arcan_frameserver_leave();
	return rv;
}

static void push_buffer(arcan_frameserver* src,
	struct storage_info_t* store, struct arcan_shmif_region* dirty)
{
	struct stream_meta stream = {.buf = NULL};
	bool explicit = src->flags.explicit;

/* we know that vpending contains the latest region that was synched,
 * so the ~vready mask should be the bits that we want to keep. */
	int vready = atomic_load_explicit(&src->shm.ptr->vready,memory_order_consume);
	int vmask=~atomic_load_explicit(&src->shm.ptr->vpending,memory_order_consume);
	vready = (vready <= 0 || vready > src->vbuf_cnt) ? 0 : vready - 1;
	shmif_pixel* buf = src->vbufs[vready];

/* Need to do this check here as-well as in the regular frameserver tick control
 * because the backing store might have changed somehwere else. */
	if (src->desc.width != store->w || src->desc.height != store->h){
		arcan_video_resizefeed(src->vid, src->desc.width, src->desc.height);
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

		arcan_event_enqueue(arcan_event_defaultctx(), &rezev);
		explicit = true;
	}

	if (src->vstream.handle && !src->vstream.dead){
		stream.handle = src->vstream.handle;
		store->vinf.text.stride = src->vstream.stride;
		store->vinf.text.format = src->vstream.format;
		stream = agp_stream_prepare(store, stream, STREAM_HANDLE);

/* buffer passing failed, mark that as an unsupported mode for some reason, log
 * and send back to client to revert to shared memory and extra copies */
		if (!stream.state){
			arcan_event ev = {
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_BUFFER_FAIL
			};
			arcan_event_enqueue(&src->outqueue, &ev);
			src->vstream.dead = true;
		}
		else
			agp_stream_commit(store, stream);

		goto commit_mask;
	}

/* no-alpha flag was rather dumb, should've been done shader-side but now it is
 * kept due to legacy problems that would appear if removed */
	if (src->flags.no_alpha_copy){
		stream = agp_stream_prepare(store, stream, STREAM_RAW);
		if (!stream.buf)
			goto commit_mask;

		av_pixel* wbuf = stream.buf;

		size_t np = store->w * store->h;
		for (size_t i = 0; i < np; i++){
			av_pixel px = *buf++;
			*wbuf++ = RGBA_FULLALPHA_REPACK(px);
		}

		agp_stream_release(store, stream);
	}
	else{
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
	}

	agp_stream_commit(store, stream);
commit_mask:
	atomic_fetch_and(&src->shm.ptr->vpending, vmask);
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

		arcan_event_queuetransfer(arcan_event_defaultctx(),
			&tgt->inqueue, tgt->queue_mask, 0.5, tgt->vid);
	}
	else if (cmd == FFUNC_DESTROY)
		arcan_frameserver_free(tgt);

no_out:
	arcan_frameserver_leave();
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
				tick_control(tgt, false);
				if (tgt->shm.ptr && tgt->shm.ptr->vready){
					arcan_frameserver_leave();
					return FRV_GOTFRAME;
				}
			}

			if (tgt->flags.autoclock && tgt->clock.frame)
				autoclock_frame(tgt);
		break;

		case FFUNC_TICK:
			tick_control(tgt, true);
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

	arcan_frameserver_leave();
	return FRV_NOFRAME;
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
		tick_control(tgt, false);
		goto no_out;
	}

	switch (cmd){
/* silent compiler, this should not happen for a target with a
 * frameserver feeding it */
	case FFUNC_READBACK:
	break;

	case FFUNC_POLL:
		if (shmpage->resized){
			tick_control(tgt, false);
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
		rv = tgt->shm.ptr->vready ? FRV_GOTFRAME : FRV_NOFRAME;
	break;

	case FFUNC_TICK:
		tick_control(tgt, true);
	break;

	case FFUNC_DESTROY:
		arcan_frameserver_free( tgt );
	break;

	case FFUNC_RENDER:
		arcan_event_queuetransfer(arcan_event_defaultctx(),
			&tgt->inqueue, tgt->queue_mask, 0.5, tgt->vid);

		struct arcan_vobject* vobj = arcan_video_getobject(tgt->vid);
		struct storage_info_t* dst_store = vobj->frameset ?
			vobj->frameset->frames[vobj->frameset->index].frame : vobj->vstore;
		struct arcan_shmif_region dirty = atomic_load(&shmpage->dirty);
		push_buffer(tgt, dst_store,
			shmpage->hints & SHMIF_RHINT_SUBREGION ? &dirty : NULL);
		dst_store->vinf.text.vpts = shmpage->vpts;

/* for some connections, we want additional statistics */
		if (tgt->desc.callback_framestate)
			emit_deliveredframe(tgt, shmpage->vpts, tgt->desc.framecount++);

/* interactive frameserver blocks on vsemaphore only,
 * so set monitor flags and wake up */
		atomic_store_explicit(&shmpage->vready, 0, memory_order_release);
		arcan_sem_post( tgt->vsync );

		do_aud = (atomic_load(&tgt->shm.ptr->aready) > 0 &&
			atomic_load(&tgt->shm.ptr->apending) > 0);
	break;

	case FFUNC_ADOPT:
		default_adoph(tgt, srcid);
	break;
  }

no_out:
	arcan_frameserver_leave();

/* we need to defer the fake invocation here to not mess with
 * the signal- guard */
	if (do_aud)
		arcan_aid_refresh(tgt->aid);

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
			arcan_frameserver_leave();
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
			arcan_frameserver_pushevent(src, &ev);
		}

		if (src->flags.autoclock && src->clock.frame)
			autoclock_frame(src);

		arcan_event_queuetransfer(arcan_event_defaultctx(), &src->inqueue,
			src->queue_mask, 0.5, src->vid);
	}

leave:
	arcan_frameserver_leave();
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

		arcan_event_queuetransfer(arcan_event_defaultctx(), &src->inqueue,
			src->queue_mask, 0.5, src->vid);
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
			arcan_frameserver_pushevent(src, &ev);

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
	arcan_frameserver_leave();
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
		arcan_frameserver_leave(src);
		return ARCAN_ERRC_NOTREADY;
	}

	if (0 == amask || ((1<<ind)&amask) == 0){
		atomic_store_explicit(&src->shm.ptr->aready, 0, memory_order_release);
		arcan_frameserver_leave(src);
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
		arcan_frameserver_leave(src);
		arcan_sem_post(src->async);
	}

	return ARCAN_OK;
}

static void tick_control(arcan_frameserver* src, bool tick)
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
	arcan_event_queuetransfer(arcan_event_defaultctx(),
		&src->inqueue, src->queue_mask, 0.5, src->vid);

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
	if (!arcan_frameserver_resize(src))
		goto leave;

	fail = false;

/*
 * at this stage, frameserver impl. should have remapped event queues,
 * vbuf/abufs, and signaled the connected process. Make sure we are running the
 * right feed function (may have been turned into another or started in a
 * passive one
 */
	vfunc_state cstate = *arcan_video_feedstate(src->vid);
	arcan_video_alterfeed(src->vid, FFUNC_VFRAME, cstate);

leave:
/* want the event to be queued after resize so the possible reaction (i.e.
 * redraw + synch) aligns with pending resize */
	if (!fail && tick){
		if (0 >= --src->clock.left){
			arcan_event ev = {
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_STEPFRAME,
				.tgt.ioevs[0].iv = 1,
				.tgt.ioevs[1].iv = 1
			};

			src->clock.left = src->clock.start;
			arcan_frameserver_pushevent(src, &ev);
		}
	}
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

arcan_frameserver* arcan_frameserver_alloc()
{
	arcan_frameserver* res = arcan_alloc_mem(sizeof(arcan_frameserver),
		ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	if (!cookie)
		cookie = arcan_shmif_cookie();

	res->watch_const = 0xfeed;

	res->dpipe = BADFD;

	res->playstate = ARCAN_PLAYING;
	res->flags.alive = true;
	res->flags.autoclock = true;
	res->parent.vid = ARCAN_EID;
	res->desc.samplerate = ARCAN_SHMIF_SAMPLERATE;

/* these are statically defined right now, but we may want to make them
 * configurable in the future to possibly utilize other accelerated resampling
 * etc. */
	res->desc.channels = ARCAN_SHMIF_ACHANNELS;

/* not used for any serious identification purpose,
 * just to prevent / help detect developer errors */
	res->cookie = (uint32_t) random();

/* shm- related settings are deferred as this is called previous to mapping
 * (spawn_subsegment / spawn_server) so setting up the eventqueues with
 * killswitches have to be done elsewhere
 */

	return res;
}

void arcan_frameserver_configure(arcan_frameserver* ctx,
	struct frameserver_envp setup)
{
	arcan_errc errc;
	if (!ctx)
		return;

	if (setup.use_builtin){
/* "game" (or rather, interactive mode) treats a single pair of
 * videoframe+audiobuffer each transfer, minimising latency is key. */
		if (strcmp(setup.args.builtin.mode, "game") == 0){
			ctx->aid = arcan_audio_feed((arcan_afunc_cb)
				arcan_frameserver_audioframe_direct, ctx, &errc);

			ctx->segid = SEGID_GAME;
			ctx->sz_audb  = 0;
			ctx->ofs_audb = 0;
			ctx->segid = SEGID_GAME;
			ctx->audb = NULL;
			ctx->queue_mask = EVENT_EXTERNAL;
		}

/* network client needs less in terms of buffering etc. but instead a
 * different signalling mechanism for flushing events */
		else if (strcmp(setup.args.builtin.mode, "net-cl") == 0){
			ctx->segid = SEGID_NETWORK_CLIENT;
			ctx->queue_mask = EVENT_EXTERNAL | EVENT_NET;
		}
		else if (strcmp(setup.args.builtin.mode, "net-srv") == 0){
			ctx->segid = SEGID_NETWORK_SERVER;
			ctx->queue_mask = EVENT_EXTERNAL | EVENT_NET;
		}

/* record instead operates by maintaining up-to-date local buffers,
 * then letting the frameserver sample whenever necessary */
		else if (strcmp(setup.args.builtin.mode, "encode") == 0){
			ctx->segid = SEGID_ENCODER;
/* we don't know how many audio feeds are actually monitored to produce the
 * output, thus not how large the intermediate buffer should be to
 * safely accommodate them all */
			ctx->sz_audb = 65535;
			ctx->audb = arcan_alloc_mem(ctx->sz_audb,
				ARCAN_MEM_ABUFFER, 0, ARCAN_MEMALIGN_PAGE);
			ctx->queue_mask = EVENT_EXTERNAL;
		}
		else if (strcmp(setup.args.builtin.mode, "terminal") == 0){
			ctx->segid = SEGID_TERMINAL;
			goto defcfg;
		}
		else{
defcfg:
			ctx->segid = SEGID_UNKNOWN;
			ctx->aid = arcan_audio_feed(
			(arcan_afunc_cb) arcan_frameserver_audioframe_direct, ctx, &errc);
			ctx->sz_audb  = 0;
			ctx->ofs_audb = 0;
			ctx->audb = NULL;
			ctx->queue_mask = EVENT_EXTERNAL;
		}
	}
/* hijack works as a 'process parasite' inside the rendering pipeline of other
 * projects, either through a generic fallback library or for specialized "per-
 * target" (in order to minimize size and handle 32/64 switching
 * parent-vs-child relations */
	else{
		ctx->aid = arcan_audio_feed((arcan_afunc_cb)
			arcan_frameserver_audioframe_direct, ctx, &errc);
		ctx->segid = SEGID_UNKNOWN;
		ctx->queue_mask = EVENT_EXTERNAL;

/* local-side buffering only used for recording/mixing now */
		ctx->sz_audb = 0;
		ctx->ofs_audb = 0;
		ctx->audb = NULL;
	}

/* two separate queues for passing events back and forth between main program
 * and frameserver, set the buffer pointers to the relevant offsets in
 * backend_shmpage */
	arcan_shmif_setevqs(ctx->shm.ptr,
		ctx->esync, &(ctx->inqueue), &(ctx->outqueue), true);
	ctx->inqueue.synch.killswitch = (void*) ctx;
	ctx->outqueue.synch.killswitch = (void*) ctx;

	struct arcan_shmif_page* shmpage = ctx->shm.ptr;
	shmpage->w = setup.init_w;
	shmpage->h = setup.init_h;

	ctx->vbuf_cnt = ctx->abuf_cnt = 1;
	arcan_shmif_mapav(shmpage,
		ctx->vbufs, ctx->vbuf_cnt, setup.init_w*setup.init_h*sizeof(shmif_pixel),
		ctx->abufs, ctx->abuf_cnt, 65536
	);

	if (ctx->segid != SEGID_UNKNOWN){
		arcan_event_enqueue(arcan_event_defaultctx(), &(arcan_event){
			.category = EVENT_FSRV,
			.fsrv.kind = EVENT_FSRV_PREROLL,
		});
	}
}
