/*
 * Copyright 2018-2020, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: https://github.com/letoram/arcan/wiki/wayland.md
 * Description: XWayland specific 'Window Manager' that deals with the special
 * considerations needed for pairing XWayland redirected windows with wayland
 * surfaces etc. Decoupled from the normal XWayland so that both sides can be
 * sandboxed better and possibly used for a similar -rootless mode in Xarcan.
 */
#include "../../shmif/arcan_shmif.h"
#include "../../shmif/arcan_shmif_debugif.h"
#include <inttypes.h>
#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <poll.h>

/* #include <X11/XCursor/XCursor.h> */
#include <xcb/xcb.h>
#include <xcb/composite.h>
#include <xcb/xfixes.h>
#include <xcb/xcb_event.h>
#include <xcb/xcb_icccm.h>
#include <pthread.h>

#include "../uthash.h"

static pthread_mutex_t logout_synch = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t wm_synch = PTHREAD_MUTEX_INITIALIZER;

struct xwnd_state {
	bool mapped;
	bool paired;
	bool override_redirect;
	bool fullscreen;
	int x, y;
	int w, h;
	int id;
	char* title;
	UT_hash_handle hh;
};
static struct xwnd_state* windows;

static int signal_fd = -1;
static xcb_connection_t* dpy;
static xcb_screen_t* screen;
static xcb_drawable_t wnd_root;
static xcb_drawable_t wnd_wm;
static xcb_drawable_t wnd_sel;
static xcb_colormap_t colormap;
static xcb_visualid_t visual;
static int64_t input_grab = XCB_WINDOW_NONE;
static int64_t input_focus = XCB_WINDOW_NONE;
static bool xwm_standalone = false;

#include "atoms.h"

#define WM_FLUSH true
#define WM_APPEND false

static void on_chld(int num)
{
	uint8_t ch = 'x';
	write(signal_fd, &ch, 1);
}

static void on_dbgreq(int num)
{
	uint8_t ch = 'd';
	write(signal_fd, &ch, 1);
}

static inline void trace(const char* msg, ...)
{
	FILE* dst = stdout;

	va_list args;
	va_start( args, msg );
		vfprintf(dst,  msg, args );
		fputc((int) '\n', dst);
	va_end( args);
}

#ifdef _DEBUG
#define TRACE_PREFIX "kind=trace:"
#define trace(Y, ...) do { \
	pthread_mutex_lock(&logout_synch); \
	trace("%sts=%lld:" Y, TRACE_PREFIX, arcan_timemillis(), ##__VA_ARGS__);\
	pthread_mutex_unlock(&logout_synch); \
} while (0)
#else
#define TRACE_PREFIX ""
#define trace(Y, ...) do { } while (0)
#endif

static bool is_wm_window(xcb_drawable_t id)
{
	return id == wnd_wm || id == wnd_root || id == wnd_sel;
}

static inline void wm_command(bool flush, const char* msg, ...)
{
	va_list args;
	va_start(args, msg);
	static bool in_lock;

	if (!in_lock){
		pthread_mutex_lock(&logout_synch);
		in_lock = true;
	}

	vfprintf(stdout, msg, args);
	va_end(args);

	if (!msg || flush){
		fputc((int) '\n', stdout);
	}

	if (flush){
		in_lock = false;
		pthread_mutex_unlock(&logout_synch);
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
			trace("atom (%s) failed with code (%d)", atom_map[i], error->error_code);
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
			xcb_create_colormap(dpy, XCB_COLORMAP_ALLOC_NONE, colormap, wnd_root, visual);
			return true;
		}
		xcb_depth_next(&depth);
	}

	return false;
}

static void update_title(struct xwnd_state* state)
{
	xcb_get_property_cookie_t cookie = xcb_get_property(
		dpy, 0, state->id, atoms[NET_WM_NAME], XCB_ATOM_ANY, 0, 2048);
	xcb_get_property_reply_t* reply = xcb_get_property_reply(dpy, cookie, NULL);

	if (!reply)
		return;

	if (reply->type != atoms[UTF8_STRING]){
		trace("title:unsupported_type");
		goto out;
	}

	size_t len = xcb_get_property_value_length(reply);
	char* title = xcb_get_property_value(reply);
	if (!title || !len)
		goto out;

	char* scratch = strndup(title, len);
	if (!scratch)
		goto out;

/* treat as non-0 terminated */
	if (!state->title || strcmp(state->title, scratch) != 0){
		free(state->title);
		state->title = scratch;
		trace("title=%s", scratch);
	}
	else
		free(scratch);

out:
	free(reply);
}

