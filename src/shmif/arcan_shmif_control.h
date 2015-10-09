/*
 Arcan Shared Memory Interface

 Copyright (c) 2014-2015, Bjorn Stahl
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

#ifndef _HAVE_ARCAN_SHMIF_CONTROL
#define _HAVE_ARCAN_SHMIF_CONTROL

/*
 * This header defines the interface and support functions for
 * shared memory- based communication between the arcan parent
 * and frameservers/non-authoritative clients.
 *
 * For extended documentation on how this interface works, design
 * rationale, changes and so on, please refer to the wiki @
 * https://github.com/letoram/arcan/wiki/Shmif
 */

/*
 * These prefixes change the search and namespacing rules for how a
 * non-authoritative connection should find a running arcan server based
 * on a key.
 */
#ifdef __linux
#ifndef ARCAN_SHMIF_PREFIX
#define ARCAN_SHMIF_PREFIX "\0arcan_"
#endif

/* If the first character does not begin with /, HOME env will be used. */
#else
#ifndef ARCAN_SHMIF_PREFIX
#define ARCAN_SHMIF_PREFIX ".arcan_"
#endif
#endif

/*
 * Default permissions / mask that listening sockets will be created under
 */
#ifndef ARCAN_SHM_UMASK
#define ARCAN_SHM_UMASK (S_IRWXU | S_IRWXG)
#endif

/*
 * Compile-time constants that define the size and layout
 * of the shared structure. These values are part in defining the ABI
 * and should therefore only be tuned when you have control of the
 * whole-system compilation and packaging (OS distributions, embedded
 * systems).
 */

/*
 * Define the reserved ring-buffer space used for input and output events
 * must be 0 < PP_QUEUE_SZ < 256
 */
#ifndef PP_QUEUE_SZ
#define PP_QUEUE_SZ 32
#endif
static const int ARCAN_SHMIF_QUEUE_SZ = PP_QUEUE_SZ;

/*
 * Audio format and basic parameters, this is kept primitive on purpose.
 * This part is slated for refactoring to support exclusive- device locks,
 * and raw device access for advanced applications.
 */
static const int ARCAN_SHMIF_SAMPLERATE = 48000;
static const int ARCAN_SHMIF_ACHANNELS = 2;
static const int ARCAN_SHMIF_SAMPLE_SIZE = sizeof(short);
static const int ARCAN_SHMIF_AUDIOBUF_SZ = 65535;

/*
 * These are technically limited by the combination of graphics and video
 * platforms. Since the buffers are placed at the end of the struct, they
 * can be changed without breaking ABI though several resize requests may
 * be rejected.
 */
#ifndef PP_SHMPAGE_MAXW
#define PP_SHMPAGE_MAXW 4096
#endif
static const int ARCAN_SHMPAGE_MAXW = PP_SHMPAGE_MAXW;


#ifndef PP_SHMPAGE_MAXH
#define PP_SHMPAGE_MAXH 2048
#endif
static const int ARCAN_SHMPAGE_MAXH = PP_SHMPAGE_MAXH;

/*
 * Identification token that may need to be passed when making a socket
 * connection to the main arcan process.
 */
#ifndef PP_SHMPAGE_SHMKEYLIM
#define PP_SHMPAGE_SHMKEYLIM 32
#endif

/*
 * We abstract the base type for a pixel and provide a packing macro in
 * order to permit systems with lower memory to switch to uint16 RGB565
 * style formats, and to permit future switches to higher depth/range.
 */
#ifndef VIDEO_PIXEL_TYPE
#define VIDEO_PIXEL_TYPE uint32_t
#endif
#define ARCAN_SHMPAGE_VCHANNELS 4
typedef VIDEO_PIXEL_TYPE shmif_pixel;
#ifndef RGBA
#define RGBA(r, g, b, a)( ((uint32_t)(a) << 24) | ((uint32_t) (b) << 16) |\
((uint32_t) (g) << 8) | ((uint32_t) (r)) )
#endif

/*
 * Reasonable starting dimensions, this can be changed without breaking ABI
 * as parent/client will initiate a resize based on gain relative to the
 * current size.
 *
 * It should, at least, fit 32*32*sizeof(shmif_pixel) + sizeof(struct) +
 * sizeof event*PP_QUEUE_SIZE*2 + PP_AUDIOBUF_SZ with alignment padding.
 */
