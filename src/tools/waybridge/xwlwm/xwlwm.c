/*
 * Copyright 2018-2019, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: https://github.com/letoram/arcan/wiki/wayland.md
 * Description: XWayland specific 'Window Manager' that deals with the special
 * considerations needed for pairing XWayland redirected windows with wayland
 * surfaces etc. Decoupled from the normal XWayland so that both sides can be
 * sandboxed better and possibly used for a similar -rootless mode in Xarcan.
 *
 * Points:
 *  override_redirect : if set, don't focus window
 *
 * Todo:
 * [ ] Basic bringup still, particularly popups, XEmbed etc.
 *
 * [ ] Clipboard could/should be done with us inheriting an arcan segment
 *     that is setup for clipboard, then we connect our clipboard manager
 *     to the xserver and go at it like that, don't need to involve wayland.
 */
#define _GNU_SOURCE
#include <arcan_shmif.h>
#include <inttypes.h>
#include <errno.h>
#include <signal.h>
#include <stdarg.h>

/* #include <X11/XCursor/XCursor.h> */
#include <xcb/xcb.h>
#include <xcb/composite.h>
#include <xcb/xfixes.h>
#include <xcb/xcb_event.h>
#include <xcb/xcb_icccm.h>
#include <pthread.h>

/*
 * should we need to map window-id to struct
#include "hash.h"
static struct hash_table known_windows;
 */

static xcb_connection_t* dpy;
static xcb_screen_t* screen;
static xcb_drawable_t root;
static xcb_drawable_t wnd;
static xcb_colormap_t colormap;
static xcb_visualid_t visual;
static int64_t input_grab = -1;
static int64_t input_focus = -1;
static volatile bool alive = true;
static bool xwm_standalone = false;

#include "atoms.h"

#define WM_FLUSH true
#define WM_APPEND false

/*
 * struct window, malloc, set id, HASH_ADD_INT(windows, id, new)
 * HASH_FIND_INT( users, &id, outptr)
 * HASH_DEL(windows, outptr)
 */

static void on_chld(int num)
{
	alive = false;
}

static inline void trace(const char* msg, ...)
{
#ifdef _DEBUG
	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
		fprintf(stderr, "\n");
	va_end( args);
	fflush(stderr);
#endif
}

static inline void wm_command(bool flush, const char* msg, ...)
{
	va_list args;
	va_start(args, msg);
	vfprintf(stdout, msg, args);
	va_end(args);

	if (!msg || flush){
		fputc((int) '\n', stdout);
	}

	if (flush){
		fflush(stdout);
	}
}

static void scan_atoms()
{
	for (size_t i = 0; i < ATOM_LAST; i++){
		xcb_intern_atom_cookie_t cookie =
			xcb_intern_atom(dpy, 0, strlen(atom_map[i]), atom_map[i]);

		xcb_generic_error_t* error;
		xcb_intern_atom_reply_t* reply =
			xcb_intern_atom_reply(dpy, cookie, &error);
		if (reply && !error){
			atoms[i] = reply->atom;
		}
		if (error){
			trace("atom (%s) failed with code (%d)\n", atom_map[i], error->error_code);
			free(error);
		}
		free(reply);
	}

/* do we need to add xfixes here? */
}

static bool setup_visuals()
{
	xcb_depth_iterator_t depth =
		xcb_screen_allowed_depths_iterator(screen);

	while(depth.rem > 0){
		if (depth.data->depth == 32){
			visual = (xcb_depth_visuals_iterator(depth.data).data)->visual_id;
			colormap = xcb_generate_id(dpy);
			xcb_create_colormap(dpy, XCB_COLORMAP_ALLOC_NONE, colormap, root, visual);
			return true;
		}
		xcb_depth_next(&depth);
	}

	return false;
}

