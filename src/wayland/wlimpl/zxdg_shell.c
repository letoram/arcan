static void zxdg_getsurf(struct wl_client* client,
	struct wl_resource* res, uint32_t id, struct wl_resource* surf_res)
{
	trace(TRACE_SHELL, "get zxdg-shell surface");
	struct comp_surf* surf = wl_resource_get_user_data(surf_res);
	struct wl_resource* zxdgsurf_res = wl_resource_create(client,
		&zxdg_surface_v6_interface, wl_resource_get_version(res), id);

	if (!zxdgsurf_res){
		wl_resource_post_no_memory(res);
		return;
	}

	snprintf(surf->tracetag, 16, "zxdg_surf");
	surf->surf_res = zxdgsurf_res;
	wl_resource_set_implementation(zxdgsurf_res, &zxdgsurf_if, surf, NULL);
	zxdg_surface_v6_send_configure(zxdgsurf_res, wl_display_next_serial(wl.disp));
}

static void zxdg_pong(
	struct wl_client* client, struct wl_resource* res, uint32_t serial)
{
	trace(TRACE_SHELL, "xdg_pong(%PRIu32)", serial);
}

static void zxdg_createpos(
	struct wl_client* client, struct wl_resource* res, uint32_t id)
{
	trace(TRACE_SHELL, "%"PRIu32, id);

	struct positioner* new_pos = malloc(sizeof(struct positioner));
	if (!new_pos){
		wl_resource_post_no_memory(res);
		return;
	}
	*new_pos = (struct positioner){};
	struct wl_resource* pos = wl_resource_create(client,
		&zxdg_positioner_v6_interface, wl_resource_get_version(res), id);

	if (!pos){
		free(new_pos);
		wl_resource_post_no_memory(pos);
		return;
	}

	wl_resource_set_implementation(pos, &zxdgpos_if, new_pos, NULL);
}

static void zxdg_destroy(
	struct wl_client* client, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "xdg_destroy");
}

