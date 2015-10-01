-- image_matchstorage
-- @short: test if two vids share the same underlying storage
-- @inargs: v1, v2
-- @outargs: true or false
-- @longdescr: This function can be used to determine if two
-- vids share the same underlying backing store. This can be helpful
-- in cases where one might need transition based on visual properties
-- that are inherent to the backing store, as there are no strong equality
-- tests for regular vids as they are all treated as unique.
-- @group: image
-- @cfunction: matchstorage
-- @related:
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 0, 255, 0);
	c = fill_surface(32, 32, 255, 0, 0);
	b = null_surface(32, 32);
	image_sharestorage(a, b);
	assert(image_matchstorage(a, b) == true);
	assert(image_matchstorage(a, c) == false);
	image_sharestorage(a, c);
	assert(image_matchstorage(a, c) == true);
#endif

#ifdef ERROR1
#endif
end
