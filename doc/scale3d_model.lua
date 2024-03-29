-- scale3d_model
-- @short: Apply or schedule a scale transform on a 3D model
-- @inargs: vid:model, float:sx, float:sy, float:sz
-- @inargs: vid:model, float:sx, float:sy, float:sz, uint:time=0
-- @inargs: vid:model, float:sx, float:sy, float:sz, uint:time, uint:interp=INTERP_LINEAR
-- @longdescr: This function will scale the model in all three axes by the specified
-- factor relative to its initial scale state of 1,1,1.
-- If the optional *time* argument is set, the transform will be appended to the
-- end of the scale transform queue, otherwise it will be cleared and the transform
-- is applied immediately.
-- @group: 3d
-- @cfunction: scalemodel
-- @related: move3d_model, forward3d_model, step3d_model, strafe3d_model

