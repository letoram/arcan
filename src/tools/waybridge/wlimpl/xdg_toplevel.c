/*
 * => VIEWPORT
 */
static void xdgtop_setparent(
	struct wl_client* cl, struct wl_resource* res, struct wl_resource* parent)
{
	trace("xdgtop_setparent");
}

static void xdgtop_title(
	struct wl_client* cl, struct wl_resource* res, const char* title)
{
	trace("xdgtop_title");
	struct comp_surf* surf = wl_resource_get_user_data(res);

	arcan_event ev = {
		.ext.kind = ARCAN_EVENT(IDENT)
	};
	size_t lim = sizeof(ev.ext.message.data)/sizeof(ev.ext.message.data[1]);
	snprintf((char*)ev.ext.message.data, lim, "%s", title);
	arcan_shmif_enqueue(&surf->acon, &ev);
}

static void xdgtop_appid(
	struct wl_client* cl, struct wl_resource* res, const char* app_id)
{
	trace("xdgtop_app_id");
	/* I wondered how long it would take for D-Bus to rear its ugly
	 * face along with the .desktop clusterfuck. I wonder no more.
	 * we can wrap this around some _message call and leave it to
	 * the appl to determine if the crap should be bridged or not. */
}

static void xdgtop_wndmenu(struct wl_client* cl, struct wl_resource* res,
	struct wl_resource* seat, uint32_t serial, int32_t x, int32_t y)
{
	trace("xdgtop_wndmenu (%"PRId32", %"PRId32")", x, y);
}

/*
 * "The server may ignore move requests depending on the state of
 * the surface (e.g. fullscreen or maximized), or if the passed
 * serial is no longer valid."
 *
 *  i.e. the state can be such that it never needs to drag-move..
 *
 * "If triggered, the surface will lose the focus of the device
 * (wl_pointer, wl_touch, etc) used for the move. It is up to the
 * compositor to visually indicate that the move is taking place,
 * such as updating a pointer cursor, during the move. There is no
 * guarantee that the device focus will return when the move is
 * completed."
 *
 * so this implies that the compositor actually needs to have
 * state cursors.
 *  => _CURSORHINT
 */
static void xdgtop_move(struct wl_client* cl,
	struct wl_resource* res, struct wl_resource* seat, uint32_t serial)
{
	trace("xdgtop_move");
}

/*
 * => _CURSORHINT
 */
static void xdgtop_resize(struct wl_client* cl, struct wl_resource* res,
	struct wl_resource* seat, uint32_t serial, uint32_t edges)
{
	trace("xdgtop_resize");
}

/*
 * => We need to track this in the client structure so that the
 * reconfigure done in reaction to DISPLAYHINT constrain this.
 *
 * All these comes for the reason that the titlebar lives in the
 * client as part of the toplevel surface.
 */
static void xdgtop_set_max(struct wl_client* cl,
	struct wl_resource* res, int32_t width, int32_t height)
{
	trace("xdgtop_set_max (%"PRIu32", %"PRIu32")");
}

/*
 * Same as with _max
 */
static void xdgtop_set_min(struct wl_client* cl,
	struct wl_resource* res, int32_t width, int32_t height)
{
	trace("xdgtop_set_min (%"PRId32", %"PRId32")", width, height);
}

/*
 * Hmm, this actually has implications for the presence of shadow
 */
static void xdgtop_maximize(
	struct wl_client* cl, struct wl_resource* res)
{
	trace("xdgtop_maximize");
}

static void xdgtop_demaximize(
	struct wl_client* cl, struct wl_resource* res)
{
	trace("xdgtop_demaximize");
}

static void xdgtop_fullscreen(
	struct wl_client* cl, struct wl_resource* res, struct wl_resource* output)
{
	trace("xdgtop_fullscreen");
}

static void xdgtop_unset_fullscreen(
	struct wl_client* cl, struct wl_resource* res)
{
	trace("xdgtop_unset_fullscreen");
}

static void xdgtop_minimize(
	struct wl_client* cl, struct wl_resource* res)
{
	trace("xdgtop_minimize");
}

static void xdgtop_destroy(
	struct wl_client* cl, struct wl_resource* res)
{
	trace("xdgtop_destroy");
}
