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

/* NOTE; for full OSX support a few key- features are missing;
 * there's a way to exec() a program "discretely in the background"
 * with fullscreen mode on the main- app, initial tests suggests there is some
 * kind of priority inversion going on */

#include "arcan_target.c"

/* a lot of this trickery is to do the hijack,
 * and maximise code-reuse among the supported platforms.
 *
 * OSX linker uses a special section of the DATA segment
 * and a two-layer namespace. Thus the symbols of the targetted lib are available under their
 * native name, this is not so with the GNU ld linker, where you need to lookup each symbol
 * dynamically. Thus we use an intermediate table, alongside preprocessor renaming. */

typedef struct interpose_s {
	void* new_func;
	void* orig_func;
} interpose_t;

static const interpose_t interposers[] \
__attribute__((section("__DATA, __interpose"))) = {
	{(void *) ARCAN_SDL_GL_SwapBuffers, (void*) SDL_GL_SwapBuffers },
	{(void *) ARCAN_SDL_SetVideoMode, (void*) SDL_SetVideoMode },
	{(void *) ARCAN_SDL_PollEvent, (void*) SDL_PollEvent },
	{(void *) ARCAN_SDL_CreateRGBSurface, (void*) SDL_CreateRGBSurface },
	{(void *) ARCAN_SDL_UpperBlit, (void*) SDL_UpperBlit },
	{(void *) ARCAN_SDL_UpdateRect, (void*) SDL_UpdateRect },
	{(void *) ARCAN_SDL_UpdateRects, (void*) SDL_UpdateRects },
	{(void *) ARCAN_SDL_OpenAudio, (void*) SDL_OpenAudio },
	{(void *) ARCAN_SDL_Flip, (void*) SDL_Flip },
	{(void *) ARCAN_SDL_WM_GrabInput, (void*) SDL_WM_GrabInput }
};

__attribute__((constructor))
void hijack_init(void){
	forwardtbl.sdl_grabinput = SDL_WM_GrabInput;
	forwardtbl.sdl_openaudio = SDL_OpenAudio;
	forwardtbl.sdl_peepevents = SDL_PeepEvents;
	forwardtbl.sdl_pollevent = SDL_PollEvent;
	forwardtbl.sdl_pushevent = SDL_PushEvent;
	forwardtbl.sdl_setvideomode = SDL_SetVideoMode;
	forwardtbl.sdl_swapbuffers = SDL_GL_SwapBuffers;
	forwardtbl.sdl_flip = SDL_Flip;
	forwardtbl.sdl_iconify = SDL_WM_IconifyWindow;
	forwardtbl.sdl_updaterect = SDL_UpdateRect;
	forwardtbl.sdl_updaterects = SDL_UpdateRects;
	forwardtbl.sdl_upperblit = SDL_UpperBlit;
	forwardtbl.sdl_creatergbsurface = SDL_CreateRGBSurface;
	ARCAN_target_init();
}
