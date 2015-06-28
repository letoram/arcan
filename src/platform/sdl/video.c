/*
 * Copyright 2003-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#include <SDL.h>
#include <SDL_opengl.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_shmif.h"
#include "arcan_event.h"

static struct {
	SDL_Surface* screen;
	int sdlarg;
	size_t mdispw, mdisph;
	size_t canvasw, canvash;
	uint64_t last;
} sdl;

static char* synchopts[] = {
	"dynamic", "herustic driven balancing latency, performance and utilization",
	"vsync", "let display vsync dictate speed",
	"processing", "minimal synchronization, prioritize speed",
	NULL
};

static char* envopts[] = {
	"ARCAN_VIDEO_MULTISAMPLES=1", "attempt to enable multisampling",
	NULL
};

static enum {
	DYNAMIC = 0,
	VSYNC = 1,
	PROCESSING = 2,
	ENDMARKER
} synchopt;

void platform_video_shutdown()
{
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	SDL_GL_SwapBuffers();
	SDL_FreeSurface(sdl.screen);
	SDL_QuitSubSystem(SDL_INIT_VIDEO);
}

void platform_video_prepare_external()
{
	SDL_FreeSurface(sdl.screen);
	if (arcan_video_display.fullscreen)
		SDL_QuitSubSystem(SDL_INIT_VIDEO);
}

void platform_video_restore_external()
{
	if (arcan_video_display.fullscreen)
		SDL_Init(SDL_INIT_VIDEO | SDL_INIT_NOPARACHUTE);

	sdl.screen = SDL_SetVideoMode(
		sdl.mdispw, sdl.mdisph, sizeof(av_pixel), sdl.sdlarg);
}

void* platform_video_gfxsym(const char* sym)
{
	return SDL_GL_GetProcAddress(sym);
}

void platform_video_minimize()
{
	SDL_WM_IconifyWindow();
}

int64_t platform_video_output_handle(struct storage_info_t* store,
	enum status_handle* status)
{
	*status = ERROR_UNSUPPORTED;
	return -1;
}

void platform_video_synch(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

	size_t nd;
	arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );

	agp_activate_rendertarget(NULL);
	arcan_vint_drawrt(arcan_vint_world(), 0, 0, sdl.mdispw, sdl.mdisph);
	arcan_vint_drawcursor(false);

	SDL_GL_SwapBuffers();

/* With dynamic, we run an artificial vsync if the time between swaps
 * become to low. This is a workaround for a driver issue spotted on
 * nvidia and friends from time to time where multiple swaps in short
 * regression in combination with 'only redraw' adds bubbles */
	int delta = arcan_frametime() - sdl.last;
	if (synchopt == DYNAMIC && delta >= 0 && delta < 8)
		arcan_timesleep(16 - delta);

	sdl.last = arcan_frametime();
	if (post)
		post();
}

const char** platform_video_synchopts()
{
	return (const char**) synchopts;
}

const char** platform_video_envopts()
{
	return (const char**) envopts;
}

void platform_video_setsynch(const char* arg)
{
	int ind = 0;

	while(synchopts[ind]){
		if (strcmp(synchopts[ind], arg) == 0){
			synchopt = (ind > 0 ? ind / 2 : ind);
			arcan_warning("synchronisation strategy set to (%s)\n", synchopts[ind]);
			break;
		}

		ind += 2;
	}
}

enum dpms_state platform_video_dpms(
	platform_display_id disp, enum dpms_state state)
{
	return ADPMS_ON;
}

bool platform_video_map_handle(struct storage_info_t* dst, int64_t handle)
{
	return false;
}

void platform_video_query_displays()
{
}

bool platform_video_specify_mode(platform_display_id disp,
	struct monitor_mode mode)
{
	return false;
}

bool platform_video_set_mode(platform_display_id disp, platform_mode_id mode)
{
	return disp == 0 && mode == 0;
}

struct monitor_mode* platform_video_query_modes(
	platform_display_id id, size_t* count)
{
	static struct monitor_mode mode = {};

	mode.width  = sdl.mdispw;
	mode.height = sdl.mdisph;
	mode.depth  = sizeof(av_pixel) * 8;
	mode.refresh = 60; /* should be queried */

	*count = 1;
	return &mode;
}

