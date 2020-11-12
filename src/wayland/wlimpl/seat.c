static void pointer_set(struct wl_client* cl, struct wl_resource* res,
	uint32_t serial, struct wl_resource* surf_res, int32_t hot_x, int32_t hot_y)
{
	trace(TRACE_SEAT, "cursor_set(%"PRIxPTR")", (uintptr_t)surf_res);
	struct seat* seat = wl_resource_get_user_data(res);
	struct bridge_client* bcl = find_client(cl);

	bcl->cursor = surf_res;

	if (bcl->hot_x != hot_x || bcl->hot_y != hot_y){
		trace(TRACE_SEAT, "hotspot:old=%d,%d:new=%d,%d",
			(int) bcl->hot_x, (int) bcl->hot_y, (int) hot_x, (int) hot_y);
		bcl->dirty_hot = true;
		bcl->hot_x = hot_x;
		bcl->hot_y = hot_y;
	}

/* switch out who is responsible for events on the surface this round, this is
 * important as it breaks the 0..1 mapping between comp_surf and acon (realloc
 * on cursor each switch is too expensive) */
	struct acon_tag* tag = bcl->acursor.user;
	if (!tag){
		trace(TRACE_ALLOC, "error:unassigned pointer");
		return;
	}

	if (surf_res){
		struct comp_surf* csurf = wl_resource_get_user_data(surf_res);
		snprintf(csurf->tracetag, SURF_TAGLEN, "cursor");
		csurf->rcon = &bcl->acursor;
		wl.groups[tag->group].slots[tag->slot].surface = csurf;
	}
/* set a 0-alpha buffer? */
	else {
		wl.groups[tag->group].slots[tag->slot].surface = NULL;
	}
}

static void pointer_release(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SEAT, "cursor_release");
	struct seat* seat = wl_resource_get_user_data(res);
	struct bridge_client* bcl = find_client(cl);
	seat->ptr = NULL;
	wl_resource_destroy(res);
}

struct wl_pointer_interface pointer_if = {
	.set_cursor = pointer_set,
	.release = pointer_release
};

static void seat_pointer(
	struct wl_client* cl,	struct wl_resource* res, uint32_t id)
{
	trace(TRACE_SEAT, "seat_pointer(%"PRIu32")", id);
	struct seat* seat = wl_resource_get_user_data(res);

	struct wl_resource* ptr = wl_resource_create(
			cl, &wl_pointer_interface, wl_resource_get_version(res), id);

	if (!ptr){
		wl_resource_post_no_memory(res);
		return;
	}

	wl_resource_set_implementation(ptr, &pointer_if, seat, NULL);
	seat->ptr = ptr;
}

static void kbd_release(struct wl_client* client, struct wl_resource* res)
{
	trace(TRACE_SEAT, "kbd release");

	struct seat* seat = wl_resource_get_user_data(res);
	seat->kbd = NULL;
	wl_resource_destroy(res);
}

struct wl_keyboard_interface kbd_if = {
	.release = kbd_release
};

static void seat_keyboard(
	struct wl_client* cl, struct wl_resource* res, uint32_t id)
{
	trace(TRACE_SEAT, "seat_keyboard(%"PRIu32")", id);
	struct seat* seat = wl_resource_get_user_data(res);

	struct wl_resource* kbd = wl_resource_create(cl,
		&wl_keyboard_interface, wl_resource_get_version(res), id);

	if (!kbd){
		wl_resource_post_no_memory(res);
		return;
	}

	size_t sz;
	int fd;
	int fmt;
	if (!waybridge_instance_keymap(seat, &fd, &fmt, &sz)){
		wl_resource_post_no_memory(res);
		wl_resource_destroy(res);
		return;
	}

	seat->kbd = kbd;
	wl_resource_set_implementation(kbd, &kbd_if, seat, NULL);

	if (wl_resource_get_version(kbd) >= WL_KEYBOARD_REPEAT_INFO_SINCE_VERSION)
		wl_keyboard_send_repeat_info(kbd, 25, 600);

	wl_keyboard_send_keymap(seat->kbd, fmt, fd, sz);
}

static void seat_touch(
	struct wl_client* cl, struct wl_resource* res, uint32_t id)
{
	trace(TRACE_SEAT, "seat_touch(%"PRIu32")", id);
}

static void seat_release(
	struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SEAT, "seat_release");
	struct seat* seat = wl_resource_get_user_data(res);
	seat->used = false;
}
