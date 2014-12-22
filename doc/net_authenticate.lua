-- net_authenticate
-- @short: Elevate the privilege level of the specific client connection.
-- @inargs: connid, *level*
-- @outargs: nil
-- @longdescr: For assymetric encryption, there must be
-- some way to determine that the public key in use belongs
-- to the person on the other end. Since there is no explicit
-- support for certificate chains or other PKI, it is expected
-- that the script or user can ascertain the identity
-- that the certificate corresponds to.
-- When such a connection has been established, this
-- function should be called to alter the privilege level
-- (an unauthenticated session cannot, for instance,
-- transfer frameserver- states.
-- @note: the exact semantics of each authentication level
-- is not yet established.
-- @note: setting connid to 0 is a terminal state transition.
-- @group: network
-- @cfunction: net_authenticate
function main()
#ifdef MAIN
#endif
#ifdef ERROR
#endif
end
