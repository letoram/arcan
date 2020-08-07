struct dma_buf {
	uint32_t magic;

	uint32_t w, h;
	uint32_t fmt;
	uint32_t fl;
	uint32_t id;

	struct shmifext_buffer_plane planes[4];
	struct wl_resource* res;
};

static void zdmattr_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "");
	wl_resource_destroy(res);
}

static void dmabuf_destroy(struct wl_client* cl, struct wl_resource* res)
{
	wl_resource_destroy(res);
}

static void dmabuf_destroy_user(struct wl_resource* res)
{
	trace(TRACE_DRM, "");
	struct dma_buf* buf = wl_resource_get_user_data(res);
	if (!buf || buf->magic != 0xfeedface)
		return;

	for (size_t i = 0; i < COUNT_OF(buf->planes); i++){
		if (-1 != buf->planes[i].fd){
			close(buf->planes[i].fd);
			buf->planes[i].fd = -1;
		}
	}

	buf->magic = 0xfeedface;
	free(buf);
}

static const struct wl_buffer_interface buffer_impl = {
	.destroy = dmabuf_destroy,
};

struct dma_buf* dmabuf_buffer_get(struct wl_resource* res)
{
	if (!wl_resource_instance_of(res, &wl_buffer_interface, &buffer_impl))
		return NULL;

	struct dma_buf* buf = wl_resource_get_user_data(res);
	if (!buf || buf->magic != 0xfeedface)
		return NULL;

	return buf;
}

static void zdmattr_buffer_finish(struct wl_client* cl, struct wl_resource* res,
	uint32_t id, int32_t w, int32_t h, uint32_t fmt, uint32_t fl)
{
	trace(TRACE_ALLOC, "client=%"PRIxPTR":id=%"PRIu32
		":w=%"PRId32":h=%"PRId32":fmt=%"PRIu32":flag=%"PRIu32,
		(uintptr_t) cl, id, w, h, fmt, fl);

/* validation points:
 *  - coherent set of attributes (no gaps in descriptor indices)
 *  - valid dimensions
 *  - no unknown format flags (what to do with interlaced or y-inv + b-up)
 *  ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_FORMAT,
 *  ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_WL_BUFFER
 */
	struct dma_buf* buffer = wl_resource_get_user_data(res);
	buffer->res =	wl_resource_create(cl, &wl_buffer_interface, 1, id);
	if (!buffer->res){
		wl_resource_post_no_memory(res);
		return;
	}

	buffer->magic = 0xfeedface;
	buffer->fmt = fmt;
	buffer->w = w;
	buffer->h = h;

	wl_resource_set_implementation(
		buffer->res, &buffer_impl, buffer, dmabuf_destroy_user);

	if (id == 0){
		zwp_linux_buffer_params_v1_send_created(res, buffer->res);
	}
}

/* send_modifier events should likely come from a DEVICEHINT, we have
 * enough fields to shove them in there - these should also be tracked
 * in the client structure so the client doesn't provide the wrong
 * mods */
static void zdmattr_create(struct wl_client* cl,
	struct wl_resource* res, int32_t w, int32_t h, uint32_t fmt, uint32_t fl)
{
	zdmattr_buffer_finish(cl, res, 0, w, h, fmt, fl);
}

static void zdmattr_add(struct wl_client* cl,
	struct wl_resource* res, int32_t fd, uint32_t plane, uint32_t ofs,
	uint32_t stride, uint32_t mod_hi, uint32_t mod_lo)
{
	trace(TRACE_ALLOC, "client=%"PRIxPTR":fd=%"PRId32":plane=%"PRIu32
		":plane=%"PRIu32":ofs=%"PRIu32":stride=%"PRIu32":mod=%"PRIu32",%"PRIu32,
	(uintptr_t) cl, fd, plane, ofs, stride, mod_hi, mod_lo);

	struct dma_buf* buf = wl_resource_get_user_data(res);
	if (plane < COUNT_OF(buf->planes)){
		buf->planes[plane] = (struct shmifext_buffer_plane){
/* nice little caveat, if this is pushed through the normal conversion,
 * the [fd] will get closed by plane import, so remember to dup this when
 * forwarding */
			.fd = fd,
			.gbm = {
				.offset = ofs,
				.pitch = stride,
				.mod_hi = mod_hi,
				.mod_lo = mod_lo,
				.format = buf->fmt,
			}
		};
	}
	else {
/* post something about odd indexed plane
	ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_PLANE_IDX
*/
		return;
	};
}

static void zdmattr_create_immed(struct wl_client* cl, struct wl_resource* res,
	uint32_t id, int32_t w, int32_t h, uint32_t fmt, uint32_t fl)
{
	zdmattr_buffer_finish(cl, res, id, w, h, fmt, fl);
}
