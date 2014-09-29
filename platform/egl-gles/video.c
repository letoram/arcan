/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <assert.h>

#include GL_HEADERS

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

#ifndef EGL_SUFFIX
#define EGL_SUFFIX platform
#endif

#define MERGE(X,Y) X ## Y
#define EVAL(X,Y) MERGE(X,Y)
#define PLATFORM_SYMBOL(fun) EVAL(EGL_SUFFIX, fun)

static struct {
	EGLDisplay disp;
	EGLContext ctx;
	EGLSurface surf;
	EGLConfig cfg;
	EGLNativeWindowType wnd;
} egl;

static char* egl_synchopts[] = {
	"default", "driver default buffer swap",
	NULL
};

enum {
	DEFAULT,
	ENDM
}	synchopt;

#ifdef WITH_BCM

#include <bcm_host.h>
static bool alloc_bcm_wnd(uint16_t* w, uint16_t* h)
{
	DISPMANX_ELEMENT_HANDLE_T elem;
	DISPMANX_DISPLAY_HANDLE_T disp;
	DISPMANX_UPDATE_HANDLE_T upd;

  uint32_t dw;
  uint32_t dh;

  if (graphics_get_display_size(0, &dw, &dh) < 0){
		return false;
  }

	VC_RECT_T ddst = {
		.x = 0,
		.y = 0
	};

	VC_RECT_T dsrc = {
		.x = 0,
		.y = 0
	};

	if (*w == 0)
		*w = dw;
	else
		dw = *w;

	if (*h == 0)
		*h = dh;
	else
		dh = *h;

	ddst.width = dw;
	ddst.height = dh;

	dsrc.width = ddst.width << 16;
	dsrc.height = ddst.height << 16;

	VC_DISPMANX_ALPHA_T av = {
		.flags = DISPMANX_FLAGS_ALPHA_FIXED_ALL_PIXELS,
		.opacity = 255,
		.mask = 0
	};

	disp = vc_dispmanx_display_open(0);
	upd = vc_dispmanx_update_start(0);
	elem = vc_dispmanx_element_add(upd, disp,
		0, /* layer */
		&ddst,
		0,
		&dsrc,
		DISPMANX_PROTECTION_NONE,
		&av,
		0 /* clamp */,
		DISPMANX_NO_ROTATE);

	static EGL_DISPMANX_WINDOW_T wnd;
	wnd.element = elem;
	wnd.width = dw;
	wnd.height = dh;

	vc_dispmanx_update_submit_sync(upd);
	egl.wnd = &wnd;

	return true;
}
#endif

#ifndef EGL_NATIVE_DISPLAY
#define EGL_NATIVE_DISPLAY EGL_DEFAULT_DISPLAY
#endif

#ifdef WITH_OGL3
#ifdef WITH_HEADLESS
bool PLATFORM_SYMBOL(_video_init) (uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* title)
{
	arcan_fatal("not yet supported");
}