#ifndef PP_SHMPAGE_STARTSZ
#define PP_SHMPAGE_STARTSZ 2014088
#endif

/*
 * This is calculated through MAXW*MAXH*sizeof(shmif_pixel) + sizeof
 * struct + sizeof event*PP_QUEUE_SIZE*2 + PP_AUDIOBUF_SZ with alignment.
 * (too bad constexpr isn't part of C11)
 * It is primarily of concern when OVERCOMMIT build is used where it isn't
 * possible to resize dynamically.
 */
#ifndef PP_SHMPAGE_MAXSZ
#define PP_SHMPAGE_MAXSZ 48294400
#endif
static const int ARCAN_SHMPAGE_MAX_SZ = PP_SHMPAGE_MAXSZ;

/*
 * Overcommit is a specialized build mode (that should be avoided if possible)
 * that sets the initial segment size to PP_SHMPAGE_STARTSZ and no new buffer
 * dimension negotiation will occur.
 */
#ifdef ARCAN_SHMIF_OVERCOMMIT
static const int ARCAN_SHMPAGE_START_SZ = PP_SHMPAGE_MAXSZ;
#else
static const int ARCAN_SHMPAGE_START_SZ = PP_SHMPAGE_STARTSZ;
#endif

/*
 * Two primary transfer operation types, from the perspective of the
 * main arcan application (i.e. normally frameservers feed INPUT but
 * specialized recording segments are flagged as OUTPUT. Internally,
 * these have different synchronization rules.
 */
enum arcan_shmif_type {
	SHMIF_INPUT = 1,
	SHMIF_OUTPUT
};

/*
 * This enum defines the possible operations for audio and video
 * synchronization (both or either) and how locking should behave.
 */
enum arcan_shmif_sigmask {
	SHMIF_SIGVID = 1,
	SHMIF_SIGAUD = 2,

/* synchronous, wait for parent to acknowledge */
	SHMIF_SIGBLK_FORCE = 0,

/* return immediately, further writes may cause tearing and other
 * visual/aural artifacts */
	SHMIF_SIGBLK_NONE  = 4,

/* return immediately unless there is already a transfer pending */
	SHMIF_SIGBLK_ONCE = 8
};

typedef enum arcan_shmif_sigmask(
	*shmif_trigger_hook)(struct arcan_shmif_cont*);

struct shmif_hidden;
struct arcan_shmif_page;

enum SHMIF_FLAGS {
/* by default, the connection IPC resources are unlinked, this
 * may not always be desired (debugging, monitoring, ...) */
	SHMIF_DONT_UNLINK = 1,

/* a guard thread is usually allocated to monitor the status of
 * the server, setting this flag explicitly prevents the creation of
 * that thread */
	SHMIF_DISABLE_GUARD = 2,

/* failure to acquire a segment should be exit(EXIT_FAILURE); */
	SHMIF_ACQUIRE_FATALFAIL = 4,

/* if FATALFAIL, do we have a custom function? should be first argument */
	SHMIF_FATALFAIL_FUNC = 8,

/* set to sleep- try spin until a connection is established */
	SHMIF_CONNECT_LOOP = 16
};

/*
 * Convenience wrapper function of checking environment variables
 * for packed arguments, connection path / key etc.
 *
 * Will also clean-up / reset related environments
 * to prevent propagation.
 *
 * If no arguments could be unpacked, *arg_arr will be set to NULL.
 */
struct arcan_shmif_cont arcan_shmif_open(
	enum ARCAN_SEGID type, enum SHMIF_FLAGS flags, struct arg_arr**);

/*
 * This is used to make a non-authoritative connection using
 * a domain- socket as a connection point (as specified by the
 * connpath and optional connkey).
 *
 * Will return NULL or a user-managed string with a key
 * suitable for shmkey, along with a file descriptor to the
 * connected socket in *conn_ch
 */
char* arcan_shmif_connect(const char* connpath,
	const char* connkey, file_handle* conn_ch);

/*
 * Using a identification string (implementation defined connection
 * mechanism)
 */
struct arcan_shmif_cont arcan_shmif_acquire(
	struct arcan_shmif_cont* parent, /* should only be NULL internally */
	const char* shmkey,    /* provided in ENV or from shmif_connect below */
	enum ARCAN_SEGID type, /* archetype, defined in shmif_event.h */
	enum SHMIF_FLAGS flags, ...
);

