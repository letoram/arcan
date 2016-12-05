/*
 * Copyright 2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: https://github.com/letoram/arcan/wiki/wayland.md
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

/*
 * EGL- details needed for handle translation
 */
typedef void (*PFNGLEGLIMAGETARGETTEXTURE2DOESPROC) (EGLenum, EGLImage);
static PFNEGLQUERYWAYLANDBUFFERWL query_buffer;
static PFNEGLBINDWAYLANDDISPLAYWL bind_display;
static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC img_tgt_text;
static struct bridge_client* find_client(struct wl_client* cl);

/* static PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display; */

/*
 * For tracking allocations in arcan, spit into bitmapped groups allocated/set
 * on startup. Allocation policy is first free slot, though no compaction
 * between groups. Doing it this way makes thread-group assignments etc.
 * easier if that ever becomes a need.
 */
static const size_t N_GROUP_SLOTS = sizeof(long long int) * 8;
struct conn_group {
	long long int alloc;

/* 2 padding for the wl server socket and bridge- connection */
	struct pollfd* pg;
	struct bridge_client* cl;
};

static struct {
	size_t n_groups;
	struct conn_group* groups;
	unsigned client_limit, client_count;

	EGLDisplay display;
	struct wl_display* disp;
	struct arcan_shmif_initial init;
	struct arcan_shmif_cont control;
	bool alive;
} wl;

/*
 * Welcome to callback hell where it is allowed to #include code sin because
 * the cost in sanity to figure out what goes where and how and when in this
 * tangled ball of snakes and doxygen is just not worth the mental damage.
 *
 * This whole API should've just been designed in C++, it's evident that
 * the language has much better capacity for handling it than C ever will.
 *
 * This is how UAF vulns with call-into-libc 'sploits are born
 */
#include "boilerplate.c"

