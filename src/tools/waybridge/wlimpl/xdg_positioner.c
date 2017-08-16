static void xdgpos_size(struct wl_client* cl,
	struct wl_resource* res, int32_t width, int32_t height)
{
	trace(TRACE_SHELL, "%"PRId32", %"PRId32, width, height);
}

static void xdgpos_anchor_rect(struct wl_client* cl,
	struct wl_resource* res, int32_t x, int32_t y, int32_t width, int32_t height)
{
	trace(TRACE_SHELL, "x,y: %"PRId32", %"PRId32" w,h: %"PRId32", %"PRId32,
		x, y, width, height);
}

static void xdgpos_anchor(struct wl_client* cl,
	struct wl_resource* res, uint32_t anchor)
{
	trace(TRACE_SHELL, "%"PRIu32, anchor);
}

static void xdgpos_gravity(struct wl_client* cl,
	struct wl_resource* res, uint32_t gravity)
{
	trace(TRACE_SHELL, "%"PRIu32, gravity);
}

static void xdgpos_consadj(struct wl_client* cl,
	struct wl_resource* res, uint32_t constraint_adjustment)
{
	trace(TRACE_SHELL, "%"PRIu32, constraint_adjustment);
}

static void xdgpos_offset(struct wl_client* cl,
	struct wl_resource* res, int32_t x, int32_t y)
{
	trace(TRACE_SHELL, "+x,y: %"PRId32", %"PRId32, x, y);
}

static void xdgpos_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "%"PRIxPTR, (uintptr_t) res);
}