static void create_window()
{
	wnd = xcb_generate_id(dpy);
	xcb_create_window(dpy,
		XCB_COPY_FROM_PARENT, wnd, root,
		0, 0, 10, 10, 0, XCB_WINDOW_CLASS_INPUT_OUTPUT,
		visual, 0, NULL
	);
	xcb_change_property(dpy,
		XCB_PROP_MODE_REPLACE, wnd,
		atoms[NET_SUPPORTING_WM_CHECK], XCB_ATOM_WINDOW, 32, 1, &wnd);
/* wm name, utf8 string
 * supporting wm, selection_owner, ... */
}

static bool has_atom(
	xcb_get_property_reply_t* prop, enum atom_names atom)
{
	if (prop == NULL || xcb_get_property_value_length(prop) == 0)
		return false;

	xcb_atom_t* atom_query = xcb_get_property_value(prop);
	if (!atom_query){
		return false;
	}

	size_t count = xcb_get_property_value_length(prop) / (prop->format / 8);
	for (size_t i = 0; i < count; i++){
		if (atom_query[i] == atoms[atom]){
			return true;
		}
	}

	return false;
}

static bool check_window_support(xcb_window_t wnd, xcb_atom_t atom)
{
	xcb_get_property_cookie_t cookie =
		xcb_icccm_get_wm_protocols(dpy, wnd, atoms[WM_PROTOCOLS]);
	xcb_icccm_get_wm_protocols_reply_t protocols;

	if (xcb_icccm_get_wm_protocols_reply(dpy, cookie, &protocols, NULL) == 1){
		for (size_t i = 0; i < protocols.atoms_len; i++){
			if (protocols.atoms[i] == atom){
				xcb_icccm_get_wm_protocols_reply_wipe(&protocols);
				return true;
			}
		}
	}

	xcb_icccm_get_wm_protocols_reply_wipe(&protocols);
	return false;
}

static const char* check_window_state(uint32_t id)
{
	xcb_get_property_cookie_t cookie = xcb_get_property(
		dpy, 0, id, atoms[NET_WM_WINDOW_TYPE], XCB_ATOM_ANY, 0, 2048);
	xcb_get_property_reply_t* reply = xcb_get_property_reply(dpy, cookie, NULL);

/* couldn't find out more, just map it and hope */
	bool popup = false, dnd = false, menu = false, notification = false;
	bool splash = false, tooltip = false, utility = false, dropdown = false;

	if (!reply){
		trace("no reply on window type atom\n");
		return "unknown";
	}

	popup = has_atom(reply, NET_WM_WINDOW_TYPE_POPUP_MENU);
	dnd = has_atom(reply, NET_WM_WINDOW_TYPE_DND);
	dropdown = has_atom(reply, NET_WM_WINDOW_TYPE_DROPDOWN_MENU);
	menu  = has_atom(reply, NET_WM_WINDOW_TYPE_MENU);
	notification = has_atom(reply, NET_WM_WINDOW_TYPE_NOTIFICATION);
	splash = has_atom(reply, NET_WM_WINDOW_TYPE_SPLASH);
	tooltip = has_atom(reply, NET_WM_WINDOW_TYPE_TOOLTIP);
	utility = has_atom(reply, NET_WM_WINDOW_TYPE_UTILITY);
	free(reply);

	trace("wnd-state:%"PRIu32",popup=%d,menu=%d,dnd=%d,dropdown=%d,"
		"notification=%d,splash=%d,tooltip=%d,utility=%d", id, popup, dnd,
		dropdown, menu, notification, splash, tooltip, utility
	);

/* just string- translate and leave for higher layers to deal with */
	if (popup)
		return "popup";
	else if (dnd)
		return "dnd";
	else if (dropdown)
		return "dropdown";
	else if (menu)
		return "menu";
	else if (notification)
		return "notification";
	else if (splash)
		return "splash";
	else if (tooltip)
		return "tooltip";
	else if (utility)
		return "utility";

	return "default";
}

