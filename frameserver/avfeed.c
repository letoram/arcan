/* 
 Arcan AVFeed Frameserver example 
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
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/types.h>
#include <pthread.h>

#include <arcan_shmif.h>
#include "frameserver.h"

static void update_frame(uint32_t* cptr, 
	struct arcan_shmif_cont* shms, uint32_t val)
{
	int np = shms->addr->w * shms->addr->h;
	for (int i = 0; i < np; i++)
		*cptr++ = val; 

	printf("update: %d\n", val);
	arcan_shmif_signal(shms, SHMIF_SIGVID);
}

struct seginf {
	struct arcan_evctx inevq, outevq;
	struct arcan_event ev;
	struct arcan_shmif_cont shms;
	uint32_t* vidp;
	uint16_t* audp;
};

static void* segthread(void* arg)
{
	struct seginf* seg = (struct seginf*) arg;
	uint8_t green = 0;
	
	arcan_shmif_resize(&seg->shms, 320, 200);

	while(seg->shms.addr->dms){
		arcan_event ev;
		printf("waiting for events\n");
		while(1 == arcan_event_wait(&seg->inevq, &ev)){
			printf("got event\n");
			if (ev.category == EVENT_TARGET && 
				ev.kind == TARGET_COMMAND_EXIT){
				printf("parent requested termination\n");
				update_frame(seg->vidp, &seg->shms, 0xffffff00);
				return NULL;
			}
			update_frame(seg->vidp, &seg->shms, 0xff000000 | (green++ << 8));
		}
	}

	return NULL;
}

static void mapseg(int evfd, const char* key)
{
	struct arcan_shmif_cont shms = arcan_shmif_acquire(
		key, SHMIF_INPUT, true, true 
	);

	struct seginf* newseg = malloc(sizeof(struct seginf));

	pthread_t thr; 
	arcan_shmif_calcofs(shms.addr, (uint8_t**) &newseg->vidp, 
		(uint8_t**) &newseg->audp);
	newseg->shms = shms;
	arcan_shmif_setevqs(shms.addr, shms.esem, 
		&newseg->inevq, &newseg->outevq, false);

	pthread_create(&thr, NULL, segthread, newseg);
}

/*
 * Quick skeleton to map up a audio/video/input 
 * source to an arcan frameserver along with some helpers.
 */
void arcan_frameserver_avfeed_run(const char* resource, const char* keyfile)
{
/*	struct arg_arr* args = arg_unpack(resource); */
	struct arcan_shmif_cont shms = arcan_shmif_acquire(
		keyfile, SHMIF_INPUT, true, false);

	struct arcan_evctx inevq, outevq;
	struct arcan_event ev;

	arcan_shmif_setevqs(shms.addr, shms.esem, &inevq, &outevq, false);

	if (!arcan_shmif_resize(&shms, 320, 200)){
		LOG("arcan_frameserver(decode) shmpage setup, resize failed\n");
		return;
	}
	
	uint32_t* vidp;
	uint16_t* audp;

	arcan_shmif_calcofs(shms.addr, (uint8_t**) &vidp, (uint8_t**) &audp);
	update_frame(vidp, &shms, 0xffffffff);

/*
 * request a new segment
 */
	ev.category = EVENT_EXTERNAL;
	ev.kind = EVENT_EXTERNAL_NOTICE_SEGREQ;
	arcan_event_enqueue(&outevq, &ev);

	int lastfd;

	while(1){
		while (1 == arcan_event_wait(&inevq, &ev)){
			if (ev.category == EVENT_TARGET){
				if (ev.kind == TARGET_COMMAND_FDTRANSFER){
					lastfd = frameserver_readhandle(&ev);
					printf("got handle (for new event transfer)\n");
				}
			}
			if (ev.kind == TARGET_COMMAND_NEWSEGMENT){	
				printf("new segment ready, key: %s\n", ev.data.target.message);	
				mapseg(lastfd, ev.data.target.message);
			}
			if (ev.kind == TARGET_COMMAND_EXIT){
				printf("parent requested termination, leaving.\n");
				break;
			}
			else {
				static int red;
				update_frame(vidp, &shms, 0xff000000 | red++);
			}
/*
 *	event dispatch loop, look at shmpage interop,
 *	valid categories here should (at least)
 *	be EVENT_SYSTEM, EVENT_IO, EVENT_TARGET
 */ 
		}
	}
}
