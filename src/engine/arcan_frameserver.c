/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>
#include <assert.h>
#include <limits.h>

#ifndef _WIN32
#include <sys/types.h>
#include <sys/socket.h>
#endif

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_shmif.h"
#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_audio.h"
#include "arcan_audioint.h"
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

arcan_errc arcan_frameserver_free(arcan_frameserver* src)
{
	if (!src)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct arcan_shmif_page* shmpage = (struct arcan_shmif_page*)
		src->shm.ptr;

	if (!src->flags.alive)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	if (shmpage){
		if (arcan_frameserver_enter(src)){
			arcan_event exev = {
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_EXIT
			};
			arcan_frameserver_pushevent(src, &exev);

			shmpage->dms = false;
			shmpage->vready = false;
			shmpage->aready = false;
			arcan_sem_post( src->vsync );
			arcan_sem_post( src->async );
		}

		arcan_frameserver_dropshared(src);
		src->shm.ptr = NULL;

		arcan_frameserver_leave();
	}

	arcan_frameserver_killchild(src);

	src->child = BROKEN_PROCESS_HANDLE;
	src->flags.alive = false;

/* unhook audio monitors */
	arcan_aobj_id* base = src->alocks;
	while (base && *base){
		arcan_audio_hookfeed(*base, NULL, NULL, NULL);
		base++;
	}

	vfunc_state emptys = {0};
	arcan_audio_stop(src->aid);
	arcan_mem_free(src->audb);

	if (BADFD != src->dpipe){
		close(src->dpipe);
		src->dpipe = BADFD;
	}

	arcan_video_alterfeed(src->vid, NULL, emptys);

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

bool arcan_frameserver_control_chld(arcan_frameserver* src){
/* bunch of terminating conditions -- frameserver messes
 * with the structure to provoke a vulnerability, frameserver
 * dying or timing out, ... */
	if ( src->flags.alive && src->shm.ptr &&
		src->shm.ptr->cookie == cookie &&
		arcan_frameserver_validchild(src) == false){

/* force flush beforehand, in a saturated queue, data may still
 * get lost here */
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
	if (!dst || !ev)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!arcan_frameserver_enter(dst))
		return ARCAN_ERRC_UNACCEPTED_STATE;

/*
 * printf("-> target(%d):%s\n", (int)dst->vid,
		arcan_shmif_eventstr(ev, NULL, 0));
 */

	arcan_errc rv = dst->flags.alive && (dst->shm.ptr && dst->shm.ptr->dms) ?
		(arcan_event_enqueue(&dst->outqueue, ev), ARCAN_OK) :
		ARCAN_ERRC_UNACCEPTED_STATE;
#ifndef _WIN32

#ifndef MSG_DONTWAIT
#define MSG_DONTWAIT 0
#endif

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

/* this has the effect of a ping message, when we have moved event
 * passing to the socket, the data will be mixed in here */
	arcan_pushhandle(-1, dst->dpipe);
#endif

	arcan_frameserver_leave();
	return rv;
}

static void push_buffer(arcan_frameserver* src,
	av_pixel* buf, struct storage_info_t* store)
{
	struct stream_meta stream = {.buf = NULL};

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
			.fsrv.glsource = src->shm.ptr->glsource
		};

		arcan_event_enqueue(arcan_event_defaultctx(), &rezev);
	}

/*
 * currently many situations not handled;
 * parent- allocated explicit buffers
 * parent- rejecting accelerated buffers (incompatible formats),
 * activating shmif fallback
 *  - wasted shmif space on vidp that won't be used
 */
	if (src->vstream.handle && !src->vstream.dead){
		stream.handle = src->vstream.handle;
		store->vinf.text.stride = src->vstream.stride;
		store->vinf.text.format = src->vstream.format;
		stream = agp_stream_prepare(store, stream, STREAM_HANDLE);

/* buffer passing failed, mark that as an unsupported mode for
 * some reason, log and send back to client to revert to shared
 * memory and extra copies */
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

		return;
	}

