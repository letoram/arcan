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
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/param.h>
#include <sys/mman.h>
#include <sys/stat.h>

#include <signal.h>
#include <errno.h>
#include <aio.h>

/* openAL */
#include <al.h>
#include <alc.h>

/* libSDL */
#include <SDL.h>
#include <SDL_types.h>

/* arcan */
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_framequeue.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_frameserver_backend.h"
#include "arcan_event.h"
#include "arcan_util.h"
#include "arcan_frameserver_backend_shmpage.h"

#define INCR(X, C) ( ( (X) = ( (X) + 1) % (C)) )

extern char* arcan_binpath;

arcan_errc arcan_frameserver_free(arcan_frameserver* src, bool loop)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (src) {
		src->playstate = loop ? ARCAN_PAUSED : ARCAN_PASSIVE;
		if (!loop)
			arcan_audio_stop(src->aid);
			
		if (src->vfq.alive)
			arcan_framequeue_free(&src->vfq);
		
		if (src->afq.alive)
			arcan_framequeue_free(&src->afq);

	/* might have died prematurely (framequeue cbs), no reason sending signal */
 		if (src->child_alive) {
			kill(src->child, SIGHUP);
			src->child_alive = false;
			waitpid(src->child, NULL, 0);
			src->child = 0;
		}
		
		struct movie_shmpage* shmpage = (struct movie_shmpage*) src->shm.ptr;
		
		if (shmpage){
			arcan_frameserver_dropsemaphores(src);
		
			if (src->shm.ptr && -1 == munmap((void*) shmpage, src->shm.shmsize))
				arcan_warning("BUG -- arcan_frameserver_free(), munmap failed: %s\n", strerror(errno));
			
			shm_unlink( src->shm.key );
			free(src->shm.key);
			
			src->shm.ptr = NULL;
		}
		
		rv = ARCAN_OK;
	}

	return rv;
}

bool check_child(arcan_frameserver* movie){
	int status, rv = EAGAIN;

	if (waitpid( movie->child, &status, WNOHANG ) == movie->child){
		rv = EINVAL;
		movie->child_alive = false;
	}
	
	return rv;
}

void arcan_frameserver_dbgdump(FILE* dst, arcan_frameserver* src){
	if (src){
		fprintf(dst, "movie source: %s\n"
		"mapped to: %i, %i\n"
		"video queue (%s): %i / %i\n"
		"audio queue (%s): %i / %i\n"
		"playstate: %i\n",
		src->shm.key,
		(int) src->vid, (int) src->aid,
		src->vfq.alive ? "alive" : "dead", src->vfq.c_cells, src->vfq.n_cells,
		src->afq.alive ? "alive" : "dead", src->afq.c_cells, src->afq.n_cells,
		src->playstate
		);
	}
	else
		fprintf(dst, "arcan_frameserver_dbgdump:\n(null)\n\n");
}



static const int8_t emptyvframe(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned mode, vfunc_state state){
	
	if (state.tag == ARCAN_TAG_MOVIE && state.ptr)
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

arcan_frameserver* arcan_frameserver_spawn_server(char* fname, bool extcc, bool loop, arcan_frameserver* res)
{
	img_cons cons = {.w = 32, .h = 32, .bpp = 4};
 	bool restart = res != NULL;
	size_t shmsize = MAX_SHMSIZE;
	struct frameserver_shmpage* shmpage;
	int shmfd = 0;
	char* shmkey = arcan_findshmkey(&shmfd, true);
/* findshmkey won't return until it gets a valid fd, shmkey is allocated and not freed there */
	
/* max videoframesize + DTS + structure + maxaudioframesize,
* start with max, then truncate down to whatever is actually used */
	ftruncate(shmfd, shmsize);
	shmpage = (void*) mmap(NULL, shmsize, PROT_READ | PROT_WRITE, MAP_SHARED, shmfd, 0);
	close(shmfd);
		
	if (MAP_FAILED == shmpage){
		arcan_warning("arcan_frameserver_spawn_server() -- couldn't allocate shmpage\n");
		goto error_cleanup;		
	}
		
	memset(shmpage, 0, MAX_SHMSIZE);
/* lock video, child will unlock or die trying, if this is a loop and the framequeues wasn't terminated,
 * this is a deadlock candidate */
	shmpage->parent = getpid();

/* old behavior was to wait for signal from frameserver, then allocate and return vid.
 * instead, we now follow the structure of launch_internal (in hopes that we can merge the codebase
 * for the two in the future) wherein we use a temporary CB that checks the state of the frameserver */
	pid_t child = fork();
	if (child) {
		arcan_frameserver_meta vinfo = {0};
		arcan_errc err;

		char* work = strdup(shmkey);
			work[strlen(work) - 1] = 'v';
			shmpage->vsyncp = sem_open(work, O_RDWR);
			work[strlen(work) - 1] = 'a';
			shmpage->asyncp = sem_open(work, O_RDWR);
		free(work);
		
		cons.w = shmpage->w;
		cons.h = shmpage->h;
		cons.bpp = shmpage->bpp;
		
	/* init- call (different from loop-exec as we need to 
	 * keep the vid / aud as they are external references into the scripted state-space */
		if (!restart) {
			res = (arcan_frameserver*) calloc(sizeof(arcan_frameserver), 1);
			vfunc_state state = {.tag = ARCAN_TAG_MOVIE, .ptr = res};
			res->source = strdup(fname);
            res->vid = arcan_video_addfobject((arcan_vfunc_cb) emptyvframe, state, cons, 0);
            res->aid = ARCAN_EID;
		} else { 
            /* revert back to empty vfunc? */
        }

		res->child_alive = true;
		res->desc = vinfo;
		res->child = child;
		res->loop = loop;
		res->desc.width = cons.w;
		res->desc.height = cons.h;
		res->desc.bpp = cons.bpp;
		res->shm.key = shmkey;
		res->shm.ptr = (void*) shmpage;
		res->shm.shmsize = shmsize;
		res->desc.ready = true;
	}
	else
		if (child == 0) {
			char* argv[5];
			char fn[MAXPATHLEN];
			char fn2[MAXPATHLEN];

			/* spawn the frameserver process,
			 * some IPC required;
			 * three pipes (vid, aud and control)
			 * usage pattern is pretty simple */
			argv[0] = arcan_binpath;
			argv[1] = (char*) fname;
			argv[2] = (char*) shmkey;
			argv[3] = loop ? "loop" : "";
			argv[4] = NULL;

			int rv = execv(arcan_binpath, argv);
			arcan_fatal("FATAL, arcan_frameserver_spawn_server(), couldn't spawn frameserver (%s) for %s, %s. Reason: %s\n", arcan_binpath, fname, shmkey, strerror(errno));
			exit(1);
		}
	return res;

error_cleanup:
	arcan_frameserver_dropsemaphores_keyed(shmkey);
	shm_unlink(shmkey);
	free(shmkey);

	return NULL;
}
