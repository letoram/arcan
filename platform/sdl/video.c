#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>

#include "glheaders.h"

#include "../../arcan_math.h"
#include "../../arcan_general.h"
#include "../../arcan_video.h"
#include "../../arcan_videoint.h"

static SDL_Surface* screen;

void platform_video_shutdown()
{
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	SDL_GL_SwapBuffers();
	SDL_FreeSurface(screen);
	SDL_QuitSubSystem(SDL_INIT_VIDEO);
}

void platform_video_prepare_external()
{
	SDL_FreeSurface(screen);
	if (arcan_video_display.fullscreen)
		SDL_QuitSubSystem(SDL_INIT_VIDEO);
}

void platform_video_restore_external()
{
	if (arcan_video_display.fullscreen)
		SDL_Init(SDL_INIT_VIDEO | SDL_INIT_NOPARACHUTE);

	screen = SDL_SetVideoMode(arcan_video_display.width,
		arcan_video_display.height,
		arcan_video_display.bpp,
		arcan_video_display.sdlarg);
}

void platform_video_bufferswap()
{
	SDL_GL_SwapBuffers();
}

bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames, bool conservative)
{
	char caption[64] = {0};

/* some GL attributes have to be set before creating the video-surface */
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
	SDL_GL_SetAttribute(SDL_GL_SWAP_CONTROL, 
		arcan_video_display.vsync == true ? 1 : 0);
	SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 1);
	SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 16);

	if (arcan_video_display.msasamples > 0){
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 1);
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 
		arcan_video_display.msasamples);
	}

	snprintf(caption, 63, "Arcan - %s", arcan_themename);
	SDL_WM_SetCaption(caption, "Arcan");

	arcan_video_display.fullscreen = fs;
	arcan_video_display.sdlarg = (fs ? SDL_FULLSCREEN : 0) | 
		SDL_OPENGL | (frames ? SDL_NOFRAME : 0);
	screen = SDL_SetVideoMode(width, height, bpp, arcan_video_display.sdlarg);

	if (arcan_video_display.msasamples && !screen){
		arcan_warning("arcan_video_init(), Couldn't open OpenGL display,"
			"attempting without MSAA\n");
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 0);
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 0);
		arcan_video_display.msasamples = 0;
		screen = SDL_SetVideoMode(width, height, bpp, arcan_video_display.sdlarg);
	}

	if (!screen)
		return false;

/* need to be called AFTER we have a valid GL context,
 * else we get the "No GL version" */
	int err;
	if ( (err = glewInit()) != GLEW_OK){
		arcan_fatal("arcan_video_init(), Couldn't initialize GLew: %s\n", 
			glewGetErrorString(err));
		return false;
	}

	if (!glewIsSupported("GL_VERSION_2_1  GL_ARB_framebuffer_object")){
		arcan_warning("arcan_video_init(), OpenGL context missing FBO support,"
			"outdated drivers and/or graphics adapter detected.");

		arcan_warning("arcan_video_init(), Continuing without FBOs enabled, "
			"this renderpath is to be considered unsupported.");
		arcan_video_display.fbo_support = false;
	}
	else
		arcan_video_display.pbo_support = arcan_video_display.fbo_support = true;

	arcan_video_display.width  = width;
	arcan_video_display.height = height;
	arcan_video_display.bpp    = bpp;

	return true;
}

void arcan_device_lock(int devind, bool state)
{
	SDL_WM_GrabInput( state ? SDL_GRAB_ON : SDL_GRAB_OFF );
}

