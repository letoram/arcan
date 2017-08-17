/*
 * NOTES:
 *  Missing/investigate -
 *   a. Should pointer event coordinates be clamped against surface?
 *   b. We need to track surface rotate state and transform coordinates
 *      accordingly, as there's no 'rotate state' in arcan
 *   c. Also have grabstate to consider (can only become a MESSAGE and
 *      wl-specific code in the lua layer)
 *   d. scroll- wheel are in some float- version, so we need to deal
 *      with subid 3,4 for analog events and subid 3 for digital
 *      events (there's also something with AXIS_SOURCE, ...)
 *   e. it seems like we're supposed to keep a list of all pointer
 *      resources and iterate them.
 *
 *  Touch - not used at all right now
 *
 *  Keyboard -
 *   a. we need to feed the 'per seat' keymap with inputs and modifiers
 *      in order to extract and send correct modifiers (seriously...)
 */
static void update_mxy(struct comp_surf* cl, unsigned long long pts)
{
	trace(TRACE_ANALOG, "mouse@%d,%d", cl->acc_x, cl->acc_y);
	if (cl->pointer_pending != 2 || cl->client->last_cursor != cl->res){
		trace(TRACE_ANALOG, "mouse(send_enter)");
		if (cl->client->last_cursor)
			wl_pointer_send_leave(cl->client->pointer, STEP_SERIAL(), cl->res);
		cl->client->last_cursor = cl->res;
		cl->pointer_pending = 2;
		wl_pointer_send_enter(cl->client->pointer,
			STEP_SERIAL(), cl->res,
			wl_fixed_from_int(cl->acc_x),
			wl_fixed_from_int(cl->acc_y)
		);
	}
	else
		wl_pointer_send_motion(cl->client->pointer, pts,
			wl_fixed_from_int(cl->acc_x), wl_fixed_from_int(cl->acc_y));

	if (wl_resource_get_version(cl->client->pointer) >=
		WL_POINTER_FRAME_SINCE_VERSION){
		wl_pointer_send_frame(cl->client->pointer);
	}
}

static void update_mbtn(struct comp_surf* cl,
	unsigned long long pts, int ind, bool active)
{
	trace(TRACE_DIGITAL,
		"mouse-btn(pend: %d, ind: %d:%d, @%d,%d)",
			cl->pointer_pending, ind,(int) active, cl->acc_x, cl->acc_y);

/* 0x110 == BTN_LEFT in evdev parlerance */
	wl_pointer_send_button(cl->client->pointer, STEP_SERIAL(),
		pts, 0x10f + ind, active ?
		WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED
	);
}

static void translate_input(struct comp_surf* cl, arcan_ioevent* ev)
{
	if (ev->devkind == EVENT_IDEVKIND_TOUCHDISP){
		trace(TRACE_ANALOG, "touch");
	}
/* motion would/should always come before digital */
	else if (ev->devkind == EVENT_IDEVKIND_MOUSE && cl->client->pointer){
		if (ev->datatype == EVENT_IDATATYPE_DIGITAL){
			update_mbtn(cl, ev->pts, ev->subid, ev->input.digital.active);
		}
		else if (ev->datatype == EVENT_IDATATYPE_ANALOG){
/* both samples */
			if (ev->subid == 2){
				if (ev->input.analog.gotrel){
					cl->acc_x += ev->input.analog.axisval[0];
					cl->acc_y += ev->input.analog.axisval[2];
				}
				else{
					cl->acc_x = ev->input.analog.axisval[0];
					cl->acc_y = ev->input.analog.axisval[2];
				}
				update_mxy(cl, ev->pts);
			}
/* one sample at a time, we need history - either this will introduce
 * small or variable script defined latencies and require an event lookbehind
 * or double the sample load, go with the latter */
			else {
				if (ev->input.analog.gotrel){
					if (ev->subid == 0)
						cl->acc_x += ev->input.analog.axisval[0];
					else if (ev->subid == 1)
						cl->acc_y += ev->input.analog.axisval[0];
				}
				else {
					if (ev->subid == 0)
						cl->acc_x = ev->input.analog.axisval[0];
					else if (ev->subid == 1)
						cl->acc_y = ev->input.analog.axisval[0];
				}
				update_mxy(cl, ev->pts);
			}
		}
		else
			;

/* wl_mouse_ (send_button, send_axis, send_enter, send_leave) */
	}
	else if (ev->datatype ==
		EVENT_IDATATYPE_TRANSLATED && cl->client && cl->client->keyboard){
		trace(TRACE_DIGITAL,
			"keyboard (%d:%d)", (int)ev->subid,
			(int)ev->input.translated.scancode);
		wl_keyboard_send_key(cl->client->keyboard,
			wl_display_next_serial(wl.disp),
			ev->pts,
			ev->subid,
			ev->input.translated.active /* WL_KEYBOARD_KEY_STATE_PRESSED == 1*/
		);

/* FIXME:decode modifiers field and map to wl_keyboard_send_modifiers */
	}
	else
		;
}

