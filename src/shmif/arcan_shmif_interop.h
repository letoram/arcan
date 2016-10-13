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

#ifndef HAVE_ARCAN_SHMIF_INTEROP
#define HAVE_ARCAN_SHMIF_INTEROP

/*
 * Version number works as tag and guard- bytes in the shared memory page, it
 * is set by arcan upon creation and verified along with the offset- cookie
 * during _integrity_check
 */
#define ASHMIF_VERSION_MAJOR 0
#define ASHMIF_VERSION_MINOR 9

#ifndef LOG
#define LOG(...) (fprintf(stderr, __VA_ARGS__))
#endif

#define SHMIF_PT_SIZE(ppcm, sz_mm) ((size_t)(\
	(((double)(sz_mm)) / 0.0352778) * \
	(((double)(ppcm)) / 28.346566) \
))

/*
 * For porting the shmpage interface, these functions need to be implemented
 * and pulled in, shouldn't be more complicated than mapping to the
 * corresponding platform/ functions.
 */
#ifndef PLATFORM_HEADER

#define BADFD -1
#include <sys/types.h>
#include <sys/stat.h>
#include <semaphore.h>
	typedef int file_handle;
	typedef pid_t process_handle;
	typedef sem_t* sem_handle;

long long int arcan_timemillis(void);
int arcan_sem_post(sem_handle sem);
file_handle arcan_fetchhandle(int insock, bool block);
bool arcan_pushhandle(int fd, int channel);
int arcan_sem_wait(sem_handle sem);
int arcan_sem_trywait(sem_handle sem);
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

/*
 * Duplicates a descriptor and set safe flags (e.g. CLOEXEC)
 * if [dstnum] is <= 0, it will ATTEMPT to duplicate to the specific number,
 * (though NOT GUARANTEED).
 *
 * Returns a valid descriptor or -1 on error (with errno set according
 * to the dup() call family.
 */
int arcan_shmif_dupfd(int fd, int dstnum, bool blocking);

/*
 * Part of auxiliary library, pulls in more dependencies and boiler-plate
 * for setting up accelerated graphics
 */
#ifdef WANT_ARCAN_SHMIF_HELPER

/*
 * Maintain both context and display setup. This is for cases where you don't
 * want to set up EGL or similar support yourself. For cases where you want to
 * do the EGL setup except for the NativeDisplay part, use _headless_egl.
 *
 * [Warning] stick to either _headless_setup OR _headless(_egl, vk), don't mix
 *
 */
enum shmifext_setup_status {
	SHHIFEXT_UNKNOWN = 0,
	SHMIFEXT_NO_API,
	SHMIFEXT_NO_DISPLAY,
	SHMIFEXT_NO_EGL,
	SHMIFEXT_NO_CONFIG,
	SHMIFEXT_NO_CONTEXT,
	SHMIFEXT_OK
};

enum shmifext_api {
	API_OPENGL = 0,
	API_GLES,
	API_VHK
};

struct arcan_shmifext_setup {
	uint8_t red, green, blue, alpha, depth;
	uint8_t api, major, minor;
};

struct arcan_shmifext_setup arcan_shmifext_headless_defaults();

enum shmifext_setup_status arcan_shmifext_headless_setup(
	struct arcan_shmif_cont* con,
	struct arcan_shmifext_setup arg);

/*
 * for use with the shmifext_headless_setup approach, try and find the
 * requested symbol within the context of the accelerated graphics backend
 */
void* arcan_shmifext_headless_lookup(
	struct arcan_shmif_cont* con, const char*);

/*
 * Uses lookupfun to get the function pointers needed, writes back matching
 * EGLNativeDisplayType into *display and tags *con as accelerated.
 * Can be called multiple times as response to DEVICE_NODE calls or to
 * retrieve the display associated with con
 */
bool arcan_shmifext_headless_egl(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag);

/*
 * For the corner cases where you need access to the display/surface/context
 * but don't want to detract from the _headless_setup
 */
bool arcan_shmifext_egl_meta(struct arcan_shmif_cont* con,
	uintptr_t* display, uintptr_t* surface, uintptr_t* context);

/*
 * Placeholder awaiting VK support
 */
bool arcan_shmifext_headless_vk(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag);

/*
 * Similar behavior to signalhandle, but any conversion from the texture id
 * in [tex_id] is handled internally in accordance with the last _headless_egl
 * call on [con]. Context refers to the EGLContext where [tex_id] is valid
 *
 * Returns -1 on handle- generation/passing failure, otherwise the number
 * of miliseconds (clamped to INT_MAX) that elapsed from signal to ack.
 */
int arcan_shmifext_eglsignal(struct arcan_shmif_cont*,
	uintptr_t context, int mask, uintptr_t tex_id, ...);

int arcan_shmifext_vksignal(struct arcan_shmif_cont*,
	uintptr_t context, int mask, uintptr_t tex_id, ...);
#endif

#endif
