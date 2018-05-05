-- read_rawresource
-- @short: Read a line from the globally shared raw resource handle.
-- @outargs: line
-- @note: Each "line" is constrained to a maximum of 4096 characters.
-- @note: Leading and trailing whitespace is removed.
-- @deprecated:open_nonblock
-- @group: resource
-- @cfunction: readrawresource
-- @related: open_rawresource, write_rawresource, close_rawresource
function main()
#ifdef MAIN
	zap_resource("test.txt");
	open_rawresource("test.txt");
	write_rawresource("linea");
	close_rawresource();

	open_rawresource("test.txt");
	local line = read_rawresource();
	close_rawresource();
	if (line == "linea") then
		warning("resource test OK");
	else
		warning("resource test failed");
	end
#endif
end
