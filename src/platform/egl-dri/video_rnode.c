/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <drm.h>
#include <drm_fourcc.h>
#include <xf86drm.h>
#include <gbm.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>

#define EGL_EGLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <EGL/eglext.h>

#include "../agp/glfun.h"

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

static char* rnode_envopts[] = {
	"ARCAN_VIDEO_NODE=/dev/dri/renderD128", "specify render-node",
	"ARCAN_VIDEO_FDPASS", "set to use in-GPU buffer transfers to parent",
	"EGL_LOG_LEVEL=debug|info|warning|fatal", "Mesa/EGL debug aid",
	"EGL_SOFTWARE", "Force software rendering if possible",
	"GALLIUM_HUD", "Gallium driver performance overlay",
	"GALLIUM_LOG_FILE", "Gallium driver status output",
	NULL
};

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

static struct {
	int fd;

	EGLConfig config;
	EGLContext context;
	EGLDisplay display;
	EGLSurface surface;
	EGLImageKHR output;

	size_t mdispw, mdisph;
	size_t canvasw, canvash;

	struct gbm_device* dev;

} rnode;

/*
 * we need an output FBO for this to work properly.
 */
#ifdef ARCAN_VIDEO_NOWORLD_FBO
int egl_rnode_worldfbo_required[-1];
#endif

void* PLATFORM_SYMBOL(_video_gfxsym)(const char* sym)
{
	return eglGetProcAddress(sym);
}

struct monitor_mode PLATFORM_SYMBOL(_video_dimensions)()
{
	struct monitor_mode res = {
		.width = rnode.canvasw,
		.height = rnode.canvash,
		.phy_width = rnode.mdispw,
		.phy_height = rnode.mdisph
	};
	return res;
}

int64_t PLATFORM_SYMBOL(_output_handle)(
	struct storage_info_t* store, enum status_handle* status)
{
	int32_t fd = -1;
	intptr_t descr = store->vinf.text.glid;

	rnode.output = eglCreateImageKHR(rnode.display,
		rnode.context, EGL_GL_TEXTURE_2D_KHR, (EGLClientBuffer)(descr), NULL);

	EGLint name, handle, stride;

	if (eglExportDRMImageMESA(rnode.display, rnode.output,
		&name, &handle, &stride)){
		drmPrimeHandleToFD(rnode.fd, handle, DRM_CLOEXEC, &fd);
		*status = READY_TRANSFER;
	}
	else
		*status = ERROR_UNSUPPORTED;

/* how is this allocation managed, should the handle be destroyed
 * or is it collected with the fd? */
	store->vinf.text.stride = stride;
	store->vinf.text.format = DRM_FORMAT_XRGB8888;

	return fd;
}

bool PLATFORM_SYMBOL(_video_map_handle)(
	struct storage_info_t* store, int64_t handle)
{
	return false;
}

enum dpms_state
	PLATFORM_SYMBOL(_video_dpms)(platform_display_id did, enum dpms_state state)
{
	return ADPMS_ON;
}

bool PLATFORM_SYMBOL(_video_init)(uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* title)
{
	const char* device = getenv("ARCAN_VIDEO_NODE");

/* can be set by shmif_open/connect if the display-server wants us
 * to explicitly use a certain node */
	if (!device){
		device = getenv("ARCAN_SHMIF_NODE");
		if (!device)
			device = "/dev/dri/renderD128";
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

	rnode.mdispw = rnode.canvasw = 640;
	rnode.mdisph = rnode.canvash = 480;

	rnode.display = eglGetDisplay(rnode.dev);
	if (!eglInitialize(rnode.display, NULL, NULL)){
		arcan_warning("egl-rnode() -- failed to initialize EGL display\n");
		return false;
	}

	if (!eglBindAPI(EGL_OPENGL_API)){
		arcan_warning("egl-rnode() -- couldn't bind GLES API\n");
		return false;
	}

	static const EGLint context_attribs[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_NONE
	};

	static const EGLint attribs[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
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

	eglMakeCurrent(rnode.display, NULL, NULL, rnode.context);

	return true;
}

bool PLATFORM_SYMBOL(_video_display_edid)(platform_display_id did,
	char** out, size_t* sz)
{
	*out = NULL;
	*sz = 0;
	return false;
}

void PLATFORM_SYMBOL(_video_synch)(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

#ifndef HEADLESS_NOARCAN
	size_t nupd;
	arcan_bench_register_cost( arcan_vint_refresh(fract, &nupd) );
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

struct monitor_mode* PLATFORM_SYMBOL(_video_query_modes)(
	platform_display_id id, size_t* count)
{
	static struct monitor_mode mode = {};

	mode.width  = rnode.canvasw;
	mode.height = rnode.canvash;
	mode.depth  = sizeof(av_pixel) * 8;
	mode.refresh = 60; /* should be queried */
	*count = 1;
	return &mode;
}

const char** PLATFORM_SYMBOL(_video_envopts)()
{
	return (const char**) rnode_envopts;
}

void PLATFORM_SYMBOL(_video_prepare_external)()
{
}

void PLATFORM_SYMBOL(_video_restore_external)()
{
}

bool PLATFORM_SYMBOL(_video_specify_mode)(platform_display_id id,
	struct monitor_mode mode)
{
	return false;
}

bool PLATFORM_SYMBOL(_video_map_display)(
	arcan_vobj_id id, platform_display_id disp, enum blitting_hint hint)
{
/* add ffunc to the correct display */

	return false; /* no multidisplay /redirectable output support */
}

