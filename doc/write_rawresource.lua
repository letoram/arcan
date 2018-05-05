--- write_rawresource
-- @short: Write a line from the globally shared raw resource handle.
-- @outargs: line
-- @note: Each "line" is constrained to a maximum of 256 characters.
-- @note: Leading and trailing whitespace is removed.
-- @note: This is not intended as a primary I/O mechanism, just as a
-- fallback for logging and code/configuration generation in a purposely
-- limited fashion. Furthermore, it is synchronously blocking.
-- @deprecated:open_nonblock
-- @group: resource
-- @cfunction: writerawresource
-- @related: open_rawresource, read_rawresource, close_rawresource
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
