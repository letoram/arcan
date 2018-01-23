-- step3d_model
-- @short: Move forwards and sidewards
-- @inargs: vid:model float:fwd, float:side
-- @inargs: vid:model float:fwd, float:side, uint:time=0
-- @inargs: vid:model float:fwd, float:side, uint:time, bool:update=true
-- @inargs: vid:model float:fwd, float:side, uint:time, bool:update, bool:mask_x=false
-- @inargs: vid:model float:fwd, float:side, uint:time, bool:update, bool:mask_x, bool:mask_y=false
-- @inargs: vid:model float:fwd, float:side, uint:time, bool:update, bool:mask_x, bool:mask_y, bool:mask_z=false
-- @inargs: vid:model float:fwd, float:side, uint:time, bool:update, bool:mask_x, bool:mask_y, bool:mask_z, uint:interp=INTERP_LINEAR
-- @outargs: float:x, float:y, float:z
-- @longdescr: This function combines the movement behavior of ref:forward3d_model and
-- ref:strafe3d_model into one in order to better schedule motion sequences and to
-- evaluate the consequences of a transformation without applying them if the optional
-- *update* argument is set to false.
-- @group: 3d
-- @cfunction: stepmodel
-- @related:
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
