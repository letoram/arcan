-- blend_image
-- @short: Change image opacity.
-- @inargs: VID or VIDtbl, opacity, *time*, *interp*
-- @outargs:
-- @longdescr: Changes the opacity of the selected VIDs either immediately
-- (default) or by setting an optional *time* argument to a non-negative
-- integer. This function either accepts single VIDs or a group of VIDs in
-- a table (iteration will follow the behavior of pairs()).
--
-- The *opacity* argument is a floating-point value in the range [0.0, 1.0]
-- where 0.0 is fully transparent (hidden) and 1.0 is fully opaque (visible).
-- Values outside this range are clamped: negative values become 0.0, values
-- greater than 1.0 become 1.0.
--
-- IEEE 754 special values are handled explicitly:
--   NaN  - mapped to 1.0 (fully opaque). This is a safe default because an
--          object whose opacity is accidentally NaN should remain visible
--          rather than silently disappearing, which would be much harder to
--          debug visually. Prior to this fix, NaN would bypass the CLAMP
--          macro (since NaN comparisons are always false in IEEE 754) and
--          propagate into the blending pipeline, producing undefined
--          rendering artifacts that varied by GPU driver.
--   +Inf - clamped to 1.0 (fully opaque)
--   -Inf - clamped to 0.0 (fully transparent)
--
-- Interp can be set to one of the constants (INTERP_LINEAR, INTERP_SINE,
-- INTERP_EXPIN, INTERP_EXPOUT, INTERP_EXPINOUT, INTERP_SMOOTHSTEP).
-- The interpolation function is only applied when *time* > 0; for
-- immediate opacity changes it is ignored.
--
-- When blending is active (opacity is neither exactly 0.0 nor exactly 1.0),
-- the per-fragment cost increases due to the alpha compositing math. For
-- scenes with many translucent objects, consider using
-- ref:force_image_blend with BLEND_PREMULTIPLIED to reduce the per-fragment
-- ALU cost on tiling GPUs where the shader compiler cannot elide the
-- src_alpha multiply for pre-multiplied content.
--
-- The opacity value set here interacts with the inherited opacity from
-- parent objects linked via ref:link_image. The effective opacity is the
-- product of the object's own opacity and its parent's effective opacity,
-- unless MASK_OPACITY has been cleared via ref:image_mask_clear. This
-- inherited opacity chain is evaluated lazily during the render pass,
-- so querying ref:image_surface_properties immediately after blend_image
-- will return the object's local opacity, not the resolved effective
-- opacity. To resolve the full chain, use ref:image_surface_resolve_properties.
--
-- For frameserver-backed objects that use tpack rendering, changing opacity
-- does not trigger a resize event to the client. The compositing happens
-- entirely on the server side. However, the cell metric estimates returned
-- by ref:target_displayhint (cellw, cellh, density, ppcm) are unaffected
-- by opacity changes, so there is no need to re-query after a blend_image
-- call.
--
-- @note: VIDs with an opacity other than 0.0 (hidden) and 1.0 (opaque,
-- visible) will be blended.
-- @note: Values outside the allowed range will be clamped. NaN is mapped
-- to fully opaque (1.0) as a safe default. See the longdescr section above
-- for the full IEEE 754 handling rules.
-- @note: The blend behavior is dictated by the default global blendfunc
-- value (src_alpha, 1-src_alpha) and can be overridden with
-- force_image_blend(mode). See also ref:switch_default_blendmode for
-- changing the global default.
-- @note: When animating opacity over time, the transform chain stores the
-- start and end opacity values along with the interpolation mode. If a
-- new blend_image call is issued before a previous animation completes,
-- the new animation is appended to the chain (not replacing it). To
-- cancel pending blend animations, use ref:reset_image_transform.
-- @note: The clamping is performed in both the Lua binding layer and the
-- underlying C function (arcan_video_objectopacity) for defense-in-depth.
-- Internal engine paths that set opacity directly (transform chain
-- completion, xfer surface initialization) also go through the same
-- NaN-safe clamping.
-- @group: image
-- @related: force_image_blend, image_surface_properties,
-- switch_default_blendmode, image_mask_set, target_displayhint
-- @cfunction: imageopacity
-- @alias: show_image, hide_image
-- @flags:
function main()
	a = fill_surface(128, 128, 255, 0, 0);
	b = fill_surface(128, 128, 0, 255, 0);
	move_image(b, 64, 64);
	show_image({a,b});
#ifdef MAIN
	-- basic: animate to 50% opacity over 100 ticks
	blend_image(b, 0.5, 100);

	-- with interpolation: smooth ease-in-out
	blend_image(b, 0.8, 200, INTERP_SMOOTHSTEP);

	-- batch operation: fade a group of objects together
	local surfaces = {};
	for i = 1, 4 do
		surfaces[i] = fill_surface(64, 64, 255, i * 60, 0);
		move_image(surfaces[i], (i-1) * 72, 0);
	end
	show_image(surfaces);
	blend_image(surfaces, 0.3, 50, INTERP_SINE);

	-- NaN safety: these all resolve to fully opaque (1.0)
	blend_image(b, 0/0);         -- NaN from division
	blend_image(b, math.huge - math.huge);  -- NaN from subtraction
	local props = image_surface_properties(b);
	print("opacity after NaN: " .. tostring(props.opa)); -- prints 1.0

	-- +Inf/-Inf: clamped to 1.0 and 0.0 respectively
	blend_image(b, math.huge);   -- clamped to 1.0 (opaque)
	blend_image(b, -math.huge);  -- clamped to 0.0 (hidden)
#endif

#ifdef ERROR
	blend_image(b, -0.5, -100);
#endif

#ifdef ERROR2
	blend_image(b, "a", 0.5, 100);
#endif

#ifdef ERROR3
	blend_image({-1, "a", true, 5.0}, true, "error");
#endif
end
