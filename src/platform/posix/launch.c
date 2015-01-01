/*
 * Copyright 2014-2015, Björn Ståhl
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
#ifdef DARWIN
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
	if (arcan_video_prepare_external() == false){
		arcan_warning("Warning, arcan_target_launch_external(), "
			"couldn't push current context, aborting launch.\n");
		return 0;
	}

	pid_t child = fork();

	if (child > 0) {
		int stat_loc;
		waitpid(child, &stat_loc, 0);

		if (WIFEXITED(stat_loc)){
			*exitc = WEXITSTATUS(stat_loc);
		}
		else
			*exitc = EXIT_FAILURE;

		arcan_video_restore_external();

		unsigned long ticks = arcan_timemillis();
		return arcan_timemillis() - ticks;
	}
	else {
/* GNU extension warning */
		add_interpose(libs, envv);
		execve(fname, argv->data, envv->data);
		_exit(1);
	}

	*exitc = EXIT_FAILURE;
	return 0;
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
		arcan_frameserver_spawn_server(res, args) != ARCAN_OK) {
		free(res);
		res = NULL;
	}

	return res;
}
