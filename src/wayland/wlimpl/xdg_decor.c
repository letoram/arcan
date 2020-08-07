static void xdgdecor_tl_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SURF, "decor_toplevel_destroy");
	wl_resource_destroy(res);
}

static void xdgdecor_tl_mode(struct wl_client* cl,
	struct wl_resource* res, enum zxdg_toplevel_decoration_v1_mode mode)
{
	trace(TRACE_SURF, "decor_toplevel_mode");

/* mark a configure to send */
}

static void xdgdecor_tl_unset(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SURF, "decor_toplevel_unset");

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
/* destroyed before */
	}

	if (surf->decor_mgmt){
/* xdg_toplevel already has a decoration object */
	}

	if (surf->buf){
/* xdg_toplevel has a buffer attached before configure */
	}

/* just build the decor- tool and should be set, the rest is in surface-configure
 * requests and just tracking the desired mode */
}
