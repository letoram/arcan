-- delete_image
-- @short: Delete a video object and associated resources.
-- @inargs: vid
-- @outargs:
-- @longdescr: This function deletes vid, any attached frameservers
-- and linked images without the MASK_LIVING flag cleared.
-- @note: Trying to delete a non-existing image is considered a terminal state
-- transition. The valid_vid function can be used as a last resort to
-- to determine if a number maps to a valid vid or not, but is in many cases
-- a sign of bad design.
-- @note: In a LWA build, deleting WORLDID is a terminal state object. On
-- other platforms it results in the default rendertarget being dropped.
-- This can be used to save memory in some cases where rendering goes
-- strictly through manually defined rendertargets.
-- @note: If the underlying object is in an asynchronous load state,
-- the load operation will be completed first.
-- @group: image
-- @related: expire_image
-- @cfunction: deleteimage
-- @flags:
function main()
#ifdef MAIN
	valid = fill_surface(32, 32, 255, 0, 0, 0);
	delete_image(valid);
#endif

#ifdef ERROR
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
