/*
 Arcan Shared Memory Interface

 Copyright (c) 2012-2016, Bjorn Stahl
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
 * on a key. This need to match with the [target_alloc] behavior
 * (platform/posix/frameserver.c:listen_external) in Arcan.
 */
#ifdef __LINUX
#ifndef ARCAN_SHMIF_PREFIX
#define ARCAN_SHMIF_PREFIX "\0arcan_"
#endif

/* If the first character does not begin with /, HOME env will be used,
 * so default search path will use the safer default ("single-user") */
#else
#ifndef ARCAN_SHMIF_PREFIX
#define ARCAN_SHMIF_PREFIX ".arcan/."
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
 * This will be revised shortly, but modifying still breaks ABI and may
 * break current frameservers.
 */
#ifndef AUDIO_SAMPLE_TYPE
#define AUDIO_SAMPLE_TYPE int16_t
#endif

/*
 * ALWAYS interleaved. for later quality work, all the video/audio
 * buffer format tuning and indirection macros will be moved to separate
 * selectable profile headers, and the packing macros will be redone
 * using C11 type-generic macros.
 */
typedef AUDIO_SAMPLE_TYPE shmif_asample;
static const int ARCAN_SHMIF_SAMPLERATE = 48000;
static const int ARCAN_SHMIF_ACHANNELS = 2;

#ifndef SHMIF_AFLOAT
#define SHMIF_AFLOAT(X) ( (int16_t) ((X) * 32767.0) ) /* sacrifice -32768 */
#endif

#ifndef SHMIF_AINT16
#define SHMIF_AINT16(X) ( (int16_t) ((X)) )
#endif

/*
 * These limits affect ABI as we need to track how much is used in each
 * audiobuffer slot
 */
#define ARCAN_SHMIF_ABUFC_LIM 12
#define ARCAN_SHMIF_VBUFC_LIM 3
/*
 * These are technically limited by the combination of graphics and video
 * platforms. Since the buffers are placed at the end of the struct, they
 * can be changed without breaking ABI though several resize requests may
 * be rejected.
 */
#ifndef PP_SHMPAGE_MAXW
#define PP_SHMPAGE_MAXW 8192
#endif
static const int ARCAN_SHMPAGE_MAXW = PP_SHMPAGE_MAXW;

#ifndef PP_SHMPAGE_MAXH
#define PP_SHMPAGE_MAXH 8192
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
 * We abstract the base type for a pixel and provide a packing macro in order
 * to permit systems with lower memory to switch to uint16 RGB565 style
 * formats, and to permit future switches to higher depth/range.  The
 * separation between video_platform definition of these macros also allows a
 * comparison between engine internals and interface to warn or convert.
 */
#ifndef VIDEO_PIXEL_TYPE
#define VIDEO_PIXEL_TYPE uint32_t
#endif

#ifndef ARCAN_SHMPAGE_VCHANNELS
#define ARCAN_SHMPAGE_VCHANNELS 4
#endif

#ifndef ARCAN_SHMPAGE_DEFAULT_PPCM
#define ARCAN_SHMPAGE_DEFAULT_PPCM 28.34
#endif

static const float shmif_ppcm_default = ARCAN_SHMPAGE_DEFAULT_PPCM;

typedef VIDEO_PIXEL_TYPE shmif_pixel;
#ifndef SHMIF_RGBA
#define SHMIF_RGBA(r, g, b, a)( ((uint32_t)(a) << 24) | ((uint32_t) (b) << 16)\
| ((uint32_t) (g) << 8) | ((uint32_t) (r)) )
#endif

#ifndef SHMIF_RGBA_DECOMP
static inline void SHMIF_RGBA_DECOMP(shmif_pixel val,
	uint8_t* r, uint8_t* g, uint8_t* b, uint8_t* a)
{
	*r = (val & 0x000000ff);
	*g = (val & 0x0000ff00) >>  8;
	*b = (val & 0x00ff0000) >> 16;
	*a = (val & 0xff000000) >> 24;
}
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
 * dimension negotiation will occur. This is needed for shitty platforms that
 * don't provide the means for resizing a handle- backed memory mapped store.
 * Not to point any fingers, but system-level OSX is a pile of shit.
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

