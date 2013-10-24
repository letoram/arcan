-- shutdown
-- @short: Queue a shutdown event. 
-- @longdescr: This function will shutdown the engine and terminate the 
-- process when deemed safe. This means that it will not happened immediately,
-- but rather that an event will be queued internally in order to give
-- frameservers and other pending-data related tasks time to clean-up.
-- @group: system 
-- @cfunction: arcan_lua_shutdown
function main()
#ifdef MAIN
	shutdown();
#endif
end
