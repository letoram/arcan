static void zdmabuf_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "");
	wl_resource_destroy(res);
}

static void destroy_params(struct wl_resource* res)
{
	trace(TRACE_ALLOC, "");
}

static void zdmabuf_params(
	struct wl_client* cl, struct wl_resource* res, uint32_t id)
{
	trace(TRACE_ALLOC, "");
	struct dma_buf* buf = malloc(sizeof(struct dma_buf));
	if (!buf){
		wl_resource_post_no_memory(res);
		return;
	}

/* create a resource with the same version pointing to the attributes obj. */
	uint32_t version = wl_resource_get_version(res);
	struct wl_resource* attr_res =
		wl_resource_create(cl, &zwp_linux_buffer_params_v1_interface, version, id);

	if (!attr_res){
		free(buf);
		wl_resource_post_no_memory(res);
		return;
	}
}
