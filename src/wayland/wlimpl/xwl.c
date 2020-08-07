/*
 * There are a number of oddities with dealing with XWayland, and
 * its behavior change depending on if you are using rootless mode
 * or not.
 *
 * With 'normal' mode it behaves as a dumb (and buggy) wl_shell
 * client that basically ignored everything.
 *
 * With 'rootless' mode, it creates compositor surfaces and uses
 * them directly - being basically the only client to do so. The
 * job then is to pair these surfaces based on a window property
 * and just treat them as something altogether special by adding
 * a custom window-manager.
 */
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>

static FILE* wmfd_output = NULL;
static pid_t xwl_wm_pid = -1;
static char* xwl_wm_display;

static int wmfd_input = -1;
static char wmfd_inbuf[1024];
static size_t wmfd_ofs = 0;

/*
 * HACK:
 * Issues deep inside Xwayland cause some clients to not forward the
 * client message WL_SURFACE_ID that is needed to pair a wayland surface with
 * its window in X (xwl_ensure_surface_for_window -> send_surface_id -> then
 * it gets horrible). To work-around this we can fake-pair them.
 */
static struct wl_resource* pending_resource;

/* "known" mapped windows, we trigger the search etc. when a buffer
 * is commited without a known backing on the compositor, and try
 * to 'pair' it with ones that we have been told about */
struct xwl_window {

/* Xid for Window */
	uint32_t id;

/* Wayland client-local reference ID */
	uint32_t surface_id;

/* Parent Xid for Window */
	uint32_t parent_id;

/* Track viewport separate from comp_surf viewport as it can be
 * populated when there is still no surf to pair it to */
	struct arcan_event viewport;

/* a window mapping that is PAIRED means that we know both the local
 * compositor surface and the wmed X surface */
	bool paired;

/* a window mapping that is PENDING means that we only know the local
 * compositor surface and there is a pending commit on that surface */
	struct wl_resource* pending_res;
	struct wl_client* pending_client;

/* when a surface goes pending, we flush a queue of pending wm state
 * messages, if the size does not suffice here, we should really
 * just override the ones that have been redefined */
	size_t queue_count;
	struct arcan_event queued_message[8];

	char* xtype;
	struct comp_surf* surf;
};

/* just linear search it for the time being, can copy the UT_HASH
 * use from the xwlwm side if need be */

static struct xwl_window xwl_windows[256];
static struct xwl_window* xwl_find(uint32_t id)
{
	for (size_t i = 0; i < COUNT_OF(xwl_windows); i++)
		if (xwl_windows[i].id == id)
			return &xwl_windows[i];

	return NULL;
}

static void wnd_message(struct xwl_window* wnd, const char* fmt, ...)
{
	struct arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(MESSAGE)
	};

	va_list args;
	va_start(args, fmt);
		vsnprintf((char*)ev.ext.message.data,
			COUNT_OF(ev.ext.message.data), fmt, args);
	va_end(args);

/* messages can come while unpaired, buffer them for the time being */
	if (!wnd->surf){
		if (wnd->queue_count < COUNT_OF(wnd->queued_message)){
			trace(TRACE_XWL,
				"queue(%zu:%s) unpaired: %s", wnd->queue_count,
				arcan_shmif_eventstr(&ev, NULL, 0), ev.ext.message.data);
			wnd->queued_message[wnd->queue_count++] = ev;
		}
		else {
			trace(TRACE_XWL, "queue full, broken wm");
		}
		return;
	}

	trace(TRACE_XWL, "message:%s", ev.ext.message.data);
	arcan_shmif_enqueue(&wnd->surf->acon, &ev);
}


static struct xwl_window* xwl_find_surface(uint32_t id)
{
	for (size_t i = 0; i < COUNT_OF(xwl_windows); i++)
		if (xwl_windows[i].surface_id == id)
			return &xwl_windows[i];

	return NULL;
}

static struct xwl_window* xwl_find_alloc(uint32_t id)
{
	struct xwl_window* wnd = xwl_find(id);
	if (wnd)
		return wnd;

/* default to 'toplevel' like behavior */
	wnd = xwl_find(0);
	return wnd;
}

