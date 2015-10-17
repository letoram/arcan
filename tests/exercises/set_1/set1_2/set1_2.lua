function set1_2(arguments)
	if (#arguments ~= 1) then
		return shutdown("missing argument, filename (images/icons/arcanicon.png)")
	end

	if (not resource(arguments[1])) then
		return shutdown("couldn't find resource (" .. arguments[1] .. ")")
	end

	local img = load_image(arguments[1]);
	if (not valid_vid(img)) then
		return shutdown("couldn't load image (" ..arguments[1] .. ")")
	end

	show_image(img);
end
