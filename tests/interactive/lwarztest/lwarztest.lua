function lwarztest()
	in_red = true;
	col = color_surface(VRESW, VRESH, 255, 0, 0);
	show_image(col);
end

VRES_AUTORES = function(w, h, vppcm, flags, source)
	in_red = not in_red;
	image_color(col, in_red and 255 or 0, in_red and 0 or 255, 0);
	resize_image(col, w, h);
	move_image(col, 0, 0);
end
