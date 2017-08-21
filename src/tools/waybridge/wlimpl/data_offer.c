/*
 * wl_data_offer_send_offer
 * wl_data_offer_send_source_actions
 * wl_data_offer_send_action
 */

static void doffer_accept(struct wl_client* cl,
	struct wl_resource* res, uint32_t serial, const char* mime)
{
	trace(TRACE_DDEV, "%"PRIu32", %s", serial, mime ? mime : "");
}

static void doffer_receive(struct wl_client* cl,
	struct wl_resource* res, const char* mime, int32_t fd)
{
	trace(TRACE_DDEV, "%s", mime ? mime : "");
}

static void doffer_actions(struct wl_client* cl,
	struct wl_resource* res, uint32_t dnd_actions, uint32_t preferred_action)
{
	trace(TRACE_DDEV, "%"PRIu32":%"PRIu32, dnd_actions, preferred_action);
}

static void doffer_finish(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_DDEV, "");
}

static void doffer_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_DDEV, "");
}
