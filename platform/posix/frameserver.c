/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
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

#include <arcan_math.h>
#include <arcan_general.h>
#include <arcan_event.h>
#include <arcan_framequeue.h>
#include <arcan_video.h>
#include <arcan_audio.h>	
#include <arcan_frameserver_backend.h>
#include <arcan_shmif.h>

#define INCR(X, C) ( ( (X) = ( (X) + 1) % (C)) )

/* NOTE: maintaing pid_t for frameserver (or worse, for hijacked target)
 * should really be replaced by making sure they belong to the same process
 * group and first send a close signal to the group, and thereafter KILL */

extern char* arcan_binpath;

/* dislike resorting to these kinds of antics, but it was among the cleaner
 * solutions given the portability constraints (OSX,Win32) */
static void* nanny_thread(void* arg)
{
	pid_t* pid = (pid_t*) arg;
	
	if (pid){
		int counter = 60;
		
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

void arcan_frameserver_dropshared(arcan_frameserver* src)
{
	if (!src)
		return;
	
	struct arcan_shmif_page* shmpage = src->shm.ptr;

	if (shmpage && -1 == munmap((void*) shmpage, src->shm.shmsize))
		arcan_warning("BUG -- arcan_frameserver_free(), munmap failed: %s\n",
			strerror(errno));
			
	shm_unlink( src->shm.key );
	free(src->shm.key);
}

void arcan_frameserver_killchild(arcan_frameserver* src)
{
	if (!src)
		return;

/* 
 * this one is more complicated than it seems, as we don't want zombies 
 * lying around, yet might be in a context where the child is no-longer 
 * trusted. Double-forking and getting the handle that way is 
 * overcomplicated, maintaining a state-table of assumed-alive children 
 * until wait says otherwise and then map may lead to dangling pointers
 * with video_deleteobject or sweeping the full state context etc.
 * 
 * Cheapest, it seems, is to actually spawn a guard thread with a 
 * sleep + wait cycle, countdown and then send KILL
 */
	pid_t* pidptr = malloc(sizeof(pid_t));
	pthread_t pthr;
	*pidptr = src->child;

	if (0 != pthread_create(&pthr, NULL, nanny_thread, (void*) pidptr)){
		kill(src->child, SIGKILL);
	}
}

bool arcan_frameserver_validchild(arcan_frameserver* src){
	int status;

/* free (consequence of a delete call on the associated vid)
 * will disable the child_alive flag */
	if (!src || !src->child_alive || !src->child)
		return false;

/* note that on loop conditions, the pid can change, this we have to assume
 * it will be valid in the near future. */ 
	int ec = waitpid(src->child, &status, WNOHANG);

	if (ec == src->child){
		src->child_alive = false;
		errno = EINVAL;
		return false;
	} 
	else
	 	return true;	
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
			.msg_controllen = CMSG_LEN(sizeof(int))
		};

		struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
		cmsg->cmsg_len = msg.msg_controllen;
		cmsg->cmsg_level = SOL_SOCKET;
		cmsg->cmsg_type  = SCM_RIGHTS;
		int* dptr = (int*) CMSG_DATA(cmsg);
		*dptr = fd;
		
		if (sendmsg(fsrv->sockout_fd, &msg, 0) >= 0){
			rv = ARCAN_OK;
			arcan_event ev = {
				.category = EVENT_TARGET,
				.kind = TARGET_COMMAND_FDTRANSFER
			};
			
			arcan_frameserver_pushevent( fsrv, &ev );
		}
		else
			arcan_warning("frameserver_pushfd(%d->%d) failed, reason(%d) : %s\n", 
				fd, fsrv->sockout_fd, errno, strerror(errno));
	}
	
	close(fd);
	return rv;
}


arcan_errc arcan_frameserver_spawn_server(arcan_frameserver* ctx, 
	struct frameserver_envp setup)
{
	if (ctx == NULL)
		return ARCAN_ERRC_BAD_ARGUMENT;

	size_t shmsize = ARCAN_SHMPAGE_MAX_SZ;
	struct arcan_shmif_page* shmpage;
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
	int rc = ftruncate(shmfd, shmsize);
	if (-1 == rc){
		arcan_warning("arcan_frameserver_spawn_server(unix) -- allocating"
		"	(%d) shared memory failed (%d).\n", shmsize, errno);
		goto error_cleanup;
	}
	
	shmpage = (void*) mmap(NULL, shmsize, PROT_READ | PROT_WRITE, 
		MAP_SHARED, shmfd, 0);
	close(shmfd);

	if (MAP_FAILED == shmpage){
		arcan_warning("arcan_frameserver_spawn_server(unix) -- couldn't "
			"allocate shmpage\n");
		goto error_cleanup;
	}

	memset(shmpage, '\0', shmsize);
 	shmpage->dms = true;	
	shmpage->parent = getpid();
	shmpage->major = ARCAN_VERSION_MAJOR;
	shmpage->minor = ARCAN_VERSION_MINOR;

	int sockp[2] = {-1, -1};
	if ( socketpair(PF_UNIX, SOCK_DGRAM, 0, sockp) < 0 ){
		arcan_warning("arcan_frameserver_spawn_server(unix) -- couldn't "
			"get socket pair\n");
	}

	pid_t child = fork();
	if (child) {
		close(sockp[1]);

/* 
 * init- call (different from loop-exec as we need to 
 * keep the vid / aud as they are external references into the 
 * scripted state-space 
 */
		if (ctx->vid == ARCAN_EID) {
			img_cons cons = {.w = 32, .h = 32, .bpp = 4};
			vfunc_state state = {.tag = ARCAN_TAG_FRAMESERV, .ptr = ctx};

			ctx->source = strdup(setup.args.builtin.resource);
			ctx->vid = arcan_video_addfobject((arcan_vfunc_cb)
				arcan_frameserver_emptyframe, state, cons, 0);
			ctx->aid = ARCAN_EID;
		}
		else if (setup.custom_feed == false){ 
			vfunc_state* cstate = arcan_video_feedstate(ctx->vid);
			arcan_video_alterfeed(ctx->vid, (arcan_vfunc_cb)
				arcan_frameserver_emptyframe, *cstate); 
/* revert back to empty vfunc? */
		}

		ctx->shm.ptr     = (void*) shmpage;
		ctx->shm.shmsize = shmsize;
		ctx->sockout_fd  = sockp[0];
		ctx->child       = child;

		arcan_frameserver_configure(ctx, setup);
	
	} else if (child == 0) {
		char convb[8];
	
/*
 * this little thing is used to push file-descriptors between 
 * parent and child, as to not expose child to parents namespace, 
 * and to improve privilege separation 
 */
		close(sockp[0]);
		sprintf(convb, "%i", sockp[1]);
		setenv("ARCAN_SOCKIN_FD", convb, 1);

/*
 * we need to mask this signal as when debugging parent process, 
 * GDB pushes SIGINT to children, killing them and changing
 * the behavior in the core process 
 */
		signal(SIGINT, SIG_IGN);
	
		if (setup.use_builtin){
			char* argv[5] = { 
				arcan_binpath, 
				strdup(setup.args.builtin.resource), 
				ctx->shm.key, 
				strdup(setup.args.builtin.mode), 
			NULL};
	
			execv(arcan_binpath, argv);
			arcan_fatal("FATAL, arcan_frameserver_spawn_server(), "
				"couldn't spawn frameserver(%s) with %s:%s. Reason: %s\n", 
				arcan_binpath, setup.args.builtin.mode, 
				setup.args.builtin.resource, strerror(errno));
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

			execv(setup.args.external.fname, setup.args.external.argv);
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
