-- rendertarget_vids
-- @short: Get an indexed table of vids in a rendertarget
-- @inargs: *rtvid*
-- @outargs: tbl
-- @longdescr: This function populates a list of VIDs that match the
-- contents of a specific rendertarget at the time of calling. It can
-- be used to perform certain mass-actions without manually maintaing
-- a list of vids collected at allocation time.
-- If *rtvid* is not specified, the current default attachment will be used.
-- @group: targetcontrol
-- @cfunction: rendertarget_vids
-- @related:
function main()
	local a = color_surface(8, 8, 255, 0, 0);
	local b = color_surface(4, 4, 0, 255, 0);
#ifdef MAIN
	for i,v in ipairs(rendertarget_vids()) do
		show_image(v);
		print(a, b, v);
	end
#endif

#ifdef ERROR1
	for i,v in ipairs(a) do
		print("will die before this");
	end
#endif
end
