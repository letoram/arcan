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

#include "arcan_shmpage_interop.h"
#include "arcan_shmpage_event.h"

#define ARCAN_OK 0
#define ARCAN_ERRC_UNACCEPTED_STATE -1

/*
 * This implementation is a first refactor step to separate
 * the clutter of arcan_event (pulling in general, video, ...)
 * for the purpose of frameserver implementations.
 *
 * The main process has a slightly different implementation of
 * these functions, thus special care should be taken to ensure
 * that any behavioral changes are synchronized. 
 */

static inline int queue_used(arcan_evctx* dq)
{
	int rv = *(dq->front) > *(dq->back) ? dq->n_eventbuf - 
		*(dq->front) + *(dq->back) : *(dq->back) - *(dq->front);
	return rv;
}

static unsigned alloc_queuecell(arcan_evctx* ctx)
{
	unsigned rv = *(ctx->back);
	*(ctx->back) = ( *(ctx->back) + 1) % ctx->n_eventbuf;

	return rv;
}

arcan_event* arcan_event_poll(arcan_evctx* ctx, arcan_errc* status)
{
	arcan_event* rv = NULL;
	arcan_sem_timedwait(ctx->synch.external.shared, -1);

	*status = ARCAN_OK;
	if (*ctx->front != *ctx->back){
		rv = &ctx->eventbuf[ *ctx->front ];
		*ctx->front = (*ctx->front + 1) % ctx->n_eventbuf;
	}

	arcan_sem_post(ctx->synch.external.shared);
	return rv;
}

void arcan_event_enqueue(arcan_evctx* ctx, const arcan_event* src)
{
	int rtc = 1;

/* early-out mask-filter */
	if (!src || (src->category & ctx->mask_cat_inp)){
		return;
	}

retry:
	arcan_sem_timedwait(ctx->synch.external.shared, -1);
	if (ctx->lossless){
		if (ctx->n_eventbuf - queue_used(ctx) <= 1){
			arcan_sem_post(ctx->synch.external.shared);

/* 
 * Needlessly to say, this should *REALLY* be changed
 * for futexes or even using the event semaphore as a counter
 * (awaiting bencharking and tests from the "evilcore" 
 * before proceeding though) 
 */
			rtc *= 2;
			arcan_timesleep(rtc);

			goto retry;	
		}
	}

	unsigned ind = alloc_queuecell(ctx);
	arcan_event* dst = &ctx->eventbuf[ind];
	*dst = *src;
	dst->tickstamp = ctx->c_ticks;

	arcan_sem_post(ctx->synch.external.shared);
}

