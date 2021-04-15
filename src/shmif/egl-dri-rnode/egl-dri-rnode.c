/*
 * Copyright 2016-2020, Björn Ståhl
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
#include "egl-dri/egl.h"
#include "agp/glfun.h"

#define EGL_EGLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES
#define MESA_EGL_NO_X11_HEADERS
#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <inttypes.h>
#include <drm.h>
#include <drm_fourcc.h>
#include <xf86drm.h>
#include <gbm.h>
#include <stdatomic.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/ioctl.h>

#include "egl-dri/egl_gbm_helper.h"

_Thread_local static struct arcan_shmif_cont* active_context;

static struct agp_fenv agp_fenv;
static struct egl_env agp_eglenv;

#define SHARED_DISPLAY (uintptr_t)(-1)

/*
 *
 * for EGLStreams, we need:
 *  1. egl->eglGetPlatformDisplayEXT : EGL_EXT_platform_base
 *  2. egl->eglQueryDevicesEXT : EGL_EXT_device_base
 *     OR get the device enumeration
 *  THEN
 *     when we get buffer method to streams
 *
 * we ALSO have:
 *  GL_EXT_memory_object : glCreateMemoryObjectsEXT,
 *  glMemoryObjectParameterivEXT, glTextStorageMem2DEXT,
 *  GL_NVX_unix_allocator_import. 2glImportMemoryFdEXT, glTexParametervNVX
 *  GL_EXT_memory_object_fd,
 *  ARB_texture_storage,
 */

/* note: should also get:
 * eglCreateSyncKHR,
 * eglDestroySyncKHR,
 * eglWaitSyncKHR,
 * eglClientWaitSyncKHR,
 * eglDupNativeFenceFDANDROID
 */

struct shmif_ext_hidden_int {
	struct gbm_device* dev;
	char* device_path;

	struct agp_rendertarget* rtgt;
	struct agp_vstore buf;

/* need to account for multiple contexts being created on the same setup */
	uint64_t ctx_alloc;
	EGLContext alt_contexts[64];

	int type;
	bool managed;
	EGLContext context;
	unsigned context_ind;
	EGLDisplay display;
	EGLSurface surface;
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

bool platform_video_map_handle(struct agp_vstore* store, int64_t handle)
{
	return false;
}

bool platform_video_map_buffer(
	struct agp_vstore* vs, struct agp_buffer_plane* planes, size_t n)
{
	return false;
}

struct agp_fenv* arcan_shmifext_getfenv(struct arcan_shmif_cont* con)
{
	if (!con || !con->privext || !con->privext->internal)
		return false;

