/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdbool.h>
#include <signal.h>
#include <string.h>
#include <poll.h>
#include <limits.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <unistd.h>
#include <pthread.h>

#include <errno.h>

#include <assert.h>
#include <errno.h>

#include PLATFORM_HEADER

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_db.h"
#include "arcan_audio.h"
#include "arcan_shmif.h"
#include "arcan_frameserver.h"

static char* add_interpose(struct arcan_strarr* libs, struct arcan_strarr* envv)
{
	char* interp = NULL;
	size_t lib_sz = 0;
#ifdef __APPLE__
	char basestr[] = "DYLD_INSERT_LIBRARIES=";
#else
	char basestr[] = "LD_PRELOAD=";
#endif

/* concatenate and build library string */
	char** work = libs->data;
	while(work && *work){
		lib_sz += strlen(*work) + 1;
		work++;
	}

	if (lib_sz > 0){
		interp = malloc(lib_sz + sizeof(basestr));
		memcpy(interp, basestr, sizeof(basestr));
		char* ofs = interp + sizeof(basestr)-1;

		work = libs->data;
		while (*work){
			size_t len = strlen(*work);
			memcpy(ofs, *work, len);
			ofs[len] = ':'; /* ' ' or ':', afaik : works on more platforms */
			ofs += len + 1;
			work++;
		}

		ofs[-1] = '\0';
	}

	if (envv->limit - envv->count < 2)
		arcan_mem_growarr(envv);

	envv->data[envv->count++] = interp;

	return interp;
}

unsigned long arcan_target_launch_external(const char* fname,
	struct arcan_strarr* argv, struct arcan_strarr* envv,
	struct arcan_strarr* libs, int* exitc)
{
	add_interpose(libs, envv);
	pid_t child = fork();

	if (child > 0) {
		int stat_loc;
		waitpid(child, &stat_loc, 0);

		if (WIFEXITED(stat_loc)){
			*exitc = WEXITSTATUS(stat_loc);
		}
		else
			*exitc = EXIT_FAILURE;

		unsigned long ticks = arcan_timemillis();
		return arcan_timemillis() - ticks;
	}
	else {
/* GNU extension warning */
		execve(fname, argv->data, envv->data);
		_exit(1);
	}

	*exitc = EXIT_FAILURE;
	return 0;
}

void arcan_closefrom(int fd)
{
#if defined(__APPLE__) || defined(__linux__)
	struct rlimit rlim;
	int lim = 512;
	if (0 == getrlimit(RLIMIT_NOFILE, &rlim))
		lim = rlim.rlim_cur;

	struct pollfd* fds = arcan_alloc_mem(sizeof(struct rlimit)*lim,
		ARCAN_MEM_STRINGBUF, ARCAN_MEM_BZERO |
			ARCAN_MEM_TEMPORARY, ARCAN_MEMALIGN_NATURAL);

	for (size_t i = 0; i < lim; i++)
		fds[i].fd = i+fd;

	poll(fds, lim, 0);

	for (size_t i = 0; i < lim; i++)
		if (!(fds[i].revents & POLLNVAL))
			close(fds[i].fd);

	arcan_mem_free(fds);
#else
	closefrom(fd);
#endif
}

arcan_frameserver* arcan_target_launch_internal(const char* fname,
	struct arcan_strarr* argv, struct arcan_strarr* envv,
	struct arcan_strarr* libs)
{
	arcan_frameserver* res = arcan_frameserver_alloc();
	add_interpose(libs, envv);

	argv->data = arcan_expand_namespaces(argv->data);
	envv->data = arcan_expand_namespaces(envv->data);

	struct frameserver_envp args = {
		.use_builtin = false,
		.args.external.fname = (char*) fname,
		.args.external.envv = envv,
		.args.external.argv = argv
	};

	if (
		arcan_frameserver_spawn_server(res, &args) != ARCAN_OK) {
		free(res);
		res = NULL;
	}

	return res;
}
