/*
 * Copyright 2016-2017, Björn Ståhl
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
static void reset_group_slot(int group, int slot);

/* static PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display; */

/*
 * For tracking allocations in arcan, split into bitmapped groups allocated/set
 * on startup. Allocation policy is first free slot, though no compaction
 * between groups. Doing it this way makes thread-group assignments etc.
 * easier if that ever becomes a need.
 *
 * Each group [64 bitmap] has a number of slots, and corresponding
 * poll struct entries.
 */
static const size_t N_GROUP_SLOTS = sizeof(long long int) * 8;
struct conn_group {
	long long int alloc;

/* 2 padding for the wl server socket and bridge- connection */
	struct pollfd* pg;
	struct bridge_slot* slot;
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

/*
 * implements the actual dispatch from events on shmif- to surface-
 * and shell- specific event handlers
 */
#include "shmifevmap.c"

/*
 * allocation support functions:
 * we track resources in contexts of thread-group and slots. Each slot
 * can cover either a surface or a client-control connection. Simply an
 * allocation bitmap, a type indicator and union structure.
 */
static bool alloc_group_id(int type, int* groupid, int* slot, int fd)
{
	for (size_t i = 0; i < wl.n_groups; i++){
		long long int ind = ffs(~wl.groups[i].alloc);
		if (0 == ind)
			continue;

		ind--;
		wl.groups[i].alloc |= 1 << ind;
		wl.groups[i].pg[ind].fd = fd;
		wl.groups[i].slot[ind].type = type;
		*groupid = i;
		*slot = ind;
		return true;
	}
	return false;
}

static void reset_group_slot(int group, int slot)
{
	wl.groups[group].alloc &= ~(1 << slot);
	wl.groups[group].pg[slot].fd = -1;
	wl.groups[group].pg[slot].revents = 0;
	wl.groups[group].slot[slot] = (struct bridge_slot){};
}

/*
 * this is the more complicated step in the entire process, i.e.  pseudo-asynch
 * resource allocation between the two and the decision if that should be
 * deferred or not.
 */
static bool request_surface(
	struct bridge_client* cl, struct surface_request* req)
{
	trace("requesting-segment");
	struct arcan_event acqev = {0};
	if (!cl || !req || !req->dispatch){
		fprintf(stderr, "request_surface called with bad request\n");
		return false;
	}

/*
 * IF the primary connection is unused, we can simply return that UNLESS
 * the request type is a CURSOR or a POPUP (both are possible in XDG).
 */
	static uint32_t alloc_id = 0xbabe;
	arcan_shmif_enqueue(&cl->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.kind = req->segid,
		.ext.segreq.id = alloc_id
	});
	struct arcan_event* pqueue;
	ssize_t pqueue_sz;

/*
 * This is the problematic part, basically it will block until we get accept or
 * reject on the segment request. Since we may have many clients, the possible
 * latency (say 0..16ms figure right now, lower later) might not be acceptable.
 *
 * In that case, we have the option of deferring the dispatch as per the
 * descriptor hack further below, or to thread, or to multiprocess.
 */
	if (arcan_shmif_acquireloop(&cl->acon, &acqev, &pqueue, &pqueue_sz)){
		int group, ind;
		if (acqev.tgt.kind != TARGET_COMMAND_NEWSEGMENT){
			req->dispatch(req, NULL);
		}
		else{
			struct arcan_shmif_cont cont =
				arcan_shmif_acquire(&cl->acon, NULL, req->segid, 0);
			cont.hints = SHMIF_RHINT_SUBREGION;
			arcan_shmif_resize(&cont, cont.w, cont.h);
			struct acon_tag* tag = malloc(sizeof(struct acon_tag));
			cont.user = tag;
			*tag = (struct acon_tag){};
			tag->group = group;
			tag->slot = ind;

/* allocate a pollslot for the new surface, and set its event dispatch
 * to match what the request wanted */
			if (!alloc_group_id(SLOT_TYPE_SURFACE, &group, &ind, cont.epipe)){
				req->dispatch(req, NULL);
				arcan_shmif_drop(&cont);
				reset_group_slot(group, ind);
				free(cont.user);
			}
			else if(!req->dispatch(req, &cont)){
/* caller doesn't want the surface anymore? */
				arcan_shmif_drop(&cont);
				reset_group_slot(group, ind);
				free(cont.user);
			}
/* everything went well, hook up the last reference, the other paths
 * will come from the wayland-socket dispatch and from the:
 * poll -> [group, ind] -> default event handler for type ->
 * [if SURFACE]:comp_surf(dispatch) */
			else{
				wl.groups[group].slot[ind].surface = req->source;
			}
		}
	}
	else
		req->dispatch(req, NULL);

/* FIXME: we also need to flush the accumulated events, this should
 * just be to flush_client_events with each entry of the event-queue */
	if (pqueue_sz > 0){
		printf("flush / free events\n");
	}

	return true;
}

