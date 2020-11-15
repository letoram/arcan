-- new_3dmodel
-- @short: Allocate a VID and 3D Model container.
-- @outargs: modelvid
-- @longdescr: Just like regular VIDs, 3D models start out in a hidden (opacity < EPSILON) state. Even if set to visible, no draw calls will be issues until the model has been populated with meshes. These will be drawed in insertion order. Note that vertices may be rescaled to 0..1 * factor using scale_3dvertices and that call takes the entire chain of meshes into consideration.
-- @note: If a model isn't at all visible, try setting a single color shader for troubleshooting, then check video_3dorder to make sure that 2D elements aren't occluding it. A camera must also have been activated through the camtag_ class of functions.
-- @note: By default, individual meshes doesn't have a full state akin to a complete VID and the only attribute that can really be assigned (at quite some cost) to individual meshes are the active shader.
-- @note: Order of traversed 3D objects depend on the active camera and may not necessarily follow the regular order_image class of functions.
-- @group: 3d
-- @cfunction: buildmodel
-- @related: add_3dmesh
function main()
#ifdef MAIN
	vid = new_3dmodel();
	show_image(vid);
	add_3dmesh(vid, "testmesh1.ctm");
#endif
end
