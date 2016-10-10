/*
 * Copyright 2003-2016, Björn Ståhl
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

enum arcan_frameserver_kinds {
	ARCAN_FRAMESERVER_INPUT,
	ARCAN_FRAMESERVER_OUTPUT,
	ARCAN_FRAMESERVER_INTERACTIVE,
	ARCAN_FRAMESERVER_AVFEED,
	ARCAN_FRAMESERVER_NETCL,
	ARCAN_FRAMESERVER_NETSRV,
	ARCAN_HIJACKLIB
};

struct arcan_frameserver_meta {
/* video */
	uint16_t width;
	uint16_t height;
	char bpp;
	int hints;

/* primarily for feedcopy */
	uint32_t synch_ts;

/* audio */
	unsigned samplerate;
	uint8_t channels;
	uint16_t vfthresh;

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
/* video / audio properties used */
	struct arcan_frameserver_meta desc;
	struct arcan_evctx inqueue, outqueue;
	int queue_mask;

/* original resource, needed for reloading */
	char* source;

	sem_handle vsync, async, esync;

	file_handle dpipe;

	process_handle child;

/* used for connections negotiated via socket (sockout_fd) */
	char sockinbuf[PP_SHMPAGE_SHMKEYLIM];
	char clientkey[PP_SHMPAGE_SHMKEYLIM];
	off_t sockrofs;
	char* sockaddr, (* sockkey);

	struct {
		bool alive;
		bool pbo;
		bool explicit;
		bool local_copy;
		bool no_alpha_copy;
		bool autoclock;
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

/* trackable members to help scriping engine recover on script failure */
	char title[64];
	enum ARCAN_SEGID segid;
	uint64_t guid[2];

	/* hack used to match frameserver generated events (from vid->tag
 * to fsrv->tag) needed to correlate callback in script engine with event */
	intptr_t tag;

/* precalc offsets into mapped shmpage, calculated at resize */
	shmif_pixel* vbufs[FSRV_MAX_VBUFC];
	size_t vbuf_cnt;
	shmif_asample* abufs[FSRV_MAX_ABUFC];
	size_t abuf_cnt;
	size_t abuf_sz;
	shm_handle shm;

/* above pointers are all placed so that if they overflow they should hit this
 * canary -- use for watchpoint in debugging integrity- check for release */
	uint16_t watch_const;
};

/* refactor out when time permits */
typedef struct arcan_frameserver arcan_frameserver;

/* contains both structures for managing movie- playback,
 * both video and audio support functions */
struct frameserver_envp {
	bool use_builtin;
	bool custom_feed;
	bool preserve_env;

	int init_w, init_h;

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
 * Setup a frameserver that is idle until an external party connects
 * through a listening socket, then behaves as an avfeed- style
 * frameserver.
 */
arcan_frameserver* arcan_frameserver_listen_external(const char* key, int fd);

/*
 * Allocate shared and heap memory, reset all members to an
 * empty state and then enforce defaults, returns NULL on failure
 */
arcan_frameserver* arcan_frameserver_alloc();

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
 * Allocate a new frameserver segment, bind it to the same process
 * and communicate the necessary IPC arguments (key etc.) using
 * the pre-existing eventqueue of the frameserver controlled by (ctx)
 */
arcan_frameserver* arcan_frameserver_spawn_subsegment(
	arcan_frameserver* ctx, enum ARCAN_SEGID, int hintw, int hinth, int tag);

/*
 * Take the argument event and add it to the event queue of the target,
 * returns a failure if the event queue in the child is full.
 */
arcan_errc arcan_frameserver_pushevent(arcan_frameserver*, arcan_event*);

/*
 * Poll the frameserver-out eventqueue and push it unto the evctx,
 * filter events that are outside the accepted category / kind maintained
 * in the frameserver struct
 */
void arcan_frameserver_pollevent(arcan_frameserver*, arcan_evctx*);

/*
 * Symbol should only be used by the backend to reach OS specific
 * implementations (_unix.c / win32 )
 */
void arcan_frameserver_dropsemaphores(arcan_frameserver*);
void arcan_frameserver_dropsemaphores_keyed(char*);

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
enum arcan_ffunc_rv arcan_frameserver_socketverify FFUNC_HEAD;
enum arcan_ffunc_rv arcan_frameserver_socketpoll FFUNC_HEAD;
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
 * Determine if the connected end is still alive or not,
 * this is treated as a poll -> state transition
 */
bool arcan_frameserver_validchild(arcan_frameserver* ctx);

/*
 * Guarantee that any and all child processes associated or spawned
 * from the child connected will be terminated in as clean a
 * manner as possible (thus may not happen immediately although
 * contents of the struct will be reset)
 */
void arcan_frameserver_killchild(arcan_frameserver* ctx);

/*
 * Release any shared memory resources associated with the frameserver
 */
void arcan_frameserver_dropshared(arcan_frameserver* ctx);

/*
 * PROCEED WITH EXTREME CAUTION, _configure,
 * _spawn, _free etc. are among the more complicated functions
 * in the entire project, any changes should be thoroughly tested for
 * regressions.
 *
 * part of the spawn_server that is shared between
 * the unix and the win32 implementations,
 * assumes that shared memory, semaphores etc. are already in place.
 */
void arcan_frameserver_configure(arcan_frameserver* ctx,
	struct frameserver_envp setup);

arcan_errc arcan_frameserver_free(arcan_frameserver*);

/*
 * Working against the mapped shared memory page is a critical section,
 * there are corner cases and DoS opportunities that could be exploited
 * by the other side that forces us to setup a fallback point in the
 * case of signals e.g. SIGBUS (due to truncate-on-fd).
 */
#include <setjmp.h>
#define TRAMP_GUARD(ERRC, fsrv){\
	jmp_buf tramp;\
	if (0 != setjmp(tramp))\
		return ERRC;\
	arcan_frameserver_enter(fsrv, tramp);\
}

void arcan_frameserver_enter(struct arcan_frameserver*, jmp_buf ctx);
void arcan_frameserver_leave();

size_t arcan_frameserver_default_abufsize(size_t new_sz);

#endif
