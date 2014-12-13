-- valid_vid
-- @short: Check if vid matches a valid object or not, also accepts NULL/BADID arguments.
-- @inargs: *vid*
-- @outargs: validbool
-- @group: vidsys
-- @cfunction: validvid
-- @flags:
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0, 0);
	print(valid_vid(a));
	print(valid_vid(NULL));
	print(valid_vid(BADID));
#endif
end
