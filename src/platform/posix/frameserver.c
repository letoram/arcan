/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
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
#include <sys/select.h>
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
#include <arcan_frameserver.h>

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

/*
 * the rather odd structure we want for poll on the verify socket
 */
static bool fd_avail(int fd, bool* term)
{
	struct pollfd fds = {
		.fd = fd,
		.events = POLLIN | POLLERR | POLLHUP | POLLNVAL
	};

	int sv = poll(&fds, 1, 0);
	*term = false;

	if (-1 == sv){
		if (errno != EINTR)
			*term = true;

		return false;
	}

	if (0 == sv)
		return false;

	if (fds.revents & (POLLERR | POLLHUP | POLLNVAL))
		*term = true;
	else
		return true;

	return false;
}

void arcan_frameserver_dropshared(arcan_frameserver* src)
{
	if (!src)
		return;

	if (src->dpipe){
		src->dpipe = -1;
		close(src->dpipe);
	}

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

	src->shm.ptr = NULL;
	arcan_mem_free(src->shm.key);
}

void arcan_frameserver_killchild(arcan_frameserver* src)
{
	if (!src || src->parent != ARCAN_EID)
		return;

/*
 * only kill non-authoritative connections
 */
	if (src->child <= 1)
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

	static bool env_checked;
	static bool no_nanny;

	if (!env_checked)
	{
		env_checked = true;
		if (getenv("ARCAN_DEBUG_NONANNY")){
			unsetenv("ARCAN_DEBUG_NONANNY");
			no_nanny = true;
		}
	}

	if (no_nanny)
		return;

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

/*
 * for non-auth connections, we have few good options of getting
 * a non- race condition prone resource to check for connection
 * status, so use the socket descriptor.
 */
	if (src->child == BROKEN_PROCESS_HANDLE){
		if (src->dpipe > 0){
			int mask = POLLERR | POLLHUP | POLLNVAL;

			struct pollfd fds = {
				.fd = src->dpipe,
				.events = mask
			};

			if ((-1 == poll(&fds, 1, 0) &&
				errno != EINTR) || (fds.revents & mask) > 0)
				return false;
		}

		return true;
	}

/*
 * Note that on loop conditions, the pid can change,
 * thus we have to assume it will be valid in the near future.
 * PID != privilege, it's simply a process to monitor as hint
 * to what the state of a child is, the child is free to
 * redirect to anything (heck, including init)..
 */
	int ec = waitpid(src->child, &status, WNOHANG);

	if (ec == src->child){
		errno = EINVAL;
		return false;
	}
	else
	 	return true;
}

arcan_errc arcan_frameserver_pushfd(
	arcan_frameserver* fsrv, arcan_event* ev, int fd)
{
	if (!fsrv || fd == 0)
		return ARCAN_ERRC_BAD_ARGUMENT;

	arcan_frameserver_pushevent( fsrv, ev );
	if (arcan_pushhandle(fd, fsrv->dpipe))
		return ARCAN_OK;

	arcan_warning("frameserver_pushfd(%d->%d) failed, reason(%d) : %s\n",
		fd, fsrv->dpipe, errno, strerror(errno));

	return ARCAN_ERRC_BAD_ARGUMENT;
}

