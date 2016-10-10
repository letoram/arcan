/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <inttypes.h>
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
#include "arcan_audioint.h"
#include <arcan_frameserver.h>

#define INCR(X, C) ( ( (X) = ( (X) + 1) % (C)) )

#ifndef FORCE_SYNCH
	#define FORCE_SYNCH() {\
		asm volatile("": : :"memory");\
		__sync_synchronize();\
	}
#endif

/* NOTE: maintaing pid_t for frameserver (or worse, for hijacked target)
 * should really be replaced by making sure they belong to the same process
 * group and first send a close signal to the group, and thereafter KILL */

/* Dislike resorting to these kinds of antics, but it was among the cleaner
 * solutions given the portability constraints (OSX,Win32). Other solutions
 * are in the pipeline, we're essentially waiting for adoption rates to get
 * good for descriptor based pid handles. */
static void* nanny_thread(void* arg)
{
	pid_t* pid = (pid_t*) arg;
	int counter = 10;

	while (counter--){
		int statusfl;
		int rv = waitpid(*pid, &statusfl, WNOHANG);
		if (rv > 0)
			break;

		else if (counter == 0){
			kill(*pid, SIGKILL);
			waitpid(*pid, &statusfl, 0);
			break;
		}

		sleep(1);
	}

	free(pid);
	return NULL;
}

static size_t shmpage_size(size_t w, size_t h,
	size_t vbufc, size_t abufc, int abufsz)
{
#ifdef ARCAN_SHMIF_OVERCOMMIT
	return ARCAN_SHMPAGE_START_SZ;
#else
	return sizeof(struct arcan_shmif_page) + 64 +
		abufc * abufsz + (abufc * 64) +
		vbufc * w * h * sizeof(shmif_pixel) + (vbufc * 64);
#endif
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
		close(src->dpipe);
		src->dpipe = -1;
	}

	struct arcan_shmif_page* shmpage = src->shm.ptr;

	if (shmpage && -1 == munmap((void*) shmpage, src->shm.shmsize))
		arcan_warning("BUG -- arcan_frameserver_free(), munmap failed: %s\n",
			strerror(errno));

	if (src->shm.key){
		shm_unlink( src->shm.key );

/* step 2, semaphore handles */
		size_t slen = strlen(src->shm.key) + 1;
		if (slen > 1){
			char work[slen];
			snprintf(work, slen, "%s", src->shm.key);
			slen -= 2;
			work[slen] = 'v';
			sem_unlink(work); sem_close(src->vsync);
			work[slen] = 'a';
			sem_unlink(work); sem_close(src->async);
			work[slen] = 'e';
			sem_unlink(work); sem_close(src->esync);
			arcan_mem_free(src->shm.key);
		}
	}
	if (-1 != src->shm.handle)
		close(src->shm.handle);
	src->shm.ptr = NULL;
}

void arcan_frameserver_killchild(arcan_frameserver* src)
{
/* only "kill" main-segments and non-authoritative connections */
	if (!src || src->parent.vid != ARCAN_EID || src->child <= 1)
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
	static bool env_checked;
	static bool no_nanny;

/* drop env so we don't propagate to sub- arcan_lwa processes */
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

/* nanny thread: fire once then forget, with what should be,
 * "minimal" stack, i.e. by glibc standard */
	pid_t* pidptr = malloc(sizeof(pid_t));
	pthread_attr_t nanny_attr;
	pthread_attr_init(&nanny_attr);
	pthread_attr_setdetachstate(&nanny_attr, PTHREAD_CREATE_DETACHED);
	*pidptr = src->child;

	pthread_t nanny;
	if (0 != pthread_create(&nanny, &nanny_attr, nanny_thread, (void*) pidptr))
		kill(src->child, SIGKILL);
	pthread_attr_destroy(&nanny_attr);
}

