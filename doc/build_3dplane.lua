-- build_3dplane
-- @short: Allocate a new 3d model, generate a flat plane mesh and attach it to the model.
-- @inargs: min_width, min_depth, max_width, max_depth, yvalue, width_density, depth_density, *nmaps
-- @outargs: VID or BADID
-- @longdescr: Several 3D effects, e.g. clouds from a ground perspective, terrain or a water surface can be built using a simple plane, with optional curvature or displacement added at another stage. This function serves as such a basis, but will only yield a tesselated mesh, with normals and textures to be filled out in the vertex shader stage.
-- @note: As the case with the other functions in the 3D group, refer to 'modeldemo' for a more comprehensive example.
-- @note: Members of the 3D group are not as tightly governed as other groups are and should be disabled in a security- and resource- conscious build.
-- @group: 3d
-- @cfunction: arcan_lua_buildplane
-- @flags:
function main()
#ifdef MAIN
#endif
end