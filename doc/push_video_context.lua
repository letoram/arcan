-- push_video_context
-- @short: Store the current video context and make it unreachable.
-- @longdescr: All video objects are bound to (at least) one rendering context.
-- The currently active context is managed on a stack. Pushing involves
-- saving the current context on a stack, possibly deallocating data that
-- can be reloaded or regenerated.
-- @group: vidsys
-- @cfunction: pushcontext
-- @related: pop_video_context, storepop_video_context, storepush_video_context
function main()
#ifdef MAIN
	QSZ = math.floor(VRESW * 0.5);
	a = fill_surface(QSZ, 255, 0, 0);
	b = load_image("test.png");
	c = load_movie("test.avi", FRAMESERVER_LOOP, function(s, state)
		if (state.kind == "resized") then
			play_movie(c);
		end
	end);

	resize_image({b, c}, QSZ, QSZ);
	show_image({a, b, c});
	move_image(b, QSZ, 0);
	move_image(c, 0, QSZ);

	push_video_context();
	pop_video_context();
#endif
end
