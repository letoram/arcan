/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <pthread.h>
#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <errno.h>
#include <math.h>
#include <assert.h>
#include <signal.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_event.h"
#include "arcan_framequeue.h"
#include "arcan_frameserver_backend.h"

static int64_t arcan_last_frametime = 0;
static int64_t arcan_tickofset = 0;

typedef struct queue_cell queue_cell;

static arcan_event eventbuf[ARCAN_EVENT_QUEUE_LIM];
static unsigned eventfront = 0, eventback = 0;

static struct arcan_evctx default_evctx = {
	.eventbuf = eventbuf,
	.n_eventbuf = ARCAN_EVENT_QUEUE_LIM,
	.front = &eventfront,
	.back  = &eventback,
	.local = true,
	.lossless = false
};

arcan_evctx* arcan_event_defaultctx(){
	return &default_evctx;
}

static unsigned alloc_queuecell(arcan_evctx* ctx)
{
	unsigned rv = *(ctx->back);
	*(ctx->back) = ( *(ctx->back) + 1) % ctx->n_eventbuf;

	return rv;
}

static inline bool lock_local(arcan_evctx* ctx)
{
	pthread_mutex_lock(&ctx->synch.local);
	return true;
}

static inline bool lock_shared(arcan_evctx* ctx)
{
	if (ctx->synch.external.killswitch){
		if (-1 == arcan_sem_timedwait(ctx->synch.external.shared, 
			DEFAULT_EVENT_TIMEOUT)){
			arcan_frameserver_free( (arcan_frameserver*) 
				ctx->synch.external.killswitch, false );
			ctx->synch.external.killswitch = NULL;

			return false;
		}
	}
	else
		arcan_sem_timedwait(ctx->synch.external.shared, -1);

	return true;
}

static inline bool unlock_local(arcan_evctx* ctx)
{
	pthread_mutex_unlock(&ctx->synch.local);
	return true;
}

static inline bool unlock_shared(arcan_evctx* ctx)
{
	arcan_sem_post(ctx->synch.external.shared);
	return true;
}

static inline bool LOCK(arcan_evctx* ctx)
{
	return ctx->local ? lock_local(ctx) : lock_shared(ctx);
}

static inline bool UNLOCK(arcan_evctx* ctx)
{
	return ctx->local ? unlock_local(ctx) : unlock_shared(ctx);
}

/* check queue for event, ignores mask */
arcan_event* arcan_event_poll(arcan_evctx* ctx, arcan_errc* status)
{
	arcan_event* rv = NULL;

		if (!LOCK(ctx)){
			*status = ARCAN_ERRC_UNACCEPTED_STATE; /* possibly dead frameserver */
			return NULL;
		}

		*status = ARCAN_OK;
		if (*ctx->front != *ctx->back){
			rv = &ctx->eventbuf[ *ctx->front ];
			*ctx->front = (*ctx->front + 1) % ctx->n_eventbuf;
		}

	UNLOCK(ctx);
	return rv;
}

void arcan_event_maskall(arcan_evctx* ctx){
	if ( LOCK(ctx) ){
		ctx->mask_cat_inp = 0xffffffff;
		UNLOCK(ctx);
	}
}

void arcan_event_clearmask(arcan_evctx* ctx){
	if ( LOCK(ctx) ){
		ctx->mask_cat_inp = 0;
	UNLOCK(ctx);
	}
}

void arcan_event_setmask(arcan_evctx* ctx, uint32_t mask){
	if (LOCK(ctx)){
		ctx->mask_cat_inp = mask;
		UNLOCK(ctx);
	}
}

/* drop the specified index and compact everything to the right of it,
 * assumes the context is already locked, so for large event queues etc.
 * this is subpar */
static void drop_event(arcan_evctx* ctx, unsigned index)
{
	unsigned current  = (index + 1) % ctx->n_eventbuf;
	unsigned previous = index;

/* compact left until we reach the end, back is actually
 * one after the last cell in use */
	while (current != *(ctx->back)){
		memcpy( &ctx->eventbuf[ previous ], &ctx->eventbuf[ current ], 
			sizeof(arcan_event) );
		previous = current;
		current  = (index + 1) % ctx->n_eventbuf;
	}

	*(ctx->back) = previous;
}

/*
 * this implementation is pretty naive and expensive on a large/filled queue,
 * partly because this feature was added as an afterthought and the underlying
 * datastructure isn't optimal for the use, should have been linked or 
 * double-linked 
 */
void arcan_event_erase_vobj(arcan_evctx* ctx, 
	enum ARCAN_EVENT_CATEGORY category, arcan_vobj_id source)
{
	unsigned elem = *(ctx->front);

/* ignore unsupported categories */
	if ( !(category == EVENT_VIDEO || category == EVENT_FRAMESERVER) )
		return;

	if (LOCK(ctx)){

		while(elem != *(ctx->back)){
			bool match = false;

			switch (ctx->eventbuf[elem].category){
			case EVENT_VIDEO: match = source == 
				ctx->eventbuf[elem].data.video.source; 
			break;
			case EVENT_FRAMESERVER: match = source == 
				ctx->eventbuf[elem].data.frameserver.video; 
			break;
			}

/* slide only if the cell shouldn't be deleted, 
 * otherwise it'll be replaced with the next one in line */
			if (match){
				drop_event(ctx, elem);
			}
			else
				elem = (elem + 1) % ctx->n_eventbuf;
		}

		UNLOCK(ctx);
	}
}

