-- add_3dmesh
-- @short: Load a mesh and attach to a model.
-- @inargs: dstmodel, resource, *nmaps
-- @outargs:
-- @longdescr: Load and decompress a mesh from the specified resource (CTM format) and attach to the model in question. The optional (default 1) nmaps argument specifies how many frameset objects that should be consumed and spent on the different texture units (additional specular, normal etc. maps).
-- @group: 3d
-- @note: Nmaps is hard- limited to 8, matching the minimum of texture units according to the GLES2.0 standard.
-- @cfunction: loadmesh
-- @related: new_3dmodel
-- @note: The example below is somewhat limited, refer to 'modeldemo' for a more comprehensive example.
function main()
#ifdef MAIN
	vid = new_3dmodel();
	add_3dmesh(vid, "testmesh1.ctm", 1);
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

