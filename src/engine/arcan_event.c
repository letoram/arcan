/*
 * Copyright: Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: The event-queue interface has gone through a lot of hacks
 * over the years and some of the decisions made makes little to no sense
 * anymore. It is primarily used as an ordering and queueing mechanism to
 * avoid a ton of callbacks when mapping between Script<->Core engine but
 * also for synchronizing transfers over the shared memory interface.
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <poll.h>
#include <errno.h>
#include <math.h>
#include <assert.h>
#include <signal.h>

/*
 * fixed limit of allowed events in queue before we need to do something more
 * aggressive (flush queue to script, blacklist noisy sources, rate- limit
 * frameservers)
 */
#ifndef ARCAN_EVENT_QUEUE_LIM
#define ARCAN_EVENT_QUEUE_LIM 255
#endif

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_db.h"
#include "arcan_shmif.h"
#include "arcan_event.h"
#include "arcan_led.h"

#include "arcan_frameserver.h"

typedef struct queue_cell queue_cell;

static arcan_event eventbuf[ARCAN_EVENT_QUEUE_LIM];

static uint8_t eventfront = 0, eventback = 0;
static int64_t epoch;

/* basic context is just mapped on the static buffer, the reason for this
 * construct is to share code with the event ring buffers in shmif */
static struct arcan_evctx default_evctx = {
	.eventbuf = eventbuf,
	.eventbuf_sz = ARCAN_EVENT_QUEUE_LIM,
	.front = &eventfront,
	.back = &eventback,
	.local = true
};

#ifndef FORCE_SYNCH
	#define FORCE_SYNCH() {\
		asm volatile("": : :"memory");\
		__sync_synchronize();\
	}
#endif

/* set through environment variable to ensure we can shut down
 * cleanly based on a certain keybinding */
static int panic_keysym = -1, panic_keymod = -1;

/* fixed size 64 entries bitmap for dynamic event source tracking */
struct evsrc_meta {
	intptr_t tag;
	mode_t mode;
	bool mask;
};

static struct pollfd evsrc_pollset[64];
static struct evsrc_meta evsrc_meta[64];
static uint64_t evsrc_bitmap;

arcan_evctx* arcan_event_defaultctx(){
	return &default_evctx;
}

/*
 * If the shmpage integrity is somehow compromised,
 * if semaphore use is out of order etc.
 */
static void pull_killswitch(arcan_evctx* ctx)
{
	arcan_frameserver* ks = (arcan_frameserver*) ctx->synch.killswitch;
	arcan_sem_post(ctx->synch.handle);
	arcan_warning("inconsistency while processing "
		"shmpage events, pulling killswitch.\n");
	arcan_frameserver_free(ks);
	ctx->synch.killswitch = NULL;
}

static bool queue_full(arcan_evctx* ctx)
{
	 return (((*ctx->back + 1) % ctx->eventbuf_sz) == *ctx->front);
}

static bool queue_empty(arcan_evctx* ctx)
{
	return (*ctx->front == *ctx->back);
}

int arcan_event_poll(arcan_evctx* ctx, struct arcan_event* dst)
{
	assert(dst);
	if (queue_empty(ctx))
		return 0;

/* overflow in external connection? pull killswitch that will hopefully
 * wake the guard thread that will try to safely shut down */
	if (ctx->local == false){
		FORCE_SYNCH();
		if ( *(ctx->front) > PP_QUEUE_SZ ){
			pull_killswitch(ctx);
			return 0;
		}
		else {
			*dst = ctx->eventbuf[ *(ctx->front) ];
			memset(&ctx->eventbuf[ *(ctx->front) ], 0xff, sizeof(struct arcan_event));
			*(ctx->front) = (*(ctx->front) + 1) % PP_QUEUE_SZ;
		}
	}
	else {
			*dst = ctx->eventbuf[ *(ctx->front) ];
			*(ctx->front) = (*(ctx->front) + 1) % ctx->eventbuf_sz;
	}

	return 1;
}

