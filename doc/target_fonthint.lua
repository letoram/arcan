-- target_fonthint
-- @short: Send font drawing hints to target frameserver.
-- @inargs: dstvid, *fontres*, size_cm, strength, *merge*
-- @outargs: bool
-- @longdescr: The target_fonthint function sends a hint (and
-- optionally a descriptor to the specified font resource in the
-- ARCAN_SYS_FONT namespace) about how frameserver rendered text should be
-- drawn into the specified segment. The *size_pt* argument sets the desired
-- 'normal' font size (in cm). Use ref:target_displayhint to handle changes
-- in underlying display pixel density. *Strength* hints to anti-aliasing
-- like this (0: disabled, 1: monospace, 2: weak, 3: medium, 4:strong) and
-- if bit 8 is set (+ 256) try and apply subpixel hinting.
-- It is still up to the renderer in the receiving frameserver to respect
-- these flags and to match any rendering properties with corresponding
-- displayhints in order for sizes to match.
-- If the *merge* option is set, this font is intended to be chained as a
-- fallback in the case of missing glyphs in previously supplied font.
-- @note: if -1 is used for *size_cm* and or *strength*, the recipient
-- should keep the currently hinted size.
-- @note: to translate from the normal typographic 'point size',
-- multiply with the constant FONT_PT_SZ
-- (0.0352778)
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
