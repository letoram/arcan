/*
 * Copyright 2003-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef _HAVE_ARCAN_VIDEO
#define _HAVE_ARCAN_VIDEO

/*
 * All calls that allocate a video object may
 * return a valid object id OR ARCAN_EID.
 *
 * All calls that requires one or more video object ids
 * can return ARCAN_ERRC_NO_SUCH_OBJECT.
 *
 * All calls that depends on a changeable internal state,
 * masks, asynchronous loading, heritage, ...
 * can return ARCAN_ERRC_UNACCEPTED_STATE.
 */

#ifndef CONTEXT_STACK_LIMIT
#define CONTEXT_STACK_LIMIT 8
#endif

#ifndef VITEM_CONTEXT_LIMIT
#define VITEM_CONTEXT_LIMIT 65536
#endif

/*
 * These define how members of a frameset are supposed to be managed
 * when rendering the parent object. For SPLIT, only the currently
 * active frame will actually be drawn. For MULTITEXTURE, as many
 * as supported natively (minimum, 8) will be mapped to different
 * texture units as map_tu0 (primary), (1+ first member of frameset)
 */
enum arcan_framemode {
	ARCAN_FRAMESET_SPLIT,
	ARCAN_FRAMESET_MULTITEXTURE
};

/*
 * How to deal with texture coordinates outside the 0..1 range,
 * due to the GLES2/GL2.1 limitation, we don't support CLAMP_TO_EDGE
 * or CLAMP_TO_BORDER
 */
enum arcan_vtex_mode {
	ARCAN_VTEX_REPEAT = 0,
	ARCAN_VTEX_CLAMP  = 1
};

/*
 * How to render an object that is linked to another (not WORLDID).
 * CLIP_OFF : render fully,
 * CLIP_ON  : use stencil buffer to draw the entire hierarchy of
 *            clipping enabled objects.
 * CLIP_SHALLOW : only clip to parent. Will use stencil buffer if
 *                parent or child is rotated, otherwise texture
 *                coordinates will be used to perform the clipping.
 */
enum arcan_clipmode {
	ARCAN_CLIP_OFF = 0,
	ARCAN_CLIP_ON  = 1,
	ARCAN_CLIP_SHALLOW = 2
};

/*
 * Default sampling options for when drawing dimensions differ from
 * source dimensions. Default is set to BILINEAR, but can be overridden
 * globally or on a per object basis. Custom filtering can be implemented
 * by creative use of sharestorage and rendertargets with force update.
 */
enum arcan_vfilter_mode {
	ARCAN_VFILTER_NONE = 0,
	ARCAN_VFILTER_LINEAR,
	ARCAN_VFILTER_BILINEAR,
	ARCAN_VFILTER_TRILINEAR,
	ARCAN_VFILTER_MIPMAP = 128
};

/*
 * Interpolation methods for drawing animation frames (ongoing transformations)
 * but also effects other calls (picking in particular). LINEAR is the default.
 */
enum arcan_vinterp {
	ARCAN_VINTER_LINEAR = 0,
	ARCAN_VINTER_SINE,
	ARCAN_VINTER_EXPIN,
	ARCAN_VINTER_EXPOUT,
	ARCAN_VINTER_EXPINOUT,
	ARCAN_VINTER_ENDMARKER
};

/*
 * Legacy option, when loading images where dimensions are not power of 2s
 * (which effects GPU storage and MIPMAPPING). Default is NOPOW2 and for
 * some corner cases (streaming frameservers) SCALEPOW2 have no effect.
 */
enum arcan_vimage_mode {
	ARCAN_VIMAGE_NOPOW2    = 0,
	ARCAN_VIMAGE_SCALEPOW2 = 1
};

/*
 * When linking coordinate systems with a parent, we can specify
 * anchor point here which cuts down on the amount of dynamic
 * recalculations needed for common UI operations.
 */
enum parent_anchor {
	ANCHORP_UL = 0,
	ANCHORP_UR,
	ANCHORP_LL,
	ANCHORP_LR,
	ANCHORP_C,
	ANCHORP_ENDM
};

/*
 * Each VOBJect can have additional data associated with it.
 */