	return &agp_fenv;
}

static void zap_vstore(struct agp_vstore* vstore)
{
	free(vstore->vinf.text.raw);
	vstore->vinf.text.raw = NULL;
	vstore->vinf.text.s_raw = 0;
}

static void gbm_drop(struct arcan_shmif_cont* con)
{
	if (!con->privext->internal)
		return;

	struct shmif_ext_hidden_int* in = con->privext->internal;

	if (in->dev){
/* this will actually free the gbm- resources as well */
		if (in->rtgt){
			agp_drop_rendertarget(in->rtgt);
		}
	}
/* are we managing the context or is the user providing his own? */
	if (in->managed){
		agp_eglenv.make_current(in->display,
			EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
		if (in->context)
			agp_eglenv.destroy_context(in->display, in->context);
		agp_eglenv.terminate(in->display);
	}
	in->dev = NULL;

	if (in->device_path){
		free(in->device_path);
		in->device_path = NULL;
	}

	free(in);
	con->privext->internal = NULL;
	con->privext->cleanup = NULL;
}

struct arcan_shmifext_setup arcan_shmifext_defaults(
	struct arcan_shmif_cont* con)
{
	int major = getenv("AGP_GL_MAJOR") ?
		strtoul(getenv("AGP_GL_MAJOR"), NULL, 10) : 2;

	int minor= getenv("AGP_GL_MINOR") ?
		strtoul(getenv("AGP_GL_MINOR"), NULL, 10) : 1;

	return (struct arcan_shmifext_setup){
		.red = 1, .green = 1, .blue = 1,
		.alpha = 1, .depth = 16,
		.api = API_OPENGL,
		.builtin_fbo = 1,
		.major = 2, .minor = 1,
		.shared_context = 0
	};
}

bool arcan_shmifext_import_buffer(
	struct arcan_shmif_cont* con,
	int format,
	struct shmifext_buffer_plane* planes,
	size_t n_planes,
	size_t buffer_plane_sz
)
{
	if (!con || !con->addr || !con->privext || !con->privext->internal)
		return false;

	struct shmif_ext_hidden_int* I = con->privext->internal;
	EGLDisplay display = I->display;

	if ((uintptr_t)I->display == SHARED_DISPLAY){
		if (!active_context)
			return false;

		struct shmif_ext_hidden_int* O = active_context->privext->internal;
		display = O->display;
	}

	struct agp_vstore* vs = &I->buf;
	vs->txmapped = TXSTATE_TEX2D;

	if (I->rtgt){
		agp_drop_rendertarget(I->rtgt);
		I->rtgt = NULL;
		memset(vs, '\0', sizeof(struct agp_vstore));
	}

	EGLImage img = helper_dmabuf_eglimage(
		&agp_fenv, &agp_eglenv, display, planes, n_planes);

	if (!img)
		return false;

/* might have an old eglImage around */
	if (0 != vs->vinf.text.tag){
		agp_eglenv.destroy_image(display, (EGLImageKHR) vs->vinf.text.tag);
	}

	I->buf.w = planes[0].w;
	I->buf.h = planes[0].h;

	helper_eglimage_color(&agp_fenv, &agp_eglenv, img, &vs->vinf.text.glid);
	vs->vinf.text.tag = (uintptr_t) img;

	return true;
}

static void* lookup(void* tag, const char* sym)
{
	return eglGetProcAddress(sym);
}

void* arcan_shmifext_lookup(
	struct arcan_shmif_cont* con, const char* fun)
{
	return eglGetProcAddress(fun);
}

static void* lookup_fenv(void* tag, const char* sym, bool req)
{
	return eglGetProcAddress(sym);
}

static bool get_egl_context(
	struct shmif_ext_hidden_int* ctx, unsigned ind, EGLContext* dst)
{
	if (ind >= 64)
		return false;

	if (!ctx->managed || !((1 << ind) & ctx->ctx_alloc))
		return false;

	*dst = ctx->alt_contexts[(1 << ind)-1];
	return true;
}

static enum shmifext_setup_status add_context(
	struct shmif_ext_hidden_int* ctx, struct arcan_shmifext_setup* arg,
	unsigned* ind)
{
/* make sure the shmifext has been setup */
	int type;
	EGLint nc;
	switch(arg->api){
		case API_OPENGL: type = EGL_OPENGL_BIT; break;
		case API_GLES: type = EGL_OPENGL_ES2_BIT; break;
		default:
			return SHMIFEXT_NO_API;
		break;
	}

	const EGLint attribs[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, type,
		EGL_RED_SIZE, arg->red,
		EGL_GREEN_SIZE, arg->green,
		EGL_BLUE_SIZE, arg->blue,
		EGL_ALPHA_SIZE, arg->alpha,
		EGL_DEPTH_SIZE, arg->depth,
		EGL_NONE
	};

/* find first free context in bitmap */
	size_t i = 0;
	bool found = false;
	for (; i < 64; i++)
		if (!(ctx->ctx_alloc & (1 << i))){
			found = true;
			break;
		}

/* common for GL applications to treat 0 as no context, so we do the same, have
 * to add/subtract 1 from the index (or just XOR with a cookie */
	if (!found)
		return SHMIFEXT_OUT_OF_MEMORY;

	if (!agp_eglenv.get_configs(ctx->display, NULL, 0, &nc))
		return SHMIFEXT_NO_CONFIG;

	if (0 == nc)
		return SHMIFEXT_NO_CONFIG;

	EGLConfig cfg;
	if (!agp_eglenv.choose_config(ctx->display, attribs, &cfg, 1, &nc) || nc < 1)
		return SHMIFEXT_NO_CONFIG;

	EGLint cas[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE,
		EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE,
		EGL_NONE, EGL_NONE, EGL_NONE};

	int ofs = 2;
	if (arg->api != API_GLES){
		if (arg->major){
			cas[ofs++] = EGL_CONTEXT_MAJOR_VERSION_KHR;
			cas[ofs++] = arg->major;
			cas[ofs++] = EGL_CONTEXT_MINOR_VERSION_KHR;
			cas[ofs++] = arg->minor;
		}

		if (arg->mask){
			cas[ofs++] = EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR;
			cas[ofs++] = arg->mask;
		}

		if (arg->flags){
			cas[ofs++] = EGL_CONTEXT_FLAGS_KHR;
			cas[ofs++] = arg->flags;
		}
	}

/* pick a pre-existing / pre-added bit that has been manually
 * added to the specific shmif context */
	EGLContext sctx = NULL;
	if (arg->shared_context)
		get_egl_context(ctx, arg->shared_context, &sctx);

	ctx->alt_contexts[(1 << i)-1] =
		agp_eglenv.create_context(ctx->display, cfg, sctx, cas);

	if (!ctx->alt_contexts[(1 << i)-1])
		return SHMIFEXT_NO_CONTEXT;

	ctx->ctx_alloc |= 1 << i;
	*ind = i+1;
	return SHMIFEXT_OK;
}

unsigned arcan_shmifext_add_context(
	struct arcan_shmif_cont* con, struct arcan_shmifext_setup arg)
{
	if (!con || !con->privext || !con->privext->internal ||
		!con->privext->internal->display)
			return 0;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;

	unsigned res;
	if (SHMIFEXT_OK != add_context(ctx, &arg, &res)){
		return 0;
	}

	return res;
}

void arcan_shmifext_swap_context(
	struct arcan_shmif_cont* con, unsigned context)
{
	if (!con || !con->privext || !con->privext->internal ||
		!con->privext->internal->display || context > 64 || !context)
			return;

	context--;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;
	EGLContext egl_ctx;

	if (!get_egl_context(ctx, context, &egl_ctx))
		return;

	ctx->context_ind = context;
	ctx->context = egl_ctx;
	agp_eglenv.make_current(ctx->display, ctx->surface, ctx->surface, ctx->context);
}

static bool scanout_alloc(
	struct agp_rendertarget* tgt, struct agp_vstore* vs, int action, void* tag)
{
	struct agp_fenv* env = agp_env();
	struct arcan_shmif_cont* conn = tag;

	if (action == RTGT_ALLOC_FREE){
		struct shmifext_color_buffer* buf =
			(struct shmifext_color_buffer*) vs->vinf.text.handle;

		if (buf)
			arcan_shmifext_free_color(conn, buf);
		else
			env->delete_textures(1, &vs->vinf.text.glid);

		vs->vinf.text.handle = 0;
		vs->vinf.text.glid = 0;

		return true;
	}

/* this will give a color buffer that is suitable for FBO and sharing */
	struct shmifext_color_buffer* buf =
		malloc(sizeof(struct shmifext_color_buffer));

	if (!arcan_shmifext_alloc_color(conn, buf)){
		agp_empty_vstore(vs, vs->w, vs->h);
		free(buf);
		return true;
	}

/* remember the metadata for free later */
	vs->vinf.text.glid = buf->id.gl;
	vs->vinf.text.handle = (uintptr_t) buf;

	return true;
}

enum shmifext_setup_status arcan_shmifext_setup(
	struct arcan_shmif_cont* con,
	struct arcan_shmifext_setup arg)
{
	struct shmif_ext_hidden_int* ctx = con->privext->internal;
	enum shmifext_setup_status res;

	if (ctx && ctx->display)
		return SHMIFEXT_ALREADY_SETUP;

/* don't do anything with this for the time being */
	if (arg.no_context){
		con->privext->internal = malloc(sizeof(struct shmif_ext_hidden_int));
		if (!con->privext->internal)
			return SHMIFEXT_NO_API;

		memset(con->privext->internal, '\0', sizeof(struct shmif_ext_hidden_int));
		con->privext->internal->display = (EGLDisplay)((void*)SHARED_DISPLAY);
		return SHMIFEXT_OK;
	}

/* don't use the agp_eglenv here as it has not been setup yet */
	switch (arg.api){
	case API_OPENGL:
		if (!((ctx && ctx->display) || eglBindAPI(EGL_OPENGL_API)))
			return SHMIFEXT_NO_API;
	break;
	case API_GLES:
		if (!((ctx && ctx->display) || eglBindAPI(EGL_OPENGL_ES_API)))
			return SHMIFEXT_NO_API;
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
	if (!arcan_shmifext_egl(con, &display, lookup, NULL))
		return SHMIFEXT_NO_DISPLAY;

	ctx = con->privext->internal;

	if (agp_eglenv.get_platform_display){
		ctx->display = agp_eglenv.get_platform_display(
			EGL_PLATFORM_GBM_KHR, (void*) display, NULL);
	}
	else
		ctx->display = agp_eglenv.get_display((EGLNativeDisplayType) display);

	if (!ctx->display)
		return SHMIFEXT_NO_DISPLAY;

	if (!agp_eglenv.initialize(ctx->display, NULL, NULL))
		return SHMIFEXT_NO_EGL;

/* this needs the context to be initialized */
	map_eglext_functions(&agp_eglenv, lookup_fenv, NULL);

/* we have egl and a display, build a config/context and set it as the
 * current default context for this shmif-connection */
	ctx->managed = true;
	unsigned ind;
	res = add_context(ctx, &arg, &ind);

	if (SHMIFEXT_OK != res)
		return res;

	arcan_shmifext_swap_context(con, ind);
	ctx->surface = EGL_NO_SURFACE;
	active_context = con;

/*
 * this is likely not the best way to keep it if we try to run multiple
 * segments on different GPUs with different GL implementations, if/when
 * that becomes a problem, move to a context specific one - should mostly
 * be to resolve the fenv on first make-curreny
 */
	if (!agp_fenv.draw_buffer){
		agp_glinit_fenv(&agp_fenv, lookup_fenv, NULL);
		agp_setenv(&agp_fenv);
	}

/* the built-in render targets act as a framebuffer object container that can
 * also mutate into having a swapchain, with DOUBLEBUFFER that happens
 * immediately */
	if (arg.builtin_fbo){
		ctx->buf = (struct agp_vstore){
			.txmapped = TXSTATE_TEX2D,
				.w = con->w,
				.h = con->h
		};

		ctx->rtgt = agp_setup_rendertarget(
			&ctx->buf, RENDERTARGET_COLOR_DEPTH_STENCIL);

		agp_rendertarget_allocator(ctx->rtgt, scanout_alloc, con);
	}

	arcan_shmifext_make_current(con);
	return SHMIFEXT_OK;
}

bool arcan_shmifext_drop(struct arcan_shmif_cont* con)
{
	if (!con ||
		!con->privext || !con->privext->internal ||
		!con->privext->internal->display ||
		(uintptr_t)con->privext->internal->display == SHARED_DISPLAY
	)
		return false;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;

	agp_eglenv.make_current(ctx->display,
		EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);

	for (size_t i = 0; i < 64 && ctx->ctx_alloc; i++){
		if ((ctx->ctx_alloc & ((1<<i)))){
			ctx->ctx_alloc &= ~(1 << i);
			agp_eglenv.destroy_context(ctx->display, ctx->alt_contexts[i]);
			ctx->alt_contexts[i] = NULL;
		}
	}

	ctx->context = NULL;
	gbm_drop(con);
	return true;
}

bool arcan_shmifext_drop_context(struct arcan_shmif_cont* con)
{
	if (!con || !con->privext || !con->privext->internal ||
		!con->privext->internal->display)
		return false;

/* might be a different context in TLS, so switch first */
	struct arcan_shmif_cont* old = active_context;
	if (active_context != con)
		arcan_shmifext_make_current(con);

	struct shmif_ext_hidden_int* ctx = con->privext->internal;

/* it's the caller's responsibility to switch in a new ctx, but right
 * now, we're in a state where managed = true, though there's no context */
	if (ctx->context){
		agp_eglenv.make_current(ctx->display,
			EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
		agp_eglenv.destroy_context(ctx->display, ctx->context);
		ctx->context = NULL;
	}

/* and restore */
	arcan_shmifext_make_current(old);
	return true;
}

static void authenticate_fd(struct arcan_shmif_cont* con, int fd)
{
/* is it a render node or a real device? */
	struct stat nodestat;
	if (0 == fstat(fd, &nodestat) && !(nodestat.st_rdev & 0x80)){
		unsigned magic;
		drmGetMagic(fd, &magic);
		atomic_store(&con->addr->vpts, magic);
		con->hints |= SHMIF_RHINT_AUTH_TOK;
		arcan_shmif_resize(con, con->w, con->h);
		con->hints &= ~SHMIF_RHINT_AUTH_TOK;
		magic = atomic_load(&con->addr->vpts);
	}
}

void arcan_shmifext_bufferfail(struct arcan_shmif_cont* con, bool st)
{
	if (!con || !con->privext || !con->privext->internal)
		return;

	con->privext->state_fl |= STATE_NOACCEL *
		(getenv("ARCAN_VIDEO_NO_FDPASS") ? 1 : st);
}

int arcan_shmifext_dev(struct arcan_shmif_cont* con,
	uintptr_t* dev, bool clone)
{
	if (!con || !con->privext || !con->privext->internal)
		return -1;

	struct shmif_ext_hidden_int* I = con->privext->internal;

	if (dev)
		*dev = (uintptr_t)(void*)I->dev;

/* see the note about device_path in shmifext_egl */
	if (clone){
		int fd = -1;
		if (I->device_path){
			fd = open(I->device_path, O_RDWR);
		}

		if (-1 == fd)
			arcan_shmif_dupfd(con->privext->active_fd, -1, true);

/* this can soon be removed entirely, the cardN path is dying */
		if (-1 != fd)
			authenticate_fd(con, fd);

		return fd;
	}
	else
	  return con->privext->active_fd;
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
	void** display, void*(*lookup)(void*, const char*), void* tag)
{
	if (!lookup || !con || !con->addr || !display)
		return false;

	int dfd = -1;

/* case for switching to another node, we're still missing a way to extract the
 * 'real' library paths to the GL implementation and to the EGL implementation
 * for dynamic- GPU switching */
	if (con->privext->pending_fd != -1){
		if (-1 != con->privext->active_fd){
			close(con->privext->active_fd);
			con->privext->active_fd = -1;
			gbm_drop(con);
		}
		dfd = con->privext->pending_fd;
		con->privext->pending_fd = -1;
	}
	else if (-1 != con->privext->active_fd){
		dfd = con->privext->active_fd;
	}

/*
 * Or first setup without a pending_fd, with the preroll state added it is
 * likely that we no longer need this - if we don't get a handle in the preroll
 * state we don't have extended graphics.
 *
 * There is a caveat to this in that some drivers expect the render node itself
 * to not be shared onwards to other processes. This is relevant in bridging
 * cases like for X11 and Wayland.
 *
 * In particular, AMDGPU may get triggered by this and fail on context creation
 * in the 3rd party client - bailing with a cryptic message like "failed to
 * create context".
 *
 * Thus, for the 'clone' case we need to remember the backing path and open a
 * new node rather than trying to dup the descriptor.
 */
	const char* nodestr = "/dev/dri/renderD128";
	if (!con->privext->internal){
		if (getenv("ARCAN_RENDER_NODE"))
			nodestr = getenv("ARCAN_RENDER_NODE");
		dfd = open(nodestr, O_RDWR | O_CLOEXEC);
	}
/* mode-switch is no-op in init here, but we still may need
 * to update function pointers due to possible context changes */

	map_egl_functions(&agp_eglenv, lookup_fenv, tag);
	if (!agp_eglenv.initialize)
		return false;

	if (-1 == dfd)
		return false;

/* special cleanup to deal with gbm_device abstraction */
	con->privext->cleanup = gbm_drop;
	con->privext->active_fd = dfd;
	authenticate_fd(con, dfd);

/* finally open device */
	if (!con->privext->internal){
		con->privext->internal = malloc(sizeof(struct shmif_ext_hidden_int));
		if (!con->privext->internal){
			gbm_drop(con);
			return false;
		}

/* The 'no-fdpass' is forcing a manual readback as a way of probing if the
 * rather fragile cross-process GPU sharing breaks. Normally this comes as
 * an event that dynamically changes the same state_fl. This causes the
 * signalling to revert to GPU-readback into SHM as a way of still getting
 * the data across. */
		memset(con->privext->internal, '\0', sizeof(struct shmif_ext_hidden_int));
		con->privext->state_fl = STATE_NOACCEL * (getenv("ARCAN_VIDEO_NO_FDPASS") ? 1 : 0);
		con->privext->internal->device_path = strdup(nodestr);

		if (NULL == (con->privext->internal->dev = gbm_create_device(dfd))){
			gbm_drop(con);
			return false;
		}
	}

/* this needs the context to be initialized */
	map_eglext_functions(&agp_eglenv, lookup_fenv, tag);
	if (!agp_eglenv.destroy_image){
		gbm_drop(con);
		return false;
	}

	*display = (void*) (con->privext->internal->dev);
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

void arcan_shmifext_bind(struct arcan_shmif_cont* con)
{
/* need to resize both potential rendertarget destinations */
	if (!con || !con->privext || !con->privext->internal ||
		!con->privext->internal->display)
		return;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;
	if (active_context != con){
		arcan_shmifext_make_current(con);
	}

/* with an internally managed rendertarget / swapchain, we try to resize on
 * bind, this earlies out of the dimensions are already the same */
	if (ctx->rtgt){
		agp_resize_rendertarget(ctx->rtgt, con->w, con->h);
		agp_activate_rendertarget(ctx->rtgt);
	}
}

void arcan_shmifext_free_color(
	struct arcan_shmif_cont* con, struct shmifext_color_buffer* in)
{
	if (!con || !in || !in->id.gl)
		return;

	EGLDisplay* dpy = con->privext->internal->display;

	struct agp_fenv* fenv = arcan_shmifext_getfenv(con);
	arcan_shmifext_make_current(con);

	fenv->delete_textures(1, &in->id.gl);
	in->id.gl = 0;

/* need to destroy the gbm-bo and egl image separately */
	agp_eglenv.destroy_image(dpy, in->alloc_tags[1]);
	gbm_bo_destroy(in->alloc_tags[0]);
	in->alloc_tags[0] = NULL;
	in->alloc_tags[1] = NULL;
}

bool arcan_shmifext_alloc_color(
	struct arcan_shmif_cont* con, struct shmifext_color_buffer* out)
{
	struct gbm_bo* bo;
	EGLImage img;
	if (!con || !con->privext || !con->privext->internal)
		return false;

	struct shmif_ext_hidden_int* ext = con->privext->internal;
	struct agp_fenv* fenv = arcan_shmifext_getfenv(con);

/* and now EGL-image into out texture */
	int fmt = DRM_FORMAT_XRGB8888;

	return
		helper_alloc_color(&agp_fenv, &agp_eglenv,
			ext->dev, ext->display, out, con->w, con->h,
			fmt, con->privext->state_fl,
			con->privext->n_modifiers, con->privext->modifiers
		);
}

bool arcan_shmifext_make_current(struct arcan_shmif_cont* con)
{
	if (!con || !con->privext || !con->privext->internal ||
		!con->privext->internal->display)
		return false;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;

	if (active_context != con){
		agp_eglenv.make_current(
			ctx->display, ctx->surface, ctx->surface, ctx->context);
		active_context = con;
	}
	arcan_shmifext_bind(con);

	return true;
}

size_t arcan_shmifext_export_image(
	struct arcan_shmif_cont* con,
	uintptr_t display, uintptr_t tex_id,
	size_t plane_limit, struct shmifext_buffer_plane* planes)
{
	if (!con || !con->addr || !con->privext || !con->privext->internal)
		return 0;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;

/* built-in or provided egl-display? */
	EGLDisplay* dpy = display == 0 ?
		con->privext->internal->display : (EGLDisplay*) display;

/* texture/FBO to egl image */
	EGLImage newimg = agp_eglenv.create_image(
		dpy,
		con->privext->internal->context,
		EGL_GL_TEXTURE_2D_KHR,
		(EGLClientBuffer)(tex_id), NULL
	);

/* legacy - single plane / no-modifier version */
	if (!newimg)
		return 0;

/* grab the metadata (number of planes, modifiers, ...) but also cap
 * against both the caller limit (which might come from up high) and
 * to a sanity check 'more than 4 planes is suspicious' */
	int fourcc, nplanes;
	uint64_t modifiers;
	if (!agp_eglenv.query_image_format(dpy, newimg,
		&fourcc, &nplanes, &modifiers) || plane_limit < nplanes || nplanes > 4){
		agp_eglenv.destroy_image(dpy, newimg);
		return 0;
	}

/* bugs experienced with the alpha- channel versions of these that a
 * quick hack is better for the time being */
	if (fourcc == DRM_FORMAT_ARGB8888){
		fourcc = DRM_FORMAT_XRGB8888;
	}

/* now grab the actual dma-buf, and repackage into our planes */
	EGLint strides[4] = {-1, -1, -1, -1};
	EGLint offsets[4] = {0, 0, 0, 0};
	EGLint fds[4] = {-1, -1, -1, -1};

	if (!agp_eglenv.export_dmabuf(dpy, newimg,
		fds, strides, offsets) || strides[0] < 0){
		agp_eglenv.destroy_image(dpy, newimg);
		return 0;
	}

	for (size_t i = 0; i < nplanes; i++){
		planes[i] = (struct shmifext_buffer_plane){
			.fd = fds[i],
			.fence = -1,
			.w = con->w,
			.h = con->h,
			.gbm.format = fourcc,
			.gbm.stride = strides[i],
			.gbm.offset = offsets[i],
			.gbm.mod_hi = (modifiers >> 32),
			.gbm.mod_lo = (modifiers & 0xffffffff)
		};
	}

	agp_eglenv.destroy_image(dpy, newimg);
	return nplanes;
}

/* legacy interface - only support one plane so wrap it around the new */
bool arcan_shmifext_gltex_handle(
	struct arcan_shmif_cont* cont,
	uintptr_t display, uintptr_t tex_id,
 int* dhandle, size_t* dstride, int* dfmt)
{
	struct shmifext_buffer_plane plane = {};

	size_t n_planes =
		arcan_shmifext_export_image(cont, display, tex_id, 1, &plane);

	*dfmt = plane.gbm.format;
	*dstride = plane.gbm.stride;
	*dhandle = plane.fd;

	return true;
}

int arcan_shmifext_isext(struct arcan_shmif_cont* con)
{
	if (!con || !con->privext || !con->privext->internal)
		return 0;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;
	if (!ctx->display)
		return 0;

	if (con->privext->state_fl == STATE_NOACCEL)
		return 2;
	else
		return 1;
}

size_t arcan_shmifext_signal_planes(
	struct arcan_shmif_cont* c,
	int mask,
	size_t n_planes,
	struct shmifext_buffer_plane* planes
)
{
	if (!c || !n_planes)
		return 0;

/* missing - we need to track which vbuffers that are locked using
 * the vmask and then on stepframe check when they are released so
 * that we can release them back to the caller */

	struct arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(BUFFERSTREAM)
	};

	for (size_t i = 0; i < n_planes; i++){
/* missing - another edge case is that when we transfer one plane but run out
 * of descriptor slots on the server-side, basically the sanest case then is to
 * simply fake-inject an event with a buffer-fail so that the rest of the setup
 * falls back to readback and wait for a reset or device-hint to rebuild */
		if (!arcan_pushhandle(planes[i].fd, c->epipe))
			return i;
		close(planes[i].fd);

/* missing - the gpuid should be set based on what gpu the context is assigned
 * to based on initial/device-hint - this is to make sure that we don't commit
 * buffers to something that was not intended (particularly during hand-over)
 * */
		ev.ext.bstream.stride = planes[i].gbm.stride;
		ev.ext.bstream.format = planes[i].gbm.format;
		ev.ext.bstream.mod_lo = planes[i].gbm.mod_lo;
		ev.ext.bstream.mod_hi = planes[i].gbm.mod_hi;
		ev.ext.bstream.offset = planes[i].gbm.offset;
		ev.ext.bstream.width  = planes[i].w;
		ev.ext.bstream.height = planes[i].h;
		ev.ext.bstream.left = n_planes - i - 1;

		arcan_shmif_enqueue(c, &ev);
	}

	arcan_shmif_signal(c, mask);
	return n_planes;
}

int arcan_shmifext_signal(struct arcan_shmif_cont* con,
	uintptr_t display, int mask, uintptr_t tex_id, ...)
{
	if (!con || !con->addr || !con->privext || !con->privext->internal)
		return -1;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;

	EGLDisplay* dpy;
	if (display){
		dpy = (EGLDisplay)((void*) display);
	}
	else if ((uintptr_t)ctx->display == SHARED_DISPLAY && active_context){
		dpy = active_context->privext->internal->display;
	}
	else
		dpy = ctx->display;

	if (!dpy)
		return -1;

/* swap and forward the state of the builtin- rendertarget or the latest
 * imported buffer depending on how the context was configured */
	if (tex_id == SHMIFEXT_BUILTIN){
		if (!ctx->rtgt)
			return -1;

		agp_activate_rendertarget(NULL);
		glFinish();

		bool swap;
		struct agp_vstore* vs = agp_rendertarget_swap(ctx->rtgt, &swap);
		if (!swap)
			return INT_MAX;

		tex_id = vs->vinf.text.glid;
	}

/* begin extraction of the currently rendered-to buffer */
	size_t nplanes;
	struct shmifext_buffer_plane planes[4];

	if (con->privext->state_fl & STATE_NOACCEL ||
			!(nplanes=arcan_shmifext_export_image(con, display, tex_id, 4, planes)))
		goto fallback;

	arcan_shmifext_signal_planes(con, mask, nplanes, planes);
	return INT_MAX;


/* handle-passing is disabled or broken, instead perform a manual readback into
 * the shared memory segment and signal like a normal buffer */
fallback:
	if (1){
		struct agp_vstore vstore = {
			.w = con->w,
			.h = con->h,
			.txmapped = TXSTATE_TEX2D,
			.vinf.text = {
				.glid = tex_id,
				.raw = (void*) con->vidp
			},
		};
		agp_readback_synchronous(&vstore);
	}

	unsigned res = arcan_shmif_signal(con, mask);
	return res > INT_MAX ? INT_MAX : res;
}
