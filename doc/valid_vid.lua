-- valid_vid
-- @short: Check if vid matches a valid object or not, also accepts NULL/BADID arguments.
-- @inargs: *vid*, *type*
-- @outargs: true or false
-- @longdescr: Due to the design decision to use a numerical type to reference
-- the internal engine type most visible entities, a number of situations arise where
-- one might need to test if a specific numeric value maps to a corresponding engine
-- object before calling some functions that require a valid VID or even a valid VID
-- that is also connected to a frameserver or other secondary processing types.
-- @note: Possible values for *type* are TYPE_FRAMESERVER and TYPE_3DOBJECT.
-- requirement
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