enum arcan_vobj_tags {
ARCAN_TAG_NONE      = 0,/* "don't touch" -- rawobjects, uninitialized etc.    */
ARCAN_TAG_IMAGE     = 1,/* images from an external source, need to be able
													 to grab by internal video_getimage function        */
ARCAN_TAG_TEXT      = 2,/* specialized form of RAWOBJECT                      */
ARCAN_TAG_FRAMESERV = 3,/* got a connection to an external
													 resource (frameserver)                             */
ARCAN_TAG_ASYNCIMGLD= 4,/* intermediate state, means that getimage is still
													 loading, don't touch objects in this state         */
ARCAN_TAG_ASYNCIMGRD= 5,/* when asynch loader is finished, ready to collect   */

/* Only 3D - related tags after this, order dependent! */
ARCAN_TAG_3DOBJ     = 6,/* got a corresponding entry in arcan_3dbase, ffunc is
													 used to control the behavior of the 3d part        */
ARCAN_TAG_3DCAMERA  = 7,/* set after using camtag,
													 only usable on NONE/IMAGE                          */
ARCAN_TAG_CUSTOMPROC= 8, /* used in Lua specific contexts, calctarget etc.    */
ARCAN_TAG_LWA       = 9  /* used for LWA- to arcan subsegments                */
};

/*
 * Since some properties are hierarchically managed, they can be
 * masked and managed on a per object basis. Note that MASK_SCALE
 * is currently not in use
 */
enum arcan_transform_mask {
	MASK_NONE        = 0,
	MASK_POSITION    = 1,   /* DEFAULT ON */
	MASK_SCALE       = 2,   /* RESERVED, DEFAULT OFF */
	MASK_OPACITY     = 4,   /* DEFAULT ON, object is only visible if parent is */
	MASK_LIVING      = 8,   /* DEFAULT ON, object dies when parent dies        */
	MASK_ORIENTATION = 16,  /* DEFAULT ON, can be combined with origoofs       */
	MASK_UNPICKABLE  = 32,  /* DEFAULT OFF, setting to ON disable picking      */
	MASK_FRAMESET    = 64,  /* DEFAULT ON, use parent frameset or own          */
	MASK_MAPPING     = 128, /* Overriden texture coordinates, DEFAULT OFF      */
	MASK_ALL         = 255
};

#ifndef MASK_MOTION
#define MASK_TRANSFORMS (MASK_POSITION | MASK_SCALE\
 | MASK_OPACITY | MASK_ORIENTATION)
#endif

typedef float (*arcan_interp_1d_function)(
	float startv, float stopv, float fract);

typedef vector (*arcan_interp_3d_function)(
	vector begin, vector end, float fract);

typedef quat (*arcan_interp_4d_function)(
	quat begin, quat end, float fract);

/*
 * When loading an image, a transformation can be applied
 * before the image is added to
 */
enum arcan_imageproc_mode {
	IMAGEPROC_NORMAL,
	IMAGEPROC_FLIPH
};

/*
 * State flag, determine when the 3D pipeline should
 * be processed in relation to the 2D one.
 */
enum arcan_order3d {
	ORDER3D_NONE,
	ORDER3D_FIRST,
	ORDER3D_LAST
};

/*
 * All pseudo- dynamic code paths (callback driven) go through
 * an indirection layer specified here
 */
#include "arcan_ffunc_lut.h"

/*
 * Reversed VOBJ values, everything is forcibly linked to WORLDID
 * (which can be manipulated)
 */
extern arcan_vobj_id ARCAN_VIDEO_WORLDID;
extern arcan_vobj_id ARCAN_VIDEO_BADID;

#include "arcan_ffunc_lut.h"

/*
 * Perform basic rendering library setup and forward
 * requests to platform layer. Note that width/height are hints
 * and something of a legacy. Some platform implementations use
 * environment variables or build time flags for additional setup.
 *
 * width/height can be 0 and will then be set to a probed default.
 * fullscreen / frames are hints to any window manager / compositor
 *
 * conservative hints that memory is a scarce resource and that we
 * should try and avoid online local stores if possible (and rather
 * reload/recreate video objects as needed).
 */
arcan_errc arcan_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fullscreen, bool frames, bool conservative, const char* caption);

/*
 * Clear the display, deallocate all resources (fonts, shaders,
 * video objects), chain to platform_video_shutdown etc.
 * Note that this do not reset any attributes modified by the
 * the _default_ class functions.
 */
void arcan_video_shutdown();

/*
 * Push the current context, shut down the video display but in a way
 * that all state can be restored at a later time. This is intended
 * for launching resource- hungry 3rd party software that can work
 * standalone, and for hibernation/suspend style power management.
 */
