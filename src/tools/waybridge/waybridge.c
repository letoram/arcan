/*
 * Copyright 2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#define WANT_ARCAN_SHMIF_HELPER
#include <arcan_shmif.h>
#include <wayland-server.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <sys/mman.h>
#include <errno.h>
#include <poll.h>

static inline void trace(const char* msg, ...)
{
	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
		fprintf(stderr, "\n");
	va_end( args);
	fflush(stderr);
}

struct bridge_client {
	struct arcan_shmif_cont acon;
	struct arcan_shmif_cont cursor;

	struct wl_client* client;
	struct wl_resource* keyboard;
	struct wl_resource* pointer;
	struct wl_resource* touch;
	struct wl_list link;
};

struct bridge_surface {
	struct wl_resource* res;
	struct wl_resource* buf;
	struct wl_resource* frame_cb;

	int sstate;
	int x, y, glid;
	struct bridge_client* cl;
	struct wl_list link;
	struct wl_listener on_destroy;
};

struct bridge_pool {
	struct wl_resource* res;
	void* mem;
	size_t size;
	unsigned refc;
	int fd;
};

static struct {
	EGLDisplay display;
	struct wl_list cl, surf;
	struct wl_display* disp;
	struct arcan_shmif_initial init;
	struct arcan_shmif_cont control;
} wl;

/*
 * xkbdkeyboard
 */

/*
 * EGL- details needed for handle translation
 */
typedef void (*PFNGLEGLIMAGETARGETTEXTURE2DOESPROC) (EGLenum, EGLImage);
static PFNEGLQUERYWAYLANDBUFFERWL query_buffer;
static PFNEGLBINDWAYLANDDISPLAYWL bind_display;
static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC img_tgt_text;
/* static PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display; */

/*
 * Welcome to callback hell
 */
#include "surf.c"
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

/*
 * an issue here is of course that we don't have a 1:1 mapping between
 * shmif connections and surfaces. When we get a new client, we request
 * a shmif-connection, then we have to wait for a surface that fits the
 * role so we can associate shmifcont.tag(surface). We can almost assume
 * everyone wants a mouse cursor and a popup, so we can request one each
 * of those and just keep it dormant as a subseg.
 */
void send_client_input(struct bridge_client* cl, arcan_ioevent* ev)
{
	if (ev->devkind == EVENT_IDEVKIND_TOUCHDISP){
	}
	else if (ev->devkind == EVENT_IDEVKIND_MOUSE){
		trace("mouse input..");
	}
	else if (ev->datatype == EVENT_IDATATYPE_TRANSLATED){
/* wl_keyboard_send_enter,
 * wl_keyboard_send_leave,
 * wl_keyboard_send_key,
 * wl_keyboard_send_keymap,
 * wl_keyboard_send_modifiers,
 * wl_keyboard_send_repeat_info */
	}
	else
		;
}

static void flush_events(struct bridge_client* cl)
{
	struct arcan_event ev;

	while (arcan_shmif_poll(&cl->acon, &ev) > 0){
		if (ev.category == EVENT_IO)
			send_client_input(cl, &ev.io);
		else if (ev.category != EVENT_TARGET)
			continue;
		switch(ev.tgt.kind){
		case TARGET_COMMAND_EXIT:
			trace("shmif-> kill client");
		break;
		case TARGET_COMMAND_DISPLAYHINT:
			trace("shmif-> target update visibility or size");
		break;
		case TARGET_COMMAND_OUTPUTHINT:
			trace("shmif-> target update configuration");
		break;
		default:
		break;
		}
	}
}

static struct bridge_client* find_client(struct wl_client* cl)
{
	struct bridge_client* res;
	wl_list_for_each(res, &wl.cl, link){
		if (res->client == cl)
			return res;
	}
	res = malloc(sizeof(struct bridge_client));
	memset(res, '\0', sizeof(struct bridge_client));

/* this can impose a stall with connection rate limiting and so
 * on, so there might be a value in either pre-allocating connections
 * or running it as a connection-thread */
	trace("allocating new client\n");
	res->acon = arcan_shmif_open(SEGID_BRIDGE_WAYLAND, 0, NULL);
	res->client = cl;
	if (!res->acon.addr){
		free(res);
		return NULL;
	}

/* might be useful to pre-queue for the cursor subsegment here,
 * rather than deferring etc. */
	wl_list_insert(&wl.cl, &res->link);

