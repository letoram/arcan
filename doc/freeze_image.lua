-- freeze_image
-- @short: Tag object as freezed, the next attempt to access it will trigger a crash.
-- @inargs: vid
-- @longdescr: For debugging purpose, it can at times become frustrating
-- to figure out where and when an objects gets manipulated into an undesired
-- state. This function tags the object as frozen, and next time the object is accessed
-- across the VM barrier, execution is terminated and a dump is generated (logs/).
-- @group: system
-- @cfunction: freezeimage
-- @note: debug_only
function main()
#ifdef MAIN
	if (freeze_image == nil) then
		warning("Arcan must be compiled in debug mode for this function to work.");
		shutdown();
	else
		a = fill_surface(64, 64, 255, 255, 255);
		freeze_image(a);
		show_image(a); -- should yield a dump
	end
#endif
end
