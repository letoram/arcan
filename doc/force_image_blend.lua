-- force_image_blend
-- @short: Control image blend behaviour
-- @inargs: vid:dst
-- @inargs: vid:dst, int:mode
-- @outargs:
-- @longdescr: There are a number of controls for adjusting how overlapping
-- objects that are translucent or has transparent contents described by an
-- alpha color channel are supposed to combine. This function can be used to
-- change that behavior. If no *mode* is set, the system default will be set.
-- Other blend-modes are:
-- BLEND_NORMAL (disable blending if object opacity is marked as opaque)
-- BLEND_ADD (one, one: additive blending, rgb channels will be combined)
-- BLEND_SUB (one: dst will be subtracted based on one-src alpha),
-- BLEND_MUL (dst-color, one-src alpha),
-- BLEND_PREMULTIPLIED (one, one-src alpha: the source object has its alpha
-- values pre-multiplied into the color channels)
-- @note: The default can be changed by calling ref:switch_default_blendmode.
-- @group: image
-- @cfunction: forceblend
-- @flags:
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	blend_image(a, 0.5);
	force_image_blend(a, BLEND_ADD);
#endif

#ifdef ERROR
	force_image_blend(BADID, BLEND_NORMAL);
#endif

#ifdef ERROR2
	a = fill_surface(32, 32, 255, 0, 0);
	force_image_blend(a, -10);
#endif
end
