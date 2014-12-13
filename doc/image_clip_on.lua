-- image_clip_on
-- @short: Enable clipping for object.
-- @inargs: vid, *clipmode
-- @outargs:
-- @longdescr: Enable clipping for object. This is only effective for objects
-- that have been linked to eachother, through instancing or calls to link_image.
-- The optional *clipmode* argument, (CLIP_ON, CLIP_OFF, CLIP_SHALLOW) determines
-- how the clipping region will be determined. With normal, CLIP_ON, mode, the
-- clipping hierarchy resolves to the firstmost object in the parent chain with
-- clipping disabled. With CLIP_SHALLOW, the region of the parent will be used
-- for clipping regardless of other states.
-- @group: image
-- @cfunction: clipon
-- @related: image_clip_off
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	b = fill_surface(64, 64, 0, 255, 0);
	link_image(b, a);
	move_image(b, 32, 32);
	show_image({a,b});
	image_clip_on(b, CLIP_SHALLOW);
#endif
#ifdef ERROR
	image_clip_on(BADID);
#endif
end
