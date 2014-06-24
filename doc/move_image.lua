-- move_image
-- @short: Set new world-space coordinates for the specified video object.
-- @inargs: vid, newx, newy, *time*
-- @longdescr: All move/scale/rotate transforms can be animated by specifying a relative deadline. These can be both queued and combined, letting the engine to interpolate (linearly by default) allowing for inexpensive yet smooth transitions and animations.
-- @group: image
-- @cfunction: arcan_lua_moveimage
-- @related: rotate_image, scale_image, nudge_image, resize_image
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	show_image(a);
	move_image(a, VRESW, VRESH, 200);
	move_image(a,     0,     0, 100);
#endif
end
