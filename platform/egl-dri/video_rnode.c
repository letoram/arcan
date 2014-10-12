#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <drm.h>
#include <gbm.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>

#include GL_HEADERS

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"

#ifndef HEADLESS_NOARCAN
#include "arcan_videoint.h"
#endif

#ifndef PLATFORM_SUFFIX
#define PLATFORM_SUFFIX platform
#endif

#define MERGE(X,Y) X ## Y
#define EVAL(X,Y) MERGE(X,Y)
#define PLATFORM_SYMBOL(fun) EVAL(PLATFORM_SUFFIX, fun)

static struct {
	int fd;

	EGLConfig config;
	EGLContext context;
	EGLDisplay display;
	EGLSurface surface;

	struct gbm_device* dev;

} rnode;

/*
 * we need an output FBO for this to work properly.
 */
#ifdef ARCAN_VIDEO_NOWORLD_FBO
int egl_rnode_worldfbo_required[-1];
#endif

bool PLATFORM_SYMBOL(_video_init)(uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* title)
{
	const char* device = getenv("ARCAN_VIDEO_NODE");
	if (!device){
		arcan_fatal("fixme: glob for common node paths, else fail on no nodes");
	}

	rnode.fd = open(device, O_RDWR);
	if (rnode.fd < 0){
		arcan_warning("egl-rnode(), couldn't open rendernode (%s), reason: (%s)",
			device, strerror(errno));
	}

	rnode.dev = gbm_create_device(rnode.fd);

/*
 * EGL setup is similar, but we don't have an output display
 */
	if (0 == w)
		w = 640;

	if (0 == h)
		h = 480;

	rnode.display = eglGetDisplay(rnode.dev);
	if (!eglInitialize(rnode.display, NULL, NULL)){
		arcan_warning("egl-rnode() -- failed to initialize EGL display\n");
		return false;
	}

	if (!eglBindAPI(EGL_OPENGL_ES_API)){
		arcan_warning("egl-rnode() -- couldn't bind GLES API\n");
		return false;
	}

	static const EGLint context_attribs[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_NONE
	};

	static const EGLint attribs[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 1,
		EGL_GREEN_SIZE, 1,
		EGL_BLUE_SIZE, 1,
		EGL_ALPHA_SIZE, 0,
		EGL_DEPTH_SIZE, 1,
		EGL_NONE
	};

	GLint nc;
	eglGetConfigs(rnode.display, NULL, 0, &nc);
	if (nc < 1){
		arcan_warning(
			"egl-dri() -- no configurations found (%s).\n", egl_errstr());
	}
	EGLConfig* configs = malloc(sizeof(EGLConfig) * nc);
	memset(configs, '\0', sizeof(EGLConfig) * nc);

	GLint selv;
	arcan_warning(
		"egl-dri() -- %d configurations found.\n", (int) nc);

	if (!eglChooseConfig(rnode.display, attribs, &rnode.config, 1, &selv)){
		arcan_warning(
			"egl-dri() -- couldn't chose a configuration (%s).\n", egl_errstr());
		return -1;
	}

	rnode.context = eglCreateContext(rnode.display,
		rnode.config, EGL_NO_CONTEXT, context_attribs);

	if (rnode.context == NULL) {
		arcan_warning("egl-dri() -- couldn't create a context.\n");
		return -1;
	}

/*
 * skip dealing with creating a buffer etc. as we will use the
 * world- fbo mechanism for that indirectly in the arcan-in-arcan
 * platform.
 */

	return true;
}

void PLATFORM_SYMBOL(_video_synch)(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

#ifndef HEADLESS_NOARCAN
	arcan_bench_register_cost( arcan_video_refresh(fract, true) );
#endif

	glFlush();

	if (post)
		post();
}

void PLATFORM_SYMBOL(_video_shutdown) ()
{
}

bool PLATFORM_SYMBOL(_video_set_mode)(
	platform_display_id disp, platform_mode_id mode)
{
	return disp == 0 && mode == 0;
}

struct monitor_modes* PLATFORM_SYMBOL(_video_query_modes)(
	platform_display_id id, size_t* count)
{
	static struct monitor_modes mode = {};

#ifndef HEADLESS_NOARCAN
	mode.width  = arcan_video_display.width;
	mode.height = arcan_video_display.height;
	mode.depth  = GL_PIXEL_BPP * 8;
	mode.refresh = 60; /* should be queried */
	*count = 1;
#else
	*count = 0;
#endif
	return &mode;
}

void PLATFORM_SYMBOL(_video_prepare_external)()
{
}

void PLATFORM_SYMBOL(_video_restore_external)()
{
}

bool PLATFORM_SYMBOL(_video_map_display)(
	arcan_vobj_id id, platform_display_id disp)
{
/* add ffunc to the correct display */

	return false; /* no multidisplay /redirectable output support */
}


