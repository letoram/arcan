static void ddev_start_drag(
	struct wl_client* cl,
	struct wl_resource* ddev,

/* uncertain what underlying 'type' src and origin has, wl_surf? */
	struct wl_resource* src,
	struct wl_resource* origin,

/* set the icon as the seat cursor and message the cursor segment
 * to switch to default with the 'icon' as cursor tag */
	struct wl_resource* icon,
	uint32_t serial)
{
	trace(TRACE_DDEV, "ddev:start drag");
}

static void ddev_set_selection(
	struct wl_client* cl,
	struct wl_resource* ddev,
	struct wl_resource* selection,
	uint32_t serial)
{
	trace(TRACE_DDEV, "%"PRIu32);
	struct data_offer* offer = wl_resource_get_user_data(selection);
	if (!offer){
		return;
	}

	offer->device = ddev;
	offer->client = cl;
}

static void ddev_release(
	struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_DDEV, "%"PRIxPTR, (uintptr_t) res);
	wl_resource_destroy(res);
}