	return res;
}

static void comp_surf_delete(struct wl_resource* res)
{
	trace("destroy compositor surface\n");
	struct bridge_surface* surf = wl_resource_get_user_data(res);
	if (!surf)
		return;

	if (surf->cl){
		arcan_shmif_drop(&surf->cl->acon);
	}

	wl_list_remove(&surf->link);
	free(surf);
}

static void comp_surf_create(struct wl_client *client,
	struct wl_resource *res, uint32_t id)
{
	trace("create compositor surface(%"PRIu32")", id);
/* we need to defer this and make a subsegment connection unless
 * the client has not consumed its primary one */
	struct bridge_surface* new_surf = malloc(sizeof(struct bridge_surface));
	memset(new_surf, '\0', sizeof(struct bridge_surface));
	new_surf->cl = find_client(client);
	if (!new_surf->cl){
		wl_resource_post_error(res, WL_SHM_ERROR_INVALID_FD, "out of memory\n");
		free(new_surf);
		return;
	}

	new_surf->res = wl_resource_create(client, &wl_surface_interface,
		wl_resource_get_version(res), id);

	wl_resource_set_implementation(new_surf->res,
		&surf_if, new_surf, comp_surf_delete);

	wl_list_insert(&wl.surf, &new_surf->link);
}

#include "region.c"
static struct wl_region_interface region_if = {
	.destroy = region_destroy,
	.add = region_add,
	.subtract = region_sub
};
static void comp_create_reg(struct wl_client *client,
	struct wl_resource *resource, uint32_t id)
{
	trace("create region");
	struct wl_resource* region = wl_resource_create(client,
		&wl_region_interface, wl_resource_get_version(resource), id);
	wl_resource_set_implementation(region, &region_if, NULL, NULL);
}

static struct wl_compositor_interface compositor_if = {
	.create_surface = comp_surf_create,
	.create_region = comp_create_reg,
};

static void shm_buf_create(struct wl_client* client,
	struct wl_resource* res, uint32_t id, int32_t offset,
	int32_t width, int32_t height, int32_t stride, uint32_t format)
{
	trace("wl_shm_buf_create(%d*%d)", (int) width, (int) height);
/*
 * struct bridge_surface* surf = wl_resource_get_user_data(res);
 */

/*
	wayland_buffer_create_resource(client,
		wl_resource_get_version(resource), id, buffer);
 */

 /* wld_buffer_add_destructor(buffer, reference->destructor */
}

static void shm_buf_destroy(struct wl_client* client,
	struct wl_resource* res)
{
	trace("shm_buf_destroy");
	wl_resource_destroy(res);
}

static void shm_buf_resize(struct wl_client* client,
	struct wl_resource* res, int32_t size)
{
	trace("shm_buf_resize(%d)", (int) size);
	struct bridge_pool* pool = wl_resource_get_user_data(res);
	void* data = mmap(NULL, size, PROT_READ, MAP_SHARED, pool->fd, 0);
	if (data == MAP_FAILED){
		wl_resource_post_error(res,WL_SHM_ERROR_INVALID_FD,
			"couldn't remap shm_buf (%s)", strerror(errno));
	}
	else {
		munmap(pool->mem, pool->size);
		pool->mem = data;
		pool->size = size;
	}
}

static struct wl_shm_pool_interface shm_pool_if = {
	.create_buffer = shm_buf_create,
	.destroy = shm_buf_destroy,
	.resize = shm_buf_resize,
};

static void destroy_pool_res(struct wl_resource* res)
{
	struct bridge_pool* pool = wl_resource_get_user_data(res);
	pool->refc--;
	if (!pool->refc){
		munmap(pool->mem, pool->size);
		free(pool);
	}
}

