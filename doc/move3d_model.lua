-- move3d_model
-- @short: Set new world-space coordinates for the specified model.
-- @inargs: modelvid, x, y, z, *time*
-- @longdescr: The move3d, rotate3d, scale3d etc. class functions are similar to their
-- 2D counterparts, but takes an additional z coordinate. These could, in fact, be used
-- on normal 2D objects to achieve other effects as well.
-- @group: 3d
-- @cfunction: arcan_lua_movemodel
-- @related: move3d_model, rotate3d_model, scale3d_model
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	move3d_model(a, 100, 100, -5, 100);
	show_image(a);
#endif
end
