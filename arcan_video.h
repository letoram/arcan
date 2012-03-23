/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#ifndef _HAVE_ARCAN_VIDEO
#define _HAVE_ARCAN_VIDEO

#define RGBPACK(r, g, b, d)\
{\
	((uint32_t *)(d))[0] = (0xff << 24) | (r << 16) | (g << 8) | b;\
}

#ifndef CONTEXT_STACK_LIMIT
#define CONTEXT_STACK_LIMIT 8
#endif

/* supposedly, GL_BGRA is more efficient and can be directly transferred without 'swizzling',
 * but it's not implemented in all supported GL environments */
#define GL_PIXEL_FORMAT GL_RGBA

/* video-style enum of potential arcan_video_* outcomes */

enum arcan_vrtypes {
	ARCAN_VRTYPE_IMAGE,
	ARCAN_VRTYPE_VIDEO,
	ARCAN_VRTYPE_CFUNC,
	ARCAN_VRTYPE_RENDERSOURCE
};

enum arcan_vtex_mode {
	ARCAN_VTEX_REPEAT = 0,
	ARCAN_VTEX_CLAMP = 1
};

enum arcan_vimage_mode {
	ARCAN_VIMAGE_NOPOW2 = 0, 
	ARCAN_VIMAGE_TXCOORD = 1,
	ARCAN_VIMAGE_SCALEPOW2 = 2
};

enum arcan_transform_mask {
	MASK_NONE = 0,
	MASK_POSITION = 1,
	MASK_SCALE = 2,
	MASK_OPACITY = 4,
	MASK_LIVING = 8,
	MASK_ORIENTATION = 16,
	MASK_UNPICKABLE = 32,
	MASK_ALL = 63
};

enum arcan_ffunc_cmd {
	ffunc_poll = 0,
	ffunc_render = 1,
	ffunc_tick = 2,
	ffunc_destroy = 3
};

enum arcan_ffunc_rv {
	FFUNC_RV_FAILURE = -1,
	FFUNC_RV_NOFRAME = 0,
	FFUNC_RV_GOTFRAME = 1,
	FFUNC_RV_COPIED = 2,
	FFUNC_RV_NOUPLOAD = 64
};

enum arcan_blendfunc {
	blend_disable,
	blend_force
};

enum arcan_interp_function {
	interpolate_linear,
	interpolate_spherical,
	interpolate_normalized_linear
};

enum arcan_imageproc_mode {
	imageproc_normal,
	imageproc_fliph
};

/* callback format for a feed- function to a video object.
 * buf can be 0 (peek to know if data is available) OR pointer to data storage * with storage format (buf_s = width * height * bpp)
 * src indicates if the tick is from video refresh (0) or how many logic ticks it represents */

typedef struct {
	volatile int tag;
	void* ptr;
} vfunc_state;
const

typedef int8_t(*arcan_vfunc_cb)(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned int mode, vfunc_state state);

arcan_errc arcan_video_init(uint16_t width, uint16_t height, uint8_t bpp, bool fullscreen, bool frames, bool conservative);

/* will apply to all new vobjects, it is, however, tracked on a per-object basis so can be changed during runtime */
void arcan_video_default_scalemode(enum arcan_vimage_mode);
void arcan_video_default_texmode(enum arcan_vtex_mode s, enum arcan_vtex_mode t);
void arcan_video_default_imageprocmode(enum arcan_imageproc_mode);

void arcan_video_fullscreen();
uint16_t arcan_video_screenw();
uint16_t arcan_video_screenh();

/* basic context management functions */
unsigned arcan_video_popcontext();
unsigned arcan_video_nfreecontexts();
unsigned arcan_video_contextusage(unsigned* free);

/* returns # of free context slots left, -1 if context could not be pushed */
signed arcan_video_pushcontext();

/* create a video object with a desired end-position and measurements
 * rloc = resource location, most commonly just a file. loading might be asynchronous. can be null.
 * zval = 0 (order added) otherwise 1 (draw first) up to 255 (draw last)
 * vis  = 0 (hidden) or 1 (visible)
 * opa  = 0.001 .. 1.000 (render opacity)
 * returns 0 if id couldn't be created
 * errc = if !null, will be set to potential errorcode
 */

