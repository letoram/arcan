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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor Boston, MA 02110-1301, USA.
 *
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <assert.h>

#include <sys/types.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/param.h>
#include <sys/mman.h>
#include <sys/stat.h>

#include <signal.h>
#include <errno.h>
#include <aio.h>

/* openAL */
#include <al.h>
#include <alc.h>

/* libSDL */
#include <SDL.h>
#include <SDL_types.h>

/* arcan */
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_framequeue.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_frameserver_backend.h"
#include "arcan_util.h"
#include "arcan_frameserver_shmpage.h"

#define INCR(X, C) ( ( (X) = ( (X) + 1) % (C)) )

extern char* arcan_binpath;

arcan_errc arcan_frameserver_free(arcan_frameserver* src, bool loop)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (src) {
		src->playstate = loop ? ARCAN_PAUSED : ARCAN_PASSIVE;
		if (!loop)
			arcan_audio_stop(src->aid);
			
		if (src->vfq.alive)
			arcan_framequeue_free(&src->vfq);
		
		if (src->afq.alive)
			arcan_framequeue_free(&src->afq);

		if (src->lock_audb)
			SDL_DestroyMutex(src->lock_audb);
		
	/* might have died prematurely (framequeue cbs), no reason sending signal */
 		if (src->child_alive) {
			kill(src->child, SIGHUP);
			src->child_alive = false;
			waitpid(src->child, NULL, 0);
			src->child = 0;
		}
		
		struct movie_shmpage* shmpage = (struct movie_shmpage*) src->shm.ptr;
		
		free(src->audb);

		if (shmpage){
			arcan_frameserver_dropsemaphores(src);
		
			if (src->shm.ptr && -1 == munmap((void*) shmpage, src->shm.shmsize))
				arcan_warning("BUG -- arcan_frameserver_free(), munmap failed: %s\n", strerror(errno));
			
			shm_unlink( src->shm.key );
			free(src->shm.key);
			
			src->shm.ptr = NULL;
		}
		
		rv = ARCAN_OK;
	}

	return rv;
}

int check_child(arcan_frameserver* movie){
	int rv = -1, status;

/* this will be called on any attached video source with a tag of TAG_MOVIE,
 * return EAGAIN to continue, EINVAL implies that the child frameserver died somehow.
 * When a movie is in between states, the child pid might not be set yet */
	if (movie->child &&
		waitpid( movie->child, &status, WNOHANG ) == movie->child){
		errno = EINVAL;
		movie->child_alive = false;
	} else 
		errno = EAGAIN;

	return rv;
}

arcan_errc arcan_frameserver_pushfd(arcan_frameserver* fsrv, int fd)
{
	arcan_errc rv = ARCAN_ERRC_BAD_ARGUMENT;

	if (fsrv && fd > 0){
		char empty = '!';
		
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
		((int*) CMSG_DATA(cmsg))[0] = fd;
		
		if (sendmsg(fsrv->sockout_fd, &msg, 0) >= 0){
			rv = ARCAN_OK;
			arcan_event ev = {
				.category = EVENT_TARGET,
				.kind = TARGET_COMMAND_FDTRANSFER
			};
			
			arcan_frameserver_pushevent( fsrv, &ev );
			close(fd);
		}
		else
			arcan_warning("frameserver_pushfd(%d->%d) failed, reason(%d) : %s\n", fd, fsrv->sockout_fd, errno, strerror(errno));
	}
	
	return rv;
}

void arcan_frameserver_dbgdump(FILE* dst, arcan_frameserver* src){
	if (src){
		fprintf(dst, "movie source: %s\n"
		"mapped to: %i, %i\n"
		"video queue (%s): %i / %i\n"
		"audio queue (%s): %i / %i\n"
		"playstate: %i\n",
		src->shm.key,
		(int) src->vid, (int) src->aid,
		src->vfq.alive ? "alive" : "dead", src->vfq.c_cells, src->vfq.n_cells,
		src->afq.alive ? "alive" : "dead", src->afq.c_cells, src->afq.n_cells,
		src->playstate
		);
	}
	else
		fprintf(dst, "arcan_frameserver_dbgdump:\n(null)\n\n");
}

