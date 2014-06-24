-- input_filter_analog
-- @short: Define a prefilter-stage for a specific analog device.
-- @inargs: devid, subid, mode, modeval
-- @outargs:
-- @longdescr: Some input devices are very noisy in that they emitt
-- samples at a high frequency. This increases the engine load overall,
-- both in terms of increasing the likelyhood that queues will be saturated
-- and in terms of the number of "input_event" state transitions which
-- are somewhat expensive.
-- This function allows for a filter to be associated on an axis per axis basis,
-- to even out or otherwise analyze samples to generate a lower frequency of
-- calls to the LUA layer.
-- @group: iodev
-- @cfunction: arcan_lua_inputfilteranalog
-- @flags: incomplete
function main()
#ifdef MAIN
	input_filter_analog(0, 1, FILTER_SMOOTH, 8);
#endif
end
