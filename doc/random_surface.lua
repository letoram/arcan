-- random_surface
-- @short: Generate a pseudo-random image surface.
-- @inargs: width, height
-- @outargs: vid
-- @longdescr: Generate a simple high- frequency 1D noise texture packed in a
-- RGBA surface with an "always one" alpha channel.
-- @group: image
-- @note: In its current form, it merely wraps random() calls which is not
-- particularly useful for graphics purposes in contrast to more controllable
-- ones (e.g. Perlin Noise), future revisions to this function will include
-- a specifiable noise function and parameters.
-- @cfunction: arcan_lua_randomsurface
function main()
#ifdef MAIN
	a = random_surface(256, 256);
	show_image(a);
#endif
end