static void send_client_input(struct bridge_client* cl, arcan_ioevent* ev)
{
	if (ev->devkind == EVENT_IDEVKIND_TOUCHDISP){
	}
	else if (ev->devkind == EVENT_IDEVKIND_MOUSE){
/* wl_mouse_blabla */
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

static void flush_client_events(struct bridge_client* cl)
{
	struct arcan_event ev;
	while (arcan_shmif_poll(&cl->acon, &ev) > 0){
		if (ev.category == EVENT_IO){
			send_client_input(cl, &ev.io);
			continue;
		}
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

/*
 * Will allocate / open new as needed, divide clients into groups of 64
 * (so bitmasked) for both structure tracking and for fd-polling for ev
 * flush
 */
static struct bridge_client* find_client(struct wl_client* cl)
{
	struct bridge_client* res = NULL;

/* traverse each group, check the fields for the set bits for match */
	for (size_t i = 0; i < wl.n_groups; i++){
		long long int mask = wl.groups[i].alloc;
		while (mask){
			long long int ind = ffs(mask);
			if (!ind)
				continue;

			ind--;
			if (wl.groups[i].cl[ind].client == cl)
				return &wl.groups[i].cl[ind];
			mask &= ~(1 << ind);
		}
	}

	if (wl.client_limit == wl.client_count)
		return NULL;

/* find first group with a free slot and alloc into it */
	for (size_t i = 0; i < wl.n_groups; i++){
		long long int ind = ffs(~wl.groups[i].alloc);
		if (0 == ind)
			continue;

/* connect/allocate
 * this can impose a stall with connection rate limiting and so on, so there
 * might be a value in either pre-allocating connections or running it as a
 * connection-thread
 */
		trace("allocating new client (%zu:%lld)", i, ind);
		ind--;
		res = &wl.groups[i].cl[ind];
		memset(res, '\0', sizeof(struct bridge_client));

		res->acon = arcan_shmif_open(SEGID_BRIDGE_WAYLAND, 0, NULL);
		if (!res->acon.vidp)
			return NULL;

/*
 * pretty much always need to be ready for damaged surfaces so enable now
 */
		res->client = cl;
		res->acon.hints = SHMIF_RHINT_SUBREGION;
		res->group = i;
		res->slot = ind;
		arcan_shmif_resize(&res->acon, res->acon.w, res->acon.h);
		wl.groups[i].pg[ind].fd = res->acon.epipe;
		wl.groups[i].alloc |= 1 << ind;
		wl.client_count++;
	}

	return res;
}

static void destroy_client(struct bridge_client* cl)
{
	if (!cl)
		return;

	trace("destroy client");
	wl.client_count--;
	arcan_shmif_drop(&cl->acon);
	wl.groups[cl->group].alloc &= ~(1 << cl->slot);
	wl.groups[cl->group].pg[cl->slot].fd = -1;
	wl.groups[cl->group].pg[cl->slot].revents = 0;
	memset(&wl.groups[cl->group].cl[cl->slot],
		'\0', sizeof(struct bridge_client));
}

static bool prepare_groups(size_t cl_limit, int ctrlfd, int wlfd,
	size_t* nfd, struct pollfd** pfd, struct bridge_client** bcd)
{
	wl.n_groups = (cl_limit == 0 ? 1 : cl_limit / N_GROUP_SLOTS +
		!!(cl_limit % N_GROUP_SLOTS) * N_GROUP_SLOTS);

/*
 * allocate the tracking structures in advance to fit the maximum number
 * of clients (or default to 64) and then prepare indices to match.
 */
	size_t nelem = wl.n_groups * N_GROUP_SLOTS;
	wl.groups = malloc(sizeof(struct conn_group) * wl.n_groups);
	if (!wl.groups)
		return false;

	for (size_t i = 0; i < wl.n_groups; i++)
		wl.groups[i] = (struct conn_group){};

	*pfd = malloc(sizeof(struct pollfd) * nelem + 2);
	if (!*pfd)
		return false;

	*bcd = malloc(sizeof(struct bridge_client) * nelem);
	if (!bcd){
		free(*pfd);
		*pfd = NULL;
		return false;
	}

/* generate group indices */
	for (size_t i = 0; i < wl.n_groups; i++){
		wl.groups[i] = (struct conn_group){
			.cl = &(*bcd)[i*N_GROUP_SLOTS],
			.pg = &(*pfd)[2+i*N_GROUP_SLOTS]
		};
	}

/* and default polling flags */
	*nfd = nelem + 2;
	for (size_t i = 0; i < nelem+2; i++){
		(*pfd)[i] = (struct pollfd){
			.events = POLLIN | POLLERR | POLLHUP,
			.fd = -1
		};
	}

	(*pfd)[0].fd = ctrlfd;
	(*pfd)[1].fd = wlfd;
	wl.client_limit = cl_limit ? cl_limit : wl.n_groups * N_GROUP_SLOTS;

	return true;
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

	wl.n_groups = 4;

	for (size_t i = 1; i < argc; i++){
		if (strcmp(argv[i], "-egl") == 0){
			shm_egl = true;
		}
		else if (strcmp(argv[i], "-layout") == 0){
/* missing */
		}
		else if (strcmp(argv[i], "-dir") == 0){
			if (i == argc-1){
				return show_use("missing path to runtime dir", "");
			}
			i++;
			setenv("XDG_RUNTIME_DIR", argv[i], 1);
		}
		else if (strcmp(argv[i], "-max-cl") == 0){
			if (i < argc-1){
				return show_use("missing client limit argument", "");
			}
			i++;
			wl.client_limit = strtoul(argv[i], NULL, 10);
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
 * 2. limit to number of active connections
 * 3. default keyboard layout to provide (can possibly scan the dir
 *    and try to map to GEOHINT from the arcan_shmif_initial)
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
		if (!bind_display((EGLDisplay)display, wl.disp)){
			fprintf(stderr, "(eglBindWaylandDisplaYWL) failed\n");
			arcan_shmif_drop(&wl.control);
			return EXIT_FAILURE;
		}
	}

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

	wl.alive = true;

/*
 * init polling settings, allocate group storage etc. what may seem
 * weird here is the pfd/bcd bit - we partition clients into groups
 * in order to easier move the thread-groups around.
 */
	size_t nfd;
	struct pollfd* pfd;
	struct bridge_client* bcd;
	if (!prepare_groups(wl.client_limit,
		wl.control.epipe, wl_event_loop_get_fd(loop), &nfd, &pfd, &bcd))
		goto out;

	while(wl.alive){
		int sv = poll(pfd, nfd, -1);
		if (pfd[0].revents){
			sv--;
			if (!flush_bridge_events(&wl.control))
				break;
		}

		if (pfd[1].revents){
			sv--;
			wl_event_loop_dispatch(loop, 0);
		}

		for (size_t i = 2; i < nfd && sv; i++){
			if (pfd[i].revents){
				flush_client_events(&bcd[i-2]);
				sv--;
			}
		}

		wl_display_flush_clients(wl.disp);
	}

out:
	wl_display_destroy(wl.disp);
	arcan_shmif_drop(&wl.control);

	return EXIT_SUCCESS;
}
