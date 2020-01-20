static void region_destroy(struct wl_client* client, struct wl_resource* res)
{
	trace(TRACE_REGION, "region_destroy");
}

static void region_add(struct wl_client* client, struct wl_resource* res,
	int32_t x, int32_t y, int32_t width, int32_t height)
{
	trace(TRACE_REGION, "region_add");
}

static void region_sub(struct wl_client* client, struct wl_resource* res,
	int32_t x, int32_t y, int32_t width, int32_t height)
{
	trace(TRACE_REGION, "region_subtrace");
}
