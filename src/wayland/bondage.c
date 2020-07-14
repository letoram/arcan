/*
 * we used to do this, now the helper in -server will suffice
static void bind_shm(struct wl_client* client,
	void* data, uint32_t version, uint32_t id)
{
	struct wl_resource* res = wl_resource_create(client,
		&wl_shm_interface, version, id);
	wl_resource_set_implementation(res, &shm_if, NULL, NULL);
	wl_shm_send_format(res, WL_SHM_FORMAT_XRGB8888);
	wl_shm_send_format(res, WL_SHM_FORMAT_ARGB8888);
}
 */

static void bind_comp(struct wl_client *client,
	void *data, uint32_t version, uint32_t id)
{
	trace(TRACE_ALLOC, "wl_bind(compositor %d:%d)", version, id);
	struct wl_resource* res = wl_resource_create(client,
		&wl_compositor_interface, version, id);
	if (!res){
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_implementation(res, &compositor_if, NULL, NULL);
}

static void bind_cons(struct wl_client* client,
	void *data, uint32_t version, uint32_t id)
{
	trace(TRACE_ALLOC, "wl_bind(constraints %d:%d)", version, id);
	struct wl_resource* res = wl_resource_create(client,
		&zwp_pointer_constraints_v1_interface, version, id);
	if (!res){
		wl_client_post_no_memory(client);
		return;
	}

	struct bridge_client* cl = find_client(client);
	if (!cl){
		wl_client_post_no_memory(client);
		return;
	}

	wl_resource_set_implementation(res, &consptr_if, cl, NULL);
}

static void bind_seat(struct wl_client *client,
	void *data, uint32_t version, uint32_t id)
{
	trace(TRACE_ALLOC, "wl_bind(seat %d:%d)", version, id);
	struct wl_resource* res = wl_resource_create(client,
		&wl_seat_interface, version, id);
	if (!res){
		wl_client_post_no_memory(client);
		return;
	}

	struct bridge_client* cl = find_client(client);
	if (!cl){
		wl_client_post_no_memory(client);
		return;
	}

	wl_resource_set_implementation(res, &seat_if, cl, NULL);
	wl_seat_send_capabilities(res, WL_SEAT_CAPABILITY_POINTER |
		WL_SEAT_CAPABILITY_KEYBOARD | WL_SEAT_CAPABILITY_TOUCH);

	if (version > 2)
		wl_seat_send_name(res, "seat0");
}

static void bind_shell(struct wl_client* client,
	void *data, uint32_t version, uint32_t id)
{
	trace(TRACE_ALLOC, "wl_bind(shell %d:%d)", version, id);
	struct wl_resource* res = wl_resource_create(client,
		&wl_shell_interface, version, id);
	if (!res){
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_implementation(res, &shell_if, NULL, NULL);
}

static void bind_zxdg(struct wl_client* client,
	void *data, uint32_t version, uint32_t id)
{
	trace(TRACE_ALLOC, "wl_bind(zxdg %d:%d)", version, id);
	struct wl_resource* res = wl_resource_create(client,
		&zxdg_shell_v6_interface, version, id);
	if (!res){
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_implementation(res, &zxdgshell_if, NULL, NULL);
}

static void bind_xdg(struct wl_client* client,
	void *data, uint32_t version, uint32_t id)
{
	trace(TRACE_ALLOC, "wl_bind(xdg %d:%d)", version, id);
	struct wl_resource* res = wl_resource_create(
		client, &xdg_wm_base_interface, version, id);
	if (!res){
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_implementation(res, &xdgshell_if, NULL, NULL);
}

static void decompose_mod(uint64_t mod, uint32_t* hi, uint32_t* lo)
{
	*hi = mod & 0xffffffff;
	*lo = mod >> 32;
}

static void send_fallback(struct wl_resource* res, bool mods)
{
	static const int formats[] = {
		DRM_FORMAT_ARGB8888,
		DRM_FORMAT_XRGB8888
	};
	if (mods)
		for (size_t i = 0; i < COUNT_OF(formats); i++){
			uint32_t mod_hi, mod_lo;
			decompose_mod(DRM_FORMAT_MOD_INVALID, &mod_hi, &mod_lo);
			zwp_linux_dmabuf_v1_send_modifier(res, formats[i], mod_hi, mod_lo);
		}
	else
		for (size_t i = 0; i < COUNT_OF(formats); i++){
			zwp_linux_dmabuf_v1_send_format(res, formats[i]);
		}
}

static void bind_zwp_dma_buf(struct wl_client* client,
	void *data, uint32_t version, uint32_t id)
{
	trace(TRACE_ALLOC, "wl_bind(zwp-dma-buf %d:%d)", version, id);
	struct wl_resource* res = wl_resource_create(
		client, &zwp_linux_dmabuf_v1_interface, version, id);
	if (!res){
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_implementation(res, &zdmabuf_if, NULL, NULL);

/* the proper route for this is to use an egl display derived from a
 * DEVICE_NODE event, then first query the formats, then for each format, query
 * modifiers and send format+modifier pairs */

/* so simple-dmabuf-drm just removed the handling of this altogether with a
 * nice deprecated, much engineering quality, such versioning - as they
 * apparently can't drop the symbol due to the shit API, and nobody cares
 * enough to renamespace etc. Xwayland, also falls back to wl_drm?! if the
 * invalid modifier thing is provided */
	if (version < ZWP_LINUX_DMABUF_V1_MODIFIER_SINCE_VERSION)
		send_fallback(res, false);

	EGLint num;

	if (!wl.query_formats || !wl.query_formats(wl.display, 0, NULL, &num)){
		send_fallback(res, true);
		return;
	}

	int* formats = malloc(sizeof(int) * num);
	if (!formats){
		send_fallback(res, true);
		return;
	}

	if (!wl.query_formats(wl.display, num, formats, &num)){
		num = 0;
	}

	for (size_t i = 0; i < num; i++){
		uint64_t* mods = NULL;
		int n_mods = 0;

/* no modifiers for format? send invalid */
		if (!wl.query_modifiers(wl.display,
			formats[i], 0, NULL, NULL, &n_mods) || !n_mods){
			uint64_t invalid = DRM_FORMAT_MOD_INVALID;
			uint32_t mod_hi, mod_lo;
			decompose_mod(invalid, &mod_hi, &mod_lo);
			zwp_linux_dmabuf_v1_send_modifier(res, formats[i], mod_hi, mod_lo);
			continue;
		}

		mods = malloc(n_mods * sizeof(uint64_t));
		if (mods &&
			wl.query_modifiers(wl.display, formats[i], n_mods, mods, NULL, &n_mods)){
			for (size_t j = 0; j < n_mods; j++){
				uint32_t mod_hi, mod_lo;
				decompose_mod(mods[j], &mod_hi, &mod_lo);
				zwp_linux_dmabuf_v1_send_modifier(res, formats[i], mod_hi, mod_lo);
			}
		}
		free(mods);
	}

	free(formats);
}

static void bind_subcomp(struct wl_client* client,
	void* data, uint32_t version, uint32_t id)
{
	trace(TRACE_ALLOC, "wl_bind(subcomp %d:%d)", version, id);
	struct wl_resource* res = wl_resource_create(client,
		&wl_subcompositor_interface, version, id);
	if (!res){
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_implementation(res, &subcomp_if, NULL, NULL);
}

static void bind_ddev(struct wl_client* client,
	void* data, uint32_t version, uint32_t id)
{
	trace(TRACE_ALLOC, "bind_ddev");
	struct wl_resource* resource = wl_resource_create(client,
		&wl_data_device_manager_interface, version, id);
	if (!resource){
		wl_client_post_no_memory(client);
		return;
	}
	struct bridge_client* cl = find_client(client);
	if (!cl){
		wl_client_post_no_memory(client);
	}
	wl_resource_set_implementation(resource, &ddevmgr_if, NULL, NULL);
}

static void bind_xdgoutput(
	struct wl_client* client, void* data, uint32_t version, uint32_t id)
{
	trace(TRACE_ALLOC, "bind_xdg_output");
	struct wl_resource* res =
		wl_resource_create(client, &zxdg_output_manager_v1_interface, version, id);
	if (!res){
		wl_client_post_no_memory(client);
		return;
	}
	struct bridge_client* cl = find_client(client);
	if (!cl){
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_implementation(res, &outmgr_if, NULL, NULL);
}

static void bind_xdgdecor(
	struct wl_client* client, void* data, uint32_t version, uint32_t id)
{
	trace(TRACE_ALLOC, "bind_xdg_decor");
	struct wl_resource* res =
		wl_resource_create(client, &zxdg_decoration_manager_v1_interface, version, id);
	if (!res){
		wl_client_post_no_memory(client);
		return;
	}
	struct bridge_client* cl = find_client(client);
	if (!cl){
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_implementation(res, &decormgr_if, cl, NULL);
}

static void bind_relp(struct wl_client* client,
	void* data, uint32_t version, uint32_t id)
{
	trace(TRACE_ALLOC, "bind_relp");
	struct wl_resource* resource = wl_resource_create(client,
		&zwp_relative_pointer_manager_v1_interface, version, id);
	if (!resource){
		wl_client_post_no_memory(client);
		return;
	}
	struct bridge_client* cl = find_client(client);
	if (!cl){
		wl_client_post_no_memory(client);
	}
	wl_resource_set_implementation(resource, &relpmgr_if, cl, NULL);
}

static void bind_output(struct wl_client* client,
	void* data, uint32_t version, uint32_t id)
{
	trace(TRACE_ALLOC, "bind_output (geom: %zu*%zu)",
		wl.init.display_width_px, wl.init.display_height_px);

	struct wl_resource* resource = wl_resource_create(client,
		&wl_output_interface, version, id);
	if (!resource){
		wl_client_post_no_memory(client);
		return;
	}

	struct bridge_client* cl = find_client(client);
	if (!cl){
		wl_client_post_no_memory(client);
	}

	cl->output = resource;
/* convert the initial display info from x, y to mm using ppcm */
	wl_output_send_geometry(resource, 0, 0,
		(float)wl.init.display_width_px / wl.init.density * 10.0,
		(float)wl.init.display_height_px / wl.init.density * 10.0,
		0, /* init.fonts[0] hinting should work */
		"unknown", "unknown",
		0
	);

	wl_output_send_mode(resource, WL_OUTPUT_MODE_CURRENT,
		wl.init.display_width_px, wl.init.display_height_px, wl.init.rate);

	int scale = wl.scale;
	if (!scale){
		scale = roundf(wl.init.density / ARCAN_SHMPAGE_DEFAULT_PPCM);
	}
	cl->scale = scale;

	if (version >= WL_OUTPUT_SCALE_SINCE_VERSION){
		wl_output_send_scale(resource, scale);
	}

	if (version >= 2)
		wl_output_send_done(resource);
}

/* for zxdg output, logical_position and logical_size as well */
