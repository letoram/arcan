-- instant_image_transform
-- @short: Immediately perform all pending transformations.
-- @inargs: vid
-- @group: image
-- @cfunction: arcan_lua_instanttransform
-- @related: copy_image_transform,
-- image_transform_cycle, reset_image_transform, transfer_image_transform
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	show_image(a);
	move_image(a, 50, 50, 100);
	instant_image_transform(a);
	props = image_surface_properties(a);
	print(props.x, props.y);
#endif
end
