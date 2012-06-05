/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>
#include <assert.h>

#include <al.h>
#include <alc.h>

/* libSDL */
#include <SDL.h>
#include <SDL_types.h>
#include <SDL_opengl.h>

/* arcan */
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_framequeue.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_frameserver_backend.h"
#include "arcan_frameserver_shmpage.h"
#include "arcan_event.h"
#include "arcan_util.h"

#define INCR(X, C) ( (X = (X + 1) % C) )

extern int check_child(arcan_frameserver*);

static struct {
	unsigned vcellcount;
	unsigned abufsize;
	unsigned short acellcount;
} queueopts = {
	.vcellcount = ARCAN_FRAMESERVER_VCACHE_LIMIT,
	.abufsize = ARCAN_FRAMESERVER_ABUFFER_SIZE,
	.acellcount = ARCAN_FRAMESERVER_ACACHE_LIMIT
};

void arcan_frameserver_queueopts_override(unsigned short vcellcount, unsigned short abufsize, unsigned short acellcount)
{
	queueopts.vcellcount = vcellcount;
	queueopts.abufsize = abufsize;
	queueopts.acellcount = acellcount;
}

void arcan_frameserver_queueopts(unsigned short* vcellcount, unsigned short* acellcount, unsigned short* abufsize){
	if (vcellcount)
		*vcellcount = queueopts.vcellcount;

	if (abufsize)
		*abufsize = queueopts.abufsize;
	
	if (acellcount)
		*acellcount = queueopts.acellcount;
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
		struct frameserver_shmpage* shmpage = (struct frameserver_shmpage*) src->shm.ptr;
		arcan_frameserver_dropsemaphores_keyed(src->shm.key);
	}
}

bool arcan_frameserver_check_frameserver(arcan_frameserver* src)
{
	if (src && src->loop){
		arcan_frameserver_free(src, true);
		arcan_audio_pause(src->aid);

/* with asynch movieplayback, we can't set it to playing state before loaded */
		src->autoplay = true;
		
		struct frameserver_envp args = {
			.use_builtin = true,
			.args.builtin.resource = src->source,
			.args.builtin.mode = "movie"
		};
		
		arcan_frameserver_spawn_server(src, args);
		return false;
	}
	else{
		arcan_event ev = {
			.category = EVENT_SYSTEM,
			.kind = EVENT_SYSTEM_FRAMESERVER_TERMINATED
		};
		ev.data.system.hitag = src->vid;
		ev.data.system.lotag = src->aid;
		arcan_event_enqueue(arcan_event_defaultctx(), &ev);
		arcan_frameserver_free(src, false);
	}

	return true;
}

arcan_errc arcan_frameserver_pushevent(arcan_frameserver* dst, arcan_event* ev)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	
	if (dst && ev)
		rv = dst->child_alive ? 
			(arcan_event_enqueue(&dst->outqueue, ev), ARCAN_OK) : 
			ARCAN_ERRC_UNACCEPTED_STATE;
	
	return rv;
}

int8_t arcan_frameserver_emptyframe(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned mode, vfunc_state state){
	
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
    
	return 0;
}

int8_t arcan_frameserver_videoframe_direct(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned int mode, vfunc_state state)
{
	int8_t rv = 0;
	if (state.tag != ARCAN_TAG_FRAMESERV || !state.ptr)
		return rv;

	arcan_frameserver* tgt = (arcan_frameserver*) state.ptr;
	struct frameserver_shmpage* shmpage = (struct frameserver_shmpage*) tgt->shm.ptr;
	
	/* should have a special framequeue mode which supports more direct form of rendering */
	switch (cmd){
		case ffunc_poll: return shmpage->vready; break;        
        case ffunc_tick: arcan_frameserver_tick_control( (arcan_frameserver*) state.ptr); break;		
		case ffunc_destroy: arcan_frameserver_free( tgt, false ); break;
		case ffunc_render:
			if (width != shmpage->w || 
				height != shmpage->h) {
					uint16_t cpy_width  = (width > shmpage->w ? shmpage->w : width);
					uint16_t cpy_height = (height > shmpage->h ? shmpage->h : height);
					assert(bpp == shmpage->bpp);
					
					for (uint16_t row = 0; row < cpy_height && row < cpy_height; row++)
						memcpy(buf + (row * width * bpp),
						       ((void*)shmpage + shmpage->vbufofs) + (row * shmpage->w * shmpage->bpp),
						       cpy_width * bpp
						);
						
					rv = FFUNC_RV_COPIED; 
			}
			else {  /* need to reduce all those copies if at all possible .. */
				glBindTexture(GL_TEXTURE_2D, mode);
				glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, (char*)shmpage + shmpage->vbufofs);

				rv = FFUNC_RV_NOUPLOAD;
			}

			shmpage->vready = false;
			arcan_sem_post( tgt->vsync );
		break;
    }

	return rv;
}

