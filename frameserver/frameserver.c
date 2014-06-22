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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor,Boston, MA 02110-1301,USA.
 *
 */

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <assert.h>

#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <sys/time.h>
#include <sys/signal.h>
#include <fcntl.h>
#include <time.h>
#include <dlfcn.h>

#include <arcan_shmif.h> 
#include "frameserver.h"

void arcan_frameserver_decode_run(
	const char* resource, const char* keyfile);
void arcan_frameserver_libretro_run(
	const char* resource, const char* keyfile);
void arcan_frameserver_encode_run(
	const char* resource, const char* keyfile);
void arcan_frameserver_net_run(
	const char* resource, const char* keyfile);
void arcan_frameserver_avfeed_run(
	const char* resource, const char* keyfile);
void arcan_frameserver_terminal_run(
	const char* resource, const char* keyfile);

/* 
 * arcan_general functions assumes these are valid for searchpaths etc.
 * since we want to use some of those functions, we need a linkerhack or two.
 * These should be refactored to use the platform* functions
 */
void* frameserver_getrawfile(const char* fname, ssize_t* dstsize)
{
	int fd;
	struct stat filedat;
	*dstsize = -1;

	if (-1 == stat(fname, &filedat)){
		LOG("arcan_frameserver(get_rawfile) stat (%s) failed, reason: %d,%s\n", 
			fname, errno, strerror(errno));
		return NULL;
	}
	
	if (-1 == (fd = open(fname, O_RDONLY)))
	{
		LOG("arcan_frameserver(get_rawfile) open (%s) failed, reason: %d:%s\n", 
			fname, errno, strerror(errno));
		return NULL;
	}
	
	void* buf = mmap(NULL, filedat.st_size, PROT_READ | 
		PROT_WRITE, MAP_PRIVATE, fd, 0);

	if (buf == MAP_FAILED){
		LOG("arcan_frameserver(get_rawfile) mmap (%s) failed"
			" (fd: %d, size: %zd)\n", fname, fd, (ssize_t) filedat.st_size);
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
		LOG("arcan_frameserver(get_rawfile) stat (%d) failed, reason: %d,%s\n", 
			fd, errno, strerror(errno));
		goto error;
	}
	
	void* buf = mmap(NULL, filedat.st_size, PROT_READ | 
		PROT_WRITE, MAP_PRIVATE, fd, 0);
	if (buf == MAP_FAILED){
		LOG("arcan_frameserver(get_rawfile) mmap failed (fd: %d, size: %zd)\n", 
			fd, (ssize_t) filedat.st_size);
		goto error;
	}

	rv = buf;
	*dstsize = filedat.st_size;

error:
	return rv;
}

bool frameserver_dumprawfile_handle(const void* const data, size_t sz_data, 
	file_handle dst, bool finalize)
{
	bool rv = false;
	
	if (dst != BADFD)
	{
		off_t ofs = 0;
		ssize_t nw;

		while ( ofs != sz_data){
			nw = write(dst, ((char*) data) + ofs, sz_data - ofs);
			if (-1 == nw)
				switch (errno){
				case EAGAIN: continue;
				case EINTR: continue;
				default:
					LOG("arcan_frameserver(dumprawfile) -- write failed (%d),"
					"	reason: %s\n", errno, strerror(errno));
					goto out;
			}

			ofs += nw;
		}
		rv = true;
		
		out:
		if (finalize)
			close(dst);
	}
	 else
		 LOG("arcan_frameserver(dumprawfile) -- request to dump to invalid "
			"file handle ignored, no output set by parent.\n");
	
	return rv;
}

/* inev is part of the argument in order for Win32 and others that can 
 * pass handles in a less hackish way to do so by reusing symbols and
 * cutting down on defines */
