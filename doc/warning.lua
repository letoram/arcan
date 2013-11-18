-- warning
-- @short: Write a string to the warning log output. 
-- @inargs: messagestr
-- @group: system 
-- @cfunction: arcan_lua_warning
function main()
#ifdef MAIN
	warning("warning test");
#endif

#ifdef ERROR1
	warning(nil);
#endif
end
