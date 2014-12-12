-- storepop_video_context
-- @short: Render the current video context to an object, then pop the context.
-- @outargs: contextind, newvid
-- @longdescr: The storepush/storepop category of function are similar to
-- the regular push/pop context functions with the addition that the new context
-- will contain an object with a screenshot of the previous context in its storage.
-- @note: if the underlying context is fully allocated, the function will
-- return BADID, the pop operation will, however, suceed.
-- @note: this is a reasonably costly operation and relies on using the
-- screenshot function into a temporary buffer which is then used as input to
-- rawobject.
-- @group: vidsys
-- @cfunction: popcontext_ext
-- @related: pop_video_context, push_video_context, storepush_video_context
function main()
#ifdef MAIN
	a = fill_surface(100, 100, 0, 255, 0);
	show_image(a);
	b = storepop_video_context();
	show_image(b);
	print(valid_vid(a), valid_vid(b));
#endif
end
