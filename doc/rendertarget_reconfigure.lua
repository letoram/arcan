-- rendertarget_reconfigure
-- @short: Change the output density on a rendertarget
-- @inargs: vid:rtgt, float:hppcm, float:vppcm
-- @outargs:
-- @longdescr: Vectorized assets that are sized in physical units
-- e.g. pt (1/72th of an inch) like with render_text, the engine needs
-- needs knowledge of the target output before drawing. By default, this is
-- some display-dependent initial size, accessible through the global
-- constants HPPCM and VPPCM, or 38.4 when those cannot be found. When
-- targeting a display, locally or remote, that has a different density
-- it is typically advised to update the rendertarget pipeline that gets
-- mapped to that output using this function. Whenever an asset gets created
-- or attached to a rendertarget, it will rerastered to match the density
-- of the rendertarget.
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
