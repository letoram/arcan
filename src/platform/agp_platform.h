/*
 * The following functions abstract the graphics operations that arcan_video.c
 * relies on, implementations can be found in platform/agp_.
 */

#ifndef HAVE_AGP_PLATFORM
#define HAVE_AGP_PLATFORM
/*
 * These are just opaque structures used to contain the R/O function pointers
 * that the corresponding agp implementation needs access to. The setup is a
 * bit convoluted as there are some interdependencies between the video
 * platform and the agp platform, particularly in the case with multi-vendor
 * supplied libraries for accelerated functions.
 *
 * Only the video platform implementation should concern itself with these
 * functions, with the 'worst case' being the streaming update of a vstore with
 * multi-GPU affinity.
 */
struct agp_fenv* agp_alloc_fenv(
	void*(lookup)(void* tag, const char* sym, bool req), void* tag);

struct agp_fenv* agp_env();
void agp_setenv(struct agp_fenv*);
void agp_dropenv(struct agp_fenv*);

/*
 * Resets the state machine for the graphics platform to the 'default'.
 * If there's no fenv- allocated or set, one will be setup and initialized.
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
void agp_activate_vstore(struct agp_vstore* backing);

/*
 * Explicitly deactivate vstore, after this state of the specified backing
 * store can be considered undefined.
 */
void agp_deactivate_vstore(void);

/*
 * Drop the underlying ID mapping with a pending call to update_vstore, though
 * the application manually managed reallocation
 */
void agp_null_vstore(struct agp_vstore* backing);

/*
 * Setup an empty vstore backing with the specified dimensions
 */
void agp_empty_vstore(struct agp_vstore* backing, size_t w, size_t h);

/*
 * Setup a sliced vstore (cubemap, 3d- texture, ....),
 * the slices are updated individually and it is not considered 'complete'
 * until it has been updated with agp_slice_synch with a matching number of
 * slices.
 * If [txstate] is set to TXSTATE_CUBEMAP, only valid [n_slices] value is 6.
 */
bool agp_slice_vstore(
	struct agp_vstore* backing, size_t n_slices, size_t base_size, enum txstate);

/*
 * Make sure the backing store is synched acording to its mode and from the set
 * of conformant slices. A conformant slice has the same base_size and is of a
 * texture_2D based source type.
 */
bool agp_slice_synch(
	struct agp_vstore* backing, size_t n_slices, struct agp_vstore** slices);

/*
 * Return an accelerated graphics handle for referring to the final texture
 * within the backing store. This is typically the same as the glid member,
 * but can be set to a proxy and/or reblitting stage to deal with implicit
 * format conversions. Should only have a use within AGP itself.
 */
unsigned agp_resolve_texid(struct agp_vstore* vs);

bool agp_accelerated();

/*
 * Extended form to allow internal platform choice in format used,
 * can be used to some rendertargets for improved performance and for
 * buffer-passing workarounds
 */
enum vstore_hint
{
	VSTORE_HINT_NORMAL = 0,
	VSTORE_HINT_NORMAL_NOALPHA = 1,
	VSTORE_HINT_LODEF = 2,
	VSTORE_HINT_LODEF_NOALPHA = 3,
	VSTORE_HINT_HIDEF = 4,
	VSTORE_HINT_HIDEF_NOALPHA = 5,
	VSTORE_HINT_F16 = 6,
	VSTORE_HINT_F16_NOALPHA = 7,
	VSTORE_HINT_F32 = 8,
	VSTORE_HINT_F32_NOALPHA = 9
};
void agp_empty_vstoreext(struct agp_vstore* backing,
	size_t w, size_t h, enum vstore_hint);

/*
 * Rebuild an existing vstore to handle a change in data source dimensions
 * without sharestorage- like operations breaking
 */
void agp_resize_vstore(struct agp_vstore* backing, size_t w, size_t h);

/*
 * Deallocate all resources associated with a backing store.  Note that this
 * function DO NOT respect the reference counter field, that is the
 * responsibility of the caller. (engine uses vint_* for this purpose).
 */
void agp_drop_vstore(struct agp_vstore* backing);

/*
 * Map multiple backing store devices sequentially across available texture
 * units.
 */
void agp_activate_vstore_multi(struct agp_vstore** backing, size_t n);

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
	STREAM_EXT_RESYNCH,
	STREAM_HANDLE
};

/* This matches the form defined in arcan_shmif_interop.h,
 * While they are packed/unpacked across the barrier - make sure these have
 * the same structure so the prototype in egl_kms_helper.h can be re-used! */
struct agp_buffer_plane {
	int fd;
	int fence;
	size_t w;
	size_t h;

	union {
		struct {
			uint32_t format;
			uint64_t stride;
			uint64_t offset;
			uint32_t mod_hi;
			uint32_t mod_lo;
		} gbm;
	};
};