bool arcan_frameserver_validchild(arcan_frameserver* src){
	int status;

/* free (consequence of a delete call on the associated vid)
 * will disable the child_alive flag */
	if (!src || !src->flags.alive)
		return false;

/*
 * for non-auth connections, we have few good options of getting a non- race
 * condition prone resource to check for connection status, so use the socket
 * descriptor.
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
 * Note that on loop conditions, the pid can change, thus we have to assume it
 * will be valid in the near future.  PID != privilege, it's simply a process
 * to monitor as hint to what the state of a child is, the child is free to
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
	if (!fsrv || fd == BADFD)
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
	const char* errmsg = NULL;

	char playbuf[sizeof(pattern) + 8];

	while (retrycount){
/* not a security mechanism, just light "avoid stepping on my own toes" */
		snprintf(playbuf, sizeof(playbuf), pattern, selfpid % 1000, rand() % 1000);

		pb_ofs = strlen(playbuf) - 1;
		*dfd = shm_open(playbuf, O_CREAT | O_RDWR | O_EXCL, 0700);

/*
 * with EEXIST, we happened to have a name collision, it is unlikely, but may
 * happen. for the others however, there is something else going on and there's
 * no point retrying
 */
		if (-1 == *dfd && errno != EEXIST){
			arcan_warning("arcan_findshmkey(), allocating "
				"shared memory failed, reason: %d\n", errno);
			return false;
		}

		else if (-1 == *dfd){
			errmsg = "shmalloc failed -- named exists\n";
			retrycount--;
			continue;
		}

		playbuf[pb_ofs] = 'v';
		ctx->vsync = sem_open(playbuf, O_CREAT | O_EXCL, 0700, 0);

		if (SEM_FAILED == ctx->vsync){
			playbuf[pb_ofs] = 'm'; shm_unlink(playbuf);
			close(*dfd);
			retrycount--;
			errmsg = "couldn't create (v) semaphore\n";
			continue;
		}

		playbuf[pb_ofs] = 'a';
		ctx->async = sem_open(playbuf, O_CREAT | O_EXCL, 0700, 0);

		if (SEM_FAILED == ctx->async){
			playbuf[pb_ofs] = 'v'; sem_unlink(playbuf); sem_close(ctx->vsync);
			playbuf[pb_ofs] = 'm'; shm_unlink(playbuf);
			close(*dfd);
			retrycount--;
			errmsg = "couldn't create (a) semaphore\n";
			continue;
		}

		playbuf[pb_ofs] = 'e';
		ctx->esync = sem_open(playbuf, O_CREAT | O_EXCL, 0700, 1);
		if (SEM_FAILED == ctx->esync){
			playbuf[pb_ofs] = 'a'; sem_unlink(playbuf); sem_close(ctx->async);
			playbuf[pb_ofs] = 'v'; sem_unlink(playbuf); sem_close(ctx->vsync);
			playbuf[pb_ofs] = 'm'; shm_unlink(playbuf);
			close(*dfd);
			retrycount--;
			errmsg = "couldn't create (e) semaphore\n";
			continue;
		}

		break;
	}

	playbuf[pb_ofs] = 'm';
	ctx->shm.key = strdup(playbuf);

	if (retrycount)
		return true;

	arcan_warning("findshmkey() -- namespace reservation failed: %s\n", errmsg);
	return false;
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
			int flags = fcntl(dst[i], F_GETFL);
			if (-1 != flags)
				fcntl(dst[i], F_SETFL, flags | O_NONBLOCK);

			if (cloexec){
				flags = fcntl(dst[i], F_GETFD);
				if (-1 != flags)
					fcntl(dst[i], F_SETFD, flags | O_CLOEXEC);
			}
#ifdef __APPLE__
 			int val = 1;
			setsockopt(dst[i], SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
#endif
		}
	}

	return res;
}

/*
 * even if we have a preset listening socket, we run through the routine to
 * generate unlink- target etc. still
 */
