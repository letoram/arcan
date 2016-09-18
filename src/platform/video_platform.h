/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description:
 * This platform layer is an attempt to decouple the _video.c and _3dbase.c
 * parts of the engine from working with OpenGL directly.
 */

#ifndef HAVE_ARCAN_VIDEOPLATFORM
#define HAVE_ARCAN_VIDEOPLATFORM

/*
 * We only work with / support one internal pixel representation which should
 * be defined at build time to correspond to whatever the underlying hardware
 * supports optimally.
 */
#ifndef VIDEO_PIXEL_TYPE
#define VIDEO_PIXEL_TYPE uint32_t
#endif

typedef VIDEO_PIXEL_TYPE av_pixel;

#ifndef RGBA
#define RGBA(r, g, b, a)( ((uint32_t)(a) << 24) | ((uint32_t) (b) << 16) |\
((uint32_t) (g) << 8) | ((uint32_t) (r)) )
#endif

/*
 * Just prepared for a low-def format, none is really active at the moment
 * but likely candidate is RGB565 in scenarios where we need to constrain
 * memory and bandwidth use.
 */
#define RGBA_LOWDEF(r, g, b, a)( RGBA((r), (g), (b)) )

/*
 * To change the internal representation, define these macros in some other
 * header that is forcibly included, or redefine through the build-system.
 */
#ifdef HDEF_10BIT
#include "video_platform_hdef.h"
#else
#define OUT_DEPTH_R 8
#define OUT_DEPTH_G 8
#define OUT_DEPTH_B 8
#define OUT_DEPTH_A 0

#ifndef GL_PIXEL_FORMAT
#define GL_PIXEL_FORMAT GL_RGBA
#endif

#define GL_PIXEL_HDEF_FORMAT GL_PIXEL_FORMAT
#define RGBA_HDEF(r, g, b, a) RGBA(\
	(uint8_t)((r) * 255.0f), (uint8_t)((g) * 255.0f), \
	(uint8_t)((b) * 255.0f), (uint8_t)((a) * 255.0f))

#endif
#ifndef RGBA_FULLALPHA_REPACK
#define RGBA_FULLALPHA_REPACK(inv)(	RGBA( ((inv) & 0x000000ff), \
(((inv) & 0x0000ff00) >> 8), (((inv) & 0x00ff0000) >> 16), 0xff) )
#endif

#define GL_PIXEL_LDEF_FORMAT GL_PIXEL_FORMAT

#ifndef RGBA_DECOMP
static inline void RGBA_DECOMP(av_pixel val, uint8_t* r,
	uint8_t* g, uint8_t* b, uint8_t* a)
{
	*r = (val & 0x000000ff);
	*g = (val & 0x0000ff00) >>  8;
	*b = (val & 0x00ff0000) >> 16;
	*a = (val & 0xff000000) >> 24;
}
#endif

/*
 * For objects that are not opaque or invisible, a blending function can be
 * specified. These functions regulate how overlapping objects should be mixed.
 */
enum arcan_blendfunc {
	BLEND_NONE,
	BLEND_NORMAL,
	BLEND_FORCE,
	BLEND_ADD,
	BLEND_MULTIPLY
};

/*
 * Internal shader type tracking
 */
enum shdrutype {
	shdrbool   = 0,
	shdrint    = 1,
	shdrfloat  = 2,
	shdrvec2   = 3,
	shdrvec3   = 4,
	shdrvec4   = 5,
	shdrmat4x4 = 6
};

/* Built-in shader properties, these are order dependant, check shdrmgmt.c */
enum agp_shader_envts{
/* packed matrices */
	MODELVIEW_MATR  = 0,
	PROJECTION_MATR = 1,
	TEXTURE_MATR    = 2,
	OBJ_OPACITY     = 3,

/* transformation completion */
	TRANS_MOVE      = 4,
	TRANS_ROTATE    = 5,
	TRANS_SCALE     = 6,

/* object storage / rendering properties */
	SIZE_INPUT  = 7,
	SIZE_OUTPUT = 8,
  SIZE_STORAGE= 9,

