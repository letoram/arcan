/*
 * Copyright 2014-2020, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <stddef.h>
#include <inttypes.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <assert.h>
#include <pthread.h>
#include <poll.h>
#include <setjmp.h>

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

struct arcan_shmif_cont;
#include "../shmif/arcan_shmif_event.h"
#include "../shmif/platform/shmif_platform.h"

#include <arcan_math.h>
#include <arcan_general.h>
#include <arcan_shmif.h>
#include <arcan_event.h>
#include <arcan_video.h>
#include <arcan_audio.h>
#include <arcan_frameserver.h>


#define INCR(X, C) ( ( (X) = ( (X) + 1) % (C)) )

#ifndef FORCE_SYNCH
	#define FORCE_SYNCH() {\
		asm volatile("": : :"memory");\
		__sync_synchronize();\
	}
#endif

/* when building static shmif-server for libarcan-shmif-a11y pulling in these
 * symbols would cause a collision for main arcan, since it is only used for
 * the one case, replace with regular malloc/bzero */
#ifdef PLATFORM_FRAMESERVER_NOAMEM
static void* aalloc(size_t sz,
	enum arcan_memtypes type,
	enum arcan_memhint hint,
	enum arcan_memalign align)
{
	void* res = malloc(sz);
	if (!res)
		return NULL;

	memset(res, '\0', sz);
	return res;
}

static void afree(void* p)
{
	free(p);
}
#define arcan_alloc_mem aalloc
#define arcan_mem_free afree
#else
#endif

static size_t default_abuf_sz = 512;
static size_t default_disp_lim = 8;

/*
 * Provide a size calculation for the specified subprotocol in the context of a
 * specific frameserver. 0 if unknown protocol or not applicable.  The dofs
 * structure will be populated with the detailed offsets and sizes, which
 * should be passed to setproto if the change could be applied.
 */
static size_t fsrv_protosize(struct arcan_frameserver* ctx,
	unsigned proto, struct arcan_shmif_ofstbl* dofs);

/*
 * Prepare the necessary metadata for a specific sub-protocol, should
 * only originate from a platform implementation of the resize handler.
 */
static void fsrv_setproto(struct arcan_frameserver* ctx,
	unsigned proto, struct arcan_shmif_ofstbl* ofsets);

/*
 * Spawn a guard thread that makes sure the process connected to src will
 * be killed off.
 */
static void fsrv_killchild(arcan_frameserver* src);

/* NOTE: maintaing pid_t for frameserver (or worse, for hijacked target)
 * should really be replaced by making sure they belong to the same process
 * group and first send a close signal to the group, and thereafter KILL */

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
	size_t vbufc, size_t abufc, int abufsz, size_t apad)
{
#ifdef ARCAN_SHMIF_OVERCOMMIT
	return ARCAN_SHMPAGE_START_SZ;
#else
	return sizeof(struct arcan_shmif_page) + apad + 64 +
		abufc * abufsz + (abufc * 64) +
		vbufc * w * h * sizeof(shmif_pixel) + (vbufc * 64);
#endif
}

static void fsrv_setevqs(
	struct arcan_shmif_page* dst,
	struct arcan_evctx* inq, struct arcan_evctx* outq)
{
	struct arcan_evctx* tmp = inq;
	inq = outq;
	outq = tmp;

	inq->synch.killswitch = NULL;
	outq->synch.killswitch = NULL;

	inq->local = false;
	inq->eventbuf = dst->childevq.evqueue;
	inq->front = &dst->childevq.front;
	inq->back  = &dst->childevq.back;
	inq->eventbuf_sz = PP_QUEUE_SZ;

	outq->local = false;
	outq->eventbuf = dst->parentevq.evqueue;
	outq->front = &dst->parentevq.front;
	outq->back  = &dst->parentevq.back;
	outq->eventbuf_sz = PP_QUEUE_SZ;
}

