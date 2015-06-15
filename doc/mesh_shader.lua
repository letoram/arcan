-- mesh_shader
-- @short: Change the active shader for an individual mesh.
-- @inargs: mesh, shaderslot, *shadergroup*
-- @longdescr: Each 3D-model can have a number of meshes associated with it.
-- Each individual mesh may also have a specific shader attached, although the
-- more common case is to use one shader globally for the entire model due to
-- the cost involved in switching shaders too often.
-- @group: 3d
-- @related: build_shader, image_shader, shader_ugroup, shader_uniform
-- @cfunction: setmeshshader
function main()
#ifdef MAIN
#endif
end
