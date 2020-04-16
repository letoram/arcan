#define WANT_ARCAN_SHMIF_HELPER
#define AGP_ENABLE_UNPURE

#include "../arcan_shmif.h"
#include "../shmif_privext.h"
#include "agp/glfun.h"

#include <fcntl.h>
#include <dlfcn.h>

#include <OpenGL/OpenGL.h>
#include <OpenGL/GL.h>

struct shmif_ext_hidden_int {
	struct agp_rendertarget* rtgt;
	struct agp_vstore vstore;
	struct agp_fenv fenv;
	CGLContextObj context;
};

struct arcan_shmifext_setup arcan_shmifext_defaults(
	struct arcan_shmif_cont* con)
{
	return (struct arcan_shmifext_setup){
		.red = 8, .green = 8, .blue = 8, .depth = 16,
		.api = API_OPENGL,
		.builtin_fbo = true,
		.major = 2, .minor = 1
	};
}

static void* lookup_fenv(void* tag, const char* sym, bool req)
{
	return arcan_shmifext_lookup(NULL, sym);
}

struct agp_fenv* arcan_shmifext_getfenv(struct arcan_shmif_cont* con)
{
	if (!con || !con->privext || !con->privext->internal)
		return false;

	struct shmif_ext_hidden_int* in = con->privext->internal;
	return &in->fenv;
}

int arcan_shmifext_isext(struct arcan_shmif_cont* con)
{
	if (con && con->privext && con->privext->internal)
		return 2; /* we don't support handle passing via IOSurfaces yet */
	return 0;
}

bool arcan_shmifext_drop(struct arcan_shmif_cont* con)
{
	if (!con || !con->privext || !con->privext->internal)
		return false;

	struct shmif_ext_hidden_int* in = con->privext->internal;
	con->privext->internal = NULL;

	if (in->rtgt){
		agp_drop_rendertarget(in->rtgt);
		agp_drop_vstore(&in->vstore);
	}
  CGLDestroyContext(in->context);

	free(in);
	return true;
}

bool arcan_shmifext_drop_context(struct arcan_shmif_cont* con)
{
	return arcan_shmifext_drop(con);
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
	CGLPixelFormatObj pix;
	CGLError errc;
	GLint num;

	CGLPixelFormatAttribute attributes[] = {
		kCGLPFAAccelerated,
		kCGLPFAOpenGLProfile,
		(CGLPixelFormatAttribute) kCGLOGLPVersion_Legacy,
		(CGLPixelFormatAttribute) 0,
		kCGLPFAColorSize, 24,
		kCGLPFADepthSize, arg.depth,
		(CGLPixelFormatAttribute) 0, /* supersample */
		(CGLPixelFormatAttribute) 0,
	};

	if (arg.supersample)
		attributes[8] = kCGLPFASupersample;

	switch(arg.api){
	case API_OPENGL:
	break;
	default:
		return SHMIFEXT_NO_API;
	break;
	}

	if (arg.major == 3){
		attributes[2] = (CGLPixelFormatAttribute) kCGLOGLPVersion_3_2_Core;
	}
	else if (arg.major > 3){
		return SHMIFEXT_NO_API;
	}

	errc = CGLChoosePixelFormat( attributes, &pix, &num );
	if (!pix)
		return SHMIFEXT_NO_CONFIG;

	struct shmif_ext_hidden_int* ictx = malloc(sizeof(
		struct shmif_ext_hidden_int));

	if (!ictx){
		CGLDestroyPixelFormat(pix);
		return SHMIFEXT_NO_CONFIG;
	}
	memset(ictx, '\0', sizeof(struct shmif_ext_hidden_int));

  errc = CGLCreateContext( pix, NULL, &ictx->context );
	CGLDestroyPixelFormat( pix );
	if (!ictx->context){
		free(ictx);
		return SHMIFEXT_NO_CONTEXT;
	}
  errc = CGLSetCurrentContext(ictx->context);

/*
 * no double buffering,
 * we let the parent transfer process act as the limiting clock.
 */
	GLint si = 0;
	CGLSetParameter(ictx->context, kCGLCPSwapInterval, &si);

	agp_glinit_fenv(&ictx->fenv, lookup_fenv, NULL);

	if (arg.builtin_fbo){
		agp_empty_vstore(&ictx->vstore, con->w, con->h);
		ictx->rtgt = agp_setup_rendertarget(
			&ictx->vstore, arg.depth > 0 ? RENDERTARGET_COLOR_DEPTH_STENCIL :
				RENDERTARGET_COLOR);
	}
	con->privext->internal = ictx;
	return SHMIFEXT_OK;
}

