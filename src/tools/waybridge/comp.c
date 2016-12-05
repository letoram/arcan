static void comp_surf_delete(struct wl_resource* res)
{
	trace("destroy compositor surface");
	struct bridge_surf* surf = wl_resource_get_user_data(res);
	if (!surf)
		return;

	surf->cookie = 0xbad1dea;
	if (surf->acon == &surf->cl->acon){
		surf->cl->got_primary = 0;
/* FIXME: viewport hint this one to invisible */
	}
	else
		arcan_shmif_drop(surf->acon);

	free(surf);
}

static void comp_surf_create(struct wl_client *client,
	struct wl_resource *res, uint32_t id)
{
	trace("create compositor surface(%"PRIu32")", id);

/* we need to defer this and make a subsegment connection unless
 * the client has not consumed its primary one */
	struct bridge_surf* new_surf = malloc(sizeof(struct bridge_surf));
	memset(new_surf, '\0', sizeof(struct bridge_surf));
	new_surf->cl = find_client(client);
	if (!new_surf->cl){
		wl_resource_post_error(res, WL_SHM_ERROR_INVALID_FD, "out of memory\n");
		free(new_surf);
		return;
	}
	new_surf->cookie = 0xfeedface;

/*
 * NOTE:
 * if the primary connection doesn't have a surface using it, that one should
 * be assigned to the first created - otherwise, we need to go into the whole
 * segreq-wait thing.
 */
	new_surf->res = wl_resource_create(client, &wl_surface_interface,
		wl_resource_get_version(res), id);

	wl_resource_set_implementation(new_surf->res,
		&surf_if, new_surf, comp_surf_delete);
}

static void comp_create_reg(struct wl_client *client,
	struct wl_resource *resource, uint32_t id)
{
	trace("create region");
	struct wl_resource* region = wl_resource_create(client,
		&wl_region_interface, wl_resource_get_version(resource), id);
	wl_resource_set_implementation(region, &region_if, NULL, NULL);
}
