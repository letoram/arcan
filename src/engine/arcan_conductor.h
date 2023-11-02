/*
 * Copyright 2018-2020, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the arcan source repository.
 * Reference: https://arcan-fe.com
 * Description: The conductor interface is used to coordinate scheduling
 * between the various subsystem refreshments, enforcing synchronization
 * strategy to optimize for throughput, latency or energy efficiency.
 */
#ifndef HAVE_ARCAN_CONDUCTOR
#define HAVE_ARCAN_CONDUCTOR

enum synch_method {
	SYNCH_NONE = 0,
	SYNCH_STATIC = 1,
	SYNCH_DYNAMIC = 2 /* VFR */
};

#ifndef VIDEO_PLATFORM_IMPL
/* Main processing loop, takes care of invoking the scripting VM, synching
 * display updates and so on. */
int arcan_conductor_run(arcan_tick_cb cb);
#endif

/* [ called from platform ] */
void arcan_conductor_enable_watchdog();
void arcan_conductor_toggle_watchdog();

/* will return true after one complete event-flush -> scanout cycle
 * has been completed, this is a test heuristic to determine if the
 * platform has gotten stuck in some recoverable state. */
bool arcan_conductor_valid_cycle();

/* [ called from platform ]
 * Specify the relationship between display, gpu, synch and object - displays
 * are never 'lost' though they can be disabled with a bad vobj. */
void arcan_conductor_register_display(size_t gpu_id,
		size_t disp_id, enum synch_method method, float rate, arcan_vobj_id obj);

/* [ called from platform ]
 * Release a previously registered display and gpu pairing */
void arcan_conductor_release_display(size_t gpu_id, size_t disp_id);

/* [ called from platform ]
 * mark GPU as locked and add [fence] to pollset, when there's data on fence,
 * invoke the lockhandler callback which [may] release the gpu.
 */
typedef void (*arcan_gpu_lockhandler)(size_t, int);
void arcan_conductor_lock_gpu(size_t gpu_id, int fence, arcan_gpu_lockhandler);

/* [called from platform ]
 * Allow processing operations bound to gpu_id to be scheduled, gpu_ids
 * as part of the argument are matched against the bitmask vstore_t used by
 * various producers and consumers */
void arcan_conductor_release_gpu(size_t gpu_id);

/* Return a bitmap of the GPUs that are currently in a locked state.
 * This may need to be queried in order to determine if an event can be
 * processed without altering GPU state */
size_t arcan_conductor_gpus_locked();

/*
 * Return a list of available synch-options that can be used as input to
 * arcan_conductor_setsynch. These strings are user-presentable.
 */
const char** arcan_conductor_synchopts();

/* [called from platform]
 *
 * Used on platforms that have internal synch-control and can hand over
 * some control during 'waiting for agp-/ gpu- release'. Is used to
 * perform downtime maintenance (GC, polling clients, ...)
 *
 * [disps] refers to a set of displays that we are waiting for synch ack
 * on, along with possible poll descriptors or other triggers. This can
 * be empty if the platform has its own mechanism for poll / select like
 * behavior.
 *
 * If returned -1, the synch to the display isn't interesting (non-
 * display driven processing modes) and the platform shouldn't keep
 * waiting.
 *
 * Otherwise it returns the number of ms that the platform could wait
 * before yielding again (if, for instance, the pollset wasn't considered)
 */
struct conductor_display {
	ssize_t refresh;
	int fd;
};
int arcan_conductor_yield(struct conductor_display* disps, size_t pset_count);

/*
 * [called from platform]
 * Provide a time relative to now to treat as the next display synchronization
 * deadline. This act as a complement or alternative to register_display. The
 * reason for the split is that not all platforms and display configurations
 * can actually provide either type of information accurately.
 *
 * The choice of uint8_t is to protect against calculation mistakes in some
 * platform delaying everything indefinitely
 */
void arcan_conductor_deadline(uint8_t next_deadline_ms);

/*
 * Switch the synchronization strategy to a string reference available in
 * synchopts, if no such string is found, the current strategy will remain.
 */
void arcan_conductor_setsynch(const char* arg);

/*
 * [called from platform]
 *
 * This can occur when the platform needs to lock GPU resources but has no
 * access to better display feedback control than a rough estimate as to how
 * long the synch should take. It is used as an artificial constraint when
 * running inside another display system, and when operating 'headless'.
 */
void arcan_conductor_fakesynch(uint8_t left_ms);

#ifndef VIDEO_PLATFORM_IMPL
int arcan_conductor_reset_count(bool step);

/* Update the priority target to match the specified frameserver. This
 * means that heuristics driving synchronization will be biased towards
 * letting the specific fsrv align synchronization - if the synchronization
 * strategy so permits */
void arcan_conductor_focus(struct arcan_frameserver* fsrv);

/* add a frameserver to the set of external data sources that should be
 * monitored for transfer requests and resize/renegotiation, invoked when a
 * frameserver structure is built and activated */
void arcan_conductor_register_frameserver(struct arcan_frameserver* fsrv);

/* remove a frameserver from the processing set, typically only needed if
 * all processing on the frameserver should be suspended or as part of the
 * deallocation sequence */
void arcan_conductor_deregister_frameserver(struct arcan_frameserver* fsrv);
#endif
#endif
