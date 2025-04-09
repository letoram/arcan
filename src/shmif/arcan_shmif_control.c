/*
 * Copyright 2012-2021, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <errno.h>
#include <time.h>
#include <limits.h>
#include <assert.h>
#include <string.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdatomic.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <pthread.h>

#include "arcan_shmif.h"
#include "platform/shmif_platform.h"
#include "shmif_privext.h"
#include "shmif_privint.h"
#include "shmif_defimpl.h"

#include <signal.h>
#include <poll.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>

#ifdef __LINUX
#include <sys/inotify.h>
#endif

_Static_assert(sizeof(struct mstate) == ASHMIF_MSTATE_SZ, "invalid mstate sz");

/*
 * Accessor for redirectable log output related to a shmif context
 * The context association is a placeholder for being able to handle
 * context- specific log output devices later.
 */
static _Atomic volatile uintptr_t log_device;
FILE* shmif_platform_log_device(struct arcan_shmif_cont* c)
{
	FILE* res = (FILE*)(void*) atomic_load(&log_device);
	if (res)
		return res;

	return stderr;
}

void shmif_platform_set_log_device(struct arcan_shmif_cont* c, FILE* outdev)
{
	atomic_store(&log_device, (uintptr_t)(void*)outdev);
}

static uint64_t g_epoch;

void arcan_random(uint8_t*, size_t);

/*
 * The guard-thread thing tries to get around all the insane edge conditions
 * that exist when you have a partial parent<->child circular dependency with
 * an untrusted child and a limited set of IPC primitives (from portability
 * constraints).
 *
 * When some monitored condition (process dies, shmpage doesn't validate,
 * dead man switch has been pulled), we also dms, then forcibly release
 * the semaphores used for synch, and optionally some user supplied callback
 * function.
 *
 * Thereafter, functions that depend on the shmpage will use their failure path
 * (or forcibly exit if a FATALFAIL behavior has been set) and event triggered
 * functions will fail.
 */

/* We let one 'per process singleton' slot for an input and for an output
 * segment as a primitive discovery mechanism. This is managed (mostly) by the
 * caller, though cleaned up on certain calls like _drop etc. to avoid UAF. */
static struct {
	struct arcan_shmif_cont* input, (* output), (*accessibility);
} primary;

#ifndef offsetof
#define offsetof(type, member) ((size_t)((char*)&(*(type*)0).member\
 - (char*)&(*(type*)0)))
#endif

uint64_t arcan_shmif_cookie()
{
	uint64_t base = sizeof(struct arcan_event) + sizeof(struct arcan_shmif_page);
	base |= (uint64_t)offsetof(struct arcan_shmif_page, cookie)  <<  8;
	base |= (uint64_t)offsetof(struct arcan_shmif_page, resized) << 16;
	base |= (uint64_t)offsetof(struct arcan_shmif_page, aready)  << 24;
	base |= (uint64_t)offsetof(struct arcan_shmif_page, abufused)<< 32;
	base |= (uint64_t)offsetof(struct arcan_shmif_page, childevq.front) << 40;
	base |= (uint64_t)offsetof(struct arcan_shmif_page, childevq.back) << 48;
	base |= (uint64_t)offsetof(struct arcan_shmif_page, parentevq.front) << 56;
	return base;
}

void arcan_shmif_defimpl(
	struct arcan_shmif_cont* newchild, int type, void* typetag)
{
#ifdef SHMIF_DEBUG_IF
	if (type == SEGID_DEBUG &&
		arcan_shmif_debugint_spawn(newchild, typetag, NULL)){
		return;
	}
#endif

	arcan_shmif_drop(newchild);
}

bool arcan_shmif_handle_permitted(struct arcan_shmif_cont* ctx)
{
	return (ctx && ctx->privext && ctx->privext->state_fl != STATE_NOACCEL);
}

int arcan_shmif_poll(struct arcan_shmif_cont* c, struct arcan_event* dst)
{
	if (!c || !c->priv || !c->priv->alive)
		return -1;

	if (c->priv->valid_initial)
		shmifint_drop_initial(c);

	int rv = shmifint_process_events(c, dst, false, false);

/* the stepframe events can be so frequent as to mandate verbose logging */
	if (rv > 0 && c->priv->log_event){
		if (dst->category == EVENT_TARGET &&
			dst->tgt.kind == TARGET_COMMAND_STEPFRAME && c->priv->log_event < 2)
			return rv;

		log_print("[%"PRIu64":%"PRIu32"] <- %s",
			(uint64_t) arcan_timemillis() - g_epoch,
			(uint32_t) c->cookie, arcan_shmif_eventstr(dst, NULL, 0));
	}
	return rv;
}

int arcan_shmif_wait_timed(
	struct arcan_shmif_cont* c, unsigned* time_ms, struct arcan_event* dst)
{
	if (!c || !c->priv || !c->priv->alive)
		return 0;

	if (c->priv->valid_initial)
		shmifint_drop_initial(c);

	unsigned beg = arcan_timemillis();

	int timeout = *time_ms;
	struct pollfd pfd = {
		.fd = c->epipe,
		.events = POLLIN | POLLERR | POLLHUP | POLLNVAL
	};

	int rv = poll(&pfd, 1, timeout);
	int elapsed = arcan_timemillis() - beg;
	*time_ms = (elapsed < 0 || elapsed > timeout) ? 0 : timeout - elapsed;

	if (1 == rv){
		return arcan_shmif_wait(c, dst);
	}

	return 0;
}

int arcan_shmif_wait(struct arcan_shmif_cont* c, struct arcan_event* dst)
{
	if (!c || !c->priv || !c->priv->alive)
		return false;

	if (c->priv->valid_initial)
		shmifint_drop_initial(c);

	int rv = shmifint_process_events(c, dst, true, false);
	if (rv > 0 && c->priv->log_event){
		if (dst->category == EVENT_TARGET &&
			dst->tgt.kind == TARGET_COMMAND_STEPFRAME && c->priv->log_event < 2)
			return rv > 0;

		log_print("(@%"PRIxPTR"<-)%s",
			(uintptr_t) c, arcan_shmif_eventstr(dst, NULL, 0));
	}
	return rv > 0;
}

