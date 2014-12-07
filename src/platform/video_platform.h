/*
 * Copyright 2014, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef HAVE_ARCAN_VIDEOPLATFORM
#define HAVE_ARCAN_VIDEOPLATFORM

/*
 * This platform layer is an attempt to decouple the _video.c
 * and _3dbase.c parts of the engine from OpenGL.
 */

/*
 * We only work with / support one internal pixel representation
 * which should be defined at build time to correspond to whatever
 * the underlying hardware supports optimally.
 */
#ifndef VIDEO_PIXEL_TYPE
#define VIDEO_PIXEL_TYPE uint32_t
#endif

typedef VIDEO_PIXEL_TYPE av_pixel;

/*
 * To change the internal representation, define this macros in
 * some other header that is forcibly included or redefine through
 * the build-system.
 */
#ifndef RGBA
#define RGBA(r, g, b, a)( ((uint32_t)(a) << 24) | ((uint32_t) (b) << 16) |\
((uint32_t) (g) << 8) | ((uint32_t) (r)) )
#endif

#ifndef GL_PIXEL_FORMAT
#define GL_PIXEL_FORMAT GL_RGBA
#endif

#ifndef GL_PIXEL_BPP
#define GL_PIXEL_BPP 4
#define GL_PIXEL_BPP_BIT 32
#endif

#define RGBA_FULLALPHA_REPACK(inv)(	RGBA( ((inv) & 0x000000ff), \
(((inv) & 0x0000ff00) >> 8), (((inv) & 0x00ff0000) >> 16), 0xff) )

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

/* Built-in shader properties, these are
 * order dependant, check shdrmgmt.c */
enum arcan_shader_envts{
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

struct storage_info_t {
	size_t refcount;

