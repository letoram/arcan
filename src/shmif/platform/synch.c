#include <arcan_shmif.h>
#include <pthread.h>
#include "shmif_platform.h"

int shmif_platform_sync_post(struct arcan_shmif_page* P, int slot)
{
	if (slot & SYNC_EVENT)
		P->esync = 0xffffffff;

	if (slot & SYNC_VIDEO)
		P->vsync = 0xffffffff;

	if (slot & SYNC_AUDIO)
		P->async = 0xffffffff;

	return 1;
}

int shmif_platform_sync_wait(struct arcan_shmif_page* P, int slot)
{
	volatile uint32_t* volatile addr;
	if (slot & SYNC_EVENT){
		addr = &P->esync;
		while (*addr)
			arcan_timesleep(1);
	}
	if (slot & SYNC_VIDEO){
		addr = &P->vsync;
		while (*addr)
			arcan_timesleep(1);
	}
	if (slot & SYNC_AUDIO){
		addr = &P->async;
		while (*addr)
			arcan_timesleep(1);
	}

	return 1;
}

int shmif_platform_sync_trywait(struct arcan_shmif_page* P, int slot)
{
	int rv = 1;
	if (slot & SYNC_EVENT)
		rv = P->esync == 0;
	if (slot & SYNC_VIDEO)
		rv = P->vsync == 0;
	if (slot & SYNC_AUDIO)
		rv = P->async == 0;
	return rv;
}
