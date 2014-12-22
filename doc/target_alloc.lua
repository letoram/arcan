-- target_alloc
-- @short: Setup a subsegment or external connection
-- @inargs: key or vid, [passcode], callback, [tag]
-- @outargs: vid, aid
-- @longdescr: By default, frameserver connections are single-segment and
-- authoritative, meaning that they can only be explicitly created and
-- setup by a user through the related functions (net_open, load_movie, ...)
-- and that they are either input (provides data to arcan) or output
-- (receive datastreams from arcan for purposes such as recording).
-- target_alloc is then used to attach additional input segments
-- to a pre-existing frameserver connection (by specifying the vid of said
-- frameserver). When communicating these segments, it is also possible to
-- specify a *tag* (default: 0) which should correspond to the tag value
-- in an segment_request kind target event in a frameserver callback.
-- target_alloc is also used to allow non-authoritative connections that
-- follow a more traditional client server model. By specifying a
-- key string, a listening connection is prepared in a shared namespace (OS
-- dependent). By specifying ARCAN_CONNPATH (and optionally, a verification
-- passcode in ARCAN_CONNKEY) a program that uses the arcan_shmif interface
-- (e.g. the default frameservers) can connect and be treated like any
-- other frameserver.
-- @note: To allocate new output segments, see define_recordtarget.
-- @note: Each call that allows a non-authoritative connection is only valid
-- once, if a connection fail to verify OR a connection is completed,
-- the connection point will be removed.
-- @note: The first example below will continuously listen for new connections
-- under the 'nonauth' connection path. In a real-world setting, be sure to
-- restrict the number of allowed connections to avoid running out of resources
-- and to monitor for suspicious activities e.g. a high amount of connections
-- or connection attempts in a short timeframe etc.
-- @note: for honoring explicit requests from a frameserver, use
-- the accept_target function.
-- @group: targetcontrol
-- @cfunction: targetalloc
-- @related: define_recordtarget, accept_target
function main()
#ifdef MAIN
	local chain_call = function()
		target_alloc("nonauth", function(source, status)
			print(source, status.kind);
			chain_call();
		end);
	end
#endif

#ifdef ERROR
	local a = fill_surface(32, 32, 255, 0, 0, 0);
	target_alloc(a, function(source, status)
	end);
#endif

#ifdef ERROR2
	vid = net_listen();
	target_alloc(vid, target_alloc);
#endif
end
