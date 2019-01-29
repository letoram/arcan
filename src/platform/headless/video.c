/*
 * Copyright 2019, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: The headless platform video implementation, uses egl in a
 * displayless configuration to allow local processing for testing,
 * verification and so on, with the option of exposing the default output via
 * the encode frameserver.
 */
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <unistd.h>
#include <dlfcn.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/types.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_shmif.h"
#include "arcan_event.h"
#include "arcan_audio.h"
#include "arcan_frameserver.h"
#include "arcan_conductor.h"

#include "../platform.h"

#define EGL_EGLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES
#define MESA_EGL_NO_X11_HEADERS
#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <drm.h>
#include <drm_fourcc.h>
#include <xf86drm.h>
#include <gbm.h>

static struct {
	size_t width;
	size_t height;
	struct arcan_frameserver* outctx;
	int deadline;

	struct {
		EGLDisplay disp;
		EGLContext ctx;
		EGLSurface surf;
		EGLConfig cfg;
		EGLNativeWindowType wnd;
		struct gbm_device* gbmdev;
	} egl;

	arcan_vobj_id mapped;
} global = {
	.deadline = 13
};

static char* envopts[] = {
	NULL
};

static void spawn_encode_output()
{
/*
 * Terminate a current / pending connection if one can be found
 */
	if (global.outctx){
		arcan_frameserver_free(global.outctx);
		global.outctx = NULL;
	}

/*
 * Build an 'encode' rendertarget with one VID that matches whatever is mapped
 * to the default output. This has a big caveat in that we currently don't have
 * a mechanism to block the Lua layer from finding and modifying it. As we move
 * more towards using shmif for internal separation (decode etc.)
 *
 * The corresponding lua code would be:
 * dvid = alloc_surface(w, h)
 * interim = null_surface(w, h)
 * show_image(interim)
 * image_sharestorage(mapped_vid, interim)
 * define_recordtarget(dvid,
 *     "", enc_arg, {interim}, {}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE,
 *     -1, function(source, status)
 *         end
 * )
 *
 * If this is mapped, we treat the recordtarget synch as 'vsynch' for the
 * platform, otherwise we go with a config appropriate one
 */
	uintptr_t tag;
	char* enc_arg;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);
	if (!get_config("encode", 0, &enc_arg, tag))
		return;

/*
 * dvid = alloc_surface
 */
	arcan_vobj_id dst;
	arcan_vobject* vobj = arcan_video_newvobject(&dst);
	if (!vobj){
		arcan_warning("(headless) couldn't allocate encode- storage\n");
		return;
	}

	struct agp_vstore* ds = vobj->vstore;
	agp_empty_vstoreext(ds, global.width, global.heightm 1);
	ds->origw = global.width;
	ds->origh = global.height;
	ds->order = 0;
	ds->blendmode = BLEND_NORMAL;
	arcan_vint_attachobject(dst);

/*
 * interim = null_surface
 */
	arcan_vobj_id cont = arcan_video_nullobject(global.width, global.height, 1);
	if (ARCAN_EID == cont){
		arcan_warning("(headless) couldn't allocate proxy object\n");
		arcan_video_deleteobject(dst);
		return;
	}

/*
 * show_image
 * image_sharestorage
 */
	arcan_video_shareglstore(ARCAN_VIDEO_WORLDID, cont);

/*
 * define_recordtarget
 */
	if (ARCAN_OK != arcan_video_setuprendertarget(
		dst, -1, -1, RENDERTARGET_NOSCALE, RENDERTARGET_COLOR)){
		arcan_warning("(headless) couldn't bind a rendertarget\n");
		arcan_video_deleteobject(cont);
		arcan_video_deleteobject(dst);
		return;
	}

/*
	struct arcan_strarr arr_argv = {0}, arr_env = {0};
	struct frameserver_envp args = {
		.use_builtin = true,
		.args.builtind.mode = "encode",
		.args.builtin.resource = enc_arg,
		.init_w = g_width,
		.init_h = g_height
	};

	free(enc_arg); */
}

void platform_video_shutdown()
{
}

void platform_video_prepare_external()
{
}

void platform_video_restore_external()
{
}
bool platform_video_display_edid(
	platform_display_id did, char** out, size_t* sz)
{
	*out = NULL;
	*sz = 0;
	return false;
}

enum dpms_state platform_video_dpms(
	platform_display_id disp, enum dpms_state state)
{
	return ADPMS_IGNORE;
}

void platform_video_recovery()
{
}

bool platform_video_set_display_gamma(platform_display_id did,
	size_t n_ramps, uint16_t* r, uint16_t* g, uint16_t* b)
{
	return false;
}

bool platform_video_get_display_gamma(platform_display_id did,
	size_t* n_ramps, uint16_t** outb)
{
	return false;
}

void* platform_video_gfxsym(const char* sym)
{
	return dlsym(RTLD_DEFAULT, sym);
}

void platform_video_minimize()
{
}

void platform_video_reset(int id, int swap)
{
}

bool platform_video_specify_mode(platform_display_id disp, struct monitor_mode mode)
{
	return false;
}

void platform_video_synch(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

/*
 * normal refresh cycle, then leave the next possible deadline to the conductor
 */
	size_t nd;
	arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );

/*
 * Fixme: wait for encode out synch and yield in the meanwhile
 */
	if (global.outctx){
		arcan_warning("encode stage missing\n");
	}
	else
		arcan_conductor_fakesynch(global.deadline);

	if (post)
		post();
}

bool platform_video_auth(int cardn, unsigned token)
{
	return false;
}

int platform_video_cardhandle(int cardn,
		int* buffer_method, size_t* metadata_sz, uint8_t** metadata)
{
	return -1;
}

const char** platform_video_envopts()
{
	return (const char**) envopts;
}

