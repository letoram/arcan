static void xdgdecor_tl_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SURF, "decor_toplevel_destroy");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (surf){
		surf->decor_mgmt = NULL;
	}

	wl_resource_destroy(res);
}

static void xdgdecor_tl_mode(struct wl_client* cl,
	struct wl_resource* res, enum zxdg_toplevel_decoration_v1_mode mode)
{
	trace(TRACE_SURF, "decor_toplevel_mode");
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (!surf)
		return;

	struct arcan_shmif_cont* acon = &surf->acon;
	surf->pending_decoration = mode;

	if (mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE){
		trace(TRACE_SURF, "xdg_toplevel:send_mode=csd");
		arcan_shmif_enqueue(acon,
			&(struct arcan_event){
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(MESSAGE),
			.ext.message.data = "decor:csd"
			}
		);
	}
	else {
		trace(TRACE_SURF, "xdg_toplevel:send_mode=ssd");
		arcan_shmif_enqueue(acon,
			&(struct arcan_event){
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(MESSAGE),
			.ext.message.data = "decor:ssd"
			}
		);
	}
}

static void xdgdecor_tl_unset(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SURF, "decor_toplevel_unset");
/* client has no preference? */
}

static const struct zxdg_toplevel_decoration_v1_interface tldecor_impl = {
	.destroy = xdgdecor_tl_destroy,
	.set_mode = xdgdecor_tl_mode,
	.unset_mode = xdgdecor_tl_unset
};

static void xdgdecor_destroy(struct wl_client* cl, struct wl_resource* res)
{
	wl_resource_destroy(res);
}

static void xdgdecor_get(struct wl_client* cl,
	struct wl_resource* res, uint32_t id, struct wl_resource* toplevel)
{
	struct bridge_client* bcl = wl_resource_get_user_data(res);
	struct comp_surf* surf = wl_resource_get_user_data(toplevel);

	if (!surf){
/* destroyed before
 * ZXDG_TOPLEVEL_DECORATION_V1_ERROR_OPERHANED */
	}

	if (surf->decor_mgmt){
/* xdg_toplevel already has a decoration object
 * ZXDG_TOPLEVEL_DECORATION_v1_ERROR_ALREADY_CONSTRUCTED */
	}

	if (surf->buf){
/* xdg_toplevel has a buffer attached before configure -
 * ZXDG_TOPLEVEL_DECORATION_V1_ERROR_UNCONFIGURED_BUFFER */
	}

/* just build the decor- tool and should be set, the rest is in surface-configure
 * requests and just tracking the desired mode */
	struct wl_resource* decor =
		wl_resource_create(cl,
			&zxdg_toplevel_decoration_v1_interface,
			wl_resource_get_version(res), id
		);

	if (!decor){
		wl_client_post_no_memory(cl);
	}

	wl_resource_set_implementation(decor, &tldecor_impl, surf, NULL);
}
