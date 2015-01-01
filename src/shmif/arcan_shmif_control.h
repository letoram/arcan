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
 * and each "frameserver". Some parts of this interface is
 * likely to be changed/expanded in the near future, and is
 * NOT to be treated as a communication protocol between
 * processes of different trust-domains/compiler/abi/... origin,
 * we can/might/should use Wayland for that.
 *
 * The primary use here is for frequent, synchronized transfer
 * of video frames along with related control events.
 *
 * It is assumed that all newly spawned frameservers are allowed
 * ONE video- buffer and ONE audio- buffer to work with.
 *
 * Other forms of data (files for transferring to a remote source,
 * data sources for state serialization / deserialization) etc.
 * are managed through file-descriptor passing (HANDLES for the
 * windows crowd).
 *
 * See frameserver/avfeed.c for a stripped down example of using
 * this interface. There are three principal ways this interface
 * is used;
 * 1. compliant frameservers - video decoders, encoders, network
 * protocol implementations etc. Environment and connection points
 * are prepared by the parent process in beforehand.
 *
 * 2. external programs - using arcan as a display server. The
 * domain socket is used to find a connection point to the parent.
 * These points has to be explicitly set-up and managed by the
 * parent (from the LUA side, target_alloc).
 *
 * 3. hijacked programs - code injected into other processes,
 * as a means of exfiltrating data. These are launched as compliant
 * frameservers, but additional data (which descriptors should
 * be used to communicate etc.) are conveyed through environmental
 * variables.
 */

/*
 * The IPC connection points (which may vary slightly based on
 * connection method, e.g. authorative or non-authorative, are
 * the shmpage, a socket and three semaphores.
 *
 * The way these can reach the process vary; by being passed as
 * an environment variable (ARCAN_CONNPATH, and for additional
 * authentication, ARCAN_CONNKEY).
 */

/*
 * Compile-time constants that define the size and layout
 * of the shared structure.
 */

/*
 * Number of allowed events in the in-queue and the out-queue,
 * should be kept low and monitored for use.
 */
#define PP_QUEUE_SZ 32
static const int ARCAN_SHMPAGE_QUEUE_SZ = PP_QUEUE_SZ;

/*
 * Default audio storage / transfer characteristics
 * The gist of it is to keep this interface trivial "for basic sound"
 * now and prepare an (optional) "advanced toggle" later with
 * the whole surround sound in floating point at high sample-rates
 * thing.
 */
static const int ARCAN_SHMPAGE_MAXAUDIO_FRAME = 192000;
static const int ARCAN_SHMPAGE_SAMPLERATE = 44100;
static const int ARCAN_SHMPAGE_ACHANNELS = 2;
static const int ARCAN_SHMPAGE_SAMPLE_SIZE = sizeof(short);

/*
 * This is a hint to resamplers used as part of whatever
 * frameserver uses this interface, on a scale from 1..10,
 * how do we value audio resampling quality
 */
static const int ARCAN_SHMPAGE_RESAMPLER_QUALITY = 5;

#ifndef PP_SHMPAGE_MAXW
#define PP_SHMPAGE_MAXW 4096
#endif

#ifndef PP_SHMPAGE_MAXH
#define PP_SHMPAGE_MAXH 2048
#endif

#ifndef PP_SHMPAGE_SHMKEYLIM
#define PP_SHMPAGE_SHMKEYLIM 78
#endif

/*
 * This is somewhat of a formatting hint; for now,
 * only RGBA32 buffers are actually used (and the streaming
 * texture uploads in the main process will treat the
 * input as that. It is suggested that other formats
 * and packing strategies (e.g. hardware YUV) still
 * pack in 4x8bit channels interleaved and then hint the
 * conversion in the shader used.
 *
 * For future cases when the API opens up a bit,
 * additional color formats will be passed as GL buffer-references
 * rather than full copies on the shmif.
 */
