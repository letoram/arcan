/*
 * Most of these merely mimic the behavior used in xdg- shell with some
 * omissions, and for the needs server-script- side, we're don't need
 * 'more'.
 */

static void ssurf_pong(struct wl_client *client,
	struct wl_resource *resource, uint32_t serial)
{
/* protocol: parent pings, child must pong or be deemed unresponsive */
	trace(TRACE_SHELL, "pong (%"PRIu32")", serial);
}

static void ssurf_move(struct wl_client *client,
	struct wl_resource *res, struct wl_resource *seat, uint32_t serial)
{
	trace(TRACE_SHELL, "%"PRIxPTR" serial: %"PRIu32, (uintptr_t) seat, serial);
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (!surf || !surf->acon.addr){
		return;
	}

	arcan_shmif_enqueue(&surf->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(MESSAGE),
		.ext.message.data = {"shell:xdg_top:move"}
	});
}

static bool shellsurf_shmifev_handler(
	struct comp_surf* surf, struct arcan_event* ev)
{
	if (ev->category == EVENT_TARGET)
		switch (ev->tgt.kind){
/* resize? or focus change? */
		case TARGET_COMMAND_DISPLAYHINT:{
			int w = ev->tgt.ioevs[0].iv;
			int h = ev->tgt.ioevs[1].iv;
			if (wl.force_sz){
				w = wl.init.display_width_px;
				h = wl.init.display_height_px;
			}
			displayhint_handler(surf, &ev->tgt);
			if (w && h && (w != surf->acon.w || h != surf->acon.h)){
				wl_shell_surface_send_configure(
					surf->shell_res, WL_SHELL_SURFACE_RESIZE_NONE, w, h);
			}

			return true;
		}
/* use the default handler for surface callback */
		return false;
		break;
		case TARGET_COMMAND_EXIT:
/*
 * protocol-wtf: there doesn't seem to exist a way for the server
 * to indicate that a shell-surface isn't wanted? do we block/ignore on
 * the surface or kill the client outright?
 */
			return true;
		break;
		default:
		break;
		}

	return false;
}

static void shelledge_to_mask(uint32_t edges, int* dx, int* dy)
{
	switch (edges){
	case WL_SHELL_SURFACE_RESIZE_TOP:
		*dx = 0; *dy = -1;
	break;
	case WL_SHELL_SURFACE_RESIZE_BOTTOM:
		*dx = 0; *dy = 1;
	break;
	case WL_SHELL_SURFACE_RESIZE_LEFT:
		*dx = -1; *dy = 0;
	break;
	case WL_SHELL_SURFACE_RESIZE_TOP_LEFT:
		*dx = -1; *dy = -1;
	break;
	case WL_SHELL_SURFACE_RESIZE_BOTTOM_LEFT:
		*dx = -1; *dy = 1;
	break;
	case WL_SHELL_SURFACE_RESIZE_RIGHT:
		*dx = 1; *dy = 0;
	break;
	case WL_SHELL_SURFACE_RESIZE_TOP_RIGHT:
		*dx = 1; *dy = -1;
	break;
	case WL_SHELL_SURFACE_RESIZE_BOTTOM_RIGHT:
		*dx = 1; *dy = 1;
	break;
	default:
		*dx = 0; *dy = 0;
	break;
	}
}

static void ssurf_resize(struct wl_client *client,
	struct wl_resource *res, struct wl_resource *seat,
	uint32_t serial, uint32_t edges)
{
	trace(TRACE_SHELL, "serial: %"PRIu32", edges: %"PRIu32, serial, edges);
	struct comp_surf* surf = wl_resource_get_user_data(res);
	if (!surf || !surf->acon.addr)
		return;

	int dx, dy;
	shelledge_to_mask(edges, &dx, &dy);

	struct arcan_event ev = {};
	size_t lim = sizeof(ev.ext.message.data)/sizeof(ev.ext.message.data[1]);
	snprintf((char*)ev.ext.message.data, lim, "shell:xdg_top:resize:%d:%d", dx, dy);
	arcan_shmif_enqueue(&surf->acon, &ev);
}

struct shell_metadata {
	struct wl_resource* parent;
	int32_t x, y, flags;
};

static bool shell_defer_handler(
	struct surface_request* req, struct arcan_shmif_cont* con)
{
	if (!req || !con){
		wl_resource_post_no_memory(req->target);
		return false;
	}

