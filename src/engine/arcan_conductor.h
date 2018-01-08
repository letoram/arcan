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
	SYNCH_DYNAMIC = 2
};

/* Main processing loop, takes care of invoking the scripting VM, synching
 * display updates and so on. */
int arcan_conductor_run(arcan_tick_cb cb);

/* [ called from platform ]
 * Specify the relationship between display, gpu, synch and object - displays
 * are never 'lost' though they can be disabled with a bad vobj. */
void arcan_conductor_register_display(size_t gpu_id,
		size_t disp_id, enum synch_method method, float rate, arcan_vobj_id obj);

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

/* Update the priority target to match the specified frameserver. This
 * means that heuristics driving synchronization will be biased towards
 * letting the specific fsrv align synchronization - if the synchronization
 * strategy so permits */
void arcan_frameserver_priority(struct arcan_frameserver* fsrv);

/* add a frameserver to the set of external data sources that should be
 * monitored for transfer requests and resize/renegotiation, invoked when a
 * frameserver structure is built and activated */
void arcan_conductor_register_frameserver(struct arcan_frameserver* fsrv);

/* remove a frameserver from the processing set, typically only needed if
 * all processing on the frameserver should be suspended or as part of the
 * deallocation sequence */
void arcan_conductor_deregister_frameserver(struct arcan_frameserver* fsrv);

