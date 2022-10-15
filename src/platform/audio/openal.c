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
#include <inttypes.h>
#include <pthread.h>

#include <al.h>
#include <alc.h>

/* Apple++ does not have the extension header in question (of course) so go
 * with lifted definitions and dynamic loading */
static void (*alc_device_pause_soft)(ALCdevice*);
static void (*alc_device_resume_soft)(ALCdevice*);

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_shmif.h"
#include "arcan_video.h"
#include "arcan_audio.h"
#include "arcan_audioint.h"
#include "arcan_event.h"
#include "platform_types.h"

#ifndef CONST_MAX_ASAMPLESZ
#define CONST_MAX_ASAMPLESZ 1048756
#endif

#ifndef ARCAN_AUDIO_SLIMIT
#define ARCAN_AUDIO_SLIMIT 32
#endif

#define ARCAN_ASTREAMBUF_LIMIT ARCAN_SHMIF_ABUFC_LIM

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

struct arcan_achain {
	unsigned t_gain;
	float d_gain;

	struct arcan_achain* next;
};

struct arcan_acontext {
/* linked list of audio sources, the number of available sources are platform /
 * hw dependant, ranging between 10-100 or so */
	arcan_aobj* first;
	ALCcontext* context;
	ALCdevice* device;

	bool al_active;

	arcan_aobj_id lastid;
	float def_gain;

/* limit on amount of simultaneous active sources */
	ALuint sample_sources[ARCAN_AUDIO_SLIMIT];
	intptr_t sample_tags[ARCAN_AUDIO_SLIMIT];

	arcan_tickv atick_counter;

	arcan_monafunc_cb globalhook;
	void* global_hooktag;
};

/* context management here is quite different from video (no push / pop / etc.
 * openAL volatility alongside hardware buffering problems etc. make it too
 * much of a hazzle */
static struct arcan_acontext _current_acontext = {
	.first = NULL, .context = NULL, .def_gain = 1.0
};
static struct arcan_acontext* current_acontext = &_current_acontext;

static bool _wrap_alError(arcan_aobj* obj, char* prefix)
{
	ALenum errc = alGetError();
	arcan_aobj empty = {.id = 0, .alid = 0};
	if (!obj)
		obj = &empty;

#ifndef _DEBUG
	return errc == AL_NO_ERROR;
#endif

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

static arcan_aobj_id arcan_audio_alloc(arcan_aobj** dst, bool defer)
{
	arcan_aobj_id rv = ARCAN_EID;
	ALuint alid = AL_NONE;
	if (dst)
		*dst = NULL;

/* some streaming sources never use their audio buffers,
 * defer until it's actually needed (and possibly passive- collect
 * when not feeding to save on IDs */
	if (!defer){
		alGenSources(1, &alid);
		alSourcef(alid, AL_GAIN, current_acontext->def_gain);
		_wrap_alError(NULL, "audio_alloc(genSources)");
		if (alid == AL_NONE)
			return rv;
	}

	arcan_aobj* newcell = arcan_alloc_mem(sizeof(arcan_aobj), ARCAN_MEM_ATAG,
		ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	newcell->alid = alid;
	newcell->gain = current_acontext->def_gain;

/* unlikely event of wrap-around */
	newcell->id = current_acontext->lastid++;
	if (newcell->id == ARCAN_EID)
		newcell->id = 1;

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

	return newcell->id;
}

static arcan_errc arcan_audio_free(arcan_aobj_id id)
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

			_wrap_alError(NULL, "audio_free(DeleteBuffers/sources)");
		}
		current->next = (void*) 0xdeadbeef;
		current->tag = (void*) 0xdeadbeef;
		current->feed = NULL;
		arcan_mem_free(current);

		rv = ARCAN_OK;
	}

	return rv;
}


