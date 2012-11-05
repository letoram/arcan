/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal, property of its developers, please refer
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

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_target_const.h"
#include "arcan_frameserver_shmpage.h"
#include "frameserver/ntsc/snes_ntsc.h"

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

static struct {
/* SDL */
	void (*sdl_swapbuffers)(void);
	SDL_Surface* (*sdl_setvideomode)(int, int, int, Uint32);
	int (*sdl_pollevent)(SDL_Event*);
	int (*sdl_pushevent)(SDL_Event*);
	int (*sdl_peepevents)(SDL_Event*, int, SDL_eventaction, Uint32);
	int (*sdl_openaudio)(SDL_AudioSpec*, SDL_AudioSpec*);
	SDL_GrabMode (*sdl_grabinput)(SDL_GrabMode);
	int (*sdl_iconify)(void);
	void (*sdl_updaterect)(SDL_Surface*, Sint32, Sint32, Uint32, Uint32);
	void (*sdl_updaterects)(SDL_Surface*, int, SDL_Rect*);
	int (*sdl_upperblit)(SDL_Surface *src, const SDL_Rect *srcrect, SDL_Surface *dst, SDL_Rect *dstrect);
	int (*sdl_flip)(SDL_Surface*);
	SDL_Surface* (*sdl_creatergbsurface)(Uint32, int, int, int, Uint32, Uint32, Uint32, Uint32);
	int (*audioproxy)(int, int);
	
	void (*glLineWidth)(float);
	void (*glPointSize)(float);
	void (*glFinish)(void);
	void (*glFlush)(void);

#ifdef ENABLE_X11_HIJACK
	XVisualInfo* (*glXChooseVisual)(Display* dpy, int screen, int* attribList);
	Window (*XCreateWindow)(Display* display, Window parent,int x, int y, unsigned int width, unsigned int height, unsigned int border_width,
		int depth, unsigned int class, Visual* visual, unsigned long valuemask, XSetWindowAttributes* attributes);
	
	Window (*XCreateSimpleWindow)(Display* display, Window parent, int x, int y, unsigned int width, unsigned int height, unsigned int border_width,
		unsigned long border, unsigned long background);

	void* (*glXGetProcAddress)(const GLubyte* name);

	Bool (*XQueryPointer)(Display* display, Window w, Window* root_return, Window* child_return, int* rxret, int* ryret, int* wxret, int* wyret, unsigned* maskret);
	Bool (*XGetEventData)(Display*, XGenericEventCookie*);
	int (*XCheckIfEvent)(Display*, XEvent*, Bool (*predicate)(), XPointer);
	Bool (*XFilterEvent)(XEvent*, Window);
	int (*XNextEvent)(Display*, XEvent*);
	int (*XPeekEvent)(Display*, XEvent*);
	
/* could take the CheckMaskEvent, CheckTypedEvent etc. as well as we're just filtering input */
	
	void (*glXSwapBuffers)(Display *dpy, GLXDrawable drawable);
#endif
} forwardtbl = {0};

static struct {
/* audio */
	float attenuation;
	uint16_t frequency;
	uint8_t channels;
	uint16_t format;
	
/* keep track of video surface size as it may differ pre/post NTSC */
	unsigned width, height;

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
	snes_ntsc_t ntscctx;
	snes_ntsc_setup_t ntsc_opts;
	
/* specialized hack for vector graphics, a better approach would be to implement
 * a geometry buffering scheme (requires different SHM sizes though) and have a list of 
 * geometry + statetable + maptable etc. and see how many 3D- based emulators that would run
 * in such conditions */
	bool update_vector;
	float point_size;
	float line_size;
	
	SDL_MouseMotionEvent mousestate;
	uint8_t mousebutton;
		
	char* shmkey;
		
