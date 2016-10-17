/*
 * Copyright 2012-2016, Björn Ståhl
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

#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <pthread.h>

#include "arcan_shmif.h"
#include "shmif_privext.h"

#include <signal.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

/*
 * a bit clunky, but some scenarios that we want debug-builds but without the
 * debug logging spam for external projects, and others where we want to
 * redefine the logging macro for shmif- only.
 */
#ifdef _DEBUG
#ifndef _DEBUG_NOLOG
#define DLOG(...)
#endif

#ifndef DLOG
#define DLOG(...) LOG(__VA_ARGS__)
#endif
#else
#ifndef DLOG
#define DLOG(...)
#endif
#endif

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
 * These should be kept in lock-step with changes to the event structures.
 */
static const char* tgt_cmd_xlt[] = {
	"UNDEFINED",
	"EXIT",
	"FRAMESKIP",
	"STEPFRAME",
	"COREOPT",
	"STORE",
	"RESTORE",
	"BCHUNK_IN",
	"BCHINK_OUT",
	"RESET",
	"PAUSE",
	"UNPAUSE",
	"SEEKTIME",
	"SEEKCONTENT",
	"DISPLAYHINT",
	"SETIODEV",
	"STREAMSET",
	"ATTENUATE",
	"AUDDELAY",
	"NEWSEGMENT",
	"REQFAIL",
	"BUFFER_FAIL",
	"DEVICE_NODE",
	"GRAPHMODE",
	"MESSAGE",
	"FONTHINT",
	"GEOHINT",
	"OUTPUTHINT",
	"ACTIVATE"
};

static const char* ext_cmd_xlt[] = {
	"MESSAGE",
	"COREOPT",
	"IDENT",
	"FAILURE",
	"BUFFERSTREAM",
	"FRAMESTATUS",
	"STREAMINFO",
	"STREAMSTATUS",
	"STATESIZE",
	"FLUSHAUDIO",
	"SEGMENT_REQUEST",
	"KEYINPUT",
	"CURSORINPUT",
	"CURSORHINT",
	"VIEWPORT",
	"CONTENT",
	"LABELHINT",
	"REGISTER",
	"ALERT",
	"CLOCKREQ",
	"BCHUNKSTATE"
};

static const char* fsrv_cmd_xlt[] = {
	"EXTCONN",
	"RESIZED",
	"TERMINATED",
	"DROPPEDFRAME",
	"DELIVEREDFRAME"
};

static const char* cat_xlt[] = {
	"SYSTEM",
	"IO",
	"VIDEO",
	"AUDIO",
	"TARGET",
	"FSRV",
	"EXT",
	"NET"
};

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

const char* arcan_shmif_eventstr(arcan_event* aev, char* dbuf, size_t dsz)
{
	static char evbuf[256];
	char* work;
	if (dbuf){
		work = dbuf;
	}
	else{
		work = evbuf;
		dsz = sizeof(evbuf);
	}

	int cat_ind = ilog2(aev->category);

	if (cat_ind < 1 || cat_ind > COUNT_OF(cat_xlt))
		return NULL;

	const char* evstr;
	switch(aev->category){
	case EVENT_TARGET:
		evstr = aev->tgt.kind > COUNT_OF(tgt_cmd_xlt)
			? "overflow/broken" : tgt_cmd_xlt[aev->ext.kind];
	break;
	case EVENT_FSRV:
		evstr = aev->fsrv.kind > COUNT_OF(fsrv_cmd_xlt)
			? "" : fsrv_cmd_xlt[aev->fsrv.kind];
	break;
	case EVENT_EXTERNAL:
		evstr = aev->ext.kind > COUNT_OF(ext_cmd_xlt)
			? "overflow/broken" : ext_cmd_xlt[aev->ext.kind];
		break;
	default:
		evstr = "UNKNOWN";
	}

	snprintf(work, dsz, "%s:%s", cat_xlt[cat_ind], evstr);

	return work;
}

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
struct shmif_hidden {
	shmif_trigger_hook video_hook;
	void* video_hook_data;
	uint8_t vbuf_ind, vbuf_cnt;
	shmif_pixel* vbuf[ARCAN_SHMIF_VBUFC_LIM];

	shmif_trigger_hook audio_hook;
	void* audio_hook_data;
	uint8_t abuf_ind, abuf_cnt;
	shmif_asample* abuf[ARCAN_SHMIF_ABUFC_LIM];

	struct arcan_shmif_initial initial;
	bool valid_initial, output, alive, paused;
	char* alt_conn;

	enum ARCAN_FLAGS flags;
	int type;

	struct arcan_evctx inev;
	struct arcan_evctx outev;

/* during automatic pause, we want displayhint and fonthint events to queue and
 * aggregate so we can return immediately on release, this pattern can be
 * re-used for more events should they be needed (possibly CLOCK..) */
	struct arcan_event dh, fh;
	int ph; /* bit 1, dh - bit 2 fh */

	struct {
		bool gotev, consumed;
		arcan_event ev;
		file_handle fd;
	} pev;

/* used for pending / incoming subsegments */
	struct {
		int epipe;
		char key[256];
	} pseg;

/* guard thread checks DMS and a parent PID, then tries to pull synch
 * handles and/or run an @exit function */
	struct {
		bool active;
		sem_handle semset[3];
		process_handle parent;
		volatile uint8_t* dms;
		pthread_mutex_t synch;
		void (*exitf)(int val);
	} guard;

/* if we permit 'reconnect on parent- death', this callback will be invoked
 * when a previously returned cont is invalid, and provide a newly negotiated
 * context */
	void (*resetf)(struct arcan_shmif_cont*);
};

static struct {
	struct arcan_shmif_cont* input, (* output);
} primary;

static void* guard_thread(void* gstruct);

static inline bool parent_alive(struct shmif_hidden* gs)
{
/* based on the idea that init inherits an orphaned process, return getppid()
 * != 1; won't work for hijack targets that double fork, and we don't have
 * the means for an inhertied connection right now (though a reasonable
 * possibility) */
	return kill(gs->guard.parent, 0) != -1;
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
	pthread_create(&pth, &pthattr, guard_thread, hgs);
	pthread_detach(pth);
}

