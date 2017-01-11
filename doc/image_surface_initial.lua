-- image_surface_initial
-- @short: Retrieve a table describing the initial storage state for the specified object.
-- @inargs: vid
-- @outargs: proptbl
-- @longdescr: The system distinguishes between transformations that have been applied
-- after an object was created and the initial state of the object. This function retrieves
-- the values associated with this initial state and returns it as a property table.
-- @group: image
-- @cfunction: getimageinitprop
-- @related: image_surface_resolve, image_surface_properties
function main()
#ifdef MAIN
	a = load_image("test.png");
	resize_image(a, 32, 32);
	iprop = image_surface_initial(a);
	cprop = image_surface_properties(a);

	print(string.format("initial_w: %d, inital_h: %d, current_w: %d, current_h: %d",
		iprop.width, iprop.height, cprop.width, cprop.height));
#endif
end
