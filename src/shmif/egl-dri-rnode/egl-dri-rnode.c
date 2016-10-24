/*
 * Copyright 2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: egl-dri specific render-node based backend support
 * library for setting up headless display, and passing handles
 * handling render-node transfer
 */
#define WANT_ARCAN_SHMIF_HELPER
#define AGP_ENABLE_UNPURE
#include "../arcan_shmif.h"
#include "../shmif_privext.h"
#include "video_platform.h"

#define EGL_EGLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES
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
	struct agp_rendertarget* rtgt;
	struct storage_info_t vstore;
	bool nopass;
	int fd;

	int type;
	struct {
		bool managed;
		EGLContext context;
		EGLDisplay display;
		EGLSurface surface;
	};
};

/*
 * These are spilled over from AGP, and ideally, we should just
 * separate those references or linker-script erase them as they are
 * not needed here
 */
void* platform_video_gfxsym(const char* sym)
{
	return eglGetProcAddress(sym);
}

bool platform_video_map_handle(struct storage_info_t* store, int64_t handle)
{
	return false;
}

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

	struct shmif_ext_hidden_int* in = con->privext->internal;

	if (in->dev){
/* this will actually free the gbm- resources as well */
		if (in->managed){
			eglMakeCurrent(in->display,
				EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
			eglDestroyContext(in->display, in->context);
			eglTerminate(in->display);
		}
		if (in->rtgt){
			agp_drop_rendertarget(in->rtgt);
			agp_drop_vstore(&in->vstore);

		}
		con->privext->internal->dev = NULL;
	}

	if (-1 != con->privext->internal->fd)
		close(con->privext->internal->fd);

	free(con->privext->internal);
	con->privext->internal = NULL;
}

struct arcan_shmifext_setup arcan_shmifext_headless_defaults(
	struct arcan_shmif_cont* con)
{
	int major = getenv("AGP_GL_MAJOR") ?
		strtoul(getenv("AGP_GL_MAJOR"), NULL, 10) : 2;

	int minor= getenv("AGP_GL_MINOR") ?
		strtoul(getenv("AGP_GL_MINOR"), NULL, 10) : 1;

	return (struct arcan_shmifext_setup){
		.red = 8, .green = 8, .blue = 8,
		.alpha = 0, .depth = 0,
		.api = API_OPENGL,
		.builtin_fbo = true,
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
	ctx->managed = true;
	eglMakeCurrent(ctx->display, ctx->surface, ctx->surface, ctx->context);

	if (arg.builtin_fbo){
		agp_empty_vstore(&ctx->vstore, con->w, con->h);
		ctx->rtgt = agp_setup_rendertarget(
			&ctx->vstore, arg.depth > 0 ? RENDERTARGET_COLOR_DEPTH_STENCIL :
				RENDERTARGET_COLOR);
	}

	return SHMIFEXT_OK;
}

bool arcan_shmifext_headless_drop(struct arcan_shmif_cont* con)
{
	if (!con || !con->privext || !con->privext->internal ||
		!con->privext->internal->display)
		return false;

	gbm_drop(con);
	return true;
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

bool arcan_shmifext_make_current(struct arcan_shmif_cont* con)
{
	if (!con || !con->privext || !con->privext->internal ||
		!con->privext->internal->display)
		return false;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;

	eglMakeCurrent(ctx->display, ctx->surface, ctx->surface, ctx->context);
	if (ctx->rtgt){
		if (ctx->vstore.w != con->w || ctx->vstore.h != con->h){
			agp_activate_rendertarget(NULL);
			agp_resize_rendertarget(ctx->rtgt, con->w, con->h);
		}
		agp_activate_rendertarget(ctx->rtgt);
	}

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
	if (!con || !con->addr || !con->privext || !con->privext->internal)
		return -1;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;
	struct storage_info_t vstore = {0};

	EGLDisplay* dpy = display == 0 ?
		con->privext->internal->display : (EGLDisplay*) display;

	if (tex_id == SHMIFEXT_BUILTIN){
		if (ctx->managed)
			tex_id = ctx->vstore.vinf.text.glid;
		else
			return -1;
	}

	if (!dpy)
		return -1;

	if (con->privext->internal->nopass || !create_image)
		goto fallback;

	EGLImageKHR image = create_image(dpy, eglGetCurrentContext(),
		EGL_GL_TEXTURE_2D_KHR, (EGLClientBuffer)(tex_id), NULL
	);

	if (!image)
		goto fallback;

	int fourcc, nplanes;
	if (!query_image_format(dpy, image, &fourcc, &nplanes, NULL))
		goto fallback;

/* currently unsupported */
	if (nplanes != 1)
		goto fallback;

	EGLint stride;
	int fd;
	if (!export_dmabuf(dpy, image, &fd, &stride, NULL))
		goto fallback;

	unsigned res = arcan_shmif_signalhandle(con, mask, fd, stride, fourcc);
	destroy_image(dpy, image);

	if (con->privext->internal->fd != -1){
		close(con->privext->internal->fd);
	}
	con->privext->internal->fd = fd;
	return res > INT_MAX ? INT_MAX : res;

/*
 * this should really be switched to flipping PBOs, or even better,
 * somehow be able to mark/pin our output buffer for safe readback
 */
fallback:
	vstore.vinf.text.raw = (void*) con->vidp;
	agp_activate_rendertarget(NULL);
	agp_readback_synchronous(&vstore);
	res = arcan_shmif_signal(con, mask);
	return res > INT_MAX ? INT_MAX : res;
}

signed arcan_shmifext_vksignal(struct arcan_shmif_cont* con,
	uintptr_t context, int mask, uintptr_t tex_id, ...)
{
	return 0;
}
