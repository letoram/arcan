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
#include <signal.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <sys/mman.h>
#include <errno.h>
#include <poll.h>
#include <assert.h>

#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>
#include <xkbcommon/xkbcommon-compose.h>

/*
 * only linux
 */
#ifdef ENABLE_SECCOMP
	#include <sys/prctl.h>
	#include <seccomp.h>
#endif

/*
 * EGL- details needed for handle translation
 */
struct comp_surf;

/*
 * shared allocation functions, find_client takes a reference to a
 * wl client and tries to locate its bridge_client structure, or alloc
 * if it doesn't exist.
 */
static struct bridge_client* find_client(struct wl_client* cl);

/*
 * Used as a reaction to _RESET[HARD] when a client is forcibly migrated or
 * recovers from a crash. Enumerate all related surfaces, re-request and then
 * re-viewport.
 */
static void rebuild_client(struct bridge_client*);

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
static bool waybridge_instance_keymap(
	struct bridge_client* bcl, int* fd, int* fmt, size_t* sz);

static void destroy_comp_surf(struct comp_surf* surf, bool clean);

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
/* allocation bitmaps to partition into poll and alloc- groups */
	size_t n_groups;
	struct conn_group* groups;

	EGLDisplay display;
	struct wl_display* disp;
/* set to false after initialization to terminate */
	bool alive;

/* metadata on accelerated graphics */
	struct wl_drm* drm;

/* initial display parameters retrieved from the control connection */
	struct arcan_shmif_initial init;
	struct arcan_shmif_cont control;

/*
 * fork out new clients and only use this process as a display
 * discovery mechanism
 */
	bool fork_mode;

/*
 * all surfaces start with accel-transfer disabled, only sourced
 * dma-buffers will actully be passed on as-is
 */
	int default_accel_surface;

/*
 * this is a workaround for shm- buffers and relates to clients that just push
 * a new buffer as soon as the old is released, causing excessive double-
 * buffering as we already have a copy in one way or another.
 */
	bool defer_release;

/*
 * accepted trace level
 */
	int trace_log;

/*
 * single- client exit- on terminate mode
 */
	bool exec_mode;
} wl = {
	.default_accel_surface = -1
};

enum trace_levels {
	TRACE_ALLOC   = 1,
	TRACE_DIGITAL = 2,
	TRACE_ANALOG  = 4,
	TRACE_SHELL   = 8,
	TRACE_REGION  = 16,
	TRACE_DDEV    = 32,
	TRACE_SEAT    = 64,
	TRACE_SURF    = 128,
	TRACE_DRM     = 256,
	TRACE_ALERT   = 512
};

static inline void trace(int level, const char* msg, ...)
{
	if (!wl.trace_log || !(level & wl.trace_log))
		return;

	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
		fprintf(stderr, "\n");
	va_end( args);
	fflush(stderr);
}

#define __FILENAME__ (strrchr(__FILE__, '/')?strrchr(__FILE__, '/') + 1 : __FILE__)
#define trace(X, Y, ...) do { trace(X, "%s:%d:%s(): " \
	Y, __FILENAME__, __LINE__, __func__,##__VA_ARGS__); } while (0)

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

static void dump_alloc(int i, char* domain, bool wmode)
{
/* debug output to see slot and source */
	if (wmode || (wl.trace_log & TRACE_ALLOC)){
		char alloc_buf[sizeof(wl.groups[i].alloc) * 8 + 1] = {0};
		for (size_t j = 0; j < sizeof(wl.groups[i].alloc)*8;j++){
			alloc_buf[j] =
				(1 << j) & wl.groups[i].alloc ?
				wl.groups[i].slots[j].idch : '_';
		}
		if (wmode){
			write(STDERR_FILENO, alloc_buf, sizeof(alloc_buf));
			write(STDERR_FILENO, "\n", 1);
		}
		else
			trace(TRACE_ALLOC, "%s,slotmap:%s", domain?domain:"", alloc_buf);
	}
}

