-- warning
-- @short: Write a string to the warning log output.
-- @inargs: string:message
-- @inargs: string:message, bool:debug
-- @group: system
-- @longdescr: Log a message to the current system/debug log.
-- If the optional *debug* argument is set to true, any attached
-- debug monitor will be invoked with the context. This can be
-- used to source-inject breakpoints.
-- @note: Only [a-Z,.0-9] and whitespace characters will be
-- passed to the output log, other characters will be
-- replaced with a whitespace.
-- @cfunction: warning
function main()
#ifdef MAIN
	warning("warning test");
#endif

#ifdef ERROR
	warning(nil);
#endif
end
