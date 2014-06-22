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

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
 *
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

/*
 * The following macros are defined in order to compile-time define 
 * different native/forced data format. It is currently unwise to edit 
 * these as some parts of the codebase slated for refactoring still
 * assumes it is working with RGBA8888.
 *
 * Furthermore, there should be a build-time step that probes different 
 * variants (RGBA, ARGB, BGRA, ...) based on the GPU drivers at hand and
 * define macros accordingly.
 */
#ifndef RGBA
#define RGBA(r, g, b, a)( ((uint32_t)(a) << 24) | ((uint32_t) (b) << 16) |\
((uint32_t) (g) << 8) | ((uint32_t) (r)) )
#endif

/*
 * Used for frameserver<->video where the A channel of the input should
 * be ignored when uploading.
 */
#define RGBA_FULLALPHA_REPACK(inv)(	RGBA( ((inv) & 0x000000ff), \
(((inv) & 0x0000ff00) >> 8), (((inv) & 0x00ff0000) >> 16), 0xff) )

#ifndef CONTEXT_STACK_LIMIT
#define CONTEXT_STACK_LIMIT 8
#endif

#ifndef GL_PIXEL_FORMAT
#define GL_PIXEL_FORMAT GL_RGBA
#endif

#ifndef VIDEO_PIXEL_TYPE
#define VIDEO_PIXEL_TYPE uint32_t
#endif

typedef VIDEO_PIXEL_TYPE av_pixel; 

#ifndef GL_PIXEL_BPP
#define GL_PIXEL_BPP 4
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
	ARCAN_VFILTER_NONE,
	ARCAN_VFILTER_LINEAR,
	ARCAN_VFILTER_BILINEAR,
	ARCAN_VFILTER_TRILINEAR
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
 * Destination format for rendertargets. Note that we do not currently
 * suport floating point targets and that for some platforms,
 * COLOR_DEPTH will map to COLOR_DEPTH_STENCIL.
 */