static void try_frame_callback(
	struct comp_surf* surf, struct arcan_shmif_cont* acon)
{
/* non-eligible state */
	if (surf->states.hidden || !surf->frame_callback){
		return;
	}

/* still synching? */
	if (!acon || acon->addr->vready){
		return;
	}

	trace(TRACE_SURF, "reply callback: %"PRIu32, surf->cb_id);
	wl_callback_send_done(surf->frame_callback, surf->cb_id);
	wl_resource_destroy(surf->frame_callback);
	surf->frame_callback = NULL;
}

static void get_keyboard_states(struct wl_array* dst)
{
	wl_array_init(dst);
/* FIXME: track press/release so we can send the right ones */
}

/*
 * update the state table for surf and return if it would result in visible
 * state change that should be propagated
 */
static bool displayhint_handler(struct comp_surf* surf, struct arcan_tgtevent* ev)
{
	struct surf_state states = {
		.drag_resize = !!(ev->ioevs[2].iv & 1),
		.hidden = !!(ev->ioevs[2].iv & 2),
		.unfocused = !!(ev->ioevs[2].iv & 4),
		.maximized = !!(ev->ioevs[2].iv & 8),
		.minimized = !!(ev->ioevs[2].iv & 16)
	};

/* alert the seat */
	if (surf->states.unfocused != states.unfocused){
		if (!states.unfocused){
			if (surf->client->keyboard){
				struct wl_array states;
				get_keyboard_states(&states);
				wl_keyboard_send_enter(
					surf->client->keyboard, STEP_SERIAL(), surf->res, &states);
				wl_array_release(&states);
			}

/* We can't send enter for the pointer before we actually get an event
 * so that we know the local coordinates or at least the relative pos,
 * just track this here and send the enter on the first sample we get.
 * The other option is to add a hack over MESSAGE for wayland clients */
			if (surf->client->pointer && surf->pointer_pending != 2){
      	surf->pointer_pending = 1;
			}
		}
		else {
			if (surf->client->keyboard)
				wl_keyboard_send_leave(surf->client->keyboard,STEP_SERIAL(),surf->res);

/* tristate pointer pending (not -> pending -> ack), only ack that
 * should result in a leave */
			if (surf->client->pointer && surf->pointer_pending == 2)
				wl_pointer_send_leave(surf->client->pointer, STEP_SERIAL(),surf->res);

			surf->pointer_pending = 0;
/* touch can't actually 'enter or leave' */
		}
	}

	bool change = memcmp(&surf->states, &states, sizeof(struct surf_state)) != 0;
	surf->states = states;
	return change;
}

static void flush_surface_events(struct comp_surf* surf)
{
	struct arcan_event ev;
/* rcon is set as redirect-con when there's a shared connection or similar */
	struct arcan_shmif_cont* acon = surf->rcon ? surf->rcon : &surf->acon;

	while (arcan_shmif_poll(acon, &ev) > 0){
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
		case TARGET_COMMAND_OUTPUTHINT:{
/* have we gotten reconfigured to a different display? */
		}
		case TARGET_COMMAND_STEPFRAME:
			try_frame_callback(surf, acon);
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
		if (ev.category != EVENT_TARGET)
			continue;
		switch(ev.tgt.kind){
		case TARGET_COMMAND_EXIT:
			trace(TRACE_ALLOC, "shmif-> kill client");
/*		this just murders us, hmm...
 *		wl_client_destroy(cl->client);
			trace("shmif-> kill client");
 */
		break;
		case TARGET_COMMAND_DISPLAYHINT:
			trace(TRACE_ALLOC, "shmif-> target update visibility or size");
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
		break;
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
