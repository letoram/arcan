/*
 * Copyright 2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: egl-dri specific render-node based backend support
 * library for setting up headless display, and passing handles
 * handling render-node transfer
 */
#define HAVE_ARCAN_SHMIF_HELPER
#include "../arcan_shmif.h"
#include "../shmif_privext.h"

#define EGL_EGLEXT_PROTOTYPES
#define MESA_EGL_NO_X11_HEADERS
#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <drm.h>
#include <drm_fourcc.h>
#include <xf86drm.h>
#include <gbm.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

static PFNEGLCREATEIMAGEKHRPROC create_image;
static PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC query_image_format;
static PFNEGLEXPORTDMABUFIMAGEMESAPROC export_dmabuf;
static PFNEGLDESTROYIMAGEKHRPROC destroy_image;

struct shmif_ext_hidden_int {
	struct gbm_device* dev;
	bool nopass;
};

static void check_functions(void*(*lookup)(void*, const char*), void* tag)
{
	create_image = (PFNEGLCREATEIMAGEKHRPROC)
		lookup(tag, "eglCreateImageKHR");
	destroy_image = (PFNEGLDESTROYIMAGEKHRPROC)
		lookup(tag, "eglDestroyImageKHR");
	query_image_format = (PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC)
		lookup(tag, "eglExportDMABUFImageQueryMESA");
	export_dmabuf = (PFNEGLEXPORTDMABUFIMAGEMESAPROC)
		lookup(tag, "eglExportDMABUFImageMESA");
}

static void gbm_drop(struct arcan_shmif_cont* con)
{
	if (!con->privext->internal)
		return;

	if (con->privext->internal->dev){
/*
 * Since we don't manage the context ourselves, it is not
 * safe to do this, as the EGL behavior seem to be to free this indirectly
 * during EGL display destruction
 * gbm_device_destroy(con->privext->internal->dev);
 */
		con->privext->internal->dev = NULL;
	}
	free(con->privext->internal);
	con->privext->internal = NULL;
}

bool arcan_shmifext_headless_egl(struct arcan_shmif_cont* con,
	void** display, void*(*lookup)(void*, const char*), void* tag)
{
	if (!lookup || !con || !con->addr || !display)
		return false;

	int dfd = -1;

/* case for switching to another node */
	if (con->privext->pending_fd != -1){
		if (-1 != con->privext->active_fd){
			close(con->privext->active_fd);
			gbm_drop(con);
		}
		else
			dfd = con->privext->active_fd;
	}
/* or first setup without a pending_fd */
	else if (!con->privext->internal){
		const char* nodestr = getenv("ARCAN_RENDER_NODE") ?
			getenv("ARCAN_RENDER_NODE") : "/dev/dri/renderD128";
		dfd = open(nodestr, O_RDWR | FD_CLOEXEC);
	}
/* mode-switch is no-op in init here, but we still may need
 * to update function pointers due to possible context changes */
	else {
		check_functions(lookup, tag);
		return true;
	}

	if (-1 == dfd)
		return false;

/* special cleanup to deal with gbm_device abstraction */
	con->privext->cleanup = gbm_drop;

/* finally open device */
	con->privext->internal = malloc(sizeof(struct shmif_ext_hidden_int));
	con->privext->internal->nopass = getenv("ARCAN_VIDEO_NO_FDPASS") ?
		true : false;
	if (NULL == (con->privext->internal->dev = gbm_create_device(dfd))){
		free(con->privext->internal);
		close(dfd);
		con->privext->internal = NULL;
		return false;
	}

	*display = (void*) (con->privext->internal->dev);
	check_functions(lookup, tag);
	return true;
}

bool arcan_shmifext_headless_vk(struct arcan_shmif_cont* con,
	void** display, void*(*lookupfun)(const char*), void* tag)
{
	return false;
}

unsigned arcan_shmifext_eglsignal(struct arcan_shmif_cont* con,
	uintptr_t context, int mask, uintptr_t tex_id, ...)
{
	if (!con || !con->addr || !con->privext->internal || !create_image)
		return 0;

/* missing: check nofdpass (or mask bit) and switch to synch_
 * readback and normal signalling */

	EGLImageKHR image = create_image(con->privext->internal->dev,
		(EGLContext) context,
		EGL_GL_TEXTURE_2D_KHR, (EGLClientBuffer)(tex_id), NULL
		);

	if (!image)
		return 0;

	int fourcc, nplanes;
	if (!query_image_format(con->privext->internal->dev,
		image, &fourcc, &nplanes, NULL))
		return 0;

/* currently unsupported */
	if (nplanes != 1)
		return 0;

	EGLint stride;
	int fd;
	if (!export_dmabuf(con->privext->internal->dev, image, &fd, &stride, NULL))
		return 0;

	unsigned res = arcan_shmif_signalhandle(con, mask, fd, stride, fourcc);
	destroy_image(con->privext->internal->dev, image);
	return res;
}

unsigned arcan_shmifext_vksignal(struct arcan_shmif_cont* con,
	uintptr_t context, int mask, uintptr_t tex_id, ...)
{
	return 0;
}
