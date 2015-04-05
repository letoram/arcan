/*
 * Copyright 2006-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <math.h>
#include <stdbool.h>
#include <ulimit.h>
#include <limits.h>
#include <string.h>
#include <sys/mman.h>
#include <errno.h>
#include <poll.h>
#include <signal.h>

#include "../frameserver/resampler/speex_resampler.h"

#ifdef ENABLE_X11_HIJACK
#include <X11/X.h>
#include <X11/Xlib.h>
#include <X11/Xlibint.h>
#include <X11/Xutil.h>
#include <GL/glx.h>
#else
#define GL_GLEXT_PROTOTYPES 1
#include <SDL/SDL_opengl.h>
#endif

#define clamp(a,min,max) (((a)>(max))?(max):(((a)<(min))?(min):(a)))

#include <SDL/SDL.h>

#include "arcan_target.h"
#include <arcan_shmif.h>

#include "../frameserver/ntsc/snes_ntsc.h"

static SDL_PixelFormat PixelFormat_RGB565 = {
	.BitsPerPixel = 16,
	.BytesPerPixel = 2,
	.Bmask = 0xf800,.Gmask = 0x7e0,.Rmask = 0x1f,
	.Rloss = 3,.Gloss = 2,.Bloss = 3
};

static SDL_PixelFormat PixelFormat_RGBA888 = {
	.BitsPerPixel = 32,
	.BytesPerPixel = 4,
	.Rmask = 0x000000ff,
	.Gmask = 0x0000ff00,
	.Bmask = 0x00ff0000,
	.Amask = 0xff000000
};

struct hijack_fwdtbl forwardtbl = {0};

static struct {
/* audio */
	float attenuation;
	uint16_t samplerate;
	uint8_t channels;
	uint16_t format;

/* resampling / audio transfer (likely to come from a
 * different thread than the rendering one) */
	SpeexResamplerState* resampler;
	int16_t* encabuf;
	int encabuf_ofs;
	size_t encabuf_sz;
	SDL_mutex* abuf_synch;

	unsigned sourcew, sourceh;

/* merging event pairs to single mouse motion events */
	int lastmx;
	int lastmy;

/* video readback from GL */
	uint8_t* buf;

/* for non-GL accelerated applications, we need to know if the source
 * is doublebuffered or not as it yields a different execution path */
	bool doublebuffered, glsource, gotsdl, unlinked;

/* track the display surface so we know what to work with / convert between */
	SDL_Surface* mainsrfc;
	SDL_PixelFormat desfmt;

/* for GL surfaces only */
	unsigned pbo_ind;
	unsigned rb_pbos[2];

/* for NTSC conversion filter */
	uint16_t* ntsc_imb;
	bool ntscconv;
	snes_ntsc_t* ntscctx;
	snes_ntsc_setup_t ntsc_opts;

/* specialized hack for vector graphics, a better approach would be to implement
 * a geometry buffering scheme (requires different SHM sizes though)
 * and have a list of geometry + statetable + maptable etc. and see how
 * many 3D- based emulators that would run in such conditions */
	bool update_vector;
	float point_size;
	float line_size;

	SDL_MouseMotionEvent mousestate;
	uint8_t mousebutton;

	char* shmkey;

	struct arcan_shmif_cont shared;
} global = {
		.desfmt = {
			.BitsPerPixel = 32,
			.BytesPerPixel = 4,
	#if SDL_BYTEORDER == SDL_BIG_ENDIAN
			.Rmask = 0xff000000,
			.Gmask = 0x00ff0000,
			.Bmask = 0x0000ff00,
			.Amask = 0x000000ff
	#else
			.Rmask = 0x000000ff,
			.Gmask = 0x0000ff00,
			.Bmask = 0x00ff0000,
			.Amask = 0xff000000
	#endif
		},

		.update_vector = true,
		.point_size = 1.0,
		.line_size  = 1.0
};


static inline void trace(const char* msg, ...)
{
#ifdef TRACE_ENABLE
	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
	va_end( args);
#endif
}

#include <time.h>

static void(*acbfun)(void*, uint8_t*, int) = NULL;

/* Note; we always let the target application DRIVE the playback,
 * we may, however, copy the output data in order
 * for it to be available for analysis / recording, etc.
 *
 * (parent) -> (attenuation request) -> [target: we're here] alters
 * audio buffers in situ to reflect attenuation,
 * resamples output into shared memory buffer (unless full) -> (
 * parent) -> drops audio or pushes it to whatever is monitoring.
 */

