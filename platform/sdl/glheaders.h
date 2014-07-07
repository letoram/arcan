/*
 * The glheaders_xxx headerfiles are
 * compile-time options for which support / wrapping library to use.
 * Given the wide variety in supported platforms, along with the stated
 * goal of keeping necessary dependencies and dynamic configurations
 * to a minimum, we opted for this approach when it comes to
 * GL, extensions, video context etc.
 */
#ifndef ARCAN_GLHEADER
#define ARCAN_GLHEADER

#define GLEW_STATIC
#define NO_SDL_GLEXT
#define GL_GLEXT_PROTOTYPES 1

#include <glew.h>

#ifdef WITH_HEADLESS
#include <glxew.h>
#endif

#include <SDL.h>
#include <SDL_opengl.h>
#include <SDL_byteorder.h>

bool platform_video_init(uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* caption);

void platform_video_bufferswap();
void platform_video_shutdown();

void platform_video_timing(float* vsync, float* stddev, float* variance);
void platform_video_minimize();
long long int arcan_timemillis();

#endif