static int enqueue_internal(
	struct arcan_shmif_cont* c, const struct arcan_event* const src, bool try)
{
	assert(c);
	if (!c || !c->addr || !c->priv)
		return -1;

	if (!src)
		return 0;

	struct shmif_hidden* P = c->priv;

/*
 * Sending TARGET is normally not permitted, but there are use-cases where one
 * might want to 'fake' events between multiple segments on different threads.
 * A special one there is _EXIT to trigger shutdown of a segment from
 * elsewhere.
 */
	if (src->category == EVENT_TARGET){
		if (src->tgt.kind == TARGET_COMMAND_EXIT){
			P->alive = false;
			shmif_platform_sync_post(c->addr, SYNC_EVENT | SYNC_AUDIO | SYNC_VIDEO);
			return 1;
		}
		return 0;
	}

/* this is dangerous territory: many _enqueue calls are done without checking
 * the return value, so chances are that some event will be dropped. In the
 * crash- recovery case this means that if the migration goes through, we have
 * either an event that might not fit in the current context, or an event that
 * gets lost. Neither is good. The counterargument is that crash recovery is a
 * 'best effort basis' - we're still dealing with an actual crash. */
	if (!shmif_platform_check_alive(c) && !try){
		shmif_platform_fallback(c, P->alt_conn, true);
		return 0;
	}

/* need some extra patching up for log-event to contain the proper values */
	if (P->log_event){
		struct arcan_event outev = *src;
		if (!outev.category){
			outev.category = EVENT_EXTERNAL;
		}
		if (outev.category == EVENT_EXTERNAL)
			outev.ext.frame_id = P->vframe_id;

		log_print("(@%"PRIxPTR"->)%s",
			(uintptr_t) c, arcan_shmif_eventstr(&outev, NULL, 0));
	}

	struct arcan_evctx* ctx = &P->outev;

/* paused only set if segment is configured to handle it,
 * and process_events on blocking will block until unpaused */
	if (P->paused){
		struct arcan_event ev;
		shmifint_process_events(c, &ev, true, true);
	}

	while ( shmif_platform_check_alive(c) &&
			((*ctx->back + 1) % ctx->eventbuf_sz) == *ctx->front){
		struct arcan_event outev = *src;
		debug_print(INFO, c,
			"=> %s: outqueue is full, waiting", arcan_shmif_eventstr(&outev, NULL, 0));
		shmif_platform_sync_wait(c->addr, SYNC_EVENT);
	}

	int category = src->category;
	ctx->eventbuf[*ctx->back] = *src;
	if (!category)
		ctx->eventbuf[*ctx->back].category = category = EVENT_EXTERNAL;

/* Some events affect internal state tracking, synch those here - not
 * particularly expensive as the frequency and max-rate of events
 * client->server is really low. Tag the event with the last signalled frame
 * for it to act as a clock. */
	if (category == EVENT_EXTERNAL){
		ctx->eventbuf[*ctx->back].ext.frame_id = P->vframe_id;

		if (src->ext.kind == ARCAN_EVENT(REGISTER)){

			if (src->ext.registr.guid[0] || src->ext.registr.guid[1]){
				P->guid[0] = src->ext.registr.guid[0];
				P->guid[1] = src->ext.registr.guid[1];
			}

/* Changing the type post first register is a no-op normally. The edge case is
 * when/if the register event was deferred (NOREGISTER) as part of handover or
 * just special needs AND a migrate event happens later. That would have the
 * internally tracked type to be SEGID_UNKNOWN (forcing its frame delivery to
 * be blocked in the recipient) and the injected on-migrate REGISTER would
 * propagate.
 *
 * That's why we need to update the type and not just the GUID.
 */
			if (src->ext.registr.kind && P->type == SEGID_UNKNOWN)
				P->type = src->ext.registr.kind;
		}
	}

	FORCE_SYNCH();
	*ctx->back = (*ctx->back + 1) % ctx->eventbuf_sz;

	if (P->flags & SHMIF_SOCKET_PINGEVENT){
		char pb = '1';
		write(c->epipe, &pb, 1);
	}

	return 1;
}

int arcan_shmif_enqueue(
	struct arcan_shmif_cont* c, const struct arcan_event* const src)
{
	return enqueue_internal(c, src, false);
}

int arcan_shmif_tryenqueue(
	struct arcan_shmif_cont* c, const arcan_event* const src)
{
	return enqueue_internal(c, src, true);
}

void arcan_shmif_unlink(struct arcan_shmif_cont* dst)
{
/* deprecated, not neeed anymore */
}

const char* arcan_shmif_segment_key(struct arcan_shmif_cont* dst)
{
/* deprecated, not needed anymore */
	return NULL;
}

static bool ensure_stdio()
{
/* this would create a stdin that is writable, but that is a lesser evil */
	int fd = 0;
	while (fd < STDERR_FILENO && fd != -1)
		fd = open("/dev/null", O_RDWR);

	if (fd > STDERR_FILENO)
		close(fd);

	if (-1 == fd)
		return false;

	return true;
}