/* convert, attenuate (0..1), buffer copy to parent,
 * can't be certain about correctly aligned input --
 * branch-predict + any decent -O step + intrisics
 * should reduce this to barely nothing though */
static inline int process_sample(uint8_t* stream, float attenuate)
{
	int counter = 1;

	for (int i = 0; i < global.channels; i++){
		int16_t tmp_a;
		uint16_t tmp_b;

		switch (global.format){
			case AUDIO_U8:
				*stream = (uint8_t)( (float) *stream * attenuate);
				global.encabuf[global.encabuf_ofs++] = ((*stream) << 8) - 0x7ff;

				if (global.channels == 1){
					global.encabuf[global.encabuf_ofs] =
						global.encabuf[global.encabuf_ofs - 1];
					global.encabuf_ofs++;
				}
			break;

			case AUDIO_S8:
				*stream = (int8_t)( (float) *((int8_t*)stream) * attenuate);
			break;

			case AUDIO_U16:
				memcpy(&tmp_b, stream, 2);

				tmp_a = tmp_b - 32768;
				global.encabuf[global.encabuf_ofs++] = tmp_a;
				if (global.channels == 1)
					global.encabuf[global.encabuf_ofs++] = tmp_a;

				tmp_b = (int16_t) ((float) tmp_b * global.attenuation);
				memcpy(stream, &tmp_b, 2);
				counter = 2;
			break;

			case AUDIO_S16:
				memcpy(&tmp_a, stream, 2);
				global.encabuf[global.encabuf_ofs++] = tmp_a;

				if (global.channels == 1)
					global.encabuf[global.encabuf_ofs++] = tmp_a;

				tmp_a = (int16_t) ((float) tmp_a * global.attenuation);
				memcpy(stream, &tmp_a, 2);
				counter = 2;
			break;

			default:
				fprintf(stderr, "hijack process sample; Big Endian"
					"	not supported by this hijack library");
				abort();
		}

/* buffer overrun, throw away */
		if (global.encabuf_ofs * 2 >= global.encabuf_sz){
			trace("process_sample failed, overflow (%d vs %d)\n",
				global.encabuf_ofs * 2, global.encabuf_sz);
			global.encabuf_ofs = 0;
		}

		stream += counter;
	}

	return counter * global.channels;
}

static void audiocb(void *userdata, uint8_t *stream, int len)
{
	trace("SDL audio callback\n");
	if (!acbfun)
		return;

/* let the "real" part of the process populate */
	acbfun(userdata, stream, len);

	if (!global.abuf_synch){
		return;
	}

/* apply attenuation, convert to s16 2ch and add to global buffer */
	int ofs = 0;

	SDL_mutexP(global.abuf_synch);
	if (global.encabuf_ofs + 4 < global.encabuf_sz){
		while (ofs < len)
			ofs += process_sample(stream + ofs, global.attenuation);
	}
	SDL_mutexV(global.abuf_synch);

	trace("samples converted, @ %d\n", ofs);
}

SDL_GrabMode ARCAN_SDL_WM_GrabInput(SDL_GrabMode mode)
{
	static SDL_GrabMode requested_mode = SDL_GRAB_OFF;
	trace("WM_GrabInput( %d )\n", mode);

/* blatantly lie about being able to grab input */
	if (mode != SDL_GRAB_QUERY)
		requested_mode = mode;

	return requested_mode;
}

void ARCAN_target_init()
{
	struct arg_arr* args;
	global.shared = arcan_shmif_open(SEGID_GAME, SHMIF_ACQUIRE_FATALFAIL, &args);

	if (getenv("ARCAN_FRAMESERVER_DEBUGSTALL")){
		fprintf(stderr, "frameserver_debugstall, waiting 10s"
			"	to continue. pid: %d\n", (int) getpid());
		sleep(10);
	}

	global.ntsc_opts = snes_ntsc_rgb;
}

