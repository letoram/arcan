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

struct arcan_vobject_item;

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
		
		unsigned short w, h;
		unsigned char ncpt;
		unsigned int txu, txv;
		enum arcan_vimage_mode scale;
		enum arcan_imageproc_mode imageproc;

		arcan_shader_id program;
};

typedef struct arcan_vobject {
	/* image-storage / reference,
	 * current_frame is set to default_frame */
	arcan_vstorage default_frame;
	struct arcan_vobject* current_frame;
	uint16_t origw, origh;

	struct arcan_vobject** frameset;
	unsigned frameset_capacity;
	
	struct storage_info_t gl_storage;
	
	/* support for feed- functions
	 * set to null if no feed functions are avail.
	 * [note] this might be more handy as a per/frame thing */
	struct {
		arcan_vfunc_cb ffunc;
		vfunc_state state;
		
		unsigned* rrobin;
		unsigned rrobin_cur;
		unsigned rrobin_lim;
	} feed;
	
	uint8_t ffunc_mask;
	
	/* visual- params */
	struct {
		char* vertex;
		char* fragment;
	} gpu_program;
	

	float txcos[8];
	enum arcan_blendfunc blendmode;
	/* flags */
	struct {
		bool in_use;
		bool clone;
		bool cliptoparent;
		bool asynchdisable;
	} flags;
	
/* position */
	signed short order;
	surface_properties current;
	
	surface_transform* transform;
	enum arcan_transform_mask mask;
	
/* life-cycle tracking */
	unsigned long last_updated;
	unsigned long lifetime;
	
/* management mappings */
	struct arcan_vobject* parent;
	struct arcan_vobject_litem* owner;
	arcan_vobj_id cellid;
} arcan_vobject;

/* regular old- linked list, but also mapped to an array */
struct arcan_vobject_litem {
	arcan_vobject* elem;
	struct arcan_vobject_litem* next;
	struct arcan_vobject_litem* previous;
};
typedef struct arcan_vobject_litem arcan_vobject_litem;

struct arcan_video_display {
	bool suspended, text_support, fullscreen, conservative, late3d;
	float projmatr[16];

	unsigned default_vitemlim;
	arcan_shader_id defaultshdr;
	
	/* default image loading options */
	enum arcan_vimage_mode scalemode;
	enum arcan_imageproc_mode imageproc;
	unsigned deftxs, deftxt;
    	bool mipmap;
	
	SDL_Surface* screen;
	uint32_t sdlarg;
	
	unsigned char bpp;
	unsigned short width, height;
	uint32_t c_ticks;
	
	unsigned char msasamples;
};

extern struct arcan_video_display arcan_video_display;
int arcan_debug_pumpglwarnings(const char* src);
void arcan_resolve_vidprop(arcan_vobject* vobj, float lerp, surface_properties* props);
arcan_vobject* arcan_video_getobject(arcan_vobj_id id);
arcan_vobject* arcan_video_newvobject(arcan_vobj_id* id);
void arcan_3d_setdefaults();

/* sweep the glstor and bind the corresponding texture units (unless we hit the imit that is) */
unsigned int arcan_video_pushglids(struct storage_info_t* glstor, unsigned ofs);

arcan_vobject_litem* arcan_refresh_3d(unsigned camtag, arcan_vobject_litem* cell, float frag, unsigned int destination);

#endif