struct arcan_frameserver* platform_fsrv_wrapcl(struct arcan_shmif_cont* in)
{
/* alloc - set the wrapped bitflag, set MONITOR FFUNC, map in eventqueues */
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

bool platform_fsrv_lastwords(struct arcan_frameserver* src, char* dst, size_t n)
{
	if (!src || !src->shm.ptr)
		goto out;

	jmp_buf buf;
	if (0 != setjmp(buf))
		goto out;

	platform_fsrv_enter(src, buf);
	size_t lw_sz = COUNT_OF(src->shm.ptr->last_words);
	if (n > lw_sz)
		n = lw_sz;
	snprintf(dst, n, "%s", src->shm.ptr->last_words);
	platform_fsrv_leave();
	return true;

out:
	if (n > 0)
		*dst = '\0';
	return false;
}

bool platform_fsrv_destroy_local(arcan_frameserver* src)
{
	if (!src)
		return false;

	if (!src->flags.alive)
		return false;

	src->flags.alive = false;
	arcan_mem_free(src->audb);
	src->audb = NULL;

	if (src->flags.wrapped){
		src->shm.ptr = NULL;
	}

/* 'shutdown' is not activated for local */
	if (BADFD != src->dpipe){
		close(src->dpipe);
		src->dpipe = BADFD;
	}

	struct arcan_shmif_page* shmpage = src->shm.ptr;

	if (shmpage && -1 == munmap((void*) shmpage, src->shm.shmsize))
		arcan_warning("BUG -- frameserver_dropshared(), munmap failed: %s\n",
			strerror(errno));

	if (-1 != src->shm.handle)
		close(src->shm.handle);

	src->shm.ptr = NULL;
	return true;
}

bool platform_fsrv_destroy(arcan_frameserver* src)
{
	if (!src)
		return false;

	if (!src->flags.alive)
		return false;

	struct arcan_shmif_page* shmpage = src->shm.ptr;

	jmp_buf buf;
	if (0 != setjmp(buf))
		goto out;

	platform_fsrv_enter(src, buf);

/*
 * Clients have an auto-reconnect/crash-recovery mode if they have been
 * provided with a recovery connection point. This will only be activated if
 * there isn't a clean exit, i.e. TARGET_COMMAND_EXIT when the DMS gets pulled
 * or the server process dies.
 *
 * Sometimes, you might want to activate this feature without actually exiting
 * or at least not by SIGSEGV yourself. The 'no_dms_free' flag is used for
 * that purpose.
 */
	if (shmpage){
		if (!src->flags.no_dms_free){
			platform_fsrv_pushevent(src, &(struct arcan_event){
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_EXIT
			});
			shmpage->dms = false;
		}
		else {
			shmpage->childevq.front = shmpage->childevq.back;
			shmpage->parentevq.front = shmpage->parentevq.back;
			shmpage->esync = 0xffffffff;
		}

		shmpage->vready = false;
		shmpage->aready = false;
		shmpage->vsync = 0xffffffff;
		shmpage->async = 0xffffffff;
	}

/* if BUS happens during _enter, the handler will take
 * care of dropping shared and shutting down so no problem here */
	platform_fsrv_dropshared(src);
	platform_fsrv_leave();

/* non-auth trigger nanny thread */
out:
	fsrv_killchild(src);
	src->child = BROKEN_PROCESS_HANDLE;
	src->flags.alive = false;

/* possible mixing audio buffer */
	arcan_mem_free(src->audb);

/* we don't reset state as the data might be useful in core dumps */
	src->watch_const = 0xdead;

/* might be in a listening / pending state, close the pipe */
	if (BADFD != src->dpipe){
		shutdown(src->dpipe, SHUT_RDWR);
		close(src->dpipe);
		src->dpipe = BADFD;
	}

	arcan_mem_free(src);
	return true;
}

void platform_fsrv_dropshared(arcan_frameserver* src)
{
	if (!src)
		return;

	if (src->dpipe != BADFD){
		shutdown(src->dpipe, SHUT_RDWR);
		close(src->dpipe);
		src->dpipe = BADFD;
	}

	if (src->sockaddr){
		unlink(src->sockaddr);
		arcan_mem_free(src->sockaddr);
		src->sockaddr = NULL;
	}

	struct arcan_shmif_page* shmpage = src->shm.ptr;

	if (shmpage && -1 == munmap((void*) shmpage, src->shm.shmsize))
		arcan_warning("BUG -- frameserver_dropshared(), munmap failed: %s\n",
			strerror(errno));

	if (-1 != src->shm.handle)
		close(src->shm.handle);

	src->shm.ptr = NULL;
}

static void fsrv_killchild(arcan_frameserver* src)
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

bool platform_fsrv_validchild(arcan_frameserver* src){
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
	errno = 0;
	int ec = waitpid(src->child, &status, WNOHANG);

	if (ec == src->child || errno == ECHILD){
		errno = EINVAL;
		return false;
	}
	else
		return true;
}

int platform_fsrv_pushfd(
	arcan_frameserver* fsrv, arcan_event* ev, int fd)
{
	if (!fsrv || fd == BADFD)
		return ARCAN_ERRC_BAD_ARGUMENT;

	if (arcan_pushhandle(fd, fsrv->dpipe)){
		platform_fsrv_pushevent( fsrv, ev );
		return ARCAN_OK;
	}

	arcan_warning("frameserver_pushfd(%d->%d) failed, reason(%d) : %s\n",
		fd, fsrv->dpipe, errno, strerror(errno));

	return ARCAN_ERRC_BAD_ARGUMENT;
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
					fcntl(dst[i], F_SETFD, flags | FD_CLOEXEC);
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
 * generate unlink- target etc.
 */
static bool setup_socket(
	arcan_frameserver* ctx, int shmfd, const char* optkey, int optdesc)
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
		arcan_warning("posix/frameserver.c:setup_socket(), couldn't resolve path");
		return false;
	}
	else if (len > lim){
		arcan_warning("posix/frameserver.c:setup_socket(), expanded path "
			"exceed build-time length (%d > %zu)", len, lim);
		return false;
	}

