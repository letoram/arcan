/*
 * Long-term, the hope is that EGL will be the adopted interface
 * for basic context management / setup. The underlying platform
 * driver supports most necessary permutations;
 * (EGL  + GLEW + GL2+)
 * (GLEW + GL2+)
 * (EGL  + GLES2+)
 * (DRM  + EGL  + GLES2+)
 */
#ifndef ARCAN_GLHEADER
#define ARCAN_GLHEADER

#include "../video_platform.h"

#include <EGL/egl.h>

#ifdef WITH_OGL3
	#ifdef WITH_GLEW
		#define GLEW_STATIC
		#define GL_GLEXT_PROTOTYPES 1
		#include <GL/glew.h>
	#endif

	#include <GL/gl.h>
	#include <GL/glext.h>

#else

#ifdef WITH_GLES3
	#include <GLES3/gl3.h>
	#include <GLES3/gl3ext.h>

#define GL_NO_GETTEXIMAGE

#else
	#include <GLES2/gl2.h>
	#include <GLES2/gl2ext.h>
#define GL_NO_GETTEXIMAGE

/*
 * A lot of the engine was made with these available, but
 * the corresponding execution paths could be skipped.
 * Later on, all gl* related calls will be put into its
 * own platform container (so we can support low-power scale/blit- only
 * style renderers and accidentally also Mantle* and
 * similar feeble attempts at fragmenting the graphics space further).
 */
	#define ACCESS_FLAG_RW 0
	#define ACCESS_FLAG_W 0
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
	#define glMapBuffer_Wrap(t, a, l) NULL
	#define glUnmapBuffer(A)
#endif
#endif
#endif
