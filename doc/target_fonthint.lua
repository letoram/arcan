-- target_fonthint
-- @short: Send font drawing hints to target frameserver.
-- @inargs: dstvid, *fontres*, size_pt, strength
-- @outargs: bool
-- @longdescr: The target_fonthint function sends a hint (and
-- optionally a descriptor to the specified font resource in the
-- ARCAN_SYS_FONT namespace) about how frameserver rendered text should be
-- drawn into the specified segment. The *size_pt* argument sets the desired
-- 'normal' font size (in points, 1/72 inch)
-- ref:target_displayhint to handle changes in underlying display pixel density.
-- Strength is an implementation-specific (as we do not directly provide or
-- control libraries for font-rendering) hint on anti-aliasing properties
-- ranging from disabled (0), weak (1) to strong (16).
-- @group: targetcontrol
-- @cfunction: targetfonthint
-- @related:
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
