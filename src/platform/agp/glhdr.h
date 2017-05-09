/*
 * No copyright claimed, Public Domain
 */

#ifdef __APPLE__
/* we already have a reasonably sane GL environment here */
#include <OpenGL/gl.h>
#include <OpenGL/glext.h>
#else

#ifdef GLES2
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#define GL_DEPTH24_STENCIL8 GL_DEPTH24_STENCIL8_OES
#ifndef GL_DEPTH_STENCIL_ATTACHMENT
#define GL_DEPTH_STENCIL_ATTACHMENT GL_STENCIL_ATTACHMENT
#endif

#elif GLES3
#include <GLES3/gl3.h>
#include <GLES3/gl3ext.h>

#else

#include <GL/gl.h>
#include "glext.h"

#endif
#endif