struct stream_meta {
	union{
		struct {
		av_pixel* buf;
		bool dirty;
		unsigned x1, y1, w, h, stride;
		};
		struct {
			struct agp_buffer_plane planes[4];
			size_t used;
		};
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
 *  - EXT_RESYNCH: vstore- is externally managed in terms of buffers,
 *                and contents have been invalidated (resize)
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
struct stream_meta agp_stream_prepare(struct agp_vstore* store,
	struct stream_meta base, enum stream_type type);

void agp_stream_commit(struct agp_vstore*, struct stream_meta);
void agp_stream_release(struct agp_vstore*, struct stream_meta);

/*
 * Synchronize a populated backing store with the underlying graphics layer.
 * [copy] is used to indicate if the backing contents should be updated,
 *        if set to false, only filtering and similar flags will be synched
 */
void agp_update_vstore(struct agp_vstore*, bool copy);

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
void agp_readback_synchronous(struct agp_vstore* dst);

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
struct asynch_readback_meta agp_poll_readback(struct agp_vstore*);

/*
 * Initiate a new asynchronous readback.
 * if one is already pending, this is a no-operation.
 */
void agp_request_readback(struct agp_vstore*);

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
	RENDERTARGET_COLOR_DEPTH_STENCIL = 4,
	RENDERTARGET_RETAIN_ALPHA = 16,
	RENDERTARGET_MSAA = 32
};

/*
 * opaque structure for clustering other video operations, setup_rendertarget
 * allocates and associates a rendertarget with the specified texture backing
 * store (that also defines dimensions etc.) with the preferred use hinted in
 * mode.
 */
struct agp_rendertarget;
struct agp_fenv;
struct agp_rendertarget* agp_setup_rendertarget(
	struct agp_vstore*, enum rendertarget_mode mode);

/*
 * register an external allocator handler, that, whenever the rendertarget need
 * to be rebuilt, will take it upon itself to populate the agp_vstore. This is
 * mainly used for platforms where a lower layer is responsible for allocating
 * buffers used for scanning out a rendertarget mapped to a display.
 *
 * In the callback, [action] is:
 * 0 : free / deallocate
 * 1 : alloc / setup
 */
enum {
	RTGT_ALLOC_FREE = 0,
	RTGT_ALLOC_SETUP = 1
};
void agp_rendertarget_allocator(struct agp_rendertarget*, bool(*handler)(
	struct agp_rendertarget*, struct agp_vstore*, int action, void* tag),
	void* tag);

/*
 * Break the opaqueness somewhat by exposing underlying handles, primarily for
 * frameservers that explicitly need to use GL and where we want to re-use the
 * underlying code.
 */
void agp_rendertarget_ids(struct agp_rendertarget*,
	uintptr_t* tgt, uintptr_t* col, uintptr_t* depth);

/*
 * Drop and rebuild the current backing store, along with possible transfer
 * objects etc. with the >0 dimensions specified by neww / newh.
 */
void agp_resize_rendertarget(
	struct agp_rendertarget*, size_t neww, size_t newh);

/*
 * Change the coordinate range used for visible viewport and scissor region.
 * This is reset on a call to [agp_resize_rendertarget] to [0,0,w,h]. Also
 * note that the rendertarget >projection< is retained and might need to be
 * adjusted accordingly.
 */
void agp_rendertarget_viewport(struct agp_rendertarget*,
	ssize_t x1, ssize_t y1, ssize_t x2, ssize_t y2);

/*
 * Replace the active vstore that is used as destination for the rendertarget
 * with another one. This will not alter reference counting or deallocate the
 * existing store. The new store need to match the old one in type and size.
 */
bool agp_rendertarget_swapstore(
	struct agp_rendertarget* tgt, struct agp_vstore* vstore);

/*
 * Switch the currently active rendertarget to the one specified.  If set to
 * null, rendertarget based rendering will be disabled.
 */
void agp_activate_rendertarget(struct agp_rendertarget*);
void agp_drop_rendertarget(struct agp_rendertarget*);

/*
 * When processing a rendertarget for rendering, and the result gets mapped
 * to a screen directly, and the rendertarget source isn't used for anything
 * else, we can have a fast-path here where the output gets drawn to the
 * platform screen immediately.
 */
void agp_rendertarget_proxy(struct agp_rendertarget* tgt,
	bool (*proxy_state)(struct agp_rendertarget*, uintptr_t tag), uintptr_t tag);

/*
 * Swap out the color attachment in the rendertarget, and return a graphics
 * library buffer ID for the latest 'rendered-to' buffer as the vstore that
 * has previously been run through the allocator.
 *
 * [swap] is set to false if the frame should be skipped instead of forwarded /
 * scanned out. This can happen following an initial setup, a resize or a
 * non-dirty rendertarget.
 */
struct agp_vstore* agp_rendertarget_swap(struct agp_rendertarget*, bool* swap);

/*
 * Reset the internal extra resources indirectly allocated via a call to
 * agp_rendertarget_swap.
 */
void agp_rendertarget_dropswap(struct agp_rendertarget*);

/*
 * Drop the rendertarget bound resources, and any intermediate back- buffers.
 * The main vstore that was bound to the rendertarget is still alive and needs
 * to be destroyed manually.
 */
void agp_drop_rendertarget(struct agp_rendertarget*);

/*
 * manually mark part of rendertarget as dirty, returns number of invalidations
 * so far. if [dirty] is set to NULL, no changes will be marked, but counter
 * will still be returned.
 */
size_t agp_rendertarget_dirty(
	struct agp_rendertarget* dst, struct agp_region* dirty);

/*
 * Flush the list of dirty regions, and store a copy inside [dst], if provided.
 * The [dst] size can be probed using agp_rendertarget_dirty(src, NULL).
 * This will also set the dirty- counter for the rendertarget to 0.
 */
void agp_rendertarget_dirty_reset(
	struct agp_rendertarget* src, struct agp_region* dst);

/*
 * reset the currently bound rendertarget output buffer
 */
void agp_rendertarget_clear();

/*
 * change the clear color of the rendertarget from the default RGBA(0,0,0,1)
 */
void agp_rendertarget_clearcolor(
	struct agp_rendertarget*, float, float, float, float);

enum agp_mesh_type {
	AGP_MESH_TRISOUP,
	AGP_MESH_POINTCLOUD
};

enum agp_depth_func {
	AGP_DEPTH_LESS = 0,
	AGP_DEPTH_LESSEQUAL = 1,
	AGP_DEPTH_GREATER = 2,
	AGP_DEPTH_GREATEREQUAL = 3,
	AGP_DEPTH_EQUAL = 4,
	AGP_DEPTH_NOTEQUAL = 5,
	AGP_DEPTH_ALWAYS = 6,
	AGP_DETPH_NEVER = 7
};

struct agp_mesh_store
{
/*
 * set of one or more of the vertex attributes come from the same buffer, each
 * attribute will be tested for range against shared_buffer+ shared_buffer_sz
 * when managing memory. If out-of-range, they are treated as a separate
 * allocation.
 */
	uint8_t* shared_buffer;
	size_t shared_buffer_sz;

/*
 * [ VERTEX ATTRIBUTES ]
 * all these correspond to possible vertex attributes, NULL if not available
 */
	float* verts;
	float* txcos;
	float* txcos2;
	float* normals;
	float* colors;
	float* tangents;
	float* bitangents;
	float* weights;
	uint16_t* joints;
	unsigned* indices;

