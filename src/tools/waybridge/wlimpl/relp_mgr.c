static void relp_destroy(struct wl_client* client, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "");
	struct bridge_client* bcl = wl_resource_get_user_data(res);
	if (bcl)
		bcl->got_relative = NULL;
}

static void relpm_destroy(struct wl_client* client, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "");
}

static const struct zwp_relative_pointer_v1_interface relp_if = {
	.destroy = relp_destroy
};

static void relpm_get(struct wl_client* client,
	struct wl_resource* in_res, uint32_t id, struct wl_resource* pointer)
{
	struct bridge_client* bcl = wl_resource_get_user_data(pointer);
	struct wl_resource* res = wl_resource_create(bcl->client,
		&zwp_relative_pointer_v1_interface, wl_resource_get_version(pointer), id);
	if (!res){
		wl_resource_post_no_memory(in_res);
		return;
	}
/* as soon as the resource is on the client, the shmifev-mapping will start
 * emitting relative mouse events when apropriate */
	bcl->got_relative = res;
	wl_resource_set_implementation(res, &relp_if, bcl, NULL);
}
