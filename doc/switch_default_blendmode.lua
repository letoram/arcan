-- switch_default_blendmode
-- @short: Change the blend operation set as default on all new objects.
-- @inargs: int:mode
-- @outargs:
-- @longdescr: Due to legacy and scripts dependent on now known buggy behaviour,
-- the default blending mode is set to BLEND_FORCE. This means that regardless
-- of object opacity, everything will be drawn with blending enabled. This
-- might be less performant on some GPUs when compared to the option of
-- disabling blending for objects that are fully opaque and have no alpha
-- channel, which is refered to as BLEND_NORMAL. This function can be used to
-- indicate that the script knows about the distinction or has other blending
-- needs where a lot of ref:force_image_blend calls can be avoided by changing
-- the default to some other mode.
-- @note: Specifying an invalid value for *mode* is a terminal state transition.
-- @group: vidsys
-- @cfunction: setblendmode
-- @related:
function main()
#ifdef MAIN
	switch_default_blendmode(BLEND_NORMAL)
#endif

#ifdef ERROR1
	switch_default_blendmode(BADID)
#endif
end
