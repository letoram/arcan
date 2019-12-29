/*
 * Copyright 2012-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: 3D support is rather basic and it is not within the scope
 * of the project to expand this to 'crazy modern day levels', though some
 * more culling, picking and rendering-modes would be useful.
 */

#ifndef _HAVE_ARCAN_3DBASE
#define _HAVE_ARCAN_3DBASE

struct arcan_vobject_litem;

/*
 * Process the scene according to the perspective defined in [camtag],
 * starting at [cell] with the interpolation factor of [frag](EPSILON..1.0)
 */
struct arcan_vobject_litem* arcan_3d_refresh(
	arcan_vobj_id camtag, struct arcan_vobject_litem* cell, float frag);

/*
 * Update the rendertarget [tgt] to use the 3D model indicated by
 * [vid] to act as a camtag. This irreversibly converts the type of
 * [vid] to become a 3D camera.
 *
 * [front,back] determine the facing of meshes that will be drawn
 * [near,far,AspectRatio and fov] the properties of the camera
 *
 * this can only be applied on objects that does not have any other
 * extended feature (frameserver, async-img, ..)
 *
 * If [flags] has the MESH_FILL_LINE attribute set, the line-width that
 * will be used when the camera is processing the pipeline is treated as
 * the FIRST va_arg.
 */
arcan_errc arcan_3d_camtag(arcan_vobj_id tgt,
	arcan_vobj_id vid, float near, float far, float ar, float fov, int flags, ...);

/*
 * Replace the projection matrix on a tagged camera
 */
arcan_errc arcan_3d_camproj(arcan_vobj_id vid, float proj[static 16]);

/*
 * Generate a finalized model where the vertices range between [mins,mint]
 * with s mapped to x axis and t mapped to y or z depending on if [vert] is
 * set to [true,t=y] or [false,t=x] while the remaining axis will be set
 * to [base].
 * [wdens] and [ddens] corresponds to the number of subdivisions.
 */
arcan_vobj_id arcan_3d_buildplane(float mins, float mint, float maxs,
	float maxt, float base, float sdens, float tdens, size_t nmaps, bool vert);

/*
 * Generate a finalized model with a specified radius at l divisions along
 * the latitude, and m divisions along the longitude. If [hemi] is set to
 * true, only the upper hemisphere will be generated. The texture coords
 * used will be mercator projection.
 */
arcan_vobj_id arcan_3d_buildsphere(float r,
	unsigned l, unsigned m, bool hemi, size_t nmaps);

/*
 * Generate a finalized model centered at 0, 0 with y range from [halfheight]
 * .. [-halfheight], a radius of [radius] divided into [steps] slices,
 * consuming [nmaps] textures from the frameset. [fill_mode] determins how
 * complete the final geometry should be.
 *
 *
 */
enum a3d_cylinder {
	CYLINDER_FILL_FULL,
	CYLINDER_FILL_HALF,
	CYLINDER_FILL_FULL_CAPS,
	CYLINDER_FILL_HALF_CAPS
};
arcan_vobj_id arcan_3d_buildcylinder(float r,
	float halfh, size_t steps, size_t nmaps, int fill_mode);

/*
 * Generate a finalized model centered at 0,0 with [-width..+width,
 * -height..+height, -depth..+depth] consuming [nmaps] from frameset
 * in returned object, set split to divide inte submeshes.
 */
arcan_vobj_id arcan_3d_buildbox(float width, float height,
	float depth, size_t nmaps, bool split);

/*
 * Generate a finalized model with [count] vertices and a frameset that
 * can cover [nmaps] texture maps. The vertices will initialize be placed
 * pseudorandomly within the [-1..1][x,y,z] volume with texture coordinates
 * matching the position [X-Z] plane.
 *
 * The principal way for distributing the vertices is to attach an image to a
 * frameset slot (one will be allocated) and use that in a vertex shader that
 * determines the actual position of each vertice.
 */
arcan_vobj_id arcan_3d_pointcloud(size_t count, size_t nmaps);

/*
 * Use the transform defined by the camtagged object in [cam] and return
 * true if a ray from [x, y] in the [cam] plane would intersect with the
 * bounding volume contained in [obj]. This is used for simple 'picking'.
 */
bool arcan_3d_obj_bb_intersect(arcan_vobj_id cam,
	arcan_vobj_id obj, int x, int y);

/*
 * Simplified version of arcan_3d_obj_bb_intersect, returns the world-space
 * position in [pos] and it's vector in [ang] using [camtag] for unprojection
 * and x, y for position in the [camtag] near plane.
 */
void arcan_3d_viewray(arcan_vobj_id camtag,
	int x, int y, float fract, vector* pos, vector* ang);


/* Empty model allocates and populates a container, that can be populated with
 * models (addmesh) until it is finalized, which will prompt the generation of
 * bounding volumes. Only finalized models will be drawn in 3d_refresh */
arcan_vobj_id arcan_3d_emptymodel();

/*
 * Mark a model as completed, this is a contract that no-more meshes will be
 * added and that it is safe to calculate values that require the entire model
 * to be available (such as bounding volumes).
 * Repeated calls to this function will be no-ops.
 */
arcan_errc arcan_3d_finalizemodel(arcan_vobj_id);

/*
 * Toggle a flag on or of for if the model should be drawn at 'infinite'
 * distance from the camera (not applying translation) -- used for 'skybox'-
 * like drawing.
 */
arcan_errc arcan_3d_infinitemodel(arcan_vobj_id, bool);

/*
 * Specify the shader [shid] that is to be applied when drawing a submesh
 * in [slot]. This overrides the shader that may be set for the entire [dst].
 */
arcan_errc arcan_3d_meshshader(arcan_vobj_id dst,
	agp_shader_id shid, unsigned slot);

/*
 * [Asynchronous Operation]
 * Add a mesh to an unfinalized model and set it to consume [nmaps]
 * maps from the frameset associated with [dst].
 */
arcan_errc arcan_3d_addmesh(arcan_vobj_id dst,
	data_source resource, unsigned nmaps);

/*
 * Add a trisoup as a mesh to an unfinalized model and set it to
 * consume [nmaps] from the frameset associated with [dst].
 *
 * The model takes over memory control for the pointers it has been
 * passed and are treated as heap-allocated via the arcan_alloc_mem
 * class of functions.
 *
 * [vertices] are mandatory (non-null) with n_vertices > 0 while
 * the other attributes are optional.
 */
arcan_errc arcan_3d_addraw(arcan_vobj_id dst,
	float* vertices, size_t n_vertices,
	unsigned* indices, size_t n_indices,
	float* txcos, float* txcos2,
	float* normals, float* tangents,
	float* colors,
	uint16_t bones[4], float weights[4],
	unsigned nmaps
);

/* [Destructive Transform]
 * Apply the specified roll / pitch / yaw transform to the vertices of [dst]
 */
arcan_errc arcan_3d_baseorient(arcan_vobj_id dst,
	float roll, float pitch, float yaw);

/*
 * [Destructive Transform]
 * Calculate the bounding volume for the specified model and map all
 * vertex values so that they normalize within the -1..1 range for x,y,z
 */
arcan_errc arcan_3d_scalevertices(arcan_vobj_id vid);

/*
 * [Non-Destructive Transform]
 * Re-order the vertices of the model so that the facing is inverted.
 */
arcan_errc arcan_3d_swizzlemodel(arcan_vobj_id model);

#ifdef A3D_PRIVATE
enum arcan_ffunc_rv arcan_ffunc_3dobj FFUNC_HEAD;
#endif

#endif
