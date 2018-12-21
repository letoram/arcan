/*
 * Copyright 2003-2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_FRAMESERVER
#define _HAVE_ARCAN_FRAMESERVER

#define FSRV_MAX_VBUFC ARCAN_SHMIF_VBUFC_LIM
#define FSRV_MAX_ABUFC ARCAN_SHMIF_ABUFC_LIM

/*
 * The following functions are implemented in the platform layer;
 * arcan_frameserver_validchild,
 * arcan_frameserver_killchild,
 * arcan_frameserver_dropshared,
 * arcan_frameserver_pushfd,
 * arcan_frameserver_spawn_server
 */

enum arcan_playstate {
	ARCAN_PASSIVE = 0,
	ARCAN_BUFFERING = 1,
	ARCAN_PLAYING = 2,
	ARCAN_PAUSED = 3
};

/*
 * This substructure is a cache of the negotiated state, i.e.  the server side
 * view of the agreed upon use and limits of the contents of the shared memory
 * page.
 */
struct arcan_frameserver_meta {
/* video */
	uint16_t width;
	uint16_t height;
	char bpp;
	int hints, pending_hints;
	bool rz_flag;

/* primarily for feedcopy */
	uint32_t synch_ts;

/* audio */
	unsigned samplerate;
	uint8_t channels;
	uint16_t vfthresh;

/* subprotocol area, these will all be directly memory mapped,
 * so access need to happen in a shm- criticial section */
	size_t apad;
	unsigned aproto;

/* relative addr->adata */
	struct arcan_shmif_ofstbl aofs;

/* resolved / updated on renegotiation */
	struct {
		struct arcan_shmif_ramp* gamma;
		struct arcan_shmif_vr* vr;
		struct arcan_shmif_vector* vector;
		struct arcan_shmif_hdr* hdr;
		uint8_t gamma_map;
	} aext;

/* statistics for tracking performance / timing */
	bool callback_framestate;
	unsigned long long framecount;
	unsigned long long dropcount;
	unsigned long long lastpts;
};

struct frameserver_audsrc {
	float inbuf[4096];
	off_t inofs;
	arcan_aobj_id src_aid;
	float l_gain;
	float r_gain;
};

struct arcan_frameserver {
/* negotiated state cache */
	struct arcan_frameserver_meta desc;

/* mapped to point into shmpage */
	struct arcan_evctx inqueue, outqueue;
	int queue_mask;

/* original resource, needed for reloading */
	char* source;

/* signaling primitives */
	sem_handle vsync, async, esync;
	file_handle dpipe;

/* if we spawn child, track if it is alive */
	process_handle child;

/*
 * dynamic limits set on a resize request in order to let other parts set
 * restrictions on dimension changes, i.e. not permit a mouse cursor to be
 * max_w*maxh_h etc.
 */
	size_t max_w, max_h;

/* used for connections negotiated via socket (sockout_fd) */
	mode_t sockmode;
/* key read-in buffer */
	char sockinbuf[PP_SHMPAGE_SHMKEYLIM];
	off_t sockrofs;
/* key comparison buffer */
	char clientkey[PP_SHMPAGE_SHMKEYLIM];
/* linked address, passed through shmif_resolve_connpath to get the
 * final string, to handle things like linux private socket namespace */
	char* sockaddr, (* sockkey);

/* list of permitted meta- protocols for this connection */
	unsigned metamask;

/* special transfer state flags */
	struct {
		bool alive : 1;
		bool pbo : 1;
		bool explicit : 1;
		bool local_copy : 1;
		bool no_alpha_copy : 1;
		bool autoclock : 1;
		bool gpu_auth : 1;
		bool no_dms_free : 1;
		bool rz_ack : 1;
		bool locked : 1;
		bool release_pending : 1;
	} flags;

/* if autoclock is set, track and use as metric for firing events */
	struct {
		uint32_t left;
		uint32_t start;
		int64_t frametime;
		bool frame;
	} clock;

/* for monitoring hooks, 0 entry terminates. */
	arcan_aobj_id* alocks;
	arcan_aobj_id aid;
	arcan_vobj_id vid;
	struct {
		struct arcan_framserver* ptr;
		arcan_vobj_id vid;
	} parent;

/* for recording output where we need to mix multiple audio sources */
	struct {
		unsigned n_aids;
		size_t max_bufsz;
		struct frameserver_audsrc* inaud;
	} amixer;

/* playstate control and statistics */
	enum arcan_playstate playstate;
	int64_t lastpts;
	int64_t launchedtime;
	unsigned vfcount;

/* per segment identification cookie */
	uint32_t cookie;

/* state tracking for accelerated buffer sharing, populated by handle
 * events that accompany signalling if enabled */
	struct {
		bool dead;
		int handle;
		size_t stride;
		int format;
	} vstream;

/* temporary buffer for aligning queue/dequeue events in audio, can/should
 * be scrapped after the 0.6 audio refactor */
	size_t sz_audb;
	off_t ofs_audb, ofs_audp;
	uint8_t* audb;

/* trackable members to help scriping engine recover on script failure,
 * populated through allocation or during queuetransfer */
	char title[64];
	enum ARCAN_SEGID segid;
	uint64_t guid[2];

/* hack used to match frameserver generated events (from vid->tag
 * to fsrv->tag) needed to correlate callback in script engine with event */
	intptr_t tag;

/* need to keep the handle around to allow remapping */
	struct shm_handle shm;

/* precalc offsets into mapped shmpage, calculated at resize */
	size_t abuf_cnt;
	size_t abuf_sz;
	size_t vbuf_cnt;

/* for use with rz_ack */
	int rz_known;
	shmif_pixel* vbufs[FSRV_MAX_VBUFC];
	shmif_asample* abufs[FSRV_MAX_ABUFC];

/* above pointers are all placed so that if they overflow they should hit this
 * canary -- use for watchpoint in debugging integrity- check for release */
	uint16_t watch_const;
};

