-- image_transform_cycle
-- @short: Toggle transform cycles ON/OFF.
-- @inargs: vid, toggle
-- @outargs:
-- @longdescr: The default behavior for objects with one or several
-- transforms queued is to drop all tracking of a transform state
-- after it has been completed. This function changes that behavior
-- to instead requeue the transform at the end of the chain,
-- looping the animation.
-- @note: Since this makes a lot of the object state variable,
-- this function has a severe impact on the ability to cache previous
-- states and can thus be very expensive.
-- @group: image
-- @cfunction: cycletransform
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	image_transform_cycle(a, 1);
	move_image(a, 100, 100, 100);
	rotate_image(a, 100, 100);
	move_image(a, 10, 10, 100);
	scale_image(a, 64, 64, 25);
	scale_image(a, 32, 32, 25);
#endif
end
