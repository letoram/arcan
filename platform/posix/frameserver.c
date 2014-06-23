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
#include <arcan_shmif.h>
#include <arcan_event.h>
#include <arcan_video.h>
#include <arcan_audio.h>	
#include <arcan_frameserver_backend.h>

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
		int counter = 10;
		
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

/* step 2, semaphore handles */
	char* work = strdup(src->shm.key);
	work[strlen(work) - 1] = 'v';
	sem_unlink(work);

	work[strlen(work) - 1] = 'a';
	sem_unlink(work);

	work[strlen(work) - 1] = 'e';
	sem_unlink(work);
	free(work);

	arcan_mem_free(src->shm.key);
}

void arcan_frameserver_killchild(arcan_frameserver* src)
{
	if (!src || src->flags.subsegment)
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
	if (!src || !src->flags.alive)
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
		src->flags.alive = false;
		errno = EINVAL;
		return false;
	} 
	else
	 	return true;	
}

arcan_errc arcan_frameserver_pushfd(arcan_frameserver* fsrv, int fd)
{
	if (!fsrv || fd == 0)
		return ARCAN_ERRC_BAD_ARGUMENT; 
	
	if (arcan_pushhandle(fd, fsrv->sockout_fd)){
		arcan_event ev = {
			.category = EVENT_TARGET,
			.kind = TARGET_COMMAND_FDTRANSFER
		};
		
		arcan_frameserver_pushevent( fsrv, &ev );
		return ARCAN_OK;
	}

	arcan_warning("frameserver_pushfd(%d->%d) failed, reason(%d) : %s\n", 
		fd, fsrv->sockout_fd, errno, strerror(errno));
	
	return ARCAN_ERRC_BAD_ARGUMENT;
}

