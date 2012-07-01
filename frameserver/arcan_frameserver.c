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
#include <time.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"
#include "arcan_frameserver.h"
#include "../arcan_frameserver_shmpage.h"
#include "arcan_frameserver_libretro.h"
#include "arcan_frameserver_decode.h"

FILE* logdev = NULL;

/* arcan_general functions assumes these are valid for searchpaths etc.
 * since we want to use some of those functions, we need a linkerhack or two */

void* frameserver_getrawfile(const char* fname, ssize_t* dstsize)
{
	int fd;
	struct stat filedat;
	*dstsize = -1;
	
	if (-1 == stat(fname, &filedat)){
		LOG("arcan_frameserver(get_rawfile) stat (%s) failed, reason: %d,%s\n", fname, errno, strerror(errno));
		return NULL;
	}
	
	if (-1 == (fd = open(fname, O_RDWR)))
	{
		LOG("arcan_frameserver(get_rawfile) open (%s) failed, reason: %d:%s\n", fname, errno, strerror(errno));
		return NULL;
	}
	
	void* buf = mmap(NULL, filedat.st_size, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
	if (buf == MAP_FAILED){
		LOG("arcan_frameserver(get_rawfile) mmap (%s) failed (fd: %d, size: %zu)\n", fname, fd, filedat.st_size);
		close(fd);
		return NULL;
	}

	*dstsize = filedat.st_size;
	return buf;
}

unsigned long long int frameserver_timemillis()
{
	struct timespec tp;
	clock_gettime(CLOCK_MONOTONIC, &tp);
	return (tp.tv_sec * 1000) + (tp.tv_nsec / 1000000);
}

void frameserver_delay(unsigned long val)
{
	struct timespec req, rem;
	req.tv_sec = floor(val / 1000);
	val -= req.tv_sec * 1000;
	req.tv_nsec = val * 1000000;
	
	while( nanosleep(&req, &rem) == -1 ){
/* sweeping EINTR introduces an error rate that can grow large,
 * check if the remaining time is less than a threshold */
		if (errno == EINTR) {
			req = rem;
			if (rem.tv_sec * 1000 + (1 + req.tv_nsec) / 1000000 < 4)
				break;
		} 
	}
}

/* linker hack */
void arcan_frameserver_free(void* dontuse){}

/* Stream-server is used as a 'reverse' movie mode,
 * i.e. it is the frameserver that reads from the shmpage,
 * feeding whatever comes to ffmpeg */
static void mode_streamserv(char* resource, char* keyfile)
{
	/* incomplete, first version should just take
	 * a vid (so buffercopy or readback) or an aggregate (render vids to fbo, readback fbo)
	 * we can't treat this the same as vid), encode and store in a file.
	 * 
	 * next step would be to compare this with a more established straming protocol 
	 */
}

#ifdef _DEBUG
static void arcan_simulator(struct frameserver_shmcont* shm){
	arcan_evctx inevq, outevq;
	frameserver_shmpage_setevqs(shm->addr, shm->esem, &inevq, &outevq, true /*parent*/ );

	while( getppid() != 1 ){
		if (shm->addr->vready){
			shm->addr->vready = false;
			sem_post(shm->vsem);
		}
		
		if (shm->addr->aready){
			shm->addr->aready = false;
			sem_post(shm->asem);
		}
		
		unsigned evc = 0;		
		while ( arcan_event_poll( &inevq ) != NULL ) evc++;

/* if nothing has happened, the frameserver is probably not set up right yet, sleep a little */
		struct timespec tv = {.tv_sec = 0, .tv_nsec = 10000000L};
		if (!(shm->addr->vready || shm->addr->aready || evc > 0))
			nanosleep(&tv, NULL);
	}
}

static char* launch_debugparent()
{
	int shmfd = -1;
	struct frameserver_shmcont cont;

/* prealloc shmpage */
	char* key = arcan_findshmkey(&shmfd, true);
	if (!key)
		return NULL;
	
	ftruncate(shmfd, MAX_SHMSIZE);

/* set the size, fork a child (mimicking frameserver parent behavior)
 * now we can break / step the frameserver with correct synching behavior
 * without the complexity of the main program */

	return key;
	
	if ( fork() == 0){
		struct frameserver_shmcont cont = frameserver_getshm(key, false);

		if (cont.addr)
			arcan_simulator(&cont);

		arcan_warning("frameserver_debugparent() -- shutting down.\n");
		exit(1);
	}
	else{
		sleep(1); /* make sure the parent has been able to setup keys by now so we can unlink */
		return key;
	}
}
#endif

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
#ifdef _DEBUG
		printf("arcan_frameserver(debug) resource keyfile fsrvmode\n");
#else
		printf(stdout, "arcan_frameserver - Invalid arguments (shouldn't be launched from the commandline).\n");
#endif

		return 1;
	}

/* set this env whenever you want to step through the frameserver as launched from the parent */
	if (getenv("ARCAN_FRAMESERVER_DEBUGSTALL")){
		arcan_warning("-- frameserver stall activated, won't continue without gdb intervention. Pid: (%d)\n", getpid());
		volatile int a = 0;
		while (a == 0);
	}
	
/* to ease debugging, allow the frameserver to be launched without a parent of we 
 * pass debug: to modestr, so setup shmpage, fork a lightweight parent, ..*/
#ifdef _DEBUG
	char* modeprefix = NULL;
	char* splitp = strchr(fsrvmode, ':');
	if (splitp){
		*splitp = '\0';
		modeprefix = fsrvmode;
		fsrvmode = splitp+1;
		
		if (strcmp(modeprefix, "debug") == 0){
			keyfile = launch_debugparent();
			if (keyfile)
				arcan_warning("frameserver_debug() -- mapped to %s\n", keyfile);
			else
				arcan_fatal("frameserver_debug() -- couldn't get shmkey\n");
		}
	}
#endif
/*
	close(0);
	close(1);
	close(2);
*/
	if (strcmp(fsrvmode, "movie") == 0 || strcmp(fsrvmode, "audio") == 0)
		arcan_frameserver_ffmpeg_run(resource, keyfile);
	
	else if (strcmp(fsrvmode, "libretro") == 0)
		arcan_frameserver_libretro_run(resource, keyfile);
	
	else if (strcmp(fsrvmode, "streamserve") == 0)
		mode_streamserv(resource, keyfile);
	
	else;

	return 0;
}
