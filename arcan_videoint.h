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

/* this one needs a bit explaining:
 * each vobj- can have a series of transformations,
 * each transformation describes the number of ticks
 * left for each attribute, and the associated values
 * are deltas in respect to the current state of the object.
 * These are also used to interpolate between game-time clocks */
typedef struct surface_transform {
	/* g1 */
	unsigned int time_move;
	float move[4];
	
	/* g2 */
	unsigned int time_scale;
	float scale[4];
	
	/* g3 */
	unsigned int time_opacity;
	float opa[2];
	
	/* g4 */
	unsigned int time_rotate;
	float rotate[2];
	
	struct surface_transform* next;
} surface_transform;

typedef struct arcan_vstorage {
	uint32_t s_raw;
	uint8_t* raw;
	char* source;
	char tag;
} arcan_vstorage;

typedef struct arcan_vobject {
	/* image-storage / reference,
	 * current_frame is set to default_frame */
	arcan_vstorage default_frame;
	struct arcan_vobject* current_frame;
	uint16_t origw, origh;
	
	/* animation / states,
	 * (could also be used for multitexturing
	 * but would require some more "thought" first) */
	struct arcan_vobject** frameset;
	unsigned frameset_capacity;
	
	/* support for feed- functions
	 * set to null if no feed functions are avail.
	 * [note] this might be more handy as a per/frame thing */
	arcan_vfunc_cb ffunc;
	vfunc_state state;
	uint8_t ffunc_mask;
	
	/* visual- params */
	struct {
		char* vertex;
		char* fragment;
	} gpu_program;
	
	struct {
		GLuint glid;
		GLuint program, vertex, fragment;
		uint8_t c_glid;
		uint16_t w, h;
		GLuint txu, txv;
		bool scale;
		uint8_t ncpt;
	} gl_storage;
	
	float txcos[8];
	
	/* flags */
	struct {
		bool in_use;
		bool twofaced;
		bool clone;
		bool cliptoparent;
	} flags;
	
	/* position */
	uint8_t zval;
	surface_properties current;
	
	surface_transform transform;
	struct arcan_vobject* parent;
	enum arcan_transform_mask mask;
	
	/* life-cycle tracking */
	unsigned long last_updated;
	unsigned long lifetime;
	
	/* management mappings */
	struct arcan_vobject_litem* owner;
} arcan_vobject;

/* regular old- linked list, but also mapped to an array */
struct arcan_vobject_litem {
	arcan_vobject* elem;
	struct arcan_vobject_litem* next;
	struct arcan_vobject_litem* previous;
	arcan_vobj_id cellid;
};
typedef struct arcan_vobject_litem arcan_vobject_litem;

arcan_vobject* arcan_video_getobject(arcan_vobj_id id);
arcan_vobject* arcan_video_newvobject(arcan_vobj_id* id);

#endif
