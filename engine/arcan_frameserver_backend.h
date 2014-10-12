/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#ifndef _HAVE_ARCAN_FRAMESERVER
#define _HAVE_ARCAN_FRAMESERVER

/*
 * Missing;
 *  The resource mapping between main engine and frameservers is
 *  1:1, 1 shmpage segment (associated with one vid,aid pair) etc.
 *
 *  There is a need for children to be able to request new video
 *  blocks and for the running script to accept / reject that,
 *  which essentially becomes a new allocation function.
 *
 *  This means that we also need to refcount such blocks, to
 *  account for the possibility of the child to flag it as a "won't use"
 *  and for the parent to indicate that the associated VID has been removed.
 *
 *  There is also a need to specify "special" storage classes,
 *  in particular sharing GL/GLES textures rather than having
 *  to go the readback approach.
 */

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

typedef struct {
/* video */
	uint16_t width;
	uint16_t height;
	uint16_t bpp;

/* audio */
	unsigned samplerate;
	uint8_t channels;
	uint16_t vfthresh;

/* if the user wants detailed
 * info about the latest frame that was
 * uploaded */
	bool callback_framestate;
	unsigned long long framecount;
	unsigned long long dropcount;
	unsigned long long lastpts;

} arcan_frameserver_meta;

struct frameserver_audsrc {
	float inbuf[4096];
	off_t inofs;
	arcan_aobj_id src_aid;
	float l_gain;
	float r_gain;
};

struct frameserver_audmix {
	unsigned n_aids;
	size_t max_bufsz;
	struct frameserver_audsrc* inaud;
};

typedef struct arcan_frameserver {
/* video / audio properties used */
	arcan_frameserver_meta desc;
	struct arcan_evctx inqueue, outqueue;
	int queue_mask;

/* original resource, needed for reloading */
	char* source;

/* OS- specific, defined in general.h */
	shm_handle shm;
	sem_handle vsync, async, esync;
	file_handle sockout_fd;
	process_handle child;
#if _WIN32
	DWORD childp;
#endif

/* used for connections negotiated via socket
 * (sockout_fd) */
	char sockinbuf[PP_SHMPAGE_SHMKEYLIM];
	char* clientkey[PP_SHMPAGE_SHMKEYLIM];
	off_t sockrofs;
	char* sockaddr;

/* transfer */
	unsigned pbo;

	struct {
		bool socksig;
		bool alive;
		bool pbo;
		bool explicit;
		bool subsegment;
		bool no_alpha_copy;
	} flags;

/* for monitoring hooks, 0 entry terminates. */
	arcan_aobj_id* alocks;
	arcan_aobj_id aid;
	arcan_vobj_id vid;

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

	enum ARCAN_SEGID segid;
	bool hijacked;
	char title[64];

/* precalc offsets into mapped shmpage, calculated at resize */
	uint32_t* vidp;
	int16_t* audp;

/* temporary buffer for aligning queue/dequeue events in audio */
	size_t sz_audb;
	off_t ofs_audb, ofs_audp;
	uint8_t* audb;

/* usual hack, similar to load_asynchimage */
	intptr_t tag;
	uint16_t watch_const;
} arcan_frameserver;

/* contains both structures for managing movie- playback,
 * both video and audio support functions */
struct frameserver_envp {
	bool use_builtin;
	bool custom_feed;
	int init_w, init_h;

	union {
		struct {
			const char* const resource;
/* current: movie, libretro, record, net-cl, net-srv */
			const char* const mode;
		} builtin;

		struct {
			char* fname; /* program to execute */
/* key with ARCAN_SHMKEY, ARCAN_SHMSIZE will have
 * its value replaced, key=val, NULL terminated */
			char** argv;
			char** envv;
		} external;

	} args;
};

/* this will either launch the configured frameserver (use_builtin),
 * or act as a more generic execv of a program that
 * supposedly implements the same shmpage interface and protocol. */
arcan_errc arcan_frameserver_spawn_server(arcan_frameserver* dst,
	struct frameserver_envp);

/*
 * setup a frameserver that is idle until an external party connects
 * through a listening socket, then behaves as an avfeed- style
 * frameserver.
 */
arcan_frameserver* arcan_frameserver_listen_external(const char* key);

/* allocate shared and heap memory, reset all members to an
 * empty state and then enforce defaults, returns NULL on failure */
arcan_frameserver* arcan_frameserver_alloc();

/* enable the forked process to start decoding */
arcan_errc arcan_frameserver_playback(arcan_frameserver*);
arcan_errc arcan_frameserver_pause(arcan_frameserver*);
arcan_errc arcan_frameserver_resume(arcan_frameserver*);

/*
 * frameserver_pushfd send the file_handle into the process controlled
 * by the specified frameserver and emits a corresponding event into the
 * eventqueue of the frameserver. returns !ARCAN_OK if the socket isn't
 * connected, wrong type, OS can't handle transfer or the FD can't be
 * transferred (e.g. stdin) fd will always be closed in this function.
 */
arcan_errc arcan_frameserver_pushfd(arcan_frameserver*, int fd);

