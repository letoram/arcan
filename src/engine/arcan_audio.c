/*
 * Copyright 2003-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: audio management code (just basic buffering, gain, ...)
 * This is seriously dated and need to be reworked into something notably
 * cleaner.
 */

#include "arcan_hmeta.h"

arcan_errc arcan_audio_alterfeed(arcan_aobj_id id, arcan_afunc_cb cb)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (platform_audio_alterfeed(id, cb)) {
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_audio_setup(bool nosound)
{
	arcan_errc rv = ARCAN_ERRC_NOAUDIO;

	if (nosound){
		arcan_warning("arcan_audio_init(nosound)\n");
	}

	if (platform_audio_init(nosound)){
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_audio_shutdown()
{
	arcan_errc rv = ARCAN_OK;

	platform_audio_shutdown();

	return rv;
}

arcan_errc arcan_audio_play(
	arcan_aobj_id id, bool gain_override, float gain, intptr_t tag)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (platform_audio_play(id, gain_override, gain, tag)) {
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_aobj_id arcan_audio_sample_buffer(float* buffer,
	size_t elems, int channels, int samplerate, const char* fmt_specifier)
{
	if (!buffer || !elems || channels <= 0 || channels > 2 || elems % channels != 0)
		return ARCAN_EID;

	return platform_audio_sample_buffer(buffer, elems, channels, samplerate, fmt_specifier);
}

arcan_aobj_id arcan_audio_load_sample(
	const char* fname, float gain, arcan_errc* err)
{
	if (fname == NULL) {
		*err = ARCAN_ERRC_BAD_ARGUMENT;
		return ARCAN_EID;
	}

	return platform_audio_load_sample(fname, gain, err);
}

arcan_errc arcan_audio_hookfeed(arcan_aobj_id id, void* tag,
	arcan_monafunc_cb hookfun, void** oldtag)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (platform_audio_hookfeed(id, tag, hookfun, oldtag)) {
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_aobj_id arcan_audio_feed(arcan_afunc_cb feed, void* tag, arcan_errc* errc)
{
	return platform_audio_feed(feed, tag, errc);
}

/* Another workaround to the many "fine" problems experienced with OpenAL .. */
arcan_errc arcan_audio_rebuild(arcan_aobj_id id)
{
        arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

        if (platform_audio_rebuild(id)){
                rv = ARCAN_OK;
        }

	return rv;
}

enum aobj_kind arcan_audio_kind(arcan_aobj_id id)
{
	return platform_audio_kind(id);
}

arcan_errc arcan_audio_suspend()
{
	arcan_errc rv = ARCAN_ERRC_BAD_ARGUMENT;

	platform_audio_suspend();

	rv = ARCAN_OK;

	return rv;
}

arcan_errc arcan_audio_resume()
{
	arcan_errc rv = ARCAN_ERRC_BAD_ARGUMENT;

	platform_audio_resume();

	rv = ARCAN_OK;

	return rv;
}

arcan_errc arcan_audio_pause(arcan_aobj_id id)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (platform_audio_pause(id)) {
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_audio_rewind(arcan_aobj_id id)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (platform_audio_rewind(id)) {
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_audio_stop(arcan_aobj_id id)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (platform_audio_stop(id)) {
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_audio_getgain(arcan_aobj_id id, float* gain)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (platform_audio_getgain(id, gain)) {
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_audio_setgain(arcan_aobj_id id, float gain, uint16_t time)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (platform_audio_setgain(id, gain, time)) {
		rv = ARCAN_OK;
	}

	return rv;
}

void arcan_audio_buffer(void* aobj, ssize_t buffer, void* audbuf,
	size_t abufs, unsigned int channels, unsigned int samplerate, void* tag)
{
	platform_audio_buffer(aobj, buffer, audbuf, abufs, channels, samplerate, tag);
}

void arcan_aid_refresh(arcan_aobj_id aid)
{
	platform_audio_aid_refresh(aid);
}

char** arcan_audio_capturelist()
{
	static char** capturelist;

/* free possibly previous result */
	if (capturelist){
		char** cur = capturelist;
		while (*cur){
			arcan_mem_free(*cur);
			*cur = NULL;
			cur++;
		}

		arcan_mem_free(capturelist);
	}

	platform_audio_capturelist(capturelist);

	return capturelist;
}

arcan_aobj_id arcan_audio_capturefeed(const char* dev)
{
	return platform_audio_capturefeed(dev);
}

size_t arcan_audio_refresh()
{
        return platform_audio_refresh();
}

void arcan_audio_tick(uint8_t ntt)
{
	platform_audio_tick(ntt);
}

void arcan_audio_purge(arcan_aobj_id* ids, size_t nids)
{
	platform_audio_purge(ids, nids);
}
