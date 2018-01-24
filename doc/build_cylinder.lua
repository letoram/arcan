-- build_cylinder
-- @short: Generate a full or half cylinder model
-- @inargs: float:radius, float:halfh, uint:steps
-- @inargs: float:radius, float:halfh, uint:steps, uint:nmaps=1
-- @inargs: float:radius, float:halfh, uint:steps, uint:nmaps=1, str:opts=""
-- @outargs: vid
-- @longdescr: This builds a mesh and binds to a new finalised 3d model.
-- The typical use is for debug geometry, skydrawing and for representing
-- panoramic pictures and video sources.
-- The mesh range in the y axis will range from -halfh..halfh. The optional
-- *opts* argument specifies additional constraints, e.g. "caps" for
-- adding endcaps, "half" for generating an open sliced half of a cylinder,
-- or "halfcaps" for generating a closed sliced half of a cylinder.
-- @group: 3d
-- @cfunction: buildsphere
-- @related: build_3dplane, build_pointcloud, build_3dbox
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
