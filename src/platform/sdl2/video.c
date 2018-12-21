/*
 * Copyright 2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: Quick and dirty port of the old SDL1.2 platform, missing a lot
 * of the low-level graphics integration again. Looking at the capabilities of
 * SDL2, we should be able to implement a lot more of the same functionality as
 * egl-dri has, including handle passing and so on, but perhaps really not
 * worth the effort. It might be worth looking into simply for the idea of not
 * having to write a wayland client backend.
 *
 * Progress / missing:
 * 1. synch- strategy swapping
 * 2. resize- management
 * 3. dynamic display settings
 * 4. handle mapping (this needs platform specific ifdefs etc.
 *    but principally dma-buf + iostreams + ... could be used)
 */
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#include <SDL.h>
#include <SDL_video.h>
#include <SDL_opengl.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_shmif.h"
#include "arcan_event.h"

static struct {
	SDL_Window* screen;
	int sdlarg;
	char* caption;
	size_t canvasw, canvash;
	size_t draww, drawh, drawx, drawy;
	arcan_vobj_id vid;
	size_t blackframes;
	uint64_t last;
	float txcos[8];
} sdl = {
	.blackframes = 2
};

static char* envopts[] = {
	"ARCAN_VIDEO_MULTISAMPLES=1", "attempt to enable multisampling",
	NULL
};

void platform_video_shutdown()
{
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	SDL_GL_SwapWindow(sdl.screen);
	SDL_DestroyWindow(sdl.screen);
	SDL_QuitSubSystem(SDL_INIT_VIDEO);
}

void platform_video_prepare_external()
{
	SDL_DestroyWindow(sdl.screen);
	if (arcan_video_display.fullscreen)
		SDL_QuitSubSystem(SDL_INIT_VIDEO);
}

SDL_Window* sdl2_platform_activewnd()
{
	return sdl.screen;
}

static bool rebuild_screen()
{
	char caption[64] = {0};

/* some GL attributes have to be set before creating the video-surface */
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
	SDL_ShowCursor(SDL_DISABLE);

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

	sdl.screen = SDL_CreateWindow(
		sdl.caption, SDL_WINDOWPOS_UNDEFINED,
		SDL_WINDOWPOS_UNDEFINED, sdl.canvasw, sdl.canvash,
		sdl.sdlarg
	);
	if (!sdl.screen)
		return false;

	int w, h;
	SDL_GL_GetDrawableSize(sdl.screen, &w, &h);
	sdl.canvasw = w;
	sdl.canvash = h;
	sdl.draww = w;
	sdl.drawh = h;

	SDL_GL_CreateContext(sdl.screen);
	glViewport(0, 0, sdl.canvasw, sdl.canvash);

	return true;
}

void platform_video_reset(int id, int swap)
{
}

void platform_video_restore_external()
{
	if (arcan_video_display.fullscreen)
		SDL_Init(SDL_INIT_VIDEO);

	int counter = 10;
	while (!rebuild_screen()){
		arcan_warning("Failed to rebuild- screen after restore"
			", retrying - tries: (%d)\n", counter--);
		sleep(1);
		if (counter == 0)
			exit(EXIT_FAILURE);
	}
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

void* platform_video_gfxsym(const char* sym)
{
	return SDL_GL_GetProcAddress(sym);
}

void platform_video_minimize()
{
}

void platform_video_synch(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	if (pre)
		pre();

	arcan_vobject* vobj = arcan_video_getobject(sdl.vid);
	if (!vobj){
		sdl.vid = ARCAN_VIDEO_WORLDID;
		vobj = arcan_video_getobject(ARCAN_VIDEO_WORLDID);
	}

	size_t nd;
	arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );
	agp_shader_id shid = agp_default_shader(BASIC_2D);

	agp_activate_rendertarget(NULL);
	if (sdl.blackframes){
		agp_rendertarget_clear();
		sdl.blackframes--;
	}

	if (vobj->program > 0)
		shid = vobj->program;

	agp_activate_vstore(sdl.vid == ARCAN_VIDEO_WORLDID ?
		arcan_vint_world() : vobj->vstore);

	agp_shader_activate(shid);

	agp_draw_vobj(sdl.drawx, sdl.drawy, sdl.draww, sdl.drawh, sdl.txcos, NULL);
	arcan_vint_drawcursor(false);

/*
 * NOTE: heuristic fix-point for direct- mapping dedicated source for
 * low latency here when we fix up internal syncing paths.
 */
	SDL_GL_SwapWindow(sdl.screen);

/* With dynamic, we run an artificial vsync if the time between swaps
 * become to low. This is a workaround for a driver issue spotted on
 * nvidia and friends from time to time where multiple swaps in short
 * regression in combination with 'only redraw' adds bubbles */
	int delta = arcan_frametime() - sdl.last;
	if (delta >= 0 && delta < 8){
		arcan_timesleep(16 - delta);
	}

	sdl.last = arcan_frametime();
	if (post)
		post();
}

