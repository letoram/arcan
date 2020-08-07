/*
 * Copyright 2016-2019, Björn Ståhl
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

#include <drm.h>
#include <drm_fourcc.h>
#include <xf86drm.h>
#include <gbm.h>
#include <stdatomic.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

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
	struct agp_rendertarget* rtgt;
	struct agp_vstore buf;

/* we buffer- queue the cleanup of these images (rtgt is already swapchain) */
	struct {
		EGLImage image;
		int dmabuf;
	} images[3];
	size_t image_index;

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

static void free_image_index(
	EGLDisplay* dpy, struct shmif_ext_hidden_int* in, size_t i)
{
	if (!in->images[i].image)
		return;

	agp_eglenv.destroy_image(dpy, in->images[i].image);
	in->images[i].image = NULL;
	close(in->images[i].dmabuf);
	in->images[i].dmabuf = -1;
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
		for (size_t i = 0; i < COUNT_OF(in->images); i++){
			free_image_index(in->display, in, i);
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
	}

	free(con->privext->internal);
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

static int dma_fd_constants[] = {
	EGL_DMA_BUF_PLANE0_FD_EXT,
	EGL_DMA_BUF_PLANE1_FD_EXT,
	EGL_DMA_BUF_PLANE2_FD_EXT,
	EGL_DMA_BUF_PLANE3_FD_EXT
};

static int dma_offset_constants[] = {
	EGL_DMA_BUF_PLANE0_OFFSET_EXT,
	EGL_DMA_BUF_PLANE1_OFFSET_EXT,
	EGL_DMA_BUF_PLANE2_OFFSET_EXT,
	EGL_DMA_BUF_PLANE3_OFFSET_EXT
};

static int dma_pitch_constants[] = {
	EGL_DMA_BUF_PLANE0_PITCH_EXT,
	EGL_DMA_BUF_PLANE1_PITCH_EXT,
	EGL_DMA_BUF_PLANE2_PITCH_EXT,
	EGL_DMA_BUF_PLANE3_PITCH_EXT
};

static int dma_mod_constants[] = {
	EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT,
	EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
	EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT,
	EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT,
	EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT,
	EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT,
	EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT,
	EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT,
};

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

/* only support one for the time being, but the rest of the function is written
 * so that it can import additional planes when vstore- change is through */
	if (n_planes != 1)
		return false;

	struct agp_vstore* vs = &I->buf;

	if (I->rtgt){
		agp_drop_rendertarget(I->rtgt);
		I->rtgt = NULL;
		memset(vs, '\0', sizeof(struct agp_vstore));
	}

	size_t n_attr = 0;
	EGLint attrs[64] = {};
#define ADD_ATTR(X, Y) { attrs[n_attr++] = (X); attrs[n_attr++] = (Y); }
	ADD_ATTR(EGL_WIDTH, planes[0].w);
	ADD_ATTR(EGL_HEIGHT, planes[0].h);
	ADD_ATTR(EGL_LINUX_DRM_FOURCC_EXT, planes[0].gbm.format);

	for (size_t i = 0; i < n_planes; i++){
		ADD_ATTR(dma_fd_constants[i], planes[i].fd);
		ADD_ATTR(dma_offset_constants[i], planes[i].gbm.offset);
		ADD_ATTR(dma_pitch_constants[i], planes[i].gbm.pitch);
		if (planes[i].gbm.modifiers){
			ADD_ATTR(dma_mod_constants[i*2+0], planes[i].gbm.modifiers >> 32);
			ADD_ATTR(dma_mod_constants[i*2+1], planes[i].gbm.modifiers & 0xffffffff);
		}
	}

	ADD_ATTR(EGL_NONE, EGL_NONE);
#undef ADD_ATTR

	EGLImage img = agp_eglenv.create_image(display,
		EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, attrs);

	if (!img)
		return false;

/* eglImage is suposed to dup internally */
	for (size_t i = 0; i < n_planes; i++){
		if (-1 != planes[i].fd){
			close(planes[i].fd);
			planes[i].fd = -1;
		}
	}

/* might have an old eglImage around */
	if (0 != vs->vinf.text.tag){
		agp_eglenv.destroy_image(display, (EGLImageKHR) vs->vinf.text.tag);
	}

	I->buf.w = planes[0].w;
	I->buf.h = planes[0].h;

/* bind eglImage to GLID, and we don't have any filtering for external,
 * also cheat a bit around vstore setup */
	if (!vs->vinf.text.glid){
		agp_fenv.gen_textures(1, &vs->vinf.text.glid);
		agp_fenv.active_texture(GL_TEXTURE0);
		agp_fenv.bind_texture(GL_TEXTURE_2D, vs->vinf.text.glid);
		agp_fenv.tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		agp_fenv.tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		agp_fenv.tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		agp_fenv.tex_param_i(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		vs->txmapped = TXSTATE_TEX2D;
		vs->bpp = sizeof(shmif_pixel);
	}

	agp_activate_vstore(vs);
		agp_eglenv.image_target_texture2D(GL_TEXTURE_2D, img);
	agp_deactivate_vstore(vs);

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
		ctx->rtgt = agp_setup_rendertarget(&ctx->buf,
			RENDERTARGET_DOUBLEBUFFER | RENDERTARGET_COLOR_DEPTH_STENCIL);
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

	if (dev)
		*dev = (uintptr_t) con->privext->internal->dev;

	if (clone){
		int fd = arcan_shmif_dupfd(con->privext->active_fd, -1, true);
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
/* or first setup without a pending_fd, with the preroll state added it is
 * likely that we no longer need this - if we don't get a handle in the preroll
 * state we don't have extended graphics */
	else if (!con->privext->internal){
		const char* nodestr = getenv("ARCAN_RENDER_NODE") ?
			getenv("ARCAN_RENDER_NODE") : "/dev/dri/renderD128";
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

		memset(con->privext->internal, '\0', sizeof(struct shmif_ext_hidden_int));
		con->privext->state_fl = STATE_NOACCEL * (getenv("ARCAN_VIDEO_NO_FDPASS") ? 1 : 0);
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

bool arcan_shmifext_gltex_handle(struct arcan_shmif_cont* con,
   uintptr_t display, uintptr_t tex_id,
	 int* dhandle, size_t* dstride, int* dfmt)
{
	if (!con || !con->addr || !con->privext || !con->privext->internal)
		return -1;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;

	EGLDisplay* dpy = display == 0 ?
		con->privext->internal->display : (EGLDisplay*) display;

/* step buffer, clean / free */
	size_t next_i = (ctx->image_index + 1) % COUNT_OF(ctx->images);
	free_image_index(dpy, ctx, next_i);

	EGLImage newimg = agp_eglenv.create_image(dpy,
		con->privext->internal->context, EGL_GL_TEXTURE_2D_KHR,
		(EGLClientBuffer)(tex_id), NULL
	);

	if (!newimg)
		return false;

	int fourcc, nplanes;
	if (!agp_eglenv.query_image_format(dpy, newimg, &fourcc, &nplanes, NULL)){
		agp_eglenv.destroy_image(dpy, newimg);
		return false;
	}

/* currently unsupported */
	if (nplanes != 1)
		return false;

	EGLint stride;
	if (!agp_eglenv.export_dmabuf(dpy,
		newimg, dhandle, &stride, NULL)|| stride < 0){
		agp_eglenv.destroy_image(dpy, newimg);
		return false;
	}

	*dfmt = fourcc;
	*dstride = stride;
	ctx->images[next_i].image = newimg;
	ctx->images[next_i].dmabuf = *dhandle;
	ctx->image_index = next_i;
	return true;
}

int arcan_shmifext_isext(struct arcan_shmif_cont* con)
{
	return (con && con->privext && con->privext->internal);
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
		if (!ctx->rtgt && ctx->buf.vinf.text.tag){
			tex_id = ctx->buf.vinf.text.glid;
			goto fallback;
		}
		else {
			bool swap;
			tex_id = agp_rendertarget_swap(ctx->rtgt, &swap);
			if (!swap)
				return INT_MAX;
		}
	}

/* begin extraction of the currently rendered-to buffer */
	int fd, fourcc;
	size_t stride;
	if (con->privext->state_fl & STATE_NOACCEL ||
			!arcan_shmifext_gltex_handle(con, display, tex_id, &fd, &stride, &fourcc))
		goto fallback;

	unsigned res = arcan_shmif_signalhandle(con, mask, fd, stride, fourcc);
	return res > INT_MAX ? INT_MAX : res;

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
	res = arcan_shmif_signal(con, mask);
	return res > INT_MAX ? INT_MAX : res;
}
