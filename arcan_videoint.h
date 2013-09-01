/* Arcan-fe, scriptable front-end engine
 * 
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,USA
 */

#ifndef _HAVE_ARCAN_VIDEOINT
#define _HAVE_ARCAN_VIDEOINT

#ifndef RENDERTARGET_LIMIT
#define RENDERTARGET_LIMIT 32 
#endif


enum rendertarget_mode {
	RENDERTARGET_DEPTH = 0,
	RENDERTARGET_COLOR = 1,
	RENDERTARGET_COLOR_DEPTH = 2,
	RENDERTARGET_COLOR_DEPTH_STENCIL = 3
};

struct arcan_vobject_litem;
struct arcan_vobject;

struct rendertarget {
/* depth and stencil are combined as stencil_index 
 * formats have poor driver support */
	unsigned fbo, depth;

/* only used / allocated if readback != 0 */ 
	unsigned pbo;
	
/* think of base as identity matrix, sometimes with added scale */
	float base[16];
	float projection[16];
	
/* readback == 0, no readback. Otherwise, a readback is requested 
 * every abs(readback) frames. if readback is negative, 
 * or readback ticks if it is positive */
	int readback;
	long long readcnt;

/* flagged after a PBO readback has been issued, 
 * cleared when buffer have been mapped */
	bool readreq; 

	enum rendertarget_mode mode;

/* each rendertarget can have one possible camera attached to it
 * which affects the 3d pipe. This is defaulted to BADID until 
 * a vobj is explicitly camtaged */
	arcan_vobj_id camtag;

/* color representes the attached vid, 
 * first is the pipeline (subset of context vid pool) */
	struct arcan_vobject* color;
	struct arcan_vobject_litem* first;
};

struct transf_move{
	enum arcan_interp_function interp;
	arcan_tickv startt, endt;
	point startp, endp;
};

struct transf_scale{
	enum arcan_interp_function interp;
	arcan_tickv startt, endt;
	scalefactor startd, endd;
};

struct transf_blend{
	enum arcan_interp_function interp;
	arcan_tickv startt, endt;
	float startopa, endopa;
};

struct transf_rotate{
	enum arcan_interp_function interp;
	arcan_tickv startt, endt;
	surface_orientation starto, endo;
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
struct storage_info_t {
	unsigned refcount;
	bool txmapped;

	union {
		struct {
			unsigned  glid; /* GLUint should always be unsigned int */
			uint32_t s_raw;
			uint8_t*   raw;
			char*   source;
		} text;
		struct {
			float r;
			float g;
			float b;
		} col;
	} vinf; 

	unsigned short w, h, bpp;
	unsigned txu, txv;
	
	enum arcan_vimage_mode    scale;
	enum arcan_imageproc_mode imageproc;
	enum arcan_vfilter_mode   filtermode;
};

typedef struct arcan_vobject {
/*
 * image-storage / reference,
 * current_frame is set to default_frame, but could well reference 
 * another object (frameset) 
 */
	struct arcan_vobject* current_frame;
	uint16_t origw, origh;

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
	} feed;

/* basic texture mapping, can be overridden (to mirror, skew etc.) */
	float txcos[8];
	enum arcan_blendfunc blendmode;

	struct {
		bool in_use;         /* must be set for any operation other than allocate */
		bool clone;          /* limited features, inherits from another obj       */
		char cliptoparent;   /* only draw to the parent object surface area       */
		bool asynchdisable;  /* don't run any asynchronous loading operations     */
		bool cycletransform; /* when a transform is finished, attach it to the end*/
		bool origoofs;       /* use world-space coordinate as center for rotation */
		bool orderofs;       /* ofset is relative parent                          */
#ifdef _DEBUG
		bool frozen;         /* tag for debugging */
#endif
/* with this flag set, the object will be maintained in every "higher" context
 * position, and only deleted if pop:ed off without existing in a lower layer.
 * They can't be rendertargets, nor be instanced or linked (anything that would
 * allow for dangling references) primary use is for frameserver connections */
		bool persist;
	} flags;
	
/* position */
	signed int order;
	surface_properties current;
	point origo_ofs;
	
	surface_transform* transform;
	enum arcan_transform_mask mask;
	
/* transform caching,
 * the invalidated flag will be active as long as there are running
 * transformations for the object in question, or if there's running
 * transformations somewhere in the parent chain */
	bool valid_cache, rotate_state;
	surface_properties prop_cache;
	float prop_matr[16];

/* life-cycle tracking */
	unsigned long last_updated;
	long lifetime;
	
/* management mappings */
	struct arcan_vobject* parent;
	struct arcan_vobject** children;
	unsigned childslots;

	struct rendertarget* owner;
	arcan_vobj_id cellid;

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
	bool vsync, fbo_support, pbo_support;
	enum arcan_order3d order3d;

	unsigned default_vitemlim;
 
	arcan_shader_id defaultshdr;
	arcan_shader_id defclrshdr;
	
/* default image loading options */
	enum arcan_vimage_mode scalemode;
	enum arcan_imageproc_mode imageproc;
	enum arcan_vfilter_mode filtermode;
	
	unsigned deftxs, deftxt;
	bool mipmap;
	
	uint32_t sdlarg;
	
	unsigned char bpp;
	unsigned short width, height;
	uint32_t c_ticks;
	
	unsigned char msasamples;
	float vsync_timing, vsync_stddev, vsync_variance;

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

static void drop_glres(struct storage_info_t* s);

int arcan_debug_pumpglwarnings(const char* src);
void arcan_resolve_vidprop(arcan_vobject* vobj, 
	float lerp, surface_properties* props);

arcan_vobject* arcan_video_getobject(arcan_vobj_id id);
arcan_vobject* arcan_video_newvobject(arcan_vobj_id* id);

arcan_errc arcan_video_attachobject(arcan_vobj_id id);
arcan_errc arcan_video_deleteobject(arcan_vobj_id id);

arcan_errc arcan_video_getimage(const char* fname, arcan_vobject* dst,
	img_cons forced, bool asynchsrc);

void arcan_video_setblend(const surface_properties* dprops, 
	const arcan_vobject* elem);

#ifdef _DEBUG
void arcan_debug_tracetag_dump();
#endif

/* only ever used for next power of two concerning dislay resolutions */
uint16_t nexthigher(uint16_t k);

struct arcan_img_meta;
void push_globj(arcan_vobject*, bool, struct arcan_img_meta*);
void generate_basic_mapping(float* dst, float st, float tt);
void generate_mirror_mapping(float* dst, float st, float tt);

/*
 * To split between GLFX/EGL/SDL/etc. All relevant settings are predefined in
 * arcan_video_display, and these just implement the necessary foreplay
 */ 
bool arcan_videodev_init();
void arcan_videodev_deinit();

void arcan_3d_setdefaults();

/* sweep the glstor and bind the corresponding 
 * texture units (unless we hit the limit that is) */
unsigned arcan_video_pushglids(struct storage_info_t* glstor,unsigned ofs);
arcan_vobject_litem* arcan_refresh_3d(arcan_vobj_id camtag,
	arcan_vobject_litem* cell, float frag);

int stretchblit(char* src, int srcw, int srch,
	uint32_t* dst, int dstw, int dsth, int flipy);
#endif
