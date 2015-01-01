/*
 * Copyright 2003-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_AUDIO
#define _HAVE_ARCAN_AUDIO

/*
 * This part of the engine has received notably less attention,
 * We've so- far stuck with fixed format, fixed frequency etc.
 * Many of the more interesting OpenAL bits (effects) are missing.
 */

enum aobj_kind {
	AOBJ_INVALID,
	AOBJ_STREAM,
	AOBJ_SAMPLE,
	AOBJ_FRAMESTREAM,
	AOBJ_CAPTUREFEED
};
struct arcan_aobj;

/*
 * For streaming audio sources where we have defined a feed function,
 * a callback of this form will be added. Buffer == -1 means that the
 * audio feed is shutting down.
 *
 * Audio data is fed through arcan_audio_buffer, where the buffer value
 * in this callback should be forwarded.
 */
typedef arcan_errc(*arcan_afunc_cb)(struct arcan_aobj* aobj,
	arcan_aobj_id id, ssize_t buffer, void* tag);

/*
 * There is one global hook that can be used to get access to audio
 * data as it is beeing flushed to lower layers, and this is the form
 * of that callback.
 */
typedef void(*arcan_monafunc_cb)(arcan_aobj_id id, uint8_t* buf,
	size_t bytes, unsigned channels, unsigned frequency, void* tag);

/*
 * It is possible that the frameserver is a process parasite in another
 * process where we would like to interface audio control anyhow throuh
 * a gain proxy. This callback is used for those purposes.
 */
typedef arcan_errc(*arcan_again_cb)(float gain, void* tag);

/*
 * Setting nosound enforces a global silence, data will still be buffered
 * and monitoring etc. functions will work as usual.
 */
arcan_errc arcan_audio_setup(bool nosound);

/*
 * We have, unfortunately, seen a lot of driver- related issues with
 * these ones, so prefer buffering silence (or not buffering data at
 * all and have the engine put the mixing slot to better use).
 */
arcan_errc arcan_audio_suspend();
arcan_errc arcan_audio_resume();

/*
 * Some audio transformations (pitch, gain, ...) need a clock
 * to work, this tick is usually tied to the same slot in the video
 * subsystem.
 */
void arcan_audio_tick(uint8_t ntt);

/*
 * Similarly to video refresh, the audio counterpart may need to
 * refill / de- en- queue buffers at a higher rate than the tick
 * clock would allow.
 */
void arcan_audio_refresh();

arcan_errc arcan_audio_shutdown();

/*
 * Some drivers / implementations have put us in a situation where
 * the audio subsystem has died, but some commands are still responsive.
 * Calling this function is a sortof a "last chance" rebuild of underlying
 * IDs and buffers for a single audio object.
 */
arcan_errc arcan_audio_rebuild(arcan_aobj_id id);

/*
 * Add a hook to the feed functions of a specific audio ID, primarily
 * used for implementing audio recording of multiple sources.
 */
arcan_errc arcan_audio_hookfeed(arcan_aobj_id id,
	void* tag, arcan_monafunc_cb hookfun, void** oldtag);

/*
 * One-shot WAV- kind of samples. Internal caching etc, may apply.
 */
arcan_aobj_id arcan_audio_load_sample(
	const char* fname, float gain, arcan_errc* err);

/*
 * Alter the feed function associated with an audio object in a streaming
 * state.
 */
arcan_errc arcan_audio_alterfeed(arcan_aobj_id id, arcan_afunc_cb feed);

/*
 * Allocate a streaming audio source, tag is a regular context pointer
 * that will be passed to the corresponding callback / feed function.
 * These will likely be invoked as part of audio_refresh.
 */
arcan_aobj_id arcan_audio_feed(arcan_afunc_cb feed,
	void* tag, arcan_errc* errc);

/*
 * Get the underlying type associated with an audio object.
 */
enum aobj_kind arcan_audio_kind(arcan_aobj_id);

/* destroy an audio object and everything associated with it */
arcan_errc arcan_audio_stop(arcan_aobj_id);

/* initiate playback (i.e. push buffers to OpenAL) */
arcan_errc arcan_audio_play(arcan_aobj_id, bool gain_override, float gain);

/* Pause might not work satisfactory. If this starts acting weird,
 * consider using the rebuild hack above */
arcan_errc arcan_audio_pause(arcan_aobj_id);

/* Might only be applicable for some aobjs */
arcan_errc arcan_audio_rewind(arcan_aobj_id);

/* get a null- terminated list of available capture devices */
char** arcan_audio_capturelist();

/*
 * try and get a lock on a specific capture device
 * (matching arcan_audio_capturelist),
 * actual sampled data is dropped silently
 * unless there's a monitor attached
 */
arcan_aobj_id arcan_audio_capturefeed(const char* identifier);
arcan_errc arcan_audio_setgain(arcan_aobj_id id, float gain, uint16_t time);

/*
 * This function is used similarly to the collapse/adopt style
 * functions in the video subsystem. If the scripting / execution layer
 * fails for some reason, we want to keep the audio objects that
 * are associated with frameservers and leave any samples etc. to rot.
 */
void arcan_audio_purge(arcan_aobj_id* save, size_t save_count);

#endif