/* refactor out when time permits */
typedef struct arcan_frameserver arcan_frameserver;

/* cover initial launch arguments */
struct frameserver_envp {
	bool use_builtin;

/* set to a valid vid to avoid allocation+feed setup */
	long long custom_feed;

/* should execute with a clean env or inherit existing? */
	bool preserve_env;

	int init_w, init_h;
	size_t prequeue_sz;
	arcan_event** prequeue_events;

/* if we should have a specific set of enabled subprotocols from the start */
	int metamask;

	union {
		struct {
			const char* resource;
/* mode matches the set of allowed archetypes */
			const char* mode;
		} builtin;

		struct {
			char* fname;
			struct arcan_strarr* argv;
			struct arcan_strarr* envv;
			char* resource;
		} external;

	} args;
};

/*
 * This will either launch the configured frameserver (use_builtin),
 * or act as a more generic execv of a program that uses the same
 * shmpage interface and protocol.
 */
arcan_errc arcan_frameserver_spawn_server(arcan_frameserver* dst,
	struct frameserver_envp*);

/*
 * Playback control, temporarly disable buffering / synchronizing.
 * should be used in conjunction with an encoded pause event.
 */
arcan_errc arcan_frameserver_pause(arcan_frameserver*);
arcan_errc arcan_frameserver_resume(arcan_frameserver*);

/*
 * Frameserver_pushfd send the file_handle into the process controlled
 * by the specified frameserver and emits a corresponding event into the
 * eventqueue of the frameserver. returns !ARCAN_OK if the socket isn't
 * connected, wrong type, OS can't handle transfer or the FD can't be
 * transferred (e.g. stdin) fd will always be closed in this function.
 */
arcan_errc arcan_frameserver_pushfd(arcan_frameserver*, arcan_event*, int fd);

/*
 * Take the argument event and add it to the event queue of the target,
 * returns a failure if the event queue in the child is full.
 */
arcan_errc arcan_frameserver_pushevent(arcan_frameserver*, arcan_event*);

/*
 * Check if the frameserver is still alive, that the shared memory page is
 * intact and look for any state-changes, e.g. resize (which would require a
 * recalculation of shared memory layout. These are used by the various
 * feedfunctions and should not need to be triggered elsewhere.
 * If a resize/activation occurs, it will switch the active ffunc on the outer
 * video object to [ff] (value from ffunc_lut.h)
 */
bool arcan_frameserver_tick_control(arcan_frameserver* src, bool tick, int ff);

/*
 * Poll the frameserver-out eventqueue and push it unto the evctx,
 * filter events that are outside the accepted category / kind maintained
 * in the frameserver struct
 */
void arcan_frameserver_pollevent(arcan_frameserver*, arcan_evctx*);

/*
 * Attempt to retrieve a copy of the current LUT-ramps for a specific
 * display index, returns false if the client has not requested extended
 * metadata, true otherwise.
 *
 * REQUIRED: fsrv-ctx with negotiated CM subproto, LOCK-CALL
 */
bool arcan_frameserver_getramps(arcan_frameserver*,
	size_t index,
	float* table, size_t table_sz,
	size_t* ch_sz
);

/*
 * Attempt to update a specific display index with new ramps and an (optional)
 * edid metadata block.
 *
 * table is a packed array of values in [0..1] (will be mapped or filtered into
 * the range and precision expected by the device) and ch_sz describes how many
 * elements of the table should be assigned to each LUT plane
 *
 * Returns false if the client has not requested extended display metadata,
 * true otherwise.
 *
 * EXPECTS:
 * COUNT_OF(ch_sz) = SHMIF_CMRAMP_PLIM,
 * SIZE_OF(table) = SUM_OF(ch_sz) <= SHMIF_CMRAMP_ULIM
 *
 * REQUIRED: fsrv-ctx with negotiated CM subproto, LOCK-CALL
 */
