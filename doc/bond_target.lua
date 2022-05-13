-- bond_target
-- @short: Setup a state transfer pipe between two targets.
-- @inargs: vid:source, vid:dest
-- @inargs: vid:source, vid:dest, bool:blob
-- @inargs: vid:source, vid:dest, bool:blob, string:identifier
-- @inargs: vid:source, vid:dest, bool:blob, string:id_source, string:id_dest
-- @outargs:
-- @longdescr: This function is used to setup a state transfer stream between
-- two targets. A pipe-pair is created with the write- end sent to *source* and
-- the read- end sent to *dest*. By default, the transfer target type is marked
-- as 'state', meaning that *dest* should replace its runtime state with that
-- of *source*. If the *blob* argument is set to true, then the transfer type
-- will be that of a opaque data blob, up to the *dest* to figure out what to
-- do with. The *identifier* is a short string matching a previously announced
-- extension or the reserved stdin, stdout or stderr names. If a single
-- identifier is sent it will be used for both *source* and *dest*, otherwise
-- *id_source* will be sent to *source* and *id_dest* sent to *dest*.
-- @group:
-- targetcontrol
-- @cfunction: targetbond
-- @related:
function main()
#ifdef MAIN
	local feed_1 =
	launch_avfeed("keep_alive:exec=ls /", "terminal",
		function(source, status)
		end
	)
	local feed_2 =
	launch_avfeed("keep_alive:exec=tee", "terminal",
		function(source, status)
		end
	)
	bond_target(feed_1, feed_2, true, "stdout", "stdin")
	local in = open_nonblock(feed_2, false)
#endif
end
