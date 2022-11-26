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
	arcan_aobj_id lastid;
	float def_gain;

	arcan_tickv atick_counter;

	arcan_monafunc_cb globalhook;
	void* global_hooktag;
};

/* context management here is quite different from video (no push / pop / etc.
 * openAL volatility alongside hardware buffering problems etc. make it too
 * much of a hazzle */
static struct arcan_acontext _current_acontext = {
	.first = NULL, .def_gain = 1.0
};
static struct arcan_acontext* current_acontext = &_current_acontext;

static arcan_aobj_id arcan_audio_alloc(arcan_aobj** dst, bool defer)
{
	arcan_aobj_id rv = ARCAN_EID;
	if (dst)
		*dst = NULL;

	arcan_aobj* newcell = arcan_alloc_mem(
		sizeof(arcan_aobj), ARCAN_MEM_ATAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

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

		current->next = (void*) 0xdeadbeef;
		current->tag = (void*) 0xdeadbeef;
		current->feed = NULL;
		arcan_mem_free(current);

		rv = ARCAN_OK;
	}

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

static arcan_errc capturefeed(
	void* aobjopaq, arcan_aobj_id id, ssize_t buffer, bool cont, void* tag)
{
	arcan_aobj* aobj = aobjopaq;
	return ARCAN_ERRC_NOTREADY;
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

static void astream_refill(arcan_aobj* current)
{
	arcan_event newevent = {
		.category = EVENT_AUDIO,
		.aud.kind = EVENT_AUDIO_PLAYBACK_FINISHED
	};

	if (current->feed){
		current->feed(current, 0, 0, false, current->tag);
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

void platform_audio_preinit()
{
}

bool platform_audio_init(bool noaudio)
{
	arcan_random((unsigned char*)&current_acontext->lastid, sizeof(arcan_aobj_id));
	return true;
}

void platform_audio_suspend()
{
}

void platform_audio_resume()
{
	arcan_aobj* current = current_acontext->first;

	while (current) {
		platform_audio_play(current->id, false, 1.0, -2);
		current = current->next;
	}
}

void platform_audio_tick(uint8_t ntt)
{
	platform_audio_refresh();

/* update time-dependent transformations */
	while (ntt-- > 0) {
		arcan_aobj* current = current_acontext->first;

		while (current){
			if (step_transform(current)){
				if (current->gproxy)
					current->gproxy(current->gain, current->tag);
			}

			current = current->next;
		}

		current_acontext->atick_counter++;
	}
}

size_t platform_audio_refresh()
{
	arcan_aobj* current = current_acontext->first;
	size_t rv = 0;

	while(current){
		if (
			current->kind == AOBJ_STREAM      ||
			current->kind == AOBJ_FRAMESTREAM ||
			current->kind == AOBJ_CAPTUREFEED
		)
			astream_refill(current);

		if (current->used)
			rv++;

		current = current->next;
	}

	return rv;
}

void platform_audio_shutdown()
{
}

bool platform_audio_rebuild(arcan_aobj_id id)
{
	return true;
}

bool platform_audio_hookfeed(
	arcan_aobj_id id, void* tag, arcan_monafunc_cb hookfun, void** oldtag)
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

	aobj->kind = AOBJ_SAMPLE;
	aobj->gain = gain;
	aobj->n_streambuf = 1;
	aobj->used = 1;

	if (err) *err = ARCAN_OK;

	return rid;
}

arcan_aobj_id platform_audio_sample_buffer(
	float* buffer, size_t elems, int channels, int samplerate, const char* fmt_specifier)
{
	arcan_aobj* aobj;
	arcan_aobj_id rid = arcan_audio_alloc(&aobj, true);

	if (rid == ARCAN_EID)
		return ARCAN_EID;

	aobj->kind = AOBJ_SAMPLE;
	aobj->gain = 1.0;
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
	return arcan_audio_getobj(id) != NULL;
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
	return arcan_audio_getobj(id) != NULL;
}

bool platform_audio_pause(arcan_aobj_id id)
{
	return arcan_audio_getobj(id) != NULL;
}

bool platform_audio_rewind(arcan_aobj_id id)
{
	return arcan_audio_getobj(id) != NULL;
}

void platform_audio_capturelist(char** capturelist)
{
	capturelist = arcan_alloc_mem(
		sizeof(char*), ARCAN_MEM_STRINGBUF, 0, ARCAN_MEMALIGN_NATURAL);

	capturelist[0] = NULL;
}

arcan_aobj_id platform_audio_capturefeed(const char* identifier)
{
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
}

void platform_audio_aid_refresh(arcan_aobj_id aid)
{
	struct arcan_aobj* obj = arcan_audio_getobj(aid);
	if (obj)
		astream_refill(obj);
}

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

			arcan_mem_free(current);
		}
		else {
			previous = &current->next;
		}

		current = next;
	}
}