bool arcan_video_prepare_external();

/*
 * Re-initialize the event layer, shaders, video objects etc. and
 * pop the last context saved. This ASSUMES that we are in a state
 * defined by arcan_video_prepare_external.
 */
void arcan_video_restore_external();

/*
 * Specify if the 3D pipeline should be processed and if so,
 * if it should happen before or after the 2D pipeline has been processed.
 * This attribute is copied to new rendertargets.
 *
 * [rt] is optional and should be set to ARCAN_EID or a VID referencing
 *      a valid rendertarget.
 */
arcan_errc arcan_video_3dorder(enum arcan_order3d, arcan_vobj_id rt);

/*
 * Forcibly empty the font cache, this can free up some memory resources.
 */
void arcan_video_reset_fontcache();

/*
 * the arcan_video_default_ class of functions all change the current
* default values for newly created objects. They do not update already
 * existing ones.
 */
void arcan_video_default_scalemode(enum arcan_vimage_mode);
void arcan_video_default_texmode(enum arcan_vtex_mode s,
	enum arcan_vtex_mode t);
void arcan_video_default_texfilter(enum arcan_vfilter_mode);
void arcan_video_default_imageprocmode(enum arcan_imageproc_mode);
arcan_errc arcan_video_screenshot(av_pixel** dptr, size_t* dsize);

/*
 * Request a fullscreen/window toggle if working / implemented,
 * not guranteed to perform any meaningful change.
 */
void arcan_video_fullscreen();

/*
 * Store the currently highest Z value for a specific rendertarget (or WORLDID)
 * in the currently active context. This imposes a linear search through the
 * active context. Note that the last 5 values are (65531-65535) reserved and
 * won't be returned. This is to allow a maxorder()+n idiom while still having
 * objects with an 'overlay' or cursor role.
 *
 */
arcan_errc arcan_video_maxorder(arcan_vobj_id rt, uint16_t* ov);

/*
 * Set a new object limit for new contexts. This will not effect
 * the current context. A special case is that the outmost context
 * can be poped and will then have the new object limit.
 *
 * 0 > newlim < VITEM_CONTEXT_LIMIT
 *
 * will fail if shrinking a context would undershoot the number
 * of persistent- flagged items.
 */
bool arcan_video_contextsize(unsigned newlim);

/*
 * Returns the number or free contexts on the context stack.
 * 0 >= retval <= CONTEXT_STACK_LIMIT
 */
unsigned arcan_video_nfreecontexts();

/*
 * Mass-deallocate objects in the currently active context and
 * load the previously active one on the stack (if available).
 * Returns the current context index (0 is top level / empty stack).
 */
unsigned arcan_video_popcontext();

/*
 * Non-destructively deallocate as much as possible from the current context
 * and move to a backing store. Objects flagged as persistant will migrate
 * into the new context.
 *
 * Return -1 if there's no free context slots or the number of context
 * slots left. The number of contexts are compile-time limited with
 * the CONTEXT_STACK_LIMIT define.
 *
 */
signed arcan_video_pushcontext();

/*
 * extpopcontext works similar to popcontext,
 * but the currently active context will be rendered into a temporary buffer
 * (internally using the arcan_video_screenshot function) that will be used
 * to create a new object which will be inserted into the previous context.
 *
 * [dst] must point to a arcan_vobj_id, otherwise undefined behavior.
 * [dst] will be set to ARCAN_EID if there was insufficient room in the
 *       old context to fit a new object.
 */
unsigned arcan_video_extpopcontext(arcan_vobj_id* dst);

/*
 * extpushcontext is similar to extpopcontext,
 * it can fail if the number of objects with the persist flag >= vobj slots
 * in the new context.
 *
 */
signed arcan_video_extpushcontext(arcan_vobj_id* dst);

/*
 * Returns the number of total video object slots in the current context,
 * if [free] is set, it will be used to store the number of slots in use
 */
unsigned arcan_video_contextusage(unsigned* used);

/*
 * Create a "visible" but initially non-drawable object with its initial
 * dimensions set to [origw] and [origh] ordered by [zv]. This should be
 * used in conjunction with linkobject (to act as a clipping/transformation
 * anchor) or with sharestorage to act as an expensive clone.
 */
arcan_vobj_id arcan_video_nullobject(float origw, float origh,
	unsigned short zv);

