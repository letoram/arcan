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

#ifndef _HAVE_ARCAN_SHMIF_INTEROP
#define _HAVE_ARCAN_SHMIF_INTEROP

#define ARCAN_VERSION_MAJOR 0
#define ARCAN_VERSION_MINOR 3 
#define ARCAN_VERSION_PATCH 2 

/* There is a limited amount of types that both arcan
 * and frameservers need to agree on. To limit namespaces
 * this header provides definitions that otherwise would've
 * resided in the platform subdirectories or as part of 
 * arcan_general.h */

#ifdef _WIN32
#include "platform/win32/platform.h"
#else
#define BADFD -1
#include <pthread.h>
#include <semaphore.h>

typedef int pipe_handle;
typedef int file_handle;
typedef pid_t process_handle;
typedef sem_t* sem_handle;
#endif

struct arcan_event;
struct arcan_evctx;

/*
 * For porting the shmpage interface, these functions need to be 
 * implemented and pulled in, shouldn't be more complicated than
 * mapping to the corresponding platform/ functions. 
 */
long long int arcan_timemillis();
void arcan_timesleep(unsigned long);

int arcan_sem_post(sem_handle sem);
int arcan_sem_unlink(sem_handle sem, char* key);
int arcan_sem_wait(sem_handle sem);
int arcan_sem_trywait(sem_handle sem);

typedef int8_t arcan_errc;
typedef long long arcan_vobj_id;
typedef int arcan_aobj_id;

/*
 * Try and dequeue the element in the front of the queue with (wait)
 * or without (poll) blocking execution. 
 * returns non-zero on success. 
 */
int arcan_event_poll(struct arcan_evctx*, struct arcan_event* dst);
int arcan_event_wait(
	struct arcan_evctx*, struct arcan_event* dst);

/*
 * Try and enqueue the element to the queue. If the context is 
 * set to lossless, enqueue may block, sleep (or spinlock).
 *
 * returns the number of FREE slots left on success or a negative
 * value on failure. The purpose of the try- approach is to let
 * the user distinguish between necessary and merely "helpful"
 * events (e.g. frame numbers, net ping-pongs etc.) 
 */
int arcan_event_enqueue(struct arcan_evctx*, 
	const struct arcan_event* const);

int arcan_event_tryenqueue(struct arcan_evctx*, 
	const struct arcan_event* const);

/* 
 * The following functions are simple lookup/unpack support functions
 * for argument strings usually passed on the command-line to a newly 
 * spawned frameserver in a simple (utf-8) key=value\tkey=value type format. 
 */ 
struct arg_arr {
	char* key;
	char* value;
};

/* take the input string and unpack it into an array of key-value pairs */
struct arg_arr* arg_unpack(const char*);

/*
 * return the value matching a certain key, 
 * if ind is larger than 0, it's the n-th result 
 * that will be stored in dst 
 */ 
bool arg_lookup(struct arg_arr* arr, const char* val, 
	unsigned short ind, const char** found);

void arg_cleanup(struct arg_arr*);
#endif

