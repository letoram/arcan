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

/* the use for these functions is just to call with, 
 * a possibly user supplied preferred codec identification string,
 * begin with container, as we need the flags to open correctly.
 * then video and audio, passing the flags of the container.
 * then call each codec_ents setup function with respective options */
#ifndef _HAVE_ENCPRESETS
#define _HAVE_ENCPRESETS

enum codec_kind {
	CODEC_VIDEO,
	CODEC_AUDIO,
	CODEC_FORMAT
};

struct codec_ent
{
	enum codec_kind kind;
	
	const char* const name;
	const char* const shortname;
	int id;
	
	union {
		struct {
		AVCodec* codec;
		AVCodecContext* context;
		AVFrame* pframe;
		int channel_layout; /* copy here for <= v53 */
		} video, audio;
		
		struct {
			AVOutputFormat*  format;
			AVFormatContext* context;
		} container;
		
	} storage;
	
/* pass the codec member of this structure as first arg, 
 * unsigned number of channels (only == 2 supported currently)
 * unsigned samplerate (> 0, <= 48000)
 * unsigned abr|quality (0..n, n < 10 : quality preset, otherwise bitrate) */
	union {
		bool (*video)(struct codec_ent*, unsigned, unsigned, float, unsigned, bool);
		bool (*audio)(struct codec_ent*, unsigned, unsigned, unsigned);
		bool (*muxer)(struct codec_ent*); 
	} setup;
};

/*
 * try to find and allocate a valid video codec combination, 
 * requested : (NULL) use default, otherwise look for this as name.
 */
struct codec_ent encode_getvcodec(const char* const requested, int flags);
struct codec_ent encode_getacodec(const char* const requested, int flags);
struct codec_ent encode_getcontainer(const char* const requested, 
	int fd, const char* remote);
#endif
