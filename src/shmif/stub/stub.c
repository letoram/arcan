#define HAVE_ARCAN_SHMIF_HELPER
#include "../arcan_shmif.h"

bool arcan_shmifext_headless_egl(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag)
{
	return false;
}

bool arcan_shmifext_headless_vk(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag)
{
	return false;
}

unsigned arcan_shmifext_eglsignal(struct arcan_shmif_cont* con,
	uintptr_t context, int mask, uintptr_t tex_id, ...)
{
	return 0;
}

unsigned arcan_shmifext_vksignal(struct arcan_shmif_cont* con,
	uintptr_t context, int mask, uintptr_t tex_id, ...)
{
	return 0;
}
