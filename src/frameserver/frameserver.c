/*
 * Copyright 2014-2016, Björn Ståhl
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
#include <signal.h>
#include <fcntl.h>
#include <time.h>
#include <dlfcn.h>

#include <arcan_shmif.h>
#include "frameserver.h"

#ifndef AFSRV_CHAINLOADER
static void close_logdev()
{
	fflush(stderr);
}

static void toggle_logdev(const char* prefix)
{
	const char* const logdir = getenv("ARCAN_FRAMESERVER_LOGDIR");

	if (!prefix || !logdir)
		return;

	char timeb[16];
	time_t t = time(NULL);
	struct tm* basetime = localtime(&t);
	strftime(timeb, sizeof(timeb)-1, "%y%m%d_%H%M", basetime);

	size_t logbuf_sz = strlen(logdir) +
		sizeof("/fsrv__yymmddhhss__65536.txt") + strlen(prefix);
	char* logbuf = malloc(logbuf_sz);

	snprintf(logbuf, logbuf_sz,
		"%s/fsrv_%s_%s_%d.txt", logdir, prefix, timeb, (int)getpid());
	if (!freopen(logbuf, "a", stderr)){
		if (!freopen("/dev/null", "a", stderr))
			fclose(stderr);
	}
	setlinebuf(stderr);
}
#endif

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

#if defined(_DEBUG) && !defined(__APPLE__) && !defined(__BSD)

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

/*
 * When built as a chainloader we select a different binary (our own
 * name or afsrv if we're arcan_frameserver) + _mode and just pass
 * the environment onwards. The afsrv_ split permits the parent to run
 * with a different set of frameservers for debugging/testing/etc. purposes.
 *
 * The chainloading approach is to get a process separated spot for
 * implementing monitoring, sandboxing and other environment related factors
 * where we might have temporarily inflated privileges.
 */
#ifdef AFSRV_CHAINLOADER
int main(int argc, char** argv)
{
	if (2 != argc){
		dumpargs(argc, argv);
		return EXIT_FAILURE;
	}

	if (!argv[0])
		return EXIT_FAILURE;

	size_t i = strlen(argv[0])-1;
	for (; i && argv[0][i] == '/'; i--) argv[0][i] = 0;
	for (; i && argv[0][i-1] != '/'; i--);
	if (i)
		argv[0][i-1] = '\0';

	const char* dirn = argv[0];
	const char* base = argv[0] + i;
	const char* mode = argv[1];

	if (strcmp(base, "arcan_frameserver") == 0)
		base = "afsrv";

	size_t bin_sz = strlen(dirn) + strlen(base) + strlen(argv[1]) + 3;
	char newarg[ bin_sz ];
	snprintf(newarg, bin_sz, "%s/%s_%s", dirn, base, argv[1]);

/*
 * the sweet-spot for adding in privilege/uid/gid swapping and setting up mode-
 * specific sandboxing, package format mount (or other compatibility / loading)
 * etc. When that is done, ofc. add more stringent control over what newarg
 * turns out to be.
 */

/* we no longer need the mode argument */
	argv[1] = NULL;
	argv[0] = newarg;

	setsid();

	execv(newarg, argv);

	return EXIT_FAILURE;
}

#else
typedef int (*mode_fun)(struct arcan_shmif_cont*, struct arg_arr*);

int launch_mode(const char* modestr,
	mode_fun fptr, enum ARCAN_SEGID id, enum ARCAN_FLAGS flags, char* altarg)
{
	char* debug = getenv("ARCAN_FRAMESERVER_DEBUGSTALL");

	if (!debug){
		toggle_logdev(modestr);
		fprintf(stderr, "mode: %s, arg: %s\n",
			modestr, getenv("ARCAN_ARG") ? getenv("ARCAN_ARG") : " [missing] ");
	}

	struct arg_arr* arg = NULL;
	struct arcan_shmif_cont con = arcan_shmif_open_ext(flags,
		&arg, (struct shmif_open_ext){.type = id}, sizeof(struct shmif_open_ext));

	if (!arg && altarg)
		arg = arg_unpack(altarg);

	if (debug){
		arcan_shmif_signal(&con, SHMIF_SIGVID);
		int sleeplen = strtoul(debug, NULL, 10);

		struct arcan_event ev = {
			.ext.kind = ARCAN_EVENT(IDENT)
		};
		arcan_shmif_enqueue(&con, &ev);
		snprintf(
			(char*)ev.ext.message.data,
			sizeof(ev.ext.message.data), "debugstall:%d:%zu", sleeplen, (size_t)getpid()
		);

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
#if defined(_DEBUG) && !defined(__APPLE__) && !defined(__BSD)
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
 * These are enabled based on build-system toggles,
 * a global define, FRAMESERVER_MODESTRING includes a space
 * separated list of enabled frameserver archetypes.
 */
#ifdef ENABLE_FSRV_DECODE
	if (strcmp(fsrvmode, "decode") == 0)
		return launch_mode("decode",
			afsrv_decode, SEGID_UNKNOWN,
			SHMIF_MANUAL_PAUSE |
			SHMIF_NOACTIVATE_RESIZE |
			SHMIF_NOREGISTER, argstr
		);
#endif

#ifdef ENABLE_FSRV_TERMINAL
	if (strcmp(fsrvmode, "terminal") == 0)
		return launch_mode("terminal", afsrv_terminal, SEGID_TERMINAL, 0, argstr);
#endif

#ifdef ENABLE_FSRV_ENCODE
	if (strcmp(fsrvmode, "encode") == 0)
		return launch_mode("encode", afsrv_encode, SEGID_ENCODER, 0, argstr);
#endif

#ifdef ENABLE_FSRV_REMOTING
	if (strcmp(fsrvmode, "remoting") == 0)
		return launch_mode("remoting", afsrv_remoting, SEGID_REMOTING, 0, argstr);
#endif

#ifdef ENABLE_FSRV_GAME
	if (strcmp(fsrvmode, "game") == 0)
		return launch_mode("game", afsrv_game,
			SEGID_GAME, SHMIF_NOACTIVATE_RESIZE, argstr);
#endif

#ifdef ENABLE_FSRV_AVFEED
	if (strcmp(fsrvmode, "avfeed") == 0)
		return launch_mode("avfeed", afsrv_avfeed,
			SEGID_MEDIA, SHMIF_DISABLE_GUARD, argstr);
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
				id = SEGID_REMOTING; /* SEGID_NETWORK_CLIENT; */
				fptr = afsrv_netcl;
				modestr = "client";
			}
			else if (strcmp(rk, "server") == 0){
				id = SEGID_NETWORK_SERVER;
				fptr = afsrv_netsrv;
				modestr = "server";
			}
			else{
				fprintf(stdout, "frameserver_net, invalid ARCAN_ARG env:\n"
					"must have mode=modev set to client or server.\n");
				return EXIT_FAILURE;
			}
		}
 /* will invalidate all aliases from _lookup */
		arg_cleanup(tmp);

		if (!modestr){
			fprintf(stdout, "frameserver_net, invalid ARCAN_ARG env:\n"
				"must have mode=modev set to client or server.\n");
			return EXIT_FAILURE;
		}

		return launch_mode(modestr, fptr, id, 0, argstr);
	}
#endif

	printf("frameserver launch failed, unsupported mode (%s)\n", fsrvmode);
	dumpargs(argc, argv);

	return EXIT_FAILURE;
}
#endif
