-- step3d_model
-- @short: Move forwards and sidewards
-- @inargs: float:fwd, float:side
-- @inargs: float:fwd, float:side, uint:time=0
-- @inargs: float:fwd, float:side, uint:time=0, bool:update=true
-- @inargs: float:fwd, float:side, uint:time=0, bool:update, bool:mask_x=false
-- @inargs: float:fwd, float:side, uint:time=0, bool:update, bool:mask_x, bool:mask_y=false
-- @inargs: float:fwd, float:side, uint:time=0, bool:update, bool:mask_x, bool:mask_y, bool:mask_z=false
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
