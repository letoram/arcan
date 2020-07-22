void confptr_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SEAT, "confine_pointer_destroy");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	wl_resource_set_user_data(res, NULL);

	if (surf->confined != res)
		return;

	surf->confined = NULL;
	surf->locked = false;
	wl_resource_destroy(res);
}

void confptr_region(
	struct wl_client* cl, struct wl_resource* res, struct wl_resource* reg)
{
	trace(TRACE_SEAT, "confine_region");
	struct comp_surf* surf = wl_resource_get_user_data(res);

	if (surf->confined != res)
		return;

	surf->locked = false;
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
