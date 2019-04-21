/*
 Shmif- server library
 Copyright (c) 2017-2018, Bjorn Stahl
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

/*
 * This is used to be able to write headless servers for shmif, in order to
 * easier facilitate testing, proxying and nesting of shmif connections.  It
 * (re-) uses the same setup, platform and similar code from the normal arcan
 * build, but with different event-routing and polling.
 */
struct shmifsrv_client;

/*
 * Used for setup when we need to launch an external program with working/
 * unique connection primitives from the start. If init_w and init_h are 0, the
 * client needs to set its size on its own, or be told of it during the
 * preroll- event stage.
 */
struct shmifsrv_envp {
	const char* path;
	const char** argv;
	const char** envv;

	size_t init_w;
	size_t init_h;
};

enum shmifsrv_status {
	SHMIFSRV_OK = 1,
	SHMIFSRV_INVALID_ARGUMENT = -1,
	SHMIFSRV_OUT_OF_MEMORY = -2,
};

/*
 * Depending on underlying OS, there are a number of recoverable shared memory
 * related errors that can occur while reading/writing, but it is typically a
 * sign of a malicious client. To work around this, we rely on setjmp/longjmp
 * like behavior. This is wrapped with these functions, like so:
 *
 * if (!shmifsrv_enter(conn)){
 *     something_bad_happened, anything between enter and leave
 *     may be in a partial state, kill/clean.
 *
 *     return;
 * }
 *
 * sensitive functions (marked [CRITICAL])
 *     shmifsrv_queuestatus
 *     shmifsrv_video
 *     shmifsrv_audio
 *
 * shmifsrv_leave();
 *
 * only sensitive functions ([CRITICAL]) should be called within the
 * _enter/_leave critical region. BEWARE that this function MAY temporarily
 * modify the signal mask for some signals (e.g. SIGBUS).
 */
bool shmifsrv_enter(struct shmifsrv_client*);
void shmifsrv_leave();

/*
 * Allocate, prepare and transfer a new sub-segment to the frameserver
 * referenced by [dst] (!NULL). [segid] specifies the type of the subsegment
 * (MUST match REQID if it is in response to a SEGREQ event)
 * [idtok] is used as a reference in a client addressable namespace in order
 * to set spatial hints.
 */
struct shmifsrv_client*
	shmifsrv_send_subsegment(struct shmifsrv_client* dst, int segid,
	size_t init_w, size_t init_h, int reqid, uint32_t idtok);

/*
 * Allocate and prepare a frameserver connection point accessible via the name
 * [name](!NULL) an (optional) authentication key and the permission mask of
 * the target socket. The function returns a valid server context or NULL with
 * the reason for failure in statuscode.
 *
 * Design / legacy quirk:
 * The listening socket is contained within shmifsrv_client and should be
 * extracted using shmifsrv_client_handle. If a client connects (see
 * shmifsrv_poll), this handle with mutate internally to that of the accepted
 * connection and it is the responsibility of the caller to either close
 * the descriptor or use it as the [fd] argument to this function in order
 * to re-open the connection point.
 *
 * Example use:
 * struct shmifsrv_client* cl =
 *   shmifsrv_allocate_connpoint("demo", NULL, S_IRWXU, -1);
 *
 * if (!cl)
 *  error("couldn't allocate resources");

 * int server_fd = shmifsrv_client_handler(cl);
 * while(cl){
 *    ... poll / wait in activity on server_fd ...
 *    dispatch_client(cl); (have a thread/loop that runs shmifsrv_poll)
 *    cl = shmifsrv_allocate_connpoint("demo", NULL, S_IRWXU, server_fd);
 * }
 *
 */
struct shmifsrv_client* shmifsrv_allocate_connpoint(
	const char* name, const char* key, mode_t permission, int fd);

/*
 * Setup a connection-less frameserver, meaning that all primitives and
 * allocation is passed through means that can be inherited via the client
 * context itself, though it could also be used in the same process space.
 *
 * return NULL on failure, and, if provided, a shmifsrv_error status
 * code.
 */
struct shmifsrv_client* shmifsrv_spawn_client(
	struct shmifsrv_envp env, int* clsocket, int* statuscode, uint32_t idtok);

/*
 * Retrieve an I/O multiplexable handle for mixing into poll() rather
 * than throwing a _poll() call in there whenever there's time.
 */
int shmifsrv_client_handle(struct shmifsrv_client*);

/*
 * This should be invoked at a monotonic tickrate, the common default
 * used here is 25Hz (% 50, 75, 90 as nominal video framerates)
 *
 * Internally, it verifies that the shared resources are in a healthy
 * state, forwards client- managed timers and so on.
 */
bool shmifsrv_tick(struct shmifsrv_client*);

/*
 * Polling routine for pumping synchronization actions and determining
 * updating status. Should be called periodically, as part of the normal
 * processing loop, at least once every shmifsrv_monotonic_tick()/
 */