struct monitor_mode platform_video_dimensions()
{
	struct monitor_mode res = {
		.width = sdl.canvasw,
		.height = sdl.canvash,
		.phy_width = sdl.mdispw,
		.phy_height = sdl.mdisph
	};
	return res;
}

bool platform_video_map_display(arcan_vobj_id id, platform_display_id disp,
	enum blitting_hint hint)
{
	return false; /* no multidisplay /redirectable output support */
}

bool platform_video_display_id(platform_display_id id,
	platform_mode_id mode_id, struct monitor_mode mode)
{
	return false;
}

const char* platform_video_capstr()
{
	static char* capstr;

	if (!capstr){
		const char* vendor = (const char*) glGetString(GL_VENDOR);
		const char* render = (const char*) glGetString(GL_RENDERER);
		const char* version = (const char*) glGetString(GL_VERSION);
		const char* shading = (const char*)glGetString(GL_SHADING_LANGUAGE_VERSION);
		const char* exts = (const char*) glGetString(GL_EXTENSIONS);

		size_t interim_sz = 64 * 1024;
		char* interim = malloc(interim_sz);
		size_t nw = snprintf(interim, interim_sz, "Video Platform (SDL)\n"
			"Vendor: %s\nRenderer: %s\nGL Version: %s\n"
			"GLSL Version: %s\n\n Extensions Supported: \n%s\n\n",
			vendor, render, version, shading, exts
		) + 1;

		if (nw < (interim_sz >> 1)){
			capstr = malloc(nw);
			memcpy(capstr, interim, nw);
			free(interim);
		}
		else
			capstr = interim;
	}

	return capstr;
}

bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames, const char* capt)
{
	char caption[64] = {0};
	SDL_Init(SDL_INIT_VIDEO);

	const SDL_VideoInfo* vi = SDL_GetVideoInfo();
	if (!vi){
		arcan_fatal("SDL_GetVideoInfo() failed, broken display subsystem.");
	}

	if (width == 0)
		width = vi->current_w;

	if (height == 0)
		height = vi->current_h;

	arcan_warning("Notice: [SDL] Video Info: %i, %i, hardware acceleration: %s, "
		"window manager: %s, MSAA: %i\n",
			vi->current_w, vi->current_h, vi->hw_available ? "yes" : "no",
			vi->wm_available ? "yes" : "no",
			arcan_video_display.msasamples);

/* some GL attributes have to be set before creating the video-surface */
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
	SDL_GL_SetAttribute(SDL_GL_SWAP_CONTROL, synchopt == PROCESSING ? 0 : 1);
	SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 1);
	SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 16);

	int msasamples = 0;

	const char* msenv;
	if ( (msenv = getenv("ARCAN_VIDEO_MULTISAMPLES")) ){
		msasamples = (int) strtol(msenv, NULL, 10);
	}

	if (msasamples > 0){
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 1);
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, msasamples);
	}

	snprintf(caption, 63, "%s", capt);
	SDL_WM_SetCaption(caption, "Arcan");

	arcan_video_display.fullscreen = fs;
	sdl.sdlarg = (fs ? SDL_FULLSCREEN : 0) |
		SDL_OPENGL | (frames ? SDL_NOFRAME : 0);
	sdl.screen = SDL_SetVideoMode(width, height, bpp, sdl.sdlarg);

	if (msasamples && !sdl.screen){
		arcan_warning("arcan_video_init(), Couldn't open OpenGL display,"
			"attempting without MSAA\n");
		setenv("ARCAN_VIDEO_MULTISAMPLES", "0", 1);
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 0);
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 0);
		sdl.screen = SDL_SetVideoMode(width, height, bpp, sdl.sdlarg);
	}

	if (!sdl.screen)
		return false;

	sdl.canvasw = sdl.mdispw = width;
	sdl.canvash = sdl.mdisph = height;
	glViewport(0, 0, width, height);
	sdl.last = arcan_frametime();
	return true;
}
