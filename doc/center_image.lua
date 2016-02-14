-- center_image
-- @short: move a video object relative to an external reference object
-- @inargs: srcvid, refvid, *anchorp*
-- @outargs:
-- @longdescr: This positions the center of *srcvid* relative to an
-- anchor point on *refvid* (default to center, other options are
-- ANCHOR_ UL, UR, LL, LR) taking relative coordinate systems into
-- account.
-- @group: image
-- @cfunction: centerimage
-- @related: link_image
function main()
	local a = fill_surface(64, 32, 255, 0, 0);
	local b = fill_surface(127, 127, 0, 255, 0);
	show_image({a, b});
#ifdef MAIN
	center_image(a, b);
#endif

#ifdef ERROR1
	center_image(a, b, 919191);
#endif
end
