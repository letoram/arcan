static void shell_getsurf(struct wl_client* client,
	struct wl_resource* res, uint32_t id, struct wl_resource* surf_res)
{
	trace(TRACE_SHELL, "get shell surface");
	struct comp_surf* surf = wl_resource_get_user_data(surf_res);

	struct wl_resource* ssurf = wl_resource_create(client,
		&wl_shell_surface_interface, wl_resource_get_version(surf_res), id);

	if (!ssurf){
		wl_resource_post_no_memory(surf_res);
		return;
	}

	wl_resource_set_implementation(ssurf, &ssurf_if, surf, NULL);
}
