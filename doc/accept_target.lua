-- accept_target
-- @short: accept a pending target request for a new segment
-- @inargs: *setw*, *seth*
-- @outargs:
-- @longdescr: A connected frameserver is provided with one segment
-- by default, but additional ones can be requested. If that happens,
-- a segment_request event is sent through to the callback
-- associated with the frameserver. If this request goes unhandled
-- in the callback implementation, a rejection reply will be sent.
-- By calling accept_target in immediate response to a segment_request,
-- a new segment will be allocated and sent to the frameserver. The
-- type of this segment will follow the one present in the request,
-- and it is the responsibility of the script to determine that this
-- is one that is supported. To filter the segkind field, prefer to
-- use an inclusive whitelisting approach.
-- The optional arguments *setw*, *seth* can be used to change the
-- initial dimensions of the new segment from the ones requested in the
-- segreq event (see ref:launch\_target). The frameserver can still
-- perform a resize to ignore these values, but it saves a possible
-- displayhint->resize cycle with the 1-2 frame latency that would
-- impose.
-- @note: accept_target is context sensitive. This means that calling
-- it outside a frameserver event-handler, or when there is no pending
-- segment_request event, is a terminal state transition.
-- @note: Possible segkind values are: "multimedia", "cursor", "shell",
-- "popup", "icon", "remoting", "game", "hmd-l", "hmd-r", "hmd-sbs-lr",
-- "vm", "application", "clipboard", "browser", "encoder", "titlebar",
-- "sensor", "debug", "accessibility", "unknown".
-- @note: The number of permitted segments etc. should be limited
-- by available vids and other resources so that a malicious client
-- cannot starve the serving arcan process. See the 'recursive_evil'
-- security test case for more detail.
-- @note: Subsegments are always bound to the primary segment,
-- this means that attempts at complex hierarchies (main- window
-- with a popup window with a titlebar with an icon is not possible).
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
