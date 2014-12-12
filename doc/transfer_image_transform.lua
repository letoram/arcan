-- transfer_image_transform
-- @short: Move the transform chain from one VID to another.
-- @inargs: srcvid, dstvid
-- @longdescr: This function act as an aggregate of copying a transform chain
-- (including the translation step and related side notes as described in
-- copy_image_transform) from *srcvid* to *dstvid* and then
-- reseting the source transform.
-- @group: image
-- @cfunction: transfertransform
-- @related: copy_image_transform, reset_image_transform
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	b = fill_surface(32, 32, 0, 255, 0);
	show_image({a, b});

	move_image(a, 64, 64, 100);
	rotate_image(a, 32, 100);
	transfer_image_transform(a, b);
#endif
end
