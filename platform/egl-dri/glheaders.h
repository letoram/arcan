#ifndef ARCAN_GLHEADER
#define ARCAN_GLHEADER

#include "../video_platform.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>

static const char* egl_errstr()
{
	EGLint errc = eglGetError();
	switch(errc){
	case EGL_SUCCESS:
		return "Success";
	case EGL_NOT_INITIALIZED:
		return "Not initialize for the specific display connection";
	case EGL_BAD_ACCESS:
		return "Cannot access the requested resource (wrong thread?)";
	case EGL_BAD_ALLOC:
		return "Couldn't allocate resources for the requested operation";
	case EGL_BAD_ATTRIBUTE:
		return "Unrecognized attribute or attribute value";
	case EGL_BAD_CONTEXT:
		return "Context argument does not name a valid context";
	case EGL_BAD_CONFIG:
		return "EGLConfig argument did not match a valid config";
	case EGL_BAD_CURRENT_SURFACE:
		return "Current surface refers to an invalid destination";
	case EGL_BAD_DISPLAY:
		return "The EGLDisplay argument does not match a valid display";
	case EGL_BAD_SURFACE:
		return "EGLSurface argument does not name a valid surface";
	case EGL_BAD_MATCH:
		return "Inconsistent arguments";
	case EGL_BAD_PARAMETER:
		return "Invalid parameter passed to function";
	case EGL_BAD_NATIVE_PIXMAP:
		return "NativePixmapType is invalid";
	case EGL_BAD_NATIVE_WINDOW:
		return "Native Window Type does not refer to a valid window";
	case EGL_CONTEXT_LOST:
		return "Power-management event has forced the context to drop";
	default:
		return "Uknown Error";
	}
}

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
#ifndef HAVE_GLES3
#define HAVE_GLES3
#endif

	#define GL_NO_GETTEXIMAGE

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