static const int ARCAN_SHMPAGE_VCHANNELS = 4;
static const int ARCAN_SHMPAGE_MAXW = PP_SHMPAGE_MAXW;
static const int ARCAN_SHMPAGE_MAXH = PP_SHMPAGE_MAXH;

/*
 * The final shmpage size will be a function of the constants
 * above, along with a few extra bytes to make room for the
 * header structure (audioframe * 3 / shmpage_achannels),
 * legacy from ffmpeg.
 */
static const int ARCAN_SHMPAGE_AUDIOBUF_SZ = 288000;

#ifndef RGBA
#define RGBA(r, g, b, a)( ((uint32_t)(a) << 24) | ((uint32_t) (b) << 16) |\
((uint32_t) (g) << 8) | ((uint32_t) (r)) )
#endif

static const int ARCAN_SHMPAGE_VIDEOBUF_SZ = 8294400;

#ifndef PP_SHMPAGE_MAXSZ
#define PP_SHMPAGE_MAXSZ 48294400
#endif

/*
 * If this define is overridden, make sure that the starting dimensions
 * actually fit the minimal (32x32 + buffers + sizeof(struct)
 */
#ifndef PP_SHMPAGE_STARTSZ
#define PP_SHMPAGE_STARTSZ 2014088
#endif

/*
 * Some plaforms/implementations do not support dynamically growing/shrinking
 * shared memory. To cope, we principally have two methods;
 * one is to overcommit -- always allocate the limit and then just re-map
 * the same page with lower / greater sizes.
 *
 * The other is to allocate a new shared memory with the new size.
 * This increases the number of context switches and introduces the constraint
 * that the event-queues should be EMPTY on both sides during resize calls.
 */
#ifdef ARCAN_SHMIF_OVERCOMMIT
static const int ARCAN_SHMPAGE_START_SZ = PP_SHMPAGE_MAXSZ;
#else
static const int ARCAN_SHMPAGE_START_SZ = PP_SHMPAGE_STARTSZ;
#endif

static const int ARCAN_SHMPAGE_MAX_SZ = PP_SHMPAGE_MAXSZ;

enum arcan_shmif_type {
	SHMIF_INPUT = 1,
	SHMIF_OUTPUT
};

enum arcan_shmif_sigmask {
/* can combine transfers */
	SHMIF_SIGVID = 1,
	SHMIF_SIGAUD = 2,

/* blocking vs. accepting data corruption (partial) trade-off          */
  SHMIF_SIGBLK_FORCE = 0, /* wait for synchronous releasefrom parent   */
	SHMIF_SIGBLK_NONE  = 4, /* never wait, always overwrite              */
	SHMIF_SIGBLK_ONCE  = 8  /* non-blocking unless already frame pending */
};

/*
 * Tracking context for a frameserver connection,
 * will only be used "locally" with references
 */
struct arcan_shmif_cont {
	struct arcan_shmif_page* addr;

/* offset- pointers into addr, can change between calls to
 * shmif_ functions so aliasing is not recommended */
	uint32_t* vidp;
	int16_t* audp;

/*
 * used in integrity_check, should never be != 0 and that
 * would be indicative of poor / broken vidp/audp- dependant
 * code.
 */
	int16_t oflow_cookie;

/* maintain a connection to the shared memory handle in order
 * to handle resizing (on platforms that support it, otherwise
 * define ARCAN_SHMIF_OVERCOMMIT which will only recalc pointers
 * on resize */
	intptr_t shmh;
	size_t shmsize;

/*
 * Used on some platforms as a control channel for transferring
 * descriptors. This may refer to the initial socket connection
 * (for external connections) or to a pre-existing descriptor
 * (authorative) with the number conveyed in the environment.
 */
	file_handle dpipe;

/*
 * handles are exposed in the struct rather than in (priv) but
 * manually manipulating them is not recommended. When shmpage
 * layout has been refactored into passing events through a
 * socket, this interface will also be replaced with a descriptor-
 * like signalling interface to get working multiplexation rather
 * than polling.
 */
	sem_handle vsem;
	sem_handle asem;
	sem_handle esem;

