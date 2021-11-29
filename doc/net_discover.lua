-- net_discover
-- @short: Probe or monitor for compatible hosts or clients on the network
-- @inargs: function:callback
-- @inargs: int:mode, int:trust, function:callback
-- @inargs: int:mode, int:trust, string:description, function:handler(source, status)
-- @outargs:
-- @longdescr: this function is used to find other sources or sinks on the network
-- which implement the a12 protocol. Each time a connection is discovered, the
-- *callback* function is invoked with whatever that could be discerned.
--
-- The short argument form uses whatever implementation defined default detection
-- mechanism that is available, with the TRUST_KNOWN level of trust.
-- For more refined control, the *mode* argument can  be set to one of the following:
-- DISCOVER_PASSIVE, DISCOVER_SWEEP, DISCOVER_BROADCAST, DISCOVER_DIRECTORY.
--
-- DISCOVER_PASSIVE silently listens on available network interfaces (or ones
-- specified through the *description* argument) for broadcasting clients.
--
-- DISCOVER_BROADCAST periodically announces its presence in a privacy
-- preserving way, assuming that the trust model is set to TRUST_KNOWN.
--
-- DISCOVER_SWEEP cycles through the set of trusted keys, looking for the first
-- possible host for each keyset. The *description* arguments accepts a
-- delay=n:period=m form where the delay is a number in seconds between each
-- attempted keyset, and period delay in seconds between sweeps.
--
-- DISCOVER_DIRECTORY uses a directory service to discover which ones are
-- currently available. This mode can punch through NATed networks and is
-- suitable for wide-area network use where you have access to a remote trusted
-- server.
--
-- the *trust* argment changes how the discover modes based on a specified trust
-- model, which can be one of the following:
-- TRUST_KNOWN, TRUST_PERMIT_UNKNOWN, TRUST_TRANSITIVE.
--
-- TRUST_KNOWN will only forward and reply to messages that comes from
-- previously known and trusted sources. Known sources are managed through an
-- external keystore, see the arcan-net tool.
--
-- TRUST_PERMIT_UNKNOWN (for broadcast, passive and directory) allows
-- interactive verification whether a certain connection should be trusted or
-- not.
--
-- TRUST_TRANSITIVE (for directory) allows viewing and temporary or permanentily
-- trusting connections that comes from an intermediary dictionary server.
--
-- The callback *handler* provides the source vid as well as a status table.
-- This behaves similar to other ref:launch_target style callbacks. The set of
-- useful events is reduced to kind=terminated, and kind=state as the ones
-- of relevance.
--
-- @tblent: "state" {string:name, string:namespace, bool:lost, bool:discovered,
-- bool:bad, bool:source, bool:sink, bool: directory}. Name is a user-presentable
-- identifier for the network resource that has changed state. The
-- interpretation of name is governed by the namespace (tag, basename, subname,
-- ipv4, ipv6, a12pub). Tag is a user-defined entry in the local keystore, while
-- basename/subname is a breakdown of components in a fully qualified domain
-- name. Multiple events may be used to provide a complete reverse entry:
-- basename.basename.subname (com.example.local) and is terminated with an
-- zero-length base- or subname. A12pub is a bit special in the sense that it
-- provides the public key for a previously unknown a12 connection.
-- The (source, sink and directory) states describe capabilities of the node at
-- the other end and if neither are set, the capabilities could not be derived
-- from the detection method. A source can provide an application, a sink
-- expects one, and a directory act as a 3rd party trust and state store for
-- DISCOVER_DIRECTORY with TRUST_TRANSITIVE.
-- The (lost, discovered, bad) states describes transitions, a name can appear
-- as either discovered or bad. A discovered name can later be lost.
--
-- @note: specifying an invalid value for *trust* or *mode* is a terminal state
-- transition.
-- @group: network
-- @cfunction: net_discover
-- @related:
function main()
#ifdef MAIN
	net_discover(
	function(source, status)
		if status.kind == "terminated" then
			delete_image(source)
		elseif status.kind == "found" then
			print("discovered", status.trusted, status.tag, status.host)
			if not status.trusted then
				return false
			end
		elseif status.kind == "lost" then
			print("lost", status.tag)
		end
	end
	)
#endif

#ifdef ERROR1
#endif
end
