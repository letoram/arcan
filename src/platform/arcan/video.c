/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: Platform that draws to an arcan display server using the shmif.
 * Multiple displays are simulated when we explicitly get a subsegment pushed
 * to us although they only work with the agp readback approach currently.
 */

#define PLATFORM_SUFFIX lwa

#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/types.h>
#include <poll.h>

#include "../video_platform.h"

#define WITH_HEADLESS
#include HEADLESS_PLATFORM

/* 2. interpose and map to shm */
#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_event.h"
#include "arcan_videoint.h"
#include "arcan_renderfun.h"

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

struct display {
	struct arcan_shmif_cont conn;
	bool mapped;
	enum dpms_state dpms;
	struct storage_info_t* vstore;
} disp[MAX_DISPLAYS];

static struct arg_arr* shmarg;
static bool nopass;

bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames, const char* title)
{
	static bool first_init = true;

	if (getenv("ARCAN_VIDEO_NO_FDPASS"))
		nopass = true;

	if (width == 0 || height == 0){
		width = 640;
		height = 480;
	}

	if (first_init){
		disp[0].conn = arcan_shmif_open(SEGID_LWA, 0, &shmarg);
		if (disp[0].conn.addr == NULL){
			arcan_warning("couldn't connect to parent\n");
			return false;
		}

		disp[0].conn.addr->hints = RHINT_ORIGO_LL;

		if (!arcan_shmif_resize( &disp[0].conn, width, height )){
			arcan_warning("couldn't set shm dimensions (%d, %d)\n", width, height);
			return false;
		}

		arcan_shmif_enqueue(&disp[0].conn, &(struct arcan_event){
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(CURSORHINT),
			.ext.message = "hidden"
		});

/* disp[0] always start out mapped / enabled and we'll use the
 * current world unless overridden */
		disp[0].mapped = true;
		first_init = false;
	}
	else {
		if (!arcan_shmif_resize( &disp[0].conn, width, height )){
			arcan_warning("couldn't set shm dimensions (%d, %d)\n", width, height);
			return false;
		}
	}

/*
 * currently, we actually never de-init this
 */
	arcan_shmif_setprimary(SHMIF_INPUT, &disp[0].conn);
	return lwa_video_init(width, height, bpp, fs, frames, title);
}

/*
 * These are just direct maps that will be statically sucked in
 */
void platform_video_shutdown()
{
	lwa_video_shutdown();
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
	lwa_video_prepare_external();
}

void platform_video_restore_external()
{
	lwa_video_restore_external();
}

void* platform_video_gfxsym(const char* sym)
{
	return lwa_video_gfxsym(sym);
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
	static const char** cache;
	static bool env_init;

	if (!env_init){
		const char** buf = lwa_video_envopts();
		const char** wrk = buf;
		ssize_t count = sizeof(arcan_envopts)/sizeof(arcan_envopts[0]);

		while (*wrk++)
			count++;

		cache = malloc(sizeof(char*) * count);
		cache[count] = NULL;
		wrk = buf;

		count = 0;
		while(*wrk)
			cache[count++] = *wrk++;

		wrk = arcan_envopts;
		while(*wrk)
			cache[count++] = *wrk++;

		env_init = true;
	}

	return cache;
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

	return arcan_shmif_resize(&disp[id].conn,
		mode.width, mode.height);
}

struct monitor_mode platform_video_dimensions()
{
	struct monitor_mode mode = {
		.width = disp[0].conn.addr->w,
		.height = disp[0].conn.addr->h,
		.phy_width = disp[0].conn.addr->w,
		.phy_height = disp[0].conn.addr->h
	};
	return mode;
}

bool platform_video_set_mode(platform_display_id id, platform_mode_id newmode)
{
	struct monitor_mode* mode = get_platform_mode(newmode);

	if (!mode)
		return false;

	if (!(id < MAX_DISPLAYS && disp[id].conn.addr))
		return false;

	return arcan_shmif_resize(&disp[id].conn, mode->width, mode->height);

	return false;
}

static bool check_store(platform_display_id id)
{
	if (disp[id].vstore->w != disp[id].conn.addr->w ||
		disp[id].vstore->h != disp[id].conn.addr->h){

		if (!arcan_shmif_resize(&disp[id].conn,
				disp[id].vstore->w, disp[id].vstore->h)){
			arcan_warning("platform_video_map_display(), attempt to switch "
				"display output mode to match backing store failed.\n");
			return false;
		}
	}
	return true;
}

bool platform_video_map_display(arcan_vobj_id vid, platform_display_id id,
	enum blitting_hint hint)
{
	if (id > MAX_DISPLAYS)
		return false;

	if (disp[id].vstore){
		arcan_vint_drop_vstore(disp[id].vstore);
		disp[id].vstore = NULL;
	}

	disp[id].mapped = false;

	if (id == ARCAN_VIDEO_WORLDID)
		disp[id].vstore = disp[0].vstore;
	else if (id == ARCAN_EID)
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

		disp[id].vstore = vobj->vstore;
		vobj->vstore->refcount++;
	}

/*
 * enforce display size constraint, this wouldn't be necessary
 * when doing a buffer passing operation
 */
	if (!check_store(id))
		return false;

	disp[id].vstore->refcount++;
	disp[id].mapped = true;

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

bool platform_video_map_handle(struct storage_info_t* store, int64_t handle)
{
	return lwa_video_map_handle(store, handle);
}

/*
 * we use a deferred stub here to avoid having the headless platform
 * sync function generate bad statistics due to our two-stage synch
 * process
 */
