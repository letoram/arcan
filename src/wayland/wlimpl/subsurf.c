static bool subsurf_shmifev_handler(
	struct comp_surf* surf, struct arcan_event* ev)
{
	trace(TRACE_SURF, "subsurface - shmif: %s\n",
		arcan_shmif_eventstr(ev, NULL, 0));
	return false;
}

static void subsurf_destroy(struct wl_client *cl, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	destroy_comp_surf(surf, false);
}

static void subsurf_position(
	struct wl_client *cl, struct wl_resource* res, int32_t x, int32_t y)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (!surf){
		trace(TRACE_SURF, "position on broken subsurf");
		return;
	}
	else
		trace(TRACE_SURF, "x,y - %"PRId32", %"PRId32, x, y);

	surf->viewport.ext.viewport.x = x;
	surf->viewport.ext.viewport.y = y;
	arcan_shmif_enqueue(&surf->acon, &surf->viewport);
}

static void subsurf_placeabove(
	struct wl_client *cl, struct wl_resource* res, struct wl_resource* sibl)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);
	struct comp_surf* surf_sibl = wl_resource_get_user_data(sibl);
	if (!surf || !surf_sibl){
		trace(TRACE_SURF, "placeabove on broken subsurf");
		return;
	}

	trace(TRACE_SHELL, "@above(%"PRIxPTR")", (uintptr_t)sibl);

	if (surf_sibl->viewport.ext.viewport.order < 127)
		surf->viewport.ext.viewport.order = surf_sibl->viewport.ext.viewport.order+1;

/* synch parent cookie token */
	struct comp_surf* surf_parent = wl_resource_get_user_data(surf->sub_parent_res);
	if (surf_parent && surf_parent->acon.addr){
		surf->viewport.ext.viewport.parent = surf_parent->acon.segment_token;
	}
	else {
		trace(TRACE_SHELL, "placeabove on empty parent\n");
	}

	arcan_shmif_enqueue(&surf->acon, &surf->viewport);
}

static void subsurf_placebelow(
	struct wl_client *cl, struct wl_resource* res, struct wl_resource* sibl)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);
	struct comp_surf* surf_sibl = wl_resource_get_user_data(sibl);
	if (!surf || !surf_sibl){
		trace(TRACE_SURF, "placeabove on broken subsurf");
		return;
	}

	trace(TRACE_SURF, "@below(%"PRIxPTR")", (uintptr_t)sibl);
	if (surf_sibl->viewport.ext.viewport.order > -128)
		surf->viewport.ext.viewport.order = surf_sibl->viewport.ext.viewport.order-1;
	arcan_shmif_enqueue(&surf->acon, &surf->viewport);
}

static void subsurf_setsync(struct wl_client *cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "");
}

static void subsurf_setdesync(struct wl_client *cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "");
}
