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

#include <stdlib.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdbool.h>
#include <signal.h>
#include <poll.h>
#include <limits.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <unistd.h>

#include <errno.h>

#include <SDL.h>
#include <SDL_opengl.h>
#include <SDL_syswm.h>

#include <al.h>

#include <assert.h>
#include <errno.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_event.h"
#include "arcan_framequeue.h"
#include "arcan_target_const.h"
#include "arcan_frameserver_backend.h"
#include "arcan_frameserver_backend_shmpage.h"
#include "arcan_target_launcher.h"

extern bool fullscreen;

int arcan_target_launch_external(const char* fname, char** argv)
{
	if (arcan_video_prepare_external() == false){
		arcan_warning("Warning, arcan_target_launch_external(), couldn't push current context, aborting launch.\n");
		return 0;
	}
	
	pid_t child = fork();
	unsigned long ticks = SDL_GetTicks();

	if (child) {
		int stat_loc;

			while (-1 == waitpid(child, &stat_loc, 0)){
				if (errno != EINVAL) 
					break;
			}
		arcan_video_restore_external();

		return SDL_GetTicks() - ticks;
	}
	else {
		execv(fname, argv);
		_exit(1);
	}
}

int arcan_target_clean_internal(arcan_launchtarget* tgt)
{
	if (!tgt || tgt->source.child <= 0)
		return -1;

/* send a killcommand, wait n seconds and get the child a chance
 * to clean up "cleanly"? */
	
	kill(tgt->source.child, SIGKILL);
	waitpid(tgt->source.child, NULL, 0);

	arcan_frameserver_dropsemaphores(&tgt->source);
	shm_unlink(tgt->source.shm.key);
	close(tgt->ifd);

	return 0;
}

static arcan_errc again_feed(float gain, void* tag)
{
	arcan_launchtarget* tgt = (arcan_launchtarget*) tag;
	arcan_errc rv = ARCAN_OK;

	if (tgt) {
		char buf[ sizeof(float) + 2] = {TF_AGAIN, sizeof(float)};
		memcpy(&buf[2], &gain, sizeof(float));
		write(tgt->ifd, buf, sizeof(buf));
	}

	return rv;
}

arcan_errc arcan_target_inject_event(arcan_launchtarget* tgt, arcan_event ev)
{
	arcan_errc rc = ARCAN_ERRC_BAD_ARGUMENT;

	if (tgt) {
		char buf[256] = {TF_EVENT, 0};
		char* work = buf;
		int bufused = arcan_event_tobytebuf(buf + 2, sizeof(buf) - 2, &ev);
		
		if (-1 != bufused){
			buf[1] = bufused;
			bufused += 2; 
			
			while( bufused ){
				ssize_t nw = write(tgt->ifd, work, bufused);
				if (-1 == nw)
					if (errno == EAGAIN)
						continue;
					else
						return ARCAN_ERRC_EOF;

				bufused -= nw;
				work += nw;
			}	
			
			rc = ARCAN_OK;
		}
	}

	return rc;
}

static const int8_t internal_empty(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned mode, vfunc_state state){
	
	if (state.tag == ARCAN_TAG_TARGET && state.ptr)
		switch (cmd){
			case ffunc_tick:
				arcan_target_tick_control( (arcan_launchtarget*) state.ptr);
			break;
			
			case ffunc_destroy:
				arcan_target_clean_internal( (arcan_launchtarget*) state.ptr);
			break;
			
			default:
			break;
		}

	return 0;
}

static int8_t internal_videoframe(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned mode, vfunc_state vstate)
{
	int8_t rv = 0;
	if (vstate.tag != ARCAN_TAG_TARGET || !vstate.ptr)
		return rv;

	arcan_launchtarget* tgt = (arcan_launchtarget*) vstate.ptr;
	struct frameserver_shmpage* shmpage = (struct frameserver_shmpage*) tgt->source.shm.ptr;
	
	/* should have a special framequeue mode which supports more direct form of rendering */
	switch (cmd){
		case ffunc_poll:
			return shmpage->vready;
		break;
        
        case ffunc_tick:
            break;
		
		case ffunc_destroy:
			arcan_target_clean_internal( tgt );
		break;
		
		case ffunc_render:
			if (width != shmpage->w || 
				height != shmpage->h) {
					uint16_t cpy_width  = (width > shmpage->w ? shmpage->w : width);
					uint16_t cpy_height = (height > shmpage->h ? shmpage->h : height);
					assert(bpp == shmpage->bpp);
					
					for (uint16_t row = 0; row < cpy_height && row < cpy_height; row++)
						memcpy(buf + (row * width * bpp),
						       ((char*)shmpage + shmpage->vbufofs) + (row * shmpage->w * shmpage->bpp),
						       cpy_width * bpp
						);
						
					rv = FFUNC_RV_COPIED; 
			}
			else {  /* need to reduce all those copies if at all possible .. */
				glBindTexture(GL_TEXTURE_2D, mode);
				glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height, GL_PIXEL_FORMAT, GL_UNSIGNED_BYTE, (char*)shmpage + shmpage->vbufofs);

				rv = FFUNC_RV_COPIED;
			}
			
			shmpage->vready = false;
			sem_post( shmpage->vsyncp );
		break;
    }

	return rv;
}

