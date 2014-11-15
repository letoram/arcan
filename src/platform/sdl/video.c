/* Arcan-fe (OS/device platform), scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the platform/LICENSE file distributed with this source distribution
 * for licensing terms.
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

static SDL_Surface* screen;
static int sdlarg;

static char* synchopts[] = {
	"dynamic", "herustic driven balancing latency, performance and utilization",
	"vsync", "let display vsync dictate speed",
	"processing", "minimal synchronization, prioritize speed",
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
	SDL_FreeSurface(screen);
	SDL_QuitSubSystem(SDL_INIT_VIDEO);
}

void platform_video_prepare_external()
{
	SDL_FreeSurface(screen);
	if (arcan_video_display.fullscreen)
		SDL_QuitSubSystem(SDL_INIT_VIDEO);
}

void platform_video_restore_external()
{
	if (arcan_video_display.fullscreen)
		SDL_Init(SDL_INIT_VIDEO | SDL_INIT_NOPARACHUTE);

	screen = SDL_SetVideoMode(arcan_video_display.width,
		arcan_video_display.height,
		arcan_video_display.bpp,
		sdlarg);
}

void* platform_video_gfxsym(const char* sym)
{
	return SDL_GL_GetProcAddress(sym);
}

void platform_video_minimize()
{
	SDL_WM_IconifyWindow();
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

	SDL_GL_SwapBuffers();

	if (post)
		post();
}

const char** platform_video_synchopts()
{
	return (const char**) synchopts;
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
	mode.depth  = GL_PIXEL_BPP * 8;
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

	if (arcan_video_display.msasamples > 0){
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 1);
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES,
		arcan_video_display.msasamples);
	}

	snprintf(caption, 63, "%s", capt);
	SDL_WM_SetCaption(caption, "Arcan");

	arcan_video_display.fullscreen = fs;
	sdlarg = (fs ? SDL_FULLSCREEN : 0) |
		SDL_OPENGL | (frames ? SDL_NOFRAME : 0);
	screen = SDL_SetVideoMode(width, height, bpp, sdlarg);

	if (arcan_video_display.msasamples && !screen){
		arcan_warning("arcan_video_init(), Couldn't open OpenGL display,"
			"attempting without MSAA\n");
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 0);
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 0);
		arcan_video_display.msasamples = 0;
		screen = SDL_SetVideoMode(width, height, bpp, sdlarg);
	}

	if (!screen)
		return false;

/* need to be called AFTER we have a valid GL context,
 * else we get the "No GL version" */
	arcan_video_display.width  = width;
	arcan_video_display.height = height;
	arcan_video_display.bpp    = bpp;
	glViewport(0, 0, width, height);

	return true;
}


