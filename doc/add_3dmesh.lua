-- add_3dmesh
-- @short: Load/build a mesh and attach to a model.
-- @inargs: vid:dstmodel, str/tbl:source
-- @inargs: vid:dstmodel, str/tbl:source, int:nmaps
-- @outargs: int:meshindex
-- @longdescr: This function can be used to setup and attach a mesh to an open
-- model. If *source* is a string, it is treated as a resource that will be
-- passed through an internal model loader. Right now, this method of model
-- loading is disabled and will always fail soft. The reason for that is that
-- the parsing stage needs to move out of the main engine into the decode
-- frameserver for safety and security. This is a temporary measure. The
-- intermediate workaround for the time being is to use the table structure
-- along with a mesh to .lua or mesh to .json along with the builtin/json.lua
-- parser.
--
-- If *source* is a table, the following fields are expected:
-- .vertices (indexed table) {x1, y1, z1, x2, y2, z2, ...}
--
-- If the 'indices' field is provided, the number of triangles
-- becomes #indices/3, otherwise the vertices field will be used
-- directly.
--
-- If the 'txcos' field is provided, it is used to add an additional
-- set of texture coordinates. It is expected to be #vertices/3*2 in size.
--
-- If the 'txcos_2' field is provided, it is used to add an addition
-- set of texture coordinates. It is expected to be #vertices/3*2 in size.
--
-- If the 'normals' field is provided, it is used to define per-vertex
-- normals, and should match #vertices. It is expected to match #vertices.
--
-- If the 'colors' field is provided, it is used to define per-vertex
-- colors, and should match #vertices/3*4.
--
-- If the 'tangent' field is provided, it is used to define the
-- tangent space to use, and the bitangents will be generated automatically.
-- It should match #vertices/3*4.
--
-- If the 'joints' field is provided, it is expected to be #vertices/3*4
-- uints that refer to a bone matrix uniform.
--
-- If the 'weights' field is provided, it is expected to be #vertices/3*4
-- floats that weigh the different joint indices together.
--
-- If the *nmaps* argument is provided (default:1), it is used specify how many
-- texture slots that should be assigned to the mesh, and there should either
-- be one set of texture coordinates for the entire mesh or an amount that
-- matches the number of desired slots.
--
-- Slots are consumed from the global amount of slots in the frameset attached
-- to *dstmodel*. A correct model thus has model(framesetsize) = mesh(0).nmaps
-- + ... + mesh(n).nmaps and will be divided based on the order the individual
-- meshes were added to the model.
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

