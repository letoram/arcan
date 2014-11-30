/*
 * Copyright 2014, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/poll.h>

#include <fcntl.h>
#include <assert.h>

/*
 * We take these from khronos to avoid installations
 * where there, for some reason, exists older version
 * without the extensions we need.
 */
#include "egl.h"
#include "eglext.h"
PFNEGLQUERYDEVICESEXTPROC eglQueryDevicesEXT;
PFNEGLQUERYDEVICESTRINGEXTPROC eglQueryDeviceStringEXT;

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"

#ifndef HEADLESS_NOARCAN
#include "arcan_videoint.h"
#endif

#include "../agp/glfun.h"

#ifndef PLATFORM_SUFFIX
#define PLATFORM_SUFFIX platform
#endif

#define MERGE(X,Y) X ## Y
#define EVAL(X,Y) MERGE(X,Y)
#define PLATFORM_SYMBOL(fun) EVAL(PLATFORM_SUFFIX, fun)

static char* egl_synchopts[] = {
	"default", "double buffered, display controls refresh",
	NULL
};

static char* egl_envopts[] = {
	"ARCAN_VIDEO_LIST_DEVICES", "set to get a list of available devices",
	"ARCAN_VIDEO_PREFFERED_DEVICE=id", "force the use of a specific device",
	NULL
};

enum {
	DEFAULT,
	ENDM
}	synchopt;

static struct {
	EGLConfig config;
	EGLContext context;
	EGLDisplay display;
	EGLSurface surface;

