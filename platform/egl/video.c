/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */

/*
 * A lot of toggleable options in this one.
 * Important ones:
 *  WITH_X11      - adds X11 support to context setup
 *  WITH_BCM      - special setup needed for certain broadcom GPUs
 *  WITH_GLES3    - default is GLES2, preferably we want 3 for PBOs
 *  WITH_OGL3     - when the 'nux graphics mess gets cleaned up,
 *                  this is the minimum version to support
 *  WITH_HEADLESS - allocates a GL context that lacks a framebuffer
 *                  only available on systems where we can use the 
 *                  KHR_ method of context creation (dep, WITH_OGL3)
 *  WITH_GLEW     - some setups might have problems with calls 
 *                  (particularly if you want to use some fancy extension)
 *                  this library helps with that, but not needed everywhere
 *
 * Each different device / Windowing type etc. need to have this defined:
 * EGL_NATIVE_DISPLAY 
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#include GL_HEADERS

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

static struct {
	EGLDisplay disp;
	EGLContext ctx;
	EGLSurface surf;
	EGLConfig cfg;
	EGLNativeWindowType wnd;
} egl;

#ifdef WITH_X11
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>

#define EGL_NATIVE_DISPLAY x11.xdisp

static struct {
	Display* xdisp;
	Window xwnd;
	XWindowAttributes xwa;
} x11;

static bool setup_xwnd(int w, int h, bool fullscreen)
{
	x11.xdisp = XOpenDisplay(NULL);
	if (!x11.xdisp)
		return false;

	XSetWindowAttributes xwndattr;
	xwndattr.event_mask = ExposureMask | PointerMotionMask | KeyPressMask;

	Window root = DefaultRootWindow(x11.xdisp);
	x11.xwnd = XCreateWindow(x11.xdisp, root, 0, 0, w, h, 0, CopyFromParent,
		InputOutput, CopyFromParent, CWEventMask, &xwndattr);

	XSetWindowAttributes xattr;
	xattr.override_redirect = False;
  XChangeWindowAttributes (x11.xdisp, x11.xwnd, CWOverrideRedirect, &xattr);

/*
 * We don't take care of input here, either we have an
 * input platform driver for x11 or we use a linux/bsd/...
 * specific one directly
 */
	XWMHints hints;
  hints.input = False;
  hints.flags = InputHint;
  XSetWMHints(x11.xdisp, x11.xwnd, &hints);
 
  XMapWindow(x11.xdisp, x11.xwnd);
  XStoreName(x11.xdisp, x11.xwnd, "Arcan"); 

	if (fullscreen){
		/* other properties needed */
	}

	egl.wnd = x11.xwnd;
	return true;
}
#endif

#ifdef WITH_BCM 
#include <bcm_host.h>
bool alloc_bcm_wnd(uint16_t* w, uint16_t* h)
{
	bcm_host_init();

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

void platform_video_bufferswap()
{
	eglSwapBuffers(egl.disp, egl.surf);
}

#ifndef EGL_NATIVE_DISPLAY
#define EGL_NATIVE_DISPLAY EGL_DEFAULT_DISPLAY
#endif

bool platform_video_init(uint16_t w, uint16_t h, uint8_t bpp, bool fs,
	bool frames)
{
	EGLint ca[] = { 
		EGL_CONTEXT_CLIENT_VERSION, 2, 
		EGL_NONE, 
		EGL_NONE 
	};

	EGLint attrlst[] = {
		EGL_RED_SIZE, 8,
		EGL_GREEN_SIZE, 8,
		EGL_BLUE_SIZE, 8,
		EGL_ALPHA_SIZE, 8,
		EGL_DEPTH_SIZE, 8,
		EGL_STENCIL_SIZE, 1,
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_NONE
	};

	EGLint nc;

#ifdef WITH_BCM
	alloc_bcm_wnd(&w, &h);
#endif

#ifdef WITH_X11
	if (!setup_xwnd(w, h, fs)){
		arcan_warning("Couldn't setup Window (X11)\n");
		return false;
	}
#endif

	egl.disp = eglGetDisplay((EGLNativeDisplayType) EGL_NATIVE_DISPLAY);
	arcan_video_display.pbo_support = false;

	if (egl.disp == EGL_NO_DISPLAY){
		arcan_warning("Couldn't create display\n");
		return false;
	}

	EGLint major, minor;

	if (!eglInitialize(egl.disp, &major, &minor)){
		arcan_warning("Couldn't initialize EGL\n");
		return false;
	}
	else 
		arcan_warning("EGL Version %d.%d Found\n", major, minor);

	if (!eglGetConfigs(egl.disp, NULL, 0, &nc)){
		arcan_warning("No fitting configurations found\n");
		return false;
	}

	if (!eglChooseConfig(egl.disp, attrlst, &egl.cfg, 1, &nc)){
		arcan_warning("Couldn't activate config\n");
		return false;
	}

	egl.ctx = eglCreateContext(egl.disp, egl.cfg, EGL_NO_CONTEXT, ca);
	if (egl.ctx == EGL_NO_CONTEXT){
		arcan_warning("Couldn't create EGL context\n");
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
	
	arcan_warning("EGL context active\n");
	arcan_video_display.width = w;
	arcan_video_display.height = h;
	arcan_video_display.bpp = bpp;
	glViewport(0, 0, w, h);

/* 
 * This should be needed less and less with newer GL versions
 */
#ifdef WITH_GLEW
	int err;
	if ( (err = glewInit()) != GLEW_OK){
		platform_video_shutdown();
		arcan_warning("Couldn't initialize GLEW\n");
		return false;
	}
#endif

	return true;
}

void platform_video_prepare_external()
{}

void platform_video_restore_external()
{}

void platform_video_shutdown()
{
	eglDestroyContext(egl.disp, egl.ctx);
	eglDestroySurface(egl.disp, egl.surf);
  eglTerminate(egl.disp);

#ifdef WITH_X11
  XDestroyWindow(x11.xdisp, x11.xwnd);
  XCloseDisplay(x11.xdisp);
#endif
}

void platform_video_timing(float* vsync, float* stddev, float* variance)
{
	*vsync = 16.667;
	*stddev = 0.01;
	*variance = 0.01;
}

void platform_video_minimize()
{
}
