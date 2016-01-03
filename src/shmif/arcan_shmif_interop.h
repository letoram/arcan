/*
 Arcan Shared Memory Interface, Interoperability definitions

 Copyright (c) 2014-2016, Bjorn Stahl
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

/*
 * Version number works as tag and guard- bytes in the shared memory page, it
 * is set by arcan upon creation and verified along with the offset- cookie
 * during _integrity_check
 */
#define ASHMIF_VERSION_MAJOR 0
#define ASHMIF_VERSION_MINOR 6

#ifndef LOG
#define LOG(...) (fprintf(stderr, __VA_ARGS__))
#endif


/*
 * For porting the shmpage interface, these functions need to be implemented
 * and pulled in, shouldn't be more complicated than mapping to the
 * corresponding platform/ functions.
 */
#ifndef PLATFORM_HEADER

#ifdef WIN32
#define INVALID_HANDLE_VALUE
	typedef HANDLE file_handle;
	typedef HANDLE sem_handle;
	typedef void* process_handle;
#else
#define BADFD -1
#include <sys/types.h>
#include <sys/stat.h>
#include <semaphore.h>
	typedef int file_handle;
	typedef pid_t process_handle;
	typedef sem_t* sem_handle;
#endif

long long int arcan_timemillis(void);
int arcan_sem_post(sem_handle sem);
file_handle arcan_fetchhandle(int insock, bool block);
bool arcan_pushhandle(int fd, int channel);
int arcan_sem_wait(sem_handle sem);
#endif

struct arcan_shmif_cont;
struct arcan_event;

/*
 * Note the different semantics in return- values for _poll versus _wait
 */

/*
 * _poll will return as soon as possible with one of the following values:
 *  > 0 when there are incoming events available,
 *  = 0 when there are no incoming events available,
 *  < 0 when the shmif_cont is unable to process events (terminal state)
 */
int arcan_shmif_poll(struct arcan_shmif_cont*, struct arcan_event* dst);

/*
 * _wait will block an unspecified time and return:
 * !0 when an event was successfully dequeued and placed in *dst
 *  0 when the shmif_cont is unable to process events (terminal state)
 */
int arcan_shmif_wait(struct arcan_shmif_cont*, struct arcan_event* dst);

/*
 * Try and enqueue the element to the queue. If the context is set to lossless,
 * enqueue may block, sleep (or spinlock).
 *
 * returns the number of FREE slots left on success or a negative value on
 * failure. The purpose of the try- approach is to let the user distinguish
 * between necessary and merely "helpful" events (e.g. frame numbers, net
 * ping-pongs etc.)
 *
 * These methods are thread-safe if and only if ARCAN_SHMIF_THREADSAFE_QUEUE
 * has been defined at build-time and not during a pending resize operation.
 */
int arcan_shmif_enqueue(struct arcan_shmif_cont*,
	const struct arcan_event* const);

int arcan_shmif_tryenqueue(struct arcan_shmif_cont*,
	const struct arcan_event* const);

/*
 * Provide a text representation useful for logging, tracing and debugging
 * purposes. If dbuf is NULL, a static buffer will be used (so for
 * threadsafety, provide your own).
 */
const char* arcan_shmif_eventstr(
	struct arcan_event* aev, char* dbuf, size_t dsz);

/*
 * Resolve implementation- defined connection connection path based on a
 * suggested key. Returns -num if the resolved path couldn't fit in dsz (with
 * abs(num) indicating the number of truncated bytes) and number of characters
 * (excluding NULL) written to dst.
 */
int arcan_shmif_resolve_connpath(
	const char* key, char* dst, size_t dsz);

/*
 * calculates a hash of the layout of the shmpage in order to detect subtle
 * compiler mismatches etc.
 */
uint64_t arcan_shmif_cookie(void);

/*
 * The following functions are simple lookup/unpack support functions for
 * argument strings usually passed on the command-line to a newly spawned
 * frameserver in a simple (utf-8) key=value\tkey=value type format.
 */
struct arg_arr {
	char* key;
	char* value;
};

/* take the input string and unpack it into an array of key-value pairs */
struct arg_arr* arg_unpack(const char*);

/*
 * return the value matching a certain key, if ind is larger than 0, it's the
 * n-th result that will be stored in dst
 */
bool arg_lookup(struct arg_arr* arr, const char* val,
	unsigned short ind, const char** found);

void arg_cleanup(struct arg_arr*);
#endif

