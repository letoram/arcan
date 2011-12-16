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

/* ogg vorbis */
#include <ogg/ogg.h>
#include <vorbis/codec.h>
#include <vorbis/vorbisenc.h>
#include <vorbis/vorbisfile.h>

struct ogg_ctx {
	OggVorbis_File stream;
	vorbis_info* info;
	vorbis_comment* comment;
	char* buffer;
	uint16_t ofs;
	uint16_t size;
};

/* just quick SDL RWops fptr wrappers */
static size_t wrapr(void *ptr, size_t size, size_t nmemb, void *tag)
{
    return SDL_RWread((SDL_RWops*)tag, ptr, size, nmemb);
}

static int wrapsk(void *tag, ogg_int64_t offset, int whence)
{
    return SDL_RWseek((SDL_RWops*)tag, (int)offset, whence);
}

static int wrapc(void *tag)
{
    return SDL_RWclose((SDL_RWops*)tag);
}

static long wrapt(void *tag)
{
    return SDL_RWtell((SDL_RWops*)tag);
}

void* arcan_audio_ogg_buildtag(arcan_aobj* aobj)
{
	struct ogg_ctx* odtag = (struct ogg_ctx*) calloc(sizeof(struct ogg_ctx), 1);
	ov_callbacks callbacks = {
		.read_func = wrapr,
		.seek_func = wrapsk,
		.close_func = wrapc,
		.tell_func = wrapt
	};

	int ec;

	if ((ec = ov_open_callbacks(aobj->lfeed, &odtag->stream, NULL, 0, callbacks)) == 0) {
		odtag->info = ov_info(&odtag->stream, -1);
		odtag->comment = ov_comment(&odtag->stream, 1);
		odtag->size = 1024 * 8;
		odtag->buffer = (char*) malloc(odtag->size);
	}
	else {
		fprintf(stderr, "Warning: arcan_audio_ogg(), couldn't open input, reason: %i\n", ec);
		free(odtag);
		odtag = NULL;
	}

	return odtag;
}

arcan_errc arcan_audio_sfeed_ogg(arcan_aobj* aobj, arcan_aobj_id id, ALuint buf, void* tag)
{
	struct ogg_ctx* octx = (struct ogg_ctx*) tag;
	arcan_errc rv = ARCAN_OK; 
	
	if (aobj) {
		size_t ntr = octx->size - octx->ofs;

		if (ntr) {
			int nr, section;
			do {
				/* arg 4 (0: LITTLE ENDIAN, 1: BIG ENDIAN), arg 5 dformat (8 or 16bit samples?), arg 6 signedness */
				if ((nr = ov_read(&octx->stream, octx->buffer + octx->ofs, ntr, 0, 2, 1, &section)) <= 0){
				  rv = ARCAN_ERRC_EOF;
				  break;
			  }
				ntr -= nr;
				octx->ofs += nr;

			}
			while (ntr);

			if (octx->ofs) {
				alBufferData(buf, (octx->info->channels == 1 ? AL_FORMAT_MONO16 : AL_FORMAT_STEREO16), octx->buffer, octx->ofs, octx->info->rate);
				octx->ofs = 0;
			}
		}
	}
	else { /* cleanup */
		free(octx->buffer);
		free(octx);
	}

	return rv;
}
