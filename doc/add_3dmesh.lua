-- add_3dmesh
-- @short: Load/build a mesh and attach to a model.
-- @inargs: dstmodel, source, *nmaps*
-- @outargs:
-- @longdescr: This function can be used to setup and attach a
-- mesh to an open model. If *source* is a string, it is treated
-- as a resource that will be passed through an internal model
-- loader (CTM format as of now).
--
-- If *source* is a table, the following fields are expected:
-- .vertices (indexed table) {x1, y1, z1, x2, y2, z2, ...}
--
-- If the 'indices' field is provided, the number of triangles
-- becomes #indices/3, otherwise the vertices field will be used
-- directly.
--
-- The optional field 'txcos' is used to define per vertex
-- texture coordinates and should thus match #txcos*nmaps/2 or
-- #txcos/2 for sharing the same set across all maps.
--
-- The optional field 'normals' is used to provide per vertex
-- normals and should thus match #vertices and have matching
-- relative table position.
--
-- The optional *nmaps* (default: 1) is used to specify how many
-- texture slots that should be assigned to the mesh, and there
-- should either be one set of texture coordinates for the entire
-- mesh or an amount that matches the number of desired slots.
--
-- Slots are consumed from the global amount of slots in the
-- frameset attached to *dstmodel*. A correct model thus has
-- model(framesetsize) = mesh(0).nmaps + ... + mesh(n).nmaps
-- and will be divided based on the order the individual meshes
-- were added to the model.
-- @group: 3d
-- @note: Nmaps is hard- limited to 8, matching the minimum
-- of texture units according to the GLES2.0 standard.
-- @note: This function is currently only intended for static
-- meshes. It does not provide more advanced features like
-- interrelations/bones/skinning or streaming updates, though
-- it is likely that the format will be extended to accomodate
-- that in time.
-- @cfunction: loadmesh
-- @related: new_3dmodel, finalize_3dmodel, swizzle_model,
-- camtag_model, attrtag_model, scale_3dvertices
function main()
#ifdef MAIN
	vid = new_3dmodel();
	add_3dmesh(vid, "testmesh1.ctm", 1);
	finalize_model(vid);
	show_image(vid);
#endif

#ifdef ERROR
	vid = fill_surface(32, 32, 255, 0, 0, 0);
	add_3dmesh(vid, "testmesh1.ctm");
#endif

#ifdef ERROR2
	vid = new_3dmodel();
	add_3dmesh(vid, "testmesh1.ctm", -1);
#endif

#ifdef ERROR3
	vid = new_3dmodel();
	add_3dmesh(vid, "testmesh1.ctm", 10000000);
#endif

#ifdef ERROR4
	vid = new_3dmodel();
	add_3dmesh(vid, nil, "test");
#endif

#ifdef ERROR5
	vid = new_3dmodel();
	while(true) do
		add_3dmesh(vid, "testmesh1.ctm", 8);
	end
#endif
end

