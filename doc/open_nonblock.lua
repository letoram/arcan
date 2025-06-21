-- open_nonblock
-- @short: Open a file in read or write mode for non-blocking I/O.
-- @inargs: vid:res
-- @inargs: vid:res, bool:write
-- @inargs: vid:res, bool:write, string:identifier=stream
-- @inargs: vid:res, bool:write, string:identifier=stream, userdata:nbioud
-- @inargs: vid:res, table:opts, string:identifier=stream
-- @inargs: vid:res, table:opts, string:identifier=stream, userdata:nbioud
-- @inargs: string:res
-- @inargs: string:res, bool:write
-- @outargs: blocktbl
-- @longdescr: Create or open the resource indicated by *res* in (default)
-- read-mode or (if *mode* is provided, write mode)
--
-- If *res* is a vid connected to a frameserver, either a streaming fifo
-- session will be set up over the connection along with the corresponding
-- _BCHUNK events or an pre-existing nonblock-io stream, *nbioud*, will be
-- redirected to said client and the backing descriptor closed locally.
--
-- The *identifier* argument can then be used to specify some client announced
-- type identifier, or one of the reserved "stdin", "stdout", "stderr".
--
-- If *res* is a string, the initial character determines if it creates a
-- FIFO (<) or a SOCKET (=). Unless a namespace is explicitly set and the
-- namespace is marked as valid for IPC, FIFOs and SOCKETs will be created in
-- the RESOURCE_APPL_TEMP namespace. For sockets, the *write* argument
-- determines if the connection should be outbound (=true) or listening
-- (=false).
--
-- If the *identifier* starts with a valid namespace identifier and separator
-- (alphanum:/)  the identifier will first be matched to a user defined
-- namespace (see ref:list_namespaces).
--
-- If the *res* is connected to a frameserver, the namespace identifier is
-- fixed and only defined for connections coming from ref:net_open. The
-- default is to target the private store of the authenticated client. To
-- let the server side controller script decide, prefix the *identifier*
-- with appl:/
--
-- If successful, FIFOs and normal resources return a table wih a close
-- operation (which is activated on garbage collection unless called in
-- beforehand) and a read or write function depending on the mode that
-- the resource was opened in.
--
-- The socket table is special in that it allows multiple connections.
-- the initial table for a socket only has a close and an accept function.
-- The accept function takes no arguments and returns a table in both read
-- and write mode when there is a client waiting.
--
-- The *opts* table argument form is used to tune transfer parameters.
--
-- @tblent: bool:write - same as the 'write' argument form, stream will be
--          for output only.
--
-- @tblent: bool:streaming - indicate that the transfer will be clocked to
--          decoding the contents, typically when routed to another client.
--          This is mainly useful for when *res* is a vid reference to a
--          network connected frameserver coming from *net_open* where one
--          transfer otherwise will block future ones until completed.
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
-- The bgcopy(nbio:dst) function assumes the called table is in read mode and
-- the *dst* argument is in write mote. It returns a new progress nonblock
-- userdata and both the source and *dst* are disconnected from their bound
-- descriptors. Internally it spawns a copy thread which copies data from
-- source to dst until eof or error. The returned nonblock state can be read to
-- get progress on the copy operation. The lines read from the the returned
-- progress are colon separated "last_read:accumulated:total" with last-read is
-- the number of bytes processed since the previous report, accumulated the
-- number of bytes processed and total the estimated total (unless the source
-- is streaming). The backing descriptors are closed when the job is completed.
--
-- The lf_strip(bool) function affects read results to include or exclude a
-- splitting linefeed if operating in linefeed mode. This is mainly an
-- optimization to avoid additional string manipulation when linefeeds aren't
-- desired in the resulting string. It is also possible to pass lf_strip(bool,
-- str) where the first character of the string will be used to determine end
-- of line. This can be used to manage '\0' separated sequenced strings.
--
-- The write(buf, [callback(ok, gpublock)]):int,bool function takes a buffer string
-- or table of buffer strings as argument and queues for writing.
-- If a callback is provided, it will be triggered if writing encounters a
-- terminal state or all queued writes have been completed.
-- Multiple subsequent write calls will add buffers to the queue, and the last
-- provided callback will be the only one to fire.
-- The callback form can also fail (returns 0, false) if the number of polled data
-- sources exceed some system bound or if the source is not opened for writing.
-- If a table is provided, it is expected to be a pure n- indexed table of strings
-- with an optional 'suffix' key with string value to be appended to the output
-- of each table entry.
--
-- The queue processing status can be queried through the
-- outqueue():count,queue with the returned count being accumulated bytes in
-- total, and queue the current remaining queued bytes. These counters are
-- flushed when the queue has finished processing and the callback is invoked.
--
-- The data_handler(callback(gpublock)):bool function sets a callback that will
-- be invoked when the descriptor becomes available for reading. This will only
-- fire once, and need to be re-armed by setting a new data_handler or
-- returning true in the handler. This can fail if the number of polled data
-- sources exceed some system bound, but there is at least one slot for
-- data_handler calls.
--
-- The gpublock argument in both *write* and *data_handler* indicates if the
-- callback is triggered from a state where calls that would alter graphics
-- pipeline state are permitted or would trigger undefined behaviour. This is
-- likely to be set as the scheduler will try to defer I/O operations to when
-- it is blocked on rendering or scanning out to a display. If processing the
-- data would cause modifications to the rendering pipeline state, it should
-- then be buffered and handled in the preframe_pulse event handler.
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
-- @note: FIFOs and sockets that were created will be unlinked when the close
-- method is called or when the table reference is garbage collected.
-- @note: When a nonblocking userdata is handed over to a frameserver, the
-- *write* argument will be ignored and the corresponding BCHUNK event will
-- match the userdata. This was a bug in a previous version where the write
-- argument was respected and the argument had to be kept to avoid breaking
-- compatibility.
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
