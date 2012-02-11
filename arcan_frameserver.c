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
#include <strings.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_frameserver_backend_shmpage.h"

#define VID_FD 3
#define AUD_FD 4
#define CTRL_FD 5

#include "arcan_frameserver_decode.h"

FILE* logdev = NULL;
char* active_shmkey = NULL;
#define LOG(...) ( fprintf(logdev, __VA_ARGS__))

char* arcan_themepath = "";
char* arcan_resourcepath = "";
char* arcan_themename = "";
char* arcan_binpath = "";
char *arcan_libpath = "";

void arcan_frameserver_dropsemaphores(char* shmkey){
	if (NULL == shmkey) 
		return;
	
	char* work = strdup(shmkey);
		work[ strlen(work) - 1] = 'v';
		sem_unlink(work);
		work[strlen(work) - 1] = 'a';
		sem_unlink(work);
	free(work);	
}

/* based on the idea that init inherits an orphaned process */
static bool parent_alive()
{
	return getppid() != 1;
}

/* need the timeout to avoid a deadlock situation */
bool semcheck(sem_handle semaphore, unsigned mstimeout){
	struct timespec st = {.tv_sec  = 0, .tv_nsec = 1000000L}, rem; /* 5 ms */
	bool rv = true;
	int rc;

	do {
		rc = sem_trywait(semaphore);
		if (-1 == rc){
				if (errno == EINVAL){
					LOG("arcan_frameserver -- fatal error while waiting for semaphore\n");
					exit(1);
				}
			nanosleep(&st, &rem); /* don't care about precision here really */
		}
	} while ( (rv = parent_alive()) && rc != 0 );

	return rv;
}

static bool setup_shm_ipc(arcan_ffmpeg_context* dstctx, char* shmkey)
{
	/* step 1, use the fd (which in turn is set up by the parent to point to a mmaped "tempfile" */
	/* unsigned bufsize = sizeof(struct movie_shmpage) + 4 + (dstctx->width * dstctx->height * dstctx->bpp) + (dstctx->c_audio_buf); */
	unsigned bufsize = MAX_SHMSIZE;
	int fd = shm_open(shmkey, O_RDWR, 0700);
	char* semkeya = strdup(shmkey);
	char* semkeyv = strdup(shmkey);

	semkeyv[ strlen(shmkey) - 1 ] = 'v';
	semkeya[ strlen(shmkey) - 1 ] = 'a';
	
	if (-1 == fd) {
		LOG("arcan_frameserver() -- couldn't open keyfile (%s)\n", shmkey);
		return false;
	}

	LOG("arcan_frameserver() -- mapping shm, %i from %i\n", bufsize, fd);
	/* map up the shared key- file */
	char* buf = (char*) mmap(NULL,
							bufsize,
							PROT_READ | PROT_WRITE,
							MAP_SHARED,
							fd,
							0);
	
	if (buf == MAP_FAILED){
		LOG("arcan_frameserver() -- couldn't map shared memory keyfile.\n");
		close(fd);
		return false;
	}
	
	/* step 2, buffer all set-up, map it to the shared structure */
	dstctx->shared = (struct frameserver_shmpage*) buf;
	dstctx->shared->w = dstctx->width;
	dstctx->shared->h = dstctx->height;
	dstctx->shared->bpp = dstctx->bpp;
	dstctx->shared->vready = false;
	dstctx->shared->aready = false;
	dstctx->shared->vbufofs = sizeof(struct frameserver_shmpage);
	dstctx->shared->channels = dstctx->channels;
	dstctx->shared->frequency = dstctx->samplerate;
	dstctx->shared->abufofs = dstctx->shared->vbufofs + 4 + dstctx->width * dstctx->height * dstctx->bpp;
	dstctx->shared->abufbase = 0;
	dstctx->shared->vsyncc = sem_open(semkeyv, O_RDWR, 0700);
	dstctx->shared->asyncc = sem_open(semkeya, O_RDWR, 0700);
	active_shmkey = shmkey;
	LOG("arcan_frameserver() -- shmpage configured and filled.\n");
	
	return true;
}

void cleanshmkey(){
	LOG("arcan_frameserver() -- atexit( cleanshmkey )\n");
	arcan_frameserver_dropsemaphores(active_shmkey);
	shm_unlink(active_shmkey);
}

/* args accepted;
 * fname
 * keyfile
 * these are set-up by the parent before exec, so is the sempage.
 * the sem_t semaphores in the page are set up as vid(1), aud(0)
 * and we release vid (within a few seconds or get killed).
 */
 int main(int argc, char** argv)
{
	arcan_ffmpeg_context* vidctx;
	
	logdev = stderr;
	if (argc != 4){
		LOG("arcan_frameserver(), invalid arguments in exec()\n");
		return 1;
	}
	
    /* shut up */
	close(0);
	close(1);
	close(2);
	
	bool loop = strcmp(argv[3], "loop") == 0;
	vidctx = ffmpeg_preload(argv[1]);
	
	if (vidctx != NULL && setup_shm_ipc(vidctx, argv[2])){
		atexit(cleanshmkey);
		/* the better solution for this kind of frame-server,
		 * would be to build the arcan_framequeue.c in such a way that
		 * it can live in either the child or in the parent (transparently to the
		 * ffunc in arcan_frameserver), but not as beneficial for internal launch. */
		int semv, rv;

        vidctx->shared->resized = true;
		sem_post(vidctx->shared->vsyncc);
		
		LOG("arcan_frameserver() -- decoding\n");
		
		/* reuse the shmpage, anyhow, the main app should support
		 * relaunching the frameserver when looping to cover for
		 * memory leaks, crashes and other ffmpeg goodness */
		while (ffmpeg_decode(vidctx) && loop) {
			struct frameserver_shmpage* page = vidctx->shared;
			LOG("arcan_frameserver() -- decode finished, looping\n");
			ffmpeg_cleanup(vidctx);
			vidctx = ffmpeg_preload(argv[1]);

			/* sanity check, file might have changed between loads */
			if (!vidctx ||
			        vidctx->width != page->w ||
			        vidctx->height != page->h ||
			        vidctx->bpp != page->bpp)
				break;

			vidctx->shared = page;
		}
	}
	
	exit(0);
}
