-- hide_image
-- @short: Alias for show_image(vid, 0.0, *time)
-- @alias: show_image
function main()
#ifdef MAIN
	hide_image(WORLDID);
#endif

#ifdef ERROR
	hide_image(-1);
#endif
end
