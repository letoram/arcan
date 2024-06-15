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
#include <sys/utsname.h>

#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <pthread.h>

#include "arcan_shmif.h"
#include "shmif_privext.h"
#include "shmif_privint.h"

#include "shmif_defimpl.h"
#include "platform/shmif_platform.h"

#include <signal.h>
#include <poll.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>

#ifdef __LINUX
#include <sys/inotify.h>
#endif

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

/*
 * a bit clunky, but some scenarios that we want debug-builds but without the
 * debug logging spam for external projects, and others where we want to
 * redefine the logging macro for shmif- only.
 */
enum debug_level {
	FATAL = 0,
 	INFO = 1,
	DETAILED = 2
};

_Static_assert(sizeof(struct mstate) == ASHMIF_MSTATE_SZ, "invalid mstate sz");

/*
 * Accessor for redirectable log output related to a shmif context
 * The context association is a placeholder for being able to handle
 * context- specific log output devices later.
 */
static _Atomic volatile uintptr_t log_device;
FILE* shmifint_log_device(struct arcan_shmif_cont* c)
{
	FILE* res = (FILE*)(void*) atomic_load(&log_device);
	if (res)
		return res;

	return stderr;
}

void shmifint_set_log_device(struct arcan_shmif_cont* c, FILE* outdev)
{
	atomic_store(&log_device, (uintptr_t)(void*)outdev);
}

#ifdef _DEBUG
#ifdef _DEBUG_NOLOG
#define debug_print(...)
#endif

