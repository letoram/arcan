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

#include <al.h>
#include <alc.h>

/* libSDL */
#include <SDL.h>
#include <SDL_types.h>
#include <SDL_opengl.h>

/* arcan */
#include "arcan_general.h"
#include "arcan_framequeue.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_frameserver_backend.h"
#include "arcan_frameserver_backend_shmpage.h"
#include "arcan_event.h"
#include "arcan_util.h"

#define INCR(X, C) ( (X = (X + 1) % C) )

int arcan_frameserver_decode(void*);
extern bool check_child(arcan_frameserver*);

static struct {
	unsigned vcellcount;
	unsigned short abufsize;
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

unsigned int skip_frames(frame_queue* queue, uint32_t current, uint32_t thresh)
{
	if (!queue || !queue->front_cell)
		return 0;
	int sc = 0;

	while (queue->front_cell &&
	        (current > *(uint32_t*)(queue->front_cell->buf)) &&
	        ((current - *(uint32_t*)(queue->front_cell->buf)) > thresh)) {
		arcan_framequeue_dequeue(queue);
		sc++;
	}
	return sc;
}

void arcan_frameserver_dropsemaphores_keyed(char* key)
{
	char* work = strdup(key);
		work[ strlen(work) - 1] = 'v';
		arcan_sem_unlink(NULL, work);
		work[strlen(work) - 1] = 'a';
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
		arcan_frameserver_spawn_server(src->source, src->extcc, src->loop, src);
		arcan_frameserver_playback(src);
		return false;
	}
	else{
		arcan_event ev = {
			.category = EVENT_SYSTEM,
			.kind = EVENT_SYSTEM_FRAMESERVER_TERMINATED
		};
		
		ev.data.system.hitag = src->vid;
		ev.data.system.lotag = src->aid;
		arcan_event_enqueue(&ev);
		arcan_frameserver_free(src, false);
	}

	return true;
}

