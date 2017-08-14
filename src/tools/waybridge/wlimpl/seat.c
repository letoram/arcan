static void cursor_set(struct wl_client* cl, struct wl_resource* res,
	uint32_t serial, struct wl_resource* surf_res, int32_t hot_x, int32_t hot_y)
{
	trace(TRACE_SEAT, "cursor_set(%"PRIxPTR")", (uintptr_t)surf_res);
	struct bridge_client* bcl = wl_resource_get_user_data(res);
	bcl->cursor = surf_res;
	if (bcl->hot_x != hot_x || bcl->hot_y != hot_y){
		bcl->dirty_hot = true;
		bcl->hot_x = hot_x;
		bcl->hot_y = hot_y;
	}
}

static void pointer_release(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SEAT, "cursor_release");
	struct bridge_client* bcl = wl_resource_get_user_data(res);
	bcl->pointer = NULL;
/*
 * NOTE: we should probably indicate that the client no-longer uses
 * a custom cursor (so none at all for that matter)
 */
	wl_resource_destroy(res);
}

struct wl_pointer_interface pointer_if = {
	.set_cursor = cursor_set,
	.release = pointer_release
};

static bool pointer_handler(
	struct surface_request* req, struct arcan_shmif_cont* con)
{
	if (!con){
		wl_resource_post_no_memory(req->target);
		return false;
	}

	trace(TRACE_SEAT, "seat pointer paired with SEGID_CURSOR\n");
	struct bridge_client* bcl = wl_resource_get_user_data(req->target);
	bcl->acursor = *con;
	return true;
}

static void seat_pointer(struct wl_client* cl,
	struct wl_resource* res, uint32_t id)
{
	trace(TRACE_SEAT, "seat_pointer(%"PRIu32")", id);
	struct bridge_client* bcl = wl_resource_get_user_data(res);

/*
 * there may be many pointer allocations (for some reason..)
 */
	struct wl_resource* ptr_res =
		wl_resource_create(bcl->client,
			&wl_pointer_interface, wl_resource_get_version(res), id);

	if (!ptr_res){
		wl_resource_post_no_memory(res);
		return;
	}
	wl_resource_set_implementation(ptr_res, &pointer_if, bcl, NULL);
	bcl->pointer = ptr_res;

/*
 * we only allocate the pointer- connection once, and then switch which
 * active surface that we synch- to it.
 */
	if (!bcl->acursor.addr){
		request_surface(bcl, &(struct surface_request){
			.segid = SEGID_CURSOR,
			.target = res,
			.trace = "cursor",
			.id = id,
			.dispatch = pointer_handler,
			.client = bcl
			}, 'm'
		);
	}
}

static void kbd_release(struct wl_client* client, struct wl_resource* res)
{
	trace(TRACE_SEAT, "kbd release");
	wl_resource_destroy(res);
}

struct wl_keyboard_interface kbd_if = {
	.release = kbd_release
};

static void seat_keyboard(struct wl_client* cl,
	struct wl_resource* res, uint32_t id)
{
	trace(TRACE_SEAT, "seat_keyboard(%"PRIu32")", id);
	struct bridge_client* bcl = wl_resource_get_user_data(res);

	struct wl_resource* kbd = wl_resource_create(cl,
		&wl_keyboard_interface, wl_resource_get_version(res), id);


	if (!kbd){
		wl_resource_post_no_memory(res);
		return;
	}

	size_t sz;
	int fd;
	int fmt;
	if (!waybridge_instance_keymap(&fd, &fmt, &sz)){
		wl_resource_post_no_memory(res);
		wl_resource_destroy(res);
		return;
	}

/* we might also need to send repeat rate, that information isn't
 * exported by arcan in any way, so might need to either add a side-channel
 * or user setting */
	bcl->keyboard = kbd;
	wl_resource_set_implementation(kbd, &kbd_if, bcl, NULL);
	wl_keyboard_send_keymap(kbd, fmt, fd, sz);
}

static void seat_touch(struct wl_client* cl,
	struct wl_resource* res, uint32_t id)
{
	trace(TRACE_SEAT, "seat_touch(%"PRIu32")", id);
}
