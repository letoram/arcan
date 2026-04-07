-- image_surface_properties
-- @short: Retrieve the current properties of the specified object.
-- @inargs: vid, *dt
-- @outargs: proptbl
-- @longdescr: There are a number of attributes tracked for each object. Those that directly influence rendering and are modifiable through transformations (move, rotate, scale, ...) may vary with time. This function can be used to retrieve either the current state of such attributes, or resolve what the state would be at a future point in time (by providing the *dt* argument).
-- @note: The fields used in proptbl are: (x, y, z, rotation, roll, pitch, yaw,
-- opa, zv, scalex and scaley).
-- @note: The values retrieved are expressed in local (object) coordinate space.
-- @note: For frameserver-backed objects that use tpack rendering, the surface
-- dimensions reported here reflect the raw backing store, not the logical cell
-- grid. To obtain the cell grid metrics (cellw, cellh, density, ppcm), use the
-- table returned by ref:target_displayhint instead. The opa field in proptbl
-- corresponds to the current blend state, which may differ from the value set
-- via ref:blend_image if the opacity has been clamped (see blend_image notes
-- on NaN handling).
-- @group: image
-- @cfunction: getimageprop
-- @related: image_surface_initial_properties, image_surface_resolve_properties,
-- image_surface_storage_properties
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	show_image(a);
	move_image(a, 100, 100, 100);
	cprops = image_surface_properties(a);
	fprops = image_surface_properties(a, 50);

	print(string.format("now(x,y): %d, %d -- later(x,y): %d, %d",
		cprops.x, cprops.y, fprops.x, fprops.y));

	print(string.format("scale: %f, %f", cprops.scalex, cprops.scaley));
#endif
end