static void surf_commit(struct wl_client*, struct wl_resource*);
static void wnd_viewport(struct xwl_window* wnd);

static void xwl_wnd_paired(struct xwl_window* wnd)
{
/*
 * we will be sent here if there existed a surface id before the id mapping was
 * known, and there might be an id before the surface id. Find the 'orphan'
 * and copy / merge
 */
	ssize_t match = -1;

	for (size_t i = 0; i < COUNT_OF(xwl_windows); i++){
		if (&xwl_windows[i] == wnd){
			continue;
		}
		if (xwl_windows[i].id == wnd->id || xwl_windows[i].id == wnd->surface_id){
			match = i;
			break;
		}
	}

/* merge orphan states */
	if (-1 != match){
		struct xwl_window tmp = *wnd;
		struct xwl_window* xwnd = &xwl_windows[match];

		*wnd = *xwnd;
		wnd->id = tmp.id;
		wnd->surface_id = tmp.surface_id;
		wnd->pending_res = tmp.pending_res;
		wnd->pending_client = tmp.pending_client;
		*xwnd = (struct xwl_window){};
	}

/* this requires some thinking, surface commit on a compositor surface will
 * lead to a query if the surface has been paired to a non-wayland one (X11) */
	wnd->paired = true;
	if (pending_resource && wl_resource_get_id(pending_resource) == wnd->id){
		pending_resource = NULL;
	}

	wnd_message(wnd, "pair:%d:%d", wnd->surface_id, wnd->id);
	surf_commit(wnd->pending_client, wnd->pending_res);

	if (!wnd->surf){
		trace(TRACE_XWL, "couldn't pair, surface allocation failed");
		return;
	}

	wnd->pending_res = NULL;
	wnd->pending_client = NULL;
}

static void wnd_viewport(struct xwl_window* wnd)
{
/* always re-resolve parent token */
	wnd->viewport.ext.viewport.parent = 0;

	if (wnd->parent_id > 0){
		struct xwl_window* pwnd = xwl_find(wnd->parent_id);
		if (!pwnd || !pwnd->surf){
			trace(TRACE_XWL, "bad parent id:%"PRIu32, wnd->parent_id);
		}
		else{
		trace(TRACE_XWL, "parent set (%"PRIu32") => (%"PRIu32")",
			wnd->parent_id, pwnd->surf->acon.segment_token);
			wnd->viewport.ext.viewport.parent = pwnd->surf->acon.segment_token;
		}
	}

	if (!wnd->surf)
		return;

	arcan_shmif_enqueue(&wnd->surf->acon, &wnd->viewport);

	trace(TRACE_XWL, "viewport id:%"PRIu32",parent:%"PRIu32"@%"PRId32",%"PRId32,
		wnd->id, wnd->parent_id,
		wnd->viewport.ext.viewport.x, wnd->viewport.ext.viewport.y
	);
}

/*
 * Take an input- line from the window manager, unpack it, and interpret the
 * command inside. A noticable part here is that the resolved window may be
 * in an unallocated, unpaired or paired state here and the input itself is
 * not necessarily trusted.
 *
 * Thus any extracted field or update that should propagate as an event to
 * a backing shmif connection need to be support being deferred until
 * pairing / allocation - and resist UAF/spoofing. Luckily, there is not
 * many events that need to be forwarded.
 */
