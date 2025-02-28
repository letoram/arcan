#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <limits.h>
#include <stdio.h>

#include "arcan_shmif.h"
#include "shmif_platform.h"
#include "arcan_shmif_event.h"

void shmif_platform_setevqs(
	struct arcan_shmif_page* dst,
	sem_t* esem,
	struct arcan_evctx* inq, struct arcan_evctx* outq
)
{
	inq->synch.synch = &dst->esync;
	inq->synch.killswitch = &dst->dms;
	outq->synch.killswitch = &dst->dms;

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
	if (!inq->synch.init){
		inq->synch.init = true;
		pthread_mutex_init(&inq->synch.lock, NULL);
	}
	if (!outq->synch.init){
		outq->synch.init = true;
		pthread_mutex_init(&outq->synch.lock, NULL);
	}
#endif

	inq->local = false;
	inq->eventbuf = dst->childevq.evqueue;
	inq->front = &dst->childevq.front;
	inq->back  = &dst->childevq.back;
	inq->eventbuf_sz = PP_QUEUE_SZ;

	outq->local =false;
	outq->eventbuf = dst->parentevq.evqueue;
	outq->front = &dst->parentevq.front;
	outq->back  = &dst->parentevq.back;
	outq->eventbuf_sz = PP_QUEUE_SZ;
}