void ARCAN_target_shmsize(int w, int h, int bpp)
{
	trace("ARCAN_target_shmsize(%d, %d, %d)\n", w, h, bpp);

/* filter "useless" resolutions */
	if (w > ARCAN_SHMPAGE_MAXW || h > ARCAN_SHMPAGE_MAXH || w < 32 || h < 32)
		return;

	global.sourcew = w;
	global.sourceh = h;

	if (global.ntscconv && SNES_NTSC_OUT_WIDTH(w) <
		ARCAN_SHMPAGE_MAXW && h * 2 < ARCAN_SHMPAGE_MAXH){
		w  = SNES_NTSC_OUT_WIDTH(w);
		h *= 2;
		if (global.ntsc_imb)
			free(global.ntsc_imb);

		global.ntsc_imb = malloc(global.sourcew * global.sourceh * sizeof(int16_t));
	} else {
		if (global.ntsc_imb){
			free(global.ntsc_imb);
			global.ntsc_imb = NULL;
		}
	}

	if (!	arcan_shmif_resize( &(global.shared), w, h) )
		exit(EXIT_FAILURE);

	uint32_t px = 0xff000000;
	uint32_t* vidp = (uint32_t*) global.shared.vidp;
	for (int i = 0; i < w * h * 4; i++)
		*vidp = px;
}

int ARCAN_SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained)
{
	trace("SDL_OpenAudio( %d, %d, %d )\n",
		obtained->freq, obtained->channels, obtained->format);

	acbfun = desired->callback;
	desired->callback = audiocb;

	int rc = forwardtbl.sdl_openaudio(desired, obtained);

	SDL_AudioSpec* res = obtained != NULL ? obtained : desired;

	global.samplerate= res->freq;
	global.channels  = res->channels;
	global.format    = res->format;
	global.attenuation = 1.0;

	if (global.encabuf)
		global.encabuf = (free(global.encabuf), NULL);
	else {
		global.abuf_synch = SDL_CreateMutex();
	}

	if (global.resampler)
		global.resampler = (speex_resampler_destroy(global.resampler), NULL);

	global.encabuf_sz = 120 * 1024;
	global.encabuf    = malloc(global.encabuf_sz);

	if (global.samplerate != ARCAN_SHMPAGE_SAMPLERATE){
		int errc;
		global.resampler  = speex_resampler_init(ARCAN_SHMPAGE_ACHANNELS,
			global.samplerate, ARCAN_SHMPAGE_SAMPLERATE,
			ARCAN_SHMPAGE_RESAMPLER_QUALITY, &errc);
	}

	return rc;
}

SDL_Surface* ARCAN_SDL_CreateRGBSurface(Uint32 flags,
	int width, int height, int depth,
	Uint32 Rmask, Uint32 Gmask, Uint32 Bmask, Uint32 Amask){
	trace("SDL_CreateRGBSurface(%d, %d, %d, %d)\n", flags, width, height, depth);
	return forwardtbl.sdl_creatergbsurface(flags, width,
		height, depth, Rmask, Gmask, Bmask, Amask);
}

/*
 * certain events might be filtered as well,
 * since the subject needs to be tricked to belive that it is active/in focus/...
 * even though it is not
 */

SDL_Surface* ARCAN_SDL_SetVideoMode(int w, int h, int ncps, Uint32 flags)
{
	trace("SDL_SetVideoMode(%d, %d, %d, %d)\n", w, h, ncps, flags);
	global.gotsdl = true;

	SDL_Surface* res = forwardtbl.sdl_setvideomode(w, h, ncps, flags);
	global.doublebuffered = ((flags & SDL_DOUBLEBUF) > 0);
	global.glsource = ((flags & SDL_OPENGL) > 0);
	global.shared.addr->glsource = global.glsource;

	if ( (flags & SDL_FULLSCREEN) > 0) {
/* oh no you don't */
		flags &= !SDL_FULLSCREEN;
	}

/* resize */
	if (res)
		ARCAN_target_shmsize(w, h, 4);

	global.mainsrfc = res;

	if (forwardtbl.sdl_iconify)
		forwardtbl.sdl_iconify();

	return res;
}

#ifdef ENABLE_X11_HIJACK
/* Will only get called if we build with X11 support
 * AND SDL hasn't been detected */
static inline void push_ioevent_x11(arcan_ioevent event)
{

}
#endif