	FRACT_TIMESTAMP_F = 10,
	TIMESTAMP_D       = 11,
};

/*
 * union specifier
 */
enum txstate {
	TXSTATE_OFF   = 0,
	TXSTATE_TEX2D = 1,
	TXSTATE_DEPTH = 2
};

enum storage_source {
	STORAGE_IMAGE_URI,
	STORAGE_TEXT,
	STORAGE_TEXTARRAY
};

struct storage_info_t {
	size_t refcount;
	uint32_t update_ts;

	union {
		struct {
/* ID number connecting to AGP */
			unsigned glid;
			uint64_t glformat;

/* used for PBO transfers */
			unsigned rid, wid;

/* intermediate storage for reconstructing lost context */
			uint32_t s_raw;
			av_pixel*  raw;

/* may need to propagate vpts state */
			uint64_t vpts;

/* re- construction string may be used as factory in conservative memory
 * management model to recreate contents of raw */
			enum storage_source kind;
			union {
				char* source;
				char** source_arr;
			};

/* used if we have an external buffered backing store
 * (implies s_raw / raw / source are useless) */
			int format;
			size_t stride;
			uintptr_t tag;
		} text;

		struct {
			float r;
			float g;
			float b;
		} col;
	} vinf;

	size_t w, h;
	uint8_t bpp, txmapped,
		txu, txv, scale, imageproc, filtermode;
};

/* Built in Shader Vertex Attributes */
enum shader_vertex_attributes {
	ATTRIBUTE_VERTEX,
	ATTRIBUTE_NORMAL,
	ATTRIBUTE_COLOR,
	ATTRIBUTE_TEXCORD
};

/*
 * end of internal representation specific data.
 */
typedef long long arcan_vobj_id;

/*
 * Allocate resources, devices and set up a safe initial default.
 * [w, h, bpp, fs, frames, caption] arguments are used for legacy reasons,
 * and new platform implementations should accept 0- values and rather
 * probe best values and use other mapping / notification functions for
 * resizing and similar operations.
 */
bool platform_video_init(uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* caption);

/*
 * Sent as a trigger to notify that higher scripting levels have recovered
 * from an error and possible video- layer related events are possibly missing
 * and may need to be re-emitted.
 */
void platform_video_recovery();

/*
 * Release / free as much resource as possible while still being able to
 * resume operations later. This is used for suspend/resume style behavior
 * when switching virtual terminals or when going into powersave- states.
 * After this point, the event subsystem will also be deinitialized.
 */
void platform_video_prepare_external();

/*
 * Undo the effects of the prepare_external call.
 */
void platform_video_restore_external();

/*
 * get a (NULL terminated) array of synchronization options that are valid
 * arguments to _setsynch(). It should follow the pattern
 * {"synchopt1", "description1",
 *  "synchopt2", "description2",
 *  NULL};
 */
const char** platform_video_synchopts();

/*
 * get a (NULL terminated) array of environment options that can be set during
 * the command line, this is primarily used to populate command-line help.
 */
const char** platform_video_envopts();

/*
 * The AGP layer may need to dynamically map symbols against whatever graphics
 * library is in play but the video layer is typically the one capable of
 * determining how such functions should be found.
 */
void* platform_video_gfxsym(const char* sym);

/*
 * switch active synchronization strategy (if possible), strat must be a valid
 * result from platform_video_synchopts and can change dynamically.
 */
void platform_video_setsynch(const char* strat);

/*
 * attempt to generate a handle that can be passed to an external process, this
 * is primarily used by arcan-in-arcan and frameservers that need to send a
 * buffer onwards.
 *
 * status outputs:
 */
enum status_handle {
	ERROR_UNSUPPORTED = -1, /* platform cannot handle buffer transfers */
  ERROR_BADSTORE = -2, /* store is not in a suitable format */
  READY_REUSE = 0, /* previous handle still valid */
  READY_TRANSFER = 1, /* new- handle to be transferred */
  READY_TRANSFERRED = 2 /* transfered using side-channel */
};
int64_t platform_video_output_handle(
	struct storage_info_t* store, enum status_handle* status);

