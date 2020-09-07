-- benchmark_tracedata
-- @short: Add a datapoint to the ongoing tracebuffer
-- @inargs: string:subsystem, string:message
-- @inargs: string:subsystem, string:message, int:identifier=0, int:quantity=1
-- @inargs: string:subsystem, string:message, int:identifier=0, int:quantity=1, int:trigger=TRACE_TRIGGER_ONESHOT
-- @inargs: string:subsystem, string:message, int:identifier=0, int:quantity=1, int:trigger=TRACE_TRIGGER_ONESHOT, int:level=TRACE_PATH_DEFAULT
-- @inargs: string:subsystem, string:message, int:identifier=0, int:quantity=1, int:trigger=TRACE_TRIGGER_ONESHOT, int:level=TRACE_PATH_DEFAULT
-- @outargs:
-- @longdescr:
-- This function adds a datapoint to the ongoing tracebuffer. See ref:benchmark_enable
-- for how the buffer and its reporting function is used and configured. The possible
-- arguments are 'subsystem' (caller defined), 'message' (caller defined),
-- object identifier (caller defined), quantity indicator, trigger
-- (from the set of TRACE_TRIGGER_ONESHOT, TRACE_TRIGGER_ENTER,
-- TRACE_TRIGGER_EXIT) and performance path (TRACE_PATH_DEFAULT, TRACE_PATH_SLOW,
-- TRACE_PATH_WARNING, TRACE_PATH_ERROR, TRACE_PATH_FAST).
-- @group: system
-- @cfunction: benchtracedata
-- @related: benchmark_enable
function main()
#ifdef MAIN
	benchmark_enable(1,
	function(res)
		for k,v in ipairs(res[1]) do
			print(k, v);
		end
	end)
	benchmark_tracedata("test", "hi", 10, TRACE_TRIGGER_ONESHOT, TRACE_PATH_DEFAULT)
#endif
end