static inline void push_ioevent_sdl(arcan_ioevent event){
	SDL_Event newev = {0};

	switch (event.datatype){
		case EVENT_IDATATYPE_TOUCH: break;
		case EVENT_IDATATYPE_DIGITAL:
			newev.button.which = event.input.digital.devid;

			if (event.devkind == EVENT_IDEVKIND_MOUSE){
				newev.button.state  = event.input.digital.active ?
					SDL_PRESSED : SDL_RELEASED;
				newev.button.type   = event.input.digital.active ?
					SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
				newev.button.button = event.input.digital.subid;
				newev.button.x = global.mousestate.x;
				newev.button.y = global.mousestate.y;

				global.mousebutton = event.input.digital.active ?
					global.mousebutton | SDL_BUTTON( newev.button.button + 1 ) :
					global.mousebutton & ~(SDL_BUTTON( newev.button.button + 1 ));
			} else {
				newev.jbutton.state  = event.input.digital.active ?
					SDL_PRESSED : SDL_RELEASED;
				newev.jbutton.type   = event.input.digital.active ?
					SDL_JOYBUTTONDOWN : SDL_JOYBUTTONUP;
				newev.jbutton.button = event.input.digital.subid;
			}

			forwardtbl.sdl_pushevent(&newev);
		break;

		case EVENT_IDATATYPE_TRANSLATED:
			newev.key.keysym.scancode = event.input.translated.scancode;
			newev.key.keysym.sym      = event.input.translated.keysym;
			newev.key.keysym.mod      = event.input.translated.modifiers;
			newev.key.keysym.unicode  = event.input.translated.subid;
			newev.key.which           = event.input.translated.devid;
			newev.key.state = event.input.translated.active ?SDL_PRESSED:SDL_RELEASED;
			newev.key.type = event.input.translated.active ? SDL_KEYDOWN : SDL_KEYUP;

			trace("got key: %c\n", newev.key.keysym.sym);
			forwardtbl.sdl_pushevent(&newev);
		break;

		case EVENT_IDATATYPE_ANALOG:
			if (event.devkind == EVENT_IDEVKIND_MOUSE){
					newev.motion = global.mousestate;

					newev.motion.which = event.input.analog.devid;
					newev.motion.state = global.mousebutton;
					newev.motion.type = SDL_MOUSEMOTION;

				if (event.input.analog.subid == 0){
					newev.motion.x = event.input.analog.axisval[0];
					newev.motion.xrel = event.input.analog.axisval[1];
					newev.motion.yrel = 0;

				} else if (event.input.analog.subid == 1){
					newev.motion.y = event.input.analog.axisval[0];
					newev.motion.yrel = event.input.analog.axisval[1];
					newev.motion.xrel = 0;
				}

				global.mousestate = newev.motion;
				forwardtbl.sdl_pushevent(&newev);
			} else {
				newev.jaxis.value = event.input.analog.axisval[0];
				newev.jaxis.which = event.input.analog.devid;
				newev.jaxis.axis = event.input.analog.subid;
				newev.jaxis.type = SDL_JOYAXISMOTION;
				forwardtbl.sdl_pushevent(&newev);
			}
		break;
	}
}

void setup_ntsc(int v1, int v2, int v3, int v4)
{
	static bool init;
	if (!init){
		init = true;
		global.ntscctx = malloc(sizeof(snes_ntsc_t));
		snes_ntsc_init(global.ntscctx, &global.ntsc_opts);
	}

	snes_ntsc_update_setup(
		global.ntscctx, &global.ntsc_opts, v1, v2, v3, v4);
}

void process_targetevent(unsigned kind, arcan_tgtevent* ev)
{
	switch (kind)
	{
		case TARGET_COMMAND_VECTOR_LINEWIDTH:
			global.update_vector = true;
			global.line_size = ev->ioevs[0].fv;
		break;

		case TARGET_COMMAND_VECTOR_POINTSIZE:
			global.update_vector = true;
			global.point_size = ev->ioevs[0].fv;
		break;

		case TARGET_COMMAND_EXIT:
			exit(0);
		break;

		case TARGET_COMMAND_ATTENUATE:
			global.attenuation = ev->ioevs[0].fv > 1.0 ? 1.0 :
				( ev->ioevs[0].fv < 0.0 ? 0.0 : ev->ioevs[0].fv);
		break;

		case TARGET_COMMAND_NTSCFILTER:
			if (ev->ioevs[0].iv == 0 && global.ntscconv == true){
				global.ntscconv = false;
				ARCAN_target_shmsize(global.sourcew, global.sourceh, 4);
			}
			else if (ev->ioevs[0].iv == 1 && global.ntscconv == false){
				global.ntscconv = true;
				ARCAN_target_shmsize(global.sourcew, global.sourceh, 4);
			}
		break;

		case TARGET_COMMAND_NTSCFILTER_ARGS:
			setup_ntsc(ev->ioevs[0].iv,
				ev->ioevs[1].fv, ev->ioevs[2].fv, ev->ioevs[3].fv);

		break;
	}
}

