/*
 Arcan-FE Platform, process setup/launch

 Copyright (c) Björn Ståhl 2014,
 All rights reserved.

 Redistribution and use in source and binary forms,
 with or without modification, are permitted provided that the
 following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
 may be used to endorse or promote products derived from this software without
 specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 THE POSSIBILITY OF SUCH DAMAGE
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
