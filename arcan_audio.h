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

#ifndef _HAVE_ARCAN_AUDIO
#define _HAVE_ARCAN_AUDIO

struct arcan_aobj;

/* this one is shady at best, patchwork to get audio - movie deps. allover the place
 * coupled with openAL headers, it only works assuming that ALuint - unsigned match
 * somehow (or is convertible) if something bugs, suspect buffer arg. */
typedef arcan_errc(*arcan_afunc_cb)(struct arcan_aobj* aobj, arcan_aobj_id id, unsigned buffer, void* tag);
typedef arcan_errc(*arcan_again_cb)(float gain, void* tag);

enum aobj_atypes {
	AUTO = 0,
	PCM  = 1,
	WAV  = 2,
	AIFF = 3,
	OGG  = 4,
	MP3  = 5,
	FLAC = 6,
	AAC  = 7,
	MP4  = 8
};

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

arcan_errc arcan_audio_teardown();

/* A little hack to workaround certain AL implementation bugs,
 * will reallocate AL IDs / buffers associated with the aobj */
arcan_errc arcan_audio_rebuild(arcan_aobj_id id);

/* object management --- */
arcan_aobj_id arcan_audio_load_sample(const char* fname, float gain, arcan_errc* err);

/* setup / change a callback feed for refilling buffers */
arcan_aobj_id arcan_audio_feed(arcan_afunc_cb feed, void* tag, arcan_errc* errc);
arcan_errc arcan_audio_alterfeed(arcan_aobj_id id, arcan_afunc_cb feed);

/* setup a proxy object for some commands (gain, ...),
 * used particularly in internal target launch mode when
 * we don't want to interfere with a targets buffering too much
 * and just implement our transformations client- side */
arcan_aobj_id arcan_audio_proxy(arcan_again_cb feed, void* tag);
arcan_aobj_id arcan_audio_alterfeedio_stream(const char* uri, enum aobj_atypes type, arcan_errc* errc);

/* destroy an audio object and everything associated with it */
arcan_errc arcan_audio_stop(arcan_aobj_id);
arcan_aobj_id arcan_audio_stream(const char* uri, enum aobj_atypes type, arcan_errc* errc);

/* initiate playback (i.e. push buffers to OpenAL) */
arcan_errc arcan_audio_play(arcan_aobj_id);

/* Pause might not work satisfactory. If this starts acting weird,
 * consider using the rebuild hack above */
arcan_errc arcan_audio_pause(arcan_aobj_id);

/* Might only be applicable for some aobjs */
arcan_errc arcan_audio_rewind(arcan_aobj_id);

/* Time component is similar to video management.
 * However, the fades are currently only linear (oops) */
arcan_errc arcan_audio_setgain(arcan_aobj_id id, float gain, uint16_t time);
arcan_errc arcan_audio_setpitch(arcan_aobj_id id, float pitch, uint16_t time);

#endif
