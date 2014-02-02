/* 
 Arcan Shared Memory Interface, Interoperability definitions

 Copyright (c) 2014, Bjorn Stahl
 All rights reserved.
 
 Redistribution and use in source and binary forms, 
 with or without modification, are permitted provided that the 
 following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice, 
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice, 
 this list of conditions and the following disclaimer in the documentation 
 and/or other materials provided with the distribution.
 
 3. Neither the name of the copyright holder nor the names of its contributors 
 may be used to endorse or promote products derived from this software without 
 specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, 
 THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE 
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, 
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF 
 THE POSSIBILITY OF SUCH DAMAGE.
*/

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>

#include "arcan_shmpage_if.h"

/*
 * This implementation is a first refactor step to separate
 * the clutter of arcan_event (pulling in general, video, ...)
 * for the purpose of frameserver implementations.
 *
 * The main process has a slightly different implementation of
 * these functions, thus special care should be taken to ensure
 * that any behavioral changes are synchronized.
 *
 * One of the big differences is that the main process has to
 * verify or clamp the front and back values as to not provide
 * an easy write/read from user-controllable offsets type
 * vulnerability.
 */

static inline int queue_used(arcan_evctx* dq)
{
	return (*dq->front > *dq->back) ? 
		(dq->eventbuf_sz - *dq->front + *dq->back) : (*dq->back - *dq->front);
}

static inline unsigned alloc_queuecell(arcan_evctx* ctx)
{
	unsigned rv = *ctx->back;
	*ctx->back = (*ctx->back + 1) % ctx->eventbuf_sz;
	return rv;
}

int arcan_event_poll(struct arcan_evctx* ctx, struct arcan_event* dst)
{
	assert(dst);

	if (ctx->front == ctx->back)
		return 0;

	*dst = ctx->eventbuf[ *ctx->front ];
	*ctx->front = (*ctx->front + 1) % ctx->eventbuf_sz;

	return 1;
}

int arcan_event_wait(struct arcan_evctx* ctx, struct arcan_event* dst)
{
	assert(dst);

	if (*ctx->front == *ctx->back){
#ifdef _DEBUG
		int value;
		assert(arcan_sem_value(
			ctx->synch.handle, &value) == 0 && value == 1);
#endif
		arcan_sem_wait(ctx->synch.handle);
	}
	
	return arcan_event_poll(ctx, dst);
}

int arcan_event_enqueue(arcan_evctx* ctx, const struct arcan_event* const src)
{
	assert(ctx);

/* child version doesn't use any masking */
	unsigned ind; 
	int rtc;
 
	rtc	= queue_used(ctx);

	while (rtc == ctx->eventbuf_sz){
/* we just sleep at the moment, the rational being that the parent
 * process should spend very little time actually processing events,
 * and if it's overloaded to the point that it cannot, the noisiest
 * children can slow down (particularly if the parent processes events
 * in a fair way, e.g. while(set_of_providers:gotevent)[queuetransfer(provider,n)])
 * rather than foreach(set_of_providers)queuetransfer(provider)) */
		arcan_timesleep(10);
		rtc	= queue_used(ctx);
	}
	
	ind = alloc_queuecell(ctx);

	arcan_event* dst = &ctx->eventbuf[ind];
	*dst = *src;

/* won't "really" matter here as the parent,
 * when multiplexing events on the main-queue,
 * re-timestamps it to local time 	
 * dst->tickstamp = ctx->c_ticks;
*/
	return ctx->eventbuf_sz - rtc - 1;
}

int arcan_event_tryenqueue(arcan_evctx* ctx, const arcan_event* const src)
{
	int rtc = queue_used(ctx);
	if (rtc == ctx->eventbuf_sz)
		return 0;

	return arcan_event_enqueue(ctx, src);	
}