static void create_pool(struct wl_client* client,
	struct wl_resource* res, uint32_t id, int32_t fd, int32_t size)
{
	trace("wl_shm_create_pool(%d)", id);
	struct bridge_pool* pool = malloc(sizeof(struct bridge_pool));
	if (!pool){
		wl_resource_post_error(res, WL_SHM_ERROR_INVALID_FD,
			"out of memory\n");
		close(fd);
		return;
	}
	*pool = (struct bridge_pool){};

	pool->res = wl_resource_create(client,
		&wl_shm_pool_interface, wl_resource_get_version(res), id);
	if (!pool->res){
		wl_resource_post_no_memory(res);
		free(pool);
		close(fd);
		return;
	}

	wl_resource_set_implementation(pool->res,
		&shm_pool_if, pool, &destroy_pool_res);

	pool->mem = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, 0);
	if (pool->mem == MAP_FAILED){
		wl_resource_post_error(res, WL_SHM_ERROR_INVALID_FD,
			"couldn't mmap: %s\n", strerror(errno));
		wl_resource_destroy(pool->res);
		free(pool);
		close(fd);
	}
	else {
		pool->size = size;
		pool->refc = 1;
		pool->fd = fd;
	}
}

static void bind_output(struct wl_client* client,
	void* data, uint32_t version, uint32_t id)
{
	trace("bind_output");
	struct wl_resource* resource = wl_resource_create(client,
		&wl_output_interface, version, id);
	if (!resource){
		wl_client_post_no_memory(client);
		return;
	}

/* convert the initial display info from x, y to mm using ppcm */
	wl_output_send_geometry(resource, 0, 0,
		(float)wl.init.display_width_px / wl.init.density * 10.0,
		(float)wl.init.display_height_px / wl.init.density * 10.0,
		0, /* init.fonts[0] hinting should work */
		"unknown", "unknown",
		0
	);

	wl_output_send_mode(resource, WL_OUTPUT_MODE_CURRENT,
		wl.init.display_width_px, wl.init.display_height_px, wl.init.rate);

	if (version >= 2)
		wl_output_send_done(resource);
}

static struct wl_shm_interface shm_if = {
	.create_pool = create_pool
};

static void bind_shm(struct wl_client* client,
	void* data, uint32_t version, uint32_t id)
{
	struct wl_resource* res = wl_resource_create(client,
		&wl_shm_interface, version, id);
	wl_resource_set_implementation(res, &shm_if, NULL, NULL);
	wl_shm_send_format(res, WL_SHM_FORMAT_XRGB8888);
	wl_shm_send_format(res, WL_SHM_FORMAT_ARGB8888);
}

#include "seat.c"
static struct wl_seat_interface seat_if = {
	.get_pointer = seat_pointer,
	.get_keyboard = seat_keyboard,
	.get_touch = seat_touch
};

static void bind_comp(struct wl_client *client,
	void *data, uint32_t version, uint32_t id)
{
	trace("wl_bind(compositor %d:%d)", version, id);
	struct wl_resource* res = wl_resource_create(client,
		&wl_compositor_interface, version, id);
	wl_resource_set_implementation(res, &compositor_if, NULL, NULL);
}

static void bind_seat(struct wl_client *client,
	void *data, uint32_t version, uint32_t id)
{
	trace("wl_bind(seat %d:%d)", version, id);
	struct wl_resource* res = wl_resource_create(client,
		&wl_seat_interface, version, id);
	wl_resource_set_implementation(res, &seat_if, NULL, NULL);
	wl_seat_send_capabilities(res, WL_SEAT_CAPABILITY_POINTER |
		WL_SEAT_CAPABILITY_KEYBOARD | WL_SEAT_CAPABILITY_TOUCH);
}

#include "shell.c"
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

void wl_shell_get_surf(struct wl_client* client,
	struct wl_resource* res, uint32_t id, struct wl_resource* surf_res)
{
	trace("get shell surface");
	struct bridge_surface* surf = malloc(sizeof(struct bridge_surface));
	if (!surf){
		wl_resource_post_no_memory(res);
		return;
	}
	*surf = (struct bridge_surface){};

