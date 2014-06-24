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
#include <sys/resource.h>
#include <sys/shm.h>
#include <errno.h>
#include <poll.h>

#define GL_GLEXT_PROTOTYPES 1
#define clamp(a,min,max) (((a)>(max))?(max):(((a)<(min))?(min):(a)))

#include <SDL/SDL.h>
#include <SDL/SDL_opengl.h>
#include <SDL/SDL.h>

#include "arcan_target_const.h"

struct {
		void (*sdl_swapbuffers)(void);
		SDL_Surface* (*sdl_setvideomode)(int, int, int, Uint32);
		int (*sdl_pollevent)(SDL_Event*);
		void (*sdl_pushevent)(SDL_Event*);
		int (*sdl_peepevents)(SDL_Event*, int, SDL_eventaction, Uint32);
		int (*sdl_openaudio)(SDL_AudioSpec*, SDL_AudioSpec*);
		SDL_GrabMode (*sdl_grabinput)(SDL_GrabMode);
		int (*sdl_flip)(SDL_Surface*);
		int (*sdl_iconify)(void);
		void (*sdl_updaterects)(SDL_Surface*, int, SDL_Rect*);
		void (*sdl_updaterect)(SDL_Surface*, Sint32, Sint32, Sint32, Sint32);
		int (*sdl_upperblit)(SDL_Surface *src, SDL_Rect *srcrect, SDL_Surface *dst, SDL_Rect *dstrect);
		SDL_Surface* (*sdl_creatergbsurface)(Uint32, int, int, int, Uint32, Uint32, Uint32, Uint32);
		int (*audioproxy)(int, int);
} forwardtbl = {0};

void ARCAN_target_init(){
}

SDL_GrabMode ARCAN_SDL_WM_GrabInput(SDL_GrabMode mode)
{
	fprintf(stderr, "ARCAN:SDL:WM_GrabInput\n");
	return forwardtbl.sdl_grabinput(mode);
}

int ARCAN_SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained)
{
	fprintf(stderr, "ARCAN:SDL:OpenAudio\n");
	return forwardtbl.sdl_openaudio(desired, obtained);
}

SDL_Surface* ARCAN_SDL_SetVideoMode(int w, int h, int ncps, Uint32 flags)
{
	fprintf(stderr, "ARCAN:SDL:SetVideoMode\n");
	return forwardtbl.sdl_setvideomode(w, h, ncps, flags);
}

int ARCAN_SDL_PollEvent(SDL_Event* ev)
{
	fprintf(stderr, "ARCAN:SDL:SetVideoMode\n");
	return forwardtbl.sdl_pollevent(ev);
}

/* Used by double-buffered non-GL apps */
int ARCAN_SDL_Flip(SDL_Surface* screen)
{
	fprintf(stderr, "ARCAN:SDL:Flip\n");
	return forwardtbl.sdl_flip(screen);
}

SDL_Surface* ARCAN_SDL_CreateRGBSurface(Uint32 flags, int width, int height, int depth, Uint32 Rmask, Uint32 Gmask, Uint32 Bmask, Uint32 Amask){
	fprintf(stderr, "ARCAN:SDL:CreateRGBSurface");
	return forwardtbl.sdl_creatergbsurface(flags, width, height, depth, Rmask, Gmask, Bmask, Amask);
}

void ARCAN_SDL_UpdateRect(SDL_Surface* surf, Sint32 x, Sint32 y, Uint32 w, Uint32 h)
{
	fprintf(stderr, "ARCAN:SDL:UpdateRect");
	forwardtbl.sdl_updaterect(surf, x, y, w, h);
}

void ARCAN_SDL_UpdateRects(SDL_Surface* screen, int numrects, SDL_Rect* rects){
	fprintf(stderr, "ARCAN:SDL:UpdateRects");
	forwardtbl.sdl_updaterects(screen, numrects, rects);
}

int ARCAN_SDL_UpperBlit(SDL_Surface *src, SDL_Rect *srcrect, SDL_Surface *dst, SDL_Rect *dstrect)
{
	fprintf(stderr, "ARCAN:SDL:BlitSurface");
	return forwardtbl.sdl_upperblit(src, srcrect, dst, dstrect);
}

void ARCAN_SDL_GL_SwapBuffers()
{
	fprintf(stderr, "ARCAN:SDL:GL:SwapBuffers\n");
	forwardtbl.sdl_swapbuffers();
}