static void map_shared(int fd, struct arcan_shmif_cont* dst)
{
	struct shmif_hidden* P = dst->priv;

/* This has happened, and while 'technically' legal - it can (and will in most
 * cases) lead to nasty bugs. Since we need to keep the descriptor around in
 * order to resize/remap, chances are that some part of normal processing will
 * printf to stdout, stderr - potentially causing a write into the shared
 * memory page. The server side will likely detect this due to the validation
 * cookie failing, causing it to terminate the connection. */
	if (fd <= STDERR_FILENO){
		debug_print(FATAL, dst, "[stdin, stderr, stdout] unmapped, refusing");
		return;
	}

	dst->addr = mmap(NULL,
		ARCAN_SHMPAGE_START_SZ, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	dst->shmh = fd;


/* parent suggested a different size from the start, need to remap */
	if (dst->addr->segment_size != (size_t) ARCAN_SHMPAGE_START_SZ){
		debug_print(INFO, dst, "different initial size, remapping.");
		size_t sz = dst->addr->segment_size;
		munmap(dst->addr, ARCAN_SHMPAGE_START_SZ);
		dst->addr = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
		if (MAP_FAILED == dst->addr)
			goto map_fail;
	}

	debug_print(INFO, dst, "segment mapped to %" PRIxPTR, (uintptr_t) dst->addr);

	if (MAP_FAILED == dst->addr){
map_fail:
		debug_print(FATAL, dst,
			"couldn't shmpage from descriptor: reason: %s", strerror(errno));
		close(fd);
		dst->addr = NULL;
		return;
	}
}

/*
 * The rules for socket sharing are shared between all
 */
 int arcan_shmif_resolve_connpath(
	const char* key, char* dbuf, size_t dbuf_sz)
{
	return shmif_platform_connpath(key, dbuf, dbuf_sz, 0);
}

static void shmif_exit(int c)
{
	debug_print(FATAL, NULL, "guard thread empty");
}

char* arcan_shmif_connect(
	const char* connpath, const char* connkey, int* conn_ch)
{
	struct sockaddr_un dst = {
		.sun_family = AF_UNIX
	};
	size_t lim = COUNT_OF(dst.sun_path);
	char fdstr[16] = "";

	if (!connpath){
		debug_print(FATAL, NULL, "missing connection path");
		return NULL;
	}

	int len;
	char* res = NULL;
	int index = 0;
	int sock = -1;

retry:
	len = shmif_platform_connpath(connpath, (char*)&dst.sun_path, lim, index++);

	if (len < 0){
		debug_print(FATAL, NULL, "couldn't resolve connection path");
		if (sock != -1)
			close(sock);
		return NULL;
	}

/* 1. treat connpath as socket and connect */
	if (sock == -1)
		sock = socket(AF_UNIX, SOCK_STREAM, 0);

	if (-1 == sock){
		debug_print(FATAL, NULL, "couldn't allocate socket: %s", strerror(errno));
		goto end;
	}

#ifdef __APPLE__
	setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &(int){1}, sizeof(int));
#endif

/* if connection fails, the socket will be re-used with a different address
 * until we run out - this normally will just involve XDG_RUNTIME_DIR then HOME */
	if (connect(sock, (struct sockaddr*) &dst, sizeof(dst))){
		debug_print(FATAL, NULL,
			"couldn't connect to (%s): %s", dst.sun_path, strerror(errno));
		goto retry;
	}

/* 2. wait for key response (or broken socket) */
	int memfd = shmif_platform_mem_from_socket(sock);
	if (-1 == memfd){
		debug_print(FATAL, NULL, "Couldn't get memory from socket: %s", strerror(errno));
		close(sock);
		return NULL;
	}

/* 3. enable timeout for recvmsg so we don't risk being blocked indefinitely */
	setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO,
		&(struct timeval){.tv_sec = 1}, sizeof(struct timeval));

	*conn_ch = sock;
	snprintf(fdstr, sizeof(fdstr), "%d", memfd);

/* 4. in order to not break API we need to return this as a string, as before
 *    this used to be a named prefix from which we found the other primitives.*/
end:
	return strdup(fdstr);
}

static void setup_avbuf(struct arcan_shmif_cont* res)
{
/* flush out dangling buffers */
	memset(res->priv->vbuf, '\0', sizeof(void*) * ARCAN_SHMIF_VBUFC_LIM);
	memset(res->priv->abuf, '\0', sizeof(void*) * ARCAN_SHMIF_ABUFC_LIM);

	res->w = atomic_load(&res->addr->w);
	res->h = atomic_load(&res->addr->h);
	res->stride = res->w * ARCAN_SHMPAGE_VCHANNELS;
	res->pitch = res->w;
	res->priv->atype = atomic_load(&res->addr->apad_type);

	res->priv->vbuf_cnt = atomic_load(&res->addr->vpending);
	res->priv->abuf_cnt = atomic_load(&res->addr->apending);
	res->segment_token = res->addr->segment_token;

	res->priv->abuf_ind = 0;
	res->priv->vbuf_ind = 0;
	res->priv->vbuf_nbuf_active = false;
	atomic_store(&res->addr->vpending, 0);
	atomic_store(&res->addr->apending, 0);
	res->abufused = res->abufpos = 0;
	res->abufsize = atomic_load(&res->addr->abufsize);
	res->abufcount = res->abufsize / sizeof(shmif_asample);
	res->abuf_cnt = res->priv->abuf_cnt;
	res->samplerate = atomic_load(&res->addr->audiorate);
	if (0 == res->samplerate)
		res->samplerate = ARCAN_SHMIF_SAMPLERATE;

/* the buffer limit size needs to take the rhint into account, but only
 * if we have a known cell size as that is the primitive for calculation */
	res->vbufsize = arcan_shmif_vbufsz(
		res->priv->atype, res->hints, res->w, res->h,
		atomic_load(&res->addr->rows),
		atomic_load(&res->addr->cols)
	);

	arcan_shmif_mapav(res->addr,
		res->priv->vbuf, res->priv->vbuf_cnt, res->vbufsize,
		res->priv->abuf, res->priv->abuf_cnt, res->abufsize
	);

/*
 * NOTE, this means that every time we remap/rebuffer, the previous
 * A/V state is lost on our side, no matter if we're changing A, V or A/V.
 */
	res->vidp = res->priv->vbuf[0];
	res->audp = res->priv->abuf[0];

/* mark the entire segment as dirty */
	res->dirty.x1 = res->dirty.y1 = 0;
	res->dirty.x2 = res->w;
	res->dirty.y2 = res->h;
}

/* using a base address where the meta structure will reside, allocate n- audio
 * and n- video slots and populate vbuf/abuf with matching / aligned pointers
 * and return the total size */
