-- expire_image
-- @short: 
-- @inargs: 
-- @outargs: 
-- @longdescr: 
-- @group: image 
-- @cfunction: arcan_lua_setlife
-- @related: delete_image
-- @flags: 
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	expire_image(a, 100);
#endif

#ifdef ERROR1
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

