void xdgsurf_defer_handler(
	struct surface_request* req, struct arcan_event* ev)
{
	if (!ev || ev->tgt.kind == TARGET_COMMAND_REQFAIL){
		wl_resource_post_no_memory(req->target);
		return;
	}

	struct arcan_shmif_cont cont = arcan_shmif_acquire(
		&req->client->acon, NULL, SEGID_APPLICATION, 0);
	if (!cont.addr){
		wl_resource_post_no_memory(req->target);
	}

	struct wl_resource* toplevel = wl_resource_create(req->client->client,
		&zxdg_toplevel_v6_interface, wl_resource_get_version(req->target), req->id);

	if (!toplevel){
		arcan_shmif_drop(&cont);
		wl_resource_post_no_memory(req->target);
		return;
	}
	struct comp_surf* surf = wl_resource_get_user_data(req->target);
	wl_resource_set_implementation(toplevel, &xdgtop_if, surf, NULL);
	surf->acon = cont;
	surf->cookie = 0xfeedface;

	struct wl_array states;
	wl_array_init(&states);
	zxdg_toplevel_v6_send_configure(toplevel, surf->acon.w, surf->acon.h, &states);
	wl_array_release(&states);
}

void xdgsurf_toplevel(struct wl_client* cl, struct wl_resource* res,
	uint32_t id)
{
	trace("xdgsurf_toplevel");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	request_surface(surf->client, &(struct surface_request){
		.segid = SEGID_APPLICATION,
		.target = res,
		.id = id,
		.dispatch = xdgsurf_defer_handler,
		.client = surf->client
	});
}

void xdgsurf_getpopup(struct wl_client* cl, struct wl_resource* res,
	uint32_t id, struct wl_resource* parent, struct wl_resource* positioner)
{
	trace("xdgsurf_getpopup");
}

/* hints about the window visible size sans dropshadows and things like that,
 * but since it doesn't carry information about decorations (titlebar, ...)
 * we can't actually use this for a viewport hint */
void xdgsurf_set_geometry(struct wl_client* cl, struct wl_resource* res,
	int32_t x, int32_t y, int32_t width, int32_t height)
{
	trace("xdgsurf_setgeom");
}

void xdgsurf_ackcfg(struct wl_client* cl, struct wl_resource* res,
	uint32_t serial)
{
	trace("xdgsurf_ackcfg");
}