static struct arcan_shmif_cont shmif_acquire_int(
	struct arcan_shmif_cont* parent,
	const char* shmkey,
	int type,
	int flags, va_list vargs)
{
	struct arcan_shmif_cont res = {
		.vidp = NULL
	};

	if (!shmkey && (!parent || !parent->priv)){
		return res;
	}

/* placeholder private shmif_hidden to be populated by map_shared */
	res.priv = malloc(sizeof(struct shmif_hidden));
	*res.priv = (struct shmif_hidden){
		.flags = flags,
		.pev = {.fds = {BADFD, BADFD}},
		.pseg = {.epipe = BADFD}
	};
	struct shmif_hidden* P = res.priv;

/* different path based on an acquire from a NEWSEGMENT event or if it comes
 * from a _connect (via _open) call as the former need to pass a connection
 * string. To handle that interface and the legacy from named primitives, the
 * key is just the descriptor number as a string. */
	bool privps = false;

	if (!shmkey){
		struct shmif_hidden* gs = parent->priv;
		if (gs->pev.gotev && gs->pev.ev.tgt.kind == TARGET_COMMAND_NEWSEGMENT){
			if (gs->pev.fds[0] == BADFD){
				debug_print(INFO, parent, "acquire:missing_socket");
				return res;
			}
			if (gs->pev.fds[1] == BADFD){
				debug_print(INFO, parent, "acquire:missing_shm");
				return res;
			}
			gs->pseg.memfd = gs->pev.fds[1];
			gs->pev.fds[1] = BADFD;
			gs->pseg.epipe = gs->pev.fds[0];
			gs->pev.fds[0] = BADFD;
			gs->pev.gotev = false;
		}
		else {
			debug_print(INFO, parent, "acquire:no_matching_event");
			return res;
		}

		map_shared(gs->pseg.memfd, &res);

		if (!res.addr){
			close(gs->pseg.epipe);
			gs->pseg.epipe = BADFD;
		}
		privps = true; /* can't set d/e fields yet */
	}
	else{
		debug_print(INFO, parent, "acquire_shm_key:%s", shmkey);
		long shmfd = strtoul(shmkey, NULL, 10);
		map_shared(shmfd, &res);
	}

	if (!res.addr){
		debug_print(FATAL, NULL, "couldn't connect through: %s", shmkey);
		free(res.priv);
		res.priv = NULL;

		if (flags & SHMIF_ACQUIRE_FATALFAIL)
			exit(EXIT_FAILURE);
		else
			return res;
	}

/* allow the user to hook termination */
	void (*exitf)(int) = shmif_exit;
	if (flags & SHMIF_FATALFAIL_FUNC){
			exitf = va_arg(vargs, void(*)(int));
	}

/* and mark the segment as non-extended */
	res.privext = malloc(sizeof(struct shmif_ext_hidden));
	*res.privext = (struct shmif_ext_hidden){
		.cleanup = NULL,
		.active_fd = -1,
		.pending_fd = -1,
	};

/* if verbose debugging is enabled, set the category bitmap to what the
 * environment requested */
	P->alive = true;
	char* dbgenv = getenv("ARCAN_SHMIF_DEBUG");
	if (dbgenv)
		res.priv->log_event = strtoul(dbgenv, NULL, 10);

	if (!(flags & SHMIF_DISABLE_GUARD) && !getenv("ARCAN_SHMIF_NOGUARD"))
		shmif_platform_guard(&res, (struct watchdog_config){
			.parent_pid = res.addr->parent,
			.parent_fd = -1,
			.exitf = exitf,
			.audio = &(res.addr->async),
			.video = &(res.addr->vsync),
			.event = &(res.addr->esync),
			.relval = 0
		}
	);
/* still need to mark alive so the aliveness check doesn't fail */
	else {
		P->guard.local_dms = true;
	}

/* if this is a secondary segment, we acquire through the parent and it may be
 * a different connection / allocation path where the transmission socket comes
 * as a delay-slot stored descriptor (pseg->epipe) */
	if (privps){
		struct shmif_hidden* pp = parent->priv;

		res.epipe = pp->pseg.epipe;
#ifdef __APPLE__
		int val = 1;
		setsockopt(res.epipe, SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
#endif
		setsockopt(res.epipe, SOL_SOCKET, SO_RCVTIMEO,
			&(struct timeval){.tv_sec = 1}, sizeof(struct timeval));

/* clear this here so consume won't eat it */
		pp->pseg.epipe = BADFD;

/* reset pending descriptor state */
		shmifint_consume_pending(parent);
	}

/* this should be moved to platform for shm handling */
	shmif_platform_setevqs(res.addr, NULL, &res.priv->inev, &res.priv->outev);

/* forward our type, immutable name and GUID. This should also be an open_ext
 * flag VA_ARG so that we can attach to some other identity provider */
	if (0 != type && !(flags & SHMIF_NOREGISTER)) {
		arcan_random((uint8_t*) res.priv->guid, 16);
		struct arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(REGISTER),
			.ext.registr.kind = type,
			.ext.registr.guid = {res.priv->guid[0], res.priv->guid[1]}
		};
		arcan_shmif_enqueue(&res, &ev);
	}

/* ensure that we have the same segment size calculation and version validation
 * cookie (which is periodically checked for corruption as part of the watchdog */
	res.shmsize = res.addr->segment_size;
	res.cookie = arcan_shmif_cookie();
	res.priv->type = type;
	setup_avbuf(&res);

	pthread_mutex_init(&res.priv->lock, NULL);

/* OUTPUT segment types (ENCODER and PASTE) has an inverted synchronisation
 * flow, so mark that in order for step_a(),v() doesn't break the handles */
	if (type == SEGID_ENCODER || type == SEGID_CLIPBOARD_PASTE){
		((struct shmif_hidden*)res.priv)->output = true;
	}

	return res;
}

struct arcan_shmif_cont arcan_shmif_acquire(struct arcan_shmif_cont* parent,
	const char* shmkey,
	int type,
	int flags, ...)
{
	va_list argp;
	va_start(argp, flags);
	struct arcan_shmif_cont res =
		shmif_acquire_int(parent, shmkey, type, flags, argp);
	va_end(argp);
	return res;
}

bool arcan_shmif_integrity_check(struct arcan_shmif_cont* cont)
{
	struct arcan_shmif_page* shmp = cont->addr;
	if (!cont)
		return false;

	if (shmp->major != ASHMIF_VERSION_MAJOR ||
		shmp->minor != ASHMIF_VERSION_MINOR){
		debug_print(FATAL, cont, "integrity fail, version mismatch");
		return false;
	}

	if (shmp->cookie != cont->cookie)
	{
		debug_print(FATAL, cont, "integrity check fail, cookie mismatch");
		return false;
	}

	return true;
}

