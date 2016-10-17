-- target_displayhint
-- @short: Send visibility / drawing hint to target frameserver.
-- @inargs: tgtid, width, height, *flags*, *displaytbl*
-- @longdescr: The target_displayhint sends a hint to the specified target
-- that it should try and resize its shared memory connection to the desired
-- dimensions. This can be used to notify about current drawing dimensions for
-- the associated video object, or for special cases where one might want
-- an explicitly over- or under-sized input buffer.
-- Possible optional *flag* values:
-- TD_HINT_INVISIBLE - invisible, TD_HINT_UNFOCUSED). Hence the default is
-- visible and focused. These can be combined with bit.band(fl1, fl2) or
-- set to no change with TD_HINT_IGNORE.
-- If the optional *displaytbl* is set and is a table, the fields 'ppcm' and
-- 'subpixel_layout' are expected to be present.
-- If the optional *displaytbl* is set to WORLDID, the display information for
-- the primary display will be used.
-- @group: targetcontrol
-- @note: width/height that exceeds the static compile-time limitations of
-- MAX_TARGETW or MAX_TARGETH will be clamped to those values. Invalid hint-
-- dimensions (0 <= n) is a terminal state transition.
-- @note: changing the pixel density (width/height + *disptbl* with phy_width,
-- phy_height) may incur font rendering changes in the *tgtid* referenced target.
-- @note: The correlated event gets special treatment. When the dequeue function
-- in the shared memory interface discover a displayhint event, the remainder of
-- the queue will be scanned for additional ones. Relevant fields will be
-- merged and properties that are in conflict will favor the most recent.
-- This prevents bubbles from a possible resize- reaction for common scenarios
-- such as drag-resizing a window.
-- @cfunction: targetdisphint
-- @related:
function main()
	local a = target_alloc("example", function() end);
	show_image(a);
	resize_image(a, VRESW, VRESH);

#ifdef MAIN
	target_displayhint(a, VRESW, VRESH);
#endif

#ifdef ERROR1
	target_displayhint(a, VRESW);
#endif

#ifdef ERROR2
	target_displayhint(a, 0, 0);
#endif
end
