-- image_color
-- @short: Change color_surface and rendertarget clear-color
-- @inargs: vid, red, green, blue, *alpha*
-- @longdescr: The color_surface is a vid that lacks a textured
-- backing store and suffers some restrictions from that. It is
-- mainly intended for single-color or shader-defined color
-- surfaces that do not need to consume a texture- slot. Though
-- the color is defined at creation time, this function can be
-- used to update the color that is used for drawing.
-- If this function is used on a rendertarget, the clear-color
-- (default 0, 0, 0, 255) is changed for future rendertarget
-- updates. This is primarily needed in some edge-cases where
-- you want to create an output with a specific alpha value.
-- @outargs: true or false
-- @group: image
-- @cfunction: imagecolor
-- @related:
function main()
#ifdef MAIN
	local a = color_surface(64, 64, 255, 0, 0);
	show_image(a);
	image_color(a, 0, 255, 0);
#endif

#ifdef MAIN2
#endif

#ifdef ERROR
	image_color(BADID);
#endif
end