/*
 * take the received handle and associate it with the specified backing store.
 */
bool platform_video_map_handle(struct storage_info_t*, int64_t inh);

/*
 * retrieve a descriptor for a client- render resource connected to the
 * specified card-index, or -1 if no such handle exists. */
int platform_video_cardhandle(int cardn);

/*
 * triggers the actual rendering and is responsible for applying whatever
 * synchronization strategy that is currently active, and to run the related
 * benchmark costs trigger functions (bench_register_cost,bench_register_frame)
 */
typedef void (*video_synchevent)(void);
void platform_video_synch(uint64_t tick, float fract,
	video_synchevent pre, video_synchevent post);

/*
 * string that can be used to identify the underlying video platform, i.e.
 * driver version, GL string etc. Primarily intended for debug- data
 * collection.
 */
const char* platform_video_capstr();

typedef uint32_t platform_display_id;
typedef uint32_t platform_mode_id;

struct monitor_mode {
	platform_mode_id id;

/* scanout resolution */
	size_t width;
	size_t height;

/* in millimeters */
	size_t phy_width;
	size_t phy_height;

/* esetimated output color depth */
	uint8_t depth;

/* estimated display vertical refresh, can be 0 to indicate a dynamic or
 * unknown rate -- primarily a hint to the synchronization strategy */
	uint8_t refresh;

/* Description regarding subpixel orientation, e.g. hRGB or vGRB etc. */
	const char* subpixel;

/* There should only be one primary mode per display */
	bool primary;

/* If the display supports user- specified mode configurations via the
 * _specify_mode option, this will be true */
	bool dynamic;
};

/*
 * Retrieve default rendertarget dimensions, virtual canvas is set in
 * width/height, output buffer is set in phy_width/phy_height
 */
struct monitor_mode platform_video_dimensions();

/*
 * Queue a rescan of output displays, this can be asynchronous and any results
 * are pushed as events.
 */
void platform_video_query_displays();

/*
 * query list of available modes for a single display
 */
struct monitor_mode* platform_video_query_modes(
	platform_display_id, size_t* count);

/*
 * query a specific display_id for a descriptive blob (EDID for some platforms)
 * that could be used to further identify the display. Actual parsing/
 * identification is left as an exercise for the caller.
 */
bool platform_video_display_edid(platform_display_id did,
	char** out, size_t* sz);

/*
 * switch mode on the display to a previously queried one from
 * platform_video_query_modes
 */
bool platform_video_set_mode(
	platform_display_id, platform_mode_id mode_id);

/*
 * update the gamma ramps for the specified display.
 *
 * returns [true] if the [did] and [r,g,b] channels are valid, the
 * underlying display accepts gamma ramps and [n_ramps] size corresponds
 * to the size of the ramps a _get call would yield.
 *
 * practical use-case is thus to first call platform_video_get_display_gamma,
 * modify the returned ramps, call platform_video_set_display_gamma and
 * then free the buffer from _get_.
 */
bool platform_video_set_display_gamma(platform_display_id did,
	size_t n_ramps, uint16_t* r, uint16_t* g, uint16_t* b);

/*
 * get the current gamma ramps for the specified display.
 *
 * return [true] if the [did] is valid, the underlying display
 * supports gamma ramps and enough memory exist to allocate output storage.
 *
 * [outb] will be set to a dynamically allocated buffer of 3*n_ramps,
 * with the ramps for each channel in a planar format (r, then g, then b).
 *
 * [Caller takes responsibility for deallocation]
 */
bool platform_video_get_display_gamma(platform_display_id did,
	size_t* n_ramps, uint16_t** outb);

/*
 * set or query the display power management state.
 * ADPMS_IGNORE => return current state,
 * other options change the current state of monitors connected to a display
 * and returns the estimated current state (should match requested state).
 * For LCDs, OFF / SUSPEND / STANDBY are essentially the same state.
 */
