/*
 * Copyright 2003-2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * Structures and functions primarily intended for low-level components,
 * i.e. platform drivers and (in rare circumstances) -script system mapping.
 */

#ifndef _HAVE_ARCAN_VIDEOINT
#define _HAVE_ARCAN_VIDEOINT

#ifndef RENDERTARGET_LIMIT
#define RENDERTARGET_LIMIT 64
#endif

/*
 *  Indicate that the video pipeline is in such a state that
 *  it should be redrawn. X should be NULL or a vobj reference
 *  (to permit partial redraws in the future if we need to save
 *  bandwidth).
 */
#define FLAG_DIRTY(X) (arcan_video_display.dirty++);

#define FL_SET(obj_ptr, fl) ((obj_ptr)->flags |= fl)
#define FL_CLEAR(obj_ptr, fl) ((obj_ptr)->flags &= ~fl)
#define FL_TEST(obj_ptr, fl) (( ((obj_ptr)->flags) & (fl)) > 0)

struct arcan_vobject_litem;
struct arcan_vobject;

enum rtgt_flags {
	TGTFL_READING = 1,
	TGTFL_ALIVE   = 2,
	TGTFL_NOCLEAR = 4
};

struct rendertarget {
/* think of base as identity matrix, sometimes with added scale */
	_Alignas(16) float base[16];
	_Alignas(16) float projection[16];

/* identifier for matching against shader */
	int id;

/* color representes the attached vid,
 * first is the pipeline (subset of context vid pool) */
	struct arcan_vobject* color;
	struct arcan_vobject_litem* first;

/* it is possible for one rendertarget to share the pipeline with
 * another, if so, first is set to NULL and link points to the rtgt vid */
	struct rendertarget* link;

/* corresponding agp backend store for the rendertarget in question */
	struct agp_rendertarget* art;

	enum rtgt_flags flags;
	enum arcan_order3d order3d;

/* readback == 0, no readback. Otherwise, a readback is requested
 * every abs(readback) frames. if readback is negative,
 * or readback ticks if it is positive */
	int readback;
	int readcnt;

/* for for controlling refresh, same mechanism as with readback */
	int refresh;
	int refreshcnt;

/*
 * number of running transformation, pending transformations, active
 * frameservers and shader-load is a decent measurement for the complexity of a
 * rendertarget
 */
	size_t transfc;

/*
 * dirty- management is still incomplete in two ways, one is that dirty-
 * flagging is a global video state and not bound to rendertarget which is in
 * conflict with rendertargets being updated at different clocks.
 * second is that we do not consider the dirty- area, and just go for a full
 * redraw when it is time. Important optimizations but still low on the list.
 * When it is to be implemented, use this variable, an list of invalidation
 * rects and sweep the codebase for FLAG_DIRTY
 */
	size_t dirtyc;

/*
 * track density per rendertarget, this affects some video objects that gets
 * attached in that they are rerasterized to match the properties of the new
 * rtgt.
 */
	float hppcm, vppcm;

/* each rendertarget can have one possible camera attached to it which affects
 * the 3d pipe. This is defaulted to BADID until a vobj is explicitly camtaged */
	arcan_vobj_id camtag;

/*
 * to be able to temporarily cut off certain order values from being drawn,
 * we need to track the lower accepted bounds and the max accepted bounds.
 */
	size_t min_order, max_order;
};

enum vobj_flags {
	FL_INUSE  = 1,
	FL_NASYNC = 2,
	FL_TCYCLE = 4,
	FL_ROTOFS = 18,
	FL_ORDOFS = 16,
	FL_PRSIST = 32,
	FL_FULL3D = 64, /* switch to a quaternion- based orientation scheme */
	FL_RTGT   = 128,
#ifdef _DEBUG
	FL_FROZEN = 256
#else
#endif
};

struct transf_move{
	unsigned char interp;
	arcan_tickv startt, endt;
	point startp, endp;
	intptr_t tag;
};

struct transf_scale{
	unsigned char interp;
	arcan_tickv startt, endt;
	scalefactor startd, endd;
	intptr_t tag;
};

struct transf_blend{
	unsigned char interp;
	arcan_tickv startt, endt;
	float startopa, endopa;
	intptr_t tag;
};

struct transf_rotate{
	arcan_interp_4d_function interp;
	arcan_tickv startt, endt;
	surface_orientation starto, endo;
	intptr_t tag;
};

/*
 * these are arranged in a linked list of slots,
 * where one slot may contain one of each transform categories
 * and will be packed "to the left" each time any one of them finishes
 */
typedef struct surface_transform {

	struct transf_move   move;
	struct transf_scale  scale;
	struct transf_blend  blend;
	struct transf_rotate rotate;

	struct surface_transform* next;
} surface_transform;