static int process_input(const char* msg)
{
/* special handling for multiplexing trace messages */
	trace(TRACE_XWL, "wm->%s", msg);
	if (strncmp(msg, "kind=trace", 10) == 0){
		return 0;
	}

	struct arg_arr* cmd = arg_unpack(msg);
	if (!cmd){
		trace(TRACE_XWL, "malformed message: %s", msg);
		return 0;
	}

/* all commands should have a 'kind' field */
	const char* arg;
	if (!arg_lookup(cmd, "kind", 0, &arg) && arg){
		trace(TRACE_XWL, "malformed argument: %s, missing kind", msg);
		goto cleanup;
	}
/* pair surface */
	else if (strcmp(arg, "surface") == 0){
		if (!arg_lookup(cmd, "id", 0, &arg) && arg){
			trace(TRACE_XWL, "malformed surface argument: missing id");
			goto cleanup;
		}
		uint32_t id = strtoul(arg, NULL, 10);
		if (!arg_lookup(cmd, "surface_id", 0, &arg) && arg){
			trace(TRACE_XWL, "malformed surface argument: missing surface id");
			goto cleanup;
		}
		uint32_t surface_id = strtoul(arg, NULL, 10);
		trace(TRACE_XWL, "surface id:%"PRIu32"-%"PRIu32, id, surface_id);
		struct xwl_window* wnd = xwl_find_surface(surface_id);
		if (!wnd)
			wnd = xwl_find_alloc(id);
		if (!wnd)
			goto cleanup;

		wnd->surface_id = surface_id;
		wnd->id = id;

/* if we already know about the compositor-surface, activate it */
		if (wnd->pending_res){
			trace(TRACE_XWL, "paired-pending %"PRIu32, id);
			xwl_wnd_paired(wnd);
		}
		wnd->paired = true;
	}
/* window goes from invisible to visible state */
	else if (strcmp(arg, "create") == 0){
		if (!arg_lookup(cmd, "id", 0, &arg) && arg){
			trace(TRACE_XWL, "malformed map argument: missing id");
			goto cleanup;
		}
		uint32_t id = strtoul(arg, NULL, 10);
		trace(TRACE_XWL, "map id:%"PRIu32, id);
		struct xwl_window* wnd = xwl_find_alloc(id);
		if (!wnd)
			goto cleanup;

		wnd->id = id;

/* should come with some kind of type information */
		if (arg_lookup(cmd, "type", 0, &arg) && arg){
			trace(TRACE_XWL, "created with type %s", arg);
			wnd->xtype = strdup(arg);
			wnd_message(wnd, "type:%s", arg);
		}
		else{
			trace(TRACE_XWL, "malformed create argument: missing type");
			goto cleanup;
		}

/* we only viewport when we have a grab or hierarchy relationship change */
		if (arg_lookup(cmd, "parent", 0, &arg) && arg){
			uint32_t parent_id = strtoul(arg, NULL, 0);
			struct xwl_window* wnd = xwl_find(parent_id);
			if (wnd){
				trace(TRACE_XWL, "found parent surface: %"PRIu32, parent_id);
				wnd->parent_id = parent_id;
				wnd_viewport(wnd);
			}
			else
				trace(TRACE_XWL, "bad parent-id: "PRIu32, parent_id);
		}
	}
/* reparent */
	else if (strcmp(arg, "parent") == 0){
		if (!arg_lookup(cmd, "id", 0, &arg) && arg)
			goto cleanup;
		uint32_t id = strtoul(arg, NULL, 10);

		if (!arg_lookup(cmd, "parent_id", 0, &arg) && arg)
			goto cleanup;

		uint32_t parent_id = strtoul(arg, NULL, 10);
		struct xwl_window* wnd = xwl_find(id);

		if (!wnd)
			goto cleanup;

		wnd->parent_id = parent_id;
		trace(TRACE_XWL, "reparent id:%"PRIu32" to %"PRIu32, id, parent_id);
		wnd_viewport(wnd);
	}
/* invisible -> visible */
	else if (strcmp(arg, "map") == 0){
		if (!arg_lookup(cmd, "id", 0, &arg) && arg){
			trace(TRACE_XWL, "map:status=no_id");
			goto cleanup;
		}
		uint32_t id = strtoul(arg, NULL, 10);
		struct xwl_window* wnd = xwl_find(id);

		if (!wnd){
			trace(TRACE_XWL, "map:id=%"PRIu32":status=no_wnd", id);
			goto cleanup;
		}

/* HACK, if it is not paired and we have a pending wl-surf, guess they
 * belong together */
		if (!wnd->paired && pending_resource){
			wnd->surface_id = wl_resource_get_id(pending_resource);
			wnd->id = id;
			wnd->pending_res = pending_resource;
			pending_resource = NULL;
			xwl_wnd_paired(wnd);
		}

		wnd->viewport.ext.viewport.invisible = false;
		if (arg_lookup(cmd, "parent_id", 0, &arg)){
			wnd->parent_id = strtoul(arg, NULL, 10);
		}

		if (arg_lookup(cmd, "x", 0, &arg)){
			wnd->viewport.ext.viewport.x = strtol(arg, NULL, 10);
		}
		if (arg_lookup(cmd, "y", 0, &arg)){
			wnd->viewport.ext.viewport.y = strtol(arg, NULL, 10);
		}

		if (!arg_lookup(cmd, "type", 0, &arg)){
			trace(TRACE_XWL, "remap id:%"PRIu32", failed, no type information", id);
			goto cleanup;
		}

		if (wnd->xtype)
			free(wnd->xtype);
		wnd->xtype = strdup(arg);
		wnd_message(wnd, "type:%s", arg);
		wnd_viewport(wnd);
	}
/* window goes from visible to invisible state, but resources remain */
	else if (strcmp(arg, "unmap") == 0){
		trace(TRACE_XWL, "unmap");
		uint32_t id = strtoul(arg, NULL, 10);
		struct xwl_window* wnd = xwl_find(id);
		if (!wnd)
			goto cleanup;

		wnd->viewport.ext.viewport.invisible = true;
		wnd_viewport(wnd);
	}
	else if (strcmp(arg, "terminated") == 0){
		trace(TRACE_XWL, "xwayland died");
		if (wl.exec_mode)
			wl.alive = false;
	}
/* window changes position or hierarchy, the size part is tied to the
 * buffer in shmif- parlerance so we don't really care to match that
 * here */
	else if (strcmp(arg, "configure") == 0){
		if (!arg_lookup(cmd, "id", 0, &arg)){
			trace(TRACE_XWL, "malformed surface argument: missing surface id");
			goto cleanup;
		}
		uint32_t id = strtoul(arg, NULL, 10);
		struct xwl_window* wnd = xwl_find(id);
		if (!wnd){
			trace(TRACE_XWL, "configure on unknown id %"PRIu32, id);
			goto cleanup;
		}

/* we cache the viewport event for the window as well as for the surface
 * due to the possibility of the unpaired state */
		if (arg_lookup(cmd, "x", 0, &arg)){
			wnd->viewport.ext.viewport.x = strtol(arg, NULL, 10);
		}

		if (arg_lookup(cmd, "y", 0, &arg)){
			wnd->viewport.ext.viewport.y = strtol(arg, NULL, 10);
		}

/* and either reflect now or later */
		wnd_viewport(wnd);
	}
/* just forward */
	else if (arg_lookup(cmd, "fullscreen", 0, &arg) && arg){
		if (!arg_lookup(cmd, "id", 0, &arg)){
			trace(TRACE_XWL, "malformed surface argument: missing surface id");
			goto cleanup;
		}
		uint32_t id = strtoul(arg, NULL, 10);
		struct xwl_window* wnd = xwl_find(id);
		if (!wnd){
			trace(TRACE_XWL, "configure on unknown id %"PRIu32, id);
			goto cleanup;
		}

		wnd_message(wnd, "fullscreen=%s", arg);
	}

cleanup:
	arg_cleanup(cmd);
	return 0;
}

