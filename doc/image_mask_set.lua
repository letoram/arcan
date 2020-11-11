-- image_mask_set
-- @short: Set a status flag on the specified object
-- @inargs: vid, maskval
-- @group: image
-- @cfunction: setmask
-- @longdescr:
-- Images that are linked to eachother via ref:link_image gets a number
-- of its attributes redefined to be relative the the parent it is linked
-- again. At times, not all attributes are relevant to inherit, and these
-- can be controlled through the image_mask_ set of functions.
--
-- The currently valid maskvals are:
--
-- MASK_UNPICKABLE : if set, the image will be ignored for picking
-- operations
--
--- MASK_LIVING : (default) if set, the image will be deleted when
-- the parent expires.
--
-- MASK_POSITION : (default) image coordinate system origo
--
-- MASK_OPACITY : (default) image opacity
--
-- MASK_ROTATION : (default) image rotation angle
--
-- MASK_SCALE : (default) reserved, no-op
--
-- MASK_MAPPING : if set, the image will use the texture coordinate
-- set of its (non-world) parent
--
-- @note: an invalid maskval is considered a terminal state transition.
-- @related: image_mask_toggle, image_mask_clear, image_mask_clearall
-- @reference: image_mask
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	b = instance_image(a);
	show_image({a, b});
	move_image(a, 32, 32);
	rotate_image(a, 120);
	image_mask_clearall(b);
	image_mask_set(b, MASK_ORIENTATION);
#endif

#ifdef ERROR
	image_mask_set(WORLDID, math.random(1000));
#endif
end
