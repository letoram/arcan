/*
 * Copyright 2014-2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: Platform that draws to an arcan display server using the shmif.
 * Multiple displays are simulated when we explicitly get a subsegment pushed
 * to us although they only work with the agp readback approach currently.
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

extern jmp_buf arcanmain_recover_state;

#include "../video_platform.h"
#include "../agp/glfun.h"

#define WANT_ARCAN_SHMIF_HELPER
#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_audio.h"
#include "arcan_video.h"
#include "arcan_event.h"
#include "arcan_videoint.h"
#include "arcan_renderfun.h"

#include "../EGL/egl.h"
#include "../EGL/eglext.h"

#ifdef EGL_DMA_BUF
typedef void* GLeglImageOES;
static PFNEGLCREATEIMAGEKHRPROC eglCreateImageKHR;
static PFNEGLDESTROYIMAGEKHRPROC eglDestroyImageKHR;
typedef void (EGLAPIENTRY* PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)(GLenum target, GLeglImageOES image);
static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC glEGLImageTargetTexture2DOES;
#endif

static char* synchopts[] = {
	"parent", "display server controls synchronisation",
	"pre-wake", "use the cost of and jitter from previous frames",
	"adaptive", "skip a frame if syncpoint is at risk",
	NULL
};

static char* input_envopts[] = {
	NULL
};

static enum {
	PARENT = 0,
	PREWAKE,
	ADAPTIVE
} syncopt;

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
	bool pending;
	uintptr_t cbtag;
	struct arcan_shmif_cont con;
};

struct display {
	struct arcan_shmif_cont conn;
	bool mapped, visible, focused, nopass;
	enum dpms_state dpms;
	struct storage_info_t* vstore;
	float ppcm;
	int id, dirty;

/* only used for first display */
	uint8_t subseg_alloc;
	struct subseg_output sub[8];
} disp[MAX_DISPLAYS] = {0};

static struct arg_arr* shmarg;

bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames, const char* title)
{
	static bool first_init = true;
/* can happen in the context of suspend/resume etc. */
	if (!first_init)
		return true;

	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		disp[i].id = i;
		disp[i].nopass = getenv("ARCAN_VIDEO_NO_FDPASS") != NULL;
	}

/*
 * temporary measure for generating the guid, just based on title as
 * we have an initial order problem with _applname not necessarily accesible
 */
	unsigned long h = 5381;
	const char* str = title;
	for (; *str; str++)
		h = (h << 5) + h + *str;

	struct arg_arr* shmarg;
	disp[0].conn = arcan_shmif_open_ext(0, &shmarg, (struct shmif_open_ext){
		.type = SEGID_LWA, .title = title, .guid = {h, 0}
	}, sizeof(struct shmif_open_ext));

	if (!disp[0].conn.addr){
		arcan_warning("lwa_video_init(), couldn't connect. Check ARCAN_CONNPATH and"
			" make sure a normal arcan instance is running\n");
		return false;
	}

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

	arcan_shmif_setprimary(SHMIF_INPUT, &disp[0].conn);
	arcan_shmifext_make_current(&disp[0].conn);

/*
 * switch rendering mode since our coordinate system differs
 */
	disp[0].conn.hints = SHMIF_RHINT_ORIGO_LL;
	arcan_shmif_resize(&disp[0].conn, disp[0].conn.w, disp[0].conn.h);

/*
 * map the provided initial values to match width/height, density,
 * font size and so on.
 */
	if (init->fonts[0].fd != -1){
		arcan_video_defaultfont("arcan-default", init->fonts[0].fd, SHMIF_PT_SIZE(
			init->density, init->fonts[0].size_mm), init->fonts[0].hinting, 0);
		init->fonts[0].fd = -1;

		if (init->fonts[1].fd != -1){
			arcan_video_defaultfont("arcan-default", init->fonts[1].fd,
				SHMIF_PT_SIZE(init->density, init->fonts[1].size_mm),
				init->fonts[1].hinting, 1
			);
			init->fonts[1].fd = -1;
		}
	}
	disp[0].mapped = true;
	disp[0].ppcm = init->density;
	disp[0].dpms = ADPMS_ON;
	disp[0].visible = true;
	disp[0].focused = true;

