#define WANT_ARCAN_SHMIF_HELPER
#include "../arcan_shmif.h"
#include "../shmif_privext.h"

#include <fcntl.h>
#include <dlfcn.h>

#include <OpenGL/OpenGL.h>
#include <OpenGL/GL.h>

struct arcan_shmifext_setup arcan_shmifext_headless_defaults()
{
	return (struct arcan_shmifext_setup){};
}

enum shmifext_setup_status arcan_shmifext_headless_setup(
	struct arcan_shmif_cont* con,
	struct arcan_shmifext_setup arg)
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

	if (arg.major == 3){
		attributes[2] = (CGLPixelFormatAttribute) kCGLOGLPVersion_3_2_Core;
	}
	else if (arg.major > 3){
		return SHMIFEXT_NO_API;
	}

	static CGLContextObj context;

	errorCode = CGLChoosePixelFormat( attributes, &pix, &num );
  errorCode = CGLCreateContext( pix, NULL, &context );
	CGLDestroyPixelFormat( pix );
  errorCode = CGLSetCurrentContext( context );

/*
 * no double buffering,
 * we let the parent transfer process act as the limiting clock.
 */
	GLint si = 0;
	CGLSetParameter(context, kCGLCPSwapInterval, &si);

	return SHMIFEXT_OK;
}

void* arcan_shmifext_headless_lookup(
	struct arcan_shmif_cont* con, const char* sym)
{
	static void* dlh = NULL;
  if (NULL == dlh)
    dlh = dlopen("/System/Library/Frameworks/"
			"OpenGL.framework/Versions/Current/OpenGL", RTLD_LAZY);

  return dlh ? dlsym(dlh, sym) : NULL;
}

bool arcan_shmifext_headless_egl(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag)
{
	return false;
}

bool arcan_shmifext_headless_vk(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag)
{
	return false;
}

int arcan_shmifext_eglsignal(struct arcan_shmif_cont* con,
	uintptr_t display, int mask, uintptr_t tex_id, ...)
{
	return -1;
}

int arcan_shmifext_vksignal(struct arcan_shmif_cont* con,
	uintptr_t display, int mask, uintptr_t tex_id, ...)
{
	return -1;
}
