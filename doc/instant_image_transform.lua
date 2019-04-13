-- instant_image_transform
-- @short: Immediately perform all pending transformations.
-- @inargs: vid:dst
-- @inargs: vid:dst, bool:trigger_last
-- @inargs: vid:dst, bool:trigger_last, bool:trigger_all
-- @group: image
-- @description:
-- This will fast-forward through the transform chain for *dst*.
--
-- The default behaviour is to ignore all tagged transform handlers. If
-- *trigger_last* is set, all handlers except the end of each chain will
-- be ignored. If *trigger_all* is set, all handlers will be triggered.
--
-- Both of these behaviours can lead to hard to debug problems due to
-- the possible storms of feedback loops being created. The safest
-- solution to this problem has been to simply ignore the handlers,
-- but that is not always the ideal one.
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
