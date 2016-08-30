/*
 * Copyright 2006-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
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
#include <arcan_shmif.h>

#define GL_GLEXT_PROTOTYPES 1
#include <SDL/SDL_opengl.h>

#include <SDL/SDL.h>
#include "sdl12.h"

#define clamp(a,min,max) (((a)>(max))?(max):(((a)<(min))?(min):(a)))

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
	SDL_mutex* abuf_synch;
	unsigned sourcew, sourceh;
	size_t source_abuf_sz;
	size_t source_rate;

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
		.line_size  = 1.0,
		.source_abuf_sz = 1024,
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

static void audiocb(void* userdata, uint8_t* buf, int len)
{
	trace("SDL audio callback\n");
	if (!acbfun || len == 0)
		return;

/* if the caller keep on filling even though the connection is terminated */
	if (!global.abuf_synch){
		return;
	}

/* let the "real" driver deal with timing */
	acbfun(userdata, buf, len);

	size_t inlen = len;
	SDL_mutexP(global.abuf_synch);
	while (inlen){
		size_t ntw = global.shared.abufsize - global.shared.abufused;
		if (ntw > inlen)
			ntw = inlen;

		memcpy(&global.shared.audb[global.shared.abufused], buf, ntw);
		inlen -= ntw;
		buf += ntw;
		global.shared.abufused += ntw;

/* usually we synch left-over transfers with VID */
		if (!inlen || global.shared.abufused == global.shared.abufsize){
			arcan_shmif_signal(&global.shared, SHMIF_SIGAUD);
		}
	}

	SDL_mutexV(global.abuf_synch);
}

SDL_GrabMode ARCAN_SDL_WM_GrabInput(SDL_GrabMode mode)
{
	static SDL_GrabMode requested_mode = SDL_GRAB_OFF;
	trace("WM_GrabInput( %d )\n", mode);

/* blatantly lie about being able to grab input */
	if (mode != SDL_GRAB_QUERY){
		requested_mode = mode;
		if (mode == SDL_GRAB_OFF)
			arcan_shmif_enqueue(&global.shared, &(struct arcan_event){
				.ext.kind = ARCAN_EVENT(CURSORHINT),
				.ext.message.data = "hidden-abs"
			});
		else
			arcan_shmif_enqueue(&global.shared, &(struct arcan_event){
				.ext.kind = ARCAN_EVENT(CURSORHINT),
				.ext.message.data = "hidden-rel"
			});
	}

	return requested_mode;
}

void ARCAN_target_shmsize(int w, int h, int bpp)
{
	trace("ARCAN_target_shmsize(%d, %d, %d)\n", w, h, bpp);

/* filter "useless" resolutions */
	if (w > ARCAN_SHMPAGE_MAXW || h > ARCAN_SHMPAGE_MAXH || w < 32 || h < 32)
		return;

	global.sourcew = w;
	global.sourceh = h;

	if (!	arcan_shmif_resize_ext( &(global.shared), w, h,
		(struct shmif_resize_ext){
			.abuf_sz = global.source_abuf_sz,
			.abuf_cnt = 65536 / global.source_abuf_sz,
			.vbuf_cnt = 2,
			.samplerate = global.source_rate
	}))
		exit(EXIT_FAILURE);

	trace("resize/fill\n");
	shmif_pixel px = SHMIF_RGBA(0x00, 0x00, 0x00, 0xff);
	shmif_pixel* vidp = global.shared.vidp;
	for (int i = 0; i < w * h; i++)
		*vidp++ = px;
}

int ARCAN_SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained)
{
	trace("SDL_OpenAudio( %d, %d, %d )\n",
		obtained->freq, obtained->channels, obtained->format);

/* sneaky thing 1. mess around with the desired/obtained combo
 * so SDL will be forced to do some conversions for us */
	acbfun = desired->callback;
	desired->callback = audiocb;
	desired->channels = ARCAN_SHMIF_ACHANNELS;
	desired->format = AUDIO_S16;
	int rc = forwardtbl.sdl_openaudio(desired, obtained);
	global.abuf_synch = SDL_CreateMutex();
	if (!obtained)
		return rc;

/* A before V or V before A problem, fake the desired size and let V drive */
	global.source_abuf_sz = obtained->size;
	global.source_rate = obtained->freq;

	if (global.shared.vidp)
		arcan_shmif_resize_ext( &(global.shared),
			global.shared.w, global.shared.h,
			(struct shmif_resize_ext){
				.abuf_sz = global.source_abuf_sz,
				.abuf_cnt = 65536 / global.source_abuf_sz,
				.samplerate = obtained->freq,
				.vbuf_cnt = -1
			}
		);
	return rc;
}

