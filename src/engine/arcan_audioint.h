/*
 * Copyright 2003-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_AUDIOINT
#define _HAVE_ARCAN_AUDIOINT

#ifndef ARCAN_AUDIO_SLIMIT
#define ARCAN_AUDIO_SLIMIT 16
#endif

#define ARCAN_ASTREAMBUF_LIMIT 8
#define ARCAN_ASTREAMBUF_LLIMIT 4096

struct arcan_aobj_cell;

struct arcan_achain {
	unsigned t_gain;
	float d_gain;

	struct arcan_achain* next;
};

typedef struct arcan_aobj {
/* shared */
	arcan_aobj_id id;
	unsigned alid;
	enum aobj_kind kind;
	bool active;

	float gain;

	struct arcan_achain* transform;

/* AOBJ proxy only */
	arcan_again_cb gproxy;

/* AOBJ_STREAM only */
	bool streaming;

/* AOBJ sample only */
	uint16_t* samplebuf;

/* openAL Buffering */
	unsigned char n_streambuf;
	arcan_tickv last_used;
	unsigned streambuf[ARCAN_ASTREAMBUF_LIMIT];
	bool streambufmask[ARCAN_ASTREAMBUF_LIMIT];
	short used;

/* global hooks */
	arcan_afunc_cb feed;
	arcan_monafunc_cb monitor;
	void* monitortag, (* tag);

/* stored as linked list */
	struct arcan_aobj* next;
} arcan_aobj;

/*
 * Request [bufc] buffer indices to be stored in [buffers], return
 * the amount that could actually be fulfilled. These are expected to
 * be populated each with _audio_buffer calls.
 */
size_t arcan_audio_getbuffers(arcan_aobj* obj, unsigned* buffers, size_t bufc);

/* just a wrapper around alBufferData that takes monitors into account */
void arcan_audio_buffer(arcan_aobj*, ssize_t buffer, void* abuf,
	size_t abuf_sz, unsigned channels, unsigned samplerate, void* tag);

#endif

