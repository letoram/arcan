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

#include "../video_platform.h"

#endif
