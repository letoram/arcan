static void surf_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "destroy:surf(%"PRIxPTR")", (uintptr_t) res);
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (!surf){
		trace(TRACE_ALLOC, "destroy:lost-surface");
		return;
	}

/* check pending subsurfaces? */
	destroy_comp_surf(surf, true);
}

static void buffer_destroy(struct wl_listener* list, void* data)
{
	struct comp_surf* surf = NULL;
	surf = wl_container_of(list, surf, l_bufrem);
	if (!surf)
		return;

	trace(TRACE_SURF, "(event) destroy:buffer(%"PRIxPTR")", (uintptr_t) data);

	if (surf->buf){
		surf->cbuf = (uintptr_t) NULL;
		surf->buf = NULL;
	}

	if (surf->last_buf){
		surf->last_buf = NULL;
	}

	if (surf->l_bufrem_a){
		surf->l_bufrem_a = false;
		wl_list_remove(&surf->l_bufrem.link);
	}
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

	if (surf->l_bufrem_a){
		surf->l_bufrem_a = false;
		wl_list_remove(&surf->l_bufrem.link);
	}

	trace(TRACE_SURF, "attach to: %s, @x,y: %d, %d - buf: %"
		PRIxPTR, surf->tracetag, (int)x, (int)y, (uintptr_t)buf);

	if (surf->buf && !buf){
		trace(TRACE_SURF, "mark visible: %s", surf->tracetag);
		surf->viewport.ext.viewport.invisible = true;
		arcan_shmif_enqueue(&surf->acon, &surf->viewport);
	}
	else if (surf->viewport.ext.viewport.invisible){
		trace(TRACE_SURF, "mark visible: %s", surf->tracetag);
		surf->viewport.ext.viewport.invisible = false;
		arcan_shmif_enqueue(&surf->acon, &surf->viewport);
	}

	if (buf){
		surf->l_bufrem_a = true;
		surf->l_bufrem.notify = buffer_destroy;
		wl_resource_add_destroy_listener(buf, &surf->l_bufrem);
	}

/* buf XOR cookie == cbuf in commit */
	surf->cbuf = (uintptr_t) buf;
	surf->buf = (void*) ((uintptr_t) buf ^ ((uintptr_t) 0xfeedface));
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

	if (surf->frames_pending + surf->subsurf_pending > COUNT_OF(surf->scratch)){
		trace(TRACE_SURF, "too many pending surface ops");
		wl_resource_post_no_memory(res);
		return;
	}

	STEP_SERIAL();
	struct wl_resource* cbres =
		wl_resource_create(cl, &wl_callback_interface, 1, cb);

	if (!cbres){
		wl_resource_post_no_memory(res);
		return;
	}

	for (size_t i = 0; i < COUNT_OF(surf->scratch); i++){
		if (surf->scratch[i].type == 1){
			wl_resource_destroy(surf->scratch[i].res);
			surf->frames_pending--;
			surf->scratch[i].res = NULL;
			surf->scratch[i].id = 0;
			surf->scratch[i].type = 0;
		}

		if (surf->scratch[i].type == 0){
			surf->frames_pending++;
			surf->scratch[i].res = cbres;
			surf->scratch[i].id = cb;
			surf->scratch[i].type = 1;
			break;
		}
	}
}

static void setup_shmifext(
	struct arcan_shmif_cont* acon, struct comp_surf* surf, int fmt)
{
	struct arcan_shmifext_setup setup = arcan_shmifext_defaults(acon);
	setup.vidp_pack = true;
	setup.builtin_fbo = false;
	surf->accel_fmt = fmt;

	switch(fmt){
		case WL_SHM_FORMAT_RGB565:
/* should set UNSIGNED_SHORT_5_6_5 as well */
			setup.vidp_infmt = GL_RGB;
		break;
		case WL_SHM_FORMAT_XRGB8888:
		case WL_SHM_FORMAT_ARGB8888:
			setup.vidp_infmt = GL_BGRA_EXT;
		break;
		default:
			surf->fail_accel = -1;
			return;
		break;
	}
	if (arcan_shmifext_setup(acon, setup) != SHMIFEXT_OK)
		surf->fail_accel = -1;
	else
		surf->fail_accel = 1;
}