	struct arcan_evctx inevq, outevq;
	struct frameserver_shmcont shared;
	uint8_t* vidp, (* audp);
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

void arcan_warning(const char* msg, ...)
{
	va_list args;
	va_start( args, msg );
		vfprintf(stderr, msg, args),
	va_end(args);
}

/* lots of funky little details when it comes to video,
 * there may be multiple calls to video init (resizing windows etc.)
 * which subsequently leads to a synch in buffer sizes on both this side and
 * on the controlling node, which may, depending on transfer mode, require a re-allocation
 * of shared memory pages etc. Some of the conversions are done simply 
 * to have the option of getting rid of SDL entirely in favor of a GL- only solution */

/*
 * audio on the other hand,
 * we have several mixer options for hijacking, OR the more raw layers of SDL.
 * a viable option is to have a "light" and a "heavy" hijack mode for audio,
 * where light simply translated control commands (changing gain) and mapping
 * to corresponding SDL gain changes. This can be done with the control channel.
 * we might also need target- specific hijacks, thus these little dylibs
 * should be tossed in a folder of their own and force name to match their
 * respective target.
 */

static void(*acbfun)(void*, uint8_t*, int) = NULL;
static void audiocb(void *userdata, uint8_t *stream, int len)
{
	if (acbfun) {
		acbfun(userdata, stream, len);
		int16_t* samples = (int16_t*)stream;

		len /= 2;
		for (; len; len--, samples++) {
			int vl = *samples * (int)(255.0 * global.attenuation) >> 8;
			*samples = clamp(vl, SHRT_MIN, SHRT_MAX);
		}
	}
}

/* select friends from arcan_general as we don't want to take the entire .o in */
#include <time.h>
static inline bool parent_alive()
{
	return getppid() != 1;
}

int arcan_sem_post(sem_handle sem)
{
	return sem_post(sem);
}

int arcan_sem_unlink(sem_handle sem, char* key)
{
	return sem_unlink(key);
}

/* left for legacy reasons, old timedwait used timedwait which 
 * was broken on a lot of platforms. Now shmget spawns a guardthread instead */
int arcan_sem_timedwait(sem_handle semaphore, int mstimeout)
{
	if (mstimeout == 0)
		return sem_trywait(semaphore);
	else
		return sem_wait(semaphore);
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

void ARCAN_target_init(){
	global.shmkey = getenv("ARCAN_SHMKEY");
	char* shmsize = getenv("ARCAN_SHMSIZE");
	
	trace("ARCAN_target_init(%s, s)\n", global.shmkey, shmsize);
	
	unsigned bufsize = strtoul(shmsize, NULL, 10);

	if (errno == ERANGE || errno == EINVAL){
		fprintf(stderr, "ARCAN Hijack: Bad value in ENV[ARCAN_SHMSIZE], terminating.\n");
		exit(1);
	}
}

void ARCAN_target_shminit()
{
	trace("shm_init(%s)\n", global.shmkey);
	if (global.shmkey == NULL || ( global.shared = frameserver_getshm(global.shmkey, true)).addr == NULL ){
		fprintf(stderr, "ARCAN Hijack: Couldn't access shm-API, terminating.\n");
		exit(1);
	}
	
	frameserver_shmpage_calcofs(global.shared.addr, &global.vidp, &global.audp);
	frameserver_shmpage_setevqs(global.shared.addr, global.shared.esem, &(global.inevq), &(global.outevq), false); 

	snes_ntsc_init(&global.ntscctx, &global.ntsc_opts);
}

void ARCAN_target_shmsize(int w, int h, int bpp)
{
	if (global.shared.addr == NULL)
		ARCAN_target_shminit();
	
	trace("ARCAN_target_shmsize(%d, %d, %d)\n", w, h, bpp);

/* filter "useless" resolutions */
	if (w > MAX_SHMWIDTH || h > MAX_SHMHEIGHT || w < 32 || h < 32){
		fprintf(stderr, "ARCAN Hijack: Couldn't resize (%d, %d) outside build-time tolerance\n", w, h);
		return;
	}else
		fprintf(stderr, "resized to : %d, %d\n", w, h);
	
	if (global.ntscconv){
		trace("rebuilding NTSC settings.\n");
		free(global.ntsc_imb);
		global.ntsc_imb = malloc(w * h * 2);
		w = SNES_NTSC_OUT_WIDTH(w);
		h *= 2;
	}

	global.width = w;
	global.height = h;
	frameserver_shmpage_resize( &(global.shared), w, h, bpp, 0, 0 );
	frameserver_shmpage_calcofs(global.shared.addr, &global.vidp, &global.audp);
	frameserver_shmpage_setevqs(global.shared.addr, global.shared.esem, &(global.inevq), &(global.outevq), false);

	memset(global.vidp, 0x000000ff, w * h * 4);
}

int ARCAN_SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained)
{
	acbfun = desired->callback;
	desired->callback = audiocb;
	int rc = forwardtbl.sdl_openaudio(desired, obtained);

	trace("SDL_OpenAudio( %d, %d, %d )\n", obtained->freq, obtained->channels, obtained->format);
	global.frequency = obtained->freq;
	global.channels = obtained->channels;
	global.format = obtained->format;
	global.attenuation = 1.0;
	
	global.ntsc_opts = snes_ntsc_rgb;
	
	return rc;
}

SDL_Surface* ARCAN_SDL_CreateRGBSurface(Uint32 flags, int width, int height, int depth, Uint32 Rmask, Uint32 Gmask, Uint32 Bmask, Uint32 Amask){
	trace("SDL_CreateRGBSurface(%d, %d, %d, %d)\n", flags, width, height, depth);
	return forwardtbl.sdl_creatergbsurface(flags, width, height, depth, Rmask, Gmask, Bmask, Amask);
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
	
	ARCAN_target_shminit();
	
	SDL_Surface* res = forwardtbl.sdl_setvideomode(w, h, ncps, flags);
	global.doublebuffered = (flags & SDL_DOUBLEBUF) > 0;
	global.glsource = global.shared.addr->storage.glsource = (flags & SDL_OPENGL) > 0;
	
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
	bool active;
	
	switch (event.datatype){
		case EVENT_IDATATYPE_DIGITAL:
			newev.button.which = event.input.digital.devid;
				
			if (event.devkind == EVENT_IDEVKIND_MOUSE){
				newev.button.state  = event.input.digital.active ? SDL_PRESSED : SDL_RELEASED;
				newev.button.type   = event.input.digital.active ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
				newev.button.button = event.input.digital.subid;
				newev.button.which -= ARCAN_MOUSEIDBASE;
				newev.button.x = global.mousestate.x;
				newev.button.y = global.mousestate.y;
					
				global.mousebutton = event.input.digital.active ?
					global.mousebutton | SDL_BUTTON( newev.button.button + 1 ) :
					global.mousebutton & ~(SDL_BUTTON( newev.button.button + 1 ));
			} else {
				newev.jbutton.state  = event.input.digital.active ? SDL_PRESSED : SDL_RELEASED;
				newev.jbutton.type   = event.input.digital.active ? SDL_JOYBUTTONDOWN : SDL_JOYBUTTONUP;
				newev.jbutton.button = event.input.digital.subid;
				newev.button.which  -= ARCAN_JOYIDBASE;
			}
			
			forwardtbl.sdl_pushevent(&newev);
		break;

		case EVENT_IDATATYPE_TRANSLATED:
			newev.key.keysym.scancode = event.input.translated.scancode;
			newev.key.keysym.sym      = event.input.translated.keysym;
			newev.key.keysym.mod      = event.input.translated.modifiers;
			newev.key.keysym.unicode  = event.input.translated.subid;
			newev.key.which           = event.input.translated.devid;
			newev.key.state           = event.input.translated.active ? SDL_PRESSED : SDL_RELEASED;
			newev.key.type            = event.input.translated.active ? SDL_KEYDOWN : SDL_KEYUP;

			forwardtbl.sdl_pushevent(&newev);
		break;
		
		case EVENT_IDATATYPE_ANALOG:
			if (event.devkind == EVENT_IDEVKIND_MOUSE){
					newev.motion = global.mousestate;
				
					newev.motion.which = event.input.analog.devid - ARCAN_MOUSEIDBASE;
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
				newev.jaxis.which = event.input.analog.devid - ARCAN_JOYIDBASE;
				newev.jaxis.axis = event.input.analog.subid;
				newev.jaxis.type = SDL_JOYAXISMOTION;
				forwardtbl.sdl_pushevent(&newev);
			}
		break;
	}
}

static void toggle_ntscfilter()
{
	if (global.ntscconv){
		trace("toggle NTSC off.\n");

/* these need to lock as we can't assume video rendering is coming 
 * from the same threading context */
		sem_wait(global.shared.vsem);
		
			free(global.ntsc_imb);
			global.ntsc_imb = NULL;
			global.ntscconv = false;
			global.desfmt = PixelFormat_RGBA888;
			frameserver_shmpage_resize( &(global.shared), global.width, global.height, 4, 0, 0 );
		
		sem_post(global.shared.vsem);
	}
	else {
		trace("toggle NTSC on.\n");
		sem_wait(global.shared.vsem);
		
		global.ntscconv = true;
		global.desfmt = PixelFormat_RGB565;
		frameserver_shmpage_resize( &(global.shared), 
		SNES_NTSC_OUT_WIDTH(global.width), global.height * 2, 4, 0, 0 );
		global.ntsc_imb = malloc(global.width * global.height * 2);
		
		sem_post(global.shared.vsem);
	}
	
	frameserver_shmpage_calcofs(global.shared.addr, &global.vidp, &global.audp);
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
		
		case TARGET_COMMAND_NTSCFILTER: 
			if (ev->ioevs[0].iv){
				if (!global.ntscconv) 
					toggle_ntscfilter();
			} 
			else if (global.ntscconv) 
				toggle_ntscfilter();
		break;
		
		case TARGET_COMMAND_NTSCFILTER_ARGS:
			snes_ntsc_update_setup(&global.ntscctx, &global.ntsc_opts, 
				ev->ioevs[0].iv, ev->ioevs[1].fv, ev->ioevs[2].fv, ev->ioevs[3].fv);
		break;	
	}
}

