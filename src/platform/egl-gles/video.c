/*
 * Copyright 2014-2017, Björn Ståhl
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
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <assert.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_shmif.h"

#ifndef PLATFORM_SUFFIX
#define PLATFORM_SUFFIX platform
#endif

#define MERGE(X,Y) X ## Y
#define EVAL(X,Y) MERGE(X,Y)
#define PLATFORM_SYMBOL(fun) EVAL(PLATFORM_SUFFIX, fun)

static struct {
	EGLDisplay disp;
	EGLContext ctx;
	EGLSurface surf;
	EGLConfig cfg;
	EGLNativeWindowType wnd;

	size_t canvasw, canvash, mdispw, mdisph;
} egl;

static char* egl_envopts[] = {
	NULL
};

struct monitor_mode PLATFORM_SYMBOL(_video_dimensions)()
{
	struct monitor_mode res = {
		.width = egl.canvasw,
		.height = egl.canvash
	};

	res.phy_width = (float) res.width / ARCAN_SHMPAGE_DEFAULT_PPCM * 10.0;
	res.phy_height = (float) res.height / ARCAN_SHMPAGE_DEFAULT_PPCM * 10.0;

	return res;
}

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
		DISPMANX_NO_ROTATE
	);

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

bool PLATFORM_SYMBOL(_video_set_mode)(
	platform_display_id disp, platform_mode_id mode)
{
	return disp == 0 && mode == 0;
}

int PLATFORM_SYMBOL(_video_cardhandle)(int cardn,
		int* buffer_method, size_t* metadata_sz, uint8_t** metadata)
{
	return -1;
}

bool PLATFORM_SYMBOL(_video_display_edid)(platform_display_id did,
	char** out, size_t* sz)
{
	*out = NULL;
	*sz = 0;
	return false;
}

bool PLATFORM_SYMBOL(_video_map_display)(
	arcan_vobj_id id, platform_display_id disp, enum blitting_hint hint)
{
	return false;
}

void PLATFORM_SYMBOL(_video_reset)(int id, int swap)
{
}

bool PLATFORM_SYMBOL(_video_specify_mode)(platform_display_id id,
	struct monitor_mode mode)
{
	return false;
}

void PLATFORM_SYMBOL(_video_preinit)()
{
}

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

/*
 * for headless EGL, look for EGL_KHR_surfaceless_context
 */

#ifdef WITH_BCM
	bcm_host_init();
#endif

	egl.disp = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	if (egl.disp == EGL_NO_DISPLAY){
		arcan_warning("Couldn't create display\n");
		return false;
	}

#ifdef EGL_OPENGL_ES3_BIT
	if (strcmp(agp_ident(), "GLES3") == 0)
		eglBindAPI(EGL_OPENGL_ES3_BIT);
	else
#endif
		eglBindAPI(EGL_OPENGL_ES2_BIT);

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
	assert(glGetError() == 0);

	eglSwapBuffers(egl.disp, egl.surf);

	egl.canvasw = w;
	egl.canvash = h;
	egl.mdispw = w;
	egl.mdisph = h;

	glViewport(0, 0, w, h);
	eglSwapInterval(egl.disp, 1);

	agp_init();
	return true;
}

bool PLATFORM_SYMBOL(_video_auth)(int cardn, unsigned token)
{
	return false;
}

struct monitor_mode* PLATFORM_SYMBOL(_video_query_modes)(
	platform_display_id id, size_t* count)
{
	static struct monitor_mode mode = {};

	mode.width  = egl.mdispw;
	mode.height = egl.mdisph;
	mode.depth  = sizeof(av_pixel) * 8;
	mode.refresh = 60; /* should be queried */

	*count = 1;
	return &mode;
}

void PLATFORM_SYMBOL(_video_query_displays)()
{
}

const char** PLATFORM_SYMBOL(_video_envopts)()
{
	return (const char**) egl_envopts;
}

void* PLATFORM_SYMBOL(_video_gfxsym)(const char* sym)
{
	return eglGetProcAddress(sym);
}

bool PLATFORM_SYMBOL(_video_map_handle)(
	struct agp_vstore* dst, int64_t handle)
{
	return false;
}

enum dpms_state
	PLATFORM_SYMBOL(_video_dpms)(platform_display_id did, enum dpms_state state)
{
	return ADPMS_ON;
}

const char* PLATFORM_SYMBOL(_video_capstr)()
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

size_t PLATFORM_SYMBOL(_video_displays)(platform_display_id* dids, size_t* lim)
{
	if (dids && lim && *lim > 0){
		dids[0] = 0;
	}

	return 1;
}

void PLATFORM_SYMBOL(_video_synch)(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

#ifndef HEADLESS_NOARCAN
	size_t nd;
	arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );

/*
 * a dumb way to go about it, but this platform is not exactly a priority
 */
	if (nd == 0){
		arcan_timesleep(16);
		goto out;
	}

	if (arcan_vint_worldrt()){
		agp_activate_rendertarget(NULL);
		arcan_vint_drawrt(arcan_vint_world(), 0, 0, egl.mdispw, egl.mdisph);

		arcan_vint_drawcursor(true);
		arcan_vint_drawcursor(false);
	}

	eglSwapBuffers(egl.disp, egl.surf);
out:
#endif

	if (post)
		post();
}

bool PLATFORM_SYMBOL(_video_set_display_gamma)(platform_display_id did,
	size_t n_ramps, uint16_t* r, uint16_t* g, uint16_t* b)
{
	return false;
}

bool PLATFORM_SYMBOL(_video_get_display_gamma)(platform_display_id did,
	size_t* n_ramps, uint16_t** outb)
{
	return false;
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

void PLATFORM_SYMBOL(_video_recovery) () {}