/*
 * IGNORE, shmif doesn't split up into regions like this, though
 * we can forward it as messages and let the script-side decide.
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
/*
 * INCOMPLETE:
 * Should either send this onward for the wm scripts to mask/forward
 * events that fall outside the region, or annotate the surface resource
 * and route the input in the bridge. This becomes important with complex
 * hierarchies (from popups and subsurfaces).
 */
}

static void surf_commit(struct wl_client* cl, struct wl_resource* res)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);
	trace(TRACE_SURF, "%s (@%"PRIxPTR, surf->tracetag, (uintptr_t)surf->cbuf);
	struct arcan_shmif_cont* acon = &surf->acon;

	if (!surf){
		trace(TRACE_SURF, "no surface in resource (severe)");
		return;
	}

	if (!surf->cbuf){
		trace(TRACE_SURF, "no buffer");
		return;
	}

	if (!surf->client){
		trace(TRACE_SURF, "no bridge");
		return;
	}

/*
 * if we don't defer the release, we seem to provoke some kind of race
 * condition in the client or support libs that end very SIGSEGVy
 */
	if (surf->last_buf){
		try_frame_callback(surf, acon);
		wl_buffer_send_release(surf->last_buf);
		surf->last_buf = NULL;
	}

	struct wl_resource* buf = (struct wl_resource*)(
		(uintptr_t) surf->buf ^ ((uintptr_t) 0xfeedface));
	if ((uintptr_t) buf != surf->cbuf){
		trace(TRACE_SURF, "corrupted or unknown buf "
			"(%"PRIxPTR" vs %"PRIxPTR") (severe)", (uintptr_t) buf, surf->cbuf);
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
			trace(TRACE_SURF, "UAF or unknown surface (tag: %s)", surf->tracetag);
			return;
		}
	}

	if (!acon || !acon->addr){
		trace(TRACE_SURF, "couldn't map to arcan connection");
		wl_buffer_send_release(buf);
		return;
	}