enum dpms_state {
	ADPMS_IGNORE = 0,
	ADPMS_OFF = 1,
	ADPMS_SUSPEND = 2,
	ADPMS_STANDBY = 3,
	ADPMS_ON = 4
};

enum dpms_state
	platform_video_dpms(platform_display_id disp, enum dpms_state state);

/*
 * Update and activate the specific (dynamic) mode with desired mode dimensions
 * and possibly refresh, this fails if the display do not support dynamic
 * mapping.
 */
bool platform_video_specify_mode(
	platform_display_id, struct monitor_mode mode);

/*
 * map a video object to the output display, if id is set to ARCAN_VIDEO_BADID,
 * that display output is disabled by whatever means possible (black+dealloc,
 * sleep display etc.) if id is set to ARCAN_VIDEO_WORLDID, the primary
 * rendertarget will be used.
 *
 * The object referenced by ID is not allowed to have a ffunc associated with
 * it, this in order for the platform to be notified when it is removed.
 */
enum blitting_hint {
	HINT_NONE = 0,
	HINT_FL_PRIMARY = 1,
	HINT_FIT = 2,
	HINT_CROP = 4,
	HINT_YFLIP = 8,
	HINT_ROTATE_CW_90 = 16,
	HINT_ROTATE_CCW_90 = 32,
	HINT_ENDM = 32
};

bool platform_video_map_display(arcan_vobj_id id,
	platform_display_id disp, enum blitting_hint);

void platform_video_shutdown();

/*
 * The following functions abstract the graphics operations that arcan_video.c
 * relies on, implementations can be found in platform/agp_.
 */

/*
 * Some underlying implementations need to allocate handles / contexts etc. as
 * an extension to what platform_video_init has already done, typically the
 * initial state-machine setup needed by gl.
 */
void agp_init();

/*
 * lower 16 bits: index
 * upper 16 bits: group (default 0)
 */
#define GROUP_INDEX(X) ((uint16_t) (((X) & 0xffff0000) >> 16))
#define SHADER_INDEX(X) ((uint16_t) (((X) & 0x0000ffff)))
#define SHADER_ID(SID, GID) (((uint32_t)(GID) << 16) | (uint32_t)(SID))
#define BROKEN_SHADER ((uint32_t)0xffffffff)
typedef uint32_t agp_shader_id;

/*
 * Retrieve the default shader for a specific purpose,
 * BASIC_2D => single textured, alpha in obj_opacity
 * COLOR_2D => not textured, color channel in uniforms
 */
enum SHADER_TYPES {
	BASIC_2D = 0,
	COLOR_2D,
	BASIC_3D,
	SHADER_TYPE_ENDM
};
agp_shader_id agp_default_shader(enum SHADER_TYPES);
void agp_shader_source(enum SHADER_TYPES, const char**, const char**);

/*
 * return a NULL terminated list of supported environment variables
 */
const char** agp_envopts();

/*
 * Identification string for the shader language supported, this is platform
 * dependent and need to be exposed to higher layers as there is no one-shot
 * portable solution for this.  Expect to need a path for 'NONE', 'GLSL120' and
 * 'GLSL100'
 */
const char* agp_shader_language();

/*
 * Identification string for the underlying graphics API as such, typical ones
 * would be 'GLES3' and 'OPENGL21'. For pixman revisions, we'll likely add
 * special 'common effects that can efficiently be implemented in software' for
 * low-power optimizations, either as part of the ident or as part of the
 * shader language.
 */
const char* agp_backend_ident();

/*
 * Set as currently active sampling buffer for other drawing commands
 */
void agp_activate_vstore(struct storage_info_t* backing);

/*
 * Explicitly deactivate vstore, after this state of the specified backing
 * store can be considered undefined.
 */
void agp_deactivate_vstore();

/*
 * Drop the underlying ID mapping with a pending call to update_vstore, though
 * the application manually managed reallocation
 */
void agp_null_vstore(struct storage_info_t* backing);

/*
 * Setup an empty vstore backing with the specified dimensions
 */
