-- target_displayhint
-- @short: Send visibility / drawing hint to target frameserver.
-- @inargs: tgtid, width, height, *cont*, *disptbl*
-- @longdescr: The target_displayhint sends a hint to the specified target
-- that it should try and resize its shared memory connection to the desired
-- dimensions. This can be used to notify about current drawing dimensions for
-- the associated video object, or for special cases where one might want
-- an explicitly over- or under-sized input buffer.
-- If the optional *cont* value is set to true or 1, the hint is marked
-- as one that there may be multiple hints to come (e.g. drag-resize).
-- If the optional *disptbl* is set to a table that matches the format for
-- display added events, additional information (physical dimensions, rgb
-- hinting layout etc.) may be propagated. If it is set to WORLDID, the display
-- information for the primary display will be propagated.
-- @group: targetcontrol
-- @note: width/height that exceeds the static compile-time limitations of
-- MAX_TARGETW or MAX_TARGETH will be clamped to those values. Invalid hint-
-- dimensions (0 <= n) is a terminal state transition.
-- @note: The correlated event gets special treatment. When the dequeue function
-- in the shared memory interface discovers a displayhint event, the remainder of
-- the queue will be scanned for additional ones. If one is found, the first (i.e.
-- oldest) event will be dropped. This prevents bubbles from a possible resize-
-- reaction for common scenarios such as drag-resizing a window.
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