static int xwl_spawn_check(const char* msg)
{
	struct arg_arr* cmd = arg_unpack(msg);
	int rv = -1;
	if (cmd){
		const char* arg;
		if (arg_lookup(cmd, "xwayland_fail", 0, &arg)){
			trace(TRACE_XWL, "couldn't spawn xwayland: %s", arg);
			rv = -3;
		}
		if (arg_lookup(cmd, "xwayland_ok", 0, &arg)){
			trace(TRACE_XWL, "xwayland on: %s", arg);
			xwl_wm_display = strdup(arg);
		}
		arg_cleanup(cmd);
		rv = 0;
	}
	return rv;
}

static void close_xwl()
{
	fclose(wmfd_output);
	close(wmfd_input);
	wmfd_ofs = 0;
	xwl_wm_pid = -1;
	wmfd_input = -1;
	trace(TRACE_XWL, "arcan_xwm died");
}

static int xwl_read_wm(int (*callback)(const char* str))
{
	if (xwl_wm_pid == -1)
		return -1;

/* track so we don't accidentally call into ourself */
	static bool in_wm_input;
	if (in_wm_input)
		return 0;
	in_wm_input = true;

/* populate inbuffer, look for linefeed */
	char inbuf[256];
	int status;
	ssize_t nr = read(wmfd_input, inbuf, 256);
	if (-1 == nr){
		if (errno != EAGAIN && errno != EINTR){
			trace(TRACE_XWL, "kind=error:code=%d:message=%s", errno, strerror(errno));
			kill(xwl_wm_pid, SIGKILL);
			waitpid(xwl_wm_pid, NULL, 0);
			close_xwl();
		}
		else {
			int res = waitpid(xwl_wm_pid, &status, WNOHANG);
			if (res == xwl_wm_pid && WIFEXITED(status)){
				trace(TRACE_XWL, "kind=status:message=exited");
				close_xwl();
			}
		}

		in_wm_input = false;
		return -1;
	}

/* check the new input for a linefeed character, or flush to the buffer */
	for (size_t i = 0; i < nr; i++){
		if (inbuf[i] == '\n'){
			wmfd_inbuf[wmfd_ofs] = '\0';
			wmfd_ofs = 0;

/* leave the rest in buffer */
			if (callback(wmfd_inbuf) != 0){
				trace(TRACE_XWL, "kind=error:callback_fail:message=%s", wmfd_inbuf);
				break;
			}
		}
/* accept crop on overflow (though no command should be this long) */
		else {
			wmfd_inbuf[wmfd_ofs] = inbuf[i];
			wmfd_ofs ++;
			if (wmfd_ofs == sizeof(wmfd_inbuf)){
				trace(TRACE_XWL, "kind=error:overflow");
				wmfd_ofs = 0;
			}
		}
	}

/* possibly more to flush */
	in_wm_input = false;
	if (nr == 256)
		return xwl_read_wm(callback);

	return 0;
}

