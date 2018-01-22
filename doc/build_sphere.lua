-- build_sphere
-- @short: Generate a 3D sphere or hemisphere model
-- @inargs: float:radius, uint:div_long, uint:div_lat
-- @inargs: float:radius, uint:div_long, uint:div_lat, uint:nmaps=1
-- @inargs: float:radius, uint:div_long, uint:div_lat, uint:nmaps=1, bool:hemi=false
-- @outargs: vid
-- @longdescr: This builds a mesh and binds to a new finalised 3d model.
-- The typical use is for debug geometry and skydomes. The mesh values
-- will range from +radius..radius along the longitude and latitude or
-- +radius..0 along the longitude if the *hemi* argument is set to true.
-- @group: 3d
-- @cfunction: buildsphere
-- @related: build_3dplane, build_pointcloud, build_3dbox
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
