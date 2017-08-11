static void ssurf_pong(struct wl_client *client,
	struct wl_resource *resource, uint32_t serial)
{
/* protocol: parent pings, child must pong or be deemed unresponsive */
	trace(TRACE_SHELL, "pong (%"PRIu32")", serial);
}

static void ssurf_move(struct wl_client *client,
	struct wl_resource *resource, struct wl_resource *seat, uint32_t serial)
{
	trace(TRACE_SHELL, "drag_move (%"PRIu32")", serial);
/* mouse drag move, s'ppose the CSD approach forces you to that .. */
}

static void ssurf_resize(struct wl_client *client,
	struct wl_resource *resource, struct wl_resource *seat,
	uint32_t serial, uint32_t edges)
{
	trace(TRACE_SHELL, "drag_resize (%"PRIu32")", serial);
/* mouse drag resize, again because of the whole CSD */
}

static void ssurf_toplevel(struct wl_client *client,
	struct wl_resource *resource)
{
/* toplevel seem to match what we mean with a primary surface, thus
 * we need some method to reassign wayland surfaces with segments */
	trace(TRACE_SHELL, "toplevel()");
}

static void ssurf_transient(struct wl_client *client,
	struct wl_resource *resource, struct wl_resource *parent,
	int32_t x, int32_t y, uint32_t flags)
{
/*
 * so this is reparenting a surface, same as with toplevel
 */
	trace(TRACE_SHELL, "viewport/relative %d, %d\n", (int)x, (int)y);
}

static void ssurf_fullscreen(struct wl_client *client,
	struct wl_resource *resource, uint32_t method,
	uint32_t framerate, struct wl_resource *output)
{
	trace(TRACE_SHELL, "fullscreen\n");
}

static void ssurf_popup(struct wl_client *client,
	struct wl_resource *resource, struct wl_resource *seat,
	uint32_t serial, struct wl_resource *parent,
	int32_t x, int32_t y, uint32_t flags)
{
	trace(TRACE_SHELL, "popup\n");
/* that any surface can fullfill any role is such a pain */
}

static void ssurf_maximized(struct wl_client *client,
	struct wl_resource *resource, struct wl_resource *output)
{
	trace(TRACE_SHELL, "surf_maximize()\n");
	struct comp_surf* surf = wl_resource_get_user_data(resource);
	if (!surf)
		return;

/*
 * Fix this and simiar issues for real by having a viewport- event
 * tracked in the surface metadata, update the layout hinting with
 * a maximized flag and be done with it
 */
}

/*
 * We don't know a title when we open the connection, so wl- clients
 * have to go through the annoyance of using the IDENT state instead.
 * This means appl- side script need to have different title - ident
 * behavior for bridge-wayland SEGID.
 */
static void ssurf_title(struct wl_client* client,
	struct wl_resource* resource, const char* title)
{
	trace(TRACE_SHELL, "title(%s)", title ? title : "no title");
	struct comp_surf* surf = wl_resource_get_user_data(resource);

	arcan_event ev = {
		.ext.kind = ARCAN_EVENT(IDENT)
	};
	size_t lim = sizeof(ev.ext.message.data)/sizeof(ev.ext.message.data[1]);
	snprintf((char*)ev.ext.message.data, lim, "%s", title);
	arcan_shmif_enqueue(&surf->acon, &ev);
}

static void ssurf_class(struct wl_client *client,
struct wl_resource *resource, const char *class_)
{
	trace(TRACE_SHELL, "class(%s)", class_ ? class_ : "no class"); /* indeed */
}
