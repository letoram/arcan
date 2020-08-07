static void get_keyboard_states(struct wl_array* dst)
{
	wl_array_init(dst);
/* FIXME: track press/release so we can send the right ones */
}

static void leave_seat(
	struct comp_surf* cl,
	struct seat* seat, long serial)
{
	if (seat->ptr && seat->in_ptr){
		wl_pointer_send_leave(seat->ptr, serial, seat->in_ptr);
		seat->in_ptr = NULL;
	}

	if (seat->kbd && seat->in_kbd){
		wl_keyboard_send_leave(seat->kbd, serial, seat->in_kbd);
		seat->in_kbd = NULL;
	}
}

static void enter_seat(
	struct comp_surf* cl,
	struct seat* seat, long serial)
{
	if (seat->ptr && seat->in_ptr != cl->res){
		if (seat->in_ptr){
			trace(TRACE_SEAT, "leave-ptr@%ld:seat(%"PRIxPTR")-surface:%"
				PRIxPTR, serial, (uintptr_t)seat, (uintptr_t)seat->in_ptr, cl->res);
			wl_pointer_send_leave(seat->ptr, serial, seat->in_ptr);
		}

		trace(TRACE_SEAT, "enter-ptr@%ld:seat(%"PRIxPTR")-surface:%"
			PRIxPTR, serial, (uintptr_t)seat, (uintptr_t)cl->res, cl->res);

		wl_pointer_send_enter(
			seat->ptr,
			serial, cl->res,
			wl_fixed_from_int(cl->acc_x * (1.0 / cl->scale)),
			wl_fixed_from_int(cl->acc_y * (1.0 / cl->scale))
		);

		seat->in_ptr = cl->res;
	}

	if (seat->kbd && seat->in_kbd != cl->res){
		if (seat->in_kbd){
			wl_keyboard_send_leave(seat->kbd, serial, seat->in_kbd);
		}

		struct wl_array states;
		get_keyboard_states(&states);
		wl_keyboard_send_enter(seat->kbd, serial, cl->res, &states);
		wl_array_release(&states);

		seat->in_kbd = cl->res;
	}
}

static void each_seat(
	struct comp_surf* cl,
	void (*hnd)(struct comp_surf*, struct seat*, long))
{
	long serial = STEP_SERIAL();

	for (size_t i = 0; i < COUNT_OF(cl->client->seats); i++){
		if (!cl->client->seats[i].used)
			continue;

		hnd(cl, &cl->client->seats[i], serial);
	}
}

static void enter_all(struct comp_surf* cl)
{
	each_seat(cl, enter_seat);
	update_confinement(cl);
}

static void leave_all(struct comp_surf* cl)
{
	each_seat(cl, leave_seat);
	update_confinement(cl);
}

static void update_mxy(struct comp_surf* cl, unsigned long long pts)
{
	if (!pts)
		pts = arcan_timemillis();

/* for confinement we should really walk the region as well to determine
 * if the coordinates are within the confinement or not and filter those
 * out that fall wrong and re-signal warp + confinement */

	trace(TRACE_ANALOG, "mouse@%d,%d", cl->acc_x, cl->acc_y);
	enter_all(cl);

	for (size_t i = 0; i < COUNT_OF(cl->client->seats); i++){
		struct seat* cs = &cl->client->seats[i];
		if (!cs->used || !cs->ptr)
			continue;

		wl_pointer_send_motion(cs->ptr,
			pts,
			wl_fixed_from_int((1.0 / cl->scale) * cl->acc_x),
			wl_fixed_from_int((1.0 / cl->scale) * cl->acc_y)
	);

		if (wl_resource_get_version(cs->ptr) >= WL_POINTER_FRAME_SINCE_VERSION){
			wl_pointer_send_frame(cs->ptr);
		}
	}
}

static void scroll_axis_digital(
	struct bridge_client* bcl, bool active, int ind, unsigned long long pts)
{
	int dir = ind == 4 ? -1 : 1;
	ind = WL_POINTER_AXIS_VERTICAL_SCROLL;

	for (size_t i = 0; i < COUNT_OF(bcl->seats); i++){
		struct seat* seat = &bcl->seats[i];
		if (!seat->used || !seat->ptr)
			continue;

		if (!active){
/*			if (wl_resource_get_version(seat->ptr) >=
				WL_POINTER_AXIS_STOP_SINCE_VERSION){
				wl_pointer_send_axis_stop(seat->ptr, pts, ind);
			}
*/
			continue;
		}

		wl_pointer_send_axis_source(seat->ptr, WL_POINTER_AXIS_SOURCE_WHEEL);

		uint32_t ver = wl_resource_get_version(seat->ptr);
		if (ver >= WL_POINTER_AXIS_DISCRETE_SINCE_VERSION){
			wl_pointer_send_axis_discrete(seat->ptr, ind, dir);
		}

		wl_pointer_send_axis(seat->ptr, pts, ind, wl_fixed_from_int(dir * 10));

		if (ver >= WL_POINTER_FRAME_SINCE_VERSION){
			wl_pointer_send_frame(seat->ptr);
		}
	}
}

