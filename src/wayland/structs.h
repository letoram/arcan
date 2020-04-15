#ifndef HAVE_STRUCTS

#define STEP_SERIAL() ( wl_display_next_serial(wl.disp) )

struct xkb_stateblock {
	struct xkb_context* context;
	struct xkb_keymap* map;
	struct xkb_state* state;
	const char* map_str;
};

struct bridge_client {
	struct arcan_shmif_cont acon, clip_in, clip_out;
	struct wl_listener l_destr;
	struct wl_listener l_pending;

/* seat / wl-api mapping references */
	struct wl_client* client;
	struct wl_resource* keyboard;
	struct wl_resource* pointer;
	struct wl_resource* touch;
	struct wl_resource* output; /* only 1 atm */

	struct xkb_stateblock kbd_state;

/* cursor state, we want to share one subseg connection and just
 * switch surface resource around */
	struct arcan_shmif_cont acursor;
	struct wl_resource* cursor;
	int32_t hot_x, hot_y;
	bool dirty_hot;
	struct wl_resource* got_relative;

/* need to track these so that we can send enter/leave correctly,
 * watch out for UAFs */
	struct wl_resource* last_cursor;
	struct wl_resource* last_kbd;

	struct arcan_strarr offer_types;

/* to keep an association across display server instances */
	uint64_t guid[2];

/* track keycodes of keys that are pressed so we can fake release
 * if a window gets defocused as a way of 'resetting' the keymap,
 * this don't take latched modifiers or dicretics into account */
	uint8_t keys[512];

	bool forked;
	int group, slot;
	int refc;
};

struct acon_tag {
	int group, slot;
};

struct positioner {
	int32_t width, height;
	int32_t ofs_x, ofs_y;
	int32_t anchor_x, anchor_y, anchor_width, anchor_height;
	uint32_t anchor;
	uint32_t gravity;
	uint32_t constraints;
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

/* doesn't apply for every request */
	struct wl_resource* parent, (* positioner);

/* custom 'shove it in here' reference */
	void* tag;

/* callback that will be triggered with the result, [srf] will be NULL if the
 * request failed. Return [true] if you accept responsibility of the shmif_cont
 * (will be added to the group/slot allocation and normal I/O multiplexation)
 * or [false] if the surface is not needed anymore. */
	bool (*dispatch)(struct surface_request*, struct arcan_shmif_cont* srf);
};

static bool request_surface(struct bridge_client* cl, struct surface_request*, char);

struct surf_state {
	bool hidden : 1;
	bool unfocused : 1;
	bool maximized : 1;
	bool minimized : 1;
	bool drag_resize : 1;
};

struct frame_cb {
	struct wl_list link;
};

struct scratch_req {
	int type;
	struct wl_resource* res;
	uint32_t id;
};

#define SURF_TAGLEN 16
#define SURF_RELEASE_WND 4
struct comp_surf {
	struct wl_listener l_bufrem;
	bool l_bufrem_a;

	char tracetag[SURF_TAGLEN];

	struct bridge_client* client;

	struct wl_resource* res;
	struct wl_resource* shell_res;
	struct wl_resource* surf_res;
	struct wl_resource* sub_parent_res;
	struct wl_resource* sub_child_res;

/* mark the surface as supposed to commit, but some reason (ongoing sync
 * or similar) forced us to reconsider at a later stage. */
	bool pending_commit;

/*
 * surfaces that are passed as shm- buffers might be better to bind to a
 * GPU from the waybridge process as we both save a copy (no good way to
 * map the buffer- pool to shmif- vidp), and can safely upload a texture
 * to the GPU without risking a stall due to the main process being busy
 * with VSYNCH.
 */
	int fail_accel;
	int accel_fmt;
	int gl_fmt;
	unsigned glid;

/*
 * Just keep this fugly thing here as it is on par with wl_list masturbation,
 * the protocol is just riddled with unbounded allocations because all the bad
 * ones are. Scratch area is 'needed; for pending frame callbacks and for
 * pending subsurface allocations (again the whole letting clients allocate
 * useless resources that may or may not be assigned to something useful
 * crapola).
 */
	struct scratch_req scratch[64];
	size_t frames_pending, subsurf_pending;

/*
 * need to cache/update this one whenever we reparent, etc.
 */
	struct arcan_event viewport;

/* some comp_surfaces need to reference shared connections that are
 * managed elsewhere, so if rcon set, that one takes priority */
	struct arcan_shmif_cont acon;
	struct arcan_shmif_cont* rcon;
	struct wl_resource* buf;
	uint32_t id;
	uintptr_t cbuf;

/* track size and positioning information so we can relay */
	size_t last_w, last_h;
	uint32_t max_w, max_h, min_w, min_h;

/* need to track these so that we can subtract from displayhints..*/
	uint32_t geom_w, geom_h, geom_x, geom_y;

/* for mouse pointer, we need a surface accumulator */
	int acc_x, acc_y;

	struct surf_state last_state, states;
/* return [true] if the event was consumed and shouldn't be processed by the
 * default handler */
	bool (*dispatch)(struct comp_surf*, struct arcan_event* ev);
	int cookie;
};

static bool displayhint_handler(struct comp_surf* surf,
	struct arcan_tgtevent* tev);

static void enter_all(struct comp_surf*);
static void leave_all(struct comp_surf*);

static void try_frame_callback(
	struct comp_surf* surf, struct arcan_shmif_cont*);

/*
 * this is to share the tracking / allocation code between both clients and
 * surfaces and possible other wayland resources that results in a 1:1 mapping
 * to an arcan connection that needs to have its event loop flushed.
 */
#define SLOT_TYPE_CLIENT 1
#define SLOT_TYPE_SURFACE 2
struct bridge_slot {
	int type;
	char idch;
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

#endif