static bool setup_socket(arcan_frameserver* ctx, int shmfd,
	const char* optkey, int optdesc)
{
	struct sockaddr_un addr = {
		.sun_family = AF_UNIX
	};
	size_t lim = sizeof(addr.sun_path) / sizeof(addr.sun_path[0]);

	if (optkey == NULL){
		arcan_warning("posix/frameserver.c:shmalloc(), named socket "
			"connected requested but with empty key. cannot "
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

	char* dst = (char*) &addr.sun_path;
	int len = arcan_shmif_resolve_connpath(optkey, dst, lim);
	if (len < 0){
		arcan_warning("posix/frameserver.c:setup_socket, resolving path for "
			"%s, failed -- too long (%d vs. %d)\n", optkey, abs(len), lim);
		return false;
	}

	if (-1 == optdesc){
/*
 * if we happen to have a stale listener, unlink it but only if it has been
 * used as a domain-socket in beforehand (so in the worst case, some lets a
 * user set this path and it is maliciously used to unlink files.
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
		listen(fd, 5);
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

	jmp_buf out;
	if (0 != setjmp(out))
		goto fail;

/* tiny race condition SIGBUS window here */
	arcan_frameserver_enter(ctx, out);
		memset(shmpage, '\0', ctx->shm.shmsize);
	 	shmpage->dms = true;
		shmpage->parent = getpid();
		shmpage->major = ASHMIF_VERSION_MAJOR;
		shmpage->minor = ASHMIF_VERSION_MINOR;
		shmpage->segment_size = ctx->shm.shmsize;
		shmpage->cookie = arcan_shmif_cookie();
		shmpage->vpending = 1;
		shmpage->apending = 1;
		ctx->shm.ptr = shmpage;
	arcan_frameserver_leave(ctx);

	return true;
}

/*
 * Allocate a new segment (shmalloc), inherit the relevant tracking members
 * from the parent, re-use the segment to notify the new key to be used, mark
 * the segment as pending and set a transitional feed-function that looks for
 * an ident on the socket.
 */
arcan_frameserver* arcan_frameserver_spawn_subsegment(
	arcan_frameserver* ctx, enum ARCAN_SEGID segid, int hintw, int hinth, int tag)
{
	if (!ctx || ctx->flags.alive == false)
		return NULL;

	hintw = hintw <= 0 || hintw > ARCAN_SHMPAGE_MAXW ? 32 : hintw;
	hinth = hinth <= 0 || hinth > ARCAN_SHMPAGE_MAXH ? 32 : hinth;

	arcan_frameserver* newseg = arcan_frameserver_alloc();
	if (!newseg)
		return NULL;

	newseg->shm.shmsize = shmpage_size(hintw, hinth, 1, 1, 65535);

	if (!shmalloc(newseg, false, NULL, -1)){
		arcan_frameserver_free(newseg);
		return NULL;
	}
	struct arcan_shmif_page* shmpage = newseg->shm.ptr;

	img_cons cons = {.w = hintw , .h = hinth, .bpp = ARCAN_SHMPAGE_VCHANNELS};
	vfunc_state state = {.tag = ARCAN_TAG_FRAMESERV, .ptr = newseg};
	struct arcan_frameserver_meta vinfo = {
		.width = hintw,
		.height = hinth,
		.bpp = sizeof(av_pixel)
	};
	arcan_vobj_id newvid = arcan_video_addfobject(FFUNC_VFRAME, state, cons, 0);

	if (newvid == ARCAN_EID){
		arcan_frameserver_free(newseg);
		return NULL;
	}

	size_t abufc = 0;
	size_t abufsz = 0;

/*
 * Normally, subsegments don't get any audiobuffers unless they recipient
 * ask for it during a resize/negotiation. We ignore this for the encoder
 * case as there's currently no negotiation protocol in place.
 */
	if (segid == SEGID_ENCODER){
		abufc = 1;
		abufsz = 65535;
	}

	jmp_buf out;
	if (0 != setjmp(out)){
		arcan_frameserver_free(newseg);
		return NULL;
	}

	arcan_frameserver_enter(ctx, out);
		shmpage->w = hintw;
		shmpage->h = hinth;
		shmpage->vpending = 1;
		shmpage->abufsize = abufsz;
		shmpage->apending = abufc;
		shmpage->segment_token = ((uint32_t) newvid) ^ ctx->cookie;
	arcan_frameserver_leave(ctx);

/*
 * Currently, we're reserving a rather aggressive amount of memory for audio,
 * even though it's likely that (especially for multiple- segments) it will go
 * by unused. For arcan->frameserver data transfers we shouldn't have an AID,
 * attach monitors and synch audio transfers to video.
 */
	arcan_errc errc;
	if (segid != SEGID_ENCODER)
		newseg->aid = arcan_audio_feed((arcan_afunc_cb)
			arcan_frameserver_audioframe_direct, newseg, &errc);

 	newseg->desc = vinfo;
	newseg->source = ctx->source ? strdup(ctx->source) : NULL;
	newseg->vid = newvid;
	newseg->parent.vid = ctx->vid;
	newseg->parent.ptr = (void*) ctx;

/*
 * Transfer the new event socket along with the base-key that will be used to
 * find shm etc. We re-use the same name- allocation approach for convenience -
 * in spite of the risk of someone racing a segment intended for another. Part
 * of this is OSX not supporting unnamed semaphores on shared memory pages
 * (seriously).
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

/* NOTE: should we allow some segments to map events with other masks, or
 * should this be a separate command with a heavy warning? i.e.  allowing
 * EVENT_INPUT gives remote-control etc. options, with all the security
 * considerations that comes with it */
	newseg->queue_mask = EVENT_EXTERNAL;
	newseg->segid = segid;

	newseg->sz_audb = 0;
	newseg->ofs_audb = 0;
	newseg->audb = NULL;

	newseg->vbuf_cnt = 1;
	newseg->abuf_cnt = abufc;
	shmpage->segment_size = arcan_shmif_mapav(shmpage,
		newseg->vbufs, 1, cons.w * cons.h * sizeof(shmif_pixel),
		newseg->abufs, abufc, abufsz
	);
	newseg->abuf_sz = abufsz;

	arcan_shmif_setevqs(newseg->shm.ptr, newseg->esync,
		&(newseg->inqueue), &(newseg->outqueue), true);
	newseg->inqueue.synch.killswitch = (void*) newseg;
	newseg->outqueue.synch.killswitch = (void*) newseg;

/*
 * We finally have a completed segment with all tracking, buffering etc.  in
 * place, send it to the frameserver to map and use. Note that we cheat by
 * sending on additional descriptor in advance.
 */
	newseg->dpipe = sockp[0];
	arcan_pushhandle(sockp[1], ctx->dpipe);

	arcan_event keyev = {
		.category = EVENT_TARGET, .tgt.kind = TARGET_COMMAND_NEWSEGMENT
	};

	keyev.tgt.ioevs[0].iv = tag;
	keyev.tgt.ioevs[1].iv = segid == SEGID_ENCODER ? 1 : 0;
	keyev.tgt.ioevs[2].iv = segid;

	snprintf(keyev.tgt.message,
		sizeof(keyev.tgt.message) / sizeof(keyev.tgt.message[1]),
		"%s", newseg->shm.key
	);

	arcan_frameserver_pushevent(ctx, &keyev);
	return newseg;
}

/*
 * When we are in this callback state, it means that there's a VID connected to
 * a frameserver that is waiting for a non-authorative connection. (Pending
 * state), to monitor for suspicious activity, maintain a counter here and/or
 * add a timeout and propagate a "frameserver terminated" session [not
 * implemented].
 *
 * Note that we dont't track the PID of the client here, as the implementation
 * for passing credentials over sockets is exotic (BSD vs Linux etc.) so part
 * of the 'non-authoritative' bit is that the server won't kill-signal or check
 * if pid is still alive in this mode.
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

enum arcan_ffunc_rv arcan_frameserver_socketverify FFUNC_HEAD
{
	arcan_frameserver* tgt = state.ptr;
	char ch = '\n';
	bool term;
	size_t ntw;

/*
 * We want this code-path exercised no matter what, so if the caller specified
 * that the first connection should be accepted no mater what, immediately
 * continue.
 */
	switch (cmd){
	case FFUNC_POLL:
		if (tgt->clientkey[0] == '\0')
			goto send_key;

/*
 * We need to read one byte at a time, until we've reached LF or
 * PP_SHMPAGE_SHMKEYLIM as after the LF the socket may be used for other things
 * (e.g. event serialization)
 */
		if (!fd_avail(tgt->dpipe, &term)){
			if (term)
				arcan_frameserver_free(tgt);
			return FRV_NOFRAME;
		}

		if (-1 == read(tgt->dpipe, &ch, 1))
			return FRV_NOFRAME;

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
			return FRV_NOFRAME;
		}
		else
			tgt->sockinbuf[tgt->sockrofs++] = ch;

		if (tgt->sockrofs >= PP_SHMPAGE_SHMKEYLIM){
			arcan_warning("platform/frameserver.c(), socket "
				"verify failed on %"PRIxVOBJ", terminating.\n", tgt->vid);
			arcan_frameserver_free(tgt);
		}
		return FRV_NOFRAME;

	case FFUNC_DESTROY:
		if (tgt->sockaddr)
			unlink(tgt->sockaddr);

	default:
		return FRV_NOFRAME;
	break;
	}

/* switch to resize polling default handler */
send_key:
	ntw = snprintf(tgt->sockinbuf,
		PP_SHMPAGE_SHMKEYLIM, "%s\n", tgt->shm.key);

	ssize_t rtc = 10;
	off_t wofs = 0;

/*
 * small chance here that a malicious client could manipulate the descriptor in
 * such a way as to block, retry a short while.
 */
	int flags = fcntl(tgt->dpipe, F_GETFL);
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
		return FRV_NOFRAME;
	}

	arcan_video_alterfeed(tgt->vid, FFUNC_NULLFRAME, state);

	arcan_errc errc;
	tgt->aid = arcan_audio_feed((arcan_afunc_cb)
		arcan_frameserver_audioframe_direct, tgt, &errc);
	tgt->sz_audb = 0;
	tgt->ofs_audb = 0;
	tgt->audb = NULL;

	return FRV_NOFRAME;
}

