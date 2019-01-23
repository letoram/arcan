/*
 * Copyright 2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the arcan source repository.
 * Reference: https://arcan-fe.com
 * Description: The conductor interface is used to coordinate scheduling
 * between the various subsystem refreshments, enforcing synchronization
 * strategy to optimize for throughput, latency or energy efficiency.
 */

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
 * invoke the lockhandler callback which [may] release the gpu
 */
typedef void (*arcan_gpu_lockhandler)(size_t, int);
void arcan_conductor_lock_gpu(size_t gpu_id, int fence, arcan_gpu_lockhandler);

/* [called from platform ]
 * Allow processing operations bound to gpu_id to be scheduled, gpu_ids
 * as part of the argument are matched against the bitmask vstore_t used by
 * various producers and consumers */
void arcan_conductor_release_gpu(size_t gpu_id);

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

#ifndef VIDEO_PLATFORM_IMPL
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