	surf->res = wl_resource_create(client,
		&wl_shell_surface_interface, wl_resource_get_version(res), id);
	if (!surf->res){
		free(surf);
		wl_resource_post_no_memory(res);
		return;
	}

/* FIXME: it's likely here we have enough information to reliably
 * wait for a segment or subsegment to represent the window, but with
 * the API at hand, it seems impossible to do without blocking everything
 * (especially with EGL surfaces ...)
 *
 * What we want to do is spin a thread per client and have the usual
 * defer/buffer while wating for asynch subseg reply
 */

	wl_resource_set_implementation(surf->res, &ssurf_if, surf, &ssurf_free);
//	surf->on_destroy.notify = &ssurf_destroy;
//	wl_resource_add_destroy_listener(surf->res, &surf->on_destroy);
}

static const struct wl_shell_interface shell_if = {
	.get_shell_surface = wl_shell_get_surf
};

static void bind_shell(struct wl_client* client,
	void *data, uint32_t version, uint32_t id)
{
	trace("wl_bind(shell %d:%d)", version, id);
	struct wl_resource* res = wl_resource_create(client,
		&wl_shell_interface, version, id);
	wl_resource_set_implementation(res, &shell_if, NULL, NULL);
}

static int show_use(const char* msg, const char* arg)
{
	fprintf(stdout, "%s%s", msg, arg ? arg : "");
	fprintf(stdout, "Use: waybridge [arguments]\n"
"\t-egl            pass shm- buffers as gl textures\n"
"\t-wl-egl         enable wayland egl/drm support\n"
"\t-no-compositor  disable the compositor protocol\n"
"\t-no-shell       disable the shell protocol\n"
"\t-no-shm         disable the shm protocol\n"
"\t-no-seat        disable the seat protocol\n"
"\t-no-output      disable the output protocol\n");
	return EXIT_FAILURE;
}

