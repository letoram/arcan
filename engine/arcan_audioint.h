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

/* just a wrapper around alBufferData that takes monitors into account */
void arcan_audio_buffer(arcan_aobj*, unsigned, void*,
	size_t, unsigned, unsigned, void*);

#endif