void arcan_event_repl(struct arcan_evctx* ctx, enum ARCAN_EVENT_CATEGORY cat,
	size_t r_ofs, size_t r_b, void* cmpbuf, size_t w_ofs, size_t w_b, void* w_buf)
{
	if (!ctx->local)
		return;

	unsigned front = *ctx->front;

	while (front != *ctx->back){
		if (ctx->eventbuf[front].category == cat &&
			memcmp( (char*)(&ctx->eventbuf[front]) + r_ofs, cmpbuf, r_b) == 0){
				memcpy( (char*)(&ctx->eventbuf[front]) + w_ofs, w_buf, w_b );
		}

		front = (front + 1) % ctx->eventbuf_sz;
	}

}

void arcan_event_maskall(arcan_evctx* ctx)
{
	ctx->mask_cat_inp = 0xffffffff;
}

void arcan_event_clearmask(arcan_evctx* ctx)
{
	ctx->mask_cat_inp = 0;
}

void arcan_event_setmask(arcan_evctx* ctx, uint32_t mask)
{
	ctx->mask_cat_inp = mask;
}

int arcan_event_denqueue(arcan_evctx* ctx, const struct arcan_event* const src)
{
	if (ctx->drain){
		arcan_event ev = *src;
		if (ctx->drain(&ev, 1))
			return ARCAN_OK;
	}

	return arcan_event_enqueue(ctx, src);
}

/*
 * enqueue to current context considering input-masking, unless label is set,
 * assign one based on what kind of event it is This function has a similar
 * prototype to the enqueue defined in the interop.h, but a different
 * implementation to support waking up the child, and that blocking behaviors
 * in the main thread is always forbidden.
 */
int arcan_event_enqueue(arcan_evctx* ctx, const struct arcan_event* const src)
{
/* early-out mask-filter, these are only ever used to silently
 * discard input / output (only operate on head and tail of ringbuffer) */
	if (!src || (src->category & ctx->mask_cat_inp)
		|| (ctx->state_fl & EVSTATE_DEAD) > 0)
		return ARCAN_OK;

/* One big caveat with this approach is the possibility of feedback loop with
 * magnification - forcing us to break ordering by directly feeding drain.
 * Given that we have special treatment for _EXPIRE and similar calls,
 * there shouldn't be any functions that has this behavior. Still, broken
 * ordering is better than running out of space. */
	 if (queue_full(ctx)){
		if (ctx->drain){
			TRACE_MARK_ONESHOT("event", "queue-drain", TRACE_SYS_SLOW, 0, 0, "drain");

/* very rare / impossible, but safe-guard against future bad code where the
 * force-feeding below would trigger new events that would bring us back */
			if ((ctx->state_fl & EVSTATE_IN_DRAIN) > 0){
				arcan_event ev = *src;
				if (ctx->drain(&ev, 1))
					return ARCAN_OK;
				return ARCAN_ERRC_OUT_OF_SPACE;
			}
/* tradeoff, can cascade to embarassing GC pause or video- stall but better
 * than data corruption and unpredictable states -- this can theoretically
 * have us return a broken 'custom' error code from some script */
			else {
				ctx->state_fl |= EVSTATE_IN_DRAIN;
					arcan_event_feed(ctx, ctx->drain, NULL);
				ctx->state_fl &= ~EVSTATE_IN_DRAIN;
			}
		}
		else {
			TRACE_MARK_ONESHOT("event", "queue-overflow", TRACE_SYS_WARN, 0, 0, "full");
			return ARCAN_ERRC_OUT_OF_SPACE;
		}
	}

/* this is problematic to keep here - either it should be part of the watchdog
 * process when / if we can process input there (and then it will not follow
 * keymap) or at least move to the platform stage so the event doesn't get
 * queued as input at all but rather sent to the watchdog and have it clean up
 * correctly */
	if (panic_keysym != -1 && panic_keymod != -1 &&
		src->category == EVENT_IO && src->io.kind == EVENT_IO_BUTTON &&
		src->io.devkind == EVENT_IDEVKIND_KEYBOARD &&
		src->io.input.translated.modifiers == panic_keymod &&
		src->io.input.translated.keysym == panic_keysym
	){
		arcan_event ev = {
			.category = EVENT_SYSTEM,
			.sys.kind = EVENT_SYSTEM_EXIT,
			.sys.errcode = EXIT_SUCCESS
		};

		TRACE_MARK_ONESHOT("event", "shutdown", TRACE_SYS_WARN, 0, 0, "panic key");
		return arcan_event_enqueue(ctx, &ev);
	}

	ctx->eventbuf[(*ctx->back) % ctx->eventbuf_sz] = *src;
	*ctx->back = (*ctx->back + 1) % ctx->eventbuf_sz;

	return ARCAN_OK;
}

