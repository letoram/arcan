static void drop_source(struct wl_resource* res)
{
	struct data_offer* offer = wl_resource_get_user_data(res);
	if (!offer)
		return;

	memset(offer, '\0', sizeof(struct data_offer));
	free(offer);
	wl_resource_set_user_data(res, NULL);
}

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

	struct data_offer* data = malloc(sizeof(struct data_offer));
	memset(data, '\0', sizeof(struct data_offer));

	if (!data){
		wl_resource_post_no_memory(res);
		wl_resource_destroy(src);
		return;
	}

	data->offer = res;
	wl_resource_set_implementation(src, &dsrc_if, data, drop_source);
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