#ifndef offsetof
#define offsetof(type, member) ((size_t)((char*)&(*(type*)0).member\
 - (char*)&(*(type*)0)))
#endif

uint64_t arcan_shmif_cookie()
{
	uint64_t base = sizeof(struct arcan_event) + sizeof(struct arcan_shmif_page);
	base += (uint64_t)offsetof(struct arcan_shmif_page, cookie)  <<  8;
	base += (uint64_t)offsetof(struct arcan_shmif_page, resized) << 16;
	base += (uint64_t)offsetof(struct arcan_shmif_page, aready)  << 24;
	base += (uint64_t)offsetof(struct arcan_shmif_page, abufused)<< 32;
	base += (uint64_t)offsetof(struct arcan_shmif_page, childevq.front) << 40;
	base += (uint64_t)offsetof(struct arcan_shmif_page, childevq.back) << 48;
	base += (uint64_t)offsetof(struct arcan_shmif_page, parentevq.front) << 56;
	return base;
}

static void fd_event(struct arcan_shmif_cont* c, struct arcan_event* dst)
{
/*
 * if we get a descriptor event that is connected to acquiring a new
 * frameserver subsegment- set up special tracking so we can retain the
 * descriptor as new signalling/socket transfer descriptor
 */
	if (dst->category == EVENT_TARGET &&
		dst->tgt.kind == TARGET_COMMAND_NEWSEGMENT){
		c->priv->pseg.epipe = c->priv->pev.fd;
		c->priv->pev.fd = BADFD;
		memcpy(c->priv->pseg.key, dst->tgt.message, sizeof(dst->tgt.message));
	}
/*
 * otherwise we have a normal pending slot with a descriptor that
 * is inserted into the event, then set as consumed (so next call,
 * unless the descriptor is dup:ed or used, it will close
 */
	else
		dst->tgt.ioevs[0].iv = c->priv->pev.fd;

	c->priv->pev.consumed = true;
}

/*
 * reset pending- state tracking
 */
static void consume(struct arcan_shmif_cont* c)
{
	if (!c->priv->pev.consumed)
		return;

	if (BADFD != c->priv->pev.fd){
		close(c->priv->pev.fd);
		LOG("(shmif) closing unhandled/ignored/dup:ed state descriptor\n");
	}

	if (BADFD != c->priv->pseg.epipe){
		close(c->priv->pseg.epipe);
		c->priv->pseg.epipe = BADFD;
		LOG("(shmif) closing unhandled / ignored subsegment descriptor\n");
	}

	c->priv->pev.fd = BADFD;
	c->priv->pev.gotev = false;
	c->priv->pev.consumed = false;
}

/*
 * special rules for compacting DISPLAYHINT events,
 * where we keep w/h (if set) but overwrite hint/rgb/density
 */
static inline void merge_dh(arcan_event* new, arcan_event* old)
{
	if (!new->tgt.ioevs[0].iv)
		new->tgt.ioevs[0].iv = old->tgt.ioevs[0].iv;

	if (!new->tgt.ioevs[1].iv)
		new->tgt.ioevs[1].iv = old->tgt.ioevs[1].iv;

	if ((new->tgt.ioevs[2].iv & 128))
		new->tgt.ioevs[2].iv = old->tgt.ioevs[2].iv;

	if (!(new->tgt.ioevs[4].fv > 0))
		new->tgt.ioevs[4].fv = old->tgt.ioevs[4].fv;

	if (new->tgt.ioevs[3].iv < 0)
		new->tgt.ioevs[3].iv = old->tgt.ioevs[3].iv;
}

