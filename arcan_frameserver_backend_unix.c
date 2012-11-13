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
#include <pthread.h>

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

/* dislike resorting to these kinds of antics, but it was among the cleaner
 * solutions given the portability constraints (OSX,Win32) */
static void* nanny_thread(void* arg)
{
	pid_t* pid = (pid_t*) arg;

	if (pid){
		int counter = 10;
		kill(*pid, SIGTERM);
		
		while (counter--){
			int statusfl;
			int rv = waitpid(*pid, &statusfl, WNOHANG);
			if (rv > 0)
				break;
			else if (counter == 0){
				kill(*pid, SIGKILL);
				break;
			}

			sleep(1);
		}
		
		free(pid);
	}

	return NULL;
}

arcan_errc arcan_frameserver_free(arcan_frameserver* src, bool loop)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	
	if (src) {
		src->playstate = loop ? ARCAN_PAUSED : ARCAN_PASSIVE;
			
		if (src->vfq.alive)
			arcan_framequeue_free(&src->vfq);
		
		if (src->afq.alive)
			arcan_framequeue_free(&src->afq);

		struct frameserver_shmpage* shmpage = (struct frameserver_shmpage*) src->shm.ptr;
	
/* might have died prematurely (framequeue cbs), no reason sending signal, even if this is ignored
 * (say, hijack libraries in processes with installed signal handler, a corresponding exit event
 * will be in the queue as well, along with the dms trigger */
		if (src->child_alive) {
			shmpage->dms = false;

			arcan_event exev = {
				.category = EVENT_TARGET,
				.kind = TARGET_COMMAND_EXIT
			};

			arcan_frameserver_pushevent(src, &exev);

/* this one is more complicated than it seems, as we don't want zombies lying around,
 * yet might be in a context where the child is no-longer trusted. Double-forking and getting the handle
 * that way is overcomplicated, maintaining a state-table of assumed-alive children until wait says otherwise
 * and then map may lead to dangling pointers with video_deleteobject or sweeping the full state context etc.
 * 
 * Cheapest, it seems, is to actually spawn a guard thread with a sleep + wait cycle, countdown and then send KILL
 */
			pid_t* pidptr = malloc(sizeof(pid_t));
			pthread_t pthr;
			*pidptr = src->child;

			if (0 != pthread_create(&pthr, NULL, nanny_thread, (void*) pidptr))
				kill(src->child, SIGKILL);
/* panic option anyhow, just forcibly kill */

			src->child = -1;
			src->child_alive = false;
		}

/* unhook audio monitors */
		arcan_aobj_id* base = src->alocks;
		while (base && *base){
			arcan_audio_hookfeed(*base, NULL, NULL, NULL);
			base++;
		}
		free(src->audb);

		if (src->lock_audb)
			SDL_DestroyMutex(src->lock_audb);

		if (shmpage){
			arcan_frameserver_dropsemaphores(src);
		
			if (src->shm.ptr && -1 == munmap((void*) shmpage, src->shm.shmsize))
				arcan_warning("BUG -- arcan_frameserver_free(), munmap failed: %s\n", strerror(errno));
			
			shm_unlink( src->shm.key );
			free(src->shm.key);
			
			src->shm.ptr = NULL;
		}
		
		if (!loop){
			vfunc_state emptys = {0};
			arcan_audio_stop(src->aid);
			arcan_video_alterfeed(src->vid, arcan_video_emptyffunc(), emptys);
			memset(src, 0xaa, sizeof(arcan_frameserver));
			free(src);
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
	int ec = waitpid(movie->child, &status, WNOHANG);
	if (ec == movie->child){
		movie->child_alive = false;
		errno = EINVAL;
	} 
	else 
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
		}
		else
			arcan_warning("frameserver_pushfd(%d->%d) failed, reason(%d) : %s\n", fd, fsrv->sockout_fd, errno, strerror(errno));
	}
	
	return rv;
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

	ctx->launchedtime = arcan_frametime();
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
		} else if (setup.custom_feed == false){ 
			vfunc_state* cstate = arcan_video_feedstate(ctx->vid);
			arcan_video_alterfeed(ctx->vid, (arcan_vfunc_cb)arcan_frameserver_emptyframe, *cstate); /* revert back to empty vfunc? */
		}
	
/* "movie" mode involves parallell queues of raw, decoded, frames and heuristics 
 * for dropping, delaying or showing frames based on DTS/PTS values */
		if (setup.use_builtin && strcmp(setup.args.builtin.mode, "movie") == 0){
			ctx->kind = ARCAN_FRAMESERVER_INPUT;
		}
/* "libretro" (or rather, interactive mode) treats a single pair of videoframe+audiobuffer
 * each transfer, minimized latency is key. All operations require an intermediate buffer 
 * and are synched to one framequeue */
		else if (setup.use_builtin && strcmp(setup.args.builtin.mode, "libretro") == 0){
			ctx->kind = ARCAN_FRAMESERVER_INTERACTIVE;
			ctx->nopts = true;
			ctx->autoplay = true;
			ctx->sz_audb  = 1024 * 6400;
			ctx->ofs_audb = 0;
			
			ctx->audb = malloc( ctx->sz_audb );
			memset(ctx->audb, 0, ctx->sz_audb );
			ctx->lock_audb = SDL_CreateMutex();
		}
		else if (setup.use_builtin && strcmp(setup.args.builtin.mode, "record") == 0)
		{
			ctx->kind = ARCAN_FRAMESERVER_OUTPUT;
			ctx->nopts = true;
			ctx->autoplay = true;
/* we don't know how many audio feeds are actually monitored to produce the output,
 * thus not how large the intermediate buffer should be to safely accommodate them all */
			ctx->sz_audb = SHMPAGE_AUDIOBUF_SIZE;
			ctx->audb = malloc( ctx->sz_audb );
			memset(ctx->audb, 0, ctx->sz_audb );
			ctx->lock_audb = SDL_CreateMutex();
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
			char* argv[5] = { arcan_binpath, strdup(setup.args.builtin.resource), ctx->shm.key, strdup(setup.args.builtin.mode), NULL };
	
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
