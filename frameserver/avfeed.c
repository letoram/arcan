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

#include "../arcan_shmpage_if.h"
#include "avfeed.h"
#include "frameserver.h"

/*
 * Quick skeleton to map up a audio/video/input 
 * source to an arcan frameserver along with some helpers.
 */
void arcan_frameserver_avfeed_run(const char* resource, const char* keyfile)
{
/*	struct arg_arr* args = arg_unpack(resource); */
	struct frameserver_shmcont shms = frameserver_getshm(keyfile, true);
	struct arcan_evctx inevq, outevq;
	struct arcan_event ev;

/* setup the semaphores, vready flag + semaphore toggle required */
	if (-1 == arcan_sem_wait(shms.asem) || -1 == arcan_sem_wait(shms.vsem))
		return;

	frameserver_shmpage_setevqs(shms.addr, shms.esem, &inevq, &outevq, false);
	int startw = 320, starth = 200;

	if (!frameserver_shmpage_resize(&shms, startw, starth)){
		LOG("arcan_frameserver(decode) shmpage setup, resize failed\n");
		return;
	}
	
	uint32_t* vidp;
	uint16_t* audp;

	frameserver_shmpage_calcofs(shms.addr, (uint8_t**) &vidp, (uint8_t**) &audp);
	while(1){
		while (1 == arcan_event_poll(&inevq, &ev)){
/*
 *	event dispatch loop, look at shmpage interop,
 *	valid categories here should (at least)
 *	be EVENT_SYSTEM, EVENT_IO, EVENT_TARGET
 */ 
		}

	}
}
