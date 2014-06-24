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

#ifndef _HAVE_ARCAN_AUDIO
#define _HAVE_ARCAN_AUDIO

/* TODO: a lot of old cruft in here, should be replaced with sample management and frameserver playback,
 * specific audio format support etc. will be thrown out the door */

enum aobj_kind {
	AOBJ_INVALID,
	AOBJ_STREAM,
	AOBJ_SAMPLE,
	AOBJ_FRAMESTREAM,
	AOBJ_CAPTUREFEED
};
struct arcan_aobj;

/* this one is shady at best, patchwork to get audio - movie deps. allover the place
 * coupled with openAL headers, it only works assuming that ALuint - unsigned match
 * somehow (or is convertible) if something bugs, suspect buffer arg. */
typedef arcan_errc(*arcan_afunc_cb)(struct arcan_aobj* aobj, arcan_aobj_id id, unsigned buffer, void* tag);

/* this callback is checked prior to buffering data in OpenAL, which, in their infinite wisdom,
 * does not supply any aggregated means of gathering output or being used as a resampler (or dummy input device
 * for that matter). As the ffmpeg/libav- cruft is not allowed anywhere near the main process,
 * we're left with this sorry hack -> grab buffers, put on a tag+len+data and have the frameserver split
 * the buffer into separate streams and perform samplerate conversion / mixing there. */
typedef void(*arcan_monafunc_cb)(arcan_aobj_id id, uint8_t* buf, size_t bytes, unsigned channels, unsigned frequency, void* tag);
typedef arcan_errc(*arcan_again_cb)(float gain, void* tag);

arcan_errc arcan_audio_setup(bool nosound);

/* refrain from using (particularly in ffunc callbacks)
 * and just return silence when asked.
 * OpenAL implementation might just freak out and in stead botch the buffering.. */
arcan_errc arcan_audio_suspend();
arcan_errc arcan_audio_resume();

/* Similar to the video version,
 * input is how many logical time-units that we should process. */
void arcan_audio_tick(uint8_t ntt);
void arcan_audio_refresh(); /* audiobuffers may need to be requeued / processed quicker than tickrate */

arcan_errc arcan_audio_shutdown();

/* A little hack to workaround certain AL implementation bugs,
 * will reallocate AL IDs / buffers associated with the aobj */
arcan_errc arcan_audio_rebuild(arcan_aobj_id id);

/* Hook the audio buffer refills to the selected audio object,
 * primarily used to grab or patch data fed to a specific audio object for recording etc.
 * returns the previous tag (or NULL) in oldtag if it overrides */
arcan_errc arcan_audio_hookfeed(arcan_aobj_id id, void* tag, arcan_monafunc_cb hookfun, void** oldtag);

/* object management --- */
arcan_aobj_id arcan_audio_load_sample(const char* fname, float gain, arcan_errc* err);

/* setup / change a callback feed for refilling buffers */
arcan_aobj_id arcan_audio_feed(arcan_afunc_cb feed, void* tag, arcan_errc* errc);
arcan_errc arcan_audio_alterfeed(arcan_aobj_id id, arcan_afunc_cb feed);
int arcan_audio_findstreambufslot(arcan_aobj_id id);
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

/* try and get a lock on a specific capture device (matching arcan_audio_capturelist),
 * actual sampled data is dropped silently unless there's a monitor attached */
arcan_aobj_id arcan_audio_capturefeed(const char* identifier);

/* Time component is similar to video management.
 * However, the fades are currently only linear (oops) */
arcan_errc arcan_audio_setgain(arcan_aobj_id id, float gain, uint16_t time);

#endif
