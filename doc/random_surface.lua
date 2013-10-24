-- random_surface
-- @short:    
-- @inargs: width, height 
-- @outargs: vid 
-- @longdescr: Generate a simple high- frequency 1D noise texture packed in a
-- RGBA surface with an "always one" alpha channel.
-- @group: image 
-- @flags: deprecated
-- @cfunction: arcan_lua_randomsurface
function main()
#ifdef MAIN
	a = random_surface(256, 256);
	show_image(a);
#endif
end