#else
bool PLATFORM_SYMBOL(_video_init) (uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* title)
{
	EGLint ca[] = {
		EGL_CONTEXT_CLIENT_VERSION,
		2, EGL_NONE
	};

	const EGLint attrlst[] =
	{
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
		EGL_RED_SIZE, 1,
		EGL_GREEN_SIZE, 1,
		EGL_BLUE_SIZE, 1,
		EGL_ALPHA_SIZE, 0,
		EGL_DEPTH_SIZE, 1,
		EGL_STENCIL_SIZE, 1,
		EGL_NONE
	};

	GLint major, minor;
	egl.disp = eglGetDisplay((EGLNativeDisplayType) EGL_NATIVE_DISPLAY);

	if (!eglInitialize(egl.disp, &major, &minor)){
		arcan_warning("Couldn't initialize EGL\n");
		return false;
	}

	if (!eglBindAPI(EGL_OPENGL_API)){
		arcan_warning("Couldn't bind EGL/OpenGL API, "
			"likely that driver does not support the EGL/OGL combination."
			"check driver/GL libraries or try a different platform (e.g. GLES2+)\n");
		return false;
	}

	GLint nc;
	if (!eglGetConfigs(egl.disp, NULL, 0, &nc)){
		arcan_warning("No configurations found\n");
		return false;
	}

	if (!eglChooseConfig(egl.disp, attrlst, &egl.cfg, 1, &nc)){
		arcan_warning("Couldn't activate/find a useful configuration\n");
		return false;
	}

	egl.ctx = eglCreateContext(egl.disp, egl.cfg, EGL_NO_CONTEXT, ca);
	if (egl.ctx == EGL_NO_CONTEXT){
		arcan_warning("(egl) Couldn't create EGL/GLES context\n");
		return false;
	}

	egl.surf = eglCreateWindowSurface(egl.disp, egl.cfg, egl.wnd, NULL);
	if (egl.surf == EGL_NO_SURFACE){
		arcan_warning("Couldn't create window\n");
		return false;
	}

	if (!eglMakeCurrent(egl.disp, egl.surf, egl.surf, egl.ctx)){
		arcan_warning("Couldn't activate context\n");
		return false;
	}

#ifdef WITH_GLEW
	int err;
	if ( (err = glewInit()) != GLEW_OK){
		platform_video_shutdown();
		arcan_warning("Couldn't initialize GLEW\n");
		return false;
	}
#endif

	arcan_video_display.pbo_support = true;
	arcan_video_display.width = w;
	arcan_video_display.height = h;
	arcan_video_display.bpp = bpp;

	drmModeSetCrtc(gbmkms.fd, gbmkms.enc->crtc_id, gbmkms.fb_id, 0, 0,
		&gbmkms.conn->connector_id, 1, &gbmkms.mode);

	struct gbm_bo* gbm_surface_lock_front_buffer(egl.surf);

/* allocate back buffer, call an additional time for
 * triple buffering */
	unsigned handle = gbm_bo_get_handle(bo).u32;
	unsigned stride = gbm_bo_get_stride(bo);

	if (-1 == drmModeAddFB(gbmkms.fd,
		arcan_video_display.width, arcan_video_display.height,
		24, 32, stride, handle, &gbmkms.fb_id))
		arcan_fatal("platform/egl: couldn't obtain framebuffer handle\n");

	gbm_surface_release_buffer(gbmkms.surf, bo);

	glViewport(0, 0, w, h);

	glClearColor(1.0f, 0.0f, 0.0f, 1.0f);

	glClear(GL_COLOR_BUFFER_BIT);
	eglSwapInterval(egl.disp, 1);
	eglSwapBuffers(egl.disp, egl.surf);

	return true;
}
#endif