int main(int argc, char* argv[])
{
	struct arg_arr* aarr;
	int shm_egl = false;

/* for each wayland protocol or subprotocol supported, add a corresponding
 * field here, and then command-line argument passing to disable said protocol.
 */
	struct {
		int compositor, shell, shm, seat, output, egl;
	} protocols = {
		.compositor = 3,
		.shell = 1,
		.shm = 1,
		.seat = 4,
		.output = 2,
		.egl = 0
	};

	for (size_t i = 1; i < argc; i++){
		if (strcmp(argv[i], "-egl") == 0){
			shm_egl = true;
		}
		else if (strcmp(argv[i], "-wl-egl") == 0)
			protocols.egl = 1;
		else if (strcmp(argv[i], "-no-compositor") == 0)
			protocols.compositor = 0;
		else if (strcmp(argv[i], "-no-shell") == 0)
			protocols.shell = 0;
		else if (strcmp(argv[i], "-no-shm") == 0)
			protocols.shm = 0;
		else if (strcmp(argv[i], "-no-seat") == 0)
			protocols.seat = 0;
		else if (strcmp(argv[i], "-no-output") == 0)
			protocols.output = 0;
		else
			return show_use("unknown argument", argv[i]);
	}

	wl.disp = wl_display_create();
	if (!wl.disp){
		fprintf(stderr, "Couldn't create wayland display\n");
		return EXIT_FAILURE;
	}

/*
 * Will need to do some argument parsing here:
 * 1. runtime dir (override XDG_RUNTIME_DIR)
 * 2. limit to number of active connections
 * 3. default keyboard layout to provide (can possibly scan the dir
 *    and try to map to GEOHINT from the arcan_shmif_initial)
 * 4. allow shm- only mode with explicit copies.
 */
	if (!getenv("XDG_RUNTIME_DIR")){
		fprintf(stderr, "Missing environment: XDG_RUNTIME_DIR\n");
		return EXIT_FAILURE;
	}

	wl.control = arcan_shmif_open(SEGID_BRIDGE_WAYLAND, SHMIF_ACQUIRE_FATALFAIL, &aarr);
	struct arcan_shmif_initial* init;
	arcan_shmif_initial(&wl.control, &init);
	wl.init = *init;
	if (!init->display_width_px){
		fprintf(stderr, "Bridge connection did not receive display information\n"
			"make sure active appl- sends target_displayhint on preroll\n\n");
		wl.init.display_width_px = wl.control.w;
		wl.init.display_height_px = wl.control.h;
	}

	if (protocols.egl){
		bind_display = (PFNEGLBINDWAYLANDDISPLAYWL)
			eglGetProcAddress ("eglBindWaylandDisplayWL");
		query_buffer = (PFNEGLQUERYWAYLANDBUFFERWL)
			eglGetProcAddress ("eglQueryWaylandBufferWL");
		img_tgt_text = (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)
			eglGetProcAddress ("glEGLImageTargetTexture2DOES");

		if (!bind_display||!query_buffer||!img_tgt_text){
			fprintf(stderr, "missing WL-EGL extensions\n");
			arcan_shmif_drop(&wl.control);
			return EXIT_FAILURE;
		}

		struct arcan_shmifext_setup cfg = arcan_shmifext_defaults(&wl.control);
		cfg.builtin_fbo = false;
		if (SHMIFEXT_OK != arcan_shmifext_setup(&wl.control, cfg)){
			fprintf(stderr, "Couldn't setup EGL context/display\n");
			arcan_shmif_drop(&wl.control);
			return EXIT_FAILURE;
		}

		uintptr_t display;
		arcan_shmifext_egl_meta(&wl.control, &display, NULL, NULL);
		wl.display = eglGetDisplay((EGLDisplay)display);
		if (!bind_display(wl.display, wl.disp)){
			fprintf(stderr, "(eglBindWaylandDisplaYWL) failed\n");
			arcan_shmif_drop(&wl.control);
			return EXIT_FAILURE;
		}
	}

/*
 * The decision to not murder xkb but rather make it worse by spreading
 * it everywhere, running out of /facepalm -- when even android does it
 * better, you're really in for a treat.
 */
	wl_list_init(&wl.cl);
	wl_list_init(&wl.surf);

/*
 * FIXME: need a user config- way to set which interfaces should be
 * enabled and which should be disabled
 */
	wl_display_add_socket_auto(wl.disp);
	if (protocols.compositor)
		wl_global_create(wl.disp, &wl_compositor_interface,
			protocols.compositor, NULL, &bind_comp);
	if (protocols.shell)
		wl_global_create(wl.disp, &wl_shell_interface,
			protocols.shell, NULL, &bind_shell);
	if (protocols.shm){
		wl_global_create(wl.disp, &wl_shm_interface,
			protocols.shm, NULL, &bind_shm);
		wl_display_init_shm(wl.disp);
	}
	if (protocols.seat)
		wl_global_create(wl.disp, &wl_seat_interface,
			protocols.seat, NULL, &bind_seat);
	if (protocols.output)
		wl_global_create(wl.disp, &wl_output_interface,
			protocols.output, NULL, &bind_output);

	struct wl_event_loop* loop = wl_display_get_event_loop(wl.disp);
	trace("wl_display() finished");

	while(1){
/* FIXME multiplex on conn and shmif-fd and poll
 * int fd = wl_event_loop_get_fd(loop);
 */
		wl_event_loop_dispatch(loop, 0);
		wl_display_flush_clients(wl.disp);
/* wl_signal_init(..) */

		arcan_event ev;
		while (arcan_shmif_poll(&wl.control, &ev) > 0){
			if (ev.category == EVENT_TARGET){
				switch (ev.tgt.kind){
/* bridge has been reassigned to another output */
				case TARGET_COMMAND_OUTPUTHINT:
					wl.init.display_width_px = ev.tgt.ioevs[0].iv;
					wl.init.display_height_px = ev.tgt.ioevs[1].iv;
				break;
				case TARGET_COMMAND_EXIT:
					goto out;
				default:
				break;
				}
			}
		}

	}

out:
	wl_display_destroy(wl.disp);

	return EXIT_SUCCESS;
}
