static void xdgoutput_mgmt_destroy(struct wl_client* cl, struct wl_resource* res)
{
	wl_resource_destroy(res);
}

static void xdgoutput_destroy(struct wl_client* cl, struct wl_resource* res)
{
	struct bridge_client* bcl = find_client(cl);
	if (!cl)
		return;

	if (bcl->output_state.have_xdg == res)
		bcl->output_state.have_xdg = NULL;

	wl_resource_destroy(res);
}

static const struct zxdg_output_v1_interface output_xdg_if = {
	.destroy = xdgoutput_destroy,
};

static void xdgoutput_get(struct wl_client* cl,
	struct wl_resource* res, uint32_t id, struct wl_resource* output)
{
	struct bridge_client* bcl = find_client(cl);
	if (!cl)
		return;

/* always just send one faked output, to get more descriptive information we
 * need to enable color management on the segment and start working with EDID
 * etc. so just save that for when wl gets there which will be fun on its own
 * because HDR and sizes and the awful packing format / queue mgmt */
	struct wl_resource* outres = wl_resource_create(cl,
		&zxdg_output_v1_interface, wl_resource_get_version(res), id);

	if (!outres){
		wl_client_post_no_memory(cl);
		return;
	}

	wl_resource_set_implementation(outres, &output_xdg_if, NULL, NULL);

/* of course the client can request infinitely many of these, and poor clients
 * will scream if we OOM on multiples we'll just not give a duck and only track
 * the one */
	if (!bcl->output_state.have_xdg){
		bcl->output_state.have_xdg = outres;
	}

	if (wl_resource_get_version(outres) > ZXDG_OUTPUT_V1_NAME_SINCE_VERSION){
		zxdg_output_v1_send_name(outres, "arcan-wayland-out-0");
	}

	zxdg_output_v1_send_logical_position(outres, 0, 0);
	zxdg_output_v1_send_logical_size(outres,
		wl.init.display_width_px, wl.init.display_height_px);

	if (wl_resource_get_version(outres) < 3){
		zxdg_output_v1_send_done(outres);
	}
}
