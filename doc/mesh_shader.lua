-- mesh_shader
-- @short: Change the active shader for a submesh of a model
-- @inargs: mesh, shid, slot
-- @longdescr: Each 3D-model can have a number of meshes (grouped primitives)
-- associated with it. Each such mesh can also have a custom set of processing
-- instructions ("shader"). This function is used to associate a prebuilt
-- shader with an individual mesh slot of a 3D model.
-- @group: 3d
-- @related: build_shader, image_shader, shader_ugroup, shader_uniform
-- @cfunction: setmeshshader
function main()
#ifdef MAIN
#endif
end
