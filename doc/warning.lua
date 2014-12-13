-- warning
-- @short: Write a string to the warning log output.
-- @inargs: messagestr, *level*
-- @group: system
-- @longdescr: Log a message to the current system/debug log,
-- the optional level indicates severity (default, 0).
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