	struct arcan_evctx inev;
	struct arcan_evctx outev;

/*
 * This cookie is a magical value calculated when a page
 * is opened and resized and checked against in each verify_integrity
 * call. It is primarily based on the compiler- perspective of the
 * layout of the shmif_page structure. Deviation between this and
 * the corresponding field in shmif_page is a terminal state transition.
 */
	uint64_t cookie;

	void* user; /* tag provided to the user */
	void* priv; /* used in _control for guard threads etc. */
};

typedef enum arcan_shmif_sigmask(
	*shmif_trigger_hook)(struct arcan_shmif_cont*);

struct arcan_shmif_page {
/*
 * These will be set to the ARCAN_VERSION_MAJOR and ARCAN_VERSION_MAJOR
 * defines, a mismatch will cause the integrity_check to fail and
 * both sides may decide to terminate. Thus, they also act as a header
 * guard.
 */
	int8_t major;
	int8_t minor;

/*
 * This is calculated on both ends and is a safe-guard against
 * different compilers generating different padding / ofsets etc.
 * in this structure. See also: cookie in shmcount.
 */
	uint64_t cookie;

/*
 * SLATED FOR REFACTOR
 * should be moved to a FD based channel with a protobuf- managed
 * (de-)serilization structure. The reason this is currently kept
 * this way is to fixate the event- ontology after which we can
 * move the shmif bits to a library format.
 */
	struct {
		struct arcan_event evqueue[ PP_QUEUE_SZ ];
		uint32_t front, back;
	} childdevq, parentevq;

/* will be checked frequently, likely before transfers as it means
 * that shmcontents etc. will be invalid */
	volatile int8_t resized;

/*
 * On a resize, parent will update segment_size. If this differs from
 * the previously known size (tracked in cont), the segment should be remapped.
 * Parent ignores the value here and maintains a local copy.
 * This allows the parent to dictate if segments should be shrunk
 * to optimal- fit video- buffer or not based on the larger
 * memory subsystems.
 */
	size_t segment_size;

/* when released, it is assumed that the parent or child or both
 * has failed and everything should be dropped and terminated */
	volatile uintptr_t dms;

/*
 * flipped whenever a buffer is ready to be synched,
 * polled repeatedly by the parent (or child for the case of an
 * encode frameserver) then the corresponding sem_handle is used
 * as a wake-up trigger.
 *
 * Note that underneath the surface, this are currently just checked
 * and written to in a > non atomic way <. It's trivial to switch
 * to atomic test and sets, but they are currently kept this way
 * to control/check how "non-compliant" manipulation and race-conditions
 * manifest.
 */
	volatile uint8_t aready;
	volatile uint8_t vready;

/*
 * Current video output dimensions, if these deviate from the
 * agreed upon dimensions (i.e. change w,h and set the resized flag to !0)
 * the parent will simply ignore the data presented.
 */
	size_t w, h;

/*
 * this flag is set if the row-order is inverted (i.e. Y starts at
 * the bottom and moves up rather than upper left as per arcan default)
 * and used as a hint to the rendering subsystem in order to
 * just adjust the texture coordinates used (to spare memory bandwidth).
 */
	uint8_t glsource;

/*
 * some data-sources (e.g. video-playback) may take advantage
 * of buffering in the parent process and keep presentation/timing/queue
 * management there. In those cases, a relative ms timestamp
 * is present in this field and the main process gets the happy job
 * of trying to compensate for synchronization.
 */
	int64_t vpts;

/*
 * For some cases, the child doesn't always have access to
 * whichever process is responsible for managing "the other end"
 * of this interface. The native PID is therefore set here,
 * and for the local monitoring thread (that frequently checks
 * to see if the parent is still alive as a monitoring target
 * as input to how to behave if the parent has died.
 */
	process_handle parent;

/* while video transfers are done progressively, one frame at a time,
 * the audio buffering is a bit more lenient. This value signals
 * how much of the audio buffer is actually used, and can be
 * manipulated by both sides (only one at a time, the asem decides who) */
	uint32_t abufused;
};

