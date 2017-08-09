/*
 * Copyright 2016-2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: https://github.com/letoram/arcan/wiki/wayland.md
 */

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

#define _GNU_SOURCE /* because *sigh* */
#define WANT_ARCAN_SHMIF_HELPER
#include <arcan_shmif.h>
#include <wayland-server.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <sys/mman.h>
#include <errno.h>
#include <poll.h>
#include <assert.h>

#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>
#include <xkbcommon/xkbcommon-compose.h>

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
struct comp_surf;
typedef void (*PFNGLEGLIMAGETARGETTEXTURE2DOESPROC) (EGLenum, EGLImage);
static PFNEGLQUERYWAYLANDBUFFERWL query_buffer;
static PFNEGLBINDWAYLANDDISPLAYWL bind_display;
static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC img_tgt_text;

/*
 * shared allocation functions, find_client takes a reference to a
 * wl client and tries to locate its bridge_client structure, or alloc
 * if it doesn't exist.
 */
static struct bridge_client* find_client(struct wl_client* cl);

/*
 * we use a slightly weird system of allocation groups and slots,
 * where each group act as a "up to 64-" bitmap of bridged surfaces
 * with the hope of using that as a structure to multiprocess and/or
 * multithread
 */
static void reset_group_slot(int group, int slot);

/*
 * This is one of the ugliest things around, so the client is supposed to
 * handle its own keymaps - why should it be easy for the compositor to know
 * what the f is going on. Anyhow, the idea is that you take and compile an
 * xkb- map, translate that to a simplified string, write that to a temporary
 * file, grab a descriptor to that file, send it to the client and unlink. On
 * linux, pretty much everything has access to proc.  This means /proc/pid/fd.
 * This means that even if we would map this ro, a client can open a rw
 * reference to this file. If we re-use this descriptor between multiple
 * clients - they can corrupt eachothers maps. To get around this idiocy,
 * we need to repeat this procedure for every client.
 */
static bool waybridge_instance_keymap(int* fd, int* fmt, size_t* sz);

static void destroy_comp_surf(struct comp_surf* surf);

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
static const size_t N_GROUP_SLOTS = 64;
struct conn_group {
	unsigned long long alloc;

/* pgroup is the actual allocation, rest is offset-maps */
	struct pollfd* pgroup;

	struct pollfd* wayland;
	struct pollfd* arcan;

/* split bridge_slot and pollfd just to be able to have them on the same
 * indice, but be able to throw everyhthing at poll */
	struct pollfd* pg;
	struct bridge_slot* slots;
};

