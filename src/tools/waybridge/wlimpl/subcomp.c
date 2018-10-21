static void subcomp_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_ALLOC, "destroy");
}

static bool subcomp_defer_handler(
	struct surface_request* req, struct arcan_shmif_cont* con)
{
	if (!con){
		trace(TRACE_SHELL, "reqfail");
		wl_resource_post_no_memory(req->target);
		return false;
	}

	struct wl_resource* subsurf = wl_resource_create(req->client->client,
		&wl_subsurface_interface, wl_resource_get_version(req->target), req->id);

	if (!subsurf){
		trace(TRACE_SHELL, "reqfail");
		wl_resource_post_no_memory(req->target);
		return false;
	}

	struct comp_surf* surf = wl_resource_get_user_data(req->target);
	wl_resource_set_implementation(subsurf, &subsurf_if, surf, NULL);

	if (!surf){
		trace(TRACE_SHELL, "reqfail");
		wl_resource_post_no_memory(req->target);
		return false;
	}

	surf->acon = *con;
	surf->cookie = 0xfeedface;
	surf->shell_res = subsurf;
	surf->dispatch = subsurf_shmifev_handler;
	surf->sub_parent_res = req->parent;

	snprintf(surf->tracetag, SURF_TAGLEN, "subsurf");

	if (req->parent){
		struct comp_surf* psurf = wl_resource_get_user_data(req->parent);
		if (!psurf->acon.addr){
			trace(TRACE_ALLOC, "bad subsurface, broken parent");
			return false;
		}
		surf->viewport.ext.kind = ARCAN_EVENT(VIEWPORT);
		surf->viewport.ext.viewport.parent = psurf->acon.segment_token;
		arcan_shmif_enqueue(&surf->acon, &surf->viewport);
	}

	trace(TRACE_ALLOC, "subsurface");
	return true;
}

/*
 * allocation is similar to a popup
 */
static void subcomp_subsurf(struct wl_client* client, struct wl_resource* res,
	uint32_t id, struct wl_resource* surf, struct wl_resource* parent)
{
	trace(TRACE_ALLOC, "id: %"PRId32", parent: %"PRIxPTR, id, (uintptr_t)parent);
	struct comp_surf* csurf = wl_resource_get_user_data(surf);
	struct comp_surf* parent_surf = wl_resource_get_user_data(parent);

	request_surface(parent_surf->client, &(struct surface_request){
		.segid = SEGID_MEDIA,
		.target = surf,
		.id = id,
		.trace = "subsurface",
		.dispatch = subcomp_defer_handler,
		.client = parent_surf->client,
		.source = csurf,
		.parent = parent
	}, 's');
}
