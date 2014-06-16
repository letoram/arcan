/*
 * This file should define the generic types (and possibly header files)
 * needed for building / porting to a different platform.
 *
 * In addition, the video and event layers will also need to be implemented.
 */ 

#ifndef HAVE_PLATFORM_HEADER
#define HAVE_PLATFORM_HEADER

#define BADFD -1
#include <pthread.h>
#include <semaphore.h>

typedef int pipe_handle;
typedef int file_handle;
typedef pid_t process_handle;
typedef sem_t* sem_handle;

int arcan_sem_post(sem_handle sem);
int arcan_sem_unlink(sem_handle sem, char* key);
int arcan_sem_wait(sem_handle sem);
int arcan_sem_trywait(sem_handle sem);
int arcan_sem_init(sem_handle*, unsigned value);
int arcan_sem_destroy(sem_handle);

typedef int8_t arcan_errc;
typedef long long arcan_vobj_id;
typedef int arcan_aobj_id;

long long int arcan_timemillis();
void arcan_timesleep(unsigned long);

/*void platform_video_bufferswap();
bool platform_video_init(uint16_t w, uint16_t h, uint8_t bpp, bool fs,
	bool frames);
void platform_video_timing(float* vsync, float* stddev, float* variance);
void platform_video_minimize();
long long int arcan_timemillis();
*/
#endif