/*
 * Create an object without a buffer based object store with its initial
 * dimensions set to [origw] and [origh] ordered by [zv].
 * A default color shader will be used to, with the solid color
 * set as a uniform.
 */
arcan_vobj_id arcan_video_solidcolor(float origw, float origh,
	uint8_t r, uint8_t g, uint8_t b, unsigned short zv);

/*
 * Create an object using a raw buffer as input. Note that
 * no color space conversion is currently performed and the use
 * of this function should be avoided, if possible.
 */
arcan_vobj_id arcan_video_rawobject(av_pixel* buf,
	img_cons constraints, float origw, float origh, unsigned short zv);

/*
 * Create an object with a dynamic (callback- driven) input source.
 * This is also used for managing 3D objects.
 */
arcan_vobj_id arcan_video_addfobject(ffunc_ind feed,
	vfunc_state state, img_cons constraints, unsigned short zv);

/*
 * Create a new video object based on a format string (multiple = false,
 * message = formatstr) or array of strings (where %2 == 0 is treated as
 * format string and %2==1 is treated as plain string.
 *
 * If ID is set to a valid object (not BADID or WORLDID) with a textured
 * backing store, that backing store will be rendered to and resized --
 * breaking and resetting ongoing resize chain. The targetted vobject must be
 * the result of a previous call to arcan_video_renderstring.
 *
 * Message is a UTF-8 encoded string with backslash triggered format
 * strings. Accepted formatting commands:
 * \ffontres,fontdim : set the currently active font to the resource specified
 *                     by fontres, with the hinted size of fontdim
 *
 * \t : insert tab, they are by default spaced with [tab_spacing] in pixels
 *      unless there's a specified tab size in the 0 terminated array [tabs].
 * \n : begin a new line, this does not impose a carriage return
 * \r : return carriage to beginning of line, should be used with \n
 * \u : switch font style to underlined
 * \b : switch font style to bold
 * \i : switch font style to italic
 * \presname : load image specified by resname
 * \Pw,h,resname : load image and scale to specific dimensions
 * \#rrggbb : switch font color
 *
 * The contents pointed to by message and array is assumed to be dynamically
 * allocated (array and fields separately for array member) and the associated
 * vobject will claim ownership. This is needed in order to be able to recrate
 * the video object in the event of a lost context.
 *
 * Error code will be provided if errc pointer is set and returned id is
 * ARCAN_EID.
 *
 * stringdimensions is a reduced version of this function that only generates
 * the data without creating a video object, setting up a backing store or
 * claiming ownership over message.
 */
struct arcan_rstrarg {
	bool multiple;
	union {
		char* message;
		char** array;
	};
};

#ifndef HAVE_RLINE_META
#define HAVE_RLINE_META
struct renderline_meta {
	int height;
	int ystart;
	int ascent;
};
#endif

arcan_vobj_id arcan_video_renderstring(arcan_vobj_id id,
	struct arcan_rstrarg arg, int8_t line_spacing,
	int8_t tab_spacing, unsigned int* tabs, unsigned int* lines,
	struct renderline_meta** lineheights, arcan_errc* errc
);

void arcan_video_stringdimensions(const char* message, int8_t line_spacing,
	int8_t tab_spacing, unsigned int* tabs, unsigned int* maxw,
	unsigned int* maxh);

/*
 * Immediately erase the object and all its related resources.
 * Depending on the internal structure of the object in question,
 * this can be an expensive operation as deletions will cascade to
 * linked objects, framesets, rendertarget attachments and so on.
 */
arcan_errc arcan_video_deleteobject(arcan_vobj_id id);

/*
 * Set a lifetime counter for the specified object. When reached,
 * an event will be scheduled that will request the main eventloop
 * to invoke deleteobject.
 *
 * A [ticks] value of 0 will disable any existing lifetime timer.
 * This will also force-enable the MASK_LIVING.
 */
arcan_errc arcan_video_setlife(arcan_vobj_id id, unsigned ticks);

/*
 * Change the feed function currently associated with a fobject.
 * This should only be used to switch callback function or state
 * container in a setting that knows more about the internal state
 * already, e.g. the frameserver feed-functions, otherwise
 * it is likely that resources will leak.
 */
arcan_errc arcan_video_alterfeed(arcan_vobj_id, ffunc_ind, vfunc_state);

/*
 * Get a reference to the current feedstate in use by a specific object.
 */
vfunc_state* arcan_video_feedstate(arcan_vobj_id);