struct arg_arr* arcan_shmif_args( struct arcan_shmif_cont* inctx)
{
	if (!inctx || !inctx->priv)
		return NULL;
	return inctx->priv->args;
}

void arcan_shmif_drop(struct arcan_shmif_cont* C)
{
	if (!C || !C->priv)
		return;

	struct shmif_hidden* P = C->priv;

	if (P->support_window_hook){
		P->support_window_hook(C, SUPPORT_EVENT_EXIT);
	}

	pthread_mutex_lock(&P->lock);

/* do we still have a copy of the preroll event merge state? */
	if (P->valid_initial)
		shmifint_drop_initial(C);

/* has the user set an error message? */
	if (P->last_words){
		log_print("[shmif:drop] last words: %s", P->last_words);
		free(P->last_words);
		P->last_words = NULL;
	}

/* page mapped? then release the dms. */
	if (C->addr){
		C->addr->dms = false;
	}

/* clear any segment accessor */
	if (C == primary.input)
		primary.input = NULL;

	if (C == primary.output)
		primary.output = NULL;

	if (P->args){
		arg_cleanup(P->args);
	}

/* recovery point is no-longer needed */
	free(P->alt_conn);
	P->alt_conn = NULL;

/* this should be moved to extended segment cleanup */
	if (C->privext->cleanup)
		C->privext->cleanup(C);

	if (C->privext->active_fd != -1)
		close(C->privext->active_fd);

	if (C->privext->pending_fd != -1)
		close(C->privext->pending_fd);

	free(C->privext);
/* end of extended cleanup */

	pthread_mutex_unlock(&P->lock);
	pthread_mutex_destroy(&P->lock);

	shmif_platform_guard_release(C);

/* this should be moved to platform for shm- handling */
	close(C->epipe);
	close(C->shmh);
	munmap(C->addr, C->shmsize);
/* end of shm-handling cleanup */

	memset(C, '\0', sizeof(struct arcan_shmif_cont));
	C->epipe = -1;
}

static bool shmif_resize(struct arcan_shmif_cont* C,
	unsigned width, unsigned height, struct shmif_resize_ext ext)
{
	if (!C->addr || !arcan_shmif_integrity_check(C) ||
	!C->priv || width > PP_SHMPAGE_MAXW || height > PP_SHMPAGE_MAXH)
		return false;

	struct shmif_hidden* P = C->priv;

/* quick rename / unpack as old prototype of this didn't carry ext struct */
	size_t abufsz = ext.abuf_sz;
	int vidc = ext.vbuf_cnt;
	int audc = ext.abuf_cnt;
	int samplerate = ext.samplerate;
	int adata = ext.meta;

/* resize on a dead context triggers migration */
	if (!shmif_platform_check_alive(C)){
		if (P->reset_hook)
			P->reset_hook(SHMIF_RESET_LOST, P->reset_hook_tag);

/* fallback migrate will trigger the reset_hook on REMAP / FAIL */
		if (SHMIF_MIGRATE_OK != shmif_platform_fallback(C, P->alt_conn, true)){
			return false;
		}
	}

	width = width < 1 ? 1 : width;
	height = height < 1 ? 1 : height;

/* 0 is allowed to disable any related data, useful for not wasting
 * storage when accelerated buffer passing is working */
	vidc = vidc < 0 ? P->vbuf_cnt : vidc;
	audc = audc < 0 ? P->abuf_cnt : audc;

	bool dimensions_changed = width != C->w || height != C->h;
	bool bufcnt_changed = vidc != P->vbuf_cnt || audc != P->abuf_cnt;
	bool hints_changed = C->addr->hints != C->hints;
	bool bufsz_changed = abufsz && C->addr->abufsize != abufsz;

/* don't negotiate unless the goals have changed */
	if (C->vidp &&
		!dimensions_changed &&
		!bufcnt_changed &&
		!hints_changed &&
		!bufsz_changed){
		if (P->reset_hook)
			P->reset_hook(SHMIF_RESET_NOCHG, P->reset_hook_tag);

		return true;
	}

/* cancel any pending vsynch */
	if (atomic_load(&C->addr->vready)){
		atomic_store_explicit(&C->addr->vready, 0, memory_order_release);
		if (!shmif_platform_sync_trywait(C->addr, SYNC_VIDEO)){
			shmif_platform_sync_post(C->addr, SYNC_VIDEO);
		}
	}

/* audio drivers on the server end tend to be threaded differently and should
 * have been mutex blocked from feeding while we are in _resize but that is up
 * to the server implementation. The easier approach is to dedicate a segment
 * to audio if the video one will be resized often. Give it a chance to flush
 * here then force ignore it. */
	if (atomic_load(&C->addr->aready)){
		int count = 10;
		while (atomic_load(&C->addr->aready) &&
			shmif_platform_check_alive(C) && count){
			if (!shmif_platform_sync_trywait(C->addr, SYNC_AUDIO))
				count--;
		}
		shmif_platform_sync_post(C->addr, SYNC_AUDIO);
	}

/* synchronize hints as _ORIGO_LL and similar changes only synch on resize */
	atomic_store(&C->addr->hints, C->hints);
	atomic_store(&C->addr->apad_type, adata);

	if (samplerate < 0)
		atomic_store(&C->addr->audiorate, C->samplerate);
	else if (samplerate == 0)
		atomic_store(&C->addr->audiorate, ARCAN_SHMIF_SAMPLERATE);
	else
		atomic_store(&C->addr->audiorate, samplerate);

/* need strict ordering across procss boundaries here, first desired
 * dimensions, buffering etc. THEN resize request flag */
	atomic_store(&C->addr->w, width);
	atomic_store(&C->addr->h, height);
	atomic_store(&C->addr->rows, ext.rows);
	atomic_store(&C->addr->cols, ext.cols);
	atomic_store(&C->addr->abufsize, abufsz);
	atomic_store_explicit(&C->addr->apending, audc, memory_order_release);
	atomic_store_explicit(&C->addr->vpending, vidc, memory_order_release);
	if (P->log_event){
		log_print(
			"(@%"PRIxPTR" rz-synch): %zu*%zu(fl:%d), grid:%zu,%zu %zu Hz",
			(uintptr_t)C, (size_t)width, (size_t)height, (int)C->hints,
			(size_t)ext.rows, (size_t)ext.cols, (size_t)C->samplerate
		);
	}

/* all force synch- calls should be removed when atomicity and reordering
 * behavior have been verified properly */
	FORCE_SYNCH();
	C->addr->resized = 1;
	do{
		shmif_platform_sync_trywait(C->addr, SYNC_VIDEO);
	}
	while (C->addr->resized > 0 && shmif_platform_check_alive(C));

/* post-size data commit is the last fragile moment server-side */
	if (!shmif_platform_check_alive(C)){
		if (P->reset_hook){
			P->reset_hook(SHMIF_RESET_NOCHG, P->reset_hook_tag);
			P->reset_hook(SHMIF_RESET_LOST, P->reset_hook_tag);
		}

		shmif_platform_fallback(C, P->alt_conn, true);
		return false;
	}

/* resized failed, old settings still in effect */
	if (C->addr->resized == -1){
		C->addr->resized = 0;
		if (P->reset_hook)
			P->reset_hook(SHMIF_RESET_NOCHG, P->reset_hook_tag);
		return false;
	}

/*
 * the guard struct, if present, has another thread running that may trigger
 * the dms. BUT now the dms may be relocated so we must lock guard and update
 * and recalculate everything.
 */
	uintptr_t old_addr = (uintptr_t) C->addr;

	if (C->shmsize != C->addr->segment_size){
		size_t new_sz = C->addr->segment_size;

		shmif_platform_guard_lock(C);

/* this should be moved to platform for shm handling */
			munmap(C->addr, C->shmsize);
			C->shmsize = new_sz;
			C->addr = mmap(
				NULL, C->shmsize, PROT_READ | PROT_WRITE, MAP_SHARED, C->shmh, 0);

			if (!C->addr){
				debug_print(FATAL, arg, "segment couldn't be remapped");
				return false;
			}
/* end of shm-handling resize */
			shmif_platform_guard_resynch(C, C->addr->parent, C->epipe);

		shmif_platform_guard_unlock(C);
	}

/*
 * make sure we start from the right buffer counts and positions
 */
	shmif_platform_setevqs(C->addr, NULL, &P->inev, &P->outev);
	setup_avbuf(C);

	P->multipart_ofs = 0;

	if (P->reset_hook){
			P->reset_hook(old_addr != (uintptr_t)C->addr ?
				SHMIF_RESET_REMAP : SHMIF_RESET_NOCHG, P->reset_hook_tag);
	}

	return true;
}

