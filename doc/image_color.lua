-- image_color
-- @short: Change color_surface and rendertarget clear-color
-- @inargs: vid:dst, number:red, number:green, number:blue
-- @inargs: vid:dst, number:red, number:green, number:blue, number:alpha
-- @longdescr: There are two uses for this function. The first is
-- that it can be used to update the current color that a ref:color_surface
-- uses as the color value passed to the shader.
-- The second is that each rendertarget, including the one hidden
-- behind WORLDID has a clear color which is the default 'background'
-- color. This initialises to 25, 25, 25, (255) which is a dark grey
-- value, but can be updated via the use of this function.
-- @note: trying to set this on a non-rendertarget, textured surface
-- is a terminal state transition.
-- @outargs: true or false
-- @group: image
-- @cfunction: imagecolor
-- @related: color_surface, define_rendertarget
function main()
#ifdef MAIN
	local a = color_surface(64, 64, 255, 0, 0);
	show_image(a);
	image_color(a, 0, 255, 0);
#endif

#ifdef MAIN2
	image_color(WORLDID, 255, 0, 0, 0);
#endif

#ifdef ERROR
	image_color(BADID);
#endif

#ifdef ERROR2
	local img = fill_surface(64, 64, 0, 0, 0);
	image_color(img, 255, 0, 0, 0);
#endif
end
