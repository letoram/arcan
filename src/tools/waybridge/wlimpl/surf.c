static void surf_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "destroy:surf(%"PRIxPTR")", (uintptr_t) res);
	struct comp_surf* surf = wl_resource_get_user_data(res);

	if (surf)
		destroy_comp_surf(surf);
}

/*
 * Buffer now belongs to surface
 */
static void surf_attach(struct wl_client* cl, struct wl_resource* res,
	struct wl_resource* buf, int32_t x, int32_t y)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (!surf){
		trace(TRACE_SURF, "attempted attach to missing surface\n");
		return;
	}

	trace(TRACE_SURF, "to: %s, @x,y: %d, %d - buf: %"
		PRIxPTR, surf->tracetag, (int)x, (int)y, (uintptr_t)res);

/* this should likely prompt either a destruction of the underlying
 * connection (possibly not a good idea) or a visibility hint */
	if (surf->buf && !buf){
		trace(TRACE_SURF, "detach from: %s\n", surf->tracetag);
	}

	surf->buf = buf;
}

/*
 * Similar to the X damage stuff, just grow the synch region for shm repacking
 * but there's more to this (of course there is) as there's the whole buffer
 * isn't necessarily 1:1 of surface.
 */
static void surf_damage(struct wl_client* cl, struct wl_resource* res,
	int32_t x, int32_t y, int32_t w, int32_t h)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);
	trace(TRACE_SURF,"%s:(%"PRIxPTR") @x,y+w,h(%d+%d, %d+%d)",
		surf->tracetag, (uintptr_t)res, (int)x, (int)w, (int)y, (int)h);

	if (x < surf->acon.dirty.x1)
		surf->acon.dirty.x1 = x;
	if (x+w > surf->acon.dirty.x2)
		surf->acon.dirty.x2 = x+w;
	if (y < surf->acon.dirty.y1)
		surf->acon.dirty.y1 = y;
	if (y+h > surf->acon.dirty.y2)
		surf->acon.dirty.y2 = y+h;
}

/*
 * The client wants this object to be signalled when it is time to produce a
 * new frame. There's a few options:
 * - CLOCKREQ and attach it to frame
 * - signal immediately, but defer if we're invisible and wait for DISPLAYHINT.
 * - set a FUTEX/KQUEUE to monitor the segment vready flag, and when
 *   that triggers, send the signal.
 * - enable the frame-feedback mode on shmif.
 */
static void surf_frame(
	struct wl_client* cl, struct wl_resource* res, uint32_t cb)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);
	trace(TRACE_SURF, "req-cb, %s(%"PRIu32")", surf->tracetag, cb);

/* spec doesn't say how many callbacks we should permit */
	if (surf->frame_callback){
		trace(TRACE_SURF, "already got frame-callback", surf->tracetag);
		wl_resource_post_no_memory(res);
		return;
	}

	struct wl_resource* cbres =
		wl_resource_create(cl, &wl_callback_interface, 1, cb);

	if (!cbres){
		wl_resource_post_no_memory(res);
		return;
	}

	wl_resource_set_implementation(cbres, NULL, NULL, NULL);
	surf->frame_callback = cbres;
	surf->cb_id = cb;
}

/*
 * IGNORE, shmif doesn't split up into regions like this
 */
static void surf_opaque(struct wl_client* cl,
	struct wl_resource* res, struct wl_resource* reg)
{
	trace(TRACE_REGION, "opaque_region");
}

static void surf_inputreg(struct wl_client* cl,
	struct wl_resource* res, struct wl_resource* reg)
{
	trace(TRACE_REGION, "input_region");
}

static void surf_commit(struct wl_client* cl, struct wl_resource* res)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);
	trace(TRACE_SURF, "%s", surf->tracetag);
	struct arcan_shmif_cont* acon = &surf->acon;
	EGLint dfmt;

/*
 * can happen if we transition to a
 */
	if (!surf->buf){
		trace(TRACE_SURF, "no buffer");
		return;
	}

	if (!surf->client){
		trace(TRACE_SURF, "no bridge");
		return;
	}

/*
 * special case, if the surface we should synch is the currently set
 * pointer resource, then draw that to the special segment.
 */
	if (surf->cookie != 0xfeedface){
		if (res == surf->client->cursor){
			acon = &surf->client->acursor;
/* synch hot-spot changes at this stage */
			if (surf->client->dirty_hot){
				struct arcan_event ev = {
					.ext.kind = ARCAN_EVENT(MESSAGE)
				};
				snprintf((char*)ev.ext.message.data, COUNT_OF(ev.ext.message.data),
					"hot:%d:%d", (int)surf->client->hot_x, (int)surf->client->hot_y);
				arcan_shmif_enqueue(&surf->client->acursor, &ev);
				surf->client->dirty_hot = false;
			}
			trace(TRACE_SURF, "cursor updated");
		}
		else {
			trace(TRACE_SURF, "UAF or unknown surface");
			return;
		}
	}

	if (!acon || !acon->addr){
		trace(TRACE_SURF, "couldn't map to arcan connection");
		wl_buffer_send_release(surf->buf);
		return;
	}

/*
 * Avoid tearing due to the SIGBLK_NONE, the other option would be to actually
 * block (if we multithread/multiprocess the client) or to schedule/defer this
 * processing until we get an unlock event (can be implemented client/lib side
 * through a kqueue- trigger) and then do the corresponding release.
 */
	while (acon->addr->vready){
	}

	struct wl_drm_buffer* drm_buf = wayland_drm_buffer_get(wl.drm, surf->buf);
	if (drm_buf){
		trace(TRACE_SURF, "surf_commit(egl)");

/*
 * when vready is released, it means that the last handle we sent is
 * currently in use, if we provide a new handle, the next time its released
 * we can unlock the previous one etc.
 * arcan_shmif_signalhandle(ctx, mask, handle, stride, format, ...)
 */
		static struct wl_resource* last_buf;
		if (last_buf && last_buf != surf->buf){
			wl_buffer_send_release(surf->buf);
		}

		wayland_drm_commit(drm_buf, acon);
		last_buf = surf->buf;

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
		trace(TRACE_SURF, "surf_commit(shm)");
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

			if (acon->w != w || acon->h != h){
				trace(TRACE_SURF,
					"surf_commit(shm, resize to: %zu, %zu)", (size_t)w, (size_t)h);
				arcan_shmif_resize(acon, w, h);
			}

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
			memcpy(acon->vidp, data, w * h * sizeof(shmif_pixel));
			wl_buffer_send_release(surf->buf);
		}

		trace(TRACE_SURF,
			"surf_commit(%zu,%zu-%zu,%zu)",
				(size_t)acon->dirty.x1, (size_t)acon->dirty.y1,
				(size_t)acon->dirty.x2, (size_t)acon->dirty.y2);

		arcan_shmif_signal(acon, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
		acon->dirty.x1 = acon->w;
		acon->dirty.x2 = 0;
		acon->dirty.y1 = acon->h;
		acon->dirty.y2 = 0;
	}

}

static void surf_transform(struct wl_client* cl,
	struct wl_resource* res, int32_t transform)
{
	trace(TRACE_SURF, "surf_transform(%d)", (int) transform);
}

static void surf_scale(struct wl_client* cl,
	struct wl_resource* res, int32_t scale)
{
	trace(TRACE_SURF, "surf_scale(%d)", (int) scale);
}
