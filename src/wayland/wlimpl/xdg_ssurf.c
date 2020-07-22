static bool xdgpop_defer_handler(
	struct surface_request* req, struct arcan_shmif_cont* con)
{
	if (!con){
		trace(TRACE_SHELL, "reqfail");
		wl_resource_post_no_memory(req->target);
		return false;
	}

/*
 * PROTOCOL NOTE:
 * positioner needs to be validated: non-zero size, non-zero anchor is needed,
 * else send: ZXDG_SHELL_V6_ERROR_INVALID_POSITIONER
 *
 * parent needs to be validated,
 * else send ZXDG_SHELL_V6_ERROR_POPUP_PARENT
 *
 * + destroy- rules that are a bit clunky
 */
	struct wl_resource* popup = wl_resource_create(req->client->client,
		&xdg_popup_interface, wl_resource_get_version(req->target), req->id);

	if (!popup){
		wl_resource_post_no_memory(req->target);
		return false;
	}

	struct comp_surf* surf = wl_resource_get_user_data(req->target);
	wl_resource_set_implementation(popup, &xdgpop_if, surf, NULL);
	surf->acon = *con;
	surf->cookie = 0xfeedface;
	surf->shell_res = popup;
	surf->dispatch = xdgpopup_shmifev_handler;

	snprintf(surf->tracetag, SURF_TAGLEN, "xdg_popup");
	arcan_shmif_enqueue(&surf->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(MESSAGE),
		.ext.message.data = {"shell:xdg_popup"}
	});

/* update the viewport hint and send that event */
	bool upd_view = false;
	if (req->positioner){
		struct positioner* pos = wl_resource_get_user_data(req->positioner);
		apply_positioner(pos, &surf->viewport);
		upd_view = true;
	}

	if (req->parent){
		struct comp_surf* psurf = wl_resource_get_user_data(req->parent);
		if (!psurf->acon.addr){
			trace(TRACE_ALLOC, "bad popup, broken parent");
			return false;
		}
		surf->viewport.ext.viewport.parent = psurf->acon.segment_token;
		upd_view = true;
	}

/* likely that if this is not true, we have a protocol error */
	if (upd_view){
		arcan_shmif_enqueue(&surf->acon, &surf->viewport);
		xdg_popup_send_configure(popup,
			surf->viewport.ext.viewport.x, surf->viewport.ext.viewport.y,
			surf->viewport.ext.viewport.w, surf->viewport.ext.viewport.h);
		xdg_surface_send_configure(surf->surf_res, STEP_SERIAL());
	}

	surf->internal = xdgpop_internal;
	return true;
}

static bool xdgtop_defer_handler(
	struct surface_request* req, struct arcan_shmif_cont* con)
{
	if (!con){
		trace(TRACE_SHELL, "xdgsurf:reqfail");
		wl_resource_post_no_memory(req->target);
		return false;
	}

	struct wl_resource* toplevel = wl_resource_create(req->client->client,
		&xdg_toplevel_interface, wl_resource_get_version(req->target), req->id);

	if (!toplevel){
		wl_resource_post_no_memory(req->target);
		return false;
	}

	struct comp_surf* surf = wl_resource_get_user_data(req->target);
	wl_resource_set_implementation(toplevel, &xdgtop_if, surf, NULL);
	surf->acon = *con;
	surf->cookie = 0xfeedface;
	surf->shell_res = toplevel;
	surf->dispatch = xdgtoplevel_shmifev_handler;
	snprintf(surf->tracetag, SURF_TAGLEN, "xdg_toplevel");

/* propagate this so the scripts have a chance of following the restrictions
 * indicated by the protocol */
	arcan_shmif_enqueue(&surf->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(MESSAGE),
		.ext.message.data = {"shell:xdg_top"}
	});

	struct wl_array states;
	wl_array_init(&states);

	size_t w = surf->acon.w;
	size_t h = surf->acon.h;
	if (wl.force_sz){
		w = wl.init.display_width_px * (1.0 / surf->scale);
		h = wl.init.display_height_px * (1.0 / surf->scale);
	}

	xdg_toplevel_send_configure(toplevel, w, h, &states);
	xdg_surface_send_configure(surf->surf_res, STEP_SERIAL());
	surf->internal = xdgtop_internal;
	wl_array_release(&states);
	return true;
}

static void xdgsurf_toplevel(
	struct wl_client* cl, struct wl_resource* res, uint32_t id)
{
	trace(TRACE_SHELL, "%"PRIu32, id);
	struct comp_surf* surf = wl_resource_get_user_data(res);

/* though it is marked as 'defered' here, chances are that the request
 * function will just return with the surface immediately */
	request_surface(surf->client, &(struct surface_request){
		.segid = SEGID_APPLICATION,
		.target = res,
		.id = id,
		.trace = "xdg toplevel",
		.dispatch = xdgtop_defer_handler,
		.client = surf->client,
		.source = surf
	}, 't');
}

static void xdgsurf_getpopup(struct wl_client* cl, struct wl_resource* res,
	uint32_t id, struct wl_resource* parent, struct wl_resource* positioner)
{
	trace(TRACE_SHELL, "xdgsurf_getpopup");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	request_surface(surf->client, &(struct surface_request ){
		.segid = SEGID_POPUP,
		.target = res,
		.id = id,
		.trace = "xdg popup",
		.dispatch = xdgpop_defer_handler,
		.client = surf->client,
		.source = surf,
		.parent = parent,
		.positioner = positioner
	}, 'p');
}

/* Hints about the window visible size sans dropshadows and things like that,
 * but since it doesn't carry information about decorations (titlebar, ...)
 * we can't actually use this for a full viewport hint. Still better than
 * nothing and since we WM script need to take 'special ed' considerations
 * for xdg- clients anyhow, go with that. */
static void xdgsurf_set_geometry(struct wl_client* cl,
	struct wl_resource* res, int32_t x, int32_t y, int32_t width, int32_t height)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (!surf)
		return;

	trace(TRACE_SHELL, "xdgsurf_setgeom("
		"%"PRIu32"+%"PRIu32", %"PRIu32"+%"PRIu32")", x, y, width, height);

/* the better way is to use the tldr[] from the VIEWPORT hint,
 * we just need a 'dirty- viewport' and a cache of the properties first */
	struct arcan_event ev = {
		.ext.kind = ARCAN_EVENT(MESSAGE)
	};
	snprintf((char*)ev.ext.message.data,
		COUNT_OF(ev.ext.message.data),
		"geom:%"PRIu32":%"PRIu32":%"PRIu32":%"PRIu32,	x, y, width, height
	);

	surf->geom_x = x;
	surf->geom_y = y;
	surf->geom_w = width;
	surf->geom_h = height;
	arcan_shmif_enqueue(&surf->acon, &ev);
}

static void xdgsurf_ackcfg(
	struct wl_client* cl, struct wl_resource* res, uint32_t serial)
{
	trace(TRACE_SHELL, "%"PRIu32, serial);
/* reading the spec for this makes it seem like there can be many
 * 'in flight' cfgs and you need to send ack individually and thus
 * track pending cfgs that lacks an acq */
}

static void xdgsurf_destroy(
	struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "%"PRIxPTR, res);
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (surf){
		surf->shell_res = NULL;
		surf->internal = NULL;
	}
	wl_resource_destroy(res);
}
