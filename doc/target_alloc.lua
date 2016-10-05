-- target_alloc
-- @short: Setup a subsegment or external connection
-- @inargs: key or vid, [passcode], callback, [tag or type]
-- @outargs: vid, aid
-- @longdescr: By default, frameserver connections are single-segment and
-- authoritative, meaning that they can only be explicitly created and
-- setup by a user through the related functions (net_open, launch_target, ...)
-- and that they are either input (provides data to arcan) or output
-- (receive datastreams from arcan for purposes such as recording).
-- target_alloc is then used to attach additional input segments
-- to a pre-existing frameserver connection (by specifying the vid of said
-- frameserver). When communicating these segments, it is also possible to
-- specify a *tag* (default: 0) which should correspond to the tag value
-- in an segment_request kind target event in a frameserver callback, or
-- a *type* with a string that matches any of the possible subsegment
-- types from the list: (debug, accessibility). Both of tag/type are
-- primarily for specialized applications, and the accept_target
-- mechanism should be preferred for other types.
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
-- @note: The connection key is limited to 30 characters from the set [a-Z,_0-9]
-- and the actual search path / mechanism is implementation defined.
-- @note: The first example below will continuously listen for new connections
-- under the 'nonauth' key. In a real-world setting, be sure to
-- restrict the number of allowed connections to avoid running out of resources
-- and to monitor for suspicious activities e.g. a high amount of connections
-- or connection attempts in a short timeframe etc.
-- @note: The connection point is consumed (closed, unlinked) when the
-- first verified connection goes through. To re-use the connection point,
-- invoke target_alloc again with the same key from within the callback handler.
-- @note: for honoring explicit requests from a frameserver regarding new
-- subsegments, use the accept_target function.
-- @note: When a 'connected' event has been received, many applications
-- expect a displayhint event before being able to proceed (with information
-- about the current surface dimensions and density).
-- @group: targetcontrol
-- @cfunction: targetalloc
-- @related: define_recordtarget, accept_target
function main()
#ifdef MAIN
	local chain_call = function()
		target_alloc("nonauth", function(source, status)
			print(source, status.kind);
			if (status.kind == "connected") then
				chain_call();
			end
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
