/*
 A12, Arcan Line Protocol implementation

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

#ifndef HAVE_A12
#define HAVE_A12

struct a12_state;

/*
 * begin a new session (connect)
 */
struct a12_state*
a12_channel_open(uint8_t* authk, size_t authk_sz);

/*
 * being a new session (accept)
 */
struct a12_state*
a12_channel_build(uint8_t* authk, size_t authk_sz);

/*
 * end a session
 */
void
a12_channel_close(struct a12_state*);

/*
 * Take an incoming byte buffer and append to the current state of
 * the channel. Any received events will be pushed via the callback.
 */
void a12_channel_unpack(
	struct a12_state*, const uint8_t*, size_t, void* tag, void (*on_event)
		(struct arcan_shmif_cont* wnd, int chid, struct arcan_event*, void*));

/*
 * Set the specified context as the recipient of audio/video buffers
 * for a specific channel id.
 */
void a12_set_destination(
	struct a12_state*, struct arcan_shmif_cont* wnd, int chid);

/*
 * Returns the number of bytes that are pending for output on the channel,
 * this needs to be rate-limited by the caller in order for events and data
 * streams to be interleaved and avoid a poor user experience.
 *
 * Unless flushed >often< in response to unpack/enqueue/signal, this will grow
 * and buffer until there's no more data to be had. Internally, a12 n-buffers
 * and a12_channel_flush act as a buffer step. The typical use is therefore:
 *
 * 1. [build state machine, open or accept]
 * while active:
 * 2. [if output buffer set, write to network channel]
 * 3. [enqueue events, add audio/video buffers]
 * 4. [if output buffer empty, a12_channel_flush] => buffer size
 */
size_t
a12_channel_flush(struct a12_state*, uint8_t**);

/*
 * Get a status code indicating the state of the channel.
 *
 * <0 = dead/erroneous state
 *  0 = inactive (waiting for data)
 *  1 = processing (more data needed)
 */
int
a12_channel_poll(struct a12_state*);

/*
 * Forward an event over the channel, any associated descriptors etc.
 * will be taken over by the channel, and it is responsible for closing
 * them on completion.
 */
void
a12_channel_enqueue(struct a12_state*, struct arcan_event*);

/*
 * For sessions that support multiplexing operations for multiple
 * channels, switch the active encoded channel to the specified ID.
 */
int
a12_channel_setid(struct a12_state*, int chid);

/*
 * forward a vbuffer from shm
 */
enum a12_vframe_method {
	VFRAME_METHOD_NORMAL = 0,
	VFRAME_METHOD_RAW_NOALPHA,
	VFRAME_METHOD_RAW_RGB565,
	VFRAME_METHOD_DPNG,
	VFRAME_METHOD_H264,
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

/* Enqueue a video frame as part of the specified channel */
void
a12_channel_vframe(
	struct a12_state* S, uint8_t chid, struct shmifsrv_vbuffer* vb,
	struct a12_vframe_opts opts);

#endif
