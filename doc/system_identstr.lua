-- system_identstr
-- @short: Retrieve a string that identifies key subsystem components.
-- @inargs:
-- @outargs: identstr
-- @longdescr: There are numerous combinations of graphics cards,
-- library implementations etc. that can contribute to unwanted
-- behaviors. To assist with troubleshooting, this function generates
-- a non-sensitive (not divulging enough data to be usable to track,
-- identify or profile a user) string that can assist in debugging
-- efforts.
-- @group: system
-- @cfunction: getidentstr
-- @related:
function main()
#ifdef MAIN
	print( system_identstr() );
#endif
end