/*
 * There can be one "post-flag, pre-semaphore" hook that will occur
 * before triggering a sigmask and can be used to synch audio to video
 * or video to audio during transfers.
 * 'mask' argument defines the signal mask slot (A xor B only, A or B is
 * undefined behavior).
 */
shmif_trigger_hook arcan_shmif_signalhook(struct arcan_shmif_cont*,
	enum arcan_shmif_sigmask mask, shmif_trigger_hook, void* data);

/*
 * Using the specified shmpage state, return pointers into
 * suitable offsets into the shared memory pages for video
 * (planar, packed, RGBA) and audio (limited by abufsize constant).
 */
void arcan_shmif_calcofs(struct arcan_shmif_page*,
	uint32_t** dstvidptr, int16_t** dstaudptr);

/*
 * Using the specified shmpage state, synchronization semaphore handle,
 * construct two event-queue contexts. Parent- flag should be set
 * to false for frameservers
 */
void arcan_shmif_setevqs(struct arcan_shmif_page*,
	sem_handle, arcan_evctx* inevq, arcan_evctx* outevq, bool parent);

/* (frameserver use only) helper function to implement request/synchronization
 * protocol to issue a resize of the output video buffer.
 *
 * This request can be declined (false return value) and should be considered
 * expensive (may block indefinitely). Anything that depends on the contents of
 * the shared-memory dependent parts of shmif_cont (eventqueue, vidp/audp, ...)
 * should be considered invalid during/after a call to shmif_resize and the
 * function will internally rebuild these structures.
 *
 * This function is not thread-safe -- While a resize is pending, none of the
 * other operations (drop, signal, en/de- queue) are safe.  If events are
 * managed on a separate thread, these should be treated in mutual exclusion
 * with the size operation.
 *
 * There are four possible outcomes here:
 * a. resize fails, dimensions exceed hard-coded limits.
 * b. resize succeeds, vidp/audp are re-aligned.
 * c. resize succeeds, the segment is truncated to a new size.
 * d. resize succeeds, we switch to a new shared memory connection.
 *
 * Note that the actual effects / resize behavior in the running appl may be
 * delayed until the first shmif_signal call on the resized segment. This is
 * done in order to avoid visual artifacts that would stem from having source
 * material in one resolution while metadata refers to another.
 */
bool arcan_shmif_resize(struct arcan_shmif_cont*,
	unsigned width, unsigned height);

/*
 * Unmap memory, release semaphores and related resources
 */
void arcan_shmif_drop(struct arcan_shmif_cont*);

/*
 * Signal that the audio and/or video blocks are ready for
 * a transfer, this may block indefinitely
 */
void arcan_shmif_signal(struct arcan_shmif_cont*, int mask);

/*
 * Signal a video transfer that is based on buffer sharing
 * rather than on data in the shmpage
 */
void arcan_shmif_signalhandle(struct arcan_shmif_cont*, int mask,
	int handle, size_t stride, int format, ...);

/*
 * Support function to calculate the size of a shared memory
 * segment given the specified dimensions (width, height).
 */
size_t arcan_shmif_getsize(unsigned width, unsigned height);

/*
 * Support function to set/unset the primary access segment
 * (one slot for input. one slot for output), manually managed.
 */
struct arcan_shmif_cont* arcan_shmif_primary(enum arcan_shmif_type);
void arcan_shmif_setprimary( enum arcan_shmif_type, struct arcan_shmif_cont*);

/*
 * This should be called periodically to prevent more subtle
 * bugs from cascading and be caught at an earlier stage,
 * it checks the shared memory context against a series of cookies
 * and known guard values, returning [false] if not everything
 * checks out.
 */
bool arcan_shmif_integrity_check(struct arcan_shmif_cont*);

