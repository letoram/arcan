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

#include <SDL/SDL.h>
#include <dlfcn.h>
#include "arcan_target.h"

extern struct hijack_fwdtbl forwardtbl;

/* prototypes matching arcan_target.c */
SDL_GrabMode ARCAN_SDL_WM_GrabInput(SDL_GrabMode mode);
void ARCAN_target_init();
void ARCAN_target_shmsize(int w, int h, int bpp);
int ARCAN_SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained);
SDL_Surface* ARCAN_SDL_CreateRGBSurface(Uint32 flags, int width, int height,
	int depth, Uint32 Rmask, Uint32 Gmask, Uint32 Bmask, Uint32 Amask);
SDL_Surface* ARCAN_SDL_SetVideoMode(int w, int h, int ncps, Uint32 flags);
int ARCAN_SDL_PollEvent(SDL_Event* inev);
int ARCAN_SDL_Flip(SDL_Surface* screen);
void ARCAN_SDL_UpdateRect(SDL_Surface* screen,
	Sint32 x, Sint32 y, Uint32 w, Uint32 h);
void ARCAN_SDL_UpdateRects(SDL_Surface* screen,
	int numrects, SDL_Rect* rects);
int ARCAN_SDL_UpperBlit(SDL_Surface* src, const SDL_Rect* srcrect,
	SDL_Surface *dst, SDL_Rect *dstrect);
void ARCAN_SDL_GL_SwapBuffers();
void ARCAN_glFinish();
void ARCAN_glFlush();

#ifdef ENABLE_X11_HIJACK
int ARCAN_XNextEvent(Display* disp, XEvent* ev);
int ARCAN_XPeekEvent(Display* disp, XEvent* ev);
Bool ARCAN_XGetEventData(Display* display, XGenericEventCookie* event);
void ARCAN_glXSwapBuffers (Display *dpy, GLXDrawable drawable);
Bool ARCAN_XQueryPointer(Display* display, Window w,
	Window* root_return, Window* child_return, int* rxret,
	int* ryret, int* wxret, int* wyret, unsigned* maskret);
int ARCAN_XCheckIfEvent(Display *display, XEvent *event_return,
	Bool (*predicate)(Display*, XEvent*, XPointer), XPointer arg);
Bool ARCAN_XFilterEvent(XEvent* ev, Window m);
#endif

/* quick debugging hack */
static char* lastsym;

/* linked list of hijacked symbols,
 * sym - symbol name
 * ptr - function pointer to the redirected function
 * bounce - function pointer to the original function */
struct symentry {
	char* sym;
	void* ptr;
	void* bounce;
	struct symentry* next;
};

static struct {
	struct symentry* first;
	struct symentry* last;
} symtbl = {0};

static void fatal_catcher(){
	fprintf(stderr, "ARCAN_Hijack, fatal error in (%s), aborting.\n", lastsym);
	abort();
}

static void* lookupsym(const char* symname, void* bounce, bool fatal){
	void* res = dlsym(RTLD_NEXT, symname);

	if (res == NULL && fatal){
		fprintf(stderr, "ARCAN_Hijack, warning: %s not found.\n", symname);
		res = fatal_catcher;
	}

	struct symentry* dst = malloc(sizeof(struct symentry));

	if (!symtbl.first){
		symtbl.first = dst;
		symtbl.last  = dst;
	}
	else{
		symtbl.last->next = dst;
		symtbl.last       = dst;
	}

	dst->sym    = strdup(symname);
	dst->ptr    = res;
	dst->bounce = bounce;
	dst->next   = NULL;

	return res;
}

static struct symentry* find_symbol(const char* sym)
{
	struct symentry* res = symtbl.first;

	while (res != NULL) {
		if (strcmp(res->sym, sym) == 0)
			return res;

		res = res->next;
	}

	return res;
}

