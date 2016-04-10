/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <math.h>
#include <unistd.h>
#include <drm.h>
#include <drm_fourcc.h>
#include <xf86drm.h>
#include <gbm.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <signal.h>
#include <errno.h>
#include <glob.h>
#include <ctype.h>

#define EGL_EGLEXT_PROTOTYPES
#define MESA_EGL_NO_X11_HEADERS
#include <EGL/egl.h>
#include <EGL/eglext.h>

#include "../agp/glfun.h"

#include "arcan_shmif.h"
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

static PFNEGLCREATEIMAGEKHRPROC create_image;
static PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC query_image_format;
static PFNEGLEXPORTDMABUFIMAGEMESAPROC export_dmabuf;
static PFNEGLDESTROYIMAGEKHRPROC destroy_image;

static bool handle_disable = false;

static char* rnode_envopts[] = {
	"ARCAN_RENDER_NODE=/dev/dri/renderD128", "specify render-node",
	"ARCAN_VIDEO_NO_FDPASS", "set to use in-GPU buffer transfers to parent",
	"EGL_LOG_LEVEL=debug|info|warning|fatal", "Mesa/EGL debug aid",
	"EGL_SOFTWARE", "Force software rendering if possible",
	"GALLIUM_HUD", "Gallium driver performance overlay",
	"GALLIUM_LOG_FILE", "Gallium driver status output",
	NULL
};

static void map_extensions()
{
	create_image = (PFNEGLCREATEIMAGEKHRPROC)
		eglGetProcAddress("eglCreateImageKHR");
	if (!create_image){
		arcan_warning("no eglCreateImageKHR,buffer passing disabled\n");
		goto fail;
	}

	destroy_image = (PFNEGLDESTROYIMAGEKHRPROC)
		eglGetProcAddress("eglDestroyImageKHR");
	if (!destroy_image){
		arcan_warning("no eglDestroyImageKHR,buffer passing disabled\n");
		goto fail;
	}

	query_image_format = (PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC)
		eglGetProcAddress("eglExportDMABUFImageQueryMESA");
	if (!query_image_format){
		arcan_warning("no eglExportDMABUFImageQueryMESA,buffer passing disabled\n");
		goto fail;
	}

	export_dmabuf = (PFNEGLEXPORTDMABUFIMAGEMESAPROC)
		eglGetProcAddress("eglExportDMABUFImageMESA");
	if (!export_dmabuf){
		arcan_warning("no eglExportDMABUFImageMESA,buffer passing disabled\n");
		goto fail;
	}

	return;
fail:
	handle_disable = true;
	return;
}

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
	void* addr = eglGetProcAddress(sym);

	return addr;
}

struct monitor_mode PLATFORM_SYMBOL(_video_dimensions)()
{
	struct monitor_mode res = {
		.width = rnode.canvasw,
		.height = rnode.canvash
	};

	res.phy_width = (float) res.width / ARCAN_SHMPAGE_DEFAULT_PPCM * 10.0;
	res.phy_height = (float) res.height / ARCAN_SHMPAGE_DEFAULT_PPCM * 10.0;

	return res;
}

int64_t PLATFORM_SYMBOL(_video_output_handle)(
	struct storage_info_t* store, enum status_handle* status)
{
	int32_t fd = -1;
	intptr_t descr = store->vinf.text.glid;

	if (handle_disable){
		*status = ERROR_UNSUPPORTED;
		return -1;
	}

	rnode.output = create_image(rnode.display,
		rnode.context, EGL_GL_TEXTURE_2D_KHR, (EGLClientBuffer)(descr), NULL);

	if (!rnode.output){
		arcan_warning("eglCreateImageKHR failed, buffer passing disabled\n");
		goto unsup_fail;
	}

	int fourcc, nplanes;
	uint64_t modifiers;

	if (!query_image_format(rnode.display,rnode.output,&fourcc,&nplanes,NULL)){
		arcan_warning("ExportDMABUFImageQuery failed, buffer passing disabled\n");
		goto unsup_fail;
	}

