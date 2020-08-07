static void xdg_invalid_input(struct wl_resource* res)
{
	wl_resource_post_error(res,
		XDG_POSITIONER_ERROR_INVALID_INPUT, "w||h must be > 0");
}

static bool apply_positioner(
	struct positioner* pos, struct arcan_event* ev)
{
	if (!pos || !ev)
		return false;

	ev->category = EVENT_EXTERNAL;
	ev->ext.kind = ARCAN_EVENT(VIEWPORT);
	ev->ext.viewport.y = pos->anchor_y + pos->ofs_y;
	ev->ext.viewport.x = pos->anchor_x + pos->ofs_x;
	ev->ext.viewport.w = pos->width;
	ev->ext.viewport.h = pos->height;

/* translate anchor to viewport anchor-pos */
	bool t = pos->anchor & XDG_POSITIONER_ANCHOR_TOP;
	bool l = pos->anchor & XDG_POSITIONER_ANCHOR_LEFT;
	bool d = pos->anchor & XDG_POSITIONER_ANCHOR_BOTTOM;
	bool r = pos->anchor & XDG_POSITIONER_ANCHOR_RIGHT;

	if ((l && r) || (t && d)){
		return false;
	}

	if (t){
		if (l)
			ev->ext.viewport.edge = 1;
		else if (r)
			ev->ext.viewport.edge = 3;
		else
			ev->ext.viewport.edge = 2;
	}
	else if (d){
		if (l)
			ev->ext.viewport.edge = 7;
		else if (r)
			ev->ext.viewport.edge = 9;
		else
			ev->ext.viewport.edge = 8;
	}
	else if (l)
		ev->ext.viewport.edge = 4;
	else if (r)
		ev->ext.viewport.edge = 6;
	else
		ev->ext.viewport.edge = 5;

	ev->ext.viewport.anchor_edge = 1;
	ev->ext.viewport.anchor_pos = 1;

/* uncertain how to translate these really */
	if (pos->gravity & XDG_POSITIONER_GRAVITY_TOP)
		ev->ext.viewport.y -= pos->height;
	else if (pos->gravity & XDG_POSITIONER_GRAVITY_BOTTOM)
		;
	else
		ev->ext.viewport.y -= pos->height >> 1;

	return true;
}

static void xdgpos_size(struct wl_client* cl,
	struct wl_resource* res, int32_t width, int32_t height)
{
	trace(TRACE_SHELL, "%"PRId32", %"PRId32, width, height);
	struct positioner* pos = wl_resource_get_user_data(res);
	if (width < 1 || height < 1)
		return xdg_invalid_input(res);

	pos->width = width;
	pos->height = height;
}

static void xdgpos_anchor_rect(struct wl_client* cl,
	struct wl_resource* res, int32_t x, int32_t y, int32_t width, int32_t height)
{
	trace(TRACE_SHELL, "x,y: %"PRId32", %"PRId32" w,h: %"PRId32", %"PRId32,
		x, y, width, height);
	struct positioner* pos = wl_resource_get_user_data(res);

	if (width <= 0 || height < 0)
		return xdg_invalid_input(res);

	pos->anchor_x = x;
	pos->anchor_y = y;
	pos->anchor_width = width;
	pos->anchor_height = height;
}

static void xdgpos_anchor(struct wl_client* cl,
	struct wl_resource* res, uint32_t anchor)
{
	trace(TRACE_SHELL, "%"PRIu32, anchor);
	struct positioner* pos = wl_resource_get_user_data(res);
	pos->anchor = anchor;
}

static void xdgpos_gravity(struct wl_client* cl,
	struct wl_resource* res, uint32_t gravity)
{
	trace(TRACE_SHELL, "%"PRIu32, gravity);
	struct positioner* pos = wl_resource_get_user_data(res);
/* ENFORCE: if the gravity constraints are invalid, send invalid input */
	pos->gravity = gravity;
}

static void xdgpos_consadj(struct wl_client* cl,
	struct wl_resource* res, uint32_t constraint_adjustment)
{
	trace(TRACE_SHELL, "%"PRIu32, constraint_adjustment);
	struct positioner* pos = wl_resource_get_user_data(res);
	pos->constraints = constraint_adjustment;
}

static void xdgpos_offset(struct wl_client* cl,
	struct wl_resource* res, int32_t x, int32_t y)
{
	trace(TRACE_SHELL, "+x,y: %"PRId32", %"PRId32, x, y);
	struct positioner* pos = wl_resource_get_user_data(res);
	pos->ofs_x = x;
	pos->ofs_y = y;
}

static void xdgpos_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "%"PRIxPTR, (uintptr_t) res);
	wl_resource_set_user_data(res, NULL);
	wl_resource_destroy(res);
}
