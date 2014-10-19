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

static char* get_hijack(char** libs)
{
	char* hijack = NULL;
	size_t lib_sz = 0;

/* concatenate and build library string */
	char** work = libs;
	while(work && *work){
		lib_sz += strlen(*work) + 1;
		work++;
	}

	if (lib_sz > 0){
		hijack = malloc(lib_sz + 1);
		char* ofs = hijack;

		work = libs;
		while (*work){
			size_t len = strlen(*work);
			memcpy(ofs, *work, len);
			ofs[len] = ':'; /* ' ' or ':', afaik : works on more platforms */
			ofs += len + 1;
			work++;
		}

		ofs[-1] = '\0';
	}

	return hijack;
}

int arcan_target_launch_external(const char* fname,
	char** argv, char** envv, char** libs)
{
	if (arcan_video_prepare_external() == false){
		arcan_warning("Warning, arcan_target_launch_external(), "
			"couldn't push current context, aborting launch.\n");
		return 0;
	}

	pid_t child = fork();
	unsigned long ticks = arcan_timemillis();

	if (child) {
		int stat_loc;

			while (-1 == waitpid(child, &stat_loc, 0)){
				if (errno != EINVAL)
					break;
			}
		arcan_video_restore_external();

		return arcan_timemillis() - ticks;
	}
	else {
		execv(fname, argv);
		_exit(1);
	}
}

arcan_frameserver* arcan_target_launch_internal(const char* fname,
	char** argv, char** envv, char** libs)
{
	arcan_frameserver* res = arcan_frameserver_alloc();

	char shmsize[ 39 ] = {0};
/*
	char* envv[10] = {
			"LD_PRELOAD", hijack,
			"DYLD_INSERT_LIBRARIES", hijack,
			"ARCAN_SHMKEY", "",
			"ARCAN_SHMSIZE", "",
			NULL, NULL
	};
*/
	struct frameserver_envp args = {
		.use_builtin = false,
		.args.external.fname = (char*) fname,
		.args.external.envv = envv,
		.args.external.argv = argv
	};

	snprintf(shmsize, 38, "%ui", (unsigned int) ARCAN_SHMPAGE_MAX_SZ);

	if (
		arcan_frameserver_spawn_server(res, args) != ARCAN_OK) {
		free(res);
		res = NULL;
	}

	return res;
}