/* no-alpha flag was rather dumb, should've been done shader-wise */
	if (src->flags.no_alpha_copy){
		stream = agp_stream_prepare(store, stream, STREAM_RAW);
		if (!stream.buf)
			return;

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
		stream = agp_stream_prepare(store, stream, src->flags.explicit ?
			STREAM_RAW_DIRECT_SYNCHRONOUS : (
				src->flags.local_copy ? STREAM_RAW_DIRECT_COPY : STREAM_RAW_DIRECT));
	}

	agp_stream_commit(store, stream);
}

enum arcan_ffunc_rv arcan_frameserver_dummyframe(
	enum arcan_ffunc_cmd cmd, uint8_t* buf,
	uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp,
	unsigned mode, vfunc_state state)
{
    if (state.tag == ARCAN_TAG_FRAMESERV && state.ptr && cmd == FFUNC_DESTROY)
        arcan_frameserver_free( (arcan_frameserver*) state.ptr);

    return FFUNC_RV_NOFRAME;
}

enum arcan_ffunc_rv arcan_frameserver_emptyframe(
	enum arcan_ffunc_cmd cmd, av_pixel* buf,
	size_t s_buf, uint16_t width, uint16_t height,
	unsigned mode, vfunc_state state)
{
	arcan_frameserver* tgt = state.ptr;
	if (!tgt || state.tag != ARCAN_TAG_FRAMESERV
	 || !arcan_frameserver_enter(tgt))
		return FFUNC_RV_NOFRAME;

	switch (cmd){
		case FFUNC_POLL:
			if (tgt->shm.ptr->resized){
				arcan_frameserver_tick_control(tgt);
        if (tgt->shm.ptr && tgt->shm.ptr->vready){
					arcan_frameserver_leave();
        	return FFUNC_RV_GOTFRAME;
				}
			}

		case FFUNC_TICK:
			arcan_frameserver_tick_control(tgt);
		break;

		case FFUNC_DESTROY:
			arcan_frameserver_free(tgt);
		break;

		default:
			break;
	}

	arcan_frameserver_leave();
	return FFUNC_RV_NOFRAME;
}

static void check_audb(arcan_frameserver* tgt, struct arcan_shmif_page* shmpage)
{
/* interleave audio / video processing */
	if (!(shmpage->aready && shmpage->abufused))
		return;

	size_t ntc = tgt->ofs_audb + shmpage->abufused > tgt->sz_audb ?
		(tgt->sz_audb - tgt->ofs_audb) : shmpage->abufused;

	if (ntc == 0){
		static bool overflow;
		if (!overflow){
			arcan_warning("frameserver_videoframe_direct(), incoming buffer "
				"overflow for: %d, resetting.\n", tgt->vid);
			overflow = true;
		}
		tgt->ofs_audb = 0;
	}

	memcpy(&tgt->audb[tgt->ofs_audb], tgt->audp, ntc);
	tgt->ofs_audb += ntc;
	shmpage->abufused = 0;
	shmpage->aready = false;
	arcan_sem_post( tgt->async );
}

