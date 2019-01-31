/*
 * Copyright 2003-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: Internal engine event queue handler and pseudo-monotonic
 * time keeping. Grab _defaultctx, prepare with _init -> pump with _process
 * and flush with _feed.
 *
 * For synching frameserver, explicitly run _queuetransfer.
 */
#ifndef _HAVE_ARCAN_EPRIV
#define _HAVE_ARCAN_EPRIV

struct arcan_evctx;

enum evctx_states {
	EVSTATE_OK = 0,
	EVSTATE_DEAD = 1,
	EVSTATE_IN_DRAIN = 2
};

/*
 * Retrieve the default (internally static) event context
 */
struct arcan_evctx* arcan_event_defaultctx();

/* check timers, poll IO events and timing calculations
 * out : (NOT NULL) storage- container for number of ticks that has passed
 *                   since the last call to arcan_process
 * ret : range [0 > n < 1] how much time has passed towards the next tick */
typedef void (*arcan_tick_cb)(int count);

/*
 * initialize a context structure. The [drain] function will be invoked if the
 * queue gets saturated during an enqueue. That will force an internal
 * dequeue-race, and in the rare case of feedback loops (drain function leads
 * to more enqueue calls) break ordering.
 */
typedef void (*arcan_event_handler)(arcan_event*, int);
void arcan_event_init(struct arcan_evctx*);
void arcan_event_set_drain(arcan_event_handler);

/*
 * Time- keeping function, need to be pumped regularly (will take care of
 * polling input devices and maintain the pseudo-monotonic clock).
 * Returns the fraction of the next tick (useful for interpolation).
 */
float arcan_event_process(struct arcan_evctx*, arcan_tick_cb);

/*
 * Process the entire event queue and forward relevant events through [hnd].
 * Will return false if an exit state is enqueued, and optional [ec] exit code
 * set.
 */
bool arcan_event_feed(struct arcan_evctx*, arcan_event_handler hnd, int* ec);

/*
 * Convert as many external events in [srcqueue] to [dstqueue] as possible
 * without breaking [saturation] (% of dstqueue slots, 0..1 range).
 *
 * Some events will need rewriting, specify source- vobj id (can be EID but
 * should typically be a valid VID).
 */
struct arcan_frameserver;
void arcan_event_queuetransfer(
	struct arcan_evctx* dstqueue, struct arcan_evctx* srcqueue,
	enum ARCAN_EVENT_CATEGORY allowed, float saturation, struct arcan_frameserver*
);

/*
 * enqueue event into context, returns [ARCAN_OK] if successful or
 * [ARCAN_ERRC_OUT_SPACE]  if the context lacks a drain function and the queue
 * is full.
 */
int arcan_event_enqueue(struct arcan_evctx*, const struct arcan_event* const);

/*
 * if the event context has a drain function, forward the event straight to
 * the drain, if not, act as a normal arcan_event_enqueue.
 */
int arcan_event_denqueue(struct arcan_evctx*, const struct arcan_event* const);

/* global clock, milisecond resolution relative to epoch set during start */
int64_t arcan_frametime();

/*
 * Masking functions should only be needed for very special edge cases,
 * e.g. recovering from a scripting environment failure.
 */
void arcan_event_maskall(struct arcan_evctx*);
void arcan_event_clearmask(struct arcan_evctx*);
void arcan_event_setmask(struct arcan_evctx*, unsigned mask);

/*
 * It may be the case that a user wants to make sure the event layer ignores
 * certain devices (in constrast to the _BLOCKED state that is also possible)
 * or that some engine parts, like LED drivers, wants to instruct the
 * platform layer that a certain device is accounted for. To do that, we
 * maintain a blacklist as part of the protected 'arcan' key/value database
 * namespace, though the platform-event implementation need to explicitly
 * respect it.
 *
 * For USB- devices, idstr is a snprintf("%d:%d", (int)vid, (int)pid)
 */
void arcan_event_blacklist(const char* idstr);
bool arcan_event_blacklisted(const char* idstr);

/*
 * [DANGEROUS]
 * Lock and sweep the event queue to alter all events in category where
 * memcmp((ev+r_ofs), cmpbuf, r_b) match and then write w_b from buf to
 * ev+w_ofs.
 *
 * This is used to manually patch or rewrite events that need to be invalidated
 * after that they have been enqueued, primarily for EVENT_FRAMESERVER_*
 */
void arcan_event_repl(struct arcan_evctx* ctx, enum ARCAN_EVENT_CATEGORY cat,
	size_t r_ofs, size_t r_b, void* cmpbuf,
	size_t w_ofs, size_t w_b, void* w_buf
);

/*
 * [DANGEROUS]
 * used as part of trying to salvage external connections while resetting
 * audio/video/scripting contexts. This sweeps the "to be processed"
 * event-queue and removes all events that doesn't strictly come from external
 * sources or might otherwise leak state from previous context
 */
void arcan_event_purge();

/* Try to remove at most one event from the ingoing slot of the event
 * queue and put into *dst. returns 0 if there are no events to receive,
 * or 1 if an event was successfully dequeued. */
int arcan_event_poll(struct arcan_evctx*, struct arcan_event* dst);

/*
 * Try and cleanly close down device drivers and other platform specifics.
 * Any pending events are lost rather than processed.
 */
void arcan_event_deinit(struct arcan_evctx*);
#endif