static void xcb_property_notify(xcb_property_notify_event_t* ev)
{
	trace("xcb=property-notify");
	struct xwnd_state* state = NULL;

/* intended for our clipboard? */
	if (ev->window == wnd_sel){
/* NEW_VALUE */
	}

	HASH_FIND_INT(windows,&ev->window,state);
	if (!state)
		return;

	if (ev->atom != atoms[NET_WM_NAME])
		return;

	update_title(state);
}

static void update_focus(int64_t id)
{
	struct xwnd_state* state = NULL;

	if (id != XCB_WINDOW_NONE)
		HASH_FIND_INT(windows,&id,state);

	input_focus = id;
	if (!state){
		xcb_set_input_focus_checked(dpy,
			XCB_INPUT_FOCUS_POINTER_ROOT, XCB_NONE, XCB_TIME_CURRENT_TIME);
		trace("focus-none");
	}
	else {
		if (state->override_redirect){
			trace("ignore-redirect");
			return;
		}

		trace("focus-to:id=%"PRId64, id);
		xcb_client_message_event_t msg = (xcb_client_message_event_t){
			.response_type = XCB_CLIENT_MESSAGE,
			.format = 32,
			.window = id,
			.type = atoms[WM_PROTOCOLS],
			.data.data32[0] = atoms[WM_TAKE_FOCUS],
			.data.data32[1] = XCB_TIME_CURRENT_TIME
		};

		xcb_send_event(dpy, 0, id, XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT, (char*)&msg);
		xcb_set_input_focus(dpy,
			XCB_INPUT_FOCUS_POINTER_ROOT, id, XCB_TIME_CURRENT_TIME);
		xcb_configure_window(dpy, id,
			XCB_CONFIG_WINDOW_STACK_MODE, (uint32_t[]){XCB_STACK_MODE_ABOVE, 0});
	}

	xcb_change_property(dpy, XCB_PROP_MODE_REPLACE,
		wnd_root, atoms[NET_ACTIVE_WINDOW], atoms[WINDOW], 32, 1, &input_focus);
}

