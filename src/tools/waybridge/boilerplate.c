#define STEP_SERIAL() ( wl_display_next_serial(wl.disp) )

/*
 * From every wayland subprotocol that needs to allocate a surface,
 * this structure needs to be filled and sent to the request_surface
 * call.
 */
struct bridge_client {
	struct arcan_shmif_cont acon;
	struct arcan_shmif_cont cursor, popup;

	struct wl_listener l_destr;

	struct wl_client* client;
	struct wl_resource* keyboard;
	struct wl_resource* pointer;
	struct wl_resource* touch;
	struct wl_resource* output; /* only 1 atm */

	bool forked;
	int group, slot;
	int refc;
};

struct acon_tag {
	int group, slot;
};

struct surface_request {
/* local identifier, only for personal tracking */
	uint32_t id;
	const char* trace;

/* the type of the segment that should be requested */
	int segid;

/* the tracking resource and mapping between all little types */
	struct comp_surf* source;
	struct wl_resource* target;
	struct bridge_client* client;

/* custom 'shove it in here' reference */
	void* tag;

/* callback that will be triggered with the result, [srf] will be NULL if the
 * request failed. Return [true] if you accept responsibility of the shmif_cont
 * (will be added to the group/slot allocation and normal I/O multiplexation)
 * or [false] if the surface is not needed anymore. */
	bool (*dispatch)(struct surface_request*, struct arcan_shmif_cont* srf);
};

static bool request_surface(struct bridge_client* cl, struct surface_request*);

struct surf_state {
	bool hidden : 1;
	bool unfocused : 1;
	bool maximized : 1;
	bool minimized : 1;
	bool drag_resize : 1;
};

struct comp_surf {
	struct bridge_client* client;
	struct wl_resource* res;
	struct wl_resource* shell_res;
	struct arcan_shmif_cont acon;
	struct wl_resource* buf;
	struct wl_resource* frame_callback;

	int pointer_pending;
	struct surf_state states;
	uint32_t cb_id;
/* return [true] if the event was consumed and shouldn't be processed by the
 * default handler */
	bool (*dispatch)(struct comp_surf*, struct arcan_event* ev);
	int cookie;
};

static bool displayhint_handler(struct comp_surf* surf,
	struct arcan_tgtevent* tev);

static void try_frame_callback(struct comp_surf* surf);

/*
 * this is to share the tracking / allocation code between both clients and
 * surfaces and possible other wayland resources that results in a 1:1 mapping
 * to an arcan connection that needs to have its event loop flushed.
 *
 * The layout in the structures is so the first member (can't be bad) resolve
 * to the same type of structure.
 */
#define SLOT_TYPE_CLIENT 1
#define SLOT_TYPE_SURFACE 2
struct bridge_slot {
	int type;
	union {
		struct arcan_shmif_cont con;
		struct bridge_client client;
		struct comp_surf* surface;
	};
};

struct bridge_pool {
	struct wl_resource* res;
	void* mem;
	size_t size;
	unsigned refc;
	int fd;
};

#include "wlimpl/surf.c"
static struct wl_surface_interface surf_if = {
	.destroy = surf_destroy,
	.attach = surf_attach,
	.damage = surf_damage,
	.frame = surf_frame,
	.set_opaque_region = surf_opaque,
	.set_input_region = surf_inputreg,
	.commit = surf_commit,
	.set_buffer_transform = surf_transform,
	.set_buffer_scale = surf_scale,
	.damage_buffer = surf_damage
};

#include "wlimpl/region.c"
static struct wl_region_interface region_if = {
	.destroy = region_destroy,
	.add = region_add,
	.subtract = region_sub
};

#include "wlimpl/comp.c"
static struct wl_compositor_interface compositor_if = {
	.create_surface = comp_surf_create,
	.create_region = comp_create_reg,
};

#include "wlimpl/subcomp.c"
static struct wl_subcompositor_interface subcomp_if = {
	.destroy = subcomp_destroy,
	.get_subsurface = subcomp_subsurf
};

#include "wlimpl/subsurf.c"
static struct wl_subsurface_interface subsurf_if = {
	.destroy = subsurf_destroy,
	.set_position = subsurf_position,
	.place_above = subsurf_placeabove,
	.place_below = subsurf_placebelow,
	.set_sync = subsurf_setsync,
	.set_desync = subsurf_setdesync
};

#include "wlimpl/seat.c"
static struct wl_seat_interface seat_if = {
	.get_pointer = seat_pointer,
	.get_keyboard = seat_keyboard,
	.get_touch = seat_touch
};

#include "wlimpl/shell_surf.c"
static struct wl_shell_surface_interface ssurf_if = {
	.pong = ssurf_pong,
	.move = ssurf_move,
	.resize = ssurf_resize,
	.set_toplevel = ssurf_toplevel,
	.set_transient = ssurf_transient,
	.set_fullscreen = ssurf_fullscreen,
	.set_popup = ssurf_popup,
	.set_maximized = ssurf_maximized,
	.set_title = ssurf_title,
	.set_class = ssurf_class
};

#include "wlimpl/shell.c"
static const struct wl_shell_interface shell_if = {
	.get_shell_surface = shell_getsurf
};

#include "wayland-xdg-shell-unstable-v6-server-protocol.h"
#include "wlimpl/xdg_positioner.c"
static struct zxdg_positioner_v6_interface xdgpos_if = {
	.destroy = xdgpos_destroy,
	.set_size = xdgpos_size,
	.set_anchor_rect = xdgpos_anchor_rect,
	.set_anchor = xdgpos_anchor,
	.set_gravity = xdgpos_gravity,
	.set_constraint_adjustment = xdgpos_consadj,
	.set_offset = xdgpos_offset
};

#include "wlimpl/xdg_popup.c"
static struct zxdg_popup_v6_interface xdgpop_if = {
	.destroy = xdgpop_destroy,
	.grab = xdgpop_grab
};

#include "wlimpl/xdg_toplevel.c"
static struct zxdg_toplevel_v6_interface xdgtop_if = {
	.destroy = xdgtop_destroy,
	.set_parent = xdgtop_setparent,
	.set_title = xdgtop_title,
	.set_app_id = xdgtop_appid,
	.show_window_menu = xdgtop_wndmenu,
	.move = xdgtop_move,
	.resize = xdgtop_resize,
	.set_max_size = xdgtop_set_max,
	.set_min_size = xdgtop_set_min,
	.set_maximized = xdgtop_maximize,
	.unset_maximized = xdgtop_demaximize,
	.set_fullscreen = xdgtop_fullscreen,
	.unset_fullscreen = xdgtop_unset_fullscreen,
	.set_minimized = xdgtop_minimize
};

#include "wlimpl/xdg_ssurf.c"
static struct zxdg_surface_v6_interface xdgsurf_if = {
	.destroy = xdgsurf_destroy,
	.get_toplevel = xdgsurf_toplevel,
	.get_popup = xdgsurf_getpopup,
	.set_window_geometry = xdgsurf_set_geometry,
	.ack_configure = xdgsurf_ackcfg,
};

#include "wlimpl/xdg_shell.c"
static const struct zxdg_shell_v6_interface xdgshell_if = {
	.get_xdg_surface = xdg_getsurf,
	.create_positioner = xdg_createpos,
	.pong = xdg_pong,
	.destroy = xdg_destroy
};

#include "bondage.c"
