-- open_nonblock
-- @short: Open a file in read or write mode for non-blocking text I/O.
-- @inargs: string:res
-- @inargs: string:res, bool:write
-- @inargs: vid:res
-- @inargs: vid:res, bool:write
-- @outargs: blocktbl
-- @longdescr: Create or open the resource indicated by *res* in (default)
-- read-mode or (if *mode* is provided, write mode)
-- If *res* is a vid connected to a frameserver, a streaming fifo session will
-- be set up over the connection along with the corresponding _BCHUNK events.
-- If *res* is a string, the initial character determines if it creates a
-- FIFO (<) or a SOCKET (=). FIFOs and SOCKETs are always created in the
-- RESOURCE_APPL_TEMP namespace.
-- If successful, FIFOs and normal resources return a table wih a close
-- operation (which is activated on garbage collection unless called in
-- beforehand) and a read or write function depending on the mode that
-- the resource was opened in.
-- The socket table is special in that it allows multiple connections.
-- the initial table for a socket only has a close and an accept function.
-- The accept function takes no arguments and returns a table in both read
-- and write mode when there is a client waiting.
--
-- The read() function takes one optional argument, bool:nobuf which disables
-- local buffering. The default behavior of the read function is otherwise to
-- buffer until a full line, a fixed buffer size or eof has been encountered.
-- It returns two values, a string (possibly empty) and a boolean indicating
-- if the connection is alive or not.
--
-- The write() function takes an indexed table or string as argument, and
-- returns the number of bytes written (short reads are possible) and a
-- boolean indicating if the output is alive or not.
--
-- @note: FIFOs that were created in the APPL_TEMP namespace will be unlinked
-- when the close method is called or when the table is garbage collected.
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