static inline int queue_used(arcan_evctx* dq)
{
	int rv = *(dq->front) > *(dq->back) ? dq->eventbuf_sz -
	*(dq->front) + *(dq->back) : *(dq->back) - *(dq->front);
	return rv;
}

static bool append_bufferstream(struct arcan_frameserver* tgt, arcan_extevent* ev)
{
/* this assumes a certain ordering around fetching the handle and it being
 * available on the descriptor, there are no obvious hard guarantees on this
 * from the kernel, though the client libs do send descriptor before adding the
 * event and compiler can't safely re-order around it */
	int fd = arcan_fetchhandle(tgt->dpipe, false);
	if (-1 == fd){
		arcan_warning("fetchhandle-bstream mismatch\n");
		goto fail;
	}

/* if the client lies about the plane count - we arrive here: */
	if (tgt->vstream.incoming_used == 4){
		goto fail;
	}

	size_t i = tgt->vstream.incoming_used;
	tgt->vstream.incoming[i].fd = fd;
	tgt->vstream.incoming[i].gbm.stride = ev->bstream.stride;
	tgt->vstream.incoming[i].gbm.offset = ev->bstream.offset;
	tgt->vstream.incoming[i].gbm.mod_hi = ev->bstream.mod_hi;
	tgt->vstream.incoming[i].gbm.mod_lo = ev->bstream.mod_lo;
	tgt->vstream.incoming[i].gbm.format = ev->bstream.format;
	tgt->vstream.incoming[i].w = ev->bstream.width;
	tgt->vstream.incoming[i].h = ev->bstream.height;
	tgt->vstream.incoming_used++;

/* flush incoming to pending, but if there is already something pending, take
 * its place so that a newer frame gets precedence (mailbox mode) */
	if (!ev->bstream.left){
		arcan_frameserver_close_bufferqueues(tgt, false, true);
		size_t buf_sz = sizeof(struct agp_buffer_plane) * COUNT_OF(tgt->vstream.pending);
		memcpy(tgt->vstream.pending, tgt->vstream.incoming, buf_sz);
		tgt->vstream.pending_used = tgt->vstream.incoming_used;
		tgt->vstream.incoming_used = 0;
		memset(&tgt->vstream.incoming, '\0', buf_sz);
		return true;
	}

	return false;

fail:
	arcan_frameserver_close_bufferqueues(tgt, true, true);
	arcan_event_enqueue(&tgt->outqueue, &(struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_BUFFER_FAIL
	});
	tgt->vstream.dead = true;
	return true;
}


int arcan_event_queuetransfer(arcan_evctx* dstqueue, arcan_evctx* srcqueue,
	enum ARCAN_EVENT_CATEGORY allowed, float sat, struct arcan_frameserver* tgt)
{
	if (!srcqueue || !dstqueue || (srcqueue && !srcqueue->front)
		|| (srcqueue && !srcqueue->back))
		return 0;

