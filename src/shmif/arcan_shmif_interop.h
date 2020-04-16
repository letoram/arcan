/*
 Arcan Shared Memory Interface, Interoperability definitions

 Copyright (c) 2014-2018, Bjorn Stahl
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
#define ASHMIF_VERSION_MINOR 13

#ifndef LOG
#define LOG(X, ...) (fprintf(stderr, "[%lld]" X, arcan_timemillis(), ## __VA_ARGS__))
#endif

/*
 * For porting the shmpage interface, these functions need to be implemented
 * and pulled in, shouldn't be more complicated than mapping to the
 * corresponding platform/ functions. In the longer scope, these should be
 * factored out and replaced as well.
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
int arcan_fdscan(int** listout);
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
 * Wait for an incoming event for a maximum of ~time_ms, and update it with
 * the amount of milliseconds left (if any) on the timer.
 *
 * This is a convenience wrapper combining the behavior of some low precision
 * OS wait primitive and that of arcan_shmif_wait. The amount of milliseconds
 * left (if any) will be stored back into time_ms.
 */
int arcan_shmif_wait_timed(
	struct arcan_shmif_cont*, unsigned* time_us, struct arcan_event* dst);

/*
 * When integrating with libraries assuming that a window can be created
 * synchronously, there is a problem with what to do with events that are
 * incoming while waiting for the accept- or reject to our request.
 *
 * The easiest approach is to simply skip forwarding events until we receive
 * the proper reply since windows allocations typically come during some init/
 * setup phase or as low-frequent event response. Thep problem with this is
 * that any events in between will be dropped.
 *
 * The other option is to buffer events, and then flush them out,
 * essentially creating an additional event-queue. This works EXCEPT for the
 * cases where there are events that require file descriptor transfers.
 *
 * This function implements this buffering indefinitely (or until OOM),
 * dup:ing/saving descriptors while waiting and forcing the caller to cleanup.
 *
 * The correct use of this function is as follows:
 * (send SEGREQ event)
 *
 * struct arcan_event acq_event;
 * struct arcan_event* evpool = NULL;
 *
 * if (arcan_shmif_acquireloop(cont, &acq_event, &evpool, &evpool_sz){
 * 	we have a valid segment
 *   acq_event is valid, arcan_shmif_acquire(...);
 * }
 * else {
 * 	if (!evpool){
 *    OOM
 * 	}
 * 	if (evpool_sz < 0){
 *  	shmif-state broken, only option is to terminate the connection
 *  	arcan_shmif_drop(cont);
 *  	return;
 * 	}
 *	the segment request failed
 *}
 *
 * cleanup
 * for (size_t i = 0; i < evpool_sz; i++){
 *  forward_event(&evpool[i]);
 *  if (arcan_shmif_descrevent(&evpool[i]) &&
 *  	evpool[i].tgt.ioev[0].iv != -1)
 *  		close(evpool[i].tgt.ioev[0].iv);
 * }
 *
 * free(evpool);
 *
 * Be sure to check the cookie of the acq_event in the case of a
 * TARGET_COMMAND_NEWSEGMENT as the server might have tried to preemptively
 * push a new subsegment (clipboard management, output, ...)
 */
bool arcan_shmif_acquireloop(struct arcan_shmif_cont*,
	struct arcan_event*, struct arcan_event**, ssize_t*);

/*
 * returns true if the provided event carries a file descriptor
 */
bool arcan_shmif_descrevent(struct arcan_event*);

/*
 * retrieve the currently saved- context GUID
 */
void arcan_shmif_guid(struct arcan_shmif_cont*, uint64_t[2]);

/*
 * Take a subsegment carrying event and forward to a possible default
 * implementation of it. This is an extreme corner case use intended primarily
 * for the TUI implementation where a user may request a subsegment that it he
 * doesn't want to handle, and we want to fall-back to the default
 * implementation that is dormant inside shmif and would be activated when a
 * subsegment request isn't mapped.
 */
void arcan_shmif_defimpl(
	struct arcan_shmif_cont* newchild, int type, void* pref);

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
 * Pack the contents of the event into an implementation specifized byte
 * buffer. Returns the amount of bytes consumed or -1 if the supplied buffer
 * is too small.
 */
ssize_t arcan_shmif_eventpack(
	const struct arcan_event* const aev, uint8_t* dbuf, size_t dbuf_sz);

/*
 * Unpack an event from a bytebuffer, returns the number of byted consumed
 * or -1 if the buffer did not contain a valid event.
 */
ssize_t arcan_shmif_eventunpack(
	const uint8_t* const buf, size_t buf_sz, struct arcan_event* out);

