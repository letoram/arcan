/*
 * The glheaders_xxx headerfiles are
 * compile-time options for which support / wrapping library to use.
 * Given the wide variety in supported platforms, along with the stated
 * goal of keeping necessary dependencies and dynamic configurations
 * to a minimum, we opted for this approach when it comes to
 * GL, extensions, video context etc.
 */
#ifndef ARCAN_GLHEADER
#define ARCAN_GLHEADER

#define GLEW_STATIC
#define NO_SDL_GLEXT
#define GL_GLEXT_PROTOTYPES 1

#include <glew.h>

#ifdef WITH_HEADLESS
#include <glxew.h>
#endif

#include <SDL.h>
#include <SDL_opengl.h>
#include <SDL_byteorder.h>

/*
 * wrap to handle GLES3 vs GL2.1 differences
 */

#define ACCESS_FLAG_RW (GL_READ_WRITE )
#define ACCESS_FLAG_W (GL_WRITE_ONLY )

#define glMapBuffer_Wrap(target, access, len) (\
	glMapBuffer(target, access) \
)

#include "../video_platform.h"

#endif
