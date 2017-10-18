-- center_image
-- @short: move a video object relative to an external reference object
-- @inargs: vid:src, vid:ref
-- @inargs: vid:src, vid:ref, int:anchor
-- @inargs: vid:src, vid:ref, int:anchor, int x_ofs
-- @inargs: vid:src, vid:ref, int:anchor, int x_ofs, y_ofs
-- @longdescr: This positions the center of *src* relative to the
-- center anchor point on *ref*. The anchor point can be changed by
-- specifying the *anchor* object to one of:
-- ANCHOR_UL : upper-left, ANCHOR_CR : upper-center, ANCHOR_UR : upper-right,
-- ANCHOR_CL : center-left, ANCHOR_C : center, ANCHOR_CR : center-right,
-- ANCHOR_LL : lower-left, ANCHOR-LC : lower-center, ANCHOR_LR : lower-right.
-- The final position can also be shifted by specifying *x_ofs* (px) and
-- *y_ofs*. This is a one-time alignment and resolves *src* and *ref* into
-- world-space when calculating the final coordinates. For automatic response
-- to changes in *ref*, use the ref:link_image function.
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
