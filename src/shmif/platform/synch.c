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

#ifdef __LINUX
#include <linux/futex.h>
#include <sys/syscall.h>
int shmif_platform_sync_wait(struct arcan_shmif_page* P, int slot)
{
	if ((slot & SYNC_EVENT) && P->esync){
		syscall(SYS_futex, &P->esync, FUTEX_WAIT, 0xffffffff);
	}

	if ((slot & SYNC_VIDEO) && P->vsync){
		syscall(SYS_futex, &P->vsync, FUTEX_WAIT, 0xffffffff);
	}

	if ((slot & SYNC_AUDIO) && P->async){
		syscall(SYS_futex, &P->vsync, FUTEX_WAIT, 0xffffffff);
	}

	return 1;
}

/*
 * The desired behaviour here is part of the resize- loop where there is a
 * shorter (~vblank) period where it might be blocking, but at the same time
 * don't want to wait indefinitely. The actual timeout should really be set to
 * a possible OUTPUTHINT but the savings are maginal.
 *
 * Previously, when this used semaphores, it was for NONBLOCK signalling where
 * we still needed the semaphore to have the correct value. That is no longer a
 * concern.
 */
int shmif_platform_sync_trywait(struct arcan_shmif_page* P, int slot)
{
	int rv = 1;
	struct timespec req =
	{
		.tv_nsec = 1000000
	};

	if ((slot & SYNC_EVENT) && P->esync){
		syscall(SYS_futex, &P->esync, FUTEX_WAIT, 0xffffffff, &req);
		if (P->esync)
			rv = 0;
	}

	if ((slot & SYNC_VIDEO) && P->vsync){
		syscall(SYS_futex, &P->vsync, FUTEX_WAIT, 0xffffffff, &req);
		if (P->vsync)
			rv = 0;
	}

	if ((slot & SYNC_AUDIO) && P->async){
		syscall(SYS_futex, &P->vsync, FUTEX_WAIT, 0xffffffff, &req);
		if (P->async)
			rv = 0;
	}

	return rv;
}

#else
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
#endif