	size_t canvasw, canvash;
	size_t mdispw, mdisph;
} egl = {
	.surface = EGL_NO_SURFACE
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

bool PLATFORM_SYMBOL(_video_set_mode)(
	platform_display_id disp, platform_mode_id mode)
{
	return disp == 0 && mode == 0;
}

struct monitor_mode PLATFORM_SYMBOL(_video_dimensions)()
{
	struct monitor_mode res = {
		.width = egl.canvasw,
		.height = egl.canvash,
		.phy_width = egl.mdispw,
		.phy_height = egl.mdisph
	};
	return res;
}

bool PLATFORM_SYMBOL(_video_map_display)(
	arcan_vobj_id id, platform_display_id disp, enum blitting_hint hint)
{
/* add ffunc to the correct display */

	return false; /* no multidisplay /redirectable output support */
}

bool PLATFORM_SYMBOL(_video_specify_mode)(platform_display_id id,
	platform_mode_id mode_id, struct monitor_mode mode)
{
	return false;
}

struct monitor_mode* PLATFORM_SYMBOL(_video_query_modes)(
	platform_display_id id, size_t* count)
{
	static struct monitor_mode mode = {};

#ifndef HEADLESS_NOARCAN
	mode.width  = egl.canvasw;
	mode.height = egl.canvash;
#endif

	mode.depth  = GL_PIXEL_BPP * 8;
	mode.refresh = 60; /* should be queried */

	*count = 1;
	return &mode;
}

platform_display_id* PLATFORM_SYMBOL(_video_query_displays)(size_t* count)
{
	static platform_display_id id = 0;
	*count = 1;
	return &id;
}

#define MAP(X, Y) if ((Y = platform_video_gfxsym(X)) == NULL)\
arcan_warning("couldn't find extension (%s)\n", X);

static bool map_extensions()
{
	MAP("eglQueryDevicesEXT", eglQueryDevicesEXT);
	MAP("eglQueryDeviceStringEXT", eglQueryDeviceStringEXT);
/*	MAP("eglGetPlatformDisplayEXT");
	MAP("eglCreatePlatformWindowSurfaceEXT");
	MAP("eglCreateStreamKHR");
	MAP("eglQueryOutputLayerAttribEXT");
	MAP("eglQueryOutputLayerStringEXT");
	MAP("eglQueryOutputPortAttribEXT");
	MAP("eglQueryOutputPortStringEXT"); */

/* we will need to map stream consumption with
 * the texture in the vstore that is connected to
 * the frameserver that acts as producer of the EGLStream */

/*	MAP("EGL_KHR_stream_consumer_gltexture"); */

/*
 * Issue, how should this locking work -- would a lock on
 * the stream prevent a client from rendering to it?
 * That'd force me to either have two streams running
 * (analogous to front/back buffer) OR waste more vram
 * by doing stream->RTT (that's the GLid of the frameserver
 * and do this in the ffunc for arcan_frameserver.c) and
 * then release?
 */
/*	MAP("EGL_KHR_stream_consumer_acquire");
	MAP("EGL_KHR_stream_consumer_release");
 */
/*
 * Plan (for platform/arcan), map composition output
 * to EGLStream, on init use this extension to get fd,
 * use event queue + socket to push FD to parent,
 * queue multiplexer would suck up the event + socket
 * and forward to agp_ where we set foreign handle
 * for the backing store (need this repeatedly for MESA),
 * where we have one agp_ implementation that uses
 * stream consumer and extension above to map that
 * to the texture id associated with the frameserver.
 */
	/* MAP("EGL_KHR_stream_cross_process_fd");*/
	return true;
}

static int setup_gl(void)
{
	static const EGLint context_attribs[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_NONE
	};

	const char* ident = agp_ident();

	EGLint apiv;

	static EGLint attribs[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, 0,
		EGL_RED_SIZE, 1,
		EGL_GREEN_SIZE, 1,
		EGL_BLUE_SIZE, 1,
		EGL_ALPHA_SIZE, 0,
		EGL_DEPTH_SIZE, 1,
		EGL_NONE
	};

	size_t i = 0;
	if (strcmp(ident, "OPENGL21") == 0){
		apiv = EGL_OPENGL_API;
		for (i = 0; attribs[i] != EGL_RENDERABLE_TYPE; i++);
		attribs[i+1] = EGL_OPENGL_BIT;
	}
	else if (strcmp(ident, "GLES3") == 0 ||
		strcmp(ident, "GLES2") == 0){
		apiv = EGL_OPENGL_API;
		for (i = 0; attribs[i] != EGL_RENDERABLE_TYPE; i++);
#ifndef EGL_OPENGL_ES2_BIT
			arcan_warning("EGL implementation do not support GLESv2, "
				"yet AGP platform requires it, use a different AGP platform.\n");
			return -1;
#endif

#ifndef EGL_OPENGL_ES3_BIT
#define EGL_OPENGL_ES3_BIT EGL_OPENGL_ES2_BIT
#endif
		attribs[i+1] = EGL_OPENGL_ES3_BIT;
		apiv = EGL_OPENGL_ES_API;
	}
	else
		return -1;

/*
 * These are only implemented in nvidia drivers atm. afaik.
 */
	if (!map_extensions()){
		arcan_warning("egl-nvidia() -- couldn't map extensions.\n");
		return -1;
	}

	EGLDeviceEXT devices[32];
	EGLint n_dev;

	if (EGL_FALSE == eglQueryDevicesEXT(32, devices, &n_dev)){
		arcan_warning("eglQueryDevicesEXT() failed, driver or permission issue\n");
		return -1;
	}

	if (getenv("ARCAN_VIDEO_LIST_DEVICES")){
		for (size_t i = 0; i < n_dev; i++){
			const char* str = eglQueryDeviceStringEXT(devices[i], EGL_EXTENSIONS);
			arcan_warning("device %s found.\n", str);
		}
	}

/*
 * Seems like we still need KMS support, i.e. the OuputLayers/OutputPorts
 * can't be used in place of the whole DRM-fd + CRTCs + Encoders + Connectors
 *
 * Curious why there's no eglSetOutputPorts eglSetOutputLayers etc.
 * Additionally, how are we (for the headless- platform) supposed to
 * manage resource allocation and limits, or is that a no-go?
 */

	return -1;

	egl.display = eglGetDisplay(NULL);
	if (!eglInitialize(egl.display, NULL, NULL)){
		arcan_warning("egl-dri() -- failed to initialize EGL.\n");
		return -1;
	}

	if (!eglBindAPI(apiv)){
		arcan_warning("egl-dri() -- couldn't bind GL API.\n");
		return -1;
	}

	EGLint nc;
	eglGetConfigs(egl.display, NULL, 0, &nc);
	if (nc < 1){
		arcan_warning(
			"egl-dri() -- no configurations found (%s).\n", egl_errstr());
	}

	EGLConfig* configs = malloc(sizeof(EGLConfig) * nc);
	memset(configs, '\0', sizeof(EGLConfig) * nc);

	EGLint selv;
	arcan_warning(
		"egl-dri() -- %d configurations found.\n", (int) nc);

	if (!eglChooseConfig(egl.display, attribs, &egl.config, 1, &selv)){
		arcan_warning(
			"egl-dri() -- couldn't chose a configuration (%s).\n", egl_errstr());
		return -1;
	}

	egl.context = eglCreateContext(egl.display, egl.config,
			EGL_NO_CONTEXT, context_attribs);
	if (egl.context == NULL) {
		arcan_warning("egl-dri() -- couldn't create a context.\n");
		return -1;
	}

/*
 * egl.surface = eglCreateWindowSurface(egl.display,
		egl.config, (uintptr_t)gbm.surface, NULL);
 */

	if (egl.surface == EGL_NO_SURFACE) {
		arcan_warning("egl-dri() -- couldn't create a window surface.\n");
		return -1;
	}

	eglMakeCurrent(egl.display, egl.surface, egl.surface, egl.context);

	return 0;
}

void* PLATFORM_SYMBOL(_video_gfxsym)(const char* sym)
{
	return eglGetProcAddress(sym);
}

bool PLATFORM_SYMBOL(_video_init) (uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* title)
{
	if (setup_gl() == 0){
		agp_init();
		return true;
	}

	return false;
}

void PLATFORM_SYMBOL(_video_synch)(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

#ifndef HEADLESS_NOARCAN
	size_t nd;
	arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );

	static bool ld;
	if (nd > 0 || !ld){
		arcan_vint_drawrt(arcan_vint_world(), 0, 0, egl.mdispw, egl.mdisph);
		ld = nd == 0;
	}
#endif

	agp_activate_rendertarget(NULL);
	eglSwapBuffers(egl.display, egl.surface);

	if (post)
		post();
}

