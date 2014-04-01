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
#include <poll.h>

#include <sys/types.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/un.h>
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
	if (!src || src->subsegment)
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
 * sleep + wait cycle, countdown and then send KILL. Other possible
 * idea is (and part of this should be implemented anyway)
 * is to have a session and group, and a plain run a zombie-catcher / kill 
 * broadcaster as a session leader. 
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
	if (!src || !src->child_alive)
		return false;

/* this means that we have a child that we have no monitoring strategy
 * for currently (i.e. non-authorative) */ 
	if (src->child == BROKEN_PROCESS_HANDLE)
		return true;	

/* 
 * Note that on loop conditions, the pid can change, 
 * thus we have to assume it will be valid in the near future. 
 * PID != privilege, it's simply a process to monitor as hint
 * to what the state of a child is, the child is free to 
 * redirect to anything (heck, including init)..
 */ 
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

static bool shmalloc(arcan_frameserver* ctx, 
	bool namedsocket, const char* optkey)
{
	size_t shmsize = ARCAN_SHMPAGE_MAX_SZ;
	struct arcan_shmif_page* shmpage;
	int shmfd = 0;

	ctx->shm.key = arcan_findshmkey(&shmfd, true);
	ctx->shm.shmsize = shmsize;

	char* work = strdup(ctx->shm.key);
	work[strlen(work) - 1] = 'v';
	ctx->vsync = sem_open(work, 0);
	work[strlen(work) - 1] = 'a';
	ctx->async = sem_open(work, 0);
	work[strlen(work) - 1] = 'e';
	ctx->esync = sem_open(work, 0);

/*
 * Named domain sockets are used for non-authoritative connections
 * it enforces a build-time prefix (non / path means apply homedir env)
 * but an optkey can be specified to override default arcan_%d_%d part
 * note the odd length requirements of sun_path though.
 */
	if (namedsocket){
		if (optkey == NULL || strlen(optkey) == 0){
			arcan_warning("posix/frameserver.c:shmalloc(), named socket "
				"connected requested but with empty/missing key. cannot "
				"setup frameserver connectionpoint.\n");
			goto fail;
		}

		struct sockaddr_un addr;
		int fd = socket(AF_UNIX, SOCK_STREAM, 0);
		memset(&addr, '\0', sizeof(addr));
		addr.sun_family = AF_UNIX;
	
		size_t baselen = sizeof(ARCAN_SHM_PREFIX);
		size_t auxsz = 0;
		const char* auxp = "", (* auxv) = "";

		if (ARCAN_SHM_PREFIX[0] != '/' 
#ifdef __linux
&& ARCAN_SHM_PREFIX[0] != '\0'
#endif
		){
			auxp = getenv("HOME");
			if (!auxp){
				arcan_warning("posix/frameserver.c:shmalloc(), compile-time "
					"prefix set to home but HOME environment missing, cannot "
					"setup frameserver connectionpoint.\n");
				goto fail;
			}
			auxv = "/";
			auxsz += strlen(auxp) + 1;
		}

		size_t full_len = baselen + auxsz + (optkey ? strlen(optkey) : 11);
		arcan_event ev;
		size_t msg_sz = sizeof(ev.data.target.message) - 1;
		size_t max_sz = sizeof(addr.sun_path) - 1 > msg_sz ? 
			msg_sz : sizeof(addr.sun_path) - 1;
	
		if (full_len > max_sz){
				arcan_fatal("posix/frameserver.c:shmalloc(), compile-time prefix "
				"yielded a length that is not suitable for a domain socket "
				"i.e. %s%s%s should be %d characters or less\n", auxp,
				ARCAN_SHM_PREFIX, optkey?optkey: "_num_num", max_sz); 
		}

		int retrc = 10;
		if (optkey != NULL)
			retrc = 1;
	
/* this makes things not particularly thread safe, but we should not 
 * be in a multithreaded context anyhow */
		mode_t cumask = umask(0);
		umask(ARCAN_SHM_UMASK);
		while(1){
			if (optkey != NULL)
				snprintf(addr.sun_path, sizeof(addr.sun_path), 
					"%s%s%s", auxp, auxv, optkey);
			else
/* this is not an obfuscation or security mechanism as the namespaces may well
 * be enumerable, it is simply to reduce the chance of beign collisions */
				snprintf(addr.sun_path, sizeof(addr.sun_path), "%s/%s_%i_%i", auxp,
					ARCAN_SHM_PREFIX, getpid() % 1000, rand() % 1000);

			unlink(addr.sun_path);

			if (bind(fd, (struct sockaddr*) &addr, sizeof(addr)) == 0)
				break;
			else if (--retrc == 0){
				arcan_warning("posix/frameserver.c:shmalloc(), couldn't setup "
					"domain socket for frameserver connectionpoint, check "
					"path permissions (%s), reason:%s\n",addr.sun_path,strerror(errno));
				umask(cumask);
				goto fail;
			}
		}
		umask(cumask);

		listen(fd, 1);
		ctx->sockout_fd = fd;

/* track output socket separately so we can unlink on exit,
 * other options (readlink on proc) or F_GETPATH are unportable
 * (and in the case of readlink .. /facepalm) */ 
		ctx->source = strdup(addr.sun_path);
	}

/* max videoframesize + DTS + structure + maxaudioframesize,
* start with max, then truncate down to whatever is actually used */
	int rc = ftruncate(shmfd, shmsize);
	if (-1 == rc){
		arcan_warning("arcan_frameserver_spawn_server(unix) -- allocating"
		"	(%d) shared memory failed (%d).\n", shmsize, errno);
		return false;
	}

	shmpage = (void*) mmap(NULL, shmsize, PROT_READ | PROT_WRITE, 
		MAP_SHARED, shmfd, 0);
	close(shmfd);

	if (MAP_FAILED == shmpage){
		arcan_warning("arcan_frameserver_spawn_server(unix) -- couldn't "
			"allocate shmpage\n");

fail:
		arcan_frameserver_dropsemaphores_keyed(work);
		free(work);
		return false;
	}

	memset(shmpage, '\0', shmsize);
 	shmpage->dms = true;	
	shmpage->parent = getpid();
	shmpage->major = ARCAN_VERSION_MAJOR;
	shmpage->minor = ARCAN_VERSION_MINOR;
	ctx->shm.ptr = shmpage;
	free(work);

	return true;	
}	

