/*
 * Copyright 2016-2019, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: https://github.com/letoram/arcan/wiki/wayland.md
 */

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

#define WANT_ARCAN_SHMIF_HELPER
#include "../shmif/arcan_shmif.h"
#include <wayland-server.h>
#include <signal.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <dirent.h>
#include <errno.h>
#include <poll.h>
#include <assert.h>
#include <stdatomic.h>
#include "../engine/arcan_mem.h"

#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>
#include <xkbcommon/xkbcommon-compose.h>
#include <libdrm/drm_fourcc.h>

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
 * sent when a surface loses focus
 */
static void release_all_keys(struct bridge_client* cl);

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
 * return the next allocated surface in group with the specific type starting
 * at index *pos, returns the index found. If type is set to 0, the next
 * allocated surface will be returned.
 */
static struct comp_surf* find_surface_group(int group, char type, size_t* pos);

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
	struct pollfd* xwm;

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
	EGLBoolean (*query_formats)(EGLDisplay, EGLint, EGLint*, EGLint*);
	EGLBoolean (*query_modifiers)(EGLDisplay,
		EGLint, EGLint, EGLuint64KHR* mods, EGLBoolean* ext_only, EGLint* n_mods);

	struct wl_display* disp;
/* set to false after initialization to terminate */
	bool alive;

/* metadata on accelerated graphics (legacy) */
	struct wl_drm* drm;

/* initial display parameters retrieved from the control connection */
	struct arcan_shmif_initial init;
	struct arcan_shmif_cont control;

/*
 * this is a workaround for clients that starts scaling or padding
 * when receiving a configure event that doesn't fit what they can
 * support
 */
	bool force_sz;

/*
 * all surfaces start with accel-transfer disabled, only sourced
 * dma-buffers will actully be passed on as-is
 */
	int default_accel_surface;

/*
 * needed to communicate window management events in the xwayland space, to
 * pair compositor surfaces with xwayland- originating ones and so on. On-
 * demand launch of the arcan-xwayland / arcan-xwayland-wm is found in
 * wlimpl/xwl.c
 */
	bool use_xwayland;

/*
 * accepted trace level and destination file
 */
	int trace_log;
	FILE* trace_dst;

/*
 * single- client exit- on terminate mode
 */
	bool exec_mode;
} wl = {
	.default_accel_surface = -1,
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
	TRACE_ALERT   = 512,
	TRACE_XWL     = 1024
};

static const char* trace_groups[] = {
	"alloc",
	"digital",
	"analog",
	"shell",
	"region",
	"datadev",
	"seat",
	"surface",
	"drm",
	"alert",
	"xwl"
};

static inline void trace(int level, const char* msg, ...)
{
	if (!wl.trace_log || !(level & wl.trace_log) || !wl.trace_dst)
		return;

	va_list args;
	va_start(args, msg);
		vfprintf(wl.trace_dst,  msg, args);
		fprintf(wl.trace_dst, "\n");
	va_end(args);
	fflush(wl.trace_dst);
}

#define __FILENAME__ (strrchr(__FILE__, '/')?strrchr(__FILE__, '/') + 1 : __FILE__)
#define trace(X, Y, ...) do { trace(X, "[%lld]%s:%d:%s(): " \
	Y, arcan_timemillis(), __FILENAME__, __LINE__, __func__,##__VA_ARGS__); } while (0)

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
#include "structs.h"
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
		trace(TRACE_ALERT, "pqueue size of %zu ignored", pqueue_sz);
	}

	return true;
}