static bool scan_disp_event(struct arcan_evctx* c, struct arcan_event* old)
{
	uint8_t cur = *c->front;

	while (cur != *c->back){
		struct arcan_event* ev = &c->eventbuf[cur];
		if (ev->category == EVENT_TARGET && ev->tgt.kind == old->tgt.kind){
			merge_dh(ev, old);
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

static enum shmif_migrate_status fallback_migrate(struct arcan_shmif_cont* c)
{
/* sleep - retry connect loop */
	enum shmif_migrate_status sv;
	int step = 0;

/* parent can pull dms explicitly */
	if ((c->priv->flags & SHMIF_NOAUTO_RECONNECT) ||
		parent_alive(c->priv) || c->priv->output)
		return SHMIF_MIGRATE_NOCON;

/* we force CONNECT_LOOP style behavior here */
	while ((sv = arcan_shmif_migrate(
		c, c->priv->alt_conn, NULL)) == SHMIF_MIGRATE_NOCON){
		sleep(1 << step);
		if (step < 4)
			step++;
	}

	switch (sv){
	case SHMIF_MIGRATE_NOCON: break;
	case SHMIF_MIGRATE_BADARG:
		LOG("(shmif) recover process failed, broken alternate- path/key\n");
	break;
	case SHMIF_MIGRATE_TRANSFER_FAIL:
		LOG("(shmif) the migration process failed during setup, can't recover\n");
	break;

/* set a reset event in the "to be dispatched next dequeue" slot */
	case SHMIF_MIGRATE_OK:
		c->priv->ph |= 4;
		c->priv->fh = (struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_RESET,
			.tgt.ioevs[0].iv = 3
		};
	break;
	}

	return sv;
}

static int process_events(struct arcan_shmif_cont* c,
	struct arcan_event* dst, bool blocking, bool upret)
{
reset:
	if (!c || !dst || !c->addr || !c->priv->alive)
		return -1;

	struct shmif_hidden* priv = c->priv;
	bool noks = false;
	int rv = 0;

/* difference between dms and ks is that the dms is pulled by the shared
 * memory interface and process management, killswitch from the event queues */
	struct arcan_evctx* ctx = &priv->inev;
	volatile uint8_t* ks = (volatile uint8_t*) ctx->synch.killswitch;

/* Select few events has a special queue position and can be delivered 'out of
 * order' from normal affairs. This is needed for displayhint/fonthint in WM
 * cases where a connection may be suspended for a long time and normal system
 * state (move window between displays, change global fonts) may be silently
 * ignored, when we actually want them delivered immediately upon UNPAUSE */
#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_lock(&ctx->synch.lock);
#endif

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
		if (-1 == priv->pev.fd)
			priv->pev.fd = arcan_fetchhandle(c->epipe, blocking);

		if (priv->pev.gotev){
			LOG("(shmif) waiting for descriptor from %d parent (%d:%d)\n",
				c->epipe, priv->pev.fd, blocking);
			if (priv->pev.fd != BADFD){
				fd_event(c, dst);
				rv = 1;
			}
			else if (blocking){ LOG("(shmif) blocking fd wait failed, %s\n", strerror(errno));}
			goto done;
		}
	} while (priv->pev.gotev && *ks && c->addr->dms);

/* atomic increment of front -> event enqueued, memset is technically
 * superflous but helps showing event queue consumption in debugging */
	if (*ctx->front != *ctx->back){
		*dst = ctx->eventbuf[ *ctx->front ];
		memset(&ctx->eventbuf[ *ctx->front ], '\0', sizeof(arcan_event));
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
					priv->pev.gotev = true;
					goto checkfd;
				}
				else
					dst->tgt.ioevs[0].iv = BADFD;
			break;

/* similar to fonthint but uses different descriptor- indicator field,
 * more complex rules for if we should forward or handle ourselves. If
 * it's about switching or defining render node for handle passing, then
 * we need to forward as the client need to rebuild its context. */
			case TARGET_COMMAND_DEVICE_NODE:{
				int iev = dst->tgt.ioevs[1].iv;
				if (iev == 4){
/* replace slot with message, never forward */
					if (priv->alt_conn)
						free(priv->alt_conn);
					priv->alt_conn = strdup(dst->tgt.message);
					goto reset;
				}
				else if (iev >= 1 && iev <= 3){
					if (dst->tgt.message[0] == '\0'){
						priv->pev.gotev = true;
						goto checkfd;
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
			case TARGET_COMMAND_STORE:
			case TARGET_COMMAND_RESTORE:
			case TARGET_COMMAND_BCHUNK_IN:
			case TARGET_COMMAND_BCHUNK_OUT:
			case TARGET_COMMAND_NEWSEGMENT:
				LOG("(shmif) got descriptor transfer related event\n");
				priv->pev.gotev = true;
				goto checkfd;
			default:
			break;
			}

		rv = 1;
	}
	else if (c->addr->dms == 0){
		rv = fallback_migrate(c) == SHMIF_MIGRATE_OK ? 0 : -1;
		goto done;
	}

/* Need to constantly pump the event socket for incoming descriptors and
 * caller- mandated polling, as the order between event and descriptor is
 * not deterministic */
	else if (blocking && *ks)
		goto checkfd;

done:
#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

	return *ks || noks ? rv : -1;
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
	if (c && c->priv->valid_initial)
		drop_initial(c);

	return process_events(c, dst, false, false);
}

int arcan_shmif_wait(struct arcan_shmif_cont* c, struct arcan_event* dst)
{
	if (c && c->priv->valid_initial)
		drop_initial(c);

	return process_events(c, dst, true, false) > 0;
}

int arcan_shmif_enqueue(struct arcan_shmif_cont* c,
	const struct arcan_event* const src)
{
	assert(c);
	if (!c->addr)
		return 0;

	if (!c->addr->dms || !c->priv->alive){
		fallback_migrate(c);
		return 0;
	}

	struct arcan_evctx* ctx = &c->priv->outev;

/* paused only set if segment is configured to handle it,
 * and process_events on blocking will block until unpaused */
	if (c->priv->paused){
		struct arcan_event ev;
		process_events(c, &ev, true, true);
	}

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_lock(&ctx->synch.lock);
#endif

	while ( ((*ctx->back + 1) % ctx->eventbuf_sz) == *ctx->front){
		DLOG("arcan_event_enqueue(), going to sleep, eventqueue full\n");
		arcan_sem_wait(ctx->synch.handle);
	}

	ctx->eventbuf[*ctx->back] = *src;
	if (src->category == 0)
		ctx->eventbuf[*ctx->back].category = EVENT_EXTERNAL;
	FORCE_SYNCH();
	*ctx->back = (*ctx->back + 1) % ctx->eventbuf_sz;

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

	return 1;
}

int arcan_shmif_tryenqueue(
	struct arcan_shmif_cont* c, const arcan_event* const src)
{
	assert(c);
	if (!c || !src || !c->addr || !c->addr->dms)
		return 0;

	struct arcan_evctx* ctx = &c->priv->outev;
	if (c->priv->paused)
		return 0;

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_lock(&ctx->synch.lock);
#endif

	if (((*ctx->front + 1) % ctx->eventbuf_sz) == *ctx->back){
#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

		return 0;
	}

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

	return arcan_shmif_enqueue(c, src);
}

static void map_shared(const char* shmkey, char force_unlink,
	struct arcan_shmif_cont* dst)
{
	assert(shmkey);
	assert(strlen(shmkey) > 0);

	int fd = -1;
	fd = shm_open(shmkey, O_RDWR, 0700);

	if (-1 == fd){
		LOG("arcan_frameserver(getshm) -- couldn't open "
			"keyfile (%s), reason: %s\n", shmkey, strerror(errno));
		return;
	}

	dst->addr = mmap(NULL, ARCAN_SHMPAGE_START_SZ,
		PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	dst->shmh = fd;

	if (force_unlink)
		shm_unlink(shmkey);

	if (MAP_FAILED == dst->addr){
map_fail:
		LOG("arcan_frameserver(getshm) -- couldn't map keyfile"
			"	(%s), reason: %s\n", shmkey, strerror(errno));
		dst->addr = NULL;
		return;
	}

/* parent suggested a different size from the start, need to remap */
	if (dst->addr->segment_size != ARCAN_SHMPAGE_START_SZ){
		DLOG("arcan_frameserver(getshm) -- different initial size, remapping.\n");
		size_t sz = dst->addr->segment_size;
		munmap(dst->addr, ARCAN_SHMPAGE_START_SZ);
		dst->addr = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
		if (MAP_FAILED == dst->addr)
			goto map_fail;
	}

	DLOG("arcan_frameserver(getshm) -- mapped to %" PRIxPTR
		" \n", (uintptr_t) dst->addr);

/* step 2, semaphore handles */
	size_t slen = strlen(shmkey) + 1;
	if (slen > 1){
		char work[slen];
		snprintf(work, slen, "%s", shmkey);
		slen -= 2;
		work[slen] = 'v';
		dst->vsem = sem_open(work, 0);
		if (force_unlink)
			sem_unlink(work);

		work[slen] = 'a';
		dst->asem = sem_open(work, 0);
		if (force_unlink)
			sem_unlink(work);

		work[slen] = 'e';
		dst->esem = sem_open(work, 0);
		if (force_unlink)
			sem_unlink(work);
	}

	if (dst->asem == 0x0 || dst->esem == 0x0 || dst->vsem == 0x0){
		LOG("arcan_shmif_control(getshm) -- couldn't "
			"map semaphores (basekey: %s), giving up.\n", shmkey);
		free(dst->addr);
		dst->addr = NULL;
		return;
	}
}

/* the rules for resolving the connection socket namespace are somewhat
 * complex, i.e. on linux we have the atrocious \0 prefix that defines a
 * separate socket namespace, if we don't specify an absolute path, the key
 * will resolve to be relative your HOME environment (BUT we also have an odd
 * size limitation to sun_path to take into consideration). */
int arcan_shmif_resolve_connpath(const char* key,
	char* dbuf, size_t dbuf_sz)
{
	int len;
#ifdef __LINUX
	if (ARCAN_SHMIF_PREFIX[0] == '\0'){
		len = 1+snprintf(dbuf+1, dbuf_sz-1, "%s%s", &ARCAN_SHMIF_PREFIX[1], key);
	}
	else
#endif
	if (ARCAN_SHMIF_PREFIX[0] == '/')
		len = snprintf(dbuf, dbuf_sz, "%s%s", ARCAN_SHMIF_PREFIX, key);
	else
		len = snprintf(dbuf, dbuf_sz, "%s/%s%s",
			getenv("HOME"), ARCAN_SHMIF_PREFIX, key);

	if (len >= dbuf_sz)
		return len - dbuf_sz;
	else
		return len;
}

static void shmif_exit(int c)
{
	DLOG("(guard_thread::exit) - empty shmif_exit\n");
}

char* arcan_shmif_connect(const char* connpath, const char* connkey,
	file_handle* conn_ch)
{
	struct sockaddr_un dst = {
		.sun_family = AF_UNIX
	};
	size_t lim = COUNT_OF(dst.sun_path);

	if (!connpath){
		DLOG("arcan_shmif_connect(), missing connpath, giving up.\n");
		return NULL;
	}

	char* res = NULL;
	int len = arcan_shmif_resolve_connpath(connpath, (char*)&dst.sun_path, lim);

	if (len < 0){
		LOG("arcan_shmif_resolve_connpath(%s) - connection path too long"
			" (%d vs %zu)\n", dst.sun_path, abs(len), lim);
		return NULL;
	}

/* 1. treat connpath as socket and connect */
	int sock = socket(AF_UNIX, SOCK_STREAM, 0);

#ifdef __APPLE__
	int val = 1;
	setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
#endif

	if (-1 == sock){
		DLOG("arcan_shmif_connect(), "
			"couldn't allocate socket, reason: %s\n", strerror(errno));
		goto end;
	}

/* connection or not, unlink the connection path */
	if (connect(sock, (struct sockaddr*) &dst, sizeof(dst))){
		DLOG("arcan_shmif_connect(%s), "
			"couldn't connect to server, reason: %s.\n",
			dst.sun_path, strerror(errno)
		);
		close(sock);
		goto end;
	}

/* 2. send (optional) connection key, we send that first (keylen + linefeed) */
	char wbuf[PP_SHMPAGE_SHMKEYLIM+1];
	if (connkey){
		ssize_t nw = snprintf(wbuf, PP_SHMPAGE_SHMKEYLIM, "%s\n", connkey);
		if (nw >= PP_SHMPAGE_SHMKEYLIM){
			DLOG("arcan_shmif_connect(%s), ident string (%s) exceeds "
				"limit (%d).\n", connpath, connkey, PP_SHMPAGE_SHMKEYLIM);
			close(sock);
			goto end;
		}

		if (write(sock, wbuf, nw) < nw){
			DLOG("arcan_shmif_connect(), error sending connection "
				"string, reason: %s\n", strerror(errno));
			close(sock);
			goto end;
		}
	}

/* 3. wait for key response (or broken socket) */
	size_t ofs = 0;
	do {
		if (-1 == read(sock, wbuf + ofs, 1)){
			DLOG("arcan_shmif_connect(%s), "
				"invalid response received during shmpage negotiation.\n", connpath);
			close(sock);
			goto end;
		}
	}
	while(wbuf[ofs++] != '\n' && ofs < PP_SHMPAGE_SHMKEYLIM);
	wbuf[ofs-1] = '\0';

/* 4. omitted, just return a copy of the key and let someoneddelse perform the
 * arcan_shmif_acquire call. Just set the env. */
	res = strdup(wbuf);

	*conn_ch = sock;

end:
	return res;
}

static void setup_avbuf(struct arcan_shmif_cont* res)
{
	res->w = atomic_load(&res->addr->w);
	res->h = atomic_load(&res->addr->h);
	res->stride = res->w * ARCAN_SHMPAGE_VCHANNELS;
	res->pitch = res->w;

	res->priv->vbuf_cnt = atomic_load(&res->addr->vpending);
	res->priv->abuf_cnt = atomic_load(&res->addr->apending);

	res->priv->abuf_ind = 0;
	res->priv->vbuf_ind = 0;
	atomic_store(&res->addr->vpending, 0);
	atomic_store(&res->addr->apending, 0);
	res->abufused = res->abufpos = 0;
	res->abufsize = atomic_load(&res->addr->abufsize);
	res->abufcount = res->abufsize / sizeof(shmif_asample);
	res->abuf_cnt = res->priv->abuf_cnt;
	res->samplerate = atomic_load(&res->addr->audiorate);
	if (0 == res->samplerate)
		res->samplerate = ARCAN_SHMIF_SAMPLERATE;

	arcan_shmif_mapav(res->addr,
		res->priv->vbuf, res->priv->vbuf_cnt, res->w*res->h*sizeof(shmif_pixel),
		res->priv->abuf, res->priv->abuf_cnt, res->abufsize
	);

/*
 * NOTE, this means that every time we remap/rebuffer, the previous
 * A/V state is lost on our side, no matter if we're changing A, V or A/V.
 */
	res->vidp = res->priv->vbuf[0];
	res->audp = res->priv->abuf[0];
}

/* using a base address where the meta structure will reside, allocate n- audio
 * and n- video slots and populate vbuf/abuf with matching / aligned pointers
 * and return the total size */
struct arcan_shmif_cont arcan_shmif_acquire(
	struct arcan_shmif_cont* parent,
	const char* shmkey,
	enum ARCAN_SEGID type,
	enum ARCAN_FLAGS flags, ...)
{
	struct arcan_shmif_cont res = {
		.vidp = NULL
	};

	if (!shmkey && (!parent || !parent->priv))
		return res;

	bool privps = false;

/* different path based on an acquire from a NEWSEGMENT event or if it comes
 * from a _connect (via _open) call */
	if (!shmkey){
		struct shmif_hidden* gs = parent->priv;
		map_shared(gs->pseg.key, !(flags & SHMIF_DONT_UNLINK), &res);
		if (!res.addr){
			close(gs->pseg.epipe);
			gs->pseg.epipe = BADFD;
		}
		privps = true; /* can't set d/e fields yet */
	}
	else
		map_shared(shmkey, !(flags & SHMIF_DONT_UNLINK), &res);

	if (!res.addr){
		LOG("(arcan_shmif) Couldn't acquire connection through (%s)\n", shmkey);

		if (flags & SHMIF_ACQUIRE_FATALFAIL)
			exit(EXIT_FAILURE);
		else
			return res;
	}

	void (*exitf)(int) = shmif_exit;
	if (flags & SHMIF_FATALFAIL_FUNC){
		va_list funarg;

		va_start(funarg, flags);
			exitf = va_arg(funarg, void(*)(int));
		va_end(funarg);
	}

	struct shmif_hidden gs = {
		.guard = {
			.dms = (uint8_t*) &res.addr->dms,
			.semset = { res.asem, res.vsem, res.esem },
			.parent = res.addr->parent,
			.exitf = exitf
		},
		.flags = flags,
		.pev = {.fd = BADFD},
		.pseg = {.epipe = BADFD},
	};

	res.priv = malloc(sizeof(struct shmif_hidden));
	memset(res.priv, '\0', sizeof(struct shmif_hidden));
	res.privext = malloc(sizeof(struct shmif_ext_hidden));
	*res.privext = (struct shmif_ext_hidden){
		.cleanup = NULL,
		.active_fd = -1,
		.pending_fd = -1
	};

	*res.priv = gs;
	res.priv->alive = true;

	if (!(flags & SHMIF_DISABLE_GUARD))
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

	if (0 != type) {
		struct arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(REGISTER),
			.ext.registr.kind = type
		};
		arcan_shmif_enqueue(&res, &ev);
	}

	res.shmsize = res.addr->segment_size;
	res.cookie = arcan_shmif_cookie();
	res.priv->type = type;

	setup_avbuf(&res);

/* local flag that hints at different synchronization work */
	if (type == SEGID_ENCODER || type == SEGID_CLIPBOARD_PASTE){
		((struct shmif_hidden*)res.priv)->output = true;
	}

	return res;
}

/* this act as our safeword (or well safebyte), if either party
 * for _any_reason decides that it is not worth going - the dms
 * (dead man's switch) is pulled. */
static void* guard_thread(void* gs)
{
	struct shmif_hidden* gstr = gs;
	*(gstr->guard.dms) = true;

	while (gstr->guard.active){
		if (!parent_alive(gstr)){
			pthread_mutex_lock(&gstr->guard.synch);
			*(gstr->guard.dms) = false;

			for (size_t i = 0; i < COUNT_OF(gstr->guard.semset); i++){
				if (gstr->guard.semset[i])
					arcan_sem_post(gstr->guard.semset[i]);
			}

			pthread_mutex_unlock(&gstr->guard.synch);
			sleep(5);
			DLOG("frameserver::guard_thread -- couldn't shut"
				"	down gracefully, exiting.\n");

			if (gstr->guard.exitf)
				gstr->guard.exitf(EXIT_FAILURE);
			goto done;
		}

		sleep(5);
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
		LOG("frameserver::shmif integrity check failed, version mismatch\n");
		return false;
	}

	if (shmp->cookie != cont->cookie)
	{
		LOG("frameserver::shmif integrity check failed, non-matching cookies"
			"(%llu) vs (%llu), this is a serious issue indicating either "
			"data-corruption or compiler / interface version mismatch.\n",
			(long long unsigned) shmp->cookie, (long long unsigned) cont->cookie);

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
	enum arcan_shmif_sigmask mask, int handle, size_t stride, int format, ...)
{
	if (!arcan_pushhandle(handle, ctx->epipe))
		return 0;

	struct arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_BUFFERSTREAM,
		.ext.bstream.pitch = stride,
		.ext.bstream.format = format
	};
	arcan_shmif_enqueue(ctx, &ev);
	return arcan_shmif_signal(ctx, mask);
}

static bool step_v(struct arcan_shmif_cont* ctx)
{
	struct shmif_hidden* priv = ctx->priv;
	bool lock = false;

	atomic_store(&ctx->addr->hints, ctx->hints);
	if (ctx->hints & SHMIF_RHINT_SUBREGION)
		atomic_store(&ctx->addr->dirty, ctx->dirty);
	int pending = atomic_fetch_or_explicit(&ctx->addr->vpending,
		1 << priv->vbuf_ind, memory_order_release);
	atomic_store_explicit(&ctx->addr->vready,
		priv->vbuf_ind+1, memory_order_release);

/* slide window so the caller don't have to care about which
 * buffer we are actually working against */
	priv->vbuf_ind++;
	if (priv->vbuf_ind == priv->vbuf_cnt)
		priv->vbuf_ind = 0;
	lock = priv->vbuf_cnt == 1 || (pending & (1 << priv->vbuf_ind));
	ctx->vidp = priv->vbuf[priv->vbuf_ind];

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

unsigned arcan_shmif_signal(struct arcan_shmif_cont* ctx,
	enum arcan_shmif_sigmask mask)
{
	struct shmif_hidden* priv = ctx->priv;
	if (!ctx || !ctx->addr)
		return 0;

	if (!ctx->vidp)
		return 0;

/* to protect against some callers being stuck in a 'just signal
 * as a means of draining buffers' */
	if (!ctx->addr->dms){
		ctx->abufused = ctx->abufpos = 0;
		fallback_migrate(ctx);
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
	if (mask & SHMIF_SIGVID){
		bool lock = step_v(ctx);

		if (lock && !(mask & SHMIF_SIGBLK_NONE))
			arcan_sem_wait(ctx->vsem);
		else
			arcan_sem_trywait(ctx->vsem);
	}

	return arcan_timemillis() - startt;
}

void arcan_shmif_drop(struct arcan_shmif_cont* inctx)
{
	if (!inctx || !inctx->priv)
		return;

	LOG("dropping, dms status: %d\n", inctx->addr->dms);
	if (inctx->priv->valid_initial)
		drop_initial(inctx);

	if (inctx->addr)
		inctx->addr->dms = false;

	struct shmif_hidden* gstr = inctx->priv;

	close(inctx->epipe);
	close(inctx->shmh);

	sem_close(inctx->asem);
	sem_close(inctx->esem);
	sem_close(inctx->vsem);

/* guard thread will clean up on its own */
	free(inctx->priv->alt_conn);
	if (inctx->privext->cleanup)
		inctx->privext->cleanup(inctx);

	if (inctx->privext->active_fd != -1)
		close(inctx->privext->active_fd);
	if (inctx->privext->pending_fd != -1)
		close(inctx->privext->pending_fd);

	if (gstr->guard.active){
		gstr->guard.active = false;
	}
/* no guard thread for this context */
	else
		free(inctx->priv);
	free(inctx->privext);
	munmap(inctx->addr, inctx->shmsize);
	memset(inctx, '\0', sizeof(struct arcan_shmif_cont));
}

static bool shmif_resize(struct arcan_shmif_cont* arg,
	unsigned width, unsigned height,
	size_t abufsz, int vidc, int audc, int samplerate)
{
	if (!arg->addr || !arcan_shmif_integrity_check(arg) ||
	width > PP_SHMPAGE_MAXW || height > PP_SHMPAGE_MAXH)
		return false;

	if (!arg->addr->dms){
		if (SHMIF_MIGRATE_OK != fallback_migrate(arg))
			return false;
	}

/* wait for any outstanding v/asynch */
	if (atomic_load(&arg->addr->vready)){
		while (atomic_load(&arg->addr->vready) && arg->addr->dms)
			arcan_sem_wait(arg->vsem);
	}
	if (atomic_load(&arg->addr->aready)){
		while (atomic_load(&arg->addr->aready) && arg->addr->dms)
			arcan_sem_wait(arg->asem);
	}

	width = width < 1 ? 1 : width;
	height = height < 1 ? 1 : height;

/* 0 is allowed to disable any related data, useful for not wasting
 * storage when accelerated buffer passing is working */
	vidc = vidc < 0 ? arg->priv->vbuf_cnt : vidc;
	audc = audc < 0 ? arg->priv->abuf_cnt : audc;

/* don't negotiate unless the goals have changed */
	if (arg->vidp && width == arg->w && height == arg->h &&
		vidc == arg->priv->vbuf_cnt && audc == arg->priv->abuf_cnt &&
		arg->addr->hints == arg->hints)
		return true;

/* synchronize hints as _ORIGO_LL and similar changes only synch
 * on resize */
	atomic_store(&arg->addr->hints, arg->hints);

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
	atomic_store(&arg->addr->abufsize, abufsz);
	atomic_store_explicit(&arg->addr->apending, audc, memory_order_release);
	atomic_store_explicit(&arg->addr->vpending, vidc, memory_order_release);

/* all force synch- calls should be removed when atomicity and reordering
 * behavior have been verified properly */
	FORCE_SYNCH();
	arg->addr->resized = 1;
	arcan_sem_wait(arg->vsem);

/*
 * spin until acknowledged, re-using the "wait on sync-fd" approach might be
 * worthwile, but previous latency etc. showed it's not worth it based on the
 * code overhead from needing to buffer, manage descriptors, etc. as there
 * might be other events 'in flight'.
 */
	while(arg->addr->resized == 1 && arg->addr->dms)
		;

	if (!arg->addr->dms){
		DLOG("dead man switch pulled during resize, giving up.\n");
		return false;
	}

/*
 * the guard struct, if present, has another thread running that may trigger
 * the dms. BUT now the dms may be relocated so we must lock guard and update
 * and recalculate everything.
 */
	if (arg->shmsize != arg->addr->segment_size){
		size_t new_sz = arg->addr->segment_size;
		struct shmif_hidden* gs = arg->priv;
		pthread_mutex_lock(&gs->guard.synch);

		munmap(arg->addr, arg->shmsize);
		arg->shmsize = new_sz;
		arg->addr = mmap(NULL, arg->shmsize,
			PROT_READ | PROT_WRITE, MAP_SHARED, arg->shmh, 0);
		if (!arg->addr){
			DLOG("arcan_shmif_resize() failed on segment remapping.\n");
			return false;
		}

		gs->guard.dms = &arg->addr->dms;
		pthread_mutex_unlock(&gs->guard.synch);
	}

/*
 * make sure we start from the right buffer counts and positions
 */
	arcan_shmif_setevqs(arg->addr, arg->esem,
		&arg->priv->inev, &arg->priv->outev, false);
	setup_avbuf(arg);
	return true;
}

bool arcan_shmif_resize_ext(struct arcan_shmif_cont* arg,
	unsigned width, unsigned height, struct shmif_resize_ext ext)
{
	return shmif_resize(arg, width, height,
		ext.abuf_sz, ext.vbuf_cnt, ext.abuf_cnt, ext.samplerate);
}

bool arcan_shmif_resize(struct arcan_shmif_cont* arg,
	unsigned width, unsigned height)
{
	return shmif_resize(arg, width, height,
		arg->addr->abufsize, -1, -1, -1);
}

shmif_trigger_hook arcan_shmif_signalhook(struct arcan_shmif_cont* cont,
	enum arcan_shmif_sigmask mask, shmif_trigger_hook hook, void* data)
{
	struct shmif_hidden* priv = cont->priv;
	shmif_trigger_hook rv = NULL;

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
	else;

	return rv;
}

struct arcan_shmif_cont* arcan_shmif_primary(enum arcan_shmif_type type)
{
	if (type == SHMIF_INPUT)
		return primary.input;
	else
		return primary.output;
}

void arcan_shmif_setprimary(enum arcan_shmif_type type,
	struct arcan_shmif_cont* seg)
{
	if (type == SHMIF_INPUT)
		primary.input = seg;
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

struct arg_arr* arg_unpack(const char* resource)
{
	int argc = 1;
	const char* rsstr = resource;

/* unless an empty string, we'll always have 1 */
	if (!resource)
		return NULL;

/* figure out the number of additional arguments we have */
	do{
		if (rsstr[argc] == ':')
			argc++;
		rsstr++;
	} while(*rsstr);

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

int arcan_shmif_dupfd(int fd, int dstnum, bool blocking)
{
	int rfd = -1;
	if (-1 == fd)
		return -1;

	if (dstnum > 0)
		while (-1 == (rfd = dup2(fd, dstnum)) && errno == EINTR){}

	if (-1 == rfd)
		while (-1 == (rfd = dup(fd)) && errno == EINTR){}

	if (-1 == rfd)
		return -1;

/* unless F_SETLKW, EINTR is not an issue */
	int flags;
	if (!blocking){
		flags = fcntl(rfd, F_GETFL);
		if (-1 != flags)
			fcntl(rfd, F_SETFL, flags | O_NONBLOCK);
	}

	flags = fcntl(rfd, F_GETFD);
	if (-1 != flags)
		fcntl(rfd, F_SETFD, flags | O_CLOEXEC);

	return rfd;
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

	enum ARCAN_FLAGS flags = 0;
	bool active;

	file_handle dpipe;
	char* keyfile = arcan_shmif_connect(newpath, key, &dpipe);
	if (!keyfile)
		return SHMIF_MIGRATE_NOCON;

/* re-use tracked "old" credentials" */
	fcntl(dpipe, F_SETFD, FD_CLOEXEC);
	struct arcan_shmif_cont ret =
		arcan_shmif_acquire(NULL, keyfile, cont->priv->type, cont->priv->flags);
	ret.epipe = dpipe;

	if (!ret.addr){
		close(dpipe);
		return SHMIF_MIGRATE_NOCON;
	}

/* got a valid connection, first synch source segment so we don't have
 * anything pending */
	while(atomic_load(&cont->addr->vready) && cont->addr->dms)
		arcan_sem_wait(cont->vsem);

	while(atomic_load(&cont->addr->aready) && cont->addr->dms)
		arcan_sem_wait(cont->vsem);

	size_t w = atomic_load(&cont->addr->w);
	size_t h = atomic_load(&cont->addr->h);

	if (!shmif_resize(&ret, w, h, cont->abufsize,
		cont->priv->vbuf_cnt, cont->priv->abuf_cnt, cont->samplerate)){
		arcan_shmif_drop(&ret);
		return SHMIF_MIGRATE_TRANSFER_FAIL;
	}

/* Copy the audio/video video contents of [cont] into [ret] */
	for (size_t i = 0; i < cont->priv->vbuf_cnt; i++)
		memcpy(ret.priv->vbuf[i], cont->priv->vbuf[i], cont->stride * cont->h);
	for (size_t i = 0; i < cont->priv->abuf_cnt; i++)
		memcpy(ret.priv->abuf[i], cont->priv->abuf[i], cont->abufsize);

	void* contaddr = cont->addr;

/* now we can free cont and update the video state of the new connection */
	void* olduser = cont->user;
	int oldhints = cont->hints;
	struct arcan_shmif_region olddirty = cont->dirty;
	arcan_shmif_drop(cont);
	arcan_shmif_signal(&ret, SHMIF_SIGVID);

/* last step, replace the relevant members of cont with the values from ret */
/* first try and just re-use the mapping so any aliasing issues from the
 * caller can be masked */
	void* alias = mmap(contaddr, ret.shmsize, PROT_READ |
		PROT_WRITE, MAP_SHARED, ret.shmh, 0);

	pthread_mutex_lock(&ret.priv->guard.synch);
	if (alias != contaddr){
		munmap(alias, ret.shmsize);
		DLOG("Couldn't retain mapping, client-aliasing may break\n");
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

/* This does not currently handle subsegment remapping as they typically
 * depend on more state "server-side" and there are not that many safe
 * options. The current approach is simply to kill tracked subsegments,
 * although we could "in theory" repeat the process for each subsegment */
	return SHMIF_MIGRATE_OK;
}

static void wait_for_activation(struct arcan_shmif_cont* cont, bool resize)
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
			{.fd = -1}, {.fd = -1}, {.fd = -1}, {.fd = -1}
		}
	};

	size_t w = 640;
	size_t h = 480;
	size_t font_ind = 0;

	while (arcan_shmif_wait(cont, &ev)){
		LOG("event: %s\n", arcan_shmif_eventstr(&ev, NULL, 0));
		if (ev.category != EVENT_TARGET){
			continue;
		}

		switch (ev.tgt.kind){
		case TARGET_COMMAND_ACTIVATE:
			LOG("activation()\n");
			cont->priv->valid_initial = true;
			if (resize)
				arcan_shmif_resize(cont, w, h);
			cont->priv->initial = def;
			return;
		break;
		case TARGET_COMMAND_DISPLAYHINT:
			if (ev.tgt.ioevs[0].iv)
				w = ev.tgt.ioevs[0].iv;
			if (ev.tgt.ioevs[1].iv)
				h = ev.tgt.ioevs[1].iv;
			if (ev.tgt.ioevs[4].fv > 0.0001)
				def.density = ev.tgt.ioevs[4].fv;
			LOG("displayhint (%d, %d, %f)()\n", w, h, def.density);
		break;
		case TARGET_COMMAND_OUTPUTHINT:
			if (ev.tgt.ioevs[0].iv)
				def.display_width_px = ev.tgt.ioevs[0].iv;
			if (ev.tgt.ioevs[1].iv)
				def.display_height_px = ev.tgt.ioevs[1].iv;
			LOG("outputhint (%d, %d)()\n", def.display_width_px, def.display_height_px);
		break;
		case TARGET_COMMAND_DEVICE_NODE:
/* alt-con will be updated automatically, due to normal wait handler */
			if (ev.tgt.ioevs[0].iv != -1){
				LOG("render target device node: %d\n", ev.tgt.ioevs[0].iv);
				def.render_node = arcan_shmif_dupfd(
					ev.tgt.ioevs[0].iv, def.render_node, true);
			}
		break;
/* not 100% correct - won't reset if font+font-append+font
 * pattern is set but not really a valid use */
		case TARGET_COMMAND_FONTHINT:
			def.fonts[font_ind].hinting = ev.tgt.ioevs[3].iv;
			def.fonts[font_ind].size_mm = ev.tgt.ioevs[2].fv;
			if (font_ind < 3){
				LOG("font_hint(%d)\n");
				if (ev.tgt.ioevs[0].iv != -1){
					def.fonts[font_ind].fd = arcan_shmif_dupfd(
						ev.tgt.ioevs[0].iv, def.fonts[font_ind].fd, true);
					font_ind++;
				}
			}
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

	LOG("never got activate, connection died\n");
	cont->priv->valid_initial = true;
	arcan_shmif_drop(cont);
	return;
}

struct arcan_shmif_cont arcan_shmif_open_ext(enum ARCAN_FLAGS flags,
	struct arg_arr** outarg, struct shmif_open_ext ext, size_t ext_sz)
{
	struct arcan_shmif_cont ret = {0};
	file_handle dpipe;

	char* resource = getenv("ARCAN_ARG");
	char* keyfile = NULL;
	char* conn_src = getenv("ARCAN_CONNPATH");

	if (getenv("ARCAN_SHMKEY") && getenv("ARCAN_SOCKIN_FD")){
		keyfile = strdup(getenv("ARCAN_SHMKEY"));
		dpipe = (int) strtol(getenv("ARCAN_SOCKIN_FD"), NULL, 10);
	}
	else if (conn_src){
		int step = 0;
		do {
			keyfile = arcan_shmif_connect(conn_src, getenv("ARCAN_CONNKEY"), &dpipe);
		} while (keyfile == NULL &&
			(flags & SHMIF_CONNECT_LOOP) > 0 && (sleep(1 << (step>4?4:step++)), 1));
	}
	else {
		LOG("shmif_open() - No arcan-shmif connection, "
			"check ARCAN_CONNPATH environment.\n\n");
		goto fail;
	}

	if (!keyfile){
		LOG("shmif_open() - No valid connection key found, giving up.\n");
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
		ret = arcan_shmif_acquire(NULL, keyfile, 0, flags);
		struct arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(REGISTER),
			.ext.registr = {
				.kind = ext.type,
				.guid = {ext.guid[0], ext.guid[1]}
			}
		};
		if (ext.title)
			snprintf(ev.ext.registr.title,
				COUNT_OF(ev.ext.registr.title), "%s", ext.title);
		arcan_shmif_enqueue(&ret, &ev);

		if (ext.ident){
			ev.ext.kind = ARCAN_EVENT(IDENT);
			snprintf((char*)ev.ext.message.data,
				COUNT_OF(ev.ext.message.data), "%s", ext.ident);
			arcan_shmif_enqueue(&ret, &ev);
		}
	}
	else
		ret = arcan_shmif_acquire(NULL, keyfile, ext.type, flags);

	if (outarg){
		if (resource)
			*outarg = arg_unpack(resource);
		else
			*outarg = NULL;
	}

	ret.epipe = dpipe;
	if (-1 == ret.epipe)
		DLOG("shmif_open() - Could not retrieve event- pipe from parent.\n");

	if (conn_src)
		ret.priv->alt_conn = strdup(conn_src);

	free(keyfile);
	wait_for_activation(&ret, !(flags & SHMIF_NOACTIVATE_RESIZE));
	return ret;

fail:
	if (flags & SHMIF_ACQUIRE_FATALFAIL)
		exit(EXIT_FAILURE);
	return ret;
}

struct arcan_shmif_cont arcan_shmif_open(
	enum ARCAN_SEGID type, enum ARCAN_FLAGS flags, struct arg_arr** outarg)
{
	return arcan_shmif_open_ext(flags, outarg,
		(struct shmif_open_ext){.type = type}, 0);
}
