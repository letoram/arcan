/*
 * Long-term, the hope is that EGL will be the adopted interface
 * for basic context management / setup. The underlying platform
 * driver supports most necessary permutations;
 * (X11 + EGL  + GLEW + GL2+)
 * (X11 + GLEW + GL2+)
 * (X11 + EGL  + GLES2+)
 * (DRM + EGL  + GLES2+)
 */
#ifndef ARCAN_GLHEADER
#define ARCAN_GLHEADER

#define GLEW_STATIC
#define GL_GLEXT_PROTOTYPES 1
#include <glew.h>
#include <glxew.h>

#define ACCESS_FLAG_RW (GL_READ_WRITE )
#define ACCESS_FLAG_W (GL_WRITE_ONLY )

#define glMapBuffer_Wrap(target, access, len) (\
	glMapBuffer(target, access)\
	)

#include "../video_platform.h"

#endif
