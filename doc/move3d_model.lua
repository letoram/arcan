-- move3d_model
-- @short: Set new world-space coordinates for the specified model.
-- @inargs: vid:model, float:x, float:y, float:z
-- @inargs: vid:model, float:x, float:y, float:z, uint:time=0
-- @inargs: vid:model, float:x, float:y, float:z, uint:time, uint:interp=INTERP_LINEAR
-- @longdescr: The move3d, rotate3d, scale3d etc. class functions are similar to their
-- 2D counterparts, but takes an additional z coordinate. While these functions are
-- intended for 3D objects, it is possible to apply on 2D objects as well, but with
-- possible side-effects to picking and similar operations.
-- @group: 3d
-- @cfunction: movemodel
-- @related: move3d_model, rotate3d_model, scale3d_model
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	move3d_model(a, 100, 100, -5, 100);
	show_image(a);
#endif
end