/*
 * deallocate the group/slot assigned to a client, and drop its
 * corresponding arcan-shmif connection.
 */
static void destroy_client(struct wl_listener* l, void* data)
{
	struct bridge_client* cl;
	cl = wl_container_of(l, cl, l_destr);

	if (!cl || !(wl.groups[cl->group].alloc & (1 << cl->slot))){
		trace("destroy_client(), struct doesn't match bitmap");
		return;
	}

	trace("destroy client()");
	wl.client_count--;
	arcan_shmif_drop(&cl->acon);
	reset_group_slot(cl->group, cl->slot);
}

/*
 * [BLOCKING]
 * Match a wayland client with its local resources, or, if not found, allocate
 * and connect. This is one key spot to determine if we should look into
 * multithread-multiprocess due to stalls imposed by connect, resize or
 * subsegment requests.
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

			if (wl.groups[i].slot[ind].type == SLOT_TYPE_CLIENT){
				if (wl.groups[i].slot[ind].client.client == cl)
					return &wl.groups[i].slot[ind].client;
			}

			mask &= ~(1 << ind);
		}
	}

	if (wl.client_limit == wl.client_count)
		return NULL;

	trace("connecting new bridge client");
/*
 * [POSSIBLE FORK SLOT]
 * if (0 == fork()){
		cl->forked = true;
		wl.alive = false;
	}
 */

/* FIRST connect a new bridge to arcan, this could be circumvented and
 * simply treat each 'surface' as a bridge- connection, but it would break
 * the option to track origin. */
	struct arcan_shmif_cont con = arcan_shmif_open(SEGID_BRIDGE_WAYLAND, 0, NULL);
	if (!con.addr){
		trace("failed to open segid-bridge-wayland connection to arcan server");
		free(res);
		return NULL;
	}

/* THEN allocate a local resource */
	int group, ind;
	if (!alloc_group_id(SLOT_TYPE_CLIENT, &group, &ind, con.epipe)){
		trace("couldn't allocate bridge client slot");
		arcan_shmif_drop(&con);
		free(res);
		return NULL;
	}

/* There's an ugly little mismatch here in that a client connection in arcan
 * forcibly implies a surface, while-as in wayland, a client can connect and
 * just sit there - or create one surface, destroy it and create a new one.
 *
 * This leaves us the problem of what to do with this wasted connection, either
 * we treat it as a local 'cache' and re-use this when a new surface is
 * allocated and it isn't already in used, and the surface is not a popup or
 * mouse cursor. Since these NEED to be allocated through an existing
 * connection, we can't simply ignore connecting at this stage.
 */
	trace("new client assigned to (%d:%d)", group, ind);
	res = &wl.groups[group].slot[ind].client;
	*res = (struct bridge_client){};

/*
 * pretty much always need to be ready for damaged surfaces so enable now
 */
	res->acon = con;
	res->client = cl;
	res->group = group;
	res->slot = ind;
	res->l_destr.notify = destroy_client;
	wl.client_count++;
	wl_client_add_destroy_listener(cl, &res->l_destr);

	return res;
}

static bool prepare_groups(size_t cl_limit, int ctrlfd, int wlfd,
	size_t* nfd, struct pollfd** pfd, struct bridge_slot** bcd)
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

	*bcd = malloc(sizeof(struct bridge_slot) * nelem);
	if (!bcd){
		free(*pfd);
		*pfd = NULL;
		return false;
	}

