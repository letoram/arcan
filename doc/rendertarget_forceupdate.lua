-- rendertarget_forceupdate
-- @short: Manually perform an out-of-loop update of a rendertarget
-- @inargs: rendertarget
-- @outargs:
-- @longdescr: By default, rendertargets update synchronously with the
-- regular video refresh/redraw that is performed as part of the active
-- synchronization strategy. For rendertargets that has a customised
-- refresh-rate or that need to be managed outside this cycle due to
-- a temporary life-span or similar need, this function can be used to
-- force a separate renderpass of the specified rendertarget. This will
-- also include possible readbacks, in the case of ref:define_calctarget
-- and ref:define_recordtarget. Any pending counters/timers for frame/
-- or tick based automatic updates will be reset.
-- @note: Trying to call this function on a VID that references an object
-- that is not flagged as a rendertarget is a terminal state transition.
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
