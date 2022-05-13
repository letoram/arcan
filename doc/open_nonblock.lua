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
-- FIFO (<) or a SOCKET (=). Unless a namespace is explicitly set and the
-- namespace is marked as valid for IPC, FIFOs and SOCKETs will be created
-- in the RESOURCE_APPL_TEMP namespace.
-- If the string starts with a valid namespace identifier and separator
-- (alphanum:/)  the identifier will first be matched to a user defined
-- namespace (see ref:list_namespaces).
-- If successful, FIFOs and normal resources return a table wih a close
-- operation (which is activated on garbage collection unless called in
-- beforehand) and a read or write function depending on the mode that
-- the resource was opened in.
-- The socket table is special in that it allows multiple connections.
-- the initial table for a socket only has a close and an accept function.
-- The accept function takes no arguments and returns a table in both read
-- and write mode when there is a client waiting.
--
-- The read(bool:nobuf, [arg]):str,bool function takes one optional argument,
-- *nobuf* which disables local buffering. The default behavior of the read
-- function is otherwise to buffer until a full line, a fixed buffer size or
-- eof has been encountered.  It returns two values, a string (possibly empty)
-- and a boolean indicating if the connection or file is still alive or not.
-- It also supports two optional reading modes that are more convenient and
-- faster than multiple calls to read.
-- If [arg] is a lua function, it will be invoked as a callback(str:line,
-- bool:eof) with each line in the current buffer along with information (eof)
-- if the backing data store is still connected and has more data that
-- could be read or arrive in the future (sockets, pipes) or not.
-- If [arg] is a table, it will be treated as n indexed and new lines will be
-- appending at the end of the table [#tbl+1] = line1; [#tbl+2] = line2; and so
-- on.
--
-- The lf_strip(bool) function affects read results to include or exclude a
-- splitting linefeed if operating in linefeed mode. This is mainly an
-- optimization to avoid additional string manipulation when linefeeds aren't
-- desired in the resulting string.
--
-- The write(buf, [callback(ok, gpublock)]):int,bool function takes a buffer string
-- or table of buffer strings as argument and queues for writing.
-- If a callback is provided, it will be triggered if writing encounters a
-- terminal state or all queued writes have been completed.
-- Multiple subsequent write calls will add buffers to the queue, and the last
-- provided callback will be the only one to fire.
-- The callback form can also fail (returns 0, false) if the number of polled data
-- sources exceed some system bound or if the source is not opened for writing.
--
-- The queue processing status can be queried through the
-- outqueue():count,queue with the returned count being accumulated bytes in
-- total, and queue the current remaining queued bytes. These counters are
-- flushed when the queue has finished processing and the callback is invoked.
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
-- Some files support absolute and/or relative seeking. For relative seeking
-- based on the current file position, call :seek(ofs):bool,int. To set an
-- absolute file position, call set_position(pos):bool,int with negative values
-- being treated as the offset from file end. Both forms return if the seek
-- succeeded and the last known absolute file position.
--
-- @note: Do note that input processing has soft realtime constraints, and care
-- should be taken to avoid processing large chunks of data in one go as it may
-- affect application responsiveness.
-- @note: FIFOs that were created will be unlinked when the close method is
-- called or when the table reference is garbage collected.
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
