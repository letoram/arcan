#ifndef _STREAMS

#include <EGL/egl.h>
#include <EGL/eglext.h>

#if !defined(EGL_DRM_MASTER_FD_EXT)
#define EGL_DRM_MASTER_FD_EXT                   0x333C
#endif

PFNEGLQUERYDEVICESEXTPROC eglQueryDevicesEXT;
PFNEGLQUERYDEVICESTRINGEXTPROC eglQueryDeviceStringEXT;
PFNEGLGETPLATFORMDISPLAYEXTPROC eglGetPlatformDisplayEXT;
PFNEGLGETOUTPUTLAYERSEXTPROC eglGetOutputLayersEXT;
PFNEGLCREATESTREAMKHRPROC eglCreateStreamKHR;
PFNEGLSTREAMCONSUMEROUTPUTEXTPROC eglStreamConsumerOutputEXT;
PFNEGLCREATESTREAMPRODUCERSURFACEKHRPROC eglCreateStreamProducerSurfaceKHR;

/* and possibly: EXT_stream_acquire_mode,
 * EGL_NV_output_drm_flip_event */

#define MAP(R, T, SYM) if (!(R=(T) eglGetProcAddress(SYM))){\
	fprintf(stderr, "\tSTREAMS missing extension: %s\n", SYM);\
	rv = false;\
}

static bool map_stream_extensions()
{
	bool rv = true;
	MAP(eglQueryDevicesEXT,
		PFNEGLQUERYDEVICESEXTPROC, "eglQueryDevicesEXT");
	MAP(eglQueryDeviceStringEXT,
		PFNEGLQUERYDEVICESTRINGEXTPROC, "eglQueryDeviceStringEXT");
	MAP(eglGetPlatformDisplayEXT,
		PFNEGLGETPLATFORMDISPLAYEXTPROC, "eglGetPlatformDisplayEXT");
	MAP(eglGetOutputLayersEXT,
		PFNEGLGETOUTPUTLAYERSEXTPROC, "eglGetOutputLayersEXT");
 	MAP(eglCreateStreamKHR,
		PFNEGLCREATESTREAMKHRPROC, "eglCreateStreamKHR");
	MAP(eglStreamConsumerOutputEXT,
		PFNEGLSTREAMCONSUMEROUTPUTEXTPROC, "eglStreamConsumerOutputEXT");
	MAP(eglCreateStreamProducerSurfaceKHR,
		PFNEGLCREATESTREAMPRODUCERSURFACEKHRPROC, "eglCreateStreamProducerSurfaceKHR");
	return rv;
}
#undef MAP

#endif