struct arcan_shmif_cont {
	struct arcan_shmif_page* addr;

/* offset- pointers into addr, can change between calls to
 * shmif_ functions so aliasing is not recommended */
	shmif_pixel* vidp;
	int16_t* audp;

/*
 * This cookie is set/kept to some implementation defined value
 * and will be verified during integrity_check. It is placed here
 * to quickly detect overflows in video or audio management.
 */
	int16_t oflow_cookie;

/*
 * the event handle is provided and used for signal event delivery
 * in order to allow multiplexation with other input/output sources
 */
	file_handle epipe;

/*
 * Maintain a connection to the shared memory handle in order
 * to handle resizing (on platforms that support it, otherwise
 * define ARCAN_SHMIF_OVERCOMMIT which will only recalc pointers
 * on resize
 */
	file_handle shmh;
	size_t shmsize;

/*
 * Used internally for synchronization (and mapped / managed outside
 * the regular shmpage). system-defined but typically named semaphores.
 */
	sem_handle vsem, asem, esem;

/*
 * Should be used to index vidp, i.e. vidp[y * pitch + x] = RGBA(r, g, b, a)
 * stride and pitch account for padding, with stride being a row length in
 * bytes and pitch a row length in pixels.
 */
	size_t w, h, stride, pitch;

/*
 * The cookie act as overflow monitor and trigger for ABI incompatibilities
 * between arcan main and program using the shmif library. Combined from
 * shmpage struct offsets and type sizes. Periodically monitored (using
 * arcan_shmif_integrity_check calls) and incompatibilities is a terminal
 * state transition.
 */
	uint64_t cookie;

/*
 * User-tag, primarily to support attaching ancilliary data to subsegments
 * that are run and synchronized in separate threads.
 */
	void* user;

/*
 * Opaque struct for implementation defined tracking (guard thread handles
 * and related data).
 */
	struct shmif_hidden* priv;
};

enum rhint_mask {
	RHINT_ORIGO_UL = 0,
	RHINT_ORIGO_LL = 1
};

struct arcan_shmif_page {
/*
 * These will be set to the ARCAN_VERSION_MAJOR and ARCAN_VERSION_MAJOR
 * defines, a mismatch will cause the integrity_check to fail and
 * both sides may decide to terminate. Thus, they also act as a header
 * guard.
 */
	int8_t major;
	int8_t minor;

/* will be checked frequently, likely before transfers as it means
 * that shmcontents etc. will be invalid */
	volatile int8_t resized;

/*
 * Dead man's switch, set to 1 when a connection is active and released
 * if parent or child detects an anomaly that would indicate misuse or
 * data corruption. This will trigger guard-threads and similar structures
 * to release semaphores and attempt to shut down gracefully.
 */
	volatile uint8_t dms;

/*
 * Flipped whenever a buffer is ready to be synched,
 * polled repeatedly by the parent (or child for the case of an
 * encode frameserver) then the corresponding sem_handle is used
 * as a wake-up trigger.
 */
	volatile uint8_t aready;
	volatile uint8_t vready;

/*
 * Presentation hints, see mask above.
 */
	uint8_t hints;

/*
 * This is set by the parent and will be compared with the cookie
 * that is generated in the shmcont structure above.
 */
	uint64_t cookie;

/*
 * These heavily rely on the layout provided in shmif/arcan_event.h
 * and tightly couples the connection model and the event model, which
 * is an unpleasant tradeoff. Most structures are prepared to quickly
 * switch this model to using a socket, should it be needed.
 */
	struct {
		struct arcan_event evqueue[ PP_QUEUE_SZ ];
		uint8_t front, back;
	} childevq, parentevq;

/*
 * On a resize, parent will update segment_size. If this differs from
 * the previously known size (tracked in cont), the segment should be
 * remapped. Parent has a local copy so from a client perspective, this
 * value is read-only.
 *
 * Not all operations will lead to a change in segment_size, OVERCOMMIT
 * builds has its size fixed, and parent may heuristically determine if
 * a shrinking- operation is worth the overhead or not.
 */
	uint32_t segment_size;

/*
 * Current video output dimensions, if these deviate from the
 * agreed upon dimensions (i.e. change w,h and set the resized flag to !0)
 * the parent will simply ignore the data presented.
 */
	uint16_t w, h;

/*
 * Video buffers are planar transfers of a pre-determined size. Audio,
 * on the other hand, can be appended and wholly or partially consumed
 * by the side that currently holds the synch- semaphore.
 */
	uint16_t abufused;

/*
 * Timing related data to a video frame can be attached in order to assist
 * the parent in determining when/if synchronization should be released
 * and the frame rendered. This value is a hint, do not rely on it as a
 * clock/sleep mechanism.
 */
	int64_t vpts;

/*
 * A frameserver or non-authoritative connection do not always know which
 * process that is responsible for maintaining the connection (which may
 * be a desired property). To allow a child to monitor and see if the parent
 * is alive in situations where the event- signal socket do not help,
 * this value is set upon creation (and can be modified during a video-
 * frame synch). This is to permit the parent to do hand-overs/migration
 * etc.
 */

	process_handle parent;
};

#endif