int ARCAN_SDL_PollEvent(SDL_Event* inev)
{
	SDL_Event gevent;
	arcan_event ev;

	trace("SDL_PollEvent()\n");

	while ( arcan_shmif_poll(&global.shared, &ev) ){
		switch (ev.category){
		case EVENT_IO:
			if (global.gotsdl)
				push_ioevent_sdl(ev.io);
#ifdef ENABLE_X11_HIJACK
			else
				push_ioevent_x11(ev.io);
#endif
		break;
		case EVENT_TARGET:
			process_targetevent(ev.tgt.kind, &ev.tgt);
		default:
		break;
		}
	}

/* strip away a few events related to fullscreen,
 * I/O grabs etc. */
	int evs;
	if ( (evs = forwardtbl.sdl_pollevent(&gevent) ) )
	{
		if (gevent.type == SDL_ACTIVEEVENT)
			return forwardtbl.sdl_pollevent(inev);

		*inev = gevent;
	}

	return evs;
}

static void push_audio()
{
	if (global.abuf_synch && global.encabuf_ofs > 0){
		SDL_mutexP(global.abuf_synch);

			if (global.samplerate == ARCAN_SHMPAGE_SAMPLERATE){
				memcpy(global.shared.audp, global.encabuf,
					global.encabuf_ofs * sizeof(int16_t));
			} else {
				spx_uint32_t outc  = ARCAN_SHMPAGE_AUDIOBUF_SZ;
/*first number of bytes, then after process..., number of samples */
				spx_uint32_t nsamp = global.encabuf_ofs >> 1;

				speex_resampler_process_interleaved_int(global.resampler,
					(const spx_int16_t*) global.encabuf, &nsamp,
					(spx_int16_t*) global.shared.audp, &outc);
				if (outc)
					global.shared.addr->abufused +=
						outc * ARCAN_SHMPAGE_ACHANNELS * sizeof(uint16_t);

				global.shared.addr->aready = true;
			}

			global.encabuf_ofs = 0;
		SDL_mutexV(global.abuf_synch);
	}
}

/* blit/convert the ntsc_intermediatebuffer to the shared memory page */
static void push_ntsc()
{
	trace("push_ntsc()\n");

	size_t line_sz = SNES_NTSC_OUT_WIDTH(global.sourcew) * 4;

/* only draw on every other line, so we can easily mix or blend interleaved */
	snes_ntsc_blit(global.ntscctx, global.ntsc_imb,
		global.sourcew, 0, global.sourcew, global.sourceh,
		global.shared.vidp, line_sz * 2);

/* just line-double for now */
	for (int row = 1; row < global.sourceh * 2; row += 2)
		memcpy(&global.shared.vidp[row * line_sz],
			&global.shared.vidp[(row-1) * line_sz], line_sz);
}

static bool cmpfmt(SDL_PixelFormat* a, SDL_PixelFormat* b){
	return (b->BitsPerPixel == a->BitsPerPixel &&
	a->Amask == b->Amask &&
	a->Rmask == b->Rmask &&
	a->Gmask == b->Gmask &&
	a->Bmask == b->Bmask);
}

