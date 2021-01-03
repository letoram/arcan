-- target_fonthint
-- @short: Send font drawing hints to target frameserver.
-- @inargs: vid:dst, string:font, number:size_mm, int:hint
-- @inargs: vid:dst, string:font, number:size_mm, int:hint, int:cont
-- @inargs: vid:dst, number:size_mm, int:hint
-- @inargs: vid:dst, number:size_mm, int:hint, int:cont
-- @outargs: bool:state, int:cellw, int:cellh
-- @longdescr: The target_fonthint function sends a hint (and
-- optionally a descriptor to the specified font resource in the
-- ARCAN_SYS_FONT namespace) about how frameserver rendered text should be
-- drawn into the specified segment. The *size_mm* argument sets the desired
-- 'normal' font size (in mm). Use ref:target_displayhint to handle changes
-- in underlying display pixel density. *strength* hints to anti-aliasing
-- like this (0: disabled, 1: monospace, 2: weak, 3: medium, 4:strong) and
-- if bit 8 is set (+ 256) try and apply subpixel hinting.
-- It is still up to the renderer in the receiving frameserver to respect
-- these flags and to match any rendering properties with corresponding
-- displayhints in order for sizes to match.
-- If the *cont* option is set to 1, this font is intended to be chained as a
-- fallback in the case of missing glyphs in previously supplied fonts.
-- The function returns true if the font was found and was forwarded correctly
-- to the client, as well as the estimated cell width/height that will currently
-- be used for size calculations of server-side text in monospaced form with the
-- supplied fonts.
-- @note: If -1 is used for *size_mm* and/or *strength*, the recipient
-- should keep the currently hinted size.
-- @note: To translate from the Postscript 'point size' to
-- millimeter, multiply with the constant FONT_PT_SZ.
-- @note: The actual font size will also vary with the density of the
-- output segment. The density can be expressed via the ref:target_displayhint
-- function.
-- @note: .default is a reserved name for propagating the font that is
-- currently set as the default (using ref:system_defaultfont)
-- @group: targetcontrol
-- @cfunction: targetfonthint
-- @related: system_defaultfont
function main()
	local fsrv = launch_avfeed(function(source, status)
	end);
#ifdef MAIN
	target_fonthint(fsrv, "default.ttf", 10, 1);
	target_fonthint(fsrv, 1, 0);
#endif

#ifdef ERROR1
	target_fonthint(WORLDID);
#endif
end
