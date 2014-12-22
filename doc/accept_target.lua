-- accept_target
-- @short: accept a pending target request for a new segment
-- @inargs:
-- @outargs:
-- @longdescr: A connected frameserver is permitted one segment by
-- default, though it can queue an event to request additional ones.
-- That results in a segment_request event being ent to the callback
-- associated with the frameserver. If this request goes unanswered
-- in the callback implementation, a rejection event will be sent.
-- By calling accept_target in response to a segment_request will
-- allocate and associate a subsegment with the target.
-- @note: This function is context sensitive meaning that to call
-- it outside a frameserver eventhandler when there is a pending
-- segment_request event, is a terminal state transition.
-- @note: The number of permitted segments etc. should be limited
-- by available vids and other resources so that a malicious client
-- cannot starve the serving arcan process.
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
