void xdgsurf_toplevel(struct wl_client* cl, struct wl_resource* res,
	uint32_t id)
{
	trace("xdgsurf_toplevel");
	struct wl_array states;
	struct bridge_surf* surf = wl_resource_get_user_data(res);
	struct wl_resource* toplevel = wl_resource_create(cl,
		&zxdg_toplevel_v6_interface, wl_resource_get_version(res), id);
	if (!toplevel){
		wl_resource_post_no_memory(res);
		return;
	}
	wl_resource_set_implementation(toplevel, &xdgtop_if, surf, NULL);

	wl_array_init(&states);
	zxdg_toplevel_v6_send_configure(toplevel, surf->acon->w, surf->acon->h, &states);
	wl_array_release(&states);
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