static void send_updated_window(
	const char* kind, uint32_t id, int32_t x, int32_t y, bool no_coord)
{
/*
 * metainformation about the window to better select a type and behavior.
 *
 * _NET_WM_WINDOW_TYPE replaces MOTIF_WM_HINTS so we much prefer that as it
 * maps to the segment type.
 */
	wm_command(WM_APPEND,
		"kind=%s:id=%"PRIu32":type=%s", kind, id, check_window_state(id));

	xcb_get_property_cookie_t cookie = xcb_get_property(dpy,
		0, id, XCB_ATOM_WM_TRANSIENT_FOR, XCB_ATOM_WINDOW, 0, 2048);
	xcb_get_property_reply_t* reply = xcb_get_property_reply(dpy, cookie, NULL);

	if (reply){
		xcb_window_t* pwd = xcb_get_property_value(reply);
		wm_command(WM_APPEND, ":parent=%"PRIu32, *pwd);
		free(reply);
	}

/*
 * a bunch of translation heuristics here:
 *  transient_for ? convert to parent- relative coordinates unless input
 *  if input, set toplevel and viewport parent-
 *
 * do we have a map request coordinate?
 */

/*
 * WM_HINTS :
 *  flags as feature bitmap
 *  input, initial_state, pixmap, window, position, mask, group,
 *  message, urgency
 */
	if (no_coord)
		wm_command(WM_FLUSH, NULL);
	else
		wm_command(WM_FLUSH, ":x=%"PRId32":y=%"PRId32, x, y);
}

static void xcb_create_notify(xcb_create_notify_event_t* ev)
{
	trace("create-notify:%"PRIu32, ev->window);
	if (ev->window == wnd)
		return;

	send_updated_window("create", ev->window, ev->x, ev->y, false);
}

static void xcb_map_notify(xcb_map_notify_event_t* ev)
{
	trace("map-notify:%"PRIu32, ev->window);
/* chances are that we get mapped with different atoms being set,
 * particularly for popups used by cutebrowser etc. */
	xcb_get_property_cookie_t cookie = xcb_get_property(dpy,
		0, ev->window, XCB_ATOM_WM_TRANSIENT_FOR, XCB_ATOM_WINDOW, 0, 2048);
	xcb_get_property_reply_t* reply = xcb_get_property_reply(dpy, cookie, NULL);

	if (reply){
		xcb_window_t* pwd = xcb_get_property_value(reply);
		wm_command(WM_FLUSH,
			"kind=parent:id=%"PRIu32":parent_id=%"PRIu32, ev->window, *pwd);
		free(reply);
	}

/*
	if (-1 == input_focus){
		input_focus = ev->window;
		xcb_set_input_focus(dpy,
			XCB_INPUT_FOCUS_POINTER_ROOT, ev->window, XCB_CURRENT_TIME);
	}
 */

	send_updated_window("map", ev->window, -1, -1, true);
}

static void xcb_map_request(xcb_map_request_event_t* ev)
{
/* while the above could've made a round-trip to make sure we don't
 * race with the wayland channel, the approach of detecting surface-
 * type and checking seems to work ok (xwl.c) */
	trace("map-request:%"PRIu32, ev->window);

/* for popup- windows, we kindof need to track override-redirect here */
	xcb_configure_window(dpy, ev->window,
		XCB_CONFIG_WINDOW_STACK_MODE, (uint32_t[]){XCB_STACK_MODE_BELOW});

	xcb_map_window(dpy, ev->window);

/* ICCCM_NORMAL_STATE */
	xcb_change_property(dpy,
		XCB_PROP_MODE_REPLACE, ev->window, atoms[WM_STATE],
		atoms[WM_STATE], 32, 2, (uint32_t[]){1, XCB_WINDOW_NONE});
}

