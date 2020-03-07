/*
 * This one is a bit special as it have been plucked from mesa and slightly
 * patched to retrieve the render node we are supposed to use
 */
#include "wayland-wayland-drm-server-protocol.h"
#include "wayland-linux-dmabuf-unstable-v1-server-protocol.h"

#include "wlimpl/xwl.c"

#include "wlimpl/drm.c"

#include "wlimpl/dma_buf_param.c"
static struct zwp_linux_buffer_params_v1_interface zdmabuf_params_if = {
	.destroy = zdmattr_destroy,
	.add = zdmattr_add,
	.create = zdmattr_create,
	.create_immed = zdmattr_create_immed
};

#include "wlimpl/dma_buf.c"
static struct zwp_linux_dmabuf_v1_interface zdmabuf_if = {
	.destroy = zdmabuf_destroy,
	.create_params = zdmabuf_params,
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

#include "wlimpl/subsurf.c"
static struct wl_subsurface_interface subsurf_if = {
	.destroy = subsurf_destroy,
	.set_position = subsurf_position,
	.place_above = subsurf_placeabove,
	.place_below = subsurf_placebelow,
	.set_sync = subsurf_setsync,
	.set_desync = subsurf_setdesync
};

#include "wlimpl/subcomp.c"
static struct wl_subcompositor_interface subcomp_if = {
	.destroy = subcomp_destroy,
	.get_subsurface = subcomp_subsurf
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

#include "wlimpl/data_offer.c"
static const struct wl_data_offer_interface doffer_if = {
	.accept = doffer_accept,
	.receive = doffer_receive,
	.finish = doffer_finish,
	.set_actions = doffer_actions,
	.destroy = doffer_destroy
};

#include "wlimpl/data_source.c"
static const struct wl_data_source_interface dsrc_if = {
	.offer = dsrc_offer,
	.destroy = dsrc_destroy,
	.set_actions = dsrc_actions
};

#include "wlimpl/data_device.c"
static const struct wl_data_device_interface ddev_if = {
	.start_drag = ddev_start_drag,
	.set_selection = ddev_set_selection,
	.release = ddev_release
};

#include "wlimpl/data_device_mgr.c"
static const struct wl_data_device_manager_interface ddevmgr_if = {
	.create_data_source = ddevmgr_create_data_source,
	.get_data_device = ddevmgr_get_data_device
};

#include "wayland-xdg-shell-unstable-v6-server-protocol.h"
#include "wlimpl/zxdg_positioner.c"
static struct zxdg_positioner_v6_interface zxdgpos_if = {
	.destroy = zxdgpos_destroy,
	.set_size = zxdgpos_size,
	.set_anchor_rect = zxdgpos_anchor_rect,
	.set_anchor = zxdgpos_anchor,
	.set_gravity = zxdgpos_gravity,
	.set_constraint_adjustment = zxdgpos_consadj,
	.set_offset = zxdgpos_offset
};

#include "wlimpl/zxdg_popup.c"
static struct zxdg_popup_v6_interface zxdgpop_if = {
	.destroy = zxdgpop_destroy,
	.grab = zxdgpop_grab
};

#include "wlimpl/zxdg_toplevel.c"
static struct zxdg_toplevel_v6_interface zxdgtop_if = {
	.destroy = zxdgtop_destroy,
	.set_parent = zxdgtop_setparent,
	.set_title = zxdgtop_title,
	.set_app_id = zxdgtop_appid,
	.show_window_menu = zxdgtop_wndmenu,
	.move = zxdgtop_move,
	.resize = zxdgtop_resize,
	.set_max_size = zxdgtop_set_max,
	.set_min_size = zxdgtop_set_min,
	.set_maximized = zxdgtop_maximize,
	.unset_maximized = zxdgtop_demaximize,
	.set_fullscreen = zxdgtop_fullscreen,
	.unset_fullscreen = zxdgtop_unset_fullscreen,
	.set_minimized = zxdgtop_minimize
};

#include "wlimpl/zxdg_ssurf.c"
static struct zxdg_surface_v6_interface zxdgsurf_if = {
	.destroy = zxdgsurf_destroy,
	.get_toplevel = zxdgsurf_toplevel,
	.get_popup = zxdgsurf_getpopup,
	.set_window_geometry = zxdgsurf_set_geometry,
	.ack_configure = zxdgsurf_ackcfg,
};

#include "wlimpl/zxdg_shell.c"
static const struct zxdg_shell_v6_interface zxdgshell_if = {
	.get_xdg_surface = zxdg_getsurf,
	.create_positioner = zxdg_createpos,
	.pong = zxdg_pong,
	.destroy = zxdg_destroy
};

/*
 * most of these are just differently named vtables that map to the same zxdg-
 * implementation, should these diverge, simply copy the zxdg_ version and add
 * xdg_ versions.
 */
#include "wayland-xdg-shell-server-protocol.h"
#include "wlimpl/xdg_positioner.c"
static struct xdg_positioner_interface xdgpos_if = {
	.destroy = xdgpos_destroy,
	.set_size = xdgpos_size,
	.set_anchor_rect = xdgpos_anchor_rect,
	.set_anchor = xdgpos_anchor,
	.set_gravity = xdgpos_gravity,
	.set_constraint_adjustment = xdgpos_consadj,
	.set_offset = xdgpos_offset
};

#include "wlimpl/xdg_toplevel.c"
static struct xdg_toplevel_interface xdgtop_if = {
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

#include "wlimpl/xdg_popup.c"
static struct xdg_popup_interface xdgpop_if = {
	.destroy = xdgpop_destroy,
	.grab = xdgpop_grab
};

#include "wlimpl/xdg_ssurf.c"
static struct xdg_surface_interface xdgsurf_if = {
	.destroy = xdgsurf_destroy,
	.get_toplevel = xdgsurf_toplevel,
	.get_popup = xdgsurf_getpopup,
	.set_window_geometry = xdgsurf_set_geometry,
	.ack_configure = xdgsurf_ackcfg,
};

#include "wlimpl/xdg_shell.c"
static const struct xdg_wm_base_interface xdgshell_if = {
	.get_xdg_surface = xdg_getsurf,
	.create_positioner = xdg_createpos,
	.pong = xdg_pong,
	.destroy = xdg_destroy
};

#include "wayland-relative-pointer-unstable-v1-server-protocol.h"
#include "wlimpl/relp_mgr.c"
static const struct zwp_relative_pointer_manager_v1_interface relpmgr_if = {
	.destroy = relpm_destroy,
	.get_relative_pointer = relpm_get
};

#include "wayland-pointer-constraints-unstable-v1-server-protocol.h"
#include "wlimpl/constrain.c"
static const struct zwp_confined_pointer_v1_interface confptr_if = {
	.destroy = confptr_destroy,
	.set_region = confptr_region
};

static const struct zwp_pointer_constraints_v1_interface consptr_if = {
	.destroy = consptr_destroy,
	.confine_pointer = consptr_confine,
	.lock_pointer = consptr_lock
};

static const struct zwp_locked_pointer_v1_interface lockptr_if = {
	.destroy = lockptr_destroy,
	.set_region = lockptr_region,
	.set_cursor_position_hint = lockptr_hintat
};

#include "bondage.c"
