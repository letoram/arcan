/**
 * tried to grab after being mapped
   ZXDG_POPUP_V6_ERROR_INVALID_GRAB = 0,
 */

static bool xdgpopup_shmifev_handler(
	struct comp_surf* surf, struct arcan_event* ev)
{
	if (!surf->shell_res)
		return true;

	if (ev->category == EVENT_TARGET)
		switch (ev->tgt.kind){

/* we need a MESSAGE for conveying the actual popup placement */

		case TARGET_COMMAND_DISPLAYHINT:{
		/* update state tracking first */
			bool changed = displayhint_handler(surf, &ev->tgt);

/* and then, if something has changed, send the configure event */
			int w = ev->tgt.ioevs[0].iv ? ev->tgt.ioevs[0].iv : 0;
			int h = ev->tgt.ioevs[1].iv ? ev->tgt.ioevs[1].iv : 0;
			if ((w && h && (w != surf->acon.w || h != surf->acon.h))){
				zxdg_popup_v6_send_configure(surf->shell_res, 0, 0, w, h);
				changed = true;
			}

			if (changed)
				try_frame_callback(surf);
		}
		return true;
		break;
		case TARGET_COMMAND_EXIT:
			zxdg_popup_v6_send_popup_done(surf->shell_res);
			return true;
		break;
		default:
		break;
		}

	return false;
}

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

static void xdgpop_grab(struct wl_client *cl,
	struct wl_resource *res, struct wl_resource* seat, uint32_t serial)
{
	trace(TRACE_SHELL, "xdgpop_grab");
}

static void xdgpop_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "xdgpop_destroy");
}