#ifndef debug_print
#define debug_print(sev, ctx, fmt, ...) \
            do { fprintf(shmifint_log_device(NULL),\
						"[%lld]%s:%d:%s(): " fmt "\n", \
						arcan_timemillis(), "shmif-dbg", __LINE__, __func__,##__VA_ARGS__); } while (0)
#endif
#else
#ifndef debug_print
#define debug_print(...)
#endif
#endif

#define log_print(fmt, ...) \
            do { fprintf(shmifint_log_device(NULL),\
						"[%lld]%d:%s(): " fmt "\n", \
						arcan_timemillis(), __LINE__, __func__,##__VA_ARGS__); } while (0)

/*
 * implementation defined for out-of-order execution and reordering protection
 * when we+the compilers are full c11 thread+atomics, this can be dropped
 */
#ifndef FORCE_SYNCH
	#define FORCE_SYNCH() {\
		__asm volatile("": : :"memory");\
		__sync_synchronize();\
	}
#endif

/*
 * To avoid having -lm or similar requirements on terrible libc implementations
 */
static int ilog2(int val)
{
	int i = 0;
	while( val >>= 1)
		i++;
	return i;
}

static uint64_t g_epoch;

void arcan_random(uint8_t*, size_t);
static char* spawn_arcan_net(
	struct shmif_hidden* priv, const char* conn_src, int* dsock);
static ssize_t a12_cp(const char* conn_src, bool* weak);

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

static void* guard_thread(void* gstruct);

static inline bool parent_alive(struct shmif_hidden* gs)
{
	/* for authoritative connections, a parent monitoring pid is set. */
	if (gs->guard.parent > 0){
		if (-1 == kill(gs->guard.parent, 0))
			return false;
	}

/* peek the socket (if it exists) and see if we get an error back */
	if (-1 != gs->guard.parent_fd){
		unsigned char ch;

		if (-1 == recv(gs->guard.parent_fd, &ch, 1, MSG_PEEK | MSG_DONTWAIT)
			&& (errno != EWOULDBLOCK && errno != EAGAIN))
			return false;
	}

	return true;
}

/*
 * consolidate 3 signal paths for detecting connection liveness
 * shared page   - triggered on memory page inconsistency / integrity fail
 * guard thread  - triggered on parent death
 * event context - triggered on queue structure integrity, normally hooked to dms
 */
static bool check_dms(struct arcan_shmif_cont* c)
{
	if (!c->priv->alive ||
		!atomic_load(&c->priv->guard.local_dms) || !c->addr->dms)
		return false;

	return true;
}

static void spawn_guardthread(struct arcan_shmif_cont* d)
{
	struct shmif_hidden* hgs = d->priv;

	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	pthread_mutex_init(&hgs->guard.synch, NULL);

	hgs->guard.active = true;
	if (-1 == pthread_create(&pth, &pthattr, guard_thread, hgs)){
		hgs->guard.active = false;
	}
}

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

static bool fd_event(struct arcan_shmif_cont* c, struct arcan_event* dst)
{
/*
 * if we get a descriptor event that is connected to acquiring a new
 * frameserver subsegment- set up special tracking so we can retain the
 * descriptor as new signalling/socket transfer descriptor
 */
	c->priv->pev.consumed = true;
	if (dst->category == EVENT_TARGET &&
		dst->tgt.kind == TARGET_COMMAND_NEWSEGMENT){
/*
 * forward the file descriptor as well so that, in the case of a HANDOVER,
 * the parent process has enough information to forward into a new process.
 */
		dst->tgt.ioevs[0].iv = c->priv->pseg.epipe = c->priv->pev.fd;
		c->priv->pev.fd = BADFD;
		memcpy(c->priv->pseg.key, dst->tgt.message, sizeof(dst->tgt.message));
		return true;
	}
/*
 * this event can swap out store access handle for sensitive material like
 * authentication and signing keys. Make sure it doesn't get forwarded.
 */
	else if (dst->category == EVENT_TARGET &&
		dst->tgt.kind == TARGET_COMMAND_DEVICE_NODE &&
		dst->tgt.ioevs[3].iv == 3){
		if (c->priv->keystate_store)
			close(c->priv->keystate_store);

		c->priv->keystate_store = c->priv->pev.fd;
		c->priv->autoclean = true;
		c->priv->pev.fd = BADFD;
		return true;
	}
/*
 * otherwise we have a normal pending slot with a descriptor that
 * is inserted into the event, then set as consumed (so next call,
 * unless the descriptor is dup:ed or used, it will close
 */
	else
		dst->tgt.ioevs[0].iv = c->priv->pev.fd;

	return false;
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

/*
 * reset pending- state tracking
 */
static void consume(struct arcan_shmif_cont* c)
{
	if (!c->priv->pev.consumed)
		return;

	debug_print(
		DETAILED, c, "acquire: %s",
		arcan_shmif_eventstr(&c->priv->pev.ev, NULL, 0)
	);

	if (BADFD != c->priv->pev.fd){
		close(c->priv->pev.fd);
		if (c->priv->pev.handedover){
			debug_print(DETAILED, c,
				"closing descriptor (%d:handover)", c->priv->pev.fd);
		}
		else
			debug_print(DETAILED, c,
				"closing descriptor (%d)", c->priv->pev.fd);
	}

	if (BADFD != c->priv->pseg.epipe){
/*
 * Special case, the parent explicitly pushed a debug segment that was not
 * mapped / accepted by the client. Then we take it upon ourselves to add
 * another debugging interface that redirects STDERR to TUI, eventually also
 * setting up support for attaching gdb or lldb, or providing sense_mem style
 * sampling
 */
#ifdef SHMIF_DEBUG_IF
		if (c->priv->pev.gotev &&
			c->priv->pev.ev.category == EVENT_TARGET &&
			c->priv->pev.ev.tgt.kind == TARGET_COMMAND_NEWSEGMENT &&
			c->priv->pev.ev.tgt.ioevs[2].iv == SEGID_DEBUG){
			debug_print(DETAILED, c, "debug subsegment received");

/* want to let the debugif do initial registration */
			struct arcan_shmif_cont pcont =
				arcan_shmif_acquire(c, NULL, SEGID_DEBUG, SHMIF_NOREGISTER);

			if (pcont.addr){
				if (!arcan_shmif_debugint_spawn(&pcont, NULL, NULL))
					arcan_shmif_drop(&pcont);
				return;
			}
		}
#endif
		if (c->priv->pev.gotev &&
			c->priv->pev.ev.category == EVENT_TARGET &&
			c->priv->pev.ev.tgt.kind == TARGET_COMMAND_NEWSEGMENT &&
			c->priv->pev.ev.tgt.ioevs[2].iv == SEGID_ACCESSIBILITY){
			struct arcan_shmif_cont pcont =
				arcan_shmif_acquire(c, NULL, SEGID_ACCESSIBILITY, 0);
			if (pcont.addr){
				if (!arcan_shmif_a11yint_spawn(&pcont, c))
					arcan_shmif_drop(&pcont);
				return;
			}
		}

		close(c->priv->pseg.epipe);
		c->priv->pseg.epipe = BADFD;
		debug_print(DETAILED, c, "closing unhandled subsegment descriptor");
	}

	c->priv->pev.fd = BADFD;
	c->priv->pev.gotev = false;
	c->priv->pev.consumed = false;
	c->priv->pev.handedover = false;
}

/*
 * Rules for compacting DISPLAYHINT events
 *  1. If dimensions have changed [!0], use new values
 *  2. Always use new hint state
 *  3. If density has changed [> 0], use new value
 *  4. If cell dimensions has changed, use new values
 *  5. Use timestamp component of new event, if it is not there
 *     force it to the process local one
*/
static inline bool merge_dh(arcan_event* new, arcan_event* old)
{
	if (new->tgt.ioevs[7].uiv != old->tgt.ioevs[7].uiv)
		return false;

	if (!new->tgt.ioevs[0].iv)
		new->tgt.ioevs[0].iv = old->tgt.ioevs[0].iv;

	if (!new->tgt.ioevs[1].iv)
		new->tgt.ioevs[1].iv = old->tgt.ioevs[1].iv;

/*
	if ((new->tgt.ioevs[2].iv & 128))
		new->tgt.ioevs[2].iv = old->tgt.ioevs[2].iv;
 */

	if (new->tgt.ioevs[3].iv < 0)
		new->tgt.ioevs[3].iv = old->tgt.ioevs[3].iv;

	if (!(new->tgt.ioevs[4].fv > 0))
		new->tgt.ioevs[4].fv = old->tgt.ioevs[4].fv;

	if (!new->tgt.ioevs[5].iv)
		new->tgt.ioevs[5].iv = old->tgt.ioevs[5].iv;

	if (!new->tgt.ioevs[6].iv)
		new->tgt.ioevs[6].iv = old->tgt.ioevs[6].iv;

	if (!new->tgt.timestamp){
		new->tgt.timestamp = arcan_timemillis();
	}

	return true;
}

static bool calc_dirty(
	struct arcan_shmif_cont* ctx, shmif_pixel* old, shmif_pixel* new)
{
	shmif_pixel diff = SHMIF_RGBA(0, 0, 0, 255);
	shmif_pixel ref = SHMIF_RGBA(0, 0, 0, 255);

/* find dirty y1, if this does not find anything, short-out */
	size_t cy = 0;
	for (; cy < ctx->h && diff == ref; cy++){
		for (size_t x = 0; x < ctx->w && diff == ref; x++)
			diff |= old[ctx->pitch * cy + x] ^ new[ctx->pitch * cy + x];
	}

	if (diff == ref)
		return false;

	ctx->dirty.y1 = cy - 1;

/* find dirty y2, since y1 is dirty there must be one */
	diff = ref;
	for (cy = ctx->h - 1; cy && diff == ref; cy--){
		for (size_t x = 0; x < ctx->w && diff == ref; x++)
			diff |= old[ctx->pitch * cy + x] ^ new[ctx->pitch * cy + x];
	}

/* dirty region starts at y1 and ends < y2 */
	ctx->dirty.y2 = cy + 1;

/* now do x in the same way, the order matters as the search space is hopefully
 * reduced with y, and the data access patterns are much more predictor
 * friendly */

	size_t cx;
	diff = ref;
	for (cx = 0; cx < ctx->w && diff == ref; cx++){
		for (cy = ctx->dirty.y1; cy < ctx->dirty.y2 && diff == ref; cy++)
			diff |= old[ctx->pitch * cy + cx] ^ new[ctx->pitch * cy + cx];
	}
	ctx->dirty.x1 = cx - 1;

	diff = ref;
	for (cx = ctx->w - 1; cx > 0 && diff == ref; cx--){
		for (cy = ctx->dirty.y1; cy < ctx->dirty.y2 && diff == ref; cy++)
			diff |= old[ctx->pitch * cy + cx] ^ new[ctx->pitch * cy + cx];
	}

	ctx->dirty.x2 = cx + 1;

	return true;
}

static bool scan_stepframe_event(
	struct arcan_evctx*c, struct arcan_event* old, int id)
{
	if (old->tgt.ioevs[1].iv != id)
		return false;
	uint8_t cur = *c->front;

/* conservative merge on STEPFRAME so far is results from VBLANK polling only */
	while (cur != *c->back){
		struct arcan_event* ev = &c->eventbuf[cur];
		if (ev->category == EVENT_TARGET &&
			ev->tgt.kind == TARGET_COMMAND_STEPFRAME &&
			ev->tgt.ioevs[1].iv == id)
				return true;
		cur = (cur + 1) % c->eventbuf_sz;
	}
	return false;
}

static bool scan_disp_event(struct arcan_evctx* c, struct arcan_event* old)
{
	uint8_t cur = *c->front;

	while (cur != *c->back){
		struct arcan_event* ev = &c->eventbuf[cur];
		if (ev->category == EVENT_TARGET &&
			ev->tgt.kind == old->tgt.kind && merge_dh(ev, old)){
			return true;
		}
		cur = (cur + 1) % c->eventbuf_sz;
	}

	return false;
}

/*
 * shorter handling cycle for automated paused state with partial buffering,
 * true if the event was consumed, false if it should be forwarded.
 */
static bool pause_evh(struct arcan_shmif_cont* c,
	struct shmif_hidden* priv, arcan_event* ev)
{
	if (ev->category != EVENT_TARGET)
		return true;

	bool rv = true;
	if (ev->tgt.kind == TARGET_COMMAND_UNPAUSE ||
		ev->tgt.kind == TARGET_COMMAND_RESET)
		priv->paused = false;
	else if (ev->tgt.kind == TARGET_COMMAND_EXIT){
		priv->alive = false;
		rv = false;
	}
	else if (ev->tgt.kind == TARGET_COMMAND_DISPLAYHINT){
		merge_dh(ev, &priv->dh);
		priv->dh = *ev;
		priv->ph |= 1;
	}

/*
 * theoretical race here is not possible with kms/ks being pulled resulting
 * in either end of epipe being closed and broken socket
 */
	else if (ev->tgt.kind == TARGET_COMMAND_FONTHINT){
		priv->fh.category = EVENT_TARGET;
		priv->fh.tgt.kind = TARGET_COMMAND_FONTHINT;

/* received event while one already pending? don't leak descriptor */
		if (ev->tgt.ioevs[1].iv != 0){
			if (priv->fh.tgt.ioevs[0].iv != BADFD)
				close(priv->fh.tgt.ioevs[0].iv);
			priv->fh.tgt.ioevs[0].iv = arcan_fetchhandle(c->epipe, true);
		}

		if (ev->tgt.ioevs[2].fv > 0.0)
			priv->fh.tgt.ioevs[2].fv = ev->tgt.ioevs[2].fv;
		if (ev->tgt.ioevs[3].iv > -1)
			priv->fh.tgt.ioevs[3].iv = ev->tgt.ioevs[3].iv;

/* set the bit to indicate we need to return this event */
		priv->ph |= 2;
	}
	return rv;
}

#ifdef __LINUX
static bool notify_wait(const char* cpoint)
{
/* if we get here we really shouldnt be at the stage of a broken connpath,
 * and if we are the connect loop won't do much of anything */
	char buf[256];
	int len = arcan_shmif_resolve_connpath(cpoint, buf, 256);
	if (len <= 0)
		return false;

/* path in abstract namespace or non-absolute */
	if (buf[0] != '/')
		return false;

/* strip down to the path itself */
	size_t pos = strlen(buf);
	while(pos > 0 && buf[pos] != '/')
		pos--;

	if (!pos)
		return false;

	buf[pos] = '\0';

	int notify = inotify_init1(IN_CLOEXEC);
	if (-1 == notify)
		return false;

/* watch the path for changes */
	if (-1 == inotify_add_watch(notify, buf, IN_CREATE)){
		close(notify);
		return false;
	}

/* just wait for something, the path shouldn't be particularly active */
	struct inotify_event ev;
	read(notify, &ev, sizeof(ev));

	close(notify);
	return true;
}
#endif

static enum shmif_migrate_status fallback_migrate(
	struct arcan_shmif_cont* c, const char* cpoint, bool force)
{
/* sleep - retry connect loop */
	enum shmif_migrate_status sv;
	int oldfd = c->epipe;

/* parent can pull dms explicitly */
	if (force){
		if ((c->priv->flags & SHMIF_NOAUTO_RECONNECT)
			||	parent_alive(c->priv) || c->priv->output)
			return SHMIF_MIGRATE_NOCON;
	}

/* CONNECT_LOOP style behavior on force */
	const char* current = cpoint;

	while ((sv = arcan_shmif_migrate(c, current, NULL)) == SHMIF_MIGRATE_NOCON){
		if (!force)
			break;

/* try to return to the last known connection point after a few tries */
		else if (current == cpoint && c->priv->alt_conn)
			current = c->priv->alt_conn;
		else
			current = cpoint;

/* if there is a poll mechanism to use, go for it, otherwise fallback to a
 * timesleep - special cases include a12://, non-linux, ... */
#ifdef __LINUX
		if (!(strlen(cpoint) > 6 &&
			strncmp(cpoint, "a12://", 6) == 0) && notify_wait(cpoint))
				continue;
		else
#endif
		arcan_timesleep(100);
	}

	switch (sv){
/* dealt with above already */
	case SHMIF_MIGRATE_NOCON:
	break;
	case SHMIF_MIGRATE_BAD_SOURCE:
/* this means that multiple threads tried to migrate at the same time,
 * and we come from one that isn't the primary one */
		return sv;
	break;
	case SHMIF_MIGRATE_BADARG:
		debug_print(FATAL, c, "recovery failed, broken path / key");
	break;
	case SHMIF_MIGRATE_TRANSFER_FAIL:
		debug_print(FATAL, c, "migration failed on setup");
	break;

/* set a reset event in the "to be dispatched next dequeue" slot, it would be
 * nice to have a sneakier way of injecting events into the normal dequeue
 * process to use as both inter-thread and MiM */
	case SHMIF_MIGRATE_OK:
		c->priv->ph |= 4;
		c->priv->fh = (struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_RESET,
			.tgt.ioevs[0].iv = 3,
			.tgt.ioevs[1].iv = oldfd
		};
	break;
	}

	return sv;
}

/* this one is really terrible and unfortunately very central
 * subject to a long refactoring of its own, points to keep in check:
 *  - blocking or nonblocking (coming from wait or poll)
 *  - paused state (only accept UNPAUSE)
 *  - crashed or connection terminated
 *  - pairing fd and event for descriptor events
 *  - cleanup of pending resources not consumed by client
 *  - merging event storms (pending hint, ph)
 *  - key state transitions:
 *    - switch devices
 *    - migration
 */
static int process_events(struct arcan_shmif_cont* c,
	struct arcan_event* dst, bool blocking, bool upret)
{
reset:
	if (!dst || !c->addr)
		return -1;

	struct shmif_hidden* priv = c->priv;
	struct arcan_evctx* ctx = &priv->inev;
	bool noks = false;
	int rv = 0;

	if (priv->support_window_hook){
		priv->support_window_hook(c, SUPPORT_EVENT_POLL);
	}

/* Select few events has a special queue position and can be delivered 'out of
 * order' from normal affairs. This is needed for displayhint/fonthint in WM
 * cases where a connection may be suspended for a long time and normal system
 * state (move window between displays, change global fonts) may be silently
 * ignored, when we actually want them delivered immediately upon UNPAUSE */

	if (!priv->paused && priv->ph){
		if (priv->ph & 1){
			priv->ph &= ~1;
			*dst = priv->dh;
			rv = 1;
			goto done;
		}
		else if (priv->ph & 2){
			*dst = priv->fh;
			c->priv->pev.consumed = dst->tgt.ioevs[0].iv != BADFD;
			c->priv->pev.fd = dst->tgt.ioevs[0].iv;
			priv->ph &= ~2;
			rv = 1;
			goto done;
		}
		else{
			priv->ph = 0;
			rv = 1;
			*dst = priv->fh;
			goto done;
		}
	}

/* clean up any pending descriptors, as the client has a short frame to
 * directly use them or at the very least dup() to safety */
	consume(c);

/*
 * fetchhandle also pumps 'got event' pings that we send in order to portably
 * I/O multiplex in the eventqueue, see arcan/ source for frameserver_pushevent
 */
checkfd:
	do {
		errno = 0;
		if (-1 == priv->pev.fd){
			priv->pev.fd = arcan_fetchhandle(c->epipe, blocking);
		}

		if (priv->pev.gotev){
			if (blocking){
				debug_print(DETAILED, c, "waiting for parent descriptor");
			}

			if (priv->pev.fd != BADFD){
				if (fd_event(c, dst) && priv->autoclean){
					priv->autoclean = false;
					consume(c);
				}
				else
					rv = 1;
			}
			else if (blocking){
				debug_print(INFO, c, "failure on blocking fd-wait: %s, %s",
					strerror(errno), arcan_shmif_eventstr(&priv->pev.ev, NULL, 0));
				if (!errno || errno == EAGAIN)
					continue;
			}

			goto done;
		}
	} while (priv->pev.gotev && check_dms(c));

/* atomic increment of front -> event enqueued, other option in this sense
 * would be to have a poll that provides the pointer, and a step that unlocks */
	if (*ctx->front != *ctx->back){
		*dst = ctx->eventbuf[ *ctx->front ];

/*
 * memset to 0xff for easier visibility on debugging)
 */
		memset(&ctx->eventbuf[ *ctx->front ], 0xff, sizeof (struct arcan_event));
		*ctx->front = (*ctx->front + 1) % ctx->eventbuf_sz;

/* Unless mask is set, paused won't be changed so that is ok. This has the
 * effect of silently discarding events if the server acts in a weird way
 * (pause -> do things -> unpause) but that is the expected behavior, with
 * the exception of DISPLAYHINT, FONTHINT and EXIT */
		if (priv->paused){
			if (pause_evh(c, priv, dst))
				goto reset;
			rv = 1;
			noks = dst->category == EVENT_TARGET
				&& dst->tgt.kind == TARGET_COMMAND_EXIT;
			goto done;
		}

		if (dst->category == EVENT_TARGET)
			switch (dst->tgt.kind){

/* Ignore displayhints if there are newer ones in the queue. This pattern can
 * be re-used for other events, should it be necessary, the principle is that
 * if there is a serious cost involved for a state change that will be
 * overridden with something in the queue, use this mechanism. Cannot be applied
 * to descriptor- carrying events as more state tracking is needed. */
			case TARGET_COMMAND_DISPLAYHINT:
				if (!priv->valid_initial && scan_disp_event(ctx, dst))
					goto reset;
			break;

			case TARGET_COMMAND_STEPFRAME:
				if (scan_stepframe_event(ctx, dst, 2) || scan_stepframe_event(ctx, dst, 3))
					goto reset;
			break;

/* automatic pause switches to pause_ev, which only supports subset */
			case TARGET_COMMAND_PAUSE:
				if ((priv->flags & SHMIF_MANUAL_PAUSE) == 0){
				priv->paused = true;
				goto reset;
			}
			break;

			case TARGET_COMMAND_UNPAUSE:
				if ((priv->flags & SHMIF_MANUAL_PAUSE) == 0){
/* used when enqueue:ing while we are asleep */
					if (upret)
						return 0;
					priv->paused = false;
					goto reset;
				}
				break;

			case TARGET_COMMAND_BUFFER_FAIL:
/* we can't call bufferfail immediately from here as that would pull in a
 * dependency to shmifext which in turn pulls in GL libraries and so on. */
				debug_print(INFO, c, "buffer-fail, accelerated handle passing rejected");
				c->privext->state_fl = STATE_NOACCEL;
				goto reset;
			break;

			case TARGET_COMMAND_EXIT:
/* While tempting to run _drop here to prevent caller from leaking resources,
 * we can't as the event- loop might be running in a different thread than A/V
 * updating. _drop would modify the context in ways that would break, and we
 * want consistent behavior between threadsafe- and non-threadsafe builds. */
				priv->alive = false;
				noks = true;
			break;

/* fonthint is different in the sense that the descriptor is not always
 * mandatory, it is conditional on one of the ioevs (as there might not be an
 * interest to override default font */
			case TARGET_COMMAND_FONTHINT:
				if (dst->tgt.ioevs[1].iv == 1){
					priv->pev.ev = *dst;
					priv->pev.gotev = true;
					goto checkfd;
				}
				else
					dst->tgt.ioevs[0].iv = BADFD;
			break;

/* similar to fonthint but uses different descriptor- indicator field, more
 * complex rules for if we should forward or handle ourselves. If it's about
 * switching or defining render node for handle passing, then we need to
 * forward as the client need to rebuild its context. */
			case TARGET_COMMAND_DEVICE_NODE:{
				if (priv->log_event){
					log_print("(@%"PRIxPTR"<-)%s",
						(uintptr_t) c, arcan_shmif_eventstr(dst, NULL, 0));
				}

				int iev = dst->tgt.ioevs[1].iv;
				if (iev == 4){
/* replace slot with message, never forward, if message is not set - drop */
					if (priv->alt_conn){
						free(priv->alt_conn);
						priv->alt_conn = NULL;
					}

/* if we're provided with a guid, keep it to be used on a possible migrate */
					uint64_t guid[2] = {
						((uint64_t)dst->tgt.ioevs[2].uiv)|
						((uint64_t)dst->tgt.ioevs[3].uiv << 32),
						((uint64_t)dst->tgt.ioevs[4].uiv)|
						((uint64_t)dst->tgt.ioevs[5].uiv << 32)
					};

					if ( (guid[0] || guid[1]) &&
						(priv->guid[0] != guid[0] && priv->guid[1] != guid[1] )){
						priv->guid[0] = guid[0];
						priv->guid[1] = guid[1];
					}

					if (dst->tgt.message[0])
						priv->alt_conn = strdup(dst->tgt.message);

/* for a state store we also need to fetch the descriptor, and this should
 * ideally already be pending because for the 'force' mode the DMS will be
 * pulled and semaphores unlocked. */
					goto reset;
				}
				else if (iev == 1){
/* other ones are ignored for now, require cooperation with shmifext */
					if (dst->tgt.ioevs[3].iv == 3){
						priv->pev.ev = *dst;
						priv->pev.gotev = true;
						goto checkfd;
					}
				}
/* event that request us to switch connection point */
				else if (iev > 1 && iev <= 3){
					if (dst->tgt.message[0] == '\0'){
						priv->pev.ev = *dst;
						priv->pev.gotev = true;
						goto checkfd;
					}
/* try to migrate automatically, but ignore on failure */
					else {
						if (fallback_migrate(c,dst->tgt.message, false)!=SHMIF_MIGRATE_OK){
							rv = 0;
							goto done;
						}
						else
							goto reset;
					}
				}
				else
					goto reset;
			}
			break;

/* Events that require a handle to be tracked (and possibly garbage collected
 * if the caller does not handle it) should be added here. Then the event will
 * be deferred until we have received a handle and the specific handle will be
 * added to the actual event. */
			case TARGET_COMMAND_NEWSEGMENT:
				priv->autoclean = !!(dst->tgt.ioevs[5].iv);

/* fallthrough behavior is expected */
			case TARGET_COMMAND_STORE:
			case TARGET_COMMAND_RESTORE:
			case TARGET_COMMAND_BCHUNK_IN:
			case TARGET_COMMAND_BCHUNK_OUT:
				debug_print(DETAILED, c,
					"got descriptor event (%s)", arcan_shmif_eventstr(dst, NULL, 0));
				priv->pev.gotev = true;
				priv->pev.ev = *dst;
				goto checkfd;
			default:
			break;
			}

		rv = 1;
	}
	else if (!check_dms(c)){
		rv = fallback_migrate(c, priv->alt_conn, true) == SHMIF_MIGRATE_OK?0:-1;
		goto done;
	}

/* Need to constantly pump the event socket for incoming descriptors and
 * caller- mandated polling, as the order between event and descriptor is
 * not deterministic */
	else if (blocking && check_dms(c))
		goto checkfd;

done:
	return check_dms(c) || noks ? rv : -1;
}

bool arcan_shmif_handle_permitted(struct arcan_shmif_cont* ctx)
{
	return (ctx && ctx->privext && ctx->privext->state_fl != STATE_NOACCEL);
}

static bool is_output_segment(enum ARCAN_SEGID segid)
{
	return (segid == SEGID_ENCODER || segid == SEGID_CLIPBOARD_PASTE);
}

static void drop_initial(struct arcan_shmif_cont* c)
{
	if (!(c && c->priv && c->priv->valid_initial))
		return;
	struct arcan_shmif_initial* init = &c->priv->initial;

	if (-1 != init->render_node){
		close(init->render_node);
		init->render_node = -1;
	}

	for (size_t i = 0; i < COUNT_OF(init->fonts); i++)
		if (-1 != init->fonts[i].fd){
			close(init->fonts[i].fd);
			init->fonts[i].fd = -1;
		}

	c->priv->valid_initial = false;
}

int arcan_shmif_poll(struct arcan_shmif_cont* c, struct arcan_event* dst)
{
	if (!c || !c->priv || !c->priv->alive)
		return -1;

	if (c->priv->valid_initial)
		drop_initial(c);

	int rv = process_events(c, dst, false, false);

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
		drop_initial(c);

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
		drop_initial(c);

	int rv = process_events(c, dst, true, false);
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

/* this is dangerous territory: many _enqueue calls are done without checking
 * the return value, so chances are that some event will be dropped. In the
 * crash- recovery case this means that if the migration goes through, we have
 * either an event that might not fit in the current context, or an event that
 * gets lost. Neither is good. The counterargument is that crash recovery is a
 * 'best effort basis' - we're still dealing with an actual crash. */
	if (!check_dms(c) && !try){
		fallback_migrate(c, c->priv->alt_conn, true);
		return 0;
	}

/* need some extra patching up for log-event to contain the proper values */
	if (c->priv->log_event){
		struct arcan_event outev = *src;
		if (!outev.category){
			outev.category = EVENT_EXTERNAL;
		}
		if (outev.category == EVENT_EXTERNAL)
			outev.ext.frame_id = c->priv->vframe_id;

		log_print("(@%"PRIxPTR"->)%s",
			(uintptr_t) c, arcan_shmif_eventstr(&outev, NULL, 0));
	}

	struct arcan_evctx* ctx = &c->priv->outev;

/* paused only set if segment is configured to handle it,
 * and process_events on blocking will block until unpaused */
	if (c->priv->paused){
		struct arcan_event ev;
		process_events(c, &ev, true, true);
	}

	while ( check_dms(c) &&
			((*ctx->back + 1) % ctx->eventbuf_sz) == *ctx->front){
		struct arcan_event outev = *src;
		debug_print(INFO, c,
			"=> %s: outqueue is full, waiting", arcan_shmif_eventstr(&outev, NULL, 0));
		arcan_sem_wait(ctx->synch.handle);
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
		ctx->eventbuf[*ctx->back].ext.frame_id = c->priv->vframe_id;

		if (src->ext.kind == ARCAN_EVENT(REGISTER)){

			if (src->ext.registr.guid[0] || src->ext.registr.guid[1]){
				c->priv->guid[0] = src->ext.registr.guid[0];
				c->priv->guid[1] = src->ext.registr.guid[1];
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
			if (src->ext.registr.kind && c->priv->type == SEGID_UNKNOWN)
				c->priv->type = src->ext.registr.kind;
		}
	}

	FORCE_SYNCH();
	*ctx->back = (*ctx->back + 1) % ctx->eventbuf_sz;

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

static void unlink_keyed(const char* key)
{
	shm_unlink(key);
	size_t slen = strlen(key) + 1;
	char work[slen];
	snprintf(work, slen, "%s", key);
	slen -= 2;
	work[slen] = 'v';
	sem_unlink(work);

	work[slen] = 'a';
	sem_unlink(work);

	work[slen] = 'e';
	sem_unlink(work);

}

void arcan_shmif_unlink(struct arcan_shmif_cont* dst)
{
	if (!dst->priv->shm_key)
		return;

	debug_print(INFO, dst, "release_shm_key:%s", dst->priv->shm_key);
	unlink_keyed(dst->priv->shm_key);
	dst->priv->shm_key = NULL;
}

const char* arcan_shmif_segment_key(struct arcan_shmif_cont* dst)
{
	if (!dst || !dst->priv)
		return NULL;

	return dst->priv->shm_key;
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

static void map_shared(const char* shmkey, struct arcan_shmif_cont* dst)
{
	assert(shmkey);
	assert(strlen(shmkey) > 0);

	int fd = -1;
	fd = shm_open(shmkey, O_RDWR, 0700);

/* This has happened, and while 'technically' legal - it can (and will in most
 * cases) lead to nasty bugs. Since we need to keep the descriptor around in
 * order to resize/remap, chances are that some part of normal processing will
 * printf to stdout, stderr - potentially causing a write into the shared
 * memory page. The server side will likely detect this due to the validation
 * cookie failing, causing it to terminate the connection. */
	if (fd <= STDERR_FILENO){
		close(fd);
		if (!ensure_stdio())
			return;
		fd = shm_open(shmkey, O_RDWR, 0700);
	}

	if (-1 == fd){
		debug_print(FATAL,
			dst, "couldn't open keyfile (%s): %s", shmkey, strerror(errno));
		return;
	}

	dst->addr = mmap(NULL, ARCAN_SHMPAGE_START_SZ,
		PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	dst->shmh = fd;

/* step 2, semaphore handles */
	size_t slen = strlen(shmkey) + 1;
	if (slen > 1){
		char work[slen];
		snprintf(work, slen, "%s", shmkey);
		slen -= 2;
		work[slen] = 'v';
		dst->vsem = sem_open(work, 0);
		work[slen] = 'a';
		dst->asem = sem_open(work, 0);
		work[slen] = 'e';
		dst->esem = sem_open(work, 0);
	}

	if (dst->asem == 0x0 || dst->esem == 0x0 || dst->vsem == 0x0){
		debug_print(FATAL, dst, "couldn't map semaphores: %s", shmkey);
		free(dst->addr);
		close(fd);
		dst->addr = NULL;
		return;
	}

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
		debug_print(FATAL, dst, "couldn't map keyfile"
			"	(%s), reason: %s", shmkey, strerror(errno));
		close(fd);
		dst->addr = NULL;
		return;
	}
}

static int try_connpath(const char* key, char* dbuf, size_t dbuf_sz, int attempt)
{
	if (!key || key[0] == '\0')
		return -1;

/* 1. If the [key] is set to an absolute path, that will be respected. */
	size_t len = strlen(key);
	if (key[0] == '/')
		return snprintf(dbuf, dbuf_sz, "%s", key);

/* 2. Otherwise we check for an XDG_RUNTIME_DIR */
	if (attempt == 0 && getenv("XDG_RUNTIME_DIR"))
		return snprintf(dbuf, dbuf_sz, "%s/%s", getenv("XDG_RUNTIME_DIR"), key);

/* 3. Last (before giving up), HOME + prefix */
	if (getenv("HOME") && attempt <= 1)
		return snprintf(dbuf, dbuf_sz, "%s/.%s", getenv("HOME"), key);

/* no env no nothing? bad environment */
	return -1;
}

/*
 * The rules for socket sharing are shared between all
 */
 int arcan_shmif_resolve_connpath(
	const char* key, char* dbuf, size_t dbuf_sz)
{
	return try_connpath(key, dbuf, dbuf_sz, 0);
}

static void shmif_exit(int c)
{
	debug_print(FATAL, NULL, "guard thread empty");
}

static bool get_shmkey_from_socket(int sock, char* wbuf, size_t sz)
{
/* do this the slow way rather than juggle block/nonblock states */
	size_t ofs = 0;
	do {
		ssize_t nr = read(sock, wbuf + ofs, 1);
		if (-1 == nr && errno != EAGAIN){
			debug_print(INFO, NULL, "shmkey_acquire:fail=%s", strerror(errno));
			return false;
		}
		else
			ofs += nr;
	}
	while(wbuf[ofs-1] != '\n' && ofs < sz);
	debug_print(INFO, NULL, "shmkey_acquire=%s:len=%zu\n", wbuf, ofs);
	wbuf[ofs-1] = '\0';

	return true;
}

char* arcan_shmif_connect(
	const char* connpath, const char* connkey, file_handle* conn_ch)
{
	struct sockaddr_un dst = {
		.sun_family = AF_UNIX
	};
	size_t lim = COUNT_OF(dst.sun_path);

	if (!connpath){
		debug_print(FATAL, NULL, "missing connection path");
		return NULL;
	}

	int len;
	char* res = NULL;
	int index = 0;
	int sock = -1;

retry:
	len = try_connpath(connpath, (char*)&dst.sun_path, lim, index++);

	if (len < 0){
		debug_print(FATAL, NULL, "couldn't resolve connection path");
		if (sock != -1)
			close(sock);
		return NULL;
	}

/* 1. treat connpath as socket and connect */
	if (sock == -1)
		sock = socket(AF_UNIX, SOCK_STREAM, 0);

#ifdef __APPLE__
	int val = 1;
	setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
#endif

	if (-1 == sock){
		debug_print(FATAL, NULL, "couldn't allocate socket: %s", strerror(errno));
		goto end;
	}

/* if connection fails, the socket will be re-used with a different address
 * until we run out - this normally will just involve XDG_RUNTIME_DIR then HOME */
	if (connect(sock, (struct sockaddr*) &dst, sizeof(dst))){
		debug_print(FATAL, NULL,
			"couldn't connect to (%s): %s", dst.sun_path, strerror(errno));
		goto retry;
	}

/* 2. send (optional) connection key, we send that first (keylen + linefeed),
 *    this setup is dated and should just be removed */
	char wbuf[PP_SHMPAGE_SHMKEYLIM+1];
	if (connkey){
		ssize_t nw = snprintf(wbuf, PP_SHMPAGE_SHMKEYLIM, "%s\n", connkey);
		if (nw >= PP_SHMPAGE_SHMKEYLIM){
			debug_print(FATAL, NULL,
				"returned path (%s) exceeds limit (%d)", connpath, PP_SHMPAGE_SHMKEYLIM);
			close(sock);
			goto end;
		}

		if (write(sock, wbuf, nw) < nw){
			debug_print(FATAL, NULL,
				"error sending connection string: %s", strerror(errno));
			close(sock);
			goto end;
		}
	}

/* 3. wait for key response (or broken socket) */
	if (!get_shmkey_from_socket(sock, wbuf, sizeof(wbuf)-1)){
		debug_print(FATAL, NULL, "invalid response on negotiation: %s", strerror(errno));
		close(sock);
		goto end;
	}

/* 4. omitted, just return a copy of the key and let someone else perform the
 * arcan_shmif_acquire call. Just set the env. */
	res = strdup(wbuf);

	*conn_ch = sock;

end:
	return res;
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

	if (!shmkey && (!parent || !parent->priv))
		return res;

	bool privps = false;

/* different path based on an acquire from a NEWSEGMENT event or if it comes
 * from a _connect (via _open) call */
	const char* key_used = NULL;

	if (!shmkey){
		struct shmif_hidden* gs = parent->priv;

/* special case as a workaround until we can drop the semaphore / key,
 * if we get a newsegment without a matching key, try and read it from
 * the socket. */
		if (strlen(gs->pseg.key) == 0){
			debug_print(INFO, parent,
				"missing_event_key:try_socket=%d", gs->pseg.epipe);
			get_shmkey_from_socket(
				gs->pseg.epipe, gs->pseg.key, COUNT_OF(gs->pseg.key)-1);
		}

		map_shared(gs->pseg.key, &res);
		key_used = gs->pseg.key;
		debug_print(INFO, parent, "newsegment_shm_key:%s", key_used);

		if (!(flags & SHMIF_DONT_UNLINK))
			unlink_keyed(gs->pseg.key);

		if (!res.addr){
			close(gs->pseg.epipe);
			gs->pseg.epipe = BADFD;
		}
		privps = true; /* can't set d/e fields yet */
	}
	else{
		debug_print(INFO, parent, "acquire_shm_key:%s", shmkey);
		key_used = shmkey;
		map_shared(shmkey, &res);
		if (!(flags & SHMIF_DONT_UNLINK))
			unlink_keyed(shmkey);
	}

	if (!res.addr){
		debug_print(FATAL, NULL, "couldn't connect through: %s", shmkey);

		if (flags & SHMIF_ACQUIRE_FATALFAIL)
			exit(EXIT_FAILURE);
		else
			return res;
	}

	void (*exitf)(int) = shmif_exit;
	if (flags & SHMIF_FATALFAIL_FUNC){
			exitf = va_arg(vargs, void(*)(int));
	}

	struct shmif_hidden gs = {
		.guard = {
			.local_dms = true,
			.semset = { res.asem, res.vsem, res.esem },
			.parent = res.addr->parent,
			.parent_fd = -1,
			.exitf = exitf
		},
		.flags = flags,
		.pev = {.fd = BADFD},
		.pseg = {.epipe = BADFD},
	};

	atomic_store(&gs.guard.dms, (uint8_t*) &res.addr->dms);

	res.priv = malloc(sizeof(struct shmif_hidden));
	memset(res.priv, '\0', sizeof(struct shmif_hidden));
	res.priv->shm_key = strdup(key_used);

	res.privext = malloc(sizeof(struct shmif_ext_hidden));
	*res.privext = (struct shmif_ext_hidden){
		.cleanup = NULL,
		.active_fd = -1,
		.pending_fd = -1,
	};

	*res.priv = gs;
	res.priv->alive = true;
	char* dbgenv = getenv("ARCAN_SHMIF_DEBUG");
	if (dbgenv)
		res.priv->log_event = strtoul(dbgenv, NULL, 10);

	if (!(flags & SHMIF_DISABLE_GUARD) && !getenv("ARCAN_SHMIF_NOGUARD"))
		spawn_guardthread(&res);

	if (privps){
		struct shmif_hidden* pp = parent->priv;

		res.epipe = pp->pseg.epipe;
#ifdef __APPLE__
		int val = 1;
		setsockopt(res.epipe, SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
#endif

/* clear this here so consume won't eat it */
		pp->pseg.epipe = BADFD;
		memset(pp->pseg.key, '\0', sizeof(pp->pseg.key));

/* reset pending descriptor state */
		consume(parent);
	}

	arcan_shmif_setevqs(res.addr, res.esem,
		&res.priv->inev, &res.priv->outev, false);

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

	res.shmsize = res.addr->segment_size;
	res.cookie = arcan_shmif_cookie();
	res.priv->type = type;

	setup_avbuf(&res);

	pthread_mutex_init(&res.priv->lock, NULL);

/* local flag that hints at different synchronization work */
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

/* this act as our safeword (or well safebyte), if either party for _any_reason
 * decides that it is not worth going the dms (dead man's switch) is pulled. */
static void* guard_thread(void* gs)
{
	struct shmif_hidden* gstr = gs;

	while (gstr->guard.active){
		if (!parent_alive(gstr)){
			volatile uint8_t* dms;

/* guard synch mutex only protects the structure itself, it is not
 * loaded or checked between every shmif-operation */
			pthread_mutex_lock(&gstr->guard.synch);

/* setting the dms here practically doesn't imply that the sem_post
 * on wakeup set won't run again from a delayed dms write, the dms
 * set action here is for any others that might monitor the segment */
			if ((dms = atomic_load(&gstr->guard.dms)))
				*dms = false;

			atomic_store(&gstr->guard.local_dms, false);

/* other threads might be locked on semaphores, so wake them up, and
 * force them to re-examine the dms from being released */
			for (size_t i = 0; i < COUNT_OF(gstr->guard.semset); i++){
				if (gstr->guard.semset[i])
					arcan_sem_post(gstr->guard.semset[i]);
			}

			gstr->guard.active = false;

/* same as everywhere else, implementation need to allow unlock to destroy */
			pthread_mutex_unlock(&gstr->guard.synch);
			pthread_mutex_destroy(&gstr->guard.synch);

/* also shutdown the socket, should unlock any blocking I/O stage */
			shutdown(gstr->guard.parent_fd, SHUT_RDWR);
			debug_print(FATAL, NULL, "guard thread activated, shutting down");

			if (gstr->guard.exitf)
				gstr->guard.exitf(EXIT_FAILURE);

			goto done;
		}

		sleep(1);
	}

done:
	return NULL;
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

void arcan_shmif_setevqs(struct arcan_shmif_page* dst,
	sem_handle esem, arcan_evctx* inq, arcan_evctx* outq, bool parent)
{
	if (parent){
		arcan_evctx* tmp = inq;
		inq = outq;
		outq = tmp;

		outq->synch.handle = esem;
		inq->synch.handle = esem;

		inq->synch.killswitch = NULL;
		outq->synch.killswitch = NULL;
	}
	else {
		inq->synch.handle = esem;
		inq->synch.killswitch = &dst->dms;
		outq->synch.handle = esem;
		outq->synch.killswitch = &dst->dms;
	}

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	if (!inq->synch.init){
		inq->synch.init = true;
		pthread_mutex_init(&inq->synch.lock, NULL);
	}
	if (!outq->synch.init){
		outq->synch.init = true;
		pthread_mutex_init(&outq->synch.lock, NULL);
	}
#endif

	inq->local = false;
	inq->eventbuf = dst->childevq.evqueue;
	inq->front = &dst->childevq.front;
	inq->back  = &dst->childevq.back;
	inq->eventbuf_sz = PP_QUEUE_SZ;

	outq->local =false;
	outq->eventbuf = dst->parentevq.evqueue;
	outq->front = &dst->parentevq.front;
	outq->back  = &dst->parentevq.back;
	outq->eventbuf_sz = PP_QUEUE_SZ;
}

unsigned arcan_shmif_signalhandle(struct arcan_shmif_cont* ctx,
	int mask, int handle, size_t stride, int format, ...)
{
	if (!arcan_pushhandle(handle, ctx->epipe))
		return 0;

	struct arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_BUFFERSTREAM,
		.ext.bstream.width = ctx->w,
		.ext.bstream.height = ctx->h,
		.ext.bstream.stride = stride,
		.ext.bstream.format = format
	};
	arcan_shmif_enqueue(ctx, &ev);
	return arcan_shmif_signal(ctx, mask);
}

static bool step_v(struct arcan_shmif_cont* ctx, int sigv)
{
	struct shmif_hidden* priv = ctx->priv;
	bool lock = false;

/* store the current hint flags, could do away with this stage by
 * only changing hints at resize_ stage */
	atomic_store(&ctx->addr->hints, ctx->hints);
	priv->vframe_id++;

/* subregion is part of the shared block and not the video buffer
 * itself. this is a design flaw that should be moved into a
 * VBI- style post-buffer footer */
	if (ctx->hints & SHMIF_RHINT_SUBREGION){

/* set if we should trim the dirty region based on current ^ last buffer,
 * but it only works if we are >= double buffered and buffers are populated */
		if ((sigv & SHMIF_SIGVID_AUTO_DIRTY) &&
			priv->vbuf_nbuf_active && priv->vbuf_cnt > 1){
			shmif_pixel* old;
			if (priv->vbuf_ind == 0)
				old = priv->vbuf[priv->vbuf_cnt-1];
			else
				old = priv->vbuf[priv->vbuf_ind-1];

			if (!calc_dirty(ctx, ctx->vidp, old)){
				log_print("%lld: SIGVID (auto-region: no-op)", arcan_timemillis());
				return false;
			}
		}

		if (ctx->dirty.x2 <= ctx->dirty.x1 || ctx->dirty.y2 <= ctx->dirty.y1){
			log_print("%lld: SIGVID "
				"(id: %"PRIu64", force_full: dirty-inval-region: %zu,%zu-%zu,%zu)",
				arcan_timemillis(),
				priv->vframe_id,
				(size_t)ctx->dirty.x1, (size_t)ctx->dirty.y1,
				(size_t)ctx->dirty.x2, (size_t)ctx->dirty.y2
			);
			ctx->dirty.x1 = 0;
			ctx->dirty.y1 = 0;
			ctx->dirty.x2 = ctx->w;
			ctx->dirty.y2 = ctx->h;
		}

		if (priv->log_event){
			log_print("%lld: SIGVID (id: %"PRIu64", block: %d region: %zu,%zu-%zu,%zu)",
				arcan_timemillis(),
				priv->vframe_id,
				(sigv & SHMIF_SIGBLK_NONE) ? 0 : 1,
				(size_t)ctx->dirty.x1, (size_t)ctx->dirty.y1,
				(size_t)ctx->dirty.x2, (size_t)ctx->dirty.y2
			);
		}

		atomic_store(&ctx->addr->dirty, ctx->dirty);

/* set an invalid dirty region so any subsequent signals would be ignored until
 * they are updated (i.e. something has changed) */
		ctx->dirty.y2 = ctx->dirty.x2 = 0;
		ctx->dirty.y1 = ctx->h;
		ctx->dirty.x1 = ctx->w;
	}
	else {
		if (priv->log_event){
			log_print("%lld: SIGVID (id: %"PRIu64", block: %d full)",
				arcan_timemillis(),
				priv->vframe_id,
				(sigv & SHMIF_SIGBLK_NONE) ? 0 : 1
			);
		}
	}

/* mark the current buffer as pending, this is used when we have
 * non-subregion + (double, triple, quadruple buffer) rendering */
	int pending = atomic_fetch_or_explicit(
		&ctx->addr->vpending, 1 << priv->vbuf_ind, memory_order_release);
	atomic_store_explicit(&ctx->addr->vready,
		priv->vbuf_ind+1, memory_order_release);

/* let a latched support content analysis work through the buffer
 * while pending before we try to slide window or synch */
	if (priv->support_window_hook)
		priv->support_window_hook(ctx, SUPPORT_EVENT_VSIGNAL);

/* slide window so the caller don't have to care about which
 * buffer we are actually working against */
	priv->vbuf_ind++;
	priv->vbuf_nbuf_active = true;
	if (priv->vbuf_ind == priv->vbuf_cnt)
		priv->vbuf_ind = 0;

/* note if we need to wait for an ack before continuing */
	lock = priv->vbuf_cnt == 1 || (pending & (1 << priv->vbuf_ind));
	ctx->vidp = priv->vbuf[priv->vbuf_ind];

/* protect against reordering, like not needed after atomic- switch */
	FORCE_SYNCH();
	return lock;
}

static bool step_a(struct arcan_shmif_cont* ctx)
{
	struct shmif_hidden* priv = ctx->priv;
	bool lock = false;

	if (ctx->abufpos)
		ctx->abufused = ctx->abufpos * sizeof(shmif_asample);

	if (ctx->abufused == 0)
		return false;

/* atomic, set [pending, used] -> flag */
	int pending = atomic_fetch_or_explicit(&ctx->addr->apending,
		1 << priv->abuf_ind, memory_order_release);
	atomic_store_explicit(&ctx->addr->abufused[priv->abuf_ind],
		ctx->abufused, memory_order_release);
	atomic_store_explicit(&ctx->addr->aready,
		priv->abuf_ind+1, memory_order_release);

/* now it is safe to slide local references */
	pending |= 1 << priv->abuf_ind;
	priv->abuf_ind++;
	if (priv->abuf_ind == priv->abuf_cnt)
		priv->abuf_ind = 0;
	ctx->abufused = ctx->abufpos = 0;
	ctx->audp = priv->abuf[priv->abuf_ind];
	lock = priv->abuf_cnt == 1 || (pending & (1 << priv->abuf_ind));

	FORCE_SYNCH();
	return lock;
}

unsigned arcan_shmif_signal(struct arcan_shmif_cont* ctx, int mask)
{
	struct shmif_hidden* priv = ctx->priv;
	if (!ctx || !ctx->addr || !priv || !ctx->vidp)
		return 0;

/* sematics for output segments are easier, no chunked buffers
 * or hooks to account for */
	if (is_output_segment(priv->type)){
		if (mask & SHMIF_SIGVID)
			atomic_store(&ctx->addr->vready, 0);
		if (mask & SHMIF_SIGAUD)
			atomic_store(&ctx->addr->aready, 0);
		return 0;
	}

/* if we are in migration there is no reason to go into signal until that
 * has been dealt with */
	if (priv->in_migrate)
		return 0;

/* and if we are in signal, migration will need to unlock semaphores so we
 * leave signal and any held mutex on the context will be released until NEXT
 * signal that would then let migration continue on other thread. */
	priv->in_signal = true;

/*
 * To protect against some callers being stuck in a 'just signal as a means of
 * draining buffers'. We can only initiate fallback recovery here if the
 * context is not unlocked, the current thread is holding the lock and there
 * is no on-going migration
 */
	if (!ctx->addr->dms || !atomic_load(&priv->guard.local_dms)){
		ctx->abufused = ctx->abufpos = 0;
		fallback_migrate(ctx, ctx->priv->alt_conn, true);
		priv->in_signal = false;
		return 0;
	}

	unsigned startt = arcan_timemillis();
	if ( (mask & SHMIF_SIGVID) && priv->video_hook)
		mask = priv->video_hook(ctx);

	if ( (mask & SHMIF_SIGAUD) && priv->audio_hook)
		mask = priv->audio_hook(ctx);

	if ( mask & SHMIF_SIGAUD ){
		bool lock = step_a(ctx);

/* guard-thread will pull the sems for us on dms */
		if (lock && !(mask & SHMIF_SIGBLK_NONE))
			arcan_sem_wait(ctx->asem);
		else
			arcan_sem_trywait(ctx->asem);
	}
/* for sub-region multi-buffer synch, we currently need to
 * check before running the step_v */
	if (mask & SHMIF_SIGVID){
		while ((ctx->hints & SHMIF_RHINT_SUBREGION)
			&& ctx->addr->vready && check_dms(ctx))
			arcan_sem_wait(ctx->vsem);

		bool lock = step_v(ctx, mask);

		if (lock && !(mask & SHMIF_SIGBLK_NONE)){
			while (ctx->addr->vready && check_dms(ctx))
				arcan_sem_wait(ctx->vsem);
		}
		else
			arcan_sem_trywait(ctx->vsem);
	}

	priv->in_signal = false;
	return arcan_timemillis() - startt;
}

struct arg_arr* arcan_shmif_args( struct arcan_shmif_cont* inctx)
{
	if (!inctx || !inctx->priv)
		return NULL;
	return inctx->priv->args;
}

void arcan_shmif_drop(struct arcan_shmif_cont* inctx)
{
	if (!inctx || !inctx->priv)
		return;

	if (inctx->priv->support_window_hook){
		inctx->priv->support_window_hook(inctx, SUPPORT_EVENT_EXIT);
	}

	pthread_mutex_lock(&inctx->priv->lock);

	if (inctx->priv->valid_initial)
		drop_initial(inctx);

	if (inctx->priv->last_words){
		log_print("[shmif:drop] last words: %s", inctx->priv->last_words);
		free(inctx->priv->last_words);
		inctx->priv->last_words = NULL;
	}

	if (inctx->addr){
		inctx->addr->dms = false;
	}

	if (inctx == primary.input)
		primary.input = NULL;

	if (inctx == primary.output)
		primary.output = NULL;

	struct shmif_hidden* gstr = inctx->priv;

	close(inctx->epipe);
	close(inctx->shmh);

	sem_close(inctx->asem);
	sem_close(inctx->esem);
	sem_close(inctx->vsem);

	if (gstr->args){
		arg_cleanup(gstr->args);
	}

/* guard thread will clean up on its own */
	free(inctx->priv->alt_conn);
	if (inctx->privext->cleanup)
		inctx->privext->cleanup(inctx);

	if (inctx->privext->active_fd != -1)
		close(inctx->privext->active_fd);
	if (inctx->privext->pending_fd != -1)
		close(inctx->privext->pending_fd);

	pthread_mutex_unlock(&inctx->priv->lock);
	pthread_mutex_destroy(&inctx->priv->lock);

	if (gstr->guard.active){
		atomic_store(&gstr->guard.dms, 0);
		gstr->guard.active = false;
	}
/* no guard thread for this context */
	else
		free(inctx->priv);
	free(inctx->privext);
	munmap(inctx->addr, inctx->shmsize);
	memset(inctx, '\0', sizeof(struct arcan_shmif_cont));
	inctx->epipe = -1;
}

static bool shmif_resize(struct arcan_shmif_cont* arg,
	unsigned width, unsigned height, struct shmif_resize_ext ext)
{
	if (!arg->addr || !arcan_shmif_integrity_check(arg) ||
	!arg->priv || width > PP_SHMPAGE_MAXW || height > PP_SHMPAGE_MAXH)
		return false;

	struct shmif_hidden* priv = arg->priv;

/* quick rename / unpack as old prototype of this didn't carry ext struct */
	size_t abufsz = ext.abuf_sz;
	int vidc = ext.vbuf_cnt;
	int audc = ext.abuf_cnt;
	int samplerate = ext.samplerate;
	int adata = ext.meta;

/* resize on a dead context triggers migration */
	if (!check_dms(arg)){
		if (priv->reset_hook)
			priv->reset_hook(SHMIF_RESET_LOST, priv->reset_hook_tag);

/* fallback migrate will trigger the reset_hook on REMAP / FAIL */
		if (SHMIF_MIGRATE_OK != fallback_migrate(arg, priv->alt_conn, true)){
			return false;
		}
	}

/* wait for any outstanding v/asynch */
	if (atomic_load(&arg->addr->vready)){
		while (atomic_load(&arg->addr->vready) && check_dms(arg))
			arcan_sem_wait(arg->vsem);
	}
	if (atomic_load(&arg->addr->aready)){
		while (atomic_load(&arg->addr->aready) && check_dms(arg))
			arcan_sem_wait(arg->asem);
	}

/* since the vready wait can be long and an error prone operation,
 * the context might have died between the check above and here */
	if (!check_dms(arg)){
		if (priv->reset_hook)
			priv->reset_hook(SHMIF_RESET_LOST, priv->reset_hook_tag);

		if (SHMIF_MIGRATE_OK != fallback_migrate(arg, priv->alt_conn, true))
			return false;
	}

	width = width < 1 ? 1 : width;
	height = height < 1 ? 1 : height;

/* 0 is allowed to disable any related data, useful for not wasting
 * storage when accelerated buffer passing is working */
	vidc = vidc < 0 ? priv->vbuf_cnt : vidc;
	audc = audc < 0 ? priv->abuf_cnt : audc;

	bool dimensions_changed = width != arg->w || height != arg->h;
	bool bufcnt_changed = vidc != priv->vbuf_cnt || audc != priv->abuf_cnt;
	bool hints_changed = arg->addr->hints != arg->hints;
	bool bufsz_changed = abufsz && arg->addr->abufsize != abufsz;

/* don't negotiate unless the goals have changed */
	if (arg->vidp &&
		!dimensions_changed &&
		!bufcnt_changed &&
		!hints_changed &&
		!bufsz_changed){
		if (priv->reset_hook)
			priv->reset_hook(SHMIF_RESET_NOCHG, priv->reset_hook_tag);

		return true;
	}

/* synchronize hints as _ORIGO_LL and similar changes only synch on resize */
	atomic_store(&arg->addr->hints, arg->hints);
	atomic_store(&arg->addr->apad_type, adata);

	if (samplerate < 0)
		atomic_store(&arg->addr->audiorate, arg->samplerate);
	else if (samplerate == 0)
		atomic_store(&arg->addr->audiorate, ARCAN_SHMIF_SAMPLERATE);
	else
		atomic_store(&arg->addr->audiorate, samplerate);

/* need strict ordering across procss boundaries here, first desired
 * dimensions, buffering etc. THEN resize request flag */
	atomic_store(&arg->addr->w, width);
	atomic_store(&arg->addr->h, height);
	atomic_store(&arg->addr->rows, ext.rows);
	atomic_store(&arg->addr->cols, ext.cols);
	atomic_store(&arg->addr->abufsize, abufsz);
	atomic_store_explicit(&arg->addr->apending, audc, memory_order_release);
	atomic_store_explicit(&arg->addr->vpending, vidc, memory_order_release);
	if (priv->log_event){
		log_print(
			"(@%"PRIxPTR" rz-synch): %zu*%zu(fl:%d), grid:%zu,%zu %zu Hz",
			(uintptr_t)arg, (size_t)width, (size_t)height, (int)arg->hints,
			(size_t)ext.rows, (size_t)ext.cols, (size_t)arg->samplerate
		);
	}

/* all force synch- calls should be removed when atomicity and reordering
 * behavior have been verified properly */
	FORCE_SYNCH();
	arg->addr->resized = 1;
	do{
		if (0 == arcan_sem_trywait(arg->vsem))
			arcan_timesleep(16);
	}
	while (arg->addr->resized > 0 && check_dms(arg));

/* post-size data commit is the last fragile moment server-side */
	if (!check_dms(arg)){
		if (priv->reset_hook){
			priv->reset_hook(SHMIF_RESET_NOCHG, priv->reset_hook_tag);
			priv->reset_hook(SHMIF_RESET_LOST, priv->reset_hook_tag);
		}

		fallback_migrate(arg, priv->alt_conn, true);
		return false;
	}

/* resized failed, old settings still in effect */
	if (arg->addr->resized == -1){
		arg->addr->resized = 0;
		if (priv->reset_hook)
			priv->reset_hook(SHMIF_RESET_NOCHG, priv->reset_hook_tag);
		return false;
	}

/*
 * the guard struct, if present, has another thread running that may trigger
 * the dms. BUT now the dms may be relocated so we must lock guard and update
 * and recalculate everything.
 */
	uintptr_t old_addr = (uintptr_t) arg->addr;

	if (arg->shmsize != arg->addr->segment_size){
		size_t new_sz = arg->addr->segment_size;
		struct shmif_hidden* gs = priv;

		if (gs->guard.active)
			pthread_mutex_lock(&gs->guard.synch);

		munmap(arg->addr, arg->shmsize);
		arg->shmsize = new_sz;
		arg->addr = mmap(NULL, arg->shmsize,
			PROT_READ | PROT_WRITE, MAP_SHARED, arg->shmh, 0);
		if (!arg->addr){
			debug_print(FATAL, arg, "segment couldn't be remapped");
			return false;
		}

		atomic_store(&gs->guard.dms, (uint8_t*) &arg->addr->dms);
		if (gs->guard.active)
			pthread_mutex_unlock(&gs->guard.synch);
	}

/*
 * make sure we start from the right buffer counts and positions
 */
	arcan_shmif_setevqs(arg->addr,
		arg->esem, &priv->inev, &priv->outev, false);
	setup_avbuf(arg);

	priv->multipart_ofs = 0;

	if (priv->reset_hook){
			priv->reset_hook(old_addr != (uintptr_t)arg->addr ?
				SHMIF_RESET_REMAP : SHMIF_RESET_NOCHG, priv->reset_hook_tag);
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

static char* strrep(char* dst, char key, char repl)
{
	char* src = dst;

	if (dst)
		while (*dst){
			if (*dst == key)
				*dst = repl;
			dst++;
		}

	return src;
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

struct arg_arr* arg_unpack(const char* resource)
{
	int argc = 1;
/* unless an empty string, we'll always have 1 */
	if (!resource)
		return NULL;

/* figure out the maximum number of additional arguments we have */
	for (size_t i = 0; resource[i]; i++)
		if (resource[i] == ':')
			argc++;

/* prepare space */
	struct arg_arr* argv = malloc( (argc+1) * sizeof(struct arg_arr) );
	if (!argv)
		return NULL;

	int curarg = 0;
	argv[argc].key = argv[argc].value = NULL;

	char* base = strdup(resource);
	char* workstr = base;

/* sweep for key=val:key:key style packed arguments, since this is used in such
 * a limited fashion (RFC 3986 at worst), we use a replacement token rather
 * than an escape one, so \t becomes : post-process
 */
	while (curarg < argc){
		char* endp = workstr;
		bool inv = false;
		argv[curarg].key = argv[curarg].value = NULL;

		while (*endp && *endp != ':'){
			if (!inv && *endp == '='){
				if (!argv[curarg].key){
					*endp = 0;
					argv[curarg].key = strrep(strdup(workstr), '\t', ':');
					argv[curarg].value = NULL;
					workstr = endp + 1;
					inv = true;
				}
				else{
					free(argv);
					argv = NULL;
					goto cleanup;
				}
			}

			endp++;
		}

		if (*endp == ':')
			*endp = '\0';

		if (argv[curarg].key)
			argv[curarg].value = strrep(strdup( workstr ), '\t', ':');
		else
			argv[curarg].key = strrep(strdup( workstr ), '\t', ':');

		workstr = (++endp);
		curarg++;
	}

cleanup:
	free(base);

	return argv;
}

void arg_cleanup(struct arg_arr* arr)
{
	if (!arr)
		return;

	while (arr->key){
		free(arr->key);
		free(arr->value);
		arr++;
	}
}

bool arg_lookup(struct arg_arr* arr, const char* val,
	unsigned short ind, const char** found)
{
	int pos = 0;
	if (found)
		*found = NULL;

	if (!arr)
		return false;

	while (arr[pos].key != NULL){
/* return only the 'ind'th match */
		if (strcmp(arr[pos].key, val) == 0)
			if (ind-- == 0){
				if (found)
					*found = arr[pos].value;

				return true;
			}

		pos++;
	}

	return false;
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

bool arcan_shmif_acquireloop(struct arcan_shmif_cont* c,
	struct arcan_event* acqev, struct arcan_event** evpool, ssize_t* evpool_sz)
{
	if (!c || !acqev || !evpool || !evpool_sz)
		return false;

/* preallocate a buffer "large enough", some unreasonable threshold */
	size_t ul = 512;
	*evpool = malloc(sizeof(struct arcan_event) * ul);
	if (!*evpool)
		return false;

	*evpool_sz = 0;
	while (arcan_shmif_wait(c, acqev) && ul--){
/* event to buffer? */
		if (acqev->category != EVENT_TARGET ||
			(acqev->tgt.kind != TARGET_COMMAND_NEWSEGMENT &&
			acqev->tgt.kind != TARGET_COMMAND_REQFAIL)){
/* dup- copy the descriptor so it doesn't get freed in shmif_wait */
			if (arcan_shmif_descrevent(acqev)){
				acqev->tgt.ioevs[0].iv =
					arcan_shmif_dupfd(acqev->tgt.ioevs[0].iv, -1, true);
			}
			(*evpool)[(*evpool_sz)++] = *acqev;
		}
		else
			return true;
	}

/* broken pool */
	debug_print(FATAL, c, "eventpool is broken: %zu / %zu", *evpool_sz, ul);
	*evpool_sz = -1;
	free(*evpool);
	*evpool = NULL;
	return false;
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

bool arcan_shmif_descrevent(struct arcan_event* ev)
{
	if (!ev)
		return false;

	if (ev->category != EVENT_TARGET)
		return false;

	unsigned list[] = {
		TARGET_COMMAND_STORE,
		TARGET_COMMAND_RESTORE,
		TARGET_COMMAND_DEVICE_NODE,
		TARGET_COMMAND_FONTHINT,
		TARGET_COMMAND_BCHUNK_IN,
		TARGET_COMMAND_BCHUNK_OUT,
		TARGET_COMMAND_NEWSEGMENT
	};

	for (size_t i = 0; i < COUNT_OF(list); i++){
		if (ev->tgt.kind == list[i] &&
			ev->tgt.ioevs[0].iv != BADFD)
				return true;
	}

	return false;
}

static int dupfd_to(int fd, int dstnum, int fflags, int fdopt)
{
	int rfd = -1;
	if (-1 == fd)
		return -1;

	if (dstnum >= 0)
		while (-1 == (rfd = dup2(fd, dstnum)) && errno == EINTR){}

	if (-1 == rfd)
		while (-1 == (rfd = dup(fd)) && errno == EINTR){}

	if (-1 == rfd)
		return -1;

/* unless F_SETLKW, EINTR is not an issue */
	int flags;
	flags = fcntl(rfd, F_GETFL);
	if (-1 != flags && fflags)
		fcntl(rfd, F_SETFL, flags | fflags);

	flags = fcntl(rfd, F_GETFD);
	if (-1 != flags && fdopt)
		fcntl(rfd, F_SETFD, flags | fdopt);

	return rfd;
}

int arcan_shmif_dupfd(int fd, int dstnum, bool blocking)
{
	return dupfd_to(fd, dstnum, blocking * O_NONBLOCK, FD_CLOEXEC);
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

enum shmif_migrate_status arcan_shmif_migrate(
	struct arcan_shmif_cont* cont, const char* newpath, const char* key)
{
	if (!cont || !cont->addr || !newpath)
		return SHMIF_MIGRATE_BADARG;

	struct shmif_hidden* P = cont->priv;

	if (!pthread_equal(P->primary_id, pthread_self()))
		return SHMIF_MIGRATE_BAD_SOURCE;

	file_handle dpipe;
	char* keyfile = NULL;

	if (-1 != a12_cp(newpath, NULL))
		keyfile = spawn_arcan_net(P, newpath, &dpipe);
	else
		keyfile = arcan_shmif_connect(newpath, key, &dpipe);
	if (!keyfile)
		return SHMIF_MIGRATE_NOCON;

/* re-use tracked "old" credentials" */
	fcntl(dpipe, F_SETFD, FD_CLOEXEC);
	struct arcan_shmif_cont ret =
		arcan_shmif_acquire(NULL, keyfile, P->type, P->flags);
	ret.epipe = dpipe;

	if (!ret.addr){
		close(dpipe);
		return SHMIF_MIGRATE_NOCON;
	}

/* all preconditions GO */
	P->in_migrate = true;
	ret.priv->guard.parent_fd = dpipe;

/* REGISTER is special, as GUID can be internally generated but should persist */
	if (P->flags & SHMIF_NOREGISTER){
		struct arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(REGISTER),
			.ext.registr.kind = P->type,
			.ext.registr.guid = {
				P->guid[0], P->guid[1]
			}
		};
		arcan_shmif_enqueue(&ret, &ev);
	}

/* allow a reset-hook to release anything pending */
	if (cont->priv->reset_hook)
		cont->priv->reset_hook(SHMIF_RESET_REMAP, cont->priv->reset_hook_tag);

/* extract settings from the page and context, forward into the new struct -
 * possibly just actually cache this inside ext would be safer */
	size_t w = cont->w;
	size_t h = cont->h;

	struct shmif_resize_ext ext = {
		.abuf_sz = cont->abufsize,
		.vbuf_cnt = P->vbuf_cnt,
		.abuf_cnt = P->abuf_cnt,
		.samplerate = cont->samplerate,
		.meta = P->atype,
		.rows = atomic_load(&cont->addr->rows),
		.cols = atomic_load(&cont->addr->cols)
	};

/* Copy the drawing/formatting hints, this is particularly important in case of
 * certain extended features such as TPACK as the size calculations are
 * different, then remap / resize the new context accordingly */
	ret.hints = cont->hints;
	shmif_resize(&ret, w, h, ext);

/* and wake anything possibly blocking still as whatever was there is dead */
	arcan_sem_post(cont->vsem);
	arcan_sem_post(cont->asem);
	arcan_sem_post(cont->esem);

/* Copy the audio/video contents of [cont] into [ret], if possible, a possible
 * workaround on failure is to check if we have VSIGNAL- state and inject one
 * of those, or delay-slot queue a RESET */
	size_t vbuf_sz_new =
		arcan_shmif_vbufsz(
			ret.priv->atype, ret.hints, ret.w, ret.h,
			atomic_load(&ret.addr->rows),
			atomic_load(&ret.addr->cols)
		);

	size_t vbuf_sz_old =
		arcan_shmif_vbufsz(
			P->atype, cont->hints, cont->w, cont->h, ext.rows, ext.cols);

/* This might miss the bit where the new vs the old connection has the same
 * format but enforce different padding rules - but that edge case is better
 * off as accepting the buffer as lost */
	if (vbuf_sz_new == vbuf_sz_old){
		for (size_t i = 0; i < P->vbuf_cnt; i++)
			memcpy(ret.priv->vbuf[i], P->vbuf[i], vbuf_sz_new);
	}
/* Set some indicator color so this can be detected visually */
	else{
		log_print("[shmif::recovery] vbuf_sz "
			"mismatch (%zu, %zu)", vbuf_sz_new, vbuf_sz_old);
		shmif_pixel color = SHMIF_RGBA(90, 60, 60, 255);
		for (size_t row = 0; row < ret.h; row++){
			shmif_pixel* cr = ret.vidp + row * ret.pitch;
			for (size_t col = 0; col < ret.w; col++)
				cr[col] = color;
			}
	}

/* The audio buffering parameters >should< be simpler as the negotiation
 * there does not have hint- or subprotocol- dependent constraints, though
 * again we could just delay-slot queue a FLUSH */
	if (ret.abuf_cnt == P->abuf_cnt && ret.abufsize == cont->abufsize){
		for (size_t i = 0; i < P->abuf_cnt && i < ret.priv->abuf_cnt; i++)
			memcpy(ret.priv->abuf[i], P->abuf[i], cont->abufsize);
	}
	else {
		log_print("[shmif::recovery] couldn't restore audio parameters"
			" , want=(%zu * %zu) got=(%zu * %zu)", (size_t)ret.priv->abuf_cnt,
			(size_t)ret.abufsize, (size_t) cont->abufsize, (size_t) P->abuf_cnt);
	}

	void* contaddr = cont->addr;

/* now we can free cont and update the video state of the new connection */
	void* olduser = cont->user;
	int oldhints = cont->hints;
	struct arcan_shmif_region olddirty = cont->dirty;

/* But not before transferring privext or accel would be lost, no platform has
 * any back-refs inside of the privext so that's fine - chances are that we
 * should switch render device though. That can't be done here as there is
 * state in the outer client that needs to come with, so when we have delay
 * slots, another one of those is needed for DEVICEHINT */
	ret.privext = cont->privext;
	cont->privext = malloc(sizeof(struct shmif_ext_hidden));
	*cont->privext = (struct shmif_ext_hidden){
		.cleanup = NULL,
		.active_fd = -1,
		.pending_fd = -1,
	};

	arcan_shmif_drop(cont);

/* last step, replace the relevant members of cont with the values from ret */
/* first try and just re-use the mapping so any aliasing issues from the
 * caller can be masked */
	void* alias = mmap(contaddr, ret.shmsize,
		PROT_READ | PROT_WRITE, MAP_SHARED, ret.shmh, 0);

/* prepare the guard-thread in the returned context to have its dms swapped */
	pthread_mutex_lock(&ret.priv->guard.synch);
	if (alias != contaddr){
		munmap(alias, ret.shmsize);
		debug_print(INFO, cont, "remapped base changed, beware of aliasing clients");
	}
/* we did manage to retain our old mapping, so switch the pointers,
 * including synchronization with the guard thread */
	else {
		munmap(ret.addr, ret.shmsize);
		ret.addr = alias;
		ret.priv->guard.dms = &ret.addr->dms;

/* need to recalculate the buffer pointers */
		arcan_shmif_mapav(ret.addr, ret.priv->vbuf, ret.priv->vbuf_cnt,
			ret.w * ret.h * sizeof(shmif_pixel), ret.priv->abuf, ret.priv->abuf_cnt,
			ret.abufsize);

		arcan_shmif_setevqs(ret.addr, ret.esem,
		&ret.priv->inev, &ret.priv->outev, false);

		ret.vidp = ret.priv->vbuf[0];
		ret.audp = ret.priv->abuf[0];
	}
	memcpy(cont, &ret, sizeof(struct arcan_shmif_cont));
	pthread_mutex_unlock(&ret.priv->guard.synch);

	cont->hints = oldhints;
	cont->dirty = olddirty;
	cont->user = olduser;

/* and signal the reset hook listener that the contents have now been
 * remapped and can be filled with new data */
	if (cont->priv->reset_hook){
		cont->priv->reset_hook(SHMIF_RESET_REMAP, cont->priv->reset_hook_tag);
	}

	P->in_migrate = false;

/* This does not currently handle subsegment remapping as they typically
 * depend on more state "server-side" and there are not that many safe
 * options. The current approach is simply to kill tracked subsegments,
 * although we could "in theory" repeat the process for each subsegment */
	return SHMIF_MIGRATE_OK;
}

static bool wait_for_activation(struct arcan_shmif_cont* cont, bool resize)
{
	arcan_event ev;
	struct arcan_shmif_initial def = {
		.country = {'G', 'B', 'R', 0},
		.lang = {'E', 'N', 'G', 0},
		.text_lang = {'E', 'N', 'G', 0},
		.latitude = 51.48,
		.longitude = 0.001475,
		.render_node = -1,
		.density = ARCAN_SHMPAGE_DEFAULT_PPCM,
		.fonts = {
			{
				.fd = -1,
				.size_mm = 3.527780
			}, {.fd = -1}, {.fd = -1}, {.fd = -1}
		}
	};

	size_t w = 640;
	size_t h = 480;
	size_t font_ind = 0;

	while (arcan_shmif_wait(cont, &ev)){
		if (ev.category != EVENT_TARGET){
			continue;
		}

		switch (ev.tgt.kind){
		case TARGET_COMMAND_ACTIVATE:
			cont->priv->valid_initial = true;
			if (resize)
				arcan_shmif_resize(cont, w, h);
			cont->priv->initial = def;
			return true;
		break;
		case TARGET_COMMAND_DISPLAYHINT:
			if (ev.tgt.ioevs[0].iv)
				w = ev.tgt.ioevs[0].iv;
			if (ev.tgt.ioevs[1].iv)
				h = ev.tgt.ioevs[1].iv;
			if (ev.tgt.ioevs[4].fv > 0.0001)
				def.density = ev.tgt.ioevs[4].fv;
			if (ev.tgt.ioevs[5].iv)
				def.cell_w = ev.tgt.ioevs[5].iv;
			if (ev.tgt.ioevs[6].iv)
				def.cell_h = ev.tgt.ioevs[6].iv;
		break;
		case TARGET_COMMAND_OUTPUTHINT:
			if (ev.tgt.ioevs[0].iv)
				def.display_width_px = ev.tgt.ioevs[0].iv;
			if (ev.tgt.ioevs[1].iv)
				def.display_height_px = ev.tgt.ioevs[1].iv;
			if (ev.tgt.ioevs[2].iv)
				def.rate = ev.tgt.ioevs[2].iv;
		break;

		case TARGET_COMMAND_GRAPHMODE:{
			bool bg = (ev.tgt.ioevs[0].iv & 256) > 0;
			int slot = ev.tgt.ioevs[0].iv & (~256);
			def.colors[1].bg[0] = 255;
			def.colors[1].bg_set = true;

			if (slot >= 0 && slot < COUNT_OF(def.colors)){
				uint8_t* dst = def.colors[slot].fg;
				if (bg){
					def.colors[slot].bg_set = true;
					dst = def.colors[slot].bg;
				}
				else
					def.colors[slot].fg_set = true;
				dst[0] = ev.tgt.ioevs[1].fv;
				dst[1] = ev.tgt.ioevs[2].fv;
				dst[2] = ev.tgt.ioevs[3].fv;
			}
		}
		break;

		case TARGET_COMMAND_DEVICE_NODE:
/* alt-con will be updated automatically, due to normal wait handler */
			if (ev.tgt.ioevs[0].iv != -1){
				def.render_node = arcan_shmif_dupfd(
					ev.tgt.ioevs[0].iv, -1, true);
			}
		break;
/* not 100% correct - won't reset if font+font-append+font
 * pattern is set but not really a valid use */
		case TARGET_COMMAND_FONTHINT:
			def.fonts[font_ind].hinting = ev.tgt.ioevs[3].iv;

/* protect against a bad value there, disabling the size isn't permitted */
			if (ev.tgt.ioevs[2].fv > 0)
				def.fonts[font_ind].size_mm = ev.tgt.ioevs[2].fv;
			if (font_ind < 3){
				if (ev.tgt.ioevs[0].iv != -1){
					def.fonts[font_ind].fd = arcan_shmif_dupfd(
						ev.tgt.ioevs[0].iv, -1, true);
					font_ind++;
				}
			}
		break;

/* allow remapping of stdin but don't CLOEXEC it */
		case TARGET_COMMAND_BCHUNK_IN:
			if (strcmp(ev.tgt.message, "stdin") == 0)
				dupfd_to(ev.tgt.ioevs[0].iv, STDIN_FILENO, 0, 0);
		break;

/* allow remapping of stdout but don't CLOEXEC it */
		case TARGET_COMMAND_BCHUNK_OUT:
			if (strcmp(ev.tgt.message, "stdout") == 0)
				dupfd_to(ev.tgt.ioevs[0].iv, STDOUT_FILENO, 0, 0);
		break;

		case TARGET_COMMAND_GEOHINT:
			def.latitude = ev.tgt.ioevs[0].fv;
			def.longitude = ev.tgt.ioevs[1].fv;
			def.elevation = ev.tgt.ioevs[2].fv;
			if (ev.tgt.ioevs[3].cv[0])
				memcpy(def.country, ev.tgt.ioevs[3].cv, 3);
			if (ev.tgt.ioevs[4].cv[0])
				memcpy(def.lang, ev.tgt.ioevs[3].cv, 3);
			if (ev.tgt.ioevs[5].cv[0])
				memcpy(def.text_lang, ev.tgt.ioevs[4].cv, 3);
			def.timezone = ev.tgt.ioevs[5].iv;
		break;
		default:
		break;
		}
	}

/* this will only be called during first setup, so the _drop is safe here
 * as the mutex lock it performs have not been exposed to the user */
	debug_print(FATAL, cont, "no-activate event, connection died/timed out");
	cont->priv->valid_initial = true;
	arcan_shmif_drop(cont);
	return false;
}

bool arcan_shmif_defer_register(
	struct arcan_shmif_cont* C, struct arcan_event ev)
{
	arcan_shmif_enqueue(C, &ev);
	return wait_for_activation(C, true);
}

static ssize_t a12_cp(const char* conn_src, bool* weak)
{
	if (weak)
		*weak = false;

	size_t len = strlen(conn_src);
	if (!len)
		return -1;

/* protocol:// friendly */
	if (strncmp(conn_src, "a12s://", 7) == 0)
		return sizeof("a12s://") - 1;
	else if (strncmp(conn_src, "a12://", 6) == 0){
		if (weak)
			*weak = true;
		return sizeof("a12://") - 1;
	}
/* tag@host:port format */
	else if (strrchr(conn_src, '@'))
		return 0;
	else
		return -1;
}

static char* spawn_arcan_net(
	struct shmif_hidden* P, const char* conn_src, int* dsock)
{
/* extract components from URL: a12://(keyid)@server(:port) */
	char* work = strdup(conn_src);
	if (!work)
		return NULL;

/* Quick-workaround, the url format for keyid@ is in conflict with other forms
 * like ident@key@. first fallback to hostname uname and if even that is
 * broken, go just by anon and let the directory deal with the likely collision */
	const char* ident = getenv("A12_IDENT");
	struct utsname nam;

	if (!ident){
		if (0 == uname(&nam)){
			if (nam.nodename[0]){
				ident = nam.nodename;
			}
		}
		if (!ident)
			ident = "anon";
	}

	bool weak;
	ssize_t start = a12_cp(conn_src, &weak);

/* (:port or ' port' - both are fine) - the argument is ignored if a12_cp returns
 * 0 as that matches a tag which already has host and port as part of its keystore
 * definition */
	const char* port = "6680";
	if (!start)
		port = NULL;

	for (size_t i = start; work[i]; i++){
		if (work[i] == ':' || work[i] == ' '){
			work[i] = '\0';
			port = &work[i+1];
		}
	}

/* build socketpair, keep one end for ourself */
	int spair[2];
	if (-1 == socketpair(PF_UNIX, SOCK_STREAM, 0, spair)){
		free(work);
		log_print("[shmif::a12::connect] couldn't build IPC socket");
		return NULL;
	}

/* as normal, we want the descriptors to be non-blocking, and
 * only the right one should persist across exec */
	for (size_t i = 0; i < 2; i++){
		int flags = fcntl(spair[i], F_GETFL);
		if (flags & O_NONBLOCK)
			fcntl(spair[i], F_SETFL, flags & (~O_NONBLOCK));

		if (i == 0){
			flags = fcntl(spair[i], F_GETFD);
			if (-1 != flags)
				fcntl(spair[i], F_SETFD, flags | FD_CLOEXEC);
		}

#ifdef __APPLE__
 		int val = 1;
		setsockopt(spair[i], SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
#endif
	}
	*dsock = spair[0];

	char tmpbuf[8];
	snprintf(tmpbuf, sizeof(tmpbuf), "%d", spair[1]);

	char ksfdbuf[8] = {'-', '1'};
	int ksfd = -1;
	if (!weak && P && P->keystate_store){
		ksfd = dupfd_to(P->keystate_store, -1, 0, 0);
		snprintf(ksfdbuf, sizeof(ksfdbuf), "%d", ksfd);
	}

/* spawn the arcan-net process, zombie- tactic was either doublefork
 * or spawn a waitpid thread - given that the length/lifespan of net
 * may well be as long as the process, go with double-fork + wait */
	pid_t pid = fork();
	if (pid == 0){
		if (0 == fork()){
			sigaction(SIGINT, &(struct sigaction){}, NULL);

			if (weak){
				execlp("arcan-net", "arcan-net", "-X",
					"--ident", ident, "--soft-auth",
					"-S", tmpbuf, &work[start], port, (char*) NULL);
			}
			else {
				execlp("arcan-net", "arcan-net", "-X",
					"--ident", ident, "--keystore", ksfdbuf, "-S",
					tmpbuf, &work[start], port, (char*) NULL);
			}

			shutdown(spair[1], SHUT_RDWR);
			exit(EXIT_FAILURE);
		}
		exit(EXIT_FAILURE);
	}
	close(spair[1]);

	if (-1 == pid){
		log_print("[shmif::a12::connect] fork() failed");
		close(spair[0]);
		return NULL;
	}

	if (-1 != ksfd){
		close(ksfd);
	}

/* temporary override any existing handler */
	struct sigaction oldsig;
	sigaction(SIGCHLD, &(struct sigaction){}, &oldsig);
	while(waitpid(pid, NULL, 0) == -1 && errno == EINTR){}
	sigaction(SIGCHLD, &oldsig, NULL);

/* retrieve shmkeyetc. like with connect */
	free(work);
	size_t ofs = 0;
	char wbuf[PP_SHMPAGE_SHMKEYLIM+1];
	do {
		if (-1 == read(*dsock, wbuf + ofs, 1)){
			debug_print(FATAL, NULL, "invalid response on negotiation");
			close(*dsock);
			return NULL;
		}
	}

	while(wbuf[ofs++] != '\n' && ofs < PP_SHMPAGE_SHMKEYLIM);
	wbuf[ofs-1] = '\0';

/* note: should possibly pass some error data from arcan-net here
 * so we can propagate an error message */

	return strdup(wbuf);
}

struct arcan_shmif_cont arcan_shmif_open_ext(enum ARCAN_FLAGS flags,
	struct arg_arr** outarg, struct shmif_open_ext ext, size_t ext_sz)
{
	struct arcan_shmif_cont ret = {0};
	file_handle dpipe;
	uint64_t ts = arcan_timemillis();

	if (!g_epoch)
		g_epoch = arcan_timemillis();

	if (outarg)
		*outarg = NULL;

	char* resource = getenv("ARCAN_ARG");
	char* keyfile = NULL;
	char* conn_src = getenv("ARCAN_CONNPATH");
	char* conn_fl = getenv("ARCAN_CONNFL");
	if (conn_fl)
		flags = (int) strtol(conn_fl, NULL, 10) |
			(flags & (SHMIF_ACQUIRE_FATALFAIL | SHMIF_NOACTIVATE));

	bool networked = false;

/* Inheritance based, still somewhat rugged until it is tolerable with one path
 * for osx and one for all the less broken OSes where we can actually inherit
 * both semaphores and shmpage without problem. If no key is provided we still
 * read that from the socket. */
	if (getenv("ARCAN_SOCKIN_FD")){
		dpipe = (int) strtol(getenv("ARCAN_SOCKIN_FD"), NULL, 10);
		if (getenv("ARCAN_SHMKEY")){
			keyfile = strdup(getenv("ARCAN_SHMKEY"));
		}
		else {
			char wbuf[PP_SHMPAGE_SHMKEYLIM+1];
			if (get_shmkey_from_socket(dpipe, wbuf, PP_SHMPAGE_SHMKEYLIM)){
				keyfile = strdup(wbuf);
			}
		}
		unsetenv("ARCAN_SOCKIN_FD");
		unsetenv("ARCAN_HANDOVER_EXEC");
		unsetenv("ARCAN_SHMKEY");
	}
/* connection point based setup, check if we want local or remote connection
 * setup - for the remote part we still need some other mechanism in the url
 * to identify credential store though */
	else if (conn_src){
		if (-1 != a12_cp(conn_src, NULL)){
			keyfile = spawn_arcan_net(NULL, conn_src, &dpipe);
			networked = true;
		}
		else {
			int step = 0;
			do {
				keyfile = arcan_shmif_connect(conn_src, getenv("ARCAN_CONNKEY"), &dpipe);
			} while (keyfile == NULL &&
				(flags & SHMIF_CONNECT_LOOP) > 0 && (sleep(1 << (step>4?4:step++)), 1));
		}
	}
	else {
		debug_print(INFO, &ret, "no connection: check ARCAN_CONNPATH");
		goto fail;
	}

	if (!keyfile || -1 == dpipe){
		debug_print(INFO, &ret, "no valid connection key on open");
		goto fail;
	}

	fcntl(dpipe, F_SETFD, FD_CLOEXEC);
	int eflags = fcntl(dpipe, F_GETFL);
	if (eflags & O_NONBLOCK)
		fcntl(dpipe, F_SETFL, eflags & (~O_NONBLOCK));

/* to differentiate between the calls that come from old shmif_open and
 * the newer extended version, we add the little quirk that ext_sz is 0 */
	if (ext_sz > 0){
/* we want manual control over the REGISTER message */
		ret = arcan_shmif_acquire(NULL, keyfile, ext.type, flags | SHMIF_NOREGISTER);
		if (!ret.priv){
			close(dpipe);
			return ret;
		}

/* remember guid used so we resend on crash recovery or migrate */
		struct shmif_hidden* priv = ret.priv;
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
			arcan_shmif_enqueue(&ret, &ev);

			if (ext.ident){
				ev.ext.kind = ARCAN_EVENT(IDENT);
					snprintf((char*)ev.ext.message.data,
					COUNT_OF(ev.ext.message.data), "%s", ext.ident);
				arcan_shmif_enqueue(&ret, &ev);
			}
		}
	}
	else{
		ret = arcan_shmif_acquire(NULL, keyfile, ext.type, flags);
		if (!ret.priv){
			close(dpipe);
			return ret;
		}
	}

	if (resource){
		ret.priv->args = arg_unpack(resource);
		if (outarg)
			*outarg = ret.priv->args;
	}

	ret.epipe = dpipe;
	if (-1 == ret.epipe){
		debug_print(FATAL, &ret, "couldn't get event pipe from parent");
	}

/* remember the last connection point and use-that on a failure on the current
 * connection point and on a failed force-migrate UNLESS we have a custom
 * alt-specifier OR come from a a12:// like setup */
	if (getenv("ARCAN_ALTCONN"))
		ret.priv->alt_conn = strdup(getenv("ARCAN_ALTCONN"));
	else if (conn_src && !networked){
		ret.priv->alt_conn = strdup(conn_src);
	}

	free(keyfile);
	if (ext.type>0 && !is_output_segment(ext.type) && !(flags & SHMIF_NOACTIVATE))
		if (!wait_for_activation(&ret, !(flags & SHMIF_NOACTIVATE_RESIZE))){
			goto fail;
		}

	ret.priv->primary_id = pthread_self();
	return ret;

fail:
	if (flags & SHMIF_ACQUIRE_FATALFAIL){
		log_print("[shmif::open_ext], error connecting");
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

void arcan_shmif_mousestate_setup(
	struct arcan_shmif_cont* con, bool relative, uint8_t* state)
{
	if (!con || !con->priv)
		return;

	struct mstate* ms = (struct mstate*) state;
	if (!ms)
		ms = &con->priv->mstate;

	*ms = (struct mstate){
		.rel = relative
	};
}

static bool absclamp(
	struct mstate* ms, struct arcan_shmif_cont* con,
	int* out_x, int* out_y)
{
	if (ms->ax < 0)
		ms->ax = 0;
	else
		ms->ax = ms->ax > con->w ? con->w : ms->ax;

	if (ms->ay < 0)
		ms->ay = 0;
	else
		ms->ay = ms->ay > con->h ? con->h : ms->ay;

/* with clamping, we can get relative samples that shouldn't
 * propagate, so test that before updating history */
	bool res = ms->ly != ms->ay || ms->lx != ms->ax;
	*out_y = ms->ly = ms->ay;
	*out_x = ms->lx = ms->ax;

	return res;
}

bool arcan_shmif_mousestate(
	struct arcan_shmif_cont* con, uint8_t* state,
	struct arcan_event* inev, int* out_x, int* out_y)
{
	return arcan_shmif_mousestate_ioev(con, state, &inev->io, out_x, out_y);
}

/*
 * Weak attempt of trying to bring some order in the accumulated mouse
 * event handling chaos - definitely one of the bigger design fails that
 * can't be fixed easily due to legacy.
 */
bool arcan_shmif_mousestate_ioev(
	struct arcan_shmif_cont* con, uint8_t* state,
	struct arcan_ioevent* inev, int* out_x, int* out_y)
{
	struct mstate* ms = (struct mstate*) state;
	if (!con || !con->priv)
		return false;

	if (!state)
		ms = &con->priv->mstate;

	if (!ms|| !out_x || !out_y)
		return false;

	if (!inev){
		if (!ms->inrel)
			return absclamp(ms, con, out_x, out_y);
		else
			*out_x = *out_y = 0;
		return true;
	}

	if (!ms ||
		inev->datatype != EVENT_IDATATYPE_ANALOG ||
		inev->devkind != EVENT_IDEVKIND_MOUSE
	)
		return false;

/* state switched between samples, reset tracking */
	bool gotrel = inev->input.analog.gotrel;
	if (gotrel != ms->inrel){
		ms->inrel = gotrel;
		ms->ax = ms->ay = ms->lx = ms->ly = 0;
	}

/* packed, both axes in one sample */
	if (inev->subid == 2){
/* relative input sample, are we in relative state? */
		if (gotrel){
/* good case, the sample is already what we want */
			if (ms->rel){
				*out_x = ms->lx = inev->input.analog.axisval[0];
				*out_y = ms->ly = inev->input.analog.axisval[2];
				return *out_x || *out_y;
			}
/* bad case, the sample is relative and we want absolute,
 * accumulate and clamp */
			ms->ax += inev->input.analog.axisval[0];
			ms->ay += inev->input.analog.axisval[2];

			return absclamp(ms, con, out_x, out_y);
		}
/* good case, the sample is absolute and we want absolute, clamp */
    else {
			if (!ms->rel){
				ms->ax = inev->input.analog.axisval[0];
				ms->ay = inev->input.analog.axisval[2];
				return absclamp(ms, con, out_x, out_y);
			}
/* worst case, the sample is absolute and we want relative,
 * need history AND discard large jumps */
			int dx = inev->input.analog.axisval[0] - ms->lx;
			int dy = inev->input.analog.axisval[2] - ms->ly;
			ms->lx = inev->input.analog.axisval[0];
			ms->ly = inev->input.analog.axisval[2];
			if (!dx && !dy){
				return false;
			}
			*out_x = dx;
			*out_y = dy;
			return true;
		}
	}

/* one sample, X axis */
	else if (inev->subid == 0){
		if (gotrel){
			if (ms->rel){
				*out_x = ms->lx = inev->input.analog.axisval[0];
				return *out_x;
			}
			ms->ax += inev->input.analog.axisval[0];
			return absclamp(ms, con, out_x, out_y);
		}
		else {
			if (!ms->rel){
				ms->ax = inev->input.analog.axisval[0];
				return absclamp(ms, con, out_x, out_y);
			}
			int dx = inev->input.analog.axisval[0] - ms->lx;
			ms->lx = inev->input.analog.axisval[0];
			if (!dx)
				return false;
			*out_x = dx;
			*out_y = 0;
			return true;
		}
	}

/* one sample, Y axis */
	else if (inev->subid == 1){
		if (gotrel){
			if (ms->rel){
				*out_y = ms->ly = inev->input.analog.axisval[0];
				return *out_y;
			}
			ms->ay += inev->input.analog.axisval[0];
			return absclamp(ms, con, out_x, out_y);
		}
		else {
			if (!ms->rel){
				ms->ay = inev->input.analog.axisval[0];
				return absclamp(ms, con, out_x, out_y);
			}
			int dy = inev->input.analog.axisval[0] - ms->ly;
			ms->ly = inev->input.analog.axisval[0];
			if (!dy)
				return false;
			*out_x = 0;
			*out_y = dy;
			return true;
		}
	}
	else
		return false;
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

/* clear the tracking in the same way as an _acquire would */
	else{
		cont->priv->pseg.epipe = BADFD;
		memset(cont->priv->pseg.key, '\0', sizeof(cont->priv->pseg.key));
		cont->priv->pev.handedover = true;

/* reset pending descriptor state */
		consume(cont);
	}

/* Dup to drop CLOEXEC and close the original */
	int dup_fd = dup(ev.tgt.ioevs[0].iv);
	close(ev.tgt.ioevs[0].iv);
	if (-1 == dup_fd)
		return -1;

	pid_t res =
		shmif_platform_execve(
			dup_fd, ev.tgt.message,
			path, argv, env,
			detach, fds, fdset_sz, NULL
		);
	close(dup_fd);

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

static bool write_buffer(int fd, char* inbuf, size_t inbuf_sz)
{
	while(inbuf_sz){
		ssize_t nr = write(fd, inbuf, inbuf_sz);
		if (-1 == nr){
			if (errno == EAGAIN || errno == EINTR)
				continue;
			return false;
		}
		inbuf += nr;
		inbuf_sz -= nr;
	}
	return true;
}

static void* copy_thread(void* inarg)
{
	int* fds = inarg;
	char inbuf[4096];
	int8_t sc = 0;

	size_t tot = 0;
	size_t acc = 0;
	size_t last_acc = 0;
	uint64_t time_last = arcan_timemillis();
	static const size_t report_mb = 10;

	struct stat fs;

/* might not remain accurate but fair to keep around, slightly more
 * diligent is re-stating on boundary invalidation (st_size < acc) */
	if (-1 != fstat(fds[0], &fs) && fs.st_size > 0){
		tot = fs.st_size;
	}

/* depending on type and OS, there are a number of options e.g. sendfile,
 * splice, sosplice, ... right now just use a slow/safe */
	for(;;){
		ssize_t nr = read(fds[0], inbuf, sizeof(inbuf));
		if (-1 == nr){
			if (errno == EAGAIN || errno == EINTR)
				continue;
			sc = -1;
			break;
		}
		if (0 == nr){
			break;
		}
		else if (!write_buffer(fds[1], inbuf, nr)){
			sc = -2;
			break;
		}

/* PIPE_BUF is required to be >= 512 on POSIX, only update every n megabytes or
 * every second or so as to not block unnecessarily on reporting while still
 * being responsive. */
		if (fds[3] & SHMIF_BGCOPY_PROGRESS){
			acc += nr;

			if (acc - last_acc > report_mb * 1024 * 1024 ||
				arcan_timemillis() - time_last > 1000){

				time_last = arcan_timemillis();
				int n = snprintf(inbuf,
					sizeof(inbuf), "%zu:%zu:%zu\n", (size_t) nr, acc, tot);
				write(fds[2], inbuf, n);
			}
		}
	}

	if (!(fds[3] & SHMIF_BGCOPY_KEEPIN))
		close(fds[0]);
	if (!(fds[3] & SHMIF_BGCOPY_KEEPOUT))
		close(fds[1]);

	if (-1 != fds[2]){
		if (fds[3] & SHMIF_BGCOPY_PROGRESS){
			int n = snprintf(inbuf, sizeof(inbuf), "%d:%zu:%zu\n", sc, acc, tot);
			while (-1 == write(fds[2], inbuf, n) &&
				(errno == EAGAIN || errno == EINTR)){}
		}
		else
			while (-1 == write(fds[2], &sc, 1) &&
				(errno == EAGAIN || errno == EINTR)){}

		close(fds[2]);
	}

	free(fds);
	return NULL;
}

void arcan_shmif_bgcopy(
	struct arcan_shmif_cont* c, int fdin, int fdout, int sigfd, int fl)
{
	int* fds = malloc(sizeof(int) * 4);
	if (!fds)
		return;

	fds[0] = fdin;
	fds[1] = fdout;
	fds[2] = sigfd;
	fds[3] = fl;

/* options, fork or thread */
	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);

	if (-1 == pthread_create(&pth, &pthattr, copy_thread, fds)){
		if (!(fl & SHMIF_BGCOPY_KEEPIN))
			close(fdin);
		if (!(fl & SHMIF_BGCOPY_KEEPOUT))
			close(fdout);
		if (-1 != sigfd){
			int8_t ch = -3;
			write(sigfd, &ch, 1);
		}
		free(fds);
	}
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

#include "../frameserver/util/utf8.c"
bool arcan_shmif_pushutf8(
	struct arcan_shmif_cont* acon, struct arcan_event* base,
	const char* msg, size_t len)
{
	uint32_t state = 0, codepoint = 0;
	const char* outs = msg;
	size_t maxlen = sizeof(base->ext.message.data) - 1;

/* utf8- point aligned against block size */
	while (len > maxlen){
		size_t i, lastok = 0;
		state = 0;
		for (i = 0; i <= maxlen - 1; i++){
			if (UTF8_ACCEPT == utf8_decode(&state, &codepoint, (uint8_t)(msg[i])))
				lastok = i;

			if (i != lastok){
				if (0 == i)
					return false;
			}
		}

		memcpy(base->ext.message.data, outs, lastok);
		base->ext.message.data[lastok] = '\0';
		len -= lastok;
		outs += lastok;
		if (len)
			base->ext.message.multipart = 1;
		else
			base->ext.message.multipart = 0;

		arcan_shmif_enqueue(acon, base);
	}

/* flush remaining */
	if (len){
		snprintf((char*)base->ext.message.data, maxlen, "%s", outs);
		base->ext.message.multipart = 0;
		arcan_shmif_enqueue(acon, base);
	}

	return true;
}

bool arcan_shmif_multipart_message(
	struct arcan_shmif_cont* C, struct arcan_event* ev,
	char** out, bool* bad)
{
	if (!C || !ev || !out || !bad ||
		ev->category != EVENT_TARGET || ev->tgt.kind != TARGET_COMMAND_MESSAGE)
		return false;

	struct shmif_hidden* P = C->priv;
	size_t msglen = strlen(ev->tgt.message);

	if (msglen + P->multipart_ofs >= sizeof(P->multipart)){
		*bad = true;
			return false;
	}
	else {
		memcpy(&P->multipart[P->multipart_ofs], ev->tgt.message, msglen);
		P->multipart_ofs += msglen;
		P->multipart[P->multipart_ofs] = '\0';
		*out = P->multipart;
	}

	return ev->tgt.ioevs[0].iv == 0;
}

/*
 * Missing: special behavior for SHMIF_RHINT_SUBREGION_CHAIN, setup chain of
 * atomic [uint32_t, bitfl] and walk from first position to last free. Bitfl
 * marks both the server side "I know this" and client side "synch this or
 * wait".
 *
 * If there's not enough store left to walk on, signal video and wait (unless
 * noblock flag is set)
 */

#ifdef __LINUX
char* arcan_shmif_bchunk_resolve(
	struct arcan_shmif_cont* C, struct arcan_event* bev)
{
	char buf[24];
	if (bev->category != EVENT_TARGET ||
		(bev->tgt.kind != TARGET_COMMAND_BCHUNK_IN &&
		 bev->tgt.kind != TARGET_COMMAND_BCHUNK_OUT))
		return NULL;

	char* mbuf = malloc(PATH_MAX);
	if (!mbuf)
		return mbuf;

	snprintf(buf, sizeof(buf), "/proc/self/fd/%d", bev->tgt.ioevs[0].iv);
	ssize_t rv = readlink(buf, mbuf, PATH_MAX);

	if (-1 == rv || mbuf[0] != '/')
		return NULL;

	struct stat base, comp;
	if (-1 == fstat(bev->tgt.ioevs[0].iv, &base) ||
			-1 == stat(mbuf, &comp) || base.st_ino != comp.st_ino){
		free(mbuf);
		return NULL;
	}

	return mbuf;
}
/* OpenBSD has no solution, FreeBSD / OSX has a fcntl that can be used */
#else
char* arcan_shmif_bchunk_resolve(
	struct arcan_shmif_cont* C, struct arcan_event* bev)
{
	return NULL;
}
#endif

#ifdef __OpenBSD__
void arcan_shmif_privsep(struct arcan_shmif_cont* C,
	const char* pledge_str, struct shmif_privsep_node** nodes, int opts)
{
	size_t i = 0;
	while (nodes[i]){
		unveil(nodes[i]->path, nodes[i]->perm);
		i++;
	}

	unveil(NULL, NULL);

	if (pledge_str){
		if (
			strcmp(pledge_str, "shmif")  == 0 ||
			strcmp(pledge_str, "decode") == 0 ||
			strcmp(pledge_str, "encode") == 0 ||
			strcmp(pledge_str, "a12-srv") == 0 ||
			strcmp(pledge_str, "a12-cl") == 0
		){
			pledge_str = SHMIF_PLEDGE_PREFIX;
		}
		else if (strcmp(pledge_str, "minimal") == 0){
			pledge_str = "stdio";
		}
		else if (strcmp(pledge_str, "minimalfd") == 0){
			pledge_str = "stdio sendfd recvfd";
		}

		pledge(pledge_str, NULL);
	}
}

#else
void arcan_shmif_privsep(struct arcan_shmif_cont* C,
	const char* pledge, struct shmif_privsep_node** nodes, int opts)
{
/* oh linux, why art thou.. */
}
#endif
