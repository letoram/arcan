void shell_getsurf(struct wl_client* client,
	struct wl_resource* res, uint32_t id, struct wl_resource* surf_res)
{
	trace("get shell surface");
	struct bridge_surf* surf = malloc(sizeof(struct bridge_surf));
	if (!surf){
		wl_resource_post_no_memory(res);
		return;
	}
	*surf = (struct bridge_surf){};

	surf->res = wl_resource_create(client,
		&wl_shell_surface_interface, wl_resource_get_version(res), id);
	if (!surf->res){
		free(surf);
		wl_resource_post_no_memory(res);
		return;
	}

/* FIXME: it's likely here we have enough information to reliably
 * wait for a segment or subsegment to represent the window, but with
 * the API at hand, it seems impossible to do without blocking everything
 * (especially with EGL surfaces ...)
 *
 * What we want to do is spin a thread per client and have the usual
 * defer/buffer while wating for asynch subseg reply BUT then we fall
 * into to the EGL Context trap.
 */

	wl_resource_set_implementation(surf->res, &ssurf_if, surf, &ssurf_free);
//	surf->on_destroy.notify = &ssurf_destroy;
//	wl_resource_add_destroy_listener(surf->res, &surf->on_destroy);
}
