static void subcomp_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "subcomp:destroy");
}

/*
 * pretty much just the same as comp_surf
 */
static void subcomp_subsurf(struct wl_client* client, struct wl_resource* res,
	uint32_t id, struct wl_resource* surf, struct wl_resource* parent)
{
	trace(TRACE_ALLOC, "id: %"PRId32", parent: %"PRIxPTR, id, (uintptr_t)parent);
	struct bridge_client* cl = find_client(client);

	if (!cl){
		wl_resource_post_error(res, WL_SHM_ERROR_INVALID_FD, "out of memory\n");
		return;
	}

	struct comp_surf* new_surf = malloc(sizeof(struct comp_surf));
	if (!new_surf){
		wl_resource_post_no_memory(res);
		free(new_surf);
	}
	*new_surf = (struct comp_surf){
		.client = cl
	};

	new_surf->res = wl_resource_create(client,
		&wl_subsurface_interface, wl_resource_get_version(res), id);

	if (!new_surf->res){
		wl_resource_post_no_memory(res);
		free(new_surf);
	}

	wl_resource_set_implementation(new_surf->res, &subsurf_if, new_surf, NULL);
}