/*
 * Run through all registered dynamic feed objects and request that they
 * notify if their internal state has changed or not. If it has, backing
 * stores will update.
 */
void arcan_video_pollfeed();

/*
 * Forcibly alter the feed state for the specified object,
 * this is typically used by a dynamically resizing source e.g. a frameserver.
 *
 * Note that the operation is rather expensive as it involves
 * deallocating current backing stores and replacing them with new ones.
 */
arcan_errc arcan_video_resizefeed(arcan_vobj_id id, size_t w, size_t h);

/*
 * arcan_video_loadimageasynch and arcan_video_loadimage
 *
 * Load an image from the resource description in [resource]
 *(all [resource] marked functions will be resolved through arcan_map_resource)
 *
 * if [constraints] are empty (w == 0 && h == 0) then the dimensions
 * defined in the resource will be retained, otherwise the image will be
 * rescaled upon loading (unfiltered and rather slow).
 *
 * The asynchronous version will spawn a worker thread (up to a certain
 * number, compile-time limited with ASYNCH_CONCURRENT_THREADS).
 * Context operations will force a join on any outstanding asynchronous
 * loading jobs.
 *
 * Loadimage returns ARCAN_EID on failure, asynch will always succeed but
 * may later enqueue EVENT_ASYNCHIMAGE_FAILED or EVENT_VIDEO_ASYNCHIMAGE_LOADED
 */
arcan_vobj_id arcan_video_loadimageasynch(const char* resource,
	img_cons constraints, intptr_t tag);
arcan_vobj_id arcan_video_loadimage(const char* fname,
	img_cons constraints, unsigned short zv);

/*
 * Force-join on an outstanding asynchronous (loadimageasynch) object.
 * Return codes other than ARCAN_OK is not necessarily bad, just that
 * the effect of the operation was a no-op.
 */
arcan_errc arcan_video_pushasynch(arcan_vobj_id id);

/*
 * By default, all objects share a set of texture coordinates in the form
 * [ul(s,t), ur(s,t), lr(s,t), ll(st)]. When any texture coordinate related
 * operation is called, a local set is generated and used for the particular
 * video object. This function generates a local set and then scales the
 * s and t values with the supplied factors.
 */
arcan_errc arcan_video_scaletxcos(arcan_vobj_id id, float sfs, float sft);

/*
 * resize the virtual canvas (on initialization, it is set to
 * the same dimensions as the display.
 */
arcan_errc arcan_video_resize_canvas(size_t neww, size_t newh);

/*
 * Create a new storage based on the one in used by [id] and resampled
 * using the shader specified with [prg]. Associate this new storage with
 * the [id] container.
 */
arcan_errc arcan_video_resampleobject(arcan_vobj_id id,
	int neww, int newh, agp_shader_id prg);

/* Object hierarchy related functions */
arcan_errc arcan_video_linkobjs(arcan_vobj_id src, arcan_vobj_id parent,
	enum arcan_transform_mask mask, enum parent_anchor);
arcan_vobj_id arcan_video_findparent(arcan_vobj_id id);
arcan_vobj_id arcan_video_findchild(arcan_vobj_id parentid, unsigned ofs);

/*
 * Recursively resolves if [vid] is linked to any of parents near
 * or distant children. Set [limit] to -1 to search the entire tree,
 * otherwise a [limit] of >0 will limit the search depth.
 */
bool arcan_video_isdescendant(arcan_vobj_id vid,
	arcan_vobj_id parent, int limit);

arcan_errc arcan_video_changefilter(arcan_vobj_id id,
	enum arcan_vfilter_mode);
arcan_errc arcan_video_persistobject(arcan_vobj_id id);

/*
 * Framesets are special storage containers inside an object that can
 * have references to other vstores (textured). They are primarily used
 * for four purposes:
 * 1. multitexturing,
 * 2. container for individual textures 3d objects with multiple meshes
 * 3. animation (framestepping)
 * 4. round-robin store for streaming data sources
 *
 * Use allocframes to associate a frameset with a vobject (which will
 * remain until the object dies, the size of the store can only ever grow).
 *
 * mode can be one of FRAMESET_MULTITEXTURE or FRAMESET_SPLIT.
 */
arcan_errc arcan_video_allocframes(arcan_vobj_id id,
	uint8_t capacity, enum arcan_framemode mode);

