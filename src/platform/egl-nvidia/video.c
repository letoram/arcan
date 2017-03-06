/*
 * Not a serious video platform implementation, just pulling in the bare
 * minimum from aritgers repository (github.com/aritgler/) to test against. See
 * the tagged stream-ext-rollback for failed integration experiment
 */

/*
 * Copyright (c) 2016, NVIDIA CORPORATION. All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#include "utils.h"
#include "egl.h"
#include "kms.h"

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_shmif.h"
#include "arcan_event.h"

static char* synchopts[] = {
	"default", "skeleton driver has no synchronization strategy",
	NULL
};

static EGLDisplay eglDpy;
static EGLDeviceEXT eglDevice;
static int drmFd;
static uint32_t planeID = 0;
static EGLSurface eglSurface;
static arcan_vobj_id out_vid;
static size_t d_width, d_height;
static float txcos[8];
static size_t blackframes;
static uint64_t last;

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
	return eglGetProcAddress(sym);
}

bool platform_video_auth(int cardn, unsigned token)
{
	return false;
}

void platform_video_minimize()
{
}

int platform_video_cardhandle(int cardn)
{
	return -1;
}

void platform_video_synch(uint64_t tick_count, float fract,
	video_synchevent pre, video_synchevent post)
{
	long long start = arcan_timemillis();
	if (pre)
		pre();

	arcan_vobject* vobj = arcan_video_getobject(out_vid);
	if (!vobj){
		out_vid = ARCAN_VIDEO_WORLDID;
		vobj = arcan_video_getobject(ARCAN_VIDEO_WORLDID);
	}

	size_t nd;
	arcan_bench_register_cost( arcan_vint_refresh(fract, &nd) );
	agp_shader_id shid = agp_default_shader(BASIC_2D);

	agp_activate_rendertarget(NULL);
	if (blackframes){
		agp_rendertarget_clear();
		blackframes--;
	}

	if (vobj->program > 0)
		shid = vobj->program;

	agp_activate_vstore(out_vid == ARCAN_VIDEO_WORLDID ?
		arcan_vint_world() : vobj->vstore);

	agp_shader_activate(shid);

	agp_draw_vobj(0, 0, d_width, d_height, txcos, NULL);
	arcan_vint_drawcursor(false);

/*
 * NOTE: heuristic fix-point for direct- mapping dedicated source for
 * low latency here when we fix up internal syncing paths.
 */
	eglSwapBuffers(eglDpy, eglSurface);

/* With dynamic, we run an artificial vsync if the time between swaps
 * become to low. This is a workaround for a driver issue spotted on
 * nvidia and friends from time to time where multiple swaps in short
 * regression in combination with 'only redraw' adds bubbles */
	int delta = arcan_frametime() - last;
	if (delta >= 0 && delta < 8){
		arcan_timesleep(16 - delta);
	}

	last = arcan_frametime();

	if (post)
		post();
}

const char** platform_video_synchopts()
{
	return (const char**) synchopts;
}

static char** envopts[] = {
	NULL
};

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

void platform_video_query_displays()
{
}

bool platform_video_set_mode(platform_display_id disp, platform_mode_id mode)
{
	return disp == 0 && mode == 0;
}

size_t platform_video_displays(platform_display_id* dids, size_t* lim)
{
	if (dids && lim && *lim > 0){
		dids[0] = 0;
	}

	return 1;
}

struct monitor_mode* platform_video_query_modes(
	platform_display_id id, size_t* count)
{
	static struct monitor_mode mode = {};

	mode.width  = d_width;
	mode.height = d_height;
	mode.depth  = sizeof(av_pixel) * 8;
	mode.refresh = 60; /* should be queried */

	*count = 1;
	return &mode;
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
	size_t drawx = 0, drawy = 0;
	if (isrt){
		arcan_vint_applyhint(vobj, hint, vobj->txcos ? vobj->txcos :
			arcan_video_display.mirror_txcos, txcos,
			&drawx, &drawy,
			&d_width, &d_height,
			&blackframes);
	}
/* direct VOBJ mapping, prepared for indirect drawying so flip yhint */
	else {
		arcan_vint_applyhint(vobj,
		(hint & HINT_YFLIP) ? (hint & (~HINT_YFLIP)) : (hint | HINT_YFLIP),
		vobj->txcos ? vobj->txcos : arcan_video_display.default_txcos, txcos,
		&drawx, &drawy,
		&d_width, &d_height,
		&blackframes);
	}

	out_vid = id;
	return true;
}

struct monitor_mode platform_video_dimensions()
{
	struct monitor_mode res = {
		.width = d_width,
		.height = d_height
	};

/* any decent way to query for that value here? */
	res.phy_width = (float) d_width / ARCAN_SHMPAGE_DEFAULT_PPCM * 10.0;
	res.phy_height = (float) d_height / ARCAN_SHMPAGE_DEFAULT_PPCM * 10.0;

	return res;
}

bool platform_video_display_edid(platform_display_id did,
	char** out, size_t* sz)
{
	*out = NULL;
	*sz = 0;
	return false;
}

bool platform_video_specify_mode(platform_display_id disp,
	struct monitor_mode mode)
{
	return false;
}

enum dpms_state platform_video_dpms(
	platform_display_id disp, enum dpms_state state)
{
	return ADPMS_ON;
}

void platform_video_recovery()
{
}

bool platform_video_map_handle(struct storage_info_t* dst, int64_t handle)
{
	return false;
}

const char* platform_video_capstr()
{
	return "skeleton driver, no capabilities";
}

static void* lookup(void* tag, const char* sym, bool req)
{
	return eglGetProcAddress(sym);
}

struct agp_fenv* env;
bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames, const char* capt)
{
	GetEglExtensionFunctionPointers();

	int dw, dh;
	eglDevice = GetEglDevice();
	drmFd = GetDrmFd(eglDevice);
	SetMode(drmFd, &planeID, &dw, &dh);
	eglDpy = GetEglDisplay(eglDevice, drmFd);
	eglSurface = SetUpEgl(eglDpy, planeID, dw, dh);
	d_width = dw;
	d_height = dh;

	if (!env)
		env = agp_alloc_fenv(lookup, NULL);

	return true;
}