/*
 * Resolve implementation- defined connection connection path based on a
 * suggested key. Returns -num if the resolved path couldn't fit in dsz (with
 * abs(num) indicating the number of truncated bytes) and number of characters
 * (excluding NULL) written to dst.
 */
int arcan_shmif_resolve_connpath(
	const char* key, char* dst, size_t dsz);

/*
 * get the segment kind identifier from an existing connection
 */
int arcan_shmif_segkind(struct arcan_shmif_cont* con);

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
 * Lookup the [ind]th(starting at 0) argument matching [key].
 * Returns true if there was a matching key at the desired position.
 *
 * If [found] is provided, the corresponding value will be stored.
 * If no key could be found OR the lookup failed, NULL will be stored instead.
 *
 * Example:
 * ARCAN_ARG=test:test=1
 * if (arg_lookup(myarg, "test", 1, &val)){
 *    if (val){
 *        val will be "1" here
 *    }
 * }
 */
bool arg_lookup(struct arg_arr* arr,
	const char* key, unsigned short ind, const char** found);

/*
 * deallocate/free the resources bound to an arg_arr struct. Don't use this
 * on an arg_arr that comes from a shmif_open or shmif_args call as the
 * normal context management functions will clean after that one.
 */
void arg_cleanup(struct arg_arr*);

/*
 * ideally both rpath and wpath could be dropped when the semaphores becomes
 * futex- only as the set now is too permissive to be comfortable
 */
#define SHMIF_PLEDGE_PREFIX \
	"stdio unix sendfd recvfd proc ps rpath wpath cpath tmppath unveil video"

/*
 * Attempt to reduce the exposed set of privileges and whitelist accessible
 * filesystem paths. This is a best-effort that might result in a no-op
 * or a lesser set of restrictions depending on the platform and context.
 *
 * if a context is provided, the function may enqueue an event to indicate
 * sandbox status to the server.
 *
 * [pledge] this argument matches either special preset strings of higher
 *          roles, or the set of OpenBSD-pledge(2) syscall whitelists, with
 *          the necessary set for opening and maintaining shmif context
 *          changes being SHMIF_PLEDGE_PREFIX.
 *
 * [paths] is a NULL- terminated list of file-system paths and their
 *         intended mode of operations
 *
 * [flag]  reserved for future use.
 *
 * alternate pledge templates:
 *         shmif    - same as running the SHMIF_PLEDGE_PREFIX
 *         minimal  - shared memory page
 *         decode   - decode frameserver archetype
 *         encode   - encode frameserver archetype
 *         a12-srv  - a local shmif-server to network proxy
 *         a12-cl   - a local shmif-client to network proxy
 */
struct shmif_privsep_node {
	const char* path;
	const char* perm; /*r, w, x, c */
};
void arcan_shmif_privsep(struct arcan_shmif_cont* C,
	const char* pledge, struct shmif_privsep_node**, int opts);

/*
 * Duplicates a descriptor and set safe flags (e.g. CLOEXEC)
 * if [dstnum] is >= 0, it will ATTEMPT to duplicate to the specific number,
 * (though NOT GUARANTEED).
 *
 * Returns a valid descriptor or -1 on error (with errno set according
 * to the dup() call family.
 */
int arcan_shmif_dupfd(int fd, int dstnum, bool blocking);

/*
 * Update the short ~(32b) message that the connection will try and forward
 * should the client crash or be terminated in some other abnormal way.
 */
void arcan_shmif_last_words(struct arcan_shmif_cont* cont, const char* msg);

/*
 * Take a pending HANDOVER segment allocation and inherit into a new
 * process.
 *
 * If env is empty, the ONLY environment that will propagate is the
 * handover relevant variables.
 *
 * [detach] is treated as a bitmap, where the bits set:
 *   1: detach process (double-fork)
 *   2: stdin (becomes /dev/null or similar)
 *   3: stdout (becomes /dev/null or similar)
 *   4: stderr (becomes /dev/null or similar)
 * Other descriptors follow normal system specific inheritance semantics.
 *
 * The function returns the pid of the new process, or -1 in the event
 * of a failure (e.g. invalid arguments, empty path or argv).
 *
 * NOTE:
 * call from event dispatch immediately upon receiving a NEWSEGMENT with
 * a HANDOVER type, the function will assume allocation responsibility.
 *
 * If handover_exec is called WITHOUT the corresponding handover event in
 * ev, it is the context in [cont] that will be forwarded.
 */