void agp_empty_vstore(struct storage_info_t* backing, size_t w, size_t h);

/*
 * Extended form to allow internal platform choice in format used,
 * can be used to some rendertargets for improved performance and for
 * buffer-passing workarounds
 */
enum vstore_hint
{
	VSTORE_HINT_NORMAL = 0,
	VSTORE_HINT_NOALPHA = 1,
	VSTORE_HINT_LODEF = 2,
	VSTORE_HINT_LODEF_NOALPHA = 3,
	VSTORE_HINT_HIDEF = 4,
	VSTORE_HINT_HIDEF_NOALPHA = 5,
};
void agp_empty_vstoreext(struct storage_info_t* backing,
	size_t w, size_t h, enum vstore_hint);

/*
 * Rebuild an existing vstore to handle a change in data source dimensions
 * without sharestorage- like operations breaking
 */
void agp_resize_vstore(struct storage_info_t* backing, size_t w, size_t h);

/*
 * Deallocate all resources associated with a backing store.  Note that this
 * function DO NOT respect the reference counter field, that is the
 * responsibility of the caller. (engine uses vint_* for this purpose).
 */
void agp_drop_vstore(struct storage_info_t* backing);

/*
 * Map multiple backing store devices sequentially across available texture
 * units.
 */
void agp_activate_vstore_multi(struct storage_info_t** backing, size_t n);

/*
 * Prepare the specified backing store for streaming texture uploads. The
 * semantics is determined by the stream_type and meta. See description
 * for agp_stream_prepare.
 */
enum stream_type {
	STREAM_RAW,
	STREAM_RAW_DIRECT,
	STREAM_RAW_DIRECT_COPY,
	STREAM_RAW_DIRECT_SYNCHRONOUS,
	STREAM_HANDLE
};

struct stream_meta {
	union{
		struct {
		av_pixel* buf;
		bool dirty;
		unsigned x1, y1, w, h, stride;
		};
		int64_t handle;
	};
	enum stream_type type;
	bool state;
};

/*
 * Streaming update of the !NULL textured backing store in [store].
 *
 * Contents of [base] depends on [type]:
 *  - RAW: just synch opaque backing store (on-GPU), buffer to populate
 *         will be returned in meta.buf.
 *                prop: none, really. con: additional copy, slow
 *
 *  - RAW_DIRECT: prop: asynchronous copy of contents, fastest when handle
 *                is unavailable, con:
 *
 *  - RAW_DIRECT_SYNCHRONOUS: block and copy meta.buf.
 *                pro: guarantee of content state, con: stalls pipeline
 *
 *  - RAW_HANDLE: handle contains reference to opaque backing store.
 *                pro: possibly the fastest, covers more formats
 *                con: .raw is not in synch, reliability/availability issues
 *
 * Typical use:
 *  create a [struct stream_meta] with possble subregion or handle.
 *
 *  meta = agp_stream_prepare(store, mode, type);
 *   - populate meta.buf or meta.handle (type: STREAM_HANDLE)
 *  agp_stream_commit(store, mode, type); (unless meta/buf)
 *   - for type:HANDLE, state should be valid or fallback
 *  agp_stream_release(store); (type: STREAM_RAW)
 *
 * In a dream world, there should be an option to take our shmif- vidp,
 * a synch fence and have driver map to opaque backing store.
 */
struct stream_meta agp_stream_prepare(struct storage_info_t* store,
	struct stream_meta base, enum stream_type type);

void agp_stream_commit(struct storage_info_t*, struct stream_meta);
void agp_stream_release(struct storage_info_t*, struct stream_meta);

/*
 * Synchronize a populated backing store with the underlying graphics layer.
 * [copy] is used to indicate if the backing contents should be updated,
 *        if set to false, only filtering and similar flags will be synched
 */
void agp_update_vstore(struct storage_info_t*, bool copy);

enum pipeline_mode {
	PIPELINE_2D,
	PIPELINE_3D
};

/*
 * Set up the base internal state tracking for 2D, 3D or other specialized
 * configurations.
 */
