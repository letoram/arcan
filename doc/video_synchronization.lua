-- video_synchronization
-- @short: Get or set the current synchronization strategy
-- @inargs:
-- @outargs: nil or strtbl
-- @longdescr: There are two stages for controlling synchronization strategy.
-- The first one is static and can only be formed on the command-line, which should
-- be limited to strategies that require specific video platform configuration that
-- could invalidate the current graphics context. The other stage can be controlled
-- using this function. First a call with a nil *stratname* argument which will
-- return a table with the set of allowed values. One of these values can then be
-- used in a subsequent call which will switch the active strategy to the one
-- specified, if possible.
-- @note: The resulting *strtbl* values are valid only until the next call to
-- set a video_synchronization.
-- @note: Attempting to set an invalid or unknown synchronization will silently
-- fail. No systemic state change will be attempted.
-- @note: The returned strtbl is indexed both on name and by number. name indexes
-- can be used to also get the short description of the strategy.
-- @note: The available selection of synchronization strategies are video platform
-- and possibly hardware configuration specific.
-- @group: vidsys
-- @cfunction: videosynch
-- @related:
function main()
#ifdef MAIN
	local tbl = video_synchronization();
	for k,v in ipairs(tbl) do
		print(v);
		print(tbl[v]);
	end

	if (#tbl > 0) then
		print("switching to " .. tbl[1]);
		video_synchronization(tbl[1]);
	else
		print("no dynamic synchronization strategies are available");
	end
#endif
end
