/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
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

#define ARCAN_ASTREAMBUF_LIMIT 4 
#define ARCAN_ASAMPLE_LIMIT 1024 * 64

struct arcan_aobj_cell;

enum aobj_kind {
	AOBJ_STREAM,
	AOBJ_SAMPLE,
	AOBJ_FRAMESTREAM,
	AOBJ_PROXY
};


typedef struct arcan_aobj {
	arcan_aobj_id id;
	ALuint alid;
	enum aobj_kind kind;
	
	bool active;

	unsigned t_gain;
	unsigned t_pitch;

	float gain;
	float pitch;
	float d_gain;
	float d_pitch;

	bool streaming;
	SDL_RWops* lfeed;

	unsigned char n_streambuf;
	short used;
	ALuint streambuf[ARCAN_ASTREAMBUF_LIMIT];
	bool streambufmask[ARCAN_ASTREAMBUF_LIMIT];

	enum aobj_atypes atype;
	uint32_t preguard;
	
	arcan_afunc_cb feed;
	arcan_monafunc_cb monitor;
	
	uint32_t postguard;
	arcan_again_cb gproxy;

	void* tag;
	struct arcan_aobj* next;
} arcan_aobj;

#ifndef ARCAN_AUDIO_SLIMIT 
#define ARCAN_AUDIO_SLIMIT 16
#endif

#endif