/*
 * allocate a new frameserver segment, bind it to the same process
 * and communicate the necessary IPC arguments (key etc.) using
 * the pre-existing eventqueue of the frameserver controlled by (ctx)
 */
arcan_frameserver* arcan_frameserver_spawn_subsegment(
	arcan_frameserver* ctx, bool input, int hintw, int hinth, int tag);

/* take the argument event and add it to the event queue of the target,
 * returns a failure if the event queue in the child is full */
arcan_errc arcan_frameserver_pushevent(arcan_frameserver*, arcan_event*);

/* poll the frameserver out eventqueue and push it unto the evctx,
 * filter events that are outside the accepted category / kind */
void arcan_frameserver_pollevent(arcan_frameserver*, arcan_evctx*);

/* symbol should only be used by the backend to reach
 * OS specific implementations (_unix.c / win32 )*/
void arcan_frameserver_dropsemaphores(arcan_frameserver*);
void arcan_frameserver_dropsemaphores_keyed(char*);

/* check if the frameserver is still alive, that the shared memory page
 * is intact and look for any state-changes, e.g. resize (which would
 * require a recalculation of shared memory layout */
void arcan_frameserver_tick_control(arcan_frameserver*);
bool arcan_frameserver_resize(shm_handle*, int, int);

/* default implementations for shared memory framequeue readers,
 * two with separate sync (vidcb audcb) and one where sync is
 * locked to vid only but transfer audio frames into
 * intermediate buffer as well */
ssize_t arcan_frameserver_shmvidcb(int fd, void* dst, size_t ntr);
ssize_t arcan_frameserver_shmaudcb(int fd, void* dst, size_t ntr);
ssize_t arcan_frameserver_shmvidaudcb(int fd, void* dst, size_t ntr);

/* used for streaming data to the frameserver,
 * audio / video interleaved in one synch */
enum arcan_ffunc_rv arcan_frameserver_avfeedframe(enum arcan_ffunc_cmd cmd,
	av_pixel* buf, size_t s_buf, uint16_t width, uint16_t height,
 	unsigned int mode, vfunc_state state);

/* used as monitor hook for frameserver audio feeds */
void arcan_frameserver_avfeedmon(arcan_aobj_id src, uint8_t* buf,
	size_t buf_sz, unsigned channels, unsigned frequency, void* tag);

void arcan_frameserver_avfeed_mixer(arcan_frameserver* dst,
	int n_sources, arcan_aobj_id* sources);
void arcan_frameserver_update_mixweight(arcan_frameserver* dst,
	arcan_aobj_id source, float leftch, float rightch);

/* return a callback function for retrieving appropriate video-feeds */
enum arcan_ffunc_rv arcan_frameserver_videoframe(enum arcan_ffunc_cmd cmd,
	av_pixel* buf, size_t s_buf, uint16_t width, uint16_t height,
	unsigned int mode, vfunc_state state);

enum arcan_ffunc_rv arcan_frameserver_emptyframe(enum arcan_ffunc_cmd cmd,
	av_pixel* buf, size_t s_buf, uint16_t width, uint16_t height,
	unsigned int mode, vfunc_state state);

/* return a callback function for retrieving appropriate audio-feeds */
arcan_errc arcan_frameserver_audioframe(struct
	arcan_aobj* aobj, arcan_aobj_id id, unsigned buffer, void* tag);

/* after a seek operation (or something else that would impose
 * a stall or screw with VPTS vs. audioclock ratio, this function
 * flushes out pending buffers etc. and adjusts clocks */
arcan_errc arcan_frameserver_flush(arcan_frameserver* fsrv);

/* simplified versions of the above that
 * ignores PTS/DTS and doesn't use the framequeue */
enum arcan_ffunc_rv arcan_frameserver_videoframe_direct(
	enum arcan_ffunc_cmd cmd,
	av_pixel* buf, size_t s_buf, uint16_t width, uint16_t height,
	unsigned int mode, vfunc_state state);

arcan_errc arcan_frameserver_audioframe_direct(struct arcan_aobj* aobj,
	arcan_aobj_id id, unsigned buffer, void* tag);

/*
 * return if the child process associated with the frameserver context
 * is still alive or not
 */
bool arcan_frameserver_validchild(arcan_frameserver* ctx);

/*
 * guarantee that any and all child processes associated or spawned
 * from the child connected will be terminated in as clean a
 * manner as possible (thus may not happen immediately although
 * contents of the struct will be reset)
 */
void arcan_frameserver_killchild(arcan_frameserver* ctx);

/*
 * release any shared memory resources associated with the frameserver
 */
void arcan_frameserver_dropshared(arcan_frameserver* ctx);

/* PROCEED WITH EXTREME CAUTION, _configure,
 * _spawn, _free etc. are among the more complicated functions
 * in the entire project, any changes should be
 * thoroughly tested for regressions.
 *
 * part of the spawn_server that is shared between
 * the unix and the win32 implementations,
 * assumes that shared memory, semaphores etc. are already in place. */
void arcan_frameserver_configure(arcan_frameserver* ctx,
	struct frameserver_envp setup);

arcan_errc arcan_frameserver_free(arcan_frameserver*);
#endif
