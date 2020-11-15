-- instant_image_transform
-- @short: Immediately perform all pending transformations.
-- @inargs: vid:dst
-- @inargs: vid:dst, int:mask
-- @inargs: vid:dst, bool:trigger_last
-- @inargs: vid:dst, bool:trigger_last, bool:trigger_all
-- @group: image
-- @longdescr:
-- This will fast-forward through the transform chain for *dst*.  If 'mask' is
-- set, only the specifiied bitmask of chains (MASK_OPACITY, MASK_ORIENTATION,
-- MASK_POSITION, MASK_SCALE) will be fast-forwarded.
--
-- The default behaviour is to ignore all tagged transform handlers. If
-- *trigger_last* is set, all handlers except the end of each chain will
-- be ignored. If *trigger_all* is set, all handlers will be triggered.
--
-- @note: The trigger_last, trigger_all forms are problematic and should only
-- be used in exceptional circumstances as a tag transform might lead to a new
-- transform being added which will immediately be triggered and so on,
-- possibly causing hard to debug infinite chains.
--
-- @cfunction: instanttransform
-- @related: copy_image_transform
-- image_transform_cycle, reset_image_transform, transfer_image_transform
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	show_image(a);
	move_image(a, 50, 50, 100);
	instant_image_transform(a);
	props = image_surface_properties(a);
	print(props.x, props.y);
#endif
end