static bool shmalloc(arcan_frameserver* ctx, 
	bool namedsocket, const char* optkey)
{
	size_t shmsize = ARCAN_SHMPAGE_START_SZ;
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

	if (namedsocket){
		size_t optlen;
		struct sockaddr_un addr;
		size_t lim = sizeof(addr.sun_path) / sizeof(addr.sun_path[0]) - 1;
		size_t pref_sz = sizeof(ARCAN_SHM_PREFIX) - 1;

		if (optkey == NULL || (optlen = strlen(optkey)) == 0 || 
			pref_sz + optlen > lim){
			arcan_warning("posix/frameserver.c:shmalloc(), named socket "
				"connected requested but with empty/missing/oversized key. cannot "
				"setup frameserver connectionpoint.\n");
			goto fail;
		}

		int fd = socket(AF_UNIX, SOCK_STREAM, 0);
		if (fd == -1){
			arcan_warning("posix/frameserver.c:shmalloc(), could allocate socket "
				"for listening, check permissions and descriptor ulimit.\n");
			goto fail;
		}
		fcntl(fd, F_SETFD, FD_CLOEXEC);

		memset(&addr, '\0', sizeof(addr));
		addr.sun_family = AF_UNIX;
		char* dst = (char*) &addr.sun_path;
	
#ifdef __linux
		if (ARCAN_SHM_PREFIX[0] == '\0')
		{
			memcpy(dst, ARCAN_SHM_PREFIX, pref_sz);
			dst += sizeof(ARCAN_SHM_PREFIX) - 1;
			memcpy(dst, optkey, optlen); 
		}
		else
#endif
		if (ARCAN_SHM_PREFIX[0] != '/'){
			char* auxp = getenv("HOME");
			if (!auxp){
				arcan_warning("posix/frameserver.c:shmalloc(), compile-time "
					"prefix set to home but HOME environment missing, cannot "
					"setup frameserver connectionpoint.\n");
				close(fd);
				goto fail;
			}
			
			size_t envlen = strlen(auxp);
			if (envlen + optlen + pref_sz > lim){
				arcan_warning("posix/frameserver.c:shmalloc(), applying built-in "
					"prefix and resolving username exceeds socket path limit.\n");
				close(fd);
				goto fail;
			}
		
			memcpy(dst, auxp, envlen);
			dst += envlen;
			*dst++ = '/';
			memcpy(dst, ARCAN_SHM_PREFIX, pref_sz);
			dst += pref_sz;
			memcpy(dst, optkey, optlen);
		} 
/* use prefix in its full form */
		else {
			memcpy(dst, ARCAN_SHM_PREFIX, pref_sz);
			dst += pref_sz;
			memcpy(dst, optkey, optlen);
		}

/* this makes things not particularly thread safe, but we should not 
 * be in a multithreaded context anyhow */

		unlink(addr.sun_path);
		if (bind(fd, (struct sockaddr*) &addr, sizeof(addr)) != 0){
			arcan_warning("posix/frameserver.c:shmalloc(), couldn't setup "
				"domain socket for frameserver connectionpoint, check "
				"path permissions (%s), reason:%s\n",addr.sun_path,strerror(errno));
			close(fd);
			goto fail;
		}

		fchmod(fd, ARCAN_SHM_UMASK);
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

	ctx->shm.handle = shmfd;
	shmpage = (void*) mmap(
		NULL, shmsize, PROT_READ | PROT_WRITE, MAP_SHARED, shmfd, 0);

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
	shmpage->segment_size = shmsize;
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
	arcan_frameserver* ctx, bool input, int hintw, int hinth, int tag)
{
	if (!ctx || ctx->flags.alive == false)
		return NULL;
	
	arcan_frameserver* newseg = arcan_frameserver_alloc();
	if (!shmalloc(newseg, false, NULL)){
		arcan_frameserver_free(newseg);
		return NULL;
	}

	if (!newseg)
		return NULL;

	hintw = hintw < 0 || hintw > ARCAN_SHMPAGE_MAXW ? 32 : hintw;
	hinth = hinth < 0 || hinth > ARCAN_SHMPAGE_MAXH ? 32 : hinth;

	img_cons cons = {.w = hintw , .h = hinth, .bpp = ARCAN_SHMPAGE_VCHANNELS};
	vfunc_state state = {.tag = ARCAN_TAG_FRAMESERV, .ptr = newseg};
	arcan_frameserver_meta vinfo = {
		.width = hintw, 
		.height = hinth, 
		.bpp = GL_PIXEL_BPP
	};
	arcan_vobj_id newvid = arcan_video_addfobject((arcan_vfunc_cb)
		arcan_frameserver_emptyframe, state, cons, 0);

	if (newvid == ARCAN_EID){
		arcan_frameserver_free(newseg);
		return NULL;
	}

/*
 * set these before pushing to the child to avoid a possible race 
 */
	newseg->shm.ptr->w = hintw;
	newseg->shm.ptr->h = hinth;

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
	newseg->flags.pbo = ctx->flags.pbo;
	newseg->flags.subsegment = true;

/* Transfer the new event socket, along with
 * the base-key that will be used to find shmetc.
 * There is little other than convenience that makes
 * us re-use the other parts of the shm setup routine,
 * we could've sent the shm and semaphores this way as well */
	int sockp[2] = {-1, -1};
	if ( socketpair(PF_UNIX, SOCK_DGRAM, 0, sockp) < 0 ){
		arcan_warning("arcan_frameserver_spawn_server(unix) -- couldn't "
			"get socket pair\n");
	}
	else {
		fcntl(sockp[0], F_SETFD, FD_CLOEXEC);
    fcntl(sockp[1], F_SETFD, FD_CLOEXEC);
  	newseg->sockout_fd = sockp[0];
		arcan_frameserver_pushfd(ctx, sockp[1]);
	}
  
	arcan_event keyev = {
		.category = EVENT_TARGET,
		.kind = TARGET_COMMAND_NEWSEGMENT,
		.data.target.ioevs[0].iv = input ? 1 : 0,
		.data.target.ioevs[1].iv = tag 
	};

	snprintf(keyev.data.target.message,
		sizeof(keyev.data.target.message) / sizeof(keyev.data.target.message[1]),
		"%s", newseg->shm.key);

/*
 * We monitor the same PID (but on frameserver_free, 
 */
	newseg->launchedtime = arcan_timemillis();
	newseg->child = ctx->child;
	newseg->flags.alive = true;

/* NOTE: should we allow some segments to map events
 * with other masks, or should this be a separate command
 * with a heavy warning? i.e. allowing EVENT_INPUT gives
 * remote-control etc. options, with all the security considerations
 * that comes with it */	
	newseg->queue_mask = EVENT_EXTERNAL;

/*
 * Memory- constraints and future refactoring plans means that
 * AVFEED/INTERACTIVE are the only supported subtypes 
 */
	if (input){
		newseg->kind = ARCAN_FRAMESERVER_OUTPUT;
		newseg->flags.socksig = true;
		keyev.data.target.ioevs[0].iv = 1;
		keyev.data.target.ioevs[1].iv = tag;
	}
	else {
		newseg->kind = ARCAN_FRAMESERVER_INTERACTIVE;
		newseg->flags.socksig = true;
	}

/*
 * NOTE: experiment with deferring this step as new segments likely
 * won't need / use audio, "Mute" shmif- sessions should also be 
 * permitted to cut down on shm memory use 
 */
	newseg->sz_audb = ARCAN_SHMPAGE_AUDIOBUF_SZ; 
	newseg->ofs_audb = 0;
	newseg->audb = malloc(ctx->sz_audb);

	arcan_shmif_calcofs(newseg->shm.ptr, &(newseg->vidp), &(newseg->audp));
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
static bool memcmp_nodep(const void* s1, const void* s2, size_t n)
{
	const uint8_t* p1 = s1;
	const uint8_t* p2 = s2;

	uint8_t diffv = 0;

	while (n--){
		diffv |= *p1++ ^ *p2++;	
	}

	return !(diffv != 0);
}

static enum arcan_ffunc_rv socketverify(enum arcan_ffunc_cmd cmd, uint8_t* buf,
	uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned mode,
	vfunc_state state)
{
	arcan_frameserver* tgt = state.ptr;
	char ch;
	size_t ntw;

	switch (cmd){
	case FFUNC_POLL:
		if (tgt->clientkey[0] == '\0')
			goto send_key;

/* only need a few characters, so can get away with not having a more
 * elaborate buffering strategy */
		while (-1 != read(tgt->sockout_fd, &ch, 1)){
			if (ch == '\n'){
/* 0- pad to max length */
				memset(tgt->sockinbuf + tgt->sockrofs, '\0', 
					PP_SHMPAGE_SHMKEYLIM - tgt->sockrofs);

/* alternative memcmp to not be used as a timing oracle */
				if (memcmp_nodep(tgt->sockinbuf, tgt->clientkey, PP_SHMPAGE_SHMKEYLIM))
					goto send_key;

				arcan_warning("platform/frameserver.c(), key verification failed on %"
					PRIxVOBJ", received: %s\n", tgt->vid, tgt->sockinbuf);
				tgt->flags.alive = false;
			}
			else
				tgt->sockinbuf[tgt->sockrofs++] = ch;

			if (tgt->sockrofs >= PP_SHMPAGE_SHMKEYLIM){
				arcan_warning("platform/frameserver.c(), socket "
					"verify failed on %"PRIxVOBJ", terminating.\n", tgt->vid);
/* will terminate the frameserver session */
				tgt->flags.alive = false; 
			}
		}
		if (errno != EAGAIN && errno != EINTR){
			arcan_warning("platform/frameserver.c(), "
				"read broken on %"PRIxVOBJ", reason: %s\n", tgt->vid); 
			tgt->flags.alive = false;
		}
		return FFUNC_RV_NOFRAME;

	case FFUNC_DESTROY:
		unlink(tgt->source);
	
	default:
		return FFUNC_RV_NOFRAME;
	break;	
	}

/* switch to resize polling default handler */
send_key:
	arcan_warning("platform/frameserver.c(), connection verified.\n");

/* Note: we here assume that we can write without blocking, which is 
 * usually the case. There might be a DoS opportunity here with a 
 * connection that somehow gets our socket write to block/lock here,
 * if that's ever a real concern, switch to select and just drop connection
 * if we can't write enough. */
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
		case FFUNC_POLL:
			if (1 == poll(&polldscr, 1, 0)){
				int insock = accept(polldscr.fd, NULL, NULL);
				if (insock != -1){
					close(polldscr.fd);
				tgt->sockout_fd = insock;
				fcntl(insock, F_SETFD, O_NONBLOCK);
				arcan_video_alterfeed(tgt->vid, socketverify, state);
				if (tgt->sockaddr){
					unlink(tgt->sockaddr);
					free(tgt->sockaddr);
					tgt->sockaddr = NULL;
				}

				return socketverify(cmd, buf, s_buf, width, height, bpp, mode, state);
				}
				else if (errno == EFAULT || errno == EINVAL)
					tgt->flags.alive = false;		
			}
		break;

/* socket is closed in frameserver_destroy */
		case FFUNC_DESTROY:
			if (tgt->sockaddr){
				unlink(tgt->sockaddr);
				free(tgt->sockaddr);
				tgt->sockaddr = NULL;
			}

			arcan_frameserver_free(tgt);
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
	res->flags.socksig = false;
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

bool arcan_frameserver_resize(shm_handle* src, int w, int h)
{
	w = abs(w);
	h = abs(h);

	size_t sz = arcan_shmif_getsize(w, h);
	if (sz > ARCAN_SHMPAGE_MAX_SZ)
		return false;

/*
 * Don't resize unless the gain is ~20%
 */
	if (sz < src->shmsize && sz > (float)src->shmsize * 0.8)
		return true;

/* create a temporary copy */
	char* tmpbuf = arcan_alloc_mem(sizeof(struct arcan_shmif_page),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_TEMPORARY, ARCAN_MEMALIGN_NATURAL);

	memcpy(tmpbuf, src->ptr, sizeof(struct arcan_shmif_page));

/* unmap + truncate + map */
	munmap(src->ptr, src->shmsize);
	src->shmsize = sz;	
	ftruncate(src->handle, sz);
	src->ptr = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_SHARED, src->handle,0); 
	memcpy(src->ptr, tmpbuf, sizeof(struct arcan_shmif_page));
	src->ptr->segment_size = sz;

	arcan_mem_free(tmpbuf);
	return true;
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
		fcntl(sockp[0], F_SETFD, FD_CLOEXEC);

		img_cons cons = {
			.w = setup.init_w, 
			.h = setup.init_h, 
			.bpp = 4
		};
		vfunc_state state = {
			.tag = ARCAN_TAG_FRAMESERV, 
			.ptr = ctx
		};
	
		ctx->source = strdup(setup.args.builtin.resource);
		ctx->vid = arcan_video_addfobject((arcan_vfunc_cb)
			arcan_frameserver_emptyframe, state, cons, 0);
		ctx->aid = ARCAN_EID;

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
		setenv("ARCAN_ARG", setup.args.builtin.resource, 1);
	
/*
 * frameservers that are semi-trusted currently get an
 * environment variable to help search for theme-relative resources
 */
		char cwdinbuf[ PATH_MAX ];

		if ( getcwd(cwdinbuf, PATH_MAX) ){
			int baselen = strlen(arcan_themename) + strlen(arcan_themepath);
			size_t cwd_sz = PATH_MAX + baselen + 1;
			char cwdbuf[ cwd_sz ]; 
			snprintf(cwdbuf, cwd_sz, "%s/%s/%s", 
					cwdinbuf, arcan_themepath, arcan_themename); 
			setenv("ARCAN_THEMEPATH", cwdbuf, 1);
		}
		else
			setenv("ARCAN_THEMEPATH", ".", 1);

/*
 * we need to mask this signal as when debugging parent process, 
 * GDB pushes SIGINT to children, killing them and changing
 * the behavior in the core process 
 */
		signal(SIGINT, SIG_IGN);
	
		if (setup.use_builtin){
			char* argv[4] = { 
				arcan_binpath, 
				strdup(setup.args.builtin.mode), 
				ctx->shm.key,
				NULL
			};

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
