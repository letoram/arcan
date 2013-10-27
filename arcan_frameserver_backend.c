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
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>
#include <assert.h>
#include <limits.h>
#include <pthread.h>

#ifndef _WIN32
#include <sys/socket.h>
#endif

#include <AL/al.h>
#include <AL/alc.h>

#include GL_HEADERS

/* arcan */
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_framequeue.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_audio.h"
#include "arcan_audioint.h"
#include "arcan_frameserver_backend.h"
#include "arcan_frameserver_shmpage.h"
#include "arcan_event.h"

#define INCR(X, C) ( (X = (X + 1) % C) )

extern int check_child(arcan_frameserver*);

static struct {
	unsigned vcellcount;
	unsigned abufsize;
	unsigned short acellcount;
	unsigned presilence;
} queueopts = {
	.vcellcount = ARCAN_FRAMESERVER_VCACHE_LIMIT,
	.abufsize   = ARCAN_FRAMESERVER_ABUFFER_SIZE,
	.acellcount = ARCAN_FRAMESERVER_ACACHE_LIMIT,
	.presilence = ARCAN_FRAMESERVER_PRESILENCE
};

void arcan_frameserver_queueopts_override(unsigned short vcellcount,
	unsigned short abufsize, unsigned short acellcount, 
	unsigned short presilence)
{
	queueopts.vcellcount = vcellcount;
	queueopts.abufsize = abufsize;
	queueopts.acellcount = acellcount;
	queueopts.presilence = presilence;
}

void arcan_frameserver_queueopts(unsigned short* vcellcount, 
	unsigned short* acellcount, unsigned short* abufsize, 
	unsigned short* presilence){
	if (vcellcount)
		*vcellcount = queueopts.vcellcount;

	if (abufsize)
		*abufsize = queueopts.abufsize;

	if (acellcount)
		*acellcount = queueopts.acellcount;

	if (presilence)
		*presilence = queueopts.presilence;
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
	free(work);
}

void arcan_frameserver_dropsemaphores(arcan_frameserver* src){
	if (src && src->shm.key && src->shm.ptr){
		struct frameserver_shmpage* shmpage = src->shm.ptr;
		arcan_frameserver_dropsemaphores_keyed(src->shm.key);
	}
}

bool arcan_frameserver_control_chld(arcan_frameserver* src){
/* bunch of terminating conditions -- frameserver messes 
 * with the structure to provoke a vulnerability, frameserver 
 * dying or timing out, ... */
	if (frameserver_shmpage_integrity_check(src->shm.ptr) == false ||
		(src->child_alive && src->child && -1 == 
		 check_child(src) && errno == EINVAL))
	{
		arcan_event sevent = {.category = EVENT_FRAMESERVER,
		.kind = EVENT_FRAMESERVER_TERMINATED,
		.data.frameserver.video = src->vid,
		.data.frameserver.glsource = false,
		.data.frameserver.audio = src->aid,
		.data.frameserver.otag = src->tag
		};
		
/*
 * prevent looping if the frameserver didn't last more than a second, 
 * indicative of it being broken, rapid relaunching could result
 * in triggering alarm systems etc. for fork() bombs 
 */
		if (src->loop && abs(arcan_frametime() - src->launchedtime) > 1000 ){
			arcan_frameserver_free(src, true);
			src->autoplay = true;
			sevent.kind = EVENT_FRAMESERVER_LOOPED;

			struct frameserver_envp args = {
				.use_builtin = true,
				.args.builtin.resource = src->source,
				.args.builtin.mode = "movie"
			};

			arcan_frameserver_spawn_server(src, args);
		}

/* force flush beforehand */
		arcan_event_queuetransfer(arcan_event_defaultctx(), &src->inqueue, 
			EVENT_EXTERNAL | EVENT_NET, 0.5, src->vid);
		arcan_event_enqueue(arcan_event_defaultctx(), &sevent);
		return false;
	}

	return true;
}