static bool findshmkey(arcan_frameserver* ctx, int* dfd){
	pid_t selfpid = getpid();
	int retrycount = 10;
	size_t pb_ofs = 0;

	const char pattern[] = "/arcan_%i_%im";
	char playbuf[sizeof(pattern) + 8];

	while (1){
/* not a security mechanism */
		snprintf(playbuf, sizeof(playbuf), pattern, selfpid % 1000, rand() % 1000);

		pb_ofs = strlen(playbuf) - 1;
		*dfd = shm_open(playbuf, O_CREAT | O_RDWR | O_EXCL, 0700);

/*
 * with EEXIST, we happened to have a name collision,
 * it is unlikely, but may happen. for the others however,
 * there is something else going on and there's no point retrying
 */
		if (-1 == *dfd && errno != EEXIST){
			arcan_warning("arcan_findshmkey(), allocating "
				"shared memory, reason: %d\n", errno);
			return false;
		}

		else if (-1 == *dfd){
			if (retrycount-- == 0){
				arcan_warning("arcan_findshmkey(), allocating named "
				"semaphores failed, reason: %d, aborting.\n", errno);
				return false;
			}
		}

		playbuf[pb_ofs] = 'v';
		ctx->vsync = sem_open(playbuf, O_CREAT | O_EXCL, 0700, 0);

		if (SEM_FAILED == ctx->vsync){
			playbuf[pb_ofs] = 'm'; shm_unlink(playbuf);
			close(*dfd);
			continue;
		}

		playbuf[pb_ofs] = 'a';
		ctx->async = sem_open(playbuf, O_CREAT | O_EXCL, 0700, 0);

		if (SEM_FAILED == ctx->async){
			playbuf[pb_ofs] = 'v'; sem_unlink(playbuf); sem_close(ctx->vsync);
			playbuf[pb_ofs] = 'm'; shm_unlink(playbuf);
			close(*dfd);
			continue;
		}

		playbuf[pb_ofs] = 'e';
		ctx->esync = sem_open(playbuf, O_CREAT | O_EXCL, 0700, 1);
		if (SEM_FAILED == ctx->esync){
			playbuf[pb_ofs] = 'a'; sem_unlink(playbuf); sem_close(ctx->async);
			playbuf[pb_ofs] = 'v'; sem_unlink(playbuf); sem_close(ctx->vsync);
			playbuf[pb_ofs] = 'm'; shm_unlink(playbuf);
			close(*dfd);
			continue;
		}

		break;
	}

	playbuf[pb_ofs] = 'm';
	ctx->shm.key = strdup(playbuf);
	return true;
}

