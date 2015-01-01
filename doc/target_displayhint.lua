-- target_displayhint
-- @short: Send visibility / drawing hint to target frameserver.
-- @inargs: tgtid, width, height
-- @longdescr: A frameserver is not updated about drawing details
-- such as current display dimensions as that is considered privileged
-- information. target_displayhint can be used to indiciate a discrepancy
-- between the current effective frameserver resolution and the output
-- buffer dimensions that the frameserver has negotiated to provide something
-- for the frameserver to react to when it comes to drawing (or resizing).
-- @group: targetcontrol
-- @note: Care should be taken to avoid introducing feedback loops or stalls
-- from sending this event too frequently as the engine does not currently
-- rate-limit frameserver resize requests (as indicated with the FLEXIBLE
-- test that can be found in tests/security).
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