#ifdef EGL_DMA_BUF
	eglCreateImageKHR = (PFNEGLCREATEIMAGEKHRPROC)
		eglGetProcAddress("eglCreateImageKHR");

	eglDestroyImageKHR = (PFNEGLDESTROYIMAGEKHRPROC)
		eglGetProcAddress("eglDestroyImageKHR");

	glEGLImageTargetTexture2DOES = (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)
		eglGetProcAddress("glEGLImageTargetTexture2DOES");
#endif

/* we provide our own cursor that is blended in the output */
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
		if (disp[i].conn.addr)
			arcan_shmif_drop(&disp[i].conn);
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
}

void platform_video_restore_external()
{
}

void* platform_video_gfxsym(const char* sym)
{
	return arcan_shmifext_lookup(&disp[0].conn, sym);
}

void platform_video_setsynch(const char* arg)
{
	int ind = 0;

	while(synchopts[ind]){
		if (strcmp(synchopts[ind], arg) == 0){
			syncopt = (ind > 0 ? ind / 2 : ind);
			break;
		}

		ind += 2;
	}
}

int platform_video_cardhandle(int cardn)
{
	return -1;
}

void platform_event_samplebase(int devid, float xyz[3])
{
}

const char** platform_video_synchopts()
{
	return (const char**) synchopts;
}

static const char* arcan_envopts[] = {
	NULL
};

const char** platform_video_envopts()
{
	return arcan_envopts;
}

const char** platform_input_envopts()
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

bool platform_video_specify_mode(platform_display_id id,
	struct monitor_mode mode)
{
	if (!(id < MAX_DISPLAYS && disp[id].conn.addr))
		return false;

	if (!mode.width || !mode.height ||
		(mode.height == disp[id].conn.w && mode.height == disp[id].conn.h) ||
		!arcan_shmif_lock(&disp[id].conn))
		return false;

	bool rz = arcan_shmif_resize(&disp[id].conn, mode.width, mode.height);

	disp[id].dirty = 2;
	arcan_shmif_unlock(&disp[id].conn);

	return rz;
}

struct monitor_mode platform_video_dimensions()
{
	struct monitor_mode mode = {
		.width = disp[0].conn.addr->w,
		.height = disp[0].conn.addr->h,
	};
	mode.phy_width = (float)mode.width / disp[0].ppcm * 10.0;
	mode.phy_height = (float)mode.height / disp[0].ppcm * 10.0;

	return mode;
}

bool platform_video_set_mode(platform_display_id id, platform_mode_id newmode)
{
	struct monitor_mode* mode = get_platform_mode(newmode);

	if (!mode)
		return false;

	return platform_video_specify_mode(id, *mode);
}