static void xcb_reparent_notify(xcb_reparent_notify_event_t* ev)
{
	trace("reparent: %"PRIu32" new parent: %"PRIu32"%s",
		ev->window, ev->parent, ev->override_redirect ? " override" : "");
	if (ev->parent == root){
		wm_command(WM_FLUSH,
			"kind=reparent:parent=root,override=%d", ev->override_redirect ? 1 : 0);
	}
	else
		wm_command(WM_FLUSH,
			"kind=reparent:id=%"PRIu32":parent=%"PRIu32"%s",
			ev->window, ev->parent, ev->override_redirect ? ":override=1" : "");
}

static void xcb_unmap_notify(xcb_unmap_notify_event_t* ev)
{
	trace("unmap: %"PRIu32, ev->window);
	if (ev->window == input_focus)
		input_focus = -1;
	if (ev->window == input_grab)
		input_grab = -1;
	wm_command(WM_FLUSH, "kind=unmap:id=%"PRIu32, ev->window);
}

static void xcb_client_message(xcb_client_message_event_t* ev)
{
/*
 * switch type against resolved atoms:
 * WL_SURFACE_ID : gives wayland surface id
 *  NET_WM_STATE : (format field == 32), gives:
 *                 modal, fullscreen, maximized_vert, maximized_horiz
 * NET_ACTIVE_WINDOW: set active window on root
 * NET_WM_MOVERESIZE: set edges for move-resize window
 * PROTOCOLS: set ping-pong
 */
	if (ev->type == atoms[WL_SURFACE_ID]){
		trace("wl-surface:%"PRIu32" to %"PRIu32, ev->data.data32[0], ev->window);
		wm_command(WM_FLUSH,
			"kind=surface:id=%"PRIu32":surface_id=%"PRIu32,
			ev->window, ev->data.data32[0]
		);
	}
	else {
		trace("client-message(unhandled) %"PRIu32"->%d", ev->window, ev->type);
	}
}

static void xcb_destroy_notify(xcb_destroy_notify_event_t* ev)
{
	trace("destroy-notify:%"PRIu32, ev->window);
	if (ev->window == input_focus){
		input_focus = -1;
	}

	wm_command(WM_FLUSH, "kind=destroy:id=%"PRIu32,
		((xcb_destroy_notify_event_t*) ev)->window);
}

/*
 * ConfigureNotify :
 */
static void xcb_configure_notify(xcb_configure_notify_event_t* ev)
{
	trace("configure-notify:%"PRIu32" @%d,%d", ev->window, ev->x, ev->y);

	/* ev->x, ev->y, ev->width, ev->height, ev->override_redirect */

	wm_command(WM_FLUSH,
		"kind=configure:id=%"PRIu32":x=%d:y=%d:w=%d:h=%d",
		ev->window, ev->x, ev->y, ev->width, ev->height
	);
}

/*
 * ConfigureRequest : different client initiated a configure request
 * (i.e. could practically be the result of ourselves saying 'configure'
 */
static void xcb_configure_request(xcb_configure_request_event_t* ev)
{
	trace("configure-request:%"PRIu32", for: %d,%d+%d,%d",
			ev->window, ev->x, ev->y, ev->width, ev->height);

/* this needs to translate to _resize calls and to VIEWPORT hint events */
	wm_command(WM_FLUSH,
		"kind=configure:id=%"PRIu32":x=%d:y=%d:w=%d:h=%d",
		ev->window, ev->x, ev->y, ev->width, ev->height
	);

/* just ack the configure request for now, this should really be deferred
 * until we receive the corresponding command from our parent but we lack
 * that setup right now */

	xcb_configure_window(dpy, ev->window,
		XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y |
		XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT |
		XCB_CONFIG_WINDOW_BORDER_WIDTH,
		(uint32_t[]){ev->x, ev->y, ev->width, ev->height, 0}
	);
}

static void update_focus(int64_t id)
{
	if (-1 == id){
		xcb_set_input_focus(dpy,
			XCB_INPUT_FOCUS_POINTER_ROOT, XCB_NONE, XCB_CURRENT_TIME);
	}
	else {
		xcb_set_input_focus(dpy,
			XCB_INPUT_FOCUS_POINTER_ROOT, id, XCB_CURRENT_TIME);
	}
	xcb_flush(dpy);
}