#else
bool PLATFORM_SYMBOL(_video_init) (uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* caption)
{
	EGLint ca[] = {
		EGL_CONTEXT_CLIENT_VERSION,
		2, EGL_NONE
	};

	EGLint attrlst[] = {
		EGL_RED_SIZE, 8,
		EGL_GREEN_SIZE, 8,
		EGL_BLUE_SIZE, 8,
		EGL_ALPHA_SIZE, 8,
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_NONE
	};

#ifdef WITH_BCM
	bcm_host_init();
#endif

	egl.disp = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	if (egl.disp == EGL_NO_DISPLAY){
		arcan_warning("Couldn't create display\n");
		return false;
	}

#if defined(WITH_GLES3)
	arcan_video_display.pbo_support = true;
#else
/* probe for PBO extensions before failing this path */
	arcan_video_display.pbo_support = false;
#endif

	EGLint major, minor;
	if (!eglInitialize(egl.disp, &major, &minor)){
		arcan_warning("(egl) Couldn't initialize EGL\n");
		return false;
	}
	else
		arcan_warning("EGL Version %d.%d Found\n", major, minor);

	EGLint ncfg;
	if (EGL_FALSE == eglChooseConfig(egl.disp, attrlst, &egl.cfg, 1, &ncfg)){
		arcan_warning("(cgl) couldn't activate/choose configuration\n");
		return false;
	}

	if (EGL_FALSE == eglBindAPI(EGL_OPENGL_ES_API)){
		arcan_warning("(egl) couldn't bind API\n");
		return false;
	}

	egl.ctx = eglCreateContext(egl.disp, egl.cfg, EGL_NO_CONTEXT, ca);
	if (egl.ctx == EGL_NO_CONTEXT){
		arcan_warning("(egl) Couldn't create EGL/GLES context\n");
		return false;
	}

#ifdef WITH_BCM
	alloc_bcm_wnd(&w, &h);
#endif

	egl.surf = eglCreateWindowSurface(egl.disp, egl.cfg, egl.wnd, NULL);
	if (egl.surf == EGL_NO_SURFACE){
		arcan_warning("Couldn't create window\n");
		return false;
	}

	if (!eglMakeCurrent(egl.disp, egl.surf, egl.surf, egl.ctx)){
		arcan_warning("Couldn't activate context\n");
		return false;
	}

	eglSwapBuffers(egl.disp, egl.surf);

/*
 * Interestingly enough, EGL swap allows dirty rect updates with
 * eglSwapBuffersREegionNOK. In animations, we can, each update,
 * take the full boundary volume or better yet, go quadtree
 * and do dirty regions that way. Not leveraged yet but should
 * definitely be a concern later on.
 */
	#define check() assert(glGetError() == 0)
	check();

	arcan_warning("EGL context active (%d x %d)\n", w, h);
	arcan_video_display.width = w;
	arcan_video_display.height = h;
	arcan_video_display.bpp = bpp;
	glViewport(0, 0, w, h);

	eglSwapInterval(egl.disp, 1);

	return true;
}
#endif

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

const char* platform_video_capstr()
{
	static char* capstr;

	if (!capstr){
		const char* vendor = (const char*) glGetString(GL_VENDOR);
		const char* render = (const char*) glGetString(GL_RENDERER);
		const char* version = (const char*) glGetString(GL_VERSION);
		const char* shading = (const char*)glGetString(GL_SHADING_LANGUAGE_VERSION);
		const char* exts = (const char*) glGetString(GL_EXTENSIONS);

		size_t interim_sz = 64 * 1024;
		char* interim = malloc(interim_sz);
		size_t nw = snprintf(interim, interim_sz, "Video Platform (SDL)\n"
			"Vendor: %s\nRenderer: %s\nGL Version: %s\n"
			"GLSL Version: %s\n\n Extensions Supported: \n%s\n\n",
			vendor, render, version, shading, exts
		) + 1;

		if (nw < (interim_sz >> 1)){
			capstr = malloc(nw);
			memcpy(capstr, interim, nw);
			free(interim);
		}
		else
			capstr = interim;
	}

	return capstr;
}

void PLATFORM_SYMBOL(_video_synch)(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

	arcan_bench_register_cost( arcan_video_refresh(fract, true) );

/* render to current back buffer, in normal "externally managed"
 * buffered EGL, this also determines swapping / buffer behavior */
	eglSwapBuffers(egl.disp, egl.surf);

	if (post)
		post();
}

const char** PLATFORM_SYMBOL(_video_synchopts) ()
{
	return (const char**) egl_synchopts;
}

void PLATFORM_SYMBOL(_video_prepare_external) () {}
void PLATFORM_SYMBOL(_video_restore_external) () {}
void PLATFORM_SYMBOL(_video_shutdown) ()
{
	eglDestroyContext(egl.disp, egl.ctx);
	eglDestroySurface(egl.disp, egl.surf);
  eglTerminate(egl.disp);
}

void PLATFORM_SYMBOL(_video_minimize) () {}

