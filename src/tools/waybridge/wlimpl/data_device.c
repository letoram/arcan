static void ddev_start_drag(struct wl_client* cl,
	struct wl_resource* res, struct wl_resource* src,
	struct wl_resource* origin, struct wl_resource* icon,
	uint32_t serial)
{
	trace("ddev:start drag");
}

static void ddev_set_selection(struct wl_client* cl,
	struct wl_resource* res, struct wl_resource* src,
	uint32_t serial)
{
	trace("ddev:set selection");
}

static void ddev_release(struct wl_client* cl,
	struct wl_resource* res)
{
	trace("ddev:release");
}