	bool wake = false;
	bool drain = false;

/* If we set negative saturation, it means that it is permitted for this source
 * to send directly to drain (though mask and filters still apply). While this
 * should not be needed for the vast majority of clients, the exception is
 * external input device drivers and bridges e.g. X11 where a client is
 * expected to break the ev.in / ev.out rate asymetry. */
	if (sat < 0.0){
		drain = true;
		sat = 1.0;
/* see the comments further below where the drain variable is used */
	}

	size_t cap = floor((float)dstqueue->eventbuf_sz * sat);

	while (!queue_empty(srcqueue) && queue_used(dstqueue) < cap){
		arcan_event inev;
		if (arcan_event_poll(srcqueue, &inev) == 0)
			break;

/* Ioevents have special behavior as the routed path (via frameserver callback
 * or global event handler) can be decided here: if raw transfers have been
 * permitted we don't change the category as those events can be pushed out of
 * loop. Otherwise we go the slow defaultpath and forward the events through
 * the normal callback event handler. */
		if (inev.category == EVENT_IO && tgt){
			if (inev.category & allowed)
				;
			else {
				inev = (struct arcan_event){
					.category = EVENT_FSRV,
					.fsrv.kind = EVENT_FSRV_IONESTED,
					.fsrv.otag = tgt->tag,
					.fsrv.video = tgt->vid,
					.fsrv.input = inev.io
				};
			}
		}
/* a custom mask to allow certain events to be passed through or not */
		else if ((inev.category & allowed) == 0 )
			continue;

/*
 * update / translate to make sure the corresponding frameserver<->lua mapping
 * can be found and tracked, there are also a few events that should be handled
 * here rather than propagated (bufferstream for instance).
 */
		if (inev.category == EVENT_EXTERNAL && tgt){
			switch(inev.ext.kind){

/* to protect against scripts that would happily try to just allocate/respond
 * to what the event says, clamp this here */
				case EVENT_EXTERNAL_SEGREQ:
					if (inev.ext.segreq.width > PP_SHMPAGE_MAXW)
						inev.ext.segreq.width = PP_SHMPAGE_MAXW;

					if (inev.ext.segreq.height > PP_SHMPAGE_MAXH)
						inev.ext.segreq.height = PP_SHMPAGE_MAXH;
				break;

				case EVENT_EXTERNAL_BUFFERSTREAM:
/* this assumes that we are in non-blocking state and that a single CMSG on a
 * socket is sufficient for a non-blocking recvmsg */
					wake = append_bufferstream(tgt, &inev.ext);
					continue;
				break;

				case EVENT_EXTERNAL_PRIVDROP:
					tgt->flags.external |= inev.ext.privdrop.external;
					tgt->flags.networked = inev.ext.privdrop.networked;
					tgt->flags.sandboxed |= inev.ext.privdrop.sandboxed;
/* modify the event so that no illegal transitions are forwarded or applied */
					inev.ext.privdrop.external = tgt->flags.external;
					inev.ext.privdrop.networked = tgt->flags.networked;
					inev.ext.privdrop.sandboxed = tgt->flags.sandboxed;
				break;

				case EVENT_EXTERNAL_INPUTMASK:
					tgt->devicemask = inev.ext.inputmask.device;
					tgt->datamask   = inev.ext.inputmask.types;
				break;

/* for autoclocking, only one-fire events are forwarded if flag has been set */
				case EVENT_EXTERNAL_CLOCKREQ:
					if (inev.ext.clock.dynamic == 1){
						if (inev.ext.clock.rate){
							tgt->clock.present = inev.ext.clock.rate;
							tgt->clock.msc_feedback = true;
						}
						else
							tgt->clock.msc_feedback = !tgt->clock.msc_feedback;
					}
					else if (inev.ext.clock.dynamic == 2){
						tgt->clock.vblank = !tgt->clock.vblank;
					}
					else if (tgt->flags.autoclock){
						tgt->clock.once = inev.ext.clock.once;
						tgt->clock.frame = inev.ext.clock.dynamic;
						tgt->clock.left = tgt->clock.start = inev.ext.clock.rate;
						tgt->clock.id = inev.ext.clock.id;
						tgt->clock.once = inev.ext.clock.once;
					}
					continue;
				break;

				case EVENT_EXTERNAL_REGISTER:
					if (tgt->segid == SEGID_UNKNOWN){
/* 0.6/CRYPTO - need actual signature authentication here */
						if (!inev.ext.registr.guid[0] && !inev.ext.registr.guid[1]){
							arcan_random((uint8_t*)tgt->guid, 16);
						}
						else {
							tgt->guid[0] = inev.ext.registr.guid[0];
							tgt->guid[1] = inev.ext.registr.guid[1];
						}
					}
					snprintf(tgt->title,
						COUNT_OF(tgt->title), "%s", inev.ext.registr.title);
				break;
/* note: one could manually enable EVENT_INPUT and use separate processes
 * as input sources (with all the risks that comes with it security wise)
 * if that ever becomes a concern, here would be a good place to consider
 * filtering the panic_key* */

/* client may need more fine grained control for audio transfers when it
 * comes to synchronized A/V playback */
				case EVENT_EXTERNAL_FLUSHAUD:
					arcan_frameserver_flush(tgt);
					continue;
				break;

				default:
				break;
			}
			inev.ext.source = tgt->vid;
		}
		else if (inev.category == EVENT_IO && tgt){
			inev.io.subid = tgt->vid;
		}
		wake = true;

/* it might be slightly faster to drain multiple events here, but since the
 * source might be mapped to an untrusted in-memory queue it would still take a
 * full filter+copy path - so likely not worth pursuing.
 *
 * There is a complex and subtle danger here:
 *  0.Recall we are being called from the TRAMP_GUARD
 *    (against sigbus on the shared page).
 *
 *  1.In the drain function, we will jump into the callback handler in the
 *    Lua VM, still with the TRAMP_GUARD set. If that callback handler then
 *    queues an event into the frameserver, a new TRAMP_GUARD will be set
 *    for that scope, but when finished it will CLEAR the existing
 *    tramp-guard, causing the next event transfer to be performed without
 *    a guard in place. In a sense this is similar to the recursive mutex
 *    problem and atfork handling.
 *
 *  2.Another nasty possibility is that the frameserver structure might get
 *    killed off as a response to a transferred event. That's really bad.
 *
 * The mitigations are:
 *  1. Re-arm the guard based on counter changes, forward the failure.
 *  2. Add a fuse to _free, if that one blows, forward the failure.
 */
		if (drain && dstqueue->drain){
			tgt->fused = true;
			size_t last_stamp = platform_fsrv_clock();

			if (dstqueue->drain(&inev, 1)){
				if (last_stamp != platform_fsrv_clock()){
					TRAMP_GUARD(-1, tgt);
				}

				tgt->fused = false;
				if (tgt->fuse_blown){
					break;
				}
			}
			tgt->fused = false;
			continue;
		}

		arcan_event_enqueue(dstqueue, &inev);
	}

