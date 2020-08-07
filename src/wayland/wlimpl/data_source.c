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

	trace(TRACE_DDEV, "%s", mime?mime:"");
	if (cl->offer_types.count+1 >= cl->offer_types.limit){
		arcan_mem_growarr(&cl->offer_types);
	}

	cl->offer_types.data[cl->offer_types.count++] = strdup(mime);
}

static void dsrc_actions(struct wl_client* cl,
	struct wl_resource* res, uint32_t actions)
{
	trace(TRACE_DDEV, "%"PRIu32, actions);
}

static void dsrc_destroy(struct wl_client* wcl, struct wl_resource* res)
{
	trace(TRACE_DDEV, "");
	struct bridge_client* cl = find_client(wcl);
	if (!cl)
		return;

	arcan_mem_freearr(&cl->offer_types);
	memset(&cl->offer_types, '\0', sizeof(struct arcan_strarr));
}
