/* LOCKING considers a restricted region as well as a warp */
void lockptr_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SEAT, "destroy");
	struct comp_surf* surf = wl_resource_get_user_data(res);

	if (surf->confined != res)
		return;

	surf->confined = NULL;
	wl_resource_destroy(res);
}

void lockptr_region(struct wl_client* cl,
	struct wl_resource* res, struct wl_resource* reg)
{
	trace(TRACE_SEAT, "lock_region");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	surf->locked = true;

	struct surface_region* region = wl_resource_get_user_data(reg);
	if (surf->confine_region){
		free_region(surf->confine_region);
		surf->confine_region = NULL;
	}

	if (region){
		surf->confine_region = duplicate_region(region);
	}

	update_confinement(surf);
}

void lockptr_hintat(struct wl_client* cl,
	struct wl_resource* res, wl_fixed_t x, wl_fixed_t y)
{
	trace(TRACE_SEAT, "lock_hint_at");
/* hint for saying 'on unlock, I believe cursor to be here', safe to ignore */
}
