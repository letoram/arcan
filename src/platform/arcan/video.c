/*
 * Copyright 2014-2021, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: Platform that draws to an arcan display server using the shmif.
 * Multiple displays are simulated when we explicitly get a subsegment pushed
 * to us although they only work with the agp readback approach currently.
 *
 * This is not a particularly good 'arcan-client' in the sense that some
 * event mapping and other behaviors is still being plugged in.
 *
 * Some things of note:
 *
 *  1. a pushed subsegment is treated as a new 'display'
 *  2. custom-requested subsegments (display.sub[]) are treated as recordtargets
 *     which, in principle, is fine - but currently transfers using readback and
 *     copy, not accelerated buffer transfers and rotating backing stores.
 *  3. more considerations need to happen with events that gets forwarded into
 *     the events that go to the scripting layer handler
 *  4. dirty-regions don't propagate in signal
 *  5. resizing the rendertarget bound to a subsegment is also painful
 *
 */
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <strings.h>
#include <stdio.h>
#include <sys/types.h>
#include <poll.h>
#include <setjmp.h>
#include <math.h>
#include <stdatomic.h>
#include <lua.h>
#include <errno.h>

extern jmp_buf arcanmain_recover_state;

#include "../video_platform.h"
#include "../agp/glfun.h"

#define VIDEO_PLATFORM_IMPL
#include "../../engine/arcan_conductor.h"

#define WANT_ARCAN_SHMIF_HELPER
#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_audio.h"
#include "arcan_video.h"
#include "arcan_event.h"
#include "arcan_videoint.h"
#include "arcan_renderfun.h"
#include "../../engine/arcan_lua.h"

#include "../EGL/egl.h"
#include "../EGL/eglext.h"

/* shmifext doesn't expose these - and to run correctly nested we need to be
 * able to import buffers from ourselves. While there is no other platform to
 * grab from, just use this. */
#ifdef EGL_DMA_BUF
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <drm.h>
#include <drm_mode.h>
#include <drm_fourcc.h>

#include <xf86drm.h>
#include <xf86drmMode.h>
#include <gbm.h>

#include "../egl-dri/egl.h"
#include "../egl-dri/egl_gbm_helper.h"

static struct egl_env agp_eglenv;
#endif

#ifdef _DEBUG
#define DEBUG 1
#else
#define DEBUG 0
#endif

#ifdef HAVE_XKBCOMMON
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>
#include <xkbcommon/xkbcommon-compose.h>
#endif

#define debug_print(fmt, ...) \
            do { if (DEBUG) arcan_warning("%lld:%s:%d:%s(): " fmt "\n",\
						arcan_timemillis(), "platform-arcan:", __LINE__, __func__,##__VA_ARGS__); } while (0)

#ifndef verbose_print
#define verbose_print
#endif

static char* input_envopts[] = {
	NULL
};

static char* video_envopts[] = {
	"ARCAN_RENDER_NODE=/path/to/dev", "(env only) override accelerated GPU device",
	"ARCAN_VIDEO_NO_FDPASS=1", "(env only) disable handle passing and force shm/readback",
	NULL
};

static struct monitor_mode mmodes[] = {
	{
		.id = 0,
		.width = 640,
		.height = 480,
		.refresh = 60,
		.depth = sizeof(av_pixel) * 8,
		.dynamic = true
	},
};

#define MAX_DISPLAYS 8

struct subseg_output {
	int id;
	uintptr_t cbtag;
	arcan_vobj_id vid;
	struct arcan_shmif_cont con;
	struct arcan_luactx* ctx;
};

struct display {
	struct arcan_shmif_cont conn;
	size_t decay;
	unsigned long long pending;
	bool mapped, visible, focused, nopass;
	enum dpms_state dpms;
	struct agp_vstore* vstore;
	float ppcm;
	int id;
  map_region keymap;

/* only used for first display */
	uint8_t subseg_alloc;
	struct subseg_output sub[8];
} disp[MAX_DISPLAYS] = {0};

static struct arg_arr* shmarg;
static bool event_process_disp(arcan_evctx* ctx, struct display* d, size_t i);

static struct {
	uint64_t magic;
	bool signal_pending;
	volatile uint8_t resize_pending;
} primary_udata = {
	.magic = 0xfeedface
};

void platform_video_preinit()
{
}

void platform_video_reset(int id, int swap)
{
/*
 * no-op on this platform as the DEVICEHINT argument is responsible
 * for swapping out the accelerated device target
 */
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

static void* lookup_egl(void* tag, const char* sym, bool req)
{
	void* res = arcan_shmifext_lookup((struct arcan_shmif_cont*) tag, sym);
	if (!res && req)
		arcan_fatal("agp lookup(%s) failed, missing req. symbol.\n", sym);
	return res;
}

bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames, const char* title)
{
	static bool first_init = true;
/* can happen in the context of suspend/resume etc. */
	if (!first_init)
		return true;

	uintptr_t config_tag;
	cfg_lookup_fun in_config = platform_config_lookup(&config_tag);

	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		disp[i].id = i;
		disp[i].nopass = in_config("video_no_fdpass", 0, NULL, config_tag);
	}

/* respect the command line provided dimensions if set, otherwise just
 * go with whatever defaults we get from the activate- phase */
	int flags = 0;
	if (width > 32 && height > 32)
		flags |= SHMIF_NOACTIVATE_RESIZE;

	struct arg_arr* shmarg;
	disp[0].conn = arcan_shmif_open_ext(flags, &shmarg, (struct shmif_open_ext){
		.type = SEGID_LWA, .title = title,}, sizeof(struct shmif_open_ext)
	);

	if (!disp[0].conn.addr){
		arcan_warning("lwa_video_init(), couldn't connect. Check ARCAN_CONNPATH and"
			" make sure a normal arcan instance is running\n");
		return false;
	}

/* add the display as a pollable event trigger */
	arcan_event_add_source(
		arcan_event_defaultctx(), disp[0].conn.epipe, O_RDONLY, -1, true);

	struct arcan_shmif_initial* init;
	if (sizeof(struct arcan_shmif_initial) != arcan_shmif_initial(
		&disp[0].conn, &init)){
		arcan_warning("lwa_video_init(), initial structure size mismatch, "
			"out-of-synch header/shmif lib\n");
		return NULL;
	}

/*
 * we want to do our own output texture handling since it depends on
 * how the arcan-space display is actually mapped
 */
	enum shmifext_setup_status status;
	struct arcan_shmifext_setup defs = arcan_shmifext_defaults(&disp[0].conn);
	defs.builtin_fbo = false;

	if ((status =
		arcan_shmifext_setup(&disp[0].conn, defs)) != SHMIFEXT_OK){
		arcan_warning("lwa_video_init(), couldn't setup headless graphics\n"
			"\t error code: %d\n", status);
		arcan_shmif_drop(&disp[0].conn);
		return false;
	}

	disp[0].conn.user = &primary_udata;
	arcan_shmif_setprimary(SHMIF_INPUT, &disp[0].conn);
	arcan_shmifext_make_current(&disp[0].conn);

#ifdef EGL_DMA_BUF
	map_egl_functions(&agp_eglenv, lookup_egl, &disp[0].conn);
	map_eglext_functions(&agp_eglenv, lookup_egl, &disp[0].conn);
#endif

/*
 * switch rendering mode since our coordinate system differs
 */
	disp[0].conn.hints = SHMIF_RHINT_ORIGO_LL | SHMIF_RHINT_VSIGNAL_EV;
	arcan_shmif_resize(&disp[0].conn,
		width > 0 ? width : disp[0].conn.w,
		height > 0 ? height : disp[0].conn.h
	);

/*
 * map the provided initial values to match width/height, density,
 * font size and so on.
 */
	if (init->fonts[0].fd != -1){
		size_t pt_sz = (init->fonts[0].size_mm * 2.8346456693f);
		arcan_video_defaultfont("arcan-default", init->fonts[0].fd,
			pt_sz, init->fonts[0].hinting, 0);
		init->fonts[0].fd = -1;

		if (init->fonts[1].fd != -1){
		size_t pt_sz = (init->fonts[1].size_mm * 2.8346456693f);
			arcan_video_defaultfont("arcan-default", init->fonts[1].fd,
				pt_sz, init->fonts[1].hinting, 1
			);
			init->fonts[1].fd = -1;
		}
	}
	disp[0].mapped = true;
	disp[0].ppcm = init->density;
	disp[0].dpms = ADPMS_ON;
	disp[0].visible = true;
	disp[0].focused = true;

/* we provide our own cursor that is blended in the output, this might change
 * when we allow map_ as layers, then we treat those as subsegments and
 * viewport */
	arcan_shmif_enqueue(&disp[0].conn, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(CURSORHINT),
		.ext.message = "hidden"
	});

	first_init = false;
	return true;
}

