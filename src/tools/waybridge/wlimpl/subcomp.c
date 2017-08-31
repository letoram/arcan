static void subcomp_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "subcomp:destroy");
}

static bool subcomp_defer_handler(
	struct surface_request* req, struct arcan_shmif_cont* con)
{
	if (!con){
		trace(TRACE_SHELL, "");
		wl_resource_post_no_memory(req->target);
		free(req->source);
		return false;
	}

	struct comp_surf* source = req->source;
	source->acon = *con;
	source->cookie = 0xfeedface;
	source->res = wl_resource_create(req->client->client,
		&wl_subsurface_interface, wl_resource_get_version(req->target), req->id);

	if (!source->res){
		trace(TRACE_SHELL, "no res in req");
		wl_resource_post_no_memory(req->target);
		free(req->source);
		return false;
	}

	wl_resource_set_implementation(source->res, &subsurf_if, source, NULL);
	return true;
}

/*
 * pretty much just the same as comp_surf, but we immediately allocate a
 * subsegment as this will be tied to the parent. There's also the 'synched'
 * and 'desynched' crap that means we need to defer commit until such a time
 * that the parent in the chain is also committed.
 */
static void subcomp_subsurf(struct wl_client* client, struct wl_resource* res,
	uint32_t id, struct wl_resource* surf, struct wl_resource* parent)
{
	trace(TRACE_ALLOC, "id: %"PRId32", parent: %"PRIxPTR, id, (uintptr_t)parent);
	struct bridge_client* cl = find_client(client);

	if (!cl){
		wl_resource_post_no_memory(res);
		return;
	}

	struct comp_surf* parent_surf = wl_resource_get_user_data(parent);
	if (!parent_surf){
		wl_resource_post_no_memory(res);
		return;
	}

	struct comp_surf* new_surf = malloc(sizeof(struct comp_surf));
	if (!new_surf){
		wl_resource_post_no_memory(res);
		free(new_surf);
	}

	new_surf->sub_parent_res = parent;
	new_surf->surf_res = surf;
	request_surface(parent_surf->client, &(struct surface_request){
		.segid = SEGID_APPLICATION,
		.target = res,
		.id = id,
		.trace = "subsurface",
		.dispatch = subcomp_defer_handler,
		.client = parent_surf->client,
		.source = new_surf
	}, 's');
}