	if (-1 == optdesc){
/*
 * If we happen to have a stale listener, unlink it but only if it has been
 * used as a domain-socket in beforehand (so in the worst case, some lets a
 * user set this path and it is accidentally used to unlink another socket
 * or race the deletion. Since it is not across a privilege barrier the
 * risk is rather small.
 */
		struct stat buf;
		int rv = stat(addr.sun_path, &buf);
		if ( (-1 == rv && errno != ENOENT)||(0 == rv && !S_ISSOCK(buf.st_mode))){
			close(fd);
			return false;
		}
		else if (0 == rv)
			unlink(addr.sun_path);

		if (bind(fd, (struct sockaddr*) &addr, sizeof(addr)) != 0){
			arcan_warning("posix/frameserver.c:shmalloc(), couldn't setup "
				"domain socket for frameserver connectionpoint, check "
				"path permissions (%s), reason:%s\n",addr.sun_path,strerror(errno));
			close(fd);
			return false;
		}

/*
 * Classic permission problem, though it is also not guaranteed portable,
 * hence why we also have the option of an authentication key.
 */
		fchmod(fd, ctx->sockmode);
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
	ctx->sockkey = optkey ? strdup(optkey) : NULL;
	return true;
}

static bool shmalloc(arcan_frameserver* ctx,
	bool namedsocket, const char* optkey, int optdesc)
{
	if (0 == ctx->shm.shmsize)
		ctx->shm.shmsize = ARCAN_SHMPAGE_START_SZ;

	struct arcan_shmif_page* shmpage;
	int shmfd = platform_fsrv_shmmem();

	if (namedsocket)
		if (!setup_socket(ctx, shmfd, optkey, optdesc))
			goto fail;

/* max videoframesize + DTS + structure + maxaudioframesize,
* start with max, then truncate down to whatever is actually used */
	int rc = ftruncate(shmfd, ctx->shm.shmsize);
	if (-1 == rc){
		arcan_warning("platform_fsrv_spawn_server(unix) -- allocating"
		" (%d) shared memory failed (%d).\n", ctx->shm.shmsize, errno);
		goto fail;
	}

	ctx->shm.handle = shmfd;
	shmpage = (void*) mmap(
		NULL, ctx->shm.shmsize, PROT_READ | PROT_WRITE, MAP_SHARED, shmfd, 0);

	if (MAP_FAILED == shmpage){
		arcan_warning("platform_fsrv_spawn_server(unix) -- couldn't "
			"allocate shmpage\n");
fail:
		if (shmfd != -1){
			close(shmfd);
		}
		return false;
	}

/* separate failure code here as the memory is still mapped */
	jmp_buf out;
	if (0 != setjmp(out)){
		munmap(shmpage, ctx->shm.shmsize);
		ctx->shm.ptr = NULL;
		return false;
	}

/* tiny race condition SIGBUS window here */
	platform_fsrv_enter(ctx, out);
		memset(shmpage, '\0', ctx->shm.shmsize);
		shmpage->dms = true;
		shmpage->parent = getpid();
		shmpage->major = ASHMIF_VERSION_MAJOR;
		shmpage->minor = ASHMIF_VERSION_MINOR;
		shmpage->segment_size = ctx->shm.shmsize;
		shmpage->segment_token = ctx->cookie;
		shmpage->cookie = arcan_shmif_cookie();
		shmpage->vpending = 1;
		shmpage->apending = 1;
		ctx->shm.ptr = shmpage;
	platform_fsrv_leave();

	return true;
}

struct arcan_frameserver* platform_fsrv_alloc()
{
	arcan_frameserver* res = arcan_alloc_mem(sizeof(arcan_frameserver),
		ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	res->watch_const = 0xfeed;

	res->dpipe = BADFD;
	res->queue_mask = EVENT_EXTERNAL;
	res->playstate = ARCAN_PLAYING;
	res->flags.alive = true;
	res->flags.autoclock = true;
	res->xfer_sat = 0.5;
	res->parent.vid = ARCAN_EID;
	res->desc.samplerate = ARCAN_SHMIF_SAMPLERATE;
	res->sockmode = S_IRWXU;
	res->child = BROKEN_PROCESS_HANDLE;

/* these are statically defined right now, but we may want to make them
 * configurable in the future to possibly utilize other accelerated resampling
 * etc. */
	res->desc.channels = ARCAN_SHMIF_ACHANNELS;

/*
 * used to provide reference value that a client can use in VIEWPORT as a
 * way of reparenting. Exposed to the scripts in the SEGREQ- handler and
 * then affirmed in the VIEWPORT handler.
 */
	arcan_random((uint8_t*) &res->cookie, sizeof(res->cookie));

/* shm- related settings are deferred as this is called previous to mapping
 * (spawn_subsegment / spawn_server) so setting up the eventqueues with
 * killswitches have to be done elsewhere
 */
	return res;
}

static size_t fsrv_protosize(arcan_frameserver* ctx,
	unsigned proto, struct arcan_shmif_ofstbl* dofs)
{
	size_t tot = 0;
	if (!proto || !dofs){
		if (dofs)
			*dofs = (struct arcan_shmif_ofstbl){};
		return 0;
	}

	tot += sizeof(struct arcan_shmif_ofstbl);
	if (tot % sizeof(max_align_t) != 0)
		tot += tot - (tot % sizeof(max_align_t));

/*
 * Complicated, as there might be a number of different displays with
 * different lut formats, edid size etc.
 *
 * Cheap/lossy Formula:
 *  max_displays * (max_lut_size + edid(128) + structs)
 *
 * Other nasty bit is that the device mapping isn't exposed directly, it's the
 * user- controlled parts of the engine that has to provide the actual tables
 * to use. On top of that, there's the situation where displays are hotplugged
 * and/or moved between ports and that we might want to control virtual/
 * simulated/remote displays and just take advantage of an external clients
 * color management capabilities.
 *
 * TL:DR - Doesn't make much sense saving a few k here.
 */
	if (proto & SHMIF_META_CM){
		size_t lim = default_disp_lim;
		dofs->ofs_ramp = dofs->sz_ramp = tot;
		lim *= 2; /* both in and out */

/* WARNING: the max_lut_size is not actually used / retrieved here */
		tot += sizeof(struct arcan_shmif_ramp) +
			sizeof(struct ramp_block) * lim;
		dofs->sz_ramp = tot - dofs->sz_ramp;
	}
	else {
		dofs->ofs_ramp = dofs->sz_ramp = 0;
	};

	if (tot % sizeof(max_align_t) != 0)
		tot += tot - (tot % sizeof(max_align_t));

	if (proto & SHMIF_META_HDR){
/* nothing now, possibly reserved for tone-mapping */
	}
	dofs->ofs_hdr = dofs->sz_hdr = 0;

	if (proto & SHMIF_META_VENC){
		dofs->ofs_venc = dofs->sz_venc = tot;
		tot += sizeof(struct arcan_shmif_venc);
		dofs->sz_venc = tot - dofs->sz_venc;
	}

	if (tot % sizeof(max_align_t) != 0)
		tot += tot - (tot % sizeof(max_align_t));

	if (proto & SHMIF_META_VR){
		dofs->ofs_vr = dofs->sz_vr = tot;
		tot += sizeof(struct arcan_shmif_vr);
		tot += sizeof(struct vr_limb) * LIMB_LIM;
		dofs->sz_vr = tot - dofs->sz_vr;
	}
	else
		dofs->sz_vr = dofs->ofs_vr = 0;

	if (tot % sizeof(max_align_t) != 0)
		tot += tot - (tot % sizeof(max_align_t));

	return tot;
}

/*
 * size, allocate and fill out the necessary members for a segment with
 * the specific id, dimensions and tag
 */
static bool prepare_segment(struct arcan_frameserver* ctx,
	int segid, int hints, size_t hintw, size_t hinth, bool named,
	const char* optkey, int optdesc, uintptr_t tag)
{
	size_t abufc = 0;
	size_t abufsz = 0;

/*
 * Normally, subsegments don't get any audiobuffers unless the recipient
 * ask for it during a resize/negotiation. We ignore this for the encoder
 * case as there's currently no negotiation protocol in place.
 */
	if (segid == SEGID_ENCODER){
		abufc = 1;
		abufsz = 65535;
	}

	ctx->shm.shmsize = shmpage_size(hintw, hinth, 1, abufc, abufsz, 0);

	if (!shmalloc(ctx, named, optkey, optdesc))
		return NULL;

	struct arcan_shmif_page* shmpage = ctx->shm.ptr;

	jmp_buf out;
	if (0 != setjmp(out)){
		platform_fsrv_destroy(ctx);
		return NULL;
	}

/* write the new settings to our shmalloced block */
	platform_fsrv_enter(ctx, out);
		shmpage->w = hintw;
		shmpage->h = hinth;
		shmpage->hints = hints;
		shmpage->vpending = 1;
		shmpage->abufsize = abufsz;
		shmpage->apending = abufc;
		shmpage->segment_size = arcan_shmif_mapav(shmpage,
			ctx->vbufs, 1, hintw * hinth * sizeof(shmif_pixel),
			ctx->abufs, abufc, abufsz
		);
	platform_fsrv_leave();

	ctx->desc = (struct arcan_frameserver_meta){
		.width = hintw,
		.height = hinth,
		.samplerate = ARCAN_SHMIF_SAMPLERATE,
		.channels = ARCAN_SHMIF_ACHANNELS,
		.bpp = sizeof(av_pixel)
	};

/*
 * We monitor the same PID as parent, but for cases where we don't monitor
 * parent (non-auth) we switch to using the socket as indicator.
 */
	ctx->launchedtime = arcan_timemillis();
	ctx->flags.alive = true;
	ctx->segid = segid;

/*
 * prepare A/V buffers, map up queue controls
 */
	ctx->vbuf_cnt = 1;
	ctx->abuf_cnt = abufc;
	ctx->abuf_sz = abufsz;
	ctx->tag = tag;
	fsrv_setevqs(ctx->shm.ptr, &(ctx->inqueue), &(ctx->outqueue));
	ctx->inqueue.synch.killswitch = (void*) ctx;
	ctx->outqueue.synch.killswitch = (void*) ctx;

	return ctx;
}

/*
 * Allocate a new segment (shmalloc), inherit the relevant tracking members
 * from the parent, re-use the segment to notify the new key to be used, mark
 * the segment as pending and set a transitional feed-function that looks for
 * an ident on the socket.
 */
struct arcan_frameserver* platform_fsrv_spawn_subsegment(
	struct arcan_frameserver* ctx, int segid, int hints,
	size_t hintw, size_t hinth, uintptr_t tag, uint32_t reqid)
{
	if (!ctx || ctx->flags.alive == false)
		return NULL;

	hintw = hintw == 0 || hintw > ARCAN_SHMPAGE_MAXW ? 32 : hintw;
	hinth = hinth == 0 || hinth > ARCAN_SHMPAGE_MAXH ? 32 : hinth;

	bool forced_bit = !!(segid & (1 << 31));
	segid &= ~(1 << 31);

	arcan_frameserver* newseg = platform_fsrv_alloc();
	if (!newseg)
		return NULL;

	if (!prepare_segment(newseg, segid, hints, hintw, hinth, false, NULL, -1, tag)){
		arcan_mem_free(newseg);
		return NULL;
	}

/* minor parent relationship tracking */
	if (ctx->source)
		newseg->source = strdup(ctx->source);

	newseg->parent.vid = ctx->vid;
	newseg->parent.ptr = (void*) ctx;
	newseg->vid = tag;

/*
 * We monitor the same PID as parent, but for cases where we don't monitor
 * parent (non-auth) we switch to using the socket as indicator.
 */
	newseg->child = ctx->child;

/* Set this to make sure that the 'resized' event goes through even when the
 * client subsegment can submit without renegotiating.
 */
	newseg->desc.rz_flag = true;

/* Socket pair used for transfer of descriptors where we don't have
 * DuplicateHandle and for I/O multiplexing (pinging the socket with empty data
 * to let the client end incorporate into other event loop)
 */
	int sockp[2] = {-1, -1};
	if (!sockpair_alloc(sockp, 1, true)){
		platform_fsrv_destroy(newseg);
		return NULL;
	}

/*
 * We finally have a completed segment with all tracking, buffering etc.  in
 * place, send it to the frameserver to map and use. Also send the memory fd
 * attached to the same CMSG as putting it on the sockpair separately will fail
 * through 'connection reset by peer'. Shmif will map this into the key
 */
	newseg->dpipe = sockp[0];
	arcan_pushhandle(sockp[1], ctx->dpipe);
	arcan_pushhandle(newseg->shm.handle, sockp[0]);
	close(sockp[1]);

	arcan_event keyev = {
		.category = EVENT_TARGET, .tgt.kind = TARGET_COMMAND_NEWSEGMENT
	};

	keyev.tgt.ioevs[1].iv = segid == SEGID_ENCODER ? 1 : 0;
	keyev.tgt.ioevs[2].iv = segid;
	keyev.tgt.ioevs[3].iv = reqid;

/*
 * Forward the segment token for the NEW segment as part of the event, the
 * reason for this is to allow the trusted middle-man in a HANDOVER connection
 * to be able to viewport-event the child without mapping it.
 */
	keyev.tgt.ioevs[4].uiv = newseg->cookie;
	keyev.tgt.ioevs[5].iv = forced_bit;

/* manually queue rather than pushevent */
	TRAMP_GUARD(NULL, newseg);
		struct arcan_evctx* evctx = &ctx->outqueue;
		if ( ((*evctx->back + 1) % evctx->eventbuf_sz) == *evctx->front){
			platform_fsrv_leave();
			return NULL;
		}
		evctx->eventbuf[*evctx->back] = keyev;

	FORCE_SYNCH();
	*evctx->back = (*evctx->back + 1) % evctx->eventbuf_sz;
	platform_fsrv_leave();

/*
 * This special case is worth noting, should a HANDOVER subsegment be provided,
 * we detach the parent relationship as the sheer purpose is to act as a proxy
 * for a client that can't retrieve a connection by some other means.
 */
	if (segid == SEGID_HANDOVER){
		newseg->segid = SEGID_UNKNOWN;
		newseg->parent.ptr = NULL;
		newseg->parent.vid = ARCAN_EID;
	}

	return newseg;
}

int platform_fsrv_pushevent(arcan_frameserver* dst, arcan_event* ev)
{
	if (!dst || !ev || !dst->outqueue.back)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	TRAMP_GUARD(ARCAN_ERRC_UNACCEPTED_STATE, dst);

	if (!dst->flags.alive || !dst->shm.ptr || !dst->shm.ptr->dms){
		platform_fsrv_leave();
		return ARCAN_ERRC_UNACCEPTED_STATE;
	}

/* if the type is masked, then drop silently */
	if (ev->category == EVENT_IO && (
		(dst->devicemask & ev->io.devkind) || (dst->datamask & ev->io.datatype))){
		platform_fsrv_leave();
		return ARCAN_OK;
	}

	struct arcan_evctx* ctx = &dst->outqueue;
	if ( ((*ctx->back + 1) % ctx->eventbuf_sz) == *ctx->front){
		platform_fsrv_leave();
		return ARCAN_ERRC_OUT_OF_SPACE;
	}

	ctx->eventbuf[*ctx->back] = *ev;

	FORCE_SYNCH();
	*ctx->back = (*ctx->back + 1) % ctx->eventbuf_sz;

#ifndef MSG_DONTWAIT
#define MSG_DONTWAIT 0
#endif

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

/*
 * Since the support for multiplexing on semaphores is limited at best,
 * we also have the option of pinging the socket as a possible wakeup.
 */
	arcan_pushhandle(-1, dst->dpipe);
	platform_fsrv_leave();
	return ARCAN_OK;
}

int platform_fsrv_socketauth(struct arcan_frameserver* tgt)
{
	char ch;
	size_t ntw;

	if (!arcan_pushhandle(tgt->shm.handle, tgt->dpipe)){
		arcan_warning("couldn't send shared memory handle over socket");
		errno = EBADF;
		return -1;
	}

	return 0;
}

int platform_fsrv_socketpoll(struct arcan_frameserver* tgt)
{
/* if we're not in a pending state, just return normal. */
	bool term;
	if (!fd_avail(tgt->dpipe, &term)){
		if (term){
			errno = EBADF;
			return -1;
		}
		errno = EAGAIN;
		return -1;
	}

	int newfd = accept(tgt->dpipe, NULL, NULL);
	int oldfd = tgt->dpipe;
	if (-1 == newfd){
		errno = EAGAIN;
		return -1;
	}

	int flags = fcntl(tgt->dpipe, F_GETFL);
	fcntl(newfd, F_SETFL, flags | O_NONBLOCK);

	free(tgt->sockaddr);
	tgt->sockaddr = NULL;
	tgt->dpipe = newfd;
	return oldfd;
}

/*
 * reset the fields of the adata- struct due to a negotiation
 */
static void fsrv_setproto(arcan_frameserver* ctx,
	unsigned proto, struct arcan_shmif_ofstbl* aofs)
{
	if (!ctx || !aofs)
		return;

	memset(&ctx->desc.aext, '\0', sizeof(ctx->desc.aext));
	ctx->desc.aofs = *aofs;

	if (!proto)
		return;

/* first, use the baseadr and the offset table to relocate the struct-
 * pointers in the desc.aext structure */
	uintptr_t base = (uintptr_t)
		(((struct arcan_shmif_page*) ctx->shm.ptr)->adata);
	struct arcan_shmif_ofstbl* dst = (struct arcan_shmif_ofstbl*) base;
	*dst = *aofs;

	size_t ofs = 0;

	if (proto & SHMIF_META_CM){
		size_t lim = default_disp_lim;
		ctx->desc.aext.gamma = (struct arcan_shmif_ramp*)(base + aofs->ofs_ramp);
		memset(ctx->desc.aext.gamma, '\0', aofs->sz_ramp);
/* just some magic value in terms of screen limits unless we've been
 * provided with one */
		lim = lim ? lim : 4;
		lim *= 2; /* both in and out */
		ctx->desc.aext.gamma->magic = ARCAN_SHMIF_RAMPMAGIC;
		ctx->desc.aext.gamma->n_blocks = lim;
/* we don't actually fill out the data here yet, the scripts need to tell
 * us explicitly which outputs that should be presented and in which order,
 * that's done in the setramps/getramps */
	}
	else
		ctx->desc.aext.gamma = NULL;

/* The hinted metadata comes as per target_displayhint with a reference
 * display, that stage checks for hdr metadata, locks and updates. In the other
 * direction metadata is transferred on sigvid synch */
	if (proto & SHMIF_META_HDR){
		ctx->desc.aext.hdr = (struct arcan_shmif_hdr*)(base + aofs->ofs_hdr);
		memset(ctx->desc.aext.hdr, '\0', aofs->sz_hdr);
	}
	else
		ctx->desc.aext.hdr = NULL;

	if (proto & SHMIF_META_VR){
		ctx->desc.aext.vr =
			(struct arcan_shmif_vr*)(base + aofs->ofs_vr);
		memset(ctx->desc.aext.vr, '\0', aofs->sz_vr);
		ctx->desc.aext.vr->version = VR_VERSION;
		ctx->desc.aext.vr->limb_lim = LIMB_LIM;
	}
	else
		ctx->desc.aext.vr = NULL;

	if (proto & SHMIF_META_VENC){
		ctx->desc.aext.venc =
			(struct arcan_shmif_venc*)(base + aofs->ofs_venc);
		memset(ctx->desc.aext.venc, '\0', aofs->sz_venc);
	}
	else
		ctx->desc.aext.venc = NULL;

	ctx->desc.aproto = proto;
}

size_t platform_fsrv_default_abufsize(size_t new_sz)
{
	size_t res = default_abuf_sz;
	if (new_sz > 0)
		default_abuf_sz = new_sz;
	return res;
}

size_t platform_fsrv_display_limit(size_t new_sz)
{
	size_t res = default_disp_lim;
	if (new_sz)
		default_disp_lim = new_sz;
	return res;
}

int platform_fsrv_resynch(struct arcan_frameserver* s)
{
	int state = 0;
	struct shm_handle* src = &s->shm;
	struct arcan_shmif_page* shmpage = s->shm.ptr;

/* local copy so we don't fall victim for TOCTU */
	size_t w = atomic_load(&shmpage->w);
	size_t h = atomic_load(&shmpage->h);
	size_t abufsz = atomic_load(&shmpage->abufsize);
	size_t vbufc = atomic_load(&shmpage->vpending);
	size_t abufc = atomic_load(&shmpage->apending);
	size_t samplerate = atomic_load(&shmpage->audiorate);
	size_t rows = atomic_load(&shmpage->rows);
	size_t cols = atomic_load(&shmpage->cols);
	unsigned aproto = atomic_load(&shmpage->apad_type) & s->metamask;

	vbufc = vbufc > FSRV_MAX_VBUFC ? FSRV_MAX_VBUFC : vbufc;
	abufc = abufc > FSRV_MAX_ABUFC ? FSRV_MAX_ABUFC : abufc;
	vbufc = vbufc == 0 ? 1 : vbufc;

/*
 * Determine if we should switch/ enable privileged subprotocols.
 * This requires the metamask to be updated (which can be done at the preroll
 * or register stage)
 */
	struct arcan_shmif_ofstbl apend = {};
	size_t apad_sz = fsrv_protosize(s, aproto, &apend);
	bool reset_proto = s->desc.aproto != aproto;

/*
 * you can potentially have a really big audiobuffer (or well, quite a few 64k
 * ones unless we exceed the upper limit, but by setting 0 there's the
 * indication that we want the size that match the output device the best.
 * Currently, we can't know this and there's a pending audio subsystem refactor
 * to remedy this (kindof) but for now, just have it as a user controlled var.
 */
	if (abufsz < default_abuf_sz)
		abufsz = default_abuf_sz;

/*
 * pending the same audio refactoring, we just assume the audio layer
 * accepts whatever samplerate and resamples itself if absolutely necessary
 */
	if (samplerate)
		s->desc.samplerate = samplerate;

/* shrink number of video buffers if we don't fit */
	size_t shmsz;
	do{
		shmsz = shmpage_size(w, h, vbufc, abufc, abufsz, apad_sz);
	} while (shmsz > ARCAN_SHMPAGE_MAX_SZ && vbufc-- > 1);

/* initial sanity check */
	if (shmsz > ARCAN_SHMPAGE_MAX_SZ || (s->max_w && w > s->max_w) ||
		(s->max_h && h > s->max_h))
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
	atomic_store(&shmpage->rows, rows);
	atomic_store(&shmpage->cols, cols);

	s->desc.width = w;
	s->desc.height = h;
	s->desc.rows = rows;
	s->desc.cols = cols;
	s->desc.pending_hints = atomic_load(&shmpage->hints);
	s->vbuf_cnt = vbufc;
	s->abuf_cnt = abufc;

/* authenticate if needed */
#ifdef PLATFORM_VIDEO_DRMAUTH
	if (s->desc.pending_hints & SHMIF_RHINT_AUTH_TOK){
		unsigned token = atomic_load(&shmpage->vpts);
		s->desc.pending_hints &= ~SHMIF_RHINT_AUTH_TOK;
		atomic_store(&shmpage->hints, s->desc.pending_hints);

/* MULTI/GPU NOTE: need to look at the primary- GPU for this fsrv */
		if (!s->flags.gpu_auth || !platform_video_auth(0, token))
			goto fail;
	}
#endif

/* Still incomplete for TPACK etc. as w/h needs to be determined based on
 * the active cell dimensions and not of the pixel dimensions */
	size_t vbufsz = arcan_shmif_vbufsz(aproto,
		s->desc.pending_hints, w, h, s->desc.rows, s->desc.cols);

/* remap pointers, padding need to be updated first as shmif_mapav
 * uses that as a side-channel and we don't want to change the interface */
	atomic_store(&shmpage->apad, apad_sz);
	shmpage->segment_size = arcan_shmif_mapav(shmpage,
		s->vbufs, s->vbuf_cnt, vbufsz, s->abufs, s->abuf_cnt, abufsz);
	s->abuf_sz = abufsz;
	fsrv_setevqs(shmpage, &(s->inqueue), &(s->outqueue));

/* commit to shared page */
	shmpage->resized = 0;
	shmpage->abufsize = abufsz;
	shmpage->apending = s->abuf_cnt;
	shmpage->vpending = s->vbuf_cnt;

/* realize the sub-protocol */
	if (reset_proto){
		fsrv_setproto(s, aproto, &apend);
		atomic_store(&shmpage->apad_type, aproto);
		state = 2;
	}
	else
		state = 1;

	goto done;

/* couldn't resize, restore contents. this shouldn't be "needed" but is a
 * protection for clients that erroneously use .addr->** rather than the
 * context-local copy */
fail:
	atomic_store(&shmpage->abufsize, abufsz);
	atomic_store(&shmpage->apending, s->abuf_cnt);
	atomic_store(&shmpage->vpending, s->vbuf_cnt);
	atomic_store(&shmpage->w, s->desc.width);
	atomic_store(&shmpage->h, s->desc.height);
	atomic_store(&shmpage->cols, s->desc.cols);
	atomic_store(&shmpage->rows, s->desc.rows);
	shmpage->resized = -1;
	state = -1;

done:
/* barrier + signal */
	FORCE_SYNCH();
	shmpage->vsync = 0xffffffff;
	return state;
}

struct arcan_frameserver* platform_fsrv_listen_external(const char* key,
	const char* auth, int fd, mode_t mode, size_t w, size_t h, uintptr_t tag)
{
	arcan_frameserver* newseg = platform_fsrv_alloc();
	newseg->sockmode = mode;
	if (!prepare_segment(newseg, SEGID_UNKNOWN, 0, w, h, true, key, fd, tag)){
		arcan_mem_free(newseg);
		return NULL;
	}

	return newseg;
}

struct arcan_frameserver* platform_fsrv_preset_server(
	int sockin, int segid, size_t w, size_t h, uintptr_t tag)
{
	arcan_frameserver* newseg = platform_fsrv_alloc();
	if (!newseg)
		return NULL;

	if (!prepare_segment(newseg, segid, 0, w, h, false, NULL, -1, tag)){
		arcan_mem_free(newseg);
		return NULL;
	}

	newseg->dpipe = sockin;
	return newseg;
}

struct arcan_frameserver* platform_fsrv_spawn_server(
	int segid, size_t w, size_t h, uintptr_t tag, int* childfd)
{
	arcan_frameserver* newseg = platform_fsrv_alloc();
	if (!newseg)
		return NULL;

	if (!prepare_segment(newseg, segid, 0, w, h, false, NULL, -1, tag)){
		arcan_mem_free(newseg);
		return NULL;
	}

	int sockp[4] = {-1, -1};
	if (!sockpair_alloc(sockp, 1, true)){
		platform_fsrv_destroy(newseg);
		return NULL;
	}

	newseg->dpipe = sockp[0];
	*childfd = sockp[1];

	arcan_pushhandle(*childfd, newseg->shm.handle);

	return newseg;
}
