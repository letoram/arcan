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
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

#include "../agp/glfun.h"

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
#include <GL/glx.h>

static struct {
	Display* xdisp;
	Window xwnd;
	XWindowAttributes xwa;
	GLXContext ctx;
	XVisualInfo* vi;
	size_t mdispw, mdisph;
	size_t canvasw, canvash;
} x11;

Display* x11_get_display()
{
	return x11.xdisp;
}

Window* x11_get_window()
{
	return &x11.xwnd;
}

int x11_get_evmask()
{
	return ExposureMask | PointerMotionMask | KeyPressMask |
		KeyReleaseMask | ButtonPressMask | ButtonReleaseMask;
}

static char* x11_synchopts[] = {
	"default", "driver- specific GLX swap buffers",
	NULL
};

static char* x11_envopts[] = {
	NULL
};

static bool setup_xwnd(int w, int h, bool fullscreen)
{
	x11.xdisp = XOpenDisplay(NULL);
	if (!x11.xdisp)
		return false;

	XSetWindowAttributes xwndattr;
	xwndattr.event_mask = x11_get_evmask();

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

struct monitor_mode PLATFORM_SYMBOL(_video_dimensions)()
{
	struct monitor_mode res = {
		.width = x11.canvasw,
		.height = x11.canvash,
		.phy_width = x11.mdispw,
		.phy_height = x11.mdisph
	};
	return res;
}

void* PLATFORM_SYMBOL(_video_gfxsym)(const char* sym)
{
	return glXGetProcAddress((const GLubyte*) sym);
}

bool PLATFORM_SYMBOL(_video_init) (uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* caption)
{
#if defined(WITH_HEADLESS_MAIN) || defined (HEADLESS_NOARCAN)
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

	XSync(x11.xdisp, False);

	x11.mdispw = x11.canvasw = w;
	x11.mdisph = x11.canvash = h;

	return true;
}

#ifndef HEADLESS_NOARCAN
bool PLATFORM_SYMBOL(_video_set_mode)(
	platform_display_id disp, platform_mode_id mode)
{
	return disp == 0 && mode == 0;
}

bool PLATFORM_SYMBOL(_video_specify_mode)(platform_display_id id,
	struct monitor_mode mode)
{
	return false;
}

bool PLATFORM_SYMBOL(_video_map_display)(
	arcan_vobj_id id, platform_display_id disp, enum blitting_hint hint)
{
	return false; /* no multidisplay /redirectable output support */
}

struct monitor_mode* PLATFORM_SYMBOL(_video_query_modes)(
	platform_display_id id, size_t* count)
{
	static struct monitor_mode mode = {};

	mode.width  = x11.mdispw;
	mode.height = x11.mdisph;
	mode.depth  = GL_PIXEL_BPP * 8;
	mode.refresh = 60; /* should be queried */

	*count = 1;
	return &mode;
}
#endif

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
		return "platform/x11 capstr(), couldn't create memstream";

	const char* vendor  = (const char*) glGetString(GL_VENDOR);
	const char* render  = (const char*) glGetString(GL_RENDERER);
	const char* version = (const char*) glGetString(GL_VERSION);
	const char* shading = (const char*) glGetString(GL_SHADING_LANGUAGE_VERSION);
	const char* exts    = (const char*) glGetString(GL_EXTENSIONS);

	fprintf(stream, "Video Platform (EGL-X11)\n"
		"Vendor: %s\nRenderer: %s\nGL Version: %s\n"
		"GLSL Version: %s\n\n Extensions Supported: \n%s\n\n",
		vendor, render, version, shading, exts
	);

	fclose(stream);

	return buf;
}

void PLATFORM_SYMBOL(_video_query_displays)()
{
}

const char** PLATFORM_SYMBOL(_video_synchopts)(void)
{
	return (const char**) x11_synchopts;
}

const char** PLATFORM_SYMBOL(_video_envopts)(void)
{
	return (const char**) x11_envopts;
}

int64_t PLATFORM_SYMBOL(_output_handle)(struct storage_info_t* store,
	enum status_handle* status)
{
	*status = ERROR_UNSUPPORTED;
	return -1;
}

void PLATFORM_SYMBOL(_video_setsynch)(const char* arg)
{
	arcan_warning("unhandled synchronization strategy (%s) ignored.\n", arg);
}

bool PLATFORM_SYMBOL(_video_map_handle)(
	struct storage_info_t* dst, int64_t handle)
{
	return false;
}

void PLATFORM_SYMBOL(_video_synch)(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

#ifndef HEADLESS_NOARCAN
	size_t dsz;
	arcan_bench_register_cost( arcan_vint_refresh(fract, &dsz) );

	agp_activate_rendertarget(NULL);

	static bool ld;

	if (dsz > 0 || !ld){
		arcan_vint_drawrt(arcan_vint_world(), 0, 0, x11.mdispw, x11.mdisph);
		ld = dsz == 0;
	}

	arcan_vint_drawcursor(true);
	arcan_vint_drawcursor(false);
#endif

#if defined(WITH_HEADLESS_MAIN) || defined(HEADLESS_NOARCAN)
	glFinish();
#else
	glXSwapBuffers(x11.xdisp, x11.xwnd);
#endif

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

void PLATFORM_SYMBOL(_video_minimize) () {}