static void create_window()
{
	wnd_wm = xcb_generate_id(dpy);
	xcb_create_window(dpy,
		XCB_COPY_FROM_PARENT, wnd_wm, wnd_root,
		0, 0, 10, 10, 0, XCB_WINDOW_CLASS_INPUT_OUTPUT,
		visual, 0, NULL
	);
/* should visual be here? */

	xcb_change_property(dpy,
		XCB_PROP_MODE_REPLACE, wnd_wm,
		atoms[NET_SUPPORTING_WM_CHECK], XCB_ATOM_WINDOW, 32, 1, &wnd_wm);

	static const char wmname[] = "Arcan XWM";
	xcb_change_property(dpy,
		XCB_PROP_MODE_REPLACE, wnd_wm,
		atoms[NET_WM_NAME], atoms[UTF8_STRING], 8, strlen(wmname), wmname);

	xcb_change_property(dpy,
		XCB_PROP_MODE_REPLACE, wnd_wm,
		atoms[NET_SUPPORTING_WM_CHECK], XCB_ATOM_WINDOW, 32, 1, &wnd_root);

/* for clipboard forwarding */
	xcb_set_selection_owner(dpy,
		wnd_wm, atoms[WM_S0], XCB_TIME_CURRENT_TIME);

	xcb_set_selection_owner(dpy,
		wnd_wm, atoms[NET_WM_CM_S0], XCB_TIME_CURRENT_TIME);

	wnd_sel = xcb_generate_id(dpy);
	xcb_create_window(dpy,
		XCB_COPY_FROM_PARENT, wnd_sel, wnd_root,
		0, 0, 12, 12, 0, XCB_WINDOW_CLASS_INPUT_OUTPUT,
		visual, XCB_CW_EVENT_MASK,
		(uint32_t[]){XCB_EVENT_MASK_PROPERTY_CHANGE}
	);
	xcb_set_selection_owner(dpy, wnd_sel, atoms[CLIPBOARD], XCB_TIME_CURRENT_TIME);
/*
 * xcb_xfixes_select_selection_input(dpy, wnd_sel, atoms[CLIPBOARD],
		XCB_XFIXES_SELECTION_EVENT_MASK_SET_SELECTION_OWNER |
		XCB_XFIXES_SELECTION_EVENT_MASK_SELECTION_WINDOW_DESTROY |
		XCB_XFIXES_SELECTION_EVENT_MASK_SELECTION_CLIENT_CLOSE
	);
 */
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

static void send_configure_notify(uint32_t id)
{
	struct xwnd_state* state;
	HASH_FIND_INT(windows,&id,state);
	if (!state)
		return;

/* so a number of games have different behavior for 'fullscreen', where
 * an older form of this is using the x/y of the output and the dimensions
 * of the window */

	xcb_configure_notify_event_t notify = (xcb_configure_notify_event_t){
		.response_type = XCB_CONFIGURE_NOTIFY,
		.event = id,
		.window = id,
		.above_sibling = XCB_WINDOW_NONE,
		.x = state->x,
		.y = state->y,
		.width = state->w,
		.height = state->h
	};
	xcb_send_event(dpy, 0, id, XCB_EVENT_MASK_STRUCTURE_NOTIFY, (char*)&notify);
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
		trace("no reply on window type atom");
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

/*
 * trace("wnd-state:%"PRIu32",popup=%d,menu=%d,dnd=%d,dropdown=%d,"
		"notification=%d,splash=%d,tooltip=%d,utility=%d:fullscreen=%d",
		id, popup, menu, dnd, dropdown, notification, splash,
		tooltip, utility, fullscreen
	);
*/

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

static void send_updated_window(struct xwnd_state* wnd, const char* kind)
{
/* defer update information until we have something mapped, otherwise we can
 * get one update where the type is generic, then immediately one that is popup
 * etc. making life more difficult for the arcan wm side */
/*
 * metainformation about the window to better select a type and behavior.
 *
 * _NET_WM_WINDOW_TYPE replaces MOTIF_wm_HINTS so we much prefer that as it
 * maps to the segment type.
 */
	trace("update_window=%s:x=%"PRId32":y=%"PRId32":w=%"PRId32":y=%"PRId32,
		kind, wnd->x, wnd->y, wnd->w, wnd->h);

	xcb_get_property_cookie_t cookie = xcb_get_property(dpy,
		0, wnd->id, XCB_ATOM_WM_TRANSIENT_FOR, XCB_ATOM_WINDOW, 0, 2048);
	xcb_get_property_reply_t* reply = xcb_get_property_reply(dpy, cookie, NULL);

	if (reply){
		xcb_window_t* pwd = xcb_get_property_value(reply);
		wm_command(WM_FLUSH,
			"kind=%s:id=%"PRIu32":type=%s:x=%"PRId32":y=%"PRId32":parent_id=%"PRIu32,
			kind, wnd->id, check_window_state(wnd->id), wnd->x, wnd->y, *pwd
		);
		free(reply);
	}
	else
		wm_command(WM_FLUSH,
			"kind=%s:id=%"PRIu32":type=%s:x=%"PRId32":y=%"PRId32":w=%"PRId32":h=%"PRId32,
			kind, wnd->id, check_window_state(wnd->id), wnd->x, wnd->y, wnd->w, wnd->h
		);

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
}

static void xcb_create_notify(xcb_create_notify_event_t* ev)
{
	trace("xcb=create-notify:%"PRIu32, ev->window);

/* if we add other wm- managed windows (selection, dnd),
 * these should be filtered out here as well */
	if (is_wm_window(ev->window))
		return;

	struct xwnd_state* state = malloc(sizeof(struct xwnd_state));
	*state = (struct xwnd_state){
		.id = ev->window,
		.x = ev->x,
		.y = ev->y,
		.w = ev->width,
		.h = ev->height,
		.override_redirect = ev->override_redirect
	};
	HASH_ADD_INT(windows, id, state);

/* other properties, request geometry and check if depth is alpha or not */

	send_updated_window(state, "create");

/*
	xcb_configure_window(dpy, ev->window,
		XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y |
		XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT |
		XCB_CONFIG_WINDOW_BORDER_WIDTH,
		(uint32_t[]){ev->x, ev->y, ev->width, ev->height, 0}
	);
*/
}

static void xcb_map_notify(xcb_map_notify_event_t* ev)
{
	trace("xcb=map-notify:%"PRIu32, ev->window);

/*
	xcb_get_property_cookie_t cookie = xcb_get_property(dpy,
		0, ev->window, XCB_ATOM_WM_TRANSIENT_FOR, XCB_ATOM_WINDOW, 0, 2048);
	xcb_get_property_reply_t* reply = xcb_get_property_reply(dpy, cookie, NULL);

	if (reply){
		xcb_window_t* pwd = xcb_get_property_value(reply);
		wm_command(WM_FLUSH,
			"kind=parent:id=%"PRIu32":parent_id=%"PRIu32, ev->window, *pwd);
		free(reply);
	}
 */

/*
	if (XCB_WINDOW_NONE == input_focus){
		update_focus(ev->window);
	}
 */

	struct xwnd_state* state;
	HASH_FIND_INT(windows,&ev->window,state);

	if (state){
		state->mapped = true;
		update_title(state);
		send_updated_window(state, "map");
	}
}

static void xcb_map_request(xcb_map_request_event_t* ev)
{
/* while the above could've made a round-trip to make sure we don't
 * race with the wayland channel, the approach of detecting surface-
 * type and checking seems to work ok (xwl.c) */
	trace("xcb=map-request:%"PRIu32, ev->window);

	struct xwnd_state* state;
	HASH_FIND_INT(windows,&ev->window,state);

/* ICCCM_NORMAL_STATE */
	xcb_change_property(dpy,
		XCB_PROP_MODE_REPLACE, ev->window, atoms[WM_STATE],
		atoms[WM_STATE], 32, 2, (uint32_t[]){1, XCB_WINDOW_NONE});

/* this > should < cause the RealizeWindow -> send client message path
 * in Xwayland that has caused so much trouble */
	xcb_map_window(dpy, ev->window);
}

static void xcb_reparent_notify(xcb_reparent_notify_event_t* ev)
{
	trace("xcb=reparent:=id%"PRIu32":parent=%"PRIu32":mode=%s",
		ev->window, ev->parent, ev->override_redirect ? " override" : "normal");
	if (ev->parent == wnd_root){
		wm_command(WM_FLUSH,
			"kind=reparent:parent=root:override=%d", ev->override_redirect ? 1 : 0);
	}
	else
		wm_command(WM_FLUSH,
			"kind=reparent:id=%"PRIu32":parent_id=%"PRIu32"%s",
			ev->window, ev->parent, ev->override_redirect ? ":override=1" : "");
}

static void xcb_unmap_notify(xcb_unmap_notify_event_t* ev)
{
	trace("xcb=unmap:id=%"PRIu32, ev->window);
	if (ev->window == input_focus)
		input_focus = -1;
	if (ev->window == input_grab)
		input_grab = -1;
	wm_command(WM_FLUSH, "kind=unmap:id=%"PRIu32, ev->window);
}

static void xcb_client_message(xcb_client_message_event_t* ev)
{
	trace("xcb=client-message:id=%"PRIu32":type=%d", ev->window, ev->type);
/*
 * switch type against resolved atoms:
 *  NET_WM_STATE : (format field == 32), gives:
 *                 modal, fullscreen, maximized_vert, maximized_horiz
 * NET_ACTIVE_WINDOW: set active window on root
 * NET_WM_MOVERESIZE: set edges for move-resize window
 * PROTOCOLS: set ping-pong
 */
	struct xwnd_state* state;
	HASH_FIND_INT(windows,&ev->window,state);

/* WL_SURFACE_ID : gives wayland surface id */
	if (ev->type == atoms[WL_SURFACE_ID]){
		trace("wl-surface:%"PRIu32" to %"PRIu32, ev->data.data32[0], ev->window);
		wm_command(WM_FLUSH,
			"kind=surface:id=%"PRIu32":surface_id=%"PRIu32,
			ev->window, ev->data.data32[0]
		);

		if (state){
			state->paired = true;
			send_updated_window(state, "map");
		}
	}
/* NET_WM_STATE:
 * data32[0] : action (remove:0, add:1, toggle:2)
 * [1,2] property (NET_WM_STATE_ MODAL, FULLSCREEN, MAXIMIZED_VERT, MAXIMIZED_HORIZ) */
	else if (ev->type == atoms[NET_WM_STATE] && state){
		if (ev->data.data32[1] == atoms[NET_WM_STATE_FULLSCREEN] ||
			ev->data.data32[2] == atoms[NET_WM_STATE_FULLSCREEN]){
			if (ev->data.data32[0] == 0){
				state->fullscreen = false;
			}
			else if (ev->data.data32[0] == 1){
				state->fullscreen = true;
			}
			else {
				state->fullscreen = !state->fullscreen;
			}
			wm_command(WM_FLUSH,
				"kind=fullscreen:state=%s:id=%"PRIu32,
				state->fullscreen ? "on" : "off", ev->window);

		}
	}
	else {
		trace("client-message(unhandled) %"PRIu32"->%d", ev->window, ev->type);
	}
}

static void xcb_destroy_notify(xcb_destroy_notify_event_t* ev)
{
	trace("xcb=destroy-notify:id=%"PRIu32, ev->window);
	if (ev->window == input_focus){
		input_focus = -1;
	}

	struct xwnd_state* state;
	HASH_FIND_INT(windows,&ev->window,state);

	if (state){
		HASH_DEL(windows, state);
		free(state->title);
	}

	size_t count = HASH_COUNT(windows);
	wm_command(WM_FLUSH, "kind=destroy:left=%zu:id=%"PRIu32,
		count, ((xcb_destroy_notify_event_t*) ev)->window);
}

/*
 * ConfigureNotify :
 */
static void xcb_configure_notify(xcb_configure_notify_event_t* ev)
{
	trace("xcb=configure-notify:id=%"PRIu32":x=%d:y=%d:w=%d:h=%d",
		ev->window, ev->x, ev->y, ev->width, ev->height);

	struct xwnd_state* state;
	HASH_FIND_INT(windows,&ev->window,state);
	if (!state)
		return;

	state->mapped = true;
	state->x = ev->x;
	state->y = ev->y;
	state->w = ev->width;
	state->h = ev->height;
	state->override_redirect = ev->override_redirect;

/* override redirect? use width / height */

	if (state->mapped && state->paired){
		wm_command(WM_FLUSH,
		"kind=configure:id=%"PRIu32":x=%d:y=%d:w=%d:h=%d",
		ev->window, ev->x, ev->y, ev->width, ev->height);
	}
}

/*
 * ConfigureRequest : different client initiated a configure request
 * (i.e. could practically be the result of ourselves saying 'configure'
 */
static void xcb_configure_request(xcb_configure_request_event_t* ev)
{
	trace("xcb=configure-request:id=%"PRIu32":x=%d:y=%d:w=%d:d=%d",
			ev->window, ev->x, ev->y, ev->width, ev->height);

	struct xwnd_state* state;
	HASH_FIND_INT(windows,&ev->window,state);
	if (!state){
		trace("status=error:unknown_window:id=%d", ev->window);
		return;
	}

/* this needs to translate to _resize calls and to VIEWPORT hint events */
	wm_command(WM_FLUSH,
		"kind=configure:id=%"PRIu32":x=%d:y=%d:w=%d:h=%d",
		ev->window, ev->x, ev->y, ev->width, ev->height
	);

	if (ev->width)
		state->w = ev->width;

	if (ev->height)
		state->h = ev->height;

	if (state->fullscreen){
		send_configure_notify(ev->window);
		return;
	}

	int mask =
		XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y |
		XCB_CONFIG_WINDOW_BORDER_WIDTH;

/* just some kind of default, we don't have any forwarding of 'next window size'
 * at the moment as the arcan appl doesn't have a communication path for i */
	int w = 0;
	int h = 0;
	if (ev->value_mask & XCB_CONFIG_WINDOW_WIDTH){
		w = ev->width;
		mask |= XCB_CONFIG_WINDOW_WIDTH;
	}

	if (ev->value_mask & XCB_CONFIG_WINDOW_HEIGHT){
		h = ev->height;
		mask |= XCB_CONFIG_WINDOW_HEIGHT;
	}

	uint32_t values[8] = {
		ev->x,
		ev->y,
		w,
		h
	};
	int pos = 5;

	if (ev->value_mask & XCB_CONFIG_WINDOW_SIBLING){
		values[pos++] = ev->sibling;
		mask |= XCB_CONFIG_WINDOW_SIBLING;
	}

	if (ev->value_mask & XCB_CONFIG_WINDOW_STACK_MODE){
		values[pos++] = ev->stack_mode;
		mask |= XCB_CONFIG_WINDOW_STACK_MODE;
	}

/* just ack the configure request for now, this should really be deferred
 * until we receive the corresponding command from our parent but we lack
 * that setup right now */
	xcb_configure_window(dpy, ev->window, mask, values);
}

static void xcb_focus_in(xcb_focus_in_event_t* ev)
{
	if (ev->mode == XCB_NOTIFY_MODE_GRAB ||
		ev->mode == XCB_NOTIFY_MODE_UNGRAB){
		trace("kind=focus-in:status=grab-ignore:id=%"PRIu32, ev->event);
		return;
	}
	trace("kind=focus-in:id=%"PRIu32, ev->event);

/* this is more troublesome than it seems, so this is a notification that
 * something got focus. This might not reflect the focus status in the real WM,
 * so right now we just say nope, you don't get to chose focus and force-back
 * the old one - otoh some applications do like to hand over focus between its
 * windows as possible keybindings, ... and there it might be highly desired */
	if (XCB_WINDOW_NONE == input_focus){ /* || ev->event != input_focus){ */
		update_focus(input_focus);
	}
}

/* use stdin/popen/line based format to make debugging easier */
static void process_wm_command(const char* arg)
{
	trace("wm_command=%s", arg);
	struct arg_arr* args = arg_unpack(arg);
	if (!args)
		return;

/* all commands have kind/id */
	const char* idstr;
	if (!arg_lookup(args, "id", 0, &idstr) || !idstr){
		trace("wm_error=bad_argument:message=missing/empty id");
		goto cleanup;
	}

/* and they should be present in the wnd table */
	struct xwnd_state* state = NULL;
	uint32_t id = strtoul(idstr, NULL, 10);
	HASH_FIND_INT(windows,&id,state);
	if (!state){
		trace("wm_error=bad_wnd_id=%s", idstr);
		goto cleanup;
	}

	const char* dst;
	if (!arg_lookup(args, "kind", 0, &dst) || !dst){
		trace("wm_error=bad_argument:message=missing/empty kind");
		goto cleanup;
	}

	if (strcmp(dst, "maximized") == 0){
		trace("wm=srv-maximize:id=%s", idstr);
	}
	else if (strcmp(dst, "fullscreen") == 0){
		trace("wm=srv-fullscreen:id=%s", idstr);
		state->fullscreen = !state->fullscreen;
	}
	else if (strcmp(dst, "resize") == 0){
		if (!arg_lookup(args, "width", 0, &dst) || !dst){
			trace("wm_error=bad_argument:message=resize missing width");
			goto cleanup;
		}
		size_t w = strtoul(dst, NULL, 10);

		if (!arg_lookup(args, "height", 0, &dst) || !dst){
			trace("wm_error=bad_argument:message=resize missing height");
			goto cleanup;
		}
		size_t h = strtoul(dst, NULL, 10);
		trace("wm=srv-resize:id=%s:width=%zu:height=%zu", idstr, w, h);
		state->w = w;
		state->h = h;
		const char* wtype = check_window_state(id);
		if (strcmp(wtype, "default") == 0){
			xcb_configure_window(dpy, id,
				XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y |
				XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT |
				XCB_CONFIG_WINDOW_BORDER_WIDTH,
				(uint32_t[]){state->x, state->y, w, h, 0}
			);
		}
/* just don't configure popups etc. */
		else {
			trace("wm=srv-resize:id=%s:wtype=%s:ignored=true", idstr, wtype);
		}
	}
/* absolute positioned window position need to be synched */
	else if (strcmp(dst, "move") == 0){
		arg_lookup(args, "x", 0, &dst);
		ssize_t x = strtol(dst, NULL, 10);
		arg_lookup(args, "y", 0, &dst);
		ssize_t y = strtol(dst, NULL, 10);
		trace("srv-move(%d)(%zd, %zd)", id, x, y);
		state->x = x;
		state->y = y;
		xcb_configure_window(dpy, id,
			XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y,
			(uint32_t[]){x, y, 0, 0, 0}
		);
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
			xcb_send_event(dpy, false, wnd_wm, XCB_EVENT_MASK_NO_EVENT, (char*)&ev);
		}
		else {
/* if it is the last one currently active, disconnect the client */
			trace("srv-destroy, delete_kill(%d)", id);
			if (HASH_COUNT(windows) == 1){
				xcb_kill_client(dpy, id);
			}
			else
				xcb_destroy_window(dpy, id);
		}
	}
	else if (strcmp(dst, "unfocus") == 0){
		if (input_focus == id){
			trace("srv-unfocus(%d)", id);
			update_focus(-1);
		}
	}
	else if (strcmp(dst, "focus") == 0){
		struct xwnd_state* state = NULL;
		HASH_FIND_INT(windows,&id,state);

		if (state && state->override_redirect)
			goto cleanup;

		trace("srv-focus(%d)", id);
		update_focus(id);
	}

cleanup:
	arg_cleanup(args);
}

static bool supported_selection(xcb_atom_t type)
{
	return false;
}

static void xcb_selection_request(struct xcb_selection_request_event_t* ev)
{
	trace("kind=selection_request");
}

static void xcb_selection_notify(struct xcb_selection_notify_event_t* ev)
{
	if (ev->property == XCB_ATOM_NONE){
		trace("kind=error:message=couldn't convert selection");
		return;
	}
	if (supported_selection(ev->target)){
	}
/* ev->target matches the ATOM from the requested selection target,
 * e.g. timestamp, utf8_string, text, ...) */
	trace("kind=error:message=unsupported selection target");
}

static void spawn_debug()
{
	trace("kind=status:message=debug requested");
	struct arcan_shmif_cont ct = arcan_shmif_open(SEGID_TUI, 0, NULL);
	if (ct.addr){
		arcan_shmif_debugint_spawn(&ct, NULL, NULL);
/* &(struct debugint_ext_resolver){
 * .handler, .label and .tag to attach to the menu structure, can expose the
 * known WM states there
 * } */
	}
}

static void* process_thread(void* arg)
{
	while (!ferror(stdin) && !feof(stdin)){
		char inbuf[1024];
		if (fgets(inbuf, 1024, stdin)){
/* trim */
			size_t len = strlen(inbuf);
			if (len && inbuf[len-1] == '\n')
				inbuf[len-1] = '\0';

/* shouldn't be needed but doesn't trust xcb */
			pthread_mutex_lock(&wm_synch);
			process_wm_command(inbuf);
			xcb_flush(dpy);
			pthread_mutex_unlock(&wm_synch);
		}
	}
	wm_command(WM_FLUSH, "kind=terminated");
	uint8_t ch = 'x';
	trace("shutdown:source=process_thread");
	write(signal_fd, &ch, 1);
	return NULL;
}

static void run_event()
{
	xcb_generic_event_t* ev = xcb_wait_for_event(dpy);
	if (ev->response_type == 0){
		return;
	}

	pthread_mutex_lock(&wm_synch);
	switch (ev->response_type & ~0x80) {
/* the following are mostly relevant for "UI" events if the decorations are
* implemented in the context of X rather than at a higher level. Since this
* doesn't really apply to us, these can be ignored */
	case XCB_BUTTON_PRESS:
		trace("xcb=button-press");
	break;
	case XCB_MOTION_NOTIFY:
		trace("xcb=motion-notify");
	break;
	case XCB_BUTTON_RELEASE:
		trace("xcb=button-release");
	break;
	case XCB_ENTER_NOTIFY:
		trace("xcb=enter-notify");
	break;
	case XCB_LEAVE_NOTIFY:
		trace("xcb=leave-notify");
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
		trace("xcb=mapping-notify");
	break;
	case XCB_PROPERTY_NOTIFY:
		xcb_property_notify((xcb_property_notify_event_t*) ev);
	break;
	case XCB_CLIENT_MESSAGE:
		xcb_client_message((xcb_client_message_event_t*) ev);
	break;
	case XCB_FOCUS_IN:
		xcb_focus_in((xcb_focus_in_event_t*) ev);
	break;
	case XCB_SELECTION_NOTIFY:
		xcb_selection_notify((xcb_selection_notify_event_t *) ev);
	break;
	case XCB_SELECTION_REQUEST:
		xcb_selection_request((xcb_selection_request_event_t *) ev);
	break;
	default:
		trace("xcb-unhandled:type=%"PRIu8, ev->response_type);
	break;
	}
	xcb_flush(dpy);
	pthread_mutex_unlock(&wm_synch);
}

/*
 * before we have our WM 'window' and before the first client has been launched
 */
static void setup_init_state(bool standalone)
{
	xcb_change_window_attributes(dpy, wnd_root, XCB_CW_EVENT_MASK, (uint32_t[]){
		XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY |
		XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT |
		XCB_EVENT_MASK_PROPERTY_CHANGE, 0, 0
	});

	if (!standalone){
		xcb_composite_redirect_subwindows(
			dpy, wnd_root, XCB_COMPOSITE_REDIRECT_MANUAL);
	}

	xcb_atom_t atom_supp[] = {
		atoms[NET_WM_STATE],
		atoms[NET_ACTIVE_WINDOW],
		atoms[NET_WM_MOVERESIZE],
		atoms[NET_WM_STATE_MODAL],
		atoms[NET_WM_STATE_FULLSCREEN],
		atoms[NET_WM_STATE_MAXIMIZED_VERT]
	};

	xcb_change_property(dpy,
		XCB_PROP_MODE_REPLACE, wnd_root, atoms[NET_SUPPORTED],
		XCB_ATOM_ATOM, 32, 6, atom_supp
	);
}

static void* xcb_msg_thread(void* arg)
{
	for (;;)
		run_event();
	return NULL;
}

int main (int argc, char **argv)
{
	int code;

	sigaction(SIGCHLD, &(struct sigaction){
		.sa_handler = on_chld, .sa_flags = 0}, 0);

	sigaction(SIGPIPE, &(struct sigaction){
		.sa_handler = on_chld, .sa_flags = 0}, 0);

/* standalone mode is to test/debug the WM against an externally managed X,
 * this runs without the normal inherited/rootless setup */
	xwm_standalone = argc > 1 && strcmp(argv[1], "-standalone") == 0;
	bool single_exec = !xwm_standalone && argc > 1;

/*
 * Now we spawn the XWayland instance with a pipe- pair so that we can
 * read when the server is ready
 */
	int notification[2];
	if (-1 == pipe(notification)){
		trace("setup=fail:message=couldn't create status pipe");
		return EXIT_FAILURE;
	}

	int wmfd[2] = {-1, -1};
	if (-1 == socketpair(AF_UNIX, SOCK_STREAM, 0, wmfd)){
		trace("setup=fail:message=couldn't create wm socket");
		return EXIT_FAILURE;
	}
	int flags = fcntl(wmfd[0], F_GETFD);
	fcntl(wmfd[0], F_SETFD, flags | O_CLOEXEC);

	pid_t xwayland = fork();
	if (0 == xwayland){
		close(notification[0]);
		char* argv[] = {
			"Xwayland", "-rootless",
			"-displayfd", NULL,
			"-wm", NULL,
			NULL, NULL};

		asprintf(&argv[3], "%d", notification[1]);
		if (single_exec)
			argv[6] = "-terminate";

		asprintf(&argv[5], "%d", wmfd[1]);

/* note, we also have -noreset, -eglstream (?) */
		int ndev = open("/dev/null", O_RDWR);
		dup2(ndev, STDIN_FILENO);
		dup2(ndev, STDOUT_FILENO);
		dup2(ndev, STDERR_FILENO);
		close(ndev);
		setsid();

		execvp("Xwayland", argv);
		exit(EXIT_FAILURE);
	}
	else if (-1 == xwayland){
		trace("setup=fail:message=failed to fork xwayland");
		return EXIT_FAILURE;
	}
	trace("xwayland:pid=%d", xwayland);
/*
 * wait for a reply from the Xwayland setup, we can also get that as a SIGUSR1
 */
	if (!xwm_standalone){
		trace("xwayland:status=initializing");
		char inbuf[64] = {0};
		close(notification[1]);
		int rv = read(notification[0], inbuf, 63);
		if (-1 == rv){
			trace("xwayland:message=%s", strerror(errno));
			return EXIT_FAILURE;
		}

		char* err;
		unsigned long num = strtoul(inbuf, &err, 10);
		if (err == inbuf){
			trace("xwayland:status=error:message=couldn't spawn");
			return EXIT_FAILURE;
		}

		char dispnum[8];
		snprintf(dispnum, 8, ":%lu", num);
		setenv("DISPLAY", dispnum, 1);
		close(notification[0]);
		trace("xwayland:display=%lu", num);
/*
 * since we have gotten a reply, the display should be ready, just connect
 */
		dpy = xcb_connect_to_fd(wmfd[0], NULL);
	}
	else{
		dpy = xcb_connect(NULL, NULL);
	}

	if ((code = xcb_connection_has_error(dpy))){
		trace("setup=fail:code=%d:message=no display", code);
		return EXIT_FAILURE;
	}

	screen = xcb_setup_roots_iterator(xcb_get_setup(dpy)).data;
	wnd_root = screen->root;
	if (!setup_visuals()){
		trace("setup=fail:message=no 32bit visual");
		return EXIT_FAILURE;
	}

	scan_atoms();

/* pipe pair to 'wake' event thread with */
	int eventsig[2];
	if (-1 == pipe(eventsig)){
		trace("setup=fail:message=pipe-pair fail:reason=%s", strerror(errno));
		return EXIT_FAILURE;
	}
	signal_fd = eventsig[1];

	sigaction(SIGUSR2, &(struct sigaction){.sa_handler = on_dbgreq}, 0);

	setup_init_state(xwm_standalone);

	create_window();

/*
 * xcb is thread-safe, so we can have one thread for incoming
 * dispatch and another thread for outgoing dispatch
 */
	if (xwm_standalone){
		for (;;){
			run_event();
		}
		return EXIT_SUCCESS;
	}

	setlinebuf(stdin);
	setlinebuf(stdout);

/* one thread for the WM, one thread for the arcan-wayland connection */
	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	pthread_create(&pth, &pthattr, process_thread, NULL);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	pthread_create(&pth, &pthattr, xcb_msg_thread, NULL);

/*
 * Now it should be safe to chain-execute any single client we'd want, and
 * unlink on connect should we want to avoid more clients connecting to the
 * display, this will block / stop clients that proxy/spawn multiples etc.
 *
 * To retain that kind of isolation the other option is to create a
 * new namespace for this tree and keep the references around in there.
 */
	pid_t exec_child = -1;
	if (single_exec){
		exec_child = fork();
		if (-1 == exec_child){
			trace("setup=fail:message=fork-fail");
			return EXIT_FAILURE;
		}
		else if (0 == exec_child){
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

			int ndev = open("/dev/null", O_RDWR);
			dup2(ndev, STDIN_FILENO);
			dup2(ndev, STDOUT_FILENO);
			dup2(ndev, STDERR_FILENO);
			close(ndev);
			setsid();

			execvp(argv[1], &argv[1]);
			return EXIT_FAILURE;
		}
		else {
			trace("client_exec=%s", argv[1]);
		}
	}

	for(;;){
		uint8_t ch;
		if (1 == read(eventsig[0], &ch, 1)){
			if (ch == 'x'){
				trace("shutdown:source=kill_thread_msg");
				break;
			}
			if (ch == 'd')
				spawn_debug();
		}
	}

	if (exec_child != -1){
		trace("shutdown:kill_child=%d", (int)exec_child);
		kill(SIGHUP, exec_child);
	}

	if (xwayland != -1){
		trace("shutdown:kill_xwayland=%d", (int)xwayland);
		kill(SIGHUP, xwayland);
	}

	return 0;
}
