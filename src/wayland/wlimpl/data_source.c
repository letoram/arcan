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

	offer->offer = res;
/* how to handle multiple sources being set? */
	cl->doffer_copy = offer;

/* Queue each type as a message on the bridge - currently not used for anything
 * else but at least prefix with a command. The reason for going with that
 * instead of the BCHUNKSTATE option is that the mime- type is not
 * transferrable over the extension-list, arcan will restrict the character set
 * there is also the bit about arbitrary mime-type length but ignored for now -
 *
 * then for 'paste' we set the type with a message, and consume on the next
 * bchunkstate event where we get the descriptor
 */
	struct arcan_event hint = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(MESSAGE),
	};

	snprintf(
		(char*)hint.ext.message.data,
		COUNT_OF(hint.ext.message.data), "offer:%s", mime
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

	struct arcan_event hint = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(MESSAGE),
	};

	snprintf(
		(char*)hint.ext.message.data,
		COUNT_OF(hint.ext.message.data), "-reset"
	);

	arcan_shmif_enqueue(&cl->acon, &hint);
}
