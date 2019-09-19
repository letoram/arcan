-- image_storage_properties
-- @short: Retrieve a table describing the current storage state for the specified object.
-- @inargs: vid:src
-- @outargs: proptbl
-- @longdescr:
-- This function is used to retrieve the image state with the same fields as
-- ref:image_surface_resolve, but dimensions will be that of the backing store
-- rather than the current presentation size. The extended fields 'type' and
-- 'refcount' are also provided.
-- @group: image
-- @cfunction: getimagestorageprop
-- @related: image_surface_properties, image_surface_initial_properties,
-- image_surface_resolve_properties
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0, 33, 33);
	b = image_storage_properties(a);
	print(b.width, b.height);
#endif
end
