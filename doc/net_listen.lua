-- net_listen
-- @short: Setup a network frameserver in listening mode
-- @inargs: function:callback
-- @inargs: string:name, function:callback
-- @inargs: string:name, string:interface, function:callback
-- @inargs: string:name, string:interface, int:port, function:callback
-- @outargs: vid
-- @longdescr: Launch a new frameserver in networking server mode. The *callback* argument
-- behaves just like any other client connected through ref:target_alloc, ref:launch_avfeed
-- and so on. The key difference to ref:target_alloc is that clients are only allowed to
-- connect through whatever protocol the network frameserver exposes (typically a12).
--
-- The longer form accepts a *name* that has the same ([a-Z0-9_]1,30) restriction as
-- normal connection points. It will not be allocated in the domain socket namespace
-- and the name is only used to limit the set of accepted keys from the keystore that
-- are allowed to authenticate against the keystore.
--
-- Listening interface and port are implementation defined by default, but the long
-- form with *host* and *port* can be used to override this.
--
-- New clients are bootstrapped as 'handover' segments and thus needs to be
-- acknowledged via the use of ref:accept_target. See the example further below.
--
-- By using *target_input(vid, "num:secret")* immediately on the returned vid,
-- an extended authentication key can be set. This requires both a key authenticated
-- for use with *name* and the right secret for a connection to be let through.
--
-- If *num* is set to > 0 a limited number of unknown keys authenticated with
-- the shared secret will be added to the list of known and accepted keys for
-- *name* in the keystore. This opens a short window where man-in-the-middle
-- attacks against unknown keys could be used (assuming the shared secret can
-- be retrieved). The idea is to help bootstrap in controlled network
-- environments or where there is an established secure side-band communication
-- where the secret can be shared.
--
-- @note: terminating the listening vid will not immediately terminate any
-- clients that have been authenticated and given a handover segments, but
-- no new clients will be accepted.
--
-- @group: network
-- @cfunction: net_listen
-- @exampleappl: tests/interactive/nettest
-- @flags:
function main()
#ifdef MAIN
	net_listen(
	function(source, status)
		if status.kind == "segment_request" then
			accept_target(
				function(source, status)
					if status.kind == "terminated" then
						delete_image(source)
					else
						print("client", source, status.kind)
					end
				end
			)
		end

		if status.kind == "terminated" then
			shutdown(EXIT_SUCCESS)
		end
	end)
end
#endif
