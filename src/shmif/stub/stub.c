#define WANT_ARCAN_SHMIF_HELPER
#include "../arcan_shmif.h"
#include "../shmif_privext.h"

struct arcan_shmifext_setup arcan_shmifext_defaults(
	struct arcan_shmif_cont* con)
{
	return (struct arcan_shmifext_setup){};
}

enum shmifext_setup_status arcan_shmifext_setup(
	struct arcan_shmif_cont* con,
	struct arcan_shmifext_setup arg)
{
	return SHMIFEXT_NO_API;
}

bool arcan_shmifext_drop_context(struct arcan_shmif_cont* con)
{
	return false;
}

int arcan_shmifext_dev(struct arcan_shmif_cont* con,
	uintptr_t* dev, bool clone)
{
	if (dev)
		*dev = 0;

	return -1;
}

bool arcan_shmifext_drop_context(struct arcan_shmif_cont* con)
{
	return arcan_shmifext_drop(con);
}

void* arcan_shmifext_lookup(
	struct arcan_shmif_cont* con, const char* fun)
{
	return NULL;
}

bool arcan_shmifext_make_current(struct arcan_shmif_cont* con)
{
	return false;
}

bool arcan_shmifext_egl(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag)
{
	return false;
}

bool arcan_shmifext_vk(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(void*, const char*), void* tag)
{
	return false;
}

int arcan_shmifext_signal(struct arcan_shmif_cont* con,
	uintptr_t display, int mask, uintptr_t tex_id, ...)
{
	return -1;
}

bool arcan_shmifext_gltex_handle(struct arcan_shmif_cont* con,
   uintptr_t display, uintptr_t tex_id,
	 int* dhandle, size_t* dstride, int* dfmt)
{
	return false;
}

bool arcan_shmifext_egl_meta(struct arcan_shmif_cont* con,
	uintptr_t* display, uintptr_t* surface, uintptr_t* context)
{
	return false;
}
