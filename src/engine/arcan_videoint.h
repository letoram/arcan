/*
 * Copyright 2014, Björn Ståhl
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

/* color representes the attached vid,
 * first is the pipeline (subset of context vid pool) */
	struct arcan_vobject* color;
	struct arcan_vobject_litem* first;

	struct rendertarget_store* store;

	enum rtgt_flags flags;

/* readback == 0, no readback. Otherwise, a readback is requested
 * every abs(readback) frames. if readback is negative,
 * or readback ticks if it is positive */
	int readback;
	long long readcnt;

/*
 * number of running transformation, pending transformations +
 * active frameservers is a decent measurement for the complexity of
 * a rendertarget
 */
	size_t transfc;

/* each rendertarget can have one possible camera attached to it
 * which affects the 3d pipe. This is defaulted to BADID until
 * a vobj is explicitly camtaged */
	arcan_vobj_id camtag;
};

enum vobj_flags {
	FL_INUSE  = 1,
	FL_CLONE  = 2,
	FL_NASYNC = 4,
	FL_TCYCLE = 8,
	FL_ROTOFS = 16,
	FL_ORDOFS = 32,
	FL_PRSIST = 64,
#ifdef _DEBUG
	FL_FROZEN = 128
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

/*
 * refcount is usually defaulted to 1 or ignored,
 * otherwise it indicates that the storage is
 * shared between multiple vobjects (sprite-sheets,
 * binpacked font pages etc.)
 *
 * we separate single color (program is bound
 * and quad is sent and a vec3 col uniform is expected,
 * but no texture is bound)
 */

enum txstate {
	TXSTATE_OFF   = 0,
	TXSTATE_TEX2D = 1,
	TXSTATE_DEPTH = 2
};

/*
 * Overly bloated and thus a nasty cache influence,
 * when optimization rounds come as part of 1.0 effort
 * this should be trimmed down to 64-byte modulo and
 * profiled extensively for cache behavior,
 * re-order based on access patterns, full quat/matrix- transforms
 * should be moved to 3d objects, refcounts only for debug etc.
 * There's a ton of possible optimizations here but only after
 * the featureset is frozen and GL has been refactored to its
 * respective platform* level.
 */
typedef struct arcan_vobject {
	enum vobj_flags flags;

	struct arcan_vobject* current_frame;
	uint16_t origw, origh;

/*
 * image-storage / reference,
 * current_frame is set to default_frame, but could well reference
 * another object (frameset)
 */
struct arcan_vobject** frameset;
	struct {
		unsigned short capacity;        /* only allowed to grow                   */
		signed short mode;              /* cycling, > 0 per tick, < 0 per frame   */
		unsigned short counter;         /* keeps track on steps left until cycle  */
		unsigned short current;         /* current frame, might be "dst"          */
		enum arcan_framemode framemode; /* multitexture or just active frame      */
	} frameset_meta;

	struct storage_info_t* vstore;
	arcan_shader_id program;

	struct {
		arcan_vfunc_cb ffunc;
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
	struct arcan_vobject* parent;
	enum parent_anchor p_anchor;

	struct arcan_vobject** children;
	unsigned childslots;

	struct rendertarget* owner;
	arcan_vobj_id cellid;

#ifdef _DEBUG
	bool frozen;
#endif

/* for integrity checks, a destructive operation on a
 * !0 reference count is a terminal state */
	struct {
		signed framesets;
		signed instances;
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
	bool suspended, fullscreen, conservative;

	int dirty;
	bool ignore_dirty;
	enum arcan_order3d order3d;

/*
 * track mouse-cursor as a separate entity that re-uses
 * an image vstore, in order to have a default FBO that
 * is rendered to and not cause excessive refreshes.
 */
	struct {
		struct storage_info_t* vstore;
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

/* these all represent a subset of the current context that is to be drawn.
 * if (dest != NULL) this means that the vid actually represents a rendertarget,
 * e.g. FBO. The mode defines which output buffers (color, depth, ...)
 * that should be stored. Readback defines if we want a PBO- or glReadPixels
 * style  readback into the .raw buffer of the target. reset defines if any of
 * the intermediate buffers should be cleared beforehand. first refers to the
 * first object in the subset. if first and dest are null, stop processing
 * the list of rendertargets. */
struct arcan_video_context {
	unsigned vitem_ofs;
	unsigned vitem_limit;
	long int nalive;
	arcan_tickv last_tickstamp;

	arcan_vobject world;
	arcan_vobject* vitems_pool;

	struct rendertarget rtargets[RENDERTARGET_LIMIT];
	ssize_t n_rtargets;

	struct rendertarget stdoutp;
};

extern struct arcan_video_context vcontext_stack[];
extern unsigned vcontext_ind;
extern struct arcan_video_display arcan_video_display;

/*
 * Perform a render-pass, set synch to true if we should block
 * Fragment is in the 0..999 range and specifies how far we are
 * towards the next logical tick. This is used to calculate interpolations
 * for transformation chains to get smoother animation even when running
 * with a slow logic clock.
 *
 * This will only populate the underlying vstores, mapping to the
 * output display is made by the platform_video_sync function.
 */
unsigned arcan_vint_refresh(float fragment, size_t* ndirty);

int arcan_debug_pumpglwarnings(const char* src);
void arcan_resolve_vidprop(arcan_vobject* vobj,
	float lerp, surface_properties* props);

arcan_vobject* arcan_video_getobject(arcan_vobj_id id);
arcan_vobject* arcan_video_newvobject(arcan_vobj_id* id);

/*
 * agp_drop_vstore does not explicitly manage reference
 * counting etc. that is up to the video layer,
 * and should rarely be used directly
 */
void arcan_vint_drop_vstore(struct storage_info_t* s);

arcan_errc arcan_video_attachobject(arcan_vobj_id id);
arcan_errc arcan_video_deleteobject(arcan_vobj_id id);

arcan_errc arcan_video_getimage(const char* fname, arcan_vobject* dst,
	img_cons forced, bool asynchsrc);

void arcan_video_setblend(const surface_properties* dprops,
	const arcan_vobject* elem);

#ifdef _DEBUG
void arcan_debug_tracetag_dump();
#endif

struct storage_info_t* arcan_vint_world();

struct arcan_img_meta;
void generate_basic_mapping(float* dst, float st, float tt);
void generate_mirror_mapping(float* dst, float st, float tt);
void arcan_video_joinasynch(arcan_vobject* img, bool emit, bool force);
struct rendertarget* find_rendertarget(arcan_vobject* vobj);

void arcan_vint_drawrt(struct storage_info_t*, int x, int y, int w, int h);
void arcan_vint_drawcursor(bool erase);

void arcan_3d_setdefaults();

/* sweep the glstor and bind the corresponding
 * texture units (unless we hit the limit that is) */
unsigned arcan_video_pushglids(struct storage_info_t* glstor,unsigned ofs);
arcan_vobject_litem* arcan_refresh_3d(arcan_vobj_id camtag,
	arcan_vobject_litem* cell, float frag);
#endif