	struct comp_surf* surf = wl_resource_get_user_data(req->target);
	snprintf(surf->tracetag, SURF_TAGLEN, "shell_surface");
	surf->acon = *con;
	surf->cookie = 0xfeedface;
	surf->shell_res = req->target;
	surf->dispatch = shellsurf_shmifev_handler;

	arcan_shmif_enqueue(&surf->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(MESSAGE),
		.ext.message = {.data = "shell:xdg_shell"}
	});

/* fill out VIEWPORT hint */
	if (req->tag){
		struct shell_metadata* md = req->tag;
		if (md->parent){
			struct comp_surf* psurf = wl_resource_get_user_data(md->parent);
			surf->viewport.ext.viewport.focus = true;
			surf->viewport.ext.viewport.parent = psurf->acon.segment_token;
			surf->viewport.ext.viewport.x = md->x;
			surf->viewport.ext.viewport.y = md->y;
			arcan_shmif_enqueue(con, &surf->viewport);
		}
	}

	return true;
}

static void surf_request(
	struct wl_client* client, struct wl_resource* res, int segid,
	const char* trace, const char idch, void* tag)
{
	struct comp_surf* surf = wl_resource_get_user_data(res);
	request_surface(surf->client, &(struct surface_request){
		.segid = segid,
		.target = res,
		.trace = trace,
		.dispatch = shell_defer_handler,
		.client = surf->client,
		.source = surf,
		.tag = tag
	}, idch);
}

static void ssurf_toplevel(struct wl_client* client, struct wl_resource* res)
{
	trace(TRACE_SHELL, "");
	surf_request(client, res, SEGID_APPLICATION, "wl_shell_toplevel", 'S', NULL);
}

static void ssurf_transient(struct wl_client *client,
	struct wl_resource *res, struct wl_resource *parent,
	int32_t x, int32_t y, uint32_t flags)
{
	trace(TRACE_SHELL, "%d, %d\n", (int)x, (int)y);
	struct shell_metadata md = {
		.parent = parent,
		.x = x,
		.y = y,
		.flags = flags
	};

	surf_request(client, res, SEGID_APPLICATION, "wl_shell_transient", 'T', &md);
}

static void ssurf_fullscreen(struct wl_client *client,
	struct wl_resource *resource, uint32_t method,
	uint32_t framerate, struct wl_resource *output)
{
	trace(TRACE_SHELL, "");
	ssurf_toplevel(client, resource);
}

static void ssurf_popup(struct wl_client *client,
	struct wl_resource* res, struct wl_resource *seat,
	uint32_t serial, struct wl_resource *parent,
	int32_t x, int32_t y, uint32_t flags)
{
	trace(TRACE_SHELL, "");
	struct shell_metadata md = {
		.x = x,
		.y = y,
		.flags = flags,
		.parent = parent
	};

	surf_request(client, res, SEGID_POPUP, "wl_shell_popup", 'P', &md);
}

static void ssurf_maximized(struct wl_client *client,
	struct wl_resource *resource, struct wl_resource *output)
{
	trace(TRACE_SHELL, "");
	struct comp_surf* surf = wl_resource_get_user_data(resource);
	if (!surf || !surf->acon.addr)
		return;

	arcan_shmif_enqueue(&surf->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(MESSAGE),
		.ext.message.data = {"shell:xdg_top:maximize"}
	});
}

static void ssurf_title(struct wl_client* client,
	struct wl_resource* resource, const char* title)
{
	trace(TRACE_SHELL, "title(%s)", title ? title : "no title");
	struct comp_surf* surf = wl_resource_get_user_data(resource);
	if (!surf || !surf->acon.addr)
		return;

	arcan_event ev = {
		.ext.kind = ARCAN_EVENT(IDENT)
	};
	size_t lim = sizeof(ev.ext.message.data)/sizeof(ev.ext.message.data[1]);
	snprintf((char*)ev.ext.message.data, lim, "%s", title);
	arcan_shmif_enqueue(&surf->acon, &ev);
}

static void ssurf_class(struct wl_client *client,
struct wl_resource *resource, const char *class_)
{
	trace(TRACE_SHELL, "class(%s)", class_ ? class_ : "no class"); /* indeed */
}
