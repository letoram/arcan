static bool xdgtoplevel_shmifev_handler(
	struct comp_surf* surf, struct arcan_event* ev)
{
	if (!surf->shell_res)
		return true;

	if (ev->category == EVENT_TARGET)
		switch (ev->tgt.kind){

		case TARGET_COMMAND_DISPLAYHINT:{
		/* update state tracking first */
			trace(TRACE_SHELL, "xdg-toplevel(%"PRIxPTR"):hint=%d,%d,%d,%d:size=%d,%d",
				(uintptr_t) surf,
				ev->tgt.ioevs[0].iv, ev->tgt.ioevs[1].iv,
				ev->tgt.ioevs[2].iv, ev->tgt.ioevs[3].iv, surf->acon.w, surf->acon.h);

			bool changed = displayhint_handler(surf, &ev->tgt);

/* and then, if something has changed, send the configure event */
			int w = ev->tgt.ioevs[0].iv ? ev->tgt.ioevs[0].iv : surf->acon.w;
			int h = ev->tgt.ioevs[1].iv ? ev->tgt.ioevs[1].iv : surf->acon.h;
			bool resized = (w && h && (w != surf->acon.w || h != surf->acon.h));

			if (changed || resized){
				struct wl_array states;

				if (resized){
					trace(TRACE_SHELL,
						"resizereq:last=%d,%d:req:=%d,%d",
						(int) surf->acon.w, (int) surf->acon.h, w, h);
				}

				wl_array_init(&states);
				uint32_t* sv;
				if (surf->states.maximized){
					sv = wl_array_add(&states, sizeof(uint32_t));
					*sv = XDG_TOPLEVEL_STATE_MAXIMIZED;
					trace(TRACE_SHELL, "maximized");
				}

				if (surf->states.drag_resize){
					sv = wl_array_add(&states, sizeof(uint32_t));
					*sv = XDG_TOPLEVEL_STATE_RESIZING;
					trace(TRACE_SHELL, "resizing");
				}

				if (!surf->states.unfocused){
					sv = wl_array_add(&states, sizeof(uint32_t));
					*sv = XDG_TOPLEVEL_STATE_ACTIVATED;
					trace(TRACE_SHELL, "focused");
				}

				if (wl.force_sz){
					w = wl.init.display_width_px;
					h = wl.init.display_height_px;
				}

				xdg_toplevel_send_configure(surf->shell_res, w, h, &states);
				xdg_surface_send_configure(surf->surf_res, STEP_SERIAL());
				wl_array_release(&states);
				changed = true;
			}

			if (changed)
				try_frame_callback(surf, &surf->acon);
		}
		return true;
		break;

/* Previously we flushed callbacks and released buffers here, but afaict
 * the proper procedure is to let the client do the closing as a response to
 * send_close. After this all arcan- related calls will fail on the surface, so
 * chances are that a window could go with something like 'do you really want
 * to close' and we can't actually draw that anywhere, this is not really
 * solvable, can only warn the appl- side about the perils of force closing a
 * wayland surface - unless there is some error we can send to fake it */
		case TARGET_COMMAND_EXIT:
/*
 * try_frame_callback(surf, &surf->acon);
 */
			xdg_toplevel_send_close(surf->shell_res);
			return true;
		break;
		default:
		break;
		}

	return false;
}

static void xdgtop_setparent(
	struct wl_client* cl, struct wl_resource* res, struct wl_resource* parent)
{
	trace(TRACE_SHELL, "parent: %"PRIxPTR, (uintptr_t) parent);
	struct comp_surf* surf = wl_resource_get_user_data(res);
	uint32_t par_token = 0;
	int8_t order = 0;

	if (parent){
		struct comp_surf* par = wl_resource_get_user_data(parent);
		par_token = par->acon.segment_token;
		order = par->viewport.ext.viewport.order + 1;
	}
	surf->viewport.ext.viewport.order = order;
	surf->viewport.ext.viewport.parent = par_token;

/* Likely that we need more order tracking for subsurfaces, or shift
 * the relative assignment to the scripting layer again */
	arcan_shmif_enqueue(&surf->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(VIEWPORT),
		.ext.viewport.parent = par_token,
		.ext.viewport.order = order
	});
}