void PLATFORM_SYMBOL(_video_shutdown) ()
{
}

void PLATFORM_SYMBOL(_video_setsynch)(const char* arg)
{
	int ind = 0;

	while(egl_synchopts[ind]){
		if (strcmp(egl_synchopts[ind], arg) == 0){
			synchopt = (ind > 0 ? ind / 2 : ind);
			arcan_warning("synchronisation strategy set to (%s)\n",
				egl_synchopts[ind]);
			break;
		}

		ind += 2;
	}
}

const char* PLATFORM_SYMBOL(_video_capstr)()
{
	static char* buf;
	static size_t buf_sz;

	if (buf){
		free(buf);
		buf = NULL;
	}

	FILE* stream = open_memstream(&buf, &buf_sz);
	if (!stream)
		return "platform/egl-nvidia capstr(), couldn't create memstream\n";

	const char* vendor = (const char*) glGetString(GL_VENDOR);
	const char* render = (const char*) glGetString(GL_RENDERER);
	const char* version = (const char*) glGetString(GL_VERSION);
	const char* shading = (const char*)glGetString(GL_SHADING_LANGUAGE_VERSION);
	const char* exts = (const char*) glGetString(GL_EXTENSIONS);
	const char* eglexts = (const char*)eglQueryString(egl.display,EGL_EXTENSIONS);

	fprintf(stream, "Video Platform (EGL-DRI)\n"
			"Vendor: %s\nRenderer: %s\nGL Version: %s\n"
			"GLSL Version: %s\n\n Extensions Supported: \n%s\n\n"
			"EGL Extensions supported: \n%s\n\n",
			vendor, render, version, shading, exts, eglexts);

	fclose(stream);

	return buf;
}

const char** PLATFORM_SYMBOL(_video_synchopts) ()
{
	return (const char**) egl_synchopts;
}

const char** PLATFORM_SYMBOL(_video_envopts)()
{
	return (const char**) egl_envopts;
}

void PLATFORM_SYMBOL(_video_prepare_external) () {}
void PLATFORM_SYMBOL(_video_restore_external) () {}