int8_t arcan_frameserver_videoframe(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned gltarget, vfunc_state vstate)
{
	enum arcan_ffunc_rv rv = FFUNC_RV_NOFRAME;

	assert(vstate.ptr);
	assert(vstate.tag == ARCAN_TAG_FRAMESERV);
	
	arcan_frameserver* src = (arcan_frameserver*) vstate.ptr;
/* PEEK -
	 * > 0 if there are frames to render
	*/
	if (cmd == ffunc_poll) {
		if (!(src->playstate == ARCAN_PLAYING))
		return rv;

/* early out if the "synch- to PTS" feature has been disabled */
		if (src->nopts && src->vfq.front_cell != NULL)
			return FFUNC_RV_GOTFRAME;
		
	#ifdef _DEBUG                
        arcan_event ev = {.kind = EVENT_VIDEO_MOVIESTATUS, .data.video.constraints.w = src->vfq.c_cells,
        .data.video.constraints.h = src->afq.c_cells, .data.video.props.position.x = src->vfq.n_cells,
            .data.video.props.position.y = src->afq.n_cells, .category = EVENT_VIDEO};
        arcan_event_enqueue(arcan_event_defaultctx(), &ev);
#endif  
		if (src->vfq.front_cell) {
			int64_t now = arcan_frametime() - src->starttime;

		/* if frames are too old, just ignore them */
			while (src->vfq.front_cell && 
				(now - (int64_t)src->vfq.front_cell->tag > (int64_t) src->desc.vskipthresh)){
				src->lastpts = src->vfq.front_cell->tag;
				arcan_framequeue_dequeue(&src->vfq);
			}

		/* if there are any frames left, check if the difference between then and now is acceptible */
			if (src->vfq.front_cell != NULL &&
				abs((int64_t)src->vfq.front_cell->tag - now) < (int64_t) src->desc.vskipthresh){
					src->lastpts = src->vfq.front_cell->tag;
					return FFUNC_RV_GOTFRAME;
			}
			else;
		}
		else if (src->vfq.alive == false) {
				arcan_event sevent = {.category = EVENT_VIDEO,
				                      .kind = EVENT_VIDEO_FRAMESERVER_TERMINATED,
				                      .data.video.data = src,
				                      .data.video.source = src->vid
				                     };
				src->playstate = ARCAN_PAUSED;

				arcan_event_enqueue(arcan_event_defaultctx(), &sevent);
			}
/* no videoframes, but we have audioframes? might be the sounddrivers that have given up,
 * last resort workaround */
	}
	/* RENDER, can assume that peek has just happened */
	else if (cmd == ffunc_render) {
			frame_cell* current = src->vfq.front_cell;
			if (src->vfq.cell_size != s_buf) {
				/* cap to the size of the "to feed" object */
				uint16_t cpy_width  = (width  > src->desc.width  ? src->desc.width  : width);
				uint16_t cpy_height = (height > src->desc.height ? src->desc.height : height);

				for (uint16_t row = 0; row < cpy_height; row++)
					memcpy(buf + (row * width * bpp),
						current->buf + (row * src->desc.width * src->desc.bpp),
						cpy_width * src->desc.bpp);
                
				rv = FFUNC_RV_COPIED;
			}
			else {
				glBindTexture(GL_TEXTURE_2D, gltarget);
				glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, (char*)current->buf);
				rv = FFUNC_RV_NOUPLOAD;
			}

			arcan_framequeue_dequeue(&src->vfq);
	}
	else if (cmd == ffunc_tick && !check_child(src)){
		arcan_frameserver_free(src, src->loop);
	}
	else if (cmd == ffunc_destroy){
		arcan_frameserver_free(src, false);
	}

	return rv;
}

/* synching behavior is different in this mode,
 * the semaphore is used as a mutex rather than than a conditional */
arcan_errc arcan_frameserver_audioframe_direct(void* aobj, arcan_aobj_id id, unsigned buffer, void* tag)
{
	arcan_errc rv = ARCAN_ERRC_NOTREADY;
	arcan_frameserver* src = (arcan_frameserver*) tag;
	
	struct frameserver_shmpage* shmpage = (struct frameserver_shmpage*) src->shm.ptr;
	if (shmpage->abufused > 0 && arcan_sem_timedwait(src->async, 1) ){
		
		alBufferData(buffer, AL_FORMAT_STEREO16, (void*)shmpage + shmpage->abufofs, shmpage->abufused, src->desc.samplerate);
		rv = ARCAN_OK;
	
		shmpage->abufused = 0;
		shmpage->aready = false;

		arcan_sem_post(src->async);
	}
	
	return rv;
}

