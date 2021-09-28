-- video_displaymodes
-- @short: Retrieve (or set) platform-specific output display options.
-- @inargs:
-- @inargs: int:id
-- @inargs: int:id, int:modeid
-- @inargs: int:id, int:modeid, tbl:modeopts
-- @inargs: int:id, int:width, int:height
-- @outargs: modelist or nil or bool
-- @longdescr: Some video platforms allow the user to dynamically change
-- how output is being mapped. This is necessary for multiple- display
-- support and support for changing video configuration and behavior
-- when a user hotplugs a display.
--
-- There are four ways of using this function. If it is called with
-- no arguments, the underlying video platform will be requested to
-- do a rescan of devices and connectors. This can stall graphics for
-- noticable (100ms+) periods of time for some systems, but is necessary
-- where we do not have working hotplug support. It is also an asynchronous
-- process and any results will be propagated as _display_state events.
--
-- Calling this function with a display index will return a table of
-- possible modes.
--
-- Calling this function with a display index and a modeid obtained
-- from a previous table from video_displaymodes will attempt to switch
-- the display to that mode and return success or not as a boolean.
--
-- This can be further hinted by providing a *modeopts* table.
--
-- The valid keys for this table are:
-- *modeopts:number:vrr* for setting the refresh rate target (Hz) or a <= 0 value
-- for letting the platform dynamically decide.
-- *modeopts:int:quality* for setting the mode scanout quality. This overrides
-- the behaviour for WORLDID and directly composited output only. If another
-- rendertarget has been set as the direct output through ref:map_video_display
-- then the properties of the rendertarget store takes precendent. The permitted
-- quality options are the same as for ref:alloc_surface:
-- ALLOC_QUALITY_LOW (typically RGB565), ALLOC_QUALITY_NORMAL (RGB888),
-- ALLOC_QUALITY_HIGH (R10G10B10, "deep"), ALLOC_QUALITY_FLOAT16 (HDR-FP16) or
-- ALLOC_QUALITY_FLOAT32 (HDR-FP32).
--
-- Calling this function on a display that supports dynamic (caller-defined)
-- modes, with a width and a height set will try to force that specific
-- dynamic mode and return success or not as a boolean.
-- @bug: LUA_API_VERSION_MAJOR/MINOR <= 0 11 (arcan < 0.6.1) incorrectly
-- handles the (int, int, tbl) argument form.
-- @note: possible modelist table members are: cardid, displayid,
-- phy_width_mm, phy_height_mm, subpixel_layout, dynamic, primary,
-- modeid, width, height, refresh, depth
-- @group: vidsys
-- @cfunction: videodisplay
-- @example: tests/interactive/scan
-- @related:
function main()
#ifdef MAIN
	local list = video_displaymodes(0);
	if (#list == 0) then
		return shutdown("video platform did not expose any modes.");
	end
	for i,v in ipairs(list) do
		print(string.format("(%d) display(%d:%d)\n\t" ..
			"dimensions(%d * %d) @ %d Hz, depth: %d\n\n",
			v.modeid, v.cardid, v.displayid, v.width,
			v.height, v.refresh, v.depth)
		);
	end

	print("swiching modes\n");
	video_displaymodes(0, list[math.random(#list)].modeid);
	print("modes switched\n");
#endif

#ifdef ERROR
	video_displaymodes("not acceptable");
#endif
end