static bool load_keymap(struct xkb_stateblock* dst)
{
	trace(TRACE_ALLOC, "building keymap");
	dst->context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	if (!dst->context)
		return false;

/* load the keymap, XKB_ environments will get the map */
	dst->map = xkb_keymap_new_from_names(
		dst->context, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);

	if (!dst->map){
		xkb_context_unref(dst->context);
		dst->context = NULL;
		return false;
	}

	dst->map_str = xkb_map_get_as_string(dst->map);
	dst->state = xkb_state_new(dst->map);
	return true;
}

static void free_kbd_state(struct xkb_stateblock* kbd)
{
	if (kbd->context){
		xkb_context_unref(kbd->context);
		kbd->context = NULL;
	}

	if (kbd->map){
		xkb_keymap_unref(kbd->map);
		kbd->map = NULL;
	}

	if (kbd->state){
		xkb_state_unref(kbd->state);
		kbd->state = NULL;
	}

	kbd->map_str = NULL; /* should live/die with map */
}

static bool waybridge_instance_keymap(
	struct bridge_client* cl, int* out_fd, int* out_fmt, size_t* out_sz)
{
	if (!out_fd || !out_fmt || !out_sz)
		return false;

	if (!load_keymap(&cl->kbd_state))
		return false;

	trace(TRACE_ALLOC, "creating temporary keymap copy");

	char* chfn = NULL;
	if (-1 == asprintf(&chfn, "%s/wlbridge-kmap-XXXXXX",
		getenv("XDG_RUNTIME_DIR") ? getenv("XDG_RUNTIME_DIR") : "."))
			chfn = NULL;

	int fd;
	if (!chfn || (fd = mkstemp(chfn)) == -1){
		trace(TRACE_ALLOC, "make tempmap failed");
		free(chfn);
		free_kbd_state(&cl->kbd_state);
		return false;
	}
	unlink(chfn);

	*out_sz = strlen(cl->kbd_state.map_str) + 1;
	if (*out_sz != write(fd, cl->kbd_state.map_str, *out_sz)){
		trace(TRACE_ALLOC, "write keymap failed");
		close(fd);
		free(chfn);
		free_kbd_state(&cl->kbd_state);
		return false;
	}

	free(chfn);
	*out_fd = fd;
	*out_fmt = WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1;

	return true;
}

