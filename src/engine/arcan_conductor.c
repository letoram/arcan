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

void arcan_conductor_lock_gpu(size_t gpu_id)
{
}

void arcan_conductor_release_gpu(size_t gpu_id)
{
}

void arcan_conductor_register_frameserver(struct arcan_frameserver* fsrv)
{
}

void arcan_conductor_deregister_frameserver(struct arcan_frameserver* fsrv)
{
}

extern struct arcan_luactx* main_lua_context;
static void process_event(arcan_event* ev, int drain)
{
	arcan_lua_pushevent(main_lua_context, ev);
}

static void preframe()
{
	arcan_lua_callvoidfun(main_lua_context, "preframe_pulse", false, NULL);
}

static void postframe()
{
	arcan_lua_callvoidfun(main_lua_context, "postframe_pulse", false, NULL);
	arcan_bench_register_frame();
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
		platform_video_synch(tick_count, frag, preframe, postframe);
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