int8_t arcan_frameserver_videoframe(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned gltarget, vfunc_state vstate)
{
	enum arcan_ffunc_rv rv = FFUNC_RV_NOFRAME;
	if (vstate.tag != ARCAN_TAG_MOVIE || !vstate.ptr)
		return rv;

	arcan_frameserver* src = (arcan_frameserver*) vstate.ptr;

	if (!(src->playstate == ARCAN_PLAYING))
		return rv;

	/* PEEK -
	 * > 0 if there are frames to render
	*/
	if (cmd == ffunc_poll) {
		if (src->vfq.front_cell) {
			uint32_t toshow = *((uint32_t*)(src->vfq.front_cell->buf));
			int64_t nticks = (int64_t) SDL_GetTicks() - (int64_t) src->base_time;

			/* If we've had a huge stall, just forget that we can skip to that
			 * point and assume our time-keeping is dodgy */
			if (nticks - toshow > ARCAN_FRAMESERVER_IGNORE_SKIP_THRESH) {
				src->base_time = SDL_GetTicks();
				nticks = toshow;
			}

			if (nticks - toshow > src->desc.vskipthresh) {
				unsigned int nframes = skip_frames(&src->vfq, nticks, src->desc.vskipthresh);
				rv = src->vfq.front_cell != NULL ? FFUNC_RV_GOTFRAME : FFUNC_RV_NOFRAME;
			}
			else /* might be ahead */
				rv = (toshow - nticks) < src->desc.vfthresh ? FFUNC_RV_GOTFRAME : FFUNC_RV_NOFRAME;
		}
		else
			if (src->vfq.alive == false) {
				arcan_event sevent = {.category = EVENT_VIDEO,
				                      .kind = EVENT_VIDEO_FRAMESERVER_TERMINATED,
				                      .data.video.data = src,
				                      .data.video.source = src->vid
				                     };
				src->playstate = ARCAN_PAUSED;

				arcan_event_enqueue(&sevent);
			}
	}
	/* RENDER, can assume that peek has just happened */
	else
		if (cmd == ffunc_render) {
			frame_cell* current = src->vfq.front_cell;

			if (src->vfq.cell_size - 4 != s_buf) {
				/* cap to the size of the "to feed" object */
				uint16_t cpy_width  = (width > src->desc.width   ? src->desc.width : width);
				uint16_t cpy_height = (height > src->desc.height ? src->desc.height : height);

				for (uint16_t row = 0; row < cpy_height && row < cpy_height; row++)
					memcpy(buf + (row * width * bpp),
						current->buf + 4 + (row * src->desc.width * src->desc.bpp),
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
		else
			if (cmd == ffunc_destroy) {
				arcan_frameserver_free(src, false);
			}
			else
				; /* ignore ffunc_tick */

	return rv;
}

arcan_errc arcan_frameserver_audioframe(void* aobj, arcan_aobj_id id, unsigned buffer, void* tag)
{
	arcan_frameserver* src = (arcan_frameserver*) tag;
	struct arcan_aobj* aobjs = (struct arcan_aobj*) aobj;

	if (src->playstate == ARCAN_PLAYING && src->afq.front_cell) {
		alBufferData(buffer, AL_FORMAT_STEREO16, src->afq.front_cell->buf, src->afq.cell_size, src->desc.samplerate);
		arcan_framequeue_dequeue(&src->afq);
	} else if (src->playstate == ARCAN_PAUSED || /* pad with silence */
		src->playstate == ARCAN_SUSPENDED ||
		(src->afq.alive && src->afq.n_cells < ARCAN_FRAMESERVER_ACACHE_MINIMUM)) {
		char buf[4096] = {0};
		alBufferData(buffer, AL_FORMAT_STEREO16, buf, 4096, src->desc.samplerate);
		return ARCAN_OK;
	} else {
		arcan_event sevent = {.category = EVENT_AUDIO,
								.kind = EVENT_AUDIO_FRAMESERVER_TERMINATED,
								.data.audio.data = src,
								.data.audio.source = id
							};

		arcan_event_enqueue(&sevent);
		src->playstate = ARCAN_PAUSED;
	}

	return ARCAN_OK;
}

arcan_errc arcan_frameserver_playback(arcan_frameserver* src)
{
	if (!src)
		return ARCAN_ERRC_BAD_ARGUMENT;
	if (!src->desc.ready)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	src->base_time = SDL_GetTicks();
	src->playstate = ARCAN_PLAYING;
	arcan_audio_play(src->aid);

	return ARCAN_OK;
}

arcan_errc arcan_frameserver_pause(arcan_frameserver* src, bool syssusp)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (src) {
		src->playstate = (syssusp ? ARCAN_SUSPENDED : ARCAN_PAUSED);
		src->base_delta = SDL_GetTicks() - src->base_time;
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
		src->base_time = SDL_GetTicks() - src->base_delta;
		src->playstate = ARCAN_PLAYING;
		/*		arcan_audio_play(src->aid); */

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
	
	if (state && state->tag == ARCAN_TAG_MOVIE && ((arcan_frameserver*)state->ptr)->child_alive) {
		arcan_frameserver* movie = (arcan_frameserver*) state->ptr;
		
		struct frameserver_shmpage* shm = (struct frameserver_shmpage*) movie->shm.ptr;
		
		/* SDL mutex protects the shm- page for freeing etc. */
			if (shm->vready) {
				memcpy(dst, (void*)shm + shm->vbufofs, ntr);
				shm->vready = false;
				rv = ntr;
				arcan_sem_post(shm->vsyncp);
			}
			else
				errno = check_child(movie) == true ? EAGAIN : EINVAL;
			
		return rv;
	}

	errno = EINVAL;
	return rv;
}

/* audio on the other hand, is not set up to get a fixed frame-size,
 * so here we may need to buffer */
ssize_t arcan_frameserver_shmaudcb(int fd, void* dst, size_t ntr)
{
	vfunc_state* state = arcan_video_feedstate(fd);
	ssize_t rv = -1;

	if (state && state->tag == ARCAN_TAG_MOVIE && ((arcan_frameserver*)state->ptr)->child_alive) {
		arcan_frameserver* movie = (arcan_frameserver*) state->ptr;
		struct frameserver_shmpage* shm = (struct frameserver_shmpage*)movie->shm.ptr;

			if (shm->aready) {
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
					arcan_sem_post(shm->asyncp);
					rv = nc;
				}
			}
			else
				errno = check_child(movie) == true ? EAGAIN : EINVAL;
			
		return rv;
	}

	errno = EINVAL;
	return rv;
}
