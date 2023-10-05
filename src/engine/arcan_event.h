/*
 * Copyright Björn Ståhl
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
typedef bool (*arcan_event_handler)(arcan_event*, int);
void arcan_event_init(struct arcan_evctx*);
void arcan_event_setdrain(struct arcan_evctx*, arcan_event_handler);

/*
 * Time- keeping function, need to be pumped regularly (will take care of
 * polling input devices and maintain the pseudo-monotonic clock).
 * Returns the fraction of the next tick (useful for interpolation).
 */
float arcan_event_process(struct arcan_evctx*, arcan_tick_cb);

/* Add a polling source to the normal processing loop. This will not trigger on
 * errors, only on read/write capability. It is up to the caller to manually
 * remove the source if reading/writing from it indicates that the backing has
 * failed. When the level changes for the descriptor, an event will be pused in
 * the EVENT_SYSTEM_DATA_IN/EVENT_SYSTEM_DATA_OUT category, which is eligible
 * for being sent direct to drain (e.g. while GPUs are locked).
 *
 * Each unique descriptor is only allowed to be added once, subsequent calls
 * will only updated / modify the input/output mask and the otag, overriding
 * previously set states. */
bool arcan_event_add_source(
	struct arcan_evctx*, int fd, mode_t mode, intptr_t otag, bool mask);

/* Remove a source previously added through add_source. Will return true if
 * the source existed and set the last known otag in *out if provided. Since
 * the same descriptor can be registered multiple times (each with a different
 * mode) the mode specified should also match. */
bool arcan_event_del_source(
	struct arcan_evctx*, int fd, mode_t mode, intptr_t* out);

/* Work through the list of registered sources and queue events for the ones
 * that are readable/writable as EVENT_SYSTEM_DATA_IN/OUT. This is intended to
 * be run as part of the conductor scheduler. The internal queueing is
 * direct-to-drain. */
void arcan_event_poll_sources(struct arcan_evctx* ctx, int timeout);

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
 * If [saturation] is set to a negative value, the queuetransfer will be direct
 * to drain - meaning that the copy will instead go to the designated sink (Lua
 * VM) and only be queued if rejected by the sink (locking constraints).
 *
 * While this will increase throughput and lower latency, very few events gain
 * from that, and there is a number of subtle and dangerous edge cases.
 * Normally outbound events (from here to frameserver) outnumber inbound events
 * (from frameserver to here) by a large factor. The exception are protocol
 * bridges input device drivers and backpressure/stalled clients.
 *
 * This should be called with the reference frameserver in guarded mode, see
 * enter/leave in platform/fsrv_platform.h. If the function returns -1, this
 * guard needs to be activated and the failure treated as the initial guard
 * failure. If the function returns -2, it means that the frameserver died
 * during processing of one event in the queue and is expected to be freed.
 */
struct arcan_frameserver;
int arcan_event_queuetransfer(
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
 * the drain, if not (or the drain function rejects the event), act as a normal
 * arcan_event_enqueue.
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
 *
 * If [flush] is set to true, any pending events or monitored input sources
 * will be dropped.
 */
void arcan_event_deinit(struct arcan_evctx*, bool flush);
#endif