static void xcb_focus_in(xcb_focus_in_event_t* ev)
{
	trace("focus-in: %"PRIu32, ev->event);
/*
 * Do anything with these?
	ev->mode == XCB_NOTIFY_MODE_GRAB ||
	ev->mode == XCB_NOTIFY_MODE_UNGRAB
 */

	if (-1 == input_focus || ev->event != input_focus){
		update_focus(input_focus);
	}
}

/* use stdin/popen/line based format to make debugging easier */
static void process_wm_command(const char* arg)
{
	trace("wm_command: %s", arg);
	struct arg_arr* args = arg_unpack(arg);
	if (!args)
		return;

/* all commands have kind/id */
	const char* dst;
	if (!arg_lookup(args, "id", 0, &dst)){
		fprintf(stderr, "malformed argument: %s, missing id\n", arg);
	}

	uint32_t id = strtoul(dst, NULL, 10);
	if (!arg_lookup(args, "kind", 0, &dst)){
		fprintf(stderr, "malformed argument: %s, missing kind\n", arg);
		goto cleanup;
	}

/* match to previously known window so we get the right handle */

	if (strcmp(dst, "maximized") == 0){
		trace("srv-maximize");
	}
	else if (strcmp(dst, "fullscreen") == 0){
		trace("srv-fullscreen");
	}
	else if (strcmp(dst, "resize") == 0){
		arg_lookup(args, "width", 0, &dst);
		size_t w = strtoul(dst, NULL, 10);
		arg_lookup(args, "height", 0, &dst);
		size_t h = strtoul(dst, NULL, 10);
		trace("srv-resize(%d)(%zu, %zu)", id, w, h);

		const char* state = check_window_state(id);
		if (strcmp(state, "default") == 0){
			xcb_configure_window(dpy, id,
				XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y |
				XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT |
				XCB_CONFIG_WINDOW_BORDER_WIDTH,
				(uint32_t[]){0, 0, w, h, 0}
			);
			xcb_flush(dpy);
		}
/* just don't configure popups etc. */
		else {
			trace("srv->resize(%d), ignore (popup/...) : %s", id, state);
		}
	}
	else if (strcmp(dst, "destroy") == 0){
/* check if window support WM_DELETE_WINDOW, and if so: */
		if (check_window_support(id, atoms[WM_DELETE_WINDOW])){
			trace("srv-destroy, delete_window(%d)", id);
			xcb_client_message_event_t ev = {
				.response_type = XCB_CLIENT_MESSAGE,
				.window = id,
				.type = atoms[WM_PROTOCOLS],
				.format = 32,
				.data = {
					.data32 = {atoms[WM_DELETE_WINDOW], XCB_CURRENT_TIME}
				}
			};
			xcb_send_event(dpy, false, wnd, XCB_EVENT_MASK_NO_EVENT, (char*)&ev);
			xcb_flush(dpy);
		}
		else {
			trace("srv-destroy, delete_kill(%d)", id);
			xcb_destroy_window(dpy, id);
		}
	}
	else if (strcmp(dst, "unfocus") == 0){
		trace("srv-unfocus(%d)", id);
		input_focus = -1;
		update_focus(-1);

		xcb_flush(dpy);
	}
	else if (strcmp(dst, "focus") == 0){
		trace("srv-focus(%d)", id);
		input_focus = id;
		update_focus(id);
	}

cleanup:
	arg_cleanup(args);
}

static void* process_thread(void* arg)
{
	while (!ferror(stdin) && !feof(stdin) && alive){
		char inbuf[1024];
		if (fgets(inbuf, 1024, stdin)){
/* trim */
			size_t len = strlen(inbuf);
			if (len && inbuf[len-1] == '\n')
				inbuf[len-1] = '\0';
			process_wm_command(inbuf);
		}
	}
	wm_command(WM_FLUSH, "kind=terminated");
	alive = false;
	return NULL;
}