static void mouse_button_send(struct bridge_client* bcl,
	unsigned long long pts, int wl_ind, int btn_state)
{
	long serial = STEP_SERIAL();

	for (size_t i = 0; i < COUNT_OF(bcl->seats); i++){
		struct seat* seat = &bcl->seats[i];
		if (!seat->used || !seat->ptr)
			continue;

		wl_pointer_send_button(seat->ptr, serial, pts, wl_ind, btn_state);
	}
}

static void update_mbtn(struct comp_surf* cl,
	unsigned long long pts, int ind, bool active)
{
	trace(TRACE_DIGITAL,
		"mouse-btn(ind: %d:%d, @%d,%d)", ind,(int) active, cl->acc_x, cl->acc_y);

	if (!pts)
		pts = arcan_timemillis();

	enter_all(cl);

	if (ind == 4 || ind == 5){
		scroll_axis_digital(cl->client, active, ind, pts);
	}

/* 0x110 == BTN_LEFT in evdev parlerance, ignore 0 index as it is used
 * to convey gestures and that's a separate unstable protocol */
	else if (ind > 0){
		mouse_button_send(cl->client, pts, 0x10f + ind, active ?
			WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
	}
}

static void forward_key(struct bridge_client* cl, uint32_t key, bool pressed)
{
	int serial = STEP_SERIAL();

	for (size_t i = 0; i < COUNT_OF(cl->seats); i++){
		struct seat* seat = &cl->seats[i];

		if (!seat->used || !seat->kbd)
			continue;

		struct xkb_state* state = seat->kbd_state.state;
		xkb_state_update_key(state, key + 8, pressed ? XKB_KEY_DOWN : XKB_KEY_UP);
		uint32_t depressed = xkb_state_serialize_mods(state,XKB_STATE_MODS_DEPRESSED);
		uint32_t latched = xkb_state_serialize_mods(state, XKB_STATE_MODS_LATCHED);
		uint32_t locked = xkb_state_serialize_mods(state, XKB_STATE_MODS_LOCKED);
		uint32_t group = xkb_state_serialize_mods(state, XKB_STATE_MODS_EFFECTIVE);

		wl_keyboard_send_modifiers(seat->kbd, serial, depressed, latched, locked, group);
		wl_keyboard_send_key(seat->kbd, serial, arcan_timemillis(), key, pressed);
	}
}

static void release_all_keys(struct bridge_client* cl)
{
	for (size_t i = 0 ; i < COUNT_OF(cl->keys); i++){
		if (cl->keys[i]){
			cl->keys[i] = 0;
			forward_key(cl, i, false);
		}
	}
}

static void update_kbd(struct comp_surf* cl, arcan_ioevent* ev)
{
	trace(TRACE_DIGITAL,
		"button (%d:%d)", (int)ev->subid, (int)ev->input.translated.scancode);

/* keyboard not acknowledged on this surface?
 * send focus and possibly leave on previous one */
	enter_all(cl);

/* This is, politely put, batshit insane - every time the modifier mask has
 * changed from the last time we were here, we either have to allocate and
 * rebuild a new xkb_state as the structure is opaque, and they provide no
 * reset function - then rebuild it by converting our modifier mask back to
 * linux keycodes and reinsert them into the state machine but that may not
 * work for each little overcomplicated keymap around. The other option,
 * is that each wayland seat gets its own little state-machine that breaks
 * every input feature we have server-side.
 * The other panic option is to fake/guess/estimate the different modifiers
 * and translate that way.
 */
	uint8_t subid = ev->subid;
	bool active = ev->input.translated.active;

	if (subid < COUNT_OF(cl->client->keys)){
/* no-op, bad input from server */
		if (cl->client->keys[subid] == active)
			return;

		cl->client->keys[subid] = active;
	}

	forward_key(cl->client, subid, active);
}

static void consume_relative(
	struct bridge_client* cl, uint64_t ts, int x, int y)
{
	uint32_t lo = (ts * 1000) >> 32;
	uint32_t hi = ts * 1000;

	for (size_t i = 0; i < COUNT_OF(cl->seats); i++){
		if (!cl->seats[i].used || !cl->seats[i].rel_ptr)
			continue;

		zwp_relative_pointer_v1_send_relative_motion(
			cl->seats[i].rel_ptr, hi, lo,
			wl_fixed_from_int(x), wl_fixed_from_int(y),
			wl_fixed_from_int(x), wl_fixed_from_int(y)
		);
	}
}

static void translate_input(struct comp_surf* cl, arcan_ioevent* ev)
{
	if (ev->devkind == EVENT_IDEVKIND_TOUCHDISP){
		trace(TRACE_ANALOG, "touch");
	}
/* motion would/should always come before digital */
	else if (ev->devkind == EVENT_IDEVKIND_MOUSE){
		if (ev->datatype == EVENT_IDATATYPE_DIGITAL){
			update_mbtn(cl, ev->pts, ev->subid, ev->input.digital.active);
		}
		else if (ev->datatype == EVENT_IDATATYPE_ANALOG){
/* both samples */
			if (ev->subid == 2){
				if (ev->input.analog.gotrel){
					cl->acc_x += ev->input.analog.axisval[0];
					cl->acc_y += ev->input.analog.axisval[2];

/* forward to seats with a relative pointer */
					consume_relative(cl->client, ev->pts,
						ev->input.analog.axisval[0], ev->input.analog.axisval[1]);
				}
				else{
					cl->acc_x = ev->input.analog.axisval[0];
					cl->acc_y = ev->input.analog.axisval[2];
				}

				update_mxy(cl, ev->pts);
			}
/* one sample at a time, we need history - either this will introduce small or
 * variable script defined latencies and require an event lookbehind or double
 * the sample load, go with the latter */
			else {
				if (ev->input.analog.gotrel){
					if (ev->subid == 0)
						cl->acc_x += ev->input.analog.axisval[0];
					else if (ev->subid == 1)
						cl->acc_y += ev->input.analog.axisval[0];
				}
				else {
					if (ev->subid == 0){
						cl->acc_x = ev->input.analog.axisval[0];
						consume_relative(cl->client, ev->pts,
							ev->input.analog.axisval[0], ev->input.analog.axisval[1]);
					}
					else if (ev->subid == 1){
						cl->acc_y = ev->input.analog.axisval[0];
						consume_relative(cl->client, ev->pts,
							ev->input.analog.axisval[0], ev->input.analog.axisval[1]);
					}
				}

		/* locked pointer should only emit relative motion */
				if (!cl->confined || !cl->locked)
					update_mxy(cl, ev->pts);
			}
		}
		else
			;
	}
	else if (ev->datatype == EVENT_IDATATYPE_TRANSLATED)
			update_kbd(cl, ev);
	else
		;
}

static void run_callback(struct comp_surf* surf)
{
	if (!surf->acon.addr)
		return;

	for (size_t i = 0; i < COUNT_OF(surf->scratch) && surf->frames_pending; i++){
		if (surf->scratch[i].type == 1){
			surf->scratch[i].type = 0;
			wl_callback_send_done(surf->scratch[i].res, surf->scratch[i].id);
			wl_resource_destroy(surf->scratch[i].res);
			surf->frames_pending--;
			trace(TRACE_SURF, "reply callback: %"PRIu32, surf->scratch[i].id);
			surf->scratch[i] = (struct scratch_req){};
		}
	}
}

static void try_frame_callback(
	struct comp_surf* surf, struct arcan_shmif_cont* acon)
{
/* still synching? */
	if (!acon || !acon->addr || acon->addr->vready){
		return;
	}

/* if this is a surface and there are subsurfaces in play that parent
	size_t i = 0;
	struct comp_surf* subsurf = find_surface_group(0, 's', &i);
	while (subsurf){
		struct comp_surf* psurf = wl_resource_get_user_data(subsurf->sub_parent_res);
		if (psurf == surf){
			printf("subsurface with parent, run callback\n");
			run_callback(subsurf);
		}
		i++;
		subsurf = find_surface_group(0, 's', &i);
	}
 */

	run_callback(surf);
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

	bool change = memcmp(&surf->states, &states, sizeof(struct surf_state)) != 0;
	if (change){
		surf->last_state = surf->states;
	}

	surf->states = states;
	return change;
}

static void flush_surface_events(struct comp_surf* surf)
{
	struct arcan_event ev;
/* rcon is set as redirect-con when there's a shared connection or similar */
	struct arcan_shmif_cont* acon = surf->rcon ? surf->rcon : &surf->acon;

	int pv;
	while ((pv = arcan_shmif_poll(acon, &ev)) > 0){
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
/* have we gotten reconfigured to a different display? if so,
 * the client should send a new scale factor */
		}
/* we might get a migrate reset induced by the client-bridge connection,
 * if so, update viewporting hints at least, and possibly active input-
 * etc. regions as well */
		case TARGET_COMMAND_RESET:{
			if (ev.tgt.ioevs[0].iv == 0){
				trace(TRACE_ALLOC, "surface-reset client rebuild test");
				rebuild_client(surf->client);
			}
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

	trace(TRACE_ALERT, "flush state: %d", pv);
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
/* actual 'close' command varies with the shell type, so the real code
 * for this should come inside the dispatch of the right one */
		break;
		case TARGET_COMMAND_DISPLAYHINT:
			trace(TRACE_ALLOC, "shmif-> target update visibility or size");
			if (ev.tgt.ioevs[0].iv && ev.tgt.ioevs[1].iv){
			}
		break;

/*
 * destroy / re-request all surfaces tied to this client as the underlying
 * connection primitive might have been changed, when stable, this should only
 * need to be done for reset state 3 though, but it helps testing.
 */
		case TARGET_COMMAND_RESET:
			trace(TRACE_ALLOC, "reset-rebuild client");
			rebuild_client(cl);

/* in state 3, we also need to extract the descriptor and swap it out in the
 * pollset or we'll spin 100% */
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