	size_t vertex_size;
	size_t n_vertices;
	size_t n_indices;

	enum agp_mesh_type type;
	enum agp_depth_func depth_func;

/* opaque field used to store additional implementation defined tags,
 * such as VBO backing index etc. */
	uintptr_t opaque;

/* set if the underlying buffers have changed and force a resynch (VBOs) */
	bool dirty;

/* set if the mesh should be processed without a depth buffer active */
	bool nodepth;

/* applied the first time the buffer is used in a draw command if the object
 * is indexed, makes sure that all the indices points to valid vertices */
	bool validated;
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
	MESH_DEBUG_GEOMETRY = 8,
	MESH_FILL_LINE      = 16
};

/*
 * Some video platforms need to have a more intimate connection with the agp
 * implementation, i.e. distinguish between GLES and OPENGL etc.
 */
const char* agp_ident();

void agp_submit_mesh(struct agp_mesh_store*, enum agp_mesh_flags);

/*
 * Mark that the contents of the mesh has changed dynamically and that possible
 * GPU- side cache might need to be updated.
 */
void agp_invalidate_mesh(struct agp_mesh_store*);

/*
 * Free the resources tied to a mesh (buffers + GPU handles)
 */
void agp_drop_mesh(struct agp_mesh_store* s);

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
 * undefined after this. If the shid points to a uniform subgroup rather than
 * the default (GROUP_INDEX(shid) == 0), only that subgroup will be destroyed.
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
 * Copy [x1, y1, x2, y2] regionn from src to dst
 */
void agp_vstore_copyreg(
	struct agp_vstore* restrict src, struct agp_vstore* restrict dst,
	size_t x1, size_t y1, size_t x2, size_t y2
);

/*
 * Update the uniform value of the currently bound shader and uniform group
 */
void agp_shader_forceunif(const char* label, enum shdrutype type, void* value);

struct agp_render_options {
	int line_width;
};
void agp_render_options(struct agp_render_options);

/* Perform an integrity check on the graphics platform */
bool agp_status_ok(const char** msg);

#endif
