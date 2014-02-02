/* 
 Arcan Shared Memory Interface

 Copyright (c) 2014, Bjorn Stahl
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

#ifndef _HAVE_ARCAN_FRAMESERVER_SHMPAGE
#define _HAVE_ARCAN_FRAMESERVER_SHMPAGE

/* 
 * This header defines the interface and support functions for
 * shared memory- based communication between the arcan parent
 * and each "frameserver". Some parts of this interface is 
 * likely to be changed/expanded in the near future, and is
 * not to be treated as a communication protocol between 
 * processes of different trust-domains/compiler/abi/... origin.
 *
 * The primary use here is for frequent, synchronized transfer
 * of video frames along with related control events. 
 * The events as such can be found in the arcan_event.h header
 *
 * It is assumed that all newly spawned frameservers are allowed
 * ONE video- buffer and ONE audio- buffer to work with. What is
 * currently lacking is the option to request additional ones 
 * (which would also need sematics for handling the corresponding
 * rejection).
 *
 * Additionally, note that the default eventqueue behaviour is
 * lossy, if the parent is not handling them in time, an attempt
 * to enqueue a new event will mean the loss of an older one,
 * unless the event context is explicitly set to lossless.
 *
 * The rational for this rather odd behavior, is in part for
 * historial reasons (initial event- transfers were mostly
 * framestatus updates, or noisy input device data). The longer
 * term is to fixate the event.h structure in a versioned binary
 * protocol (XDR or protobuf).  
 *
 * Other forms of data (files for transferring to a remote source,
 * data sources for state serialization / deserialization) etc.
 * are managed through file-descriptor passing (HANDLES for the 
 * windows crowd). 
 *
 */

/* 
 * Compile-time constants that define the size and layout
 * of the shared structure.
 */

/*
 * Number of allowed events in the in-queue and the out-queue,
 * should be kept low and monitored for use. 
 */
#define PP_QUEUE_SZ 64
static const int ARCAN_SHMPAGE_QUEUE_SZ = PP_QUEUE_SZ;

/* 
 * Default audio storage / transfer characteristics
 * The gist of it is to keep this interface trivially simple
 * for the basic basic sound needs (bell sounds and whatnot)
 */
static const int ARCAN_SHMPAGE_MAXAUDIO_FRAME = 192000;
static const int ARCAN_SHMPAGE_SAMPLERATE = 44100;

/* 
 * This is a hint to resamplers used as part of whatever
 * frameserver uses this interface, on a scale from 1..10,
 * how do we value audio resampling quality
 */
static const int ARCAN_SHMPAGE_RESAMPLER_QUALITY = 5;
static const int ARCAN_SHMPAGE_ACHANNELS = 2;

/*
 * This is somewhat of a formatting hint; for now,
 * only RGBA32 buffers are actually used (and the streaming
 * texture uploads in the main process will treat the 
 * input as that. It is suggested that other formats
 * and packing strategies (e.g. hardware YUV) still
 * pack in 4x8bit channels interleaved and then hint the
 * conversion in the shader used 
 */ 
#ifndef PP_SHMPAGE_MAXW
#define PP_SHMPAGE_MAXW 1920
#endif

#ifndef PP_SHMPAGE_MAXH
#define PP_SHMPAGE_MAXH 1080
#endif
static const int ARCAN_SHMPAGE_VCHANNELS = 4;
static const int ARCAN_SHMPAGE_MAXW = PP_SHMPAGE_MAXW;
static const int ARCAN_SHMPAGE_MAXH = PP_SHMPAGE_MAXH;

/* 
 * The final shmpage size will be a function of the constants 
 * above, along with a few extra bytes to make room for the
 * header structure (audioframe * 3 / shmpage_achannels)
 */
static const int ARCAN_SHMPAGE_AUDIOBUF_SZ = 288000;
/*	ARCAN_SHMPAGE_MAXAUDIO_FRAME * 3 / ARCAN_SHMPAGE_ACHANNELS; */

static const int ARCAN_SHMPAGE_VIDEOBUF_SZ = 8294400;
/* ARCAN_SHMPAGE_MAXW * ARCAN_SHMPAGE_MAXH * ARCAN_SHMPAGE_VCHANNELS */

static const int ARCAN_SHMPAGE_MAX_SZ = 8647936; 
/* ARCAN_SHMPAGE_AUDIOBUF_SZ + ARCAN_SHMPAGE_VIDEOBUF_SZ + 
  sizeof(struct arcan_event) * ARCAN_SHMPAGE_QUEUE_SZ * 2) + 512 */

#ifndef INFINITE
#define INFINITE -1
#endif

/* 
 * Tracking context for a frameserver connection,
 * will only be used "locally" with references 
 */
struct frameserver_shmcont{
	struct frameserver_shmpage* addr;
	sem_handle vsem;
	sem_handle asem;
	sem_handle esem;
};