static void copysurface(SDL_Surface* src){
	trace("CopySurface(noGL)\n");
	if (src->w != global.sourcew || src->h != global.sourceh)
		ARCAN_target_shmsize(src->w, src->h, 4);

	if (global.ntsc_imb && global.ntscconv){
		if (cmpfmt(src->format, &PixelFormat_RGB565)){
			SDL_LockSurface(src);
			memcpy(global.ntsc_imb, src->pixels, src->w * src->h * sizeof(int16_t));
			SDL_UnlockSurface(src);
		}
		else {
			SDL_Surface* surf = SDL_ConvertSurface(src,
				&PixelFormat_RGB565, SDL_SWSURFACE);
			SDL_LockSurface(surf);
			memcpy(global.ntsc_imb, surf->pixels,
				surf->w * surf->h * sizeof(int16_t));
			SDL_UnlockSurface(surf);
			SDL_FreeSurface(surf);
		}

		push_ntsc();
	}
	else {
		if (cmpfmt(src->format, &PixelFormat_RGBA888)){
			SDL_LockSurface(src);
			memcpy(global.shared.vidp,
				src->pixels, src->w * src->h * sizeof(int32_t));
			SDL_UnlockSurface(src);
		} else {
			SDL_Surface* surf = SDL_ConvertSurface(src,
				&PixelFormat_RGBA888, SDL_SWSURFACE);
			SDL_LockSurface(surf);
			memcpy(global.shared.vidp,
				surf->pixels, surf->w * surf->h * sizeof(int32_t));
			SDL_UnlockSurface(surf);
			SDL_FreeSurface(surf);
		}
	}

	global.shared.addr->glsource = false;
	push_audio();
	global.shared.addr->vready = true;
}

/* NON-GL SDL applications (unfortunately, moreso for 1.3
 * which is not handled at all currently)
 * have a lot of different entry-points to actually blit,
 * there's perhaps some low level SDL hack to do this,
 * the options are a few;
 * a. blits using UpdateRect/UpdateRects/Blit(UpperBlit)
 * b. direct raw manipulation of the display surface
 * c. double buffered
 * along with overlaysurfaces etc. etc.
 *
 * In addition these can be multicontext/multiwindow,
 * we don't concern ourselves with those currently.
 *
 * -- we can catch
 * (a) by looking for calls that uses the surface allocated through videomode,
 * (b) give up and just emit a page every 'n' ticks
 * (c) catch the flip
 *
 * there's possibly a slightly more cool hack, for surfaces that match
 * the shmpage in pixformat, create a proxy SDL_Surface object, replace
 * the low-level buffer object with a pointer to our shmpage, align ->ready
 * to flips (otherwise the app has the possiblity of tearing anyhow so...)
 * -- There's also the SDL_malloc and look for requests that match their
 * w * h * bpp dimensions, and return pointers to locally managed ones ...
 * lots to play with if anyone is interested.
 *
 * Currently, we use (a) / (c) -- to implement the (b) fallback,
 * PollEvent is likely the more "natural" place */
int ARCAN_SDL_Flip(SDL_Surface* screen)
{
	copysurface(screen);
	return 0;
}

void ARCAN_SDL_UpdateRect(SDL_Surface* screen,
	Sint32 x, Sint32 y, Uint32 w, Uint32 h){
	forwardtbl.sdl_updaterect(screen, x, y, w, h);

	if (!global.doublebuffered &&
		screen == global.mainsrfc)
			copysurface(screen);
}

void ARCAN_SDL_UpdateRects(SDL_Surface* screen, int numrects, SDL_Rect* rects){
	forwardtbl.sdl_updaterects(screen, numrects, rects);

	if (!global.doublebuffered &&
		screen == global.mainsrfc)
			copysurface(screen);
}

/* this is the actual SDL1.2 call most blit functions resolve to */
int ARCAN_SDL_UpperBlit(SDL_Surface* src, const SDL_Rect* srcrect,
	SDL_Surface *dst, SDL_Rect *dstrect){
	int rv = forwardtbl.sdl_upperblit(src, srcrect, dst, dstrect);

	if (!global.doublebuffered &&
		dst == global.mainsrfc)
			copysurface(dst);

	return rv;
}

/*
 * The OpenGL case is easier, but perhaps a bit pricier ..
 */
#define RGB565(r, g, b) ((uint16_t)(((uint8_t)(r) >> 3) << 11) \
	| (((uint8_t)(g) >> 2) << 5) | ((uint8_t)(b) >> 3))