arcan_errc arcan_frameserver_audioframe(void* aobj, arcan_aobj_id id, unsigned buffer, void* tag)
{
	arcan_errc rv = ARCAN_ERRC_NOTREADY;
	arcan_frameserver* src = (arcan_frameserver*) tag;

/* for each cell, buffer (-> quit), wait (-> quit) or drop (full/partially) */
	if (src->playstate == ARCAN_PLAYING){
		while (src->afq.front_cell){
			int64_t now = arcan_frametime() - src->starttime;
			int64_t toshow = src->afq.front_cell->tag;

/* as there are latencies introduced by the audiocard etc. as well,
 * it is actually somewhat beneficial to lie a few ms ahead of the videotimer */
			size_t buffers = src->afq.cell_size - (src->afq.cell_size - src->afq.front_cell->ofs);
			double dc = (double)src->lastpts - src->audioclock;
			src->audioclock += src->bpms * (double)buffers;

/* not more than 60ms and not severe desynch? send the audio, else we drop and continue */
			if (dc < 60.0){
				alBufferData(buffer, AL_FORMAT_STEREO16, src->afq.front_cell->buf, buffers, src->desc.samplerate);
				arcan_framequeue_dequeue(&src->afq);
				rv = ARCAN_OK;
				break;
			}
		
			arcan_framequeue_dequeue(&src->afq);
		}
	} 

	return rv;
}

static arcan_errc again_feed(float gain, void* tag)
{
	arcan_frameserver* target = (arcan_frameserver*) tag;

	if (target){
		/* queue event into target */
	}
	
	return ARCAN_OK;
}

void arcan_frameserver_tick_control(arcan_frameserver* src)
{
    if (src->shm.ptr){
		struct frameserver_shmpage* shmpage = (struct frameserver_shmpage*) src->shm.ptr;

/* may happen multiple- times */
		if (shmpage->resized){
			arcan_warning("trace, resize event: %d, %d\n", shmpage->w, shmpage->h);
			vfunc_state cstate = *arcan_video_feedstate(src->vid);
			img_cons cons = {.w = shmpage->w, .h = shmpage->h, .bpp = shmpage->bpp};
            src->desc.width = cons.w; src->desc.height = cons.h; src->desc.bpp = cons.bpp;

			arcan_framequeue_free(&src->vfq);
			shmpage->resized = false;

/* resize the source vid in a way that won't propagate to user scripts */
			src->desc.samplerate = shmpage->frequency;
			src->desc.channels = shmpage->channels;
			arcan_event_maskall(arcan_event_defaultctx());
			arcan_video_resizefeed(src->vid, cons, shmpage->glsource);
			arcan_event_clearmask(arcan_event_defaultctx());

			arcan_errc rv;

/* simplified mode, disables framequeues and just use the buffer in the shared memory page */
			if (src->nopts){
				arcan_video_alterfeed(src->vid, arcan_frameserver_videoframe_direct, cstate);
				
				if (src->aid == ARCAN_EID){
					src->aid =
						src->kind == ARCAN_HIJACKLIB ? arcan_audio_proxy(again_feed, src) :
						arcan_audio_feed((arcan_afunc_cb) arcan_frameserver_audioframe_direct, src, &rv);
				}
				
			} else {
				if (src->aid == ARCAN_EID)
				src->aid = arcan_audio_feed((arcan_afunc_cb) arcan_frameserver_audioframe, src, &rv);
				arcan_video_alterfeed(src->vid, arcan_frameserver_videoframe, cstate);

/* otherwise, figure out reasonable buffer sizes (or user-defined overrides) */
				unsigned short acachelim, vcachelim, abufsize;
				arcan_frameserver_queueopts(&vcachelim, &acachelim, &abufsize);
				if (acachelim == 0 || abufsize == 0){
					float mspvf = 1000.0 / 30.0;
					float mspaf = 1000.0 / (float)shmpage->frequency;
					abufsize = ceilf( (mspvf / mspaf) * shmpage->channels * 2);
					acachelim = vcachelim * 2;
				}
				
				src->bpms = (1000.0 / (double)src->desc.samplerate) / (double)src->desc.channels * 0.5;
				src->desc.vfthresh = ARCAN_FRAMESERVER_DEFAULT_VTHRESH_SKIP;
				src->desc.vskipthresh = ARCAN_FRAMESERVER_IGNORE_SKIP_THRESH;
				src->audioclock = 0.0;
				
				char labelbuf[32];
				snprintf(labelbuf, 32, "audio_%lli", (long long) src->vid);
				arcan_framequeue_alloc(&src->afq, src->vid, acachelim, abufsize, true, arcan_frameserver_shmaudcb, labelbuf);

				snprintf(labelbuf, 32, "video_%lli", (long long) src->aid);
				arcan_framequeue_alloc(&src->vfq, src->vid, vcachelim, src->desc.width * src->desc.height * src->desc.bpp, false, arcan_frameserver_shmvidcb, labelbuf);
			}

		
			if (src->kind == ARCAN_FRAMESERVER_INPUT){
				if (src->autoplay){
					arcan_frameserver_playback(src);
				}
				else {
					arcan_event ev = {.kind = EVENT_VIDEO_MOVIEREADY, .data.video.source = src->vid,
					.data.video.constraints = cons, .category = EVENT_VIDEO};
					arcan_event_enqueue(arcan_event_defaultctx(), &ev);
				}
			}
			else if (src->kind == ARCAN_FRAMESERVER_INTERACTIVE || src->kind == ARCAN_HIJACKLIB){
				arcan_frameserver_playback(src);
				arcan_event ev = {.kind = EVENT_TARGET_INTERNAL_STATUS, .category = EVENT_TARGET,
				.data.target.video.source = src->vid,
				.data.target.video.constraints = cons,
				.data.target.audio = src->aid,
				.data.target.statuscode = TARGET_STATUS_RESIZED};
				
				arcan_event_enqueue(arcan_event_defaultctx(), &ev);
			}
			else 
				arcan_warning("(frameserver_tick_control) unhandled frameserver type (%d)\n", src->kind);
		}

/* since this is a tick, make sure that the child process is still alive */
		if (!check_child(src->shm.ptr))
			arcan_frameserver_free(src, src->loop);
	}   
}

