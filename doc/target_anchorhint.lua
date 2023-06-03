-- target_anchorhint
-- @short: Inform a target about its coordinates relative to a reference
-- @inargs: vid:tgt, int:type=ANCHORHINT_SEGMENT, int:parent, int:x, int:y, int:z
-- @inargs: vid:tgt, int:type=ANCHORHINT_EXTERNAL, int:parent, int:x, int:y, int:z
-- @inargs: vid:tgt, int:type=ANCHORHINT_PROXY, vid:src, int:parent, int:x, int:y, int:z
-- @inargs: vid:tgt, int:type=ANCHORHINT_PROXY_EXTERNAL, int:src, int:parent, int:x, int:y, int:z
-- @outargs:
-- @longdescr: While ref:target_displayhint can be used to provide additional
-- information about how a client will be presented, it does not carry
-- information about how it will be positioned within some reference frame.
-- This is not as useful since clients can already hint in the other direction
-- through viewport events.
--
-- The major exceptions are when one client is bridging to other windowing
-- systems (ANCHORHINT_PROXY, ANCHORHINT_PROXY_EXTERNAL),
-- acting as a window manager for nested/embedded subsegments (ANCHORHINT_SEGMENT)
-- or as an out-of-process external window manager (ANCHORHINT_PROXY).
-- *x* and *y* refers to the resolved upper-left corner position of the target,
-- and *z* the stacking or composition order.
--
-- In such cases target_anchorhint can be used. The type indicates which
-- reference objects that could be provided. If the type contains EXTERNAL the
-- *src* and *parent* arguments will be treated as an opaque externally
-- provided identifier, as with ref:target_displayhint and received through the
-- segment_request and viewport events.
--
-- The non-external types will have *src* and *parent* verified as valid
-- frameservers and the VIDs substitued for the respective cookie identifier
-- (see ref:launch_target). If no parenting relationship is required, use the
-- global WORLDID as reference. Pointing to an invalid VID is a terminal state transition.
--
-- @group: targetcontrol
-- @cfunction: targetdisphint
-- @related: target_displayhint, launch_target
function main()
#ifdef MAIN
#endif
end
