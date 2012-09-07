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

#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/types.h>

#include "../arcan_math.h"
#include "../arcan_general.h"
#include "../arcan_event.h"

#include "arcan_frameserver.h"
#include "../arcan_frameserver_shmpage.h"
#include "arcan_frameserver_encode.h"

/* libFFMPEG */
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>

typedef struct arcan_ffmpeg_context {
	struct frameserver_shmcont shmcont;
	
	struct arcan_evctx inevq;
	struct arcan_evctx outevq;
	
	struct SwsContext* ccontext;
	AVFormatContext* fcontext;
	AVCodecContext* acontext;
	AVCodecContext* vcontext;
	AVCodec* vcodec;
	AVCodec* acodec;
	AVStream* astream;
	AVStream* vstream;
	AVPacket packet;
	AVFrame* pframe, (* aframe);

	bool extcc;

	int vid; /* selected video-stream */
	int aid; /* Selected audio-stream */

	int height;
	int width;
	int bpp;

	uint16_t samplerate;
	uint16_t channels;

	uint8_t* video_buf;
	uint32_t c_video_buf;
	
/* precalc dstptrs into shm */
	uint8_t* vidp, (* audp);

} arcan_ffmpeg_context;

void arcan_frameserver_ffmpeg_run(const char* resource, const char* keyfile);
