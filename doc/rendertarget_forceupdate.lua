-- rendertarget_forceupdate
-- @short: Manually perform an out-of-loop update of a rendertarget
-- @inargs: vid:rendertarget
-- @inargs: vid:rendertarget, bool:force_dirty=false
-- @inargs: vid:rendertarget, number:refresh
-- @inargs: vid:rendertarget, number:refresh, number:readback
-- @inargs: vid:rendertarget, number:refresh, number:readback, bool:allow_hw=false
-- @outargs:
-- @longdescr: By default, rendertargets update synchronously with the
-- regular video refresh/redraw that is performed as part of the active
-- synchronization strategy combined with the refreshrate hinted during
-- creation.
--
-- The two argument forms (bool or number) follow a single rule: pass any
-- truthy value as the second argument to request an update. Numbers are
-- truthy, so passing 1 will force an out-of-loop update for rendertargets
-- in manual mode; passing 0 disables the forced update. The bool form is
-- preserved as a synonym for backwards compatibility.
--
-- For the rate-change use case, the same number argument also adjusts
-- the rendertarget refresh and readback rates -- temporarily disabling
-- rendertargets without rebuilding/migrating is a side effect of the
-- unified call, not a separate code path.
--
-- Any pending counters/timers for frame or tick/based automatic updates
-- will be reset, and the update includes synchronizing with readback in
-- the case of calctargets and recordtargets.
--
-- If *allow_hw* is set to true, the readback performed will instead be used to
-- share the buffer of the rendertarget with the assigned sink. This has
-- complex effects on the underlying graphics stack and may fail. If a failure
-- can be detected it will automatically switch back to a software only
-- approach (allow\_hw=false), but it can also fail without warning.
--
-- @note: Trying to call this function on a VID that references an object
-- that is not flagged as a rendertarget is a terminal state transition.
--
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
	rendertarget_forceupdate(dst, 1);
	save_screenshot("test.png", FORMAT_PNG, dst);
	delete_image(dst);
#endif

#ifdef ERROR
	local a = fill_surface(32, 32, 255, 0, 0, 0);
	rendertarget_forceupdate(a);
#endif
end
