#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#include "glheaders.h"

#include <arcan_math.h>
#include <arcan_general.h>
#include <arcan_video.h>
#include <arcan_videoint.h>

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

void platform_video_minimize()
{
    SDL_WM_IconifyWindow();
}

void platform_video_timing(float* o_sync, float* o_stddev, float* o_variance)
{
	static float sync, stddev, variance;
	static bool gottiming;

	if (!gottiming){
		platform_video_bufferswap();
	
		int retrycount = 0;

/* 
 * try to get a decent measurement of actual timing, this is not really used for
 * synchronization but rather as a guess of we're actually vsyncing and how 
 * processing should be scheduled in relation to vsync, or if we should yield at
 * appropriate times.
 */

		const int nsamples = 10;
		long long int samples[nsamples], sample_sum;

retry:
		sample_sum = 0;
		for (int i = 0; i < nsamples; i++){
			long long int start = arcan_timemillis();
			platform_video_bufferswap();
			long long int stop = arcan_timemillis();
			samples[i] = stop - start;
			sample_sum += samples[i];
		}

		sync = (float) sample_sum / (float) nsamples;
		variance = 0.0;
		for (int i = 0; i < nsamples; i++){
			variance += powf(sync - (float)samples[i], 2);
		}
		stddev = sqrtf(variance / (float) nsamples);
		if (stddev > 0.5){
			retrycount++;
			if (retrycount > 10)
				arcan_video_display.vsync_timing = 16.667; /* give up and just revert */
			else
				goto retry;
		}
	}

	*o_sync = sync;
	*o_stddev = stddev;
	*o_variance = variance;
}

bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames)
{
	char caption[64] = {0};
	SDL_Init(SDL_INIT_VIDEO);

	const SDL_VideoInfo* vi = SDL_GetVideoInfo();
	if (!vi){
		arcan_fatal("SDL_GetVideoInfo() failed, broken display subsystem.");
	}

	if (width == 0)
		width = vi->current_w;

	if (height == 0)
		height = vi->current_h;

	arcan_warning("Notice: [SDL] Video Info: %i, %i, hardware acceleration: %s, "
		"window manager: %s, VSYNC: %i, MSAA: %i\n",
			vi->current_w, vi->current_h, vi->hw_available ? "yes" : "no", 
			vi->wm_available ? "yes" : "no", arcan_video_display.vsync,
			arcan_video_display.msasamples);

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

	snprintf(caption, 63, "Arcan");
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