	if (nplanes != 1){
		arcan_warning("_video_output_handle - only single plane "
			"supported (%d)", nplanes);
		goto unsup_fail;
	}

/* this is not safe if nplanes != 1 */
	EGLint stride;
	if (!export_dmabuf(rnode.display, rnode.output, &fd, &stride, NULL)){
		arcan_warning("exportDMABUFImage failed, buffer passing disabled\n");
		goto unsup_fail;
	}

/* some drivers have been spotted failing to create buffer but
 * still returning "valid" (0) file descriptor */
	if (fd <= 0){
		arcan_warning("exportDMABUFImage returned bad descriptor\n");
		goto unsup_fail;
	}

/* fd should be destroyed by caller, and since this can be called from
 * multiple threads, we're not safe tracking it here */
	store->vinf.text.format = fourcc;
	store->vinf.text.stride = stride;

/* there is no invalidation / signalling mechanism in place right now, just the
 * tacit assumption that the output buffer will be consumed and destroyed
 * between synch calls (though the shmif- mechanism of hinting rendernode
 * device might help us with that) */
	eglSwapBuffers(rnode.display, rnode.surface);
	return fd;

unsup_fail:
	*status = ERROR_UNSUPPORTED;
	if (rnode.output){
		destroy_image(rnode.display, rnode.output);
		rnode.output = NULL;
	}
	handle_disable = true;
	return -1;
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

static bool scan_node()
{
#ifndef VDEV_GLOB
#define VDEV_GLOB "/dev/dri/renderD*"
#endif
	bool rv = false;
	glob_t res;

	if (glob(VDEV_GLOB, 0, NULL, &res) == 0){
		char** beg = res.gl_pathv;

		while(*beg){
			int fd = open(*beg, O_RDWR);
			if (-1 != fd){
				rnode.dev = gbm_create_device(fd);
				if (rnode.dev){
					rnode.fd = fd;
					rv = true;
					break;
				}
				close(fd);
			}
			beg++;
		}

		globfree(&res);
	}

	return rv;
}

static void sigsegv_errmsg(int sign)
{
	static const char msg[] = "gbm- crash looking for render-nodes";
	size_t nw __attribute__((unused));
	nw = write(STDOUT_FILENO, msg, sizeof(msg));
	_exit(EXIT_FAILURE);
}

bool PLATFORM_SYMBOL(_video_init)(uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* title)
{
/*
 * we don't have a good way of communicating which rnode to use yet,
 * or if we should be able to switch, start by checking a device,
 * path or preset descriptor
 */
	const char* device = getenv("ARCAN_RENDER_NODE");

/*
 * hack around gbm crashes to get some kind of log output
 */
	struct sigaction old_sh;
	struct sigaction err_sh = {
		.sa_handler = sigsegv_errmsg
	};
	sigaction(SIGSEGV, &err_sh, &old_sh);

/*
 * try parent supplied or scan / brute force for a working device node
 */
	if (device){
		int fd = isdigit(device[0]) ?
			strtoul(device, NULL, 10) : open(device, O_RDWR);
		if (-1 != fd){
			rnode.dev = gbm_create_device(fd);
			if (!rnode.dev)
				close(fd);
			else
				rnode.fd = fd;
		}
		else{
			arcan_warning("couldn't map (env:ARCAN_RENDER_NODE) %s\n", device);
			sigaction(SIGSEGV, &old_sh, NULL);
			return false;
		}
	}

/* static set to NULL, will remain so on fail above */
	if (!rnode.dev && !scan_node()){
		arcan_warning("no available render node, giving up.\n");
		sigaction(SIGSEGV, &old_sh, NULL);
		return false;
	}
	sigaction(SIGSEGV, &old_sh, NULL);

/*
 * EGL setup is similar, but we don't have an output display
 */
	if (0 == w)
		w = 640;

	if (0 == h)
		h = 480;

	rnode.canvasw = 640;
	rnode.canvash = 480;

	rnode.display = eglGetDisplay((EGLNativeDisplayType) rnode.dev);
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
		EGL_RED_SIZE, OUT_DEPTH_R,
		EGL_GREEN_SIZE, OUT_DEPTH_G,
		EGL_BLUE_SIZE, OUT_DEPTH_B,
		EGL_ALPHA_SIZE, OUT_DEPTH_A,
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
	map_extensions();
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

size_t platform_nupd;

void PLATFORM_SYMBOL(_video_synch)(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

#ifndef HEADLESS_NOARCAN
	arcan_bench_register_cost(
		arcan_vint_refresh(fract, &platform_nupd));
#endif

/* actually needed for arcan platform or our handle-content may be bad */
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

