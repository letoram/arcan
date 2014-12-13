-- expire_image
-- @short: Schedule the image for deletion
-- @inargs: vid, timetolive
-- @longdescr: For some images, we want to specify not only that it should
-- be deleted but when (often in conjunction with how the transformation
-- chain is currently running) without tracking time in other means. This
-- function allows you to specify how many ticks the image has left to live.
-- @note: for n : 0 <= n < 1, n will be forced to one tick.
-- the timer to the new value.
-- @group: image
-- @cfunction: setlife
-- @related: delete_image
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	expire_image(a, 100);
#endif

#ifdef ERROR
	expire_image(WORLDID, 10);
#endif

#ifdef ERROR2
	a = fill_surface(32, 32, 0, 255, 0);
	expire_image(a, -1);
#endif

#ifdef ERROR3
	a = fill_surface(32, 32, 0, 0, 255);
	expire_image(a, "deadline");
#endif
end

