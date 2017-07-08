static bool xdgsurf_shmifev_handler(
	struct comp_surf* surf, struct arcan_event* ev)
{
	if (!surf->shell_res)
		return true;

	if (ev->category == EVENT_TARGET)
		switch (ev->tgt.kind){

		case TARGET_COMMAND_DISPLAYHINT:{
		/* update state tracking first */
			trace("displayhint(%d, %d, %d, %d) = (%d*%d)",
				ev->tgt.ioevs[0].iv, ev->tgt.ioevs[1].iv,
				ev->tgt.ioevs[2].iv, ev->tgt.ioevs[3].iv, surf->acon.w, surf->acon.h);

			bool changed = displayhint_handler(surf, &ev->tgt);

/* and then, if something has changed, send the configure event */
			int w = ev->tgt.ioevs[0].iv ? ev->tgt.ioevs[0].iv : 0;
			int h = ev->tgt.ioevs[1].iv ? ev->tgt.ioevs[1].iv : 0;
			if (changed || (w && h && (w != surf->acon.w || h != surf->acon.h))){
				struct wl_array states;
				trace("xdg_surface(request resize to %d*%d)", w, h);
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

static bool xdgsurf_defer_handler(
	struct surface_request* req, struct arcan_shmif_cont* con)
{
	if (!con){
		trace("xdgsurf:reqfail");
		wl_resource_post_no_memory(req->target);
		return false;
	}

	struct wl_resource* toplevel = wl_resource_create(req->client->client,
		&zxdg_toplevel_v6_interface, wl_resource_get_version(req->target), req->id);

	if (!toplevel){
		wl_resource_post_no_memory(req->target);
		return false;
	}

	struct comp_surf* surf = wl_resource_get_user_data(req->target);
	wl_resource_set_implementation(toplevel, &xdgtop_if, surf, NULL);
	surf->acon = *con;
	surf->cookie = 0xfeedface;
	surf->shell_res = toplevel;
	surf->dispatch = xdgsurf_shmifev_handler;

/* propagate this so the scripts have a chance of following the restrictions
 * indicated by the protocol */
	arcan_shmif_enqueue(&surf->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(MESSAGE),
		.ext.message.data = {"shell:xdg_shell"}
	});

	struct wl_array states;
	wl_array_init(&states);
	zxdg_toplevel_v6_send_configure(toplevel, surf->acon.w, surf->acon.h, &states);
	wl_array_release(&states);
	return true;
}

static void xdgsurf_toplevel(
	struct wl_client* cl, struct wl_resource* res, uint32_t id)
{
	trace("xdgsurf_toplevel");
	struct comp_surf* surf = wl_resource_get_user_data(res);

/* though it is marked as 'defered' here, chances are that the request
 * function will just return with the surface immediately */
	request_surface(surf->client, &(struct surface_request){
		.segid = SEGID_APPLICATION,
		.target = res,
		.id = id,
		.trace = "xdg toplevel",
		.dispatch = xdgsurf_defer_handler,
		.client = surf->client,
		.source = surf
	});
}

static void xdgsurf_getpopup(struct wl_client* cl, struct wl_resource* res,
	uint32_t id, struct wl_resource* parent, struct wl_resource* positioner)
{
	trace("xdgsurf_getpopup");

/* "theoretically" we could've used the SEGID_POPUP etc. type when
 * requesting the surface, BUT there's nothing stopping the client from
 * taking a toplevel surface and promoting to a popup or menu, so this
 * distinction is pointless. */
}

/* Hints about the window visible size sans dropshadows and things like that,
 * but since it doesn't carry information about decorations (titlebar, ...)
 * we can't actually use this for a full viewport hint. Still better than
 * nothing and since we WM script need to take 'special ed' considerations
 * for xdg- clients anyhow, go with that. */
static void xdgsurf_set_geometry(struct wl_client* cl,
	struct wl_resource* res, int32_t x, int32_t y, int32_t width, int32_t height)
{
	trace("xdgsurf_setgeom("
		"%"PRIu32"+%"PRIu32", %"PRIu32"+%"PRIu32")", x, y, width, height);

	struct comp_surf* surf = wl_resource_get_user_data(res);
	arcan_shmif_enqueue(&surf->acon,
		&(struct arcan_event){
			.ext.kind = ARCAN_EVENT(VIEWPORT),
			.ext.viewport = {
				.x = x,
				.y = y,
				.w = width,
				.h = height
			}
	});
}

static void xdgsurf_ackcfg(
	struct wl_client* cl, struct wl_resource* res, uint32_t serial)
{
	trace("xdgsurf_ackcfg");
}

static void xdgsurf_destroy(
	struct wl_client* cl, struct wl_resource* res)
{
	trace("xdgsurf_destroy");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	surf->shell_res = NULL;
}
