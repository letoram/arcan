/*
 * Copyright 2003-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_EPRIV
#define _HAVE_ARCAN_EPRIV

struct arcan_evctx;

/* check timers, poll IO events and timing calculations
 * out : (NOT NULL) storage- container for number of ticks that has passed
 *                   since the last call to arcan_process
 * ret : range [0 > n < 1] how much time has passed towards the next tick */
typedef void (*arcan_tick_cb)(int count);
float arcan_event_process(struct arcan_evctx*, arcan_tick_cb);

struct arcan_evctx* arcan_event_defaultctx();

/*
 * Pushes as many events from srcqueue to dstqueue as possible
 * without over-saturating. allowed defines which kind of category
 * that will be transferred, other events will be silently ignored (dropped)
 * The saturation cap is defined in 0..1 range as % of full capacity
 * specifying a source ID (can be ARCAN_EID) will be used for rewrites
 * if the category has a source identifier
 */
void arcan_event_queuetransfer(
	struct arcan_evctx* dstqueue, struct arcan_evctx* srcqueue,
	enum ARCAN_EVENT_CATEGORY allowed, float saturation, arcan_vobj_id source
);

int arcan_event_poll(struct arcan_evctx*, struct arcan_event* dst);
int arcan_event_wait(struct arcan_evctx*, struct arcan_event* dst);

/*
 * Try and enqueue the element to the queue. If the context is
 * set to lossless, enqueue may block, sleep (or spinlock).
 *
 * returns the number of FREE slots left on success or a negative
 * value on failure. The purpose of the try- approach is to let
 * the user distinguish between necessary and merely "helpful"
 * events (e.g. frame numbers, net ping-pongs etc.)
 *
 * These methods are thread-safe if and only if
 * ARCAN_SHMIF_THREADSAFE_QUEUE has been defined at build-time and
 * not during a pending resize operation.
 */
int arcan_event_enqueue(struct arcan_evctx*, const struct arcan_event* const);
int arcan_event_tryenqueue(struct arcan_evctx*,const struct arcan_event* const);

/* ignore-all on enqueue */
void arcan_event_maskall(struct arcan_evctx*);

/* drop any mask, including maskall */
void arcan_event_clearmask(struct arcan_evctx*);

/* set a specific mask, somewhat limited */
void arcan_event_setmask(struct arcan_evctx*, unsigned mask);

/* global clock, milisecond resolution relative to epoch set during start */
int64_t arcan_frametime();

/*
 * Lock and sweep the event queue to alter all events in category
 * where memcmp((ev+r_ofs), cmpbuf, r_b) match and then write
 * w_b from buf to ev+w_ofs.
 *
 * This is used to manually patch or rewrite events that need
 * to be invalidated after that they have been enqueued, primarily
 * for EVENT_FRAMESERVER_*
 */
void arcan_event_repl(struct arcan_evctx* ctx, enum ARCAN_EVENT_CATEGORY cat,
	size_t r_ofs, size_t r_b, void* cmpbuf,
	size_t w_ofs, size_t w_b, void* w_buf
);

/*
 * used as part of trying to salvage external connections while resetting
 * audio/video/scripting contexts. This sweeps the "to be processed"
 * event-queue and removes all events that doesn't strictly come from external
 * sources or might otherwise leak state from previous context
 */
void arcan_event_purge();

#ifdef _DEBUG
void arcan_event_dump(struct arcan_evctx*);
#endif

void arcan_event_init(struct arcan_evctx* dstcontext);

void arcan_event_deinit(struct arcan_evctx*);

#endif

