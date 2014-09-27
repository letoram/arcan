-- open_nonblock
-- @short: Open a file in read-only mode for non-blocking text-input.
-- @inargs: res
-- @outargs: blocktbl
-- @longdescr: Locate and open the resource indicated by *res* and
-- map to a usertable (blocktbl, methods: read, close) for non-blocking
-- buffered reads. Calls to read (no arguments) will yield nil or a
-- string representing a line or null-terminated buffer contents.
-- @note: the corresponding file-descriptor will be closed upon
-- garbage collection or by calling the table- method close.
-- @group: resource
-- @cfunction: opennonblock
-- @related:
#ifdef MAIN
function main()
	a = open_nonblock("test.txt")
	if (a == nil) then
		return shutdown("couldn't open test.txt");
	end
end

function main_clock_pulse()
	local line = a:read();
	if (line ~= nil) then
		print(line);
	end
end
#endif