enum rendertarget_mode {
	RENDERTARGET_DEPTH = 0,
	RENDERTARGET_COLOR = 1,
	RENDERTARGET_COLOR_DEPTH = 2,
	RENDERTARGET_COLOR_DEPTH_STENCIL = 3
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
ARCAN_TAG_3DOBJ     = 5,/* got a corresponding entry in arcan_3dbase, ffunc is
												   used to control the behavior of the 3d part        */
ARCAN_TAG_3DCAMERA  = 6,/* set after using camtag,
													 only usable on NONE/IMAGE                          */
ARCAN_TAG_ASYNCIMGLD= 7,/* intermediate state, means that getimage is still
											     loading, don't touch objects in this state         */
ARCAN_TAG_ASYNCIMGRD= 8 /* when asynch loader is finished, ready to collect   */
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

/*
 * For objects that are not opaque or invisible, a blending function
 * can be specified. These functions regulate how overlapping objects
 * should be mixed.  
 */
enum arcan_blendfunc {
	BLEND_NONE,
	BLEND_NORMAL, 
	BLEND_FORCE,   
	BLEND_ADD,     
	BLEND_MULTIPLY  
};

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
 * State container for aux- data.
 * Tag is volatile as it can arbitrarily change from ASYNCIMG loading
 * to regular image. 
 */
typedef struct {
	volatile int tag;
	void* ptr;
} vfunc_state;

/*
 * Reversed VOBJ values, everything is forcibly linked to WORLDID
 * (which can be manipulated)
 */
extern arcan_vobj_id ARCAN_VIDEO_WORLDID;
extern arcan_vobj_id ARCAN_VIDEO_BADID;

/*
 * Prototype and enumerations for frameserver- and other dynamic data sources
 */

enum arcan_ffunc_cmd {
	FFUNC_POLL    = 0, /* every frame, check for new data */
	FFUNC_RENDER  = 1, /* follows a GOTFRAME returning poll */
	FFUNC_TICK    = 2, /* logic pulse */
	FFUNC_DESTROY = 3, /* custom cleanup */ 
	FFUNC_READBACK= 4  /* recordtargets, when a readback is ready */
};

enum arcan_ffunc_rv {
	FFUNC_RV_NOFRAME  = 0,
	FFUNC_RV_GOTFRAME = 1, /* ready to transfer a frame to the object       */
	FFUNC_RV_COPIED   = 2, /* means that the local storage has been updated */
	FFUNC_RV_NOUPLOAD = 64 /* don't synch local storage with GPU buffer     */
};

typedef enum arcan_ffunc_rv(*arcan_vfunc_cb)(
	enum arcan_ffunc_cmd cmd, uint8_t* buf, 
	uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, 
	unsigned int mode, vfunc_state state
);

/*
 * Perform basic rendering library setup and forward
 * requests to platform layer. Note that width/height/bpp are hints
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
	bool fullscreen, bool frames, bool conservative);

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
 * Perform a render-pass, set synch to true if we should block
 * until the results have been sucessfully sent to the output display.
 * Fragment is in the 0..999 range and specifies how far we are 
 * towards the next logical tick. This is used to calculate interpolations
 * for transformation chains to get smoother animation even when running
 * with a slow logic clock.
 */
unsigned arcan_video_refresh(float fragment, bool synch);

/*
 * Specify if the 3D pipeline should be processed and if so,
 * if it should happen before or after the 2D pipeline has been processed.
 */
void arcan_video_3dorder(enum arcan_order3d);

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
arcan_errc arcan_video_screenshot(void** dptr, size_t* dsize);

/*
 * Request a fullscreen/window toggle if working / implemented,
 * not guranteed to perform any meaningful change.
 */
void arcan_video_fullscreen();

/*
 * Accessors for the current rendering dimensions, these do not 
 * necessarily correlate to the actual device dimensions. They
 * rather define the coordinate- and dimensioning system we're working
 * within. 
 */
uint16_t arcan_video_screenw();
uint16_t arcan_video_screenh();

/*
 * Get the currently highest Z value (rendering order) for the 
 * currently active context. This imposes a linear search through
 * the entire context, O(n) where n is context size.
 */
unsigned arcan_video_maxorder();

/*
 * Set a new object limit for new contexts. This will not effect 
 * the current context. A special case is that the outmost context
 * can be poped and will then have the new object limit.
 *
 * 0 > newlim < 65535
 */
void arcan_video_contextsize(unsigned newlim);

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
arcan_vobj_id arcan_video_rawobject(uint8_t* buf, size_t bufs, 
	img_cons constraints, float origw, float origh, unsigned short zv);

/*
 * Create an object with a dynamic (callback- driven) input source.
 * This is also used for managing 3D objects.
 */
arcan_vobj_id arcan_video_addfobject(arcan_vfunc_cb feed, 
	vfunc_state state, img_cons constraints, unsigned short zv);

/*
 * Create a restricted instance of a specific object. 
 * These instances forcibly inherits a lot of properties from its 
 * parent, and other arcan_video_ functions that are restricted to 
 * instances will return ARCAN_ERRC_CLONE_NOT_PERMITTED, if used.
 *
 * Ideally, instance calls can re-use a lot of graphic state containers
 * from its parent, but the feature is largely superseeded by the less
 * restricted nullobject with shared storage.
 *
 * Some clone-restricted features include feed functions, framesets, 
 * linking, altering living mask, persist flags.
 *
 */
arcan_vobj_id arcan_video_cloneobject(arcan_vobj_id id);

/*
 * Create a new video object based on a format string.
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
 * stringdimensions is a reduced version of this function that only
 * generates the data without creating a video object, setting up a 
 * backing store etc.
 */
arcan_vobj_id arcan_video_renderstring(const char* message, int8_t line_spacing, 
	int8_t tab_spacing, unsigned int* tabs, unsigned int* lines, 
	unsigned int** lineheights);
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
arcan_errc arcan_video_alterfeed(arcan_vobj_id id, 
	arcan_vfunc_cb feed, vfunc_state state);

/*
 * Get a reference to the current feedstate in use by a specific object.
 */
vfunc_state* arcan_video_feedstate(arcan_vobj_id);

/* 
 * A skeleton that can be used to disable dynamic behaviors in
 * a dynamic object, use as [feed] argument to arcan_video_alterfeed.
 */
arcan_vfunc_cb arcan_video_emptyffunc();

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
arcan_errc arcan_video_resizefeed(arcan_vobj_id id, img_cons store, 
	img_cons display);

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
 * Create a new storage based on the one in used by [id] and resampled
 * using the shader specified with [prg]. Associate this new storage with
 * the [id] container. 
 */
arcan_errc arcan_video_resampleobject(arcan_vobj_id id, 
	int neww, int newh, arcan_shader_id prg); 

/* Object hierarchy related functions */
arcan_errc arcan_video_linkobjs(arcan_vobj_id src, arcan_vobj_id parent, 
	enum arcan_transform_mask mask);
arcan_vobj_id arcan_video_findparent(arcan_vobj_id id);
arcan_vobj_id arcan_video_findchild(arcan_vobj_id parentid, unsigned ofs);
arcan_errc arcan_video_changefilter(arcan_vobj_id id, 
	enum arcan_vfilter_mode);
arcan_errc arcan_video_persistobject(arcan_vobj_id id);

arcan_errc arcan_video_allocframes(arcan_vobj_id id, uint8_t capacity, 
	enum arcan_framemode mode);
arcan_vobj_id arcan_video_setasframe(arcan_vobj_id dst, arcan_vobj_id src, 
	unsigned fid, bool detach, arcan_errc* errc);
arcan_errc arcan_video_setactiveframe(arcan_vobj_id dst, unsigned fid);
arcan_errc arcan_video_framecyclemode(arcan_vobj_id id, signed mode);

/* Rendertarget- operations */
arcan_errc arcan_video_setuprendertarget(arcan_vobj_id did, int readback, 
	bool scale, enum rendertarget_mode format);		
arcan_errc arcan_video_forceupdate(arcan_vobj_id vid);
arcan_errc arcan_video_attachtorendertarget(arcan_vobj_id did, 
	arcan_vobj_id src, bool detach);
arcan_errc arcan_video_alterreadback(arcan_vobj_id did, int readback);
arcan_errc arcan_video_rendertarget_setnoclear(arcan_vobj_id did, bool value);

/* Object state property manipulation */ 
enum arcan_transform_mask arcan_video_getmask(arcan_vobj_id src);
arcan_errc arcan_video_transformmask(arcan_vobj_id src, 
	enum arcan_transform_mask mask);

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
arcan_errc arcan_video_setzv(arcan_vobj_id id,unsigned short newzv);

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
arcan_errc arcan_video_forceread(arcan_vobj_id sid, void** dptr, size_t* dstsz);

/* Transformation chain actions */
arcan_errc arcan_video_objectmove(arcan_vobj_id id, float newx, float newy, 
	float newz, unsigned int time);
arcan_errc arcan_video_moveinterp(arcan_vobj_id id, enum arcan_vinterp);
arcan_errc arcan_video_objectscale(arcan_vobj_id id, float wf, float hf, 
	float df, unsigned int time);
arcan_errc arcan_video_scaleinterp(arcan_vobj_id id, enum arcan_vinterp);
arcan_errc arcan_video_objectrotate(arcan_vobj_id id, float roll, float pitch, 
	float yaw, unsigned int time);
arcan_errc arcan_video_objectopacity(arcan_vobj_id id, float opa, 
	unsigned int time);
arcan_errc arcan_video_blendinterp(arcan_vobj_id id, enum arcan_vinterp);
arcan_errc arcan_video_origoshift(arcan_vobj_id id, float sx, 
	float sy, float sz);
arcan_errc arcan_video_inheritorder(arcan_vobj_id id, bool val);
arcan_errc arcan_video_override_mapping(arcan_vobj_id id, float* dst);
arcan_errc arcan_video_retrieve_mapping(arcan_vobj_id id, float* dst);
arcan_errc arcan_video_setprogram(arcan_vobj_id id, arcan_shader_id shid);
arcan_errc arcan_video_instanttransform(arcan_vobj_id id);
arcan_errc arcan_video_transfertransform(arcan_vobj_id sid, 
	arcan_vobj_id did);
arcan_errc arcan_video_copytransform(arcan_vobj_id sid, arcan_vobj_id did);
arcan_errc arcan_video_copyprops(arcan_vobj_id sid, arcan_vobj_id did);
arcan_errc arcan_video_shareglstore(arcan_vobj_id sid, arcan_vobj_id did);
arcan_errc arcan_video_transformcycle(arcan_vobj_id, bool);
arcan_errc arcan_video_zaptransform(arcan_vobj_id id);

/* picking, collision detection */
unsigned arcan_video_tick(unsigned steps, unsigned* njobs);
bool arcan_video_hittest(arcan_vobj_id id, unsigned int x, unsigned int y);
unsigned int arcan_video_pick(arcan_vobj_id* dst, unsigned int count, 
	int x, int y);
unsigned int arcan_video_rpick(arcan_vobj_id* dst, unsigned int count, 
	int x, int y);
uint32_t arcan_video_pick_detailed(uint32_t* dst, uint32_t count, 
	uint16_t x, uint16_t y, int zval_low, int zval_high, bool ignore_alpha);
#endif