bool arcan_frameserver_setramps(arcan_frameserver*,
	size_t index,
	float* table, size_t table_sz,
	size_t ch_sz[],
	uint8_t* edid, size_t edid_sz
);

/*
 * Various transfer- and buffering schemes. These should not be mapped
 * into video- feedfunctions by themeselves, but managed through
 * the arcan_ffunc_lut.h
 */
#ifdef FRAMESERVER_PRIVATE

enum arcan_ffunc_rv arcan_frameserver_avfeedframe FFUNC_HEAD;
enum arcan_ffunc_rv arcan_frameserver_feedcopy FFUNC_HEAD;
enum arcan_ffunc_rv arcan_frameserver_emptyframe FFUNC_HEAD;
enum arcan_ffunc_rv arcan_frameserver_vdirect FFUNC_HEAD;
enum arcan_ffunc_rv arcan_frameserver_verifyffunc FFUNC_HEAD;
enum arcan_ffunc_rv arcan_frameserver_pollffunc FFUNC_HEAD;
enum arcan_ffunc_rv arcan_frameserver_nullfeed FFUNC_HEAD;

#endif

/*
 * Used as monitor hook for frameserver audio feeds, will be reworked
 * to a LUT- style callback system similar to that of videofeeds in 0.6
 */
void arcan_frameserver_avfeedmon(arcan_aobj_id src, uint8_t* buf,
	size_t buf_sz, unsigned channels, unsigned frequency, void* tag);

arcan_errc arcan_frameserver_audioframe_direct(struct arcan_aobj* aobj,
	arcan_aobj_id id, unsigned buffer, bool cont, void* tag);

/*
 * Update audio mixing settings for a monitoring frameserver that
 * has multiple audio sources
 */
void arcan_frameserver_avfeed_mixer(arcan_frameserver* dst,
	int n_sources, arcan_aobj_id* sources);

void arcan_frameserver_update_mixweight(arcan_frameserver* dst,
arcan_aobj_id source, float leftch, float rightch);

/*
 * After a seek operation (or something else that would impose
 * a stall or screw with VPTS vs. audioclock ratio, this function
 * flushes out pending buffers etc. and adjusts clocks.
 */
arcan_errc arcan_frameserver_flush(arcan_frameserver* fsrv);

/*
 * Guarantee that any and all child processes associated or spawned
 * from the child connected will be terminated in as clean a
 * manner as possible (thus may not happen immediately although
 * contents of the struct will be reset)
 */
void arcan_frameserver_killchild(arcan_frameserver* ctx);

/*
 * Take an allocated frameserver context and realise the settings
 * in setup on it.
 */
void arcan_frameserver_configure(arcan_frameserver* ctx,
	struct frameserver_envp setup);

arcan_errc arcan_frameserver_free(arcan_frameserver*);

/*
 * Prevent any attempt at pushing or forwarding buffers from going through.
 * This effectively locks clients that are waiting for ack on a buffer transfer
 * to continue.
 *
 * If [state] is set to 0, buffer transfers are always permitted
 * If [state] is set to 1, buffer transfers are not permitted
 * If [state] is set to 2, buffer transfers are permitted, but clients are
 * held until explicitly released via arcan_frameserver_releaselock
 *
 * Toggling buffer access on or off does not immediately trigger any evaluation
 * on pending clients, that should be managed elsewhere (arcan_video_pollfeed).
 */
void arcan_frameserver_lock_buffers(int state);

/*
 * IF the frameserver is in pending-release state, this will send signals
 * unlock semaphores and clear the flag. This is used in combination with
 * lock_buffers by the conductor.
 */
int arcan_frameserver_releaselock(struct arcan_frameserver* tgt);

/*
 * helper functions that tie together the platform/.../frameserver.c
 * with allocation, member matching, presets etc.
 */
arcan_frameserver* platform_launch_listen_external(
	const char* key, const char* pw, int fd, mode_t mode, uintptr_t tag);

struct arcan_frameserver* platform_launch_fork(
	struct frameserver_envp* setup, uintptr_t tag);

arcan_frameserver* platform_launch_internal(const char* fname,
	struct arcan_strarr* argv, struct arcan_strarr* envv,
	struct arcan_strarr* libs, uintptr_t tag);

/*
 * Working against the mapped shared memory page is a critical section,
 * there are corner cases and DoS opportunities that could be exploited
 * by the other side that forces us to setup a fallback point in the
 * case of signals e.g. SIGBUS (due to truncate-on-fd).
 */
#define TRAMP_GUARD(ERRC, fsrv){\
	jmp_buf tramp;\
	if (0 != setjmp(tramp))\
		return ERRC;\
	platform_fsrv_enter(fsrv, tramp);\
}

#endif