enum arcan_ffunc_rv arcan_frameserver_videoframe_direct(
	enum arcan_ffunc_cmd cmd, av_pixel* buf, size_t s_buf,
	uint16_t width, uint16_t height,
	unsigned int mode, vfunc_state state)
{
	int8_t rv = 0;
	if (state.tag != ARCAN_TAG_FRAMESERV || !state.ptr)
		return rv;

	arcan_frameserver* tgt = state.ptr;
	struct arcan_shmif_page* shmpage = tgt->shm.ptr;

	if (!shmpage || !arcan_frameserver_enter(tgt))
		return FFUNC_RV_NOFRAME;

	switch (cmd){
/* silent compiler, this should not happen for a target with a
 * frameserver feeding it */
	case FFUNC_READBACK:
	break;

	case FFUNC_POLL:
		if (shmpage->resized){
			arcan_frameserver_tick_control(tgt);
			shmpage = tgt->shm.ptr;
		}

/* use this opportunity to make sure that we treat audio as well */
		check_audb(tgt, shmpage);

/* caller uses this hint to determine if a transfer should be
 * initiated or not */
		rv = (tgt->playstate == ARCAN_PLAYING && shmpage->vready) ?
			FFUNC_RV_GOTFRAME : FFUNC_RV_NOFRAME;
	break;

	case FFUNC_TICK:
		arcan_frameserver_tick_control( tgt );
	break;

	case FFUNC_DESTROY:
		arcan_frameserver_free( tgt );
	break;

	case FFUNC_RENDER:
		arcan_event_queuetransfer(arcan_event_defaultctx(),
			&tgt->inqueue, tgt->queue_mask, 0.5, tgt->vid);

		struct arcan_vobject* vobj = arcan_video_getobject(tgt->vid);
		struct storage_info_t* dst_store = vobj->frameset ?
			vobj->frameset->frames[vobj->frameset->index] : vobj->vstore;
		push_buffer(tgt, tgt->vidp, dst_store);

/* for some connections, we want additional statistics */
		if (tgt->desc.callback_framestate)
			emit_deliveredframe(tgt, shmpage->vpts, tgt->desc.framecount++);

		check_audb(tgt, shmpage);

/* interactive frameserver blocks on vsemaphore only,
 * so set monitor flags and wake up */
		shmpage->vready = false;
		arcan_sem_post( tgt->vsync );

		break;
  }

	arcan_frameserver_leave();
	return rv;
}

/*
 * a little bit special, the vstore is already assumed to
 * contain the state that we want to forward, and there's
 * no audio mixing or similar going on, so just copy.
 */
enum arcan_ffunc_rv arcan_frameserver_feedcopy(
	enum arcan_ffunc_cmd cmd, av_pixel* buf,
	size_t s_buf, uint16_t width, uint16_t height,
	unsigned mode, vfunc_state state)
{
	assert(state.ptr);
	assert(state.tag == ARCAN_TAG_FRAMESERV);
	arcan_frameserver* src = (arcan_frameserver*) state.ptr;

	if (!arcan_frameserver_enter(src))
		return FFUNC_RV_NOFRAME;

	if (cmd == FFUNC_DESTROY)
		arcan_frameserver_free(state.ptr);

	else if (cmd == FFUNC_POLL){
/* done differently since we don't care if the frameserver
 * wants to resize segments used for recording */
		if (!arcan_frameserver_control_chld(src)){
			arcan_frameserver_leave();
   		return FFUNC_RV_NOFRAME;
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

			memcpy(src->vidp,
				me->vstore->vinf.text.raw, me->vstore->vinf.text.s_raw);

			src->shm.ptr->vready = true;
			arcan_frameserver_pushevent(src, &ev);
		}

		arcan_event_queuetransfer(arcan_event_defaultctx(), &src->inqueue,
			src->queue_mask, 0.5, src->vid);
	}

leave:
	arcan_frameserver_leave();
	return FFUNC_RV_NOFRAME;
}