/* generate group indices */
	for (size_t i = 0; i < wl.n_groups; i++){
		wl.groups[i] = (struct conn_group){
			.slot = &(*bcd)[i*N_GROUP_SLOTS],
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
"\t-shm-egl        pass shm- buffers as gl textures\n"
"\t-no-egl         disable the wayland-egl extensions\n"
"\t-no-compositor  disable the compositor protocol\n"
"\t-no-shell       disable the shell protocol\n"
"\t-no-shm         disable the shm protocol\n"
"\t-no-seat        disable the seat protocol\n"
"\t-no-xdg         disable the xdg protocol\n"
"\t-no-output      disable the output protocol\n"
"\t-layout lay     set keyboard layout to <lay>\n"
"\t-dir dir        override XDG_RUNTIME_DIR with <dir>\n"
"\t-max-cl lim     limit the amount of concurrent clients to <lim>\n");
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
		int compositor, shell, shm, seat, output, egl, xdg;
	} protocols = {
		.compositor = 3,
		.shell = 1,
		.shm = 1,
		.seat = 4,
		.output = 2,
		.egl = 1,
		.xdg = 1
	};

	for (size_t i = 1; i < argc; i++){
		if (strcmp(argv[i], "-shm-egl") == 0){
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
		else if (strcmp(argv[i], "-no-egl") == 0)
			protocols.egl = 0;
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
		else if (strcmp(argv[i], "-no-xdg") == 0)
			protocols.xdg = 0;
		else
			return show_use("unknown argument (%s)\n", argv[i]);
	}

	wl.disp = wl_display_create();
	if (!wl.disp){
		fprintf(stderr, "Couldn't create wayland display\n");
		return EXIT_FAILURE;
	}

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

/*
 * we need an acelerated graphics setup that we can use to tie into mesa/gl
 * in order for the whole WLDisplay integration that goes on (...)
 * the 'upload texture here, pass handle onwards' option to accelerate _shm
 * and get rid of the extra copy is setup per client, not here. It is thus
 * possible to disable EGL wayland clients and still have that feature.
 */
		struct arcan_shmifext_setup cfg = arcan_shmifext_defaults(&wl.control);
		cfg.builtin_fbo = false;
		if (SHMIFEXT_OK != arcan_shmifext_setup(&wl.control, cfg)){
			fprintf(stderr, "Couldn't setup EGL context/display\n");
			arcan_shmif_drop(&wl.control);
			return EXIT_FAILURE;
		}

/*
 * note: the device node matching is part of the bind_display action and the
 * server, so it might be possible to do the GPU swap for new clients on
 * DEVICEHINT by rebinding or by eglUnbindWaylandDisplayWL
 */
		uintptr_t display;
		arcan_shmifext_egl_meta(&wl.control, &display, NULL, NULL);
		wl.display = eglGetDisplay((EGLDisplay)display);
		if (!bind_display((EGLDisplay)display, wl.disp)){
			fprintf(stderr, "(eglBindWaylandDisplayWL) failed\n");
			arcan_shmif_drop(&wl.control);
			return EXIT_FAILURE;
		}
	}

	wl_display_add_socket_auto(wl.disp);

/*
 * This approach of caller- control in regards to announced protocols helps
 * testing / breaking clients as it's easy to run into 'woops we only tested
 * against weston/mutter exposed sets'.
 */
	if (protocols.compositor)
		wl_global_create(wl.disp, &wl_compositor_interface,
			protocols.compositor, NULL, &bind_comp);
	if (protocols.shell)
		wl_global_create(wl.disp, &wl_shell_interface,
			protocols.shell, NULL, &bind_shell);
	if (protocols.shm){
/* NOTE: register additional formats? */
		wl_display_init_shm(wl.disp);
	}
	if (protocols.seat)
		wl_global_create(wl.disp, &wl_seat_interface,
			protocols.seat, NULL, &bind_seat);
	if (protocols.output)
		wl_global_create(wl.disp, &wl_output_interface,
			protocols.output, NULL, &bind_output);
	if (protocols.xdg)
		wl_global_create(wl.disp, &zxdg_shell_v6_interface,
			protocols.xdg, NULL, &bind_xdg);

	struct wl_event_loop* loop = wl_display_get_event_loop(wl.disp);
	trace("wl_display() finished");

	wl.alive = true;

/*
 * init polling settings, allocate group storage etc. what may seem
 * weird here is the pfd/bcd bit - we partition clients into groups
 * that can later be split out into separate thread dispatches or
 * processes.
 */
	size_t nfd;
	struct pollfd* pfd;
	struct bridge_slot* bcd;
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

/*
 * If a client is created here, we can retrieve the actual connection here (and
 * not the epoll fd) with wl_client_get_fd and we can then add / remove the
 * client from the event loop with wl_event_loop_get_fd and that's just an
 * epoll-fd. We can remove the client from the epoll-fd with epoll_ctl(fd,
 * EPOLL_CTL_DEL, clfd, NULL) All that is left is to find a way to notice when
 * a client connects and break out of the loop somehow. Oh well, good old
 * setjmp.
 */
		if (pfd[1].revents){
			sv--;
			wl_event_loop_dispatch(loop, 0);
		}

/* the +2 -2 everywhere is just that pollset also has room for bridge
 * connection and epoll-fd, not particularly pretty but not a priority to
 * refactor either. */
		for (size_t i = 2; i < nfd && sv; i++){
			if (pfd[i].revents){
				if (bcd[i-2].type == SLOT_TYPE_CLIENT){
					trace("client event\n");
					flush_client_events(&bcd[i-2].client, NULL, 0);
				}
				else if (bcd[i-2].type == SLOT_TYPE_SURFACE){
					trace("surface event\n");
					flush_surface_events(bcd[i-2].surface);
				}
				sv--;
			}
		}

/*
 * When we have clients with pending segment requests, we
 * can't use the normal flush mechanism for clients with requests
 * pending.
 *
 * Instead, we can iterate this ourselves and simply go:
 * list = wl_display_get_client_list;
 * wl_client* client, *next;
 * wl_list_for_each_safe(client, next, &list, link){
 *  lookup-client
 *  check if pending, then wait
 * 	ret = wl_conenection_flush(client->connection);
 * }
 */
		wl_display_flush_clients(wl.disp);
	}

out:
	wl_display_destroy(wl.disp);
	arcan_shmif_drop(&wl.control);

	return EXIT_SUCCESS;
}
