static void subsurf_destroy(struct wl_client *cl, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "destroy:subsurface");
}

static void subsurf_position(
	struct wl_client *cl, struct wl_resource* res, int32_t x, int32_t y)
{
	trace(TRACE_SHELL, "subsurf_position");
}

static void subsurf_placeabove(
	struct wl_client *cl, struct wl_resource* res, struct wl_resource* sibl)
{
	trace(TRACE_SHELL, "subsurf_placeabove");
}

static void subsurf_placebelow(
	struct wl_client *cl, struct wl_resource* res, struct wl_resource* sibl)
{
	trace(TRACE_SHELL, "subsurf_placebelow");
}

static void subsurf_setsync(struct wl_client *cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "subsurf_setsync");
}

static void subsurf_setdesync(struct wl_client *cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "subsurf_setdesync");
}
