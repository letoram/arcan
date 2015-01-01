/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <string.h>

#include "arcan_shmif.h"

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

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_lock(&ctx->synch.lock);
#endif

	if (*ctx->front == *ctx->back){
#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
		pthread_mutex_unlock(&ctx->synch.lock);
#endif
		return 0;
	}

	*dst = ctx->eventbuf[ *ctx->front ];
	*ctx->front = (*ctx->front + 1) % ctx->eventbuf_sz;

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

	return 1;
}

int arcan_event_wait(struct arcan_evctx* ctx, struct arcan_event* dst)
{
	assert(dst);
	volatile int* ks = (volatile int*) ctx->synch.killswitch;

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_lock(&ctx->synch.lock);
#endif

	while (*ctx->front == *ctx->back && *ks){
		arcan_sem_wait(ctx->synch.handle);
	}

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

	return arcan_event_poll(ctx, dst);
}

int arcan_event_enqueue(arcan_evctx* ctx, const struct arcan_event* const src)
{
	assert(ctx);
/* child version doesn't use any masking */

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_lock(&ctx->synch.lock);
#endif

	while ( ((*ctx->back + 1) % ctx->eventbuf_sz) == *ctx->front){
		LOG("arcan_event_enqueue(), going to sleep, eventqueue full\n");
		arcan_sem_wait(ctx->synch.handle);
	}

	ctx->eventbuf[*ctx->back] = *src;
	*ctx->back = (*ctx->back + 1) % ctx->eventbuf_sz;

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

	return 1;
}

int arcan_event_tryenqueue(arcan_evctx* ctx, const arcan_event* const src)
{
#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_lock(&ctx->synch.lock);
#endif

	if (((*ctx->front + 1) % ctx->eventbuf_sz) == *ctx->back){
#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

		return 0;
	}

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

	return arcan_event_enqueue(ctx, src);
}

