-- target_displayhint
-- @short: Send visibility / drawing hint to target frameserver.
-- @inargs: tgtid, width, height, *flags*, *displaytbl*
-- @longdescr: The target_displayhint sends a hint to the specified target
-- that it should try and resize its shared memory connection to the desired
-- dimensions. This can be used to notify about current drawing dimensions for
-- the associated video object, or for special cases where one might want
-- an explicitly over- or under-sized input buffer.
-- The possible values for the optional *flag* field are (combine with bit.bor):
-- TD_HINT_IGNORE - no change to the flag state from last time.
-- TD_HINT_CONTINUED - resize events are likely to be followed with more,
-- TD_HINT_UNFOCUSED - no input focus, input events can still arrive but
-- no visibile indication (e.g. cursor) needs to be shown
-- TD_HINT_INVISIBLE - not currently visible/used, no need to update/draw
-- TD_HINT_MAXIMIZED - window is in a 'maximized' state, some UI toolkits
-- will change their visible behavior if they know that they are in this state.
-- TD_HINT_FULLSCREEN - window is in a 'fullscreen' state, similar to the
-- maximized state, some UI toolkits may want this.
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
