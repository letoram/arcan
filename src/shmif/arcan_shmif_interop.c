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
#include <errno.h>

#include "arcan_shmif.h"

#ifndef WIN32
#include <sys/types.h>
#include <sys/socket.h>
#endif

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

int arcan_shmif_poll(struct arcan_shmif_cont* c, struct arcan_event* dst)
{
	assert(dst);
	assert(c);
	struct arcan_evctx* ctx = &c->inev;

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

int arcan_shmif_wait(struct arcan_shmif_cont* c, struct arcan_event* dst)
{
	assert(c);
	assert(dst);
	struct arcan_evctx* ctx = &c->inev;
	volatile int* ks = (volatile int*) ctx->synch.killswitch;

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_lock(&ctx->synch.lock);
#endif

/*
 * this is currently wrong(memory coherency..) and should be re-written
 * using proper C11 atomics had we had decent mechanics for it. Doing
 * this correctly costs more than what it is currently worth, particularly
 * due to the pending update in event serialization.
 */

	while (*ctx->front == *ctx->back && *ks){
#ifdef _WIN32
		arcan_sem_wait(ctx->synch.handle);
#else
		arcan_sem_trywait(ctx->synch.handle);
		int num = 0;
		recv(c->dpipe, &num, sizeof(int), 0);
#endif
	}

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	pthread_mutex_unlock(&ctx->synch.lock);
#endif

	return arcan_shmif_poll(c, dst);
}

int arcan_shmif_enqueue(struct arcan_shmif_cont* c,
	const struct arcan_event* const src)
{
	assert(c);
	struct arcan_evctx* ctx = &c->outev;

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

int arcan_shmif_tryenqueue(
	struct arcan_shmif_cont* c, const arcan_event* const src)
{
	assert(c);
	struct arcan_evctx* ctx = &c->outev;

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

	return arcan_shmif_enqueue(c, src);
}

