static void surf_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace("surf_destroy(%"PRIxPTR")", (uintptr_t) res);
/* should I do this or will the lib? wl_resource_destroy(res); */
}

/*
 * Buffer now belongs to surface
 */
static void surf_attach(struct wl_client* cl, struct wl_resource* res,
	struct wl_resource* buf, int32_t x, int32_t y)
{
	trace("surf_attach(%d, %d)", (int)x, (int)y);
	struct bridge_surf* surf = wl_resource_get_user_data(res);
	surf->buf = buf;
}

/*
 * Similar to the X damage stuff, just grow the synch region for shm repacking
 */
static void surf_damage(struct wl_client* cl, struct wl_resource* res,
	int32_t x, int32_t y, int32_t w, int32_t h)
{
	trace("surf_damage(%d+%d, %d+%d)", (int)x, (int)w, (int)y, (int)h);
//	struct bridge_surf* surf = wl_resource_get_user_data(res);
}

static void surf_frame(
	struct wl_client* cl, struct wl_resource* res, uint32_t cb)
{
	trace("surf_damage()");
}

static void surf_opaque(struct wl_client* cl,
	struct wl_resource* res, struct wl_resource* reg)
{
	trace("surf_opaqaue()");
}

static void surf_inputreg(struct wl_client* cl,
	struct wl_resource* res, struct wl_resource* reg)
{
	trace("surf_inputreg()");
}

static void surf_commit(struct wl_client* cl, struct wl_resource* res)
{
	trace("surf_commit(xxx)");
	struct bridge_surf* surf = wl_resource_get_user_data(res);
	EGLint dfmt;

	if (surf->cookie != 0xfeedface){
		trace("surf_commit() UAF on surface in commit");
		return;
	}

	if (!surf->buf){
		trace("surf_commit() surface lacks buffer");
		return;
	}

	if (!surf->cl || !surf->acon){
		trace("surf_commit() surface doesn't have an arcan connection");
		wl_buffer_send_release(surf->buf);
		return;
	}

	while (surf->acon->addr->vready){}
	if (query_buffer && query_buffer(wl.display,
		surf->buf, EGL_TEXTURE_FORMAT, &dfmt)){
		trace("surf_commit(egl)");

/* for this case, we need to defer the release of a buffer, chances are we run
 * into a live-locking problem as the server will keep the buffer and use it as
 * long as the client doesn't send another, but from what I could tell this is
 * supposed to be double buffered
 *
 */
		wl_buffer_send_release(surf->buf);

/* Now we can format the buffer through the normal signal_handle.
 *
 * this is done through repeated calls to query wayland buffer to get
 * the properties, e.g. EGL_WAYLAND_Y_INVERTED_WL, then
 * eglCreateImageKHR(wl.display, EGL_NO_CONTEXT, EGL_WAYLAND_BUFFER_WL,
 * 	(EGLClientBuffer)buffer->resource(), attrs)
 * and if that works we can forward the descriptor as usual..
 */
	}
	else {
		trace("surf_commit(shm)");
		struct wl_shm_buffer* buf = wl_shm_buffer_get(surf->buf);
		if (buf){
				uint32_t w = wl_shm_buffer_get_width(buf);
				uint32_t h = wl_shm_buffer_get_height(buf);
				void* data = wl_shm_buffer_get_data(buf);

/* The server API is way too unfinished to dare doing a 1-thread-1-client
 * thing. We could've just forked out (shmif has no problems with that as
 * long as you don't double fork) and ran one of those per client but the
 * EGLDisplay approach seem to break that for us, probably worth a try if
 * the main-thread stalls start to hurt */

			if (surf->acon->w != w || surf->acon->h != h)
				arcan_shmif_resize(surf->acon, w, h);

/*
 * FIXME: For the accelerated handle passing, we offload the cost of
 * translating to GL textures here. Enable by doing a shmifext_setup on
 * the client->acon with the _fbo attribute disabled and the format
 * changed to whatever the buffer pool is set to. Use the primary segment
 * to get the context to use and setup shmifext on the cl->acon with
 * shared context. This might not work 100% for shmpools with
 * multiple buffer formats though (if that is possible)
 *
 * Then trick the shmifext_signal by modifying vidp temporarily to
 * pointing to the buffer properties extracted from wl_shm_buffer*
 *
 * The other option is to implement the shm.c fully, and on the create_buffer
 * call, return the current base / offsets (along with the possible
 * resize_ext dance to get the right number of buffers, offsets etc.)
 */
			memcpy(surf->acon->vidp, data, w * h * sizeof(shmif_pixel));
		}

		arcan_shmif_signal(surf->acon, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
		wl_buffer_send_release(surf->buf);
	}

}

static void surf_transform(struct wl_client* cl,
	struct wl_resource* res, int32_t transform)
{
	trace("surf_transform(%d)", (int) transform);
}

static void surf_scale(struct wl_client* cl,
	struct wl_resource* res, int32_t scale)
{
	trace("surf_scale(%d)", (int) scale);
}