/* setasframe shares the textured backing store associated with [src] with
 * the specified frameset slot [fid] in the object pointed to by [dst].
 * This operation will fail if [src] backing store is not textured,
 * if there's no frameset specified in [dst] or if [fid] exceeds the number
 * of slots in the frameset.
 */
arcan_errc arcan_video_setasframe(arcan_vobj_id dst,
	arcan_vobj_id src, size_t fid);

/*
 * Manually switch the active frame used when rendering [dst] to a specific
 * slot.
 */
arcan_errc arcan_video_setactiveframe(arcan_vobj_id dst, unsigned fid);

/*
 * Specify automatic management of active frameset frame. If [mode] is
 * 0, automatic management is disabled. If [mode] is set to a number,
 * the frame will be cycled every abs(num) LOGICAL frames (tick).
 * If an object with a feed-function (e.g. a frameserver) is cycled, the
 * mode is associated with every DELIVERED frame.
 */
arcan_errc arcan_video_framecyclemode(arcan_vobj_id id, signed mode);

/* Rendertarget- operations */
arcan_errc arcan_video_setuprendertarget(arcan_vobj_id did, int readback,
	int refresh, bool scale, enum rendertarget_mode format);
arcan_errc arcan_video_forceupdate(arcan_vobj_id vid);
arcan_errc arcan_video_attachtorendertarget(arcan_vobj_id did,
	arcan_vobj_id src, bool detach);

/* Drop the any secondary attachments that the rendertarget backing of *did*
 * may have to *src*.
 * Error codes:
 *  ARCAN_ERRC_NO_SUCH_OBJECT
 */
arcan_errc arcan_video_detachfromrendertarget(arcan_vobj_id did,
	arcan_vobj_id src);
arcan_errc arcan_video_alterreadback(arcan_vobj_id did, int readback);
arcan_errc arcan_video_rendertarget_setnoclear(arcan_vobj_id did, bool value);

/*
 * Switch default attachmentpoint from the normal WORLDID to a user-
 * specified one. If this rendertarget is deleted, the default attachment
 * reverts back to WORLDID. Same applies to new contexts. Persisted objects
 * will default back to WORLDID on context transfers.
 */
arcan_errc arcan_video_defaultattachment(arcan_vobj_id id);

/*
 * Retrieve the vobj_id of the current default attachment.
 */
arcan_vobj_id arcan_video_currentattachment();

/* Object state property manipulation */
enum arcan_transform_mask arcan_video_getmask(arcan_vobj_id src);
arcan_errc arcan_video_transformmask(arcan_vobj_id src,
	enum arcan_transform_mask mask);

/*
 * Fallback flush -- will iterate all active contexts, detach frameservers from
 * their objects (but maintain their gl-store by incrementing the reference
 * counter), pop-all contexts and finally rebuild a new context with objects
 * that consist only of the frameservers.
 *
 * The main purpose for this is to enable the support of a recovery mode,
 * where, if something goes wrong in other layers (e.g. scripting), external
 * processes can be saved.
 *
 * CAVEAT: if the total number of frameservers in all contexts > the maximum
 * limit of objects in a context, the context will be truncated.
 * This would require a high number of concurrently running processes however.
 *
 * if pop is set, the adopt function will be called in a clean context
 * (desired when collapsing current app, not desired when switching app)
 */
typedef void (*recovery_adoptfun)(arcan_vobj_id new_ent, void*);
void arcan_video_recoverexternal(bool pop, int* saved,
	int* truncated, recovery_adoptfun, void* tag);

/*
 * sweep the active context and look for a vobj- with matching
 * vfunc tuple (tag, ptr)
 */
arcan_vobj_id arcan_video_findstate(enum arcan_vobj_tags tag, void* ptr);

/*
 * Convert the mipmapping mode for the video object to on [state=true] or
 * off [state=false]. By default, all objects are created with mimapping,
 * but for certain ones, there is a possible performance gain if you are
 * certain that lower mipmap levels will not be used.
 *
 * Note that OpenGL and friends can't directly free storage previously
 * used for mipmaps. Therefore, calls to this function will create a copy
 * of the offline buffer and use that to assign a new glstore.
 */
arcan_errc arcan_video_mipmapset(arcan_vobj_id id, bool state);

arcan_errc arcan_video_setclip(arcan_vobj_id id, enum arcan_clipmode toggleon);
arcan_errc arcan_video_tracetag(arcan_vobj_id id, const char* const message);
arcan_errc arcan_video_forceblend(arcan_vobj_id id, enum arcan_blendfunc);
arcan_errc arcan_video_objecttexmode(arcan_vobj_id id,
	enum arcan_vtex_mode modes, enum arcan_vtex_mode modet);