	if (wake)
		arcan_sem_post(srcqueue->synch.handle);

	return tgt->fuse_blown ? -2 : 0;
}

void arcan_event_blacklist(const char* idstr)
{
/* idstr comes from a trusted context, won't exceed stack size */
	char buf[strlen(idstr) + sizeof("bl_")];
	snprintf(buf, COUNT_OF(buf), "bl_%s", idstr);
	const char* appl;
	struct arcan_dbh* dbh = arcan_db_get_shared(&appl);
	arcan_db_appl_kv(dbh, appl, "bl_", "block");
}

bool arcan_event_blacklisted(const char* idstr)
{
/* idstr comes from a trusted context, won't exceed stack size */
	char buf[strlen(idstr) + sizeof("bl_")];
	snprintf(buf, COUNT_OF(buf), "bl_%s", idstr);
	const char* appl;
	struct arcan_dbh* dbh = arcan_db_get_shared(&appl);
	char* res = arcan_db_appl_val(dbh, appl, "bl_");
	bool rv = res && strcmp(res, "block") == 0;
	arcan_mem_free(res);
	return rv;
}

int64_t arcan_frametime()
{
	int64_t now = arcan_timemillis();
	if (now < epoch)
		epoch = now - (epoch - now);

	return now - epoch;
}

