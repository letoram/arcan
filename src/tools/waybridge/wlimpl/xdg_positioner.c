static void xdgpos_size(struct wl_client* cl,
	struct wl_resource* res, int32_t width, int32_t height)
{
	trace(TRACE_SHELL, "xdgpos_set_size");
}

static void xdgpos_anchor_rect(struct wl_client* cl,
	struct wl_resource* res, int32_t x, int32_t y, int32_t width, int32_t height)
{
	trace(TRACE_SHELL, "xdgpos_anchor_rect");
}

static void xdgpos_anchor(struct wl_client* cl,
	struct wl_resource* res, uint32_t anchor)
{
	trace(TRACE_SHELL, "xdgpos_anchor");
}

static void xdgpos_gravity(struct wl_client* cl,
	struct wl_resource* res, uint32_t gravity)
{
	trace(TRACE_SHELL, "xdgpos_gravity");
}

static void xdgpos_consadj(struct wl_client* cl,
	struct wl_resource* res, uint32_t constraint_adjustment)
{
	trace(TRACE_SHELL, "xdgpos_consadj");
}

static void xdgpos_offset(struct wl_client* cl,
	struct wl_resource* res, int32_t x, int32_t y)
{
	trace(TRACE_SHELL, "xdgpos_offset");
}

static void xdgpos_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "xdgpos_destroy");
}
