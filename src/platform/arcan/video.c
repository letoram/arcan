/* Arcan-fe (OS/device platform), scriptable front-end endinge
 *
 * Arcan-fe is the legal property of its developers, please refer to
 * the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
 */

/*
 * This implements using arcan-in-arcan, nested execution as part of
 * the hybrid mode (see engine design docs). We'll set up a GL
 * context, map to that the shared memory, do readbacks etc.
 */

/* We re-use X11/egl or other platforms with this little hack */
#define PLATFORM_SUFFIX lwa

#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>

#include "../video_platform.h"

#define WITH_HEADLESS
#include HEADLESS_PLATFORM

/* 2. interpose and map to shm */
#include "arcan_shmif.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

static char* synchopts[] = {
	"parent", "display server controls synchronisation",
	"pre-wake", "use the cost of and jitter from previous frames",
	"adaptive", "skip a frame if syncpoint is at risk",
	NULL
};

static enum {
	PARENT = 0,
	PREWAKE,
	ADAPTIVE
} syncopt;

static struct monitor_modes mmodes[] = {
	{
		.id = 0,
		.width = 640,
		.height = 480,
		.refresh = 60,
		.depth = GL_PIXEL_BPP_BIT
	},
};

static struct arcan_shmif_cont shms;
static struct {
	unsigned refresh;
} synch_vals;

bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames, const char* title)
{
	static bool first_init = true;

	if (width == 0 || height == 0){
		width = 640;
		height = 480;
	}

	if (first_init){
		const char* connkey = getenv("ARCAN_CONNPATH");
		const char* shmkey = NULL;
		if (connkey){
			shmkey = arcan_shmif_connect(connkey, getenv("ARCAN_CONNKEY"));
			if (!shmkey)
				arcan_warning("Couldn't connect through (%s), "
					"trying ARCAN_SHMKEY env.\n", connkey);
		}

		if (!shmkey)
			shmkey = getenv("ARCAN_SHMKEY");

		if (!shmkey){
			arcan_warning("platform/arcan/video.c:platform_video_init(): "
				"no connection key found, giving up. (see environment ARCAN_CONNPATH)\n");
			return false;
		}
		shms = arcan_shmif_acquire(shmkey, SEGID_LWA, SHMIF_ACQUIRE_FATALFAIL);

		if (shms.addr == NULL){
			arcan_warning("couldn't connect to parent\n");
			return false;
		}

		const char* argstr = getenv("ARCAN_ARG");
		struct arg_arr* args = argstr ? arg_unpack(argstr) : NULL;

		if (argstr){
			const char* val;
			if (arg_lookup(args, "width", 0, &val))
				width = strtoul(val, NULL, 10);
			if (arg_lookup(args, "height", 0, &val))
				height = strtoul(val, NULL, 10);
		}

		shms.addr->glsource = true;
		if (!arcan_shmif_resize( &shms, width, height )){
			arcan_warning("couldn't set shm dimensions (%d, %d)\n", width, height);
			return false;
		}

		first_init = false;
	}
	else {
		if (!arcan_shmif_resize( &shms, width, height )){
			arcan_warning("couldn't set shm dimensions (%d, %d)\n", width, height);
			return false;
		}
	}

/*
 * currently, we actually never de-init this
 */
	arcan_shmif_setprimary(SHMIF_INPUT, &shms);
	return lwa_video_init(width, height, bpp, fs, frames, title);
}

/*
 * These are just direct maps that will be statically sucked in
 */
