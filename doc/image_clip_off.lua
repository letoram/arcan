-- image_clip_off
-- @short: Disable clipping for the specified object
-- @inargs: vid
-- @outargs:
-- @longdescr:
-- @group: image
-- @note:
-- @cfunction: arcan_lua_clipoff
-- @related: image_clip_on
function main()
#ifdef ERROR1
	image_clip_off(BADID);
#endif
end