float arcan_event_process(arcan_evctx* ctx, arcan_tick_cb cb)
{
	int64_t base = ctx->c_ticks * ARCAN_TIMER_TICK;
	int64_t delta = arcan_frametime() - base;

	platform_event_process(ctx);

	if (delta > ARCAN_TIMER_TICK){
		int nticks = delta / ARCAN_TIMER_TICK;
		if (nticks > ARCAN_TICK_THRESHOLD){
			epoch += (nticks - 1) * ARCAN_TIMER_TICK;
			nticks = 1;
		}

		ctx->c_ticks += nticks;
		cb(nticks);
		arcan_bench_register_tick(nticks);
		return arcan_event_process(ctx, cb);
	}

	return (float)delta / (float)ARCAN_TIMER_TICK;
}

arcan_benchdata benchdata = {0};

/*
 * keep the time tracking separate from the other
 * timekeeping parts, discard non-monotonic values
 */
void arcan_bench_register_tick(unsigned nticks)
{
	static long long int lasttick = -1;
	if (benchdata.bench_enabled == false)
		return;

	while (nticks--){
		long long int ftime = arcan_timemillis();
		benchdata.tickcount++;

		if (lasttick > 0 && ftime > lasttick){
			unsigned delta = ftime - lasttick;
			benchdata.ticktime[(unsigned)benchdata.tickofs] = delta;
			benchdata.tickofs = (benchdata.tickofs + 1) %
				(sizeof(benchdata.ticktime) / sizeof(benchdata.ticktime[0]));
		}

		lasttick = ftime;
	}
}

void arcan_event_purge()
{
	eventfront = 0;
	eventback = 0;
	platform_event_reset(&default_evctx);
}

arcan_benchdata* arcan_bench_data()
{
	return &benchdata;
}

void arcan_bench_register_cost(unsigned cost)
{
	benchdata.framecost[(unsigned)benchdata.costofs] = cost;
	if (benchdata.bench_enabled == false)
		return;

	benchdata.costcount++;
	benchdata.costofs = (benchdata.costofs + 1) %
		(sizeof(benchdata.framecost) / sizeof(benchdata.framecost[0]));
}

void arcan_bench_register_frame()
{
	static long long int lastframe = -1;
	if (benchdata.bench_enabled == false)
		return;

	long long int ftime = arcan_timemillis();
	if (lastframe > 0 && ftime > lastframe){
		unsigned delta = ftime - lastframe;
		benchdata.frametime[(unsigned)benchdata.frameofs] = delta;
		benchdata.framecount++;
		benchdata.frameofs = (benchdata.frameofs + 1) %
			(sizeof(benchdata.frametime) / sizeof(benchdata.frametime[0]));
		}

	lastframe = ftime;
}

void arcan_event_deinit(arcan_evctx* ctx, bool flush)
{
	platform_event_deinit(ctx);

/* This separation is to avoid some edge cases like VT switching causing events
 * to be dropped even when there are dependencies such as key-down to key-up */
	if (!flush)
		return;

	eventfront = eventback = 0;
}

#ifdef _DEBUG
void arcan_event_dump(struct arcan_evctx* ctx)
{
	unsigned front = *ctx->front;
	size_t count = 0;

	while (front != *ctx->back){
		arcan_warning("slot: %d, category: %d, kind: %d\n",
			count, ctx->eventbuf[front].io.kind, ctx->eventbuf[front].category);
		front = (front + 1) % ctx->eventbuf_sz;
	}
}
#endif

