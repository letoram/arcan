static void xdg_getsurf(struct wl_client* client,
	struct wl_resource* res, uint32_t id, struct wl_resource* surf_res)
{
	trace(TRACE_SHELL, "get xdg-shell surface");
	struct comp_surf* surf = wl_resource_get_user_data(surf_res);
	struct wl_resource* xdgsurf_res = wl_resource_create(client,
		&xdg_surface_interface, wl_resource_get_version(res), id);

	if (!xdgsurf_res){
		wl_resource_post_no_memory(res);
		return;
	}

	snprintf(surf->tracetag, 16, "xdg_surf");
	surf->surf_res = xdgsurf_res;
	wl_resource_set_implementation(xdgsurf_res, &xdgsurf_if, surf, NULL);
/*
 * used to be here, deferred to until we actually set a role
 * xdg_surface_send_configure(xdgsurf_res, wl_display_next_serial(wl.disp));
 */
}

static void xdg_pong(
	struct wl_client* client, struct wl_resource* res, uint32_t serial)
{
	trace(TRACE_SHELL, "xdg_pong(%PRIu32)", serial);
}

static void xdg_createpos(
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
		&xdg_positioner_interface, wl_resource_get_version(res), id);

	if (!pos){
		free(new_pos);
		wl_resource_post_no_memory(pos);
		return;
	}

	wl_resource_set_implementation(pos, &xdgpos_if, new_pos, NULL);
}

static void xdg_destroy(
	struct wl_client* client, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "xdg_destroy");
}