struct frameserver_shmpage {
/* 
 * These queues carry the event blocks (~100b datastructures)
 * back and forth between parent and child. It is treated as a
 * ring-buffer.
 */ 
	struct {
		struct arcan_event evqueue[ PP_QUEUE_SZ ];
		uint32_t front, back;
	} childdevq, parentdevq;

/* will be checked frequently, likely before transfers.
 * if the DMS is released, the parent (or child or both) will
 * drop the connection. */
	volatile int8_t resized;

/* when released, it is assumed that the parent or child or both
 * has failed and everything should be dropped and terminated */
	volatile int8_t dms;

/* used as a hint to how disruptions (e.g. broken datastreams,
 * end of content in terms of video playback etc.) should be handled,
 * terminating or looping back to the initial state (if possible) */ 
	uint8_t loop;

/*
 * flipped whenever a buffer is ready to be synched,
 * polled repeatedly by the parent (or child for the case of an
 * encode frameserver) then the corresponding sem_handle is used
 * as a wake-up trigger 
 */	
	volatile uint8_t aready;
	volatile uint8_t vready;

/*
 * Current video output dimensions, if these deviate from the
 * agreed upon dimensions (i.e. change w,h and set the resized flag to !0)
 * the parent will simply ignore the data presented.
 */ 	
	uint16_t w, h;

/* 
 * this flag is set if the row-order is inverted (i.e. Y starts at 
 * the bottom and moves up rather than upper left as per arcan default)
 * and used as a hint to the rendering subsystem in order to 
 * just adjust the texture coordinates used (to spare memory bandwidth).
 */
	uint8_t glsource;

/*
 * this is currently unused and reserved for future cases when we have
 * an agreed upon handle for sharing textures across processes, which
 * would allow for scenarios like (frameserver allocates GL context,
 * creates a texture and attaches as FBO color output, after rendering,
 * switches the buffer, sets the value here and flags the vready toggle).
 */
	uint64_t glhandle;

/* some data-sources (e.g. video-playback) may take advantage
 * of buffering in the parent process and keep presentation/timing/queue
 * management there. In those cases, a relative ms timestamp
 * is present in this field and the main process gets the happy job
 * of trying to compensate for synchronization */ 
	int64_t vpts;
	int64_t apts;

/* 
 * For some cases, the child doesn't always have access to 
 * whichever process is responsible for managing "the other end"
 * of this interface. The native PID is therefore set here,
 * and for the local monitoring thread (that frequently checks
 * to see if the parent is still alive as a last resort 
 * against deadlocks).
 */
	process_handle parent;

/* while video transfers are done progressively, one frame at a time,
 * the audio buffering is a bit more lenient. This value signals
 * how much of the audio buffer is actually used, and can be 
 * manipulated by both sides. */
	uint32_t abufused, abufbase;
};

/* 
 * The following functions are support functions used to manage
 * the shared memory pages, presented in the order they are likely
 * to be used 
 */

/* This function is used by a frameserver to use some kind of
 * named shared memory reference string (typically provided by
 * as an argument on the command-line. 
 *
 * The force-unlink flag is to set if whatever symbol in whatever 
 * namespace the key resides in, should be unlinked after
 * allocation, to prevent other processes from mapping it as well.
 */
struct frameserver_shmcont frameserver_getshm(
	const char* shmkey, bool force_unlink);

/* 
 * Using the specified shmpage state, return pointers into 
 * suitable offsets into the shared memory pages for video
 * (planar, packed, RGBA) and audio (limited by abufsize constant). 
 */ 
void frameserver_shmpage_calcofs(struct frameserver_shmpage*, 
	uint8_t** dstvidptr, uint8_t** dstaudptr);

/*
 * Using the specified shmpage state, synchronization semaphore handle,
 * construct two event-queue contexts. Parent- flag should be set 
 * to false for frameservers 
 */
void frameserver_shmpage_setevqs(struct frameserver_shmpage*, 
	sem_handle, arcan_evctx* inevq, arcan_evctx* outevq, bool parent);

/* (frameserver use only) helper function to implement 
 * request/synchronization protocol to issue a resize of the 
 * output video buffer.
 * This request can be declined (false return value) and 
 * can be considered costly (may block indefinitely) 
 */ 
bool frameserver_shmpage_resize(struct frameserver_shmcont*, 
	unsigned width, unsigned height);

/*
 * This is currently a "stub" although it is suggested that
 * both frameservers and parents repeatedly invokes it as part
 * of rendering / eventloops or similar activity. The purpose
 * is to (through checksums or similar means) detect and self-destruct
 * in the event of a corrupt page (indication of a serious underlying
 * problem) so that proper debug-/tracing-/user- measures can be taken.  
 */
bool frameserver_shmpage_integrity_check(struct frameserver_shmpage*);

/* 
 * The following functions are simple lookup/unpack support functions
 * for argument strings usually passed on the command-line to a newly 
 * spawned frameserver in a simple (utf-8) key=value\tkey=value type format. 
 */ 
struct arg_arr {
	char* key;
	char* value;
};

/* take the input string and unpack it into an array of key-value pairs */
struct arg_arr* arg_unpack(const char*);

/*
 * return the value matching a certain key, 
 * if ind is larger than 0, it's the n-th result 
 * that will be stored in dst 
 */ 
bool arg_lookup(struct arg_arr* arr, const char* val, 
	unsigned short ind, const char** found);

void arg_cleanup(struct arg_arr*);
#endif
