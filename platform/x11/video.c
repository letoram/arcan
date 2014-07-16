/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */

/*
 * PLATFORM DRIVER NOTICE:
 * This platform driver is incomplete in the sense that it lacks;
 *  - proper mouse/keyboard input handling
 *
 * The reason for this is that the platform was mainly provided to support
 * accelerated "non-visible" or (for GL3+) offscreen windows that shouldn't
 * manage input anyhow (LWA mode and Libretro3D support)
 *
 * Anyone interested in improving this, expose the x11 struct (non-static)
 * and add a x11/event.c input driver that processes the event loop, maps
 * as arcan events (frameserver/vnc* bits have some example code for converting
 * keysyms back and forth between X and arcan).
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

#include GL_HEADERS

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

/*
 * These macro tweaks is so that we can include the .c file from
 * another platform (say arcan/video.c) with additional defines
 * e.g. WITH_HEADLESS and re-use the code.
 */
#ifndef PLATFORM_SUFFIX
#define PLATFORM_SUFFIX platform
#endif

#define MERGE(X,Y) X ## Y
#define EVAL(X,Y) MERGE(X,Y)
#define PLATFORM_SYMBOL(fun) EVAL(PLATFORM_SUFFIX, fun)

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>

struct {
	Display* xdisp;
	Window xwnd;
	XWindowAttributes xwa;
	GLXContext ctx;
	XVisualInfo* vi;
} x11;

static char* x11_synchopts[] = {
	"default", "driver- specific GLX swap buffers",
	NULL
};

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

	XWMHints hints;
  hints.input = True;
  hints.flags = InputHint;
  XSetWMHints(x11.xdisp, x11.xwnd, &hints);

  XMapWindow(x11.xdisp, x11.xwnd);
  XStoreName(x11.xdisp, x11.xwnd, "Arcan");

	if (fullscreen){
		XEvent xev = {0};
 		Atom wm_state = XInternAtom ( x11.xdisp, "_NET_WM_STATE", False );
	  Atom fsa = XInternAtom ( x11.xdisp, "_NET_WM_STATE_FULLSCREEN", False );

  	xev.type = ClientMessage;
	  xev.xclient.window = x11.xwnd;
  	xev.xclient.message_type = wm_state;
  	xev.xclient.format = 32;
	  xev.xclient.data.l[0] = 1;
	  xev.xclient.data.l[1] = fsa;
	  XSendEvent ( x11.xdisp, DefaultRootWindow( x11.xdisp ), False,
			SubstructureNotifyMask, &xev );
	}

	return true;
}

#ifdef WITH_OFFSCREEN
bool PLATFORM_SYMBOL(_video_init) (uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames)
{
/*
	static int visual_attribs[] = {
               None
 	};
	int context_attribs[] = {
 		GLX_CONTEXT_MAJOR_VERSION_ARB, 3,
		GLX_CONTEXT_MINOR_VERSION_ARB, 0,
		None
	};

	Display* dpy = XOpenDisplay(0);
  	int fbcount = 0;
		GLXFBConfig* fbc = NULL;
		GLXContext ctx;
		GLXPbuffer pbuf;

	if ( ! (dpy = XOpenDisplay(0)) ){
		return false;
	}

	if ( !(fbc = glXChooseFBConfig(dpy, DefaultScreen(dpy), visual_attribs, &fbcount) ) )
  	return false;

	glXCreateContextAttribsARB = (glXCreateContextAttribsARBProc)
		glXGetProcAddressARB( (const GLubyte *) "glXCreateContextAttribsARB");

	glXMakeContextCurrentARB = (glXMakeContextCurrentARBProc)
		glXGetProcAddressARB( (const GLubyte *) "glXMakeContextCurrent");

	if ( !(glXCreateContextAttribsARB && glXMakeContextCurrentARB) ){
 		fprintf(stderr, "missing support for GLX_ARB_create_context\n");
   	XFree(fbc);
   	exit(1);
	}

	if ( !( ctx = glXCreateContextAttribsARB(dpy, fbc[0], 0, True, context_attribs)) ){
		fprintf(stderr, "Failed to create opengl context\n");
		XFree(fbc);
		exit(1);
	}

	int pbuffer_attribs[] = {
		GLX_PBUFFER_WIDTH, w,
		GLX_PBUFFER_HEIGHT, h,
		None
	};
	pbuf = glXCreatePbuffer(dpy, fbc[0], pbuffer_attribs);
	XFree(fcb);
	XSync(dpy, false);
*/
}

