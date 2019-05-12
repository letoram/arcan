-- image_surface_resolve
-- @short: Retrieve current image properties in world-space.
-- @inargs: vid
-- @outargs: proptbl
-- @longdescr: Most of the surface_ class of functions return
-- results in object space. This function will traverse the related set
-- of object hierarchies and resolve the world-space ones that will be
-- used when compositing the output.
-- @group: image
-- @note: The fields used in proptbl are: (x, y, z, width, height,
-- depth, angle, roll, pitch, yaw, opacity and order).
-- @note: this function has a highly variable cost since the rendering
-- pipeline normallys caches both resolved properties and resulting
-- transformation matrices, if possible.
-- @cfunction: getimageresolveprop
-- @related: image_surface_initial_properties, image_surface_properties,
-- image_surface_storage_properties
-- @flags:
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	b = fill_surface(64, 64, 0, 255, 0);
	link_image(b, a);
	move_image(a, 100, 100);
	move_image(b, 50, 50);
	props = image_surface_resolve(b);
	print(string.format("%d %d", props.x, props.y));
#endif
end
