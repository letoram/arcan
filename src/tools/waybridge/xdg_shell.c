void xdg_getsurf(struct wl_client* client,
	struct wl_resource* res, uint32_t id, struct wl_resource* surf_res)
{
	trace("get xdg-shell surface");
	struct bridge_surf* surf = wl_resource_get_user_data(surf_res);
	struct wl_resource* xdgsurf_res = wl_resource_create(client,
		&zxdg_surface_v6_interface, wl_resource_get_version(res), id);

	if (!xdgsurf_res){
		wl_resource_post_no_memory(res);
		return;
	}

	if (!surf->cl->got_primary){
		trace("xdg_surface assigned as primary");
		surf->type = SURF_SHELL;
		surf->acon = &surf->cl->acon;
		surf->cl->got_primary = 1;
	}
	else{
/* FIXME: we need to do the whole - spin and wait for subseq request */
		wl_resource_post_no_memory(res);
	}

	wl_resource_set_implementation(xdgsurf_res, &xdgsurf_if, surf, NULL);
}

void xdg_createpos(struct wl_client* client, struct wl_resource* res,
	uint32_t id)
{
	trace("xdg_createpos");
}
