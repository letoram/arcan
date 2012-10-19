/* Arcan-fe, scriptable front-end engine
 * 
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#ifndef _HAVE_ARCAN_VIDEOINT
#define _HAVE_ARCAN_VIDEOINT

#ifndef RENDERTARGET_LIMIT
#define RENDERTARGET_LIMIT 6 
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
/* depth and stencil are combined as stencil_index formats have poor driver support */
	unsigned fbo, depth;

/* only used / allocated if readback != 0 */ 
	unsigned pbo;
	
/* think of base as identity matrix, sometimes with added scale */
	float base[16];  
	float projection[16];
	
/* readback == 0, no readback. Otherwise, a readback is requested every abs(readback) frames
 * if readback is negative, or readback ticks if it is positive */
	int readback;
	long long readcnt;

/* flagged after a PBO readback has been issued, cleared when buffer have been mapped */
	bool readreq; 

	enum rendertarget_mode mode;

/* color representes the attached vid, first is the pipeline (subset of context vid pool) */
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

/* these are arranged in a linked list of slots,
 * where one slot may contain one of each transform categories
 * and will be packed "to the left" each time any one of them finishes */
typedef struct surface_transform {

	struct transf_move move;
	struct transf_scale scale;
	struct transf_blend blend;
	struct transf_rotate rotate;
	
	struct surface_transform* next;
} surface_transform;

typedef struct arcan_vstorage {
	uint32_t s_raw;
	uint8_t* raw;
	char* source;
} arcan_vstorage;

struct storage_info_t {
	unsigned int glid;
		
	unsigned short w, h, bpp;
	unsigned int txu, txv;
	
	enum arcan_vimage_mode scale;
	enum arcan_imageproc_mode imageproc;
	enum arcan_vfilter_mode filtermode;

	arcan_shader_id program;
};

typedef struct arcan_vobject {
/* image-storage / reference,
 * current_frame is set to default_frame, but could well reference another object (frameset) */
	arcan_vstorage default_frame;
	struct arcan_vobject* current_frame;
	uint16_t origw, origh;

	struct arcan_vobject** frameset;
	struct {
		unsigned short capacity; /* only allowed to grow */
		signed short mode; /* automatic cycling, > 0 per tick, < 0 per frame */
		unsigned short counter; /* keeps track on steps left until cycle */
		unsigned short current; /* current frame, might be "dst" */
		enum arcan_framemode framemode; /* multitexture or just active frame */
	} frameset_meta;
	
	struct storage_info_t gl_storage;
	
/* support for feed- functions
 * set to null if no feed functions are avail.
 * [note] this might be more handy as a per/frame thing */
	struct {
		arcan_vfunc_cb ffunc;
		vfunc_state state;
	} feed;
	
	uint8_t ffunc_mask;

/* basic texture mapping, can be overridden (to mirror, skew etc.) */
	float txcos[8];
	enum arcan_blendfunc blendmode;

	struct {
		bool in_use;         /* must be set for any operation other than allocate to be valid */
		bool clone;          /* limits the set of allowed operations from those that allocate resources or link */
		bool cliptoparent;   /* only draw to the parent object surface area */
		bool asynchdisable;  /* don't run any asynchronous loading operations */
		bool cycletransform; /* when a transform is finished, attach it to the end */
		bool origoofs;       /* when the user defines a world-space coordinate as center for rotation */
	} flags;
	
/* position */
	signed int order;
	surface_properties current;
	point origo_ofs;
	
	surface_transform* transform;
	enum arcan_transform_mask mask;
	
/* life-cycle tracking */
	unsigned long last_updated;
	long lifetime;
	
/* management mappings */
	struct arcan_vobject* parent;
	struct rendertarget* owner;
	arcan_vobj_id cellid;

/* for integrity checks, a destructive operation on a !0 reference count is a terminal state */
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
	bool suspended, text_support, fullscreen, conservative, vsync;
	enum arcan_order3d order3d;

	unsigned default_vitemlim;
 
	arcan_shader_id defaultshdr;
	
	/* default image loading options */
	enum arcan_vimage_mode scalemode;
	enum arcan_imageproc_mode imageproc;
	enum arcan_vfilter_mode filtermode;
	
	unsigned deftxs, deftxt;
    	bool mipmap;
	
	SDL_Surface* screen;
	uint32_t sdlarg;
	
	unsigned char bpp;
	unsigned short width, height;
	uint32_t c_ticks;
	
	unsigned char msasamples;
	float vsync_timing;
};

extern struct arcan_video_display arcan_video_display;
int arcan_debug_pumpglwarnings(const char* src);
void arcan_resolve_vidprop(arcan_vobject* vobj, float lerp, surface_properties* props);
arcan_vobject* arcan_video_getobject(arcan_vobj_id id);
arcan_vobject* arcan_video_newvobject(arcan_vobj_id* id);
arcan_errc arcan_video_attachobject(arcan_vobj_id id);
arcan_errc arcan_video_deleteobject(arcan_vobj_id id);
arcan_errc arcan_video_getimage(const char* fname, arcan_vobject* dst, arcan_vstorage* dstframe, img_cons forced, bool asynchsrc);
void arcan_video_setblend(const surface_properties* dprops, const arcan_vobject* elem);

#ifdef _DEBUG
void arcan_debug_tracetag_dump();
#endif

/* only ever used for next power of two concerning dislay resolutions */
uint16_t nexthigher(uint16_t k);

void generate_basic_mapping(float* dst, float st, float tt);
void generate_mirror_mapping(float* dst, float st, float tt);

void arcan_3d_setdefaults();

/* sweep the glstor and bind the corresponding texture units (unless we hit the imit that is) */
unsigned int arcan_video_pushglids(struct storage_info_t* glstor, unsigned ofs);
arcan_vobject_litem* arcan_refresh_3d(unsigned camtag, arcan_vobject_litem* cell, float frag, unsigned int destination);

int stretchblit(SDL_Surface* src, uint32_t* dst, int dstw, int dsth, int dstpitch, int flipy);
#endif
