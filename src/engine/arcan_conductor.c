/*
 * Copyright 2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the arcan source repository.
 * Reference: https://arcan-fe.com
 */
#include <stdint.h>
#include <stdlib.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_shmif.h"
#include "arcan_event.h"
#include "arcan_audio.h"
#include "arcan_frameserver.h"
#include "arcan_conductor.h"
#include "arcan_lua.h"
#include "arcan_video.h"

#include "../platform/platform.h"
#include "../platform/video_platform.h"

static uint64_t tick_count;

/*
 * the main problems to address:
 *
 * 1. resized- ack is gpu-state bound, contributing to a possible full
 * frame of latency on an ack request (same for segreq really but that
 * one is harder as it creates GPU resources)
 *
 * 2. PBO uploads aren't used to parallelize and we can't use fence
 * fds to figure out when it is safe to update again, we want to
 * push uploads for all frameservers and then wait for synch
 *
 * 3. we want to be able to have pinned buffer transfers even when we
 * can't shmmap in order to release vbuffers faster
 *
 * 4. we need to be able to specify priority loads in order to reduce
 * latency on a focus target
 *
 * 5. audio buffer transfers are rarely locked to the GPU (though
 * there are edge cases)
 *
 * 6. we want to reduce the number of external/ named resources to
 * zero or one (the connection socket)
 *
 * 7. we need more clever ways of dealing with dynamic - synch screens
 *
 * 8. we want the same synch- solution and setup work for all video
 * platforms, not repeat them in each.
 *
 * 9. we want to schedule the scripting VM gc passes so they happen
 * when we are busy waiting for displays
 *
 * 10. we want to schedule readbacks to happen while we are waiting
 * for synch to scanout
 *
 * 11. with all this in place, we can start making rendertarget processing
 * threaded - every time a vobj is visited, the interp. is either recalculated
 * for the specific thread (ouch) except for the primary attachment (owner),
 * though we might be able to do some funky atomics + spinlocks
 */

void arcan_conductor_lock_gpu(
	size_t gpu_id, int fence, arcan_gpu_lockhandler lockh)
{
/*
 * this interface needs some more thinking, but the callback chain will
 * be that video_synch -> lock_gpu[gpu_id, fence_fd] and a process callback
 * when there's data on the fence_fd (which might potentially call unlock)
 */
}

void arcan_conductor_release_gpu(size_t gpu_id)
{
}

void arcan_conductor_register_display(size_t gpu_id,
		size_t disp_id, enum synch_method method, float rate, arcan_vobj_id obj)
{
/* need to know which display and which vobj is needed to be updated in order
 * to fulfill the requirement of the display synch so that we can schedule it
 * accordingly, later the full DAG- would also be calculated here to resolve
 * which agp- stores are involved and if they have an affinity on a locked
 * GPU or not so that we can MT GPU updates */
}

void arcan_conductor_register_frameserver(struct arcan_frameserver* fsrv)
{
/*
 * spawn a monitor thread that checks the resized- tag,
 * later we should consolidate all the aready/vready/resized into one
 * and use the same synch- mechanism on both sides and kill the semaphores
 */
}

void arcan_conductor_deregister_frameserver(struct arcan_frameserver* fsrv)
{
/* just need to poke the bit used in the monitor thread */
}

extern struct arcan_luactx* main_lua_context;
static void process_event(arcan_event* ev, int drain)
{
/* [ mutex ]
 * can't perform while any of the frameservers are in a resizing state */
	arcan_lua_pushevent(main_lua_context, ev);
}

static arcan_tick_cb outcb;
static void conductor_cycle();
int arcan_conductor_run(arcan_tick_cb tick)
{
	arcan_evctx* evctx = arcan_event_defaultctx();
	outcb = tick;
	int exit_code;

	for(;;){
		arcan_video_pollfeed();
		arcan_audio_refresh();
		float frag = arcan_event_process(evctx, conductor_cycle);
		if (!arcan_event_feed(evctx, process_event, &exit_code))
			break;

/* these should be replaced with a platform_video_displaysynch(dispid) that
 * assumes the underlying vobj-id has already been updated so the draw-call
 * isn't set from the platform layer, and the preframe/postframe pulse thus
 * needs to be altered to provide a display-id */
		arcan_lua_callvoidfun(main_lua_context, "preframe_pulse", false, NULL);
		platform_video_synch(tick_count, frag, NULL, NULL);
		arcan_lua_callvoidfun(main_lua_context, "postframe_pulse", false, NULL);
		arcan_bench_register_frame();
	}

	outcb = NULL;
	return exit_code;
}

void conductor_cycle(int nticks)
{
	tick_count += nticks;
/* priority is always in maintaining logical clock and event processing */
	unsigned njobs;

/* start with lua as it is likely to incur changes
 * to what is supposed to be drawn */
	arcan_lua_tick(main_lua_context, nticks, tick_count);

	arcan_video_tick(nticks, &njobs);
	arcan_audio_tick(nticks);
	outcb(nticks);

	while(nticks--)
		arcan_mem_tick();
}


