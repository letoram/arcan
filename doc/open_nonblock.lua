-- open_nonblock
-- @short: Open a file in read or write mode for non-blocking text I/O.
-- @inargs: res, *wmode*
-- @outargs: blocktbl
-- @longdescr: Locate and open the resource indicated by *res* and map to a
-- usertable in (default) read-mode or (if wmode ~= 0) write-mode.  for
-- non-blocking buffered reads XOR write. Calls to read (no arguments) will
-- yield nil or a string representing a line or null-terminated buffer
-- contents.  If the open operation fails for any reason, blocktbl will be nil.
-- Calls to write will yield the number of character successfully written
-- (should ideally be #res but short-writes are possible). The blocktable will
-- contain (read,close) or (write,close) methods. Close is called on garbage
-- collect unless explicitly closed in beforehand.
-- @note: If *res* begins with a '<' character, the input will be created as a
-- named pipe (fifo) and the fifo will be restricted to the APPL_TEMP namespace.
-- @note: blocktbl methods: (read-mode: read, close)
-- @note: if *res* points to a valid frameserver connection, an unnamed pipe
-- pair will be created and sent to target as a _BCHUNK_(IN) or (OUT) event
-- (write-mode: write, close)
-- @note: the corresponding file-descriptor will be closed upon
-- garbage collection or by calling the table- method close.
-- @note: For filesystem backed *res* destinations, the restrictions of the
-- APPL_TEMP namespace applies.
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