static ALuint arcan_load_wave(const char* fname)
{
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

	if (smplrte != 48000 && smplrte != 44100 && smplrte != 22050 && smplrte != 11025)
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

	uint8_t* samplebuf = arcan_alloc_mem(nb,
		ARCAN_MEM_ABUFFER, 0, ARCAN_MEMALIGN_PAGE);

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
	arcan_mem_free(samplebuf);

cleanup:
	arcan_release_map(inmem);
	arcan_release_resource(&inres);

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

/* default feed function for capture devices,
 * it just maps to the buffer refill/capture used elsewhere,
 * then it's up to the monitoring function of the recording
 * frameserver to do the mixing */
static arcan_errc capturefeed(void* aobjopaq, arcan_aobj_id id,
	ssize_t buffer, bool cont, void* tag)
{
	arcan_aobj* aobj = aobjopaq;

	if (buffer < 0)
		return ARCAN_ERRC_NOTREADY;

/* though a single capture buffer is shared, we don't want it allocated
 * statically as some AL implementations behaved incorrectly and overflowed
 * into other members making it more difficult to track down than necessary */
	static int16_t* capturebuf;

	if (!capturebuf)
		capturebuf = arcan_alloc_mem(1024 * 4, ARCAN_MEM_ABUFFER,
			ARCAN_MEM_SENSITIVE, ARCAN_MEMALIGN_PAGE);

	ALCint sample;
	ALCdevice* dev = (ALCdevice*) tag;

	alcGetIntegerv(dev, ALC_CAPTURE_SAMPLES, (ALCsizei)sizeof(ALint), &sample);
	sample = sample > 1024 ? 1024 : sample;

	if (sample <= 0)
		return ARCAN_ERRC_NOTREADY;

	alcCaptureSamples(dev, (ALCvoid *)capturebuf, sample);

	if (aobj->monitor)
		aobj->monitor(aobj->id, (uint8_t*) capturebuf, sample << 2,
			ARCAN_SHMIF_ACHANNELS, ARCAN_SHMIF_SAMPLERATE, aobj->monitortag);

	if (current_acontext->globalhook)
		current_acontext->globalhook(aobj->id, (uint8_t*) capturebuf,
			sample << 2, ARCAN_SHMIF_ACHANNELS, ARCAN_SHMIF_SAMPLERATE,
			current_acontext->global_hooktag
		);

	return ARCAN_OK;
}

static inline void reset_chain(arcan_aobj* dobj)
{
	struct arcan_achain* current = dobj->transform;
	struct arcan_achain* next;

	while (current) {
		next = current->next;
		arcan_mem_free(current);
		current = next;
	}

	dobj->transform = NULL;
}

static ssize_t find_bufferind(arcan_aobj* cur, unsigned bufnum)
{
	for (size_t i = 0; i < cur->n_streambuf; i++){
		if (cur->streambuf[i] == bufnum)
			return i;
	}

	return -1;
}

static ssize_t find_freebufferind(arcan_aobj* cur, bool tag)
{
	for (size_t i = 0; i < cur->n_streambuf; i++){
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

static void astream_refill(arcan_aobj* current)
{
	arcan_event newevent = {
		.category = EVENT_AUDIO,
		.aud.kind = EVENT_AUDIO_PLAYBACK_FINISHED
	};
	ALenum state = 0;
	ALint processed = 0;

	if (current->alid == AL_NONE && current->feed){
		current->feed(current, current->alid, 0, false, current->tag);
		return;
	}

/* stopped or not, the process is the same,
 * dequeue and requeue as many buffers as possible */
	alGetSourcei(current->alid, AL_SOURCE_STATE, &state);
	alGetSourcei(current->alid, AL_BUFFERS_PROCESSED, &processed);
/* make sure to replace each one that finished with the next one */

	for (size_t i = 0; i < processed; i++){
		unsigned buffer = 1;
		alSourceUnqueueBuffers(current->alid, 1, &buffer);
		ssize_t bufferind = find_bufferind(current, buffer);
		if (-1 == bufferind){
			arcan_warning("(audio) unqueue returned unknown buffer, "
				"processed (%d)\n", (int) bufferind);
			continue;
		}

		current->streambufmask[bufferind] = false;

		_wrap_alError(current, "audio_refill(refill:dequeue)");
		current->used--;

/* as soon as we've used a buffer, try to refill it.
 * for streaming source etc. try with a callback.
 * Some frameserver modes will do this as a push rather than pull however. */
		if (current->feed){
			arcan_errc rv = current->feed(current, current->alid,
				buffer, i < processed - 1, current->tag);
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
		size_t lim = sizeof(current->streambuf) / sizeof(current->streambuf[0]);
		for (size_t i = current->used; i < lim; i++){
			int ind = find_freebufferind(current, false);
			if (-1 == ind)
				break;

			arcan_errc rv = current->feed(current, current->alid,
				current->streambuf[ind], find_freebufferind(
				current, false) != -1, current->tag
			);

			if (rv == ARCAN_OK){
				alSourceQueueBuffers(current->alid, 1, &current->streambuf[ind]);
				current->streambufmask[ind] = true;
				current->used++;
			}
			else if (rv == ARCAN_ERRC_NOTREADY)
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
/* enqueue direct into drain, this might invoke audio callback on the scripting
 * side in order to immediately chain the playback of another sample */
	newevent.aud.source = current->id;
	arcan_event_denqueue(arcan_event_defaultctx(), &newevent);
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

static int16_t float_s16(float val)
{
	if (val < 0.0)
		return -val * -32768.0;
	else
		return val * 32767.0;
}

void platform_audio_preinit()
{
}

bool platform_audio_init(bool noaudio)
{
	bool rv = false;

/* don't supported repeated calls without shutting down in between */
	if (current_acontext && !current_acontext->context) {
		ALCint attrs[] = {
			ALC_FREQUENCY, ARCAN_SHMIF_SAMPLERATE,
			0
		};

/* unfortunately, the pretty poorly thought out alcOpenDevice/alcCreateContext
 * doesn't allow you to create a nosound or debug/testing audio device (or for
 * that matter, enumerate without an extension, seriously..) so to avoid yet
 * another codepath, we'll just set the listenerGain to 0 */
#ifdef ARCAN_LWA
		current_acontext->device = alcOpenDevice("arcan");
#else
		current_acontext->device = alcOpenDevice(NULL);
#endif
		current_acontext->context = alcCreateContext(current_acontext->device, attrs);
		alcMakeContextCurrent(current_acontext->context);

		if (noaudio){
			alListenerf(AL_GAIN, 0.0);
		}

		if (
			alcIsExtensionPresent(current_acontext->device, "alcDevicePauseSOFT") &&
			alcIsExtensionPresent(current_acontext->device, "alcDeviceResumeSOFT"))
		{
			alc_device_pause_soft = alcGetProcAddress(
				current_acontext->device, "alcDevicePauseSOFT");
			alc_device_resume_soft = alcGetProcAddress(
				current_acontext->device, "alcDeviceResumeSOFT");
		}

		current_acontext->al_active = true;
		rv = true;

		/* just give a slightly "random" base so that
		 user scripts don't get locked into hard-coded ids .. */
		arcan_random((unsigned char*)&current_acontext->lastid, sizeof(arcan_aobj_id));
	}

	return rv;
}

void platform_audio_suspend()
{
	arcan_aobj* current = current_acontext->first;

	while (current) {
		if (current->id != AL_NONE)
			platform_audio_pause(current->id);

		current = current->next;
	}

	current_acontext->al_active = false;
	if (alc_device_pause_soft)
		alc_device_pause_soft(current_acontext->device);
}

void platform_audio_resume()
{
	arcan_aobj* current = current_acontext->first;

	if (alc_device_resume_soft)
		alc_device_resume_soft(current_acontext->device);

	while (current) {
		if (current->id != AL_NONE)
			platform_audio_play(current->id, false, 1.0, -2);
		current = current->next;
	}

	current_acontext->al_active = true;
}

void platform_audio_tick(uint8_t ntt)
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

	platform_audio_refresh();

/* update time-dependent transformations */
	while (ntt-- > 0) {
		arcan_aobj* current = current_acontext->first;

		while (current){
			if (step_transform(current)){
				if (current->gproxy)
					current->gproxy(current->gain, current->tag);
				else if (current->alid){
					alSourcef(current->alid, AL_GAIN, current->gain);
					_wrap_alError(current, "audio_tick(source/gain)");
				}
			}

			current = current->next;
		}

		current_acontext->atick_counter++;
	}

/* scan all streaming buffers and free up those no-longer needed */
	for (size_t i = 0; i < ARCAN_AUDIO_SLIMIT; i++)
	if ( current_acontext->sample_sources[i] > 0) {
		ALint state;
		alGetSourcei(current_acontext->sample_sources[i], AL_SOURCE_STATE, &state);
		if (state != AL_PLAYING){
			alDeleteSources(1, &current_acontext->sample_sources[i]);
			current_acontext->sample_sources[i] = 0;

			if (current_acontext->sample_tags[i] != 0){
				arcan_event_enqueue(arcan_event_defaultctx(),
				&(struct arcan_event){
					.category = EVENT_AUDIO,
					.aud.kind = EVENT_AUDIO_PLAYBACK_FINISHED,
					.aud.otag = current_acontext->sample_tags[i]
				});
				current_acontext->sample_tags[i] = 0;
			}
		}
	}
}

size_t platform_audio_refresh()
{
	if (!current_acontext->context || !current_acontext->al_active)
		return 0;

	arcan_aobj* current = current_acontext->first;
	size_t rv = 0;

	while(current){
		if (
			current->kind == AOBJ_STREAM      ||
			current->kind == AOBJ_FRAMESTREAM ||
			current->kind == AOBJ_CAPTUREFEED
		)
			astream_refill(current);

		_wrap_alError(current, "audio_refresh()");
		if (current->used)
			rv++;

		current = current->next;
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

void platform_audio_shutdown()
{
	ALCcontext* ctx = current_acontext->context;
	if (!ctx)
		return;

/* there might be more to clean-up here, monitoring /callback buffers/tags */

	alcDestroyContext(ctx);
	current_acontext->al_active = false;
	current_acontext->context = NULL;
	memset(current_acontext->sample_sources,
		'\0', sizeof(ALuint) * ARCAN_AUDIO_SLIMIT);
}

bool platform_audio_rebuild(arcan_aobj_id id)
{
	arcan_aobj* aobj = arcan_audio_getobj(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	if (!aobj || aobj->alid == AL_NONE)
		return false;

	alSourceStop(aobj->alid);
	_wrap_alError(NULL, "audio_rebuild(stop)");

	int n;
	while(alGetSourcei(aobj->alid, AL_BUFFERS_PROCESSED, &n), n > 0){
		unsigned buffer = 0;
		alSourceUnqueueBuffers(aobj->alid, 1, &buffer);
		int bufferind = find_bufferind(aobj, buffer);
		if (bufferind >= 0){
			aobj->streambufmask[bufferind] = false;
			aobj->used--;
		}
	}

	alDeleteSources(1, &aobj->alid);
	alGenSources(1, &aobj->alid);
	alSourcef(aobj->alid, AL_GAIN, aobj->gain);

	_wrap_alError(NULL, "audio_rebuild(recreate)");

	return true;
}

bool platform_audio_hookfeed(arcan_aobj_id id, void* tag, arcan_monafunc_cb hookfun, void** oldtag)
{
	arcan_aobj* aobj = arcan_audio_getobj(id);
	if (!aobj)
		return false;

	if (oldtag)
		*oldtag = aobj->monitortag ? aobj->monitortag : NULL;

	aobj->monitor = hookfun;
	aobj->monitortag = tag;

	return true;
}

arcan_aobj_id platform_audio_load_sample(
	const char* fname, float gain, arcan_errc* err)
{
	arcan_aobj* aobj;
	arcan_aobj_id rid = arcan_audio_alloc(&aobj, true);

	if (rid == ARCAN_EID){
		if (err) *err = ARCAN_ERRC_OUT_OF_SPACE;
		return ARCAN_EID;
	}

	ALuint id = arcan_load_wave(fname);
	if (id == AL_NONE){
		if (err) *err = ARCAN_ERRC_BAD_RESOURCE;
		arcan_audio_free(id);
		return ARCAN_EID;
	}

	aobj->kind = AOBJ_SAMPLE;
	aobj->gain = gain;
	aobj->n_streambuf = 1;
	aobj->streambuf[0] = id;
	aobj->used = 1;

	if (err) *err = ARCAN_OK;

	return rid;
}

arcan_aobj_id platform_audio_sample_buffer(float* buffer, size_t elems, int channels, int samplerate, const char* fmt_specifier)
{
	arcan_aobj* aobj;
	arcan_aobj_id rid = arcan_audio_alloc(&aobj, true);
	ALuint id = 0;

	if (rid == ARCAN_EID)
		return ARCAN_EID;

	alGenBuffers(1, &id);
	if (!alcIsExtensionPresent(current_acontext->device, "AL_EXT_float32")){
		int16_t* samplebuf = arcan_alloc_mem(
			elems * 2, ARCAN_MEM_ABUFFER, 0, ARCAN_MEMALIGN_PAGE);

		for (size_t i = 0; i < elems; i++){
			samplebuf[i] = float_s16(buffer[i]);
		}

		alBufferData(id,
			channels == 1 ? AL_FORMAT_MONO16 : AL_FORMAT_STEREO16,
			(uint8_t*)samplebuf, elems * 2, samplerate
		);
		arcan_mem_free(samplebuf);
	}
	else {
		int fmt = alGetEnumValue(
			channels == 1 ? "AL_FORMAT_MONO_FLOAT32" : "AL_FORMAT_STEREO_FLOAT32");
		alBufferData(id, fmt, buffer, elems * sizeof(float), samplerate);
	}

	aobj->kind = AOBJ_SAMPLE;
	aobj->gain = 1.0;
	aobj->n_streambuf = 1;
	aobj->streambuf[0] = id;
	aobj->used = 1;

	return rid;
}

bool platform_audio_alterfeed(arcan_aobj_id id, arcan_afunc_cb cb)
{
	bool rv = false;
	arcan_aobj* obj = arcan_audio_getobj(id);

	if (obj) {
		if (!cb)
			rv = ARCAN_ERRC_BAD_ARGUMENT;
		else {
			obj->feed = cb;
			rv = true;
		}
	}

	return rv;
}

arcan_aobj_id platform_audio_feed(arcan_afunc_cb feed, void* tag, arcan_errc* errc)
{
	arcan_aobj* aobj;
	arcan_aobj_id rid = arcan_audio_alloc(&aobj, true);
	if (!aobj){
		if (errc) *errc = ARCAN_ERRC_OUT_OF_SPACE;
		return ARCAN_EID;
	}

/* the id will be allocated when we first get data as there
 * is a limit to how many streaming / mixed sources we can support */
	aobj->alid = AL_NONE;
	aobj->streaming = true;
	aobj->tag = tag;
	aobj->n_streambuf = ARCAN_ASTREAMBUF_LIMIT;
	aobj->feed = feed;
	aobj->gain = 1.0;
	aobj->kind = AOBJ_STREAM;

	if (errc) *errc = ARCAN_OK;
	return rid;
}

enum aobj_kind platform_audio_kind(arcan_aobj_id id)
{
	arcan_aobj* aobj = arcan_audio_getobj(id);
	return aobj ? aobj->kind : AOBJ_INVALID;
}

bool platform_audio_stop(arcan_aobj_id id)
{
	arcan_aobj* dobj = arcan_audio_getobj(id);
	if (!dobj)
		return false;

	dobj->kind = AOBJ_INVALID;
	dobj->feed = NULL;

	arcan_audio_free(id);

	arcan_event newevent = {
		.category = EVENT_AUDIO,
		.aud.kind = EVENT_AUDIO_OBJECT_GONE,
		.aud.source = id
	};

	arcan_event_enqueue(arcan_event_defaultctx(), &newevent);
	return true;
}

bool platform_audio_play(
	arcan_aobj_id id, bool gain_override, float gain, intptr_t tag)
{
	arcan_aobj* aobj = arcan_audio_getobj(id);

	if (!aobj)
		return false;

/* for aobj sample, just find a free sample slot (if any) and
 * attach the buffer already part of the aobj */
	if (aobj->kind == AOBJ_SAMPLE){
		for (size_t i = 0; i < ARCAN_AUDIO_SLIMIT; i++)
			if (current_acontext->sample_sources[i] == 0){
				alGenSources(1, &current_acontext->sample_sources[i]);
				ALint alid = current_acontext->sample_sources[i];
				current_acontext->sample_tags[i] = tag;
				alSourcef(alid, AL_GAIN, gain_override ? gain : aobj->gain);
				_wrap_alError(aobj,"load_sample(alSource)");

				alSourceQueueBuffers(alid, 1, &aobj->streambuf[0]);
				_wrap_alError(aobj, "load_sample(alQueue)");
				alSourcePlay(alid);
				break;
			}
	}
/* some kind of streaming source, can't play if it is already active */
	else if (aobj->active == false && aobj->alid != AL_NONE){
		alSourcePlay(aobj->alid);
		_wrap_alError(aobj, "play(alSourcePlay)");
		aobj->active = true;
	}

	return true;
}

bool platform_audio_pause(arcan_aobj_id id)
{
	arcan_aobj* dobj = arcan_audio_getobj(id);
	bool rv = false;

	if (dobj && dobj->alid != AL_NONE) {
/*
 * int processed;
 * alGetSourcei(dobj->alid, AL_BUFFERS_PROCESSED, &processed);
 * alSourceUnqueueBuffers(dobj->alid, 1, (unsigned int*) &processed);
 * dobj->used -= processed;
 */
		alSourceStop(dobj->alid);
		_wrap_alError(dobj, "audio_pause(get/unqueue/stop)");
		dobj->active = false;
		rv = true;
	}

	return rv;
}

bool platform_audio_rewind(arcan_aobj_id id)
{
	arcan_aobj* aobj = arcan_audio_getobj(id);
	bool rv = false;

	if (aobj && aobj->alid != AL_NONE) {
/* TODO Implement OpenAL rewind */
		rv = true;
	}

	return rv;
}

void platform_audio_capturelist(char** capturelist)
{
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

	capturelist = arcan_alloc_mem(sizeof(char*) * (elemc + 1),
		ARCAN_MEM_STRINGBUF, 0, ARCAN_MEMALIGN_NATURAL);

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
}

arcan_aobj_id platform_audio_capturefeed(const char* identifier)
{
	arcan_aobj* dstobj = NULL;
	ALCdevice* capture = alcCaptureOpenDevice(identifier,
		ARCAN_SHMIF_SAMPLERATE, AL_FORMAT_STEREO16, 65536);
	arcan_audio_alloc(&dstobj, false);

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
		arcan_warning("arcan_audio_capturefeed() - could get audio lock\n");
		if (capture){
			alcCaptureStop(capture);
			alcCaptureCloseDevice(capture);
		}

		if (dstobj)
			arcan_audio_free(dstobj->id);
	}

	return ARCAN_EID;
}

bool platform_audio_setgain(arcan_aobj_id id, float gain, uint16_t time)
{
	if (id == ARCAN_EID){
		current_acontext->def_gain = gain;
		return true;
	}

	arcan_aobj* dobj = arcan_audio_getobj(id);

	if (!dobj)
		return false;

/* immediately */
	if (time == 0){
		reset_chain(dobj);
		dobj->gain = gain;

		if (dobj->gproxy)
			dobj->gproxy(dobj->gain, dobj->tag);
		else if (dobj->alid){
			alSourcef(dobj->alid, AL_GAIN, gain);
			_wrap_alError(dobj, "audio_setgain(getSource/source)");
		}
		else
			;
	}
	else{
		struct arcan_achain** dptr = &dobj->transform;

		while(*dptr){
			dptr = &(*dptr)->next;
		}

		*dptr = arcan_alloc_mem(sizeof(struct arcan_achain),
			ARCAN_MEM_ATAG, 0, ARCAN_MEMALIGN_NATURAL);

		(*dptr)->next = NULL;
		(*dptr)->t_gain = time;
		(*dptr)->d_gain = gain;
	}

	return true;
}

bool platform_audio_getgain(arcan_aobj_id id, float* gain)
{
	if (id == ARCAN_EID){
		if (gain)
			*gain = current_acontext->def_gain;
		return true;
	}

	arcan_aobj* dobj = arcan_audio_getobj(id);

	if (!dobj)
		return false;

	if (gain)
		*gain = dobj->gain;

	return true;
}

void platform_audio_buffer(void* aobjopaq, ssize_t buffer, void* audbuf,
	size_t abufs, unsigned int channels, unsigned int samplerate, void* tag)
{
	arcan_aobj* aobj = aobjopaq;
/*
 * even if the AL subsystem should fail, our monitors and globalhook
 * can still work (so record, streaming etc. doesn't cascade)
 */
	if (aobj->monitor)
		aobj->monitor(aobj->id, audbuf, abufs, channels,
			samplerate, aobj->monitortag);

	if (current_acontext->globalhook)
		current_acontext->globalhook(aobj->id, audbuf, abufs, channels,
			samplerate, current_acontext->global_hooktag);

/*
 * the audio system can bounce back in the case of many allocations
 * exceeding what can be mixed internally, through the _tick mechanism
 * keeping track of which sources that are actively in use and freeing
 * up those that havn't seen any use for a while.
 */
	if (aobj->alid == AL_NONE){
		alGenSources(1, &aobj->alid);
		alGenBuffers(aobj->n_streambuf, aobj->streambuf);
		alSourcef(aobj->alid, AL_GAIN, aobj->gain);

		alSourceQueueBuffers(aobj->alid, 1, &aobj->streambuf[0]);
		aobj->streambufmask[0] = true;
		aobj->used++;
		alSourcePlay(aobj->alid);

	_wrap_alError(NULL, "audio_feed(genBuffers)");
	}
	else if (aobj->gproxy == false){
		aobj->last_used = current_acontext->atick_counter;
		alBufferData(buffer, channels == 2 ? AL_FORMAT_STEREO16 :
			AL_FORMAT_MONO16, audbuf, abufs, samplerate);
	}
}

void platform_audio_aid_refresh(arcan_aobj_id aid)
{
	struct arcan_aobj* obj = arcan_audio_getobj(aid);
	if (obj)
		astream_refill(obj);
}

/*
 * very inefficient, but the set of IDs to delete is reasonably small
 */
void platform_audio_purge(arcan_aobj_id* save, size_t save_count)
{
	arcan_aobj* current = _current_acontext.first;
	arcan_aobj** previous = &_current_acontext.first;

	while(current){
		bool match = false;

		for (size_t i = 0; i < save_count; i++){
			if (save[i] == current->id){
				match = true;
				break;
			}
		}

		arcan_aobj* next = current->next;
		if (!match){
			(*previous) = next;
			if (current->feed)
				current->feed(current, current->id, -1, false, current->tag);

			_wrap_alError(current, "audio_stop(stop)");

			if (current->alid != AL_NONE){
				alSourceStop(current->alid);
				alDeleteSources(1, &current->alid);

				if (current->n_streambuf)
					alDeleteBuffers(current->n_streambuf, current->streambuf);
			}

			arcan_mem_free(current);
		}
		else {
			previous = &current->next;
		}

		current = next;
	}
}
