-- rendertarget_forceupdate
-- @short: Manually perform an out-of-loop update of a rendertarget
-- @inargs: rendertarget, *newrate*
-- @outargs:
-- @longdescr: By default, rendertargets update synchronously with the
-- regular video refresh/redraw that is performed as part of the active
-- synchronization strategy combined with the refreshrate hinted during
-- creation. This function covers two use-cases. The first use case is
-- to force an out-of-loop update of the specified target in 'manual'
-- update mode (rate=0). The second use case is to change the rate-
-- value set for the target after creation in order. This can be used as
-- an optimization to temporarily disable rendertargets without going
-- through the process of rebuilding and migrating between rendertargets.
-- Any pending counters/timers for frame or tick/based automatic updates
-- will be reset, and the update includes synchronizing with readback in
-- the case of calctargets and recordtargets.
-- @note: Trying to call this function on a VID that references an object
-- that is not flagged as a rendertarget is a terminal state transition.
-- @note: If a newrate is set, the rendertarget will not be updated
-- directly. If that behaviour is desired, call the function again without
-- the newrate argument.
-- @group: targetcontrol
-- @cfunction: rendertargetforce
-- @related: define_rendertarget, define_calctarget, define_recordtarget
function main()
#ifdef MAIN
	local dst = alloc_surface(320, 200);
	local a = color_surface(64, 64, 0, 255, 0);
	show_image(a);
	rotate_image(a, 45);
	define_rendertarget(dst, {a});
	rendertarget_forceupdate(dst);
	save_screenshot("test.png", FORMAT_PNG, dst);
	delete_image(dst);
#endif

#ifdef ERROR
	local a = fill_surface(32, 32, 255, 0, 0, 0);
	rendertarget_forceupdate(a);
#endif
end