bool arcan_shmif_resize_ext(struct arcan_shmif_cont* arg,
	unsigned width, unsigned height, struct shmif_resize_ext ext)
{
	return shmif_resize(arg, width, height, ext);
}

bool arcan_shmif_resize(struct arcan_shmif_cont* arg,
	unsigned width, unsigned height)
{
	if (!arg || !arg->addr)
		return false;

	return shmif_resize(arg, width, height, (struct shmif_resize_ext){
		.abuf_sz = arg->addr->abufsize,
		.vbuf_cnt = -1,
		.abuf_cnt = -1,
		.samplerate = -1,
	});
}

shmif_trigger_hook_fptr arcan_shmif_signalhook(
	struct arcan_shmif_cont* cont,
	enum arcan_shmif_sigmask mask, shmif_trigger_hook_fptr hook, void* data)
{
	struct shmif_hidden* priv = cont->priv;
	shmif_trigger_hook_fptr rv = NULL;

	if (mask == (SHMIF_SIGVID | SHMIF_SIGAUD))
	;
	else if (mask == SHMIF_SIGVID){
		rv = priv->video_hook;
		priv->video_hook = hook;
		priv->video_hook_data = data;
	}
	else if (mask == SHMIF_SIGAUD){
		rv = priv->audio_hook;
		priv->audio_hook = hook;
		priv->audio_hook_data = data;
	}
	else
		;

	return rv;
}

struct arcan_shmif_cont* arcan_shmif_primary(enum arcan_shmif_type type)
{
	if (type == SHMIF_INPUT)
		return primary.input;
	else if (type == SHMIF_ACCESSIBILITY)
		return primary.accessibility;
	else
		return primary.output;
}

void arcan_shmif_setprimary(
	enum arcan_shmif_type type, struct arcan_shmif_cont* seg)
{
	if (type == SHMIF_INPUT)
		primary.input = seg;
	else if (type == SHMIF_ACCESSIBILITY)
		primary.accessibility = seg;
	else
		primary.output = seg;
}

void arcan_shmif_guid(struct arcan_shmif_cont* cont, uint64_t guid[2])
{
	if (!guid)
		return;

	if (!cont || !cont->priv){
		guid[0] = guid[1] = 0;
		return;
	}

	guid[0] = cont->priv->guid[0];
	guid[1] = cont->priv->guid[1];
}

int arcan_shmif_signalstatus(struct arcan_shmif_cont* c)
{
	if (!c || !c->addr || !c->addr->dms)
		return -1;

	int a = atomic_load(&c->addr->aready);
	int v = atomic_load(&c->addr->vready);
	int res = 0;

	if (atomic_load(&c->addr->aready))
		res |= 2;
	if (atomic_load(&c->addr->vready))
		res |= 1;

	return res;
}

bool arcan_shmif_lock(struct arcan_shmif_cont* C)
{
	if (!C || !C->addr)
		return false;

	struct shmif_hidden* P = C->priv;

/* locking ourselves when we already have the lock is a bad idea,
 * we don't rely on having access to recursive mutexes */
	if (P->in_lock && pthread_equal(P->lock_id, pthread_self())){
		return false;
	}

	if (0 != pthread_mutex_lock(&P->lock))
		return false;

	P->in_lock = true;
	P->lock_id = pthread_self();
	return true;
}

