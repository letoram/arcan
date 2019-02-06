/*
 * Copyright 2019, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: The headless platform video implementation, uses egl in a
 * displayless configuration to allow local processing for testing,
 * verification and so on, with the option of exposing the default output via
 * the encode frameserver.
 */

/*
 * TODO:
 * [ ] deal with frameserver death / relaunch
 * [ ] map_handle should be shared with egl-dri
 * [ ] let DPMS state and map_handle(BADID) reflect in encode-output
 * [ ] "resolution" switch reflect in encode output
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
#include "arcan_event.h"

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
	int deadline;

	struct {
		struct arcan_frameserver* outctx;
		bool check_output;
		bool flip_y;
		bool block;
	} encode;

	struct {
		EGLDisplay disp;
		EGLContext ctx;
		EGLSurface surf;
		EGLConfig cfg;
		EGLNativeWindowType wnd;
		struct gbm_device* gbmdev;
	} egl;

	struct agp_vstore* vstore;
} global = {
	.deadline = 13,
	.encode = {
		.flip_y = true
	}
};

static char* envopts[] = {
	"ARCAN_VIDEO_ENCODE=encode_args",
	"Use encode frameserver as virtual output, see afsrv_encode for format",
	NULL
};

static void spawn_encode_output()
{
/*
 * Terminate a current / pending connection if one can be found
 */
	if (global.encode.outctx){
		arcan_frameserver_free(global.encode.outctx);
		global.encode.outctx = NULL;
	}

/*
 * Get the parameters / options from the config- layer
 */
	uintptr_t tag;
	char* enc_arg;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);
	if (!get_config("video_encode", 0, &enc_arg, tag))
		return;

/*
 * spawn the actual process
 */
	struct frameserver_envp args = {
		.use_builtin = true,
		.custom_feed = 0xfeedface,
		.args.builtin.mode = "encode",
		.args.builtin.resource = enc_arg,
		.init_w = global.width,
		.init_h = global.height
	};
	struct arcan_frameserver* fsrv = platform_launch_fork(&args, 0);
	if (!fsrv){
		arcan_warning("(headless) couldn't spawn afsrv_encode\n");
		return;
	}

	global.encode.outctx = fsrv;
}

