-- rotate3d_model
-- @short: Set the current rotation for the specified model.
-- @inargs: model, roll, pitch, yaw, *dt*
-- @longdescr: The move3d, rotate3d, scale3d etc. class functions are similar to their
-- 2D counterparts, but takes an additional z coordinate. These could, in fact, be used
-- on normal 2D objects to achieve other effects as well.
-- @group: 3d
-- once for any model.
-- @related: orient3d_model, move3d_model
-- @cfunction: arcan_lua_rotatemodel
function main()
#ifdef MAIN
	camera = null_surface(4, 4, 0, 0, 0);
	view = camtag_model(camera, 0);
	model = build_plane3d(-5.0, -5.0, 5.0, 5.0, -0.4, 1.0, 1.0, 0);
	show_image(model);

	rotate3d_model(model, 45, 45, 45, 100);
#endif
end
