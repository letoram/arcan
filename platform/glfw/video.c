#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#include "glheaders.h"

#include "../../arcan_math.h"
#include "../../arcan_general.h"
#include "../../arcan_video.h"
#include "../../arcan_videoint.h"

static GLFWwindow* screen; 
static bool screen_hidden;

void platform_video_shutdown()
{
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	if (screen)
		glfwDestroyWindow(screen);
	screen = NULL;
	glfwTerminate();
}

void platform_video_prepare_external()
{
	glfwTerminate();
}

void platform_video_restore_external()
{
/* restore_ won't be called without a prepare,
 * we assume that the if we could create the window once,
 * it can be repeated */
	glfwInit();
}

void platform_video_bufferswap()
{
	glfwSwapBuffers(screen);
}

void platform_video_minimize()
{
	if (screen_hidden)
		glfwShowWindow(screen);
	else
		glfwHideWindow(screen);

	screen_hidden = !screen_hidden;
}

void platform_video_timing(float* o_sync, float* o_stddev, float* o_variance)
{
	static float sync, stddev, variance;
	static bool gottiming;

	if (!gottiming){
		platform_video_bufferswap();
	
		int retrycount = 0;

/* 
 * try to get a decent measurement of actual timing, this is not really used for
 * synchronization but rather as a guess of we're actually vsyncing and how 
 * processing should be scheduled in relation to vsync, or if we should yield at
 * appropriate times.
 */

		const int nsamples = 10;
		long long int samples[nsamples], sample_sum;

retry:
		sample_sum = 0;
		for (int i = 0; i < nsamples; i++){
			long long int start = arcan_timemillis();
			platform_video_bufferswap();
			long long int stop = arcan_timemillis();
			samples[i] = stop - start;
			sample_sum += samples[i];
		}

		sync = (float) sample_sum / (float) nsamples;
		variance = 0.0;
		for (int i = 0; i < nsamples; i++){
			variance += powf(sync - (float)samples[i], 2);
		}
		stddev = sqrtf(variance / (float) nsamples);
		if (stddev > 0.5){
			retrycount++;
			if (retrycount > 10)
				arcan_video_display.vsync_timing = 16.667; /* give up and just revert */
			else
				goto retry;
		}
	}

	*o_sync = sync;
	*o_stddev = stddev;
	*o_variance = variance;
}

bool platform_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames)
{
/*	if (width == 0)
		width = vi->current_w;

	if (height == 0)
		height = vi->current_h;
*/

/*
 * check for / use 
 *  WGL_EXT_swap_control_tear
 */

	screen = glfwCreateWindow(width, height, 
		"ARCAN", 
		NULL, /* display preferences */
		NULL /*share*/
	);

//	glfwSetSwapInterval(1);
	arcan_video_display.pbo_support = 
		arcan_video_display.fbo_support = true;

	arcan_video_display.width  = width;
	arcan_video_display.height = height;
	arcan_video_display.bpp    = bpp;

	return true;
}


