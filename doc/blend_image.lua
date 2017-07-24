-- blend_image
-- @short: Change image opacity.
-- @inargs: VID or VIDtbl, opacity, *time*, *interp*
-- @outargs:
-- @longdescr: Changes the opacity of the selected VIDs either immediately (default) or by setting an optional *time* argument to a non-negative integer. This function either accepts single VIDs or a group of VIDs in a table (iteration will follow the behavior of pairs()
-- Interp can be set to one of the constants (INTERP_LINEAR,
-- INTERP_SINE, INTERP_EXPIN, INTERP_EXPOUT, INTERP_EXPINOUT,
-- INTERP_SMOOTHSTEP).
-- @note: VIDs with an opacity other than 0.0 (hidden) and 1.0 (opaque, visible) will be blended.
-- @note: Values outside the allowed range will be clamped.
-- @note: The blend behavior is dictated by the default global blendfunc value (src_alpha, 1-src_alpha) and can be overridden with force_image_blend(mode)
-- @group: image
-- @related: image_force_blend
-- @cfunction: imageopacity
-- @alias: show_image, hide_image
-- @flags:
function main()
	a = fill_surface(128, 128, 255, 0, 0);
	b = fill_surface(128, 128, 0, 255, 0);
	move_image(b, 64, 64);
	show_image({a,b});
#ifdef MAIN
	blend_image(b, 0.5, 100);
#endif

#ifdef ERROR
	blend_image(b, -0.5, -100);
#endif

#ifdef ERROR2
	blend_image("a", 0.5, 100);
#endif

#ifdef ERROR3
	blend_image({-1, "a", true, 5.0}, true, "error");
#endif
end
