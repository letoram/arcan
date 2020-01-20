static void zxdg_invalid_input(struct wl_resource* res)
{
	wl_resource_post_error(res,
		ZXDG_POSITIONER_V6_ERROR_INVALID_INPUT, "w||h must be > 0");
}

static void zxdg_apply_positioner(
	struct positioner* pos, struct arcan_event* ev)
{
	if (!pos || !ev)
		return;

	ev->category = EVENT_EXTERNAL;
	ev->ext.kind = ARCAN_EVENT(VIEWPORT);
	ev->ext.viewport.y = pos->ofs_y;
	ev->ext.viewport.x = pos->ofs_x;
	ev->ext.viewport.w = pos->width;
	ev->ext.viewport.h = pos->height;

	if (pos->anchor & ZXDG_POSITIONER_V6_ANCHOR_TOP)
		ev->ext.viewport.y += pos->anchor_y;
	else if (pos->anchor & ZXDG_POSITIONER_V6_ANCHOR_BOTTOM)
		ev->ext.viewport.y += pos->anchor_y + pos->anchor_height;
	else
		ev->ext.viewport.y += pos->anchor_y + (pos->anchor_height >> 1);

	if (pos->anchor & ZXDG_POSITIONER_V6_ANCHOR_LEFT)
		ev->ext.viewport.x += pos->anchor_x;
	else if (pos->anchor & ZXDG_POSITIONER_V6_ANCHOR_RIGHT)
		ev->ext.viewport.x += pos->anchor_x + pos->anchor_width;
	else
		ev->ext.viewport.x += pos->anchor_x + (pos->anchor_width >> 1);

	if (pos->gravity & ZXDG_POSITIONER_V6_GRAVITY_TOP)
		ev->ext.viewport.y -= pos->height;
	else if (pos->gravity & ZXDG_POSITIONER_V6_GRAVITY_BOTTOM)
		;
	else
		ev->ext.viewport.y -= pos->height >> 1;

/*
 * uncertain what to do about the constraint adjustment at this stage
 */
}

static void zxdgpos_size(struct wl_client* cl,
	struct wl_resource* res, int32_t width, int32_t height)
{
	trace(TRACE_SHELL, "%"PRId32", %"PRId32, width, height);
	struct positioner* pos = wl_resource_get_user_data(res);
	if (width < 1 || height < 1)
		return zxdg_invalid_input(res);

	pos->width = width;
	pos->height = height;
}

static void zxdgpos_anchor_rect(struct wl_client* cl,
	struct wl_resource* res, int32_t x, int32_t y, int32_t width, int32_t height)
{
	trace(TRACE_SHELL, "x,y: %"PRId32", %"PRId32" w,h: %"PRId32", %"PRId32,
		x, y, width, height);
	struct positioner* pos = wl_resource_get_user_data(res);

	if (width < 1 || height < 1)
		return zxdg_invalid_input(res);

	pos->anchor_x = x;
	pos->anchor_y = y;
	pos->anchor_width = width;
	pos->anchor_height = height;
}

static void zxdgpos_anchor(struct wl_client* cl,
	struct wl_resource* res, uint32_t anchor)
{
	trace(TRACE_SHELL, "%"PRIu32, anchor);
	struct positioner* pos = wl_resource_get_user_data(res);
	pos->anchor = anchor;
}

static void zxdgpos_gravity(struct wl_client* cl,
	struct wl_resource* res, uint32_t gravity)
{
	trace(TRACE_SHELL, "%"PRIu32, gravity);
	struct positioner* pos = wl_resource_get_user_data(res);
/* ENFORCE: if the gravity constraints are invalid, send invalid input */
	pos->gravity = gravity;
}

static void zxdgpos_consadj(struct wl_client* cl,
	struct wl_resource* res, uint32_t constraint_adjustment)
{
	trace(TRACE_SHELL, "%"PRIu32, constraint_adjustment);
	struct positioner* pos = wl_resource_get_user_data(res);
	pos->constraints = constraint_adjustment;
}

static void zxdgpos_offset(struct wl_client* cl,
	struct wl_resource* res, int32_t x, int32_t y)
{
	trace(TRACE_SHELL, "+x,y: %"PRId32", %"PRId32, x, y);
	struct positioner* pos = wl_resource_get_user_data(res);
	pos->ofs_x = x;
	pos->ofs_y = y;
}

static void zxdgpos_destroy(struct wl_client* cl, struct wl_resource* res)
{
	trace(TRACE_SHELL, "%"PRIxPTR, (uintptr_t) res);
}