int main (int argc, char **argv)
{
	int code;

	xcb_generic_event_t *ev;

	if (getenv("ARCAN_XWLWM_LOGOUT")){
		freopen(getenv("ARCAN_XWLWM_LOGOUT"), "w+", stderr);
	}

	if (getenv("ARCAN_XWLWM_DEBUGSTALL")){
		volatile bool sleeper = true;
		while (sleeper){}
	}

	signal(SIGCHLD, on_chld);

/* standalone mode is to test/debug the WM against an externally managed X,
 * this runs without the normal inherited/rootless setup */
	xwm_standalone = argc > 1 && strcmp(argv[1], "-standalone") == 0;
	if (xwm_standalone){
		freopen("wm.log", "w", stdout);
		argv--;
		argv = &argv[1];
		goto startx;
	}

/*
 * Now we spawn the XWayland instance with a pipe- pair so that we can read
 * when the server is ready
 */
	int notification[2];
	if (-1 == pipe(notification)){
		fprintf(stderr, "couldn't create status pipe\n");
		return EXIT_FAILURE;
	}

	pid_t xwayland = fork();
	if (0 == xwayland){
		close(notification[0]);
		char* argv[] = {"Xwayland", "-rootless", "-displayfd", NULL, NULL};
		asprintf(&argv[3], "%d", notification[1]);

/* note, we have -terminate, -noreset, -wm (fd), -eglstream (?) */
		execvp("Xwayland", argv);
		exit(EXIT_FAILURE);
	}
	else if (-1 == xwayland){
		fprintf(stderr, "couldn't fork Xwayland process\n");
		return EXIT_FAILURE;
	}

/*
 * wait for a reply from the Xwayland setup
 */
	trace("waiting for display");
	char inbuf[64] = {0};
	int rv = read(notification[0], inbuf, 63);
	if (-1 == rv){
		fprintf(stderr, "error reading from Xwayland: %s\n", strerror(errno));
		return EXIT_FAILURE;
	}

/*
 * there is some way to get a wm-fd out of xorg so that we could just connect
 * that immediately instead, but env for now
 */
	unsigned long num = strtoul(inbuf, NULL, 10);
	char dispnum[8];
	snprintf(dispnum, 8, ":%lu", num);
	setenv("DISPLAY", dispnum, 1);
	close(notification[0]);

/*
 * since we have gotten a reply, the display should be ready, just connect
 */
startx:
	dpy = xcb_connect(NULL, NULL);
	if ((code = xcb_connection_has_error(dpy))){
		fprintf(stderr, "Couldn't open display (%d)\n", code);
		return EXIT_FAILURE;
	}

	screen = xcb_setup_roots_iterator(xcb_get_setup(dpy)).data;
	root = screen->root;
	if (!setup_visuals()){
		fprintf(stderr, "Couldn't setup visuals/colormap\n");
		return EXIT_FAILURE;
	}

	scan_atoms();

/*
 * enable structure and redirection notifications so that we can forward
 * the related events onward to the active arcan window manager
 */
	create_window();

	xcb_change_window_attributes(dpy, root, XCB_CW_EVENT_MASK, (uint32_t[]){
		XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY |
		XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT |
		XCB_EVENT_MASK_PROPERTY_CHANGE, 0, 0
	});
	if (!xwm_standalone){
		xcb_composite_redirect_subwindows(
			dpy, root, XCB_COMPOSITE_REDIRECT_MANUAL);
	}
	xcb_flush(dpy);

/*
 * xcb is thread-safe, so we can have one thread for incoming
 * dispatch and another thread for outgoing dispatch
 */
	if (!xwm_standalone){
		pthread_t pth;
		pthread_attr_t pthattr;
		pthread_attr_init(&pthattr);
		pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
		pthread_create(&pth, &pthattr, process_thread, NULL);
	}

/*
 * now it should be safe to chain-execute any single client we'd want,
 * and unlink on connect should we want to avoid more clients connecting
 * to the display
 */
	if (!xwm_standalone && argc > 1){
		int rv = fork();
		if (-1 == rv){
			fprintf(stderr, "-exec (%s), couldn't fork\n", argv[1]);
			return EXIT_FAILURE;
		}
		else if (0 == rv){
/* remove the display variable, but also unlink the parent socket for the
 * normal 'default' display as some toolkits also fallback and check for it */
			const char* disp = getenv("WAYLAND_DISPLAY");
			if (!disp)
				disp = "wayland-0";

/* should be guaranteed here but just to be certain, length is at sun_path (108) */
			if (getenv("XDG_RUNTIME_DIR")){
				char path[128];
				snprintf(path, 128, "%s/%s", getenv("XDG_RUNTIME_DIR"), disp);
				unlink(path);
			}

			unsetenv("WAYLAND_DISPLAY");
			execvp(argv[1], &argv[1]);
			return EXIT_FAILURE;
		}
		else {
		}
	}

/* atom lookup:
 * moveresize, state, fullscreen, maximized vert, maximized horiz, active window
 */
	while( (ev = xcb_wait_for_event(dpy)) && alive){
		if (ev->response_type == 0){
			continue;
		}

		switch (ev->response_type & ~0x80) {
/* the following are mostly relevant for "UI" events if the decorations are
 * implemented in the context of X rather than at a higher level. Since this
 * doesn't really apply to us, these can be ignored */
		case XCB_BUTTON_PRESS:
			trace("button-press");
		break;
		case XCB_MOTION_NOTIFY:
			trace("motion-notify");
		break;
		case XCB_BUTTON_RELEASE:
			trace("button-release");
		break;
		case XCB_ENTER_NOTIFY:
			trace("enter-notify");
		break;
		case XCB_LEAVE_NOTIFY:
			trace("leave-notify\n");
		break;
/*
 * end of 'UI notifications'
 */
		case XCB_CREATE_NOTIFY:
			xcb_create_notify((xcb_create_notify_event_t*) ev);
		break;
		case XCB_MAP_REQUEST:
			xcb_map_request((xcb_map_request_event_t*) ev);
		break;
    case XCB_MAP_NOTIFY:
			xcb_map_notify((xcb_map_notify_event_t*) ev);
		break;
    case XCB_UNMAP_NOTIFY:
			xcb_unmap_notify((xcb_unmap_notify_event_t*) ev);
		break;
    case XCB_REPARENT_NOTIFY:
			xcb_reparent_notify((xcb_reparent_notify_event_t*) ev);
		break;
    case XCB_CONFIGURE_REQUEST:
			xcb_configure_request((xcb_configure_request_event_t*) ev);
		break;
    case XCB_CONFIGURE_NOTIFY:
			xcb_configure_notify((xcb_configure_notify_event_t*) ev);
		break;
		case XCB_DESTROY_NOTIFY:
			xcb_destroy_notify((xcb_destroy_notify_event_t*) ev);
		break;
	/* keyboards / pointer / notifications, not interesting here
	 * unless going for some hotkey etc. kind of a thing */
		case XCB_MAPPING_NOTIFY:
			trace("mapping-notify");
		break;
		case XCB_PROPERTY_NOTIFY:
			trace("property-notify");
		break;
		case XCB_CLIENT_MESSAGE:
			xcb_client_message((xcb_client_message_event_t*) ev);
		break;
		case XCB_FOCUS_IN:
			xcb_focus_in((xcb_focus_in_event_t*) ev);
		break;
		default:
			trace("unhandled: %"PRIu8, ev->response_type);
		break;
		}
		xcb_flush(dpy);
	}

return 0;
}
