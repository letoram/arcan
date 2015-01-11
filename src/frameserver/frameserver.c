/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <assert.h>
#include <dirent.h>

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

static void close_logdev()
{
	fflush(stderr);
}

#ifndef ARCAN_FRAMESERVER_SPLITMODE
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

	atexit(close_logdev);
}
#endif

/*
 * Splitmode warrant some explaining,
 * in the mode we use the frameserver binary as a chainloader;
 * we select a different binary (our own name + _mode and
 * just pass the environment onwards.
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
 * one part as a package format with FUSE + chroot,
 * another using local sandboxing options (seccomp and capsicum)
 */
static void dumpargs(int argc, char** argv)
{
	printf("invalid number of arguments (%d):\n", argc);
 	printf("[1 mode] : %s\n", argc > 1 && argv[1] ? argv[1] : "");
	printf("environment (ARCAN_ARG) : %s\n",
		getenv("ARCAN_ARG") ? getenv("ARCAN_ARG") : "");
	printf("environment (ARCAN_SOCKIN_FD) : %s\n",
		getenv("ARCAN_SOCKIN_FD") ? getenv("ARCAN_SOCKIN_FD") : "");
	printf("environment (ARCAN_CONNPATH) : %s\n",
		getenv("ARCAN_CONNPATH") ? getenv("ARCAN_CONNPATH") : "");
	printf("environment (ARCAN_CONNKEY) : %s\n",
		getenv("ARCAN_CONKEY") ? getenv("ARCAN_CONNKEY") : "");
}

#if defined(_DEBUG) && !defined(__APPLE__) && !defined(__FreeBSD__)

void dump_links(const char* path)
{
	DIR* dp;
	struct dirent64* dirp;

	if ((dp = opendir(path)) == NULL)
		return;

	int fd = dirfd(dp);

	while((dirp = readdir64(dp)) != NULL){
		if (strcmp(dirp->d_name, ".") == 0)
			continue;
		else if (strcmp(dirp->d_name, "..") == 0)
			continue;

		char buf[256];
		buf[255] = '\0';

		ssize_t nr = readlinkat(fd, dirp->d_name, buf, sizeof(buf)-1);
		if (-1 == nr)
			continue;

		buf[nr] = '\0';
		fprintf(stdout, "\t%s\n", buf);
	}

	closedir(dp);
}
#endif

#ifdef ARCAN_FRAMESERVER_SPLITMODE
int main(int argc, char** argv)
{
	if (2 != argc){
		dumpargs(argc, argv);
		return EXIT_FAILURE;
	}

	char* fsrvmode = argv[1];

	size_t bin_sz = strlen(argv[0]) + strlen(fsrvmode) + 2;
	char newarg[ bin_sz ];
	snprintf(newarg, bin_sz, "%s_%s", argv[0], fsrvmode);

/*
 * the sweet-spot for adding in privilege/uid/gid swapping and
 * setting up mode- specific sandboxing, package format mount
 * etc.
 */

/* we no longer need the mode argument */
	argv[1] = NULL;
	argv[0] = newarg;
	execv(newarg, argv);

	return EXIT_FAILURE;
}

#else

typedef int (*mode_fun)(struct arcan_shmif_cont*, struct arg_arr*);

int launch_mode(const char* modestr,
	mode_fun fptr, enum ARCAN_SEGID id, char* altarg)
{
	if (!getenv("ARCAN_FRAMESERVER_DEBUGSTALL"))
		toggle_logdev(modestr);

	struct arg_arr* arg;
	struct arcan_shmif_cont con = arcan_shmif_open(id, 0, &arg);

	if (!arg && altarg)
		arg = arg_unpack(altarg);

	return fptr(con.addr ? &con : NULL, arg);
}

