/*
 A12, Arcan Line Protocol implementation

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
 * the channel.
 */
int
a12_channel_unpack(struct a12_state*, uint8_t**, size_t*);

/*
 * Returns the number of bytes that are pending for output on the channel,
 * this needs to be rate-limited by the caller in order for events and data
 * streams to be interleaved and avoid a poor user experience.
 *
 * Unless flushed >often< in response to unpack/enqueue/signal, this will
 * grow and buffer until there's no more data to be had. Internally, a12
 * double-buffers and a12_channel_flush act as a buffer swap. The typical
 * use is therefore:
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
 *  0 = inactive
 */
int
a12_channel_poll(struct a12_state*);

/*
 * forward an event over the channel, any associated descriptors etc. will be
 * taken over by the channel, and it is responsible for closing them on
 * completion.
 */
void
a12_channel_enqueue(struct a12_state*, struct arcan_event*);

/*
 * Used on an input segment to signal the availability of audio and/or video
 * data to be transferred. Will return false if the channel is blocked due to
 * more ancilliary data being needed.
 */
bool
a12_channel_signal(struct a12_state*, struct arcan_shmif_cont*);

/*
 * Synch the state of the channel to the destination context. This will
 * possibly resize, forward-signal etc. update all alises to dst if
 * modified. The user- field of [dst] will be claimed by the channel
 * until destruction.
 */
bool
a12_channel_synch(struct a12_state* S, struct arcan_shmif_cont* dst);

#endif