/*
 * Allocate a new segment (shmalloc), inherit the relevant
 * tracking members from the parent, re-use the segment
 * to notify the new key to be used, mark the segment as 
 * pending and set a transitional feed-function that
 * looks for an ident on the socket.
 */
arcan_frameserver* arcan_frameserver_spawn_subsegment(
	arcan_frameserver* ctx, bool input)
{
	if (!ctx || ctx->child_alive == false)
		return NULL;
	
	arcan_frameserver* newseg = arcan_frameserver_alloc();
	if (!newseg)
		return NULL;

	if (!shmalloc(newseg, true, NULL)){
		arcan_frameserver_free(newseg, false);
		return NULL;
	}
		
/*
 * Display object (default at 32x32x4, nothing will be activated
 * until first resize) as per arcan_frameserver_emptyframe
 */	
	img_cons cons = {.w = 32, .h = 32, .bpp = 4};
	vfunc_state state = {.tag = ARCAN_TAG_FRAMESERV, .ptr = newseg};
	arcan_frameserver_meta vinfo = {
		.width = 32, 
		.height = 32, 
		.bpp = GL_PIXEL_BPP
	};
	arcan_vobj_id newvid = arcan_video_addfobject((arcan_vfunc_cb)
		arcan_frameserver_emptyframe, state, cons, 0);

	if (newvid == ARCAN_EID){
		arcan_frameserver_free(newseg, false);
		return NULL;
	}

/*
 * Currently, we're reserving a rather aggressive amount of memory
 * for audio, even though it's likely that (especially for multiple-
 * segments) it will go by unused. For arcan->frameserver data transfers
 * we shouldn't have an AID, attach monitors and synch audio transfers
 * to video.
 */
	arcan_errc errc;
	if (!input)
		newseg->aid = arcan_audio_feed((arcan_afunc_cb)
			arcan_frameserver_audioframe_direct, ctx, &errc);

 	newseg->desc = vinfo;
	newseg->source = ctx->source ? strdup(ctx->source) : NULL;
	newseg->vid = newvid;
	newseg->use_pbo = ctx->use_pbo;

/* Transfer the new event socket, along with
 * the base-key that will be used to find shmetc.
 * There is little other than convenience that makes
 * us re-use the other parts of the shm setup routine,
 * we could've sent the shm and semaphores this way as well */
	arcan_frameserver_pushfd(ctx, newseg->sockout_fd);	

	arcan_event keyev = {
		.category = EVENT_TARGET,
		.kind = TARGET_COMMAND_NEWSEGMENT
	};

	snprintf(keyev.data.target.message,
		sizeof(keyev.data.target.message) / sizeof(keyev.data.target.message[1]),
	"%s", newseg->shm.key);

/*
 * We monitor the same PID (but on frameserver_free, 
 */
	newseg->launchedtime = arcan_timemillis();
	newseg->child = ctx->child;
	newseg->child_alive = true;

/* NOTE: should we allow some segments to map events
 * with other masks, or should this be a separate command
 * with a heavy warning? i.e. allowing EVENT_INPUT gives
 * remote-control etc. options, with all the security considerations
 * that comes with it */	
	newseg->queue_mask = EVENT_EXTERNAL;

/*
 * Memory- constraints and future refactoring plans means that
 * AVFEED/INTERACTIVE are the only supported subtypes (never buffered
 * INPUT á movie
 */
	newseg->autoplay = true;
	if (input){
		newseg->kind = ARCAN_FRAMESERVER_OUTPUT;
		newseg->socksig = true;
		newseg->nopts = true;
		keyev.data.target.ioevs[0].iv = 1;
	}
	else {
		newseg->kind = ARCAN_FRAMESERVER_INTERACTIVE;
		newseg->socksig = true;
		newseg->nopts = true;
	}

/*
 * NOTE: experiment with deferring this step as new segments likely
 * won't need / use audio, "Mute" shmif- sessions should also be 
 * permitted to cut down on shm memory use 
 */
	newseg->sz_audb = ARCAN_SHMPAGE_AUDIOBUF_SZ; 
	newseg->ofs_audb = 0;
	newseg->audb = malloc(ctx->sz_audb);

	arcan_shmif_setevqs(newseg->shm.ptr, newseg->esync, 
		&(newseg->inqueue), &(newseg->outqueue), true);
	newseg->inqueue.synch.killswitch = (void*) newseg;
	newseg->outqueue.synch.killswitch = (void*) newseg;

	arcan_event_enqueue(&ctx->outqueue, &keyev);
	return newseg;	
}

