/*
 * Copyright 2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: egl-dri specific render-node based backend support
 * library for setting up headless display, and passing handles
 * handling render-node transfer
 */
#define WANT_ARCAN_SHMIF_HELPER
#include "../arcan_shmif.h"
#include "../shmif_privext.h"

#define EGL_EGLEXT_PROTOTYPES
#define MESA_EGL_NO_X11_HEADERS
#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <drm.h>
#include <drm_fourcc.h>
#include <xf86drm.h>
#include <gbm.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

static PFNEGLCREATEIMAGEKHRPROC create_image;
static PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC query_image_format;
static PFNEGLEXPORTDMABUFIMAGEMESAPROC export_dmabuf;
static PFNEGLDESTROYIMAGEKHRPROC destroy_image;

struct shmif_ext_hidden_int {
	struct gbm_device* dev;
	bool nopass;
	int fd;

	int type;
	struct {
		EGLContext context;
		EGLDisplay display;
		EGLSurface surface;
	};
};

static void check_functions(void*(*lookup)(void*, const char*), void* tag)
{
	create_image = (PFNEGLCREATEIMAGEKHRPROC)
		lookup(tag, "eglCreateImageKHR");
	destroy_image = (PFNEGLDESTROYIMAGEKHRPROC)
		lookup(tag, "eglDestroyImageKHR");
	query_image_format = (PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC)
		lookup(tag, "eglExportDMABUFImageQueryMESA");
	export_dmabuf = (PFNEGLEXPORTDMABUFIMAGEMESAPROC)
		lookup(tag, "eglExportDMABUFImageMESA");
}

static void gbm_drop(struct arcan_shmif_cont* con)
{
	if (!con->privext->internal)
		return;

	if (con->privext->internal->dev){
/*
 * Since we don't manage the context ourselves, it is not
 * safe to do this, as the EGL behavior seem to be to free this indirectly
 * during EGL display destruction
 * gbm_device_destroy(con->privext->internal->dev);
 */
		con->privext->internal->dev = NULL;
	}

	if (-1 != con->privext->internal->fd)
		close(con->privext->internal->fd);

	free(con->privext->internal);
	con->privext->internal = NULL;
}

struct arcan_shmifext_setup arcan_shmifext_headless_defaults()
{
	int major = getenv("AGP_GL_MAJOR") ?
		strtoul(getenv("AGP_GL_MAJOR"), NULL, 10) : 2;

	int minor= getenv("AGP_GL_MINOR") ?
		strtoul(getenv("AGP_GL_MINOR"), NULL, 10) : 1;

	return (struct arcan_shmifext_setup){
		.red = 8, .green = 8, .blue = 8,
		.alpha = 0, .depth = 0,
		.api = API_OPENGL,
		.major = 2, .minor = 1
	};
}

static void* lookup(void* tag, const char* sym)
{
	return eglGetProcAddress(sym);
}

void* arcan_shmifext_headless_lookup(
	struct arcan_shmif_cont* con, const char* fun)
{
	return eglGetProcAddress(fun);
}

enum shmifext_setup_status arcan_shmifext_headless_setup(
	struct arcan_shmif_cont* con,
	struct arcan_shmifext_setup arg)
{
	int type;
	switch (arg.api){
	case API_OPENGL:
		if (!eglBindAPI(EGL_OPENGL_API))
			return SHMIFEXT_NO_API;
		type = EGL_OPENGL_BIT;
	break;
	case API_GLES:
		if (!eglBindAPI(EGL_OPENGL_ES_API))
			return SHMIFEXT_NO_API;
		type = EGL_OPENGL_ES2_BIT;
	break;
	case API_VHK:
	default:
/* won't have working code here for a while, first need a working AGP_
 * implementation that works with normal Arcan. Then there's the usual
 * problem with getting access to a handle, for EGLStreams it should
 * work, but with GBM? KRH VKCube has some intel- only hack */
		return SHMIFEXT_NO_API;
	break;
	};

	void* display;
	if (!arcan_shmifext_headless_egl(con, &display, lookup, NULL))
		return SHMIFEXT_NO_DISPLAY;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;
	ctx->display = eglGetDisplay((EGLNativeDisplayType) display);
	if (!ctx->display)
		return SHMIFEXT_NO_DISPLAY;

	if (!eglInitialize(ctx->display, NULL, NULL))
		return SHMIFEXT_NO_EGL;

	const EGLint attribs[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, type,
		EGL_RED_SIZE, arg.red,
		EGL_GREEN_SIZE, arg.green,
		EGL_BLUE_SIZE, arg.blue,
		EGL_ALPHA_SIZE, arg.alpha,
		EGL_DEPTH_SIZE, arg.depth,
		EGL_NONE
	};

	EGLint nc, cc;

	if (!eglGetConfigs(ctx->display, NULL, 0, &nc))
		return SHMIFEXT_NO_CONFIG;

	if (0 == nc)
		return SHMIFEXT_NO_CONFIG;

	EGLConfig cfg;
	if (!eglChooseConfig(ctx->display, attribs, &cfg, 1, &nc) || nc < 1)
		return SHMIFEXT_NO_CONFIG;

