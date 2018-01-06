/*
 * Copyright 2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the arcan source repository.
 * Reference: https://arcan-fe.com
 * Description: The conductor interface is used to coordinate scheduling
 * between the various subsystem refreshments, enforcing synchronization
 * strategy to optimize for throughput, latency or energy efficiency.
 */

/* Main processing loop, takes care of invoking the scripting VM, synching
 * display updates and so on. */
int arcan_conductor_run(arcan_tick_cb cb);

/* Allow processing operations bound to gpu_id to be scheduled, gpu_ids
 * as part of the argument are matched against the bitmask vstore_t used by
 * various producers and consumers */
void arcan_conductor_release_gpu(size_t gpu_id);

/* Prevent processing operations bound to gpu_id from being scheduled or
 * otherwise modified */
void arcan_conductor_lock_gpu(size_t gpu_id);

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

