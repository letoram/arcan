-- link_image
-- @short: Reassign the property-space to be relative another object
-- @inargs: vid:id, vid:newparent
-- @inargs: vid:id, vid:newparent, int:panchor
-- @inargs: vid:id, vid:newparent, int:panchor, int:anchor_opt
-- @longdescr: By default, all objects defines their properties relative to
-- an invisible WORLDID object. By the use of this function, this object can
-- be switched to another dynamically, allowing you to build complex
-- hierarchies.
--
-- The default properties that are relative to another object in this way
-- are opacity, position, orientation and lifetime, though this set can be
-- changed with the use of ref:image_mask_set, ref:image_mask_clear,
-- ref:image_mask_clearall, ref:image_mask_toggle
--
-- The *vid* argument refers to the object that shall be reassigned, and
-- the *newparent* arguments specified the object that it should be made
-- relative to.
--
-- If the *panchor* argument is specified, it defines the positional
-- anchoring space based on one of the following values:
--
-- ANCHOR_UL : upper-left, ANCHOR_CR : upper-center, ANCHOR_UR : upper-right,
-- ANCHOR_CL : center-left, ANCHOR_C : center, ANCHOR_CR : center-right,
-- ANCHOR_LL : lower-left, ANCHOR_LC : lower-center, ANCHOR_LR : lower-right.
--
-- If the *anchor_opt* argument is specified, further anchor behavior can
-- be controlled. The valid values for anchor_opt now are:
-- ANCHOR_SCALE_NONE (default),
-- ANCHOR_SCALE_W, ANCHOR_SCALE_H, ANCHOR_SCALE_WH - the object size is
-- now defined relative to that of the width and/or height of the parent.
-- The relative delta is calculated based on the current scale versus the
-- initial (storage without a texture backing) or the current storage size.
--
-- @note: Changing link ownership resets all scheduled transformations
-- except for blending.
-- @note: Rotation transforms do not take the positional anchor point
-- into account, only its mask.
-- @note: Link to self is equivalent to linking back to WORLDID.
-- @note: linked scale means that 1px will be subtracted from *id* in each
-- desired dimension when calculating final size as no object can go below
-- 1x1 px size, making it otherwise impossible to describe the case where
-- parent and child should have identical size for the shared dimension.
-- hare dimensions
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