/* use a prepared buffer to generate the video object.
 * buf* will be managed internally.
 * assumes constraints are a valid texture size (power of two),
 * and that the data is in RGBA format*/
arcan_vobj_id arcan_video_rawobject(uint8_t* buf, size_t bufs, img_cons constraints, float origw, float origh, unsigned short zv);

/* if tag is set,
 * the image will be loaded asynch and in the event that will get pushed, the tag will come along */
arcan_vobj_id arcan_video_loadimage(const char* fname, img_cons constraints, unsigned short zv, void* tag);
arcan_errc arcan_video_pushasynch(arcan_vobj_id id);
arcan_vobj_id arcan_video_addfobject(arcan_vfunc_cb feed, vfunc_state state, img_cons constraints, unsigned short zv);
arcan_errc arcan_video_scaletxcos(arcan_vobj_id id, float sfs, float sft);
arcan_errc arcan_video_alterfeed(arcan_vobj_id id, arcan_vfunc_cb feed, vfunc_state state);
vfunc_state* arcan_video_feedstate(arcan_vobj_id);
arcan_errc arcan_video_resizefeed(arcan_vobj_id id, img_cons constraints, bool mirror);
arcan_vfunc_cb arcan_video_emptyffunc();

/* spawn an instance of the particular vobj,
 * which will use the storage properties of its parent (shaders, image objects, ...),
 * have its coordinates relative to the parent.
 * Typical use-case is for particle systems and transition effects. */
arcan_vobj_id arcan_video_cloneobject(arcan_vobj_id id);

/* link the transformation system for
 * src to be realtive to the coordinate system of parent
 * life if "immortal" properties should be ignored and the object
 * dies if its parent does.
 * returns OK,
 * fails if any object doesn't exist.
 * This will reset any transformations on the src object, as will the death of a parent object. */
arcan_errc arcan_video_linkobjs(arcan_vobj_id src, arcan_vobj_id parent, enum arcan_transform_mask mask);
enum arcan_transform_mask arcan_video_getmask(arcan_vobj_id src);
arcan_errc arcan_video_transformmask(arcan_vobj_id src, enum arcan_transform_mask mask);
arcan_errc arcan_video_setclip(arcan_vobj_id id, bool toggleon);

img_cons arcan_video_storage_properties(arcan_vobj_id id);
surface_properties arcan_video_resolve_properties(arcan_vobj_id id);
surface_properties arcan_video_initial_properties(arcan_vobj_id id);
surface_properties arcan_video_current_properties(arcan_vobj_id id);
surface_properties arcan_video_properties_at(arcan_vobj_id id, uint32_t ticks);
arcan_errc arcan_video_forceblend(arcan_vobj_id id, bool on);
arcan_vobj_id arcan_video_findparent(arcan_vobj_id id);
arcan_vobj_id arcan_video_findchild(arcan_vobj_id parentid, unsigned ofs);

img_cons arcan_video_dimensions(uint16_t w, uint16_t h);

/* -- multiple- frame management --
 * this is done by associating a working video-object (src) with another (dst),
 * so that (src) becomes part of (dst)s rendering. */
/* specify the number of frames associated with vobj, default is 0 */
arcan_errc arcan_video_allocframes(arcan_vobj_id id, uint8_t capacity);
/* note that the frame_id (fid) have to be available through allocframes first */
arcan_vobj_id arcan_video_setasframe(arcan_vobj_id dst, arcan_vobj_id src, unsigned fid, bool detatch, arcan_errc* errc);
arcan_errc arcan_video_setactiveframe(arcan_vobj_id dst, unsigned fid);
void arcan_video_imgmanmode(enum arcan_vimage_mode mode, bool repeat);
void arcan_video_contextsize(unsigned newlim);

/* change zval (see arcan_video_addobject) for a particular object.
 * return value is an error code */
arcan_errc arcan_video_setzv(arcan_vobj_id id,unsigned short newzv);
unsigned short arcan_video_getzv(arcan_vobj_id id);

/* forcibly kill videoobject after n cycles,
 * which will reset a counter that upon expiration invocates
 * arcan_video_deleteobject(arcan_vobj_id id)
 * and fires a corresponding event */
