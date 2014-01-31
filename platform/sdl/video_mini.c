#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#include "glheaders.h"

/* this is just to re-use the interface for 
 * the libretro- frameserver 3D special case */

bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
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

void platform_video_minimize()
{
	SDL_WM_IconifyWindow();
}