int frameserver_readhandle(arcan_event* inev)
{
	static int sockin_fd = -1;
	if (sockin_fd == -1){
		char* sockin = getenv("ARCAN_SOCKIN_FD");
		if (sockin)
			sockin_fd = strtoul(sockin, NULL, 10);
	}

	return arcan_fetchhandle(sockin_fd);
}

/* set currently active library for loading symbols */
static void* lastlib, (* globallib);

bool frameserver_loadlib(const char* const lib)
{
	lastlib = dlopen(lib, RTLD_LAZY);
	if (!globallib)
		globallib = dlopen(NULL, RTLD_LAZY);

	return lastlib != NULL;
}

void* frameserver_requirefun(const char* const sym, bool module)
{
/* not very relevant here, but proper form is dlerror() */
	if (!sym)
		return NULL;

	if (module){
		if (lastlib)
			return dlsym(lastlib, sym);
		else
			return NULL;
	}

	return dlsym(lastlib, sym);
}

static void toggle_logdev(const char* prefix)
{
	const char* const logdir = getenv("ARCAN_FRAMESERVER_LOGDIR");
	if (!prefix)
		return;

	if (logdir){
		char timeb[16];
		time_t t = time(NULL);
		struct tm* basetime = localtime(&t);
		strftime(timeb, sizeof(timeb)-1, "%y%m%d_%H%M", basetime);

		size_t logbuf_sz = strlen(logdir) + 
			sizeof("/fsrv__yymmddhhss.txt") + strlen(prefix);
		char* logbuf = malloc(logbuf_sz + 1);

		snprintf(logbuf, logbuf_sz+1, "%s/fsrv_%s_%s.txt", logdir, prefix, timeb);
		if (!freopen(logbuf, "a", stderr)){
			stderr = fopen("/dev/null", "a");
			if (!stderr)
				stderr = stdout;
		}
	}
}

/*
 * Splitmode warrant some explaining,
 * in the mode we use the frameserver binary as a chainloader;
 * we select a different binary (our own name + _mode and
 * just pass the environment onwards. We also get the benefit 
 * of testing the main process resolve against double forking.
 *
 * This is done to limit the effect of some libraries having unreasonable
 * (possible even non-ASLRable) requirements, doing multi-threading,
 * installing signal handlers and what not in .ctor/.init
 * and we like to limit that contamination (the herpes stops here...)
 *
 * This is mostly implemented in the build system;
 * a main arcan_frameserver binary is produced with ARCAN_FRAMESERVER_SPLITMODE
 * defined, and n' different others with the _mode suffix attached and 
 * the unused subsystems won't be #defined in.
 *
 * The intent is also to implement sandboxing setup and loading here,
 * one part as a package format (FAP) with FUSE + chroot,
 * another using local sandboxing options (seccomp and capsicum)
 */
static void dumpargs(int argc, char** argv)
{
	printf("invalid number of arguments (%d):\n", argc);
 	printf("[1 mode] : %s\n", argc > 1 && argv[1] ? argv[1] : "");	
	printf("[2 key] : %s\n", argc > 2 && argv[2] ? argv[2] : "");
	printf("environment (ARCAN_ARG) : %s\n", 
		getenv("ARCAN_ARG") ? getenv("ARCAN_ARG") : "");
	printf("environment (ARCAN_SOCKIN_FD) : %s\n",
		getenv("ARCAN_SOCKIN_FD") ? getenv("ARCAN_SOCKIN_FD") : "");
	printf("environment (ARCAN_CONNPATH) : %s\n",
		getenv("ARCAN_CONNPATH") ? getenv("ARCAN_CONNPATH") : "");
	printf("environment (ARCAN_CONNKEY) : %s\n",
		getenv("ARCAN_CONKEY") ? getenv("ARCAN_CONNKEY") : "");
}

