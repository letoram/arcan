/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#include "glheaders.h"

#ifndef SDL_MINI_SUFFIX
#define SDL_MINI_SUFFIX platform
#endif

#define MERGE(X,Y) X ## Y
#define EVAL(X,Y) MERGE(X,Y)
#define PLATFORM_SYMBOL(fun) EVAL(SDL_MINI_SUFFIX, fun)

/* this is just to re-use the interface for 
 * the libretro- frameserver 3D special case */

bool PLATFORM_SYMBOL(_video_init) (uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames)
{
	SDL_Init(SDL_INIT_VIDEO);

	SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 1);
	SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 16);

	SDL_Surface* screen = SDL_SetVideoMode(width, height, bpp, SDL_OPENGL);

	if (!screen)
		return false;

	int err;
	if ( (err = glewInit()) != GLEW_OK){
		return false;
	}
	
	return true;
}

void PLATFORM_SYMBOL(_video_minimize) ()
{
	SDL_WM_IconifyWindow();
}

void PLATFORM_SYMBOL(_video_prepare_external) ()
{
}

void PLATFORM_SYMBOL(_video_restore_external) ()
{
}

void PLATFORM_SYMBOL(_video_bufferswap) ()
{
}

void PLATFORM_SYMBOL(_video_shutdown) ()
{
}