bool arcan_shmif_unlock(struct arcan_shmif_cont* C)
{
	if (!C || !C->addr || !C->priv->in_lock){
		debug_print(FATAL, C, "unlock on unlocked/invalid context");
		return false;
	}

/* don't unlock from any other thread than the locking one */
	if (!pthread_equal(C->priv->lock_id, pthread_self())){
		debug_print(FATAL, C, "mutex theft attempted");
		return false;
	}

	if (0 != pthread_mutex_unlock(&C->priv->lock))
		return false;

	C->priv->in_lock = false;
	return true;
}

int arcan_shmif_dupfd(int fd, int dstnum, bool nonblocking)
{
	return shmif_platform_dupfd_to(fd, dstnum, nonblocking * O_NONBLOCK, FD_CLOEXEC);
}

void arcan_shmif_last_words(
	struct arcan_shmif_cont* cont, const char* msg)
{
	if (!cont || !cont->addr)
		return;

/* keep a local copy around for stderr reporting */
	if (cont->priv->last_words){
		free(cont->priv->last_words);
		cont->priv->last_words = NULL;
	}

/* allow it to be cleared */
	if (!msg){
		cont->addr->last_words[0] = '\0';
		return;
	}
	cont->priv->last_words = strdup(msg);

/* it's volatile so manually write in */
	size_t lim = COUNT_OF(cont->addr->last_words);
	size_t i = 0;
	for (; i < lim-1 && msg[i] != '\0' && msg[i] != '\n'; i++)
		cont->addr->last_words[i] = msg[i];
	cont->addr->last_words[i] = '\0';
}

size_t arcan_shmif_initial(struct arcan_shmif_cont* cont,
	struct arcan_shmif_initial** out)
{
	if (!out || !cont || !cont->priv || !cont->priv->valid_initial)
		return 0;

	*out = &cont->priv->initial;

	return sizeof(struct arcan_shmif_initial);
}

static void apply_ext_options(
	struct arcan_shmif_cont* C,
	struct shmif_open_ext ext, size_t ext_sz
	)
{
/* remember guid used so we resend on crash recovery or migrate */
	struct shmif_hidden* priv = C->priv;
	if (ext.guid[0] || ext.guid[1]){
		priv->guid[0] = ext.guid[0];
		priv->guid[1] = ext.guid[1];
	}
/* or use our own CSPRNG */
	else {
		arcan_random((uint8_t*)priv->guid, 16);
	}

	struct arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(REGISTER),
		.ext.registr = {
			.kind = ext.type,
		}
	};

	if (ext.title)
		snprintf(ev.ext.registr.title,
			COUNT_OF(ev.ext.registr.title), "%s", ext.title);

/* only register if the type is known */
	if (ext.type != SEGID_UNKNOWN){
		arcan_shmif_enqueue(C, &ev);

		if (ext.ident){
			ev.ext.kind = ARCAN_EVENT(IDENT);
				snprintf((char*)ev.ext.message.data,
				COUNT_OF(ev.ext.message.data), "%s", ext.ident);
			arcan_shmif_enqueue(C, &ev);
		}
	}
}

bool arcan_shmif_defer_register(
	struct arcan_shmif_cont* C, struct arcan_event ev)
{
	arcan_shmif_enqueue(C, &ev);
	return shmifint_preroll_loop(C, true);
}

struct arcan_shmif_cont arcan_shmif_open_ext(enum ARCAN_FLAGS flags,
	struct arg_arr** outarg, struct shmif_open_ext ext, size_t ext_sz)
{
/* seed a timestamp for logging */
	if (!g_epoch)
		g_epoch = arcan_timemillis();

	struct arcan_shmif_cont ret = {0};
	struct shmif_connection con = shmif_platform_open_env_connection(flags);
	if (con.error)
		goto fail;

	if (ext_sz > 0)
		con.flags |= SHMIF_NOREGISTER;

	ret = arcan_shmif_acquire(NULL, con.keyfile, ext.type, flags | con.flags);
	if (!ret.priv){
		close(con.socket);
		return ret;
	}

	if (ext_sz > 0)
		apply_ext_options(&ret, ext, ext_sz);

/* unpack the args once for the caller, and one to use for internal lookup */
	if (outarg)
		*outarg = arg_unpack(con.args ? con.args : "");
	ret.priv->args = arg_unpack(con.args ? con.args : "");

	ret.epipe = con.socket;
	if (-1 == ret.epipe){
		debug_print(FATAL, &ret, "couldn't get event pipe from parent");
	}

/* remember the last connection point and use-that on a failure on the current
 * connection point and on a failed force-migrate UNLESS we have a custom
 * alt-specifier OR come from a a12:// like setup */
	if (con.alternate_cp && !con.networked){
		ret.priv->alt_conn = strdup(con.alternate_cp);
	}

	free(con.keyfile);
	if (ext.type>0 && !is_output_segment(ext.type) && !(flags & SHMIF_NOACTIVATE))
		if (!shmifint_preroll_loop(&ret, !(flags & SHMIF_NOACTIVATE_RESIZE))){
			goto fail;
		}

	ret.priv->primary_id = pthread_self();
	return ret;

fail:
	if (flags & SHMIF_ACQUIRE_FATALFAIL){
		log_print(
			"[shmif::open_ext], error connecting (%s)", con.error ? con.error : "");
		exit(EXIT_FAILURE);
	}
	return ret;
}

struct arcan_shmif_cont arcan_shmif_open(
	enum ARCAN_SEGID type, enum ARCAN_FLAGS flags, struct arg_arr** outarg)
{
	return arcan_shmif_open_ext(flags, outarg,
		(struct shmif_open_ext){.type = type}, 0);
}

int arcan_shmif_segkind(struct arcan_shmif_cont* con)
{
	return (!con || !con->priv) ? SEGID_UNKNOWN : con->priv->type;
}

