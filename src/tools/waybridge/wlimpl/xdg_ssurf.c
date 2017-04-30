static bool xdgsurf_shmifev_handler(
	struct comp_surf* surf, struct arcan_event* ev)
{
	if (ev->category == EVENT_TARGET)
		switch (ev->tgt.kind){
		case TARGET_COMMAND_EXIT:
			zxdg_toplevel_v6_send_close(surf->shell_res);
			return true;
		break;
		default:
		break;
		}

	return false;
}

static bool xdgsurf_defer_handler(
	struct surface_request* req, struct arcan_shmif_cont* con)
{
	if (!con){
		wl_resource_post_no_memory(req->target);
		return false;
	}

	struct wl_resource* toplevel = wl_resource_create(req->client->client,
		&zxdg_toplevel_v6_interface, wl_resource_get_version(req->target), req->id);

	if (!toplevel){
		wl_resource_post_no_memory(req->target);
		return false;
	}

	struct comp_surf* surf = wl_resource_get_user_data(req->target);
	wl_resource_set_implementation(toplevel, &xdgtop_if, surf, NULL);
	surf->acon = *con;
	surf->cookie = 0xfeedface;
	surf->shell_res = toplevel;
	surf->dispatch = xdgsurf_shmifev_handler;

	struct wl_array states;
	wl_array_init(&states);
	zxdg_toplevel_v6_send_configure(toplevel, surf->acon.w, surf->acon.h, &states);
	wl_array_release(&states);
	return true;
}

static void xdgsurf_toplevel(
	struct wl_client* cl, struct wl_resource* res, uint32_t id)
{
	trace("xdgsurf_toplevel");
	struct comp_surf* surf = wl_resource_get_user_data(res);

/* though it is marked as 'defered' here, chances are that the request
 * function will just return with the surface immediately */
	request_surface(surf->client, &(struct surface_request){
		.segid = SEGID_APPLICATION,
		.target = res,
		.id = id,
		.dispatch = xdgsurf_defer_handler,
		.client = surf->client,
		.source = surf
	});
}

static void xdgsurf_getpopup(struct wl_client* cl, struct wl_resource* res,
	uint32_t id, struct wl_resource* parent, struct wl_resource* positioner)
{
	trace("xdgsurf_getpopup");
}

/* hints about the window visible size sans dropshadows and things like that,
 * but since it doesn't carry information about decorations (titlebar, ...)
 * we can't actually use this for a viewport hint */
static void xdgsurf_set_geometry(struct wl_client* cl,
	struct wl_resource* res, int32_t x, int32_t y, int32_t width, int32_t height)
{
	trace("xdgsurf_setgeom(%"PRIu32"+%"PRIu32", "PRIu32"+%"PRIu32"",
		x, width, y, height);
}

static void xdgsurf_ackcfg(
	struct wl_client* cl, struct wl_resource* res, uint32_t serial)
{
	trace("xdgsurf_ackcfg");
}

static void xdgsurf_destroy(
	struct wl_client* cl, struct wl_resource* res)
{
	trace("xdgsurf_destroy");
}
