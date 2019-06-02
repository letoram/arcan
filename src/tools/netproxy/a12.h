/*
 A12, Arcan Line Protocol implementation

 Copyright (c) 2017-2019, Bjorn Stahl
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

#ifndef HAVE_A12
#define HAVE_A12

struct a12_state;

/*
 * begin a new session (connect)
 */
struct a12_state*
a12_open(uint8_t* authk, size_t authk_sz);

/*
 * being a new session (accept)
 */
struct a12_state*
a12_build(uint8_t* authk, size_t authk_sz);

/*
 * Take an incoming byte buffer and append to the current state of
 * the channel. Any received events will be pushed via the callback.
 */
void a12_unpack(
	struct a12_state*, const uint8_t*, size_t, void* tag, void (*on_event)
		(struct arcan_shmif_cont* wnd, int chid, struct arcan_event*, void*));

/*
 * Set the specified context as the recipient of audio/video buffers
 * for a specific channel id.
 */
void a12_set_destination(
	struct a12_state*, struct arcan_shmif_cont* wnd, uint8_t chid);

/*
 * Returns the number of bytes that are pending for output on the channel,
 * this needs to be rate-limited by the caller in order for events and data
 * streams to be interleaved and avoid a poor user experience.
 *
 * Unless flushed >often< in response to unpack/enqueue/signal, this will grow
 * and buffer until there's no more data to be had. Internally, a12 n-buffers
 * and a12_flush act as a buffer step. The typical use is therefore:
 *
 * 1. [build state machine, open or accept]
 * while active:
 * 2. [if output buffer set, write to network channel]
 * 3. [enqueue events, add audio/video buffers]
 * 4. [if output buffer empty, a12_flush] => buffer size
 */
size_t
a12_flush(struct a12_state*, uint8_t**);

/*
 * Get a status code indicating the state of the connection.
 *
 * <0 = dead/erroneous state
 *  0 = inactive (waiting for data)
 *  1 = processing (more data needed)
 */
int
a12_poll(struct a12_state*);

/*
 * For sessions that support multiplexing operations for multiple
 * channels, switch the active encoded channel to the specified ID.
 */
void
a12_set_channel(struct a12_state*, uint8_t chid);

/*
 * Enable debug tracing out to a FILE, set mask to the bitmap of
 * message types you are interested in messages from.
 */
enum trace_groups {
/* video system state transitions */
	A12_TRACE_VIDEO = 1,

/* audio system state transitions / data */
	A12_TRACE_AUDIO = 2,

/* system/serious errors */
	A12_TRACE_SYSTEM = 4,

/* event transfers in/out */
	A12_TRACE_EVENT = 8,

/* data transfer statistics */
	A12_TRACE_TRANSFER = 16,

/* debug messages, when patching / developing  */
	A12_TRACE_DEBUG = 32,

/* missing feature warning */
	A12_TRACE_MISSING = 64,

/* memory allocation status */
	A12_TRACE_ALLOC = 128,

/* crypto- system state transition */
	A12_TRACE_CRYPTO = 256,

/* video frame compression/transfer details */
	A12_TRACE_VDETAIL = 512,

/* binary blob transfer state information */
	A12_TRACE_BTRANSFER = 1024,
};
void
a12_set_trace_level(int mask, FILE* dst);

/*
 * forward a vbuffer from shm
 */
enum a12_vframe_method {
	VFRAME_METHOD_NORMAL = 0,
	VFRAME_METHOD_RAW_NOALPHA,
	VFRAME_METHOD_RAW_RGB565,
	VFRAME_METHOD_DPNG,
	VFRAME_METHOD_H264,
	VFRAME_METHOD_FLIF,
	VFRAME_METHOD_AV1
};

enum a12_vframe_compression_bias {
	VFRAME_BIAS_LATENCY = 0,
	VFRAME_BIAS_BALANCED,
	VFRAME_BIAS_QUALITY
};

struct a12_vframe_opts {
	enum a12_vframe_method method;
	enum a12_vframe_compression_bias bias;
	bool variable;
	union {
		float bitrate; /* !variable, Mbit */
		int ratefactor; /* variable (ffmpeg scale) */
	};
};

enum a12_aframe_method {
	AFRAME_METHOD_RAW = 0,
};

struct a12_aframe_opts {
	enum a12_aframe_method method;
};

struct a12_aframe_cfg {
	uint8_t channels;
	uint32_t samplerate;
};

/*
 * The following functions provide data over a channel, each channel corresponds
 * to a subsegment, with the special ID(0) referring to the primary segment. To
 * modify which subsegment actually receives some data, use the a12_set_channel
 * function.
 */

/*
 * Forward an event. Any associated descriptors etc.  will be taken over by the
 * transfer, and it is responsible for closing them on completion.
 *
 * Return:
 * false - congestion, flush some data and try again.
 */
bool
a12_channel_enqueue(struct a12_state*, struct arcan_event*);

/* Encode and transfer an audio frame with a number of samples in the native
 * audio sample format and the samplerate etc. configuration that matches */
void
a12_channel_aframe(
	struct a12_state* S, shmif_asample* buf,
	size_t n_samples,
	struct a12_aframe_cfg cfg,
	struct a12_aframe_opts opts
);

/* Encode and transfer a video frame based on the video buffer structure
 * provided as part of arcan_shmif_server. */
void
a12_channel_vframe(
	struct a12_state* S,
	struct shmifsrv_vbuffer* vb,
	struct a12_vframe_opts opts
);

/* Close / destroy a channel, if this is the primary (0) all channels will
 * be closed and the connection terminated */
void
a12_channel_close(struct a12_state*);

#endif