bool arcan_shmifext_make_current(struct arcan_shmif_cont* con)
{
	if (!con || !con->addr || !con->privext || !con->privext->internal)
		return false;

	struct shmif_ext_hidden_int* ctx = con->privext->internal;
	agp_setenv(&ctx->fenv);
	CGLSetCurrentContext(con->privext->internal->context);
	if (ctx->rtgt){
		if (ctx->vstore.w != con->w || ctx->vstore.h != con->h){
			agp_activate_rendertarget(NULL);
			agp_resize_rendertarget(ctx->rtgt, con->w, con->h);
		}
		agp_activate_rendertarget(ctx->rtgt);
	}

	return true;
}

bool arcan_shmifext_gl_handles(struct arcan_shmif_cont* con,
	uintptr_t* frame, uintptr_t* color, uintptr_t* depth)
{
	if (!con || !con->privext || !con->privext->internal ||
		!con->privext->internal->rtgt)
		return false;

	agp_rendertarget_ids(con->privext->internal->rtgt, frame, color, depth);
	return true;
}

bool arcan_shmifext_egl_meta(struct arcan_shmif_cont* con,
	uintptr_t* display, uintptr_t* surface, uintptr_t* context)
{
	if (!con || !con->addr || !con->privext || !con->privext->internal)
		return false;

	if (context)
		*context = (uintptr_t) con->privext->internal->context;

	if (display)
		*display = 0;

	if (surface)
		*surface = 0;

	return true;
}

bool arcan_shmifext_gltex_handle(struct arcan_shmif_cont* con,
   uintptr_t display, uintptr_t tex_id,
	 int* dhandle, size_t* dstride, int* dfmt)
{
	return false;
}

int arcan_shmifext_dev(struct arcan_shmif_cont* con,
	uintptr_t* dev, bool clone)
{
	if (dev)
		*dev = 0;

	return -1;
}

void arcan_shmifext_bufferfail(struct arcan_shmif_cont* cont, bool fl)
{
}

void* arcan_shmifext_lookup(
	struct arcan_shmif_cont* con, const char* sym)
{
	static void* dlh = NULL;
  if (NULL == dlh)
    dlh = dlopen("/System/Library/Frameworks/"
			"OpenGL.framework/Versions/Current/OpenGL", RTLD_LAZY);

  return dlh ? dlsym(dlh, sym) : NULL;
}

bool arcan_shmifext_egl(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag)
{
	return false;
}

bool arcan_shmifext_vk(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag)
{
	return false;
}

int arcan_shmifext_signal(struct arcan_shmif_cont* con,
	uintptr_t display, int mask, uintptr_t tex_id, ...)
{
	if (!con || !con->addr || !con->privext || !con->privext->internal)
		return -1;
	struct shmif_ext_hidden_int* ctx = con->privext->internal;

	if (tex_id == SHMIFEXT_BUILTIN)
		tex_id = ctx->vstore.vinf.text.glid;

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

/*
 * workaround for some namespace pollution
 */
#include <mach/mach_time.h>

bool platform_video_map_handle(
	struct agp_vstore* dst, int64_t handle)
{
	return false;
}

void arcan_warning(const char* msg, ...)
{
}

void arcan_fatal(const char* msg, ...)
{
}

unsigned long long int arcan_timemillis()
{
	uint64_t time = mach_absolute_time();
	static double sf;

	if (!sf){
		mach_timebase_info_data_t info;
		kern_return_t ret = mach_timebase_info(&info);
		if (ret == 0)
			sf = (double)info.numer / (double)info.denom;
		else{
			sf = 1.0;
		}
	}
	return ( (double)time * sf) / 1000000;
}


