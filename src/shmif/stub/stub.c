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

int arcan_shmifext_isext(struct arcan_shmif_cont* con)
{
	return 0;
}

int arcan_shmifext_dev(struct arcan_shmif_cont* con,
	uintptr_t* dev, bool clone)
{
	if (dev)
		*dev = 0;

	return -1;
}

bool arcan_shmifext_import_buffer(
	struct arcan_shmif_cont* c,
	struct shmifext_buffer_plane* planes,
	int format,
	size_t n_planes,
	size_t buffer_plane_sz
)
{
	return false;
}

bool platform_video_map_handle(struct agp_vstore* store, int64_t handle)
{
	return false;
}

bool arcan_shmifext_gl_handles(struct arcan_shmif_cont* con,
	uintptr_t* frame, uintptr_t* color, uintptr_t* depth)
{
	return false;
}

bool arcan_shmifext_drop(struct arcan_shmif_cont* con)
{
	return false;
}

bool arcan_shmifext_drop_context(struct arcan_shmif_cont* con)
{
	return false;
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

void arcan_shmifext_swap_context(
	struct arcan_shmif_cont* con, unsigned context)
{
}

unsigned arcan_shmifext_add_context(
	struct arcan_shmif_cont* con, struct arcan_shmifext_setup arg)
{
	return 0;
}

void arcan_shmifext_bufferfail(struct arcan_shmif_cont* cont, bool fl)
{
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

struct agp_fenv* arcan_shmifext_getfenv(struct arcan_shmif_cont* con)
{
	return NULL;
}

bool arcan_shmifext_egl_meta(struct arcan_shmif_cont* con,
	uintptr_t* display, uintptr_t* surface, uintptr_t* context)
{
	return false;
}