	union {
		struct {
/* ID number connecting to AGP */
			unsigned glid;

/* used for PBO transfers */
			unsigned rid, wid;

/* intermediate storage for reconstructing lost context */
			uint32_t s_raw;
			av_pixel*  raw;

/* re- construction string should we be conservative and free raw */
			char*   source;

/* used if we have an external buffered backing store
 * (implies s_raw / raw / source are useless) */
			int format;
			size_t stride;

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
 * Setup the video layer to some undetermined default.
 * The w/h/bpp/fs/frames/caption arguments are currently here
 * due to legacy, in the future we simply probe reasonable
 * values and then let the display/window mechanisms take over.
 */
bool platform_video_init(uint16_t w, uint16_t h,
	uint8_t bpp, bool fs, bool frames, const char* caption);

/*
 * get a (NULL terminated) array of synchronization options that are
 * valid arguments to _setsynch(). It should follow the pattern
 * {"synchopt1", "description1",
 *  "synchopt2", "description2",
 *  NULL};
 */
const char** platform_video_synchopts();

/*
 * get a (NULL terminated) array of environment options that can be
 * set during the command line, this is primarily used to populate
 * command-line help.
 */
const char** platform_video_envopts();

/*
 * The AGP layer may need to dynamically map symbols against
 * whatever graphics library is in play but the video layer is
 * typically the one capable of determining how
 * such functions should be found.
 */
void* platform_video_gfxsym(const char* sym);

/*
 * switch active synchronization strategy (if possible), strat must be
 * a valid result from platform_video_synchopts and can change dynamically.
 */
void platform_video_setsynch(const char* strat);

/*
 * attempt to generate a handle that can be passed to an external
 * process, this is primarily used by arcan-in-arcan and frameservers
 * that need to send a buffer onwards.
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
 * take the received handle and associate it
 * with the specified backing store.
 */
bool platform_video_map_handle(struct storage_info_t*, int64_t inh);

/*
 * triggers the actual rendering and is responsible for applying whatever
 * synchronization strategy that is currently active, and to run the related
 * benchmark costs trigger functions (bench_register_cost,bench_register_frame)
 */
typedef void (*video_synchevent)(void);
void platform_video_synch(uint64_t tick, float fract,
	video_synchevent pre, video_synchevent post);

/*
 * string that can be used to identify the underlying video platform,
 * i.e. driver version, GL string etc. Primarily intended for debug- data
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

/* estimated display vertical refresh, can be 0
 * to indicate a dynamic or unknown rate --
 * primarily a hint to the synchronization strategy */
	uint8_t refresh;

/* Description regarding subpixel orientation,
 * e.g. hRGB or vGRB etc. */
	const char* subpixel;

/* There should only be one primary mode per display */
	bool primary;

/* If the display supports user- specified mode configurations via
 * the _specify_mode option, this will be true */
	bool dynamic;
};

/*
 * Retrieve default rendertarget dimensions,
 * virtual canvas is set in width/height,
 * output buffer is set in phy_width/phy_height
 */
struct monitor_mode platform_video_dimensions();

/*
 * Get list of available display IDs, these can then be queried for
 * currently available modes (which is subject to change based on
 * what connectors a user inserts / removes.
 */
platform_display_id* platform_video_query_displays(size_t* count);
struct monitor_mode* platform_video_query_modes(platform_display_id,
	size_t* count);

bool platform_video_set_mode(platform_display_id, platform_mode_id mode_id);

/*
 * Update and activate the specific (dynamic) mode with new mode options,
 * fails if the display does not support dynamic mapping.
 */
bool platform_video_specify_mode(platform_display_id,
	platform_mode_id mode_id, struct monitor_mode mode);

/*
 * map a video object to the output display,
 * if id is set to ARCAN_VIDEO_BADID, that display output is disabled
 * by whatever means possible (black+dealloc, sleep display etc.)
 * if id is set to ARCAN_VIDEO_WORLDID, the primary rendertarget will
 * be used.
 *
 * The object referenced by ID is not allowed to have a ffunc associated
 * with it, this in order for the platform to be notified when it is removed.
 */
enum blitting_hint {
	HINT_NONE,
	HINT_FIT,
	HINT_CROP,
	HINT_ROTATE_CW_90,
	HINT_ROTATE_CCW_90,
	HINT_ENDM
};

bool platform_video_map_display(arcan_vobj_id id,
	platform_display_id disp, enum blitting_hint);

void platform_video_shutdown();

/*
 * The following function abstracts the graphics operations that
 * arcan_video.c relies on, implementations can be found in platform/agp_.
 *
 * This is currently a refactor-in-progress to fix some long standing
 * issues with GL<->GLES incompatibilty and inefficies that come from
 * the previous GL2.1 requirement. When the GL_HEADERS hack has been
 * removed, that refactor can be considered completed.
 */

/*
 * Some underlying implementations need to allocate handles / contexts
 * etc. as an extension to what platform_video_init has already done,
 * typically the initial state-machine setup needed by gl.
 */
void agp_init();

typedef long int arcan_shader_id;

/*
 * Retrieve the default shader for a specific purpose,
 * BASIC_2D => single textured, alpha in obj_opacity
 * COLOR_2D => not textured, color channel in uniforms
 */
enum SHADER_TYPES {
	BASIC_2D = 0,
	COLOR_2D,
	SHADER_TYPE_ENDM
};
arcan_shader_id agp_default_shader(enum SHADER_TYPES);
void agp_shader_source(enum SHADER_TYPES, const char**, const char**);

/*
 * return a NULL terminated list of supported environment variables
 */
const char** agp_envopts();

/*
 * Identification string for the shader language supported,
 * this is platform dependent and need to be exposed to higher
 * layers as there is no one-shot portable solution for this.
 * Expect to need a path for 'NONE', 'GLSL120' and 'GLSL100'
 */
const char* agp_shader_language();

/*
 * Identification string for the underlying graphics API as
 * such, typical ones would be 'GLES3', 'OPENGL21', and 'SOFTWARE'.
 */
const char* agp_backend_ident();

/*
 * Set as currently active sampling buffer for other drawing commands
 */
void agp_activate_vstore(struct storage_info_t* backing);

/*
 * Explicitly deactivate vstore, after this state of the specified backing
 * store can be consideired undefined.
 */
void agp_deactivate_vstore(struct storage_info_t* backing);

/*
 * Drop the underlying ID mapping with a pending call to update_vstore,
 * though the application manually managed reallocation
 */
void agp_null_vstore(struct storage_info_t* backing);

/*
 * Setup an empty vstore backing with the specified dimensions
 */
void agp_empty_vstore(struct storage_info_t* backing, size_t w, size_t h);

/*
 * Rebuild an existing vstore to handle a change in data source
 * dimensions without sharestorage- like operations breaking
 */
void agp_resize_vstore(struct storage_info_t* backing, size_t w, size_t h);

/*
 * Deallocate all resources associated with a backing store.
 * Note that this function DO NOT respect the reference counter field,
 * that is the responsibility of the caller. (engine uses vint_* for
 * this purpose).
 */
void agp_drop_vstore(struct storage_info_t* backing);

/*
 * Map multiple backing store devices sequentially across
 * available texture units.
 */
void agp_activate_vstore_multi(struct storage_info_t** backing, size_t n);

/*
 * Prepare the specified backing store for streaming texture
 * uploads. The semantics is determined by the stream_type and meta:
 */
enum stream_type {
	STREAM_RAW,  /* buf will be NULL, call returns NULL (fail) or a pointer to
								*	a buffer to populate manually and then commit */