arcan_errc arcan_frameserver_pushevent(arcan_frameserver* dst, 
	arcan_event* ev){
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

/* NOTE: when arcan_event_serialize(*buffer) is implemented,
 * the queue should be stripped from the shmpage entirely and only 
 * transferred over the socket(!) */
	if (dst && ev)
		rv = dst->child_alive ?
			(arcan_event_enqueue(&dst->outqueue, ev), ARCAN_OK) :
			ARCAN_ERRC_UNACCEPTED_STATE;

#ifndef _WIN32
	if (dst->kind == ARCAN_FRAMESERVER_NETCL || 
		dst->kind == ARCAN_FRAMESERVER_NETSRV){
		int sn = 0;
		send(dst->sockout_fd, &sn, sizeof(int), MSG_DONTWAIT);
	}
#endif

	return rv;
}

static int push_buffer(arcan_frameserver* src, char* buf, unsigned int glid,
	unsigned sw, unsigned sh, unsigned bpp,
	unsigned dw, unsigned dh, unsigned dpp)
{
	int8_t rv;

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
 * in the first place */
	if (src->desc.pbo_transfer){
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
	}
	else
		glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, sw, sh,
			GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, buf);

	glBindTexture(GL_TEXTURE_2D, 0);

	return FFUNC_RV_NOUPLOAD;
}

int8_t arcan_frameserver_dummyframe(enum arcan_ffunc_cmd cmd, uint8_t* buf, 
	uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, 
	unsigned mode, vfunc_state state)
{
    if (state.tag == ARCAN_TAG_FRAMESERV && state.ptr && cmd == ffunc_destroy)
        arcan_frameserver_free( (arcan_frameserver*) state.ptr, false);

    return FFUNC_RV_NOFRAME;
}

int8_t arcan_frameserver_emptyframe(enum arcan_ffunc_cmd cmd, uint8_t* buf, 
	uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, 
	unsigned mode, vfunc_state state)
{

	if (state.tag == ARCAN_TAG_FRAMESERV && state.ptr)
	switch (cmd){
		case ffunc_tick:
			arcan_frameserver_tick_control( (arcan_frameserver*) state.ptr);
		break;

		case ffunc_destroy:
			arcan_frameserver_free( (arcan_frameserver*) state.ptr, false);
		break;

		default:
			break;
	}

	return FFUNC_RV_NOFRAME;
}

int8_t arcan_frameserver_videoframe_direct(enum arcan_ffunc_cmd cmd, 
	uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, 
	unsigned int mode, vfunc_state state)
{
	int8_t rv = 0;
	if (state.tag != ARCAN_TAG_FRAMESERV || !state.ptr)
		return rv;

	arcan_frameserver* tgt = state.ptr;
	arcan_vobject* vobj = arcan_video_getobject(tgt->vid);
	struct frameserver_shmpage* shmpage = tgt->shm.ptr;
	unsigned srcw, srch, srcbpp;

	switch (cmd){
	case ffunc_rendertarget_readback: break;
	case ffunc_poll:
		if (shmpage->resized)
			arcan_frameserver_tick_control( tgt);

		return shmpage->vready;
	break;
	case ffunc_tick: arcan_frameserver_tick_control( tgt ); break;
	case ffunc_destroy: arcan_frameserver_free( tgt, false ); break;

	case ffunc_render:
		arcan_event_queuetransfer(arcan_event_defaultctx(), &tgt->inqueue, 
			EVENT_EXTERNAL | EVENT_NET, 0.5, tgt->vid);
/* as we don't really "synch on resize", if one is 
 * detected, just ignore this frame */
		srcw = shmpage->storage.w;
		srch = shmpage->storage.h;
	
		if (srcw == tgt->desc.width && srch == tgt->desc.height){
			rv = push_buffer( tgt, (char*) tgt->vidp, mode, srcw, srch, 
				GL_PIXEL_BPP, width, height, GL_PIXEL_BPP);

			if (shmpage->aready) {
				sem_wait(&tgt->lock_audb);

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
				sem_post(&tgt->lock_audb);

				shmpage->abufused = 0;
				shmpage->aready = false;
			}
		}
/* interactive frameserver blocks on vsemaphore only, 
 * so set monitor flags and wake up */
		shmpage->vready = false;
		arcan_sem_post( tgt->vsync );
	break;
  }

	return rv;
}