#ifdef _CLOCK_FUZZ
/* jump back ~34 hours */
static void sig_rtfuzz_a(int v)
{
	epoch -= 3600 * 24 * 1000;
}
/* jump forward ~24 hours */
static void sig_rtfuzz_b(int v)
{
	epoch += 3600 * 24 * 1000;
}
#endif

bool arcan_event_feed(struct arcan_evctx* ctx,
	arcan_event_handler hnd, int* exit_code)
{
/* dead, but we weren't able to deal with it last time */
	if ((ctx->state_fl & EVSTATE_DEAD)){
		if (exit_code)
			*exit_code = ctx->exit_code;
		return false;
	}

	while (*ctx->front != *ctx->back){
/* slide, we forego _poll to cut down on one copy */
		arcan_event* ev = &ctx->eventbuf[ *(ctx->front) ];
		*(ctx->front) = (*(ctx->front) + 1) % ctx->eventbuf_sz;

		switch (ev->category){
			case EVENT_VIDEO:
				if (ev->vid.kind == EVENT_VIDEO_EXPIRE)
					arcan_video_deleteobject(ev->vid.source);
				else
					hnd(ev, 0);
			break;

			case EVENT_SYSTEM:
				if (ev->sys.kind == EVENT_SYSTEM_EXIT){
					ctx->state_fl |= EVSTATE_DEAD;
					ctx->exit_code = ev->sys.errcode;
					if (exit_code) *exit_code = ev->sys.errcode;
					break;
				}
			default:
				hnd(ev, 0);
			break;
		}
	}

	if (ctx->state_fl & EVSTATE_DEAD)
		return arcan_event_feed(ctx, hnd, exit_code);
	else
		return true;
}

static int mode_to_poll(mode_t mode)
{
	if (mode == O_RDWR)
		mode = POLLIN | POLLOUT;
	else if (mode == O_WRONLY)
		mode = POLLOUT;
	else if (mode == O_RDONLY)
		mode = POLLIN;
	return mode | POLLERR | POLLHUP;
}

bool arcan_event_add_source(
	struct arcan_evctx* ctx, int fd, mode_t mode, intptr_t otag, bool masked)
{
	int mask = 0;
	mode = mode_to_poll(mode);

/* allocate new */
	uint64_t i = __builtin_ffsll(~evsrc_bitmap);
	if (!i)
		return false;

	i--;
	evsrc_pollset[i].fd = fd;
	evsrc_pollset[i].events = mode;
	evsrc_meta[i].mode = mode;
	evsrc_meta[i].tag = otag;
	evsrc_meta[i].mask = masked;
	evsrc_bitmap |= (uint64_t)1 << i;

	return true;
}

void arcan_event_poll_sources(struct arcan_evctx* ctx, int timeout)
{
	ssize_t nelem = poll(evsrc_pollset, 64, timeout);
	if (nelem <= 0){
		if (timeout > 0)
			arcan_timesleep(timeout);
		return;
	}

	for (size_t i = 0; i < 64; i++){
		struct pollfd* ent = &evsrc_pollset[i];
		if (ent->fd <= 0 || !ent->revents || evsrc_meta[i].mask)
			continue;

		struct arcan_event ev = (struct arcan_event){
			.category = EVENT_SYSTEM,
			.sys.data.fd = evsrc_pollset[i].fd,
			.sys.data.otag = evsrc_meta[i].tag
		};

/* Note that we send IN/OUT even in the case of failure. This is to force the
 * recipient to use normal error handling for read/write to react to a
 * monitored source failing. */
		if (ent->revents & POLLIN ||
			((ent->revents & (POLLERR | POLLHUP)) && (ent->events & POLLIN))){
				ev.sys.kind = EVENT_SYSTEM_DATA_IN;
				arcan_event_denqueue(ctx, &ev);
			}

/* This is subtle - the events here go direct to drain. That means that
 * infinitely many calls to add_source and del_source can happen between these
 * two, possibly changing the otag being used to map to VM objects. Removing
 * the source is save though, as the pollset is cleared when the source is
 * removed, and this condition won't fire an extraneous event. */
		if (ent->revents & POLLOUT ||
			((ent->revents & (POLLERR | POLLHUP)) && (ent->events & POLLOUT))){
			ev.sys.kind = EVENT_SYSTEM_DATA_OUT;
			arcan_event_denqueue(ctx, &ev);
		}
	}
}

