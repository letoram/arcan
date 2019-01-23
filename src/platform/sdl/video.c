/*
 * Copyright 2003-2016, Björn Ståhl
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
		sdl.canvasw, sdl.canvash, sizeof(av_pixel), sdl.sdlarg);
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

void platform_video_reset(int id, int swap)
{
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

	arcan_vobject* vobj = arcan_video_getobject(sdl.vid);
	if (!vobj){
		sdl.vid = ARCAN_VIDEO_WORLDID;
		vobj = arcan_video_getobject(ARCAN_VIDEO_WORLDID);
	}

/* special case, lost WORLDID, draw direct on GL context */
	size_t nd;
	if (sdl.vid == ARCAN_VIDEO_WORLDID && !arcan_vint_worldrt()){
		agp_shader_envv(PROJECTION_MATR,
			arcan_video_display.default_projection, sizeof(float)*16);
		arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );
	}
	else {
		arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );
		agp_shader_id shid = agp_default_shader(BASIC_2D);
		agp_activate_rendertarget(NULL);
		if (sdl.blackframes){
			agp_rendertarget_clear();
			sdl.blackframes--;
		}
		if (vobj->program > 0)
			shid = vobj->program;

		agp_shader_activate(shid);
		agp_shader_envv(PROJECTION_MATR,
			arcan_video_display.window_projection, sizeof(float)*16);

		if (sdl.vid == ARCAN_VIDEO_WORLDID){
			agp_activate_vstore(arcan_vint_world());
		}
		else{
			agp_activate_vstore(vobj->vstore);
		}

		agp_draw_vobj(sdl.drawx, sdl.drawy, sdl.draww, sdl.drawh, sdl.txcos, NULL);
	}

	arcan_vint_drawcursor(false);

/*
 * NOTE: heuristic fix-point for direct- mapping dedicated source for
 * low latency here when we fix up internal syncing paths.
 */
	if (nd)
		SDL_GL_SwapBuffers();

/*
 * This is the 'legacy- approach' to synching and should be reworked
 * to match the changes inside the conductor
 */
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

/* any decent way to query for that value here? */
	res.phy_width = (float) res.width / ARCAN_SHMPAGE_DEFAULT_PPCM * 10.0;
	res.phy_height = (float) res.height / ARCAN_SHMPAGE_DEFAULT_PPCM * 10.0;

	return res;
}

bool platform_video_map_display(arcan_vobj_id id,
	platform_display_id disp, enum blitting_hint hint)
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
			arcan_video_display.default_txcos, sdl.txcos,
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

	sdl.canvasw = width;
	sdl.canvash = height;
	sdl.draww = width;
	sdl.drawh = height;

	arcan_warning("Notice: [SDL] Video Info: %i, %i, hardware acceleration: %s, "
		"window manager: %s, MSAA: %i\n",
			vi->current_w, vi->current_h, vi->hw_available ? "yes" : "no",
			vi->wm_available ? "yes" : "no",
			arcan_video_display.msasamples);

/* some GL attributes have to be set before creating the video-surface */
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
	SDL_GL_SetAttribute(SDL_GL_SWAP_CONTROL, 0);
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

	glViewport(0, 0, width, height);
	sdl.vid = ARCAN_VIDEO_WORLDID;
	memcpy(sdl.txcos, arcan_video_display.mirror_txcos, sizeof(float) * 8);

	sdl.last = arcan_frametime();
	return true;
}
