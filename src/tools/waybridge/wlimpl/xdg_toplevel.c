static bool xdgtoplevel_shmifev_handler(
	struct comp_surf* surf, struct arcan_event* ev)
{
	if (!surf->shell_res)
		return true;

	if (ev->category == EVENT_TARGET)
		switch (ev->tgt.kind){

		case TARGET_COMMAND_DISPLAYHINT:{
		/* update state tracking first */
			trace(TRACE_SHELL, "xdg-toplevel:displayhint(%d, %d, %d, %d) = (%d*%d)",
				ev->tgt.ioevs[0].iv, ev->tgt.ioevs[1].iv,
				ev->tgt.ioevs[2].iv, ev->tgt.ioevs[3].iv, surf->acon.w, surf->acon.h);

			bool changed = displayhint_handler(surf, &ev->tgt);

/* and then, if something has changed, send the configure event */
			int w = ev->tgt.ioevs[0].iv ? ev->tgt.ioevs[0].iv : 0;
			int h = ev->tgt.ioevs[1].iv ? ev->tgt.ioevs[1].iv : 0;
			if (changed || (w && h && (w != surf->acon.w || h != surf->acon.h))){
				struct wl_array states;
				trace(TRACE_SHELL, "xdg_surface(request resize to %d*%d)", w, h);
				wl_array_init(&states);
				uint32_t* sv;
				if (surf->states.maximized){
					sv = wl_array_add(&states, sizeof(uint32_t));
					*sv = ZXDG_TOPLEVEL_V6_STATE_MAXIMIZED;
				}

				if (surf->states.drag_resize){
					sv = wl_array_add(&states, sizeof(uint32_t));
					*sv = ZXDG_TOPLEVEL_V6_STATE_RESIZING;
				}

				if (!surf->states.unfocused){
					sv = wl_array_add(&states, sizeof(uint32_t));
					*sv = ZXDG_TOPLEVEL_V6_STATE_ACTIVATED;
				}

				zxdg_toplevel_v6_send_configure(surf->shell_res, w, h, &states);
				wl_array_release(&states);
				changed = true;
			}

			if (changed)
				try_frame_callback(surf);
		}
		return true;
		break;
		case TARGET_COMMAND_EXIT:
			zxdg_toplevel_v6_send_close(surf->shell_res);
			return true;
		break;
		default:
		break;
		}

	return false;
}

/*
 * => VIEWPORT
 */
static void xdgtop_setparent(
	struct wl_client* cl, struct wl_resource* res, struct wl_resource* parent)
{
	trace(TRACE_SHELL, "xdgtop_setparent");
}

static void xdgtop_title(
	struct wl_client* cl, struct wl_resource* res, const char* title)
{
	trace(TRACE_SHELL, "xdgtop_title");
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
	trace(TRACE_SHELL, "xdgtop_app_id");
	/* I wondered how long it would take for D-Bus to rear its ugly
	 * face along with the .desktop clusterfuck. I wonder no more.
	 * we can wrap this around some _message call and leave it to
	 * the appl to determine if the crap should be bridged or not. */
}

static void xdgtop_wndmenu(struct wl_client* cl, struct wl_resource* res,
	struct wl_resource* seat, uint32_t serial, int32_t x, int32_t y)
{
	trace(TRACE_SHELL, "xdgtop_wndmenu (%"PRId32", %"PRId32")", x, y);
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
	trace(TRACE_SHELL, "xdgtop_move");
}

/*
 * => _CURSORHINT
 */
static void xdgtop_resize(struct wl_client* cl, struct wl_resource* res,
	struct wl_resource* seat, uint32_t serial, uint32_t edges)
{
	trace(TRACE_SHELL, "xdgtop_resize");
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
	trace(TRACE_SHELL, "xdgtop_set_max (%"PRIu32", %"PRIu32")");
}

/*
 * Same as with _max
 */
static void xdgtop_set_min(struct wl_client* cl,
	struct wl_resource* res, int32_t width, int32_t height)
{
	trace(TRACE_SHELL, "xdgtop_set_min (%"PRId32", %"PRId32")", width, height);
}

/*
 * Hmm, this actually has implications for the presence of shadow
 */
static void xdgtop_maximize(
	struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "xdgtop_maximize");
}

static void xdgtop_demaximize(
	struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "xdgtop_demaximize");
}

static void xdgtop_fullscreen(
	struct wl_client* cl, struct wl_resource* res, struct wl_resource* output)
{
	trace(TRACE_SHELL, "xdgtop_fullscreen");
}

static void xdgtop_unset_fullscreen(
	struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "xdgtop_unset_fullscreen");
}

static void xdgtop_minimize(
	struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "xdgtop_minimize");
}

static void xdgtop_destroy(
	struct wl_client* cl, struct wl_resource* res)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);

/* so we don't send a _leave to a dangling surface */
	if (surf && surf->client){
		if (surf->client->last_cursor == res)
			surf->client->last_cursor = NULL;
	}
	trace(TRACE_ALLOC, "xdgtop_destroy");
}
