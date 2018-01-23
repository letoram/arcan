-- forward3d_model
-- @short: Push the model along its view vector.
-- @inargs: vid:model, float:factor
-- @inargs: vid:model, float:factor, bool:mask_x=false
-- @inargs: vid:model, float:factor, bool:mask_x, bool:mask_y=false
-- @inargs: vid:model, float:factor, bool:mask_x, bool:mask_y, bool:mask_z+false
-- @inargs: vid:model, float:factor, bool:mask_x, bool:mask_y, bool:mask_z, uint:interp=INTERP_LINEAR
-- @group: 3d
-- @cfunction: forwardmodel
-- @longdescr: This function moves the object further along in the direction it
-- is currently facing by taking the orientation view vector, multiplying it by
-- a factor and adding it to the current position. If any of the optional mask
-- arguments, the specified axis will not be altered.
-- @related: move3d_model, strafe3d_model, step3d_model
function main()
#ifdef MAIN
#endif

#ifdef ERROR
#endif
end