int ARCAN_SDL_PollEvent(SDL_Event* inev)
{
	SDL_Event gevent;
	arcan_event* ev;
	
	trace("SDL_PollEvent()\n");
	
	while ( (ev = arcan_event_poll(&global.inevq)) ) 
		switch (ev->category){
			case EVENT_IO:
				if (global.gotsdl)
					push_ioevent_sdl(ev->data.io);
#ifdef ENABLE_X11_HIJACK
				else
					push_ioevent_x11(ev->data.io);
#endif
			break;
			case EVENT_TARGET: process_targetevent(ev->kind, &ev->data.target); break;
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

static void push_ntsc()
{
	unsigned width = global.width;
	unsigned height = global.height;
	trace("push_ntsc()\n");
	
	size_t linew = SNES_NTSC_OUT_WIDTH(width) * 4;
/* only draw on every other line, so we can easily mix or blend interleaved */
	snes_ntsc_blit(&global.ntscctx, global.ntsc_imb, width, 0, width, height, global.vidp, linew * 2);

	for (int row = 1; row < height * 2; row += 2)
		memcpy(&global.vidp[row * linew], &global.vidp[(row-1) * linew], linew);
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
	char* destp = global.ntscconv ? (char*)global.ntsc_imb : (char*)global.vidp;
	
	if ( cmpfmt(src->format, &global.desfmt) ){
		trace("don't convert surface, just copy\n"); 
			SDL_LockSurface(src);
			memcpy(destp, 
				   src->pixels, 
				   src->w * src->h * global.desfmt.BytesPerPixel);
			SDL_UnlockSurface(src);
	} else {
		trace("convert surface\n");
		SDL_Surface* surf = SDL_ConvertSurface(src, &global.desfmt, SDL_SWSURFACE);
		SDL_LockSurface(surf);
		memcpy(destp,
			   surf->pixels, 
			   surf->w * surf->h * global.desfmt.BytesPerPixel);
		SDL_UnlockSurface(surf);
		SDL_FreeSurface(surf);
	}

	if (global.ntscconv)
		push_ntsc();
	
	global.shared.addr->storage.glsource = false;
	global.shared.addr->vready = true;
}

/* NON-GL SDL applications (unfortunately, moreso for 1.3 which is not handled at all currently) 
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
 * there's possibly a slightly more cool hack, for surfaces that match the shmpage
 * in pixformat, create a proxy SDL_Surface object, replace the low-level buffer object
 * with a pointer to our shmpage, align ->ready to flips (otherwise the app has the possiblity
 * of tearing anyhow so...) -- There's also the SDL_malloc and look for requests that match their
 * w * h * bpp dimensions, and return pointers to locally managed ones ... lots to play with
 * if anyone is interested.
 * 
 * Currently, we use (a) / (c) -- to implement the (b) fallback, PollEvent is likely the more
 * "natural" place */
int ARCAN_SDL_Flip(SDL_Surface* screen)
{
	copysurface(screen);
	return 0;
}

void ARCAN_SDL_UpdateRect(SDL_Surface* screen, Sint32 x, Sint32 y, Uint32 w, Uint32 h){
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
int ARCAN_SDL_UpperBlit(SDL_Surface* src, const SDL_Rect* srcrect, SDL_Surface *dst, SDL_Rect *dstrect){
	int rv = forwardtbl.sdl_upperblit(src, srcrect, dst, dstrect);

	if (!global.doublebuffered && 
		dst == global.mainsrfc)
			copysurface(dst);

	return rv;
}

/* 
 * The OpenGL case is easier, but perhaps a bit pricier .. 
 */
#define RGB565(r, g, b) ((uint16_t)(((uint8_t)(r) >> 3) << 11) | (((uint8_t)(g) >> 2) << 5) | ((uint8_t)(b) >> 3))

void ARCAN_SDL_GL_SwapBuffers()
{
	trace("CopySurface(GL:pre)\n");

	sem_wait(global.shared.vsem);
	if (!global.shared.addr->dms)
		return;

	glReadBuffer(GL_BACK_LEFT);
/* the assumption as to the performance impact of this is that if it is aligned to the
 * buffer swap, we're at a point in any 3d engine where there will be a natural pause
 * which masquerades much of the readback overhead, initial measurements did not see a worthwhile performance
 * increase when using PBOs. The 2D-in-GL edgecase could probably get an additional boost
 * by patching glTexImage2D- class functions triggering on ortographic projection and texture dimensions */

	glReadPixels(0, 0, global.width, global.height, GL_RGBA, GL_UNSIGNED_BYTE, global.vidp);
	trace("buffer read (%d, %d)\n", global.width, global.height);
	
/* seems like several driver combinations implement readback swizzling in a broken way, use RGBA and convert manually. */
	if (global.ntscconv){
		uint16_t* dbuf = global.ntsc_imb;
		uint8_t*   inb = (uint8_t*) global.vidp;
	
		for (int y = 0; y < global.height; y++)
			for (int x = 0; x < global.width; x++){
				*dbuf++ = RGB565(inb[2], inb[1], inb[0]);
				inb += 4;
			}

		push_ntsc();
	}

/* here's a nasty little GL thing, readPixels can only be with origo in lower-left rather than up, 
 * so we need to swap Y, on the other hand, with the amount of data involved here (minimize memory bw- use at all time),
 * we want to flip in the main- app using the texture coordinates, hence the glsource flag */
	if (!global.shared.addr->storage.glsource){
		global.shared.addr->storage.glsource = true;
		ARCAN_target_shmsize(global.width, global.height, 4);
	}
	global.shared.addr->vready = true;

	trace("CopySurface(GL:post)\n");
	
/* can't be done in the target event handler as it might be in a different thread and thus GL context */
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
	return forwardtbl.glFinish();
}

void ARCAN_glFlush()
{
	trace("glFlush()\n");
	return forwardtbl.glFlush();
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

	if (width != global.width || height != global.height)
		ARCAN_target_shmsize(width, height, 4);
	
	ARCAN_SDL_GL_SwapBuffers();

//	forwardtbl.glx_swap_buffers(dpy, drawable); 
}

Bool ARCAN_XQueryPointer(Display* display, Window w, Window* root_return, Window* child_return, int* rxret, int* ryret, int* wxret, int* wyret, unsigned* maskret)
{
	bool rv = forwardtbl.XQueryPointer(display, w, root_return, child_return, rxret, ryret, wxret, wyret, maskret);
	
	*rxret = global.lastmx;
	*ryret = global.lastmy;

	return rv;
}

int ARCAN_XCheckIfEvent(Display *display, XEvent *event_return, Bool (*predicate)(Display*, XEvent*, XPointer), XPointer arg)
{
	if ( forwardtbl.XCheckIfEvent(display, event_return, predicate, arg) ){
		trace("got event, %d (%d, %d, %d)\n", event_return->type, KeyPress, KeyRelease, MotionNotify);
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