static void xwl_request_handover()
{
/* use the waybridge to request a handover surface that will be used for xwl
 * debugging bootstrap and for clipboard / selection - it is a bit trickier if
 * this happens on a wm-crash where we run in service mode as the control
 * connection is lost, option is to re-open one or just ignore the clipboard
 * part, start with the later */
	if (!wl.control.addr){
		return;
	}

	arcan_shmif_enqueue(&wl.control,
	&(struct arcan_event){
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.kind = SEGID_HANDOVER
	});

}

/*
 * Launch the arcan-xwayland-wm (that in turn launches Xwayland) if [block] is
 * set, wait until arcan-xwayland-wm acknowledges that Xwayland could be
 * launched or not.
 *
 * The other detail is how to handle the clipboard in a way that covers both
 * cut/paste and drag/drop. Best is probably to request a clipboard/handover
 * and then exec that into arcan-xwayland-wm.
 *
 * Error codes:
 * -1 : arcan-xwayland-wm connection died
 * -2 : arcan-xwayland-wm couldn't spawn Xwayland
 * -3 : resource errors spawning arcan-xwayland-wm
 *  0 : ok
 */
static int xwl_spawn_wm(bool block, char** argv)
{
/* already running */
	if (xwl_wm_pid != -1)
		return 0;

	trace(TRACE_XWL, "spawning 'arcan-xwayland-wm'");
	wl.groups[0].xwm->fd = -1;
	int p2c_pipe[2];
	int c2p_pipe[2];
	if (-1 == pipe(p2c_pipe))
		return -3;

	if (-1 == pipe(c2p_pipe)){
		close(p2c_pipe[0]);
		close(p2c_pipe[1]);
		return -3;
	}

	wmfd_input = c2p_pipe[0];
	wmfd_output = fdopen(p2c_pipe[1], "w");
	setlinebuf(wmfd_output);
	wl.groups[0].xwm->fd = wmfd_input;

	xwl_wm_pid = fork();

	if (-1 == xwl_wm_pid){
		fprintf(stderr, "Couldn't spawn wm- process (fork failed)\n");
		exit(EXIT_FAILURE);
	}

/* child, close, dup spawn */
	if (!xwl_wm_pid){
		close(p2c_pipe[1]);
		close(c2p_pipe[0]);
		dup2(p2c_pipe[0], STDIN_FILENO);
		dup2(c2p_pipe[1], STDOUT_FILENO);
		close(p2c_pipe[1]);
		close(c2p_pipe[0]);

		setsid();
		int ndev = open("/dev/null", O_WRONLY);
		dup2(ndev, STDERR_FILENO);
		close(ndev);

		size_t nargs = 0;
		while (argv[nargs])
			nargs++;

/* need to prepend the binary name so top makes sense */
		char* newargv[nargs+2];
		newargv[0] = "arcan_xwm";
		newargv[nargs+1] = NULL;
		for (size_t i = 0; i < nargs+1; i++){
			newargv[i+1] = argv[i];
		}

/* want to avoid the situation when building / working from a build dir, the
 * execvp approach would still the usr/bin one */
#ifdef _DEBUG
		execv("./arcan_xwm", newargv);
#endif
		execvp("arcan_xwm", newargv);
		exit(EXIT_FAILURE);
	}

/* in this case we care about the status of the ability to launch Xwayland,
 * this happens with -xwl -exec */
	if (block){
		int rv = xwl_read_wm(xwl_spawn_check);
		if (rv < 0)
			return rv;
	}

/* want the input-pipe to work non-blocking here */
	int flags = fcntl(wmfd_input, F_GETFL);
		if (-1 != flags)
			fcntl(wmfd_input, F_SETFL, flags | O_NONBLOCK);

/* drop child write end, parent read end as the wm process owns these now */
	close(c2p_pipe[1]);
	close(p2c_pipe[0]);

	return 0;
}