SDL_Surface* ARCAN_SDL_CreateRGBSurface(Uint32 flags,
	int width, int height, int depth,
	Uint32 Rmask, Uint32 Gmask, Uint32 Bmask, Uint32 Amask){
	trace("SDL_CreateRGBSurface(%d, %d, %d, %d)\n", flags, width, height, depth);
	return forwardtbl.sdl_creatergbsurface(flags, width,
		height, depth, Rmask, Gmask, Bmask, Amask);
}

void ARCAN_SDL_WM_SetCaption(const char* title, const char* icon)
{
	struct arcan_event ev = {0};
	size_t lim=sizeof(ev.ext.message.data)/sizeof(ev.ext.message.data[0]);
	ev.ext.kind = ARCAN_EVENT(IDENT);
	snprintf((char*)ev.ext.message.data, lim, "%s", title ? title : "");
	arcan_shmif_enqueue(&global.shared, &ev);
}

/*
 * certain events might be filtered as well, since the subject needs to be
 * tricked to belive that it is active/in focus/...  even though it is not
 */
SDL_Surface* ARCAN_SDL_SetVideoMode(int w, int h, int ncps, Uint32 flags)
{
	trace("SDL_SetVideoMode(%d, %d, %d, %d)\n", w, h, ncps, flags);
	global.gotsdl = true;

	if (!global.shared.addr){
		struct arg_arr* args;
		global.shared = arcan_shmif_open(SEGID_GAME, SHMIF_ACQUIRE_FATALFAIL,&args);
	}

	SDL_Surface* res = forwardtbl.sdl_setvideomode(w, h, ncps, flags);
	global.doublebuffered = ((flags & SDL_DOUBLEBUF) > 0);
	global.glsource = ((flags & SDL_OPENGL) > 0);
	global.shared.addr->hints = global.glsource & SHMIF_RHINT_ORIGO_LL;

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

static inline void push_ioevent_sdl(arcan_ioevent event){
	SDL_Event newev = {0};

	switch (event.datatype){
	case EVENT_IDATATYPE_TOUCH:
	break;
	case EVENT_IDATATYPE_DIGITAL:
		newev.button.which = event.devid;

		if (event.devkind == EVENT_IDEVKIND_MOUSE){
			newev.button.state = event.input.digital.active ?
				SDL_PRESSED : SDL_RELEASED;
			newev.button.type  = event.input.digital.active ?
				SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
			newev.button.button = event.subid;
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
			newev.jbutton.button = event.subid;
		}

		forwardtbl.sdl_pushevent(&newev);
	break;

	case EVENT_IDATATYPE_TRANSLATED:
		newev.key.keysym.scancode = event.input.translated.scancode;
		newev.key.keysym.sym = event.input.translated.keysym;
		newev.key.keysym.mod = event.input.translated.modifiers;
		newev.key.keysym.unicode = event.subid;
		newev.key.which = event.devid;
		newev.key.state = event.input.translated.active ?SDL_PRESSED:SDL_RELEASED;
		newev.key.type = event.input.translated.active ? SDL_KEYDOWN : SDL_KEYUP;

		trace("got key: %c\n", newev.key.keysym.sym);
		forwardtbl.sdl_pushevent(&newev);
	break;

	case EVENT_IDATATYPE_ANALOG:
	if (event.devkind == EVENT_IDEVKIND_MOUSE){
			newev.motion = global.mousestate;

			newev.motion.which = event.devid;
			newev.motion.state = global.mousebutton;
			newev.motion.type = SDL_MOUSEMOTION;

		if (event.subid == 0){
			newev.motion.x = event.input.analog.axisval[0];
			newev.motion.xrel = event.input.analog.axisval[1];
			newev.motion.yrel = 0;

		}
		else if (event.subid == 1){
			newev.motion.y = event.input.analog.axisval[0];
			newev.motion.yrel = event.input.analog.axisval[1];
			newev.motion.xrel = 0;
		}

		trace("mouse: %d (%d), %d (%d)\n", newev.motion.x, newev.motion.xrel,
			newev.motion.y, newev.motion.yrel);
		global.mousestate = newev.motion;
		forwardtbl.sdl_pushevent(&newev);
	}
	else {
		newev.jaxis.value = event.input.analog.axisval[0];
		newev.jaxis.which = event.devid;
		newev.jaxis.axis = event.subid;
		newev.jaxis.type = SDL_JOYAXISMOTION;
		forwardtbl.sdl_pushevent(&newev);
	}
	break;
	default:
	break;
	}
}

void process_targetevent(unsigned kind, arcan_tgtevent* ev)
{
	switch (kind)
	{
		case TARGET_COMMAND_GRAPHMODE:
			if (ev->ioevs[0].iv == 4){
				global.update_vector = true;
				global.line_size = ev->ioevs[0].fv;
			}
			else if (ev->ioevs[0].iv == 5){
				global.update_vector = true;
				global.point_size = ev->ioevs[0].fv;
			}
		break;
		case TARGET_COMMAND_EXIT:
/* FIXME: this should be done way more gracefully */
			exit(0);
		break;
	}
}

static void run_event(struct arcan_event* ev)
{
	switch (ev->category){
	case EVENT_IO:
		if (global.gotsdl)
			push_ioevent_sdl(ev->io);
	break;
	case EVENT_TARGET:
		process_targetevent(ev->tgt.kind, &ev->tgt);
	default:
	break;
	}
}

int ARCAN_SDL_WaitEvent(SDL_Event* out)
{
	static bool got_pulse;

	if (!got_pulse){
		arcan_shmif_enqueue(&global.shared, &(struct arcan_event){
			.ext.kind = ARCAN_EVENT(CLOCKREQ),
			.ext.clock.rate = 1,
			.ext.clock.id = 1
		});
		got_pulse = true;
	}

/* register an automatic timer so we have a chance to catch
 * some timer in SDL at least */
	struct arcan_event ev;
	while (arcan_shmif_wait(&global.shared, &ev) != 0){
		run_event(&ev);

		if (forwardtbl.sdl_pollevent(out))
			return 1;
	}

	return 0;
}

int ARCAN_SDL_PollEvent(SDL_Event* inev)
{
	SDL_Event gevent;
	arcan_event ev;

	while (arcan_shmif_poll(&global.shared, &ev) > 0){
		run_event(&ev);
	}

/* strip away a few events related to fullscreen, I/O grabs etc. */
	int evs;
	if ( (evs = forwardtbl.sdl_pollevent(&gevent) ) )
	{
		if (gevent.type == SDL_ACTIVEEVENT)
			return forwardtbl.sdl_pollevent(inev);

		*inev = gevent;
	}

	return evs;
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

	if (cmpfmt(src->format, &PixelFormat_RGBA888)){
		SDL_LockSurface(src);
		memcpy(global.shared.vidp,
			src->pixels, src->w * src->h * sizeof(int32_t));
		SDL_UnlockSurface(src);
	}
	else {
		SDL_Surface* surf = SDL_ConvertSurface(src,
			&PixelFormat_RGBA888, SDL_SWSURFACE);
		SDL_LockSurface(surf);
		memcpy(global.shared.vidp,
			surf->pixels, surf->w * surf->h * sizeof(int32_t));
		SDL_UnlockSurface(surf);
		SDL_FreeSurface(surf);
	}

	global.shared.addr->hints = SHMIF_RHINT_ORIGO_UL;
	arcan_shmif_signal(&global.shared, SHMIF_SIGVID);
}

/* NON-GL SDL applications
 * have a lot of different entry-points to actually blit,
 * (there's perhaps some low level SDL hack to do this)
 *
 * the options are a few;
 * a. blits using UpdateRect/UpdateRects/Blit(UpperBlit)
 * b. direct raw manipulation of the display surface
 * c. double buffered
 * along with overlaysurfaces etc. etc.
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

	if (!global.doublebuffered && screen == global.mainsrfc)
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

/*
 * This was written a long time ago, a better approach would be somthing similar
 * to what is done in the SDL2 backend - force drawing into a FBO and use the
 * shmif-ext functions to try buffer passing with readback as a fallback
 */
void ARCAN_SDL_GL_SwapBuffers()
{
	trace("CopySurface(GL:pre)\n");

/* here's a nasty little GL thing, readPixels can only be with origo in
 * lower-left rather than up, so we need to swap Y, on the other hand, with the
 * amount of data involved here (minimize memory bw- use at all time), we want
 * to flip in the main- app using the texture coordinates, hence the glsource
 * flag */
	if (!(global.shared.addr->hints & SHMIF_RHINT_ORIGO_LL)){
		trace("Toggle GL surface support");
		global.shared.addr->hints = SHMIF_RHINT_ORIGO_LL;
		ARCAN_target_shmsize(global.sourcew, global.sourceh, 4);
	}

	glReadBuffer(GL_BACK_LEFT);

/*
 * the assumption as to the performance impact of this is that if it is aligned
 * to the buffer swap, we're at a point in most engines targeted (so no AAA)
 * where there will be a natural pause which masquerades much of the readback
 * overhead, initial measurements did not see a worthwhile performance increase
 * when using PBOs. The 2D-in-GL edgecase could probably get an additional
 * boost by patching glTexImage2D- class functions triggering on ortographic
 * projection and texture dimensions
 */
	glReadPixels(0, 0, global.sourcew, global.sourceh,
		GL_RGBA, GL_UNSIGNED_BYTE, global.shared.vidp);
	trace("buffer read (%d, %d)\n", global.sourcew, global.sourceh);

	arcan_shmif_signal(&global.shared, SHMIF_SIGVID);
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

/*
 * with X running, we leave a dangling black window, but may need to be kept
 * active is the caller is using the back buffer for something..
 * forwardtbl.sdl_swapbuffers()
 */
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
