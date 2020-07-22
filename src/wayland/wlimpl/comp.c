static void comp_surf_delete(struct wl_resource* res)
{
	trace(TRACE_ALLOC,
		"destroy:compositor surface(%"PRIxPTR")", (uintptr_t)res);
/*
 * note that this already happens in surface destroy
 * struct comp_surf* surf = wl_resource_get_user_data(res);
	if (!surf)
		return;

	destroy_comp_surf(surf);
 */
}

static void comp_surf_create(struct wl_client *client,
	struct wl_resource *res, uint32_t id)
{
	trace(TRACE_ALLOC, "create:compositor surface(%"PRIu32")", id);

/* If the client doesn't already exist, now is the time we make the first
 * connection. Then we just accept that the surface is created, and defer
 * any real management until the surface is promoted to a role we can fwd */
	struct bridge_client* cl = find_client(client);
	if (!cl){
		wl_resource_post_error(res, WL_SHM_ERROR_INVALID_FD, "out of memory\n");
		return;
	}

	if (cl->forked)
		return;

/* the container for the useless- surface, we'll just hold it until
 * an actual shell- etc. surface is created */
	struct comp_surf* new_surf = malloc(sizeof(struct comp_surf));
	if (!new_surf){
		wl_resource_post_no_memory(res);
		free(new_surf);
	}
	*new_surf = (struct comp_surf){
		.client = cl,
		.tracetag = "compositor",
		.shm_gl_fail = wl.default_accel_surface,
		.scale = cl->scale
	};
	new_surf->viewport = (struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(VIEWPORT)
	};

	new_surf->res = wl_resource_create(client,
		&wl_surface_interface, wl_resource_get_version(res), id);

/* prepare state trackers for both absolute and relative mouse input */
	arcan_shmif_mousestate_setup(NULL, false, new_surf->mstate_abs);
	arcan_shmif_mousestate_setup(NULL, true, new_surf->mstate_rel);

	if (!new_surf->res){
		wl_resource_post_no_memory(res);
		free(new_surf);
	}

	wl_resource_set_implementation(
		new_surf->res, &surf_if, new_surf, comp_surf_delete);

	if (cl->output)
		wl_surface_send_enter(new_surf->res, cl->output);
}

static void comp_create_reg(struct wl_client *client,
	struct wl_resource *resource, uint32_t id)
{
	trace(TRACE_REGION, "create:region");
	struct wl_resource* region = wl_resource_create(client,
		&wl_region_interface, wl_resource_get_version(resource), id);

	if (!region){
		wl_resource_post_no_memory(resource);
	}

	struct surface_region* reg = malloc(sizeof(struct surface_region));
	*reg = (struct surface_region){0};

	if (!region){
		wl_resource_post_no_memory(resource);
		wl_resource_destroy(region);
		return;
	}

	wl_resource_set_implementation(region, &region_if, reg, NULL);
}
