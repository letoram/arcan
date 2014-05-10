/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
 *
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
#include <pthread.h>

#ifndef _WIN32
#include <sys/types.h>
#include <sys/socket.h>
#endif

#include GL_HEADERS

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_audio.h"
#include "arcan_audioint.h"
#include "arcan_frameserver_backend.h"
#include "arcan_shmif.h"
#include "arcan_event.h"

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

	if (!shmpage || !src->child_alive)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	shmpage->dms = false;
	shmpage->vready = false;
	shmpage->aready = false;
	arcan_sem_post( src->vsync );
	arcan_sem_post( src->async );

	arcan_event exev = {
		.category = EVENT_TARGET,
		.kind = TARGET_COMMAND_EXIT
	};

	arcan_frameserver_pushevent(src, &exev);
	arcan_frameserver_killchild(src);
 
	src->child = BROKEN_PROCESS_HANDLE;
	src->child_alive = false;

	arcan_frameserver_dropshared(src);
	src->shm.ptr = NULL;

/* unhook audio monitors */
	arcan_aobj_id* base = src->alocks;
	while (base && *base){
		arcan_audio_hookfeed(*base, NULL, NULL, NULL);
		base++;
	}

	arcan_mem_free(src->audb);
	pthread_mutex_destroy(&src->lock_audb);

#ifndef _WIN32
	close(src->sockout_fd);
#endif

	vfunc_state emptys = {0};
	arcan_audio_stop(src->aid);
	arcan_video_alterfeed(src->vid, NULL, emptys);
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
	if ( src->child_alive && 
		(arcan_shmif_integrity_check(src->shm.ptr) == false ||
		arcan_frameserver_validchild(src) == false)){

		arcan_event sevent = {.category = EVENT_FRAMESERVER,
		.kind = EVENT_FRAMESERVER_TERMINATED,
		.data.frameserver.video = src->vid,
		.data.frameserver.glsource = false,
		.data.frameserver.audio = src->aid,
		.data.frameserver.otag = src->tag
		};
		
/* force flush beforehand, in a saturated queue, data may still
 * get lost here */
		arcan_event_queuetransfer(arcan_event_defaultctx(), &src->inqueue, 
			src->queue_mask, 0.5, src->vid);
		arcan_event_enqueue(arcan_event_defaultctx(), &sevent);
		return false;
	}

	return true;
}

arcan_errc arcan_frameserver_pushevent(arcan_frameserver* dst, 
	arcan_event* ev){
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

/* 
 * NOTE: when arcan_event_serialize(*buffer) is implemented,
 * the queue should be stripped from the shmpage entirely and only 
 * transferred over the socket(!) 
 * The problem with the current approach is that we have no
 * decent mechanism active for waking a child that's simultaneously
 * polling and need to respond quickly to enqueued events,
 */
	if (dst && ev){
		rv = dst->child_alive ?
			(arcan_event_enqueue(&dst->outqueue, ev), ARCAN_OK) :
			ARCAN_ERRC_UNACCEPTED_STATE;

#ifndef _WIN32

#ifndef MSG_DONTWAIT
#define MSG_DONTWAIT 0
#endif

		if (dst->socksig){
			int sn = 0;
			send(dst->sockout_fd, &sn, sizeof(int), MSG_DONTWAIT);
		}
#endif
	}
	return rv;
}

