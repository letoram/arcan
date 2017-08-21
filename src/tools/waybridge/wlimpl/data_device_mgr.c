static void ddevmgr_create_data_source(
	struct wl_client* cl, struct wl_resource* res, uint32_t id)
{
	trace(TRACE_DDEV, "%"PRIu32, id);
	struct wl_resource* src = wl_resource_create(
		cl, &wl_data_source_interface, wl_resource_get_version(res), id);

	if (!src){
		wl_resource_post_no_memory(res);
		return;
	}

	wl_resource_set_implementation(src, &dsrc_if, NULL, NULL);
}

static void ddevmgr_get_data_device(
	struct wl_client* cl, struct wl_resource* res, uint32_t id,
	struct wl_resource* seat)
{
	trace(TRACE_DDEV, "%"PRIu32, id);
	struct wl_resource* src = wl_resource_create(
		cl, &wl_data_device_interface, wl_resource_get_version(res), id);

	if (!src){
		wl_resource_post_no_memory(res);
		return;
	}

	wl_resource_set_implementation(src, &ddev_if, NULL, NULL);
}