arcan_errc arcan_video_objectfilter(arcan_vobj_id id,
	enum arcan_vfilter_mode filter);
arcan_errc arcan_video_setzv(arcan_vobj_id id, int newzv);

/* Object state retrieval */
unsigned short arcan_video_getzv(arcan_vobj_id id);
const char* const arcan_video_readtag(arcan_vobj_id id);
img_cons arcan_video_storage_properties(arcan_vobj_id id);
surface_properties arcan_video_resolve_properties(arcan_vobj_id id);
surface_properties arcan_video_initial_properties(arcan_vobj_id id);
surface_properties arcan_video_current_properties(arcan_vobj_id id);
arcan_errc arcan_video_screencoords(arcan_vobj_id, vector*);
surface_properties arcan_video_properties_at(
	arcan_vobj_id id, uint32_t ticks);
img_cons arcan_video_dimensions(uint16_t w, uint16_t h);
arcan_errc arcan_video_forceread(arcan_vobj_id sid,
	bool local, av_pixel** dptr, size_t* dstsz);

/* Transformation chain actions */
arcan_errc arcan_video_objectmove(arcan_vobj_id id, float newx, float newy,
	float newz, unsigned int time);
arcan_errc arcan_video_moveinterp(arcan_vobj_id id, enum arcan_vinterp);
arcan_errc arcan_video_objectscale(arcan_vobj_id id, float wf, float hf,
	float df, unsigned int time);
arcan_errc arcan_video_scaleinterp(arcan_vobj_id id, enum arcan_vinterp);
arcan_errc arcan_video_objectrotate(arcan_vobj_id id, float ang, arcan_tickv time);
arcan_errc arcan_video_objectrotate3d(arcan_vobj_id id,
	float roll, float pitch, float yaw, arcan_tickv time);

arcan_errc arcan_video_objectopacity(arcan_vobj_id id, float opa,
	unsigned int time);
arcan_errc arcan_video_blendinterp(arcan_vobj_id id, enum arcan_vinterp);
arcan_errc arcan_video_origoshift(arcan_vobj_id id, float sx,
	float sy, float sz);
arcan_errc arcan_video_inheritorder(arcan_vobj_id id, bool val);
arcan_errc arcan_video_override_mapping(arcan_vobj_id id, float* dst);
arcan_errc arcan_video_retrieve_mapping(arcan_vobj_id id, float* dst);
arcan_errc arcan_video_setprogram(arcan_vobj_id id, agp_shader_id shid);
arcan_errc arcan_video_instanttransform(arcan_vobj_id id);
arcan_errc arcan_video_transfertransform(arcan_vobj_id sid,
	arcan_vobj_id did);
arcan_errc arcan_video_copytransform(arcan_vobj_id sid, arcan_vobj_id did);
arcan_errc arcan_video_copyprops(arcan_vobj_id sid, arcan_vobj_id did);
arcan_errc arcan_video_shareglstore(arcan_vobj_id sid, arcan_vobj_id did);
arcan_errc arcan_video_transformcycle(arcan_vobj_id, bool);
arcan_errc arcan_video_zaptransform(arcan_vobj_id id, float*);

/*
 * Associate a tag with the specified transform, and a mask of
 * valid transforms (only BLEND, ROTATE, SCALE, POSITION allowed).
 *
 * The tag will be associated with the last element of each specified
 * slot, and the event will fire wehn that transform is dropped from
 * the front.
 */
arcan_errc arcan_video_tagtransform(arcan_vobj_id id,
	intptr_t tag, enum arcan_transform_mask mask);

void arcan_video_cursorpos(int newx, int newy, bool absolute);
void arcan_video_cursorsize(size_t w, size_t h);
void arcan_video_cursorstore(arcan_vobj_id src);


/* picking, collision detection */
unsigned arcan_video_tick(unsigned steps, unsigned* njobs);
bool arcan_video_hittest(arcan_vobj_id id, int x, int y);

size_t arcan_video_pick(arcan_vobj_id rt,
	arcan_vobj_id* dst, size_t count, int x, int y);

size_t arcan_video_rpick(arcan_vobj_id rt,
	arcan_vobj_id* dst, size_t count, int x, int y);
#endif

