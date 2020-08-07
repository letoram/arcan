#include "../../platform/agp/glfun.h"

static void surf_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "destroy:surf(%"PRIxPTR")", (uintptr_t) res);
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (!surf){
		trace(TRACE_ALLOC, "destroy:lost-surface");
		return;
	}

	if (pending_resource == res)
		pending_resource = NULL;

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

	if (surf->l_bufrem_a){
		surf->l_bufrem_a = false;
		wl_list_remove(&surf->l_bufrem.link);
	}
}

/*
 * Buffer now belongs to surface, but it is useless until there's a commit
 */
static void surf_attach(struct wl_client* cl,
	struct wl_resource* res, struct wl_resource* buf, int32_t x, int32_t y)
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
	setup.builtin_fbo = false;

	surf->accel_fmt = fmt;

	switch(fmt){
	case WL_SHM_FORMAT_ARGB8888:
	case WL_SHM_FORMAT_XRGB8888:
		surf->gl_fmt = GL_BGRA;
	break;
	case WL_SHM_FORMAT_ABGR8888:
	case WL_SHM_FORMAT_XBGR8888:
		surf->gl_fmt = GL_RGBA;
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

static bool fmt_has_alpha(int fmt, struct comp_surf* surf)
{
/* should possible check for the special case if the entire region is marked
 * as opaque as well or if there are translucent portions */
	return
		fmt == WL_SHM_FORMAT_XRGB8888 ||
		fmt == WL_DRM_FORMAT_XRGB4444 ||
		fmt == WL_DRM_FORMAT_XBGR4444 ||
		fmt == WL_DRM_FORMAT_RGBX4444 ||
		fmt == WL_DRM_FORMAT_BGRX4444 ||
		fmt == WL_DRM_FORMAT_XRGB1555 ||
		fmt == WL_DRM_FORMAT_XBGR1555 ||
		fmt == WL_DRM_FORMAT_RGBX5551 ||
		fmt == WL_DRM_FORMAT_BGRX5551 ||
		fmt == WL_DRM_FORMAT_XRGB8888 ||
		fmt == WL_DRM_FORMAT_XBGR8888 ||
		fmt == WL_DRM_FORMAT_RGBX8888 ||
		fmt == WL_DRM_FORMAT_BGRX8888 ||
		fmt == WL_DRM_FORMAT_XRGB2101010 ||
		fmt == WL_DRM_FORMAT_XBGR2101010 ||
		fmt == WL_DRM_FORMAT_RGBX1010102 ||
		fmt == WL_DRM_FORMAT_BGRX1010102;
}

static void synch_acon_alpha(struct arcan_shmif_cont* acon, bool has_alpha)
{
	if (has_alpha){
		if (acon->hints & SHMIF_RHINT_IGNORE_ALPHA){
			/* NOP */
		}
		else {
			acon->hints |= SHMIF_RHINT_IGNORE_ALPHA;
		}
	}
	else {
		if (acon->hints & SHMIF_RHINT_IGNORE_ALPHA){
			acon->hints &= ~SHMIF_RHINT_IGNORE_ALPHA;
		}
		else {
			/* NOP */
		}
	}
}

static bool push_drm(struct wl_client* cl,
	struct arcan_shmif_cont* acon, struct wl_resource* buf, struct comp_surf* surf)
{
	struct wl_drm_buffer* drm_buf = wayland_drm_buffer_get(wl.drm, buf);
	if (!drm_buf)
		return false;

	trace(TRACE_SURF, "surf_commit(egl:%s)", surf->tracetag);
	synch_acon_alpha(acon,
		fmt_has_alpha(wayland_drm_buffer_get_format(drm_buf), surf));
	wayland_drm_commit(surf, drm_buf, acon);
	return true;
}

static bool push_dma(struct wl_client* cl,
	struct arcan_shmif_cont* acon, struct wl_resource* buf, struct comp_surf* surf)
{
	struct dma_buf* dmabuf = dmabuf_buffer_get(buf);
	if (!dmabuf)
		return false;

	if (dmabuf->w != acon->w || dmabuf->h != acon->h){
		arcan_shmif_resize(acon, dmabuf->w, dmabuf->h);
	}

/* right now this only supports a single transfered buffer, the real support
 * is close by in another branch, but for the sake of bringup just block those
 * now */
	for (size_t i = 0; i < COUNT_OF(dmabuf->planes); i++){
		if (i == 0){
			arcan_shmif_signalhandle(acon, SHMIF_SIGVID | SHMIF_SIGBLK_NONE,
				dmabuf->planes[i].fd, dmabuf->planes[i].stride, dmabuf->fmt);
		}
	}

	synch_acon_alpha(acon, fmt_has_alpha(dmabuf->fmt, surf));

	trace(TRACE_SURF, "surf_commit(dmabuf:%s)", surf->tracetag);
	return true;
}

/*
 * since if we have GL already going if the .egl toggle is set, we can pull
 * in agp and use those functions raw
 */
#include "../../platform/video_platform.h"
static bool push_shm(struct wl_client* cl,
	struct arcan_shmif_cont* acon, struct wl_resource* buf, struct comp_surf* surf)
{
	struct wl_shm_buffer* shm_buf = wl_shm_buffer_get(buf);
	if (!shm_buf)
		return false;

	trace(TRACE_SURF, "surf_commit(shm:%s)", surf->tracetag);

	uint32_t w = wl_shm_buffer_get_width(shm_buf);
	uint32_t h = wl_shm_buffer_get_height(shm_buf);
	int fmt = wl_shm_buffer_get_format(shm_buf);
	void* data = wl_shm_buffer_get_data(shm_buf);
	int stride = wl_shm_buffer_get_stride(shm_buf);

	if (acon->w != w || acon->h != h){
		trace(TRACE_SURF,
			"surf_commit(shm, resize to: %zu, %zu)", (size_t)w, (size_t)h);
		arcan_shmif_resize(acon, w, h);
	}

/* resize failed, this will only happen when growing, thus we can crop */
	if (acon->w != w || acon->h != h){
		w = acon->w;
		h = acon->h;
	}

/* have acceleration failed or format changed since we last negotiated accel? */
	if (0 == surf->fail_accel ||
		(surf->fail_accel > 0 && fmt != surf->accel_fmt)){
		trace(TRACE_SURF,
			"surf_commit:status=drop_ext:message:accel_failed\n");
		arcan_shmifext_drop(acon);
		setup_shmifext(acon, surf, fmt);
		arcan_shmifext_make_current(acon);
	}

/* alpha state changed? only changing this flag does not require a resynch
 * as the hint is checked on each frame */
	synch_acon_alpha(acon, fmt_has_alpha(fmt, surf));

/* try the path of converting the shm buffer to an accelerated, BUT there
 * is a special case in that a failed accelerated context can have local
 * readback (receiver isn't a GPU or an incompatible GPU), which we really
 * don't want. */
	if (1 == surf->fail_accel){
		int ext_state = arcan_shmifext_isext(acon);

/* no acceleration if that means fallback, as that would be slower, this can
* happen by upstream event if the buffer is rejected or some other activity
* (GPU swapping etc) make the context invalid */
		if (ext_state == 2){
			surf->fail_accel = -1;
			arcan_shmifext_drop(acon);
			return push_shm(cl, acon, buf, surf);
		}

/* though it would be possible to share context between surfaces on the
 * same client, at this stage it turns out to be more work than the overhead */
		trace(TRACE_SURF,"surf_commit(shm-gl-repack)");
		arcan_shmifext_make_current(acon);
		struct agp_fenv* fenv = arcan_shmifext_getfenv(acon);
		if (!fenv || !fenv->gen_textures){
			trace(TRACE_SURF, "no_gl in env, fallback");
			surf->fail_accel = -1;
			arcan_shmifext_drop(acon);
			return push_shm(cl, acon, buf, surf);
		}

/* grab our buffer */
		if (0 == surf->glid){
			fenv->gen_textures(1, &surf->glid);
			if (0 == surf->glid){
				trace(TRACE_SURF, "couldn't build texture, fallback");
				arcan_shmifext_drop(acon);
				surf->fail_accel = -1;
				return push_shm(cl, acon, buf, surf);
			}
		}

/* update the texture, could do a more efficient use of damage regions here,
 * crutch is that we may need to maintain a queue of buffers again */
		fenv->bind_texture(GL_TEXTURE_2D, surf->glid);
		fenv->pixel_storei(GL_UNPACK_ROW_LENGTH, stride);
		fenv->tex_image_2d(GL_TEXTURE_2D,
			0, surf->gl_fmt, w, h, 0, surf->gl_fmt, GL_UNSIGNED_BYTE, data);
		fenv->pixel_storei(GL_UNPACK_ROW_LENGTH, 0);
		fenv->bind_texture(GL_TEXTURE_2D, 0);

		int fd;
		size_t stride_out;
		int fmt;

		uintptr_t gl_display;
		arcan_shmifext_egl_meta(&wl.control, &gl_display, NULL, NULL);

		if (arcan_shmifext_gltex_handle(acon,
			gl_display, surf->glid, &fd, &stride_out, &fmt)){
			trace(TRACE_SURF, "converted to handle, bingo");
			arcan_shmif_signalhandle(acon,
				SHMIF_SIGVID | SHMIF_SIGBLK_NONE,
				fd, stride_out, fmt
			);
		}
		else{
			trace(TRACE_SURF, "couldn't build texture, fallback");
			arcan_shmifext_drop(acon);
			surf->fail_accel = -1;
			return push_shm(cl, acon, buf, surf);
		}

		return true;
	}

/* two other options to avoid repacking, one is to actually use this signal-
 * handle facility to send a descriptor, and mark the type as the WL shared
 * buffer with the metadata in vidp[] in order for offset and other bits to
 * make sense.
 * The other is to actually allow the shmif server to ptrace into us (wut) and
 * use a rare linuxism known as process_vm_writev and process_vm_readv and send
 * the pointers that way.
 */
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
	return true;
}

/*
 * Practically there is another thing to consider here and that is the trash
 * fire of subsurfaces. Mapping each to a shmif segment is costly, and
 * snowballs into a bunch of extra work in the WM, making otherwise trivial
 * features nightmarish. The other possible option here would be to do the
 * composition ourself into one shmif segment, masking that the thing exists at
 * all.
 */
static void surf_commit(struct wl_client* cl, struct wl_resource* res)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);
	trace(TRACE_SURF, "%s (@%"PRIxPTR")->commit", surf->tracetag, (uintptr_t)surf->cbuf);
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
/* In general, a surface without a role means that the client is in the wrong
 * OR that there is a rootless Xwayland surface going - for the latter, we'd
 * like to figure out if this is correct or not - so wrap around a query
 * function. Since there can be stalls etc. in the corresponding wm, we need to
 * tag this surface as pending on failure */
		else if (!xwl_pair_surface(cl, surf, res)){
			trace(TRACE_SURF, "defer commit until paired");
			return;
		}
	}

	if (!acon || !acon->addr){
		trace(TRACE_SURF, "couldn't map to arcan connection");
		return;
	}

/*
 * Safeguard due to the SIGBLK_NONE, used for signalling, below.
 */
	while(arcan_shmif_signalstatus(acon) > 0){}

/*
 * So it seems that the buffer- protocol actually don't give us
 * a type of the buffer, so the canonical way is to just try them in
 * order shm -> drm -> dma-buf.
 */

	if (
		!push_shm(cl, acon, buf, surf) &&
		!push_drm(cl, acon, buf, surf) &&
		!push_dma(cl, acon, buf, surf)){
		trace(TRACE_SURF, "surf_commit(unknown:%s)", surf->tracetag);
	}

/* might be that this should be moved to the buffer types as well,
 * since we might need double-triple buffering, uncertain how mesa
 * actually handles this */
	wl_buffer_send_release(buf);

	trace(TRACE_SURF,
		"surf_commit(%zu,%zu-%zu,%zu):accel=%d",
			(size_t)acon->dirty.x1, (size_t)acon->dirty.y1,
			(size_t)acon->dirty.x2, (size_t)acon->dirty.y2,
			surf->fail_accel);

/* reset the dirty rectangle */
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
