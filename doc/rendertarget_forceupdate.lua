-- rendertarget_forceupdate
-- @short: Manually perform an out-of-loop update of a rendertarget 
-- @inargs: vid
-- @longdescr: For short-lived rendertarget/calctarget calls it may 
-- be inconvenient to let the engine schedule the job and defer destruction.
-- For those settings, a manual forceupdate can be issued for more fine-grained
-- life-cycle control.
-- @note: Passing a vid that is not a rendertarget is considered a terminal
-- state transition.
-- @group: targetcontrol 
-- @cfunction: rendertargetforce
-- @related:
function main()
#ifdef MAIN
	local dst = fill_surface(320, 200, 0, 0, 0, 320, 200);
	local a = color_surface(64, 64, 0, 255, 0);
	show_image(a);
	rotate_image(a, 45);
	define_rendertarget(dst, {a}, RENDERTARGET_DETACH, RENDERTARGET_SCALE);
	rendertarget_forceupdate(dst);
	save_screenshot(dst, "test.png");
	delete_image(dst);
#endif

#ifdef ERROR1
	local a = fill_surface(32, 32, 255, 0, 0, 0);
	rendertarget_forceupdate(a);
#endif
end
