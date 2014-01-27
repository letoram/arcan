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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,USA.
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
#include <assert.h>
#include <limits.h>
#include <pthread.h>

#include <al.h>
#include <alc.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_audioint.h"
#include "arcan_event.h"
#include "arcan_frameserver_shmpage.h"

typedef struct {
/* linked list of audio sources,
 * the number of available sources are platform / hw dependant,
 * ranging between 10-100 or so */
	arcan_aobj* first;
	ALCcontext* context;
	bool al_active;

	arcan_aobj_id lastid;
	
/* limit on amount of simultaneous active sources */
	ALuint sample_sources[ARCAN_AUDIO_SLIMIT];
	
	arcan_monafunc_cb globalhook;
	void* global_hooktag;
} arcan_acontext;

static bool _wrap_alError(arcan_aobj*, char*);

#ifndef CONST_MAX_ASAMPLESZ
#define CONST_MAX_ASAMPLESZ 1048756  
#endif

/* context management here is quite different from 
 * video (no push / pop / etc. openAL volatility alongside
 * hardware buffering problems etc. make it too much of a hazzle */
static arcan_acontext _current_acontext = {.first = NULL, .context = NULL};
static arcan_acontext* current_acontext = &_current_acontext;

static arcan_aobj* arcan_audio_getobj(arcan_aobj_id);
static arcan_errc arcan_audio_free(arcan_aobj_id);

static ALuint load_wave(const char* fname){
	ALuint rv = 0;

	data_source inres = arcan_open_resource(fname);
	if (inres.fd == BADFD)
		return rv; 

	map_region inmem = arcan_map_resource(&inres, false);
	if (inmem.ptr == NULL){
		arcan_release_resource(&inres);
		return rv; 
	}

/* only accept well-formed headers */
	if (memcmp(inmem.ptr + 0, "RIFF", 4) != 0 &&
		(arcan_warning("load_wave() -- missing RIFF header identifier\n"), true))
		goto cleanup;

	if (memcmp(inmem.ptr + 8, "WAVE", 4) != 0 &&
		(arcan_warning("load_wave() -- missing WAVE format identifier\n"), true))
		goto cleanup;

	uint16_t kv = 0x1234;
	bool le = (*(char*)&kv) == 0x34;
	if (!le && (arcan_warning(
		"load_wave(BE) -- big endian swap unimplemented\n"), true))
	goto cleanup;

/* a. map resource / file as per usual */
/* b. read header; (RIFX BE, RIFF LE)
 * Endian, Ofs, Name, Size
 * BE        0,  CID,    4
 * LE        4,  CSz,    4 Whole-chunk Size 
 * --        8,  Fmt,    4 (WAVE)
 * --- chunk 1 ---
 * BE       12,  CID,    4
 * LE       16,  CSz,    4 (subchunk size)
 * LE       20, AFMt,    2 (PCM: 0x0001) 
 * LE       22,  NCh,    2
 * LE       24, SRte,    4
 * LE       28, BRte,    4
 * LE       32, Algn,    2
 * LE       34, Btps,    2
 * --- chunk 2 --- (data)
 * BE       36,  CID,    4
 * LE       40,  CSz,    4
 * LE       44,  data    *
 * 8bit are unsigned, 16bit are 2compl. signed,
 * stereo are planar (rch then lch) */
	int16_t  fmt;
	int16_t  nch;
	uint16_t bits_ps;
	uint16_t smplrte;
	int32_t  nofs;
	
	if (memcmp(inmem.ptr + 12, "fmt ", 4) != 0 && 
		(arcan_warning("load_wave() -- missing format chuck ID\n"), true))
		goto cleanup;

	memcpy(&fmt,     inmem.ptr + 20, 2);
	memcpy(&nch,     inmem.ptr + 22, 2);
	memcpy(&smplrte, inmem.ptr + 24, 2);
	memcpy(&bits_ps, inmem.ptr + 34, 2);
	memcpy(&nofs,    inmem.ptr + 16, 4);
	nofs += 20;

	if (fmt != 0x001 && (arcan_warning(
		"load_wave() -- unsupported encoding (%d),only PCM accepted.\n", fmt), true))
		goto cleanup;

	if (nch != 1 && nch != 2 && (arcan_warning(
		"load_wave() -- unexpected number of channels (%d).\n", nch), true))
		goto cleanup;

	if (bits_ps != 8 && bits_ps != 16 && (arcan_warning(
		"load_wave() -- unsupported bitdepth (%d)\n", bits_ps), true))
		goto cleanup;

	if (smplrte != 44100 && smplrte != 22050 && smplrte != 11025)
		arcan_warning("load_wave() -- unconventional samplerate (%d).\n", smplrte);

	if (memcmp(inmem.ptr + nofs, "data", 4) != 0 && 
		(arcan_warning("load_wave() -- data chunk not found\n"), true))
		goto cleanup;
	
	int32_t nb;
	memcpy(&nb, inmem.ptr + nofs + 4, 4);
	if (nb > CONST_MAX_ASAMPLESZ){
		arcan_warning("load_wave() -- sample exceeds compile time limit "
			" (CONST_MAX_ASAMPLESZ %d), truncating.\n", CONST_MAX_ASAMPLESZ);
		nb = CONST_MAX_ASAMPLESZ;	
	}
	
	if (nb > (inmem.sz - nofs - 4) && (arcan_warning(
	 "load wave() -- total sample size is larger than the mapped input.\n"), true))
		goto cleanup;

	int alfmt = 0;
	off_t ofs = nofs + 8;
	int32_t innb = nb;

	uint8_t* samplebuf = malloc(nb);

	if (bits_ps == 8){
		alfmt = nch == 1 ? AL_FORMAT_MONO8 : AL_FORMAT_STEREO8;
		memcpy(samplebuf, inmem.ptr + ofs, nb);
	}
	else if (bits_ps == 16){
		alfmt = nch == 1 ? AL_FORMAT_MONO16 : AL_FORMAT_STEREO16;
		int16_t* s16_samplebuf = (int16_t*) samplebuf;

		while( nb > 0){	
			memcpy(s16_samplebuf++, inmem.ptr + ofs, 2);
			ofs += 2;
			nb -= 2;
		}
	}

	alGenBuffers(1, &rv);
	alBufferData(rv, alfmt, samplebuf, innb, smplrte);
	_wrap_alError(NULL, "load_wave(bufferData)");
	free(samplebuf);

cleanup:
	arcan_release_map(inmem);
	arcan_release_resource(&inres);

	return rv;
}