__attribute__((constructor))
static void hijack_init(void){
  forwardtbl.sdl_grabinput = lookupsym("SDL_WM_GrabInput",ARCAN_SDL_WM_GrabInput, true);
	forwardtbl.sdl_openaudio = lookupsym("SDL_OpenAudio",ARCAN_SDL_OpenAudio, true);
	forwardtbl.sdl_peepevents = lookupsym("SDL_PeepEvents",NULL, true);
	forwardtbl.sdl_pollevent = lookupsym("SDL_PollEvent",ARCAN_SDL_PollEvent, true);
	forwardtbl.sdl_pushevent = lookupsym("SDL_PushEvent",NULL, true);
	forwardtbl.sdl_swapbuffers = lookupsym("SDL_GL_SwapBuffers",ARCAN_SDL_GL_SwapBuffers, true);
	forwardtbl.sdl_flip = lookupsym("SDL_Flip",ARCAN_SDL_Flip, true);
	forwardtbl.sdl_iconify = lookupsym("SDL_WM_IconifyWindow", NULL, true);
	forwardtbl.sdl_updaterect = lookupsym("SDL_UpdateRect", ARCAN_SDL_UpdateRect, true);
	forwardtbl.sdl_updaterects = lookupsym("SDL_UpdateRects", ARCAN_SDL_UpdateRects, true);
	forwardtbl.sdl_upperblit = lookupsym("SDL_UpperBlit", ARCAN_SDL_UpperBlit, true);

	forwardtbl.sdl_setvideomode = lookupsym("SDL_SetVideoMode", ARCAN_SDL_SetVideoMode, true);
	forwardtbl.sdl_creatergbsurface = lookupsym("SDL_CreateRGBSurface", ARCAN_SDL_CreateRGBSurface, true);

	forwardtbl.glLineWidth = lookupsym("glLineWidth", NULL, true);
	forwardtbl.glPointSize = lookupsym("glPointSize", NULL, true);
	forwardtbl.glFlush     = lookupsym("glFlush", ARCAN_glFlush, true);
	forwardtbl.glFinish    = lookupsym("glFinish", ARCAN_glFinish, true);

#ifdef ENABLE_X11_HIJACK
	forwardtbl.glXSwapBuffers = lookupsym("glXSwapBuffers", ARCAN_glXSwapBuffers, true);
	forwardtbl.glXGetProcAddress = lookupsym("glXGetProcAddressARB", ARCAN_glxGetProcAddr, true);
	forwardtbl.XNextEvent = lookupsym("XNextEvent", ARCAN_XNextEvent, true);
	forwardtbl.XPeekEvent = lookupsym("XPeekEvent", ARCAN_XPeekEvent, true);
	forwardtbl.XQueryPointer = lookupsym("XQueryPointer", ARCAN_XQueryPointer, true);
	forwardtbl.XGetEventData = lookupsym("XGetEventData", ARCAN_XGetEventData, true);
	forwardtbl.XCheckIfEvent = lookupsym("XCheckIfEvent", ARCAN_XCheckIfEvent, true);
	forwardtbl.XFilterEvent  = lookupsym("XFilterEvent", ARCAN_XFilterEvent, true);
#endif

/* SDL_mixer hijack, might not be present */
	forwardtbl.audioproxy = lookupsym("Mix_Volume", NULL, false);
	ARCAN_target_init();
}

__attribute__((destructor))
static void hijack_close(void){
}

/* UNIX hijack requires both symbol collision and pointers to forward call */

SDL_GrabMode SDL_WM_GrabInput(SDL_GrabMode mode)
{
	lastsym = "SDL_WM_GrabInput";
	return ARCAN_SDL_WM_GrabInput(mode);
}

void SDL_WarpMouse(uint16_t x, uint16_t y){
	lastsym = "SDL_WarpMouse";
}

int SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained)
{
	lastsym = "SDL_OpenAudio";
	return ARCAN_SDL_OpenAudio(desired, obtained);
}

SDL_Surface* SDL_SetVideoMode(int w, int h, int ncps, Uint32 flags)
{
	lastsym = "SDL_SetVideoMode";
	return ARCAN_SDL_SetVideoMode(w, h, ncps, flags);
}

int SDL_PollEvent(SDL_Event* ev)
{
	lastsym = "SDL_PollEvent";
	return ARCAN_SDL_PollEvent(ev);
}

/* Used by double-buffered non-GL apps */
int SDL_Flip(SDL_Surface* screen)
{
	lastsym = "SDL_Flip";
	return ARCAN_SDL_Flip(screen);
}