enum arcan_ffunc_rv arcan_frameserver_socketpoll FFUNC_HEAD
{
	arcan_frameserver* tgt = state.ptr;
	struct arcan_shmif_page* shmpage = tgt->shm.ptr;
	bool term;

	if (state.tag != ARCAN_TAG_FRAMESERV || !shmpage){
		arcan_warning("platform/posix/frameserver.c:socketpoll, called with"
			" invalid source tag, investigate.\n");
		return FRV_NOFRAME;
	}

/* wait for connection, then unlink directory node and switch to verify. */
	switch (cmd){
		case FFUNC_POLL:
			if (!fd_avail(tgt->dpipe, &term)){
				if (term)
					arcan_frameserver_free(tgt);

				return FRV_NOFRAME;
			}

			int insock = accept(tgt->dpipe, NULL, NULL);
			if (-1 == insock)
				return FRV_NOFRAME;

			arcan_video_alterfeed(tgt->vid, FFUNC_SOCKVER, state);

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

			return arcan_frameserver_socketverify(
				cmd, buf, buf_sz, width, height, mode, state, tgt->vid);
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

	return FRV_NOFRAME;
}

/*
 * expand-env pre-fork and make sure appropriate namespaces are present
 * and that there's enough room in the frameserver_envp for NULL term.
 * The caller will cleanup env with free_strarr.
 */
static void append_env(struct arcan_strarr* darr,
	char* argarg, char* sockmsg, char* conn)
{
/*
 * slightly unsure which ones we actually need to propagate, for now these go
 * through the chainloader so it is much less of an issue as most namespace
 * remapping features will go there, and arcterm need to configure the new
 * userenv anyhow.
 */
	const char* spaces[] = {
		getenv("PATH"),
		getenv("CWD"),
		getenv("HOME"),
		getenv("LANG"),
		getenv("ARCAN_FRAMESERVER_DEBUGSTALL"),
		getenv("ARCAN_RENDER_NODE"),
		getenv("ARCAN_VIDEO_NO_FDPASS"),
		arcan_fetch_namespace(RESOURCE_APPL),
		arcan_fetch_namespace(RESOURCE_APPL_TEMP),
		arcan_fetch_namespace(RESOURCE_APPL_STATE),
		arcan_fetch_namespace(RESOURCE_APPL_SHARED),
		arcan_fetch_namespace(RESOURCE_SYS_DEBUG),
		sockmsg,
		argarg,
		conn,
		getenv("LD_LIBRARY_PATH")
	};

/* HARDENING / REFACTOR: we should NOT pass logdir here as it should
 * not be accessible due to exfiltration risk. We should setup the log-
 * entry here and inherit that descriptor as stderr instead!. For harder
 * sandboxing, we can also pass the directory descriptors here */
	size_t n_spaces = sizeof(spaces) / sizeof(spaces[0]);
	const char* keys[] = {
		"PATH",
		"CWD",
		"HOME",
		"LANG",
		"ARCAN_FRAMESERVER_DEBUGSTALL",
		"ARCAN_RENDER_NODE",
		"ARCAN_VIDEO_NO_FDPASS",
		"ARCAN_APPLPATH",
		"ARCAN_APPLTEMPPATH",
		"ARCAN_STATEPATH",
		"ARCAN_RESOURCEPATH",
		"ARCAN_FRAMESERVER_LOGDIR",
		"ARCAN_SOCKIN_FD",
		"ARCAN_ARG",
		"ARCAN_SHMKEY",
		"LD_LIBRARY_PATH"
	};

/* growarr is set to FATALFAIL internally, this should be changed
 * when refactoring _mem and replacing strdup to properly handle OOM */
	while(darr->count + n_spaces + 1 > darr->limit)
		arcan_mem_growarr(darr);

	size_t max_sz = 0;
	for (size_t i = 0; i < n_spaces; i++){
		size_t len = spaces[i] ? strlen(spaces[i]) : 0;
		max_sz = len > max_sz ? len : max_sz;
	}

	char convb[max_sz + sizeof("ARCAN_FRAMESERVER_LOGDIR=")];
	size_t ofs = darr->count > 0 ? darr->count - 1 : 0;
	size_t step = ofs;

	for (size_t i = 0; i < n_spaces; i++){
		if (spaces[i] && strlen(spaces[i]) &&
			snprintf(convb, sizeof(convb), "%s=%s", keys[i], spaces[i])){
			darr->data[step] = strdup(convb);
			step++;
		}
	}

	darr->count = step;
	darr->data[step] = NULL;
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
 * start with a default / empty fobject (so all image_ operations still work)
 */
	res->segid = SEGID_UNKNOWN;
	res->launchedtime = arcan_timemillis();
	res->child = BROKEN_PROCESS_HANDLE;
	img_cons cons = {.w = 32, .h = 32, .bpp = 4};
	vfunc_state state = {.tag = ARCAN_TAG_FRAMESERV, .ptr = res};

	res->vid = arcan_video_addfobject(FFUNC_SOCKPOLL, state, cons, 0);

/*
 * audio setup is deferred until the connection has been acknowledged and
 * verified, but since this call yields a valid VID, we need to have the queues
 * in place.
 */
	res->queue_mask = EVENT_EXTERNAL;
	arcan_shmif_setevqs(res->shm.ptr, res->esync,
		&(res->inqueue), &(res->outqueue), true);
	res->inqueue.synch.killswitch = (void*) res;
	res->outqueue.synch.killswitch = (void*) res;

	return res;
}

