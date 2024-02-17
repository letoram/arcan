-- rendertarget_reconfigure
-- @short: Change the output density or processing flags of a rendertarget
-- @inargs: vid:rtgt, float:hppcm, float:vppcm
-- @outargs:
-- @longdescr:
-- Two major properties of a rendertarget are the intended output density
-- and the targetted colour space.
--
-- For vectorized assets that are sized in physical units e.g. pt (1/72th of an
-- inch) like with render_text, the engine needs knowledge of the target output
-- before drawing. By default, this is some display-dependent initial size,
-- accessible through the global constants HPPCM and VPPCM, or 38.4 when those
-- cannot be found. When targeting a display, locally or remote, that has a
-- different density it is typically advised to update the rendertarget
-- pipeline that gets mapped to that output using this function. Whenever an
-- asset gets created or attached to a rendertarget, it will be rerastered to
-- match the density of the rendertarget.
--
-- @note: For HDR composition and rendering, you typically need to provide
-- further metadata about light levels and so on. This can be set on the *rtgt*
-- using ref:image_metadata.
-- @group: targetcontrol
-- @cfunction: renderreconf
-- @external: yes
-- @example: tests/rtdensity
-- @related:
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
