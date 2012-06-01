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

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <strings.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>


#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"
#include "arcan_frameserver.h"
#include "../arcan_frameserver_shmpage.h"
#include "arcan_frameserver_libretro.h"

#define VID_FD 3
#define AUD_FD 4
#define CTRL_FD 5

#include "arcan_frameserver_decode.h"

FILE* logdev = NULL;
const char* active_shmkey = NULL;

char* arcan_themepath = "";
char* arcan_resourcepath = "";
char* arcan_themename = "";
char* arcan_binpath = "";
char *arcan_libpath = "";

static void drop_semaphores(const char* shmkey){
	if (NULL == shmkey) 
		return;
	
	char* work = strdup(shmkey);
		work[ strlen(work) - 1] = 'v';
		sem_unlink(work);
		work[strlen(work) - 1] = 'a';
		sem_unlink(work);
		work[strlen(work) - 1] = 'e';
		sem_unlink(work);
	free(work);	
}

/* based on the idea that init inherits an orphaned process */
static bool parent_alive()
{
	return getppid() != 1;
}

/* need the timeout to avoid a deadlock situation */
bool frameserver_semcheck(sem_handle semaphore, unsigned mstimeout){
	struct timespec st = {.tv_sec  = 0, .tv_nsec = 1000000L}, rem; 
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

static void cleanshmkey(){
	LOG("arcan_frameserver() -- atexit( cleanshmkey )\n");
	drop_semaphores(active_shmkey);
	shm_unlink(active_shmkey);
}

struct frameserver_shmcont frameserver_getshm(const char* shmkey, unsigned width, unsigned height, unsigned bpp, unsigned nchan, unsigned freq){
/* step 1, use the fd (which in turn is set up by the parent to point to a mmaped "tempfile" */
	struct frameserver_shmcont res = {0};
	
	unsigned bufsize = MAX_SHMSIZE;
	int fd = shm_open(shmkey, O_RDWR, 0700);

	if (-1 == fd) {
		LOG("arcan_frameserver() -- couldn't open keyfile (%s)\n", shmkey);
		return res;
	}

	LOG("arcan_frameserver() -- mapping shm, %i from %i\n", bufsize, fd);
	/* map up the shared key- file */
	res.addr = (struct frameserver_shmpage*) mmap(NULL,
		bufsize,
		PROT_READ | PROT_WRITE,
		MAP_SHARED,
		fd,
	0);
	
	if (res.addr == MAP_FAILED){
		LOG("arcan_frameserver() -- couldn't map addr memory keyfile.\n");
		close(fd);
		return res;
	}

/* step 2, semaphore handles */
	char* work = strdup(shmkey);
	work[strlen(work) - 1] = 'v';
	res.vsem = sem_open(work, 0);
	work[strlen(work) - 1] = 'a';
	res.asem = sem_open(work, 0);
	work[strlen(work) - 1] = 'e';
	res.esem = sem_open(work, 0);	
	free(work);
	
	if (res.asem == 0x0 ||
		res.esem == 0x0 ||
		res.vsem == 0x0 ){
		LOG("arcan_frameserver() -- couldn't map semaphores, giving up.\n");
		return res;  
	}

/* step 2, buffer all set-up, map it to the addr structure */
	res.addr->w = width;
	res.addr->h = height;
	res.addr->bpp = bpp;
	res.addr->vready = false;
	res.addr->aready = false;
	res.addr->vbufofs = sizeof(struct frameserver_shmpage);
	res.addr->channels = nchan;
	res.addr->frequency = freq;

/* ensure vbufofs is aligned, and the rest should follow (bpp forced to 4) */
	res.addr->abufofs = res.addr->vbufofs + (res.addr->w* res.addr->h* res.addr->bpp);
	res.addr->abufbase = 0;

	active_shmkey = shmkey;
	atexit(cleanshmkey);
	LOG("arcan_frameserver() -- shmpage configured and filled.\n");

	return res;
}


/* Stream-server is used as a 'reverse' movie mode,
 * i.e. it is the frameserver that reads from the shmpage,
 * feeding whatever comes to ffmpeg */
void mode_streamserv(char* resource, char* keyfile)
{
	/* incomplete, first version should just take
	 * a vid (so buffercopy or readback) or an aggregate (render vids to fbo, readback fbo)
	 * we can't treat this the same as vid), encode and store in a file.
	 * 
	 * next step would be to compare this with a more established straming protocol 
	 */
}

void mode_video(char* resource, const char* keyfile)
{
	arcan_ffmpeg_context* vidctx = ffmpeg_preload(resource);
	if (!vidctx) return;

	LOG("video(%s)\n", resource);
	struct frameserver_shmcont shms = frameserver_getshm(keyfile, vidctx->width, vidctx->height, vidctx->bpp, vidctx->channels, vidctx->samplerate);
	vidctx->shared = shms.addr;
	vidctx->async  = shms.asem;
	vidctx->vsync  = shms.vsem;
	vidctx->esync  = shms.esem;
	
	if (vidctx->shared){
		int semv, rv;
		vidctx->shared->resized = true;
		sem_post(vidctx->vsync);
		
		LOG("arcan_frameserver(video) -- decoding\n");
		
/* reuse the shmpage, anyhow, the main app should support
 * relaunching the frameserver when looping to cover for
 * memory leaks, crashes and other ffmpeg goodness */
		while (ffmpeg_decode(vidctx) && vidctx->shared->loop) {
			struct frameserver_shmpage* page = vidctx->shared;
			LOG("arcan_frameserver(video) -- decode finished, looping\n");
			ffmpeg_cleanup(vidctx);
			vidctx = ffmpeg_preload(resource);

			/* sanity check, file might have changed between loads */
			if (!vidctx ||
				vidctx->width != page->w ||
				vidctx->height != page->h ||
				vidctx->bpp != page->bpp)
			break;

			vidctx->shared = page;
			vidctx->async = shms.asem;
			vidctx->vsync = shms.vsem;
			vidctx->esync = shms.esem;
		}
	}
}

/* args accepted;
 * fname
 * keyfile
 * these are set-up by the parent before exec, so is the sempage.
 * all of these are derived from the keyfile (last char replaced with v, a, e for sems) 
 * and we release vid (within a few seconds or get killed).
 */
 int main(int argc, char** argv)
{
	char* resource = argv[1];
	char* keyfile  = argv[2];
	char* fsrvmode = argv[3];
	
	logdev = stderr;
	if (argc != 4 || !resource || !keyfile || !fsrvmode){
		LOG("arcan_frameserver(), invalid arguments in exec()\n");
		return 1;
	}

/*
	close(0);
	close(1);
	close(2);
*/
	LOG("frameserver with %s\n", fsrvmode);

	if (strcmp(fsrvmode, "movie") == 0 || strcmp(fsrvmode, "audio") == 0)
		mode_video(resource, keyfile);
	
	else if (strcmp(fsrvmode, "libretro") == 0)
		arcan_frameserver_libretro_run(resource, keyfile);
	
	else if (strcmp(fsrvmode, "streamserve") == 0)
		mode_streamserv(resource, keyfile);
	
	else;

	return 0;
}