static struct {
	size_t n_groups;
	struct conn_group* groups;

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

static uint64_t find_set64(uint64_t bmap)
{
	return __builtin_ffsll(bmap);
}

static char* load_keymap()
{
	trace("building keymap");
	struct xkb_context* ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	if (!ctx)
		return false;

/* load the keymap, XKB_ environments will get the map */
	struct xkb_keymap* map =
		xkb_keymap_new_from_names(ctx, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);

	if (!map){
		xkb_context_unref(ctx);
		return false;
	}
	char* keymap_str = xkb_map_get_as_string(map);
	xkb_keymap_unref(map);
	xkb_context_unref(ctx);
	return keymap_str;
}

static bool waybridge_instance_keymap(int* out_fd, int* out_fmt, size_t* out_sz)
{
	static char* keymap;
	if (!keymap)
		keymap = load_keymap();

	if (!keymap || !out_fd || !out_fmt || !out_sz)
		return false;

	trace("creating temporary keymap copy");

	char* chfn = NULL;
	if (-1 == asprintf(&chfn, "%s/wlbridge-kmap-XXXXXX",
		getenv("XDG_RUNTIME_DIR") ? getenv("XDG_RUNTIME_DIR") : "."))
			chfn = NULL;

	int fd;
	if (!chfn || (fd = mkstemp(chfn)) == -1){
		trace("make tempmap failed");
		free(chfn);
		return false;
	}
	unlink(chfn);

	*out_sz = strlen(keymap) + 1;
	if (*out_sz != write(fd, keymap, *out_sz)){
		trace("write keymap failed");
		close(fd);
	}

	*out_fd = fd;
	*out_fmt = WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1;

	return true;
}

static bool alloc_group_id(int type, int* groupid, int* slot, int fd)
{
	for (size_t i = 0; i < wl.n_groups; i++){
	uint64_t ind = find_set64(~wl.groups[i].alloc);
		if (0 == ind)
			continue;

/* go from counter to offset */
		ind--;

/* mark as allocated and store */
		trace("alloc_to(%d : %d)\n", i, ind);
		wl.groups[i].alloc |= 1 << ind;
		wl.groups[i].pg[ind].fd = fd;
		wl.groups[i].slots[ind].type = type;
		*groupid = i;
		*slot = ind;
#if 1
	for (size_t j = 0; j < sizeof(wl.groups[i].alloc)*8; j++){
		fprintf(stderr, "%c", (1 << j) & wl.groups[i].alloc ? 'x' : 'o');
	}
	fprintf(stderr, "\n");
#endif
		return true;
	}
	return false;
}

static void reset_group_slot(int group, int slot)
{
	wl.groups[group].alloc &= ~(1 << slot);
	wl.groups[group].pg[slot].fd = -1;
	wl.groups[group].pg[slot].revents = 0;
	wl.groups[group].slots[slot] = (struct bridge_slot){};

#if 1
	for (size_t i = 0; i < sizeof(wl.groups[group].alloc)*8; i++){
		fprintf(stderr, "%c", (1 << i) & wl.groups[group].alloc ? 'x' : 'o');
	}
	fprintf(stderr, "\n");
#endif

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
	trace("segment-req source(%s) -> %d\n", req->trace, alloc_id);
	arcan_shmif_enqueue(&cl->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.kind = req->segid,
		.ext.segreq.id = alloc_id++
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
			cont.hints = SHMIF_RHINT_SUBREGION | SHMIF_RHINT_VSIGNAL_EV;
			arcan_shmif_resize(&cont, cont.w, cont.h);
			struct acon_tag* tag = malloc(sizeof(struct acon_tag));
			cont.user = tag;
			*tag = (struct acon_tag){};

/* allocate a pollslot for the new surface, and set its event dispatch
 * to match what the request wanted */
			if (!alloc_group_id(SLOT_TYPE_SURFACE, &group, &ind, cont.epipe)){
				req->dispatch(req, NULL);
				arcan_shmif_drop(&cont);
				free(cont.user);
			}
			else {
				trace("new surface assigned to (%d:%d)\n", group, ind);
				tag->group = group;
				tag->slot = ind;
				if(!req->dispatch(req, &cont)){
					trace("surface request dispatcher rejected surface\n");
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
					cl->refc++;
					wl.groups[group].slots[ind].surface = req->source;
				}
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

static void destroy_comp_surf(struct comp_surf* surf)
{
	if (!surf)
		return;

	if (surf->acon.addr){
		struct acon_tag* tag = surf->acon.user;
		if (tag){
			trace("deregister-surface (%d:%d)\n", tag->group, tag->slot);
			reset_group_slot(tag->group, tag->slot);
		}
		else {
			trace("dropping unbound shmif-connection\n");
		}
		surf->client->refc--;
		surf->acon.user = NULL;
		arcan_shmif_drop(&surf->acon);
		free(tag);
	}

	memset(surf, '\0', sizeof(struct comp_surf));
	free(surf);
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

	trace("destroy client(%d:%d)", cl->group, cl->slot);

	arcan_shmif_drop(&cl->acon);
	assert(!cl->cursor.addr);
	assert(!cl->popup.addr);
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
		uint64_t mask = wl.groups[i].alloc;
		while (mask){
			uint64_t ind = find_set64(mask);
			if (!ind)
				continue;

			ind--;

			if (wl.groups[i].slots[ind].type == SLOT_TYPE_CLIENT){
				if (wl.groups[i].slots[ind].client.client == cl)
					return &wl.groups[i].slots[ind].client;
			}

			mask &= ~(1 << ind);
		}
	}

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
	res = &wl.groups[group].slots[ind].client;
	*res = (struct bridge_client){};

/*
 * pretty much always need to be ready for damaged surfaces so enable now
 */
	res->acon = con;
	res->client = cl;
	res->group = group;
	res->slot = ind;
	res->l_destr.notify = destroy_client;
	wl_client_add_destroy_listener(cl, &res->l_destr);

	return res;
}

/*
 * no point in a graceful recover for this particular set of allocations
 */
static void OUT_OF_MEMORY(const char* msg)
{
	fprintf(stderr, "%s\n", msg ? msg : "");
	exit(EXIT_FAILURE);
}

/*
 * we pair [arcan-wayland-clients] into groups of long-long-int slots
 * (matching allocation bitmap)
 */
static struct conn_group* prepare_groups(size_t count)
{
	struct conn_group* groups =
		malloc(sizeof(struct conn_group) * count);

	if (!groups)
		OUT_OF_MEMORY("prepare_groups");

	memset(groups, '\0', sizeof(struct conn_group) * count);
	for (size_t i = 0; i < count; i++){
		groups[i].pgroup = malloc(sizeof(struct pollfd) * (N_GROUP_SLOTS+2));
		groups[i].slots = malloc(sizeof(struct bridge_slot) * N_GROUP_SLOTS);

		if (!groups[i].pgroup || !groups[i].slots)
			OUT_OF_MEMORY("group/slot alloc");

		groups[i].pg = &groups[i].pgroup[2];
		groups[i].wayland = &groups[i].pgroup[0];
		groups[i].arcan = &groups[i].pgroup[1];

		for (size_t j = 0; j < N_GROUP_SLOTS+2; j++){
			groups[i].pgroup[j] = (struct pollfd){
				.events = POLLIN | POLLERR | POLLHUP,
				.fd = -1
			};
		}

		for (size_t j = 0; j < N_GROUP_SLOTS; j++){
			groups[i].slots[j] = (struct bridge_slot){};
		}
	}

	return groups;
}

static int show_use(const char* msg, const char* arg)
{
	fprintf(stdout, "%s%s", msg, arg ? arg : "");
	fprintf(stdout, "Use: waybridge [arguments]\n"
"\t-shm-egl          pass shm- buffers as gl textures\n"
"\t-no-egl           disable the wayland-egl extensions\n"
"\t-no-compositor    disable the compositor protocol\n"
"\t-no-subcompositor disable the sub-compositor protocol\n"
"\t-no-subsurface    disable the sub-surface protocol\n"
"\t-no-shell         disable the shell protocol\n"
"\t-no-shm           disable the shm protocol\n"
"\t-no-seat          disable the seat protocol\n"
"\t-no-xdg           disable the xdg protocol\n"
"\t-no-output        disable the output protocol\n"
"\t-layout lay       set keyboard layout to <lay>\n"
"\t-dir dir          override XDG_RUNTIME_DIR with <dir>\n");
	return EXIT_FAILURE;
}

static bool process_group(struct conn_group* group)
{
	int sv = poll(group->pgroup, N_GROUP_SLOTS+2, -1);

/*
 * If a client is created here, we can retrieve the actual connection here (and
 * not the epoll fd) with wl_client_get_fd and we can then add / remove the
 * client from the event loop with wl_event_loop_get_fd and that's just an
 * epoll-fd. We can remove the client from the epoll-fd with epoll_ctl(fd,
 * EPOLL_CTL_DEL, clfd, NULL) All that is left is to find a way to notice when
 * a client connects and break out of the loop somehow. Oh well, good old
 * setjmp.
 */
	if (group->wayland && group->wayland->revents){
		wl_event_loop_dispatch(
			wl_display_get_event_loop(wl.disp), 0);
		sv--;
	}

	if (group->arcan && group->arcan->revents){
		flush_bridge_events(&wl.control);
		sv--;
	}

	for (size_t i = 0; i < N_GROUP_SLOTS && sv > 0; i++){
		if (group->pg[i].revents){
			sv--;
			switch(group->slots[i].type){
			case SLOT_TYPE_CLIENT:
				flush_client_events(&group->slots[i].client, NULL, 0);
			break;
			case SLOT_TYPE_SURFACE:
				if (group->slots[i].surface)
					flush_surface_events(group->slots[i].surface);
			break;
			}
		}
	}

/*
 * When we have clients with pending segment requests, we can't use the normal
 * flush mechanism for clients with requests pending.
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
	return true;
}

int main(int argc, char* argv[])
{
	struct arg_arr* aarr;
	int shm_egl = false;

/* for each wayland protocol or subprotocol supported, add a corresponding
 * field here, and then command-line argument passing to disable said protocol.
 */
	struct {
		int compositor, shell, shm, seat, output, egl, xdg, subcomp, ddev;
	} protocols = {
		.compositor = 3,
		.shell = 1,
		.shm = 1,
		.seat = 5,
		.output = 2,
		.egl = 1,
		.xdg = 1,
		.subcomp = 1,
		.ddev = 1
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
		else if (strcmp(argv[i], "-egl-device") == 0){
			if (i == argc-1){
				fprintf(stderr, "missing egl device argument\n");
				return EXIT_FAILURE;
			}
			i++;
			setenv("ARCAN_RENDER_NODE", argv[i], 1);
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
		else if (strcmp(argv[i], "-no-subcompositor") == 0)
			protocols.subcomp = 0;
		else if (strcmp(argv[i], "-no-data-device") == 0)
			protocols.ddev = 0;
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

/*
 * The reason for running a control connection is to get access to the initial
 * state in terms of display, output etc. so we can answer those requests from
 * a client BEFORE actually allocating connections for each client. This makes
 * the multiplexing etc. a bit more annoying since we steer away from epoll or
 * kqueue or other OS specific multiplexation mechanisms.
 */
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
 * This is a special case, if RENDER_NODE points to a card node, and arcan
 * has been setup allowing clients to try and negotiate, this function will
 * actually do the deed.
 */
		uintptr_t devnode;
		arcan_shmifext_dev(&wl.control, &devnode, false);

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
	if (protocols.subcomp)
		wl_global_create(wl.disp, &wl_subcompositor_interface,
			protocols.subcomp, NULL, &bind_subcomp);
	if (protocols.ddev)
		wl_global_create(wl.disp, &wl_data_device_manager_interface,
			protocols.ddev, NULL, &bind_ddev);

	trace("wl_display() finished");

	wl.alive = true;

/*
 * This is just a temporary / ugly "64 restriction" in that this is how many
 * clients and surfaces we run per group. When a group is completely full, it's
 * time to slice of a new thread/process and continue there - but that's
 * something to worry about when we have all the features in place.
 */
	wl.groups = prepare_groups(1);
	wl.n_groups = 1;
	wl.groups[0].wayland->fd = wl_event_loop_get_fd(wl_display_get_event_loop(wl.disp));
	wl.groups[0].arcan->fd = wl.control.epipe;

	while(wl.alive && process_group(&wl.groups[0])){}

	wl_display_destroy(wl.disp);
	arcan_shmif_drop(&wl.control);

	return EXIT_SUCCESS;
}
