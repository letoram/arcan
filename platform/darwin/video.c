/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */

/*
 * PLATFORM DRIVER NOTICE:
 * This platform driver is incomplete in the sense that it was only set
 * up in order to allow for headless LWA/hijack/retro3d.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include GL_HEADERS

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

#ifndef PLATFORM_SUFFIX
#define PLATFORM_SUFFIX platform
#endif

#define MERGE(X,Y) X ## Y
#define EVAL(X,Y) MERGE(X,Y)
#define PLATFORM_SYMBOL(fun) EVAL(PLATFORM_SUFFIX, fun)

#include <OpenGL/OpenGL.h>

static CGLContextObj context;

void PLATFORM_SYMBOL(_video_bufferswap)()
{
}

bool PLATFORM_SYMBOL(_video_init)(uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* cap)
{
	CGLPixelFormatObj pix;
	CGLError errorCode;
	GLint num;

	CGLPixelFormatAttribute attributes[4] = {
  	kCGLPFAAccelerated,
  	kCGLPFAOpenGLProfile,
  	(CGLPixelFormatAttribute) kCGLOGLPVersion_Legacy,
  	(CGLPixelFormatAttribute) 0
	};

	errorCode = CGLChoosePixelFormat( attributes, &pix, &num );
  errorCode = CGLCreateContext( pix, NULL, &context );
	CGLDestroyPixelFormat( pix );
  errorCode = CGLSetCurrentContext( context );

#ifndef HEADLESS_NOARCAN
	arcan_video_display.pbo_support = true;
	arcan_video_display.width = w;
	arcan_video_display.height = h;
	arcan_video_display.bpp = bpp;
#endif

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
	}
	else
		arcan_video_display.pbo_support = true;

	glViewport(0, 0, w, h);

	return true;
}

void PLATFORM_SYMBOL(_video_prepare_external) () {}
void PLATFORM_SYMBOL(_video_restore_external) () {}

void PLATFORM_SYMBOL(_video_shutdown) ()
{
}

void PLATFORM_SYMBOL(_video_timing) (
	float* vsync, float* stddev, float* variance)
{
	*vsync = 16.667;
	*stddev = 0.01;
	*variance = 0.01;
}

void PLATFORM_SYMBOL(_video_minimize) () {}