static int push_buffer(arcan_frameserver* src, char* buf, unsigned int glid,
	unsigned sw, unsigned sh, unsigned bpp,
	unsigned dw, unsigned dh, unsigned dpp)
{
	int8_t rv;
	FLAG_DIRTY();

	if (sw != dw ||
		sh != dh) {
		uint16_t cpy_width  = (dw > sw ? sw : dw);
		uint16_t cpy_height = (dh > sh ? sh : dh);
		assert(bpp == dpp);

		for (uint16_t row = 0; row < cpy_height && row < cpy_height; row++)
			memcpy(buf + (row * sw * bpp), buf, cpy_width * bpp);

		rv = FFUNC_RV_COPIED;
		return rv;
	}

	glBindTexture(GL_TEXTURE_2D, glid);

/* flip-floping PBOs, simply using one risks the chance of turning a PBO 
 * operation synchronous, eliminating much of the point in using them
 * in the first place. Note that with PBOs running, we currently have
 * one frame delay in that the buffer won't be activate until the next 
 * frame is about to be queued. This works fine on a streaming source
 * but not in other places unfortunately */
	if (src->desc.pbo_transfer){
#ifdef VIDEO_PBO_FLIPFLOP
		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 
			src->desc.upload_pbo[src->desc.pbo_index]);

		glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, sw, sh, 
			GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, 0);

		src->desc.pbo_index = 1 - src->desc.pbo_index;

		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 
			src->desc.upload_pbo[src->desc.pbo_index]);
		void* ptr = glMapBuffer(GL_PIXEL_UNPACK_BUFFER, GL_WRITE_ONLY);

		if (ptr)
			memcpy(ptr, buf, sw * sh * bpp);

		glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER);
		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
#else
		glBindBuffer(GL_PIXEL_UNPACK_BUFFER,
			src->desc.upload_pbo[0]);
		void* ptr = glMapBuffer(GL_PIXEL_UNPACK_BUFFER, GL_WRITE_ONLY);
		if (ptr)
			memcpy(ptr, buf, sw * sh * bpp);
		glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER);
		glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, sw, sh, 
			GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, 0);
		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
#endif
	}
	else
		glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, sw, sh,
			GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, buf);

	glBindTexture(GL_TEXTURE_2D, 0);

	return FFUNC_RV_NOUPLOAD;
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
	enum arcan_ffunc_cmd cmd, uint8_t* buf, 
	uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, 
	unsigned mode, vfunc_state state)
{
	arcan_frameserver* tgt = state.ptr;
	struct arcan_shmif_page* shmpage;
	
	if (state.tag == ARCAN_TAG_FRAMESERV && state.ptr)
	switch (cmd){
		case FFUNC_POLL:
  		shmpage = tgt->shm.ptr;
			if (shmpage->resized) 
				arcan_frameserver_tick_control(tgt);
			return shmpage->vready;	

		case FFUNC_TICK:
			arcan_frameserver_tick_control(tgt); 
		break;

		case FFUNC_DESTROY:
			arcan_frameserver_free(tgt);
		break;

		default:
			break;
	}

	return FFUNC_RV_NOFRAME;
}

enum arcan_ffunc_rv arcan_frameserver_videoframe_direct(
	enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, 
	uint16_t width, uint16_t height, uint8_t bpp, 
	unsigned int mode, vfunc_state state)
{
	int8_t rv = 0;
	if (state.tag != ARCAN_TAG_FRAMESERV || !state.ptr)
		return rv;

	arcan_frameserver* tgt = state.ptr;
	struct arcan_shmif_page* shmpage = tgt->shm.ptr;

	switch (cmd){
	case FFUNC_READBACK: 
	break;

	case FFUNC_POLL:
		if (shmpage->resized)
			arcan_frameserver_tick_control(tgt);

		return tgt->playstate == ARCAN_PLAYING && shmpage->vready 
				&& (tgt->ofs_audb < 2 * ARCAN_ASTREAMBUF_LLIMIT);
	break;

	case FFUNC_TICK: 
		arcan_frameserver_tick_control( tgt ); 
	break;

	case FFUNC_DESTROY: arcan_frameserver_free( tgt ); break;

	case FFUNC_RENDER:
		arcan_event_queuetransfer(arcan_event_defaultctx(), &tgt->inqueue, 
			tgt->queue_mask, 0.5, tgt->vid);
	
		rv = push_buffer( tgt, (char*) tgt->vidp, mode, 
			tgt->desc.width, tgt->desc.height, GL_PIXEL_BPP, width, height, GL_PIXEL_BPP);

		if (tgt->desc.callback_framestate)
			emit_deliveredframe(tgt, shmpage->vpts, tgt->desc.framecount++);
	
		if (tgt->kind == ARCAN_FRAMESERVER_INTERACTIVE && shmpage->abufused > 0){
			pthread_mutex_lock(&tgt->lock_audb);

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
			pthread_mutex_unlock(&tgt->lock_audb);
		}

/* interactive frameserver blocks on vsemaphore only, 
 * so set monitor flags and wake up */
		shmpage->vready = false;
		arcan_sem_post( tgt->vsync );

		break;
  }

	return rv;
}

