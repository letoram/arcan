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
#include <string.h>
#include <strings.h>
#include <fcntl.h>
#include <sys/types.h>


#include <SDL.h>
#include <al.h>
#include <alc.h>

#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_event.h"

#define ARCAN_ASTREAMBUF_LIMIT 4
#define ARCAN_ASTREAMBUF_DEFAULT 4
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
	unsigned char used;
	ALuint streambuf[ARCAN_ASTREAMBUF_LIMIT];

	enum aobj_atypes atype;
	arcan_afunc_cb feed;
	arcan_again_cb gproxy;

	void* tag;
	struct arcan_aobj* next;
} arcan_aobj;

typedef struct {
/* linked list of audio sources,
 * the number of available sources are platform / hw dependant,
 * ranging between 10-100 or so */
	arcan_aobj* first;
	ALCcontext* context;
	bool al_active;

	arcan_aobj_id lastid;
	unsigned aobjc;
} arcan_acontext;

static void _wrap_alError(arcan_aobj*);

/* context management here is quite different from 
 * video (no push / pop / etc. openAL volatility alongside
 * hardware buffering problems etc. make it too much of a hazzle */
static arcan_acontext _current_acontext = {.first = NULL, .context = NULL};
static arcan_acontext* current_acontext = &_current_acontext;

static arcan_aobj* arcan_audio_getobj(arcan_aobj_id);
static arcan_errc arcan_audio_free(arcan_aobj_id);

/* This little stinker came to be as much as a curiousity towards
 * how various IDE suites actually handed it than some balanced and insightful design choice */
#include "arcan_audio_ogg.c"

#ifdef _HAVE_MPG123
#include "arcan_audio_mp3.c"
#endif

static arcan_aobj* arcan_audio_prepare_format(enum aobj_atypes type, arcan_afunc_cb* cb, arcan_aobj* aobj)
{
	switch (type) {
		case OGG:
			aobj->tag = arcan_audio_ogg_buildtag(aobj);
			*cb = arcan_audio_sfeed_ogg;
			return aobj;
			break;

#ifdef _HAVE_MPG123
		case MP3:
			rv = arcan_audio_mp3_buildtag(input, tag);
			*cb = arcan_audio_sfeed_mp3;
			break;
#endif

		default:
			fprintf(stderr, "Warning: arcan_audio_prepare_format(), unknown audio type: %i\n", type);
			break;
	}

	return NULL;
}

static ALuint load_wave(const char* fname){
	ALuint rv = 0;
	SDL_AudioSpec spec;
	Uint8* abuf;
	Uint32 abuflen;
	
	if (SDL_LoadWAV_RW(
		SDL_RWFromFile(fname, "rb"), 
		1, &spec, &abuf, &abuflen) != NULL){
		ALenum alfmt = AL_NONE;
		
	/* unsure about the full SDL implementation here,
	 * might be necessary to do signed -> unsigned for _*8 formats, 
	 * and unsigned -> signed for *16 formats, and endianness conversion */
		switch (spec.format){
			case AUDIO_U8:
			case AUDIO_S8:
				alfmt = spec.channels == 2 ? AL_FORMAT_STEREO8 : AL_FORMAT_MONO8;
			break;
		
			case AUDIO_U16:
			case AUDIO_S16:
				alfmt = spec.channels == 2 ? AL_FORMAT_STEREO16 : AL_FORMAT_MONO16;
			break;
		}
		
		if (alfmt != AL_NONE){
			alGenBuffers(1, &rv);
			alBufferData(rv, alfmt, abuf, abuflen, spec.freq);
		}
		
		SDL_FreeWAV(abuf);
	}
	
	return rv;
}

static arcan_aobj_id arcan_audio_alloc(arcan_aobj** dst)
{
	arcan_aobj_id rv = ARCAN_EID;
	ALuint alid;
	if (dst)
		*dst = NULL;
	
	alGenSources(1, &alid);

	if (alid == AL_NONE)
		return rv;

	arcan_aobj* newcell = (arcan_aobj*) calloc(sizeof(arcan_aobj), 1);
	newcell->alid = alid;
	rv = newcell->id = current_acontext->lastid++;
	if (dst)
		*dst = newcell;
	
	if (current_acontext->first){
		arcan_aobj* current = current_acontext->first;
		while(current && current->next)	
			current = current->next;
		
		current->next = newcell;
	}
	else 
		current_acontext->first = newcell;
	
	return rv;
}