int main(int argc, char** argv)
{
#ifdef DEFAULT_FSRV_MODE
	char* fsrvmode = DEFAULT_FSRV_MODE;
	char* argstr = argc > 1 ? argv[1] : NULL; /* optional */
#else
/* non-split mode arguments require [mode + opt-arg ] */
	char* fsrvmode = argv[1];
	char* argstr = argc > 2 ? argv[2] : NULL;
#endif

/*
 * Monitor for descriptor leaks from parent
 */
#if defined(_DEBUG) && !defined(__APPLE__) && !defined(__FreeBSD__)
	DIR* dp;
	struct dirent64* dirp;
	if ((dp = opendir("/proc/self/fd")) != NULL){
		size_t desc_count = 0;

		while((dirp = readdir64(dp)) != NULL) {
			if (strcmp(dirp->d_name, ".") != 0 && strcmp(dirp->d_name, "..") != 0)
				desc_count++;
		}
		closedir(dp);

/* stdin, stdout, stderr, [connection socket], any more
 * and we should be suspicious about descriptor leakage */
		if (desc_count > 5){
			fprintf(stdout, "\x1b[1msuspicious amount (%zu)"
				"of descriptors open, investigate.\x1b[0m\n", desc_count);

			dump_links("/proc/self/fd");
		}
	}
#endif

/*
 * set this env whenever you want to step through the
 * frameserver as launched from the parent
 */
	if (getenv("ARCAN_FRAMESERVER_DEBUGSTALL")){
		int sleeplen = strtoul(getenv("ARCAN_FRAMESERVER_DEBUGSTALL"), NULL, 10);

		if (sleeplen <= 0){
			fprintf(stdout, "\x1b[1mARCAN_FRAMESERVER_DEBUGSTALL,\x1b[0m "
				"spin-waiting for debugger.\n \tAttach to pid: "
				"\x1b[32m%d\x1b[39m\x1b[0m and break out of loop"
				" (set loop = 0)\n", getpid()
			);

			volatile int loop = 1;
			while(loop == 1);
		}
		else{
			fprintf(stdout,"\x1b[1mARCAN_FRAMESERVER_DEBUGSTALL set, waiting %d s.\n"
				"\tfor debugging/tracing, attach to pid: \x1b[32m%d\x1b[39m\x1b[0m\n",
				sleeplen, (int) getpid());
			sleep(sleeplen);
		}
	}

/*
 * These are enabled based on build-system toggles,
 * a global define, FRAMESERVER_MODESTRING includes a space
 * separated list of enabled frameserver archetypes.
 */
#ifdef ENABLE_FSRV_DECODE
	if (strcmp(fsrvmode, "decode") == 0){
		return launch_mode("decode", arcan_frameserver_decode_run,
			SEGID_MEDIA, argstr);
	}
#endif

#ifdef ENABLE_FSRV_TERMINAL
	if (strcmp(fsrvmode, "terminal") == 0){
		return launch_mode("terminal", arcan_frameserver_terminal_run,
			SEGID_TERMINAL, argstr);
	}
#endif

#ifdef ENABLE_FSRV_ENCODE
	if (strcmp(fsrvmode, "record") == 0){
		return launch_mode("record", arcan_frameserver_encode_run,
			SEGID_ENCODER, argstr);
	}
#endif

#ifdef ENABLE_FSRV_REMOTING
	if (strcmp(fsrvmode, "remoting") == 0){
		return launch_mode("remoting", arcan_frameserver_remoting_run,
			SEGID_REMOTING, argstr);
	}
#endif

#ifdef ENABLE_FSRV_LIBRETRO
	if (strcmp(fsrvmode, "libretro") == 0){
		return launch_mode("libretro", arcan_frameserver_libretro_run,
			SEGID_GAME, argstr);
	}
#endif

#ifdef ENABLE_FSRV_AVFEED
	if (strcmp(fsrvmode, "avfeed") == 0){
		return launch_mode("avfeed", arcan_frameserver_avfeed_run,
			SEGID_MEDIA, argstr);
	}
#endif

/*
 * NET- is a bit special in that it encompasses multiple submodes
 * and may need to support multiple more (p2p-node etc.)
 * which may need different IDs, so we do a preliminary arg-unpack
 * in beforehand.
 */
#ifdef ENABLE_FSRV_NET
	if (strcmp(fsrvmode, "net") == 0){
		struct arg_arr* tmp = arg_unpack(getenv("ARCAN_ARG"));
		const char* rk;

		if (!tmp)
			tmp = arg_unpack(argstr);

		enum ARCAN_SEGID id;
		mode_fun fptr;
		const char* modestr = NULL;

		if (tmp && arg_lookup(tmp, "mode", 0, &rk)){
			if (strcmp(rk, "client") == 0){
				id = SEGID_NETWORK_CLIENT;
				fptr = arcan_frameserver_net_client_run;
				modestr = "client";
			}
			else if (strcmp(rk, "server") == 0){
				id = SEGID_NETWORK_SERVER;
				fptr = arcan_frameserver_net_server_run;
				modestr = "server";
			}
			else{
				fprintf(stdout, "frameserver_net, invalid ARCAN_ARG env:\n"
					"must have mode=modev set to client or server.\n");
				return EXIT_FAILURE;
			}
		}
			arg_cleanup(tmp); /* will invalidate all aliases from _lookup */

		if (!modestr){
			fprintf(stdout, "frameserver_net, invalid ARCAN_ARG env:\n"
				"must have mode=modev set to client or server.\n");
			return EXIT_FAILURE;
		}

		return launch_mode(modestr, fptr, id, argstr);
	}
#endif

	printf("frameserver launch failed, unsupported mode (%s)\n", fsrvmode);
	dumpargs(argc, argv);

	return EXIT_FAILURE;
}
#endif
