-- video_displaygamma
-- @short: get or set the gamma ramps for a display
-- @inargs: dispid, *tbl*
-- @outargs: [tbl or boolean]
-- @longdescr: Some hardware platforms and displays supports hardware accelerated
-- gamma and color correction. This function is used to both test for the
-- availability of such features and to change the currently active values.
-- *dispid* is either 0 for the default display, or provided as a hotplug
-- event in the applname_display_event handler.
-- If the optional *tbl* argument is not set, the gamma tables will be queried,
-- and either returned as a number-indexed table with the individual channels
-- (r, g, b) packed as separated planes (tbl[1] = r, tbl[#tbl/3] = g,
-- tbl[#tbl/3*2] = b) as numbers in the 0.0 to 1.0 range.
-- If the optional *tbl* argument is set, the gamma tables for the display will
-- be updated with new values and the function returns true or false depending
-- on if the device accepted the tables or not. Mismatching tables can be a
-- terminal state transition, so only use tables that come from a previous call
-- to ref:video_displaygamma.
-- @group: vidsys
-- @cfunction: videodispgamma
-- @related:
function main()
#ifdef MAIN
	local tbl = video_displaygamma(0);
	if (tbl and #tbl > 0) then
		for i=1,#tbl/3 do
			tbl[i] = tbl[i] * 0.1;
		end
		video_displaygamma(0, tbl);
	else
		warning("display does not support gamma tables");
	end
#endif

#ifdef ERROR1
	video_displaygamma(0, {1,2,3,4});
#endif
end
