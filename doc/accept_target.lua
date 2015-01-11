-- accept_target
-- @short: accept a pending target request for a new segment
-- @inargs:
-- @outargs:
-- @longdescr: A connected frameserver is provided with one segment
-- by default, but additional ones can be requested. If that happens,
-- a segment_request event is sent through to the callback
-- associated with the frameserver. If this request goes unhandled
-- in the callback implementation, a rejection reply will be sent.
-- By calling accept_target in immediate response to a segment_request,
-- a new segment will be allocated and sent to the frameserver.
-- @note: accept_target is context sensitive. This means that calling
-- it outside a frameserver event-handler, or when there is no pending
-- segment_request event, is a terminal state transition.
-- @note: The number of permitted segments etc. should be limited
-- by available vids and other resources so that a malicious client
-- cannot starve the serving arcan process. See the 'recursive_evil'
-- security test case for more detail.
-- @group: targetcontrol
-- @cfunction: targetaccept
-- @related: target_alloc
function main()
#ifdef MAIN
	target_alloc("test", function(source, status)
		if (status.kind == "segment_request") then
-- possibly ignore request if supplied properties e.g.
-- dimensions or subtype is not permitted.
			accept_target();
		end
	end)
#endif

#ifdef ERROR1
	accept_target();
#endif
end