static void xwl_check_wm()
{
	xwl_read_wm(process_input);
}

static bool xwlsurf_shmifev_handler(
	struct comp_surf* surf, struct arcan_event* ev)
{
	if (ev->category != EVENT_TARGET || !wmfd_output)
		return false;

/* translate relevant non-input shmif events to the text- based
 * format used with the wm- process */

	struct xwl_window* wnd =
		xwl_find_surface(wl_resource_get_id(surf->shell_res));
	if (!wnd)
		return false;

	switch (ev->tgt.kind){
	case TARGET_COMMAND_DISPLAYHINT:{
		struct surf_state states = surf->states;
		bool changed = displayhint_handler(surf, &ev->tgt);
		int rw = ev->tgt.ioevs[0].iv;
		int rh = ev->tgt.ioevs[1].iv;
		int dw = rw - (int)surf->acon.w;
		int dh = rh - (int)surf->acon.h;

/* split up into resize requests and focus/input changes */
		if (rw > 0 && rh > 0 && (dw != 0 || dh != 0)){
			trace(TRACE_XWL, "displayhint: %"PRIu32",%"PRIu32,
				ev->tgt.ioevs[0].iv, ev->tgt.ioevs[1].iv);

			fprintf(wmfd_output,
				"id=%"PRIu32":kind=resize:width=%"PRIu32":height=%"PRIu32"%s\n",
				(uint32_t) wnd->id,
				(uint32_t) abs(ev->tgt.ioevs[0].iv),
				(uint32_t) abs(ev->tgt.ioevs[1].iv),
				(surf->states.drag_resize) ? ":drag" : ""
			);
		}

		if (changed){
			if (states.unfocused != surf->states.unfocused){
				fprintf(wmfd_output, "id=%"PRIu32"%s\n",
					wnd->id, surf->states.unfocused ? ":kind=unfocus" : ":kind=focus");
				if (surf->states.unfocused){
					leave_all(surf);
				}
				else{
					enter_all(surf);
					if (surf->client->pointer){
						wl_pointer_send_button(surf->client->pointer, STEP_SERIAL(),
							arcan_timemillis(), 0x10f, WL_POINTER_BUTTON_STATE_RELEASED);
					}
				}
			}
		}

		return true;
	}
/* raw-forward from appl to xwm, doesn't respect multipart */
	case TARGET_COMMAND_MESSAGE:
		fprintf(wmfd_output, "id=%"PRIu32":%s\n", (uint32_t) wnd->id, ev->tgt.message);
	break;
	case TARGET_COMMAND_EXIT:
		fprintf(wmfd_output, "kind=destroy:id=%"PRIu32"\n", wnd->id);
		return true;
	default:
	break;
	}

