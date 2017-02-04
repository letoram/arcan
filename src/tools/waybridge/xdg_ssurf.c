void xdgsurf_toplevel(struct wl_client* cl, struct wl_resource* res,
	uint32_t id)
{
	trace("xdgsurf_toplevel");
}

void xdgsurf_getpopup(struct wl_client* cl, struct wl_resource* res,
	uint32_t id, struct wl_resource* parent, struct wl_resource* positioner)
{
	trace("xdgsurf_getpopup");
}

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
