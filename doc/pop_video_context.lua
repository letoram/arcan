-- pop_video_context
-- @short: Deallocate the current video context.
-- @longdescr: All video objects are bound to (at least) one rendering context.
-- The currently active context is managed on a stack. Poping involves
-- deleting all video subsystem related resources currently bound to the active context.
-- @note: poping the outmost context is similar to deleting all allocated vids.
-- @group: vidsys
-- @cfunction: popcontext
-- @related: system_context_size, current_context_usage, push_video_context
function main()
#ifdef MAIN
	a = fill_surface(VRESW, VRESH, 0, 255, 0);
	show_image(a);
	pop_video_context(); -- a should disappear
	move_image(a, 0, 0); -- should yield a crash
#endif
end
