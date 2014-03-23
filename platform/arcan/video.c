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
#define platform_video_ static inline egl_platform_video_
#include "../egl/video.c" 
#undef platform_video_

/* 2. interpose and map to shm */
#include <arcan_shmif.h>

static struct arcan_shmif_cont shms;
static struct arcan_evctx inevq, outevq;
static struct arcan_event ev;
static uint32_t* vidp;
static uint32_t* audp;

bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames)
{
	static first_init = true;

	if (first_init){
		shms = arcan_shmif_acquire(getenv("ARCAN_SHMKEY"), SHMIF_INPUT, true);	
		if (shms.addr == NULL){
			arcan_warning("couldn't connect to parent\n");
			return false;
		}

		if (!arcan_shmif_resize( &shms, width, height )){
			arcan_warning("couldn't set shm dimensions (%d, %d)\n", width, height);
			return false;
		}

		arcan_shmif_calcofs(shms.addr, (uint8_t**) &vidp, (uint8_t**) &audp);
		arcan_shmif_setevqs(shms.addr, &inevq, &outevq, false); 

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
	return egl_platform_video_init(width, height, bpp, fs, frames);
}

/*
 * These are just direct maps that will be statically sucked in
 */ 
void platform_video_shutdown()
{
	egl_platform_video_shutdown();
}

void platform_video_prepare_external()
{
	egl_platform_video_prepare_external();
}

void platform_video_restore_external()
{
	egl_platform_video_restore_external();
}

void platform_video_bufferswap()
{
	glFlush();
/* now our color attachment contains the final picture,
 * if we have access to inter-process texture sharing, we can just fling 
 * the FD, for now, readback into the shmpage */

	glReadPixels(0, 0, shms.width, shms.height, 
		GL_RGBA, GL_UNSIGNED_BYTE, vidp);

	arcan_shmif_signal(&shms.shmcont, SHMIF_SIGVID);	
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
