-- image_hit
-- @short: Test if the visible region of a specific object covers
-- a specific point in screen space.
-- @inargs: vid, x, y
-- @outargs: true or false
-- @longdescr:
-- @group: image
-- @note: This function works by applying the active transform of the bounding volume
-- and then projects using the currently active output projection and finally
-- performs a point-in-polygon test for the two triangles. This is performed even for
-- simpler cases (e.g. non-hierarchical translations etc.).
-- @cfunction: hittest
-- @related: pick_items
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 0, 255, 0);
	rotate_image(a, 45);
	show_image(a);

	if (image_hit(a, 0, 0) == false and
		image_hit(a, 16, 16) == true) then
		print("OK");
	else
		print("Fail");
	end
#endif
end