/* Remove a source previously added through add_source. Will return true if
 * the source existed and set the last known otag in *out if provided. */
bool arcan_event_del_source(
	struct arcan_evctx* ctx, int fd, mode_t mode, intptr_t* out)
{
	mode = mode_to_poll(mode);
	for (uint64_t i = 0; i < 64; i++){
		if (evsrc_pollset[i].fd == fd && evsrc_pollset[i].events == mode){
			evsrc_pollset[i].fd = -1;
			evsrc_bitmap &= ~((uint64_t)1 << i);
			if (out)
				*out = evsrc_meta[i].tag;
			evsrc_meta[i] = (struct evsrc_meta){0};
			evsrc_pollset[i] = (struct pollfd){0};
			return true;
		}
	}

	return false;
}

void arcan_event_setdrain(arcan_evctx* ctx, arcan_event_handler drain)
{
	if (!ctx->local)
		return;
	ctx->drain = drain;
}

void arcan_event_init(arcan_evctx* ctx)
{
/*
 * non-local (i.e. shmpage resident) event queues has a different
 * init approach (see frameserver_shmpage.c)
 */
	if (!ctx->local){
		return;
	}

/*
 * used for testing response to clock skew over time
 */
#if defined(_DEBUG) && defined(_CLOCK_FUZZ)
	sigaction(SIGRTMIN+0, &(struct sigaction) {.sa_handler = sig_rtfuzz_a}, NULL);
	sigaction(SIGRTMIN+1, &(struct sigaction) {.sa_handler = sig_rtfuzz_b}, NULL);
#endif

	const char* panicbutton = getenv("ARCAN_EVENT_SHUTDOWN");
	char* cp;

	if (panicbutton){
		cp = strchr(panicbutton, ':');
		if (cp){
			*cp = '\0';
			panic_keysym = strtol(panicbutton, NULL, 10);
			panic_keymod = strtol(cp+1, NULL, 10);
			*cp = ':';
		}
		else
			arcan_warning("ARCAN_EVENT_SHUTDOWN=%s, malformed key "
				"expecting number:number (keysym:modifiers).\n", panicbutton);
	}

	epoch = arcan_timemillis() - ctx->c_ticks * ARCAN_TIMER_TICK;
	platform_event_init(ctx);
}

void arcan_led_removed(int devid)
{
	arcan_event_enqueue(arcan_event_defaultctx(),
		&(struct arcan_event){
		.category = EVENT_IO,
		.io.kind = EVENT_IO_STATUS,
		.io.devkind = EVENT_IDEVKIND_STATUS,
		.io.devid = devid,
		.io.input.status.domain = 1,
		.io.input.status.devkind = EVENT_IDEVKIND_LEDCTRL,
		.io.input.status.action = EVENT_IDEV_REMOVED
	});
}

void arcan_led_added(int devid, int refdev, const char* label)
{
	arcan_event ev = {
		.category = EVENT_IO,
		.io.kind = EVENT_IO_STATUS,
		.io.devkind = EVENT_IDEVKIND_STATUS,
		.io.devid = devid,
		.io.input.status.devref = refdev,
		.io.input.status.domain = 1,
		.io.input.status.devkind = EVENT_IDEVKIND_LEDCTRL,
		.io.input.status.action = EVENT_IDEV_ADDED
	};
	snprintf(ev.io.label, COUNT_OF(ev.io.label), "%s", label);
	arcan_event_enqueue(arcan_event_defaultctx(), &ev);
}

extern void platform_device_lock(int lockdev, bool lockstate);
void arcan_device_lock(int lockdev, bool lockstate)
{
	platform_device_lock(lockdev, lockstate);
}