enum shmifsrv_client_status {
	CLIENT_DEAD = -1,
	CLIENT_NOT_READY = 0,
	CLIENT_VBUFFER_READY = 1,
	CLIENT_ABUFFER_READY = 2
};
int shmifsrv_poll(struct shmifsrv_client*);

/*
 * Free the resources associated with a shmifsrv_client. If this client has
 * been created through shmifsrv_allocate_connpoint and is still in a listening
 * state, the underlying descriptor won't be closed in order for the connpoint
 * to be reused.
 */
void shmifsrv_free(struct shmifsrv_client*);

/*
 * [CRITICAL]
 * Add an event to the outgoing event-queue, will return false if the queue has
 * been saturated (non-responsive client), true otherwise.
 * arcan_shmif_descrevent() can be used to verify if there's supposed to be a
 * descriptor coupled with the event.
 *
 * As a rule, only srv->client events carry descriptors (the exception is
 * accelerated buffer passing) as the client isn't expected to be in a context
 * where it can easily create descriptors to shareable resources (sandboxing)
 * and as a means of closing paths where a client may attempt to starve the
 * parent by filling descriptor tables. The descriptors passed can safely be
 * closed afterwards.
 */
bool shmifsrv_enqueue_event(
	struct shmifsrv_client*, struct arcan_event*, int fd);

/*
 * [CRITICAL]
 * Attempt to dequeue up to [limit] events from the ingoing event queue. Will
 * return the numbers of actual events dequeued. This will perform no additional
 * tracking or management, only raw event access. For assistance with state
 * tracking, feed the events through shmifsrv_process_event.
 */
size_t shmifsrv_dequeue_events(
	struct shmifsrv_client*, struct arcan_event* newev, size_t limit);

/*
 * Retrieve the currently registered type for a client
 */
enum ARCAN_SEGID shmifsrv_client_type(struct shmifsrv_client* cl);

/*
 * Handle some of the normal state-tracking events (e.g. CLOCKREQ,
 * BUFFERSTREAM, FLUSHAUD). Returns true if the event was consumed and no
 * further action is needed.
 */
bool shmifsrv_process_event(
	struct shmifsrv_client*, struct arcan_event* ev);

enum vbuffer_status {
	VBUFFER_OUTPUT = -1,
	VBUFFER_NODATA = 0,
	VBUFFER_OKDATA,
	VBUFFER_HANDLE
};

struct shmifsrv_vbuffer {
	int state;
	shmif_pixel* buffer;
	struct {
		bool origo_ll : 1;
		bool ignore_alpha : 1;
		bool subregion : 1;
		bool srgb : 1;
		bool hwhandles : 1;
	} flags;

	size_t w, h, pitch, stride;

/* desired presentation time since connection epoch, hint */
	uint64_t vpts;

/* only usedated with subregion : true */
	struct arcan_shmif_region region;

/* only used with hwhandles : true */
	size_t formats[4];
	int planes[4];
};

/*
 * [CRITICAL]
 * access the currently active video buffer slot in the client.
 * the buffer is returned to the client. The contents of the buffer are
 * a reference to shared memory, and should thus be explicitly copied out
 * before leaving critical.
 *
 * The [state] field of the returned structure will match vbuffer_status:
 * VBUFFER_OUTPUT - segment is configured for output, don't use this function.
 * VBUFFER_NODATA - nothing available.
 * VBUFFER_OKDATA - buffer is updated.
 * VBUFFER_HANDLE - accelerated opaque handle, descriptor field set.
 *
 * Video buffers can operate in two different modes, accelerated (opaque)
 * handle passing and accelerated. This server library does not currently
 * provide support functions for working with opaque handles.
 */
struct shmifsrv_vbuffer shmifsrv_video(struct shmifsrv_client*);

/* [CRITICAL]
 * Forward that the last known video buffer is no longer interesting and
 * signal a release to the client
 */
void shmifsrv_video_step(struct shmifsrv_client*);

/* [CRITICAL]
 * Flush all pending buffers to the provided drain function. In contrast to
 * _video_step this function has an implicit step stage so all known buffers
 * will be flushed and a waiting client will be woken up.
 */
void shmifsrv_audio(struct shmifsrv_client* cl,
	void (*on_buffer)(shmif_asample* buf,
		size_t n_samples, unsigned channels, unsigned rate, void* tag), void* tag);

/*
 * [THREAD_UNSAFE]
 * This is a helper function that returns the number of monotonic ticks
 * since the last time this function was called. It is thus a global state
 * shared by many clients, along with the optional time to next tick. The
 * typical pattern is:
 *  [start]
 *   shmifsrv_monotonic_rebase();
 *
 *  [loop]
 *   num = shmifsrv_monotonic_tick(NULL);
 *   while (num-- > 0)
 *   	each_client(cl){ shmifsrv_tick( cl )
 */
int shmifsrv_monotonic_tick(int* left);

/*
 * [THREAD_UNSAFE]
 * Explicitly rebase the shared clock counter due to a large stall,
 * pause, global suspend action and so on.
 */
void shmifsrv_monotonic_rebase();