static arcan_aobj_id arcan_audio_alloc(arcan_aobj** dst)
{
	arcan_aobj_id rv = ARCAN_EID;
	ALuint alid;
	if (dst)
		*dst = NULL;

	alGenSources(1, &alid);
	_wrap_alError(NULL, "audio_alloc(genSources)");

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
	
 /* find */
	while(current && current->id != id){
		owner = &(current->next);
		current = current->next;
	}
	
 /* if found, delink */
	if (current){
		*owner = current->next;
		
		if (current->alid != AL_NONE){
			alSourceStop(current->alid);
			alDeleteSources(1, &current->alid);
			
			if (current->n_streambuf)
				alDeleteBuffers(current->n_streambuf, current->streambuf);
		}

		_wrap_alError(NULL, "audio_free(DeleteBuffers/sources)");
		memset(current, 0, sizeof(arcan_aobj));
		free(current);
		
		rv = ARCAN_OK;
	}
	
	return rv;
}

arcan_errc arcan_audio_setup(bool nosound)
{
	arcan_errc rv = ARCAN_ERRC_NOAUDIO; 

/* don't supported repeated calls without shutting down in between */
	if (current_acontext && !current_acontext->context) {

/* unfortunately, the pretty poorly thought out alcOpenDevice/alcCreateContext 
 * doesn't allow you to create a nosound or debug/testing audio device 
 * (or for that matter, enumerate without an extension, seriously..)
 * so to avoid yet another codepath, we'll just set the listenerGain to 0 */
		current_acontext->context = alcCreateContext(alcOpenDevice(NULL), NULL);
		alcMakeContextCurrent(current_acontext->context);
	
		if (nosound){
			arcan_warning("arcan_audio_init(nosound)\n");
			alListenerf(AL_GAIN, 0.0);
		}
		
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

arcan_errc arcan_audio_shutdown()
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

arcan_errc arcan_audio_play(arcan_aobj_id id, bool gain_override, float gain)
{
	arcan_aobj* aobj = arcan_audio_getobj(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (aobj){
	/* for aobj sample, just find a free sample slot (if any) and 
	 * attach the buffer already part of the aobj */
		if (aobj->kind == AOBJ_SAMPLE){
			rv = ARCAN_ERRC_OUT_OF_SPACE;

			for (unsigned i= 0; i < ARCAN_AUDIO_SLIMIT; i++)
				if (current_acontext->sample_sources[i] == 0){
					alGenSources(1, &current_acontext->sample_sources[i]);
					ALint alid = current_acontext->sample_sources[i];
					alSourcef(alid, AL_GAIN, gain_override ? gain : aobj->gain);
					_wrap_alError(aobj,"load_sample(alSource)");
					alSourceQueueBuffers(alid, 1, &aobj->streambuf[0]);
					_wrap_alError(aobj, "load_sample(alQueue)");
					alSourcePlay(alid);
					rv = ARCAN_OK;
					break;
				}
	/* some kind of streaming source, can't play if it is already active */
		} else if (aobj->active == false) {
			alSourcePlay(aobj->alid);
			_wrap_alError(aobj, "play(alSourcePlay)");
			aobj->active = true;
		}

		rv = ARCAN_OK;
	}

	return rv;
}

arcan_aobj_id arcan_audio_load_sample(const char* fname, 
	float gain, arcan_errc* err)
{
	if (fname == NULL)
		return ARCAN_EID;
	
	arcan_aobj* aobj;
	arcan_aobj_id rid = arcan_audio_alloc(&aobj);
	if (err)
		*err = ARCAN_ERRC_OUT_OF_SPACE;
	
	if (rid != ARCAN_EID){
/* since we have a "on play" source buffer, 
 * ignore the one we got from alloc */
		alDeleteSources(1, &aobj->alid);
		aobj->alid = 0;
		ALuint id = load_wave(fname);

/* throw everything in one buffer, if it doesn't fit, 
 * the source material should've been a stream and not a sample */
		if (id != AL_NONE){
			aobj->kind = AOBJ_SAMPLE;
			aobj->gain = gain;
			aobj->n_streambuf = 1;
			aobj->streambuf[0] = id;
			aobj->used = 1;

			if (err)
				*err = ARCAN_OK;
		}
		else{
			arcan_audio_free(rid);
			rid = ARCAN_EID;
			if (err)
				*err = ARCAN_ERRC_BAD_RESOURCE;
		}
		
	}
	
	return rid;
}

arcan_errc arcan_audio_hookfeed(arcan_aobj_id id, void* tag, 
	arcan_monafunc_cb hookfun, void** oldtag)
{
	arcan_aobj* aobj = arcan_audio_getobj(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	
	if (aobj){
		if (oldtag)
			*oldtag = aobj->monitortag ? aobj->monitortag : NULL;
	
		aobj->monitor = hookfun;
		aobj->monitortag = tag;
		
		rv = ARCAN_OK;
	}
	
	return rv;
}

arcan_aobj_id arcan_audio_feed(arcan_afunc_cb feed, void* tag, arcan_errc* errc)
{
	arcan_aobj* aobj;
	arcan_aobj_id rid = arcan_audio_alloc(&aobj);
	arcan_errc rc = ARCAN_ERRC_OUT_OF_SPACE;

	if (aobj) {
		aobj->streaming = true;
		aobj->tag = tag;
		aobj->n_streambuf = ARCAN_ASTREAMBUF_LIMIT;
		aobj->feed = feed;
		aobj->gain = 1.0;
		aobj->kind = AOBJ_STREAM;
		alGenBuffers(aobj->n_streambuf, aobj->streambuf);
		_wrap_alError(NULL, "audio_feed(genBuffers)");

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

	if (aobj && aobj->alid) {
		alSourceStop(aobj->alid);
		alDeleteBuffers(aobj->n_streambuf, aobj->streambuf);
		alDeleteSources(1, &aobj->alid);
		alGenSources(1, &aobj->alid);
		alGenBuffers(aobj->n_streambuf, aobj->streambuf);
		_wrap_alError(NULL, "audio_rebuild(Delete/Stop/Delete/Gen/Buffer)");

		rv = ARCAN_OK;
	}

	return rv;
}

enum aobj_kind arcan_audio_kind(arcan_aobj_id id)
{
	arcan_aobj* aobj = arcan_audio_getobj(id);
	return aobj ? aobj->kind : AOBJ_INVALID;
}

arcan_errc arcan_audio_suspend()
{
	arcan_errc rv = ARCAN_ERRC_BAD_ARGUMENT;

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
	arcan_aobj* current = current_acontext->first;

	while (current) {
		arcan_audio_play(current->id, false, 1.0);
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

	if (dobj && dobj->alid) {
/*		int processed;
		alGetSourcei(dobj->alid, AL_BUFFERS_PROCESSED, &processed);
		alSourceUnqueueBuffers(dobj->alid, 1, (unsigned int*) &processed);
		dobj->used -= processed; */ 
		alSourceStop(dobj->alid);
		_wrap_alError(dobj, "audio_pause(get/unqueue/stop)"); 
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
/* callback with empty buffers means that we want to clean up */
		if (dobj->feed)
			dobj->feed(dobj, id, 0, dobj->tag);

		_wrap_alError(dobj, "audio_stop(stop)"); 
		arcan_audio_free(id);

/* different from the finished/stopped event */
		arcan_event newevent = {
			.category = EVENT_AUDIO, 
			.kind = EVENT_AUDIO_OBJECT_GONE
		};
	
		newevent.data.audio.source = id;
		arcan_event_enqueue(arcan_event_defaultctx(), &newevent);
		rv = ARCAN_OK;
	}

	return rv;
}

static inline void reset_chain(arcan_aobj* dobj)
{
	struct arcan_achain* current = dobj->transform;
	struct arcan_achain* next;

	while (current) {
		next = current->next;
		free(current);
		current = next; 
	}

	dobj->transform = NULL;
}

arcan_errc arcan_audio_setgain(arcan_aobj_id id, float gain, uint16_t time)
{
	arcan_aobj* dobj = arcan_audio_getobj(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (dobj) {
		rv = ARCAN_OK;
	
/* immediately */
		if (time == 0){
			reset_chain(dobj);
			dobj->gain = gain;

			if (dobj->gproxy)
				dobj->gproxy(dobj->gain, dobj->tag);
			else if (dobj->alid)
				alSourcef(dobj->alid, AL_GAIN, gain);

			_wrap_alError(dobj, "audio_setgain(getSource/source)");
		}
		else{
			struct arcan_achain** dptr = &dobj->transform;
	
			while(*dptr){
				dptr = &(*dptr)->next;
			}
			
			*dptr = malloc(sizeof(struct arcan_achain));
			(*dptr)->next = NULL;
			(*dptr)->t_gain = time;
			(*dptr)->d_gain = gain;
		}
	}

	return rv;
}

static int find_bufferind(arcan_aobj* cur, unsigned bufnum){
	for (int i = 0; i < cur->n_streambuf; i++){
		if (cur->streambuf[i] == bufnum)
			return i;
	}

	return -1;
}

static int find_freebufferind(arcan_aobj* cur, bool tag){
	for (int i = 0; i < cur->n_streambuf; i++){
		if (cur->streambufmask[i] == false){
			if (tag){
				cur->used++;
				cur->streambufmask[i] = true;
			}

			return i;
		}
	}

	return -1;
}

arcan_errc arcan_audio_queuebufslot(arcan_aobj_id aid, unsigned int abufslot, 
	void* audbuf, size_t nbytes, unsigned int channels, unsigned int samplerate)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_aobj* aobj = arcan_audio_getobj(aid);

	if (aobj && abufslot < aobj->n_streambuf && aobj->streambufmask[abufslot]){
	
		if (aobj->monitor)
			aobj->monitor(aid, audbuf, nbytes, channels, 
				samplerate, aobj->monitortag);

		alBufferData(aobj->streambuf[abufslot], AL_FORMAT_STEREO16, 
			audbuf, nbytes, samplerate);
		_wrap_alError(aobj, "audio_queuebufslot()::buffer");
		
		alSourceQueueBuffers(aobj->alid, 1, &aobj->streambuf[abufslot]);
		_wrap_alError(aobj, "audio_queuebufslot()::queue buffer");

		rv = ARCAN_OK;
	}
	
	return rv;
}

void arcan_audio_buffer(arcan_aobj* aobj, ALuint buffer, void* audbuf, 
	size_t abufs, unsigned int channels, unsigned int samplerate, void* tag)
{
	if (aobj->monitor)
		aobj->monitor(aobj->id, audbuf, abufs, channels, 
			samplerate, aobj->monitortag);

	if (current_acontext->globalhook)
		current_acontext->globalhook(aobj->id, audbuf, abufs, channels, 
			samplerate, current_acontext->global_hooktag);

	if (aobj->gproxy == false)
		alBufferData(buffer, channels == 2 ? AL_FORMAT_STEREO16 : 
			AL_FORMAT_MONO16, audbuf, abufs, samplerate);
}

int arcan_audio_findstreambufslot(arcan_aobj_id id)
{
	arcan_aobj* aobj = arcan_audio_getobj(id);
	return aobj ? find_freebufferind(aobj, true) : -1;
}

static void arcan_astream_refill(arcan_aobj* current)
{
	arcan_event newevent = {
		.category = EVENT_AUDIO, 
		.kind = EVENT_AUDIO_PLAYBACK_FINISHED
	};
	ALenum state = 0;
	ALint processed = 0;
/* stopped or not, the process is the same,
 * dequeue and requeue as many buffers as possible */
	alGetSourcei(current->alid, AL_SOURCE_STATE, &state);
	alGetSourcei(current->alid, AL_BUFFERS_PROCESSED, &processed);
/* make sure to replace each one that finished with the next one */

	for (int i = 0; i < processed; i++){
		unsigned buffer = 0, bufferind;
		alSourceUnqueueBuffers(current->alid, 1, &buffer);
		bufferind = find_bufferind(current, buffer);
		assert(bufferind != -1);
		current->streambufmask[bufferind] = false;

		_wrap_alError(current, "audio_refill(refill:dequeue)");
		current->used--;

/* as soon as we've used a buffer, try to refill it.
 * for streaming source etc. try with a callback. 
 * Some frameserver modes will do this as a push rather than pull however. */
		if (current->feed){
			arcan_errc rv = current->feed(current, current->alid, 
				buffer, current->tag);
			_wrap_alError(current, "audio_refill(refill:buffer)");

			if (rv == ARCAN_OK){
				alSourceQueueBuffers(current->alid, 1, &buffer);
				current->streambufmask[bufferind] = true;
				_wrap_alError(current, "audio_refill(refill:queue)");
				current->used++;
			} 
			else if (rv == ARCAN_ERRC_NOTREADY) 
        goto playback;
			else
				goto cleanup;
		}
	}

/* if we're totally empty, try to fill all buffers,
 * if feed fails for the first one, it's over */
	if (current->used < 0)
		arcan_warning("arcan_audio(), astream_refill: inconsistency with"
			"	internal vs openAL buffers.\n");

	if (current->used < current->n_streambuf && current->feed){
		for (int i = current->used; i < sizeof(current->streambuf) / 
			sizeof(current->streambuf[0]); i++){
			int ind = find_freebufferind(current, false);
			arcan_errc rv = current->feed(current, current->alid, 
				current->streambuf[ind], current->tag);

			if (rv == ARCAN_OK){
				alSourceQueueBuffers(current->alid, 1, &current->streambuf[ind]);
				current->streambufmask[ind] = true;
				current->used++;
			} else if (rv == ARCAN_ERRC_NOTREADY)
				goto playback;
			else
				goto cleanup;
		}
	}

playback:
	if (current->used && state != AL_PLAYING){
		alSourcePlay(current->alid);
		_wrap_alError(current, "audio_restart(astream_refill)");
	}
	return;

cleanup:
arcan_warning("cleaning up\n");
/* means that when main() receives this event, it will kill/free the object */
	newevent.data.audio.source = current->id;
	arcan_event_enqueue(arcan_event_defaultctx(), &newevent);
}

char** arcan_audio_capturelist()
{
	static char** capturelist;

/* free possibly previous result */
	if (capturelist){
		char** cur = capturelist;
		while (*cur){
			free(*cur);
			*cur = NULL;
			cur++;
		}
		
		free(capturelist);
	}

/* convert from ALs list format to NULL terminated array of strings */
	const ALchar* list = alcGetString(NULL, ALC_CAPTURE_DEVICE_SPECIFIER);
	const ALchar* base = list;

	int elemc = 0;

	while (*list) {
		size_t len = strlen(list);
		if (len)
			elemc++;

		list += len + 1;
	};

	capturelist = malloc(sizeof(char*) * (elemc + 1));
	elemc = 0;

	list = base;
	while (*list){
		size_t len = strlen(list);
		if (len){
			capturelist[elemc] = strdup(list);
			elemc++;
		}

		list += len + 1;
	}

	capturelist[elemc] = NULL;
	return capturelist;
}

/* default feed function for capture devices,
 * it just maps to the buffer refill/capture used elsewhere,
 * then it's up to the monitoring function of the recording 
 * frameserver to do the mixing */
static arcan_errc capturefeed(arcan_aobj* aobj, arcan_aobj_id id, 
	unsigned buffer, void* tag)
{
	arcan_errc rv = ARCAN_ERRC_NOTREADY;
	if (buffer > 0){
/* though a single capture buffer is shared, we don't want it allocated 
 * statically as some AL implementations behaved incorrectly and overflowed 
 * into other members making it more difficult to track down than necessary */
		static int16_t* capturebuf;
		if (!capturebuf)
			capturebuf = malloc(1024 * 4); 
		
		ALCint sample;
		ALCdevice* dev = (ALCdevice*) tag;

		alcGetIntegerv(dev, ALC_CAPTURE_SAMPLES, (ALCsizei)sizeof(ALint), &sample);
		sample = sample > 1024 ? 1024 : sample;

		if (sample > 0){
			alcCaptureSamples(dev, (ALCvoid *)capturebuf, sample); 
			
			if (aobj->monitor)
				aobj->monitor(aobj->id, (uint8_t*) capturebuf, sample << 2, 
					ARCAN_SHMPAGE_ACHANNELS, ARCAN_SHMPAGE_SAMPLERATE, aobj->monitortag);

			if (current_acontext->globalhook)
				current_acontext->globalhook(aobj->id, (uint8_t*) capturebuf, 
					sample << 2, ARCAN_SHMPAGE_ACHANNELS, ARCAN_SHMPAGE_SAMPLERATE, 
					current_acontext->global_hooktag);
		}
	}
	
	return rv;
}

arcan_aobj_id arcan_audio_capturefeed(const char* dev)
{
	arcan_aobj* dstobj = NULL;
	ALCdevice* capture = alcCaptureOpenDevice(dev, 
		ARCAN_SHMPAGE_SAMPLERATE, AL_FORMAT_STEREO16, 65536);
	arcan_audio_alloc(&dstobj);

/* we let OpenAL maintain the capture buffer, we flush it like other feeds
 * and resend it back into the playback chain, so that monitoring etc. 
 * gets reused */
	if (_wrap_alError(dstobj, "capture-device") && dstobj){
		dstobj->streaming = true;
		dstobj->gain = 1.0;
		dstobj->kind = AOBJ_CAPTUREFEED;
		dstobj->n_streambuf = ARCAN_ASTREAMBUF_LIMIT;
		dstobj->feed = capturefeed;
		dstobj->tag = capture;
	
		alGenBuffers(dstobj->n_streambuf, dstobj->streambuf);
		alcCaptureStart(capture);
		return dstobj->id;
	}
	else{
		arcan_warning("could get audio lock\n");
		if (capture){
			alcCaptureStop(capture);
			alcCaptureCloseDevice(capture);
		}
		
		if (dstobj)
			arcan_audio_free(dstobj->id);
	}
	
	return ARCAN_EID;
}

void arcan_audio_refresh()
{
	if (!current_acontext->context || !current_acontext->al_active)
		return;

	arcan_aobj* current = current_acontext->first;

	while(current){
		if (current->kind == AOBJ_STREAM ||
			current->kind == AOBJ_FRAMESTREAM ||
			current->kind == AOBJ_CAPTUREFEED){
			arcan_astream_refill(current);
		}

		_wrap_alError(current, "audio_refresh()");
		current = current->next;
	}
}	

static inline bool step_transform(arcan_aobj* obj)
{
	if (obj->transform == NULL)
		return false;

/* OpenAL maps dB to linear */
	obj->gain += (obj->transform->d_gain - obj->gain) /
		(float) obj->transform->t_gain;

	obj->transform->t_gain--;
	if (obj->transform->t_gain == 0){
		obj->gain = obj->transform->d_gain;
		struct arcan_achain* ct = obj->transform;
		obj->transform = obj->transform->next;
		free(ct);
	}

	return true;
}

void arcan_audio_tick(uint8_t ntt)
{
/*
 * scan list of allocated IDs and update buffers for all streaming / cb 
 * functions, also make sure our context is the current active one, 
 * flush error buffers etc. 
 */
	if (!current_acontext->context || !current_acontext->al_active)
		return;

	if (alcGetCurrentContext() != current_acontext->context)
		alcMakeContextCurrent(current_acontext->context);

	arcan_audio_refresh();

/* update time-dependent transformations */	
	while (ntt-- > 0) {
		arcan_aobj* current = current_acontext->first;

		while (current){
			if (step_transform(current)){
				if (current->gproxy)
					current->gproxy(current->gain, current->tag);
				else
					alSourcef(current->alid, AL_GAIN, current->gain);
				_wrap_alError(current, "audio_tick(source/gain)");
			}
			
			current = current->next;
		}
	}
/* scan all streaming buffers and free up those no-longer needed */	
	for (unsigned i = 0; i < ARCAN_AUDIO_SLIMIT; i++)
	if ( current_acontext->sample_sources[i] > 0) {
		ALint state;
		alGetSourcei(current_acontext->sample_sources[i], AL_SOURCE_STATE, &state);
		if (state != AL_PLAYING){
			alDeleteSources(1, &current_acontext->sample_sources[i]);
			current_acontext->sample_sources[i] = 0;
		}
	}
}	

static bool _wrap_alError(arcan_aobj* obj, char* prefix)
{
	ALenum errc = alGetError();
	arcan_aobj empty = {.id = 0, .alid = 0};
	if (!obj)
		obj = &empty;

	if (errc != AL_NO_ERROR) {
		arcan_warning("(openAL): ");
		
		switch (errc) {
		case AL_INVALID_NAME:
			arcan_warning("(%u:%u), %s - bad ID passed to function\n", 
				obj->id, obj->alid, prefix);
			break;
		case AL_INVALID_ENUM:
			arcan_warning("(%u:%u), %s - bad enum value passed to function\n", 
				obj->id, obj->alid, prefix);
			break;
		case AL_INVALID_VALUE:
			arcan_warning("(%u:%u), %s - bad value passed to function\n", 
				obj->id, obj->alid, prefix);
			break;
		case AL_INVALID_OPERATION:
			arcan_warning("(%u:%u), %s - requested operation is not valid\n", 
				obj->id, obj->alid, prefix);
			break;
		case AL_OUT_OF_MEMORY:
			arcan_warning("(%u:%u), %s - OpenAL out of memory\n", obj->id, 
				obj->alid, prefix);
			break;
		default:
			arcan_warning("(%u:%u), %s - undefined error\n", obj->id, 
				obj->alid, prefix);
		}
		return false;
	}
	
	return true;
}
