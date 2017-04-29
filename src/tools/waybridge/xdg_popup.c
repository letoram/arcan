/**
 * tried to grab after being mapped
   ZXDG_POPUP_V6_ERROR_INVALID_GRAB = 0,
 */

/*
 * zxdg_toplevel_v6_send_close(struct wl_resource *resource_)
 * Sends an close event to the client owning the resource.
 */

/*
 * zxdg_popup_v6_send_popup_done(struct wl_resource *resource_)
 * Sends an popup_done event to the client owning the resource.
static inline void
zxdg_popup_v6_send_popup_done(struct wl_resource *resource_)
 */

void xdgpop_grab(struct wl_client *cl, struct wl_resource *res,
	struct wl_resource* seat, uint32_t serial)
{
	trace("xdgpop_grab");
}
