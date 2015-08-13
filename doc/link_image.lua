-- link_image
-- @short: Change some properties to be automatically relative to another object.
-- @inargs: src, newparent, *anchor*
-- @longdescr: By default, all objects defines their properties relative to
-- WORLDID, but this association can be reassigned by calling *link_image* for
-- full video objects.  A full video object is one that do is not a clone
-- (instance) and have not been marked as persistant. The default properties
-- that are turned relatrive in this way are *opacity*, *position*,
-- *orientation*, though these can be controlled with mask functions such as
-- ref:image_mask_set. *src* refers to the object that should be reassigned and
-- *newparent* refers to the object that the assignment would be changed to.
-- This also applies to life tracking, delete or expire *newparent* and this
-- will cascade to any associated objects. Both *src* and *newparent* must be
-- full video objects.  The optional *anchor* properties can be one of the
-- following values: ANCHOR_UL, ANCHOR_UR, ANCHOR_LL, ANCHOR_LR, ANCHOR_C and
-- refers to the anchor point, meaning that if the *newparent* would change
-- size, the position of *src* will be shifted in to reflect this based on the
-- anchor point. The default anchor point is ANCHOR_UL.
-- @warning: Changing link ownership resets all scheduled transformations
-- except for blending.
-- @note: Rotation/Orientation do not apply to the anchor point.
-- @note: Link to self is equivalent to linking back to WORLDID.
-- @group: image
-- @cfunction: linkimage
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	b = fill_surface(32, 32, 0, 255, 0);
	link_image(b, a);
	show_image(b);
	blend_image(a, 1.0, 50);
	move_image(a, VRESW, VRESH, 100);
	rotate_image(a, 100, 100);
	expire_image(a, 100);
#endif
end