pid_t arcan_shmif_handover_exec(
	struct arcan_shmif_cont* cont, struct arcan_event ev,
	const char* path, char* const argv[], char* const env[],
	int detach);

/*
 * Mark, for the current frame (this is reset each signal on sigvid) buffer
 * contents as updated. Note that this does not guarantee that only the dirty
 * regions will be synched to the next receiver in the chain, the buffer
 * contents are required to be fully intact.
 *
 * This requires that the segment has been resized with the flags
 * SHMIF_RHINT_SUBREGION (or _CHAIN) or it will have no effect.
 *
 * Depending on if the segment is in SHMIF_RHINT_SUBREGION or
 * SHMIF_RHINT_SUBREGION_CHAIN, the behavior will be different.
 *
 * For SHMIF_RHINT_SUBREGION, the function returns 0 on success or -1 if the
 * context is dead / broken. You are still required to use shmif_signal calls
 * to synchronize the contents. Only the set of damaged regions will grow.
 *
 * [ Not yet implemented ]
 * This interface combines a number of latency and performance sensitive
 * usecases, with the ideal should re-add the possibility of run-ahead or
 * a run-behind the beam on a single buffered output.
 *
 * For SHMIF_RHINT_SUBREGION_CHAIN, the options to the flags function are:
 * SHMIF_DIRTY_NONBLOCK, SHMIF_DIRTY_PARTIAL and SHMIF_DIRTY_SIGNAL.
 * Bitmask behavior is: NONBLOCK | (PARTIAL ^ SIGNAL).
 *
 * If NONBLOCK is set, the function returns SHMIF_DIRTY_EWOULDBLOCK if the
 * operation would block and in that case, the dirty region won't register.
 *
 * if PARTIAL is set, the update will be synched to whatever output the
 * connection may be mapped to but no other notification about the update will
 * be triggered. Instead, if SIGNAL is set, when the region has been synched,
 * other subsystems will be alerted as to a logical 'frame' update.
 *
 * This is used in order to allow 'per scanline' like updates but without
 * storming subsystems that reason on a "logical buffer" update where the
 * cost per frame might be too high to be invoked in smaller chunks.
 *
 * If the dirty region provides invalid constraints (x1 >= x2, y1 >= y2,
 * x2 > cont->w, y2 > cont->h) the values will be clamped to the size of
 * the segment.
 */
int arcan_shmif_dirty(struct arcan_shmif_cont*,
	size_t x1, size_t y1, size_t x2, size_t y2, int fl);

/*
 * This is primarily intended for clients with special timing needs due to
 * latency concerns, typically games and multimedia.
 *
 * Get an estimate on how many MICROSECONDS left until the next ideal time
 * to synch. These are relative to the current time, thus will tick down
 * on multiple calls until a deadline has passed.
 *
 * The [cost_estimate] argument is an estimate on how much processing
 * time you would need to prepare the next frame and it can simply be
 * the value of how much was spent rendering the last one.
 *
 * Possible [errc] values:
 *
 *  -1, invalid / dead context
 *  -2, context in a blocked state
 *  -3, deadline information inaccurate, values returned are defaults.
 *
 * The optional [tolerance] argument provides an estimate as to how large
 * margin for error that is reasonable (in MICROSECONDS). This MAY be
 * derived from frame delivery timings or be adjusted by the consumer
 * to balance latency, precision and accuracy.
 *
 * Thus, deadline - jitter = time left until synch should be called for
 * a chance to have your contents be updated in time. This time can thus
 * be used to delay synching and used as a timeout (pseudo-code):
 *
 * int left = arcan_shmif_deadline(cont, last_cost, &jout, &errc);
 * if (last_frame_cost - left > jout){
 *     while(poll_timeout(cont, left)){
 *         process_event();
 *     }
 * }
 */
int arcan_shmif_deadline(
	struct arcan_shmif_cont*, unsigned last_cost, int* jitter, int* errc);

/*
 * Asynchronously transfer the contents of [fdin] to [fdout]. This is
 * mainly to encourage non-blocking implementation of the bchunk handler.
 * The descriptors will be closed when the transfer is completed or if
 * it fails.
 *
 * If [sigfd] is provided (> 0),
 * the result of the operation will be written on finish as:
 *   -1 (read error)
 *   -2 (write error)
 *   -3 (alloc/arg error)
 *    0 (ok)
 *
 */
void arcan_shmif_bgcopy(
	struct arcan_shmif_cont*, int fdin, int fdout, int sigfd, int flags);

