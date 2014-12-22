-- net_disconnect
-- @short: Disconnect the specific connection or domain- ID.
-- @inargs: connid
-- @outargs:
-- @longdescr: Misbehaving users or resource contraints may force a server to
-- disconnect one or several clients. The special IDs (0, 1..level) targets
-- all connection or all connections with a certain level of authentication.
-- @group: network
-- @cfunction: net_disconnect
-- @flags: experimental
-- @related: net_accept, net_authenticate
function main()
#ifdef MAIN
#endif
#ifdef ERROR
#endif
end