pid_t arcan_shmif_handover_exec_pipe(
	struct arcan_shmif_cont* cont, struct arcan_event ev,
	const char* path, char* const argv[], char* const env[],
	int detach, int* fds[], size_t fdset_sz)
{
	if (!cont || !cont->addr || ev.category != EVENT_TARGET || ev.tgt.kind
		!= TARGET_COMMAND_NEWSEGMENT || ev.tgt.ioevs[2].iv != SEGID_HANDOVER)
		return -1;

/* protect against the caller sending in a bad / misplaced event */
	if (cont->priv->pseg.epipe == BADFD)
		return -1;

/* Dup to drop CLOEXEC and close the original */
	int dup_socket = dup(ev.tgt.ioevs[0].iv);
	int dup_mem    = dup(ev.tgt.ioevs[6].iv);

/* clear the tracking in the same way as an _acquire would */
	cont->priv->pseg.epipe = BADFD;
	cont->priv->pev.handedover = true;

/* reset pending descriptor state */
	shmifint_consume_pending(cont);

	if (-1 == dup_socket)
		return -1;

	pid_t res =
		shmif_platform_execve(
			dup_socket, dup_mem,
			path, argv, env,
			detach, fds, fdset_sz, NULL
		);

	close(dup_socket);
	close(dup_mem);

	return res;
}

pid_t arcan_shmif_handover_exec(
	struct arcan_shmif_cont* cont, struct arcan_event ev,
	const char* path, char* const argv[], char* const env[],
	int detach)
{
	int in = STDIN_FILENO;
	int out = STDOUT_FILENO;
	int err = STDERR_FILENO;

	int* fds[3] = {&in, &out, &err};

	if (detach & 2){
		detach &= ~(int)2;
		fds[0] = NULL;
	}

	if (detach & 4){
		detach &= ~(int)4;
		fds[1] = NULL;
	}

	if (detach & 8){
		detach &= ~(int)8;
		fds[2] = NULL;
	}

	return
		arcan_shmif_handover_exec_pipe(
			cont, ev, path, argv, env, detach, fds, 3);
}

int arcan_shmif_deadline(
	struct arcan_shmif_cont* c, unsigned last_cost, int* jitter, int* errc)
{
	if (!c || !c->addr)
		return -1;

	if (c->addr->vready)
		return -2;

/*
 * no actual deadline information yet, just first part in hooking it up
 * then modify shmif_signal / dirty to use the vpts field to retrieve
 */
	return 0;
}

int arcan_shmif_dirty(struct arcan_shmif_cont* cont,
	size_t x1, size_t y1, size_t x2, size_t y2, int fl)
{
	if (!cont || !cont->addr)
		return -1;

/* precision problem here:
 *
 *  older arm atomic constraints forced the dirty region tracking to uint16_t
 *  which would take an ABI bump to adjust. Since larger regions would expand
 *  past the shmif MAXW/MAXH anyhow, if x2/y2 exceends UINT16_MAX clamp to
 *  that first.
 *
 * On values outside of the range, grow to invalidate the entire segment.
 */
	if (x1 > UINT16_MAX)
		x1 = 0;
	if (x2 > UINT16_MAX)
		x2 = UINT16_MAX;
	if (y1 > UINT16_MAX)
		y1 = 0;
	if (y2 > UINT16_MAX)
		y2 = UINT16_MAX;

	if (x1 > x2){
		size_t tmp = x1;
		x1 = x2;
		x2 = tmp;
	}
	if (y1 > y2){
		size_t tmp = y1;
		y1 = y2;
		y2 = tmp;
	}

/* Resize to synch flags shouldn't cause a remap here, but some edge case could
 * possible have client-aliased context where the flag would not hit - but that
 * is on them. */
	if (!(cont->hints & SHMIF_RHINT_SUBREGION)){
		cont->hints |= SHMIF_RHINT_SUBREGION;
		arcan_shmif_resize(cont, cont->w, cont->h);
	}

/* grow to extents */
	if (x1 < cont->dirty.x1)
		cont->dirty.x1 = x1;

	if (x2 > cont->dirty.x2)
		cont->dirty.x2 = x2;

	if (y1 < cont->dirty.y1)
		cont->dirty.y1 = y1;

	if (y2 > cont->dirty.y2)
		cont->dirty.y2 = y2;

/* clamp */
	if (cont->dirty.y2 > cont->h){
		cont->dirty.y2 = cont->h;
	}

	if (cont->dirty.x2 > cont->w){
		cont->dirty.x2 = cont->w;
	}

#ifdef _DEBUG
	if (getenv("ARCAN_SHMIF_DEBUG_NODIRTY")){
		cont->dirty.x1 = 0;
		cont->dirty.x2 = cont->w;
		cont->dirty.y1 = 0;
		cont->dirty.y2 = cont->h;
	}
	else if (getenv("ARCAN_SHMIF_DEBUG_DIRTY")){
		shmif_pixel* buf = malloc(sizeof(shmif_pixel) *
			(cont->dirty.y2 - cont->dirty.y1) * (cont->dirty.x2 - cont->dirty.x1));

/* save and replace with green, then restore and synch real */
		if (buf){
			size_t count = 0;
			struct arcan_shmif_region od = cont->dirty;
			for (size_t y = cont->dirty.y1; y < cont->dirty.y2; y++)
				for (size_t x = cont->dirty.x1; x < cont->dirty.x2; x++){
				buf[count++] = cont->vidp[y * cont->pitch + x];
				cont->vidp[y * cont->pitch + x] = SHMIF_RGBA(0x00, 0xff, 0x00, 0xff);
			}

			arcan_shmif_signal(cont, SHMIF_SIGVID);

			count = 0;
			cont->dirty = od;
			for (size_t y = cont->dirty.y1; y < cont->dirty.y2; y++)
				for (size_t x = cont->dirty.x1; x < cont->dirty.x2; x++){
				cont->vidp[y * cont->pitch + x] = buf[count++];
			}

			free(buf);
		}
	}
#endif

	return 0;
}

shmif_reset_hook_fptr arcan_shmif_resetfunc(
	struct arcan_shmif_cont* C, shmif_reset_hook_fptr hook, void* tag)
{
	if (!C)
		return NULL;

	struct shmif_hidden* hs = C->priv;
	shmif_reset_hook_fptr old_hook = hs->reset_hook;

	hs->reset_hook = hook;
	hs->reset_hook_tag = tag;

	return old_hook;
}
