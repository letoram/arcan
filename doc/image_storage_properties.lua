-- image_storage_properties
-- @short: Retrieve a table describing the current storage state for the specified object. 
-- @inargs: vid
-- @outargs: proptbl 
-- @longdescr: An object has a number of different properties that affect memory consumption
-- and video rendering. Storage properties has the fields 'width' and 'height' that refer 
-- to the internal storage format of the object, as this may be padded to fit a POT restriction,
-- meaning that width and height needs to have a valid power of two value.
-- @group: image 
-- @cfunction: arcan_lua_getimagestorageprop
-- @related: image_surface_properties, image_surface_initial_properties,
-- image_surface_resolve_properties
function main()
#define MAIN
	a = fill_surface(64, 64, 255, 0, 0, 33, 33);
	b = image_storage_properties(a);
	print(b.width, b.height);
#endif
end