/*
 * Used as helper to avoid dealing with all of the permutations of
 * devkind == EVENT_IDEVKIND_MOUSE for datatype == EVENT_IDATATYPE_ANALOG.
 * If >true< the status of have changed since last time.
 *
 * uint8_t mstate[ASHMIF_MSTATE_SZ];
 * arcan_shmif_mousestate_setup(acon, false, mstate);
 * ... in event loop ...
 * if (arcan_shmif_mousestate(mstate, &inev, &out_x, &out_y)){
 *  react on mouse event
 * }
 *
 * if [inev] isn't provided and the state is set to absolute, the last known
 * values will be returned.
 *
 * Mouse button tracking, gestures, and splitting on .devid are not included
 * in this helper function.
 */
#define ASHMIF_MSTATE_SZ 32
void arcan_shmif_mousestate_setup(
	struct arcan_shmif_cont* con, bool relative, uint8_t* state);

bool arcan_shmif_mousestate(
	struct arcan_shmif_cont*, uint8_t* state,
	struct arcan_event* inev, int* out_x, int* out_y);

/*
 * Part of auxiliary library, pulls in more dependencies and boiler-plate
 * for setting up accelerated graphics
 */
#ifdef WANT_ARCAN_SHMIF_HELPER

/*
 * Maintain both context and display setup. This is for cases where you don't
 * want to set up EGL or similar support yourself. For cases where you want to
 * do the EGL setup except for the NativeDisplay part, use _egl.
 *
 * [Warning] stick to either _setup OR (_egl, vk), don't mix
 *
 */
enum shmifext_setup_status {
	SHHIFEXT_UNKNOWN = 0,
	SHMIFEXT_NO_API,
	SHMIFEXT_NO_DISPLAY,
	SHMIFEXT_NO_EGL,
	SHMIFEXT_NO_CONFIG,
	SHMIFEXT_NO_CONTEXT,
	SHMIFEXT_ALREADY_SETUP,
	SHMIFEXT_OUT_OF_MEMORY,
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
	uint64_t flags;
	uint64_t mask;

/* 0 for self-managed fbo or imported buffers
 * >0 for internal rendertarget that swaps out */
	uint8_t builtin_fbo;
	uint8_t supersample;
	uint8_t stencil;

/* don't allocate a context or display at all - whatever context is
 * active in the current thread will be used for allocations */
	uint8_t no_context;
	uint64_t shared_context;

/* deprecated members, but don't want to break abi, while still
 * generating compiler visible errors for api break */
	uint8_t deprecated_1;
	uint32_t deprecated_2;

/* workaround for versioning snafu with _setup not taking sizeof(...) */
	uint8_t uintfl_reserve[6];
	uint64_t reserved[4];
};

struct arcan_shmifext_setup arcan_shmifext_defaults(
	struct arcan_shmif_cont* con);

enum shmifext_setup_status arcan_shmifext_setup(
	struct arcan_shmif_cont* con,
	struct arcan_shmifext_setup arg);

/*
 * Check if the connection is in an extended state or not.
 * return values:
 * 0 - not extended
 * 1 - extended, handle passing
 * 2 - extended, readback fallback
 */
int arcan_shmifext_isext(struct arcan_shmif_cont* con);

/*
 * for use with the shmifext_setup approach, try and find the
 * requested symbol within the context of the accelerated graphics backend
 */
void* arcan_shmifext_lookup(
	struct arcan_shmif_cont* con, const char*);

/*
 * Sometimes, multiple contexts, possibly bound to different threads, are
 * needed. _setup creates one context, and this function can be added to
 * create additional ones.
 *
 * Returns 0 or a reference to use for shmifext_swap_context calls
 */
unsigned arcan_shmifext_add_context(
	struct arcan_shmif_cont* con, struct arcan_shmifext_setup arg);

/*
 * Swap the current underlying context to use for _make_current calls.
 * the [context] argument comes from _add_context, though the first (_setup)
 * one will always be 1 */
void arcan_shmifext_swap_context(
	struct arcan_shmif_cont* con, unsigned context);

/*
 * Uses lookupfun to get the function pointers needed, writes back matching
 * EGLNativeDisplayType into *display and tags *con as accelerated.
 * Can be called multiple times as response to DEVICE_NODE calls or to
 * retrieve the display associated with con
 */
bool arcan_shmifext_egl(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag);

/*
 * For the corner cases where you need access to the display/surface/context
 * but don't want to detract from the _setup
 */
bool arcan_shmifext_egl_meta(struct arcan_shmif_cont* con,
	uintptr_t* display, uintptr_t* surface, uintptr_t* context);

/*
 * Similar to extracting the display, surface, context and manually
 * making it the current eglContext. If the setup has been called with
 * builtin- FBO, it will also manage allocating and resizing FBO.
 */