void arcan_target_suspend_internal(arcan_launchtarget* tgt)
{
	char wbuf[2] = {TF_SLEEP, sizeof(wbuf)/sizeof(wbuf[0]) - 2};
	write(tgt->ifd, wbuf, sizeof(wbuf));
}

void arcan_target_resume_internal(arcan_launchtarget* tgt)
{
	char wbuf[2] = {TF_WAKE, sizeof(wbuf)/sizeof(wbuf[0]) - 2};
	write(tgt->ifd, wbuf, sizeof(wbuf));
}


void arcan_target_tick_control(arcan_launchtarget* tgt)
{
	/* check if child is alive */
	/* check if we're resized */
	if (tgt->source.shm.ptr){
		struct frameserver_shmpage* shmpage = (struct frameserver_shmpage*) tgt->source.shm.ptr;

		if (shmpage->resized){
			vfunc_state cstate = *arcan_video_feedstate(tgt->source.vid);
			img_cons cons = {.w = shmpage->w, .h = shmpage->h, .bpp = shmpage->bpp};
			arcan_framequeue_free(&tgt->source.vfq);
			shmpage->resized = false;
			arcan_video_resizefeed(tgt->source.vid, cons, shmpage->glsource);
			arcan_video_alterfeed(tgt->source.vid, (arcan_vfunc_cb) internal_videoframe, cstate);
		}
		
		int status;
		if (waitpid( tgt->source.child, &status, WNOHANG ) == tgt->source.child){
			tgt->source.child_alive = false;
			arcan_warning("arcan_target_tick_control() -- internal launch died\n");
		}
	}
}

/* note for debugging internal launch (particularly the hijack lib)
 * (linux only)
 * gdb, break just before the fork
 * set follow-fork-mode child, add a breakpoint to the yet unresolved hijack_init symbol
 * and move on. 
 * for other platforms, patch the hijacklib loader to set an infinite while loop on a volatile flag,
 * break the process and manually change the memory of the flag */
extern char* arcan_libpath;
arcan_launchtarget* arcan_target_launch_internal(const char* fname, char** argv,
        enum intercept_mechanism mechanism,
        enum intercept_mode intercept,
        enum communication_mode comm)
{
	if (arcan_libpath == NULL){
		arcan_warning("Warning: arcan_target_launch_internal() called without a proper hijack lib.\n");
		return NULL;
	}
	
	int i[2];
	int shmfd = 0;
	arcan_launchtarget* res = (arcan_launchtarget*) calloc(sizeof(arcan_launchtarget), 1);
	char* shmkey = arcan_findshmkey(&shmfd, true);
	
/*	char** curr = argv;
	while(*curr)
		printf("\t%s\n", *curr++); */
	
	ftruncate(shmfd, MAX_SHMSIZE);
	struct frameserver_shmpage* shmpage = (void*) mmap(NULL, MAX_SHMSIZE, PROT_READ | PROT_WRITE, MAP_SHARED, shmfd, 0);
	close(shmfd);

	if (MAP_FAILED == shmpage){
		arcan_warning("arcan_frameserver_spawn_server() -- couldn't allocate shmpage\n");
		goto cleanup;
	}
	
	shmpage->parent = getpid();
	pipe(i);
	fcntl(i[1], F_SETFL, O_NONBLOCK);

	if ( (res->source.child = fork() ) > 0) {
		arcan_errc err;
		img_cons empty = {.w = 32, .h = 32, .bpp = 4};
		vfunc_state state = {
			.tag = ARCAN_TAG_TARGET,
			.ptr = res
		};
		
		char* work = strdup(shmkey);
			work[strlen(work) - 1] = 'v';
			shmpage->vsyncp = sem_open(work, O_RDWR);
			sem_post(shmpage->vsyncp);
		free(work);
		
	/* tick() checks for a video-init. When one happens, the fobject- is resized
	 * and a new ffunc is set, framequeue is not used as such as we don't need / want
	 * intermediate buffering */
		res->ifd = i[1];
		res->comm = comm;
		res->source.vid = arcan_video_addfobject(internal_empty, state, empty, 0);
		res->source.aid = arcan_audio_proxy(again_feed, res);
		res->source.shm.ptr = (void*) shmpage;
		res->source.shm.key = shmkey;
		res->source.shm.shmsize = MAX_SHMSIZE;
		res->source.loop = false;
		
		return res;
	}
	else {
		char shmsize[ 39 ] = {0};
		snprintf(shmsize, 38, "%ui", (unsigned int) MAX_SHMSIZE);
		
		setenv("LD_PRELOAD", arcan_libpath, 1); /* ignored by OSX */
		setenv("DYLD_INSERT_LIBRARIES", arcan_libpath, 1); /* ignored by other NIXes */
		setenv("ARCAN_SHMKEY", shmkey, 1);
		setenv("ARCAN_SHMSIZE", shmsize, 1);

		dup2(i[0], COMM_FD);
		fcntl(COMM_FD, F_SETFL, O_NONBLOCK);

		execv(fname, argv);
		arcan_warning("arcan_target_launch_internal() child : couldn't execute %s\n", fname);
		exit(1);
	}
	
cleanup:
	if (res)
		arcan_frameserver_dropsemaphores(&res->source);
	shm_unlink(shmkey);
	free(shmkey);
	free(res);

	return NULL;
}
