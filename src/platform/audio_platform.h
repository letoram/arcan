#ifndef HAVE_ARCAN_AUDIOPLATFORM
#define HAVE_ARCAN_AUDIOPLATFORM

#include "platform_types.h"

void platform_audio_preinit();

bool platform_audio_init(bool nosound);

void platform_audio_suspend();

void platform_audio_resume();

void platform_audio_tick(uint8_t ntt);

size_t platform_audio_refresh();

void platform_audio_shutdown();

bool platform_audio_rebuild(arcan_aobj_id id);

bool platform_audio_hookfeed(
	arcan_aobj_id id, void* tag, arcan_monafunc_cb hookfun, void** oldtag);

arcan_aobj_id platform_audio_load_sample(
	const char* fname, float gain, arcan_errc* err);

arcan_aobj_id platform_audio_sample_buffer(float* buffer,
	size_t elems, int channels, int samplerate, const char* fmt_specifier);

bool platform_audio_alterfeed(arcan_aobj_id id, arcan_afunc_cb cb);

arcan_aobj_id platform_audio_feed(
	arcan_afunc_cb feed, void* tag, arcan_errc* errc);

enum aobj_kind platform_audio_kind(arcan_aobj_id id);

bool platform_audio_stop(arcan_aobj_id id);

bool platform_audio_play(
	arcan_aobj_id id, bool gain_override, float gain, intptr_t tag);

bool platform_audio_pause(arcan_aobj_id id);

bool platform_audio_rewind(arcan_aobj_id id);

void platform_audio_capturelist(char** capturelist);

arcan_aobj_id platform_audio_capturefeed(const char* identifier);

bool platform_audio_setgain(arcan_aobj_id id, float gain, uint16_t time);

bool platform_audio_getgain(arcan_aobj_id id, float* cgain);

void platform_audio_buffer(void* aobj, ssize_t buffer, void* audbuf,
	size_t abufs, unsigned int channels, unsigned int samplerate, void* tag);

void platform_audio_aid_refresh(arcan_aobj_id aid);

void platform_audio_purge(arcan_aobj_id* save, size_t save_count);

#endif