void ARCAN_SDL_GL_SwapBuffers()
{
	trace("CopySurface(GL:pre)\n");
/* here's a nasty little GL thing, readPixels can only be with
 * origo in lower-left rather than up, so we need to swap Y,
 * on the other hand, with the amount of data involved here
 * (minimize memory bw- use at all time),
 * we want to flip in the main- app using the texture coordinates,
 * hence the glsource flag */
	if (!global.shared.addr->glsource){
		trace("Toggle GL surface support");
		global.shared.addr->glsource = true;
		ARCAN_target_shmsize(global.sourcew, global.sourceh, 4);
	}

	glReadBuffer(GL_BACK_LEFT);
/*
 * the assumption as to the performance impact of this is that
 * if it is aligned to the buffer swap, we're at a point in most engines
 * targeted (so no AAA) where there will be a natural pause
 * which masquerades much of the readback overhead, initial measurements
 * did not see a worthwhile performance
 * increase when using PBOs. The 2D-in-GL edgecase could probably get
 * an additional boost by patching glTexImage2D- class functions
 * triggering on ortographic projection and texture dimensions
 */

	glReadPixels(0, 0, global.sourcew, global.sourceh,
		GL_RGBA, GL_UNSIGNED_BYTE, global.shared.vidp);
	trace("buffer read (%d, %d)\n", global.sourcew, global.sourceh);

/*
 * seems like several driver combinations implement readback
 * swizzling in a broken way, use RGBA and convert manually.
 */
	if (global.ntscconv && global.ntsc_imb){
		uint16_t* dbuf = global.ntsc_imb;
		uint8_t*   inb = (uint8_t*) global.shared.vidp;

		for (int y = 0; y < global.sourcew; y++)
			for (int x = 0; x < global.sourceh; x++){
				*dbuf++ = RGB565(inb[2], inb[1], inb[0]);
				inb += 4;
			}

		push_ntsc();
	}

	push_audio();

	global.shared.addr->vready = true;
	sem_wait(global.shared.vsem);

	trace("CopySurface(GL:post)\n");

/*
 * can't be done in the target event handler as it might be
 * in a different thread and thus GL context
 */
	if (global.update_vector){
		forwardtbl.glPointSize(global.point_size);
		forwardtbl.glLineWidth(global.line_size);
		global.update_vector = false;
	}

/*	 forwardtbl.sdl_swapbuffers(); */
}

void ARCAN_glFinish()
{
	trace("glFinish()\n");
	forwardtbl.glFinish();
}

void ARCAN_glFlush()
{
	trace("glFlush()\n");
	forwardtbl.glFlush();
}

#ifdef ENABLE_X11_HIJACK

int ARCAN_XNextEvent(Display* disp, XEvent* ev)
{
	trace("XNextEvent\n");
	return forwardtbl.XNextEvent(disp, ev);
}

int ARCAN_XPeekEvent(Display* disp, XEvent* ev)
{
	trace("XPeekEvent\n");
	return forwardtbl.XPeekEvent(disp, ev);
}

Bool ARCAN_XGetEventData(Display* display, XGenericEventCookie* event)
{
	trace("GetEventData\n");
	return forwardtbl.XGetEventData(display, event);
}

void ARCAN_glXSwapBuffers (Display *dpy, GLXDrawable drawable)
{
	if (global.gotsdl)
		return;

	unsigned int width, height;
	glXQueryDrawable(dpy, drawable, GLX_WIDTH, &width);
	glXQueryDrawable(dpy, drawable, GLX_HEIGHT, &height);

	if (width != global.sourcew || height != global.sourceh){
		trace("glXSwapBuffers, resizing");
		ARCAN_target_shmsize(width, height, 4);
	}

	ARCAN_SDL_GL_SwapBuffers();

/* uncommenting this would allow the target application to render as usual
 *	forwardtbl.glx_swap_buffers(dpy, drawable);
 */
}

Bool ARCAN_XQueryPointer(Display* display, Window w,
	Window* root_return, Window* child_return, int* rxret,
	int* ryret, int* wxret, int* wyret, unsigned* maskret)
{
	bool rv = forwardtbl.XQueryPointer(display, w, root_return,
		child_return, rxret, ryret, wxret, wyret, maskret);

	*rxret = global.lastmx;
	*ryret = global.lastmy;

	return rv;
}

int ARCAN_XCheckIfEvent(Display *display, XEvent *event_return,
	Bool (*predicate)(Display*, XEvent*, XPointer), XPointer arg)
{
	if ( forwardtbl.XCheckIfEvent(display, event_return, predicate, arg) ){
		trace("got event, %d (%d, %d, %d)\n",
			event_return->type, KeyPress, KeyRelease, MotionNotify);
		return true;
	}
	return false;
}

Bool ARCAN_XFilterEvent(XEvent* ev, Window m)
{
	return forwardtbl.XFilterEvent(ev, m);
}
/* XWarpPointer */
/* XGrabPointer */

#endif