struct frameset_store {
	struct agp_vstore* frame;
	float txcos[8];
};

struct vobject_frameset {
	struct frameset_store* frames;
	size_t n_frames; /* number of slots in frames */
	size_t index; /* current frame */
	int ctr; /* ticks- left counter */
	int mctr; /* counter- limits */
	enum arcan_framemode mode; /* how frameset should be applied */
};

/*
 * Contents of this structure has grown from horrible to terrible over time.
 * It is due for a long overhaul as soon as regression and benchmark coverage
 * is up to a sufficient standard.
 *
 * List of planned changes:
  *  - pack all flags -> in total, we have somewhere around 20-30 possible
 *                      flags and masks, these should be packed into one
 *                      uint32
 *
 *  - reference counters -> only enabled and present in debug mode
 *
 *  - smaller types -> a lot of members use way to large integer ranges
 *
 *  - rendertargets -> dynamically grow, pack / re-arrange on creation
 *
 *  - prefetch vobj->next and vobj
 *
 *  - use external re-order tool to cut down on padding
 *
 *  - null- terminate children
 */
typedef struct arcan_vobject {
	struct arcan_vobject* parent;
	struct arcan_vobject** children;

	struct vobject_frameset* frameset;
	struct agp_vstore* vstore;

	enum vobj_flags flags;
	uint16_t origw, origh;

/* visual modifiers */
	agp_shader_id program;
	struct agp_mesh_store* shape;

	struct {
		enum arcan_ffunc ffunc;
		vfunc_state state;
		int pcookie;
	} feed;

/* if NULL, a default mapping will be used */
	float* txcos;
	enum arcan_blendfunc blendmode;

/* position */
	signed int order;
	surface_properties current;
	point origo_ofs;

	surface_transform* transform;
	enum arcan_transform_mask mask;
	enum arcan_clipmode clip;

/* transform caching,
 * the invalidated flag will be active as long as there are running
 * transformations for the object in question, or if there's running
 * transformations somewhere in the parent chain */
	bool valid_cache, rotate_state;
	surface_properties prop_cache;
	float _Alignas(16) prop_matr[16];

/* life-cycle tracking */
	unsigned long last_updated;
	long lifetime;

/* management mappings */
	enum parent_anchor p_anchor;

	unsigned childslots;

	struct rendertarget* owner;
	arcan_vobj_id cellid;

#ifdef _DEBUG
	bool frozen;
#endif

/* for integrity checks, a destructive operation on a
 * !0 reference count is a terminal state */
	struct {
		signed attachments;
		signed links;
	} extrefc;

	char* tracetag;
} arcan_vobject;

/* regular old- linked list, but also mapped to an array */
struct arcan_vobject_litem {
	arcan_vobject* elem;
	struct arcan_vobject_litem* next;
	struct arcan_vobject_litem* previous;
};
typedef struct arcan_vobject_litem arcan_vobject_litem;

struct arcan_video_display {
	bool suspended, fullscreen, conservative, in_video, no_stdout;

	int dirty;
	bool ignore_dirty;
	enum arcan_order3d order3d;

/*
 * track mouse-cursor as a separate entity that re-uses an image vstore, in
 * order to have a default FBO that is rendered to and not cause excessive
 * refreshes.
 */
	struct {
		struct agp_vstore* vstore;
		int x, ox;
		int y, oy;
		size_t w;
		size_t h;
		bool active;
	} cursor;

	unsigned default_vitemlim;

	float default_projection[16];
	float window_projection[16];

	float default_txcos[8];
	float cursor_txcos[8];
	float mirror_txcos[8];

/* default image loading options */
	enum arcan_vimage_mode scalemode;
	enum arcan_imageproc_mode imageproc;
	enum arcan_vfilter_mode filtermode;

	unsigned deftxs, deftxt;
	bool mipmap;

	arcan_tickv c_ticks;
	float c_lerp;

	unsigned char msasamples;
	char* txdump;
};

/* these all represent a subset of the current context that is to be drawn.  if
 * (dest != NULL) this means that the vid actually represents a rendertarget,
 * e.g. FBO. The mode defines which output buffers (color, depth, ...) that
 * should be stored. Readback defines if we want a PBO- or glReadPixels style
 * readback into the .raw buffer of the target. reset defines if any of the
 * intermediate buffers should be cleared beforehand. first refers to the first
 * object in the subset. if first and dest are null, stop processing the list
 * of rendertargets. */
struct arcan_video_context {
	unsigned vitem_ofs;
	unsigned vitem_limit;
	long int nalive;
	arcan_tickv last_tickstamp;

	arcan_vobject world;
	arcan_vobject* vitems_pool;

