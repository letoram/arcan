void xdgtop_setparent(struct wl_client* cl, struct wl_resource* res,
	struct wl_resource* parent)
{
	trace("xdgtop_setparent");
}

void xdgtop_title(struct wl_client* cl, struct wl_resource* res,
	const char* title)
{
	trace("xdgtop_title");
	/* just update the ident */
}

void xdgtop_appid(struct wl_client* cl, struct wl_resource* res,
	const char* app_id)
{
	trace("xdgtop_app_id");
	/* I wondered how long it would take for D-Bus to rear its ugly
	 * face along with the .desktop clusterfuck. I wonder no more.
	 * we can wrap this around some _message call and leave it to
	 * the appl to determine if the crap should be bridged or not. */
}

void xdgtop_wndmenu(struct wl_client* cl, struct wl_resource* res,
	struct wl_resource* seat, uint32_t serial, int32_t x, int32_t y)
{
	trace("xdgtop_wndmenu");
}

void xdgtop_move(struct wl_client* cl, struct wl_resource* res,
	struct wl_resource* seat, uint32_t serial)
{
	trace("xdgtop_move");
}

void xdgtop_resize(struct wl_client* cl, struct wl_resource* res,
	struct wl_resource* seat, uint32_t serial, uint32_t edges)
{
	trace("xdgtop_resize");
}

void xdgtop_set_max(struct wl_client* cl, struct wl_resource* res,
	int32_t width, int32_t height)
{
	trace("xdgtop_set_max");
}

void xdgtop_set_min(struct wl_client* cl, struct wl_resource* res,
	int32_t width, int32_t height)
{
	trace("xdgtop_set_min");
}

void xdgtop_maximize(struct wl_client* cl, struct wl_resource* res)
{
	trace("xdgtop_maximize");
}

void xdgtop_demaximize(struct wl_client* cl, struct wl_resource* res)
{
	trace("xdgtop_demaximize");
}

void xdgtop_fullscreen(struct wl_client* cl, struct wl_resource* res,
	struct wl_resource* output)
{
	trace("xdgtop_fullscreen");
}

void xdgtop_unset_fullscreen(struct wl_client* cl, struct wl_resource* res)
{
	trace("xdg_unset_fullscreen");
}

void xdgtop_minimize(struct wl_client* cl, struct wl_resource* res)
{
	trace("xdg_minimize");
}
