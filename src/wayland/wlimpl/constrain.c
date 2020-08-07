/* LOCKING considers a restricted region as well as a warp */
void lockptr_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SEAT, "destroy");
}

void lockptr_region(struct wl_client* cl,
	struct wl_resource* res, struct wl_resource* reg)
{
	trace(TRACE_SEAT, "lock_region");
	struct bridge_client* bridge = find_client(cl);
	if (!bridge)
		return;

/* let the client think that whatever confinement it sets is true */
}

void lockptr_hintat(struct wl_client* cl,
	struct wl_resource* res, wl_fixed_t x, wl_fixed_t y)
{
	trace(TRACE_SEAT, "lock_hint_at");

	struct comp_surf* surf = wl_resource_get_user_data(res);

	if (!surf)
		return;

	struct arcan_event ev = (struct arcan_event){
		.ext.kind = ARCAN_EVENT(MESSAGE)
	};

	snprintf((char*)ev.ext.message.data,
		COUNT_OF(ev.ext.message.data), "warp:x:%zu:y:%zu", (size_t)x, (size_t)y);
	arcan_shmif_enqueue(&surf->acon, &ev);
}

void confptr_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SEAT, "confine_pointer_destroy");
	wl_resource_destroy(res);
}

void confptr_region(struct wl_client* cl,
	struct wl_resource* res, struct wl_resource* reg)
{
	trace(TRACE_SEAT, "confine_region");
	struct bridge_client* bridge = find_client(cl);
	if (!bridge)
		return;

/* let the client think that whatever confinement it sets is true */
}

/*
 * CONSTRAINTS setup the factory that produces a lock object and/or a confinement
 */
void consptr_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SEAT, "constrain_destroy");
	wl_resource_destroy(res);
}

void consptr_lock(struct wl_client* cl, struct wl_resource* res,
	uint32_t id, struct wl_resource* surf, struct wl_resource* pointer,
	struct wl_resource* region, uint32_t lifetime)
{
	trace(TRACE_SEAT, "constrain_lock(region)");
/* extract surface structure */
/* got constraint object already? reject */
/* otherwise, wl_resource_create in to zwp_locked_pointer_v1_interface, lockptr_if */
}

void consptr_confine(struct wl_client* cl, struct wl_resource* res,
	uint32_t id, struct wl_resource* surf, struct wl_resource* pointer,
	struct wl_resource* region, uint32_t lifetime)
{
	trace(TRACE_SEAT, "constrain_confine(region)");
/* extract surface structure */
/* got constraint object already? reject */
/* otherwise, wl_resource_create in to zwp_confined_pointer_v1_interface, confptr_if */
}
