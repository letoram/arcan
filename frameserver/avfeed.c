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

#include <arcan_shmif.h>
#include "frameserver.h"

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
	int startw = 320, starth = 200;

	if (!arcan_shmif_resize(&shms, startw, starth)){
		LOG("arcan_frameserver(decode) shmpage setup, resize failed\n");
		return;
	}
	
	uint32_t* vidp;
	uint16_t* audp;

	arcan_shmif_calcofs(shms.addr, (uint8_t**) &vidp, (uint8_t**) &audp);
	uint32_t* cptr = vidp;
	for (int i = 0; i < starth * startw; i++)
		*cptr++ = 0xff000000;
	arcan_shmif_signal(&shms, SHMIF_SIGVID);

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