arcan_errc arcan_frameserver_spawn_server(arcan_frameserver* ctx, struct frameserver_envp setup)
{
	if (ctx == NULL)
		return ARCAN_ERRC_BAD_ARGUMENT;
	
	img_cons cons = {.w = 32, .h = 32, .bpp = 4};
	
	size_t shmsize = MAX_SHMSIZE;
	struct frameserver_shmpage* shmpage;
	int shmfd = 0;
	
	ctx->shm.key = arcan_findshmkey(&shmfd, true);
	char* work = strdup(ctx->shm.key);
		work[strlen(work) - 1] = 'v';
		ctx->vsync = sem_open(work, 0);
		work[strlen(work) - 1] = 'a';
		ctx->async = sem_open(work, 0);
		work[strlen(work) - 1] = 'e';
		ctx->esync = sem_open(work, 0);	
	free(work);
		
/* max videoframesize + DTS + structure + maxaudioframesize,
* start with max, then truncate down to whatever is actually used */
	ftruncate(shmfd, shmsize);
	shmpage = (void*) mmap(NULL, shmsize, PROT_READ | PROT_WRITE, MAP_SHARED, shmfd, 0);
	close(shmfd);
		
	if (MAP_FAILED == shmpage){
		arcan_warning("arcan_frameserver_spawn_server(unix) -- couldn't allocate shmpage\n");
		goto error_cleanup;
	}
		
	shmpage->parent = getpid();

	int sockp[2] = {-1, -1};
	if ( socketpair(PF_UNIX, SOCK_DGRAM, 0, sockp) < 0 ){
		arcan_warning("arcan_frameserver_spawn_server(unix) -- couldn't get socket pair\n");
	}
	
	pid_t child = fork();
	if (child) {
		arcan_frameserver_meta vinfo = {0};
		arcan_errc err;
		close(sockp[1]);
		
/* init- call (different from loop-exec as we need to 
 * keep the vid / aud as they are external references into the scripted state-space */
		if (ctx->vid == ARCAN_EID) {
			vfunc_state state = {.tag = ARCAN_TAG_FRAMESERV, .ptr = ctx};
			
			ctx->source = strdup(setup.args.builtin.resource);
			ctx->vid = arcan_video_addfobject((arcan_vfunc_cb)arcan_frameserver_emptyframe, state, cons, 0);
			ctx->aid = ARCAN_EID;
		} else { 
			vfunc_state* cstate = arcan_video_feedstate(ctx->vid);
			arcan_video_alterfeed(ctx->vid, (arcan_vfunc_cb)arcan_frameserver_emptyframe, *cstate); /* revert back to empty vfunc? */
		}
	
/* "movie" mode involves parallell queues of raw, decoded, frames and heuristics 
 * for dropping, delaying or showing frames based on DTS/PTS values */
		if (setup.use_builtin && strcmp(setup.args.builtin.mode, "movie") == 0)
			ctx->kind = ARCAN_FRAMESERVER_INPUT;

/* "libretro" (or rather, interactive mode) treats a single pair of videoframe+audiobuffer
 * each transfer, minimized latency is key. All operations require an intermediate buffer 
 * and are synched to one framequeue */
		else if (setup.use_builtin && strcmp(setup.args.builtin.mode, "libretro") == 0){
			ctx->kind = ARCAN_FRAMESERVER_INTERACTIVE;
			ctx->nopts = true;
			ctx->autoplay = true;
			ctx->sz_audb = 1024 * 24;
			
			ctx->audb = malloc( ctx->sz_audb );
			ctx->lock_audb = SDL_CreateMutex();
			memset(ctx->audb, 0, ctx->ofs_audb);
		}

/* hijack works as a 'process parasite' inside the rendering pipeline of other projects,
 * similar otherwise to libretro except it only deals with videoframes */
		else if (!setup.use_builtin){
			ctx->kind = ARCAN_HIJACKLIB;
			ctx->nopts = true;
			ctx->autoplay = true;
		}
		
		ctx->child_alive = true;
		ctx->desc = vinfo;
		ctx->child = child;
		ctx->desc.width = cons.w;
		ctx->desc.height = cons.h;
		ctx->desc.bpp = cons.bpp;
		ctx->shm.ptr = (void*) shmpage;
		ctx->shm.shmsize = shmsize;
		ctx->sockout_fd = sockp[0];

/* two separate queues for passing events back and forth between main program and frameserver,
 * set the buffer pointers to the relevant offsets in backend_shmpage, and semaphores from the sem_open calls */
		frameserver_shmpage_setevqs( shmpage, ctx->esync, &(ctx->inqueue), &(ctx->outqueue), true);
		ctx->inqueue.synch.external.killswitch = ctx;
		ctx->outqueue.synch.external.killswitch = ctx;
	}
	else if (child == 0) {
		char convb[8];
	
/* this little thing is used to push file-descriptors between parent and child, as to not expose 
 * child to parents namespace, and to improve privilege separation */
		close(sockp[0]);
		sprintf(convb, "%i", sockp[1]);
		setenv("ARCAN_SOCKIN_FD", convb, 1);
		
		if (setup.use_builtin){
			char* argv[5] = { arcan_binpath, setup.args.builtin.resource, ctx->shm.key, setup.args.builtin.mode, NULL };

/* just to help keeping track when there's a lot of them */
			char vla[ strlen(setup.args.builtin.mode) + 1];
			snprintf( vla, sizeof(vla), "%s", setup.args.builtin.mode );
			argv[0] = vla;

			int rv = execv(arcan_binpath, argv);
			arcan_fatal("FATAL, arcan_frameserver_spawn_server(), couldn't spawn frameserver(%s) with %s:%s. Reason: %s\n", arcan_binpath, 
									setup.args.builtin.mode, setup.args.builtin.resource, strerror(errno));
			exit(1);
		} else {
/* hijack lib */
			char shmsize_s[32];
			snprintf(shmsize_s, 32, "%zu", shmsize);
			
			char** envv = setup.args.external.envv;

			while (envv && *envv){
				if (strcmp(envv[0], "ARCAN_SHMKEY") == 0)
					setenv("ARCAN_SHMKEY", ctx->shm.key, 1);
				else if (strcmp(envv[0], "ARCAN_SHMSIZE") == 0)
					setenv("ARCAN_SHMSIZE", shmsize_s, 1);
				else 
					setenv(envv[0], envv[1], 1);
				
				envv += 2;
			}
			
			int rv = execv(setup.args.external.fname, setup.args.external.argv);
			exit(1);
		}
	}
	else /* -1 */
		goto error_cleanup;
		
	return ARCAN_OK;

error_cleanup:
	arcan_frameserver_dropsemaphores_keyed(ctx->shm.key);
	shm_unlink(ctx->shm.key);
	free(ctx->shm.key);
	ctx->shm.key = NULL;

	return ARCAN_ERRC_OUT_OF_SPACE;
}