static void destroy_comp_surf(struct comp_surf* surf, bool clean)
{
	STEP_SERIAL();
	if (!surf)
		return;

/* remove old listener (always) */
	if (surf->l_bufrem_a){
		surf->l_bufrem_a = false;
		wl_list_remove(&surf->l_bufrem.link);
	}

/* destroy any dangling listeners */
	for (size_t i = 0; i < COUNT_OF(surf->scratch) && surf->frames_pending; i++){
		if (surf->scratch[i].type == 1){
			wl_resource_destroy(surf->scratch[i].res);
			surf->frames_pending--;
			surf->scratch[i] = (struct scratch_req){};
		}
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

static struct comp_surf* find_surface_group(int group, char type, size_t* pos)
{
	if (group < 0 || group < wl.n_groups)
		return NULL;

	for (size_t i = (*pos); i < sizeof(wl.groups[i].alloc)*8; i++){
		if (!((1 << i) & wl.groups[group].alloc) ||
			wl.groups[group].slots[i].type != SLOT_TYPE_SURFACE ||
			!wl.groups[group].slots[i].surface)
			continue;

		if (type == 0 || wl.groups[group].slots[i].idch == type){
			*pos = i;
			return wl.groups[group].slots[i].surface;
		}
	}

	return NULL;
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

/* Connect a new bridge to arcan. There are two ways this could be done, one is
 * to simply open a new one, but that assumes we are running with external
 * connections permitted. If we inherit, the new client should be bootstrapped
 * over the bridge connection.
 */
	struct arcan_shmif_cont con = arcan_shmif_open(SEGID_BRIDGE_WAYLAND, 0, NULL);
	if (!con.addr){
		arcan_shmif_enqueue(&wl.control,
		&(struct arcan_event){
			.ext.kind = ARCAN_EVENT(SEGREQ),
			.ext.segreq.kind = SEGID_BRIDGE_WAYLAND
		});

		struct arcan_event* pqueue;
		ssize_t pqueue_sz;
		struct arcan_event acqev;

	/* there are no real events coming on the control node at the moment, so the
	 * queue can simply be ignored, if we happened to run into an EXIT the loop
	 * would just fail next iteration */
		if (arcan_shmif_acquireloop(&wl.control, &acqev, &pqueue, &pqueue_sz)){
			if (acqev.tgt.kind != TARGET_COMMAND_NEWSEGMENT){
				trace(TRACE_ALLOC, "couldn't allocate client over control connection");
				wl_client_post_no_memory(cl);
				return NULL;
			}
			trace(TRACE_ALERT, "retrieved new connection");
			con =
				arcan_shmif_acquire(&wl.control, NULL,
					SEGID_BRIDGE_WAYLAND, SHMIF_DISABLE_GUARD|SHMIF_NOREGISTER);
			free(pqueue);
		}
	}

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

	memset(res->keys, '\0', sizeof(res->keys));
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
			trace(TRACE_ALERT, "queue surface for rebuild: %c",
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
		trace(TRACE_ALERT, "(%zu/%zu) rebuild, request %s => %d (%"PRIxPTR",%"PRIxPTR")",
			i, surf_count, surf->tracetag, arcan_shmif_segkind(&surf->acon),
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
				arcan_shmif_acquire(&bcl->acon, NULL,
				arcan_shmif_segkind(&surf->acon), SHMIF_DISABLE_GUARD|SHMIF_NOREGISTER);
			free(pqueue);
		}
	}

/* [Pass 2]
 * Now we have all new shiny surfaces, rebuild buffer hierarchy tracking */
	for (size_t i = 0; i < surf_count; i++){
		struct comp_surf* surf = surfaces[i].surf;

/* skip those where there is no documented relationship */
		if (!surf->viewport.ext.viewport.parent)
			continue;

/* linear-search for the matching segment */
		for (size_t j = 0; j < surf_count; j++){

/* and for the one where the OLD token MATCH the known PARENT, SET to new */
			if (surf->viewport.ext.viewport.parent ==
				surfaces[j].surf->acon.segment_token){
					surf->viewport.ext.viewport.parent = surfaces[j].new.segment_token;
					break;
				}
		}
	}

/* [Pass 3]
 * synch sizes, copy contents and return buffers */
	for (size_t i = 0; i < surf_count; i++){
		struct comp_surf* surf = surfaces[i].surf;
		surfaces[i].new.hints = surf->acon.hints;

/* There's no expressed guarantee that the new buffer will have the same
 * stride/pitch, but that's practically the case, more worrying is that the
 * buffer is likely to not match the new initial size. It might be better to
 * extract initial and pre-emit a configure and so on, but for now, just run
 * with the old values */
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

/* retain the old GUID */
		struct arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(REGISTER),
			.ext.registr.kind = arcan_shmif_segkind(&surf->acon)
		};
		arcan_shmif_guid(&surf->acon, ev.ext.registr.guid);
		arcan_shmif_enqueue(&surfaces[i].new, &ev);

/* free the old relation and resynch the hierarchy/coordinates */
		surfaces[i].new.user = surf->acon.user;
		surf->acon.user = NULL;
		arcan_shmif_drop(&surf->acon);
		surf->acon = surfaces[i].new;
		arcan_shmif_signal(&surf->acon, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
		wl.groups[surfaces[i].group].pg[surfaces[i].ind].fd = surf->acon.epipe;
		trace(TRACE_ALERT, "rebuild %zu:%s - fd set to %d",
			i, surf->tracetag, surf->acon.epipe);
	}

/* [Pass 4], now the hierarchy should be 'alive' on the parent side,
 * resubmit viewports */
	for (size_t i = 0; i < surf_count; i++){
		struct comp_surf* surf = surfaces[i].surf;
		arcan_shmif_enqueue(&surf->acon, &surf->viewport);

/* if the surface is tied to xwayland, we also need to resubmit (at least)
 * the type, possibly also surface-id to wl-id pairing */
		struct xwl_window* wnd = xwl_find_surface(surf->id);
		if (wnd && wnd->xtype){
			wnd_message(wnd, "type:%s", wnd->xtype);
		}
	}

/* clipboards can be allocated dynamically so no need to care there */
	arcan_shmif_drop(&bcl->clip_in);
	arcan_shmif_drop(&bcl->clip_out);

/* need to treat the mouse cursor as something special, (if it is used),
 * rerequest it, assign to the last known surface that held it and update
 * the corresponding slot group and index */
	if (!bcl->acursor.addr)
		return;

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
			&bcl->acon, NULL, SEGID_CURSOR, SHMIF_DISABLE_GUARD | SHMIF_NOREGISTER);
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
 * naive and racy, but only used for cleanup on tmpdir in exec mode
 */
static void rmdir_recurse(const char* p)
{
	DIR* d = opendir(p);
	if (!d)
		return;

	size_t plen = strlen(p);
	struct dirent* dent;

	while ((dent = readdir(d))){
		if (strcmp(dent->d_name, ".") == 0 || strcmp(dent->d_name, "..") == 0)
			continue;

		size_t tmplen = plen + strlen(dent->d_name) + 2;
		char* tmp = malloc(tmplen);
		if (!tmp)
			break;

		struct stat bs;
		snprintf(tmp, tmplen, "%s/%s", p, dent->d_name);
		if (0 != stat(tmp, &bs)){
			free(tmp);
			break;
		}
		if (S_ISDIR(bs.st_mode)){
			rmdir_recurse(tmp);
		}
		else
			unlink(tmp);
		free(tmp);
	}

	closedir(d);
	rmdir(p);
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
		groups[i].pgroup = malloc(sizeof(struct pollfd) * (N_GROUP_SLOTS+3));
		groups[i].slots = malloc(sizeof(struct bridge_slot) * N_GROUP_SLOTS);

		if (!groups[i].pgroup || !groups[i].slots)
			OUT_OF_MEMORY("group/slot alloc");

		groups[i].pg = &groups[i].pgroup[3];
		groups[i].wayland = &groups[i].pgroup[0];
		groups[i].arcan = &groups[i].pgroup[1];
		groups[i].xwm = &groups[i].pgroup[2];

		for (size_t j = 0; j < N_GROUP_SLOTS+3; j++){
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

static int tracestr_to_bitmap(char* work)
{
	int res = 0;
	char* pt = strtok(work, ",");
	while(pt != NULL){
		for (size_t i = 0; i < COUNT_OF(trace_groups); i++){
			if (strcasecmp(trace_groups[i], pt) == 0){
				res |= 1 << i;
				break;
			}
		}
		pt = strtok(NULL, ",");
	}
	return res;
}

static int show_use(const char* msg, const char* arg)
{
	fprintf(stdout, "%s%s", msg, arg ? arg : "");
	fprintf(stdout, "\nUse: arcan-wayland [arguments]\n"
"     arcan-wayland [arguments] -exec /path/to/bin arg1 arg2 ...\n\n"
"Compatibility:\n"
"\t-egl-device path  set path to render node (/dev/dri/renderD128)\n"
"\t-xwl              enable XWayland\n\n"
"Security/Performance:\n"
"\t-exec bin arg1 .. end of arg parsing, single-client mode (recommended)\n"
"\t-exec-x11 bin arg same as -xwl -exec bin arg1 .. form\n"
"\t-shm-egl          pass shm- buffers as gl textures\n"
#ifdef ENABLE_SECCOMP
"\t-sandbox          filter syscalls, ...\n"
#endif
"\nWorkarounds:\n"
"\t-prefix prefix    use with -exec, override XDG_RUNTIME_DIR/awl_XXXXXX prefix\n"
"\t-width px         override display 'fullscreen' width\n"
"\t-height px        override display 'fullscreen' height\n"
"\t-force-fs         ignore displayhints and always configure to display size\n"
"\nProtocol Filters:\n"
"\t-no-egl           disable the wayland-egl extensions\n"
"\t       -no-drm    disable the drm subprotocol\n"
"\t       -dma       ENABLE  the dma-buf subprotocol\n"
"\t-no-compositor    disable the compositor protocol\n"
"\t-no-subcompositor disable the sub-compositor/surface protocol\n"
"\t-no-shell         disable the shell protocol\n"
"\t-no-shm           disable the shm protocol\n"
"\t-no-seat          disable the seat protocol\n"
"\t-no-xdg           disable the xdg protocol\n"
"\t-no-zxdg          disable the zxdg protocol\n"
"\t-no-output        disable the output protocol\n"
"\nDebugging Tools:\n"
"\t-trace level      set trace output to (bitmask or key1,key2,...):\n"
"\t\t1   - alloc         2 - digital          4 - analog\n"
"\t\t8   - shell        16 - region          32 - datadev\n"
"\t\t64  - seat        128 - surface        256 - drm\n"
"\t\t512 - alert      1024 - xwl \n");
	return EXIT_FAILURE;
}

static bool process_group(struct conn_group* group)
{
	int sv = poll(group->pgroup, N_GROUP_SLOTS+3, 1000);

	if (group->wayland && group->wayland->revents){
		trace(TRACE_ALERT, "process wayland");
		wl_event_loop_dispatch(
			wl_display_get_event_loop(wl.disp), 0);
		sv--;
	}

	if (group->xwm && group->xwm->revents){
		trace(TRACE_ALERT, "process xwm");
		xwl_check_wm();
		sv--;
	}

	if (group->arcan && group->arcan->revents){
		trace(TRACE_ALERT, "process bridge");
		flush_bridge_events(&wl.control);
		sv--;
	}

	for (size_t i = 0; i < N_GROUP_SLOTS && sv > 0 && wl.alive; i++){
		if (group->pg[i].revents){
			sv--;
			switch(group->slots[i].type){
			case SLOT_TYPE_CLIENT:
				flush_client_events(&group->slots[i].client, NULL, 0);
			break;
			case SLOT_TYPE_SURFACE:
				if (group->slots[i].surface){
					if (group->pg[i].revents & POLLIN)
						flush_surface_events(group->slots[i].surface);
					else
						trace(TRACE_ALERT, "broken surface slot (%zu)", i);

/* we can get into a situation where arcan considers the connection over and
 * done with, but wayland clients have much less strinent lifecycle
 * requirements, in those cases the read-socket is actually over and done with
 * so it needs to be removedfrom the pollset or we start spinning - with
 * x clients in particular we can switch to an 'xkill' like behavior though */
					char flush[256];
					ssize_t nr = read(group->pg[i].fd, flush, 256);
					if (0 == nr){
						close(group->pg[i].fd);
						group->pg[i].fd = -1;
					}
				}
				else {
					trace(TRACE_ALERT, "event on empty slot (%zu)", i);
				}
			break;
			}
		}
	}

	wl_display_flush_clients(wl.disp);
	return true;
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
	int exit_code = EXIT_SUCCESS;
	int force_width = 0;
	int force_height = 0;

/*
 * There is a conflict between XDG_RUNTIME_DIR used for finding the Arcan
 * setup, and the 'sandboxed' runtime-dir used with Wayland and other clients.
 * To get around this we keep two around and flip-flop as needed.
 */
	if (!getenv("XDG_RUNTIME_DIR")){
		return show_use("No XDG_RUNTIME_DIR environment could be found.", "");
	}
	char* arcan_runtime_dir = strdup(getenv("XDG_RUNTIME_DIR"));
	char* wayland_runtime_dir = NULL;

/* for each wayland protocol or subprotocol supported, add a corresponding
 * field here, and then command-line argument passing to disable said protocol.
 */
	struct {
		int compositor, shell, shm, seat, output, ddev;
		int egl, zxdg, xdg, subcomp, drm, relp, dma;
	} protocols = {
		.compositor = 4,
		.shell = 1,
		.shm = 1,
		.seat = 5,
		.output = 2,
		.egl = 1,
		.zxdg = 1,
		.xdg = 1,
		.drm = 1,
		.dma = 3,
		.subcomp = 1,
		.ddev = 3,
		.relp = 1,
	};
#ifdef ENABLE_SECCOMP
	bool sandbox = false;
#endif

	wl.trace_dst = stdout;

/*
 * Only used with -exec (but should be user controllable) in order to split
 * the XDG_RUNTIME_DIR used by arcan and the one used by Wayland
 */
	char* xdgtemp_prefix;
	asprintf(&xdgtemp_prefix, "%s/awl_XXXXXX", getenv("XDG_RUNTIME_DIR"));

	size_t arg_i = 1;
	for (; arg_i < argc; arg_i++){
		if (strcmp(argv[arg_i], "-xwl") == 0)
			wl.use_xwayland = true;
		else if (strcmp(argv[arg_i], "-shm-egl") == 0){
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
			char* workstr = NULL;
			wl.trace_log = strtoul(argv[arg_i], &workstr, 10);
			if (workstr == argv[arg_i]){
				wl.trace_log = tracestr_to_bitmap(workstr);
			}
		}
		else if (strcmp(argv[arg_i], "-trace-file") == 0){
			if (arg_i == argc-1)
				return show_use("missign trace destination argument", "");
			arg_i++;
			wl.trace_dst = fopen(argv[arg_i], "w");
		}
		else if (strcmp(argv[arg_i], "-prefix") == 0){
			if (arg_i == argc-1){
				return show_use("missing path to prefix path", "");
			}
			arg_i++;
			size_t len = strlen(argv[arg_i]);
			if (len <= 7 || strcmp(&argv[arg_i][len-7], "XXXXXX") != 0){
				return show_use("prefix path must end with XXXXXX", "");
			}
			free(xdgtemp_prefix);
			xdgtemp_prefix = strdup(argv[arg_i]);
		}
		else if (strcmp(argv[arg_i], "-egl-device") == 0){
			if (arg_i == argc-1){
				fprintf(stderr, "missing egl device argument\n");
				return EXIT_FAILURE;
			}
			arg_i++;
			setenv("ARCAN_RENDER_NODE", argv[arg_i], 1);
		}
		else if (strcmp(argv[arg_i], "-width") == 0){
			if (arg_i == argc-1){
				fprintf(stderr, "missing width px argument\n");
				return EXIT_FAILURE;
			}
			arg_i++;
			force_width = strtoul(argv[arg_i], NULL, 10);
		}
		else if (strcmp(argv[arg_i], "-height") == 0){
			if (arg_i == argc-1){
				fprintf(stderr, "missing width px argument\n");
				return EXIT_FAILURE;
			}
			arg_i++;
			force_height = strtoul(argv[arg_i], NULL, 10);
		}
		else if (strcmp(argv[arg_i], "-force-fs") == 0){
			wl.force_sz = true;
		}
		else if (strcmp(argv[arg_i], "-no-egl") == 0)
			protocols.egl = 0;
		else if (strcmp(argv[arg_i], "-no-drm") == 0)
			protocols.drm = 0;
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
		else if (strcmp(argv[arg_i], "-no-zxdg") == 0)
			protocols.zxdg = 0;
		else if (strcmp(argv[arg_i], "-dma") == 0)
			protocols.dma = 1;
		else if (strcmp(argv[arg_i], "-no-xdg") == 0)
			protocols.xdg = 0;
		else if (strcmp(argv[arg_i], "-no-subcompositor") == 0)
			protocols.subcomp = 0;
		else if (strcmp(argv[arg_i], "-no-data-device") == 0)
			protocols.ddev = 0;
		else if (strcmp(argv[arg_i], "-no-relative-pointer") == 0)
			protocols.relp = 0;
		else if (strcmp(argv[arg_i], "-exec-x11") == 0){
			wl.exec_mode = true;
			wl.use_xwayland = true;
			arg_i++;
			break;
		}
		else if (strcmp(argv[arg_i], "-exec") == 0){
			wl.exec_mode = true;
			arg_i++;
			break;
		}
		else if (strcmp(argv[arg_i], "-h") == 0 ||
			strcmp(argv[arg_i], "--help") == 0 || strcmp(argv[arg_i], "-help")){
			return show_use("", "");
		}
		else
			return show_use("unknown argument: ", argv[arg_i]);
	}

	wl.disp = wl_display_create();
	if (!wl.disp){
		fprintf(stderr, "Couldn't create wayland display\n");
		return EXIT_FAILURE;
	}

/* track and use as scratch directory */
	int dstdir_fd = -1;
	DIR* tmpdir = NULL;

	if (wl.exec_mode){
		wayland_runtime_dir = mkdtemp(xdgtemp_prefix);
		if (!wayland_runtime_dir){
			fprintf(stderr,
				"-exec, couldn't create temporary in (%s)\n", xdgtemp_prefix);
			return EXIT_FAILURE;
		}

		tmpdir = opendir(wayland_runtime_dir);
		if (!tmpdir || -1 == (dstdir_fd = dirfd(tmpdir))){
			fprintf(stderr,
				"-exec, couldn't open temporary dir (%s)\n", wayland_runtime_dir);
			return EXIT_FAILURE;
		}

/* Until we have a way to proxy pulseaudio etc. we need, at least, to forward
 * the socket into the namespace so that the client will find it */
		char* papath;
		if (-1 == asprintf(&papath, "%s/pulse/native", getenv("XDG_RUNTIME_DIR")))
			papath = NULL;

		if (papath){
			mkdirat(dstdir_fd, "pulse", S_IRWXU | S_IRWXG);
			free(papath);
		}

/* Enable the other 'select wayland backend' environment variables we know of,
 * but only if we are not supposed to go via xwayland */
		if (!wl.use_xwayland){
			setenv("SDL_VIDEODRIVER", "wayland", 1);
			setenv("QT_QPA_PLATFORM", "wayland", 1);
			setenv("ECORE_EVAS_ENGINE",
				protocols.egl ? "wayland_egl" : "wayland_shm", 1);
		}
	}


/*
 * The purpose of having a 'control' bridge connection on which we never set
 * clients is to have a window where we can monitor the state of the server
 * and its clients, but also to get the initial display, figure out if we have
 * accelerated graphics or not and so on.
 */
	setenv("XDG_RUNTIME_DIR", arcan_runtime_dir, 1);
	wl.control = arcan_shmif_open(
		SEGID_BRIDGE_WAYLAND, SHMIF_ACQUIRE_FATALFAIL, &aarr);

	struct arcan_shmif_initial* init;
	arcan_shmif_initial(&wl.control, &init);
	wl.init = *init;
	if (!init->display_width_px){
		fprintf(stderr, "[Warning] "
			"window manager provided no display/output information\n");
		wl.init.display_width_px = wl.control.w;
		wl.init.display_height_px = wl.control.h;
	}

	if (force_width > 0)
		wl.init.display_width_px = force_width;

	if (force_height > 0)
		wl.init.display_height_px = force_height;

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

		uintptr_t gl_display;
		arcan_shmifext_egl_meta(&wl.control, &gl_display, NULL, NULL);
		wl.display = (void*) gl_display;

		if (!wl.display){
			fprintf(stderr, "(eglBindWaylandDisplayWL) failed\n");
			exit_code = EXIT_FAILURE;
			goto cleanup;
		}

		wl.query_formats =
			arcan_shmifext_lookup(&wl.control, "eglQueryDmaBufFormatsEXT");
		wl.query_modifiers =
			arcan_shmifext_lookup(&wl.control, "eglQueryDmaBufModifiersEXT");

/*
 * The initial device node comes as a possible file descriptor, but the drm
 * protocol wants the drm device name
 */
		if (!getenv("ARCAN_RENDER_NODE")){
			fprintf(stderr, "No render-node provided "
				"(-egl-device), accelerated graphics disabled.\n");
			protocols.drm = 0;
		}

		if (protocols.drm){
			wl.drm = wayland_drm_init(wl.disp, getenv("ARCAN_RENDER_NODE"), NULL, 0);
		}
	}

/*
 * add_socket auto will create the display in XDG_RUNTIME
 */
	if (wayland_runtime_dir){
		setenv("XDG_RUNTIME_DIR", wayland_runtime_dir, 1);
		wl_display_add_socket_auto(wl.disp);
		setenv("XDG_RUNTIME_DIR", arcan_runtime_dir, 1);
	}
	else{
		wl_display_add_socket_auto(wl.disp);
	}

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
	if (protocols.zxdg)
		wl_global_create(wl.disp, &zxdg_shell_v6_interface,
			protocols.zxdg, NULL, &bind_zxdg);
	if (protocols.xdg)
		wl_global_create(wl.disp, &xdg_wm_base_interface,
			protocols.xdg, NULL, &bind_xdg);
	if (protocols.dma){
		wl_global_create(wl.disp, &zwp_linux_dmabuf_v1_interface,
			protocols.dma, NULL, &bind_zwp_dma_buf);
	}
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

/* pipes from xwm etc, don't want that to kill us */
	sigaction(SIGPIPE, &(struct sigaction){
		.sa_handler = SIG_IGN, .sa_flags = 0}, 0);

/* intercept signals and forward to cleanup */
	if (
		(sigaction(SIGCHLD,
		&(struct sigaction){.sa_handler = &sigchld_handler}, NULL) < 0) ||
		(sigaction(SIGTERM,
		&(struct sigaction){.sa_handler = &sigchld_handler}, NULL) < 0) ||
		(sigaction(SIGINT,
		&(struct sigaction){.sa_handler = &sigchld_handler}, NULL) < 0))
	{
			wl.alive = false;
	}

/* we can't actually use xwl_spawn blocking here as that would cause the wm
 * process to wait for xwayland that is waiting for the wl_display here */
	if (wl.use_xwayland){
		if (wayland_runtime_dir)
			setenv("XDG_RUNTIME_DIR", wayland_runtime_dir, 1);
		trace(TRACE_XWL, "spawning Xserver/wm");
		xwl_spawn_wm(false, &argv[arg_i]);
		setenv("XDG_RUNTIME_DIR", arcan_runtime_dir, 1);
	}

/* chain-execute the single client that we want to handle, this is handled
 * by the wm in the use-xwayland mode so ignore here */
	if (wl.exec_mode){
/* we'll spawn the X-wm and child a little bit later */
		if (!wl.use_xwayland){
			if (wayland_runtime_dir)
				setenv("XDG_RUNTIME_DIR", wayland_runtime_dir, 1);

			int rc = fork();
			if (rc == 0){
				setpgid(0,0);
				execvp(argv[arg_i], &argv[arg_i]);
				fprintf(stderr, "couldn't exec %s: %s\n", argv[arg_i], strerror(errno));
				exit(EXIT_FAILURE);
			}
			else if (rc == -1){
				wl.alive = false;
			}
		}

		setenv("XDG_RUNTIME_DIR", arcan_runtime_dir, 1);
	}

#ifdef ENABLE_SECCOMP
/* Unfortunately a rather obese list, part of it is our lack of control
 * over the whole FFI nonsense and the keylayout creation/transfer. You
 * need to be a rather shitty attacker not to manage with this set, but
 * we have our targets for reduction at least.
 * either make it completely pointless or fail to relaunch WM. */
	if (sandbox){
		prctl(PR_SET_NO_NEW_PRIVS, 1);
		scmp_filter_ctx flt = seccomp_init(SCMP_ACT_KILL);
#include "syscalls.c"
		seccomp_load(flt);
	}
#endif
	while(wl.alive && process_group(&wl.groups[0])){

/* Xwayland or the window manager might have died, restart in those cases */
		if (wl.use_xwayland){
			if (xwl_wm_pid == -1){
				trace(TRACE_XWL, "respawning Xserver/wm");
				xwl_spawn_wm(false, NULL);
			}
		}

	}

cleanup:
	if (wl.disp)
		wl_display_destroy(wl.disp);
	arcan_shmif_drop(&wl.control);
	free(arcan_runtime_dir);

/* We have created a folder with temporary files and links, this comes with
 * the -xwl and -exec modes and we treat this as authoritative. This should
 * be shallow (only nodes by us or possibly symlinks so don't recurse */
	if (wayland_runtime_dir){
		rmdir_recurse(wayland_runtime_dir);
		free(wayland_runtime_dir);
	}
	return exit_code;
}
