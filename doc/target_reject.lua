-- target_reject
-- @short: Notify a frameserver that the request for
-- an additional segment was rejected.
-- @inargs: vid, *reqid*
-- @longdescr: A frameserver can send out a request for
-- a new input or output segment through an event with
-- the 'kind' field set to segment_request and a reqid.
-- It is then up to the script to respond by either allocating
-- a new segment through _target_alloc_ or refusing and
-- calling _target_reject_.
-- @group: targetcontrol
-- @cfunction: targetreject
-- @related:
function main()
#ifdef MAIN
#endif

#ifdef ERROR
#endif
end