/*
 * These are just direct maps that will be statically sucked in
 */
void platform_video_shutdown()
{
	for (size_t i=0; i < MAX_DISPLAYS; i++)
		if (disp[i].conn.addr){
			arcan_shmif_drop(&disp[i].conn);
			disp[i] = (struct display){};
		}
}

size_t platform_video_decay()
{
	size_t decay = 0;
	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		if (disp[i].decay > decay)
			decay = disp[i].decay;
		disp[i].decay = 0;
	}
	return decay;
}

size_t platform_video_displays(platform_display_id* dids, size_t* lim)
{
	size_t rv = 0;

	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		if (!disp[i].conn.vidp)
			continue;

		if (dids && lim && *lim < rv)
			dids[rv] = disp[i].id;
		rv++;
	}

	if (lim)
		*lim = MAX_DISPLAYS;

	return rv;
}

bool platform_video_auth(int cardn, unsigned token)
{
	TRACE_MARK_ONESHOT("video", "authenticate", TRACE_SYS_DEFAULT, 0, 0, "lwa");

	if (cardn < MAX_DISPLAYS && disp[cardn].conn.addr){
		disp[cardn].conn.hints |= SHMIF_RHINT_AUTH_TOK;
		atomic_store(&disp[cardn].conn.addr->vpts, token);
		arcan_shmif_resize(&disp[cardn].conn,
			disp[cardn].conn.w, disp[cardn].conn.h);
		disp[cardn].conn.hints &= ~SHMIF_RHINT_AUTH_TOK;
		return true;
	}
	return false;
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

bool platform_video_display_edid(platform_display_id did,
	char** out, size_t* sz)
{
	*out = NULL;
	*sz = 0;
	return false;
}

void platform_video_prepare_external()
{
/* comes with switching in AGP, should give us card- switching
 * as well (and will be used as test case for that) */
	TRACE_MARK_ENTER("video", "external-handover", TRACE_SYS_DEFAULT, 0, 0, "");
}

void platform_video_restore_external()
{
	TRACE_MARK_EXIT("video", "external-handover", TRACE_SYS_DEFAULT, 0, 0, "");
}

void* platform_video_gfxsym(const char* sym)
{
	return arcan_shmifext_lookup(&disp[0].conn, sym);
}

int platform_video_cardhandle(int cardn, int* method, size_t* msz, uint8_t** dbuf)
{
/* this should be retrievable from the shmifext- connection so that we can
 * forward to any client we set up */
	return -1;
}

static char* names_to_keymap_str(const char** arg, const char** err)
{
#ifdef HAVE_XKBCOMMON
/* setup / fill out pref. */
	struct xkb_context* xkb_context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	struct xkb_rule_names names = {0};
	names.layout = arg[0];
	if (names.layout)
		names.model = arg[1];
	if (names.model)
		names.variant = arg[2];
	if (names.variant)
		names.options = arg[3];

/* compile / convert */
	struct xkb_keymap* kmap =
		xkb_keymap_new_from_names(xkb_context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
	if (!kmap){
		*err = "couldn't compile map";
		xkb_context_unref(xkb_context);
		return NULL;
	}
	char* map = xkb_map_get_as_string(kmap);
	if (!map){
		*err = "export failed";
		xkb_keymap_unref(kmap);
		xkb_context_unref(xkb_context);
		return NULL;
	}

/* export / cleanup */
	char* res = strdup(map);
	if (!res){
		*err = "map copy failed";
	}
	else
		*err = "";

	xkb_keymap_unref(kmap);
	xkb_context_unref(xkb_context);
	return res;
#else
	*err = "no xkb support";
	return NULL;
#endif
}

int platform_event_translation(int devid,
	int action, const char** names, const char** err)
{
/*
 * The serialize and remap can have meaning here as we might have native
 * wayland / x11 clients that need the map client side and we are running
 * inside another arcan that has it.
 *
 * If we get a BCHUNK event with 'xkb' type, the shared / cached 'current'
 * is forwarded, and if not we build and set according to the shared helper
 */
	if ((devid == -1 || devid == 0) && disp[0].keymap.ptr){
		switch (action){
			case EVENT_TRANSLATION_SET:{
				char* newmap = names_to_keymap_str(names, err);
				if (!newmap){
					return -1;
				}
				arcan_release_map(disp[0].keymap);
				disp[0].keymap.ptr = newmap;
				disp[0].keymap.sz = strlen(newmap);
				return 0;
			}
			break;
			case EVENT_TRANSLATION_SERIALIZE_SPEC:{
				char* newmap = names_to_keymap_str(names, err);
				int fd = arcan_strbuf_tempfile(newmap, strlen(newmap), err);
				free(newmap);
				return fd;
			}
			case EVENT_TRANSLATION_SERIALIZE_CURRENT:{
				return arcan_strbuf_tempfile(disp[0].keymap.ptr, disp[0].keymap.sz, err);
			}
			break;
		}
	}

	*err = "Not Supported";
	return -1;
}

int platform_event_device_request(int space, const char* path)
{
	return -1;
}

void platform_event_samplebase(int devid, float xyz[3])
{
}

const char** platform_video_envopts()
{
	return (const char**) video_envopts;
}

const char** platform_event_envopts()
{
	return (const char**) input_envopts;
}

static struct monitor_mode* get_platform_mode(platform_mode_id mode)
{
	for (size_t i = 0; i < sizeof(mmodes)/sizeof(mmodes[0]); i++){
		if (mmodes[i].id == mode)
			return &mmodes[i];
	}

	return NULL;
}

bool platform_video_specify_mode(
	platform_display_id id, struct monitor_mode mode)
{
	if (!(id < MAX_DISPLAYS && disp[id].conn.addr)){
		verbose_print("rejected bad id/connection (%d)", (int) id);
		return false;
	}

	primary_udata.resize_pending = 1;

/* audio rejects */
	if (!arcan_shmif_lock(&disp[id].conn)){
		return false;
	}

/* a crash during resize will trigger migration that might trigger _drop that might lock */
	bool rz = arcan_shmif_resize(&disp[id].conn, mode.width, mode.height);
	if (!rz){
		verbose_print("display "
			"id rejected resize (%d) => %zu*%zu",(int)id, mode.width, mode.height);
	}

	TRACE_MARK_ONESHOT("video", "resize-display", TRACE_SYS_DEFAULT, id, mode.width * mode.height, "");
	arcan_shmif_unlock(&disp[id].conn);
	primary_udata.resize_pending = 0;

	return rz;
}

struct monitor_mode platform_video_dimensions()
{
	struct monitor_mode mode = {
		.width = disp[0].conn.w,
		.height = disp[0].conn.h,
	};
	mode.phy_width = (float)mode.width / disp[0].ppcm * 10.0;
	mode.phy_height = (float)mode.height / disp[0].ppcm * 10.0;

	return mode;
}

bool platform_video_set_mode(
	platform_display_id id, platform_mode_id newmode, struct platform_mode_opts opts)
{
	struct monitor_mode* mode = get_platform_mode(newmode);

	if (!mode)
		return false;

	verbose_print("set mode on (%d) to %zu*%zu",
		(int) id, mode->width, mode->height);
	return platform_video_specify_mode(id, *mode);
}

static bool check_store(platform_display_id id)
{
	struct agp_vstore* vs = (disp[id].vstore ?
		disp[id].vstore : arcan_vint_world());

	if (!vs)
		return false;

	if (vs->w != disp[id].conn.w || vs->h != disp[id].conn.h){
		if (!platform_video_specify_mode(id,
			(struct monitor_mode){.width = vs->w, .height = vs->h})){
			arcan_warning("platform_video_map_display(), attempt to switch "
				"display output mode to match backing store failed.\n");
			return false;
		}
	}
	return true;
}

bool platform_video_map_display(
	arcan_vobj_id vid, platform_display_id id, enum blitting_hint hint)
{
	struct display_layer_cfg cfg = {
		.opacity = 1.0,
		.hint = hint
	};

	return platform_video_map_display_layer(vid, id, 0, cfg) >= 0;
}

void platform_video_invalidate_map(
	struct agp_vstore* vstore, struct agp_region region)
{
/* NOP for the time being - might change for direct forwarding of client */
}

/*
 * Two things that are currently wrong with this approach to mapping:
 * 1. hint is ignored entirely, mapping mode is just based on WORLDID
 * 2. the texture coordinates of the source are not being ignored.
 *
 * For these to be solved, we need to extend the full path of shmif rhints
 * to cover all possible mapping modes, and a on-gpu rtarget- style blit
 * with extra buffer or partial synch and VIEWPORT events.
 */
ssize_t platform_video_map_display_layer(arcan_vobj_id vid,
	platform_display_id id, size_t layer_index, struct display_layer_cfg cfg)
{

	if (id > MAX_DISPLAYS)
		return -1;

	if (!disp[id].conn.addr){
		arcan_warning("platform_video_map_display_layer(), "
			"attempt to map unconnected display.\n");
		return -1;
	}

	if (id < MAX_DISPLAYS && disp[id].vstore){
		if (disp[id].vstore != arcan_vint_world()){
			arcan_vint_drop_vstore(disp[id].vstore);
			disp[id].vstore = NULL;
		}
	}

	disp[id].mapped = false;

	if (vid == ARCAN_VIDEO_WORLDID){
		if (!arcan_vint_world())
			return -1;

		disp[id].conn.hints = SHMIF_RHINT_ORIGO_LL;
		disp[id].vstore = arcan_vint_world();
		disp[id].mapped = true;
		return 0;
	}
	else if (vid == ARCAN_EID)
		return 0;
	else{
		arcan_vobject* vobj = arcan_video_getobject(vid);
		if (vobj == NULL){
			arcan_warning("platform_video_map_display(), "
				"attempted to map a non-existing video object");
			return 0;
		}

		if (vobj->vstore->txmapped != TXSTATE_TEX2D){
			arcan_warning("platform_video_map_display(), "
				"attempted to map a video object with an invalid backing store");
			return 0;
		}

		disp[id].conn.hints = 0;
		disp[id].vstore = vobj->vstore;
	}

/*
 * enforce display size constraint, this wouldn't be necessary
 * when doing a buffer passing operation
 */
	if (!check_store(id))
		return -1;

	disp[id].vstore->refcount++;
	disp[id].mapped = true;

	return 0;
}

struct monitor_mode* platform_video_query_modes(
	platform_display_id id, size_t* count)
{
	*count = sizeof(mmodes) / sizeof(mmodes[0]);

	return mmodes;
}

void platform_video_query_displays()
{
}

static EGLDisplay conn_egl_display(struct arcan_shmif_cont* con)
{
	uintptr_t display;
	if (!arcan_shmifext_egl_meta(&disp[0].conn, &display, NULL, NULL))
		return NULL;

	EGLDisplay disp = (EGLDisplay) display;
	return disp;
}

bool platform_video_map_buffer(
	struct agp_vstore* vs, struct agp_buffer_plane* planes, size_t n)
{
#ifdef EGL_DMA_BUF
	struct agp_fenv* fenv = arcan_shmifext_getfenv(&disp[0].conn);
	EGLDisplay egldpy = conn_egl_display(&disp[0].conn);
	if (!egldpy)
		return false;

	EGLImage img = helper_dmabuf_eglimage(
		fenv, &agp_eglenv, egldpy, (struct shmifext_buffer_plane*) planes, n);

	if (!img){
		debug_print("buffer import failed");
		return false;
	}

/* might have an old eglImage around */
	if (0 != vs->vinf.text.tag){
		agp_eglenv.destroy_image(disp, (EGLImageKHR) vs->vinf.text.tag);
	}

	vs->w = planes[0].w;
	vs->h = planes[0].h;
	vs->bpp = sizeof(shmif_pixel);
	vs->txmapped = TXSTATE_TEX2D;

	agp_activate_vstore(vs);
		agp_eglenv.image_target_texture2D(GL_TEXTURE_2D, img);
	agp_deactivate_vstore();

	vs->vinf.text.tag = (uintptr_t) img;
	return true;
#endif
	return false;
}

/*
 * Need to do this manually here so that when we run nested, we are still able
 * to import data from clients that give us buffers. When/ if we implement the
 * same mechanism on OSX, Windows and Android, the code should probably be
 * moved to another shared platform path
 */
bool platform_video_map_handle(struct agp_vstore* dst, int64_t handle)
{
	uint64_t invalid =
#ifdef EGL_DMA_BUF
		DRM_FORMAT_MOD_INVALID;
#else
	-1;
#endif
	uint32_t hi = invalid >> 32;
	uint32_t lo = invalid & 0xffffffff;

/* special case, destroy the backing image */
	if (-1 == handle){
#ifdef EGL_DMA_BUF
		agp_eglenv.destroy_image(
			conn_egl_display(&disp[0].conn), (EGLImage) dst->vinf.text.tag);
#endif
		dst->vinf.text.tag = 0;
		return true;
	}

	struct agp_buffer_plane plane = {
		.fd = handle,
		.gbm = {
	#ifdef EGL_DMA_BUF
			.mod_hi = DRM_FORMAT_MOD_INVALID >> 32,
			.mod_lo = DRM_FORMAT_MOD_INVALID & 0xffffffff,
	#endif
			.offset = 0,
			.stride = dst->vinf.text.stride,
			.format = dst->vinf.text.format
		}
	};

	return platform_video_map_buffer(dst, &plane, 1);
}

/*
 * we use a deferred stub here to avoid having the headless platform
 * sync function generate bad statistics due to our two-stage synch
 * process
 */
static void stub()
{
}

/*
 * This one is undoubtedly slow and only used when the other side
 * is network-remote, or otherwise distrust our right to submit GPU
 * buffers, two adjustments could be made for making it less painful:
 *
 *  1. switch context to n-buffered state
 *  2. setup asynchronous readback and change to polling state for the
 *     backing store
 *
 * It might also apply when the source contents is an external client
 * (as we have no way of duplicating a dma-buf and takes a reblit pass)
 *
 * another valuable high-GL optimization would be to pin the object
 * memory to the mapped base address along with 2 and have a futex-
 * trigger thread that forwards the buffer then.
 */
static void synch_copy(struct display* disp, struct agp_vstore* vs)
{
	check_store(disp->id);
	struct agp_vstore store = *vs;
	store.vinf.text.raw = disp->conn.vidp;

	TRACE_MARK_ENTER("video", "copy-blit", TRACE_SYS_SLOW, 0, 0, "");
		agp_readback_synchronous(&store);
		arcan_shmif_signal(&disp->conn, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
		disp->pending = arcan_timemillis();
		arcan_conductor_deadline(4);
	TRACE_MARK_EXIT("video", "copy-blit", TRACE_SYS_SLOW, 0, 0, "");
}

size_t platform_video_export_vstore(
	struct agp_vstore* vs, struct agp_buffer_plane* planes, size_t n)
{
	_Static_assert(
		sizeof(struct shmifext_buffer_plane) ==
		sizeof(struct agp_buffer_plane), "agp-shmif mismatch"
	);

	return arcan_shmifext_export_image(&disp[0].conn,
		0, vs->vinf.text.glid, n, (struct shmifext_buffer_plane*)planes);
}

/*
 * The synch code here is rather rotten and should be reworked in its entirety
 * in a bit. It is hinged on a few refactors however:
 *
 *  1. proper explicit fencing and pipeline semaphores.
 *  2. screen deadline propagation.
 *  3. per rendertarget invalidation and per rendertarget scanout.
 *  4. rendertarget reblitter helper.
 *
 * This is to support both variable throughput, deadline throughput and
 * presentation time accurate rendering where the latency in the pipeline is
 * compensated for in animations and so on.
 *
 * The best configuration 'test' for this is to have two displays attached with
 * each being on vastly different synch targets, e.g. 48hz and 140hz or so and
 * both resizing.
 */
void platform_video_synch(
	uint64_t tick_count, float fract, video_synchevent pre, video_synchevent post)
{
/* Check back in a little bit, this is where the event_process, and vframe sig.
 * should be able to help. Setting the conductor display to the epipe and */
	while (primary_udata.signal_pending){
		struct conductor_display d = {
			.fd = disp[0].conn.epipe,
			.refresh = -1,
		};

		int ts = arcan_conductor_yield(&d, 1);
		platform_event_process(arcan_event_defaultctx());

/* the event processing while yielding / waiting for synch can reach EXIT and
 * then we should refuse to continue regardless */
		if (!disp[0].conn.vidp)
			return;

		if (primary_udata.signal_pending && ts > 0)
			arcan_timesleep(ts);
	}

	if (pre)
		pre();

/* first frame, fake rendertarget_swap so the first frame doesn't get lost into
 * the vstore that doesn't get hidden buffers, for the rest display mapped
 * rendertargets case we can do that on-map */
	static bool got_frame;
	if (!got_frame){
		bool swap;
		got_frame = true;
		verbose_print("first-frame swap");
		agp_rendertarget_allocator(
			arcan_vint_worldrt(), scanout_alloc, &disp[0].conn);
		agp_rendertarget_swap(arcan_vint_worldrt(), &swap);
	}

	static size_t last_nupd;
	size_t nupd;

	unsigned cost = arcan_vint_refresh(fract, &nupd);

/* nothing to do, yield with the timestep the conductor prefers - (fake 60hz
 * now until the shmif_deadline communication is more robust, then we can just
 * plug the next deadline and the conductor will wake us accordingly. */
	if (!nupd){
		TRACE_MARK_ONESHOT("video", "synch-stall", TRACE_SYS_SLOW, 0, 0, "nothing to do");
		verbose_print("skip frame");

/* mark it as safe to process events for each display and then allow stepframe
 * signal to break out of the block */
		arcan_conductor_deadline(4);
		goto pollout;
	}
/* so we have a buffered frame but this one didn't cause any updates,
 * force an update (could pretty much just reblit / swap but...) */
	arcan_bench_register_cost(cost);
	agp_activate_rendertarget(NULL);

/* needed here or handle content will be broken, though what we would actually
 * want is a fence on the last drawcall to each mapped rendercall and yield
 * until finished or at least send with the buffer */
	glFinish();

	for (size_t i = 0; i < MAX_DISPLAYS; i++){
/* server-side controlled visibility or script controlled visibility */
		if (!disp[i].visible || !disp[i].mapped || disp[i].dpms != ADPMS_ON)
			continue;

/*
 * Missing features / issues:
 *
 * 1. texture coordinates are not taken into account (would require RT
 *    indirection, manual resampling during synch-copy or shmif- rework
 *    to allow texture coordinates as part of signalling)
 *
 * 2. no post-processing shader, also needs blit stage
 *
 * 3. same rendertarget CAN NOT! be mapped to different displays as the
 *    frame-queueing would break
 *
 * solution would be extending the vstore- to have a 'repack/reblit/raster'
 * state, which would be needed for server-side text anyhow
 */
		struct rendertarget* rtgt = arcan_vint_findrt_vstore(disp[i].vstore);
		struct agp_rendertarget* art = arcan_vint_worldrt();

		if (disp[i].nopass || (disp[i].vstore && !rtgt) ||
			!arcan_shmif_handle_permitted(&disp[i].conn)){
			verbose_print("force-disable readback pass");
			synch_copy(&disp[i],
				disp[i].vstore ? disp[i].vstore : arcan_vint_world());
			continue;
		}

		if (disp[i].vstore){
/* there are conditions where could go with synch- handle + passing, but
 * with streaming sources we have no reliable way of knowing if its safe */
			if (!rtgt){
				verbose_print("synch-copy non-rt source");
				synch_copy(&disp[i], disp[i].vstore);
				continue;
			}
			art = rtgt->art;
		}

/* got the rendertarget vstore, export it to planes */
		bool swap;
		struct agp_vstore* vs = agp_rendertarget_swap(art, &swap);
		if (swap){
			size_t n_pl = 4;
			struct shmifext_buffer_plane planes[4];

			n_pl = arcan_shmifext_export_image(
				&disp[i].conn, 0, vs->vinf.text.glid, n_pl, planes);

			if (n_pl){
				arcan_shmifext_signal_planes(&disp[i].conn,
					SHMIF_SIGVID | SHMIF_SIGBLK_NONE, n_pl, planes);

				disp[i].pending = arcan_timemillis();
			}

/* wait for a stepframe before we continue with this rendertarget */
			arcan_conductor_deadline(4);
		}
	}

pollout:
	if (post)
		post();
}

void platform_event_preinit()
{
}

/*
 * The regular event layer is just stubbed, when the filtering etc.
 * is broken out of the platform layer, we can re-use that to have
 * local filtering untop of the one the engine is doing.
 */
arcan_errc platform_event_analogstate(int devid, int axisid,
	int* lower_bound, int* upper_bound, int* deadzone,
	int* kernel_size, enum ARCAN_ANALOGFILTER_KIND* mode)
{
	return ARCAN_ERRC_NO_SUCH_OBJECT;
}

void platform_event_analogall(bool enable, bool mouse)
{
}

void platform_event_analogfilter(int devid,
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind)
{
}

/*
 * For LWA simulated multidisplay, we still simulate disable by
 * drawing an empty output display.
 */
enum dpms_state
	platform_video_dpms(platform_display_id did, enum dpms_state state)
{
	if (!(did < MAX_DISPLAYS && did[disp].mapped))
		return ADPMS_IGNORE;

	if (state == ADPMS_IGNORE)
		return disp[did].dpms;

	disp[did].dpms = state;

	return state;
}

const char* platform_video_capstr()
{
	return "Video Platform (Arcan - in - Arcan)\n";
}

const char* platform_event_devlabel(int devid)
{
	return "no device";
}

/*
 * This handler takes care of the pushed segments that don't have a
 * corresponding request, i.e. they are force-pushed from the server
 * side.
 *
 * Most types are best ignored for now (or until we can / want to
 * provide a special handler for them, primary DEBUG where we can
 * expose conductor timing state).
 *
 * Special cases:
 *  SEGID_MEDIA - map as a low-level display that the scripts/engine
 *                can map to.
 *
 * The better option is to expose them as _adopt handlers, similar
 * to how we do stdin/stdout mapping.
 */
static void map_window(
	struct arcan_shmif_cont* seg, arcan_evctx* ctx, int kind, const char* key)
{
	if (kind != SEGID_MEDIA)
		return;

	TRACE_MARK_ONESHOT("video", "new-display", TRACE_SYS_DEFAULT, 0, 0, "lwa");

/*
 * we encode all our IDs (except clipboard) with the internal VID and
 * connected to a rendertarget slot, so re-use that fact.
 */

	struct display* base = NULL;
	size_t i = 0;

	for (; i < MAX_DISPLAYS; i++)
		if (disp[i].conn.addr == NULL){
			base = disp + i;
			break;
		}

	if (base == NULL){
		arcan_warning("Hard-coded display-limit reached (%d), "
			"ignoring new segment.\n", (int)MAX_DISPLAYS);
		return;
	}

	base->conn = arcan_shmif_acquire(seg, key, SEGID_LWA, SHMIF_DISABLE_GUARD);
	base->ppcm = ARCAN_SHMPAGE_DEFAULT_PPCM;
	base->dpms = ADPMS_ON;
	base->visible = true;

	arcan_event ev = {
		.category = EVENT_VIDEO,
		.vid.kind = EVENT_VIDEO_DISPLAY_ADDED,
		.vid.source = -1,
		.vid.displayid = i,
		.vid.width = seg->w,
		.vid.height = seg->h,
	};

	arcan_event_enqueue(ctx, &ev);
}

enum arcan_ffunc_rv arcan_lwa_ffunc FFUNC_HEAD
{
	struct subseg_output* outptr = state.ptr;
/* we don't care about the guard part here since the data goes low->
 * high-priv and not the other way around */

	if (cmd == FFUNC_DESTROY){
		arcan_shmif_drop(&outptr->con);
		outptr->id = 0;
		for (size_t i = 0; i < 8; i++)
			if (outptr == &disp[0].sub[i]){
				disp[0].subseg_alloc &= ~(1 << i);
				break;
			}
/* don't need to free outptr as it's from the displays- structure */
		return 0;
	}

	if (cmd == FFUNC_ADOPT){
/* we don't support adopt, so will be dropped */
		return 0;
	}

/* drain events to scripting layer, don't care about DMS here */
	if (cmd == FFUNC_TICK){
	}

/*
 * This should only be reached / possible / used when we don't have the
 * fast-path of simply rotating backing color buffer and forwarding the handle
 * to the rendertarget but lack of explicit synch wiring is the big thing here.
 */
	if (cmd == FFUNC_POLL){
		struct arcan_event inev;
		int ss = arcan_shmif_signalstatus(&outptr->con);
		if (-1 == ss || (ss & 1))
			return FRV_GOTFRAME;
		else
			return FRV_NOFRAME;
	}

/* the -1 == ss test above guarantees us that READBACK will only trigger on
 * a valid segment as the progression is always POLL immediately before any
 * READBACK is issued */
	if (cmd == FFUNC_READBACK){
		struct arcan_shmif_cont* c = &outptr->con;

/* readback buffer is always packed as it comes from a PBO (pixel packing op)
 * and both vidp and buf will be forced to shmif_pixel == av_pixel */
		for (size_t y = 0; y < c->h; y++){
			memcpy(&outptr->con.vidp[y * c->pitch], &buf[y * width], c->stride);
		}

/* any audio is transfered as part of (unfortunate) patches to openAL pending
 * a better audio layer separation */
		arcan_shmif_signal(&outptr->con, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
	}

/* special cases, how do we mark ourselves as invisible for popup,
 * or set our position relative to parent? */
	return FRV_NOFRAME;
}

/*
 * Generate a subsegment request on the primary segment, bind and
 * add that as the feed-recipient to the recordtarget defined in [rtgt].
 * will fail immediately if we are out of free subsegments.
 *
 * To avoid callbacks or additional multiplex- copies, expect the
 * lwa_subseg_eventdrain(uintptr_t tag, arcan_event*) function to
 * exist.
 */
bool platform_lwa_allocbind_feed(struct arcan_luactx* ctx,
	arcan_vobj_id rtgt, enum ARCAN_SEGID type, uintptr_t cbtag)
{
	arcan_vobject* vobj = arcan_video_getobject(rtgt);
	if (!vobj || !vobj->vstore)
		return false;

/* limit to 8 possible subsegments / 'display' */
	if (disp[0].subseg_alloc == 255)
		return false;

	int ind = ffs(~disp[0].subseg_alloc)-1;
	disp[0].subseg_alloc |= 1 << ind;

	struct subseg_output* out = &disp[0].sub[ind];
	*out = (struct subseg_output){
		.id = 0xcafe + ind,
		.ctx = ctx,
		.cbtag = cbtag,
		.vid = vobj->cellid
	};

	arcan_shmif_enqueue(&disp[0].conn, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.width = vobj->vstore->w,
		.ext.segreq.height = vobj->vstore->h,
		.ext.segreq.kind = type,
		.ext.segreq.id = out->id
	});

	arcan_video_alterfeed(rtgt,
		FFUNC_LWA, (vfunc_state){.tag = cbtag, .ptr = out});
	return true;
}

bool platform_lwa_targetevent(struct subseg_output* tgt, arcan_event* ev)
{
/* selectively convert certain events, like target_displayhint to indicate
 * visibility - opted for this kind of contextual reuse rather than more
 * functions to track */
	if (!tgt){
		arcan_shmif_enqueue(&disp[0].conn, ev);
		return true;
	}

	return arcan_shmif_enqueue(&tgt->con, ev);
}

static bool scan_subseg(arcan_tgtevent* ev, bool ok)
{
/* 0 : fd,
 * 1 : direction,
 * 2 : type,
 * 3 : cookie
 * ... */

	int ind = -1;
	if (ev->ioevs[1].iv != 0)
		return false;

	for (size_t i = 0; i < 8; i++){
		if (disp[0].sub[i].id == ev->ioevs[3].iv){
			ind = i;
			break;
		}
	}
	if (-1 == ind)
		return false;

	struct subseg_output* out = &disp[0].sub[ind];

/* if !ok, mark as free, send EXIT event so the scripting side can terminate,
 * we won't release the bit until TERMINATE comes in the FFUNC on the vobj
 * itself */
	if (!ok)
		goto send_error;

	out->con = arcan_shmif_acquire(&disp[0].conn, NULL, out->id, 0);
	if (out->con.vidp)
		return true;

send_error:
	arcan_lwa_subseg_ev(out->ctx, out->vid, out->cbtag, &(struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_EXIT,
		.tgt.message = "rejected"
	});
	return false;
}

/*
 * return true if the segment has expired
 */
extern struct arcan_luactx* main_lua_context;
static bool event_process_disp(arcan_evctx* ctx, struct display* d, size_t did)
{
	if (!d->conn.addr)
		return true;

	arcan_event ev;

	while (1 == arcan_shmif_poll(&d->conn, &ev))
		if (ev.category == EVENT_TARGET)
		switch(ev.tgt.kind){

/*
 * We use subsegments forced from the parent- side as an analog for hotplug
 * displays, giving developers a testbed for a rather hard feature and at the
 * same time get to evaluate the API. This is not ideal as the _adopt handler
 * is more apt at testing that the script code can handle an unannounced
 * lwa_segment coming in.
 *
 * Similary, if an OUTPUT segment comes in such a way, that would be better
 * treated as an adopt on a media source. More things to reconsider in this
 * interface come ~0.7
 *
 * For subsegment IDs that match a pending request, with special treatment for
 * the DND/PASTE cases.
*/
		case TARGET_COMMAND_NEWSEGMENT:
			if (d == &disp[0]){
				if (!scan_subseg(&ev.tgt, true))
					map_window(&d->conn, ctx, ev.tgt.ioevs[2].iv, ev.tgt.message);
			}
		break;

		case TARGET_COMMAND_REQFAIL:
			scan_subseg(&ev.tgt, false);
		break;

/*
 * Depends on active synchronization strategy, could also be used with a
 * 'every tick' timer to synch clockrate to server or have a single-frame
 * stepping mode. This ought to be used with the ability to set RT clocking
 * mode
 */
		case TARGET_COMMAND_STEPFRAME:
			TRACE_MARK_ONESHOT("video", "signal-stepframe", TRACE_SYS_DEFAULT, d->id, 0, "");
			arcan_conductor_deadline(0);
			d->pending = 0;
		break;

/*
 * We can't automatically resize as the layouting in the running appl may not
 * be able to handle relayouting in an event-driven manner, so we translate and
 * forward as a monitor event.
 */
		case TARGET_COMMAND_DISPLAYHINT:{
			bool update = false;
			size_t w = d->conn.w;
			size_t h = d->conn.h;

			if (ev.tgt.ioevs[0].iv && ev.tgt.ioevs[1].iv){
				update |= ev.tgt.ioevs[0].iv != d->conn.w;
				update |= ev.tgt.ioevs[1].iv != d->conn.h;
				w = ev.tgt.ioevs[0].iv;
				h = ev.tgt.ioevs[1].iv;
			}

/*
 * These properties are >currently< not forwarded - as the idea of mapping
 * windows as 'displays' is problematic with 'visibility and focus' not
 * making direct sense as such.
 *
 * This should probably be forwarded as the special _LWA events so that
 * any focus state or mouse cursor state can be updated accordingly.
 * The best option is 'probably' to use arcan_lwa_subseg_ev and some
 * _arcan event entry-point for the primary display.
 *
 * Currently the flags are forwarded raw so the reset event handler can
 * take them into account, but it is not pretty.
 */
			if (!(ev.tgt.ioevs[2].iv & 128)){
				d->visible = !((ev.tgt.ioevs[2].iv & 2) > 0);
				d->focused = !((ev.tgt.ioevs[2].iv & 4) > 0);
			}

			if (ev.tgt.ioevs[4].fv > 0 && ev.tgt.ioevs[4].fv != d->ppcm){
				update = true;
				d->ppcm = ev.tgt.ioevs[4].fv;
			}

			if (update){
				arcan_event_denqueue(ctx, &(arcan_event){
					.category = EVENT_VIDEO,
					.vid.kind = EVENT_VIDEO_DISPLAY_RESET,
					.vid.source = -1,
					.vid.displayid = d->id,
					.vid.width = w,
					.vid.height = h,
					.vid.flags = ev.tgt.ioevs[2].iv,
					.vid.vppcm = d->ppcm
				});
			}
		}
		break;
/*
 * This behavior may be a bit strong, but we allow the display server
 * to override the default font (if provided)
 */
		case TARGET_COMMAND_FONTHINT:{
			int newfd = BADFD;
			int font_sz = 0;
			int hint = ev.tgt.ioevs[3].iv;

			if (ev.tgt.ioevs[1].iv == 1 && BADFD != ev.tgt.ioevs[0].iv){
				newfd = dup(ev.tgt.ioevs[0].iv);
			};

			if (ev.tgt.ioevs[2].fv > 0)
				font_sz = ceilf(d->ppcm * ev.tgt.ioevs[2].fv);

			arcan_video_defaultfont("arcan-default",
				newfd, font_sz, hint, ev.tgt.ioevs[4].iv);

			arcan_event_enqueue(ctx, &(arcan_event){
				.category = EVENT_VIDEO,
				.vid.kind = EVENT_VIDEO_DISPLAY_RESET,
				.vid.source = -2,
				.vid.displayid = d->id,
				.vid.vppcm = ev.tgt.ioevs[2].fv,

			});
		}
		break;

		case TARGET_COMMAND_RESET:
			if (ev.tgt.ioevs[0].iv == 0)
				longjmp(arcanmain_recover_state, ARCAN_LUA_SWITCH_APPL);
			else if (ev.tgt.ioevs[0].iv == 1)
				longjmp(arcanmain_recover_state, ARCAN_LUA_SWITCH_APPL_NOADOPT);
			else {
/* We are in migrate state, so force-mark frames as dirty */
				disp[0].decay = 4;
			}
		break;

/*
 * The nodes have already been unlinked, so all cleanup
 * can be made when the process dies.
 */
		case TARGET_COMMAND_EXIT:
			if (d == &disp[0]){
				ev.category = EVENT_SYSTEM;
				ev.sys.kind = EVENT_SYSTEM_EXIT;
				d->conn.vidp = NULL;
				arcan_event_enqueue(ctx, &ev);
			}
/* Need to explicitly drop single segment */
			else {
				arcan_event ev = {
					.category = EVENT_VIDEO,
					.vid.kind = EVENT_VIDEO_DISPLAY_REMOVED,
					.vid.displayid = d->id
				};
				arcan_event_enqueue(ctx, &ev);
				free(d->conn.user);
				arcan_shmif_drop(&d->conn);
				if (d->vstore){
					arcan_vint_drop_vstore(d->vstore);
					d->vstore = NULL;
				}

				memset(d, '\0', sizeof(struct display));
			}
			return true; /* it's not safe here */
		break;

		case TARGET_COMMAND_BCHUNK_IN:
			if (strcmp(ev.tgt.message, "xkb") == 0){
			    data_source ds = {.fd = ev.tgt.ioevs[0].iv};
					arcan_release_map(d->keymap);
/* setting to write means that the fd won't be cached and the whole resource
 * will be read in one go and copied, so no need to dup and keep a fd */
					d->keymap = arcan_map_resource(&ds, true);
			}

/* fallthrough to default is intended */
		default:
			if (did == 0){
				arcan_lwa_subseg_ev(main_lua_context, ARCAN_VIDEO_WORLDID, 0, &ev);
			}
		break;
		}
		else
			arcan_event_enqueue(ctx, &ev);

	return false;
}

void platform_event_keyrepeat(arcan_evctx* ctx, int* period, int* delay)
{
	*period = 0;
	*delay = 0;
/* in principle, we could use the tick, implied in _process,
 * track the latest input event that corresponded to a translated
 * keyboard device (track per devid) and emit that every oh so often */
}

void platform_event_process(arcan_evctx* ctx)
{
	bool locked = primary_udata.signal_pending;
	primary_udata.signal_pending = false;

/*
 * Most events can just be added to the local queue, but we want to handle some
 * of the target commands separately (with a special path to Lua and a
 * different hook)
 */
	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		event_process_disp(ctx, &disp[i], i);

/*
 * normally we should just return to polling when there is a display still
 * waiting for a frame release, but there is some kind of initial timing race
 * where a STEPFRAME fails to emit properly. Since much of this need to be
 * reworked when we have proper fences on buffers ("any day now") solving it
 * isn't worth the hassle.
 */
		if (disp[i].pending && arcan_timemillis() - disp[i].pending < 64)
			primary_udata.signal_pending = true;
	}

	int subs = disp[0].subseg_alloc;
	int bits;

/*
 * Only first 'display' can have subsegments, sweep any of those if they are
 * allocated, this could again be done with monitoring threads on the futex
 * with better synch strategies. Their outputs act as recordtargets with
 * swapchains, not as proper 'displays'
 */
	while ((bits = ffs(subs))){
		struct subseg_output* out = &disp[0].sub[bits-1];
		subs = subs & ~(1 << (bits-1));

		struct arcan_event inev;
		while (arcan_shmif_poll(&out->con, &inev) > 0){
			arcan_lwa_subseg_ev(out->ctx, out->vid, out->cbtag, &inev);
		}
	}
}

void platform_event_rescan_idev(arcan_evctx* ctx)
{
}

enum PLATFORM_EVENT_CAPABILITIES platform_event_capabilities(const char** out)
{
	if (out)
		*out = "lwa";

	return ACAP_TRANSLATED | ACAP_MOUSE | ACAP_TOUCH |
		ACAP_POSITION | ACAP_ORIENTATION;
}

void platform_key_repeat(arcan_evctx* ctx, unsigned int rate)
{
}

void platform_event_deinit(arcan_evctx* ctx)
{
	TRACE_MARK_ONESHOT("event", "event-platform-deinit", TRACE_SYS_DEFAULT, 0, 0, "lwa");
}

void platform_video_recovery()
{
	arcan_event ev = {
		.category = EVENT_VIDEO,
		.vid.kind = EVENT_VIDEO_DISPLAY_ADDED
	};

	TRACE_MARK_ONESHOT("video", "video-platform-recovery", TRACE_SYS_DEFAULT, 0, 0, "lwa");
	arcan_evctx* evctx = arcan_event_defaultctx();
	arcan_event_enqueue(evctx, &ev);

	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		disp[i].vstore = arcan_vint_world();
		ev.vid.source = -1;
		ev.vid.displayid = i;
		arcan_event_enqueue(evctx, &ev);
	}
}

void platform_event_reset(arcan_evctx* ctx)
{
	TRACE_MARK_ONESHOT("event", "event-platform-reset", TRACE_SYS_DEFAULT, 0, 0, "lwa");
	platform_event_deinit(ctx);
}

void platform_device_lock(int devind, bool state)
{
}

void platform_event_init(arcan_evctx* ctx)
{
	TRACE_MARK_ONESHOT("event", "event-platform-init", TRACE_SYS_DEFAULT, 0, 0, "lwa");
}