int8_t arcan_frameserver_avfeedframe(enum arcan_ffunc_cmd cmd, uint8_t* buf, 
	uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, 
	unsigned mode, vfunc_state state)
{
	assert(state.ptr);
	assert(state.tag == ARCAN_TAG_FRAMESERV);
	arcan_frameserver* src = (arcan_frameserver*) state.ptr;

	if (cmd == ffunc_destroy)
		arcan_frameserver_free(state.ptr, false);

	else if (cmd == ffunc_tick){
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
	else if (cmd == ffunc_rendertarget_readback){
		if ( arcan_sem_timedwait(src->vsync, 0) == 0){

			memcpy(src->vidp, buf, s_buf);
			if (src->ofs_audb){
				sem_wait(&src->lock_audb);
					memcpy(src->audp, src->audb, src->ofs_audb);
					src->shm.ptr->abufused = src->ofs_audb;
					src->ofs_audb = 0;
				sem_post(&src->lock_audb);
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
		}
	}
	else;

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
		free(dst->amixer.inaud);
		
	dst->amixer.inaud = malloc(n_sources * sizeof(struct frameserver_audsrc) 
		* n_sources);
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
	sem_wait(&dst->lock_audb);
	if (dst->amixer.n_aids > 0){
		feed_amixer(dst, src, (int16_t*) buf, buf_sz >> 1);
	} 
	else if (dst->ofs_audb + buf_sz < dst->sz_audb){
			memcpy(dst->audb + dst->ofs_audb, buf, buf_sz);
			dst->ofs_audb += buf_sz;
	}
	else;
	sem_post(&dst->lock_audb);
}

int8_t arcan_frameserver_videoframe(enum arcan_ffunc_cmd cmd, uint8_t* buf, 
	uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, 
	unsigned gltarget, vfunc_state vstate)
{
	assert(vstate.ptr);
	assert(vstate.tag == ARCAN_TAG_FRAMESERV);

	arcan_frameserver* src = (arcan_frameserver*) vstate.ptr;
/* 
 * PEEK -
 * > 0 if there are frames to render
 */
	if (cmd == ffunc_poll) {
		if (src->shm.ptr && src->shm.ptr->resized)
			arcan_frameserver_tick_control(src);

		if (!(src->playstate == ARCAN_PLAYING))
		return FFUNC_RV_NOFRAME;

/* early out if the "synch- to PTS" feature has been disabled */
		frame_cell* ccell = arcan_framequeue_front(&src->vfq);
	
		if (src->nopts)
			return ccell ? FFUNC_RV_GOTFRAME : FFUNC_RV_NOFRAME;

		if (ccell){
/* seeks etc. start giving PTSes that are outside expected values */
			int64_t now = arcan_frametime() - src->starttime;
			int64_t delta = now - (int64_t)ccell->tag;

			if (abs(delta) > src->desc.resynchthresh){
				src->reclock = true;
				src->starttime += delta;
				delta = 0;
			}
		
/* if frames are too old, just ignore them */
			while (delta > src->desc.vskipthresh){
				arcan_framequeue_dequeue(&src->vfq);
				ccell = arcan_framequeue_front(&src->vfq); 

				if (!ccell){
					return FFUNC_RV_NOFRAME;
				}

				delta = now - (int64_t) ccell->tag;
			}
			
			if (delta > -1 * src->desc.vfthresh){
				src->lastpts = ccell->tag; 
				return FFUNC_RV_GOTFRAME;
			}
		}
		else;
	}
/* no videoframes, but we have audioframes? might be the 
 * sounddrivers that have given up, last resort workaround */

/* RENDER, can assume that peek has just happened */
	else if (cmd == ffunc_render) {
		frame_cell* current = arcan_framequeue_front(&src->vfq);
		arcan_errc rv = push_buffer( src, (char*) current->buf, 
			gltarget, src->desc.width, src->desc.height, src->desc.bpp, 
			width, height, bpp);
		arcan_framequeue_dequeue(&src->vfq);
		return rv;
	}
	else if (cmd == ffunc_tick)
		arcan_frameserver_tick_control(src);

	else if (cmd == ffunc_destroy){
		arcan_frameserver_free(src, false);
	}

	return FFUNC_RV_NOFRAME;
}

arcan_errc arcan_frameserver_audioframe_direct(arcan_aobj* aobj, 
	arcan_aobj_id id, unsigned buffer, void* tag)
{
	arcan_errc rv = ARCAN_ERRC_NOTREADY;
	arcan_frameserver* src = (arcan_frameserver*) tag;

/* buffer == 0, shutting down */
	if (buffer > 0 && src->audb && src->ofs_audb > ARCAN_ASTREAMBUF_LLIMIT){

/* this function will make sure all monitors etc. gets their chance */
		sem_wait(&src->lock_audb);
			arcan_audio_buffer(aobj, buffer, src->audb, src->ofs_audb, 
				src->desc.channels, src->desc.samplerate, tag);
		sem_post(&src->lock_audb);

		src->ofs_audb = 0;

		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_frameserver_audioframe(arcan_aobj* aobj, arcan_aobj_id id, 
	unsigned buffer, void* tag)
{
	arcan_errc rv = ARCAN_ERRC_NOTREADY;
	arcan_frameserver* src = (arcan_frameserver*) tag;

/* for each cell, buffer (-> quit), wait (-> quit) or drop(full/partially) */
	if (src->playstate == ARCAN_PLAYING){
		frame_cell* ccell;
	
		while ( (ccell = arcan_framequeue_front(&src->afq)) != NULL){
			int64_t now = arcan_frametime() - src->starttime;
			int64_t toshow = ccell->tag; 

			size_t buffers = src->afq.cell_size; 
			double dc = (double)src->lastpts - src->audioclock;
			src->audioclock += src->bpms * (double)buffers;

			const float audioframe_prethresh = 40.0f;

/* seems to work better with just have the soundcard buffer and play whatever,
 * should experiment more or make this feature programmable */
			if (1 || dc < audioframe_prethresh){
				sem_wait(&src->lock_audb);
				arcan_audio_buffer(aobj, buffer, ccell->buf, 
					buffers, src->desc.channels, src->desc.samplerate, tag);
				sem_post(&src->lock_audb);
				arcan_framequeue_dequeue(&src->afq);
				rv = ARCAN_OK;
				break;
			}
			else if (src->reclock){
				src->reclock = false;
				src->audioclock = src->lastpts;
			}
			else
				arcan_framequeue_dequeue(&src->afq);
		}
	}

	return rv;
}

static arcan_errc again_feed(float gain, void* tag)
{
	arcan_frameserver* target = tag;

	if (target){
		arcan_event ev = {
			.category = EVENT_TARGET,
			.kind = TARGET_COMMAND_ATTENUATE,
			.data.target.ioevs[0].fv = gain
		};
		arcan_frameserver_pushevent( target, &ev );

		return ARCAN_OK;
	}
	else
		return ARCAN_ERRC_NO_SUCH_OBJECT;
}

void arcan_frameserver_tick_control(arcan_frameserver* src)
{
	struct frameserver_shmpage* shmpage = src->shm.ptr;

    if (!arcan_frameserver_control_chld(src) || !src || !shmpage){
		vfunc_state cstate = *arcan_video_feedstate(src->vid);
		arcan_video_alterfeed(src->vid, arcan_frameserver_emptyframe, cstate);
        return;
    }

/* only allow the two categories below, and only let the 
 * internal event queue be filled to half in order to not 
 * have a crazy frameserver starve the main process */
	arcan_event_queuetransfer(arcan_event_defaultctx(), &src->inqueue, 
		EVENT_EXTERNAL | EVENT_NET, 0.5, src->vid);

/* may happen multiple- times, reasonably costly, might
 * want rate-limit this */
	if ( shmpage->resized ){
		arcan_errc rv;
		char labelbuf[32];
		vfunc_state cstate = *arcan_video_feedstate(src->vid);
		img_cons store = {.w = shmpage->storage.w, .h = shmpage->storage.h, 
			.bpp = SHMPAGE_VCHANNELCOUNT};
		img_cons disp  = {.w = shmpage->display.w, .h = shmpage->display.h};

		src->desc.width = store.w; 
		src->desc.height = store.h; 
		src->desc.bpp = store.bpp;

		arcan_framequeue_free(&src->vfq);
		arcan_framequeue_free(&src->afq);

/* resize the source vid in a way that won't propagate to user scripts */
		src->desc.samplerate = SHMPAGE_SAMPLERATE;
		src->desc.channels = SHMPAGE_ACHANNELCOUNT;

		arcan_event_maskall(arcan_event_defaultctx());
/* this will also emit the resize event */
		arcan_video_resizefeed(src->vid, store, disp);
		arcan_event_clearmask(arcan_event_defaultctx());
		frameserver_shmpage_calcofs(shmpage, &(src->vidp), &(src->audp));

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
		if (src->nopts){
			arcan_video_alterfeed(src->vid, 
				arcan_frameserver_videoframe_direct, cstate);
		}
		else {
			arcan_video_alterfeed(src->vid, arcan_frameserver_videoframe, cstate);

/* otherwise, figure out reasonable buffer sizes (or user-defined overrides)*/
			unsigned short acachelim, vcachelim, abufsize, presilence;
			arcan_frameserver_queueopts(&vcachelim, &acachelim, 
				&abufsize, &presilence);
			if (acachelim == 0 || abufsize == 0){
				float mspvf = 1000.0 / 30.0;
				float mspaf = 1000.0 / (float) SHMPAGE_SAMPLERATE;
				abufsize = ceilf( (mspvf / mspaf) * SHMPAGE_ACHANNELCOUNT * 2);
				acachelim = vcachelim * 2;
			}

/* tolerance margins for PTS deviations */
			src->bpms = (1000.0 / (double)src->desc.samplerate) / 
				(double)src->desc.channels * 0.5;
			src->desc.vfthresh = ARCAN_FRAMESERVER_DEFAULT_VTHRESH_SKIP;
			src->desc.vskipthresh = ARCAN_FRAMESERVER_IGNORE_SKIP_THRESH;
			src->desc.resynchthresh = ARCAN_FRAMESERVER_RESET_PTS_THRESH;
			src->audioclock = 0.0;

/* just to get some kind of trace when threading acts up */
			snprintf(labelbuf, 32, "audio_%lli", (long long) src->vid);
			arcan_framequeue_alloc(&src->afq, src->vid, acachelim, abufsize, true, 
				arcan_frameserver_shmaudcb, labelbuf);

			snprintf(labelbuf, 32, "video_%lli", (long long) src->aid);
			arcan_framequeue_alloc(&src->vfq, src->vid, vcachelim, 
				src->desc.width * src->desc.height * src->desc.bpp, false, 
				arcan_frameserver_shmvidcb, labelbuf);
		}

		arcan_event rezev = {
			.category = EVENT_FRAMESERVER,
			.kind = EVENT_FRAMESERVER_RESIZED,
			.data.frameserver.width = store.w,
			.data.frameserver.height = store.h,
			.data.frameserver.video = src->vid,
			.data.frameserver.audio = src->aid,
			.data.frameserver.otag = src->tag,
			.data.frameserver.glsource = shmpage->storage.glsource
		};

		arcan_event_enqueue(arcan_event_defaultctx(), &rezev);

		if (src->autoplay && src->playstate != ARCAN_PLAYING)
			arcan_frameserver_playback(src);

/* acknowledge the resize */
		shmpage->resized = false;
	}

}

arcan_errc arcan_frameserver_playback(arcan_frameserver* src)
{
	if (!src)
		return ARCAN_ERRC_BAD_ARGUMENT;

	src->starttime = arcan_frametime();
	src->playstate = ARCAN_PLAYING;

	arcan_audio_play(src->aid, false, 0.0);
	return ARCAN_OK;
}

arcan_errc arcan_frameserver_pause(arcan_frameserver* src, bool syssusp)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (src) {
		src->playstate = (syssusp ? ARCAN_SUSPENDED : ARCAN_PAUSED);
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_frameserver_resume(arcan_frameserver* src)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (src && (src->playstate == ARCAN_PAUSED ||
		src->playstate == ARCAN_SUSPENDED)
	) {
		src->playstate = ARCAN_PLAYING;
		/* arcan_audio_play(src->aid); */

		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_frameserver_flush(arcan_frameserver* fsrv)
{
	if (!fsrv)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (fsrv->vfq.alive){
		arcan_framequeue_flush(&fsrv->vfq);
	}
	
	if (fsrv->afq.alive){
		arcan_framequeue_flush(&fsrv->afq);
/* FIXME: have arcan_audio drop all queued output buffers as well,
 * otherwise we can get drift with multiple consequtive flushes */
		fsrv->reclock = true;
	}
}

/* video- frames will always yield a ntr here that
 * corresponds to a full frame (no partials allowed) */
ssize_t arcan_frameserver_shmvidcb(int fd, void* dst, size_t ntr)
{
	ssize_t rv = -1;
	vfunc_state* state = arcan_video_feedstate(fd);

	if (state && state->tag == ARCAN_TAG_FRAMESERV && 
		((arcan_frameserver*)state->ptr)->child_alive) {
		arcan_frameserver* movie = state->ptr;
		struct frameserver_shmpage* shm = movie->shm.ptr;

			if (shm->vready) {
				frame_cell* current = &(movie->vfq.da_cells[ movie->vfq.ni ]);
				current->tag = shm->vpts;
				memcpy(dst, movie->vidp, ntr);
				shm->vready = false;
				arcan_sem_post(movie->vsync);
				rv = ntr;
			}
			else
				errno = EAGAIN;
	}
	else
		errno = EINVAL;

	return rv;
}

/* audio on the other hand, is not set up to get a fixed frame-size,
 * so here we may need to buffer */
ssize_t arcan_frameserver_shmaudcb(int fd, void* dst, size_t ntr)
{
	vfunc_state* state = arcan_video_feedstate(fd);
	ssize_t rv = -1;

	if (state && state->tag == ARCAN_TAG_FRAMESERV && 
		((arcan_frameserver*)state->ptr)->child_alive) {
		arcan_frameserver* movie = (arcan_frameserver*) state->ptr;
		struct frameserver_shmpage* shm = (struct frameserver_shmpage*)
			movie->shm.ptr;

		if (shm->aready) {
			frame_cell* current = &(movie->afq.da_cells[ movie->afq.ni ]);
			current->tag = shm->vpts;

/* more in buffer than we can process in this frame? copy as much
 * as possible, return and let the main lock/step */
			if (shm->abufused - shm->abufbase > ntr) {
				memcpy(dst, movie->audp + shm->abufbase, ntr);
				shm->abufbase += ntr;
				rv = ntr;
			}
			else {
				size_t nc = shm->abufused - shm->abufbase;
				memcpy(dst, movie->audp + shm->abufbase, nc);
				shm->abufused = 0;
				shm->abufbase = 0;
				shm->aready = false;
				arcan_sem_post(movie->async);
				rv = nc;
			}
		}
		else
			errno = EAGAIN;
	}
	else
		errno = EINVAL;

	return rv;
}

arcan_frameserver* arcan_frameserver_alloc()
{
	arcan_frameserver* res = malloc(sizeof(arcan_frameserver));
	if (!res)
		return NULL;

	memset(res, 0, sizeof(arcan_frameserver));
	res->use_pbo = arcan_video_display.pbo_support;
	res->watch_const = 0xdead;
	return res;
}

void arcan_frameserver_configure(arcan_frameserver* ctx, 
	struct frameserver_envp setup)
{
	arcan_errc errc;
	
/* "movie" mode involves parallel queues of raw, decoded, 
 * frames and heuristics for dropping, delaying or showing 
 * frames based on DTS/PTS values */
	if (setup.use_builtin){
		if (strcmp(setup.args.builtin.mode, "movie") == 0){
			ctx->kind  = ARCAN_FRAMESERVER_INPUT;
			ctx->aid   = arcan_audio_feed((arcan_afunc_cb) 
											arcan_frameserver_audioframe, ctx, &errc);
/* nopts / autoplay is preset from the calling context */
		}

/* "libretro" (or rather, interactive mode) treats a single pair of 
 * videoframe+audiobuffer each transfer, minimising latency is key. 
 * All operations require an intermediate buffer and are synched 
 * to one framequeue */
		else if (strcmp(setup.args.builtin.mode, "libretro") == 0){
			ctx->nopts    = true;
			ctx->autoplay = true;
			ctx->aid      = arcan_audio_feed((arcan_afunc_cb) 
												arcan_frameserver_audioframe_direct, ctx, &errc);
			ctx->kind     = ARCAN_FRAMESERVER_INTERACTIVE;
			ctx->sz_audb  = 1024 * 64;
			ctx->ofs_audb = 0;
			ctx->audb     = malloc( ctx->sz_audb );
		}

/* network client needs less in terms of buffering etc. but instead a 
 * different signalling mechanism for flushing events */
		else if (strcmp(setup.args.builtin.mode, "net-cl") == 0){
			ctx->kind    = ARCAN_FRAMESERVER_NETCL;
			ctx->use_pbo = false;
			ctx->nopts   = false;
			ctx->autoplay= true;
		}
		else if (strcmp(setup.args.builtin.mode, "net-srv") == 0){
			ctx->kind    = ARCAN_FRAMESERVER_NETSRV;
			ctx->use_pbo = false;
			ctx->nopts   = false;
			ctx->autoplay= true;
		}

/* record instead operates by maintaining up-to-date local buffers, 
 * then letting the frameserver sample whenever necessary */
		else if (strcmp(setup.args.builtin.mode, "record") == 0){
			ctx->kind = ARCAN_FRAMESERVER_OUTPUT;

/* we don't know how many audio feeds are actually monitored to produce the
 * output, thus not how large the intermediate buffer should be to 
 * safely accommodate them all */
			ctx->sz_audb = SHMPAGE_AUDIOBUF_SIZE;
			ctx->audb = malloc( ctx->sz_audb );
		}
	}
/* hijack works as a 'process parasite' inside the rendering pipeline of 
 * other projects, either through a generic fallback library or for
 * specialized "per- target" (in order to minimize size and handle 32/64
 * switching parent-vs-child relations */
	else{
		ctx->kind = ARCAN_HIJACKLIB;
		ctx->autoplay = true;
		ctx->nopts = true;

/* although audio playback tend to be kept in the child process, the
 * sampledata may still be needed for recording/monitoring */ 
		ctx->sz_audb  = 1024 * 64;
		ctx->ofs_audb = 0;
		ctx->audb     = malloc( ctx->sz_audb );
	}

	sem_init(&ctx->lock_audb, 0, 1);
	arcan_frameserver_meta vinfo = {0};

	ctx->child_alive = true;
	ctx->desc        = vinfo;

/* these are just placeholders to be able to return a real vid without
 * stalling waiting for the other process to finish, so the first event
 * tend to be a resize- */ 
	ctx->desc.width  = 32;
	ctx->desc.height = 32;
	ctx->desc.bpp    = GL_PIXEL_BPP;

/* two separate queues for passing events back and forth between main program
 * and frameserver, set the buffer pointers to the relevant offsets in 
 * backend_shmpage, and semaphores from the sem_open calls -- plan is 
 * to switch this behavior on some platforms to instead use sockets to 
 * improve I/O multiplexing (network- frameservers) or at least have futex
 * triggers on Linux */
	frameserver_shmpage_setevqs(ctx->shm.ptr, ctx->esync, 
		&(ctx->inqueue), &(ctx->outqueue), true);
	ctx->inqueue.synch.external.killswitch = ctx;
	ctx->outqueue.synch.external.killswitch = ctx;
}