void agp_pipeline_hint(enum pipeline_mode);

/*
 * Synchronize the current backing store on-host buffer (i.e.
 * dstore->vinf.text.raw).
 */
void agp_readback_synchronous(struct storage_info_t* dst);

struct asynch_readback_meta {
	av_pixel* ptr;
	size_t buf_sz;
	size_t w;
	size_t h;
	size_t stride;

	void (*release)(void* tag);
	void* tag;
};

/*
 * Check if a pending readback request has been completed.
 * In that case, [meta.ptr] will be !NULL and the caller is expected to:
 * meta.release(meta.tag); when finished using the contents of [meta.ptr]
 */
struct asynch_readback_meta agp_poll_readback(struct storage_info_t*);

/*
 * Initiate a new asynchronous readback.
 * if one is already pending, this is a no-operation.
 */
void agp_request_readback(struct storage_info_t*);

/*
 * For clipping and similar operations where we want to
 * prepare a mask ("stencil") buffer, this sequence of operations
 * is used:
 * agp_prepare_stencil()  -- reset lingering state
 * agp_draw_stencil(...)  -- multiple calls to populate
 * agp_activate_stencil() -- other drawcalls should honor this mask
 * agp_disable_stencil()  -- normal operations
 */
void agp_prepare_stencil();
void agp_draw_stencil(float x1, float y1, float x2, float y2);
void agp_activate_stencil();
void agp_disable_stencil();

/*
 * Switch the currently active blending mode, i.e. how new objects shall be
 * drawn in respects to the current color output.
 */
void agp_blendstate(enum arcan_blendfunc);

/*
 * Bind uniforms and draw using the currently active vstore to the active
 * rendertarget. [txcos], [modelview] can be NULL. In that case, texturing
 * will be ignored and identity matrix will be used.
 */
void agp_draw_vobj(float x1, float y1, float x2, float y2,
	const float* txcos, const float* modelview);

/*
 * Destination format for rendertargets. Note that we do not currently suport
 * floating point targets and that for some platforms, COLOR_DEPTH will map to
 * COLOR_DEPTH_STENCIL.
 */
enum rendertarget_mode {
	RENDERTARGET_DEPTH = 0,
	RENDERTARGET_COLOR = 1,
	RENDERTARGET_COLOR_DEPTH = 2,
	RENDERTARGET_COLOR_DEPTH_STENCIL = 3
};

/*
 * opaque structure for clustering other video operations, setup_rendertarget
 * allocates and associates a rendertarget with the specified texture backing
 * store (that also defines dimensions etc.) with the preferred use hinted in
 * mode.
 */
struct agp_rendertarget;
struct agp_rendertarget* agp_setup_rendertarget(struct storage_info_t*,
	enum rendertarget_mode mode);

#ifdef AGP_ENABLE_UNPURE
/*
 * Break the opaqueness somewhat by exposing underlying handles, primarily for
 * frameservers that explicitly need to use GL and where we want to re-use the
 * underlying code.
 */
void agp_rendertarget_ids(struct agp_rendertarget*, uintptr_t* tgt,
	uintptr_t* col, uintptr_t* depth);
#endif

/*
 * Drop and rebuild the current backing store, along with possible transfer
 * objects etc. with the >0 dimensions specified by neww / newh.
 */
void agp_resize_rendertarget(struct agp_rendertarget*,
	size_t neww, size_t newh);

/*
 * Switch the currently active rendertarget to the one specified.  If set to
 * null, rendertarget based rendering will be disabled.
 */
void agp_activate_rendertarget(struct agp_rendertarget*);
void agp_drop_rendertarget(struct agp_rendertarget*);

/*
 * reset the currently bound rendertarget output buffer
 */
void agp_rendertarget_clear();

enum agp_mesh_type {
	AGP_MESH_TRISOUP,
	AGP_MESH_POINTCLOUD
};

struct mesh_storage_t
{
	float* verts;
	float* txcos;
	float* normals;
	unsigned* indices;

