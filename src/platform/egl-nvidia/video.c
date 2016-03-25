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
#
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
static int drmFd, d_width, d_height;
static uint32_t planeID = 0;
static EGLSurface eglSurface;

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

void platform_video_minimize()
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
		arcan_vint_drawrt(arcan_vint_world(), 0, 0, d_width, d_height);
		eglSwapBuffers(eglDpy, eglSurface);
	}

	arcan_vint_drawcursor(true);
	arcan_vint_drawcursor(false);

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

void platform_video_query_displays()
{
}

bool platform_video_set_mode(platform_display_id disp, platform_mode_id mode)
{
	return disp == 0 && mode == 0;
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
	return false; /* no multidisplay /redirectable output support */
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

bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames, const char* capt)
{
	GetEglExtensionFunctionPointers();

	eglDevice = GetEglDevice();
	drmFd = GetDrmFd(eglDevice);
	SetMode(drmFd, &planeID, &d_width, &d_height);
	eglDpy = GetEglDisplay(eglDevice, drmFd);
	eglSurface = SetUpEgl(eglDpy, planeID, d_width, d_height);

	return true;
}