SDL_Surface* SDL_CreateRGBSurface(Uint32 flags, int width, int height, int depth, Uint32 Rmask, Uint32 Gmask, Uint32 Bmask, Uint32 Amask){
	lastsym = "SDL_CreateRGBSurface";
	return ARCAN_SDL_CreateRGBSurface(flags, width, height, depth, Rmask, Gmask, Bmask, Amask);
}

void SDL_GL_SwapBuffers()
{
	lastsym = "SDL_GL_SwapBuffers";
	ARCAN_SDL_GL_SwapBuffers();
}

void SDL_UpdateRects(SDL_Surface* screen, int numrects, SDL_Rect* rects){
	lastsym = "SDL_UpdateRects";
	ARCAN_SDL_UpdateRects(screen, numrects, rects);
}

void SDL_UpdateRect(SDL_Surface* surf, Sint32 x, Sint32 y, Uint32 w, Uint32 h){
	lastsym = "SDL_UpdateRect";
	ARCAN_SDL_UpdateRect(surf, x, y, w, h);
}

/* disable fullscreen attempts on X11, VideoMode hijack removes it from flags */
int SDL_WM_ToggleFullscreen(SDL_Surface* screen){
		return 0;
}

DECLSPEC int SDLCALL SDL_UpperBlit(SDL_Surface *src, SDL_Rect *srcrect, SDL_Surface *dst, SDL_Rect *dstrect){
	return ARCAN_SDL_UpperBlit(src, srcrect, dst, dstrect);
}

void glFinish()
{
	ARCAN_glFinish();
}

void glFlush()
{
	ARCAN_glFlush();
}

#ifdef ENABLE_X11_HIJACK
void glXSwapBuffers(Display *dpy, GLXDrawable drawable)
{
	lastsym = "glXSwapBuffers";
	return ARCAN_glXSwapBuffers(dpy, drawable);
}

void* ARCAN_glxGetProcAddr(const GLubyte* symbol)
{
	struct symentry* syment = find_symbol((char*)symbol);

	if (syment)
		return (syment->bounce ? syment->bounce : syment->ptr);

/* s'ppose the calls are to flush lookup errors or something.. */
	dlerror(); dlerror();
	void* rv = dlsym(NULL, (const char*) symbol);

	dlerror();
	return rv;
}

int XNextEvent(Display* disp, XEvent* ev)
{
	lastsym = "XNextEvent";
	return forwardtbl.XNextEvent(disp, ev);
}

int XPeekEvent(Display* disp, XEvent* ev)
{
	lastsym = "XPeekEvent";
	return forwardtbl.XPeekEvent(disp, ev);
}

void* glxGetProcAddress(const GLubyte* msg)
{
	lastsym = "glxGetProcAddress";
	return ARCAN_glxGetProcAddr(msg);
}

void* glxGetProcAddressARB(const GLubyte* msg)
{
	lastsym = "glxGetProcAddressARB";
	return ARCAN_glxGetProcAddr(msg);
}

Bool XQueryPointer(Display* display, Window w, Window* root_return, Window* child_return, int* rxret, int* ryret, int* wxret, int* wyret, unsigned* maskret)
{
	lastsym = "XQueryPointer";
	return ARCAN_XQueryPointer(display, w, root_return, child_return, rxret, ryret, wxret, wyret, maskret);
}

Bool XGetEventData(Display* display, XGenericEventCookie* event)
{
	lastsym = "XGetEventData";
	return ARCAN_XGetEventData(display, event);
}

Bool XCheckIfEvent(Display *display, XEvent *event_return, Bool (*predicate)(), XPointer arg)
{
	lastsym = "XCheckIfEvent";
	return ARCAN_XCheckIfEvent(display, event_return, predicate, arg);
}

Bool XFilterEvent(XEvent* ev, Window m)
{
	return ARCAN_XFilterEvent(ev, m);
}

#endif

#ifdef ENABLE_WINE_HIJACK
void* wine_dlsym(void* handle, const char* symbol, char* error, size_t errorsize)
{
	const char* err();
	struct symentry* syment = find_symbol(symbol);

	if (syment){
		return (syment->bounce ? syment->bounce : syment->ptr);
	} else;

/* s'ppose the calls are to flush lookup errors or something.. */
	dlerror(); dlerror();
	void* rv = dlsym(handle, symbol);
	dlerror();
	return rv;
}
#endif
