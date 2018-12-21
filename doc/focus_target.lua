-- focus_target
-- @short: Specify a frameserver the scheduler should try and bias
-- @inargs:
-- @inargs: vid:WORLDID
-- @inargs: vid:fsrv
-- @outargs:
-- @longdescr: Some synchronisation strategies might rely on a focus target,
-- some external process to bias in favor of. In such cases, the specific target
-- has to be pointed out by the scripts themselves as the engine has no direct
-- way of knowing which client has visual focus and so on.
-- This function can be used to set such an object.
-- Calling the function without any arguments or with WORLDID as argument will
-- remove any existing bias focus. Should the frameserver expire, the bias will
-- be removed implicitly.
-- @note: calling the function with a vid that is not tied to a frameserver
-- is a terminal state transition.
-- @group: targetcontrol
-- @cfunction: targetfocus
-- @related:
function main()
#ifdef MAIN
	local vid =
		target_alloc("test", function(source, status)
		end);
	if (valid_vid(vid, TYPE_FRAMESERVER)) then
		focus_target(vid);
	end
#endif

#ifdef ERROR1
	focus_target(BADID);
#endif

#ifdef ERROR2
	local vid = null_surface(32, 32);
	focus_taget(BADID);
#endif
end
