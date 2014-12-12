-- storepush_video_context
-- @short: Render the current video context to an object, then push the context.
-- @outargs: contextind, newvid
-- @longdescr: The storepush/storepop category of functions are similar to the
-- regular push/pop context functions with the addition that the new context
-- will contain an object with a screenshot of the previous context in its storage.
-- @group: vidsys
-- @cfunction: pushcontext_ext
-- @related: storepop_video_context, push_video_context, pop_video_context
function main()
#ifdef MAIN
	a = fill_surface(100, 100, 0, 255, 0);
	b = fill_surface(100, 100, 255, 0, 0);
	show_image({a, b});
	move_image(b, VRESW - 100, VRESH - 100);
	c = storepop_video_context();
	show_image(c);
	move_image(c, 50, 50, 50);
	move_image(c, 0,   0, 50);
#endif
end
