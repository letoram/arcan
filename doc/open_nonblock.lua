-- open_nonblock
-- @short: Open a file in read or write mode for non-blocking I/O.
-- @inargs: string:res
-- @inargs: string:res, bool:write
-- @inargs: vid:res
-- @inargs: vid:res, bool:write
-- @inargs: vid:res, bool:write, string:identifier=stream
-- @outargs: blocktbl
-- @longdescr: Create or open the resource indicated by *res* in (default)
-- read-mode or (if *mode* is provided, write mode)
-- If *res* is a vid connected to a frameserver, a streaming fifo session will
-- be set up over the connection along with the corresponding _BCHUNK events.
-- The *identifier* argument can then be used to specify some client announced
-- type identifier, or one of the reserved "stdin", "stdout", "stderr".
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
-- The read(bool:nobuf):str,bool function takes one optional argument, *nobuf*
-- which disables local buffering. The default behavior of the read function is
-- otherwise to buffer until a full line, a fixed buffer size or eof has been
-- encountered.  It returns two values, a string (possibly empty) and a boolean
-- indicating if the connection or file is still alive or not.
--
-- The write(buf, [callback(ok, gpublock)]):int,bool function takes a buffer string as
-- argument, and returns the number of bytes written (short writes are possible)
-- and a boolean indicating if the output is still alive or not.
-- If a callback is provided the write will be queued, and the callback triggered
-- if writing encounters a terminal state or all queued writes have been completed.
-- Multiple subsequent write calls will add buffers to the queue, and the last
-- provided callback will be the only one to fire.
-- The callback form can also fail (returns 0, false) if the number of polled data
-- sources exceed some system bound or if the source is not opened for writing.
--
-- The data_handler(callback(gpublock)):bool function sets a callback that will
-- be invoked when the descriptor becomes available for reading. This will only
-- fire once, and need to be re-armed by setting a new data_handler. This can
-- fail if the number of polled data sources exceed some system bound, but
-- there is at least one slot for data_handler calls.
--
-- The gpublock argument in both *write* and *data_handler* indicates if the
-- callback is triggered from a state where calls that would alter graphics
-- pipeline state are permitted or would trigger undefined behaviour. This is
-- likely to be set as the scheduler will try to defer I/O operations to when
-- it is blocked on rendering or scanning out to a display.
--
-- @note: Do note that input processing has soft realtime constraints, and care
-- should be taken to not process large chunks of data in one go as it may
-- affect responsiveness.
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

#ifdef MAIN2
function main()
	a = open_nonblock("=test", false)
	b = open_nonblock("=test", true)

-- our reader, note the scoping and the closure here
	local counter = 20
	local dh
	dh =
	function()
		local res, alive = a:read()
		if res then
			print("read:", res)
			counter = counter - 1
			if alive and counter > 0 then
				a:data_handler(dh)
				return
			end
		end

		a:close() -- will close on error or if counter reaches 0
	end

	a:data_handler(dh)
end

function main_clock_pulse()
	if CLOCK % 100 == 0 then
		local _, alive = b:write("sent at " .. tostring(CLOCK))
		if not alive then
			return shutdown()
		end
	end
end
#endif