static bool check_store(platform_display_id id)
{
	struct storage_info_t* vs = (disp[id].vstore ?
		disp[id].vstore : arcan_vint_world());

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

/*
 * Two things that are currently wrong with this approach to mapping:
 * 1. hint is ignored entirely, mapping mode is just based on WORLDID
 * 2. the texture coordinates of the source are not being ignored.
 *
 * For these to be solved, we need to extend the full path of shmif rhints
 * to cover all possible mapping modes, and a on-gpu rtarget- style blit
 * with extra buffer or partial synch and VIEWPORT events.
 */
bool platform_video_map_display(arcan_vobj_id vid, platform_display_id id,
	enum blitting_hint hint)
{
	if (id > MAX_DISPLAYS || id != (platform_display_id) ARCAN_VIDEO_WORLDID)
		return false;

	if (id < MAX_DISPLAYS && disp[id].vstore){
		arcan_vint_drop_vstore(disp[id].vstore);
		disp[id].vstore = NULL;
	}

	disp[id].mapped = false;

	if (vid == ARCAN_VIDEO_WORLDID){
		disp[id].conn.hints = SHMIF_RHINT_ORIGO_LL;
		disp[id].vstore = arcan_vint_world();
		return true;
	}
	else if (vid == ARCAN_EID)
		return true;
	else{
		arcan_vobject* vobj = arcan_video_getobject(vid);
		if (vobj == NULL){
			arcan_warning("platform_video_map_display(), attempted to map a "
				"non-existing video object");
			return false;
		}

		if (vobj->vstore->txmapped != TXSTATE_TEX2D){
			arcan_warning("platform_video_map_display(), attempted to map a "
				"video object with an invalid backing store");
			return false;
		}

		disp[id].conn.hints = 0;
		disp[id].vstore = vobj->vstore;
	}

/*
 * enforce display size constraint, this wouldn't be necessary
 * when doing a buffer passing operation
 */
	if (!check_store(id))
		return false;

	disp[id].vstore->refcount++;
	disp[id].mapped = true;
	disp[id].dirty = 2;

	return true;
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

/*
 * Need to do this manually here so that when we run nested, we are still able
 * to import data from clients that give us buffers. When/ if we implement the
 * same mechanism on OSX, Windows and Android, the code should probably be
 * moved to another shared platform path
 */
bool platform_video_map_handle(struct storage_info_t* dst, int64_t handle)
{
#ifdef EGL_DMA_BUF
	EGLint attrs[] = {
		EGL_DMA_BUF_PLANE0_FD_EXT,
		handle,
		EGL_DMA_BUF_PLANE0_PITCH_EXT,
		dst->vinf.text.stride,
		EGL_DMA_BUF_PLANE0_OFFSET_EXT,
		0,
		EGL_WIDTH,
		dst->w,
		EGL_HEIGHT,
		dst->h,
		EGL_LINUX_DRM_FOURCC_EXT,
		dst->vinf.text.format,
		EGL_NONE
	};

	if (!eglCreateImageKHR || !glEGLImageTargetTexture2DOES)
		return false;

	uintptr_t display;
	arcan_shmifext_egl_meta(&disp[0].conn, &display, NULL, NULL);

	if (0 != dst->vinf.text.tag){
		eglDestroyImageKHR((EGLDisplay) display, (EGLImageKHR) dst->vinf.text.tag);
		dst->vinf.text.tag = 0;
		if (handle != dst->vinf.text.handle){
			close(dst->vinf.text.handle);
		}
		dst->vinf.text.handle = -1;
	}

	if (-1 == handle)
		return false;

	EGLImageKHR img = eglCreateImageKHR(
		(EGLDisplay) display,
		EGL_NO_CONTEXT,
		EGL_LINUX_DMA_BUF_EXT,
		(EGLClientBuffer)NULL, attrs
	);

	if (img == EGL_NO_IMAGE_KHR){
		arcan_warning("could not import EGL buffer (%zu * %zu), "
			"stride: %d, format: %d from %d\n", dst->w, dst->h,
		 dst->vinf.text.stride, dst->vinf.text.format,handle
		);
		close(handle);
		return false;
	}

	agp_activate_vstore(dst);
	glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, img);
	dst->vinf.text.tag = (uintptr_t) img;
	dst->vinf.text.handle = handle;
	agp_deactivate_vstore(dst);
	return true;
#endif
	return false;
}

/*
 * we use a deferred stub here to avoid having the headless platform
 * sync function generate bad statistics due to our two-stage synch
 * process
 */
static void stub()
{
}

extern struct agp_rendertarget* arcan_vint_worldrt();

static void synch_copy(struct display* disp, struct storage_info_t* vs)
{
	check_store(disp->id);
	struct storage_info_t store = *vs;
	store.vinf.text.raw = disp->conn.vidp;

	agp_readback_synchronous(&store);
	arcan_shmif_signal(&disp->conn, SHMIF_SIGVID);
}

void platform_video_synch(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

	unsigned long long frametime = arcan_timemillis();

	size_t platform_nupd;
	arcan_bench_register_cost(arcan_vint_refresh(fract, &platform_nupd));
	agp_activate_rendertarget(NULL);

/* actually needed here or handle content will be broken */
	glFlush();

	unsigned long long ts = arcan_timemillis();
	if (ts < frametime){
		frametime = (unsigned long long)-1 - frametime + ts;
	}
	else
		frametime = ts - frametime;

	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		if (!(disp[i].dirty || (platform_nupd && disp[i].visible)))
			continue;

		if (!disp[i].mapped || disp[i].dpms != ADPMS_ON)
			continue;

/*
 * This is incorrect for a number of reasons. The synch output should either
 * be a readback target or double-buffered rendertarget. This does not take
 * texture coordinates or other vstore properties into account.
 */
		if (disp[i].dirty)
			disp[i].dirty--;
		if (disp[i].vstore || disp[i].nopass){
			synch_copy(&disp[i], disp[i].vstore ?
				disp[i].vstore : arcan_vint_world());
		}
		else {
			unsigned col = agp_rendertarget_swap(arcan_vint_worldrt());
			if (!disp[i].dirty)
				arcan_shmifext_signal(&disp[i].conn, 0, SHMIF_SIGVID, col);
		}
	}

	unsigned long long synchtime = arcan_timemillis();
	if (synchtime < ts){
		synchtime = (unsigned long long)-1 - synchtime + ts;
	}
	else
		synchtime = synchtime - ts;

/*
 * missing synchronization strategy setting here entirely, this
 * is just based on an assumed ~16ish max delay using the rendertime
 */
	if (frametime + synchtime < 16){
		struct pollfd pfd = {
			.fd = disp[0].conn.epipe,
			.events = POLLIN | POLLERR | POLLHUP | POLLNVAL
		};
		poll(&pfd, 1, 16 - frametime - synchtime);
	}

	if (post)
		post();
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
 * Ignoring mapping the segment will mean that it will eventually timeout,
 * either long (seconds+) or short (empty outevq and frames but no
 * response).
 */

static void map_window(struct arcan_shmif_cont* seg, arcan_evctx* ctx,
	int kind, const char* key)
{

/* encoder should really be mapped as an avfeed- type frameserver,
 * maintain it in a 'pending' slot, enqueue some notification and
 * let alloc_target() handle it */
	if (kind == SEGID_ENCODER){
		arcan_warning("(FIXME) SEGID_ENCODER type not yet supported.\n");
		return;
	}

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
	base->dirty = 2;

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

void arcan_lwa_subseg_ev(uintptr_t, arcan_event*);

enum arcan_ffunc_rv arcan_lwa_ffunc FFUNC_HEAD
{
	struct subseg_output* outptr = state.ptr;
/* we don't care about the guard part here since the data goes low->
 * high-priv and not the other way around */

	if (cmd == FFUNC_DESTROY){
		arcan_shmif_drop(&outptr->con);
		outptr->id = 0;
		outptr->pending = false;
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
		struct arcan_event inev;
		while (arcan_shmif_poll(&outptr->con, &inev) > 0)
			arcan_lwa_subseg_ev(outptr->cbtag, &inev);
		return 0;
	}

/*
 * FIXME: we need some way to set the pointer for the readback output
 * backing store to be buf so we can avoid this copy using the normal
 * signalling mechanisms, abusing the record target is not efficient.
 */
	if (cmd == FFUNC_READBACK){
		arcan_shmif_signal(&outptr->con, SHMIF_SIGVID);
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
bool platform_lwa_allocbind_feed(arcan_vobj_id rtgt,
	enum ARCAN_SEGID type, uintptr_t cbtag)
{
	arcan_vobject* vobj = arcan_video_getobject(rtgt);
	if (!vobj || !vobj->vstore)
		return false;

	if (disp[0].subseg_alloc == 255)
		return false;

	int ind = ffs(~disp[0].subseg_alloc)-1;
	disp[0].sub[ind].pending = true;
	disp[0].sub[ind].id = 0xcafe + ind;

	arcan_shmif_enqueue(&disp[0].conn, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.width = vobj->vstore->w,
		.ext.segreq.height = vobj->vstore->h,
		.ext.segreq.kind = type,
		.ext.segreq.id = disp[0].sub[ind].id
	});

	arcan_video_alterfeed(rtgt, FFUNC_LWA,
		(vfunc_state){.tag = cbtag, .ptr = &disp[0].sub[ind]});
	return true;
}

bool platform_lwa_targetevent(struct subseg_output* tgt, arcan_event* ev)
{
/* selectively covert certain events, like target_displayhint
 * to indicate visibility - opted for this kind of contextual reuse
 * rather than more functions to track */
	return false;
}

static bool scan_subseg(arcan_tgtevent* ev, bool ok)
{
/* 0 is cookie, 1 should be 0, 2 carries type */
/* if !ok, mark as free, if ok - mark as enabled and map */
	int ind = -1;
	if (ev->ioevs[1].iv != 0)
		return false;

	for (size_t i = 0; i < 8; i++){
		if (disp[0].sub[i].id == ev->ioevs[0].iv){
			ind = i;
			break;
		}
	}
	if (-1 == ind)
		return false;

	if (!ok){
		disp[0].sub[ind].pending = false;
		disp[0].subseg_alloc &= ~(1 << ind);
		arcan_warning("lwa - parent rejected subsegment with id %d\n", ind);
		return false;
	}

	disp[0].sub[ind].con = arcan_shmif_acquire(&disp[0].conn,
		NULL, disp[0].sub[ind].id, 0);
	disp[0].sub[ind].pending = false;
	if (!disp[0].sub[ind].con.vidp){
		arcan_warning("lwa - failed during mapping\n");
		disp[0].subseg_alloc &= ~(1 << ind);
		return false;
	}

	arcan_warning("accepted pending");
	return true;
}

/*
 * return true if the segment has expired
 */
static bool event_process_disp(arcan_evctx* ctx, struct display* d)
{
	if (!d->conn.addr)
		return true;

	arcan_event ev;

	while (1 == arcan_shmif_poll(&d->conn, &ev))
		if (ev.category == EVENT_TARGET)
		switch(ev.tgt.kind){

/*
 * We use subsegments forced from the parent- side as an analog for
 * hotplug displays, giving developers a testbed for a rather hard
 * feature and at the same time get to evaluate the API.
 *
 * For subsegment IDs that match a pending request, with special
 * treatment for the DND/PASTE cases.
*/
		case TARGET_COMMAND_NEWSEGMENT:
			if (d == &disp[0]){
				if (!scan_subseg(&ev.tgt, true))
					map_window(&d->conn, ctx, ev.tgt.ioevs[0].iv, ev.tgt.message);
			}
		break;

		case TARGET_COMMAND_REQFAIL:
			scan_subseg(&ev.tgt, false);
		break;

		case TARGET_COMMAND_BUFFER_FAIL:
			d->nopass = true;
		break;

/*
 * Depends on active synchronization strategy, could also be used with a
 * 'every tick' timer to synch clockrate to server or have a single-frame
 * stepping mode. This ought to be used with the ability to set RT clocking
 * mode
 */
		case TARGET_COMMAND_STEPFRAME:
		break;

/*
 * We can't automatically resize as the layouting in the running appl may not
 * be able to handle relayouting in an event-driven manner, so we translate and
 * forward as a monitor event.
 */
		case TARGET_COMMAND_DISPLAYHINT:
			if (ev.tgt.ioevs[0].iv && ev.tgt.ioevs[1].iv){
				arcan_event_enqueue(ctx, &(arcan_event){
					.category = EVENT_VIDEO,
					.vid.kind = EVENT_VIDEO_DISPLAY_RESET,
					.vid.source = -1,
					.vid.displayid = d->id,
					.vid.width = ev.tgt.ioevs[0].iv,
					.vid.height = ev.tgt.ioevs[1].iv,
					.vid.flags = ev.tgt.ioevs[2].iv,
					.vid.vppcm = ev.tgt.ioevs[4].fv,
				});
			}

			if (!(ev.tgt.ioevs[2].iv & 128)){
				bool vss = !((ev.tgt.ioevs[2].iv & 2) > 0);
				if (vss && !d->visible){
					d->dirty = 2;
				}
				d->visible = vss;
				d->focused = !((ev.tgt.ioevs[2].iv & 4) > 0);
			}

/*
 * If the density has changed, grab the current standard font size
 * and convert to mm to get the scaling factor, apply and update default
 */
			if (ev.tgt.ioevs[4].fv > 0){
				int font_sz;
				int hint;
				arcan_video_fontdefaults(NULL, &font_sz, &hint);
				float sf = ev.tgt.ioevs[4].fv / d->ppcm;
				arcan_video_defaultfont("arcan-default",
					BADFD, (float)font_sz * sf, hint, false);
				d->ppcm = ev.tgt.ioevs[4].fv;
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
				.vid.width = ev.tgt.ioevs[3].iv
			});
		}
		break;

/*
 * This is harsher than perhaps necessary as this does not care
 * for adoption of old connections, they are just killed off.
 */
		case TARGET_COMMAND_RESET:
			longjmp(arcanmain_recover_state, 2);
		break;

/*
 * The nodes have already been unlinked, so all cleanup
 * can be made when the process dies.
 */
		case TARGET_COMMAND_EXIT:
			if (d == &disp[0]){
				ev.category = EVENT_SYSTEM;
				ev.sys.kind = EVENT_SYSTEM_EXIT;
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
				if (d->vstore)
					arcan_vint_drop_vstore(d->vstore);

				memset(d, '\0', sizeof(struct display));
			}
			return true; /* it's not safe here */
		break;

		default:
		break;
		}
		else
			arcan_event_enqueue(ctx, &ev);

	return false;
}

void platform_input_help()
{
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
/*
 * Most events can just be added to the local queue,
 * but we want to handle some of the target commands separately
 * (with a special path to LUA and a different hook)
 */
	for (size_t i = 0; i < MAX_DISPLAYS; i++)
		event_process_disp(ctx, &disp[i]);
}

void platform_event_rescan_idev(arcan_evctx* ctx)
{
}

enum PLATFORM_EVENT_CAPABILITIES platform_input_capabilities()
{
	return ACAP_TRANSLATED | ACAP_MOUSE | ACAP_TOUCH |
		ACAP_POSITION | ACAP_ORIENTATION;
}

void platform_key_repeat(arcan_evctx* ctx, unsigned int rate)
{
}

void platform_event_deinit(arcan_evctx* ctx)
{
}

void platform_video_recovery()
{
	arcan_event ev = {
		.category = EVENT_VIDEO,
		.vid.kind = EVENT_VIDEO_DISPLAY_ADDED
	};
	arcan_evctx* evctx = arcan_event_defaultctx();
	arcan_event_enqueue(evctx, &ev);

	for (size_t i = 0; i < MAX_DISPLAYS; i++){
		platform_video_map_display(ARCAN_VIDEO_WORLDID, i, HINT_NONE);
		ev.vid.source = -1;
		ev.vid.displayid = i;
		arcan_event_enqueue(evctx, &ev);
	}
}

void platform_event_reset(arcan_evctx* ctx)
{
	platform_event_deinit(ctx);
}

void platform_device_lock(int devind, bool state)
{
}

void platform_event_init(arcan_evctx* ctx)
{
}