/*
 * The following functions are support functions used to manage
 * the shared memory pages, presented in the order they are likely
 * to be used
 */

enum SHMIF_FLAGS {
/* by default, the connection IPC resources are unlinked, this
 * may not always be desired (debugging, monitoring, ...) */
	SHMIF_DONT_UNLINK = 1,

/* a guard thread is usually allocated to monitor the status of
 * the server, setting this flag explicitly prevents the creation of
 * that thread */
	SHMIF_DISABLE_GUARD = 2,

/* failure to acquire a segment should be exit(EXIT_FAILURE); */
	SHMIF_ACQUIRE_FATALFAIL = 4
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

/* (frameserver use only) helper function to implement
 * request/synchronization protocol to issue a resize of the
 * output video buffer.
 *
 * This request can be declined (false return value) and
 * should be considered expensive (may block indefinitely). Anything
 * that depends on the contents of the shared-memory dependent
 * parts of shmif_cont (eventqueue, vidp/audp, ...) should be considered
 * invalid during/after a call to shmif_resize and the function will
 * internally rebuild these structures.
 *
 * This function is not thread-safe -- While a resize is pending,
 * none of the other operations (drop, signal, en/de- queue) are safe.
 * If events are managed on a separate thread, these should be treated
 * in mutual exclusion with the size operation.
 *
 * There are four possible outcomes here:
 * a. resize fails, dimensions exceed hard-coded limits.
 * b. resize succeeds, vidp/audp are re-aligned.
 * c. resize succeeds, the segment is truncated to a new size.
 * d. resize succeeds, we switch to a new shared memory connection.
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

/*
 * Additional buffers can be allocated, and non-authoritative,
 * (i.e. processes that are outside the direct control of the parent)
 * can optionally be allowed to connect through a similar mechanism;
 * For a new connection to a pre-existing frameserver,
 * the arcan_frameserver_spawn_subsegment (lua: target_alloc) function
 * which pushes an event on the queue notifying which key to access
 * the new connection under. The management / setup is exactly like
 * the main one, including separate eventqueues.
 *
 * For a new external connection, look at the defines below. It's
 * implemented through an event socket with a pre-set prefix
 * (i.e. /tmp/arcan_shm_ or for linux, \0arcan_shm_ a (user-defined
 * or random) key, an optional code and a predefined UMASK.
 * It is up to the script / engine implementation to communicate
 * this to the external process. The main difference between the
 * authoritative way and the non-authoritiative way is that the latter
 * needs to do a domain socket connection and send an activation message.
 * Until then, the shmif segment is viewed as pending by the main engine.
 *
 * The use of a code is to prevent partially compromised processes to
 * race- the shared namespace (enumerable or not) and, more importantly,
 * for the main engine to have a chance of detecting if this is the case or not
 *
 * Setting the ARCAN_SHM_PREFIX to an empty string disables this approach
 * entirely. For the non-authoritative additional buffer cases, the
 * code is not used, but rather the UID/GID is checked against the monitoring
 * pid in the preexisting frameserver.
 */
#ifdef __linux
#ifndef ARCAN_SHM_PREFIX
#define ARCAN_SHM_PREFIX "\0arcan_shm_"
#endif

/* if the first character does not begin with /, HOME env will be used. */
#else
#ifndef ARCAN_SHM_PREFIX
#define ARCAN_SHM_PREFIX ".arcan_"
#endif
#endif

#ifndef ARCAN_SHM_UMASK
#define ARCAN_SHM_UMASK (S_IRWXU | S_IRWXG)
#endif

#endif
