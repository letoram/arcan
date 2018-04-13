-- shutdown
-- @short: Queue a shutdown event.
-- @inargs: *optmsg*, *optcode*
-- @longdescr: This function will shutdown the engine and terminate the
-- process when deemed safe. This means that it will not happened immediately,
-- but rather that an event will be queued internally in order to give
-- frameservers and other pending-data related tasks time to clean-up.
-- The system interpretation of *optcode* varies with the underlying
-- environment, though the EXIT_SUCCESS and EXIT_FAILURE constants are
-- propagated and useful here. There is also a special constant, EXIT_SILENT
-- that will return an EXIT_SUCCESS to the outer system, but only signal
-- a 'display server lost' action to external clients, rather than asking
-- them to shut down.
-- @note: by default, the exit code corresponds to system EXIT_SUCCESS,
-- but can be set to a custom value through *optcode*.
-- @note: optmsg is filtered to only accept [a-Z,.0-9] and whitespace.
-- @group: system
-- @cfunction: shutdown
function main()
#ifdef MAIN
	return shutdown();
#endif

#ifdef MAIN2
	return shutdown("giving up", -1);
#endif
end