void platform_video_query_displays()
{
}

size_t platform_video_displays(platform_display_id* dids, size_t* lim)
{
	if (dids && lim && *lim > 0){
		dids[0] = 0;
	}

	if (lim)
		*lim = 1;

	return 1;
}

bool platform_video_map_handle(struct agp_vstore* dst, int64_t handle)
{
	return false;
}

bool platform_video_set_mode(platform_display_id disp, platform_mode_id mode)
{
	return disp == 0 && mode == 0;
}

struct monitor_mode platform_video_dimensions()
{
	return (struct monitor_mode){
		.width = global.width,
		.height = global.height
	};
}

struct monitor_mode* platform_video_query_modes(
	platform_display_id id, size_t* count)
{
	static struct monitor_mode mode = {};
	mode.width  = global.width;
	mode.height = global.height;
	mode.depth  = sizeof(av_pixel) * 8;
	mode.refresh = 60; /* should be queried */

	*count = 1;
	return &mode;
}

bool platform_video_map_display(
	arcan_vobj_id id, platform_display_id disp, enum blitting_hint hint)
{
/* FIXME: update the recordtarget output to match the new obj- */
	if (disp != 0)
		return false;

/* FIXME: modify the recordtarget interim- object to match */

	return true;
}

const char* platform_video_capstr()
{
	return "skeleton driver, no capabilities";
}

void platform_video_preinit()
{
}

bool platform_video_init(uint16_t width,
	uint16_t height, uint8_t bpp, bool fs, bool frames, const char* capt)
{
	global.width = width;
	global.height = height;

	const EGLint attribs[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
		EGL_RED_SIZE, 8,
		EGL_BLUE_SIZE, 8,
		EGL_ALPHA_SIZE, 8,
		EGL_DEPTH_SIZE, 16,
		EGL_NONE
	};

/* Normal EGL progression:
 * API -> Display -> Configuration -> Context */
	bool gles = false;
	if (strcmp(agp_ident(), "OPENGL21") == 0){
		if (!eglBindAPI(EGL_OPENGL_API)){
			arcan_warning("(headless) couldn't bind openGL API\n");
			return false;
		}
	}
	else if (strcmp(agp_ident(), "GLES3") == 0){
		if (!eglBindAPI(EGL_OPENGL_ES_API)){
			arcan_warning("(headless) couldn't bind gles- API\n");
			return false;
		}
		gles = true;
	}
	else {
		arcan_fatal("unhandled agp platform: %s\n", agp_ident());
		return false;
	}

	PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display =
		(PFNEGLGETPLATFORMDISPLAYEXTPROC)
		eglGetProcAddress("eglGetPlatformDisplayEXT");

	uintptr_t tag;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);

/* this is not right for nvidia, and would possibly pick nouveau even in the
 * presence of the binary driver, we have the same issue with streams */
	if (get_platform_display){
		char* node;
		int devfd = -1;

/* let the user control which specific render node, since we "don't"
 * have a display server to connect to we don't really have any way
 * of knowing which one to use */
		if (get_config("video_device", 0, &node, tag)){
			devfd = open(node, O_RDWR | O_CLOEXEC);
			free(node);
		}

		if (-1 == devfd){
			devfd = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
		}

/* the render node / device could be open, start with gbm, this might
 * trigger the nouveau problem above */
		if (-1 != devfd){
			global.egl.gbmdev = gbm_create_device(devfd);
			if (global.egl.gbmdev){
				global.egl.disp = get_platform_display(
					EGL_PLATFORM_GBM_KHR, (void*) global.egl.gbmdev, NULL);
			}
		}
	}
/* if we don't have the option to specify a platform display, just
 * go with whatever the default display happens to be */
	if (!global.egl.disp)
		global.egl.disp = eglGetDisplay((EGLNativeDisplayType) NULL);

	EGLint major, minor;
	if (!eglInitialize(global.egl.disp, &major, &minor)){
		arcan_warning("(headless) couldn't initialize EGL\n");
		return false;
	}

	EGLint nc;
	if (!eglGetConfigs(global.egl.disp, NULL, 0, &nc) || 0 == nc){
		arcan_warning("(headless) no valid EGL configuration\n");
		return false;
	}

	if (!eglChooseConfig(global.egl.disp, attribs, &global.egl.cfg, 1, &nc)){
		arcan_warning("(headless) couldn't pick a suitable EGL configuration\n");
		return false;
	}

/*
 * Default is ~75Hz (no real need to be very precise, but % logic clock) Then
 * let user override. This will only be effective if we don't tie the output to
 * the encode/remoting stage.
 */
	char* node;
	if (get_config("video_refresh", 0, &node, tag)){
		float hz = strtoul("node", NULL, 10);
		if (hz)
			global.deadline = 1.0 / hz;
		free(node);
	}

	EGLint cas[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_NONE, EGL_NONE,
		EGL_NONE, EGL_NONE,
		EGL_NONE, EGL_NONE,
		EGL_NONE, EGL_NONE,
		EGL_NONE
	};

	int ofs = 2;
	if (gles){
		cas[ofs++] = EGL_CONTEXT_MAJOR_VERSION_KHR;
		cas[ofs++] = 3;
		cas[ofs++] = EGL_CONTEXT_MINOR_VERSION_KHR;
		cas[ofs++] = 0;
	}

	global.egl.ctx =
		eglCreateContext(global.egl.disp, global.egl.cfg, NULL, cas);

	if (!global.egl.ctx)
		return false;

/*
 * Options:
 *  EGL_KHR_Surfaceless_Context
 *  Pbuffer
 */

	eglMakeCurrent(
		global.egl.disp, EGL_NO_SURFACE, EGL_NO_SURFACE, global.egl.ctx);

	spawn_encode_output();

	return true;
}