	struct rendertarget rtargets[RENDERTARGET_LIMIT];
	struct rendertarget* attachment;
	ssize_t n_rtargets;

	struct rendertarget stdoutp;
};

extern struct arcan_video_context vcontext_stack[];
extern unsigned vcontext_ind;
extern struct arcan_video_display arcan_video_display;

/*
 * Perform a render-pass, set synch to true if we should block Fragment is in
 * the 0..999 range and specifies how far we are towards the next logical tick.
 * This is used to calculate interpolations for transformation chains to get
 * smoother animation even when running with a slow logic clock.
 *
 * This will only populate the underlying vstores, mapping to the output
 * display is made by the platform_video_sync function.
 */
unsigned arcan_vint_refresh(float fragment, size_t* ndirty);

/*
 * populate props with the (possibly cached) transformation state
 * of existing video object (vobj) at interpolation stage (0..1)
 */
void arcan_resolve_vidprop(arcan_vobject* vobj,
	float lerp, surface_properties* props);

arcan_vobject* arcan_video_getobject(arcan_vobj_id id);
arcan_vobject* arcan_video_newvobject(arcan_vobj_id* id);

/*
 * agp_drop_vstore does not explicitly manage reference counting etc. that is
 * up to the video layer. All cases that access s-> directly should be
 * manually inspected.
 */
void arcan_vint_drop_vstore(struct agp_vstore* s);

/* check if a pending readback is completed, and process it if it is. */
void arcan_vint_pollreadback(struct rendertarget* rtgt);

/*
 * ensure that the video object pointed to by id is attached to the
 * currently active (main) rendergarget
 */
arcan_errc arcan_vint_attachobject(arcan_vobj_id id);

/*
 * semaphore- rate limited image decoding and repacking to native
 * format used both threaded and non-threaded
 */
arcan_errc arcan_vint_getimage(const char* fname,
	arcan_vobject* dst, img_cons forced, bool asynchsrc);

#ifdef _DEBUG
void arcan_debug_tracetag_dump();
#endif

/*
 * access to the current rendertarget backend store for primary rendertarget
 * used primarily by the video-platform layer
 */
struct agp_vstore* arcan_vint_world();
struct agp_rendertarget* arcan_vint_worldrt();

/*
 * generate the normal set of texture coordinates (should be CW:
 * 0.0 , 1.0,  1.1,  0.1
 */
void arcan_vint_defaultmapping(float* dst, float st, float tt);

/*
 * same as basic mapping but invert T to aaccount for LL origo vs UL
 */
void arcan_vint_mirrormapping(float* dst, float st, float tt);

/*
 * try to complete vobject asynchronous loading process, set emit to have the
 * asynch- loaded event propagate and force to wait for completion
 */
void arcan_vint_joinasynch(arcan_vobject* img, bool emit, bool force);

void arcan_vint_reraster(arcan_vobject* img, struct rendertarget*);

/*
 * Figure out what the vid will be for the next object allocated in this
 * context. This function is primarily used to avoid an initialization
 * order problem in frameserver allocation tagging, needed to, in turn,
 * avoid a linear search on VIEWPORT hints.
 */
arcan_vobj_id arcan_vint_nextfree();

/*
 * get the internal structure of the rendertarget that vobj has as
 * its primary attachment (for ordering etc.)
 */
struct rendertarget* arcan_vint_findrt(arcan_vobject* vobj);
struct rendertarget* arcan_vint_findrt_vstore(struct agp_vstore* st);

/*
 * used by the video platform layer, assume that agp_vstore points
 * to the backing end of a rendertarget, and draw it to the bound output-rt
 * at the specified (x,y, x+w, y+h) position
 */
void arcan_vint_drawrt(struct agp_vstore*, int x, int y, int w, int h);

/*
 * [may be] used by the video platform layer to share the normal hinting
 * settings between implementations
 */
void arcan_vint_applyhint(arcan_vobject* src, enum blitting_hint hint,
	float* txcos_in, float* txcos_out,
	size_t* out_x, size_t* out_y,
	size_t* out_w, size_t* out_h, size_t* blackframes);

/*
 * Explicitly trigger a new pollfeed step. If [step] is set, any new frames
 * will be committed and trigger cookie updates, events and so on. If it is
 * not set, only the sanity- check and resize processing will be handled.
 */
arcan_errc arcan_vint_pollfeed(arcan_vobj_id vid, bool step);

/*
 * accessor for the rendertarget currently (thread_local) marked as active
 */
struct rendertarget* arcan_vint_current_rt();

/*
 * used by the video platform layer for "accelerated" cursor drawing,
 * meaning that !erase draws using the backing store set as the cursor
 * and erase draws using the current attached rendertarget
 */
void arcan_vint_drawcursor(bool erase);
#endif