void platform_video_shutdown()
{
	lwa_video_shutdown();
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

const char** platform_video_synchopts()
{
	return (const char**) synchopts;
}

static struct monitor_modes* get_platform_mode(platform_mode_id mode)
{
	for (size_t i = 0; i < sizeof(mmodes)/sizeof(mmodes[0]); i++){
		if (mmodes[i].id == mode)
			return &mmodes[i];
	}

	return NULL;
}

bool platform_video_set_mode(platform_display_id disp, platform_mode_id newmode)
{
	struct monitor_modes* mode = get_platform_mode(newmode);
	if (!mode)
		return false;

	if (arcan_shmif_resize(&shms, mode->width, mode->height))
	{
		arcan_video_display.width = mode->width;
		arcan_video_display.height = mode->height;
		synch_vals.refresh = mode->refresh;
		return true;
	}

	return false;
}

bool platform_video_map_display(arcan_vobj_id id, platform_display_id disp)
{
	return false;
}

static void stub()
{
}

struct monitor_modes* platform_video_query_modes(
	platform_display_id id, size_t* count)
{
	*count = sizeof(mmodes) / sizeof(mmodes[0]);

	return mmodes;
}

platform_display_id* platform_video_query_displays(size_t* count)
{
	static platform_display_id id;
	*count = 1;
	return &id;
}

void platform_video_synch(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	lwa_video_synch(tick_count, fract, pre, stub);

	struct storage_info_t store = *arcan_vint_world();

	store.vinf.text.raw = shms.vidp;
	agp_readback_synchronous(&store);

/*
 * we should implement a mapping for TARGET_COMMAND_FRAMESKIP or so
 * and use to set virtual display timings. ioev[0] => mode, [1] => prewake,
 * [2] => preaudio, 3/4 for desired jitter (testing / simulation)
 */
	arcan_shmif_signal(&shms, SHMIF_SIGVID);

	if (post)
		post();
}

/*
 * The regular event layer is just stubbed, when the filtering etc.
 * is broken out of the platform layer, we can re-use that to have
 * local filtering untop of the one the engine is doing.
 */
arcan_errc arcan_event_analogstate(int devid, int axisid,
	int* lower_bound, int* upper_bound, int* deadzone,
	int* kernel_size, enum ARCAN_ANALOGFILTER_KIND* mode)
{
	return ARCAN_ERRC_UNACCEPTED_STATE;
}

void arcan_event_analogall(bool enable, bool mouse)
{
}

void arcan_event_analogfilter(int devid,
	int axisid, int lower_bound, int upper_bound, int deadzone,
	int buffer_sz, enum ARCAN_ANALOGFILTER_KIND kind)
{
}

const char* platform_video_capstr()
{
	return "Video Platform (Arcan - in - Arcan)\n";
}

const char* arcan_event_devlabel(int devid)
{
	return "no device";
}

void platform_event_process(arcan_evctx* ctx)
{
	arcan_event ev;

/*
 * Most events can just be added to the local queue,
 * but we want to handle some of the target commands separately
 * (with a special path to LUA and a different hook)
 */
	while (1 == arcan_event_poll(&shms.inev, &ev))
		if (ev.category == EVENT_TARGET)
		switch(ev.kind){
/*
 * Should write a way to serialize the state of the entire engine,
 * both as a quality indicator, a way to do live desktop migrations
 */
		case TARGET_COMMAND_FDTRANSFER:
			arcan_warning("platform(arcan): fdtransfer not implemented\n");
		break;

		case TARGET_COMMAND_NEWSEGMENT:
			arcan_warning("multi-window received\n");
		break;

/*
 * Should only do something if we've set the SKIPMODE to single stepping
 */
		case TARGET_COMMAND_STEPFRAME:
		break;

/*
 * We might have loading threads still going etc.
 */
		case TARGET_COMMAND_PAUSE:
		case TARGET_COMMAND_UNPAUSE:
		break;

/*
 * Could be used with the switch-theme functionality
 */
		case TARGET_COMMAND_RESET:
		break;

		case TARGET_COMMAND_EXIT:
			ev.category = EVENT_SYSTEM;
			ev.kind = EVENT_SYSTEM_EXIT;
			arcan_event_enqueue(ctx, &ev);

/* unlock no matter what so parent can't lock us out */
			arcan_sem_post(shms.vsem);
		break;
		}
		else
			arcan_event_enqueue(ctx, &ev);
}

void arcan_event_rescan_idev(arcan_evctx* ctx)
{
}

void platform_key_repeat(arcan_evctx* ctx, unsigned int rate)
{
}

void platform_event_deinit(arcan_evctx* ctx)
{
}

void platform_device_lock(int devind, bool state)
{
}

void platform_event_init(arcan_evctx* ctx)
{
}