	EGLint cas[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE,
		EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE,
		EGL_NONE, EGL_NONE, EGL_NONE};

	int ofs = 2;
	if (arg.major){
		cas[ofs++] = EGL_CONTEXT_MAJOR_VERSION_KHR;
		cas[ofs++] = arg.major;
		cas[ofs++] = EGL_CONTEXT_MINOR_VERSION_KHR;
		cas[ofs++] = arg.minor;
	}

	if (arg.mask){
		cas[ofs++] = EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR;
		cas[ofs++] = arg.mask;
	}

	if (arg.flags){
		cas[ofs++] = EGL_CONTEXT_FLAGS_KHR;
		cas[ofs++] = arg.flags;
	}

	ctx->context = eglCreateContext(ctx->display, cfg, EGL_NO_CONTEXT, cas);

	if (!ctx->context){
		ctx->display = NULL;
		return SHMIFEXT_NO_CONTEXT;
	}

	ctx->surface = EGL_NO_SURFACE;
	eglMakeCurrent(ctx->display, ctx->surface, ctx->surface, ctx->context);
	return SHMIFEXT_OK;
}

bool arcan_shmifext_headless_egl(struct arcan_shmif_cont* con,
	void** display, void*(*lookup)(void*, const char*), void* tag)
{
	if (!lookup || !con || !con->addr || !display)
		return false;

	int dfd = -1;

/* case for switching to another node */
	if (con->privext->pending_fd != -1){
		if (-1 != con->privext->active_fd){
			close(con->privext->active_fd);
			gbm_drop(con);
		}
		else
			dfd = con->privext->active_fd;
	}
/* or first setup without a pending_fd */
	else if (!con->privext->internal){
		const char* nodestr = getenv("ARCAN_RENDER_NODE") ?
			getenv("ARCAN_RENDER_NODE") : "/dev/dri/renderD128";
		dfd = open(nodestr, O_RDWR | O_CLOEXEC);
	}
/* mode-switch is no-op in init here, but we still may need
 * to update function pointers due to possible context changes */
	else {
		check_functions(lookup, tag);
		return true;
	}

	if (-1 == dfd)
		return false;

/* special cleanup to deal with gbm_device abstraction */
	con->privext->cleanup = gbm_drop;

/* finally open device */
	if (!con->privext->internal){
		con->privext->internal = malloc(sizeof(struct shmif_ext_hidden_int));
		if (!con->privext->internal)
			return false;

		memset(con->privext->internal, '\0', sizeof(struct shmif_ext_hidden_int));
		con->privext->internal->fd = -1;
		con->privext->internal->nopass = getenv("ARCAN_VIDEO_NO_FDPASS") ?
			true : false;
		if (NULL == (con->privext->internal->dev = gbm_create_device(dfd))){
			free(con->privext->internal);
			close(dfd);
			con->privext->internal = NULL;
			return false;
		}
	}

	*display = (void*) (con->privext->internal->dev);
	check_functions(lookup, tag);
	return true;
}

bool arcan_shmifext_egl_meta(struct arcan_shmif_cont* con,
	uintptr_t* display, uintptr_t* surface, uintptr_t* context)
{
	if (!con || !con->privext || !con->privext->internal ||
		!con->privext->internal->display)
		return false;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;
	if (display)
		*display = (uintptr_t) ctx->display;
	if (surface)
		*surface = (uintptr_t) ctx->surface;
	if (context)
		*context = (uintptr_t) ctx->context;

	return true;
}

bool arcan_shmifext_headless_vk(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag)
{
	return false;
}

int arcan_shmifext_eglsignal(struct arcan_shmif_cont* con,
	uintptr_t display, int mask, uintptr_t tex_id, ...)
{
	if (!con || !con->addr || !con->privext->internal || !create_image ||
		con->privext->internal->nopass)
		return -1;

/* missing: check nofdpass (or mask bit) and switch to synch_
 * readback and normal signalling */
	EGLDisplay* dpy = display == 0 ?
		con->privext->internal->display : (EGLDisplay*) display;

	if (!dpy)
		return -1;

	EGLImageKHR image = create_image(dpy, eglGetCurrentContext(),
		EGL_GL_TEXTURE_2D_KHR, (EGLClientBuffer)(tex_id), NULL
	);

	if (!image)
		return -1;

	int fourcc, nplanes;
	if (!query_image_format(dpy, image, &fourcc, &nplanes, NULL))
		return -1;

/* currently unsupported */
	if (nplanes != 1)
		return -1;

	EGLint stride;
	int fd;
	if (!export_dmabuf(dpy, image, &fd, &stride, NULL))
		return -1;

	unsigned res = arcan_shmif_signalhandle(con, mask, fd, stride, fourcc);
	destroy_image(dpy, image);

	if (con->privext->internal->fd != -1){
		close(con->privext->internal->fd);
	}
	con->privext->internal->fd = fd;
	return res > INT_MAX ? INT_MAX : res;
}

signed arcan_shmifext_vksignal(struct arcan_shmif_cont* con,
	uintptr_t context, int mask, uintptr_t tex_id, ...)
{
	return 0;
}