bool arcan_shmifext_make_current(struct arcan_shmif_cont* con);

/*
 * Free and destroy an associated context, display and internal buffers
 * in order to stop using the connection for accelerated drawing.
 */
bool arcan_shmifext_drop(struct arcan_shmif_cont* con);

/*
 * Similar to arcan_shmifext_drop, except the display and device connection
 * is kept alive, intended to build a new context with _setup later
 */
bool arcan_shmifext_drop_context(struct arcan_shmif_cont* con);

/*
 * If headless setup uses a built-in FBO configuration, this function can be
 * used to extract the opaque handles from it. These are only valid when the
 * context is active (_make_current).
 */
bool arcan_shmifext_gl_handles(struct arcan_shmif_cont* con,
	uintptr_t* frame, uintptr_t* color, uintptr_t* depth);

/*
 * Placeholder awaiting VK support
 */
bool arcan_shmifext_vk(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag);

/*
 * Set the rendertarget contained in the extended context as active.
 */
void arcan_shmifext_bind(struct arcan_shmif_cont* con);

/*
 * Update the internal buffer-fail to slow readback fallback resulting from a
 * failed attempt to pass an accelerated buffer. This will be called
 * automatically on an incoming BUFFER_FAIL event.
 */
void arcan_shmifext_bufferfail(struct arcan_shmif_cont*, bool);

/*
 * Run the platform specific dance to convert a gl texture ID to a passable
 * descriptor (shmif_signalhandle), note that only one texture should be 'in
 * flight' (on both sides) at any one time, and calling this a second time
 * invalidates the resources used by the last passed one.
 *
 * This is slated to be changed to use the same buffer-plane format as in
 * import buffer.
 */
bool arcan_shmifext_gltex_handle(
	struct arcan_shmif_cont* con,
	uintptr_t display, uintptr_t tex_id,
	int* dhandle, size_t* dstride, int* dfmt);

/*
 * Retrieve a file-handle to the device that is currently used for the
 * acceleration, or -1 if it is unavailable. if [outdev] is !NULL, it will
 * be set to point to a platform specific device structure. Outside very
 * specialized uses (Xarcan), this should be ignored.
 */
int arcan_shmifext_dev(
	struct arcan_shmif_cont* con, uintptr_t* outdev, bool clone);

/*
 * Retrieve the agp function environment from the currently active context.
 * This should only really be useful for project-coupled tools like waybridge
 * where access to the agp_ set of functions is also guaranteed.
 */
struct agp_fenv* arcan_shmifext_getfenv(struct arcan_shmif_cont*);

/*
 * Take an external buffer e.g. from gbm or egl-streams and import into the
 * context as a substitution for it's current backing store, this disables
 * rendering using the context.
 *
 * If the import is successful, any descriptors pointed to by the fd and fence
 * fields will be owned by the implementation of the import function and will
 * be closed when safe to do so.
 *
 * If [dst_store] is set, the default buffer of the context will not be used
 * as the target store. Instead, [dst_store] will be updated to contain the
 * imported buffer.
 */
struct shmifext_buffer_plane {
	int fd;
	int fence;
	size_t w;
	size_t h;

	union {
		struct {
			uint32_t format;
			uint64_t pitch;
			uint64_t offset;
			uint64_t modifiers;
		} gbm;
	};
};

enum shmifext_buffer_format {
	SHMIFEXT_BUFFER_GBM = 0,
};

bool arcan_shmifext_import_buffer(
	struct arcan_shmif_cont*,
	int format,
	struct shmifext_buffer_plane* planes,
	size_t n_planes,
	size_t buffer_plane_sz
);

/*
 * Similar behavior to signalhandle, but any conversion from the texture id
 * in [tex_id] is handled internally in accordance with the last _egl
 * call on [con]. The context where tex_id is valid should already be
 * active.
 *
 * Display corresponds to the EGLDisplay where tex_id is valid, or
 * 0 if the shmif_cont is managing the context.
 *
 * If tex_id is SHMIFEXT_BUILTIN and context was setup with FBO management OR
 * with vidp- texture streaming, the color attachment for the active FBO OR
 * the latest imported buffer.
 *
 * Returns -1 on handle- generation/passing failure, otherwise the number
 * of miliseconds (clamped to INT_MAX) that elapsed from signal to ack.
 */
#define SHMIFEXT_BUILTIN (~(uintptr_t)0)
int arcan_shmifext_signal(struct arcan_shmif_cont*,
	uintptr_t display, int mask, uintptr_t tex_id, ...);
#endif

#endif