#else
bool PLATFORM_SYMBOL(_video_init) (uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* caption)
{
#if defined(WITH_HEADLESS) || defined(WITH_HEADLESS_MAIN)
	x11.xdisp = XOpenDisplay(NULL);
	x11.xwnd = DefaultRootWindow(x11.xdisp);
#else
	if (!setup_xwnd(w, h, fs)){
		arcan_warning("(x11) Couldn't setup window\n");
		return false;
	}
#endif

	int alist[] = {
		GLX_RGBA,
		GLX_DOUBLEBUFFER,
		GLX_DEPTH_SIZE,
		24,
		None
	};

	int err;
	x11.vi = glXChooseVisual(x11.xdisp, DefaultScreen(x11.xdisp), alist);
	if (!x11.vi){
		arcan_warning("(x11) Couldn't find a suitable visual\n");
		return false;
	}

	x11.ctx = glXCreateContext(x11.xdisp, x11.vi, 0, GL_TRUE);
	if (!x11.ctx){
		arcan_warning("(x11) Couldn't create GL2.1 context\n");
		return false;
	}

	if (!glXMakeCurrent(x11.xdisp, x11.xwnd, x11.ctx)){
		arcan_warning("video_init failed while trying to activate glx context.\n");
		return false;
	}

	if ( (err = glewInit()) != GLEW_OK){
		arcan_warning("arcan_video_init(), Couldn't initialize GLew: %s\n",
			glewGetErrorString(err));
		return false;
	}

	XSync(x11.xdisp, False);

#ifndef HEADLESS_NOARCAN
	arcan_video_display.pbo_support = arcan_video_display.fbo_support = true;
	arcan_video_display.width = w;
	arcan_video_display.height = h;
	arcan_video_display.bpp = bpp;
#endif

	glViewport(0, 0, w, h);

	return true;
}
#endif

const char** PLATFORM_SYMBOL(_video_synchopts)()
{
	return (const char**) x11_synchopts;
}

void PLATFORM_SYMBOL(_video_setsynch)(const char* arg)
{
	arcan_warning("unhandled synchronization strategy (%s) ignored.\n", arg);
}

void PLATFORM_SYMBOL(_video_synch)(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

	arcan_bench_register_cost( arcan_video_refresh(fract) );
/*
	while (XPending(x11.xdisp)){
		XEvent xev;
		XNextEvent(x11.xdisp, &xev);
		if (xev.type == KeyPress)
						exit(1);
	}
*/

	glXSwapBuffers(x11.xdisp, x11.xwnd);
	if (post)
		post();
}

void PLATFORM_SYMBOL(_video_prepare_external) () {}
void PLATFORM_SYMBOL(_video_restore_external) () {}

void PLATFORM_SYMBOL(_video_shutdown) ()
{
	glXMakeCurrent(x11.xdisp, None, NULL);
	glXDestroyContext(x11.xdisp, x11.ctx);
  XDestroyWindow(x11.xdisp, x11.xwnd);
  XCloseDisplay(x11.xdisp);
}

void PLATFORM_SYMBOL(_video_timing) (
	float* vsync, float* stddev, float* variance)
{
	*vsync = 16.667;
	*stddev = 0.01;
	*variance = 0.01;
}

void PLATFORM_SYMBOL(_video_minimize) () {}

