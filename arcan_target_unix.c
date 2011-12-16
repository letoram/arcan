/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.

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

#ifndef PROBE
#define _TARGET_BASE "arcan_target.c"
#else
#define _TARGET_BASE "arcan_target_probe.c"
#endif

#include <dlfcn.h>
#include _TARGET_BASE

/* quick debugging hack */
static char* lastsym;
static void fatal_catcher(){
	fprintf(stderr, "ARCAN_Hijack, fatal error in (%s), aborting.\n", lastsym);
	abort();
}

static void* lookupsym(const char* symname, bool fatal){
	void* res = dlsym(RTLD_NEXT, symname);

	if (res == NULL && fatal){
		fprintf(stderr, "ARCAN_Hijack, warning: %s not found.\n", symname);
		res = fatal_catcher;
	}
	return res;
}

__attribute__((constructor))
static void hijack_init(void){
	forwardtbl.sdl_grabinput = lookupsym("SDL_WM_GrabInput", true);
	forwardtbl.sdl_openaudio = lookupsym("SDL_OpenAudio", true);
	forwardtbl.sdl_peepevents = lookupsym("SDL_PeepEvents", true);
	forwardtbl.sdl_pollevent = lookupsym("SDL_PollEvent", true);
	forwardtbl.sdl_pushevent = lookupsym("SDL_PushEvent", true);
	forwardtbl.sdl_setvideomode = lookupsym("SDL_SetVideoMode", true);
	forwardtbl.sdl_swapbuffers = lookupsym("SDL_GL_SwapBuffers", true);
	forwardtbl.sdl_flip = lookupsym("SDL_Flip", true);
	forwardtbl.sdl_iconify = lookupsym("SDL_WM_IconifyWindow", true);
	forwardtbl.sdl_updaterect = lookupsym("SDL_UpdateRect", true);
	forwardtbl.sdl_updaterects = lookupsym("SDL_UpdateRects", true);
	forwardtbl.sdl_upperblit = lookupsym("SDL_UpperBlit", true);
	forwardtbl.sdl_creatergbsurface = lookupsym("SDL_CreateRGBSurface", true);

/* SDL_mixer hijack, might not be present */
	forwardtbl.audioproxy = lookupsym("Mix_Volume", false);
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
	return ARCAN_SDL_GL_SwapBuffers();
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
