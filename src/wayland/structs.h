#ifndef HAVE_STRUCTS

#define STEP_SERIAL() ( wl_display_next_serial(wl.disp) )
#define MAX_SEATS 8

enum internal_command {
	CMD_NONE = 0,
	CMD_RECONFIGURE = 1,
	CMD_FLUSH_CALLBACKS = 2
};

struct xkb_stateblock {
	struct xkb_context* context;
	struct xkb_keymap* map;
	struct xkb_state* state;
	const char* map_str;
};

/* Walking this per input operation can be very expensive as mouse operations
 * are high-frequency and something like intersect of multiples are requested.
 * Limit depth / count for these are generally a good idea - hence the linked
 * list of blocks. */
struct surface_region;

enum {
	REGION_OP_IGNORE = 0,
	REGION_OP_ADD    = 1,
	REGION_OP_SUB    = 2
};

struct data_offer {
	struct wl_resource* device;
	struct wl_resource* offer;
	struct wl_client* client;
};

struct region {
	int op;
	ssize_t x1, y1, x2, y2;
};

struct surface_region {
	struct region regions[4];
	struct surface_region* next;
};

struct seat {
	struct xkb_stateblock kbd_state;

	struct wl_resource* kbd;
	struct wl_resource* in_kbd;

	struct wl_resource* ptr;
	struct wl_resource* rel_ptr;
	struct wl_resource* in_ptr;

	struct wl_resource* touch;
	struct wl_resource* in_touch;

	bool used;
};

struct bridge_client {
	struct arcan_shmif_cont acon;
	struct wl_listener l_destr;
	struct wl_listener l_pending;

/* seat / wl-api mapping references */
	struct wl_client* client;

/* some clients rely on multiple seat objects, we still broadcast to all
 * of them though when mapping events */
	struct seat seats[MAX_SEATS];

	struct wl_resource* output; /* only 1 atm */
	struct {
		struct wl_resource* have_xdg;
		int size_px[2];
		float density[2];
		float rate;
	} output_state;

/* cursor states, we want to share one subseg connection
 * and just switch surface resource around */
	struct arcan_shmif_cont acursor;
	struct wl_resource* cursor;
	int32_t hot_x, hot_y;
	bool dirty_hot;
	bool mask_absolute;
	struct wl_resource* lock_region;
	struct wl_resource* locked;
	struct wl_resource* confined;
	struct arcan_event confine_event;

/* see ddev */
	struct data_offer* doffer_copy;
	struct data_offer* doffer_drag;
	struct data_offer* doffer_paste;
	char doffer_type[64];

/* need to track these so that we can send enter/leave correctly,
 * watch out for UAFs */
	struct wl_resource* last_cursor;
	struct wl_resource* last_kbd;

/* to keep an association across display server instances */
	uint64_t guid[2];

/* track keycodes of keys that are pressed so we can fake release
 * if a window gets defocused as a way of 'resetting' the keymap,
 * this don't take latched modifiers or dicretics into account */
	uint8_t keys[512];

/* used to assign initial scale for new surfaces */
	float scale;

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
	bool drag_resize : 1;
	bool fullscreen : 1;

/* set by xdgdecor */
	bool ssd : 1;
	bool csd : 1;
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

/* used with zxdg_toplevel_decoration and kwin- decor
 * 0 = no change,
 * otherwise forward value to decorator */
	int pending_decoration;
	struct wl_resource* decor_mgmt;

/* mark the surface as supposed to commit, but some reason (ongoing sync
 * or similar) forced us to reconsider at a later stage. */
	bool pending_commit;
	struct wl_resource* confined;

	bool locked;
	struct surface_region* confine_region;

/*
 * surfaces that are passed as shm- buffers might be better to bind to a
 * GPU from the waybridge process as we both save a copy (no good way to
 * map the buffer- pool to shmif- vidp), and can safely upload a texture
 * to the GPU without risking a stall due to the main process being busy
 * with GL context locked on synch.
 */
	bool shm_gl_fail;

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

/* input state for cursor on the surface */
	uint8_t mstate_abs[ASHMIF_MSTATE_SZ];
	uint8_t mstate_rel[ASHMIF_MSTATE_SZ];
	bool has_ptr, has_kbd;

/*
 * need to cache/update this one whenever we reparent, etc.
 */
	bool is_subsurface;
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

/* clients doesn't "scale" in shmif, you either draw it at the hinted
 * dimensions at the proper density or the server side will do 'something',
 * for wl we need to apply a transform hint */
	float scale;

/* need to track these so that we can subtract from displayhints..*/
	uint32_t geom_w, geom_h, geom_x, geom_y;

	struct surf_state last_state, states;
/* return [true] if the event was consumed and shouldn't be processed by the
 * default handler */
	bool (*dispatch)(struct comp_surf*, struct arcan_event* ev);

/* edge cases that require some shell specific actions */
	void (*internal)(struct comp_surf*, int command);

	int cookie;
};

static bool displayhint_handler(struct comp_surf* surf,
	struct arcan_tgtevent* tev);

static void enter_all(struct comp_surf*);
static void leave_all(struct comp_surf*);
static void try_frame_callback(struct comp_surf* surf);

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
