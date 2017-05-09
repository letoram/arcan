static void cursor_set(struct wl_client* cl, struct wl_resource* res,
	uint32_t serial, struct wl_resource* surf_res, int32_t hot_x, int32_t hot_y)
{
	trace("cursor_set");
/*
 * struct comp_surf* surf = wl_resource_get_user_data(surf_res);
 */
}

static void cursor_release(struct wl_client* cl, struct wl_resource* res)
{
	trace("cursor_release");
	wl_resource_destroy(res);
}

struct wl_pointer_interface pointer_if = {
	.set_cursor = cursor_set,
	.release = cursor_release
};

static bool pointer_handler(
	struct surface_request* req, struct arcan_shmif_cont* con)
{
	if (!con){
		wl_resource_post_no_memory(req->target);
		return false;
	}

	struct wl_resource* ptr_res =
		wl_resource_create(req->client->client, &wl_pointer_interface, 1, req->id);

	if (!ptr_res){
		wl_resource_post_no_memory(req->target);
		return false;
	}

	req->client->pointer = ptr_res;
	wl_resource_set_implementation(ptr_res, &pointer_if, req->target, NULL);
	return true;
}

static void seat_pointer(struct wl_client* cl,
	struct wl_resource* res, uint32_t id)
{
	trace("seat_pointer(%"PRIu32")", id);

	struct bridge_client* bcl = wl_resource_get_user_data(res);
	if (!bcl->cursor.addr){
		request_surface(bcl, &(struct surface_request){
			.segid = SEGID_CURSOR,
			.target = res,
			.id = id,
			.dispatch = pointer_handler,
			.client = bcl
/* note that we can't set source any since we don't have a surface to
 * attach the connection to */
		});
	}
}

static void kbd_release(struct wl_client* client, struct wl_resource* res)
{
	wl_resource_destroy(res);
}

struct wl_keyboard_interface kbd_if = {
	.release = kbd_release
};

static void seat_keyboard(struct wl_client* cl,
	struct wl_resource* res, uint32_t id)
{
	trace("seat_keyboard(%"PRIu32")", id);
	struct bridge_client* bcl = wl_resource_get_user_data(res);

	struct wl_resource* kbd = wl_resource_create(cl,
		&wl_keyboard_interface, wl_resource_get_version(res), id);

	if (!kbd){
		wl_resource_post_no_memory(res);
		return;
	}

	bcl->keyboard = kbd;
	wl_resource_set_implementation(kbd, &kbd_if, bcl, NULL);

/* FIXME: need to send keyboard layout
 * 	wl_keyboard_send_keymap */
}

static void seat_touch(struct wl_client* cl,
	struct wl_resource* res, uint32_t id)
{
	trace("seat_touch(%"PRIu32")", id);
}