 size_t default_sz = 512;
size_t arcan_frameserver_default_abufsize(size_t new_sz)
{
	size_t res = default_sz;
	if (new_sz > 0)
		default_sz = new_sz;
	return res;
}

bool arcan_frameserver_resize(struct arcan_frameserver* s)
{
	bool state = false;
	shm_handle* src = &s->shm;
	struct arcan_shmif_page* shmpage = s->shm.ptr;

/* local copy so we don't fall victim for TOCTU */
	size_t w = shmpage->w;
	size_t h = shmpage->h;
	size_t abufsz = atomic_load(&shmpage->abufsize);
	size_t vbufc = atomic_load(&shmpage->vpending);
	size_t abufc = atomic_load(&shmpage->apending);
	size_t samplerate = atomic_load(&shmpage->audiorate);
	vbufc = vbufc > FSRV_MAX_VBUFC ? FSRV_MAX_VBUFC : vbufc;
	abufc = abufc > FSRV_MAX_ABUFC ? FSRV_MAX_ABUFC : abufc;
	vbufc = vbufc == 0 ? 1 : vbufc;

/*
 * you can potentially have a really big audiobuffer (or well, quite a few 64k
 * ones unless we exceed the upper limit, but by setting 0 there's the
 * indication that we want the size that match the output device the best.
 * Currently, we can't know this and there's a pending audio subsystem refactor
 * to remedy this (kindof) but for now, just have it as a user controlled var.
 */
	if (abufsz < default_sz)
		abufsz = default_sz;

/*
 * pending the same audio refactoring, we just assume the audio layer
 * accepts whatever samplerate and resamples itself if absolutely necessary
 */
	if (samplerate)
		s->desc.samplerate = samplerate;

/* shrink number of video buffers if we don't fit */
	size_t shmsz;
	do{
		shmsz = shmpage_size(w, h, vbufc, abufc, abufsz);
	} while (shmsz > ARCAN_SHMPAGE_MAX_SZ && vbufc-- > 1);

/* initial sanity check */
	if (shmsz > ARCAN_SHMPAGE_MAX_SZ)
		goto fail;

/* no remapping required, resize effect is insignificant or impossible */
	bool rmap = (shmsz > src->shmsize || shmsz < (float) src->shmsize * 0.8);

/* special case, no remap supported */
#ifdef ARCAN_SHMIF_OVERCOMMIT
	rmap = false;
	shmsz = ARCAN_SHMPAGE_MAX_SZ;
#endif

	if (rmap){
	if (-1 == ftruncate(src->handle, shmsz)){
		arcan_warning("truncate failed during resize operation (%d, %d)\n",
			(int) src->handle, (int) shmsz);
		goto fail;
	}

/* other option here would be to set up a new subsegment, make the process
 * asynchronous and push a MIGRATE event, but the gains seem rather pointless */
#if defined(_GNU_SOURCE) && !defined(__APPLE__) && !defined(__BSD)
	struct arcan_shmif_page* newp = mremap(src->ptr,
		src->shmsize, shmsz, MREMAP_MAYMOVE, NULL);
	if (MAP_FAILED == newp){
		if (-1 == ftruncate(src->handle, src->shmsize))
			arcan_warning("_resize, truncate reset on resize fail fail\n");
		goto fail;
	}
	src->ptr = newp;
/*
 * doesn't seem to exist on FBSD10 etc.?
	struct arcan_shmif_page* newp = mremap(src->ptr, src->shmsize, shmsz, NULL);
	if (MAP_FAILED == newp){
		ftruncate(src->handle, src->shmsize);
		goto fail;
	}
	src->ptr = newp;
*/
#else
	munmap(src->ptr, src->shmsize);
	src->ptr = mmap(NULL, shmsz, PROT_READ|PROT_WRITE, MAP_SHARED,src->handle,0);
  if (MAP_FAILED == src->ptr){
  	src->ptr = NULL;
		arcan_warning("frameserver_resize() failed, reason: %s\n", strerror(errno));
  	goto fail;
	}
#endif
	}

	shmpage = src->ptr;
	src->shmsize = shmsz;

/* commit to local tracking */
	atomic_store(&shmpage->w, w);
	atomic_store(&shmpage->h, h);
	s->desc.width = w;
	s->desc.height = h;
	s->desc.hints = atomic_load(&shmpage->hints);
	s->vbuf_cnt = vbufc;
	s->abuf_cnt = abufc;

/* remap pointers */
	shmpage->segment_size = arcan_shmif_mapav(shmpage,
		s->vbufs, s->vbuf_cnt, w * h * sizeof(shmif_pixel),
		s->abufs, s->abuf_cnt, abufsz);
	s->abuf_sz = abufsz;
	arcan_shmif_setevqs(shmpage, s->esync, &(s->inqueue), &(s->outqueue), 1);

/* commit to shared page */
	shmpage->resized = 0;
	shmpage->abufsize = abufsz;
	shmpage->apending = s->abuf_cnt;
	shmpage->vpending = s->vbuf_cnt;
	state = true;

	goto done;

fail:
	shmpage->vpending = 0;
	shmpage->apending = 0;
	shmpage->resized = -1;

done:
/* barrier + signal */
	FORCE_SYNCH();
	arcan_sem_post(s->vsync);
	return state;
}

arcan_errc arcan_frameserver_spawn_server(arcan_frameserver* ctx,
	struct frameserver_envp* setup)
{
	if (ctx == NULL)
		return ARCAN_ERRC_BAD_ARGUMENT;