#ifdef ARCAN_FRAMESERVER_SPLITMODE
int main(int argc, char** argv)
{
	if (argc != 3){
		dumpargs(argc, argv);
		return 1;
	}

/* seriously doing this to work around compiler warnings, ./facepalm */ 
	toggle_logdev(NULL);

	char* fsrvmode = argv[1];
	if (strcmp(fsrvmode, "net-cl") == 0 || strcmp(fsrvmode, "net-srv") == 0){
		fsrvmode = "net";
	}

	size_t newbin = strlen(argv[0]) + strlen(fsrvmode) + 2;
 	char* newarg = malloc(newbin);
	snprintf(newarg, newbin, "%s_%s", argv[0], fsrvmode);

	argv[0] = newarg;
	return execv(newarg, argv);
}

#else
int main(int argc, char** argv)
{
	char* resource = getenv("ARCAN_ARG");
	char* keyfile  = NULL;
	char* fsrvmode = NULL;

	if (argc != 3){
#ifdef DEFAULT_FSRV_MODE
		fsrvmode = DEFAULT_FSRV_MODE;
#endif

		if ( getenv("ARCAN_CONNPATH")){
			keyfile = arcan_shmif_connect(
				getenv("ARCAN_CONNPATH"), getenv("ARCAN_CONNKEY")
			);
		}
		else
			LOG("no shared memory key could be acquired, "
				"check socket at ARCAN_CONNKEY environment.\n");
	} else {
		keyfile = argv[2];
		fsrvmode = argv[1];
	}

	if (!keyfile || !fsrvmode){
		dumpargs(argc, argv);
		return 1;
	}

/*
 * set this env whenever you want to step through the 
 * frameserver as launched from the parent 
 */
	if (getenv("ARCAN_FRAMESERVER_DEBUGSTALL")){
		LOG("frameserver_debugstall, waiting 10s to continue. pid: %d\n",
			(int) getpid());
		sleep(10);
	}
	
/* 
 * These are enabled based on build-system toggles,
 * a global define, FRAMESERVER_MODESTRING includes a space
 * separated list of enabled frameserver archetypes.
 */
#ifdef ENABLE_FSRV_NET
	if (strcmp(fsrvmode, "net-cl") == 0 || strcmp(fsrvmode, "net-srv") == 0){
		toggle_logdev("net");
		arcan_frameserver_net_run(resource, keyfile);
		return 0;
	}
#endif

#ifdef ENABLE_FSRV_DECODE
	if (strcmp(fsrvmode, "decode") == 0){
		toggle_logdev("dec");
		arcan_frameserver_decode_run(resource, keyfile);
		return 0;
	}
#endif

#ifdef ENABLE_FSRV_TERMINAL
	if (strcmp(fsrvmode, "terminal") == 0){
		toggle_logdev("term");
		arcan_frameserver_terminal_run(resource, keyfile);
		return 0;
	}
#endif	

#ifdef ENABLE_FSRV_ENCODE
	if (strcmp(fsrvmode, "record") == 0){
		toggle_logdev("rec");
		arcan_frameserver_encode_run(resource, keyfile);
		return 0;
	}
#endif

#ifdef ENABLE_FSRV_REMOTING
	if (strcmp(fsrvmode, "remoting") == 0){
		toggle_logdev("remoting");
		arcan_frameserver_remoting_run(resource, keyfile);
		return 0;
	}
#endif

#ifdef ENABLE_FSRV_LIBRETRO
	if (strcmp(fsrvmode, "libretro") == 0){
		toggle_logdev("retro");
		extern void arcan_frameserver_libretro_run(
			const char* resource, const char* shmkey);
		arcan_frameserver_libretro_run(resource, keyfile);
		return 0;
	}
#endif

#ifdef ENABLE_FSRV_AVFEED
	if (strcmp(fsrvmode, "avfeed") == 0){
		toggle_logdev("avfeed");
		arcan_frameserver_avfeed_run(resource, keyfile);
		return 0;
	}
#endif

	printf("frameserver launch failed, unsupported mode (%s)\n", fsrvmode);
	dumpargs(argc, argv);
	return 0;
}
#endif
