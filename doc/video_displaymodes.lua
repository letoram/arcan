-- video_displaymodes
-- @short: Retrieve (or set) platform-specific output display options.
-- @inargs: *moderef*, *overw*, *overh*
-- @outargs: modelist
-- @longdescr: Some video platforms allow the user to dynamically change
-- how output is being mapped. This is necessary for multiple- display
-- support and support for changing video configuration and behavior
-- when a user hotplugs a display. Calling this function will return
-- a list of modes (tables). Using a moderef field from such a table
-- as the *moderef* argument will request that the video platform
-- reconfigure device output to comply.
-- @note: possible modelist table members are: cardid, displayid,
-- phy_width_mm, phy_height_mm, subpixel_layout, dynamic, primary,
-- moderef, width, height, refresh, depth
-- @group: vidsys
-- @cfunction: videodisplay
-- @related:
function main()
#ifdef MAIN
	local list = video_displaymodes();
	if (#list == 0) then
		return shutdown("video platform did not expose any modes.");
	end
	for i,v in ipairs(list) do
		print(string.format("(%d) display(%d:%d)\n\t" ..
			"dimensions(%d * %d) @ %d Hz, depth: %d\n\n",
			v.moderef, v.cardid, v.displayid, v.width,
			v.height, v.refresh, v.depth)
		);
	end

	print("swiching modes\n");
	video_displaymodes(math.random(#list));
	print("modes switched\n");
#endif

#ifdef ERROR
	video_displaymodes("no sirree!");
#endif
end
