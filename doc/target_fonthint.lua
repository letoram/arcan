-- target_fonthint
-- @short: Send font drawing hints to target frameserver.
-- @inargs: dstvid, *fontres*, size_mm, strength
-- @outargs: bool
-- @longdescr: The target_fonthint function sends a hint (and
-- optionally a descriptor to the specified font resource in the
-- ARCAN_SYS_FONT namespace) about how frameserver rendered text should be
-- drawn into the specified segment. The *size_pt* argument sets the desired
-- 'normal' font size (in mm). Use ref:target_displayhint to handle changes
-- in underlying display pixel density. Strength is an implementation-specific
-- (as we do not directly provide or control libraries for font-rendering)
-- hint on anti-aliasing properties ranging from disabled (0), weak (1)
-- to strong (16).
-- @note: if -1 is used for *size_mm* and or *strength*, the recipient
-- should keep the currently hinted size.
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