enum arcan_ffunc_rv arcan_frameserver_avfeedframe(
	enum arcan_ffunc_cmd cmd, uint8_t* buf, 
	uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, 
	unsigned mode, vfunc_state state)
{
	assert(state.ptr);
	assert(state.tag == ARCAN_TAG_FRAMESERV);
	arcan_frameserver* src = (arcan_frameserver*) state.ptr;

	if (cmd == FFUNC_DESTROY)
		arcan_frameserver_free(state.ptr);

	else if (cmd == FFUNC_TICK){
/* done differently since we don't care if the frameserver wants 
 * to resize, that's its problem. */
		if (!arcan_frameserver_control_chld(src)){
 			vfunc_state cstate = *arcan_video_feedstate(src->vid);
			arcan_video_alterfeed(src->vid,
				arcan_frameserver_dummyframe, cstate);
  		return FFUNC_RV_NOFRAME;
    }
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
		if ( (src->desc.explicit_xfer && arcan_sem_wait(src->vsync) == 0) ||
			(!src->desc.explicit_xfer && arcan_sem_trywait(src->vsync) == 0)){
			memcpy(src->vidp, buf, s_buf);
			if (src->ofs_audb){
				pthread_mutex_lock(&src->lock_audb);
					memcpy(src->audp, src->audb, src->ofs_audb);
					src->shm.ptr->abufused = src->ofs_audb;
					src->ofs_audb = 0;
				pthread_mutex_unlock(&src->lock_audb);
			}

/* it is possible that we deliver more videoframes than we can legitimately 
 * encode in the target framerate, it is up to the frameserver 
 * to determine when to drop and when to double frames */
			arcan_event ev  = {
				.kind = TARGET_COMMAND_STEPFRAME,
				.category = EVENT_TARGET,
				.data.target.ioevs[0] = src->vfcount++
			};

			arcan_event_enqueue(&src->outqueue, &ev);

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

/* not really used */
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
	pthread_mutex_lock(&dst->lock_audb);
	if (dst->amixer.n_aids > 0){
		feed_amixer(dst, src, (int16_t*) buf, buf_sz >> 1);
	} 
	else if (dst->ofs_audb + buf_sz < dst->sz_audb){
			memcpy(dst->audb + dst->ofs_audb, buf, buf_sz);
			dst->ofs_audb += buf_sz;
	}
	else;
	pthread_mutex_unlock(&dst->lock_audb);
}

static inline void emit_deliveredframe(arcan_frameserver* src, 
	unsigned long long pts, unsigned long long framecount)
{
	arcan_event deliv = {
		.category = EVENT_FRAMESERVER,
		.kind = EVENT_FRAMESERVER_DELIVEREDFRAME,
		.data.frameserver.pts = pts,
		.data.frameserver.counter = framecount,
		.data.frameserver.otag = src->tag,
		.data.frameserver.video = src->vid
	};

	arcan_event_enqueue(arcan_event_defaultctx(), &deliv);
}

static inline void emit_droppedframe(arcan_frameserver* src,
	unsigned long long pts, unsigned long long dropcount)
{
	arcan_event deliv = {
		.category = EVENT_FRAMESERVER,
		.kind = EVENT_FRAMESERVER_DROPPEDFRAME,
		.data.frameserver.pts = pts,
		.data.frameserver.counter = dropcount,
		.data.frameserver.otag = src->tag,
		.data.frameserver.video = src->vid
	};

	arcan_event_enqueue(arcan_event_defaultctx(), &deliv);
}

arcan_errc arcan_frameserver_audioframe_shared(arcan_aobj* aobj,
	arcan_aobj_id id, unsigned buffer, void* tag)
{
	arcan_frameserver* src = (arcan_frameserver*) tag;
	struct arcan_shmif_page* shmpage = src->shm.ptr;

	if (!shmpage || !shmpage->aready)
		return ARCAN_ERRC_NOTREADY;

	if (shmpage->abufused)
		arcan_audio_buffer(aobj, buffer, src->audp, shmpage->abufused,
			src->desc.channels, src->desc.samplerate, tag);

	shmpage->abufused = 0;
	shmpage->aready = false;
	arcan_sem_post(src->async);

	return ARCAN_OK;
}

arcan_errc arcan_frameserver_audioframe_direct(arcan_aobj* aobj, 
	arcan_aobj_id id, unsigned buffer, void* tag)
{
	arcan_errc rv = ARCAN_ERRC_NOTREADY;
	arcan_frameserver* src = (arcan_frameserver*) tag;

/* buffer == 0, shutting down */
	if (buffer > 0 && src->audb && src->ofs_audb > ARCAN_ASTREAMBUF_LLIMIT){
/* this function will make sure all monitors etc. gets their chance */
		pthread_mutex_lock(&src->lock_audb);
			arcan_audio_buffer(aobj, buffer, src->audb, src->ofs_audb, 
				src->desc.channels, src->desc.samplerate, tag);
		pthread_mutex_unlock(&src->lock_audb);

		src->ofs_audb = 0;

		rv = ARCAN_OK;
	}

	return rv;
}

void arcan_frameserver_tick_control(arcan_frameserver* src)
{
	struct arcan_shmif_page* shmpage = src->shm.ptr;

    if (!arcan_frameserver_control_chld(src) || !src || !shmpage){
		vfunc_state cstate = *arcan_video_feedstate(src->vid);
		arcan_video_alterfeed(src->vid, arcan_frameserver_emptyframe, cstate);
        return;
    }

/* only allow the two categories below, and only let the 
 * internal event queue be filled to half in order to not 
 * have a crazy frameserver starve the main process */
	arcan_event_queuetransfer(arcan_event_defaultctx(), &src->inqueue, 
		src->queue_mask, 0.5, src->vid);

/* may happen multiple- times, reasonably costly, might
 * want rate-limit this */
	if ( shmpage->resized ){
		vfunc_state cstate = *arcan_video_feedstate(src->vid);
		img_cons store = {
			.w = shmpage->w, 
			.h = shmpage->h, 
			.bpp = ARCAN_SHMPAGE_VCHANNELS
		};

		src->desc.width = store.w; 
		src->desc.height = store.h; 
		src->desc.bpp = store.bpp;

/* resize the source vid in a way that won't propagate to user scripts */
		src->desc.samplerate = ARCAN_SHMPAGE_SAMPLERATE;
		src->desc.channels = ARCAN_SHMPAGE_ACHANNELS;

		arcan_event_maskall(arcan_event_defaultctx());
/* this will also emit the resize event */
		arcan_video_resizefeed(src->vid, store, store);
		arcan_event_clearmask(arcan_event_defaultctx());
		arcan_shmif_calcofs(shmpage, &(src->vidp), &(src->audp));

/* for PBO transfers, new buffers etc. need to be prepared
 * that match the new internal resolution */
		glBindTexture(GL_TEXTURE_2D, 
			arcan_video_getobject(src->vid)->vstore->vinf.text.glid);

		if (src->desc.pbo_transfer)
			glDeleteBuffers(2, src->desc.upload_pbo);

/* PBO support has on some buggy drivers been dynamically failing,
 * this was a safety fallback for that kind of behavior */
		src->desc.pbo_transfer = src->use_pbo;

		if (src->use_pbo){
			glGenBuffers(2, src->desc.upload_pbo);
			for (int i = 0; i < 2; i++){
				glBindBuffer(GL_PIXEL_PACK_BUFFER, src->desc.upload_pbo[i]);
				glBufferData(GL_PIXEL_PACK_BUFFER, store.w * store.h * store.bpp, 
					NULL, GL_STREAM_DRAW);
				void* ptr = glMapBuffer(GL_PIXEL_PACK_BUFFER, GL_WRITE_ONLY);
				if (ptr){
					memset(ptr, 0, store.w * store.h * store.bpp);
				}
				glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
				glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
			}
			glBindTexture(GL_TEXTURE_2D, 0);
		}

/*
 * with a resize, our framequeues are possibly invalid, dump them
 * and rebuild, slightly different if we don't maintain a queue 
 * (present as soon as possible)
 */
		arcan_video_alterfeed(src->vid, 
			arcan_frameserver_videoframe_direct, cstate);

		arcan_event rezev = {
			.category = EVENT_FRAMESERVER,
			.kind = EVENT_FRAMESERVER_RESIZED,
			.data.frameserver.width = store.w,
			.data.frameserver.height = store.h,
			.data.frameserver.video = src->vid,
			.data.frameserver.audio = src->aid,
			.data.frameserver.otag = src->tag,
			.data.frameserver.glsource = shmpage->glsource
		};

		arcan_event_enqueue(arcan_event_defaultctx(), &rezev);

/* acknowledge the resize */
		shmpage->resized = false;
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

	res->use_pbo = arcan_video_display.pbo_support;
	res->watch_const = 0xdead;

	pthread_mutex_init(&res->lock_audb, NULL);

	res->playstate = ARCAN_PLAYING;
	res->child_alive = true;

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

/* avfeed   = sync audio and video transfers independently,
 * movie    = legacy back when we used ffmpeg backend
 * libretro = sync audio and video on video only */
	if (setup.use_builtin){
		if ((strcmp(setup.args.builtin.mode, "movie") == 0) ||
		(strcmp(setup.args.builtin.mode, "avfeed") == 0)){
			ctx->kind     = ARCAN_FRAMESERVER_AVFEED;
			ctx->socksig  = false;
			ctx->aid      = arcan_audio_feed((arcan_afunc_cb)
											arcan_frameserver_audioframe_shared, ctx, &errc);
			ctx->sz_audb  = 0; 
			ctx->ofs_audb = 0;

			ctx->queue_mask = EVENT_EXTERNAL;
		} 
/* "libretro" (or rather, interactive mode) treats a single pair of 
 * videoframe+audiobuffer each transfer, minimising latency is key. */ 
		else if (strcmp(setup.args.builtin.mode, "libretro") == 0){
			ctx->aid      = arcan_audio_feed((arcan_afunc_cb) 
												arcan_frameserver_audioframe_direct, ctx, &errc);
			ctx->kind     = ARCAN_FRAMESERVER_INTERACTIVE;
			ctx->sz_audb  = 1024 * 64;
			ctx->socksig  = false;
			ctx->ofs_audb = 0;
			ctx->audb     = arcan_alloc_mem(ctx->sz_audb,
				ARCAN_MEM_ABUFFER, 0, ARCAN_MEMALIGN_PAGE);
			ctx->queue_mask = EVENT_EXTERNAL;
		}

/* network client needs less in terms of buffering etc. but instead a 
 * different signalling mechanism for flushing events */
		else if (strcmp(setup.args.builtin.mode, "net-cl") == 0){
			ctx->kind    = ARCAN_FRAMESERVER_NETCL;
			ctx->use_pbo = false;
			ctx->socksig = true;
			ctx->queue_mask = EVENT_EXTERNAL | EVENT_NET;
		}
		else if (strcmp(setup.args.builtin.mode, "net-srv") == 0){
			ctx->kind    = ARCAN_FRAMESERVER_NETSRV;
			ctx->use_pbo = false;
			ctx->socksig = true;
			ctx->queue_mask = EVENT_EXTERNAL | EVENT_NET;
		}

/* record instead operates by maintaining up-to-date local buffers, 
 * then letting the frameserver sample whenever necessary */
		else if (strcmp(setup.args.builtin.mode, "record") == 0){
			ctx->kind = ARCAN_FRAMESERVER_OUTPUT;

/* we don't know how many audio feeds are actually monitored to produce the
 * output, thus not how large the intermediate buffer should be to 
 * safely accommodate them all */
			ctx->sz_audb = ARCAN_SHMPAGE_AUDIOBUF_SZ;
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
		ctx->kind = ARCAN_HIJACKLIB;
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
}
