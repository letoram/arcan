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

int arcan_event_poll(struct arcan_evctx* ctx, struct arcan_event* dst)
{
	assert(dst);

	if (*ctx->front == *ctx->back)
		return 0;

	*dst = ctx->eventbuf[ *ctx->front ];
	*ctx->front = (*ctx->front + 1) % ctx->eventbuf_sz;

	return 1;
}

int arcan_event_wait(struct arcan_evctx* ctx, struct arcan_event* dst)
{
	assert(dst);
	volatile int* ks = (volatile int*) ctx->synch.killswitch;

	while (*ctx->front == *ctx->back && *ks)
		arcan_sem_wait(ctx->synch.handle);
	
	return arcan_event_poll(ctx, dst);
}

int arcan_event_enqueue(arcan_evctx* ctx, const struct arcan_event* const src)
{
	assert(ctx);
/* child version doesn't use any masking */

	while ( ((*ctx->back + 1) % ctx->eventbuf_sz) == *ctx->front){
		arcan_sem_wait(ctx->synch.handle);
	}
	
	ctx->eventbuf[*ctx->back] = *src;
	*ctx->back = (*ctx->back + 1) % ctx->eventbuf_sz;

	return 1;
}

int arcan_event_tryenqueue(arcan_evctx* ctx, const arcan_event* const src)
{
	if (((*ctx->front + 1) % ctx->eventbuf_sz) == *ctx->back)
		return 0;	

	return arcan_event_enqueue(ctx, src);	
}

