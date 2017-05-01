static void translate_input(struct comp_surf* cl, arcan_ioevent* ev)
{
	if (ev->devkind == EVENT_IDEVKIND_TOUCHDISP){
	}
	else if (ev->devkind == EVENT_IDEVKIND_MOUSE){
/* wl_mouse_ (send_button, send_axis, send_enter, send_leave) */
	}
	else if (ev->datatype == EVENT_IDATATYPE_TRANSLATED){
/* wl_keyboard_send_enter,
 * wl_keyboard_send_leave,
 * wl_keyboard_send_key,
 * wl_keyboard_send_keymap,
 * wl_keyboard_send_modifiers,
 * wl_keyboard_send_repeat_info */
	}
	else
		;
}

static void flush_surface_events(struct comp_surf* surf)
{
	struct arcan_event ev;

	while (arcan_shmif_poll(&surf->acon, &ev) > 0){
		if (surf->dispatch && surf->dispatch(surf, &ev))
			continue;

		if (ev.category == EVENT_IO){
			translate_input(surf, &ev.io);
			continue;
		}
		else if (ev.category != EVENT_TARGET)
			continue;

		switch(ev.tgt.kind){
/* translate to configure events */
		case TARGET_COMMAND_DISPLAYHINT:
		break;

		case TARGET_COMMAND_STEPFRAME:
			if (!surf->hidden && surf->frame_callback){
				wl_callback_send_done(surf->frame_callback, surf->cb_id);
				surf->frame_callback = NULL;
			}
		break;

/* in the 'generic' case, there's litle we can do that match
 * 'EXIT' behavior. It's up to the shell-subprotocols to swallow
 * the event and map to the correct surface teardown. */
		case TARGET_COMMAND_EXIT:
		break;

		default:
		break;
		}
	}
}

static void flush_client_events(
	struct bridge_client* cl, struct arcan_event* evs, size_t nev)
{
/* same dispatch, different path if we're dealing with 'ev' or 'nev' */
	struct arcan_event ev;

	while (arcan_shmif_poll(&cl->acon, &ev) > 0){
		trace("(client-event) %s\n", arcan_shmif_eventstr(&ev, NULL, 0));
		if (ev.category != EVENT_TARGET)
			continue;
		switch(ev.tgt.kind){
		case TARGET_COMMAND_EXIT:
/* this means killing off all resources associated with a client */
			wl_client_destroy(cl->client);
			trace("shmif-> kill client");
		break;
		case TARGET_COMMAND_DISPLAYHINT:
			trace("shmif-> target update visibility or size");
			if (ev.tgt.ioevs[0].iv && ev.tgt.ioevs[1].iv){
			}
/* this one isn't very easy - since only the primary segment (i.e.
 * client here) survives, all the existing subsurfaces need to be
 * re-requested and remapped.
 *
 * reset-state:
 *  for all surfaces from this client:
 *     resubmit-request, fail: simulate _COMMAND_EXIT
 *     accept: update the resource reference
 */
		case TARGET_COMMAND_RESET:
		break;
		case TARGET_COMMAND_REQFAIL:
		break;
		case TARGET_COMMAND_NEWSEGMENT:
		break;

/* if selection status change, send wl_surface_
 * if type: wl_shell, send _send_configure */
		break;
		case TARGET_COMMAND_OUTPUTHINT:
			trace("shmif-> target update configuration");
		break;
		default:
		break;
		}
	}
}

static bool flush_bridge_events(struct arcan_shmif_cont* con)
{
	struct arcan_event ev;
	while (arcan_shmif_poll(con, &ev) > 0){
		if (ev.category == EVENT_TARGET){
		switch (ev.tgt.kind){
		case TARGET_COMMAND_EXIT:
			return false;
		default:
		break;
		}
		}
	}
	return true;
}
