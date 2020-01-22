static void ddev_start_drag(struct wl_client* cl,
	struct wl_resource* res, struct wl_resource* src,
	struct wl_resource* origin, struct wl_resource* icon,
	uint32_t serial)
{
	trace(TRACE_DDEV, "ddev:start drag");
/*
 * this will be ugly as we someone need to tag the cursor,
 * it may be possible that we can create a cursor subsegment
 * to a the cursor subsegment and that would/should be enough
 */
}

static void ddev_set_selection(struct wl_client* cl,
	struct wl_resource* res, struct wl_resource* src,
	uint32_t serial)
{
	trace(TRACE_DDEV, "%"PRIu32);
}

static void ddev_release(struct wl_client* cl,
	struct wl_resource* res)
{
	trace(TRACE_DDEV, "%"PRIxPTR, (uintptr_t) res);
}