static void stub()
{
}

static void synch_hpassing(struct storage_info_t* vs,
	int handle, enum status_handle status)
{
/*
 * This does not yet handle multiple windows handle passing,
 * only for primary segment (which isn't correct of course but is
 * currently pretty much a fringle case for multidisplay testing)
 */
	arcan_shmif_signalhandle(&disp[0].conn, SHMIF_SIGVID,
		handle, vs->vinf.text.stride, vs->vinf.text.format);
	close(handle);
}

static void synch_copy(struct storage_info_t* vs)
{
	struct storage_info_t store = *vs;
	store.vinf.text.raw = disp[0].conn.vidp;

	agp_readback_synchronous(&store);
	arcan_shmif_signal(&disp[0].conn, SHMIF_SIGVID);

	for (size_t i = 1; i < MAX_DISPLAYS; i++){
		if (!disp[i].mapped || disp[i].dpms != ADPMS_ON)
			continue;

/* re-use world readback, make a temporary copy to re-use check_store */
		if (!disp[i].vstore){
			disp[i].vstore = &store;
			check_store(i);

			memcpy(disp[i].conn.vidp, disp[0].conn.vidp,
				disp[i].vstore->vinf.text.s_raw);

			disp[i].vstore = NULL;

			if (!check_store(i))
				continue;
		}
		else {
			check_store(i);
			store = *(disp[i].vstore);
			store.vinf.text.raw = disp[i].conn.vidp;
			agp_readback_synchronous(&store);
		}

		arcan_shmif_signal(&disp[i].conn, SHMIF_SIGVID);
	}
}

void platform_video_synch(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	lwa_video_synch(tick_count, fract, pre, stub);

	static int64_t last_frametime;
	if (0 == last_frametime)
		last_frametime = arcan_timemillis();

/*
 * Other options, schedule all readbacks asynchronously first pass
 * and then do a synch- pass after.
 *
 * Evaluate when we can compare performance against sharing
 * gpu- specific handles
 */

	if (platform_nupd){
		struct storage_info_t* vs = arcan_vint_world();
		enum status_handle status;

		int handle = nopass ? -1 :
			lwa_video_output_handle(vs, &status);

		if (handle == -1 || status < 0)
			synch_copy(vs);
		else{
			synch_hpassing(vs, handle, status);
		}
	}
/* or just check on a ~60Hz basis letting external events prewake */
	else {
		struct pollfd pfd = {
			.fd = disp[0].conn.epipe,
			.events = POLLIN | POLLERR | POLLHUP | POLLNVAL
		};
		poll(&pfd, 1, 16);
	}

/*
 * we should implement a mapping for TARGET_COMMAND_FRAMESKIP or so and use to
 * set virtual display timings. ioev[0] => mode, [1] => prewake, [2] =>
 * preaudio, 3/4 for desired jitter (testing / simulation)
 */

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
	if (kind == SEGID_ENCODER){
		arcan_warning("(FIXME) SEGID_ENCODER type not yet supported.\n");
		return;
	}

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
	arcan_event ev = {
		.category = EVENT_VIDEO,
		.vid.kind = EVENT_VIDEO_DISPLAY_ADDED,
		.vid.source = i
	};

	arcan_shmif_enqueue(&base->conn, &ev);
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
 */
		case TARGET_COMMAND_NEWSEGMENT:
			map_window(&d->conn, ctx, ev.tgt.ioevs[0].iv, ev.tgt.message);
		break;

/*
 * Depends on active synchronization strategy of course.
 */
		case TARGET_COMMAND_STEPFRAME:
		break;

/*
 * We can't automatically resize as the layouting in the running
 * appl may not be able to handle relayouting in an event-driven
 * manner, so we translate and forward as a monitor event.
 */
		case TARGET_COMMAND_DISPLAYHINT:
				arcan_event_enqueue(ctx, &(arcan_event) {
					.category = EVENT_VIDEO,
					.vid.kind = EVENT_VIDEO_DISPLAY_RESET,
					.vid.source = -1,
					.vid.width = ev.tgt.ioevs[0].iv,
					.vid.height = ev.tgt.ioevs[1].iv
				});
		break;
/*
 * This behavior may be a bit strong, but we allow the display server
 * to override the default font (if provided)
 */
		case TARGET_COMMAND_FONTHINT:
			if (ev.tgt.ioevs[0].iv == 1 && BADFD != ev.tgt.ioevs[0].iv){
				int newfd = dup(ev.tgt.ioevs[0].iv);
				if (BADFD != newfd)
					arcan_video_defaultfont("arcan-default", newfd,
						ev.tgt.ioevs[2].iv, ev.tgt.ioevs[3].iv);
			}
			arcan_event_enqueue(ctx, &(arcan_event){
				.category = EVENT_VIDEO,
				.vid.kind = EVENT_VIDEO_DISPLAY_RESET,
				.vid.source = -2,
				.vid.width = ev.tgt.ioevs[2].iv
			});
		break;

/*
 * These will not actually be received as we can let the ashmif
 * library automatically handle suspend/resume
 */
		case TARGET_COMMAND_PAUSE:
		case TARGET_COMMAND_UNPAUSE:
		break;

		case TARGET_COMMAND_BUFFER_FAIL:
			nopass = true;
		break;

/*
 * Could be used with the switch appl- feature.
 */
		case TARGET_COMMAND_RESET:
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
					.vid.source = d - &disp[MAX_DISPLAYS-1]
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

