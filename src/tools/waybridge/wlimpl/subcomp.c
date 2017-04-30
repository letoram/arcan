static void subcomp_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace("subcomp_destroy");
}

static void subcomp_subsurf(struct wl_client* cl, struct wl_resource* res,
	uint32_t id, struct wl_resource* surf, struct wl_resource* parent)
{
	trace("subcomp_subsurf");
/* => VIEWPORT hint */
}