enum arcan_ffunc_rv arcan_frameserver_avfeedframe(
	enum arcan_ffunc_cmd cmd, av_pixel* buf,
	size_t s_buf, uint16_t width, uint16_t height,
	unsigned mode, vfunc_state state)
{
	assert(state.ptr);
	assert(state.tag == ARCAN_TAG_FRAMESERV);
	arcan_frameserver* src = (arcan_frameserver*) state.ptr;

	if (!arcan_frameserver_enter(src))
		return FFUNC_RV_NOFRAME;

	if (cmd == FFUNC_DESTROY)
		arcan_frameserver_free(state.ptr);

	else if (cmd == FFUNC_TICK){
/* done differently since we don't care if the frameserver
 * wants to resize segments used for recording */
		if (!arcan_frameserver_control_chld(src)){
			arcan_frameserver_leave();
   		return FFUNC_RV_NOFRAME;
		}

		arcan_event_queuetransfer(arcan_event_defaultctx(), &src->inqueue,
			src->queue_mask, 0.5, src->vid);
	}

/*
 * if the frameserver isn't ready to receive (semaphore unlocked)
 * then the frame will be dropped, a warning noting that the
 * frameserver isn't fast enough to deal with the data (allowed to
 * duplicate frame to maintain framerate,
 * it can catch up reasonably by using less CPU intensive frame format.
 * Audio will keep on buffering until overflow,
 */
	else if (cmd == FFUNC_READBACK){
		if (!src->shm.ptr->vready){
			memcpy(src->vidp, buf, s_buf);
			if (src->ofs_audb){
					memcpy(src->audp, src->audb, src->ofs_audb);
					src->shm.ptr->abufused = src->ofs_audb;
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

	arcan_frameserver_leave();
	return 0;
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

arcan_errc arcan_frameserver_audioframe_direct(arcan_aobj* aobj,
	arcan_aobj_id id, unsigned buffer, void* tag)
{
	arcan_errc rv = ARCAN_ERRC_NOTREADY;
	arcan_frameserver* src = (arcan_frameserver*) tag;

	if (buffer != -1 && src->audb && src->ofs_audb > ARCAN_ASTREAMBUF_LLIMIT){
/* this function will make sure all monitors etc. gets their chance */
			arcan_audio_buffer(aobj, buffer, src->audb, src->ofs_audb,
				src->desc.channels, src->desc.samplerate, tag);

		src->ofs_audb = 0;

		rv = ARCAN_OK;
	}

	return rv;
}

void arcan_frameserver_tick_control(arcan_frameserver* src)
{
	if (!arcan_frameserver_control_chld(src) ||
		!src || !src->shm.ptr || !src->shm.ptr->dms)
		goto leave;

/*
 * Only allow the two categories below, and only let the internal event
 * queue be filled to half in order to not have a crazy frameserver starve
 * the main process.
 */
	arcan_event_queuetransfer(arcan_event_defaultctx(), &src->inqueue,
		src->queue_mask, 0.5, src->vid);

	if (!src->shm.ptr->resized)
		goto leave;

	FORCE_SYNCH();
	size_t neww = src->shm.ptr->w;
	size_t newh = src->shm.ptr->h;

	if (src->desc.width == neww && src->desc.height == newh){
		arcan_warning("frameserver_tick_control(), source requested "
			"resize to current dimensions.\n");
		goto leave;
	}

	if (!arcan_frameserver_resize(src, neww, newh)){
 		arcan_warning("client requested illegal resize (%d, %d) -- killing.\n",
			neww, newh);
		arcan_frameserver_free(src);
		goto leave;
	}

/*
 * evqueues contain pointers into the shmpage that may have been moved
 */
	arcan_shmif_setevqs(src->shm.ptr, src->esync,
		&(src->inqueue), &(src->outqueue), true);

	struct arcan_shmif_page* shmpage = src->shm.ptr;
	/*
 * this is a rather costly operation that we want to rate-control or
 * at least monitor as multiple resizes in a short amount of time
 * is indicative of something foul going on.
 */
	vfunc_state cstate = *arcan_video_feedstate(src->vid);

/* resize the source vid in a way that won't propagate to user scripts
 * as we want the resize event to be forwarded to the regular callback */
	arcan_event_maskall(arcan_event_defaultctx());
	src->desc.samplerate = ARCAN_SHMPAGE_SAMPLERATE;
	src->desc.channels = ARCAN_SHMPAGE_ACHANNELS;

/*
 * though the frameserver backing is resized, the actual
 * resize event won't propagate until the frameserver has provided
 * data (push buffer)
 */
	arcan_event_clearmask(arcan_event_defaultctx());
	arcan_shmif_calcofs(shmpage, &(src->vidp), &(src->audp));

	arcan_video_alterfeed(src->vid, arcan_frameserver_videoframe_direct, cstate);

/* acknowledge the resize */
	shmpage->resized = false;

leave:
	arcan_frameserver_leave();
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
	res->parent = ARCAN_EID;

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

	if (setup.use_builtin){
/* "libretro" (or rather, interactive mode) treats a single pair of
 * videoframe+audiobuffer each transfer, minimising latency is key. */
		if (strcmp(setup.args.builtin.mode, "libretro") == 0){
			ctx->aid = arcan_audio_feed((arcan_afunc_cb)
				arcan_frameserver_audioframe_direct, ctx, &errc);

			ctx->segid    = SEGID_GAME;
			ctx->sz_audb  = 1024 * 64;
			ctx->ofs_audb = 0;
			ctx->segid = SEGID_GAME;
			ctx->audb     = arcan_alloc_mem(ctx->sz_audb,
				ARCAN_MEM_ABUFFER, 0, ARCAN_MEMALIGN_PAGE);
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
		else if (strcmp(setup.args.builtin.mode, "record") == 0){
			ctx->segid = SEGID_ENCODER;

/* we don't know how many audio feeds are actually monitored to produce the
 * output, thus not how large the intermediate buffer should be to
 * safely accommodate them all */
			ctx->sz_audb = ARCAN_SHMPAGE_AUDIOBUF_SZ;
			ctx->audb = arcan_alloc_mem(ctx->sz_audb,
				ARCAN_MEM_ABUFFER, 0, ARCAN_MEMALIGN_PAGE);
			ctx->queue_mask = EVENT_EXTERNAL;
		}
		else {
			ctx->segid = SEGID_MEDIA;
			ctx->aid = arcan_audio_feed(
			(arcan_afunc_cb) arcan_frameserver_audioframe_direct, ctx, &errc);
			ctx->sz_audb  = 1024 * 64;
			ctx->ofs_audb = 0;
			ctx->audb = arcan_alloc_mem(ctx->sz_audb,
				ARCAN_MEM_ABUFFER, 0, ARCAN_MEMALIGN_PAGE);
			ctx->queue_mask = EVENT_EXTERNAL;
		}
	}
/* hijack works as a 'process parasite' inside the rendering pipeline of
 * other projects, either through a generic fallback library or for
 * specialized "per- target" (in order to minimize size and handle 32/64
 * switching parent-vs-child relations */
	else{
		ctx->aid = arcan_audio_feed((arcan_afunc_cb)
			arcan_frameserver_audioframe_direct, ctx, &errc);
		ctx->segid = SEGID_UNKNOWN;
		ctx->queue_mask = EVENT_EXTERNAL;

/* although audio playback tend to be kept in the child process, the
 * sampledata may still be needed for recording/monitoring */
		ctx->sz_audb  = 1024 * 64;
		ctx->ofs_audb = 0;
		ctx->audb = arcan_alloc_mem(ctx->sz_audb,
				ARCAN_MEM_ABUFFER, 0, ARCAN_MEMALIGN_PAGE);
	}

/* two separate queues for passing events back and forth between main program
 * and frameserver, set the buffer pointers to the relevant offsets in
 * backend_shmpage, and semaphores from the sem_open calls -- plan is
 * to switch this behavior on some platforms to instead use sockets to
 * improve I/O multiplexing (network- frameservers) or at least have futex
 * triggers on Linux */
	arcan_shmif_setevqs(ctx->shm.ptr, ctx->esync,
		&(ctx->inqueue), &(ctx->outqueue), true);
	ctx->inqueue.synch.killswitch = (void*) ctx;
	ctx->outqueue.synch.killswitch = (void*) ctx;

	struct arcan_shmif_page* shmpage = ctx->shm.ptr;
	shmpage->w = setup.init_w;
	shmpage->h = setup.init_h;

	arcan_shmif_calcofs(shmpage, &(ctx->vidp), &(ctx->audp));
}
