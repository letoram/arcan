#define WANT_ARCAN_SHMIF_HELPER
#define AGP_ENABLE_UNPURE
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
	struct agp_rendertarget* rtgt;
	struct agp_vstore vstore;
	struct agp_fenv fenv;
	bool managed;
	Window wnd;
};

struct arcan_shmifext_setup arcan_shmifext_defaults(
	struct arcan_shmif_cont* con)
{
	return (struct arcan_shmifext_setup){
		.red = 8, .green = 8, .blue = 8,
		.alpha = 0, .depth = 24,
		.api = API_OPENGL,
		.builtin_fbo = true,
		.major = 2, .minor = 1
	};
}

struct agp_fenv* arcan_shmifext_getfenv(struct arcan_shmif_cont* con)
{
	if (!con || !con->privext || !con->privext->internal)
		return false;

	struct shmif_ext_hidden_int* in = con->privext->internal;
	return &in->fenv;
}

bool arcan_shmifext_import_buffer(
	struct arcan_shmif_cont* cont,
	struct shmifext_buffer_plane* planes,
	int format,
	size_t n_planes,
	size_t buffer_plane_sz
)
{
	return false;
}

static void x11_drop(struct arcan_shmif_cont* con)
{
	if (!con->privext->internal)
		return;

	struct shmif_ext_hidden_int* in = con->privext->internal;

	if (in->managed){
		glXDestroyContext(in->display, in->ctx);
		XCloseDisplay(in->display);
	}
	if (in->rtgt){
		agp_drop_rendertarget(in->rtgt);
		agp_drop_vstore(&in->vstore);
		in->rtgt = NULL;
	}

	free(con->privext->internal);
	con->privext->internal = NULL;
}

bool arcan_shmifext_drop(struct arcan_shmif_cont* con)
{
	if (!con || !con->privext || !con->privext->internal)
		return false;
	x11_drop(con);
	return true;
}

bool arcan_shmifext_drop_context(struct arcan_shmif_cont* con)
{
	return arcan_shmifext_drop(con);
}

void* arcan_shmifext_lookup(
	struct arcan_shmif_cont* con, const char* fun)
{
	return glXGetProcAddress((const GLubyte*) fun);
}

static void* lookup_fun(void* tag, const char* sym, bool req)
{
	return glXGetProcAddress((const GLubyte*) sym);
}

void arcan_shmifext_swap_context(
	struct arcan_shmif_cont* con, unsigned context)
{
}

unsigned arcan_shmifext_add_context(
	struct arcan_shmif_cont* con, struct arcan_shmifext_setup arg)
{
	return 0;
}

enum shmifext_setup_status arcan_shmifext_setup(
	struct arcan_shmif_cont* con,
	struct arcan_shmifext_setup arg)
{
	if (con->privext->internal)
		con->privext->cleanup(con);

	struct shmif_ext_hidden_int* ctx = con->privext->internal =
		malloc(sizeof(struct shmif_ext_hidden_int));
	memset(ctx, '\0', sizeof(struct shmif_ext_hidden_int));

	if (!con->privext->internal)
		return SHMIFEXT_NO_DISPLAY;

	int alist[] = {
		GLX_RGBA,
		GLX_DEPTH_SIZE,
		arg.depth,
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

	agp_glinit_fenv(&con->privext->internal->fenv, lookup_fun, NULL);

	if (!glXMakeCurrent(ctx->display, ctx->wnd, ctx->ctx))
		XSync(ctx->display, False);

	ctx->managed = true;
	if (arg.builtin_fbo){
		agp_empty_vstore(&ctx->vstore, con->w, con->h);
		ctx->rtgt = agp_setup_rendertarget(
			&ctx->vstore, arg.depth > 0 ? RENDERTARGET_COLOR_DEPTH_STENCIL :
				RENDERTARGET_COLOR);
	}

	return SHMIFEXT_OK;
}

void arcan_shmifext_bufferfail(struct arcan_shmif_cont* cont, bool fl)
{
}

int arcan_shmifext_dev(struct arcan_shmif_cont* con,
	uintptr_t* dev, bool clone)
{
	if (dev)
		*dev = 0;

    return -1;
}

bool arcan_shmifext_gl_handles(struct arcan_shmif_cont* con,
	uintptr_t* frame, uintptr_t* color, uintptr_t* depth)
{
	if (!con || !con->privext || !con->privext->internal ||
		!con->privext->internal->display || !con->privext->internal->rtgt)
		return false;

	agp_rendertarget_ids(con->privext->internal->rtgt, frame, color, depth);
	return true;
}

bool arcan_shmifext_egl(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag)
{
	return false;
}

bool arcan_shmifext_gltex_handle(struct arcan_shmif_cont* con,
   uintptr_t display, uintptr_t tex_id,
	 int* dhandle, size_t* dstride, int* dfmt)
{
	return false;
}

bool arcan_shmifext_make_current(struct arcan_shmif_cont* con)
{
	if (!con || !con->privext || !con->privext->internal)
		return false;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;

	if (!glXMakeCurrent(ctx->display, ctx->wnd, ctx->ctx)){
		XSync(ctx->display, False);
		return false;
	}

	if (ctx->rtgt){
		if (ctx->vstore.w != con->w || ctx->vstore.h != con->h){
			agp_activate_rendertarget(NULL);
			agp_resize_rendertarget(ctx->rtgt, con->w, con->h);
		}
		agp_activate_rendertarget(ctx->rtgt);
	}

	return true;
}

int arcan_shmifext_isext(struct arcan_shmif_cont* con)
{
	if (con && con->privext && con->privext->internal)
		return 2; /* we don't support handle passing via IOSurfaces yet */
	return 0;
}

bool arcan_shmifext_vk(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag)
{
	return false;
}

int arcan_shmifext_signal(struct arcan_shmif_cont* con,
	uintptr_t display, int mask, uintptr_t tex_id, ...)
{
	if (!con || !con->privext || !con->privext->internal)
		return -1;
	struct shmif_ext_hidden_int* ctx = con->privext->internal;

	if (tex_id == SHMIFEXT_BUILTIN){
		if (ctx->managed)
			tex_id = ctx->vstore.vinf.text.glid;
		else
			return -1;
	}

/*
 * There are some possible extensions for sharing resources from a GLX
 * context between processes, but it's on the very distant research- list
 * and would need a corresponding _map_handle etc. implementation server-side
 *
 * right now, juse use the slow readback method
 */
	struct agp_vstore vstore = {
		.w = con->w,
		.h = con->h,
		.txmapped = TXSTATE_TEX2D,
		.vinf.text = {
			.glid = tex_id,
			.raw = (void*) con->vidp
		},
	};

	if (ctx->rtgt){
		agp_activate_rendertarget(NULL);
		agp_readback_synchronous(&vstore);
		agp_activate_rendertarget(ctx->rtgt);
	}
	else
		agp_readback_synchronous(&vstore);

	unsigned res = arcan_shmif_signal(con, mask);
	return res > INT_MAX ? INT_MAX : res;
}

bool platform_video_map_handle(struct agp_vstore* store, int64_t handle)
{
	return false;
}
