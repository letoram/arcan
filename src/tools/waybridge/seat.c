static void cursor_set(struct wl_client* cl, struct wl_resource* res,
	uint32_t serial, struct wl_resource* surf_res, int32_t hot_x, int32_t hot_y)
{
	trace("cursor_set");
	struct comp_surf* surf = wl_resource_get_user_data(surf_res);
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

static void seat_pointer(struct wl_client* cl,
	struct wl_resource* res, uint32_t id)
{
	trace("seat_pointer(%"PRIu32")", id);
	struct wl_resource* ptr_res =
		wl_resource_create(cl, &wl_pointer_interface, 1, id);
	wl_resource_set_implementation(ptr_res, &pointer_if, NULL, NULL);
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
	struct wl_resource* kbd = wl_resource_create(cl,
		&wl_keyboard_interface, wl_resource_get_version(res), id);
	wl_resource_set_implementation(kbd, &kbd_if, NULL, NULL);
}

static void seat_touch(struct wl_client* cl,
	struct wl_resource* res, uint32_t id)
{
	trace("seat_touch(%"PRIu32")", id);
}
