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
#include <sys/socket.h>
#include <sys/uio.h>
#include <sys/time.h>
#include <fcntl.h>
#include <time.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"
#include "arcan_frameserver.h"
#include "../arcan_frameserver_shmpage.h"
#include "arcan_frameserver_libretro.h"
#include "arcan_frameserver_decode.h"
#include "arcan_frameserver_encode.h"

FILE* logdev = NULL;
int sockin_fd = -1;

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
		LOG("arcan_frameserver(get_rawfile) mmap (%s) failed (fd: %d, size: %zd)\n", fname, fd, (ssize_t) filedat.st_size);
		close(fd);
		return NULL;
	}

	*dstsize = filedat.st_size;
	return buf;
}

void* frameserver_getrawfile_handle(file_handle fd, ssize_t* dstsize)
{
	struct stat filedat;
	void* rv = NULL;
	*dstsize = -1;
	
	if (-1 == fstat(fd, &filedat)){
		LOG("arcan_frameserver(get_rawfile) stat (%d) failed, reason: %d,%s\n", fd, errno, strerror(errno));
		goto error;
	}
	
	void* buf = mmap(NULL, filedat.st_size, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
	if (buf == MAP_FAILED){
		LOG("arcan_frameserver(get_rawfile) mmap failed (fd: %d, size: %zd)\n", fd, (ssize_t) filedat.st_size);
		goto error;
	}

	rv = buf;
	*dstsize = filedat.st_size;

error:
	return rv;
}

bool frameserver_dumprawfile_handle(const void* const data, size_t sz_data, file_handle dst)
{
	bool rv = false;
	
	if (dst != BADFD)
	{
		off_t ofs = 0;
		ssize_t nw;

		while ( ofs != sz_data && (
			(nw = write(dst, ((char*) data) + ofs, sz_data - ofs)) >= 0, ofs += nw)
			|| errno == EAGAIN || errno == EINTR);
		
		if (nw == -1)
			LOG("arcan_frameserver(dumprawfile) -- write failed (%d), reason: %s\n", errno, strerror(errno));
		
		close(dst);
	}
	 else
		 LOG("arcan_frameserver(dumprawfile) -- request to dump to invalid file handle ignored.\n");
	
	return rv;
}

long long int frameserver_timemillis()
{

	struct timespec tp;
#if _POSIX_TIMERS > 0
	clock_gettime(CLOCK_MONOTONIC, &tp);
#else
	struct timeval tv;
	gettimeofday(&tv, NULL);
	tp.tv_sec = tp.tv_sec;
	tp.tv_nsec = tv.tv_usec * 1000;
#endif

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

/* inev is part of the argument in order for Win32 and others that can pass handles in a 
 * less hackish way to do so by reusing symbols and cutting down on defines */
file_handle frameserver_readhandle(arcan_event* inev)
{
	int rv = -1;
	
/* some would call this black magic. They'd be right. */
	if (sockin_fd != -1){
		char empty;
		
		struct cmsgbuf {
			struct cmsghdr hdr;
			int fd[1];
		} msgbuf;
		
		struct iovec nothing_ptr = {
			.iov_base = &empty,
			.iov_len = 1
		};
		
		struct msghdr msg = {
			.msg_name = NULL,
			.msg_namelen = 0,
			.msg_iov = &nothing_ptr,
			.msg_iovlen = 1,
			.msg_flags = 0,
			.msg_control = &msgbuf,
			.msg_controllen = sizeof(struct cmsghdr) + sizeof(int)
		};
		
		struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
		cmsg->cmsg_len = msg.msg_controllen;
		cmsg->cmsg_level = SOL_SOCKET;
		cmsg->cmsg_type  = SCM_RIGHTS;
		((int*) CMSG_DATA(cmsg))[0] = -1;
		
		if (recvmsg(sockin_fd, &msg, 0) >= 0)
			rv = msgbuf.fd[0];
	}
	
	return rv;
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
#ifdef _DEBUG
		printf("arcan_frameserver(debug) resource keyfile fsrvmode\n");
#else
		printf("arcan_frameserver - Invalid arguments (shouldn't be launched from the commandline).\n");
#endif

		return 1;
	}

/* this is not passed as a command-line argument in order to reuse code with arcan_target where we don't 
 * have control over argv. furthermore, it requires the FD to be valid from an environment perspective (already open socket that
 * can pass file-descriptors */
	if (getenv("ARCAN_SOCKIN_FD")){
		sockin_fd = strtol( getenv("ARCAN_SOCKIN_FD"), NULL, 10 );
	}
	
/* set this env whenever you want to step through the frameserver as launched from the parent */
	if (getenv("ARCAN_FRAMESERVER_DEBUGSTALL")){
		arcan_warning("-- frameserver stall activated, won't continue without gdb intervention. Pid: (%d)\n", getpid());
		volatile int a = 0;
		while (a == 0);
	}
	
/* to ease debugging, allow the frameserver to be launched without a parent we 
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
	LOG("mode: %s", fsrvmode);
	
	if (strcmp(fsrvmode, "movie") == 0 || strcmp(fsrvmode, "audio") == 0)
		arcan_frameserver_ffmpeg_run(resource, keyfile);
	
	else if (strcmp(fsrvmode, "libretro") == 0)
		arcan_frameserver_libretro_run(resource, keyfile);
	
	else if (strcmp(fsrvmode, "record") == 0)
		arcan_frameserver_ffmpeg_encode(resource, keyfile);
	
	else;

	return 0;
}
