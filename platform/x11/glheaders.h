/*
 * Long-term, the hope is that EGL will be the adopted interface
 * for basic context management / setup. The underlying platform
 * driver supports most necessary permutations;
 * (X11 + EGL  + GLEW + GL2+)
 * (X11 + GLEW + GL2+)
 * (X11 + EGL  + GLES2+)
 * (DRM + EGL  + GLES2+)
 */
#ifndef ARCAN_GLHEADER
#define ARCAN_GLHEADER

#define GLEW_STATIC
#define GL_GLEXT_PROTOTYPES 1
#include <glew.h>
#include <glxew.h>

bool platform_video_init(uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames);

void platform_video_bufferswap();
void platform_video_shutdown();
void platform_video_timing(float* vsync, float* stddev, float* variance);
void platform_video_minimize();
long long int arcan_timemillis();

#endif