	size_t n_vertices;
	size_t n_elements;
	size_t n_indices;
	size_t n_triangles;

	enum agp_mesh_type type;

/* opaque field used to store additional implementation defined tags, e.g. VBO
 * backing index etc. */
	uintptr_t opaque;
};

/*
 * submit the specified mesh for rendering, which parts of the mesh that will
 * actually be transmitted and mapped depends on the active shader (which is
 * probed through shader_vattribute_loc
 */
enum agp_mesh_flags {
	MESH_FACING_FRONT   = 1,
	MESH_FACING_BACK    = 2,
	MESH_FACING_BOTH    = 3,
	MESH_FACING_NODEPTH = 4,
	MESH_DEBUG_GEOMETRY = 8
};

/*
 * Some video platforms need to have a more intimate connection with the agp
 * implementation, i.e. distinguish between GLES and OPENGL etc.
 */
const char* agp_ident();

void agp_submit_mesh(struct mesh_storage_t*, enum agp_mesh_flags);

/*
 * Mark that the contents of the mesh has changed dynamically and that possible
 * GPU- side cache might need to be updated.
 */
void agp_invalidate_mesh(struct mesh_storage_t*);

/*
 * Get a copy of the current display output and save into the supplied buffer,
 * scale / convert color format if necessary.
 */
void agp_save_output(size_t w, size_t h, av_pixel* dst, size_t dsz);

/* delete, forget and flush all allocated shaders */
void agp_shader_flush();

/*
 * Drop possible underlying handles, a call chain of unload_all and rebuild_all
 * should yield no visible changes to the rest of the engine.
 */
void agp_shader_unload_all();

/*
 * Will be called on possible external launch transitions where we might have
 * lost underlying context data.
 */
void agp_shader_rebuild_all();

/*
 * Set the current transformation / processing rules (i.e. shader) This will be
 * called on new objects and may effectively be a no-op if the same one is
 * already active and there is only one uniform group.
 */
int agp_shader_activate(agp_shader_id shid);

/*
 * Take transformation rules in source-code form (platform specific a
 * agp_shader_language) and build for the specified processing stages.
 */
agp_shader_id agp_shader_build(const char* tag, const char* geom,
	const char* vert, const char* frag);

/*
 * Drop the specified shader and mark as re-usable (destroy on invalid ID
 * should return false here). States local to shid should be considered
 * undefined after this.
 */
bool agp_shader_destroy(agp_shader_id shid);

/*
 * Name- based shader lookup (typically to match string representations from
 * higher-level languages without tracking numerical IDs).
 */
agp_shader_id agp_shader_lookup(const char* tag);
const char* agp_shader_lookuptag(agp_shader_id id);

/*
 * Get a local copy of the source stored in *vert, *frag based
 * on the specified ID.
 */
bool agp_shader_lookupprgs(agp_shader_id id,
	const char** vert, const char** frag);
bool agp_shader_valid(agp_shader_id);

/*
 * Get the vertex- attribute location for a specific vertex attribute (as some
 * integral reference or -1 on non-existing in the currently bound program).
 */
int agp_shader_vattribute_loc(enum shader_vertex_attributes attr);

/*
 * Allocate a new uniform group to the shader specified by shid.  The new group
 * is tied to the lifespan of the shader in general, and initially copies the
 * values from the default group (first index).  The uniform group index is
 * part of the shader_id.
 */
agp_shader_id agp_shader_addgroup(agp_shader_id shid);

/*
 * Update the specified built-in environment variable with a slot, value and
 * size matching the tables above, should return -1 if no such- slot exists or
 * is not available in the currently bound program.
 */
int agp_shader_envv(enum agp_shader_envts slot, void* value, size_t size);

/*
 * Get a string representation for the specific environment slot, this is
 * primarily for debugging / tracing purposes.
 */
const char* agp_shader_symtype(enum agp_shader_envts env);

/*
 * Update the uniform value of the currently bound shader and uniform group
 */
void agp_shader_forceunif(const char* label, enum shdrutype type, void* value);

#endif