static arcan_aobj* arcan_audio_getobj(arcan_aobj_id id)
{
	arcan_aobj* current = current_acontext->first;
	
	while (current){
		if (current->id == id)
			return current;
		
		current = current->next;
	}

	return NULL;
}

arcan_errc arcan_audio_alterfeed(arcan_aobj_id id, arcan_afunc_cb cb)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_aobj* obj = arcan_audio_getobj(id);

	if (obj) {
		if (!cb)
			rv = ARCAN_ERRC_BAD_ARGUMENT;
		else {
			obj->feed = cb;
			rv = ARCAN_OK;
		}
	}

	return rv;
}

arcan_errc arcan_audio_free(arcan_aobj_id id)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_aobj* current = current_acontext->first;
	arcan_aobj** owner = &(current_acontext->first);
	
	while(current && current->id != id){
		owner = &(current->next);
		current = current->next;
	}
	
	if (current && current->id == id){
		*owner = current->next;
		
		if (current->lfeed)
			SDL_RWclose(current->lfeed);
		
		if (current->n_streambuf)
			alDeleteBuffers(current->n_streambuf, current->streambuf);
		
		if (current->alid != AL_NONE)
			alDeleteSources(1, &current->alid);
		
		memset(current, 0, sizeof(arcan_aobj));
		free(current);
		
		current_acontext->aobjc--;
		rv = ARCAN_OK;
	}
	
	return rv;
}

arcan_errc arcan_audio_setup()
{
	arcan_errc rv = ARCAN_ERRC_NOAUDIO; 
	
	if (current_acontext && !current_acontext->context) {
		current_acontext->context = alcCreateContext(alcOpenDevice(NULL), NULL);
		alcMakeContextCurrent(current_acontext->context);
		current_acontext->al_active = true;
		rv = ARCAN_OK;
		
		/* just give a slightly random base so that 
		 * user scripts don't get locked into hard-coded ids .. */
		current_acontext->lastid = rand() % 2000; 
	}

	return rv;
}

/*
 * sample code to show which audio devices are available
 * if the OpenAL subsystem support this extension.

	alcIsExtensionPresent(NULL, (ALubyte*)"ALC_ENUMERATION_EXT") => AL_TRUE,
	devices = (char *)alcGetString(NULL, ALC_DEVICE_SPECIFIER);

	strlen(deviceList)
	defdev = (char *)alcGetString(NULL, ALC_DEFAULT_DEVICE_SPECIFIER);

	alcOpenDevice from devices, can be used to alcCreateContext
	then alcMakeContextCurrent
	something fails, revert to alcOpenDevice
*/

arcan_errc arcan_audio_teardown()
{
	arcan_errc rv = ARCAN_OK;
	ALCcontext* ctx = current_acontext->context;

	if (ctx) {
		/* fixme, free callback buffers etc. */
		alcDestroyContext(ctx);
		current_acontext->al_active = false;
		current_acontext->context = NULL;
	}

	return rv;
}

