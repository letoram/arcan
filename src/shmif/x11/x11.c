#define WANT_ARCAN_SHMIF_HELPER
#include "../arcan_shmif.h"
#include "../shmif_privext.h"

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>

#include "agp/glfun.h"

#include <GL/glx.h>

struct shmif_ext_hidden_int {
	GLXContext ctx;
	XVisualInfo* vi;
	Display* display;
	Window wnd;
};

struct arcan_shmifext_setup arcan_shmifext_headless_defaults(
	struct arcan_shmif_cont* con)
{
return (struct arcan_shmifext_setup){
	.red = 8, .green = 8, .blue = 8,
	.alpha = 0, .depth = 0,
	.api = API_OPENGL,
	.major = 2, .minor = 1
};
}

static void x11_drop(struct arcan_shmif_cont* con)
{
if (!con->privext->internal)
		return;

	glXDestroyContext(con->privext->internal->display,
		con->privext->internal->ctx);
	XCloseDisplay(con->privext->internal->display);
	free(con->privext->internal);
	con->privext->internal = NULL;
}

void* arcan_shmifext_headless_lookup(
	struct arcan_shmif_cont* con, const char* fun)
{
	return glXGetProcAddress((const GLubyte*) fun);
}

enum shmifext_setup_status arcan_shmifext_headless_setup(
	struct arcan_shmif_cont* con,
	struct arcan_shmifext_setup arg)
{
	if (con->privext->internal)
		con->privext->cleanup(con);

	struct shmif_ext_hidden_int* ctx = con->privext->internal =
		malloc(sizeof(struct shmif_ext_hidden_int));

	if (!con->privext->internal)
		return SHMIFEXT_NO_DISPLAY;

	int alist[] = {
		GLX_RGBA,
		GLX_DEPTH_SIZE,
		24,
		None
	};

	con->privext->cleanup = x11_drop;
	ctx->display = XOpenDisplay(NULL);
	if (!ctx->display){
		free(con->privext->internal);
		con->privext->internal = NULL;
		return SHMIFEXT_NO_DISPLAY;
	}

	ctx->wnd = DefaultRootWindow(ctx->display);
	ctx->vi = glXChooseVisual(ctx->display, DefaultScreen(ctx->display), alist);
	ctx->ctx = glXCreateContext(ctx->display, ctx->vi, 0, GL_TRUE);
	if (!ctx->ctx){
		XCloseDisplay(con->privext->internal->display);
		free(con->privext->internal);
		con->privext->internal = NULL;
		return SHMIFEXT_NO_CONTEXT;
	}

	if (!glXMakeCurrent(ctx->display, ctx->wnd, ctx->ctx))
		XSync(ctx->display, False);

	return SHMIFEXT_OK;
}

bool arcan_shmifext_headless_egl(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag)
{
	return false;
}

bool arcan_shmifext_make_current(struct arcan_shmif_cont* con)
{
	return false;
}

bool arcan_shmifext_headless_vk(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag)
{
	return false;
}

int arcan_shmifext_eglsignal(struct arcan_shmif_cont* con,
	uintptr_t display, int mask, uintptr_t tex_id, ...)
{
	return -1;
}

int arcan_shmifext_vksignal(struct arcan_shmif_cont* con,
	uintptr_t display, int mask, uintptr_t tex_id, ...)
{
	return -1;
}
