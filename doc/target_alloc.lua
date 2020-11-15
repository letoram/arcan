-- target_alloc
-- @short: Bind an external connection point or force-push a subsegment
-- @inargs: string:cpoint, function:callback
-- @inargs: string:cpoint, string:passkey, function:callback
-- @inargs: string:cpoint, string:passkey, int:w, int:h, function:callback
-- @inargs: string:cpoint, int:w, int:h, function:callback
-- @inargs: vid:fsrv
-- @inargs: vid:fsrv, function:callback
-- @inargs: vid:fsrv, int:w, int:h, function:callback
-- @inargs: vid:fsrv, function:callback, string:type
-- @inargs: vid:fsrv, function:callback, number:tag
-- @inargs: vid:fsrv, int:w, int:h, function:callback, string:type
-- @inargs: vid:fsrv, int:w, int:h, function:callback, string:type, bool:forced
-- @outargs: vid:new_vid, aid:new_aid, int:new_cookie
-- @longdescr: This functions controls server-side initiated allocation of segments or connection
-- points. If the initial argument is of the *cpoint* form, the allocation will be a
-- named connection point to which a client can connect.
-- If the initial argument is of the *fsrv* form, a subsegment will be allocated and
-- pushed to the client. This form is more specialised and intended as a server-side
-- means of requesting and probing for client- side support for alternate views of
-- whatever the *fsrv* connection current presents. This can be further specified
-- by providing a *type* (debug, accessibility) and if a backend implementation
-- should be forced or not (default=false).
-- The form and use for *callback* is the same as in ref:launch_target, please
-- refer to that function for detailed documentation.
-- The optional *passkey* form is an aditional authentication string that the
-- connecting client is expected to be able to authenticate against in a platform
-- defined function, typically as a simple string comparison or challenge-response
-- and is not intended as a strong means of authentication. For such cases, the
-- ref:launch_target mechanism combined with the target/configuration database
-- is preferred, as only the connection itself will be authenticated, the contents
-- can still be subject to interception and tampering by a local attacker.
-- @note: To push new output segments,
-- see ref:define_recordtarget, ref:define_nulltarget and ref:define_feedtarget.
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
-- about the current surface dimensions and density)
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
