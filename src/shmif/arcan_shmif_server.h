/*
 Shmif- server library
 Copyright (c) 2017, Bjorn Stahl
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
 */
bool shmifsrv_enter();
void shmifsrv_leave();

/*
 * Allocate, prepare and transfer a new sub-segment to the frameserver
 * referenced by [dst] (!NULL). [segid] specifies the type of the subsegment
 * (MUST match REQID if it is in response to a SEGREQ event)
 */
struct shmifsrv_client*
	shmifsrv_send_subsegment(struct shmifsrv_client* dst, int segid,
	size_t init_w, size_t init_h, int reqid);

/*
 * Allocate and prepare a frameserver connection point accessible via the name
 * [name](!NULL) an (optional) authentication key and the permission mask of
 * the target socket. The function returns a valid server context or NULL with
 * the reason for failure in statuscode.
 */
struct shmifsrv_client*
	shmifsrv_allocate_connpoint(const char* name, const char* key,
	mode_t permission, int* statuscode);

/*
 * Setup a connection-less frameserver, meaning that all primitives and
 * allocation is passed through other means than
 */
struct shmifsrv_client* shmifsrv_prepare_client();

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
bool shmifsrv_frameserver_tick(struct shmifsrv_client*);

/*
 * Polling routine for pumping synchronization actions that are not aligned to
 * _tick. Can be used independently as part of a loop or as a reaction to
 * incoming data on the event descriptor.
 */
enum shmifsrv_status {
	CLIENT_VBUFFER_READY = 1,
	CLIENT_ABUFFER_READY = 2,
	CLIENT_RESYNCHED = 4,
	CLIENT_WAITING = 8,
	CLIENT_VERIFYING = 16,
	CLIENT_DEAD
};
enum shmifsrv_status shmifsrv_poll(struct shmifsrv_client*);

/*
 * [CRITICAL]
 * Retrieve information on the saturation of each event queue.
 */
void shmifsrv_queue_status(struct shmifsrv_client*,
	size_t* in_queue, size_t* out_queue, size_t* queue_lim);

/*
 * [CRITICAL]
 * Push events into the outgoing event-queue. Events that are paired with a
 * file-descriptor transfer should have the corresponding descriptors placed
 * into fds (will be kept open). Any overflows will silently overflow oldest
 * events in the queue, use queue_status function in advance if you don't have
 * any tracking of your own.
 */
void shmifsrv_enqueue_events(struct shmifsrv_client*,
	struct arcan_event*, size_t n, int* fds, size_t nfds);

struct shmifsrv_vbuffer {
	shmif_pixel* buffer;
	size_t w, h, pitch, stride;
};

struct shmifsrv_abuffer {
	shmif_asample* buffer;
	size_t bytes;
	size_t samples;
	size_t samplerate;
	uint8_t chanels;
};

/*
 * [CRITICAL]
 * access the current active video buffer slot in the client. If step is set,
 * the buffer is returned to the client.
 *
 * Audio and video buffers work differently. If a client has negotiated
 * multiple buffers, video will only ever pick the latest one to cut down on
 * latency. For audio, multiple small buffers that match the target device is
 * more important, so there may be many buffers available at any time.
 */
struct shmifsrv_vbuffer shmifsrv_video(struct shmifsrv_client*, bool step);
size_t shmifsrv_audio(struct shmifsrv_client*,
	struct shmifsrv_abuffer*, bool step);

/*
 * Helper, returns the number of monotonic ticks that has occured since
 * last time this function was called. Use to judge when to invoke shmifsrv_
 * frameserver_tick.
 */
int shmifsrv_monotonic_tick();
