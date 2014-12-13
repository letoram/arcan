-- close_rawresource
-- @short: Close the context-global output file.
-- @inargs:
-- @outargs:
-- @longdescr: Raw access to string- or raw-byte- output files is not encouraged in the scriptable Arcan interface, although some support functions are added for certain edge-cases. Calling this function closes a resource file opened through open_rawresource.
-- @group: resource
-- @cfunction: rawclose
-- @related: open_rawresource, write_rawresource, read_rawresource
-- @flags:
function main()
#ifdef MAIN
	open_rawresource("testres.txt");
	close_rawresource();
#endif

#ifdef ERROR
	close_rawresource();
#endif
end
