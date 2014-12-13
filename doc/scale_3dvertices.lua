-- scale_3dvertices
-- @short: Statically scale the vertex values of the specified model.
-- @inargs: objid, dx, dy, dz
-- @longdescr: This function transforms all the vertices assigned to the
-- specified model. This is a harmful transform and may unnecessarily reduce
-- precision if called repeatedly. For temporary transformtions, see scale3d_model.
-- @group: 3d
-- @cfunction: scale3dverts
-- @related: scale3d_model

