static void surf_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace("surf_destroy()");
}

static void surf_attach(struct wl_client* cl, struct wl_resource* res,
	struct wl_resource* buf, int32_t x, int32_t y)
{
	trace("surf_attach(%d, %d)", (int)x, (int)y);
	struct bridge_surface* surf = wl_resource_get_user_data(res);
	surf->buf = buf;
}

static void surf_damage(struct wl_client* cl, struct wl_resource* res,
	int32_t x, int32_t y, int32_t w, int32_t h)
{
/* FIXME:
 * track the extent of the damage here (we don't do multiple damage
 * regions, the test- set we ran on showed that damage often fell into
 * the damage(small subset) or the entire buffer so there's no mechanism
 * in shmif- for tracking multiple regions (though not difficult, only
 * tedious)
 */
	trace("surf_damage(%d+%d, %d+%d)", (int)x, (int)w, (int)y, (int)h);
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
	struct bridge_surface* surf = wl_resource_get_user_data(res);
	EGLint dfmt;
	if (!surf->buf || !surf->cl || !surf->cl->acon.vidp)
		return;

	if (query_buffer && query_buffer(wl.display,
		surf->buf, EGL_TEXTURE_FORMAT, &dfmt)){
		trace("surf_commit(egl)");
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
 */
			if (surf->cl->acon.w != w || surf->cl->acon.h != h)
				arcan_shmif_resize(&surf->cl->acon, w, h);

/*
 * FIXME: Depending on format, we may need to repack here (which stings
 * like a *******
 */
			memcpy(surf->cl->acon.vidp, data, w * h * sizeof(shmif_pixel));

/* need another deferred option if we're not finished synchronizing,
 * i.e. if surf->cl->acon.vidp.vready or not
 */
			arcan_shmif_signal(&surf->cl->acon, SHMIF_SIGVID);
		}
	}
	wl_buffer_send_release(surf->buf);
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