arcan_errc arcan_video_setlife(arcan_vobj_id id, unsigned nCycles);

/* removes an object immediately, regardless of masks, life-cycles left etc. */
arcan_errc arcan_video_deleteobject(arcan_vobj_id id);

/* move, scale and so on all works in a similar fashion,
 * you enter the desired values whatever attribute you wish to be changed, then
 * how many logical time-steps you wish for them to take. These can be linked together (will occur
 * at the same time, though seperate events will be fired upon completion for each and every one)
 * but also chained by repeatedly setting new values before the previous one expires.
 * If the change is to be instantaneous, set 0 as time (this will dequeue all chained- changes for
 * that particular attribute */
arcan_errc arcan_video_objectmove(arcan_vobj_id id, float newx, float newy, float newz, unsigned int time);
arcan_errc arcan_video_objectscale(arcan_vobj_id id, float wf, float hf, float df, unsigned int time);
arcan_errc arcan_video_objectrotate(arcan_vobj_id id, float roll, float pitch, float yaw, unsigned int time);
arcan_errc arcan_video_objectopacity(arcan_vobj_id id, float opa, unsigned int time);
arcan_errc arcan_video_override_mapping(arcan_vobj_id id, float* dst);
arcan_errc arcan_video_retrieve_mapping(arcan_vobj_id id, float* dst); 
arcan_errc arcan_video_setprogram(arcan_vobj_id id, arcan_shader_id shid);
arcan_errc arcan_video_instanttransform(arcan_vobj_id id);
arcan_errc arcan_video_zaptransform(arcan_vobj_id id);
unsigned arcan_video_maxorder();
arcan_vobj_id arcan_video_cloneobject(arcan_vobj_id parent);

/* process a logical time-frame (which more or less means, update / rescale / redraw / flip)
 * returns msecs elapsed */
uint32_t arcan_video_tick(uint8_t steps);

bool arcan_video_hittest(arcan_vobj_id id, unsigned int x, unsigned int y);

/* perform a simple 'pick' query,
 * gathering up to 'count' items ordered by Z and storing in 'dst' if they match the specified coordinates
 * returns number picked. O(n) */
unsigned int arcan_video_pick(arcan_vobj_id* dst, unsigned int count, int x, int y);

/* a more precise pick-query (the first is implemented as a detailed pick with some fixed parameters.
 * zval_low and zval_high sets a threshold interval for items to be considered,
 * ignore_alpha skips the alpha (pixel-pixel tests for sources with transparent values etc.) test
 * which is a quite expensive one (as rotation and scaling need to be considered, it turns into a
 * 2D(AABB - OBB) test) */
uint32_t arcan_video_pick_detailed(uint32_t* dst, uint32_t count, uint16_t x, uint16_t y, int zval_low, int zval_high, bool ignore_alpha);

void arcan_video_stringdimensions(const char* message, int8_t line_spacing, int8_t tab_spacing, unsigned int* tabs, unsigned int* maxw, unsigned int* maxh);
arcan_vobj_id arcan_video_renderstring(const char* message, /* string to render */
                                       int8_t line_spacing, /* default spacing between lines */
                                       int8_t tab_spacing,  /* default spacing between tabs */
                                       unsigned int* tabs,  /* specific tab widths (null-terminated) */
                                       unsigned int* lines, /* [out]-> number of lines processed */
                                       unsigned int** lineheights); /* [out]-> height of each line, needs to be freed */

void arcan_video_dumppipe();

/* determine if 3D is going to be processed first (2D mode used as 'HUD' and supplementary imagery') or
 * 'last' (adding partial 3D models to an otherwise 2D scene */
void arcan_video_3dorder(bool first);

/* somewhat ugly hack to try and pause the objects that rely on timing etc. that might be
 * disturbed by an external launch */
bool arcan_video_prepare_external();
void arcan_video_restore_external();

/* fragment represents how much time left until the next timestep,
 * used to interpolate movements / fades */
void arcan_video_refresh(float fragment);
void arcan_video_pollfeed();

void arcan_video_shutdown();

#endif