arcan_errc arcan_audio_play(arcan_aobj_id id)
{
	arcan_aobj* aobj = arcan_audio_getobj(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (aobj && !aobj->active) {
		alSourcePlay(aobj->alid);
		aobj->active = true;
	}

	return rv;
}

arcan_aobj_id arcan_audio_play_sample(const char* fname, float gain, arcan_errc* err)
{
	if (fname == NULL)
		return ARCAN_EID;
	
	arcan_aobj* aobj;
	arcan_aobj_id rid = arcan_audio_alloc(&aobj);
	if (err)
		*err = ARCAN_ERRC_OUT_OF_SPACE;
	
	if (rid != ARCAN_EID){
		ALuint id = load_wave(fname);
		
		if (id != AL_NONE){
			aobj->kind = AOBJ_STREAM;
			aobj->gain = gain;
			aobj->n_streambuf = 1;
			aobj->streambuf[0] = id;
			alSourcef(id, AL_GAIN, gain);
			alSourceQueueBuffers(aobj->alid, 1, &id);
			alSourcePlay(aobj->alid);
			
			if (err)
				*err = ARCAN_OK;
		}
		else{
			arcan_audio_free(rid);

			if (err)
				*err = ARCAN_ERRC_BAD_RESOURCE;
		}
		
	}
	
	return rid;
}

arcan_aobj_id arcan_audio_feed(arcan_afunc_cb feed, void* tag, arcan_errc* errc)
{
	arcan_aobj* aobj;
	arcan_aobj_id rid = arcan_audio_alloc(&aobj);
	arcan_errc rc = ARCAN_ERRC_OUT_OF_SPACE;

	if (aobj) {
		aobj->streaming = true;
		aobj->tag = tag;
		aobj->n_streambuf = ARCAN_ASTREAMBUF_DEFAULT;
		aobj->feed = feed;
		aobj->gain = 1.0;
		aobj->kind = AOBJ_STREAM;
		alGenBuffers(aobj->n_streambuf, aobj->streambuf);

		rc = ARCAN_OK;
	}

	if (errc)
		*errc = rc;
	return rid;
}

/* Another workaround to the many "fine" problems
 * experienced with OpenAL .. */
arcan_errc arcan_audio_rebuild(arcan_aobj_id id)
{
	arcan_aobj* aobj = arcan_audio_getobj(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (aobj) {
		alDeleteBuffers(aobj->n_streambuf, aobj->streambuf);
		alSourceStop(aobj->alid);
		alDeleteSources(1, &aobj->alid);
		alGenSources(1, &aobj->alid);
		alGenBuffers(aobj->n_streambuf, aobj->streambuf);

		rv = ARCAN_OK;
	}

	return rv;
}

arcan_aobj_id arcan_audio_proxy(arcan_again_cb proxy, void* tag)
{
	arcan_aobj_id rid = ARCAN_EID;

	if (proxy) {
		arcan_aobj* aobj;
		rid = arcan_audio_alloc(&aobj);
		aobj->kind = AOBJ_PROXY;
		aobj->tag = tag;
		aobj->feed = NULL;
		aobj->gproxy = proxy;
		aobj->gain = 1.0;
	}

	return rid;
}


static enum aobj_atypes find_type(const char* path)
{
	static char* atypetbl[] = {
		"PCM", "WAV", "AIFF", "OGG", "MP3", "FLAC", "AAC", "MP4", NULL
	};
	static int ainttypetbl[] = {
		PCM, WAV, AIFF, OGG, MP3, FLAC, AAC, MP4, 0
	};

	char* extension = strrchr(path, '.');
	if (extension && *extension) {
		extension++;
		char** cur = atypetbl;
		int ofs = 0;

		while (cur[ofs]) {
			if (strcasecmp(cur[ofs], extension) == 0)
				return ainttypetbl[ofs];

			ofs++;
		}
	}

	return -1;
}

arcan_aobj_id arcan_audio_stream(const char* fname, enum aobj_atypes type, arcan_errc* errc)
{
	arcan_aobj_id rid = ARCAN_EID;
	arcan_afunc_cb cb = NULL;
	arcan_aobj* aobj;
	void* dtag;
	
	if (!fname)
		return rid;

	SDL_RWops* fpek = SDL_RWFromFile(fname, "rb");
	if (!fpek)
		return rid;
	
	rid = arcan_audio_alloc(&aobj);
	aobj->lfeed = fpek;
	type = find_type(fname);

	if (rid != ARCAN_EID){
		if (arcan_audio_prepare_format(type, &cb, aobj) ){
			aobj->streaming = true;
			aobj->n_streambuf = ARCAN_ASTREAMBUF_DEFAULT;
			aobj->feed = cb;
			aobj->kind = AOBJ_STREAM;
			alGenBuffers(aobj->n_streambuf, aobj->streambuf);
		}
		else{
			SDL_RWclose(fpek);
			arcan_audio_free(rid);
			rid = ARCAN_EID;
		}
	}
	
	return rid;
}

arcan_errc arcan_audio_suspend()
{
	arcan_errc rv = ARCAN_ERRC_BAD_ARGUMENT;
	ALCcontext* ctx = current_acontext->context;

	arcan_aobj* current = current_acontext->first;

	while (current) {
		arcan_audio_pause(current->id);
		current = current->next;
	}

	current_acontext->al_active = false;
	rv = ARCAN_OK;

	return rv;
}

arcan_errc arcan_audio_resume()
{
	arcan_errc rv = ARCAN_ERRC_BAD_ARGUMENT;
	ALCcontext* ctx = current_acontext->context;
	arcan_aobj* current = current_acontext->first;

	while (current) {
		arcan_audio_play(current->id);
		current = current->next;
	}
	
	current_acontext->al_active = true;

	rv = ARCAN_OK;

	return rv;
}

arcan_errc arcan_audio_pause(arcan_aobj_id id)
{
	arcan_aobj* dobj = arcan_audio_getobj(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (dobj) {
		int processed;
		alGetSourcei(dobj->alid, AL_BUFFERS_PROCESSED, &processed);
		alSourceUnqueueBuffers(dobj->alid, 1, (unsigned int*) &processed);
		alSourceStop(dobj->alid);
		dobj->active = false;
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_audio_stop(arcan_aobj_id id)
{
	arcan_aobj* dobj = arcan_audio_getobj(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (dobj) {
		if (dobj->kind == AOBJ_STREAM) {
			// run a callback with empty params as a cleanup
			// based on dtype, clean with appropriate call, ie:
			// ov_clear(&oggStream); OGG through libvorbis
			dobj->feed(dobj, id, 0, dobj->tag);
		}

		alSourceStop(dobj->alid);
		arcan_audio_free(id);

		arcan_event newevent = {.category = EVENT_AUDIO, .kind = EVENT_AUDIO_OBJECT_GONE};
		newevent.data.audio.source = id;
		arcan_event_enqueue(&newevent);
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_audio_setgain(arcan_aobj_id id, float gain, uint16_t time)
{
	arcan_aobj* dobj = arcan_audio_getobj(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (dobj) {
		gain = gain > 1.0 ? 1.0 : (gain < 0.0 ? 0.0 : gain);

		if (!dobj->gproxy)
			alGetSourcef(dobj->alid, AL_GAIN, &dobj->gain);

		/* immediately */
		if (time == 0) {
			dobj->d_gain = 0.0;
			dobj->t_gain = 0;
			dobj->gain = gain;

			if (dobj->gproxy)
				dobj->gproxy(dobj->gain, dobj->tag);
			else
				alSourcef(dobj->alid, AL_GAIN, gain);

			rv = (alGetError() == AL_NO_ERROR ? ARCAN_OK : ARCAN_ERRC_UNACCEPTED_STATE);
		}
		else {
			dobj->d_gain = (gain - dobj->gain) / (float) time;
			dobj->t_gain = time;
			rv = ARCAN_OK;
		}

	}

	return rv;
}

arcan_errc arcan_audio_setpitch(arcan_aobj_id id, float pitch, uint16_t time)
{
	arcan_aobj* dobj = arcan_audio_getobj(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (dobj) {
		alGetSourcef(dobj->alid, AL_PITCH, &dobj->pitch);
		pitch = (pitch < 0.0 ? 0.0 : pitch);

		if (!time && !dobj->gproxy) {
			alSourcef(dobj->alid, AL_PITCH, pitch);
			dobj->d_pitch = 0.0;
			dobj->t_pitch = 0;
			rv = (alGetError() == AL_NO_ERROR ? ARCAN_OK : ARCAN_ERRC_UNACCEPTED_STATE);
		}
		else {
			dobj->d_pitch = pitch;
			dobj->t_pitch = time;
			rv = ARCAN_OK;
		}
	}

	return rv;
}

static void arcan_astream_refill(arcan_aobj* current)
{
	ALenum state;
	alGetSourcei(current->alid, AL_SOURCE_STATE, &state);

	if (state == AL_PLAYING){
		int processed;
		alGetSourcei(current->alid, AL_BUFFERS_PROCESSED, &processed);

	/* the ffuncs do alBufferData */
		for (int i = 0; i < processed; i++){
			ALuint buffer;
			alSourceUnqueueBuffers(current->alid, 1, &buffer);

			if (current->feed && 
				current->feed(current, current->id,  buffer, current->tag) == ARCAN_OK)
				alSourceQueueBuffers(current->alid, 1, &buffer);
		}
	}
	else if (current->active && 
		(state == AL_INITIAL || state == AL_STOPPED)){
		int bufc = 0;

		for (int i = 0; i < current->n_streambuf; i++){
			arcan_errc rv = ARCAN_OK;
			
			if (current->feed &&
		        (rv = current->feed(current, current->id, current->streambuf[i], current->tag)) == ARCAN_OK){
				alSourceQueueBuffers(current->alid, 1, &current->streambuf[i]);
				bufc++;
			}
			else if (rv == ARCAN_ERRC_EOF){
				break;
			}
			else {
				_wrap_alError(current); /* can't fill buffers for some reason */
			}
		}
		if (bufc > 0){
			alSourcePlay(current->alid);
		} else {
			arcan_event newevent = {
				.category = EVENT_AUDIO, 
				.kind = EVENT_AUDIO_PLAYBACK_FINISHED
			};
			
			newevent.data.audio.source = current->id;
			arcan_event_enqueue(&newevent);
		}
	}
	else
		_wrap_alError(current);	
}

void arcan_audio_tick(uint8_t ntt)
{
	/* scan list of allocated IDs and update buffers for all streaming / cb function,
	   * also make sure our context is the current active one, flush error buffers etc. */
	if (!current_acontext->context || !current_acontext->al_active)
		return;

	if (alcGetCurrentContext() != current_acontext->context)
		alcMakeContextCurrent(current_acontext->context);

	while (ntt-- > 0) {
		arcan_aobj* current = current_acontext->first;

		while (current){
		/* step gradual gain change */
			if (current->t_gain > 0) {
				current->t_gain--;
				current->gain += current->d_gain;

				if (current->gproxy)
					current->gproxy(current->gain, current->tag);
				else
					alSourcef(current->alid, AL_GAIN, current->gain);

				if (current->t_gain == 0) {
					arcan_event newevent = {
						.category = EVENT_AUDIO, 
						.kind = EVENT_AUDIO_GAIN_TRANSFORMATION_FINISHED
					};
					
					newevent.data.audio.source = current->id;
					arcan_event_enqueue(&newevent);
				}
			}
		
		/* step gradual pitch change */
			if (current->t_pitch) {
				float newpitch = current->pitch + (current->d_pitch - current->pitch) / (float)current->t_pitch;
				alSourcef(current->alid, AL_PITCH, newpitch);
				current->t_pitch--;
				alGetSourcef(current->alid, AL_PITCH, &current->pitch);

				if (current->t_pitch == 0) {
					arcan_event newevent = {
						.category = EVENT_AUDIO, 
						.kind = EVENT_AUDIO_PITCH_TRANSFORMATION_FINISHED,
					};
					
					newevent.data.audio.source = current->id;
					arcan_event_enqueue(&newevent);
				}
			}

			if (current->active)
				if (current->streaming)
					arcan_astream_refill(current);
				else { 
					ALenum state;
					alGetSourcei(current->alid, AL_SOURCE_STATE, &state);
					current->active = (state == AL_PLAYING);
				}

			current = current->next;
		}
	}
}

static void _wrap_alError(arcan_aobj* obj)
{
	ALenum errc = alGetError();
	if (errc != AL_NO_ERROR) {

		fprintf(stderr, "(openAL): ");
		
		switch (errc) {
			case AL_INVALID_NAME:
				fprintf(stderr, "(%li:%ui), bad ID passed to function\n", obj->id, obj->alid);
				break;
			case AL_INVALID_ENUM:
				fprintf(stderr, "(%li:%ui), bad enum value passed to function\n", obj->id, obj->alid);
				break;
			case AL_INVALID_VALUE:
				fprintf(stderr, "(%li:%ui), bad value passed to function\n", obj->id, obj->alid);
				break;
			case AL_INVALID_OPERATION:
				fprintf(stderr, "(%li:%ui), requested operation is not valid\n", obj->id, obj->alid);
				break;
			case AL_OUT_OF_MEMORY:
				fprintf(stderr, "(%li:%ui), OpenAL out of memory\n", obj->id, obj->alid);
				break;
			default:
				fprintf(stderr, "(%li:%ui), undefined error\n", obj->id, obj->alid);
		}

		
	}
}
