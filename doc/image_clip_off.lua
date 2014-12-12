-- image_clip_off
-- @short: Disable clipping for the specified object
-- @inargs: vid
-- @outargs:
-- @longdescr:
-- @group: image
-- @note:
-- @cfunction: clipoff
-- @related: image_clip_on
function main()
#ifdef ERROR
	image_clip_off(BADID);
#endif
end
