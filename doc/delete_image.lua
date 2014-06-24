-- delete_image
-- @short: Delete a VID and all its associated resources.
-- @inargs: VID
-- @outargs:
-- @longdescr: This function deleted as VID, its clones, any attached frameservers
-- and linked images without the MASK_LIVING flag cleared.
-- @note: Trying to delete a non-existing image is considered a fatal error and
-- will immediately terminate the engine. The valid_vid function can be used to
-- determine if a deletion would be considered illegal or not.
-- @note: Trying to delete WORLDID and BADID is also considered a fatal error.
-- @note: Deleting an VID in an asynchronous state will force the asynchronous load
-- operation to complete first.
-- @group: image
-- @related: expire_image
-- @cfunction: arcan_lua_deleteimage
-- @flags:
function main()
#ifdef MAIN
	valid = fill_surface(32, 32, 255, 0, 0, 0);
	delete_image(valid);
#endif

#ifdef ERROR1
	delete_image(WORLDID);
#endif

#ifdef ERROR2
	delete_image();
#endif

#ifdef ERROR3
	delete_image(BADID);
#endif

#ifdef ERROR4
	delete_image(-1);
#endif
end