/*
 * Avoid tearing due to the SIGBLK_NONE, the other option would be to actually
 * block (if we multithread/multiprocess the client) or to schedule/defer this
 * processing until we get an unlock event (can be implemented client/lib side
 * through a kqueue- trigger or with the delivery-event callback approach that
 * we use for frame-callbacks. At least verify the compilers generate spinlock
 * style instructions.
 */
	while (acon->addr->vready){}

	struct wl_shm_buffer* shm_buf = wl_shm_buffer_get(buf);
	if (!shm_buf){
		struct wl_drm_buffer* drm_buf = wayland_drm_buffer_get(wl.drm, buf);
		if (drm_buf){
			trace(TRACE_SURF, "surf_commit(egl:%s)", surf->tracetag);
			wayland_drm_commit(surf, drm_buf, acon);
			surf->last_buf = buf;
		}
		else
			trace(TRACE_SURF, "surf_commit(unknown:%s)", surf->tracetag);
	}
	else if (shm_buf){
		trace(TRACE_SURF, "surf_commit(shm:%s)", surf->tracetag);
		uint32_t w = wl_shm_buffer_get_width(shm_buf);
		uint32_t h = wl_shm_buffer_get_height(shm_buf);
		int fmt = wl_shm_buffer_get_format(shm_buf);
		void* data = wl_shm_buffer_get_data(shm_buf);
		size_t stride = wl_shm_buffer_get_stride(shm_buf);

		if (acon->w != w || acon->h != h){
			trace(TRACE_SURF,
				"surf_commit(shm, resize to: %zu, %zu)", (size_t)w, (size_t)h);
			arcan_shmif_resize(acon, w, h);
		}

		if (0 == surf->fail_accel ||
			(surf->fail_accel > 0 && fmt != surf->accel_fmt)){
			arcan_shmifext_drop(acon);
			setup_shmifext(acon, surf, fmt);
		}

		if (1 == surf->fail_accel){
			int ext_state = arcan_shmifext_isext(acon);

/* no acceleration if that means fallback, as that would be slower, this can
 * happen by upstream event if the buffer is rejected or some other activity
 * (GPU swapping etc) make the context invalid */
			if (ext_state == 2){
				surf->fail_accel = -1;
				arcan_shmifext_drop(acon);
			}
/* though it would be possible to share context between surfaces on the
 * same client, at this stage it turns out to be more work than the overhead */
			else {
				trace(TRACE_SURF,"surf_commit(shm-gl-repack)");
				arcan_shmifext_make_current(acon);

/* the context is setup so that vidp will be uploaded into two textures, acting
 * as our dma-buf intermediates. we then signalext which pass the underlying
 * handles. the other option would be to work with the arcan-abc libraries to
 * get access to agp for texture uploads etc. but since it's already wrapped in
 * shmifext, use that. */
				void* old_vidp = acon->vidp;
				size_t old_stride = acon->stride;
				acon->vidp = data;
				acon->stride = stride;
				arcan_shmifext_signal(acon,
					0, SHMIF_SIGVID | SHMIF_SIGBLK_NONE, SHMIFEXT_BUILTIN);
				acon->vidp = old_vidp;
				acon->stride = old_stride;
				if (wl.defer_release)
					surf->last_buf = buf;
				else
					wl_buffer_send_release(buf);
				return;
			}
		}

/* if stride mismatch, copy row by row - this do NOT handle format conversion /
 * swizzling yet, copy code from fsrv_game for that */
		if (stride != acon->stride){
			trace(TRACE_SURF,"surf_commit(stride-mismatch)");
			for (size_t row = 0; row < h; row++){
				memcpy(&acon->vidp[row * acon->pitch],
					&((uint8_t*)data)[row * stride],
					w * sizeof(shmif_pixel)
				);
			}
		}
		else
			memcpy(acon->vidp, data, w * h * sizeof(shmif_pixel));

		arcan_shmif_signal(acon, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
		if (wl.defer_release)
			surf->last_buf = buf;
		else
			wl_buffer_send_release(buf);
	}

	trace(TRACE_SURF,
		"surf_commit(%zu,%zu-%zu,%zu):accel=%d",
			(size_t)acon->dirty.x1, (size_t)acon->dirty.y1,
			(size_t)acon->dirty.x2, (size_t)acon->dirty.y2,
			surf->fail_accel);

	acon->dirty.x1 = acon->w;
	acon->dirty.x2 = 0;
	acon->dirty.y1 = acon->h;
	acon->dirty.y2 = 0;
}

static void surf_transform(struct wl_client* cl,
	struct wl_resource* res, int32_t transform)
{
	trace(TRACE_SURF, "surf_transform(%d)", (int) transform);
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (!surf || !surf->acon.addr)
		return;

	struct arcan_event ev = {
		.ext.kind = ARCAN_EVENT(MESSAGE),
	};
	snprintf((char*)ev.ext.message.data,
		COUNT_OF(ev.ext.message.data), "transform:%"PRId32, transform);

	arcan_shmif_enqueue(&surf->acon, &ev);
}

static void surf_scale(struct wl_client* cl,
	struct wl_resource* res, int32_t scale)
{
	trace(TRACE_SURF, "surf_scale(%d)", (int) scale);
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (!surf || !surf->acon.addr)
		return;

	struct arcan_event ev = {
		.ext.kind = ARCAN_EVENT(MESSAGE)
	};
	snprintf((char*)ev.ext.message.data,
		COUNT_OF(ev.ext.message.data), "scale:%"PRId32, scale);
	arcan_shmif_enqueue(&surf->acon, &ev);
}
