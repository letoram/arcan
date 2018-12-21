/*
 * No copyright claimed, Public Domain
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_shmif.h"
#include "arcan_event.h"

static SDL_Surface* screen;
static int sdlarg;

static enum {
	DEFAULT = 0,
	ENDMARKER
} synchopt;

void platform_video_shutdown()
{
}

void platform_video_prepare_external()
{
}

void platform_video_restore_external()
{
}

void* platform_video_gfxsym(const char* sym)
{
	return SDL_GL_GetProcAddress(sym);
}

void platform_video_minimize()
{
}

void platform_video_reset(int id, int swap)
{
}

void platform_video_synch(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

	size_t nd;
	arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );

	agp_activate_rendertarget(NULL);

	if (nd > 0){
		arcan_vint_drawrt(arcan_vint_world(), 0, 0,
			arcan_video_display.width, arcan_video_display.height
		);
	}

	arcan_vint_drawcursor(true);
	arcan_vint_drawcursor(false);

	if (post)
		post();
}

bool platform_video_auth(int cardn, unsigned token)
{
	return false;
}

int platform_video_cardhandle(int cardn)
{
	return -1;
}

static void envopts[] = {
	NULL
};

const char** platform_video_envopts()
{
	return (const char**) envopts;
}

platform_display_id* platform_video_query_displays(size_t* count)
{
	static platform_display_id id = 0;
	*count = 1;
	return &id;
}

bool platform_video_set_mode(platform_display_id disp, platform_mode_id mode)
{
	return disp == 0 && mode == 0;
}

struct monitor_modes* platform_video_query_modes(
	platform_display_id id, size_t* count)
{
	static struct monitor_modes mode = {};

	mode.width  = arcan_video_display.width;
	mode.height = arcan_video_display.height;
	mode.depth  = sizeof(av_pixel) * 8;
	mode.refresh = 60; /* should be queried */

	*count = 1;
	return &mode;
}

bool platform_video_map_display(arcan_vobj_id id, platform_display_id disp)
{
	return false; /* no multidisplay /redirectable output support */
}

const char* platform_video_capstr()
{
	return "skeleton driver, no capabilities";
}

void platform_video_preinit()
{
}

bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames, const char* capt)
{
	return true;
}
