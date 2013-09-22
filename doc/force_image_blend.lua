-- force_image_blend
-- @short: Explicitly set blendmode 
-- @inargs: vid, *blendmode
-- @outargs: 
-- @longdescr: All objects default to BLEND_NONE when completely opaque (opacity around 1.0),
-- and revert to the global default otherwise (BLEND_NORMAL, i.e. SRC_ALPHA, 1 - SRC_ALPHA).
-- This behavior can be overridden on a per-object basis.
-- Accepted values for *blendmode* are (BLEND_NORMAL, BLEND_ADD, BLEND_FORCE, BLEND_MULTIPLY)
-- and if no blend mode is specified, BLEND_FORCE will be assumed.
-- @note: blendmode 
-- @group: image 
-- @cfunction: arcan_lua_forceblend
-- @flags: 
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	blend_image(a, 0.5);
	force_image_blend(a, BLEND_ADD);
#endif

#ifdef ERROR1
	force_image_blend(BADID, BLEND_NORMAL);
#endif

#ifdef ERROR2
	a = fill_surface(32, 32, 255, 0, 0);
	force_image_blend(a, -10);
#endif
end
