/**
 * tried to grab after being mapped
   ZXDG_POPUP_V6_ERROR_INVALID_GRAB = 0,
 */

static bool zxdgpopup_shmifev_handler(
	struct comp_surf* surf, struct arcan_event* ev)
{
	if (!surf->shell_res)
		return true;

	if (ev->category == EVENT_TARGET)
		switch (ev->tgt.kind){
		case TARGET_COMMAND_DISPLAYHINT:{
		/* update state tracking first */
			bool changed = displayhint_handler(surf, &ev->tgt);

/* and then, if something has changed, send the configure event */
			int w = ev->tgt.ioevs[0].iv ? ev->tgt.ioevs[0].iv : surf->geom_w;
			int h = ev->tgt.ioevs[1].iv ? ev->tgt.ioevs[1].iv : surf->geom_h;
			if ((w && h && (w != surf->geom_w || h != surf->geom_h))){
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

static void zxdgpop_grab(struct wl_client *cl,
	struct wl_resource *res, struct wl_resource* seat, uint32_t serial)
{
	trace(TRACE_SHELL, "xdgpop_grab");
	struct comp_surf* surf = wl_resource_get_user_data(res);

/* forward to WM scripts so the window gets raised */
	if (!surf->acon.addr)
		return;
	surf->viewport.ext.viewport.focus = true;
	arcan_shmif_enqueue(&surf->acon, &surf->viewport);
}

static void zxdgpop_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "xdgpop_destroy");
}
