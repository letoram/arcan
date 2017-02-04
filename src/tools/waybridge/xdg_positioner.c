void xdgpos_size(struct wl_client* cl, struct wl_resource* res,
	int32_t width, int32_t height)
{
	trace("xdgpos_set_size");
}

void xdgpos_anchor_rect(struct wl_client* cl, struct wl_resource* res,
	int32_t x, int32_t y, int32_t width, int32_t height)
{
	trace("xdgpos_anchor_rect");
}

void xdgpos_anchor(struct wl_client* cl, struct wl_resource* res,
	uint32_t anchor)
{
	trace("xdgpos_anchor");
}

void xdgpos_gravity(struct wl_client* cl, struct wl_resource* res,
	uint32_t gravity)
{
	trace("xdgpos_gravity");
}

void xdgpos_consadj(struct wl_client* cl, struct wl_resource* res,
	uint32_t constraint_adjustment)
{
	trace("xdgpos_consadj");
}

void xdgpos_offset(struct wl_client* cl, struct wl_resource* res,
	int32_t x, int32_t y)
{
	trace("xdgpos_offset");
}