arcan_errc arcan_frameserver_playback(arcan_frameserver* src)
{
	if (!src)
		return ARCAN_ERRC_BAD_ARGUMENT;

	if (!src->desc.ready)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	src->starttime = arcan_frametime();
	src->playstate = ARCAN_PLAYING;
	arcan_audio_play(src->aid);
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

/* video- frames will always yield a ntr here that
 * corresponds to a full frame (no partials allowed) */
ssize_t arcan_frameserver_shmvidcb(int fd, void* dst, size_t ntr)
{
	ssize_t rv = -1;
	vfunc_state* state = arcan_video_feedstate(fd);
	
	if (state && state->tag == ARCAN_TAG_FRAMESERV && ((arcan_frameserver*)state->ptr)->child_alive) {
		arcan_frameserver* movie = (arcan_frameserver*) state->ptr;
		struct frameserver_shmpage* shm = (struct frameserver_shmpage*) movie->shm.ptr;
		
		/* SDL mutex protects the shm- page for freeing etc. */
			if (shm->vready) {
                frame_cell* current = &(movie->vfq.da_cells[ movie->vfq.ni ]);
                current->tag = shm->vdts;
				memcpy(dst, (void*)shm + shm->vbufofs, ntr);
				shm->vready = false;
				rv = ntr;
				arcan_sem_post(movie->vsync);
			}
			else
				errno = EAGAIN;
	} else errno = EINVAL;

	return rv;
}

/* audio on the other hand, is not set up to get a fixed frame-size,
 * so here we may need to buffer */
ssize_t arcan_frameserver_shmaudcb(int fd, void* dst, size_t ntr)
{
	vfunc_state* state = arcan_video_feedstate(fd);
	ssize_t rv = -1;

	if (state && state->tag == ARCAN_TAG_FRAMESERV && ((arcan_frameserver*)state->ptr)->child_alive) {
		arcan_frameserver* movie = (arcan_frameserver*) state->ptr;
		struct frameserver_shmpage* shm = (struct frameserver_shmpage*)movie->shm.ptr;

			if (shm->aready) {
                frame_cell* current = &(movie->afq.da_cells[ movie->afq.ni ]);
                current->tag = shm->vdts;

				if (shm->abufused - shm->abufbase > ntr) {
					memcpy(dst, (void*) shm + shm->abufofs + shm->abufbase, ntr);
					shm->abufbase += ntr;
					rv = ntr;
				}
				else {
					size_t nc = shm->abufused - shm->abufbase;
					memcpy(dst, (void*) shm + shm->abufofs + shm->abufbase, nc);
					shm->abufbase = 0;
					shm->aready = false;
					arcan_sem_post(movie->async);
					rv = nc;
				}
			}
			else
				errno = EAGAIN;
	}else errno = EINVAL;

	return rv;
}