static bool alloc_group_id(int type, int* groupid, int* slot, int fd, char d)
{
	for (size_t i = 0; i < wl.n_groups; i++){
	uint64_t ind = find_set64(~wl.groups[i].alloc);
		if (0 == ind)
			continue;

/* go from counter to offset */
		ind--;

/* mark as allocated and store */
		trace(TRACE_ALLOC, "alloc_to(%d : %d)", i, ind);
		wl.groups[i].alloc |= 1 << ind;
		wl.groups[i].pg[ind].fd = fd;
		wl.groups[i].slots[ind].type = type;
		wl.groups[i].slots[ind].idch = d;
		*groupid = i;
		*slot = ind;

		dump_alloc(i, "alloc", false);

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

	dump_alloc(group, "reset", false);
}

/*
 * this is the more complicated step in the entire process, i.e.  pseudo-asynch
 * resource allocation between the two and the decision if that should be
 * deferred or not.
 */
static bool request_surface(
	struct bridge_client* cl, struct surface_request* req, char idch)
{
	trace(TRACE_ALLOC, "requesting-segment");
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
	trace(TRACE_ALLOC, "segment-req source(%s) -> %d", req->trace, alloc_id);
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
				arcan_shmif_acquire(&cl->acon, NULL, req->segid, SHMIF_DISABLE_GUARD);
			cont.hints = SHMIF_RHINT_SUBREGION | SHMIF_RHINT_VSIGNAL_EV;
			arcan_shmif_resize(&cont, cont.w, cont.h);
			struct acon_tag* tag = malloc(sizeof(struct acon_tag));
			cont.user = tag;
			*tag = (struct acon_tag){};

/* allocate a pollslot for the new surface, and set its event dispatch
 * to match what the request wanted */
			if (!alloc_group_id(SLOT_TYPE_SURFACE, &group, &ind, cont.epipe, idch)){
				req->dispatch(req, NULL);
				arcan_shmif_drop(&cont);
				free(cont.user);
			}
			else {
				trace(TRACE_ALLOC, "new surface assigned to (%d:%d) token: %"PRIu32,
					group, ind, cont.segment_token);
				tag->group = group;
				tag->slot = ind;
				if(!req->dispatch(req, &cont)){
					trace(TRACE_ALLOC, "surface request dispatcher rejected surface");
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
 * just be to flush_client_events with each entry of the event-queue -
 * since we don't use the control connection for anything, this only
 * mask trivial events though. There is the offchance that we'd get
 * something more serious, like a migrate that would trigger a rebuild */
	if (pqueue_sz > 0){
	}

	return true;
}

static void destroy_comp_surf(struct comp_surf* surf, bool clean)
{
	if (!surf)
		return;

/* remove old listener (always) */
	if (surf->l_bufrem_a){
		surf->l_bufrem_a = false;
		wl_list_remove(&surf->l_bufrem.link);
	}

	if (surf->acon.addr){
		struct acon_tag* tag = surf->acon.user;
		if (tag){
			trace(TRACE_ALLOC, "deregister-surface (%d:%d)", tag->group, tag->slot);
			reset_group_slot(tag->group, tag->slot);
		}
		else {
			trace(TRACE_ALLOC, "dropping unbound shmif-connection");
		}
		surf->client->refc--;
		surf->acon.user = NULL;
		arcan_shmif_drop(&surf->acon);
		free(tag);
	}
	else
		trace(TRACE_ALLOC, "destroy comp on non-acon surface\n");

	if (clean){
		memset(surf, '\0', sizeof(struct comp_surf));
		free(surf);
	}
}

/*
 * delete all resources/surfaces bound to a specific bridge client,
 * this is set as an event listener for destruction on a client
 */
static void destroy_client(struct wl_listener* l, void* data)
{
	struct bridge_client* cl = wl_container_of(l, cl, l_destr);

	if (!cl || !(wl.groups[cl->group].alloc & (1 << cl->slot))){
		trace(TRACE_ALLOC, "destroy_client(), struct doesn't match bitmap");
		return;
	}

/*
 * There's the chance that we have dangling surfaces for a client that
 * just exits uncleanly. If these doesn't get cleaned up here, we'll
 * UAF next cycle
 */

/* each 'group', skip those with no alloc- bits */
	for (size_t i = 0; i < wl.n_groups; i++){
		if (0 == find_set64(~wl.groups[i].alloc))
			continue;

/* each surface in group */
		for (size_t j = 0; j < sizeof(wl.groups[i].alloc)*8; j++){
			if ( !((1 << j) & wl.groups[i].alloc) )
				continue;

/* check if it belongs to the client we want to destroy */
			if (wl.groups[i].slots[j].type == SLOT_TYPE_SURFACE &&
				wl.groups[i].slots[j].surface &&
				(wl.groups[i].slots[j].surface->client == cl)){
				trace(TRACE_ALLOC,"destroy_client->dangling surface(%zu:%zu:%c)",
					i, j, wl.groups[i].slots[j].idch);
				destroy_comp_surf(wl.groups[i].slots[j].surface, true);
			}
		}
	}
	trace(TRACE_ALLOC, "destroy client(%d:%d)", cl->group, cl->slot);

	arcan_shmif_drop(&cl->acon);
	if (cl->acursor.addr){
		struct acon_tag* tag = cl->acursor.user;
		trace(TRACE_ALLOC, "destroy client-cursor(%d:%d)", tag->group, tag->slot);
		arcan_shmif_drop(&cl->acursor);
		reset_group_slot(tag->group, tag->slot);
	}
	reset_group_slot(cl->group, cl->slot);
	trace(TRACE_ALLOC, "client destroyed");

/* the connection has been dealt with, give up */
	if (wl.exec_mode){
		wl.alive = false;
	}
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

/*
 * we can get away with this since we are comprised of asynch signal safe
 * calls, no mallocs or threads that would be in a pending state - the
 * dangerous parts - mostly EGL aren't used or allocated in the main process
 */
	trace(TRACE_ALLOC, "connecting new bridge client");

/* FIRST connect a new bridge to arcan, this could be circumvented and simply
 * treat each 'surface' as a bridge- connection, but it would break the option
 * to track origin. There's also the problem of creating the abstract display
 * as we don't have the display properties until the first connection has been
 * made */
	struct arcan_shmif_cont con =
		arcan_shmif_open(SEGID_BRIDGE_WAYLAND, 0, NULL);
	if (!con.addr){
		trace(TRACE_ALLOC,
			"failed to open segid-bridge-wayland connection to arcan server");
		free(res);
		return NULL;
	}

/* THEN allocate a local resource */
	int group, ind;
	if (!alloc_group_id(SLOT_TYPE_CLIENT, &group, &ind, con.epipe, 'C')){
		trace(TRACE_ALLOC, "couldn't allocate bridge client slot");
		arcan_shmif_drop(&con);
		free(res);
		return NULL;
	}

/* There's an ugly little mismatch here in that a client connection in arcan
 * forcibly implies a surface-buffer-role bond at the same time, while-as in
 * wayland, a client can connect and just sit there - or create one surface,
 * destroy it and create a new one.
 *
 * This leaves us the problem of what to do with this wasted connection, either
 * we treat it as a local 'cache' and re-use this when a new surface is
 * allocated and it isn't already in used, and the surface is not a popup or
 * mouse cursor. Since these NEED to be allocated through an existing
 * connection, we can't simply ignore connecting at this stage.
 */
	trace(TRACE_ALLOC, "new client assigned to (%d:%d)", group, ind);
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

static void rebuild_client(struct bridge_client* bcl)
{
/* enumerate all surfaces, find those that are tied to the bridge,
 * rerequest the underlying segment and apply it to that slot. */
	struct {
		struct comp_surf* surf;
		struct arcan_shmif_cont new;
		int ind;
		int group;
	} surfaces[wl.n_groups * 64];
	size_t surf_count = 0;
	memset(surfaces, '\0', sizeof(surfaces[0]) * wl.n_groups * 64);

	trace(TRACE_ALERT, "rebuild_client");

/* update the pollset with the new descriptor */
	wl.groups[bcl->group].pg[bcl->slot].fd = bcl->acon.epipe;
	struct comp_surf* cursor_surface = NULL;
	size_t cs_group = 0;
	size_t cs_ind = 0;

	for (size_t i = 0; i < wl.n_groups; i++){
		uint64_t mask = wl.groups[i].alloc;
		while (mask){
			uint64_t ind = find_set64(mask);
			if (!ind)
				continue;
			ind--;
			mask &= ~(1 << ind);

/* if it is not marked as a normal surface, or not actually in-use, skip */
			if (wl.groups[i].slots[ind].type != SLOT_TYPE_SURFACE ||
				!wl.groups[i].slots[ind].surface)
				continue;

/* if it is not tied to the requested client, ignore */
			if (wl.groups[i].slots[ind].surface->client != bcl)
				continue;

/* rcons (mouse cursor), just disassociate, the next time the cursor
 * is set, we'll reassociate */
			if (wl.groups[i].slots[ind].surface->rcon){
				wl.groups[i].slots[ind].surface->rcon = NULL;
				cursor_surface = wl.groups[i].slots[ind].surface;
				cs_group = i;
				cs_ind = ind;
				continue;
			}

			surfaces[surf_count].group = i;
			surfaces[surf_count].ind = ind;
			surfaces[surf_count].surf = wl.groups[i].slots[ind].surface;
			trace(TRACE_ALERT, "queue surface for rebuild: %c\n",
				wl.groups[i].slots[ind].idch);
			surf_count++;
		}
	}

/* [Pass 1]
 * Enumerate all the client-bound surfaces and re-request them, if one fails
 * though - we're SOL, might need a panic- hook in the comp_surf in order to
 * forward deletion to the client so it knows that some surface died, though
 * this will likely just make the thing crash. */
	static uint32_t ralloc_id = 0xbeba;
	for (size_t i = 0; i < surf_count; i++){
		struct comp_surf* surf = surfaces[i].surf;
		trace(TRACE_ALERT, "rebuild, request %s => %d (%"PRIxPTR",%"PRIxPTR")",
			surf->tracetag, arcan_shmif_segkind(&surf->acon),
			(uintptr_t) surf->acon.addr, (uintptr_t) surf->acon.priv);

		arcan_shmif_enqueue(&bcl->acon, &(struct arcan_event){
			.ext.kind = ARCAN_EVENT(SEGREQ),
			.ext.segreq.kind = arcan_shmif_segkind(&surf->acon),
			.ext.segreq.id = ralloc_id++
		});

/* The pqueue should really not have any interesting events as we only use
 * the bridge for allocation (except exits and then we'll fail anyhow) */
		struct arcan_event* pqueue;
		ssize_t pqueue_sz;
		struct arcan_event acqev;

		if (arcan_shmif_acquireloop(&bcl->acon, &acqev, &pqueue, &pqueue_sz)){
/* unrecoverable */
			if (acqev.tgt.kind != TARGET_COMMAND_NEWSEGMENT){
				trace(TRACE_ALERT, "failed to re-acquire subsegment, broken client");
				wl_client_post_no_memory(bcl->client);
				for (size_t j = 0; j < i; j++)
					arcan_shmif_drop(&surfaces[i].new);
				wl.alive = false;
				return;
			}
			trace(TRACE_ALERT, "retrieved new connection");
			surfaces[i].new =
				arcan_shmif_acquire(&bcl->acon,
					NULL, arcan_shmif_segkind(&surf->acon), SHMIF_DISABLE_GUARD);
			free(pqueue);
		}
	}

/* [Pass 2]
 * Now we have all new shiny surfaces, rebuild buffer hierarchy tracking
 */
	for (size_t i = 0; i < surf_count; i++){
		struct comp_surf* surf = surfaces[i].surf;

/* if there's a hierarchy relation, first find the original index */
		if (surf->viewport.ext.viewport.parent){
			for (size_t j = 0; j < surf_count; j++){
				if (surfaces[j].surf->acon.segment_token){
					surf->viewport.ext.viewport.parent = surfaces[j].new.segment_token;
					break;
				}
			}
		}
	}

/* [Pass 3]
 * synch sizes, copy contents and return buffers
 */
	for (size_t i = 0; i < surf_count; i++){
		struct comp_surf* surf = surfaces[i].surf;
		surfaces[i].new.hints = surf->acon.hints;

/* there's no expressed guarantee that the new buffer will have the same
 * stride/pitch, but that's practically the case */
		if (arcan_shmif_resize(&surfaces[i].new, surf->acon.w, surf->acon.h)){
			memcpy(
				surfaces[i].new.vidp,
				surf->acon.vidp,
				surf->acon.h * surf->acon.stride
			);
		}
		else {
			trace(TRACE_ALERT, "rebuild %zu:%s - size failed: %zu, %zu",
				i, surf->tracetag, surf->acon.w, surf->acon.h);
		}

/* free the old relation and resynch the hierarchy/coordinates */
		surfaces[i].new.user = surf->acon.user;
		surf->acon.user = NULL;
		arcan_shmif_drop(&surf->acon);
		surf->acon = surfaces[i].new;
		arcan_shmif_enqueue(&surf->acon, &surf->viewport);
		arcan_shmif_signal(&surf->acon, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
		wl.groups[surfaces[i].group].pg[surfaces[i].ind].fd = surf->acon.epipe;
		trace(TRACE_ALERT, "rebuild %zu:%s - fd set to %d",
			i, surf->tracetag, surf->acon.epipe);

/* release the old buffer regardless, as drm- handles etc. are likely
 * dead and defunct. same goes with framecallbacks */
		if (surf->last_buf){
			wl_buffer_send_release(surf->last_buf);
			surf->last_buf = NULL;
		}

	}

/* clipboards can be allocated dynamically so no need to care there */
	arcan_shmif_drop(&bcl->clip_in);
	arcan_shmif_drop(&bcl->clip_out);

/* need to treat the mouse cursor as something special,
 * rerequest it, assign to the last known surface that held it and update
 * the corresponding slot group and index */
	void* cursor_user = bcl->acursor.user;
	arcan_shmif_drop(&bcl->acursor);
	struct arcan_event* pqueue;
	ssize_t pqueue_sz;
	struct arcan_event acqev;

	arcan_shmif_enqueue(&bcl->acon, &(struct arcan_event){
		.ext.kind = ARCAN_EVENT(SEGREQ),
		.ext.segreq.kind = SEGID_CURSOR,
		.ext.segreq.id = ralloc_id++
	});

	if (arcan_shmif_acquireloop(&bcl->acon, &acqev, &pqueue, &pqueue_sz)){
		if (acqev.tgt.kind != TARGET_COMMAND_NEWSEGMENT){
			trace(TRACE_ALERT, "failed to re-acquire cursor subsegment");
			wl_client_post_no_memory(bcl->client);
			wl.alive = false;
			return;
		}
		bcl->acursor = arcan_shmif_acquire(
			&bcl->acon, NULL, SEGID_CURSOR, SHMIF_DISABLE_GUARD);
		bcl->acursor.user = cursor_user;

		if (cursor_surface){
			trace(TRACE_ALERT, "reassigned cursor subsegment");
			cursor_surface->rcon = &bcl->acursor;
			wl.groups[cs_group].pg[cs_ind].fd = bcl->acursor.epipe;
			dump_alloc(cs_group, "rebuild_client", false);
		}

	}
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
	fprintf(stdout, "\nUse: arcan-wayland [arguments]\n"
"     arcan-wayland [arguments] -exec /path/to/bin arg1 arg2 ...\n"
#ifdef ENABLE_SECCOMP
"\t-sandbox          filter syscalls, ...\n"
#endif
"\t-shm-egl          pass shm- buffers as gl textures\n"
"\t-no-egl           disable the wayland-egl extensions\n"
"\t-no-compositor    disable the compositor protocol\n"
"\t-no-subcompositor disable the sub-compositor/surface protocol\n"
"\t-no-shell         disable the shell protocol\n"
"\t-no-shm           disable the shm protocol\n"
"\t-no-seat          disable the seat protocol\n"
"\t-no-xdg           disable the xdg protocol\n"
"\t-no-output        disable the output protocol\n"
"\t-defer-release    defer buffer releases, aggressive client workaround\n"
"\t-debugusr1        use SIGUSR1 to dump debug information\n"
"\t-prefix prefix    use with -exec, override /tmp/awl_XXXXXX prefix\n"
"\t-fork             fork- off new clients as separate processes\n"
"\t-dir dir          override XDG_RUNTIME_DIR with <dir>\n"
"\t-trace level      set trace output to (bitmask):\n"
"\t1 - allocations, 2 - digital-input, 4 - analog-input\n"
"\t8 - shell, 16 - region-events, 32 - data device\n"
"\t64 - seat, 128 - surface, 256 - drm, 512 - alert\n");
	return EXIT_FAILURE;
}

static bool process_group(struct conn_group* group)
{
	int sv = poll(group->pgroup, N_GROUP_SLOTS+2, 1000);

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

	wl_display_flush_clients(wl.disp);
	return true;
}

static void debugusr1()
{
	dump_alloc(0, "sigusr1", true);
}

/*
 * only happens in exec_mode
 */
static void sigchld_handler()
{
	wl.alive = false;
}

int main(int argc, char* argv[])
{
	struct arg_arr* aarr;
	char dtemp_prefix[] = "/tmp/awl_XXXXXX";
	int exit_code = EXIT_SUCCESS;

/* for each wayland protocol or subprotocol supported, add a corresponding
 * field here, and then command-line argument passing to disable said protocol.
 */
	struct {
		int compositor, shell, shm, seat, output, egl, xdg, subcomp, ddev, relp;
	} protocols = {
		.compositor = 3,
		.shell = 1,
		.shm = 1,
		.seat = 5,
		.output = 2,
		.egl = 1,
		.xdg = 1,
		.subcomp = 1,
		.ddev = 3,
		.relp = 1
	};
#ifdef ENABLE_SECCOMP
	bool sandbox = false;
#endif

	size_t arg_i = 1;
	for (; arg_i < argc; arg_i++){
		if (strcmp(argv[arg_i], "-shm-egl") == 0){
			wl.default_accel_surface = 0;
		}
#ifdef ENABLE_SECCOMP
		else if (strcmp(argv[arg_i], "-sandbox") == 0){
			sandbox = true;
		}
#endif
		else if (strcmp(argv[arg_i], "-trace") == 0){
			if (arg_i == argc-1){
				return show_use("missing trace argument", "");
			}
			arg_i++;
			wl.trace_log = strtoul(argv[arg_i], NULL, 10);
		}
		else if (strcmp(argv[arg_i], "-dir") == 0){
			if (arg_i == argc-1){
				return show_use("missing path to runtime dir", "");
			}
			arg_i++;
			setenv("XDG_RUNTIME_DIR", argv[arg_i], 1);
		}
		else if (strcmp(argv[arg_i], "-egl-device") == 0){
			if (arg_i == argc-1){
				fprintf(stderr, "missing egl device argument\n");
				return EXIT_FAILURE;
			}
			arg_i++;
			setenv("ARCAN_RENDER_NODE", argv[arg_i], 1);
		}
		else if (strcmp(argv[arg_i], "-debugusr1") == 0){
			sigaction(SIGUSR1, &(struct sigaction){.sa_handler = debugusr1}, NULL);
		}
		else if (strcmp(argv[arg_i], "-no-egl") == 0)
			protocols.egl = 0;
		else if (strcmp(argv[arg_i], "-no-compositor") == 0)
			protocols.compositor = 0;
		else if (strcmp(argv[arg_i], "-no-shell") == 0)
			protocols.shell = 0;
		else if (strcmp(argv[arg_i], "-no-shm") == 0)
			protocols.shm = 0;
		else if (strcmp(argv[arg_i], "-no-seat") == 0)
			protocols.seat = 0;
		else if (strcmp(argv[arg_i], "-no-output") == 0)
			protocols.output = 0;
		else if (strcmp(argv[arg_i], "-no-xdg") == 0)
			protocols.xdg = 0;
		else if (strcmp(argv[arg_i], "-no-subcompositor") == 0)
			protocols.subcomp = 0;
		else if (strcmp(argv[arg_i], "-no-data-device") == 0)
			protocols.ddev = 0;
		else if (strcmp(argv[arg_i], "-defer-release") == 0)
			wl.defer_release = true;
		else if (strcmp(argv[arg_i], "-no-relative-pointer") == 0)
			protocols.relp = 0;
		else if (strcmp(argv[arg_i], "-exec") == 0){
			if (wl.fork_mode){
				fprintf(stderr, "Can't use -exec with -fork\n");
				return EXIT_FAILURE;
			}
			wl.exec_mode = true;
			arg_i++;
			break;
		}
		else if (strcmp(argv[arg_i], "-fork") == 0){
			wl.fork_mode = true;
		}
		else
			return show_use("unknown argument: ", argv[arg_i]);
	}

	wl.disp = wl_display_create();
	if (!wl.disp){
		fprintf(stderr, "Couldn't create wayland display\n");
		return EXIT_FAILURE;
	}

/* Generate temporary XDG_RUNTIME_DIR so we don't get any interference from
 * other clients looking in RUNTIME_DIR for the display and grabbing the same
 * one. Actual exec comes later */
	char* newdir = NULL;
	if (wl.exec_mode){
		newdir = mkdtemp(dtemp_prefix);
		if (!newdir){
			fprintf(stderr,"-exec, couldn't create temporary in (%s)\n",dtemp_prefix);
			return EXIT_FAILURE;
		}

		setenv("XDG_RUNTIME_DIR", newdir, 1);
/*
 * Enable the other 'select wayland backend' environment variables we know of
 */
		setenv("SDL_VIDEODRIVER", "wayland", 1);
		setenv("QT_QPA_PLATFORM", "wayland", 1);
		setenv("ECORE_EVAS_ENGINE",
			protocols.egl ? "wayland_egl" : "wayland_shm", 1);
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
	wl.control = arcan_shmif_open(
		SEGID_BRIDGE_WAYLAND, SHMIF_ACQUIRE_FATALFAIL, &aarr);
	struct arcan_shmif_initial* init;
	arcan_shmif_initial(&wl.control, &init);
	wl.init = *init;
	if (!init->display_width_px){
		fprintf(stderr, "Bridge connection did not receive display information\n"
			"make sure appl- sends target_displayhint/outputhint on preroll\n\n");
		wl.init.display_width_px = wl.control.w;
		wl.init.display_height_px = wl.control.h;
	}

/*
 * We'll need some tricks for this one as well. The expected solution is that
 * you surrender to MESA and let the extensions for binding etc. hide the fact
 * that it's pretty much only a tiny wrapper for the opaque native window and
 * then registering the wl_drm interface. Since we want to specify which
 * device a client should use on a per-client basis, and just proxy-pass the
 * descriptors, we'll need a wl_drm implementation and possibly let the
 * shmif-ext proxy authentication for us.
 */
	if (protocols.egl){
/*
 * we need an accelerated graphics setup that we can use to tie into mesa/gl
 * in order for the whole WLDisplay integration that goes on (...)
 * the 'upload texture here, pass handle onwards' option to accelerate _shm
 * and get rid of the extra copy is setup per client, not here. It is thus
 * possible to disable EGL wayland clients and still have that feature.
 */
		struct arcan_shmifext_setup cfg = arcan_shmifext_defaults(&wl.control);
		cfg.builtin_fbo = false;
		if (SHMIFEXT_OK != arcan_shmifext_setup(&wl.control, cfg)){
			fprintf(stderr, "Couldn't setup EGL context/display\n");
			exit_code = EXIT_FAILURE;
			goto cleanup;
		}

/*
 * This is a special case, if RENDER_NODE points to a card node, and arcan
 * has been setup allowing clients to try and negotiate, this function will
 * actually do the deed.
 */
		uintptr_t devnode;
		arcan_shmifext_dev(&wl.control, &devnode, false);

		uintptr_t display;
		arcan_shmifext_egl_meta(&wl.control, &display, NULL, NULL);
		wl.display = eglGetDisplay((EGLDisplay)display);
		if (!wl.display){
			fprintf(stderr, "(eglBindWaylandDisplayWL) failed\n");
			exit_code = EXIT_FAILURE;
			goto cleanup;
		}
		wl.drm = wayland_drm_init(wl.disp,
			getenv("ARCAN_RENDER_NODE"), NULL, NULL, 0);
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
	if (protocols.relp)
		wl_global_create(wl.disp, &zwp_relative_pointer_manager_v1_interface,
			protocols.relp, NULL, &bind_relp);

	trace(TRACE_ALLOC, "wl_display() finished");

	wl.alive = true;

/*
 * This is just a temporary / ugly "64 restriction" in that this is how many
 * clients and surfaces we run per group. When a group is completely full, it's
 * time to slice of a new thread/process and continue there - but that's
 * something to worry about when we have all the features in place.
 */
	wl.groups = prepare_groups(1);
	wl.n_groups = 1;
	wl.groups[0].wayland->fd =
		wl_event_loop_get_fd(wl_display_get_event_loop(wl.disp));
	wl.groups[0].arcan->fd = wl.control.epipe;

/*
 * chain-execute the single client that we want to handle
 */
	if (wl.exec_mode){
		struct sigaction act = {
			.sa_handler = &sigchld_handler
		};
		if (sigaction(SIGCHLD, &act, NULL) < 0){
			wl.alive = false;
		}
		else {
			int rc = fork();
			if (rc == 0){
				size_t nargs = argc - arg_i;
				char* args[nargs];
				for (size_t i = 1; arg_i + i < argc; i++)
					args[i] = argv[arg_i+i];
				args[nargs-1] = NULL;
				if (-1 == execvp(argv[arg_i], args))
					exit(EXIT_FAILURE);
			}
			else if (rc == -1){
				wl.alive = false;
			}
		}
	}

#ifdef ENABLE_SECCOMP
/* Unfortunately a rather obese list, part of it is our lack of control
 * over the whole FFI nonsense and the keylayout creation/transfer. You
 * need to be a rather shitty attacker not to manage with this set, but
 * we have our targets for reduction at least */
	if (sandbox){
		prctl(PR_SET_NO_NEW_PRIVS, 1);
		scmp_filter_ctx flt = seccomp_init(SCMP_ACT_KILL);
#include "syscalls.c"
		seccomp_load(flt);
	}
#endif
	while(wl.alive && process_group(&wl.groups[0])){}

cleanup:
	if (wl.disp)
		wl_display_destroy(wl.disp);
	arcan_shmif_drop(&wl.control);

/*
 * can at least try, don't be aggressive and opendir/glob/rm until it works
 */
	if (newdir){
		rmdir(newdir);
	}

	return exit_code;
}
