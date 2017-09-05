/*
 * Copyright 2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * Launch the binary specified through arcan_db_kv(arcan, ext_vr) with an
 * inherited extended frameserver context using the protocol header defined in
 * shmif/vr_platform.h and the [bridge_arg] being the packed argstr to expose
 * through ARCAN_ARG.
 *
 * The event-context provided in [evctx] will be used to send appear/ disappear
 * events which covers the _vid mapping of the associated null_surface device
 * that will have its object- space position and orientation mapped and
 * continously updated prior to rendering and to ticks.
 *
 * The [tag] provided will be added to relevant events, primarily for VM
 * mapping (Lua, ...)
 */
struct arcan_vr_ctx;
struct arcan_vr_ctx* arcan_vr_setup(
	const char* bridge_arg, struct arcan_evctx* evctx, uintptr_t tag);

enum arcan_ffunc_rv arcan_vr_ffunc FFUNC_HEAD;

/*
 * Try and force- reset the devices bound to the platform controller.
 */
arcan_errc arcan_vr_reset(struct arcan_vr_ctx*);

/*
 * Take two rendertarget outputs and associate a camera with each of them,
 * using the parameters provided. They will be linked with the correct fov,
 * ipd and other parameters. The contents of each rendertarget will not have
 * any distortion applied yet, that is done in the final compositioning stage
 * by either setting up a distortion shader or using a provided distortion
 * mesh.
 */
arcan_errc arcan_vr_camtag(struct arcan_vr_ctx*,
	arcan_vobj_id left, arcan_vobj_id right);

/*
 * Used when breaking the association between a limb in a VR context and
 * a 3D model as the model has been destroyed. Only reasonable to call from
 * the destructor of a 3d model.
 */
arcan_errc arcan_vr_release(struct arcan_vr_ctx*, arcan_vobj_id ind);

/*
 * Associate a model-carrying VID with a limb index. The limb must have been
 * announced in respect to a plug/unplug action. If the limb disappears from
 * the provider, the mapping will be released. If the model is destroyed, the
 * limb index will be freed. If there already is a mapping on the limb, the
 * previous one will be removed first. If model refers to an invalid id, the
 * association will still be dropped.
 */
arcan_errc arcan_vr_maplimb(
	struct arcan_vr_ctx*, unsigned ind, arcan_vobj_id model);

/*
 * Retrieve (if possible) two distortion meshes to use for texturing
 * the camtagged rendertargets. The output data is formatted planar:
 * plane-1[x, y, z] plane-2[s, t] with n_elems in each plane.
 */
arcan_errc arcan_vr_distortion(struct arcan_vr_ctx*,
	float* out_left, float* l_elems, uint8_t* out_right, size_t* r_elems);

/*
 * Retrieve the values used for representing the display and
 * lens parameters and store in [dst]
 */
struct vr_meta;
arcan_errc arcan_vr_displaydata(
	struct arcan_vr_ctx*, struct vr_meta* dst);

/*
 * Clean/ free the contents of the vr- context and associated
 * processes. This will not explicitly delete the null_surfaces,
 * these will continue to live in vid- space.
 */
arcan_errc arcan_vr_shutdown(struct arcan_vr_ctx*);