static void xdgtop_title(
	struct wl_client* cl, struct wl_resource* res, const char* title)
{
	trace(TRACE_SHELL, "%s", title ? title : "(null)");
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
	trace(TRACE_SHELL, "@x,y: %"PRId32", %"PRId32"", x, y);
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
	trace(TRACE_SHELL, "%"PRIxPTR", serial: %"PRIu32, (uintptr_t) seat, serial);
	struct comp_surf* surf = wl_resource_get_user_data(res);
	arcan_shmif_enqueue(&surf->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(MESSAGE),
		.ext.message.data = {"shell:xdg_top:move"}
	});
}

static void xdg_edge_to_mask(uint32_t edges, int* dx, int* dy)
{
	switch (edges){
	case XDG_TOPLEVEL_RESIZE_EDGE_TOP:
		*dx = 0; *dy = -1;
	break;
	case XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM:
		*dx = 0; *dy = 1;
	break;
	case XDG_TOPLEVEL_RESIZE_EDGE_LEFT:
		*dx = -1; *dy = 0;
	break;
	case XDG_TOPLEVEL_RESIZE_EDGE_TOP_LEFT:
		*dx = -1; *dy = -1;
	break;
	case XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_LEFT:
		*dx = -1; *dy = 1;
	break;
	case XDG_TOPLEVEL_RESIZE_EDGE_RIGHT:
		*dx = 1; *dy = 0;
	break;
	case XDG_TOPLEVEL_RESIZE_EDGE_TOP_RIGHT:
		*dx = 1; *dy = -1;
	break;
	case XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_RIGHT:
		*dx = 1; *dy = 1;
	break;
	default:
		*dx = *dy = 0;
	}
}

static void xdgtop_resize(struct wl_client* cl, struct wl_resource* res,
	struct wl_resource* seat, uint32_t serial, uint32_t edges)
{
	trace(TRACE_SHELL, "serial: %"PRIu32", edges: %"PRIu32, serial, edges);
	struct comp_surf* surf = wl_resource_get_user_data(res);
	struct arcan_event ev = {
		.ext.kind = ARCAN_EVENT(MESSAGE)
	};

	int dx, dy;
	xdg_edge_to_mask(edges, &dx, &dy);
	size_t lim = sizeof(ev.ext.message.data)/sizeof(ev.ext.message.data[1]);
	snprintf((char*)ev.ext.message.data, lim, "shell:xdg_top:resize:%d:%d", dx, dy);
	arcan_shmif_enqueue(&surf->acon, &ev);
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
	trace(TRACE_SHELL, "xdgtop_set_max (%"PRId32", %"PRId32")");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	surf->max_w = width;
	surf->max_h = height;
}

/*
 * Same as with _max
 */
static void xdgtop_set_min(struct wl_client* cl,
	struct wl_resource* res, int32_t width, int32_t height)
{
	trace(TRACE_SHELL, "xdgtop_set_min (%"PRId32", %"PRId32")", width, height);
	struct comp_surf* surf = wl_resource_get_user_data(res);
	surf->min_w = width;
	surf->min_h = height;
}

/*
 * Hmm, this actually has implications for the presence of shadow
 */
static void xdgtop_maximize(
	struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "xdgtop_maximize");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	arcan_shmif_enqueue(&surf->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(MESSAGE),
		.ext.message.data = {"shell:xdg_top:maximize"}
	});
}

static void xdgtop_demaximize(
	struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "xdgtop_demaximize");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	arcan_shmif_enqueue(&surf->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(MESSAGE),
		.ext.message.data = {"shell:xdg_top:demaximize"}
	});
}

static void xdgtop_fullscreen(
	struct wl_client* cl, struct wl_resource* res, struct wl_resource* output)
{
	trace(TRACE_SHELL, "xdgtop_fullscreen");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	arcan_shmif_enqueue(&surf->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(MESSAGE),
		.ext.message.data = {"shell:xdg_top:fullscreen"}
	});
}

static void xdgtop_unset_fullscreen(
	struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "xdgtop_unset_fullscreen");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	arcan_shmif_enqueue(&surf->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(MESSAGE),
		.ext.message.data = {"shell:xdg_top:defullscreen"}
	});
}

static void xdgtop_minimize(
	struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "xdgtop_minimize");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	arcan_shmif_enqueue(&surf->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(MESSAGE),
		.ext.message.data = {"shell:xdg_top:minimize"}
	});
}

static void xdgtop_destroy(
	struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "%"PRIxPTR, (uintptr_t)res);
	struct comp_surf* surf = wl_resource_get_user_data(res);

/* so we don't send a _leave to a dangling surface */
	if (surf && surf->client){
		if (surf->client->last_cursor == res)
			surf->client->last_cursor = NULL;
	}
}
