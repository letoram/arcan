#ifndef ARCAN_GLHEADER
#define ARCAN_GLHEADER

#include "../video_platform.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>

#ifdef WITH_OGL3

	#ifdef WITH_GLEW
		#define GLEW_STATIC
		#define GL_GLEXT_PROTOTYPES 1
		#include <GL/glew.h>
	#endif

	#include <GL/gl.h>
	#include <GL/glext.h>

	#define ACCESS_FLAG_RW (GL_READ_WRITE )
	#define ACCESS_FLAG_W (GL_WRITE_ONLY )

	#define glMapBuffer_Wrap(target, access, len) (\
	glMapBuffer(target, access)\
	)

#else

	#define GL_MAX_TEXTURE_UNITS 8
	#define GL_CLAMP GL_CLAMP_TO_EDGE

	#define glDrawBuffer(x)
	#define glReadBuffer(x)

	#define ACCESS_FLAG_RW (GL_MAP_READ_BIT | GL_MAP_WRITE_BIT)
	#define ACCESS_FLAG_W (GL_MAP_WRITE_BIT)

	#define glMapBuffer_Wrap(target, access, len) (\
		glMapBufferRange(target, 0, len, access)\
	)

	#include <GLES3/gl3.h>
	#include <GLES3/gl3ext.h>

#endif
#endif
