-- rendertarget_reconfigure
-- @short: Change the output density or colour properties of a rendertarget
-- @inargs: vid:rtgt, float:hppcm, float:vppcm
-- @inargs: vid:rtgt, tbl:metadata
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
-- For HDR composition and rendering, you typically need to provide further
-- metadata about light levels and so on. This can be set through the metadata
-- table which accepts the following fields: {encoding, whitepoint, levels,
-- lumarange, primaries}.
--
-- @tblent: string:encoding, "itu-r", "bt.601", "bt.709", "bt.2020", "YCBCr"
-- @tblent: table:whitepoint[2], x/y coordinates ranging from 0..1, 0..1
-- @tblent: table:primaries[6], x/y coordinates of red, green, blue primaries
-- @tblent: number:max_frame_average, in nits, caps at 65535.
-- @tblent: number:max_content_level, in nits, caps at 65535.
-- @tblent: table:mastering_levels[2], in nits, caps at 65535.
--
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