/*
 * When we are in this callback state, it means that there's
 * a VID connected to a frameserver that is waiting for a non-authorative
 * connection. (Pending state), to monitor for suspicious activity,
 * maintain a counter here and/or add a timeout and propagate a 
 * "frameserver terminated" session [not implemented].
 *
 * Note that we dont't track the PID of the client here,
 * as the implementation for passing credentials over sockets is exotic
 * (BSD vs Linux etc.) so part of the 'non-authoritative' bit is that
 * the server won't kill-signal or check if pid is still alive in this mode.
 *
 * (listen) -> socketpoll (connection) -> socketverify -> (key ? wait) -> ok -> 
 * send connection data, set emptyframe.  
 * 
 */
static int8_t socketverify(enum arcan_ffunc_cmd cmd, uint8_t* buf,
	uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned mode,
	vfunc_state state)
{
	arcan_frameserver* tgt = state.ptr;
	char ch;
	size_t ntw;
	
	switch (cmd){
	case ffunc_poll:
		if (!tgt->clientkey)
			goto send_key;

/* only need a few characters, so can get away with not having a more
 * elaborate buffering strategy */
		while (-1 != read(tgt->sockout_fd, &ch, 1)){
			if (ch == '\n'){
				tgt->sockinbuf[tgt->sockrofs] = '\0';
				if (strcmp(tgt->sockinbuf, tgt->clientkey) == 0)
					goto send_key;
				arcan_warning("platform/frameserver.c(), key verification failed on %"
					PRIxVOBJ", received: %s\n", tgt->vid, tgt->sockinbuf);
				tgt->child_alive = false;
			}
			else
				tgt->sockinbuf[tgt->sockrofs++] = ch;

			if (tgt->sockrofs >= PP_SHMPAGE_SHMKEYLIM){
				arcan_warning("platform/frameserver.c(), socket "
					"verify failed on %"PRIxVOBJ", terminating.\n", tgt->vid);
/* will terminate the frameserver session */
				tgt->child_alive = false; 
			}
		}
		if (errno != EAGAIN && errno != EINTR){
			arcan_warning("platform/frameserver.c(), "
				"read broken on %"PRIxVOBJ", reason: %s\n", tgt->vid); 
			tgt->child_alive = false;
		}
		return FFUNC_RV_NOFRAME;

	case ffunc_destroy:
		if (tgt->clientkey){
			free(tgt->clientkey);
			tgt->clientkey = NULL;			
		}
	default:
		return FFUNC_RV_NOFRAME;
	break;	
	}


/* switch to resize polling default handler */
send_key:
	arcan_warning("platform/frameserver.c(), connection verified.\n");
	if (tgt->clientkey){
		free(tgt->clientkey);
		tgt->clientkey = NULL;
	}

	ntw = snprintf(tgt->sockinbuf, PP_SHMPAGE_SHMKEYLIM, "%s\n", tgt->shm.key);
	write(tgt->sockout_fd, tgt->sockinbuf, ntw); 

	arcan_video_alterfeed(tgt->vid,
		arcan_frameserver_emptyframe, state);

	arcan_errc errc;	
	tgt->aid = arcan_audio_feed((arcan_afunc_cb)
		arcan_frameserver_audioframe_direct, tgt, &errc);
	tgt->sz_audb = 1024 * 64;
	tgt->audb = malloc(tgt->sz_audb);

	return FFUNC_RV_NOFRAME;
}