const char** platform_video_envopts()
{
	return (const char**) envopts;
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

enum dpms_state platform_video_dpms(
	platform_display_id disp, enum dpms_state state)
{
	return ADPMS_ON;
}

bool platform_video_map_handle(struct agp_vstore* dst, int64_t handle)
{
	return false;
}

void platform_video_query_displays()
{
}

void platform_video_recovery()
{
}

bool platform_video_display_edid(platform_display_id did,
	char** out, size_t* sz)
{
	*out = NULL;
	*sz = 0;
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

	mode.width  = sdl.canvasw;
	mode.height = sdl.canvash;
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
	};

	float hdpi, vdpi, ddpi;
	if (0 == SDL_GetDisplayDPI(0, &ddpi, &hdpi, &vdpi) && hdpi && vdpi){
		res.phy_width = (float) res.width / hdpi * 25.0;
		res.phy_height = (float) res.height / vdpi * 25.0;
	}

	return res;
}

bool platform_video_map_display(arcan_vobj_id id, platform_display_id disp,
	enum blitting_hint hint)
{
	if (disp != 0)
		return false;

	arcan_vobject* vobj = arcan_video_getobject(id);
	bool isrt = arcan_vint_findrt(vobj) != NULL;

	if (vobj && vobj->vstore->txmapped != TXSTATE_TEX2D){
		arcan_warning("platform_video_map_display(), attempted to map a "
			"video object with an invalid backing store");
		return false;
	}

/*
 * The constant problem of what are we drawing and how are we drawing it
 * (rts were initially used for 3d models, vobjs were drawin with inverted ys
 * and world normally etc. a huge mess)
 */
	if (isrt){
		arcan_vint_applyhint(vobj, hint, vobj->txcos ? vobj->txcos :
			arcan_video_display.mirror_txcos, sdl.txcos,
			&sdl.drawx, &sdl.drawy,
			&sdl.draww, &sdl.drawh,
			&sdl.blackframes);
	}
/* direct VOBJ mapping, prepared for indirect drawying so flip yhint */
	else {
		arcan_vint_applyhint(vobj,
		(hint & HINT_YFLIP) ? (hint & (~HINT_YFLIP)) : (hint | HINT_YFLIP),
		vobj->txcos ? vobj->txcos : arcan_video_display.default_txcos, sdl.txcos,
		&sdl.drawx, &sdl.drawy,
		&sdl.draww, &sdl.drawh,
		&sdl.blackframes);
	}

	sdl.vid = id;
	return true;
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

void platform_video_preinit()
{
}

bool platform_video_init(uint16_t width, uint16_t height,
	uint8_t bpp, bool fs, bool frames, const char* capt)
{
	SDL_Init(SDL_INIT_VIDEO);

	sdl.canvasw = width;
	sdl.canvash = height;
	sdl.draww = width;
	sdl.drawh = height;
	if (sdl.caption)
		free(sdl.caption);
	sdl.caption = strdup(capt ? capt : "");

	arcan_video_display.fullscreen = fs;
	sdl.sdlarg = SDL_WINDOW_ALLOW_HIGHDPI |
		(fs ? SDL_WINDOW_FULLSCREEN_DESKTOP : SDL_WINDOW_RESIZABLE) |
		(frames ? SDL_WINDOW_BORDERLESS : 0);

	if (arcan_video_display.msasamples){
		if (!rebuild_screen()){
			arcan_warning("arcan_video_init(), Couldn't open OpenGL display,"
				"attempting without MSAA\n");
			setenv("ARCAN_VIDEO_MULTISAMPLES", "0", 1);
			SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 0);
			SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 0);
			rebuild_screen();
		}
	}
	else
		rebuild_screen();

	if (!sdl.screen)
		return false;

	sdl.vid = ARCAN_VIDEO_WORLDID;
	memcpy(sdl.txcos, arcan_video_display.mirror_txcos, sizeof(float) * 8);

	sdl.last = arcan_frametime();
	return true;
}