	int sockp[2] = {-1, -1};

	if (!sockpair_alloc(sockp, 1, false)){
		arcan_warning("posix/frameserver.c() couldn't get socket pairs\n");
		return ARCAN_ERRC_UNACCEPTED_STATE;
	}

	if (!shmalloc(ctx, false, NULL, -1)){
		arcan_warning("posix/frameserver.c() shmalloc failed\n");
		close(sockp[0]);
		close(sockp[1]);
		return ARCAN_ERRC_UNACCEPTED_STATE;
	}
	ctx->launchedtime = arcan_frametime();

/*
 * this warrants explaining - to avoid dynamic allocations in the asynch unsafe
 * context of fork, we prepare the str_arr in *setup along with all envs needed
 * for the two to find eachother. The descriptor used for passing socket etc.
 * is inherited and duped to a fix position and possible leaked fds are closed.
 */
	struct arcan_strarr arr = {0};
	const char* source;
	if (setup->use_builtin)
		append_env(&arr,
			(char*) setup->args.builtin.resource, "3", ctx->shm.key);
	else
		append_env(setup->args.external.envv, "", "3", ctx->shm.key);

	pid_t child = fork();
	if (child) {
		close(sockp[1]);

		img_cons cons = {
			.w = setup->init_w,
			.h = setup->init_h,
			.bpp = 4
		};
		vfunc_state state = {
			.tag = ARCAN_TAG_FRAMESERV,
			.ptr = ctx
		};

		ctx->source = strdup(setup->args.builtin.resource);

		if (!ctx->vid)
			ctx->vid = arcan_video_addfobject(FFUNC_NULLFRAME, state, cons, 0);

		ctx->aid = ARCAN_EID;

#ifdef __APPLE__
		int val = 1;
		setsockopt(sockp[0], SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
#endif
		fcntl(sockp[0], F_SETFD, FD_CLOEXEC);

		ctx->dpipe = sockp[0];
		ctx->child = child;

		arcan_frameserver_configure(ctx, *setup);
	}
	else if (child == 0){
		close(STDERR_FILENO+1);
/* will also strip CLOEXEC */
		dup2(sockp[1], STDERR_FILENO+1);
		arcan_closefrom(STDERR_FILENO+2);

/*
 * we need to mask this signal as when debugging parent process, GDB pushes
 * SIGINT to children, killing them and changing the behavior in the core
 * process
 */
		sigaction(SIGPIPE, &(struct sigaction){
			.sa_handler = SIG_IGN}, NULL);

		if (setup->use_builtin){
			char* argv[] = {
				arcan_fetch_namespace(RESOURCE_SYS_BINS),
				(char*) setup->args.builtin.mode,
				NULL
			};

/* OVERRIDE/INHERIT rather than REPLACE environment (terminal, ...) */
			if (setup->preserve_env){
				for (size_t i = 0; i < arr.count;	i++){
					if (!(arr.data[i] || arr.data[i][0]))
						continue;

					char* val = strchr(arr.data[i], '=');
					*val++ = '\0';
					setenv(arr.data[i], val, 1);
				}
				execv(argv[0], argv);
			}
			else
				execve(argv[0], argv, arr.data);

			arcan_warning("arcan_frameserver_spawn_server() failed: %s, %s\n",
				strerror(errno), argv[0]);
				;
			exit(EXIT_FAILURE);
		}
/* non-frameserver executions (hijack libs, ...) */
		else {
			execve(setup->args.external.fname,
				setup->args.external.argv->data, setup->args.external.envv->data);
			exit(EXIT_FAILURE);
		}
	}
	else /* -1 */
		arcan_fatal("fork() failed, check ulimit or similar configuration issue.");

	arcan_mem_freearr(&arr);
	return ARCAN_OK;
}