static int8_t socketpoll(enum arcan_ffunc_cmd cmd, uint8_t* buf,
	uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned mode,
	vfunc_state state)
{
	arcan_frameserver* tgt = state.ptr;
	struct arcan_shmif_page* shmpage = tgt->shm.ptr;

	if (state.tag != ARCAN_TAG_FRAMESERV || !shmpage){
		arcan_warning("platform/posix/frameserver.c:socketpoll, called with"
			" invalid source tag, investigate.\n");
		return FFUNC_RV_NOFRAME;
	}

	struct pollfd polldscr = {
		.fd = tgt->sockout_fd,
		.events = POLLIN	
	};

/* wait for connection, then unlink directory node,
 * switch to verify callback.*/ 
	switch (cmd){
		case ffunc_poll:
			if (1 == poll(&polldscr, 1, 0)){
				int insock = accept(polldscr.fd, NULL, NULL);
				if (insock != -1){
					close(polldscr.fd);
				tgt->sockout_fd = insock;
				fcntl(insock, O_NONBLOCK);
				arcan_video_alterfeed(tgt->vid, socketverify, state);
				if (tgt->sockaddr){
					unlink(tgt->sockaddr);
					free(tgt->sockaddr);
					tgt->sockaddr = NULL;
				}

				return socketverify(cmd, buf, s_buf, width, height, bpp, mode, state);
				}
				else if (errno == EFAULT || errno == EINVAL)
					tgt->child_alive = false;		
			}
		break;

/* socket is closed in frameserver_destroy */
		case ffunc_destroy:
			arcan_frameserver_free(tgt, false);
			if (tgt->sockaddr){
				unlink(tgt->sockaddr);
				free(tgt->sockaddr);
				tgt->sockaddr = NULL;
			}
			if (tgt->clientkey){
				free(tgt->clientkey);
				tgt->clientkey = NULL;
			}
		default:
		break;
	}

	return FFUNC_RV_NOFRAME;
}

arcan_frameserver* arcan_frameserver_listen_external(const char* key)
{
	arcan_frameserver* res = arcan_frameserver_alloc();
	if (!shmalloc(res, true, key)){
		arcan_warning("arcan_frameserver_listen_external(), shared memory"
			" setup failed\n");
		return NULL;
	}

/* 
 * defaults for an external connection is similar to that of avfeed/libretro 
 */
	res->kind = ARCAN_FRAMESERVER_INTERACTIVE;
	res->socksig = false;
	res->nopts = true;
	res->autoplay = true;
	res->pending = true;
	res->launchedtime = arcan_timemillis();
	res->child = BROKEN_PROCESS_HANDLE; 
	img_cons cons = {.w = 32, .h = 32, .bpp = 4};
	vfunc_state state = {.tag = ARCAN_TAG_FRAMESERV, .ptr = res};

	res->vid = arcan_video_addfobject((arcan_vfunc_cb)
		socketpoll, state, cons, 0);

/*
 * audio setup is deferred until the connection has been acknowledged
 * and verified, but since this call yields a valid VID, we need to have
 * the queues in place.
 */
	res->queue_mask = EVENT_EXTERNAL;
	arcan_shmif_setevqs(res->shm.ptr, res->esync, 
		&(res->inqueue), &(res->outqueue), true);
	res->inqueue.synch.killswitch = (void*) res;
	res->outqueue.synch.killswitch = (void*) res;

	return res;	
}

arcan_errc arcan_frameserver_spawn_server(arcan_frameserver* ctx, 
	struct frameserver_envp setup)
{
	if (ctx == NULL)
		return ARCAN_ERRC_BAD_ARGUMENT;

	shmalloc(ctx, false, NULL);

	ctx->launchedtime = arcan_frametime();

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
		if (ctx->vid == ARCAN_EID){
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
			snprintf(shmsize_s, 32, "%zu", ctx->shm.shmsize);
			
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
		arcan_fatal("fork() failed, check ulimit or similar configuration issue.");
		
	return ARCAN_OK;
}