static inline int queue_used(arcan_evctx* dq)
{
	int rv = *(dq->front) > *(dq->back) ? dq->n_eventbuf - 
		*(dq->front) + *(dq->back) : *(dq->back) - *(dq->front);
	return rv;
}

/* enqueue to current context considering input-masking,
 * unless label is set, assign one based on what kind of event it is */
void arcan_event_enqueue(arcan_evctx* ctx, const arcan_event* src)
{
	int rtc = 1;

/* early-out mask-filter */
	if (!src || (src->category & ctx->mask_cat_inp)){
		return;
	}

retry:

	if (LOCK(ctx)){
		if (ctx->lossless){
			if (ctx->n_eventbuf - queue_used(ctx) <= 1){
				UNLOCK(ctx);
/* futex or other sleep mechanic, 
 * or use the synch as a counting semaphore */	
				rtc *= 2;
				arcan_timesleep(rtc);

				goto retry;	
			}
		}

		unsigned ind = alloc_queuecell(ctx);
		arcan_event* dst = &ctx->eventbuf[ind];
		*dst = *src;
		dst->tickstamp = ctx->c_ticks;

		UNLOCK(ctx);
	}
}

void arcan_event_queuetransfer(arcan_evctx* dstqueue, arcan_evctx* srcqueue, 
	enum ARCAN_EVENT_CATEGORY allowed, float saturation, arcan_vobj_id source)
{
	if (!srcqueue || !dstqueue || (srcqueue && !srcqueue->front) 
		|| (srcqueue && !srcqueue->back))
		return;

	saturation = (saturation > 1.0 ? 1.0 : saturation < 0.5 ? 0.5 : saturation);

	while ( srcqueue->front && *srcqueue->front != *srcqueue->back &&
			floor((float)dstqueue->n_eventbuf * saturation) > queue_used(dstqueue) ){

		arcan_errc status;
		arcan_event* ev = arcan_event_poll(srcqueue, &status);
	
		if (status != ARCAN_OK)
			break;
		
		if (ev && (ev->category & allowed) > 0 ){
			if (ev->category == EVENT_EXTERNAL)
				ev->data.external.source = source;

			else if (ev->category == EVENT_NET){
				ev->data.network.source = source;
			}

			arcan_event_enqueue(dstqueue, ev);
		}
	}

}

extern void platform_key_repeat(arcan_evctx* ctx, unsigned rate);
void arcan_event_keyrepeat(arcan_evctx* ctx, unsigned rate)
{
	if (LOCK(ctx)){
		platform_key_repeat(ctx, rate);
		UNLOCK(ctx);
	}
}

int64_t arcan_frametime()
{
	return arcan_last_frametime - arcan_tickofset;
}

/* the main usage case is simply to alternate between process and poll 
 * after a scene has been setup */
extern void platform_event_process(arcan_evctx* ctx);
float arcan_event_process(arcan_evctx* ctx, unsigned* dtick)
{
	static const int rebase_timer_threshold = ARCAN_TIMER_TICK * 1000;

	arcan_last_frametime = arcan_timemillis();
	unsigned delta  = arcan_last_frametime - ctx->c_ticks;

/*
 * compensate for a massive stall, non-monotonic clock
 * or first time initialization 
 */
	if (ctx->c_ticks == 0 || delta == 0 || delta > rebase_timer_threshold){
		ctx->c_ticks = arcan_last_frametime;
		delta = 1;
	}
	
	unsigned nticks = delta / ARCAN_TIMER_TICK;
	float fragment = ((float)(delta % ARCAN_TIMER_TICK) + 0.0001) /
		(float) ARCAN_TIMER_TICK;

	if (nticks){
		arcan_event newevent = {.category = EVENT_TIMER, 
			.kind = 0, 
			.data.timer.pulse_count = nticks
		};

		ctx->c_ticks += nticks * ARCAN_TIMER_TICK;
		arcan_event_enqueue(ctx, &newevent);
	}

	*dtick = nticks;
	platform_event_process(ctx);

	return fragment;
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

extern void platform_event_deinit(arcan_evctx* ctx);
void arcan_event_deinit(arcan_evctx* ctx)
{
	platform_event_deinit(ctx);
	eventfront = eventback = 0;
}

extern void platform_event_init(arcan_evctx* ctx);
void arcan_event_init(arcan_evctx* ctx)
{
/*
 * non-local (i.e. shmpage resident) event queues has a different 
 * init approach (see frameserver_shmpage.c) 
 */
	if (!ctx->local){
		return;
	}

	pthread_mutex_init(&ctx->synch.local, NULL);
	platform_event_init(ctx);

 	arcan_tickofset = arcan_timemillis();
}

extern void platform_device_lock(int lockdev, bool lockstate);
void arcan_device_lock(int lockdev, bool lockstate)
{
    platform_device_lock(lockdev, lockstate);
}

