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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#include <stdlib.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdbool.h>
#include <signal.h>
#include <poll.h>
#include <limits.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <unistd.h>

#include <errno.h>

#include <SDL.h>
#include <SDL_opengl.h>

#include <assert.h>
#include <errno.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_event.h"
#include "arcan_framequeue.h"
#include "arcan_target_const.h"
#include "arcan_frameserver_backend.h"
#include "arcan_frameserver_shmpage.h"
#include "arcan_target_launcher.h"
#include "arcan_db.h"

int arcan_target_launch_external(const char* fname, char** argv)
{
	if (arcan_video_prepare_external() == false){
		arcan_warning("Warning, arcan_target_launch_external(), couldn't push current context, aborting launch.\n");
		return 0;
	}
	
	pid_t child = fork();
	unsigned long ticks = SDL_GetTicks();

	if (child) {
		int stat_loc;

			while (-1 == waitpid(child, &stat_loc, 0)){
				if (errno != EINVAL) 
					break;
			}
		arcan_video_restore_external();

		return SDL_GetTicks() - ticks;
	}
	else {
		execv(fname, argv);
		_exit(1);
	}
}

static arcan_errc again_feed(float gain, void* tag)
{
	return ARCAN_OK;
}

/* note for debugging internal launch (particularly the hijack lib)
 * (linux only)
 * gdb, break just before the fork
 * set follow-fork-mode child, add a breakpoint to the yet unresolved hijack_init symbol
 * and move on. 
 * for other platforms, patch the hijacklib loader to set an infinite while loop on a volatile flag,
 * break the process and manually change the memory of the flag */

arcan_frameserver* arcan_target_launch_internal(const char* fname, char* hijack, char** argv)
{
	if (hijack == NULL){
		arcan_warning("Warning: arcan_target_launch_internal() called without a proper hijack lib.\n");
		return NULL;
	}

	arcan_frameserver* res = arcan_frameserver_alloc(); 
	
	char shmsize[ 39 ] = {0};
	
	char* envv[10] = {
			"LD_PRELOAD", hijack,
			"DYLD_INSERT_LIBRARIES", hijack,
			"ARCAN_SHMKEY", "",
			"ARCAN_SHMSIZE", "",
			NULL, NULL
	};
	
	struct frameserver_envp args = {
		.use_builtin = false,
		.args.external.fname = (char*) fname,
		.args.external.envv = envv,
		.args.external.argv = argv
	};
	
	snprintf(shmsize, 38, "%ui", (unsigned int) MAX_SHMSIZE);
	
	if (
		arcan_frameserver_spawn_server(res, args) != ARCAN_OK) {
		free(res);
		res = NULL;
	}

	return res;
}
