#define WANT_ARCAN_SHMIF_HELPER
#include "../arcan_shmif.h"
#include "../shmif_privext.h"

struct arcan_shmifext_setup arcan_shmifext_headless_defaults()
{
	return (struct arcan_shmifext_setup){};
}

enum shmifext_setup_status arcan_shmifext_headless_setup(
	struct arcan_shmif_cont* con,
	struct arcan_shmifext_setup arg)
{
	return SHMIFEXT_NO_API;
}

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

int arcan_shmifext_eglsignal(struct arcan_shmif_cont* con,
	uintptr_t display, int mask, uintptr_t tex_id, ...)
{
	return -1;
}

int arcan_shmifext_vksignal(struct arcan_shmif_cont* con,
	uintptr_t display, int mask, uintptr_t tex_id, ...)
{
	return -1;
}
