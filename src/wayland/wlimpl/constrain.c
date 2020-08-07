/*
 * CONSTRAINTS setup the factory that produces a lock object and/or a confinement
 */
void consptr_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SEAT, "constrain_destroy");

	struct comp_surf* surf = wl_resource_get_user_data(res);
	wl_resource_set_user_data(res, NULL);

	if (!surf || surf->confined != res)
		return;

	surf->confined = NULL;
	surf->locked = false;
	wl_resource_destroy(res);
}

void update_confinement(struct comp_surf* surf)
{
/* send as viewport:
 *
 * x1,y1 -> x, y then (x2-x1) to w, and (y2-y1) to h -
 * visibility status does not really apply as the client will just
 * empty out the cursor image anyhow
 */
	size_t x1 = 0, y1 = 0, x2 = 0, y2 = 0;

/* just lock to center */
	if (surf->confined){
		if (surf->locked){
			x1 = surf->acon.w >> 1;
			y2 = surf->acon.h >> 1;
			x2 = 1;
			y2 = 1;
		}
/* does not really respect the region currently, we need to calculate the intersect.
 * between surface input region and confinement region (and somehow deal when those
 * fail) */
		else {
			x2 = surf->acon.w;
			y2 = surf->acon.h;
		}
	}

/* so confinement can be set on a bunch of surfaces, and be applied for each
 * when we enter confinement - since we have one shared cursor between all
 * surfaces the confinement event needs to be synched when the cursor is
 * entered there */
	struct arcan_event new_conf = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(VIEWPORT),
		.ext.viewport.x = x1,
		.ext.viewport.y = y1,
		.ext.viewport.w = x2 - x1,
		.ext.viewport.h = y2 - y1
	};

	if (memcmp(&surf->client->confine_event.ext.viewport,
		&new_conf.ext.viewport, sizeof(new_conf.ext.viewport)) == 0)
		return;

	surf->client->confine_event = new_conf;
	arcan_shmif_enqueue(&surf->client->acon, &new_conf);

/* but if we already are on the confined- to surface, we should send that
 * immediately - otherwise recent versions of xwayland etc. will bug out */
}

void consptr_lock(struct wl_client* cl, struct wl_resource* res,
	uint32_t id, struct wl_resource* surface, struct wl_resource* pointer,
	struct wl_resource* region, uint32_t lifetime)
{
	trace(TRACE_SEAT, "constrain_lock(region)");
	struct comp_surf* surf = wl_resource_get_user_data(surface);

	if (surf->confined){
		wl_resource_post_error(res,
			ZWP_POINTER_CONSTRAINTS_V1_ERROR_ALREADY_CONSTRAINED, "constrain conflict");
		return;
	}

	struct wl_resource* lock = wl_resource_create(
			cl, &zwp_locked_pointer_v1_interface, wl_resource_get_version(res), id);

	if (!lock){
		wl_client_post_no_memory(cl);
		return;
	}

	surf->locked = true;
	surf->confined = lock;
	wl_resource_set_implementation(lock, &lockptr_if, surf, NULL);

	if (surf->client->last_cursor == surf->res)
		update_confinement(surf);

	zwp_locked_pointer_v1_send_locked(lock);
}

void consptr_confine(struct wl_client* cl, struct wl_resource* res,
	uint32_t id, struct wl_resource* surface, struct wl_resource* pointer,
	struct wl_resource* region, uint32_t lifetime)
{
	trace(TRACE_SEAT, "constrain_confine(region)");

	struct comp_surf* surf = wl_resource_get_user_data(surface);
	if (surf->confined){
		wl_resource_post_error(res,
			ZWP_POINTER_CONSTRAINTS_V1_ERROR_ALREADY_CONSTRAINED, "constrain conflict");
		return;
	}

	struct wl_resource* lock = wl_resource_create(cl,
			&zwp_confined_pointer_v1_interface, wl_resource_get_version(res), id);

	if (!lock){
		wl_client_post_no_memory(cl);
		return;
	}

	surf->confined = lock;
	surf->locked = false;

	wl_resource_set_implementation(lock, &confptr_if, surf, NULL);
	zwp_confined_pointer_v1_send_confined(lock);

	if (surf->client->last_cursor == surf->res)
		update_confinement(surf);
}
