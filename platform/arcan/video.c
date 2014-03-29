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

/* 1. we re-use the EGL platform with a little hack */

#ifdef SDL_PLATFORM
#define SDL_MINI_SUFFIX static inline ext
#include "../sdl/video_mini.c"
#else
#define EGL_SUFFIX static inline ext
#include "../egl/video.c" 
#endif

/* 2. interpose and map to shm */
#include <arcan_shmif.h>
#include "arcan_math.h"
#include "arcan_general.h"

static struct arcan_shmif_cont shms;
static struct arcan_evctx inevq, outevq;
static struct arcan_event ev;
static uint32_t* vidp;
static uint32_t* audp;

bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames)
{
	static bool first_init = true;

	if (first_init){
		shms = arcan_shmif_acquire(
			getenv("ARCAN_SHMKEY"), SHMIF_INPUT, true, false);	

		if (shms.addr == NULL){
			arcan_warning("couldn't connect to parent\n");
			return false;
		}

		if (!arcan_shmif_resize( &shms, width, height )){
			arcan_warning("couldn't set shm dimensions (%d, %d)\n", width, height);
			return false;
		}

		arcan_shmif_calcofs(shms.addr, (uint8_t**) &vidp, (uint8_t**) &audp);
		arcan_shmif_setevqs(shms.addr, shms.esem, &inevq, &outevq, false); 

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
	return ext_video_init(width, height, bpp, fs, frames);
}

/*
 * These are just direct maps that will be statically sucked in
 */ 
void platform_video_shutdown()
{
	ext_video_shutdown();
}

void platform_video_prepare_external()
{
	ext_video_prepare_external();
}

void platform_video_restore_external()
{
	ext_video_restore_external();
}

void platform_video_timing(float* os, float* std, float* ov)
{
	*os = 16.667;
	*std = 0.0;
	*ov = 0.0;
}

void platform_video_bufferswap()
{
	glFlush();
/* now our color attachment contains the final picture,
 * if we have access to inter-process texture sharing, we can just fling 
 * the FD, for now, readback into the shmpage */

	glReadPixels(0, 0, shms.addr->w, shms.addr->h, 
		GL_RGBA, GL_UNSIGNED_BYTE, vidp);

	arcan_shmif_signal(&shms, SHMIF_SIGVID);	
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

const char* arcan_event_devlabel(int devid)
{
	return "no device";
}

void platform_event_process(arcan_evctx* ctx)
{
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

/*
 * missing; for the event-queue, we just reuse the queuetransfer(!)
 * routine to move things between the shared memory event-queue
 *
 * -- we don't propagate much upwards 
 *
 * for the audio support, we re-use openAL soft with a patch to
 * existing backends to just expose a single device with properties
 * matching the shmif constants, write into the audp and voila!
 */
