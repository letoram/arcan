/*
 * Copyright (c) Björn Ståhl 2014,
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms,
 * with or without modification, are permitted provided
 * that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above
 * copyright notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its contributors
 * may be used to endorse or promote products derived from this software without
 * specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef _HAVE_SYNC_PLOT
#define _HAVE_SYNC_PLOT

/*
 * Note that these functions, internally, assume RGBA32- at the moment,
 * slated for refactor when we clean-up shmif support formats.
 */

typedef uint64_t timestamp_t;

/*
 * plot key-events against a sliding window
 */
struct synch_graphing {
	enum synch_state {
		SYNCH_NONE,
		SYNCH_OVERLAY,
		SYNCH_INDEPENDENT
	} state;

	void (*update)(struct synch_graphing*, float period, const char* msg);

/* signal whenever parent provides non-periodic input */
	void (*mark_input)(struct synch_graphing*, timestamp_t);

/* signal when heuristics decide that it's not worth transferring */
	void (*mark_drop)(struct synch_graphing*, timestamp_t);

/* signal the audio buffer size before sending */
	void (*mark_abuf_size)(struct synch_graphing*, unsigned);

/* mark the beginning of frame creation */
	void (*mark_start)(struct synch_graphing*, timestamp_t);

/* mark the end of frame creation */
	void (*mark_stop)(struct synch_graphing*, timestamp_t);

/* register the cost of the specific frame (stop-start) */
	void (*mark_cost)(struct synch_graphing*, unsigned);

/* register the transfer- completion point and the cost */
	void (*mark_transfer)(struct synch_graphing*, timestamp_t, unsigned);

/* deallocate private resources, will also set the calling pointer
 * to NULL, if state is INDEPENDENT, the associated contest will
 * be terminated */
	void (*free)(struct synch_graphing**);

/* dimensions have changed or similar */
	void (*cont_switch)(struct synch_graphing*, struct arcan_shmif_cont*);

	void* priv;
};

/*
 * populate a synch_graphing structure with the apropriate callbacks etc.
 * if overlay is set to false, the context will manage itself (as long
 * as update is called periodically), otherwise resize() member must
 * be called to reflect changes in the shmcont.
 */
struct synch_graphing* setup_synch_graph(
	struct arcan_shmif_cont* cont, bool overlay);

#endif
