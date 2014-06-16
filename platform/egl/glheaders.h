/*
 * These are only for the rather rare combination of 
 * EGL + regular OpenGL (rather than GLW,GLX,...)
 */

#ifndef ARCAN_GLHEADER
#define ARCAN_GLHEADER

#include <EGL/egl.h>

bool platform_video_init(uint16_t w, uint16_t h, 
	uint8_t bpp, bool fs, bool frames);

void platform_video_timing(float* vsync, float* stddev, float* variance);
void platform_video_minimize();
long long int arcan_timemillis();

#ifdef WITH_GLES3
	#include <GLES3/gl3.h>
	#include <GLES3/gl3ext.h>
#elif WITH_OGL3
	#include <GL/gl.h>
	#include <GL/glext.h>
#else
	#include <GLES2/gl2.h>
	#include <GLES2/gl2ext.h>

/*
 * A lot of the engine was made with these available, but
 * the corresponding execution paths could be skipped
 * zero them out here
 */
#define GL_DEPTH_STENCIL_ATTACHMENT 0
#define GL_STREAM_READ 0 
#define GL_DEPTH24_STENCIL8 0
#define GL_CLAMP GL_CLAMP_TO_EDGE
#define glDrawBuffer(X)
#define glReadBuffer(X)
#define GL_PIXEL_PACK_BUFFER 0
#define GL_PIXEL_UNPACK_BUFFER 0 
#define GL_MAX_TEXTURE_UNITS 8
#define glGetTexImage(A,B,C,D,E)
#define glMapBuffer(A,B) NULL
#define glUnmapBuffer(A)
#endif

#ifdef WITH_GLEW
#define GLEW_STATIC
#define GL_GLEXT_PROTOTYPES 1
#include <glew.h>
#endif

#endif
