-- video_displaydescr
-- @short: retrieve a byte block and a hash for identifying a specific display
-- @inargs: dispid
-- @outargs: block, hash
-- @longdescr: For dealing with multiple-monitors where one might need to track
-- settings, calibration and other monitor individual properties , some kind of
-- identity token is needed. This function returns the platform identity one,
-- which for most cases should be an EDID formatted binary blob, along with a
-- hash value of the contents of the block for when user-readable names are
-- not needed.
-- @group: vidsys
-- @cfunction: videodispdescr
-- @related:
function main()
#ifdef MAIN
	warning( video_displaydescr(0) );
#endif

#ifdef ERROR1
	warning( video_displaydescr() );
#endif
end