static bool sockpair_alloc(int* dst, size_t n, bool cloexec)
{
	bool res = false;
	n*=2;

	for (size_t i = 0; i < n; i+=2){
		res |= socketpair(PF_UNIX, SOCK_STREAM, 0, &dst[i]) != -1;
	}

	if (!res){
		for (size_t i = 0; i < n; i++)
			if (dst[i] != -1){
				close(dst[i]);
				dst[i] = -1;
			}
	}
	else {
		for (size_t i = 0; i < n; i++){
			if (cloexec)
				fcntl(dst[i], F_SETFD, FD_CLOEXEC);
#ifdef __APPLE__
 			int val = 1;
			setsockopt(dst[i], SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
#endif
		}
	}

	return res;
}

/*
 * even if we have a preset listening socket,
 * we run through the routine to generate unlink- target
 * etc. still
 */
static bool setup_socket(arcan_frameserver* ctx, int shmfd,
	const char* optkey, int optdesc)
{
	size_t optlen;
	struct sockaddr_un addr;
	size_t lim = sizeof(addr.sun_path) / sizeof(addr.sun_path[0]) - 1;
	size_t pref_sz = sizeof(ARCAN_SHM_PREFIX) - 1;

	if (optkey == NULL || (optlen = strlen(optkey)) == 0 ||
		pref_sz + optlen > lim){
		arcan_warning("posix/frameserver.c:shmalloc(), named socket "
			"connected requested but with empty/missing/oversized key. cannot "
			"setup frameserver connectionpoint.\n");
		return false;
	}

	int fd = optdesc;
	if (-1 == optdesc){
		fd = socket(AF_UNIX, SOCK_STREAM, 0);
		if (fd == -1){
			arcan_warning("posix/frameserver.c:shmalloc(), could allocate socket "
				"for listening, check permissions and descriptor ulimit.\n");
			return false;
		}
	fcntl(fd, F_SETFD, FD_CLOEXEC);
	}

	memset(&addr, '\0', sizeof(addr));
	addr.sun_family = AF_UNIX;
	char* dst = (char*) &addr.sun_path;

#ifdef __linux
	if (ARCAN_SHM_PREFIX[0] == '\0'){
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
			return false;
		}

		size_t envlen = strlen(auxp);
		if (envlen + optlen + pref_sz > lim){
			arcan_warning("posix/frameserver.c:shmalloc(), applying built-in "
				"prefix and resolving username exceeds socket path limit.\n");
			close(fd);
			return false;
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

	if (-1 == optdesc){
/*
 * if we happen to have a stale listener, unlink it but only if it
 * has been used as a domain-socket in beforehand (so in the worst
 * case, some lets a user set this path and it is maliciously used
 * to unlink files.
 */
		if (addr.sun_path[0] == '\0')
			unlink(addr.sun_path);
		else{
			struct stat buf;
			int rv = stat(addr.sun_path, &buf);
			if ( (-1 == rv && errno != ENOENT)||(0 == rv && !S_ISSOCK(buf.st_mode))){
				close(fd);
				return false;
			}
			else if (0 == rv)
				unlink(addr.sun_path);
		}

		if (bind(fd, (struct sockaddr*) &addr, sizeof(addr)) != 0){
			arcan_warning("posix/frameserver.c:shmalloc(), couldn't setup "
				"domain socket for frameserver connectionpoint, check "
				"path permissions (%s), reason:%s\n",addr.sun_path,strerror(errno));
			close(fd);
			return false;
		}

		fchmod(fd, ARCAN_SHM_UMASK);
		listen(fd, 1);
#ifdef __APPLE__
		int val = 1;
		setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
#endif
	}

	ctx->dpipe = fd;
/* track output socket separately so we can unlink on exit,
 * other options (readlink on proc) or F_GETPATH are unportable
 * (and in the case of readlink .. /facepalm) */
	ctx->sockaddr = strdup(addr.sun_path);
	ctx->sockkey = strdup(optkey);
	return true;
}

static bool shmalloc(arcan_frameserver* ctx,
	bool namedsocket, const char* optkey, int optdesc)
{
	if (0 == ctx->shm.shmsize)
		ctx->shm.shmsize = ARCAN_SHMPAGE_START_SZ;

	struct arcan_shmif_page* shmpage;
	int shmfd = 0;

	if (!findshmkey(ctx, &shmfd))
		return false;

	if (namedsocket)
		if (!setup_socket(ctx, shmfd, optkey, optdesc))
		goto fail;

/* max videoframesize + DTS + structure + maxaudioframesize,
* start with max, then truncate down to whatever is actually used */
	int rc = ftruncate(shmfd, ctx->shm.shmsize);
	if (-1 == rc){
		arcan_warning("arcan_frameserver_spawn_server(unix) -- allocating"
		"	(%d) shared memory failed (%d).\n", ctx->shm.shmsize, errno);
		goto fail;
	}

	ctx->shm.handle = shmfd;
	shmpage = (void*) mmap(
		NULL, ctx->shm.shmsize, PROT_READ | PROT_WRITE, MAP_SHARED, shmfd, 0);

	if (MAP_FAILED == shmpage){
		arcan_warning("arcan_frameserver_spawn_server(unix) -- couldn't "
			"allocate shmpage\n");

fail:
		arcan_frameserver_dropsemaphores_keyed(ctx->shm.key);
		return false;
	}

	memset(shmpage, '\0', ctx->shm.shmsize);
 	shmpage->dms = true;
	shmpage->parent = getpid();
	shmpage->major = ARCAN_VERSION_MAJOR;
	shmpage->minor = ARCAN_VERSION_MINOR;
	shmpage->segment_size = ctx->shm.shmsize;
	shmpage->cookie = arcan_shmif_cookie();
	ctx->shm.ptr = shmpage;

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
	arcan_frameserver* ctx, bool record, int hintw, int hinth, int tag)
{
	if (!ctx || ctx->flags.alive == false)
		return NULL;

	hintw = hintw <= 0 || hintw > ARCAN_SHMPAGE_MAXW ? 32 : hintw;
	hinth = hinth <= 0 || hinth > ARCAN_SHMPAGE_MAXH ? 32 : hinth;

	arcan_frameserver* newseg = arcan_frameserver_alloc();
	if (!newseg)
		return NULL;

	newseg->shm.shmsize = arcan_shmif_getsize(hintw, hinth);

	if (!shmalloc(newseg, false, NULL, -1)){
		arcan_frameserver_free(newseg);
		return NULL;
	}

	img_cons cons = {.w = hintw , .h = hinth, .bpp = ARCAN_SHMPAGE_VCHANNELS};
	vfunc_state state = {.tag = ARCAN_TAG_FRAMESERV, .ptr = newseg};
	arcan_frameserver_meta vinfo = {
		.width = hintw,
		.height = hinth,
		.bpp = sizeof(av_pixel)
	};
	arcan_vobj_id newvid = arcan_video_addfobject((arcan_vfunc_cb)
		arcan_frameserver_videoframe_direct, state, cons, 0);

	if (newvid == ARCAN_EID){
		arcan_frameserver_free(newseg);
		return NULL;
	}

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
	if (!record)
		newseg->aid = arcan_audio_feed((arcan_afunc_cb)
			arcan_frameserver_audioframe_direct, ctx, &errc);

 	newseg->desc = vinfo;
	newseg->source = ctx->source ? strdup(ctx->source) : NULL;
	newseg->vid = newvid;
	newseg->parent = ctx->vid;

/*
 * Transfer the new event socket along with the base-key that will be used
 * to find shm etc. We re-use the same name- allocation approach for
 * convenience - in spite of the risk of someone racing a segment intended
 * for another. Part of this is OSX not supporting unnamed semaphores on
 * shared memory pages (seriously).
 */
	int sockp[4] = {-1, -1};
	if (!sockpair_alloc(sockp, 1, true)){
		arcan_audio_stop(newseg->aid);
		arcan_frameserver_free(newseg);
		arcan_video_deleteobject(newvid);

		return NULL;
	}

/*
 * We monitor the same PID as parent, but for cases where we don't monitor
 * parent (non-auth) we switch to using the socket as indicator.
 */
	newseg->launchedtime = arcan_timemillis();
	newseg->child = ctx->child;
	newseg->flags.alive = true;

/* NOTE: should we allow some segments to map events with other masks,
 * or should this be a separate command with a heavy warning? i.e.
 * allowing EVENT_INPUT gives remote-control etc. options, with all
 * the security considerations that comes with it */
	newseg->queue_mask = EVENT_EXTERNAL;

	if (record)
		newseg->segid = SEGID_ENCODER;
/* frameserver gets one chance to hint the purpose for this segment */
	else
		newseg->segid = SEGID_UNKNOWN;

	newseg->sz_audb = ARCAN_SHMPAGE_AUDIOBUF_SZ;
	newseg->ofs_audb = 0;
	newseg->audb = malloc(ctx->sz_audb);

	arcan_shmif_calcofs(newseg->shm.ptr, &(newseg->vidp), &(newseg->audp));
	arcan_shmif_setevqs(newseg->shm.ptr, newseg->esync,
		&(newseg->inqueue), &(newseg->outqueue), true);
	newseg->inqueue.synch.killswitch = (void*) newseg;
	newseg->outqueue.synch.killswitch = (void*) newseg;

/*
 * We finally have a completed segment with all tracking, buffering etc.
 * in place, send it to the frameserver to map and use. Note that we
 * cheat by sending on additional descriptor in advance.
 */
	newseg->dpipe = sockp[0];
	arcan_pushhandle(sockp[1], ctx->dpipe);

	arcan_event keyev = {
		.category = EVENT_TARGET, .tgt.kind = TARGET_COMMAND_NEWSEGMENT
	};

	keyev.tgt.ioevs[0].iv = tag;
	keyev.tgt.ioevs[1].iv = record ? 1 : 0;

	snprintf(keyev.tgt.message,
		sizeof(keyev.tgt.message) / sizeof(keyev.tgt.message[1]),
		"%s", newseg->shm.key
	);

	arcan_frameserver_pushevent(ctx, &keyev);
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

	volatile uint8_t diffv = 0;

	while (n--){
		diffv |= *p1++ ^ *p2++;
	}

	return !(diffv != 0);
}

static enum arcan_ffunc_rv socketverify(enum arcan_ffunc_cmd cmd,
	av_pixel* buf, size_t s_buf, uint16_t width, uint16_t height,
	unsigned mode, vfunc_state state)
{
	arcan_frameserver* tgt = state.ptr;
	char ch = '\n';
	bool term;
	size_t ntw;

/*
 * We want this code-path exercised no matter what,
 * so if the caller specified that the first connection should be
 * accepted no mater what, immediately continue.
 */
	switch (cmd){
	case FFUNC_POLL:
		if (tgt->clientkey[0] == '\0')
			goto send_key;

/*
 * We need to read one byte at a time, until we've reached LF or
 * PP_SHMPAGE_SHMKEYLIM as after the LF the socket may be used
 * for other things (e.g. event serialization)
 */
		if (!fd_avail(tgt->dpipe, &term)){
			if (term)
				arcan_frameserver_free(tgt);
			return FFUNC_RV_NOFRAME;
		}

		if (-1 == read(tgt->dpipe, &ch, 1))
			return FFUNC_RV_NOFRAME;

		if (ch == '\n'){
/* 0- pad to max length */
			memset(tgt->sockinbuf + tgt->sockrofs, '\0',
				PP_SHMPAGE_SHMKEYLIM - tgt->sockrofs);

/* alternative memcmp to not be used as a timing oracle */
			if (memcmp_nodep(tgt->sockinbuf, tgt->clientkey, PP_SHMPAGE_SHMKEYLIM))
				goto send_key;

			arcan_warning("platform/frameserver.c(), key verification failed on %"
				PRIxVOBJ", received: %s\n", tgt->vid, tgt->sockinbuf);
			arcan_frameserver_free(tgt);
			return FFUNC_RV_NOFRAME;
		}
		else
			tgt->sockinbuf[tgt->sockrofs++] = ch;

		if (tgt->sockrofs >= PP_SHMPAGE_SHMKEYLIM){
			arcan_warning("platform/frameserver.c(), socket "
				"verify failed on %"PRIxVOBJ", terminating.\n", tgt->vid);
			arcan_frameserver_free(tgt);
		}
		return FFUNC_RV_NOFRAME;

	case FFUNC_DESTROY:
		if (tgt->sockaddr)
			unlink(tgt->sockaddr);

	default:
		return FFUNC_RV_NOFRAME;
	break;
	}

/* switch to resize polling default handler */
send_key:
	ntw = snprintf(tgt->sockinbuf,
		PP_SHMPAGE_SHMKEYLIM, "%s\n", tgt->shm.key);

	ssize_t rtc = 10;
	off_t wofs = 0;

/*
 * small chance here that a malicious client could manipulate the
 * descriptor in such a way as to block, retry a short while.
 */
	int flags = fcntl(tgt->dpipe, F_GETFL, 0);
	fcntl(tgt->dpipe, F_SETFL, flags | O_NONBLOCK);
	while (rtc && ntw){
		ssize_t rc = write(tgt->dpipe, tgt->sockinbuf + wofs, ntw);
		if (-1 == rc){
			rtc = (errno == EAGAIN || errno ==
				EWOULDBLOCK || errno == EINTR) ? rtc - 1 : 0;
		}
		else{
			ntw -= rc;
			wofs += rc;
		}
	}

	if (rtc <= 0){
		arcan_frameserver_free(tgt);
		return FFUNC_RV_NOFRAME;
	}

	arcan_video_alterfeed(tgt->vid,
		arcan_frameserver_emptyframe, state);

	arcan_errc errc;
	tgt->aid = arcan_audio_feed((arcan_afunc_cb)
		arcan_frameserver_audioframe_direct, tgt, &errc);
	tgt->sz_audb = 1024 * 64;
	tgt->audb = malloc(tgt->sz_audb);

	return FFUNC_RV_NOFRAME;
}

static int8_t socketpoll(enum arcan_ffunc_cmd cmd, av_pixel* buf,
	size_t s_buf, uint16_t width, uint16_t height, unsigned mode,
	vfunc_state state)
{
	arcan_frameserver* tgt = state.ptr;
	struct arcan_shmif_page* shmpage = tgt->shm.ptr;
	bool term;

	if (state.tag != ARCAN_TAG_FRAMESERV || !shmpage){
		arcan_warning("platform/posix/frameserver.c:socketpoll, called with"
			" invalid source tag, investigate.\n");
		return FFUNC_RV_NOFRAME;
	}

/* wait for connection, then unlink directory node and switch to verify. */
	switch (cmd){
		case FFUNC_POLL:
			if (!fd_avail(tgt->dpipe, &term)){
				if (term)
					arcan_frameserver_free(tgt);

				return FFUNC_RV_NOFRAME;
			}

			int insock = accept(tgt->dpipe, NULL, NULL);
			if (-1 == insock)
				return FFUNC_RV_NOFRAME;

			arcan_video_alterfeed(tgt->vid, socketverify, state);

/* hand over responsibility for the dpipe to the event layer */
			arcan_event adopt = {
				.category = EVENT_FSRV,
				.fsrv.kind = EVENT_FSRV_EXTCONN,
				.fsrv.descriptor = tgt->dpipe,
				.fsrv.otag = tgt->tag,
				.fsrv.video = tgt->vid
			};
			tgt->dpipe = insock;

			snprintf(adopt.fsrv.ident, sizeof(adopt.fsrv.ident)/
				sizeof(adopt.fsrv.ident[0]), "%s", tgt->sockkey);

			arcan_event_enqueue(arcan_event_defaultctx(), &adopt);

			free(tgt->sockaddr);
			free(tgt->sockkey);
			tgt->sockaddr = tgt->sockkey = NULL;

			return socketverify(cmd, buf, s_buf, width, height, mode, state);
		break;

/* socket is closed in frameserver_destroy */
		case FFUNC_DESTROY:
			if (tgt->sockaddr){
				close(tgt->dpipe);
				free(tgt->sockkey);
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

arcan_frameserver* arcan_frameserver_listen_external(const char* key, int fd)
{
	arcan_frameserver* res = arcan_frameserver_alloc();
	if (!shmalloc(res, true, key, fd)){
		arcan_warning("arcan_frameserver_listen_external(), shared memory"
			" setup failed\n");
		return NULL;
	}

/*
 * start with a default / empty fobject
 * (so all image_ operations still work)
 */
	res->segid = SEGID_UNKNOWN;
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

bool arcan_frameserver_resize(struct arcan_frameserver* s, int w, int h)
{
	shm_handle* src = &s->shm;
	w = abs(w);
	h = abs(h);

	size_t sz = arcan_shmif_getsize(w, h);
	if (sz > ARCAN_SHMPAGE_MAX_SZ)
		return false;

/* Don't resize unless the gain is ~20%, the routines does support
 * shrinking the size of the segment, something to consider in memory
 * constrained environments */
	if (sz < src->shmsize && sz > (float)src->shmsize * 0.8)
		goto done;

/* Cheap option out when we can't ftruncate to new sizes */
#ifdef ARCAN_SHMIF_OVERCOMMIT
	goto done;
#endif

	char* tmpbuf = arcan_alloc_mem(sizeof(struct arcan_shmif_page),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_TEMPORARY, ARCAN_MEMALIGN_NATURAL);

	memcpy(tmpbuf, src->ptr, sizeof(struct arcan_shmif_page));

/* Re-use the existing keys and descriptors on OSes that support this
 * feature, for others we should have a fallback that relies on mapping
 * a new segment and doing the transfer that way, but at the moment
 * OVERCOMMIT is the only other option */
	munmap(src->ptr, src->shmsize);
	src->ptr = NULL;

	src->shmsize = sz;
	if (-1 == ftruncate(src->handle, sz)){
		arcan_warning("frameserver_resize() failed, "
			"bad (broken?) truncate (%s)\n", strerror(errno));
		return false;
	}

	src->ptr = mmap(NULL, sz, PROT_READ|PROT_WRITE, MAP_SHARED, src->handle, 0);

  if (MAP_FAILED == src->ptr){
  	src->ptr = NULL;
		arcan_warning("frameserver_resize() failed, reason: %s\n", strerror(errno));
    return false;
  }

  memcpy(src->ptr, tmpbuf, sizeof(struct arcan_shmif_page));
  src->ptr->segment_size = sz;
	arcan_mem_free(tmpbuf);

done:
	s->desc.width = w;
	s->desc.height = h;
	return true;
}

arcan_errc arcan_frameserver_spawn_server(arcan_frameserver* ctx,
	struct frameserver_envp setup)
{
	if (ctx == NULL)
		return ARCAN_ERRC_BAD_ARGUMENT;

	int sockp[2] = {-1, -1};

	if (!sockpair_alloc(sockp, 1, false)){
		arcan_warning("posix/frameserver.c() couldn't get socket pairs\n");
		return ARCAN_ERRC_UNACCEPTED_STATE;
	}

	shmalloc(ctx, false, NULL, -1);

	ctx->launchedtime = arcan_frametime();
	pid_t child = fork();
	if (child) {
		close(sockp[1]);

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

		if (!ctx->vid)
			ctx->vid = arcan_video_addfobject((arcan_vfunc_cb)
				arcan_frameserver_emptyframe, state, cons, 0);

		ctx->aid = ARCAN_EID;

#ifdef __APPLE__
		int val = 1;
		setsockopt(sockp[0], SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
#endif

		ctx->dpipe = sockp[0];
		ctx->child = child;

		arcan_frameserver_configure(ctx, setup);

	}
	else if (child == 0){
		char convb[8];
		close(sockp[0]);

		sprintf(convb, "%i", sockp[1]);
		setenv("ARCAN_SOCKIN_FD", convb, 1);
		setenv("ARCAN_ARG", setup.args.builtin.resource, 1);

/*
 * Semi-trusteed frameservers are allowed
 * some namespace mapping access.
 */
		setenv( "ARCAN_APPLPATH", arcan_expand_resource("", RESOURCE_APPL), 1);
		setenv( "ARCAN_APPLTEMPPATH",
			arcan_expand_resource("", RESOURCE_APPL_TEMP), 1);
		setenv( "ARCAN_STATEPATH",
			arcan_expand_resource("", RESOURCE_APPL_STATE), 1);
		setenv( "ARCAN_RESOURCEPATH",
			arcan_expand_resource("", RESOURCE_APPL_SHARED), 1);
		setenv("ARCAN_SHMKEY", ctx->shm.key, 1);

/*
 * we need to mask this signal as when debugging parent process,
 * GDB pushes SIGINT to children, killing them and changing
 * the behavior in the core process
 */
		signal(SIGINT, SIG_IGN);

		if (setup.use_builtin){
			char* argv[] = {
				arcan_expand_resource("", RESOURCE_SYS_BINS),
				strdup(setup.args.builtin.mode),
				NULL
			};

			execv(argv[0], argv);
			arcan_fatal("FATAL, arcan_frameserver_spawn_server(), "
				"couldn't spawn frameserver(%s) with %s:%s. Reason: %s\n",
				argv[0], setup.args.builtin.mode,
				setup.args.builtin.resource, strerror(errno));
			exit(1);
		}
/* non-frameserver executions (hijack libs, ...) */
		else {
			char** envv = setup.args.external.envv->data;
			while(*envv)
				putenv(*(envv++));

			execv(setup.args.external.fname, setup.args.external.argv->data);
			exit(1);
		}
	}
	else /* -1 */
		arcan_fatal("fork() failed, check ulimit or similar configuration issue.");

	return ARCAN_OK;
}