	return false;
}

static bool xwl_defer_handler(
	struct surface_request* req, struct arcan_shmif_cont* con)
{
	if (!req || !con){
		return false;
	}

	struct comp_surf* surf = wl_resource_get_user_data(req->target);
	surf->acon = *con;
	surf->cookie = 0xfeedface;
	surf->shell_res = req->target;
	surf->dispatch = xwlsurf_shmifev_handler;
	surf->id = wl_resource_get_id(surf->shell_res);

	struct xwl_window* wnd = (req->tag);
	wnd->surf = surf;
	wnd->viewport.ext.kind = ARCAN_EVENT(VIEWPORT);
	trace(TRACE_ALLOC, "kind=X:fd=%d:queue=%zu", con->epipe, wnd->queue_count);

/* the normal path is:
 * surface_commit -> check_paired -> request surface -> request ok ->
 * commit and flush */
	if (wnd->queue_count > 0){
		trace(TRACE_XWL, "flush (%zu) queued messages", wnd->queue_count);
		for (size_t i = 0; i < wnd->queue_count; i++){
			arcan_shmif_enqueue(con, &wnd->queued_message[i]);
		}
		wnd->queue_count = 0;
	}
	wnd_viewport(wnd);

	return true;
}

static struct xwl_window*
	lookup_surface(struct comp_surf* surf, struct wl_resource* res)
{
	if (!wl.use_xwayland)
		return NULL;

/* always start by synching against pending from wm as the surface + atom
 * mapping might be done there before we actually get to this stage */
	xwl_check_wm();
	uint32_t id = wl_resource_get_id(res);
	struct xwl_window* wnd = xwl_find_surface(id);
	if (!wnd){
		wnd = xwl_find(0);
		if (!wnd){
			trace(TRACE_XWL, "out-of-memory");
			return NULL;
		}
		wnd->surface_id = id;
	}
	return wnd;
}

/* called from the surface being commited when it is not marked as paired */
static bool xwl_pair_surface(
	struct wl_client* cl, struct comp_surf* surf, struct wl_resource* res)
{
/* do we know of a matching xwayland- provided surface? */
	struct xwl_window* wnd = lookup_surface(surf, res);
	if (!wnd){
		trace(TRACE_XWL,
			"no known X surface for: %"PRIu32, wl_resource_get_id(res));
		return false;
	}

/* are we waiting for the surface-id part? then set as pending so that we can
 * activate when it arrives - allocation behavior is a bit suspicious here -
 * other option is also to release the buffer and trigger frame callbacks */
	if (!wnd->paired){
		trace(TRACE_XWL,
			"unpaired surface-ID: %"PRIu32, wl_resource_get_id(res));
		wnd->pending_res = res;
		wnd->pending_client = cl;

/* remember the last pending window, this is race prone on multiple clients */
		if (!pending_resource)
			pending_resource = res;

		return false;
	}

/* if so, allocate the corresponding arcan- side resource */
	return request_surface(surf->client, &(struct surface_request){
			.segid = SEGID_BRIDGE_X11,
			.target = res,
			.trace = "xwl",
			.dispatch = xwl_defer_handler,
			.client = surf->client,
			.source = surf,
			.tag = wnd
	}, 'X');
}
