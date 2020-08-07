/*
WL_DATA_SOURCE_TARGET 0
WL_DATA_SOURCE_SEND 1
WL_DATA_SOURCE_CANCELLED 2
WL_DATA_SOURCE_DND_DROP_PERFORMED 3
WL_DATA_SOURCE_DND_FINISHED 4
WL_DATA_SOURCE_ACTION 5

wl_data_source_send_target(res, char*)
wl_data_source_send_send(res, char*, int fd)
wl_data_source_send_cancelled(res)
wl_data_source_send_dnd_drop_performed(res)
wl_data_source_send_dnd_finished
wl_data_source_send_action(res, action)
*/

/*
WL_DATA_SOURCE_ERROR_INVALID_ACTION_MASK = 0,
WL_DATA_SOURCE_ERROR_INVALID_SOURCE = 1
*/
static void dsrc_offer(struct wl_client* wcl,
	struct wl_resource* res, const char* mime)
{
	if (!mime || strlen(mime) == 0)
		return;

	struct bridge_client* cl = find_client(wcl);
	if (!cl)
		return;

	trace(TRACE_DDEV, "%s", mime);
	struct data_offer* offer = wl_resource_get_user_data(res);
	if (!offer)
		return;

/* how to handle multiple sources being set? */
	cl->doffer_copy = offer;

/* queue each available type as a bchunkstate on the bridge connection */
	struct arcan_event hint = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(BCHUNKSTATE),
		.ext.bchunk = {
			.size = 0, /* no way of knowing this, *sigh*/
			.input = 1,
		}
	};

	snprintf(
		(char*)hint.ext.bchunk.extensions,
		COUNT_OF(hint.ext.bchunk.extensions), "%s", mime
	);

	arcan_shmif_enqueue(&cl->acon, &hint);
}

static void dsrc_actions(struct wl_client* cl,
	struct wl_resource* res, uint32_t actions)
{
	trace(TRACE_DDEV, "%"PRIu32, actions);
}

static void dsrc_destroy(struct wl_client* wcl, struct wl_resource* res)
{
	trace(TRACE_DDEV, "");
	struct data_offer* src = wl_resource_get_user_data(res);
	wl_resource_set_user_data(res, NULL);
	wl_resource_destroy(res);
	free(src);

	struct bridge_client* cl = find_client(wcl);
	if (!cl || !cl->acon.addr)
		return;

	if (cl->doffer_copy == src)
		cl->doffer_copy = NULL;
	else if (cl->doffer_drag == src)
		cl->doffer_drag = NULL;
	else
		return;

/* send an empty hint to tell that we no longer are capable of providing this */
	struct arcan_event hint = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(BCHUNKSTATE),
		.ext.bchunk = {
			.size = 0, /* no way of knowing this, *sigh*/
			.input = 1
		}
	};
	arcan_shmif_enqueue(&cl->acon, &hint);
}
