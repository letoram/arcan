static void kwindecor_release(
	struct wl_client* client, struct wl_resource* res)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (surf){
		surf->decor_mgmt = NULL;
	}

	wl_resource_destroy(res);
}

static void mode_to_acon(struct arcan_shmif_cont* acon, uint32_t mode)
{
	switch(mode){
	case ORG_KDE_KWIN_SERVER_DECORATION_MANAGER_MODE_NONE:
	case ORG_KDE_KWIN_SERVER_DECORATION_MANAGER_MODE_SERVER:
		trace(TRACE_SURF, "kwin_decor:send_mode=ssd");
		arcan_shmif_enqueue(acon,
			&(struct arcan_event){
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(MESSAGE),
			.ext.message.data = "decor:ssd"
			}
		);
		break;
	case ORG_KDE_KWIN_SERVER_DECORATION_MANAGER_MODE_CLIENT:
		trace(TRACE_SURF, "kwin_decor:send_mode=csd");
		arcan_shmif_enqueue(acon,
			&(struct arcan_event){
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(MESSAGE),
			.ext.message.data = "decor:csd"
			}
		);
	break;
	}
}

static void kwindecor_request(
	struct wl_client* client, struct wl_resource* res, uint32_t mode)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (!surf || !surf->decor_mgmt)
		return;

/* accept whatever the client accepted */
	org_kde_kwin_server_decoration_send_mode(res, mode);
	mode_to_acon(&surf->acon, mode);
}

static struct org_kde_kwin_server_decoration_interface kwin_decor = {
	.release = kwindecor_release,
	.request_mode = kwindecor_request
};

static void kwindecor_create(struct wl_client* cl,
	struct wl_resource* res, uint32_t id, struct wl_resource* surf)
{
	struct comp_surf* cs = wl_resource_get_user_data(surf);
	struct wl_resource* decor = wl_resource_create(cl,
		&org_kde_kwin_server_decoration_interface, wl_resource_get_version(res), id);

	if (!decor){
		wl_client_post_no_memory(cl);
		return;
	}

	cs->decor_mgmt = decor;
	wl_resource_set_implementation(decor, &kwin_decor, cs, NULL);
	mode_to_acon(&cs->acon, ORG_KDE_KWIN_SERVER_DECORATION_MODE_SERVER);
	trace(TRACE_SURF, "kwin_decor:create:default=ssd");
}
