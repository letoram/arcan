#ifndef HAVE_PLATFORM_HEADER
#define HAVE_PLATFORM_HEADER

int arcan_sem_trywait(sem_handle);
int arcan_sem_init(sem_handle*, unsigned value);
int arcan_sem_destroy(sem_handle);

void platform_video_bufferswap();
bool platform_video_init(uint16_t w, uint16_t h, uint8_t bpp, bool fs,
	bool frames);
void platform_video_timing(float* vsync, float* stddev, float* variance);
void platform_video_minimize();
long long int arcan_timemillis();

#endif