	STREAM_RAW_DIRECT, /* buf will be an av_pixel buffer that matches the
											*	backing store dimensions */

	STREAM_RAW_DIRECT_SYNCHRONOUS, /* similar to direct but we will block
                                    until the transfer is complete */

	STREAM_HANDLE  /* with buf 0, return a handle that can be passed to
									*	a child or different context that needs to render onwards.
									*	with buf !0, treat it as a handle that can be used by
									*	the graphics layer to access an external data source */
};

struct stream_meta {
	union{
		av_pixel* buf;
		int64_t handle;
	};
};

/*
 * flow: [prepare(RAW, HANDLE)] -> populate returned buffer / handle ->
 * release -> commit.
 *
 * [prepare(RAW_DIRECT, HANDLE_DIRECT)] -> commit.
 *
 * other agp calls are permitted between release -> commit or
 * direct-prepare -> commit but NOT for prepare(non-direct) -> release.
 */
struct stream_meta agp_stream_prepare(struct storage_info_t*,
		struct stream_meta, enum stream_type);
void agp_stream_commit(struct storage_info_t*);
void agp_stream_release(struct storage_info_t*);
/*
 * Synchronize a populated backing store with the underlying
 * graphics layer
 */
void agp_update_vstore(struct storage_info_t*, bool copy);

/*
 * Allocate id and upload / store raw buffer into vstore
 */
void agp_buffer_tostore(struct storage_info_t* dst,
	av_pixel* buf, size_t buf_sz, size_t w, size_t h,
	size_t origw, size_t origh, unsigned short zv
);

enum pipeline_mode {
	PIPELINE_2D,
	PIPELINE_3D
};
void agp_pipeline_hint(enum pipeline_mode);

/*
 * Synchronize the current backing store on-host buffer
 * (i.e. dstore->vinf.text.raw)
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
 * If so, meta.ptr will be !NULL. In that case, the caller
 * is expected to invoke meta.release with tag as argument.
 */
struct asynch_readback_meta agp_poll_readback(struct storage_info_t*);

/*
 * Initiate a new asynchronous readback, if one is already
 * pending, this is a no-operation.
 */
void agp_request_readback(struct storage_info_t*);

/*
 * For clipping and similar operations where we want to
 * prepare a mask ("stencil") buffer, this sequency of operations
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
 * Switch the currently active blending mode, i.e. how
 * new objects shall be drawn in respects to the current
 * color output.
 */
void agp_blendstate(enum arcan_blendfunc);

/*
 * Bind uniforms and draw using the currently active vstore.
 * Txcos, Ident and Model can be NULL and then defaults will be used.
 */
void agp_draw_vobj(float x1, float y1, float x2, float y2,
	float* txcos, float*);

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
 * opaque structure for clustering other video operations,
 * setup_rendertarget allocates and associates a rendertarget
 * with the specified texture backing store (that also
 * defines dimensions etc.) with the preferred use hinted in
 * mode.
 */
struct agp_rendertarget;
struct agp_rendertarget* agp_setup_rendertarget(struct storage_info_t*,
	enum rendertarget_mode mode);

#ifdef AGP_ENABLE_UNPURE
/*
 * Break the opaqueness somewhat by exposing underlying handles,
 * primarily for frameservers that explicitly need to use GL
 * and where we want to re-use the underlying code.
 */
void agp_rendertarget_ids(struct agp_rendertarget*, uintptr_t* tgt,
	uintptr_t* col, uintptr_t* depth);
#endif

/*
 * Drop and rebuild the current backing store, along with
 * possible transfer objects etc. with the >0 dimensions
 * specified by neww / newh.
 */
void agp_resize_rendertarget(struct agp_rendertarget*,
	size_t neww, size_t newh);

/*
 * Switch the currently active rendertarget to the one specified.
 * If set to null, rendertarget based rendering will be disabled.
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

/* opaque field used to store additional implementation
 * defined tags, e.g. VBO backing index etc. */
	uintptr_t opaque;
};

/*
 * submit the specified mesh for rendering,
 * which parts of the mesh that will actually be transmitted and mapped depends
 * on the active shader (which is probed through shader_vattribute_loc
 */
enum agp_mesh_flags {
	MESH_FACING_FRONT   = 1,
	MESH_FACING_BACK    = 2,
	MESH_FACING_BOTH    = 3,
	MESH_FACING_NODEPTH = 4,
	MESH_DEBUG_GEOMETRY = 8
};

/*
 * Some video platforms need to have a more intimate connection
 * with the agp implementation, i.e. distinguish between GLES and OPENGL etc.
 */
const char* agp_ident();

void agp_submit_mesh(struct mesh_storage_t*, enum agp_mesh_flags);

/*
 * mark that the contents of the mesh has changed dynamically
 * and that possible GPU- side cache might need to be updated.
 */
void agp_invalidate_mesh(struct mesh_storage_t*);

/*
 * Get a copy of the current display output and save
 * into the supplied buffer, scale / convert color format
 * if necessary.
 */
void agp_save_output(size_t w, size_t h, av_pixel* dst, size_t dsz);

/* delete, forget and flush all allocated shaders */
void arcan_shader_flush();

/*
 * Drop possible underlying handles, a call chain of
 * unload_all and rebuild_all should yield no visible
 * changes to the rest of the engine.
 */
void arcan_shader_unload_all();

/*
 * Will be called on possible external launch transitions
 * where we might have lost underlying context data.
 */
void arcan_shader_rebuild_all();

/*
 * Set the current transformation / processing rules (i.e. shader)
 * This will be called on new objects and may effectively be a no-o
 * if the same one is already active.
 */
int arcan_shader_activate(arcan_shader_id shid);

/*
 * Take transformation rules in source-code form (platform specific
 * a agp_shader_language) and build for the specified processing
 * stages.
 */
arcan_shader_id arcan_shader_build(const char* tag, const char* geom,
	const char* vert, const char* frag);

/*
 * Drop the specified shader and mark as re-usable (destroy on
 * invalid ID should return false here). States local to shid
 * should be considered undefined after this.
 */
bool arcan_shader_destroy(arcan_shader_id shid);

/*
 * Name- based shader lookup (typically to match string representations
 * from higher-level languages without tracking numerical IDs).
 */
arcan_shader_id arcan_shader_lookup(const char* tag);
const char* arcan_shader_lookuptag(arcan_shader_id id);

/*
 * Get a local copy of the source stored in *vert, *frag based
 * on the specified ID.
 */
bool arcan_shader_lookupprgs(arcan_shader_id id,
	const char** vert, const char** frag);
bool arcan_shader_valid(arcan_shader_id);

/*
 * Get the vertex- attribute location for a specific vertex attribute
 * (as some integral reference or -1 on non-existing in the currently
 * bound program).
 */
int arcan_shader_vattribute_loc(enum shader_vertex_attributes attr);

/*
 * Update the specified built-in environment variable with a slot,
 * value and size matching the tables above, should return -1 if
 * no such- slot exists or is not available in the currently bound
 * program.
 */
int arcan_shader_envv(enum arcan_shader_envts slot, void* value, size_t size);

/*
 * Get a string representation for the specific environment slot,
 * this is primarily for debugging / tracing purposes.
 */
const char* arcan_shader_symtype(enum arcan_shader_envts env);

/*
 * This is used for possibly custom uniforms, with persist set
 * to false we hint that it can be updated regularly and do not
 * have to survive a context-drop/rebuild.
 */
void arcan_shader_forceunif(const char* label,
	enum shdrutype type, void* value, bool persist);

#endif