/* return immediately unless there is already a transfer pending,
 * currently disabled as the option of having multiple A/V buffers
 * might work out better
	SHMIF_SIGBLK_ONCE = 8
 */
};

struct arcan_shmif_cont;
struct shmif_ext_hidden;
struct arcan_shmif_page;
struct arcan_shmif_initial;

typedef enum arcan_shmif_sigmask(
	*shmif_trigger_hook)(struct arcan_shmif_cont*);

enum ARCAN_FLAGS {
	SHMIF_NOFLAGS = 0,

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
	SHMIF_CONNECT_LOOP = 16,

/* don't implement pause/resume management in backend, forward the
 * events to frontend */
	SHMIF_MANUAL_PAUSE = 32,

/* On crash or disconnect, wait and try to reconnect. If successful,
 * a _RESET event will be enqueued locally with ioev[0].iv == 3.
 * Subsegments will still be lost, and if the connection has been set-up
 * inherited+anonymous, this will still exit like normally. Set this
 * fal to disable RECONNECT attempts entirely. */
	SHMIF_NOAUTO_RECONNECT = 64,

/* for use as flag input to shmif_migrate calls, the default behavior
 * is to only permit migration of the primary segment as there are
 * further client considerations when secondary segments run in different
 * threads along with the problem if subsegment requests are rejected */
	SHMIF_MIGRATE_SUBSEGMENTS = 128,

/*
 * When a connection is initiated, a number of events are gathered until
 * the connection is activated (see arcan_shmif_initial) to determine
 * costly properties in advance. By default, this also sets the initial
 * size of the segment. Set this flag during connection if this behavior
 * would be ignored/overridden by a manual- "data-source controlled"
 * size.
 */
	SHMIF_NOACTIVATE_RESIZE = 256
};

/*
 * Convenience wrapper function of checking environment variables
 * for packed arguments, connection path / key etc.
 *
 * Will also clean-up / reset related environments
 * to prevent propagation.
 *
 * If no arguments could be unpacked, *arg_arr will be set to NULL.
 * If type is set to 0, no REGISTER event will be sent and you will
 * need to send one manually.
 */
struct arg_arr;
struct arcan_shmif_cont arcan_shmif_open(
	enum ARCAN_SEGID type, enum ARCAN_FLAGS flags, struct arg_arr**);

/*
 * arcan_shmif_initial can be used to access initial configured
 * settings (see struct arcan_shmif_initial for details). These values
 * are only valid AFTER a successful call to arcan_shmif_open and ONLY
 * until the first _enqeue, _poll or _wait call.
 *
 * REMEMBER to arcan_shmif_dupfd() on the fonts and render-nodes you
 * want to keep and use as they will be closed, or set the fields to
 * -1 to indicate that you take responsibility.
 *
 * RETURNS the number of bytes in struct (should == sizeof(struct
 * arcan_shmif_initial, if larger, your code is using dated headers)
 * or 0,NULL on failure (bad _cont or _enqueue/ _poll/_wait has been
 * called).
 */
size_t arcan_shmif_initial(struct arcan_shmif_cont*,
	struct arcan_shmif_initial**);

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
 * This is used to migrate a currect connection, authoritative or not,
 * to a non-authoritate connection, possibly using a different connection
 * path and primitive.
 *
 * Will return false on invalid [cont] argument.
 *
 * Current limitations are that subsegments are not re-negotiated.
 * Will return true or false depending on if the transfer was successful
 * or not. If it failed, the referenced main connection is still valid.
 */
enum shmif_migrate_status {
	SHMIF_MIGRATE_OK = 0,
	SHMIF_MIGRATE_BADARG = -1,
	SHMIF_MIGRATE_NOCON = -2,
	SHMIF_MIGRATE_TRANSFER_FAIL = -4
};

enum shmif_migrate_status arcan_shmif_migrate(
	struct arcan_shmif_cont* cont, const char* newpath, const char* key);