void platform_video_shutdown()
{
	if (global.encode.outctx){
		arcan_frameserver_free(global.encode.outctx);
	}
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

/*
 * called as external from the headless input platform
 */
int headless_flush_encode_events()
{
	if (!global.encode.outctx)
		return FRV_NOFRAME;

/* Prevent control_chld from emitting events about the state of the frameserver
 * (it doesn't exist in the lua space) and instead substitute it with the exit
 * request. Run silent so that it can launch with re-attach */
	arcan_event_maskall(arcan_event_defaultctx());
	if (!arcan_frameserver_control_chld(global.encode.outctx)){
		arcan_warning("(headless) output encoder died\n");
		global.encode.outctx = NULL;
		arcan_event_clearmask(arcan_event_defaultctx());
		arcan_event ev = {
			.category = EVENT_SYSTEM,
			.sys.kind = EVENT_SYSTEM_EXIT,
			.sys.errcode = 256 /* EXIT_SILENT */
		};
		arcan_event_enqueue(arcan_event_defaultctx(), &ev);
		return FRV_NOFRAME;
	}
	arcan_event_clearmask(arcan_event_defaultctx());

	TRAMP_GUARD(FRV_NOFRAME, global.encode.outctx);
	arcan_event inev;

/* !arcan_frameserver_control_chld -> _free() -> TERMINATED event */

	while (arcan_event_poll(&global.encode.outctx->inqueue, &inev) > 0){
/* allow IO events to be forwarded as if the encode frameserver was actually
 * an input device (which in the remoting stage it is) */
		if (inev.category == EVENT_IO){
			arcan_event_enqueue(arcan_event_defaultctx(), &inev);
			continue;
		}

		if (inev.category != EVENT_EXTERNAL)
			continue;

		switch (inev.ext.kind){
		default:
		break;
		}
	}

	platform_fsrv_leave();
	return FRV_NOFRAME;
}

static int readback_encode()
{
/* other side is still encoding / synching so don't overwrite the buffer */
	struct arcan_frameserver* out = global.encode.outctx;
	TRAMP_GUARD(0, out);

/* not finished, fake it until we finish */
	if (out->shm.ptr->vready || global.encode.block){
		platform_fsrv_leave();
		return 0;
	}

/* even if the store sizes have changed for some reason, we crop to the smallest */
	agp_activate_rendertarget(NULL);

	struct agp_vstore* vs = global.vstore ? global.vstore : arcan_vint_world();
	size_t row_len = vs->w > out->desc.width ? out->desc.width : vs->w;
	size_t row_sz = row_len * sizeof(av_pixel);
	size_t n_rows = vs->h > out->desc.height ? out->desc.height : vs->h;
	size_t buf_sz = vs->w * vs->h * sizeof(av_pixel);

/* recall, alloc_mem is default FATAL unless flagged otherwise */
	if (buf_sz != vs->vinf.text.s_raw){
		arcan_mem_free(vs->vinf.text.raw);
		vs->vinf.text.s_raw = buf_sz;
		vs->vinf.text.raw = arcan_alloc_mem(vs->vinf.text.s_raw,
			ARCAN_MEM_VBUFFER, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE
		);
	}

/* don't really guarantee color format and coding here when it is
 * non-normal texture2D surfaces (where we statically pick formats
 * to avoid repack). */
	agp_readback_synchronous(vs);

	bool in_dirty = false;
	size_t x1 = row_len - 1;
	size_t x2 = 0, y1 = 0, y2 = 0;

	shmif_pixel* dst = out->vbufs[0];
	shmif_pixel* src = vs->vinf.text.raw;

	size_t dst_row = n_rows - 1;
	int dst_step = -1;

	if (!global.encode.flip_y){
		dst_row = 0;
		dst_step = 1;
	}

	for (size_t row = 0; row < n_rows; row++, dst_row += dst_step){
		av_pixel acc = 0;

		for (size_t px = 0; px < row_len; px++){
			av_pixel a = src[row     * vs->w           + px];
			av_pixel b = dst[dst_row * out->desc.width + px];
			acc = acc | (a ^ b);
		}

		if (!acc)
			continue;

		if (!in_dirty){
			in_dirty = true;
			y1 = dst_row;
			y2 = dst_row;
		}
		else
			y1 = dst_row;

/* grow / shrink the bounding volume */
		for (size_t tx = 0; tx < x1; tx++){
			if (
					(dst[dst_row * out->desc.width + tx] ^
					 src[row * out->desc.width + tx]) != 0){
				x1 = tx;
				break;
			}
		}

		for (size_t tx = row_len-1; tx > x2; tx--){
			if (
					(dst[dst_row * out->desc.width + tx] ^
					 src[row * out->desc.width + tx]) != 0){
				x2 = tx;
				break;
			}
		}

		memcpy(&dst[dst_row * out->desc.width], &src[row * vs->w], row_sz);
	}

	if (!in_dirty){
		platform_fsrv_leave();
		return 1;
	}

/* flag ok and commit dirty region */
	global.encode.outctx->shm.ptr->hints |= SHMIF_RHINT_SUBREGION;
	struct arcan_shmif_region dirty = {
		.x1 = x1, .y1 = y1,
		.x2 = x2, .y2 = y2
	};
	atomic_store(&global.encode.outctx->shm.ptr->dirty, dirty);
	atomic_store_explicit(
		&global.encode.outctx->shm.ptr->vready, true, memory_order_seq_cst);

/* encode has more explicit frame signalling until we have futexes */
	platform_fsrv_pushevent(global.encode.outctx, &(struct arcan_event){
		.tgt.kind = TARGET_COMMAND_STEPFRAME,
		.category = EVENT_TARGET,
		.tgt.ioevs[0] = global.encode.outctx->vfcount++
	});

	platform_fsrv_leave();
	return 1;
}

void platform_video_synch(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

/*
 * we can't spawn this in platform init as the agp_ and video stack context
 * isn't available at that stage so it needs to be deferred here
 */
	if (!global.encode.check_output && !global.encode.outctx){
		global.encode.check_output = true;
		spawn_encode_output();
	}

/*
 * normal refresh cycle, then leave the next possible deadline to the conductor
 */
	size_t nd;
	arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );

/*
 * if there is no encoder listening run with the estimated fake synch
 */
	if (!nd || !global.encode.outctx){
		arcan_conductor_fakesynch(global.deadline);
	}
/*
 * if there is an encoder set, try to synch it or 'fake-+yield' until
 * the deadline has elapsed or synch succeeded
 */
	else{
		unsigned long deadline = arcan_timemillis() + global.deadline;

		while (!readback_encode()){
			unsigned step = arcan_conductor_yield(NULL, 0);
			if (arcan_timemillis() + step < deadline)
				arcan_timesleep(step);
		}
	}

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
	if (disp != 0)
		return false;

	arcan_warning("got map display %d, %d\n", id, disp);

	arcan_vobject* vobj = arcan_video_getobject(id);

/*
 * unmap any existing one
 */
	if (global.vstore && global.vstore != arcan_vint_world()){
		arcan_vint_drop_vstore(global.vstore);
		global.vstore = NULL;
	}

/*
 * disable output temporarily if it's there
 */
	if (id == ARCAN_EID){
		global.encode.block = true;
		return true;
	}

	global.encode.block = false;

/*
 * switch to the global output
 */
	if (id == ARCAN_VIDEO_WORLDID || !vobj){
		global.encode.flip_y = true;
		return true;
	}

	if (vobj->vstore->txmapped != TXSTATE_TEX2D){
		arcan_warning("(headless) map display called with bad source vobj\n");
		return false;
	}

/*
 * Refcount the new and mark as mapped, this is the place to add an indirect
 * rendertarget- apply/transform pass in order to handle mapping hints. Should
 * possible be done in the AGP stage though in the same way we should handle
 * repack-reblit
 */
	vobj->vstore->refcount++;
	bool isrt = arcan_vint_findrt(vobj) != NULL;
	global.encode.flip_y = isrt;
	global.vstore = vobj->vstore;

	return true;
}

const char* platform_video_capstr()
{
	return "Video Platform (HEADLESS)";
}

void platform_video_preinit()
{
}

bool platform_video_init(uint16_t width,
	uint16_t height, uint8_t bpp, bool fs, bool frames, const char* capt)
{
	global.width = width;
	global.height = height;

/* some trival default as default is -w 0 -h 0 */
	if (!global.width)
		global.width = 640;
	if (!global.height)
		global.height = 480;

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

	return true;
}
