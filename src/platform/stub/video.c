
/*
 * No copyright claimed, Public Domain
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <unistd.h>
#include <dlfcn.h>
#include <stdio.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_shmif.h"
#include "arcan_event.h"

#include "../platform.h"

static size_t g_width;
static size_t g_height;

static char* envopts[] = {
	NULL
};

void platform_video_shutdown()
{
}

size_t platform_video_decay()
{
	return 0;
}

void platform_video_prepare_external()
{
}

size_t platform_video_export_vstore(
	struct agp_vstore* vs, struct agp_buffer_plane* planes, size_t n)
{
	return false;
}

bool platform_video_map_buffer(
	struct agp_vstore* vs, struct agp_buffer_plane* planes, size_t n)
{
	return false;
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

	agp_activate_rendertarget(NULL);

	arcan_vint_drawcursor(true);
	arcan_vint_drawcursor(false);

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

bool platform_video_set_mode(platform_display_id disp,
	platform_mode_id mode, struct platform_mode_opts opts)
{
	return disp == 0 && mode == 0;
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

struct monitor_mode platform_video_dimensions()
{
	return (struct monitor_mode){
		.width = g_width,
		.height = g_height
	};
}

struct monitor_mode* platform_video_query_modes(
	platform_display_id id, size_t* count)
{
	static struct monitor_mode mode = {};

	mode.width  = g_width;
	mode.height = g_height;
	mode.depth  = sizeof(av_pixel) * 8;
	mode.refresh = 60; /* should be queried */

	*count = 1;
	return &mode;
}

void platform_video_invalidate_map(
	struct agp_vstore* vstore, struct agp_region region)
{
/* NOP for the time being - might change for direct forwarding of client */
}

bool platform_video_map_display(
	arcan_vobj_id id, platform_display_id disp, enum blitting_hint hint)
{
	return false; /* no multidisplay /redirectable output support */
}

ssize_t platform_video_map_display_layer(arcan_vobj_id vid,
	platform_display_id id, size_t layer_index, struct display_layer_cfg cfg)
{
	return -1;
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
	g_width = width;
	g_height = height;
	return true;
}