/*
 * Using a identification string (implementation defined connection
 * mechanism) If type is set to 0, no REGISTER event will be sent and
 * you will need to send one manually.
 */
struct arcan_shmif_cont arcan_shmif_acquire(
	struct arcan_shmif_cont* parent, /* should only be NULL internally */
	const char* shmkey,    /* provided in ENV or from shmif_connect below */
	enum ARCAN_SEGID type, /* archetype, defined in shmif_event.h */
	enum ARCAN_FLAGS flags, ...
);

/*
 * Used internally by _control etc. but also in ARCAN for mapping the
 * different buffer positions / pointers, very limited use outside those
 * contexts. Returns size: (end of last buffer) - addr
 */
uintptr_t arcan_shmif_mapav(
	struct arcan_shmif_page* addr,
	shmif_pixel* vbuf[], size_t vbufc, size_t vbuf_sz,
	shmif_asample* abuf[], size_t abufc, size_t abuf_sz
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
 * Using the specified shmpage state, synchronization semaphore handle,
 * construct two event-queue contexts. Parent- flag should be set
 * to false for frameservers
 */
void arcan_shmif_setevqs(struct arcan_shmif_page*,
	sem_handle, arcan_evctx* inevq, arcan_evctx* outevq, bool parent);

/* resize/synchronization protocol to issue a resize of the output video buffer.
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
 * Extended version of resize that supports requesting more audio / video
 * buffers for better swap/synch control. abuf_cnt and vbuf_cnt are limited
 * to the constants ARCAN_SHMIF_
 * [PLACEHOLDER] Samplerate can be something different than
 * ARCAN_SHMIF_SAMPLERATE, but this is currently ignored until audio monitoring,
 * mixing and recording has been reworked to account for different samplerates.
 */
struct shmif_resize_ext {
	size_t abuf_sz;
	ssize_t abuf_cnt;
	ssize_t vbuf_cnt;
	ssize_t samplerate;
};

bool arcan_shmif_resize_ext(struct arcan_shmif_cont*,
	unsigned width, unsigned height, struct shmif_resize_ext);
/*
 * Unmap memory, release semaphores and related resources
 */
void arcan_shmif_drop(struct arcan_shmif_cont*);

/*
 * Signal that a synchronized transfer should take place. The contents of the
 * mask determine buffers to synch and blocking behavior.
 *
 * Returns the number of miliseconds that the synchronization reported, and
 * is a value that can be used to adjust local rendering/buffer.
 */
unsigned arcan_shmif_signal(struct arcan_shmif_cont*, enum arcan_shmif_sigmask);

/*
 * Signal a video transfer that is based on buffer sharing rather than on data
 * in the shmpage. Otherwise it behaves like [arcan_shmif_signal] but with a
 * possible reserved variadic argument for future use.
 *
 * If included with DEFINED(WANT_ARCAN_SHMIF_HELPER) and linked with
 * arcan_shmif_ext, abstract support functions for setup and passing are
 * provided (arcan_shmifext_***)
 */
unsigned arcan_shmif_signalhandle(struct arcan_shmif_cont* ctx,
	enum arcan_shmif_sigmask,	int handle, size_t stride, int format, ...);

/*
 * Support function to set/unset the primary access segment (one slot for
 * input. one slot for output), manually managed. This is just a static member
 * helper with no currently strongly negotiated meaning.
 */
struct arcan_shmif_cont* arcan_shmif_primary(enum arcan_shmif_type);
void arcan_shmif_setprimary( enum arcan_shmif_type, struct arcan_shmif_cont*);

/*
 * update the failure callback associated with a context- remapping due to
 * a connection failure. Although ->vidp and ->audp may be correct, there are
 * no guarantees and any aliases to these buffers should be updated in the
 * callback.
 */
void arcan_shmif_resetfunc(struct arcan_shmif_cont*,
	void (*resetf)(struct arcan_shmif_cont*));

/*
 * This should be called periodically to prevent more subtle bugs from
 * cascading and be caught at an earlier stage, it checks the shared memory
 * context against a series of cookies and known guard values, returning
 * [false] if not everything checks out.
 *
 * The guard thread (if active) uses this function as part of its monitoring
 * heuristic.
 */
bool arcan_shmif_integrity_check(struct arcan_shmif_cont*);

struct arcan_shmif_region {
	uint16_t x1,x2,y1,y2;
};

struct arcan_shmif_cont {
	struct arcan_shmif_page* addr;

/* offset- pointers into addr, can change between calls to shmif_ functions so
 * aliasing is not recommended, especially important if (default)
 * connection-crash recovery-reconnect is enabled as the address >may< be
 * changed. If that is a concern, define a handler using the shmif_resetfunc */
  union {
		shmif_pixel* vidp;
		uint8_t* vidb;
	};
	union {
		shmif_asample* audp;
		uint8_t* audb;
	};

/*
 * This cookie is set/kept to some implementation defined value
 * and will be verified during integrity_check. It is placed here
 * to quickly detect overflows in video or audio management.
 */
	int16_t oflow_cookie;

/* use EITHER [audp, abufpos, abufcount] OR [audb, abufused, abufsize]
 * to populate the current audio buffer depending on if you are working on
 * SAMPLES or BYTES. abufpos != 0 will assume the latter */
	uint16_t abufused, abufpos;
	uint16_t abufsize, abufcount;

/* updated on resize, provided to get feedback on an extended resize */
	uint8_t abuf_cnt;

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
 * defaults to ARCAN_SHMIF_SAMPLERATE but may be renegotiated as part
 * of an extended resize. A deviation between the constant samplerate
 * and the negotiated one will likely lead to resampling server-side.
 */
	size_t samplerate;

/*
 * Presentation hints:
 * SHMIF_RHINT_ORIGO_UL (or LL),
 * SHMIF_RHINT_SUBREGION (only synch dirty region below)
 * If MULTIPLE video buffers are used, the SUBREGION applies to BOTH.
 */
	uint8_t hints;

/*
 * IF the contraints:
 * [Hints & SHMIF_RHINT_SUBREGION] and (X2>X1,(X2-X1)<=W,Y2>Y1,(Y2-Y1<=H))
 * valid, [ARCAN] MAY synch only the specified region.
 * Caller manipulates this field, will be copied to shmpage during synch.
 */
  struct arcan_shmif_region dirty;

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
	struct shmif_ext_hidden* privext;
};

struct arcan_shmif_initial {
/* pre-configured primary font and possible fallback, remember to convert
 * to point size to account for density (interop macro
 * SHMIF_PT_SIZE(ppcm, sz_mm) */
	struct {
		int fd;
		int type;
		int hinting;
		float size_mm;
	} fonts[4];

/* output display density and LED- layout hint for subpixel hinting */
	float density;
	int rgb_layout;

/* maximum display output dimensions */
	size_t display_width_px;
	size_t display_height_px;
	uint16_t rate;

	uint8_t lang[4], country[4], text_lang[4];
	float latitude, longitude, elevation;

/* device to use for 3D acceleration */
	int render_node;

/* UTC + */
	int timezone;
};

enum rhint_mask {
	SHMIF_RHINT_ORIGO_UL = 0,
	SHMIF_RHINT_ORIGO_LL = 1,
	SHMIF_RHINT_SUBREGION = 2
};

struct arcan_shmif_page {
/*
 * These will be statically set to the ARCAN_VERSION_MAJOR, ARCAN_VERSION_MAJOR
 * defines, a mismatch will cause the integrity_check to fail and both sides
 * may decide to terminate. Thus, they also act as a header guard. A more
 * precise guard value is found in [cookie].
 */
	int8_t major;
	int8_t minor;

/* [FSRV-REQ, ARCAN-ACK, ATOMIC-NOCARE]
 * Will be checked periodically and before transfers. When set, FSRV should
 * treat other contents of page as UNDEFINED until acknowledged.
 * RELATES-TO: width, height */
	 volatile int8_t resized;

/* [FSRV-SET or ARCAN-SET, ATOMIC-NOCARE]
 * Dead man's switch, set to 1 when a connection is active and released
 * if parent or child detects an anomaly that would indicate misuse or
 * data corruption. This will trigger guard-threads and similar structures
 * to release semaphores and attempt to shut down gracefully.
 */
	volatile uint8_t dms;

/* [FSRV-SET, ARCAN-ACK(fl+sem)]
 * Set whenever a buffer is ready to be synchronized.
 * [vready-1] indicates the buffer index of the last set frame, while
 * vpending are the number of frames with contents that hasn't been
 * synchronzied.
 * [aready-1] indicates the starting index for buffers that have not
 * been synchronized, ring-buffer wrapping the bits that are set.
 */
	volatile atomic_uint aready;
	volatile atomic_uint apending;
	volatile atomic_uint vready;
	volatile atomic_uint vpending;

/* abufused contains the number of bytes consumed in every slot */
	volatile _Atomic uint_least16_t abufused[ARCAN_SHMIF_ABUFC_LIM];

/*
 * Presentation hints, manipulate field in _cont, not here.
 */
	volatile _Atomic uint_least8_t hints;

/*
 * see dirty- field in _cont, manipulate there, not here.
 */
	volatile _Atomic struct arcan_shmif_region dirty;

/* [FSRV-SET]
 * Unique (or 0) segment identifier. Prvodes a local namespace for specifying
 * relative properties (e.g. VIEWPORT command from popups) between subsegments,
 * is always 0 for subsegments.
 */
	uint32_t segment_token;

/* [ARCAN-SET]
 * Calculated once when initializing segment, and verified periodically from
 * both [FSRV] and [ARCAN]. Any deviation MAY have the [dms] be pulled.
 */
	uint64_t cookie;

/*
 * [ARCAN-SET (parent), FSRV-SET (child)]
 * Uses the event model provded in shmif/arcan_event and tightly couples
 * structure / event layout which introduces a number of implementation defined
 * constraints, making this interface a poor choice for a protocol.
 */
	struct {
		struct arcan_event evqueue[ PP_QUEUE_SZ ];
		uint8_t front, back;
	} childevq, parentevq;

/* [ARCAN-SET (parent), FSRV-CHECK]
 * Arcan mandates segment size, will only change during resize negotiation.
 * If this differs from the previous known size (tracked inside shmif_cont),
 * the segment should be remapped.
 *
 * Not all operations will lead to a change in segment_size, OVERCOMMIT
 * builds has its size fixed, and parent may heuristically determine if
 * a shrinking- operation is worth the overhead or not.
 */
	volatile uint32_t segment_size;

/*
 * [FSRV-SET (resize), ARCAN-ACK]
 * Current video output dimensions. If these deviate from the agreed upon
 * dimensions (i.e. change w,h and set the resized flag to !0) ARCAN will
 * simply ignore the data presented.
 */
	volatile _Atomic uint_least16_t w, h;

/*
 * [FSRV-SET (aready signal), ARCAN-ACK]
 * Video buffers are planar transfers of a pre-determined size. Audio,
 * on the other hand, can be appended and consumed by the side that currently
 * holds the synch- semaphore. Note that if the transfered amount for each
 * synch is less than the negotiated abufsize, audio artifacts may be heard.
 */
	volatile _Atomic uint_least16_t abufsize;

/*
 * [FSRV-SET (resize), ARCAN-ACK]
 * Desired buffer samplerate, 0 maps back to ARCAN_SHMIF_SAMPLERATE that
 * should be tuned for the underlying audio system at build-time.
 */
	volatile _Atomic uint_least32_t audiorate;

/*
 * [FSRV-OR-ARCAN-SET]
 * Timestamp hint for presentation of a video frame (using synch-to-video)
 */
	volatile _Atomic uint_least64_t vpts;

/*
 * [ARCAN-SET]
 * Set during segment initalization, provides some identifier to determine
 * if the parent process is still allowed (used internally by GUARDTHREAD).
 * Can also be updated in relation to a RESET event.
 */
	process_handle parent;
};
#endif
